#!/usr/bin/env ruby
# encoding: UTF-8

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

SOURCE_ROOT = File.expand_path("..", __dir__)
SAFE_AUTHORITY_FIXTURE_PATHS = %w[
  AGENTS.md
  docs/aios/FOUNDER_DELEGATION_POLICY.md
  docs/aios/truth/project_state.yaml
  docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml
  docs/aios/tasks/P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET.yaml
].freeze
FORBIDDEN_P1_038_CONTRACT_PATH = "docs/aios/tasks/P1-038_MINIMAL_HIDDEN_ADMISSION_PARAMETERIZED_HARNESS_IMPLEMENTATION.yaml"
FORBIDDEN_P1_038_CONTRACT_OID = "4ca0a67bef37fd55dc6db18f3190d94876d00221"

def run!(*command, chdir: nil)
  stdout, stderr, status = if chdir
    Open3.capture3(*command, chdir: chdir)
  else
    Open3.capture3(*command)
  end
  raise "#{command.join(' ')} failed: #{stdout}#{stderr}" unless status.success?
  stdout.strip
end

def capture_bytes!(*command, chdir: nil, stdin_data: "")
  stdout, stderr, status = Open3.capture3(*command, chdir: chdir, stdin_data: stdin_data, binmode: true)
  raise "#{command.join(' ')} failed: #{stderr}" unless status.success?
  stdout
end

def source_tracked_bytes(ref, path)
  capture_bytes!("git", "show", "#{ref}:#{path}", chdir: SOURCE_ROOT)
end

def authority_metadata_commits(truth)
  recovery = truth.fetch("mandatory_exit_capability_recovery")
  commits = []
  route = (recovery["integrated_capability_routes"] || {}).values.first
  commits << route["canonical_parent_commit"] if route.is_a?(Hash)
  %w[final_clean_room_implementation_route post_revision_final_implementation_route].each do |field|
    value = recovery[field]
    commits << value["canonical_parent_commit"] if value.is_a?(Hash)
  end
  rebaseline = recovery["project_level_rebaseline"]
  commits << rebaseline["canonical_parent_commit"] if rebaseline.is_a?(Hash)
  truth.fetch("task_history").each_value do |entry|
    next unless entry.is_a?(Hash) && entry["status"].to_s.include?("ACCEPTED")
    commits << entry["accepted_candidate_commit"] if entry["accepted_candidate_commit"]
  end
  commits.compact.uniq
end

def import_commit_and_tree_metadata!(root, commit)
  raise "unsafe metadata commit identity" unless commit.match?(/\A[0-9a-f]{40}\z/)
  commit_bytes = capture_bytes!("git", "cat-file", "commit", commit, chdir: SOURCE_ROOT)
  imported_commit = capture_bytes!("git", "hash-object", "-t", "commit", "-w", "--stdin", chdir: root, stdin_data: commit_bytes).strip
  raise "commit metadata identity drift" unless imported_commit == commit
  tree = capture_bytes!("git", "rev-parse", "#{commit}^{tree}", chdir: SOURCE_ROOT).strip
  tree_bytes = capture_bytes!("git", "cat-file", "tree", tree, chdir: SOURCE_ROOT)
  imported_tree = capture_bytes!("git", "hash-object", "-t", "tree", "-w", "--stdin", chdir: root, stdin_data: tree_bytes).strip
  raise "tree metadata identity drift" unless imported_tree == tree
end

def initialize_synthetic_authority_repo!(root, ref)
  FileUtils.rm_rf(root)
  SAFE_AUTHORITY_FIXTURE_PATHS.each do |path|
    absolute = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.binwrite(absolute, source_tracked_bytes(ref, path))
  end
  validator_path = File.join(root, "scripts/validate-current-task-authority.rb")
  FileUtils.mkdir_p(File.dirname(validator_path))
  FileUtils.cp(File.join(SOURCE_ROOT, "scripts/validate-current-task-authority.rb"), validator_path)
  run!("git", "init", "-q", "-b", "main", chdir: root)
  run!("git", "config", "user.name", "SourceLens Synthetic Authority Test", chdir: root)
  run!("git", "config", "user.email", "synthetic-authority@example.invalid", chdir: root)
  run!("git", "add", "--", *SAFE_AUTHORITY_FIXTURE_PATHS, "scripts/validate-current-task-authority.rb", chdir: root)
  run!("git", "commit", "-q", "-m", "synthetic authority base", chdir: root)
  truth = YAML.safe_load(File.read(File.join(root, "docs/aios/truth/project_state.yaml")), aliases: false)
  source_ref_commit = capture_bytes!("git", "rev-parse", "#{ref}^{commit}", chdir: SOURCE_ROOT).strip
  (authority_metadata_commits(truth) + [source_ref_commit]).uniq.each do |commit|
    import_commit_and_tree_metadata!(root, commit)
  end
  raise "forbidden P1-038 Contract materialized in synthetic worktree" if File.exist?(File.join(root, FORBIDDEN_P1_038_CONTRACT_PATH))
  _stdout, _stderr, status = Open3.capture3("git", "cat-file", "-e", FORBIDDEN_P1_038_CONTRACT_OID, chdir: root)
  raise "forbidden P1-038 Contract blob imported into synthetic object store" if status.success?
end

def write_yaml(path, value)
  File.write(path, YAML.dump(value), mode: "w:UTF-8")
end

def write_json(path, value)
  File.write(path, JSON.pretty_generate(value) + "\n", mode: "w:UTF-8")
end

def run_validator(root, expected_pass, label, expected_failure: nil, env: {})
  validator_env = { "LC_ALL" => "C", "LANG" => "C" }.merge(env)
  stdout, stderr, status = Open3.capture3(validator_env, "ruby", "scripts/validate-current-task-authority.rb", chdir: root)
  actual = status.success?
  raise "#{label}: expected #{expected_pass ? 'PASS' : 'FAIL'}, observed #{actual ? 'PASS' : 'FAIL'}: #{stdout}#{stderr}" unless actual == expected_pass
  if !expected_pass && expected_failure && !"#{stdout}#{stderr}".include?(expected_failure)
    raise "#{label}: expected failure containing #{expected_failure.inspect}, observed: #{stdout}#{stderr}"
  end
end

Dir.mktmpdir("aios-rebuild-authority-") do |root|
  canonical_root = File.join(root, "canonical")
  rebuild_root = File.join(root, "fresh-clone")
  run!("git", "clone", "--no-local", "--branch", "main", SOURCE_ROOT, canonical_root)
  FileUtils.cp(File.join(SOURCE_ROOT, "scripts/validate-current-task-authority.rb"), File.join(canonical_root, "scripts/validate-current-task-authority.rb"))
  truth_path = File.join(canonical_root, "docs/aios/truth/project_state.yaml")
  truth = YAML.safe_load(File.read(truth_path), aliases: false)
  truth["project"]["canonical_repository"] = canonical_root
  truth["project"]["task_worktree_root"] = File.join(root, "task-worktrees")
  FileUtils.mkdir_p(truth["project"]["task_worktree_root"])
  write_yaml(truth_path, truth)
  run!("git", "config", "user.name", "SourceLens Rebuild Verification Test", chdir: canonical_root)
  run!("git", "config", "user.email", "rebuild-verification@example.invalid", chdir: canonical_root)
  run!("git", "add", "docs/aios/truth/project_state.yaml", "scripts/validate-current-task-authority.rb", chdir: canonical_root)
  run!("git", "commit", "-m", "synthetic rebuild authority source", chdir: canonical_root)

  run!("git", "clone", "--no-local", "--branch", "main", canonical_root, rebuild_root)
  run_validator(rebuild_root, false, "fresh clone without rebuild mode negative", expected_failure: "canonical repository identity drift")
  run_validator(canonical_root, false, "canonical cannot use rebuild mode negative", expected_failure: "requires a non-canonical fresh clone", env: { "SOURCELENS_REBUILD_VERIFY" => "1" })
  run_validator(rebuild_root, true, "clean fresh clone rebuild mode positive", env: { "SOURCELENS_REBUILD_VERIFY" => "1" })

  File.write(File.join(rebuild_root, "UNTRACKED_REBUILD_DRIFT"), "drift\n", mode: "w:UTF-8")
  run_validator(rebuild_root, false, "dirty fresh clone rebuild mode negative", expected_failure: "clone is not clean", env: { "SOURCELENS_REBUILD_VERIFY" => "1" })
  FileUtils.rm_f(File.join(rebuild_root, "UNTRACKED_REBUILD_DRIFT"))

  run!("git", "config", "user.name", "SourceLens Rebuild Verification Test", chdir: rebuild_root)
  run!("git", "config", "user.email", "rebuild-verification@example.invalid", chdir: rebuild_root)
  File.write(File.join(rebuild_root, "REBUILD_HEAD_DRIFT"), "drift\n", mode: "w:UTF-8")
  run!("git", "add", "REBUILD_HEAD_DRIFT", chdir: rebuild_root)
  run!("git", "commit", "-m", "synthetic rebuild head drift", chdir: rebuild_root)
  run_validator(rebuild_root, false, "fresh clone HEAD drift negative", expected_failure: "HEAD drift", env: { "SOURCELENS_REBUILD_VERIFY" => "1" })
end

Dir.mktmpdir("aios-current-task-authority-") do |root|
  FileUtils.mkdir_p(File.join(root, "scripts"))
  FileUtils.mkdir_p(File.join(root, "docs/aios/truth"))
  FileUtils.mkdir_p(File.join(root, "docs/aios/tasks"))
  FileUtils.cp(File.join(SOURCE_ROOT, "scripts/validate-current-task-authority.rb"), File.join(root, "scripts"))
  FileUtils.cp(File.join(SOURCE_ROOT, "AGENTS.md"), root)
  FileUtils.cp(File.join(SOURCE_ROOT, "docs/aios/FOUNDER_DELEGATION_POLICY.md"), File.join(root, "docs/aios"))
  FileUtils.cp(File.join(SOURCE_ROOT, "docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml"), File.join(root, "docs/aios/tasks"))

  worktree_root = File.join(root, "task-worktrees")
  evidence_base = File.join(root, "audit")
  FileUtils.mkdir_p(worktree_root)
  FileUtils.mkdir_p(evidence_base)

  truth = YAML.safe_load(File.read(File.join(SOURCE_ROOT, "docs/aios/truth/project_state.yaml")), aliases: false)
  truth["authority"]["founder_delegation_policy"]["sha256"] = Digest::SHA256.file(File.join(root, "docs/aios/FOUNDER_DELEGATION_POLICY.md")).hexdigest
  truth["project"]["canonical_repository"] = root
  truth["project"]["task_worktree_root"] = worktree_root
  truth["project"]["execution_evidence_root_base"] = evidence_base
  rebaseline = truth.dig("mandatory_exit_capability_recovery", "project_level_rebaseline")
  rebaseline_root = File.join(evidence_base, "p1-exit-gate-project-level-rebaseline")
  FileUtils.mkdir_p(rebaseline_root)
  {
    "plan_path" => "P1_EXIT_GATE_PROJECT_LEVEL_REBASELINE.md",
    "decision_record_path" => "FOUNDER_FINAL_REBASELINE_DECISION_DRAFT.md"
  }.each do |field, basename|
    source = rebaseline.fetch(field)
    target = File.join(rebaseline_root, basename)
    FileUtils.cp(source, target)
    rebaseline[field] = target
  end
  truth["task_history"] = {
    "aios_p1_006" => {
      "task_id" => "AIOS-P1-006_SYNTHETIC_TERMINAL_HISTORY",
      "status" => "TERMINAL_STOPPED",
      "resume_retry_successor_allowed" => false
    }
  }
  truth["mandatory_exit_capability_recovery"]["capability_status"].keys.each do |capability|
    truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "MISSING"
    truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][capability] = nil
  end
  truth["mandatory_exit_capability_recovery"]["founder_dispositions"] = {}
  truth["mandatory_exit_capability_recovery"]["integrated_capability_routes"] = {}
  truth["mandatory_exit_capability_recovery"]["historical_governance_metadata_read_boundary"] = nil
  truth["mandatory_exit_capability_recovery"]["final_clean_room_implementation_route"] = nil
  truth["mandatory_exit_capability_recovery"]["final_clean_room_implementation_attempt"] = nil
  truth["mandatory_exit_capability_recovery"]["final_clean_room_contract_review_terminal"] = nil
  truth["mandatory_exit_capability_recovery"]["post_revision_final_implementation_route"] = nil
  truth["mandatory_exit_capability_recovery"]["post_revision_final_implementation_attempt"] = nil
  truth["mandatory_exit_capability_recovery"]["post_revision_final_route_terminal"] = nil
  truth["goal"]["control_plane_status_observed"] = "ACTIVE"
  truth["goal"]["current_task_authority"] = "NONE"
  truth["project"]["phase_execution_status"] = "NO_CURRENT_TASK"
  truth["project"]["p1_execution_status"] = "NO_CURRENT_TASK"
  truth["active_work"] = {
    "current_task" => "NONE",
    "current_task_status" => "NONE",
    "current_task_contract" => nil,
    "current_task_contract_sha256" => nil,
    "current_execution_authorization" => nil,
    "current_execution_authorization_sha256" => nil,
    "execution_nonce" => nil,
    "execution_nonce_status" => "NONE",
    "authorization_id" => nil,
    "activation_parent_commit" => nil,
    "activation_parent_tree" => nil,
    "task_resource_state" => "NONE",
    "task_branch" => nil,
    "task_worktree" => nil,
    "execution_evidence_root" => nil,
    "offsite_target" => nil,
    "founder_reserved_authorization" => nil,
    "founder_reserved_authorization_sha256" => nil,
    "founder_decision_required" => false,
    "escalation_reason" => nil,
    "user_action_required" => nil,
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_IMPLEMENT_P1_EXIT_CAPABILITIES_IN_FROZEN_PRIORITY_ORDER"
  }
  truth["phase_execution_claim"]["current_task_claim"] = "NO_CURRENT_TASK"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)

  run!("git", "init", chdir: root)
  run!("git", "config", "user.name", "SourceLens Validator Test", chdir: root)
  run!("git", "config", "user.email", "validator@example.invalid", chdir: root)
  run!("git", "add", ".", chdir: root)
  run!("git", "commit", "-m", "base", chdir: root)
  run!("git", "branch", "-M", "main", chdir: root)
  import_commit_and_tree_metadata!(root, rebaseline.fetch("canonical_parent_commit"))
  run_validator(root, true, "NONE positive")

  none_truth = Marshal.load(Marshal.dump(truth))
  bad_none = Marshal.load(Marshal.dump(none_truth))
  bad_none["active_work"]["next_eligible_action"] = "REQUEST_FOUNDER_APPROVAL_FOR_NEXT_P1_TASK"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), bad_none)
  run_validator(root, false, "routine Founder approval negative")

  stale_none = Marshal.load(Marshal.dump(none_truth))
  stale_none["active_work"]["activation_parent_commit"] = "deadbeef"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), stale_none)
  run_validator(root, false, "stale NONE binding negative")

  in_progress_none = Marshal.load(Marshal.dump(none_truth))
  in_progress_none["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "IN_PROGRESS"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), in_progress_none)
  run_validator(root, false, "in-progress capability without active Task negative")

  accepted_without_gate = Marshal.load(Marshal.dump(none_truth))
  accepted_without_gate["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "ACCEPTED"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), accepted_without_gate)
  run_validator(root, false, "accepted capability without Task Gate binding negative")

  disposed_without_founder = Marshal.load(Marshal.dump(none_truth))
  disposed_without_founder["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "FOUNDER_DISPOSED"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), disposed_without_founder)
  run_validator(root, false, "Founder-disposed capability without decision binding negative")

  fake_terminal_root = File.join(evidence_base, "fake-terminal")
  FileUtils.mkdir_p(fake_terminal_root)
  fake_task_id = "AIOS-P1-900_FAKE_ACCEPTED"
  fake_capability = "VERSIONED_REPRESENTATIVE_TASK_DATASET"
  fake_contract_sha = "1" * 64
  fake_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  fake_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  fake_manifest_path = File.join(fake_terminal_root, "weak-manifest.json")
  File.write(fake_manifest_path, "{}\n")
  fake_review_paths = {}
  %w[cto security quality].each do |role|
    path = File.join(fake_terminal_root, "weak-#{role}.json")
    File.write(path, JSON.pretty_generate({ "status" => "PASS", "task_id" => fake_task_id, "mandatory_exit_capability" => fake_capability }) + "\n")
    fake_review_paths[role] = path
  end
  fake_gate_path = File.join(fake_terminal_root, "weak-gate.json")
  fake_gate = {
    "record_type" => "aios_phase_delegated_task_gate_receipt",
    "status" => "ACCEPTED",
    "authority" => "MASTER_CEO_AGENT",
    "task_id" => fake_task_id,
    "mandatory_exit_capability" => fake_capability,
    "task_contract_sha256" => fake_contract_sha,
    "candidate_commit" => fake_commit,
    "candidate_tree" => fake_tree,
    "evidence_manifest_sha256" => Digest::SHA256.file(fake_manifest_path).hexdigest,
    "cto_review_sha256" => Digest::SHA256.file(fake_review_paths["cto"]).hexdigest,
    "security_review_sha256" => Digest::SHA256.file(fake_review_paths["security"]).hexdigest,
    "quality_review_sha256" => Digest::SHA256.file(fake_review_paths["quality"]).hexdigest
  }
  File.write(fake_gate_path, JSON.pretty_generate(fake_gate) + "\n")
  fake_accepted = Marshal.load(Marshal.dump(none_truth))
  fake_accepted["mandatory_exit_capability_recovery"]["capability_status"][fake_capability] = "ACCEPTED"
  fake_accepted["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][fake_capability] = {
    "status" => "ACCEPTED", "task_id" => fake_task_id, "attempt_ordinal" => 1,
    "contract_sha256" => fake_contract_sha, "bounded_contract_corrections_used" => 0
  }
  fake_accepted["task_history"]["fake_accepted"] = {
    "task_id" => fake_task_id,
    "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
    "mandatory_exit_capability" => fake_capability,
    "clean_room_attempt_ordinal" => 1,
    "task_gate_result" => "PASS",
    "task_contract_sha256" => fake_contract_sha,
    "bounded_contract_corrections_used" => 0,
    "accepted_candidate_commit" => fake_commit,
    "accepted_candidate_tree" => fake_tree,
    "execution_evidence_root" => fake_terminal_root,
    "evidence_manifest_path" => fake_manifest_path,
    "evidence_manifest_sha256" => Digest::SHA256.file(fake_manifest_path).hexdigest,
    "cto_review_path" => fake_review_paths["cto"],
    "cto_review_sha256" => Digest::SHA256.file(fake_review_paths["cto"]).hexdigest,
    "security_review_path" => fake_review_paths["security"],
    "security_review_sha256" => Digest::SHA256.file(fake_review_paths["security"]).hexdigest,
    "quality_review_path" => fake_review_paths["quality"],
    "quality_review_sha256" => Digest::SHA256.file(fake_review_paths["quality"]).hexdigest,
    "task_gate_receipt_path" => fake_gate_path,
    "task_gate_receipt_sha256" => Digest::SHA256.file(fake_gate_path).hexdigest
  }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), fake_accepted)
  run_validator(root, false, "accepted capability with weakly bound artifacts negative")

  fake_disposed = Marshal.load(Marshal.dump(none_truth))
  fake_disposed["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "FOUNDER_DISPOSED"
  fake_disposed["mandatory_exit_capability_recovery"]["founder_dispositions"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = {
    "status" => "APPROVED",
    "decision_record_path" => File.join(evidence_base, "missing-founder-disposition.json"),
    "decision_record_sha256" => "0" * 64
  }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), fake_disposed)
  run_validator(root, false, "Founder disposition with nonexistent decision record negative")

  blocked_without_terminal = Marshal.load(Marshal.dump(none_truth))
  blocked_without_terminal["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "ARCHITECTURE_BLOCKED"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), blocked_without_terminal)
  run_validator(root, false, "architecture-blocked capability without terminal binding negative")

  review_blocked_without_record = Marshal.load(Marshal.dump(none_truth))
  review_blocked_without_record["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "CONTRACT_REVIEW_BLOCKED"
  review_blocked_without_record["mandatory_exit_capability_recovery"]["capability_attempt_ledger"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = {
    "status" => "CONTRACT_REVIEW_BLOCKED", "task_id" => "AIOS-P1-900_REVIEW_BLOCKED",
    "attempt_ordinal" => 1, "founder_escalation_required" => true,
    "failure_record_path" => File.join(evidence_base, "missing-review-failure.json"),
    "failure_record_sha256" => "0" * 64
  }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), review_blocked_without_record)
  run_validator(root, false, "contract-review-blocked capability without failure record negative")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), none_truth)

  parent_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  parent_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  task_id = "AIOS-P1-900_AUTHORITY_TEST"
  task_branch = "task/AIOS-P1-900-authority-test"
  task_worktree = File.join(worktree_root, "AIOS-P1-900-authority-test")
  evidence_root = File.join(evidence_base, "p1-900-authority-test")
  FileUtils.mkdir_p(evidence_root)
  contract = {
    "schema_version" => 1,
    "task_id" => task_id,
    "phase" => "P1",
    "status" => "READY_FOR_PHASE_DELEGATED_EXECUTION",
    "execution_authority" => "PHASE_DELEGATED",
    "objective" => "Verify the generic current Task authority state machine.",
    "why_now" => ["The phase-level delegation gate requires positive and negative coverage."],
    "task_spec_ref" => "synthetic://current-task-authority-test",
    "read_context" => ["docs/aios/FOUNDER_DELEGATION_POLICY.md"],
    "dependencies" => [],
    "mandatory_exit_capability" => "VERSIONED_REPRESENTATIVE_TASK_DATASET",
    "clean_room_recovery" => {
      "historical_execution_lineage_reused" => false,
      "attempt_ordinal" => 1,
      "bounded_contract_corrections_allowed" => 1,
      "bounded_contract_corrections_used" => 0,
      "original_contract_path" => nil,
      "original_contract_sha256" => nil
    },
    "task_kind" => "EVALUATION_FOUNDATION_ENGINEERING",
    "capabilities" => ["TASK_SPEC_VALIDATION"],
    "capability_claim" => false,
    "risk_level" => "medium",
    "lineage" => {
      "kind" => "INDEPENDENT_PHASE_INCREMENT",
      "retries" => [],
      "remediates" => [],
      "supersedes" => []
    },
    "roles" => {
      "accountable_owner" => "Engineering Manager Agent",
      "worker" => "Test Worker",
      "independent_reviewers" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
    },
    "allowed_paths" => {
      "worker" => ["evaluation-harness/environment/test/**"],
      "external_evidence" => ["#{evidence_root}/**"]
    },
    "forbidden_actions" => ["network", "Provider", "Secret", "remote", "production", "public effect"],
    "budget" => { "engineering_hours" => 1, "implementation_iterations" => 1, "execution_retries" => 0, "network_calls" => 0 },
    "acceptance_criteria" => ["positive and negative validator vectors pass"],
    "failure_criteria" => ["an invalid authority state is accepted"],
    "stop_conditions" => ["scope expansion is required"],
    "evidence" => { "required" => ["validator result"] },
    "rollback" => { "method" => "delete the unmerged test worktree" },
    "delegated_authority" => {
      "phase_local" => true,
      "task_gate_owner" => "MASTER_CEO_AGENT",
      "founder_gate" => "RESERVED_DECISIONS_ONLY",
      "founder_reserved_decisions" => [],
      "external_effects" => {
        "network" => false, "provider" => false, "secret" => false,
        "remote" => false, "production" => false, "public" => false
      }
    }
  }
  contract_rel = "docs/aios/tasks/P1-900_AUTHORITY_TEST.yaml"
  contract_path = File.join(root, contract_rel)
  write_yaml(contract_path, contract)
  contract_sha = Digest::SHA256.file(contract_path).hexdigest
  authorization_id = Digest::SHA256.hexdigest("#{task_id}:#{contract_sha}:#{parent_commit}")
  authorization_path = File.join(evidence_root, "P1-900_AUTHORIZATION.json")
  authorization = {
    "record_type" => "aios_phase_delegated_task_authorization",
    "status" => "ACTIVE",
    "authority" => "MASTER_CEO_AGENT",
    "delegation_model" => "PHASE_LEVEL_FOUNDER_DELEGATION",
    "authorization_id" => authorization_id,
    "task_id" => task_id,
    "phase" => "P1",
    "task_contract_sha256" => contract_sha,
    "goal_canonical_sha256" => truth.dig("goal", "observed_body_sha256"),
    "parent_commit" => parent_commit,
    "parent_tree" => parent_tree,
    "external_effects" => contract.dig("delegated_authority", "external_effects"),
    "founder_reserved_decisions" => [],
    "founder_reserved_decision_required" => false
  }
  File.write(authorization_path, JSON.pretty_generate(authorization) + "\n")

  active_truth = Marshal.load(Marshal.dump(none_truth))
  active_truth["goal"]["current_task_authority"] = task_id
  active_truth["project"]["phase_execution_status"] = "TASK_ACTIVE"
  active_truth["project"]["p1_execution_status"] = "TASK_ACTIVE"
  active_truth["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "IN_PROGRESS"
  active_truth["active_work"] = {
    "current_task" => task_id,
    "current_task_status" => "AUTHORIZED_ACTIVE",
    "current_task_contract" => contract_rel,
    "current_task_contract_sha256" => contract_sha,
    "current_execution_authorization" => authorization_path,
    "current_execution_authorization_sha256" => Digest::SHA256.file(authorization_path).hexdigest,
    "execution_nonce" => nil,
    "execution_nonce_status" => "NOT_REQUIRED_PHASE_DELEGATION",
    "authorization_id" => authorization_id,
    "activation_parent_commit" => parent_commit,
    "activation_parent_tree" => parent_tree,
    "task_resource_state" => "DECLARED",
    "task_branch" => task_branch,
    "task_worktree" => task_worktree,
    "execution_evidence_root" => evidence_root,
    "offsite_target" => nil,
    "founder_reserved_authorization" => nil,
    "founder_reserved_authorization_sha256" => nil,
    "founder_decision_required" => false,
    "escalation_reason" => nil,
    "user_action_required" => nil,
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_EXECUTE_CURRENT_TASK"
  }
  active_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = {
    "status" => "ACTIVE",
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "contract_sha256" => contract_sha,
    "bounded_contract_corrections_used" => 0
  }
  active_truth["phase_execution_claim"]["current_task_claim"] = task_id
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), active_truth)
  run!("git", "add", "docs/aios/tasks", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "-m", "activate test task", chdir: root)
  run_validator(root, true, "active DECLARED positive")

  reserved_contract = Marshal.load(Marshal.dump(contract))
  reserved_contract["risk_level"] = "critical"
  reserved_contract["delegated_authority"]["founder_reserved_decisions"] = ["critical_residual_risk_acceptance"]
  write_yaml(contract_path, reserved_contract)
  reserved_contract_sha = Digest::SHA256.file(contract_path).hexdigest
  reserved_authorization = Marshal.load(Marshal.dump(authorization))
  reserved_authorization["task_contract_sha256"] = reserved_contract_sha
  reserved_authorization["founder_reserved_decisions"] = ["critical_residual_risk_acceptance"]
  reserved_authorization["founder_reserved_decision_required"] = true
  File.write(authorization_path, JSON.pretty_generate(reserved_authorization) + "\n")
  founder_path = File.join(evidence_root, "FOUNDER_RESERVED_DECISION.json")
  founder_decision = {
    "record_type" => "sourcelens_aios_founder_reserved_decision",
    "status" => "APPROVED",
    "authority" => "HUMAN_FOUNDER",
    "task_id" => task_id,
    "phase" => "P1",
    "authorization_id" => authorization_id,
    "task_contract_sha256" => reserved_contract_sha,
    "approved_reserved_decisions" => ["critical_residual_risk_acceptance"],
    "approved_external_effects" => {}
  }
  File.write(founder_path, JSON.pretty_generate(founder_decision) + "\n")
  reserved_truth = Marshal.load(Marshal.dump(active_truth))
  reserved_truth["active_work"]["current_task_contract_sha256"] = reserved_contract_sha
  reserved_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  reserved_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"]["contract_sha256"] = reserved_contract_sha
  reserved_truth["active_work"]["founder_reserved_authorization"] = founder_path
  reserved_truth["active_work"]["founder_reserved_authorization_sha256"] = Digest::SHA256.file(founder_path).hexdigest
  reserved_truth["active_work"]["founder_decision_required"] = true
  reserved_truth["active_work"]["escalation_reason"] = "critical_risk_requires_acceptance"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), reserved_truth)
  run!("git", "add", "docs/aios/tasks", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "--amend", "--no-edit", chdir: root)
  run_validator(root, true, "Founder-reserved DECLARED positive")

  wrong_founder = Marshal.load(Marshal.dump(founder_decision))
  wrong_founder["authorization_id"] = "0" * 64
  File.write(founder_path, JSON.pretty_generate(wrong_founder) + "\n")
  wrong_founder_truth = Marshal.load(Marshal.dump(reserved_truth))
  wrong_founder_truth["active_work"]["founder_reserved_authorization_sha256"] = Digest::SHA256.file(founder_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), wrong_founder_truth)
  run_validator(root, false, "Founder reserved decision binding negative")

  write_yaml(contract_path, contract)
  File.write(authorization_path, JSON.pretty_generate(authorization) + "\n")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), active_truth)
  File.unlink(founder_path)
  run!("git", "add", "docs/aios/tasks", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "--amend", "--no-edit", chdir: root)
  run_validator(root, true, "active DECLARED restored positive")

  expanded_contract = Marshal.load(Marshal.dump(contract))
  expanded_contract["allowed_paths"]["integration"] = ["AGENTS.md"]
  write_yaml(contract_path, expanded_contract)
  expanded_contract_sha = Digest::SHA256.file(contract_path).hexdigest
  expanded_authorization = Marshal.load(Marshal.dump(authorization))
  expanded_authorization["task_contract_sha256"] = expanded_contract_sha
  File.write(authorization_path, JSON.pretty_generate(expanded_authorization) + "\n")
  expanded_truth = Marshal.load(Marshal.dump(active_truth))
  expanded_truth["phase_boundary"]["role_write_roots"]["integration"] << "AGENTS.md"
  expanded_truth["phase_boundary"]["immutable_authority_paths"].delete("AGENTS.md")
  expanded_truth["active_work"]["current_task_contract_sha256"] = expanded_contract_sha
  expanded_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), expanded_truth)
  run!("git", "add", "docs/aios/tasks", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "--amend", "--no-edit", chdir: root)
  run_validator(root, false, "self-expanded Phase boundary negative")
  write_yaml(contract_path, contract)
  File.write(authorization_path, JSON.pretty_generate(authorization) + "\n")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), active_truth)
  run!("git", "add", "docs/aios/tasks", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "--amend", "--no-edit", chdir: root)

  deleted_history_truth = Marshal.load(Marshal.dump(active_truth))
  deleted_history_truth["task_history"].delete("aios_p1_006")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), deleted_history_truth)
  run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "--amend", "--no-edit", chdir: root)
  run_validator(root, false, "activation history deletion negative")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), active_truth)
  run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "--amend", "--no-edit", chdir: root)

  blocked = Marshal.load(Marshal.dump(active_truth))
  blocked["goal"]["control_plane_status_observed"] = "BLOCKED"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), blocked)
  run_validator(root, false, "blocked Goal negative")

  reused = Marshal.load(Marshal.dump(active_truth))
  reused["task_history"]["reused_test"] = { "task_id" => task_id, "status" => "TERMINAL_STOPPED" }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), reused)
  run_validator(root, false, "terminal Task reuse negative")

  reserved_historical_id = Marshal.load(Marshal.dump(active_truth))
  reserved_historical_id["active_work"]["current_task"] = "AIOS-P1-007_RESERVED_ID"
  reserved_historical_id["goal"]["current_task_authority"] = "AIOS-P1-007_RESERVED_ID"
  reserved_historical_id["phase_execution_claim"]["current_task_claim"] = "AIOS-P1-007_RESERVED_ID"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), reserved_historical_id)
  run_validator(root, false, "P1-002..P1-034 reserved Task ID negative")

  reused_evidence = Marshal.load(Marshal.dump(active_truth))
  reused_evidence["task_history"]["other_test"] = {
    "task_id" => "AIOS-P1-899_OTHER",
    "execution_evidence_root" => evidence_root,
    "status" => "TERMINAL_STOPPED"
  }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), reused_evidence)
  run_validator(root, false, "historical Evidence root reuse negative")

  malformed_authorization_id = Marshal.load(Marshal.dump(active_truth))
  malformed_authorization_id["active_work"]["authorization_id"] = "not-a-canonical-id"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), malformed_authorization_id)
  run_validator(root, false, "malformed authorization ID negative")

  peripheral_contract = Marshal.load(Marshal.dump(contract))
  peripheral_contract["mandatory_exit_capability"] = "PERIPHERAL_GOVERNANCE_VALIDATOR"
  write_yaml(contract_path, peripheral_contract)
  peripheral_sha = Digest::SHA256.file(contract_path).hexdigest
  peripheral_authorization = Marshal.load(Marshal.dump(authorization))
  peripheral_authorization["task_contract_sha256"] = peripheral_sha
  File.write(authorization_path, JSON.pretty_generate(peripheral_authorization) + "\n")
  peripheral_truth = Marshal.load(Marshal.dump(active_truth))
  peripheral_truth["active_work"]["current_task_contract_sha256"] = peripheral_sha
  peripheral_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), peripheral_truth)
  run_validator(root, false, "peripheral capability selection negative")

  bypass_contract = Marshal.load(Marshal.dump(contract))
  bypass_contract["mandatory_exit_capability"] = "HIDDEN_SET_PROTOCOL"
  write_yaml(contract_path, bypass_contract)
  bypass_sha = Digest::SHA256.file(contract_path).hexdigest
  bypass_authorization = Marshal.load(Marshal.dump(authorization))
  bypass_authorization["task_contract_sha256"] = bypass_sha
  File.write(authorization_path, JSON.pretty_generate(bypass_authorization) + "\n")
  bypass_truth = Marshal.load(Marshal.dump(active_truth))
  bypass_truth["mandatory_exit_capability_recovery"]["capability_status"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"] = "ARCHITECTURE_BLOCKED"
  bypass_truth["mandatory_exit_capability_recovery"]["capability_status"]["HIDDEN_SET_PROTOCOL"] = "IN_PROGRESS"
  bypass_truth["active_work"]["current_task_contract_sha256"] = bypass_sha
  bypass_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), bypass_truth)
  run_validator(root, false, "earlier mandatory capability bypass negative")

  reuse_contract = Marshal.load(Marshal.dump(contract))
  reuse_contract["clean_room_recovery"]["historical_execution_lineage_reused"] = true
  write_yaml(contract_path, reuse_contract)
  reuse_sha = Digest::SHA256.file(contract_path).hexdigest
  reuse_authorization = Marshal.load(Marshal.dump(authorization))
  reuse_authorization["task_contract_sha256"] = reuse_sha
  File.write(authorization_path, JSON.pretty_generate(reuse_authorization) + "\n")
  reuse_truth = Marshal.load(Marshal.dump(active_truth))
  reuse_truth["active_work"]["current_task_contract_sha256"] = reuse_sha
  reuse_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), reuse_truth)
  run_validator(root, false, "historical execution lineage reuse negative")

  prior_attempt_truth = Marshal.load(Marshal.dump(active_truth))
  prior_attempt_truth["task_history"]["prior_clean_room_attempt"] = {
    "task_id" => "AIOS-P1-899_PRIOR_CLEAN_ROOM_ATTEMPT",
    "status" => "TERMINAL_STOPPED",
    "mandatory_exit_capability" => "VERSIONED_REPRESENTATIVE_TASK_DATASET"
  }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), prior_attempt_truth)
  write_yaml(contract_path, contract)
  File.write(authorization_path, JSON.pretty_generate(authorization) + "\n")
  run_validator(root, false, "second clean-room capability attempt negative")

  historical_read_contract = Marshal.load(Marshal.dump(contract))
  historical_read_contract["read_context"] = ["docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml"]
  write_yaml(contract_path, historical_read_contract)
  historical_read_sha = Digest::SHA256.file(contract_path).hexdigest
  historical_read_authorization = Marshal.load(Marshal.dump(authorization))
  historical_read_authorization["task_contract_sha256"] = historical_read_sha
  File.write(authorization_path, JSON.pretty_generate(historical_read_authorization) + "\n")
  historical_read_truth = Marshal.load(Marshal.dump(active_truth))
  historical_read_truth["active_work"]["current_task_contract_sha256"] = historical_read_sha
  historical_read_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), historical_read_truth)
  run_validator(root, false, "historical Task asset read-context negative")

  excessive_correction_contract = Marshal.load(Marshal.dump(contract))
  excessive_correction_contract["clean_room_recovery"]["bounded_contract_corrections_used"] = 2
  write_yaml(contract_path, excessive_correction_contract)
  excessive_correction_sha = Digest::SHA256.file(contract_path).hexdigest
  excessive_correction_authorization = Marshal.load(Marshal.dump(authorization))
  excessive_correction_authorization["task_contract_sha256"] = excessive_correction_sha
  File.write(authorization_path, JSON.pretty_generate(excessive_correction_authorization) + "\n")
  excessive_correction_truth = Marshal.load(Marshal.dump(active_truth))
  excessive_correction_truth["active_work"]["current_task_contract_sha256"] = excessive_correction_sha
  excessive_correction_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), excessive_correction_truth)
  run_validator(root, false, "excessive bounded Contract correction negative")

  already_corrected_original = Marshal.load(Marshal.dump(contract))
  already_corrected_original["clean_room_recovery"]["bounded_contract_corrections_used"] = 1
  already_corrected_original["clean_room_recovery"]["original_contract_path"] = File.join(evidence_root, "earlier-original.yaml")
  already_corrected_original["clean_room_recovery"]["original_contract_sha256"] = "0" * 64
  already_corrected_path = File.join(evidence_root, "already-corrected-original.yaml")
  write_yaml(already_corrected_path, already_corrected_original)
  second_correction_contract = Marshal.load(Marshal.dump(contract))
  second_correction_contract["clean_room_recovery"]["bounded_contract_corrections_used"] = 1
  second_correction_contract["clean_room_recovery"]["original_contract_path"] = already_corrected_path
  second_correction_contract["clean_room_recovery"]["original_contract_sha256"] = Digest::SHA256.file(already_corrected_path).hexdigest
  write_yaml(contract_path, second_correction_contract)
  second_correction_sha = Digest::SHA256.file(contract_path).hexdigest
  second_correction_authorization = Marshal.load(Marshal.dump(authorization))
  second_correction_authorization["task_contract_sha256"] = second_correction_sha
  File.write(authorization_path, JSON.pretty_generate(second_correction_authorization) + "\n")
  second_correction_truth = Marshal.load(Marshal.dump(active_truth))
  second_correction_truth["active_work"]["current_task_contract_sha256"] = second_correction_sha
  second_correction_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  second_correction_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"]["contract_sha256"] = second_correction_sha
  second_correction_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"]["VERSIONED_REPRESENTATIVE_TASK_DATASET"]["bounded_contract_corrections_used"] = 1
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), second_correction_truth)
  run_validator(root, false, "second bounded Contract correction disguised as first negative")

  missing_reviewer = Marshal.load(Marshal.dump(contract))
  missing_reviewer["roles"]["independent_reviewers"] = []
  write_yaml(contract_path, missing_reviewer)
  changed = Marshal.load(Marshal.dump(active_truth))
  changed["active_work"]["current_task_contract_sha256"] = Digest::SHA256.file(contract_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), changed)
  run_validator(root, false, "missing Reviewer negative")

  old_gate = Marshal.load(Marshal.dump(contract))
  old_gate["delegated_authority"]["founder_gate"] = "EVERY_TASK"
  write_yaml(contract_path, old_gate)
  changed["active_work"]["current_task_contract_sha256"] = Digest::SHA256.file(contract_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), changed)
  run_validator(root, false, "routine Task Founder Gate negative")

  stopped_contract = Marshal.load(Marshal.dump(contract))
  stopped_contract["status"] = "STOPPED"
  write_yaml(contract_path, stopped_contract)
  changed["active_work"]["current_task_contract_sha256"] = Digest::SHA256.file(contract_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), changed)
  run_validator(root, false, "terminal Contract status negative")

  effect_contract = Marshal.load(Marshal.dump(contract))
  effect_contract["delegated_authority"]["external_effects"]["network"] = true
  write_yaml(contract_path, effect_contract)
  effect_contract_sha = Digest::SHA256.file(contract_path).hexdigest
  effect_authorization = Marshal.load(Marshal.dump(authorization))
  effect_authorization["task_contract_sha256"] = effect_contract_sha
  File.write(authorization_path, JSON.pretty_generate(effect_authorization) + "\n")
  effect_truth = Marshal.load(Marshal.dump(active_truth))
  effect_truth["active_work"]["current_task_contract_sha256"] = effect_contract_sha
  effect_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), effect_truth)
  run_validator(root, false, "Contract authorization effect mismatch negative")

  nonboolean_contract = Marshal.load(Marshal.dump(contract))
  nonboolean_contract["delegated_authority"]["external_effects"]["network"] = "yes"
  write_yaml(contract_path, nonboolean_contract)
  nonboolean_sha = Digest::SHA256.file(contract_path).hexdigest
  nonboolean_authorization = Marshal.load(Marshal.dump(authorization))
  nonboolean_authorization["task_contract_sha256"] = nonboolean_sha
  nonboolean_authorization["external_effects"]["network"] = "yes"
  File.write(authorization_path, JSON.pretty_generate(nonboolean_authorization) + "\n")
  nonboolean_truth = Marshal.load(Marshal.dump(active_truth))
  nonboolean_truth["active_work"]["current_task_contract_sha256"] = nonboolean_sha
  nonboolean_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), nonboolean_truth)
  run_validator(root, false, "non-boolean external effect negative")

  immutable_scope = Marshal.load(Marshal.dump(contract))
  immutable_scope["allowed_paths"]["worker"] = ["docs/aios/STRATEGIC_CONSTITUTION.md"]
  write_yaml(contract_path, immutable_scope)
  immutable_sha = Digest::SHA256.file(contract_path).hexdigest
  immutable_authorization = Marshal.load(Marshal.dump(authorization))
  immutable_authorization["task_contract_sha256"] = immutable_sha
  File.write(authorization_path, JSON.pretty_generate(immutable_authorization) + "\n")
  immutable_truth = Marshal.load(Marshal.dump(active_truth))
  immutable_truth["active_work"]["current_task_contract_sha256"] = immutable_sha
  immutable_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), immutable_truth)
  run_validator(root, false, "immutable authority scope negative")

  self_contract_scope = Marshal.load(Marshal.dump(contract))
  self_contract_scope["allowed_paths"]["integration"] = [contract_rel]
  write_yaml(contract_path, self_contract_scope)
  self_contract_sha = Digest::SHA256.file(contract_path).hexdigest
  self_contract_authorization = Marshal.load(Marshal.dump(authorization))
  self_contract_authorization["task_contract_sha256"] = self_contract_sha
  File.write(authorization_path, JSON.pretty_generate(self_contract_authorization) + "\n")
  self_contract_truth = Marshal.load(Marshal.dump(active_truth))
  self_contract_truth["active_work"]["current_task_contract_sha256"] = self_contract_sha
  self_contract_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), self_contract_truth)
  run_validator(root, false, "self-modifying Task Contract scope negative")

  role_overlap_contract = Marshal.load(Marshal.dump(contract))
  role_overlap_contract["allowed_paths"]["worker"] = ["evaluation-harness/fixtures/worker-owned/**"]
  role_overlap_contract["allowed_paths"]["quality"] = ["evaluation-harness/fixtures/**"]
  write_yaml(contract_path, role_overlap_contract)
  role_overlap_sha = Digest::SHA256.file(contract_path).hexdigest
  role_overlap_authorization = Marshal.load(Marshal.dump(authorization))
  role_overlap_authorization["task_contract_sha256"] = role_overlap_sha
  File.write(authorization_path, JSON.pretty_generate(role_overlap_authorization) + "\n")
  role_overlap_truth = Marshal.load(Marshal.dump(active_truth))
  role_overlap_truth["active_work"]["current_task_contract_sha256"] = role_overlap_sha
  role_overlap_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), role_overlap_truth)
  run_validator(root, false, "cross-role write overlap negative")

  parent_scope = Marshal.load(Marshal.dump(contract))
  parent_scope["allowed_paths"]["worker"] = [".."]
  write_yaml(contract_path, parent_scope)
  parent_sha = Digest::SHA256.file(contract_path).hexdigest
  parent_authorization = Marshal.load(Marshal.dump(authorization))
  parent_authorization["task_contract_sha256"] = parent_sha
  File.write(authorization_path, JSON.pretty_generate(parent_authorization) + "\n")
  parent_truth = Marshal.load(Marshal.dump(active_truth))
  parent_truth["active_work"]["current_task_contract_sha256"] = parent_sha
  parent_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), parent_truth)
  run_validator(root, false, "parent scope alias negative")

  glob_escape_contract = Marshal.load(Marshal.dump(contract))
  glob_escape_contract["allowed_paths"]["worker"] = ["evaluation-harness/**/../../docs/aios/STRATEGIC_CONSTITUTION.md"]
  write_yaml(contract_path, glob_escape_contract)
  glob_escape_sha = Digest::SHA256.file(contract_path).hexdigest
  glob_escape_authorization = Marshal.load(Marshal.dump(authorization))
  glob_escape_authorization["task_contract_sha256"] = glob_escape_sha
  File.write(authorization_path, JSON.pretty_generate(glob_escape_authorization) + "\n")
  glob_escape_truth = Marshal.load(Marshal.dump(active_truth))
  glob_escape_truth["active_work"]["current_task_contract_sha256"] = glob_escape_sha
  glob_escape_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), glob_escape_truth)
  run_validator(root, false, "glob traversal scope negative")

  remediation_contract = Marshal.load(Marshal.dump(contract))
  remediation_contract["lineage"]["remediates"] = ["AIOS-P1-899_STOPPED"]
  write_yaml(contract_path, remediation_contract)
  remediation_sha = Digest::SHA256.file(contract_path).hexdigest
  remediation_authorization = Marshal.load(Marshal.dump(authorization))
  remediation_authorization["task_contract_sha256"] = remediation_sha
  File.write(authorization_path, JSON.pretty_generate(remediation_authorization) + "\n")
  remediation_truth = Marshal.load(Marshal.dump(active_truth))
  remediation_truth["active_work"]["current_task_contract_sha256"] = remediation_sha
  remediation_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), remediation_truth)
  run_validator(root, false, "remediation lineage negative")

  terminal_dependency_contract = Marshal.load(Marshal.dump(contract))
  terminal_dependency_contract["dependencies"] = ["AIOS-P1-899_TERMINAL_DEPENDENCY"]
  write_yaml(contract_path, terminal_dependency_contract)
  terminal_dependency_sha = Digest::SHA256.file(contract_path).hexdigest
  terminal_dependency_authorization = Marshal.load(Marshal.dump(authorization))
  terminal_dependency_authorization["task_contract_sha256"] = terminal_dependency_sha
  File.write(authorization_path, JSON.pretty_generate(terminal_dependency_authorization) + "\n")
  terminal_dependency_truth = Marshal.load(Marshal.dump(active_truth))
  terminal_dependency_truth["task_history"]["terminal_dependency"] = {
    "task_id" => "AIOS-P1-899_TERMINAL_DEPENDENCY",
    "status" => "TERMINAL_STOPPED",
    "resume_retry_successor_allowed" => false
  }
  terminal_dependency_truth["active_work"]["current_task_contract_sha256"] = terminal_dependency_sha
  terminal_dependency_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), terminal_dependency_truth)
  run_validator(root, false, "terminal Task dependency negative")

  unknown_dependency_contract = Marshal.load(Marshal.dump(contract))
  unknown_dependency_contract["dependencies"] = ["AIOS-P1-898_UNKNOWN_DEPENDENCY"]
  write_yaml(contract_path, unknown_dependency_contract)
  unknown_dependency_sha = Digest::SHA256.file(contract_path).hexdigest
  unknown_dependency_authorization = Marshal.load(Marshal.dump(authorization))
  unknown_dependency_authorization["task_contract_sha256"] = unknown_dependency_sha
  File.write(authorization_path, JSON.pretty_generate(unknown_dependency_authorization) + "\n")
  unknown_dependency_truth = Marshal.load(Marshal.dump(active_truth))
  unknown_dependency_truth["active_work"]["current_task_contract_sha256"] = unknown_dependency_sha
  unknown_dependency_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), unknown_dependency_truth)
  run_validator(root, false, "unknown dependency negative")

  deferred_contract = Marshal.load(Marshal.dump(contract))
  deferred_contract["capabilities"] = ["SUPERVISOR"]
  write_yaml(contract_path, deferred_contract)
  deferred_sha = Digest::SHA256.file(contract_path).hexdigest
  deferred_authorization = Marshal.load(Marshal.dump(authorization))
  deferred_authorization["task_contract_sha256"] = deferred_sha
  File.write(authorization_path, JSON.pretty_generate(deferred_authorization) + "\n")
  deferred_truth = Marshal.load(Marshal.dump(active_truth))
  deferred_truth["active_work"]["current_task_contract_sha256"] = deferred_sha
  deferred_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), deferred_truth)
  run_validator(root, false, "deferred P3 capability negative")

  write_yaml(contract_path, contract)
  File.write(authorization_path, JSON.pretty_generate(authorization) + "\n")
  created_without_resources = Marshal.load(Marshal.dump(active_truth))
  created_without_resources["active_work"]["task_resource_state"] = "CREATED"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), created_without_resources)
  run_validator(root, false, "missing created resources negative")

  run!("git", "worktree", "add", "-b", task_branch, task_worktree, "HEAD", chdir: root)
  created_truth = Marshal.load(Marshal.dump(active_truth))
  created_truth["active_work"]["task_resource_state"] = "CREATED"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), created_truth)
  run_validator(root, true, "active CREATED positive")
  review_truth = Marshal.load(Marshal.dump(created_truth))
  review_truth["active_work"]["current_task_status"] = "REVIEW"
  review_truth["active_work"]["task_resource_state"] = "REVIEW"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), review_truth)
  run_validator(root, true, "active REVIEW positive")
  empty_tree = run!("git", "hash-object", "-t", "tree", "/dev/null", chdir: root)
  orphan_commit = run!("git", "commit-tree", empty_tree, "-m", "unrelated root", chdir: root)
  run!("git", "update-ref", "refs/heads/#{task_branch}", orphan_commit, chdir: root)
  run_validator(root, false, "unrelated Task branch ancestry negative")
  run!("git", "update-ref", "refs/heads/#{task_branch}", "HEAD", chdir: root)
  run!("git", "branch", "task/AIOS-P1-901-unexpected", chdir: root)
  run_validator(root, false, "second Task branch negative")
  run!("git", "branch", "-D", "task/AIOS-P1-901-unexpected", chdir: root)

  outside = File.join(root, "outside-authorization.json")
  File.write(outside, JSON.pretty_generate(authorization) + "\n")
  File.unlink(authorization_path)
  File.symlink(outside, authorization_path)
  symlink_truth = Marshal.load(Marshal.dump(active_truth))
  symlink_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(outside).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), symlink_truth)
  run_validator(root, false, "authorization symlink escape negative")
end

Dir.mktmpdir("aios-integrated-route-") do |root|
  initialize_synthetic_authority_repo!(root, "8ff44537dcc96b52260365f2a3f28175a0541e4f")

  truth = YAML.safe_load(File.read(File.join(root, "docs/aios/truth/project_state.yaml")), aliases: false)
  current_source_truth = YAML.safe_load(File.read(File.join(SOURCE_ROOT, "docs/aios/truth/project_state.yaml")), aliases: false)
  truth["mandatory_exit_capability_recovery"]["historical_governance_metadata_read_boundary"] =
    Marshal.load(Marshal.dump(current_source_truth.dig("mandatory_exit_capability_recovery", "historical_governance_metadata_read_boundary")))
  worktree_root = File.join(root, "task-worktrees")
  FileUtils.mkdir_p(worktree_root)
  truth["project"]["canonical_repository"] = root
  truth["project"]["task_worktree_root"] = worktree_root
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  run_validator(root, true, "integrated route current sync positive")

  route_id = truth.dig("mandatory_exit_capability_recovery", "integrated_capability_routes").keys.fetch(0)
  route = truth.dig("mandatory_exit_capability_recovery", "integrated_capability_routes", route_id)
  evidence_base = truth.dig("project", "execution_evidence_root_base")

  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  run!("git", "add", "docs/aios/truth/project_state.yaml", "scripts/validate-current-task-authority.rb", chdir: root)
  run!("git", "commit", "-m", "sync integrated route", chdir: root)
  activation_parent = run!("git", "rev-parse", "HEAD", chdir: root)
  activation_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)

  removed_route = Marshal.load(Marshal.dump(truth))
  removed_route["mandatory_exit_capability_recovery"]["integrated_capability_routes"] = {}
  removed_route["mandatory_exit_capability_recovery"]["capability_status"]["HIDDEN_SET_PROTOCOL"] = "CONTRACT_REVIEW_BLOCKED"
  removed_route["active_work"]["founder_decision_required"] = true
  removed_route["active_work"]["escalation_reason"] = "mandatory_exit_capability_blocked"
  removed_route["active_work"]["user_action_required"] = "FOUNDER_DECISION_REQUIRED"
  removed_route["active_work"]["next_eligible_action"] = "WAIT_FOR_FOUNDER_MANDATORY_EXIT_CAPABILITY_DECISION"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), removed_route)
  run_validator(root, false, "integrated route removal negative", expected_failure: "integrated capability route was removed, replaced, renamed or rebound")

  rebound_route = Marshal.load(Marshal.dump(truth))
  rebound_value = rebound_route["mandatory_exit_capability_recovery"]["integrated_capability_routes"].delete(route_id)
  rebound_route["mandatory_exit_capability_recovery"]["integrated_capability_routes"]["P1_099_REBOUND_ROUTE"] = rebound_value
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), rebound_route)
  run_validator(root, false, "integrated route rebind negative", expected_failure: "integrated capability route was removed, replaced, renamed or rebound")

  second_route = Marshal.load(Marshal.dump(truth))
  second_route["mandatory_exit_capability_recovery"]["integrated_capability_routes"]["P1_099_SECOND_ROUTE"] = Marshal.load(Marshal.dump(route))
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), second_route)
  run_validator(root, false, "second integrated route negative", expected_failure: "integrated capability route map invalid")

  decision_drift = Marshal.load(Marshal.dump(truth))
  decision_drift["mandatory_exit_capability_recovery"]["integrated_capability_routes"][route_id]["decision_record_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), decision_drift)
  run_validator(root, false, "integrated route decision hash drift negative", expected_failure: "integrated capability route was removed, replaced, renamed or rebound")

  ledger_mutation = Marshal.load(Marshal.dump(truth))
  ledger_mutation["mandatory_exit_capability_recovery"]["capability_attempt_ledger"]["HIDDEN_SET_PROTOCOL"]["founder_exception_terminal_record_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), ledger_mutation)
  run_validator(root, false, "P1-036 ledger mutation negative", expected_failure: "integrated capability route does not preserve blocked ledger")

  current_route_states = route["mandatory_exit_capabilities"].map do |capability|
    truth.dig("mandatory_exit_capability_recovery", "capability_status", capability)
  end
  if current_route_states == ["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"]
    partial_terminal = Marshal.load(Marshal.dump(truth))
    partial_terminal["mandatory_exit_capability_recovery"]["capability_status"][route["mandatory_exit_capabilities"].first] = "RELOCATED_PENDING_INTEGRATED_TASK"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_terminal)
    run_validator(root, false, "partial integrated terminal state negative", expected_failure: "integrated capability route current state population is not atomic")

    terminal_reactivation = Marshal.load(Marshal.dump(truth))
    route["mandatory_exit_capabilities"].each do |capability|
      terminal_reactivation["mandatory_exit_capability_recovery"]["capability_status"][capability] = "IN_PROGRESS"
    end
    terminal_reactivation["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][route["primary_capability"]]["status"] = "ACTIVE"
    terminal_reactivation["active_work"]["founder_decision_required"] = false
    terminal_reactivation["active_work"]["escalation_reason"] = nil
    terminal_reactivation["active_work"]["user_action_required"] = nil
    terminal_reactivation["active_work"]["next_eligible_action"] = "MASTER_AUTONOMOUSLY_EXECUTE_CURRENT_TASK"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), terminal_reactivation)
    run_validator(root, false, "terminal integrated route reactivation negative", expected_failure: "mandatory Exit capability status transition invalid")
    next
  end

  if current_route_states == ["FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION", "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"]
    partial_recalibration = Marshal.load(Marshal.dump(truth))
    partial_recalibration["mandatory_exit_capability_recovery"]["capability_status"][route["mandatory_exit_capabilities"].first] = "CONTRACT_REVIEW_BLOCKED"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_recalibration)
    run_validator(root, false, "partial Founder recalibration negative", expected_failure: "integrated capability route current state population is not atomic")

    removed_final_route = Marshal.load(Marshal.dump(truth))
    removed_final_route["mandatory_exit_capability_recovery"]["final_clean_room_implementation_route"] = nil
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), removed_final_route)
    run_validator(root, false, "final clean-room route removal negative")
    next
  end

  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)

  Dir.mktmpdir("p1-037-contract-review-terminal-", evidence_base) do |terminal_root|
    failure_path = File.join(terminal_root, "CONTRACT_REVIEW_FAILURE.json")
    failure = {
      "record_type" => "aios_p1_mandatory_capability_contract_review_failure",
      "status" => "CONTRACT_REVIEW_BLOCKED",
      "task_id" => route["task_id"],
      "mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
      "attempt_ordinal" => 1,
      "founder_escalation_required" => true,
      "final_review_result" => "NON_PASS"
    }
    write_json(failure_path, failure)

    review_blocked_truth = Marshal.load(Marshal.dump(truth))
    route["mandatory_exit_capabilities"].each do |capability|
      review_blocked_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "CONTRACT_REVIEW_BLOCKED"
    end
    unless review_blocked_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][route["primary_capability"]].is_a?(Hash)
      review_blocked_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][route["primary_capability"]] = {
        "status" => "CONTRACT_REVIEW_BLOCKED",
        "task_id" => route["task_id"],
        "attempt_ordinal" => 1,
        "contract_sha256" => "1" * 64,
        "bounded_contract_corrections_used" => 1,
        "integrated_mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
        "founder_architecture_route_id" => route_id,
        "founder_escalation_required" => true,
        "failure_record_path" => failure_path,
        "failure_record_sha256" => Digest::SHA256.file(failure_path).hexdigest
      }
    end
    review_blocked_truth["active_work"]["founder_decision_required"] = true
    review_blocked_truth["active_work"]["escalation_reason"] = "mandatory_exit_capability_blocked"
    review_blocked_truth["active_work"]["user_action_required"] = "FOUNDER_DECISION_REQUIRED"
    review_blocked_truth["active_work"]["next_eligible_action"] = "WAIT_FOR_FOUNDER_MANDATORY_EXIT_CAPABILITY_DECISION"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), review_blocked_truth)
    run_validator(root, false, "unallowlisted integrated contract-review record negative", expected_failure: "is not admitted by one exact historical metadata record")

    partial_review_blocked = Marshal.load(Marshal.dump(review_blocked_truth))
    partial_review_blocked["mandatory_exit_capability_recovery"]["capability_status"][route["mandatory_exit_capabilities"].first] = "RELOCATED_PENDING_INTEGRATED_TASK"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_review_blocked)
    run_validator(root, false, "partial integrated CONTRACT_REVIEW_BLOCKED negative", expected_failure: "integrated capability route current state population is not atomic")
  end

  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  Dir.mktmpdir("p1-037-authority-test-", evidence_base) do |evidence_root|
    task_id = route["task_id"]
    task_branch = "task/AIOS-P1-037-integrated-authority-test"
    task_worktree = File.join(worktree_root, "AIOS-P1-037-integrated-authority-test")
    contract_rel = "docs/aios/tasks/P1-037_INTEGRATED_AUTHORITY_TEST.yaml"
    contract_path = File.join(root, contract_rel)
    contract = {
      "schema_version" => 1,
      "task_id" => task_id,
      "phase" => "P1",
      "status" => "READY_FOR_PHASE_DELEGATED_EXECUTION",
      "execution_authority" => "PHASE_DELEGATED",
      "objective" => "Verify the exact Founder-approved integrated capability route.",
      "why_now" => ["The route must activate both capabilities atomically."],
      "task_spec_ref" => "synthetic://p1-037-integrated-route-test",
      "read_context" => ["docs/aios/FOUNDER_DELEGATION_POLICY.md"],
      "dependencies" => ["AIOS-P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET"],
      "mandatory_exit_capability" => route["primary_capability"],
      "integrated_mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
      "founder_architecture_route_id" => route_id,
      "clean_room_recovery" => {
        "historical_execution_lineage_reused" => false,
        "attempt_ordinal" => 1,
        "bounded_contract_corrections_allowed" => 1,
        "bounded_contract_corrections_used" => 0,
        "original_contract_path" => nil,
        "original_contract_sha256" => nil
      },
      "task_kind" => "EVALUATION_FOUNDATION_ENGINEERING",
      "capabilities" => ["EVALUATOR_AND_ORACLE", "LOCAL_SYNTHETIC_DATASET"],
      "capability_claim" => false,
      "risk_level" => "medium",
      "lineage" => { "kind" => "INDEPENDENT_PHASE_INCREMENT", "retries" => [], "remediates" => [], "supersedes" => [] },
      "roles" => {
        "accountable_owner" => "Engineering Manager Agent",
        "worker" => "Integrated Route Worker",
        "independent_reviewers" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
      },
      "allowed_paths" => {
        "worker" => ["evaluation-harness/harness/p1-037-test/**"],
        "quality" => ["evaluation-harness/fixtures/p1-037-test/**"],
        "external_evidence" => ["#{evidence_root}/**"]
      },
      "forbidden_actions" => ["network", "Provider", "Secret", "remote", "production", "public effect"],
      "budget" => { "engineering_hours" => 1, "implementation_iterations" => 1, "execution_retries" => 0, "network_calls" => 0 },
      "acceptance_criteria" => ["both capabilities transition atomically"],
      "failure_criteria" => ["either capability transitions alone"],
      "stop_conditions" => ["the exact route binding drifts"],
      "evidence" => { "required" => ["authority validator result"] },
      "rollback" => { "method" => "delete the unmerged synthetic worktree" },
      "claim_boundary" => route["claim_boundary"],
      "delegated_authority" => {
        "phase_local" => true,
        "task_gate_owner" => "MASTER_CEO_AGENT",
        "founder_gate" => "RESERVED_DECISIONS_ONLY",
        "founder_reserved_decisions" => [],
        "external_effects" => { "network" => false, "provider" => false, "secret" => false, "remote" => false, "production" => false, "public" => false }
      }
    }
    write_yaml(contract_path, contract)
    contract_sha = Digest::SHA256.file(contract_path).hexdigest
    authorization_id = Digest::SHA256.hexdigest("#{task_id}:#{contract_sha}:#{activation_parent}")
    authorization_path = File.join(evidence_root, "PHASE_DELEGATED_AUTHORIZATION.json")
    authorization = {
      "record_type" => "aios_phase_delegated_task_authorization",
      "status" => "ACTIVE",
      "authority" => "MASTER_CEO_AGENT",
      "delegation_model" => "PHASE_LEVEL_FOUNDER_DELEGATION",
      "authorization_id" => authorization_id,
      "task_id" => task_id,
      "phase" => "P1",
      "task_contract_sha256" => contract_sha,
      "goal_canonical_sha256" => truth.dig("goal", "observed_body_sha256"),
      "parent_commit" => activation_parent,
      "parent_tree" => activation_tree,
      "integrated_mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
      "founder_architecture_route_id" => route_id,
      "external_effects" => contract.dig("delegated_authority", "external_effects"),
      "founder_reserved_decisions" => [],
      "founder_reserved_decision_required" => false
    }
    File.write(authorization_path, JSON.pretty_generate(authorization) + "\n")

    active_truth = Marshal.load(Marshal.dump(truth))
    active_truth["goal"]["current_task_authority"] = task_id
    active_truth["project"]["phase_execution_status"] = "TASK_ACTIVE"
    active_truth["project"]["p1_execution_status"] = "TASK_ACTIVE"
    route["mandatory_exit_capabilities"].each do |capability|
      active_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "IN_PROGRESS"
    end
    active_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][route["primary_capability"]] = {
      "status" => "ACTIVE",
      "task_id" => task_id,
      "attempt_ordinal" => 1,
      "contract_sha256" => contract_sha,
      "bounded_contract_corrections_used" => 0,
      "integrated_mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
      "founder_architecture_route_id" => route_id
    }
    active_truth["active_work"] = {
      "current_task" => task_id,
      "current_task_status" => "AUTHORIZED_ACTIVE",
      "current_task_contract" => contract_rel,
      "current_task_contract_sha256" => contract_sha,
      "current_execution_authorization" => authorization_path,
      "current_execution_authorization_sha256" => Digest::SHA256.file(authorization_path).hexdigest,
      "execution_nonce" => nil,
      "execution_nonce_status" => "NOT_REQUIRED_PHASE_DELEGATION",
      "authorization_id" => authorization_id,
      "activation_parent_commit" => activation_parent,
      "activation_parent_tree" => activation_tree,
      "task_resource_state" => "DECLARED",
      "task_branch" => task_branch,
      "task_worktree" => task_worktree,
      "execution_evidence_root" => evidence_root,
      "offsite_target" => nil,
      "founder_reserved_authorization" => nil,
      "founder_reserved_authorization_sha256" => nil,
      "founder_decision_required" => false,
      "escalation_reason" => nil,
      "user_action_required" => nil,
      "next_eligible_action" => "MASTER_AUTONOMOUSLY_EXECUTE_CURRENT_TASK"
    }
    active_truth["phase_execution_claim"]["current_task_claim"] = task_id
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), active_truth)
    run!("git", "add", contract_rel, "docs/aios/truth/project_state.yaml", chdir: root)
    run!("git", "commit", "-m", "activate integrated route test", chdir: root)
    run_validator(root, true, "integrated dual activation positive")

    partial_in_progress = Marshal.load(Marshal.dump(active_truth))
    partial_in_progress["mandatory_exit_capability_recovery"]["capability_status"][route["mandatory_exit_capabilities"].first] = "RELOCATED_PENDING_INTEGRATED_TASK"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_in_progress)
    run_validator(root, false, "partial integrated IN_PROGRESS negative", expected_failure: "integrated capability route current state population is not atomic")

    candidate_commit = run!("git", "rev-parse", "HEAD", chdir: root)
    candidate_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
    result_path = File.join(evidence_root, "result.txt")
    File.write(result_path, "integrated route acceptance test\n")
    artifact_index_path = File.join(evidence_root, "ARTIFACT_INDEX.json")
    artifact_index = {
      "record_type" => "aios_p1_mandatory_capability_artifact_index",
      "status" => "FROZEN",
      "task_id" => task_id,
      "mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
      "candidate_commit" => candidate_commit,
      "candidate_tree" => candidate_tree,
      "artifacts" => [{
        "path" => "result.txt",
        "sha256" => Digest::SHA256.file(result_path).hexdigest,
        "byte_length" => File.size(result_path)
      }]
    }
    write_json(artifact_index_path, artifact_index)
    artifact_index_sha = Digest::SHA256.file(artifact_index_path).hexdigest
    manifest_path = File.join(evidence_root, "EVIDENCE_MANIFEST.json")
    manifest = {
      "record_type" => "aios_p1_mandatory_capability_evidence_manifest",
      "status" => "FROZEN",
      "task_id" => task_id,
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => candidate_commit,
      "candidate_tree" => candidate_tree,
      "artifact_index_path" => artifact_index_path,
      "artifact_index_sha256" => artifact_index_sha,
      "replay_result" => "PASS",
      "rebuild_result" => "PASS",
      "rollback_result" => "PASS",
      "claim_boundary" => route["claim_boundary"],
      "mandatory_exit_capabilities" => route["mandatory_exit_capabilities"]
    }
    write_json(manifest_path, manifest)
    manifest_sha = Digest::SHA256.file(manifest_path).hexdigest
    review_paths = {}
    review_hashes = {}
    %w[cto security quality].each do |role|
      review_path = File.join(evidence_root, "#{role.upcase}_REVIEW.json")
      review = {
        "record_type" => "aios_independent_task_review",
        "status" => "PASS",
        "role" => role.upcase,
        "task_id" => task_id,
        "task_contract_sha256" => contract_sha,
        "candidate_commit" => candidate_commit,
        "candidate_tree" => candidate_tree,
        "evidence_manifest_sha256" => manifest_sha,
        "claim_boundary" => route["claim_boundary"],
        "mandatory_exit_capabilities" => route["mandatory_exit_capabilities"]
      }
      write_json(review_path, review)
      review_paths[role] = review_path
      review_hashes[role] = Digest::SHA256.file(review_path).hexdigest
    end
    gate_path = File.join(evidence_root, "TASK_GATE_RECEIPT.json")
    gate = {
      "record_type" => "aios_phase_delegated_task_gate_receipt",
      "status" => "ACCEPTED",
      "authority" => "MASTER_CEO_AGENT",
      "task_id" => task_id,
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => candidate_commit,
      "candidate_tree" => candidate_tree,
      "evidence_manifest_sha256" => manifest_sha,
      "cto_review_sha256" => review_hashes["cto"],
      "security_review_sha256" => review_hashes["security"],
      "quality_review_sha256" => review_hashes["quality"],
      "claim_boundary" => route["claim_boundary"],
      "mandatory_exit_capabilities" => route["mandatory_exit_capabilities"]
    }
    write_json(gate_path, gate)

    none_active_work = Marshal.load(Marshal.dump(truth["active_work"]))
    accepted_truth = Marshal.load(Marshal.dump(active_truth))
    route["mandatory_exit_capabilities"].each do |capability|
      accepted_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "ACCEPTED"
    end
    accepted_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][route["primary_capability"]]["status"] = "ACCEPTED"
    accepted_truth["task_history"]["integrated_route_accepted"] = {
      "task_id" => task_id,
      "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      "mandatory_exit_capability" => route["primary_capability"],
      "integrated_mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
      "founder_architecture_route_id" => route_id,
      "clean_room_attempt_ordinal" => 1,
      "task_gate_result" => "PASS",
      "task_contract_sha256" => contract_sha,
      "bounded_contract_corrections_used" => 0,
      "accepted_candidate_commit" => candidate_commit,
      "accepted_candidate_tree" => candidate_tree,
      "execution_evidence_root" => evidence_root,
      "evidence_manifest_path" => manifest_path,
      "evidence_manifest_sha256" => manifest_sha,
      "artifact_index_path" => artifact_index_path,
      "artifact_index_sha256" => artifact_index_sha,
      "cto_review_path" => review_paths["cto"],
      "cto_review_sha256" => review_hashes["cto"],
      "security_review_path" => review_paths["security"],
      "security_review_sha256" => review_hashes["security"],
      "quality_review_path" => review_paths["quality"],
      "quality_review_sha256" => review_hashes["quality"],
      "task_gate_receipt_path" => gate_path,
      "task_gate_receipt_sha256" => Digest::SHA256.file(gate_path).hexdigest,
      "claim_boundary" => route["claim_boundary"]
    }
    accepted_truth["goal"]["current_task_authority"] = "NONE"
    accepted_truth["project"]["phase_execution_status"] = "NO_CURRENT_TASK"
    accepted_truth["project"]["p1_execution_status"] = "NO_CURRENT_TASK"
    accepted_truth["active_work"] = none_active_work
    accepted_truth["active_work"]["next_eligible_action"] = "MASTER_AUTONOMOUSLY_IMPLEMENT_P1_EXIT_CAPABILITIES_IN_FROZEN_PRIORITY_ORDER"
    accepted_truth["phase_execution_claim"]["current_task_claim"] = "NO_CURRENT_TASK"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), accepted_truth)
    run_validator(root, true, "integrated dual ACCEPTED positive")

    partial_accepted = Marshal.load(Marshal.dump(accepted_truth))
    partial_accepted["mandatory_exit_capability_recovery"]["capability_status"][route["mandatory_exit_capabilities"].first] = "IN_PROGRESS"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_accepted)
    run_validator(root, false, "partial integrated ACCEPTED negative", expected_failure: "integrated capability route current state population is not atomic")

    terminal_manifest_path = File.join(evidence_root, "TERMINAL_EVIDENCE_MANIFEST.json")
    terminal_manifest = {
      "record_type" => "aios_p1_mandatory_capability_terminal_evidence_manifest",
      "status" => "TERMINAL_STOPPED_REAL_ARCHITECTURE_ROOT",
      "task_id" => task_id,
      "attempt_ordinal" => 1,
      "task_contract_sha256" => contract_sha,
      "bounded_contract_corrections_used" => 0,
      "failure_classification" => "REAL_ARCHITECTURE_ROOT",
      "mandatory_exit_capabilities" => route["mandatory_exit_capabilities"]
    }
    write_json(terminal_manifest_path, terminal_manifest)
    architecture_blocked_truth = Marshal.load(Marshal.dump(active_truth))
    route["mandatory_exit_capabilities"].each do |capability|
      architecture_blocked_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "ARCHITECTURE_BLOCKED"
    end
    architecture_blocked_truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][route["primary_capability"]]["status"] = "ARCHITECTURE_BLOCKED"
    architecture_blocked_truth["task_history"]["integrated_route_architecture_blocked"] = {
      "task_id" => task_id,
      "status" => "TERMINAL_STOPPED_REAL_ARCHITECTURE_ROOT",
      "mandatory_exit_capability" => route["primary_capability"],
      "integrated_mandatory_exit_capabilities" => route["mandatory_exit_capabilities"],
      "founder_architecture_route_id" => route_id,
      "clean_room_attempt_ordinal" => 1,
      "execution_evidence_root" => evidence_root,
      "founder_escalation_required" => true,
      "terminal_evidence" => {
        "evidence_manifest_path" => terminal_manifest_path,
        "evidence_manifest_sha256" => Digest::SHA256.file(terminal_manifest_path).hexdigest
      }
    }
    architecture_blocked_truth["goal"]["current_task_authority"] = "NONE"
    architecture_blocked_truth["project"]["phase_execution_status"] = "NO_CURRENT_TASK"
    architecture_blocked_truth["project"]["p1_execution_status"] = "NO_CURRENT_TASK"
    architecture_blocked_truth["active_work"] = none_active_work
    architecture_blocked_truth["active_work"]["founder_decision_required"] = true
    architecture_blocked_truth["active_work"]["escalation_reason"] = "mandatory_exit_capability_blocked"
    architecture_blocked_truth["active_work"]["user_action_required"] = "FOUNDER_DECISION_REQUIRED"
    architecture_blocked_truth["active_work"]["next_eligible_action"] = "WAIT_FOR_FOUNDER_MANDATORY_EXIT_CAPABILITY_DECISION"
    architecture_blocked_truth["phase_execution_claim"]["current_task_claim"] = "NO_CURRENT_TASK"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), architecture_blocked_truth)
    run_validator(root, true, "integrated dual ARCHITECTURE_BLOCKED positive")

    partial_architecture_blocked = Marshal.load(Marshal.dump(architecture_blocked_truth))
    partial_architecture_blocked["mandatory_exit_capability_recovery"]["capability_status"][route["mandatory_exit_capabilities"].first] = "IN_PROGRESS"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_architecture_blocked)
    run_validator(root, false, "partial integrated ARCHITECTURE_BLOCKED negative", expected_failure: "integrated capability route current state population is not atomic")

    route_reuse = Marshal.load(Marshal.dump(accepted_truth))
    route_reuse["active_work"]["current_task"] = task_id
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), route_reuse)
    run_validator(root, false, "integrated route reuse negative", expected_failure: "integrated capability route was reused")
  end
end

Dir.mktmpdir("aios-final-clean-room-route-") do |root|
  truth_relative_path = "docs/aios/truth/project_state.yaml"
  current_truth_bytes = source_tracked_bytes("HEAD", truth_relative_path)
  current_truth = YAML.safe_load(current_truth_bytes, aliases: false)
  final_route_ref = "HEAD"
  if current_truth.dig("mandatory_exit_capability_recovery", "post_revision_final_route_terminal")
    truth_commits = run!("git", "log", "--format=%H", "--", truth_relative_path, chdir: SOURCE_ROOT).lines.map(&:strip)
    final_route_ref = truth_commits.find do |commit|
      candidate = YAML.safe_load(source_tracked_bytes(commit, truth_relative_path), aliases: false)
      candidate.dig("mandatory_exit_capability_recovery", "post_revision_final_implementation_route") &&
        candidate.dig("mandatory_exit_capability_recovery", "post_revision_final_route_terminal").nil?
    end
    raise "post-revision final route pre-terminal Truth commit not found" unless final_route_ref
  end
  initialize_synthetic_authority_repo!(root, final_route_ref)

  truth = YAML.safe_load(source_tracked_bytes(final_route_ref, truth_relative_path), aliases: false)
  worktree_root = File.join(root, "task-worktrees")
  evidence_base = truth.dig("project", "execution_evidence_root_base")
  FileUtils.mkdir_p(worktree_root)
  truth["project"]["canonical_repository"] = root
  truth["project"]["task_worktree_root"] = worktree_root
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  final_terminal = truth.dig("mandatory_exit_capability_recovery", "final_clean_room_contract_review_terminal")
  if final_terminal
    run_validator(root, true, "final clean-room contract-review terminal positive")

    boundary_hash_drift = Marshal.load(Marshal.dump(truth))
    boundary_hash_drift["mandatory_exit_capability_recovery"]["historical_governance_metadata_read_boundary"]["decision_record_sha256"] = "0" * 64
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), boundary_hash_drift)
    run_validator(root, false, "historical governance boundary Founder hash negative")

    boundary_allowlist_gap = Marshal.load(Marshal.dump(truth))
    boundary_allowlist_gap["mandatory_exit_capability_recovery"]["historical_governance_metadata_read_boundary"]["allowed_records"].reject! do |entry|
      entry["record_class"] == "INDEPENDENT_CONTRACT_REVIEW" && entry["path"].end_with?("CTO_FINAL_CONTRACT_REVIEW.json")
    end
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), boundary_allowlist_gap)
    run_validator(root, false, "historical governance exact allowlist gap negative", expected_failure: "allowlist is not the exact closed set")

    boundary_allowlist_extra = Marshal.load(Marshal.dump(truth))
    boundary_allowlist_extra["mandatory_exit_capability_recovery"]["historical_governance_metadata_read_boundary"]["allowed_records"] <<
      Marshal.load(Marshal.dump(boundary_allowlist_extra.dig("mandatory_exit_capability_recovery", "historical_governance_metadata_read_boundary", "allowed_records").first)).merge(
        "path" => File.join(evidence_base, "forbidden-extra-governance-record.json")
      )
    write_json(File.join(evidence_base, "forbidden-extra-governance-record.json"), { "unexpected" => true })
    extra_entry = boundary_allowlist_extra.dig("mandatory_exit_capability_recovery", "historical_governance_metadata_read_boundary", "allowed_records").last
    extra_entry["sha256"] = Digest::SHA256.file(extra_entry["path"]).hexdigest
    extra_entry["byte_length"] = File.size(extra_entry["path"])
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), boundary_allowlist_extra)
    run_validator(root, false, "historical governance extra allowlist record negative", expected_failure: "allowlist is not the exact closed set")
    File.unlink(extra_entry["path"])

    post_revision_route_drift = Marshal.load(Marshal.dump(truth))
    post_revision_route_drift["mandatory_exit_capability_recovery"]["post_revision_final_implementation_route"]["task_id"] = "AIOS-P1-040_FORBIDDEN_FIFTH_ROUTE"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), post_revision_route_drift)
    run_validator(root, false, "post-revision route identity negative", expected_failure: "post-revision final route identity drift")

    removed_terminal = Marshal.load(Marshal.dump(truth))
    removed_terminal["mandatory_exit_capability_recovery"]["final_clean_room_contract_review_terminal"] = nil
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), removed_terminal)
    run_validator(root, false, "final clean-room terminal removal negative", expected_failure: "final clean-room contract-review terminal binding missing")

    terminal_status_drift = Marshal.load(Marshal.dump(truth))
    terminal_status_drift["mandatory_exit_capability_recovery"]["final_clean_room_contract_review_terminal"]["status"] = "ACTIVE"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), terminal_status_drift)
    run_validator(root, false, "final clean-room terminal status drift negative", expected_failure: "final clean-room contract-review terminal route binding drift")

    partial_terminal = Marshal.load(Marshal.dump(truth))
    capability = final_terminal.fetch("mandatory_exit_capabilities").first
    partial_terminal["mandatory_exit_capability_recovery"]["capability_status"][capability] = "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_terminal)
    run_validator(root, false, "partial final clean-room terminal projection negative", expected_failure: "final clean-room terminal capability projection drift")

    consumed_attempt = Marshal.load(Marshal.dump(truth))
    consumed_attempt["mandatory_exit_capability_recovery"]["final_clean_room_contract_review_terminal"]["implementation_attempt_consumed"] = true
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), consumed_attempt)
    run_validator(root, false, "final clean-room terminal implementation consumption negative", expected_failure: "final clean-room terminal safety rule drift")

    review_hash_drift = Marshal.load(Marshal.dump(truth))
    review_hash_drift["mandatory_exit_capability_recovery"]["final_clean_room_contract_review_terminal"]["cto_review_sha256"] = "0" * 64
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), review_hash_drift)
    run_validator(root, false, "final clean-room terminal review binding negative")
  end

  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  run_validator(root, true, "post-revision final route pending positive")

  silent_phase_expansion = Marshal.load(Marshal.dump(truth))
  silent_phase_expansion["phase_boundary"]["allowed_capabilities"] << "AGENT_SHELL"
  silent_phase_expansion["phase_boundary"]["deferred_capabilities"].delete("AGENT_SHELL")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), silent_phase_expansion)
  run_validator(root, false, "NONE transition cannot silently expand Phase capability negative", expected_failure: "immutable control surface changed: phase_boundary")

  silent_phase_claim_expansion = Marshal.load(Marshal.dump(truth))
  silent_phase_claim_expansion["phase_execution_claim"]["forbidden_without_separate_founder_authority"] = []
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), silent_phase_claim_expansion)
  run_validator(root, false, "NONE transition cannot silently expand Phase execution claim negative", expected_failure: "immutable control surface changed: phase_execution_claim")

  unknown_active_work_field = Marshal.load(Marshal.dump(truth))
  unknown_active_work_field["active_work"]["undeclared_authority_field"] = true
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), unknown_active_work_field)
  run_validator(root, false, "NONE active-work unknown field negative", expected_failure: "active work schema drift")

  recovery_invariant_drift = Marshal.load(Marshal.dump(truth))
  recovery_invariant_drift["mandatory_exit_capability_recovery"]["clean_room_rules"] << "allow_historical_asset_reuse"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), recovery_invariant_drift)
  run_validator(root, false, "mandatory recovery invariant drift negative", expected_failure: "mandatory Exit capability recovery invariant surface changed")

  founder_class_projection_drift = Marshal.load(Marshal.dump(truth))
  founder_class_projection_drift["mandatory_exit_capability_recovery"]["historical_governance_metadata_read_boundary"]["founder_allowed_record_classes"] << "UNDECLARED_CLASS"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), founder_class_projection_drift)
  run_validator(root, false, "historical Founder class projection negative", expected_failure: "Founder class projection drift")

  historical_semantic_projection = Marshal.load(Marshal.dump(truth))
  historical_semantic_projection["mandatory_exit_capability_recovery"]["historical_governance_metadata_read_boundary"]["allowed_records"].first["projected_semantic_json_pointers"] = ["/task_id"]
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), historical_semantic_projection)
  run_validator(root, false, "historical semantic projection remains empty negative", expected_failure: "allowlist entry schema drift")

  final_route = truth.dig("mandatory_exit_capability_recovery", "post_revision_final_implementation_route") ||
    truth.dig("mandatory_exit_capability_recovery", "final_clean_room_implementation_route")
  post_revision_route = !truth.dig("mandatory_exit_capability_recovery", "post_revision_final_implementation_route").nil?
  attempt_key = post_revision_route ? "post_revision_final_implementation_attempt" : "final_clean_room_implementation_attempt"
  pending_state = post_revision_route ? "FOUNDER_REVISED_PENDING_IMPLEMENTATION" : "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"
  route_id = final_route.fetch("route_id")
  capabilities = final_route.fetch("mandatory_exit_capabilities")
  task_id = final_route.fetch("task_id")

  partial_pending = Marshal.load(Marshal.dump(truth))
  partial_pending["mandatory_exit_capability_recovery"]["capability_status"][capabilities.first] = "CONTRACT_REVIEW_BLOCKED"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_pending)
  run_validator(root, false, "partial final route pending negative")

  removed_route = Marshal.load(Marshal.dump(truth))
  removed_route["mandatory_exit_capability_recovery"][post_revision_route ? "post_revision_final_implementation_route" : "final_clean_room_implementation_route"] = nil
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), removed_route)
  run_validator(root, false, "final clean-room route removal negative")

  rebound_route = Marshal.load(Marshal.dump(truth))
  rebound_route["mandatory_exit_capability_recovery"][post_revision_route ? "post_revision_final_implementation_route" : "final_clean_room_implementation_route"]["route_id"] = "P1_FORBIDDEN_REBOUND_ROUTE"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), rebound_route)
  run_validator(root, false, "final clean-room route rebind negative")

  historical_ledger_mutation = Marshal.load(Marshal.dump(truth))
  historical_ledger_mutation["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][capabilities.first]["contract_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), historical_ledger_mutation)
  run_validator(root, false, "final route historical ledger mutation negative")

  integrated_historical_ledger_mutation = Marshal.load(Marshal.dump(truth))
  integrated_historical_ledger_mutation["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][capabilities.last].delete("failure_record_sha256")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), integrated_historical_ledger_mutation)
  run_validator(
    root,
    false,
    "final route P1-037 historical ledger field deletion negative",
    expected_failure: "final clean-room route changed historical contract-attempt ledger: #{capabilities.last}"
  )

  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  run!("git", "add", "docs/aios/truth/project_state.yaml", "scripts/validate-current-task-authority.rb", chdir: root)
  run!("git", "commit", "-m", "sync final clean-room route", chdir: root)

  if post_revision_route
    pre_activation_terminal_root = Dir.mktmpdir("p1-039-contract-terminal-test-", evidence_base)
    begin
      terminal_record_path = File.join(pre_activation_terminal_root, "P1_039_FINAL_ROUTE_TERMINAL_RECORD.json")
      terminal_record = {
        "record_type" => "sourcelens_aios_p1_post_revision_final_route_terminal_record",
        "schema_version" => "1.0",
        "status" => "P1_TERMINAL_STOPPED",
        "task_id" => task_id,
        "route_id" => route_id,
        "mandatory_exit_capabilities" => capabilities,
        "failure_stage" => "FINAL_CONTRACT_REVIEW_NON_PASS",
        "implementation_attempt_consumed" => false,
        "route_recovery_allowed" => false,
        "fifth_route_allowed" => false,
        "successor_replacement_correction_allowed" => false,
        "founder_escalation_required" => true,
        "project_level_disposition_required" => true,
        "terminal_action" => "STOP_P1_NO_FIFTH_ROUTE"
      }
      write_json(terminal_record_path, terminal_record)
      contract_terminal_truth = Marshal.load(Marshal.dump(truth))
      capabilities.each do |capability|
        contract_terminal_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "ARCHITECTURE_BLOCKED"
      end
      contract_terminal_truth["mandatory_exit_capability_recovery"]["post_revision_final_route_terminal"] = {
        "record_type" => "p1_post_revision_final_route_terminal_binding",
        "status" => "P1_TERMINAL_STOPPED",
        "task_id" => task_id,
        "route_id" => route_id,
        "mandatory_exit_capabilities" => capabilities,
        "failure_stage" => "FINAL_CONTRACT_REVIEW_NON_PASS",
        "terminal_record_path" => terminal_record_path,
        "terminal_record_sha256" => Digest::SHA256.file(terminal_record_path).hexdigest,
        "implementation_attempt_consumed" => false,
        "route_recovery_allowed" => false,
        "fifth_route_allowed" => false,
        "successor_replacement_correction_allowed" => false,
        "founder_escalation_required" => true,
        "project_level_disposition_required" => true
      }
      contract_terminal_truth["active_work"]["founder_decision_required"] = true
      contract_terminal_truth["active_work"]["escalation_reason"] = "p1_post_revision_final_route_terminal_stop"
      contract_terminal_truth["active_work"]["user_action_required"] = "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED"
      contract_terminal_truth["active_work"]["next_eligible_action"] = "STOP_P1_AND_WAIT_FOR_PROJECT_LEVEL_DISPOSITION"
      write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), contract_terminal_truth)
      run_validator(root, true, "post-revision final Contract NON_PASS terminal positive")

      terminal_reentry = Marshal.load(Marshal.dump(contract_terminal_truth))
      capabilities.each do |capability|
        terminal_reentry["mandatory_exit_capability_recovery"]["capability_status"][capability] = pending_state
      end
      write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), terminal_reentry)
      run_validator(root, false, "post-revision terminal cannot re-enter pending negative", expected_failure: "terminal capability projection is not atomic")
    ensure
      FileUtils.rm_rf(pre_activation_terminal_root)
    end
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  end

  contract_rel = post_revision_route ?
    "docs/aios/tasks/P1-039_MINIMAL_HIDDEN_ADMISSION_PARAMETERIZED_HARNESS_IMPLEMENTATION.yaml" :
    "docs/aios/tasks/P1-038_FINAL_CLEAN_ROOM_AUTHORITY_TEST.yaml"
  contract_path = File.join(root, contract_rel)
  evidence_root = Dir.mktmpdir(post_revision_route ? "p1-039-final-route-authority-test-" : "p1-038-final-route-authority-test-", evidence_base)
  begin
  task_branch = "task/#{task_id.downcase.tr('_', '-')}"
  task_worktree = File.join(worktree_root, task_id)
  contract = {
    "schema_version" => 1,
    "task_id" => task_id,
    "phase" => "P1",
    "status" => "READY_FOR_PHASE_DELEGATED_EXECUTION",
    "execution_authority" => "PHASE_DELEGATED",
    "objective" => "Verify the exact Founder-approved final clean-room route.",
    "why_now" => ["The one-time implementation route must activate and terminate atomically."],
    "task_spec_ref" => "synthetic://post-revision-final-route-test",
    "read_context" => [
      "docs/aios/FOUNDER_DELEGATION_POLICY.md",
      "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml",
      "docs/aios/tasks/P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET.yaml"
    ],
    "dependencies" => [
      "AIOS-P1-001",
      "AIOS-P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET"
    ],
    "mandatory_exit_capability" => capabilities.last,
    "integrated_mandatory_exit_capabilities" => capabilities,
    "founder_architecture_route_id" => nil,
    "founder_final_clean_room_route_id" => route_id,
    "clean_room_recovery" => {
      "historical_execution_lineage_reused" => false,
      "attempt_ordinal" => 1,
      "bounded_contract_corrections_allowed" => 0,
      "bounded_contract_corrections_used" => 0,
      "original_contract_path" => nil,
      "original_contract_sha256" => nil
    },
    "task_kind" => "EVALUATION_FOUNDATION_ENGINEERING",
    "capabilities" => ["EVALUATOR_AND_ORACLE", "LOCAL_SYNTHETIC_DATASET", "DETERMINISTIC_REPLAY", "EVIDENCE_MANIFEST"],
    "capability_claim" => false,
    "risk_level" => "medium",
    "lineage" => { "kind" => "INDEPENDENT_PHASE_INCREMENT", "retries" => [], "remediates" => [], "supersedes" => [] },
    "roles" => {
      "accountable_owner" => "Engineering Manager Agent",
      "worker" => "Final Clean Room Worker",
      "independent_reviewers" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
    },
    "allowed_paths" => {
      "worker" => ["evaluation-harness/harness/parameterized-authority-test/**"],
      "quality" => ["evaluation-harness/fixtures/parameterized-authority-test/**"],
      "integration" => ["scripts/verify-p1-final-route-authority-test.sh"],
      "external_evidence" => ["#{evidence_root}/**"]
    },
    "forbidden_actions" => ["network", "provider", "secret", "remote", "production", "public effect", "historical failed Task asset reuse"],
    "budget" => { "engineering_hours" => 1, "implementation_iterations" => 1, "execution_retries" => 0, "network_calls" => 0 },
    "acceptance_criteria" => ["both capabilities transition atomically"],
    "failure_criteria" => ["either capability transitions alone"],
    "stop_conditions" => ["the exact final clean-room route binding drifts"],
    "evidence" => { "required" => ["authority validator result"] },
    "rollback" => { "method" => "delete the unmerged synthetic worktree" },
    "claim_boundary" => final_route.fetch("claim_boundary"),
    "delegated_authority" => {
      "phase_local" => true,
      "task_gate_owner" => "MASTER_CEO_AGENT",
      "founder_gate" => "RESERVED_DECISIONS_ONLY",
      "founder_reserved_decisions" => [],
      "external_effects" => { "network" => false, "provider" => false, "secret" => false, "remote" => false, "production" => false, "public" => false }
    }
  }
  write_yaml(contract_path, contract)
  run!("git", "add", contract_rel, chdir: root)
  run!("git", "commit", "-m", "freeze final clean-room contract", chdir: root)
  activation_parent = run!("git", "rev-parse", "HEAD", chdir: root)
  activation_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  contract_sha = Digest::SHA256.file(contract_path).hexdigest
  authorization_id = Digest::SHA256.hexdigest("#{task_id}:#{contract_sha}:#{activation_parent}")
  authorization_path = File.join(evidence_root, "PHASE_DELEGATED_AUTHORIZATION.json")
  authorization = {
    "record_type" => "aios_phase_delegated_task_authorization",
    "status" => "ACTIVE",
    "authority" => "MASTER_CEO_AGENT",
    "delegation_model" => "PHASE_LEVEL_FOUNDER_DELEGATION",
    "authorization_id" => authorization_id,
    "task_id" => task_id,
    "phase" => "P1",
    "task_contract_sha256" => contract_sha,
    "goal_canonical_sha256" => truth.dig("goal", "observed_body_sha256"),
    "parent_commit" => activation_parent,
    "parent_tree" => activation_tree,
    "integrated_mandatory_exit_capabilities" => capabilities,
    "founder_final_clean_room_route_id" => route_id,
    "external_effects" => contract.dig("delegated_authority", "external_effects"),
    "founder_reserved_decisions" => [],
    "founder_reserved_decision_required" => false
  }
  write_json(authorization_path, authorization)

  active_truth = Marshal.load(Marshal.dump(truth))
  active_truth["goal"]["current_task_authority"] = task_id
  active_truth["project"]["phase_execution_status"] = "TASK_ACTIVE"
  active_truth["project"]["p1_execution_status"] = "TASK_ACTIVE"
  capabilities.each do |capability|
    active_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "IN_PROGRESS"
  end
  active_attempt = {
    "status" => "ACTIVE",
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "contract_sha256" => contract_sha,
    "bounded_contract_corrections_used" => 0,
    "integrated_mandatory_exit_capabilities" => capabilities,
    "founder_final_clean_room_route_id" => route_id
  }
  active_truth["mandatory_exit_capability_recovery"][attempt_key] = active_attempt
  active_truth["active_work"] = {
    "current_task" => task_id,
    "current_task_status" => "AUTHORIZED_ACTIVE",
    "current_task_contract" => contract_rel,
    "current_task_contract_sha256" => contract_sha,
    "current_execution_authorization" => authorization_path,
    "current_execution_authorization_sha256" => Digest::SHA256.file(authorization_path).hexdigest,
    "execution_nonce" => nil,
    "execution_nonce_status" => "NOT_REQUIRED_PHASE_DELEGATION",
    "authorization_id" => authorization_id,
    "activation_parent_commit" => activation_parent,
    "activation_parent_tree" => activation_tree,
    "task_resource_state" => "DECLARED",
    "task_branch" => task_branch,
    "task_worktree" => task_worktree,
    "execution_evidence_root" => evidence_root,
    "offsite_target" => nil,
    "founder_reserved_authorization" => nil,
    "founder_reserved_authorization_sha256" => nil,
    "founder_decision_required" => false,
    "escalation_reason" => nil,
    "user_action_required" => nil,
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_EXECUTE_CURRENT_TASK"
  }
  active_truth["phase_execution_claim"]["current_task_claim"] = task_id
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), active_truth)
  run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "-m", "activate final clean-room route test", chdir: root)
  run_validator(root, true, "final clean-room ACTIVE positive")

  forbidden_contract_read = Marshal.load(Marshal.dump(active_truth))
  forbidden_contract_read["active_work"]["current_task_contract"] = FORBIDDEN_P1_038_CONTRACT_PATH
  forbidden_contract_read["active_work"]["current_task_contract_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), forbidden_contract_read)
  run_validator(
    root,
    false,
    "active historical failed Contract read-before-deny negative",
    expected_failure: "active Task contract overlaps a historical failed Contract denylist path"
  )

  partial_active = Marshal.load(Marshal.dump(active_truth))
  partial_active["mandatory_exit_capability_recovery"]["capability_status"][capabilities.first] = pending_state
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_active)
  run_validator(root, false, "partial final route ACTIVE negative")

  wrong_task = Marshal.load(Marshal.dump(active_truth))
  wrong_task["active_work"]["current_task"] = "AIOS-P1-039_WRONG_TASK"
  wrong_task["goal"]["current_task_authority"] = "AIOS-P1-039_WRONG_TASK"
  wrong_task["phase_execution_claim"]["current_task_claim"] = "AIOS-P1-039_WRONG_TASK"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), wrong_task)
  run_validator(root, false, "final clean-room wrong Task negative")

  attempt_identity_drift = Marshal.load(Marshal.dump(active_truth))
  attempt_identity_drift["mandatory_exit_capability_recovery"][attempt_key]["contract_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), attempt_identity_drift)
  run_validator(
    root,
    false,
    "final route attempt identity drift negative",
    expected_failure: post_revision_route ? "post-revision final implementation attempt identity changed: contract_sha256" : "final clean-room implementation attempt identity changed: contract_sha256"
  )

  apply_contract_variant = lambda do |contract_variant|
    write_yaml(contract_path, contract_variant)
    variant_sha = Digest::SHA256.file(contract_path).hexdigest
    variant_authorization = Marshal.load(Marshal.dump(authorization))
    variant_authorization["task_contract_sha256"] = variant_sha
    write_json(authorization_path, variant_authorization)
    variant_truth = Marshal.load(Marshal.dump(active_truth))
    variant_truth["active_work"]["current_task_contract_sha256"] = variant_sha
    variant_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), variant_truth)
  end

  write_yaml(contract_path, contract)
  wrong_route_authorization = Marshal.load(Marshal.dump(authorization))
  wrong_route_authorization["founder_final_clean_room_route_id"] = "P1_038_WRONG_ROUTE"
  write_json(authorization_path, wrong_route_authorization)
  wrong_route_truth = Marshal.load(Marshal.dump(active_truth))
  wrong_route_truth["active_work"]["current_execution_authorization_sha256"] = Digest::SHA256.file(authorization_path).hexdigest
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), wrong_route_truth)
  run_validator(root, false, "final clean-room wrong route negative", expected_failure: "active Task authorization final clean-room capability binding drift")

  corrected_contract = Marshal.load(Marshal.dump(contract))
  corrected_contract["clean_room_recovery"]["bounded_contract_corrections_allowed"] = 1
  corrected_contract["clean_room_recovery"]["bounded_contract_corrections_used"] = 1
  apply_contract_variant.call(corrected_contract)
  run_validator(root, false, "final clean-room correction count negative", expected_failure: "active Task bounded Contract correction limit drift")

  unfrozen_contract = Marshal.load(Marshal.dump(contract))
  unfrozen_contract["why_now"] = ["This changed after the final Contract freeze."]
  apply_contract_variant.call(unfrozen_contract)
  run_validator(root, false, "final clean-room Contract not frozen at parent negative", expected_failure: "final clean-room Contract was not frozen at the activation parent")

  routine_founder_gate_contract = Marshal.load(Marshal.dump(contract))
  routine_founder_gate_contract["delegated_authority"]["founder_gate"] = "REQUIRED_PER_TASK"
  apply_contract_variant.call(routine_founder_gate_contract)
  run_validator(root, false, "final clean-room routine Founder Gate cannot bypass frozen Contract negative", expected_failure: "final clean-room Contract was not frozen at the activation parent")

  write_yaml(contract_path, contract)
  write_json(authorization_path, authorization)
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), active_truth)

  candidate_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  candidate_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  result_path = File.join(evidence_root, "result.txt")
  File.write(result_path, "final clean-room route acceptance test\n")
  binding = { "mandatory_exit_capabilities" => capabilities }
  artifact_index_path = File.join(evidence_root, "ARTIFACT_INDEX.json")
  artifact_index = {
    "record_type" => "aios_p1_mandatory_capability_artifact_index",
    "status" => "FROZEN",
    "task_id" => task_id,
    "candidate_commit" => candidate_commit,
    "candidate_tree" => candidate_tree,
    "artifacts" => [{
      "path" => "result.txt",
      "sha256" => Digest::SHA256.file(result_path).hexdigest,
      "byte_length" => File.size(result_path)
    }]
  }.merge(binding)
  write_json(artifact_index_path, artifact_index)
  artifact_index_sha = Digest::SHA256.file(artifact_index_path).hexdigest
  manifest_path = File.join(evidence_root, "EVIDENCE_MANIFEST.json")
  manifest = {
    "record_type" => "aios_p1_mandatory_capability_evidence_manifest",
    "status" => "FROZEN",
    "task_id" => task_id,
    "task_contract_sha256" => contract_sha,
    "candidate_commit" => candidate_commit,
    "candidate_tree" => candidate_tree,
    "artifact_index_path" => artifact_index_path,
    "artifact_index_sha256" => artifact_index_sha,
    "replay_result" => "PASS",
    "rebuild_result" => "PASS",
    "rollback_result" => "PASS",
    "claim_boundary" => final_route.fetch("claim_boundary")
  }.merge(binding)
  write_json(manifest_path, manifest)
  manifest_sha = Digest::SHA256.file(manifest_path).hexdigest
  review_paths = {}
  review_hashes = {}
  %w[cto security quality].each do |role|
    review_path = File.join(evidence_root, "#{role.upcase}_REVIEW.json")
    review = {
      "record_type" => "aios_independent_task_review",
      "status" => "PASS",
      "role" => role.upcase,
      "task_id" => task_id,
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => candidate_commit,
      "candidate_tree" => candidate_tree,
      "evidence_manifest_sha256" => manifest_sha,
      "claim_boundary" => final_route.fetch("claim_boundary")
    }.merge(binding)
    write_json(review_path, review)
    review_paths[role] = review_path
    review_hashes[role] = Digest::SHA256.file(review_path).hexdigest
  end
  gate_path = File.join(evidence_root, "TASK_GATE_RECEIPT.json")
  gate = {
    "record_type" => "aios_phase_delegated_task_gate_receipt",
    "status" => "ACCEPTED",
    "authority" => "MASTER_CEO_AGENT",
    "task_id" => task_id,
    "task_contract_sha256" => contract_sha,
    "candidate_commit" => candidate_commit,
    "candidate_tree" => candidate_tree,
    "evidence_manifest_sha256" => manifest_sha,
    "cto_review_sha256" => review_hashes.fetch("cto"),
    "security_review_sha256" => review_hashes.fetch("security"),
    "quality_review_sha256" => review_hashes.fetch("quality"),
    "claim_boundary" => final_route.fetch("claim_boundary")
  }.merge(binding)
  write_json(gate_path, gate)

  none_active_work = Marshal.load(Marshal.dump(truth.fetch("active_work")))
  accepted_truth = Marshal.load(Marshal.dump(active_truth))
  capabilities.each do |capability|
    accepted_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "ACCEPTED"
  end
  accepted_truth["mandatory_exit_capability_recovery"][attempt_key]["status"] = "ACCEPTED"
  accepted_truth["task_history"]["final_route_accepted_test"] = {
    "task_id" => task_id,
    "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
    "mandatory_exit_capability" => capabilities.last,
    "integrated_mandatory_exit_capabilities" => capabilities,
    "founder_final_clean_room_route_id" => route_id,
    "clean_room_attempt_ordinal" => 1,
    "task_gate_result" => "PASS",
    "task_contract_sha256" => contract_sha,
    "bounded_contract_corrections_used" => 0,
    "accepted_candidate_commit" => candidate_commit,
    "accepted_candidate_tree" => candidate_tree,
    "execution_evidence_root" => evidence_root,
    "evidence_manifest_path" => manifest_path,
    "evidence_manifest_sha256" => manifest_sha,
    "artifact_index_path" => artifact_index_path,
    "artifact_index_sha256" => artifact_index_sha,
    "cto_review_path" => review_paths.fetch("cto"),
    "cto_review_sha256" => review_hashes.fetch("cto"),
    "security_review_path" => review_paths.fetch("security"),
    "security_review_sha256" => review_hashes.fetch("security"),
    "quality_review_path" => review_paths.fetch("quality"),
    "quality_review_sha256" => review_hashes.fetch("quality"),
    "task_gate_receipt_path" => gate_path,
    "task_gate_receipt_sha256" => Digest::SHA256.file(gate_path).hexdigest,
    "claim_boundary" => final_route.fetch("claim_boundary")
  }
  accepted_truth["goal"]["current_task_authority"] = "NONE"
  accepted_truth["project"]["phase_execution_status"] = "NO_CURRENT_TASK"
  accepted_truth["project"]["p1_execution_status"] = "NO_CURRENT_TASK"
  accepted_truth["active_work"] = none_active_work
  accepted_truth["active_work"]["next_eligible_action"] = "MASTER_AUTONOMOUSLY_IMPLEMENT_P1_EXIT_CAPABILITIES_IN_FROZEN_PRIORITY_ORDER"
  accepted_truth["phase_execution_claim"]["current_task_claim"] = "NO_CURRENT_TASK"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), accepted_truth)
  run_validator(root, true, "final clean-room atomic ACCEPTED positive")

  partial_accepted = Marshal.load(Marshal.dump(accepted_truth))
  partial_accepted["mandatory_exit_capability_recovery"]["capability_status"][capabilities.first] = "IN_PROGRESS"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_accepted)
  run_validator(root, false, "partial final route ACCEPTED negative")

  route_reuse = Marshal.load(Marshal.dump(accepted_truth))
  capabilities.each do |capability|
    route_reuse["mandatory_exit_capability_recovery"]["capability_status"][capability] = "IN_PROGRESS"
  end
  route_reuse["mandatory_exit_capability_recovery"][attempt_key]["status"] = "ACTIVE"
  route_reuse["goal"]["current_task_authority"] = task_id
  route_reuse["project"]["phase_execution_status"] = "TASK_ACTIVE"
  route_reuse["project"]["p1_execution_status"] = "TASK_ACTIVE"
  route_reuse["active_work"] = Marshal.load(Marshal.dump(active_truth.fetch("active_work")))
  route_reuse["phase_execution_claim"]["current_task_claim"] = task_id
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), route_reuse)
  run_validator(root, false, "final clean-room route reuse negative")

  terminal_manifest_path = File.join(evidence_root, "TERMINAL_EVIDENCE_MANIFEST.json")
  terminal_manifest = {
    "record_type" => "aios_p1_mandatory_capability_terminal_evidence_manifest",
    "status" => "TERMINAL_STOPPED_REAL_ARCHITECTURE_ROOT",
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "task_contract_sha256" => contract_sha,
    "bounded_contract_corrections_used" => 0,
    "failure_classification" => "REAL_ARCHITECTURE_ROOT"
  }.merge(binding)
  write_json(terminal_manifest_path, terminal_manifest)
  blocked_truth = Marshal.load(Marshal.dump(active_truth))
  capabilities.each do |capability|
    blocked_truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "ARCHITECTURE_BLOCKED"
  end
  blocked_truth["mandatory_exit_capability_recovery"][attempt_key]["status"] = "ARCHITECTURE_BLOCKED"
  if post_revision_route
    post_revision_terminal_record_path = File.join(evidence_root, "P1_039_POST_REVISION_TERMINAL_RECORD.json")
    post_revision_terminal_record = {
      "record_type" => "sourcelens_aios_p1_post_revision_final_route_terminal_record",
      "schema_version" => "1.0",
      "status" => "P1_TERMINAL_STOPPED",
      "task_id" => task_id,
      "route_id" => route_id,
      "mandatory_exit_capabilities" => capabilities.dup,
      "failure_stage" => "REAL_ARCHITECTURE_IMPLEMENTATION_FAILURE",
      "implementation_attempt_consumed" => true,
      "route_recovery_allowed" => false,
      "fifth_route_allowed" => false,
      "successor_replacement_correction_allowed" => false,
      "founder_escalation_required" => true,
      "project_level_disposition_required" => true,
      "terminal_action" => "STOP_P1_NO_FIFTH_ROUTE"
    }
    write_json(post_revision_terminal_record_path, post_revision_terminal_record)
    blocked_truth["mandatory_exit_capability_recovery"]["post_revision_final_route_terminal"] = {
      "record_type" => "p1_post_revision_final_route_terminal_binding",
      "status" => "P1_TERMINAL_STOPPED",
      "task_id" => task_id,
      "route_id" => route_id,
      "mandatory_exit_capabilities" => capabilities.dup,
      "failure_stage" => "REAL_ARCHITECTURE_IMPLEMENTATION_FAILURE",
      "terminal_record_path" => post_revision_terminal_record_path,
      "terminal_record_sha256" => Digest::SHA256.file(post_revision_terminal_record_path).hexdigest,
      "implementation_attempt_consumed" => true,
      "route_recovery_allowed" => false,
      "fifth_route_allowed" => false,
      "successor_replacement_correction_allowed" => false,
      "founder_escalation_required" => true,
      "project_level_disposition_required" => true
    }
  end
  blocked_truth["task_history"]["final_route_architecture_blocked_test"] = {
    "task_id" => task_id,
    "status" => "TERMINAL_STOPPED_REAL_ARCHITECTURE_ROOT",
    "mandatory_exit_capability" => capabilities.last,
    "integrated_mandatory_exit_capabilities" => capabilities.dup,
    "founder_final_clean_room_route_id" => route_id,
    "clean_room_attempt_ordinal" => 1,
    "execution_evidence_root" => evidence_root,
    "founder_escalation_required" => true,
    "terminal_evidence" => {
      "evidence_manifest_path" => terminal_manifest_path,
      "evidence_manifest_sha256" => Digest::SHA256.file(terminal_manifest_path).hexdigest
    }
  }
  blocked_truth["goal"]["current_task_authority"] = "NONE"
  blocked_truth["project"]["phase_execution_status"] = "NO_CURRENT_TASK"
  blocked_truth["project"]["p1_execution_status"] = "NO_CURRENT_TASK"
  blocked_truth["active_work"] = none_active_work
  blocked_truth["active_work"]["founder_decision_required"] = true
  blocked_truth["active_work"]["escalation_reason"] = post_revision_route ? "p1_post_revision_final_route_terminal_stop" : "mandatory_exit_capability_blocked"
  blocked_truth["active_work"]["user_action_required"] = post_revision_route ? "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED" : "FOUNDER_DECISION_REQUIRED"
  blocked_truth["active_work"]["next_eligible_action"] = post_revision_route ? "STOP_P1_AND_WAIT_FOR_PROJECT_LEVEL_DISPOSITION" : "WAIT_FOR_FOUNDER_MANDATORY_EXIT_CAPABILITY_DECISION"
  blocked_truth["phase_execution_claim"]["current_task_claim"] = "NO_CURRENT_TASK"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), blocked_truth)
  run_validator(root, true, "final clean-room atomic ARCHITECTURE_BLOCKED positive")

  partial_blocked = Marshal.load(Marshal.dump(blocked_truth))
  partial_blocked["mandatory_exit_capability_recovery"]["capability_status"][capabilities.first] = "IN_PROGRESS"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), partial_blocked)
  run_validator(root, false, "partial final route ARCHITECTURE_BLOCKED negative")
  ensure
    FileUtils.rm_rf(evidence_root)
  end
end

puts "Current Task authority state-machine tests passed for the current canonical authority model."

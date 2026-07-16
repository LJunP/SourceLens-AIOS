#!/usr/bin/env ruby
# encoding: UTF-8

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

SOURCE_ROOT = File.expand_path("..", __dir__)

def run!(*command, chdir: nil)
  stdout, stderr, status = Open3.capture3(*command, chdir: chdir)
  raise "#{command.join(' ')} failed: #{stdout}#{stderr}" unless status.success?
  stdout.strip
end

def write_yaml(path, value)
  File.write(path, YAML.dump(value), mode: "w:UTF-8")
end

def run_validator(root, expected_pass, label)
  stdout, stderr, status = Open3.capture3({ "LC_ALL" => "C", "LANG" => "C" }, "ruby", "scripts/validate-current-task-authority.rb", chdir: root)
  actual = status.success?
  raise "#{label}: expected #{expected_pass ? 'PASS' : 'FAIL'}, observed #{actual ? 'PASS' : 'FAIL'}: #{stdout}#{stderr}" unless actual == expected_pass
end

Dir.mktmpdir("aios-current-task-authority-") do |root|
  FileUtils.mkdir_p(File.join(root, "scripts"))
  FileUtils.mkdir_p(File.join(root, "docs/aios/truth"))
  FileUtils.mkdir_p(File.join(root, "docs/aios/tasks"))
  FileUtils.cp(File.join(SOURCE_ROOT, "scripts/validate-current-task-authority.rb"), File.join(root, "scripts"))
  FileUtils.cp(File.join(SOURCE_ROOT, "AGENTS.md"), root)
  FileUtils.cp(File.join(SOURCE_ROOT, "docs/aios/FOUNDER_DELEGATION_POLICY.md"), File.join(root, "docs/aios"))

  worktree_root = File.join(root, "task-worktrees")
  evidence_base = File.join(root, "audit")
  FileUtils.mkdir_p(worktree_root)
  FileUtils.mkdir_p(evidence_base)

  truth = YAML.safe_load(File.read(File.join(SOURCE_ROOT, "docs/aios/truth/project_state.yaml")), aliases: false)
  truth["authority"]["founder_delegation_policy"]["sha256"] = Digest::SHA256.file(File.join(root, "docs/aios/FOUNDER_DELEGATION_POLICY.md")).hexdigest
  truth["project"]["canonical_repository"] = root
  truth["project"]["task_worktree_root"] = worktree_root
  truth["project"]["execution_evidence_root_base"] = evidence_base
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
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_SELECT_NEXT_PHASE_LOCAL_TASK"
  }
  truth["phase_execution_claim"]["current_task_claim"] = "NO_CURRENT_TASK"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)

  run!("git", "init", chdir: root)
  run!("git", "config", "user.name", "SourceLens Validator Test", chdir: root)
  run!("git", "config", "user.email", "validator@example.invalid", chdir: root)
  run!("git", "add", ".", chdir: root)
  run!("git", "commit", "-m", "base", chdir: root)
  run!("git", "branch", "-M", "main", chdir: root)
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

puts "Current Task authority state-machine tests passed (5 positive states, 27 negative vectors)."

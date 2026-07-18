#!/usr/bin/env ruby
# encoding: UTF-8

require "digest"
require "fileutils"
require "json"
require "open3"
require "stringio"
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
VALIDATOR_HELPERS = Module.new
validator_source = File.read(File.join(SOURCE_ROOT, "scripts/validate-current-task-authority.rb"), encoding: "UTF-8")
validator_function_source = validator_source.split(/^def worktree_records\b/, 2).first
VALIDATOR_HELPERS.module_eval(validator_function_source, File.join(SOURCE_ROOT, "scripts/validate-current-task-authority.rb"), 1)
VALIDATOR_HELPER_RECEIVER = Object.new.extend(VALIDATOR_HELPERS)

EXPECTED_REBASELINE_LIFECYCLE_STATES = %w[
  FOUNDER_APPROVED_ACTIVE
  REBASELINED_PENDING_EXECUTION
  REBASELINED_SLICE_ACTIVE
  P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE
  TERMINAL_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION
  PERMANENTLY_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION
].freeze
expected_rebaseline_allowlist = "%w[#{EXPECTED_REBASELINE_LIFECYCLE_STATES.join(' ')}]"
%w[
  scripts/validate-current-task-authority.rb
  scripts/validate-aios-governance.sh
  scripts/check-p1-safety-boundary.sh
].each do |relative_path|
  source = File.read(File.join(SOURCE_ROOT, relative_path), encoding: "UTF-8")
  raise "#{relative_path} lacks the exact production rebaseline lifecycle allowlist" unless source.include?(expected_rebaseline_allowlist)
end
authority_knowledge_sha = validator_source[/FOUNDER_KNOWLEDGE_SECTION_CANONICAL_SHA256 = "([0-9a-f]{64})"/, 1]
authority_knowledge_length = validator_source[/FOUNDER_KNOWLEDGE_SECTION_CANONICAL_BYTE_LENGTH = ([\d_]+)/, 1]&.delete("_")
governance_source = File.read(File.join(SOURCE_ROOT, "scripts/validate-aios-governance.sh"), encoding: "UTF-8")
governance_knowledge_sha = governance_source[/founder_knowledge_section_sha256='([0-9a-f]{64})'/, 1]
governance_knowledge_length = governance_source[/founder_knowledge_section_byte_length='(\d+)'/, 1]
raise "authority/governance Founder Knowledge exact section hash drift" unless
  authority_knowledge_sha == governance_knowledge_sha && authority_knowledge_sha == "e6b353038598122a9d347378ceaab1dc4e7957357bb29f72adfbcbf27820303e"
raise "authority/governance Founder Knowledge exact section byte-length drift" unless
  authority_knowledge_length == governance_knowledge_length && authority_knowledge_length == "1011"

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
    bytes = path == "AGENTS.md" ? File.binread(File.join(SOURCE_ROOT, path)) : source_tracked_bytes(ref, path)
    File.binwrite(absolute, bytes)
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
  # Test fixtures often reuse the same nested Hash for two exact bindings.
  # Break Ruby object aliases so the production parser can keep aliases disabled.
  alias_free_value = JSON.parse(JSON.generate(value))
  File.write(path, YAML.dump(alias_free_value), mode: "w:UTF-8")
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

def run_exact_validator_helper(method_name, arguments, expected_pass, label, expected_failure: nil)
  captured_stderr = StringIO.new
  previous_stderr = $stderr
  $stderr = captured_stderr
  actual = true
  begin
    VALIDATOR_HELPER_RECEIVER.public_send(method_name, *arguments)
  rescue SystemExit
    actual = false
  ensure
    $stderr = previous_stderr
  end
  output = captured_stderr.string
  raise "#{label}: expected #{expected_pass ? 'PASS' : 'FAIL'}, observed #{actual ? 'PASS' : 'FAIL'}: #{output}" unless actual == expected_pass
  if !expected_pass && expected_failure && !output.include?(expected_failure)
    raise "#{label}: expected failure containing #{expected_failure.inspect}, observed: #{output}"
  end
end

def run_current_reopen_transition(root, previous_truth, current_truth, expected_pass, label, expected_failure: nil)
  run_exact_validator_helper(
    :validate_current_reopen_transition!,
    [previous_truth, current_truth],
    expected_pass,
    label,
    expected_failure: expected_failure
  )
end

def run_current_reopen_superseding_projection(truth, legacy_attempt, expected_pass, label, expected_failure: nil)
  run_exact_validator_helper(
    :current_reopen_superseding_projection_state!,
    [truth, legacy_attempt],
    expected_pass,
    label,
    expected_failure: expected_failure
  )
end

def run_rebaseline_contract_correction(root, clean_room, contract_sha256, final_contract_path, evidence_root, expected_pass, label, expected_failure: nil)
  run_exact_validator_helper(
    :validate_rebaseline_contract_correction_evidence!,
    [clean_room, contract_sha256, File.binread(final_contract_path), evidence_root],
    expected_pass,
    label,
    expected_failure: expected_failure
  )
end

def run_rebaseline_contract_budget(contract, slice, expected_pass, label, expected_failure: nil)
  run_exact_validator_helper(
    :validate_rebaseline_contract_budget!,
    [contract, slice],
    expected_pass,
    label,
    expected_failure: expected_failure
  )
end

def run_effective_slice_order(truth, expected_pass, label, expected_failure: nil)
  run_exact_validator_helper(
    :validate_effective_rebaseline_slice_order!,
    [truth],
    expected_pass,
    label,
    expected_failure: expected_failure
  )
end

def run_effective_slice_transition(previous_truth, current_truth, expected_pass, label, expected_failure: nil)
  run_exact_validator_helper(
    :validate_effective_rebaseline_slice_transition!,
    [previous_truth, current_truth],
    expected_pass,
    label,
    expected_failure: expected_failure
  )
end

Dir.mktmpdir("aios-worktree-record-authority-", SOURCE_ROOT) do |root|
  canonical_dir = File.join(root, "canonical")
  runtime_dir = File.join(root, "linked-current")
  external_dir = File.join(root, "external-linked")
  symlink_dir = File.join(root, "linked-current-symlink")
  missing_dir = File.join(root, "missing")
  [canonical_dir, runtime_dir, external_dir].each { |path| FileUtils.mkdir_p(path) }
  File.symlink(runtime_dir, symlink_dir)

  primary_records = VALIDATOR_HELPER_RECEIVER.parse_worktree_porcelain_records!(
    "worktree #{canonical_dir}\nHEAD #{"1" * 40}\nbranch refs/heads/main\n"
  )
  primary_runtime = VALIDATOR_HELPER_RECEIVER.unique_runtime_worktree_record!(primary_records, canonical_dir)
  run_exact_validator_helper(
    :validate_runtime_worktree_population!,
    [primary_records, primary_records.first, primary_runtime],
    true,
    "worktree canonical primary runtime positive"
  )

  linked_porcelain = [
    "worktree #{canonical_dir}\nHEAD #{"1" * 40}\nbranch refs/heads/main",
    "worktree #{runtime_dir}\nHEAD #{"2" * 40}\nbranch refs/heads/task/current"
  ].join("\n\n") + "\n"
  linked_records = VALIDATOR_HELPER_RECEIVER.parse_worktree_porcelain_records!(linked_porcelain)
  linked_runtime = VALIDATOR_HELPER_RECEIVER.unique_runtime_worktree_record!(linked_records, runtime_dir)
  run_exact_validator_helper(
    :validate_runtime_worktree_population!,
    [linked_records, linked_records.first, linked_runtime],
    true,
    "worktree linked current runtime positive"
  )

  reversed_records = VALIDATOR_HELPER_RECEIVER.parse_worktree_porcelain_records!(
    linked_porcelain.split(/\n\n/).reverse.join("\n\n")
  )
  reversed_runtime = VALIDATOR_HELPER_RECEIVER.unique_runtime_worktree_record!(reversed_records, runtime_dir)
  reversed_canonical = reversed_records.find { |record| record["worktree"] == canonical_dir }
  run_exact_validator_helper(
    :validate_runtime_worktree_population!,
    [reversed_records, reversed_canonical, reversed_runtime],
    true,
    "worktree porcelain order reversed positive"
  )

  run_exact_validator_helper(
    :unique_runtime_worktree_record!,
    [primary_records, runtime_dir],
    false,
    "worktree no runtime match negative",
    expected_failure: "no exact existing non-symlink match"
  )
  duplicate_records = VALIDATOR_HELPER_RECEIVER.parse_worktree_porcelain_records!(
    "worktree #{runtime_dir}\nHEAD #{"2" * 40}\nbranch refs/heads/task/current\n\n" \
    "worktree #{runtime_dir}\nHEAD #{"3" * 40}\nbranch refs/heads/task/duplicate\n"
  )
  run_exact_validator_helper(
    :unique_runtime_worktree_record!,
    [duplicate_records, runtime_dir],
    false,
    "worktree duplicate runtime match negative",
    expected_failure: "duplicate exact matches"
  )
  symlink_only_records = [{ "worktree" => symlink_dir, "branch" => "refs/heads/task/symlink" }]
  run_exact_validator_helper(
    :unique_runtime_worktree_record!,
    [symlink_only_records, runtime_dir],
    false,
    "worktree symlink-only runtime match negative",
    expected_failure: "match missing, symlinked, or not a directory"
  )
  run_exact_validator_helper(
    :unique_runtime_worktree_record!,
    [[{ "worktree" => runtime_dir }, { "worktree" => symlink_dir }], runtime_dir],
    false,
    "worktree real plus symlink duplicate negative",
    expected_failure: "duplicate exact matches"
  )
  run_exact_validator_helper(
    :unique_runtime_worktree_record!,
    [[{ "worktree" => missing_dir }], runtime_dir],
    false,
    "worktree nonexistent runtime record negative",
    expected_failure: "no exact existing non-symlink match"
  )
  external_record = { "worktree" => external_dir, "branch" => "refs/heads/feature/external" }
  run_exact_validator_helper(
    :validate_runtime_worktree_population!,
    [linked_records + [external_record], linked_records.first, linked_runtime],
    false,
    "worktree external-path extra linked worktree negative",
    expected_failure: "outside canonical and current runtime"
  )
end

def current_reopen_lifecycle_fixture(base_truth, stage, task_id: "AIOS-P1-943_CURRENT_REOPEN_LIFECYCLE_TEST", contract_sha256: "a" * 64)
  value = Marshal.load(Marshal.dump(base_truth))
  recovery = value.fetch("mandatory_exit_capability_recovery")
  reopen = recovery.fetch("current_project_level_reopen")
  value.fetch("task_history").delete_if do |_key, entry|
    entry.is_a?(Hash) &&
      entry["project_level_reopen_decision_sha256"] == reopen["decision_record_sha256"] &&
      entry["clean_room_attempt_ordinal"] == 1
  end
  rebaseline = recovery.fetch("project_level_rebaseline")
  delivery = recovery.fetch("delivery_architecture_simplification")
  approved_route = reopen.fetch("approved_reopen_decision_route")
  approved_ordinal = approved_route.fetch("next_slice_ordinal")
  slice = rebaseline.fetch("slices").find { |candidate| candidate["ordinal"] == approved_ordinal }
  attempt = if stage == "PENDING"
    nil
  else
    {
      "status" => stage,
      "task_id" => task_id,
      "attempt_ordinal" => 1,
      "contract_sha256" => contract_sha256,
      "bounded_contract_corrections_used" => 0,
      "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(slice.fetch("capability_projection"))),
      "project_level_rebaseline_slice_ordinal" => approved_ordinal,
      "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
      "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256"),
      "project_level_reopen_decision_sha256" => reopen.fetch("decision_record_sha256")
    }
  end
  reopen["current_slice_attempt"] = attempt

  projection = case stage
  when "PENDING"
    ["REBASELINED_PENDING_EXECUTION", "NONE", "REBASELINED_PENDING_EXECUTION", approved_ordinal, "REBASELINED_PENDING_EXECUTION"]
  when "ACTIVE"
    ["REBASELINED_SLICE_ACTIVE", task_id, "TASK_ACTIVE", approved_ordinal, "IN_PROGRESS"]
  when "ACCEPTED"
    ["ACCEPTED", "NONE", "REBASELINED_PENDING_EXECUTION", approved_ordinal + 1, "ACCEPTED"]
  when "ARCHITECTURE_BLOCKED"
    ["ARCHITECTURE_BLOCKED", "NONE", "TERMINAL_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION", nil, "ARCHITECTURE_BLOCKED"]
  when "SCOPE_COMPLIANCE_BLOCKED"
    ["SCOPE_COMPLIANCE_BLOCKED", "NONE", "PERMANENTLY_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION", nil, "P1_TERMINAL_STOPPED_NOT_ACCEPTED"]
  else
    raise "unknown current reopen lifecycle stage: #{stage}"
  end
  reopen_status, current_task, project_status, next_slice_ordinal, capability_status = projection
  rebaseline_status = case stage
  when "PENDING", "ACCEPTED"
    "REBASELINED_PENDING_EXECUTION"
  when "ACTIVE"
    "REBASELINED_SLICE_ACTIVE"
  else
    project_status
  end
  rebaseline["status"] = rebaseline_status
  rebaseline["p1_status"] = rebaseline_status
  rebaseline["current_task"] = current_task
  rebaseline["next_slice_ordinal"] = next_slice_ordinal
  rebaseline["next_slice_action"] = if next_slice_ordinal
    "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_#{next_slice_ordinal}"
  else
    "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED"
  end
  value.fetch("claim_boundary")["p1_status"] = rebaseline_status
  reopen["current_p1_status"] = reopen_status
  reopen["current_task"] = current_task
  reopen["next_slice_ordinal"] = next_slice_ordinal
  reopen["next_slice_action"] = rebaseline["next_slice_action"]
  slice.fetch("capability_projection").each { |capability| recovery.fetch("capability_status")[capability] = capability_status }
  value.fetch("project")["phase_execution_status"] = project_status
  value.fetch("project")["p1_execution_status"] = project_status
  value.fetch("goal")["current_task_authority"] = current_task
  value.fetch("active_work")["current_task"] = current_task
  value
end

def install_synthetic_architecture_terminal_evidence!(truth, task_id, contract_sha256, contract_path, terminal_root, capabilities)
  root = truth.dig("project", "canonical_repository")
  FileUtils.mkdir_p(terminal_root)
  candidate_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  candidate_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  task_number = task_id[/\AAIOS-P1-(\d{3})/, 1]
  raise "synthetic architecture terminal Task ID invalid" unless task_number
  tag = "refs/tags/evidence/synthetic-#{Digest::SHA256.hexdigest(task_id)[0, 16]}"
  run!("git", "tag", "-f", tag.delete_prefix("refs/tags/"), candidate_commit, chdir: root)
  contract_absolute = File.join(root, contract_path)
  contract_byte_length = File.file?(contract_absolute) ? File.binread(contract_absolute).bytesize : 0
  contract = {
    "path" => contract_path,
    "sha256" => contract_sha256,
    "byte_length" => contract_byte_length,
    "bounded_contract_corrections_used" => truth.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt", "bounded_contract_corrections_used") || 0
  }
  activation = {
    "commit" => candidate_commit,
    "tree" => candidate_tree,
    "authorization_id" => Digest::SHA256.hexdigest("#{task_id}:authorization-id"),
    "authorization_sha256" => Digest::SHA256.hexdigest("#{task_id}:authorization")
  }
  quality_receipt_path = File.join(terminal_root, "SYNTHETIC_QUALITY_FREEZE_RECEIPT.json")
  quality_receipt = {
    "record_type" => "synthetic_quality_freeze_receipt",
    "status" => "PASS",
    "task_id" => task_id,
    "task_contract" => contract.slice("path", "sha256", "byte_length"),
    "quality_commit" => { "commit" => candidate_commit, "tree" => candidate_tree }
  }
  write_json(quality_receipt_path, quality_receipt)
  quality = {
    "commit" => candidate_commit,
    "tree" => candidate_tree,
    "receipt_sha256" => Digest::SHA256.file(quality_receipt_path).hexdigest,
    "self_test_result_sha256" => Digest::SHA256.hexdigest("#{task_id}:quality-self-test"),
    "status" => "PASS_HISTORICAL_ONLY_AFTER_TASK_STOP"
  }
  candidate_record_path = File.join(terminal_root, "SYNTHETIC_CANDIDATE_NONPASS_RECORD.json")
  rejected = {
    "commit" => candidate_commit,
    "tree" => candidate_tree,
    "preservation_ref" => tag,
    "candidate_nonpass_record_path" => candidate_record_path,
    "candidate_nonpass_record_sha256" => nil,
    "candidate_nonpass_record_byte_length" => nil,
    "targeted_task_checks" => "PASS_HISTORICAL_ONLY",
    "repository_make_verify" => "NON_PASS",
    "candidate_accepted" => false,
    "candidate_integrated" => false,
    "capability_claims" => 0
  }
  candidate_record = {
    "record_type" => "synthetic_candidate_nonpass_record",
    "status" => "NON_PASS_STOP_CONDITION_TRIGGERED",
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "rejected_candidate" => {
      "commit" => candidate_commit,
      "tree" => candidate_tree,
      "candidate_accepted" => false,
      "canonical_main_advanced" => false
    },
    "negative_execution_facts" => { "capability_claims" => 0 }
  }
  write_json(candidate_record_path, candidate_record)
  rejected["candidate_nonpass_record_sha256"] = Digest::SHA256.file(candidate_record_path).hexdigest
  rejected["candidate_nonpass_record_byte_length"] = File.size(candidate_record_path)
  review_bindings = {}
  %w[cto security quality].each do |role|
    review_path = File.join(terminal_root, "SYNTHETIC_#{role.upcase}_TERMINAL_REVIEW.json")
    write_json(review_path, {
      "record_type" => "synthetic_#{role}_terminal_review",
      "status" => "NON_PASS",
      "task_id" => task_id,
      "attempt_ordinal" => 1
    })
    review_bindings[role] = {
      "path" => review_path,
      "sha256" => Digest::SHA256.file(review_path).hexdigest,
      "byte_length" => File.size(review_path),
      "status" => "NON_PASS"
    }
  end
  rollback_path = File.join(terminal_root, "SYNTHETIC_ROLLBACK_RECEIPT.json")
  rollback_receipt = {
    "record_type" => "synthetic_terminal_rollback_receipt",
    "status" => "PASS",
    "task_id" => task_id,
    "removed_task_resources" => { "branch_absent" => true, "worktree_absent" => true },
    "rejected_candidate_preservation" => {
      "commit" => candidate_commit,
      "tree" => candidate_tree,
      "ref" => tag,
      "candidate_integrated_to_main" => false
    }
  }
  write_json(rollback_path, rollback_receipt)
  rollback = {
    "receipt_path" => rollback_path,
    "receipt_sha256" => Digest::SHA256.file(rollback_path).hexdigest,
    "receipt_byte_length" => File.size(rollback_path),
    "task_branch_removed" => true,
    "task_worktree_removed" => true,
    "canonical_commit_unchanged" => candidate_commit,
    "canonical_tree_unchanged" => candidate_tree
  }
  bindings = {
    "slice_ordinal" => 1,
    "project_level_rebaseline_decision_sha256" => truth.dig("mandatory_exit_capability_recovery", "project_level_rebaseline", "decision_record_sha256"),
    "delivery_architecture_simplification_decision_sha256" => truth.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt", "delivery_architecture_simplification_decision_sha256"),
    "project_level_reopen_decision_sha256" => truth.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "decision_record_sha256")
  }
  manifest_path = File.join(terminal_root, "TERMINAL_EVIDENCE_MANIFEST.json")
  manifest = {
    "record_type" => "aios_p1_mandatory_capability_terminal_evidence_manifest",
    "status" => "TERMINAL_STOPPED_AFTER_REAL_ARCHITECTURE_ROOT",
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "task_contract_sha256" => contract_sha256,
    "bounded_contract_corrections_used" => contract["bounded_contract_corrections_used"],
    "failure_classification" => "REAL_ARCHITECTURE_ROOT",
    "mandatory_exit_capabilities" => capabilities
  }
  write_json(manifest_path, manifest)
  terminal_record_path = File.join(terminal_root, "SYNTHETIC_TERMINAL_STOP_RECORD.json")
  claim_boundary = "SYNTHETIC_REAL_ARCHITECTURE_ROOT_TERMINAL_EVIDENCE_ONLY"
  terminal_record = {
    "record_type" => "aios_p1_#{task_number}_terminal_stop_record",
    "status" => "TERMINAL_STOPPED_AFTER_REAL_ARCHITECTURE_ROOT",
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "terminal_classification" => "ARCHITECTURE_BLOCKED",
    "failure_classification" => "REAL_ARCHITECTURE_ROOT",
    "founder_escalation_required" => true,
    "task_contract" => contract,
    "mandatory_exit_capabilities" => capabilities,
    "project_level_bindings" => bindings,
    "activation" => activation,
    "quality_freeze" => quality,
    "rejected_candidate" => rejected,
    "independent_terminal_reviews" => review_bindings,
    "rollback" => rollback,
    "terminal_evidence_manifest" => {
      "path" => manifest_path,
      "sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "byte_length" => File.size(manifest_path)
    },
    "prohibitions" => {
      "retry" => false,
      "successor" => false,
      "replacement" => false,
      "historical_candidate_reuse" => false,
      "continue_to_slice_2" => false
    },
    "next_required_decision" => "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED",
    "claim_boundary" => claim_boundary
  }
  write_json(terminal_record_path, terminal_record)
  {
    "task_id" => task_id,
    "status" => terminal_record["status"],
    "terminal_classification" => "ARCHITECTURE_BLOCKED",
    "failure_classification" => "REAL_ARCHITECTURE_ROOT",
    "mandatory_exit_capability" => capabilities.first,
    "integrated_mandatory_exit_capabilities" => capabilities,
    "clean_room_attempt_ordinal" => 1,
    "project_level_rebaseline_slice_ordinal" => 1,
    "project_level_rebaseline_decision_sha256" => bindings["project_level_rebaseline_decision_sha256"],
    "project_level_reopen_decision_sha256" => bindings["project_level_reopen_decision_sha256"],
    "founder_escalation_required" => true,
    "task_contract" => contract,
    "project_level_bindings" => bindings,
    "activation" => activation,
    "quality_freeze" => quality,
    "quality_freeze_receipt" => {
      "path" => quality_receipt_path,
      "sha256" => Digest::SHA256.file(quality_receipt_path).hexdigest,
      "byte_length" => File.size(quality_receipt_path)
    },
    "rejected_candidate" => rejected,
    "independent_terminal_reviews" => review_bindings,
    "rollback" => rollback,
    "execution_evidence_root" => terminal_root,
    "terminal_evidence" => {
      "terminal_stop_record_path" => terminal_record_path,
      "terminal_stop_record_sha256" => Digest::SHA256.file(terminal_record_path).hexdigest,
      "terminal_stop_record_byte_length" => File.size(terminal_record_path),
      "evidence_manifest_path" => manifest_path,
      "evidence_manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "evidence_manifest_byte_length" => File.size(manifest_path)
    },
    "candidate_accepted" => false,
    "candidate_integrated" => false,
    "capability_claims" => 0,
    "recovery_allowed" => false,
    "asset_reuse_allowed" => false,
    "retry_allowed" => false,
    "successor_allowed" => false,
    "replacement_allowed" => false,
    "continue_to_next_slice" => false,
    "claim_boundary" => claim_boundary
  }
end

def current_reopen_terminal_fixture(active_truth, stage, task_id:, contract_sha256:, terminal_evidence_root: nil, terminal_status_override: nil)
  value = current_reopen_lifecycle_fixture(
    active_truth,
    stage,
    task_id: task_id,
    contract_sha256: contract_sha256
  )
  project_status = stage == "ARCHITECTURE_BLOCKED" ?
    "TERMINAL_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION" :
    "PERMANENTLY_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION"
  active = value.fetch("active_work")
  active.keys.each { |key| active[key] = nil }
  active.merge!({
    "current_task" => "NONE",
    "current_task_status" => "NONE",
    "execution_nonce_status" => "NOT_APPLICABLE_TERMINAL_STOPPED",
    "task_resource_state" => stage == "ARCHITECTURE_BLOCKED" ?
      "TERMINAL_STOPPED_RESOURCES_PRESERVED" :
      "TERMINAL_STOPPED_RESOURCES_ABSENT",
    "founder_decision_required" => true,
    "escalation_reason" => stage == "ARCHITECTURE_BLOCKED" ?
      "CURRENT_REBASELINED_SLICE_ARCHITECTURE_BLOCKED" :
      "CURRENT_REBASELINED_SLICE_SCOPE_COMPLIANCE_BLOCKED",
    "user_action_required" => "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED",
    "next_eligible_action" => "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED"
  })
  value.fetch("phase_execution_claim")["current_task_claim"] = project_status == "TERMINAL_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION" ?
    "NONE_P1_TERMINAL_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION" :
    "NONE_P1_PERMANENTLY_STOPPED_PENDING_PROJECT_LEVEL_DISPOSITION"
  capabilities = value.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt", "integrated_mandatory_exit_capabilities")
  terminal_status = terminal_status_override || (stage == "ARCHITECTURE_BLOCKED" ?
    "TERMINAL_STOPPED_AFTER_REAL_ARCHITECTURE_ROOT" :
    "TERMINAL_STOPPED_AFTER_SCOPE_COMPLIANCE_FAILURE")
  failure_classification = stage == "ARCHITECTURE_BLOCKED" ? "REAL_ARCHITECTURE_ROOT" : "SCOPE_COMPLIANCE_FAILURE"
  terminal_root = terminal_evidence_root || active_truth.dig("active_work", "execution_evidence_root")
  FileUtils.mkdir_p(terminal_root)
  contract_path = active_truth.dig("active_work", "current_task_contract")
  if stage == "ARCHITECTURE_BLOCKED" &&
      terminal_status == "TERMINAL_STOPPED_AFTER_REAL_ARCHITECTURE_ROOT" &&
      contract_path
    value.fetch("task_history")["synthetic_current_reopen_#{stage.downcase}"] = install_synthetic_architecture_terminal_evidence!(
      value, task_id, contract_sha256, contract_path, terminal_root, capabilities
    )
    return value
  end
  manifest_path = File.join(terminal_root, "TERMINAL_EVIDENCE_MANIFEST_#{Digest::SHA256.hexdigest(terminal_status)[0, 8]}.json")
  write_json(manifest_path, {
    "record_type" => "aios_p1_mandatory_capability_terminal_evidence_manifest",
    "status" => terminal_status,
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "task_contract_sha256" => contract_sha256,
    "bounded_contract_corrections_used" => 0,
    "failure_classification" => failure_classification,
    "mandatory_exit_capabilities" => capabilities
  })
  value.fetch("task_history")["synthetic_current_reopen_#{stage.downcase}"] = {
    "task_id" => task_id,
    "status" => terminal_status,
    "mandatory_exit_capability" => capabilities.first,
    "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(capabilities)),
    "clean_room_attempt_ordinal" => 1,
    "project_level_rebaseline_slice_ordinal" => 1,
    "project_level_rebaseline_decision_sha256" => value.dig("mandatory_exit_capability_recovery", "project_level_rebaseline", "decision_record_sha256"),
    "project_level_reopen_decision_sha256" => value.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "decision_record_sha256"),
    "founder_escalation_required" => true,
    "execution_evidence_root" => terminal_root,
    "terminal_evidence" => {
      "evidence_manifest_path" => manifest_path,
      "evidence_manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest
    }
  }
  value
end

def later_rebaseline_slice_fixture(base_truth, ordinal, stage)
  raise "later Slice fixture ordinal invalid" unless ordinal.between?(2, 4)
  raise "later Slice fixture stage invalid" unless %w[ACTIVE ACCEPTED].include?(stage)
  value = Marshal.load(Marshal.dump(base_truth))
  recovery = value.fetch("mandatory_exit_capability_recovery")
  rebaseline = recovery.fetch("project_level_rebaseline")
  delivery = recovery.fetch("delivery_architecture_simplification")
  slice = rebaseline.fetch("slices").find { |candidate| candidate["ordinal"] == ordinal }
  task_id = "AIOS-P1-#{950 + ordinal}_SYNTHETIC_SLICE_#{ordinal}"
  attempt = {
    "status" => stage,
    "task_id" => task_id,
    "attempt_ordinal" => 1,
    "contract_sha256" => Digest::SHA256.hexdigest("#{task_id}:contract"),
    "bounded_contract_corrections_used" => 0,
    "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(slice.fetch("capability_projection"))),
    "project_level_rebaseline_slice_ordinal" => ordinal,
    "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
    "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256")
  }
  rebaseline.fetch("slice_attempts")[ordinal.to_s] = attempt
  capability_status = stage == "ACTIVE" ? "IN_PROGRESS" : "ACCEPTED"
  slice.fetch("capability_projection").each do |capability|
    recovery.fetch("capability_status")[capability] = capability_status
  end
  if stage == "ACTIVE"
    rebaseline["status"] = "REBASELINED_SLICE_ACTIVE"
    rebaseline["p1_status"] = "REBASELINED_SLICE_ACTIVE"
    rebaseline["current_task"] = task_id
    rebaseline["next_slice_ordinal"] = ordinal
    rebaseline["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_#{ordinal}"
    value.fetch("project")["phase_execution_status"] = "TASK_ACTIVE"
    value.fetch("project")["p1_execution_status"] = "TASK_ACTIVE"
    value.fetch("goal")["current_task_authority"] = task_id
    value.fetch("active_work")["current_task"] = task_id
  elsif ordinal < 4
    rebaseline["status"] = "REBASELINED_PENDING_EXECUTION"
    rebaseline["p1_status"] = "REBASELINED_PENDING_EXECUTION"
    rebaseline["current_task"] = "NONE"
    rebaseline["next_slice_ordinal"] = ordinal + 1
    rebaseline["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_#{ordinal + 1}"
    value.fetch("project")["phase_execution_status"] = "REBASELINED_PENDING_EXECUTION"
    value.fetch("project")["p1_execution_status"] = "REBASELINED_PENDING_EXECUTION"
    value.fetch("goal")["current_task_authority"] = "NONE"
    value.fetch("active_work")["current_task"] = "NONE"
  else
    rebaseline["status"] = "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
    rebaseline["p1_status"] = "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
    rebaseline["current_task"] = "NONE"
    rebaseline["next_slice_ordinal"] = nil
    rebaseline["next_slice_action"] = "FOUNDER_P1_PHASE_GATE_REVIEW_REQUIRED"
  end
  value
end

def install_rebaseline_gate_evidence!(truth, evidence_base, candidate_commit, candidate_tree, contract_sha_by_ordinal = {}, candidate_identity_by_ordinal = {})
  value = Marshal.load(Marshal.dump(truth))
  recovery = value.fetch("mandatory_exit_capability_recovery")
  rebaseline = recovery.fetch("project_level_rebaseline")
  delivery = recovery.fetch("delivery_architecture_simplification")
  reopen = recovery.fetch("current_project_level_reopen")

  rebaseline.fetch("slices").each do |slice|
    ordinal = slice.fetch("ordinal")
    capabilities = Marshal.load(Marshal.dump(slice.fetch("capability_projection")))
    task_id = "AIOS-P1-#{970 + ordinal}_SYNTHETIC_GATE_SLICE_#{ordinal}"
    contract_sha = contract_sha_by_ordinal.fetch(ordinal, Digest::SHA256.hexdigest("#{task_id}:frozen-contract"))
    slice_candidate_commit, slice_candidate_tree = candidate_identity_by_ordinal.fetch(ordinal, [candidate_commit, candidate_tree])
    attempt = {
      "status" => "ACCEPTED",
      "task_id" => task_id,
      "attempt_ordinal" => 1,
      "contract_sha256" => contract_sha,
      "bounded_contract_corrections_used" => 0,
      "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(capabilities)),
      "project_level_rebaseline_slice_ordinal" => ordinal,
      "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
      "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256")
    }
    if ordinal == 1
      attempt["project_level_reopen_decision_sha256"] = reopen.fetch("decision_record_sha256")
      reopen["current_slice_attempt"] = attempt
      reopen["current_p1_status"] = "ACCEPTED"
      reopen["current_task"] = "NONE"
      reopen["next_slice_ordinal"] = ordinal + 1
      reopen["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_#{ordinal + 1}"
    else
      rebaseline.fetch("slice_attempts")[ordinal.to_s] = attempt
    end
    capabilities.each { |capability| recovery.fetch("capability_status")[capability] = "ACCEPTED" }

    evidence_root = File.join(evidence_base, "synthetic-gate-slice-#{ordinal}")
    FileUtils.mkdir_p(evidence_root)
    result_path = File.join(evidence_root, "result.txt")
    File.write(result_path, "synthetic accepted Slice #{ordinal}\n", mode: "w:UTF-8")
    binding = capabilities.length == 1 ? { "mandatory_exit_capability" => capabilities.first } : { "mandatory_exit_capabilities" => capabilities }
    artifact_index_path = File.join(evidence_root, "ARTIFACT_INDEX.json")
    write_json(artifact_index_path, {
      "record_type" => "aios_p1_mandatory_capability_artifact_index",
      "status" => "FROZEN",
      "task_id" => task_id,
      "candidate_commit" => slice_candidate_commit,
      "candidate_tree" => slice_candidate_tree,
      "artifacts" => [{
        "path" => "result.txt",
        "sha256" => Digest::SHA256.file(result_path).hexdigest,
        "byte_length" => File.size(result_path)
      }]
    }.merge(binding))
    artifact_index_sha = Digest::SHA256.file(artifact_index_path).hexdigest
    manifest_path = File.join(evidence_root, "EVIDENCE_MANIFEST.json")
    write_json(manifest_path, {
      "record_type" => "aios_p1_mandatory_capability_evidence_manifest",
      "status" => "FROZEN",
      "task_id" => task_id,
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => slice_candidate_commit,
      "candidate_tree" => slice_candidate_tree,
      "artifact_index_path" => artifact_index_path,
      "artifact_index_sha256" => artifact_index_sha,
      "replay_result" => "PASS",
      "rebuild_result" => "PASS",
      "rollback_result" => "PASS",
      "claim_boundary" => slice.fetch("claim_boundary")
    }.merge(binding))
    manifest_sha = Digest::SHA256.file(manifest_path).hexdigest
    review_paths = {}
    review_hashes = {}
    %w[cto security quality].each do |role|
      review_path = File.join(evidence_root, "#{role.upcase}_REVIEW.json")
      write_json(review_path, {
        "record_type" => "aios_independent_task_review",
        "status" => "PASS",
        "role" => role.upcase,
        "task_id" => task_id,
        "task_contract_sha256" => contract_sha,
        "candidate_commit" => slice_candidate_commit,
        "candidate_tree" => slice_candidate_tree,
        "evidence_manifest_sha256" => manifest_sha,
        "claim_boundary" => slice.fetch("claim_boundary")
      }.merge(binding))
      review_paths[role] = review_path
      review_hashes[role] = Digest::SHA256.file(review_path).hexdigest
    end
    gate_path = File.join(evidence_root, "TASK_GATE_RECEIPT.json")
    write_json(gate_path, {
      "record_type" => "aios_phase_delegated_task_gate_receipt",
      "status" => "ACCEPTED",
      "authority" => "MASTER_CEO_AGENT",
      "task_id" => task_id,
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => slice_candidate_commit,
      "candidate_tree" => slice_candidate_tree,
      "evidence_manifest_sha256" => manifest_sha,
      "cto_review_sha256" => review_hashes.fetch("cto"),
      "security_review_sha256" => review_hashes.fetch("security"),
      "quality_review_sha256" => review_hashes.fetch("quality"),
      "claim_boundary" => slice.fetch("claim_boundary")
    }.merge(binding))

    history = {
      "task_id" => task_id,
      "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      "mandatory_exit_capability" => capabilities.first,
      "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(capabilities)),
      "clean_room_attempt_ordinal" => 1,
      "project_level_rebaseline_slice_ordinal" => ordinal,
      "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
      "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256"),
      "task_gate_result" => "PASS",
      "task_contract_sha256" => contract_sha,
      "bounded_contract_corrections_used" => 0,
      "accepted_candidate_commit" => slice_candidate_commit,
      "accepted_candidate_tree" => slice_candidate_tree,
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
      "claim_boundary" => slice.fetch("claim_boundary")
    }
    history["project_level_reopen_decision_sha256"] = reopen.fetch("decision_record_sha256") if ordinal == 1
    value.fetch("task_history")["synthetic_gate_slice_#{ordinal}"] = history
  end

  dataset_capability = "VERSIONED_REPRESENTATIVE_TASK_DATASET"
  dataset_task_id = "AIOS-P1-969_SYNTHETIC_PREACCEPTED_DATASET"
  dataset_contract_sha = Digest::SHA256.hexdigest("#{dataset_task_id}:frozen-contract")
  dataset_claim_boundary = "P1_EXIT_CAPABILITY_ENGINEERING_ARTIFACT_ONLY_NO_BENCHMARK_AGENT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM"
  dataset_root = File.join(evidence_base, "synthetic-preaccepted-dataset")
  FileUtils.mkdir_p(dataset_root)
  dataset_result_path = File.join(dataset_root, "result.txt")
  File.write(dataset_result_path, "synthetic preaccepted dataset\n", mode: "w:UTF-8")
  dataset_artifact_index_path = File.join(dataset_root, "ARTIFACT_INDEX.json")
  write_json(dataset_artifact_index_path, {
    "record_type" => "aios_p1_mandatory_capability_artifact_index",
    "status" => "FROZEN",
    "task_id" => dataset_task_id,
    "mandatory_exit_capability" => dataset_capability,
    "candidate_commit" => candidate_commit,
    "candidate_tree" => candidate_tree,
    "artifacts" => [{
      "path" => "result.txt",
      "sha256" => Digest::SHA256.file(dataset_result_path).hexdigest,
      "byte_length" => File.size(dataset_result_path)
    }]
  })
  dataset_artifact_index_sha = Digest::SHA256.file(dataset_artifact_index_path).hexdigest
  dataset_manifest_path = File.join(dataset_root, "EVIDENCE_MANIFEST.json")
  write_json(dataset_manifest_path, {
    "record_type" => "aios_p1_mandatory_capability_evidence_manifest",
    "status" => "FROZEN",
    "task_id" => dataset_task_id,
    "task_contract_sha256" => dataset_contract_sha,
    "candidate_commit" => candidate_commit,
    "candidate_tree" => candidate_tree,
    "artifact_index_path" => dataset_artifact_index_path,
    "artifact_index_sha256" => dataset_artifact_index_sha,
    "replay_result" => "PASS",
    "rebuild_result" => "PASS",
    "rollback_result" => "PASS",
    "claim_boundary" => dataset_claim_boundary,
    "mandatory_exit_capability" => dataset_capability
  })
  dataset_manifest_sha = Digest::SHA256.file(dataset_manifest_path).hexdigest
  dataset_review_paths = {}
  dataset_review_hashes = {}
  %w[cto security quality].each do |role|
    review_path = File.join(dataset_root, "#{role.upcase}_REVIEW.json")
    write_json(review_path, {
      "record_type" => "aios_independent_task_review",
      "status" => "PASS",
      "role" => role.upcase,
      "task_id" => dataset_task_id,
      "task_contract_sha256" => dataset_contract_sha,
      "candidate_commit" => candidate_commit,
      "candidate_tree" => candidate_tree,
      "evidence_manifest_sha256" => dataset_manifest_sha,
      "claim_boundary" => dataset_claim_boundary,
      "mandatory_exit_capability" => dataset_capability
    })
    dataset_review_paths[role] = review_path
    dataset_review_hashes[role] = Digest::SHA256.file(review_path).hexdigest
  end
  dataset_gate_path = File.join(dataset_root, "TASK_GATE_RECEIPT.json")
  write_json(dataset_gate_path, {
    "record_type" => "aios_phase_delegated_task_gate_receipt",
    "status" => "ACCEPTED",
    "authority" => "MASTER_CEO_AGENT",
    "task_id" => dataset_task_id,
    "task_contract_sha256" => dataset_contract_sha,
    "candidate_commit" => candidate_commit,
    "candidate_tree" => candidate_tree,
    "evidence_manifest_sha256" => dataset_manifest_sha,
    "cto_review_sha256" => dataset_review_hashes.fetch("cto"),
    "security_review_sha256" => dataset_review_hashes.fetch("security"),
    "quality_review_sha256" => dataset_review_hashes.fetch("quality"),
    "claim_boundary" => dataset_claim_boundary,
    "mandatory_exit_capability" => dataset_capability
  })
  recovery.fetch("capability_status")[dataset_capability] = "ACCEPTED"
  recovery.fetch("capability_attempt_ledger")[dataset_capability] = {
    "status" => "ACCEPTED",
    "task_id" => dataset_task_id,
    "attempt_ordinal" => 1,
    "contract_sha256" => dataset_contract_sha,
    "bounded_contract_corrections_used" => 0
  }
  value.fetch("task_history")["synthetic_preaccepted_dataset"] = {
    "task_id" => dataset_task_id,
    "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
    "mandatory_exit_capability" => dataset_capability,
    "clean_room_attempt_ordinal" => 1,
    "task_gate_result" => "PASS",
    "task_contract_sha256" => dataset_contract_sha,
    "bounded_contract_corrections_used" => 0,
    "accepted_candidate_commit" => candidate_commit,
    "accepted_candidate_tree" => candidate_tree,
    "execution_evidence_root" => dataset_root,
    "evidence_manifest_path" => dataset_manifest_path,
    "evidence_manifest_sha256" => dataset_manifest_sha,
    "artifact_index_path" => dataset_artifact_index_path,
    "artifact_index_sha256" => dataset_artifact_index_sha,
    "cto_review_path" => dataset_review_paths.fetch("cto"),
    "cto_review_sha256" => dataset_review_hashes.fetch("cto"),
    "security_review_path" => dataset_review_paths.fetch("security"),
    "security_review_sha256" => dataset_review_hashes.fetch("security"),
    "quality_review_path" => dataset_review_paths.fetch("quality"),
    "quality_review_sha256" => dataset_review_hashes.fetch("quality"),
    "task_gate_receipt_path" => dataset_gate_path,
    "task_gate_receipt_sha256" => Digest::SHA256.file(dataset_gate_path).hexdigest,
    "claim_boundary" => dataset_claim_boundary
  }

  rebaseline["status"] = "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
  rebaseline["p1_status"] = "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
  rebaseline["current_task"] = "NONE"
  rebaseline["next_slice_ordinal"] = nil
  rebaseline["next_slice_action"] = "FOUNDER_P1_PHASE_GATE_REVIEW_REQUIRED"
  value.fetch("project")["phase_execution_status"] = "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
  value.fetch("project")["p1_execution_status"] = "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
  value.fetch("goal")["current_task_authority"] = "NONE"
  active = value.fetch("active_work")
  active.keys.each { |key| active[key] = nil }
  active.merge!({
    "current_task" => "NONE",
    "current_task_status" => "NONE",
    "execution_nonce_status" => "NONE",
    "task_resource_state" => "NONE",
    "founder_decision_required" => true,
    "escalation_reason" => "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE",
    "user_action_required" => "FOUNDER_P1_PHASE_GATE_REVIEW_REQUIRED",
    "next_eligible_action" => "FOUNDER_P1_PHASE_GATE_REVIEW_REQUIRED"
  })
  value.fetch("phase_execution_claim")["current_task_claim"] = "NONE_P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
  value.fetch("claim_boundary")["p1_status"] = "P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE"
  value
end

def slice_4_active_before_gate_fixture(gate_truth)
  value = Marshal.load(Marshal.dump(gate_truth))
  recovery = value.fetch("mandatory_exit_capability_recovery")
  rebaseline = recovery.fetch("project_level_rebaseline")
  slice = rebaseline.fetch("slices").find { |candidate| candidate["ordinal"] == 4 }
  attempt = rebaseline.fetch("slice_attempts").fetch("4")
  attempt["status"] = "ACTIVE"
  task_id = attempt.fetch("task_id")
  slice.fetch("capability_projection").each { |capability| recovery.fetch("capability_status")[capability] = "IN_PROGRESS" }
  value.fetch("task_history").delete("synthetic_gate_slice_4")
  rebaseline["status"] = "REBASELINED_SLICE_ACTIVE"
  rebaseline["p1_status"] = "REBASELINED_SLICE_ACTIVE"
  rebaseline["current_task"] = task_id
  rebaseline["next_slice_ordinal"] = 4
  rebaseline["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_4"
  value.fetch("project")["phase_execution_status"] = "TASK_ACTIVE"
  value.fetch("project")["p1_execution_status"] = "TASK_ACTIVE"
  value.fetch("goal")["current_task_authority"] = task_id
  value.fetch("active_work")["current_task"] = task_id
  value.fetch("phase_execution_claim")["current_task_claim"] = task_id
  value.fetch("claim_boundary")["p1_status"] = "REBASELINED_SLICE_ACTIVE"
  value
end

def slice_4_pending_before_activation_fixture(gate_truth)
  value = Marshal.load(Marshal.dump(gate_truth))
  recovery = value.fetch("mandatory_exit_capability_recovery")
  rebaseline = recovery.fetch("project_level_rebaseline")
  slice = rebaseline.fetch("slices").find { |candidate| candidate["ordinal"] == 4 }
  rebaseline.fetch("slice_attempts").delete("4")
  value.fetch("task_history").delete("synthetic_gate_slice_4")
  slice.fetch("capability_projection").each do |capability|
    recovery.fetch("capability_status")[capability] = "REBASELINED_PENDING_EXECUTION"
  end
  rebaseline["status"] = "REBASELINED_PENDING_EXECUTION"
  rebaseline["p1_status"] = "REBASELINED_PENDING_EXECUTION"
  rebaseline["current_task"] = "NONE"
  rebaseline["next_slice_ordinal"] = 4
  rebaseline["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_4"
  value.fetch("project")["phase_execution_status"] = "REBASELINED_PENDING_EXECUTION"
  value.fetch("project")["p1_execution_status"] = "REBASELINED_PENDING_EXECUTION"
  value.fetch("goal")["current_task_authority"] = "NONE"
  active = value.fetch("active_work")
  active.keys.each { |key| active[key] = nil }
  active.merge!({
    "current_task" => "NONE",
    "current_task_status" => "NONE",
    "execution_nonce_status" => "NONE",
    "task_resource_state" => "NONE",
    "founder_decision_required" => false,
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_4"
  })
  value.fetch("phase_execution_claim")["current_task_claim"] = "NONE_P1_REBASELINED_PENDING_EXECUTION"
  value.fetch("claim_boundary")["p1_status"] = "REBASELINED_PENDING_EXECUTION"
  value
end

Dir.mktmpdir("aios-rebuild-authority-") do |root|
  canonical_root = File.join(root, "canonical")
  rebuild_root = File.join(root, "fresh-clone")
  run!("git", "clone", "--no-local", "--branch", "main", SOURCE_ROOT, canonical_root)
  FileUtils.cp(File.join(SOURCE_ROOT, "AGENTS.md"), File.join(canonical_root, "AGENTS.md"))
  FileUtils.cp(File.join(SOURCE_ROOT, "docs/aios/truth/project_state.yaml"), File.join(canonical_root, "docs/aios/truth/project_state.yaml"))
  FileUtils.cp(File.join(SOURCE_ROOT, "scripts/validate-current-task-authority.rb"), File.join(canonical_root, "scripts/validate-current-task-authority.rb"))
  truth_path = File.join(canonical_root, "docs/aios/truth/project_state.yaml")
  truth = YAML.safe_load(File.read(truth_path), aliases: false)
  truth = current_reopen_lifecycle_fixture(truth, "PENDING")
  truth.fetch("claim_boundary")["p1_status"] = "REBASELINED_PENDING_EXECUTION"
  truth.fetch("phase_execution_claim")["current_task_claim"] = "NONE_P1_REBASELINED_PENDING_EXECUTION"
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
    "user_action_required" => "NONE",
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_1"
  }
  truth["project"]["canonical_repository"] = canonical_root
  truth["project"]["task_worktree_root"] = File.join(root, "task-worktrees")
  FileUtils.mkdir_p(truth["project"]["task_worktree_root"])
  write_yaml(truth_path, truth)
  run!("git", "config", "user.name", "SourceLens Rebuild Verification Test", chdir: canonical_root)
  run!("git", "config", "user.email", "rebuild-verification@example.invalid", chdir: canonical_root)
  run!("git", "add", "AGENTS.md", "docs/aios/truth/project_state.yaml", "scripts/validate-current-task-authority.rb", chdir: canonical_root)
  run!("git", "commit", "--amend", "-m", "synthetic rebuild authority source", chdir: canonical_root)

  run!("git", "clone", "--no-local", "--branch", "main", canonical_root, rebuild_root)
  run_validator(rebuild_root, false, "wrong workspace common-dir normal mode negative", expected_failure: "canonical repository identity drift")
  run_validator(canonical_root, false, "canonical cannot use rebuild mode negative", expected_failure: "requires a non-canonical fresh clone", env: { "SOURCELENS_REBUILD_VERIFY" => "1" })
  run_validator(rebuild_root, true, "fresh clone rebuild approved and current routing separation nonregression positive", env: { "SOURCELENS_REBUILD_VERIFY" => "1" })

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
  FileUtils.cp(File.join(SOURCE_ROOT, "scripts/validate-aios-governance.sh"), File.join(root, "scripts"))
  FileUtils.cp(File.join(SOURCE_ROOT, "scripts/check-p1-safety-boundary.sh"), File.join(root, "scripts"))
  FileUtils.cp(File.join(SOURCE_ROOT, "AGENTS.md"), root)
  FileUtils.cp(File.join(SOURCE_ROOT, "docs/PROJECT_CODE_MAP.md"), File.join(root, "docs"))
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
  rebaseline["status"] = "REBASELINED_PENDING_EXECUTION"
  rebaseline["p1_status"] = "REBASELINED_PENDING_EXECUTION"
  rebaseline["current_task"] = "NONE"
  rebaseline["next_slice_ordinal"] = 1
  rebaseline["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_1"
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
  delivery = truth.dig("mandatory_exit_capability_recovery", "delivery_architecture_simplification")
  delivery_root = File.join(evidence_base, "p1-delivery-architecture-simplification")
  FileUtils.mkdir_p(delivery_root)
  delivery_source = delivery.fetch("decision_record_path")
  delivery_target = File.join(delivery_root, "FOUNDER_P1_DELIVERY_ARCHITECTURE_SIMPLIFICATION_DECISION_RECORD.json")
  FileUtils.cp(delivery_source, delivery_target)
  delivery["decision_record_path"] = delivery_target
  project_reopen = truth.dig("mandatory_exit_capability_recovery", "project_level_reopen")
  project_reopen_root = File.join(evidence_base, "p1-project-level-reopen")
  FileUtils.mkdir_p(project_reopen_root)
  project_reopen_source = project_reopen.fetch("decision_record_path")
  project_reopen_target = File.join(project_reopen_root, "FOUNDER_P1_PROJECT_LEVEL_REOPEN_DECISION_RECORD.json")
  FileUtils.cp(project_reopen_source, project_reopen_target)
  project_reopen["decision_record_path"] = project_reopen_target
  current_project_reopen = truth.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")
  current_project_reopen_root = File.join(evidence_base, "p1-current-project-level-reopen")
  FileUtils.mkdir_p(current_project_reopen_root)
  current_project_reopen_source = current_project_reopen.fetch("decision_record_path")
  current_project_reopen_target = File.join(current_project_reopen_root, "FOUNDER_P1_PROJECT_LEVEL_REOPEN_AFTER_P1_042_DECISION_RECORD.json")
  FileUtils.cp(current_project_reopen_source, current_project_reopen_target)
  current_project_reopen["decision_record_path"] = current_project_reopen_target
  current_project_reopen["current_slice_attempt"] = nil
  current_project_reopen["current_p1_status"] = "REBASELINED_PENDING_EXECUTION"
  current_project_reopen["current_task"] = "NONE"
  current_project_reopen["next_slice_ordinal"] = current_project_reopen.dig(
    "approved_reopen_decision_route", "next_slice_ordinal"
  )
  current_project_reopen["next_slice_action"] = current_project_reopen.dig(
    "approved_reopen_decision_route", "next_slice_action"
  )
  p1_041_history = truth.fetch("task_history").values.find do |entry|
    entry.is_a?(Hash) && entry["task_id"] == "AIOS-P1-041_PARAMETERIZED_EVALUATION_CORE_IMPLEMENTATION"
  end
  raise "current role-local reopen fixture lacks P1-041 terminal metadata" unless p1_041_history
  p1_042_history = Marshal.load(Marshal.dump(truth.fetch("task_history").fetch("aios_p1_042")))
  p1_042_contract_root = File.join(evidence_base, "p1-042-contract-review")
  p1_042_terminal_root = File.join(evidence_base, "p1-042-terminal-custody")
  FileUtils.mkdir_p(p1_042_contract_root)
  FileUtils.mkdir_p(p1_042_terminal_root)
  p1_042_contract_target = File.join(p1_042_contract_root, "WORKING_DRAFT.yaml")
  p1_042_record_target = File.join(p1_042_terminal_root, "P1_042_TERMINAL_STOP_RECORD.json")
  p1_042_manifest_target = File.join(p1_042_terminal_root, "TERMINAL_EVIDENCE_MANIFEST.json")
  p1_042_contract_source = p1_042_history.fetch("task_contract_external_path")
  p1_042_record_source = p1_042_history.fetch("terminal_record_path")
  p1_042_manifest_source = p1_042_history.fetch("terminal_evidence_manifest_path")
  FileUtils.cp(p1_042_contract_source, p1_042_contract_target)
  FileUtils.cp(p1_042_record_source, p1_042_record_target)
  FileUtils.cp(p1_042_manifest_source, p1_042_manifest_target)
  p1_042_relocated_history = Marshal.load(Marshal.dump(p1_042_history))
  p1_042_relocated_history["task_contract_external_path"] = p1_042_contract_target
  p1_042_relocated_history["execution_evidence_root"] = p1_042_terminal_root
  p1_042_relocated_history["terminal_record_path"] = p1_042_record_target
  p1_042_relocated_history["terminal_evidence_manifest_path"] = p1_042_manifest_target
  truth["task_history"] = {
    "aios_p1_006" => {
      "task_id" => "AIOS-P1-006_SYNTHETIC_TERMINAL_HISTORY",
      "status" => "TERMINAL_STOPPED",
      "resume_retry_successor_allowed" => false
    },
    "aios_p1_041" => Marshal.load(Marshal.dump(p1_041_history)),
    "aios_p1_042" => p1_042_history
  }
  truth["mandatory_exit_capability_recovery"]["capability_status"].keys.each do |capability|
    truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "MISSING"
    truth["mandatory_exit_capability_recovery"]["capability_attempt_ledger"][capability] = nil
  end
  rebaseline.fetch("slices").flat_map { |slice| slice.fetch("capability_projection") }.each do |capability|
    truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "REBASELINED_PENDING_EXECUTION"
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
  truth["project"]["phase_execution_status"] = "REBASELINED_PENDING_EXECUTION"
  truth["project"]["p1_execution_status"] = "REBASELINED_PENDING_EXECUTION"
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
    "user_action_required" => "NONE",
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_1"
  }
  truth["phase_execution_claim"]["current_task_claim"] = "NONE_P1_REBASELINED_PENDING_EXECUTION"
  truth["claim_boundary"]["p1_status"] = "REBASELINED_PENDING_EXECUTION"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)

  run!("git", "init", chdir: root)
  run!("git", "config", "user.name", "SourceLens Validator Test", chdir: root)
  run!("git", "config", "user.email", "validator@example.invalid", chdir: root)
  run!("git", "add", ".", chdir: root)
  run!("git", "commit", "-m", "base", chdir: root)
  run!("git", "branch", "-M", "main", chdir: root)
  import_commit_and_tree_metadata!(root, rebaseline.fetch("canonical_parent_commit"))
  import_commit_and_tree_metadata!(root, current_project_reopen.fetch("canonical_parent_commit"))
  run_validator(root, true, "NONE positive")
  bypass_stdout, bypass_stderr, bypass_status = Open3.capture3(
    "ruby", "scripts/validate-current-task-authority.rb", "--validate-current-reopen-transition",
    chdir: root
  )
  raise "production validator accepted a helper bypass argument" if bypass_status.success?
  bypass_output = "#{bypass_stdout}#{bypass_stderr}"
  raise "production validator helper bypass did not fail closed" unless bypass_output.include?("does not accept arguments")
  raise "production validator helper bypass emitted an authority PASS" if bypass_output.include?("authority validation passed")

  none_truth = Marshal.load(Marshal.dump(truth))
  pending_current_reopen = current_reopen_lifecycle_fixture(none_truth, "PENDING")
  active_current_reopen = current_reopen_lifecycle_fixture(none_truth, "ACTIVE")
  accepted_current_reopen = current_reopen_lifecycle_fixture(none_truth, "ACCEPTED")
  transition_terminal_root = File.join(evidence_base, "synthetic-current-reopen-transition-terminal")
  active_current_reopen.fetch("active_work")["execution_evidence_root"] = transition_terminal_root
  architecture_blocked_current_reopen = current_reopen_terminal_fixture(
    active_current_reopen,
    "ARCHITECTURE_BLOCKED",
    task_id: "AIOS-P1-943_CURRENT_REOPEN_LIFECYCLE_TEST",
    contract_sha256: "a" * 64,
    terminal_evidence_root: transition_terminal_root
  )
  scope_blocked_current_reopen = current_reopen_terminal_fixture(
    active_current_reopen,
    "SCOPE_COMPLIANCE_BLOCKED",
    task_id: "AIOS-P1-943_CURRENT_REOPEN_LIFECYCLE_TEST",
    contract_sha256: "a" * 64,
    terminal_evidence_root: transition_terminal_root
  )
  run_current_reopen_transition(root, pending_current_reopen, pending_current_reopen, true, "current reopen pending NONE positive")
  run_current_reopen_transition(root, pending_current_reopen, active_current_reopen, true, "current reopen ordinal-1 ACTIVE positive")
  run_current_reopen_transition(root, active_current_reopen, accepted_current_reopen, true, "current reopen ACCEPTED terminal positive")
  run_current_reopen_transition(root, active_current_reopen, architecture_blocked_current_reopen, true, "current reopen ARCHITECTURE_BLOCKED terminal positive")
  run_current_reopen_transition(root, active_current_reopen, scope_blocked_current_reopen, true, "current reopen SCOPE_COMPLIANCE_BLOCKED terminal positive")

  current_reopen_authority = none_truth.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")
  current_reopen_decision = JSON.parse(File.read(current_reopen_authority.fetch("decision_record_path")))
  run_exact_validator_helper(
    :validate_approved_reopen_decision_binding!,
    [none_truth, current_reopen_authority, current_reopen_decision],
    true,
    "historical approved reopen decision ordinal and action exact binding positive"
  )
  mismatched_historical_decision_action = Marshal.load(Marshal.dump(current_reopen_decision))
  mismatched_historical_decision_action.fetch("decision")["next_slice_action"] = "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED"
  run_exact_validator_helper(
    :validate_approved_reopen_decision_binding!,
    [none_truth, current_reopen_authority, mismatched_historical_decision_action],
    false,
    "historical decision action inconsistent with original decision bytes negative",
    expected_failure: "Founder decision route binding drift"
  )

  legacy_attempt = none_truth.dig("mandatory_exit_capability_recovery", "project_level_reopen", "slice_1_reopen_attempt")
  run_current_reopen_superseding_projection(pending_current_reopen, legacy_attempt, true, "current reopen pending supersedes preserved legacy attempt positive")
  run_current_reopen_superseding_projection(active_current_reopen, legacy_attempt, true, "current reopen ACTIVE supersedes preserved legacy attempt positive")
  run_current_reopen_superseding_projection(accepted_current_reopen, legacy_attempt, true, "current reopen ACCEPTED supersedes preserved legacy attempt positive")
  run_current_reopen_superseding_projection(architecture_blocked_current_reopen, legacy_attempt, true, "current reopen ARCHITECTURE_BLOCKED supersedes preserved legacy attempt positive")
  run_current_reopen_superseding_projection(scope_blocked_current_reopen, legacy_attempt, true, "current reopen SCOPE_COMPLIANCE_BLOCKED supersedes preserved legacy attempt positive")

  forged_legacy_terminal = Marshal.load(Marshal.dump(legacy_attempt))
  forged_legacy_terminal["status"] = "ARCHITECTURE_BLOCKED"
  forged_legacy_terminal["bounded_contract_corrections_used"] = 0
  run_current_reopen_superseding_projection(active_current_reopen, forged_legacy_terminal, false, "current reopen cannot supersede a self-consistently rewritten legacy terminal negative", expected_failure: "cannot supersede the historical attempt")

  forged_pending_supersession = Marshal.load(Marshal.dump(pending_current_reopen))
  forged_pending_supersession.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")["historical_task_id"] = "AIOS-P1-999_FORGED"
  run_current_reopen_superseding_projection(forged_pending_supersession, legacy_attempt, false, "forged pending current reopen cannot supersede preserved legacy attempt negative", expected_failure: "cannot supersede the historical attempt")

  mixed_active_supersession = Marshal.load(Marshal.dump(active_current_reopen))
  mixed_capability = legacy_attempt.fetch("integrated_mandatory_exit_capabilities").first
  mixed_active_supersession.dig("mandatory_exit_capability_recovery", "capability_status")[mixed_capability] = "P1_TERMINAL_STOPPED_NOT_ACCEPTED"
  run_current_reopen_superseding_projection(mixed_active_supersession, legacy_attempt, false, "mixed legacy and ACTIVE capability projection cannot supersede negative", expected_failure: "lifecycle projection drift")

  unknown_active_supersession = Marshal.load(Marshal.dump(active_current_reopen))
  unknown_active_supersession.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt")["status"] = "UNKNOWN_STAGE"
  run_current_reopen_superseding_projection(unknown_active_supersession, legacy_attempt, false, "unknown current reopen lifecycle cannot supersede negative", expected_failure: "attempt binding drift")

  active_claim_projection_drift = Marshal.load(Marshal.dump(active_current_reopen))
  active_claim_projection_drift.fetch("claim_boundary")["p1_status"] = "REBASELINED_PENDING_EXECUTION"
  run_current_reopen_superseding_projection(active_claim_projection_drift, legacy_attempt, false, "current reopen ACTIVE claim lifecycle projection drift negative", expected_failure: "claim lifecycle projection drift")

  slice_2_active_after_accepted = later_rebaseline_slice_fixture(accepted_current_reopen, 2, "ACTIVE")
  run_current_reopen_transition(
    root,
    accepted_current_reopen,
    slice_2_active_after_accepted,
    true,
    "current reopen ACCEPTED steady permits Slice 2 ACTIVE global projection positive"
  )
  run_effective_slice_order(pending_current_reopen, true, "effective Slice order pending ordinal 1 positive")
  run_effective_slice_order(active_current_reopen, true, "effective Slice order ordinal 1 ACTIVE positive")
  run_effective_slice_order(accepted_current_reopen, true, "effective Slice order ordinal 1 ACCEPTED to pending ordinal 2 positive")
  run_effective_slice_order(slice_2_active_after_accepted, true, "effective Slice order ordinal 2 ACTIVE positive")
  run_effective_slice_transition(accepted_current_reopen, slice_2_active_after_accepted, true, "effective Slice transition ordinal 1 to ordinal 2 ACTIVE positive")
  slice_2_accepted = later_rebaseline_slice_fixture(slice_2_active_after_accepted, 2, "ACCEPTED")
  run_effective_slice_order(slice_2_accepted, true, "effective Slice order ordinal 2 ACCEPTED to pending ordinal 3 positive")
  run_effective_slice_transition(slice_2_active_after_accepted, slice_2_accepted, true, "effective Slice transition ordinal 2 ACTIVE to ACCEPTED positive")
  slice_3_active = later_rebaseline_slice_fixture(slice_2_accepted, 3, "ACTIVE")
  run_effective_slice_order(slice_3_active, true, "effective Slice order ordinal 3 ACTIVE positive")
  run_effective_slice_transition(slice_2_accepted, slice_3_active, true, "effective Slice transition ordinal 2 to ordinal 3 ACTIVE positive")
  slice_3_accepted = later_rebaseline_slice_fixture(slice_3_active, 3, "ACCEPTED")
  run_effective_slice_order(slice_3_accepted, true, "effective Slice order ordinal 3 ACCEPTED to pending ordinal 4 positive")
  run_effective_slice_transition(slice_3_active, slice_3_accepted, true, "effective Slice transition ordinal 3 ACTIVE to ACCEPTED positive")
  slice_4_active = later_rebaseline_slice_fixture(slice_3_accepted, 4, "ACTIVE")
  run_effective_slice_order(slice_4_active, true, "effective Slice order ordinal 4 ACTIVE positive")
  run_effective_slice_transition(slice_3_accepted, slice_4_active, true, "effective Slice transition ordinal 3 to ordinal 4 ACTIVE positive")

  run_effective_slice_transition(accepted_current_reopen, slice_2_accepted, false, "effective Slice cannot become ACCEPTED without ACTIVE transition negative", expected_failure: "activated without ACTIVE")

  slice_1_to_3_gap = later_rebaseline_slice_fixture(accepted_current_reopen, 3, "ACTIVE")
  run_effective_slice_order(slice_1_to_3_gap, false, "effective Slice order 1 to 3 gap negative", expected_failure: "gap or out-of-order")
  slice_1_to_4_gap = later_rebaseline_slice_fixture(accepted_current_reopen, 4, "ACTIVE")
  run_effective_slice_order(slice_1_to_4_gap, false, "effective Slice order 1 to 4 gap negative", expected_failure: "gap or out-of-order")
  slice_2_to_4_gap = later_rebaseline_slice_fixture(slice_2_accepted, 4, "ACTIVE")
  run_effective_slice_order(slice_2_to_4_gap, false, "effective Slice order 2 to 4 gap negative", expected_failure: "gap or out-of-order")

  accepted_slice_1_projection_drift = Marshal.load(Marshal.dump(slice_2_active_after_accepted))
  accepted_slice_1_projection_drift["mandatory_exit_capability_recovery"]["capability_status"][rebaseline.fetch("slices").first.fetch("capability_projection").first] = "REBASELINED_PENDING_EXECUTION"
  run_current_reopen_transition(
    root,
    accepted_current_reopen,
    accepted_slice_1_projection_drift,
    false,
    "current reopen ACCEPTED steady Slice 1 capability regression negative",
    expected_failure: "lifecycle projection drift"
  )

  active_current_reopen_with_one_correction = Marshal.load(Marshal.dump(active_current_reopen))
  active_current_reopen_with_one_correction.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt")["bounded_contract_corrections_used"] = 1
  run_current_reopen_transition(root, pending_current_reopen, active_current_reopen_with_one_correction, true, "current reopen ACTIVE with one bounded Contract correction positive")

  active_current_reopen_with_excessive_correction = Marshal.load(Marshal.dump(active_current_reopen))
  active_current_reopen_with_excessive_correction.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt")["bounded_contract_corrections_used"] = 2
  run_current_reopen_transition(root, pending_current_reopen, active_current_reopen_with_excessive_correction, false, "current reopen excessive bounded Contract correction negative", expected_failure: "attempt binding drift")

  correction_unit_root = File.join(evidence_base, "rebaseline-contract-correction-unit")
  FileUtils.mkdir_p(correction_unit_root)
  original_contract_path = File.join(correction_unit_root, "ORIGINAL_CONTRACT_CANDIDATE.yaml")
  original_contract = {
    "task_id" => "AIOS-P1-943_CURRENT_REOPEN_LIFECYCLE_TEST",
    "objective" => "frozen bounded correction unit",
    "clean_room_recovery" => {
      "bounded_contract_corrections_allowed" => 1,
      "bounded_contract_corrections_used" => 0,
      "original_contract_path" => nil,
      "original_contract_sha256" => nil
    }
  }
  write_yaml(original_contract_path, original_contract)
  final_contract_path = File.join(correction_unit_root, "FINAL_CONTRACT.yaml")
  final_contract = Marshal.load(Marshal.dump(original_contract))
  final_contract["clean_room_recovery"]["bounded_contract_corrections_used"] = 1
  final_contract["clean_room_recovery"]["original_contract_path"] = original_contract_path
  final_contract["clean_room_recovery"]["original_contract_sha256"] = Digest::SHA256.file(original_contract_path).hexdigest
  write_yaml(final_contract_path, final_contract)
  final_contract_sha256 = Digest::SHA256.file(final_contract_path).hexdigest
  run_rebaseline_contract_correction(
    root,
    final_contract.fetch("clean_room_recovery"),
    final_contract_sha256,
    final_contract_path,
    correction_unit_root,
    true,
    "rebaseline one bounded Contract correction exact original/final binding positive"
  )
  missing_original_binding = Marshal.load(Marshal.dump(final_contract.fetch("clean_room_recovery")))
  missing_original_binding["original_contract_path"] = nil
  missing_original_binding["original_contract_sha256"] = nil
  run_rebaseline_contract_correction(
    root,
    missing_original_binding,
    final_contract_sha256,
    final_contract_path,
    correction_unit_root,
    false,
    "rebaseline corrected Contract missing original binding negative",
    expected_failure: "original binding missing"
  )
  excessive_correction_binding = Marshal.load(Marshal.dump(final_contract.fetch("clean_room_recovery")))
  excessive_correction_binding["bounded_contract_corrections_used"] = 2
  run_rebaseline_contract_correction(
    root,
    excessive_correction_binding,
    final_contract_sha256,
    final_contract_path,
    correction_unit_root,
    false,
    "rebaseline corrected Contract used greater than one negative",
    expected_failure: "correction usage invalid"
  )
  FileUtils.rm_rf(correction_unit_root)

  slice_1_budget_contract = {
    "budget" => {
      "engineering_hours" => 24,
      "calendar_days" => 5,
      "implementation_iterations" => 2,
      "candidate_limit" => 1,
      "execution_retries" => 0,
      "network_calls" => 0
    }
  }
  slice_1_budget = rebaseline.fetch("slices").find { |slice| slice["ordinal"] == 1 }
  run_rebaseline_contract_budget(slice_1_budget_contract, slice_1_budget, true, "Slice 1 frozen Contract budget positive")
  %w[engineering_hours calendar_days implementation_iterations candidate_limit].each do |field|
    excessive = Marshal.load(Marshal.dump(slice_1_budget_contract))
    excessive.fetch("budget")[field] = slice_1_budget.fetch(field) + 1
    run_rebaseline_contract_budget(
      excessive,
      slice_1_budget,
      false,
      "Slice 1 #{field} budget exceeds frozen Slice negative",
      expected_failure: "#{field} budget invalid or exceeds frozen Slice"
    )
  end
  zero_budget = Marshal.load(Marshal.dump(slice_1_budget_contract))
  zero_budget.fetch("budget")["engineering_hours"] = 0
  run_rebaseline_contract_budget(zero_budget, slice_1_budget, false, "Slice 1 non-positive budget negative", expected_failure: "engineering_hours budget invalid")
  retry_budget = Marshal.load(Marshal.dump(slice_1_budget_contract))
  retry_budget.fetch("budget")["execution_retries"] = 1
  run_rebaseline_contract_budget(retry_budget, slice_1_budget, false, "Slice 1 execution retry budget negative", expected_failure: "execution retry must be zero")
  network_budget = Marshal.load(Marshal.dump(slice_1_budget_contract))
  network_budget.fetch("budget")["network_calls"] = 1
  run_rebaseline_contract_budget(network_budget, slice_1_budget, false, "Slice 1 network call budget negative", expected_failure: "network calls must be zero")

  slice_4_budget = rebaseline.fetch("slices").find { |slice| slice["ordinal"] == 4 }
  slice_4_budget_contract = {
    "budget" => {
      "engineering_hours" => 12,
      "calendar_days" => 5,
      "implementation_iterations" => 1,
      "candidate_limit" => 1,
      "execution_retries" => 0,
      "network_calls" => 0,
      "scheduled_runs" => 48
    }
  }
  run_rebaseline_contract_budget(slice_4_budget_contract, slice_4_budget, true, "Slice 4 exact scheduled-run budget positive")
  wrong_scheduled_runs = Marshal.load(Marshal.dump(slice_4_budget_contract))
  wrong_scheduled_runs.fetch("budget")["scheduled_runs"] = 47
  run_rebaseline_contract_budget(wrong_scheduled_runs, slice_4_budget, false, "Slice 4 scheduled-run budget drift negative", expected_failure: "scheduled run budget drift")
  missing_scheduled_runs = Marshal.load(Marshal.dump(slice_4_budget_contract))
  missing_scheduled_runs.fetch("budget").delete("scheduled_runs")
  run_rebaseline_contract_budget(missing_scheduled_runs, slice_4_budget, false, "Slice 4 scheduled-run budget missing negative", expected_failure: "scheduled run budget drift")

  old_reopen_hash_activation = Marshal.load(Marshal.dump(active_current_reopen))
  old_reopen_hash_activation.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt")["project_level_reopen_decision_sha256"] = project_reopen.fetch("decision_record_sha256")
  run_current_reopen_transition(root, pending_current_reopen, old_reopen_hash_activation, false, "historical project reopen hash activation negative", expected_failure: "attempt binding drift")

  old_attempt_ordinal_activation = Marshal.load(Marshal.dump(active_current_reopen))
  old_attempt_ordinal_activation.dig("mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt")["attempt_ordinal"] = 2
  run_current_reopen_transition(root, pending_current_reopen, old_attempt_ordinal_activation, false, "historical attempt ordinal activation negative", expected_failure: "attempt binding drift")

  p1_042_reuse_activation = current_reopen_lifecycle_fixture(
    none_truth,
    "ACTIVE",
    task_id: current_project_reopen.fetch("historical_task_id")
  )
  run_current_reopen_transition(root, pending_current_reopen, p1_042_reuse_activation, false, "P1-042 Task identity reuse activation negative", expected_failure: "attempt binding drift")

  p1_042_contract_reuse_activation = current_reopen_lifecycle_fixture(
    none_truth,
    "ACTIVE",
    contract_sha256: current_project_reopen.fetch("historical_task_contract_sha256")
  )
  run_current_reopen_transition(root, pending_current_reopen, p1_042_contract_reuse_activation, false, "P1-042 Contract hash reuse activation negative", expected_failure: "attempt binding drift")

  legacy_attempt_without_current_reopen = Marshal.load(Marshal.dump(none_truth))
  legacy_attempt_without_current_reopen.fetch("mandatory_exit_capability_recovery").delete("current_project_level_reopen")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), legacy_attempt_without_current_reopen)
  run_validator(root, false, "legacy terminal Slice attempt cannot be superseded without current reopen authority negative", expected_failure: "P1 project-level reopen attempt/capability state drift")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), none_truth)

  active_task_identity_drift = current_reopen_lifecycle_fixture(none_truth, "ACCEPTED", task_id: "AIOS-P1-944_CHANGED_TASK")
  run_current_reopen_transition(root, active_current_reopen, active_task_identity_drift, false, "active current reopen Task identity drift negative", expected_failure: "attempt identity changed")

  active_contract_identity_drift = current_reopen_lifecycle_fixture(none_truth, "ACCEPTED", contract_sha256: "b" * 64)
  run_current_reopen_transition(root, active_current_reopen, active_contract_identity_drift, false, "active current reopen Contract identity drift negative", expected_failure: "attempt identity changed")

  run_current_reopen_transition(root, active_current_reopen, pending_current_reopen, false, "active current reopen rollback negative", expected_failure: "attempt was erased")
  run_current_reopen_transition(root, accepted_current_reopen, active_current_reopen, false, "terminal current reopen reactivation negative", expected_failure: "lifecycle transition invalid")

  current_reopen_identity_drift = Marshal.load(Marshal.dump(active_current_reopen))
  current_reopen_identity_drift.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")["canonical_parent_commit"] = "f" * 40
  run_current_reopen_transition(root, pending_current_reopen, current_reopen_identity_drift, false, "current reopen canonical parent mutation negative", expected_failure: "immutable identity changed")

  goal_identity_drift = Marshal.load(Marshal.dump(none_truth))
  goal_identity_drift["goal"]["observed_body_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), goal_identity_drift)
  run_validator(root, false, "current Goal identity drift mutation negative", expected_failure: "current Goal canonical identity drift")

  reopen_parent_drift = Marshal.load(Marshal.dump(none_truth))
  reopen_parent_drift.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")["canonical_parent_tree"] = "0" * 40
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), reopen_parent_drift)
  run_validator(root, false, "current reopen canonical parent binding mutation negative", expected_failure: "current P1 project-level reopen authority drift")

  p1_042_binding_drift = Marshal.load(Marshal.dump(none_truth))
  p1_042_binding_drift.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")["historical_terminal_record_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), p1_042_binding_drift)
  run_validator(root, false, "current reopen P1-042 historical binding mutation negative", expected_failure: "P1-042 exact historical custody identity drift")

  reopen_decision_drift = Marshal.load(Marshal.dump(none_truth))
  reopen_decision_drift.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")["decision_record_sha256"] = "0" * 64
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), reopen_decision_drift)
  run_validator(root, false, "current reopen decision hash mutation negative", expected_failure: "current P1 project-level reopen Founder decision hash drift")

  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), none_truth)
  p1_042_unit_truth = Marshal.load(Marshal.dump(none_truth))
  p1_042_unit_truth.fetch("task_history")["aios_p1_042"] = Marshal.load(Marshal.dump(p1_042_relocated_history))
  run_exact_validator_helper(
    :validate_p1_042_mechanical_custody!,
    [p1_042_unit_truth, evidence_base, true],
    false,
    "P1-042 identical bytes relocated inside audit root negative",
    expected_failure: "canonical custody path drift"
  )
  run_exact_validator_helper(
    :validate_p1_042_mechanical_custody!,
    [p1_042_unit_truth, evidence_base, false],
    true,
    "P1-042 relocated unit fixture mechanical bytes positive without canonical authority claim"
  )
  [
    [p1_042_contract_target, p1_042_contract_source, "Contract", "P1-042 exact Contract byte drift", "P1-042 exact Contract missing or outside audit custody"],
    [p1_042_record_target, p1_042_record_source, "terminal record", "P1-042 terminal record byte drift", "P1-042 terminal record path is not exact execution-root custody"],
    [p1_042_manifest_target, p1_042_manifest_source, "terminal manifest", "P1-042 terminal manifest byte drift", "P1-042 terminal manifest path is not exact execution-root custody"]
  ].each do |target, source, label, tamper_failure, missing_failure|
    File.binwrite(target, File.binread(source) + "tamper\n")
    run_exact_validator_helper(
      :validate_p1_042_mechanical_custody!,
      [p1_042_unit_truth, evidence_base, false],
      false,
      "P1-042 #{label} tamper negative",
      expected_failure: tamper_failure
    )
    FileUtils.cp(source, target)

    FileUtils.rm_f(target)
    run_exact_validator_helper(
      :validate_p1_042_mechanical_custody!,
      [p1_042_unit_truth, evidence_base, false],
      false,
      "P1-042 #{label} missing negative",
      expected_failure: missing_failure
    )
    File.symlink(source, target)
    run_exact_validator_helper(
      :validate_p1_042_mechanical_custody!,
      [p1_042_unit_truth, evidence_base, false],
      false,
      "P1-042 #{label} symlink negative",
      expected_failure: missing_failure
    )
    FileUtils.rm_f(target)
    FileUtils.cp(source, target)
  end
  cleanup_probe = File.join(root, "P1_042_CLEANUP_NEGATIVE_PROBE")
  File.write(cleanup_probe, "must be absent\n", mode: "w:UTF-8")
  run_exact_validator_helper(
    :validate_absent_path!,
    [cleanup_probe, "P1-042 cleanup probe"],
    false,
    "P1-042 cleanup residual file negative",
    expected_failure: "unexpectedly exists"
  )
  FileUtils.rm_f(cleanup_probe)
  File.symlink(p1_042_contract_source, cleanup_probe)
  run_exact_validator_helper(
    :validate_absent_path!,
    [cleanup_probe, "P1-042 cleanup probe"],
    false,
    "P1-042 cleanup residual symlink negative",
    expected_failure: "unexpectedly exists"
  )
  FileUtils.rm_f(cleanup_probe)
  run_validator(root, true, "P1-042 exact custody restored positive")

  founder_input_unit_root = File.join(root, "founder-input-custody")
  founder_input_outside_root = File.join(root, "founder-input-outside")
  FileUtils.mkdir_p(founder_input_unit_root)
  FileUtils.mkdir_p(founder_input_outside_root)
  founder_input_regular = File.join(founder_input_unit_root, "regular.txt")
  founder_input_outside = File.join(founder_input_outside_root, "outside.txt")
  File.write(founder_input_regular, "regular Founder input\n", mode: "w:UTF-8")
  File.write(founder_input_outside, "outside Founder input\n", mode: "w:UTF-8")
  run_exact_validator_helper(
    :read_regular_file_under_root!,
    [founder_input_regular, founder_input_unit_root, "Founder input unit"],
    true,
    "Founder input exact regular file positive"
  )
  founder_input_leaf_symlink = File.join(founder_input_unit_root, "leaf-symlink.txt")
  File.symlink(founder_input_regular, founder_input_leaf_symlink)
  run_exact_validator_helper(
    :read_regular_file_under_root!,
    [founder_input_leaf_symlink, founder_input_unit_root, "Founder input unit"],
    false,
    "Founder input leaf symlink negative",
    expected_failure: "missing, symlinked, or outside fixed custody"
  )
  founder_input_parent_symlink = File.join(founder_input_unit_root, "linked-parent")
  File.symlink(founder_input_outside_root, founder_input_parent_symlink)
  run_exact_validator_helper(
    :read_regular_file_under_root!,
    [File.join(founder_input_parent_symlink, "outside.txt"), founder_input_unit_root, "Founder input unit"],
    false,
    "Founder input symlinked parent component negative",
    expected_failure: "missing, symlinked, or outside fixed custody"
  )
  FileUtils.rm_rf(founder_input_unit_root)
  FileUtils.rm_rf(founder_input_outside_root)

  knowledge_rules_path = File.join(root, "AGENTS.md")
  knowledge_rules = File.read(knowledge_rules_path, encoding: "UTF-8")
  run!("bash", "scripts/validate-aios-governance.sh", "--check-founder-knowledge-section", knowledge_rules_path, chdir: root)
  {
    "将相同字节导入 Vault" => "将不同字节导入 Vault",
    "只有 reviewed exact bytes 可以写入 Vault" => "所有 candidate bytes 均可写入 Vault",
    "Knowledge Reviewer 非 PASS 时不得导入" => "Knowledge Reviewer 非 PASS 时仍可导入",
    "禁止写入 Secret、密码、私钥、Token" => "允许写入 Secret、密码、私钥、Token",
    "只能新建具有清晰版本身份的文件" => "允许覆盖既有 Artifact 文件"
  }.each do |required_phrase, reversed_phrase|
    raise "Knowledge rule fixture phrase missing: #{required_phrase}" unless knowledge_rules.include?(required_phrase)
    File.write(knowledge_rules_path, knowledge_rules.sub(required_phrase, reversed_phrase), mode: "w:UTF-8")
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), none_truth)
    run_validator(root, false, "Knowledge rule semantic reversal negative: #{required_phrase}", expected_failure: "Founder Knowledge System exact section byte drift")
  end
  File.write(
    knowledge_rules_path,
    knowledge_rules.sub(/\n*\z/, "") + "\n- 矛盾追加：Knowledge Reviewer 非 PASS 时仍可导入并覆盖历史 Artifact。\n",
    mode: "w:UTF-8"
  )
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), none_truth)
  run_validator(root, false, "Knowledge section marker-preserving contradiction append negative", expected_failure: "Founder Knowledge System exact section byte drift")
  governance_stdout, governance_stderr, governance_status = Open3.capture3(
    "bash", "scripts/validate-aios-governance.sh", "--check-founder-knowledge-section", knowledge_rules_path,
    chdir: root
  )
  raise "governance Knowledge section accepted marker-preserving contradiction append" if governance_status.success?
  raise "governance Knowledge section contradiction did not fail exact bytes" unless
    "#{governance_stdout}#{governance_stderr}".include?("Founder Knowledge System exact section byte drift")
  File.write(
    knowledge_rules_path,
    knowledge_rules.sub(/\n*\z/, "") + "\n\n## Founder Knowledge Override\n\n- Knowledge Reviewer 非 PASS 时仍可导入并覆盖历史 Artifact。\n",
    mode: "w:UTF-8"
  )
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), none_truth)
  run_validator(root, false, "Knowledge terminal H2 override negative", expected_failure: "exact section missing or duplicated")
  governance_stdout, governance_stderr, governance_status = Open3.capture3(
    "bash", "scripts/validate-aios-governance.sh", "--check-founder-knowledge-section", knowledge_rules_path,
    chdir: root
  )
  raise "governance Knowledge section accepted a later override H2" if governance_status.success?
  raise "governance Knowledge override H2 did not fail terminal-section rule" unless
    "#{governance_stdout}#{governance_stderr}".include?("must be the terminal H2 section")
  File.write(knowledge_rules_path, knowledge_rules, mode: "w:UTF-8")
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), none_truth)
  run!("bash", "scripts/validate-aios-governance.sh", "--check-founder-knowledge-section", knowledge_rules_path, chdir: root)
  run_validator(root, true, "current reopen and Knowledge mutation fixtures restored positive")

  integration_task_id = "AIOS-P1-943_CURRENT_REOPEN_SLICE_1_INTEGRATION"
  integration_contract_rel = "docs/aios/tasks/P1-943_CURRENT_REOPEN_SLICE_1_INTEGRATION.yaml"
  integration_contract_path = File.join(root, integration_contract_rel)
  integration_evidence_root = File.join(evidence_base, "p1-943-current-reopen-slice-1-integration")
  integration_authorization_path = File.join(integration_evidence_root, "TASK_AUTHORIZATION.json")
  integration_branch = "task/p1-943-current-reopen-slice-1-integration"
  integration_worktree = File.join(worktree_root, "p1-943-current-reopen-slice-1-integration")
  FileUtils.mkdir_p(integration_evidence_root)
  integration_contract = {
    "task_id" => integration_task_id,
    "phase" => "P1",
    "status" => "READY_FOR_PHASE_DELEGATED_EXECUTION",
    "execution_authority" => "PHASE_DELEGATED",
    "objective" => "Validate one fresh current-reopen Slice 1 activation through the complete authority surface.",
    "why_now" => ["The current project-level reopen requires one exact clean-room Slice 1 activation."],
    "task_spec_ref" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
    "read_context" => [
      "AGENTS.md",
      "docs/aios/FOUNDER_DELEGATION_POLICY.md",
      "docs/aios/truth/project_state.yaml"
    ],
    "dependencies" => [],
    "mandatory_exit_capability" => "PARAMETERIZED_EVALUATION_HARNESS",
    "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(rebaseline.fetch("slices").first.fetch("capability_projection"))),
    "project_level_rebaseline_slice_ordinal" => 1,
    "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
    "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256"),
    "delivery_architecture_model" => delivery.fetch("model"),
    "project_level_reopen_decision_sha256" => current_project_reopen.fetch("decision_record_sha256"),
    "post_activation_quality_plan" => {
      "freeze_stage" => "AFTER_TASK_ACTIVATION_BEFORE_WORKER_IMPLEMENTATION",
      "owner" => "Quality and Evaluation Agent",
      "worker_start_precondition" => "QUALITY_EXECUTABLE_PLAN_AND_OWNERSHIP_MANIFEST_FROZEN",
      "independent_evaluator_verdict_path_separate_from_worker_runtime" => true,
      "worker_may_write_evaluator_verdict" => false,
      "contract_version_chain_allowed" => false
    },
    "clean_room_recovery" => {
      "historical_execution_lineage_reused" => false,
      "attempt_ordinal" => 1,
      "bounded_contract_corrections_allowed" => 1,
      "bounded_contract_corrections_used" => 0,
      "original_contract_path" => nil,
      "original_contract_sha256" => nil
    },
    "task_kind" => "EVALUATION_FOUNDATION_ENGINEERING",
    "capabilities" => ["EVALUATOR_AND_ORACLE", "EVALUATION_METRICS", "OBSERVABLE_TRACE_VALIDATION"],
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
      "worker" => "Fresh Slice 1 Worker",
      "independent_reviewers" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
    },
    "allowed_paths" => {
      "worker" => ["evaluation-harness/harness/**", "evaluation-harness/validators/**"],
      "quality" => ["evaluation-harness/fixtures/**"],
      "external_evidence" => ["#{integration_evidence_root}/**"]
    },
    "forbidden_actions" => ["network", "Provider", "Secret", "remote", "production", "public effect", "historical failed Contract reuse"],
    "budget" => {
      "engineering_hours" => 1,
      "calendar_days" => 1,
      "implementation_iterations" => 1,
      "candidate_limit" => 1,
      "execution_retries" => 0,
      "network_calls" => 0
    },
    "acceptance_criteria" => ["the complete main validator accepts the exact active authority combination"],
    "failure_criteria" => ["any authority, order, scope, resource or identity binding fails"],
    "stop_conditions" => ["the fixture requires historical failed Contract bytes or external effects"],
    "evidence" => { "required" => ["complete validator result"] },
    "rollback" => { "method" => "remove the synthetic Task worktree and rebuild the next isolated fixture lineage" },
    "claim_boundary" => rebaseline.fetch("slices").first.fetch("claim_boundary"),
    "delegated_authority" => {
      "phase_local" => true,
      "task_gate_owner" => "MASTER_CEO_AGENT",
      "founder_gate" => "RESERVED_DECISIONS_ONLY",
      "founder_reserved_decisions" => [],
      "external_effects" => {
        "network" => false,
        "provider" => false,
        "secret" => false,
        "remote" => false,
        "production" => false,
        "public" => false
      }
    }
  }
  write_yaml(integration_contract_path, integration_contract)
  integration_contract_sha = Digest::SHA256.file(integration_contract_path).hexdigest
  run!("git", "add", integration_contract_rel, chdir: root)
  run!("git", "commit", "-m", "freeze current reopen Slice 1 integration Contract", chdir: root)
  integration_parent_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  integration_parent_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  integration_authorization_id = Digest::SHA256.hexdigest("#{integration_task_id}:#{integration_contract_sha}:#{integration_parent_commit}")
  integration_authorization = {
    "record_type" => "aios_phase_delegated_task_authorization",
    "status" => "ACTIVE",
    "authority" => "MASTER_CEO_AGENT",
    "delegation_model" => "PHASE_LEVEL_FOUNDER_DELEGATION",
    "authorization_id" => integration_authorization_id,
    "task_id" => integration_task_id,
    "phase" => "P1",
    "task_contract_sha256" => integration_contract_sha,
    "goal_canonical_sha256" => none_truth.dig("goal", "observed_body_sha256"),
    "parent_commit" => integration_parent_commit,
    "parent_tree" => integration_parent_tree,
    "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(rebaseline.fetch("slices").first.fetch("capability_projection"))),
    "project_level_rebaseline_slice_ordinal" => 1,
    "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
    "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256"),
    "project_level_reopen_decision_sha256" => current_project_reopen.fetch("decision_record_sha256"),
    "external_effects" => integration_contract.dig("delegated_authority", "external_effects"),
    "founder_reserved_decisions" => [],
    "founder_reserved_decision_required" => false
  }
  write_json(integration_authorization_path, integration_authorization)
  integration_active_truth = current_reopen_lifecycle_fixture(
    none_truth,
    "ACTIVE",
    task_id: integration_task_id,
    contract_sha256: integration_contract_sha
  )
  integration_active_truth["phase_execution_claim"]["current_task_claim"] = integration_task_id
  integration_active_truth["active_work"] = {
    "current_task" => integration_task_id,
    "current_task_status" => "AUTHORIZED_ACTIVE",
    "current_task_contract" => integration_contract_rel,
    "current_task_contract_sha256" => integration_contract_sha,
    "current_execution_authorization" => integration_authorization_path,
    "current_execution_authorization_sha256" => Digest::SHA256.file(integration_authorization_path).hexdigest,
    "execution_nonce" => nil,
    "execution_nonce_status" => "NOT_REQUIRED_PHASE_DELEGATION",
    "authorization_id" => integration_authorization_id,
    "activation_parent_commit" => integration_parent_commit,
    "activation_parent_tree" => integration_parent_tree,
    "task_resource_state" => "CREATED",
    "task_branch" => integration_branch,
    "task_worktree" => integration_worktree,
    "execution_evidence_root" => integration_evidence_root,
    "offsite_target" => nil,
    "founder_reserved_authorization" => nil,
    "founder_reserved_authorization_sha256" => nil,
    "founder_decision_required" => false,
    "escalation_reason" => nil,
    "user_action_required" => nil,
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_EXECUTE_CURRENT_TASK"
  }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), integration_active_truth)
  File.write(File.join(root, "docs/PROJECT_CODE_MAP.md"), "\nSynthetic Slice 1 activation projection.\n", mode: "a:UTF-8")
  run!("git", "add", "docs/PROJECT_CODE_MAP.md", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "-m", "activate current reopen Slice 1 integration fixture", chdir: root)
  run!("git", "branch", integration_branch, "HEAD", chdir: root)
  run!("git", "worktree", "add", integration_worktree, integration_branch, chdir: root)
  run_validator(integration_worktree, true, "linked current worktree approved and current routing separation nonregression positive")
  integration_active_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  active_safety_truth = Marshal.load(Marshal.dump(integration_active_truth))
  active_safety_truth.fetch("mandatory_exit_capability_recovery")["post_revision_final_route_terminal"] = { "status" => "P1_TERMINAL_STOPPED" }
  active_safety_truth_path = File.join(root, "SLICE_1_ACTIVE_SAFETY_TRUTH.yaml")
  write_yaml(active_safety_truth_path, active_safety_truth)
  run!(
    "bash", "scripts/check-p1-safety-boundary.sh", "--check-rebaseline-safety-envelope",
    active_safety_truth_path, chdir: root
  )
  FileUtils.rm_f(active_safety_truth_path)
  run!("git", "worktree", "remove", integration_worktree, chdir: root)
  run!("git", "branch", "-d", integration_branch, chdir: root)

  run!("git", "reset", "--hard", integration_parent_commit, chdir: root)
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), integration_active_truth)
  run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "-m", "synthetic activation missing code map", chdir: root)
  run!("git", "branch", integration_branch, "HEAD", chdir: root)
  run!("git", "worktree", "add", integration_worktree, integration_branch, chdir: root)
  run_validator(integration_worktree, false, "rebaseline activation missing Code Map negative", expected_failure: "active Task activation path population drift")
  run!("git", "worktree", "remove", integration_worktree, chdir: root)
  run!("git", "branch", "-d", integration_branch, chdir: root)

  run!("git", "reset", "--hard", integration_parent_commit, chdir: root)
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), integration_active_truth)
  File.write(File.join(root, "docs/PROJECT_CODE_MAP.md"), "\nSynthetic Slice 1 activation projection.\n", mode: "a:UTF-8")
  File.write(File.join(root, "EXTRA_ACTIVATION_PATH"), "forbidden third path\n", mode: "w:UTF-8")
  run!("git", "add", "docs/PROJECT_CODE_MAP.md", "docs/aios/truth/project_state.yaml", "EXTRA_ACTIVATION_PATH", chdir: root)
  run!("git", "commit", "-m", "synthetic activation with third path", chdir: root)
  run!("git", "branch", integration_branch, "HEAD", chdir: root)
  run!("git", "worktree", "add", integration_worktree, integration_branch, chdir: root)
  run_validator(integration_worktree, false, "rebaseline activation third path negative", expected_failure: "active Task activation path population drift")
  run!("git", "worktree", "remove", integration_worktree, chdir: root)
  run!("git", "branch", "-d", integration_branch, chdir: root)

  run!("git", "reset", "--hard", integration_parent_commit, chdir: root)
  File.write(File.join(root, "docs/PROJECT_CODE_MAP.md"), "\nSynthetic Slice 1 activation projection.\n", mode: "a:UTF-8")
  run!("git", "add", "docs/PROJECT_CODE_MAP.md", chdir: root)
  run!("git", "commit", "-m", "synthetic split activation code map", chdir: root)
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), integration_active_truth)
  run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "-m", "synthetic split activation truth", chdir: root)
  run!("git", "branch", integration_branch, "HEAD", chdir: root)
  run!("git", "worktree", "add", integration_worktree, integration_branch, chdir: root)
  run_validator(integration_worktree, false, "rebaseline activation two commits negative", expected_failure: "active Task activation must be one governance commit")
  run!("git", "worktree", "remove", integration_worktree, chdir: root)
  run!("git", "branch", "-d", integration_branch, chdir: root)

  run!("git", "reset", "--hard", integration_active_commit, chdir: root)
  sibling_terminal_root = File.join(evidence_base, "synthetic-current-reopen-wrong-sibling-root")
  sibling_terminal_truth = current_reopen_terminal_fixture(
    integration_active_truth,
    "ARCHITECTURE_BLOCKED",
    task_id: integration_task_id,
    contract_sha256: integration_contract_sha,
    terminal_evidence_root: sibling_terminal_root
  )
  run_current_reopen_transition(
    root,
    integration_active_truth,
    sibling_terminal_truth,
    false,
    "current reopen terminal Evidence cannot move to a sibling audit root negative",
    expected_failure: "terminal Evidence root drift"
  )

  %w[ARCHITECTURE_BLOCKED SCOPE_COMPLIANCE_BLOCKED].each do |terminal_stage|
    terminal_truth = current_reopen_terminal_fixture(
      integration_active_truth,
      terminal_stage,
      task_id: integration_task_id,
      contract_sha256: integration_contract_sha,
      terminal_evidence_root: integration_evidence_root
    )
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), terminal_truth)
    run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
    run!("git", "commit", "-m", "synthetic current reopen #{terminal_stage}", chdir: root)
    if terminal_stage == "ARCHITECTURE_BLOCKED"
      hidden_state = terminal_truth.dig("mandatory_exit_capability_recovery", "capability_status", "HIDDEN_SET_PROTOCOL")
      raise "current Slice terminal fixture did not preserve Hidden pending" unless hidden_state == "REBASELINED_PENDING_EXECUTION"
      terminal_reopen = terminal_truth.dig("mandatory_exit_capability_recovery", "current_project_level_reopen")
      raise "historical approved reopen route identity drift in terminal fixture" unless
        terminal_reopen["approved_reopen_decision_route"] == {
          "next_slice_ordinal" => 1,
          "next_slice_action" => "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_1"
        }
      raise "current terminal routing is not fail-closed in terminal fixture" unless
        terminal_reopen["next_slice_ordinal"].nil? &&
        terminal_reopen["next_slice_action"] == "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED"
      run_validator(root, true, "historical approved ordinal 1 with current terminal routing null and Hidden pending positive")

      residual_task_branch = "task/residual-none-terminal"
      run!("git", "branch", residual_task_branch, "HEAD", chdir: root)
      run_validator(
        root,
        false,
        "NONE residual task branch production-validator negative",
        expected_failure: "Task branches remain while no Task is active"
      )
      run!("git", "branch", "-D", residual_task_branch, chdir: root)

      residual_external_branch = "feature/residual-none-external-linked"
      residual_external_worktree = File.join(root, "external-residual-linked-worktree")
      run!("git", "worktree", "add", "-b", residual_external_branch, residual_external_worktree, "HEAD", chdir: root)
      run_validator(
        root,
        false,
        "NONE residual external-path worktree production-validator negative",
        expected_failure: "unexpected worktree population outside canonical and current runtime"
      )
      run!("git", "worktree", "remove", residual_external_worktree, chdir: root)
      run!("git", "branch", "-D", residual_external_branch, chdir: root)

      terminal_history_key = terminal_truth.fetch("task_history").keys.find do |key|
        terminal_truth.dig("task_history", key, "task_id") == integration_task_id &&
          terminal_truth.dig("task_history", key, "terminal_classification") == "ARCHITECTURE_BLOCKED"
      end
      raise "current architecture terminal history fixture missing" unless terminal_history_key
      run_terminal_truth_negative = lambda do |variant, label, expected_failure|
        run!("git", "reset", "--hard", integration_active_commit, chdir: root)
        write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), variant)
        run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
        run!("git", "commit", "-m", "synthetic #{label}", chdir: root)
        run_validator(root, false, label, expected_failure: expected_failure)
      end

      stale_current_terminal_ordinal = Marshal.load(Marshal.dump(terminal_truth))
      stale_current_terminal_ordinal.dig(
        "mandatory_exit_capability_recovery", "current_project_level_reopen"
      )["next_slice_ordinal"] = 1
      run_terminal_truth_negative.call(
        stale_current_terminal_ordinal,
        "current terminal routing stale ordinal 1 negative",
        "current routing drift"
      )

      null_approved_reopen_ordinal = Marshal.load(Marshal.dump(terminal_truth))
      null_approved_reopen_ordinal.dig(
        "mandatory_exit_capability_recovery", "current_project_level_reopen", "approved_reopen_decision_route"
      )["next_slice_ordinal"] = nil
      run_terminal_truth_negative.call(
        null_approved_reopen_ordinal,
        "historical approved reopen ordinal null negative",
        "approved decision route binding drift"
      )

      drifted_approved_reopen_ordinal = Marshal.load(Marshal.dump(terminal_truth))
      drifted_approved_route = drifted_approved_reopen_ordinal.dig(
        "mandatory_exit_capability_recovery", "current_project_level_reopen", "approved_reopen_decision_route"
      )
      drifted_approved_route["next_slice_ordinal"] = 2
      drifted_approved_route["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_2"
      run_terminal_truth_negative.call(
        drifted_approved_reopen_ordinal,
        "historical approved reopen ordinal drift negative",
        "current P1 project-level reopen cannot supersede the historical attempt"
      )

      missing_current_terminal_action = Marshal.load(Marshal.dump(terminal_truth))
      missing_current_terminal_action.dig(
        "mandatory_exit_capability_recovery", "current_project_level_reopen"
      ).delete("next_slice_action")
      run_terminal_truth_negative.call(
        missing_current_terminal_action,
        "current terminal next Slice action missing negative",
        "current P1 project-level reopen current routing drift"
      )

      wrong_current_terminal_action = Marshal.load(Marshal.dump(terminal_truth))
      wrong_current_terminal_action.dig(
        "mandatory_exit_capability_recovery", "current_project_level_reopen"
      )["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_1"
      run_terminal_truth_negative.call(
        wrong_current_terminal_action,
        "current terminal next Slice action wrong negative",
        "current routing drift"
      )

      terminal_without_evidence = Marshal.load(Marshal.dump(terminal_truth))
      terminal_without_evidence.fetch("task_history").delete(terminal_history_key)
      run_terminal_truth_negative.call(
        terminal_without_evidence,
        "current terminal routing without terminal Evidence negative",
        "current architecture terminal history population drift"
      )

      false_hidden_blocked = Marshal.load(Marshal.dump(terminal_truth))
      false_hidden_blocked.dig("mandatory_exit_capability_recovery", "capability_status")["HIDDEN_SET_PROTOCOL"] = "ARCHITECTURE_BLOCKED"
      run_terminal_truth_negative.call(
        false_hidden_blocked,
        "current Slice false Hidden architecture-blocked without Evidence negative",
        "marked an unrelated capability architecture-blocked"
      )

      attempt_projection_mismatch = Marshal.load(Marshal.dump(terminal_truth))
      attempt_projection_mismatch.dig(
        "mandatory_exit_capability_recovery", "current_project_level_reopen", "current_slice_attempt",
        "integrated_mandatory_exit_capabilities"
      ).pop
      run_terminal_truth_negative.call(
        attempt_projection_mismatch,
        "current Slice attempt projection mismatch negative",
        "current P1 project-level reopen attempt binding drift"
      )

      terminal_manifest_hash_drift = Marshal.load(Marshal.dump(terminal_truth))
      terminal_manifest_hash_drift.dig("task_history", terminal_history_key, "terminal_evidence")["evidence_manifest_sha256"] = "0" * 64
      run_terminal_truth_negative.call(
        terminal_manifest_hash_drift,
        "current Slice terminal manifest hash drift negative",
        "current architecture terminal manifest hash drift"
      )

      terminal_stop_hash_drift = Marshal.load(Marshal.dump(terminal_truth))
      terminal_stop_hash_drift.dig("task_history", terminal_history_key, "terminal_evidence")["terminal_stop_record_sha256"] = "0" * 64
      run_terminal_truth_negative.call(
        terminal_stop_hash_drift,
        "current Slice terminal stop record hash drift negative",
        "current architecture terminal stop record hash drift"
      )

      candidate_reuse = Marshal.load(Marshal.dump(terminal_truth))
      candidate_reuse.dig("task_history", terminal_history_key)["asset_reuse_allowed"] = true
      run_terminal_truth_negative.call(
        candidate_reuse,
        "current Slice rejected candidate reuse flag negative",
        "current architecture terminal history binding drift"
      )
    else
      run_validator(root, true, "preserved legacy plus current reopen #{terminal_stage} production-validator positive")
    end
    run!("git", "reset", "--hard", integration_active_commit, chdir: root)
  end
  {
    "ARCHITECTURE_BLOCKED" => "TERMINAL_STOPPED_AFTER_SCOPE_COMPLIANCE_FAILURE",
    "SCOPE_COMPLIANCE_BLOCKED" => "TERMINAL_STOPPED_AFTER_REAL_ARCHITECTURE_ROOT"
  }.each do |terminal_stage, wrong_terminal_status|
    wrong_terminal_truth = current_reopen_terminal_fixture(
      integration_active_truth,
      terminal_stage,
      task_id: integration_task_id,
      contract_sha256: integration_contract_sha,
      terminal_evidence_root: integration_evidence_root,
      terminal_status_override: wrong_terminal_status
    )
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), wrong_terminal_truth)
    run!("git", "add", "docs/aios/truth/project_state.yaml", chdir: root)
    run!("git", "commit", "-m", "synthetic current reopen wrong terminal status #{terminal_stage}", chdir: root)
    run_validator(root, false, "current reopen #{terminal_stage} wrong self-consistent terminal status negative", expected_failure: terminal_stage == "ARCHITECTURE_BLOCKED" ? "current architecture terminal history schema drift" : "current reopened Slice scope-compliance terminal lacks Evidence binding")
    run!("git", "reset", "--hard", integration_active_commit, chdir: root)
  end

  gate_base_candidate_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  gate_base_candidate_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  slice_4 = rebaseline.fetch("slices").find { |slice| slice["ordinal"] == 4 }
  slice_4_task_id = "AIOS-P1-974_SYNTHETIC_GATE_SLICE_4"
  slice_4_contract_rel = "docs/aios/tasks/P1-974_SYNTHETIC_GATE_SLICE_4.yaml"
  slice_4_contract_path = File.join(root, slice_4_contract_rel)
  slice_4_active_evidence_root = File.join(evidence_base, "p1-974-synthetic-gate-slice-4-active")
  slice_4_authorization_path = File.join(slice_4_active_evidence_root, "TASK_AUTHORIZATION.json")
  slice_4_branch = "task/p1-974-synthetic-gate-slice-4"
  slice_4_worktree = File.join(worktree_root, "p1-974-synthetic-gate-slice-4")
  FileUtils.mkdir_p(slice_4_active_evidence_root)
  slice_4_contract = {
    "task_id" => slice_4_task_id,
    "phase" => "P1",
    "status" => "READY_FOR_PHASE_DELEGATED_EXECUTION",
    "execution_authority" => "PHASE_DELEGATED",
    "objective" => "Run the complete frozen Slice 4 baseline experiment and produce the bounded P1 report.",
    "why_now" => ["Slices 1 through 3 are accepted and the exact fourth Slice is next in the frozen order."],
    "task_spec_ref" => "docs/aios/EVALUATION_PROTOCOL.md",
    "read_context" => [
      "AGENTS.md",
      "docs/aios/FOUNDER_DELEGATION_POLICY.md",
      "docs/aios/truth/project_state.yaml"
    ],
    "dependencies" => [],
    "mandatory_exit_capability" => slice_4.fetch("capability_projection").first,
    "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(slice_4.fetch("capability_projection"))),
    "project_level_rebaseline_slice_ordinal" => 4,
    "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
    "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256"),
    "delivery_architecture_model" => delivery.fetch("model"),
    "clean_room_recovery" => {
      "historical_execution_lineage_reused" => false,
      "attempt_ordinal" => 1,
      "bounded_contract_corrections_allowed" => 1,
      "bounded_contract_corrections_used" => 0,
      "original_contract_path" => nil,
      "original_contract_sha256" => nil
    },
    "task_kind" => "EVALUATION_FOUNDATION_ENGINEERING",
    "capabilities" => ["EVALUATOR_AND_ORACLE", "EVALUATION_METRICS", "OBSERVABLE_TRACE_VALIDATION"],
    "capability_claim" => false,
    "risk_level" => "medium",
    "lineage" => { "kind" => "INDEPENDENT_PHASE_INCREMENT", "retries" => [], "remediates" => [], "supersedes" => [] },
    "roles" => {
      "accountable_owner" => "Engineering Manager Agent",
      "worker" => "Fresh Slice 4 Worker",
      "independent_reviewers" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
    },
    "allowed_paths" => {
      "worker" => ["evaluation-harness/harness/synthetic-slice-4/**"],
      "quality" => ["evaluation-harness/fixtures/synthetic-slice-4/**"],
      "external_evidence" => ["#{slice_4_active_evidence_root}/**"]
    },
    "forbidden_actions" => ["network", "Provider", "Secret", "remote", "production", "public effect", "historical failed Contract reuse"],
    "budget" => {
      "engineering_hours" => 12,
      "calendar_days" => 5,
      "implementation_iterations" => 1,
      "candidate_limit" => 1,
      "execution_retries" => 0,
      "network_calls" => 0,
      "scheduled_runs" => 48
    },
    "acceptance_criteria" => ["the exact 48-run bounded Slice 4 evidence package reaches independent Task Gate PASS"],
    "failure_criteria" => ["any frozen run count, budget, authority, evidence, or claim boundary drifts"],
    "stop_conditions" => ["the Slice requires external effects or exceeds its frozen envelope"],
    "evidence" => { "required" => ["complete production authority validator result", "Task Gate evidence package"] },
    "rollback" => { "method" => "remove the unmerged synthetic Slice 4 worktree" },
    "claim_boundary" => slice_4.fetch("claim_boundary"),
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
  write_yaml(slice_4_contract_path, slice_4_contract)
  slice_4_contract_sha = Digest::SHA256.file(slice_4_contract_path).hexdigest
  preliminary_gate_truth = install_rebaseline_gate_evidence!(
    none_truth,
    evidence_base,
    gate_base_candidate_commit,
    gate_base_candidate_tree,
    { 4 => slice_4_contract_sha }
  )
  slice_4_pending_truth = slice_4_pending_before_activation_fixture(preliminary_gate_truth)
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), slice_4_pending_truth)
  run!("git", "add", slice_4_contract_rel, "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "-m", "freeze valid Slice 4 Contract and pending authority", chdir: root)
  slice_4_parent_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  slice_4_parent_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  slice_4_authorization_id = Digest::SHA256.hexdigest("#{slice_4_task_id}:#{slice_4_contract_sha}:#{slice_4_parent_commit}")
  slice_4_authorization = {
    "record_type" => "aios_phase_delegated_task_authorization",
    "status" => "ACTIVE",
    "authority" => "MASTER_CEO_AGENT",
    "delegation_model" => "PHASE_LEVEL_FOUNDER_DELEGATION",
    "authorization_id" => slice_4_authorization_id,
    "task_id" => slice_4_task_id,
    "phase" => "P1",
    "task_contract_sha256" => slice_4_contract_sha,
    "goal_canonical_sha256" => slice_4_pending_truth.dig("goal", "observed_body_sha256"),
    "parent_commit" => slice_4_parent_commit,
    "parent_tree" => slice_4_parent_tree,
    "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(slice_4.fetch("capability_projection"))),
    "project_level_rebaseline_slice_ordinal" => 4,
    "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
    "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256"),
    "external_effects" => slice_4_contract.dig("delegated_authority", "external_effects"),
    "founder_reserved_decisions" => [],
    "founder_reserved_decision_required" => false
  }
  write_json(slice_4_authorization_path, slice_4_authorization)
  slice_4_active_truth = Marshal.load(Marshal.dump(slice_4_pending_truth))
  slice_4_active_recovery = slice_4_active_truth.fetch("mandatory_exit_capability_recovery")
  slice_4_active_rebaseline = slice_4_active_recovery.fetch("project_level_rebaseline")
  slice_4_attempt = {
    "status" => "ACTIVE",
    "task_id" => slice_4_task_id,
    "attempt_ordinal" => 1,
    "contract_sha256" => slice_4_contract_sha,
    "bounded_contract_corrections_used" => 0,
    "integrated_mandatory_exit_capabilities" => Marshal.load(Marshal.dump(slice_4.fetch("capability_projection"))),
    "project_level_rebaseline_slice_ordinal" => 4,
    "project_level_rebaseline_decision_sha256" => rebaseline.fetch("decision_record_sha256"),
    "delivery_architecture_simplification_decision_sha256" => delivery.fetch("decision_record_sha256")
  }
  slice_4_active_rebaseline.fetch("slice_attempts")["4"] = slice_4_attempt
  slice_4.fetch("capability_projection").each do |capability|
    slice_4_active_recovery.fetch("capability_status")[capability] = "IN_PROGRESS"
  end
  slice_4_active_rebaseline["status"] = "REBASELINED_SLICE_ACTIVE"
  slice_4_active_rebaseline["p1_status"] = "REBASELINED_SLICE_ACTIVE"
  slice_4_active_rebaseline["current_task"] = slice_4_task_id
  slice_4_active_rebaseline["next_slice_ordinal"] = 4
  slice_4_active_rebaseline["next_slice_action"] = "MASTER_AUTONOMOUSLY_PREPARE_AND_EXECUTE_REBASELINED_SLICE_4"
  slice_4_active_truth.fetch("project")["phase_execution_status"] = "TASK_ACTIVE"
  slice_4_active_truth.fetch("project")["p1_execution_status"] = "TASK_ACTIVE"
  slice_4_active_truth.fetch("goal")["current_task_authority"] = slice_4_task_id
  slice_4_active_truth.fetch("phase_execution_claim")["current_task_claim"] = slice_4_task_id
  slice_4_active_truth.fetch("claim_boundary")["p1_status"] = "REBASELINED_SLICE_ACTIVE"
  slice_4_active_truth["active_work"] = {
    "current_task" => slice_4_task_id,
    "current_task_status" => "AUTHORIZED_ACTIVE",
    "current_task_contract" => slice_4_contract_rel,
    "current_task_contract_sha256" => slice_4_contract_sha,
    "current_execution_authorization" => slice_4_authorization_path,
    "current_execution_authorization_sha256" => Digest::SHA256.file(slice_4_authorization_path).hexdigest,
    "execution_nonce" => nil,
    "execution_nonce_status" => "NOT_REQUIRED_PHASE_DELEGATION",
    "authorization_id" => slice_4_authorization_id,
    "activation_parent_commit" => slice_4_parent_commit,
    "activation_parent_tree" => slice_4_parent_tree,
    "task_resource_state" => "CREATED",
    "task_branch" => slice_4_branch,
    "task_worktree" => slice_4_worktree,
    "execution_evidence_root" => slice_4_active_evidence_root,
    "offsite_target" => nil,
    "founder_reserved_authorization" => nil,
    "founder_reserved_authorization_sha256" => nil,
    "founder_decision_required" => false,
    "escalation_reason" => nil,
    "user_action_required" => nil,
    "next_eligible_action" => "MASTER_AUTONOMOUSLY_EXECUTE_CURRENT_TASK"
  }
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), slice_4_active_truth)
  File.write(File.join(root, "docs/PROJECT_CODE_MAP.md"), "\nSynthetic Slice 4 activation projection.\n", mode: "a:UTF-8")
  run!("git", "add", "docs/PROJECT_CODE_MAP.md", "docs/aios/truth/project_state.yaml", chdir: root)
  run!("git", "commit", "-m", "activate complete valid Slice 4 predecessor", chdir: root)
  run!("git", "branch", slice_4_branch, "HEAD", chdir: root)
  run!("git", "worktree", "add", slice_4_worktree, slice_4_branch, chdir: root)
  run_validator(slice_4_worktree, true, "complete valid Slice 4 linked current worktree ACTIVE production-validator predecessor positive")
  slice_4_active_safety_path = File.join(root, "SLICE_4_ACTIVE_SAFETY_TRUTH.yaml")
  slice_4_active_safety_truth = Marshal.load(Marshal.dump(slice_4_active_truth))
  slice_4_active_safety_truth.fetch("mandatory_exit_capability_recovery")["post_revision_final_route_terminal"] = { "status" => "P1_TERMINAL_STOPPED" }
  write_yaml(slice_4_active_safety_path, slice_4_active_safety_truth)
  run!("bash", "scripts/check-p1-safety-boundary.sh", "--check-rebaseline-safety-envelope", slice_4_active_safety_path, chdir: root)
  FileUtils.rm_f(slice_4_active_safety_path)
  run!("git", "worktree", "remove", slice_4_worktree, chdir: root)
  run!("git", "branch", "-d", slice_4_branch, chdir: root)

  slice_4_candidate_commit = run!("git", "rev-parse", "HEAD", chdir: root)
  slice_4_candidate_tree = run!("git", "rev-parse", "HEAD^{tree}", chdir: root)
  gate_truth = install_rebaseline_gate_evidence!(
    none_truth,
    evidence_base,
    gate_base_candidate_commit,
    gate_base_candidate_tree,
    { 4 => slice_4_contract_sha },
    { 4 => [slice_4_candidate_commit, slice_4_candidate_tree] }
  )
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), gate_truth)
  run_validator(root, true, "complete valid Slice 4 ACTIVE to ACCEPTED Founder Phase Gate production-validator positive")
  gate_safety_truth = Marshal.load(Marshal.dump(gate_truth))
  gate_safety_truth.fetch("mandatory_exit_capability_recovery")["post_revision_final_route_terminal"] = { "status" => "P1_TERMINAL_STOPPED" }
  gate_safety_truth_path = File.join(root, "SLICE_4_GATE_SAFETY_TRUTH.yaml")
  write_yaml(gate_safety_truth_path, gate_safety_truth)
  run!(
    "bash", "scripts/check-p1-safety-boundary.sh", "--check-rebaseline-safety-envelope",
    gate_safety_truth_path, chdir: root
  )
  FileUtils.rm_f(gate_safety_truth_path)

  gate_founder_projection_drift = Marshal.load(Marshal.dump(gate_truth))
  gate_founder_projection_drift.fetch("active_work")["founder_decision_required"] = false
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), gate_founder_projection_drift)
  run_validator(root, false, "Founder Phase Gate founder-decision field negative", expected_failure: "Founder Phase Gate escalation projection drift")

  gate_user_action_drift = Marshal.load(Marshal.dump(gate_truth))
  gate_user_action_drift.fetch("active_work")["user_action_required"] = "NONE"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), gate_user_action_drift)
  run_validator(root, false, "Founder Phase Gate user-action field negative", expected_failure: "Founder Phase Gate escalation projection drift")

  gate_phase_claim_drift = Marshal.load(Marshal.dump(gate_truth))
  gate_phase_claim_drift.fetch("phase_execution_claim")["current_task_claim"] = "NONE_P1_REBASELINED_PENDING_EXECUTION"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), gate_phase_claim_drift)
  run_validator(root, false, "Founder Phase Gate phase claim negative", expected_failure: "NONE state task claim drift")

  gate_incomplete_attempt = Marshal.load(Marshal.dump(gate_truth))
  gate_incomplete_attempt.dig("mandatory_exit_capability_recovery", "project_level_rebaseline", "slice_attempts", "4")["status"] = "ACTIVE"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), gate_incomplete_attempt)
  run_validator(root, false, "Founder Phase Gate incomplete Slice acceptance negative", expected_failure: "completed Slice prefix drift")

  gate_wrong_escalation = Marshal.load(Marshal.dump(gate_truth))
  gate_wrong_escalation.fetch("active_work")["escalation_reason"] = "ROUTINE_TASK_APPROVAL"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), gate_wrong_escalation)
  run_validator(root, false, "Founder Phase Gate escalation reason negative", expected_failure: "Founder Phase Gate escalation projection drift")

  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), gate_truth)
  run_validator(root, true, "Founder Phase Gate negative fixtures restored positive")

  # The remaining vectors exercise legacy generic Task authority behavior. Rebuild a
  # separate synthetic lineage without the current-reopen control node so those
  # generic vectors cannot accidentally act as Slice 1 activation fixtures.
  truth = Marshal.load(Marshal.dump(none_truth))
  truth.fetch("mandatory_exit_capability_recovery").delete("current_project_level_reopen")
  truth.dig("mandatory_exit_capability_recovery", "project_level_reopen")["slice_1_reopen_attempt"] = nil
  truth.fetch("task_history").delete("aios_p1_042")
  rebaseline = truth.dig("mandatory_exit_capability_recovery", "project_level_rebaseline")
  delivery = truth.dig("mandatory_exit_capability_recovery", "delivery_architecture_simplification")
  project_reopen = truth.dig("mandatory_exit_capability_recovery", "project_level_reopen")
  rebaseline["status"] = "FOUNDER_APPROVED_ACTIVE"
  rebaseline["p1_status"] = "REBASELINED_PENDING_EXECUTION"
  rebaseline["current_task"] = "NONE"
  rebaseline["next_slice_ordinal"] = 1
  rebaseline["next_slice_action"] = "MASTER_AUTONOMOUSLY_IMPLEMENT_P1_EXIT_CAPABILITIES_IN_FROZEN_PRIORITY_ORDER"
  truth.fetch("mandatory_exit_capability_recovery").fetch("capability_status").keys.each do |capability|
    truth["mandatory_exit_capability_recovery"]["capability_status"][capability] = "MISSING"
  end
  truth["project"]["phase_execution_status"] = "NO_CURRENT_TASK"
  truth["project"]["p1_execution_status"] = "NO_CURRENT_TASK"
  truth["active_work"]["user_action_required"] = nil
  truth["active_work"]["next_eligible_action"] = "MASTER_AUTONOMOUSLY_IMPLEMENT_P1_EXIT_CAPABILITIES_IN_FROZEN_PRIORITY_ORDER"
  truth["phase_execution_claim"]["current_task_claim"] = "NO_CURRENT_TASK"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), truth)
  FileUtils.rm_rf(File.join(root, ".git"))
  run!("git", "init", chdir: root)
  run!("git", "config", "user.name", "SourceLens Legacy Authority Test", chdir: root)
  run!("git", "config", "user.email", "legacy-authority@example.invalid", chdir: root)
  run!("git", "add", ".", chdir: root)
  run!("git", "commit", "-m", "legacy generic authority base", chdir: root)
  run!("git", "branch", "-M", "main", chdir: root)
  import_commit_and_tree_metadata!(root, rebaseline.fetch("canonical_parent_commit"))
  none_truth = Marshal.load(Marshal.dump(truth))
  run_validator(root, true, "legacy generic NONE positive")

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
  write_yaml(File.join(task_worktree, "docs/aios/truth/project_state.yaml"), created_truth)
  run_validator(task_worktree, true, "linked current worktree active CREATED positive")
  review_truth = Marshal.load(Marshal.dump(created_truth))
  review_truth["active_work"]["current_task_status"] = "REVIEW"
  review_truth["active_work"]["task_resource_state"] = "REVIEW"
  write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), review_truth)
  write_yaml(File.join(task_worktree, "docs/aios/truth/project_state.yaml"), review_truth)
  run_validator(task_worktree, true, "linked current worktree active REVIEW positive")
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
    run_validator(root, false, "P1-039 historical route identity immutable mutation negative", expected_failure: "post-revision final route identity drift")

    removed_terminal = Marshal.load(Marshal.dump(truth))
    removed_terminal["mandatory_exit_capability_recovery"]["final_clean_room_contract_review_terminal"] = nil
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), removed_terminal)
    run_validator(root, false, "final clean-room terminal removal negative", expected_failure: "final clean-room contract-review terminal binding missing")

    terminal_status_drift = Marshal.load(Marshal.dump(truth))
    terminal_status_drift["mandatory_exit_capability_recovery"]["final_clean_room_contract_review_terminal"]["status"] = "ACTIVE"
    write_yaml(File.join(root, "docs/aios/truth/project_state.yaml"), terminal_status_drift)
    run_validator(root, false, "P1-038 historical terminal fact immutable mutation negative", expected_failure: "final clean-room contract-review terminal route binding drift")

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

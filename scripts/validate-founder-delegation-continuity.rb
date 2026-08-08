#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "find"
require "json"
require "open3"
require "pathname"
require "psych"
require "yaml"

class FounderDelegationContinuityError < StandardError; end
class FounderDelegationDuplicateJsonKeyError < StandardError; end

class FounderDelegationClosedJsonHash < Hash
  def []=(key, value)
    raise FounderDelegationDuplicateJsonKeyError, key if key?(key)
    super
  end
end

module FounderDelegationContinuity
  module_function

  POLICY_PATH = "docs/aios/FOUNDER_DELEGATION_POLICY.md"
  POLICY_VERSION = "1.8"
  CONTINUATION_ROUTE_SCHEMA = "phase-delegated-continuation-hold/v1"
  RESERVED_ROUTE_SCHEMA = "founder-reserved-decision-hold/v1"
  DELEGATED_TASK_ROUTE_SCHEMA = "phase-delegated-independent-task/v1"
  DELEGATION_AMENDMENT_SCHEMA = "founder-phase-delegation-amendment/v1"
  DELEGATION_AMENDMENT_ID = "FOUNDER_PHASE_DELEGATION_CONTINUITY_AMENDMENT_2026_08_08"
  CONTINUE_ACTION = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
  CONTINUE_DISPOSITION = "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
  FOUNDER_DISPOSITION = "FOUNDER_DECISION_REQUIRED"
  FALSE_EXTERNAL_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze
  RESERVED_TRIGGERS = %w[
    PHASE_ENTRY_OR_EXIT
    MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
    MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
    NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT
    IRREVERSIBLE_ASSET_REMOVAL
    MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT
    CRITICAL_RESIDUAL_RISK_ACCEPTANCE
  ].freeze
  RESERVED_EVENT_KINDS = {
    "PHASE_ENTRY_OR_EXIT" => "PHASE_EXIT_GATE_ELIGIBLE",
    "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" => "FOUNDER_RESERVED_STRATEGY_CHANGE_REQUESTED",
    "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE" =>
      "PHASE_ENVELOPE_EXPANSION_REQUIRED",
    "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT" =>
      "EXTERNAL_EFFECT_PERMISSION_REQUIRED",
    "IRREVERSIBLE_ASSET_REMOVAL" => "IRREVERSIBLE_ASSET_ACTION_REQUIRED",
    "MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT" =>
      "MATERIAL_LEGAL_PRIVACY_COMMERCIAL_COMMITMENT_REQUIRED",
    "CRITICAL_RESIDUAL_RISK_ACCEPTANCE" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE_REQUIRED"
  }.freeze
  ORDINARY_TERMINAL_EVENTS = %w[
    TASK_TERMINAL_IMPLEMENTATION_NON_PASS
    TASK_TERMINAL_FINAL_REVIEW_NON_PASS
    TASK_TERMINAL_REPAIR_BUDGET_EXHAUSTED
    TASK_TERMINAL_TASK_BUDGET_EXHAUSTED
    TASK_TERMINAL_CANONICAL_VERIFY_NON_PASS
  ].freeze
  FOUNDER_RESERVED_DECISIONS = %w[
    mission_icp_year_one_or_phase_route_change
    phase_entry_or_exit
    material_scope_budget_or_permission_expansion_beyond_phase_envelope
    network_provider_secret_remote_production_or_public_effect
    irreversible_asset_removal
    material_legal_privacy_commercial_commitment
    critical_residual_risk_acceptance
  ].freeze
  AGENT_DELEGATED_DECISIONS = %w[
    select_reject_sequence_and_freeze_phase_local_tasks
    assign_roles_workers_reviewers_and_disjoint_write_ownership
    authorize_and_execute_local_task_branch_worktree_and_commands
    perform_in_scope_implementation_tests_repairs_evidence_replay_and_rollback
    accept_return_or_terminally_stop_tasks_after_independent_review
    integrate_task_to_local_canonical_main_after_task_gate
    choose_the_next_independent_phase_local_task_after_task_completion_or_stop
    continue_phase_without_founder_reapproval_after_ordinary_task_terminal
  ].freeze
  ESCALATION_CONDITIONS = %w[
    founder_reserved_decision_required
    phase_boundary_or_strategy_conflict
    high_risk_external_effect_required
    irreversible_action_required
    critical_risk_requires_acceptance
  ].freeze
  PHASE_DELEGATION_ANTI_LOOP = {
    "routine_founder_task_approval_required" => false,
    "per_file_or_command_approval_required" => false,
    "route_or_task_may_downgrade_phase_delegation" => false,
    "reviewer_non_pass_may_trigger_founder_gate" => false,
    "phase_gate_requires_exit_gate_eligibility" => true,
    "phase_execution_envelope_survives_route_terminal" => true,
    "ordinary_repairs_stay_in_same_task" => true,
    "successor_replacement_correction_chain_allowed" => false,
    "task_id_hardcoding_in_current_authority_validator_allowed" => false,
    "historical_execution_lineage_reuse_allowed" => false,
    "mandatory_exit_capability_permanent_ban_from_historical_stop" => false,
    "peripheral_work_before_exit_capabilities_allowed" => false
  }.freeze

  def fail!(message)
    raise FounderDelegationContinuityError, message
  end

  def assert(condition, message)
    fail!(message) unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} must be an array")
    value
  end

  def integer(value, label)
    assert(value.is_a?(Integer), "#{label} must be an integer")
    value
  end

  def exact_keys(value, keys, label)
    record = mapping(value, label)
    assert(record.keys.sort == keys.sort, "#{label} keys are not closed")
    record
  end

  def reject_duplicate_keys!(text)
    tree = Psych.parse_stream(text)
    walk = nil
    walk = lambda do |node, location|
      case node
      when Psych::Nodes::Mapping
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          assert(key_node.is_a?(Psych::Nodes::Scalar), "non-scalar YAML key at #{location}")
          key = key_node.value
          assert(!seen.key?(key), "duplicate YAML key at #{location}: #{key}")
          seen[key] = true
          walk.call(value_node, "#{location}.#{key}")
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index { |child, index| walk.call(child, "#{location}[#{index}]") }
      else
        children = node.respond_to?(:children) ? node.children : nil
        children&.each { |child| walk.call(child, location) }
      end
    end
    walk.call(tree, "Truth")
  rescue Psych::SyntaxError => e
    fail!("Truth YAML is invalid: #{e.message}")
  end

  def parse_truth(path)
    pathname = Pathname.new(path)
    assert(pathname.file? && !pathname.symlink?, "Truth must be a non-symlink regular file")
    bytes = pathname.binread
    text = bytes.dup.force_encoding("UTF-8")
    assert(text.valid_encoding?, "Truth encoding is invalid")
    reject_duplicate_keys!(text)
    truth = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
    mapping(truth, "Truth")
  end

  def git(root, *arguments)
    stdout, stderr, status = Open3.capture3("git", *arguments, chdir: root.to_s)
    assert(status.success?, "Git command failed: git #{arguments.join(' ')}: #{stderr.strip}")
    stdout
  end

  def parse_yaml_bytes(bytes, label)
    text = bytes.dup.force_encoding("UTF-8")
    assert(text.valid_encoding?, "#{label} encoding is invalid")
    reject_duplicate_keys!(text)
    value = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
    mapping(value, label)
  rescue Psych::SyntaxError => e
    fail!("#{label} YAML is invalid: #{e.message}")
  end

  def route_by_id(truth, route_id)
    candidates = truth.each_value.select do |value|
      value.is_a?(Hash) && value["route_id"] == route_id
    end
    assert(candidates.length == 1, "source Route anchor is missing or ambiguous")
    candidates.first
  end

  def first_truth_anchor!(root, search_literal, label)
    commits = git(
      root,
      "log",
      "--reverse",
      "--format=%H",
      "-S#{search_literal}",
      "--",
      "docs/aios/truth/project_state.yaml"
    ).lines.map(&:strip).reject(&:empty?)
    assert(!commits.empty?, "#{label} has no immutable Git anchor")
    commits.each do |commit|
      bytes, stderr, status = Open3.capture3(
        "git", "show", "#{commit}:docs/aios/truth/project_state.yaml", chdir: root.to_s
      )
      next unless status.success?
      truth = parse_yaml_bytes(bytes, "#{label} anchor Truth")
      return [commit, truth] if yield(truth)
    end
    fail!("#{label} immutable Git anchor could not be resolved")
  end

  def repo_identity_bytes(root, identity, label)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    relative = Pathname.new(record["path"].to_s)
    assert(!relative.absolute?, "#{label} path must be repository-relative")
    clean = relative.cleanpath
    assert(clean.to_s == relative.to_s && clean.to_s != "." && !clean.to_s.start_with?("../"),
           "#{label} path is unsafe")
    path = root.join(clean)
    assert(path.file? && !path.symlink?, "#{label} must be a non-symlink regular file")
    assert(path.realpath.to_s.start_with?(root.realpath.to_s + File::SEPARATOR),
           "#{label} escapes the repository")
    bytes = path.binread
    assert(bytes.bytesize == record["byte_length"], "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == record["sha256"], "#{label} SHA-256 mismatch")
    bytes
  end

  def repo_identity_bytes_at_commit(root, commit, identity, label)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    relative = Pathname.new(record["path"].to_s)
    assert(!relative.absolute?, "#{label} path must be repository-relative")
    clean = relative.cleanpath
    assert(clean.to_s == relative.to_s && clean.to_s != "." && !clean.to_s.start_with?("../"),
           "#{label} path is unsafe")
    assert(commit.to_s.match?(/\A[0-9a-f]{40}\z/), "#{label} anchor commit is invalid")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{commit}:#{clean}", chdir: root.to_s
    )
    assert(status.success?, "#{label} is absent from its active anchor: #{stderr.strip}")
    assert(bytes.bytesize == record["byte_length"], "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == record["sha256"], "#{label} SHA-256 mismatch")
    bytes
  end

  def recursively_sorted(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, recursively_sorted(value.fetch(key))] }
    when Array
      value.map { |item| recursively_sorted(item) }
    else
      value
    end
  end

  def closed_regular_file_inventory(root_path, label)
    root = Pathname.new(root_path.to_s)
    assert(root.absolute?, "#{label} root must be absolute")
    before_root = root.lstat
    assert(before_root.directory? && !before_root.symlink?,
           "#{label} root must be a non-symlink directory")
    assert(root.realpath == root.cleanpath, "#{label} root resolves through a symlink")
    entries = []
    Find.find(root.to_s) do |path_string|
      next if path_string == root.to_s

      path = Pathname.new(path_string)
      stat = path.lstat
      if stat.directory?
        next
      end
      assert(stat.file? && !stat.symlink?, "#{label} contains a non-regular object")
      assert(stat.nlink == 1, "#{label} contains a hardlinked file")
      relative = path.relative_path_from(root).to_s
      utf8_relative = relative.dup.force_encoding("UTF-8")
      assert(utf8_relative.valid_encoding?, "#{label} contains a non-UTF-8 path")
      assert(path.realpath.to_s.start_with?(root.to_s + File::SEPARATOR),
             "#{label} file escapes its root")

      flags = File::RDONLY
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      bytes = nil
      File.open(path.to_s, flags) do |file|
        opened = file.stat
        assert([opened.dev, opened.ino, opened.nlink, opened.size, opened.mtime.to_f] ==
               [stat.dev, stat.ino, stat.nlink, stat.size, stat.mtime.to_f],
               "#{label} file identity changed while opening")
        bytes = file.read
        after = file.stat
        assert([after.dev, after.ino, after.nlink, after.size, after.mtime.to_f] ==
               [opened.dev, opened.ino, opened.nlink, opened.size, opened.mtime.to_f],
               "#{label} file changed while reading")
      end
      final = path.lstat
      assert([final.dev, final.ino, final.nlink, final.size, final.mtime.to_f] ==
             [stat.dev, stat.ino, stat.nlink, stat.size, stat.mtime.to_f],
             "#{label} file changed during inventory")
      entries << {
        "path" => utf8_relative,
        "type" => "REGULAR_FILE",
        "byte_length" => bytes.bytesize,
        "sha256" => Digest::SHA256.hexdigest(bytes)
      }
    end
    after_root = root.lstat
    assert([after_root.dev, after_root.ino] == [before_root.dev, before_root.ino],
           "#{label} root identity changed during inventory")
    entries.sort_by { |entry| entry.fetch("path").b }
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail!("#{label} is unavailable (#{e.class})")
  end

  def validate_closed_formal_inventory!(forensic, label)
    first = closed_regular_file_inventory(forensic["evidence_root"], label)
    second = closed_regular_file_inventory(forensic["evidence_root"], label)
    assert(first == second, "#{label} changed between closed inventory passes")
    canonical = JSON.pretty_generate(recursively_sorted(first)) + "\n"
    assert(first.length == forensic["file_count"], "#{label} file count mismatch")
    assert(first.sum { |entry| entry.fetch("byte_length") } == forensic["total_bytes"],
           "#{label} total bytes mismatch")
    assert(Digest::SHA256.hexdigest(canonical) == forensic["canonical_inventory_sha256"],
           "#{label} canonical inventory SHA-256 mismatch")
  end

  def validate_identity(identity, label)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    path = Pathname.new(record["path"].to_s)
    assert(path.absolute?, "#{label} path must be absolute")
    stat = path.lstat
    assert(stat.file? && !stat.symlink?, "#{label} must be a non-symlink regular file")
    assert(stat.nlink == 1, "#{label} must not be hardlinked")
    clean = path.cleanpath
    assert(path.realpath == clean, "#{label} path resolves through a symlink")
    bytes = path.binread
    assert(bytes.bytesize == record["byte_length"], "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == record["sha256"], "#{label} SHA-256 mismatch")
    bytes
  end

  def parse_bound_json(identity, label)
    bytes = validate_identity(identity, label)
    value = JSON.parse(
      bytes,
      object_class: FounderDelegationClosedJsonHash,
      array_class: Array,
      create_additions: false
    )
    mapping(value, label)
  rescue JSON::ParserError => e
    fail!("#{label} JSON is invalid: #{e.message}")
  rescue FounderDelegationDuplicateJsonKeyError => e
    fail!("#{label} contains duplicate JSON key: #{e.message}")
  end

  def parse_json_bytes(bytes, label)
    value = JSON.parse(
      bytes,
      object_class: FounderDelegationClosedJsonHash,
      array_class: Array,
      create_additions: false
    )
    mapping(value, label)
  rescue JSON::ParserError => e
    fail!("#{label} JSON is invalid: #{e.message}")
  rescue FounderDelegationDuplicateJsonKeyError => e
    fail!("#{label} contains duplicate JSON key: #{e.message}")
  end

  def evidence_bytes(root_path, relative_path, label)
    root = Pathname.new(root_path.to_s)
    assert(root.absolute?, "#{label} root must be absolute")
    assert(root.lstat.directory? && !root.symlink?, "#{label} root must be a non-symlink directory")
    assert(root.realpath == root.cleanpath, "#{label} root resolves through a symlink")
    relative = Pathname.new(relative_path.to_s)
    assert(!relative.absolute? && relative.cleanpath.to_s == relative.to_s &&
           relative.to_s != "." && !relative.to_s.start_with?("../"),
           "#{label} path is unsafe")
    path = root.join(relative)
    stat = path.lstat
    assert(stat.file? && !stat.symlink?, "#{label} must be a non-symlink regular file")
    assert(stat.nlink == 1, "#{label} must not be hardlinked")
    assert(path.realpath.to_s.start_with?(root.realpath.to_s + File::SEPARATOR),
           "#{label} escapes its Evidence root")
    bytes = path.binread
    final = path.lstat
    assert([final.dev, final.ino, final.nlink, final.size, final.mtime.to_f] ==
           [stat.dev, stat.ino, stat.nlink, stat.size, stat.mtime.to_f],
           "#{label} changed while reading")
    bytes
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail!("#{label} is unavailable (#{e.class})")
  end

  def evidence_json(root_path, relative_path, label)
    parse_json_bytes(evidence_bytes(root_path, relative_path, label), label)
  end

  def validate_candidate_identity!(root, candidate, authority, label)
    record = exact_keys(
      candidate,
      %w[commit tree parent_commit tracked_binary_diff_sha256 integrated],
      "#{label} candidate"
    )
    %w[commit tree parent_commit].each do |key|
      assert(record[key].to_s.match?(/\A[0-9a-f]{40}\z/),
             "#{label} candidate #{key} is invalid")
    end
    assert(record["tracked_binary_diff_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/),
           "#{label} candidate diff identity is invalid")
    assert(record["integrated"] == false, "#{label} rejected candidate may not be integrated")
    commit_type = git(root, "cat-file", "-t", record["commit"]).strip
    assert(commit_type == "commit", "#{label} candidate commit object is invalid")
    assert(git(root, "rev-parse", "#{record['commit']}^{tree}").strip == record["tree"],
           "#{label} candidate tree drift")
    assert(git(root, "rev-parse", "#{record['commit']}^").strip == record["parent_commit"],
           "#{label} candidate parent drift")
    assert(record["parent_commit"] == authority.dig("activation_parent", "commit"),
           "#{label} candidate parent drifts from delegated authority")
    diff = git(root, "diff", "--binary", "--full-index", record["parent_commit"], record["commit"])
    assert(Digest::SHA256.hexdigest(diff) == record["tracked_binary_diff_sha256"],
           "#{label} candidate binary diff drift")
    record
  end

  def validate_formal_run_transaction!(formal_root, candidate_result, observer, task_id, mode)
    run_id = "#{mode}-#{task_id}"
    run_prefix = "runs/#{task_id}/#{mode}"
    observation = evidence_json(
      formal_root,
      "#{run_prefix}/quality-observation.json",
      "delegated terminal formal run #{run_id} observation"
    )
    exact_keys(
      observation,
      %w[
        effects exit_status input_state_sha256 mode observed_processes observer_samples
        process_sample_count raw_manifest raw_stable_projection run_id sandbox
        scanner_sandbox_binding schema_version selector_argv selector_cwd selector_env signal
        static_worker_audit task_id wall_ms worker_argv
      ],
      "delegated terminal formal run #{run_id} observation"
    )
    assert(observation["schema_version"] == "p2-057-quality-run-observation/v1" &&
           observation["task_id"] == task_id && observation["mode"] == mode &&
           observation["run_id"] == run_id && observation["exit_status"] == 0 &&
           observation["signal"].nil?,
           "delegated terminal formal run #{run_id} lifecycle drift")
    effects = exact_keys(
      observation["effects"],
      %w[
        accepted_change_content_opened diff_or_history_commands network_connect_attempts
        production_effects provider_requests public_effects remote_writes secret_read_attempts
        validation_oracle_opened_by_selector
      ],
      "delegated terminal formal run #{run_id} effects"
    )
    assert(effects == {
      "accepted_change_content_opened" => false,
      "diff_or_history_commands" => 0,
      "network_connect_attempts" => 0,
      "production_effects" => 0,
      "provider_requests" => 0,
      "public_effects" => 0,
      "remote_writes" => 0,
      "secret_read_attempts" => 0,
      "validation_oracle_opened_by_selector" => false
    }, "delegated terminal formal run #{run_id} effects are not independently zero")
    assert(observation["process_sample_count"].is_a?(Integer) &&
           observation["process_sample_count"].positive? &&
           array(observation["observed_processes"], "delegated terminal observed processes").any? &&
           observation.dig("sandbox", "network_policy") == "DENY_NETWORK_ALL",
           "delegated terminal formal run #{run_id} observer boundary drift")

    raw_manifest_bytes = evidence_bytes(
      formal_root,
      "#{run_prefix}/raw-evidence/RAW_MANIFEST.json",
      "delegated terminal formal run #{run_id} raw manifest"
    )
    stable_bytes = evidence_bytes(
      formal_root,
      "#{run_prefix}/raw-evidence/stable-projection.json",
      "delegated terminal formal run #{run_id} stable projection"
    )
    raw_manifest_identity = exact_keys(
      observation["raw_manifest"], %w[byte_length sha256],
      "delegated terminal formal run #{run_id} raw manifest identity"
    )
    stable_identity = exact_keys(
      observation["raw_stable_projection"], %w[byte_length sha256],
      "delegated terminal formal run #{run_id} stable projection identity"
    )
    assert(raw_manifest_bytes.bytesize == raw_manifest_identity["byte_length"] &&
           Digest::SHA256.hexdigest(raw_manifest_bytes) == raw_manifest_identity["sha256"],
           "delegated terminal formal run #{run_id} raw manifest identity drift")
    assert(stable_bytes.bytesize == stable_identity["byte_length"] &&
           Digest::SHA256.hexdigest(stable_bytes) == stable_identity["sha256"],
           "delegated terminal formal run #{run_id} stable projection identity drift")
    raw_manifest = parse_json_bytes(raw_manifest_bytes, "delegated terminal formal run raw manifest")
    assert(raw_manifest["schema_version"] == "p2-057-raw-manifest/v1" &&
           raw_manifest["task_id"].to_s.match?(/\AAIOS-P2-[0-9]{3}_[A-Z0-9_]+\z/) &&
           raw_manifest["entry_count"] == array(raw_manifest["entries"], "raw manifest entries").length,
           "delegated terminal formal run #{run_id} raw manifest schema drift")

    before_input = evidence_bytes(formal_root, "#{run_prefix}/input-state.before.json",
                                  "delegated terminal formal run #{run_id} input before")
    after_input = evidence_bytes(formal_root, "#{run_prefix}/input-state.after.json",
                                 "delegated terminal formal run #{run_id} input after")
    before_repo = evidence_bytes(formal_root, "#{run_prefix}/repository-status.before.bin",
                                 "delegated terminal formal run #{run_id} repository before")
    after_repo = evidence_bytes(formal_root, "#{run_prefix}/repository-status.after.bin",
                                "delegated terminal formal run #{run_id} repository after")
    assert(before_input == after_input && before_repo == after_repo,
           "delegated terminal formal run #{run_id} mutated an admitted input or repository")

    result = array(candidate_result.fetch("#{mode}_runs"), "candidate #{mode} runs").find do |item|
      item.is_a?(Hash) && item["task_id"] == task_id && item["run_id"] == run_id
    end
    assert(result, "delegated terminal formal run #{run_id} is missing from candidate result")
    exact_keys(result, %w[metrics ranked_items run_id snapshot_commit stable_projection_sha256 task_id],
               "delegated terminal formal candidate run #{run_id}")
    observed = array(observer["run_observations"], "formal observer run observations").find do |item|
      item.is_a?(Hash) && item["task_id"] == task_id && item["run_id"] == run_id
    end
    assert(observed && observed["result_projection_sha256"] == stable_identity["sha256"] &&
           result["stable_projection_sha256"] == stable_identity["sha256"] &&
           observed["provider_requests"] == 0 && observed["secret_read_attempts"] == 0 &&
           observed["network_connect_attempts"] == 0 && observed["remote_writes"] == 0 &&
           observed["production_effects"] == 0 && observed["public_effects"] == 0 &&
           observed["diff_or_history_commands"] == 0 &&
           observed["validation_oracle_opened_by_selector"] == false &&
           observed["accepted_change_content_opened"] == false,
           "delegated terminal formal run #{run_id} observer or result binding drift")
  end

  def validate_terminal_receipt_and_formal_evidence!(root, receipt, entry, authority)
    exact_keys(
      receipt,
      %w[
        schema_version task_id route_id phase terminal_status accepted_capability_created
        capability_credit p2_accepted_capability_progress candidate public_prefreeze
        formal_execution normalized_root_cause root_cause_evidence
        failure_diagnostic_research_artifact stop_decision knowledge_sync created_at
      ],
      "delegated consumed Task outcome receipt"
    )
    assert(receipt["schema_version"] == "p2-057-terminal-receipt/v1",
           "delegated consumed Task outcome receipt schema drift")
    validate_candidate_identity!(root, receipt["candidate"], authority,
                                 "delegated consumed Task")
    formal = exact_keys(
      receipt["formal_execution"],
      %w[
        evidence_root exit_status reason_code message automatic_retries formal_runs formal_reruns
        scheduled_runs completed_runs raw_run_reconstruction target_replay quality_receipt_present
        quality_manifest_present independent_value_evaluation_present value_result
        postformal_read_only_snapshot external_effects
      ],
      "delegated consumed Task formal execution"
    )
    assert(formal["exit_status"] == 2 && formal["reason_code"] == "BASELINE_IDENTITY_MISMATCH" &&
           formal["automatic_retries"] == 0 && formal["formal_runs"] == 1 &&
           formal["formal_reruns"] == 0 && formal["scheduled_runs"] == 6 &&
           formal["completed_runs"] == 6 && formal["raw_run_reconstruction"] == "PASS" &&
           formal["target_replay"] == "PASS_BYTE_EXACT" &&
           formal["quality_receipt_present"] == false &&
           formal["quality_manifest_present"] == false &&
           formal["independent_value_evaluation_present"] == false &&
           formal["value_result"] == "UNKNOWN_EVALUATION_INVALID" &&
           formal["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "delegated consumed Task formal failure lifecycle drift")

    authority_root = Pathname.new(authority["evidence_root"].to_s)
    formal_root = Pathname.new(formal["evidence_root"].to_s)
    assert(authority_root.absolute? && authority_root.lstat.directory? && !authority_root.symlink? &&
           authority_root.realpath == authority_root.cleanpath,
           "delegated consumed Task authority Evidence root is not physical and canonical")
    assert(formal_root.absolute? && formal_root.lstat.directory? && !formal_root.symlink? &&
           formal_root.realpath == formal_root.cleanpath &&
           formal_root.to_s.start_with?(authority_root.to_s + File::SEPARATOR),
           "delegated consumed Task formal Evidence is outside its delegated authority root")
    assert(formal_root.to_s == entry.dig("formal_forensic", "evidence_root"),
           "delegated consumed Task formal Evidence root binding drift")

    candidate_bytes = evidence_bytes(formal_root, "candidate-result.json",
                                     "delegated terminal candidate result")
    candidate_result = parse_json_bytes(candidate_bytes, "delegated terminal candidate result")
    exact_keys(candidate_result,
               %w[baseline_runs configuration_id freeze_id replay_runs schema_version target_runs],
               "delegated terminal candidate result")
    assert(candidate_result["schema_version"] == "p2-repository-context-candidate-result/v2" &&
           %w[baseline target replay].all? do |mode|
             array(candidate_result["#{mode}_runs"], "candidate #{mode} runs").length == 2
           end,
           "delegated terminal candidate result run set drift")
    observer = evidence_json(formal_root, "accepted-observer-receipt.json",
                             "delegated terminal accepted observer receipt")
    exact_keys(
      observer,
      %w[
        candidate_sha256 closed_input_inventory closed_input_inventory_sha256 freeze_id
        observer_id observer_policy_sha256 run_observations schema_version
      ],
      "delegated terminal accepted observer receipt"
    )
    assert(observer["schema_version"] == "p2-repository-context-observer-receipt/v1" &&
           observer["candidate_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
           array(observer["run_observations"], "formal observer run observations").length == 6,
           "delegated terminal accepted observer binding drift")

    tasks = %w[P2CTX-VAL-001-CONTEXT-RETRIEVAL P2CTX-VAL-002-TOOL-BOUNDARY]
    tasks.product(%w[baseline target replay]).each do |task_id, mode|
      validate_formal_run_transaction!(formal_root, candidate_result, observer, task_id, mode)
    end
    tasks.each do |task_id|
      target = candidate_result["target_runs"].find { |run| run["task_id"] == task_id }
      replay = candidate_result["replay_runs"].find { |run| run["task_id"] == task_id }
      assert(target && replay && target["stable_projection_sha256"] == replay["stable_projection_sha256"],
             "delegated terminal target/replay identity drift for #{task_id}")
    end

    guardrails = evidence_json(formal_root, "public-prefreeze-guardrails.json",
                               "delegated terminal public prefreeze guardrails")
    assert(guardrails["schema_version"] == "p2-057-public-prefreeze-guardrails/v1" &&
           guardrails["status"] == "PASS" && guardrails["failed_guardrails"] == [],
           "delegated terminal public prefreeze guardrails drift")
    controls = evidence_json(formal_root, "controls/sandbox-negative-controls.json",
                             "delegated terminal sandbox negative controls")
    assert(controls["schema_version"] == "p2-057-quality-sandbox-negative-controls/v1" &&
           controls["status"] == "PASS" && controls["negative_cases"] == 3 &&
           controls["false_accepts"] == 0,
           "delegated terminal sandbox negative controls drift")
    socket = evidence_json(formal_root, "controls/socket-denial.json",
                           "delegated terminal socket denial control")
    assert(socket["schema_version"] == "p2-057-quality-socket-denial-control/v1" &&
           socket["status"] == "PASS_DENIED" && socket["exit_status"] != 0,
           "delegated terminal socket denial control drift")
    process = evidence_json(formal_root, "controls/process-isolation.json",
                            "delegated terminal process isolation control")
    assert(process["schema_version"] == "p2-057-quality-process-isolation-control/v1" &&
           process["status"] == "PASS_UNRELATED_PROCESS_COMMAND_NOT_RETAINED" &&
           process["canary_retained_in_evidence"] == false && process["sample_count"].to_i.positive?,
           "delegated terminal process isolation control drift")
    formal
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail!("delegated consumed Task formal Evidence topology is unavailable (#{e.class})")
  end

  def validate_policy!(root, truth)
    authority = mapping(truth["authority"], "authority")
    policy = exact_keys(
      authority["founder_delegation_policy"],
      %w[path version sha256 status],
      "authority.founder_delegation_policy"
    )
    assert(policy["path"] == POLICY_PATH, "Founder delegation policy path drift")
    assert(policy["version"].to_s == POLICY_VERSION, "Founder delegation policy version drift")
    assert(policy["status"] == "FOUNDER_DIRECTIVE_ACTIVE", "Founder delegation policy is not active")
    path = root.join(POLICY_PATH)
    assert(path.file? && !path.symlink?, "Founder delegation policy file missing or symlinked")
    assert(Digest::SHA256.file(path).hexdigest == policy["sha256"],
           "Founder delegation policy SHA-256 drift")
    _anchor_commit, anchor_truth = first_truth_anchor!(root, "version: \"1.8\"", "Founder delegation policy") do |candidate|
      candidate.dig("authority", "founder_delegation_policy", "version").to_s == POLICY_VERSION
    end
    anchor_policy = mapping(
      mapping(anchor_truth["authority"], "Founder delegation policy anchor authority")["founder_delegation_policy"],
      "Founder delegation policy anchor"
    )
    assert(anchor_policy.slice("path", "version", "sha256", "status") == policy,
           "Founder delegation policy identity drifts from its first canonical Git anchor")
    policy
  end

  def validate_delegation_amendment!(root, identity, phase, policy)
    amendment = parse_bound_json(identity, "Founder delegation continuity amendment")
    exact_keys(
      amendment,
      %w[
        schema_version record_type decision_id phase effective_policy delegated_authority
        constraints claim_boundary
      ],
      "Founder delegation continuity amendment"
    )
    assert(amendment["schema_version"] == DELEGATION_AMENDMENT_SCHEMA &&
           amendment["record_type"] == "founder_phase_delegation_amendment" &&
           amendment["decision_id"] == DELEGATION_AMENDMENT_ID && amendment["phase"] == phase,
           "Founder delegation continuity amendment identity drift")
    assert(exact_keys(amendment["effective_policy"], %w[path version], "delegation amendment policy") ==
           policy.slice("path", "version"),
           "delegation amendment policy binding drift")
    assert(exact_keys(
      amendment["delegated_authority"],
      %w[
        select_new_independent_task_after_ordinary_terminal
        reallocate_unused_task_specific_capacity_within_same_phase_objective
        founder_reapproval_required
      ],
      "delegation amendment authority"
    ) == {
      "select_new_independent_task_after_ordinary_terminal" => true,
      "reallocate_unused_task_specific_capacity_within_same_phase_objective" => true,
      "founder_reapproval_required" => false
    }, "delegation amendment authority drift")
    assert(exact_keys(
      amendment["constraints"],
      %w[
        numeric_phase_ceiling_expansion_allowed external_effect_expansion_allowed
        phase_change_allowed rejected_lineage_reuse_allowed successor_or_replacement_chain_allowed
        maximum_active_tasks maximum_task_branches maximum_task_worktrees maximum_active_candidates
      ],
      "delegation amendment constraints"
    ) == {
      "numeric_phase_ceiling_expansion_allowed" => false,
      "external_effect_expansion_allowed" => false,
      "phase_change_allowed" => false,
      "rejected_lineage_reuse_allowed" => false,
      "successor_or_replacement_chain_allowed" => false,
      "maximum_active_tasks" => 1,
      "maximum_task_branches" => 1,
      "maximum_task_worktrees" => 1,
      "maximum_active_candidates" => 1
    }, "delegation amendment constraints drift")
    assert(amendment["claim_boundary"].is_a?(String) && !amendment["claim_boundary"].empty?,
           "delegation amendment claim boundary missing")

    _anchor_commit, anchor_truth = first_truth_anchor!(root, identity["sha256"],
                                                       "Founder delegation continuity amendment") do |candidate|
      candidate.dig("phase_execution_envelope", "authority_basis", "delegation_amendment", "sha256") ==
        identity["sha256"]
    end
    anchored = anchor_truth.dig("phase_execution_envelope", "authority_basis", "delegation_amendment")
    assert(anchored == identity,
           "Founder delegation continuity amendment drifts from its first canonical Git anchor")
    amendment
  end

  def validate_phase_delegation!(truth, phase)
    delegation = exact_keys(
      truth["phase_delegation"],
      %w[
        status model decision_source phase_gate_owner task_selection_owner
        task_authorization_owner task_gate_owner founder_reserved_decisions
        agent_delegated_decisions escalation_conditions anti_loop claim_boundary
      ],
      "phase_delegation"
    )
    assert([
      "ACTIVE_#{phase}_PHASE_DELEGATION",
      "ACTIVE_#{phase}_PHASE_DELEGATED_CONTINUATION"
    ].include?(delegation["status"]),
           "Phase delegation status drift")
    assert(delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION",
           "Phase delegation model drift")
    assert(delegation["decision_source"].to_s.include?("V1_8_NON_DOWNGRADE_DIRECTIVE"),
           "Phase delegation decision source drift")
    assert(delegation["phase_gate_owner"] == "HUMAN_FOUNDER" &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT_WITHIN_CURRENT_PHASE_ENVELOPE" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT_AFTER_REQUIRED_INDEPENDENT_REVIEW",
           "Phase delegation ownership drift")
    assert(delegation["founder_reserved_decisions"] == FOUNDER_RESERVED_DECISIONS,
           "Founder reserved decision set drift")
    assert(delegation["agent_delegated_decisions"] == AGENT_DELEGATED_DECISIONS,
           "Agent delegated decision set drift")
    assert(delegation["escalation_conditions"] == ESCALATION_CONDITIONS,
           "Founder escalation condition set drift")
    anti_loop = exact_keys(
      delegation["anti_loop"],
      PHASE_DELEGATION_ANTI_LOOP.keys + ["maximum_same_task_bounded_contract_repairs"],
      "phase_delegation.anti_loop"
    )
    PHASE_DELEGATION_ANTI_LOOP.each do |key, expected|
      assert(anti_loop[key] == expected, "Phase delegation anti-loop control drift: #{key}")
    end
    assert(integer(anti_loop["maximum_same_task_bounded_contract_repairs"],
                   "phase_delegation maximum same-Task repairs").positive?,
           "Phase delegation same-Task repair ceiling must be positive")
    assert(delegation["claim_boundary"].is_a?(String) && !delegation["claim_boundary"].empty?,
           "Phase delegation claim boundary missing")
    delegation
  end

  def historical_route_ref!(truth, route)
    reference = route["historical_terminal_route_ref"]
    inventory_reference = route["inherited_worktree_inventory_source"]
    assert(reference.is_a?(String) &&
           reference.match?(/\Ahistorical_p(?:0|[1-9]|1[0-2])_[a-z0-9_]+_phase_route\z/),
           "historical terminal route reference is invalid")
    assert(inventory_reference == reference,
           "historical terminal route and worktree inventory references diverge")
    mapping(truth[reference], reference)
    reference
  end

  def phase_gate_state(truth, phase)
    phases = mapping(mapping(truth["strict_phase_gate_ledger"], "strict_phase_gate_ledger")["phases"],
                     "strict_phase_gate_ledger.phases")
    record = mapping(phases[phase], "strict phase record #{phase}")
    items = mapping(record["required_items"], "strict phase required items #{phase}")
    ids = array(record["required_item_ids"], "strict phase required item ids #{phase}")
    assert(ids == items.keys, "strict phase required item ordering or set drift")
    accepted = items.values.all? { |item| item.is_a?(Hash) && item["status"] == "ACCEPTED" }
    gate = mapping(record["founder_phase_gate"], "strict phase Founder gate #{phase}")
    [record, accepted, gate["status"]]
  end

  def source_route_static_projection(route)
    {
      "route_id" => route["route_id"],
      "phase" => route["phase"],
      "phase_entry_status" => route["phase_entry_status"],
      "authorization_token" => route["authorization_token"],
      "decision_packet" => route["decision_packet"],
      "original_founder_packet" => route["original_founder_packet"],
      "activation_parent" => route["activation_parent"],
      "goal_identity" => route["goal_identity"],
      "objective" => route["objective"],
      "envelope" => route["envelope"],
      "founder_reserved_profile" => route["founder_reserved_profile"],
      "founder_reserved_profiles" => route["founder_reserved_profiles"],
      "automatic_entry" => route["automatic_entry"],
      "automatic_entries" => route["automatic_entries"],
      "task_plan" => array(route["task_plan"], "source Route task plan").map do |task|
        mapping(task, "source Route Task").reject { |key, _value| key == "status" }
      end
    }
  end

  def validate_source_route_authority!(root, historical_route)
    route_id = historical_route["route_id"]
    _anchor_commit, anchor_truth = first_truth_anchor!(root, route_id, "Phase source Route") do |candidate|
      candidate.any? do |_key, value|
        value.is_a?(Hash) && value["route_id"] == route_id
      end
    end
    anchor_route = route_by_id(anchor_truth, route_id)
    assert(source_route_static_projection(historical_route) == source_route_static_projection(anchor_route),
           "historical source Route static authority drifts from its first canonical Git anchor")

    decision = parse_bound_json(
      historical_route["decision_packet"],
      "phase execution envelope source decision"
    )
    exact_keys(
      decision,
      %w[
        activation_parent authorization_token automatic_entries automatic_entry claim_boundary
        envelope external_effects goal_identity ordered_tasks phase record_type route_id
        schema_version source_founder_packet_identity
      ],
      "phase execution envelope source decision"
    )
    assert(decision["record_type"] == "founder_phase_route_decision" &&
           decision["schema_version"] == "1.1",
           "phase execution envelope requires a structured Founder route decision v1.1")
    assert(decision["phase"] == historical_route["phase"] &&
           decision["route_id"] == historical_route["route_id"] &&
           decision["authorization_token"] == historical_route["authorization_token"],
           "phase execution envelope source decision identity drift")
    assert(decision["activation_parent"] == historical_route["activation_parent"],
           "source Route activation parent drifts from structured Founder decision")
    assert(decision["automatic_entry"] == historical_route["automatic_entry"] &&
           decision["automatic_entries"] == historical_route["automatic_entries"],
           "source Route automatic-entry semantics drift from structured Founder decision")
    assert(decision["claim_boundary"] == historical_route["claim_boundary"] &&
           decision["goal_identity"] == historical_route["goal_identity"],
           "source Route claim or Goal binding drifts from structured Founder decision")
    source_identity = exact_keys(
      decision["source_founder_packet_identity"],
      %w[authorization_token path byte_length sha256],
      "phase execution envelope source Founder packet identity"
    )
    assert(source_identity["authorization_token"] == historical_route["authorization_token"],
           "source Founder packet authorization token drift")
    source_file_identity = source_identity.slice("path", "byte_length", "sha256")
    assert(source_file_identity == historical_route["original_founder_packet"],
           "source Founder packet identity drift")
    validate_identity(
      source_file_identity,
      "phase execution envelope source Founder packet"
    )

    decision_envelope = exact_keys(
      decision["envelope"],
      %w[
        max_active_candidates max_active_tasks max_calendar_days max_engineering_hours
        max_engineering_tasks max_same_task_repairs_per_task max_task_branches
        max_task_worktrees p3_entry_authorized
      ],
      "structured Founder route envelope"
    )
    route_envelope = mapping(historical_route["envelope"], "historical route envelope")
    envelope_pairs = {
      "max_active_candidates" => "max_active_candidates",
      "max_active_tasks" => "max_active_tasks",
      "max_calendar_days" => "max_calendar_days",
      "max_engineering_hours" => "max_engineering_hours",
      "max_engineering_tasks" => "max_engineering_tasks",
      "max_same_task_repairs_per_task" => "max_same_task_repairs",
      "max_task_branches" => "max_task_branches",
      "max_task_worktrees" => "max_task_worktrees",
      "p3_entry_authorized" => "p3_entry_authorized"
    }
    envelope_pairs.each do |decision_key, route_key|
      assert(decision_envelope[decision_key] == route_envelope[route_key],
             "historical route envelope drifts from structured Founder decision: #{route_key}")
    end
    assert(decision["external_effects"] == route_envelope["external_effects"],
           "historical route effects drift from structured Founder decision")

    decision_tasks = array(decision["ordered_tasks"], "structured Founder ordered Tasks").map do |task|
      record = exact_keys(
        task,
        %w[
          calendar_days engineering_hours external_effects founder_reserved_profile
          max_candidates max_implementation_iterations max_same_task_repairs task_id task_slot
        ],
        "structured Founder ordered Task"
      )
      assert(record["founder_reserved_profile"].nil?,
             "offline delegated continuation source Task may not carry a Founder profile")
      record.reject { |key, _value| key == "founder_reserved_profile" }
    end
    route_tasks = array(historical_route["task_plan"], "historical route task plan").map do |task|
      record = mapping(task, "historical route Task")
      assert(record["engineering_hours"] == record["max_engineering_hours"] &&
             record["calendar_days"] == record["max_calendar_days"],
             "historical route Task budget aliases drift")
      {
        "calendar_days" => record["calendar_days"],
        "engineering_hours" => record["engineering_hours"],
        "external_effects" => record["external_effects"],
        "max_candidates" => record["max_candidates"],
        "max_implementation_iterations" => record["max_implementation_iterations"],
        "max_same_task_repairs" => record["max_same_task_repairs"],
        "task_id" => record["task_id"],
        "task_slot" => record["task_slot"]
      }
    end
    assert(route_tasks == decision_tasks,
           "historical route Task plan drifts from structured Founder decision")
    decision
  end

  def source_capacity_task!(source_route, capacity_source_task_id)
    matches = array(source_route["task_plan"], "source Route task plan").select do |task|
      task.is_a?(Hash) && task["task_id"] == capacity_source_task_id
    end
    assert(matches.length == 1, "delegated Task capacity source is missing or ambiguous")
    source = mapping(matches.first, "delegated Task capacity source")
    assert(source["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "delegated Task capacity source exceeds the offline Phase boundary")
    source
  end

  def delegated_active_anchor!(root, task_id)
    first_truth_anchor!(root, task_id, "delegated consumed Task ACTIVE lifecycle") do |candidate|
      route = candidate["current_phase_route"]
      route.is_a?(Hash) && route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA &&
        route.dig("selected_task", "task_id") == task_id &&
        route.dig("selected_task", "status") == "ACTIVE" &&
        candidate.dig("active_work", "current_task") == task_id &&
        candidate.dig("active_work", "current_task_status") == "ACTIVE"
    end
  end

  def validate_terminal_contract_static_fields!(active_contract, terminal_contract)
    assert(active_contract["status"] == "ACTIVE" && !active_contract.key?("terminal_outcome"),
           "delegated consumed Task ACTIVE Contract lifecycle drift")
    ignored = %w[status terminal_outcome]
    assert(active_contract.reject { |key, _value| ignored.include?(key) } ==
           terminal_contract.reject { |key, _value| ignored.include?(key) },
           "delegated consumed Task terminal Contract static fields drift from first ACTIVE anchor")
  end

  def validate_delegated_terminal_ledger_entry!(root, entry, source_route, phase,
                                                 claimed_capacity_sources)
    assert(entry["status"].to_s.start_with?("TERMINAL_") &&
           entry["status"].to_s.include?("NON_PASS"),
           "delegated consumed Task must be terminal NON_PASS")
    assert(entry["capability_credit"] == 0,
           "delegated consumed Task may record only zero capability credit")

    capacity_source_id = entry["capacity_source_task_id"]
    capacity_source = source_capacity_task!(source_route, capacity_source_id)
    assert(!capacity_source["status"].to_s.start_with?("TERMINAL_") &&
           !capacity_source["status"].to_s.include?("ACCEPTED"),
           "delegated consumed Task capacity source was already consumed by its source Route")
    assert(!claimed_capacity_sources.include?(capacity_source_id),
           "delegated consumed Task capacity source is consumed more than once")
    claimed_capacity_sources << capacity_source_id

    budget = exact_keys(
      entry["budget"],
      %w[engineering_tasks engineering_hours calendar_days],
      "delegated consumed Task budget"
    )
    assert(budget == {
      "engineering_tasks" => 1,
      "engineering_hours" => capacity_source["engineering_hours"],
      "calendar_days" => capacity_source["calendar_days"]
    }, "delegated consumed Task budget does not exactly consume its source capacity slot")

    anchor_commit, anchor_truth = delegated_active_anchor!(root, entry["task_id"])
    anchor_route = mapping(anchor_truth["current_phase_route"], "delegated active anchor Route")
    anchor_task = mapping(anchor_route["selected_task"], "delegated active anchor Task")
    anchor_active = mapping(anchor_truth["active_work"], "delegated active anchor active_work")
    anchor_reservation = mapping(anchor_truth.dig("phase_execution_envelope", "reserved"),
                                 "delegated active anchor reservation")
    binding = exact_keys(
      entry["activation_binding"],
      %w[first_active_anchor_commit contract authority task_branch task_worktree evidence_root],
      "delegated consumed Task activation binding"
    )
    assert(binding["first_active_anchor_commit"] == anchor_commit,
           "delegated consumed Task first ACTIVE anchor commit drift")
    assert(anchor_route["route_id"] == entry["route_id"] &&
           anchor_task["task_id"] == entry["task_id"] &&
           anchor_task["capacity_source_task_id"] == capacity_source_id &&
           anchor_reservation["capacity_source_task_id"] == capacity_source_id,
           "delegated consumed Task ACTIVE anchor capacity or Route binding drift")
    assert(binding["contract"] == anchor_task["contract"] &&
           binding["contract"] == anchor_active["current_task_contract"],
           "delegated consumed Task ACTIVE Contract binding drift")
    assert(binding["authority"] == anchor_reservation["authority"] &&
           binding["authority"] == anchor_active["authority_record"],
           "delegated consumed Task ACTIVE authority binding drift")
    authority = parse_bound_json(
      binding["authority"],
      "delegated consumed Task ACTIVE authority"
    )
    exact_keys(
      authority,
      %w[
        schema_version record_type task_id phase route_id status authorization_id
        task_contract_sha256 execution_nonce activation_parent branch worktree evidence_root
        capacity_source_task_id budget max_same_task_repairs roles allowlisted_paths
        external_effects goal_identity phase_delegation_binding founder_reserved_authorization
        founder_reserved_profile
      ],
      "delegated consumed Task ACTIVE authority"
    )
    assert(authority["schema_version"] == "1.0" &&
           authority["record_type"] == "aios_phase_delegated_independent_task_authority" &&
           authority["task_id"] == entry["task_id"] && authority["phase"] == phase &&
           authority["route_id"] == entry["route_id"] && authority["status"] == "ACTIVE" &&
           authority["branch"] == binding["task_branch"] &&
           authority["worktree"] == binding["task_worktree"] &&
           authority["evidence_root"] == binding["evidence_root"] &&
           authority["capacity_source_task_id"] == capacity_source_id &&
           authority["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "delegated consumed Task ACTIVE authority semantic binding drift")
    assert(binding["task_branch"] == anchor_active["task_branch"] &&
           binding["task_worktree"] == anchor_active["task_worktree"] &&
           binding["evidence_root"] == anchor_active["execution_evidence_root"],
           "delegated consumed Task ACTIVE branch/worktree/Evidence binding drift")

    active_contract_bytes = repo_identity_bytes_at_commit(
      root,
      anchor_commit,
      binding["contract"],
      "delegated consumed Task ACTIVE Contract"
    )
    active_contract = parse_yaml_bytes(
      active_contract_bytes,
      "delegated consumed Task ACTIVE Contract"
    )
    contract_bytes = repo_identity_bytes(root, entry["contract"],
                                         "delegated consumed Task terminal Contract")
    contract = parse_yaml_bytes(contract_bytes, "delegated consumed Task terminal Contract")
    assert(contract["task_id"] == entry["task_id"] && contract["phase"] == phase &&
           contract["route_id"] == entry["route_id"] && contract["status"] == entry["status"],
           "delegated consumed Task terminal Contract lifecycle drift")
    validate_terminal_contract_static_fields!(active_contract, contract)
    terminal = exact_keys(
      contract["terminal_outcome"],
      %w[accepted_capability_created capability_credit outcome_receipt formal_forensic],
      "delegated consumed Task Contract terminal outcome"
    )
    assert(terminal["accepted_capability_created"] == false && terminal["capability_credit"] == 0 &&
           terminal["outcome_receipt"] == entry["outcome_receipt"] &&
           terminal["formal_forensic"] == entry["formal_forensic"],
           "delegated consumed Task Contract terminal outcome binding drift")

    receipt = parse_bound_json(entry["outcome_receipt"], "delegated consumed Task outcome receipt")
    receipt_status = receipt["terminal_status"] || receipt["outcome_status"] || receipt["status"]
    assert(receipt["task_id"] == entry["task_id"] && receipt["route_id"] == entry["route_id"] &&
           receipt["phase"] == phase && receipt_status == entry["status"],
           "delegated consumed Task outcome receipt lifecycle drift")
    assert(receipt["accepted_capability_created"] == false && receipt["capability_credit"] == 0,
           "delegated consumed Task outcome receipt may not claim capability credit")
    formal = validate_terminal_receipt_and_formal_evidence!(root, receipt, entry, authority)
    forensic = exact_keys(
      entry["formal_forensic"],
      %w[evidence_root file_count total_bytes canonical_inventory_sha256],
      "delegated consumed Task formal forensic identity"
    )
    snapshot = mapping(formal["postformal_read_only_snapshot"],
                       "delegated consumed Task formal snapshot")
    assert(forensic["evidence_root"] == formal["evidence_root"] &&
           forensic["file_count"] == snapshot["file_count"] &&
           forensic["total_bytes"] == snapshot["total_bytes"] &&
           forensic["canonical_inventory_sha256"] == snapshot["canonical_inventory_sha256"],
           "delegated consumed Task formal forensic identity drift")
    assert(forensic["file_count"].is_a?(Integer) && forensic["file_count"].positive? &&
           forensic["total_bytes"].is_a?(Integer) && forensic["total_bytes"].positive? &&
           forensic["canonical_inventory_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/),
           "delegated consumed Task formal forensic identity is invalid")
    validate_closed_formal_inventory!(forensic, "delegated consumed Task formal Evidence")
  end

  def validate_consumed_task_ledger!(root, ledger, source_route, phase, anchored_source_entries)
    entries = array(ledger, "phase execution task ledger")
    ids = entries.map { |entry| mapping(entry, "phase execution task ledger entry")["task_id"] }
    assert(ids.uniq.length == ids.length, "phase execution task ledger contains duplicate Task ids")
    source_tasks = array(source_route["task_plan"], "source Route task plan")
    source_consumed = source_tasks.select do |task|
      status = mapping(task, "source Route Task")["status"].to_s
      status.start_with?("TERMINAL_") || status.include?("ACCEPTED")
    end
    assert((source_consumed.map { |task| task["task_id"] } - ids).empty?,
           "phase execution task ledger omits a consumed source Route Task")
    source_ineligible_ids = source_tasks.reject { |task| source_consumed.include?(task) }
                                      .map { |task| task["task_id"] }
    assert((ids & source_ineligible_ids).empty?,
           "phase execution task ledger consumes an ineligible source Route Task")

    claimed_capacity_sources = []
    entries.each_with_index do |value, index|
      raw_entry = mapping(value, "phase execution task ledger[#{index}]")
      source_task = source_tasks.find { |task| task["task_id"] == raw_entry["task_id"] }
      delegated = source_task.nil?
      entry = exact_keys(
        raw_entry,
        delegated ? %w[
          task_id route_id status capacity_source_task_id budget activation_binding contract
          outcome_receipt formal_forensic capability_credit
        ] : %w[task_id route_id status budget contract outcome_receipt],
        "phase execution task ledger[#{index}]"
      )
      assert(entry["task_id"].to_s.match?(/\AAIOS-P(?:0|[1-9]|1[0-2])-[0-9]{3}_[A-Z0-9_]+\z/),
             "phase execution task ledger Task id is invalid")
      assert(entry["route_id"].is_a?(String) && !entry["route_id"].empty?,
             "phase execution task ledger Route id is invalid")
      assert(entry["status"].to_s.start_with?("TERMINAL_") ||
             entry["status"].to_s.include?("ACCEPTED"),
             "phase execution task ledger status is not consumed")
      budget = exact_keys(
        entry["budget"],
        %w[engineering_tasks engineering_hours calendar_days],
        "phase execution task ledger budget"
      )
      assert(budget["engineering_tasks"] == 1 &&
             budget["engineering_hours"].is_a?(Integer) && budget["engineering_hours"].positive? &&
             budget["calendar_days"].is_a?(Integer) && budget["calendar_days"].positive?,
             "phase execution task ledger budget is invalid")

      if delegated
        validate_delegated_terminal_ledger_entry!(
          root,
          entry,
          source_route,
          phase,
          claimed_capacity_sources
        )
        next
      end

      contract_bytes = repo_identity_bytes(root, entry["contract"], "phase execution consumed Task Contract")
      contract = parse_yaml_bytes(contract_bytes, "phase execution consumed Task Contract")
      assert(contract["task_id"] == entry["task_id"] && contract["phase"] == phase &&
             contract["route_id"] == entry["route_id"] && contract["status"] == entry["status"],
             "phase execution consumed Task Contract lifecycle drift")
      contract_budget = mapping(contract["budget"], "phase execution consumed Task Contract budget")
      assert(contract_budget["engineering_hours"] == budget["engineering_hours"] &&
             contract_budget["calendar_days"] == budget["calendar_days"],
             "phase execution consumed Task Contract budget drift")

      receipt = parse_bound_json(entry["outcome_receipt"], "phase execution Task outcome receipt")
      receipt_status = receipt["terminal_status"] || receipt["outcome_status"] || receipt["status"]
      assert(receipt["task_id"] == entry["task_id"] && receipt["route_id"] == entry["route_id"] &&
             receipt_status == entry["status"],
             "phase execution Task outcome receipt lifecycle drift")

      anchored = array(anchored_source_entries, "anchored source task ledger").find do |item|
        item.is_a?(Hash) && item["task_id"] == entry["task_id"]
      end
      assert(anchored == entry,
             "phase execution source Task ledger drifts from its first canonical anchor")
      assert(entry["route_id"] == source_route["route_id"] && source_task["status"] == entry["status"] &&
             source_task["engineering_hours"] == budget["engineering_hours"] &&
             source_task["calendar_days"] == budget["calendar_days"],
             "phase execution source Task ledger binding drift")
    end
    entries
  end

  def validate_phase_envelope!(root, truth, source_route, phase, policy)
    envelope = exact_keys(
      truth["phase_execution_envelope"],
      %w[
        schema_version phase status authority_basis accounting_basis limits task_ledger
        consumed reserved remaining external_effects
      ],
      "phase_execution_envelope"
    )
    assert(envelope["schema_version"] == "phase-execution-envelope/v1",
           "phase execution envelope schema drift")
    assert(envelope["phase"] == phase, "phase execution envelope phase drift")
    assert(%w[ACTIVE_REMAINING_CAPACITY TASK_CAPACITY_RESERVED EXHAUSTED].include?(envelope["status"]),
           "phase execution envelope status is invalid")
    authority = exact_keys(
      envelope["authority_basis"],
      %w[
        phase_entry_status policy_path policy_version policy_sha256 source_route_ref
        source_route_id source_decision delegation_amendment
      ],
      "phase execution envelope authority_basis"
    )
    assert(authority["phase_entry_status"] == "AUTHORIZED" &&
           authority["policy_path"] == POLICY_PATH &&
           authority["policy_version"] == POLICY_VERSION &&
           authority["policy_sha256"] == policy["sha256"] &&
           authority["source_route_id"] == source_route["route_id"] &&
           truth[authority["source_route_ref"]] == source_route,
           "phase execution envelope authority binding drift")
    assert(authority["source_decision"] == source_route["decision_packet"],
           "phase execution envelope source Decision identity drift")
    validate_identity(authority["source_decision"], "phase execution envelope source Decision")
    validate_delegation_amendment!(root, authority["delegation_amendment"], phase, policy)
    _amendment_anchor_commit, amendment_anchor_truth = first_truth_anchor!(
      root,
      authority.dig("delegation_amendment", "sha256"),
      "Founder delegation continuity amendment ledger"
    ) do |candidate|
      candidate.dig("phase_execution_envelope", "authority_basis", "delegation_amendment", "sha256") ==
        authority.dig("delegation_amendment", "sha256")
    end
    assert(envelope["accounting_basis"] == "DECLARED_TASK_BUDGET_RESERVATION_NOT_WALL_CLOCK",
           "phase execution envelope accounting basis drift")

    route_envelope = mapping(source_route["envelope"], "historical route envelope")
    limits = exact_keys(
      envelope["limits"],
      %w[engineering_tasks engineering_hours calendar_days active_tasks task_branches task_worktrees active_candidates],
      "phase execution envelope limits"
    )
    expected_limits = {
      "engineering_tasks" => route_envelope["max_engineering_tasks"],
      "engineering_hours" => route_envelope["max_engineering_hours"],
      "calendar_days" => route_envelope["max_calendar_days"],
      "active_tasks" => route_envelope["max_active_tasks"],
      "task_branches" => route_envelope["max_task_branches"],
      "task_worktrees" => route_envelope["max_task_worktrees"],
      "active_candidates" => route_envelope["max_active_candidates"]
    }
    assert(limits == expected_limits, "phase execution envelope limits drift from source route")

    anchored_source_entries = array(
      amendment_anchor_truth.dig("phase_execution_envelope", "task_ledger"),
      "anchored phase execution source task ledger"
    )
    ledger = validate_consumed_task_ledger!(
      root,
      envelope["task_ledger"],
      source_route,
      phase,
      anchored_source_entries
    )
    expected_consumed = {
      "engineering_tasks" => ledger.sum { |entry| entry.dig("budget", "engineering_tasks") },
      "engineering_hours" => ledger.sum { |entry| entry.dig("budget", "engineering_hours") },
      "calendar_days" => ledger.sum { |entry| entry.dig("budget", "calendar_days") }
    }
    consumed = exact_keys(envelope["consumed"], %w[engineering_tasks engineering_hours calendar_days],
                          "phase execution envelope consumed")
    reserved = envelope["reserved"]
    reserved_budget = if reserved.nil?
                        { "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0 }
                      else
                        record = exact_keys(
                          reserved,
                          %w[task_id route_id status capacity_source_task_id budget contract authority],
                          "phase execution reserved Task"
                        )
                        assert(%w[ELIGIBLE_NOT_ACTIVATED ACTIVE].include?(record["status"]),
                               "phase execution reservation lifecycle drift")
                        exact_keys(
                          record["budget"],
                          %w[engineering_tasks engineering_hours calendar_days],
                          "phase execution reserved Task budget"
                        )
                      end
    assert(reserved_budget["engineering_tasks"].between?(0, 1) &&
           reserved_budget["engineering_hours"].is_a?(Integer) && reserved_budget["engineering_hours"] >= 0 &&
           reserved_budget["calendar_days"].is_a?(Integer) && reserved_budget["calendar_days"] >= 0,
           "phase execution reserved Task budget is invalid")
    assert(reserved.nil? || (reserved_budget["engineering_tasks"] == 1 &&
           reserved_budget["engineering_hours"].positive? && reserved_budget["calendar_days"].positive?),
           "phase execution reserved Task budget must reserve one positive Task")
    unless reserved.nil?
      capacity_source = source_capacity_task!(source_route, reserved["capacity_source_task_id"])
      consumed_source_ids = ledger.map { |entry| entry["task_id"] }
      assert(!consumed_source_ids.include?(capacity_source["task_id"]),
             "phase execution reservation reuses consumed source capacity")
    end
    remaining = exact_keys(envelope["remaining"], %w[engineering_tasks engineering_hours calendar_days],
                           "phase execution envelope remaining")
    assert(consumed == expected_consumed, "phase execution envelope consumed accounting drift")
    expected_remaining = {
      "engineering_tasks" => limits["engineering_tasks"] - consumed["engineering_tasks"] - reserved_budget["engineering_tasks"],
      "engineering_hours" => limits["engineering_hours"] - consumed["engineering_hours"] - reserved_budget["engineering_hours"],
      "calendar_days" => limits["calendar_days"] - consumed["calendar_days"] - reserved_budget["calendar_days"]
    }
    assert(remaining == expected_remaining, "phase execution envelope remaining accounting drift")
    assert(remaining.values.all? { |value| value >= 0 },
           "phase execution envelope remaining accounting is negative")
    derived_status = if reserved
                       "TASK_CAPACITY_RESERVED"
                     elsif remaining.values.all?(&:positive?)
                       "ACTIVE_REMAINING_CAPACITY"
                     else
                       "EXHAUSTED"
                     end
    assert(envelope["status"] == derived_status,
           "phase execution envelope status does not match reservation and remaining capacity")
    assert(envelope["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "phase execution envelope external effects exceed offline boundary")
    assert(route_envelope["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "source route external effects exceed offline boundary")
    envelope
  end

  def validate_reserved_trigger_evidence!(trigger, event, phase, historical_route, phase_envelope)
    evidence = parse_bound_json(trigger["evidence"], "Founder reserved trigger evidence")
    exact_keys(
      evidence,
      %w[schema_version category phase source_event source_route_id condition supporting_evidence],
      "Founder reserved trigger evidence"
    )
    assert(evidence["schema_version"] == "founder-reserved-trigger-evidence/v1",
           "Founder reserved trigger evidence schema drift")
    assert(evidence["category"] == trigger["category"] && evidence["phase"] == phase,
           "Founder reserved trigger Evidence category or Phase drift")
    assert(evidence["source_event"] == event,
           "Founder reserved trigger Evidence source event drift")
    assert(evidence["source_route_id"] == historical_route["route_id"],
           "Founder reserved trigger Evidence source Route drift")

    condition = exact_keys(
      evidence["condition"],
      %w[
        phase_route_change material_scope_or_permission_expansion requested_budget
        requested_external_effects irreversible_asset_action
        material_legal_privacy_commercial_commitment critical_residual_risk_acceptance
      ],
      "Founder reserved trigger condition"
    )
    requested_budget = exact_keys(
      condition["requested_budget"],
      %w[engineering_tasks engineering_hours calendar_days],
      "Founder reserved trigger requested budget"
    )
    requested_budget.each do |key, value|
      assert(value.is_a?(Integer) && value >= 0,
             "Founder reserved trigger requested budget #{key} is invalid")
    end
    requested_effects = exact_keys(
      condition["requested_external_effects"],
      FALSE_EXTERNAL_EFFECTS.keys,
      "Founder reserved trigger requested external effects"
    )
    requested_effects.each do |key, value|
      assert(value == true || value == false,
             "Founder reserved trigger requested external effect #{key} is not boolean")
    end
    boolean_keys = %w[
      phase_route_change material_scope_or_permission_expansion irreversible_asset_action
      material_legal_privacy_commercial_commitment critical_residual_risk_acceptance
    ]
    boolean_keys.each do |key|
      assert(condition[key] == true || condition[key] == false,
             "Founder reserved trigger condition #{key} is not boolean")
    end

    limits = mapping(phase_envelope["limits"], "phase execution envelope limits")
    consumed = mapping(phase_envelope["consumed"], "phase execution envelope consumed")
    assert(requested_budget.all? { |key, value| value >= consumed.fetch(key) },
           "Founder reserved trigger requested total budget is below consumed capacity")
    budget_expands = requested_budget.any? do |key, value|
      value > limits.fetch(key)
    end
    effect_expands = requested_effects.values.any?(true)
    signals = {
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" => condition["phase_route_change"],
      "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE" =>
        condition["material_scope_or_permission_expansion"] && budget_expands,
      "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT" => effect_expands,
      "IRREVERSIBLE_ASSET_REMOVAL" => condition["irreversible_asset_action"],
      "MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT" =>
        condition["material_legal_privacy_commercial_commitment"],
      "CRITICAL_RESIDUAL_RISK_ACCEPTANCE" => condition["critical_residual_risk_acceptance"]
    }
    assert(signals.fetch(trigger["category"]),
           "Founder reserved trigger Evidence does not prove its category")
    other_signals = signals.reject { |category, _value| category == trigger["category"] }
    assert(other_signals.values.none?(true),
           "Founder reserved trigger Evidence contains ambiguous reserved conditions")

    support = array(evidence["supporting_evidence"], "Founder reserved trigger supporting Evidence")
    expected_support = array(phase_envelope["task_ledger"], "phase execution task ledger").map do |entry|
      mapping(entry, "phase execution task ledger entry")["outcome_receipt"]
    end
    assert(!support.empty? && support == expected_support,
           "Founder budget expansion trigger must bind every consumed Task outcome receipt")
    support.each_with_index do |identity, index|
      validate_identity(identity, "Founder reserved trigger supporting Evidence[#{index}]")
    end
    evidence
  end

  def validate_control!(truth, phase, phase_gate_status, phase_complete, historical_route, phase_envelope)
    control = exact_keys(
      truth["founder_escalation_control"],
      %w[schema_version disposition source_event reserved_trigger phase_gate_status founder_decision_required next_action_owner next_eligible_action],
      "founder_escalation_control"
    )
    assert(control["schema_version"] == "founder-escalation-control/v1",
           "Founder escalation control schema drift")
    assert(control["phase_gate_status"] == phase_gate_status,
           "Founder escalation control Phase Gate projection drift")
    event = exact_keys(control["source_event"], %w[kind task_id status],
                       "Founder escalation source_event")
    trigger = exact_keys(control["reserved_trigger"], %w[category evidence],
                         "Founder escalation reserved_trigger")
    if ORDINARY_TERMINAL_EVENTS.include?(event["kind"])
      matching_tasks = array(historical_route["task_plan"], "historical route task plan").select do |task|
        task.is_a?(Hash) && task["task_id"] == event["task_id"]
      end
      assert(matching_tasks.length == 1, "ordinary terminal event Task identity drift")
      terminal_task = matching_tasks.first
      assert(event["status"] == terminal_task["status"] && event["status"] == historical_route["status"],
             "ordinary terminal event status drift")
      assert(event["status"].to_s.start_with?("TERMINAL_") && event["status"].to_s.include?("NON_PASS"),
             "ordinary terminal event is not a terminal NON_PASS")
    end

    if trigger["category"] == "NONE"
      assert(trigger["evidence"].nil?, "no reserved trigger may not carry evidence")
      assert(ORDINARY_TERMINAL_EVENTS.include?(event["kind"]),
             "no-trigger continuation requires an ordinary terminal lifecycle event")
      assert(!phase_complete, "completed Phase cannot use ordinary continuation disposition")
      assert(control["disposition"] == CONTINUE_DISPOSITION,
             "ordinary terminal lifecycle must continue inside the Phase")
      assert(control["founder_decision_required"] == false,
             "ordinary terminal lifecycle cannot require Founder decision")
      assert(control["next_action_owner"] == "MASTER_CEO_AGENT",
             "ordinary terminal lifecycle next action owner must be Master")
      assert(control["next_eligible_action"] == CONTINUE_ACTION,
             "ordinary terminal lifecycle next action drift")
      return control
    end

    assert(RESERVED_TRIGGERS.include?(trigger["category"]), "unknown Founder reserved trigger")
    assert(%w[PHASE_ENTRY_OR_EXIT MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE]
             .include?(trigger["category"]),
           "terminal transition only supports mechanically derived Phase exit or envelope expansion")
    expected_event_kind = RESERVED_EVENT_KINDS.fetch(trigger["category"])
    assert(event["kind"] == expected_event_kind,
           "Founder reserved trigger source event kind drift")
    if trigger["category"] == "PHASE_ENTRY_OR_EXIT"
      assert(event["task_id"].nil? && event["status"] == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "Phase exit source event drift")
      assert(phase_complete && phase_gate_status == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "Phase exit escalation requires a complete eligible Exit Gate")
      assert(trigger["evidence"].nil?, "Phase Gate ledger is the Phase exit trigger evidence")
    else
      assert(event["status"] == "PENDING_FOUNDER_RESERVED_DECISION",
             "Founder reserved source event status drift")
      assert(event["task_id"].nil?,
             "Phase envelope expansion source event may not impersonate a Task outcome")
      assert(phase_envelope["status"] == "EXHAUSTED" && phase_envelope["reserved"].nil?,
             "Phase envelope expansion requires exact unreserved exhausted accounting")
      validate_reserved_trigger_evidence!(
        trigger,
        event,
        phase,
        historical_route,
        phase_envelope
      )
    end
    assert(control["disposition"] == FOUNDER_DISPOSITION,
           "reserved trigger requires Founder decision disposition")
    assert(control["founder_decision_required"] == true,
           "reserved trigger requires Founder decision flag")
    assert(control["next_action_owner"] == "HUMAN_FOUNDER",
           "reserved trigger next action owner must be Founder")
    assert(control["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
           "reserved trigger next action drift")
    control
  end

  def validate_continue_state!(truth, policy, historical_route, historical_route_ref, phase_envelope, control)
    project = mapping(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[schema_version route_id status execution_status scheduling_status phase phase_entry_status policy founder_phase_route_decision_required next_eligible_action phase_execution_envelope_ref historical_terminal_route_ref external_effects additional_write_roots inherited_worktree_inventory_source],
      "current_phase_route delegated continuation hold"
    )
    assert(route["schema_version"] == CONTINUATION_ROUTE_SCHEMA, "delegated continuation route schema drift")
    assert(route["route_id"] == "#{route["phase"]}_PHASE_DELEGATED_CONTINUATION_PENDING_TASK_SELECTION",
           "delegated continuation route id drift")
    assert(route["status"] == "AUTHORIZED_READY" &&
           route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
           route["scheduling_status"] == "MASTER_SELECTING_NEXT_INDEPENDENT_PHASE_LOCAL_TASK",
           "delegated continuation route lifecycle drift")
    assert(route["phase"] == project["current_phase"] && route["phase_entry_status"] == "AUTHORIZED",
           "delegated continuation route Phase drift")
    assert(route["policy"] == policy.slice("path", "version", "sha256"),
           "delegated continuation route policy binding drift")
    assert(route["founder_phase_route_decision_required"] == false,
           "delegated continuation route cannot require Founder decision")
    assert(route["next_eligible_action"] == CONTINUE_ACTION,
           "delegated continuation route next action drift")
    assert(route["phase_execution_envelope_ref"] == "phase_execution_envelope",
           "delegated continuation route Phase envelope reference drift")
    assert(route["historical_terminal_route_ref"] == historical_route_ref &&
           route["inherited_worktree_inventory_source"] == historical_route_ref,
           "delegated continuation historical route reference drift")
    assert(truth[route["historical_terminal_route_ref"]].equal?(historical_route) ||
           truth[route["historical_terminal_route_ref"]] == historical_route,
           "delegated continuation historical route binding drift")
    assert(route["external_effects"] == FALSE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "delegated continuation hold may not grant effects or write roots")

    assert(project["p2_entry_status"] == "AUTHORIZED" &&
           project["p2_execution_status"] == "ACTIVE" &&
           project["phase_execution_status"] == "ACTIVE" &&
           project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY",
           "project Phase continuation status drift")

    active = mapping(truth["active_work"], "active_work")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE",
           "delegated continuation requires current Task NONE")
    assert(active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_CONTINUATION_READY",
           "delegated continuation Task resource state drift")
    assert(active["founder_decision_required"] == false &&
           active["founder_decision_required_scope"].nil? &&
           active["escalation_reason"].nil? &&
           active["user_action_required"] == "NONE" &&
           active["phase_route_decision_required"] == false &&
           active["phase_route_user_action_required"] == "NONE" &&
           active["next_eligible_action"] == CONTINUE_ACTION,
           "active_work ordinary terminal projection drift")
    assert(active["founder_reserved_authorization"].nil? &&
           active["founder_reserved_authorization_sha256"].nil?,
           "ordinary continuation must not invent Founder-reserved authorization")
    assert(mapping(active["external_effects"], "active_work.external_effects") == FALSE_EXTERNAL_EFFECTS,
           "active_work external effects drift")
    assert(control["disposition"] == CONTINUE_DISPOSITION,
           "continue state requires no-reserved-trigger disposition")
    assert(phase_envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
           mapping(phase_envelope["remaining"], "phase execution envelope remaining").values.all?(&:positive?),
           "ordinary continuation requires positive Phase envelope capacity")
  end

  def validate_delegated_task_state!(truth, policy, preceding_route, preceding_route_ref,
                                     phase_envelope, control)
    project = mapping(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[
        schema_version route_id status execution_status scheduling_status phase
        phase_entry_status policy founder_phase_route_decision_required next_eligible_action
        phase_execution_envelope_ref source_authority_route_ref preceding_terminal_route_ref
        selected_task external_effects additional_write_roots inherited_worktree_inventory_source
      ],
      "current_phase_route delegated independent Task"
    )
    assert(route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA,
           "delegated independent Task route schema drift")
    assert(route["phase"] == project["current_phase"] && route["phase_entry_status"] == "AUTHORIZED",
           "delegated independent Task route Phase drift")
    assert(route["policy"] == policy.slice("path", "version", "sha256"),
           "delegated independent Task route policy binding drift")
    assert(route["founder_phase_route_decision_required"] == false,
           "delegated independent Task route cannot require Founder decision")
    assert(route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["source_authority_route_ref"] ==
             phase_envelope.dig("authority_basis", "source_route_ref") &&
           route["preceding_terminal_route_ref"] == preceding_route_ref &&
           route["inherited_worktree_inventory_source"] == preceding_route_ref &&
           truth[preceding_route_ref] == preceding_route,
           "delegated independent Task route authority references drift")
    assert(route["external_effects"] == FALSE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "delegated independent Task route may not expand effects or write roots")

    task = exact_keys(
      route["selected_task"],
      %w[
        task_id status task_kind capability objective capacity_source_task_id budget max_same_task_repairs
        contract independence
      ],
      "delegated independent Task descriptor"
    )
    task_id = task["task_id"]
    assert(task_id.to_s.match?(/\AAIOS-#{route['phase']}-[0-9]{3}_[A-Z0-9_]+\z/),
           "delegated independent Task id is invalid")
    assert(route["route_id"] == "#{task_id}_PHASE_DELEGATED_ROUTE",
           "delegated independent Task Route id drift")
    boundary = mapping(truth["phase_boundary"], "phase_boundary")
    assert(array(boundary["allowed_task_kinds"], "Phase allowed Task kinds").include?(task["task_kind"]),
           "delegated Task kind is outside the current Phase")
    assert(array(boundary["allowed_capabilities"], "Phase allowed capabilities").include?(task["capability"]),
           "delegated Task capability is outside the current Phase")
    assert(task["objective"].is_a?(String) && !task["objective"].empty?,
           "delegated independent Task objective missing")
    source_route = mapping(
      truth[phase_envelope.dig("authority_basis", "source_route_ref")],
      "delegated independent Task source Route"
    )
    capacity_source = source_capacity_task!(source_route, task["capacity_source_task_id"])
    assert(!capacity_source["status"].to_s.start_with?("TERMINAL_") &&
           !capacity_source["status"].to_s.include?("ACCEPTED"),
           "delegated independent Task capacity source is already consumed")
    budget = exact_keys(
      task["budget"],
      %w[engineering_hours calendar_days implementation_iterations candidates],
      "delegated independent Task budget"
    )
    budget.each do |key, value|
      assert(value.is_a?(Integer) && value.positive?, "delegated independent Task budget #{key} is invalid")
    end
    assert(budget["candidates"] == 1,
           "delegated independent Task candidate budget must equal one")
    max_repairs = integer(task["max_same_task_repairs"], "delegated Task same-Task repair budget")
    assert(max_repairs >= 0,
           "delegated Task same-Task repair budget must not be negative")
    assert(max_repairs <= budget["implementation_iterations"] - 1,
           "delegated Task repairs exceed implementation iterations minus one")
    assert(
           max_repairs <= capacity_source["max_same_task_repairs"] &&
           max_repairs <= truth.dig("phase_delegation", "anti_loop", "maximum_same_task_bounded_contract_repairs"),
           "delegated Task same-Task repair budget exceeds Phase delegation")
    assert(budget["engineering_hours"] <= capacity_source["engineering_hours"] &&
           budget["calendar_days"] <= capacity_source["calendar_days"] &&
           budget["implementation_iterations"] <= capacity_source["max_implementation_iterations"] &&
           budget["candidates"] <= capacity_source["max_candidates"],
           "delegated independent Task budget exceeds its Founder-bound source capacity slot")
    independence = exact_keys(
      task["independence"],
      %w[
        new_task_id new_execution_nonce new_branch new_worktree new_contract new_evidence_root
        rejected_lineage_read rejected_lineage_compare rejected_lineage_copy
        same_phase_objective successor_or_replacement
      ],
      "delegated independent Task independence"
    )
    assert(independence == {
      "new_task_id" => true,
      "new_execution_nonce" => true,
      "new_branch" => true,
      "new_worktree" => true,
      "new_contract" => true,
      "new_evidence_root" => true,
      "rejected_lineage_read" => false,
      "rejected_lineage_compare" => false,
      "rejected_lineage_copy" => false,
      "same_phase_objective" => true,
      "successor_or_replacement" => false
    }, "delegated independent Task independence classification drift")
    historical_ids = truth.select { |key, value| key.to_s.start_with?("historical_") && value.is_a?(Hash) }
                          .values.flat_map do |historical|
      task_plan_ids = Array(historical["task_plan"]).map do |item|
        item["task_id"] if item.is_a?(Hash)
      end.compact
      selected_id = historical.dig("selected_task", "task_id")
      task_plan_ids + [selected_id].compact
    end
    assert(!historical_ids.include?(task_id), "delegated independent Task reuses a historical Task id")

    reservation = mapping(phase_envelope["reserved"], "delegated independent Task reservation")
    expected_reservation_budget = {
      "engineering_tasks" => 1,
      "engineering_hours" => budget["engineering_hours"],
      "calendar_days" => budget["calendar_days"]
    }
    assert(reservation["task_id"] == task_id && reservation["route_id"] == route["route_id"] &&
           reservation["capacity_source_task_id"] == task["capacity_source_task_id"] &&
           reservation["status"] == task["status"] && reservation["budget"] == expected_reservation_budget &&
           reservation["contract"] == task["contract"],
           "delegated independent Task reservation binding drift")
    assert(phase_envelope["status"] == "TASK_CAPACITY_RESERVED",
           "delegated independent Task requires exact Phase capacity reservation")

    active = mapping(truth["active_work"], "active_work")
    assert(control["disposition"] == CONTINUE_DISPOSITION,
           "delegated independent Task requires autonomous continuation disposition")
    if task["status"] == "ELIGIBLE_NOT_ACTIVATED"
      assert(route["status"] == "AUTHORIZED_READY" &&
             route["execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
             route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" &&
             route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
             "delegated independent Task READY lifecycle drift")
      assert(reservation["authority"].nil?, "READY delegated Task may not pre-create active authority")
      assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
             active["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
             "delegated independent Task READY active_work drift")
      assert(project["current_route_execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
             mapping(truth["goal"], "goal")["current_task_authority"] == "NONE",
             "delegated independent Task READY project or Goal projection drift")
    elsif task["status"] == "ACTIVE"
      assert(route["status"] == "ACTIVE" && route["execution_status"] == "ACTIVE" &&
             route["scheduling_status"] == "ACTIVE_PHASE_DELEGATED_TASK" &&
             route["next_eligible_action"] == "COMPLETE_CURRENT_TASK_GATE",
             "delegated independent Task ACTIVE lifecycle drift")
      reserved_authority = exact_keys(
        reservation["authority"],
        %w[path byte_length sha256],
        "ACTIVE delegated Task reserved authority"
      )
      active_authority = exact_keys(
        active["authority_record"],
        %w[path byte_length sha256],
        "ACTIVE delegated Task active_work authority"
      )
      assert(reserved_authority == active_authority &&
             active["current_execution_authorization"] == reserved_authority["path"] &&
             active["current_execution_authorization_sha256"] == reserved_authority["sha256"],
             "ACTIVE delegated Task reserved authority identity drift")
      validate_identity(reserved_authority, "ACTIVE delegated Task reserved authority")
      assert(active["current_task"] == task_id && active["current_task_status"] == "ACTIVE" &&
             active["task_resource_state"] == "ACTIVE_UNIQUE_PHASE_DELEGATED" &&
             active["next_eligible_action"] == "COMPLETE_CURRENT_TASK_GATE",
             "delegated independent Task ACTIVE active_work drift")
      assert(project["current_route_execution_status"] == "ACTIVE_PHASE_DELEGATED_TASK" &&
             mapping(truth["goal"], "goal")["current_task_authority"] == task_id,
             "delegated independent Task ACTIVE project or Goal projection drift")
      historical_active = truth.select do |key, value|
        key.to_s.start_with?("historical_") && value.is_a?(Hash) &&
          value["current_task"].is_a?(String) && value["current_task"] != "NONE"
      end.values
      historical_active.each do |record|
        assert(active["execution_nonce"] != record["execution_nonce"] &&
               active["authorization_id"] != record["authorization_id"] &&
               active["task_branch"] != record["task_branch"] &&
               active["task_worktree"] != record["task_worktree"] &&
               active["execution_evidence_root"] != record["execution_evidence_root"] &&
               task.dig("contract", "path") != record.dig("current_task_contract", "path") &&
               reserved_authority["path"] != record.dig("authority_record", "path"),
               "delegated independent Task reuses historical execution lineage identity")
      end
    else
      fail!("delegated independent Task status is invalid")
    end
    assert(active["founder_reserved_authorization"].nil? &&
           active["founder_reserved_authorization_sha256"].nil? &&
           active["founder_decision_required"] == false &&
           active["phase_route_decision_required"] == false &&
           active["user_action_required"] == "NONE" &&
           active["phase_route_user_action_required"] == "NONE",
           "delegated independent Task must not invent a Founder authorization or action")
    assert(project["p2_entry_status"] == "AUTHORIZED" &&
           project["p2_execution_status"] == "ACTIVE" &&
           project["phase_execution_status"] == "ACTIVE",
           "delegated independent Task requires active P2 Phase execution")
  end

  def validate_delegated_terminal_route_projection!(truth, historical_route, phase_envelope, control)
    route = exact_keys(
      historical_route,
      %w[
        schema_version route_id status execution_status scheduling_status phase phase_entry_status
        task_id capacity_source_task_id contract outcome_receipt formal_forensic
        accepted_capability_created capability_credit inherited_worktree_inventory
      ],
      "historical delegated terminal Route"
    )
    assert(route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA &&
           route["status"].to_s.start_with?("TERMINAL_") &&
           route["status"].to_s.include?("NON_PASS") &&
           route["execution_status"] == route["status"] &&
           route["accepted_capability_created"] == false && route["capability_credit"] == 0,
           "historical delegated terminal Route lifecycle or capability drift")
    entries = array(phase_envelope["task_ledger"], "phase execution task ledger").select do |entry|
      entry.is_a?(Hash) && entry["task_id"] == route["task_id"]
    end
    assert(entries.length == 1, "historical delegated terminal Route ledger binding is missing or ambiguous")
    entry = entries.first
    assert(route["route_id"] == entry["route_id"] && route["status"] == entry["status"] &&
           route["capacity_source_task_id"] == entry["capacity_source_task_id"] &&
           route["contract"] == entry["contract"] &&
           route["outcome_receipt"] == entry["outcome_receipt"] &&
           route["formal_forensic"] == entry["formal_forensic"] &&
           route["capability_credit"] == entry["capability_credit"],
           "historical delegated terminal Route drifts from validated terminal ledger")
    receipt = parse_bound_json(entry["outcome_receipt"], "historical delegated terminal receipt")
    candidate = exact_keys(
      receipt["candidate"],
      %w[commit tree parent_commit tracked_binary_diff_sha256 integrated],
      "historical delegated terminal candidate"
    )
    inherited = array(route["inherited_worktree_inventory"],
                      "historical delegated terminal worktree inventory")
    assert(inherited.length == 1, "historical delegated terminal worktree inventory is not unique")
    worktree = exact_keys(inherited.first, %w[path head branch status],
                          "historical delegated terminal worktree")
    binding = entry["activation_binding"]
    assert(worktree["path"] == binding["task_worktree"] &&
           worktree["branch"] == binding["task_branch"] &&
           worktree["head"] == candidate["commit"] &&
           worktree["status"] == "INHERITED_TERMINAL_OUT_OF_SCOPE_NOT_CURRENT",
           "historical delegated terminal worktree projection drift")

    claim = mapping(truth["claim_boundary"], "claim_boundary")
    task_match = route["task_id"].to_s.match(/\AAIOS-(P(?:0|[1-9]|1[0-2]))-([0-9]{3})_/)
    assert(task_match, "historical delegated terminal Task id cannot project claim boundary")
    prefix = "#{task_match[1].downcase}_#{task_match[2]}"
    expected = {
      "current_phase_route" => truth.dig("current_phase_route", "route_id"),
      "current_task" => truth.dig("active_work", "current_task"),
      "next_eligible_action" => truth.dig("active_work", "next_eligible_action"),
      "#{prefix}_status" => entry["status"],
      "#{prefix}_terminal_receipt_sha256" => entry.dig("outcome_receipt", "sha256"),
      "#{prefix}_formal_inventory_sha256" =>
        entry.dig("formal_forensic", "canonical_inventory_sha256"),
      "#{prefix}_capability_credit" => entry["capability_credit"],
      "#{task_match[1].downcase}_phase_envelope_status" => phase_envelope["status"],
      "#{task_match[1].downcase}_phase_envelope_consumed_tasks" =>
        phase_envelope.dig("consumed", "engineering_tasks"),
      "#{task_match[1].downcase}_phase_envelope_consumed_engineering_hours" =>
        phase_envelope.dig("consumed", "engineering_hours"),
      "#{task_match[1].downcase}_phase_envelope_consumed_calendar_days" =>
        phase_envelope.dig("consumed", "calendar_days"),
      "founder_reserved_trigger" => control.dig("reserved_trigger", "category")
    }
    expected.each do |key, value|
      assert(claim[key] == value, "claim_boundary terminal projection drift: #{key}")
    end
    expected_progress =
      "P1_COMPLETE_#{task_match[1]}_ZERO_ACCEPTED_CAPABILITY_#{prefix.upcase}_#{entry['status']}"
    assert(claim["real_engineering_progress"] == expected_progress,
           "claim_boundary real engineering progress drift")
  end

  def validate_reserved_state!(truth, policy, historical_route_ref, phase_envelope, control)
    project = mapping(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[schema_version route_id status execution_status scheduling_status phase phase_entry_status policy founder_phase_route_decision_required next_eligible_action phase_execution_envelope_ref historical_terminal_route_ref external_effects additional_write_roots inherited_worktree_inventory_source],
      "current_phase_route Founder reserved hold"
    )
    assert(route["schema_version"] == RESERVED_ROUTE_SCHEMA,
           "Founder reserved disposition requires the exact reserved-decision hold schema")
    assert(route["route_id"].to_s.match?(/\AP(?:0|[1-9]|1[0-2])_FOUNDER_RESERVED_DECISION_HOLD\z/),
           "Founder reserved hold route id drift")
    assert(route["status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
           route["execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
           route["scheduling_status"] == "STOPPED_AT_FOUNDER_RESERVED_DECISION",
           "Founder reserved hold route lifecycle drift")
    assert(route["phase"] == project["current_phase"] && route["phase_entry_status"] == "AUTHORIZED",
           "Founder reserved hold Phase drift")
    assert(route["policy"] == policy.slice("path", "version", "sha256"),
           "Founder reserved hold policy binding drift")
    assert(route["founder_phase_route_decision_required"] == true &&
           route["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
           "Founder reserved hold decision projection drift")
    assert(route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["historical_terminal_route_ref"] == historical_route_ref &&
           route["inherited_worktree_inventory_source"] == historical_route_ref,
           "Founder reserved hold reference drift")
    assert(route["external_effects"] == FALSE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "Founder reserved hold may not grant effects or write roots")

    assert(project["phase_execution_status"] == "STOPPED_AT_FOUNDER_RESERVED_DECISION" &&
           project["current_route_execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED",
           "project Founder reserved hold status drift")
    active = mapping(truth["active_work"], "active_work")
    category = mapping(control["reserved_trigger"], "Founder reserved trigger")["category"]
    if phase_envelope["status"] == "EXHAUSTED"
      assert(category == "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE",
             "exhausted Phase capacity requires the exact envelope-expansion trigger")
    end
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE",
           "Founder reserved hold requires current Task NONE")
    assert(active["task_resource_state"] == "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD",
           "Founder reserved hold Task resource state drift")
    assert(active["founder_decision_required"] == true &&
           active["founder_decision_required_scope"] == category &&
           active["escalation_reason"] == category &&
           active["user_action_required"] == "FOUNDER_RESERVED_DECISION" &&
           active["phase_route_decision_required"] == true &&
           active["phase_route_user_action_required"] == "FOUNDER_RESERVED_DECISION" &&
           active["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
           "active_work Founder reserved decision projection drift")
    historical_route = mapping(truth[historical_route_ref], historical_route_ref)
    if historical_route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA
      validate_delegated_terminal_route_projection!(
        truth,
        historical_route,
        phase_envelope,
        control
      )
    end
  end

  def validate_non_transition_state!(truth)
    route = mapping(truth["current_phase_route"], "current_phase_route")
    active = mapping(truth["active_work"], "active_work")
    assert(route["founder_phase_route_decision_required"] != true,
           "ordinary active or ready Route cannot self-authorize a Founder interruption")
    assert(active["founder_decision_required"] != true &&
           active["phase_route_decision_required"] != true,
           "ordinary active or ready Task cannot self-authorize a Founder interruption")
    assert(active["next_eligible_action"].to_s !~ /FOUNDER/ &&
           active["user_action_required"].to_s !~ /FOUNDER/,
           "ordinary active or ready Task cannot route its next action to Founder")
    if truth["founder_escalation_control"].is_a?(Hash)
      control = truth["founder_escalation_control"]
      assert(control["founder_decision_required"] != true &&
             control["disposition"] != FOUNDER_DISPOSITION,
             "Founder escalation control cannot interrupt a non-reserved Route")
    end
    "ACTIVE_OR_READY_PHASE_TASK_NO_FOUNDER_INTERRUPT"
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    assert(truth["record_type"] == "sourcelens_aios_current_truth", "unexpected Truth record type")
    policy = validate_policy!(root, truth)
    project = mapping(truth["project"], "project")
    phase = project["current_phase"]
    assert(phase.is_a?(String) && phase.match?(/\AP(?:0|[1-9]|1[0-2])\z/), "current Phase is invalid")
    validate_phase_delegation!(truth, phase)
    assert(truth["phase_execution_envelope"].is_a?(Hash),
           "active Phase delegation requires a phase execution envelope")
    phase_record, phase_complete, phase_gate_status = phase_gate_state(truth, phase)
    if phase_complete
      assert(%w[EXIT_GATE_READY COMPLETE].include?(phase_record["status"]),
             "strict Phase complete items require Exit Gate ready or complete status")
    else
      assert(phase_record["status"] == "INCOMPLETE",
             "strict Phase incomplete items require INCOMPLETE status")
    end

    route = mapping(truth["current_phase_route"], "current_phase_route")
    unless [CONTINUATION_ROUTE_SCHEMA, RESERVED_ROUTE_SCHEMA, DELEGATED_TASK_ROUTE_SCHEMA].include?(route["schema_version"])
      assert(!truth["phase_execution_envelope"].is_a?(Hash),
             "active Phase delegation envelope requires a closed delegated Route schema")
      return validate_non_transition_state!(truth)
    end
    historical_route_ref = if route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA
                             route["preceding_terminal_route_ref"]
                           else
                             historical_route_ref!(truth, route)
                           end
    historical_route = mapping(truth[historical_route_ref], historical_route_ref)
    assert(historical_route["phase"] == phase && historical_route["phase_entry_status"] == "AUTHORIZED",
           "historical terminal route Phase drift")
    assert(historical_route["status"].to_s.start_with?("TERMINAL_") &&
           historical_route["execution_status"] == historical_route["status"],
           "historical route is not an exact terminal lifecycle")
    source_route_ref = truth.dig("phase_execution_envelope", "authority_basis", "source_route_ref")
    assert(source_route_ref.is_a?(String), "phase execution envelope source Route reference missing")
    source_route = mapping(truth[source_route_ref], source_route_ref)
    validate_source_route_authority!(root, source_route)
    phase_envelope = validate_phase_envelope!(root, truth, source_route, phase, policy)
    control = validate_control!(
      truth,
      phase,
      phase_gate_status,
      phase_complete,
      historical_route,
      phase_envelope
    )
    if route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA
      validate_delegated_task_state!(
        truth,
        policy,
        historical_route,
        historical_route_ref,
        phase_envelope,
        control
      )
    elsif control["disposition"] == CONTINUE_DISPOSITION
      validate_continue_state!(
        truth,
        policy,
        historical_route,
        historical_route_ref,
        phase_envelope,
        control
      )
    else
      validate_reserved_state!(truth, policy, historical_route_ref, phase_envelope, control)
    end
    control["disposition"]
  end

  def validate!(truth_path: nil, root: nil)
    root ||= `git rev-parse --show-toplevel`.strip
    fail!("cannot resolve repository root") if root.empty?
    truth_path ||= File.join(root, "docs/aios/truth/project_state.yaml")
    validate_truth!(root: root, truth: parse_truth(truth_path))
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    truth_path = if ARGV.empty?
                   nil
                 elsif ARGV.length == 2 && ARGV.first == "--fixture"
                   ARGV.last
                 else
                   raise FounderDelegationContinuityError, "usage: validate-founder-delegation-continuity.rb [--fixture TRUTH]"
                 end
    disposition = FounderDelegationContinuity.validate!(truth_path: truth_path)
    puts "FOUNDER_DELEGATION_CONTINUITY: PASS disposition=#{disposition}"
  rescue FounderDelegationContinuityError => e
    warn "FOUNDER_DELEGATION_CONTINUITY: NON_PASS #{e.message}"
    exit 1
  rescue StandardError => e
    warn "FOUNDER_DELEGATION_CONTINUITY: NON_PASS unexpected #{e.class}: #{e.message}"
    exit 1
  end
end

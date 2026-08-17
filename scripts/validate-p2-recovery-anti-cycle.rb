#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "psych"
require "yaml"
require_relative "validate-current-task-authority"
require_relative "validate-p2-benchmark-source-pack"

module P2RecoveryAntiCycle
  ROOT = File.expand_path("..", __dir__)
  DEFAULT_TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
  DEFAULT_PLAN = File.join(ROOT, "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml")
  DEFAULT_RULES = File.join(ROOT, "AGENTS.md")

  class ValidationError < StandardError; end

  module_function

  def exact_keys!(value, keys, label)
    unless value.is_a?(Hash) && value.keys.sort == keys.sort
      raise ValidationError, "#{label} is not a closed object"
    end
    value
  end

  def assert!(condition, message)
    raise ValidationError, message unless condition
  end

  def reject_duplicate_yaml_keys!(bytes, label)
    stream = Psych.parse_stream(bytes)
    visit = nil
    visit = lambda do |node, location|
      case node
      when Psych::Nodes::Mapping
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          key = key_node.value
          raise ValidationError, "#{label} duplicate YAML key at #{location}.#{key}" if seen[key]
          seen[key] = true
          visit.call(value_node, "#{location}.#{key}")
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index { |child, index| visit.call(child, "#{location}[#{index}]") }
      else
        children = node.respond_to?(:children) ? node.children : nil
        children&.each { |child| visit.call(child, location) }
      end
    end
    stream.children.each { |child| visit.call(child, label) }
  end

  def read_yaml!(path, label, repo_root)
    stat = File.lstat(path)
    assert!(stat.file? && !stat.symlink? && stat.nlink == 1, "#{label} must be a regular nlink1 non-symlink file")
    real = File.realpath(path)
    root = File.realpath(repo_root)
    assert!(real == root || real.start_with?(root + File::SEPARATOR), "#{label} escapes repository root")
    bytes = File.binread(path)
    reject_duplicate_yaml_keys!(bytes, label)
    [YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false), bytes]
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise ValidationError, "#{label} is unavailable: #{error.message}"
  end

  def git!(repo_root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", repo_root, *args)
    raise ValidationError, "git #{args.join(' ')} failed: #{stderr}" unless status.success?
    stdout
  end

  def validate_source_guardrails_bytes!(raw_bytes)
    text = raw_bytes.dup.force_encoding("UTF-8")
    assert!(text.valid_encoding?, "P2 source guardrails encoding is invalid")
    pattern = /<!-- P2_BENCHMARK_SOURCE_GUARDRAILS_BEGIN -->\n```yaml\n(?<yaml>.*?)```\n<!-- P2_BENCHMARK_SOURCE_GUARDRAILS_END -->/m
    matches = text.to_enum(:scan, pattern).map { Regexp.last_match }
    assert!(matches.length == 1, "P2 source guardrails block is missing or duplicated")
    bytes = matches.first[:yaml]
    reject_duplicate_yaml_keys!(bytes, "P2 source guardrails")
    guardrails = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    exact_keys!(guardrails, %w[delegation progress runtime schema_version selection], "P2 source guardrails")
    assert!(guardrails["schema_version"] == "p2-benchmark-source-guardrails/v1", "P2 source guardrails schema drift")

    runtime = exact_keys!(guardrails.fetch("runtime"), %w[
      build_parameter_override_allowed build_process_network_sandbox build_subprocess_network_mode dependency_bytes_provenance
      file_repository_or_closed_env_alone_proves_offline gradle_required_arguments java_major
      maven_required_arguments newer_java_install_authorized
      tool_install_user_and_explicit_config_preflight_required
    ], "P2 source runtime guardrails")
    assert!(runtime == {
      "java_major" => 17,
      "newer_java_install_authorized" => false,
      "build_parameter_override_allowed" => false,
      "build_subprocess_network_mode" => "FORCE_OFFLINE_BEFORE_SPAWN",
      "build_process_network_sandbox" => "MACOS_SANDBOX_EXEC_DENY_NETWORK_REQUIRED",
      "maven_required_arguments" => %w[--offline --global-settings --settings -Dmaven.repo.local],
      "gradle_required_arguments" => %w[--offline --no-daemon],
      "tool_install_user_and_explicit_config_preflight_required" => true,
      "file_repository_or_closed_env_alone_proves_offline" => false,
      "dependency_bytes_provenance" => "CONTROLLED_EXACT_CURL_CUSTODY_ONLY"
    }, "P2 source runtime guardrails drift")

    selection = exact_keys!(guardrails.fetch("selection"), %w[
      base_and_fix_jdk17_probe_required dependency_closure_before_freeze
      effective_compiler_release_max exact_submodule_exception_requires_observed_jdk17_build
      final_freeze_requires_prefreeze_gate_pass
      final_freeze_before_toolchain_probe_allowed final_repository_count final_task_count
      prefreeze_gate_must_execute_bound_builds response_order_freeze_allowed
      self_report_only_receipts_allowed tasks_per_repository
    ], "P2 source selection guardrails")
    assert!(selection == {
      "final_repository_count" => 6,
      "final_task_count" => 12,
      "tasks_per_repository" => 2,
      "base_and_fix_jdk17_probe_required" => true,
      "effective_compiler_release_max" => 17,
      "exact_submodule_exception_requires_observed_jdk17_build" => true,
      "dependency_closure_before_freeze" => true,
      "response_order_freeze_allowed" => false,
      "final_freeze_before_toolchain_probe_allowed" => false,
      "prefreeze_gate_must_execute_bound_builds" => true,
      "self_report_only_receipts_allowed" => false,
      "final_freeze_requires_prefreeze_gate_pass" => true
    }, "P2 source selection guardrails drift")

    delegation = exact_keys!(guardrails.fetch("delegation"), %w[
      active_direct_capability_required_for_network default_after_route_non_pass
      future_network_request_style next_independent_route_owner
      numbered_single_route_reauthorization_chain_allowed ordinary_route_non_pass_founder_trigger
      reauthorization_required_only_for rules_do_not_authorize_network
      terminal_single_use_capability_reuse_allowed
    ], "P2 source delegation guardrails")
    assert!(delegation == {
      "ordinary_route_non_pass_founder_trigger" => false,
      "rules_do_not_authorize_network" => true,
      "next_independent_route_owner" => "MASTER_CEO_AGENT",
      "default_after_route_non_pass" => "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK",
      "numbered_single_route_reauthorization_chain_allowed" => false,
      "future_network_request_style" => "PHASE_MILESTONE_SCOPED_BOUNDED_CAPABILITY",
      "active_direct_capability_required_for_network" => true,
      "terminal_single_use_capability_reuse_allowed" => false,
      "reauthorization_required_only_for" => %w[
        NO_VALID_NETWORK_CAPABILITY
        HOST_METHOD_BUDGET_CREDENTIAL_WRITE_OR_PHASE_SCOPE_EXPANSION
        CRITICAL_RESIDUAL_RISK_ACCEPTANCE
      ]
    }, "P2 source delegation guardrails drift")

    progress = exact_keys!(guardrails.fetch("progress"), %w[
      acquisition_credit governance_credit review_receipt_terminal_credit
    ], "P2 source progress guardrails")
    assert!(progress.values.all?(&:zero?), "P2 source guardrail activity gained progress credit")
    guardrails
  end

  def validate_source_guardrails!(rules_path, repo_root)
    assert!(File.expand_path(rules_path) == File.expand_path(DEFAULT_RULES), "production P2 source guardrails must use canonical AGENTS.md")
    stat = File.lstat(rules_path)
    assert!(stat.file? && !stat.symlink? && stat.nlink == 1, "P2 source guardrails rules must be a regular nlink1 non-symlink file")
    real = File.realpath(rules_path)
    root = File.realpath(repo_root)
    assert!(real == root || real.start_with?(root + File::SEPARATOR), "P2 source guardrails rules escape repository root")
    validate_source_guardrails_bytes!(File.binread(rules_path))
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise ValidationError, "P2 source guardrails rules are unavailable: #{error.message}"
  end

  def validate_plan!(plan, repo_root)
    exact_keys!(plan, %w[
      authority_boundary baseline current_control drift_diagnosis mechanical_controls
      progress_model recommended_recovery_sequence root_causes schema_version status
    ], "P2 recovery plan")
    assert!(plan["schema_version"] == "p2-recovery-and-anti-cycle-plan/v1", "P2 recovery plan schema drift")
    assert!(plan["status"] == "FOUNDER_CORRECTION_ACTIVE_AWAITING_ENVELOPE_AUTHORIZATION", "P2 recovery plan status drift")

    authority = exact_keys!(plan.fetch("authority_boundary"), %w[
      activates_task authorizes_external_effects changes_exit_gate changes_phase_objective
      creates_engineering_progress_credit expands_phase_envelope
    ], "P2 recovery authority boundary")
    assert!(authority.values == [false, false, false, false, false, false], "P2 recovery correction expanded authority")

    baseline = exact_keys!(plan.fetch("baseline"), %w[
      canonical_commit canonical_tree current_phase current_task p2_entry_activation_parent_commit
      p2_entry_activation_parent_tree phase_envelope strict_exit_gate
    ], "P2 recovery baseline")
    assert!(baseline["current_phase"] == "P2" && baseline["current_task"] == "NONE", "P2 recovery baseline phase/task drift")
    assert!(git!(repo_root, "show", "-s", "--format=%T", baseline.fetch("canonical_commit")).strip == baseline.fetch("canonical_tree"), "P2 recovery canonical commit/tree mismatch")
    assert!(git!(repo_root, "show", "-s", "--format=%T", baseline.fetch("p2_entry_activation_parent_commit")).strip == baseline.fetch("p2_entry_activation_parent_tree"), "P2 entry commit/tree mismatch")
    system("git", "-C", repo_root, "merge-base", "--is-ancestor", baseline.fetch("canonical_commit"), "HEAD", out: File::NULL, err: File::NULL)
    assert!($?.success?, "P2 recovery baseline is not canonical ancestry")

    gate = exact_keys!(baseline.fetch("strict_exit_gate"), %w[accepted missing_item percent total], "P2 recovery strict gate baseline")
    assert!(gate == {
      "accepted" => 0,
      "total" => 1,
      "percent" => 0,
      "missing_item" => "CONTEXT_BENCHMARK_BEATS_SIMPLE_RETRIEVAL_BASELINES"
    }, "P2 recovery strict gate baseline drift")
    envelope = exact_keys!(baseline.fetch("phase_envelope"), %w[consumed limits remaining status], "P2 recovery envelope baseline")
    expected_budget = { "engineering_tasks" => 12, "engineering_hours" => 336, "calendar_days" => 84 }
    expected_zero = { "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0 }
    assert!(envelope["status"] == "EXHAUSTED" && envelope["limits"] == expected_budget && envelope["consumed"] == expected_budget && envelope["remaining"] == expected_zero, "P2 recovery envelope baseline drift")

    validate_diff_diagnosis!(plan.fetch("drift_diagnosis"), baseline, repo_root)
    validate_root_causes!(plan.fetch("root_causes"))
    validate_progress_model!(plan.fetch("progress_model"))
    validate_sequence!(plan.fetch("recommended_recovery_sequence"))
    validate_controls!(plan.fetch("mechanical_controls"))
    validate_current_control!(plan.fetch("current_control"))
  end

  def validate_diff_diagnosis!(diagnosis, baseline, repo_root)
    exact_keys!(diagnosis, %w[
      accepted_p2_capability_count exact_diff_since_p2_entry execution_deviation
      self_loop_currently_running self_loop_occurred strategic_direction_changed
    ], "P2 drift diagnosis")
    assert!(diagnosis["strategic_direction_changed"] == false, "P2 strategy direction may not be silently changed")
    assert!(diagnosis["execution_deviation"] == "SEVERE" && diagnosis["self_loop_occurred"] == true && diagnosis["self_loop_currently_running"] == false, "P2 drift classification drift")
    assert!(diagnosis["accepted_p2_capability_count"] == 0, "P2 accepted capability count is not zero")

    diff = exact_keys!(diagnosis.fetch("exact_diff_since_p2_entry"), %w[evaluation governance other product], "P2 drift diff")
    expected_prefixes = {
      "product" => %w[backend-spring/ analyzer-rust/ web-console/],
      "evaluation" => ["evaluation-harness/"],
      "governance" => %w[docs/aios/ scripts/]
    }
    actual = Hash.new { |hash, key| hash[key] = { "changed_files" => 0, "insertions" => 0, "deletions" => 0 } }
    other_paths = []
    range = "#{baseline.fetch('p2_entry_activation_parent_commit')}..#{baseline.fetch('canonical_commit')}"
    git!(repo_root, "diff", "--numstat", range).each_line do |line|
      additions, deletions, path = line.chomp.split("\t", 3)
      group = expected_prefixes.find { |_name, prefixes| prefixes.any? { |prefix| path.start_with?(prefix) } }&.first || "other"
      actual[group]["changed_files"] += 1
      actual[group]["insertions"] += additions == "-" ? 0 : additions.to_i
      actual[group]["deletions"] += deletions == "-" ? 0 : deletions.to_i
      other_paths << path if group == "other"
    end
    expected_prefixes.each do |name, prefixes|
      entry = exact_keys!(diff.fetch(name), %w[changed_files deletions insertions path_prefixes], "P2 #{name} diff")
      assert!(entry["path_prefixes"] == prefixes && entry.reject { |key, _| key == "path_prefixes" } == actual[name], "P2 #{name} diff facts drift")
    end
    other = exact_keys!(diff.fetch("other"), %w[changed_files deletions exact_paths insertions], "P2 other diff")
    assert!(other["exact_paths"] == other_paths.sort && other.reject { |key, _| key == "exact_paths" } == actual["other"], "P2 other diff facts drift")
  end

  def validate_root_causes!(causes)
    expected = %w[
      PROOF_INFRASTRUCTURE_PRECEDED_PRODUCT_VALUE
      REPRESENTATIVENESS_FROZEN_TOO_LATE
      ALL_IN_ONE_TASK_SCOPE
      REVIEW_FINDINGS_NOT_GATE_RELEVANCE_FILTERED
      GOVERNANCE_ACTIVITY_MISREAD_AS_PROGRESS
      NO_ACCEPTED_MILESTONE_CHECKPOINTS
    ]
    assert!(causes.is_a?(Array) && causes.length == expected.length, "P2 root cause set drift")
    causes.each { |cause| exact_keys!(cause, %w[id statement], "P2 root cause") }
    assert!(causes.map { |cause| cause["id"] } == expected, "P2 root cause order or identity drift")
    assert!(causes.all? { |cause| cause["statement"].is_a?(String) && !cause["statement"].strip.empty? }, "P2 root cause statement missing")
  end

  def validate_progress_model!(model)
    exact_keys!(model, %w[current_delivery_percent delivery_milestones strict_gate zero_credit_activities], "P2 progress model")
    strict = exact_keys!(model.fetch("strict_gate"), %w[allowed_percent_values current_percent rule], "P2 strict progress")
    assert!(strict == { "rule" => "BINARY_ACCEPTED_GATE_ONLY", "current_percent" => 0, "allowed_percent_values" => [0, 100] }, "P2 strict progress is not binary")
    milestones = model.fetch("delivery_milestones")
    expected = [
      ["P2_RECOVERY_BASELINE_ACCEPTED", 25],
      ["P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED", 70],
      ["P2_RECOVERY_FORMAL_HELD_MATRIX_COMPLETE", 85],
      ["P2_EXIT_GATE_ACCEPTED", 100]
    ]
    assert!(milestones.is_a?(Array) && milestones.length == expected.length, "P2 delivery milestone count drift")
    milestones.each { |milestone| exact_keys!(milestone, %w[acceptance id percent], "P2 delivery milestone") }
    assert!(milestones.map { |milestone| [milestone["id"], milestone["percent"]] } == expected, "P2 delivery milestone values drift")
    assert!(model["current_delivery_percent"] == 0, "P2 delivery progress may not be inferred from activity")
    assert!(model["zero_credit_activities"] == %w[
      governance_document_created validator_or_schema_created review_or_receipt_created
      evidence_inventory_created time_or_budget_consumed task_terminal_non_pass
      nonintegrated_candidate
    ], "P2 zero-credit activity set drift")
  end

  def validate_sequence!(sequence)
    exact_keys!(sequence, %w[authorization_status proposed_additional_envelope tasks], "P2 recovery sequence")
    assert!(sequence["authorization_status"] == "PLANNED_NOT_AUTHORIZED", "P2 recovery plan invented authorization")
    assert!(sequence["proposed_additional_envelope"] == { "engineering_tasks" => 3, "engineering_hours" => 96, "calendar_days" => 24 }, "P2 recovery envelope recommendation drift")
    tasks = sequence.fetch("tasks")
    expected = [
      [1, "BENCHMARK_FOUNDATION", "P2_RECOVERY_BASELINE_ACCEPTED", false],
      [2, "PRODUCT_SELECTOR_IMPLEMENTATION", "P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED", true],
      [3, "FORMAL_HELD_EVALUATION", "P2_RECOVERY_FORMAL_HELD_MATRIX_COMPLETE", false]
    ]
    assert!(tasks.is_a?(Array) && tasks.length == expected.length, "P2 recovery task sequence drift")
    tasks.each_with_index do |task, index|
      exact_keys!(task, %w[product_mutation_allowed recommended_budget required_output role sequence target_milestone task_id], "P2 recovery task")
      assert!(task["task_id"].nil?, "P2 recovery plan may not preauthorize a Task ID")
      assert!([task["sequence"], task["role"], task["target_milestone"], task["product_mutation_allowed"]] == expected[index], "P2 recovery task ordering drift")
      assert!(task["recommended_budget"] == { "engineering_hours" => 32, "calendar_days" => 8 }, "P2 recovery task budget drift")
      assert!(task["required_output"].is_a?(String) && !task["required_output"].strip.empty?, "P2 recovery required output missing")
    end
  end

  def validate_controls!(controls)
    expected = {
      "governance_progress_credit" => 0,
      "task_non_pass_progress_credit" => 0,
      "max_candidate_generations_per_task" => 2,
      "max_same_task_repairs" => 1,
      "max_review_cycles" => 2,
      "first_review_freezes_complete_p0_p1_set" => true,
      "second_review_may_only_close_frozen_findings_or_reject_new_regression" => true,
      "governance_pre_worker_budget_percent_max" => 10,
      "worker_must_start_by_engineering_hour" => 1,
      "gate_relevance_required_for_blocker" => true,
      "blocker_gate_relevance_categories" => %w[EXIT_GATE_VALIDITY AUTHORITY_OR_EXTERNAL_EFFECT_SAFETY RESULT_INTEGRITY PRODUCT_CORRECTNESS],
      "product_task_requires_nonempty_product_diff" => true,
      "benchmark_foundation_precedes_product_implementation" => true,
      "product_implementation_precedes_formal_evaluation" => true,
      "formal_task_forbids_product_dataset_or_metric_mutation" => true,
      "next_sequence_requires_prior_milestone_accepted" => true,
      "rejected_lineage_reuse_allowed" => false,
      "successor_replacement_remediation_chain_allowed" => false,
      "next_p2_task_contract_requires_recovery_binding" => true,
      "validator_command" => "ruby scripts/validate-p2-recovery-anti-cycle.rb"
    }
    exact_keys!(controls, expected.keys, "P2 mechanical controls")
    assert!(controls == expected, "P2 mechanical anti-cycle controls drift")
  end

  def validate_current_control!(control)
    exact_keys!(control, %w[
      long_term_goal_must_remain_active new_task_creation_allowed next_action_owner
      next_eligible_action p2_must_remain_active_incomplete project_must_remain_active reason
    ], "P2 current control")
    expected = {
      "new_task_creation_allowed" => false,
      "reason" => "PHASE_ENVELOPE_EXHAUSTED_AWAITING_FOUNDER_EXPANSION",
      "next_action_owner" => "HUMAN_FOUNDER",
      "next_eligible_action" => "FOUNDER_RESERVED_DECISION",
      "long_term_goal_must_remain_active" => true,
      "project_must_remain_active" => true,
      "p2_must_remain_active_incomplete" => true
    }
    assert!(control == expected, "P2 current control drift")
  end

  def validate_truth!(truth, plan, plan_bytes, repo_root)
    project = truth.fetch("project")
    goal = truth.fetch("goal")
    route = truth.fetch("current_phase_route")
    envelope = truth.fetch("phase_execution_envelope")
    escalation = truth.fetch("founder_escalation_control")
    active = truth.fetch("active_work")
    claim = truth.fetch("claim_boundary")
    gate = truth.dig("strict_phase_gate_ledger", "phases", "P2")
    control = exact_keys!(truth.fetch("p2_recovery_control"), %w[
      accepted_milestones benchmark_source_admission_status capacity_slots
      current_delivery_percent envelope_expansion_decision governance_progress_credit
      next_eligible_action plan schema_version source_admission_decision status
      strict_gate_percent task_creation_allowed
    ], "Truth P2 recovery control")
    plan_identity = exact_keys!(control.fetch("plan"), %w[byte_length path sha256], "Truth P2 recovery plan identity")
    assert!(plan_identity == {
      "path" => "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml",
      "byte_length" => plan_bytes.bytesize,
      "sha256" => Digest::SHA256.hexdigest(plan_bytes)
    }, "Truth P2 recovery plan identity drift")
    assert!(project["current_phase"] == "P2" && project["p2_execution_status"] == "ACTIVE", "Truth P2 is not active")
    assert!(goal["control_plane_status_observed"] == "ACTIVE", "Long-term Goal is not active")
    assert!(gate["status"] == "INCOMPLETE" && gate.dig("required_items", "CONTEXT_BENCHMARK_BEATS_SIMPLE_RETRIEVAL_BASELINES", "status") == "MISSING", "P2 strict Exit Gate is not the expected incomplete gate")
    baseline_accepted = %w[
      CLEAN_ROOM_SLOT_V2_1_BENCHMARK_FOUNDATION_ACCEPTED_SLOT_V2_2_ELIGIBLE_NOT_ACTIVATED
      CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY
      CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TASK_ACTIVE
      CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_LOCKED
      CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_ACCEPTED_SLOT_V2_3_ELIGIBLE_NOT_ACTIVATED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V6_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V6_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V6_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED
    ].include?(control["status"])
    expected_delivery_percent = baseline_accepted ? 25 : 0
    expected_accepted_milestones = baseline_accepted ? ["P2_RECOVERY_BASELINE_ACCEPTED"] : []
    assert!(control["strict_gate_percent"] == 0 &&
            control["current_delivery_percent"] == expected_delivery_percent &&
            control["accepted_milestones"] == expected_accepted_milestones,
            "Truth P2 delivery milestone projection drift")
    assert!(control["governance_progress_credit"] == 0, "Truth credited governance as P2 progress")

    decision_identity = exact_keys!(control.fetch("envelope_expansion_decision"), %w[byte_length path sha256], "Truth recovery expansion decision identity")
    decision_path = File.expand_path(decision_identity.fetch("path"), repo_root)
    assert!(decision_path.start_with?(repo_root + File::SEPARATOR), "Truth recovery expansion decision escapes repository root")
    decision_stat = File.lstat(decision_path)
    assert!(decision_stat.file? && !decision_stat.symlink? && decision_stat.nlink == 1, "Truth recovery expansion decision must be a regular nlink1 file")
    decision_bytes = File.binread(decision_path)
    assert!(decision_identity["byte_length"] == decision_bytes.bytesize && decision_identity["sha256"] == Digest::SHA256.hexdigest(decision_bytes), "Truth recovery expansion decision identity drift")
    decision_claims = CurrentTaskAuthority.founder_phase_route_decision_claims(
      decision_bytes,
      decision_path: decision_identity.fetch("path"),
      root: repo_root
    )
    assert!(decision_claims["structured_decision_version"] == "1.4", "Truth recovery expansion decision is not v1.4")

    source_decision_identity = exact_keys!(control.fetch("source_admission_decision"), %w[byte_length path sha256], "Truth source-admission decision identity")
    source_decision_path = File.expand_path(source_decision_identity.fetch("path"), repo_root)
    assert!(source_decision_path.start_with?(repo_root + File::SEPARATOR), "Truth source-admission decision escapes repository root")
    source_decision_stat = File.lstat(source_decision_path)
    assert!(source_decision_stat.file? && !source_decision_stat.symlink? && source_decision_stat.nlink == 1, "Truth source-admission decision must be a regular nlink1 file")
    source_decision_bytes = File.binread(source_decision_path)
    assert!(source_decision_identity["byte_length"] == source_decision_bytes.bytesize && source_decision_identity["sha256"] == Digest::SHA256.hexdigest(source_decision_bytes), "Truth source-admission decision identity drift")
    source_decision = P2BenchmarkSourcePack.parse_json!(source_decision_bytes, "canonical source-admission decision")
    exact_keys!(source_decision, %w[
      artifact_root_contract authorization canonical_parent capability_lifecycle
      dependency_custody external_effects_after_acceptance formal_source_admission
      installation_verification installed_at_utc installed_source_pack operation_type
      progress recovery_plan rejected_lineage_recovered_or_reused reserved_trigger
      schema_version slot_unlock status
    ], "canonical source-admission decision")
    assert!(source_decision["schema_version"] == "p2-benchmark-source-admission-accepted/v1" && source_decision["status"] == "ACCEPTED_SOURCE_PACK_INSTALLED_SLOT_1_ELIGIBLE_NOT_ACTIVATED", "canonical source admission is not accepted and slot1 eligible")
    assert!(source_decision["authorization"] == P2BenchmarkSourcePack::AUTHORIZATION && source_decision["canonical_parent"] == P2BenchmarkSourcePack::CANONICAL_PARENT && source_decision["recovery_plan"] == {"path" => P2BenchmarkSourcePack::PLAN_IDENTITY["relative_path"], "byte_length" => P2BenchmarkSourcePack::PLAN_IDENTITY["byte_length"], "sha256" => P2BenchmarkSourcePack::PLAN_IDENTITY["sha256"]}, "canonical source-admission authority binding drift")
    assert!(source_decision["artifact_root_contract"] == {"artifact_id" => P2BenchmarkSourcePack::ARTIFACT_ID, "configuration_environment_variable" => P2BenchmarkSourcePack::ARTIFACT_ROOT_ENV, "all_artifact_paths_are_root_relative" => true, "absolute_path_embedded" => false}, "canonical source-pack root contract drift")
    expected_pack = {
      "manifest" => P2BenchmarkSourcePack::INSTALLED_MANIFEST_IDENTITY,
      "inventory" => P2BenchmarkSourcePack::INSTALLED_INVENTORY_IDENTITY,
      "seal" => P2BenchmarkSourcePack::INSTALLED_SEAL_IDENTITY
    }
    assert!(source_decision["installed_source_pack"] == expected_pack, "canonical installed source-pack identity drift")
    formal = source_decision.fetch("formal_source_admission")
    assert!(formal["status"] == "ACCEPTED" && formal["final_result"] == P2BenchmarkSourcePack::FINAL_RESULT_IDENTITY && formal["freeze"] == P2BenchmarkSourcePack::FREEZE_IDENTITY && formal.slice("repositories", "tasks", "source_archives", "dev_tasks", "held_tasks", "formal_processes", "reruns", "result_integrity_non_pass") == {"repositories" => 6, "tasks" => 12, "source_archives" => 24, "dev_tasks" => 8, "held_tasks" => 4, "formal_processes" => 24, "reruns" => 0, "result_integrity_non_pass" => 0}, "canonical formal source-admission facts drift")
    assert!(source_decision["dependency_custody"] == {"manifest" => P2BenchmarkSourcePack::MAVEN_MANIFEST_IDENTITY, "file_count" => 2_501, "inventory_json_sha256" => "ea4a01e3f5ba2ed70a4ccd1133b5866064e3f2c5a3885610e0cd59e6dcff0b68"}, "canonical dependency custody drift")
    assert!(source_decision["capability_lifecycle"] == {"status" => "ENDED_ON_SOURCE_ADMISSION_ACCEPTED", "further_network_authorized" => false, "ordinary_route_non_pass_consumed_capability" => false}, "source-admission network capability did not end")
    assert!(source_decision["slot_unlock"] == {"capacity_slot_id" => "P2_RECOVERY_CAPACITY_SLOT_1", "milestone_id" => "P2_RECOVERY_BASELINE_ACCEPTED", "unlock_requirement" => "BENCHMARK_SOURCE_PACK_ADMISSION_ACCEPTED", "unlock_status" => "SATISFIED", "task_id" => nil, "task_activation_status" => "ELIGIBLE_NOT_ACTIVATED"}, "source admission did not unlock only slot1")
    assert!(source_decision["progress"] == {"p2_strict_percent" => 0, "p2_delivery_percent" => 0, "accepted_milestones" => [], "governance_progress_credit" => 0, "source_admission_progress_credit" => 0, "p3_status" => "HOLD"} && source_decision["rejected_lineage_recovered_or_reused"] == false, "source admission created false progress or reused rejected lineage")
    assert!(source_decision.fetch("external_effects_after_acceptance").values.none?, "source admission retained an external effect")

    clean_room_resequenced = decision_claims["route_id"] ==
      "P2_CLEAN_ROOM_RECOVERY_RESEQUENCING_AND_MINIMAL_ENVELOPE_EXPANSION_ROUTE_V1"
    limits = {
      "engineering_tasks" => decision_claims.fetch("max_engineering_tasks"),
      "engineering_hours" => decision_claims.fetch("max_engineering_hours"),
      "calendar_days" => decision_claims.fetch("max_calendar_days")
    }
    consumed = decision_claims.fetch("prior_consumed_envelope").fetch("consumed")
    terminal_or_accepted_slot_1 = %w[
      SLOT_1_BENCHMARK_FOUNDATION_TASK_TERMINAL_NON_PASS
      CLEAN_ROOM_SLOT_V2_1_BENCHMARK_FOUNDATION_TASK_TERMINAL_NON_PASS
      CLEAN_ROOM_SLOT_V2_1_BENCHMARK_FOUNDATION_ACCEPTED_SLOT_V2_2_ELIGIBLE_NOT_ACTIVATED
      CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY
      CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TASK_ACTIVE
      CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_LOCKED
      CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_ACCEPTED_SLOT_V2_3_ELIGIBLE_NOT_ACTIVATED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
    ].include?(control["status"])
    expected_consumed = consumed.dup
    if terminal_or_accepted_slot_1
      consumed_slots = control["status"] ==
        "CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_LOCKED" ? 2 : 1
      expected_consumed = {
        "engineering_tasks" => consumed["engineering_tasks"] + consumed_slots,
        "engineering_hours" => consumed["engineering_hours"] + (32 * consumed_slots),
        "calendar_days" => consumed["calendar_days"] + (8 * consumed_slots)
      }
    end
    assert!(envelope["limits"].slice(*limits.keys) == limits && envelope["consumed"] == expected_consumed,
            "Truth P2 recovery envelope fixed accounting drift")
    source_route_ref = envelope.dig("authority_basis", "source_route_ref")
    source_route = truth[source_route_ref]
    assert!(source_route.is_a?(Hash) && source_route["route_id"] == decision_claims["route_id"] &&
            envelope.dig("authority_basis", "source_route_id") == decision_claims["route_id"] &&
            envelope.dig("authority_basis", "source_decision") == decision_identity,
            "Truth P2 recovery envelope authority binding drift")
    assert!(control["schema_version"] == "p2-recovery-control/v1" &&
            control["benchmark_source_admission_status"] == "ACCEPTED_SOURCE_PACK_INSTALLED_SLOT_1_ELIGIBLE",
            "Truth P2 recovery source-admission projection drift")
    expected_slots = decision_claims.fetch("capacity_slots").map do |slot|
      slot.slice("slot", "capacity_slot_id", "task_id", "milestone_id", "unlock_requirement", "engineering_hours", "calendar_days")
    end
    task_id = clean_room_resequenced ?
      "AIOS-P2-069_CLEAN_ROOM_RECOVERY_BENCHMARK_FOUNDATION" :
      "AIOS-P2-068_RECOVERY_BENCHMARK_FOUNDATION"
    slot_1_id = decision_claims.fetch("capacity_slots").first.fetch("capacity_slot_id")
    slot_2_task_id = "AIOS-P2-070_PRODUCT_JAVA_MAINTENANCE_CONTEXT_SELECTOR_DEV"
    slot_2_id = decision_claims.fetch("capacity_slots").fetch(1).fetch("capacity_slot_id")
    terminal_locked = %w[
      CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_LOCKED
      CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
      CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
    ].include?(control["status"])
    if terminal_locked
      assert!(escalation["disposition"] == "FOUNDER_DECISION_REQUIRED" &&
              escalation.dig("reserved_trigger", "category") ==
                "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE" &&
              escalation["founder_decision_required"] == true &&
              escalation["next_action_owner"] == "HUMAN_FOUNDER",
              "Truth locked Slot V2_3 must preserve the exact Founder reserved decision")
    else
      assert!(escalation["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
              escalation.dig("reserved_trigger", "category") == "NONE" &&
              escalation["founder_decision_required"] == false &&
              escalation["next_action_owner"] == "MASTER_CEO_AGENT",
              "Truth Founder escalation must preserve autonomous P2 continuation")
    end
    assert!(project["phase_execution_status"] ==
              (terminal_locked ? "STOPPED_AT_FOUNDER_RESERVED_DECISION" : "ACTIVE") &&
            claim["p2_project_status"] == "ACTIVE" &&
            claim["long_term_goal_status"] == "ACTIVE",
            "Truth recovery lifecycle projection drift")

    case control["status"]
    when "CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V6_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED"
      product_path_closure = control["status"].include?("SLOT_V6_1")
      stream_lifecycle = control["status"].include?("SLOT_V5_1")
      next_action = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
      expected_remaining = {
        "engineering_tasks" => 2,
        "engineering_hours" => 64,
        "calendar_days" => 16
      }
      expected_token = if product_path_closure
                         "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V4"
                       elsif stream_lifecycle
                         "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V3"
                       else
                         "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V2"
                       end
      expected_capacity_ids = if product_path_closure
                                %w[P2_RECOVERY_CAPACITY_SLOT_V6_1 P2_RECOVERY_CAPACITY_SLOT_V2_3]
                              elsif stream_lifecycle
                                %w[P2_RECOVERY_CAPACITY_SLOT_V5_1 P2_RECOVERY_CAPACITY_SLOT_V2_3]
                              else
                                %w[P2_RECOVERY_CAPACITY_SLOT_V4_1 P2_RECOVERY_CAPACITY_SLOT_V2_3]
                              end
      assert!(decision_claims["authorization_token"] == expected_token &&
              decision_claims["capacity_slots"].map { |slot| slot["capacity_slot_id"] } == expected_capacity_ids,
              "Truth Product Selector recovery decision or re-locked HELD identity drift")
      expected_consumed = if product_path_closure
                            { "engineering_tasks" => 18, "engineering_hours" => 528, "calendar_days" => 132 }
                          elsif stream_lifecycle
                            { "engineering_tasks" => 17, "engineering_hours" => 496, "calendar_days" => 124 }
                          else
                            { "engineering_tasks" => 16, "engineering_hours" => 464, "calendar_days" => 116 }
                          end
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
              envelope["reserved"].nil? && envelope["remaining"] == expected_remaining &&
              envelope["consumed"] == expected_consumed,
              "Truth eligible Product Selector recovery envelope drift")
      expected_preceding_route = if product_path_closure
                                   "historical_p2_073_phase_route"
                                 elsif stream_lifecycle
                                   "historical_p2_072_phase_route"
                                 else
                                   "historical_p2_071_phase_route"
                                 end
      assert!(route["schema_version"] == "phase-delegated-continuation-hold/v1" &&
              route["status"] == "AUTHORIZED_READY" &&
              route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              route["scheduling_status"] == "MASTER_SELECTING_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
              route["historical_terminal_route_ref"] == expected_preceding_route &&
              route["next_eligible_action"] == next_action,
              "Truth eligible Product Selector recovery continuation Route drift")
      assert!(active["current_task"] == "NONE" &&
              active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_CONTINUATION_READY" &&
              active["execution_nonce_status"] == "NOT_ALLOCATED" &&
              active["next_eligible_action"] == next_action &&
              goal["current_task_authority"] == "NONE",
              "Truth eligible Product Selector recovery active-work drift")
      assert!(control["task_creation_allowed"] == true &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots &&
              control["capacity_slots"].all? { |slot| slot["task_id"].nil? },
              "Truth eligible Product Selector recovery capacity projection drift")
      expected_progress = if product_path_closure
                            "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_NEW_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_V6_1_ELIGIBLE_FORMAL_HELD_SLOT_V2_3_RELOCKED"
                          elsif stream_lifecycle
                            "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_NEW_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_V5_1_ELIGIBLE_FORMAL_HELD_SLOT_V2_3_RELOCKED"
                          else
                            "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_NEW_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_V4_1_ELIGIBLE_FORMAL_HELD_SLOT_V2_3_RELOCKED"
                          end
      assert!(project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] == expected_progress,
              "Truth eligible Product Selector recovery claim projection drift")
    when "CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V6_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V6_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED"
      product_path_closure = control["status"].include?("SLOT_V6_1")
      stream_lifecycle = control["status"].include?("SLOT_V5_1")
      ready = control["status"].include?("RESERVED_READY")
      task_id_v4 = if product_path_closure
                     "AIOS-P2-074_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_DEV"
                   elsif stream_lifecycle
                     "AIOS-P2-073_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_SANDBOX_STREAM_LIFECYCLE_DEV"
                   else
                     "AIOS-P2-072_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_EXECUTION_INTEGRITY_DEV"
                   end
      capacity_slot_id = if product_path_closure
                           "P2_RECOVERY_CAPACITY_SLOT_V6_1"
                         elsif stream_lifecycle
                           "P2_RECOVERY_CAPACITY_SLOT_V5_1"
                         else
                           "P2_RECOVERY_CAPACITY_SLOT_V4_1"
                         end
      preceding_route_ref = if product_path_closure
                              "historical_p2_073_phase_route"
                            elsif stream_lifecycle
                              "historical_p2_072_phase_route"
                            else
                              "historical_p2_071_phase_route"
                            end
      task_status = ready ? "ELIGIBLE_NOT_ACTIVATED" : "ACTIVE"
      next_action = ready ? "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" : "COMPLETE_CURRENT_TASK_GATE"
      expected_resource_state = ready ? "NOT_CREATED_PHASE_DELEGATED_TASK_READY" : "ACTIVE_UNIQUE_PHASE_DELEGATED"
      expected_route_status = ready ? "AUTHORIZED_READY" : "ACTIVE"
      expected_route_execution = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE"
      expected_scheduling = ready ? "READY_FOR_MASTER_ACTIVATION" : "ACTIVE_PHASE_DELEGATED_TASK"
      expected_project_route = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE_PHASE_DELEGATED_TASK"
      remaining = { "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8 }
      expected_slots[0]["task_id"] = task_id_v4
      selected = route.fetch("selected_task")
      reservation = envelope.fetch("reserved")
      expected_consumed = if product_path_closure
                            { "engineering_tasks" => 18, "engineering_hours" => 528, "calendar_days" => 132 }
                          elsif stream_lifecycle
                            { "engineering_tasks" => 17, "engineering_hours" => 496, "calendar_days" => 124 }
                          else
                            { "engineering_tasks" => 16, "engineering_hours" => 464, "calendar_days" => 116 }
                          end
      assert!(envelope["status"] == "TASK_CAPACITY_RESERVED" &&
              envelope["consumed"] == expected_consumed &&
              envelope["remaining"] == remaining,
              "Truth reserved clean-room Product Selector slot envelope drift")
      assert!(selected["task_id"] == task_id_v4 && selected["status"] == task_status &&
              selected["capacity_source_task_id"] == capacity_slot_id,
              "Truth reserved clean-room Product Selector Task projection drift")
      assert!(reservation["task_id"] == task_id_v4 && reservation["route_id"] == route["route_id"] &&
              reservation["status"] == task_status &&
              reservation["capacity_source_task_id"] == capacity_slot_id &&
              reservation["contract"] == selected["contract"] &&
              reservation["budget"] == { "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8 } &&
              (ready ? reservation["authority"].nil? : reservation["authority"] == active["authority_record"]),
              "Truth reserved clean-room Product Selector authority or budget drift")
      assert!(route["status"] == expected_route_status &&
              route["execution_status"] == expected_route_execution &&
              route["scheduling_status"] == expected_scheduling &&
              route["preceding_terminal_route_ref"] == preceding_route_ref &&
              route["next_eligible_action"] == next_action,
              "Truth reserved clean-room Product Selector Route lifecycle drift")
      assert!(active["current_task"] == (ready ? "NONE" : task_id_v4) &&
              active["task_resource_state"] == expected_resource_state &&
              goal["current_task_authority"] == (ready ? "NONE" : task_id_v4),
              "Truth reserved clean-room Product Selector active-work lifecycle drift")
      assert!(control["task_creation_allowed"] == false &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots,
              "Truth reserved clean-room Product Selector capacity projection drift")
      slot_label = product_path_closure ? "SLOT_V6_1" : (stream_lifecycle ? "SLOT_V5_1" : "SLOT_V4_1")
      assert!(project["current_route_execution_status"] == expected_project_route &&
              claim["p2_phase_envelope_status"] == "TASK_CAPACITY_RESERVED" &&
              claim["current_task"] == (ready ? "NONE" : task_id_v4) &&
              claim["real_engineering_progress"] ==
                "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_#{slot_label}_PRODUCT_SELECTOR_DEV_TASK_#{ready ? 'READY' : 'ACTIVE'}_SLOT_V2_3_RELOCKED",
              "Truth reserved clean-room Product Selector claim projection drift")
    when "CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED"
      stream_lifecycle = control["status"].include?("SLOT_V5_1")
      task_id = stream_lifecycle ?
        "AIOS-P2-073_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_SANDBOX_STREAM_LIFECYCLE_DEV" :
        "AIOS-P2-072_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_EXECUTION_INTEGRITY_DEV"
      terminal_status = stream_lifecycle ?
        "TERMINAL_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AUTHORITY_AND_EVIDENCE_NON_PASS" :
        "TERMINAL_PRODUCT_SELECTOR_DEV_REPLAY_EXECUTION_INTEGRITY_NON_PASS"
      terminal_receipt = if stream_lifecycle
                           {
                             "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p2-product-selector-sandbox-stream-lifecycle-recovery-20260817/task-p2-073/terminal/P2_073_TERMINAL_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AUTHORITY_AND_EVIDENCE_NON_PASS_RECEIPT_V1.json",
                             "byte_length" => 5267,
                             "sha256" => "570eaa011c79159f172667d592e023540f1db4128e15b3e408513d217202eae8"
                           }
                         else
                           {
                             "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p2-product-selector-execution-integrity-recovery-20260817/task-p2-072/terminal/P2_072_TERMINAL_PRODUCT_SELECTOR_DEV_REPLAY_EXECUTION_INTEGRITY_NON_PASS_RECEIPT_V1.json",
                             "byte_length" => 6064,
                             "sha256" => "a14509a6e2ff8ce82962f6f4205adef7f1e6fde956f93d9c9331c2276e4ecf05"
                           }
                         end
      historical_ref = stream_lifecycle ? "historical_p2_073_phase_route" : "historical_p2_072_phase_route"
      expected_consumed = stream_lifecycle ?
        { "engineering_tasks" => 18, "engineering_hours" => 528, "calendar_days" => 132 } :
        { "engineering_tasks" => 17, "engineering_hours" => 496, "calendar_days" => 124 }
      expected_progress = stream_lifecycle ?
        "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_P2_073_TERMINAL_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AUTHORITY_AND_EVIDENCE_NON_PASS_SLOT_V2_3_LOCKED" :
        "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_P2_072_TERMINAL_PRODUCT_SELECTOR_DEV_REPLAY_EXECUTION_INTEGRITY_NON_PASS_SLOT_V2_3_LOCKED"
      terminal_slot_label = stream_lifecycle ? "V5_1" : "V4_1"
      expected_slots[0]["task_id"] = task_id
      expected_remaining = {
        "engineering_tasks" => 1,
        "engineering_hours" => 32,
        "calendar_days" => 8
      }
      historical = truth.fetch(historical_ref)
      ledger_entry = envelope.fetch("task_ledger").find { |entry| entry["task_id"] == task_id }
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
              envelope["reserved"].nil? &&
              envelope["remaining"] == expected_remaining &&
              envelope["consumed"] == expected_consumed,
              "Truth terminal clean-room Slot #{terminal_slot_label} envelope drift")
      assert!(route["schema_version"] == "founder-reserved-decision-hold/v1" &&
              route["status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              route["execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              route["scheduling_status"] == "STOPPED_AT_FOUNDER_RESERVED_DECISION" &&
              route["historical_terminal_route_ref"] == historical_ref &&
              route["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
              "Truth terminal clean-room Slot #{terminal_slot_label} Founder hold drift")
      assert!(historical["status"] == terminal_status &&
              historical["execution_status"] == terminal_status &&
              historical.dig("selected_task", "task_id") == task_id &&
              historical.dig("selected_task", "status") == terminal_status &&
              historical.dig("selected_task", "rejected_candidate", "integrated") == false &&
              historical.dig("selected_task", "outcome_receipt") == terminal_receipt,
              "Truth terminal clean-room Slot #{terminal_slot_label} historical Route drift")
      assert!(ledger_entry && ledger_entry["status"] == terminal_status &&
              ledger_entry["outcome_receipt"] == terminal_receipt,
              "Truth terminal clean-room Slot #{terminal_slot_label} ledger drift")
      assert!(active["current_task"] == "NONE" &&
              active["task_resource_state"] == "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD" &&
              active["next_eligible_action"] == "FOUNDER_RESERVED_DECISION" &&
              goal["current_task_authority"] == "NONE",
              "Truth terminal clean-room Slot #{terminal_slot_label} active-work drift")
      assert!(control["task_creation_allowed"] == false &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == "FOUNDER_RESERVED_DECISION" &&
              control["capacity_slots"] == expected_slots,
              "Truth terminal clean-room Slot #{terminal_slot_label} capacity projection drift")
      assert!(project["current_route_execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] == expected_progress,
              "Truth terminal clean-room Slot #{terminal_slot_label} claim projection drift")
    when "CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_ELIGIBLE_NOT_ACTIVATED_SLOT_V2_3_RELOCKED"
      next_action = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
      expected_remaining = {
        "engineering_tasks" => 2,
        "engineering_hours" => 64,
        "calendar_days" => 16
      }
      assert!(decision_claims["authorization_token"] ==
                "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_RECOVERY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V1" &&
              decision_claims["capacity_slots"].map { |slot| slot["capacity_slot_id"] } ==
                %w[P2_RECOVERY_CAPACITY_SLOT_V3_1 P2_RECOVERY_CAPACITY_SLOT_V2_3],
              "Truth Product Selector recovery decision or re-locked HELD identity drift")
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
              envelope["reserved"].nil? && envelope["remaining"] == expected_remaining &&
              envelope["consumed"] == {
                "engineering_tasks" => 15,
                "engineering_hours" => 432,
                "calendar_days" => 108
              }, "Truth eligible Product Selector recovery envelope drift")
      assert!(route["schema_version"] == "phase-delegated-continuation-hold/v1" &&
              route["status"] == "AUTHORIZED_READY" &&
              route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              route["scheduling_status"] == "MASTER_SELECTING_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
              route["historical_terminal_route_ref"] == "historical_p2_070_phase_route" &&
              route["next_eligible_action"] == next_action,
              "Truth eligible Product Selector recovery continuation Route drift")
      assert!(active["current_task"] == "NONE" &&
              active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_CONTINUATION_READY" &&
              active["next_eligible_action"] == next_action &&
              goal["current_task_authority"] == "NONE",
              "Truth eligible Product Selector recovery active-work drift")
      assert!(control["task_creation_allowed"] == true &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots &&
              control["capacity_slots"].all? { |slot| slot["task_id"].nil? },
              "Truth eligible Product Selector recovery capacity projection drift")
      assert!(project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] ==
                "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_NEW_PRODUCT_SELECTOR_DEV_RECOVERY_SLOT_V3_1_ELIGIBLE_FORMAL_HELD_SLOT_V2_3_RELOCKED",
              "Truth eligible Product Selector recovery claim projection drift")
    when "CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY_SLOT_V2_3_RELOCKED",
         "CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TASK_ACTIVE_SLOT_V2_3_RELOCKED"
      ready = control["status"].include?("RESERVED_READY")
      task_id_v3 = "AIOS-P2-071_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_DEV"
      task_status = ready ? "ELIGIBLE_NOT_ACTIVATED" : "ACTIVE"
      next_action = ready ? "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" : "COMPLETE_CURRENT_TASK_GATE"
      expected_resource_state = ready ? "NOT_CREATED_PHASE_DELEGATED_TASK_READY" : "ACTIVE_UNIQUE_PHASE_DELEGATED"
      expected_route_status = ready ? "AUTHORIZED_READY" : "ACTIVE"
      expected_route_execution = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE"
      expected_scheduling = ready ? "READY_FOR_MASTER_ACTIVATION" : "ACTIVE_PHASE_DELEGATED_TASK"
      expected_project_route = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE_PHASE_DELEGATED_TASK"
      remaining = { "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8 }
      expected_slots[0]["task_id"] = task_id_v3
      selected = route.fetch("selected_task")
      reservation = envelope.fetch("reserved")
      assert!(envelope["status"] == "TASK_CAPACITY_RESERVED" &&
              envelope["consumed"] == { "engineering_tasks" => 15, "engineering_hours" => 432, "calendar_days" => 108 } &&
              envelope["remaining"] == remaining,
              "Truth reserved clean-room Slot V3_1 envelope drift")
      assert!(selected["task_id"] == task_id_v3 && selected["status"] == task_status &&
              selected["capacity_source_task_id"] == "P2_RECOVERY_CAPACITY_SLOT_V3_1",
              "Truth reserved clean-room Slot V3_1 Task projection drift")
      assert!(reservation["task_id"] == task_id_v3 && reservation["route_id"] == route["route_id"] &&
              reservation["status"] == task_status &&
              reservation["capacity_source_task_id"] == "P2_RECOVERY_CAPACITY_SLOT_V3_1" &&
              reservation["contract"] == selected["contract"] &&
              reservation["budget"] == { "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8 } &&
              (ready ? reservation["authority"].nil? : reservation["authority"] == active["authority_record"]),
              "Truth reserved clean-room Slot V3_1 authority or budget drift")
      assert!(route["status"] == expected_route_status &&
              route["execution_status"] == expected_route_execution &&
              route["scheduling_status"] == expected_scheduling &&
              route["preceding_terminal_route_ref"] == "historical_p2_070_phase_route" &&
              route["next_eligible_action"] == next_action,
              "Truth reserved clean-room Slot V3_1 Route lifecycle drift")
      assert!(active["current_task"] == (ready ? "NONE" : task_id_v3) &&
              active["task_resource_state"] == expected_resource_state &&
              goal["current_task_authority"] == (ready ? "NONE" : task_id_v3),
              "Truth reserved clean-room Slot V3_1 active-work lifecycle drift")
      assert!(control["task_creation_allowed"] == false &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots,
              "Truth reserved clean-room Slot V3_1 capacity projection drift")
      assert!(project["current_route_execution_status"] == expected_project_route &&
              claim["p2_phase_envelope_status"] == "TASK_CAPACITY_RESERVED" &&
              claim["current_task"] == (ready ? "NONE" : task_id_v3) &&
              claim["real_engineering_progress"] ==
                "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TASK_#{ready ? 'READY' : 'ACTIVE'}_SLOT_V2_3_RELOCKED",
              "Truth reserved clean-room Slot V3_1 claim projection drift")
    when "CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED"
      task_id_v3 = "AIOS-P2-071_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_DEV"
      expected_slots[0]["task_id"] = task_id_v3
      expected_remaining = {
        "engineering_tasks" => 1,
        "engineering_hours" => 32,
        "calendar_days" => 8
      }
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
              envelope["reserved"].nil? &&
              envelope["remaining"] == expected_remaining &&
              envelope["consumed"] == {
                "engineering_tasks" => 16,
                "engineering_hours" => 464,
                "calendar_days" => 116
              }, "Truth terminal clean-room Slot V3_1 envelope drift")
      assert!(route["schema_version"] == "founder-reserved-decision-hold/v1" &&
              route["status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              route["execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              route["scheduling_status"] == "STOPPED_AT_FOUNDER_RESERVED_DECISION" &&
              route["historical_terminal_route_ref"] == "historical_p2_071_phase_route" &&
              route["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
              "Truth terminal clean-room Slot V3_1 Founder hold drift")
      historical = truth.fetch("historical_p2_071_phase_route")
      assert!(historical["status"] ==
                "TERMINAL_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_AND_AUTHORITY_NON_PASS" &&
              historical.dig("selected_task", "task_id") == task_id_v3 &&
              historical.dig("selected_task", "status") == historical["status"] &&
              historical.dig("selected_task", "rejected_candidate", "integrated") == false,
              "Truth terminal clean-room Slot V3_1 historical Route drift")
      assert!(active["current_task"] == "NONE" &&
              active["task_resource_state"] == "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD" &&
              active["next_eligible_action"] == "FOUNDER_RESERVED_DECISION" &&
              goal["current_task_authority"] == "NONE",
              "Truth terminal clean-room Slot V3_1 active-work drift")
      assert!(control["task_creation_allowed"] == false &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == "FOUNDER_RESERVED_DECISION" &&
              control["capacity_slots"] == expected_slots,
              "Truth terminal clean-room Slot V3_1 capacity projection drift")
      assert!(project["current_route_execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] ==
                "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_P2_071_TERMINAL_EXECUTION_INTEGRITY_AND_AUTHORITY_NON_PASS_SLOT_V2_3_LOCKED",
              "Truth terminal clean-room Slot V3_1 claim projection drift")
    when "BENCHMARK_SOURCE_ADMISSION_ACCEPTED_SLOT_1_ELIGIBLE_NOT_ACTIVATED",
         "CLEAN_ROOM_RESEQUENCE_DECISION_ACCEPTED_SLOT_V2_1_ELIGIBLE_NOT_ACTIVATED"
      clean_room_state = control["status"].start_with?("CLEAN_ROOM_")
      assert!(clean_room_state == clean_room_resequenced,
              "Truth eligible Slot 1 decision generation drift")
      next_action = clean_room_state ?
        "MASTER_ACTIVATE_P2_CLEAN_ROOM_CAPACITY_SLOT_V2_1_BENCHMARK_FOUNDATION" :
        "MASTER_ACTIVATE_P2_RECOVERY_CAPACITY_SLOT_1_BENCHMARK_FOUNDATION"
      remaining = { "engineering_tasks" => 3, "engineering_hours" => 96, "calendar_days" => 24 }
      scheduling_status = clean_room_state ?
        "MASTER_ACTIVATING_P2_CLEAN_ROOM_CAPACITY_SLOT_V2_1" :
        "MASTER_ACTIVATING_P2_RECOVERY_CAPACITY_SLOT_1"
      resource_state = clean_room_state ?
        "NOT_CREATED_CLEAN_ROOM_RESEQUENCE_SLOT_V2_1_ELIGIBLE" :
        "NOT_CREATED_SOURCE_ADMISSION_ACCEPTED_SLOT_1_ELIGIBLE"
      progress_claim = clean_room_state ?
        "P1_COMPLETE_P2_ZERO_ACCEPTED_CAPABILITY_CLEAN_ROOM_RESEQUENCE_SLOT_V2_1_ELIGIBLE_TASK_NONE_DELIVERY_ZERO" :
        "P1_COMPLETE_P2_ZERO_ACCEPTED_CAPABILITY_BENCHMARK_SOURCE_ADMISSION_ACCEPTED_SLOT_1_ELIGIBLE_TASK_NONE_DELIVERY_ZERO"
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" && envelope["reserved"].nil? &&
              envelope["remaining"] == remaining,
              "Truth eligible Slot 1 envelope drift")
      assert!(route["status"] == "AUTHORIZED_READY" &&
              route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              route["scheduling_status"] == scheduling_status &&
              route["next_eligible_action"] == next_action,
              "Truth current route is not delegated Slot 1 selection ready")
      assert!(active["current_task"] == "NONE" && goal["current_task_authority"] == "NONE" &&
              active["task_resource_state"] == resource_state,
              "Truth eligible Slot 1 active-work projection drift")
      assert!(control["task_creation_allowed"] == true && control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots &&
              control["capacity_slots"].all? { |slot| slot["task_id"].nil? },
              "Truth eligible Slot 1 capacity projection drift")
      assert!(project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] == progress_claim,
              "Truth eligible Slot 1 claim projection drift")
    when "SLOT_1_BENCHMARK_FOUNDATION_TASK_RESERVED_READY", "SLOT_1_BENCHMARK_FOUNDATION_TASK_ACTIVE",
         "CLEAN_ROOM_SLOT_V2_1_BENCHMARK_FOUNDATION_TASK_RESERVED_READY",
         "CLEAN_ROOM_SLOT_V2_1_BENCHMARK_FOUNDATION_TASK_ACTIVE"
      clean_room_state = control["status"].start_with?("CLEAN_ROOM_")
      assert!(clean_room_state == clean_room_resequenced,
              "Truth reserved Slot 1 decision generation drift")
      ready = control["status"].end_with?("READY")
      task_status = ready ? "ELIGIBLE_NOT_ACTIVATED" : "ACTIVE"
      next_action = ready ? "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" : "COMPLETE_CURRENT_TASK_GATE"
      expected_resource_state = ready ? "NOT_CREATED_PHASE_DELEGATED_TASK_READY" : "ACTIVE_UNIQUE_PHASE_DELEGATED"
      expected_route_status = ready ? "AUTHORIZED_READY" : "ACTIVE"
      expected_route_execution = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE"
      expected_scheduling = ready ? "READY_FOR_MASTER_ACTIVATION" : "ACTIVE_PHASE_DELEGATED_TASK"
      expected_project_route = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE_PHASE_DELEGATED_TASK"
      remaining = { "engineering_tasks" => 2, "engineering_hours" => 64, "calendar_days" => 16 }
      expected_slots[0]["task_id"] = task_id
      selected = route.fetch("selected_task")
      reservation = envelope.fetch("reserved")
      assert!(envelope["status"] == "TASK_CAPACITY_RESERVED" && envelope["remaining"] == remaining,
              "Truth reserved Slot 1 envelope drift")
      assert!(selected["task_id"] == task_id && selected["status"] == task_status &&
              selected["capacity_source_task_id"] == slot_1_id,
              "Truth reserved Slot 1 Task projection drift")
      assert!(reservation["task_id"] == task_id && reservation["route_id"] == route["route_id"] &&
              reservation["status"] == task_status &&
              reservation["capacity_source_task_id"] == slot_1_id &&
              reservation["contract"] == selected["contract"] &&
              reservation["budget"] == { "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8 } &&
              (ready ? reservation["authority"].nil? : reservation["authority"] == active["authority_record"]),
              "Truth reserved Slot 1 authority or budget drift")
      assert!(route["status"] == expected_route_status && route["execution_status"] == expected_route_execution &&
              route["scheduling_status"] == expected_scheduling && route["next_eligible_action"] == next_action,
              "Truth reserved Slot 1 Route lifecycle drift")
      assert!(active["current_task"] == (ready ? "NONE" : task_id) &&
              active["task_resource_state"] == expected_resource_state &&
              goal["current_task_authority"] == (ready ? "NONE" : task_id),
              "Truth reserved Slot 1 active-work lifecycle drift")
      assert!(control["task_creation_allowed"] == false && control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots,
              "Truth reserved Slot 1 capacity projection drift")
      assert!(project["current_route_execution_status"] == expected_project_route &&
              claim["p2_phase_envelope_status"] == "TASK_CAPACITY_RESERVED" &&
              claim["current_task"] == (ready ? "NONE" : task_id) &&
              claim["real_engineering_progress"] == if clean_room_state
                "P1_COMPLETE_P2_ZERO_ACCEPTED_CAPABILITY_CLEAN_ROOM_SLOT_V2_1_#{ready ? 'TASK_READY' : 'TASK_ACTIVE'}_DELIVERY_ZERO"
              else
                "P1_COMPLETE_P2_ZERO_ACCEPTED_CAPABILITY_BENCHMARK_SOURCE_ADMISSION_ACCEPTED_SLOT_1_#{ready ? 'TASK_READY' : 'TASK_ACTIVE'}_DELIVERY_ZERO"
              end,
              "Truth reserved Slot 1 claim projection drift")
    when "CLEAN_ROOM_SLOT_V2_1_BENCHMARK_FOUNDATION_ACCEPTED_SLOT_V2_2_ELIGIBLE_NOT_ACTIVATED"
      accepted_status = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
      next_action = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
      remaining = { "engineering_tasks" => 2, "engineering_hours" => 64, "calendar_days" => 16 }
      expected_slots[0]["task_id"] = task_id
      historical = truth.fetch("historical_p2_069_phase_route")
      accepted_receipt = {
        "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p2-clean-room-recovery-benchmark-foundation-20260817/task-p2-069/canonical-integration/P2_069_CANONICAL_INTEGRATION_AND_ACCEPTED_OUTCOME_RECEIPT_V1.json",
        "byte_length" => 2130,
        "sha256" => "78d5ad1af278f5e112c52021a1c8b81da330a14171d238992083a2ab9ae90747"
      }
      ledger_entry = envelope.fetch("task_ledger").find { |entry| entry["task_id"] == task_id }
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" && envelope["reserved"].nil? &&
              envelope["remaining"] == remaining &&
              envelope["consumed"] == { "engineering_tasks" => 14, "engineering_hours" => 400, "calendar_days" => 100 },
              "Truth accepted clean-room Slot V2_1 envelope drift")
      assert!(historical["status"] == accepted_status &&
              historical["execution_status"] == accepted_status &&
              historical.dig("selected_task", "task_id") == task_id &&
              historical.dig("selected_task", "status") == accepted_status &&
              historical["task_gate_receipt"] == accepted_receipt,
              "Truth accepted clean-room Slot V2_1 historical Route drift")
      assert!(ledger_entry && ledger_entry["status"] == accepted_status &&
              ledger_entry["outcome_receipt"] == accepted_receipt,
              "Truth accepted clean-room Slot V2_1 ledger drift")
      assert!(route["schema_version"] == "phase-delegated-continuation-hold/v1" &&
              route["status"] == "AUTHORIZED_READY" &&
              route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              route["scheduling_status"] == "MASTER_SELECTING_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
              route["historical_terminal_route_ref"] == "historical_p2_069_phase_route" &&
              route["next_eligible_action"] == next_action,
              "Truth accepted clean-room Slot V2_1 continuation Route drift")
      assert!(active["current_task"] == "NONE" && goal["current_task_authority"] == "NONE" &&
              active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_CONTINUATION_READY",
              "Truth accepted clean-room Slot V2_1 active-work drift")
      assert!(control["task_creation_allowed"] == true &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots,
              "Truth accepted clean-room Slot V2_1 recovery control drift")
      assert!(project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] ==
                "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_SLOT_V2_2_ELIGIBLE_TASK_NONE",
              "Truth accepted clean-room Slot V2_1 claim projection drift")
    when "CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TASK_RESERVED_READY",
         "CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TASK_ACTIVE"
      ready = control["status"].end_with?("READY")
      task_status = ready ? "ELIGIBLE_NOT_ACTIVATED" : "ACTIVE"
      next_action = ready ? "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" : "COMPLETE_CURRENT_TASK_GATE"
      expected_resource_state = ready ? "NOT_CREATED_PHASE_DELEGATED_TASK_READY" : "ACTIVE_UNIQUE_PHASE_DELEGATED"
      expected_route_status = ready ? "AUTHORIZED_READY" : "ACTIVE"
      expected_route_execution = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE"
      expected_scheduling = ready ? "READY_FOR_MASTER_ACTIVATION" : "ACTIVE_PHASE_DELEGATED_TASK"
      expected_project_route = ready ? "PHASE_DELEGATED_TASK_READY" : "ACTIVE_PHASE_DELEGATED_TASK"
      remaining = { "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8 }
      expected_slots[0]["task_id"] = task_id
      expected_slots[1]["task_id"] = slot_2_task_id
      selected = route.fetch("selected_task")
      reservation = envelope.fetch("reserved")
      assert!(envelope["status"] == "TASK_CAPACITY_RESERVED" &&
              envelope["consumed"] == { "engineering_tasks" => 14, "engineering_hours" => 400, "calendar_days" => 100 } &&
              envelope["remaining"] == remaining,
              "Truth reserved clean-room Slot V2_2 envelope drift")
      assert!(selected["task_id"] == slot_2_task_id && selected["status"] == task_status &&
              selected["capacity_source_task_id"] == slot_2_id,
              "Truth reserved clean-room Slot V2_2 Task projection drift")
      assert!(reservation["task_id"] == slot_2_task_id && reservation["route_id"] == route["route_id"] &&
              reservation["status"] == task_status &&
              reservation["capacity_source_task_id"] == slot_2_id &&
              reservation["contract"] == selected["contract"] &&
              reservation["budget"] == { "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8 } &&
              (ready ? reservation["authority"].nil? : reservation["authority"] == active["authority_record"]),
              "Truth reserved clean-room Slot V2_2 authority or budget drift")
      assert!(route["status"] == expected_route_status &&
              route["execution_status"] == expected_route_execution &&
              route["scheduling_status"] == expected_scheduling &&
              route["next_eligible_action"] == next_action,
              "Truth reserved clean-room Slot V2_2 Route lifecycle drift")
      assert!(active["current_task"] == (ready ? "NONE" : slot_2_task_id) &&
              active["task_resource_state"] == expected_resource_state &&
              goal["current_task_authority"] == (ready ? "NONE" : slot_2_task_id),
              "Truth reserved clean-room Slot V2_2 active-work lifecycle drift")
      assert!(control["task_creation_allowed"] == false &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots,
              "Truth reserved clean-room Slot V2_2 capacity projection drift")
      assert!(project["current_route_execution_status"] == expected_project_route &&
              claim["p2_phase_envelope_status"] == "TASK_CAPACITY_RESERVED" &&
              claim["current_task"] == (ready ? "NONE" : slot_2_task_id) &&
              claim["real_engineering_progress"] ==
                "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_SLOT_V2_2_TASK_#{ready ? 'READY' : 'ACTIVE'}",
              "Truth reserved clean-room Slot V2_2 claim projection drift")
    when "CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_LOCKED"
      terminal_status = "TERMINAL_PRODUCT_SELECTOR_DEV_METRIC_AND_REPAIR_NON_PASS"
      terminal_receipt = {
        "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p2-product-selector-dev-20260817/task-p2-070/terminal/P2_070_TERMINAL_PRODUCT_SELECTOR_DEV_METRIC_AND_REPAIR_NON_PASS_RECEIPT_V1.json",
        "byte_length" => 5551,
        "sha256" => "514e1001303bbbec4dc657aff2604c014ba93b1cdff28c093fcbba89508b07fa"
      }
      expected_slots[0]["task_id"] = task_id
      expected_slots[1]["task_id"] = slot_2_task_id
      historical = truth.fetch("historical_p2_070_phase_route")
      ledger_entry = envelope.fetch("task_ledger").find { |entry| entry["task_id"] == slot_2_task_id }
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
              envelope["reserved"].nil? &&
              envelope["consumed"] == {
                "engineering_tasks" => 15,
                "engineering_hours" => 432,
                "calendar_days" => 108
              } &&
              envelope["remaining"] == {
                "engineering_tasks" => 1,
                "engineering_hours" => 32,
                "calendar_days" => 8
              }, "Truth terminal clean-room Slot V2_2 envelope drift")
      assert!(historical["status"] == terminal_status &&
              historical["execution_status"] == terminal_status &&
              historical.dig("selected_task", "task_id") == slot_2_task_id &&
              historical.dig("selected_task", "status") == terminal_status &&
              historical["terminal_receipt"] == terminal_receipt,
              "Truth terminal clean-room Slot V2_2 historical Route drift")
      assert!(ledger_entry && ledger_entry["status"] == terminal_status &&
              ledger_entry["outcome_receipt"] == terminal_receipt,
              "Truth terminal clean-room Slot V2_2 ledger drift")
      assert!(route["schema_version"] == "founder-reserved-decision-hold/v1" &&
              route["status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              route["execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              route["scheduling_status"] == "STOPPED_AT_FOUNDER_RESERVED_DECISION" &&
              route["historical_terminal_route_ref"] == "historical_p2_070_phase_route" &&
              route["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
              "Truth terminal clean-room Slot V2_2 Founder hold drift")
      assert!(active["current_task"] == "NONE" &&
              active["task_resource_state"] == "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD" &&
              goal["current_task_authority"] == "NONE",
              "Truth terminal clean-room Slot V2_2 active-work drift")
      assert!(control["task_creation_allowed"] == false &&
              control["current_delivery_percent"] == 25 &&
              control["accepted_milestones"] == ["P2_RECOVERY_BASELINE_ACCEPTED"] &&
              control["next_eligible_action"] == "FOUNDER_RESERVED_DECISION" &&
              control["capacity_slots"] == expected_slots,
              "Truth terminal clean-room Slot V2_2 recovery control drift")
      assert!(project["current_route_execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] ==
                "P1_COMPLETE_P2_BASELINE_ACCEPTED_DELIVERY_25_STRICT_GATE_ZERO_P2_070_TERMINAL_PRODUCT_SELECTOR_DEV_NON_PASS_SLOT_V2_3_LOCKED",
              "Truth terminal clean-room Slot V2_2 claim projection drift")
    when "SLOT_1_BENCHMARK_FOUNDATION_TASK_TERMINAL_NON_PASS"
      terminal_status = "TERMINAL_IMPLEMENTATION_BUDGET_EXHAUSTED_RUNTIME_COMPATIBILITY_NON_PASS"
      next_action = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
      remaining = { "engineering_tasks" => 2, "engineering_hours" => 64, "calendar_days" => 16 }
      expected_slots[0]["task_id"] = task_id
      historical = truth.fetch("historical_p2_068_phase_route")
      terminal_receipt = {
        "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p2-recovery-benchmark-foundation-20260817/task-p2-068/terminal/P2_068_TERMINAL_IMPLEMENTATION_BUDGET_EXHAUSTED_NON_PASS_RECEIPT_V1.json",
        "byte_length" => 5602,
        "sha256" => "d8289319ed32cd5754dc26d7f77ec4ae4bfa27fe45c4747dc1f7e187a3b21cfb"
      }
      ledger_entry = envelope.fetch("task_ledger").find { |entry| entry["task_id"] == task_id }
      assert!(envelope["status"] == "ACTIVE_REMAINING_CAPACITY" && envelope["reserved"].nil? &&
              envelope["remaining"] == remaining &&
              envelope["consumed"] == { "engineering_tasks" => 13, "engineering_hours" => 368, "calendar_days" => 92 },
              "Truth terminal Slot 1 envelope drift")
      assert!(historical["status"] == terminal_status &&
              historical["execution_status"] == terminal_status &&
              historical.dig("selected_task", "task_id") == task_id &&
              historical.dig("selected_task", "status") == terminal_status &&
              historical["terminal_receipt"] == terminal_receipt,
              "Truth terminal Slot 1 historical Route drift")
      assert!(ledger_entry && ledger_entry["status"] == terminal_status &&
              ledger_entry["outcome_receipt"] == terminal_receipt,
              "Truth terminal Slot 1 ledger drift")
      assert!(route["schema_version"] == "phase-delegated-continuation-hold/v1" &&
              route["status"] == "AUTHORIZED_READY" &&
              route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              route["scheduling_status"] == "MASTER_SELECTING_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
              route["historical_terminal_route_ref"] == "historical_p2_068_phase_route" &&
              route["next_eligible_action"] == next_action,
              "Truth terminal Slot 1 continuation Route drift")
      assert!(active["current_task"] == "NONE" && goal["current_task_authority"] == "NONE" &&
              active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_CONTINUATION_READY",
              "Truth terminal Slot 1 active-work drift")
      assert!(control["task_creation_allowed"] == false && control["next_eligible_action"] == next_action &&
              control["capacity_slots"] == expected_slots,
              "Truth terminal Slot 1 recovery control drift")
      assert!(project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
              claim["p2_phase_envelope_status"] == "ACTIVE_REMAINING_CAPACITY" &&
              claim["current_task"] == "NONE" &&
              claim["real_engineering_progress"] == "P1_COMPLETE_P2_ZERO_ACCEPTED_CAPABILITY_SLOT_1_TERMINAL_NON_PASS_NO_BASELINE_RESULT_DELIVERY_ZERO",
              "Truth terminal Slot 1 claim projection drift")
    else
      fail!("unsupported P2 recovery control lifecycle #{control['status'].inspect}")
    end
    assert!(escalation["next_eligible_action"] == route["next_eligible_action"] &&
            active["founder_decision_required"] == terminal_locked &&
            active["next_eligible_action"] == route["next_eligible_action"] &&
            claim["current_phase_route"] == route["route_id"] &&
            claim["next_eligible_action"] == route["next_eligible_action"],
            "Truth P2 recovery current projections drift")
    assert!(plan.dig("current_control", "new_task_creation_allowed") == false,
            "Recovery plan historical baseline was rewritten")
  end

  def validate!(truth_path: DEFAULT_TRUTH, plan_path: DEFAULT_PLAN, repo_root: ROOT)
    repo_root = File.realpath(repo_root)
    plan, plan_bytes = read_yaml!(plan_path, "P2 recovery plan", repo_root)
    truth, = read_yaml!(truth_path, "canonical Truth", repo_root)
    validate_source_guardrails!(DEFAULT_RULES, repo_root)
    validate_plan!(plan, repo_root)
    validate_truth!(truth, plan, plan_bytes, repo_root)
    truth.fetch("p2_recovery_control")
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {
      truth_path: P2RecoveryAntiCycle::DEFAULT_TRUTH,
      plan_path: P2RecoveryAntiCycle::DEFAULT_PLAN,
      repo_root: P2RecoveryAntiCycle::ROOT
    }
    OptionParser.new do |parser|
      parser.on("--truth PATH") { |value| options[:truth_path] = File.expand_path(value) }
      parser.on("--plan PATH") { |value| options[:plan_path] = File.expand_path(value) }
      parser.on("--repo PATH") { |value| options[:repo_root] = File.expand_path(value) }
    end.parse!
    control = P2RecoveryAntiCycle.validate!(**options)
    puts "P2_RECOVERY_ANTI_CYCLE: PASS strict_gate=#{control.fetch('strict_gate_percent')} " \
         "delivery=#{control.fetch('current_delivery_percent')} source_admission=true lifecycle=validated"
  rescue P2RecoveryAntiCycle::ValidationError, AuthorityValidationError,
         DuplicateJsonKeyError, JSON::ParserError, KeyError, Psych::Exception,
         Errno::ENOENT, Errno::ELOOP => error
    warn "P2_RECOVERY_ANTI_CYCLE: NON_PASS #{error.message}"
    exit 1
  end
end

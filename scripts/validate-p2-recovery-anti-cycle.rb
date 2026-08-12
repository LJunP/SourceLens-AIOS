#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "psych"
require "yaml"

module P2RecoveryAntiCycle
  ROOT = File.expand_path("..", __dir__)
  DEFAULT_TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
  DEFAULT_PLAN = File.join(ROOT, "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml")

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

  def validate_truth!(truth, plan, plan_bytes)
    project = truth.fetch("project")
    goal = truth.fetch("goal")
    route = truth.fetch("current_phase_route")
    envelope = truth.fetch("phase_execution_envelope")
    escalation = truth.fetch("founder_escalation_control")
    active = truth.fetch("active_work")
    claim = truth.fetch("claim_boundary")
    gate = truth.dig("strict_phase_gate_ledger", "phases", "P2")
    control = exact_keys!(truth.fetch("p2_recovery_control"), %w[
      accepted_milestones current_delivery_percent governance_progress_credit next_eligible_action
      plan schema_version status strict_gate_percent task_creation_allowed
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
    assert!(control["strict_gate_percent"] == 0 && control["current_delivery_percent"] == 0 && control["accepted_milestones"] == [], "Truth created false P2 progress")
    assert!(control["governance_progress_credit"] == 0, "Truth credited governance as P2 progress")

    expected_budget = { "engineering_tasks" => 12, "engineering_hours" => 336, "calendar_days" => 84 }
    expected_zero = { "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0 }
    assert!(envelope["status"] == "EXHAUSTED" && envelope["limits"].slice(*expected_budget.keys) == expected_budget && envelope["consumed"] == expected_budget && envelope["remaining"] == expected_zero, "Truth P2 envelope drift")
    assert!(route["status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" && route["next_eligible_action"] == "FOUNDER_RESERVED_DECISION", "Truth current route is not the reserved hold")
    assert!(escalation["disposition"] == "FOUNDER_DECISION_REQUIRED" && escalation.dig("reserved_trigger", "category") == "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE", "Truth Founder escalation drift")
    assert!(active["current_task"] == "NONE" && goal["current_task_authority"] == "NONE", "P2 recovery correction may not activate a Task")
    assert!(claim["p2_phase_envelope_status"] == "EXHAUSTED" && claim["p2_project_status"] == "ACTIVE" && claim["long_term_goal_status"] == "ACTIVE", "Truth lifecycle projection drift")
    assert!(control["schema_version"] == "p2-recovery-control/v1" && control["status"] == "FOUNDER_CORRECTION_ACTIVE_AWAITING_ENVELOPE_AUTHORIZATION" && control["task_creation_allowed"] == false && control["next_eligible_action"] == "FOUNDER_RESERVED_DECISION", "Truth P2 recovery hold drift")
    assert!(plan.dig("current_control", "new_task_creation_allowed") == control["task_creation_allowed"], "Plan/Truth task creation control drift")
  end

  def validate!(truth_path: DEFAULT_TRUTH, plan_path: DEFAULT_PLAN, repo_root: ROOT)
    repo_root = File.realpath(repo_root)
    plan, plan_bytes = read_yaml!(plan_path, "P2 recovery plan", repo_root)
    truth, = read_yaml!(truth_path, "canonical Truth", repo_root)
    validate_plan!(plan, repo_root)
    validate_truth!(truth, plan, plan_bytes)
    true
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
    P2RecoveryAntiCycle.validate!(**options)
    puts "P2_RECOVERY_ANTI_CYCLE: PASS strict_gate=0 delivery=0 task_creation=false"
  rescue P2RecoveryAntiCycle::ValidationError, KeyError, Psych::Exception => error
    warn "P2_RECOVERY_ANTI_CYCLE: NON_PASS #{error.message}"
    exit 1
  end
end

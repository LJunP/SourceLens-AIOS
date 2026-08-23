#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

class P3ExecutableTransitionSystemKernelRouteValidationError < StandardError; end

module P3ExecutableTransitionSystemKernelRouteValidation
  module_function

  ROUTE_SCHEMA = "p3-executable-transition-system-kernel-reentry-route/v1"
  ROUTE_ID = "P3_EXECUTABLE_TRANSITION_SYSTEM_KERNEL_REENTRY_ROUTE_V1"
  DECISION_SCHEMA = "p3-executable-transition-system-kernel-founder-decision/v1"
  DECISION_ID =
    "AUTHORIZE_P3_EXECUTABLE_TRANSITION_SYSTEM_KERNEL_TASK_WIDE_PRODUCT_AND_ONE_SHOT_AUDIT_REENTRY_V1"
  OPERATION_TYPE =
    "P3_EXECUTABLE_TRANSITION_SYSTEM_KERNEL_TASK_WIDE_PRODUCT_AND_ONE_SHOT_AUDIT_REENTRY"
  OBJECTIVE_ID = "TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION"
  WORKFLOW_ID = "SHA256_READ_ONLY_CUSTODY_V1"
  STRICT_GATE_ID =
    "TRUSTED_HOST_TCB_TASK_WIDE_TRANSACTIONAL_EXECUTION_WITH_PROCESS_REAL_CONTAINMENT"
  STRICT_ITEMS = %w[
    TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER
    AUTHORIZATION_AND_INTENT_DURABILITY
    CRASH_ORPHAN_RECONCILIATION_AND_RESUME
    EXACTLY_ONE_TERMINAL_TRACE_AND_CHECKPOINT_GATE
    TRUSTED_HOST_TCB_PROCESS_REAL_CONTAINMENT_ATTESTATION
  ].freeze
  COMPATIBILITY_ITEM = "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"

  DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/decision/FOUNDER_P3_ETSK_ACCEPTED_STRUCTURED_DECISION_V1.json",
    "byte_length" => 14_147,
    "sha256" => "3797ad7b1ffd91631dc010423b7d77c9214a66ab03a51de50427d343732ebf67"
  }.freeze
  ADR = {
    "path" => "docs/aios/decisions/P3_EXECUTABLE_TRANSITION_SYSTEM_KERNEL_REENTRY_ROUTE_DECISION_V1.json",
    "byte_length" => 14_147,
    "sha256" => "3797ad7b1ffd91631dc010423b7d77c9214a66ab03a51de50427d343732ebf67"
  }.freeze
  AUTHORIZATION_BODY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/decision/FOUNDER_AUTHORIZATION_BODY_V1.txt",
    "byte_length" => 12_677,
    "sha256" => "e1154f53ee8deab25550bef3a71d241b02bc56879708813310a0b736a1a740d4"
  }.freeze
  SOURCE_ATTACHMENT = AUTHORIZATION_BODY.merge(
    "path" => "/Users/lijunpeng/.codex/attachments/1987d038-0d59-4c17-9f8b-aee1eb28137a/pasted-text.txt"
  ).freeze
  CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "3.2",
    "byte_length" => 20_994,
    "sha256" => "ccba174ea66d1044d63de97cd1a666139d6c886d2ebd1d790dbb59b98fb9b32a"
  }.freeze
  TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-task-wide-reservation-frontier-20260823/task-foundation/terminal/P3_TWRF_F1_FOUNDATION_TASK_TERMINAL_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 6_123,
    "sha256" => "3489a70fd8af5e1e1000aa860b9d0eee346024c74c855ed17fd67e8eb00ad977"
  }.freeze
  TERMINAL_FINDING_IDS = %w[
    P3-TWRF-F1-C1-P1-001
    P3-TWRF-F1-C1-P1-002
  ].freeze
  CANONICAL_START = {
    "repository" => "/Users/lijunpeng/Developer/SourceLens-AIOS",
    "branch" => "main",
    "commit" => "86fbe52acf7150a70f94f6fe7a286b5b69907e6f",
    "tree" => "6fed8dabd3d5f2aa33e643e4215d143cd6102b49",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_947_994,
      "sha256" => "6e03831e89f97fc141894964551832827e5d569f040043114e4f42e3e62f578b"
    },
    "constitution" => CONSTITUTION,
    "terminal_receipt" => TERMINAL_RECEIPT
  }.freeze

  LIMITS = {
    "engineering_tasks" => 16,
    "engineering_hours" => 456,
    "calendar_days" => 108,
    "active_tasks" => 1,
    "task_branches" => 1,
    "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  BASE_CONSUMED = {
    "engineering_tasks" => 13,
    "engineering_hours" => 384,
    "calendar_days" => 92
  }.freeze
  STAGE_IDS = %w[
    EXECUTABLE_TRANSITION_SYSTEM_KERNEL
    TASK_WIDE_TRANSACTIONAL_EXECUTION_PRODUCT
    ONE_SHOT_STRICT_EXIT_AUDIT
  ].freeze
  TASK_IDS = %w[
    AIOS-P3-ETSK-F1_EXECUTABLE_TRANSITION_SYSTEM_KERNEL
    AIOS-P3-ETSK-P1_TASK_WIDE_TRANSACTIONAL_EXECUTION_PRODUCT
    AIOS-P3-ETSK-A1_ONE_SHOT_STRICT_EXIT_AUDIT
  ].freeze
  STAGE_KINDS = %w[EVALUATION_FOUNDATION PRODUCT_IMPLEMENTATION EVALUATION_ONLY].freeze
  STAGE_BUDGETS = [
    {
      "engineering_tasks" => 1, "engineering_hours" => 8, "calendar_days" => 2,
      "candidate_generations" => 1, "same_task_repairs" => 0, "review_cycles" => 1
    },
    {
      "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 10,
      "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
    },
    {
      "engineering_tasks" => 1, "engineering_hours" => 16, "calendar_days" => 4,
      "formal_dispatches" => 1, "product_changes" => 0, "same_task_repairs" => 0,
      "rerun_to_pass_allowed" => false
    }
  ].map(&:freeze).freeze
  STAGE_RESOURCES = [
    {
      "branch" => "codex/p3-etsk-f1-executable-transition-system-kernel",
      "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-etsk-f1-executable-transition-system-kernel",
      "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/task-foundation"
    },
    {
      "branch" => "codex/p3-etsk-p1-task-wide-transactional-execution",
      "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-etsk-p1-task-wide-transactional-execution",
      "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/task-product"
    },
    {
      "branch" => "codex/p3-etsk-a1-one-shot-strict-exit-audit",
      "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-etsk-a1-one-shot-strict-exit-audit",
      "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/task-audit"
    }
  ].map(&:freeze).freeze
  WORKER_PATHS = [
    %w[
      evaluation-harness/harness/p3-executable-transition-system-kernel-v1
      evaluation-harness/reports/p3-executable-transition-system-kernel-v1
      docs/aios/tasks/P3-ETSK-F1_EXECUTABLE_TRANSITION_SYSTEM_KERNEL.yaml
      docs/PROJECT_CODE_MAP.md
    ],
    %w[
      backend-spring/src/main/java/com/sourcelens/module/execution/taskwide
      backend-spring/src/main/java/com/sourcelens/module/sandbox/oci/taskwide
      backend-spring/src/main/java/com/sourcelens/module/execution/service/ExecutionCheckpointService.java
      backend-spring/src/main/java/com/sourcelens/module/execution/mapper/ExecutionCheckpointStore.java
      backend-spring/src/main/resources/db/migration/V034__add_task_wide_reservation_frontier.sql
      backend-spring/src/test/java/com/sourcelens/module/execution/taskwide
      backend-spring/src/test/java/com/sourcelens/module/sandbox/oci/taskwide
      backend-spring/src/test/resources/p3-task-wide-reservation
      docs/aios/tasks/P3-ETSK-P1_TASK_WIDE_TRANSACTIONAL_EXECUTION_PRODUCT.yaml
      docs/PROJECT_CODE_MAP.md
    ],
    %w[
      docs/aios/tasks/P3-ETSK-A1_ONE_SHOT_STRICT_EXIT_AUDIT.yaml
      evaluation-harness/reports/p3-executable-transition-system-kernel-audit-v1
    ]
  ].map(&:freeze).freeze
  REJECTED_LINEAGE_POLICY =
    "CANONICAL_MAIN_ACCEPTED_P3_001_AND_ACCEPTED_ETSK_FOUNDATION_ONLY_NO_TWRF_OR_EARLIER_REJECTED_ENGINEERING_LINEAGE_READ_COMPARE_COPY_EXECUTE_REPAIR_OR_REUSE"
  STRATEGIC_PATHS = %w[
    docs/aios/truth/project_state.yaml
    docs/aios/decisions/P3_EXECUTABLE_TRANSITION_SYSTEM_KERNEL_REENTRY_ROUTE_DECISION_V1.json
    scripts/validate-founder-delegation-continuity.rb
    scripts/validate-current-task-authority.rb
    scripts/validate-p3-final-transactional-route.rb
    scripts/test-p3-final-transactional-route.rb
    scripts/validate-strict-phase-gates.rb
    scripts/test-strict-phase-gates.rb
  ].freeze

  LIFECYCLE = {
    "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" => {
      "state" => "P3_ETSK_FOUNDATION_ELIGIBLE",
      "route_status" => "ACTIVE_FOUNDATION_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_ETSK_F1_FOUNDATION",
      "stage_statuses" => %w[ELIGIBLE_NOT_ACTIVATED LOCKED_PENDING_FOUNDATION_ACCEPTED LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => nil, "completed_stage_count" => 0, "delivery" => 25, "strict" => 0,
      "consumed_count" => 0, "reserved_index" => nil, "founder_required" => false
    },
    "FOUNDATION_TASK_ACTIVE" => {
      "state" => "P3_ETSK_FOUNDATION_TASK_ACTIVE",
      "route_status" => "ACTIVE_FOUNDATION_TASK",
      "action" => "EXECUTE_AIOS_P3_ETSK_F1_FOUNDATION",
      "stage_statuses" => %w[ACTIVE LOCKED_PENDING_FOUNDATION_ACCEPTED LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => 0, "completed_stage_count" => 0, "delivery" => 25, "strict" => 0,
      "consumed_count" => 0, "reserved_index" => 0, "founder_required" => false
    },
    "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE" => {
      "state" => "P3_ETSK_PRODUCT_ELIGIBLE",
      "route_status" => "ACTIVE_PRODUCT_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_ETSK_P1_PRODUCT",
      "stage_statuses" => %w[ACCEPTED ELIGIBLE_NOT_ACTIVATED LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => nil, "completed_stage_count" => 1, "delivery" => 25, "strict" => 0,
      "consumed_count" => 1, "reserved_index" => nil, "founder_required" => false
    },
    "PRODUCT_TASK_ACTIVE" => {
      "state" => "P3_ETSK_PRODUCT_TASK_ACTIVE",
      "route_status" => "ACTIVE_PRODUCT_TASK",
      "action" => "EXECUTE_AIOS_P3_ETSK_P1_PRODUCT",
      "stage_statuses" => %w[ACCEPTED ACTIVE LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => 1, "completed_stage_count" => 1, "delivery" => 25, "strict" => 0,
      "consumed_count" => 1, "reserved_index" => 1, "founder_required" => false
    },
    "PRODUCT_ACCEPTED_AUDIT_ELIGIBLE" => {
      "state" => "P3_ETSK_AUDIT_ELIGIBLE",
      "route_status" => "ACTIVE_AUDIT_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_ETSK_A1_AUDIT",
      "stage_statuses" => %w[ACCEPTED ACCEPTED_INTEGRATED ELIGIBLE_NOT_ACTIVATED],
      "active_index" => nil, "completed_stage_count" => 2, "delivery" => 75, "strict" => 0,
      "consumed_count" => 2, "reserved_index" => nil, "founder_required" => false
    },
    "AUDIT_TASK_ACTIVE" => {
      "state" => "P3_ETSK_AUDIT_TASK_ACTIVE",
      "route_status" => "ACTIVE_AUDIT_TASK",
      "action" => "EXECUTE_AIOS_P3_ETSK_A1_ONE_SHOT_AUDIT",
      "stage_statuses" => %w[ACCEPTED ACCEPTED_INTEGRATED ACTIVE],
      "active_index" => 2, "completed_stage_count" => 2, "delivery" => 75, "strict" => 0,
      "consumed_count" => 2, "reserved_index" => 2, "founder_required" => false
    },
    "ROUTE_TERMINAL_NON_PASS" => {
      "state" => "P3_ETSK_ROUTE_TERMINAL_NON_PASS",
      "route_status" => "HOLD_INCOMPLETE_ROUTE_TERMINAL_NON_PASS",
      "action" => "FOUNDER_DECIDE_P3_AFTER_ETSK_ROUTE_TERMINAL_NON_PASS",
      "active_index" => nil, "founder_required" => true
    },
    "AUDIT_PASS_PHASE_GATE_ELIGIBLE" => {
      "state" => "P3_ETSK_P3_PHASE_GATE_ELIGIBLE",
      "route_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "action" => "FOUNDER_DECIDE_P3_PHASE_EXIT",
      "stage_statuses" => %w[ACCEPTED ACCEPTED_INTEGRATED ACCEPTED],
      "active_index" => nil, "completed_stage_count" => 3, "delivery" => 100, "strict" => 100,
      "consumed_count" => 3, "reserved_index" => nil, "founder_required" => true
    }
  }.freeze
  LIFECYCLE_STATES = LIFECYCLE.each_with_object({}) { |(key, value), result| result[key] = value["state"] }.freeze

  def assert(condition, message)
    raise P3ExecutableTransitionSystemKernelRouteValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} is not a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} is not an array")
    value
  end

  def git!(root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    assert(status.success?, "git #{args.join(' ')} failed: #{stderr.strip}")
    stdout.strip
  end

  def path_for(root, identity)
    path = Pathname.new(identity.fetch("path"))
    path.absolute? ? path : Pathname.new(root).join(path)
  end

  def read_identity!(root, identity, label, create_once: false)
    path = path_for(root, identity)
    assert(path.exist? && path.file? && !path.symlink?, "#{label} missing, non-regular or symlinked")
    stat = path.stat
    assert(stat.nlink == 1, "#{label} link count is not one") if create_once
    assert((stat.mode & 0o777) == 0o444, "#{label} mode is not 0444") if create_once
    bytes = path.binread
    assert(bytes.bytesize == identity.fetch("byte_length"), "#{label} byte length drift")
    assert(Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"), "#{label} SHA-256 drift")
    bytes
  end

  def parse_json!(bytes, label)
    value = JSON.parse(bytes)
    mapping(value, label)
  rescue JSON::ParserError => e
    raise P3ExecutableTransitionSystemKernelRouteValidationError, "#{label} invalid JSON: #{e.message}"
  end

  def load_start_truth!(root)
    bytes, stderr, status = Open3.capture3(
      "git", "-C", root.to_s, "show",
      "#{CANONICAL_START.fetch('commit')}:docs/aios/truth/project_state.yaml"
    )
    assert(status.success?, "cannot read canonical-start Truth: #{stderr.strip}")
    assert(bytes.bytesize == CANONICAL_START.dig("truth", "byte_length"),
           "canonical-start Truth byte length drift")
    assert(Digest::SHA256.hexdigest(bytes) == CANONICAL_START.dig("truth", "sha256"),
           "canonical-start Truth SHA-256 drift")
    YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def validate_decision!(root)
    adr_bytes = read_identity!(root, ADR, "P3 ETSK canonical ADR")
    staging = ENV["SOURCELENS_ETSK_STRATEGIC_STAGING_ROOT"]
    external_path = path_for(root, DECISION)
    external_bytes = if staging && !external_path.exist?
                       adr_bytes
                     else
                       read_identity!(root, DECISION, "P3 ETSK Founder decision", create_once: true)
                     end
    assert(external_bytes == adr_bytes, "P3 ETSK external decision and canonical ADR differ")
    attachment = read_identity!(root, SOURCE_ATTACHMENT, "P3 ETSK direct attachment")
    body_path = path_for(root, AUTHORIZATION_BODY)
    body = if staging && !body_path.exist?
             attachment
           else
             read_identity!(root, AUTHORIZATION_BODY, "P3 ETSK authorization body", create_once: true)
           end
    assert(body == attachment, "P3 ETSK installed authorization body differs from attachment")
    assert(body.dup.force_encoding(Encoding::UTF_8).valid_encoding? &&
           body.lines.first&.chomp == DECISION_ID,
           "P3 ETSK authorization token or UTF-8 identity drift")
    decision = parse_json!(external_bytes, "P3 ETSK Founder decision")
    assert(decision["schema_version"] == DECISION_SCHEMA &&
           decision["record_type"] == "FOUNDER_ACCEPTED_STRATEGIC_DECISION" &&
           decision["decision_id"] == DECISION_ID && decision["operation_type"] == OPERATION_TYPE &&
           decision["status"] == "ACCEPTED_CURRENT_DIRECT_FOUNDER_MESSAGE",
           "P3 ETSK Founder decision header drift")
    assert(decision.dig("source", "byte_length") == AUTHORIZATION_BODY.fetch("byte_length") &&
           decision.dig("source", "sha256") == AUTHORIZATION_BODY.fetch("sha256") &&
           decision.dig("source", "installed_body", "path") == AUTHORIZATION_BODY.fetch("path") &&
           decision.dig("source", "installed_body", "byte_equal_to_attachment") == true,
           "P3 ETSK source-body binding drift")
    start_keys = %w[repository branch commit tree truth constitution]
    assert(decision["canonical_start"].slice(*start_keys) == CANONICAL_START.slice(*start_keys) &&
           decision.dig("canonical_start", "clean") == true &&
           decision.dig("canonical_start", "terminal_route", "receipt") == CANONICAL_START.fetch("terminal_receipt") &&
           decision.dig("canonical_start", "terminal_route", "candidate_integrated") == false,
           "P3 ETSK canonical-start or terminal binding drift")
    assert(decision.dig("strategic_change", "objective_id") == OBJECTIVE_ID &&
           decision.dig("strategic_change", "strict_exit_gate_id") == STRICT_GATE_ID &&
           decision.dig("strategic_change", "required_gate_items") == STRICT_ITEMS &&
           decision.dig("strategic_change", "same_frozen_product_candidate_required") == true &&
           decision.dig("strategic_change", "p3_001_semantics", "prebinding_one_workflow_at_task_creation_is_forbidden_scope_degradation") == true,
           "P3 ETSK strategic Gate or P3-001 semantics drift")
    foundation = mapping(decision["foundation_acceptance"], "P3 ETSK Foundation acceptance")
    assert(foundation["single_machine_spec_path"] == "machine_spec.json" &&
           foundation["machine_spec_is_only_semantic_source"] == true &&
           foundation["interpreter_state_mutation_only_through_declared_transition"] == true &&
           foundation["verifier_replays_every_trace_from_initial_state"] == true &&
           foundation["required_negative_controls"] == %w[
             UNKNOWN_STATE UNKNOWN_EVENT ILLEGAL_TRANSITION MISSING_RESULT FORGED_RESULT
             AGGREGATE_TRACE_MISMATCH TERMINAL_REPLAY_CROSS_INVOCATION_MUTATION
             RESERVATION_TAMPER HISTORY_TAMPER
           ] && foundation["product_source_changes_allowed"] == false &&
           foundation["candidate_generations"] == 1 &&
           foundation["same_task_repairs"] == 0 &&
           foundation["independent_review_cycles"] == 1,
           "P3 ETSK single-source executable Foundation contract drift")
    assert(decision.dig("route", "route_id") == ROUTE_ID &&
           decision.dig("route", "cumulative_ceiling") == LIMITS.slice(
             "engineering_tasks", "engineering_hours", "calendar_days"
           ) && decision.dig("route", "consumed_preserved") == BASE_CONSUMED &&
           decision.dig("route", "released_for_this_route") == {
             "engineering_tasks" => 3, "engineering_hours" => 72, "calendar_days" => 16
           }, "P3 ETSK non-resettable accounting drift")
    decision_stages = array(decision.dig("route", "stages"), "P3 ETSK decision stages")
    assert(decision_stages.length == 3, "P3 ETSK decision stage count drift")
    decision_stages.each_with_index do |stage, index|
      assert(stage["ordinal"] == index + 1 && stage["stage_id"] == STAGE_IDS[index] &&
             stage["task_id"] == TASK_IDS[index] && stage["kind"] == STAGE_KINDS[index] &&
             stage["budget"] == STAGE_BUDGETS[index] && stage["resources"] == STAGE_RESOURCES[index],
             "P3 ETSK decision stage #{index + 1} drift")
    end
    assert(decision.dig("external_effects", "network_authorized") == false &&
           decision.dig("external_effects", "provider_authorized") == false &&
           decision.dig("external_effects", "secret_or_credential_authorized") == false &&
           decision.dig("external_effects", "remote_production_public_authorized") == false &&
           decision.dig("external_effects", "p4_entry_authorized") == false &&
           decision.dig("anti_loop", "governance_progress_credit") == 0 &&
           decision.dig("lifecycle", "long_term_goal_status") == "ACTIVE" &&
           decision.dig("lifecycle", "codex_goal_completion_authorized") == false,
           "P3 ETSK effect, anti-loop or Goal boundary drift")
    decision
  end

  def validate_repository_context!(root, truth)
    root = Pathname.new(root).realpath
    assert(git!(root, "rev-parse", "#{CANONICAL_START.fetch('commit')}^{tree}") ==
           CANONICAL_START.fetch("tree"), "P3 ETSK canonical-start tree drift")
    _out, _err, ancestor = Open3.capture3(
      "git", "-C", root.to_s, "merge-base", "--is-ancestor", CANONICAL_START.fetch("commit"), "HEAD"
    )
    assert(ancestor.success?, "P3 ETSK canonical start is not an ancestor of HEAD")
    staging = ENV["SOURCELENS_ETSK_STRATEGIC_STAGING_ROOT"]
    if staging
      assert(root == Pathname.new(staging).realpath,
             "P3 ETSK staging root does not bind validator root")
      status_bytes, status_stderr, status = Open3.capture3(
        "git", "-C", root.to_s, "status", "--porcelain=v1", "--untracked-files=all"
      )
      assert(status.success?, "cannot inspect staged strategic path set: #{status_stderr.strip}")
      changed = status_bytes.lines.map do |line|
        line[3..-1].to_s.strip
      end
      assert((changed - STRATEGIC_PATHS).empty? && (STRATEGIC_PATHS - changed).empty?,
             "P3 ETSK staged strategic path set drift: #{changed.inspect}")
    else
      canonical = Pathname.new(CANONICAL_START.fetch("repository")).realpath
      assert(root == canonical, "P3 ETSK validator is not running from canonical repository")
      assert(git!(root, "symbolic-ref", "--quiet", "--short", "HEAD") == "main",
             "P3 ETSK canonical branch drift")
      assert(git!(root, "status", "--porcelain=v1", "--untracked-files=all").empty?,
             "P3 ETSK canonical worktree is not clean")
      descendants = git!(root, "rev-list", "--reverse", "--ancestry-path",
                          "#{CANONICAL_START.fetch('commit')}..HEAD").lines.map(&:strip)
      assert(!descendants.empty?, "P3 ETSK strategic installation commit is absent")
      install_commit = descendants.first
      changed = git!(root, "diff", "--name-only", CANONICAL_START.fetch("commit"), install_commit).lines.map(&:strip)
      assert(changed.sort == STRATEGIC_PATHS.sort,
             "P3 ETSK canonical strategic installation path set drift")
    end
    start_truth = load_start_truth!(root)
    {
      "historical_p3_twrf_route_terminal" => "current_phase_route",
      "historical_p3_twrf_phase_execution_envelope" => "phase_execution_envelope",
      "historical_p3_twrf_founder_escalation_control" => "founder_escalation_control",
      "historical_p3_twrf_phase_delegation" => "phase_delegation",
      "historical_p3_twrf_phase_boundary" => "phase_boundary",
      "historical_p3_twrf_terminal_active_work" => "active_work"
    }.each do |historical_key, start_key|
      assert(truth[historical_key] == start_truth[start_key],
             "P3 ETSK immutable predecessor projection drift: #{historical_key}")
    end
  end

  def sum_budget(count)
    STAGE_BUDGETS.first(count).each_with_object(
      {"engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0}
    ) do |budget, sum|
      sum.keys.each { |key| sum[key] += budget.fetch(key) }
    end
  end

  def expected_accounting(profile)
    consumed = BASE_CONSUMED.merge(sum_budget(profile.fetch("consumed_count"))) do |_key, base, extra|
      base + extra
    end
    reserved = if profile["reserved_index"]
                 index = profile.fetch("reserved_index")
                 STAGE_BUDGETS[index].slice("engineering_tasks", "engineering_hours", "calendar_days").merge(
                   "task_id" => TASK_IDS[index]
                 )
               else
                 {}
               end
    remaining = LIMITS.slice("engineering_tasks", "engineering_hours", "calendar_days").merge(consumed) do
      |_key, limit, used|
      limit - used
    end
    reserved.each { |key, value| remaining[key] -= value if remaining.key?(key) }
    [consumed, reserved, remaining]
  end

  def validate_stage_shape!(route, profile)
    stages = array(route["ordered_stages"], "P3 ETSK ordered stages")
    assert(stages.length == 3, "P3 ETSK ordered stage count drift")
    expected_statuses = profile["stage_statuses"]
    if route["lifecycle_stage"] == "ROUTE_TERMINAL_NON_PASS"
      assert(stages.count { |stage| stage["status"].to_s.start_with?("TERMINAL") } == 1,
             "P3 ETSK terminal Route must have exactly one terminal stage")
      terminal_index = stages.index { |stage| stage["status"].to_s.start_with?("TERMINAL") }
      assert(terminal_index && stages[0...terminal_index].all? { |stage| stage["status"].start_with?("ACCEPTED") } &&
             stages[(terminal_index + 1)..-1].all? { |stage| stage["status"].start_with?("LOCKED") },
             "P3 ETSK terminal stage ordering drift")
    else
      assert(stages.map { |stage| stage["status"] } == expected_statuses,
             "P3 ETSK stage lifecycle projection drift")
    end
    stages.each_with_index do |stage, index|
      allowed = %w[ordinal stage_id task_id kind status budget resources gate_receipt candidate terminal_receipt]
      assert((stage.keys - allowed).empty?, "P3 ETSK stage #{index + 1} unknown member")
      assert(stage["ordinal"] == index + 1 && stage["stage_id"] == STAGE_IDS[index] &&
             stage["task_id"] == TASK_IDS[index] && stage["kind"] == STAGE_KINDS[index] &&
             stage["budget"] == STAGE_BUDGETS[index] && stage["resources"] == STAGE_RESOURCES[index],
             "P3 ETSK stage #{index + 1} identity or budget drift")
    end
  end

  def validate_active_task!(root, truth, profile)
    active = mapping(truth["active_work"], "P3 ETSK active work")
    index = profile["active_index"]
    if index.nil?
      assert(active["current_task"] == "NONE" && active["execution_nonce_status"] != "ACTIVE" &&
             active["task_branch"].nil? && active["task_worktree"].nil?,
             "P3 ETSK non-active lifecycle resurrected a Task")
      return
    end
    task_id = TASK_IDS[index]
    resource = STAGE_RESOURCES[index]
    assert(active["current_task"] == task_id && active["selected_task"] == task_id &&
           active["current_task_status"] == "ACTIVE" && active["execution_nonce_status"] == "ACTIVE" &&
           active["task_branch"] == resource.fetch("branch") &&
           active["task_worktree"] == resource.fetch("worktree") &&
           active["execution_evidence_root"] == resource.fetch("evidence_root") &&
           active["allowlisted_paths"] == WORKER_PATHS[index] &&
           active["current_task_budget"] == STAGE_BUDGETS[index],
           "P3 ETSK active Task identity, resources, scope or budget drift")
    contract_identity = mapping(active["current_task_contract"], "P3 ETSK active Contract identity")
    contract_bytes = read_identity!(root, contract_identity, "P3 ETSK active Task Contract")
    contract = YAML.safe_load(contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(contract["task_id"] == task_id && contract["phase"] == "P3" &&
           contract.dig("scope", "task_branch") == resource.fetch("branch") &&
           contract.dig("scope", "task_worktree") == resource.fetch("worktree") &&
           contract.dig("scope", "evidence_root") == resource.fetch("evidence_root") &&
           contract.dig("scope", "worker_allowed_paths") == WORKER_PATHS[index] &&
           contract["budget"].slice(*STAGE_BUDGETS[index].keys) == STAGE_BUDGETS[index] &&
           contract.dig("authority", "founder_decision_id") == DECISION_ID,
           "P3 ETSK active Task Contract semantic drift")
    authority_identity = mapping(active["authority_record"], "P3 ETSK active authority identity")
    authority = parse_json!(
      read_identity!(root, authority_identity, "P3 ETSK active Task authority", create_once: true),
      "P3 ETSK active Task authority"
    )
    assert(authority["task_id"] == task_id &&
           authority["authorization_id"] == active["authorization_id"] &&
           authority["execution_nonce"] == active["execution_nonce"] &&
           authority.dig("founder_route_decision", "decision_id") == DECISION_ID &&
           authority["resources"] == resource && authority["budget"] == STAGE_BUDGETS[index] &&
           authority.dig("scope", "worker_allowed_paths") == WORKER_PATHS[index] &&
           authority.dig("external_effects", "network") == false &&
           authority.dig("external_effects", "provider") == false &&
           authority.dig("external_effects", "secret") == false &&
           authority.dig("external_effects", "remote") == false &&
           authority.dig("external_effects", "production") == false &&
           authority.dig("external_effects", "public") == false,
           "P3 ETSK active Task authority semantic drift")
  rescue Psych::Exception => e
    raise P3ExecutableTransitionSystemKernelRouteValidationError, "P3 ETSK active Contract invalid: #{e.message}"
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    assert(truth["record_type"] == "sourcelens_aios_current_truth", "unexpected Truth record type")
    route = mapping(truth["current_phase_route"], "P3 ETSK current Route")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID,
           "P3 ETSK Route identity drift")
    lifecycle = route["lifecycle_stage"]
    profile = LIFECYCLE[lifecycle]
    assert(profile, "P3 ETSK lifecycle is not closed-schema: #{lifecycle.inspect}")
    allowed_route_keys = %w[
      schema_version route_id status lifecycle_stage execution_status scheduling_status phase
      phase_entry_status policy founder_phase_route_decision_required founder_reserved_triggers_resolved
      next_eligible_action phase_execution_envelope_ref phase_entry_route_ref
      accepted_p3_001_foundation_route_ref historical_predecessor_route_ref founder_route_decision
      canonical_start constitution objective_id workflow_id threat_model strict_exit_gate p3_001_semantics
      cumulative_accounting ordered_stages progression foundation_acceptance product_acceptance
      toolchain_preflight p3_entry_authorized p4_entry_authorized long_term_goal_status
      external_effect_authority anti_loop rejected_lineage_policy historical_terminal_result
      terminal_result accepted_foundation accepted_product accepted_audit
    ]
    assert((route.keys - allowed_route_keys).empty?, "P3 ETSK current Route has unknown members")
    validate_repository_context!(root, truth)
    decision = validate_decision!(root)
    terminal_receipt = parse_json!(
      read_identity!(root, TERMINAL_RECEIPT, "P3 ETSK predecessor terminal receipt", create_once: true),
      "P3 ETSK predecessor terminal receipt"
    )
    assert(terminal_receipt["record_type"] == "P3_TWRF_F1_FOUNDATION_TASK_TERMINAL_NON_PASS_RECEIPT" &&
           terminal_receipt.dig("terminal_result", "route_lifecycle") == "ROUTE_TERMINAL_NON_PASS" &&
           terminal_receipt.dig("candidate", "canonical_integration_performed") == false &&
           terminal_receipt.dig("independent_review", "complete_frozen_findings").map { |item| item["finding_id"] } == TERMINAL_FINDING_IDS,
           "P3 ETSK predecessor terminal facts drift")
    constitution = read_identity!(root, CONSTITUTION, "P3 ETSK Strategic Constitution v3.2")
    assert(constitution.include?("## 9B. P3 v3.2 task-wide reservation frontier authority") &&
           constitution.include?("`#{STRICT_GATE_ID}`") &&
           STRICT_ITEMS.all? { |item| constitution.include?("`#{item}`") },
           "P3 ETSK Constitution semantic anchor drift")
    assert(route["status"] == profile.fetch("route_status") && route["phase"] == "P3" &&
           route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == profile.fetch("founder_required") &&
           route["next_eligible_action"] == profile.fetch("action") &&
           route["founder_route_decision"] == DECISION.merge(
             "decision_id" => DECISION_ID, "operation_type" => OPERATION_TYPE,
             "canonical_adr" => ADR, "source_body" => AUTHORIZATION_BODY
           ) && route["canonical_start"] == CANONICAL_START && route["constitution"] == CONSTITUTION &&
           route["objective_id"] == OBJECTIVE_ID && route["workflow_id"] == WORKFLOW_ID &&
           route.dig("strict_exit_gate", "gate_id") == STRICT_GATE_ID &&
           route.dig("strict_exit_gate", "required_item_ids") == STRICT_ITEMS &&
           route.dig("strict_exit_gate", "same_frozen_product_candidate_required") == true &&
           route.dig("p3_001_semantics", "prebinding_one_workflow_at_task_creation_allowed") == false &&
           route["rejected_lineage_policy"] == REJECTED_LINEAGE_POLICY &&
           route["foundation_acceptance"] == decision["foundation_acceptance"] &&
           route["product_acceptance"] == decision["product_acceptance"] &&
           route["toolchain_preflight"] == decision["toolchain_preflight"] &&
           route["anti_loop"] == decision["anti_loop"],
           "P3 ETSK Route authority, Gate or P3-001 projection drift")
    assert(route.dig("cumulative_accounting", "limits") == LIMITS &&
           route.dig("cumulative_accounting", "consumed") == BASE_CONSUMED &&
           route.dig("cumulative_accounting", "remaining") == {
             "engineering_tasks" => 3, "engineering_hours" => 72, "calendar_days" => 16
           }, "P3 ETSK installed cumulative accounting drift")
    assert(route.dig("external_effect_authority", "network") == false &&
           route.dig("external_effect_authority", "provider") == false &&
           route.dig("external_effect_authority", "secret") == false &&
           route.dig("external_effect_authority", "credential") == false &&
           route.dig("external_effect_authority", "remote") == false &&
           route.dig("external_effect_authority", "production") == false &&
           route.dig("external_effect_authority", "public") == false &&
           route.dig("external_effect_authority", "docker_registry") == false &&
           route.dig("external_effect_authority", "docker_build") == false &&
           route["p4_entry_authorized"] == false && route["long_term_goal_status"] == "ACTIVE" &&
           route.dig("anti_loop", "governance_progress_credit") == 0,
           "P3 ETSK external-effect, P4, Goal or anti-loop drift")
    validate_stage_shape!(route, profile)

    envelope = mapping(truth["phase_execution_envelope"], "P3 ETSK Phase envelope")
    if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      terminal_index = route["ordered_stages"].index { |stage| stage["status"].start_with?("TERMINAL") }
      terminal_count = terminal_index + 1
      terminal_profile = profile.merge("consumed_count" => terminal_count, "reserved_index" => nil)
      consumed, reserved, remaining = expected_accounting(terminal_profile)
      delivery = terminal_index < 2 ? 25 : 75
      strict = 0
    else
      consumed, reserved, remaining = expected_accounting(profile)
      delivery = profile.fetch("delivery")
      strict = profile.fetch("strict")
    end
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" &&
           envelope["phase"] == "P3" && envelope.dig("authority_basis", "source_route_id") == ROUTE_ID &&
           envelope["accounting_basis"] == "NON_RESETTABLE_CUMULATIVE_P3_FOUNDER_ENVELOPE" &&
           envelope["limits"] == LIMITS && envelope["consumed"] == consumed &&
           envelope["reserved"] == reserved && envelope["remaining"] == remaining &&
           envelope.dig("delivery_progress", "percent") == delivery &&
           envelope.dig("delivery_progress", "strict_exit_gate_percent") == strict &&
           envelope["governance_progress_credit"] == 0,
           "P3 ETSK Phase envelope accounting or progress drift")

    control = mapping(truth["founder_escalation_control"], "P3 ETSK Founder escalation")
    expected_disposition = profile.fetch("founder_required") ?
      "FOUNDER_RESERVED_DECISION_REQUIRED" : "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == expected_disposition &&
           control["founder_decision_required"] == profile.fetch("founder_required") &&
           control["next_action_owner"] == (profile.fetch("founder_required") ? "HUMAN_FOUNDER" : "MASTER_CEO_AGENT") &&
           control["next_eligible_action"] == profile.fetch("action"),
           "P3 ETSK Founder interruption projection drift")
    delegation = mapping(truth["phase_delegation"], "P3 ETSK Phase delegation")
    assert(delegation["decision_source"] == DECISION_ID &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation.dig("anti_loop", "foundation_2_allowed") == false &&
           delegation.dig("anti_loop", "candidate_3_allowed") == false &&
           delegation.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           delegation.dig("anti_loop", "third_review_cycle_allowed") == false &&
           delegation.dig("anti_loop", "second_formal_dispatch_allowed") == false,
           "P3 ETSK Phase delegation or anti-loop drift")
    boundary = mapping(truth["phase_boundary"], "P3 ETSK Phase boundary")
    if lifecycle == "FOUNDATION_ELIGIBLE_NOT_ACTIVATED"
      assert(boundary["phase"] == "P3" &&
             boundary["phase_execution_status"] == "ACTIVE_P3_ETSK_FOUNDATION_ELIGIBLE" &&
             boundary["task_creation_allowed"] == true &&
             boundary["task_creation_scope"] == "EXACT_AIOS_P3_ETSK_F1_FOUNDATION_ONLY" &&
             boundary["allowed_task_kinds"] == ["EVALUATION_FOUNDATION"] &&
             boundary["allowed_capabilities"] == %w[
               EXECUTABLE_TRANSITION_SYSTEM_KERNEL_SPEC
               INTERPRETER_TRANSITION_RELATION_ONLY
               FULL_TRACE_REPLAY_VERIFIER
               SEMANTIC_TAMPER_MUTATION_MATRIX
             ] && boundary["founder_decision_required"] == false &&
             boundary["user_action_required"] == "NONE" &&
             boundary["next_eligible_action"] == profile.fetch("action") &&
             boundary.dig("default_external_effects", "docker") == false &&
             boundary.dig("default_external_effects", "network") == false &&
             boundary.dig("default_external_effects", "provider") == false &&
             boundary.dig("default_external_effects", "secret") == false &&
             boundary.dig("default_external_effects", "remote") == false &&
             boundary.dig("default_external_effects", "production") == false &&
             boundary.dig("default_external_effects", "public") == false &&
             boundary.dig("default_external_effects", "p4_entry") == false,
             "P3 ETSK Foundation activation boundary drift")
    end
    assert(truth.dig("claim_boundary", "p3_phase_envelope_status") == envelope["status"] &&
           truth.dig("claim_boundary", "p3_phase_envelope_status") ==
             boundary["phase_execution_status"],
           "P3 host-authorized claim boundary projection drift (P3 ETSK envelope binding)")
    validate_active_task!(root, truth, profile)

    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"), "P3 strict Gate")
    current_gate = mapping(p3["current_exit_gate"], "P3 ETSK current strict Gate")
    assert(current_gate["gate_id"] == STRICT_GATE_ID &&
           current_gate["authority"] == DECISION.merge("decision_id" => DECISION_ID) &&
           current_gate["required_item_ids"] == STRICT_ITEMS &&
           current_gate["required_items"].keys == STRICT_ITEMS &&
           current_gate["same_frozen_candidate_required"] == true,
           "P3 ETSK strict Gate shape drift")
    if lifecycle == "AUDIT_PASS_PHASE_GATE_ELIGIBLE"
      candidates = STRICT_ITEMS.map do |item|
        record = mapping(current_gate.dig("required_items", item), "P3 ETSK accepted Gate item #{item}")
        assert(record["status"] == "ACCEPTED" && record["evidence"].is_a?(Hash),
               "P3 ETSK Audit PASS lacks accepted Evidence for #{item}")
        [record["candidate_commit"], record["candidate_tree"]]
      end
      assert(candidates.uniq.length == 1 &&
             p3.dig("required_items", COMPATIBILITY_ITEM, "status") == "ACCEPTED" &&
             p3.dig("founder_phase_gate", "status") == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "P3 ETSK Audit PASS same-candidate or compatibility projection drift")
    else
      assert(STRICT_ITEMS.all? { |item| current_gate.dig("required_items", item, "status") == "MISSING" } &&
             p3.dig("required_items", COMPATIBILITY_ITEM, "status") == "MISSING" &&
             p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
             "P3 ETSK strict Gate false acceptance before one-shot Audit PASS")
    end
    assert(truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "p4_entry_status") == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_strategic_decision", "decision_id") == DECISION_ID &&
           truth.dig("claim_boundary", "current_phase_route") == ROUTE_ID &&
           truth.dig("claim_boundary", "p3_exit_gate_progress_percent") == strict &&
           truth.dig("claim_boundary", "p3_delivery_progress_percent") == delivery &&
           truth.dig("claim_boundary", "p3_etsk_route_decision_sha256") == DECISION.fetch("sha256") &&
           truth.dig("claim_boundary", "p3_etsk_candidate_integrated") == false,
           "P3 ETSK project, P4, Goal or claim projection drift")
    profile.fetch("state")
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3ExecutableTransitionSystemKernelRouteValidationError, "P3 ETSK Route invalid: #{e.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(root.join("docs/aios/truth/project_state.yaml").binread,
                           permitted_classes: [], permitted_symbols: [], aliases: false)
    if truth.dig("current_phase_route", "schema_version") ==
       P3ExecutableTransitionSystemKernelRouteValidation::ROUTE_SCHEMA
      state = P3ExecutableTransitionSystemKernelRouteValidation.validate_truth!(root: root, truth: truth)
      puts "STRICT_PHASE_GATES: PASS state=#{state}"
    else
      p3 = truth.dig("strict_phase_gate_ledger", "phases", "P3")
      raise P3ExecutableTransitionSystemKernelRouteValidationError, "P3 strict Gate is missing" unless p3.is_a?(Hash)
      puts "STRICT_PHASE_GATES: PASS state=NON_ETSK_CURRENT_ROUTE"
    end
  rescue P3ExecutableTransitionSystemKernelRouteValidationError, JSON::ParserError, Psych::SyntaxError => e
    warn "STRICT_PHASE_GATES: NON_PASS #{e.message}"
    exit 1
  end
end

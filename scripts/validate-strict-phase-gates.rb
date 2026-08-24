#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "find"
require "rubygems/package"
require "json"
require "open3"
require "pathname"
require "rexml/document"
require "stringio"
require "time"
require "tmpdir"
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

class P3DeclarativeTransactionKernelRouteValidationError < StandardError; end

module P3DeclarativeTransactionKernelRouteValidation
  module_function

  ROUTE_SCHEMA = "p3-declarative-transaction-kernel-clean-room-route/v1"
  ROUTE_ID = "P3_DECLARATIVE_TRANSACTION_KERNEL_CLEAN_ROOM_ROUTE_V1"
  DECISION_SCHEMA = "p3-declarative-transaction-kernel-founder-decision/v1"
  DECISION_ID =
    "AUTHORIZE_P3_DECLARATIVE_TRANSACTION_KERNEL_OBJECTIVE_EXIT_GATE_AND_FINDING_SCOPED_CLEAN_ROOM_ROUTE_V1"
  OPERATION_TYPE =
    "P3_DECLARATIVE_TRANSACTION_KERNEL_OBJECTIVE_EXIT_GATE_AND_FINDING_SCOPED_CLEAN_ROOM_ROUTE"
  OBJECTIVE_ID = "TRUSTED_HOST_TCB_DECLARATIVE_TRANSACTION_KERNEL_SINGLE_AGENT_EXECUTION"
  WORKFLOW_ID = "SHA256_READ_ONLY_CUSTODY_V1"
  STRICT_GATE_ID =
    "TRUSTED_HOST_TCB_DECLARATIVE_TASK_WIDE_TRANSACTIONAL_EXECUTION_WITH_PROCESS_REAL_CONTAINMENT"
  STRICT_ITEMS = %w[
    DECLARATIVE_TRANSITION_SEMANTIC_INTEGRITY_AND_INDEPENDENT_REPLAY
    TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER
    AUTHORIZATION_AND_INTENT_DURABILITY
    CRASH_ORPHAN_RECONCILIATION_AND_RESUME
    EXACTLY_ONE_TERMINAL_TRACE_AND_CHECKPOINT_GATE
    TRUSTED_HOST_TCB_PROCESS_REAL_CONTAINMENT_ATTESTATION
  ].freeze
  COMPATIBILITY_ITEM = "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"

  DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/decision/FOUNDER_P3_DTK_ACCEPTED_STRUCTURED_DECISION_V1.json",
    "byte_length" => 13_666,
    "sha256" => "e415cff79e4bd0f4784cf232ebd1358ec52b03463733967915e2611aa2de9185"
  }.freeze
  ADR = {
    "path" => "docs/aios/decisions/P3_DECLARATIVE_TRANSACTION_KERNEL_CLEAN_ROOM_ROUTE_DECISION_V1.json",
    "byte_length" => 13_666,
    "sha256" => "e415cff79e4bd0f4784cf232ebd1358ec52b03463733967915e2611aa2de9185"
  }.freeze
  AUTHORIZATION_BODY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/decision/FOUNDER_AUTHORIZATION_BODY_V1.txt",
    "byte_length" => 27_700,
    "sha256" => "5043a744078c414adf0c467ee4f34980e1d46d326260d4971728e6bdc8c99fc6"
  }.freeze
  SOURCE_ATTACHMENT = AUTHORIZATION_BODY.merge(
    "path" => "/Users/lijunpeng/.codex/attachments/bd76b71d-4f1a-410a-b16b-2ce2666171d2/pasted-text.txt"
  ).freeze
  CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "3.3",
    "byte_length" => 26_557,
    "sha256" => "86785be2944daa0f9946ccbf1d6e2ca798320d50403db23867fb04feeed4cbc0"
  }.freeze
  TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/task-foundation/terminal/P3_ETSK_F1_FOUNDATION_TASK_TERMINAL_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 5_933,
    "sha256" => "55d3c6a0189d47380cc87102cfaa48129363ada5fd68519faaaf42703a8e42f0"
  }.freeze
  INDEPENDENT_REVIEW = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/task-foundation/reviews/cycle-1/P3_ETSK_F1_QUALITY_EVALUATION_REVIEW_V1.json",
    "byte_length" => 19_956,
    "sha256" => "f3d8df1613f41d14f47a3eb84d6c96478a163e0f976bdb967da3f5bd77b95ab6"
  }.freeze
  CAPABILITY_GAP_PREFLIGHT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-executable-transition-system-kernel-reentry-20260823/task-foundation/terminal/P3_ETSK_F1_POST_TERMINAL_FOUNDER_HANDOFF_CAPABILITY_GAP_PREFLIGHT_V1.json",
    "byte_length" => 2_959,
    "sha256" => "47ae2ae57aa94a4c5108f26daa65fc90a72b3bfa82c1ca123454b36be654f7e2"
  }.freeze
  PRODUCT_TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/task-product/terminal/P3_DTK_P1_PRODUCT_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 15_047,
    "sha256" => "22c34b40854db7b1cda4c9575166a42714c4041c9aff35ba8e87cc5a68e2a50a"
  }.freeze
  PRODUCT_TERMINAL_BLOCKER_IDS = %w[
    P3-DTK-P1-C1-CTO-P0-001
    P3-DTK-P1-C1-CTO-P0-002
    P3-DTK-P1-QE-C1-P0-001
    P3-DTK-P1-QE-C1-P1-002
    P3-DTK-P1-QE-C1-P1-003
    P3-DTK-P1-QE-C1-P1-004
    P3-DTK-P1-QE-C1-P1-005
    P3-DTK-P1-C1-SEC-P1-003
    P3-DTK-P1-C2-SEC-REG-P1-001
  ].freeze
  FINDINGS = [
    { "id" => "P3-ETSK-F1-C1-P0-001", "priority" => "P0", "gate_relevance" => "EXIT_GATE_VALIDITY",
      "required_closure" => "FAILED_TERMINAL_RELEASE_REQUIRES_TERMINAL_ACCEPTED_AND_CLEANUP_CONFIRMED_AND_ZERO_CHECKPOINTS" },
    { "id" => "P3-ETSK-F1-C1-P1-002", "priority" => "P1", "gate_relevance" => "RESULT_INTEGRITY",
      "required_closure" => "REPLAY_TERMINAL_VERDICT_RECOMPUTED_FROM_STATE_RETAINED_RESULT_AND_SPEC" },
    { "id" => "P3-ETSK-F1-C1-P1-003", "priority" => "P1", "gate_relevance" => "PRODUCT_CORRECTNESS",
      "required_closure" => "MACHINE_SPEC_IS_SOLE_DOMAIN_SEMANTIC_SOURCE_FOR_FOUNDATION_AND_PRODUCT" }
  ].map(&:freeze).freeze
  FINDING_IDS = FINDINGS.map { |finding| finding.fetch("id") }.freeze
  CANONICAL_START = {
    "repository" => "/Users/lijunpeng/Developer/SourceLens-AIOS",
    "branch" => "main",
    "commit" => "e31105bb3d285c4b3c91a404526855a1628364ee",
    "tree" => "89d5d0ed9c2c8ad2983f98de4bbdc44ad86b69ae",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_980_366,
      "sha256" => "68c41e5af75a765c9d8db35f2e6aacdbcddccb3fe6b24cac5710376b28278517"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "3.2",
      "byte_length" => 20_994,
      "sha256" => "ccba174ea66d1044d63de97cd1a666139d6c886d2ebd1d790dbb59b98fb9b32a"
    },
    "git_topology" => {
      "branches" => ["main"],
      "worktrees" => ["/Users/lijunpeng/Developer/SourceLens-AIOS"]
    }
  }.freeze
  LIMITS = {
    "engineering_tasks" => 17, "engineering_hours" => 464, "calendar_days" => 110,
    "active_tasks" => 1, "task_branches" => 1, "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  BASE_CONSUMED = {
    "engineering_tasks" => 14, "engineering_hours" => 392, "calendar_days" => 94
  }.freeze
  ROUTE_RELEASE = {
    "engineering_tasks" => 3, "engineering_hours" => 72, "calendar_days" => 16
  }.freeze
  STAGE_IDS = %w[
    DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION
    TRUSTED_HOST_DECLARATIVE_TRANSACTION_KERNEL_PRODUCT
    ONE_SHOT_STRICT_EXIT_AUDIT
  ].freeze
  TASK_IDS = %w[
    AIOS-P3-DTK-F1_DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION
    AIOS-P3-DTK-P1_TRUSTED_HOST_DECLARATIVE_TRANSACTION_KERNEL_PRODUCT
    AIOS-P3-DTK-A1_ONE_SHOT_STRICT_EXIT_AUDIT
  ].freeze
  STAGE_KINDS = %w[EVALUATION_FOUNDATION PRODUCT_IMPLEMENTATION EVALUATION_ONLY].freeze
  STAGE_BUDGETS = [
    { "engineering_tasks" => 1, "engineering_hours" => 8, "calendar_days" => 2,
      "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2 },
    { "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 10,
      "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2 },
    { "engineering_tasks" => 1, "engineering_hours" => 16, "calendar_days" => 4,
      "formal_dispatches" => 1, "product_changes" => 0, "same_task_repairs" => 0,
      "rerun_to_pass_allowed" => false }
  ].map(&:freeze).freeze
  STAGE_RESOURCES = [
    {
      "branch" => "codex/p3-dtk-f1-declarative-transaction-semantics",
      "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-dtk-f1-declarative-transaction-semantics",
      "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/task-foundation"
    },
    {
      "branch" => "codex/p3-dtk-p1-trusted-host-transaction-kernel",
      "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-dtk-p1-trusted-host-transaction-kernel",
      "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/task-product"
    },
    {
      "branch" => "codex/p3-dtk-a1-one-shot-strict-exit-audit",
      "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-dtk-a1-one-shot-strict-exit-audit",
      "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/task-audit"
    }
  ].map(&:freeze).freeze
  WORKER_PATHS = [
    %w[
      evaluation-harness/harness/p3-declarative-transaction-kernel-v1
      evaluation-harness/reports/p3-declarative-transaction-kernel-v1
      docs/aios/tasks/P3-DTK-F1_DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION.yaml
      docs/PROJECT_CODE_MAP.md
    ],
    %w[
      backend-spring/src/main/java/com/sourcelens/module/execution/kernel
      backend-spring/src/main/java/com/sourcelens/module/execution/taskwide
      backend-spring/src/main/java/com/sourcelens/module/sandbox/oci/taskwide
      backend-spring/src/main/java/com/sourcelens/module/execution/service/ExecutionCheckpointService.java
      backend-spring/src/main/java/com/sourcelens/module/execution/service/ExecutionTaskService.java
      backend-spring/src/main/java/com/sourcelens/module/execution/mapper/ExecutionCheckpointStore.java
      backend-spring/src/main/resources/p3/declarative-transaction-kernel
      backend-spring/src/main/resources/db/migration/V034__add_declarative_task_wide_transaction_kernel.sql
      backend-spring/src/test/java/com/sourcelens/module/execution/kernel
      backend-spring/src/test/java/com/sourcelens/module/execution/taskwide
      backend-spring/src/test/java/com/sourcelens/module/sandbox/oci/taskwide
      backend-spring/src/test/resources/p3-declarative-transaction-kernel
      docs/aios/tasks/P3-DTK-P1_TRUSTED_HOST_DECLARATIVE_TRANSACTION_KERNEL_PRODUCT.yaml
      docs/PROJECT_CODE_MAP.md
    ],
    %w[
      docs/aios/tasks/P3-DTK-A1_ONE_SHOT_STRICT_EXIT_AUDIT.yaml
      evaluation-harness/reports/p3-declarative-transaction-kernel-audit-v1
    ]
  ].map(&:freeze).freeze

  LIFECYCLE = {
    "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" => {
      "state" => "P3_DTK_FOUNDATION_ELIGIBLE", "route_status" => "ACTIVE_FOUNDATION_ELIGIBLE",
      "phase_status" => "ACTIVE_P3_DTK_FOUNDATION_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_DTK_F1_FOUNDATION",
      "stage_statuses" => %w[ELIGIBLE_NOT_ACTIVATED LOCKED_PENDING_FOUNDATION_ACCEPTED_AND_INTEGRATED LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => nil, "completed_stage_count" => 0, "consumed_count" => 0,
      "reserved_index" => nil, "delivery" => 25, "strict" => 0, "founder_required" => false
    },
    "FOUNDATION_TASK_ACTIVE" => {
      "state" => "P3_DTK_FOUNDATION_TASK_ACTIVE", "route_status" => "ACTIVE_FOUNDATION_TASK",
      "phase_status" => "ACTIVE_P3_DTK_FOUNDATION_TASK",
      "action" => "EXECUTE_AIOS_P3_DTK_F1_FOUNDATION",
      "stage_statuses" => %w[ACTIVE LOCKED_PENDING_FOUNDATION_ACCEPTED_AND_INTEGRATED LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => 0, "completed_stage_count" => 0, "consumed_count" => 0,
      "reserved_index" => 0, "delivery" => 25, "strict" => 0, "founder_required" => false
    },
    "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE" => {
      "state" => "P3_DTK_PRODUCT_ELIGIBLE", "route_status" => "ACTIVE_PRODUCT_ELIGIBLE",
      "phase_status" => "ACTIVE_P3_DTK_PRODUCT_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_DTK_P1_PRODUCT",
      "stage_statuses" => %w[ACCEPTED_INTEGRATED ELIGIBLE_NOT_ACTIVATED LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => nil, "completed_stage_count" => 1, "consumed_count" => 1,
      "reserved_index" => nil, "delivery" => 25, "strict" => 0, "founder_required" => false
    },
    "PRODUCT_TASK_ACTIVE" => {
      "state" => "P3_DTK_PRODUCT_TASK_ACTIVE", "route_status" => "ACTIVE_PRODUCT_TASK",
      "phase_status" => "ACTIVE_P3_DTK_PRODUCT_TASK",
      "action" => "EXECUTE_AIOS_P3_DTK_P1_PRODUCT",
      "stage_statuses" => %w[ACCEPTED_INTEGRATED ACTIVE LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED],
      "active_index" => 1, "completed_stage_count" => 1, "consumed_count" => 1,
      "reserved_index" => 1, "delivery" => 25, "strict" => 0, "founder_required" => false
    },
    "PRODUCT_ACCEPTED_AUDIT_ELIGIBLE" => {
      "state" => "P3_DTK_AUDIT_ELIGIBLE", "route_status" => "ACTIVE_AUDIT_ELIGIBLE",
      "phase_status" => "ACTIVE_P3_DTK_AUDIT_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_DTK_A1_AUDIT",
      "stage_statuses" => %w[ACCEPTED_INTEGRATED ACCEPTED_INTEGRATED ELIGIBLE_NOT_ACTIVATED],
      "active_index" => nil, "completed_stage_count" => 2, "consumed_count" => 2,
      "reserved_index" => nil, "delivery" => 75, "strict" => 0, "founder_required" => false
    },
    "AUDIT_TASK_ACTIVE" => {
      "state" => "P3_DTK_AUDIT_TASK_ACTIVE", "route_status" => "ACTIVE_AUDIT_TASK",
      "phase_status" => "ACTIVE_P3_DTK_AUDIT_TASK",
      "action" => "EXECUTE_AIOS_P3_DTK_A1_ONE_SHOT_AUDIT",
      "stage_statuses" => %w[ACCEPTED_INTEGRATED ACCEPTED_INTEGRATED ACTIVE],
      "active_index" => 2, "completed_stage_count" => 2, "consumed_count" => 2,
      "reserved_index" => 2, "delivery" => 75, "strict" => 0, "founder_required" => false
    },
    "ROUTE_TERMINAL_NON_PASS" => {
      "state" => "P3_DTK_ROUTE_TERMINAL_NON_PASS",
      "route_status" => "HOLD_INCOMPLETE_ROUTE_TERMINAL_NON_PASS",
      "phase_status" => "HOLD_INCOMPLETE_P3_DTK_ROUTE_TERMINAL_NON_PASS",
      "action" => "FOUNDER_DECIDE_P3_AFTER_DTK_ROUTE_TERMINAL_NON_PASS",
      "stage_statuses" => %w[ACCEPTED_INTEGRATED TERMINAL_TASK_GATE_NON_PASS LOCKED_ROUTE_TERMINAL],
      "active_index" => nil, "completed_stage_count" => 1, "consumed_count" => 2,
      "reserved_index" => nil, "delivery" => 25, "strict" => 0,
      "remaining_capacity_usable" => false, "selected_task" => "NONE_ROUTE_TERMINAL_NON_PASS",
      "founder_required" => true
    },
    "AUDIT_PASS_PHASE_GATE_ELIGIBLE" => {
      "state" => "P3_DTK_P3_PHASE_GATE_ELIGIBLE",
      "route_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "phase_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "action" => "FOUNDER_DECIDE_P3_PHASE_EXIT",
      "stage_statuses" => %w[ACCEPTED_INTEGRATED ACCEPTED_INTEGRATED ACCEPTED],
      "active_index" => nil, "completed_stage_count" => 3, "consumed_count" => 3,
      "reserved_index" => nil, "delivery" => 100, "strict" => 100, "founder_required" => true
    }
  }.freeze
  LIFECYCLE_STATES = LIFECYCLE.transform_values { |profile| profile.fetch("state") }.freeze

  def assert(condition, message)
    raise P3DeclarativeTransactionKernelRouteValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} is not a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} is not an array")
    value
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
    mapping(JSON.parse(bytes), label)
  rescue JSON::ParserError => e
    raise P3DeclarativeTransactionKernelRouteValidationError, "#{label} invalid JSON: #{e.message}"
  end

  def git!(root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    assert(status.success?, "git #{args.join(' ')} failed: #{stderr.strip}")
    stdout.strip
  end

  def expected_accounting(profile)
    consumed = BASE_CONSUMED.dup
    profile.fetch("consumed_count").times do |index|
      %w[engineering_tasks engineering_hours calendar_days].each do |key|
        consumed[key] += STAGE_BUDGETS.fetch(index).fetch(key)
      end
    end
    reserved = if profile["reserved_index"]
                 STAGE_BUDGETS.fetch(profile.fetch("reserved_index")).slice(
                   "engineering_tasks", "engineering_hours", "calendar_days"
                 )
               end
    remaining = %w[engineering_tasks engineering_hours calendar_days].to_h do |key|
      [key, LIMITS.fetch(key) - consumed.fetch(key) - (reserved&.fetch(key) || 0)]
    end
    [consumed, reserved, remaining]
  end

  def validate_decision!(root)
    adr_bytes = read_identity!(root, ADR, "P3 DTK canonical ADR")
    staging = ENV["SOURCELENS_DTK_STRATEGIC_STAGING_ROOT"]
    external_path = path_for(root, DECISION)
    external_bytes = if staging && !external_path.exist?
                       adr_bytes
                     else
                       read_identity!(root, DECISION, "P3 DTK Founder decision", create_once: true)
                     end
    assert(external_bytes == adr_bytes, "P3 DTK external decision and canonical ADR differ")
    attachment = read_identity!(root, SOURCE_ATTACHMENT, "P3 DTK direct attachment")
    body_path = path_for(root, AUTHORIZATION_BODY)
    body = if staging && !body_path.exist?
             attachment
           else
             read_identity!(root, AUTHORIZATION_BODY, "P3 DTK authorization body", create_once: true)
           end
    assert(body == attachment, "P3 DTK installed authorization body differs from attachment")
    assert(body.dup.force_encoding(Encoding::UTF_8).valid_encoding? &&
           body.lines.first&.chomp == DECISION_ID,
           "P3 DTK authorization token or UTF-8 identity drift")
    decision = parse_json!(external_bytes, "P3 DTK Founder decision")
    assert(decision["schema_version"] == DECISION_SCHEMA &&
           decision["record_type"] == "FOUNDER_ACCEPTED_STRATEGIC_DECISION" &&
           decision["decision_id"] == DECISION_ID && decision["operation_type"] == OPERATION_TYPE &&
           decision["status"] == "ACCEPTED_CURRENT_DIRECT_FOUNDER_MESSAGE",
           "P3 DTK Founder decision header drift")
    assert(decision.dig("source", "byte_length") == AUTHORIZATION_BODY.fetch("byte_length") &&
           decision.dig("source", "sha256") == AUTHORIZATION_BODY.fetch("sha256") &&
           decision.dig("source", "installed_body", "path") == AUTHORIZATION_BODY.fetch("path") &&
           decision.dig("source", "installed_body", "byte_equal_to_attachment") == true,
           "P3 DTK source-body binding drift")
    assert(decision["canonical_start"] == CANONICAL_START.merge("clean" => true),
           "P3 DTK canonical-start binding drift")
    terminal_basis = mapping(decision["terminal_basis"], "P3 DTK terminal basis")
    assert(terminal_basis["route_id"] == "P3_EXECUTABLE_TRANSITION_SYSTEM_KERNEL_REENTRY_ROUTE_V1" &&
           terminal_basis["status"] == "ROUTE_TERMINAL_NON_PASS" &&
           terminal_basis["terminal_receipt"] == TERMINAL_RECEIPT &&
           terminal_basis["independent_review"].slice("path", "byte_length", "sha256") == INDEPENDENT_REVIEW &&
           terminal_basis["handoff_capability_gap_preflight"].slice("path", "byte_length", "sha256") == CAPABILITY_GAP_PREFLIGHT,
           "P3 DTK terminal basis drift")
    assert(decision.dig("authority", "one_time_handoff_validator_bypass_consumed_for_intake_only") == true &&
           decision.dig("authority", "generic_validator_bypass_authorized") == false,
           "P3 DTK one-time validator-gap boundary drift")
    assert(decision.dig("strategic_change", "constitution_to_version") == "3.3" &&
           decision.dig("strategic_change", "append_only_section") == "9C" &&
           decision.dig("strategic_change", "objective_id") == OBJECTIVE_ID &&
           decision.dig("strategic_change", "strict_exit_gate_id") == STRICT_GATE_ID &&
           decision.dig("strategic_change", "required_gate_items") == STRICT_ITEMS &&
           decision.dig("strategic_change", "compatibility_aggregate_item_id") == COMPATIBILITY_ITEM &&
           decision.dig("strategic_change", "same_frozen_product_candidate_required") == true,
           "P3 DTK strategic Gate drift")
    assert(decision["frozen_findings"] == FINDINGS,
           "P3 DTK frozen finding set drift")
    assert(decision.dig("rejected_lineage", "read_compare_copy_execute_restore_repair_or_reuse_rejected_bytes") == false &&
           decision.dig("rejected_lineage", "earlier_rejected_p3_engineering_lineage_allowed") == false,
           "P3 DTK rejected-lineage boundary drift")
    assert(decision.dig("route", "route_id") == ROUTE_ID &&
           decision.dig("route", "cumulative_consumed") == BASE_CONSUMED &&
           decision.dig("route", "cumulative_ceiling") == LIMITS.slice(
             "engineering_tasks", "engineering_hours", "calendar_days"
           ) && decision.dig("route", "released_for_route") == ROUTE_RELEASE,
           "P3 DTK cumulative accounting drift")
    stages = array(decision.dig("route", "stages"), "P3 DTK decision stages")
    assert(stages.length == 3, "P3 DTK decision stage count drift")
    stages.each_with_index do |stage, index|
      assert(stage["ordinal"] == index + 1 && stage["stage_id"] == STAGE_IDS[index] &&
             stage["task_id"] == TASK_IDS[index] && stage["kind"] == STAGE_KINDS[index] &&
             stage["budget"] == STAGE_BUDGETS[index] && stage["resources"] == STAGE_RESOURCES[index],
             "P3 DTK decision stage #{index + 1} drift")
    end
    assert(decision.dig("foundation_acceptance", "required_positive_scenarios") == 10 &&
           decision.dig("foundation_acceptance", "required_mutants_killed") == 13 &&
           decision.dig("foundation_acceptance", "required_mutants_total") == 13 &&
           decision.dig("foundation_acceptance", "false_accepts_allowed") == 0 &&
           decision.dig("foundation_acceptance", "deterministic_replays") == 2 &&
           decision.dig("foundation_acceptance", "product_source_changes_allowed") == false,
           "P3 DTK Foundation acceptance drift")
    assert(decision.dig("external_effects", "network") == false &&
           decision.dig("external_effects", "provider") == false &&
           decision.dig("external_effects", "secret") == false &&
           decision.dig("external_effects", "remote") == false &&
           decision.dig("external_effects", "production") == false &&
           decision.dig("external_effects", "public") == false &&
           decision.dig("external_effects", "p4_entry") == false &&
           decision.dig("anti_loop", "governance_progress_credit") == 0 &&
           decision.dig("lifecycle", "long_term_goal_status") == "ACTIVE" &&
           decision.dig("lifecycle", "codex_goal_completion_or_blocking_authorized") == false,
           "P3 DTK effect, anti-loop or Goal boundary drift")
    decision
  end

  def validate_terminal_basis!(root)
    terminal = parse_json!(
      read_identity!(root, TERMINAL_RECEIPT, "P3 DTK ETSK terminal receipt", create_once: true),
      "P3 DTK ETSK terminal receipt"
    )
    review = parse_json!(
      read_identity!(root, INDEPENDENT_REVIEW, "P3 DTK frozen independent review", create_once: true),
      "P3 DTK frozen independent review"
    )
    read_identity!(root, CAPABILITY_GAP_PREFLIGHT, "P3 DTK handoff capability-gap preflight", create_once: true)
    assert(terminal["record_type"] == "P3_ETSK_F1_FOUNDATION_TASK_TERMINAL_NON_PASS_RECEIPT" &&
           terminal.dig("terminal_result", "route_lifecycle") == "ROUTE_TERMINAL_NON_PASS" &&
           terminal.dig("candidate", "canonical_integration_performed") == false &&
           terminal.dig("candidate", "commit") == "d9f6c609beabae0519a3eb0cc7e3ab03a79547e6" &&
           terminal.dig("candidate", "tree") == "d2d60bebe935cfa588c7a21001b8ee273ab4a3ba" &&
           terminal.dig("candidate", "bundle", "sha256") == "8eaaaf9a084e56e81d1d2a5f7f011913290ccb0acc878670e822c32a60c13da4" &&
           terminal.dig("independent_review", "complete_frozen_findings").map { |item| item["finding_id"] } == FINDING_IDS,
           "P3 DTK predecessor terminal facts drift")
    assert(review["verdict"] == "NON_PASS" &&
           review.fetch("frozen_findings").map { |finding| finding.slice("id", "priority", "gate_relevance") } ==
             FINDINGS.map { |finding| finding.slice("id", "priority", "gate_relevance") },
           "P3 DTK frozen review finding identity drift")
  end

  def validate_repository_context!(root)
    root = Pathname.new(root).realpath
    assert(git!(root, "rev-parse", "#{CANONICAL_START.fetch('commit')}^{tree}") ==
           CANONICAL_START.fetch("tree"), "P3 DTK canonical-start tree drift")
    _stdout, _stderr, status = Open3.capture3(
      "git", "-C", root.to_s, "merge-base", "--is-ancestor", CANONICAL_START.fetch("commit"), "HEAD"
    )
    assert(status.success?, "P3 DTK canonical-start commit is not an ancestor of HEAD")
    _stdout, _stderr, rejected_status = Open3.capture3(
      "git", "-C", root.to_s, "merge-base", "--is-ancestor",
      "d9f6c609beabae0519a3eb0cc7e3ab03a79547e6", "HEAD"
    )
    assert(!rejected_status.success?, "P3 DTK rejected ETSK candidate reached canonical history")
  end

  def validate_stage_shape!(route, profile)
    stages = array(route["ordered_stages"], "P3 DTK ordered stages")
    assert(stages.length == 3, "P3 DTK stage count drift")
    stages.each_with_index do |stage, index|
      assert(stage["ordinal"] == index + 1 && stage["stage_id"] == STAGE_IDS[index] &&
             stage["task_id"] == TASK_IDS[index] && stage["kind"] == STAGE_KINDS[index] &&
             stage["status"] == profile.fetch("stage_statuses")[index] &&
             stage["budget"] == STAGE_BUDGETS[index] && stage["resources"] == STAGE_RESOURCES[index],
             "P3 DTK stage #{index + 1} identity, state or budget drift")
    end
  end

  def boundary_profile(lifecycle)
    case lifecycle
    when "FOUNDATION_ELIGIBLE_NOT_ACTIVATED"
      [true, "EXACT_AIOS_P3_DTK_F1_FOUNDATION_ONLY", ["EVALUATION_FOUNDATION"]]
    when "FOUNDATION_TASK_ACTIVE", "PRODUCT_TASK_ACTIVE", "AUDIT_TASK_ACTIVE"
      [false, "NONE_ACTIVE_TASK_EXISTS", []]
    when "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE"
      [true, "EXACT_AIOS_P3_DTK_P1_PRODUCT_ONLY", ["PRODUCT_IMPLEMENTATION"]]
    when "PRODUCT_ACCEPTED_AUDIT_ELIGIBLE"
      [true, "EXACT_AIOS_P3_DTK_A1_AUDIT_ONLY", ["EVALUATION_ONLY"]]
    when "AUDIT_PASS_PHASE_GATE_ELIGIBLE"
      [false, "NONE_FOUNDER_PHASE_GATE_REQUIRED", []]
    else
      [false, "NONE_ROUTE_TERMINAL", []]
    end
  end

  def validate_active_work!(root, truth, profile)
    active = mapping(truth["active_work"], "P3 DTK active_work")
    index = profile["active_index"]
    if index.nil?
      expected_selected = profile["selected_task"] ||
        (profile.fetch("completed_stage_count") < 3 ?
          TASK_IDS.fetch(profile.fetch("completed_stage_count")) : "NONE")
      assert(active["current_task"] == "NONE" && active["selected_task"] == expected_selected &&
             active["current_task_contract"].nil? && active["current_execution_authorization"].nil? &&
             active["authority_record"].nil? && active["task_branch"].nil? &&
             active["task_worktree"].nil? && active["execution_evidence_root"].nil? &&
             active["founder_decision_required"] == profile.fetch("founder_required") &&
             active["next_eligible_action"] == profile.fetch("action"),
             "P3 DTK inactive Task projection drift")
      return
    end
    assert(active["current_task"] == TASK_IDS[index] && active["selected_task"] == TASK_IDS[index] &&
           active["current_task_status"] == "ACTIVE" && active["task_branch"] == STAGE_RESOURCES[index]["branch"] &&
           active["task_worktree"] == STAGE_RESOURCES[index]["worktree"] &&
           active["execution_evidence_root"] == STAGE_RESOURCES[index]["evidence_root"] &&
           active["allowlisted_paths"] == WORKER_PATHS[index] &&
           active["current_task_budget"] == STAGE_BUDGETS[index] &&
           active["founder_decision_required"] == false &&
           active["next_eligible_action"] == profile.fetch("action"),
           "P3 DTK active Task identity or scope drift")
    contract_identity = mapping(active["current_task_contract"], "P3 DTK active Contract identity")
    contract_bytes = read_identity!(root, contract_identity, "P3 DTK active Contract")
    contract = YAML.safe_load(contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(contract["task_id"] == TASK_IDS[index] && contract["status"] == "ACTIVE" &&
           contract["branch"] == STAGE_RESOURCES[index]["branch"] &&
           contract["worktree"] == STAGE_RESOURCES[index]["worktree"] &&
           contract["evidence_root"] == STAGE_RESOURCES[index]["evidence_root"] &&
           contract["write_allowlist"] == WORKER_PATHS[index] && contract["budget"] == STAGE_BUDGETS[index] &&
           contract["execution_nonce"] == active["execution_nonce"],
           "P3 DTK active Contract drift")
    authority_identity = mapping(active["authority_record"], "P3 DTK active authority identity")
    authority = parse_json!(
      read_identity!(root, authority_identity, "P3 DTK active authority", create_once: true),
      "P3 DTK active authority"
    )
    assert(authority["task_id"] == TASK_IDS[index] && authority["status"] == "ACTIVE" &&
           authority["branch"] == STAGE_RESOURCES[index]["branch"] &&
           authority["worktree"] == STAGE_RESOURCES[index]["worktree"] &&
           authority["evidence_root"] == STAGE_RESOURCES[index]["evidence_root"] &&
           authority["write_allowlist"] == WORKER_PATHS[index] &&
           authority["execution_nonce"] == active["execution_nonce"] &&
           authority["authorization_id"] == active["authorization_id"],
           "P3 DTK active authority drift")
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    route = mapping(truth["current_phase_route"], "P3 DTK current Route")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID,
           "P3 DTK Route schema or identity drift")
    lifecycle = route["lifecycle_stage"]
    profile = LIFECYCLE[lifecycle]
    assert(profile, "P3 DTK lifecycle is not closed-schema: #{lifecycle.inspect}")
    assert(profile["stage_statuses"], "P3 DTK terminal stage projection must be explicitly installed")

    validate_repository_context!(root)
    decision = validate_decision!(root)
    validate_terminal_basis!(root)
    if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      receipt = parse_json!(
        read_identity!(root, PRODUCT_TERMINAL_RECEIPT, "P3 DTK Product terminal receipt", create_once: true),
        "P3 DTK Product terminal receipt"
      )
      assert(receipt["record_type"] == "P3_DTK_P1_PRODUCT_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT" &&
             receipt.dig("task", "task_id") == TASK_IDS[1] &&
             receipt.dig("candidate_history", "candidate_2", "commit") ==
               "5ff6d12451c9cfb02e3e7aef4019aea4473cfe2b" &&
             receipt.dig("candidate_history", "candidate_2", "tree") ==
               "8f03459ce1e4add821af4ddf352fe03ded483ccc" &&
             receipt.dig("candidate_history", "candidate_2", "canonical_integration_performed") == false &&
             %w[cto security quality_evaluation].all? { |role|
               receipt.dig("cycle_2_independent_reviews", role, "verdict") == "NON_PASS"
             } &&
             receipt.fetch("terminal_blocking_finding_union").map { |finding| finding["finding_id"] } ==
               PRODUCT_TERMINAL_BLOCKER_IDS &&
             receipt.dig("terminal_result", "product_task_gate") == "NON_PASS" &&
             receipt.dig("terminal_result", "task_lifecycle") == "TERMINAL_TASK_GATE_NON_PASS" &&
             receipt.dig("terminal_result", "route_lifecycle") == "ROUTE_TERMINAL_NON_PASS" &&
             receipt.dig("terminal_result", "candidate_integrated") == false &&
             receipt.dig("terminal_result", "audit_status") == "LOCKED_ROUTE_TERMINAL" &&
             receipt.dig("terminal_result", "p3_delivery_progress_percent") == 25 &&
             receipt.dig("terminal_result", "p3_strict_exit_progress_percent") == 0 &&
             receipt.dig("terminal_result", "long_term_goal_lifecycle") == "ACTIVE" &&
             receipt.dig("terminal_result", "codex_goal_action_taken") == "NONE_KEEP_ACTIVE" &&
             receipt.dig("no_auto_successor", "present") == true,
             "P3 DTK Product terminal receipt facts drift")
      assert(route["product_terminal_result"] == {
        "task_id" => TASK_IDS[1],
        "status" => "TERMINAL_TASK_GATE_NON_PASS",
        "candidate_commit" => "5ff6d12451c9cfb02e3e7aef4019aea4473cfe2b",
        "candidate_tree" => "8f03459ce1e4add821af4ddf352fe03ded483ccc",
        "candidate_integrated" => false,
        "review_verdicts" => {
          "cto" => "NON_PASS", "security" => "NON_PASS", "quality_evaluation" => "NON_PASS"
        },
        "blocker_count" => PRODUCT_TERMINAL_BLOCKER_IDS.length,
        "receipt" => PRODUCT_TERMINAL_RECEIPT
      }, "P3 DTK Product terminal projection drift")
    end
    constitution = read_identity!(root, CONSTITUTION, "P3 DTK Strategic Constitution v3.3")
    assert(constitution.include?("## 9C. P3 v3.3 declarative transaction kernel authority") &&
           constitution.include?("`#{OBJECTIVE_ID}`") && constitution.include?("`#{STRICT_GATE_ID}`") &&
           STRICT_ITEMS.all? { |item| constitution.include?("`#{item}`") },
           "P3 DTK Constitution semantic anchor drift")

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
           route.dig("strict_exit_gate", "compatibility_aggregate_item_id") == COMPATIBILITY_ITEM &&
           route.dig("strict_exit_gate", "same_frozen_product_candidate_required") == true &&
           route["frozen_findings"] == FINDINGS &&
           route["rejected_lineage"] == decision["rejected_lineage"] &&
           route["foundation_acceptance"] == decision["foundation_acceptance"] &&
           route["product_acceptance"] == decision["product_acceptance"] &&
           route["audit_acceptance"] == decision["audit_acceptance"] &&
           route["toolchain"] == decision["toolchain"] && route["anti_loop"] == decision["anti_loop"],
           "P3 DTK Route authority, Gate, finding or clean-room projection drift")
    assert(route.dig("cumulative_accounting", "limits") == LIMITS &&
           route.dig("cumulative_accounting", "consumed") == BASE_CONSUMED &&
           route.dig("cumulative_accounting", "remaining") == ROUTE_RELEASE &&
           route.dig("cumulative_accounting", "reset_or_refund_allowed") == false,
           "P3 DTK installed cumulative accounting drift")
    assert(route.dig("external_effect_authority", "docker_for_active_foundation_task") == false &&
           route.dig("external_effect_authority", "network") == false &&
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
           "P3 DTK external-effect, P4, Goal or anti-loop drift")
    validate_stage_shape!(route, profile)

    consumed, reserved, remaining = expected_accounting(profile)
    envelope = mapping(truth["phase_execution_envelope"], "P3 DTK Phase envelope")
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" && envelope["phase"] == "P3" &&
           envelope["status"] == profile.fetch("phase_status") &&
           envelope.dig("authority_basis", "source_route_id") == ROUTE_ID &&
           envelope["accounting_basis"] == "NON_RESETTABLE_CUMULATIVE_P3_FOUNDER_ENVELOPE" &&
           envelope["limits"] == LIMITS && envelope["consumed"] == consumed &&
           envelope["reserved"] == (reserved || {}) && envelope["remaining"] == remaining &&
           envelope["remaining_capacity_usable"] == profile.fetch("remaining_capacity_usable", true) &&
           envelope["ordered_stages"] == route["ordered_stages"] &&
           envelope.dig("delivery_progress", "percent") == profile.fetch("delivery") &&
           envelope.dig("delivery_progress", "strict_exit_gate_percent") == profile.fetch("strict") &&
           envelope["governance_progress_credit"] == 0,
           "P3 DTK Phase envelope accounting or progress drift")
    assert(truth.dig("claim_boundary", "p3_phase_envelope_status") == envelope["status"],
           "P3 host-authorized claim boundary projection drift (P3 DTK envelope binding)")

    control = mapping(truth["founder_escalation_control"], "P3 DTK Founder escalation")
    expected_disposition = profile.fetch("founder_required") ?
      "FOUNDER_RESERVED_DECISION_REQUIRED" : "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == expected_disposition &&
           control["founder_decision_required"] == profile.fetch("founder_required") &&
           control["next_action_owner"] == (profile.fetch("founder_required") ? "HUMAN_FOUNDER" : "MASTER_CEO_AGENT") &&
           control["next_eligible_action"] == profile.fetch("action"),
           "P3 DTK Founder interruption projection drift")
    if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      assert(control["reserved_trigger"] == {
        "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
        "evidence" => PRODUCT_TERMINAL_RECEIPT
      }, "P3 DTK terminal Founder reserved-trigger evidence drift")
    end
    delegation = mapping(truth["phase_delegation"], "P3 DTK Phase delegation")
    assert(delegation["decision_source"] == DECISION_ID &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation.dig("anti_loop", "dtk_foundation_2_allowed") == false &&
           delegation.dig("anti_loop", "second_dtk_product_task_allowed") == false &&
           delegation.dig("anti_loop", "candidate_3_allowed") == false &&
           delegation.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           delegation.dig("anti_loop", "third_review_cycle_allowed") == false &&
           delegation.dig("anti_loop", "second_formal_audit_allowed") == false,
           "P3 DTK Phase delegation or anti-loop drift")
    boundary = mapping(truth["phase_boundary"], "P3 DTK Phase boundary")
    task_creation_allowed, task_creation_scope, task_kinds = boundary_profile(lifecycle)
    assert(boundary["phase"] == "P3" && boundary["phase_execution_status"] == profile.fetch("phase_status") &&
           boundary["task_creation_allowed"] == task_creation_allowed &&
           boundary["task_creation_scope"] == task_creation_scope &&
           boundary["allowed_task_kinds"] == task_kinds &&
           boundary["founder_decision_required"] == profile.fetch("founder_required") &&
           boundary["next_eligible_action"] == profile.fetch("action") &&
           boundary.dig("default_external_effects", "network") == false &&
           boundary.dig("default_external_effects", "provider") == false &&
           boundary.dig("default_external_effects", "secret") == false &&
           boundary.dig("default_external_effects", "remote") == false &&
           boundary.dig("default_external_effects", "production") == false &&
           boundary.dig("default_external_effects", "public") == false &&
           boundary.dig("default_external_effects", "p4_entry") == false,
           "P3 DTK Phase boundary drift")
    claim = mapping(truth["phase_execution_claim"], "P3 DTK Phase execution claim")
    assert(claim["current_route_claim"] == ROUTE_ID &&
           claim["current_task_claim"] == (profile["active_index"].nil? ? "NONE" : TASK_IDS[profile["active_index"]]) &&
           claim["task_creation_allowed"] == task_creation_allowed &&
           claim["remaining_capacity_usable"] == profile.fetch("remaining_capacity_usable", true) &&
           claim["candidate_integration_allowed"] == false &&
           claim["next_eligible_action"] == profile.fetch("action"),
           "P3 DTK Phase execution claim drift")
    validate_active_work!(root, truth, profile)

    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"), "P3 strict Gate")
    current_gate = mapping(p3["current_exit_gate"], "P3 DTK current strict Gate")
    assert(current_gate["gate_id"] == STRICT_GATE_ID &&
           current_gate["authority"] == DECISION.merge("decision_id" => DECISION_ID) &&
           current_gate["required_item_ids"] == STRICT_ITEMS &&
           current_gate["required_items"].keys == STRICT_ITEMS &&
           current_gate["same_frozen_candidate_required"] == true,
           "P3 DTK strict Gate shape drift")
    if lifecycle == "AUDIT_PASS_PHASE_GATE_ELIGIBLE"
      candidates = STRICT_ITEMS.map do |item|
        record = mapping(current_gate.dig("required_items", item), "P3 DTK accepted Gate item #{item}")
        assert(record["status"] == "ACCEPTED" && record["evidence"].is_a?(Hash),
               "P3 DTK Audit PASS lacks accepted Evidence for #{item}")
        [record["candidate_commit"], record["candidate_tree"]]
      end
      assert(candidates.uniq.length == 1 &&
             p3.dig("required_items", COMPATIBILITY_ITEM, "status") == "ACCEPTED" &&
             p3.dig("founder_phase_gate", "status") == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "P3 DTK Audit PASS same-candidate or compatibility projection drift")
    else
      assert(STRICT_ITEMS.all? { |item| current_gate.dig("required_items", item, "status") == "MISSING" } &&
             p3.dig("required_items", COMPATIBILITY_ITEM, "status") == "MISSING" &&
             p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
             "P3 DTK strict Gate false acceptance before one-shot Audit PASS")
    end
    assert(truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "phase_execution_status") == profile.fetch("phase_status") &&
           truth.dig("project", "current_route_execution_status") == profile.fetch("state") &&
           truth.dig("project", "p4_entry_status") == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_strategic_decision", "decision_id") == DECISION_ID &&
           truth.dig("claim_boundary", "current_phase_route") == ROUTE_ID &&
           truth.dig("claim_boundary", "p3_phase_envelope_status") == profile.fetch("phase_status") &&
           truth.dig("claim_boundary", "p3_exit_gate_progress_percent") == profile.fetch("strict") &&
           truth.dig("claim_boundary", "p3_delivery_progress_percent") == profile.fetch("delivery") &&
           truth.dig("claim_boundary", "p3_dtk_route_decision_sha256") == DECISION.fetch("sha256") &&
           truth.dig("claim_boundary", "p3_dtk_candidate_integrated") == false,
           "P3 DTK project, P4, Goal or claim projection drift")
    profile.fetch("state")
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3DeclarativeTransactionKernelRouteValidationError, "P3 DTK Route invalid: #{e.message}"
  end
end

class P3TrustedReadOnlyInvocationVerticalSliceRouteValidationError < StandardError; end

module P3TrustedReadOnlyInvocationVerticalSliceRouteValidation
  module_function

  ROUTE_SCHEMA = "p3-trusted-read-only-invocation-vertical-slice-route/v1"
  ROUTE_ID = "P3_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE_ROUTE_V1"
  DECISION_SCHEMA = "p3-trusted-read-only-invocation-vertical-slice-founder-decision/v1"
  DECISION_ID =
    "AUTHORIZE_P3_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE_OBJECTIVE_EXIT_GATE_AND_FINAL_ROUTE_REBASELINE_AFTER_DTK_TERMINAL_V1"
  OPERATION_TYPE =
    "P3_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE_OBJECTIVE_EXIT_GATE_AND_FINAL_ROUTE_REBASELINE_AFTER_DTK_TERMINAL"
  OBJECTIVE_ID = "ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE"
  WORKFLOW_ID = "SHA256_READ_ONLY_CUSTODY_V1"
  CLAIM_BOUNDARY =
    "ONE_ACTUAL_FIXED_READ_ONLY_AGENT_TO_TRUSTED_HOST_INVOCATION_ON_TRUSTED_SINGLE_USER_LOCAL_HOST"
  STRICT_GATE_ID = "ACTUAL_AGENT_TO_TRUSTED_HOST_READ_ONLY_INVOCATION_WITH_AUTOMATIC_RECOVERY"
  STRICT_ITEMS = %w[
    ACTUAL_AGENT_INGRESS_EXCLUSIVE_TRUSTED_READ_ONLY_ROUTE
    HOST_DERIVED_AUTHORITY_DURABLE_INTENT_AND_EXACTLY_ONE_TERMINAL
    AUTOMATIC_FRESH_HOST_DISCOVERY_AND_CRASH_RECOVERY
    PINNED_LOCAL_OCI_HOSTILE_CONTEXT_AND_REAL_MYSQL_PRODUCT_PATH_ATTESTATION
  ].freeze
  COMPATIBILITY_ITEM = "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"
  TASK_ID = "AIOS-P3-TRIVS-P1_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE"
  MILESTONE_ID = "TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE_PRODUCT"

  DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-read-only-invocation-vertical-slice-20260823/decision/FOUNDER_P3_TRIVS_ACCEPTED_STRUCTURED_DECISION_V1.json",
    "byte_length" => 11_896,
    "sha256" => "dfbd602ce7ab8823e835ecffbe96bf462491071874e3a726fa52ed1b62294dd2"
  }.freeze
  ADR = DECISION.merge(
    "path" => "docs/aios/decisions/P3_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE_ROUTE_DECISION_V1.json"
  ).freeze
  AUTHORIZATION_BODY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-read-only-invocation-vertical-slice-20260823/decision/FOUNDER_AUTHORIZATION_BODY_V1.txt",
    "byte_length" => 14_575,
    "sha256" => "68eeccc6af1070f06a1a4f343f08e17c4f8b16c521affe0250512cd3cfdf23ce"
  }.freeze
  SOURCE_ATTACHMENT = {
    "path" => "/Users/lijunpeng/.codex/attachments/311f4929-d686-4b83-9f95-cdffe30158c8/pasted-text.txt",
    "byte_length" => 14_574,
    "sha256" => "1ee526766e232fbc6b434c661ed81ea4cfd8b5ce94f0317b5ae02126ff174527"
  }.freeze
  TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/task-product/terminal/P3_DTK_P1_PRODUCT_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 15_047,
    "sha256" => "22c34b40854db7b1cda4c9575166a42714c4041c9aff35ba8e87cc5a68e2a50a"
  }.freeze
  CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "3.4",
    "byte_length" => 32_657,
    "sha256" => "063363c85f8967f78529abef6c777180766ec64e25b562863cfc2f9aecada2a8"
  }.freeze
  CANONICAL_START = {
    "repository" => "/Users/lijunpeng/Developer/SourceLens-AIOS",
    "branch" => "main",
    "commit" => "98090adc539199791ff0084b1e7b94de84e32f27",
    "tree" => "d7aebf4b822eb9b4d47d736093fdb203e08a42e8",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 2_017_937,
      "sha256" => "d794fa327cb7700bafd29e77f73645d8db8b6fb1e1009abeb1bdebf703b79b19"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "3.3",
      "byte_length" => 26_557,
      "sha256" => "86785be2944daa0f9946ccbf1d6e2ca798320d50403db23867fb04feeed4cbc0"
    },
    "git_topology" => {
      "branches" => ["main"],
      "worktrees" => ["/Users/lijunpeng/Developer/SourceLens-AIOS"]
    }
  }.freeze
  LIMITS = {
    "engineering_tasks" => 17, "engineering_hours" => 496, "calendar_days" => 116,
    "active_tasks" => 1, "task_branches" => 1, "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  BASE_CONSUMED = {
    "engineering_tasks" => 16, "engineering_hours" => 448, "calendar_days" => 106
  }.freeze
  TASK_BUDGET = {
    "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 10,
    "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
  }.freeze
  ROUTE_RELEASE = TASK_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days").freeze
  RESOURCES = {
    "branch" => "codex/p3-trivs-p1-actual-agent-trusted-read-only-invocation",
    "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-trivs-p1-actual-agent-trusted-read-only-invocation",
    "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-read-only-invocation-vertical-slice-20260823/task-product"
  }.freeze
  WORKER_PATHS = %w[
    backend-spring/src/main/java/com/sourcelens/module/agent/service/AgentRuntime.java
    backend-spring/src/main/java/com/sourcelens/module/agent/service/AgentTaskService.java
    backend-spring/src/main/java/com/sourcelens/module/execution/service/ExecutionTaskService.java
    backend-spring/src/main/java/com/sourcelens/module/execution/trustedread
    backend-spring/src/main/java/com/sourcelens/module/sandbox/oci/trustedread
    backend-spring/src/main/resources/db/migration/V034__add_trusted_read_only_invocation_vertical_slice.sql
    backend-spring/src/test/java/com/sourcelens/module/agent/service/AgentTrustedReadInvocationIntegrationTest.java
    backend-spring/src/test/java/com/sourcelens/module/execution/trustedread
    backend-spring/src/test/java/com/sourcelens/module/sandbox/oci/trustedread
    backend-spring/src/test/resources/p3-trusted-read-only-invocation
    docs/aios/tasks/P3-TRIVS-P1_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE.yaml
    docs/PROJECT_CODE_MAP.md
  ].freeze
  TERMINAL_FINDING_IDS = %w[
    P3-DTK-P1-C1-CTO-P0-001 P3-DTK-P1-C1-CTO-P0-002 P3-DTK-P1-QE-C1-P0-001
    P3-DTK-P1-QE-C1-P1-002 P3-DTK-P1-QE-C1-P1-003 P3-DTK-P1-QE-C1-P1-004
    P3-DTK-P1-QE-C1-P1-005 P3-DTK-P1-C1-SEC-P1-003 P3-DTK-P1-C2-SEC-REG-P1-001
  ].freeze
  PERMITTED_FINDING_FIELDS = %w[finding_id severity gate_relevance summary].freeze
  FALSE_EXTERNAL_EFFECTS = %w[
    network dns http_https provider secret credential remote production public
    docker_registry docker_build irreversible_asset_removal p4_entry
  ].freeze
  DECISION_EXTERNAL_EFFECTS = %w[
    network dns http_https provider secret credential remote production public
    irreversible_asset_removal p4_entry
  ].to_h { |key| [key, false] }.freeze
  LOCAL_DOCKER_AUTHORITY = {
    "endpoint" => "unix:///Users/lijunpeng/.docker/run/docker.sock",
    "allowed_verbs" => ["version", "info", "image import", "create", "start", "wait", "inspect", "rm", "rmi"],
    "task_created_name_label_hash_bound_objects_only" => true,
    "sterile_config_closed_environment_required" => true,
    "os_network_restriction_required" => true,
    "forbidden_verbs" => ["image ls", "ps", "build", "pull", "push", "login"],
    "registry_or_remote_context_allowed" => false
  }.freeze
  LIFECYCLE = {
    "PRODUCT_ELIGIBLE_NOT_ACTIVATED" => {
      "state" => "P3_TRIVS_PRODUCT_ELIGIBLE", "route_status" => "ACTIVE_PRODUCT_ELIGIBLE",
      "phase_status" => "ACTIVE_P3_TRIVS_PRODUCT_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_TRIVS_P1_PRODUCT", "stage_status" => "ELIGIBLE_NOT_ACTIVATED",
      "task_status" => "ELIGIBLE_NOT_ACTIVATED", "active" => false,
      "task_creation_allowed" => true, "remaining_capacity_usable" => true,
      "founder_required" => false, "founder_trigger" => "NONE",
      "delivery" => 25, "strict" => 0
    },
    "PRODUCT_TASK_ACTIVE" => {
      "state" => "P3_TRIVS_PRODUCT_TASK_ACTIVE", "route_status" => "ACTIVE_PRODUCT_TASK",
      "phase_status" => "ACTIVE_P3_TRIVS_PRODUCT_TASK",
      "action" => "EXECUTE_AIOS_P3_TRIVS_P1_PRODUCT", "stage_status" => "ACTIVE",
      "task_status" => "ACTIVE", "active" => true,
      "task_creation_allowed" => false, "remaining_capacity_usable" => true,
      "founder_required" => false, "founder_trigger" => "NONE",
      "delivery" => 25, "strict" => 0
    },
    "ROUTE_TERMINAL_NON_PASS" => {
      "state" => "P3_TRIVS_ROUTE_TERMINAL_NON_PASS",
      "route_status" => "HOLD_INCOMPLETE_ROUTE_TERMINAL_NON_PASS",
      "phase_status" => "HOLD_INCOMPLETE_P3_TRIVS_ROUTE_TERMINAL_NON_PASS",
      "action" => "FOUNDER_DECIDE_P3_AFTER_TRIVS_ROUTE_TERMINAL_NON_PASS",
      "stage_status" => "TERMINAL_TASK_GATE_NON_PASS", "task_status" => "TERMINAL_TASK_GATE_NON_PASS",
      "active" => false, "task_creation_allowed" => false, "remaining_capacity_usable" => false,
      "founder_required" => true, "delivery" => 25, "strict" => 0
    },
    "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE" => {
      "state" => "P3_TRIVS_P3_PHASE_GATE_ELIGIBLE",
      "route_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "phase_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "action" => "FOUNDER_DECIDE_P3_PHASE_EXIT", "stage_status" => "ACCEPTED_INTEGRATED",
      "task_status" => "ACCEPTED_INTEGRATED", "active" => false,
      "task_creation_allowed" => false, "remaining_capacity_usable" => false,
      "founder_required" => true, "delivery" => 100, "strict" => 100
    }
  }.freeze
  LIFECYCLE_STATES = LIFECYCLE.transform_values { |profile| profile.fetch("state") }.freeze

  def assert(condition, message)
    raise P3TrustedReadOnlyInvocationVerticalSliceRouteValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} is not a mapping")
    value
  end

  def path_for(root, identity)
    path = Pathname.new(identity.fetch("path"))
    path.absolute? ? path : Pathname.new(root).join(path)
  end

  def read_identity!(root, identity, label)
    path = path_for(root, identity)
    assert(path.exist? && path.file? && !path.symlink?, "#{label} missing, non-regular or symlinked")
    bytes = path.binread
    assert(bytes.bytesize == identity.fetch("byte_length"), "#{label} byte length drift")
    assert(Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"), "#{label} SHA-256 drift")
    bytes
  end

  def validate_decision!(root)
    adr_bytes = read_identity!(root, ADR, "P3 TRIVS canonical ADR")
    decision_bytes = read_identity!(root, DECISION, "P3 TRIVS accepted external decision")
    body_bytes = read_identity!(root, AUTHORIZATION_BODY, "P3 TRIVS normalized Founder body")
    attachment_bytes = read_identity!(root, SOURCE_ATTACHMENT, "P3 TRIVS direct Founder attachment")
    read_identity!(root, TERMINAL_RECEIPT, "P3 DTK terminal receipt identity")
    assert(decision_bytes == adr_bytes, "P3 TRIVS canonical ADR differs from the accepted external decision")
    assert(body_bytes == attachment_bytes + "\n",
           "P3 TRIVS normalized Founder body differs beyond the optional trailing LF")
    decision = mapping(JSON.parse(adr_bytes), "P3 TRIVS ADR")
    assert(decision["schema_version"] == DECISION_SCHEMA &&
           decision["record_type"] == "FOUNDER_P3_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE_ROUTE_DECISION" &&
           decision["decision_id"] == DECISION_ID && decision["operation_type"] == OPERATION_TYPE &&
           decision["status"] == "ACCEPTED_DIRECT_FOUNDER_STRATEGIC_ROUTE_DECISION",
           "P3 TRIVS Founder decision header drift")
    assert(decision["reserved_triggers"] == %w[
      MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
      MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
    ], "P3 TRIVS reserved-trigger closure drift")
    assert(decision["canonical_start"] == CANONICAL_START && decision["installed_constitution"] == CONSTITUTION,
           "P3 TRIVS canonical-start or Constitution identity drift")
    strategic = mapping(decision["strategic_change"], "P3 TRIVS strategic change")
    assert(strategic["objective_id"] == OBJECTIVE_ID && strategic["workflow_id"] == WORKFLOW_ID &&
           strategic["claim_boundary"] == CLAIM_BOUNDARY &&
           strategic.dig("strict_exit_gate", "gate_id") == STRICT_GATE_ID &&
           strategic.dig("strict_exit_gate", "required_item_ids") == STRICT_ITEMS &&
           strategic.dig("strict_exit_gate", "same_frozen_candidate_required") == true &&
           strategic.dig("strict_exit_gate", "canonical_replay_required") == true,
           "P3 TRIVS objective or exact four-item Gate drift")
    route = mapping(decision["route"], "P3 TRIVS decision route")
    assert(route["route_id"] == ROUTE_ID && route["milestone_id"] == MILESTONE_ID &&
           route["task_id"] == TASK_ID && route["branch"] == RESOURCES["branch"] &&
           route["worktree"] == RESOURCES["worktree"] && route["evidence_root"] == RESOURCES["evidence_root"] &&
           route["budget"] == TASK_BUDGET && route["worker_write_allowlist"] == WORKER_PATHS &&
           route["reviewers"] == %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT] &&
           route["all_reviewers_pass_required"] == true && route["separate_audit_task"] == false,
           "P3 TRIVS one-Task route, budget, allowlist or review boundary drift")
    accounting = mapping(decision["cumulative_accounting"], "P3 TRIVS accounting")
    assert(accounting["limits"] == LIMITS && accounting["consumed_before_route"] == BASE_CONSUMED &&
           accounting["route_release"] == ROUTE_RELEASE && accounting["reset_or_refund_allowed"] == false &&
           accounting["governance_progress_credit"] == 0,
           "P3 TRIVS non-resettable accounting drift")
    clean = mapping(decision["clean_room"], "P3 TRIVS clean-room boundary")
    assert(clean["rejected_candidate_1_or_2_source_read_compare_copy_execute_restore_repair_or_reuse"] == false &&
           clean["rejected_branch_worktree_bundle_patch_archive_or_engineering_evidence_read"] == false &&
           clean["permitted_terminal_finding_fields"] == PERMITTED_FINDING_FIELDS,
           "P3 TRIVS rejected-lineage or finding-field boundary drift")
    terminal = mapping(decision["terminal_basis"], "P3 TRIVS terminal finding projection")
    findings = terminal["findings"]
    assert(terminal["route_id"] == P3DeclarativeTransactionKernelRouteValidation::ROUTE_ID &&
           terminal["task_status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           terminal["route_status"] == "ROUTE_TERMINAL_NON_PASS" &&
           terminal["receipt"] == TERMINAL_RECEIPT &&
           terminal["finding_projection_fields"] == PERMITTED_FINDING_FIELDS &&
           findings.is_a?(Array) && findings.map { |finding| finding.keys }.
             all? { |keys| keys == PERMITTED_FINDING_FIELDS } &&
           findings.map { |finding| finding["finding_id"] } == TERMINAL_FINDING_IDS,
           "P3 TRIVS terminal metadata exceeds the permitted clean-room projection")
    assert(decision["local_docker_authority"] == LOCAL_DOCKER_AUTHORITY &&
           decision["external_effects"] == DECISION_EXTERNAL_EFFECTS,
           "P3 TRIVS Docker or forbidden external-effect decision boundary drift")
    lifecycle = mapping(decision["lifecycle"], "P3 TRIVS lifecycle")
    %w[candidate_3_allowed second_same_task_repair_allowed third_review_cycle_allowed
       second_product_task_allowed successor_replacement_normalization_closure_feasibility_remediation_allowed
       v2_v3_route_or_rerun_to_pass_allowed].each do |key|
      assert(lifecycle[key] == false, "P3 TRIVS anti-loop decision drift at #{key}")
    end
    assert(lifecycle["installation_state"] == "PRODUCT_ELIGIBLE_NOT_ACTIVATED" &&
           lifecycle["long_term_goal_status"] == "ACTIVE",
           "P3 TRIVS installed lifecycle or Long-term Goal drift")
    decision
  rescue JSON::ParserError => e
    raise P3TrustedReadOnlyInvocationVerticalSliceRouteValidationError,
          "P3 TRIVS canonical ADR invalid JSON: #{e.message}"
  end

  def expected_accounting(profile)
    reserved = profile.fetch("active") ? ROUTE_RELEASE : {}
    remaining = %w[engineering_tasks engineering_hours calendar_days].to_h do |key|
      [key, LIMITS.fetch(key) - BASE_CONSUMED.fetch(key) - (reserved[key] || 0)]
    end
    remaining = ROUTE_RELEASE if !profile.fetch("active") && profile.fetch("remaining_capacity_usable")
    [reserved, remaining]
  end

  def validate_active_work!(truth, profile)
    active = mapping(truth["active_work"], "P3 TRIVS active_work")
    if profile.fetch("active")
      assert(active["current_task"] == TASK_ID && active["selected_task"] == TASK_ID &&
             active["current_task_status"] == "ACTIVE" && active["task_branch"] == RESOURCES["branch"] &&
             active["task_worktree"] == RESOURCES["worktree"] &&
             active["execution_evidence_root"] == RESOURCES["evidence_root"] &&
             active["allowlisted_paths"] == WORKER_PATHS && active["current_task_budget"] == TASK_BUDGET &&
             active["execution_nonce"].is_a?(String) && !active["execution_nonce"].empty? &&
             active["current_task_contract"].is_a?(Hash) && active["authority_record"].is_a?(Hash),
             "P3 TRIVS active Product Task identity, authority, budget or allowlist drift")
    else
      expected_selected = profile.fetch("founder_required") ? "NONE_ROUTE_TERMINAL_NON_PASS" : TASK_ID
      assert(active["current_task"] == "NONE" && active["selected_task"] == expected_selected &&
             active["current_task_contract"].nil? && active["current_execution_authorization"].nil? &&
             active["authority_record"].nil? && active["task_branch"].nil? &&
             active["task_worktree"].nil? && active["execution_evidence_root"].nil?,
             "P3 TRIVS inactive Task projection drift") unless profile.fetch("strict") == 100
    end
    assert(active["founder_decision_required"] == profile.fetch("founder_required") &&
           active["next_eligible_action"] == profile.fetch("action"),
           "P3 TRIVS active-work control projection drift")
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    route = mapping(truth["current_phase_route"], "P3 TRIVS current Route")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID,
           "P3 TRIVS Route schema or identity drift")
    lifecycle = route["lifecycle_stage"]
    profile = LIFECYCLE[lifecycle]
    assert(profile, "P3 TRIVS lifecycle is not closed-schema: #{lifecycle.inspect}")
    decision = validate_decision!(root)
    constitution = read_identity!(root, CONSTITUTION, "P3 TRIVS Strategic Constitution v3.4")
    assert(constitution.include?("## 9D. P3 v3.4 actual trusted read-only invocation vertical slice authority") &&
           constitution.include?("`#{OBJECTIVE_ID}`") && constitution.include?("`#{STRICT_GATE_ID}`") &&
           STRICT_ITEMS.all? { |item| constitution.include?("`#{item}`") },
           "P3 TRIVS Constitution semantic anchor drift")

    assert(route["status"] == profile.fetch("route_status") && route["phase"] == "P3" &&
           route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == profile.fetch("founder_required") &&
           route["next_eligible_action"] == profile.fetch("action") &&
           route["founder_route_decision"] == DECISION.merge(
             "decision_id" => DECISION_ID, "operation_type" => OPERATION_TYPE,
             "canonical_adr" => ADR, "source_body" => AUTHORIZATION_BODY,
             "source_attachment" => SOURCE_ATTACHMENT
           ) && route["canonical_start"] == CANONICAL_START && route["constitution"] == CONSTITUTION &&
           route["objective_id"] == OBJECTIVE_ID && route["workflow_id"] == WORKFLOW_ID &&
           route["claim_boundary"] == CLAIM_BOUNDARY &&
           route.dig("strict_exit_gate", "gate_id") == STRICT_GATE_ID &&
           route.dig("strict_exit_gate", "required_item_ids") == STRICT_ITEMS &&
           route.dig("strict_exit_gate", "compatibility_aggregate_item_id") == COMPATIBILITY_ITEM &&
           route.dig("strict_exit_gate", "same_frozen_product_candidate_required") == true &&
           route.dig("strict_exit_gate", "canonical_replay_required") == true &&
           route["terminal_finding_ids"] == TERMINAL_FINDING_IDS,
           "P3 TRIVS Route authority, identity, claim or exact Gate drift")
    assert(route.dig("cumulative_accounting", "limits") == LIMITS &&
           route.dig("cumulative_accounting", "consumed") == BASE_CONSUMED &&
           route.dig("cumulative_accounting", "remaining") == ROUTE_RELEASE &&
           route.dig("cumulative_accounting", "reset_or_refund_allowed") == false,
           "P3 TRIVS installed accounting projection drift")
    assert(route["ordered_stages"] == [{
      "ordinal" => 17, "stage_id" => MILESTONE_ID, "task_id" => TASK_ID,
      "kind" => "PRODUCT_IMPLEMENTATION", "status" => profile.fetch("stage_status"),
      "budget" => TASK_BUDGET, "resources" => RESOURCES
    }], "P3 TRIVS exact one-stage lifecycle drift")
    FALSE_EXTERNAL_EFFECTS.each do |key|
      assert(route.dig("external_effect_authority", key) == false,
             "P3 TRIVS external effect unexpectedly authorized: #{key}")
    end
    expected_docker = profile.fetch("active") ? true : "LOCKED_UNTIL_PRODUCT_ACTIVATION"
    assert(route.dig("external_effect_authority", "docker_for_active_product_task") == expected_docker &&
           route.dig("external_effect_authority", "docker_endpoint") ==
             "unix:///Users/lijunpeng/.docker/run/docker.sock" &&
           route.dig("clean_room", "rejected_candidate_source_or_engineering_evidence_read_allowed") == false &&
           route.dig("clean_room", "rejected_bundle_patch_archive_or_worktree_read_allowed") == false &&
           route.dig("clean_room", "permitted_terminal_finding_fields") == PERMITTED_FINDING_FIELDS &&
           route["p4_entry_authorized"] == false && route["long_term_goal_status"] == "ACTIVE",
           "P3 TRIVS Docker, clean-room, P4 or Goal boundary drift")
    %w[candidate_3_allowed second_same_task_repair_allowed third_review_cycle_allowed
       second_trivs_product_task_allowed successor_replacement_normalization_closure_feasibility_remediation_allowed
       v2_or_v3_route_chain_allowed rerun_to_pass_allowed].each do |key|
      assert(route.dig("anti_loop", key) == false, "P3 TRIVS anti-loop projection drift at #{key}")
    end
    assert(route.dig("anti_loop", "governance_progress_credit") == 0,
           "P3 TRIVS governance may not claim progress")

    reserved, remaining = expected_accounting(profile)
    envelope = mapping(truth["phase_execution_envelope"], "P3 TRIVS Phase envelope")
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" && envelope["phase"] == "P3" &&
           envelope["status"] == profile.fetch("phase_status") &&
           envelope.dig("authority_basis", "source_route_id") == ROUTE_ID &&
           envelope["limits"] == LIMITS && envelope["consumed"] == BASE_CONSUMED &&
           envelope["reserved"] == reserved && envelope["remaining"] == remaining &&
           envelope["remaining_capacity_usable"] == profile.fetch("remaining_capacity_usable") &&
           envelope["ordered_stages"] == route["ordered_stages"] &&
           envelope.dig("delivery_progress", "percent") == profile.fetch("delivery") &&
           envelope.dig("delivery_progress", "strict_exit_gate_percent") == profile.fetch("strict") &&
           envelope["governance_progress_credit"] == 0,
           "P3 TRIVS envelope, reservation or progress drift")

    control = mapping(truth["founder_escalation_control"], "P3 TRIVS Founder escalation")
    expected_disposition = profile.fetch("founder_required") ?
      "FOUNDER_RESERVED_DECISION_REQUIRED" : "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == expected_disposition &&
           control["founder_decision_required"] == profile.fetch("founder_required") &&
           control["next_action_owner"] == (profile.fetch("founder_required") ? "HUMAN_FOUNDER" : "MASTER_CEO_AGENT") &&
           control["next_eligible_action"] == profile.fetch("action"),
           "P3 TRIVS Founder-interruption projection drift")
    delegation = mapping(truth["phase_delegation"], "P3 TRIVS Phase delegation")
    assert(delegation["decision_source"] == DECISION_ID &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation.dig("anti_loop", "second_trivs_product_task_allowed") == false &&
           delegation.dig("anti_loop", "successor_or_replacement_allowed") == false &&
           delegation.dig("anti_loop", "candidate_3_allowed") == false &&
           delegation.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           delegation.dig("anti_loop", "third_review_cycle_allowed") == false &&
           delegation.dig("anti_loop", "rerun_to_pass_allowed") == false,
           "P3 TRIVS delegation or anti-loop drift")
    boundary = mapping(truth["phase_boundary"], "P3 TRIVS Phase boundary")
    assert(boundary["phase"] == "P3" && boundary["phase_execution_status"] == profile.fetch("phase_status") &&
           boundary["task_creation_allowed"] == profile.fetch("task_creation_allowed") &&
           boundary["allowed_task_kinds"] == (profile.fetch("task_creation_allowed") ? ["PRODUCT_IMPLEMENTATION"] : []) &&
           boundary["founder_decision_required"] == profile.fetch("founder_required") &&
           boundary["next_eligible_action"] == profile.fetch("action") &&
           FALSE_EXTERNAL_EFFECTS.reject { |key| key.start_with?("docker_") || key == "irreversible_asset_removal" }.all? {
             |key| boundary.dig("default_external_effects", key) == false
           }, "P3 TRIVS Phase boundary or external-effect drift")
    claim = mapping(truth["phase_execution_claim"], "P3 TRIVS Phase execution claim")
    assert(claim["current_route_claim"] == ROUTE_ID &&
           claim["current_task_claim"] == (profile.fetch("active") ? TASK_ID : "NONE") &&
           claim["task_creation_allowed"] == profile.fetch("task_creation_allowed") &&
           claim["remaining_capacity_usable"] == profile.fetch("remaining_capacity_usable") &&
           claim["candidate_integration_allowed"] == false && claim["next_eligible_action"] == profile.fetch("action"),
           "P3 TRIVS execution-claim drift")
    validate_active_work!(truth, profile)

    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"), "P3 strict Gate")
    current_gate = mapping(p3["current_exit_gate"], "P3 TRIVS current strict Gate")
    assert(current_gate["gate_id"] == STRICT_GATE_ID &&
           current_gate["authority"] == DECISION.merge("decision_id" => DECISION_ID) &&
           current_gate["required_item_ids"] == STRICT_ITEMS && current_gate["required_items"].keys == STRICT_ITEMS &&
           current_gate["same_frozen_candidate_required"] == true && current_gate["canonical_replay_required"] == true,
           "P3 TRIVS strict Gate shape drift")
    if profile.fetch("strict") == 100
      candidates = STRICT_ITEMS.map do |item|
        record = mapping(current_gate.dig("required_items", item), "P3 TRIVS accepted Gate item #{item}")
        assert(record["status"] == "ACCEPTED" && record["evidence"].is_a?(Hash),
               "P3 TRIVS phase-gate state lacks accepted Evidence for #{item}")
        [record["candidate_commit"], record["candidate_tree"]]
      end
      assert(candidates.uniq.length == 1 &&
             current_gate.dig("compatibility_projection", "status") == "ACCEPTED" &&
             p3.dig("founder_phase_gate", "status") == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "P3 TRIVS same-candidate, compatibility or Founder Gate drift")
    else
      assert(STRICT_ITEMS.all? { |item| current_gate.dig("required_items", item, "status") == "MISSING" } &&
             current_gate.dig("compatibility_projection", "status") == "MISSING" &&
             p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
             "P3 TRIVS strict Gate false acceptance before Product acceptance and replay")
    end
    assert(truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "phase_execution_status") == profile.fetch("phase_status") &&
           truth.dig("project", "current_route_execution_status") == profile.fetch("state") &&
           truth.dig("project", "p4_entry_status") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_strategic_decision", "decision_id") == DECISION_ID &&
           truth.dig("claim_boundary", "current_phase_route") == ROUTE_ID &&
           truth.dig("claim_boundary", "p3_phase_envelope_status") == profile.fetch("phase_status") &&
           truth.dig("claim_boundary", "p3_exit_gate_progress_percent") == profile.fetch("strict") &&
           truth.dig("claim_boundary", "p3_delivery_progress_percent") == profile.fetch("delivery") &&
           truth.dig("claim_boundary", "p3_trivs_route_decision_sha256") == DECISION.fetch("sha256") &&
           truth.dig("claim_boundary", "p3_trivs_candidate_integrated") == false,
           "P3 TRIVS project, P4, Goal or claim projection drift")
    profile.fetch("state")
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3TrustedReadOnlyInvocationVerticalSliceRouteValidationError,
          "P3 TRIVS Route invalid: #{e.message}"
  end
end

class P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError < StandardError; end

module P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidation
  module_function

  ROUTE_SCHEMA = "p3-trusted-read-only-invocation-evidence-first-final-route/v1"
  ROUTE_ID = "P3_TRUSTED_READ_ONLY_INVOCATION_EVIDENCE_FIRST_FINAL_CLEAN_ROOM_ROUTE_V1"
  DECISION_SCHEMA = "p3-trusted-read-only-invocation-evidence-first-final-founder-decision/v1"
  DECISION_ID =
    "AUTHORIZE_P3_TRUSTED_READ_ONLY_INVOCATION_EVIDENCE_FIRST_FINAL_CLEAN_ROOM_ROUTE_AFTER_TRIVS_TERMINAL_V1"
  OPERATION_TYPE =
    "P3_TRUSTED_READ_ONLY_INVOCATION_EVIDENCE_FIRST_FINAL_CLEAN_ROOM_ROUTE_AFTER_TRIVS_TERMINAL"
  OBJECTIVE_ID = "ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE"
  WORKFLOW_ID = "SHA256_READ_ONLY_CUSTODY_V1"
  CLAIM_BOUNDARY =
    "ONE_ACTUAL_FIXED_READ_ONLY_AGENT_TO_TRUSTED_HOST_INVOCATION_ON_TRUSTED_SINGLE_USER_LOCAL_HOST"
  STRICT_GATE_ID = "ACTUAL_AGENT_TO_TRUSTED_HOST_READ_ONLY_INVOCATION_WITH_AUTOMATIC_RECOVERY"
  STRICT_ITEMS = %w[
    ACTUAL_AGENT_INGRESS_EXCLUSIVE_TRUSTED_READ_ONLY_ROUTE
    HOST_DERIVED_AUTHORITY_DURABLE_INTENT_AND_EXACTLY_ONE_TERMINAL
    AUTOMATIC_FRESH_HOST_DISCOVERY_AND_CRASH_RECOVERY
    PINNED_LOCAL_OCI_HOSTILE_CONTEXT_AND_REAL_MYSQL_PRODUCT_PATH_ATTESTATION
  ].freeze
  COMPATIBILITY_ITEM = "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"
  F2_TASK_ID = "AIOS-P3-TRIVS-F2_CANDIDATE_BOUND_ACCEPTANCE_HARNESS"
  P2_TASK_ID = "AIOS-P3-TRIVS-P2_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_FINAL_CLEAN_ROOM_PRODUCT"
  F2_MILESTONE_ID = "TRIVS_CANDIDATE_BOUND_ACCEPTANCE_FOUNDATION"
  PRODUCT_MILESTONE_ID = "TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE_PRODUCT"

  DECISION = {
    "path" => "docs/aios/decisions/P3_TRUSTED_READ_ONLY_INVOCATION_EVIDENCE_FIRST_FINAL_CLEAN_ROOM_ROUTE_DECISION_V1.json",
    "byte_length" => 18_380,
    "sha256" => "e112556801503247b4e52e23dbc9bb9ce544d72c78affa2566bbf9121f7f4c80"
  }.freeze
  SOURCE_ATTACHMENT = {
    "path" => "/Users/lijunpeng/.codex/attachments/ff9f2112-5031-4208-9321-85051968cec7/pasted-text.txt",
    "byte_length" => 25_055,
    "sha256" => "9c6f98a9e2b4c454187b2bd7b04a61f0391877cffd4392463108b049a87722b3"
  }.freeze
  NORMALIZED_BODY = {
    "byte_length" => 25_056,
    "sha256" => "99a32b891c93841e2340ac9fbe53d42a7e53a50ee33a411afc6059cc0eb445df"
  }.freeze
  CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "3.5",
    "byte_length" => 38_846,
    "sha256" => "1faee62ecdc49d273042048f52c429b36f87c48b512b3161fd2e297263d70408"
  }.freeze
  CANONICAL_START = {
    "repository" => "/Users/lijunpeng/Developer/SourceLens-AIOS",
    "branch" => "main",
    "commit" => "b24beb3ac8423d86d752cfb5726d00f02ffeac88",
    "tree" => "952beb02643b44037f1b6e1ebcb955b8bc3133aa",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 2_008_077,
      "sha256" => "f86752fd8d3137b8aff3477a98c0ace1140368537cebd8f15fc4ef3986fbf4c0"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "3.4",
      "byte_length" => 32_657,
      "sha256" => "063363c85f8967f78529abef6c777180766ec64e25b562863cfc2f9aecada2a8"
    },
    "git_topology" => {
      "branches" => ["main"],
      "worktrees" => ["/Users/lijunpeng/Developer/SourceLens-AIOS"]
    }
  }.freeze
  TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-read-only-invocation-vertical-slice-20260823/task-product/terminal/P3_TRIVS_P1_PRODUCT_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 7_469,
    "sha256" => "da4ec96ee559fcce19b826985627edfceaea2a8d646ca7574b46a08d6e8f8ebe"
  }.freeze
  FROZEN_FINDINGS = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-read-only-invocation-vertical-slice-20260823/task-product/reviews/cycle-1/P3_TRIVS_CYCLE_1_FROZEN_FINDINGS_V1.json",
    "byte_length" => 6_383,
    "sha256" => "52b7f564aa3b1d0bcfa1ab3a8e78e142a4db44a05d16f59f59499f1943985e86"
  }.freeze
  TERMINAL_FINDING_IDS = %w[
    CTO-P1-001 CTO-P1-002
    P3-TRIVS-C1-SEC-P1-001 P3-TRIVS-C1-SEC-P1-002 P3-TRIVS-C1-SEC-P1-003
    P3-TRIVS-C1-SEC-P1-004 P3-TRIVS-C1-QE-P1-001 P3-TRIVS-C1-QE-P1-002
    P3-TRIVS-C1-QE-P1-003 P3-TRIVS-C1-QE-P1-004 P3-TRIVS-C1-QE-P1-005
  ].freeze
  PERMITTED_FINDING_FIELDS = %w[finding_id severity gate_relevance summary].freeze
  PERMITTED_TERMINAL_METADATA = %w[identity accounting lifecycle verdict].freeze
  GATE_RELEVANCE = %w[
    EXIT_GATE_VALIDITY AUTHORITY_OR_EXTERNAL_EFFECT_SAFETY RESULT_INTEGRITY PRODUCT_CORRECTNESS
  ].freeze
  LIMITS = {
    "engineering_tasks" => 19, "engineering_hours" => 568, "calendar_days" => 132,
    "active_tasks" => 1, "task_branches" => 1, "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  BASE_CONSUMED = {
    "engineering_tasks" => 17, "engineering_hours" => 496, "calendar_days" => 116
  }.freeze
  F2_BUDGET = {
    "engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6,
    "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
  }.freeze
  P2_BUDGET = {
    "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 10,
    "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
  }.freeze
  ROUTE_RELEASE = {
    "engineering_tasks" => 2, "engineering_hours" => 72, "calendar_days" => 16
  }.freeze
  F2_RESOURCES = {
    "branch" => "codex/p3-trivs-f2-candidate-bound-acceptance-harness",
    "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-trivs-f2-candidate-bound-acceptance-harness",
    "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trivs-evidence-first-final-route-20260823/task-foundation"
  }.freeze
  P2_RESOURCES = {
    "branch" => "codex/p3-trivs-p2-final-clean-room-product",
    "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-trivs-p2-final-clean-room-product",
    "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trivs-evidence-first-final-route-20260823/task-product"
  }.freeze
  F2_WORKER_PATHS = %w[
    evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1
    evaluation-harness/replay/p3-trivs-candidate-bound-acceptance-v1
    docs/aios/tasks/P3-TRIVS-F2_CANDIDATE_BOUND_ACCEPTANCE_HARNESS.yaml
    docs/PROJECT_CODE_MAP.md
  ].freeze
  P2_WORKER_PATHS = %w[
    backend-spring/src/main/java/com/sourcelens/module/agent/service/AgentRuntime.java
    backend-spring/src/main/java/com/sourcelens/module/agent/service/PromptBuilder.java
    backend-spring/src/main/java/com/sourcelens/module/agent/trustedread
    backend-spring/src/main/java/com/sourcelens/module/execution/trustedread
    backend-spring/src/main/java/com/sourcelens/module/sandbox/oci/trustedread
    backend-spring/src/main/resources/db/migration/V034__add_trusted_read_only_invocation.sql
    backend-spring/src/test/java/com/sourcelens/module/agent/trustedread
    backend-spring/src/test/java/com/sourcelens/module/execution/trustedread
    backend-spring/src/test/java/com/sourcelens/module/sandbox/oci/trustedread
    backend-spring/src/test/resources/p3-trusted-read-only-invocation-v2
    docs/aios/tasks/P3-TRIVS-P2_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_FINAL_CLEAN_ROOM_PRODUCT.yaml
    docs/PROJECT_CODE_MAP.md
  ].freeze
  P2_OPTIONAL_PRE_FIRST_WRITE_PATHS = %w[
    backend-spring/src/main/java/com/sourcelens/module/agent/tool/ToolExecutionService.java
    backend-spring/src/main/java/com/sourcelens/module/artifact/service/ArtifactStorageService.java
  ].freeze
  FALSE_EXTERNAL_EFFECTS = %w[
    network dns http_https provider secret credential remote production public
    irreversible_asset_removal p4_entry
  ].freeze
  DOCKER_ALLOWED_VERBS = [
    "version", "info", "exact image inspect", "image import", "create", "start",
    "wait", "inspect", "logs", "rm", "rmi"
  ].freeze
  DOCKER_ENDPOINT = "unix:///Users/lijunpeng/.docker/run/docker.sock"
  MYSQL_IMAGE_CONTENT_ID =
    "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209"
  CANONICAL_REPLAY_TIMEOUT_SECONDS = 120
  CANONICAL_REPLAY_NETWORK_PROBES = %w[dns af_inet af_inet6].freeze
  CANONICAL_REPLAY_MUTATIONS = %w[
    MISSING_ARTIFACT CANDIDATE_MISMATCH MISSING_STREAM METRICS_MISMATCH
    RUN_ROOT_ESCAPE ARTIFACT_IDENTITY_MISMATCH
  ].freeze
  DOCKER_FALSE_CONTROLS = %w[
    docker_registry docker_build docker_pull docker_host_source_bind_mount
    docker_privileged_mode docker_existing_object_mutation docker_unrelated_cleanup
    pinned_mysql_content_image_removal
  ].freeze
  REVIEW_ROLES = %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT].freeze
  REVIEW_KEYS = %w[cto security quality_evaluation].freeze
  KILL_POINTS = %w[
    before-import after-import after-create after-start after-wait after-remove
    before-terminal-commit
  ].freeze
  DENY_NETWORK_SANDBOX_PROFILE = "(version 1) (allow default) (deny network*)"
  DOCKER_SOCKET_SANDBOX_PROFILE =
    '(version 1) (allow default) (deny network*) (allow network-outbound (remote unix-socket (path-literal "/Users/lijunpeng/.docker/run/docker.sock")))'
  READ_ONLY_REPLAY_SANDBOX_PROFILE =
    "(version 1) (allow default) (deny network*) (deny file-write*) (deny signal) (deny process-fork)"
  NODE22_RUNTIME_PATH = "/opt/homebrew/opt/node@22/bin/node"
  JDK17_HOME = "/Users/lijunpeng/Library/Java/JavaVirtualMachines/ms-17.0.18/Contents/Home"
  MAVEN_396_PATH = "/Users/lijunpeng/apache-maven-3.9.6/bin/mvn"
  GO_1263_PATH = "/opt/homebrew/Cellar/go/1.26.3/libexec/bin/go"
  DOCKER_CLI_PATH = "/Applications/Docker.app/Contents/Resources/bin/docker"
  NETWORK_PROBE_SCRIPT =
    "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/tools/network-probe.mjs"
  PRODUCT_FORMAL_DRIVER_SOURCE =
    "backend-spring/src/test/java/com/sourcelens/module/agent/trustedread/" \
    "P3TrustedReadOnlyInvocationFormalDriver.java"
  PRODUCT_FORMAL_DRIVER_CLASS =
    "test/com/sourcelens/module/agent/trustedread/" \
    "P3TrustedReadOnlyInvocationFormalDriver.class"
  PRODUCT_FORMAL_DRIVER_MAIN =
    "com.sourcelens.module.agent.trustedread.P3TrustedReadOnlyInvocationFormalDriver"
  TASK_CONTRACT_SCHEMA = "p3-trivs-evidence-first-phase-delegated-task-contract/v1"
  TASK_AUTHORITY_SCHEMA = "p3-trivs-evidence-first-phase-delegated-task-authority/v1"
  TASK_CONTRACT_KEYS = %w[
    schema_version record_type task_id route_id phase stage_id task_kind status
    activation_parent strategic_installation_parent branch worktree evidence_root write_allowlist
    optional_pre_first_write_allowlist_expansion product_source_mutation_allowed budget
    execution_nonce authorization_id founder_route_decision accepted_dependencies acceptance
    external_effects clean_room lifecycle
  ].freeze
  TASK_AUTHORITY_KEYS = %w[
    schema_version record_type status issued_by task_id route_id phase stage_id task_kind
    activation_parent strategic_installation_parent contract authorization_id execution_nonce
    resources budget scope founder_route_decision accepted_dependencies external_effects clean_room lifecycle
  ].freeze
  ACTIVE_WORK_KEYS = %w[
    current_task selected_task current_task_status current_task_contract current_task_contract_sha256
    current_execution_authorization current_execution_authorization_sha256 authority_record
    authority_scope_conformance execution_nonce execution_nonce_status authorization_id
    activation_parent_commit activation_parent_tree strategic_installation_parent task_resource_state
    planned_task_branch planned_task_worktree planned_execution_evidence_root task_branch task_worktree
    execution_evidence_root dependency_custody_root allowlisted_paths current_task_budget next_stage_budget
    roles external_effects offsite_target founder_reserved_authorization
    founder_reserved_authorization_sha256 founder_decision_required founder_decision_required_scope
    escalation_reason user_action_required phase_route_decision_required
    phase_route_user_action_required historical_terminal_accounting terminal_task_record
    next_eligible_action
  ].freeze
  OPTIONAL_ALLOWLIST_PREFLIGHT_SCHEMA =
    "p3-trivs-evidence-first-optional-allowlist-expansion-preflight/v1"
  CANDIDATE_MANIFEST_SCHEMA = "p3-trivs-evidence-first-candidate-manifest/v1"
  REVIEW_SCHEMA = "p3-trivs-evidence-first-independent-review/v1"
  TASK_GATE_SCHEMA = "p3-trivs-evidence-first-task-gate-receipt/v1"
  INTEGRATION_SCHEMA = "p3-trivs-evidence-first-integration-receipt/v1"
  CANONICAL_REPLAY_SCHEMA = "p3-trivs-evidence-first-canonical-replay-receipt/v1"
  TERMINAL_SCHEMA = "p3-trivs-evidence-first-task-route-terminal-receipt/v1"
  RAW_EVIDENCE_MANIFEST_SCHEMA = "p3-trivs-evidence-first-closed-raw-evidence-manifest/v1"
  RAW_EVIDENCE_ARTIFACT_SCHEMA = "p3-trivs-evidence-first-raw-evidence-artifact/v1"
  CANONICAL_REPLAY_BUNDLE_SCHEMA = "p3-trivs-evidence-first-canonical-replay-raw-bundle/v1"
  F2_RAW_ARTIFACT_ROLES = %w[
    candidate_binding frozen_dispatch source_inventory toolchain_dependency_custody
    process_ledger network_enforcement build_reproducibility mysql_custody_transcript
    oci_custody_transcript seven_kill_orchestrator adversarial_matrix
    independent_replay final_cleanup_state
  ].freeze
  P2_RAW_ARTIFACT_ROLES = %w[
    candidate_binding frozen_dispatch source_inventory toolchain_dependency_custody
    process_ledger network_enforcement build_reproducibility helper_reproducibility
    real_mysql_transcript oci_hostile_context_transcript seven_kill_recovery_matrix
    adversarial_matrix zero_external_effects independent_replay final_cleanup_state
  ].freeze
  F2_ADVERSARIAL_CASES = %w[
    authority-field-injection generic-shell-runtime-construction
    generic-python-runtime-construction late-terminal-loser authorization-anchor-drift
    always-exit-zero-helper wrong-helper-binary wrong-rootfs candidate-mismatch
    mysql-nonfresh mysql-misbound orphan-cleanup network-bypass
  ].freeze
  P2_ADVERSARIAL_CASES = %w[
    authority-field-injection malformed-authority-shape generic-shell-runtime-construction
    generic-python-runtime-construction late-terminal-loser authorization-anchor-drift
    wrong-custody wrong-helper-binary wrong-rootfs wrong-image hostile-docker-context
    duplicate-terminal identical-custody-collision orphan-cleanup network-bypass
  ].freeze
  TASK_CONTRACT_PATHS = {
    F2_TASK_ID => "docs/aios/tasks/P3-TRIVS-F2_CANDIDATE_BOUND_ACCEPTANCE_HARNESS.yaml",
    P2_TASK_ID => "docs/aios/tasks/P3-TRIVS-P2_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_FINAL_CLEAN_ROOM_PRODUCT.yaml"
  }.freeze
  TASK_AUTHORITY_PATHS = {
    F2_TASK_ID => File.join(
      F2_RESOURCES.fetch("evidence_root"), "authority",
      "P3_TRIVS_F2_PHASE_DELEGATED_TASK_AUTHORITY_V1.json"
    ),
    P2_TASK_ID => File.join(
      P2_RESOURCES.fetch("evidence_root"), "authority",
      "P3_TRIVS_P2_PHASE_DELEGATED_TASK_AUTHORITY_V1.json"
    )
  }.freeze
  RESULT_PATHS = {
    F2_TASK_ID => {
      "candidate_manifest" => "candidate/P3_TRIVS_F2_CANDIDATE_MANIFEST_V1.json",
      "raw_evidence_manifest" => "raw/P3_TRIVS_F2_CLOSED_RAW_EVIDENCE_MANIFEST_V1.json",
      "cto" => "reviews/final/P3_TRIVS_F2_CTO_REVIEW_V1.json",
      "security" => "reviews/final/P3_TRIVS_F2_SECURITY_REVIEW_V1.json",
      "quality_evaluation" => "reviews/final/P3_TRIVS_F2_QUALITY_EVALUATION_REVIEW_V1.json",
      "task_gate_receipt" => "gate/P3_TRIVS_F2_TASK_GATE_RECEIPT_V1.json",
      "integration_receipt" => "integration/P3_TRIVS_F2_INTEGRATION_RECEIPT_V1.json",
      "canonical_replay_receipt" => "replay/P3_TRIVS_F2_CANONICAL_REPLAY_RECEIPT_V1.json",
      "canonical_replay_bundle" => "replay/P3_TRIVS_F2_CANONICAL_REPLAY_RAW_BUNDLE_V1.json",
      "terminal_receipt" => "terminal/P3_TRIVS_F2_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT_V1.json"
    },
    P2_TASK_ID => {
      "candidate_manifest" => "candidate/P3_TRIVS_P2_CANDIDATE_MANIFEST_V1.json",
      "raw_evidence_manifest" => "raw/P3_TRIVS_P2_CLOSED_RAW_EVIDENCE_MANIFEST_V1.json",
      "cto" => "reviews/final/P3_TRIVS_P2_CTO_REVIEW_V1.json",
      "security" => "reviews/final/P3_TRIVS_P2_SECURITY_REVIEW_V1.json",
      "quality_evaluation" => "reviews/final/P3_TRIVS_P2_QUALITY_EVALUATION_REVIEW_V1.json",
      "task_gate_receipt" => "gate/P3_TRIVS_P2_TASK_GATE_RECEIPT_V1.json",
      "integration_receipt" => "integration/P3_TRIVS_P2_INTEGRATION_RECEIPT_V1.json",
      "canonical_replay_receipt" => "replay/P3_TRIVS_P2_CANONICAL_REPLAY_RECEIPT_V1.json",
      "canonical_replay_bundle" => "replay/P3_TRIVS_P2_CANONICAL_REPLAY_RAW_BUNDLE_V1.json",
      "terminal_receipt" => "terminal/P3_TRIVS_P2_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT_V1.json"
    }
  }.transform_values(&:freeze).freeze
  P3_001_DEPENDENCY = {
    "status" => "ACCEPTED_INTEGRATED",
    "task_id" => "AIOS-P3-001_DURABLE_EXECUTION_CHECKPOINT_RESUME_KERNEL",
    "commit" => "17ce1134da4ea15c7270b147340ad0bad25c1ac8",
    "tree" => "8b6b4e387067b25052a2f6a64d7b802077acadc5",
    "task_gate_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001/terminal/P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json",
      "byte_length" => 3_055,
      "sha256" => "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
    }
  }.freeze
  DECLARATIVE_FOUNDATION_DEPENDENCY = {
    "status" => "ACCEPTED_INTEGRATED",
    "task_id" => "AIOS-P3-DTK-F1_DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION",
    "commit" => "2f52d0912ba5621bd2258fc21f5b74dd2019efd5",
    "tree" => "e9490d8f786f913b2e60a7e690a71911e015c87a",
    "task_gate_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/task-foundation/gate/P3_DTK_F1_TASK_GATE_INTEGRATION_RECEIPT_V1.json",
      "byte_length" => 5_202,
      "sha256" => "47dfed7024336b144306b565e643da0b2b88f87e72ffc181b88d58147e09f268"
    },
    "canonical_verification_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-declarative-transaction-kernel-route-20260823/task-foundation/gate/P3_DTK_F1_CANONICAL_VERIFICATION_RECEIPT_V1.json",
      "byte_length" => 5_409,
      "sha256" => "27847f8c89166897ce41846bb7fdd47494418057fb4726e6584f6b6e1cfbd0f6"
    }
  }.freeze
  ACCEPTED_DEPENDENCIES = {
    "p3_001" => P3_001_DEPENDENCY,
    "declarative_semantics_foundation" => DECLARATIVE_FOUNDATION_DEPENDENCY
  }.freeze

  LIFECYCLE = {
    "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" => {
      "state" => "P3_TRIVS_EVIDENCE_FIRST_FOUNDATION_ELIGIBLE",
      "route_status" => "ACTIVE_FOUNDATION_ELIGIBLE",
      "phase_status" => "ACTIVE_P3_TRIVS_EVIDENCE_FIRST_FOUNDATION_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_TRIVS_F2_FOUNDATION",
      "schedule" => "MASTER_ACTIVATE_FOUNDATION", "f2_status" => "ELIGIBLE_NOT_ACTIVATED",
      "p2_status" => "LOCKED_PENDING_FOUNDATION_ACCEPTANCE", "selected" => F2_TASK_ID,
      "task_status" => "ELIGIBLE_NOT_ACTIVATED", "active_task" => nil,
      "consumed" => BASE_CONSUMED, "reserved" => {}, "remaining" => ROUTE_RELEASE,
      "task_creation_allowed" => true, "remaining_capacity_usable" => true,
      "founder_required" => false, "founder_trigger" => "NONE",
      "delivery" => 25, "strict" => 0
    },
    "FOUNDATION_TASK_ACTIVE" => {
      "state" => "P3_TRIVS_EVIDENCE_FIRST_FOUNDATION_TASK_ACTIVE",
      "route_status" => "ACTIVE_FOUNDATION_TASK", "phase_status" => "ACTIVE_P3_TRIVS_F2_FOUNDATION_TASK",
      "action" => "EXECUTE_AIOS_P3_TRIVS_F2_FOUNDATION", "schedule" => "EXECUTE_FOUNDATION",
      "f2_status" => "ACTIVE", "p2_status" => "LOCKED_PENDING_FOUNDATION_ACCEPTANCE",
      "selected" => F2_TASK_ID, "task_status" => "ACTIVE", "active_task" => F2_TASK_ID,
      "consumed" => BASE_CONSUMED, "reserved" => F2_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days"),
      "remaining" => P2_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days"),
      "task_creation_allowed" => false, "remaining_capacity_usable" => true,
      "founder_required" => false, "founder_trigger" => "NONE",
      "delivery" => 25, "strict" => 0
    },
    "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE" => {
      "state" => "P3_TRIVS_EVIDENCE_FIRST_PRODUCT_ELIGIBLE",
      "route_status" => "ACTIVE_PRODUCT_ELIGIBLE", "phase_status" => "ACTIVE_P3_TRIVS_FINAL_PRODUCT_ELIGIBLE",
      "action" => "MASTER_ACTIVATE_AIOS_P3_TRIVS_P2_FINAL_PRODUCT", "schedule" => "MASTER_ACTIVATE_PRODUCT",
      "f2_status" => "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS", "p2_status" => "ELIGIBLE_NOT_ACTIVATED",
      "selected" => P2_TASK_ID, "task_status" => "ELIGIBLE_NOT_ACTIVATED", "active_task" => nil,
      "consumed" => {"engineering_tasks" => 18, "engineering_hours" => 520, "calendar_days" => 122},
      "reserved" => {}, "remaining" => P2_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days"),
      "task_creation_allowed" => true, "remaining_capacity_usable" => true,
      "founder_required" => false, "founder_trigger" => "NONE",
      "delivery" => 25, "strict" => 0
    },
    "PRODUCT_TASK_ACTIVE" => {
      "state" => "P3_TRIVS_EVIDENCE_FIRST_PRODUCT_TASK_ACTIVE",
      "route_status" => "ACTIVE_PRODUCT_TASK", "phase_status" => "ACTIVE_P3_TRIVS_FINAL_PRODUCT_TASK",
      "action" => "EXECUTE_AIOS_P3_TRIVS_P2_FINAL_PRODUCT", "schedule" => "EXECUTE_PRODUCT",
      "f2_status" => "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS", "p2_status" => "ACTIVE",
      "selected" => P2_TASK_ID, "task_status" => "ACTIVE", "active_task" => P2_TASK_ID,
      "consumed" => {"engineering_tasks" => 18, "engineering_hours" => 520, "calendar_days" => 122},
      "reserved" => P2_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days"),
      "remaining" => {"engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0},
      "task_creation_allowed" => false, "remaining_capacity_usable" => true,
      "founder_required" => false, "founder_trigger" => "NONE",
      "delivery" => 25, "strict" => 0
    },
    "FOUNDATION_ROUTE_TERMINAL_NON_PASS" => {
      "state" => "P3_TRIVS_EVIDENCE_FIRST_FOUNDATION_ROUTE_TERMINAL_NON_PASS",
      "route_status" => "HOLD_FOUNDATION_ROUTE_TERMINAL_NON_PASS",
      "phase_status" => "HOLD_INCOMPLETE_P3_TRIVS_F2_TERMINAL_NON_PASS",
      "action" => "FOUNDER_DECIDE_P3_AFTER_TRIVS_F2_TERMINAL_NON_PASS", "schedule" => "HOLD_ROUTE_TERMINAL",
      "f2_status" => "TERMINAL_TASK_GATE_NON_PASS", "p2_status" => "LOCKED_NEVER_CREATED",
      "selected" => "NONE_ROUTE_TERMINAL_NON_PASS", "task_status" => "TERMINAL_TASK_GATE_NON_PASS",
      "active_task" => nil,
      "consumed" => {"engineering_tasks" => 18, "engineering_hours" => 520, "calendar_days" => 122},
      "reserved" => {}, "remaining" => P2_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days"),
      "task_creation_allowed" => false, "remaining_capacity_usable" => false,
      "founder_required" => true,
      "founder_trigger" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
      "delivery" => 25, "strict" => 0
    },
    "PRODUCT_ROUTE_TERMINAL_NON_PASS" => {
      "state" => "P3_TRIVS_EVIDENCE_FIRST_PRODUCT_ROUTE_TERMINAL_NON_PASS",
      "route_status" => "HOLD_PRODUCT_ROUTE_TERMINAL_NON_PASS",
      "phase_status" => "HOLD_INCOMPLETE_P3_TRIVS_FINAL_PRODUCT_TERMINAL_NON_PASS",
      "action" => "FOUNDER_DECIDE_P3_AFTER_TRIVS_FINAL_PRODUCT_TERMINAL_NON_PASS", "schedule" => "HOLD_ROUTE_TERMINAL",
      "f2_status" => "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS", "p2_status" => "TERMINAL_TASK_GATE_NON_PASS",
      "selected" => "NONE_ROUTE_TERMINAL_NON_PASS", "task_status" => "TERMINAL_TASK_GATE_NON_PASS",
      "active_task" => nil,
      "consumed" => {"engineering_tasks" => 19, "engineering_hours" => 568, "calendar_days" => 132},
      "reserved" => {}, "remaining" => {"engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0},
      "task_creation_allowed" => false, "remaining_capacity_usable" => false,
      "founder_required" => true,
      "founder_trigger" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
      "delivery" => 25, "strict" => 0
    },
    "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE" => {
      "state" => "P3_TRIVS_EVIDENCE_FIRST_P3_PHASE_GATE_ELIGIBLE",
      "route_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "phase_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "action" => "FOUNDER_DECIDE_P3_PHASE_EXIT", "schedule" => "AWAIT_FOUNDER_PHASE_GATE",
      "f2_status" => "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS",
      "p2_status" => "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS",
      "selected" => "NONE_PHASE_GATE_ELIGIBLE", "task_status" => "ACCEPTED_INTEGRATED",
      "active_task" => nil,
      "consumed" => {"engineering_tasks" => 19, "engineering_hours" => 568, "calendar_days" => 132},
      "reserved" => {}, "remaining" => {"engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0},
      "task_creation_allowed" => false, "remaining_capacity_usable" => false,
      "founder_required" => true, "founder_trigger" => "PHASE_ENTRY_OR_EXIT",
      "delivery" => 100, "strict" => 100
    }
  }.freeze
  LIFECYCLE_STATES = LIFECYCLE.transform_values { |profile| profile.fetch("state") }.freeze

  def assert(condition, message)
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} is not a mapping")
    value
  end

  def path_for(root, identity)
    path = Pathname.new(identity.fetch("path"))
    path.absolute? ? path : Pathname.new(root).join(path)
  end

  def read_identity!(root, identity, label)
    path = path_for(root, identity)
    assert(path.exist? && path.file? && !path.symlink?, "#{label} missing, non-regular or symlinked")
    bytes = path.binread
    assert(bytes.bytesize == identity.fetch("byte_length"), "#{label} byte length drift")
    assert(Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"), "#{label} SHA-256 drift")
    bytes
  end

  def exact_mapping(value, keys, label)
    record = mapping(value, label)
    assert(record.keys.sort == keys.sort, "#{label} member set drift")
    record
  end

  def identity_mapping(value, label)
    identity = exact_mapping(value, %w[path byte_length sha256], "#{label} identity")
    assert(identity["path"].is_a?(String) && !identity["path"].empty? &&
           identity["byte_length"].is_a?(Integer) && identity["byte_length"] >= 0 &&
           identity["sha256"].is_a?(String) && identity["sha256"].match?(/\A[0-9a-f]{64}\z/),
           "#{label} identity fields are invalid")
    identity
  end

  def parse_json!(bytes, label)
    record = JSON.parse(bytes)
    mapping(record, label)
  rescue JSON::ParserError => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} invalid JSON: #{e.message}"
  end

  def git!(root, *args, allow_failure: false)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    assert(status.success? || allow_failure,
           "git #{args.join(' ')} failed: #{stderr.strip}")
    [stdout, stderr, status]
  end

  def validate_commit_tree!(root, commit, tree, label, integrated: false)
    assert(commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/) &&
           tree.is_a?(String) && tree.match?(/\A[0-9a-f]{40}\z/),
           "#{label} commit or tree identity invalid")
    _out, _err, commit_status = git!(root, "cat-file", "-e", "#{commit}^{commit}", allow_failure: true)
    assert(commit_status.success?, "#{label} commit is unavailable")
    actual_tree = git!(root, "show", "-s", "--format=%T", commit).first.strip
    assert(actual_tree == tree, "#{label} tree does not match commit")
    if integrated
      _out, _err, ancestor = git!(root, "merge-base", "--is-ancestor", commit, "HEAD", allow_failure: true)
      assert(ancestor.success?, "#{label} commit is not integrated into canonical HEAD")
    end
  end

  def read_evidence_identity!(root, identity, expected_path, evidence_root, label)
    identity = identity_mapping(identity, label)
    evidence = Pathname.new(evidence_root)
    assert(evidence.absolute? && evidence.cleanpath.to_s == evidence.to_s,
           "#{label} Evidence root is not canonical and absolute")
    evidence_stat = evidence.lstat
    assert(evidence_stat.directory? && !evidence_stat.symlink? && evidence.realpath.to_s == evidence.to_s,
           "#{label} Evidence root is absent, symlinked or redirected")
    expected = evidence.join(expected_path).cleanpath.to_s
    assert(identity["path"] == expected, "#{label} path drift")
    path = path_for(root, identity)
    assert(path.parent.realpath.to_s == path.parent.cleanpath.to_s,
           "#{label} parent path traverses a symlink")
    stat = path.lstat
    assert(stat.file? && !path.symlink? && stat.nlink == 1,
           "#{label} must be a regular, non-symlink, single-link Evidence file")
    assert((stat.mode & 0o222).zero?, "#{label} must be create-once and non-writable")
    read_identity!(root, identity, label)
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} unavailable: #{e.class}"
  end

  def path_allowed?(path, allowlist)
    allowlist.any? { |entry| path == entry || path.start_with?("#{entry}/") }
  end

  def task_docker_prefix(task_id)
    return "p3-trivs-f2-" if task_id == F2_TASK_ID
    return "p3-trivs-p2-" if task_id == P2_TASK_ID

    assert(false, "unknown P3 Docker Task")
  end

  def task_docker_labels(task_id, kind)
    [
      "--label", "com.sourcelens.aios.p3.route=#{ROUTE_ID}",
      "--label", "com.sourcelens.aios.p3.task=#{task_id}",
      "--label", "com.sourcelens.aios.p3.kind=#{kind}"
    ]
  end

  def scoped_docker_container?(value, prefix, kind = nil)
    suffix = kind ? Regexp.escape(kind) : "(?:mysql|mysql-probe|oci)"
    value.is_a?(String) && value.match?(/\A#{Regexp.escape(prefix)}#{suffix}-[0-9a-f]{12}\z/)
  end

  def scoped_docker_image?(value, prefix)
    value.is_a?(String) &&
      value.match?(/\A#{Regexp.escape(prefix)}(?:oci|mysql-probe)-[0-9a-f]{12}:sha256-[0-9a-f]{12}\z/)
  end

  def validate_docker_import_path!(path, evidence_root)
    expected_root = Pathname.new(evidence_root).join("dependency-custody/docker-imports").cleanpath
    candidate = Pathname.new(path.to_s).cleanpath
    assert(candidate.absolute? && candidate.dirname == expected_root &&
           candidate.basename.to_s.match?(/\A[0-9a-f]{64}\.tar\z/),
           "P3 Docker image import escaped the hash-bound Task custody root")
    stat = candidate.lstat
    assert(stat.file? && !stat.symlink? && stat.nlink == 1 &&
           candidate.dirname.realpath == expected_root.realpath,
           "P3 Docker image import input is not one regular task-custody file")
    expected_sha = candidate.basename.to_s.delete_suffix(".tar")
    assert(Digest::SHA256.file(candidate.to_s).hexdigest == expected_sha,
           "P3 Docker image import input digest does not match its content address")
    candidate.to_s
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "P3 Docker image import input unavailable: #{e.class}"
  end

  # Return a closed descriptor only after the complete Docker argv has matched one
  # exact authorized form.  No option, second target or daemon-wide selector is
  # accepted merely because another argument carries the Task prefix.
  def validate_docker_operation_args!(task_id, operation_args, evidence_root,
                                      verify_import_file: true)
    assert(operation_args.is_a?(Array) && operation_args.all? { |value| value.is_a?(String) },
           "P3 Docker operation argv is not a string array")
    prefix = task_docker_prefix(task_id)
    case operation_args
    when ["version"]
      return {"operation" => "version"}
    when ["info"]
      return {"operation" => "info"}
    end

    if operation_args.first(2) == ["image", "inspect"]
      assert(operation_args.length == 3,
             "P3 Docker image inspect must have exactly one frozen target")
      target = operation_args.fetch(2)
      assert(target == MYSQL_IMAGE_CONTENT_ID || scoped_docker_image?(target, prefix),
             "P3 Docker image inspect target escaped Task scope")
      return {"operation" => "image inspect", "image" => target}
    end

    if operation_args.first(2) == ["image", "import"]
      assert(operation_args.length == 4 && scoped_docker_image?(operation_args.fetch(3), prefix),
             "P3 Docker image import must have one custody tar and one scoped image target")
      import_path = operation_args.fetch(2)
      validate_docker_import_path!(import_path, evidence_root) if verify_import_file
      return {
        "operation" => "image import", "input" => import_path,
        "image" => operation_args.fetch(3)
      }
    end

    if operation_args.first == "create"
      name = operation_args[operation_args.index("--name").to_i + 1]
      if scoped_docker_container?(name, prefix, "mysql")
        expected = [
          "create", "--name", name, *task_docker_labels(task_id, "mysql"),
          "--network", "none", "--memory", "1g", "--cpus", "1.0", "--pids-limit", "256",
          "--env", "MYSQL_ALLOW_EMPTY_PASSWORD=yes",
          "--env", "MYSQL_DATABASE=sourcelens_p3", MYSQL_IMAGE_CONTENT_ID
        ]
        assert(operation_args == expected,
               "P3 Docker MySQL create argv is not the exact loopback-only Task form")
        return {"operation" => "create", "kind" => "mysql", "container" => name,
                "image" => MYSQL_IMAGE_CONTENT_ID}
      end
      if scoped_docker_container?(name, prefix, "mysql-probe")
        network_target = operation_args[operation_args.index("--network").to_i + 1]
        mysql_container = network_target&.delete_prefix("container:")
        image = operation_args[-2]
        action = task_id == F2_TASK_ID ?
          "MYSQL_CUSTODY_ACCEPTANCE_V1" : "PRODUCT_SPRING_MYSQL_ACCEPTANCE_V1"
        expected = [
          "create", "--name", name, *task_docker_labels(task_id, "mysql-probe"),
          *(task_id == P2_TASK_ID ? ["--interactive"] : []),
          "--network", "container:#{mysql_container}", "--read-only", "--memory", "512m",
          "--cpus", "1.0", "--pids-limit", "256",
          "--security-opt", "no-new-privileges", "--cap-drop", "ALL",
          "--user", "65532:65532", "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=64m",
          "--entrypoint", "/probe", image, action
        ]
        assert(scoped_docker_container?(mysql_container, prefix, "mysql") &&
               scoped_docker_image?(image, prefix) && image.include?("mysql-probe-") &&
               operation_args == expected,
               "P3 Docker MySQL probe create argv is not the exact shared-loopback Task form")
        return {"operation" => "create", "kind" => "mysql-probe", "container" => name,
                "mysql_container" => mysql_container, "image" => image, "action" => action}
      end
      if scoped_docker_container?(name, prefix, "oci")
        image = operation_args[-2]
        expected = [
          "create", "--name", name, *task_docker_labels(task_id, "oci"),
          "--network", "none", "--read-only", "--memory", "64m",
          "--cpus", "0.5", "--pids-limit", "32",
          "--security-opt", "no-new-privileges", "--cap-drop", "ALL",
          "--user", "65532:65532", "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=16m",
          "--entrypoint", "/helper", image, "SHA256_READ_ONLY_CUSTODY_V1"
        ]
        assert(scoped_docker_image?(image, prefix) && operation_args == expected,
               "P3 Docker OCI create argv is not the exact network-none read-only Task form")
        return {"operation" => "create", "kind" => "oci", "container" => name,
                "image" => image}
      end
      assert(false, "P3 Docker create name escaped Task scope")
    end

    operation = operation_args.first
    case operation
    when "start"
      target = operation_args.last
      expected = if scoped_docker_container?(target, prefix, "mysql")
                   ["start", target]
                 elsif scoped_docker_container?(target, prefix, "oci")
                   ["start", "--attach", "--interactive", target]
                 elsif scoped_docker_container?(target, prefix, "mysql-probe")
                   task_id == P2_TASK_ID ?
                     ["start", "--attach", "--interactive", target] :
                     ["start", "--attach", target]
                 end
      assert(!expected.nil? && operation_args == expected,
             "P3 Docker start argv is not one exact scoped target")
      {"operation" => "start", "container" => target}
    when "wait", "inspect", "logs"
      target = operation_args[1]
      assert(operation_args == [operation, target] && scoped_docker_container?(target, prefix),
             "P3 Docker #{operation} argv is not one exact scoped target")
      {"operation" => operation, "container" => target}
    when "rm"
      target = operation_args.last
      assert(operation_args == ["rm", "--force", "--volumes", target] &&
             scoped_docker_container?(target, prefix),
             "P3 Docker rm argv is not the exact scoped cleanup form")
      {"operation" => "rm", "container" => target}
    when "rmi"
      target = operation_args[1]
      assert(operation_args == ["rmi", target] && scoped_docker_image?(target, prefix),
             "P3 Docker rmi argv is not one exact scoped image cleanup target")
      {"operation" => "rmi", "image" => target}
    else
      assert(false, "P3 Docker operation is outside the exact authorized grammar")
    end
  end

  def validate_docker_grammar_self_test!
    task_id = F2_TASK_ID
    evidence_root = F2_RESOURCES.fetch("evidence_root")
    mysql_name = "p3-trivs-f2-mysql-aaaaaaaaaaaa"
    oci_name = "p3-trivs-f2-oci-bbbbbbbbbbbb"
    probe_name = "p3-trivs-f2-mysql-probe-cccccccccccc"
    oci_image = "p3-trivs-f2-oci-cccccccccccc:sha256-dddddddddddd"
    forbidden = [
      ["create", "--privileged", "--network", "host", "--volume", "/:/host",
       "--name", mysql_name, MYSQL_IMAGE_CONTENT_ID],
      ["start", mysql_name, "unrelated-container"],
      ["start", oci_name],
      ["start", probe_name],
      ["start", "--attach", mysql_name],
      ["rm", "--force", "--volumes", mysql_name, "unrelated-container"],
      ["rmi", MYSQL_IMAGE_CONTENT_ID],
      ["image", "inspect", MYSQL_IMAGE_CONTENT_ID, "unrelated-image"],
      ["create", "--name", mysql_name, *task_docker_labels(task_id, "mysql"),
       "--network", "bridge", "--publish", "127.0.0.1::3306", "--memory", "1g",
       "--cpus", "1.0", "--pids-limit", "256", "--env", "MYSQL_ALLOW_EMPTY_PASSWORD=yes",
       "--env", "MYSQL_DATABASE=sourcelens_p3", MYSQL_IMAGE_CONTENT_ID]
    ]
    forbidden.each do |argv|
      rejected = begin
        validate_docker_operation_args!(task_id, argv, evidence_root, verify_import_file: false)
        false
      rescue P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError
        true
      end
      assert(rejected, "P3 exact Docker grammar false-accepted a forbidden mutation")
    end
    product_task_id = P2_TASK_ID
    product_evidence_root = P2_RESOURCES.fetch("evidence_root")
    product_mysql = "p3-trivs-p2-mysql-aaaaaaaaaaaa"
    product_oci = "p3-trivs-p2-oci-bbbbbbbbbbbb"
    product_probe = "p3-trivs-p2-mysql-probe-cccccccccccc"
    [
      ["start", product_oci], ["start", product_probe],
      ["start", "--attach", product_oci], ["start", "--attach", product_probe],
      ["start", "--attach", "--interactive", product_mysql]
    ].each do |argv|
      rejected = begin
        validate_docker_operation_args!(
          product_task_id, argv, product_evidence_root, verify_import_file: false
        )
        false
      rescue P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError
        true
      end
      assert(rejected, "P3 exact Product Docker start grammar false-accepted a mutation")
    end
    mysql_create = [
      "create", "--name", mysql_name, *task_docker_labels(task_id, "mysql"),
      "--network", "none", "--memory", "1g", "--cpus", "1.0", "--pids-limit", "256",
      "--env", "MYSQL_ALLOW_EMPTY_PASSWORD=yes",
      "--env", "MYSQL_DATABASE=sourcelens_p3", MYSQL_IMAGE_CONTENT_ID
    ]
    oci_create = [
      "create", "--name", oci_name, *task_docker_labels(task_id, "oci"),
      "--network", "none", "--read-only", "--memory", "64m", "--cpus", "0.5",
      "--pids-limit", "32", "--security-opt", "no-new-privileges", "--cap-drop", "ALL",
      "--user", "65532:65532", "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=16m",
      "--entrypoint", "/helper", oci_image, "SHA256_READ_ONLY_CUSTODY_V1"
    ]
    assert(validate_docker_operation_args!(task_id, mysql_create, evidence_root)["kind"] == "mysql" &&
           validate_docker_operation_args!(task_id, oci_create, evidence_root)["kind"] == "oci",
           "P3 exact Docker grammar rejected its two authorized create forms")
    authorized_starts = [
      [task_id, evidence_root, ["start", mysql_name]],
      [task_id, evidence_root, ["start", "--attach", "--interactive", oci_name]],
      [task_id, evidence_root, ["start", "--attach", probe_name]],
      [product_task_id, product_evidence_root, ["start", product_mysql]],
      [product_task_id, product_evidence_root,
       ["start", "--attach", "--interactive", product_oci]],
      [product_task_id, product_evidence_root,
       ["start", "--attach", "--interactive", product_probe]]
    ]
    assert(authorized_starts.all? { |candidate_task_id, candidate_root, argv|
             validate_docker_operation_args!(
               candidate_task_id, argv, candidate_root, verify_import_file: false
             )["operation"] == "start"
           }, "P3 exact Docker grammar rejected an authorized start form")
    true
  end

  def validate_clean_build_record!(record, evidence_root, candidate)
    purpose = record["purpose"]
    assert(%w[CLEAN_BUILD_1 CLEAN_BUILD_2].include?(purpose),
           "P3 Maven process is not one of the two frozen clean builds")
    ordinal = purpose.delete_prefix("CLEAN_BUILD_")
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    global_settings = File.join(
      evidence_root, "dependency-custody/maven/global-settings.xml"
    )
    user_settings = File.join(
      evidence_root, "dependency-custody/maven/user-settings.xml"
    )
    fresh_repo = File.join(
      evidence_root, "dependency-custody/maven/fresh-repository-build-#{ordinal}"
    )
    pom = File.join(verifier_root, "backend-spring/pom.xml")
    expected_environment = {
      "PATH" => "#{File.dirname(MAVEN_396_PATH)}:#{JDK17_HOME}/bin:/usr/bin:/bin",
      "HOME" => "/var/empty", "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC",
      "JAVA_HOME" => JDK17_HOME
    }
    expected_argv = [
      "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, MAVEN_396_PATH,
      "--offline", "--global-settings", global_settings, "--settings", user_settings,
      "-Dmaven.repo.local=#{fresh_repo}", "-DforkCount=0", "-DreuseForks=false",
      "-Dstyle.color=never", "--no-transfer-progress", "--file", pom, "clean", "test"
    ]
    assert(record["cwd"] == verifier_root && record["argv"] == expected_argv &&
           record["environment"] == expected_environment &&
           record["stdin"].nil? && record["child_process_ids"].empty? &&
           record["network_mode"] == "DENY_NETWORK" && record["exit_status"] == 0 &&
           record["signal"].nil? &&
           record.dig("target_executable_identity", "path") == MAVEN_396_PATH,
           "P3 #{purpose} is not the exact detached offline clean-test command")
    true
  end

  def normalized_maven_summary_bytes!(record, evidence_root, candidate)
    label = "P3 #{record.fetch('purpose')} normalized Maven summary"
    stdout = process_stream_bytes!(record, "stdout", evidence_root, label)
    stderr = process_stream_bytes!(record, "stderr", evidence_root, label)
    text = stdout.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                 .gsub(/\e\[[0-9;]*m/, "")
    tests = text.lines.filter_map do |line|
      match = line.match(/Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: (\d+)/)
      next unless match

      {
        "tests" => match[1].to_i, "failures" => match[2].to_i,
        "errors" => match[3].to_i, "skipped" => match[4].to_i,
        "suite" => line.split(/ -- in | - in /, 2).fetch(1, "").strip
      }
    end
    assert(text.include?("BUILD SUCCESS") && !tests.empty? &&
           tests.all? { |entry| entry["failures"].zero? && entry["errors"].zero? } &&
           stderr.bytesize < 1_048_576,
           "#{label} lacks a successful zero-failure test result")
    canonical_json(
      {
        "schema_version" => "p3-trivs-normalized-maven-summary/v1",
        "candidate" => candidate, "tests" => tests
      }
    ) + "\n"
  end

  def validate_detached_verifier_preflight!(root, task_id, observations, records_by_id,
                                             evidence_root, candidate, role_stream_paths)
    label = "P3 #{task_id} detached verifier preflight"
    verifier_root = observations.fetch("verifier_root")
    ids = observations.fetch("preflight_process_ids")
    specs = [
      ["GIT_VERIFIER_HEAD", ["rev-parse", "HEAD^{commit}"], "#{candidate.fetch('commit')}\n"],
      ["GIT_VERIFIER_TREE", ["rev-parse", "HEAD^{tree}"], "#{candidate.fetch('tree')}\n"],
      ["GIT_VERIFIER_STATUS", ["status", "--porcelain=v2", "--untracked-files=all"], ""],
      ["GIT_VERIFIER_DIFF", ["diff", "--no-ext-diff", "--binary", "--exit-code"], ""],
      ["GIT_VERIFIER_FULL_TREE", ["ls-tree", "-r", "-z", "--full-tree", "HEAD"], nil]
    ]
    expected_environment = {
      "PATH" => "/usr/bin:/bin", "HOME" => "/var/empty", "LANG" => "C",
      "LC_ALL" => "C", "TZ" => "UTC"
    }
    sequences = specs.each_with_index.map do |(purpose, git_args, expected_stdout), index|
      process = records_by_id.fetch(ids.fetch(index))
      expected_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, "/usr/bin/git",
        "-C", verifier_root, *git_args
      ]
      stdout = process_stream_bytes!(process, "stdout", evidence_root, "#{label} #{purpose}")
      stderr = process_stream_bytes!(process, "stderr", evidence_root, "#{label} #{purpose}")
      expected_stdout ||= git!(
        root, "ls-tree", "-r", "-z", "--full-tree", candidate.fetch("commit")
      ).first
      assert(process["kind"] == "GIT" && process["purpose"] == purpose &&
             process["cwd"] == verifier_root && process["argv"] == expected_argv &&
             process["environment"] == expected_environment &&
             process["network_mode"] == "DENY_NETWORK" && process["stdin"].nil? &&
             process["exit_status"] == 0 && process["signal"].nil? &&
             process.dig("target_executable_identity", "path") == "/usr/bin/git" &&
             stdout == expected_stdout && stderr.empty? &&
             [process.dig("stdout", "path"), process.dig("stderr", "path")].all? { |path|
               role_stream_paths.include?(path)
             }, "#{label} #{purpose} did not bind the detached clean candidate")
      process.fetch("seq")
    end
    assert(sequences == sequences.sort && sequences.uniq.length == sequences.length,
           "#{label} process order drift")
    sequences.max
  end

  def validate_maven_dependency_custody!(task_id, observations, records_by_id, evidence_root,
                                         candidate, role_stream_paths, verifier_preflight_last_seq)
    label = "P3 #{task_id} Maven dependency custody"
    identities = {
      "global-settings.xml" => observations["global_settings_identity"],
      "user-settings.xml" => observations["user_settings_identity"],
      "dependency-manifest.json" => observations["dependency_custody_manifest"]
    }
    bytes = identities.to_h do |name, identity|
      relative = "dependency-custody/maven/#{name}"
      normalized, content = secure_evidence_read!(identity, evidence_root, relative, "#{label} #{name}")
      [name, [normalized, content]]
    end
    %w[global-settings.xml user-settings.xml].each do |name|
      settings = bytes.fetch(name).last
      assert(settings.include?("<offline>true</offline>") &&
             !settings.match?(/https?:\/\//i) && !settings.match?(/<server>/i),
             "#{label} #{name} is not a credential-free offline settings file")
    end
    manifest = exact_mapping(
      parse_json!(bytes.fetch("dependency-manifest.json").last, "#{label} manifest"),
      %w[schema_version task_id route_id candidate repository_root files], "#{label} manifest"
    )
    repository_root = File.join(evidence_root, "dependency-custody/maven/repository")
    assert(manifest["schema_version"] == "p3-trivs-maven-dependency-custody-manifest/v1" &&
           manifest["task_id"] == task_id && manifest["route_id"] == ROUTE_ID &&
           manifest["candidate"] == candidate && manifest["repository_root"] == repository_root &&
           manifest["files"].is_a?(Array) && !manifest["files"].empty? &&
           manifest["files"].length == observations["dependency_file_count"],
           "#{label} manifest header drift")
    expected_paths = manifest["files"].map.with_index do |entry, index|
      entry = exact_mapping(entry, %w[relative_path byte_length sha256],
                            "#{label} file #{index + 1}")
      relative = Pathname.new(entry["relative_path"].to_s)
      assert(!relative.absolute? && relative.cleanpath.to_s == relative.to_s &&
             !relative.to_s.start_with?("../") && entry["byte_length"].is_a?(Integer) &&
             entry["byte_length"].positive? && entry["sha256"].is_a?(String) &&
             entry["sha256"].match?(/\A[0-9a-f]{64}\z/),
             "#{label} file #{index + 1} identity drift")
      absolute = File.join(repository_root, relative.to_s)
      secure_evidence_read!(
        {"path" => absolute, "byte_length" => entry["byte_length"], "sha256" => entry["sha256"]},
        evidence_root, "dependency-custody/maven/repository/#{relative}",
        "#{label} file #{index + 1}"
      )
      absolute
    end
    actual_paths = []
    Find.find(repository_root) do |entry|
      next if entry == repository_root

      stat = File.lstat(entry)
      assert(!stat.symlink? && (stat.directory? || stat.file?),
             "#{label} contains a symlink or special object")
      actual_paths << entry if stat.file?
    end
    assert(expected_paths.uniq.sort == expected_paths.sort && actual_paths.sort == expected_paths.sort,
           "#{label} repository inventory is not closed")
    absence_ids = observations["fresh_repo_absence_process_ids"]
    init_ids = observations["fresh_repo_init_process_ids"]
    manifest_identities = [1, 2].map do |generation|
      identity = identity_mapping(
        observations["fresh_repo_manifest_build_#{generation}"],
        "#{label} fresh manifest #{generation}"
      )
      assert(role_stream_paths.include?(identity.fetch("path")),
             "#{label} fresh manifest #{generation} escaped its artifact streams")
      identity
    end
    assert(absence_ids.is_a?(Array) && absence_ids.length == 2 && absence_ids.uniq.length == 2 &&
           init_ids.is_a?(Array) && init_ids.length == 2 && init_ids.uniq.length == 2 &&
           (absence_ids + init_ids).uniq.length == 4,
           "#{label} must bind exactly two absence checks and two fresh-repository initializers")
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    harness_script =
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/run.mjs"
    init_environment = {
      "PATH" => "#{File.dirname(NODE22_RUNTIME_PATH)}:/usr/bin:/bin", "HOME" => "/var/empty",
      "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC"
    }
    absence_sequences = []
    init_sequences = init_ids.each_with_index.map do |process_id, index|
      generation = index + 1
      absence = records_by_id.fetch(absence_ids.fetch(index))
      process = records_by_id.fetch(process_id)
      fresh_repo = File.join(
        evidence_root, "dependency-custody/maven/fresh-repository-build-#{generation}"
      )
      absence_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, "/usr/bin/test",
        "!", "-e", fresh_repo
      ]
      expected_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
        harness_script, "--mode", "init-maven-custody", "--candidate", candidate.fetch("commit"),
        "--generation", generation.to_s, "--source", repository_root,
        "--destination", fresh_repo
      ]
      stdout = process_stream_bytes!(process, "stdout", evidence_root,
                                     "#{label} initializer #{generation}")
      stderr = process_stream_bytes!(process, "stderr", evidence_root,
                                     "#{label} initializer #{generation}")
      absence_stdout = process_stream_bytes!(
        absence, "stdout", evidence_root, "#{label} absence #{generation}"
      )
      absence_stderr = process_stream_bytes!(
        absence, "stderr", evidence_root, "#{label} absence #{generation}"
      )
      assert(process.fetch("stdout") == manifest_identities.fetch(index),
             "#{label} initializer #{generation} stdout identity drift")
      fresh_manifest = exact_mapping(
        parse_json!(stdout, "#{label} fresh manifest #{generation}"), %w[
          schema_version task_id route_id candidate generation source_repository repository_root files
        ], "#{label} fresh manifest #{generation}"
      )
      assert(absence["kind"] == "FILESYSTEM_PREFLIGHT" &&
             absence["purpose"] == "MAVEN_FRESH_REPOSITORY_ABSENT_#{generation}" &&
             absence["parent_process_id"].nil? && absence["child_process_ids"].empty? &&
             absence["cwd"] == verifier_root && absence["argv"] == absence_argv &&
             absence["environment"] == init_environment && absence["stdin"].nil? &&
             absence["network_mode"] == "DENY_NETWORK" && absence["exit_status"] == 0 &&
             absence["signal"].nil? &&
             absence.dig("target_executable_identity", "path") == "/usr/bin/test" &&
             absence_stdout.empty? && absence_stderr.empty? &&
             [absence.dig("stdout", "path"), absence.dig("stderr", "path")].all? { |path|
               role_stream_paths.include?(path)
             }, "#{label} generation #{generation} was not proven absent before initialization")
      assert(process["kind"] == "HARNESS" &&
             process["purpose"] == "MAVEN_CUSTODY_INIT_#{generation}" &&
             process["parent_process_id"].nil? && process["child_process_ids"].empty? &&
             process["cwd"] == verifier_root && process["argv"] == expected_argv &&
             process["environment"] == init_environment && process["stdin"].nil? &&
             process["network_mode"] == "DENY_NETWORK" && process["exit_status"] == 0 &&
             process["signal"].nil? &&
             process.dig("target_executable_identity", "path") == NODE22_RUNTIME_PATH &&
             stderr.empty? && fresh_manifest == {
               "schema_version" => "p3-trivs-fresh-maven-repository-manifest/v1",
               "task_id" => task_id, "route_id" => ROUTE_ID, "candidate" => candidate,
               "generation" => generation, "source_repository" => repository_root,
               "repository_root" => fresh_repo, "files" => manifest.fetch("files")
             } && [process.dig("stdout", "path"), process.dig("stderr", "path")].all? { |path|
               role_stream_paths.include?(path)
             }, "#{label} initializer #{generation} did not copy exact custody into the fresh repo")
      expected_fresh_paths = manifest.fetch("files").map do |entry|
        relative = entry.fetch("relative_path")
        secure_evidence_read!(
          {
            "path" => File.join(fresh_repo, relative),
            "byte_length" => entry.fetch("byte_length"), "sha256" => entry.fetch("sha256")
          }, evidence_root,
          "dependency-custody/maven/fresh-repository-build-#{generation}/#{relative}",
          "#{label} fresh repository #{generation} #{relative}"
        )
        File.join(fresh_repo, relative)
      end
      actual_fresh_paths = []
      Find.find(fresh_repo) do |entry|
        next if entry == fresh_repo

        stat = File.lstat(entry)
        assert(!stat.symlink? && (stat.directory? || stat.file?) &&
               (stat.file? ? (stat.mode & 0o777) == 0o444 : (stat.mode & 0o777) == 0o555),
               "#{label} fresh repository #{generation} is mutable, symlinked or special")
        actual_fresh_paths << entry if stat.file?
      end
      assert(actual_fresh_paths.sort == expected_fresh_paths.sort &&
             absence.fetch("seq") < process.fetch("seq"),
             "#{label} fresh repository #{generation} on disk differs from exact custody")
      absence_sequences << absence.fetch("seq")
      process.fetch("seq")
    end
    assert(absence_sequences == absence_sequences.sort && init_sequences == init_sequences.sort &&
           absence_sequences.first > verifier_preflight_last_seq &&
           absence_sequences.zip(init_sequences).all? { |absence_seq, init_seq| absence_seq < init_seq },
           "#{label} fresh-repository initialization order drift")
    {
      "manifest" => manifest, "process_ids" => absence_ids + init_ids,
      "absence_sequences" => absence_sequences, "sequences" => init_sequences
    }
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} unavailable: #{e.class}"
  end

  def validate_helper_build_binding!(root, task_id, observations, records_by_id,
                                     evidence_root, candidate, role_stream_paths)
    label = "P3 #{task_id} helper build binding"
    source_identity = identity_mapping(observations["helper_source_manifest"], "#{label} source")
    assert(role_stream_paths.include?(source_identity.fetch("path")),
           "#{label} source manifest escaped its artifact streams")
    source_bytes = validate_raw_stream!(
      source_identity, evidence_root, "raw/run/streams", "#{label} source manifest"
    ).last
    source_manifest = exact_mapping(parse_json!(source_bytes, "#{label} source manifest"), %w[
      schema_version task_id route_id candidate sources
    ], "#{label} source manifest")
    assert(source_manifest["schema_version"] == "p3-trivs-helper-source-manifest/v1" &&
           source_manifest["task_id"] == task_id && source_manifest["route_id"] == ROUTE_ID &&
           source_manifest["candidate"] == candidate && source_manifest["sources"].is_a?(Array) &&
           !source_manifest["sources"].empty?, "#{label} source manifest header drift")
    expected_source_paths = git!(
      root, "ls-tree", "-r", "--name-only", candidate.fetch("commit"), "--",
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/helper"
    ).first.lines.map(&:strip).select { |path| path.end_with?(".go") }.sort
    source_paths = source_manifest["sources"].map.with_index do |entry, index|
      entry = identity_mapping(entry, "#{label} source #{index + 1}")
      assert(entry["path"].start_with?(
               "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/helper/"
             ) && entry["path"].end_with?(".go"),
             "#{label} source escaped the accepted F2 helper root")
      bytes = git!(root, "show", "#{candidate.fetch('commit')}:#{entry.fetch('path')}").first
      assert(bytes.bytesize == entry.fetch("byte_length") &&
             Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
             "#{label} source does not match the frozen candidate")
      entry.fetch("path")
    end
    assert(source_paths == expected_source_paths && expected_source_paths.include?(
             "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/helper/main.go"
           ), "#{label} source manifest is not the sorted closed helper Go inventory")

    file_specs = {
      "helper_binary_build_1" => "dependency-custody/helper/build-1/helper",
      "helper_binary_build_2" => "dependency-custody/helper/build-2/helper",
      "helper_rootfs_build_1" => "dependency-custody/helper/build-1/rootfs.tar",
      "helper_rootfs_build_2" => "dependency-custody/helper/build-2/rootfs.tar"
    }
    normalized = file_specs.to_h do |key, relative|
      identity, bytes = secure_evidence_read!(
        observations[key], evidence_root, relative, "#{label} #{key}"
      )
      [key, [identity, bytes]]
    end
    assert(normalized["helper_binary_build_1"].last == normalized["helper_binary_build_2"].last &&
           normalized["helper_rootfs_build_1"].last == normalized["helper_rootfs_build_2"].last,
           "#{label} two binary or rootfs builds are not byte-equal")
    helper_binary = normalized.fetch("helper_binary_build_1").last
    assert(!helper_binary.empty?, "#{label} helper binary is empty")
    validate_closed_rootfs_tar!(
      normalized.fetch("helper_rootfs_build_1").last, {"helper" => helper_binary},
      "#{label} rootfs build 1"
    )
    validate_closed_rootfs_tar!(
      normalized.fetch("helper_rootfs_build_2").last, {"helper" => helper_binary},
      "#{label} rootfs build 2"
    )

    clean_ids = observations["clean_build_process_ids"]
    helper_ids = observations["helper_build_process_ids"]
    assert(clean_ids.is_a?(Array) && clean_ids.length == 2 && clean_ids.uniq.length == 2 &&
           helper_ids.is_a?(Array) && helper_ids.length == 2 && helper_ids.uniq.length == 2,
           "#{label} process partitions are not exactly two plus two")
    harness_script =
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/run.mjs"
    helper_source =
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/helper/main.go"
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    parent_environment = {
      "PATH" => "#{File.dirname(NODE22_RUNTIME_PATH)}:#{File.dirname(GO_1263_PATH)}:#{JDK17_HOME}/bin:/usr/bin:/bin",
      "HOME" => "/var/empty", "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC",
      "JAVA_HOME" => JDK17_HOME, "CGO_ENABLED" => "0", "GOOS" => "linux",
      "GOARCH" => "arm64", "GO111MODULE" => "off", "GOPROXY" => "off",
      "GOSUMDB" => "off", "GOTOOLCHAIN" => "local", "GOENV" => "off"
    }
    clean_records = clean_ids.map { |process_id| records_by_id.fetch(process_id) }
    assert(clean_records.all? { |record| record["kind"] == "MAVEN" } &&
           clean_records.map { |record| record["purpose"] }.sort == %w[CLEAN_BUILD_1 CLEAN_BUILD_2],
           "#{label} clean-build partition does not bind the two Maven builds")
    all_bound_ids = clean_ids.dup
    helper_sequences = []
    all_helper_ids = []
    helper_ids.each_with_index do |process_id, index|
      generation = index + 1
      parent = records_by_id.fetch(process_id)
      binary_identity = normalized.fetch("helper_binary_build_#{generation}").first
      rootfs_identity = normalized.fetch("helper_rootfs_build_#{generation}").first
      expected_parent_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
        harness_script, "--mode", "build-helper", "--candidate", candidate.fetch("commit"),
        "--generation", generation.to_s, "--evidence-root", evidence_root
      ]
      stdout = process_stream_bytes!(parent, "stdout", evidence_root, "#{label} parent #{generation}")
      stderr = process_stream_bytes!(parent, "stderr", evidence_root, "#{label} parent #{generation}")
      output = exact_mapping(parse_json!(stdout, "#{label} parent #{generation} output"), %w[
        schema_version task_id route_id candidate generation source_manifest
        binary_identity rootfs_identity verdict
      ], "#{label} parent #{generation} output")
      assert(parent["kind"] == "HARNESS" && parent["purpose"] == "HELPER_BUILD_#{generation}" &&
             parent["cwd"] == verifier_root && parent["argv"] == expected_parent_argv &&
             parent["environment"] == parent_environment && parent["stdin"].nil? &&
             parent["network_mode"] == "DENY_NETWORK" && parent["exit_status"] == 0 &&
             parent["signal"].nil? && parent.dig("target_executable_identity", "path") == NODE22_RUNTIME_PATH &&
             parent["child_process_ids"].length == 1 && stderr.empty? &&
             output == {
               "schema_version" => "p3-trivs-helper-build-result/v1", "task_id" => task_id,
               "route_id" => ROUTE_ID, "candidate" => candidate, "generation" => generation,
               "source_manifest" => source_identity, "binary_identity" => binary_identity,
               "rootfs_identity" => rootfs_identity,
               "verdict" => "PASS_REPRODUCIBLE_SOURCE_BINARY_ROOTFS"
             }, "#{label} parent #{generation} drift")
      child = records_by_id.fetch(parent["child_process_ids"].first)
      build_root = File.join(evidence_root, "dependency-custody/helper", "build-#{generation}")
      child_environment = {
        "PATH" => "#{File.dirname(GO_1263_PATH)}:/usr/bin:/bin", "HOME" => "/var/empty",
        "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC", "CGO_ENABLED" => "0",
        "GOOS" => "linux", "GOARCH" => "arm64", "GO111MODULE" => "off",
        "GOPROXY" => "off", "GOSUMDB" => "off", "GOTOOLCHAIN" => "local",
        "GOENV" => "off", "GOCACHE" => File.join(build_root, "go-cache"),
        "GOTMPDIR" => File.join(build_root, "go-tmp")
      }
      expected_child_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, GO_1263_PATH,
        "build", "-trimpath", "-buildvcs=false", "-ldflags=-buildid=", "-o",
        binary_identity.fetch("path"), helper_source
      ]
      child_stdout = process_stream_bytes!(child, "stdout", evidence_root, "#{label} Go #{generation}")
      child_stderr = process_stream_bytes!(child, "stderr", evidence_root, "#{label} Go #{generation}")
      assert(child["kind"] == "GO" && child["purpose"] == "HELPER_GO_BUILD_#{generation}" &&
             child["parent_process_id"] == parent["process_id"] && child["cwd"] == verifier_root &&
             child["argv"] == expected_child_argv && child["environment"] == child_environment &&
             child["stdin"].nil? && child["network_mode"] == "DENY_NETWORK" &&
             child["exit_status"] == 0 && child["signal"].nil? &&
             child.dig("target_executable_identity", "path") == GO_1263_PATH &&
             child_stdout.empty? && child_stderr.empty? && parent["seq"] < child["seq"],
             "#{label} exact Go child #{generation} drift")
      [parent, child].each do |process|
        assert([process.dig("stdout", "path"), process.dig("stderr", "path")].all? { |path|
                 role_stream_paths.include?(path)
               }, "#{label} process stream escaped its artifact")
      end
      all_bound_ids.concat([parent.fetch("process_id"), child.fetch("process_id")])
      all_helper_ids.concat([parent.fetch("process_id"), child.fetch("process_id")])
      helper_sequences.concat([parent.fetch("seq"), child.fetch("seq")])
    end
    assert(helper_sequences == helper_sequences.sort &&
           clean_records.map { |record| record.fetch("seq") }.max < helper_sequences.min &&
           observations["process_ids"].sort == all_bound_ids.sort,
           "#{label} artifact process set is not the exact Maven plus helper build union")
    {
      "binary_sha256" => normalized["helper_binary_build_1"].first.fetch("sha256"),
      "rootfs_sha256" => normalized["helper_rootfs_build_1"].first.fetch("sha256"),
      "last_seq" => helper_sequences.max,
      "helper_build_process_ids" => helper_ids,
      "all_helper_process_ids" => all_helper_ids
    }
  end

  def process_stream_bytes!(record, stream_key, evidence_root, label)
    identity = record.fetch(stream_key)
    assert(!identity.nil?, "#{label} is missing #{stream_key}")
    validate_raw_stream!(identity, evidence_root, "raw/run/streams", "#{label} #{stream_key}").last
  end

  def one_process!(records_by_id, process_ids, kind, purpose, label)
    matches = process_ids.map { |id| records_by_id.fetch(id) }.select do |record|
      record["kind"] == kind && record["purpose"] == purpose
    end
    assert(matches.length == 1, "#{label} must bind exactly one #{kind}/#{purpose} process")
    matches.first
  end

  def docker_success_streams!(record, evidence_root, label, stderr_may_be_nonempty: false)
    stdout = process_stream_bytes!(record, "stdout", evidence_root, label)
    stderr = process_stream_bytes!(record, "stderr", evidence_root, label)
    assert(record["exit_status"] == 0 && record["signal"].nil? &&
           (stderr_may_be_nonempty || stderr.empty?),
           "#{label} was not one successful exact Docker observation")
    [stdout, stderr]
  end

  def docker_json_object!(bytes, label)
    value = JSON.parse(bytes)
    assert(value.is_a?(Array) && value.length == 1 && value.first.is_a?(Hash),
           "#{label} is not one Docker inspect object")
    value.first
  rescue JSON::ParserError => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} invalid Docker JSON: #{e.message}"
  end

  def assert_task_labels!(labels, task_id, kind, label)
    assert(labels.is_a?(Hash) &&
           labels["com.sourcelens.aios.p3.route"] == ROUTE_ID &&
           labels["com.sourcelens.aios.p3.task"] == task_id &&
           labels["com.sourcelens.aios.p3.kind"] == kind,
           "#{label} lost the exact Task labels")
  end

  def validate_mysql_probe_build_binding!(root, task_id, observations, records_by_id,
                                          evidence_root, candidate, role_stream_paths)
    label = "P3 #{task_id} MySQL probe build binding"
    source_identity = identity_mapping(observations["probe_source_manifest"], "#{label} source")
    build_one_identity = identity_mapping(
      observations["probe_class_inventory_build_1"], "#{label} class inventory 1"
    )
    build_two_identity = identity_mapping(
      observations["probe_class_inventory_build_2"], "#{label} class inventory 2"
    )
    [source_identity, build_one_identity, build_two_identity].each do |stream_identity|
      assert(role_stream_paths.include?(stream_identity.fetch("path")),
             "#{label} identity escaped the MySQL artifact stream inventory")
    end
    source_bytes = validate_raw_stream!(
      source_identity, evidence_root, "raw/run/streams", "#{label} source manifest"
    ).last
    class_one_bytes = validate_raw_stream!(
      build_one_identity, evidence_root, "raw/run/streams", "#{label} class inventory 1"
    ).last
    class_two_bytes = validate_raw_stream!(
      build_two_identity, evidence_root, "raw/run/streams", "#{label} class inventory 2"
    ).last
    assert(class_one_bytes == class_two_bytes,
           "#{label} two independent class inventories are not byte-equal")

    source_manifest = exact_mapping(parse_json!(source_bytes, "#{label} source manifest"), %w[
      schema_version task_id route_id candidate sources
    ], "#{label} source manifest")
    assert(source_manifest["schema_version"] == "p3-trivs-mysql-probe-source-manifest/v1" &&
           source_manifest["task_id"] == task_id && source_manifest["route_id"] == ROUTE_ID &&
           source_manifest["candidate"] == candidate && source_manifest["sources"].is_a?(Array) &&
           !source_manifest["sources"].empty?, "#{label} source manifest header drift")
    probe_source =
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/mysql-probe/main.go"
    java_sources = git!(
      root, "ls-tree", "-r", "--name-only", candidate.fetch("commit"), "--",
      "backend-spring/src/main/java", "backend-spring/src/test/java"
    ).first.lines.map(&:strip).select { |path| path.end_with?(".java") }
    expected_source_paths = (java_sources + [probe_source]).sort
    source_entries = source_manifest["sources"].map.with_index do |entry, index|
      entry = identity_mapping(entry, "#{label} source #{index + 1}")
      path = entry.fetch("path")
      assert(expected_source_paths.include?(path),
             "#{label} source escaped the complete candidate source inventory")
      bytes = git!(root, "show", "#{candidate.fetch('commit')}:#{path}").first
      assert(bytes.bytesize == entry.fetch("byte_length") &&
             Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
             "#{label} source identity does not match the frozen candidate")
      entry
    end
    assert(source_entries.map { |entry| entry.fetch("path") } == expected_source_paths,
           "#{label} source manifest is not the sorted closed Java plus Go source inventory")

    class_inventory = exact_mapping(parse_json!(class_one_bytes, "#{label} class inventory"), %w[
      schema_version task_id route_id candidate source_manifest_sha256 classes
    ], "#{label} class inventory")
    assert(class_inventory["schema_version"] == "p3-trivs-mysql-probe-class-inventory/v1" &&
           class_inventory["task_id"] == task_id && class_inventory["route_id"] == ROUTE_ID &&
           class_inventory["candidate"] == candidate &&
           class_inventory["source_manifest_sha256"] == source_identity.fetch("sha256") &&
           class_inventory["classes"].is_a?(Array) && !class_inventory["classes"].empty?,
           "#{label} class inventory header drift")
    source_by_path = source_entries.to_h { |entry| [entry.fetch("path"), entry] }
    normalized_classes = class_inventory["classes"].map.with_index do |entry, index|
      entry = exact_mapping(entry, %w[
        path byte_length sha256 source_path source_sha256
      ], "#{label} class #{index + 1}")
      relative = Pathname.new(entry["path"].to_s)
      assert(!relative.absolute? && relative.cleanpath.to_s == entry["path"] &&
             entry["path"].start_with?("main/", "test/") &&
             !entry["path"].start_with?("../") && entry["path"].end_with?(".class") &&
             entry["byte_length"].is_a?(Integer) && entry["byte_length"].positive? &&
             entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[0-9a-f]{64}\z/) &&
             source_by_path.fetch(entry["source_path"], nil)&.fetch("sha256") == entry["source_sha256"],
             "#{label} class inventory is not source-bound")
      entry
    end
    class_paths = normalized_classes.map { |entry| entry.fetch("path") }
    assert(class_paths == class_paths.sort && class_paths.uniq.length == class_paths.length &&
           normalized_classes.map { |entry| entry.fetch("source_path") }.uniq.sort ==
             java_sources.sort &&
           normalized_classes.any? { |entry|
             entry.fetch("source_path").start_with?("backend-spring/src/main/java/")
           } && normalized_classes.any? { |entry|
             entry.fetch("source_path").start_with?("backend-spring/src/test/java/")
           }, "#{label} class inventory is not sorted, closed or main/test complete")

    class_bytes_by_generation = [1, 2].map do |generation|
      target_root = File.join(
        evidence_root, "dependency-custody/mysql-probe/build-#{generation}/maven-target"
      )
      expected_files = normalized_classes.to_h do |entry|
        relative = entry.fetch("path")
        scope, class_relative = relative.split("/", 2)
        classes_root = File.join(target_root, scope == "main" ? "classes" : "test-classes")
        identity = {
          "path" => File.join(classes_root, class_relative),
          "byte_length" => entry.fetch("byte_length"), "sha256" => entry.fetch("sha256")
        }
        _normalized, content = secure_evidence_read!(
          identity, evidence_root,
          "dependency-custody/mysql-probe/build-#{generation}/maven-target/" \
            "#{scope == 'main' ? 'classes' : 'test-classes'}/#{class_relative}",
          "#{label} class build #{generation} #{relative}"
        )
        [relative, content]
      end
      actual_files = []
      {"main" => "classes", "test" => "test-classes"}.each do |scope, directory|
        classes_root = File.join(target_root, directory)
        Find.find(classes_root) do |entry|
          next if entry == classes_root

          stat = File.lstat(entry)
          assert(!stat.symlink? && (stat.directory? || stat.file?) &&
                 (stat.file? ? (stat.mode & 0o222).zero? : (stat.mode & 0o222).zero?),
                 "#{label} class build #{generation} contains a mutable, symlinked or special object")
          if stat.file? && entry.end_with?(".class")
            actual_files << "#{scope}/#{Pathname.new(entry).relative_path_from(Pathname.new(classes_root))}"
          end
        end
      end
      assert(actual_files.sort == expected_files.keys.sort,
             "#{label} class build #{generation} inventory is not closed")
      expected_files
    end
    assert(class_bytes_by_generation.first == class_bytes_by_generation.last,
           "#{label} two class byte inventories differ")

    file_specs = {
      "probe_binary_build_1" => "dependency-custody/mysql-probe/build-1/probe",
      "probe_binary_build_2" => "dependency-custody/mysql-probe/build-2/probe",
      "probe_rootfs_build_1" => "dependency-custody/mysql-probe/build-1/rootfs.tar",
      "probe_rootfs_build_2" => "dependency-custody/mysql-probe/build-2/rootfs.tar"
    }
    normalized_outputs = file_specs.to_h do |key, relative|
      identity, content = secure_evidence_read!(observations[key], evidence_root, relative,
                                                "#{label} #{key}")
      [key, [identity, content]]
    end
    probe_binary = normalized_outputs.fetch("probe_binary_build_1").last
    assert(!probe_binary.empty? &&
           probe_binary == normalized_outputs.fetch("probe_binary_build_2").last &&
           normalized_outputs.fetch("probe_rootfs_build_1").last ==
             normalized_outputs.fetch("probe_rootfs_build_2").last,
           "#{label} two probe binary or rootfs builds are not byte-equal")
    [1, 2].each do |generation|
      expected_rootfs = {"probe" => {"bytes" => probe_binary, "mode" => 0o555}}
      validate_closed_rootfs_tar!(
        normalized_outputs.fetch("probe_rootfs_build_#{generation}").last,
        expected_rootfs, "#{label} rootfs build #{generation}"
      )
    end

    import_identity = identity_mapping(
      observations["probe_rootfs_identity"], "#{label} import rootfs"
    )
    import_relative = Pathname.new(import_identity.fetch("path")).relative_path_from(
      Pathname.new(evidence_root)
    ).to_s
    import_identity, import_bytes = secure_evidence_read!(
      import_identity, evidence_root, import_relative, "#{label} import rootfs"
    )
    validate_docker_import_path!(import_identity.fetch("path"), evidence_root)
    assert(import_bytes == normalized_outputs.fetch("probe_rootfs_build_1").last,
           "#{label} Docker import rootfs differs from the two verified builds")
    prefix = task_docker_prefix(task_id)
    expected_image_suffix = "sha256-#{import_identity.fetch('sha256')[0, 12]}"
    assert(scoped_docker_image?(observations["probe_image"], prefix) &&
           observations["probe_image"].include?("mysql-probe-") &&
           observations["probe_image"].end_with?(expected_image_suffix),
           "#{label} probe image is not content-bound to the accepted rootfs")
    expected_action = task_id == F2_TASK_ID ?
      "MYSQL_CUSTODY_ACCEPTANCE_V1" : "PRODUCT_SPRING_MYSQL_ACCEPTANCE_V1"
    assert(observations["probe_action"] == expected_action,
           "#{label} probe action drift")

    build_ids = observations["probe_build_process_ids"]
    assert(build_ids.is_a?(Array) && build_ids.length == 2 && build_ids.uniq.length == 2,
           "#{label} must bind exactly two independent build processes")
    harness_script =
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/run.mjs"
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    expected_environment = {
      "PATH" => "#{File.dirname(NODE22_RUNTIME_PATH)}:#{File.dirname(GO_1263_PATH)}:#{JDK17_HOME}/bin:#{File.dirname(MAVEN_396_PATH)}:/usr/bin:/bin",
      "HOME" => "/var/empty", "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC",
      "JAVA_HOME" => JDK17_HOME, "CGO_ENABLED" => "0", "GOOS" => "linux",
      "GOARCH" => "arm64", "GO111MODULE" => "off", "GOPROXY" => "off",
      "GOSUMDB" => "off", "GOTOOLCHAIN" => "local", "GOENV" => "off"
    }
    all_build_process_ids = []
    build_sequences = build_ids.each_with_index.flat_map do |process_id, index|
      process = records_by_id.fetch(process_id)
      generation = index + 1
      expected_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
        harness_script, "--mode", "build-mysql-probe", "--candidate",
        candidate.fetch("commit"), "--generation", generation.to_s, "--evidence-root", evidence_root
      ]
      stdout = process_stream_bytes!(process, "stdout", evidence_root, "#{label} build #{generation}")
      stderr = process_stream_bytes!(process, "stderr", evidence_root, "#{label} build #{generation}")
      output = exact_mapping(parse_json!(stdout, "#{label} build #{generation} output"), %w[
        schema_version task_id route_id candidate generation source_manifest
        class_inventory binary_identity rootfs_identity verdict
      ], "#{label} build #{generation} output")
      expected_inventory = generation == 1 ? build_one_identity : build_two_identity
      expected_binary = normalized_outputs.fetch("probe_binary_build_#{generation}").first
      expected_rootfs = normalized_outputs.fetch("probe_rootfs_build_#{generation}").first
      maven = records_by_id.values.find { |record|
        record["kind"] == "MAVEN" && record["purpose"] == "CLEAN_BUILD_#{generation}"
      }
      assert(!maven.nil?, "#{label} build #{generation} lacks its exact Maven child")
      build_root = File.join(evidence_root, "dependency-custody/mysql-probe/build-#{generation}")
      source_target = File.join(verifier_root, "backend-spring/target")
      captured_target = File.join(build_root, "maven-target")
      target_absence = records_by_id.values.find { |record|
        record["kind"] == "FILESYSTEM_PREFLIGHT" &&
          record["purpose"] == "MAVEN_TARGET_CAPTURE_ABSENT_#{generation}"
      }
      capture = records_by_id.values.find { |record|
        record["kind"] == "FILESYSTEM" && record["purpose"] == "MAVEN_TARGET_CAPTURE_#{generation}"
      }
      chmod = records_by_id.values.find { |record|
        record["kind"] == "FILESYSTEM" && record["purpose"] == "MAVEN_TARGET_READ_ONLY_#{generation}"
      }
      go_process = records_by_id.values.find { |record|
        record["kind"] == "GO" && record["purpose"] == "MYSQL_PROBE_GO_BUILD_#{generation}"
      }
      assert([target_absence, capture, chmod, go_process].none?(&:nil?),
             "#{label} build #{generation} lacks exact target capture or Go children")
      go_environment = {
        "PATH" => "#{File.dirname(GO_1263_PATH)}:/usr/bin:/bin", "HOME" => "/var/empty",
        "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC", "CGO_ENABLED" => "0",
        "GOOS" => "linux", "GOARCH" => "arm64", "GO111MODULE" => "off",
        "GOPROXY" => "off", "GOSUMDB" => "off", "GOTOOLCHAIN" => "local",
        "GOENV" => "off", "GOCACHE" => File.join(build_root, "go-cache"),
        "GOTMPDIR" => File.join(build_root, "go-tmp")
      }
      expected_go_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, GO_1263_PATH,
        "build", "-trimpath", "-buildvcs=false", "-ldflags=-buildid=", "-o",
        expected_binary.fetch("path"), probe_source
      ]
      go_stdout = process_stream_bytes!(go_process, "stdout", evidence_root,
                                        "#{label} Go build #{generation}")
      go_stderr = process_stream_bytes!(go_process, "stderr", evidence_root,
                                        "#{label} Go build #{generation}")
      filesystem_environment = {
        "PATH" => "/usr/bin:/bin", "HOME" => "/var/empty", "LANG" => "C",
        "LC_ALL" => "C", "TZ" => "UTC"
      }
      expected_absence_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, "/usr/bin/test",
        "!", "-e", captured_target
      ]
      expected_capture_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, "/bin/mv",
        source_target, captured_target
      ]
      expected_chmod_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, "/bin/chmod",
        "-R", "a-w", captured_target
      ]
      filesystem_processes = [
        [target_absence, "FILESYSTEM_PREFLIGHT", expected_absence_argv, "/usr/bin/test"],
        [capture, "FILESYSTEM", expected_capture_argv, "/bin/mv"],
        [chmod, "FILESYSTEM", expected_chmod_argv, "/bin/chmod"]
      ]
      filesystem_processes.each do |filesystem_process, kind, argv, executable|
        fs_stdout = process_stream_bytes!(filesystem_process, "stdout", evidence_root,
                                          "#{label} #{filesystem_process.fetch('purpose')}")
        fs_stderr = process_stream_bytes!(filesystem_process, "stderr", evidence_root,
                                          "#{label} #{filesystem_process.fetch('purpose')}")
        assert(filesystem_process["kind"] == kind &&
               filesystem_process["parent_process_id"] == process.fetch("process_id") &&
               filesystem_process["child_process_ids"].empty? &&
               filesystem_process["cwd"] == verifier_root && filesystem_process["argv"] == argv &&
               filesystem_process["environment"] == filesystem_environment &&
               filesystem_process["stdin"].nil? &&
               filesystem_process["network_mode"] == "DENY_NETWORK" &&
               filesystem_process["exit_status"] == 0 && filesystem_process["signal"].nil? &&
               filesystem_process.dig("target_executable_identity", "path") == executable &&
               fs_stdout.empty? && fs_stderr.empty?,
               "#{label} #{filesystem_process.fetch('purpose')} drift")
      end
      assert(process["kind"] == "HARNESS" &&
             process["purpose"] == "MYSQL_PROBE_BUILD_#{generation}" &&
             process["cwd"] == verifier_root && process["argv"] == expected_argv &&
             process["environment"] == expected_environment && process["stdin"].nil? &&
             process["network_mode"] == "DENY_NETWORK" &&
             process["exit_status"] == 0 && process["signal"].nil? &&
             process.dig("target_executable_identity", "path") == NODE22_RUNTIME_PATH &&
             stderr.empty? &&
             output == {
               "schema_version" => "p3-trivs-mysql-probe-build-result/v1",
               "task_id" => task_id, "route_id" => ROUTE_ID, "candidate" => candidate,
               "generation" => generation, "source_manifest" => source_identity,
               "class_inventory" => expected_inventory, "binary_identity" => expected_binary,
               "rootfs_identity" => expected_rootfs,
               "verdict" => "PASS_REPRODUCIBLE_SOURCE_TO_CLASS_ROOTFS"
             } &&
             process["child_process_ids"] == [
               target_absence.fetch("process_id"), maven.fetch("process_id"),
               capture.fetch("process_id"), chmod.fetch("process_id"), go_process.fetch("process_id")
             ] &&
             maven["parent_process_id"] == process.fetch("process_id") &&
             go_process["kind"] == "GO" &&
             go_process["purpose"] == "MYSQL_PROBE_GO_BUILD_#{generation}" &&
             go_process["parent_process_id"] == process.fetch("process_id") &&
             go_process["cwd"] == verifier_root && go_process["argv"] == expected_go_argv &&
             go_process["environment"] == go_environment && go_process["stdin"].nil? &&
             go_process["network_mode"] == "DENY_NETWORK" && go_process["exit_status"] == 0 &&
             go_process["signal"].nil? && go_process["child_process_ids"].empty? &&
             go_process.dig("target_executable_identity", "path") == GO_1263_PATH &&
             go_stdout.empty? && go_stderr.empty? &&
             process.fetch("seq") < target_absence.fetch("seq") &&
             target_absence.fetch("seq") < maven.fetch("seq") &&
             maven.fetch("seq") < capture.fetch("seq") && capture.fetch("seq") < chmod.fetch("seq") &&
             chmod.fetch("seq") < go_process.fetch("seq") &&
             [process.dig("stdout", "path"), process.dig("stderr", "path"),
              maven.dig("stdout", "path"), maven.dig("stderr", "path"),
              target_absence.dig("stdout", "path"), target_absence.dig("stderr", "path"),
              capture.dig("stdout", "path"), capture.dig("stderr", "path"),
              chmod.dig("stdout", "path"), chmod.dig("stderr", "path"),
              go_process.dig("stdout", "path"), go_process.dig("stderr", "path")].all? { |path|
               role_stream_paths.include?(path)
             },
             "#{label} build #{generation} is not the exact candidate-owned offline build")
      all_build_process_ids.concat(
        [process.fetch("process_id"), target_absence.fetch("process_id"),
         maven.fetch("process_id"), capture.fetch("process_id"), chmod.fetch("process_id"),
         go_process.fetch("process_id")]
      )
      [process.fetch("seq"), target_absence.fetch("seq"), maven.fetch("seq"),
       capture.fetch("seq"), chmod.fetch("seq"), go_process.fetch("seq")]
    end
    assert(build_sequences == build_sequences.sort && build_sequences.uniq.length == build_sequences.length,
           "#{label} build process order drift")
    spring_classpath = nil
    if task_id == P2_TASK_ID
      driver_entry = normalized_classes.find { |entry|
        entry["path"] == PRODUCT_FORMAL_DRIVER_CLASS
      }
      assert(driver_entry&.fetch("source_path") == PRODUCT_FORMAL_DRIVER_SOURCE,
             "#{label} Product formal Spring driver is absent from the actual Maven output")
      target_root = File.join(
        evidence_root, "dependency-custody/mysql-probe/build-2/maven-target"
      )
      fresh_repo = File.join(evidence_root, "dependency-custody/maven/fresh-repository-build-2")
      jar_paths = []
      Find.find(fresh_repo) do |entry|
        next unless File.file?(entry) && entry.end_with?(".jar")

        stat = File.lstat(entry)
        assert(!stat.symlink? && stat.nlink == 1 && (stat.mode & 0o777) == 0o444,
               "#{label} Product Spring classpath contains a mutable or aliased jar")
        jar_paths << entry
      end
      assert(!jar_paths.empty?, "#{label} Product Spring classpath has no dependency jars")
      spring_classpath = [File.join(target_root, "classes"),
                          File.join(target_root, "test-classes"), *jar_paths.sort].join(":")
    end
    {
      "last_seq" => build_sequences.max, "process_ids" => all_build_process_ids,
      "spring_classpath" => spring_classpath
    }
  rescue ArgumentError
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} rootfs escaped the Task Evidence root"
  end

  def validate_product_spring_runtime!(task_id, observations, records_by_id, evidence_root,
                                       candidate, role_stream_paths, probe_build_binding,
                                       mysql_logs, probe_start, probe_logs, probe_remove,
                                       probe_result)
    label = "P3 #{task_id} Product Spring runtime"
    assert(task_id == P2_TASK_ID, "#{label} is only valid for the final Product Task")
    dispatch = records_by_id.fetch(observations.fetch("spring_dispatch_process_id"))
    recovery = records_by_id.fetch(observations.fetch("spring_recovery_process_id"))
    assert(dispatch.fetch("process_id") != recovery.fetch("process_id"),
           "#{label} dispatch and recovery reused one process")
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    java_path = File.join(JDK17_HOME, "bin/java")
    classpath = probe_build_binding.fetch("spring_classpath")
    assert(classpath.is_a?(String) && !classpath.empty?,
           "#{label} lacks the actual Maven Product classpath")
    environment = {
      "PATH" => "#{JDK17_HOME}/bin:/usr/bin:/bin", "HOME" => "/var/empty",
      "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC", "JAVA_HOME" => JDK17_HOME
    }
    action = "PRODUCT_SPRING_MYSQL_ACCEPTANCE_V1"
    common = [
      "--task-id", task_id, "--candidate", candidate.fetch("commit"),
      "--action", action
    ]
    dispatch_argv = [
      "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, java_path,
      "-cp", classpath, PRODUCT_FORMAL_DRIVER_MAIN, "--mode", "dispatch", *common
    ]
    recovery_argv = [
      "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, java_path,
      "-cp", classpath, PRODUCT_FORMAL_DRIVER_MAIN, "--mode", "recover", *common
    ]
    invocation_id = Digest::SHA256.hexdigest(
      "#{task_id}\0#{candidate.fetch('commit')}\0#{action}"
    )[0, 32]
    custody_sha256 = Digest::SHA256.hexdigest("P3_TRIVS_PRODUCT_FORMAL_CUSTODY_V1")
    expected_dispatch = canonical_json(
      {
        "schema_version" => "p3-trivs-product-spring-dispatch/v1",
        "task_id" => task_id, "route_id" => ROUTE_ID, "candidate" => candidate,
        "invocation_id" => invocation_id, "action" => action,
        "custody_sha256" => custody_sha256, "spring_context_started" => true,
        "spring_transaction_proxy" => true, "production_service_store_called" => true,
        "durable_intent_created" => true, "verdict" => "READY_FOR_MYSQL_WORKER"
      }
    ) + "\n"
    dispatch_stdout = process_stream_bytes!(dispatch, "stdout", evidence_root,
                                            "#{label} dispatch stdout")
    dispatch_stderr = process_stream_bytes!(dispatch, "stderr", evidence_root,
                                            "#{label} dispatch stderr")
    probe_stdin = process_stream_bytes!(probe_start, "stdin", evidence_root,
                                        "#{label} MySQL worker stdin")
    assert(dispatch["kind"] == "JVM" && dispatch["purpose"] == "PRODUCT_SPRING_DISPATCH" &&
           dispatch["parent_process_id"].nil? && dispatch["child_process_ids"].empty? &&
           dispatch["cwd"] == verifier_root && dispatch["argv"] == dispatch_argv &&
           dispatch["environment"] == environment && dispatch["stdin"].nil? &&
           dispatch["network_mode"] == "DENY_NETWORK" && dispatch["exit_status"] == 0 &&
           dispatch["signal"].nil? &&
           dispatch.dig("target_executable_identity", "path") == java_path &&
           dispatch_stdout == expected_dispatch && dispatch_stderr.empty? &&
           probe_start.fetch("stdin") == dispatch.fetch("stdout") &&
           probe_stdin == dispatch_stdout,
           "#{label} dispatch is not the exact actual JDK17/Spring-to-MySQL handoff")
    assert(probe_result["invocation_id"] == invocation_id &&
           probe_result["spring_dispatch_sha256"] == Digest::SHA256.hexdigest(dispatch_stdout),
           "#{label} MySQL result did not bind the exact Spring dispatch bytes")

    probe_result_bytes = process_stream_bytes!(probe_start, "stdout", evidence_root,
                                               "#{label} MySQL worker stdout")
    recovery_stdin = process_stream_bytes!(recovery, "stdin", evidence_root,
                                           "#{label} recovery stdin")
    recovery_stdout = process_stream_bytes!(recovery, "stdout", evidence_root,
                                            "#{label} recovery stdout")
    recovery_stderr = process_stream_bytes!(recovery, "stderr", evidence_root,
                                            "#{label} recovery stderr")
    expected_recovery = canonical_json(
      {
        "schema_version" => "p3-trivs-product-spring-recovery/v1",
        "task_id" => task_id, "route_id" => ROUTE_ID, "candidate" => candidate,
        "invocation_id" => invocation_id,
        "probe_result_sha256" => Digest::SHA256.hexdigest(probe_result_bytes),
        "fresh_jvm" => true, "spring_context_started" => true,
        "startup_global_discovery" => true, "production_service_store_called" => true,
        "exactly_one_terminal" => 1, "verdict" => "PASS"
      }
    ) + "\n"
    assert(recovery["kind"] == "JVM" && recovery["purpose"] == "PRODUCT_SPRING_RECOVERY" &&
           recovery["parent_process_id"].nil? && recovery["child_process_ids"].empty? &&
           recovery["cwd"] == verifier_root && recovery["argv"] == recovery_argv &&
           recovery["environment"] == environment &&
           recovery.fetch("stdin") == probe_start.fetch("stdout") &&
           recovery_stdin == probe_result_bytes && recovery["network_mode"] == "DENY_NETWORK" &&
           recovery["exit_status"] == 0 && recovery["signal"].nil? &&
           recovery.dig("target_executable_identity", "path") == java_path &&
           recovery_stdout == expected_recovery && recovery_stderr.empty?,
           "#{label} recovery is not one exact fresh JDK17/Spring global-discovery process")
    assert([probe_build_binding.fetch("last_seq"), mysql_logs.fetch("seq")].max <
             dispatch.fetch("seq") &&
           dispatch.fetch("seq") < probe_start.fetch("seq") &&
           probe_start.fetch("seq") < probe_logs.fetch("seq") &&
           probe_logs.fetch("seq") < recovery.fetch("seq") &&
           recovery.fetch("seq") < probe_remove.fetch("seq"),
           "#{label} dispatch, MySQL work and fresh recovery order drift")
    [dispatch, recovery].each do |process|
      assert([process.dig("stdin", "path"), process.dig("stdout", "path"),
              process.dig("stderr", "path")].compact.all? { |path|
               role_stream_paths.include?(path)
             }, "#{label} process stream escaped the real MySQL artifact")
    end
    {
      "process_ids" => [dispatch.fetch("process_id"), recovery.fetch("process_id")],
      "spring_classpath" => classpath
    }
  end

  def validate_mysql_process_transcript!(root, task_id, observations, records_by_id, descriptors,
                                         process_ids, evidence_root, candidate, role_stream_paths)
    label = "P3 #{task_id} raw MySQL transcript"
    image_inspect = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_IMAGE_INSPECT", label)
    create = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_CONTAINER_CREATE", label)
    start = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_CONTAINER_START", label)
    inspect = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_CONTAINER_INSPECT", label)
    logs = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_CONTAINER_LOGS", label)
    probe_import = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_IMAGE_IMPORT", label)
    probe_image_inspect = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_IMAGE_INSPECT", label)
    probe_create = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_CONTAINER_CREATE", label)
    probe_start = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_CONTAINER_START", label)
    probe_wait = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_CONTAINER_WAIT", label)
    probe_inspect = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_CONTAINER_INSPECT", label)
    probe_logs = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_CONTAINER_LOGS", label)
    probe_remove = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_CONTAINER_REMOVE", label)
    probe_absent = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_CONTAINER_ABSENCE", label)
    probe_image_remove = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_IMAGE_REMOVE", label)
    probe_image_absent = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_PROBE_IMAGE_ABSENCE", label)
    remove = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_CONTAINER_REMOVE", label)
    absent = one_process!(records_by_id, process_ids, "DOCKER", "MYSQL_CONTAINER_ABSENCE", label)
    required = [image_inspect, create, start, inspect, logs, probe_import, probe_image_inspect,
                probe_create, probe_start, probe_wait, probe_inspect, probe_logs, probe_remove,
                probe_absent, probe_image_remove, probe_image_absent, remove, absent]
    assert(process_ids.sort == required.map { |record| record.fetch("process_id") }.sort,
           "#{label} contains an unrelated or missing process")
    probe_build_binding = validate_mysql_probe_build_binding!(
      root, task_id, observations, records_by_id, evidence_root, candidate, role_stream_paths
    )

    image_descriptor = descriptors.fetch(image_inspect.fetch("process_id"))
    create_descriptor = descriptors.fetch(create.fetch("process_id"))
    container = create_descriptor.fetch("container")
    probe_import_descriptor = descriptors.fetch(probe_import.fetch("process_id"))
    probe_image = probe_import_descriptor.fetch("image")
    probe_create_descriptor = descriptors.fetch(probe_create.fetch("process_id"))
    probe_container = probe_create_descriptor.fetch("container")
    assert(image_descriptor == {"operation" => "image inspect", "image" => MYSQL_IMAGE_CONTENT_ID} &&
           create_descriptor["operation"] == "create" && create_descriptor["kind"] == "mysql" &&
           [start, inspect, logs, remove, absent].all? { |record|
             descriptors.fetch(record.fetch("process_id"))["container"] == container
           } && probe_import_descriptor["operation"] == "image import" &&
           probe_import_descriptor["input"] == observations.dig("probe_rootfs_identity", "path") &&
           probe_image == observations["probe_image"] &&
           descriptors.fetch(probe_image_inspect.fetch("process_id"))["image"] == probe_image &&
           probe_create_descriptor["operation"] == "create" &&
           probe_create_descriptor["kind"] == "mysql-probe" &&
           probe_create_descriptor["mysql_container"] == container &&
           probe_create_descriptor["image"] == probe_image &&
           probe_create_descriptor["action"] == observations["probe_action"] &&
           [probe_start, probe_wait, probe_inspect, probe_logs, probe_remove, probe_absent].all? { |record|
             descriptors.fetch(record.fetch("process_id"))["container"] == probe_container
           } && [probe_image_remove, probe_image_absent].all? { |record|
             descriptors.fetch(record.fetch("process_id"))["image"] == probe_image
           }, "#{label} mixed a non-Task or different Docker object")

    image_stdout, = docker_success_streams!(image_inspect, evidence_root, "#{label} image inspect")
    image_object = docker_json_object!(image_stdout, "#{label} image inspect stdout")
    assert(image_object["Id"] == MYSQL_IMAGE_CONTENT_ID,
           "#{label} did not resolve the pinned MySQL content ID")

    create_stdout, = docker_success_streams!(create, evidence_root, "#{label} create")
    container_id = create_stdout.strip
    assert(container_id.match?(/\A[0-9a-f]{64}\z/), "#{label} create did not return one container ID")
    start_stdout, = docker_success_streams!(start, evidence_root, "#{label} start")
    assert(start_stdout == "#{container}\n", "#{label} start output drift")
    inspect_stdout, = docker_success_streams!(inspect, evidence_root, "#{label} inspect")
    object = docker_json_object!(inspect_stdout, "#{label} inspect stdout")
    assert(object["Id"] == container_id && object["Name"] == "/#{container}" &&
           object["Image"] == MYSQL_IMAGE_CONTENT_ID &&
           object.dig("Config", "Image") == MYSQL_IMAGE_CONTENT_ID,
           "#{label} inspect did not bind the created pinned-image container")
    assert_task_labels!(object.dig("Config", "Labels"), task_id, "mysql", label)
    host = object.fetch("HostConfig")
    assert(host["Privileged"] == false && [nil, []].include?(host["Binds"]) &&
           host["NetworkMode"] == "none" && host["Memory"] == 1_073_741_824 &&
           host["NanoCpus"] == 1_000_000_000 && host["PidsLimit"] == 256 &&
           [nil, {}].include?(host["PortBindings"]) &&
           [nil, {}].include?(object.dig("NetworkSettings", "Ports")),
           "#{label} inspect did not prove daemon-level no-egress MySQL creation")
    mysql_sandbox_key = object.dig("NetworkSettings", "SandboxKey")
    assert(mysql_sandbox_key.is_a?(String) && !mysql_sandbox_key.empty?,
           "#{label} MySQL network namespace identity is absent")
    log_stdout, log_stderr = docker_success_streams!(
      logs, evidence_root, "#{label} logs", stderr_may_be_nonempty: true
    )
    assert(!(log_stdout + log_stderr).empty?, "#{label} retained no real MySQL log transcript")

    probe_import_stdout, = docker_success_streams!(probe_import, evidence_root, "#{label} probe import")
    probe_image_id = probe_import_stdout.strip
    assert(probe_image_id.match?(/\Asha256:[0-9a-f]{64}\z/),
           "#{label} probe import output is not one image ID")
    probe_image_stdout, = docker_success_streams!(
      probe_image_inspect, evidence_root, "#{label} probe image inspect"
    )
    assert(docker_json_object!(probe_image_stdout, "#{label} probe image inspect stdout")["Id"] ==
           probe_image_id, "#{label} probe image identity drift")
    probe_create_stdout, = docker_success_streams!(probe_create, evidence_root, "#{label} probe create")
    probe_container_id = probe_create_stdout.strip
    assert(probe_container_id.match?(/\A[0-9a-f]{64}\z/),
           "#{label} probe create did not return one container ID")
    probe_stdout, = docker_success_streams!(probe_start, evidence_root, "#{label} probe start")
    probe_wait_stdout, = docker_success_streams!(probe_wait, evidence_root, "#{label} probe wait")
    assert(probe_wait_stdout == "0\n", "#{label} probe wait did not observe success")
    probe_inspect_stdout, = docker_success_streams!(
      probe_inspect, evidence_root, "#{label} probe inspect"
    )
    probe_object = docker_json_object!(probe_inspect_stdout, "#{label} probe inspect stdout")
    assert(probe_object["Id"] == probe_container_id &&
           probe_object["Name"] == "/#{probe_container}" && probe_object["Image"] == probe_image_id &&
           probe_object.dig("Config", "Image") == probe_image &&
           probe_object.dig("Config", "OpenStdin") == (task_id == P2_TASK_ID),
           "#{label} probe inspect did not bind the imported probe image")
    assert_task_labels!(probe_object.dig("Config", "Labels"), task_id, "mysql-probe", label)
    probe_host = probe_object.fetch("HostConfig")
    assert(probe_host["Privileged"] == false && [nil, []].include?(probe_host["Binds"]) &&
           ["container:#{container}", "container:#{container_id}"].include?(probe_host["NetworkMode"]) &&
           probe_object.dig("NetworkSettings", "SandboxKey") == mysql_sandbox_key &&
           probe_host["ReadonlyRootfs"] == true && probe_host["Memory"] == 536_870_912 &&
           probe_host["NanoCpus"] == 1_000_000_000 && probe_host["PidsLimit"] == 256 &&
           probe_host["CapDrop"] == ["ALL"] &&
           Array(probe_host["SecurityOpt"]).include?("no-new-privileges") &&
           probe_object.dig("Config", "User") == "65532:65532" &&
           probe_object.dig("Config", "Entrypoint") == ["/probe"] &&
           probe_object.dig("Config", "Cmd") == [observations["probe_action"]],
           "#{label} probe did not share only the no-egress MySQL loopback namespace")

    probe_result = parse_json!(probe_stdout, "#{label} probe result")
    probe_result_keys = %w[
      schema_version task_id route_id candidate action mysql_container mysql_container_id
      probe_container probe_container_id mysql_image_content_id probe_image probe_image_id
      source_manifest_sha256 class_inventory_sha256 rootfs_sha256 events verdict
    ]
    probe_result_keys += %w[invocation_id spring_dispatch_sha256] if task_id == P2_TASK_ID
    probe_result = exact_mapping(probe_result, probe_result_keys, "#{label} probe result")
    expected_events = if task_id == F2_TASK_ID
                        {
                          "MYSQL_SERVER_UUID" => :uuid, "PRE_MIGRATION_USER_TABLE_COUNT" => 0,
                          "MIGRATION_SET_APPLIED" => true, "TRANSACTION_COMMIT" => 1,
                          "TRANSACTION_ROLLBACK" => 0, "TEMPORARY_STATE_CLEAN" => true
                        }
                      else
                        {
                          "MYSQL_SERVER_UUID" => :uuid, "PRE_MIGRATION_USER_TABLE_COUNT" => 0,
                          "MIGRATION_V034_APPLIED" => true, "TRANSACTION_COMMIT" => 1,
                          "TRANSACTION_ROLLBACK" => true, "EXACTLY_ONE_INTENT" => 1,
                          "EXACTLY_ONE_TERMINAL" => 1, "LATE_LOSER_REJECTED" => true,
                        }
                      end
    events = probe_result["events"]
    assert(events.is_a?(Array) && events.length == expected_events.length,
           "#{label} probe event set is incomplete")
    events.each_with_index do |event, index|
      event = exact_mapping(event, %w[seq event observed raw_evidence_sha256],
                            "#{label} probe event #{index + 1}")
      expected = expected_events.to_a.fetch(index)
      observed_ok = expected.last == :uuid ?
        event["observed"].is_a?(String) &&
          event["observed"].match?(/\A[0-9a-f]{8}-[0-9a-f-]{27,}\z/) :
        event["observed"] == expected.last
      assert(event["seq"] == index + 1 && event["event"] == expected.first && observed_ok &&
             event["raw_evidence_sha256"].is_a?(String) &&
             event["raw_evidence_sha256"].match?(/\A[0-9a-f]{64}\z/),
             "#{label} probe event #{index + 1} drift")
    end
    assert(probe_result["schema_version"] == "p3-trivs-mysql-container-probe-result/v1" &&
           probe_result["task_id"] == task_id && probe_result["route_id"] == ROUTE_ID &&
           probe_result["candidate"] == candidate && probe_result["action"] == observations["probe_action"] &&
           probe_result["mysql_container"] == container &&
           probe_result["mysql_container_id"] == container_id &&
           probe_result["probe_container"] == probe_container &&
           probe_result["probe_container_id"] == probe_container_id &&
           probe_result["mysql_image_content_id"] == MYSQL_IMAGE_CONTENT_ID &&
           probe_result["probe_image"] == probe_image && probe_result["probe_image_id"] == probe_image_id &&
           probe_result["source_manifest_sha256"] == observations.dig("probe_source_manifest", "sha256") &&
           probe_result["class_inventory_sha256"] ==
             observations.dig("probe_class_inventory_build_1", "sha256") &&
           probe_result["rootfs_sha256"] == observations.dig("probe_rootfs_identity", "sha256") &&
           (task_id != P2_TASK_ID ||
             (probe_result["invocation_id"].is_a?(String) &&
              probe_result["invocation_id"].match?(/\A[0-9a-f]{32}\z/) &&
              probe_result["spring_dispatch_sha256"].is_a?(String) &&
              probe_result["spring_dispatch_sha256"].match?(/\A[0-9a-f]{64}\z/))) &&
           probe_result["verdict"] == "PASS",
           "#{label} probe did not derive fresh bound MySQL acceptance")
    probe_logs_stdout, probe_logs_stderr = docker_success_streams!(
      probe_logs, evidence_root, "#{label} probe logs"
    )
    assert(probe_logs_stdout == probe_stdout && probe_logs_stderr.empty?,
           "#{label} probe logs differ from the attached raw result")
    runtime_binding = if task_id == P2_TASK_ID
                        validate_product_spring_runtime!(
                          task_id, observations, records_by_id, evidence_root, candidate,
                          role_stream_paths, probe_build_binding, logs, probe_start, probe_logs,
                          probe_remove, probe_result
                        )
                      else
                        assert(probe_start["stdin"].nil?,
                               "#{label} Foundation probe unexpectedly accepted caller input")
                        {"process_ids" => [], "spring_classpath" => nil}
                      end

    probe_remove_stdout, = docker_success_streams!(
      probe_remove, evidence_root, "#{label} probe remove"
    )
    assert(probe_remove_stdout == "#{probe_container}\n", "#{label} probe remove output drift")
    probe_absent_stdout = process_stream_bytes!(
      probe_absent, "stdout", evidence_root, "#{label} probe absence"
    )
    probe_absent_stderr = process_stream_bytes!(
      probe_absent, "stderr", evidence_root, "#{label} probe absence"
    )
    assert(probe_absent["exit_status"] != 0 && probe_absent_stdout.empty? &&
           probe_absent_stderr.include?(probe_container) &&
           probe_absent_stderr.match?(/No such (?:object|container)/i),
           "#{label} did not prove probe-container absence")
    probe_rmi_stdout, = docker_success_streams!(
      probe_image_remove, evidence_root, "#{label} probe image remove"
    )
    assert(probe_rmi_stdout.include?(probe_image) || probe_rmi_stdout.include?(probe_image_id),
           "#{label} probe image removal output drift")
    probe_image_absent_stdout = process_stream_bytes!(
      probe_image_absent, "stdout", evidence_root, "#{label} probe image absence"
    )
    probe_image_absent_stderr = process_stream_bytes!(
      probe_image_absent, "stderr", evidence_root, "#{label} probe image absence"
    )
    assert(probe_image_absent["exit_status"] != 0 && probe_image_absent_stdout.empty? &&
           probe_image_absent_stderr.include?(probe_image) &&
           probe_image_absent_stderr.match?(/No such (?:image|object)/i),
           "#{label} did not prove probe-image absence")

    remove_stdout, = docker_success_streams!(remove, evidence_root, "#{label} remove")
    assert(remove_stdout == "#{container}\n", "#{label} remove output drift")
    absent_stdout = process_stream_bytes!(absent, "stdout", evidence_root, "#{label} absence")
    absent_stderr = process_stream_bytes!(absent, "stderr", evidence_root, "#{label} absence")
    assert(absent["exit_status"] != 0 && absent["signal"].nil? && absent_stdout.empty? &&
           absent_stderr.include?(container) && absent_stderr.match?(/No such (?:object|container)/i),
           "#{label} did not prove task-container absence after cleanup")
    sequence = required.map { |record| record["seq"] }
    assert(sequence == sequence.sort && sequence.uniq.length == sequence.length &&
           probe_build_binding.fetch("last_seq") < probe_import["seq"],
           "#{label} operation order is not monotonic")
    {
      "docker_process_ids" => required.map { |record| record.fetch("process_id") },
      "non_docker_process_ids" =>
        probe_build_binding.fetch("process_ids") + runtime_binding.fetch("process_ids"),
      "spring_classpath" => runtime_binding.fetch("spring_classpath")
    }
  end

  def validate_oci_process_transcript!(task_id, records_by_id, descriptors, process_ids,
                                       evidence_root, helper_binding)
    label = "P3 #{task_id} raw OCI transcript"
    image_import = one_process!(records_by_id, process_ids, "DOCKER", "OCI_IMAGE_IMPORT", label)
    image_inspect = one_process!(records_by_id, process_ids, "DOCKER", "OCI_IMAGE_INSPECT", label)
    create = one_process!(records_by_id, process_ids, "DOCKER", "OCI_CONTAINER_CREATE", label)
    start = one_process!(records_by_id, process_ids, "DOCKER", "OCI_CONTAINER_START", label)
    wait = one_process!(records_by_id, process_ids, "DOCKER", "OCI_CONTAINER_WAIT", label)
    inspect = one_process!(records_by_id, process_ids, "DOCKER", "OCI_CONTAINER_INSPECT", label)
    logs = one_process!(records_by_id, process_ids, "DOCKER", "OCI_CONTAINER_LOGS", label)
    remove = one_process!(records_by_id, process_ids, "DOCKER", "OCI_CONTAINER_REMOVE", label)
    absent = one_process!(records_by_id, process_ids, "DOCKER", "OCI_CONTAINER_ABSENCE", label)
    image_remove = one_process!(records_by_id, process_ids, "DOCKER", "OCI_IMAGE_REMOVE", label)
    image_absent = one_process!(records_by_id, process_ids, "DOCKER", "OCI_IMAGE_ABSENCE", label)
    required = [image_import, image_inspect, create, start, wait, inspect, logs,
                remove, absent, image_remove, image_absent]
    assert(process_ids.sort == required.map { |record| record.fetch("process_id") }.sort,
           "#{label} contains an unrelated or missing process")

    import_descriptor = descriptors.fetch(image_import.fetch("process_id"))
    image = import_descriptor.fetch("image")
    input_path = import_descriptor.fetch("input")
    container_descriptor = descriptors.fetch(create.fetch("process_id"))
    container = container_descriptor.fetch("container")
    assert(import_descriptor["operation"] == "image import" &&
           File.basename(input_path, ".tar") == helper_binding.fetch("rootfs_sha256") &&
           image.end_with?("sha256-#{helper_binding.fetch('rootfs_sha256')[0, 12]}") &&
           container_descriptor["operation"] == "create" && container_descriptor["kind"] == "oci" &&
           container_descriptor["image"] == image &&
           [start, wait, inspect, logs, remove, absent].all? { |record|
             descriptors.fetch(record.fetch("process_id"))["container"] == container
           } && [image_inspect, image_remove, image_absent].all? { |record|
             descriptors.fetch(record.fetch("process_id"))["image"] == image
           }, "#{label} mixed non-Task OCI objects")

    import_stdout, = docker_success_streams!(image_import, evidence_root, "#{label} import")
    image_id = import_stdout.strip
    assert(image_id.match?(/\Asha256:[0-9a-f]{64}\z/), "#{label} import output is not one image ID")
    inspect_image_stdout, = docker_success_streams!(
      image_inspect, evidence_root, "#{label} image inspect"
    )
    image_object = docker_json_object!(inspect_image_stdout, "#{label} image inspect stdout")
    assert(image_object["Id"] == image_id, "#{label} imported image identity drift")

    create_stdout, = docker_success_streams!(create, evidence_root, "#{label} create")
    container_id = create_stdout.strip
    assert(container_id.match?(/\A[0-9a-f]{64}\z/), "#{label} create did not return one container ID")
    custody_bytes = process_stream_bytes!(start, "stdin", evidence_root, "#{label} start")
    expected_digest = Digest::SHA256.hexdigest(custody_bytes)
    start_stdout, = docker_success_streams!(start, evidence_root, "#{label} start")
    assert(start_stdout == "#{expected_digest}\n", "#{label} helper output did not hash exact stdin bytes")
    wait_stdout, = docker_success_streams!(wait, evidence_root, "#{label} wait")
    assert(wait_stdout == "0\n", "#{label} wait did not observe helper success")
    inspect_stdout, = docker_success_streams!(inspect, evidence_root, "#{label} inspect")
    object = docker_json_object!(inspect_stdout, "#{label} inspect stdout")
    assert(object["Id"] == container_id && object["Name"] == "/#{container}" &&
           object["Image"] == image_id && object.dig("Config", "Image") == image,
           "#{label} inspect did not bind the imported image and created container")
    assert_task_labels!(object.dig("Config", "Labels"), task_id, "oci", label)
    host = object.fetch("HostConfig")
    assert(host["Privileged"] == false && [nil, []].include?(host["Binds"]) &&
           host["NetworkMode"] == "none" && host["ReadonlyRootfs"] == true &&
           host["Memory"] == 67_108_864 && host["NanoCpus"] == 500_000_000 &&
           host["PidsLimit"] == 32 && host["CapDrop"] == ["ALL"] &&
           Array(host["SecurityOpt"]).include?("no-new-privileges") &&
           object.dig("Config", "User") == "65532:65532" &&
           object.dig("Config", "Entrypoint") == ["/helper"] &&
           object.dig("Config", "Cmd") == ["SHA256_READ_ONLY_CUSTODY_V1"],
           "#{label} inspect did not prove network-none read-only bounded OCI execution")
    logs_stdout, logs_stderr = docker_success_streams!(logs, evidence_root, "#{label} logs")
    assert(logs_stdout == "#{expected_digest}\n" && logs_stderr.empty?,
           "#{label} logs did not preserve exact helper output")
    remove_stdout, = docker_success_streams!(remove, evidence_root, "#{label} remove")
    assert(remove_stdout == "#{container}\n", "#{label} remove output drift")
    absent_stdout = process_stream_bytes!(absent, "stdout", evidence_root, "#{label} absence")
    absent_stderr = process_stream_bytes!(absent, "stderr", evidence_root, "#{label} absence")
    assert(absent["exit_status"] != 0 && absent_stdout.empty? && absent_stderr.include?(container) &&
           absent_stderr.match?(/No such (?:object|container)/i),
           "#{label} did not prove OCI container absence")
    rmi_stdout, = docker_success_streams!(image_remove, evidence_root, "#{label} image remove")
    assert(rmi_stdout.include?(image) || rmi_stdout.include?(image_id),
           "#{label} image removal output did not bind the scoped image")
    image_absent_stdout = process_stream_bytes!(
      image_absent, "stdout", evidence_root, "#{label} image absence"
    )
    image_absent_stderr = process_stream_bytes!(
      image_absent, "stderr", evidence_root, "#{label} image absence"
    )
    assert(image_absent["exit_status"] != 0 && image_absent_stdout.empty? &&
           image_absent_stderr.include?(image) &&
           image_absent_stderr.match?(/No such (?:image|object)/i),
           "#{label} did not prove scoped image absence")
    sequence = [image_import, image_inspect, create, start, wait, inspect, logs,
                remove, absent, image_remove, image_absent].map { |r| r["seq"] }
    assert(sequence == sequence.sort && sequence.uniq.length == sequence.length &&
           helper_binding.fetch("last_seq") < image_import.fetch("seq"),
           "#{label} operation order is not monotonic")
    {
      "process_ids" => required.map { |record| record.fetch("process_id") },
      "records" => {
        "image_import" => image_import, "image_inspect" => image_inspect,
        "create" => create, "start" => start, "wait" => wait, "inspect" => inspect,
        "logs" => logs, "remove" => remove, "absent" => absent,
        "image_remove" => image_remove, "image_absent" => image_absent
      }
    }
  end

  def validate_adversarial_processes!(task_id, observations, records_by_id, evidence_root,
                                      candidate, role_stream_paths)
    label = "P3 #{task_id} adversarial process matrix"
    cases = task_id == F2_TASK_ID ? F2_ADVERSARIAL_CASES : P2_ADVERSARIAL_CASES
    process_ids = observations.fetch("process_ids")
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    harness_script =
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/run.mjs"
    environment = {
      "PATH" => "#{File.dirname(NODE22_RUNTIME_PATH)}:/usr/bin:/bin", "HOME" => "/var/empty",
      "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC"
    }
    sequences = cases.each_with_index.map do |case_id, index|
      process = records_by_id.fetch(process_ids.fetch(index))
      purpose = "ADVERSARIAL_#{case_id.upcase.tr('-', '_')}"
      expected_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
        harness_script, "--mode", "adversarial", "--case", case_id,
        "--candidate", candidate.fetch("commit"), "--evidence-root", evidence_root
      ]
      stdout = process_stream_bytes!(process, "stdout", evidence_root, "#{label} #{case_id}")
      stderr = process_stream_bytes!(process, "stderr", evidence_root, "#{label} #{case_id}")
      assert(process["kind"] == "ADVERSARIAL" && process["purpose"] == purpose &&
             process["parent_process_id"].nil? && process["child_process_ids"].empty? &&
             process["cwd"] == verifier_root && process["argv"] == expected_argv &&
             process["environment"] == environment && process["stdin"].nil? &&
             process["network_mode"] == "DENY_NETWORK" && process["exit_status"] == 64 &&
             process["signal"].nil? &&
             process.dig("target_executable_identity", "path") == NODE22_RUNTIME_PATH &&
             stdout.empty? && stderr == "ADVERSARIAL_REJECTED:#{case_id}\n" &&
             [process.dig("stdout", "path"), process.dig("stderr", "path")].all? { |path|
               role_stream_paths.include?(path)
             }, "#{label} #{case_id} is not the exact fail-closed mutation process")
      process.fetch("seq")
    end
    assert(sequences == sequences.sort && sequences.uniq.length == sequences.length,
           "#{label} process order drift")
    process_ids
  end

  def validate_seven_kill_processes!(task_id, observations, records_by_id, evidence_root,
                                     candidate, role_stream_paths, spring_classpath,
                                     oci_binding, helper_binding)
    label = "P3 #{task_id} seven-kill process matrix"
    process_ids = observations.fetch("process_ids")
    assert(process_ids.length == KILL_POINTS.length * 2,
           "#{label} is not exactly seven victim/recovery pairs")
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    harness_script =
      "evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/run.mjs"
    product = task_id == P2_TASK_ID
    java_path = File.join(JDK17_HOME, "bin/java")
    assert(!product || (spring_classpath.is_a?(String) && !spring_classpath.empty?),
           "#{label} Product kill matrix lacks the actual Maven Spring classpath")
    environment = if product
                    {
                      "PATH" => "#{JDK17_HOME}/bin:/usr/bin:/bin", "HOME" => "/var/empty",
                      "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC",
                      "JAVA_HOME" => JDK17_HOME
                    }
                  else
                    {
                      "PATH" => "#{File.dirname(NODE22_RUNTIME_PATH)}:/usr/bin:/bin",
                      "HOME" => "/var/empty", "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC"
                    }
                  end
    oci = oci_binding.fetch("records")
    anchor_sha256 = {
      "before-import" => helper_binding.fetch("rootfs_sha256"),
      "after-import" => Digest::SHA256.hexdigest(
        process_stream_bytes!(oci.fetch("image_import"), "stdout", evidence_root,
                              "#{label} after-import anchor")
      ),
      "after-create" => Digest::SHA256.hexdigest(
        process_stream_bytes!(oci.fetch("create"), "stdout", evidence_root,
                              "#{label} after-create anchor")
      ),
      "after-start" => Digest::SHA256.hexdigest(
        process_stream_bytes!(oci.fetch("start"), "stdout", evidence_root,
                              "#{label} after-start anchor")
      ),
      "after-wait" => Digest::SHA256.hexdigest(
        process_stream_bytes!(oci.fetch("wait"), "stdout", evidence_root,
                              "#{label} after-wait anchor")
      ),
      "after-remove" => Digest::SHA256.hexdigest(
        process_stream_bytes!(oci.fetch("remove"), "stdout", evidence_root,
                              "#{label} after-remove anchor")
      ),
      "before-terminal-commit" => Digest::SHA256.hexdigest(
        process_stream_bytes!(oci.fetch("image_absent"), "stderr", evidence_root,
                              "#{label} before-terminal anchor")
      )
    }
    assert(anchor_sha256.keys == KILL_POINTS && anchor_sha256.values.all? { |value|
             value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
           }, "#{label} real OCI anchor identity drift")
    sequences = []
    pairs = {}
    KILL_POINTS.each_with_index do |kill_point, index|
      victim = records_by_id.fetch(process_ids.fetch(index * 2))
      recovery = records_by_id.fetch(process_ids.fetch(index * 2 + 1))
      normalized_point = kill_point.upcase.tr("-", "_")
      invocation_id = Digest::SHA256.hexdigest(
        "#{task_id}\0#{candidate.fetch('commit')}\0#{kill_point}\0#{anchor_sha256.fetch(kill_point)}"
      )[0, 32]
      if product
        common = [
          "--task-id", task_id, "--candidate", candidate.fetch("commit"),
          "--kill-point", kill_point, "--anchor-sha256", anchor_sha256.fetch(kill_point)
        ]
        victim_argv = [
          "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, java_path,
          "-cp", spring_classpath, PRODUCT_FORMAL_DRIVER_MAIN,
          "--mode", "kill-victim", *common
        ]
        recovery_argv = [
          "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, java_path,
          "-cp", spring_classpath, PRODUCT_FORMAL_DRIVER_MAIN,
          "--mode", "startup-recovery", *common
        ]
      else
        common = [
          "--candidate", candidate.fetch("commit"), "--kill-point", kill_point,
          "--anchor-sha256", anchor_sha256.fetch(kill_point),
          "--evidence-root", evidence_root
        ]
        victim_argv = [
          "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
          harness_script, "--mode", "kill-victim", *common
        ]
        recovery_argv = [
          "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
          harness_script, "--mode", "recover-after-kill", *common
        ]
      end
      victim_stdout = process_stream_bytes!(victim, "stdout", evidence_root,
                                            "#{label} #{kill_point} victim")
      victim_stderr = process_stream_bytes!(victim, "stderr", evidence_root,
                                            "#{label} #{kill_point} victim")
      recovery_stdout = process_stream_bytes!(recovery, "stdout", evidence_root,
                                              "#{label} #{kill_point} recovery")
      recovery_stderr = process_stream_bytes!(recovery, "stderr", evidence_root,
                                              "#{label} #{kill_point} recovery")
      victim_result = {
        "schema_version" => "p3-trivs-seven-kill-checkpoint/v1", "task_id" => task_id,
        "route_id" => ROUTE_ID, "candidate" => candidate, "kill_point" => kill_point,
        "anchor_sha256" => anchor_sha256.fetch(kill_point),
        "state" => "CHECKPOINT_REACHED_BEFORE_SIGKILL"
      }
      expected_victim = canonical_json(victim_result) + "\n"
      recovery_result = {
        "schema_version" => "p3-trivs-seven-kill-recovery-result/v1", "task_id" => task_id,
        "route_id" => ROUTE_ID, "candidate" => candidate, "kill_point" => kill_point,
        "anchor_sha256" => anchor_sha256.fetch(kill_point),
        "checkpoint_sha256" => Digest::SHA256.hexdigest(expected_victim),
        "fresh_process" => true, "exactly_one_terminal" => 1, "duplicate_effects" => 0,
        "orphan_objects" => 0, "permanent_dispatching" => 0, "verdict" => "PASS"
      }
      if product
        victim_result.merge!("invocation_id" => invocation_id, "runtime" => "JDK17_SPRING")
        recovery_result.merge!(
          "invocation_id" => invocation_id, "fresh_jvm" => true,
          "spring_context_started" => true, "startup_global_discovery" => true,
          "production_service_store_called" => true
        )
        expected_victim = canonical_json(victim_result) + "\n"
        recovery_result["checkpoint_sha256"] = Digest::SHA256.hexdigest(expected_victim)
      end
      expected_recovery = canonical_json(recovery_result) + "\n"
      expected_kind = product ? "JVM" : "HARNESS"
      expected_target = product ? java_path : NODE22_RUNTIME_PATH
      assert(victim["kind"] == expected_kind &&
             victim["purpose"] == "SEVEN_KILL_VICTIM_#{normalized_point}" &&
             victim["parent_process_id"].nil? && victim["child_process_ids"].empty? &&
             victim["cwd"] == verifier_root && victim["argv"] == victim_argv &&
             victim["environment"] == environment && victim["stdin"].nil? &&
             victim["network_mode"] == "DENY_NETWORK" && victim["exit_status"] == 137 &&
             victim["signal"] == 9 &&
             victim.dig("target_executable_identity", "path") == expected_target &&
             victim_stdout == expected_victim && victim_stderr.empty?,
             "#{label} #{kill_point} victim is not one exact real SIGKILL checkpoint")
      recovery_stdin = process_stream_bytes!(recovery, "stdin", evidence_root,
                                             "#{label} #{kill_point} recovery stdin")
      assert(recovery["kind"] == expected_kind &&
             recovery["purpose"] == "SEVEN_KILL_RECOVERY_#{normalized_point}" &&
             recovery["parent_process_id"].nil? && recovery["child_process_ids"].empty? &&
             recovery["cwd"] == verifier_root && recovery["argv"] == recovery_argv &&
             recovery["environment"] == environment &&
             recovery.fetch("stdin") == victim.fetch("stdout") &&
             recovery_stdin == victim_stdout &&
             recovery["network_mode"] == "DENY_NETWORK" && recovery["exit_status"] == 0 &&
             recovery["signal"].nil? &&
             recovery.dig("target_executable_identity", "path") == expected_target &&
             recovery_stdout == expected_recovery && recovery_stderr.empty? &&
             victim.fetch("seq") < recovery.fetch("seq"),
             "#{label} #{kill_point} recovery is not one exact fresh-process closure")
      [victim, recovery].each do |process|
        assert([process.dig("stdout", "path"), process.dig("stderr", "path")].all? { |path|
                 role_stream_paths.include?(path)
               }, "#{label} #{kill_point} process stream escaped its artifact")
      end
      sequences.concat([victim.fetch("seq"), recovery.fetch("seq")])
      pairs[kill_point] = {"victim" => victim, "recovery" => recovery}
    end
    assert(sequences == sequences.sort && sequences.uniq.length == sequences.length,
           "#{label} pair order drift")
    {"process_ids" => process_ids, "pairs" => pairs}
  end

  def validate_seven_kill_oci_anchors!(task_id, kill_binding, oci_binding, helper_binding,
                                       replay_process)
    label = "P3 #{task_id} seven-kill OCI anchors"
    pairs = kill_binding.fetch("pairs")
    oci = oci_binding.fetch("records")
    bounds = {
      "before-import" => [helper_binding.fetch("last_seq"), oci.fetch("image_import")],
      "after-import" => [oci.fetch("image_import"), oci.fetch("image_inspect")],
      "after-create" => [oci.fetch("create"), oci.fetch("start")],
      "after-start" => [oci.fetch("start"), oci.fetch("wait")],
      "after-wait" => [oci.fetch("wait"), oci.fetch("inspect")],
      "after-remove" => [oci.fetch("remove"), oci.fetch("absent")],
      "before-terminal-commit" => [oci.fetch("image_absent"), replay_process]
    }
    assert(pairs.keys == KILL_POINTS && bounds.keys == KILL_POINTS,
           "#{label} point set drift")
    KILL_POINTS.each do |kill_point|
      pair = pairs.fetch(kill_point)
      lower, upper = bounds.fetch(kill_point)
      victim_seq = pair.fetch("victim").fetch("seq")
      recovery_seq = pair.fetch("recovery").fetch("seq")
      lower_seq = lower.is_a?(Integer) ? lower : lower.fetch("seq")
      assert(lower_seq < victim_seq &&
             victim_seq < recovery_seq && recovery_seq < upper.fetch("seq"),
             "#{label} #{kill_point} is not anchored to the same real OCI transcript")
    end
    true
  end

  def validate_independent_replay_process!(task_id, observations, records_by_id, evidence_root,
                                           candidate, role_stream_paths, expected_metrics)
    label = "P3 #{task_id} independent raw replay"
    process_id = observations.fetch("process_ids").fetch(0)
    process = records_by_id.fetch(process_id)
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    replay_path = observations.dig("replayer_identity", "path")
    expected_argv = [
      "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
      replay_path, "--mode", "raw-evidence", "--candidate", candidate.fetch("commit"),
      "--evidence-root", evidence_root
    ]
    environment = {
      "PATH" => "#{File.dirname(NODE22_RUNTIME_PATH)}:/usr/bin:/bin", "HOME" => "/var/empty",
      "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC"
    }
    stdout = process_stream_bytes!(process, "stdout", evidence_root, label)
    stderr = process_stream_bytes!(process, "stderr", evidence_root, label)
    output = exact_mapping(parse_json!(stdout, label), %w[
      schema_version task_id route_id candidate input_artifact_roles derived_metrics verdict
    ], label)
    assert(process["kind"] == "REPLAY" && process["purpose"] == "INDEPENDENT_RAW_REPLAY" &&
           process["parent_process_id"].nil? && process["child_process_ids"].empty? &&
           process["cwd"] == verifier_root && process["argv"] == expected_argv &&
           process["environment"] == environment && process["stdin"].nil? &&
           process["network_mode"] == "DENY_NETWORK" && process["exit_status"] == 0 &&
           process["signal"].nil? &&
           process.dig("target_executable_identity", "path") == NODE22_RUNTIME_PATH &&
           stderr.empty? && output == {
             "schema_version" => "p3-trivs-independent-raw-replay-result/v1",
             "task_id" => task_id, "route_id" => ROUTE_ID, "candidate" => candidate,
             "input_artifact_roles" => observations.fetch("input_artifact_roles"),
             "derived_metrics" => expected_metrics, "verdict" => "PASS"
           } && [process.dig("stdout", "path"), process.dig("stderr", "path")].all? { |path|
             role_stream_paths.include?(path)
           }, "#{label} is not the exact candidate-bound replay process")
    process_id
  end

  def validate_candidate_diff!(root, activation_parent, candidate_commit, allowlist, task_id,
                               require_delivery: true)
    output = git!(
      root, "diff", "--name-status", "-z", "--no-renames", activation_parent, candidate_commit
    ).first
    fields = output.split("\0").reject(&:empty?)
    assert(fields.length.even?, "#{task_id} candidate diff status stream is malformed")
    entries = fields.each_slice(2).to_a
    assert(entries.all? { |status, _path| %w[A M].include?(status) },
           "#{task_id} candidate diff contains a deletion or non-regular type transition")
    paths = entries.map(&:last)
    assert(!paths.empty? && paths.uniq == paths,
           "#{task_id} candidate diff must be non-empty and duplicate-free")
    assert(paths.all? { |path| path_allowed?(path, allowlist) },
           "#{task_id} candidate diff escaped the frozen worker allowlist")
    paths.each do |path|
      tree_entry = git!(root, "ls-tree", "-z", candidate_commit, "--", path).first
      match = /\A(100644|100755) blob ([0-9a-f]{40})\t#{Regexp.escape(path)}\0\z/.match(tree_entry)
      assert(match, "#{task_id} candidate path is absent, symlinked, gitlinked or non-regular: #{path}")
      _out, _err, blob = git!(root, "cat-file", "-e", "#{candidate_commit}:#{path}", allow_failure: true)
      assert(blob.success?, "#{task_id} candidate path has no readable blob: #{path}")
      blob_size = git!(root, "cat-file", "-s", match[2]).first.strip.to_i
      base_blob, _base_err, base_status =
        git!(root, "rev-parse", "#{activation_parent}:#{path}", allow_failure: true)
      assert(blob_size.positive? && (!base_status.success? || base_blob.strip != match[2]),
             "#{task_id} candidate path is empty or contains only a mode change: #{path}")
    end
    product_java_roots = %w[
      backend-spring/src/main/java/
      backend-spring/src/test/java/
    ]
    java_tree_paths = paths.select { |path| product_java_roots.any? { |root_path| path.start_with?(root_path) } }
    assert(java_tree_paths.all? { |path| path.end_with?(".java") },
           "#{task_id} candidate placed a non-Java blob in a Java source tree")
    product_paths = paths.select do |path|
      path.start_with?("backend-spring/src/main/java/") && path.end_with?(".java")
    end
    product_test_paths = paths.select do |path|
      path.start_with?("backend-spring/src/test/java/") && path.end_with?(".java")
    end
    if require_delivery
      if task_id == F2_TASK_ID
        assert(product_paths.empty?, "F2 candidate modified Product source or tests")
      else
        assert(!product_paths.empty? && !product_test_paths.empty?,
               "P2 candidate lacks non-empty Java Product source or test delivery")
      end
    end
    paths
  end

  def validate_strategic_installation_parent!(root, identity)
    parent = exact_mapping(identity, %w[commit tree], "P3 strategic-installation parent")
    validate_commit_tree!(root, parent["commit"], parent["tree"], "P3 strategic-installation parent",
                          integrated: true)
    decision_bytes = git!(root, "show", "#{parent.fetch('commit')}:#{DECISION.fetch('path')}").first
    constitution_bytes = git!(root, "show", "#{parent.fetch('commit')}:#{CONSTITUTION.fetch('path')}").first
    assert(decision_bytes.bytesize == DECISION.fetch("byte_length") &&
           Digest::SHA256.hexdigest(decision_bytes) == DECISION.fetch("sha256") &&
           constitution_bytes.bytesize == CONSTITUTION.fetch("byte_length") &&
           Digest::SHA256.hexdigest(constitution_bytes) == CONSTITUTION.fetch("sha256"),
           "P3 strategic-installation parent does not contain the installed decision and Constitution")
    parent
  end

  def validate_decision!(root)
    decision_bytes = read_identity!(root, DECISION, "P3 evidence-first canonical decision")
    attachment_bytes = read_identity!(root, SOURCE_ATTACHMENT, "P3 evidence-first direct Founder attachment")
    normalized = attachment_bytes.sub(/\n*\z/, "") + "\n"
    assert(normalized.bytesize == NORMALIZED_BODY.fetch("byte_length") &&
           Digest::SHA256.hexdigest(normalized) == NORMALIZED_BODY.fetch("sha256"),
           "P3 evidence-first direct authorization normalization drift")
    constitution = read_identity!(root, CONSTITUTION, "P3 Strategic Constitution v3.5")
    assert(constitution.include?("## 9E. P3 v3.5 evidence-first final clean-room route authority") &&
           constitution.include?("`#{OBJECTIVE_ID}`") && constitution.include?("`#{STRICT_GATE_ID}`") &&
           STRICT_ITEMS.all? { |item| constitution.include?("`#{item}`") },
           "P3 Constitution v3.5 semantic anchor drift")

    decision = mapping(JSON.parse(decision_bytes), "P3 evidence-first decision")
    assert(decision["schema_version"] == DECISION_SCHEMA &&
           decision["record_type"] == "FOUNDER_P3_TRUSTED_READ_ONLY_INVOCATION_EVIDENCE_FIRST_FINAL_ROUTE_DECISION" &&
           decision["decision_id"] == DECISION_ID && decision["operation_type"] == OPERATION_TYPE &&
           decision["status"] == "ACCEPTED_DIRECT_FOUNDER_STRATEGIC_ROUTE_DECISION",
           "P3 evidence-first decision header drift")
    assert(decision["reserved_triggers"] == %w[
      MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
      MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
    ] && decision["canonical_start"] == CANONICAL_START &&
           decision["installed_constitution"] == CONSTITUTION,
           "P3 evidence-first decision authority identity drift")
    direct = mapping(decision["direct_founder_authorization"], "P3 direct Founder authorization")
    assert(direct["path"] == SOURCE_ATTACHMENT["path"] &&
           direct["byte_length"] == SOURCE_ATTACHMENT["byte_length"] &&
           direct["sha256"] == SOURCE_ATTACHMENT["sha256"] &&
           direct["normalized_byte_length"] == NORMALIZED_BODY["byte_length"] &&
           direct["normalized_sha256"] == NORMALIZED_BODY["sha256"] && direct["token_count"] == 1,
           "P3 direct Founder authorization binding drift")

    terminal = mapping(decision["terminal_basis"], "P3 TRIVS terminal projection")
    findings = terminal["findings"]
    assert(terminal["route_id"] == P3TrustedReadOnlyInvocationVerticalSliceRouteValidation::ROUTE_ID &&
           terminal["task_id"] == P3TrustedReadOnlyInvocationVerticalSliceRouteValidation::TASK_ID &&
           terminal["task_status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           terminal["route_status"] == "ROUTE_TERMINAL_NON_PASS" &&
           terminal["receipt"] == TERMINAL_RECEIPT &&
           terminal["frozen_findings_identity"] == FROZEN_FINDINGS &&
           terminal["finding_projection_fields"] == PERMITTED_FINDING_FIELDS &&
           findings.is_a?(Array) && findings.length == TERMINAL_FINDING_IDS.length &&
           findings.map { |finding| finding.keys }.
             all? { |keys| keys == PERMITTED_FINDING_FIELDS } &&
           findings.map { |finding| finding["finding_id"] } == TERMINAL_FINDING_IDS &&
           findings.all? { |finding| finding["severity"] == "P1" &&
             GATE_RELEVANCE.include?(finding["gate_relevance"]) &&
             finding["summary"].is_a?(String) && !finding["summary"].empty? },
           "P3 terminal projection exceeds or drifts from the authorized finding scope")

    strategic = mapping(decision["strategic_change"], "P3 evidence-first strategic change")
    assert(strategic["objective_id"] == OBJECTIVE_ID && strategic["workflow_id"] == WORKFLOW_ID &&
           strategic["claim_boundary"] == CLAIM_BOUNDARY &&
           strategic.dig("strict_exit_gate", "gate_id") == STRICT_GATE_ID &&
           strategic.dig("strict_exit_gate", "required_item_ids") == STRICT_ITEMS &&
           strategic.dig("strict_exit_gate", "same_frozen_product_candidate_required") == true &&
           strategic.dig("strict_exit_gate", "canonical_replay_required") == true &&
           strategic.fetch("progress_credit").values.all? { |value| value == 0 },
           "P3 objective, strict Exit Gate or zero-credit boundary drift")
    route = mapping(decision["route"], "P3 evidence-first decision route")
    stages = route["ordered_stages"]
    assert(route["route_id"] == ROUTE_ID && route["installation_state"] == "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" &&
           route["stage_order_enforced"] == true && route["separate_audit_task"] == false &&
           stages.is_a?(Array) && stages.length == 2 &&
           stages[0].slice("ordinal", "stage_id", "task_id", "kind", "branch", "worktree", "evidence_root", "budget", "worker_write_allowlist", "product_source_mutation_allowed") == {
             "ordinal" => 18, "stage_id" => F2_MILESTONE_ID, "task_id" => F2_TASK_ID,
             "kind" => "BENCHMARK_AND_ACCEPTANCE_FOUNDATION_NON_PRODUCT",
             "branch" => F2_RESOURCES["branch"], "worktree" => F2_RESOURCES["worktree"],
             "evidence_root" => F2_RESOURCES["evidence_root"], "budget" => F2_BUDGET,
             "worker_write_allowlist" => F2_WORKER_PATHS, "product_source_mutation_allowed" => false
           } &&
           stages[1].slice("ordinal", "stage_id", "task_id", "kind", "branch", "worktree", "evidence_root", "budget", "worker_write_allowlist", "optional_pre_first_write_allowlist_expansion", "implementation_attempt_for_milestone") == {
             "ordinal" => 19, "stage_id" => PRODUCT_MILESTONE_ID, "task_id" => P2_TASK_ID,
             "kind" => "PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL",
             "branch" => P2_RESOURCES["branch"], "worktree" => P2_RESOURCES["worktree"],
             "evidence_root" => P2_RESOURCES["evidence_root"], "budget" => P2_BUDGET,
             "worker_write_allowlist" => P2_WORKER_PATHS,
             "optional_pre_first_write_allowlist_expansion" => P2_OPTIONAL_PRE_FIRST_WRITE_PATHS,
             "implementation_attempt_for_milestone" => "2_OF_2_FINAL"
           }, "P3 evidence-first two-stage route drift")
    accounting = mapping(decision["cumulative_accounting"], "P3 evidence-first cumulative accounting")
    assert(accounting["basis"] == "NON_RESETTABLE_CUMULATIVE_P3_FOUNDER_ENVELOPE" &&
           accounting["consumed_before_route"] == BASE_CONSUMED && accounting["limits"] == LIMITS &&
           accounting["route_release"] == ROUTE_RELEASE && accounting["reset_or_refund_allowed"] == false &&
           accounting["governance_progress_credit"] == 0,
           "P3 evidence-first non-resettable accounting drift")
    clean = mapping(decision["clean_room"], "P3 evidence-first clean-room boundary")
    assert(clean["rejected_candidate_1_checkout_read_compare_copy_execute_decompile_restore_repair_or_reuse"] == false &&
           clean["rejected_branch_worktree_bundle_patch_changed_source_tests_helper_rootfs_machine_state_scripts_or_engineering_evidence_read"] == false &&
           clean["permitted_terminal_finding_fields"] == PERMITTED_FINDING_FIELDS &&
           clean["permitted_terminal_metadata"] == PERMITTED_TERMINAL_METADATA,
           "P3 evidence-first clean-room boundary drift")
    assert(decision.fetch("external_effects").values.all? { |value| value == false } &&
           decision.dig("local_docker_authority", "endpoint") ==
             "unix:///Users/lijunpeng/.docker/run/docker.sock" &&
           decision.dig("local_docker_authority", "mysql_content_id") ==
             "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209" &&
           decision.dig("local_docker_authority", "pinned_mysql_content_image_removal_allowed") == false,
           "P3 evidence-first Docker or external-effect boundary drift")
    lifecycle = mapping(decision["lifecycle"], "P3 evidence-first lifecycle")
    %w[candidate_3_allowed second_same_task_repair_allowed third_review_cycle_allowed
       second_foundation_allowed third_product_implementation_allowed separate_audit_allowed
       successor_replacement_normalization_closure_feasibility_remediation_allowed
       v2_v3_route_or_rerun_to_pass_allowed].each do |key|
      assert(lifecycle[key] == false, "P3 evidence-first anti-loop decision drift at #{key}")
    end
    assert(lifecycle["installation_state"] == "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" &&
           lifecycle["long_term_goal_status"] == "ACTIVE",
           "P3 evidence-first installation or Long-term Goal lifecycle drift")
    decision
  rescue JSON::ParserError => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "P3 evidence-first decision invalid JSON: #{e.message}"
  end

  def expected_truth_stages(profile)
    historical = {
      "ordinal" => 17, "stage_id" => PRODUCT_MILESTONE_ID,
      "task_id" => P3TrustedReadOnlyInvocationVerticalSliceRouteValidation::TASK_ID,
      "kind" => "PRODUCT_IMPLEMENTATION", "status" => "TERMINAL_TASK_GATE_NON_PASS",
      "budget" => P3TrustedReadOnlyInvocationVerticalSliceRouteValidation::TASK_BUDGET,
      "resources" => P3TrustedReadOnlyInvocationVerticalSliceRouteValidation::RESOURCES
    }
    f2 = {
      "ordinal" => 18, "stage_id" => F2_MILESTONE_ID, "task_id" => F2_TASK_ID,
      "kind" => "BENCHMARK_AND_ACCEPTANCE_FOUNDATION_NON_PRODUCT", "status" => profile.fetch("f2_status"),
      "budget" => F2_BUDGET, "resources" => F2_RESOURCES, "worker_write_allowlist" => F2_WORKER_PATHS,
      "product_source_mutation_allowed" => false
    }
    product = {
      "ordinal" => 19, "stage_id" => PRODUCT_MILESTONE_ID, "task_id" => P2_TASK_ID,
      "kind" => "PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL", "status" => profile.fetch("p2_status"),
      "budget" => P2_BUDGET, "resources" => P2_RESOURCES, "worker_write_allowlist" => P2_WORKER_PATHS,
      "optional_pre_first_write_allowlist_expansion" => P2_OPTIONAL_PRE_FIRST_WRITE_PATHS,
      "implementation_attempt_for_milestone" => "2_OF_2_FINAL"
    }
    [historical, f2, product]
  end

  def task_configuration(task_id)
    if task_id == F2_TASK_ID
      {
        "stage_id" => F2_MILESTONE_ID,
        "kind" => "BENCHMARK_AND_ACCEPTANCE_FOUNDATION_NON_PRODUCT",
        "resources" => F2_RESOURCES,
        "base_paths" => F2_WORKER_PATHS,
        "budget" => F2_BUDGET,
        "product_source_mutation_allowed" => false
      }
    else
      assert(task_id == P2_TASK_ID, "unknown P3 evidence-first Task")
      {
        "stage_id" => PRODUCT_MILESTONE_ID,
        "kind" => "PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL",
        "resources" => P2_RESOURCES,
        "base_paths" => P2_WORKER_PATHS,
        "budget" => P2_BUDGET,
        "product_source_mutation_allowed" => true
      }
    end
  end

  def active_external_effects
    {
      "docker" => true,
      "docker_scope" => "ACTIVE_TASK_SCOPED",
      "docker_endpoint" => "unix:///Users/lijunpeng/.docker/run/docker.sock",
      "docker_allowed_verbs" => DOCKER_ALLOWED_VERBS,
      "mysql_content_id" =>
        "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209",
      "task_created_disposable_mysql" => true,
      "task_local_mysql_loopback_only" => true,
      "sterile_config_closed_environment_required" => true,
      "os_network_restriction_required" => true,
      "docker_registry_pull_push_login_or_build" => false,
      "docker_host_source_bind_mount" => false,
      "docker_privileged_mode" => false,
      "docker_existing_object_mutation" => false,
      "docker_unrelated_cleanup" => false,
      "pinned_mysql_content_image_removal" => false,
      "network" => false, "dns" => false, "http_https" => false,
      "provider" => false, "secret" => false, "credential" => false,
      "remote" => false, "production" => false, "public" => false,
      "existing_database_mutation" => false,
      "write_outside_exact_authorized_roots" => false,
      "irreversible_asset_deletion" => false
    }
  end

  def route_docker_scope(lifecycle)
    return "ACTIVE_TASK_SCOPED" if %w[FOUNDATION_TASK_ACTIVE PRODUCT_TASK_ACTIVE].include?(lifecycle)
    return "LOCKED_ROUTE_TERMINAL" if %w[
      FOUNDATION_ROUTE_TERMINAL_NON_PASS PRODUCT_ROUTE_TERMINAL_NON_PASS
    ].include?(lifecycle)
    return "LOCKED_PHASE_GATE" if lifecycle == "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE"

    "LOCKED_UNTIL_TASK_ACTIVATION"
  end

  def inactive_external_effects(lifecycle)
    scope = case lifecycle
            when "FOUNDATION_ELIGIBLE_NOT_ACTIVATED"
              "LOCKED_UNTIL_FOUNDATION_TASK_ACTIVATION"
            when "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE"
              "LOCKED_UNTIL_PRODUCT_TASK_ACTIVATION"
            when "FOUNDATION_ROUTE_TERMINAL_NON_PASS", "PRODUCT_ROUTE_TERMINAL_NON_PASS"
              "LOCKED_ROUTE_TERMINAL"
            when "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE"
              "LOCKED_PHASE_GATE"
            else
              "LOCKED_NO_ACTIVE_TASK"
            end
    {
      "docker" => false,
      "docker_scope" => scope,
      "docker_endpoint" => "unix:///Users/lijunpeng/.docker/run/docker.sock",
      "docker_registry_pull_push_login_or_build" => false,
      "task_created_disposable_mysql" => false,
      "task_local_mysql_loopback_only" => false,
      "network" => false, "dns" => false, "http_https" => false,
      "provider" => false, "secret" => false, "credential" => false,
      "remote" => false, "production" => false, "public" => false,
      "existing_database_mutation" => false,
      "write_outside_exact_authorized_roots" => false,
      "irreversible_asset_deletion" => false
    }
  end

  def task_lifecycle_boundary(budget)
    {
      "candidate_generations_max" => budget.fetch("candidate_generations"),
      "same_task_repairs_max" => budget.fetch("same_task_repairs"),
      "review_cycles_max" => budget.fetch("review_cycles"),
      "candidate_3_allowed" => false,
      "second_same_task_repair_allowed" => false,
      "third_review_cycle_allowed" => false,
      "automatic_successor_allowed" => false,
      "rerun_to_pass_allowed" => false
    }
  end

  def task_accepted_dependencies(truth, task_id)
    return ACCEPTED_DEPENDENCIES if task_id == F2_TASK_ID

    foundation = mapping(
      truth.dig("current_phase_route", "foundation_result"),
      "P3 Product accepted F2 Foundation dependency"
    )
    ACCEPTED_DEPENDENCIES.merge(
      "accepted_trivs_f2_foundation" => {
        "status" => foundation.fetch("status"), "task_id" => foundation.fetch("task_id"),
        "candidate" => {
          "commit" => foundation.fetch("candidate_commit"),
          "tree" => foundation.fetch("candidate_tree")
        },
        "candidate_manifest" => foundation.fetch("candidate_manifest"),
        "raw_evidence_manifest" => foundation.fetch("raw_evidence_manifest"),
        "task_gate_receipt" => foundation.fetch("task_gate_receipt"),
        "canonical_replay_bundle" => foundation.fetch("canonical_replay_bundle"),
        "canonical_replay_receipt" => foundation.fetch("canonical_replay_receipt")
      }
    )
  end

  def task_roles(task_id)
    worker = task_id == F2_TASK_ID ?
      "TRIVS_CANDIDATE_BOUND_ACCEPTANCE_HARNESS_IMPLEMENTER" :
      "TRIVS_FINAL_CLEAN_ROOM_PRODUCT_IMPLEMENTER"
    {
      "owner" => "MASTER_CEO_AGENT",
      "worker" => worker,
      "quality_owner" => "FRESH_QUALITY_EVALUATION_AGENT",
      "independent_reviewers" => %w[
        FRESH_CTO_AGENT FRESH_SECURITY_AGENT FRESH_QUALITY_EVALUATION_AGENT
      ]
    }
  end

  def inactive_task_projection(profile)
    selected = profile.fetch("selected")
    return {
      "planned_task_branch" => nil, "planned_task_worktree" => nil,
      "planned_execution_evidence_root" => nil, "allowlisted_paths" => [],
      "next_stage_budget" => {},
      "roles" => {
        "owner" => "MASTER_CEO_AGENT", "worker" => "NONE", "quality_owner" => "NONE",
        "independent_reviewers" => []
      },
      "task_resource_state" => "LOCKED_NO_TASK"
    } unless [F2_TASK_ID, P2_TASK_ID].include?(selected)

    config = task_configuration(selected)
    resources = config.fetch("resources")
    {
      "planned_task_branch" => resources.fetch("branch"),
      "planned_task_worktree" => resources.fetch("worktree"),
      "planned_execution_evidence_root" => resources.fetch("evidence_root"),
      "allowlisted_paths" => selected == F2_TASK_ID ? F2_WORKER_PATHS : P2_WORKER_PATHS,
      "next_stage_budget" => config.fetch("budget"), "roles" => task_roles(selected),
      "task_resource_state" => "PLANNED_NOT_CREATED"
    }
  end

  def validate_predecessor_terminal_projection!(active, lifecycle, truth)
    if %w[FOUNDATION_ROUTE_TERMINAL_NON_PASS PRODUCT_ROUTE_TERMINAL_NON_PASS].include?(lifecycle)
      terminal_result = lifecycle == "FOUNDATION_ROUTE_TERMINAL_NON_PASS" ?
        truth.dig("current_phase_route", "foundation_terminal_result") :
        truth.dig("current_phase_route", "product_terminal_result")
      expected_task = lifecycle == "FOUNDATION_ROUTE_TERMINAL_NON_PASS" ? F2_TASK_ID : P2_TASK_ID
      assert(active.dig("historical_terminal_accounting", "latest_terminal_task_id") == expected_task &&
             active.dig("historical_terminal_accounting", "latest_terminal_receipt_sha256") ==
               terminal_result.dig("terminal_receipt", "sha256") &&
             active.dig("terminal_task_record", "task_id") == expected_task &&
             active.dig("terminal_task_record", "candidate_commit") == terminal_result["candidate_commit"] &&
             active.dig("terminal_task_record", "candidate_tree") == terminal_result["candidate_tree"] &&
             active.dig("terminal_task_record", "candidate_integrated") == false &&
             active.dig("terminal_task_record", "terminal_receipt") == terminal_result["terminal_receipt"],
             "P3 evidence-first latest terminal projection drift")
      return
    end

    assert(active["historical_terminal_accounting"] == {
      "consumed_engineering_tasks" => 17, "consumed_engineering_hours" => 496,
      "consumed_calendar_days" => 116,
      "latest_terminal_task_id" =>
        "AIOS-P3-TRIVS-P1_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE",
      "latest_terminal_receipt_sha256" => TERMINAL_RECEIPT.fetch("sha256")
    } && active["terminal_task_record"] == {
      "task_id" => "AIOS-P3-TRIVS-P1_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE",
      "candidate_commit" => "597ee9dcf714bcd612c893b86753fa2881a06963",
      "candidate_tree" => "42ec54bddec5abb82de8dde67fff56ffc4d079da",
      "candidate_integrated" => false, "candidate_2_created" => false,
      "same_task_repair_consumed" => false, "review_cycle_2_started" => false,
      "terminal_receipt" => TERMINAL_RECEIPT
    }, "P3 evidence-first predecessor terminal projection drift")
  end

  def validate_optional_expansion!(root, task_id, value, evidence_root)
    return [F2_WORKER_PATHS, nil] if task_id == F2_TASK_ID && value.nil?

    assert(task_id == P2_TASK_ID, "F2 may not define a Product allowlist expansion")
    expansion = exact_mapping(value, %w[
      applied allowed_paths selected_paths pre_first_product_write
      product_source_manifest_created mechanical_need_receipt
    ], "P3 Product optional allowlist expansion")
    assert(expansion["allowed_paths"] == P2_OPTIONAL_PRE_FIRST_WRITE_PATHS &&
           [true, false].include?(expansion["applied"]) &&
           expansion["selected_paths"].is_a?(Array) &&
           expansion["selected_paths"].uniq == expansion["selected_paths"] &&
           (expansion["selected_paths"] - P2_OPTIONAL_PRE_FIRST_WRITE_PATHS).empty? &&
           expansion["pre_first_product_write"] == true &&
           expansion["product_source_manifest_created"] == false,
           "P3 Product optional allowlist expansion boundary drift")
    if expansion["applied"]
      assert(!expansion["selected_paths"].empty?, "applied Product allowlist expansion is empty")
      receipt_bytes = read_evidence_identity!(
        root, expansion["mechanical_need_receipt"],
        "authority/P3_TRIVS_P2_OPTIONAL_ALLOWLIST_EXPANSION_PREFLIGHT_V1.json",
        evidence_root, "P3 Product optional allowlist expansion preflight"
      )
      receipt = parse_json!(receipt_bytes, "P3 Product optional allowlist expansion preflight")
      receipt = exact_mapping(receipt, %w[
        schema_version record_type task_id route_id verdict allowed_paths selected_paths
        pre_first_product_write product_source_manifest_created product_write_observed
      ], "P3 Product optional allowlist expansion preflight")
      assert(receipt["schema_version"] == OPTIONAL_ALLOWLIST_PREFLIGHT_SCHEMA &&
             receipt["record_type"] == "P3_TRIVS_P2_OPTIONAL_ALLOWLIST_EXPANSION_PREFLIGHT" &&
             receipt["task_id"] == P2_TASK_ID && receipt["route_id"] == ROUTE_ID &&
             receipt["verdict"] == "PASS_MECHANICALLY_REQUIRED_BEFORE_FIRST_PRODUCT_WRITE" &&
             receipt["allowed_paths"] == P2_OPTIONAL_PRE_FIRST_WRITE_PATHS &&
             receipt["selected_paths"] == expansion["selected_paths"] &&
             receipt["pre_first_product_write"] == true &&
             receipt["product_source_manifest_created"] == false &&
             receipt["product_write_observed"] == false,
             "P3 Product optional allowlist expansion preflight drift")
    else
      assert(expansion["selected_paths"] == [] && expansion["mechanical_need_receipt"].nil?,
             "unused Product allowlist expansion retained authority")
    end
    [P2_WORKER_PATHS + expansion["selected_paths"], expansion]
  end

  def validate_active_task_resources!(root, resources, activation_parent, label)
    branch = resources.fetch("branch")
    worktree = Pathname.new(resources.fetch("worktree"))
    evidence_root = Pathname.new(resources.fetch("evidence_root"))
    [worktree, evidence_root].each do |path|
      assert(path.absolute? && path.cleanpath.to_s == path.to_s,
             "#{label} resource path is not canonical and absolute")
      stat = path.lstat
      assert(stat.directory? && !stat.symlink?,
             "#{label} resource is not a non-symlink directory: #{path}")
      assert(path.realpath.to_s == path.to_s,
             "#{label} resource traverses a symlinked path component: #{path}")
    end

    top = git!(worktree, "rev-parse", "--show-toplevel").first.strip
    head = git!(worktree, "rev-parse", "HEAD").first.strip
    branch_out, _branch_err, branch_status =
      git!(worktree, "symbolic-ref", "--quiet", "--short", "HEAD", allow_failure: true)
    canonical_branch_head = git!(root, "rev-parse", "refs/heads/#{branch}").first.strip
    assert(top == worktree.to_s && branch_status.success? && branch_out.strip == branch &&
           head == canonical_branch_head,
           "#{label} worktree registration, branch or HEAD identity drift")
    worktree_records = git!(root, "worktree", "list", "--porcelain").first.
      split(/\n\n+/).reject(&:empty?).map do |block|
        block.lines.to_h do |line|
          key, value = line.chomp.split(" ", 2)
          [key, value]
        end
      end
    expected_worktree_paths = [root.realpath.to_s, worktree.to_s].sort
    assert(worktree_records.map { |record| record.fetch("worktree") }.sort == expected_worktree_paths,
           "#{label} canonical Git worktree registration count or path drift")
    registered = worktree_records.find { |record| record["worktree"] == worktree.to_s }
    assert(registered && registered["HEAD"] == head &&
           registered["branch"] == "refs/heads/#{branch}",
           "#{label} is not the exact registered Git worktree")
    _out, _err, descendant = git!(
      worktree, "merge-base", "--is-ancestor", activation_parent.fetch("commit"), head,
      allow_failure: true
    )
    assert(descendant.success?,
           "#{label} worktree HEAD is not descended from the exact activation parent")
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} resource unavailable: #{e.class}"
  end

  def validate_active_work!(root, truth, profile)
    active = exact_mapping(truth["active_work"], ACTIVE_WORK_KEYS,
                           "P3 evidence-first active_work")
    active_task = profile.fetch("active_task")
    unless active_task
      lifecycle = truth.dig("current_phase_route", "lifecycle_stage")
      planned = inactive_task_projection(profile)
      assert(active["current_task"] == "NONE" && active["selected_task"] == profile.fetch("selected") &&
             active["current_task_contract"].nil? && active["current_task_contract_sha256"].nil? &&
             active["current_execution_authorization"].nil? &&
             active["current_execution_authorization_sha256"].nil? &&
             active["authority_record"].nil? && active["execution_nonce"].nil? &&
             active["authorization_id"].nil? && active["activation_parent_commit"].nil? &&
             active["activation_parent_tree"].nil? && active["strategic_installation_parent"].nil? &&
             active["task_branch"].nil? && active["task_worktree"].nil? &&
             active["execution_evidence_root"].nil? && active["current_task_budget"] == {} &&
             active["authority_scope_conformance"] == "NOT_YET_ISSUED" &&
             active["execution_nonce_status"] == "NOT_YET_ISSUED" &&
             active["task_resource_state"] == planned.fetch("task_resource_state") &&
             active["planned_task_branch"] == planned.fetch("planned_task_branch") &&
             active["planned_task_worktree"] == planned.fetch("planned_task_worktree") &&
             active["planned_execution_evidence_root"] ==
               planned.fetch("planned_execution_evidence_root") &&
             active["dependency_custody_root"].nil? &&
             active["allowlisted_paths"] == planned.fetch("allowlisted_paths") &&
             active["next_stage_budget"] == planned.fetch("next_stage_budget") &&
             active["roles"] == planned.fetch("roles") && active["offsite_target"].nil? &&
             active["founder_reserved_authorization"] == DECISION.fetch("path") &&
             active["founder_reserved_authorization_sha256"] == DECISION.fetch("sha256") &&
             active["founder_decision_required_scope"] ==
               (profile.fetch("founder_required") ? profile.fetch("founder_trigger") : nil) &&
             active["escalation_reason"] ==
               (profile.fetch("founder_required") ? profile.fetch("action") : nil) &&
             active["user_action_required"] == profile.fetch("founder_required") &&
             active["phase_route_decision_required"] == profile.fetch("founder_required") &&
             active["phase_route_user_action_required"] == profile.fetch("founder_required"),
             "P3 evidence-first inactive Task retained executable authority")
      assert(active["external_effects"] == inactive_external_effects(lifecycle),
             "P3 evidence-first inactive Task external-effect projection drift")
      assert(truth.dig("goal", "current_task_authority") == "NONE",
             "P3 evidence-first inactive lifecycle retained Goal Task authority")
      assert(active["current_task_status"] == profile.fetch("task_status") &&
             active["founder_decision_required"] == profile.fetch("founder_required") &&
             active["next_eligible_action"] == profile.fetch("action"),
             "P3 evidence-first inactive-work lifecycle drift")
      validate_predecessor_terminal_projection!(active, lifecycle, truth)
      return
    end

    config = task_configuration(active_task)
    resources = config.fetch("resources")
    budget = config.fetch("budget")
    contract_identity = identity_mapping(active["current_task_contract"], "P3 active Contract")
    assert(contract_identity["path"] == TASK_CONTRACT_PATHS.fetch(active_task),
           "P3 active Contract path drift")
    contract_bytes = read_identity!(root, contract_identity, "P3 active Contract")
    contract = YAML.safe_load(contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    contract = exact_mapping(contract, TASK_CONTRACT_KEYS, "P3 active Contract")
    optional_value = contract["optional_pre_first_write_allowlist_expansion"]
    actual_paths, normalized_expansion = validate_optional_expansion!(
      root, active_task, optional_value, resources.fetch("evidence_root")
    )
    assert(active["current_task"] == active_task && active["selected_task"] == active_task &&
           active["current_task_status"] == "ACTIVE" && active["task_branch"] == resources["branch"] &&
           active["task_worktree"] == resources["worktree"] &&
           active["execution_evidence_root"] == resources["evidence_root"] &&
           active["allowlisted_paths"] == actual_paths && active["current_task_budget"] == budget &&
           active["current_task_contract_sha256"] == contract_identity["sha256"] &&
           active["authority_scope_conformance"] == "PASS_EXACT" &&
           active["execution_nonce"].is_a?(String) &&
           active["execution_nonce"].match?(/\A[0-9a-f]{8}-[0-9a-f-]{27,}\z/) &&
           active["execution_nonce_status"] == "ACTIVE" &&
           active["authorization_id"].is_a?(String) &&
           active["authorization_id"].match?(/\A[0-9a-f]{8}-[0-9a-f-]{27,}\z/) &&
           active["task_resource_state"] == "ACTIVE_CREATED" &&
           active["external_effects"] == active_external_effects &&
           active["founder_decision_required"] == false &&
           active["next_eligible_action"] == profile.fetch("action") &&
           truth.dig("goal", "current_task_authority") == active_task,
           "P3 evidence-first active Task identity, authority, effects or budget drift")
    assert(active["planned_task_branch"] == resources.fetch("branch") &&
           active["planned_task_worktree"] == resources.fetch("worktree") &&
           active["planned_execution_evidence_root"] == resources.fetch("evidence_root") &&
           active["dependency_custody_root"] ==
             File.join(resources.fetch("evidence_root"), "dependency-custody") &&
           active["next_stage_budget"] == {} && active["roles"] == task_roles(active_task) &&
           active["offsite_target"].nil? &&
           active["founder_reserved_authorization"] == DECISION.fetch("path") &&
           active["founder_reserved_authorization_sha256"] == DECISION.fetch("sha256") &&
           active["founder_decision_required_scope"].nil? && active["escalation_reason"].nil? &&
           active["user_action_required"] == false &&
           active["phase_route_decision_required"] == false &&
           active["phase_route_user_action_required"] == false,
           "P3 evidence-first active Task planned scope or handoff projection drift")
    validate_predecessor_terminal_projection!(
      active, truth.dig("current_phase_route", "lifecycle_stage"), truth
    )

    activation_parent = {
      "commit" => active["activation_parent_commit"], "tree" => active["activation_parent_tree"]
    }
    validate_commit_tree!(root, activation_parent["commit"], activation_parent["tree"],
                          "P3 active Task activation parent", integrated: true)
    strategic_parent = validate_strategic_installation_parent!(root, active["strategic_installation_parent"])
    parent_truth_bytes = git!(
      root, "show", "#{activation_parent.fetch('commit')}:docs/aios/truth/project_state.yaml"
    ).first
    parent_truth = YAML.safe_load(parent_truth_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    expected_parent_lifecycle = active_task == F2_TASK_ID ?
      "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" : "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE"
    assert(parent_truth.dig("current_phase_route", "schema_version") == ROUTE_SCHEMA &&
           parent_truth.dig("current_phase_route", "route_id") == ROUTE_ID &&
           parent_truth.dig("current_phase_route", "lifecycle_stage") == expected_parent_lifecycle,
           "P3 active Task activation parent was not the exact preceding eligible lifecycle")

    expected_acceptance = active_task == F2_TASK_ID ?
      truth.dig("current_phase_route", "foundation_acceptance") :
      truth.dig("current_phase_route", "product_acceptance")
    expected_dependencies = task_accepted_dependencies(truth, active_task)
    founder_decision = DECISION.merge("decision_id" => DECISION_ID)
    assert(contract["schema_version"] == TASK_CONTRACT_SCHEMA &&
           contract["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_PHASE_DELEGATED_TASK_CONTRACT" &&
           contract["task_id"] == active_task && contract["route_id"] == ROUTE_ID &&
           contract["phase"] == "P3" && contract["stage_id"] == config["stage_id"] &&
           contract["task_kind"] == config["kind"] && contract["status"] == "ACTIVE" &&
           contract["activation_parent"] == activation_parent &&
           contract["strategic_installation_parent"] == strategic_parent &&
           contract["branch"] == resources["branch"] && contract["worktree"] == resources["worktree"] &&
           contract["evidence_root"] == resources["evidence_root"] &&
           contract["write_allowlist"] == actual_paths &&
           contract["optional_pre_first_write_allowlist_expansion"] == normalized_expansion &&
           contract["product_source_mutation_allowed"] == config["product_source_mutation_allowed"] &&
           contract["budget"] == budget && contract["execution_nonce"] == active["execution_nonce"] &&
           contract["authorization_id"] == active["authorization_id"] &&
           contract["founder_route_decision"] == founder_decision &&
           contract["accepted_dependencies"] == expected_dependencies &&
           contract["acceptance"] == expected_acceptance &&
           contract["external_effects"] == active_external_effects &&
           contract["clean_room"] == truth.dig("current_phase_route", "clean_room") &&
           contract["lifecycle"] == task_lifecycle_boundary(budget),
           "P3 active Contract semantic or authority drift")

    authority_identity = identity_mapping(active["authority_record"], "P3 active authority")
    assert(authority_identity["path"] == TASK_AUTHORITY_PATHS.fetch(active_task) &&
           active["current_execution_authorization"] == authority_identity["path"] &&
           active["current_execution_authorization_sha256"] == authority_identity["sha256"],
           "P3 active authority identity projection drift")
    authority_bytes = read_evidence_identity!(
      root, authority_identity, "authority/#{File.basename(TASK_AUTHORITY_PATHS.fetch(active_task))}",
      resources.fetch("evidence_root"), "P3 active authority"
    )
    authority = exact_mapping(
      parse_json!(authority_bytes, "P3 active authority"), TASK_AUTHORITY_KEYS,
      "P3 active authority"
    )
    assert(authority["schema_version"] == TASK_AUTHORITY_SCHEMA &&
           authority["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_PHASE_DELEGATED_TASK_AUTHORITY" &&
           authority["status"] == "ACTIVE" && authority["issued_by"] == "MASTER_CEO_AGENT" &&
           authority["task_id"] == active_task && authority["route_id"] == ROUTE_ID &&
           authority["phase"] == "P3" && authority["stage_id"] == config["stage_id"] &&
           authority["task_kind"] == config["kind"] &&
           authority["activation_parent"] == activation_parent &&
           authority["strategic_installation_parent"] == strategic_parent &&
           authority["contract"] == contract_identity &&
           authority["authorization_id"] == active["authorization_id"] &&
           authority["execution_nonce"] == active["execution_nonce"] &&
           authority["resources"] == resources && authority["budget"] == budget &&
           authority["scope"] == {
             "worker_allowed_paths" => actual_paths,
             "optional_pre_first_write_allowlist_expansion" => normalized_expansion,
             "product_source_mutation_allowed" => config["product_source_mutation_allowed"]
           } && authority["founder_route_decision"] == founder_decision &&
           authority["accepted_dependencies"] == expected_dependencies &&
           authority["external_effects"] == active_external_effects &&
           authority["clean_room"] == truth.dig("current_phase_route", "clean_room") &&
           authority["lifecycle"] == task_lifecycle_boundary(budget),
           "P3 active Task authority semantic drift")
    validate_active_task_resources!(root, resources, activation_parent, "P3 active Task")
    worktree_contract_bytes = git!(
      Pathname.new(resources.fetch("worktree")), "show", "HEAD:#{TASK_CONTRACT_PATHS.fetch(active_task)}"
    ).first
    assert(worktree_contract_bytes == contract_bytes,
           "P3 active Task worktree does not contain the exact canonical Contract bytes")
  rescue Psych::Exception => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "P3 active Contract invalid YAML: #{e.message}"
  end

  def validate_completed_task_identity!(root, truth, task_id, result, label)
    config = task_configuration(task_id)
    resources = config.fetch("resources")
    budget = config.fetch("budget")
    contract_identity = identity_mapping(result["task_contract"], "#{label} Contract")
    assert(contract_identity["path"] == TASK_CONTRACT_PATHS.fetch(task_id),
           "#{label} Contract path drift")
    contract = YAML.safe_load(
      read_identity!(root, contract_identity, "#{label} Contract"),
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    contract = exact_mapping(contract, TASK_CONTRACT_KEYS, "#{label} Contract")
    actual_paths, normalized_expansion = validate_optional_expansion!(
      root, task_id, contract["optional_pre_first_write_allowlist_expansion"],
      resources.fetch("evidence_root")
    )
    activation_parent = exact_mapping(
      contract["activation_parent"], %w[commit tree], "#{label} activation parent"
    )
    strategic_parent = validate_strategic_installation_parent!(
      root, contract["strategic_installation_parent"]
    )
    validate_commit_tree!(root, activation_parent["commit"], activation_parent["tree"],
                          "#{label} activation parent", integrated: true)
    expected_acceptance = task_id == F2_TASK_ID ?
      truth.dig("current_phase_route", "foundation_acceptance") :
      truth.dig("current_phase_route", "product_acceptance")
    expected_dependencies = task_accepted_dependencies(truth, task_id)
    founder_decision = DECISION.merge("decision_id" => DECISION_ID)
    authority_identity = identity_mapping(result["task_authority"], "#{label} authority")
    authority = exact_mapping(parse_json!(
      read_evidence_identity!(
        root, authority_identity,
        "authority/#{File.basename(TASK_AUTHORITY_PATHS.fetch(task_id))}",
        config.dig("resources", "evidence_root"), "#{label} authority"
      ), "#{label} authority"
    ), TASK_AUTHORITY_KEYS, "#{label} authority")
    assert(authority_identity["path"] == TASK_AUTHORITY_PATHS.fetch(task_id) &&
           contract["schema_version"] == TASK_CONTRACT_SCHEMA &&
           contract["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_PHASE_DELEGATED_TASK_CONTRACT" &&
           contract["task_id"] == task_id && contract["route_id"] == ROUTE_ID &&
           contract["phase"] == "P3" && contract["stage_id"] == config["stage_id"] &&
           contract["task_kind"] == config["kind"] && contract["status"] == "ACTIVE" &&
           contract["activation_parent"] == activation_parent &&
           contract["strategic_installation_parent"] == strategic_parent &&
           contract["branch"] == resources["branch"] && contract["worktree"] == resources["worktree"] &&
           contract["evidence_root"] == resources["evidence_root"] &&
           contract["write_allowlist"] == actual_paths &&
           contract["optional_pre_first_write_allowlist_expansion"] == normalized_expansion &&
           contract["product_source_mutation_allowed"] == config["product_source_mutation_allowed"] &&
           contract["budget"] == budget &&
           contract["execution_nonce"].is_a?(String) &&
           contract["execution_nonce"].match?(/\A[0-9a-f]{8}-[0-9a-f-]{27,}\z/) &&
           contract["authorization_id"].is_a?(String) &&
           contract["authorization_id"].match?(/\A[0-9a-f]{8}-[0-9a-f-]{27,}\z/) &&
           contract["founder_route_decision"] == founder_decision &&
           contract["accepted_dependencies"] == expected_dependencies &&
           contract["acceptance"] == expected_acceptance &&
           contract["external_effects"] == active_external_effects &&
           contract["clean_room"] == truth.dig("current_phase_route", "clean_room") &&
           contract["lifecycle"] == task_lifecycle_boundary(budget) &&
           authority["schema_version"] == TASK_AUTHORITY_SCHEMA &&
           authority["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_PHASE_DELEGATED_TASK_AUTHORITY" &&
           authority["status"] == "ACTIVE" && authority["issued_by"] == "MASTER_CEO_AGENT" &&
           authority["task_id"] == task_id && authority["route_id"] == ROUTE_ID &&
           authority["phase"] == "P3" && authority["stage_id"] == config["stage_id"] &&
           authority["task_kind"] == config["kind"] && authority["contract"] == contract_identity &&
           authority["activation_parent"] == activation_parent &&
           authority["strategic_installation_parent"] == strategic_parent &&
           authority["execution_nonce"] == contract["execution_nonce"] &&
           authority["authorization_id"] == contract["authorization_id"] &&
           authority["resources"] == resources && authority["budget"] == budget &&
           authority["scope"] == {
             "worker_allowed_paths" => actual_paths,
             "optional_pre_first_write_allowlist_expansion" => normalized_expansion,
             "product_source_mutation_allowed" => config["product_source_mutation_allowed"]
           } && authority["founder_route_decision"] == founder_decision &&
           authority["accepted_dependencies"] == expected_dependencies &&
           authority["external_effects"] == active_external_effects &&
           authority["clean_room"] == truth.dig("current_phase_route", "clean_room") &&
           authority["lifecycle"] == task_lifecycle_boundary(budget),
           "#{label} Contract or authority identity drift")
    [contract_identity, authority_identity, contract, authority]
  rescue Psych::Exception => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} Contract invalid YAML: #{e.message}"
  end

  def result_artifact!(root, task_id, key, identity, label)
    config = task_configuration(task_id)
    expected_path = RESULT_PATHS.fetch(task_id)[key]
    expected_path ||= key if key.start_with?("strict/")
    assert(expected_path, "#{label} has no frozen Evidence path")
    bytes = read_evidence_identity!(
      root, identity, expected_path,
      config.dig("resources", "evidence_root"), label
    )
    [identity_mapping(identity, label), parse_json!(bytes, label)]
  end

  def secure_evidence_read!(identity, evidence_root, relative_path, label)
    identity = identity_mapping(identity, label)
    evidence = Pathname.new(evidence_root)
    assert(evidence.absolute? && evidence.cleanpath.to_s == evidence.to_s,
           "#{label} Evidence root is not canonical and absolute")
    evidence_stat = evidence.lstat
    assert(evidence_stat.directory? && !evidence_stat.symlink? && evidence.realpath.to_s == evidence.to_s,
           "#{label} Evidence root is absent, symlinked or redirected")
    expected_path = evidence.join(relative_path).cleanpath
    assert(identity["path"] == expected_path.to_s,
           "#{label} path drift")
    path = Pathname.new(identity.fetch("path"))
    assert(path.parent.realpath.to_s == path.parent.cleanpath.to_s,
           "#{label} parent path traverses a symlink")
    before = path.lstat
    assert(before.file? && !before.symlink? && before.nlink == 1 &&
           (before.mode & 0o777) == 0o444,
           "#{label} must be a create-once 0444 regular single-link file")
    bytes = nil
    File.open(path.to_s, File::RDONLY | File::NOFOLLOW) do |io|
      opened = io.stat
      assert(opened.dev == before.dev && opened.ino == before.ino && opened.nlink == 1,
             "#{label} changed while opening")
      bytes = io.read
      after_read = io.stat
      assert(after_read.dev == opened.dev && after_read.ino == opened.ino &&
             after_read.size == opened.size && after_read.mtime == opened.mtime,
             "#{label} changed while reading")
    end
    after = path.lstat
    assert(after.dev == before.dev && after.ino == before.ino && after.size == before.size &&
           after.mtime == before.mtime && after.nlink == 1 &&
           bytes.bytesize == identity.fetch("byte_length") &&
           Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"),
           "#{label} identity or filesystem state drift")
    [identity, bytes]
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} unavailable: #{e.class}"
  end

  def validate_raw_stream!(identity, evidence_root, prefix, label)
    identity = identity_mapping(identity, label)
    evidence = Pathname.new(evidence_root)
    path = Pathname.new(identity.fetch("path"))
    begin
      relative = path.relative_path_from(evidence).to_s
    rescue ArgumentError
      assert(false, "#{label} escaped the Task Evidence root")
    end
    assert(relative.start_with?("#{prefix}/") &&
           File.basename(relative) == "#{identity.fetch('sha256')}.bin",
           "#{label} path is not content-addressed inside #{prefix}")
    secure_evidence_read!(identity, evidence_root, relative, label)
  end

  def validate_closed_rootfs_tar!(bytes, expected_files, label)
    normalized_expected = expected_files.to_h do |path, value|
      spec = value.is_a?(Hash) ? exact_mapping(value, %w[bytes mode], "#{label} #{path}") :
        {"bytes" => value, "mode" => 0o555}
      [path, spec]
    end
    assert(normalized_expected.is_a?(Hash) && !normalized_expected.empty? &&
           normalized_expected.keys.all? { |path|
             relative = Pathname.new(path)
             !relative.absolute? && relative.cleanpath.to_s == path &&
               !path.start_with?("../") && !path.include?("//")
           } && normalized_expected.values.all? { |spec|
             spec["bytes"].is_a?(String) && [0o444, 0o555].include?(spec["mode"])
           },
           "#{label} expected file inventory is invalid")
    observed = {}
    Gem::Package::TarReader.new(StringIO.new(bytes)) do |tar|
      tar.each do |entry|
        path = entry.full_name.delete_prefix("./")
        relative = Pathname.new(path)
        assert(entry.file? && !relative.absolute? && relative.cleanpath.to_s == path &&
               !path.start_with?("../") && !path.include?("//") && !observed.key?(path) &&
               entry.header.mode == normalized_expected.fetch(path, {}).fetch("mode", nil),
               "#{label} contains a non-regular, duplicate, unsafe or wrong-mode leaf")
        content = entry.read
        assert(content.bytesize == entry.header.size,
               "#{label} leaf size differs from its tar header")
        observed[path] = content
      end
    end
    assert(observed.keys.sort == normalized_expected.keys.sort &&
           observed.all? { |path, content| content == normalized_expected.fetch(path).fetch("bytes") },
           "#{label} is not the exact closed rootfs leaf inventory")
    true
  rescue Gem::Package::TarInvalidError, EOFError, IOError => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "#{label} invalid tar: #{e.class}"
  end

  def canonical_json(value)
    case value
    when Hash
      "{" + value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(",") + "}"
    when Array
      "[" + value.map { |item| canonical_json(item) }.join(",") + "]"
    else
      JSON.generate(value)
    end
  end

  def validate_process_ledger_stream!(root, task_id, stream_identities, evidence_root, candidate)
    label = "P3 #{task_id} raw process ledger"
    ledger_identity, ledger_bytes = validate_raw_stream!(
      stream_identities.first, evidence_root, "raw/run/streams", "#{label} document"
    )
    ledger = parse_json!(ledger_bytes, label)
    ledger = exact_mapping(ledger, %w[
      schema_version record_type task_id route_id candidate records final_process_group_survivors
    ], label)
    assert(ledger["schema_version"] == "p3-trivs-evidence-first-process-ledger/v1" &&
           ledger["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_PROCESS_LEDGER" &&
           ledger["task_id"] == task_id && ledger["route_id"] == ROUTE_ID &&
           ledger["candidate"] == candidate && ledger["records"].is_a?(Array) &&
           !ledger["records"].empty? && ledger["final_process_group_survivors"] == [],
           "#{label} header drift")
    stream_lookup = stream_identities.to_h { |identity| [identity.fetch("path"), identity] }
    used_stream_paths = [ledger_identity.fetch("path")]
    previous_hash = "0" * 64
    records_by_id = {}
    ledger["records"].each_with_index do |raw_record, index|
      record = exact_mapping(raw_record, %w[
        seq process_id parent_process_id process_group_id kind purpose executable_identity
        target_executable_identity cwd argv environment network_mode sandbox_profile stdin stdout stderr exit_status signal waited
        child_process_ids prev_record_sha256 record_sha256
      ], "#{label} record #{index + 1}")
      process_id = record["process_id"]
      executable = identity_mapping(record["executable_identity"], "#{label} executable #{index + 1}")
      target_executable = identity_mapping(
        record["target_executable_identity"], "#{label} target executable #{index + 1}"
      )
      stdin = record["stdin"]&.then do |value|
        identity_mapping(value, "#{label} stdin #{index + 1}")
      end
      stdout = identity_mapping(record["stdout"], "#{label} stdout #{index + 1}")
      stderr = identity_mapping(record["stderr"], "#{label} stderr #{index + 1}")
      assert(record["seq"] == index + 1 && process_id.is_a?(String) && !process_id.empty? &&
             !records_by_id.key?(process_id) &&
             (record["parent_process_id"].nil? || record["parent_process_id"].is_a?(String)) &&
             record["process_group_id"].is_a?(String) && !record["process_group_id"].empty? &&
             record["kind"].is_a?(String) && !record["kind"].empty? &&
             record["purpose"].is_a?(String) && !record["purpose"].empty? &&
             record["cwd"].is_a?(String) && Pathname.new(record["cwd"]).absolute? &&
             record["argv"].is_a?(Array) && !record["argv"].empty? &&
             record["argv"].all? { |argument| argument.is_a?(String) } &&
             record["argv"].first == executable.fetch("path") &&
             record["environment"].is_a?(Hash) &&
             record["environment"].all? { |key, value| key.is_a?(String) && value.is_a?(String) } &&
             record["exit_status"].is_a?(Integer) &&
             (record["signal"].nil? || record["signal"].is_a?(Integer)) &&
             record["waited"] == true && record["child_process_ids"].is_a?(Array) &&
             record["child_process_ids"].all? { |id| id.is_a?(String) && !id.empty? } &&
             record["child_process_ids"].uniq == record["child_process_ids"],
             "#{label} record #{index + 1} process observation drift")
      assert(record["environment"].keys.none? { |key|
               key.match?(/(?:TOKEN|PASSWORD|SECRET|CREDENTIAL|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY)/i)
             }, "#{label} record #{index + 1} retained a secret or external proxy input")
      expected_profile = case record["network_mode"]
                         when "DENY_NETWORK"
                           DENY_NETWORK_SANDBOX_PROFILE
                         when "DOCKER_SOCKET_ONLY"
                           DOCKER_SOCKET_SANDBOX_PROFILE
                         else
                           assert(false, "#{label} record #{index + 1} network mode is not closed")
                         end
      assert(record["sandbox_profile"] == expected_profile,
             "#{label} record #{index + 1} sandbox profile drift")
      if record["network_mode"] == "DOCKER_SOCKET_ONLY"
        assert(record["kind"] == "DOCKER" &&
               target_executable.fetch("path") == DOCKER_CLI_PATH,
               "#{label} record #{index + 1} exposes the Docker socket outside exact Docker CLI")
      else
        assert(record["kind"] != "DOCKER",
               "#{label} record #{index + 1} Docker CLI lacks the socket-only sandbox")
      end
      assert(executable.fetch("path") == "/usr/bin/sandbox-exec" &&
             record["argv"].first(4) == [
               executable.fetch("path"), "-p", expected_profile, target_executable.fetch("path")
             ], "#{label} record #{index + 1} was not launched by the exact outer sandbox")
      read_identity!(root, executable, "#{label} executable #{index + 1}")
      read_identity!(root, target_executable, "#{label} target executable #{index + 1}")
      assert(stream_lookup.fetch(stdout.fetch("path"), nil) == stdout &&
             stream_lookup.fetch(stderr.fetch("path"), nil) == stderr,
             "#{label} record #{index + 1} stdout/stderr escaped the closed stream inventory")
      assert(stdin.nil? || stream_lookup.fetch(stdin.fetch("path"), nil) == stdin,
             "#{label} record #{index + 1} stdin escaped the closed stream inventory")
      used_stream_paths << stdin.fetch("path") if stdin
      used_stream_paths.concat([stdout.fetch("path"), stderr.fetch("path")])
      assert(record["prev_record_sha256"] == previous_hash,
             "#{label} record #{index + 1} hash-chain predecessor drift")
      calculated_hash = Digest::SHA256.hexdigest(
        canonical_json(record.reject { |key, _value| key == "record_sha256" })
      )
      assert(record["record_sha256"] == calculated_hash,
             "#{label} record #{index + 1} hash-chain digest drift")
      previous_hash = calculated_hash
      records_by_id[process_id] = record
    end
    assert(used_stream_paths.uniq.sort == stream_lookup.keys.sort,
           "#{label} has duplicate, missing or unreferenced process streams")
    records_by_id.each_value do |record|
      parent = record["parent_process_id"]
      assert(parent.nil? || records_by_id.key?(parent), "#{label} references an unknown parent process")
      assert((record["child_process_ids"] - records_by_id.keys).empty?,
             "#{label} references an unknown child process")
      actual_children = records_by_id.values.select { |candidate_record|
        candidate_record["parent_process_id"] == record["process_id"]
      }.map { |candidate_record| candidate_record.fetch("process_id") }
      assert(record["child_process_ids"].sort == actual_children.sort,
             "#{label} parent/child relation is not a closed bijection")
      record["child_process_ids"].each do |child|
        assert(records_by_id.fetch(child)["parent_process_id"] == record["process_id"],
               "#{label} parent/child relation is not bidirectional")
      end
    end
    records_by_id
  end

  def validate_raw_observation_stream!(task_id, role, stream_identity, evidence_root,
                                       candidate, observations)
    label = "P3 #{task_id} raw #{role} observation stream"
    _identity, bytes = validate_raw_stream!(
      stream_identity, evidence_root, "raw/run/streams", label
    )
    stream = parse_json!(bytes, label)
    stream = exact_mapping(stream, %w[
      schema_version record_type task_id route_id candidate artifact_id observations
    ], label)
    assert(stream["schema_version"] == "p3-trivs-evidence-first-raw-observation-stream/v1" &&
           stream["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_RAW_OBSERVATION_STREAM" &&
           stream["task_id"] == task_id && stream["route_id"] == ROUTE_ID &&
           stream["candidate"] == candidate && stream["artifact_id"] == role &&
           stream["observations"] == observations,
           "#{label} does not derive the artifact observations")
    stream.fetch("observations")
  end

  def validate_raw_observations!(root, task_id, role, observations, candidate,
                                 activation_parent, paths, artifact_streams)
    label = "P3 #{task_id} raw #{role} observations"
    case role
    when "candidate_binding"
      record = exact_mapping(observations, %w[
        activation_parent candidate generation candidate_first detached_clean
        source_manifest_matches source_unchanged_during_run verifier_root preflight_process_ids
      ], label)
      assert(record["activation_parent"] == activation_parent && record["candidate"] == candidate &&
             [1, 2].include?(record["generation"]) && record["candidate_first"] == true &&
             record["detached_clean"] == true && record["source_manifest_matches"] == true &&
             record["source_unchanged_during_run"] == true &&
             record["verifier_root"] == File.join(
               task_configuration(task_id).dig("resources", "evidence_root"),
               "verifier", candidate.fetch("commit")
             ) && record["preflight_process_ids"].is_a?(Array) &&
             record["preflight_process_ids"].length == 5 &&
             record["preflight_process_ids"].uniq.length == 5,
             "#{label} drift")
    when "frozen_dispatch"
      record = exact_mapping(observations, %w[
        frozen_before_first_spawn command_plan_sha256 closed_environment sandbox_profile
        docker_sandbox_profile jdk_major maven_version maven_arguments docker_cli_identity docker_endpoint mysql_image_content_id
        docker_allowed_verbs kill_points
      ], label)
      docker_cli = identity_mapping(record["docker_cli_identity"], "#{label} Docker CLI")
      assert(docker_cli["path"] == DOCKER_CLI_PATH, "#{label} Docker CLI path drift")
      read_identity!(root, docker_cli, "#{label} Docker CLI")
      assert(record["frozen_before_first_spawn"] == true &&
             record["command_plan_sha256"].is_a?(String) &&
             record["command_plan_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
             record["closed_environment"] == true &&
             record["sandbox_profile"] == "(version 1) (allow default) (deny network*)" &&
             record["docker_sandbox_profile"] == DOCKER_SOCKET_SANDBOX_PROFILE &&
             record["jdk_major"] == 17 && record["maven_version"] == "3.9.6" &&
             record["maven_arguments"] == %w[--offline --global-settings --settings -Dmaven.repo.local] &&
             record["docker_endpoint"] == "unix:///Users/lijunpeng/.docker/run/docker.sock" &&
             record["mysql_image_content_id"] ==
               "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209" &&
             record["docker_allowed_verbs"] == DOCKER_ALLOWED_VERBS &&
             record["kill_points"] == KILL_POINTS,
             "#{label} drift")
    when "source_inventory"
      record = exact_mapping(observations, %w[
        changed_paths git_clean harness_paths replay_paths product_main_paths
        product_test_paths rejected_lineage_reads
      ], label)
      harness_paths = paths.select { |path| path.start_with?(F2_WORKER_PATHS[0] + "/") }
      replay_paths = paths.select { |path| path.start_with?(F2_WORKER_PATHS[1] + "/") }
      product_main = paths.select { |path| path.start_with?("backend-spring/src/main/") }
      product_tests = paths.select { |path| path.start_with?("backend-spring/src/test/") }
      assert(record["changed_paths"] == paths && record["git_clean"] == true &&
             record["harness_paths"] == harness_paths && record["replay_paths"] == replay_paths &&
             record["product_main_paths"] == product_main &&
             record["product_test_paths"] == product_tests &&
             record["rejected_lineage_reads"] == 0 &&
             (task_id == F2_TASK_ID ?
               (!harness_paths.empty? && !replay_paths.empty? && product_main.empty? && product_tests.empty?) :
               (harness_paths.empty? && replay_paths.empty? && !product_main.empty? && !product_tests.empty?)),
             "#{label} drift")
    when "toolchain_dependency_custody"
      record = exact_mapping(observations, %w[
        process_ids jdk_java_identity maven_executable_identity dependency_file_count
        all_dependencies_regular_non_symlink closed_dependency_custody
        fresh_maven_repo user_repo_writeback maven_process_count all_maven_processes_offline
        all_build_processes_sandboxed unsandboxed_build_processes
        global_settings_identity user_settings_identity dependency_custody_manifest
        fresh_repo_absence_process_ids fresh_repo_init_process_ids
        fresh_repo_manifest_build_1 fresh_repo_manifest_build_2
      ], label)
      jdk = identity_mapping(record["jdk_java_identity"], "#{label} JDK17 java")
      maven = identity_mapping(record["maven_executable_identity"], "#{label} Maven 3.9.6")
      assert(jdk["path"] == File.join(JDK17_HOME, "bin/java") &&
             maven["path"] == MAVEN_396_PATH,
             "#{label} toolchain path drift")
      read_identity!(root, jdk, "#{label} JDK17 java")
      read_identity!(root, maven, "#{label} Maven 3.9.6")
      assert(record["process_ids"].is_a?(Array) && !record["process_ids"].empty? &&
             record["dependency_file_count"].is_a?(Integer) && record["dependency_file_count"].positive? &&
             record["all_dependencies_regular_non_symlink"] == true &&
             record["closed_dependency_custody"] == true && record["fresh_maven_repo"] == true &&
             record["user_repo_writeback"] == false &&
             record["maven_process_count"].is_a?(Integer) && record["maven_process_count"] >= 2 &&
             record["all_maven_processes_offline"] == true &&
             record["all_build_processes_sandboxed"] == true &&
             record["unsandboxed_build_processes"] == 0,
             "#{label} drift")
    when "process_ledger"
      record = exact_mapping(observations, %w[
        process_ids process_count sequence_contiguous hash_chain_valid argv_arrays_only cwd_bound
        closed_env_bound stdin_bound stdout_bound stderr_bound exit_bound all_children_accounted all_waited
        process_group_survivors unexpected_processes
      ], label)
      ids = record["process_ids"]
      assert(ids.is_a?(Array) && !ids.empty? && ids.all? { |id| id.is_a?(String) && !id.empty? } &&
             ids.uniq == ids && record["process_count"] == ids.length &&
             %w[sequence_contiguous hash_chain_valid argv_arrays_only cwd_bound closed_env_bound
                stdin_bound stdout_bound stderr_bound exit_bound all_children_accounted all_waited].all? {
               |key| record[key] == true
             } && record["process_group_survivors"] == 0 && record["unexpected_processes"] == 0 &&
             artifact_streams.length >= ids.length * 2,
             "#{label} drift")
    when "network_enforcement"
      record = exact_mapping(observations, %w[
        probe_process_ids probe_results sandbox_profile successful_external_connections
        unwrapped_build_or_jvm_processes docker_registry_operations non_loopback_published_ports
      ], label)
      probes = exact_mapping(record["probe_process_ids"], %w[dns af_inet af_inet6], "#{label} probes")
      results = exact_mapping(record["probe_results"], %w[dns af_inet af_inet6], "#{label} results")
      assert(probes.values.all? { |id| id.is_a?(String) && !id.empty? } && probes.values.uniq.length == 3 &&
             results.values.all? { |verdict| verdict == "DENIED_BY_OS_SANDBOX" } &&
             record["sandbox_profile"] == "(version 1) (allow default) (deny network*)" &&
             record["successful_external_connections"] == 0 &&
             record["unwrapped_build_or_jvm_processes"] == 0 &&
             record["docker_registry_operations"] == 0 &&
             record["non_loopback_published_ports"] == 0,
             "#{label} drift")
    when "build_reproducibility"
      record = exact_mapping(observations, %w[
        process_ids clean_build_count normalized_summaries_byte_equal source_to_class_replay
        helper_clean_build_count helper_binaries_byte_equal mismatches
        clean_build_process_ids helper_build_process_ids helper_source_manifest
        helper_binary_build_1 helper_binary_build_2 helper_rootfs_build_1 helper_rootfs_build_2
        normalized_summary_build_1 normalized_summary_build_2
        class_inventory_build_1 class_inventory_build_2
      ], label)
      process_ids = record.delete("process_ids")
      clean_build_process_ids = record.delete("clean_build_process_ids")
      helper_build_process_ids = record.delete("helper_build_process_ids")
      identity_fields = %w[
        helper_source_manifest helper_binary_build_1 helper_binary_build_2
        helper_rootfs_build_1 helper_rootfs_build_2 normalized_summary_build_1
        normalized_summary_build_2 class_inventory_build_1 class_inventory_build_2
      ].to_h { |key| [key, record.delete(key)] }
      assert(process_ids.is_a?(Array) && !process_ids.empty? && record == {
        "clean_build_count" => 2, "normalized_summaries_byte_equal" => true,
        "source_to_class_replay" => true, "helper_clean_build_count" => 2,
        "helper_binaries_byte_equal" => true, "mismatches" => 0
      }, "#{label} drift")
      record["process_ids"] = process_ids
      record["clean_build_process_ids"] = clean_build_process_ids
      record["helper_build_process_ids"] = helper_build_process_ids
      identity_fields.each { |key, value| record[key] = value }
    when "mysql_custody_transcript"
      record = exact_mapping(observations, %w[
        process_ids real_mysql_started image_content_id fresh_empty_database loopback_only
        migration_fixture_exercised mutation_case_ids mutation_outcomes false_accepts cleanup_complete
        probe_source_manifest probe_class_inventory_build_1 probe_class_inventory_build_2
        probe_binary_build_1 probe_binary_build_2 probe_rootfs_build_1 probe_rootfs_build_2
        probe_rootfs_identity probe_image probe_action probe_build_process_ids
      ], label)
      cases = %w[fake-mysql nonfresh misbound migration-mismatch]
      assert(record["process_ids"].is_a?(Array) && !record["process_ids"].empty? &&
             record["real_mysql_started"] == true && record["image_content_id"] ==
               "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209" &&
             record["fresh_empty_database"] == true && record["loopback_only"] == true &&
             record["migration_fixture_exercised"] == true && record["mutation_case_ids"] == cases &&
             record["mutation_outcomes"] == cases.to_h { |id| [id, "NON_PASS"] } &&
             record["false_accepts"] == 0 && record["cleanup_complete"] == true &&
             record["probe_image"].is_a?(String) &&
             record["probe_action"] == "MYSQL_CUSTODY_ACCEPTANCE_V1",
             "#{label} drift")
    when "oci_custody_transcript"
      record = exact_mapping(observations, %w[
        process_ids docker_endpoint exact_cli_identity exact_image_content_id task_scoped_names_labels
        network_none read_only_rootfs resource_limits host_source_mounts registry_operations
        mutation_case_ids mutation_outcomes false_accepts cleanup_complete
      ], label)
      cases = %w[wrong-image wrong-rootfs host-source-mount registry-operation orphan-object]
      assert(record["process_ids"].is_a?(Array) && !record["process_ids"].empty? &&
             record["docker_endpoint"] == "unix:///Users/lijunpeng/.docker/run/docker.sock" &&
             record["exact_cli_identity"] == true && record["exact_image_content_id"] == true &&
             record["task_scoped_names_labels"] == true && record["network_none"] == true &&
             record["read_only_rootfs"] == true && record["resource_limits"] == true &&
             record["host_source_mounts"] == 0 && record["registry_operations"] == 0 &&
             record["mutation_case_ids"] == cases &&
             record["mutation_outcomes"] == cases.to_h { |id| [id, "NON_PASS"] } &&
             record["false_accepts"] == 0 && record["cleanup_complete"] == true,
             "#{label} drift")
    when "real_mysql_transcript"
      record = exact_mapping(observations, %w[
        process_ids real_mysql image_content_id mysql_version migration_v034_success
        production_spring_transaction_path exactly_one_intent exactly_one_terminal
        duplicate_effects permanent_dispatching identical_custody_collisions rollback_matrix_pass
        cleanup_complete
        probe_source_manifest probe_class_inventory_build_1 probe_class_inventory_build_2
        probe_binary_build_1 probe_binary_build_2 probe_rootfs_build_1 probe_rootfs_build_2
        probe_rootfs_identity probe_image probe_action probe_build_process_ids
        spring_dispatch_process_id spring_recovery_process_id
      ], label)
      assert(record["process_ids"].is_a?(Array) && !record["process_ids"].empty? &&
             record["real_mysql"] == true && record["image_content_id"] ==
               "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209" &&
             record["mysql_version"].is_a?(String) && !record["mysql_version"].empty? &&
             record["migration_v034_success"] == true &&
             record["production_spring_transaction_path"] == true &&
             record["exactly_one_intent"] == true && record["exactly_one_terminal"] == true &&
             record["duplicate_effects"] == 0 && record["permanent_dispatching"] == 0 &&
             record["identical_custody_collisions"] == 0 &&
             record["rollback_matrix_pass"] == true && record["cleanup_complete"] == true &&
             record["probe_image"].is_a?(String) &&
             record["probe_action"] == "PRODUCT_SPRING_MYSQL_ACCEPTANCE_V1",
             "#{label} drift")
    when "oci_hostile_context_transcript"
      record = exact_mapping(observations, %w[
        process_ids docker_endpoint exact_cli_identity pinned_image_identity task_scoped_names_labels
        hostile_contexts network_none read_only_rootfs resource_limits host_source_mounts
        registry_operations credential_helper_invocations cleanup_complete
      ], label)
      assert(record["process_ids"].is_a?(Array) && !record["process_ids"].empty? &&
             record["docker_endpoint"] == "unix:///Users/lijunpeng/.docker/run/docker.sock" &&
             record["exact_cli_identity"] == true && record["pinned_image_identity"] == true &&
             record["task_scoped_names_labels"] == true &&
             record["hostile_contexts"] == %w[HOME DOCKER_CONTEXT DOCKER_CONFIG proxy credential-helper] &&
             record["network_none"] == true && record["read_only_rootfs"] == true &&
             record["resource_limits"] == true && record["host_source_mounts"] == 0 &&
             record["registry_operations"] == 0 && record["credential_helper_invocations"] == 0 &&
             record["cleanup_complete"] == true,
             "#{label} drift")
    when "seven_kill_orchestrator", "seven_kill_recovery_matrix"
      record = exact_mapping(observations, %w[
        process_ids kill_points real_sigkill_count fresh_recovery_process_count
        exactly_one_terminal_each duplicate_effects orphan_objects permanent_dispatching false_accepts
      ], label)
      assert(record["process_ids"].is_a?(Array) && record["process_ids"].length == KILL_POINTS.length * 2 &&
             record["kill_points"] == KILL_POINTS && record["real_sigkill_count"] == 7 &&
             record["fresh_recovery_process_count"] == 7 &&
             record["exactly_one_terminal_each"] == true && record["duplicate_effects"] == 0 &&
             record["orphan_objects"] == 0 && record["permanent_dispatching"] == 0 &&
             record["false_accepts"] == 0,
             "#{label} drift")
    when "helper_reproducibility"
      record = exact_mapping(observations, %w[
        process_ids source_build_count binary_byte_equal rootfs_identity_equal
        always_exit_zero_rejected wrong_binary_rejected wrong_rootfs_rejected
      ], label)
      assert(record["process_ids"].is_a?(Array) && !record["process_ids"].empty? &&
             record["source_build_count"] == 2 && record["binary_byte_equal"] == true &&
             record["rootfs_identity_equal"] == true && record["always_exit_zero_rejected"] == true &&
             record["wrong_binary_rejected"] == true && record["wrong_rootfs_rejected"] == true,
             "#{label} drift")
    when "adversarial_matrix"
      record = exact_mapping(observations, %w[
        process_ids case_ids outcomes covered_finding_ids false_accepts
      ], label)
      cases = task_id == F2_TASK_ID ? F2_ADVERSARIAL_CASES : P2_ADVERSARIAL_CASES
      assert(record["process_ids"].is_a?(Array) && record["process_ids"].length == cases.length &&
             record["process_ids"].uniq == record["process_ids"] && record["case_ids"] == cases &&
             record["outcomes"] == cases.to_h { |id| [id, "NON_PASS"] } &&
             record["covered_finding_ids"] == TERMINAL_FINDING_IDS && record["false_accepts"] == 0,
             "#{label} drift")
    when "zero_external_effects"
      keys = %w[
        process_ids network dns http_https provider secret credential remote production public
        existing_non_task_database_mutation irreversible_asset_deletion p4_effect
      ]
      record = exact_mapping(observations, keys, label)
      process_ids = record.delete("process_ids")
      assert(process_ids.is_a?(Array) && !process_ids.empty? &&
             record.values.all? { |value| value == 0 }, "#{label} drift")
      record["process_ids"] = process_ids
    when "independent_replay"
      record = exact_mapping(observations, %w[
        process_ids replayer_identity input_artifact_roles exit_status false_accepts derived_metrics
      ], label)
      replayer = identity_mapping(record["replayer_identity"], "#{label} replayer")
      expected_replayer =
        "evaluation-harness/replay/p3-trivs-candidate-bound-acceptance-v1/replay.mjs"
      assert(replayer["path"] == expected_replayer,
             "#{label} replayer path drift")
      replay_bytes = read_identity!(root, replayer, "#{label} replayer")
      candidate_replay = git!(root, "show", "#{candidate.fetch('commit')}:#{expected_replayer}").first
      assert(candidate_replay == replay_bytes && record["process_ids"].is_a?(Array) &&
             record["process_ids"].length == 1 &&
             record["input_artifact_roles"].is_a?(Array) &&
             record["exit_status"] == 0 && record["false_accepts"] == 0,
             "#{label} replay binding drift")
    when "final_cleanup_state"
      record = exact_mapping(observations, %w[
        process_group_survivors task_created_containers_remaining task_created_volumes_remaining
        task_created_images_remaining unrelated_objects_touched pinned_mysql_image_removed cleanup_complete
      ], label)
      assert(record == {
        "process_group_survivors" => 0, "task_created_containers_remaining" => 0,
        "task_created_volumes_remaining" => 0, "task_created_images_remaining" => 0,
        "unrelated_objects_touched" => false, "pinned_mysql_image_removed" => false,
        "cleanup_complete" => true
      }, "#{label} drift")
    else
      assert(false, "#{label} has no closed validator")
    end
    record
  end

  def validate_raw_evidence!(root, task_id, identity, candidate, activation_parent, paths)
    config = task_configuration(task_id)
    evidence_root = config.dig("resources", "evidence_root")
    relative_manifest = RESULT_PATHS.fetch(task_id).fetch("raw_evidence_manifest")
    manifest_identity, bytes = secure_evidence_read!(
      identity, evidence_root, relative_manifest, "P3 #{task_id} closed raw Evidence manifest"
    )
    manifest = parse_json!(bytes, "P3 #{task_id} closed raw Evidence manifest")
    manifest = exact_mapping(manifest, %w[
      schema_version record_type task_id route_id candidate status run_root
      artifacts streams derived_metrics
    ], "P3 #{task_id} closed raw Evidence manifest")
    roles = task_id == F2_TASK_ID ? F2_RAW_ARTIFACT_ROLES : P2_RAW_ARTIFACT_ROLES
    expected_metrics = task_id == F2_TASK_ID ? f2_gate_metrics : product_gate_metrics
    run_root = Pathname.new(evidence_root).join("raw/run").to_s
    assert(manifest["schema_version"] == RAW_EVIDENCE_MANIFEST_SCHEMA &&
           manifest["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_CLOSED_RAW_EVIDENCE_MANIFEST" &&
           manifest["task_id"] == task_id && manifest["route_id"] == ROUTE_ID &&
           manifest["candidate"] == candidate &&
           manifest["status"] == "CLOSED_BEFORE_INDEPENDENT_REVIEW" &&
           manifest["run_root"] == run_root && manifest["derived_metrics"] == expected_metrics,
           "P3 #{task_id} raw Evidence manifest header or derived outcome drift")
    artifacts = exact_mapping(manifest["artifacts"], roles,
                              "P3 #{task_id} raw Evidence artifacts")
    stream_list = manifest["streams"]
    assert(stream_list.is_a?(Array) && !stream_list.empty?,
           "P3 #{task_id} raw Evidence stream inventory is empty")
    stream_identities = stream_list.map.with_index do |stream, index|
      validate_raw_stream!(stream, evidence_root, "raw/run/streams",
                           "P3 #{task_id} raw stream #{index}").first
    end
    assert(stream_identities.map { |stream| stream.fetch("path") }.uniq.length == stream_identities.length,
           "P3 #{task_id} raw stream inventory contains duplicate paths")
    streams_by_path = stream_identities.to_h { |stream| [stream.fetch("path"), stream] }

    records = {}
    process_records_by_id = nil
    artifact_stream_paths = {}
    referenced_streams = []
    artifact_paths = []
    roles.each do |role|
      artifact_identity, artifact_bytes = secure_evidence_read!(
        artifacts.fetch(role), evidence_root, "raw/run/artifacts/#{role}.json",
        "P3 #{task_id} raw artifact #{role}"
      )
      artifact_paths << artifact_identity.fetch("path")
      artifact = parse_json!(artifact_bytes, "P3 #{task_id} raw artifact #{role}")
      artifact = exact_mapping(artifact, %w[
        schema_version record_type artifact_id task_id route_id candidate status
        stream_identities observations
      ], "P3 #{task_id} raw artifact #{role}")
      artifact_streams = artifact["stream_identities"]
      assert(artifact["schema_version"] == RAW_EVIDENCE_ARTIFACT_SCHEMA &&
             artifact["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_RAW_EVIDENCE_ARTIFACT" &&
             artifact["artifact_id"] == role && artifact["task_id"] == task_id &&
             artifact["route_id"] == ROUTE_ID && artifact["candidate"] == candidate &&
             artifact["status"] == "CAPTURED_CREATE_ONCE" &&
             artifact_streams.is_a?(Array) && !artifact_streams.empty?,
             "P3 #{task_id} raw artifact #{role} header drift")
      normalized_streams = artifact_streams.map do |stream|
        stream = identity_mapping(stream, "P3 #{task_id} raw artifact #{role} stream")
        assert(streams_by_path.fetch(stream.fetch("path"), nil) == stream,
               "P3 #{task_id} raw artifact #{role} references an unbound stream")
        stream
      end
      assert(normalized_streams.map { |stream| stream.fetch("path") }.uniq.length == normalized_streams.length,
             "P3 #{task_id} raw artifact #{role} repeats a stream")
      artifact_stream_paths[role] = normalized_streams.map { |stream| stream.fetch("path") }
      referenced_streams.concat(normalized_streams.map { |stream| stream.fetch("path") })
      streamed_observations = if role == "process_ledger"
                                artifact["observations"]
                              else
                                validate_raw_observation_stream!(
                                  task_id, role, normalized_streams.first, evidence_root,
                                  candidate, artifact["observations"]
                                )
                              end
      observations = validate_raw_observations!(
        root, task_id, role, streamed_observations, candidate, activation_parent, paths,
        normalized_streams
      )
      records[role] = observations
      if role == "process_ledger"
        process_records_by_id = validate_process_ledger_stream!(
          root, task_id, normalized_streams, evidence_root, candidate
        )
        assert(observations["process_ids"] == process_records_by_id.keys,
               "P3 #{task_id} process ledger summary does not derive from its raw stream")
      end
    end
    assert(referenced_streams.uniq.sort == streams_by_path.keys.sort,
           "P3 #{task_id} raw Evidence contains an unreferenced or missing stream")

    process_ids = records.fetch("process_ledger").fetch("process_ids")
    assert(process_records_by_id.is_a?(Hash) && process_records_by_id.keys == process_ids,
           "P3 #{task_id} raw process ledger was not mechanically derived")
    command_plan = process_records_by_id.values.map do |process|
      process.slice(
        "process_id", "kind", "purpose", "target_executable_identity", "cwd", "argv",
        "environment", "network_mode", "sandbox_profile"
      )
    end
    assert(Digest::SHA256.hexdigest(canonical_json(command_plan)) ==
             records.dig("frozen_dispatch", "command_plan_sha256"),
           "P3 #{task_id} frozen dispatch hash does not bind the raw process command plan")
    records.each do |role, observations|
      observations.each do |key, value|
        next unless key == "process_ids" || key == "probe_process_ids"

        ids = value.is_a?(Hash) ? value.values : value
        assert(ids.is_a?(Array) && (ids - process_ids).empty?,
               "P3 #{task_id} raw #{role} references a process outside the closed ledger")
        required_process_streams = ids.flat_map do |id|
          process = process_records_by_id.fetch(id)
          [process.dig("stdin", "path"), process.dig("stdout", "path"),
           process.dig("stderr", "path")].compact
        end.uniq
        assert((required_process_streams - artifact_stream_paths.fetch(role)).empty?,
               "P3 #{task_id} raw #{role} does not bind its referenced process stdout/stderr")
      end
    end
    independent = records.fetch("independent_replay")
    assert(independent["input_artifact_roles"] ==
             roles.reject { |role| %w[independent_replay final_cleanup_state].include?(role) } &&
           independent["derived_metrics"] == expected_metrics,
           "P3 #{task_id} independent replay did not derive the closed raw Evidence outcome")
    verifier_preflight_last_seq = validate_detached_verifier_preflight!(
      root, task_id, records.fetch("candidate_binding"), process_records_by_id,
      evidence_root, candidate, artifact_stream_paths.fetch("candidate_binding")
    )
    custody_binding = validate_maven_dependency_custody!(
      task_id, records.fetch("toolchain_dependency_custody"), process_records_by_id,
      evidence_root, candidate, artifact_stream_paths.fetch("toolchain_dependency_custody"),
      verifier_preflight_last_seq
    )
    maven_records = process_records_by_id.values.select { |record| record["kind"] == "MAVEN" }
                                         .sort_by { |record| record.fetch("purpose") }
    maven_process_ids = maven_records.map { |record| record.fetch("process_id") }
    assert(maven_records.length == 2 &&
           maven_records.length == records.dig("toolchain_dependency_custody", "maven_process_count") &&
           records.dig("toolchain_dependency_custody", "process_ids").sort ==
             (maven_process_ids + custody_binding.fetch("process_ids")).sort &&
           maven_records.map { |record| record["purpose"] }.sort == %w[CLEAN_BUILD_1 CLEAN_BUILD_2] &&
           maven_records.each_with_index.all? { |record, index|
             record["seq"] > custody_binding.fetch("sequences").fetch(index) &&
               validate_clean_build_record!(record, evidence_root, candidate)
           } && maven_records.first.fetch("seq") < custody_binding.fetch("sequences").last,
           "P3 #{task_id} raw Maven set is not exactly two detached offline clean-test builds")
    build_observations = records.fetch("build_reproducibility")
    assert(build_observations["clean_build_count"] == 2 &&
           build_observations["clean_build_process_ids"].sort == maven_process_ids.sort,
           "P3 #{task_id} clean-build result did not derive from the exact two Maven processes")
    normalized_summaries = maven_records.each_with_index.map do |record, index|
      generation = index + 1
      identity = identity_mapping(
        build_observations["normalized_summary_build_#{generation}"],
        "P3 #{task_id} normalized Maven summary #{generation}"
      )
      assert(artifact_stream_paths.fetch("build_reproducibility").include?(identity.fetch("path")),
             "P3 #{task_id} normalized Maven summary #{generation} escaped its artifact streams")
      summary_bytes = validate_raw_stream!(
        identity, evidence_root, "raw/run/streams",
        "P3 #{task_id} normalized Maven summary #{generation}"
      ).last
      assert(summary_bytes == normalized_maven_summary_bytes!(record, evidence_root, candidate),
             "P3 #{task_id} normalized Maven summary #{generation} differs from raw Maven stdout")
      summary_bytes
    end
    assert(normalized_summaries.first == normalized_summaries.last,
           "P3 #{task_id} two normalized Maven summaries are not byte-equal")
    mysql_role = task_id == F2_TASK_ID ? "mysql_custody_transcript" : "real_mysql_transcript"
    [1, 2].each do |generation|
      class_identity = identity_mapping(
        build_observations["class_inventory_build_#{generation}"],
        "P3 #{task_id} class inventory build #{generation}"
      )
      assert(class_identity == records.dig(mysql_role, "probe_class_inventory_build_#{generation}") &&
             artifact_stream_paths.fetch("build_reproducibility").include?(class_identity.fetch("path")),
             "P3 #{task_id} build reproducibility lost its class inventory binding")
    end
    helper_binding = validate_helper_build_binding!(
      root, task_id, build_observations, process_records_by_id,
      evidence_root, candidate, artifact_stream_paths.fetch("build_reproducibility")
    )
    if task_id == P2_TASK_ID
      assert(records.dig("helper_reproducibility", "process_ids").sort ==
               helper_binding.fetch("all_helper_process_ids").sort,
             "P3 #{task_id} helper reproducibility did not derive from the exact helper builds")
    end
    network_process_ids = []
    network_environment = {
      "PATH" => "#{File.dirname(NODE22_RUNTIME_PATH)}:/usr/bin:/bin", "HOME" => "/var/empty",
      "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC"
    }
    verifier_root = File.join(evidence_root, "verifier", candidate.fetch("commit"))
    %w[dns af_inet af_inet6].each do |probe|
      process = process_records_by_id.fetch(
        records.dig("network_enforcement", "probe_process_ids", probe)
      )
      network_process_ids << process.fetch("process_id")
      expected_probe_argv = [
        "/usr/bin/sandbox-exec", "-p", DENY_NETWORK_SANDBOX_PROFILE, NODE22_RUNTIME_PATH,
        NETWORK_PROBE_SCRIPT, "--probe", probe
      ]
      _stdout_identity, probe_stdout = validate_raw_stream!(
        process.fetch("stdout"), evidence_root, "raw/run/streams",
        "P3 #{task_id} #{probe} probe stdout"
      )
      _stderr_identity, probe_stderr = validate_raw_stream!(
        process.fetch("stderr"), evidence_root, "raw/run/streams",
        "P3 #{task_id} #{probe} probe stderr"
      )
      assert(process["kind"] == "NETWORK_PROBE" &&
             process["purpose"] == "NETWORK_PROBE_#{probe.upcase}" &&
             process["parent_process_id"].nil? && process["child_process_ids"].empty? &&
             process["cwd"] == verifier_root && process["environment"] == network_environment &&
             process["stdin"].nil? && process["network_mode"] == "DENY_NETWORK" &&
             process["argv"] == expected_probe_argv &&
             process.dig("target_executable_identity", "path") == NODE22_RUNTIME_PATH &&
             process["exit_status"] == 77 && process["signal"].nil? && probe_stdout.empty? &&
             probe_stderr == "NETWORK_DENIED_BY_OS_SANDBOX:#{probe}\n" &&
             [process.dig("stdout", "path"), process.dig("stderr", "path")].all? { |path|
               artifact_stream_paths.fetch("network_enforcement").include?(path)
             },
             "P3 #{task_id} raw #{probe} probe does not prove exact OS sandbox rejection")
    end
    adversarial_process_ids = validate_adversarial_processes!(
      task_id, records.fetch("adversarial_matrix"), process_records_by_id, evidence_root,
      candidate, artifact_stream_paths.fetch("adversarial_matrix")
    )
    replay_process_id = validate_independent_replay_process!(
      task_id, independent, process_records_by_id, evidence_root, candidate,
      artifact_stream_paths.fetch("independent_replay"), expected_metrics
    )
    kill_role = task_id == F2_TASK_ID ? "seven_kill_orchestrator" : "seven_kill_recovery_matrix"
    docker_records = process_records_by_id.values.select { |record| record["kind"] == "DOCKER" }
    expected_docker_environment = {
      "PATH" => "#{File.dirname(DOCKER_CLI_PATH)}:/usr/bin:/bin", "HOME" => "/var/empty",
      "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC"
    }
    docker_descriptors = {}
    assert(!docker_records.empty?, "P3 #{task_id} raw Docker process set is empty")
    docker_records.each do |record|
      expected_prefix = [
        "/usr/bin/sandbox-exec", "-p", DOCKER_SOCKET_SANDBOX_PROFILE, DOCKER_CLI_PATH,
        "--host", DOCKER_ENDPOINT, "--config", File.join(evidence_root, "docker-config")
      ]
      assert(record["argv"].first(expected_prefix.length) == expected_prefix &&
             record["parent_process_id"].nil? && record["child_process_ids"].empty? &&
             record["cwd"] == evidence_root && record["signal"].nil? &&
             record["environment"] == expected_docker_environment &&
             record["network_mode"] == "DOCKER_SOCKET_ONLY" &&
             record["target_executable_identity"] ==
               records.dig("frozen_dispatch", "docker_cli_identity") &&
             record.dig("target_executable_identity", "path") == DOCKER_CLI_PATH,
             "P3 #{task_id} Docker process escaped its exact socket, sandbox or closed environment")
      docker_descriptors[record.fetch("process_id")] = validate_docker_operation_args!(
        task_id, record["argv"].drop(expected_prefix.length), evidence_root
      )
    end
    mysql_binding = validate_mysql_process_transcript!(
      root, task_id, records.fetch(mysql_role), process_records_by_id, docker_descriptors,
      records.dig(mysql_role, "process_ids"), evidence_root, candidate,
      artifact_stream_paths.fetch(mysql_role)
    )
    oci_role = task_id == F2_TASK_ID ? "oci_custody_transcript" : "oci_hostile_context_transcript"
    oci_binding = validate_oci_process_transcript!(
      task_id, process_records_by_id, docker_descriptors,
      records.dig(oci_role, "process_ids"), evidence_root, helper_binding
    )
    kill_binding = validate_seven_kill_processes!(
      task_id, records.fetch(kill_role), process_records_by_id, evidence_root, candidate,
      artifact_stream_paths.fetch(kill_role), mysql_binding.fetch("spring_classpath"),
      oci_binding, helper_binding
    )
    validate_seven_kill_oci_anchors!(
      task_id, kill_binding, oci_binding, helper_binding,
      process_records_by_id.fetch(replay_process_id)
    )
    claimed_docker_ids = [*records.dig(mysql_role, "process_ids"),
                          *records.dig(oci_role, "process_ids")].select do |process_id|
      process_records_by_id.fetch(process_id)["kind"] == "DOCKER"
    end.uniq
    effectful_docker_ids = docker_descriptors.select do |_process_id, descriptor|
      !%w[version info].include?(descriptor.fetch("operation"))
    end.keys
    assert(effectful_docker_ids.sort == claimed_docker_ids.sort,
           "P3 #{task_id} contains an untranscripted or multiply scoped Docker daemon operation")
    %w[version info].each do |operation|
      records_for_operation = docker_descriptors.select do |_process_id, descriptor|
        descriptor.fetch("operation") == operation
      end.keys.map { |process_id| process_records_by_id.fetch(process_id) }
      assert(records_for_operation.length == 1 &&
             records_for_operation.first["purpose"] == "DOCKER_#{operation.upcase}_PREFLIGHT" &&
             records_for_operation.first["exit_status"] == 0 &&
             records_for_operation.first["signal"].nil?,
             "P3 #{task_id} lacks one exact read-only Docker #{operation} preflight")
    end

    validated_process_ids = [
      *records.dig("candidate_binding", "preflight_process_ids"),
      *custody_binding.fetch("process_ids"), *maven_process_ids,
      *helper_binding.fetch("all_helper_process_ids"), *network_process_ids,
      *adversarial_process_ids, replay_process_id, *kill_binding.fetch("process_ids"),
      *mysql_binding.fetch("non_docker_process_ids"), *docker_records.map { |record|
        record.fetch("process_id")
      }
    ].uniq
    assert(validated_process_ids.sort == process_ids.sort,
           "P3 #{task_id} process ledger contains an unclaimed or semantically unvalidated process")
    if task_id == P2_TASK_ID
      assert(records.dig("zero_external_effects", "process_ids").sort == process_ids.sort,
             "P3 #{task_id} zero-external-effects artifact does not cover the closed process ledger")
    end

    actual_files = []
    Find.find(run_root) do |entry|
      next if entry == run_root

      stat = File.lstat(entry)
      assert(!stat.symlink?, "P3 #{task_id} raw Evidence run root contains a symlink")
      if stat.file?
        actual_files << entry
      else
        assert(stat.directory?, "P3 #{task_id} raw Evidence run root contains a non-file object")
      end
    end
    expected_files = artifact_paths + streams_by_path.keys
    assert(actual_files.sort == expected_files.sort,
           "P3 #{task_id} raw Evidence closed inventory differs from disk")
    [manifest_identity, manifest, records]
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "P3 #{task_id} raw Evidence unavailable: #{e.class}"
  end

  def validate_canonical_replay_bundle!(root, task_id, identity, candidate,
                                        raw_manifest_identity, raw_records, immutable_paths)
    config = task_configuration(task_id)
    evidence_root = config.dig("resources", "evidence_root")
    relative = RESULT_PATHS.fetch(task_id).fetch("canonical_replay_bundle")
    bundle_identity, bytes = secure_evidence_read!(
      identity, evidence_root, relative, "P3 #{task_id} canonical replay raw bundle"
    )
    bundle = parse_json!(bytes, "P3 #{task_id} canonical replay raw bundle")
    bundle = exact_mapping(bundle, %w[
      schema_version record_type task_id route_id candidate raw_evidence_manifest
      sandbox_identity runtime_identity replayer_identity canonical_commit canonical_tree
      candidate_owned_paths candidate_owned_paths_byte_equal argv cwd environment
      sandbox_profile replay_attempt_id replay_attempt_ordinal dispatch_count attempt_consumed
      rerun_allowed timeout_seconds timed_out started_at_utc finished_at_utc
      attempt_journal network_probe_streams mutation_streams
      network_probe_verdicts mutation_verdicts stdout stderr exit_status derived_metrics
    ], "P3 #{task_id} canonical replay raw bundle")
    expected_metrics = task_id == F2_TASK_ID ? f2_gate_metrics : product_gate_metrics
    sandbox = identity_mapping(bundle["sandbox_identity"], "P3 canonical replay sandbox")
    runtime = identity_mapping(bundle["runtime_identity"], "P3 canonical replay runtime")
    replayer = identity_mapping(bundle["replayer_identity"], "P3 canonical replay replayer")
    assert(sandbox["path"] == "/usr/bin/sandbox-exec",
           "P3 canonical replay sandbox path drift")
    read_identity!(root, sandbox, "P3 canonical replay sandbox")
    read_identity!(root, runtime, "P3 canonical replay runtime")
    read_identity!(root, replayer, "P3 canonical replay replayer")
    expected_replayer = raw_records.dig("independent_replay", "replayer_identity")
    stdout_identity, stdout_bytes = validate_raw_stream!(
      bundle["stdout"], evidence_root, "replay/raw", "P3 canonical replay stdout"
    )
    stderr_identity, stderr_bytes = validate_raw_stream!(
      bundle["stderr"], evidence_root, "replay/raw", "P3 canonical replay stderr"
    )
    expected_argv = [
      sandbox.fetch("path"), "-p", READ_ONLY_REPLAY_SANDBOX_PROFILE,
      runtime.fetch("path"), replayer.fetch("path"), "--manifest", raw_manifest_identity.fetch("path"),
      "--mode", "canonical-read-only"
    ]
    expected_environment = {
      "PATH" => "#{File.dirname(runtime.fetch('path'))}:/usr/bin:/bin",
      "HOME" => "/var/empty", "LANG" => "C", "LC_ALL" => "C", "TZ" => "UTC"
    }
    expected_probe_verdicts = {
      "dns" => "DENIED_BY_OS_SANDBOX",
      "af_inet" => "DENIED_BY_OS_SANDBOX",
      "af_inet6" => "DENIED_BY_OS_SANDBOX"
    }
    expected_mutation_verdicts = %w[
      MISSING_ARTIFACT CANDIDATE_MISMATCH MISSING_STREAM METRICS_MISMATCH
      RUN_ROOT_ESCAPE ARTIFACT_IDENTITY_MISMATCH
    ].to_h { |reason| [reason, "NON_PASS"] }
    begin
      replay_started = Time.iso8601(bundle.fetch("started_at_utc"))
      replay_finished = Time.iso8601(bundle.fetch("finished_at_utc"))
    rescue ArgumentError
      assert(false, "P3 #{task_id} canonical replay timestamps are invalid")
    end
    journal_identity, journal_bytes = validate_raw_stream!(
      bundle["attempt_journal"], evidence_root, "replay/raw",
      "P3 #{task_id} canonical replay attempt journal"
    )
    journal = exact_mapping(parse_json!(journal_bytes, "P3 #{task_id} replay attempt journal"), %w[
      schema_version task_id route_id candidate replay_attempt_id dispatch_count
      entries final_entry_sha256
    ], "P3 #{task_id} replay attempt journal")
    assert(journal["schema_version"] == "p3-trivs-canonical-replay-attempt-journal/v1" &&
           journal["task_id"] == task_id && journal["route_id"] == ROUTE_ID &&
           journal["candidate"] == candidate &&
           journal["replay_attempt_id"] == bundle["replay_attempt_id"] &&
           journal["dispatch_count"] == 1 && journal["entries"].is_a?(Array) &&
           journal["entries"].length == 3,
           "P3 #{task_id} canonical replay attempt journal header drift")
    previous_hash = "0" * 64
    journal_times = []
    %w[RESERVED_BEFORE_SPAWN STARTED COMPLETED_PASS].each_with_index do |state, index|
      entry = exact_mapping(journal["entries"].fetch(index), %w[
        seq state at_utc raw_manifest_sha256 argv_sha256 timeout_seconds outcome
        prev_entry_sha256 entry_sha256
      ], "P3 #{task_id} replay journal entry #{index + 1}")
      begin
        journal_times << Time.iso8601(entry.fetch("at_utc"))
      rescue ArgumentError
        assert(false, "P3 #{task_id} replay journal timestamp is invalid")
      end
      calculated = Digest::SHA256.hexdigest(
        canonical_json(entry.reject { |key, _value| key == "entry_sha256" })
      )
      expected_outcome = %w[RESERVED RUNNING PASS].fetch(index)
      assert(entry["seq"] == index + 1 && entry["state"] == state &&
             entry["raw_manifest_sha256"] == raw_manifest_identity.fetch("sha256") &&
             entry["argv_sha256"] == Digest::SHA256.hexdigest(canonical_json(expected_argv)) &&
             entry["timeout_seconds"] == CANONICAL_REPLAY_TIMEOUT_SECONDS &&
             entry["outcome"] == expected_outcome && entry["prev_entry_sha256"] == previous_hash &&
             entry["entry_sha256"] == calculated,
             "P3 #{task_id} replay journal entry #{index + 1} drift")
      previous_hash = calculated
    end
    assert(journal["final_entry_sha256"] == previous_hash &&
           journal_times == journal_times.sort && journal_times.first <= replay_started &&
           journal_times[1] == replay_started && journal_times.last == replay_finished,
           "P3 #{task_id} replay journal does not prove one pre-spawn reservation and completion")

    probe_streams = exact_mapping(
      bundle["network_probe_streams"], CANONICAL_REPLAY_NETWORK_PROBES,
      "P3 #{task_id} replay network probe streams"
    )
    probe_stream_identities = CANONICAL_REPLAY_NETWORK_PROBES.map do |probe|
      stream_identity, stream_bytes = validate_raw_stream!(
        probe_streams.fetch(probe), evidence_root, "replay/raw",
        "P3 #{task_id} replay network probe #{probe}"
      )
      observation = exact_mapping(parse_json!(stream_bytes, "P3 replay network probe #{probe}"), %w[
        schema_version task_id route_id candidate replay_attempt_id probe argv
        exit_status stdout stderr verdict
      ], "P3 #{task_id} replay network probe #{probe}")
      expected_probe_argv = [
        sandbox.fetch("path"), "-p", READ_ONLY_REPLAY_SANDBOX_PROFILE,
        runtime.fetch("path"), NETWORK_PROBE_SCRIPT, "--probe", probe
      ]
      assert(observation["schema_version"] == "p3-trivs-canonical-replay-network-probe/v1" &&
             observation["task_id"] == task_id && observation["route_id"] == ROUTE_ID &&
             observation["candidate"] == candidate &&
             observation["replay_attempt_id"] == bundle["replay_attempt_id"] &&
             observation["probe"] == probe && observation["argv"] == expected_probe_argv &&
             observation["exit_status"] == 77 && observation["stdout"] == "" &&
             observation["stderr"] == "NETWORK_DENIED_BY_OS_SANDBOX:#{probe}\n" &&
             observation["verdict"] == "DENIED_BY_OS_SANDBOX",
             "P3 #{task_id} replay network probe #{probe} drift")
      stream_identity
    end

    mutation_streams = exact_mapping(
      bundle["mutation_streams"], CANONICAL_REPLAY_MUTATIONS,
      "P3 #{task_id} replay mutation streams"
    )
    mutation_stream_identities = CANONICAL_REPLAY_MUTATIONS.map do |reason|
      stream_identity, stream_bytes = validate_raw_stream!(
        mutation_streams.fetch(reason), evidence_root, "replay/raw",
        "P3 #{task_id} replay mutation #{reason}"
      )
      observation = exact_mapping(parse_json!(stream_bytes, "P3 replay mutation #{reason}"), %w[
        schema_version task_id route_id candidate replay_attempt_id reason_code
        mutant_manifest_sha256 argv exit_status stdout stderr verdict
      ], "P3 #{task_id} replay mutation #{reason}")
      expected_mutation_argv = [*expected_argv, "--self-test-mutation", reason]
      expected_mutation_stdout = JSON.generate({
        "schema_version" => "p3-trivs-evidence-first-derived-replay-result/v1",
        "task_id" => task_id, "candidate" => candidate,
        "verdict" => "NON_PASS", "reason_code" => reason
      }) + "\n"
      assert(observation["schema_version"] == "p3-trivs-canonical-replay-mutation/v1" &&
             observation["task_id"] == task_id && observation["route_id"] == ROUTE_ID &&
             observation["candidate"] == candidate &&
             observation["replay_attempt_id"] == bundle["replay_attempt_id"] &&
             observation["reason_code"] == reason &&
             observation["mutant_manifest_sha256"].is_a?(String) &&
             observation["mutant_manifest_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
             observation["argv"] == expected_mutation_argv && observation["exit_status"] == 78 &&
             observation["stdout"] == expected_mutation_stdout && observation["stderr"] == "" &&
             observation["verdict"] == "NON_PASS",
             "P3 #{task_id} replay mutation #{reason} drift")
      stream_identity
    end
    assert(bundle["schema_version"] == CANONICAL_REPLAY_BUNDLE_SCHEMA &&
           bundle["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_CANONICAL_REPLAY_RAW_BUNDLE" &&
           bundle["task_id"] == task_id && bundle["route_id"] == ROUTE_ID &&
           bundle["candidate"] == candidate && bundle["raw_evidence_manifest"] == raw_manifest_identity &&
           runtime["path"] == NODE22_RUNTIME_PATH && replayer == expected_replayer &&
           bundle["canonical_commit"] == candidate.fetch("commit") &&
           bundle["canonical_tree"] == candidate.fetch("tree") &&
           bundle["candidate_owned_paths"] == immutable_paths &&
           bundle["candidate_owned_paths_byte_equal"] == true && bundle["argv"] == expected_argv &&
           bundle["cwd"] == root.to_s && bundle["environment"] == expected_environment &&
           bundle["sandbox_profile"] == READ_ONLY_REPLAY_SANDBOX_PROFILE &&
           bundle["replay_attempt_id"].is_a?(String) &&
           bundle["replay_attempt_id"].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/) &&
           bundle["replay_attempt_ordinal"] == 1 && bundle["dispatch_count"] == 1 &&
           bundle["attempt_consumed"] == true && bundle["rerun_allowed"] == false &&
           bundle["timeout_seconds"] == CANONICAL_REPLAY_TIMEOUT_SECONDS &&
           bundle["timed_out"] == false && replay_finished >= replay_started &&
           (replay_finished - replay_started) <= CANONICAL_REPLAY_TIMEOUT_SECONDS &&
           bundle["attempt_journal"] == journal_identity &&
           bundle["network_probe_streams"] ==
             CANONICAL_REPLAY_NETWORK_PROBES.zip(probe_stream_identities).to_h &&
           bundle["mutation_streams"] ==
             CANONICAL_REPLAY_MUTATIONS.zip(mutation_stream_identities).to_h &&
           bundle["network_probe_verdicts"] == expected_probe_verdicts &&
           bundle["mutation_verdicts"] == expected_mutation_verdicts &&
           bundle["stdout"] == stdout_identity && bundle["stderr"] == stderr_identity &&
           bundle["exit_status"] == 0 && bundle["derived_metrics"] == expected_metrics &&
           stderr_bytes.empty?,
           "P3 #{task_id} canonical replay raw bundle drift")
    replay_output = parse_json!(stdout_bytes, "P3 #{task_id} canonical replay stdout")
    assert(replay_output == {
      "schema_version" => "p3-trivs-evidence-first-derived-replay-result/v1",
      "task_id" => task_id, "candidate" => candidate,
      "verdict" => "PASS_DERIVED_FROM_CLOSED_RAW_EVIDENCE",
      "derived_metrics" => expected_metrics
    }, "P3 #{task_id} canonical replay stdout is not the exact derived result")
    replay_raw_root = Pathname.new(evidence_root).join("replay/raw").to_s
    actual_replay_raw_files = []
    Find.find(replay_raw_root) do |entry|
      next if entry == replay_raw_root

      stat = File.lstat(entry)
      assert(!stat.symlink?, "P3 #{task_id} canonical replay raw root contains a symlink")
      if stat.file?
        actual_replay_raw_files << entry
      else
        assert(stat.directory?, "P3 #{task_id} canonical replay raw root contains a non-file object")
      end
    end
    assert(actual_replay_raw_files.sort ==
             [stdout_identity, stderr_identity, journal_identity,
              *probe_stream_identities, *mutation_stream_identities]
               .map { |stream| stream.fetch("path") }.uniq.sort,
           "P3 #{task_id} canonical replay raw inventory differs from disk")
    [bundle_identity, bundle]
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "P3 #{task_id} canonical replay raw Evidence unavailable: #{e.class}"
  end

  def common_candidate_receipt?(record, schema, record_type, task_id, candidate)
    config = task_configuration(task_id)
    record["schema_version"] == schema && record["record_type"] == record_type &&
      record["task_id"] == task_id && record["route_id"] == ROUTE_ID &&
      record["stage_id"] == config["stage_id"] && record["candidate"] == candidate
  end

  def f2_gate_metrics
    {
      "candidate_first_detached_clean_verifier" => true,
      "all_processes_exact_offline" => true,
      "os_deny_network" => true,
      "closed_dependency_custody" => true,
      "jdk_major" => 17,
      "maven_version" => "3.9.6",
      "clean_build_count" => 2,
      "source_to_class_replay" => true,
      "helper_binary_byte_equal" => true,
      "exact_mysql_and_oci_custody" => true,
      "seven_kill_points_pass" => KILL_POINTS,
      "covered_finding_ids" => TERMINAL_FINDING_IDS,
      "false_accepts" => 0,
      "open_p0" => 0,
      "open_p1" => 0,
      "review_verdicts" => {
        "cto" => "PASS", "security" => "PASS", "quality_evaluation" => "PASS"
      },
      "product_source_mutation" => false,
      "delivery_progress_credit" => 0,
      "strict_exit_progress_credit" => 0
    }
  end

  def product_gate_metrics
    {
      "non_empty_testable_product_source_diff" => true,
      "actual_agent_ingress" => true,
      "generic_tool_execution_bypassed" => true,
      "host_derived_authority" => true,
      "immutable_authorization_anchor" => true,
      "production_spring_transaction_service_store_real_mysql" => true,
      "startup_global_recovery" => true,
      "terminal_monotonic_compare_and_set" => true,
      "pinned_local_oci_hostile_context" => true,
      "same_frozen_candidate" => true,
      "seven_kill_points_pass" => KILL_POINTS,
      "covered_finding_ids" => TERMINAL_FINDING_IDS,
      "false_accepts" => 0,
      "open_p0" => 0,
      "open_p1" => 0,
      "new_p0_p1_regressions" => 0,
      "review_verdicts" => {
        "cto" => "PASS", "security" => "PASS", "quality_evaluation" => "PASS"
      },
      "strict_items" => STRICT_ITEMS
    }
  end

  def validate_pass_result!(root, truth, task_id, result)
    label = task_id == F2_TASK_ID ? "P3 F2 accepted result" : "P3 P2 accepted result"
    result = exact_mapping(result, %w[
      task_id status candidate_commit candidate_tree activation_parent integrated
      task_contract task_authority candidate_manifest raw_evidence_manifest independent_reviews
      task_gate_receipt integration_receipt canonical_replay_bundle canonical_replay_receipt
      strict_gate_evidence compatibility_gate_evidence
    ], label)
    assert(result["task_id"] == task_id &&
           result["status"] == "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS" &&
           result["integrated"] == true,
           "#{label} lifecycle drift")
    candidate = {
      "commit" => result["candidate_commit"], "tree" => result["candidate_tree"]
    }
    validate_commit_tree!(root, candidate["commit"], candidate["tree"], "#{label} candidate",
                          integrated: true)
    contract_identity, authority_identity, contract, =
      validate_completed_task_identity!(root, truth, task_id, result, label)
    activation_parent = exact_mapping(result["activation_parent"], %w[commit tree],
                                      "#{label} activation parent")
    assert(contract["activation_parent"] == activation_parent,
           "#{label} activation-parent drift")
    validate_commit_tree!(root, activation_parent["commit"], activation_parent["tree"],
                          "#{label} activation parent", integrated: true)
    paths = validate_candidate_diff!(
      root, activation_parent["commit"], candidate["commit"], contract.fetch("write_allowlist"), task_id
    )
    immutable_candidate_paths = paths.select do |path|
      task_id == F2_TASK_ID ?
        path.start_with?("evaluation-harness/harness/p3-trivs-candidate-bound-acceptance-v1/",
                         "evaluation-harness/replay/p3-trivs-candidate-bound-acceptance-v1/") :
        path.start_with?("backend-spring/")
    end
    assert(!immutable_candidate_paths.empty?, "#{label} lacks immutable candidate-owned implementation paths")
    drift = git!(
      root, "diff", "--name-only", "-z", candidate.fetch("commit"), "HEAD", "--",
      *immutable_candidate_paths
    ).first.split("\0").reject(&:empty?)
    assert(drift.empty?, "#{label} candidate-owned bytes drifted after the accepted candidate")

    manifest_identity, manifest = result_artifact!(
      root, task_id, "candidate_manifest", result["candidate_manifest"], "#{label} candidate manifest"
    )
    manifest = exact_mapping(manifest, %w[
      schema_version record_type task_id route_id stage_id candidate status activation_parent
      task_contract task_authority changed_paths product_source_diff_non_empty
    ], "#{label} candidate manifest")
    assert(common_candidate_receipt?(
             manifest, CANDIDATE_MANIFEST_SCHEMA,
             "P3_TRIVS_EVIDENCE_FIRST_CANDIDATE_MANIFEST", task_id, candidate
           ) && manifest["status"] == "FROZEN_BEFORE_FORMAL_DISPATCH" &&
           manifest["activation_parent"] == activation_parent &&
           manifest["task_contract"] == contract_identity &&
           manifest["task_authority"] == authority_identity &&
           manifest["changed_paths"] == paths &&
           manifest["product_source_diff_non_empty"] == (task_id == P2_TASK_ID),
           "#{label} candidate manifest drift")

    raw_manifest_identity, _raw_manifest, raw_records = validate_raw_evidence!(
      root, task_id, result["raw_evidence_manifest"], candidate, activation_parent, paths
    )

    review_identities = exact_mapping(
      result["independent_reviews"], REVIEW_KEYS, "#{label} independent reviews"
    )
    REVIEW_KEYS.zip(REVIEW_ROLES).each do |key, role|
      identity, review = result_artifact!(
        root, task_id, key, review_identities[key], "#{label} #{key} review"
      )
      review = exact_mapping(review, %w[
        schema_version record_type task_id route_id stage_id candidate reviewer_role verdict
        raw_evidence_manifest covered_finding_ids open_p0 open_p1 new_p0_p1_regressions
      ], "#{label} #{key} review")
      assert(identity == review_identities[key] &&
             common_candidate_receipt?(
               review, REVIEW_SCHEMA, "P3_TRIVS_EVIDENCE_FIRST_INDEPENDENT_REVIEW", task_id, candidate
             ) && review["reviewer_role"] == role && review["verdict"] == "PASS" &&
             review["raw_evidence_manifest"] == raw_manifest_identity &&
             review["covered_finding_ids"] == TERMINAL_FINDING_IDS &&
             review["open_p0"] == 0 && review["open_p1"] == 0 &&
             review["new_p0_p1_regressions"] == 0,
             "#{label} #{role} review drift")
    end

    gate_identity, gate = result_artifact!(
      root, task_id, "task_gate_receipt", result["task_gate_receipt"], "#{label} Task Gate receipt"
    )
    gate = exact_mapping(gate, %w[
      schema_version record_type task_id route_id stage_id candidate verdict candidate_manifest
      raw_evidence_manifest independent_reviews metrics
    ], "#{label} Task Gate receipt")
    expected_metrics = task_id == F2_TASK_ID ? f2_gate_metrics : product_gate_metrics
    assert(common_candidate_receipt?(
             gate, TASK_GATE_SCHEMA, "P3_TRIVS_EVIDENCE_FIRST_TASK_GATE_RECEIPT", task_id, candidate
           ) && gate["verdict"] == "PASS" && gate["candidate_manifest"] == manifest_identity &&
           gate["raw_evidence_manifest"] == raw_manifest_identity &&
           gate["independent_reviews"] == review_identities && gate["metrics"] == expected_metrics,
           "#{label} Task Gate receipt drift")

    integration_identity, integration = result_artifact!(
      root, task_id, "integration_receipt", result["integration_receipt"],
      "#{label} integration receipt"
    )
    integration = exact_mapping(integration, %w[
      schema_version record_type task_id route_id stage_id candidate verdict candidate_integrated
      raw_evidence_manifest task_gate_receipt canonical_commit canonical_tree
    ], "#{label} integration receipt")
    assert(common_candidate_receipt?(
             integration, INTEGRATION_SCHEMA,
             "P3_TRIVS_EVIDENCE_FIRST_INTEGRATION_RECEIPT", task_id, candidate
           ) && integration["verdict"] == "PASS" &&
           integration["candidate_integrated"] == true &&
           integration["raw_evidence_manifest"] == raw_manifest_identity &&
           integration["task_gate_receipt"] == gate_identity &&
           integration["canonical_commit"] == candidate["commit"] &&
           integration["canonical_tree"] == candidate["tree"],
           "#{label} integration receipt drift")

    replay_bundle_identity, replay_bundle = validate_canonical_replay_bundle!(
      root, task_id, result["canonical_replay_bundle"], candidate,
      raw_manifest_identity, raw_records, immutable_candidate_paths
    )

    replay_identity, replay = result_artifact!(
      root, task_id, "canonical_replay_receipt", result["canonical_replay_receipt"],
      "#{label} canonical replay receipt"
    )
    replay = exact_mapping(replay, %w[
      schema_version record_type task_id route_id stage_id candidate verdict raw_evidence_manifest
      canonical_replay_bundle integration_receipt task_gate_receipt immutable_input_replay
      network_mode replay_attempt_id replay_attempt_ordinal dispatch_count attempt_consumed
      rerun_allowed timeout_seconds timed_out attempt_journal metrics
    ], "#{label} canonical replay receipt")
    assert(common_candidate_receipt?(
             replay, CANONICAL_REPLAY_SCHEMA,
             "P3_TRIVS_EVIDENCE_FIRST_CANONICAL_REPLAY_RECEIPT", task_id, candidate
           ) && replay["verdict"] == "PASS" &&
           replay["raw_evidence_manifest"] == raw_manifest_identity &&
           replay["canonical_replay_bundle"] == replay_bundle_identity &&
           replay["integration_receipt"] == integration_identity &&
           replay["task_gate_receipt"] == gate_identity &&
           replay["immutable_input_replay"] == true &&
           replay["network_mode"] == "OS_DENY_NETWORK" &&
           replay["replay_attempt_id"] == replay_bundle["replay_attempt_id"] &&
           replay["replay_attempt_ordinal"] == 1 && replay["dispatch_count"] == 1 &&
           replay["attempt_consumed"] == true && replay["rerun_allowed"] == false &&
           replay["timeout_seconds"] == CANONICAL_REPLAY_TIMEOUT_SECONDS &&
           replay["timed_out"] == false &&
           replay["attempt_journal"] == replay_bundle["attempt_journal"] &&
           replay["metrics"] == expected_metrics,
           "#{label} canonical replay receipt drift")

    if task_id == F2_TASK_ID
      assert(result["strict_gate_evidence"].nil? && result["compatibility_gate_evidence"].nil?,
             "F2 acceptance may not self-accept the P3 strict Exit Gate")
    else
      strict = exact_mapping(result["strict_gate_evidence"], STRICT_ITEMS,
                             "P3 Product strict Gate Evidence")
      assert(strict.values.all? { |identity| identity == replay_identity },
             "P3 Product strict Gate items must bind the one accepted canonical replay receipt")
      compatibility_identity = identity_mapping(
        result["compatibility_gate_evidence"], "P3 Product compatibility Gate Evidence"
      )
      assert(compatibility_identity == replay_identity,
             "P3 Product compatibility Gate must bind the same canonical replay receipt")
    end
    result
  end

  def validate_terminal_result!(root, truth, task_id, result)
    label = task_id == F2_TASK_ID ? "P3 F2 terminal result" : "P3 P2 terminal result"
    result = exact_mapping(result, %w[
      task_id status candidate_created candidate_commit candidate_tree candidate_integrated
      task_contract task_authority terminal_receipt
    ], label)
    assert(result["task_id"] == task_id && result["status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           [true, false].include?(result["candidate_created"]) &&
           result["candidate_integrated"] == false,
           "#{label} lifecycle drift")
    contract_identity, authority_identity, contract, =
      validate_completed_task_identity!(root, truth, task_id, result, label)
    candidate = if result["candidate_created"]
                  candidate_identity = {
                    "commit" => result["candidate_commit"], "tree" => result["candidate_tree"]
                  }
                  validate_commit_tree!(root, candidate_identity["commit"], candidate_identity["tree"],
                                        "#{label} candidate", integrated: false)
                  activation_parent = contract.fetch("activation_parent").fetch("commit")
                  _out, _err, descendant = git!(
                    root, "merge-base", "--is-ancestor", activation_parent,
                    candidate_identity.fetch("commit"), allow_failure: true
                  )
                  _out, _err, integrated = git!(
                    root, "merge-base", "--is-ancestor", candidate_identity.fetch("commit"), "HEAD",
                    allow_failure: true
                  )
                  assert(descendant.success? && !integrated.success?,
                         "#{label} candidate is not a non-integrated descendant of its activation parent")
                  validate_candidate_diff!(
                    root, activation_parent, candidate_identity.fetch("commit"),
                    contract.fetch("write_allowlist"), task_id, require_delivery: false
                  )
                  candidate_identity
                else
                  assert(result["candidate_commit"].nil? && result["candidate_tree"].nil?,
                         "#{label} invented a candidate identity")
                  nil
                end
    receipt_identity, receipt = result_artifact!(
      root, task_id, "terminal_receipt", result["terminal_receipt"], "#{label} receipt"
    )
    receipt = exact_mapping(receipt, %w[
      schema_version record_type task_id route_id stage_id verdict task_lifecycle route_lifecycle
      candidate_created candidate candidate_integrated task_contract task_authority
      p3_delivery_progress_percent p3_strict_exit_progress_percent long_term_goal_status
      codex_goal_action_taken no_automatic_successor_clause_present next_step_user_action_required
    ], "#{label} receipt")
    assert(receipt["schema_version"] == TERMINAL_SCHEMA &&
           receipt["record_type"] == "P3_TRIVS_EVIDENCE_FIRST_TASK_ROUTE_TERMINAL_RECEIPT" &&
           receipt["task_id"] == task_id && receipt["route_id"] == ROUTE_ID &&
           receipt["stage_id"] == task_configuration(task_id)["stage_id"] &&
           receipt["verdict"] == "NON_PASS" &&
           receipt["task_lifecycle"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           receipt["route_lifecycle"] == "ROUTE_TERMINAL_NON_PASS" &&
           receipt["candidate_created"] == result["candidate_created"] &&
           receipt["candidate"] == candidate && receipt["candidate_integrated"] == false &&
           receipt["task_contract"] == contract_identity &&
           receipt["task_authority"] == authority_identity &&
           receipt["p3_delivery_progress_percent"] == 25 &&
           receipt["p3_strict_exit_progress_percent"] == 0 &&
           receipt["long_term_goal_status"] == "ACTIVE" &&
           receipt["codex_goal_action_taken"] == "NONE_KEEP_ACTIVE" &&
           receipt["no_automatic_successor_clause_present"] == true &&
           receipt["next_step_user_action_required"] == true,
           "#{label} receipt drift")
    [result, receipt_identity]
  end

  def validate_repository_and_dependencies!(root, route)
    validate_commit_tree!(
      root, CANONICAL_START.fetch("commit"), CANONICAL_START.fetch("tree"),
      "P3 evidence-first canonical start", integrated: true
    )
    _out, _err, rejected = git!(
      root, "merge-base", "--is-ancestor", "597ee9dcf714bcd612c893b86753fa2881a06963", "HEAD",
      allow_failure: true
    )
    assert(!rejected.success?, "rejected TRIVS Candidate 1 reached canonical history")
    assert(route["accepted_dependencies"] == ACCEPTED_DEPENDENCIES,
           "P3 evidence-first accepted dependency projection drift")
    [P3_001_DEPENDENCY, DECLARATIVE_FOUNDATION_DEPENDENCY].each do |dependency|
      validate_commit_tree!(root, dependency.fetch("commit"), dependency.fetch("tree"),
                            "accepted dependency #{dependency.fetch('task_id')}", integrated: false)
    end
    p3_001 = parse_json!(
      read_identity!(root, P3_001_DEPENDENCY.fetch("task_gate_receipt"),
                     "accepted P3-001 Task Gate receipt"),
      "accepted P3-001 Task Gate receipt"
    )
    dtk_gate = parse_json!(
      read_identity!(root, DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("task_gate_receipt"),
                     "accepted declarative Foundation Task Gate receipt"),
      "accepted declarative Foundation Task Gate receipt"
    )
    dtk_replay = parse_json!(
      read_identity!(root, DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("canonical_verification_receipt"),
                     "accepted declarative Foundation canonical verification receipt"),
      "accepted declarative Foundation canonical verification receipt"
    )
    assert(p3_001["schema_version"] == "p3-task-gate-integration-receipt/v1" &&
           p3_001["task_id"] == P3_001_DEPENDENCY.fetch("task_id") &&
           p3_001["candidate"] == P3_001_DEPENDENCY.slice("commit", "tree") &&
           p3_001["task_lifecycle"] == "ACCEPTED_INTEGRATED" &&
           p3_001["long_term_goal_lifecycle"] == "ACTIVE",
           "accepted P3-001 dependency receipt drift")
    assert(dtk_gate["schema_version"] == "p3-task-gate-integration-receipt/v1" &&
           dtk_gate["task_id"] == DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("task_id") &&
           dtk_gate["verdict"] == "ACCEPTED_INTEGRATED" &&
           dtk_gate.dig("accepted_candidate", "commit") ==
             DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("commit") &&
           dtk_gate.dig("accepted_candidate", "tree") ==
             DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("tree") &&
           dtk_gate.dig("accepted_milestone", "id") ==
             "DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION" &&
           dtk_gate.dig("accepted_milestone", "status") == "ACCEPTED_INTEGRATED" &&
           dtk_gate.dig("canonical_verification", "sha256") ==
             DECLARATIVE_FOUNDATION_DEPENDENCY.dig("canonical_verification_receipt", "sha256") &&
           dtk_gate["long_term_goal_status"] == "ACTIVE" &&
           dtk_gate["codex_goal_action"] == "NONE_KEEP_ACTIVE",
           "accepted declarative Foundation Task Gate receipt drift")
    assert(dtk_replay["schema_version"] == "p3-dtk-f1-canonical-verification-receipt/v1" &&
           dtk_replay["task_id"] == DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("task_id") &&
           dtk_replay["verdict"] == "PASS" &&
           dtk_replay.dig("accepted_candidate", "commit") ==
             DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("commit") &&
           dtk_replay.dig("accepted_candidate", "tree") ==
             DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("tree") &&
           dtk_replay.dig("canonical", "commit") ==
             DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("commit") &&
           dtk_replay.dig("canonical", "tree") ==
             DECLARATIVE_FOUNDATION_DEPENDENCY.fetch("tree") &&
           dtk_replay["long_term_goal_status"] == "ACTIVE" &&
           dtk_replay["codex_goal_action"] == "NONE_KEEP_ACTIVE",
           "accepted declarative Foundation canonical replay receipt drift")
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    route = mapping(truth["current_phase_route"], "P3 evidence-first current Route")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID,
           "P3 evidence-first Route schema or identity drift")
    validate_docker_grammar_self_test!
    lifecycle = route["lifecycle_stage"]
    profile = LIFECYCLE[lifecycle]
    assert(profile, "P3 evidence-first lifecycle is not closed-schema: #{lifecycle.inspect}")
    decision = validate_decision!(root)
    validate_repository_and_dependencies!(root, route)

    decision_ref = mapping(route["founder_route_decision"], "P3 evidence-first Route decision ref")
    assert(route["status"] == profile.fetch("route_status") && route["execution_status"] == lifecycle &&
           route["scheduling_status"] == profile.fetch("schedule") && route["phase"] == "P3" &&
           route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == profile.fetch("founder_required") &&
           route["next_eligible_action"] == profile.fetch("action") &&
           decision_ref.slice("path", "byte_length", "sha256") == DECISION &&
           decision_ref["decision_id"] == DECISION_ID && decision_ref["operation_type"] == OPERATION_TYPE &&
           decision_ref.dig("source_body", "byte_length") == NORMALIZED_BODY["byte_length"] &&
           decision_ref.dig("source_body", "sha256") == NORMALIZED_BODY["sha256"] &&
           decision_ref["source_attachment"] == SOURCE_ATTACHMENT &&
           route["canonical_start"] == CANONICAL_START && route["constitution"] == CONSTITUTION &&
           route["objective_id"] == OBJECTIVE_ID && route["workflow_id"] == WORKFLOW_ID &&
           route["claim_boundary"] == CLAIM_BOUNDARY &&
           route.dig("strict_exit_gate", "gate_id") == STRICT_GATE_ID &&
           route.dig("strict_exit_gate", "required_item_ids") == STRICT_ITEMS &&
           route.dig("strict_exit_gate", "compatibility_aggregate_item_id") == COMPATIBILITY_ITEM &&
           route.dig("strict_exit_gate", "same_frozen_product_candidate_required") == true &&
           route.dig("strict_exit_gate", "canonical_replay_required") == true &&
           route["terminal_finding_ids"] == TERMINAL_FINDING_IDS,
           "P3 evidence-first Route authority, claim or strict Gate drift")

    accounting = mapping(route["cumulative_accounting"], "P3 evidence-first Route accounting")
    assert(accounting["basis"] == "NON_RESETTABLE_CUMULATIVE_P3_FOUNDER_ENVELOPE" &&
           accounting["limits"] == LIMITS && accounting["consumed"] == profile.fetch("consumed") &&
           accounting.fetch("reserved", {}) == profile.fetch("reserved") &&
           accounting["remaining"] == profile.fetch("remaining") && accounting["route_release"] == ROUTE_RELEASE &&
           accounting["reset_or_refund_allowed"] == false,
           "P3 evidence-first Route accounting drift")
    expected_stages = expected_truth_stages(profile)
    assert(route["ordered_stages"] == expected_stages,
           "P3 evidence-first ordered two-stage lifecycle drift")
    foundation = mapping(route["foundation_acceptance"], "P3 Foundation acceptance")
    product = mapping(route["product_acceptance"], "P3 Product acceptance")
    assert(foundation.slice(*decision.fetch("foundation_acceptance").keys) ==
             decision.fetch("foundation_acceptance") &&
           foundation["milestone_id"] == F2_MILESTONE_ID &&
           foundation["all_reviewers_pass_required"] == true &&
           foundation["jdk_major"] == 17 && foundation["maven_version"] == "3.9.6" &&
           foundation["maven_required_arguments"] ==
             %w[--offline --global-settings --settings -Dmaven.repo.local] &&
           foundation["sandbox_profile"] == "(version 1) (allow default) (deny network*)" &&
           foundation["seven_real_kill_points_required"] == KILL_POINTS &&
           foundation["false_accepts_allowed"] == 0 &&
           product["milestone_id"] == PRODUCT_MILESTONE_ID &&
           product["non_empty_testable_product_source_diff_required"] == true &&
           product["actual_agent_ingress_required"] == true &&
           product["generic_tool_execution_bypass_required"] == true &&
           product["host_derived_authority_required"] == true &&
           product["immutable_authorization_anchor_required"] == true &&
           product["production_spring_transaction_service_store_and_real_mysql_required"] == true &&
           product["startup_global_recovery_required"] == true &&
           product["terminal_monotonic_compare_and_set_required"] == true &&
           product["pinned_local_oci_hostile_context_required"] == true &&
           product["accepted_foundation_identity_required"] == true &&
           product["fresh_reviewers"] == REVIEW_ROLES &&
           product["all_reviewers_pass_required"] == true &&
           product["zero_open_p0_p1_required"] == true &&
           product["zero_new_p0_p1_regression_required"] == true &&
           product["canonical_replay_required"] == true &&
           decision.dig("product_acceptance", "same_frozen_product_candidate_required") == true &&
           decision.dig("product_acceptance", "one_canonical_replay_required") == true,
           "P3 evidence-first Foundation or Product acceptance boundary drift")
    FALSE_EXTERNAL_EFFECTS.each do |key|
      assert(route.dig("external_effect_authority", key) == false,
             "P3 evidence-first external effect unexpectedly authorized: #{key}")
    end
    expected_docker = route_docker_scope(lifecycle)
    assert(route.dig("external_effect_authority", "docker_for_active_task") == expected_docker &&
           route.dig("external_effect_authority", "docker_endpoint") ==
             "unix:///Users/lijunpeng/.docker/run/docker.sock" &&
           route.dig("external_effect_authority", "docker_allowed_verbs") == DOCKER_ALLOWED_VERBS &&
           route.dig("external_effect_authority", "mysql_content_id") ==
             "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209" &&
           route.dig("external_effect_authority", "docker_task_created_objects_only") == true &&
           route.dig("external_effect_authority", "sterile_config_closed_environment_required") == true &&
           route.dig("external_effect_authority", "os_network_restriction_required") == true &&
           DOCKER_FALSE_CONTROLS.all? { |key| route.dig("external_effect_authority", key) == false } &&
           route.dig("clean_room", "rejected_candidate_1_checkout_read_compare_copy_execute_decompile_restore_repair_or_reuse_allowed") == false &&
           route.dig("clean_room", "rejected_branch_worktree_bundle_patch_changed_source_tests_helper_rootfs_machine_state_scripts_or_engineering_evidence_read_allowed") == false &&
           route.dig("clean_room", "permitted_terminal_finding_fields") == PERMITTED_FINDING_FIELDS &&
           route.dig("clean_room", "permitted_terminal_metadata") == PERMITTED_TERMINAL_METADATA &&
           route["p4_entry_authorized"] == false && route["long_term_goal_status"] == "ACTIVE",
           "P3 evidence-first Docker, clean-room, P4 or Goal boundary drift")
    %w[candidate_3_allowed second_same_task_repair_allowed third_review_cycle_allowed
       second_foundation_task_allowed third_trivs_product_task_allowed separate_audit_task_allowed
       successor_replacement_normalization_closure_feasibility_remediation_allowed
       v2_or_v3_route_chain_allowed rerun_to_pass_allowed].each do |key|
      assert(route.dig("anti_loop", key) == false, "P3 evidence-first anti-loop projection drift at #{key}")
    end
    assert(route.dig("anti_loop", "governance_progress_credit") == 0,
           "P3 evidence-first governance may not claim progress")

    foundation_result = route["foundation_result"]
    product_result = route["product_result"]
    foundation_terminal = route["foundation_terminal_result"]
    product_terminal = route["product_terminal_result"]
    founder_evidence_identity = DECISION
    case lifecycle
    when "FOUNDATION_ELIGIBLE_NOT_ACTIVATED", "FOUNDATION_TASK_ACTIVE"
      assert([foundation_result, product_result, foundation_terminal, product_terminal].all?(&:nil?),
             "P3 Foundation pre-acceptance lifecycle invented a result")
    when "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE", "PRODUCT_TASK_ACTIVE"
      foundation_result = validate_pass_result!(root, truth, F2_TASK_ID, foundation_result)
      assert(product_result.nil? && foundation_terminal.nil? && product_terminal.nil?,
             "P3 Product pre-result lifecycle invented a Product or terminal result")
    when "FOUNDATION_ROUTE_TERMINAL_NON_PASS"
      assert(foundation_result.nil? && product_result.nil? && product_terminal.nil?,
             "P3 Foundation terminal lifecycle retained an accepted or Product result")
      _terminal, founder_evidence_identity =
        validate_terminal_result!(root, truth, F2_TASK_ID, foundation_terminal)
    when "PRODUCT_ROUTE_TERMINAL_NON_PASS"
      foundation_result = validate_pass_result!(root, truth, F2_TASK_ID, foundation_result)
      assert(product_result.nil? && foundation_terminal.nil?,
             "P3 Product terminal lifecycle invented an accepted Product result")
      _terminal, founder_evidence_identity =
        validate_terminal_result!(root, truth, P2_TASK_ID, product_terminal)
    when "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE"
      foundation_result = validate_pass_result!(root, truth, F2_TASK_ID, foundation_result)
      product_result = validate_pass_result!(root, truth, P2_TASK_ID, product_result)
      assert(foundation_terminal.nil? && product_terminal.nil?,
             "P3 accepted Product lifecycle retained a terminal result")
      founder_evidence_identity = product_result.fetch("canonical_replay_receipt")
    else
      assert(false, "unhandled P3 evidence-first lifecycle result profile")
    end

    envelope = mapping(truth["phase_execution_envelope"], "P3 evidence-first Phase envelope")
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" && envelope["phase"] == "P3" &&
           envelope["status"] == profile.fetch("phase_status") &&
           envelope.dig("authority_basis", "source_route_id") == ROUTE_ID &&
           envelope.dig("authority_basis", "founder_route_decision") == DECISION &&
           envelope["limits"] == LIMITS && envelope["consumed"] == profile.fetch("consumed") &&
           envelope["reserved"] == profile.fetch("reserved") && envelope["remaining"] == profile.fetch("remaining") &&
           envelope["remaining_capacity_usable"] == profile.fetch("remaining_capacity_usable") &&
           envelope["ordered_stages"] == expected_stages &&
           envelope.dig("delivery_progress", "percent") == profile.fetch("delivery") &&
           envelope.dig("delivery_progress", "strict_exit_gate_percent") == profile.fetch("strict") &&
           envelope["governance_progress_credit"] == 0,
           "P3 evidence-first Phase envelope drift")
    assert(truth.dig("claim_boundary", "p3_phase_envelope_status") == envelope["status"],
           "P3 host-authorized claim boundary projection drift (P3 evidence-first envelope binding)")

    control = mapping(truth["founder_escalation_control"], "P3 evidence-first Founder escalation")
    expected_disposition = profile.fetch("founder_required") ?
      "FOUNDER_RESERVED_DECISION_REQUIRED" : "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
    source_event_kinds = {
      "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" => "FOUNDER_P3_EVIDENCE_FIRST_FINAL_CLEAN_ROOM_ROUTE_AUTHORIZED",
      "FOUNDATION_TASK_ACTIVE" => "P3_TRIVS_F2_PHASE_DELEGATED_TASK_ACTIVATED",
      "FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE" => "P3_TRIVS_F2_ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS",
      "PRODUCT_TASK_ACTIVE" => "P3_TRIVS_P2_PHASE_DELEGATED_TASK_ACTIVATED",
      "FOUNDATION_ROUTE_TERMINAL_NON_PASS" => "P3_TRIVS_F2_ROUTE_TERMINAL_NON_PASS",
      "PRODUCT_ROUTE_TERMINAL_NON_PASS" => "P3_TRIVS_P2_ROUTE_TERMINAL_NON_PASS",
      "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE" =>
        "P3_TRIVS_P2_ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS"
    }
    expected_source_status = lifecycle == "FOUNDATION_ELIGIBLE_NOT_ACTIVATED" ?
      "ACCEPTED_INSTALLED_FOUNDATION_ELIGIBLE" : profile.fetch("state")
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == expected_disposition &&
           control["founder_decision_required"] == profile.fetch("founder_required") &&
           control["next_action_owner"] == (profile.fetch("founder_required") ? "HUMAN_FOUNDER" : "MASTER_CEO_AGENT") &&
           control["next_eligible_action"] == profile.fetch("action") &&
           control.dig("source_event", "kind") == source_event_kinds.fetch(lifecycle) &&
           control.dig("source_event", "decision_id") == DECISION_ID &&
           control.dig("source_event", "status") == expected_source_status &&
           control.dig("reserved_trigger", "category") == profile.fetch("founder_trigger") &&
           control.dig("reserved_trigger", "evidence") == founder_evidence_identity &&
           control.dig("resolved_strategy_decision", "category") == %w[
             MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
             MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
           ] && control.dig("resolved_strategy_decision", "decision_id") == DECISION_ID &&
           control.dig("resolved_strategy_decision", "path") == DECISION["path"] &&
           control.dig("resolved_strategy_decision", "byte_length") == DECISION["byte_length"] &&
           control.dig("resolved_strategy_decision", "sha256") == DECISION["sha256"] &&
           control["phase_gate_status"] ==
             (lifecycle == "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE" ?
              "ELIGIBLE_AWAITING_FOUNDER_DECISION" : "INCOMPLETE"),
           "P3 evidence-first Founder interruption projection drift")
    delegation = mapping(truth["phase_delegation"], "P3 evidence-first Phase delegation")
    assert(delegation["decision_source"] == DECISION_ID &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation.dig("anti_loop", "second_trivs_foundation_task_allowed") == false &&
           delegation.dig("anti_loop", "third_trivs_product_task_allowed") == false &&
           delegation.dig("anti_loop", "successor_or_replacement_allowed") == false &&
           delegation.dig("anti_loop", "candidate_3_allowed") == false &&
           delegation.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           delegation.dig("anti_loop", "third_review_cycle_allowed") == false &&
           delegation.dig("anti_loop", "rerun_to_pass_allowed") == false,
           "P3 evidence-first delegation or anti-loop drift")
    boundary = mapping(truth["phase_boundary"], "P3 evidence-first Phase boundary")
    allowed_kind = profile.fetch("task_creation_allowed") ?
      [profile.fetch("selected") == F2_TASK_ID ? "BENCHMARK_AND_ACCEPTANCE_FOUNDATION_NON_PRODUCT" :
       "PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL"] : []
    assert(boundary["phase"] == "P3" && boundary["phase_execution_status"] == profile.fetch("phase_status") &&
           boundary["task_creation_allowed"] == profile.fetch("task_creation_allowed") &&
           boundary["allowed_task_kinds"] == allowed_kind &&
           boundary["founder_decision_required"] == profile.fetch("founder_required") &&
           boundary["next_eligible_action"] == profile.fetch("action") &&
           boundary.dig("default_external_effects", "docker") == !profile.fetch("active_task").nil? &&
           FALSE_EXTERNAL_EFFECTS.reject { |key| key == "irreversible_asset_removal" }.all? {
             |key| boundary.dig("default_external_effects", key) == false
           }, "P3 evidence-first Phase boundary or external-effect drift")
    claim = mapping(truth["phase_execution_claim"], "P3 evidence-first Phase execution claim")
    assert(claim["current_route_claim"] == ROUTE_ID &&
           claim["current_task_claim"] == (profile.fetch("active_task") || "NONE") &&
           claim["task_creation_allowed"] == profile.fetch("task_creation_allowed") &&
           claim["remaining_capacity_usable"] == profile.fetch("remaining_capacity_usable") &&
           claim["candidate_integration_allowed"] == false && claim["next_eligible_action"] == profile.fetch("action"),
           "P3 evidence-first execution-claim drift")
    validate_active_work!(root, truth, profile)

    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"), "P3 strict Gate")
    current_gate = mapping(p3["current_exit_gate"], "P3 evidence-first current strict Gate")
    compatibility = mapping(
      p3.dig("required_items", COMPATIBILITY_ITEM), "P3 compatibility aggregate Gate item"
    )
    assert(current_gate["gate_id"] == STRICT_GATE_ID &&
           p3["required_item_ids"] == [COMPATIBILITY_ITEM] &&
           current_gate["authority"] == DECISION.merge("decision_id" => DECISION_ID) &&
           current_gate["required_item_ids"] == STRICT_ITEMS && current_gate["required_items"].keys == STRICT_ITEMS &&
           current_gate["same_frozen_candidate_required"] == true && current_gate["canonical_replay_required"] == true,
           "P3 evidence-first strict Gate shape drift")
    if profile.fetch("strict") == 100
      candidates = STRICT_ITEMS.map do |item|
        record = mapping(current_gate.dig("required_items", item), "P3 accepted Gate item #{item}")
        assert(record["status"] == "ACCEPTED" &&
               record["candidate_commit"] == product_result.fetch("candidate_commit") &&
               record["candidate_tree"] == product_result.fetch("candidate_tree") &&
               record["evidence"] == product_result.dig("strict_gate_evidence", item),
               "P3 phase-gate state lacks accepted Evidence for #{item}")
        [record["candidate_commit"], record["candidate_tree"]]
      end
      assert(candidates.uniq.length == 1 && current_gate.dig("compatibility_projection", "status") == "ACCEPTED" &&
             compatibility["status"] == "ACCEPTED" &&
             compatibility["task_id"] == P2_TASK_ID &&
             compatibility["acceptance_commit"] == product_result.fetch("candidate_commit") &&
             compatibility["acceptance_tree"] == product_result.fetch("candidate_tree") &&
             compatibility["gate_evidence"] == product_result.fetch("compatibility_gate_evidence") &&
             p3.dig("founder_phase_gate", "status") == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "P3 same-candidate, compatibility or Founder Gate drift")
    else
      assert(STRICT_ITEMS.all? { |item|
               record = current_gate.dig("required_items", item)
               record["status"] == "MISSING" && record["candidate_commit"].nil? &&
                 record["candidate_tree"].nil? && record["evidence"].nil?
             } &&
             current_gate.dig("compatibility_projection", "status") == "MISSING" &&
             compatibility["status"] == "MISSING" &&
             compatibility["task_id"].nil? && compatibility["acceptance_commit"].nil? &&
             compatibility["acceptance_tree"].nil? &&
             compatibility["gate_evidence"] == {
               "receipt_type" => nil, "path" => nil, "byte_length" => nil, "sha256" => nil
             } &&
             p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
             "P3 strict Gate false acceptance before final Product replay")
    end
    assert(truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "phase_execution_status") == profile.fetch("phase_status") &&
           truth.dig("project", "current_route_execution_status") == profile.fetch("state") &&
           truth.dig("project", "p4_entry_status") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_task_authority") == (profile.fetch("active_task") || "NONE") &&
           truth.dig("goal", "current_strategic_decision", "decision_id") == DECISION_ID &&
           truth.dig("claim_boundary", "current_phase_route") == ROUTE_ID &&
           truth.dig("claim_boundary", "p3_phase_envelope_status") == profile.fetch("phase_status") &&
           truth.dig("claim_boundary", "p3_exit_gate_progress_percent") == profile.fetch("strict") &&
           truth.dig("claim_boundary", "p3_delivery_progress_percent") == profile.fetch("delivery") &&
           truth.dig("claim_boundary", "p3_trivs_evidence_first_route_decision_sha256") == DECISION["sha256"] &&
           truth.dig("claim_boundary", "p3_trivs_evidence_first_route_source_body_sha256") ==
             NORMALIZED_BODY["sha256"],
           "P3 evidence-first project, P4, Goal or claim projection drift")
    profile.fetch("state")
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
          "P3 evidence-first Route invalid: #{e.message}"
  end
end

class P3MinimumTrustTransactionalOciFinalProductRouteValidationError < StandardError; end

module P3MinimumTrustTransactionalOciFinalProductRouteValidation
  module_function

  class DuplicateJsonKeyError < StandardError; end
  class ClosedJsonHash < Hash
    def []=(key, value)
      raise DuplicateJsonKeyError, key if key?(key)
      super
    end
  end

  ROUTE_SCHEMA = "p3-minimum-trust-transactional-oci-final-product-route/v1"
  ROUTE_ID = "P3_MINIMUM_TRUST_TRANSACTIONAL_OCI_FINAL_PRODUCT_ROUTE_V1"
  DECISION_ID =
    "AUTHORIZE_P3_MINIMUM_TRUST_TRANSACTIONAL_OCI_FINAL_PRODUCT_ROUTE_AFTER_F2_TERMINAL_V2"
  OPERATION_TYPE =
    "P3_MINIMUM_TRUST_TRANSACTIONAL_OCI_FINAL_PRODUCT_ROUTE_AFTER_F2_TERMINAL"
  DECISION = {
    "path" =>
      "docs/aios/decisions/P3_MINIMUM_TRUST_TRANSACTIONAL_OCI_FINAL_PRODUCT_ROUTE_AFTER_F2_TERMINAL_V2.json",
    "byte_length" => 23_363,
    "sha256" => "e1ce4b6080c4ad193fd81511e44f72a7f1bceb4edfae4d1e5425ca8b42a6b217"
  }.freeze
  CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "3.6",
    "byte_length" => 48_904,
    "sha256" => "aeacef88eae184f9fe03e74df4311d62bb8b6710299b9e4bd6cc5a566c9f9bbf"
  }.freeze
  DELEGATION_POLICY = {
    "path" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
    "version" => "1.8",
    "sha256" => "12126e9617011b6395f187939c9a1d7860d84bd3832c1b1b67357fb017e1ee29"
  }.freeze
  DIRECT_AUTHORIZATION = {
    "path" =>
      "/Users/lijunpeng/.codex/attachments/2c6e6959-80d5-4458-9d4a-0672c534b74f/pasted-text.txt",
    "byte_length" => 29_571,
    "sha256" => "cfca3b136f89ba2673203d594135404620c65a94dcfbadc771540f8b266025c2"
  }.freeze
  SUPERSEDED_V1 = {
    "path" =>
      "/Users/lijunpeng/.codex/attachments/47ac67fd-4e42-4feb-b929-496c10bc4113/pasted-text.txt",
    "byte_length" => 12_599,
    "sha256" => "bb8ebc0dfdeee22e760846185400740ede5de305c294d69024223f854607c939"
  }.freeze
  CANONICAL_START = {
    "commit" => "24a8cae969c36aafb01933466a5742b052a7e2e5",
    "tree" => "b95115968e5ca5ed2381bfa74168429319308a01",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 2_017_292,
      "sha256" => "85b16bd32ad2841e5453676e56b8e98bd7a221ab0d5fe98b0c337caaea10dc6a"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "3.5",
      "byte_length" => 38_846,
      "sha256" => "1faee62ecdc49d273042048f52c429b36f87c48b512b3161fd2e297263d70408"
    }
  }.freeze
  TRIVS_TERMINAL_RECEIPT = {
    "path" =>
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-read-only-invocation-vertical-slice-20260823/task-product/terminal/P3_TRIVS_P1_PRODUCT_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 7_469,
    "sha256" => "da4ec96ee559fcce19b826985627edfceaea2a8d646ca7574b46a08d6e8f8ebe"
  }.freeze
  F2_TERMINAL_RECEIPT = {
    "path" =>
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trivs-evidence-first-final-route-20260823/task-foundation/terminal/P3_TRIVS_F2_TASK_ROUTE_TERMINAL_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 1_365,
    "sha256" => "1246e6065d73d87bd01a5dc059ab1377145904ab3fc55f4d25d2ed8a07b7ae9c"
  }.freeze
  F2_DIAGNOSTIC = {
    "path" =>
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trivs-evidence-first-final-route-20260823/task-foundation/preflight/P3_TRIVS_F2_PREWORKER_PROTOCOL_UNREACHABILITY_FINDING_V1.json",
    "byte_length" => 4_566,
    "sha256" => "943d47729d001f0d2afb829a1177c3914b20fe95db9aaf11ecd4a105791368ae"
  }.freeze
  TASK_ID = "AIOS-P3-MTRO-P1_ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION"
  TASK_CONTRACT_PATH =
    "docs/aios/tasks/P3-MTRO-P1_ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION.yaml"
  TASK_BRANCH = "codex/p3-mtro-p1-actual-agent-transactional-oci-read-only"
  TASK_WORKTREE =
    "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-mtro-p1-actual-agent-transactional-oci-read-only"
  TASK_EVIDENCE_ROOT =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-minimum-trust-transactional-oci-20260824/task-product"
  OBJECTIVE_ID = "ACTUAL_AGENT_HOST_AUTHORIZED_DURABLE_READ_ONLY_MINIMUM_TRUST_SLICE"
  STRICT_GATE_ID =
    "ACTUAL_AGENT_HOST_AUTHORIZED_DURABLE_READ_ONLY_MINIMUM_TRUST_SLICE_ACCEPTED"
  STRICT_ITEMS = %w[
    ACTUAL_AGENT_NON_AUTHORITATIVE_PROPOSAL_AND_EXCLUSIVE_RESERVED_INGRESS
    HOST_DERIVED_CUSTODY_DURABLE_INTENT_REAL_MYSQL_AND_EXACTLY_ONE_TERMINAL
    REPRESENTATIVE_FRESH_PROCESS_RECOVERY_AND_CHECKPOINT_GATE
    PINNED_LOCAL_OCI_READ_ONLY_ISOLATION_COMPLETE_TRACE_AND_REPLAY
  ].freeze
  GATE_REQUIRED_FACTS = {
    "ACTUAL_AGENT_NON_AUTHORITATIVE_PROPOSAL_AND_EXCLUSIVE_RESERVED_INGRESS" => %w[
      ACTUAL_AGENT_PRODUCTION_DECODE_RUNTIME_POSITIVE
      MALFORMED_INGRESS_ZERO_EFFECT
      EXCLUSIVE_RESERVED_INGRESS_REJECTION
      HOST_DERIVED_AUTHORITY_BINDING
      SOURCE_TO_CLASS_CUSTODY
    ],
    "HOST_DERIVED_CUSTODY_DURABLE_INTENT_REAL_MYSQL_AND_EXACTLY_ONE_TERMINAL" => %w[
      CUSTODY_OWNERSHIP_DRIFT_MATRIX
      REAL_MYSQL_V034_APPLIED
      SPRING_AOP_TRANSACTION_ROLLBACK
      DURABLE_INTENT_CAS_TERMINAL
      IDENTICAL_TERMINAL_REPLAY_LATE_LOSER
    ],
    "REPRESENTATIVE_FRESH_PROCESS_RECOVERY_AND_CHECKPOINT_GATE" => %w[
      FRESH_PROCESS_WINDOW_INTENT
      FRESH_PROCESS_WINDOW_EFFECT
      FRESH_PROCESS_WINDOW_CLEANUP
      CHECKPOINT_BEFORE_TERMINAL_REJECTED
      CHECKPOINT_AFTER_TERMINAL_EXACTLY_ONCE
    ],
    "PINNED_LOCAL_OCI_READ_ONLY_ISOLATION_COMPLETE_TRACE_AND_REPLAY" => %w[
      PINNED_OCI_PROFILE
      OCI_RAW_STDOUT_STDERR_EXIT
      OCI_CLEANUP_ABSENCE
      HOST_INDEPENDENT_SHA_MATCH
      FOCUSED_MAVEN_TESTS
      FULL_MAVEN_TESTS
      ZERO_FORBIDDEN_EXTERNAL_EFFECTS
      CANONICAL_REPLAY
    ]
  }.transform_values(&:freeze).freeze
  RECEIPT_DERIVED_EXECUTION_FACTS = (
    GATE_REQUIRED_FACTS.values.flatten - %w[
      SOURCE_TO_CLASS_CUSTODY FOCUSED_MAVEN_TESTS FULL_MAVEN_TESTS
      ZERO_FORBIDDEN_EXTERNAL_EFFECTS CANONICAL_REPLAY
    ]
  ).freeze
  OBSERVATION_RECORD_SPECS = {
    "agent_ingress" => {
      "schema_version" => "p3-mtro-agent-ingress-observation/v1",
      "record_type" => "P3_MTRO_AGENT_INGRESS_OBSERVATION",
      "facts" => %w[
        ACTUAL_AGENT_PRODUCTION_DECODE_RUNTIME_POSITIVE MALFORMED_INGRESS_ZERO_EFFECT
        EXCLUSIVE_RESERVED_INGRESS_REJECTION HOST_DERIVED_AUTHORITY_BINDING
      ]
    },
    "source_custody" => {
      "schema_version" => "p3-mtro-source-custody-observation/v1",
      "record_type" => "P3_MTRO_SOURCE_CUSTODY_OBSERVATION",
      "facts" => %w[SOURCE_TO_CLASS_CUSTODY CUSTODY_OWNERSHIP_DRIFT_MATRIX]
    },
    "transaction_recovery" => {
      "schema_version" => "p3-mtro-transaction-recovery-observation/v1",
      "record_type" => "P3_MTRO_TRANSACTION_RECOVERY_OBSERVATION",
      "facts" => %w[
        REAL_MYSQL_V034_APPLIED SPRING_AOP_TRANSACTION_ROLLBACK
        DURABLE_INTENT_CAS_TERMINAL IDENTICAL_TERMINAL_REPLAY_LATE_LOSER
        FRESH_PROCESS_WINDOW_INTENT FRESH_PROCESS_WINDOW_EFFECT
        FRESH_PROCESS_WINDOW_CLEANUP CHECKPOINT_BEFORE_TERMINAL_REJECTED
        CHECKPOINT_AFTER_TERMINAL_EXACTLY_ONCE
      ]
    },
    "oci_lifecycle" => {
      "schema_version" => "p3-mtro-oci-lifecycle-observation/v1",
      "record_type" => "P3_MTRO_OCI_LIFECYCLE_OBSERVATION",
      "facts" => %w[
        PINNED_OCI_PROFILE OCI_RAW_STDOUT_STDERR_EXIT OCI_CLEANUP_ABSENCE
        HOST_INDEPENDENT_SHA_MATCH
      ]
    }
  }.transform_values { |value| value.merge("facts" => value.fetch("facts").freeze).freeze }.freeze
  FACT_TEST_CASES = {
    "ACTUAL_AGENT_PRODUCTION_DECODE_RUNTIME_POSITIVE" =>
      "com.sourcelens.module.agent.trustedread.TrustedReadAgentIngressIT#actualAgentProductionDecodeRuntimePositive",
    "MALFORMED_INGRESS_ZERO_EFFECT" =>
      "com.sourcelens.module.agent.trustedread.TrustedReadAgentIngressIT#malformedIngressHasZeroEffect",
    "EXCLUSIVE_RESERVED_INGRESS_REJECTION" =>
      "com.sourcelens.module.agent.trustedread.TrustedReadAgentIngressIT#reservedIngressIsExclusive",
    "HOST_DERIVED_AUTHORITY_BINDING" =>
      "com.sourcelens.module.agent.trustedread.TrustedReadAuthorityIT#hostDerivesCompleteAuthority",
    "SOURCE_TO_CLASS_CUSTODY" =>
      "com.sourcelens.module.agent.trustedread.TrustedReadSourceCustodyIT#sourceMapsToExecutedClasses",
    "CUSTODY_OWNERSHIP_DRIFT_MATRIX" =>
      "com.sourcelens.module.agent.trustedread.TrustedReadSourceCustodyIT#custodyDriftMatrixFailsClosed",
    "REAL_MYSQL_V034_APPLIED" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadTransactionIT#realMysqlV034IsApplied",
    "SPRING_AOP_TRANSACTION_ROLLBACK" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadTransactionIT#springAopRollbackLeavesNoIntent",
    "DURABLE_INTENT_CAS_TERMINAL" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadTransactionIT#durableIntentCasHasOneTerminal",
    "IDENTICAL_TERMINAL_REPLAY_LATE_LOSER" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadTransactionIT#replayIsIdempotentAndLateLoserRejected",
    "FRESH_PROCESS_WINDOW_INTENT" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadRecoveryIT#recoversCommittedIntentInFreshProcess",
    "FRESH_PROCESS_WINDOW_EFFECT" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadRecoveryIT#recoversPossibleEffectInFreshProcess",
    "FRESH_PROCESS_WINDOW_CLEANUP" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadRecoveryIT#recoversCleanupInFreshProcess",
    "CHECKPOINT_BEFORE_TERMINAL_REJECTED" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadCheckpointIT#checkpointBeforeTerminalIsRejected",
    "CHECKPOINT_AFTER_TERMINAL_EXACTLY_ONCE" =>
      "com.sourcelens.module.execution.trustedread.TrustedReadCheckpointIT#checkpointAfterTerminalIsExactlyOnce",
    "PINNED_OCI_PROFILE" =>
      "com.sourcelens.module.sandbox.oci.trustedread.TrustedReadOciIT#usesExactPinnedProfile",
    "OCI_RAW_STDOUT_STDERR_EXIT" =>
      "com.sourcelens.module.sandbox.oci.trustedread.TrustedReadOciIT#capturesRawProcessResult",
    "OCI_CLEANUP_ABSENCE" =>
      "com.sourcelens.module.sandbox.oci.trustedread.TrustedReadOciIT#cleansOnlyOwnedObjects",
    "HOST_INDEPENDENT_SHA_MATCH" =>
      "com.sourcelens.module.sandbox.oci.trustedread.TrustedReadOciIT#hostAndOciShaMatch",
    "ZERO_FORBIDDEN_EXTERNAL_EFFECTS" =>
      "com.sourcelens.module.sandbox.oci.trustedread.TrustedReadExternalEffectsIT#observesZeroForbiddenEffects"
  }.freeze
  COMPATIBILITY_ITEM = "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"
  FIXED_ACTION = {
    "action_id" => "READ_BOUND_ARCHITECTURE_OVERVIEW_SHA256_V1",
    "agent_task_type" => "TRUSTED_READ_ONLY_ARCHITECTURE_OVERVIEW_SHA256_V1",
    "reserved_tool_name" => "trusted_read_bound_architecture_overview_sha256_v1",
    "agent_arguments" => {},
    "custody_owner_type" => "SCAN_TASK",
    "custody_artifact_type" => "ARCHITECTURE_OVERVIEW"
  }.freeze
  LIMITS = {
    "engineering_tasks" => 19,
    "engineering_hours" => 568,
    "calendar_days" => 132,
    "active_tasks" => 1,
    "task_branches" => 1,
    "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  CONSUMED = {
    "engineering_tasks" => 18,
    "engineering_hours" => 520,
    "calendar_days" => 122
  }.freeze
  TASK_BUDGET = {
    "engineering_tasks" => 1,
    "engineering_hours" => 48,
    "calendar_days" => 10,
    "candidate_generations" => 2,
    "same_task_repairs" => 1,
    "review_cycles" => 2
  }.freeze
  REMAINING = TASK_BUDGET.slice(
    "engineering_tasks", "engineering_hours", "calendar_days"
  ).freeze
  DOCKER_CLI = {
    "path" => "/Applications/Docker.app/Contents/Resources/bin/docker",
    "sha256" => "a6822407e207ff0b687419ccbe55700ffbf389d77de58ef625b3b1790d88747c"
  }.freeze
  DOCKER_ENDPOINT = "unix:///Users/lijunpeng/.docker/run/docker.sock"
  IMAGE_ID = "sha256:d36d39a64cd12a5c1cc9e6aa2bfb5f8d4c81a2f6586e0a04a9ae13939db02209"
  DOCKER_VERBS = [
    "version", "info", "image inspect exact content ID", "network create --internal",
    "network inspect", "network rm", "create", "start", "wait", "inspect", "logs",
    "port", "rm --force"
  ].freeze
  AUTHORITY_PATH = File.join(
    TASK_EVIDENCE_ROOT,
    "authority/P3_MTRO_P1_PHASE_DELEGATED_TASK_AUTHORITY_V1.json"
  ).freeze
  FINAL_CONSUMED = {
    "engineering_tasks" => 19,
    "engineering_hours" => 568,
    "calendar_days" => 132
  }.freeze
  ZERO_CAPACITY = {
    "engineering_tasks" => 0,
    "engineering_hours" => 0,
    "calendar_days" => 0
  }.freeze
  PRODUCT_ARCHITECTURE = {
    "actual_agent_runtime_required" => true,
    "agent_non_authoritative" => true,
    "host_derives_all_authority_bearing_fields" => true,
    "generic_tool_registry_bypassed" => true,
    "generic_tool_execution_service_bypassed" => true,
    "generic_docker_sandbox_executor_bypassed" => true,
    "production_spring_transaction_service_store_required" => true,
    "real_mysql_required" => true,
    "migration" =>
      "backend-spring/src/main/resources/db/migration/V034__add_trusted_read_only_invocation.sql",
    "current_state_table_count" => 1,
    "allowed_statuses" => %w[INTENT DISPATCHING EFFECT_RECORDED CLEANING SUCCEEDED FAILED],
    "representative_fresh_process_windows" => [
      "INTENT_COMMITTED_EFFECT_NOT_BEGUN",
      "EFFECT_MAY_HAVE_OCCURRED_TERMINAL_NOT_COMMITTED",
      "CLEANUP_BEGUN_OR_COMPLETED_TERMINAL_NOT_COMMITTED"
    ]
  }.freeze
  DISABLED_ROUTE_EXTERNAL_EFFECTS = {
    "docker" => false,
    "task_created_disposable_mysql" => false,
    "task_local_mysql_loopback_only" => false,
    "network" => false,
    "dns" => false,
    "http_https" => false,
    "provider" => false,
    "secret" => false,
    "credential" => false,
    "remote" => false,
    "production" => false,
    "public" => false,
    "p4_entry" => false
  }.freeze
  ENABLED_TASK_LOCAL_ROUTE_EXTERNAL_EFFECTS = DISABLED_ROUTE_EXTERNAL_EFFECTS.merge(
    "docker" => true,
    "task_created_disposable_mysql" => true,
    "task_local_mysql_loopback_only" => true
  ).freeze
  DEFERRED_CAPABILITIES = %w[
    P4_ENTRY
    P5_EXHAUSTIVE_TRUSTWORTHY_EXECUTION_HARDENING
    INTERNET
    DNS
    HTTP_HTTPS
    PROVIDER
    EXTERNAL_SECRET
    EXTERNAL_CREDENTIAL
    REMOTE
    PRODUCTION
    PUBLIC
  ].freeze
  ROLE_WRITE_ROOTS = {
    "worker" => [TASK_WORKTREE],
    "quality" => [TASK_EVIDENCE_ROOT],
    "integration" => ["/Users/lijunpeng/Developer/SourceLens-AIOS"]
  }.freeze
  IMMUTABLE_AUTHORITY_PATHS = %w[
    AGENTS.md
    docs/aios/STRATEGIC_CONSTITUTION.md
    docs/aios/MASTER_EXECUTION_PROTOCOL.md
    docs/aios/FOUNDER_DELEGATION_POLICY.md
    docs/aios/EVALUATION_PROTOCOL.md
  ].freeze
  REVIEWER_ROLES = ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"].freeze
  DELEGATION_ANTI_LOOP = {
    "route_or_task_may_downgrade_phase_delegation" => false,
    "ordinary_task_failure_requests_founder" => false,
    "foundation_or_preflight_task_allowed" => false,
    "audit_task_allowed" => false,
    "third_product_task_allowed" => false,
    "successor_or_replacement_allowed" => false,
    "candidate_3_allowed" => false,
    "second_same_task_repair_allowed" => false,
    "third_review_cycle_allowed" => false,
    "rerun_to_pass_allowed" => false
  }.freeze
  FOUNDER_RESERVED_DECISIONS = %w[
    PHASE_ENTRY_OR_EXIT
    MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
    MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
    NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT
    IRREVERSIBLE_ASSET_REMOVAL
    MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT
    CRITICAL_RESIDUAL_RISK_ACCEPTANCE
  ].freeze
  AGENT_DELEGATED_DECISIONS = %w[
    EXACT_MTRO_P1_PRODUCT_TASK_ACTIVATION
    TASK_CONTRACT_AND_AUTHORITY
    IMPLEMENTATION_AND_ONE_ALLOWED_SAME_TASK_REPAIR
    TEST_EVIDENCE_TWO_REVIEW_CYCLES_AND_TASK_GATE
    LOCAL_CANONICAL_INTEGRATION
    EXACTLY_ONE_POST_INTEGRATION_CANONICAL_REPLAY
  ].freeze
  ENVELOPE_EXTERNAL_EFFECTS_LOCKED = {
    "docker_task_operations" => "LOCKED_UNTIL_TASK_ACTIVE",
    "task_created_disposable_mysql" => false,
    "task_local_mysql_loopback_only" => false,
    "network" => false,
    "dns" => false,
    "http_https" => false,
    "provider" => false,
    "secret" => false,
    "credential" => false,
    "remote" => false,
    "production" => false,
    "public" => false,
    "p4_entry" => false
  }.freeze
  ENVELOPE_EXTERNAL_EFFECTS_ACTIVE = ENVELOPE_EXTERNAL_EFFECTS_LOCKED.merge(
    "docker_task_operations" => "TASK_ACTIVE_EXACT_LOCAL_AUTHORITY_ONLY",
    "task_created_disposable_mysql" => true,
    "task_local_mysql_loopback_only" => true
  ).freeze
  ENVELOPE_EXTERNAL_EFFECTS_FINAL = ENVELOPE_EXTERNAL_EFFECTS_LOCKED.merge(
    "docker_task_operations" => "FINAL_TASK_CLOSED_NO_AUTHORITY"
  ).freeze
  DISABLED_ACTIVE_EXTERNAL_EFFECTS = {
    "docker" => false,
    "docker_scope" => "LOCKED_UNTIL_TASK_ACTIVE",
    "docker_endpoint" => DOCKER_ENDPOINT,
    "docker_registry_pull_push_login_build_import_or_tag" => false,
    "task_created_disposable_mysql" => false,
    "task_local_mysql_loopback_only" => false,
    "network" => false,
    "dns" => false,
    "http_https" => false,
    "provider" => false,
    "secret" => false,
    "credential" => false,
    "remote" => false,
    "production" => false,
    "public" => false,
    "existing_database_mutation" => false,
    "write_outside_exact_authorized_roots" => false,
    "irreversible_asset_deletion" => false
  }.freeze
  ENABLED_TASK_LOCAL_ACTIVE_EXTERNAL_EFFECTS = DISABLED_ACTIVE_EXTERNAL_EFFECTS.merge(
    "docker" => true,
    "docker_scope" => "EXACT_TASK_CREATED_OBJECTS_ONLY",
    "task_created_disposable_mysql" => true,
    "task_local_mysql_loopback_only" => true
  ).freeze
  RUNTIME_STATES = %w[
    PENDING_TASK_OWNED_DISCOVERY ACTIVATION_BOUND CANDIDATE_FROZEN
    REVIEW_BOUND INTEGRATED_REPLAY_BOUND
  ].freeze
  LIFECYCLE_PROFILES = {
    "PRODUCT_ELIGIBLE_NOT_ACTIVATED" => {
      "state" => "P3_MTRO_PRODUCT_ELIGIBLE_NOT_ACTIVATED",
      "phase_status" => "ACTIVE_P3_MTRO_PRODUCT_ELIGIBLE_NOT_ACTIVATED",
      "p3_status" => "ACTIVE_INCOMPLETE_P3_MTRO_PRODUCT_ELIGIBLE_NOT_ACTIVATED",
      "route_status" => "ACTIVE",
      "scheduling_status" => "ONE_FINAL_PRODUCT_TASK_ELIGIBLE",
      "stage_status" => "ELIGIBLE_NOT_ACTIVATED",
      "action" => "MASTER_ACTIVATE_P3_MTRO_P1",
      "task_creation" => true,
      "active" => false,
      "founder_required" => false,
      "disposition" => "NO_RESERVED_TRIGGER_CONTINUE_PHASE",
      "next_owner" => "MASTER_CEO_AGENT",
      "reserved_trigger" => "NONE",
      "resolved_result" => "P3_MTRO_FINAL_PRODUCT_ROUTE_INSTALLED_PRODUCT_ELIGIBLE",
      "phase_gate_status" => "INCOMPLETE",
      "boundary_scope" => "ONE_EXACT_MTRO_P1_PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL_ONLY",
      "task_status" => "ELIGIBLE_NOT_ACTIVATED",
      "task_resource_state" => "NOT_CREATED_PRODUCT_ELIGIBLE",
      "executable_slots" => "1_OF_1_ELIGIBLE_NOT_ACTIVATED",
      "capability_status" => "MTRO_SECOND_AND_FINAL_PRODUCT_ELIGIBLE_NOT_ACCEPTED",
      "engineering_progress" =>
        "P3_MTRO_STRATEGIC_ROUTE_INSTALLED_PRODUCT_NOT_YET_ACTIVATED_DELIVERY_25_STRICT_EXIT_ZERO",
      "goal_state_note" =>
        "P3 MTRO final Product route is installed but not activated. P3 is 25% delivery and 0% strict Exit; P4 is HOLD; the project is incomplete; the Long-term Goal remains ACTIVE.",
      "effects_enabled" => false,
      "final_accounting" => false,
      "accepted" => false,
      "terminal" => false,
      "delivery" => 25,
      "strict" => 0
    },
    "PRODUCT_TASK_ACTIVE" => {
      "state" => "P3_MTRO_PRODUCT_TASK_ACTIVE",
      "phase_status" => "ACTIVE_P3_MTRO_PRODUCT_TASK_ACTIVE",
      "p3_status" => "ACTIVE_INCOMPLETE_P3_MTRO_PRODUCT_TASK_ACTIVE",
      "route_status" => "ACTIVE",
      "scheduling_status" => "ONE_FINAL_PRODUCT_TASK_ACTIVE",
      "stage_status" => "ACTIVE",
      "action" => "WORKER_RUN_P3_MTRO_PREWRITE_OCI_PROBE_THEN_IMPLEMENT",
      "task_creation" => false,
      "active" => true,
      "founder_required" => false,
      "disposition" => "NO_RESERVED_TRIGGER_CONTINUE_PHASE",
      "next_owner" => "MASTER_CEO_AGENT",
      "reserved_trigger" => "NONE",
      "resolved_result" => "P3_MTRO_FINAL_PRODUCT_TASK_ACTIVE",
      "phase_gate_status" => "INCOMPLETE",
      "boundary_scope" => "NO_ADDITIONAL_TASK_CURRENT_FINAL_PRODUCT_ACTIVE",
      "task_status" => "ACTIVE",
      "task_resource_state" => "ACTIVE_PRODUCT_TASK_RESOURCES_CREATED",
      "executable_slots" => "1_OF_1_ACTIVE",
      "capability_status" => "MTRO_SECOND_AND_FINAL_PRODUCT_ACTIVE_NOT_ACCEPTED",
      "engineering_progress" =>
        "P3_MTRO_FINAL_PRODUCT_TASK_ACTIVE_DELIVERY_25_STRICT_EXIT_ZERO",
      "goal_state_note" =>
        "P3 MTRO final Product Task is ACTIVE under its exact Contract and authority. P3 remains 25% delivery and 0% strict Exit; P4 is HOLD; the project is incomplete; the Long-term Goal remains ACTIVE.",
      "effects_enabled" => true,
      "final_accounting" => false,
      "accepted" => false,
      "terminal" => false,
      "delivery" => 25,
      "strict" => 0
    },
    "PRODUCT_ROUTE_TERMINAL_NON_PASS" => {
      "state" => "P3_MTRO_PRODUCT_ROUTE_TERMINAL_NON_PASS",
      "phase_status" => "HOLD_INCOMPLETE_P3_MTRO_PRODUCT_ROUTE_TERMINAL_NON_PASS",
      "p3_status" => "HOLD_INCOMPLETE_P3_MTRO_PRODUCT_ROUTE_TERMINAL_NON_PASS",
      "route_status" => "TERMINAL_FINAL_PRODUCT_NON_PASS",
      "scheduling_status" => "NO_FURTHER_P3_IMPLEMENTATION_ALLOWED",
      "stage_status" => "TERMINAL_TASK_GATE_NON_PASS",
      "action" => "NO_ENGINEERING_ACTION_P3_HOLD_INCOMPLETE_FINAL_PRODUCT_FROZEN",
      "task_creation" => false,
      "active" => false,
      "founder_required" => false,
      "disposition" => "NO_RESERVED_TRIGGER_ROUTE_TERMINAL",
      "next_owner" => "NONE",
      "reserved_trigger" => "NONE",
      "resolved_result" => "P3_MTRO_FINAL_PRODUCT_ROUTE_TERMINAL_NON_PASS",
      "phase_gate_status" => "INCOMPLETE",
      "boundary_scope" => "NO_FURTHER_P3_IMPLEMENTATION_ALLOWED",
      "task_status" => "TERMINAL_TASK_GATE_NON_PASS",
      "task_resource_state" => "TERMINAL_EVIDENCE_PRESERVED_BRANCH_AND_WORKTREE_REMOVED",
      "executable_slots" => "1_OF_1_CONSUMED_TERMINAL_NO_FURTHER_IMPLEMENTATION",
      "capability_status" => "MTRO_SECOND_AND_FINAL_PRODUCT_TERMINAL_NOT_ACCEPTED",
      "engineering_progress" =>
        "P3_MTRO_FINAL_PRODUCT_ROUTE_TERMINAL_DELIVERY_25_STRICT_EXIT_ZERO",
      "goal_state_note" =>
        "P3 MTRO final Product route is terminal NON_PASS with no further P3 implementation authority. P3 remains incomplete at 25% delivery and 0% strict Exit; P4 is HOLD; the project is incomplete; the Long-term Goal remains ACTIVE.",
      "effects_enabled" => false,
      "final_accounting" => true,
      "accepted" => false,
      "terminal" => true,
      "delivery" => 25,
      "strict" => 0
    },
    "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE" => {
      "state" => "P3_MTRO_PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE",
      "phase_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "p3_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "route_status" => "ACCEPTED_AWAITING_FOUNDER_PHASE_GATE",
      "scheduling_status" => "NO_TASK_FOUNDER_PHASE_GATE",
      "stage_status" => "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS",
      "action" => "FOUNDER_DECIDE_P3_PHASE_GATE",
      "task_creation" => false,
      "active" => false,
      "founder_required" => true,
      "disposition" => "FOUNDER_RESERVED_DECISION_REQUIRED",
      "next_owner" => "HUMAN_FOUNDER",
      "reserved_trigger" => "PHASE_ENTRY_OR_EXIT",
      "resolved_result" => "P3_MTRO_PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE",
      "phase_gate_status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION",
      "boundary_scope" => "NO_TASK_FOUNDER_PHASE_GATE",
      "task_status" => "ACCEPTED_INTEGRATED_CANONICAL_REPLAY_PASS",
      "task_resource_state" => "ACCEPTED_EVIDENCE_PRESERVED_BRANCH_AND_WORKTREE_REMOVED",
      "executable_slots" => "1_OF_1_CONSUMED_ACCEPTED_NO_TASK_FOUNDER_PHASE_GATE",
      "capability_status" => "ACCEPTED_NARROW_MTRO_SLICE",
      "engineering_progress" =>
        "P3_MTRO_NARROW_SLICE_ACCEPTED_DELIVERY_100_STRICT_EXIT_100_AWAITING_FOUNDER_PHASE_GATE",
      "goal_state_note" =>
        "P3 MTRO narrow slice is accepted after three independent PASS reviews, canonical integration and one replay. P3 is 100% delivery and 100% strict Exit awaiting the Founder Phase Gate; P4 remains HOLD; the project is incomplete; the Long-term Goal remains ACTIVE.",
      "effects_enabled" => false,
      "final_accounting" => true,
      "accepted" => true,
      "terminal" => false,
      "delivery" => 100,
      "strict" => 100
    }
  }.transform_values(&:freeze).freeze

  def assert(condition, message)
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} must be a sequence")
    value
  end

  def exact_keys(value, keys, label)
    record = mapping(value, label)
    assert(record.keys.sort == keys.sort, "#{label} keys are not closed")
    record
  end

  def parse_closed_json(bytes, label)
    JSON.parse(bytes, object_class: ClosedJsonHash)
  rescue JSON::ParserError, DuplicateJsonKeyError => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "#{label} JSON invalid: #{e.message}"
  end

  def reject_duplicate_yaml_keys!(bytes, label)
    tree = Psych.parse_stream(bytes)
    walk = nil
    walk = lambda do |node, location|
      case node
      when Psych::Nodes::Mapping
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          assert(key_node.is_a?(Psych::Nodes::Scalar),
                 "#{label} contains a non-scalar YAML key at #{location}")
          key = key_node.value
          assert(!seen.key?(key), "#{label} contains duplicate YAML key #{location}.#{key}")
          seen[key] = true
          walk.call(value_node, "#{location}.#{key}")
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index { |child, index| walk.call(child, "#{location}[#{index}]") }
      end
    end
    walk.call(tree, label)
  rescue Psych::SyntaxError => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "#{label} YAML invalid: #{e.message}"
  end

  def artifact_identity!(root, value, label, exact_path: nil, under: nil)
    identity = exact_keys(value, %w[path byte_length sha256], label)
    path = identity.fetch("path")
    assert(path.is_a?(String) && !path.empty?, "#{label} path is invalid")
    assert(path == exact_path, "#{label} path drift") if exact_path
    pathname = Pathname.new(path)
    pathname = root.join(pathname) unless pathname.absolute?
    literal = literal_path!(pathname, label, directory: false)
    if under
      under_literal = literal_path!(Pathname.new(under), "#{label} authorized root", directory: true)
      prefix = under_literal.to_s + File::SEPARATOR
      assert(literal.to_s.start_with?(prefix), "#{label} escapes its authorized root")
    end
    file_identity!(literal.to_s, identity, label)
  rescue Errno::ENOENT, Errno::ELOOP => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "#{label} unavailable: #{e.message}"
  end

  def literal_path!(path, label, directory:)
    pathname = Pathname.new(path.to_s)
    assert(pathname.absolute?, "#{label} path must be absolute")
    clean = pathname.cleanpath
    assert(clean.to_s == pathname.to_s, "#{label} path is not lexical-canonical")
    current = Pathname.new(File::SEPARATOR)
    clean.each_filename do |component|
      current = current.join(component)
      stat = File.lstat(current)
      assert(!stat.symlink?, "#{label} contains symlink component #{current}")
    end
    final_stat = File.lstat(clean)
    assert(directory ? final_stat.directory? : final_stat.file?,
           "#{label} has the wrong filesystem type")
    clean
  end

  def git_identity!(root, commit, tree, label)
    assert(commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/) &&
           tree.is_a?(String) && tree.match?(/\A[0-9a-f]{40}\z/),
           "#{label} Git identity is invalid")
    actual_tree = git!(root, "rev-parse", "#{commit}^{tree}").strip
    assert(actual_tree == tree, "#{label} commit/tree mismatch")
  end

  def path_covered_by_allowlist?(path, allowlist)
    allowlist.any? do |allowed|
      directory_root = allowed.end_with?("/") || File.extname(allowed).empty?
      path == allowed || (directory_root && path.start_with?("#{allowed.delete_suffix("/")}/"))
    end
  end

  def git_changed_paths!(root, from_commit, to_commit, label)
    raw = git!(root, "diff", "--name-status", "-z", "--no-renames", from_commit, to_commit)
    tokens = raw.split("\0", -1)
    assert(tokens.pop == "" && tokens.length.even?, "#{label} diff encoding drift")
    entries = tokens.each_slice(2).map do |status, path|
      assert(%w[A M D].include?(status) && path.is_a?(String) && !path.empty?,
             "#{label} contains unsupported change status")
      pathname = Pathname.new(path)
      assert(!pathname.absolute? && pathname.cleanpath.to_s == path && path != ".." &&
             !path.start_with?("../"), "#{label} contains a non-canonical path")
      path
    end
    assert(entries.uniq.length == entries.length, "#{label} repeats a changed path")
    entries.sort
  end

  def validate_finding_record!(root, finding, label)
    finding = exact_keys(
      finding, %w[id severity gate_relevance category description evidence], label
    )
    assert(%w[P0 P1].include?(finding["severity"]) &&
           %w[
             EXIT_GATE_VALIDITY AUTHORITY_OR_EXTERNAL_EFFECT_SAFETY RESULT_INTEGRITY
             PRODUCT_CORRECTNESS
           ].include?(finding["category"]) &&
           finding["gate_relevance"] == "BLOCKING" &&
           finding["id"].is_a?(String) && !finding["id"].empty? &&
           finding["description"].is_a?(String) && !finding["description"].empty?,
           "#{label} semantic drift")
    artifact_identity!(root, finding["evidence"], "#{label} Evidence",
                       under: TASK_EVIDENCE_ROOT)
    finding
  end

  def validate_frozen_finding_set!(root, identity)
    bytes = artifact_identity!(root, identity, "P3 MTRO frozen finding set",
                               under: TASK_EVIDENCE_ROOT)
    finding_set = exact_keys(
      parse_closed_json(bytes, "P3 MTRO frozen finding set"),
      %w[
        schema_version record_type status task_id route_id candidate_commit candidate_tree
        candidate_freeze_record cycle_1_review_dispatch cycle_1_reviews
        complete_p0_p1_set findings created_at_utc
      ],
      "P3 MTRO frozen finding set"
    )
    reviews = exact_keys(finding_set["cycle_1_reviews"], %w[cto security quality_evaluation],
                         "P3 MTRO Cycle 1 review identities")
    dispatch_bytes = artifact_identity!(
      root, finding_set["cycle_1_review_dispatch"], "P3 MTRO Cycle 1 review dispatch",
      under: TASK_EVIDENCE_ROOT
    )
    dispatch = exact_keys(
      parse_closed_json(dispatch_bytes, "P3 MTRO Cycle 1 review dispatch"),
      %w[
        schema_version record_type status task_id route_id execution_nonce authorization_id
        candidate_commit candidate_tree review_cycle candidate_freeze_record
        frozen_finding_set repair_record reviewer_worktrees dispatched_at_utc
      ],
      "P3 MTRO Cycle 1 review dispatch"
    )
    assert(dispatch["schema_version"] == "p3-mtro-review-dispatch-record/v1" &&
           dispatch["record_type"] == "P3_MTRO_REVIEW_DISPATCH_RECORD" &&
           dispatch["status"] == "DISPATCHED" && dispatch["task_id"] == TASK_ID &&
           dispatch["route_id"] == ROUTE_ID && dispatch["review_cycle"] == 1 &&
           dispatch["candidate_commit"] == finding_set["candidate_commit"] &&
           dispatch["candidate_tree"] == finding_set["candidate_tree"] &&
           dispatch["candidate_freeze_record"] == finding_set["candidate_freeze_record"] &&
           dispatch["frozen_finding_set"].nil? && dispatch["repair_record"].nil?,
           "P3 MTRO Cycle 1 review dispatch semantic drift")
    Time.iso8601(dispatch.fetch("dispatched_at_utc"))
    freeze_bytes = artifact_identity!(
      root, finding_set["candidate_freeze_record"], "P3 MTRO Cycle 1 candidate freeze",
      under: TASK_EVIDENCE_ROOT
    )
    freeze = exact_keys(
      parse_closed_json(freeze_bytes, "P3 MTRO Cycle 1 candidate freeze"),
      %w[
        schema_version record_type status task_id route_id execution_nonce authorization_id
        candidate_commit candidate_tree candidate_generation manifest task_activation_record
        frozen_at_utc
      ],
      "P3 MTRO Cycle 1 candidate freeze"
    )
    assert(freeze["schema_version"] == "p3-mtro-candidate-freeze-record/v1" &&
           freeze["record_type"] == "P3_MTRO_CANDIDATE_FREEZE_RECORD" &&
           freeze["status"] == "FROZEN" && freeze["task_id"] == TASK_ID &&
           freeze["route_id"] == ROUTE_ID && freeze["candidate_generation"] == 1 &&
           freeze["candidate_commit"] == finding_set["candidate_commit"] &&
           freeze["candidate_tree"] == finding_set["candidate_tree"],
           "P3 MTRO Cycle 1 candidate freeze semantic drift")
    Time.iso8601(freeze.fetch("frozen_at_utc"))
    expected_roles = {
      "cto" => "CTO_AGENT", "security" => "SECURITY_AGENT",
      "quality_evaluation" => "QUALITY_EVALUATION_AGENT"
    }
    cycle_1_finding_ids = []
    reviews.each do |role, review_identity|
      review_bytes = artifact_identity!(root, review_identity,
                                        "P3 MTRO Cycle 1 #{role} review",
                                        under: TASK_EVIDENCE_ROOT)
      review = exact_keys(
        parse_closed_json(review_bytes, "P3 MTRO Cycle 1 #{role} review"),
        %w[
          schema_version record_type role verdict task_id route_id candidate_commit
          candidate_tree review_cycle review_dispatch frozen_finding_set reviewer_worktree
          repair_record findings open_p0_p1_findings gate_relevance reviewed_at_utc
        ],
        "P3 MTRO Cycle 1 #{role} review"
      )
      review_findings = array(review["findings"], "P3 MTRO Cycle 1 #{role} findings")
      review_findings.each do |finding|
        cycle_1_finding_ids << validate_finding_record!(
          root, finding, "P3 MTRO Cycle 1 #{role} finding"
        ).fetch("id")
      end
      assert(review["schema_version"] == "p3-mtro-independent-review/v1" &&
             review["record_type"] == "P3_MTRO_INDEPENDENT_REVIEW" &&
             review["role"] == expected_roles.fetch(role) &&
             %w[PASS NON_PASS].include?(review["verdict"]) &&
             review["task_id"] == TASK_ID && review["route_id"] == ROUTE_ID &&
             review["candidate_commit"] == finding_set["candidate_commit"] &&
             review["candidate_tree"] == finding_set["candidate_tree"] &&
             review["review_cycle"] == 1 &&
             review["review_dispatch"] == finding_set["cycle_1_review_dispatch"] &&
             review["frozen_finding_set"].nil? && review["repair_record"].nil? &&
             review["open_p0_p1_findings"].sort ==
               review_findings.map { |finding| finding.fetch("id") }.sort &&
             review["gate_relevance"] == (review_findings.empty? ? "PASS" : "NON_PASS"),
             "P3 MTRO Cycle 1 #{role} review semantic drift")
      Time.iso8601(review.fetch("reviewed_at_utc"))
    end
    findings = array(finding_set["findings"], "P3 MTRO frozen findings")
    frozen_ids = findings.map do |finding|
      validate_finding_record!(root, finding, "P3 MTRO frozen finding").fetch("id")
    end
    assert(finding_set["schema_version"] == "p3-mtro-frozen-finding-set/v1" &&
           finding_set["record_type"] == "P3_MTRO_FROZEN_FINDING_SET" &&
           finding_set["status"] == "FROZEN" && finding_set["task_id"] == TASK_ID &&
           finding_set["route_id"] == ROUTE_ID &&
           finding_set["complete_p0_p1_set"] == true &&
           frozen_ids.uniq.length == frozen_ids.length &&
           frozen_ids.sort == cycle_1_finding_ids.uniq.sort,
           "P3 MTRO frozen finding set is not the complete Cycle 1 aggregate")
    git_identity!(root, finding_set["candidate_commit"], finding_set["candidate_tree"],
                  "P3 MTRO Cycle 1 reviewed candidate")
    Time.iso8601(finding_set.fetch("created_at_utc"))
    [finding_set, frozen_ids]
  end

  def validate_task_base!(root, activation_parent_commit, descendant_commit, contract_identity)
    commits = git!(
      root, "rev-list", "--reverse", "--ancestry-path",
      "#{activation_parent_commit}..#{descendant_commit}"
    ).lines.map(&:strip).reject(&:empty?)
    assert(!commits.empty?, "P3 MTRO Task lineage has no activation commit")
    task_base_commit = commits.first
    parent_line = git!(root, "rev-list", "--parents", "-n", "1", task_base_commit).split
    assert(parent_line == [task_base_commit, activation_parent_commit],
           "P3 MTRO activation commit is not the sole direct child of strategic installation")
    activation_paths = git_changed_paths!(
      root, activation_parent_commit, task_base_commit, "P3 MTRO activation"
    )
    allowed_activation_paths = %w[
      docs/aios/tasks/P3-MTRO-P1_ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION.yaml
      docs/aios/truth/project_state.yaml
      docs/PROJECT_CODE_MAP.md
    ]
    assert(activation_paths.include?(TASK_CONTRACT_PATH) &&
           activation_paths.include?("docs/aios/truth/project_state.yaml") &&
           (activation_paths - allowed_activation_paths).empty?,
           "P3 MTRO activation commit contains non-activation changes")
    contract_bytes = git!(root, "show", "#{task_base_commit}:#{TASK_CONTRACT_PATH}")
    assert(contract_bytes.bytesize == contract_identity.fetch("byte_length") &&
           Digest::SHA256.hexdigest(contract_bytes) == contract_identity.fetch("sha256"),
           "P3 MTRO activation commit does not contain the exact Task Contract")
    task_base_tree = git!(root, "rev-parse", "#{task_base_commit}^{tree}").strip
    {"commit" => task_base_commit, "tree" => task_base_tree}
  end

  def nested_artifact_identities(value)
    case value
    when Hash
      if value.keys.sort == %w[byte_length path sha256]
        [value]
      else
        value.values.flat_map { |nested| nested_artifact_identities(nested) }
      end
    when Array
      value.flat_map { |nested| nested_artifact_identities(nested) }
    else
      []
    end
  end

  def derive_fact_projection!(root:, fact_id:, events:, candidate:, activation_identity:)
    payloads = lambda do |type|
      events.select { |event| event["event_type"] == type }.map { |event| event["payload"] }
    end
    assert(events.none? { |event| %w[RUN_BEGIN FACT_OBSERVATION].include?(event["event_type"]) },
           "P3 MTRO #{fact_id} raw measurement event type is reserved")
    case fact_id
    when "ACTUAL_AGENT_PRODUCTION_DECODE_RUNTIME_POSITIVE"
      assert(events.map { |event| event["event_type"] } == %w[
               AGENT_DECODED TOOL_CALL_OBSERVED INTENT_COMMITTED DISPATCH_CLAIMED
               DOCKER_EFFECT_OBSERVED TERMINAL_PROJECTED
             ], "P3 MTRO actual-Agent raw event sequence drift")
      decoded = exact_keys(payloads.call("AGENT_DECODED").first,
                           %w[agent_task_type runtime_entrypoint production_decode_path], fact_id)
      tool = exact_keys(payloads.call("TOOL_CALL_OBSERVED").first,
                        %w[tool_name arguments authority_bearing_fields], fact_id)
      terminal = exact_keys(payloads.call("TERMINAL_PROJECTED").first, %w[projection], fact_id)
      assert(decoded == {
               "agent_task_type" => FIXED_ACTION.fetch("agent_task_type"),
               "runtime_entrypoint" => "AgentRuntime", "production_decode_path" => "LlmClient"
             } && tool == {
               "tool_name" => FIXED_ACTION.fetch("reserved_tool_name"), "arguments" => {},
               "authority_bearing_fields" => []
             } && terminal["projection"] == "COMMITTED_TERMINAL_MINIMUM_ONLY",
             "P3 MTRO actual-Agent raw values drift")
      {
        "agent_task_type" => decoded["agent_task_type"],
        "runtime_entrypoint" => decoded["runtime_entrypoint"],
        "production_decode_path" => decoded["production_decode_path"],
        "tool_call_count" => payloads.call("TOOL_CALL_OBSERVED").length,
        "agent_authority_bearing_fields" => tool["authority_bearing_fields"],
        "terminal_projection" => terminal["projection"],
        "intent_count" => payloads.call("INTENT_COMMITTED").length,
        "dispatch_count" => payloads.call("DISPATCH_CLAIMED").length,
        "docker_effect_count" => payloads.call("DOCKER_EFFECT_OBSERVED").length
      }
    when "MALFORMED_INGRESS_ZERO_EFFECT"
      cases = payloads.call("MALFORMED_CASE_RESULT").map do |payload|
        exact_keys(payload, %w[case accepted intent_count dispatch_count docker_effect_count], fact_id)
      end
      expected_cases = %w[
        NONEMPTY_ARGUMENTS MALFORMED_ARGUMENTS NULL_ARGUMENTS ARRAY_ARGUMENTS
        MULTIPLE_TOOL_CALLS REPEATED_ROUND WRONG_TOOL_NAME
      ]
      assert(events.length == cases.length && cases.map { |item| item["case"] } == expected_cases &&
             cases.all? { |item| item["accepted"] == false },
             "P3 MTRO malformed-ingress raw case matrix drift")
      {
        "cases" => expected_cases,
        "accepted_case_count" => cases.count { |item| item["accepted"] },
        "intent_count" => cases.sum { |item| item["intent_count"] },
        "dispatch_count" => cases.sum { |item| item["dispatch_count"] },
        "docker_effect_count" => cases.sum { |item| item["docker_effect_count"] }
      }
    when "EXCLUSIVE_RESERVED_INGRESS_REJECTION"
      rejections = payloads.call("GENERIC_SURFACE_REJECTION").map do |payload|
        exact_keys(payload, %w[surface result], fact_id)
      end
      counts = exact_keys(payloads.call("TOOL_LOOP_COUNTS").fetch(0),
                          %w[other_tool_call_count second_tool_call_count repeated_round_count], fact_id)
      assert(events.length == 4 && rejections == [
               {"surface" => "generic_registry", "result" => "REJECTED"},
               {"surface" => "generic_execution", "result" => "REJECTED"},
               {"surface" => "generic_docker", "result" => "REJECTED"}
             ], "P3 MTRO reserved-ingress raw rejection drift")
      {
        "reserved_tool_name" => FIXED_ACTION.fetch("reserved_tool_name"),
        "generic_registry" => rejections[0]["result"],
        "generic_execution" => rejections[1]["result"],
        "generic_docker" => rejections[2]["result"]
      }.merge(counts)
    when "HOST_DERIVED_AUTHORITY_BINDING"
      assert(events.map { |event| event["event_type"] } == ["HOST_AUTHORITY_DERIVATION"],
             "P3 MTRO Host-authority raw event sequence drift")
      derivation = exact_keys(
        events.first["payload"],
        %w[
          fixed_action agent_arguments host_derived_fields authorization_anchor invocation
          truncated_identity_authoritative
        ], fact_id
      )
      anchor_bytes = artifact_identity!(root, derivation["authorization_anchor"],
                                        "P3 MTRO authorization anchor raw bytes",
                                        under: TASK_EVIDENCE_ROOT)
      invocation_bytes = artifact_identity!(root, derivation["invocation"],
                                            "P3 MTRO invocation raw bytes",
                                            under: TASK_EVIDENCE_ROOT)
      {
        "fixed_action" => derivation["fixed_action"],
        "agent_arguments" => derivation["agent_arguments"],
        "host_derived_fields" => derivation["host_derived_fields"],
        "authorization_anchor_sha256" => Digest::SHA256.hexdigest(anchor_bytes),
        "invocation_sha256" => Digest::SHA256.hexdigest(invocation_bytes),
        "truncated_identity_authoritative" => derivation["truncated_identity_authoritative"]
      }
    when "SOURCE_TO_CLASS_CUSTODY"
      bindings = payloads.call("CANDIDATE_MANIFEST_BINDING")
      mappings = payloads.call("SOURCE_CLASS_MAPPING")
      assert(bindings.length == 1 && !mappings.empty? && events.length == mappings.length + 1,
             "P3 MTRO source-to-class raw event cardinality drift")
      binding = exact_keys(bindings.first, %w[candidate_manifest changed_paths], fact_id)
      mappings.each do |mapping|
        mapping = exact_keys(mapping, %w[source_path class_artifact], fact_id)
        assert(binding["changed_paths"].include?(mapping["source_path"]) &&
               mapping["source_path"].end_with?(".java"),
               "P3 MTRO source-to-class raw source path drift")
        class_bytes = artifact_identity!(root, mapping["class_artifact"],
                                         "P3 MTRO compiled class bytes",
                                         under: TASK_EVIDENCE_ROOT)
        assert(class_bytes.start_with?("\xCA\xFE\xBA\xBE".b),
               "P3 MTRO source-to-class artifact is not a JVM class")
      end
      {
        "candidate_manifest" => binding["candidate_manifest"],
        "candidate_commit" => candidate["candidate_commit"],
        "candidate_tree" => candidate["candidate_tree"],
        "changed_paths" => binding["changed_paths"]
      }
    when "CUSTODY_OWNERSHIP_DRIFT_MATRIX"
      cases = payloads.call("CUSTODY_DRIFT_CASE_RESULT").map do |payload|
        exact_keys(payload, %w[case accepted], fact_id)
      end
      file_observations = payloads.call("CUSTODY_FILE_OBSERVATION")
      expected_cases = %w[
        MISSING DUPLICATE CROSS_PROJECT CROSS_OWNER TYPE_DRIFT LEGACY_FALLBACK
        SYMLINK PATH_ESCAPE SIZE_DRIFT SHA256_DRIFT
      ]
      assert(events.length == 11 && cases.map { |item| item["case"] } == expected_cases &&
             cases.all? { |item| item["accepted"] == false } && file_observations.length == 1,
             "P3 MTRO custody raw drift matrix drift")
      observed = exact_keys(
        file_observations.first,
        %w[artifact owner_type custody_mode non_symlink content_addressed], fact_id
      )
      custody_bytes = artifact_identity!(root, observed["artifact"],
                                         "P3 MTRO custody file observation",
                                         under: TASK_EVIDENCE_ROOT)
      custody_path = Pathname.new(observed.dig("artifact", "path"))
      custody_stat = File.lstat(custody_path)
      {
        "rejected_cases" => expected_cases, "false_accepts" => cases.count { |item| item["accepted"] },
        "exact_owner_type" => observed["owner_type"],
        "actual_length_reverified" => custody_bytes.bytesize == observed.dig("artifact", "byte_length"),
        "actual_sha256_reverified" => Digest::SHA256.hexdigest(custody_bytes) ==
          observed.dig("artifact", "sha256"),
        "custody_mode" => format("%04o", custody_stat.mode & 0o7777),
        "non_symlink" => !custody_stat.symlink? && observed["non_symlink"],
        "content_addressed" => observed["content_addressed"] &&
          custody_path.to_s.include?(observed.dig("artifact", "sha256"))
      }
    when "REAL_MYSQL_V034_APPLIED"
      assert(events.map { |event| event["event_type"] } == ["MYSQL_SCHEMA_QUERY"],
             "P3 MTRO MySQL raw event sequence drift")
      query = exact_keys(events.first["payload"],
                         %w[query_output mysql_container_id loopback_port spring_transaction_proxy], fact_id)
      query_bytes = artifact_identity!(root, query["query_output"], "P3 MTRO MySQL schema query",
                                       under: TASK_EVIDENCE_ROOT)
      query_result = exact_keys(
        parse_closed_json(query_bytes, "P3 MTRO MySQL schema query"),
        %w[engine migration tables flyway_status], "P3 MTRO MySQL schema query"
      )
      {
        "migration" => query_result["migration"], "table_count" => query_result["tables"].length,
        "real_mysql" => query_result["engine"] == "MYSQL",
        "spring_transaction_proxy" => query["spring_transaction_proxy"],
        "flyway_status" => query_result["flyway_status"],
        "mysql_container_id" => query["mysql_container_id"],
        "loopback_port" => query["loopback_port"]
      }
    when "SPRING_AOP_TRANSACTION_ROLLBACK"
      operations = payloads.call("TRANSACTION_OPERATION").map do |payload|
        exact_keys(payload, %w[operation requires_new jdbc_store parent_row_lock], fact_id)
      end
      snapshots = payloads.call("ROLLBACK_SNAPSHOT")
      assert(events.length == 6 && operations.map { |item| item["operation"] } == %w[
               prepareIntent claimDispatch recordEffect beginCleanup completeTerminal
             ] && snapshots.length == 1, "P3 MTRO Spring transaction raw sequence drift")
      snapshot = exact_keys(snapshots.first, %w[before_intent_count after_intent_count], fact_id)
      {
        "operations" => operations.map { |item| item["operation"] },
        "requires_new" => operations.all? { |item| item["requires_new"] },
        "jdbc_store" => operations.all? { |item| item["jdbc_store"] },
        "parent_row_lock" => operations.all? { |item| item["parent_row_lock"] },
        "prepare_rollback" => snapshot["before_intent_count"] == 0 &&
          snapshot["after_intent_count"] == 0 ?
          "PASS_ZERO_DURABLE_INTENT" : "NON_PASS",
        "result" => operations.all? { |item| item.values_at("requires_new", "jdbc_store", "parent_row_lock").all? } ?
          "PASS" : "NON_PASS"
      }
    when "DURABLE_INTENT_CAS_TERMINAL"
      transitions = payloads.call("STATE_TRANSITION").map do |payload|
        exact_keys(payload, %w[from to cas_applied], fact_id)
      end
      properties = exact_keys(payloads.call("CAS_PROPERTIES").fetch(0), %w[
                                immutable_identity_fields conditional_updates version_cas
                                effect_outside_transaction
                              ], fact_id)
      terminal = exact_keys(payloads.call("TERMINAL_ROW_COUNT").fetch(0), %w[count], fact_id)
      statuses = transitions.flat_map { |transition| [transition["from"], transition["to"]] }.compact.uniq
      assert(events.length == transitions.length + 2 && transitions.all? { |item| item["cas_applied"] },
             "P3 MTRO durable CAS raw transition drift")
      properties.merge(
        "statuses" => statuses, "terminal_count" => terminal["count"],
        "result" => statuses == PRODUCT_ARCHITECTURE.fetch("allowed_statuses") &&
          terminal["count"] == 1 ? "PASS" : "NON_PASS"
      )
    when "IDENTICAL_TERMINAL_REPLAY_LATE_LOSER"
      attempts = payloads.call("TERMINAL_ATTEMPT").map do |payload|
        exact_keys(payload, %w[kind result winner_sha256], fact_id)
      end
      assert(events.length == 3 && attempts.map { |item| item["kind"] } ==
             %w[WINNER IDENTICAL_REPLAY CONFLICTING_LATE_LOSER],
             "P3 MTRO terminal replay raw attempt order drift")
      assert(attempts.all? { |item| item["winner_sha256"].is_a?(String) &&
             item["winner_sha256"].match?(/\A[0-9a-f]{64}\z/) },
             "P3 MTRO terminal replay winner SHA-256 drift")
      {
        "identical_replay" => attempts[1]["result"],
        "conflicting_late_loser" => attempts[2]["result"],
        "winner_unchanged" => attempts.map { |item| item["winner_sha256"] }.uniq.length == 1,
        "result" => attempts[0]["result"] == "ACCEPTED" &&
          attempts[1]["result"] == "IDEMPOTENT" && attempts[2]["result"] == "REJECTED" ?
          "PASS" : "NON_PASS"
      }
    when "FRESH_PROCESS_WINDOW_INTENT", "FRESH_PROCESS_WINDOW_EFFECT",
         "FRESH_PROCESS_WINDOW_CLEANUP"
      assert(events.map { |event| event["event_type"] } == %w[
               PROCESS_START RECOVERY_ENUMERATION RECOVERY_RESULT
             ], "P3 MTRO fresh-process raw event sequence drift")
      process = exact_keys(payloads.call("PROCESS_START").first,
                           %w[pid start_time argv window fresh_process], fact_id)
      enumeration = exact_keys(
        payloads.call("RECOVERY_ENUMERATION").first,
        %w[startup_global_enumeration caller_task_id_required machine_wide_jvm_discovery], fact_id
      )
      result = exact_keys(payloads.call("RECOVERY_RESULT").first, %w[exit_code], fact_id)
      expected_window = {
        "FRESH_PROCESS_WINDOW_INTENT" => "INTENT_COMMITTED_EFFECT_NOT_BEGUN",
        "FRESH_PROCESS_WINDOW_EFFECT" => "EFFECT_MAY_HAVE_OCCURRED_TERMINAL_NOT_COMMITTED",
        "FRESH_PROCESS_WINDOW_CLEANUP" => "CLEANUP_BEGUN_OR_COMPLETED_TERMINAL_NOT_COMMITTED"
      }.fetch(fact_id)
      assert(process["pid"].is_a?(Integer) && process["pid"] > 0 &&
             process["start_time"].is_a?(Integer) && process["start_time"] > 0 &&
             process["argv"].is_a?(Array) && !process["argv"].empty? &&
             process["window"] == expected_window,
             "P3 MTRO fresh-process raw process identity drift")
      {
        "window" => process["window"], "fresh_process" => process["fresh_process"],
        "startup_global_enumeration" => enumeration["startup_global_enumeration"],
        "caller_task_id_required" => enumeration["caller_task_id_required"],
        "machine_wide_jvm_discovery" => enumeration["machine_wide_jvm_discovery"],
        "result" => result["exit_code"] == 0 && process["fresh_process"] &&
          enumeration["startup_global_enumeration"] &&
          enumeration["caller_task_id_required"] == false &&
          enumeration["machine_wide_jvm_discovery"] == false ? "PASS" : "NON_PASS"
      }
    when "CHECKPOINT_BEFORE_TERMINAL_REJECTED"
      assert(events.map { |event| event["event_type"] } == %w[
               TERMINAL_STATE CHECKPOINT_ATTEMPT CHECKPOINT_ROW_COUNT
             ], "P3 MTRO pre-terminal checkpoint raw sequence drift")
      terminal = exact_keys(payloads.call("TERMINAL_STATE").first, %w[committed], fact_id)
      attempt = exact_keys(payloads.call("CHECKPOINT_ATTEMPT").first, %w[result], fact_id)
      rows = exact_keys(payloads.call("CHECKPOINT_ROW_COUNT").first, %w[count], fact_id)
      {
        "terminal_committed" => terminal["committed"],
        "checkpoint_attempt" => attempt["result"], "checkpoint_count" => rows["count"],
        "result" => terminal["committed"] == false && attempt["result"] == "REJECTED" &&
          rows["count"] == 0 ? "PASS" : "NON_PASS"
      }
    when "CHECKPOINT_AFTER_TERMINAL_EXACTLY_ONCE"
      assert(events.map { |event| event["event_type"] } == %w[
               TERMINAL_STATE CHECKPOINT_ATTEMPT REPEATED_RECOVERY CHECKPOINT_ROW_COUNT
             ], "P3 MTRO post-terminal checkpoint raw sequence drift")
      terminal = exact_keys(payloads.call("TERMINAL_STATE").first, %w[committed], fact_id)
      attempt = exact_keys(payloads.call("CHECKPOINT_ATTEMPT").first, %w[result], fact_id)
      repeated = exact_keys(payloads.call("REPEATED_RECOVERY").first, %w[result], fact_id)
      rows = exact_keys(payloads.call("CHECKPOINT_ROW_COUNT").first, %w[count], fact_id)
      {
        "terminal_committed" => terminal["committed"], "first_checkpoint" => attempt["result"],
        "repeated_recovery" => repeated["result"], "checkpoint_count" => rows["count"],
        "p3_001_semantics" => rows["count"] == 1 ? "EXACTLY_ONCE" : "VIOLATED",
        "result" => terminal["committed"] && attempt["result"] == "ACCEPTED" &&
          repeated["result"] == "IDEMPOTENT" && rows["count"] == 1 ? "PASS" : "NON_PASS"
      }
    when "PINNED_OCI_PROFILE"
      assert(events.map { |event| event["event_type"] } == ["DOCKER_CREATE_COMMAND"],
             "P3 MTRO pinned OCI raw event sequence drift")
      command = exact_keys(events.first["payload"],
                           %w[argv task_activation_record prewrite_oci_probe], fact_id)
      argv = array(command["argv"], "P3 MTRO pinned OCI argv")
      assert(argv.length == 31 && argv.values_at(0, 1, 2, 3) == [
               DOCKER_CLI.fetch("path"), "--host", DOCKER_ENDPOINT, "create"
             ] && argv.values_at(4, 6, 8, 10, 12, 14, 15, 17, 19, 21, 23, 25, 27) == [
               "--name", "--label", "--label", "--user", "--network", "--read-only",
               "--cap-drop", "--security-opt", "--cpus", "--memory", "--pids-limit",
               "--mount", "--entrypoint"
             ] && argv.values_at(11, 13, 16, 18, 20, 22, 24, 28, 29, 30) == [
               "65534:65534", "none", "ALL", "no-new-privileges", "1", "256m", "64",
               "/usr/bin/sha256sum", IMAGE_ID, "/input/custody.bin"
             ], "P3 MTRO pinned OCI create argv shape drift")
      invocation_match = argv[5].match(/\Asourcelens-mtro-([0-9a-f]{64})\z/)
      assert(invocation_match && argv[7] == "com.sourcelens.task_id=#{TASK_ID}" &&
             argv[9] == "com.sourcelens.invocation_sha256=#{invocation_match[1]}",
             "P3 MTRO pinned OCI name or labels drift")
      mount_match = argv[26].match(
        /\Atype=bind,source=(\/[^,]+),target=\/input\/custody\.bin,readonly\z/
      )
      assert(mount_match, "P3 MTRO pinned OCI mount syntax drift")
      custody_path = literal_path!(Pathname.new(mount_match[1]),
                                   "P3 MTRO pinned OCI custody mount", directory: false)
      custody_bytes = File.binread(custody_path)
      custody_sha256 = Digest::SHA256.hexdigest(custody_bytes)
      assert(custody_path.to_s.start_with?("#{TASK_EVIDENCE_ROOT}/") &&
             format("%04o", File.lstat(custody_path).mode & 0o7777) == "0444" &&
             custody_path.to_s.include?(custody_sha256),
             "P3 MTRO pinned OCI custody mount is not read-only content-addressed Evidence")
      {
        "docker_cli" => DOCKER_CLI, "docker_endpoint" => DOCKER_ENDPOINT,
        "image_content_id" => IMAGE_ID, "entrypoint" => "/usr/bin/sha256sum",
        "arguments" => ["/input/custody.bin"], "user" => "65534:65534", "network" => "none",
        "read_only_rootfs" => argv.include?("--read-only"), "cap_drop" => "ALL",
        "no_new_privileges" => argv.include?("no-new-privileges"),
        "bounded_resources" => %w[--cpus --memory --pids-limit].all? { |token| argv.include?(token) },
        "mount" => validate_decision!(root).dig(
          "local_external_effect_authority", "action_container", "mount"
        ), "task_activation_record" => command["task_activation_record"],
        "prewrite_oci_probe" => command["prewrite_oci_probe"]
      }
    when "OCI_RAW_STDOUT_STDERR_EXIT"
      assert(events.map { |event| event["event_type"] } == ["OCI_PROCESS_CAPTURE"],
             "P3 MTRO OCI process raw event sequence drift")
      capture = exact_keys(events.first["payload"],
                           %w[stdout stderr inspect logs exit_code expected_sha256], fact_id)
      stdout_bytes = artifact_identity!(root, capture["stdout"], "P3 MTRO OCI stdout raw",
                                        under: TASK_EVIDENCE_ROOT)
      output = stdout_bytes.match(/\A([0-9a-f]{64})  \/input\/custody\.bin\n\z/)
      capture.merge("output_sha256" => output && output[1])
    when "OCI_CLEANUP_ABSENCE"
      steps = payloads.call("OCI_LIFECYCLE_STEP").map do |payload|
        exact_keys(payload, %w[step], fact_id).fetch("step")
      end
      inventory_events = payloads.call("OCI_INVENTORY")
      assert(steps == %w[create start wait inspect logs rm absence] && inventory_events.length == 1 &&
             events.length == 8, "P3 MTRO OCI cleanup raw lifecycle drift")
      inventory = exact_keys(inventory_events.first, %w[before after], fact_id)
      before_bytes = artifact_identity!(root, inventory["before"], "P3 MTRO OCI inventory before",
                                        under: TASK_EVIDENCE_ROOT)
      after_bytes = artifact_identity!(root, inventory["after"], "P3 MTRO OCI inventory after",
                                       under: TASK_EVIDENCE_ROOT)
      before = exact_keys(parse_closed_json(before_bytes, "P3 MTRO OCI inventory before"),
                          %w[task_object_ids foreign_object_ids pinned_image_present], fact_id)
      after = exact_keys(parse_closed_json(after_bytes, "P3 MTRO OCI inventory after"),
                         %w[task_object_ids foreign_object_ids pinned_image_present], fact_id)
      {
        "lifecycle" => steps, "exact_task_objects_absent" => after["task_object_ids"] == [],
        "foreign_objects_unchanged" => before["foreign_object_ids"] == after["foreign_object_ids"],
        "pinned_image_retained" => before["pinned_image_present"] && after["pinned_image_present"]
      }
    when "HOST_INDEPENDENT_SHA_MATCH"
      assert(events.map { |event| event["event_type"] } == ["HOST_SHA_CAPTURE"],
             "P3 MTRO Host SHA raw event sequence drift")
      capture = exact_keys(events.first["payload"], %w[artifact host_stdout oci_stdout], fact_id)
      artifact_bytes = artifact_identity!(root, capture["artifact"], "P3 MTRO actual artifact bytes",
                                          under: TASK_EVIDENCE_ROOT)
      host_bytes = artifact_identity!(root, capture["host_stdout"], "P3 MTRO Host SHA stdout",
                                      under: TASK_EVIDENCE_ROOT)
      oci_bytes = artifact_identity!(root, capture["oci_stdout"], "P3 MTRO OCI SHA stdout",
                                     under: TASK_EVIDENCE_ROOT)
      host = host_bytes.match(/\A([0-9a-f]{64})\n\z/)
      oci = oci_bytes.match(/\A([0-9a-f]{64})  \/input\/custody\.bin\n\z/)
      actual = Digest::SHA256.hexdigest(artifact_bytes)
      {
        "actual_artifact_sha256" => actual, "host_sha256" => host && host[1],
        "oci_sha256" => oci && oci[1],
        "exact_match" => host && oci && actual == host[1] && actual == oci[1]
      }
    else
      assert(false, "P3 MTRO has no raw-event derivation for #{fact_id}")
    end
  end

  def validate_fact_event_trace!(
    root:, identity:, fact_id:, candidate:, activation_identity:, run_id:
  )
    label = "P3 MTRO #{fact_id} raw event trace"
    bytes = artifact_identity!(root, identity, label, under: TASK_EVIDENCE_ROOT)
    trace = exact_keys(
      parse_closed_json(bytes, label),
      %w[
        schema_version record_type status task_id route_id execution_nonce authorization_id
        candidate_commit candidate_tree task_activation_record run_id fact_id events attachments
        created_at_utc
      ],
      label
    )
    events = array(trace["events"], "#{label} events")
    assert(events.length >= 2, "#{label} lacks a begin and fact observation")
    previous_hash = "0" * 64
    events.each_with_index do |event, index|
      event = exact_keys(
        event, %w[sequence event_type payload previous_event_sha256 event_sha256],
        "#{label} event #{index + 1}"
      )
      assert(event["sequence"] == index + 1 && event["event_type"].is_a?(String) &&
             !event["event_type"].empty? && event["payload"].is_a?(Hash) &&
             event["previous_event_sha256"] == previous_hash,
             "#{label} event order or chain input drift")
      material = {
        "sequence" => event["sequence"], "event_type" => event["event_type"],
        "payload" => event["payload"],
        "previous_event_sha256" => event["previous_event_sha256"]
      }
      expected_hash = Digest::SHA256.hexdigest(JSON.generate(material))
      assert(event["event_sha256"] == expected_hash, "#{label} event hash drift")
      previous_hash = expected_hash
    end
    assert(events.first["event_type"] == "RUN_BEGIN" &&
           events.first["payload"] == {"fact_id" => fact_id} &&
           events.last["event_type"] == "FACT_OBSERVATION" &&
           events.last["payload"].is_a?(Hash) && !events.last["payload"].empty?,
           "#{label} begin or terminal observation event drift")
    projection = derive_fact_projection!(
      root: root, fact_id: fact_id, events: events[1...-1], candidate: candidate,
      activation_identity: activation_identity
    )
    assert(events.last.fetch("payload") == projection,
           "#{label} terminal claim differs from raw-event derivation")
    attachments = array(trace["attachments"], "#{label} attachments")
    expected_attachments = nested_artifact_identities(
      events[1...-1].map { |event| event.fetch("payload") }
    ).uniq
    assert(attachments == expected_attachments,
           "#{label} attachment inventory is not derived from its observation payload")
    attachments.each do |attachment|
      artifact_identity!(root, attachment, "#{label} attachment", under: TASK_EVIDENCE_ROOT)
    end
    assert(trace["schema_version"] == "p3-mtro-fact-event-trace/v1" &&
           trace["record_type"] == "P3_MTRO_FACT_EVENT_TRACE" &&
           trace["status"] == "CAPTURED" && trace["task_id"] == TASK_ID &&
           trace["route_id"] == ROUTE_ID &&
           trace["execution_nonce"] == candidate["execution_nonce"] &&
           trace["authorization_id"] == candidate["authorization_id"] &&
           trace["candidate_commit"] == candidate["candidate_commit"] &&
           trace["candidate_tree"] == candidate["candidate_tree"] &&
           trace["task_activation_record"] == activation_identity &&
           trace["run_id"] == run_id && trace["fact_id"] == fact_id,
           "#{label} authority drift")
    Time.iso8601(trace.fetch("created_at_utc"))
    {
      "projection" => projection, "trace_identity" => identity, "attachments" => attachments,
      "events" => events
    }
  end

  def validate_mtro_oci_inspect!(inspect_bytes:, argv:, exit_code:)
    inspect = parse_closed_json(inspect_bytes, "P3 MTRO OCI captured inspect")
    assert(inspect.is_a?(Array) && inspect.length == 1 && inspect.first.is_a?(Hash),
           "P3 MTRO OCI inspect is not a single container object")
    assert(argv.is_a?(Array) && argv.length == 31,
           "P3 MTRO OCI inspect cannot bind an invalid create argv")
    object = inspect.first
    container_name = argv.fetch(5)
    invocation_sha256 = container_name.delete_prefix("sourcelens-mtro-")
    mount_source = argv.fetch(26).match(
      /\Atype=bind,source=(\/[^,]+),target=\/input\/custody\.bin,readonly\z/
    )&.[](1)
    labels = object.dig("Config", "Labels")
    host = object["HostConfig"]
    mounts = object["Mounts"]
    assert(object["Id"].is_a?(String) && object["Id"].match?(/\A[0-9a-f]{64}\z/) &&
           object["Name"] == "/#{container_name}" && object["Image"] == IMAGE_ID &&
           object.dig("Config", "Image") == IMAGE_ID &&
           labels.is_a?(Hash) && labels["com.sourcelens.task_id"] == TASK_ID &&
           labels["com.sourcelens.invocation_sha256"] == invocation_sha256 &&
           object.dig("Config", "User") == "65534:65534" &&
           object.dig("Config", "Entrypoint") == ["/usr/bin/sha256sum"] &&
           object.dig("Config", "Cmd") == ["/input/custody.bin"],
           "P3 MTRO OCI inspect identity, image, labels or command drift")
    assert(host.is_a?(Hash) && host["Privileged"] == false &&
           [nil, []].include?(host["Binds"]) && [nil, []].include?(host["CapAdd"]) &&
           host["NetworkMode"] == "none" && host["ReadonlyRootfs"] == true &&
           host["Memory"] == 268_435_456 && host["NanoCpus"] == 1_000_000_000 &&
           host["PidsLimit"] == 64 && host["CapDrop"] == ["ALL"] &&
           [["no-new-privileges"], ["no-new-privileges:true"]].include?(host["SecurityOpt"]),
           "P3 MTRO OCI inspect isolation or resource profile drift")
    assert(mount_source && mounts.is_a?(Array) && mounts.length == 1 &&
           mounts.first.is_a?(Hash) && mounts.first["Type"] == "bind" &&
           mounts.first["Source"] == mount_source &&
           mounts.first["Destination"] == "/input/custody.bin" &&
           mounts.first["RW"] == false && object.dig("State", "ExitCode") == exit_code,
           "P3 MTRO OCI inspect mount or process state drift")
    object
  end

  def validate_observation_record!(root:, identity:, group:, candidate:, activation_identity:)
    spec = OBSERVATION_RECORD_SPECS.fetch(group)
    bytes = artifact_identity!(
      root, identity, "P3 MTRO #{group} observation", under: TASK_EVIDENCE_ROOT
    )
    record = exact_keys(
      parse_closed_json(bytes, "P3 MTRO #{group} observation"),
      %w[
        schema_version record_type status task_id route_id execution_nonce authorization_id
        candidate_commit candidate_tree task_activation_record run_id covered_fact_ids
        observations raw_artifacts created_at_utc
      ],
      "P3 MTRO #{group} observation"
    )
    observations = exact_keys(record["observations"], spec.fetch("facts"),
                              "P3 MTRO #{group} observations")
    raw_artifacts = exact_keys(record["raw_artifacts"], spec.fetch("facts"),
                               "P3 MTRO #{group} raw artifacts")
    assert(record["schema_version"] == spec.fetch("schema_version") &&
           record["record_type"] == spec.fetch("record_type") && record["status"] == "PASS" &&
           record["task_id"] == TASK_ID && record["route_id"] == ROUTE_ID &&
           record["execution_nonce"] == candidate["execution_nonce"] &&
           record["authorization_id"] == candidate["authorization_id"] &&
           record["candidate_commit"] == candidate["candidate_commit"] &&
           record["candidate_tree"] == candidate["candidate_tree"] &&
           record["task_activation_record"] == activation_identity &&
           record["run_id"].is_a?(String) &&
           record["run_id"].match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/) &&
           record["covered_fact_ids"] == spec.fetch("facts"),
           "P3 MTRO #{group} observation authority or coverage drift")
    Time.iso8601(record.fetch("created_at_utc"))
    derived = {}
    derivation_artifacts = []
    trace_events = {}
    spec.fetch("facts").each do |fact_id|
      trace_result = validate_fact_event_trace!(
        root: root, identity: raw_artifacts.fetch(fact_id), fact_id: fact_id,
        candidate: candidate, activation_identity: activation_identity, run_id: record["run_id"]
      )
      derived[fact_id] = trace_result.fetch("projection")
      trace_events[fact_id] = trace_result.fetch("events")
      derivation_artifacts << trace_result.fetch("trace_identity")
      derivation_artifacts.concat(trace_result.fetch("attachments"))
    end
    assert(observations == derived,
           "P3 MTRO #{group} observation is not mechanically projected from raw event traces")
    if group == "oci_lifecycle"
      raw = derived.fetch("OCI_RAW_STDOUT_STDERR_EXIT")
      stdout_bytes = artifact_identity!(root, raw.fetch("stdout"),
                                        "P3 MTRO OCI captured stdout", under: TASK_EVIDENCE_ROOT)
      stderr_bytes = artifact_identity!(root, raw.fetch("stderr"),
                                        "P3 MTRO OCI captured stderr", under: TASK_EVIDENCE_ROOT)
      inspect_bytes = artifact_identity!(root, raw.fetch("inspect"),
                                         "P3 MTRO OCI captured inspect", under: TASK_EVIDENCE_ROOT)
      logs_bytes = artifact_identity!(root, raw.fetch("logs"),
                                      "P3 MTRO OCI captured logs", under: TASK_EVIDENCE_ROOT)
      stdout_match = stdout_bytes.match(/\A([0-9a-f]{64})  \/input\/custody\.bin\n\z/)
      pinned_command = trace_events.fetch("PINNED_OCI_PROFILE").first.fetch("payload")
      validate_mtro_oci_inspect!(
        inspect_bytes: inspect_bytes, argv: pinned_command.fetch("argv"),
        exit_code: raw.fetch("exit_code")
      )
      assert(stdout_match && raw["output_sha256"] == stdout_match[1] &&
             raw["expected_sha256"] == stdout_match[1] && raw["exit_code"] == 0 &&
             stderr_bytes.empty? && logs_bytes == stdout_bytes,
             "P3 MTRO OCI fact is not derived from stdout, stderr, inspect and logs")
      host_match = derived.fetch("HOST_INDEPENDENT_SHA_MATCH")
      assert(%w[actual_artifact_sha256 host_sha256 oci_sha256].all? { |key|
               host_match[key] == stdout_match[1]
             } && host_match["exact_match"] == true,
             "P3 MTRO Host/OCI SHA fact is not derived from captured OCI stdout")
    end
    {"record" => record, "derivation_artifacts" => derivation_artifacts.uniq}
  end

  def validate_maven_run_receipt!(root:, identity:, kind:, candidate:, activation_identity:)
    label = "P3 MTRO #{kind} Maven receipt"
    bytes = artifact_identity!(root, identity, label, under: TASK_EVIDENCE_ROOT)
    receipt = exact_keys(
      parse_closed_json(bytes, label),
      %w[
        schema_version record_type status receipt_kind task_id route_id execution_nonce
        authorization_id candidate_commit candidate_tree task_activation_record run_id cwd argv
        jdk_major sandbox selector observation_records junit_reports passed_test_cases
        tests failures errors skipped
        stdout stderr exit_code started_at_utc finished_at_utc
      ],
      label
    )
    expected_observation_keys = kind == "FOCUSED_MAVEN" ? OBSERVATION_RECORD_SPECS.keys : []
    observation_records = exact_keys(
      receipt["observation_records"], expected_observation_keys, "#{label} observation records"
    )
    observation_records.each do |group, observation_identity|
      exact_keys(observation_identity, %w[path byte_length sha256], "#{label} #{group} identity")
    end
    reports = array(receipt["junit_reports"], "#{label} JUnit reports")
    assert(!reports.empty? && reports.uniq.length == reports.length,
           "#{label} JUnit report inventory is empty or duplicated")
    totals = {"tests" => 0, "failures" => 0, "errors" => 0, "skipped" => 0}
    passed_test_cases = []
    reports.each do |report_identity|
      report_bytes = artifact_identity!(root, report_identity, "#{label} JUnit XML",
                                        under: TASK_EVIDENCE_ROOT)
      document = REXML::Document.new(report_bytes)
      suite = document.root
      assert(suite && suite.name == "testsuite", "#{label} JUnit XML root drift")
      totals.each_key do |key|
        value = suite.attributes[key]
        assert(value.is_a?(String) && value.match?(/\A\d+\z/),
               "#{label} JUnit #{key} is invalid")
        totals[key] += Integer(value, 10)
      end
      suite.elements.each("testcase") do |testcase|
        classname = testcase.attributes["classname"]
        name = testcase.attributes["name"]
        assert(classname.is_a?(String) && !classname.empty? &&
               name.is_a?(String) && !name.empty?, "#{label} JUnit testcase identity drift")
        failed = testcase.elements["failure"] || testcase.elements["error"] ||
          testcase.elements["skipped"]
        passed_test_cases << "#{classname}##{name}" unless failed
      end
    rescue REXML::ParseException => e
      raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
            "#{label} JUnit XML invalid: #{e.message}"
    end
    stdout_bytes = artifact_identity!(root, receipt["stdout"], "#{label} stdout",
                                      under: TASK_EVIDENCE_ROOT)
    artifact_identity!(root, receipt["stderr"], "#{label} stderr", under: TASK_EVIDENCE_ROOT)
    started = Time.iso8601(receipt.fetch("started_at_utc"))
    finished = Time.iso8601(receipt.fetch("finished_at_utc"))
    sandbox = exact_keys(
      receipt["sandbox"], %w[path sha256 network_policy], "#{label} sandbox"
    )
    argv = array(receipt["argv"], "#{label} argv")
    selector = kind == "FOCUSED_MAVEN" ? FACT_TEST_CASES.values : ["ALL_BACKEND_SPRING_TESTS"]
    selector_sha256 = Digest::SHA256.hexdigest(JSON.generate(selector))
    assert(receipt["schema_version"] == "p3-mtro-run-receipt/v1" &&
           receipt["record_type"] == "P3_MTRO_RUN_RECEIPT" && receipt["status"] == "PASS" &&
           receipt["receipt_kind"] == kind && receipt["task_id"] == TASK_ID &&
           receipt["route_id"] == ROUTE_ID &&
           receipt["execution_nonce"] == candidate["execution_nonce"] &&
           receipt["authorization_id"] == candidate["authorization_id"] &&
           receipt["candidate_commit"] == candidate["candidate_commit"] &&
           receipt["candidate_tree"] == candidate["candidate_tree"] &&
           receipt["task_activation_record"] == activation_identity &&
           receipt["run_id"].is_a?(String) &&
           receipt["run_id"].match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/) &&
           receipt["cwd"] == TASK_WORKTREE && argv.all? { |arg| arg.is_a?(String) && !arg.empty? } &&
           !argv.empty? && (argv.include?("--offline") || argv.include?("-o")) &&
           argv.include?("-Dsourcelens.mtro.selector.sha256=#{selector_sha256}") &&
           receipt["jdk_major"] == 17 && sandbox == {
             "path" => "/usr/bin/sandbox-exec",
             "sha256" => "7fc7dcd7782e1abd52b11f6c512bdfb0c09d2502b619c483fdfce554c472352e",
             "network_policy" => "DENY_ALL_EXCEPT_EXACT_TASK_MYSQL_LOOPBACK"
           } && receipt["selector"] == selector &&
           receipt["passed_test_cases"] == passed_test_cases.sort &&
           FACT_TEST_CASES.values.all? { |test_case| passed_test_cases.include?(test_case) } &&
           receipt.slice("tests", "failures", "errors", "skipped") == totals &&
           totals["tests"] > 0 && totals["failures"] == 0 && totals["errors"] == 0 &&
           receipt["exit_code"] == 0 && !stdout_bytes.empty? && started <= finished,
           "#{label} execution or derived JUnit result drift")
    receipt
  end

  def validate_forbidden_effects_receipt!(root:, identity:, candidate:, activation_identity:)
    label = "P3 MTRO forbidden external effects receipt"
    bytes = artifact_identity!(root, identity, label, under: TASK_EVIDENCE_ROOT)
    receipt = exact_keys(
      parse_closed_json(bytes, label),
      %w[
        schema_version record_type status task_id route_id execution_nonce authorization_id
        candidate_commit candidate_tree task_activation_record observation_started_at_utc
        observation_finished_at_utc effects violations observer_artifacts created_at_utc
      ],
      label
    )
    observer_artifacts = array(receipt["observer_artifacts"], "#{label} observer artifacts")
    assert(observer_artifacts.length == 1, "#{label} requires one closed observer trace")
    observer_identity = observer_artifacts.first
    observer_bytes = artifact_identity!(root, observer_identity, "#{label} observer trace",
                                        under: TASK_EVIDENCE_ROOT)
    observer = exact_keys(
      parse_closed_json(observer_bytes, "#{label} observer trace"),
      %w[
        schema_version record_type status task_id route_id candidate_commit candidate_tree
        task_activation_record events observation_started_at_utc observation_finished_at_utc
        created_at_utc
      ],
      "#{label} observer trace"
    )
    decision_effects = validate_decision!(root).fetch("forbidden_external_effects")
    events = array(observer["events"], "#{label} observer events")
    assert(events.length == decision_effects.length, "#{label} observer event cardinality drift")
    derived_effects = {}
    events.each_with_index do |event, index|
      event = exact_keys(event, %w[sequence effect observed raw_artifact],
                         "#{label} observer event #{index + 1}")
      assert(event["sequence"] == index + 1 &&
             event["effect"] == decision_effects.keys[index] &&
             [true, false].include?(event["observed"]),
             "#{label} observer event order or type drift")
      raw_bytes = artifact_identity!(root, event["raw_artifact"],
                                     "#{label} #{event['effect']} raw trace",
                                     under: TASK_EVIDENCE_ROOT)
      raw_result = derive_external_effect_observation!(
        raw_bytes, event["effect"], "#{label} #{event['effect']} raw trace"
      )
      derived_observed = raw_result.fetch("observed")
      assert(event["observed"] == derived_observed,
             "#{label} #{event['effect']} boolean differs from raw observer output")
      derived_effects[event["effect"]] = derived_observed
    end
    observer_started = Time.iso8601(observer.fetch("observation_started_at_utc"))
    observer_finished = Time.iso8601(observer.fetch("observation_finished_at_utc"))
    Time.iso8601(observer.fetch("created_at_utc"))
    assert(observer["schema_version"] == "p3-mtro-external-effect-observer-trace/v1" &&
           observer["record_type"] == "P3_MTRO_EXTERNAL_EFFECT_OBSERVER_TRACE" &&
           observer["status"] == "CAPTURED" && observer["task_id"] == TASK_ID &&
           observer["route_id"] == ROUTE_ID &&
           observer["candidate_commit"] == candidate["candidate_commit"] &&
           observer["candidate_tree"] == candidate["candidate_tree"] &&
           observer["task_activation_record"] == activation_identity &&
           observer_started <= observer_finished,
           "#{label} observer trace authority or interval drift")
    started = Time.iso8601(receipt.fetch("observation_started_at_utc"))
    finished = Time.iso8601(receipt.fetch("observation_finished_at_utc"))
    Time.iso8601(receipt.fetch("created_at_utc"))
    assert(receipt["schema_version"] == "p3-mtro-forbidden-effects-receipt/v1" &&
           receipt["record_type"] == "P3_MTRO_FORBIDDEN_EFFECTS_RECEIPT" &&
           receipt["status"] == "PASS" && receipt["task_id"] == TASK_ID &&
           receipt["route_id"] == ROUTE_ID &&
           receipt["execution_nonce"] == candidate["execution_nonce"] &&
           receipt["authorization_id"] == candidate["authorization_id"] &&
           receipt["candidate_commit"] == candidate["candidate_commit"] &&
           receipt["candidate_tree"] == candidate["candidate_tree"] &&
           receipt["task_activation_record"] == activation_identity &&
           receipt["effects"] == derived_effects &&
           receipt["violations"] == derived_effects.select { |_effect, observed| observed }.keys &&
           receipt["effects"] == decision_effects && receipt["violations"] == [] &&
           started == observer_started && finished == observer_finished && started <= finished,
           "#{label} authority or observed-effect drift")
    receipt
  end

  def derive_external_effect_observation!(bytes, effect, label)
    raw = exact_keys(
        parse_closed_json(bytes, label),
        %w[
          schema_version record_type effect observer argv observed_events
          observation_started_at_utc observation_finished_at_utc
        ],
        label
      )
      raw_events = array(raw["observed_events"], "#{label} observed events")
      raw_started = Time.iso8601(raw.fetch("observation_started_at_utc"))
      raw_finished = Time.iso8601(raw.fetch("observation_finished_at_utc"))
      assert(raw["schema_version"] == "p3-mtro-external-effect-raw-observation/v1" &&
             raw["record_type"] == "P3_MTRO_EXTERNAL_EFFECT_RAW_OBSERVATION" &&
             raw["effect"] == effect &&
             raw["observer"] == "TASK_SCOPED_OS_AND_PROCESS_OBSERVER" &&
             raw["argv"].is_a?(Array) && !raw["argv"].empty? &&
             raw["argv"].all? { |arg| arg.is_a?(String) && !arg.empty? } &&
             raw_events.all? { |observed_event| observed_event.is_a?(String) && !observed_event.empty? } &&
             raw_started <= raw_finished,
             "#{label} raw observer semantics drift")
    {"observed" => !raw_events.empty?, "started_at" => raw_started, "finished_at" => raw_finished}
  end

  def validate_canonical_replay_raw_bundle!(
    root:, identity:, candidate:, activation_identity:, integration_identity:,
    canonical_commit:, canonical_tree:
  )
    label = "P3 MTRO canonical replay raw bundle"
    bytes = artifact_identity!(root, identity, label, under: TASK_EVIDENCE_ROOT)
    bundle = exact_keys(
      parse_closed_json(bytes, label),
      %w[
        schema_version record_type status task_id route_id candidate_commit candidate_tree
        canonical_commit canonical_tree integration_record task_activation_record
        focused_test_receipt full_test_receipt forbidden_external_effects_receipt
        replay_run_id created_at_utc
      ],
      label
    )
    candidate_manifest_bytes = artifact_identity!(
      root, candidate.fetch("manifest"), "P3 MTRO replay candidate manifest",
      under: TASK_EVIDENCE_ROOT
    )
    candidate_manifest = parse_closed_json(candidate_manifest_bytes,
                                           "P3 MTRO replay candidate manifest")
    assert(%w[focused_test_receipt full_test_receipt forbidden_external_effects_receipt].all? { |key|
             bundle[key] != candidate_manifest[key]
           }, "P3 MTRO canonical replay reused pre-integration candidate receipts")
    focused = validate_maven_run_receipt!(
      root: root, identity: bundle["focused_test_receipt"], kind: "FOCUSED_MAVEN",
      candidate: candidate, activation_identity: activation_identity
    )
    OBSERVATION_RECORD_SPECS.each_key do |group|
      observation = validate_observation_record!(
        root: root, identity: focused.fetch("observation_records").fetch(group), group: group,
        candidate: candidate, activation_identity: activation_identity
      )
      assert(observation.fetch("record")["run_id"] == focused["run_id"],
             "P3 MTRO canonical replay observation run drift")
    end
    full = validate_maven_run_receipt!(
      root: root, identity: bundle["full_test_receipt"], kind: "FULL_MAVEN",
      candidate: candidate, activation_identity: activation_identity
    )
    forbidden = validate_forbidden_effects_receipt!(
      root: root, identity: bundle["forbidden_external_effects_receipt"],
      candidate: candidate, activation_identity: activation_identity
    )
    integration_bytes = artifact_identity!(root, integration_identity,
                                           "P3 MTRO replay integration record",
                                           under: TASK_EVIDENCE_ROOT)
    integration = parse_closed_json(integration_bytes, "P3 MTRO replay integration record")
    integrated_at = Time.iso8601(integration.fetch("integrated_at_utc"))
    bundle_created = Time.iso8601(bundle.fetch("created_at_utc"))
    replay_starts = [focused, full].map { |receipt| Time.iso8601(receipt.fetch("started_at_utc")) }
    replay_finishes = [focused, full].map { |receipt| Time.iso8601(receipt.fetch("finished_at_utc")) }
    forbidden_started = Time.iso8601(forbidden.fetch("observation_started_at_utc"))
    forbidden_finished = Time.iso8601(forbidden.fetch("observation_finished_at_utc"))
    assert(bundle["schema_version"] == "p3-mtro-canonical-replay-raw-bundle/v1" &&
           bundle["record_type"] == "P3_MTRO_CANONICAL_REPLAY_RAW_BUNDLE" &&
           bundle["status"] == "PASS" && bundle["task_id"] == TASK_ID &&
           bundle["route_id"] == ROUTE_ID &&
           bundle["candidate_commit"] == candidate["candidate_commit"] &&
           bundle["candidate_tree"] == candidate["candidate_tree"] &&
           bundle["canonical_commit"] == canonical_commit &&
           bundle["canonical_tree"] == canonical_tree &&
           bundle["integration_record"] == integration_identity &&
           bundle["task_activation_record"] == activation_identity &&
           bundle["replay_run_id"] == focused["run_id"] &&
           (replay_starts + [forbidden_started]).all? { |time| time > integrated_at } &&
           (replay_finishes + [forbidden_finished]).all? { |time| time <= bundle_created },
           "P3 MTRO canonical replay raw bundle authority drift")
    bundle
  end

  def validate_acceptance_fact_observations!(
    root:, fact_id:, observations:, raw_evidence:, runtime_records:, runtime_channel:, bundle:
  )
    decision = validate_decision!(root)
    candidate = runtime_records.fetch("candidate_freeze_record")
    activation = runtime_records.fetch("task_activation_record")
    manifest_identity = candidate.fetch("manifest")
    manifest_bytes = artifact_identity!(root, manifest_identity,
                                        "P3 MTRO fact candidate manifest",
                                        under: TASK_EVIDENCE_ROOT)
    manifest = parse_closed_json(manifest_bytes, "P3 MTRO fact candidate manifest")
    focused_identity = manifest.fetch("focused_test_receipt")
    expected_raw_evidence = nil
    available_raw_evidence = []
    observation_group = OBSERVATION_RECORD_SPECS.find do |_group, spec|
      spec.fetch("facts").include?(fact_id)
    end
    if observation_group
      group, = observation_group
      focused = validate_maven_run_receipt!(
        root: root, identity: focused_identity, kind: "FOCUSED_MAVEN",
        candidate: candidate, activation_identity: runtime_channel.fetch("task_activation_record")
      )
      observation_identity = focused.fetch("observation_records").fetch(group)
      record_result = validate_observation_record!(
        root: root, identity: observation_identity, group: group, candidate: candidate,
        activation_identity: runtime_channel.fetch("task_activation_record")
      )
      record = record_result.fetch("record")
      derived_observation = record.fetch("observations").fetch(fact_id).merge(
        "evidence" => record.fetch("raw_artifacts").fetch(fact_id)
      )
      derived_observation["source_to_class_evidence"] = observation_identity if
        fact_id == "SOURCE_TO_CLASS_CUSTODY"
      assert(record["run_id"] == focused["run_id"] && derived_observation == observations,
             "P3 MTRO #{fact_id} is not derived from its typed observation record")
      if group == "source_custody"
        assert(observation_identity == manifest["source_to_class_evidence"],
               "P3 MTRO source-custody observation differs from candidate custody Evidence")
        expected_raw_evidence = [manifest_identity, observation_identity, focused_identity]
      else
        expected_raw_evidence = [observation_identity, focused_identity]
      end
      available_raw_evidence = expected_raw_evidence +
        record_result.fetch("derivation_artifacts") +
        [focused.fetch("stdout"), focused.fetch("stderr")] + focused.fetch("junit_reports")
    elsif %w[FOCUSED_MAVEN_TESTS FULL_MAVEN_TESTS].include?(fact_id)
      kind = fact_id == "FOCUSED_MAVEN_TESTS" ? "FOCUSED_MAVEN" : "FULL_MAVEN"
      receipt_identity = kind == "FOCUSED_MAVEN" ? focused_identity : manifest.fetch("full_test_receipt")
      receipt = validate_maven_run_receipt!(
        root: root, identity: receipt_identity, kind: kind, candidate: candidate,
        activation_identity: runtime_channel.fetch("task_activation_record")
      )
      expected_raw_evidence = [receipt_identity]
      available_raw_evidence = expected_raw_evidence + [receipt.fetch("stdout"), receipt.fetch("stderr")] +
        receipt.fetch("junit_reports")
    elsif fact_id == "ZERO_FORBIDDEN_EXTERNAL_EFFECTS"
      receipt_identity = manifest.fetch("forbidden_external_effects_receipt")
      receipt = validate_forbidden_effects_receipt!(
        root: root, identity: receipt_identity, candidate: candidate,
        activation_identity: runtime_channel.fetch("task_activation_record")
      )
      expected_raw_evidence = [receipt_identity]
      available_raw_evidence = expected_raw_evidence + receipt.fetch("observer_artifacts")
    elsif fact_id == "CANONICAL_REPLAY"
      expected_raw_evidence = [
        bundle.fetch("integration"), bundle.fetch("canonical_replay"),
        runtime_records.fetch("canonical_replay_record").fetch("raw_replay_bundle")
      ]
      available_raw_evidence = expected_raw_evidence
    else
      assert(false, "P3 MTRO unknown acceptance fact #{fact_id.inspect}")
    end
    assert(raw_evidence == expected_raw_evidence,
           "P3 MTRO #{fact_id} raw Evidence set is not the exact typed derivation plan")
    raw_includes = lambda do |identity, label|
      assert(identity.is_a?(Hash) && available_raw_evidence.include?(identity),
             "P3 MTRO #{fact_id} does not derive #{label} from typed raw Evidence")
    end

    case fact_id
    when "ACTUAL_AGENT_PRODUCTION_DECODE_RUNTIME_POSITIVE"
      observations = exact_keys(
        observations,
        %w[
          agent_task_type runtime_entrypoint production_decode_path tool_call_count
          agent_authority_bearing_fields terminal_projection intent_count dispatch_count
          docker_effect_count evidence
        ], fact_id
      )
      assert(observations == {
               "agent_task_type" => FIXED_ACTION.fetch("agent_task_type"),
               "runtime_entrypoint" => "AgentRuntime",
               "production_decode_path" => "LlmClient",
               "tool_call_count" => 1,
               "agent_authority_bearing_fields" => [],
               "terminal_projection" => "COMMITTED_TERMINAL_MINIMUM_ONLY",
               "intent_count" => 1,
               "dispatch_count" => 1,
               "docker_effect_count" => 1,
               "evidence" => observations["evidence"]
             }, "P3 MTRO actual-Agent positive-path fact drift")
      raw_includes.call(observations["evidence"], "actual-Agent positive-path Evidence")
    when "MALFORMED_INGRESS_ZERO_EFFECT"
      observations = exact_keys(
        observations,
        %w[cases accepted_case_count intent_count dispatch_count docker_effect_count evidence],
        fact_id
      )
      assert(observations["cases"] == %w[
               NONEMPTY_ARGUMENTS MALFORMED_ARGUMENTS NULL_ARGUMENTS ARRAY_ARGUMENTS
               MULTIPLE_TOOL_CALLS REPEATED_ROUND WRONG_TOOL_NAME
             ] && observations["accepted_case_count"] == 0 &&
             observations["intent_count"] == 0 && observations["dispatch_count"] == 0 &&
             observations["docker_effect_count"] == 0,
             "P3 MTRO malformed-ingress zero-effect fact drift")
      raw_includes.call(observations["evidence"], "malformed-ingress matrix")
    when "EXCLUSIVE_RESERVED_INGRESS_REJECTION"
      observations = exact_keys(
        observations,
        %w[
          reserved_tool_name generic_registry generic_execution generic_docker
          other_tool_call_count second_tool_call_count repeated_round_count evidence
        ], fact_id
      )
      assert(observations["reserved_tool_name"] == FIXED_ACTION.fetch("reserved_tool_name") &&
             observations["generic_registry"] == "REJECTED" &&
             observations["generic_execution"] == "REJECTED" &&
             observations["generic_docker"] == "REJECTED" &&
             observations["other_tool_call_count"] == 0 &&
             observations["second_tool_call_count"] == 0 &&
             observations["repeated_round_count"] == 0,
             "P3 MTRO exclusive reserved-ingress fact drift")
      raw_includes.call(observations["evidence"], "reserved-ingress rejection matrix")
    when "HOST_DERIVED_AUTHORITY_BINDING"
      observations = exact_keys(
        observations,
        %w[
          fixed_action agent_arguments host_derived_fields authorization_anchor_sha256
          invocation_sha256 truncated_identity_authoritative evidence
        ], fact_id
      )
      assert(observations["fixed_action"] == FIXED_ACTION && observations["agent_arguments"] == {} &&
             observations["host_derived_fields"] == %w[
               project_id user_id conversation_id agent_task_id scan_task_id execution_task_id
               artifact_id action_id authorization_anchor custody_identity image executable argv
             ] && observations["authorization_anchor_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
             observations["invocation_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
             observations["truncated_identity_authoritative"] == false,
             "P3 MTRO Host-derived authority fact drift")
      raw_includes.call(observations["evidence"], "Host-derived authority Evidence")
    when "SOURCE_TO_CLASS_CUSTODY"
      observations = exact_keys(
        observations,
        %w[
          candidate_manifest source_to_class_evidence candidate_commit candidate_tree
          changed_paths evidence
        ], fact_id
      )
      assert(observations["candidate_manifest"] == manifest_identity &&
             observations["source_to_class_evidence"] == manifest["source_to_class_evidence"] &&
             observations["candidate_commit"] == candidate["candidate_commit"] &&
             observations["candidate_tree"] == candidate["candidate_tree"] &&
             observations["changed_paths"] == manifest["changed_paths"],
             "P3 MTRO source-to-class custody fact drift")
      raw_includes.call(manifest_identity, "candidate manifest")
      raw_includes.call(manifest["source_to_class_evidence"], "source-to-class Evidence")
      raw_includes.call(observations["evidence"], "source-to-class verifier output")
    when "CUSTODY_OWNERSHIP_DRIFT_MATRIX"
      observations = exact_keys(
        observations,
        %w[
          rejected_cases false_accepts exact_owner_type actual_length_reverified
          actual_sha256_reverified custody_mode non_symlink content_addressed evidence
        ], fact_id
      )
      assert(observations["rejected_cases"] == %w[
               MISSING DUPLICATE CROSS_PROJECT CROSS_OWNER TYPE_DRIFT LEGACY_FALLBACK
               SYMLINK PATH_ESCAPE SIZE_DRIFT SHA256_DRIFT
             ] && observations["false_accepts"] == 0 &&
             observations["exact_owner_type"] == "SCAN_TASK_ARCHITECTURE_OVERVIEW" &&
             observations["actual_length_reverified"] == true &&
             observations["actual_sha256_reverified"] == true &&
             observations["custody_mode"] == "0444" && observations["non_symlink"] == true &&
             observations["content_addressed"] == true,
             "P3 MTRO custody ownership/drift fact drift")
      raw_includes.call(observations["evidence"], "custody ownership/drift matrix")
    when "REAL_MYSQL_V034_APPLIED"
      observations = exact_keys(
        observations,
        %w[
          migration table_count real_mysql spring_transaction_proxy flyway_status
          mysql_container_id loopback_port evidence
        ], fact_id
      )
      assert(observations["migration"] == PRODUCT_ARCHITECTURE.fetch("migration") &&
             observations["table_count"] == 1 && observations["real_mysql"] == true &&
             observations["spring_transaction_proxy"] == true &&
             observations["flyway_status"] == "PASS" &&
             observations["mysql_container_id"] == activation["mysql_container_id"] &&
             observations["loopback_port"] == activation["loopback_port"],
             "P3 MTRO real MySQL V034 fact drift")
      raw_includes.call(observations["evidence"], "real MySQL V034 Evidence")
    when "SPRING_AOP_TRANSACTION_ROLLBACK"
      observations = exact_keys(
        observations,
        %w[operations requires_new jdbc_store parent_row_lock prepare_rollback result evidence],
        fact_id
      )
      assert(observations["operations"] == %w[
               prepareIntent claimDispatch recordEffect beginCleanup completeTerminal
             ] && observations["requires_new"] == true && observations["jdbc_store"] == true &&
             observations["parent_row_lock"] == true &&
             observations["prepare_rollback"] == "PASS_ZERO_DURABLE_INTENT" &&
             observations["result"] == "PASS",
             "P3 MTRO Spring AOP transaction fact drift")
      raw_includes.call(observations["evidence"], "Spring AOP rollback Evidence")
    when "DURABLE_INTENT_CAS_TERMINAL"
      observations = exact_keys(
        observations,
        %w[
          statuses immutable_identity_fields conditional_updates version_cas
          effect_outside_transaction terminal_count result evidence
        ], fact_id
      )
      assert(observations["statuses"] == PRODUCT_ARCHITECTURE.fetch("allowed_statuses") &&
             observations["immutable_identity_fields"] == true &&
             observations["conditional_updates"] == true && observations["version_cas"] == true &&
             observations["effect_outside_transaction"] == true &&
             observations["terminal_count"] == 1 && observations["result"] == "PASS",
             "P3 MTRO durable intent/CAS terminal fact drift")
      raw_includes.call(observations["evidence"], "durable intent/CAS terminal Evidence")
    when "IDENTICAL_TERMINAL_REPLAY_LATE_LOSER"
      observations = exact_keys(
        observations,
        %w[identical_replay conflicting_late_loser winner_unchanged result evidence], fact_id
      )
      assert(observations["identical_replay"] == "IDEMPOTENT" &&
             observations["conflicting_late_loser"] == "REJECTED" &&
             observations["winner_unchanged"] == true && observations["result"] == "PASS",
             "P3 MTRO terminal winner/replay fact drift")
      raw_includes.call(observations["evidence"], "terminal replay/loser Evidence")
    when "FRESH_PROCESS_WINDOW_INTENT", "FRESH_PROCESS_WINDOW_EFFECT",
         "FRESH_PROCESS_WINDOW_CLEANUP"
      observations = exact_keys(
        observations,
        %w[
          window fresh_process startup_global_enumeration caller_task_id_required
          machine_wide_jvm_discovery result evidence
        ], fact_id
      )
      expected_window = {
        "FRESH_PROCESS_WINDOW_INTENT" => "INTENT_COMMITTED_EFFECT_NOT_BEGUN",
        "FRESH_PROCESS_WINDOW_EFFECT" => "EFFECT_MAY_HAVE_OCCURRED_TERMINAL_NOT_COMMITTED",
        "FRESH_PROCESS_WINDOW_CLEANUP" => "CLEANUP_BEGUN_OR_COMPLETED_TERMINAL_NOT_COMMITTED"
      }.fetch(fact_id)
      assert(observations["window"] == expected_window && observations["fresh_process"] == true &&
             observations["startup_global_enumeration"] == true &&
             observations["caller_task_id_required"] == false &&
             observations["machine_wide_jvm_discovery"] == false &&
             observations["result"] == "PASS",
             "P3 MTRO #{fact_id} recovery fact drift")
      raw_includes.call(observations["evidence"], "#{expected_window} raw Evidence")
    when "CHECKPOINT_BEFORE_TERMINAL_REJECTED"
      observations = exact_keys(
        observations,
        %w[terminal_committed checkpoint_attempt checkpoint_count result evidence], fact_id
      )
      assert(observations["terminal_committed"] == false &&
             observations["checkpoint_attempt"] == "REJECTED" &&
             observations["checkpoint_count"] == 0 && observations["result"] == "PASS",
             "P3 MTRO pre-terminal checkpoint fact drift")
      raw_includes.call(observations["evidence"], "pre-terminal checkpoint Evidence")
    when "CHECKPOINT_AFTER_TERMINAL_EXACTLY_ONCE"
      observations = exact_keys(
        observations,
        %w[
          terminal_committed first_checkpoint repeated_recovery checkpoint_count
          p3_001_semantics result evidence
        ], fact_id
      )
      assert(observations["terminal_committed"] == true &&
             observations["first_checkpoint"] == "ACCEPTED" &&
             observations["repeated_recovery"] == "IDEMPOTENT" &&
             observations["checkpoint_count"] == 1 &&
             observations["p3_001_semantics"] == "EXACTLY_ONCE" &&
             observations["result"] == "PASS",
             "P3 MTRO post-terminal checkpoint fact drift")
      raw_includes.call(observations["evidence"], "post-terminal checkpoint Evidence")
    when "PINNED_OCI_PROFILE"
      observations = exact_keys(
        observations,
        %w[
          docker_cli docker_endpoint image_content_id entrypoint arguments user network
          read_only_rootfs cap_drop no_new_privileges bounded_resources mount
          task_activation_record prewrite_oci_probe evidence
        ], fact_id
      )
      assert(observations["docker_cli"] == DOCKER_CLI &&
             observations["docker_endpoint"] == DOCKER_ENDPOINT &&
             observations["image_content_id"] == IMAGE_ID &&
             observations["entrypoint"] == "/usr/bin/sha256sum" &&
             observations["arguments"] == ["/input/custody.bin"] &&
             observations["user"] == "65534:65534" && observations["network"] == "none" &&
             observations["read_only_rootfs"] == true && observations["cap_drop"] == "ALL" &&
             observations["no_new_privileges"] == true &&
             observations["bounded_resources"] == true &&
             observations["mount"] == decision.dig(
               "local_external_effect_authority", "action_container", "mount"
             ) && observations["task_activation_record"] == runtime_channel["task_activation_record"] &&
             observations["prewrite_oci_probe"] == activation["prewrite_oci_probe"],
             "P3 MTRO pinned OCI profile fact drift")
      raw_includes.call(activation["prewrite_oci_probe"], "pre-write OCI probe")
      raw_includes.call(observations["evidence"], "Product OCI profile Evidence")
    when "OCI_RAW_STDOUT_STDERR_EXIT"
      observations = exact_keys(
        observations,
        %w[stdout stderr inspect logs exit_code output_sha256 expected_sha256 evidence], fact_id
      )
      %w[stdout stderr inspect logs evidence].each do |key|
        raw_includes.call(observations[key], "OCI #{key}")
      end
      assert(observations["exit_code"] == 0 &&
             observations["output_sha256"] == observations["expected_sha256"] &&
             observations["output_sha256"].match?(/\A[0-9a-f]{64}\z/),
             "P3 MTRO OCI stdout/stderr/exit fact drift")
    when "OCI_CLEANUP_ABSENCE"
      observations = exact_keys(
        observations,
        %w[lifecycle exact_task_objects_absent foreign_objects_unchanged pinned_image_retained evidence],
        fact_id
      )
      assert(observations["lifecycle"] == %w[create start wait inspect logs rm absence] &&
             observations["exact_task_objects_absent"] == true &&
             observations["foreign_objects_unchanged"] == true &&
             observations["pinned_image_retained"] == true,
             "P3 MTRO OCI cleanup/absence fact drift")
      raw_includes.call(observations["evidence"], "OCI cleanup/absence Evidence")
    when "HOST_INDEPENDENT_SHA_MATCH"
      observations = exact_keys(
        observations,
        %w[actual_artifact_sha256 host_sha256 oci_sha256 exact_match evidence], fact_id
      )
      assert(observations["actual_artifact_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
             observations["host_sha256"] == observations["actual_artifact_sha256"] &&
             observations["oci_sha256"] == observations["actual_artifact_sha256"] &&
             observations["exact_match"] == true,
             "P3 MTRO Host/OCI SHA match fact drift")
      raw_includes.call(observations["evidence"], "Host/OCI SHA Evidence")
    when "FOCUSED_MAVEN_TESTS", "FULL_MAVEN_TESTS"
      observations = exact_keys(
        observations,
        %w[receipt candidate_commit candidate_tree status tests failures errors skipped evidence],
        fact_id
      )
      expected_receipt = fact_id == "FOCUSED_MAVEN_TESTS" ?
        manifest["focused_test_receipt"] : manifest["full_test_receipt"]
      assert(observations["receipt"] == expected_receipt &&
             observations["candidate_commit"] == candidate["candidate_commit"] &&
             observations["candidate_tree"] == candidate["candidate_tree"] &&
             observations["status"] == "PASS" &&
             observations.slice("tests", "failures", "errors", "skipped") ==
               receipt.slice("tests", "failures", "errors", "skipped") &&
             observations["evidence"] == receipt["stdout"],
             "P3 MTRO #{fact_id} fact drift")
      raw_includes.call(expected_receipt, "#{fact_id} receipt")
      raw_includes.call(observations["evidence"], "#{fact_id} raw output")
    when "ZERO_FORBIDDEN_EXTERNAL_EFFECTS"
      observations = exact_keys(
        observations, %w[receipt effects status evidence], fact_id
      )
      assert(observations["receipt"] == manifest["forbidden_external_effects_receipt"] &&
             observations["effects"] == decision.fetch("forbidden_external_effects") &&
             observations["status"] == "PASS" &&
             observations["evidence"] == receipt.fetch("observer_artifacts").first,
             "P3 MTRO zero-forbidden-effect fact drift")
      raw_includes.call(manifest["forbidden_external_effects_receipt"],
                        "forbidden-effect receipt")
      raw_includes.call(observations["evidence"], "forbidden-effect observer Evidence")
    when "CANONICAL_REPLAY"
      observations = exact_keys(
        observations,
        %w[
          receipt candidate_commit candidate_tree canonical_commit canonical_tree
          replay_count status forbidden_external_effects_observed
        ], fact_id
      )
      replay = runtime_records.fetch("canonical_replay_record")
      assert(observations["receipt"] == bundle["canonical_replay"] &&
             observations["candidate_commit"] == candidate["candidate_commit"] &&
             observations["candidate_tree"] == candidate["candidate_tree"] &&
             observations["canonical_commit"] == replay["canonical_commit"] &&
             observations["canonical_tree"] == replay["canonical_tree"] &&
             observations["replay_count"] == 1 && observations["status"] == "PASS" &&
             observations["forbidden_external_effects_observed"] == false,
             "P3 MTRO canonical replay fact drift")
      raw_includes.call(bundle["canonical_replay"], "canonical replay receipt")
    else
      assert(false, "P3 MTRO unknown acceptance fact #{fact_id.inspect}")
    end
  end

  def file_identity!(path, expected, label)
    literal_path!(Pathname.new(path), label, directory: false)
    before = File.lstat(path)
    bytes = nil
    opened = nil
    File.open(path, File::RDONLY | File::NOFOLLOW) do |io|
      opened = io.stat
      assert(opened.file? && opened.dev == before.dev && opened.ino == before.ino,
             "#{label} changed before read")
      bytes = io.read
      after = io.stat
      assert(after.dev == opened.dev && after.ino == opened.ino &&
             after.size == opened.size && after.mtime == opened.mtime,
             "#{label} changed during read")
    end
    final = File.lstat(path)
    assert(final.file? && !final.symlink? && final.dev == opened.dev && final.ino == opened.ino,
           "#{label} changed after read")
    assert(bytes.bytesize == expected.fetch("byte_length") &&
           Digest::SHA256.hexdigest(bytes) == expected.fetch("sha256"),
           "#{label} identity drift")
    bytes
  rescue Errno::ENOENT, Errno::ELOOP => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "#{label} unavailable: #{e.message}"
  end

  def repo_file_identity!(root, expected, label)
    file_identity!(root.join(expected.fetch("path")), expected, label)
  end

  def git!(root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    assert(status.success?, "git #{args.join(' ')} failed: #{stderr.strip}")
    stdout
  end

  def validate_canonical_start!(root)
    tree = git!(root, "rev-parse", "#{CANONICAL_START.fetch('commit')}^{tree}").strip
    assert(tree == CANONICAL_START.fetch("tree"), "P3 MTRO canonical-start tree drift")
    CANONICAL_START.values_at("truth", "constitution").each do |identity|
      bytes = git!(
        root, "show", "#{CANONICAL_START.fetch('commit')}:#{identity.fetch('path')}"
      )
      assert(bytes.bytesize == identity.fetch("byte_length") &&
             Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"),
             "P3 MTRO canonical-start #{identity.fetch('path')} drift")
    end
  end

  def validate_decision!(root)
    bytes = repo_file_identity!(root, DECISION, "P3 MTRO Founder decision")
    decision = parse_closed_json(bytes, "P3 MTRO Founder decision")
    assert(decision["schema_version"] ==
             "p3-minimum-trust-transactional-oci-final-product-founder-decision/v2" &&
           decision["record_type"] ==
             "FOUNDER_P3_MINIMUM_TRUST_TRANSACTIONAL_OCI_FINAL_PRODUCT_ROUTE_DECISION" &&
           decision["decision_id"] == DECISION_ID &&
           decision["operation_type"] == OPERATION_TYPE &&
           decision["status"] == "ACCEPTED_DIRECT_FOUNDER_STRATEGIC_ROUTE_DECISION" &&
           decision["reserved_triggers"] == ["MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"],
           "P3 MTRO Founder decision header drift")
    assert(decision.dig("canonical_start", "commit") == CANONICAL_START.fetch("commit") &&
           decision.dig("canonical_start", "tree") == CANONICAL_START.fetch("tree") &&
           decision.dig("canonical_start", "truth") == CANONICAL_START.fetch("truth") &&
           decision.dig("canonical_start", "constitution") == CANONICAL_START.fetch("constitution"),
           "P3 MTRO canonical-start decision binding drift")
    assert(decision.dig("direct_founder_authorization", "path") ==
             DIRECT_AUTHORIZATION.fetch("path") &&
           decision.dig("direct_founder_authorization", "byte_length") ==
             DIRECT_AUTHORIZATION.fetch("byte_length") &&
           decision.dig("direct_founder_authorization", "sha256") ==
             DIRECT_AUTHORIZATION.fetch("sha256") &&
           decision.dig("direct_founder_authorization", "normalized_byte_length") ==
             DIRECT_AUTHORIZATION.fetch("byte_length") &&
           decision.dig("direct_founder_authorization", "normalized_sha256") ==
             DIRECT_AUTHORIZATION.fetch("sha256") &&
           decision.dig("direct_founder_authorization", "content_match") ==
             "BYTE_EXACT_AUTHORIZATION_BODY",
           "P3 MTRO direct Founder authorization binding drift")
    assert(decision["installed_constitution"] == CONSTITUTION &&
           decision.dig("strategic_change", "objective_id") == OBJECTIVE_ID &&
           decision.dig("strategic_change", "strict_exit_gate", "gate_id") == STRICT_GATE_ID &&
           decision.dig("strategic_change", "strict_exit_gate", "required_item_ids") == STRICT_ITEMS &&
           mapping(decision.dig("strategic_change", "fixed_action"),
                   "P3 MTRO decision fixed action").slice(*FIXED_ACTION.keys) == FIXED_ACTION,
           "P3 MTRO strategic Objective, Gate or fixed-action drift")
    assert(decision.dig("route", "route_id") == ROUTE_ID &&
           decision.dig("route", "ordered_stages").length == 1 &&
           decision.dig("route", "ordered_stages", 0, "task_id") == TASK_ID &&
           decision.dig("route", "ordered_stages", 0, "budget") == TASK_BUDGET &&
           decision.dig("route", "ordered_stages", 0, "implementation_attempt_for_milestone") ==
             "2_OF_2_FINAL" &&
           decision.dig("route", "separate_foundation_task") == false &&
           decision.dig("route", "separate_preflight_task") == false &&
           decision.dig("route", "separate_audit_task") == false,
           "P3 MTRO one-Task final Route drift")
    assert(decision.dig("cumulative_accounting", "consumed_before_route") == CONSUMED &&
           decision.dig("cumulative_accounting", "limits") == LIMITS &&
           decision.dig("cumulative_accounting", "route_release") == REMAINING &&
           decision.dig("cumulative_accounting", "reset_refund_or_expansion_allowed") == false,
           "P3 MTRO non-resettable accounting drift")
    assert(decision.dig("local_external_effect_authority", "docker_cli") == DOCKER_CLI &&
           decision.dig("local_external_effect_authority", "docker_endpoint") == DOCKER_ENDPOINT &&
           decision.dig("local_external_effect_authority", "image_content_id") == IMAGE_ID &&
           decision.dig("local_external_effect_authority", "allowed_docker_verbs") == DOCKER_VERBS &&
           decision.dig("local_external_effect_authority", "action_container", "entrypoint") ==
             "/usr/bin/sha256sum" &&
           decision.dig("local_external_effect_authority", "action_container", "arguments") ==
             ["/input/custody.bin"] &&
           decision.dig("local_external_effect_authority", "action_container", "user") ==
             "65534:65534",
           "P3 MTRO local OCI authority drift")
    assert(decision.dig("anti_cycle", "foundation_task_allowed") == false &&
           decision.dig("anti_cycle", "preflight_task_allowed") == false &&
           decision.dig("anti_cycle", "audit_task_allowed") == false &&
           decision.dig("anti_cycle", "third_product_task_allowed") == false &&
           decision.dig("anti_cycle", "candidate_3_allowed") == false &&
           decision.dig("anti_cycle", "v3_or_later_route_under_same_objective_allowed") == false,
           "P3 MTRO anti-cycle boundary drift")
    superseded = decision.fetch("superseded_unexecuted_authorization")
    assert(superseded.slice("path", "byte_length", "sha256") == SUPERSEDED_V1 &&
           superseded["installed"] == false && superseded["executed"] == false &&
           superseded["authority_status"] == "REVOKED_AND_SUPERSEDED_BY_THIS_V2",
           "P3 MTRO superseded V1 authority drift")
    file_identity!(DIRECT_AUTHORIZATION.fetch("path"), DIRECT_AUTHORIZATION,
                   "P3 MTRO direct Founder attachment")
    file_identity!(SUPERSEDED_V1.fetch("path"), SUPERSEDED_V1,
                   "P3 MTRO superseded V1 attachment")
    repo_file_identity!(root, CONSTITUTION, "P3 MTRO Strategic Constitution v3.6")
    file_identity!(TRIVS_TERMINAL_RECEIPT.fetch("path"), TRIVS_TERMINAL_RECEIPT,
                   "P3 TRIVS terminal receipt")
    file_identity!(F2_TERMINAL_RECEIPT.fetch("path"), F2_TERMINAL_RECEIPT,
                   "P3 F2 terminal receipt")
    file_identity!(F2_DIAGNOSTIC.fetch("path"), F2_DIAGNOSTIC, "P3 F2 diagnostic")
    validate_canonical_start!(root)
    decision
  rescue DuplicateJsonKeyError, JSON::ParserError => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "P3 MTRO decision JSON invalid: #{e.message}"
  end

  def validate_runtime_identity_channel!(root, channel, lifecycle, active: nil)
    channel = exact_keys(
      channel,
      %w[
        status task_activation_record candidate_freeze_record review_dispatch_record
        integration_record canonical_replay_record future_dynamic_identity_prefill_allowed
      ],
      "P3 MTRO runtime identity channel"
    )
    assert(RUNTIME_STATES.include?(channel["status"]) &&
           channel["future_dynamic_identity_prefill_allowed"] == false,
           "P3 MTRO runtime identity channel state drift")
    allowed_states = {
      "PRODUCT_ELIGIBLE_NOT_ACTIVATED" => %w[PENDING_TASK_OWNED_DISCOVERY],
      "PRODUCT_TASK_ACTIVE" => %w[
        PENDING_TASK_OWNED_DISCOVERY ACTIVATION_BOUND CANDIDATE_FROZEN REVIEW_BOUND
      ],
      "PRODUCT_ROUTE_TERMINAL_NON_PASS" => %w[
        PENDING_TASK_OWNED_DISCOVERY ACTIVATION_BOUND CANDIDATE_FROZEN REVIEW_BOUND
      ],
      "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE" => %w[INTEGRATED_REPLAY_BOUND]
    }.fetch(lifecycle)
    assert(allowed_states.include?(channel["status"]),
           "P3 MTRO runtime state is impossible for lifecycle #{lifecycle}")
    records = %w[
      task_activation_record candidate_freeze_record review_dispatch_record
      integration_record canonical_replay_record
    ]
    if lifecycle == "PRODUCT_ELIGIBLE_NOT_ACTIVATED" ||
       channel["status"] == "PENDING_TASK_OWNED_DISCOVERY"
      assert(records.all? { |key| channel[key].nil? },
             "P3 MTRO future runtime identity was prefilled")
    end
    if channel["status"] == "ACTIVATION_BOUND"
      assert(!channel["task_activation_record"].nil? &&
             records.drop(1).all? { |key| channel[key].nil? },
             "P3 MTRO activation-bound runtime record order drift")
    end
    if channel["status"] == "CANDIDATE_FROZEN"
      assert(!channel["task_activation_record"].nil? &&
             !channel["candidate_freeze_record"].nil? &&
             records.drop(2).all? { |key| channel[key].nil? },
             "P3 MTRO candidate record order drift")
    end
    if channel["status"] == "REVIEW_BOUND"
      assert(records.first(3).all? { |key| !channel[key].nil? } &&
             records.drop(3).all? { |key| channel[key].nil? },
             "P3 MTRO review record order drift")
    end
    if channel["status"] == "INTEGRATED_REPLAY_BOUND"
      assert(records.all? { |key| !channel[key].nil? },
             "P3 MTRO integrated replay record chain incomplete")
    end
    expected_schemas = {
      "task_activation_record" => "p3-mtro-task-activation-record/v1",
      "candidate_freeze_record" => "p3-mtro-candidate-freeze-record/v1",
      "review_dispatch_record" => "p3-mtro-review-dispatch-record/v1",
      "integration_record" => "p3-mtro-integration-record/v1",
      "canonical_replay_record" => "p3-mtro-canonical-replay/v1"
    }
    observed = {}
    records.each do |key|
      next if channel[key].nil?
      bytes = artifact_identity!(
        root, channel[key], "P3 MTRO #{key}", under: TASK_EVIDENCE_ROOT
      )
      record = parse_closed_json(bytes, "P3 MTRO #{key}")
      assert(record["schema_version"] == expected_schemas.fetch(key) &&
             record["task_id"] == TASK_ID && record["route_id"] == ROUTE_ID,
             "P3 MTRO #{key} semantic drift")
      observed[key] = record
    end
    activation = observed["task_activation_record"]
    if activation
      activation = exact_keys(
        activation,
        %w[
          schema_version record_type status task_id route_id execution_nonce authorization_id
          contract authority activation_parent daemon_id network_id mysql_container_id
          loopback_port prewrite_oci_probe created_at_utc
        ],
        "P3 MTRO task activation record"
      )
      assert(activation["record_type"] == "P3_MTRO_TASK_ACTIVATION_RECORD" &&
             activation["status"] == "PASS" &&
             activation["execution_nonce"].is_a?(String) &&
             activation["authorization_id"].is_a?(String) &&
             activation["daemon_id"].is_a?(String) && !activation["daemon_id"].empty? &&
             activation["network_id"].is_a?(String) && !activation["network_id"].empty? &&
             activation["mysql_container_id"].is_a?(String) &&
             !activation["mysql_container_id"].empty? &&
             activation["loopback_port"].is_a?(Integer) &&
             activation["loopback_port"].between?(1, 65_535),
             "P3 MTRO task activation record is not runtime-bound")
      Time.iso8601(activation.fetch("created_at_utc"))
      assert(exact_keys(activation["activation_parent"], %w[commit tree],
                        "P3 MTRO activation record parent") == {
               "commit" => active && active["activation_parent_commit"],
               "tree" => active && active["activation_parent_tree"]
             }, "P3 MTRO task activation parent drift") if active
      assert(activation["contract"] == active["current_task_contract"] &&
             activation["authority"] == active["authority_record"] &&
             activation["execution_nonce"] == active["execution_nonce"] &&
             activation["authorization_id"] == active["authorization_id"],
             "P3 MTRO task activation authority drift") if active
      probe_bytes = artifact_identity!(
        root, activation["prewrite_oci_probe"], "P3 MTRO pre-write OCI probe",
        under: TASK_EVIDENCE_ROOT
      )
      probe = exact_keys(
        parse_closed_json(probe_bytes, "P3 MTRO pre-write OCI probe"),
        %w[
          schema_version record_type status task_id route_id docker_cli docker_endpoint
          image_content_id container_id entrypoint arguments user network read_only_rootfs
          cap_drop no_new_privileges bounded_resources stdout_sha256 expected_sha256 exit_code
          cleanup_complete pinned_image_retained forbidden_external_effects_observed executed_at_utc
        ],
        "P3 MTRO pre-write OCI probe"
      )
      assert(probe["schema_version"] == "p3-mtro-pre-first-product-write-oci-probe/v1" &&
             probe["record_type"] == "P3_MTRO_PRE_FIRST_PRODUCT_WRITE_OCI_PROBE" &&
             probe["status"] == "PASS" && probe["task_id"] == TASK_ID &&
             probe["route_id"] == ROUTE_ID && probe["docker_cli"] == DOCKER_CLI &&
             probe["docker_endpoint"] == DOCKER_ENDPOINT &&
             probe["image_content_id"] == IMAGE_ID &&
             probe["container_id"].is_a?(String) && !probe["container_id"].empty? &&
             probe["entrypoint"] == "/usr/bin/sha256sum" &&
             probe["arguments"] == ["/input/custody.bin"] &&
             probe["user"] == "65534:65534" && probe["network"] == "none" &&
             probe["read_only_rootfs"] == true && probe["cap_drop"] == "ALL" &&
             probe["no_new_privileges"] == true && probe["bounded_resources"] == true &&
             probe["stdout_sha256"] == probe["expected_sha256"] &&
             probe["stdout_sha256"].is_a?(String) &&
             probe["stdout_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
             probe["exit_code"] == 0 && probe["cleanup_complete"] == true &&
             probe["pinned_image_retained"] == true &&
             probe["forbidden_external_effects_observed"] == false,
             "P3 MTRO pre-write OCI probe semantic drift")
      Time.iso8601(probe.fetch("executed_at_utc"))
    end
    candidate = observed["candidate_freeze_record"]
    if candidate
      candidate = exact_keys(
        candidate,
        %w[
          schema_version record_type status task_id route_id execution_nonce authorization_id
          candidate_commit candidate_tree candidate_generation manifest task_activation_record
          frozen_at_utc
        ],
        "P3 MTRO candidate freeze record"
      )
      assert(candidate["record_type"] == "P3_MTRO_CANDIDATE_FREEZE_RECORD" &&
             candidate["status"] == "FROZEN" &&
             [1, 2].include?(candidate["candidate_generation"]) &&
             activation && candidate["execution_nonce"] == activation["execution_nonce"] &&
             candidate["authorization_id"] == activation["authorization_id"] &&
             candidate["task_activation_record"] == channel["task_activation_record"],
             "P3 MTRO frozen candidate authority drift")
      Time.iso8601(candidate.fetch("frozen_at_utc"))
      git_identity!(root, candidate["candidate_commit"], candidate["candidate_tree"],
                    "P3 MTRO frozen candidate")
      manifest_bytes = artifact_identity!(
        root, candidate["manifest"], "P3 MTRO frozen candidate manifest",
        under: TASK_EVIDENCE_ROOT
      )
      manifest = exact_keys(
        parse_closed_json(manifest_bytes, "P3 MTRO frozen candidate manifest"),
        %w[
          schema_version record_type status task_id route_id execution_nonce authorization_id
          branch worktree activation_parent task_base candidate_commit candidate_tree candidate_generation
          changed_paths approved_adjacent_expansions product_write_allowlist fixed_action contract
          authority task_activation_record source_to_class_evidence focused_test_receipt
          full_test_receipt forbidden_external_effects_receipt created_at_utc
        ],
        "P3 MTRO frozen candidate manifest"
      )
      decision = validate_decision!(root)
      activation_parent = exact_keys(
        manifest["activation_parent"], %w[commit tree],
        "P3 MTRO candidate manifest activation parent"
      )
      task_base = exact_keys(manifest["task_base"], %w[commit tree],
                             "P3 MTRO candidate manifest Task base")
      expansions = array(manifest["approved_adjacent_expansions"],
                         "P3 MTRO approved adjacent expansions")
      assert(expansions.empty?,
             "P3 MTRO adjacent Product expansion is not enabled for this frozen route")
      expanded_paths = expansions.map do |expansion|
        expansion = exact_keys(
          expansion,
          %w[
            path kind mechanical_compilation_reason zero_scope_expansion_proof
            authorization_record authorized_at_utc prewrite_oci_probe
          ],
          "P3 MTRO adjacent allowlist expansion"
        )
        allowed_expansion_kinds = %w[
          ADJACENT_DTO ADJACENT_MAPPER ADJACENT_CONFIGURATION_CLASS DIRECT_CORRESPONDING_TEST
        ]
        allowed_expansion_prefixes = %w[
          backend-spring/src/main/java/com/sourcelens/
          backend-spring/src/test/java/com/sourcelens/
        ]
        assert(expansion["path"].is_a?(String) && expansion["path"].end_with?(".java") &&
               allowed_expansion_prefixes.any? { |prefix| expansion["path"].start_with?(prefix) } &&
               allowed_expansion_kinds.include?(expansion["kind"]) &&
               !path_covered_by_allowlist?(
                 expansion["path"], decision.fetch("product_write_allowlist")
               ) &&
               IMMUTABLE_AUTHORITY_PATHS.none? { |path|
                 expansion["path"] == path || expansion["path"].start_with?("#{path}/")
               } &&
               expansion["mechanical_compilation_reason"].is_a?(String) &&
               !expansion["mechanical_compilation_reason"].empty? &&
               expansion["zero_scope_expansion_proof"] == true &&
               expansion["prewrite_oci_probe"] == activation["prewrite_oci_probe"],
               "P3 MTRO adjacent allowlist expansion is not mechanically bounded")
        Time.iso8601(expansion.fetch("authorized_at_utc"))
        authorization_bytes = artifact_identity!(
          root, expansion["authorization_record"], "P3 MTRO adjacent expansion authorization",
          under: TASK_EVIDENCE_ROOT
        )
        expansion_authority = exact_keys(
          parse_closed_json(authorization_bytes, "P3 MTRO adjacent expansion authorization"),
          %w[
            schema_version record_type status task_id route_id path kind
            mechanical_compilation_reason zero_scope_expansion_proof prewrite_oci_probe
            contract authority authorized_at_utc
          ],
          "P3 MTRO adjacent expansion authorization"
        )
        assert(expansion_authority["schema_version"] ==
                 "p3-mtro-adjacent-allowlist-expansion-authorization/v1" &&
               expansion_authority["record_type"] ==
                 "P3_MTRO_ADJACENT_ALLOWLIST_EXPANSION_AUTHORIZATION" &&
               expansion_authority["status"] == "APPROVED_BEFORE_FIRST_PRODUCT_SOURCE_WRITE" &&
               expansion_authority["task_id"] == TASK_ID &&
               expansion_authority["route_id"] == ROUTE_ID &&
               expansion_authority.slice(
                 "path", "kind", "mechanical_compilation_reason", "zero_scope_expansion_proof",
                 "prewrite_oci_probe", "authorized_at_utc"
               ) == expansion.slice(
                 "path", "kind", "mechanical_compilation_reason", "zero_scope_expansion_proof",
                 "prewrite_oci_probe", "authorized_at_utc"
               ) && expansion_authority["contract"] == active["current_task_contract"] &&
               expansion_authority["authority"] == active["authority_record"],
               "P3 MTRO adjacent expansion authorization semantic drift")
        expansion["path"]
      end
      changed_paths = array(manifest["changed_paths"], "P3 MTRO candidate changed paths")
      actual_changed_paths = git_changed_paths!(
        root, task_base.fetch("commit"), candidate.fetch("candidate_commit"),
        "P3 MTRO candidate"
      )
      assert(manifest["schema_version"] == "p3-mtro-frozen-candidate-manifest/v1" &&
             manifest["record_type"] == "P3_MTRO_FROZEN_CANDIDATE_MANIFEST" &&
             manifest["status"] == "FROZEN" && manifest["task_id"] == TASK_ID &&
             manifest["route_id"] == ROUTE_ID &&
             manifest["execution_nonce"] == candidate["execution_nonce"] &&
             manifest["authorization_id"] == candidate["authorization_id"] &&
             manifest["branch"] == TASK_BRANCH && manifest["worktree"] == TASK_WORKTREE &&
             active && activation_parent == {
               "commit" => active["activation_parent_commit"],
               "tree" => active["activation_parent_tree"]
             } &&
             task_base == validate_task_base!(
               root, activation_parent.fetch("commit"), candidate.fetch("candidate_commit"),
               active.fetch("current_task_contract")
             ) &&
             manifest["candidate_commit"] == candidate["candidate_commit"] &&
             manifest["candidate_tree"] == candidate["candidate_tree"] &&
             manifest["candidate_generation"] == candidate["candidate_generation"] &&
             !changed_paths.empty? && changed_paths.sort == actual_changed_paths &&
             changed_paths.uniq.length == changed_paths.length &&
             changed_paths.all? { |path|
               path_covered_by_allowlist?(
                 path, decision.fetch("product_write_allowlist") + expanded_paths
               )
             } && changed_paths.any? { |path| path.start_with?("backend-spring/src/main/") } &&
             expansions.length == expanded_paths.uniq.length &&
             manifest["fixed_action"] == FIXED_ACTION &&
             manifest["product_write_allowlist"] == decision.fetch("product_write_allowlist") &&
             manifest["contract"] == active["current_task_contract"] &&
             manifest["authority"] == active["authority_record"] &&
             manifest["task_activation_record"] == channel["task_activation_record"],
             "P3 MTRO frozen candidate manifest semantic drift")
      manifest_time = Time.iso8601(manifest.fetch("created_at_utc"))
      assert(expansions.all? { |expansion|
               Time.iso8601(expansion.fetch("authorized_at_utc")) <= manifest_time
             }, "P3 MTRO adjacent expansion was not authorized before candidate freeze")
      git_identity!(root, activation_parent.fetch("commit"), activation_parent.fetch("tree"),
                    "P3 MTRO candidate activation parent")
      git_identity!(root, task_base.fetch("commit"), task_base.fetch("tree"),
                    "P3 MTRO candidate Task base")
      _stdout, _stderr, ancestor = Open3.capture3(
        "git", "-C", root.to_s, "merge-base", "--is-ancestor",
        task_base.fetch("commit"), candidate.fetch("candidate_commit")
      )
      assert(ancestor.success?, "P3 MTRO candidate is not descended from activation parent")
      focused_receipt = validate_maven_run_receipt!(
        root: root, identity: manifest["focused_test_receipt"], kind: "FOCUSED_MAVEN",
        candidate: candidate, activation_identity: channel["task_activation_record"]
      )
      OBSERVATION_RECORD_SPECS.each_key do |group|
        observation_identity = focused_receipt.fetch("observation_records").fetch(group)
        assert(group != "source_custody" ||
               observation_identity == manifest["source_to_class_evidence"],
               "P3 MTRO candidate source-custody record identity drift")
        observation_result = validate_observation_record!(
          root: root, identity: observation_identity, group: group, candidate: candidate,
          activation_identity: channel["task_activation_record"]
        )
        assert(observation_result.fetch("record")["run_id"] == focused_receipt["run_id"],
               "P3 MTRO candidate observation run differs from focused Maven run")
      end
      validate_maven_run_receipt!(
        root: root, identity: manifest["full_test_receipt"], kind: "FULL_MAVEN",
        candidate: candidate, activation_identity: channel["task_activation_record"]
      )
      validate_forbidden_effects_receipt!(
        root: root, identity: manifest["forbidden_external_effects_receipt"],
        candidate: candidate, activation_identity: channel["task_activation_record"]
      )
      if active && active["current_task"] == TASK_ID && Pathname.new(TASK_WORKTREE).exist?
        task_root = literal_path!(Pathname.new(TASK_WORKTREE),
                                  "P3 MTRO live Task worktree", directory: true)
        assert(git!(task_root, "branch", "--show-current").strip == TASK_BRANCH &&
               git!(task_root, "rev-parse", "HEAD").strip == candidate["candidate_commit"] &&
               git!(task_root, "status", "--porcelain").strip.empty?,
               "P3 MTRO live candidate is not the clean exact Task branch HEAD")
      end
    end
    review_dispatch = observed["review_dispatch_record"]
    if review_dispatch
      review_dispatch = exact_keys(
        review_dispatch,
        %w[
          schema_version record_type status task_id route_id execution_nonce authorization_id
          candidate_commit candidate_tree review_cycle candidate_freeze_record
          frozen_finding_set repair_record reviewer_worktrees dispatched_at_utc
        ],
        "P3 MTRO review dispatch record"
      )
      reviewer_worktrees = exact_keys(
        review_dispatch["reviewer_worktrees"],
        %w[cto security quality_evaluation], "P3 MTRO reviewer worktrees"
      )
      assert(review_dispatch["record_type"] == "P3_MTRO_REVIEW_DISPATCH_RECORD" &&
             review_dispatch["status"] == "DISPATCHED" &&
             [1, 2].include?(review_dispatch["review_cycle"]) && candidate &&
             review_dispatch["execution_nonce"] == candidate["execution_nonce"] &&
             review_dispatch["authorization_id"] == candidate["authorization_id"] &&
             review_dispatch["candidate_freeze_record"] == channel["candidate_freeze_record"],
             "P3 MTRO review dispatch authority drift")
      Time.iso8601(review_dispatch.fetch("dispatched_at_utc"))
      if review_dispatch["review_cycle"] == 1
        assert(review_dispatch["frozen_finding_set"].nil? &&
               review_dispatch["repair_record"].nil?,
               "P3 MTRO Cycle 1 dispatch prefills future finding or repair identity")
      else
        finding_set, finding_ids = validate_frozen_finding_set!(
          root, review_dispatch["frozen_finding_set"]
        )
        assert(!finding_ids.empty?,
               "P3 MTRO Cycle 2 cannot exist without frozen Cycle 1 findings")
        repair_bytes = artifact_identity!(
          root, review_dispatch["repair_record"], "P3 MTRO same-Task repair record",
          under: TASK_EVIDENCE_ROOT
        )
        repair = exact_keys(
          parse_closed_json(repair_bytes, "P3 MTRO same-Task repair record"),
          %w[
            schema_version record_type status task_id route_id repair_index
            candidate_before_commit candidate_before_tree candidate_after_commit
            candidate_after_tree frozen_finding_set closed_finding_ids new_regressions
            scope_expansion applied_at_utc
          ],
          "P3 MTRO same-Task repair record"
        )
        assert(repair["schema_version"] == "p3-mtro-same-task-repair-record/v1" &&
               repair["record_type"] == "P3_MTRO_SAME_TASK_REPAIR_RECORD" &&
               repair["status"] == "APPLIED" && repair["task_id"] == TASK_ID &&
               repair["route_id"] == ROUTE_ID && repair["repair_index"] == 1 &&
               candidate["candidate_generation"] == 2 &&
               repair["candidate_before_commit"] == finding_set["candidate_commit"] &&
               repair["candidate_before_tree"] == finding_set["candidate_tree"] &&
               repair["candidate_after_commit"] == candidate["candidate_commit"] &&
               repair["candidate_after_tree"] == candidate["candidate_tree"] &&
               repair["candidate_before_commit"] != repair["candidate_after_commit"] &&
               repair["frozen_finding_set"] == review_dispatch["frozen_finding_set"] &&
               repair["closed_finding_ids"].sort == finding_ids.sort &&
               repair["new_regressions"] == [] && repair["scope_expansion"] == false,
               "P3 MTRO same-Task repair record semantic drift")
        git_identity!(root, repair["candidate_before_commit"], repair["candidate_before_tree"],
                      "P3 MTRO pre-repair candidate")
        _stdout, _stderr, repaired_ancestor = Open3.capture3(
          "git", "-C", root.to_s, "merge-base", "--is-ancestor",
          repair["candidate_before_commit"], repair["candidate_after_commit"]
        )
        assert(repaired_ancestor.success?,
               "P3 MTRO repaired candidate is not descended from Cycle 1 candidate")
        repair_paths = git_changed_paths!(
          root, repair["candidate_before_commit"], repair["candidate_after_commit"],
          "P3 MTRO same-Task repair"
        )
        assert(!repair_paths.empty? && repair_paths.all? { |path|
                 path_covered_by_allowlist?(
                   path, validate_decision!(root).fetch("product_write_allowlist")
                 )
               }, "P3 MTRO same-Task repair diff escapes Product allowlist")
        Time.iso8601(repair.fetch("applied_at_utc"))
      end
      reviewer_worktrees.each do |role, identity|
        worktree_bytes = artifact_identity!(
          root, identity, "P3 MTRO #{role} reviewer worktree identity",
          under: TASK_EVIDENCE_ROOT
        )
        worktree = exact_keys(
          parse_closed_json(worktree_bytes, "P3 MTRO #{role} reviewer worktree identity"),
          %w[schema_version role path candidate_commit candidate_tree detached_head clean created_at_utc],
          "P3 MTRO #{role} reviewer worktree identity"
        )
        expected_role = {
          "cto" => "CTO_AGENT", "security" => "SECURITY_AGENT",
          "quality_evaluation" => "QUALITY_EVALUATION_AGENT"
        }.fetch(role)
        assert(worktree["schema_version"] == "p3-mtro-reviewer-worktree-identity/v1" &&
               worktree["role"] == expected_role &&
               worktree["candidate_commit"] == candidate["candidate_commit"] &&
               worktree["candidate_tree"] == candidate["candidate_tree"] &&
               worktree["detached_head"] == true && worktree["clean"] == true &&
               worktree["path"].is_a?(String) && !worktree["path"].empty?,
               "P3 MTRO #{role} reviewer worktree identity drift")
        Time.iso8601(worktree.fetch("created_at_utc"))
      end
    end
    integration = observed["integration_record"]
    if integration
      integration = exact_keys(
        integration,
        %w[
          schema_version record_type status task_id route_id candidate_commit candidate_tree
          task_gate_receipt canonical_commit canonical_tree integrated_branch integrated_at_utc
        ],
        "P3 MTRO integration record"
      )
      assert(integration["record_type"] == "P3_MTRO_INTEGRATION_RECORD" &&
             integration["status"] == "PASS" && candidate &&
             integration["candidate_commit"] == candidate["candidate_commit"] &&
             integration["candidate_tree"] == candidate["candidate_tree"] &&
             integration["canonical_commit"] == candidate["candidate_commit"] &&
             integration["canonical_tree"] == candidate["candidate_tree"] &&
             integration["integrated_branch"] == "main",
             "P3 MTRO integration record semantic drift")
      task_gate_label = "P3 MTRO integration Task Gate receipt"
      task_gate_bytes = artifact_identity!(
        root, integration["task_gate_receipt"], task_gate_label, under: TASK_EVIDENCE_ROOT
      )
      task_gate = exact_keys(
        parse_closed_json(task_gate_bytes, task_gate_label),
        %w[
          schema_version record_type verdict task_id route_id candidate_commit candidate_tree
          frozen_finding_set independent_reviews required_item_evidence open_p0_p1_findings
          forbidden_external_effects_observed decided_at_utc
        ],
        task_gate_label
      )
      assert(task_gate["schema_version"] == "p3-mtro-task-gate-pass-receipt/v1" &&
             task_gate["record_type"] == "P3_MTRO_TASK_GATE_PASS_RECEIPT" &&
             task_gate["verdict"] == "PASS" && task_gate["task_id"] == TASK_ID &&
             task_gate["route_id"] == ROUTE_ID &&
             task_gate["candidate_commit"] == candidate["candidate_commit"] &&
             task_gate["candidate_tree"] == candidate["candidate_tree"] &&
             task_gate["open_p0_p1_findings"] == [] &&
             task_gate["forbidden_external_effects_observed"] == false,
             "P3 MTRO integration Task Gate receipt semantic drift")
      exact_keys(task_gate["frozen_finding_set"], %w[path byte_length sha256],
                 "#{task_gate_label} frozen finding set")
      exact_keys(
        task_gate["independent_reviews"], %w[cto security quality_evaluation],
        "#{task_gate_label} independent reviews"
      ).each_value do |identity|
        exact_keys(identity, %w[path byte_length sha256], "#{task_gate_label} review identity")
      end
      exact_keys(task_gate["required_item_evidence"], STRICT_ITEMS,
                 "#{task_gate_label} required item Evidence").each_value do |identity|
        exact_keys(identity, %w[path byte_length sha256], "#{task_gate_label} item identity")
      end
      Time.iso8601(task_gate.fetch("decided_at_utc"))
      Time.iso8601(integration.fetch("integrated_at_utc"))
    end
    replay = observed["canonical_replay_record"]
    if replay
      replay = exact_keys(
        replay,
        %w[
          schema_version record_type status task_id route_id candidate_commit candidate_tree
          canonical_commit canonical_tree integration_record replay_count
          raw_replay_bundle forbidden_external_effects_observed replayed_at_utc
        ],
        "P3 MTRO canonical replay record"
      )
      assert(replay["record_type"] == "P3_MTRO_CANONICAL_REPLAY_RECORD" &&
             replay["status"] == "PASS" && replay["replay_count"] == 1 && integration &&
             replay["candidate_commit"] == integration["candidate_commit"] &&
             replay["candidate_tree"] == integration["candidate_tree"] &&
             replay["canonical_commit"] == integration["canonical_commit"] &&
             replay["canonical_tree"] == integration["canonical_tree"] &&
             replay["integration_record"] == channel["integration_record"] &&
             replay["forbidden_external_effects_observed"] == false,
             "P3 MTRO canonical replay record semantic drift")
      replay_bundle = validate_canonical_replay_raw_bundle!(
        root: root, identity: replay["raw_replay_bundle"], candidate: candidate,
        activation_identity: channel["task_activation_record"],
        integration_identity: channel["integration_record"],
        canonical_commit: replay["canonical_commit"], canonical_tree: replay["canonical_tree"]
      )
      assert(Time.iso8601(replay_bundle.fetch("created_at_utc")) <=
             Time.iso8601(replay.fetch("replayed_at_utc")),
             "P3 MTRO replay verdict predates its raw bundle")
      Time.iso8601(replay.fetch("replayed_at_utc"))
    end
    %w[review_dispatch_record integration_record canonical_replay_record].each do |key|
      next unless observed[key] && candidate
      assert(observed[key]["candidate_commit"] == candidate["candidate_commit"] &&
             observed[key]["candidate_tree"] == candidate["candidate_tree"],
             "P3 MTRO #{key} candidate drift")
    end
    observed
  rescue ArgumentError => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "P3 MTRO runtime identity channel invalid: #{e.message}"
  end

  def validate_active_authority!(root, truth, decision, require_worktree: false)
    active = mapping(truth["active_work"], "P3 MTRO active work")
    contract_identity = exact_keys(
      active["current_task_contract"], %w[path byte_length sha256],
      "P3 MTRO Task Contract identity"
    )
    authority_identity = exact_keys(
      active["authority_record"], %w[path byte_length sha256],
      "P3 MTRO Task authority identity"
    )
    assert(contract_identity["path"] == TASK_CONTRACT_PATH &&
           authority_identity["path"] == AUTHORITY_PATH,
           "P3 MTRO Task Contract or authority path drift")
    assert(active["execution_nonce"].is_a?(String) &&
           active["execution_nonce"].match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/) &&
           active["authorization_id"].is_a?(String) &&
           active["authorization_id"].match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/) &&
           active["execution_nonce"] != active["authorization_id"],
           "P3 MTRO nonce or authorization identity is invalid")
    contract_bytes = repo_file_identity!(root, contract_identity, "P3 MTRO Task Contract")
    reject_duplicate_yaml_keys!(contract_bytes, "P3 MTRO Task Contract")
    contract = YAML.safe_load(
      contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
    )
    contract = exact_keys(
      contract,
      %w[
        schema_version record_type task_id status phase route_id stage_id kind objective_id
        strict_exit_gate_id implementation_attempt_for_milestone decision why_now branch worktree
        evidence_root activation_parent execution_nonce authorization_id roles risk_level
        write_allowlist conditional_adjacent_allowlist_expansion fixed_action budget authority_model
        transaction_model recovery_and_checkpoint local_external_effect_authority
        forbidden_external_effects clean_room acceptance anti_cycle required_evidence
        stop_conditions lifecycle
      ],
      "P3 MTRO Task Contract"
    )
    decision_identity = DECISION.merge("decision_id" => DECISION_ID)
    activation_parent = exact_keys(contract["activation_parent"], %w[commit tree],
                                   "P3 MTRO Contract activation parent")
    roles = exact_keys(contract["roles"],
                       %w[owner worker independent_reviewers task_gate_owner],
                       "P3 MTRO Contract roles")
    assert(contract["schema_version"] == "p3-mtro-phase-delegated-task-contract/v1" &&
           contract["record_type"] == "P3_MTRO_P1_PHASE_DELEGATED_TASK_CONTRACT" &&
           contract["task_id"] == TASK_ID && contract["status"] == "ACTIVE" &&
           contract["phase"] == "P3" && contract["route_id"] == ROUTE_ID &&
           contract["stage_id"] == "ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION_PRODUCT" &&
           contract["kind"] == "PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL" &&
           contract["objective_id"] == OBJECTIVE_ID &&
           contract["strict_exit_gate_id"] == STRICT_GATE_ID &&
           contract["implementation_attempt_for_milestone"] == "2_OF_2_FINAL" &&
           contract["decision"] == decision_identity &&
           contract["why_now"].is_a?(String) && !contract["why_now"].empty? &&
           contract["branch"] == TASK_BRANCH && contract["worktree"] == TASK_WORKTREE &&
           contract["evidence_root"] == TASK_EVIDENCE_ROOT &&
           contract["execution_nonce"] == active["execution_nonce"] &&
           contract["authorization_id"] == active["authorization_id"] &&
           roles == {
             "owner" => "MASTER_CEO_AGENT",
             "worker" => "BACKEND_JAVA_WORKER_AGENT",
             "independent_reviewers" => %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT],
             "task_gate_owner" => "MASTER_CEO_AGENT"
           } && contract["risk_level"] == "critical" &&
           contract["write_allowlist"] == decision.fetch("product_write_allowlist") &&
           contract["conditional_adjacent_allowlist_expansion"] ==
             decision.fetch("conditional_adjacent_allowlist_expansion") &&
           contract["fixed_action"] == FIXED_ACTION && contract["budget"] == TASK_BUDGET &&
           contract["authority_model"] == decision.fetch("authority_model") &&
           contract["transaction_model"] == decision.fetch("transaction_model") &&
           contract["recovery_and_checkpoint"] == decision.fetch("recovery_and_checkpoint") &&
           contract["local_external_effect_authority"] ==
             decision.fetch("local_external_effect_authority") &&
           contract["forbidden_external_effects"] ==
             decision.fetch("forbidden_external_effects") &&
           contract["clean_room"] == decision.fetch("clean_room") &&
           contract["acceptance"] == decision.fetch("acceptance") &&
           contract["anti_cycle"] == decision.fetch("anti_cycle") &&
           contract["required_evidence"] == %w[
             PRE_FIRST_PRODUCT_WRITE_OCI_PROBE
             SOURCE_TO_CLASS_AND_TOOLCHAIN_CUSTODY
             REAL_MYSQL_SPRING_TRANSACTION_AND_RECOVERY
             OCI_OBJECT_PROCESS_STDOUT_STDERR_EXIT_AND_CLEANUP
             FOCUSED_AND_FULL_MAVEN_TESTS
             FROZEN_CANDIDATE_MANIFEST
             CYCLE_1_FROZEN_FINDING_SET_AND_THREE_REVIEWS
             INTEGRATION_AND_CANONICAL_REPLAY_RECEIPTS
           ] && contract["stop_conditions"] == %w[
             OCI_PROBE_NON_PASS_BEFORE_PRODUCT_SOURCE_WRITE
             REJECTED_LINEAGE_ACCESS
             WRITE_OUTSIDE_EXACT_ALLOWLIST_OR_AUTHORIZED_ROOTS
             FORBIDDEN_EXTERNAL_EFFECT
             CANDIDATE_REPAIR_OR_REVIEW_BUDGET_EXHAUSTED
             FUTURE_RUNTIME_IDENTITY_PREFILL
             SCOPE_OR_PERMISSION_EXPANSION_REQUIRED
           ] && contract["lifecycle"] == decision.fetch("lifecycle"),
           "P3 MTRO Task Contract semantic or scope drift")
    assert(activation_parent["commit"] == active["activation_parent_commit"] &&
           activation_parent["tree"] == active["activation_parent_tree"],
           "P3 MTRO Contract activation parent drift")
    git_identity!(root, activation_parent.fetch("commit"), activation_parent.fetch("tree"),
                  "P3 MTRO activation parent")
    if require_worktree
      task_root = literal_path!(Pathname.new(TASK_WORKTREE),
                                "P3 MTRO active Task worktree", directory: true)
      branch = git!(task_root, "branch", "--show-current").strip
      assert(branch == TASK_BRANCH, "P3 MTRO active worktree branch drift")
      head = git!(task_root, "rev-parse", "HEAD").strip
      _stdout, _stderr, ancestor = Open3.capture3(
        "git", "-C", task_root.to_s, "merge-base", "--is-ancestor",
        activation_parent.fetch("commit"), head
      )
      assert(ancestor.success?, "P3 MTRO active worktree is not based on its activation parent")
      validate_task_base!(root, activation_parent.fetch("commit"), head, contract_identity)
    end

    authority_bytes = artifact_identity!(
      root, authority_identity, "P3 MTRO Task authority",
      exact_path: AUTHORITY_PATH, under: TASK_EVIDENCE_ROOT
    )
    authority_stat = File.lstat(AUTHORITY_PATH)
    assert(authority_stat.file? && !authority_stat.symlink? && authority_stat.nlink == 1,
           "P3 MTRO Task authority must be a single-link regular file")
    authority = parse_closed_json(authority_bytes, "P3 MTRO Task authority")
    authority = exact_keys(
      authority,
      %w[
        schema_version record_type status authorization_id execution_nonce task_id phase route_id
        stage_id kind objective_id decision activated_at_utc activation_parent branch worktree
        evidence_root contract write_allowlist conditional_adjacent_allowlist_expansion fixed_action
        budget implementation_attempt_for_milestone local_external_effect_authority
        forbidden_external_effects clean_room acceptance anti_cycle runtime_identity_channel roles
        founder_decision_required next_eligible_action long_term_goal_status
      ],
      "P3 MTRO Task authority"
    )
    initial_runtime = {
      "status" => "PENDING_TASK_OWNED_DISCOVERY",
      "task_activation_record" => nil,
      "candidate_freeze_record" => nil,
      "review_dispatch_record" => nil,
      "integration_record" => nil,
      "canonical_replay_record" => nil,
      "future_dynamic_identity_prefill_allowed" => false
    }
    Time.iso8601(authority.fetch("activated_at_utc"))
    assert(authority["schema_version"] == "p3-mtro-phase-delegated-task-authority/v1" &&
           authority["record_type"] == "P3_MTRO_P1_PHASE_DELEGATED_TASK_AUTHORITY" &&
           authority["status"] == "ACTIVE" && authority["task_id"] == TASK_ID &&
           authority["phase"] == "P3" && authority["route_id"] == ROUTE_ID &&
           authority["stage_id"] == contract["stage_id"] &&
           authority["kind"] == contract["kind"] && authority["objective_id"] == OBJECTIVE_ID &&
           authority["decision"] == decision_identity && authority["contract"] == contract_identity &&
           authority["branch"] == TASK_BRANCH && authority["worktree"] == TASK_WORKTREE &&
           authority["evidence_root"] == TASK_EVIDENCE_ROOT &&
           authority["execution_nonce"] == active["execution_nonce"] &&
           authority["authorization_id"] == active["authorization_id"] &&
           authority["activation_parent"] == activation_parent &&
           authority["write_allowlist"] == contract["write_allowlist"] &&
           authority["conditional_adjacent_allowlist_expansion"] ==
             contract["conditional_adjacent_allowlist_expansion"] &&
           authority["fixed_action"] == FIXED_ACTION && authority["budget"] == TASK_BUDGET &&
           authority["implementation_attempt_for_milestone"] == "2_OF_2_FINAL" &&
           authority["local_external_effect_authority"] ==
             decision.fetch("local_external_effect_authority") &&
           authority["forbidden_external_effects"] ==
             decision.fetch("forbidden_external_effects") &&
           authority["clean_room"] == decision.fetch("clean_room") &&
           authority["acceptance"] == decision.fetch("acceptance") &&
           authority["anti_cycle"] == decision.fetch("anti_cycle") &&
           authority["runtime_identity_channel"] == initial_runtime &&
           authority["roles"] == roles && authority["founder_decision_required"] == false &&
           authority["next_eligible_action"] ==
             "WORKER_RUN_P3_MTRO_PREWRITE_OCI_PROBE_THEN_IMPLEMENT" &&
           authority["long_term_goal_status"] == "ACTIVE",
           "P3 MTRO Task authority semantic or scope drift")
  rescue JSON::ParserError, DuplicateJsonKeyError, Psych::Exception, ArgumentError => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "P3 MTRO active authority invalid: #{e.message}"
  end

  def validate_terminal_outcome!(root, route, active, runtime_records, runtime_channel)
    bytes = artifact_identity!(
      root, route["terminal_outcome"], "P3 MTRO terminal outcome",
      under: TASK_EVIDENCE_ROOT
    )
    receipt = exact_keys(
      parse_closed_json(bytes, "P3 MTRO terminal outcome"),
      %w[
        schema_version record_type status task_id route_id execution_nonce authorization_id
        terminal_at_utc terminal_reason contract authority frozen_candidate task_gate_receipt
        candidate_integrated final_accounting resource_cleanup forbidden_external_effects_observed
        delivery_percent strict_exit_percent further_same_milestone_implementation_allowed
        founder_reserved_trigger founder_decision_required next_action_owner next_eligible_action
        project_actually_completed long_term_goal_status codex_goal_action
      ],
      "P3 MTRO terminal outcome"
    )
    assert(receipt["schema_version"] ==
             "p3-mtro-product-route-terminal-non-pass-receipt/v1" &&
           receipt["record_type"] == "P3_MTRO_PRODUCT_ROUTE_TERMINAL_NON_PASS_RECEIPT" &&
           receipt["task_id"] == TASK_ID && receipt["route_id"] == ROUTE_ID &&
           receipt["status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           %w[
             PREWRITE_OCI_PROBE_NON_PASS TASK_GATE_NON_PASS STOP_CONDITION BUDGET_EXHAUSTED
           ].include?(receipt["terminal_reason"]) &&
           receipt["execution_nonce"] == active["execution_nonce"] &&
           receipt["authorization_id"] == active["authorization_id"] &&
           receipt["contract"] == active["current_task_contract"] &&
           receipt["authority"] == active["authority_record"] &&
           receipt["candidate_integrated"] == false &&
           receipt["final_accounting"] == {
             "consumed" => FINAL_CONSUMED,
             "reserved" => {},
             "remaining" => ZERO_CAPACITY,
             "remaining_capacity_usable" => false
           } && receipt["resource_cleanup"] == {
             "task_branch_removed" => true,
             "task_worktree_removed" => true,
             "task_owned_oci_objects_absent" => true,
             "evidence_retained" => true
           } && receipt["forbidden_external_effects_observed"] == false &&
           receipt["delivery_percent"] == 25 && receipt["strict_exit_percent"] == 0 &&
           receipt["further_same_milestone_implementation_allowed"] == false &&
           receipt["founder_reserved_trigger"] == "NONE" &&
           receipt["founder_decision_required"] == false &&
           receipt["next_action_owner"] == "NONE" &&
           receipt["next_eligible_action"] ==
             "NO_ENGINEERING_ACTION_P3_HOLD_INCOMPLETE_FINAL_PRODUCT_FROZEN" &&
           receipt["project_actually_completed"] == false &&
           receipt["long_term_goal_status"] == "ACTIVE" &&
           receipt["codex_goal_action"] == "NONE_KEEP_ACTIVE",
           "P3 MTRO terminal outcome semantic drift")
    Time.iso8601(receipt.fetch("terminal_at_utc"))
    candidate = runtime_records["candidate_freeze_record"]
    expected_frozen_candidate = candidate && {
      "commit" => candidate["candidate_commit"], "tree" => candidate["candidate_tree"]
    }
    assert(receipt["frozen_candidate"] == expected_frozen_candidate,
           "P3 MTRO terminal receipt and runtime frozen candidate diverge")
    git_identity!(root, expected_frozen_candidate.fetch("commit"),
                  expected_frozen_candidate.fetch("tree"),
                  "P3 MTRO terminal frozen candidate") if expected_frozen_candidate
    assert(receipt["task_gate_receipt"].nil? && runtime_records["integration_record"].nil? &&
           runtime_channel["integration_record"].nil?,
           "P3 MTRO terminal lifecycle carries an unbound Task Gate or integration identity")
    route["terminal_outcome"]
  end

  def validate_acceptance_bundle!(root, current_gate, runtime_records, runtime_channel)
    bundle = exact_keys(
      current_gate["acceptance_bundle"],
      %w[
        candidate_commit candidate_tree frozen_finding_set task_gate_receipt independent_reviews
        integration canonical_replay phase_exit_eligibility_receipt
      ],
      "P3 MTRO acceptance bundle"
    )
    candidate_commit = bundle["candidate_commit"]
    candidate_tree = bundle["candidate_tree"]
    git_identity!(root, candidate_commit, candidate_tree, "P3 MTRO accepted candidate")
    frozen = runtime_records.fetch("candidate_freeze_record")
    assert(frozen["candidate_commit"] == candidate_commit &&
           frozen["candidate_tree"] == candidate_tree,
           "P3 MTRO accepted bundle differs from frozen runtime candidate")

    item_evidence_identities = {}
    STRICT_ITEMS.each do |item|
      record = exact_keys(
        current_gate.dig("required_items", item),
        %w[status candidate_commit candidate_tree evidence],
        "P3 MTRO strict item #{item}"
      )
      assert(record["status"] == "ACCEPTED" &&
             record["candidate_commit"] == candidate_commit &&
             record["candidate_tree"] == candidate_tree,
             "P3 MTRO strict item #{item} candidate or status drift")
      bytes = artifact_identity!(
        root, record["evidence"], "P3 MTRO strict item #{item} Evidence",
        under: TASK_EVIDENCE_ROOT
      )
      item_evidence_identities[item] = record["evidence"]
      evidence = exact_keys(
        parse_closed_json(bytes, "P3 MTRO strict item #{item} Evidence"),
        %w[
          schema_version record_type item_id status task_id route_id candidate_commit
          candidate_tree acceptance_basis evidence_manifest created_at_utc
        ],
        "P3 MTRO strict item #{item} Evidence"
      )
      assert(evidence["schema_version"] == "p3-mtro-exit-item-evidence/v1" &&
             evidence["record_type"] == "P3_MTRO_EXIT_ITEM_EVIDENCE" &&
             evidence["item_id"] == item && evidence["status"] == "ACCEPTED" &&
             evidence["task_id"] == TASK_ID && evidence["route_id"] == ROUTE_ID &&
             evidence["candidate_commit"] == candidate_commit &&
             evidence["candidate_tree"] == candidate_tree &&
             evidence["acceptance_basis"] == GATE_REQUIRED_FACTS.fetch(item),
             "P3 MTRO strict item #{item} Evidence semantic drift")
      manifest_bytes = artifact_identity!(
        root, evidence["evidence_manifest"], "P3 MTRO strict item #{item} manifest",
        under: TASK_EVIDENCE_ROOT
      )
      manifest = exact_keys(
        parse_closed_json(manifest_bytes, "P3 MTRO strict item #{item} manifest"),
        %w[
          schema_version record_type status item_id task_id route_id candidate_commit
          candidate_tree contract authority task_activation_record candidate_freeze_record
          fixed_action required_fact_ids facts zero_forbidden_external_effects created_at_utc
        ],
        "P3 MTRO strict item #{item} manifest"
      )
      required_fact_ids = GATE_REQUIRED_FACTS.fetch(item)
      facts = exact_keys(manifest["facts"], required_fact_ids,
                         "P3 MTRO strict item #{item} facts")
      facts.each do |fact_id, fact_identity|
        fact_bytes = artifact_identity!(
          root, fact_identity, "P3 MTRO acceptance fact #{fact_id}", under: TASK_EVIDENCE_ROOT
        )
        fact = exact_keys(
          parse_closed_json(fact_bytes, "P3 MTRO acceptance fact #{fact_id}"),
          %w[
            schema_version record_type status fact_id task_id route_id candidate_commit
            candidate_tree contract authority observations raw_evidence created_at_utc
          ],
          "P3 MTRO acceptance fact #{fact_id}"
        )
        raw_evidence = array(fact["raw_evidence"], "P3 MTRO fact #{fact_id} raw Evidence")
        raw_hashes = raw_evidence.map do |raw_identity|
          artifact_identity!(root, raw_identity, "P3 MTRO fact #{fact_id} raw Evidence leaf",
                             under: TASK_EVIDENCE_ROOT)
          raw_identity.fetch("sha256")
        end
        assert(fact["schema_version"] == "p3-mtro-acceptance-fact/v1" &&
               fact["record_type"] == "P3_MTRO_ACCEPTANCE_FACT" &&
               fact["status"] == "PASS" && fact["fact_id"] == fact_id &&
               fact["task_id"] == TASK_ID && fact["route_id"] == ROUTE_ID &&
               fact["candidate_commit"] == candidate_commit &&
               fact["candidate_tree"] == candidate_tree &&
               fact["contract"] == runtime_records.fetch("task_activation_record")["contract"] &&
               fact["authority"] == runtime_records.fetch("task_activation_record")["authority"] &&
               fact["observations"].is_a?(Hash) && !fact["observations"].empty? &&
               !raw_evidence.empty? && raw_hashes.uniq.length == raw_hashes.length,
               "P3 MTRO acceptance fact #{fact_id} semantic drift")
        validate_acceptance_fact_observations!(
          root: root,
          fact_id: fact_id,
          observations: fact["observations"],
          raw_evidence: raw_evidence,
          runtime_records: runtime_records,
          runtime_channel: runtime_channel,
          bundle: bundle
        )
        Time.iso8601(fact.fetch("created_at_utc"))
      end
      assert(manifest["schema_version"] == "p3-mtro-acceptance-evidence-manifest/v1" &&
             manifest["record_type"] == "P3_MTRO_ACCEPTANCE_EVIDENCE_MANIFEST" &&
             manifest["status"] == "PASS" && manifest["item_id"] == item &&
             manifest["task_id"] == TASK_ID && manifest["route_id"] == ROUTE_ID &&
             manifest["candidate_commit"] == candidate_commit &&
             manifest["candidate_tree"] == candidate_tree &&
             manifest["contract"] == runtime_records.fetch("task_activation_record")["contract"] &&
             manifest["authority"] == runtime_records.fetch("task_activation_record")["authority"] &&
             manifest["task_activation_record"] == runtime_channel["task_activation_record"] &&
             manifest["candidate_freeze_record"] == runtime_channel["candidate_freeze_record"] &&
             manifest["fixed_action"] == FIXED_ACTION &&
             manifest["required_fact_ids"] == required_fact_ids &&
             manifest["zero_forbidden_external_effects"] == true,
             "P3 MTRO strict item #{item} manifest semantic drift")
      Time.iso8601(manifest.fetch("created_at_utc"))
      Time.iso8601(evidence.fetch("created_at_utc"))
    end

    reviews = exact_keys(
      bundle["independent_reviews"], %w[cto security quality_evaluation],
      "P3 MTRO independent reviews"
    )
    expected_roles = {
      "cto" => "CTO_AGENT",
      "security" => "SECURITY_AGENT",
      "quality_evaluation" => "QUALITY_EVALUATION_AGENT"
    }
    review_identities = []
    reviews.each do |key, identity|
      review_identities << identity
      bytes = artifact_identity!(
        root, identity, "P3 MTRO #{key} review", under: TASK_EVIDENCE_ROOT
      )
      review = exact_keys(
        parse_closed_json(bytes, "P3 MTRO #{key} review"),
        %w[
          schema_version record_type role verdict task_id route_id candidate_commit
          candidate_tree review_cycle review_dispatch frozen_finding_set reviewer_worktree
          repair_record findings open_p0_p1_findings gate_relevance reviewed_at_utc
        ],
        "P3 MTRO #{key} review"
      )
      assert(review["schema_version"] == "p3-mtro-independent-review/v1" &&
             review["record_type"] == "P3_MTRO_INDEPENDENT_REVIEW" &&
             review["role"] == expected_roles.fetch(key) && review["verdict"] == "PASS" &&
             review["task_id"] == TASK_ID && review["route_id"] == ROUTE_ID &&
             review["candidate_commit"] == candidate_commit &&
             review["candidate_tree"] == candidate_tree &&
             [1, 2].include?(review["review_cycle"]) &&
             review["review_dispatch"] == runtime_channel["review_dispatch_record"] &&
             review["frozen_finding_set"] ==
               runtime_records.fetch("review_dispatch_record")["frozen_finding_set"] &&
             review["repair_record"] ==
               runtime_records.fetch("review_dispatch_record")["repair_record"] &&
             review["reviewer_worktree"] ==
               runtime_records.fetch("review_dispatch_record").dig("reviewer_worktrees", key) &&
             review["findings"] == [] &&
             review["open_p0_p1_findings"] == [] &&
             review["gate_relevance"] == "PASS",
             "P3 MTRO #{key} review semantic drift")
      Time.iso8601(review.fetch("reviewed_at_utc"))
    end
    assert(review_identities.map { |identity| identity.fetch("sha256") }.uniq.length == 3,
           "P3 MTRO independent reviews are not three distinct artifacts")
    review_documents = reviews.map do |key, identity|
      bytes = artifact_identity!(root, identity, "P3 MTRO #{key} review cycle check",
                                 under: TASK_EVIDENCE_ROOT)
      parse_closed_json(bytes, "P3 MTRO #{key} review cycle check")
    end
    review_cycles = review_documents.map { |review| review.fetch("review_cycle") }.uniq
    assert(review_cycles.length == 1 &&
           review_cycles.first == runtime_records.fetch("review_dispatch_record")["review_cycle"],
           "P3 MTRO three independent reviews do not share one frozen review cycle")
    finding_set, frozen_finding_ids = validate_frozen_finding_set!(
      root, bundle["frozen_finding_set"]
    )
    if review_cycles.first == 1
      assert(runtime_records.fetch("review_dispatch_record")["frozen_finding_set"].nil? &&
             runtime_records.fetch("review_dispatch_record")["repair_record"].nil? &&
             finding_set["candidate_commit"] == candidate_commit &&
             finding_set["candidate_tree"] == candidate_tree &&
             finding_set["cycle_1_reviews"] == reviews && frozen_finding_ids.empty?,
             "P3 MTRO Cycle 1 PASS does not close the complete frozen finding set")
    else
      assert(bundle["frozen_finding_set"] ==
               runtime_records.fetch("review_dispatch_record")["frozen_finding_set"] &&
             !frozen_finding_ids.empty? &&
             !runtime_records.fetch("review_dispatch_record")["repair_record"].nil?,
             "P3 MTRO Cycle 2 PASS lacks the single frozen-finding repair record")
    end

    task_gate_bytes = artifact_identity!(
      root, bundle["task_gate_receipt"], "P3 MTRO Task Gate receipt",
      under: TASK_EVIDENCE_ROOT
    )
    task_gate = exact_keys(
      parse_closed_json(task_gate_bytes, "P3 MTRO Task Gate receipt"),
      %w[
        schema_version record_type verdict task_id route_id candidate_commit candidate_tree
        frozen_finding_set independent_reviews required_item_evidence open_p0_p1_findings
        forbidden_external_effects_observed decided_at_utc
      ],
      "P3 MTRO Task Gate receipt"
    )
    assert(task_gate["schema_version"] == "p3-mtro-task-gate-pass-receipt/v1" &&
           task_gate["record_type"] == "P3_MTRO_TASK_GATE_PASS_RECEIPT" &&
           task_gate["verdict"] == "PASS" && task_gate["task_id"] == TASK_ID &&
           task_gate["route_id"] == ROUTE_ID && task_gate["candidate_commit"] == candidate_commit &&
           task_gate["candidate_tree"] == candidate_tree &&
           task_gate["frozen_finding_set"] == bundle["frozen_finding_set"] &&
           task_gate["independent_reviews"] == reviews &&
           task_gate["required_item_evidence"] == item_evidence_identities &&
           task_gate["open_p0_p1_findings"] == [] &&
           task_gate["forbidden_external_effects_observed"] == false,
           "P3 MTRO Task Gate receipt semantic drift")
    Time.iso8601(task_gate.fetch("decided_at_utc"))

    integration_bytes = artifact_identity!(
      root, bundle["integration"], "P3 MTRO integration", under: TASK_EVIDENCE_ROOT
    )
    integration = exact_keys(
      parse_closed_json(integration_bytes, "P3 MTRO integration"),
      %w[
        schema_version record_type status task_id route_id candidate_commit candidate_tree
        task_gate_receipt canonical_commit canonical_tree integrated_branch integrated_at_utc
      ],
      "P3 MTRO integration"
    )
    assert(integration["schema_version"] == "p3-mtro-integration-record/v1" &&
           integration["record_type"] == "P3_MTRO_INTEGRATION_RECORD" &&
           integration["status"] == "PASS" && integration["task_id"] == TASK_ID &&
           integration["route_id"] == ROUTE_ID &&
           integration["candidate_commit"] == candidate_commit &&
           integration["candidate_tree"] == candidate_tree &&
           integration["task_gate_receipt"] == bundle["task_gate_receipt"] &&
           integration["canonical_commit"] == candidate_commit &&
           integration["canonical_tree"] == candidate_tree &&
           integration["integrated_branch"] == "main",
           "P3 MTRO accepted candidate was not the canonical integration identity")
    Time.iso8601(integration.fetch("integrated_at_utc"))
    assert(bundle["integration"] == runtime_channel["integration_record"],
           "P3 MTRO acceptance and runtime integration identities differ")

    replay_bytes = artifact_identity!(
      root, bundle["canonical_replay"], "P3 MTRO canonical replay",
      under: TASK_EVIDENCE_ROOT
    )
    replay = exact_keys(
      parse_closed_json(replay_bytes, "P3 MTRO canonical replay"),
      %w[
        schema_version record_type status task_id route_id candidate_commit candidate_tree
        canonical_commit canonical_tree integration_record replay_count
        raw_replay_bundle forbidden_external_effects_observed replayed_at_utc
      ],
      "P3 MTRO canonical replay"
    )
    assert(replay["schema_version"] == "p3-mtro-canonical-replay/v1" &&
           replay["record_type"] == "P3_MTRO_CANONICAL_REPLAY_RECORD" &&
           replay["status"] == "PASS" && replay["replay_count"] == 1 &&
           replay["task_id"] == TASK_ID && replay["route_id"] == ROUTE_ID &&
           replay["candidate_commit"] == candidate_commit &&
           replay["candidate_tree"] == candidate_tree &&
           replay["canonical_commit"] == integration["canonical_commit"] &&
           replay["canonical_tree"] == integration["canonical_tree"] &&
           replay["integration_record"] == bundle["integration"] &&
           replay["forbidden_external_effects_observed"] == false,
           "P3 MTRO canonical replay semantic drift")
    replay_bundle = validate_canonical_replay_raw_bundle!(
      root: root, identity: replay["raw_replay_bundle"],
      candidate: runtime_records.fetch("candidate_freeze_record"),
      activation_identity: runtime_channel.fetch("task_activation_record"),
      integration_identity: bundle["integration"],
      canonical_commit: replay["canonical_commit"], canonical_tree: replay["canonical_tree"]
    )
    assert(Time.iso8601(replay_bundle.fetch("created_at_utc")) <=
           Time.iso8601(replay.fetch("replayed_at_utc")),
           "P3 MTRO accepted replay verdict predates its raw bundle")
    Time.iso8601(replay.fetch("replayed_at_utc"))
    assert(bundle["canonical_replay"] == runtime_channel["canonical_replay_record"],
           "P3 MTRO acceptance and runtime replay identities differ")

    phase_exit_bytes = artifact_identity!(
      root, bundle["phase_exit_eligibility_receipt"],
      "P3 MTRO Phase exit eligibility receipt", under: TASK_EVIDENCE_ROOT
    )
    phase_exit = exact_keys(
      parse_closed_json(phase_exit_bytes, "P3 MTRO Phase exit eligibility receipt"),
      %w[
        schema_version record_type status task_id route_id candidate_commit candidate_tree
        frozen_finding_set task_gate_receipt independent_reviews integration canonical_replay required_items
        compatibility_projection issued_at_utc
      ],
      "P3 MTRO Phase exit eligibility receipt"
    )
    assert(phase_exit["schema_version"] == "p3-mtro-phase-exit-eligibility-receipt/v1" &&
           phase_exit["record_type"] == "P3_MTRO_PHASE_EXIT_ELIGIBILITY_RECEIPT" &&
           phase_exit["status"] == "ELIGIBLE_AWAITING_FOUNDER_DECISION" &&
           phase_exit["task_id"] == TASK_ID && phase_exit["route_id"] == ROUTE_ID &&
           phase_exit["candidate_commit"] == candidate_commit &&
           phase_exit["candidate_tree"] == candidate_tree &&
           phase_exit["frozen_finding_set"] == bundle["frozen_finding_set"] &&
           phase_exit["task_gate_receipt"] == bundle["task_gate_receipt"] &&
           phase_exit["independent_reviews"] == reviews &&
           phase_exit["integration"] == bundle["integration"] &&
           phase_exit["canonical_replay"] == bundle["canonical_replay"] &&
           phase_exit["required_items"] == current_gate["required_items"] &&
           phase_exit["compatibility_projection"] ==
             current_gate["compatibility_projection"],
           "P3 MTRO Phase exit eligibility receipt semantic drift")
    Time.iso8601(phase_exit.fetch("issued_at_utc"))

    branch = git!(root, "branch", "--show-current").strip
    head = git!(root, "rev-parse", "HEAD").strip
    assert(branch == "main", "P3 MTRO accepted state is not on canonical main")
    _stdout, _stderr, ancestor = Open3.capture3(
      "git", "-C", root.to_s, "merge-base", "--is-ancestor", candidate_commit, head
    )
    assert(ancestor.success?, "P3 MTRO accepted candidate is not canonical-main ancestry")
    assert(head != candidate_commit,
           "P3 MTRO accepted lifecycle was prefilled into the Product candidate")
    changed = git_changed_paths!(
      root, candidate_commit, head, "P3 MTRO post-integration canonical synchronization"
    )
    assert(!changed.empty? &&
           (changed - %w[docs/aios/truth/project_state.yaml docs/PROJECT_CODE_MAP.md]).empty?,
           "P3 MTRO post-integration canonical changes exceed final Truth synchronization")
    assert(git!(root, "status", "--porcelain").strip.empty?,
           "P3 MTRO accepted canonical main is dirty")
    bundle["phase_exit_eligibility_receipt"]
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    decision = validate_decision!(root)
    route = exact_keys(
      truth["current_phase_route"],
      %w[
        schema_version route_id phase policy status lifecycle_stage execution_status
        scheduling_status phase_entry_status founder_phase_route_decision_required
        founder_reserved_trigger_resolved next_eligible_action objective_id claim_boundary
        strict_exit_gate fixed_action founder_route_decision installation_parent
        governing_constitution terminal_basis accepted_dependencies ordered_stages
        runtime_identity_channel terminal_outcome product_architecture
        local_external_effect_authority p3_p5_boundary clean_room anti_cycle progress
        external_effects lifecycle
      ],
      "P3 MTRO current Route"
    )
    lifecycle = route["lifecycle_stage"]
    profile = LIFECYCLE_PROFILES[lifecycle]
    assert(profile, "P3 MTRO lifecycle is not closed-schema: #{lifecycle.inspect}")
    expected_route_decision = DECISION.merge(
      "decision_id" => DECISION_ID,
      "operation_type" => OPERATION_TYPE,
      "reserved_trigger" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
    )
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID &&
           route["phase"] == "P3" && route["status"] == profile.fetch("route_status") &&
           route["policy"] == DELEGATION_POLICY && route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == false &&
           route["founder_reserved_trigger_resolved"] ==
             "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           route["scheduling_status"] == profile.fetch("scheduling_status") &&
           route["objective_id"] == OBJECTIVE_ID && route["fixed_action"] == FIXED_ACTION &&
           route["claim_boundary"] ==
             "ONE_ACTUAL_AGENT_HOST_AUTHORIZED_DURABLE_READ_ONLY_ARCHITECTURE_OVERVIEW_SHA256_INVOCATION_ON_TRUSTED_SINGLE_USER_LOCAL_HOST" &&
           route.dig("strict_exit_gate", "gate_id") == STRICT_GATE_ID &&
           route.dig("strict_exit_gate", "required_item_ids") == STRICT_ITEMS &&
           route["strict_exit_gate"] == {
             "gate_id" => STRICT_GATE_ID,
             "required_item_ids" => STRICT_ITEMS,
             "same_frozen_product_candidate_required" => true,
             "three_independent_reviewers_pass_required" => true,
             "canonical_replay_count" => 1
           } && route["founder_route_decision"] == expected_route_decision &&
           route["installation_parent"] == {
             "branch" => "main",
             "commit" => CANONICAL_START.fetch("commit"),
             "tree" => CANONICAL_START.fetch("tree"),
             "truth" => CANONICAL_START.fetch("truth"),
             "constitution" => CANONICAL_START.fetch("constitution")
           } && route["governing_constitution"] == CONSTITUTION &&
           route["accepted_dependencies"] == [
             "DURABLE_STATE_AND_CHECKPOINT_RESUME",
             "DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION"
           ] && route["product_architecture"] == PRODUCT_ARCHITECTURE &&
           route["local_external_effect_authority"] ==
             decision.fetch("local_external_effect_authority") &&
           route["p3_p5_boundary"] == decision.fetch("p3_p5_boundary") &&
           route["clean_room"] == decision.fetch("clean_room") &&
           route["anti_cycle"] == decision.fetch("anti_cycle") &&
           route["lifecycle"] == decision.fetch("lifecycle"),
           "P3 MTRO current Route authority drift")
    stage = exact_keys(
      array(route["ordered_stages"], "P3 MTRO ordered stages").first,
      %w[
        ordinal stage_id task_id kind status budget resources
        implementation_attempt_for_milestone contract_identity authority_identity
      ],
      "P3 MTRO sole Product stage"
    )
    assert(route["ordered_stages"].length == 1 && stage["ordinal"] == 19 &&
           stage["stage_id"] == "ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION_PRODUCT" &&
           stage["task_id"] == TASK_ID &&
           stage["kind"] == "PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL" &&
           stage["status"] == profile.fetch("stage_status") &&
           stage["budget"] == TASK_BUDGET &&
           stage["implementation_attempt_for_milestone"] == "2_OF_2_FINAL" &&
           stage.dig("resources", "branch") == TASK_BRANCH &&
           stage.dig("resources", "worktree") == TASK_WORKTREE &&
           stage.dig("resources", "evidence_root") == TASK_EVIDENCE_ROOT &&
           stage["resources"] == {
             "branch" => TASK_BRANCH,
             "worktree" => TASK_WORKTREE,
             "evidence_root" => TASK_EVIDENCE_ROOT,
             "contract_path" => TASK_CONTRACT_PATH
           },
           "P3 MTRO sole Product stage drift")
    progress = exact_keys(route["progress"],
                          %w[delivery_percent strict_exit_percent governance_progress_credit],
                          "P3 MTRO Route progress")
    assert(route["execution_status"] == profile.fetch("state") &&
           route["next_eligible_action"] == profile.fetch("action") &&
           progress == {
             "delivery_percent" => profile.fetch("delivery"),
             "strict_exit_percent" => profile.fetch("strict"),
             "governance_progress_credit" => 0
           } &&
           route["external_effects"] ==
             (profile.fetch("effects_enabled") ?
               ENABLED_TASK_LOCAL_ROUTE_EXTERNAL_EFFECTS : DISABLED_ROUTE_EXTERNAL_EFFECTS),
           "P3 MTRO lifecycle, progress or external-effect drift")
    terminal_basis = exact_keys(
      route["terminal_basis"],
      %w[
        trivs_product_receipt f2_terminal_receipt f2_diagnostic f2_scheduling_authority
        old_trivs_p2_scheduling_authority
      ],
      "P3 MTRO historical terminal basis"
    )
    assert(terminal_basis == {
             "trivs_product_receipt" => TRIVS_TERMINAL_RECEIPT,
             "f2_terminal_receipt" => F2_TERMINAL_RECEIPT,
             "f2_diagnostic" => F2_DIAGNOSTIC,
             "f2_scheduling_authority" => false,
             "old_trivs_p2_scheduling_authority" => false
           },
           "P3 MTRO historical terminal basis drift")
    old_route = mapping(
      truth["historical_p3_trivs_evidence_first_terminal_phase_route"],
      "historical P3 F2 terminal Route"
    )
    old_stages = array(old_route["ordered_stages"], "historical P3 F2 terminal stages")
    old_f2 = old_stages.find { |item|
      item["task_id"] == "AIOS-P3-TRIVS-F2_CANDIDATE_BOUND_ACCEPTANCE_HARNESS"
    }
    old_p2 = old_stages.find { |item|
      item["task_id"] ==
        "AIOS-P3-TRIVS-P2_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_FINAL_CLEAN_ROOM_PRODUCT"
    }
    assert(old_route["route_id"] ==
             "P3_TRUSTED_READ_ONLY_INVOCATION_EVIDENCE_FIRST_FINAL_CLEAN_ROOM_ROUTE_V1" &&
           old_route["lifecycle_stage"] == "FOUNDATION_ROUTE_TERMINAL_NON_PASS" &&
           old_f2.is_a?(Hash) && old_f2["status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           old_p2.is_a?(Hash) && old_p2["status"] == "LOCKED_NEVER_CREATED",
           "P3 MTRO superseded F2 Route history or no-scheduling boundary drift")
    envelope = exact_keys(
      truth["phase_execution_envelope"],
      %w[
        schema_version phase status authority_basis accounting_basis consumed limits reserved
        remaining remaining_capacity_usable milestone_order accepted_milestones ordered_stages
        implementation_accounting delivery_progress governance_progress_credit external_effects
      ],
      "P3 MTRO Phase envelope"
    )
    authority_basis = exact_keys(
      envelope["authority_basis"],
      %w[phase_entry_status source_route_ref source_route_id founder_route_decision],
      "P3 MTRO envelope authority basis"
    )
    envelope_stage = exact_keys(
      array(envelope["ordered_stages"], "P3 MTRO envelope stages").first,
      %w[ordinal stage_id task_id kind status implementation_attempt_for_milestone budget resources],
      "P3 MTRO envelope Product stage"
    )
    expected_consumed = profile.fetch("final_accounting") ? FINAL_CONSUMED : CONSUMED
    expected_reserved = profile.fetch("active") ? REMAINING : {}
    expected_remaining = if profile.fetch("final_accounting") || profile.fetch("active")
                           ZERO_CAPACITY
                         else
                           REMAINING
                         end
    expected_envelope_effects = if profile.fetch("active")
                                  ENVELOPE_EXTERNAL_EFFECTS_ACTIVE
                                elsif profile.fetch("final_accounting")
                                  ENVELOPE_EXTERNAL_EFFECTS_FINAL
                                else
                                  ENVELOPE_EXTERNAL_EFFECTS_LOCKED
                                end
    expected_accepted_milestones = [
      "DURABLE_STATE_AND_CHECKPOINT_RESUME",
      "DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION"
    ]
    expected_accepted_milestones <<
      "ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION_PRODUCT" if profile.fetch("accepted")
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" &&
           envelope["phase"] == "P3" && envelope["status"] == profile.fetch("phase_status") &&
           authority_basis == {
             "phase_entry_status" => "AUTHORIZED",
             "source_route_ref" => "current_phase_route",
             "source_route_id" => ROUTE_ID,
             "founder_route_decision" => DECISION.merge("decision_id" => DECISION_ID)
           } && envelope["accounting_basis"] ==
             "NON_RESETTABLE_CUMULATIVE_P3_FOUNDER_ENVELOPE" &&
           envelope["consumed"] == expected_consumed && envelope["limits"] == LIMITS &&
           envelope["reserved"] == expected_reserved &&
           envelope["remaining"] == expected_remaining &&
           envelope["remaining_capacity_usable"] == profile.fetch("task_creation") &&
           envelope["milestone_order"] == [
             "DURABLE_STATE_AND_CHECKPOINT_RESUME",
             "DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION",
             "ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION_PRODUCT"
           ] && envelope["accepted_milestones"] == expected_accepted_milestones &&
           envelope["ordered_stages"].length == 1 &&
           envelope_stage == stage.reject { |key, _| %w[contract_identity authority_identity].include?(key) } &&
           envelope["implementation_accounting"] == {
             "prior_product_task_id" =>
               "AIOS-P3-TRIVS-P1_ACTUAL_AGENT_TRUSTED_READ_ONLY_INVOCATION_VERTICAL_SLICE",
             "prior_implementation_attempt" => "1_OF_2",
             "current_implementation_attempt" => "2_OF_2_FINAL",
             "third_implementation_allowed" => false
           } && envelope["delivery_progress"] == {
             "accepted_dependencies" => 2,
             "route_delivery_milestones_accepted" => profile.fetch("accepted") ? 1 : 0,
             "route_delivery_milestones_total" => 1,
             "percent" => profile.fetch("delivery"),
             "strict_exit_gate_percent" => profile.fetch("strict")
           } && envelope["governance_progress_credit"] == 0 &&
           envelope["external_effects"] == expected_envelope_effects,
           "P3 MTRO Phase envelope or non-resettable accounting drift")

    control = exact_keys(
      truth["founder_escalation_control"],
      %w[
        schema_version disposition source_event reserved_trigger resolved_strategy_decision
        phase_gate_status founder_decision_required next_action_owner next_eligible_action
      ],
      "P3 MTRO Founder escalation"
    )
    source_event = exact_keys(control["source_event"], %w[kind decision_id status],
                              "P3 MTRO Founder source event")
    reserved_trigger = exact_keys(control["reserved_trigger"], %w[category evidence],
                                  "P3 MTRO reserved trigger")
    resolved = exact_keys(
      control["resolved_strategy_decision"],
      %w[category decision_id path byte_length sha256 result],
      "P3 MTRO resolved strategy decision"
    )
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == profile.fetch("disposition") &&
           source_event == {
             "kind" => "FOUNDER_P3_MTRO_FINAL_PRODUCT_ROUTE_AUTHORIZED",
             "decision_id" => DECISION_ID,
             "status" => profile.fetch("state")
           } && reserved_trigger["category"] == profile.fetch("reserved_trigger") &&
           resolved == DECISION.merge(
             "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
             "decision_id" => DECISION_ID,
             "result" => profile.fetch("resolved_result")
           ) && control["phase_gate_status"] == profile.fetch("phase_gate_status") &&
           control["founder_decision_required"] == profile.fetch("founder_required") &&
           control["next_action_owner"] == profile.fetch("next_owner") &&
           control["next_eligible_action"] == profile.fetch("action"),
           "P3 MTRO Founder escalation continuity drift")
    assert(reserved_trigger["evidence"].nil?,
           "P3 MTRO ordinary lifecycle falsely interrupts Founder") unless
      profile.fetch("founder_required")

    boundary = exact_keys(
      truth["phase_boundary"],
      %w[
        phase phase_execution_status task_creation_allowed task_creation_scope
        task_creation_lock_after_activation p3_entry_authorized allowed_task_kinds
        allowed_capabilities role_write_roots immutable_authority_paths
        allowed_independent_reviewers required_reviewers_by_risk founder_reserved_risk_levels
        deferred_capabilities default_external_effects founder_decision_required
        founder_decision_required_scope escalation_reason user_action_required
        phase_route_decision_required phase_route_user_action_required next_eligible_action
      ],
      "P3 MTRO Phase boundary"
    )
    assert(boundary["phase"] == "P3" &&
           boundary["phase_execution_status"] == profile.fetch("phase_status") &&
           boundary["task_creation_allowed"] == profile.fetch("task_creation") &&
           boundary["task_creation_scope"] == profile.fetch("boundary_scope") &&
           boundary["task_creation_lock_after_activation"] == true &&
           boundary["p3_entry_authorized"] == true &&
           boundary["allowed_task_kinds"] ==
             (profile.fetch("task_creation") ? ["PRODUCT_IMPLEMENTATION_SECOND_AND_FINAL"] : []) &&
           boundary["allowed_capabilities"] == STRICT_ITEMS &&
           boundary["role_write_roots"] == ROLE_WRITE_ROOTS &&
           boundary["immutable_authority_paths"] == IMMUTABLE_AUTHORITY_PATHS &&
           boundary["allowed_independent_reviewers"] == REVIEWER_ROLES &&
           boundary["required_reviewers_by_risk"] == {"critical" => REVIEWER_ROLES} &&
           boundary["founder_reserved_risk_levels"] == ["critical"] &&
           boundary["deferred_capabilities"] == DEFERRED_CAPABILITIES &&
           boundary["default_external_effects"] == DISABLED_ROUTE_EXTERNAL_EFFECTS &&
           boundary["founder_decision_required"] == profile.fetch("founder_required") &&
           boundary["founder_decision_required_scope"] ==
             (profile.fetch("founder_required") ? "PHASE_ENTRY_OR_EXIT" : "NONE") &&
           boundary["escalation_reason"] ==
             (profile.fetch("founder_required") ? "P3_STRICT_EXIT_GATE_COMPLETE" : nil) &&
           boundary["user_action_required"] == profile.fetch("founder_required") &&
           boundary["phase_route_decision_required"] == false &&
           boundary["phase_route_user_action_required"] == false &&
           boundary["next_eligible_action"] == profile.fetch("action"),
           "P3 MTRO Phase boundary or deferred-capability drift")

    delegation = exact_keys(
      truth["phase_delegation"],
      %w[
        status model decision_source phase_gate_owner task_selection_owner
        task_authorization_owner task_gate_owner p3_entry_authorized founder_reserved_decisions
        agent_delegated_decisions escalation_conditions anti_loop claim_boundary
      ],
      "P3 MTRO Phase delegation"
    )
    assert(delegation["status"] == profile.fetch("phase_status") &&
           delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION" &&
           delegation["decision_source"] == DECISION_ID &&
           delegation["phase_gate_owner"] == "HUMAN_FOUNDER" &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation["p3_entry_authorized"] == true &&
           delegation["founder_reserved_decisions"] == FOUNDER_RESERVED_DECISIONS &&
           delegation["agent_delegated_decisions"] == AGENT_DELEGATED_DECISIONS &&
           delegation["escalation_conditions"] == ["EXACT_FOUNDER_RESERVED_TRIGGER_ONLY"] &&
           delegation["anti_loop"] == DELEGATION_ANTI_LOOP &&
           delegation["claim_boundary"] ==
             "P3_ONE_FINAL_MTRO_PRODUCT_TASK_ONLY_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
           "P3 MTRO delegation or anti-loop drift")

    active = exact_keys(
      truth["active_work"],
      %w[
        current_task selected_task current_task_status current_task_contract
        current_task_contract_sha256 current_execution_authorization
        current_execution_authorization_sha256 authority_record authority_scope_conformance
        execution_nonce execution_nonce_status authorization_id activation_parent_commit
        activation_parent_tree strategic_installation_parent task_resource_state
        planned_task_branch planned_task_worktree planned_execution_evidence_root task_branch
        task_worktree execution_evidence_root dependency_custody_root allowlisted_paths
        current_task_budget next_stage_budget roles runtime_identity_channel external_effects
        offsite_target founder_reserved_authorization founder_reserved_authorization_sha256
        founder_decision_required founder_decision_required_scope escalation_reason
        user_action_required phase_route_decision_required phase_route_user_action_required
        historical_terminal_accounting next_eligible_action
      ],
      "P3 MTRO active work"
    )
    assert(active["selected_task"] == TASK_ID &&
           active["current_task_status"] == profile.fetch("task_status") &&
           active["strategic_installation_parent"] == {
             "commit" => CANONICAL_START.fetch("commit"),
             "tree" => CANONICAL_START.fetch("tree")
           } && active["task_resource_state"] == profile.fetch("task_resource_state") &&
           active["planned_task_branch"] == TASK_BRANCH &&
           active["planned_task_worktree"] == TASK_WORKTREE &&
           active["planned_execution_evidence_root"] == TASK_EVIDENCE_ROOT &&
           active["offsite_target"].nil? &&
           active["founder_reserved_authorization"] == DECISION.fetch("path") &&
           active["founder_reserved_authorization_sha256"] == DECISION.fetch("sha256") &&
           active["founder_decision_required"] == profile.fetch("founder_required") &&
           active["founder_decision_required_scope"] ==
             (profile.fetch("founder_required") ? "PHASE_ENTRY_OR_EXIT" : "NONE") &&
           active["escalation_reason"] ==
             (profile.fetch("founder_required") ? "P3_STRICT_EXIT_GATE_COMPLETE" : nil) &&
           active["user_action_required"] == profile.fetch("founder_required") &&
           active["phase_route_decision_required"] == false &&
           active["phase_route_user_action_required"] == false &&
           active["historical_terminal_accounting"] == {
             "consumed_engineering_tasks" => 18,
             "consumed_engineering_hours" => 520,
             "consumed_calendar_days" => 122,
             "latest_terminal_task_id" => "AIOS-P3-TRIVS-F2_CANDIDATE_BOUND_ACCEPTANCE_HARNESS",
             "latest_terminal_receipt_sha256" => F2_TERMINAL_RECEIPT.fetch("sha256")
           } && active["next_eligible_action"] == profile.fetch("action"),
           "P3 MTRO active-work common projection drift")
    if lifecycle == "PRODUCT_ELIGIBLE_NOT_ACTIVATED"
      assert(active["current_task"] == "NONE" && active["current_task_contract"].nil? &&
             active["current_task_contract_sha256"].nil? &&
             active["current_execution_authorization"].nil? &&
             active["current_execution_authorization_sha256"].nil? &&
             active["authority_record"].nil? &&
             active["authority_scope_conformance"] == "NOT_YET_ISSUED" &&
             active["execution_nonce"].nil? &&
             active["execution_nonce_status"] == "NOT_YET_ISSUED" &&
             active["authorization_id"].nil? && active["activation_parent_commit"].nil? &&
             active["activation_parent_tree"].nil? && active["task_branch"].nil? &&
             active["task_worktree"].nil? && active["execution_evidence_root"].nil? &&
             active["dependency_custody_root"].nil? && active["allowlisted_paths"] == [] &&
             active["current_task_budget"] == {} && active["next_stage_budget"] == TASK_BUDGET &&
             active["roles"] == {
               "owner" => "MASTER_CEO_AGENT", "worker" => "NOT_YET_ASSIGNED",
               "quality_owner" => "NOT_YET_ASSIGNED",
               "independent_reviewers" => %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT]
             } && active["external_effects"] == DISABLED_ACTIVE_EXTERNAL_EFFECTS,
             "P3 MTRO eligible active-work projection drift")
      assert(stage["contract_identity"].nil? && stage["authority_identity"].nil? &&
             !root.join(TASK_CONTRACT_PATH).exist? && !Pathname.new(AUTHORITY_PATH).exist? &&
             !Pathname.new(TASK_WORKTREE).exist?,
             "P3 MTRO Task resources exist before activation")
    else
      assert(active["current_task"] == (profile.fetch("active") ? TASK_ID : "NONE") &&
             active["current_task_contract"].is_a?(Hash) &&
             active["current_task_contract_sha256"] ==
               active.dig("current_task_contract", "sha256") &&
             active["current_execution_authorization"] == AUTHORITY_PATH &&
             active["current_execution_authorization_sha256"] ==
               active.dig("authority_record", "sha256") &&
             active["authority_scope_conformance"] == "PASS_EXACT_TASK_SCOPE" &&
             active["execution_nonce"].is_a?(String) &&
             active["authorization_id"].is_a?(String) &&
             active["activation_parent_commit"].is_a?(String) &&
             active["activation_parent_tree"].is_a?(String) &&
             active["dependency_custody_root"] ==
               File.join(TASK_EVIDENCE_ROOT, "dependency-custody") &&
             active["allowlisted_paths"] == decision.fetch("product_write_allowlist") &&
             active["current_task_budget"] == TASK_BUDGET && active["next_stage_budget"] == {} &&
             active["roles"] == {
               "owner" => "MASTER_CEO_AGENT", "worker" => "BACKEND_JAVA_WORKER_AGENT",
               "quality_owner" => "QUALITY_EVALUATION_AGENT",
               "independent_reviewers" => %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT]
             } && stage["contract_identity"] == active["current_task_contract"] &&
             stage["authority_identity"] == active["authority_record"],
             "P3 MTRO activated or final Task authority projection drift")
      if profile.fetch("active")
        assert(active["execution_nonce_status"] == "ACTIVE" &&
               active["task_branch"] == TASK_BRANCH && active["task_worktree"] == TASK_WORKTREE &&
               active["execution_evidence_root"] == TASK_EVIDENCE_ROOT &&
               active["external_effects"] == ENABLED_TASK_LOCAL_ACTIVE_EXTERNAL_EFFECTS,
               "P3 MTRO active Task resource or external-effect drift")
      else
        expected_nonce_status = profile.fetch("accepted") ?
          "CONSUMED_ACCEPTED" : "CONSUMED_TERMINAL_NON_PASS"
        assert(active["execution_nonce_status"] == expected_nonce_status &&
               active["task_branch"].nil? && active["task_worktree"].nil? &&
               active["execution_evidence_root"] == TASK_EVIDENCE_ROOT &&
               active["external_effects"] == DISABLED_ACTIVE_EXTERNAL_EFFECTS,
               "P3 MTRO final Task resource closure drift")
      end
      validate_active_authority!(root, truth, decision, require_worktree: profile.fetch("active"))
    end
    assert(route["runtime_identity_channel"] == active["runtime_identity_channel"],
           "P3 MTRO Route and active-work runtime channels diverge")
    runtime_records = validate_runtime_identity_channel!(
      root, active["runtime_identity_channel"], lifecycle, active: active
    )

    p3 = exact_keys(
      truth.dig("strict_phase_gate_ledger", "phases", "P3"),
      %w[
        status entry_authorized execution_started phase_entry_decision exit_gate_authority
        required_item_ids required_items current_exit_gate founder_phase_gate
      ],
      "P3 MTRO strict Gate"
    )
    phase_entry_decision = exact_keys(
      p3["phase_entry_decision"], %w[decision_id path byte_length sha256],
      "P3 MTRO Phase entry decision"
    )
    expected_phase_entry_decision = {
      "decision_id" => "AUTHORIZE_P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY_V1",
      "path" =>
        "/Users/lijunpeng/Developer/.sourcelens-audit/p3-phase-entry-20260819/decision/FOUNDER_P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY_V1.json",
      "byte_length" => 4_105,
      "sha256" => "23a50848a182fa7865f8e96c78bd9001ff2db6682d8d19dc49a0d4768994d6eb"
    }
    assert(phase_entry_decision == expected_phase_entry_decision,
           "P3 MTRO Phase entry decision drift")
    file_identity!(phase_entry_decision.fetch("path"), phase_entry_decision,
                   "P3 MTRO Phase entry decision")
    exit_gate_authority = exact_keys(
      p3["exit_gate_authority"], %w[source required_exit_evidence],
      "P3 MTRO inherited Exit Gate authority"
    )
    compatibility = exact_keys(
      p3.dig("required_items", COMPATIBILITY_ITEM),
      %w[status task_history_key task_id acceptance_commit acceptance_tree gate_evidence],
      "P3 MTRO compatibility Gate item"
    )
    compatibility_evidence = exact_keys(
      compatibility["gate_evidence"], %w[receipt_type path byte_length sha256],
      "P3 MTRO compatibility Evidence"
    )
    current_gate = exact_keys(
      p3["current_exit_gate"],
      %w[
        gate_id authority required_item_ids required_items same_frozen_candidate_required
        three_independent_reviewers_pass_required canonical_replay_required acceptance_bundle
        compatibility_projection
      ],
      "P3 MTRO current strict Gate"
    )
    required_items = exact_keys(current_gate["required_items"], STRICT_ITEMS,
                                "P3 MTRO current required items")
    required_items.each do |item, record|
      exact_keys(record, %w[status candidate_commit candidate_tree evidence],
                 "P3 MTRO strict item #{item}")
    end
    bundle = exact_keys(
      current_gate["acceptance_bundle"],
      %w[
        candidate_commit candidate_tree frozen_finding_set task_gate_receipt independent_reviews
        integration canonical_replay phase_exit_eligibility_receipt
      ],
      "P3 MTRO acceptance bundle"
    )
    reviews = exact_keys(bundle["independent_reviews"], %w[cto security quality_evaluation],
                         "P3 MTRO acceptance reviews")
    projection = exact_keys(
      current_gate["compatibility_projection"],
      %w[item_id status acceptance_requires_all_current_items],
      "P3 MTRO compatibility projection"
    )
    founder_gate = exact_keys(
      p3["founder_phase_gate"], %w[status decision_id path byte_length sha256],
      "P3 MTRO Founder Phase Gate"
    )
    assert(p3["entry_authorized"] == true && p3["execution_started"] == true &&
           exit_gate_authority == {
             "source" => "STRICT_PHASE_ROUTE_AUTHORITY",
             "required_exit_evidence" => "Resume, isolation, permission and trace tests"
           } &&
           p3["required_item_ids"] == [COMPATIBILITY_ITEM] &&
           p3["required_items"].keys == [COMPATIBILITY_ITEM] &&
           current_gate["gate_id"] == STRICT_GATE_ID &&
           current_gate["authority"] == DECISION.merge("decision_id" => DECISION_ID) &&
           current_gate["required_item_ids"] == STRICT_ITEMS &&
           current_gate["same_frozen_candidate_required"] == true &&
           current_gate["three_independent_reviewers_pass_required"] == true &&
           current_gate["canonical_replay_required"] == true &&
           projection["item_id"] == COMPATIBILITY_ITEM &&
           projection["acceptance_requires_all_current_items"] == true,
           "P3 MTRO strict Gate shape drift")
    phase_exit_identity = nil
    if profile.fetch("accepted")
      phase_exit_identity = validate_acceptance_bundle!(
        root, current_gate, runtime_records, active["runtime_identity_channel"]
      )
      candidate_commit = bundle["candidate_commit"]
      candidate_tree = bundle["candidate_tree"]
      assert(p3["status"] == "EXIT_GATE_READY" &&
             compatibility["status"] == "ACCEPTED" &&
             compatibility["task_history_key"] == "p3_mtro_task_status" &&
             compatibility["task_id"] == TASK_ID &&
             compatibility["acceptance_commit"] == candidate_commit &&
             compatibility["acceptance_tree"] == candidate_tree &&
             compatibility_evidence == phase_exit_identity.merge(
               "receipt_type" => "P3_MTRO_PHASE_EXIT_ELIGIBILITY_RECEIPT_V1"
             ) && projection["status"] == "ACCEPTED" &&
             founder_gate == phase_exit_identity.merge(
               "status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION", "decision_id" => nil
             ) && reserved_trigger["evidence"] == phase_exit_identity,
             "P3 MTRO accepted Gate, compatibility or Founder evidence drift")
    else
      nil_bundle = {
        "candidate_commit" => nil, "candidate_tree" => nil, "frozen_finding_set" => nil,
        "task_gate_receipt" => nil,
        "independent_reviews" => {
          "cto" => nil, "security" => nil, "quality_evaluation" => nil
        },
        "integration" => nil, "canonical_replay" => nil,
        "phase_exit_eligibility_receipt" => nil
      }
      assert(p3["status"] == "INCOMPLETE" &&
             compatibility["status"] == "MISSING" && compatibility["task_history_key"].nil? &&
             compatibility["task_id"].nil? && compatibility["acceptance_commit"].nil? &&
             compatibility["acceptance_tree"].nil? && compatibility_evidence == {
               "receipt_type" => nil, "path" => nil, "byte_length" => nil, "sha256" => nil
             } && STRICT_ITEMS.all? { |item|
               required_items[item] == {
                 "status" => "MISSING", "candidate_commit" => nil,
                 "candidate_tree" => nil, "evidence" => nil
               }
             } && bundle == nil_bundle && projection["status"] == "MISSING" &&
             founder_gate == {
               "status" => "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS", "decision_id" => nil,
               "path" => nil, "byte_length" => nil, "sha256" => nil
             },
             "P3 MTRO strict Gate false acceptance")
    end

    if profile.fetch("terminal")
      validate_terminal_outcome!(
        root, route, active, runtime_records, active["runtime_identity_channel"]
      )
    else
      assert(route["terminal_outcome"].nil?,
             "P3 MTRO non-terminal lifecycle contains terminal outcome")
    end

    goal = mapping(truth["goal"], "P3 MTRO Goal")
    goal_decision = exact_keys(
      goal["current_strategic_decision"],
      %w[path byte_length sha256 decision_id source_body source_attachment],
      "P3 MTRO Goal decision"
    )
    accepted_outcomes = [
      "DURABLE_STATE_AND_CHECKPOINT_RESUME",
      "DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION"
    ]
    accepted_outcomes <<
      "ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION_PRODUCT" if profile.fetch("accepted")
    phase_claim = exact_keys(
      truth["phase_execution_claim"],
      %w[
        current_route_claim current_task_claim selected_next_task real_engineering_progress
        product_capability_changed accepted_outcomes revised_research_exit_percent
        original_capability_progress_percent p3_entry_authorized p3_exit_gate_progress_percent
        p3_delivery_progress_percent phase_local_allowed phase_local_frozen_capabilities
        historical_terminal_rules mandatory_priority_rule not_authorized_in_current_phase
        deferred_to_p5_after_p4 forbidden_without_separate_founder_authority
        task_creation_allowed remaining_capacity_usable held_read_allowed
        candidate_integration_allowed next_eligible_action
      ],
      "P3 MTRO Phase execution claim"
    )
    expected_phase_local_action = profile.fetch("next_owner") == "NONE" ? [] : [profile.fetch("action")]
    expected_priority = case lifecycle
                        when "PRODUCT_ELIGIBLE_NOT_ACTIVATED"
                          "ACTIVATE_AND_EXECUTE_EXACT_MTRO_P1_SECOND_AND_FINAL_PRODUCT_TASK"
                        when "PRODUCT_TASK_ACTIVE"
                          "COMPLETE_EXACT_MTRO_P1_WITHIN_FROZEN_TASK_GATE"
                        when "PRODUCT_ROUTE_TERMINAL_NON_PASS"
                          "NO_FURTHER_P3_IMPLEMENTATION_KEEP_PHASE_INCOMPLETE"
                        else
                          "FOUNDER_DECIDE_P3_PHASE_GATE_WITHOUT_P4_AUTO_ENTRY"
                        end
    assert(phase_claim["current_route_claim"] == ROUTE_ID &&
           phase_claim["current_task_claim"] == (profile.fetch("active") ? TASK_ID : "NONE") &&
           phase_claim["selected_next_task"] ==
             (lifecycle == "PRODUCT_ELIGIBLE_NOT_ACTIVATED" ? TASK_ID : "NONE") &&
           phase_claim["real_engineering_progress"] == profile.fetch("engineering_progress") &&
           phase_claim["product_capability_changed"] == profile.fetch("accepted") &&
           phase_claim["accepted_outcomes"] == accepted_outcomes &&
           phase_claim["revised_research_exit_percent"] == 100 &&
           phase_claim["original_capability_progress_percent"] == 0 &&
           phase_claim["p3_entry_authorized"] == true &&
           phase_claim["p3_exit_gate_progress_percent"] == profile.fetch("strict") &&
           phase_claim["p3_delivery_progress_percent"] == profile.fetch("delivery") &&
           phase_claim["phase_local_allowed"] == expected_phase_local_action &&
           phase_claim["phase_local_frozen_capabilities"] == %w[
             FOUNDATION_OR_PREFLIGHT_TASK AUDIT_TASK THIRD_PRODUCT_TASK CANDIDATE_3
             SECOND_REPAIR THIRD_REVIEW
           ] && phase_claim["historical_terminal_rules"] == [
             "TRIVS_AND_F2_TERMINAL_IDENTITIES_ACCOUNTING_LIFECYCLE_VERDICT_PRESERVED",
             "NO_REJECTED_ENGINEERING_LINEAGE_READ_COMPARE_COPY_EXECUTE_RESTORE_REPAIR_OR_REUSE"
           ] && phase_claim["mandatory_priority_rule"] == expected_priority &&
           phase_claim["not_authorized_in_current_phase"] == %w[
             P4_ENTRY P5_EARLY_ENTRY INTERNET DNS HTTP_HTTPS PROVIDER EXTERNAL_SECRET
             EXTERNAL_CREDENTIAL REMOTE PRODUCTION PUBLIC
           ] && phase_claim["deferred_to_p5_after_p4"] == [
             "EXHAUSTIVE_HOSTILE_DOCKER_MYSQL_AND_SEVEN_KILL_POINT_HARDENING"
           ] && phase_claim["forbidden_without_separate_founder_authority"] == %w[
             NEW_PHASE_ROUTE_CHANGE ENVELOPE_EXPANSION_OR_REFUND UNDECLARED_EXTERNAL_EFFECT
           ] && phase_claim["task_creation_allowed"] == profile.fetch("task_creation") &&
           phase_claim["remaining_capacity_usable"] == profile.fetch("task_creation") &&
           phase_claim["held_read_allowed"] == false &&
           phase_claim["candidate_integration_allowed"] == false &&
           phase_claim["next_eligible_action"] == profile.fetch("action"),
           "P3 MTRO Phase execution claim drift")
    assert(truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "phase_name") == "Single-Agent Runtime + Minimum Trust" &&
           truth.dig("project", "canonical_branch") == "main" &&
           truth.dig("project", "phase_execution_status") == profile.fetch("phase_status") &&
           truth.dig("project", "current_route_execution_status") == profile.fetch("state") &&
           truth.dig("project", "p3_entry_status") == "AUTHORIZED" &&
           truth.dig("project", "p3_execution_status") == profile.fetch("p3_status") &&
           truth.dig("project", "p4_entry_status") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["identity_status"] ==
             "FOUNDER_MANUALLY_INSTALLED_OPTIMIZED_LONG_TERM_GOAL_IDENTITY_ACTIVE" &&
           goal["current_task_authority"] ==
             (profile.fetch("active") ? active["authorization_id"] : "NONE") &&
           goal["project_actually_completed"] == false &&
           goal["long_term_goal_status"] == "ACTIVE" &&
           goal["codex_goal_action"] == "NONE_KEEP_ACTIVE" &&
           goal["current_state_note"] == profile.fetch("goal_state_note") &&
           goal_decision["decision_id"] == DECISION_ID &&
           goal_decision.slice("path", "byte_length", "sha256") == DECISION &&
           goal_decision["source_body"] == {
             "source_attachment_ref" => "source_attachment",
             "byte_length" => DIRECT_AUTHORIZATION.fetch("byte_length"),
             "sha256" => DIRECT_AUTHORIZATION.fetch("sha256"),
             "canonicalization" => "UTF8_LF_WITH_EXACTLY_ONE_TRAILING_LF"
           } && goal_decision["source_attachment"] == DIRECT_AUTHORIZATION &&
           truth.dig("claim_boundary", "current_phase_route") == ROUTE_ID &&
           truth.dig("claim_boundary", "current_task") ==
             (profile.fetch("active") ? TASK_ID : "NONE") &&
           truth.dig("claim_boundary", "selected_task") ==
             (%w[PRODUCT_ELIGIBLE_NOT_ACTIVATED PRODUCT_TASK_ACTIVE].include?(lifecycle) ?
               TASK_ID : "NONE") &&
           truth.dig("claim_boundary", "current_task_status") == profile.fetch("task_status") &&
           truth.dig("claim_boundary", "next_eligible_action") == profile.fetch("action") &&
           truth.dig("claim_boundary", "real_engineering_progress") ==
             profile.fetch("engineering_progress") &&
           truth.dig("claim_boundary", "p3_status") == profile.fetch("p3_status") &&
           truth.dig("claim_boundary", "p3_phase_envelope_status") == profile.fetch("phase_status") &&
           truth.dig("claim_boundary", "p3_exit_gate_progress_percent") == profile.fetch("strict") &&
           truth.dig("claim_boundary", "p3_delivery_progress_percent") == profile.fetch("delivery") &&
           truth.dig("claim_boundary", "p3_accepted_milestones") == accepted_outcomes &&
           truth.dig("claim_boundary", "p3_capability_milestone_status") ==
             profile.fetch("capability_status") &&
           truth.dig("claim_boundary", "p3_mtro_route_decision_sha256") == DECISION.fetch("sha256") &&
           truth.dig("claim_boundary", "p3_mtro_route_source_body_sha256") ==
             DIRECT_AUTHORIZATION.fetch("sha256") &&
           truth.dig("claim_boundary", "p3_mtro_route_stage") == lifecycle &&
           truth.dig("claim_boundary", "p3_mtro_task_status") == profile.fetch("task_status") &&
           truth.dig("claim_boundary", "p3_mtro_implementation_attempt") == "2_OF_2_FINAL" &&
           truth.dig("claim_boundary", "p3_mtro_candidate_integrated") == profile.fetch("accepted") &&
           truth.dig("claim_boundary", "p3_mtro_delivery_credit") ==
             (profile.fetch("accepted") ? 75 : 0) &&
           truth.dig("claim_boundary", "p3_mtro_strict_exit_credit") == profile.fetch("strict") &&
           truth.dig("claim_boundary", "p3_mtro_runtime_identity_channel_status") ==
             active.dig("runtime_identity_channel", "status") &&
           truth.dig("claim_boundary", "founder_reserved_trigger") ==
             profile.fetch("reserved_trigger") &&
           truth.dig("claim_boundary", "long_term_goal_status") == "ACTIVE" &&
           truth.dig("claim_boundary", "current_route_executable_task_slots") ==
             profile.fetch("executable_slots") &&
           truth.dig("claim_boundary", "production_ready") == false &&
           truth.dig("claim_boundary", "trustworthy_software_engineering_agent_proven") == false,
           "P3 MTRO project, P4, Goal or claim boundary drift")
    profile.fetch("state")
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
          "P3 MTRO Route invalid: #{e.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(root.join("docs/aios/truth/project_state.yaml").binread,
                           permitted_classes: [], permitted_symbols: [], aliases: false)
    if truth.dig("current_phase_route", "schema_version") ==
       P3MinimumTrustTransactionalOciFinalProductRouteValidation::ROUTE_SCHEMA
      state = P3MinimumTrustTransactionalOciFinalProductRouteValidation.validate_truth!(
        root: root, truth: truth
      )
      puts "STRICT_PHASE_GATES: PASS state=#{state}"
    elsif truth.dig("current_phase_route", "schema_version") ==
       P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidation::ROUTE_SCHEMA
      state = P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidation.validate_truth!(root: root, truth: truth)
      puts "STRICT_PHASE_GATES: PASS state=#{state}"
    elsif truth.dig("current_phase_route", "schema_version") ==
       P3TrustedReadOnlyInvocationVerticalSliceRouteValidation::ROUTE_SCHEMA
      state = P3TrustedReadOnlyInvocationVerticalSliceRouteValidation.validate_truth!(root: root, truth: truth)
      puts "STRICT_PHASE_GATES: PASS state=#{state}"
    elsif truth.dig("current_phase_route", "schema_version") ==
       P3DeclarativeTransactionKernelRouteValidation::ROUTE_SCHEMA
      state = P3DeclarativeTransactionKernelRouteValidation.validate_truth!(root: root, truth: truth)
      puts "STRICT_PHASE_GATES: PASS state=#{state}"
    elsif truth.dig("current_phase_route", "schema_version") ==
          P3ExecutableTransitionSystemKernelRouteValidation::ROUTE_SCHEMA
      state = P3ExecutableTransitionSystemKernelRouteValidation.validate_truth!(root: root, truth: truth)
      puts "STRICT_PHASE_GATES: PASS state=#{state}"
    else
      p3 = truth.dig("strict_phase_gate_ledger", "phases", "P3")
      raise P3ExecutableTransitionSystemKernelRouteValidationError, "P3 strict Gate is missing" unless p3.is_a?(Hash)
      puts "STRICT_PHASE_GATES: PASS state=NON_ETSK_CURRENT_ROUTE"
    end
  rescue P3MinimumTrustTransactionalOciFinalProductRouteValidationError,
         P3TrustedReadOnlyInvocationEvidenceFirstFinalRouteValidationError,
         P3TrustedReadOnlyInvocationVerticalSliceRouteValidationError,
         P3DeclarativeTransactionKernelRouteValidationError,
         P3ExecutableTransitionSystemKernelRouteValidationError, JSON::ParserError, Psych::SyntaxError => e
    warn "STRICT_PHASE_GATES: NON_PASS #{e.message}"
    exit 1
  end
end

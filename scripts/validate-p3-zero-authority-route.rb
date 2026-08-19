#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "validate-p3-phase-entry" unless defined?(P3PhaseEntryValidation)

class P3ZeroAuthorityRouteValidationError < StandardError; end

module P3ZeroAuthorityRouteValidation
  module_function

  ROUTE_SCHEMA = "p3-zero-authority-action-envelope-route/v1"
  ROUTE_ID = "P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE"
  ROUTE_STATUS = "ACTIVE_SLOT_1_ELIGIBLE_NOT_ACTIVATED"
  NEXT_ACTION = "MASTER_ACTIVATE_P3_ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY_SLOT_1"
  DECISION_SCHEMA =
    "founder-p3-zero-authority-action-envelope-phase-route-resequencing-decision/v1"
  DECISION_ID =
    "AUTHORIZE_P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE_RESEQUENCING_V1"
  DECISION_PATH =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-zero-authority-action-envelope-route-20260819/decision/FOUNDER_P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE_RESEQUENCING_V1.json"
  DECISION_BYTES = 13_291
  DECISION_SHA256 = "1688e7d6cec549842ed4d36ae28366f7f3e0f9aaf4b9fdecde4f4b9cee65168b"
  DECISION_IDENTITY = {
    "decision_id" => DECISION_ID,
    "reserved_trigger" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
    "path" => DECISION_PATH,
    "byte_length" => DECISION_BYTES,
    "sha256" => DECISION_SHA256
  }.freeze
  HOLD_DECISION = {
    "decision_id" =>
      "DECIDE_P3_KEEP_STRICT_EXIT_AND_HOLD_CAPABILITY_MILESTONE_AFTER_P3_004_FINAL_EXCEPTION_NON_PASS_V1",
    "path" =>
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-capability-milestone-hold-20260819/decision/FOUNDER_P3_KEEP_STRICT_EXIT_AND_HOLD_CAPABILITY_MILESTONE_AFTER_P3_004_FINAL_EXCEPTION_NON_PASS_V1.json",
    "byte_length" => 4145,
    "sha256" => "ec6b35bcacdbf3686cbf0e943dd6f111dd2011dfea87996deb53af91a81453be"
  }.freeze
  P3_001_RECEIPT = {
    "path" =>
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001/terminal/P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json",
    "byte_length" => 3055,
    "sha256" => "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
  }.freeze
  P3_004_RECEIPT = {
    "path" =>
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-hermetic-capability-route-20260819/task-p3-004/terminal/P3_004_TERMINAL_FINAL_CAPABILITY_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 6451,
    "sha256" => "3ec5d1ee27c7a0376efe2a45806d92fc2c66ea2c875b1584866f69f1cdd83583"
  }.freeze
  FALSE_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze
  LIMITS = {
    "engineering_tasks" => 8,
    "engineering_hours" => 256,
    "calendar_days" => 64,
    "active_tasks" => 1,
    "task_branches" => 1,
    "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  CAPACITY = {
    "engineering_tasks" => 4,
    "engineering_hours" => 128,
    "calendar_days" => 32
  }.freeze
  TASK_BUDGET = {
    "engineering_tasks" => 1,
    "engineering_hours" => 32,
    "calendar_days" => 8,
    "candidate_generations" => 2,
    "same_task_repairs" => 1,
    "review_cycles" => 2
  }.freeze
  MILESTONES = %w[
    DURABLE_STATE_AND_CHECKPOINT_RESUME
    ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PERMISSION_ENFORCEMENT
    BOUNDED_ISOLATED_EXECUTION_WITH_COMPLETE_OBSERVABLE_TRACES
    INDEPENDENT_P3_EXIT_GATE_AUDIT
  ].freeze
  SLOT_IDS = %w[
    ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY
    IMMUTABLE_TASK_ACTION_ENVELOPE_BROKER_AND_PERMISSION_ENFORCEMENT
    BOUNDED_ISOLATED_EXECUTION_TRACE_CHECKPOINT_REPLAY_AND_ROLLBACK
    INDEPENDENT_P3_EXIT_GATE_AUDIT
  ].freeze

  def assert(condition, message)
    raise P3ZeroAuthorityRouteValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def exact_identity(identity, label)
    path = Pathname.new(identity.fetch("path"))
    assert(path.file? && !path.symlink?, "#{label} must be a regular non-symlink file")
    content = path.binread
    assert(content.bytesize == identity.fetch("byte_length"), "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(content) == identity.fetch("sha256"),
           "#{label} SHA-256 mismatch")
    content
  end

  def git(root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    raise P3ZeroAuthorityRouteValidationError,
          "git #{args.join(' ')} failed: #{stderr}" unless status.success?
    stdout
  end

  def validate_decision!(root)
    bytes = exact_identity(
      {"path" => DECISION_PATH, "byte_length" => DECISION_BYTES, "sha256" => DECISION_SHA256},
      "P3 zero-authority route decision"
    )
    decision = JSON.parse(bytes)
    assert(decision["schema_version"] == DECISION_SCHEMA &&
           decision["record_type"] ==
             "sourcelens_aios_founder_p3_phase_route_resequencing_decision" &&
           decision["decision_id"] == DECISION_ID && decision["authority"] == "HUMAN_FOUNDER" &&
           decision["source_kind"] == "CURRENT_DIRECT_FOUNDER_REPLY_V1" &&
           decision["reserved_trigger"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           decision["operation_type"] ==
             "P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE_RESEQUENCING",
           "P3 zero-authority route decision identity drift")

    source = mapping(decision["source_attachment"], "Founder source attachment")
    exact_identity(source, "Founder source attachment")
    assert(source == {
      "path" =>
        "/Users/lijunpeng/.codex/attachments/6b9b9b35-b792-4f4e-90c6-5b4c4a7b0c19/pasted-text.txt",
      "byte_length" => 9855,
      "sha256" => "f384fdf5c4ad86745621ee2adad30370060c6a3982c84a69aa515d655968eea0"
    }, "Founder source attachment identity drift")

    binding = mapping(decision["canonical_binding"], "decision canonical binding")
    assert(binding["branch"] == "main" && binding["worktree_clean"] == true &&
           binding["commit"] == "2a40277a9d883657493f711f98066ea8d527260e" &&
           binding["tree"] == "cc5fa78809b87b9f3ccccdefc0dae1c9b94675d9" &&
           git(root, "rev-parse", "#{binding['commit']}^{tree}").strip == binding["tree"],
           "P3 zero-authority activation-parent Git identity drift")
    constitution = mapping(binding["governing_artifact"], "governing Constitution")
    assert(constitution == {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "byte_length" => 9397,
      "sha256" => "7835ff584ad535b27c31bba174681abb625102a04b136ea6ee7535d57e18aaba"
    }, "governing Constitution binding drift")
    exact_identity(constitution.merge("path" => root.join(constitution["path"]).to_s),
                   "governing Constitution")
    bound_truth = mapping(binding["current_truth"], "activation-parent Truth")
    parent_truth_bytes = git(root, "show", "#{binding['commit']}:#{bound_truth['path']}")
    assert(parent_truth_bytes.bytesize == bound_truth["byte_length"] &&
           Digest::SHA256.hexdigest(parent_truth_bytes) == bound_truth["sha256"],
           "activation-parent Truth identity drift")

    assert(mapping(decision["superseded_scheduling_effect"], "superseded HOLD").slice(
      "decision_id", "path", "byte_length", "sha256"
    ) == HOLD_DECISION, "superseded HOLD identity drift")
    exact_identity(HOLD_DECISION, "superseded HOLD decision")
    assert(decision.dig("accepted_foundation", "milestone") ==
             "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           decision.dig("accepted_foundation", "status") == "ACCEPTED" &&
           decision.dig("accepted_foundation", "receipt") == P3_001_RECEIPT,
           "accepted P3-001 foundation drift")
    exact_identity(P3_001_RECEIPT, "accepted P3-001 receipt")
    assert(decision.dig("terminal_accounting", "p3_004_terminal_receipt") == P3_004_RECEIPT &&
           decision.dig("terminal_accounting", "failed_candidate_integration_count") == 0 &&
           decision.dig("terminal_accounting", "terminal_facts_reclassification_allowed") == false,
           "P3 terminal accounting drift")
    exact_identity(P3_004_RECEIPT, "P3-004 terminal accounting receipt")

    assert(decision.dig("objective", "unchanged") == true &&
           decision.dig("objective", "constitution_version") == "2.4" &&
           decision.dig("strict_exit_gate", "unchanged") == true &&
           decision.dig("strict_exit_gate", "required_test_groups") ==
             %w[RESUME ISOLATION PERMISSION COMPLETE_OBSERVABLE_TRACE] &&
           decision.dig("strict_exit_gate", "all_required_test_groups_must_be_independently_accepted") == true &&
           decision.dig("strict_exit_gate", "independent_p3_exit_gate_audit_required") == true &&
           decision.dig("strict_exit_gate", "research_non_pass_completion_allowed") == false &&
           decision.dig("strict_exit_gate", "weakened_substitute_evidence_allowed") == false,
           "P3 Objective or strict Exit Gate was weakened")
    architecture = mapping(decision["architecture"], "P3 zero-authority architecture")
    assert(architecture["agent_runtime_authority"] == "ZERO" &&
           architecture["agent_runtime_may_request_actions"] == true &&
           architecture["agent_runtime_may_mint_mutate_widen_or_execute_authority"] == false &&
           architecture.dig("task_action_envelope", "create_once") == true &&
           architecture.dig("task_action_envelope", "issuer_outside_agent_runtime") == true &&
           architecture.dig("broker", "out_of_process") == true &&
           architecture.dig("broker", "default_deny") == true &&
           architecture.dig("broker", "durable_allow_or_deny_before_tool_body") == true &&
           architecture.dig("broker", "persistence_failure_behavior") == "FAIL_CLOSED" &&
           architecture.dig("broker", "sandbox_binary") == "/usr/bin/sandbox-exec" &&
           architecture.dig("broker", "local_process_builder_fallback_allowed") == false &&
           architecture.dig("checkpoint_integration", "resume_duplicate_effects_allowed") == false,
           "P3 zero-authority architecture invariant drift")
    assert(decision["milestone_order"] == MILESTONES &&
           decision["ordered_remaining_slots"].map { |slot| slot["slot"] } == [1, 2, 3, 4] &&
           decision["ordered_remaining_slots"].map { |slot| slot["id"] } == SLOT_IDS,
           "P3 route milestone or slot order drift")
    assert(decision.dig("lineage_boundary", "p3_002_p3_003_p3_004_branch_worktree_code_test_evaluator_or_engineering_evidence_access") ==
             "PROHIBITED" &&
           decision.dig("lineage_boundary", "terminal_receipt_access") == "IDENTITY_AND_ACCOUNTING_ONLY" &&
           decision.dig("lineage_boundary", "mutable_dynamic_capability_grant_ledger_recreation") == "PROHIBITED",
           "P3 rejected-lineage or mutable-ledger boundary drift")
    assert(decision.dig("installation", "structured_decision_count") == 1 &&
           decision.dig("installation", "create_once") == true &&
           decision.dig("installation", "minimal_closed_profile_validator_extension_allowed") == true &&
           decision.dig("installation", "constitution_must_remain_byte_exact") == true &&
           decision.dig("installation", "engineering_or_delivery_credit") == 0 &&
           decision.dig("installation", "task_creation_before_installation_and_required_checks_pass") == false &&
           decision.dig("validator_boundary", "repair_authorized") == false &&
           decision.dig("validator_boundary", "waiver_authorized") == false,
           "P3 route installation boundary drift")
    phase_envelope = mapping(decision["phase_envelope"], "P3 route Phase envelope")
    assert(phase_envelope["expansion"] == false &&
           phase_envelope["limits"] == LIMITS.slice(
             "engineering_tasks", "engineering_hours", "calendar_days"
           ) && phase_envelope["preserved_consumed"] == CAPACITY &&
           phase_envelope["unlocked_remaining"] == CAPACITY &&
           phase_envelope.dig("per_task_maximum", "engineering_hours") == 32 &&
           phase_envelope.dig("per_task_maximum", "calendar_days") == 8 &&
           phase_envelope.dig("per_task_maximum", "candidate_generations") == 2 &&
           phase_envelope.dig("per_task_maximum", "same_task_repairs") == 1 &&
           phase_envelope.dig("per_task_maximum", "review_cycles") == 2 &&
           phase_envelope["governance_pre_worker_budget_percent_max"] == 10 &&
           phase_envelope["worker_start_deadline_engineering_hour"] == 1 &&
           phase_envelope["external_capabilities"] == 0,
           "P3 zero-authority Phase envelope drift")
    assert(decision.dig("progress_map", "installation") == {
      "delivery_percent" => 25, "strict_exit_percent" => 0
    } && decision.dig("progress_map", "slot_1_pass") == {
      "delivery_percent" => 25, "strict_exit_percent" => 0
    } && decision.dig("progress_map", "slot_2_pass") == {
      "delivery_percent" => 50, "strict_exit_percent" => 0
    } && decision.dig("progress_map", "slot_3_pass") == {
      "delivery_percent" => 75, "strict_exit_percent" => 0
    } && decision.dig("progress_map", "slot_4_pass", "delivery_percent") == 100 &&
           decision.dig("progress_map", "slot_4_pass", "strict_exit_percent") == 100,
           "P3 progress map drift")
    assert(mapping(decision["external_effects"], "P3 external effects").values.all? { |v| v == false } &&
           mapping(decision["prohibited_actions"], "P3 prohibitions").values.all? { |v| v == true } &&
           decision.dig("phase_and_goal_lifecycle", "p4") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           decision.dig("phase_and_goal_lifecycle", "project_actual_completion") == false &&
           decision.dig("phase_and_goal_lifecycle", "long_term_goal") == "ACTIVE",
           "P3 external-effect or lifecycle boundary drift")
    decision
  rescue JSON::ParserError => error
    raise P3ZeroAuthorityRouteValidationError,
          "P3 zero-authority decision JSON invalid: #{error.message}"
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    validate_decision!(root)
    P3PhaseEntryValidation.validate_decision!(root)

    project = mapping(truth["project"], "project")
    assert(project["current_phase"] == "P3" &&
           project["phase_name"] == "Single-Agent Runtime + Minimum Trust" &&
           project["p2_execution_status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           project["p3_entry_status"] == "AUTHORIZED" && project["p3_execution_status"] == "ACTIVE" &&
           project["phase_execution_status"] == "ACTIVE" &&
           project["current_route_execution_status"] == ROUTE_STATUS &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "project P3 zero-authority Route projection drift")

    route = mapping(truth["current_phase_route"], "current P3 Route")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID &&
           route["status"] == ROUTE_STATUS && route["execution_status"] == ROUTE_STATUS &&
           route["scheduling_status"] == "MASTER_ACTIVATING_SLOT_1" && route["phase"] == "P3" &&
           route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == false &&
           route["founder_reserved_trigger_resolved"] ==
             "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           route["next_eligible_action"] == NEXT_ACTION &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["accepted_foundation_route_ref"] == "historical_p3_001_phase_route" &&
           route["terminal_accounting_route_refs"] ==
             %w[historical_p3_002_phase_route historical_p3_003_phase_route] &&
           route["founder_route_decision"] == DECISION_IDENTITY &&
           route["superseded_hold_decision"] == HOLD_DECISION &&
           route.dig("accepted_foundation", "receipt") == P3_001_RECEIPT &&
           route.dig("terminal_p3_004_accounting", "status") ==
             "TERMINAL_FINAL_CAPABILITY_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS" &&
           route.dig("terminal_p3_004_accounting", "integrated") == false &&
           route.dig("terminal_p3_004_accounting", "terminal_receipt") == P3_004_RECEIPT &&
           route["milestone_order"] == MILESTONES && route["external_effects"] == FALSE_EFFECTS &&
           route["additional_write_roots"] == [],
           "current P3 zero-authority Route drift")
    slots = route["ordered_slots"]
    assert(slots.is_a?(Array) && slots.length == 4 &&
           slots.map { |slot| slot["slot"] } == [1, 2, 3, 4] &&
           slots.map { |slot| slot["id"] } == SLOT_IDS &&
           slots.map { |slot| slot["status"] } ==
             ["ELIGIBLE_NOT_ACTIVATED", "LOCKED_PREDECESSOR", "LOCKED_PREDECESSOR", "LOCKED_PREDECESSOR"] &&
           slots.all? { |slot| slot["budget"] == TASK_BUDGET } &&
           slots.first["predecessor"] == "DURABLE_STATE_AND_CHECKPOINT_RESUME_ACCEPTED" &&
           slots.first["phase_milestone_credit_on_pass"] == 0,
           "P3 zero-authority slot schedule drift")
    lineage = mapping(route["lineage_boundary"], "P3 zero-authority lineage boundary")
    assert(lineage["implementation_inputs"] ==
             %w[CANONICAL_MAIN ACCEPTED_P3_001_CHECKPOINT_FOUNDATION NEW_TASK_CONTRACTS] &&
           lineage["p3_002_p3_003_p3_004_rejected_engineering_lineage_access"] == "PROHIBITED" &&
           lineage["terminal_receipt_access"] == "IDENTITY_AND_ACCOUNTING_ONLY" &&
           lineage["mutable_dynamic_capability_ledger_recreation"] == "PROHIBITED",
           "P3 zero-authority lineage projection drift")

    envelope = mapping(truth["phase_execution_envelope"], "P3 Phase envelope")
    ledger = envelope["task_ledger"]
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" && envelope["phase"] == "P3" &&
           envelope["status"] == "ACTIVE_ZERO_AUTHORITY_ACTION_ENVELOPE_ROUTE" &&
           envelope["limits"] == LIMITS && envelope["accounting_basis"] ==
             "NON_RESETTABLE_DECLARED_TASK_BUDGET_RESERVATION" &&
           envelope.dig("authority_basis", "source_route_ref") == "current_phase_route" &&
           envelope.dig("authority_basis", "source_route_id") == ROUTE_ID &&
           envelope.dig("authority_basis", "founder_route_resequencing_decision") ==
             DECISION_IDENTITY.slice("path", "byte_length", "sha256") &&
           envelope["consumed"] == CAPACITY && envelope["reserved"] == {} &&
           envelope["remaining"] == CAPACITY && envelope["remaining_capacity_usable"] == true &&
           !envelope.key?("remaining_capacity_lock_reason") && envelope["milestone_order"] == MILESTONES &&
           envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25, "strict_exit_gate_percent" => 0
           } && envelope["external_effects"] == FALSE_EFFECTS,
           "P3 zero-authority Phase envelope projection drift")
    assert(ledger.is_a?(Array) && ledger.length == 4 &&
           ledger.map { |item| item["task_id"] } == %w[
             AIOS-P3-001_DURABLE_EXECUTION_CHECKPOINT_RESUME_KERNEL
             AIOS-P3-002_CAPABILITY_SCOPED_TOOL_PERMISSION_ENFORCEMENT
             AIOS-P3-003_PERSISTED_TOOL_CAPABILITY_LEDGER_ENFORCEMENT
             AIOS-P3-004_HERMETIC_SUREFIRE_AND_PERSISTED_CAPABILITY_LEDGER
           ] && ledger.map { |item| item["status"] } == [
             "ACCEPTED_INTEGRATED",
             "TERMINAL_WRITE_ROOT_ESCAPE_NON_PASS",
             "TERMINAL_PREACTIVATION_TEMP_ROOT_CONFINEMENT_NON_PASS",
             "TERMINAL_FINAL_CAPABILITY_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS"
           ] && ledger.first["task_gate_receipt"] == P3_001_RECEIPT &&
           ledger.last["terminal_receipt"] == P3_004_RECEIPT,
           "P3 terminal Task accounting drift")

    control = mapping(truth["founder_escalation_control"], "Founder escalation control")
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control.dig("source_event", "kind") ==
             "FOUNDER_P3_ZERO_AUTHORITY_ACTION_ENVELOPE_ROUTE_INSTALLED" &&
           control.dig("source_event", "task_id").nil? &&
           control.dig("source_event", "status") == ROUTE_STATUS &&
           control.dig("reserved_trigger", "category") == "NONE" &&
           control.dig("reserved_trigger", "evidence").nil? &&
           control["resolved_strategy_decision"] ==
             DECISION_IDENTITY.merge(
               "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
               "result" => "P3_ZERO_AUTHORITY_ACTION_ENVELOPE_ROUTE_ACTIVE_SLOT_1_ELIGIBLE"
             ) && control["phase_gate_status"] == "INCOMPLETE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == NEXT_ACTION,
           "P3 zero-authority Founder escalation projection drift")

    delegation = mapping(truth["phase_delegation"], "P3 Phase delegation")
    assert(delegation["status"] == "ACTIVE_P3_ZERO_AUTHORITY_ACTION_ENVELOPE_ROUTE" &&
           delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION" &&
           delegation["decision_source"] == DECISION_ID &&
           delegation["phase_gate_owner"] == "HUMAN_FOUNDER" &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation["p3_entry_authorized"] == true &&
           delegation.dig("anti_loop", "successor_replacement_correction_chain_allowed") == false &&
           delegation.dig("anti_loop", "historical_execution_lineage_reuse_allowed") == false,
           "P3 zero-authority Phase delegation drift")

    boundary = mapping(truth["phase_boundary"], "P3 Phase boundary")
    assert(boundary["phase"] == "P3" && boundary["phase_execution_status"] == "ACTIVE" &&
           boundary["task_creation_allowed"] == true &&
           boundary["task_creation_scope"] == "ONLY_ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY_SLOT_1" &&
           boundary["p3_entry_authorized"] == true &&
           boundary["allowed_task_kinds"] == %w[
             ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY
             IMMUTABLE_TASK_ACTION_ENVELOPE_BROKER_AND_PERMISSION_ENFORCEMENT
             SINGLE_AGENT_RUNTIME_ISOLATED_EXECUTION_TRACE
             P3_EXIT_GATE_AUDIT
           ] && boundary["default_external_effects"] == FALSE_EFFECTS &&
           !boundary.dig("role_write_roots", "worker").include?(
             "backend-spring/src/main/resources/db/migration"
           ), "P3 zero-authority Phase boundary drift")

    active = mapping(truth["active_work"], "active work")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["current_task_contract"].nil? && active["current_execution_authorization"].nil? &&
           active["execution_nonce_status"] == "NOT_ISSUED" &&
           active["task_resource_state"] == "NO_ACTIVE_TASK_ROUTE_INSTALLED_SLOT_1_ELIGIBLE" &&
           active["task_branch"].nil? && active["task_worktree"].nil? &&
           active["execution_evidence_root"].nil? && active["allowlisted_paths"] == [] &&
           active["founder_reserved_authorization"] == DECISION_PATH &&
           active["founder_reserved_authorization_sha256"] == DECISION_SHA256 &&
           active["founder_decision_required"] == false && active["user_action_required"] == "NONE" &&
           active["phase_route_decision_required"] == false &&
           active["next_eligible_action"] == NEXT_ACTION && active["external_effects"] == FALSE_EFFECTS &&
           active.dig("last_completed_task", "task_id") ==
             "AIOS-P3-004_HERMETIC_SUREFIRE_AND_PERSISTED_CAPABILITY_LEDGER" &&
           active.dig("last_completed_task", "terminal_receipt") == P3_004_RECEIPT,
           "P3 zero-authority active-work projection drift")

    phases = mapping(mapping(truth["strict_phase_gate_ledger"], "strict Phase Gate ledger")["phases"],
                     "strict Phase Gate phases")
    p3 = mapping(phases["P3"], "strict P3 Gate")
    assert(p3["status"] == "INCOMPLETE" && p3["entry_authorized"] == true &&
           p3["execution_started"] == true &&
           p3.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") == "MISSING" &&
           p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "strict P3 Exit Gate was changed or prematurely accepted")

    execution_claim = mapping(truth["phase_execution_claim"], "phase execution claim")
    assert(execution_claim["current_route_claim"] == ROUTE_ID &&
           execution_claim["current_task_claim"] == "NONE" &&
           execution_claim["product_capability_changed"] == false &&
           execution_claim["p3_entry_authorized"] == true &&
           execution_claim["p3_exit_gate_progress_percent"] == 0 &&
           execution_claim["p3_delivery_progress_percent"] == 25 &&
           execution_claim["phase_local_allowed"] ==
             ["ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY"] &&
           execution_claim["phase_local_frozen_capabilities"] == %w[
             IMMUTABLE_TASK_ACTION_ENVELOPE_BROKER_AND_PERMISSION_ENFORCEMENT
             BOUNDED_ISOLATED_EXECUTION_AND_COMPLETE_OBSERVABLE_TRACE
             INDEPENDENT_P3_EXIT_GATE_AUDIT
           ], "P3 zero-authority Phase execution claim drift")

    claim = mapping(truth["claim_boundary"], "claim boundary")
    assert(claim["current_phase_route"] == ROUTE_ID && claim["current_task"] == "NONE" &&
           claim["selected_task"] == "NONE_SLOT_1_NOT_ACTIVATED" &&
           claim["next_eligible_action"] == NEXT_ACTION && claim["p3_status"] == "ACTIVE_INCOMPLETE" &&
           claim["p3_phase_envelope_status"] == "ACTIVE_ZERO_AUTHORITY_ACTION_ENVELOPE_ROUTE" &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_delivery_progress_percent"] == 25 &&
           claim["p3_accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           claim["p3_capability_milestone_status"] ==
             "NOT_ACCEPTED_ZERO_AUTHORITY_PERMISSION_ROUTE_SLOT_1_NOT_STARTED" &&
           claim["p3_zero_authority_route_decision_sha256"] == DECISION_SHA256 &&
           claim["p3_004_candidate_integrated"] == false && claim["p3_004_delivery_credit"] == 0 &&
           claim["p3_004_strict_exit_credit"] == 0,
           "P3 zero-authority claim boundary drift")
    assert(truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_task_authority") == "NONE",
           "P3 route installation must keep the Long-term Goal active without Task authority")
    "P3_ZERO_AUTHORITY_ROUTE_INSTALLED_SLOT_1_ELIGIBLE"
  end

  def validate!(truth_path: nil, root: nil)
    root ||= `git rev-parse --show-toplevel`.strip
    raise P3ZeroAuthorityRouteValidationError, "cannot resolve repository root" if root.empty?
    truth_path ||= File.join(root, "docs/aios/truth/project_state.yaml")
    bytes = Pathname.new(truth_path).binread
    truth = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    validate_truth!(root: root, truth: truth)
  rescue Psych::Exception => error
    raise P3ZeroAuthorityRouteValidationError, "canonical Truth YAML invalid: #{error.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    state = P3ZeroAuthorityRouteValidation.validate!
    puts "P3_ZERO_AUTHORITY_ROUTE: PASS state=#{state}"
  rescue P3ZeroAuthorityRouteValidationError => error
    warn "P3_ZERO_AUTHORITY_ROUTE: NON_PASS #{error.message}"
    exit 1
  rescue StandardError => error
    warn "P3_ZERO_AUTHORITY_ROUTE: NON_PASS unexpected #{error.class}: #{error.message}"
    exit 1
  end
end

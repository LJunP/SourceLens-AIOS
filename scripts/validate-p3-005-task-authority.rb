#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "validate-p3-zero-authority-route"

class P3Task005AuthorityValidationError < StandardError; end

module P3Task005AuthorityValidation
  module_function

  ROUTE_SCHEMA = "p3-zero-authority-action-envelope-task-route/v1"
  ROUTE_ID = P3ZeroAuthorityRouteValidation::ROUTE_ID
  TASK_ID = "AIOS-P3-005_ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY"
  CONTRACT_PATH = "docs/aios/tasks/P3-005_ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY.yaml"
  CONTRACT_BYTES = 9473
  CONTRACT_SHA256 = "d0bcf63c9bfc66b5ef6db676b82f2892e415fa9aef4c301f27f4dd63046c446b"
  CONTRACT_IDENTITY = {
    "path" => CONTRACT_PATH,
    "byte_length" => CONTRACT_BYTES,
    "sha256" => CONTRACT_SHA256
  }.freeze
  BRANCH = "codex/p3-005-zero-authority-action-request-boundary"
  WORKTREE =
    "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-005-zero-authority-action-request-boundary"
  EVIDENCE_ROOT =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-zero-authority-action-request-boundary-20260819/task-p3-005"
  ROUTE_INSTALL_COMMIT = "842884f18abc6c30a4981faf84c91a13bba0265d"
  ROUTE_INSTALL_TREE = "9fd573135a6cf0347930ad9ed490606222ad05a2"
  FULL_BUDGET = {
    "engineering_tasks" => 1,
    "engineering_hours" => 32,
    "calendar_days" => 8,
    "candidate_generations" => 2,
    "same_task_repairs" => 1,
    "review_cycles" => 2
  }.freeze
  LEDGER_BUDGET = FULL_BUDGET.slice(
    "engineering_tasks", "engineering_hours", "calendar_days"
  ).freeze
  REMAINING = {
    "engineering_tasks" => 3,
    "engineering_hours" => 96,
    "calendar_days" => 24
  }.freeze
  TERMINAL_STATUS = "TERMINAL_SLOT_1_INDEPENDENT_REVIEW_NON_PASS"
  TERMINAL_NEXT_ACTION =
    "NONE_ROUTE_TERMINAL_NO_AUTOMATIC_SUCCESSOR_OR_FOUNDER_REQUEST"
  TERMINAL_RECEIPT = {
    "path" =>
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-zero-authority-action-request-boundary-20260819/task-p3-005/terminal/P3_005_TERMINAL_ZERO_AUTHORITY_ACTION_REQUEST_BOUNDARY_INDEPENDENT_REVIEW_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 5645,
    "sha256" => "e531a489b9b48cf119bd5a02069cfe0c686145308ff34c51591d827050bbe161"
  }.freeze
  TERMINAL_CANDIDATE = {
    "commit" => "14bfeaaff394448f528b6963fe76974ab5ab82c2",
    "tree" => "5386ae4d53ec09a6a6071fb740904445220d0958",
    "integrated" => false
  }.freeze
  ALLOWLIST = [
    "backend-spring/src/main/java/com/sourcelens/module/agent/service/AgentRuntime.java",
    "backend-spring/src/main/java/com/sourcelens/module/agent/action/AgentActionRequest.java",
    "backend-spring/src/main/java/com/sourcelens/module/agent/action/AgentActionRequestBoundary.java",
    "backend-spring/src/test/java/com/sourcelens/AgentActionRequestBoundaryTest.java",
    "backend-spring/src/test/java/com/sourcelens/AgentRuntimeActionBoundaryTest.java"
  ].freeze
  FALSE_EFFECTS = P3ZeroAuthorityRouteValidation::FALSE_EFFECTS

  def assert(condition, message)
    raise P3Task005AuthorityValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def exact_file(identity, root:, label:)
    path = Pathname.new(identity.fetch("path"))
    path = root.join(path) unless path.absolute?
    assert(path.file? && !path.symlink?, "#{label} must be a regular non-symlink file")
    bytes = path.binread
    assert(bytes.bytesize == identity.fetch("byte_length"), "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"),
           "#{label} SHA-256 mismatch")
    bytes
  end

  def git(root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    raise P3Task005AuthorityValidationError,
          "git #{args.join(' ')} failed: #{stderr}" unless status.success?
    stdout.strip
  end

  def validate_contract!(root)
    bytes = exact_file(CONTRACT_IDENTITY, root: root, label: "P3-005 Contract")
    contract = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(contract["schema_version"] == "p3-task-contract/v1" &&
           contract["record_type"] == "sourcelens_aios_p3_task_contract" &&
           contract["task_id"] == TASK_ID && contract["route_id"] ==
             "AIOS-P3-005_ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY_PHASE_DELEGATED_ROUTE" &&
           contract["phase"] == "P3" && contract["slot"] == 1 &&
           contract["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           contract["task_kind"] == "ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY" &&
           contract["capability"] == "ZERO_AUTHORITY_AGENT_ACTION_REQUEST" &&
           contract["milestone"] == "ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY" &&
           contract.dig("authority", "founder_route_decision") ==
             P3ZeroAuthorityRouteValidation::DECISION_IDENTITY &&
           contract.dig("authority", "route_install_parent") == {
             "commit" => ROUTE_INSTALL_COMMIT, "tree" => ROUTE_INSTALL_TREE
           } && contract.dig("authority", "accepted_foundation", "receipt") ==
             P3ZeroAuthorityRouteValidation::P3_001_RECEIPT &&
           contract.dig("authority", "task_selection_owner") == "MASTER_CEO_AGENT" &&
           contract.dig("authority", "task_gate_owner") == "MASTER_CEO_AGENT" &&
           contract["budget"] == FULL_BUDGET.merge(
             "governance_pre_worker_percent_max" => 10,
             "worker_start_deadline_engineering_hour" => 1
           ), "P3-005 Contract identity or authority drift")
    resource = mapping(contract["resource_identity"], "P3-005 resource identity")
    assert(resource["branch"] == BRANCH && resource["worktree"] == WORKTREE &&
           resource["evidence_root"] == EVIDENCE_ROOT &&
           resource["new_task_id"] == true && resource["new_execution_nonce_required"] == true &&
           resource["new_authorization_id_required"] == true &&
           resource["one_active_task_branch_worktree_candidate"] == true,
           "P3-005 resource identity drift")
    allowlisted = mapping(contract["allowlisted_paths"], "P3-005 allowlist")
    assert(allowlisted["product"] + allowlisted["tests"] == ALLOWLIST &&
           allowlisted["forbidden"].include?("backend-spring/pom.xml") &&
           allowlisted["forbidden"].include?("backend-spring/src/main/resources/db/migration") &&
           allowlisted["forbidden"].include?("evaluation-harness"),
           "P3-005 allowlist drift")
    invariants = mapping(contract["architectural_invariants"], "P3-005 invariants")
    assert(invariants["agent_runtime_tool_authority"] == "ZERO" &&
           invariants["agent_runtime_direct_tool_execution_dependency_allowed"] == false &&
           invariants["agent_runtime_direct_tool_registry_dependency_allowed"] == false &&
           invariants["agent_runtime_direct_sandbox_or_process_dependency_allowed"] == false &&
           invariants["immutable_typed_action_request_required"] == true &&
           invariants["canonical_arguments_snapshot_required"] == true &&
           invariants["boundary_has_effect_executor_dependency"] == false &&
           invariants["durable_denial_before_return_required"] == true &&
           invariants["tool_body_execution_count"] == 0 &&
           invariants["broker_implementation_allowed"] == false &&
           invariants["task_action_envelope_authorization_allowed"] == false &&
           invariants["sandbox_execution_allowed"] == false,
           "P3-005 zero-authority invariant drift")
    lineage = mapping(contract["implementation_inputs"], "P3-005 implementation inputs")
    assert(lineage["allowed"] ==
             %w[CANONICAL_MAIN_AT_ACTIVATION_PARENT ACCEPTED_P3_001_CHECKPOINT_FOUNDATION THIS_CONTRACT] &&
           lineage["prohibited"].include?("P3_002_REJECTED_ENGINEERING_LINEAGE") &&
           lineage["prohibited"].include?("P3_003_REJECTED_ENGINEERING_LINEAGE") &&
           lineage["prohibited"].include?("P3_004_REJECTED_ENGINEERING_LINEAGE") &&
           lineage["prohibited"].include?("MUTABLE_DYNAMIC_CAPABILITY_GRANT_LEDGER") &&
           lineage["terminal_receipt_access"] == "IDENTITY_AND_ACCOUNTING_ONLY",
           "P3-005 rejected-lineage boundary drift")
    assert(mapping(contract["external_effects"], "P3-005 external effects").values.all? { |v| v == false } &&
           contract.dig("progress_effect", "pass_delivery_percent") == 25 &&
           contract.dig("progress_effect", "pass_strict_exit_percent") == 0 &&
           contract.dig("progress_effect", "phase_milestone_credit") == 0 &&
           contract.dig("progress_effect", "pass_unlocks_only") ==
             "IMMUTABLE_TASK_ACTION_ENVELOPE_BROKER_AND_PERMISSION_ENFORCEMENT" &&
           contract.dig("progress_effect", "p4_entry_authorized") == false &&
           contract.dig("progress_effect", "long_term_goal_closure_authorized") == false,
           "P3-005 external effect or progress boundary drift")
    contract
  rescue Psych::Exception => error
    raise P3Task005AuthorityValidationError, "P3-005 Contract YAML invalid: #{error.message}"
  end

  def validate_authority!(identity, root:, activation_parent:)
    bytes = exact_file(identity, root: root, label: "P3-005 Task authority")
    authority = JSON.parse(bytes)
    assert(authority["schema_version"] == "p3-phase-delegated-task-authority/v1" &&
           authority["record_type"] == "sourcelens_aios_p3_task_authority" &&
           authority["task_id"] == TASK_ID && authority["phase"] == "P3" &&
           authority["slot"] == 1 && authority["status"] == "ACTIVE" &&
           authority["authorization_id"].is_a?(String) &&
           authority["authorization_id"].match?(/\A[0-9a-f-]{36}\z/) &&
           authority["execution_nonce"].is_a?(String) &&
           authority["execution_nonce"].match?(/\A[0-9a-f-]{36}\z/) &&
           authority["founder_route_decision"] ==
             P3ZeroAuthorityRouteValidation::DECISION_IDENTITY &&
           authority["contract"] == CONTRACT_IDENTITY &&
           authority["activation_parent"] == activation_parent &&
           authority["task_resource"] == {
             "branch" => BRANCH, "worktree" => WORKTREE, "evidence_root" => EVIDENCE_ROOT
           } && authority["budget"] == FULL_BUDGET && authority["allowlisted_paths"] == ALLOWLIST &&
           authority["external_effects"] == FALSE_EFFECTS &&
           authority.dig("lineage_boundary", "p3_002_p3_003_p3_004_rejected_engineering_lineage_access") ==
             "PROHIBITED" &&
           authority.dig("lineage_boundary", "mutable_dynamic_capability_ledger_recreation") ==
             "PROHIBITED" && authority.dig("lifecycle", "task_non_pass_locks_dependent_slots") == true &&
           authority.dig("lifecycle", "automatic_successor_allowed") == false,
           "P3-005 Task authority content drift")
    authority
  rescue JSON::ParserError => error
    raise P3Task005AuthorityValidationError, "P3-005 Task authority JSON invalid: #{error.message}"
  end

  def validate_terminal!(root:, truth:, contract:)
    receipt_bytes = exact_file(
      TERMINAL_RECEIPT, root: root, label: "P3-005 terminal receipt"
    )
    receipt = JSON.parse(receipt_bytes)
    assert(receipt["schema_version"] == "p3-task-terminal-receipt/v1" &&
           receipt["record_type"] == "sourcelens_aios_p3_task_terminal_receipt" &&
           receipt["task_id"] == TASK_ID && receipt["phase"] == "P3" &&
           receipt["slot"] == 1 &&
           receipt["task_lifecycle"] == "TERMINAL_INDEPENDENT_REVIEW_NON_PASS" &&
           receipt["target_verdict"] == "NON_PASS" &&
           receipt.dig("candidate", "commit") == TERMINAL_CANDIDATE["commit"] &&
           receipt.dig("candidate", "tree") == TERMINAL_CANDIDATE["tree"] &&
           receipt.dig("candidate", "integrated") == false &&
           receipt.dig("review_summary", "pass") == 1 &&
           receipt.dig("review_summary", "non_pass") == 2 &&
           receipt.dig("review_summary", "merged_p1") == 3 &&
           receipt.dig("budget_accounting", "repair_budget_remaining") == 0 &&
           receipt.dig("task_gate", "accepted") == false &&
           receipt["next_action"] == TERMINAL_NEXT_ACTION &&
           receipt["automatic_successor_allowed"] == false &&
           receipt["automatic_founder_request_allowed"] == false &&
           receipt["long_term_goal_status"] == "ACTIVE" &&
           receipt["project_actual_completion"] == false,
           "P3-005 terminal receipt content drift")
    receipt.fetch("independent_reviews").each_with_index do |identity, index|
      exact_file(identity, root: root, label: "P3-005 independent review #{index + 1}")
    end

    project = mapping(truth["project"], "project")
    route = mapping(truth["current_phase_route"], "P3-005 terminal Route")
    envelope = mapping(truth["phase_execution_envelope"], "P3 terminal Phase envelope")
    active = mapping(truth["active_work"], "P3 terminal active work")
    task = mapping(route["selected_task"], "P3-005 terminal selected Task")
    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "HOLD_INCOMPLETE_SLOT_1_NON_PASS" &&
           project["phase_execution_status"] == "HOLD_INCOMPLETE_SLOT_1_NON_PASS" &&
           project["current_route_execution_status"] == "P3_005_TERMINAL_SLOT_1_NON_PASS" &&
           project["p4_entry_status"] ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3-005 terminal project projection drift")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID &&
           route["status"] == TERMINAL_STATUS && route["execution_status"] == TERMINAL_STATUS &&
           route["scheduling_status"] == "HOLD_DEPENDENT_SLOTS_LOCKED" &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == false &&
           route["next_eligible_action"] == TERMINAL_NEXT_ACTION &&
           route["founder_route_decision"] == P3ZeroAuthorityRouteValidation::DECISION_IDENTITY &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "P3-005 terminal Route projection drift")
    assert(task["task_id"] == TASK_ID && task["status"] ==
             "TERMINAL_INDEPENDENT_REVIEW_NON_PASS" && task["contract"] == CONTRACT_IDENTITY &&
           task["terminal_receipt"] == TERMINAL_RECEIPT && task["candidate"] == TERMINAL_CANDIDATE &&
           task["automatic_successor_allowed"] == false &&
           task["automatic_founder_request_allowed"] == false,
           "P3-005 terminal Task projection drift")
    slots = route["ordered_slots"]
    assert(slots.is_a?(Array) && slots.length == 4 &&
           slots.map { |slot| slot["slot"] } == [1, 2, 3, 4] &&
           slots.map { |slot| slot["id"] } == P3ZeroAuthorityRouteValidation::SLOT_IDS &&
           slots.map { |slot| slot["status"] } == [
             "TERMINAL_INDEPENDENT_REVIEW_NON_PASS",
             "LOCKED_PREDECESSOR_NON_PASS", "LOCKED_PREDECESSOR_NON_PASS",
             "LOCKED_PREDECESSOR_NON_PASS"
           ], "P3-005 terminal dependent-slot lock drift")

    ledger = envelope["task_ledger"]
    p3_005_ledger = ledger.is_a?(Array) ? ledger.last : nil
    assert(envelope["phase"] == "P3" && envelope["limits"] == P3ZeroAuthorityRouteValidation::LIMITS &&
           envelope["status"] == "HOLD_ZERO_AUTHORITY_ROUTE_SLOT_1_NON_PASS_DEPENDENT_SLOTS_LOCKED" &&
           envelope["consumed"] == {
             "engineering_tasks" => 5, "engineering_hours" => 160, "calendar_days" => 40
           } && envelope["reserved"] == {} && envelope["remaining"] == REMAINING &&
           envelope["remaining_capacity_usable"] == false &&
           envelope["remaining_capacity_lock_reason"] ==
             "DEPENDENT_SLOTS_LOCKED_BY_SLOT_1_NON_PASS_NO_SUCCESSOR" &&
           envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25, "strict_exit_gate_percent" => 0
           } && p3_005_ledger["task_id"] == TASK_ID &&
           p3_005_ledger["status"] == "TERMINAL_INDEPENDENT_REVIEW_NON_PASS" &&
           p3_005_ledger["terminal_receipt"] == TERMINAL_RECEIPT &&
           p3_005_ledger["candidate"] == TERMINAL_CANDIDATE,
           "P3-005 terminal Phase-envelope projection drift")

    control = mapping(truth["founder_escalation_control"], "Founder escalation control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control.dig("source_event", "kind") == "P3_PHASE_DELEGATED_TASK_TERMINAL_NON_PASS" &&
           control.dig("source_event", "task_id") == TASK_ID &&
           control.dig("source_event", "status") == TERMINAL_STATUS &&
           control.dig("reserved_trigger", "category") == "NONE" &&
           control.dig("reserved_trigger", "evidence").nil? &&
           control["phase_gate_status"] == "INCOMPLETE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "NONE_ROUTE_TERMINAL" &&
           control["next_eligible_action"] == TERMINAL_NEXT_ACTION,
           "P3-005 terminal Founder-escalation projection drift")
    assert(truth.dig("phase_delegation", "status") ==
             "HOLD_P3_ZERO_AUTHORITY_ACTION_ENVELOPE_ROUTE_SLOT_1_NON_PASS" &&
           truth.dig("phase_boundary", "phase_execution_status") ==
             "HOLD_INCOMPLETE_SLOT_1_NON_PASS" &&
           truth.dig("phase_boundary", "task_creation_allowed") == false &&
           truth.dig("phase_boundary", "task_creation_scope") == "NONE_ROUTE_TERMINAL" &&
           truth.dig("phase_boundary", "next_eligible_action") == TERMINAL_NEXT_ACTION,
           "P3-005 terminal Phase-delegation or boundary drift")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["current_task_contract"].nil? && active["current_execution_authorization"].nil? &&
           active["execution_nonce_status"] == "CONSUMED_TERMINAL" &&
           active["task_resource_state"] == "NO_ACTIVE_TASK_ROUTE_TERMINAL_SLOT_1_NON_PASS" &&
           active["task_branch"].nil? && active["task_worktree"].nil? &&
           active["execution_evidence_root"].nil? && active["allowlisted_paths"] == [] &&
           active["founder_decision_required"] == false && active["user_action_required"] == "NONE" &&
           active["next_eligible_action"] == TERMINAL_NEXT_ACTION &&
           active.dig("last_completed_task", "task_id") == TASK_ID &&
           active.dig("last_completed_task", "status") ==
             "TERMINAL_INDEPENDENT_REVIEW_NON_PASS" &&
           active.dig("last_completed_task", "terminal_receipt") == TERMINAL_RECEIPT,
           "P3-005 terminal active-work projection drift")
    assert(truth.dig("phase_execution_claim", "current_task_claim") == "NONE" &&
           truth.dig("phase_execution_claim", "p3_delivery_progress_percent") == 25 &&
           truth.dig("phase_execution_claim", "p3_exit_gate_progress_percent") == 0 &&
           truth.dig("phase_execution_claim", "phase_local_allowed") == [] &&
           truth.dig("claim_boundary", "current_task") == "NONE" &&
           truth.dig("claim_boundary", "selected_task") == "NONE_ROUTE_TERMINAL" &&
           truth.dig("claim_boundary", "next_eligible_action") == TERMINAL_NEXT_ACTION &&
           truth.dig("claim_boundary", "p3_status") == "HOLD_INCOMPLETE_SLOT_1_NON_PASS" &&
           truth.dig("claim_boundary", "p3_phase_envelope_status") ==
             "HOLD_ZERO_AUTHORITY_ROUTE_SLOT_1_NON_PASS_DEPENDENT_SLOTS_LOCKED" &&
           truth.dig("claim_boundary", "p3_005_candidate_integrated") == false &&
           truth.dig("claim_boundary", "p3_005_terminal_receipt_sha256") ==
             TERMINAL_RECEIPT["sha256"], "P3-005 terminal claim projection drift")
    assert(truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_task_authority") == "NONE",
           "P3-005 terminal state must keep the Long-term Goal active")
    "P3_005_TERMINAL_INDEPENDENT_REVIEW_NON_PASS"
  rescue JSON::ParserError => error
    raise P3Task005AuthorityValidationError,
          "P3-005 terminal receipt JSON invalid: #{error.message}"
  end

  def validate!(root:, truth:)
    root = Pathname.new(root).realpath
    P3ZeroAuthorityRouteValidation.validate_decision!(root)
    P3PhaseEntryValidation.validate_decision!(root)
    contract = validate_contract!(root)
    return validate_terminal!(root: root, truth: truth, contract: contract) if
      truth.dig("current_phase_route", "status") == TERMINAL_STATUS
    project = mapping(truth["project"], "project")
    route = mapping(truth["current_phase_route"], "current P3-005 Route")
    envelope = mapping(truth["phase_execution_envelope"], "P3 Phase envelope")
    active = mapping(truth["active_work"], "active work")
    task = mapping(route["selected_task"], "P3-005 selected Task")
    ready = route["status"] == "AUTHORIZED_READY"
    active_state = route["status"] == "ACTIVE"
    assert(ready || active_state, "P3-005 Route lifecycle is invalid")

    expected_project_route_status = ready ? "P3_005_READY_FOR_MASTER_ACTIVATION" : "P3_005_ACTIVE"
    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE" && project["phase_execution_status"] == "ACTIVE" &&
           project["current_route_execution_status"] == expected_project_route_status &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3-005 project projection drift")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == false &&
           route["founder_route_decision"] == P3ZeroAuthorityRouteValidation::DECISION_IDENTITY &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["accepted_foundation_route_ref"] == "historical_p3_001_phase_route" &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "P3-005 Route projection drift")
    slots = route["ordered_slots"]
    expected_slot_1_status = ready ? "ELIGIBLE_NOT_ACTIVATED" : "ACTIVE"
    assert(slots.is_a?(Array) && slots.length == 4 &&
           slots.map { |slot| slot["slot"] } == [1, 2, 3, 4] &&
           slots.map { |slot| slot["id"] } == P3ZeroAuthorityRouteValidation::SLOT_IDS &&
           slots.map { |slot| slot["status"] } == [
             expected_slot_1_status, "LOCKED_PREDECESSOR",
             "LOCKED_PREDECESSOR", "LOCKED_PREDECESSOR"
           ] && slots.all? { |slot| slot["budget"] == FULL_BUDGET },
           "P3-005 ordered slot projection drift")
    architecture = mapping(route["architecture"], "P3-005 architecture")
    assert(architecture["agent_runtime_authority"] == "ZERO" &&
           architecture["agent_runtime_direct_effectful_dispatch_allowed"] == false &&
           architecture["immutable_task_action_envelope_required"] == true &&
           architecture["out_of_process_default_deny_broker_required"] == true &&
           architecture["persistence_failure_behavior"] == "FAIL_CLOSED" &&
           architecture["local_process_builder_fallback_allowed"] == false,
           "P3-005 architecture projection drift")
    lineage = mapping(route["lineage_boundary"], "P3-005 Route lineage boundary")
    assert(lineage["p3_002_p3_003_p3_004_rejected_engineering_lineage_access"] == "PROHIBITED" &&
           lineage["terminal_receipt_access"] == "IDENTITY_AND_ACCOUNTING_ONLY" &&
           lineage["mutable_dynamic_capability_ledger_recreation"] == "PROHIBITED",
           "P3-005 Route lineage projection drift")
    assert(task["task_id"] == TASK_ID && task["slot"] == 1 &&
           task["task_kind"] == "ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY" &&
           task["capability"] == "ZERO_AUTHORITY_AGENT_ACTION_REQUEST" &&
           task["milestone"] == "ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY" &&
           task["budget"] == FULL_BUDGET && task["contract"] == CONTRACT_IDENTITY &&
           task.dig("resource_identity", "branch") == BRANCH &&
           task.dig("resource_identity", "worktree") == WORKTREE &&
           task.dig("resource_identity", "evidence_root") == EVIDENCE_ROOT &&
           task.dig("independence", "p3_002_p3_003_p3_004_rejected_engineering_lineage_access") ==
             "PROHIBITED" &&
           task.dig("independence", "mutable_dynamic_capability_ledger_recreation") == "PROHIBITED",
           "P3-005 selected Task drift")

    ledger = envelope["task_ledger"]
    p3_005_ledger = ledger.is_a?(Array) ? ledger.last : nil
    assert(envelope["phase"] == "P3" && envelope["limits"] == P3ZeroAuthorityRouteValidation::LIMITS &&
           envelope["remaining"] == REMAINING && envelope["remaining_capacity_usable"] == true &&
           envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25, "strict_exit_gate_percent" => 0
           } && ledger.is_a?(Array) && ledger.length == 5 && p3_005_ledger["task_id"] == TASK_ID &&
           p3_005_ledger["budget"] == LEDGER_BUDGET && p3_005_ledger["contract"] == CONTRACT_IDENTITY &&
           envelope["external_effects"] == FALSE_EFFECTS,
           "P3-005 Phase envelope drift")

    control = mapping(truth["founder_escalation_control"], "Founder escalation control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control.dig("reserved_trigger", "category") == "NONE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == route["next_eligible_action"],
           "P3-005 Founder escalation projection drift")
    p3 = truth.dig("strict_phase_gate_ledger", "phases", "P3")
    assert(p3.is_a?(Hash) && p3["status"] == "INCOMPLETE" &&
           p3.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") == "MISSING" &&
           p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "P3-005 changed the strict P3 Exit Gate")
    claim = mapping(truth["claim_boundary"], "P3-005 claim boundary")
    assert(claim["current_phase_route"] == ROUTE_ID && claim["p3_status"] == "ACTIVE_INCOMPLETE" &&
           claim["p3_phase_envelope_status"] == envelope["status"] &&
           claim["next_eligible_action"] == route["next_eligible_action"] &&
           claim["p3_accepted_milestones"] == envelope["accepted_milestones"],
           "P3 zero-authority claim boundary drift")
    assert(truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("claim_boundary", "p3_exit_gate_progress_percent") == 0 &&
           truth.dig("claim_boundary", "p3_delivery_progress_percent") == 25 &&
           truth.dig("claim_boundary", "p3_capability_milestone_status") ==
             "NOT_ACCEPTED_ZERO_AUTHORITY_PERMISSION_ROUTE_SLOT_1_ACTIVE_BOUNDARY_ONLY",
           "P3-005 claim or Long-term Goal drift")
    boundary = mapping(truth["phase_boundary"], "P3 Phase boundary")
    assert(boundary["phase"] == "P3" && boundary["phase_execution_status"] == "ACTIVE" &&
           boundary["task_creation_allowed"] == true &&
           boundary["task_creation_scope"] == "ONLY_ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY_SLOT_1" &&
           boundary["p3_entry_authorized"] == true &&
           boundary["default_external_effects"] == FALSE_EFFECTS,
           "P3-005 Phase boundary drift")

    if ready
      assert(route["execution_status"] == "P3_TASK_READY" &&
             route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" &&
             route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" &&
             task["status"] == "ELIGIBLE_NOT_ACTIVATED" && task["authority"].nil? &&
             p3_005_ledger["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
             p3_005_ledger["authority"].nil? &&
             envelope["consumed"] == P3ZeroAuthorityRouteValidation::CAPACITY &&
             envelope["reserved"] == {
               "task_id" => TASK_ID, "status" => "ELIGIBLE_NOT_ACTIVATED",
               "budget" => LEDGER_BUDGET, "contract" => CONTRACT_IDENTITY, "authority" => nil
             } && active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["current_task_contract"] == CONTRACT_IDENTITY &&
             active["execution_nonce_status"] == "NOT_ISSUED" &&
             active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
             active["task_branch"].nil? && active["task_worktree"].nil? &&
             active["execution_evidence_root"].nil? && active["authority_record"].values.all?(&:nil?) &&
             active["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
             "P3-005 READY projection drift")
      return "P3_005_READY_FOR_MASTER_ACTIVATION"
    end

    authority_identity = mapping(task["authority"], "P3-005 authority identity")
    assert(route["execution_status"] == "ACTIVE" &&
           route["scheduling_status"] == "ACTIVE_PHASE_DELEGATED_TASK" &&
           route["next_eligible_action"] == "WORKER_IMPLEMENT_AND_TEST" && task["status"] == "ACTIVE" &&
           p3_005_ledger["status"] == "ACTIVE" && p3_005_ledger["authority"] == authority_identity &&
           envelope["consumed"] == {
             "engineering_tasks" => 5, "engineering_hours" => 160, "calendar_days" => 40
           } && envelope["reserved"] == {
             "task_id" => TASK_ID, "status" => "ACTIVE", "budget" => LEDGER_BUDGET,
             "contract" => CONTRACT_IDENTITY, "authority" => authority_identity
           } && active["current_task"] == TASK_ID && active["current_task_status"] == "ACTIVE" &&
           active["current_task_contract"] == CONTRACT_IDENTITY &&
           active["task_resource_state"] == "ACTIVE_UNIQUE_PHASE_DELEGATED" &&
           active["task_branch"] == BRANCH && active["task_worktree"] == WORKTREE &&
           active["execution_evidence_root"] == EVIDENCE_ROOT &&
           active["authority_record"] == authority_identity &&
           active["current_execution_authorization"] == authority_identity["path"] &&
           active["current_execution_authorization_sha256"] == authority_identity["sha256"] &&
           active["next_eligible_action"] == "WORKER_IMPLEMENT_AND_TEST",
           "P3-005 ACTIVE projection drift")
    activation_parent = {
      "branch" => "main",
      "commit" => active["activation_parent_commit"],
      "tree" => active["activation_parent_tree"]
    }
    authority = validate_authority!(authority_identity, root: root, activation_parent: activation_parent)
    assert(active["authorization_id"] == authority["authorization_id"] &&
           active["execution_nonce"] == authority["execution_nonce"] &&
           active["execution_nonce_status"] == "ACTIVE_SINGLE_USE" &&
           active["allowlisted_paths"] == ALLOWLIST && active["external_effects"] == FALSE_EFFECTS,
           "P3-005 active authority projection drift")
    assert(git(root, "rev-parse", "#{activation_parent['commit']}^{tree}") ==
             activation_parent["tree"], "P3-005 activation-parent tree drift")
    assert(Pathname.new(WORKTREE).directory? && !Pathname.new(WORKTREE).symlink?,
           "P3-005 worktree is unavailable")
    "P3_005_ACTIVE"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(`git rev-parse --show-toplevel`.strip).realpath
    truth = YAML.safe_load(
      root.join("docs/aios/truth/project_state.yaml").binread,
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    state = P3Task005AuthorityValidation.validate!(root: root, truth: truth)
    puts "P3_005_TASK_AUTHORITY: PASS state=#{state}"
  rescue P3Task005AuthorityValidationError, P3ZeroAuthorityRouteValidationError,
         P3PhaseEntryValidationError, KeyError => error
    warn "P3_005_TASK_AUTHORITY: NON_PASS #{error.message}"
    exit 1
  end
end

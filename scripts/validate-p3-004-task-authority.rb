#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

class P3Task004AuthorityValidationError < StandardError; end

module P3Task004AuthorityValidation
  module_function

  ROUTE_SCHEMA = "p3-founder-exception-task-route/v1"
  TASK_ID = "AIOS-P3-004_HERMETIC_SUREFIRE_AND_PERSISTED_CAPABILITY_LEDGER"
  ROUTE_ID = "#{TASK_ID}_FOUNDER_EXCEPTION_ROUTE"
  CONTRACT_PATH = "docs/aios/tasks/P3-004_HERMETIC_SUREFIRE_AND_PERSISTED_CAPABILITY_LEDGER.yaml"
  CONTRACT_BYTES = 9407
  CONTRACT_SHA256 = "0243f29a7f36e550dda4359f13dbacd52f8eb408ae0f57804b3f8b69f2052945"
  DECISION_ID = "AUTHORIZE_P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_ONLY_TERMINAL_V1"
  DECISION_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-hermetic-capability-route-20260819/decision/FOUNDER_P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_TERMINAL_V1.json"
  DECISION_BYTES = 5092
  DECISION_SHA256 = "8470fcea6bf99bca1326233c4d2fed704aa5ab9ec28df3da2a43aa8842924a30"
  P3_001_GATE_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001/terminal/P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json"
  P3_001_GATE_BYTES = 3055
  P3_001_GATE_SHA256 = "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
  P3_003_TERMINAL_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-persisted-tool-capability-ledger-20260819/task-p3-003/terminal/P3_003_TERMINAL_PREACTIVATION_TEMP_ROOT_CONFINEMENT_NON_PASS_RECEIPT_V1.json"
  P3_003_TERMINAL_BYTES = 8569
  P3_003_TERMINAL_SHA256 = "1a488dea0c6750fdb679a27492fc031b5db7ad0e0fd9700e716d9a8dd1b59ed0"
  BRANCH = "codex/p3-004-hermetic-capability-ledger"
  WORKTREE = "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-004-hermetic-capability-ledger"
  EVIDENCE_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-hermetic-capability-route-20260819/task-p3-004"
  BUDGET = {"engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8}.freeze
  FULL_BUDGET = BUDGET.merge(
    "candidate_generations" => 1, "same_task_repairs" => 1, "review_cycles" => 2
  ).freeze
  FALSE_EFFECTS = {
    "network" => false, "provider" => false, "secret" => false,
    "remote" => false, "production" => false, "public" => false
  }.freeze

  def assert(condition, message)
    raise P3Task004AuthorityValidationError, message unless condition
  end

  def exact_file(path, bytes, sha256, label)
    pathname = Pathname.new(path)
    assert(pathname.file? && !pathname.symlink?, "#{label} must be a regular non-symlink file")
    content = pathname.binread
    assert(content.bytesize == bytes && Digest::SHA256.hexdigest(content) == sha256,
           "#{label} identity drift")
    content
  end

  def identity(path, bytes, sha256)
    {"path" => path, "byte_length" => bytes, "sha256" => sha256}
  end

  def contract_identity
    identity(CONTRACT_PATH, CONTRACT_BYTES, CONTRACT_SHA256)
  end

  def decision_identity
    identity(DECISION_PATH, DECISION_BYTES, DECISION_SHA256)
  end

  def validate_decision!
    decision = JSON.parse(exact_file(DECISION_PATH, DECISION_BYTES, DECISION_SHA256,
                                     "P3-004 Founder route decision"))
    assert(decision["decision_id"] == DECISION_ID &&
           decision["reserved_trigger"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           decision["operation_type"] ==
             "P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_TERMINAL" &&
           decision.dig("route", "new_task_limit") == 1 &&
           decision.dig("route", "implementation_attempt") ==
             "3_OF_3_FINAL_FOUNDER_EXCEPTION" &&
           decision.dig("phase_envelope", "expanded") == false &&
           decision.dig("phase_envelope", "limits") == {
             "engineering_tasks" => 8, "engineering_hours" => 256, "calendar_days" => 64
           } && decision.fetch("external_effects").values.all? { |value| value == false } &&
           decision.dig("lifecycle", "p4_entry_authorized") == false &&
           decision.dig("lifecycle", "long_term_goal_closure_authorized") == false,
           "P3-004 Founder route decision semantics drift")
  end

  def validate_contract!(root)
    contract = YAML.safe_load(
      exact_file(root.join(CONTRACT_PATH), CONTRACT_BYTES, CONTRACT_SHA256, "P3-004 Contract"),
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(contract["schema_version"] == "p3-task-contract/v1" &&
           contract["task_id"] == TASK_ID && contract["route_id"] == ROUTE_ID &&
           contract["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           contract["milestone"] == "CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT" &&
           contract["implementation_attempt"] == "3_OF_3_FINAL_FOUNDER_EXCEPTION" &&
           contract.dig("authority", "founder_route_decision", "decision_id") == DECISION_ID &&
           contract.dig("ordered_stages", "stage_a", "product_source_write_allowed") == false &&
           contract.dig("ordered_stages", "stage_a", "required_execution", "test") ==
             "AgentSandboxToolTest" && contract["budget"] == FULL_BUDGET.merge(
               "phase_envelope_expanded" => false
             ) && contract["external_effects"] == FALSE_EFFECTS &&
           contract.dig("lineage", "p3_002_rejected_engineering_lineage_read") == false &&
           contract.dig("lineage", "p3_003_access_mode") == "EXACT_TERMINAL_RECEIPT_ONLY",
           "P3-004 Contract semantics drift")
  end

  def validate_predecessors!
    gate = JSON.parse(exact_file(P3_001_GATE_PATH, P3_001_GATE_BYTES, P3_001_GATE_SHA256,
                                 "P3-001 accepted Task Gate receipt"))
    terminal = JSON.parse(exact_file(P3_003_TERMINAL_PATH, P3_003_TERMINAL_BYTES,
                                     P3_003_TERMINAL_SHA256, "P3-003 terminal receipt"))
    assert(gate["accepted_milestone"] == "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           gate["task_lifecycle"] == "ACCEPTED_INTEGRATED",
           "P3-001 predecessor milestone drift")
    assert(terminal["task_lifecycle"] ==
             "TERMINAL_PREACTIVATION_TEMP_ROOT_CONFINEMENT_NON_PASS" &&
           terminal.dig("worktree_at_execution", "product_source_writes") == 0 &&
           terminal.dig("worktree_at_execution", "candidate_created") == false &&
           terminal.dig("worktree_at_execution", "integrated") == false,
           "P3-003 terminal boundary drift")
  end

  def validate_authority!(authority_identity, active)
    authority = JSON.parse(exact_file(
      authority_identity.fetch("path"), authority_identity.fetch("byte_length"),
      authority_identity.fetch("sha256"), "P3-004 Task authority"
    ))
    assert(authority["schema_version"] == "p3-founder-exception-task-authority/v1" &&
           authority["task_id"] == TASK_ID && authority["route_id"] == ROUTE_ID &&
           authority["authorization_id"] == active["authorization_id"] &&
           authority["execution_nonce"] == active["execution_nonce"] &&
           authority["branch"] == BRANCH && authority["worktree"] == WORKTREE &&
           authority["evidence_root"] == EVIDENCE_ROOT &&
           authority["contract"] == contract_identity &&
           authority["founder_route_decision"] == decision_identity &&
           authority["budget"] == FULL_BUDGET && authority["external_effects"] == FALSE_EFFECTS &&
           authority.dig("stage_a", "product_source_write_allowed") == false &&
           authority.dig("lineage", "p3_002_rejected_engineering_lineage_read") == false &&
           authority.dig("lineage", "p3_003_access_mode") == "EXACT_TERMINAL_RECEIPT_ONLY",
           "P3-004 Task authority semantics drift")
    authority
  end

  def validate!(root:, truth:)
    root = Pathname.new(root).realpath
    validate_decision!
    validate_contract!(root)
    validate_predecessors!
    project = truth.fetch("project")
    route = truth.fetch("current_phase_route")
    task = route.fetch("selected_task")
    envelope = truth.fetch("phase_execution_envelope")
    active = truth.fetch("active_work")

    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE" &&
           project["p4_entry_status"] ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3-004 project Phase projection drift")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == false &&
           route["founder_route_decision"].slice("path", "byte_length", "sha256") ==
             decision_identity && route["external_effects"] == FALSE_EFFECTS &&
           route["additional_write_roots"] == [],
           "P3-004 Route projection drift")
    assert(task["task_id"] == TASK_ID, "P3-004 selected Task id drift")
    assert(task["contract"] == contract_identity && task["budget"] == FULL_BUDGET &&
           task.dig("independence", "p3_002_rejected_lineage_read_compare_copy_or_reuse") == false &&
           task.dig("independence", "p3_003_access_mode") == "EXACT_TERMINAL_RECEIPT_ONLY",
           "P3-004 selected Task identity drift")
    assert(envelope["phase"] == "P3" && envelope["accepted_milestones"] ==
             ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25,
             "strict_exit_gate_percent" => 0
           } && envelope["external_effects"] == FALSE_EFFECTS,
           "P3-004 envelope milestone projection drift")
    claim = truth.fetch("claim_boundary")
    assert(claim["current_phase_route"] == ROUTE_ID && claim["current_task"] == TASK_ID &&
           claim["next_eligible_action"] == route["next_eligible_action"] &&
           claim["p3_status"] == "ACTIVE_INCOMPLETE" && claim["p3_entry_authorized"] == true &&
           claim["p3_phase_envelope_status"] == envelope["status"] &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_delivery_progress_percent"] == 25 &&
           claim["p3_accepted_milestones"] == envelope["accepted_milestones"] &&
           claim["p3_capability_milestone_status"].start_with?("NOT_ACCEPTED_") &&
           claim["p3_004_product_source_writes"] == 0 &&
           claim["p3_004_candidate_created"] == false &&
           claim["p3_004_delivery_credit"] == 0 && claim["p3_004_strict_exit_credit"] == 0,
           "P3 continuation claim boundary drift")
    control = truth.fetch("founder_escalation_control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == route["next_eligible_action"],
           "P3-004 Founder escalation projection drift")

    if route["status"] == "AUTHORIZED_TASK_SELECTED_NOT_ACTIVATED"
      assert(project["phase_execution_status"] ==
               "ACTIVE_INCOMPLETE_FINAL_CAPABILITY_ROUTE_AUTHORIZED" &&
             project["current_route_execution_status"] ==
               "FOUNDER_EXCEPTION_TASK_SELECTED_NOT_ACTIVATED" &&
             route["execution_status"] == "PENDING_PHASE_DELEGATED_ACTIVATION" &&
             route["next_eligible_action"] == "MASTER_ACTIVATE_EXACT_P3_004" &&
             task["status"] == "ELIGIBLE_NOT_ACTIVATED" && task["product_source_writes"] == 0 &&
             envelope["task_ledger"].length == 3 && envelope["consumed"] == {
               "engineering_tasks" => 3, "engineering_hours" => 96, "calendar_days" => 24
             } && envelope["remaining"] == {
               "engineering_tasks" => 5, "engineering_hours" => 160, "calendar_days" => 40
             } && envelope["remaining_capacity_usable"] == true && envelope["reserved"].nil? &&
             active["current_task"] == TASK_ID && active["current_task_status"] ==
               "ELIGIBLE_NOT_ACTIVATED" && active["current_task_contract"] == contract_identity &&
             active["task_resource_state"] == "SELECTED_NOT_CREATED" &&
             active["execution_nonce_status"] == "NOT_ISSUED_PREACTIVATION" &&
             active.dig("authority_record", "path").nil? &&
             active["next_eligible_action"] == "MASTER_ACTIVATE_EXACT_P3_004",
             "P3-004 READY projection drift")
      return "P3_004_READY_FOR_MASTER_ACTIVATION"
    end

    assert(%w[ACTIVE_STAGE_A_PREACTIVATION_REQUIRED ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION].include?(
             route["status"]
           ), "P3-004 lifecycle state is unsupported")
    authority_identity = active.fetch("authority_record")
    authority = validate_authority!(authority_identity, active)
    ledger = envelope.fetch("task_ledger")
    assert(ledger.length == 4 && ledger.last["task_id"] == TASK_ID &&
           ledger.last["authority"] == authority_identity && envelope["consumed"] == {
             "engineering_tasks" => 4, "engineering_hours" => 128, "calendar_days" => 32
           } && envelope["remaining"] == {
             "engineering_tasks" => 4, "engineering_hours" => 128, "calendar_days" => 32
           } && envelope.dig("reserved", "task_id") == TASK_ID &&
           envelope.dig("reserved", "authority") == authority_identity &&
           active["current_task"] == TASK_ID && active["task_branch"] == BRANCH &&
           active["task_worktree"] == WORKTREE && active["execution_evidence_root"] == EVIDENCE_ROOT,
           "P3-004 ACTIVE accounting projection drift")
    if route["status"] == "ACTIVE_STAGE_A_PREACTIVATION_REQUIRED"
      assert(task["status"] == route["status"] && task["product_source_writes"] == 0 &&
             route["next_eligible_action"] == "RUN_STAGE_A_HERMETIC_PREACTIVATION" &&
             authority["status"] == route["status"] &&
             active["current_task_status"] == route["status"] &&
             active["next_eligible_action"] == "RUN_STAGE_A_HERMETIC_PREACTIVATION",
             "P3-004 Stage A projection drift")
      return "P3_004_ACTIVE_STAGE_A_PREACTIVATION_REQUIRED"
    end

    assert(task["status"] == "ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION" &&
           route["next_eligible_action"] == "IMPLEMENT_PERSISTED_CAPABILITY_LEDGER" &&
           authority["status"] == "ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION" &&
           active["current_task_status"] == "ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION" &&
           active["next_eligible_action"] == "IMPLEMENT_PERSISTED_CAPABILITY_LEDGER" &&
           task.dig("stage_a", "status") == "PASS",
           "P3-004 Stage B projection drift")
    "P3_004_ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION"
  rescue KeyError, JSON::ParserError, Errno::ENOENT => e
    raise P3Task004AuthorityValidationError, e.message
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(root.join("docs/aios/truth/project_state.yaml").binread,
                           permitted_classes: [], permitted_symbols: [], aliases: false)
    state = P3Task004AuthorityValidation.validate!(root: root, truth: truth)
    puts "P3_004_TASK_AUTHORITY: PASS state=#{state}"
  rescue P3Task004AuthorityValidationError, Psych::SyntaxError => e
    warn "P3_004_TASK_AUTHORITY: NON_PASS #{e.message}"
    exit 1
  end
end

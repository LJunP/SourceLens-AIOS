#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

class P3Task002AuthorityValidationError < StandardError; end

module P3Task002AuthorityValidation
  module_function

  TASK_ID = "AIOS-P3-002_CAPABILITY_SCOPED_TOOL_PERMISSION_ENFORCEMENT"
  ROUTE_ID = "#{TASK_ID}_PHASE_DELEGATED_ROUTE"
  CONTRACT_PATH = "docs/aios/tasks/P3-002_CAPABILITY_SCOPED_TOOL_PERMISSION_ENFORCEMENT.yaml"
  CONTRACT_BYTES = 4518
  CONTRACT_SHA256 = "95c89d7c54042bdae4f02f67f25f2d0fa4df41f1fe20f5c00cf20e26942842af"
  P3_001_GATE_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001/terminal/P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json"
  P3_001_GATE_BYTES = 3055
  P3_001_GATE_SHA256 = "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
  BUDGET = {"engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8}.freeze
  FULL_TASK_BUDGET = BUDGET.merge(
    "candidate_generations" => 1, "same_task_repairs" => 1, "review_cycles" => 2
  ).freeze
  FALSE_EFFECTS = {
    "network" => false, "provider" => false, "secret" => false,
    "remote" => false, "production" => false, "public" => false
  }.freeze

  def assert(condition, message)
    raise P3Task002AuthorityValidationError, message unless condition
  end

  def identity
    {"path" => CONTRACT_PATH, "byte_length" => CONTRACT_BYTES, "sha256" => CONTRACT_SHA256}
  end

  def exact_file(path, bytes, sha256, label)
    pathname = Pathname.new(path)
    assert(pathname.file? && !pathname.symlink?, "#{label} must be a regular non-symlink file")
    content = pathname.binread
    assert(content.bytesize == bytes && Digest::SHA256.hexdigest(content) == sha256,
           "#{label} identity drift")
    content
  end

  def validate_contract!(root)
    bytes = exact_file(root.join(CONTRACT_PATH), CONTRACT_BYTES, CONTRACT_SHA256, "P3-002 Contract")
    contract = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(contract["schema_version"] == "p3-task-contract/v1" &&
           contract["record_type"] == "sourcelens_aios_p3_task_contract" &&
           contract["task_id"] == TASK_ID && contract["phase"] == "P3" &&
           contract["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           contract["milestone"] == "CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT" &&
           contract.dig("authority", "activation_parent", "commit") ==
             "934806bd5ce9bac029805612b58aaa9c6120dfbe" &&
           contract.dig("authority", "activation_parent", "tree") ==
             "2d0865e0e5d30a9495af5a1d6ce040496d736902" &&
           contract.dig("authority", "task_selection_owner") == "MASTER_CEO_AGENT" &&
           contract.dig("authority", "task_gate_owner") == "MASTER_CEO_AGENT" &&
           contract["budget"] == FULL_TASK_BUDGET && contract["external_effects"] == FALSE_EFFECTS &&
           contract.dig("lineage", "p2_rejected_engineering_lineage_read") == false &&
           contract.dig("scope", "product_source_required") == true,
           "P3-002 Contract semantics drift")
    contract
  end

  def validate_predecessor_gate!
    bytes = exact_file(P3_001_GATE_PATH, P3_001_GATE_BYTES, P3_001_GATE_SHA256,
                       "P3-001 Task Gate receipt")
    gate = JSON.parse(bytes)
    assert(gate["schema_version"] == "p3-task-gate-integration-receipt/v1" &&
           gate["task_id"] == "AIOS-P3-001_DURABLE_EXECUTION_CHECKPOINT_RESUME_KERNEL" &&
           gate["task_lifecycle"] == "ACCEPTED_INTEGRATED" &&
           gate["accepted_milestone"] == "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           gate.dig("phase_progress", "strict_p3_exit_gate_percent") == 0,
           "P3-001 predecessor Gate semantics drift")
  end

  def validate!(root:, truth:)
    root = Pathname.new(root).realpath
    validate_contract!(root)
    validate_predecessor_gate!
    project = truth.fetch("project")
    route = truth.fetch("current_phase_route")
    task = route.fetch("selected_task")
    envelope = truth.fetch("phase_execution_envelope")
    active = truth.fetch("active_work")

    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE" &&
           project["current_route_execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3-002 project projection drift")
    assert(route["schema_version"] == "p3-phase-delegated-task/v1" && route["route_id"] == ROUTE_ID &&
           route["status"] == "AUTHORIZED_READY" && route["execution_status"] == "P3_TASK_READY" &&
           route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" && route["phase"] == "P3" &&
           route["phase_entry_status"] == "AUTHORIZED" &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["predecessor_milestone_route_ref"] == "historical_p3_001_phase_route" &&
           route["founder_phase_route_decision_required"] == false &&
           route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "P3-002 Route projection drift")
    assert(task["task_id"] == TASK_ID && task["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           task["task_kind"] == "SINGLE_AGENT_RUNTIME_CAPABILITY_PERMISSION_ENFORCEMENT" &&
           task["capability"] == "CAPABILITY_SCOPED_TOOLS_AND_PERMISSION_ENFORCEMENT" &&
           task["milestone"] == "CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT" &&
           task["budget"] == FULL_TASK_BUDGET && task["contract"] == identity &&
           task.dig("predecessor_milestone", "id") == "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           task.dig("predecessor_milestone", "status") == "ACCEPTED" &&
           task.dig("predecessor_milestone", "task_gate_receipt") == {
             "path" => P3_001_GATE_PATH, "byte_length" => P3_001_GATE_BYTES,
             "sha256" => P3_001_GATE_SHA256
           } && task.dig("independence", "p2_rejected_lineage_read") == false,
           "P3-002 selected Task drift")

    ledger = envelope.fetch("task_ledger")
    assert(envelope["phase"] == "P3" && ledger.length == 2 &&
           ledger[0]["task_id"] == "AIOS-P3-001_DURABLE_EXECUTION_CHECKPOINT_RESUME_KERNEL" &&
           ledger[0]["status"] == "ACCEPTED_INTEGRATED" &&
           ledger[1]["task_id"] == TASK_ID && ledger[1]["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           ledger[1]["budget"] == BUDGET && ledger[1]["contract"] == identity &&
           ledger[1]["authority"].nil? &&
           envelope["consumed"] == BUDGET &&
           envelope["remaining"] == {"engineering_tasks" => 6, "engineering_hours" => 192,
                                      "calendar_days" => 48} &&
           envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25, "strict_exit_gate_percent" => 0
           } && envelope["external_effects"] == FALSE_EFFECTS,
           "P3-002 Phase envelope drift")
    assert(envelope["reserved"] == {
             "task_id" => TASK_ID, "route_id" => ROUTE_ID,
             "status" => "ELIGIBLE_NOT_ACTIVATED", "budget" => BUDGET, "authority" => nil
           }, "P3-002 reservation drift")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["current_task_contract"] == identity &&
           active["current_task_contract_sha256"] == CONTRACT_SHA256 &&
           active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
           active["task_branch"].nil? && active["task_worktree"].nil? &&
           active["execution_evidence_root"].nil? && active["authority_record"].values.all?(&:nil?) &&
           active["founder_decision_required"] == false && active["user_action_required"] == "NONE" &&
           active["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" &&
           active["external_effects"] == FALSE_EFFECTS,
           "P3-002 READY active-work projection drift")
    "P3_002_READY_FOR_MASTER_ACTIVATION"
  rescue KeyError, JSON::ParserError, Errno::ENOENT => e
    raise P3Task002AuthorityValidationError, e.message
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(root.join("docs/aios/truth/project_state.yaml").binread,
                           permitted_classes: [], permitted_symbols: [], aliases: false)
    state = P3Task002AuthorityValidation.validate!(root: root, truth: truth)
    puts "P3_002_TASK_AUTHORITY: PASS state=#{state}"
  rescue P3Task002AuthorityValidationError, Psych::SyntaxError => e
    warn "P3_002_TASK_AUTHORITY: NON_PASS #{e.message}"
    exit 1
  end
end

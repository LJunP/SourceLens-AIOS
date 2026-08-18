#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

class P3Task003AuthorityValidationError < StandardError; end

module P3Task003AuthorityValidation
  module_function

  TASK_ID = "AIOS-P3-003_PERSISTED_TOOL_CAPABILITY_LEDGER_ENFORCEMENT"
  ROUTE_ID = "#{TASK_ID}_PHASE_DELEGATED_ROUTE"
  CONTRACT_PATH = "docs/aios/tasks/P3-003_PERSISTED_TOOL_CAPABILITY_LEDGER_ENFORCEMENT.yaml"
  CONTRACT_BYTES = 5708
  CONTRACT_SHA256 = "ef502c1b0719f56472dc896674e0d99df6fac56f58fa3ce2ec70562e35f49b86"
  P3_001_GATE_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001/terminal/P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json"
  P3_001_GATE_BYTES = 3055
  P3_001_GATE_SHA256 = "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
  P3_002_TERMINAL_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-capability-scoped-tool-permission-20260819/task-p3-002/terminal/P3_002_TERMINAL_WRITE_ROOT_ESCAPE_NON_PASS_RECEIPT_V1.json"
  P3_002_TERMINAL_BYTES = 3023
  P3_002_TERMINAL_SHA256 = "686b0d254ef8d56652de7fa9b4b742e3c0b5478b93744da23cb1760c99b7a35b"
  BUDGET = {"engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8}.freeze
  FULL_TASK_BUDGET = BUDGET.merge(
    "candidate_generations" => 1, "same_task_repairs" => 1, "review_cycles" => 2
  ).freeze
  FALSE_EFFECTS = {
    "network" => false, "provider" => false, "secret" => false,
    "remote" => false, "production" => false, "public" => false
  }.freeze

  def assert(condition, message)
    raise P3Task003AuthorityValidationError, message unless condition
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
    bytes = exact_file(root.join(CONTRACT_PATH), CONTRACT_BYTES, CONTRACT_SHA256, "P3-003 Contract")
    contract = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(contract["schema_version"] == "p3-task-contract/v1" &&
           contract["record_type"] == "sourcelens_aios_p3_task_contract" &&
           contract["task_id"] == TASK_ID && contract["phase"] == "P3" &&
           contract["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           contract["milestone"] == "CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT" &&
           contract["implementation_attempt"] == "2_OF_2_FINAL_FOR_MILESTONE" &&
           contract.dig("authority", "activation_parent", "commit") ==
             "8bee5cb2f6c0cc0d69d9c4e228d9d2c00c401a1c" &&
           contract.dig("authority", "activation_parent", "tree") ==
             "6ad3149167623d17e14ec0b33a81f743c91bde83" &&
           contract["budget"] == FULL_TASK_BUDGET && contract["external_effects"] == FALSE_EFFECTS &&
           contract.dig("lineage", "p3_002_rejected_engineering_lineage_read") == false &&
           contract.dig("lineage", "p3_002_rejected_engineering_lineage_copy") == false,
           "P3-003 Contract semantics drift")
  end

  def validate_predecessors!
    gate = JSON.parse(exact_file(P3_001_GATE_PATH, P3_001_GATE_BYTES, P3_001_GATE_SHA256,
                                 "P3-001 Task Gate receipt"))
    terminal = JSON.parse(exact_file(P3_002_TERMINAL_PATH, P3_002_TERMINAL_BYTES,
                                     P3_002_TERMINAL_SHA256, "P3-002 terminal receipt"))
    assert(gate["accepted_milestone"] == "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           gate["task_lifecycle"] == "ACCEPTED_INTEGRATED",
           "P3-001 predecessor milestone drift")
    assert(terminal["task_lifecycle"] == "TERMINAL_WRITE_ROOT_ESCAPE_NON_PASS" &&
           terminal.dig("candidate", "integrated") == false &&
           terminal["milestone_status"] ==
             "CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT_NOT_ACCEPTED",
           "P3-002 terminal boundary drift")
  end

  def validate!(root:, truth:)
    root = Pathname.new(root).realpath
    validate_contract!(root)
    validate_predecessors!
    project = truth.fetch("project")
    route = truth.fetch("current_phase_route")
    task = route.fetch("selected_task")
    envelope = truth.fetch("phase_execution_envelope")
    active = truth.fetch("active_work")

    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE" &&
           project["current_route_execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3-003 project projection drift")
    assert(route["schema_version"] == "p3-phase-delegated-task/v1" && route["route_id"] == ROUTE_ID &&
           route["status"] == "AUTHORIZED_READY" && route["execution_status"] == "P3_TASK_READY" &&
           route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" && route["phase"] == "P3" &&
           route["phase_entry_status"] == "AUTHORIZED" &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["predecessor_milestone_route_ref"] == "historical_p3_001_phase_route" &&
           route["preceding_terminal_route_ref"] == "historical_p3_002_phase_route" &&
           route["founder_phase_route_decision_required"] == false &&
           route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "P3-003 Route projection drift")
    assert(task["task_id"] == TASK_ID && task["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           task["task_kind"] == "SINGLE_AGENT_RUNTIME_CAPABILITY_PERMISSION_ENFORCEMENT" &&
           task["capability"] == "PERSISTED_CAPABILITY_LEDGER_AND_TOOL_ADMISSION" &&
           task["implementation_attempt"] == "2_OF_2_FINAL_FOR_MILESTONE" &&
           task["budget"] == FULL_TASK_BUDGET && task["contract"] == identity &&
           task.dig("predecessor_milestone", "status") == "ACCEPTED" &&
           task.dig("preceding_terminal_task", "status") == "TERMINAL_WRITE_ROOT_ESCAPE_NON_PASS" &&
           task.dig("preceding_terminal_task", "engineering_lineage_reusable") == false &&
           task.dig("independence", "p3_002_rejected_lineage_read") == false &&
           task.dig("independence", "p3_002_rejected_lineage_copy") == false,
           "P3-003 selected Task drift")

    ledger = envelope.fetch("task_ledger")
    assert(envelope["phase"] == "P3" && ledger.length == 3 &&
           ledger[0]["status"] == "ACCEPTED_INTEGRATED" &&
           ledger[1]["status"] == "TERMINAL_WRITE_ROOT_ESCAPE_NON_PASS" &&
           ledger[2]["task_id"] == TASK_ID && ledger[2]["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           ledger[2]["implementation_attempt"] == "2_OF_2_FINAL_FOR_MILESTONE" &&
           ledger[2]["budget"] == BUDGET && ledger[2]["contract"] == identity &&
           ledger[2]["authority"].nil? && envelope["consumed"] == {
             "engineering_tasks" => 2, "engineering_hours" => 64, "calendar_days" => 16
           } && envelope["remaining"] == {
             "engineering_tasks" => 5, "engineering_hours" => 160, "calendar_days" => 40
           } && envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["external_effects"] == FALSE_EFFECTS,
           "P3-003 Phase envelope drift")
    assert(envelope["reserved"] == {
             "task_id" => TASK_ID, "route_id" => ROUTE_ID,
             "status" => "ELIGIBLE_NOT_ACTIVATED", "budget" => BUDGET, "authority" => nil
           }, "P3-003 reservation drift")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["current_task_contract"] == identity &&
           active["current_task_contract_sha256"] == CONTRACT_SHA256 &&
           active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
           active["task_branch"].nil? && active["task_worktree"].nil? &&
           active["execution_evidence_root"].nil? && active["authority_record"].values.all?(&:nil?) &&
           active["founder_decision_required"] == false && active["user_action_required"] == "NONE" &&
           active["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" &&
           active["external_effects"] == FALSE_EFFECTS,
           "P3-003 READY active-work projection drift")
    "P3_003_READY_FOR_MASTER_ACTIVATION"
  rescue KeyError, JSON::ParserError, Errno::ENOENT => e
    raise P3Task003AuthorityValidationError, e.message
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(root.join("docs/aios/truth/project_state.yaml").binread,
                           permitted_classes: [], permitted_symbols: [], aliases: false)
    state = P3Task003AuthorityValidation.validate!(root: root, truth: truth)
    puts "P3_003_TASK_AUTHORITY: PASS state=#{state}"
  rescue P3Task003AuthorityValidationError, Psych::SyntaxError => e
    warn "P3_003_TASK_AUTHORITY: NON_PASS #{e.message}"
    exit 1
  end
end

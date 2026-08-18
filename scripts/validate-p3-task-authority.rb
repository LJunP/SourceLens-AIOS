#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

class P3TaskAuthorityValidationError < StandardError; end

module P3TaskAuthorityValidation
  module_function

  ROUTE_SCHEMA = "p3-phase-delegated-task/v1"
  TASK_ID = "AIOS-P3-001_DURABLE_EXECUTION_CHECKPOINT_RESUME_KERNEL"
  ROUTE_ID = "#{TASK_ID}_PHASE_DELEGATED_ROUTE"
  CONTRACT_PATH = "docs/aios/tasks/P3-001_DURABLE_EXECUTION_CHECKPOINT_RESUME_KERNEL.yaml"
  CONTRACT_BYTES = 4115
  CONTRACT_SHA256 = "e34eb7afe5cb666b65080762caa515dac2c445ec71e0c66b823e66c443ccf62a"
  BRANCH = "codex/p3-001-durable-execution-checkpoint-resume"
  WORKTREE = "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-001-durable-execution-checkpoint-resume"
  EVIDENCE_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001"
  AUTHORITY_PATH = File.join(EVIDENCE_ROOT, "authority", "P3_001_PHASE_DELEGATED_TASK_AUTHORITY_V2.json")
  AUTHORITY_BYTES = 3900
  AUTHORITY_SHA256 = "d60fa38bb93987ef42fdcd9d034d0e25ce8d6e264091547e301d608e49a5271d"
  TASK_GATE_PATH = File.join(
    EVIDENCE_ROOT, "terminal", "P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json"
  )
  TASK_GATE_BYTES = 3055
  TASK_GATE_SHA256 = "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
  BUDGET = {
    "engineering_tasks" => 1,
    "engineering_hours" => 32,
    "calendar_days" => 8
  }.freeze
  FALSE_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze

  def assert(condition, message)
    raise P3TaskAuthorityValidationError, message unless condition
  end

  def identity
    {"path" => CONTRACT_PATH, "byte_length" => CONTRACT_BYTES, "sha256" => CONTRACT_SHA256}
  end

  def validate_contract!(root)
    path = root.join(CONTRACT_PATH)
    assert(path.file? && !path.symlink?, "P3-001 Contract must be a regular non-symlink file")
    bytes = path.binread
    assert(bytes.bytesize == CONTRACT_BYTES && Digest::SHA256.hexdigest(bytes) == CONTRACT_SHA256,
           "P3-001 Contract identity drift")
    contract = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(contract["schema_version"] == "p3-task-contract/v1" &&
           contract["record_type"] == "sourcelens_aios_p3_task_contract" &&
           contract["task_id"] == TASK_ID && contract["phase"] == "P3" &&
           contract["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           contract["milestone"] == "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           contract.dig("authority", "activation_parent", "commit") ==
             "80ddaaebb1cea22f0b7d836d11cb6f159ef208f9" &&
           contract.dig("authority", "activation_parent", "tree") ==
             "1749fe921c213eb3db6c07f267bd9fbfa44a2c24" &&
           contract.dig("authority", "phase_entry_parent", "commit") ==
             "b07ea8889c0c68fb343746e65b507b637935af1d" &&
           contract.dig("authority", "task_selection_owner") == "MASTER_CEO_AGENT" &&
           contract.dig("authority", "task_gate_owner") == "MASTER_CEO_AGENT" &&
           contract["budget"] == BUDGET.merge(
             "candidate_generations" => 1, "same_task_repairs" => 1, "review_cycles" => 2
           ) && contract["external_effects"] == FALSE_EFFECTS,
           "P3-001 Contract semantics drift")
    contract
  end

  def validate!(root:, truth:)
    root = Pathname.new(root).realpath
    validate_contract!(root)
    project = truth.fetch("project")
    route = truth.fetch("current_phase_route")
    envelope = truth.fetch("phase_execution_envelope")
    active = truth.fetch("active_work")
    task = route.fetch("selected_task")

    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE" && project["p2_execution_status"] ==
             "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3-001 project Phase projection drift")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["founder_phase_route_decision_required"] == false &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "P3-001 Route projection drift")
    assert(task["task_id"] == TASK_ID &&
           task["task_kind"] == "SINGLE_AGENT_RUNTIME_DURABLE_STATE_AND_RESUME" &&
           task["capability"] == "CHECKPOINT_RESUME" &&
           task["milestone"] == "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           task["budget"] == BUDGET.merge(
             "candidate_generations" => 1, "same_task_repairs" => 1, "review_cycles" => 2
           ) && task["contract"] == identity && task.dig("independence", "p2_rejected_lineage_read") == false &&
           task.dig("independence", "p2_rejected_lineage_compare") == false &&
           task.dig("independence", "p2_rejected_lineage_copy") == false,
           "P3-001 selected Task drift")

    ledger = envelope.fetch("task_ledger")
    assert(envelope["phase"] == "P3" && envelope["limits"].slice(
             "engineering_tasks", "engineering_hours", "calendar_days"
           ) == {"engineering_tasks" => 8, "engineering_hours" => 256, "calendar_days" => 64} &&
           envelope["remaining"] == {"engineering_tasks" => 7, "engineering_hours" => 224, "calendar_days" => 56} &&
           ledger.length == 1 && ledger.first["task_id"] == TASK_ID &&
           ledger.first["budget"] == BUDGET && ledger.first["contract"] == identity &&
           envelope["external_effects"] == FALSE_EFFECTS,
           "P3-001 Phase envelope drift")

    if route["status"] == "AUTHORIZED_READY"
      assert(route["execution_status"] == "P3_TASK_READY" &&
             route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" &&
             route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" &&
             task["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
             ledger.first["status"] == "ELIGIBLE_NOT_ACTIVATED" && ledger.first["authority"].nil? &&
             envelope.dig("reserved", "task_id") == TASK_ID &&
             envelope.dig("reserved", "status") == "ELIGIBLE_NOT_ACTIVATED" &&
             envelope.dig("reserved", "budget") == BUDGET && envelope.dig("reserved", "authority").nil? &&
             envelope["consumed"] == {"engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0} &&
             active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["current_task_contract"] == identity &&
             active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
             active["task_branch"].nil? && active["task_worktree"].nil? &&
             active["execution_evidence_root"].nil? && active["authority_record"].values.all?(&:nil?) &&
             active["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
             "P3-001 READY projection drift")
      return "P3_001_READY_FOR_MASTER_ACTIVATION"
    end

    if route["status"] == "TASK_GATE_PASS_INTEGRATED"
      task_gate_identity = {
        "path" => TASK_GATE_PATH,
        "byte_length" => TASK_GATE_BYTES,
        "sha256" => TASK_GATE_SHA256
      }
      assert(route["execution_status"] == "TASK_GATE_PASS_INTEGRATED" &&
             route["scheduling_status"] == "READY_FOR_MASTER_SELECTION" &&
             route["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
             task["status"] == "ACCEPTED_INTEGRATED" && task["review_status"] == "CYCLE_2_PASS" &&
             task["task_gate_receipt"] == task_gate_identity &&
             ledger.first["status"] == "ACCEPTED_INTEGRATED" &&
             ledger.first["task_gate_receipt"] == task_gate_identity &&
             envelope["reserved"] == {} && envelope["consumed"] == BUDGET &&
             envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
             envelope["delivery_progress"] == {
               "accepted" => 1, "total" => 4, "percent" => 25, "strict_exit_gate_percent" => 0
             } && active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["current_task_contract"].nil? && active["task_resource_state"] ==
               "NOT_CREATED_READY_FOR_MASTER_SELECTION" && active["task_branch"].nil? &&
             active["task_worktree"].nil? && active["execution_evidence_root"].nil? &&
             active["authority_record"].values.all?(&:nil?) &&
             active.dig("last_completed_task", "task_id") == TASK_ID &&
             active.dig("last_completed_task", "status") == "ACCEPTED_INTEGRATED" &&
             active.dig("last_completed_task", "task_gate_receipt") == task_gate_identity &&
             active["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK",
             "P3-001 ACCEPTED projection drift")
      task_gate_path = Pathname.new(TASK_GATE_PATH)
      assert(task_gate_path.file? && !task_gate_path.symlink?,
             "P3-001 Task Gate receipt must be a regular non-symlink file")
      task_gate_bytes = task_gate_path.binread
      assert(task_gate_bytes.bytesize == TASK_GATE_BYTES &&
             Digest::SHA256.hexdigest(task_gate_bytes) == TASK_GATE_SHA256,
             "P3-001 Task Gate receipt identity drift")
      task_gate = JSON.parse(task_gate_bytes)
      assert(task_gate["schema_version"] == "p3-task-gate-integration-receipt/v1" &&
             task_gate["task_id"] == TASK_ID && task_gate["task_lifecycle"] == "ACCEPTED_INTEGRATED" &&
             task_gate["phase_lifecycle"] == "P3_ACTIVE_INCOMPLETE" &&
             task_gate["long_term_goal_lifecycle"] == "ACTIVE" &&
             task_gate["contract"] == identity && task_gate["accepted_milestone"] ==
               "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
             task_gate.dig("canonical_integration", "commit") ==
               "f841ff822610264ad1b88c93b1f6248d42eb134a" &&
             task_gate.dig("canonical_integration", "tree") ==
               "6a3e67b4680464e54d72936dc24a205079614431" &&
             task_gate.dig("canonical_integration", "candidate_files_byte_exact") == "12_OF_12" &&
             task_gate.dig("phase_progress", "delivery_percent") == 25 &&
             task_gate.dig("phase_progress", "strict_p3_exit_gate_percent") == 0 &&
             task_gate["external_effects"] == FALSE_EFFECTS &&
             task_gate["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK",
             "P3-001 Task Gate receipt semantics drift")
      return "P3_001_ACCEPTED_INTEGRATED"
    end

    assert(route["status"] == "ACTIVE" && route["execution_status"] == "ACTIVE" &&
           route["scheduling_status"] == "ACTIVE_PHASE_DELEGATED_TASK" &&
           route["next_eligible_action"] == "INDEPENDENT_REVIEW_CYCLE_2" && task["status"] == "ACTIVE" &&
           ledger.first["status"] == "ACTIVE" && envelope.dig("reserved", "status") == "ACTIVE" &&
           active["current_task"] == TASK_ID && active["current_task_status"] == "ACTIVE" &&
           active["task_resource_state"] == "ACTIVE_UNIQUE_PHASE_DELEGATED" &&
           active["task_branch"] == BRANCH && active["task_worktree"] == WORKTREE &&
           active["execution_evidence_root"] == EVIDENCE_ROOT &&
           envelope["consumed"] == BUDGET &&
           active["authority_record"] == ledger.first["authority"] &&
           active["authority_record"] == envelope.dig("reserved", "authority") &&
           active["current_execution_authorization"] == active.dig("authority_record", "path") &&
           active["current_execution_authorization_sha256"] == active.dig("authority_record", "sha256") &&
           active["execution_nonce_status"] == "ACTIVE" &&
           active["next_eligible_action"] == "INDEPENDENT_REVIEW_CYCLE_2",
           "P3-001 ACTIVE projection drift")
    authority_identity = {
      "path" => AUTHORITY_PATH,
      "byte_length" => AUTHORITY_BYTES,
      "sha256" => AUTHORITY_SHA256
    }
    assert(active["authority_record"] == authority_identity,
           "P3-001 authority identity projection drift")
    authority_path = Pathname.new(AUTHORITY_PATH)
    assert(authority_path.file? && !authority_path.symlink?,
           "P3-001 authority must be a regular non-symlink file")
    authority_bytes = authority_path.binread
    assert(authority_bytes.bytesize == AUTHORITY_BYTES &&
           Digest::SHA256.hexdigest(authority_bytes) == AUTHORITY_SHA256,
           "P3-001 authority identity drift")
    authority = JSON.parse(authority_bytes)
    assert(authority["schema_version"] == "p3-phase-delegated-task-authority/v2" &&
           authority["task_id"] == TASK_ID && authority["branch"] == BRANCH &&
           authority["worktree"] == WORKTREE && authority["evidence_root"] == EVIDENCE_ROOT &&
           authority["contract"] == identity && authority["external_effects"] == FALSE_EFFECTS &&
           authority["authorization_id"] == "102dfcec-69c6-4a74-9daf-498bd1adb8e2" &&
           authority["execution_nonce"] == "ed95029e-edb5-4f80-8d6c-b3f58638ec91" &&
           authority.dig("authority_basis", "activation_parent", "commit") ==
             "80ddaaebb1cea22f0b7d836d11cb6f159ef208f9" &&
           authority.dig("repair_candidate", "commit") ==
             "17ce1134da4ea15c7270b147340ad0bad25c1ac8" &&
           authority.dig("repair_candidate", "tree") ==
             "8b6b4e387067b25052a2f6a64d7b802077acadc5" &&
           authority["budget"] == BUDGET.merge(
             "candidate_generations" => 1, "same_task_repairs" => 1, "review_cycles" => 2
           ) && authority.dig("activation_guards", "single_active_task") == true &&
           authority.dig("activation_guards", "p2_rejected_engineering_lineage_read") == false,
           "P3-001 authority semantics drift")
    "P3_001_ACTIVE"
  rescue KeyError, JSON::ParserError, Errno::ENOENT => e
    raise P3TaskAuthorityValidationError, e.message
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(
      root.join("docs/aios/truth/project_state.yaml").binread,
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    state = P3TaskAuthorityValidation.validate!(root: root, truth: truth)
    puts "P3_TASK_AUTHORITY: PASS state=#{state}"
  rescue P3TaskAuthorityValidationError, Psych::SyntaxError => e
    warn "P3_TASK_AUTHORITY: NON_PASS #{e.message}"
    exit 1
  end
end

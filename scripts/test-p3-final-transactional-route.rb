#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "validate-p3-final-transactional-route"

root = Pathname.new(__dir__).join("..").realpath
truth_path = root.join("docs/aios/truth/project_state.yaml")
terminal_truth = YAML.safe_load(
  truth_path.binread,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)

assertions = 0

state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: terminal_truth)
raise "terminal route state drift" unless
  state == P3FinalTransactionalRouteValidation::TERMINAL_STATE
assertions += 1

active_bytes, active_stderr, active_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::PREACTIVATION_COMMIT}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "active Route Truth unavailable: #{active_stderr}" unless active_status.success?
active_truth = YAML.safe_load(
  active_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
active_tree, tree_stderr, tree_status = Open3.capture3(
  "git", "rev-parse", "#{P3FinalTransactionalRouteValidation::PREACTIVATION_COMMIT}^{tree}",
  chdir: root.to_s
)
raise "active route tree unavailable: #{tree_stderr}" unless tree_status.success?
raise "active route tree drift" unless
  active_tree.strip == P3FinalTransactionalRouteValidation::PREACTIVATION_TREE &&
  active_truth.dig("current_phase_route", "lifecycle_stage") == "PRODUCT_TASK_ACTIVE" &&
  active_truth.dig("active_work", "current_task") == P3FinalTransactionalRouteValidation::TASK_ID
assertions += 1

ready_bytes, ready_stderr, ready_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::TASK_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "ready Route Truth unavailable: #{ready_stderr}" unless ready_status.success?
truth = YAML.safe_load(
  ready_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
ready_state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: truth)
raise "ready route state drift" unless ready_state == P3FinalTransactionalRouteValidation::READY_STATE
assertions += 1

def deep_copy(value)
  JSON.parse(JSON.generate(value))
end

def expect_non_pass(root, truth, label)
  candidate = deep_copy(truth)
  yield candidate
  P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: candidate)
  raise "#{label} false-PASSed"
rescue P3FinalTransactionalRouteValidationError
  true
end

mutations = {
  "historical route drift" => lambda do |candidate|
    candidate["historical_p3_host_owned_fixed_state_workflow_phase_route"]["status"] = "ACTIVE"
  end,
  "route decision identity drift" => lambda do |candidate|
    candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
  end,
  "route objective drift" => lambda do |candidate|
    candidate["current_phase_route"]["objective_id"] = "DYNAMIC_TOOL_BROKER"
  end,
  "slot kind drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][0]["kind"] = "EVALUATION_ONLY"
  end,
  "slot dependency drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][1]["predecessor"] = "NONE"
  end,
  "slot budget drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][0]["budget"]["engineering_hours"] = 33
  end,
  "slot lifecycle drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][1]["status"] = "ELIGIBLE_NOT_ACTIVATED"
  end,
  "prior ledger row drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"][2]["status"] = "ACCEPTED_INTEGRATED"
  end,
  "consumed budget drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 5
  end,
  "remaining budget drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining"]["engineering_hours"] = 96
  end,
  "capacity lock drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining_capacity_usable"] = false
  end,
  "delivery credit drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 75
  end,
  "strict exit drift" => lambda do |candidate|
    items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
    items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
  end,
  "P4 entry drift" => lambda do |candidate|
    candidate["project"]["p4_entry_status"] = "AUTHORIZED"
  end,
  "task creation scope drift" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_scope"] = "ANY_P3_TASK"
  end,
  "reserved trigger drift" => lambda do |candidate|
    candidate["founder_escalation_control"]["reserved_trigger"]["category"] =
      "PHASE_ENTRY_OR_EXIT"
  end,
  "delegation owner drift" => lambda do |candidate|
    candidate["phase_delegation"]["task_selection_owner"] = "FOUNDER"
  end,
  "active-work decision drift" => lambda do |candidate|
    candidate["active_work"]["founder_reserved_authorization_sha256"] = "f" * 64
  end,
  "active-work task drift" => lambda do |candidate|
    candidate["active_work"]["current_task"] = "AIOS-P3-007_FAKE"
  end,
  "phase-local action drift" => lambda do |candidate|
    candidate["phase_execution_claim"]["phase_local_allowed"] = []
  end,
  "claim route drift" => lambda do |candidate|
    candidate["claim_boundary"]["current_phase_route"] = "OLD_ROUTE"
  end,
  "claim progress drift" => lambda do |candidate|
    candidate["claim_boundary"]["p3_delivery_progress_percent"] = 50
  end,
  "terminal P3-006 integration rewrite" => lambda do |candidate|
    candidate["claim_boundary"]["p3_006_candidate_integrated"] = true
  end,
  "long-term Goal drift" => lambda do |candidate|
    candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
  end
}

mutations.each do |label, mutation|
  expect_non_pass(root, truth, label, &mutation)
  assertions += 1
end

active_mutations = {
  "active Contract identity drift" => lambda do |candidate|
    candidate["active_work"]["current_task_contract"]["sha256"] = "0" * 64
  end,
  "active authority identity drift" => lambda do |candidate|
    candidate["active_work"]["authority_record"]["sha256"] = "0" * 64
  end,
  "active route task status drift" => lambda do |candidate|
    candidate["current_phase_route"]["active_task"]["status"] = "ACCEPTED"
  end,
  "active slot lifecycle drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][0]["status"] = "ACCEPTED"
  end,
  "active ledger row drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"].last["status"] = "ACCEPTED"
  end,
  "active consumed budget drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 6
  end,
  "active reservation drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["reserved"]["slot_id"] = "OTHER"
  end,
  "passed preactivation cannot revoke product write" => lambda do |candidate|
    candidate["active_work"]["preactivation"]["product_source_write_authorized"] = false
  end,
  "active branch drift" => lambda do |candidate|
    candidate["active_work"]["task_branch"] = "codex/other"
  end,
  "active action drift" => lambda do |candidate|
    candidate["phase_execution_claim"]["phase_local_allowed"] = ["IMPLEMENT_BEFORE_PREACTIVATION"]
  end,
  "active Task cannot create another Task" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_allowed"] = true
  end,
  "active claim cannot erase current Task" => lambda do |candidate|
    candidate["claim_boundary"]["current_task"] = "NONE"
  end,
  "active Goal cannot erase Task authority" => lambda do |candidate|
    candidate["goal"]["current_task_authority"] = "NONE"
  end,
  "active Task cannot enter P4" => lambda do |candidate|
    candidate["project"]["p4_entry_status"] = "AUTHORIZED"
  end,
  "active Task cannot rewrite P3-006 integration" => lambda do |candidate|
    candidate["claim_boundary"]["p3_006_candidate_integrated"] = true
  end
}

active_mutations.each do |label, mutation|
  expect_non_pass(root, active_truth, label, &mutation)
  assertions += 1
end

terminal_mutations = {
  "terminal Task cannot be rewritten PASS" => lambda do |candidate|
    candidate["current_phase_route"]["terminal_task"]["status"] = "ACCEPTED"
  end,
  "terminal security verdict cannot be rewritten" => lambda do |candidate|
    candidate["current_phase_route"]["terminal_task"]["independent_review_verdicts"]["security"] = "PASS"
  end,
  "terminal candidate cannot be marked integrated" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"].last["candidate"]["integrated"] = true
  end,
  "terminal receipt identity cannot drift" => lambda do |candidate|
    candidate["current_phase_route"]["terminal_task"]["terminal_receipt"]["sha256"] = "0" * 64
  end,
  "terminal slot cannot receive delivery credit" => lambda do |candidate|
    candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 75
  end,
  "terminal evaluation slot cannot unlock" => lambda do |candidate|
    candidate["phase_execution_envelope"]["ordered_slots"][1]["status"] = "ELIGIBLE_NOT_ACTIVATED"
  end,
  "terminal reserved budget cannot reappear" => lambda do |candidate|
    candidate["phase_execution_envelope"]["reserved"] = {"task_id" => "AIOS-P3-008_FAKE"}
  end,
  "terminal remaining capacity cannot become usable" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining_capacity_usable"] = true
  end,
  "terminal state cannot create a Task" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_allowed"] = true
  end,
  "terminal state cannot erase reserved trigger" => lambda do |candidate|
    candidate["founder_escalation_control"]["reserved_trigger"] = {
      "category" => "NONE", "evidence" => nil
    }
  end,
  "terminal active work cannot resurrect Task" => lambda do |candidate|
    candidate["active_work"]["current_task"] = P3FinalTransactionalRouteValidation::TASK_ID
  end,
  "terminal phase cannot schedule implementation" => lambda do |candidate|
    candidate["phase_execution_claim"]["phase_local_allowed"] = [
      P3FinalTransactionalRouteValidation::IMPLEMENT_ACTION
    ]
  end,
  "terminal claim cannot unlock evaluation" => lambda do |candidate|
    candidate["claim_boundary"]["p3_007_evaluation_slot_unlocked"] = true
  end,
  "terminal strict Exit cannot be accepted" => lambda do |candidate|
    items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
    items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
  end,
  "terminal Long-term Goal cannot close" => lambda do |candidate|
    candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
  end
}

terminal_mutations.each do |label, mutation|
  expect_non_pass(root, terminal_truth, label, &mutation)
  assertions += 1
end

puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions"

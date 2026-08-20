#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "validate-p3-final-transactional-route"

root = Pathname.new(__dir__).join("..").realpath
truth_path = root.join("docs/aios/truth/project_state.yaml")
host_authorized_truth = YAML.safe_load(
  truth_path.binread,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)

assertions = 0

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

if host_authorized_truth.dig("current_phase_route", "schema_version") ==
   P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_ROUTE_SCHEMA
  state = P3FinalTransactionalRouteValidation.validate_truth!(
    root: root, truth: host_authorized_truth
  )
  expected_state =
    if host_authorized_truth.dig("current_phase_route", "lifecycle_stage") ==
       "FOUNDATION_TASK_ACTIVE"
      P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_FOUNDATION_ACTIVE_STATE
    else
      P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_ROUTE_STATE
    end
  raise "host-authorized current route state drift" unless state == expected_state
  assertions += 1

  host_authorized_mutations = {
    "host-authorized decision identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
    end,
    "host-authorized Objective cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["objective_id"] = "GENERIC_TOOL_BROKER"
    end,
    "host-authorized route cannot omit the capacity trigger" => lambda do |candidate|
      candidate["current_phase_route"]["founder_reserved_triggers_resolved"].pop
    end,
    "host-authorized cumulative Task ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_tasks"] = 11
    end,
    "host-authorized cumulative hour ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_hours"] = 320
    end,
    "host-authorized consumed accounting cannot reset" => lambda do |candidate|
      candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 0
    end,
    "host-authorized stage order cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].reverse!
    end,
    "host-authorized product cannot unlock before foundation acceptance" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "host-authorized audit cannot unlock before product acceptance" => lambda do |candidate|
      candidate["phase_execution_envelope"]["ordered_stages"][2]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "host-authorized installation cannot claim delivery credit" => lambda do |candidate|
      candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 50
    end,
    "host-authorized installation cannot weaken strict Exit" => lambda do |candidate|
      required_items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
      required_items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
    end,
    "host-authorized installation cannot permit rejected-lineage reuse" => lambda do |candidate|
      candidate["phase_execution_claim"]["phase_local_frozen_capabilities"].delete(
        "P3_002_THROUGH_P3_007_REJECTED_LINEAGE_FROZEN_UNREADABLE"
      )
    end,
    "host-authorized installation cannot authorize a second product Task" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].insert(
        2, deep_copy(candidate["current_phase_route"]["ordered_stages"][1])
      )
    end,
    "host-authorized installation cannot enter P4" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end,
    "host-authorized installation cannot close the long-term Goal" => lambda do |candidate|
      candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
    end
  }

  if expected_state ==
     P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_FOUNDATION_ACTIVE_STATE
    host_authorized_mutations.merge!({
      "active foundation Task identity cannot drift" => lambda do |candidate|
        candidate["active_work"]["current_task"] = "AIOS-P3-008_FORBIDDEN"
      end,
      "active foundation Contract identity cannot drift" => lambda do |candidate|
        candidate["active_work"]["current_task_contract"]["sha256"] = "0" * 64
      end,
      "active foundation authority identity cannot drift" => lambda do |candidate|
        candidate["active_work"]["authority_record"]["sha256"] = "0" * 64
      end,
      "active foundation branch cannot drift" => lambda do |candidate|
        candidate["active_work"]["task_branch"] = "codex/p3-008-forbidden"
      end,
      "active foundation reserved budget cannot drift" => lambda do |candidate|
        candidate["phase_execution_envelope"]["reserved"]["engineering_hours"] = 32
      end,
      "active foundation cannot unlock concurrent capacity" => lambda do |candidate|
        candidate["phase_execution_envelope"]["remaining_capacity_usable"] = true
      end,
      "active foundation cannot permit another Task" => lambda do |candidate|
        candidate["phase_boundary"]["task_creation_allowed"] = true
      end,
      "active foundation cannot claim acceptance before review" => lambda do |candidate|
        candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 50
      end
    })
  end

  host_authorized_mutations.each do |label, mutation|
    expect_non_pass(root, host_authorized_truth, label, &mutation)
    assertions += 1
  end

  puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions mode=HOST_AUTHORIZED_CURRENT_ONLY_NO_REJECTED_LINEAGE_REPLAY"
  exit 0
end

hold_bytes, hold_stderr, hold_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "strategic HOLD Truth unavailable: #{hold_stderr}" unless hold_status.success?
hold_truth = YAML.safe_load(
  hold_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
hold_state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: hold_truth)
raise "strategic HOLD route state drift" unless
  hold_state == P3FinalTransactionalRouteValidation::HOLD_STATE
assertions += 1

terminal_bytes, terminal_stderr, terminal_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::HOLD_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "terminal Route Truth unavailable: #{terminal_stderr}" unless terminal_status.success?
terminal_truth = YAML.safe_load(
  terminal_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
terminal_state = P3FinalTransactionalRouteValidation.validate_truth!(
  root: root,
  truth: terminal_truth
)
raise "terminal route state drift" unless
  terminal_state == P3FinalTransactionalRouteValidation::TERMINAL_STATE
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

hold_mutations = {
  "HOLD decision identity cannot drift" => lambda do |candidate|
    candidate["current_phase_route"]["founder_hold_decision"]["sha256"] = "0" * 64
  end,
  "HOLD cannot create a Task" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_allowed"] = true
  end,
  "HOLD cannot unlock remaining capacity" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining_capacity_usable"] = true
  end,
  "HOLD cannot unlock evaluation" => lambda do |candidate|
    candidate["phase_execution_envelope"]["ordered_slots"][1]["status"] =
      "ELIGIBLE_NOT_ACTIVATED"
  end,
  "HOLD cannot accept strict Exit" => lambda do |candidate|
    items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
    items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
  end,
  "HOLD cannot integrate rejected candidate" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"].last["candidate"]["integrated"] = true
  end,
  "HOLD cannot enter P4" => lambda do |candidate|
    candidate["project"]["p4_entry_status"] = "AUTHORIZED"
  end,
  "HOLD cannot close Long-term Goal" => lambda do |candidate|
    candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
  end,
  "HOLD cannot request ordinary Founder action" => lambda do |candidate|
    candidate["founder_escalation_control"]["founder_decision_required"] = true
  end,
  "HOLD next action cannot drift" => lambda do |candidate|
    candidate["claim_boundary"]["next_eligible_action"] = "MASTER_CREATE_TASK"
  end
}

hold_mutations.each do |label, mutation|
  expect_non_pass(root, hold_truth, label, &mutation)
  assertions += 1
end

puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions"

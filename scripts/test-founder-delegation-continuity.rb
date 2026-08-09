#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "open3"
require "tmpdir"
require "yaml"

require_relative "validate-founder-delegation-continuity"

ROOT = File.expand_path("..", __dir__)
TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
VALIDATOR = File.join(ROOT, "scripts/validate-founder-delegation-continuity.rb")

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def run_fixture(root, name, truth)
  path = File.join(root, "#{name}.yaml")
  File.binwrite(path, YAML.dump(truth))
  Open3.capture3("ruby", VALIDATOR, "--fixture", path, chdir: ROOT)
end

def identity_for(path)
  bytes = File.binread(path)
  {
    "path" => File.realpath(path),
    "byte_length" => bytes.bytesize,
    "sha256" => Digest::SHA256.hexdigest(bytes)
  }
end

def write_json_identity(root, name, value)
  path = File.join(root, name)
  File.binwrite(path, JSON.generate(value))
  identity_for(path)
end

def bind_strategic_decision(truth, identity)
  truth.fetch("founder_escalation_control").fetch("resolution")["structured_decision"] =
    deep_copy(identity)
  truth.fetch("current_phase_route")["founder_decision"] = deep_copy(identity)
  truth.fetch("active_work")["founder_reserved_authorization"] = identity.fetch("path")
  truth.fetch("active_work")["founder_reserved_authorization_sha256"] = identity.fetch("sha256")
end

def expect_pass(root, name, truth, expected)
  stdout, stderr, status = run_fixture(root, name, truth)
  raise "#{name} unexpectedly failed\n#{stdout}#{stderr}" unless status.success?
  raise "#{name} disposition drift\n#{stdout}" unless stdout.include?("disposition=#{expected}")
end

def expect_non_pass(root, name, truth, expected_fragment)
  stdout, stderr, status = run_fixture(root, name, truth)
  raise "#{name} unexpectedly passed\n#{stdout}#{stderr}" if status.success?
  combined = stdout + stderr
  raise "#{name} failed for the wrong reason\n#{combined}" unless combined.include?(expected_fragment)
end

current_truth = YAML.safe_load(
  File.binread(TRUTH),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)

route_literal = "AIOS-P2-058_DEV_FIRST_GRAPH_CONTEXT_VALUE_BENCHMARK_PHASE_DELEGATED_ROUTE"
commits, stderr, status = Open3.capture3(
  "git", "log", "--reverse", "--format=%H", "--",
  "docs/aios/truth/project_state.yaml", chdir: ROOT
)
raise "cannot resolve delegated active Truth history: #{stderr}" unless status.success?
historical_truths = []
active_truths = commits.lines.map(&:strip).reject(&:empty?).each_with_object([]) do |commit, values|
  bytes, _show_stderr, show_status = Open3.capture3(
    "git", "show", "#{commit}:docs/aios/truth/project_state.yaml", chdir: ROOT
  )
  next unless show_status.success?
  begin
    candidate = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
  rescue Psych::BadAlias, Psych::SyntaxError
    next
  end
  historical_truths << candidate
  route = candidate["current_phase_route"]
  values << candidate if route.is_a?(Hash) && route["route_id"] == route_literal && route["status"] == "ACTIVE"
end
base = active_truths.last
raise "delegated active Truth anchor is missing" unless base
base.fetch("phase_execution_envelope").fetch("task_ledger").each do |entry|
  entry.delete("capacity_source_task_id")
end
base["phase_boundary"] = deep_copy(current_truth.fetch("phase_boundary"))
reserved_base = historical_truths.reverse.find do |candidate|
  candidate.dig("founder_escalation_control", "schema_version") == "founder-escalation-control/v1" &&
    candidate.dig("founder_escalation_control", "reserved_trigger", "evidence", "path").is_a?(String) &&
    candidate.dig("phase_execution_envelope", "status") == "EXHAUSTED"
end
raise "Founder reserved Truth anchor is missing" unless reserved_base

Dir.mktmpdir("founder-delegation-continuity-") do |fixtures|
  assertions = 0

  current_disposition = current_truth.fetch("founder_escalation_control").fetch("disposition")
  expect_pass(fixtures, "current-canonical-delegation-disposition", current_truth,
              current_disposition)
  assertions += 1

  if current_truth.dig("current_phase_route", "schema_version") ==
     FounderDelegationContinuity::STRATEGIC_HOLD_ROUTE_SCHEMA
    decision_path = current_truth.dig(
      "founder_escalation_control", "resolution", "structured_decision", "path"
    )
    decision = JSON.parse(File.binread(decision_path))

    truth = deep_copy(current_truth)
    variant = deep_copy(decision)
    variant["decision"]["p3_entry_authorized"] = true
    bind_strategic_decision(
      truth, write_json_identity(fixtures, "strategic-hold-p3-entry.json", variant)
    )
    expect_non_pass(fixtures, "strategic-hold-cannot-enter-p3", truth,
                    "Founder strategic-hold disposition drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(decision)
    variant["phase_envelope"]["limits"]["engineering_tasks"] = 6
    bind_strategic_decision(
      truth, write_json_identity(fixtures, "strategic-hold-envelope-expansion.json", variant)
    )
    expect_non_pass(fixtures, "strategic-hold-cannot-expand-envelope", truth,
                    "Founder strategic-hold Phase envelope drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(decision)
    variant["phase_exit_gate"]["missing_required_item_status"] = "ACCEPTED"
    bind_strategic_decision(
      truth, write_json_identity(fixtures, "strategic-hold-false-exit.json", variant)
    )
    expect_non_pass(fixtures, "strategic-hold-cannot-complete-exit-gate", truth,
                    "Founder strategic-hold Phase Exit Gate drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth["founder_escalation_control"]["founder_decision_required"] = true
    expect_non_pass(fixtures, "strategic-hold-cannot-repeat-founder-prompt", truth,
                    "Founder strategic-hold control projection drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth["active_work"]["next_eligible_action"] = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
    expect_non_pass(fixtures, "strategic-hold-cannot-schedule-engineering", truth,
                    "active_work Founder strategic-hold projection drift")
    assertions += 1
  end

  truth = deep_copy(reserved_base)
  trigger = JSON.parse(File.binread(
    truth.dig("founder_escalation_control", "reserved_trigger", "evidence", "path")
  ))
  trigger["condition"]["requested_budget"] = {
    "engineering_tasks" => 6,
    "engineering_hours" => 136,
    "calendar_days" => 34
  }
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, "agent-invented-next-budget.json", trigger)
  expect_non_pass(fixtures, "exhausted-phase-cannot-invent-next-founder-budget", truth,
                  "exhausted Phase decision Evidence must not invent a new Founder budget")
  assertions += 1

  truth = deep_copy(reserved_base)
  trigger = JSON.parse(File.binread(
    truth.dig("founder_escalation_control", "reserved_trigger", "evidence", "path")
  ))
  trigger["supporting_evidence"].pop
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, "missing-terminal-ledger-support.json", trigger)
  expect_non_pass(fixtures, "exhausted-phase-must-bind-all-terminal-receipts", truth,
                  "Founder budget expansion trigger must bind every consumed Task outcome receipt")
  assertions += 1

  truth = deep_copy(current_truth)
  terminal_entry = truth.fetch("phase_execution_envelope").fetch("task_ledger").last
  terminal_entry["outcome_receipt"] = write_json_identity(
    fixtures,
    "superficial-predeclared-terminal-receipt.json",
    {
      "task_id" => terminal_entry["task_id"],
      "route_id" => terminal_entry["route_id"],
      "status" => terminal_entry["status"]
    }
  )
  expect_non_pass(fixtures, "predeclared-terminal-receipt-substitution", truth,
                  "phase execution source Task ledger entry has no immutable Git introduction")
  assertions += 1

  expect_pass(fixtures, "ordinary-terminal-continues", base,
              "NO_RESERVED_TRIGGER_CONTINUE_PHASE")
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["founder_decision_required"] = true
  expect_non_pass(fixtures, "review-non-pass-founder-required", truth,
                  "delegated independent Task must not invent a Founder authorization or action")
  assertions += 1

  truth = deep_copy(base)
  truth["current_phase_route"]["founder_phase_route_decision_required"] = true
  expect_non_pass(fixtures, "route-terminal-founder-required", truth,
                  "delegated independent Task route cannot require Founder decision")
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["next_eligible_action"] = "FOUNDER_P2_PHASE_GATE"
  expect_non_pass(fixtures, "ordinary-terminal-next-founder", truth,
                  "delegated independent Task ACTIVE active_work drift")
  assertions += 1

  truth = deep_copy(base)
  truth["founder_escalation_control"]["reserved_trigger"]["category"] =
    "FINAL_REVIEW_TARGET_NON_PASS"
  expect_non_pass(fixtures, "review-verdict-as-reserved-trigger", truth,
                  "unknown Founder reserved trigger")
  assertions += 1

  truth = deep_copy(base)
  truth["founder_escalation_control"]["source_event"]["task_id"] =
    "AIOS-P2-999_FAKE_TASK"
  expect_non_pass(fixtures, "terminal-task-identity-drift", truth,
                  "ordinary terminal event Task identity drift")
  assertions += 1

  truth = deep_copy(base)
  truth["founder_escalation_control"]["unexpected"] = true
  expect_non_pass(fixtures, "escalation-extra-field", truth,
                  "founder_escalation_control keys are not closed")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_execution_envelope"]["remaining"]["engineering_hours"] += 1
  expect_non_pass(fixtures, "remaining-budget-drift", truth,
                  "phase execution envelope remaining accounting drift")
  assertions += 1

  truth = deep_copy(base)
  source_entry = truth.dig("phase_execution_envelope", "task_ledger", 0)
  source_entry["outcome_receipt"] = write_json_identity(
    fixtures,
    "superficial-source-terminal-receipt.json",
    {
      "schema_version" => "superficial-terminal-receipt/v1",
      "task_id" => source_entry["task_id"],
      "route_id" => source_entry["route_id"],
      "terminal_status" => source_entry["status"]
    }
  )
  expect_non_pass(fixtures, "source-terminal-receipt-substitution", truth,
                  "source Task ledger drifts from its first canonical anchor")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_execution_envelope"]["status"] = "EXHAUSTED"
  expect_non_pass(fixtures, "false-envelope-exhaustion", truth,
                  "phase execution envelope status does not match reservation and remaining capacity")
  assertions += 1

  truth = deep_copy(base)
  truth["authority"]["founder_delegation_policy"]["version"] = "1.7"
  expect_non_pass(fixtures, "policy-downgrade", truth,
                  "Founder delegation policy version drift")
  assertions += 1

  truth = deep_copy(base)
  truth["project"]["current_route_execution_status"] = "STOPPED_AT_FOUNDER_P2_PHASE_GATE"
  expect_non_pass(fixtures, "project-stopped-at-false-founder-gate", truth,
                  "delegated independent Task ACTIVE project or Goal projection drift")
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["current_task"] = "AIOS-P2-999_FAKE_TASK"
  expect_non_pass(fixtures, "active-task-during-selection-hold", truth,
                  "delegated independent Task ACTIVE active_work drift")
  assertions += 1

  truth = deep_copy(base)
  p2 = truth.dig("strict_phase_gate_ledger", "phases", "P2")
  p2["required_items"].each_value { |item| item["status"] = "ACCEPTED" }
  p2["status"] = "EXIT_GATE_READY"
  p2["founder_phase_gate"]["status"] = "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  control = truth["founder_escalation_control"]
  control["disposition"] = "FOUNDER_DECISION_REQUIRED"
  control["reserved_trigger"] = {"category" => "PHASE_ENTRY_OR_EXIT", "evidence" => nil}
  control["source_event"] = {
    "kind" => "PHASE_EXIT_GATE_ELIGIBLE",
    "task_id" => nil,
    "status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  }
  control["phase_gate_status"] = "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  control["founder_decision_required"] = true
  control["next_action_owner"] = "HUMAN_FOUNDER"
  control["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  route = truth["current_phase_route"]
  route["schema_version"] = "founder-reserved-decision-hold/v1"
  route["route_id"] = "P2_FOUNDER_RESERVED_DECISION_HOLD"
  route["status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  route["execution_status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  route["scheduling_status"] = "STOPPED_AT_FOUNDER_RESERVED_DECISION"
  route["founder_phase_route_decision_required"] = true
  route["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  route.delete("source_authority_route_ref")
  route.delete("preceding_terminal_route_ref")
  route.delete("selected_task")
  route["historical_terminal_route_ref"] = "historical_p2_057_phase_route"
  route["inherited_worktree_inventory_source"] = "historical_p2_057_phase_route"
  truth["project"]["phase_execution_status"] = "STOPPED_AT_FOUNDER_RESERVED_DECISION"
  truth["project"]["current_route_execution_status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  active = truth["active_work"]
  active["current_task"] = "NONE"
  active["current_task_status"] = "NONE"
  active["task_resource_state"] = "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD"
  active["founder_decision_required"] = true
  active["founder_decision_required_scope"] = "PHASE_ENTRY_OR_EXIT"
  active["escalation_reason"] = "PHASE_ENTRY_OR_EXIT"
  active["user_action_required"] = "FOUNDER_RESERVED_DECISION"
  active["phase_route_decision_required"] = true
  active["phase_route_user_action_required"] = "FOUNDER_RESERVED_DECISION"
  active["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  expect_pass(fixtures, "eligible-phase-exit-founder-decision", truth,
              "FOUNDER_DECISION_REQUIRED")
  assertions += 1

  truth = deep_copy(base)
  control = truth["founder_escalation_control"]
  control["disposition"] = "FOUNDER_DECISION_REQUIRED"
  control["reserved_trigger"] = {"category" => "PHASE_ENTRY_OR_EXIT", "evidence" => nil}
  control["source_event"] = {
    "kind" => "PHASE_EXIT_GATE_ELIGIBLE",
    "task_id" => nil,
    "status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  }
  control["founder_decision_required"] = true
  control["next_action_owner"] = "HUMAN_FOUNDER"
  control["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  expect_non_pass(fixtures, "incomplete-phase-false-exit-gate", truth,
                  "Phase exit escalation requires a complete eligible Exit Gate")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_execution_envelope"]["external_effects"]["network"] = true
  expect_non_pass(fixtures, "silent-effect-expansion", truth,
                  "phase execution envelope external effects exceed offline boundary")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_delegation"]["anti_loop"]["reviewer_non_pass_may_trigger_founder_gate"] = true
  expect_non_pass(fixtures, "delegation-reviewer-escalation-downgrade", truth,
                  "Phase delegation anti-loop control drift")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_delegation"]["agent_delegated_decisions"].delete(
    "choose_the_next_independent_phase_local_task_after_task_completion_or_stop"
  )
  expect_non_pass(fixtures, "delegated-continuation-deleted", truth,
                  "Agent delegated decision set drift")
  assertions += 1

  truth = deep_copy(base)
  historical = truth.delete("historical_p2_058_founder_expansion_phase_route")
  truth["historical_p2_058_archive_phase_route"] = historical
  truth["current_phase_route"]["source_authority_route_ref"] =
    "historical_p2_058_archive_phase_route"
  truth["phase_execution_envelope"]["authority_basis"]["source_route_ref"] =
    "historical_p2_058_archive_phase_route"
  expect_pass(fixtures, "data-driven-historical-route-reference", truth,
              "NO_RESERVED_TRIGGER_CONTINUE_PHASE")
  assertions += 1

  truth = deep_copy(base)
  truth["current_phase_route"]["schema_version"] = "1.1"
  truth["current_phase_route"]["route_id"] = "P2_FUTURE_PHASE_LOCAL_ENGINEERING_ROUTE_V1"
  truth["current_phase_route"]["founder_phase_route_decision_required"] = false
  truth["active_work"]["current_task"] = "AIOS-P2-999_FUTURE_INDEPENDENT_TASK"
  truth["active_work"]["current_task_status"] = "ACTIVE"
  truth["active_work"]["next_eligible_action"] = "COMPLETE_CURRENT_TASK_GATE"
  expect_non_pass(fixtures, "future-active-task-cannot-bypass-phase-ledger", truth,
                  "active Phase delegation envelope requires a closed delegated Route schema")
  assertions += 1

  truth["active_work"]["founder_decision_required"] = true
  expect_non_pass(fixtures, "future-active-task-cannot-self-escalate", truth,
                  "active Phase delegation envelope requires a closed delegated Route schema")
  assertions += 1

  truth = deep_copy(base)
  truth.delete("phase_execution_envelope")
  truth["current_phase_route"]["schema_version"] = "1.1"
  truth["current_phase_route"]["route_id"] = "P2_PHASE_ENVELOPE_DELETION_ESCAPE"
  expect_non_pass(fixtures, "phase-envelope-cannot-be-deleted-to-escape-delegation", truth,
                  "active Phase delegation requires a phase execution envelope")
  assertions += 1

  truth = deep_copy(base)
  support_path = File.join(fixtures, "ordinary-terminal-support.txt")
  File.binwrite(support_path, "ordinary terminal is not a reserved trigger\n")
  fake_trigger = {
    "schema_version" => "founder-reserved-trigger-evidence/v1",
    "category" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE",
    "phase" => "P2",
    "source_event" => truth["founder_escalation_control"]["source_event"],
    "source_route_id" => truth["historical_p2_055_phase_route"]["route_id"],
    "condition" => {
      "phase_route_change" => false,
      "material_scope_or_permission_expansion" => false,
      "requested_budget" => {
        "engineering_tasks" => 2,
        "engineering_hours" => 40,
        "calendar_days" => 10
      },
      "requested_external_effects" => {
        "network" => false,
        "provider" => false,
        "secret" => false,
        "remote" => false,
        "production" => false,
        "public" => false
      },
      "irreversible_asset_action" => false,
      "material_legal_privacy_commercial_commitment" => false,
      "critical_residual_risk_acceptance" => true
    },
    "supporting_evidence" => [identity_for(support_path)]
  }
  truth["founder_escalation_control"]["disposition"] = "FOUNDER_DECISION_REQUIRED"
  truth["founder_escalation_control"]["source_event"] = {
    "kind" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE_REQUIRED",
    "task_id" => nil,
    "status" => "PENDING_FOUNDER_RESERVED_DECISION"
  }
  fake_trigger["source_event"] = truth["founder_escalation_control"]["source_event"]
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, "fake-critical-trigger-consistent.json", fake_trigger)
  truth["founder_escalation_control"]["reserved_trigger"] = {
    "category" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE",
    "evidence" => truth["founder_escalation_control"]["reserved_trigger"]["evidence"]
  }
  truth["founder_escalation_control"]["founder_decision_required"] = true
  truth["founder_escalation_control"]["next_action_owner"] = "HUMAN_FOUNDER"
  truth["founder_escalation_control"]["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  expect_non_pass(fixtures, "ordinary-terminal-cannot-masquerade-as-critical-risk", truth,
                  "terminal transition only supports mechanically derived Phase exit or envelope expansion")
  assertions += 1

  truth = deep_copy(base)
  historical = truth["historical_p2_055_phase_route"]
  classifier_control = deep_copy(truth["founder_escalation_control"])
  historical["first_task"]["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
  historical["task_plan"][0]["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
  historical["task_plan"][1]["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  classifier_control["source_event"] = {
    "kind" => "TASK_TERMINAL_FINAL_REVIEW_NON_PASS",
    "task_id" => historical["task_plan"][1]["task_id"],
    "status" => "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  }
  truth["founder_escalation_control"] = classifier_control
  FounderDelegationContinuity.validate_control!(
    truth,
    "P2",
    "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
    false,
    historical,
    truth["phase_execution_envelope"]
  ).tap do |result|
    raise "later Task terminal classifier drift" unless result["source_event"]["task_id"] ==
                                                        historical["task_plan"][1]["task_id"]
  end
  assertions += 1

  truth = deep_copy(base)
  truth["historical_p2_058_founder_expansion_phase_route"]["envelope"]["max_engineering_tasks"] = 4
  truth["phase_execution_envelope"]["limits"]["engineering_tasks"] = 4
  truth["phase_execution_envelope"]["remaining"]["engineering_tasks"] = 1
  expect_non_pass(fixtures, "self-consistent-source-envelope-expansion", truth,
                  "historical source Route static authority drifts from its first canonical Git anchor")
  assertions += 1

  truth = deep_copy(base)
  historical = truth["historical_p2_058_founder_expansion_phase_route"]
  historical["task_plan"][2]["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["execution_status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  envelope = truth["phase_execution_envelope"]
  envelope["status"] = "EXHAUSTED"
  envelope["consumed"] = {
    "engineering_tasks" => 3,
    "engineering_hours" => 64,
    "calendar_days" => 16
  }
  envelope["reserved"] = nil
  envelope["remaining"] = {
    "engineering_tasks" => 0,
    "engineering_hours" => 0,
    "calendar_days" => 0
  }
  expect_non_pass(fixtures, "self-reported-unbound-second-task-cannot-exhaust-envelope", truth,
                  "phase execution task ledger omits a consumed source Route Task")
  assertions += 1

  puts "FOUNDER_DELEGATION_CONTINUITY_TESTS: PASS assertions=#{assertions}"
end

#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

require_relative "validate-founder-delegation-continuity"

ROOT = File.expand_path("..", __dir__)
TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
VALIDATOR = File.join(ROOT, "scripts/validate-founder-delegation-continuity.rb")
TASK_ID = "AIOS-P2-057_PHASE_DELEGATED_CONTEXT_VALUE_VERTICAL_SLICE"

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

def expect_pass(root, name, truth, expected)
  stdout, stderr, status = run_fixture(root, name, truth)
  raise "#{name} unexpectedly failed\n#{stdout}#{stderr}" unless status.success?
  raise "#{name} disposition drift\n#{stdout}" unless stdout.include?("disposition=#{expected}")
end

def expect_non_pass(root, name, truth, expected_fragment)
  stdout, stderr, status = run_fixture(root, name, truth)
  raise "#{name} unexpectedly passed\n#{stdout}#{stderr}" if status.success?
  combined = stdout + stderr
  unless combined.include?(expected_fragment)
    raise "#{name} failed for the wrong reason\nexpected=#{expected_fragment.inspect}\n#{combined}"
  end
end

def expect_direct_non_pass(name, expected_fragment)
  yield
  raise "#{name} unexpectedly passed"
rescue FounderDelegationContinuityError => e
  unless e.message.include?(expected_fragment)
    raise "#{name} failed for the wrong reason: #{e.message.inspect}"
  end
end

def delegated_entry(truth)
  truth.fetch("phase_execution_envelope").fetch("task_ledger").find do |entry|
    entry["task_id"] == TASK_ID
  end || raise("delegated terminal ledger entry missing")
end

def trigger_evidence(truth)
  identity = truth.dig("founder_escalation_control", "reserved_trigger", "evidence")
  JSON.parse(File.binread(identity.fetch("path")))
end

def replace_trigger_evidence!(truth, fixtures, name)
  value = trigger_evidence(truth)
  yield value
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, name, value)
end

def latest_truth_for_route_schema(schema)
  stdout, stderr, status = Open3.capture3(
    "git", "log", "--format=%H", "--", "docs/aios/truth/project_state.yaml",
    chdir: ROOT
  )
  raise "cannot enumerate canonical Truth history: #{stderr}" unless status.success?
  stdout.lines.map(&:strip).reject(&:empty?).each do |commit|
    bytes, _show_stderr, show_status = Open3.capture3(
      "git", "show", "#{commit}:docs/aios/truth/project_state.yaml", chdir: ROOT
    )
    next unless show_status.success?
    truth = YAML.safe_load(bytes, aliases: false)
    return truth if truth.dig("current_phase_route", "schema_version") == schema
  rescue Psych::Exception
    next
  end
  raise "no canonical Truth anchor found for Route schema #{schema}"
end

def run_continuation_regressions(fixtures, base)
  assertions = 0

  expect_pass(fixtures, "legacy-ordinary-terminal-continues", base,
              FounderDelegationContinuity::CONTINUE_DISPOSITION)
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["founder_decision_required"] = true
  expect_non_pass(fixtures, "legacy-review-non-pass-founder-required", truth,
                  "active_work ordinary terminal projection drift")
  assertions += 1

  truth = deep_copy(base)
  truth["current_phase_route"]["founder_phase_route_decision_required"] = true
  expect_non_pass(fixtures, "legacy-route-terminal-founder-required", truth,
                  "delegated continuation route cannot require Founder decision")
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["next_eligible_action"] = "FOUNDER_P2_PHASE_GATE"
  expect_non_pass(fixtures, "legacy-ordinary-terminal-next-founder", truth,
                  "active_work ordinary terminal projection drift")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("founder_escalation_control", "source_event")["task_id"] =
    "AIOS-P2-999_FAKE_TASK"
  expect_non_pass(fixtures, "legacy-terminal-task-identity-drift", truth,
                  "ordinary terminal event Task identity drift")
  assertions += 1

  truth = deep_copy(base)
  truth["founder_escalation_control"]["unexpected"] = true
  expect_non_pass(fixtures, "legacy-escalation-extra-field", truth,
                  "founder_escalation_control keys are not closed")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("phase_execution_envelope", "remaining")["engineering_hours"] += 1
  expect_non_pass(fixtures, "legacy-remaining-budget-drift", truth,
                  "phase execution envelope remaining accounting drift")
  assertions += 1

  truth = deep_copy(base)
  source_entry = truth.dig("phase_execution_envelope", "task_ledger", 0)
  source_entry["outcome_receipt"] = write_json_identity(
    fixtures,
    "legacy-superficial-source-terminal-receipt.json",
    {
      "schema_version" => "superficial-terminal-receipt/v1",
      "task_id" => source_entry["task_id"],
      "route_id" => source_entry["route_id"],
      "terminal_status" => source_entry["status"]
    }
  )
  expect_non_pass(fixtures, "legacy-source-terminal-receipt-substitution", truth,
                  "source Task ledger drifts from its first canonical anchor")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("phase_execution_envelope")["status"] = "EXHAUSTED"
  expect_non_pass(fixtures, "legacy-false-envelope-exhaustion", truth,
                  "phase execution envelope status does not match reservation and remaining capacity")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("authority", "founder_delegation_policy")["version"] = "1.7"
  expect_non_pass(fixtures, "legacy-policy-downgrade", truth,
                  "Founder delegation policy version drift")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("project")["current_route_execution_status"] = "STOPPED_AT_FOUNDER_P2_PHASE_GATE"
  expect_non_pass(fixtures, "legacy-project-stopped-at-false-founder-gate", truth,
                  "project Phase continuation status drift")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("active_work")["current_task"] = "AIOS-P2-999_FAKE_TASK"
  expect_non_pass(fixtures, "legacy-active-task-during-selection-hold", truth,
                  "delegated continuation requires current Task NONE")
  assertions += 1

  truth = deep_copy(base)
  p2 = truth.dig("strict_phase_gate_ledger", "phases", "P2")
  p2["required_items"].each_value { |item| item["status"] = "ACCEPTED" }
  p2["status"] = "EXIT_GATE_READY"
  p2["founder_phase_gate"]["status"] = "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  control = truth["founder_escalation_control"]
  control["disposition"] = FounderDelegationContinuity::FOUNDER_DISPOSITION
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
  route["schema_version"] = FounderDelegationContinuity::RESERVED_ROUTE_SCHEMA
  route["route_id"] = "P2_FOUNDER_RESERVED_DECISION_HOLD"
  route["status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  route["execution_status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  route["scheduling_status"] = "STOPPED_AT_FOUNDER_RESERVED_DECISION"
  route["founder_phase_route_decision_required"] = true
  route["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  truth["project"]["phase_execution_status"] = "STOPPED_AT_FOUNDER_RESERVED_DECISION"
  truth["project"]["current_route_execution_status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  active = truth["active_work"]
  active["task_resource_state"] = "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD"
  active["founder_decision_required"] = true
  active["founder_decision_required_scope"] = "PHASE_ENTRY_OR_EXIT"
  active["escalation_reason"] = "PHASE_ENTRY_OR_EXIT"
  active["user_action_required"] = "FOUNDER_RESERVED_DECISION"
  active["phase_route_decision_required"] = true
  active["phase_route_user_action_required"] = "FOUNDER_RESERVED_DECISION"
  active["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  expect_pass(fixtures, "eligible-phase-exit-founder-decision", truth,
              FounderDelegationContinuity::FOUNDER_DISPOSITION)
  assertions += 1

  truth = deep_copy(base)
  control = truth["founder_escalation_control"]
  control["disposition"] = FounderDelegationContinuity::FOUNDER_DISPOSITION
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
  truth.dig("phase_execution_envelope", "external_effects")["network"] = true
  expect_non_pass(fixtures, "legacy-silent-effect-expansion", truth,
                  "phase execution envelope external effects exceed offline boundary")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("phase_delegation", "anti_loop")["reviewer_non_pass_may_trigger_founder_gate"] = true
  expect_non_pass(fixtures, "legacy-reviewer-escalation-downgrade", truth,
                  "Phase delegation anti-loop control drift")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("phase_delegation", "agent_delegated_decisions").delete(
    "choose_the_next_independent_phase_local_task_after_task_completion_or_stop"
  )
  expect_non_pass(fixtures, "legacy-delegated-continuation-deleted", truth,
                  "Agent delegated decision set drift")
  assertions += 1

  truth = deep_copy(base)
  historical = truth.delete("historical_p2_055_phase_route")
  truth["historical_p2_055_archive_phase_route"] = historical
  truth["current_phase_route"]["historical_terminal_route_ref"] =
    "historical_p2_055_archive_phase_route"
  truth["current_phase_route"]["inherited_worktree_inventory_source"] =
    "historical_p2_055_archive_phase_route"
  truth.dig("phase_execution_envelope", "authority_basis")["source_route_ref"] =
    "historical_p2_055_archive_phase_route"
  expect_pass(fixtures, "legacy-data-driven-historical-route-reference", truth,
              FounderDelegationContinuity::CONTINUE_DISPOSITION)
  assertions += 1

  truth = deep_copy(base)
  truth.dig("current_phase_route")["schema_version"] = "1.1"
  truth.dig("current_phase_route")["route_id"] = "P2_FUTURE_PHASE_LOCAL_ENGINEERING_ROUTE_V1"
  truth.dig("active_work")["current_task"] = "AIOS-P2-999_FUTURE_INDEPENDENT_TASK"
  truth.dig("active_work")["current_task_status"] = "ACTIVE"
  expect_non_pass(fixtures, "legacy-generic-schema-cannot-bypass-phase-ledger", truth,
                  "active Phase delegation envelope requires a closed delegated Route schema")
  assertions += 1

  truth = deep_copy(base)
  truth.delete("phase_execution_envelope")
  truth.dig("current_phase_route")["schema_version"] = "1.1"
  truth.dig("current_phase_route")["route_id"] = "P2_PHASE_ENVELOPE_DELETION_ESCAPE"
  expect_non_pass(fixtures, "legacy-envelope-cannot-be-deleted", truth,
                  "active Phase delegation requires a phase execution envelope")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("historical_p2_055_phase_route", "envelope")["max_engineering_tasks"] = 3
  truth.dig("phase_execution_envelope", "limits")["engineering_tasks"] = 3
  truth.dig("phase_execution_envelope", "remaining")["engineering_tasks"] = 2
  expect_non_pass(fixtures, "legacy-source-envelope-anchor-drift", truth,
                  "historical source Route static authority drifts from its first canonical Git anchor")
  assertions += 1

  truth = deep_copy(base)
  historical = truth["historical_p2_055_phase_route"]
  historical.dig("first_task")["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
  historical.dig("task_plan", 0)["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
  historical.dig("task_plan", 1)["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["execution_status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  envelope = truth["phase_execution_envelope"]
  envelope["status"] = "EXHAUSTED"
  envelope["consumed"] = {
    "engineering_tasks" => 2,
    "engineering_hours" => 40,
    "calendar_days" => 10
  }
  envelope["remaining"] = {
    "engineering_tasks" => 0,
    "engineering_hours" => 0,
    "calendar_days" => 0
  }
  expect_non_pass(fixtures, "legacy-unbound-second-task-cannot-exhaust-envelope", truth,
                  "phase execution task ledger omits a consumed source Route Task")
  assertions += 1

  assertions
end

base = YAML.safe_load(
  File.binread(TRUTH),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
continuation_base = latest_truth_for_route_schema(
  FounderDelegationContinuity::CONTINUATION_ROUTE_SCHEMA
)

Dir.mktmpdir("founder-delegation-continuity-") do |fixtures|
  assertions = run_continuation_regressions(fixtures, continuation_base)

  expect_pass(fixtures, "exhausted-phase-reserved-hold", base,
              FounderDelegationContinuity::FOUNDER_DISPOSITION)
  assertions += 1

  requested = trigger_evidence(base).dig("condition", "requested_budget")
  raise "requested total Phase limits drift" unless requested == {
    "engineering_tasks" => 3,
    "engineering_hours" => 64,
    "calendar_days" => 16
  }
  expected_support = base.dig("phase_execution_envelope", "task_ledger").map do |entry|
    entry.fetch("outcome_receipt")
  end
  raise "reserved trigger support is not the closed Task receipt ledger" unless
    trigger_evidence(base).fetch("supporting_evidence") == expected_support
  assertions += 1

  truth = deep_copy(base)
  delegated_entry(truth)["capability_credit"] = 1
  expect_non_pass(fixtures, "delegated-terminal-nonzero-credit", truth,
                  "may record only zero capability credit")
  assertions += 1

  truth = deep_copy(base)
  delegated_entry(truth).dig("activation_binding")["first_active_anchor_commit"] = "0" * 40
  expect_non_pass(fixtures, "delegated-terminal-active-anchor-drift", truth,
                  "first ACTIVE anchor commit drift")
  assertions += 1

  truth = deep_copy(base)
  delegated_entry(truth).dig("activation_binding", "authority")["sha256"] = "0" * 64
  expect_non_pass(fixtures, "delegated-terminal-authority-binding-drift", truth,
                  "ACTIVE authority binding drift")
  assertions += 1

  truth = deep_copy(base)
  duplicate = deep_copy(delegated_entry(truth))
  duplicate["task_id"] = "AIOS-P2-999_DUPLICATE_CAPACITY_CLAIM"
  truth.dig("phase_execution_envelope", "task_ledger") << duplicate
  expect_non_pass(fixtures, "capacity-source-consumed-twice", truth,
                  "capacity source is consumed more than once")
  assertions += 1

  active_entry = delegated_entry(base).fetch("activation_binding")
  active_bytes, active_stderr, active_status = Open3.capture3(
    "git", "show",
    "#{active_entry.fetch('first_active_anchor_commit')}:#{active_entry.dig('contract', 'path')}",
    chdir: ROOT
  )
  raise "cannot read first ACTIVE Contract: #{active_stderr}" unless active_status.success?
  active_contract = YAML.safe_load(active_bytes, aliases: false)
  terminal_contract = YAML.safe_load(
    File.binread(File.join(ROOT, delegated_entry(base).dig("contract", "path"))),
    aliases: false
  )
  FounderDelegationContinuity.validate_terminal_contract_static_fields!(
    active_contract,
    terminal_contract
  )
  assertions += 1

  mutated_contract = deep_copy(terminal_contract)
  mutated_contract.dig("budget", "engineering_hours").then do |value|
    mutated_contract["budget"]["engineering_hours"] = value + 1
  end
  expect_direct_non_pass("terminal-contract-static-budget-drift",
                         "static fields drift from first ACTIVE anchor") do
    FounderDelegationContinuity.validate_terminal_contract_static_fields!(
      active_contract,
      mutated_contract
    )
  end
  assertions += 1

  forensic = delegated_entry(base).fetch("formal_forensic")
  FounderDelegationContinuity.validate_closed_formal_inventory!(
    forensic,
    "test formal Evidence"
  )
  assertions += 1

  bad_forensic = deep_copy(forensic)
  bad_forensic["canonical_inventory_sha256"] = "0" * 64
  expect_direct_non_pass("formal-live-closed-inventory-drift",
                         "canonical inventory SHA-256 mismatch") do
    FounderDelegationContinuity.validate_closed_formal_inventory!(
      bad_forensic,
      "test formal Evidence"
    )
  end
  assertions += 1

  truth = deep_copy(base)
  truth.dig("historical_p2_057_phase_delegated_phase_route")["capability_credit"] = 1
  expect_non_pass(fixtures, "historical-p2-057-capability-credit-drift", truth,
                  "historical delegated terminal Route lifecycle or capability drift")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("historical_p2_057_phase_delegated_phase_route")["accepted_capability_created"] = true
  expect_non_pass(fixtures, "historical-p2-057-false-acceptance", truth,
                  "historical delegated terminal Route lifecycle or capability drift")
  assertions += 1

  truth = deep_copy(base)
  historical_forensic = truth.dig(
    "historical_p2_057_phase_delegated_phase_route",
    "formal_forensic"
  )
  historical_forensic["canonical_inventory_sha256"] = "0" * 64
  expect_non_pass(fixtures, "historical-p2-057-formal-identity-drift", truth,
                  "drifts from validated terminal ledger")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("claim_boundary")["p2_057_capability_credit"] = 1
  expect_non_pass(fixtures, "claim-p2-057-capability-credit-drift", truth,
                  "claim_boundary terminal projection drift: p2_057_capability_credit")
  assertions += 1

  receipt = JSON.parse(File.binread(delegated_entry(base).dig("outcome_receipt", "path")))
  authority = JSON.parse(File.binread(active_entry.dig("authority", "path")))
  superficial = deep_copy(receipt)
  superficial.delete("candidate")
  expect_direct_non_pass("superficial-terminal-receipt-closed-schema", "keys are not closed") do
    FounderDelegationContinuity.validate_terminal_receipt_and_formal_evidence!(
      Pathname.new(ROOT),
      superficial,
      delegated_entry(base),
      authority
    )
  end
  assertions += 1

  fake_root = Dir.mktmpdir(
    "superficial-formal-",
    active_entry.fetch("evidence_root")
  )
  begin
    File.binwrite(File.join(fake_root, "self-report.json"), "{\"status\":\"PASS\"}\n")
    fake_receipt = deep_copy(receipt)
    fake_receipt.dig("formal_execution")["evidence_root"] = fake_root
    fake_entry = deep_copy(delegated_entry(base))
    fake_entry.dig("formal_forensic")["evidence_root"] = fake_root
    expect_direct_non_pass("superficial-one-file-formal-evidence", "candidate result is unavailable") do
      FounderDelegationContinuity.validate_terminal_receipt_and_formal_evidence!(
        Pathname.new(ROOT),
        fake_receipt,
        fake_entry,
        authority
      )
    end
    assertions += 1
  ensure
    FileUtils.remove_entry(fake_root) if File.exist?(fake_root)
  end

  truth = deep_copy(base)
  truth.dig("phase_execution_envelope")["reserved"] = {}
  expect_non_pass(fixtures, "exhausted-envelope-cannot-retain-reservation", truth,
                  "phase execution reserved Task keys are not closed")
  assertions += 1

  truth = deep_copy(base)
  replace_trigger_evidence!(truth, fixtures, "below-consumed-total.json") do |evidence|
    evidence.dig("condition", "requested_budget")["engineering_tasks"] = 1
  end
  expect_non_pass(fixtures, "requested-total-below-consumed", truth,
                  "requested total budget is below consumed capacity")
  assertions += 1

  truth = deep_copy(base)
  replace_trigger_evidence!(truth, fixtures, "no-strict-expansion.json") do |evidence|
    evidence["condition"]["requested_budget"] = {
      "engineering_tasks" => 2,
      "engineering_hours" => 40,
      "calendar_days" => 10
    }
  end
  expect_non_pass(fixtures, "requested-total-does-not-expand", truth,
                  "does not prove its category")
  assertions += 1

  truth = deep_copy(base)
  replace_trigger_evidence!(truth, fixtures, "missing-task-support.json") do |evidence|
    evidence.fetch("supporting_evidence").pop
  end
  expect_non_pass(fixtures, "trigger-missing-consumed-task-receipt", truth,
                  "must bind every consumed Task outcome receipt")
  assertions += 1

  truth = deep_copy(base)
  replace_trigger_evidence!(truth, fixtures, "ambiguous-trigger.json") do |evidence|
    evidence.dig("condition")["phase_route_change"] = true
  end
  expect_non_pass(fixtures, "ambiguous-founder-trigger", truth,
                  "contains ambiguous reserved conditions")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("active_work")["current_task"] = TASK_ID
  expect_non_pass(fixtures, "reserved-hold-retains-active-task", truth,
                  "Founder reserved hold requires current Task NONE")
  assertions += 1

  truth = deep_copy(base)
  truth.dig("founder_escalation_control", "reserved_trigger")["category"] =
    "CRITICAL_RESIDUAL_RISK_ACCEPTANCE"
  expect_non_pass(fixtures, "task-failure-masquerades-as-risk-acceptance", truth,
                  "terminal transition only supports mechanically derived Phase exit or envelope expansion")
  assertions += 1

  puts "FOUNDER_DELEGATION_CONTINUITY_TESTS: PASS assertions=#{assertions}"
end

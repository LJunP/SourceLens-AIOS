#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

require_relative "validate-p3-phase-entry"

ROOT = File.expand_path("..", __dir__)
TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def load_yaml(bytes)
  YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
end

def expect_pass(name, truth, expected)
  state = P3PhaseEntryValidation.validate!(root: ROOT, truth: truth)
  raise "#{name} state drift: #{state}" unless state == expected
  puts "PASS #{name}"
end

def expect_non_pass(name, truth, fragment)
  P3PhaseEntryValidation.validate!(root: ROOT, truth: truth)
  raise "#{name} unexpectedly passed"
rescue P3PhaseEntryValidationError, P3Task004AuthorityValidationError,
       P3ZeroAuthorityRouteValidationError, P3Task005AuthorityValidationError => e
  raise "#{name} failed for the wrong reason: #{e.message}" unless e.message.include?(fragment)
  puts "PASS #{name} rejected"
end

def git_show(commit, path)
  stdout, stderr, status = Open3.capture3("git", "-C", ROOT, "show", "#{commit}:#{path}")
  raise "cannot load #{commit}:#{path}: #{stderr}" unless status.success?
  stdout
end

current_truth = load_yaml(File.binread(TRUTH))
assertions = 0

expect_pass(
  "exact host-owned fixed-state Route projection",
  current_truth,
  "P3_HOST_OWNED_FIXED_STATE_ROUTE_SLOT_1_ACTIVE"
)
assertions += 1

entry_truth = load_yaml(
  git_show("b07ea8889c0c68fb343746e65b507b637935af1d", "docs/aios/truth/project_state.yaml")
)
expect_pass("historical exact P3 entry projection", entry_truth, "P3_ENTRY_ACTIVE_TASK_SELECTION_READY")
assertions += 1

mutations = [
  ["Founder decision identity cannot drift", "host-owned Founder decision SHA-256 mismatch",
   ->(t) { t.dig("current_phase_route", "founder_route_decision")["sha256"] = "0" * 64 }],
  ["activation parent tree cannot drift", "host-owned activation parent commit/tree drift",
   ->(t) { t.dig("current_phase_route", "activation_parent")["tree"] = "0" * 40 }],
  ["route objective cannot drift", "host-owned current Route lifecycle drift",
   ->(t) { t.dig("current_phase_route")["objective_id"] = "AGENT_AUTHORED_PLAN" }],
  ["route may not grant network", "host-owned current Route lifecycle drift",
   ->(t) { t.dig("current_phase_route", "external_effects")["network"] = true }],
  ["slot 1 active status cannot claim acceptance", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 0)["status"] = "ACCEPTED" }],
  ["slot 1 delivery credit cannot drift", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 0)["delivery_percent_on_pass"] = 75 }],
  ["slot 1 unlock target cannot drift", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 0)["pass_unlocks_only"] = "P4" }],
  ["slot 2 predecessor cannot drift", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 1)["predecessor"] = "NONE" }],
  ["slot 2 cannot activate before slot 1 acceptance", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 1)["status"] = "ELIGIBLE_NOT_ACTIVATED" }],
  ["slot 2 budget cannot expand", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 1, "budget")["engineering_hours"] = 64 }],
  ["slot 3 must remain evaluation-only", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 2)["kind"] = "PRODUCT_IMPLEMENTATION" }],
  ["slot 3 cannot create a candidate", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 2)["max_candidate_generations"] = 1 }],
  ["slot 3 cannot rerun to pass", "host-owned Route slot dependency projection drift",
   ->(t) { t.dig("current_phase_route", "ordered_slots", 2)["rerun_to_pass_allowed"] = true }],
  ["Phase Task limit cannot expand", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope", "limits")["engineering_tasks"] = 9 }],
  ["consumed Task accounting cannot reset", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope", "consumed")["engineering_tasks"] = 4 }],
  ["remaining hours cannot expand", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope", "remaining")["engineering_hours"] = 128 }],
  ["remaining capacity cannot relock while slot 1 eligible", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope")["remaining_capacity_usable"] = false }],
  ["milestone order cannot drift", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope", "milestone_order")[1] = "DYNAMIC_CAPABILITY_LEDGER" }],
  ["accepted milestone cannot be fabricated", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope", "accepted_milestones") << "HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION" }],
  ["installation cannot receive delivery credit", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope", "delivery_progress")["percent"] = 50 }],
  ["envelope slot 2 cannot unlock early", "host-owned P3 Phase envelope drift",
   ->(t) { t.dig("phase_execution_envelope", "ordered_slots", 1)["status"] = "ELIGIBLE_NOT_ACTIVATED" }],
  ["strict Exit cannot be accepted by installation", "host-owned strict P3 Exit projection drift",
   ->(t) { t.dig("strict_phase_gate_ledger", "phases", "P3")["status"] = "EXIT_GATE_READY" }],
  ["strict Exit wording cannot be lowered", "host-owned strict P3 Exit projection drift",
   ->(t) { t.dig("strict_phase_gate_ledger", "phases", "P3", "exit_gate_authority")["required_exit_evidence"] = "Documentation" }],
  ["P4 cannot be entered", "host-owned project projection drift",
   ->(t) { t.dig("project")["p4_entry_status"] = "AUTHORIZED" }],
  ["project P3 status cannot claim completion", "host-owned project projection drift",
   ->(t) { t.dig("project")["p3_execution_status"] = "COMPLETE" }],
  ["Phase boundary cannot enable a different Task kind", "host-owned Phase boundary drift",
   ->(t) { t.dig("phase_boundary", "allowed_task_kinds")[0] = "GENERIC_INTERPRETER" }],
  ["Phase boundary cannot create a second Task", "host-owned Phase boundary drift",
   ->(t) { t.dig("phase_boundary")["task_creation_allowed"] = true }],
  ["Founder control cannot return to NONE owner", "host-owned Founder escalation projection drift",
   ->(t) { t.dig("founder_escalation_control")["next_action_owner"] = "NONE_ROUTE_TERMINAL" }],
  ["Founder control cannot invent a reserved trigger", "host-owned Founder escalation projection drift",
   ->(t) { t.dig("founder_escalation_control", "reserved_trigger")["category"] = "PHASE_ENTRY_OR_EXIT" }],
  ["Phase delegation source cannot drift", "host-owned Phase delegation drift",
   ->(t) { t.dig("phase_delegation")["decision_source"] = "OLD_ROUTE" }],
  ["active Task identity cannot drift", "host-owned active Task Contract lifecycle drift",
   ->(t) { t.dig("active_work")["current_task"] = "AIOS-P3-006_UNAUTHORIZED" }],
  ["active Task nonce cannot drift", "host-owned active Task authority drift",
   ->(t) { t.dig("active_work")["execution_nonce"] = "premature" }],
  ["active authorization cannot drift", "host-owned active-work projection drift",
   ->(t) { t.dig("active_work")["founder_reserved_authorization_sha256"] = "0" * 64 }],
  ["Phase-local slot 1 action cannot disappear", "host-owned execution claim drift",
   ->(t) { t.dig("phase_execution_claim")["phase_local_allowed"] = [] }],
  ["claim boundary cannot fabricate delivery", "host-owned claim boundary drift",
   ->(t) { t.dig("claim_boundary")["p3_delivery_progress_percent"] = 50 }],
  ["claim boundary cannot close Long-term Goal", "host-owned claim boundary drift",
   ->(t) { t.dig("claim_boundary")["long_term_goal_status"] = "COMPLETE" }],
  ["active Task Contract identity cannot drift", "host-owned active Task Contract SHA-256 mismatch",
   ->(t) { t.dig("active_work", "current_task_contract")["sha256"] = "0" * 64 }],
  ["active Task authority identity cannot drift", "host-owned active Task authority aliases drift",
   ->(t) { t.dig("active_work", "authority_record")["sha256"] = "0" * 64 }],
  ["active Task ledger status cannot drift", "host-owned active Task ledger entry drift",
   ->(t) { t.dig("phase_execution_envelope", "task_ledger", 5)["status"] = "ACCEPTED" }],
  ["active Task budget cannot drift", "host-owned active Task active-work budget or roles drift",
   ->(t) { t.dig("active_work", "budget")["engineering_hours"] = 64 }],
  ["active Task reviewer roles cannot drift", "host-owned active Task active-work budget or roles drift",
   ->(t) { t.dig("active_work", "roles", "independent_reviewers").pop }]
]

mutations.each do |name, fragment, mutation|
  fixture = deep_copy(current_truth)
  mutation.call(fixture)
  expect_non_pass(name, fixture, fragment)
  assertions += 1
end

5.times do |index|
  fixture = deep_copy(current_truth)
  fixture.dig("phase_execution_envelope", "task_ledger", index)["status"] = "REWRITTEN"
  expect_non_pass("historical Task ledger entry #{index + 1} is immutable", fixture,
                  "host-owned P3 Task ledger drift")
  assertions += 1
end

fixture = deep_copy(current_truth)
fixture.dig("phase_execution_envelope", "task_ledger") << {"task_id" => "FABRICATED"}
expect_non_pass("historical Task ledger length is immutable", fixture,
                "host-owned P3 Task ledger drift")
assertions += 1

Dir.mktmpdir("p3-host-owned-untracked-") do |directory|
  _out, err, status = Open3.capture3("git", "-C", directory, "init", "-q")
  raise "temporary git init failed: #{err}" unless status.success?
  File.binwrite(File.join(directory, "rogue.txt"), "rogue\n")
  begin
    P3PhaseEntryValidation.validate_host_owned_repository_scope!(directory, {
      "active_work" => {
        "current_task_contract" => {"path" => "docs/aios/tasks/expected.yaml"}
      }
    })
    raise "untracked repository file unexpectedly passed"
  rescue P3PhaseEntryValidationError => e
    raise "untracked test failed for wrong reason: #{e.message}" unless
      e.message.include?("neither exact installation nor exact Task activation")
  end
  puts "PASS untracked repository file rejected"
  assertions += 1
end

puts "P3_PHASE_ENTRY_TESTS: PASS #{assertions} assertions"

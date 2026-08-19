#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "open3"

require_relative "validate-p3-phase-entry"

ROOT = File.expand_path("..", __dir__)
TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def expect_pass(name, truth)
  state = P3PhaseEntryValidation.validate!(root: ROOT, truth: truth)
  raise "#{name} state drift: #{state}" unless state == "P3_ENTRY_ACTIVE_TASK_SELECTION_READY"
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

entry_truth_bytes, entry_truth_error, entry_truth_status = Open3.capture3(
  "git", "-C", ROOT, "show",
  "b07ea8889c0c68fb343746e65b507b637935af1d:docs/aios/truth/project_state.yaml"
)
raise "cannot load installed P3 entry Truth: #{entry_truth_error}" unless entry_truth_status.success?
truth = YAML.safe_load(
  entry_truth_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)

assertions = 0

expect_pass("exact P3 entry projection", truth)
assertions += 1

current_truth = YAML.safe_load(
  File.binread(TRUTH), permitted_classes: [], permitted_symbols: [], aliases: false
)
current_state = P3PhaseEntryValidation.validate!(root: ROOT, truth: current_truth)
raise "current P3-005 READY state drift: #{current_state}" unless
  current_state == "P3_005_READY_FOR_MASTER_ACTIVATION"
puts "PASS current P3-005 READY projection"
assertions += 1

fixture = deep_copy(current_truth)
fixture.dig("current_phase_route", "founder_route_decision")["sha256"] = "0" * 64
expect_non_pass("P3-005 Founder route identity cannot drift", fixture,
                "P3-005 Route projection drift")
assertions += 1

fixture = deep_copy(current_truth)
fixture.dig("phase_boundary")["task_creation_allowed"] = false
expect_non_pass("P3-005 must remain inside eligible slot 1", fixture,
                "P3-005 Phase boundary drift")
assertions += 1

fixture = deep_copy(current_truth)
fixture.dig("current_phase_route", "selected_task", "contract")["sha256"] = "0" * 64
expect_non_pass("P3-005 Contract identity cannot drift", fixture,
                "P3-005 selected Task drift")
assertions += 1

fixture = deep_copy(current_truth)
fixture.dig("current_phase_route", "ordered_slots", 1)["status"] = "ELIGIBLE_NOT_ACTIVATED"
expect_non_pass("P3 slot 2 cannot unlock before P3-005 PASS", fixture,
                "P3-005 ordered slot projection drift")
assertions += 1

fixture = deep_copy(truth)
fixture.dig("strict_phase_gate_ledger", "phases", "P2", "original_capability_gate")["status"] =
  "ACCEPTED"
expect_non_pass("P2 capability history cannot be rewritten", fixture,
                "strict P2 conclusion drift")
assertions += 1

fixture = deep_copy(truth)
fixture.dig("phase_execution_envelope", "limits")["engineering_tasks"] = 9
expect_non_pass("P3 Task budget cannot expand", fixture, "P3 Phase envelope drift")
assertions += 1

fixture = deep_copy(truth)
fixture.dig("claim_boundary")["p3_phase_envelope_status"] = "EXHAUSTED"
expect_non_pass("P3 claim cannot hide usable capacity", fixture, "P3 claim boundary drift")
assertions += 1

fixture = deep_copy(truth)
fixture.dig("current_phase_route", "founder_phase_entry_decision")["sha256"] = "0" * 64
expect_non_pass("P3 entry identity cannot drift", fixture,
                "current P3 Route decision identity drift")
assertions += 1

fixture = deep_copy(truth)
fixture.dig("current_phase_route")["p4_entry_authorized"] = true
expect_non_pass("P4 cannot activate through P3 entry", fixture, "current P3 Route drift")
assertions += 1

puts "P3_PHASE_ENTRY_TESTS: PASS #{assertions} assertions"

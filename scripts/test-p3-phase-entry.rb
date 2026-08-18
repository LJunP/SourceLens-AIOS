#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

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
rescue P3PhaseEntryValidationError => e
  raise "#{name} failed for the wrong reason: #{e.message}" unless e.message.include?(fragment)
  puts "PASS #{name} rejected"
end

truth = YAML.safe_load(
  File.binread(TRUTH),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)

assertions = 0

expect_pass("exact P3 entry projection", truth)
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

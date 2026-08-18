#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "validate-p3-task-authority"

ROOT = File.expand_path("..", __dir__)

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def reject_drift(name, truth, fragment)
  P3TaskAuthorityValidation.validate!(root: ROOT, truth: truth)
  raise "#{name} unexpectedly passed"
rescue P3TaskAuthorityValidationError => e
  raise "#{name} wrong rejection: #{e.message}" unless e.message.include?(fragment)
  puts "PASS #{name} rejected"
end

truth = YAML.safe_load(
  File.binread(File.join(ROOT, "docs/aios/truth/project_state.yaml")),
  permitted_classes: [], permitted_symbols: [], aliases: false
)

state = P3TaskAuthorityValidation.validate!(root: ROOT, truth: truth)
raise "exact READY state drift" unless state == "P3_001_READY_FOR_MASTER_ACTIVATION"
puts "PASS exact P3-001 READY projection"
assertions = 1

fixture = copy(truth)
fixture.dig("current_phase_route", "selected_task", "budget")["engineering_hours"] = 33
reject_drift("budget expansion", fixture, "selected Task drift")
assertions += 1

fixture = copy(truth)
fixture.dig("current_phase_route", "external_effects")["network"] = true
reject_drift("network expansion", fixture, "Route projection drift")
assertions += 1

fixture = copy(truth)
fixture.dig("current_phase_route", "selected_task", "independence")["p2_rejected_lineage_read"] = true
reject_drift("rejected lineage read", fixture, "selected Task drift")
assertions += 1

fixture = copy(truth)
fixture.dig("phase_execution_envelope", "remaining")["engineering_tasks"] = 8
reject_drift("reservation conservation", fixture, "Phase envelope drift")
assertions += 1

puts "P3_TASK_AUTHORITY_TESTS: PASS #{assertions} assertions"

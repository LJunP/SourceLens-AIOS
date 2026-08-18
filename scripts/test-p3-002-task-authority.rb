#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"
require_relative "validate-p3-002-task-authority"

ROOT = File.expand_path("..", __dir__)

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def reject_drift(name, truth, fragment)
  P3Task002AuthorityValidation.validate!(root: ROOT, truth: truth)
  raise "#{name} unexpectedly passed"
rescue P3Task002AuthorityValidationError => e
  raise "#{name} wrong rejection: #{e.message}" unless e.message.include?(fragment)
  puts "PASS #{name} rejected"
end

ready_bytes, ready_error, ready_status = Open3.capture3(
  "git", "-C", ROOT, "show",
  "779fc3d52f8b6a9a5e871e4b14a820d783203961:docs/aios/truth/project_state.yaml"
)
raise "cannot load P3-002 READY Truth: #{ready_error}" unless ready_status.success?
ready_truth = YAML.safe_load(ready_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
ready_state = P3Task002AuthorityValidation.validate!(root: ROOT, truth: ready_truth)
raise "exact READY state drift" unless ready_state == "P3_002_READY_FOR_MASTER_ACTIVATION"
puts "PASS exact P3-002 READY projection"
assertions = 1

active_bytes, active_error, active_status = Open3.capture3(
  "git", "-C", ROOT, "show",
  "b135ed3:docs/aios/truth/project_state.yaml"
)
raise "cannot load P3-002 ACTIVE Truth: #{active_error}" unless active_status.success?
active_truth = YAML.safe_load(active_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
active_state = P3Task002AuthorityValidation.validate!(root: ROOT, truth: active_truth)
raise "exact ACTIVE state drift" unless active_state == "P3_002_ACTIVE"
puts "PASS exact P3-002 ACTIVE projection"
assertions += 1

terminal_bytes, terminal_error, terminal_status = Open3.capture3(
  "git", "-C", ROOT, "show",
  "8bee5cb2f6c0cc0d69d9c4e228d9d2c00c401a1c:docs/aios/truth/project_state.yaml"
)
raise "cannot load P3-002 TERMINAL Truth: #{terminal_error}" unless terminal_status.success?
truth = YAML.safe_load(terminal_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
state = P3Task002AuthorityValidation.validate!(root: ROOT, truth: truth)
raise "exact TERMINAL state drift" unless state == "P3_002_TERMINAL_WRITE_ROOT_ESCAPE_NON_PASS"
puts "PASS exact P3-002 TERMINAL projection"
assertions += 1

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
fixture.dig("phase_execution_envelope", "remaining")["engineering_tasks"] = 7
reject_drift("reservation conservation", fixture, "Phase envelope drift")
assertions += 1

fixture = copy(truth)
fixture.dig("current_phase_route", "selected_task", "predecessor_milestone")["status"] = "MISSING"
reject_drift("predecessor milestone", fixture, "selected Task drift")
assertions += 1

puts "P3_002_TASK_AUTHORITY_TESTS: PASS #{assertions} assertions"

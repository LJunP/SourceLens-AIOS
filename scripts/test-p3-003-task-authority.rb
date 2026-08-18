#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"
require_relative "validate-p3-003-task-authority"

ROOT = File.expand_path("..", __dir__)

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def reject_drift(name, truth, fragment)
  P3Task003AuthorityValidation.validate!(root: ROOT, truth: truth)
  raise "#{name} unexpectedly passed"
rescue P3Task003AuthorityValidationError => e
  raise "#{name} wrong rejection: #{e.message}" unless e.message.include?(fragment)
  puts "PASS #{name} rejected"
end

ready_bytes, ready_error, ready_status = Open3.capture3(
  "git", "-C", ROOT, "show",
  "93a5c0c26d3fabf4895cb92dd96676e491bb148e:docs/aios/truth/project_state.yaml"
)
raise "cannot load P3-003 READY Truth: #{ready_error}" unless ready_status.success?
ready_truth = YAML.safe_load(ready_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
ready_state = P3Task003AuthorityValidation.validate!(root: ROOT, truth: ready_truth)
raise "exact READY state drift" unless ready_state == "P3_003_READY_FOR_MASTER_ACTIVATION"
puts "PASS exact P3-003 READY projection"
assertions = 1

truth = YAML.safe_load(File.binread(File.join(ROOT, "docs/aios/truth/project_state.yaml")),
                       permitted_classes: [], permitted_symbols: [], aliases: false)
state = P3Task003AuthorityValidation.validate!(root: ROOT, truth: truth)
raise "exact ACTIVE preactivation state drift" unless state == "P3_003_ACTIVE_PREACTIVATION_REQUIRED"
puts "PASS exact P3-003 ACTIVE preactivation projection"
assertions += 1

fixture = copy(truth)
fixture.dig("current_phase_route", "selected_task")["implementation_attempt"] = "3_OF_3"
reject_drift("implementation attempt expansion", fixture, "selected Task drift")
assertions += 1

fixture = copy(truth)
fixture.dig("current_phase_route", "selected_task", "independence")["p3_002_rejected_lineage_read"] = true
reject_drift("P3-002 lineage read", fixture, "selected Task drift")
assertions += 1

fixture = copy(truth)
fixture.dig("phase_execution_envelope", "remaining")["engineering_tasks"] = 6
reject_drift("reservation conservation", fixture, "Phase envelope drift")
assertions += 1

fixture = copy(truth)
fixture.dig("current_phase_route", "external_effects")["network"] = true
reject_drift("network expansion", fixture, "Route projection drift")
assertions += 1

puts "P3_003_TASK_AUTHORITY_TESTS: PASS #{assertions} assertions"

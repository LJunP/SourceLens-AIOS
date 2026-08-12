#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "tmpdir"
require "yaml"
require_relative "validate-p2-recovery-anti-cycle"

ROOT = P2RecoveryAntiCycle::ROOT
TRUTH_PATH = P2RecoveryAntiCycle::DEFAULT_TRUTH
PLAN_PATH = P2RecoveryAntiCycle::DEFAULT_PLAN

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def write_yaml(path, value)
  File.binwrite(path, YAML.dump(value))
end

def bind_plan!(truth, bytes)
  truth.fetch("p2_recovery_control").fetch("plan")["byte_length"] = bytes.bytesize
  truth.fetch("p2_recovery_control").fetch("plan")["sha256"] = Digest::SHA256.hexdigest(bytes)
end

def expect_pass!(truth_path, plan_path)
  P2RecoveryAntiCycle.validate!(truth_path: truth_path, plan_path: plan_path, repo_root: ROOT)
end

def expect_reject!(label, truth_path, plan_path, expected_fragment)
  P2RecoveryAntiCycle.validate!(truth_path: truth_path, plan_path: plan_path, repo_root: ROOT)
  raise "#{label} was falsely accepted"
rescue P2RecoveryAntiCycle::ValidationError, KeyError, Psych::Exception => error
  unless error.message.include?(expected_fragment)
    raise "#{label} rejected for wrong reason: #{error.message.inspect}"
  end
end

truth = YAML.safe_load(File.binread(TRUTH_PATH), permitted_classes: [], permitted_symbols: [], aliases: false)
plan = YAML.safe_load(File.binread(PLAN_PATH), permitted_classes: [], permitted_symbols: [], aliases: false)
assertions = 0

expect_pass!(TRUTH_PATH, PLAN_PATH)
assertions += 1

Dir.mktmpdir("p2-recovery-tests-", ROOT) do |root|
  run_plan_case = lambda do |label, fragment, &mutation|
    candidate_plan = deep_copy(plan)
    mutation.call(candidate_plan)
    plan_path = File.join(root, "#{label}-plan.yaml")
    truth_path = File.join(root, "#{label}-truth.yaml")
    write_yaml(plan_path, candidate_plan)
    candidate_truth = deep_copy(truth)
    bind_plan!(candidate_truth, File.binread(plan_path))
    write_yaml(truth_path, candidate_truth)
    expect_reject!(label, truth_path, plan_path, fragment)
    assertions += 1
  end

  run_truth_case = lambda do |label, fragment, &mutation|
    candidate_truth = deep_copy(truth)
    mutation.call(candidate_truth)
    truth_path = File.join(root, "#{label}-truth.yaml")
    write_yaml(truth_path, candidate_truth)
    expect_reject!(label, truth_path, PLAN_PATH, fragment)
    assertions += 1
  end

  run_plan_case.call("gate-fraction", "strict progress is not binary") do |candidate|
    candidate.dig("progress_model", "strict_gate")["current_percent"] = 25
  end
  run_plan_case.call("governance-credit", "mechanical anti-cycle controls drift") do |candidate|
    candidate.dig("mechanical_controls")["governance_progress_credit"] = 1
  end
  run_plan_case.call("terminal-credit", "mechanical anti-cycle controls drift") do |candidate|
    candidate.dig("mechanical_controls")["task_non_pass_progress_credit"] = 1
  end
  run_plan_case.call("candidate-loop", "mechanical anti-cycle controls drift") do |candidate|
    candidate.dig("mechanical_controls")["max_candidate_generations_per_task"] = 3
  end
  run_plan_case.call("repair-loop", "mechanical anti-cycle controls drift") do |candidate|
    candidate.dig("mechanical_controls")["max_same_task_repairs"] = 2
  end
  run_plan_case.call("review-loop", "mechanical anti-cycle controls drift") do |candidate|
    candidate.dig("mechanical_controls")["max_review_cycles"] = 3
  end
  run_plan_case.call("missing-root-cause", "root cause set drift") do |candidate|
    candidate.fetch("root_causes").pop
  end
  run_plan_case.call("milestone-drift", "delivery milestone values drift") do |candidate|
    candidate.dig("progress_model", "delivery_milestones", 0)["percent"] = 20
  end
  run_plan_case.call("preauthorized-task", "may not preauthorize a Task ID") do |candidate|
    candidate.dig("recommended_recovery_sequence", "tasks", 0)["task_id"] = "AIOS-P2-068"
  end
  run_plan_case.call("formal-mutation", "mechanical anti-cycle controls drift") do |candidate|
    candidate.dig("mechanical_controls")["formal_task_forbids_product_dataset_or_metric_mutation"] = false
  end
  run_plan_case.call("product-without-diff", "mechanical anti-cycle controls drift") do |candidate|
    candidate.dig("mechanical_controls")["product_task_requires_nonempty_product_diff"] = false
  end
  run_plan_case.call("invented-envelope", "correction expanded authority") do |candidate|
    candidate.dig("authority_boundary")["expands_phase_envelope"] = true
  end
  run_plan_case.call("diff-fact-drift", "governance diff facts drift") do |candidate|
    candidate.dig("drift_diagnosis", "exact_diff_since_p2_entry", "governance")["changed_files"] = 38
  end

  run_truth_case.call("goal-terminal", "Long-term Goal is not active") do |candidate|
    candidate.fetch("goal")["control_plane_status_observed"] = "COMPLETE"
  end
  run_truth_case.call("active-task-injected", "may not activate a Task") do |candidate|
    candidate.fetch("active_work")["current_task"] = "AIOS-P2-068"
  end
  run_truth_case.call("false-progress", "created false P2 progress") do |candidate|
    candidate.fetch("p2_recovery_control")["current_delivery_percent"] = 25
  end
  run_truth_case.call("envelope-capacity-injected", "envelope drift") do |candidate|
    candidate.dig("phase_execution_envelope", "remaining")["engineering_tasks"] = 1
  end
  run_truth_case.call("founder-hold-bypassed", "current route is not the reserved hold") do |candidate|
    candidate.fetch("current_phase_route")["next_eligible_action"] = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
  end
end

puts "P2_RECOVERY_ANTI_CYCLE_TESTS: PASS assertions=#{assertions}"

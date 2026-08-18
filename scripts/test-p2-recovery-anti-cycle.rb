#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "tmpdir"
require "yaml"
require_relative "validate-p2-recovery-anti-cycle"

ROOT = P2RecoveryAntiCycle::ROOT
TRUTH_PATH = P2RecoveryAntiCycle::DEFAULT_TRUTH
PLAN_PATH = P2RecoveryAntiCycle::DEFAULT_PLAN
RULES_PATH = P2RecoveryAntiCycle::DEFAULT_RULES

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

  run_rules_case = lambda do |label, fragment, before, after|
    candidate_rules = File.binread(RULES_PATH).sub(before, after)
    raise "#{label} did not mutate rules" if candidate_rules == File.binread(RULES_PATH)
    P2RecoveryAntiCycle.validate_source_guardrails_bytes!(candidate_rules)
    raise "#{label} was falsely accepted"
  rescue P2RecoveryAntiCycle::ValidationError => error
    unless error.message.include?(fragment)
      raise "#{label} rejected for wrong reason: #{error.message.inspect}"
    end
  ensure
    assertions += 1
  end

  run_plan_case.call("research-exit-fraction", "P2 split progress model drift") do |candidate|
    candidate.dig("progress_model", "revised_research_exit")["percent"] = 75
  end
  run_plan_case.call("capability-retroactive-pass", "P2 original capability truth drift") do |candidate|
    candidate.fetch("original_capability_truth")["status"] = "ACCEPTED"
  end
  run_plan_case.call("implementation-freeze-disabled", "P2 research non-pass anti-cycle closure drift") do |candidate|
    candidate.fetch("anti_cycle_closure")["implementation_freeze"] = "OPEN"
  end
  run_plan_case.call("p2-successor-enabled", "P2 research non-pass anti-cycle closure drift") do |candidate|
    candidate.fetch("anti_cycle_closure")["additional_p2_task_allowed"] = true
  end
  run_plan_case.call("held-read-enabled", "P2 research non-pass anti-cycle closure drift") do |candidate|
    candidate.fetch("anti_cycle_closure")["held_read_allowed"] = true
  end
  run_plan_case.call("governance-credit", "P2 research non-pass anti-cycle closure drift") do |candidate|
    candidate.fetch("anti_cycle_closure")["governance_progress_credit"] = 1
  end
  run_plan_case.call("invented-envelope", "P2 research non-pass authority boundary drift") do |candidate|
    candidate.dig("authority_boundary")["expands_phase_envelope"] = true
  end
  run_plan_case.call("remaining-capacity-reopened", "P2 closed envelope drift") do |candidate|
    candidate.fetch("phase_envelope")["remaining_capacity_usable"] = true
  end
  run_plan_case.call("mechanical-active-task", "P2 research non-pass mechanical controls drift") do |candidate|
    candidate.fetch("mechanical_controls")["current_task"] = "AIOS-P2-081"
  end

  run_rules_case.call(
    "jdk17-gate-disabled",
    "P2 source selection guardrails drift",
    "base_and_fix_jdk17_probe_required: true",
    "base_and_fix_jdk17_probe_required: false"
  )
  run_rules_case.call(
    "maven-offline-disabled",
    "P2 source runtime guardrails drift",
    "build_subprocess_network_mode: FORCE_OFFLINE_BEFORE_SPAWN",
    "build_subprocess_network_mode: FILE_MIRROR_ASSUMED_OFFLINE"
  )
  run_rules_case.call(
    "build-network-sandbox-disabled",
    "P2 source runtime guardrails drift",
    "build_process_network_sandbox: MACOS_SANDBOX_EXEC_DENY_NETWORK_REQUIRED",
    "build_process_network_sandbox: NONE"
  )
  run_rules_case.call(
    "maven-global-settings-unbound",
    "P2 source runtime guardrails drift",
    "tool_install_user_and_explicit_config_preflight_required: true",
    "tool_install_user_and_explicit_config_preflight_required: false"
  )
  run_rules_case.call(
    "file-repository-self-attested-offline",
    "P2 source runtime guardrails drift",
    "file_repository_or_closed_env_alone_proves_offline: false",
    "file_repository_or_closed_env_alone_proves_offline: true"
  )
  run_rules_case.call(
    "dependency-custody-bypassed",
    "P2 source runtime guardrails drift",
    "dependency_bytes_provenance: CONTROLLED_EXACT_CURL_CUSTODY_ONLY",
    "dependency_bytes_provenance: EXISTING_LOCAL_CACHE_ALLOWED"
  )

  run_rules_case.call(
    "authorization-chain-enabled",
    "P2 source delegation guardrails drift",
    "numbered_single_route_reauthorization_chain_allowed: false",
    "numbered_single_route_reauthorization_chain_allowed: true"
  )
  run_rules_case.call(
    "ordinary-route-escalated",
    "P2 source delegation guardrails drift",
    "ordinary_route_non_pass_founder_trigger: false",
    "ordinary_route_non_pass_founder_trigger: true"
  )
  run_rules_case.call(
    "self-report-receipts-enabled",
    "P2 source selection guardrails drift",
    "self_report_only_receipts_allowed: false",
    "self_report_only_receipts_allowed: true"
  )
  run_rules_case.call(
    "terminal-capability-reuse-enabled",
    "P2 source delegation guardrails drift",
    "terminal_single_use_capability_reuse_allowed: false",
    "terminal_single_use_capability_reuse_allowed: true"
  )
  run_rules_case.call(
    "route-nonpass-default-founder",
    "P2 source delegation guardrails drift",
    "default_after_route_non_pass: MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK",
    "default_after_route_non_pass: FOUNDER_RESERVED_DECISION"
  )
  copied_rules = File.join(root, "AGENTS-copy.md")
  File.binwrite(copied_rules, File.binread(RULES_PATH))
  begin
    P2RecoveryAntiCycle.validate_source_guardrails!(copied_rules, ROOT)
    raise "noncanonical rules copy was falsely accepted"
  rescue P2RecoveryAntiCycle::ValidationError => error
    raise unless error.message.include?("must use canonical AGENTS.md")
    assertions += 1
  end

  run_truth_case.call("goal-terminal", "Truth Long-term Goal drift") do |candidate|
    candidate.fetch("goal")["control_plane_status_observed"] = "COMPLETE"
  end
  run_truth_case.call("terminal-active-task-injected", "Truth active Task Phase drift after P2 closure") do |candidate|
    candidate.fetch("active_work")["current_task"] = "AIOS-P2-069_CLEAN_ROOM_RECOVERY_BENCHMARK_FOUNDATION"
  end
  run_truth_case.call("false-progress", "Truth P2 recovery control drift") do |candidate|
    candidate.fetch("p2_recovery_control")["current_delivery_percent"] = 50
  end
  run_truth_case.call("terminal-task-creation-reopened", "Truth P2 recovery control drift") do |candidate|
    candidate.fetch("p2_recovery_control")["task_creation_allowed"] = true
  end
  run_truth_case.call("envelope-capacity-injected", "Truth P2 closed envelope drift") do |candidate|
    candidate.dig("historical_p2_phase_execution_envelope", "remaining")["engineering_tasks"] = 3
  end
end

puts "P2_RECOVERY_ANTI_CYCLE_TESTS: PASS assertions=#{assertions}"

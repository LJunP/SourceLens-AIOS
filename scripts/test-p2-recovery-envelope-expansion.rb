#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "validate-current-task-authority"
require_relative "validate-p2-recovery-anti-cycle"

module P2RecoveryEnvelopeExpansionTests
  ROOT = File.expand_path("..", __dir__)
  DECISION_PATH = "docs/aios/decisions/P2_VALUE_FIRST_RECOVERY_ENVELOPE_EXPANSION_DECISION_V1.json"

  module_function

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def decision_bytes(value)
    CurrentTaskAuthority.canonical_json(value)
  end

  def claims(value)
    CurrentTaskAuthority.founder_phase_route_decision_claims(
      decision_bytes(value),
      decision_path: DECISION_PATH,
      root: ROOT
    )
  end

  def assert(condition, message)
    raise message unless condition
  end

  def reject_case(name, original)
    mutated = deep_copy(original)
    yield mutated
    begin
      claims(mutated)
    rescue AuthorityValidationError, DuplicateJsonKeyError, JSON::ParserError
      return 1
    end
    raise "#{name} was false-accepted"
  end

  def run!
    original_bytes = File.binread(File.join(ROOT, DECISION_PATH))
    original = JSON.parse(original_bytes)
    parsed = CurrentTaskAuthority.founder_phase_route_decision_claims(
      original_bytes,
      decision_path: DECISION_PATH,
      root: ROOT
    )
    assert(parsed["structured_decision_version"] == "1.4", "positive decision version drift")
    assert(parsed["task_ids"] == [] && parsed["capacity_slots"].length == 3, "positive capacity projection drift")
    assertions = 3

    assertions += reject_case("token route bijection drift", original) do |value|
      value["authorization_token"] = "AUTHORIZE_P2_VALUE_FIRST_RECOVERY_ENVELOPE_EXPANSION_V2"
    end
    assertions += reject_case("route token bijection drift", original) do |value|
      value["route_id"] = "P2_VALUE_FIRST_RECOVERY_ENVELOPE_EXPANSION_ROUTE_V2"
    end
    assertions += reject_case("activation parent drift", original) do |value|
      value["activation_parent"]["commit"] = "0" * 40
    end
    assertions += reject_case("recovery plan identity drift", original) do |value|
      value["recovery_plan_identity"]["sha256"] = "0" * 64
    end
    assertions += reject_case("prior ledger count drift", original) do |value|
      value["prior_consumed_envelope"]["task_ledger_entry_count"] = 11
    end
    assertions += reject_case("prior ledger hash drift", original) do |value|
      value["prior_consumed_envelope"]["task_ledger_canonical_sha256"] = "0" * 64
    end
    assertions += reject_case("prior consumed budget drift", original) do |value|
      value["prior_consumed_envelope"]["consumed"]["engineering_hours"] = 335
    end
    assertions += reject_case("capacity slot Task preallocation", original) do |value|
      value["capacity_slots"][0]["task_id"] = "AIOS-P2-068"
    end
    assertions += reject_case("capacity slot budget drift", original) do |value|
      value["capacity_slots"][1]["engineering_hours"] = 33
    end
    assertions += reject_case("capacity slot order drift", original) do |value|
      value["capacity_slots"].reverse!
    end
    assertions += reject_case("milestone unlock drift", original) do |value|
      value["capacity_slots"][2]["unlock_requirement"] = "P2_RECOVERY_BASELINE_ACCEPTED"
    end
    assertions += reject_case("automatic successor injection", original) do |value|
      value["automatic_entries"] = [{ "task_id" => "AIOS-P2-068" }]
    end
    assertions += reject_case("external effect expansion", original) do |value|
      value["external_effects"]["network"] = true
    end
    assertions += reject_case("cumulative envelope drift", original) do |value|
      value["envelope"]["max_engineering_hours"] = 433
    end

    P2RecoveryAntiCycle.validate!(repo_root: ROOT)
    assertions += 1
    puts "P2_RECOVERY_ENVELOPE_EXPANSION_TESTS: PASS assertions=#{assertions}"
  end
end

P2RecoveryEnvelopeExpansionTests.run! if $PROGRAM_NAME == __FILE__

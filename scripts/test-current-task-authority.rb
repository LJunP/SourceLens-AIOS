#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "time"
require "yaml"
require_relative "validate-current-task-authority"

VALIDATOR = File.expand_path("validate-current-task-authority.rb", __dir__)
SAFETY_VALIDATOR = File.expand_path("check-p1-safety-boundary.sh", __dir__)
SOURCE_REPO = File.expand_path("..", __dir__)
TRUTH_RELATIVE = "docs/aios/truth/project_state.yaml"

class TestFailure < StandardError; end

class CurrentTaskAuthorityTest
  def initialize
    @passes = 0
  end

  def assert(condition, message)
    raise TestFailure, message unless condition
  end

  def shell(root, *argv)
    stdout, stderr, status = Open3.capture3(*argv, chdir: root)
    raise TestFailure, "command failed: #{argv.join(' ')}\n#{stdout}#{stderr}" unless status.success?

    stdout
  end

  def yaml(path)
    YAML.safe_load(File.binread(path), permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def run_validator(repo)
    Open3.capture3(RbConfig.ruby, VALIDATOR, chdir: repo)
  end

  def run_safety(repo, truth_path)
    Open3.capture3("bash", SAFETY_VALIDATOR, "--check-current-p1-route", truth_path, chdir: repo)
  end

  def pass(label)
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_category(label, expected)
    yield
    raise TestFailure, "#{label}: expected #{expected}, got PASS"
  rescue AuthorityValidationError => e
    assert(e.category == expected, "#{label}: expected #{expected}, got #{e.category}: #{e.message}")
    pass("#{label} category=#{expected}")
  end

  def accounting(truth, claims, inherited_claims, packet_identity, now)
    CurrentTaskAuthority.validate_v2_accounting(
      SOURCE_REPO, truth, truth["current_phase_route"], claims, inherited_claims, packet_identity, now
    )
  end

  def run
    truth_path = File.join(SOURCE_REPO, TRUTH_RELATIVE)
    truth = yaml(truth_path)
    route = truth.fetch("current_phase_route")
    assert(route.dig("authority_kernel", "schema_version") == "2.0", "source Truth is not schema v2")
    fixed_now = Time.iso8601("2026-07-22T00:00:00Z")

    validated_route, claims, inherited_claims, packet_identity =
      CurrentTaskAuthority.validate_v2_packet(SOURCE_REPO, truth)
    assert(validated_route.equal?(route), "v2 packet validation returned another route")
    assert(claims["route_id"] == route["route_id"], "packet route identity mismatch")
    assert(claims["task_id"] == route.dig("accounting", "transitions", 0, "task_id"),
           "packet Task identity mismatch")
    assert(inherited_claims["external_effects"] == CurrentTaskAuthority::FALSE_EXTERNAL_EFFECTS,
           "inherited packet external effects drifted")
    pass("exact direct and inherited packet claims")

    open, bindings, = accounting(truth, claims, inherited_claims, packet_identity, fixed_now)
    assert(open && open["task_slot"] == 1, "v2 accounting did not derive the unique open Task")
    CurrentTaskAuthority.validate_v2_active_projection(truth, route, open, bindings, packet_identity)
    pass("v2 ledger bindings and active_work derivation")

    transition = route.dig("accounting", "transitions", 0)
    contract = yaml(File.join(SOURCE_REPO, transition.dig("contract", "path")))
    payload_sha = CurrentTaskAuthority.canonical_digest(contract.fetch("descriptor_payload"))
    assert(payload_sha == contract["descriptor_payload_sha256"], "descriptor payload digest mismatch")
    digest_input = {
      "descriptor_payload_sha256" => payload_sha,
      "contract" => transition["contract"],
      "authority" => transition["authority"],
      "write_allowlist" => transition["write_allowlist"]
    }
    assert(CurrentTaskAuthority.canonical_json(digest_input).bytesize == 770,
           "final descriptor canonical bytes length drifted")
    assert(CurrentTaskAuthority.canonical_digest(digest_input) == transition["descriptor_digest"],
           "final descriptor digest mismatch")
    pass("descriptor payload and exact identity digest")

    mutated = deep_copy(truth)
    mutated["current_phase_route"]["route_id"] = "P1_SYNTHETIC_ROUTE_DRIFT"
    expect_category("packet/Truth route drift", "ROUTE_IDENTITY") do
      CurrentTaskAuthority.validate_v2_packet(SOURCE_REPO, mutated)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "envelope", "external_effects")["network"] = true
    expect_category("external effect expansion", "EXTERNAL_EFFECT") do
      CurrentTaskAuthority.validate_v2_envelope(mutated["current_phase_route"], claims, fixed_now)
    end

    CurrentTaskAuthority.validate_cumulative_hours_v2(64, 64)
    pass("cumulative scheduled hours exact boundary 64")
    expect_category("cumulative scheduled hours 65", "BUDGET") do
      CurrentTaskAuthority.validate_cumulative_hours_v2(65, 64)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting")["transitions"] = []
    expect_category("ledger deletion/reset", "ACCOUNTING_SEQUENCE") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated["task_history"]["synthetic_terminal_lineage_collision"] = {
      "status" => "TERMINAL_NON_PASS",
      "execution_lineage_id" => transition["execution_lineage_id"]
    }
    expect_category("historical execution-lineage reuse", "ACCOUNTING_SEQUENCE") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "transitions", 0)["task_slot"] = 2
    expect_category("slot gap", "ACCOUNTING_SEQUENCE") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "transitions", 0)["scheduled_engineering_hours"] = 65
    expect_category("more than 64 scheduled hours", "BUDGET") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "transitions", 0)["scheduled_engineering_hours"] = 25
    expect_category("Task 1 packet cap 24", "PACKET_BINDING") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "transitions", 0)["implementation_iterations_cap"] = 3
    expect_category("implementation iteration cap 2", "BUDGET") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "transitions", 0)["final_candidates_cap"] = 2
    expect_category("one final candidate cap", "BUDGET") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    head = shell(SOURCE_REPO, "git", "rev-parse", "HEAD").strip
    head_tree = shell(SOURCE_REPO, "git", "rev-parse", "HEAD^{tree}").strip
    head_truth = YAML.safe_load(
      shell(SOURCE_REPO, "git", "show", "#{head}:#{TRUTH_RELATIVE}"),
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    mutated = deep_copy(head_truth)
    duplicate = deep_copy(mutated.dig("current_phase_route", "accounting", "transitions", 0))
    duplicate.update(
      "sequence" => mutated.dig("current_phase_route", "accounting", "transitions").length + 1,
      "task_slot" => 2,
      "task_id" => "AIOS-P1-999_SYNTHETIC_SECOND_TASK",
      "execution_lineage_id" => "SYNTHETIC_ROUTE_TASK_SLOT_2",
      "canonical_parent" => { "commit" => head, "tree" => head_tree }
    )
    mutated.dig("current_phase_route", "accounting", "transitions") << duplicate
    expect_category("predecessor-open second schedule", "ACCOUNTING_SEQUENCE") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "transitions", 0)["canonical_parent"] =
      { "commit" => head, "tree" => head_tree }
    expect_category("canonical-parent mutation", "PARENT_CHAIN") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    usage_truth = deep_copy(head_truth)
    scheduled = usage_truth.dig("current_phase_route", "accounting", "transitions", 0)
    current_usage, = accounting(usage_truth, claims, inherited_claims, packet_identity, fixed_now)
    usage_truth.dig("current_phase_route", "accounting", "transitions") << {
      "sequence" => usage_truth.dig("current_phase_route", "accounting", "transitions").length + 1,
      "transition" => "USAGE_RECORDED",
      "task_slot" => scheduled["task_slot"],
      "task_id" => scheduled["task_id"],
      "execution_lineage_id" => scheduled["execution_lineage_id"],
      "descriptor_digest" => scheduled["descriptor_digest"],
      "implementation_iterations_used" => 2,
      "final_candidates_used" => [current_usage["final_candidates_used"], 1].max,
      "final_review_rounds_used" => current_usage["final_review_rounds_used"],
      "canonical_parent" => { "commit" => head, "tree" => head_tree }
    }
    usage_open, usage_bindings, = accounting(usage_truth, claims, inherited_claims, packet_identity, fixed_now)
    assert(usage_open["implementation_iterations_used"] == 2 && usage_open["final_candidates_used"] == 1,
           "usage transition was not derived")
    pass("append-only implementation/candidate usage transition")
    usage_truth.dig("current_phase_route", "current_task")["candidate_status"] = "NOT_CREATED"
    expect_category("candidate usage must project to current_task", "ACTIVE_PROJECTION") do
      CurrentTaskAuthority.validate_v2_active_projection(
        usage_truth, usage_truth["current_phase_route"], usage_open, usage_bindings, packet_identity
      )
    end

    overuse_truth = deep_copy(usage_truth)
    overuse_truth.dig("current_phase_route", "accounting", "transitions").last["final_candidates_used"] = 2
    expect_category("more than one candidate used", "BUDGET") do
      accounting(overuse_truth, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "remaining")["scheduled_engineering_hours"] = 39
    expect_category("remaining counter decrement/reset", "BUDGET") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated.dig("current_phase_route", "accounting", "transitions", 0)["descriptor_digest"] = "0" * 64
    expect_category("descriptor digest substitution", "DESCRIPTOR_BINDING") do
      accounting(mutated, claims, inherited_claims, packet_identity, fixed_now)
    end

    mutated = deep_copy(truth)
    mutated["active_work"]["task_slot"] = 2
    expect_category("active_work not derived from open Task", "ACTIVE_PROJECTION") do
      CurrentTaskAuthority.validate_v2_active_projection(mutated, mutated["current_phase_route"], open,
                                                         bindings, packet_identity)
    end

    expired_now = Time.iso8601(claims["route_deadline_utc"]) + 1
    expect_category("untrusted wall-clock route expiry", "ROUTE_WINDOW") do
      accounting(truth, claims, inherited_claims, packet_identity, expired_now)
    end

    terminal_truth = deep_copy(head_truth)
    scheduled = terminal_truth.dig("current_phase_route", "accounting", "transitions", 0)
    terminal_truth.dig("current_phase_route", "accounting", "transitions") << {
      "sequence" => terminal_truth.dig("current_phase_route", "accounting", "transitions").length + 1,
      "transition" => "TERMINAL",
      "status" => "TERMINAL_NON_PASS",
      "task_slot" => scheduled["task_slot"],
      "task_id" => scheduled["task_id"],
      "execution_lineage_id" => scheduled["execution_lineage_id"],
      "descriptor_digest" => scheduled["descriptor_digest"],
      "canonical_parent" => { "commit" => head, "tree" => head_tree }
    }
    terminal_truth.dig("current_phase_route", "accounting")["open_task_count"] = 0
    terminal_open, terminal_bindings, = accounting(
      terminal_truth, claims, inherited_claims, packet_identity, expired_now
    )
    assert(terminal_open.nil? && terminal_bindings.key?(1), "terminal transition did not close the open Task")
    pass("terminal transition closes Task and permits post-deadline Truth sync")
    expect_category("terminal ledger requires active_work NONE", "ACTIVE_PROJECTION") do
      CurrentTaskAuthority.validate_v2_active_projection(
        terminal_truth, terminal_truth["current_phase_route"], terminal_open, terminal_bindings, packet_identity
      )
    end

    CurrentTaskAuthority.validate_legacy_v1_slot!("AIOS-P1-999_SYNTHETIC", "AIOS-P1-999_SYNTHETIC")
    pass("legacy v1 first Task / slot 1")
    expect_category("legacy v1 Task 2 rejection", "LEGACY_V1") do
      CurrentTaskAuthority.validate_legacy_v1_slot!("AIOS-P1-998_SYNTHETIC", "AIOS-P1-999_SYNTHETIC")
    end

    safety_bytes = File.binread(SAFETY_VALIDATOR)
    assert(!safety_bytes.include?("ruby -ryaml") && !safety_bytes.include?("ruby -e") &&
           safety_bytes.include?("exec ruby \"${CORE}\""), "safety entry contains a second semantic implementation")
    core_stdout, core_stderr, core_status = run_validator(SOURCE_REPO)
    safety_stdout, safety_stderr, safety_status = run_safety(SOURCE_REPO, truth_path)
    core_output = core_stdout + core_stderr
    safety_output = safety_stdout + safety_stderr
    core_category = core_output[/category=([A-Z0-9_]+)/, 1]
    safety_category = safety_output[/category=([A-Z0-9_]+)/, 1]
    assert(core_status.success? == safety_status.success?, "core and safety exit status differ")
    assert(core_category && core_category == safety_category,
           "core/safety category mismatch: #{core_output.inspect} versus #{safety_output.inspect}")
    assert(core_category != "UNEXPECTED", "core returned an unexpected exception: #{core_output}")
    pass("core/safety exact category parity category=#{core_category}")

    puts "CURRENT_TASK_AUTHORITY_TESTS: PASS assertions=#{@passes}"
  end
end

begin
  CurrentTaskAuthorityTest.new.run
  exit 0
rescue TestFailure => e
  warn "CURRENT_TASK_AUTHORITY_TESTS: NON_PASS #{e.message}"
  exit 1
rescue StandardError => e
  warn "CURRENT_TASK_AUTHORITY_TESTS: NON_PASS unexpected #{e.class}: #{e.message}"
  warn e.backtrace.first(5).join("\n")
  exit 1
end

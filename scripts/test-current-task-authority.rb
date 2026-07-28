#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "validate-current-task-authority"

VALIDATOR = File.expand_path("validate-current-task-authority.rb", __dir__)
SAFETY_VALIDATOR = File.expand_path("check-p1-safety-boundary.sh", __dir__)
SOURCE_REPO = File.expand_path("..", __dir__)
TRUTH_RELATIVE = "docs/aios/truth/project_state.yaml"
POLICY_RELATIVE = "docs/aios/FOUNDER_DELEGATION_POLICY.md"
P1_READY_GOLDEN_COMMIT = "03542c278ad57b030cb0798483de8c3c19341952"
STRUCTURED_DECISION_PATH = File.expand_path(
  "../.sourcelens-audit/p2-structured-decision-authority-20260727/decision/FOUNDER_P2_ROUTE_DECISION.json",
  SOURCE_REPO
)
STRUCTURED_DECISION_SHA256 = "27838e20766d84ccbbae934284331559bbee71224291b9f8ca7277fa0ea3ee5f"
STRUCTURED_DECISION_BYTE_LENGTH = 2240
STRUCTURED_DECISION_SCHEMA = File.join(SOURCE_REPO, "schemas/founder-phase-route-decision.schema.json")

class TestFailure < StandardError; end

class CurrentTaskAuthorityTest
  def initialize
    @owned = {}
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

  def register_owned(path)
    stat = File.lstat(path)
    @owned[path] = [stat.dev, stat.ino]
    path
  end

  def assert_owned(path)
    expected = @owned[path]
    raise TestFailure, "unowned fixture path: #{path}" unless expected
    stat = File.lstat(path)
    raise TestFailure, "fixture became a symlink: #{path}" if stat.symlink?
    raise TestFailure, "fixture identity changed: #{path}" unless [stat.dev, stat.ino] == expected
    stat
  end

  def create_exclusive(path, bytes)
    FileUtils.mkdir_p(File.dirname(path))
    flags = File::WRONLY | File::CREAT | File::EXCL
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    File.open(path, flags, 0o600) do |file|
      file.write(bytes)
      file.flush
      file.fsync
    end
    register_owned(path)
  end

  def rewrite_owned(path, bytes)
    expected = assert_owned(path)
    flags = File::WRONLY | File::TRUNC
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino] == [expected.dev, expected.ino], "fixture changed while opening")
      file.write(bytes)
      file.flush
      file.fsync
    end
  end

  def tamper_owned_byte(path)
    expected = assert_owned(path)
    flags = File::RDWR
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    original = nil
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino] == [expected.dev, expected.ino], "fixture changed while opening")
      original = file.read(1)
      assert(original && !original.empty?, "cannot tamper empty fixture")
      file.seek(0, IO::SEEK_SET)
      file.write((original.getbyte(0) ^ 1).chr)
      file.flush
      file.fsync
    end
    original
  end

  def restore_owned_byte(path, original)
    expected = assert_owned(path)
    flags = File::RDWR
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino] == [expected.dev, expected.ino], "fixture changed while restoring")
      file.seek(0, IO::SEEK_SET)
      file.write(original)
      file.flush
      file.fsync
    end
  end

  def verified_source_copy(source, destination, sha, length)
    stat = File.lstat(source)
    assert(stat.file? && !stat.symlink?, "source identity fixture is not a regular file")
    bytes = File.binread(source)
    assert(bytes.bytesize == length, "source identity byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == sha, "source identity SHA mismatch")
    create_exclusive(destination, bytes)
    destination
  end

  def commit(repo, message)
    shell(repo, "git", "add", "--all")
    shell(repo, "git", "commit", "-m", message)
    shell(repo, "git", "status", "--porcelain=v1").tap do |status|
      assert(status.empty?, "fixture repository is not clean after commit")
    end
  end

  def run_validator(repo)
    Open3.capture3(RbConfig.ruby, VALIDATOR, chdir: repo)
  end

  def run_safety(repo, truth_path)
    Open3.capture3("bash", SAFETY_VALIDATOR, "--check-current-p1-route", truth_path, chdir: repo)
  end

  def expect_pass(repo, label)
    stdout, stderr, status = run_validator(repo)
    assert(status.success?, "#{label}: expected PASS\n#{stdout}#{stderr}")
    assert(stdout.include?("CURRENT_TASK_AUTHORITY: PASS"), "#{label}: PASS marker missing")
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_pass_state(repo, label, expected_state)
    stdout, stderr, status = run_validator(repo)
    assert(status.success?, "#{label}: expected PASS\n#{stdout}#{stderr}")
    marker = "CURRENT_TASK_AUTHORITY: PASS state=#{expected_state}"
    assert(stdout.include?(marker), "#{label}: expected exact state marker #{marker.inspect}")
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_nonpass(repo, label, pattern)
    stdout, stderr, status = run_validator(repo)
    output = stdout + stderr
    assert(!status.success?, "#{label}: expected NON_PASS")
    assert(output.include?("CURRENT_TASK_AUTHORITY: NON_PASS"), "#{label}: NON_PASS marker missing")
    assert(pattern.match?(output), "#{label}: expected #{pattern.inspect}, got #{output.inspect}")
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_safety_pass(repo, truth_path, label)
    stdout, stderr, status = run_safety(repo, truth_path)
    assert(status.success?, "#{label}: expected safety PASS\n#{stdout}#{stderr}")
    assert(stdout.include?("Current Phase route safety validation passed."), "#{label}: safety PASS marker missing")
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_safety_nonpass(repo, truth_path, label, pattern)
    stdout, stderr, status = run_safety(repo, truth_path)
    output = stdout + stderr
    assert(!status.success?, "#{label}: expected safety NON_PASS")
    assert(pattern.match?(output), "#{label}: expected #{pattern.inspect}, got #{output.inspect}")
    @passes += 1
    puts "PASS #{label}"
  end

  def yaml(path)
    YAML.safe_load(File.binread(path), permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def dump_owned_yaml(path, value)
    rewrite_owned(path, YAML.dump(value))
  end

  def ready_active_work
    {
      "current_task" => "NONE",
      "current_task_status" => "NONE",
      "current_task_contract" => { "path" => nil, "sha256" => nil, "byte_length" => nil },
      "current_task_contract_sha256" => nil,
      "current_execution_authorization" => nil,
      "current_execution_authorization_sha256" => nil,
      "authority_record" => { "path" => nil, "sha256" => nil, "byte_length" => nil },
      "execution_nonce" => nil,
      "execution_nonce_status" => "NOT_APPLICABLE_TASK_NONE",
      "authorization_id" => nil,
      "activation_parent_commit" => nil,
      "activation_parent_tree" => nil,
      "task_resource_state" => "NOT_CREATED_ROUTE_READY",
      "task_branch" => nil,
      "task_worktree" => nil,
      "execution_evidence_root" => nil,
      "allowlisted_paths" => [],
      "budget" => {
        "engineering_hours" => nil,
        "calendar_days" => nil,
        "implementation_iterations" => nil,
        "candidates" => nil
      },
      "roles" => { "owner" => nil, "worker" => nil, "independent_reviewers" => [] },
      "external_effects" => false_effects,
      "offsite_target" => nil,
      "founder_reserved_authorization" => nil,
      "founder_reserved_authorization_sha256" => nil,
      "founder_decision_required" => false,
      "escalation_reason" => nil,
      "user_action_required" => "NONE",
      "next_eligible_action" => "MASTER_ACTIVATE_FIRST_TASK"
    }
  end

  def false_effects
    {
      "network" => false,
      "provider" => false,
      "secret" => false,
      "remote" => false,
      "production" => false,
      "public" => false
    }
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def recursively_sorted(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, recursively_sorted(value.fetch(key))] }
    when Array
      value.map { |item| recursively_sorted(item) }
    else
      value
    end
  end

  def canonical_json(value)
    JSON.generate(recursively_sorted(value)) + "\n"
  end

  def set_path(value, path, replacement)
    cursor = value
    path[0...-1].each { |key| cursor = cursor.fetch(key) }
    cursor[path.last] = replacement
    value
  end

  def expect_decision_pass(bytes, label)
    claims = CurrentTaskAuthority.packet_claims(bytes, STRUCTURED_DECISION_PATH, root: SOURCE_REPO)
    assert(claims["structured_decision"] == true, "#{label}: structured decision marker missing")
    @passes += 1
    puts "PASS #{label}"
    claims
  rescue AuthorityValidationError => e
    raise TestFailure, "#{label}: expected PASS, got #{e.message}"
  end

  def expect_decision_nonpass(bytes, label, pattern, path: STRUCTURED_DECISION_PATH)
    CurrentTaskAuthority.packet_claims(bytes, path, root: SOURCE_REPO)
    raise TestFailure, "#{label}: expected NON_PASS"
  rescue AuthorityValidationError => e
    assert(pattern.match?(e.message), "#{label}: expected #{pattern.inspect}, got #{e.message.inspect}")
    @passes += 1
    puts "PASS #{label}"
  end

  def structured_v4_profile(decision, task_id)
    {
      "schema_version" => "4.0",
      "profile_id" => "STRUCTURED_V1_1_TASK_SCOPED_LOOPBACK_PROVIDER",
      "decision_basis" =>
        "FOUNDER_PACKET_SHA256:#{decision.dig('source_founder_packet_identity', 'sha256')}",
      "route_id" => decision.fetch("route_id"),
      "task_id" => task_id,
      "transport" => {
        "scheme" => "http",
        "host" => "127.0.0.1",
        "port" => 8787,
        "completion_path" => "/v1/chat/completions",
        "api_format" => "OPENAI_COMPATIBLE_CHAT_COMPLETIONS",
        "method" => "POST",
        "follow_redirects" => false,
        "use_proxy" => false,
        "dns_resolution" => false,
        "fallback_endpoint_allowed" => false,
        "expected_peer_address" => "127.0.0.1",
        "expected_peer_port" => 8787
      },
      "model" => {
        "requested_model" => "gpt-5.6-luna",
        "substitution_allowed" => false,
        "provider_provenance" =>
          "FOUNDER_ATTESTED_OPENAI_COMPATIBLE_LOCAL_GATEWAY_MODEL_NOT_INDEPENDENTLY_VERIFIED"
      },
      "secret" => {
        "source" => "FOUNDER_OPERATOR_NO_ECHO_TTY",
        "entry_sessions" => 1,
        "persist" => false,
        "prohibited_sinks" => %w[
          ARGV ENVIRONMENT SHELL_HISTORY REPOSITORY TEMPORARY_PLAINTEXT_FILE
          EVIDENCE LOG TRACE PROMPT REVIEW VAULT
        ]
      },
      "call_limits" => {
        "diagnostic_requests_max" => 1,
        "formal_requests_exact" => 36,
        "provider_requests_max" => 37,
        "automatic_retry_max" => 0
      },
      "monetary_limits" => {
        "currency" => "USD",
        "max_spend" => 25,
        "unavailable_metering_status" => "UNKNOWN_GATEWAY_METERING_UNAVAILABLE"
      },
      "external_effects" => {
        "network" => true,
        "provider" => true,
        "secret" => true,
        "remote" => false,
        "production" => false,
        "public" => false
      },
      "claim_limits" => {
        "direct_openai_provenance_proven" => false,
        "gateway_upstream_behavior" => "UNKNOWN",
        "upstream_request_count" => "UNKNOWN",
        "actual_monetary_cost" => "UNKNOWN_UNLESS_TRUSTWORTHY_GATEWAY_EVIDENCE_EXISTS",
        "hostile_principal_isolation" => false,
        "production" => false,
        "remote" => false,
        "public" => false,
        "p2_entry" => false
      }
    }
  end

  def bind_structured_v1_1_source_packet(decision, sandbox)
    provider_profile = decision.fetch("ordered_tasks").fetch(1).fetch("founder_reserved_profile")
    transport = provider_profile.fetch("transport")
    calls = provider_profile.fetch("call_limits")
    money = provider_profile.fetch("monetary_limits")
    endpoint = "#{transport.fetch('scheme')}://#{transport.fetch('host')}:#{transport.fetch('port')}" \
               "#{transport.fetch('completion_path')}"
    packet_bytes = <<~PACKET
      Founder structured v1.1 test packet

      authorization_token=#{decision.fetch("authorization_token")}

      6. Task 2强制语义

      - endpoint:
        #{endpoint}
      - model:
        #{provider_profile.dig("model", "requested_model")}
      - diagnostic Provider requests maximum: #{calls.fetch("diagnostic_requests_max")}
      - formal Provider requests: exactly #{calls.fetch("formal_requests_exact")}
      - total Provider requests maximum: #{calls.fetch("provider_requests_max")}
      - automatic retries: #{calls.fetch("automatic_retry_max")}
      - monetary exposure maximum: #{money.fetch("currency")} #{money.fetch("max_spend")}
      - Secret仅允许operator-owned no-echo读取一次；
    PACKET
    @structured_v1_1_source_sequence ||= 0
    @structured_v1_1_source_sequence += 1
    packet_path = File.join(
      sandbox,
      "structured-v1-1-source-packet-#{@structured_v1_1_source_sequence}.md"
    )
    create_exclusive(packet_path, packet_bytes)
    packet_sha = Digest::SHA256.hexdigest(packet_bytes)
    decision["source_founder_packet_identity"] = {
      "authorization_token" => decision.fetch("authorization_token"),
      "byte_length" => packet_bytes.bytesize,
      "path" => packet_path,
      "sha256" => packet_sha
    }
    provider_profile["decision_basis"] = "FOUNDER_PACKET_SHA256:#{packet_sha}"
    decision
  end

  def structured_v1_1_decision(sandbox)
    decision = JSON.parse(File.binread(STRUCTURED_DECISION_PATH))
    decision["schema_version"] = "1.1"
    decision["ordered_tasks"].each do |task|
      task["external_effects"] = false_effects
      task["founder_reserved_profile"] = nil
    end
    decision["ordered_tasks"][1]["external_effects"] = {
      "network" => true,
      "production" => false,
      "provider" => true,
      "public" => false,
      "remote" => false,
      "secret" => true
    }
    decision["ordered_tasks"][1]["founder_reserved_profile"] =
      structured_v4_profile(decision, decision["ordered_tasks"][1]["task_id"])
    third = {
      "calendar_days" => 2,
      "engineering_hours" => 8,
      "external_effects" => false_effects,
      "founder_reserved_profile" => nil,
      "max_candidates" => 1,
      "max_implementation_iterations" => 3,
      "max_same_task_repairs" => 2,
      "task_id" => "AIOS-P2-009_REPORT_BOUND_PREREGISTRATION",
      "task_slot" => 3
    }
    decision["ordered_tasks"] << third
    decision["envelope"]["max_engineering_tasks"] = 3
    decision["envelope"]["max_engineering_hours"] += third["engineering_hours"]
    decision["envelope"]["max_calendar_days"] += third["calendar_days"]
    decision["envelope"]["max_same_task_repairs_per_task"] = 2
    decision["external_effects"] = {
      "network" => true,
      "production" => false,
      "provider" => true,
      "public" => false,
      "remote" => false,
      "secret" => true
    }
    decision["automatic_entries"] = [
      deep_copy(decision.fetch("automatic_entry")),
      {
        "after_task_id" => decision["ordered_tasks"][1]["task_id"],
        "next_task_id" => third["task_id"],
        "requires_task_gate_pass" => true
      }
    ]
    bind_structured_v1_1_source_packet(decision, sandbox)
  end

  def structured_decision_unit_tests(sandbox)
    stat = File.lstat(STRUCTURED_DECISION_PATH)
    assert(stat.file? && !stat.symlink?, "canonical structured decision is not a regular file")
    bytes = File.binread(STRUCTURED_DECISION_PATH)
    assert(bytes.bytesize == STRUCTURED_DECISION_BYTE_LENGTH,
           "canonical structured decision byte length drifted")
    assert(Digest::SHA256.hexdigest(bytes) == STRUCTURED_DECISION_SHA256,
           "canonical structured decision SHA-256 drifted")
    schema = JSON.parse(File.binread(STRUCTURED_DECISION_SCHEMA))
    decision = JSON.parse(bytes)
    assert(schema["additionalProperties"] == false,
           "structured decision schema root must be closed")
    assert(schema.fetch("required").sort == decision.keys.sort,
           "structured decision schema root key set does not equal the canonical record")
    assert(schema.dig("properties", "ordered_tasks", "items", "additionalProperties") == false,
           "structured decision schema Task items must be closed")
    version_branch = schema.fetch("allOf").fetch(0)
    assert(version_branch.dig("if", "properties", "schema_version", "const") == "1.1",
           "structured decision schema does not discriminate v1.1")
    assert(version_branch.dig("then", "required") == ["automatic_entries"],
           "structured decision schema does not require v1.1 automatic_entries")
    v1_1_task_required = version_branch.dig(
      "then", "properties", "ordered_tasks", "items", "required"
    )
    assert(v1_1_task_required.include?("external_effects") &&
           v1_1_task_required.include?("founder_reserved_profile"),
           "structured decision schema does not require v1.1 Task effects and profile fields")
    assert(version_branch.dig("else", "not", "anyOf").is_a?(Array),
           "structured decision schema does not exclude v1.1-only fields from v1.0")
    @passes += 1
    puts "PASS structured decision JSON Schema is closed and matches the canonical root"
    claims = expect_decision_pass(bytes, "exact canonical structured Founder decision")
    assert(claims["task_ids"] == [
      "AIOS-P2-007_CANONICAL_SYMBOL_IDENTITY_AND_SCANNER_GRAPH_KERNEL",
      "AIOS-P2-008_GRAPH_CONDITIONED_CONTEXT_EMPIRICAL_BENCHMARK"
    ], "exact structured decision Task set drifted")
    expect_decision_nonpass(
      bytes,
      "structured decision path extension mismatch",
      /must use the \.json extension/,
      path: File.join(sandbox, "founder-route-decision.md")
    )

    duplicate = bytes.sub(/\A\{/, "{\"phase\":\"P2\",")
    expect_decision_nonpass(duplicate, "structured decision duplicate JSON key", /duplicate JSON key "phase"/)

    missing = deep_copy(decision)
    missing.delete("record_type")
    expect_decision_nonpass(canonical_json(missing), "structured decision missing key", /keys drifted/)

    extra = deep_copy(decision)
    extra["undeclared"] = false
    expect_decision_nonpass(canonical_json(extra), "structured decision extra key", /keys drifted/)

    reverse_root = decision.keys.reverse.to_h { |key| [key, decision.fetch(key)] }
    expect_decision_nonpass(
      JSON.generate(reverse_root) + "\n",
      "structured decision noncanonical key order",
      /recursively key-sorted canonical JSON/
    )

    [
      [%w[envelope max_engineering_hours], "48", "structured decision wrong type",
       /max_engineering_hours must be an integer/],
      [["authorization_token"], "AUTHORIZE_P2_OTHER_ROUTE_V1", "structured decision token mismatch",
       /authorization token does not match route_id/],
      [["phase"], "P3", "structured decision phase mismatch", /phase must be P1 or P2/],
      [%w[activation_parent tree], "0" * 40, "structured decision parent mismatch",
       /activation parent\.tree does not match commit/],
      [%w[goal_identity raw_byte_length], 19_432, "structured decision Goal mismatch",
       /Goal identity mismatch/],
      [%w[external_effects remote], "false", "structured decision external effect type",
       /external_effects\.remote must be boolean/],
      [%w[envelope p3_entry_authorized], true, "structured decision P3 entry expansion",
       /p3_entry_authorized must be false/],
      [%w[automatic_entry next_task_id], "AIOS-P2-999_WRONG_NEXT_TASK",
       "structured decision automatic entry mismatch", /automatic entry must bind/],
      [%w[source_founder_packet_identity authorization_token], "AUTHORIZE_P2_OTHER_ROUTE_V1",
       "structured decision source packet token mismatch", /source packet authorization token mismatch/],
      [%w[source_founder_packet_identity path], 7, "structured decision source packet path type",
       /source packet path must be a non-empty string/],
      [%w[source_founder_packet_identity byte_length], 7562,
       "structured decision source packet length mismatch", /byte length mismatch/],
      [%w[source_founder_packet_identity sha256], "0" * 64,
       "structured decision source packet hash mismatch", /SHA-256 mismatch/]
    ].each do |path, replacement, label, pattern|
      variant = set_path(deep_copy(decision), path, replacement)
      expect_decision_nonpass(canonical_json(variant), label, pattern)
    end

    empty_source = File.join(sandbox, "empty-founder-source-packet.txt")
    create_exclusive(empty_source, "")
    empty_source_decision = deep_copy(decision)
    empty_source_decision["source_founder_packet_identity"]["path"] = empty_source
    empty_source_decision["source_founder_packet_identity"]["byte_length"] = 0
    empty_source_decision["source_founder_packet_identity"]["sha256"] = Digest::SHA256.hexdigest("")
    expect_decision_nonpass(
      canonical_json(empty_source_decision),
      "structured decision rejects schema-invalid zero-length source packet",
      /source packet byte_length must be positive/
    )

    data_driven_effects = deep_copy(decision)
    data_driven_effects["external_effects"]["network"] = true
    data_driven_effects["external_effects"]["provider"] = true
    data_driven_effects["external_effects"]["secret"] = true
    effects_claims = expect_decision_pass(
      canonical_json(data_driven_effects),
      "structured decision preserves Founder-declared external effects"
    )
    assert(effects_claims["external_effects"] == data_driven_effects["external_effects"],
           "structured decision external effects were not projected from Decision data")

    zero_repairs = deep_copy(decision)
    zero_repairs["envelope"]["max_same_task_repairs_per_task"] = 0
    zero_repairs["ordered_tasks"].each do |task|
      task["max_same_task_repairs"] = 0
      task["max_implementation_iterations"] = 1
    end
    zero_claims = expect_decision_pass(
      canonical_json(zero_repairs),
      "structured decision accepts internally consistent zero-repair budget"
    )
    assert(zero_claims["max_same_task_repairs"] == 0,
           "structured decision zero-repair budget projection drifted")

    route_phase = deep_copy(decision)
    route_phase["route_id"] =
      "P1_CANONICAL_SYMBOL_IDENTITY_GRAPH_KERNEL_AND_CONTEXT_BENCHMARK_CONTINUOUS_ROUTE_V1"
    route_phase["authorization_token"] = "AUTHORIZE_#{route_phase['route_id']}"
    route_phase["source_founder_packet_identity"]["authorization_token"] = route_phase["authorization_token"]
    expect_decision_nonpass(canonical_json(route_phase), "structured decision route phase prefix",
                            /route_id phase prefix mismatch/)

    task_count = deep_copy(decision)
    task_count["ordered_tasks"].pop
    expect_decision_nonpass(canonical_json(task_count), "structured decision Task count mismatch",
                            /Task count does not equal route envelope|requires at least two/)

    duplicate_task = deep_copy(decision)
    duplicate_task["ordered_tasks"][1]["task_id"] = duplicate_task["ordered_tasks"][0]["task_id"]
    duplicate_task["automatic_entry"]["next_task_id"] = duplicate_task["ordered_tasks"][0]["task_id"]
    expect_decision_nonpass(canonical_json(duplicate_task), "structured decision duplicate Task id",
                            /Task ids must be unique/)

    reordered_tasks = deep_copy(decision)
    reordered_tasks["ordered_tasks"].reverse!
    expect_decision_nonpass(canonical_json(reordered_tasks), "structured decision Task order mismatch",
                            /Task slots must be contiguous and ordered/)

    task_budget = deep_copy(decision)
    task_budget["ordered_tasks"][0]["engineering_hours"] += 1
    expect_decision_nonpass(canonical_json(task_budget), "structured decision Task budget mismatch",
                            /engineering budgets do not equal route envelope/)

    task_specific_repairs = deep_copy(decision)
    task_specific_repairs["envelope"]["max_same_task_repairs_per_task"] = 8
    task_specific_repairs["ordered_tasks"][0]["max_same_task_repairs"] = 8
    task_specific_repairs["ordered_tasks"][0]["max_implementation_iterations"] = 9
    task_specific_repairs["ordered_tasks"][1]["max_same_task_repairs"] = 2
    task_specific_repairs["ordered_tasks"][1]["max_implementation_iterations"] = 3
    task_specific_claims = expect_decision_pass(
      canonical_json(task_specific_repairs),
      "structured decision accepts independent Task repair budgets under exact route ceiling"
    )
    assert(task_specific_claims["max_same_task_repairs"] == 8,
           "structured decision route repair ceiling projection drifted")
    assert(task_specific_claims["task_budgets"].map { |task| task["max_same_task_repairs"] } == [8, 2],
           "structured decision Task-specific repair budgets drifted")

    task_repair_over = deep_copy(decision)
    task_repair_over["ordered_tasks"][0]["max_same_task_repairs"] =
      task_repair_over["envelope"]["max_same_task_repairs_per_task"] + 1
    task_repair_over["ordered_tasks"][0]["max_implementation_iterations"] =
      task_repair_over["ordered_tasks"][0]["max_same_task_repairs"] + 1
    expect_decision_nonpass(canonical_json(task_repair_over), "structured decision Task repair exceeds ceiling",
                            /repair budget exceeds route envelope maximum/)

    loose_route_ceiling = deep_copy(decision)
    loose_route_ceiling["envelope"]["max_same_task_repairs_per_task"] += 1
    expect_decision_nonpass(canonical_json(loose_route_ceiling), "structured decision loose route repair ceiling",
                            /route repair ceiling must equal the maximum Task repair budget/)

    task_candidate = deep_copy(decision)
    task_candidate["ordered_tasks"][0]["max_candidates"] = 2
    expect_decision_nonpass(canonical_json(task_candidate), "structured decision Task candidate mismatch",
                            /candidate budget does not equal route envelope/)

    source_packet = decision.fetch("source_founder_packet_identity").fetch("path")
    source_link = File.join(sandbox, "structured-source-packet-link.txt")
    File.symlink(source_packet, source_link)
    link_variant = deep_copy(decision)
    link_variant["source_founder_packet_identity"]["path"] = source_link
    expect_decision_nonpass(canonical_json(link_variant), "structured decision source packet symlink",
                            /must not be a symlink/)

    generic = deep_copy(decision)
    generic["route_id"] = "P2_GENERIC_DATA_DRIVEN_ROUTE_V9"
    generic["authorization_token"] = "AUTHORIZE_P2_GENERIC_DATA_DRIVEN_ROUTE_V9"
    generic["source_founder_packet_identity"]["authorization_token"] = generic["authorization_token"]
    generic["ordered_tasks"][0]["task_id"] = "AIOS-P2-901_GENERIC_FIRST_TASK"
    generic["ordered_tasks"][1]["task_id"] = "AIOS-P2-902_GENERIC_SECOND_TASK"
    generic["automatic_entry"]["after_task_id"] = generic["ordered_tasks"][0]["task_id"]
    generic["automatic_entry"]["next_task_id"] = generic["ordered_tasks"][1]["task_id"]
    generic_claims = expect_decision_pass(canonical_json(generic),
                                          "structured decision route and Task semantics are data-driven")
    assert(generic_claims["first_task_id"] == "AIOS-P2-901_GENERIC_FIRST_TASK",
           "structured decision parser hard-coded the canonical fixture Task id")

    v1_1 = structured_v1_1_decision(sandbox)
    v1_1_claims = expect_decision_pass(
      canonical_json(v1_1),
      "structured decision v1.1 accepts three-Task chain with Task-specific effects"
    )
    assert(v1_1_claims["automatic_entries"] == v1_1["automatic_entries"],
           "structured decision v1.1 automatic-entry chain drifted")
    assert(v1_1_claims["task_effects"] == v1_1["ordered_tasks"].to_h { |task| [task["task_id"], task["external_effects"]] },
           "structured decision v1.1 Task effect projection drifted")
    assert(v1_1_claims["founder_reserved_profiles"] == [
      v1_1["ordered_tasks"][1]["founder_reserved_profile"]
    ], "structured decision v1.1 Provider profile projection drifted")

    missing_link = deep_copy(v1_1)
    missing_link["automatic_entries"].pop
    expect_decision_nonpass(
      canonical_json(missing_link),
      "structured decision v1.1 missing automatic-entry link",
      /automatic entry count must equal Task count minus one/
    )

    drifted_link = deep_copy(v1_1)
    drifted_link["automatic_entries"][1]["after_task_id"] =
      drifted_link["ordered_tasks"][0]["task_id"]
    expect_decision_nonpass(
      canonical_json(drifted_link),
      "structured decision v1.1 non-adjacent automatic-entry link",
      /automatic entries must bind every adjacent Task/
    )

    loose_effect_ceiling = deep_copy(v1_1)
    loose_effect_ceiling["external_effects"]["provider"] = false
    expect_decision_nonpass(
      canonical_json(loose_effect_ceiling),
      "structured decision v1.1 route effect union drift",
      /route external effects must equal the union/
    )

    missing_task_effects = deep_copy(v1_1)
    missing_task_effects["ordered_tasks"][0].delete("external_effects")
    expect_decision_nonpass(
      canonical_json(missing_task_effects),
      "structured decision v1.1 missing Task effects",
      /keys drifted/
    )

    missing_task_profile = deep_copy(v1_1)
    missing_task_profile["ordered_tasks"][0].delete("founder_reserved_profile")
    expect_decision_nonpass(
      canonical_json(missing_task_profile),
      "structured decision v1.1 missing explicit Task profile field",
      /keys drifted/
    )

    provider_without_profile = deep_copy(v1_1)
    provider_without_profile["ordered_tasks"][1]["founder_reserved_profile"] = nil
    expect_decision_nonpass(
      canonical_json(provider_without_profile),
      "structured decision v1.1 Provider Task missing exact profile",
      /requires an exact Founder-reserved profile/
    )

    offline_with_profile = deep_copy(v1_1)
    offline_with_profile["ordered_tasks"][0]["founder_reserved_profile"] =
      deep_copy(v1_1["ordered_tasks"][1]["founder_reserved_profile"])
    offline_with_profile["ordered_tasks"][0]["founder_reserved_profile"]["task_id"] =
      offline_with_profile["ordered_tasks"][0]["task_id"]
    expect_decision_nonpass(
      canonical_json(offline_with_profile),
      "structured decision v1.1 offline Task profile expansion",
      /offline Task must not carry/
    )

    request_total_drift = deep_copy(v1_1)
    request_total_drift["ordered_tasks"][1]["founder_reserved_profile"]
      .dig("call_limits")["provider_requests_max"] = 38
    expect_decision_nonpass(
      canonical_json(request_total_drift),
      "structured decision v1.1 Provider request total drift",
      /exact diagnostic plus formal request total/
    )

    source_request_ceiling_drift = deep_copy(v1_1)
    source_request_ceiling_drift["ordered_tasks"][1]["founder_reserved_profile"]
      .dig("call_limits").merge!(
        "diagnostic_requests_max" => 3,
        "formal_requests_exact" => 36,
        "provider_requests_max" => 39
      )
    expect_decision_nonpass(
      canonical_json(source_request_ceiling_drift),
      "structured decision v1.1 rejects self-consistent request expansion beyond source packet",
      /request limits do not equal the source Founder packet/
    )

    source_model_drift = deep_copy(v1_1)
    source_model_drift["ordered_tasks"][1]["founder_reserved_profile"]
      .dig("model")["requested_model"] = "unauthorized-model-variant"
    expect_decision_nonpass(
      canonical_json(source_model_drift),
      "structured decision v1.1 rejects model drift from source packet",
      /model does not equal the source Founder packet/
    )

    [0, 2].each do |target_index|
      moved_profile = deep_copy(v1_1)
      provider_task = moved_profile["ordered_tasks"][1]
      target_task = moved_profile["ordered_tasks"][target_index]
      target_task["external_effects"] = deep_copy(provider_task["external_effects"])
      target_task["founder_reserved_profile"] = deep_copy(provider_task["founder_reserved_profile"])
      target_task["founder_reserved_profile"]["task_id"] = target_task["task_id"]
      provider_task["external_effects"] = false_effects
      provider_task["founder_reserved_profile"] = nil
      expect_decision_nonpass(
        canonical_json(moved_profile),
        "structured decision v1.1 rejects moving source Task 2 profile to Task #{target_index + 1}",
        /profile Task does not equal the source Founder packet Task slot/
      )
    end

    retry_drift = deep_copy(v1_1)
    retry_drift["ordered_tasks"][1]["founder_reserved_profile"]
      .dig("call_limits")["automatic_retry_max"] = 1
    expect_decision_nonpass(
      canonical_json(retry_drift),
      "structured decision v1.1 automatic retry drift",
      /automatic_retry_max must equal 0/
    )

    packet_binding_drift = deep_copy(v1_1)
    packet_binding_drift["ordered_tasks"][1]["founder_reserved_profile"]["decision_basis"] =
      "FOUNDER_PACKET_SHA256:#{'0' * 64}"
    expect_decision_nonpass(
      canonical_json(packet_binding_drift),
      "structured decision v1.1 Provider profile packet binding drift",
      /does not bind the exact source packet/
    )

    loose_effect_expansion = deep_copy(v1_1)
    loose_effect_expansion["external_effects"]["public"] = true
    expect_decision_nonpass(
      canonical_json(loose_effect_expansion),
      "structured decision v1.1 route effect expansion drift",
      /route external effects must equal the union/
    )

    v1_with_automatic_entries = JSON.parse(File.binread(STRUCTURED_DECISION_PATH))
    v1_with_automatic_entries["automatic_entries"] = [
      deep_copy(v1_with_automatic_entries.fetch("automatic_entry"))
    ]
    expect_decision_nonpass(
      canonical_json(v1_with_automatic_entries),
      "structured decision v1.0 rejects v1.1 automatic entries",
      /keys drifted/
    )

    v1_with_task_effects = JSON.parse(File.binread(STRUCTURED_DECISION_PATH))
    v1_with_task_effects["ordered_tasks"][0]["external_effects"] = false_effects
    expect_decision_nonpass(
      canonical_json(v1_with_task_effects),
      "structured decision v1.0 rejects v1.1 Task effects",
      /keys drifted/
    )
  end

  def v2_profile
    {
      "schema_version" => "2.0",
      "profile_id" => "TEST_NARROW_PROVIDER_PROFILE_V2",
      "decision_basis" => "TEST_EXACT_FOUNDER_PACKET",
      "route_id" => "P1_TEST_NARROW_PROVIDER_PROFILE_ROUTE_V1",
      "task_id" => "AIOS-P1-999_TEST_NARROW_PROVIDER_PROFILE",
      "transport" => {
        "scheme" => "http",
        "host" => "127.0.0.1",
        "port" => 8787,
        "base_path" => "/v1",
        "completion_path" => "/v1/chat/completions",
        "api_format" => "OPENAI_COMPATIBLE_CHAT_COMPLETIONS",
        "method" => "POST",
        "follow_redirects" => false,
        "use_proxy" => false,
        "dns_resolution" => false,
        "fallback_endpoint_allowed" => false,
        "expected_peer_address" => "127.0.0.1",
        "expected_peer_port" => 8787
      },
      "model" => {
        "requested_model" => "gpt-5.6-luna",
        "substitution_allowed" => false,
        "provider_provenance" =>
          "FOUNDER_ATTESTED_OPENAI_COMPATIBLE_LOCAL_GATEWAY_MODEL_NOT_INDEPENDENTLY_VERIFIED"
      },
      "secret" => {
        "allowed_sources" => %w[LOCAL_PROCESS_ENV CONTROLLED_TEMPORARY_SECRET_FILE],
        "persist" => false,
        "prohibited_sinks" => %w[REPOSITORY EVIDENCE LOG TRACE PROMPT REVIEW VAULT]
      },
      "call_limits" => {
        "provider_requests_max" => 72,
        "automatic_retry_max" => 0
      },
      "token_limits" => {
        "input_tokens_max" => 3_000_000,
        "output_tokens_max" => 300_000
      },
      "monetary_limits" => {
        "currency" => "USD",
        "max_spend" => 25,
        "unavailable_metering_status" => "UNKNOWN_GATEWAY_METERING_UNAVAILABLE"
      },
      "egress" => {
        "restricted_source_allowed" => false
      },
      "external_effects" => {
        "network" => true,
        "provider" => true,
        "secret" => true,
        "remote" => false,
        "production" => false,
        "public" => false
      },
      "claim_limits" => {
        "direct_openai_provenance_proven" => false,
        "adapter_conformance_is_model_performance" => false,
        "remote" => false,
        "production" => false,
        "public" => false
      }
    }
  end

  def v1_profile
    {
      "schema_version" => "1.0",
      "profile_id" => "TEST_LEGACY_PROVIDER_PROFILE_V1",
      "decision_basis" => "TEST_LEGACY_EXACT_FOUNDER_PACKET",
      "route_id" => "P1_TEST_LEGACY_PROVIDER_PROFILE_ROUTE_V1",
      "task_id" => "AIOS-P1-998_TEST_LEGACY_PROVIDER_PROFILE",
      "transport" => {
        "scheme" => "http",
        "host" => "127.0.0.1",
        "port" => 8787,
        "base_path" => "/v1",
        "metadata_path" => "/v1/models",
        "completion_path" => "/v1/chat/completions",
        "api_format" => "OPENAI_COMPATIBLE_CHAT_COMPLETIONS",
        "method" => "POST",
        "follow_redirects" => false,
        "use_proxy" => false,
        "dns_resolution" => false,
        "fallback_endpoint_allowed" => false,
        "expected_peer_address" => "127.0.0.1",
        "expected_peer_port" => 8787
      },
      "model" => {
        "requested_model" => "fixture-model",
        "substitution_allowed" => false,
        "provider_provenance" => "OPENAI_FOUNDER_ATTESTED_GATEWAY_NOT_INDEPENDENTLY_VERIFIED"
      },
      "secret" => {
        "env_name" => "P1_TEST_PROVIDER_KEY",
        "source" => "FOUNDER_TRANSIENT_UI_INPUT",
        "persist" => false,
        "log_hash_or_evidence_allowed" => false
      },
      "call_limits" => {
        "metadata_max" => 1,
        "metadata_used_before_activation" => 1,
        "source_bearing_max" => 1,
        "source_bearing_used_before_activation" => 0,
        "automatic_retry_max" => 0,
        "ambiguous_send_retry_allowed" => false
      },
      "request_limits" => {
        "max_input_tokens" => 4096,
        "max_output_tokens" => 1024,
        "timeout_seconds" => 120,
        "request_body_max_bytes" => 32_768,
        "response_body_max_bytes" => 131_072
      },
      "egress" => {
        "allowed_artifact_ids" => %w[
          P1_035_REP001_ISSUE_TEXT
          P1_035_REP001_ALLOWED_CLARIFICATIONS
          P1_035_REP001_ACCEPTED_BASELINE_CONTEXT
          P1_062_FINITE_IR_RESPONSE_INSTRUCTION
        ],
        "forbidden_categories" => %w[
          SOURCE_BYTES
          TEST_BYTES
          REFERENCE_PATCH
          EVALUATOR_BYTES
          GOVERNANCE_OR_TRUTH_BYTES
          SECRET_OR_AUTHORIZATION_HEADER
          HIDDEN_TASK_OR_HIDDEN_EVIDENCE
        ]
      },
      "external_effects" => {
        "network" => true,
        "provider" => true,
        "secret" => true,
        "remote" => false,
        "production" => false,
        "public" => false
      },
      "claim_limits" => {
        "direct_openai_provenance_proven" => false,
        "upstream_provider" => "OPENAI_FOUNDER_ATTESTED",
        "upstream_request_count" => "UNKNOWN",
        "monetary_cost" => "UNKNOWN_USER_MANAGED_GATEWAY"
      }
    }
  end

  def expect_profile_pass(profile, route_id, task_id, label)
    CurrentTaskAuthority.validate_founder_reserved_profile(profile, route_id, task_id, label)
    @passes += 1
    puts "PASS #{label}"
  rescue AuthorityValidationError => e
    raise TestFailure, "#{label}: expected PASS, got #{e.message}"
  end

  def expect_profile_nonpass(profile, label, pattern)
    CurrentTaskAuthority.validate_founder_reserved_profile(
      profile,
      profile.fetch("route_id"),
      profile.fetch("task_id"),
      label
    )
    raise TestFailure, "#{label}: expected NON_PASS"
  rescue AuthorityValidationError => e
    assert(pattern.match?(e.message), "#{label}: expected #{pattern.inspect}, got #{e.message.inspect}")
    @passes += 1
    puts "PASS #{label}"
  end

  def provider_profile_unit_tests
    profile = v2_profile
    expect_profile_pass(profile, profile.fetch("route_id"), profile.fetch("task_id"),
                        "schema v2 narrower exact profile")
    minimum_profile = deep_copy(profile)
    minimum_profile["call_limits"]["provider_requests_max"] = 1
    minimum_profile["token_limits"]["input_tokens_max"] = 1
    minimum_profile["token_limits"]["output_tokens_max"] = 1
    minimum_profile["monetary_limits"]["max_spend"] = 0
    expect_profile_pass(
      minimum_profile,
      minimum_profile.fetch("route_id"),
      minimum_profile.fetch("task_id"),
      "schema v2 minimum exact profile"
    )

    [
      [%w[call_limits provider_requests_max], 0, /provider_requests_max must be in 1\.\.144/],
      [%w[call_limits provider_requests_max], 145, /provider_requests_max must be in 1\.\.144/],
      [%w[call_limits automatic_retry_max], 1, /automatic_retry_max must equal 0/],
      [%w[token_limits input_tokens_max], 0, /input_tokens_max must be in 1\.\.3000000/],
      [%w[token_limits input_tokens_max], 3_000_001, /input_tokens_max must be in 1\.\.3000000/],
      [%w[token_limits output_tokens_max], 0, /output_tokens_max must be in 1\.\.300000/],
      [%w[token_limits output_tokens_max], 300_001, /output_tokens_max must be in 1\.\.300000/],
      [%w[monetary_limits max_spend], -0.01, /max_spend must be numeric in 0\.\.25/],
      [%w[monetary_limits max_spend], 25.01, /max_spend must be numeric in 0\.\.25/],
      [%w[monetary_limits max_spend], "25", /max_spend must be numeric in 0\.\.25/]
    ].each do |path, value, pattern|
      variant = deep_copy(profile)
      variant.fetch(path[0])[path[1]] = value
      expect_profile_nonpass(variant, "schema v2 rejects #{path.join('.')}:#{value.inspect}", pattern)
    end

    begin
      CurrentTaskAuthority.validate_exact_profile_binding(
        profile,
        deep_copy(profile).tap { |copy| copy["call_limits"]["provider_requests_max"] = 71 },
        "Truth Founder-reserved profile does not equal the exact decision packet"
      )
      raise TestFailure, "packet/Truth profile mismatch: expected NON_PASS"
    rescue AuthorityValidationError => e
      assert(e.message.include?("exact decision packet"), "packet/Truth mismatch reason drifted")
      @passes += 1
      puts "PASS packet/Truth profile mismatch"
    end

    %w[contract authority].each do |binding|
      begin
        CurrentTaskAuthority.validate_exact_profile_binding(
          deep_copy(profile).tap { |copy| copy["token_limits"]["output_tokens_max"] = 299_999 },
          profile,
          "#{binding} Founder-reserved profile mismatch"
        )
        raise TestFailure, "#{binding} profile mismatch: expected NON_PASS"
      rescue AuthorityValidationError => e
        assert(e.message.include?("#{binding} Founder-reserved profile mismatch"),
               "#{binding} mismatch reason drifted")
        @passes += 1
        puts "PASS #{binding} profile mismatch"
      end
    end

    legacy = v1_profile
    expect_profile_pass(legacy, legacy.fetch("route_id"), legacy.fetch("task_id"),
                        "legacy schema v1 compatibility")

    truth = yaml(File.join(SOURCE_REPO, TRUTH_RELATIVE))
    packet_path = truth.dig("current_phase_route", "decision_packet", "path")
    current_claims = CurrentTaskAuthority.packet_claims(File.binread(packet_path))
    current_profile = current_claims["founder_reserved_profile"]
    if current_profile && current_profile["schema_version"] == "3.0"
      expect_profile_pass(
        current_profile,
        current_profile.fetch("route_id"),
        current_profile.fetch("task_id"),
        "schema v3 operator-owned exact profile"
      )
      [
        [%w[secret source], "LOCAL_PROCESS_ENV", /no-echo TTY/],
        [%w[call_limits formal_requests_exact], 35, /call limits drifted/],
        [%w[effect_partition canonical_aios network], true, /exact authorized external-effect map/],
        [%w[egress derived_context_policy], "ARBITRARY_CONTEXT", /derived-context policy drifted/]
      ].each do |path, value, pattern|
        variant = deep_copy(current_profile)
        cursor = variant
        path[0...-1].each { |key| cursor = cursor.fetch(key) }
        cursor[path.last] = value
        expect_profile_nonpass(variant, "schema v3 rejects #{path.join('.')}:#{value.inspect}", pattern)
      end
    end
  end

  def closed_profile_packet_unit_tests
    truth = yaml(File.join(SOURCE_REPO, TRUTH_RELATIVE))
    packet_path = truth.dig("current_phase_route", "decision_packet", "path")
    packet = File.binread(packet_path).force_encoding(Encoding::UTF_8)
    claims = CurrentTaskAuthority.packet_claims(packet)
    expected_tasks = truth.fetch("current_phase_route").fetch("task_plan").map do |descriptor|
      descriptor.fetch("task_id")
    end
    assert(claims["task_ids"] == expected_tasks, "current packet Task set drifted")
    if claims["founder_reserved_profiles"].empty?
      expected_effects = truth.dig("current_phase_route", "envelope", "external_effects")
      assert(claims["external_effects"] == expected_effects,
             "current packet external-effect boundary drifted from Truth")
      @passes += 1
      puts "PASS exact current packet Task/effect set"
      if packet.include?("AUTHORIZE_P1_PARTIAL_EXIT_WITH_DISCLOSED_RESIDUALS_AND_DIRECT_P2_REPOSITORY_INTELLIGENCE_PHASE_ENTRY_V1") ||
         packet.include?("AUTHORIZE_P2_ACCEPTED_REPOSITORY_GRAPH_INDEX_AND_GRAPH_CONDITIONED_CONTEXT_ROUTE_V1") ||
         packet.include?("AUTHORIZE_P2_SCANNER_FIRST_EXACT_GRAPH_AUTHORITY_AND_GRAPH_CONDITIONED_CONTEXT_ROUTE_V1")
        original_task_id = expected_tasks.first
        replacement_task_id = "AIOS-P2-901_DATA_DRIVEN_PACKET_FIXTURE"
        data_driven_packet = packet.sub(original_task_id, replacement_task_id)
        data_driven_claims = CurrentTaskAuthority.packet_claims(data_driven_packet)
        assert(data_driven_claims["task_ids"].first == replacement_task_id,
               "P2 packet parser hard-coded the current first Task id")
        assert(data_driven_claims["task_budgets"].map { |entry| entry["engineering_hours"] }.sum ==
               data_driven_claims["max_engineering_hours"],
               "P2 packet parser did not derive the Task budget set")
        @passes += 1
        puts "PASS P2 packet Task ids and budgets are data-driven"
      end
      return
    end
    assert(
      claims["founder_reserved_profiles"].map { |profile| profile["task_id"] } == expected_tasks,
      "current packet profile set drifted"
    )
    @passes += 1
    puts "PASS exact current packet Task/profile set"

    if packet.include?("AUTHORIZE_P1_OPERATOR_OWNED_CREDENTIAL_CAPTURE_AND_OFFLINE_EXIT_GATE_ROUTE_V1")
      first_artifact_row = packet.lines.find do |line|
        line.match?(/^\| [^|]+ \| \d+ \| `[0-9a-f]{64}` \| `[^`]+` \|$/)
      end
      assert(first_artifact_row, "operator packet disclosure row missing")
      missing = packet.sub(first_artifact_row, "")
      begin
        CurrentTaskAuthority.packet_claims(missing)
        raise TestFailure, "missing disclosure artifact: expected NON_PASS"
      rescue AuthorityValidationError => e
        assert(e.message.include?("16 disclosed artifact"), "missing disclosure reason drifted: #{e.message}")
        @passes += 1
        puts "PASS missing operator disclosure artifact rejects"
      end
    elsif packet.include?("PROFILE_JSON")
      first_block = /
        <!--\ BEGIN\ FOUNDER_[A-Z0-9_]*PROFILE_JSON\ -->.*?
        <!--\ END\ FOUNDER_[A-Z0-9_]*PROFILE_JSON\ -->
      /mx
      missing = packet.sub(first_block, "")
      begin
        CurrentTaskAuthority.packet_claims(missing)
        raise TestFailure, "missing packet profile: expected NON_PASS"
      rescue AuthorityValidationError => e
        assert(e.message.include?("profile") || e.message.include?("external effects"),
               "missing profile reason drifted: #{e.message}")
        @passes += 1
        puts "PASS missing current packet profile rejects"
      end
    end
  end

  def prepare_p1_ready_golden_fixture(sandbox)
    source_truth = YAML.load(
      shell(SOURCE_REPO, "git", "show", "#{P1_READY_GOLDEN_COMMIT}:#{TRUTH_RELATIVE}")
    )
    assert(source_truth.dig("project", "current_phase") == "P1",
           "historical P1 READY golden phase drifted")
    assert(source_truth.dig("current_phase_route", "status") == "AUTHORIZED_READY",
           "historical P1 READY golden route drifted")
    assert(source_truth.dig("active_work", "current_task") == "NONE",
           "historical P1 READY golden Task state drifted")

    repo = File.join(sandbox, "p1-ready-repo")
    external = File.join(sandbox, "p1-ready-external")
    FileUtils.mkdir_p(external)
    shell(sandbox, "git", "clone", "--quiet", "--no-hardlinks", SOURCE_REPO, repo)
    shell(repo, "git", "checkout", "--quiet", "-B", "main", P1_READY_GOLDEN_COMMIT)
    shell(repo, "git", "config", "user.name", "P1 Golden Fixture")
    shell(repo, "git", "config", "user.email", "p1-golden@example.invalid")

    validator_path = File.join(repo, "scripts/validate-current-task-authority.rb")
    safety_path = File.join(repo, "scripts/check-p1-safety-boundary.sh")
    register_owned(validator_path)
    register_owned(safety_path)
    rewrite_owned(validator_path, File.binread(VALIDATOR))
    rewrite_owned(safety_path, File.binread(SAFETY_VALIDATOR))

    packet_identity = source_truth.fetch("current_phase_route").fetch("decision_packet")
    packet_source = packet_identity.fetch("path")
    packet_path = verified_source_copy(
      packet_source,
      File.join(external, "decision-packet#{File.extname(packet_source)}"),
      packet_identity.fetch("sha256"),
      packet_identity.fetch("byte_length")
    )
    goal_path = verified_source_copy(
      source_truth.fetch("goal").fetch("source_attachment_path"),
      File.join(external, "goal.txt"),
      "28bc384fbac9d69c6de3ef8709a5be5a0473309b0fe0e54b01bead13d4fa9cf1",
      19_433
    )
    worktree_root = File.join(external, "worktrees")
    evidence_base = File.join(external, "audit")
    FileUtils.mkdir_p(worktree_root)
    FileUtils.mkdir_p(evidence_base)

    truth_path = File.join(repo, TRUTH_RELATIVE)
    register_owned(truth_path)
    source_truth["goal"]["source_attachment_path"] = goal_path
    source_truth["project"]["canonical_repository"] = repo
    source_truth["project"]["canonical_branch"] = "main"
    source_truth["project"]["task_worktree_root"] = worktree_root
    source_truth["project"]["execution_evidence_root_base"] = evidence_base
    source_truth["current_phase_route"]["decision_packet"]["path"] = packet_path
    source_truth["current_phase_route"]["inherited_worktree_inventory"] = []
    dump_owned_yaml(truth_path, source_truth)
    commit(repo, "test: materialize historical P1 READY golden")

    {
      "repo" => repo,
      "external" => external,
      "truth_path" => truth_path,
      "policy_path" => File.join(repo, POLICY_RELATIVE),
      "packet_path" => packet_path,
      "goal_path" => goal_path,
      "worktree_root" => worktree_root,
      "evidence_base" => evidence_base
    }
  end

  def p1_ready_and_active_golden_regression_tests(sandbox)
    fixture = prepare_p1_ready_golden_fixture(sandbox)
    expect_pass(fixture["repo"], "historical P1 READY_NONE golden")
    stdout, stderr, status = run_safety(fixture["repo"], fixture["truth_path"])
    assert(status.success?, "historical P1 READY safety: expected PASS\n#{stdout}#{stderr}")
    assert(stdout.include?("P1_SAFETY_UNIQUE: PASS"),
           "historical P1 READY safety marker drifted")
    @passes += 1
    puts "PASS historical P1 READY_NONE safety golden"

    active = activate_fixture(fixture)
    expect_pass(active["repo"], "historical P1 ACTIVE_TASK golden")
    stdout, stderr, status = run_safety(active["repo"], active["truth_path"])
    assert(status.success?, "historical P1 ACTIVE safety: expected PASS\n#{stdout}#{stderr}")
    assert(stdout.include?("P1_SAFETY_UNIQUE: PASS"),
           "historical P1 ACTIVE safety marker drifted")
    @passes += 1
    puts "PASS historical P1 ACTIVE_TASK safety golden"
    shell(active["repo"], "git", "worktree", "remove", active["task_worktree"])
    shell(active["repo"], "git", "branch", "-d", active["task_branch"])
  end

  def prepare_fixture(sandbox)
    source_truth_path = File.join(SOURCE_REPO, TRUTH_RELATIVE)
    source_truth = yaml(source_truth_path)
    source_head = shell(SOURCE_REPO, "git", "rev-parse", "HEAD").strip
    repo = File.join(sandbox, "repo")
    external = File.join(sandbox, "external")
    FileUtils.mkdir_p(external)
    shell(sandbox, "git", "clone", "--quiet", "--no-hardlinks", SOURCE_REPO, repo)
    shell(repo, "git", "config", "user.name", "Authority Fixture")
    shell(repo, "git", "config", "user.email", "authority-fixture@example.invalid")
    shell(repo, "git", "checkout", "--quiet", "-B", "main", source_head)

    truth_path = File.join(repo, TRUTH_RELATIVE)
    policy_path = File.join(repo, POLICY_RELATIVE)
    validator_path = File.join(repo, "scripts/validate-current-task-authority.rb")
    safety_path = File.join(repo, "scripts/check-p1-safety-boundary.sh")
    register_owned(truth_path)
    register_owned(policy_path)
    register_owned(validator_path)
    register_owned(safety_path)
    rewrite_owned(policy_path, File.binread(File.join(SOURCE_REPO, POLICY_RELATIVE)))
    rewrite_owned(validator_path, File.binread(VALIDATOR))
    rewrite_owned(safety_path, File.binread(SAFETY_VALIDATOR))

    packet_identity = source_truth.fetch("current_phase_route").fetch("decision_packet")
    packet_source = packet_identity.fetch("path")
    goal_source = source_truth.fetch("goal").fetch("source_attachment_path")
    packet_path = verified_source_copy(
      packet_source,
      File.join(external, "decision-packet#{File.extname(packet_source)}"),
      packet_identity.fetch("sha256"),
      packet_identity.fetch("byte_length")
    )
    goal_path = verified_source_copy(
      goal_source,
      File.join(external, "goal.txt"),
      "28bc384fbac9d69c6de3ef8709a5be5a0473309b0fe0e54b01bead13d4fa9cf1",
      19_433
    )

    worktree_root = File.join(external, "worktrees")
    evidence_base = File.join(external, "audit")
    FileUtils.mkdir_p(worktree_root)
    FileUtils.mkdir_p(evidence_base)

    truth = source_truth
    truth["goal"]["source_attachment_path"] = goal_path
    truth["goal"]["current_task_authority"] = "NONE"
    truth["project"]["canonical_repository"] = repo
    truth["project"]["canonical_branch"] = "main"
    truth["project"]["task_worktree_root"] = worktree_root
    truth["project"]["execution_evidence_root_base"] = evidence_base
    truth["project"]["phase_execution_status"] = "AUTHORIZED_READY"
    phase_status_key = "#{truth.dig('project', 'current_phase').downcase}_execution_status"
    truth["project"][phase_status_key] = "AUTHORIZED_READY"
    truth["current_phase_route"]["status"] = "AUTHORIZED_READY"
    truth["current_phase_route"]["decision_packet"]["path"] = packet_path
    first_task_id = truth.fetch("current_phase_route").fetch("first_task").fetch("task_id")
    truth.fetch("task_history").delete_if do |_key, record|
      record.is_a?(Hash) && record["task_id"] == first_task_id
    end
    truth["current_phase_route"]["first_task"]["status"] = "ELIGIBLE_NOT_ACTIVATED"
    truth["current_phase_route"]["task_plan"].each_with_index do |descriptor, index|
      descriptor["status"] =
        index.zero? ? "ELIGIBLE_NOT_ACTIVATED" : "PENDING_PREDECESSOR_TASK_GATE"
    end
    truth["current_phase_route"]["next_eligible_action"] = "MASTER_ACTIVATE_FIRST_TASK"
    truth["current_phase_route"]["inherited_worktree_inventory"] = []
    truth["current_phase_route"].delete("active_task")
    truth["active_work"] = ready_active_work
    truth["active_work"]["external_effects"] =
      deep_copy(truth.dig("current_phase_route", "envelope", "external_effects"))
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: fixture ready route")

    {
      "repo" => repo,
      "external" => external,
      "truth_path" => truth_path,
      "policy_path" => policy_path,
      "packet_path" => packet_path,
      "goal_path" => goal_path,
      "worktree_root" => worktree_root,
      "evidence_base" => evidence_base
    }
  end

  def prepare_structured_fixture(sandbox, decision_override: nil)
    fixture_root = File.join(sandbox, "structured")
    FileUtils.mkdir_p(fixture_root)
    fixture = prepare_fixture(fixture_root)
    decision = decision_override || JSON.parse(File.binread(STRUCTURED_DECISION_PATH))
    decision_bytes = decision_override ? canonical_json(decision) : File.binread(STRUCTURED_DECISION_PATH)
    decision_path = File.join(fixture["external"], "founder-phase-route-decision.json")
    create_exclusive(decision_path, decision_bytes)

    truth = yaml(fixture["truth_path"])
    decision_phase = decision.fetch("phase")
    truth["project"]["current_phase"] = decision_phase
    truth["project"]["phase_execution_status"] = "AUTHORIZED_READY"
    truth["project"]["#{decision_phase.downcase}_execution_status"] = "AUTHORIZED_READY"
    truth["phase_boundary"]["phase"] = decision_phase
    if decision_phase == "P2"
      truth["project"]["p1_execution_status"] =
        "PARTIAL_EXIT_WITH_DISCLOSED_RESIDUALS_6_OF_8_75_PERCENT"
      truth["project"]["p2_entry_status"] = "AUTHORIZED"
      truth["phase_boundary"]["allowed_task_kinds"] = %w[
        REPOSITORY_INTELLIGENCE_ENGINEERING
        REPOSITORY_INTELLIGENCE_RESEARCH
      ]
      truth["phase_boundary"]["allowed_capabilities"] = %w[
        P2_REPOSITORY_INTELLIGENCE_CAPABILITY_CLAIM
        TASK_CONDITIONED_CONTEXT_SELECTION
        REPOSITORY_CONTEXT_BENCHMARK
        LOCAL_COMMIT_DERIVED_TASK_DATASET
        DETERMINISTIC_REPLAY
        EVALUATOR_AND_ORACLE
        EVIDENCE_MANIFEST
        FAILURE_TAXONOMY
        EVALUATION_METRICS
      ]
      truth["phase_boundary"]["deferred_capabilities"] = %w[
        P3_SINGLE_AGENT_RUNTIME
        AGENT_SHELL
        MODEL_INITIATED_CANONICAL_WRITE
        PLATFORM_IDENTITY
        SUPERVISOR
        ROOT_CUSTODY
        STRONG_ISOLATION
        MULTI_AGENT_RUNTIME
      ]
    end
    task_plan = decision.fetch("ordered_tasks").map do |task|
      descriptor = {
        "task_slot" => task.fetch("task_slot"),
        "task_id" => task.fetch("task_id"),
        "status" => task.fetch("task_slot") == 1 ? "ELIGIBLE_NOT_ACTIVATED" : "PENDING_PREDECESSOR_TASK_GATE",
        "engineering_hours" => task.fetch("engineering_hours"),
        "calendar_days" => task.fetch("calendar_days"),
        "max_implementation_iterations" => task.fetch("max_implementation_iterations"),
        "max_same_task_repairs" => task.fetch("max_same_task_repairs"),
        "max_candidates" => task.fetch("max_candidates")
      }
      descriptor["external_effects"] = deep_copy(task.fetch("external_effects")) if decision["schema_version"] == "1.1"
      descriptor
    end
    first = decision.fetch("ordered_tasks").first
    truth["current_phase_route"] = {
      "route_id" => decision.fetch("route_id"),
      "status" => "AUTHORIZED_READY",
      "phase" => decision.fetch("phase"),
      "phase_entry_status" => "AUTHORIZED",
      "authorization_token" => decision.fetch("authorization_token"),
      "decision_packet" => {
        "path" => decision_path,
        "sha256" => Digest::SHA256.hexdigest(decision_bytes),
        "byte_length" => decision_bytes.bytesize
      },
      "activation_parent" => deep_copy(decision.fetch("activation_parent")),
      "policy" => deep_copy(truth.dig("authority", "founder_delegation_policy")),
      "goal_identity" => {
        "raw_sha256" => decision.dig("goal_identity", "raw_sha256"),
        "raw_byte_length" => decision.dig("goal_identity", "raw_byte_length"),
        "canonicalization" => decision.dig("goal_identity", "canonicalization"),
        "canonical_sha256" => decision.dig("goal_identity", "canonical_sha256"),
        "canonical_byte_length" => decision.dig("goal_identity", "canonical_byte_length")
      },
      "objective" => "Exercise generic structured Founder route-decision authority.",
      "envelope" => {
        "max_engineering_tasks" => decision.dig("envelope", "max_engineering_tasks"),
        "max_engineering_hours" => decision.dig("envelope", "max_engineering_hours"),
        "max_calendar_days" => decision.dig("envelope", "max_calendar_days"),
        "max_active_tasks" => decision.dig("envelope", "max_active_tasks"),
        "max_task_branches" => decision.dig("envelope", "max_task_branches"),
        "max_task_worktrees" => decision.dig("envelope", "max_task_worktrees"),
        "max_active_candidates" => decision.dig("envelope", "max_active_candidates"),
        "max_contract_corrections_per_task" => 0,
        "max_same_task_repairs" => decision.dig("envelope", "max_same_task_repairs_per_task"),
        "successor_replacement_normalization_closure_feasibility_or_remediation_chain_allowed" => false,
        "p2_entry_authorized" => decision.fetch("phase") == "P2",
        "p3_entry_authorized" => decision.dig("envelope", "p3_entry_authorized"),
        "external_effects" => deep_copy(decision.fetch("external_effects"))
      },
      "accepted_inputs" => {},
      "accepted_input_ids" => [],
      "first_task" => {
        "task_id" => first.fetch("task_id"),
        "task_slot" => first.fetch("task_slot"),
        "status" => "ELIGIBLE_NOT_ACTIVATED",
        "contract_path" => "docs/aios/tasks/P2-007_STRUCTURED_AUTHORITY_FIXTURE.yaml",
        "max_engineering_hours" => first.fetch("engineering_hours"),
        "max_calendar_days" => first.fetch("calendar_days"),
        "max_implementation_iterations" => first.fetch("max_implementation_iterations"),
        "max_candidates" => first.fetch("max_candidates")
      },
      "task_plan" => task_plan,
      "automatic_entry" => deep_copy(decision.fetch("automatic_entry")),
      "next_eligible_action" => "MASTER_ACTIVATE_FIRST_TASK",
      "additional_write_roots" => [],
      "inherited_worktree_inventory" => [],
      "claim_boundary" => decision.fetch("claim_boundary")
    }
    if decision["schema_version"] == "1.1"
      truth["current_phase_route"]["automatic_entries"] =
        deep_copy(decision.fetch("automatic_entries"))
      profiles = decision.fetch("ordered_tasks").map do |task|
        deep_copy(task["founder_reserved_profile"])
      end.compact
      truth["current_phase_route"]["founder_reserved_profile"] =
        deep_copy(decision.fetch("ordered_tasks").first["founder_reserved_profile"])
      truth["current_phase_route"]["founder_reserved_profiles"] = profiles
    end
    truth.fetch("task_history").delete_if do |_key, record|
      record.is_a?(Hash) && decision.fetch("ordered_tasks").any? { |task| task["task_id"] == record["task_id"] }
    end
    truth["active_work"]["external_effects"] = if decision["schema_version"] == "1.1"
                                                  false_effects
                                                else
                                                  deep_copy(decision.fetch("external_effects"))
                                                end
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(fixture["repo"], "test: materialize structured Founder decision route")
    fixture.merge("packet_path" => decision_path, "structured_decision" => decision)
  end

  def ready_tests(fixture)
    repo = fixture["repo"]
    expect_pass(repo, "ready route with Task NONE")
    expect_safety_pass(repo, fixture["truth_path"], "ready route safety with Task NONE")

    original = tamper_owned_byte(fixture["packet_path"])
    expect_nonpass(repo, "decision packet byte tamper", /decision packet.*SHA-256 mismatch/i)
    restore_owned_byte(fixture["packet_path"], original)
    expect_pass(repo, "decision packet restored")

    original = tamper_owned_byte(fixture["goal_path"])
    expect_nonpass(repo, "Goal source byte tamper", /Goal raw SHA-256 mismatch/)
    restore_owned_byte(fixture["goal_path"], original)

    original = tamper_owned_byte(fixture["policy_path"])
    commit(repo, "test: tamper owned authority policy bytes")
    expect_nonpass(repo, "authority policy byte tamper", /founder_delegation_policy SHA-256 mismatch/)
    restore_owned_byte(fixture["policy_path"], original)
    commit(repo, "test: restore owned authority policy bytes")

    truth = yaml(fixture["truth_path"])
    original_hours = truth["current_phase_route"]["envelope"]["max_engineering_hours"]
    truth["current_phase_route"]["envelope"]["max_engineering_hours"] = original_hours + 1
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: detach route envelope from decision packet")
    expect_nonpass(repo, "route envelope decision-byte detachment", /envelope max_engineering_hours does not match/)
    truth["current_phase_route"]["envelope"]["max_engineering_hours"] = original_hours
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore route envelope binding")

    truth = yaml(fixture["truth_path"])
    if truth["current_phase_route"]["founder_reserved_profile"]
      original_host = truth["current_phase_route"]["founder_reserved_profile"]["transport"]["host"]
      truth["current_phase_route"]["founder_reserved_profile"]["transport"]["host"] = "localhost"
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: expand literal gateway host to DNS name")
      expect_nonpass(repo, "Founder profile host expansion", /transport exceeds the literal local-gateway boundary/)
      expect_safety_nonpass(repo, fixture["truth_path"], "safety rejects Founder profile host expansion",
                            /transport exceeds the literal local-gateway boundary/)
      truth["current_phase_route"]["founder_reserved_profile"]["transport"]["host"] = original_host
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: restore literal gateway host")

      truth = yaml(fixture["truth_path"])
      profile = truth["current_phase_route"]["founder_reserved_profile"]
      call_key = profile["schema_version"] == "1.0" ? "source_bearing_max" : "provider_requests_max"
      original_call_limit = profile["call_limits"][call_key]
      profile["call_limits"][call_key] = original_call_limit + 1
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: detach Founder-reserved call budget from packet")
      expect_nonpass(
        repo,
        "Founder profile call-budget detachment",
        /call limits drifted|does not equal the exact decision packet/
      )
      profile["call_limits"][call_key] = original_call_limit
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: restore Founder-reserved call budget")

      truth = yaml(fixture["truth_path"])
      profiles = truth["current_phase_route"]["founder_reserved_profiles"]
      if profiles.is_a?(Array) && profiles.length > 1
        removed = profiles.pop
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: remove one exact route Task profile")
        expect_nonpass(repo, "Truth missing Task profile", /Founder profile set/)
        truth["current_phase_route"]["founder_reserved_profiles"] << removed
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: restore exact route Task profile")

        truth = yaml(fixture["truth_path"])
        truth["current_phase_route"]["founder_reserved_profiles"] <<
          deep_copy(truth["current_phase_route"]["founder_reserved_profiles"].last)
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: duplicate one exact route Task profile")
        expect_nonpass(repo, "Truth duplicate Task profile", /Founder profile set/)
        truth["current_phase_route"]["founder_reserved_profiles"].pop
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: remove duplicate route Task profile")

        truth = yaml(fixture["truth_path"])
        truth["current_phase_route"]["founder_reserved_profiles"].reverse!
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: reorder route Task profiles")
        expect_nonpass(repo, "Truth reordered Task profiles", /Task id mismatch|profile set/)
        truth["current_phase_route"]["founder_reserved_profiles"].reverse!
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: restore route Task profile order")

        truth = yaml(fixture["truth_path"])
        truth["current_phase_route"]["task_plan"] << {
          "task_slot" => 3,
          "task_id" => "AIOS-P1-118_UNDECLARED_THIRD_TASK",
          "status" => "ELIGIBLE_AFTER_TASK_2",
          "engineering_hours" => 1,
          "calendar_days" => 1,
          "strict_p1_credit_on_pass" => 0
        }
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: inject undeclared third Task")
        expect_nonpass(repo, "undeclared third Task", /task_plan Task set/)
        truth["current_phase_route"]["task_plan"].pop
        dump_owned_yaml(fixture["truth_path"], truth)
        commit(repo, "test: remove undeclared third Task")
      end
    end

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["envelope"]["external_effects"]["remote"] = true
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: authorize remote effect outside packet")
    expect_nonpass(repo, "remote effect expansion", /exact authorized external-effect map/)
    truth["current_phase_route"]["envelope"]["external_effects"]["remote"] = false
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore remote deny")

    accepted_inputs = yaml(fixture["truth_path"]).dig("current_phase_route", "accepted_inputs")
    accepted_lineage_tests(fixture) unless accepted_inputs.empty?
    truth = yaml(fixture["truth_path"])
    if truth["current_phase_route"].key?("accepted_input_ids")
      original_ids = deep_copy(truth["current_phase_route"]["accepted_input_ids"])
      truth["current_phase_route"].delete("accepted_input_ids")
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: remove closed accepted-input set declaration")
      if truth["current_phase_route"]["accepted_inputs"].empty?
        expect_nonpass(repo, "missing closed accepted-input set", /accepted_inputs must not be empty/)
      else
        expect_pass(repo, "optional closed accepted-input id set omitted with nonempty accepted inputs")
      end
      truth["current_phase_route"]["accepted_input_ids"] = original_ids + ["UNDECLARED_INPUT"]
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: mismatch closed accepted-input set")
      expect_nonpass(repo, "mismatched closed accepted-input set", /closed Truth input set/)
      truth["current_phase_route"]["accepted_input_ids"] = original_ids
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: restore closed accepted-input set")
    end

    truth = yaml(fixture["truth_path"])
    link_path = File.join(
      fixture["external"],
      "decision-packet-link#{File.extname(fixture['packet_path'])}"
    )
    File.symlink(fixture["packet_path"], link_path)
    link_stat = File.lstat(link_path)
    assert(link_stat.symlink?, "failed to create owned symlink fixture")
    truth["current_phase_route"]["decision_packet"]["path"] = link_path
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: point route packet at symlink")
    expect_nonpass(repo, "decision packet symlink", /must not be a symlink/)
    truth["current_phase_route"]["decision_packet"]["path"] = fixture["packet_path"]
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore real route packet")
    current_link = File.lstat(link_path)
    assert(current_link.symlink? && [current_link.dev, current_link.ino] == [link_stat.dev, link_stat.ino],
           "owned symlink fixture identity changed before cleanup")
    assert(File.readlink(link_path) == fixture["packet_path"], "owned symlink target changed before cleanup")
    File.unlink(link_path)
  end

  def top_level_history_record(truth, task_id)
    matches = truth.fetch("task_history").values.select do |record|
      record.is_a?(Hash) && record["task_id"] == task_id
    end
    assert(matches.length == 1, "fixture accepted input must have one top-level history record")
    matches.first
  end

  def accepted_lineage_tests(fixture)
    repo = fixture["repo"]
    truth_path = fixture["truth_path"]

    truth = yaml(truth_path)
    inputs = truth.fetch("current_phase_route").fetch("accepted_inputs")
    primary_key = inputs.keys.sort.first
    primary = inputs.fetch(primary_key)
    original_status = primary.fetch("status")
    primary["status"] = "MASTER_TASK_GATE_NOT_ACCEPTED_COMPLETE"
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: masquerade rejected accepted-input status")
    expect_nonpass(repo, "rejected-status accepted-input masquerade", /status is not an exact accepted Gate lifecycle/)
    primary["status"] = original_status
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: restore accepted-input status")

    truth = yaml(truth_path)
    inputs = truth.fetch("current_phase_route").fetch("accepted_inputs")
    input_pairs = inputs.keys.sort.combination(2).to_a
    alias_pair = input_pairs.find { |left, right| inputs[left]["task_id"] != inputs[right]["task_id"] }
    assert(alias_pair, "fixture needs two accepted inputs with distinct Task ids")
    alias_source, alias_target = alias_pair
    original_task_id = inputs[alias_source].fetch("task_id")
    inputs[alias_source]["task_id"] = inputs[alias_target].fetch("task_id")
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: alias one accepted input to another Task id")
    expect_nonpass(repo, "accepted-input Task-id alias", /history (?:status|contract|task_contract_sha256|accepted_candidate_)/)
    inputs[alias_source]["task_id"] = original_task_id
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: restore accepted-input Task id")

    truth = yaml(truth_path)
    inputs = truth.fetch("current_phase_route").fetch("accepted_inputs")
    substitution = nil
    inputs.keys.sort.each do |input_key|
      input = inputs.fetch(input_key)
      history = top_level_history_record(truth, input.fetch("task_id"))
      [%w[activation_parent_commit activation_parent_tree], %w[activation_commit activation_tree]].each do |commit_key, tree_key|
        next unless history[commit_key].is_a?(String) && history[tree_key].is_a?(String)
        next if history[commit_key] == input["accepted_candidate_commit"]
        substitution = [input_key, history[commit_key], history[tree_key]]
        break
      end
      break if substitution
    end
    assert(substitution, "fixture needs a pre-acceptance parent candidate for substitution")
    input_key, substitute_commit, substitute_tree = substitution
    input = inputs.fetch(input_key)
    accepted_commit = input.fetch("accepted_candidate_commit")
    accepted_tree = input.fetch("accepted_candidate_tree")
    input["accepted_candidate_commit"] = substitute_commit
    input["accepted_candidate_tree"] = substitute_tree
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: substitute pre-acceptance parent candidate")
    expect_nonpass(repo, "pre-acceptance parent candidate substitution",
                   /history accepted_candidate_commit binding mismatch/)
    input["accepted_candidate_commit"] = accepted_commit
    input["accepted_candidate_tree"] = accepted_tree
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: restore accepted candidate lineage")
    expect_pass(repo, "accepted-input lineage restored")
  end

  def structured_route_binding_tests(sandbox)
    fixture = prepare_structured_fixture(sandbox)
    repo = fixture["repo"]
    expect_pass(repo, "structured decision READY_NONE route")

    original = tamper_owned_byte(fixture["packet_path"])
    expect_nonpass(repo, "structured Decision bytes mismatch", /decision.*SHA-256 mismatch/i)
    restore_owned_byte(fixture["packet_path"], original)

    truth = yaml(fixture["truth_path"])
    original_path = truth.dig("current_phase_route", "decision_packet", "path")
    truth["current_phase_route"]["decision_packet"]["path"] = 7
    commit_truth(fixture, truth, "test: structured decision path type drift")
    expect_nonpass(repo, "structured Decision path type mismatch",
                   /decision_packet\.path must be a non-empty string/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["decision_packet"]["path"] = original_path
    commit_truth(fixture, truth, "test: restore structured decision path")

    truth = yaml(fixture["truth_path"])
    original_length = truth.dig("current_phase_route", "decision_packet", "byte_length")
    truth["current_phase_route"]["decision_packet"]["byte_length"] = original_length - 1
    commit_truth(fixture, truth, "test: structured decision length drift")
    expect_nonpass(repo, "structured Decision length mismatch", /decision packet byte length mismatch/i)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["decision_packet"]["byte_length"] = original_length
    commit_truth(fixture, truth, "test: restore structured decision length")

    truth = yaml(fixture["truth_path"])
    original_sha = truth.dig("current_phase_route", "decision_packet", "sha256")
    truth["current_phase_route"]["decision_packet"]["sha256"] = "0" * 64
    commit_truth(fixture, truth, "test: structured decision hash drift")
    expect_nonpass(repo, "structured Decision hash mismatch", /decision packet SHA-256 mismatch/i)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["decision_packet"]["sha256"] = original_sha
    commit_truth(fixture, truth, "test: restore structured decision hash")

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["route_id"] = "P2_TRUTH_MISMATCH_ROUTE_V1"
    commit_truth(fixture, truth, "test: structured Decision Truth route mismatch")
    expect_nonpass(repo, "structured Decision Truth mismatch", /Truth route id does not match/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["route_id"] = fixture["structured_decision"].fetch("route_id")
    commit_truth(fixture, truth, "test: restore structured Truth route")

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["automatic_entry"]["next_task_id"] = "AIOS-P2-999_WRONG_NEXT"
    commit_truth(fixture, truth, "test: structured Truth automatic entry mismatch")
    expect_nonpass(repo, "structured automatic-entry Truth mismatch",
                   /Truth automatic entry does not match/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["automatic_entry"] =
      deep_copy(fixture["structured_decision"].fetch("automatic_entry"))
    commit_truth(fixture, truth, "test: restore structured Truth automatic entry")

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["task_plan"][1]["engineering_hours"] += 1
    commit_truth(fixture, truth, "test: structured Truth task budget mismatch")
    expect_nonpass(repo, "structured Task budget Truth mismatch",
                   /task_plan budget does not equal the exact decision packet/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["task_plan"][1]["engineering_hours"] -= 1
    commit_truth(fixture, truth, "test: restore structured Truth task budget")

    link_path = File.join(fixture["external"], "structured-decision-link.json")
    File.symlink(fixture["packet_path"], link_path)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["decision_packet"]["path"] = link_path
    commit_truth(fixture, truth, "test: structured Decision symlink")
    expect_nonpass(repo, "structured Decision symlink mismatch", /must not be a symlink/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["decision_packet"]["path"] = fixture["packet_path"]
    commit_truth(fixture, truth, "test: restore structured Decision regular path")

    fixture = activate_fixture(fixture)
    expect_pass(repo, "structured decision ACTIVE_TASK route")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    truth["active_work"]["budget"]["engineering_hours"] -= 1
    contract["budget"]["engineering_hours"] -= 1
    authority["budget"]["engineering_hours"] -= 1
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: structured active Task budget mismatch")
    expect_nonpass(repo, "structured active Task budget mismatch",
                   /active Task budget does not equal the structured Founder decision/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    truth["active_work"]["budget"]["engineering_hours"] += 1
    contract["budget"]["engineering_hours"] += 1
    authority["budget"]["engineering_hours"] += 1
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore structured active Task budget binding")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["budget"]["undeclared_budget"] = 1
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: structured Contract budget extra key")
    expect_nonpass(repo, "structured Contract budget extra key", /contract budget mismatch/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["budget"].delete("undeclared_budget")
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore structured Contract budget closed keyset")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    removed_calendar_days = contract["budget"].delete("calendar_days")
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: structured Contract budget missing key")
    expect_nonpass(repo, "structured Contract budget missing key", /contract budget mismatch/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["budget"]["calendar_days"] = removed_calendar_days
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore structured Contract budget missing key")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["budget"]["candidates"] += 1
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: structured Contract budget mutation")
    expect_nonpass(repo, "structured Contract budget mutation", /contract budget mismatch/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["budget"]["candidates"] -= 1
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore structured Contract budget mutation")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["founder_reserved_authorization"]["authorization_token"] = "AUTHORIZE_P2_WRONG_ROUTE_V1"
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: structured Contract decision mismatch")
    expect_nonpass(repo, "structured Contract decision mismatch",
                   /contract Founder-reserved authorization mismatch/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["founder_reserved_authorization"]["authorization_token"] =
      fixture["structured_decision"].fetch("authorization_token")
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore structured Contract decision binding")

    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["founder_reserved_authorization"]["sha256"] = "0" * 64
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: structured authority decision mismatch")
    expect_nonpass(repo, "structured authority decision mismatch",
                   /authority record Founder-reserved authorization mismatch/)
    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["founder_reserved_authorization"]["sha256"] = STRUCTURED_DECISION_SHA256
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: restore structured authority decision binding")

    truth = yaml(fixture["truth_path"])
    truth["active_work"]["founder_reserved_authorization_sha256"] = "0" * 64
    commit_truth(fixture, truth, "test: structured active Truth decision mismatch")
    expect_nonpass(repo, "structured active Truth decision mismatch",
                   /active Founder-reserved authorization SHA mismatch/)
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["founder_reserved_authorization_sha256"] = STRUCTURED_DECISION_SHA256
    commit_truth(fixture, truth, "test: restore structured active Truth decision binding")
    expect_pass(repo, "structured Decision Truth Contract authority bindings restored")

    shell(repo, "git", "worktree", "remove", fixture["task_worktree"])
    shell(repo, "git", "branch", "-d", fixture["task_branch"])
  end

  def transition_to_second_task_ready(fixture, predecessor_status:, gate_evidence: nil)
    truth = yaml(fixture["truth_path"])
    route = truth.fetch("current_phase_route")
    phase = truth.dig("project", "current_phase")
    predecessor = route.fetch("task_plan").fetch(0)
    successor = route.fetch("task_plan").fetch(1)
    route["status"] = "ACTIVE"
    route["first_task"]["status"] = predecessor_status
    predecessor["status"] = predecessor_status
    successor["status"] = "ELIGIBLE_NOT_ACTIVATED"
    route.delete("active_task")
    route["next_eligible_action"] = "MASTER_ACTIVATE_NEXT_TASK"
    truth["project"]["phase_execution_status"] = "ACTIVE"
    truth["project"]["#{phase.downcase}_execution_status"] = "ACTIVE"
    truth["goal"]["current_task_authority"] = "NONE"
    truth["active_work"] = ready_active_work
    truth["active_work"]["task_resource_state"] = "NONE_PHASE_ACTIVE"
    structured_decision = fixture["structured_decision"]
    truth["active_work"]["external_effects"] =
      structured_decision && structured_decision["schema_version"] == "1.1" ?
        false_effects : deep_copy(route.dig("envelope", "external_effects"))
    truth["active_work"]["next_eligible_action"] = "MASTER_ACTIVATE_NEXT_TASK"
    truth["task_history"].delete_if do |_key, record|
      record.is_a?(Hash) && record["task_id"] == predecessor["task_id"]
    end
    truth["task_history"]["structured_predecessor_gate"] = gate_evidence if gate_evidence
    commit_truth(fixture, truth, "test: materialize structured automatic-entry predecessor state")
    fixture
  end

  def transition_to_later_task_ready(fixture, task_slot:, predecessor_status:, gate_evidence: nil)
    assert(task_slot > 1, "later Task transition requires task_slot greater than one")
    truth = yaml(fixture["truth_path"])
    route = truth.fetch("current_phase_route")
    phase = truth.dig("project", "current_phase")
    predecessor = route.fetch("task_plan").fetch(task_slot - 2)
    successor = route.fetch("task_plan").fetch(task_slot - 1)
    route["status"] = "ACTIVE"
    predecessor["status"] = predecessor_status
    route["first_task"]["status"] = predecessor_status if task_slot == 2
    successor["status"] = "ELIGIBLE_NOT_ACTIVATED"
    route.delete("active_task")
    route["next_eligible_action"] = "MASTER_ACTIVATE_NEXT_TASK"
    truth["project"]["phase_execution_status"] = "ACTIVE"
    truth["project"]["#{phase.downcase}_execution_status"] = "ACTIVE"
    truth["goal"]["current_task_authority"] = "NONE"
    truth["active_work"] = ready_active_work
    truth["active_work"]["task_resource_state"] = "NONE_PHASE_ACTIVE"
    truth["active_work"]["external_effects"] = false_effects
    truth["active_work"]["next_eligible_action"] = "MASTER_ACTIVATE_NEXT_TASK"
    truth["task_history"].delete_if do |_key, record|
      record.is_a?(Hash) && record["task_id"] == predecessor["task_id"]
    end
    truth["task_history"]["structured_predecessor_gate_slot_#{task_slot - 1}"] = gate_evidence if gate_evidence
    commit_truth(fixture, truth, "test: materialize structured Task #{task_slot} predecessor state")
    fixture
  end

  def transition_to_route_complete(fixture, final_status:, gate_evidence:)
    truth = yaml(fixture["truth_path"])
    route = truth.fetch("current_phase_route")
    phase = truth.dig("project", "current_phase")
    final_task = route.fetch("task_plan").last
    final_task["status"] = final_status
    route.delete("active_task")
    route["status"] = "PHASE_GATE_READY"
    route["next_eligible_action"] = "FOUNDER_PHASE_GATE"
    truth["project"]["phase_execution_status"] = "STOPPED_AT_FOUNDER_PHASE_GATE"
    truth["project"]["#{phase.downcase}_execution_status"] = "STOPPED_AT_FOUNDER_PHASE_GATE"
    truth["goal"]["current_task_authority"] = "NONE"
    truth["active_work"] = ready_active_work
    truth["active_work"]["task_resource_state"] = "NONE_PHASE_GATE_READY"
    truth["active_work"]["founder_decision_required"] = true
    truth["active_work"]["user_action_required"] = "FOUNDER_PHASE_GATE_DECISION"
    truth["active_work"]["next_eligible_action"] = "FOUNDER_PHASE_GATE"
    truth["task_history"].delete_if do |_key, record|
      record.is_a?(Hash) && record["task_id"] == final_task["task_id"]
    end
    truth["task_history"]["structured_final_task_gate"] = gate_evidence
    commit_truth(fixture, truth, "test: complete structured route at Founder Phase Gate")
    fixture
  end

  def accepted_gate_evidence_for_fixture(fixture)
    truth = yaml(fixture["truth_path"])
    {
      "task_id" => truth.dig("active_work", "current_task"),
      "route_id" => truth.dig("current_phase_route", "route_id"),
      "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      "contract" => truth.dig("active_work", "current_task_contract", "path"),
      "task_contract_sha256" => truth.dig("active_work", "current_task_contract", "sha256"),
      "accepted_candidate_commit" => shell(fixture["repo"], "git", "rev-parse", "HEAD").strip,
      "accepted_candidate_tree" => shell(fixture["repo"], "git", "rev-parse", "HEAD^{tree}").strip,
      "cto_target_verdict" => "PASS",
      "security_target_verdict" => "PASS",
      "quality_target_verdict" => "PASS",
      "reviewed_tree_equals_integrated_tree" => true,
      "canonical_make_verify" => "PASS"
    }
  end

  def remove_fixture_task_resources(fixture)
    shell(fixture["repo"], "git", "worktree", "remove", fixture["task_worktree"])
    shell(fixture["repo"], "git", "branch", "-d", fixture["task_branch"])
  end

  def structured_automatic_entry_tests(sandbox)
    terminal = prepare_structured_fixture(File.join(sandbox, "terminal-predecessor"))
    terminal = transition_to_second_task_ready(
      terminal,
      predecessor_status: "TERMINAL_NON_PASS"
    )
    expect_nonpass(
      terminal["repo"],
      "structured Task 2 READY after Task 1 NON_PASS",
      /accepted prefix is incomplete/
    )
    terminal = activate_fixture(terminal, task_slot: 2)
    expect_nonpass(
      terminal["repo"],
      "structured Task 2 ACTIVE after Task 1 NON_PASS",
      /accepted prefix is incomplete/
    )
    remove_fixture_task_resources(terminal)

    missing = prepare_structured_fixture(File.join(sandbox, "missing-gate-evidence"))
    missing = transition_to_second_task_ready(
      missing,
      predecessor_status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
    )
    expect_nonpass(
      missing["repo"],
      "structured Task 2 READY without accepted Gate Evidence",
      /must map to exactly one top-level task_history record/
    )
    missing = activate_fixture(missing, task_slot: 2)
    expect_nonpass(
      missing["repo"],
      "structured Task 2 ACTIVE without accepted Gate Evidence",
      /must map to exactly one top-level task_history record/
    )
    remove_fixture_task_resources(missing)

    accepted = prepare_structured_fixture(File.join(sandbox, "accepted-predecessor"))
    accepted = activate_fixture(accepted)
    gate_evidence = accepted_gate_evidence_for_fixture(accepted)
    remove_fixture_task_resources(accepted)
    accepted = transition_to_second_task_ready(
      accepted,
      predecessor_status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      gate_evidence: gate_evidence
    )
    expect_pass(accepted["repo"], "structured Task 2 READY after exact Task 1 Gate PASS")
    accepted = activate_fixture(accepted, task_slot: 2)
    expect_pass(accepted["repo"], "structured Task 2 ACTIVE after exact Task 1 Gate PASS")
    remove_fixture_task_resources(accepted)
  end

  def structured_zero_repair_lifecycle_tests(sandbox)
    decision = JSON.parse(File.binread(STRUCTURED_DECISION_PATH))
    decision["envelope"]["max_same_task_repairs_per_task"] = 0
    decision["ordered_tasks"].each do |task|
      task["max_same_task_repairs"] = 0
      task["max_implementation_iterations"] = 1
    end
    fixture = prepare_structured_fixture(
      File.join(sandbox, "zero-repair-lifecycle"),
      decision_override: decision
    )
    expect_pass(fixture["repo"], "structured zero-repair READY Decision to Truth")
    expect_safety_pass(fixture["repo"], fixture["truth_path"], "structured zero-repair READY safety")
    fixture = activate_fixture(fixture)
    expect_pass(fixture["repo"], "structured zero-repair ACTIVE Contract and authority")
    expect_safety_pass(fixture["repo"], fixture["truth_path"], "structured zero-repair ACTIVE safety")
    remove_fixture_task_resources(fixture)
  end

  def structured_task_specific_repair_lifecycle_tests(sandbox)
    decision = JSON.parse(File.binread(STRUCTURED_DECISION_PATH))
    decision["envelope"]["max_same_task_repairs_per_task"] = 8
    decision["ordered_tasks"][0]["max_same_task_repairs"] = 8
    decision["ordered_tasks"][0]["max_implementation_iterations"] = 9
    decision["ordered_tasks"][1]["max_same_task_repairs"] = 2
    decision["ordered_tasks"][1]["max_implementation_iterations"] = 3
    fixture = prepare_structured_fixture(
      File.join(sandbox, "task-specific-repair-lifecycle"),
      decision_override: decision
    )
    expect_pass(fixture["repo"], "structured Task-specific repair READY Decision to Truth")
    expect_safety_pass(
      fixture["repo"],
      fixture["truth_path"],
      "structured Task-specific repair READY safety"
    )
    fixture = activate_fixture(fixture)
    expect_pass(fixture["repo"], "structured Task 1 eight-repair ACTIVE Contract and authority")
    expect_safety_pass(
      fixture["repo"],
      fixture["truth_path"],
      "structured Task 1 eight-repair ACTIVE safety"
    )
    gate_evidence = accepted_gate_evidence_for_fixture(fixture)
    remove_fixture_task_resources(fixture)
    fixture = transition_to_second_task_ready(
      fixture,
      predecessor_status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      gate_evidence: gate_evidence
    )
    expect_pass(fixture["repo"], "structured Task 2 two-repair READY after Task 1 Gate PASS")
    fixture = activate_fixture(fixture, task_slot: 2)
    expect_pass(fixture["repo"], "structured Task 2 two-repair ACTIVE Contract and authority")
    expect_safety_pass(
      fixture["repo"],
      fixture["truth_path"],
      "structured Task 2 two-repair ACTIVE safety"
    )
    remove_fixture_task_resources(fixture)
  end

  def structured_external_effect_binding_tests(sandbox)
    decision = JSON.parse(File.binread(STRUCTURED_DECISION_PATH))
    decision["external_effects"]["network"] = true
    decision["external_effects"]["provider"] = true
    decision["external_effects"]["secret"] = true
    fixture = prepare_structured_fixture(
      File.join(sandbox, "data-driven-effects"),
      decision_override: decision
    )
    expect_pass(fixture["repo"], "structured Founder effects READY exact binding")

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["envelope"]["external_effects"]["network"] = false
    commit_truth(fixture, truth, "test: structured Truth effect drift")
    expect_nonpass(fixture["repo"], "structured Truth effect drift",
                   /does not equal the exact authorized external-effect map/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["envelope"]["external_effects"]["network"] = true
    commit_truth(fixture, truth, "test: restore structured Truth effect")

    fixture = activate_fixture(fixture)
    expect_pass(fixture["repo"], "structured Founder effects ACTIVE exact binding")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["external_effects"]["provider"] = false
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: structured Contract effect drift")
    expect_nonpass(fixture["repo"], "structured Contract effect drift",
                   /contract external_effects does not equal/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["external_effects"]["provider"] = true
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore structured Contract effect")

    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["external_effects"]["secret"] = false
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: structured authority effect drift")
    expect_nonpass(fixture["repo"], "structured authority effect drift",
                   /authority external_effects does not equal/)
    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["external_effects"]["secret"] = true
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: restore structured authority effect")

    truth = yaml(fixture["truth_path"])
    truth["active_work"]["external_effects"]["network"] = false
    commit_truth(fixture, truth, "test: structured active Truth effect drift")
    expect_nonpass(fixture["repo"], "structured active Truth effect drift",
                   /active_work.external_effects does not equal/)
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["external_effects"]["network"] = true
    commit_truth(fixture, truth, "test: restore structured active Truth effect")
    expect_pass(fixture["repo"], "structured effects Decision Truth Contract authority restored")
    remove_fixture_task_resources(fixture)
  end

  def structured_v1_1_three_task_lifecycle_tests(sandbox)
    decision = structured_v1_1_decision(sandbox)
    fixture = prepare_structured_fixture(
      File.join(sandbox, "v1-1-three-task-lifecycle"),
      decision_override: decision
    )
    expect_pass(fixture["repo"], "structured v1.1 three-Task READY route")
    expect_safety_pass(fixture["repo"], fixture["truth_path"], "structured v1.1 READY safety")

    ready_truth = yaml(fixture["truth_path"])
    mutated = deep_copy(ready_truth)
    mutated["current_phase_route"]["task_plan"][2]["status"] = "ACTIVE"
    commit_truth(fixture, mutated, "test: structured v1.1 premature future ACTIVE")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 READY rejects premature future ACTIVE",
      /state vector/
    )
    commit_truth(fixture, ready_truth, "test: restore structured v1.1 initial READY vector")

    mutated = deep_copy(ready_truth)
    mutated["current_phase_route"]["task_plan"][1]["status"] = "ELIGIBLE_NOT_ACTIVATED"
    commit_truth(fixture, mutated, "test: structured v1.1 duplicate eligible Task")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 READY rejects duplicate eligible Tasks",
      /state vector|exactly one eligible/
    )
    commit_truth(fixture, ready_truth, "test: restore structured v1.1 unique eligible Task")

    fixture = activate_fixture(fixture, task_slot: 1)
    expect_pass(fixture["repo"], "structured v1.1 offline Task 1 ACTIVE")
    assert(yaml(fixture["truth_path"]).dig("active_work", "external_effects") == false_effects,
           "structured v1.1 Task 1 effects were not narrowed to offline")
    active_one_truth = yaml(fixture["truth_path"])
    mutated = deep_copy(active_one_truth)
    mutated["current_phase_route"]["active_task"] = {
      "task_id" => decision["ordered_tasks"][1]["task_id"],
      "task_slot" => 2,
      "status" => "ACTIVE",
      "contract_path" => "docs/aios/tasks/P2-008_SECOND_TASK.yaml",
      "max_engineering_hours" => decision["ordered_tasks"][1]["engineering_hours"],
      "max_calendar_days" => decision["ordered_tasks"][1]["calendar_days"],
      "max_implementation_iterations" =>
        decision["ordered_tasks"][1]["max_implementation_iterations"],
      "max_candidates" => decision["ordered_tasks"][1]["max_candidates"]
    }
    commit_truth(fixture, mutated, "test: structured v1.1 first Task duplicate active descriptor")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 first Task rejects duplicate active_task descriptor",
      /first Task must not retain/
    )
    commit_truth(fixture, active_one_truth, "test: restore structured v1.1 first Task descriptor state")
    gate_one = accepted_gate_evidence_for_fixture(fixture)
    remove_fixture_task_resources(fixture)

    fixture = transition_to_later_task_ready(
      fixture,
      task_slot: 2,
      predecessor_status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      gate_evidence: gate_one
    )
    expect_pass(fixture["repo"], "structured v1.1 Task 2 READY after exact Task 1 Gate PASS")
    fixture = activate_fixture(fixture, task_slot: 2)
    expect_pass(fixture["repo"], "structured v1.1 Provider Task 2 ACTIVE")
    task_two_effects = decision["ordered_tasks"][1]["external_effects"]
    active_two_truth = yaml(fixture["truth_path"])
    assert(active_two_truth.dig("active_work", "external_effects") == task_two_effects,
           "structured v1.1 Task 2 effects do not equal its exact Decision map")
    expected_profile = decision["ordered_tasks"][1]["founder_reserved_profile"]
    assert(yaml(fixture["contract_path"])["founder_reserved_profile"] == expected_profile,
           "structured v1.1 Task 2 Contract profile does not equal the Decision")
    assert(yaml(fixture["authority_path"])["founder_reserved_profile"] == expected_profile,
           "structured v1.1 Task 2 authority profile does not equal the Decision")
    assert(expected_profile.dig("call_limits") == {
      "diagnostic_requests_max" => 1,
      "formal_requests_exact" => 36,
      "provider_requests_max" => 37,
      "automatic_retry_max" => 0
    }, "structured v1.1 exact 37-request accounting drifted")

    mutated = deep_copy(active_two_truth)
    mutated["current_phase_route"]["active_task"]["status"] = "ELIGIBLE_NOT_ACTIVATED"
    commit_truth(fixture, mutated, "test: structured v1.1 active_task status drift")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 later active_task descriptor must remain ACTIVE",
      /descriptor status must equal ACTIVE/
    )
    commit_truth(fixture, active_two_truth, "test: restore structured v1.1 active_task status")

    mutated = deep_copy(active_two_truth)
    mutated["current_phase_route"]["task_plan"][2]["status"] = "ACTIVE"
    commit_truth(fixture, mutated, "test: structured v1.1 duplicate ACTIVE Task")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 ACTIVE rejects a second ACTIVE Task",
      /state vector/
    )
    commit_truth(fixture, active_two_truth, "test: restore structured v1.1 unique ACTIVE Task")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["founder_reserved_profile"]["call_limits"]["provider_requests_max"] = 38
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: structured v1.1 Contract Provider total drift")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 Contract rejects 38-request drift",
      /exact diagnostic plus formal request total/
    )
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["founder_reserved_profile"]["call_limits"]["provider_requests_max"] = 37
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore structured v1.1 Contract Provider total")

    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["founder_reserved_profile"]["call_limits"]["automatic_retry_max"] = 1
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: structured v1.1 authority retry drift")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 authority rejects automatic retry",
      /automatic_retry_max must equal 0/
    )
    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["founder_reserved_profile"]["call_limits"]["automatic_retry_max"] = 0
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: restore structured v1.1 authority retry ceiling")

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["founder_reserved_profiles"][0]["model"]["requested_model"] =
      "drifted-model"
    commit_truth(fixture, truth, "test: structured v1.1 Truth model drift")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 Truth rejects model drift",
      /does not equal the exact structured decision/
    )
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["founder_reserved_profiles"][0]["model"]["requested_model"] =
      expected_profile.dig("model", "requested_model")
    commit_truth(fixture, truth, "test: restore structured v1.1 Truth model binding")
    expect_pass(fixture["repo"], "structured v1.1 Provider profile bindings restored")

    gate_two = accepted_gate_evidence_for_fixture(fixture)
    remove_fixture_task_resources(fixture)

    fixture = transition_to_later_task_ready(
      fixture,
      task_slot: 3,
      predecessor_status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      gate_evidence: gate_two
    )
    expect_pass(fixture["repo"], "structured v1.1 Task 3 READY after exact Task 2 Gate PASS")

    ready_three_truth = yaml(fixture["truth_path"])
    mutated = deep_copy(ready_three_truth)
    mutated["current_phase_route"]["first_task"]["status"] = "TERMINAL_NON_PASS"
    mutated["current_phase_route"]["task_plan"][0]["status"] = "TERMINAL_NON_PASS"
    mutated["task_history"].delete_if do |_key, record|
      record.is_a?(Hash) && record["task_id"] == decision["ordered_tasks"][0]["task_id"]
    end
    commit_truth(fixture, mutated, "test: structured v1.1 erase accepted Task 1 prefix")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 Task 3 rejects incomplete accepted prefix",
      /accepted prefix is incomplete/
    )
    commit_truth(fixture, ready_three_truth, "test: restore structured v1.1 accepted Task 1 prefix")

    mutated = deep_copy(ready_three_truth)
    mutated["current_phase_route"]["task_plan"][1]["status"] = "TERMINAL_NON_PASS"
    commit_truth(fixture, mutated, "test: structured v1.1 Task 2 NON_PASS before Task 3")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 Task 3 rejects Task 2 NON_PASS",
      /accepted prefix is incomplete/
    )
    commit_truth(fixture, ready_three_truth, "test: restore structured v1.1 accepted Task 2")

    mutated = deep_copy(ready_three_truth)
    task_one_id = decision["ordered_tasks"][0]["task_id"]
    task_two_id = decision["ordered_tasks"][1]["task_id"]
    task_two_history = mutated["task_history"].values.find do |record|
      record.is_a?(Hash) && record["task_id"] == task_two_id
    end
    assert(task_two_history, "structured v1.1 Task 2 history fixture is missing")
    mutated["task_history"].delete_if do |_key, record|
      record.is_a?(Hash) && record["task_id"] == task_one_id
    end
    aliased_history = deep_copy(task_two_history)
    aliased_history["task_id"] = task_one_id
    mutated["task_history"]["structured_cross_task_gate_alias"] = aliased_history
    commit_truth(fixture, mutated, "test: structured v1.1 cross-Task Gate artifact alias")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 accepted prefix rejects cross-Task Gate artifact alias",
      /contract task_id mismatch/
    )
    commit_truth(fixture, ready_three_truth, "test: restore structured v1.1 exact accepted Gate histories")

    fixture = activate_fixture(fixture, task_slot: 3)
    expect_pass(fixture["repo"], "structured v1.1 offline Task 3 ACTIVE")
    assert(yaml(fixture["truth_path"]).dig("active_work", "external_effects") == false_effects,
           "structured v1.1 Task 3 effects were not narrowed to offline")
    gate_three = accepted_gate_evidence_for_fixture(fixture)
    remove_fixture_task_resources(fixture)
    fixture = transition_to_route_complete(
      fixture,
      final_status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      gate_evidence: gate_three
    )
    expect_pass_state(
      fixture["repo"],
      "structured v1.1 completed route Founder Phase Gate",
      "PHASE_GATE_READY"
    )
    expect_safety_pass(
      fixture["repo"],
      fixture["truth_path"],
      "structured v1.1 completed route safety"
    )
    complete_truth = yaml(fixture["truth_path"])

    mutated = deep_copy(complete_truth)
    mutated["current_phase_route"]["next_eligible_action"] = "MASTER_ACTIVATE_NEXT_TASK"
    mutated["active_work"]["next_eligible_action"] = "MASTER_ACTIVATE_NEXT_TASK"
    commit_truth(fixture, mutated, "test: structured v1.1 completed route wrong next action")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 completed route requires exact Founder Phase Gate action",
      /must be FOUNDER_PHASE_GATE/
    )
    commit_truth(fixture, complete_truth, "test: restore structured v1.1 Founder Phase Gate action")

    mutated = deep_copy(complete_truth)
    mutated["active_work"]["founder_decision_required"] = false
    commit_truth(fixture, mutated, "test: structured v1.1 completed route Founder flag drift")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 completed route requires Founder decision flag",
      /requires Founder Phase Gate decision/
    )
    commit_truth(fixture, complete_truth, "test: restore structured v1.1 Founder decision flag")

    mutated = deep_copy(complete_truth)
    mutated["active_work"]["user_action_required"] = "NONE"
    commit_truth(fixture, mutated, "test: structured v1.1 completed route user action drift")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 completed route requires exact user action",
      /user_action_required mismatch/
    )
    commit_truth(fixture, complete_truth, "test: restore structured v1.1 Founder user action")

    mutated = deep_copy(complete_truth)
    mutated["project"]["phase_execution_status"] = "ACTIVE"
    commit_truth(fixture, mutated, "test: structured v1.1 completed route project status drift")
    expect_nonpass(
      fixture["repo"],
      "structured v1.1 completed route requires stopped project status",
      /requires project Founder Phase Gate status/
    )
    commit_truth(fixture, complete_truth, "test: restore structured v1.1 Founder Gate project status")
  end

  def activate_fixture(fixture, task_slot: 1)
    repo = fixture["repo"]
    truth_path = fixture["truth_path"]
    truth = yaml(truth_path)
    route = truth.fetch("current_phase_route")
    if task_slot == 1
      task = route.fetch("first_task")
    else
      plan = route.fetch("task_plan").fetch(task_slot - 1)
      task = {
        "task_id" => plan.fetch("task_id"),
        "task_slot" => plan.fetch("task_slot"),
        "status" => "ACTIVE",
        "contract_path" => "docs/aios/tasks/#{plan.fetch('task_id').delete_prefix('AIOS-')}.yaml",
        "max_engineering_hours" => plan.fetch("engineering_hours"),
        "max_calendar_days" => plan.fetch("calendar_days"),
        "max_implementation_iterations" => plan.fetch("max_implementation_iterations"),
        "max_candidates" => plan.fetch("max_candidates")
      }
      route["active_task"] = deep_copy(task)
    end
    task_id = task.fetch("task_id")
    structured_decision = fixture["structured_decision"]
    task_effects = if structured_decision && structured_decision["schema_version"] == "1.1"
                     deep_copy(
                       structured_decision.fetch("ordered_tasks")
                         .fetch(task_slot - 1).fetch("external_effects")
                     )
                   else
                     deep_copy(truth.fetch("current_phase_route").fetch("envelope").fetch("external_effects"))
                   end
    task_profile = if structured_decision && structured_decision["schema_version"] == "1.1"
                     deep_copy(
                       structured_decision.fetch("ordered_tasks")
                         .fetch(task_slot - 1).fetch("founder_reserved_profile")
                     )
                   else
                     deep_copy(truth.dig("current_phase_route", "founder_reserved_profile"))
                   end
    phase = truth.dig("project", "current_phase")
    route_id = truth.fetch("current_phase_route").fetch("route_id")
    contract_relative = task.fetch("contract_path")
    contract_path = File.join(repo, contract_relative)
    FileUtils.mkdir_p(File.dirname(contract_path))

    budget = {
      "engineering_hours" => task.fetch("max_engineering_hours"),
      "calendar_days" => task.fetch("max_calendar_days"),
      "implementation_iterations" => task.fetch("max_implementation_iterations"),
      "candidates" => task.fetch("max_candidates")
    }
    roles = {
      "owner" => "Fixture Master",
      "worker" => "Fixture Worker",
      "independent_reviewers" => ["Fixture CTO", "Fixture Security", "Fixture Quality"]
    }
    allowlisted = ["evaluation-harness/harness/local-patch-control/**", "scripts/verify-fixture-task.sh"]
    contract = {
      "schema_version" => 1,
      "record_type" => "aios_phase_local_task_contract",
      "task_id" => task_id,
      "phase" => phase,
      "route_id" => route_id,
      "status" => "ACTIVE",
      "objective" => "Run one bounded local-gateway finite-IR fixture task.",
      "why_now" => "Exercise the exact Founder-reserved authority path without network in this fixture.",
      "budget" => budget,
      "roles" => roles,
      "allowlisted_paths" => allowlisted,
      "external_effects" => deep_copy(task_effects),
      "founder_reserved_authorization" => {
        "path" => truth.dig("current_phase_route", "decision_packet", "path"),
        "sha256" => truth.dig("current_phase_route", "decision_packet", "sha256"),
        "byte_length" => truth.dig("current_phase_route", "decision_packet", "byte_length"),
        "authorization_token" => truth.dig("current_phase_route", "authorization_token")
      },
      "goal_identity" => deep_copy(truth.dig("current_phase_route", "goal_identity")),
      "founder_reserved_profile" => deep_copy(task_profile),
      "acceptance_criteria" => ["exact bounded fixture passes"],
      "required_evidence" => ["fixture receipt"],
      "stop_conditions" => ["authority drift"],
      "forbidden_actions" => ["network"]
    }
    if File.exist?(contract_path)
      register_owned(contract_path)
      rewrite_owned(contract_path, YAML.dump(contract))
    else
      create_exclusive(contract_path, YAML.dump(contract))
    end
    contract_bytes = File.binread(contract_path)
    contract_sha = Digest::SHA256.hexdigest(contract_bytes)

    branch = task_slot == 1 ? "codex/test-current-authority-active" :
      "codex/test-current-authority-active-slot-#{task_slot}"
    worktree = File.join(fixture["worktree_root"], "active-slot-#{task_slot}")
    evidence = File.join(fixture["evidence_base"], "active-task-slot-#{task_slot}")
    FileUtils.mkdir_p(evidence)
    authorization_id = Digest::SHA256.hexdigest("#{task_id}:fixture-authority")
    parent_commit = shell(repo, "git", "rev-parse", "HEAD").strip
    parent_tree = shell(repo, "git", "rev-parse", "HEAD^{tree}").strip
    authority_path = File.join(fixture["external"], "task-authority-slot-#{task_slot}.yaml")
    authority = {
      "schema_version" => 1,
      "record_type" => "aios_phase_delegated_task_authority",
      "task_id" => task_id,
      "phase" => phase,
      "route_id" => route_id,
      "status" => "ACTIVE",
      "authorization_id" => authorization_id,
      "task_contract_sha256" => contract_sha,
      "execution_nonce" => Digest::SHA256.hexdigest("#{task_id}:fixture-nonce"),
      "activation_parent" => { "commit" => parent_commit, "tree" => parent_tree },
      "branch" => branch,
      "worktree" => worktree,
      "evidence_root" => evidence,
      "budget" => budget,
      "roles" => roles,
      "allowlisted_paths" => allowlisted,
      "external_effects" => deep_copy(task_effects),
      "founder_reserved_authorization" => deep_copy(contract.fetch("founder_reserved_authorization")),
      "goal_identity" => deep_copy(truth.dig("current_phase_route", "goal_identity")),
      "founder_reserved_profile" => deep_copy(task_profile)
    }
    create_exclusive(authority_path, YAML.dump(authority))
    authority_bytes = File.binread(authority_path)
    authority_sha = Digest::SHA256.hexdigest(authority_bytes)

    truth["goal"]["current_task_authority"] = task_id
    truth["project"]["phase_execution_status"] = "ACTIVE"
    truth["project"]["#{phase.downcase}_execution_status"] = "ACTIVE"
    truth["current_phase_route"]["status"] = "ACTIVE"
    if task_slot == 1
      truth["current_phase_route"]["first_task"]["status"] = "ACTIVE"
    else
      truth["current_phase_route"]["active_task"]["status"] = "ACTIVE"
    end
    truth["current_phase_route"]["task_plan"][task_slot - 1]["status"] = "ACTIVE"
    truth["current_phase_route"]["next_eligible_action"] = "CONTINUE_CURRENT_TASK"
    truth["active_work"] = {
      "current_task" => task_id,
      "current_task_status" => "ACTIVE",
      "current_task_contract" => {
        "path" => contract_relative,
        "sha256" => contract_sha,
        "byte_length" => contract_bytes.bytesize
      },
      "current_task_contract_sha256" => contract_sha,
      "current_execution_authorization" => authority_path,
      "current_execution_authorization_sha256" => authority_sha,
      "authority_record" => {
        "path" => authority_path,
        "sha256" => authority_sha,
        "byte_length" => authority_bytes.bytesize
      },
      "execution_nonce" => Digest::SHA256.hexdigest("#{task_id}:fixture-nonce"),
      "execution_nonce_status" => "ACTIVE",
      "authorization_id" => authorization_id,
      "activation_parent_commit" => parent_commit,
      "activation_parent_tree" => parent_tree,
      "task_resource_state" => "ACTIVE",
      "task_branch" => branch,
      "task_worktree" => worktree,
      "execution_evidence_root" => evidence,
      "allowlisted_paths" => allowlisted,
      "budget" => budget,
      "roles" => roles,
      "external_effects" => deep_copy(task_effects),
      "offsite_target" => nil,
      "founder_reserved_authorization" => truth.dig("current_phase_route", "decision_packet", "path"),
      "founder_reserved_authorization_sha256" => truth.dig("current_phase_route", "decision_packet", "sha256"),
      "founder_decision_required" => false,
      "escalation_reason" => nil,
      "user_action_required" => "NONE",
      "next_eligible_action" => "CONTINUE_CURRENT_TASK"
    }
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: activate generic phase-local task")
    shell(repo, "git", "worktree", "add", "--quiet", "-b", branch, worktree, "HEAD")

    fixture.merge(
      "task_id" => task_id,
      "contract_path" => contract_path,
      "contract_bytes" => contract_bytes,
      "authority_path" => authority_path,
      "authority_bytes" => authority_bytes,
      "task_worktree" => worktree,
      "task_branch" => branch
    )
  end

  def bind_authority_to_truth(fixture, truth, authority)
    dump_owned_yaml(fixture["authority_path"], authority)
    bytes = File.binread(fixture["authority_path"])
    sha = Digest::SHA256.hexdigest(bytes)
    truth["active_work"]["current_execution_authorization_sha256"] = sha
    truth["active_work"]["authority_record"] = {
      "path" => fixture["authority_path"],
      "sha256" => sha,
      "byte_length" => bytes.bytesize
    }
  end

  def bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    dump_owned_yaml(fixture["contract_path"], contract)
    bytes = File.binread(fixture["contract_path"])
    sha = Digest::SHA256.hexdigest(bytes)
    truth["active_work"]["current_task_contract"] = {
      "path" => truth.dig("active_work", "current_task_contract", "path"),
      "sha256" => sha,
      "byte_length" => bytes.bytesize
    }
    truth["active_work"]["current_task_contract_sha256"] = sha
    authority["task_contract_sha256"] = sha
    bind_authority_to_truth(fixture, truth, authority)
  end

  def commit_truth(fixture, truth, message)
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(fixture["repo"], message)
  end

  def expect_dual_nonpass(fixture, label, pattern)
    expect_nonpass(fixture["repo"], "#{label} main", pattern)
    expect_safety_nonpass(fixture["repo"], fixture["truth_path"], "#{label} safety", pattern)
  end

  def active_tests(fixture)
    repo = fixture["repo"]
    expect_pass(repo, "mapping-only roles active Task")
    expect_safety_pass(repo, fixture["truth_path"], "mapping-only roles active Task safety")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    original_owner = contract.fetch("roles").fetch("owner")
    contract["roles"]["owner"] = "Fixture Contract Drift"
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: drift Contract role mapping")
    expect_dual_nonpass(fixture, "Contract role mismatch", /contract roles mismatch/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["roles"]["owner"] = original_owner
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore Contract role mapping")
    expect_pass(repo, "Contract role mapping restored")
    expect_safety_pass(repo, fixture["truth_path"], "Contract role mapping safety restored")

    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    original_owner = authority.fetch("roles").fetch("owner")
    authority["roles"]["owner"] = "Fixture Authority Drift"
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: drift Authority role mapping")
    expect_dual_nonpass(fixture, "Authority role mismatch", /authority record roles mismatch/)
    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["roles"]["owner"] = original_owner
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: restore Authority role mapping")
    expect_pass(repo, "Authority role mapping restored")
    expect_safety_pass(repo, fixture["truth_path"], "Authority role mapping safety restored")

    truth = yaml(fixture["truth_path"])
    original_owner = truth.dig("active_work", "roles", "owner")
    truth["active_work"]["roles"]["owner"] = "Fixture Truth Drift"
    commit_truth(fixture, truth, "test: drift Truth role mapping")
    expect_dual_nonpass(fixture, "Truth role mismatch", /contract roles mismatch/)
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["roles"]["owner"] = original_owner
    commit_truth(fixture, truth, "test: restore Truth role mapping")
    expect_pass(repo, "Truth role mapping restored")
    expect_safety_pass(repo, fixture["truth_path"], "Truth role mapping safety restored")

    original = tamper_owned_byte(fixture["authority_path"])
    expect_nonpass(repo, "authority record byte tamper", /authority record SHA-256 mismatch/)
    restore_owned_byte(fixture["authority_path"], original)

    original = tamper_owned_byte(fixture["contract_path"])
    shell(repo, "git", "add", fixture["contract_path"])
    shell(repo, "git", "commit", "-m", "test: tamper owned contract bytes")
    expect_nonpass(repo, "Task Contract byte tamper", /active Task contract SHA-256 mismatch/)
    restore_owned_byte(fixture["contract_path"], original)
    commit(repo, "test: restore owned contract bytes")

    truth = yaml(fixture["truth_path"])
    original_network = truth["active_work"]["external_effects"]["network"]
    truth["active_work"]["external_effects"]["network"] = !original_network
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: set unauthorized external effect")
    expect_dual_nonpass(fixture, "unauthorized network-effect drift",
                        /exact authorized external-effect map/)
    truth["active_work"]["external_effects"]["network"] = original_network
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore external effects")

    truth = yaml(fixture["truth_path"])
    original_hours = truth["active_work"]["budget"]["engineering_hours"]
    truth["active_work"]["budget"]["engineering_hours"] = original_hours + 1
    commit_truth(fixture, truth, "test: drift active Task budget")
    expect_dual_nonpass(
      fixture,
      "active budget mismatch",
      /contract budget mismatch|active budget engineering_hours exceeds envelope|active Task budget does not equal the structured Founder decision/
    )
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["budget"]["engineering_hours"] = original_hours
    commit_truth(fixture, truth, "test: restore active Task budget")

    truth = yaml(fixture["truth_path"])
    original_repairs = truth["current_phase_route"]["envelope"]["max_same_task_repairs"]
    truth["current_phase_route"]["envelope"]["max_same_task_repairs"] = original_repairs + 1
    commit_truth(fixture, truth, "test: expand repair allowance")
    expect_dual_nonpass(fixture, "repair allowance mismatch", /max_same_task_repairs does not match/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["envelope"]["max_same_task_repairs"] = original_repairs
    commit_truth(fixture, truth, "test: restore repair allowance")

    truth = yaml(fixture["truth_path"])
    truth["active_work"]["allowlisted_paths"] << "README.md"
    commit_truth(fixture, truth, "test: grant path outside reviewed Contract")
    expect_dual_nonpass(fixture, "allowlisted path mismatch", /outside the reviewed Contract maximum scope/)
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["allowlisted_paths"].delete("README.md")
    commit_truth(fixture, truth, "test: restore allowlisted paths")

    truth = yaml(fixture["truth_path"])
    truth["phase_boundary"]["allowed_capabilities"] << "AGENT_SHELL"
    commit_truth(fixture, truth, "test: admit deferred capability")
    expect_pass(repo, "authority core does not duplicate deferred-capability policy")
    expect_safety_nonpass(repo, fixture["truth_path"], "safety rejects deferred capability",
                          /P[12] admits a deferred capability/)
    truth = yaml(fixture["truth_path"])
    truth["phase_boundary"]["allowed_capabilities"].delete("AGENT_SHELL")
    commit_truth(fixture, truth, "test: restore deferred capability boundary")
    expect_pass(repo, "deferred capability boundary restored")
    expect_safety_pass(repo, fixture["truth_path"], "deferred capability safety restored")

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["additional_write_roots"] << "outside-p1-owned-root"
    commit_truth(fixture, truth, "test: add route write root outside Phase boundary")
    expect_pass(repo, "authority core leaves P1 write-root policy to safety")
    expect_safety_nonpass(repo, fixture["truth_path"], "safety rejects out-of-bound write root",
                          /route write root is outside the P[12] boundary/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["additional_write_roots"].delete("outside-p1-owned-root")
    commit_truth(fixture, truth, "test: restore route write roots")
    expect_pass(repo, "route write roots restored")
    expect_safety_pass(repo, fixture["truth_path"], "route write-root safety restored")

    truth = yaml(fixture["truth_path"])
    truth["task_history"]["fixture_reuse"] = { "task_id" => fixture["task_id"], "status" => "HISTORICAL" }
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: inject historical Task id collision")
    expect_nonpass(repo, "historical Task id reuse", /reuses historical|reuses a historical/)
    truth["task_history"].delete("fixture_reuse")
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: remove historical Task id collision")

    extra = File.join(fixture["worktree_root"], "extra")
    shell(repo, "git", "worktree", "add", "--quiet", "-b", "codex/test-current-authority-extra", extra, "HEAD")
    expect_nonpass(repo, "undeclared extra worktree", /Git worktree set does not equal/)
    shell(repo, "git", "worktree", "remove", extra)
    shell(repo, "git", "branch", "-d", "codex/test-current-authority-extra")
    expect_pass(repo, "active Task after owned extra worktree cleanup")

    current_claims = CurrentTaskAuthority.packet_claims(File.binread(fixture["packet_path"]))
    structured_gate_evidence =
      accepted_gate_evidence_for_fixture(fixture) if current_claims["structured_decision"]
    shell(repo, "git", "worktree", "remove", fixture["task_worktree"])
    shell(repo, "git", "branch", "-d", fixture["task_branch"])
    truth = yaml(fixture["truth_path"])
    truth["goal"]["current_task_authority"] = "NONE"
    truth["project"]["phase_execution_status"] = "ACTIVE"
    phase = truth.dig("project", "current_phase")
    truth["project"]["#{phase.downcase}_execution_status"] = "ACTIVE"
    truth["current_phase_route"]["status"] = "ACTIVE"
    truth["current_phase_route"]["first_task"]["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
    truth["current_phase_route"].delete("active_task")
    if structured_gate_evidence
      truth["current_phase_route"]["task_plan"][0]["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
      truth["current_phase_route"]["task_plan"][1]["status"] = "ELIGIBLE_NOT_ACTIVATED"
      truth["current_phase_route"]["next_eligible_action"] = "MASTER_ACTIVATE_NEXT_TASK"
      truth["task_history"]["fixture_completed_first_task"] = structured_gate_evidence
    else
      truth["current_phase_route"]["next_eligible_action"] = "MASTER_SELECT_NEXT_PHASE_LOCAL_TASK"
      truth["task_history"]["fixture_completed_first_task"] = {
        "task_id" => fixture["task_id"],
        "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
      }
    end
    truth["active_work"] = ready_active_work
    truth["active_work"]["task_resource_state"] = "NONE_PHASE_ACTIVE"
    truth["active_work"]["external_effects"] =
      deep_copy(truth.dig("current_phase_route", "envelope", "external_effects"))
    truth["active_work"]["next_eligible_action"] =
      structured_gate_evidence ? "MASTER_ACTIVATE_NEXT_TASK" : "MASTER_SELECT_NEXT_PHASE_LOCAL_TASK"
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: enter between-Task active Phase idle")
    expect_pass(repo, "between-Task active Phase with Task NONE")
  end

  def run
    sandbox = Dir.mktmpdir("sourcelens-current-authority-")
    sandbox_identity = nil
    begin
      structured_decision_unit_tests(sandbox)
      provider_profile_unit_tests
      closed_profile_packet_unit_tests
      p1_ready_and_active_golden_regression_tests(sandbox)
      structured_route_binding_tests(sandbox)
      structured_automatic_entry_tests(sandbox)
      structured_zero_repair_lifecycle_tests(sandbox)
      structured_task_specific_repair_lifecycle_tests(sandbox)
      structured_external_effect_binding_tests(sandbox)
      structured_v1_1_three_task_lifecycle_tests(sandbox)
      sandbox_stat = File.lstat(sandbox)
      assert(sandbox_stat.directory? && !sandbox_stat.symlink?, "temporary root is not an owned directory")
      sandbox_identity = [sandbox_stat.dev, sandbox_stat.ino]
      fixture = prepare_fixture(sandbox)
      ready_tests(fixture)
      fixture = activate_fixture(fixture)
      active_tests(fixture)
    ensure
      if sandbox_identity
        current = File.lstat(sandbox)
        assert(current.directory? && !current.symlink? && [current.dev, current.ino] == sandbox_identity,
               "temporary root identity changed before cleanup")
        FileUtils.remove_entry_secure(sandbox)
      end
    end
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

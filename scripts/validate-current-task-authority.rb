#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "time"
require "yaml"

class AuthorityValidationError < StandardError
  attr_reader :category

  def initialize(message, category: "VALIDATION")
    @category = category
    super(message)
  end
end

module CurrentTaskAuthority
  module_function

  SHA256_RE = /\A[0-9a-f]{64}\z/.freeze
  COMMIT_RE = /\A[0-9a-f]{40}\z/.freeze
  SAFE_TASK_ID_RE = /\AAIOS-P1-[0-9]{3}(?:_[A-Z0-9_]+)?\z/.freeze
  EXTERNAL_EFFECT_KEYS = %w[network provider secret remote production public].freeze
  FALSE_EXTERNAL_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze
  LOCAL_GATEWAY_EXTERNAL_EFFECTS = {
    "network" => true,
    "provider" => true,
    "secret" => true,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze
  ACTIVE_STATUSES = %w[ACTIVE AUTHORIZED_ACTIVE EXECUTING].freeze
  AUTHORIZED_ROUTE_STATUSES = %w[AUTHORIZED_READY ACTIVE].freeze
  ACCEPTED_GATE_STATUS_RE = /\A(?:FOUNDER_GATE|MASTER_TASK_GATE)_ACCEPTED_COMPLETE\z/.freeze
  GOAL_RAW_SHA256 = "28bc384fbac9d69c6de3ef8709a5be5a0473309b0fe0e54b01bead13d4fa9cf1".freeze
  GOAL_RAW_BYTE_LENGTH = 19_433
  GOAL_CANONICAL_SHA256 = "b1be2cb56da4a1ad8b16fb3d8e8d5ccc413c047da30bd4cbdb161ebc1df5f70a".freeze
  GOAL_CANONICAL_BYTE_LENGTH = 19_434

  def fail!(message, category: "VALIDATION")
    raise AuthorityValidationError.new(message, category: category)
  end

  def fail_category!(category, message)
    fail!(message, category: category)
  end

  def assert(condition, message)
    fail!(message) unless condition
  end

  def hash(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} must be a sequence")
    value
  end

  def string(value, label)
    assert(value.is_a?(String) && !value.empty?, "#{label} must be a non-empty string")
    value
  end

  def integer(value, label)
    assert(value.is_a?(Integer), "#{label} must be an integer")
    value
  end

  def exact_false(value, label)
    assert(value == false, "#{label} must be false")
  end

  def git(root, *args, allow_failure: false)
    stdout, stderr, status = Open3.capture3("git", "-C", root, *args)
    unless status.success? || allow_failure
      fail!("git #{args.join(' ')} failed: #{stderr.strip}")
    end
    [stdout, stderr, status]
  end

  def secure_read(path, label)
    before = File.lstat(path)
    assert(!before.symlink?, "#{label} must not be a symlink: #{path}")
    assert(before.file?, "#{label} must be a regular file: #{path}")

    flags = File::RDONLY
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    bytes = nil
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino] == [before.dev, before.ino], "#{label} changed while opening: #{path}")
      bytes = file.read
      after = file.stat
      assert([after.dev, after.ino, after.size, after.mtime.to_f] ==
             [opened.dev, opened.ino, opened.size, opened.mtime.to_f],
             "#{label} changed while reading: #{path}")
    end
    final = File.lstat(path)
    assert([final.dev, final.ino, final.size, final.mtime.to_f] ==
           [before.dev, before.ino, before.size, before.mtime.to_f],
           "#{label} changed during validation: #{path}")
    bytes
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail!("#{label} is unavailable: #{path} (#{e.class})")
  end

  def parse_yaml(bytes, label)
    value = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    hash(value, label)
  rescue Psych::Exception => e
    fail!("#{label} is invalid YAML: #{e.message}")
  end

  def parse_structured(bytes, path, label)
    if File.extname(path).downcase == ".json"
      value = JSON.parse(bytes)
      hash(value, label)
    else
      parse_yaml(bytes, label)
    end
  rescue JSON::ParserError => e
    fail!("#{label} is invalid JSON: #{e.message}")
  end

  def sha256(bytes)
    Digest::SHA256.hexdigest(bytes)
  end

  def canonical_json(value)
    case value
    when Hash
      "{" + value.keys.sort.map { |key| JSON.generate(key) + ":" + canonical_json(value[key]) }.join(",") + "}"
    when Array
      "[" + value.map { |item| canonical_json(item) }.join(",") + "]"
    else
      JSON.generate(value)
    end
  end

  def canonical_digest(value)
    sha256(canonical_json(value).encode(Encoding::UTF_8))
  end

  def utc_time(value, label)
    text = string(value, label)
    parsed = Time.iso8601(text)
    assert(parsed.utc_offset.zero? && text.end_with?("Z"), "#{label} must be UTC ISO-8601")
    parsed.utc
  rescue ArgumentError
    fail!("#{label} is not valid ISO-8601 UTC")
  end

  def validate_identity(path, identity, label)
    record = hash(identity, "#{label} identity")
    expected_sha = string(record["sha256"], "#{label}.sha256")
    expected_length = integer(record["byte_length"], "#{label}.byte_length")
    assert(SHA256_RE.match?(expected_sha), "#{label}.sha256 must be lowercase SHA-256")
    assert(expected_length >= 0, "#{label}.byte_length must be non-negative")
    bytes = secure_read(path, label)
    assert(bytes.bytesize == expected_length,
           "#{label} byte length mismatch: expected #{expected_length}, got #{bytes.bytesize}")
    assert(sha256(bytes) == expected_sha, "#{label} SHA-256 mismatch")
    bytes
  end

  def validate_sha_only(path, expected_sha, label)
    digest = string(expected_sha, "#{label}.sha256")
    assert(SHA256_RE.match?(digest), "#{label}.sha256 must be lowercase SHA-256")
    bytes = secure_read(path, label)
    assert(sha256(bytes) == digest, "#{label} SHA-256 mismatch")
    bytes
  end

  def repo_path(root, relative, label)
    rel = string(relative, label)
    path = Pathname.new(rel)
    assert(!path.absolute?, "#{label} must be repository-relative")
    clean = path.cleanpath.to_s
    assert(clean != "." && clean != ".." && !clean.start_with?("../"), "#{label} escapes the repository")
    assert(clean == rel, "#{label} must be normalized")
    full = File.expand_path(clean, root)
    root_real = File.realpath(root)
    full_real = File.realpath(full)
    assert(full_real == full, "#{label} must not traverse symlinked path components")
    assert(full_real.start_with?(root_real + File::SEPARATOR), "#{label} escapes the repository")
    full
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail!("#{label} is unavailable (#{e.class})")
  end

  def absolute_existing_file(value, label)
    path = string(value, label)
    assert(Pathname.new(path).absolute?, "#{label} must be absolute")
    secure_read(path, label)
    path
  end

  def canonical_goal_bytes(raw)
    text = raw.dup.force_encoding(Encoding::UTF_8)
    assert(text.valid_encoding?, "Goal raw bytes are not valid UTF-8")
    normalized = text.gsub("\r\n", "\n").gsub("\r", "\n")
    normalized.sub(/\n*\z/, "") + "\n"
  end

  def validate_goal(truth)
    goal = hash(truth["goal"], "goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE", "Goal control plane must be ACTIVE")
    assert(goal["body_canonicalization"] == "UTF8_LF_WITH_EXACTLY_ONE_TRAILING_LF",
           "unsupported Goal canonicalization")
    source = string(goal["source_attachment_path"], "goal.source_attachment_path")
    raw = secure_read(source, "Goal source attachment")
    raw_sha = string(goal["observed_raw_body_sha256"], "goal.observed_raw_body_sha256")
    raw_length = integer(goal["observed_raw_body_byte_length"], "goal.observed_raw_body_byte_length")
    assert(raw_sha == GOAL_RAW_SHA256 && raw_length == GOAL_RAW_BYTE_LENGTH,
           "Truth does not bind the Founder-installed raw Goal identity")
    assert(raw.bytesize == raw_length, "Goal raw byte length mismatch")
    assert(sha256(raw) == raw_sha, "Goal raw SHA-256 mismatch")
    canonical = canonical_goal_bytes(raw)
    canonical_sha = string(goal["observed_body_sha256"], "goal.observed_body_sha256")
    canonical_length = integer(goal["observed_body_byte_length"], "goal.observed_body_byte_length")
    assert(canonical_sha == GOAL_CANONICAL_SHA256 && canonical_length == GOAL_CANONICAL_BYTE_LENGTH,
           "Truth does not bind the Founder-installed canonical Goal identity")
    assert(canonical.bytesize == canonical_length, "Goal canonical byte length mismatch")
    assert(sha256(canonical) == canonical_sha, "Goal canonical SHA-256 mismatch")
  end

  def validate_authority_documents(root, truth)
    authority = hash(truth["authority"], "authority")
    %w[strategy execution_protocol founder_delegation_policy evaluation_protocol].each do |key|
      record = hash(authority[key], "authority.#{key}")
      path = repo_path(root, record["path"], "authority.#{key}.path")
      validate_sha_only(path, record["sha256"], "authority.#{key}")
    end
    current_facts = repo_path(root, authority["current_facts"], "authority.current_facts")
    expected_truth = File.join(root, "docs/aios/truth/project_state.yaml")
    assert(current_facts == expected_truth, "authority.current_facts must identify canonical Truth")
  end

  def validate_commit_tree(root, commit, tree, label)
    commit_id = string(commit, "#{label}.commit")
    tree_id = string(tree, "#{label}.tree")
    assert(COMMIT_RE.match?(commit_id), "#{label}.commit must be a full commit id")
    assert(COMMIT_RE.match?(tree_id), "#{label}.tree must be a full tree id")
    _out, _err, status = git(root, "cat-file", "-e", "#{commit_id}^{commit}", allow_failure: true)
    assert(status.success?, "#{label}.commit is not available")
    actual_tree = git(root, "show", "-s", "--format=%T", commit_id).first.strip
    assert(actual_tree == tree_id, "#{label}.tree does not match commit")
  end

  def accepted_history_record(truth, task_id, label)
    history = hash(truth["task_history"], "task_history")
    matches = history.values.select do |record|
      record.is_a?(Hash) && record["task_id"] == task_id
    end
    assert(matches.length == 1, "#{label} must map to exactly one top-level task_history record")
    record = matches.first
    status = string(record["status"], "#{label} history status")
    assert(ACCEPTED_GATE_STATUS_RE.match?(status), "#{label} history status is not an exact accepted Gate lifecycle")
    record
  end

  def validate_accepted_contract(bytes, path, task_id, phase, label)
    contract = parse_structured(bytes, path, label)
    assert(contract["task_id"] == task_id, "#{label} task_id mismatch")
    assert(contract["phase"] == phase, "#{label} phase mismatch")
    contract
  end

  def validate_external_effects(value, label, expected = FALSE_EXTERNAL_EFFECTS)
    effects = hash(value, label)
    assert(effects.keys.sort == EXTERNAL_EFFECT_KEYS.sort, "#{label} must contain exactly the six external-effect keys")
    assert(effects == expected, "#{label} does not equal the exact authorized external-effect map")
    effects
  end

  def exact_keys(value, expected, label)
    record = hash(value, label)
    assert(record.keys.sort == expected.sort, "#{label} keys drifted")
    record
  end

  def founder_reserved_profile_from_packet(text)
    matches = text.scan(
      /<!-- BEGIN FOUNDER_RESERVED_PROFILE_JSON -->\s*```json\s*(.*?)\s*```\s*<!-- END FOUNDER_RESERVED_PROFILE_JSON -->/m
    )
    assert(matches.length == 1, "decision packet must contain exactly one Founder-reserved profile")
    profile = JSON.parse(matches.first.first)
    hash(profile, "Founder-reserved profile")
  rescue JSON::ParserError => e
    fail!("Founder-reserved profile is invalid JSON: #{e.message}")
  end

  def validate_founder_reserved_profile(value, route_id, task_id, label)
    profile = exact_keys(
      value,
      %w[schema_version profile_id decision_basis route_id task_id transport model secret call_limits request_limits egress external_effects claim_limits],
      label
    )
    assert(profile["schema_version"] == "1.0", "#{label} schema version drifted")
    string(profile["profile_id"], "#{label}.profile_id")
    string(profile["decision_basis"], "#{label}.decision_basis")
    assert(profile["route_id"] == route_id, "#{label} route id mismatch")
    assert(profile["task_id"] == task_id, "#{label} Task id mismatch")

    transport = exact_keys(
      profile["transport"],
      %w[scheme host port base_path metadata_path completion_path api_format method follow_redirects use_proxy dns_resolution fallback_endpoint_allowed expected_peer_address expected_peer_port],
      "#{label}.transport"
    )
    expected_transport = {
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
    }
    assert(transport == expected_transport, "#{label}.transport exceeds the literal local-gateway boundary")

    model = exact_keys(profile["model"], %w[requested_model substitution_allowed provider_provenance],
                       "#{label}.model")
    string(model["requested_model"], "#{label}.model.requested_model")
    exact_false(model["substitution_allowed"], "#{label}.model.substitution_allowed")
    assert(model["provider_provenance"] == "OPENAI_FOUNDER_ATTESTED_GATEWAY_NOT_INDEPENDENTLY_VERIFIED",
           "#{label}.model provider provenance must remain Founder-attested and independently unverified")

    secret = exact_keys(profile["secret"], %w[env_name source persist log_hash_or_evidence_allowed],
                        "#{label}.secret")
    assert(secret["env_name"].is_a?(String) && secret["env_name"].match?(/\A[A-Z][A-Z0-9_]*\z/),
           "#{label}.secret.env_name is invalid")
    assert(secret["source"] == "FOUNDER_TRANSIENT_UI_INPUT", "#{label}.secret source drifted")
    exact_false(secret["persist"], "#{label}.secret.persist")
    exact_false(secret["log_hash_or_evidence_allowed"], "#{label}.secret.log_hash_or_evidence_allowed")

    calls = exact_keys(
      profile["call_limits"],
      %w[metadata_max metadata_used_before_activation source_bearing_max source_bearing_used_before_activation automatic_retry_max ambiguous_send_retry_allowed],
      "#{label}.call_limits"
    )
    assert(calls == {
      "metadata_max" => 1,
      "metadata_used_before_activation" => 1,
      "source_bearing_max" => 1,
      "source_bearing_used_before_activation" => 0,
      "automatic_retry_max" => 0,
      "ambiguous_send_retry_allowed" => false
    }, "#{label}.call limits drifted")

    limits = exact_keys(
      profile["request_limits"],
      %w[max_input_tokens max_output_tokens timeout_seconds request_body_max_bytes response_body_max_bytes],
      "#{label}.request_limits"
    )
    caps = {
      "max_input_tokens" => 4096,
      "max_output_tokens" => 1024,
      "timeout_seconds" => 120,
      "request_body_max_bytes" => 32_768,
      "response_body_max_bytes" => 131_072
    }
    caps.each do |key, cap|
      current = integer(limits[key], "#{label}.request_limits.#{key}")
      assert(current.positive? && current <= cap, "#{label}.request_limits.#{key} exceeds the safety cap")
    end

    egress = exact_keys(profile["egress"], %w[allowed_artifact_ids forbidden_categories], "#{label}.egress")
    expected_allowed = %w[
      P1_035_REP001_ISSUE_TEXT
      P1_035_REP001_ALLOWED_CLARIFICATIONS
      P1_035_REP001_ACCEPTED_BASELINE_CONTEXT
      P1_062_FINITE_IR_RESPONSE_INSTRUCTION
    ]
    expected_forbidden = %w[
      SOURCE_BYTES
      TEST_BYTES
      REFERENCE_PATCH
      EVALUATOR_BYTES
      GOVERNANCE_OR_TRUTH_BYTES
      SECRET_OR_AUTHORIZATION_HEADER
      HIDDEN_TASK_OR_HIDDEN_EVIDENCE
    ]
    assert(array(egress["allowed_artifact_ids"], "#{label}.egress.allowed_artifact_ids") == expected_allowed,
           "#{label}.egress allowlist drifted")
    assert(array(egress["forbidden_categories"], "#{label}.egress.forbidden_categories") == expected_forbidden,
           "#{label}.egress denylist drifted")

    validate_external_effects(profile["external_effects"], "#{label}.external_effects",
                              LOCAL_GATEWAY_EXTERNAL_EFFECTS)
    claims = exact_keys(profile["claim_limits"],
                        %w[direct_openai_provenance_proven upstream_provider upstream_request_count monetary_cost],
                        "#{label}.claim_limits")
    assert(claims == {
      "direct_openai_provenance_proven" => false,
      "upstream_provider" => "OPENAI_FOUNDER_ATTESTED",
      "upstream_request_count" => "UNKNOWN",
      "monetary_cost" => "UNKNOWN_USER_MANAGED_GATEWAY"
    }, "#{label}.claim limits drifted")
    profile
  end

  def one_packet_match(text, pattern, label)
    matches = text.scan(pattern)
    assert(matches.length == 1, "decision packet must contain exactly one #{label}")
    match = matches.first
    match.is_a?(Array) && match.length == 1 ? match.first : match
  end

  def project_route_packet_claims(text)
    record_type = one_packet_match(
      text,
      /- `record_type`: `(FOUNDER_PROJECT_LEVEL_ARCHITECTURE_ROUTE_AND_PHASE_REENTRY_DECISION_PACKET)`/,
      "project-level route record type"
    )
    assert(record_type == "FOUNDER_PROJECT_LEVEL_ARCHITECTURE_ROUTE_AND_PHASE_REENTRY_DECISION_PACKET",
           "unsupported project-level route record type")
    route_id = one_packet_match(text, /- `route_id`: `(P1_[A-Z0-9_]+_ROUTE_V1)`/,
                                "Route ID declaration")
    authorization_token = one_packet_match(text, /- `authorization_token`: `([A-Z0-9_]+)`/,
                                            "Founder authorization token declaration")
    envelope = one_packet_match(
      text,
      /- `maximum_engineering_tasks`: `(\d+)`\s+- `maximum_engineering_hours`: `(\d+)`\s+- `maximum_calendar_days`: `(\d+)`/m,
      "Phase envelope declaration"
    )
    task_section = one_packet_match(text, /## 7\. Task 1[^\n]*\n(.*?)\n## 8\. Task 2/m,
                                    "first Task section")
    first_task_id = one_packet_match(task_section, /- `task_id`: `(AIOS-P1-[0-9]{3}_[A-Z0-9_]+)`/,
                                     "first Task ID declaration")
    first_task_budget = one_packet_match(
      task_section,
      /- `engineering_hours`: `(\d+)`\s+- `calendar_days`: `(\d+)`\s+- `implementation_iterations`: `(\d+)`\s+- `final_candidates`: `(\d+)`/m,
      "first Task budget declaration"
    )
    parent = one_packet_match(
      text,
      /- canonical `main`：commit `([0-9a-f]{40})`；tree `([0-9a-f]{40})`；工作区 clean。/,
      "activation parent declaration"
    )
    implementation_iterations = Integer(first_task_budget[2], 10)
    assert(implementation_iterations >= 1, "first Task implementation iterations must be positive")
    founder_reserved_profile = founder_reserved_profile_from_packet(text)
    validate_founder_reserved_profile(founder_reserved_profile, route_id, first_task_id,
                                      "decision packet Founder-reserved profile")
    {
      "route_id" => route_id,
      "first_task_id" => first_task_id,
      "authorization_token" => authorization_token,
      "max_engineering_tasks" => Integer(envelope[0], 10),
      "max_engineering_hours" => Integer(envelope[1], 10),
      "max_calendar_days" => Integer(envelope[2], 10),
      "first_task_engineering_hours" => Integer(first_task_budget[0], 10),
      "first_task_calendar_days" => Integer(first_task_budget[1], 10),
      "first_task_implementation_iterations" => implementation_iterations,
      "first_task_candidates" => Integer(first_task_budget[3], 10),
      "max_contract_corrections_per_task" => nil,
      "max_same_task_repairs" => implementation_iterations - 1,
      "activation_parent_commit" => parent[0],
      "activation_parent_tree" => parent[1],
      "founder_reserved_profile" => founder_reserved_profile,
      "text" => text
    }
  rescue ArgumentError
    fail!("decision packet contains a non-integer Phase envelope")
  end

  def legacy_route_packet_claims(text)
    route_id = one_packet_match(
      text,
      /## 1\. 单一结论.*?`(P1_[A-Z0-9_]+ARCHITECTURE_ROUTE_V1)`/m,
      "Route ID declaration"
    )
    first_task_id = one_packet_match(
      text,
      /### T1 — (AIOS-P1-[0-9]{3}_[A-Z0-9_]+)/,
      "first Task ID declaration"
    )
    authorization_token = one_packet_match(
      text,
      /authorization_token=([A-Z0-9_]+)/,
      "Founder authorization token declaration"
    )
    envelope = one_packet_match(
      text,
      /### Route Envelope\s+- 最多 `(\d+) engineering Tasks`。\s+- 最多 `(\d+) engineering hours`。\s+- 最多 `(\d+) calendar days`。/m,
      "Phase envelope declaration"
    )
    first_task_budget = one_packet_match(
      text,
      /### T1 — [^\n]+\s+- Budget：`(\d+) engineering hours \/ (\d+) calendar days`/m,
      "first Task budget declaration"
    )
    contract_corrections = one_packet_match(
      text,
      /### Route Envelope.*?每个 Task 最多一份 working Contract、([一二两三四五六七八九十]+)次[^\n]+bounded contract/m,
      "per-Task contract correction declaration"
    )
    same_task_repairs = one_packet_match(
      text,
      /### Route Envelope.*?initial implementation 加([一二两三四五六七八九十]+)次 same-Task bounded repair/m,
      "same-Task repair declaration"
    )
    candidates = one_packet_match(
      text,
      /### Route Envelope.*?same-Task bounded repair、([一二两三四五六七八九十]+)个 exact candidate/m,
      "per-Task candidate declaration"
    )
    parent = one_packet_match(
      text,
      /- Canonical commit：`([0-9a-f]{40})`。\s+- Canonical tree：`([0-9a-f]{40})`。/m,
      "activation parent declaration"
    )
    repair_count = chinese_integer(same_task_repairs)
    {
      "route_id" => route_id,
      "first_task_id" => first_task_id,
      "authorization_token" => authorization_token,
      "max_engineering_tasks" => Integer(envelope[0], 10),
      "max_engineering_hours" => Integer(envelope[1], 10),
      "max_calendar_days" => Integer(envelope[2], 10),
      "first_task_engineering_hours" => Integer(first_task_budget[0], 10),
      "first_task_calendar_days" => Integer(first_task_budget[1], 10),
      "first_task_implementation_iterations" => 1 + repair_count,
      "first_task_candidates" => chinese_integer(candidates),
      "max_contract_corrections_per_task" => chinese_integer(contract_corrections),
      "max_same_task_repairs" => repair_count,
      "activation_parent_commit" => parent[0],
      "activation_parent_tree" => parent[1],
      "text" => text
    }
  rescue ArgumentError
    fail!("decision packet contains a non-integer Phase envelope")
  end

  def packet_claims(packet_bytes)
    text = packet_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(text.valid_encoding?, "decision packet must be valid UTF-8")
    if text.include?("FOUNDER_PROJECT_LEVEL_ARCHITECTURE_ROUTE_AND_PHASE_REENTRY_DECISION_PACKET")
      project_route_packet_claims(text)
    else
      legacy_route_packet_claims(text)
    end
  end

  def chinese_integer(text)
    digits = { "一" => 1, "二" => 2, "两" => 2, "三" => 3, "四" => 4, "五" => 5,
               "六" => 6, "七" => 7, "八" => 8, "九" => 9 }
    return 10 if text == "十"
    if text.include?("十")
      left, right = text.split("十", 2)
      tens = left.empty? ? 1 : digits[left]
      ones = right.empty? ? 0 : digits[right]
      fail!("unsupported Chinese integer in decision packet") unless tens && ones
      return (tens * 10) + ones
    end
    digits.fetch(text) { fail!("unsupported Chinese integer in decision packet") }
  end

  def validate_route(root, truth)
    project = hash(truth["project"], "project")
    route = hash(truth["current_phase_route"], "current_phase_route")
    route_id = string(route["route_id"], "current_phase_route.route_id")
    assert(route["phase"] == project["current_phase"], "route phase must equal project phase")
    assert(route["phase_entry_status"] == "AUTHORIZED", "route phase entry must be AUTHORIZED")
    assert(AUTHORIZED_ROUTE_STATUSES.include?(route["status"]), "route status is not executable")

    packet = hash(route["decision_packet"], "current_phase_route.decision_packet")
    packet_path = string(packet["path"], "current_phase_route.decision_packet.path")
    assert(Pathname.new(packet_path).absolute?, "decision packet path must be absolute")
    assert(SHA256_RE.match?(string(packet["sha256"], "current_phase_route.decision_packet.sha256")),
           "decision packet SHA-256 must be lowercase")
    assert(integer(packet["byte_length"], "current_phase_route.decision_packet.byte_length").positive?,
           "decision packet byte length must be positive")
    packet_bytes = validate_identity(packet_path, packet, "Founder route decision packet")
    claims = packet_claims(packet_bytes)
    assert(route_id == claims["route_id"], "Truth route id does not match exact decision packet")
    authorization_token = string(route["authorization_token"], "current_phase_route.authorization_token")
    assert(authorization_token == claims["authorization_token"],
           "route authorization token does not match exact decision packet")

    parent = hash(route["activation_parent"], "current_phase_route.activation_parent")
    assert(parent["commit"] == claims["activation_parent_commit"] &&
           parent["tree"] == claims["activation_parent_tree"],
           "Truth activation parent does not match exact decision packet")
    validate_commit_tree(root, parent["commit"], parent["tree"], "route activation parent")

    route_policy = hash(route["policy"], "current_phase_route.policy")
    authority_policy = hash(hash(truth["authority"], "authority")["founder_delegation_policy"],
                            "authority.founder_delegation_policy")
    assert(route_policy["path"] == authority_policy["path"] &&
           route_policy["version"].to_s == authority_policy["version"].to_s &&
           route_policy["sha256"] == authority_policy["sha256"],
           "route policy identity must equal authority policy identity")

    envelope = hash(route["envelope"], "current_phase_route.envelope")
    %w[max_engineering_tasks max_engineering_hours max_calendar_days max_active_tasks
       max_task_branches max_task_worktrees max_active_candidates
       max_contract_corrections_per_task max_same_task_repairs].each do |key|
      assert(integer(envelope[key], "current_phase_route.envelope.#{key}") > 0,
             "current_phase_route.envelope.#{key} must be positive")
    end
    %w[max_active_tasks max_task_branches max_task_worktrees max_active_candidates].each do |key|
      assert(envelope[key] == 1, "current_phase_route.envelope.#{key} must equal 1")
    end
    exact_false(envelope["successor_replacement_normalization_closure_feasibility_or_remediation_chain_allowed"],
                "route envelope correction-chain permission")
    exact_false(envelope["p2_entry_authorized"], "route envelope P2 entry")
    exact_false(envelope["p3_entry_authorized"], "route envelope P3 entry")
    route_profile = validate_founder_reserved_profile(
      route["founder_reserved_profile"], route_id, claims["first_task_id"],
      "current_phase_route.founder_reserved_profile"
    )
    assert(route_profile == claims["founder_reserved_profile"],
           "Truth Founder-reserved profile does not equal the exact decision packet")
    validate_external_effects(envelope["external_effects"], "current_phase_route.envelope.external_effects",
                              route_profile["external_effects"])
    %w[max_engineering_tasks max_engineering_hours max_calendar_days].each do |key|
      assert(envelope[key] == claims[key], "route envelope #{key} does not match exact decision packet")
    end
    assert(envelope["max_same_task_repairs"] == claims["max_same_task_repairs"],
           "route envelope max_same_task_repairs does not match exact decision packet")
    if claims["max_contract_corrections_per_task"]
      assert(envelope["max_contract_corrections_per_task"] == claims["max_contract_corrections_per_task"],
             "route envelope max_contract_corrections_per_task does not match exact decision packet")
    else
      delegated_limit = integer(
        truth.dig("phase_delegation", "anti_loop", "maximum_same_task_bounded_contract_repairs"),
        "delegation policy maximum bounded Contract repairs"
      )
      assert(envelope["max_contract_corrections_per_task"] <= delegated_limit,
             "route envelope contract correction limit exceeds delegated policy")
    end

    accepted = hash(route["accepted_inputs"], "current_phase_route.accepted_inputs")
    assert(!accepted.empty?, "current_phase_route.accepted_inputs must not be empty")
    accepted.each do |input_id, record_value|
      record = hash(record_value, "accepted input #{input_id}")
      task_id = string(record["task_id"], "accepted input #{input_id}.task_id")
      status = string(record["status"], "accepted input #{input_id}.status")
      assert(ACCEPTED_GATE_STATUS_RE.match?(status),
             "accepted input #{input_id} status is not an exact accepted Gate lifecycle")
      history_record = accepted_history_record(truth, task_id, "accepted input #{input_id}")
      bindings = {
        "status" => status,
        "contract" => record["task_contract_path"],
        "task_contract_sha256" => record["task_contract_sha256"],
        "accepted_candidate_commit" => record["accepted_candidate_commit"],
        "accepted_candidate_tree" => record["accepted_candidate_tree"]
      }
      bindings.each do |history_key, expected|
        assert(history_record[history_key] == expected,
               "accepted input #{input_id} history #{history_key} binding mismatch")
      end
      validate_commit_tree(root, record["accepted_candidate_commit"], record["accepted_candidate_tree"],
                           "accepted input #{input_id}")
      _out, _err, ancestor_status = git(root, "merge-base", "--is-ancestor",
                                         record["accepted_candidate_commit"], "HEAD", allow_failure: true)
      assert(ancestor_status.success?, "accepted input #{input_id} is not an ancestor of canonical HEAD")
      contract_path = repo_path(root, record["task_contract_path"], "accepted input #{input_id}.task_contract_path")
      current_contract = validate_sha_only(contract_path, record["task_contract_sha256"],
                                           "accepted input #{input_id} contract")
      historical_contract = git(root, "show",
                                "#{record['accepted_candidate_commit']}:#{record['task_contract_path']}").first
      assert(sha256(historical_contract) == record["task_contract_sha256"],
             "accepted input #{input_id} commit does not bind the declared contract bytes")
      assert(current_contract == historical_contract,
             "accepted input #{input_id} current and accepted-commit contract bytes differ")
      validate_accepted_contract(current_contract, contract_path, task_id, project["current_phase"],
                                 "accepted input #{input_id} current contract")
      validate_accepted_contract(historical_contract, record["task_contract_path"], task_id,
                                 project["current_phase"], "accepted input #{input_id} accepted-commit contract")
    end

    first_task = hash(route["first_task"], "current_phase_route.first_task")
    first_task_id = string(first_task["task_id"], "current_phase_route.first_task.task_id")
    assert(SAFE_TASK_ID_RE.match?(first_task_id), "first Task id has invalid form")
    assert(first_task_id == claims["first_task_id"], "first Task id does not match exact decision packet")
    assert(integer(first_task["max_engineering_hours"], "first task hours") <= envelope["max_engineering_hours"],
           "first Task hours exceed route envelope")
    assert(integer(first_task["max_calendar_days"], "first task days") <= envelope["max_calendar_days"],
           "first Task days exceed route envelope")
    assert(integer(first_task["max_candidates"], "first task candidates") <= envelope["max_active_candidates"],
           "first Task candidates exceed route envelope")
    first_task_packet_bindings = {
      "max_engineering_hours" => claims["first_task_engineering_hours"],
      "max_calendar_days" => claims["first_task_calendar_days"],
      "max_implementation_iterations" => claims["first_task_implementation_iterations"],
      "max_candidates" => claims["first_task_candidates"]
    }
    first_task_packet_bindings.each do |key, value|
      assert(first_task[key] == value, "first Task #{key} does not match exact decision packet")
    end
    goal = hash(truth["goal"], "goal")
    assert(claims["text"].include?(goal["observed_body_sha256"].to_s),
           "canonical Goal identity is not bound by the exact decision packet")
    [route, route_id, first_task, accepted]
  end

  def historical_task_ids(truth)
    roots = [truth["task_history"], truth["superseded_pre_delegation_authorizations"], truth["gate_history"]]
    ids = []
    walk = lambda do |value|
      case value
      when Hash
        value.each do |key, child|
          ids << child if key == "task_id" && child.is_a?(String)
          walk.call(child)
        end
      when Array
        value.each { |child| walk.call(child) }
      end
    end
    roots.compact.each { |root| walk.call(root) }
    ids.uniq
  end

  def historical_execution_lineage_ids(truth)
    ids = []
    history = truth["task_history"]
    if history.is_a?(Hash)
      history.each_value do |record|
        next unless record.is_a?(Hash)
        next if record["status"].to_s.start_with?("ACTIVE")

        lineage = record["execution_lineage_id"]
        ids << lineage if lineage.is_a?(String)
      end
    end
    roots = [truth["superseded_pre_delegation_authorizations"], truth["gate_history"]]
    walk = lambda do |value|
      case value
      when Hash
        value.each do |key, child|
          ids << child if key == "execution_lineage_id" && child.is_a?(String)
          walk.call(child)
        end
      when Array
        value.each { |child| walk.call(child) }
      end
    end
    roots.compact.each { |root| walk.call(root) }
    ids.uniq
  end

  def null_identity(record, label)
    item = hash(record, label)
    assert(item.keys.sort == %w[byte_length path sha256], "#{label} must contain path, sha256 and byte_length")
    item.each { |key, value| assert(value.nil?, "#{label}.#{key} must be null while Task is NONE") }
  end

  def validate_none_state(truth, route, first_task)
    goal = hash(truth["goal"], "goal")
    project = hash(truth["project"], "project")
    active = hash(truth["active_work"], "active_work")
    assert(goal["current_task_authority"] == "NONE", "Goal current Task authority must be NONE")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE",
           "active_work must express Task NONE")
    initial_ready = route["status"] == "AUTHORIZED_READY"
    between_tasks = route["status"] == "ACTIVE"
    assert(initial_ready || between_tasks, "Task NONE requires a ready or active Phase route")
    if initial_ready
      assert(project["phase_execution_status"] == "AUTHORIZED_READY" &&
             project["p1_execution_status"] == "AUTHORIZED_READY", "initial Task NONE requires project AUTHORIZED_READY")
      assert(first_task["status"] == "ELIGIBLE_NOT_ACTIVATED",
             "initial Task NONE requires an eligible, non-activated first Task")
    else
      assert(%w[ACTIVE EXECUTING].include?(project["phase_execution_status"]) &&
             %w[ACTIVE EXECUTING].include?(project["p1_execution_status"]),
             "between-Task NONE requires active project execution")
      assert(first_task["status"] != "ACTIVE", "between-Task NONE cannot leave first Task active")
    end
    null_identity(active["current_task_contract"], "active_work.current_task_contract")
    null_identity(active["authority_record"], "active_work.authority_record")
    %w[current_task_contract_sha256 current_execution_authorization
       current_execution_authorization_sha256 execution_nonce authorization_id
       activation_parent_commit activation_parent_tree task_branch task_worktree
       execution_evidence_root offsite_target founder_reserved_authorization
       founder_reserved_authorization_sha256].each do |key|
      assert(active[key].nil?, "active_work.#{key} must be null while Task is NONE")
    end
    assert(active["execution_nonce_status"] == "NOT_APPLICABLE_TASK_NONE",
           "Task NONE execution_nonce_status mismatch")
    expected_resource_state = initial_ready ? "NOT_CREATED_ROUTE_READY" : "NONE_PHASE_ACTIVE"
    assert(active["task_resource_state"] == expected_resource_state, "Task NONE resource state mismatch")
    assert(array(active["allowlisted_paths"], "active_work.allowlisted_paths").empty?,
           "Task NONE allowlisted_paths must be empty")
    budget = hash(active["budget"], "active_work.budget")
    assert(budget.keys.sort == %w[calendar_days candidates engineering_hours implementation_iterations],
           "Task NONE budget keys mismatch")
    budget.each { |key, value| assert(value.nil?, "Task NONE budget.#{key} must be null") }
    roles = hash(active["roles"], "active_work.roles")
    assert(roles.keys.sort == %w[independent_reviewers owner worker], "Task NONE roles keys mismatch")
    assert(roles["owner"].nil? && roles["worker"].nil? &&
           array(roles["independent_reviewers"], "Task NONE reviewers").empty?, "Task NONE roles must be empty")
    validate_external_effects(active["external_effects"], "active_work.external_effects")
    exact_false(active["founder_decision_required"], "active_work.founder_decision_required")
    assert(active["escalation_reason"].nil?, "Task NONE escalation_reason must be null")
    assert(active["user_action_required"] == "NONE", "Task NONE user_action_required must be NONE")
    string(active["next_eligible_action"], "active_work.next_eligible_action")
    assert(active["next_eligible_action"] == route["next_eligible_action"], "next eligible action mismatch")
  end

  def identity_from(record, legacy_sha, label)
    item = hash(record, label)
    sha = string(item["sha256"], "#{label}.sha256")
    assert(legacy_sha.nil? || legacy_sha == sha, "#{label} legacy SHA projection mismatch")
    item
  end

  def safe_scope_path(value, label)
    path = string(value, label)
    assert(!Pathname.new(path).absolute?, "#{label} must be repository-relative")
    plain = path.sub(%r{/\*\*\z}, "")
    clean = Pathname.new(plain).cleanpath.to_s
    assert(clean == plain && clean != "." && clean != ".." && !clean.start_with?("../"),
           "#{label} is not a safe normalized path")
    assert(!path.include?("\0"), "#{label} contains NUL")
    path
  end

  def flatten_write_roots(value)
    hash(value, "phase_boundary.role_write_roots").values.flat_map do |entry|
      entry.is_a?(Array) ? entry : [entry]
    end.select { |entry| entry.is_a?(String) }
  end

  def scope_within_root?(scope, root)
    scope_plain = scope.sub(%r{/\*\*\z}, "")
    root_plain = root.sub(%r{/\*\*\z}, "")
    scope_plain == root_plain || scope_plain.start_with?(root_plain + "/")
  end

  def contract_field(contract, key)
    return contract[key] if contract.key?(key)
    %w[task scope execution authority].each do |section|
      child = contract[section]
      return child[key] if child.is_a?(Hash) && child.key?(key)
    end
    nil
  end

  def normalize_scopes(value, label)
    list = if value.is_a?(Array)
             value
           elsif value.is_a?(Hash)
             value.values.flat_map { |child| child.is_a?(Array) ? child : [child] }
           else
             fail!("#{label} must be a sequence or role mapping")
           end
    assert(!list.empty?, "#{label} must not be empty")
    list.map.with_index { |entry, index| safe_scope_path(entry, "#{label}[#{index}]") }.uniq.sort
  end

  def validate_active_state(root, truth, route, route_id, first_task)
    goal = hash(truth["goal"], "goal")
    project = hash(truth["project"], "project")
    active = hash(truth["active_work"], "active_work")
    task_id = string(active["current_task"], "active_work.current_task")
    assert(SAFE_TASK_ID_RE.match?(task_id), "active Task id has invalid form")
    assert(goal["current_task_authority"] == task_id, "Goal current Task authority mismatch")
    assert(ACTIVE_STATUSES.include?(active["current_task_status"]), "active Task status is not active")
    assert(route["status"] == "ACTIVE", "active Task requires route ACTIVE")
    assert(%w[ACTIVE EXECUTING].include?(project["phase_execution_status"]),
           "active Task requires active project phase execution")
    assert(%w[ACTIVE EXECUTING].include?(project["p1_execution_status"]),
           "active Task requires active P1 execution")
    assert(!historical_task_ids(truth).include?(task_id), "active Task id reuses a historical Task id")

    contract_identity = identity_from(active["current_task_contract"], active["current_task_contract_sha256"],
                                      "active_work.current_task_contract")
    contract_path = repo_path(root, contract_identity["path"], "active Task contract path")
    contract_bytes = validate_identity(contract_path, contract_identity, "active Task contract")
    contract = parse_structured(contract_bytes, contract_path, "active Task contract")

    authority_identity = identity_from(active["authority_record"], active["current_execution_authorization_sha256"],
                                       "active_work.authority_record")
    authority_path = string(authority_identity["path"], "active_work.authority_record.path")
    assert(Pathname.new(authority_path).absolute?, "Task authority record path must be absolute")
    authority_bytes = validate_identity(authority_path, authority_identity, "active Task authority record")
    authority_record = parse_structured(authority_bytes, authority_path, "active Task authority record")
    assert(active["current_execution_authorization"] == authority_path,
           "current_execution_authorization must equal authority record path")

    [contract, authority_record].each_with_index do |record, index|
      label = index.zero? ? "contract" : "authority record"
      assert(contract_field(record, "task_id") == task_id, "#{label} Task id mismatch")
      assert(contract_field(record, "phase") == project["current_phase"], "#{label} phase mismatch")
      assert(contract_field(record, "route_id") == route_id, "#{label} route id mismatch")
      assert(ACTIVE_STATUSES.include?(contract_field(record, "status")), "#{label} status is not active")
    end
    assert(contract_field(authority_record, "task_contract_sha256") == contract_identity["sha256"],
           "authority record contract SHA mismatch")
    authorization_id = string(active["authorization_id"], "active_work.authorization_id")
    assert(contract_field(authority_record, "authorization_id") == authorization_id,
           "authority record authorization id mismatch")
    assert(active["execution_nonce"].is_a?(String) && !active["execution_nonce"].empty?,
           "active Task requires execution_nonce")
    assert(active["execution_nonce_status"] == "ACTIVE", "active Task execution nonce must be ACTIVE")
    assert(contract_field(authority_record, "execution_nonce") == active["execution_nonce"],
           "authority record execution nonce mismatch")

    parent_commit = string(active["activation_parent_commit"], "active_work.activation_parent_commit")
    parent_tree = string(active["activation_parent_tree"], "active_work.activation_parent_tree")
    validate_commit_tree(root, parent_commit, parent_tree, "active Task activation parent")
    authority_parent = hash(contract_field(authority_record, "activation_parent"),
                            "authority record activation_parent")
    assert(authority_parent["commit"] == parent_commit && authority_parent["tree"] == parent_tree,
           "authority record activation parent mismatch")
    _out, _err, ancestor_status = git(root, "merge-base", "--is-ancestor", parent_commit, "HEAD", allow_failure: true)
    assert(ancestor_status.success?, "active Task activation parent must be an ancestor of canonical HEAD")

    task_descriptor = if task_id == first_task["task_id"]
                        first_task
                      else
                        descriptor = hash(route["active_task"], "current_phase_route.active_task")
                        assert(descriptor["task_id"] == task_id, "route active_task descriptor mismatch")
                        descriptor
                      end
    budget = hash(active["budget"], "active_work.budget")
    budget_limits = {
      "engineering_hours" => route.dig("envelope", "max_engineering_hours"),
      "calendar_days" => route.dig("envelope", "max_calendar_days"),
      "implementation_iterations" => task_descriptor["max_implementation_iterations"],
      "candidates" => task_descriptor["max_candidates"]
    }
    budget_limits.each do |key, limit|
      value = integer(budget[key], "active_work.budget.#{key}")
      assert(value.positive? && value <= integer(limit, "limit for #{key}"), "active budget #{key} exceeds envelope")
    end
    contract_budget = hash(contract_field(contract, "budget"), "contract budget")
    budget.each { |key, value| assert(contract_budget[key] == value, "contract budget #{key} mismatch") }
    authority_budget = hash(contract_field(authority_record, "budget"), "authority record budget")
    assert(authority_budget == budget, "authority record budget mismatch")

    roles = hash(active["roles"], "active_work.roles")
    owner = string(roles["owner"], "active_work.roles.owner")
    worker = string(roles["worker"], "active_work.roles.worker")
    reviewers = array(roles["independent_reviewers"], "active_work.roles.independent_reviewers")
    assert(reviewers.length == 3 && reviewers.all? { |reviewer| reviewer.is_a?(String) && !reviewer.empty? },
           "active Task requires exactly three named independent reviewers")
    assert(([owner, worker] + reviewers).uniq.length == 5, "active Task role identities must be distinct")
    contract_roles = hash(contract_field(contract, "roles"), "contract roles")
    assert(contract_roles == roles, "contract roles mismatch")
    authority_roles = hash(contract_field(authority_record, "roles"), "authority record roles")
    assert(authority_roles == roles, "authority record roles mismatch")

    scopes = normalize_scopes(active["allowlisted_paths"], "active_work.allowlisted_paths")
    contract_scopes = normalize_scopes(contract_field(contract, "allowlisted_paths"), "contract allowlisted_paths")
    assert(scopes == contract_scopes, "contract allowlisted paths mismatch")
    authority_scopes = normalize_scopes(contract_field(authority_record, "allowlisted_paths"),
                                        "authority record allowlisted_paths")
    assert(scopes == authority_scopes, "authority record allowlisted paths mismatch")
    boundary = hash(truth["phase_boundary"], "phase_boundary")
    roots = flatten_write_roots(boundary["role_write_roots"])
    immutable = array(boundary["immutable_authority_paths"], "phase_boundary.immutable_authority_paths")
    scopes.each do |scope|
      assert(roots.any? { |root_path| scope_within_root?(scope, root_path) },
             "allowlisted path is outside the P1 role roots: #{scope}")
      assert(immutable.none? { |path| scope_within_root?(scope, path) || scope_within_root?(path, scope) },
             "allowlisted path overlaps immutable authority: #{scope}")
    end

    expected_effects = validate_founder_reserved_profile(
      route["founder_reserved_profile"], route_id, task_id, "current_phase_route.founder_reserved_profile"
    )["external_effects"]
    validate_external_effects(active["external_effects"], "active_work.external_effects", expected_effects)
    validate_external_effects(contract_field(contract, "external_effects"), "contract external_effects", expected_effects)
    validate_external_effects(contract_field(authority_record, "external_effects"), "authority external_effects",
                              expected_effects)
    contract_profile = validate_founder_reserved_profile(
      contract_field(contract, "founder_reserved_profile"), route_id, task_id, "contract Founder-reserved profile"
    )
    authority_profile = validate_founder_reserved_profile(
      contract_field(authority_record, "founder_reserved_profile"), route_id, task_id,
      "authority Founder-reserved profile"
    )
    assert(contract_profile == route["founder_reserved_profile"], "contract Founder-reserved profile mismatch")
    assert(authority_profile == route["founder_reserved_profile"], "authority Founder-reserved profile mismatch")
    exact_false(active["founder_decision_required"], "active_work.founder_decision_required")
    packet = hash(route["decision_packet"], "current_phase_route.decision_packet")
    assert(active["founder_reserved_authorization"] == packet["path"],
           "active Founder-reserved authorization path mismatch")
    assert(active["founder_reserved_authorization_sha256"] == packet["sha256"],
           "active Founder-reserved authorization SHA mismatch")
    [contract, authority_record].each_with_index do |record, index|
      label = index.zero? ? "contract" : "authority record"
      binding = exact_keys(contract_field(record, "founder_reserved_authorization"),
                           %w[path sha256 byte_length authorization_token],
                           "#{label} Founder-reserved authorization")
      assert(binding["path"] == packet["path"] && binding["sha256"] == packet["sha256"] &&
             binding["byte_length"] == packet["byte_length"] &&
             binding["authorization_token"] == route["authorization_token"],
             "#{label} Founder-reserved authorization mismatch")
    end

    branch = string(active["task_branch"], "active_work.task_branch")
    assert(branch != project["canonical_branch"], "Task branch must differ from canonical branch")
    worktree = string(active["task_worktree"], "active_work.task_worktree")
    root_base = File.realpath(string(project["task_worktree_root"], "project.task_worktree_root"))
    worktree_real = File.realpath(worktree)
    assert(worktree_real.start_with?(root_base + File::SEPARATOR), "Task worktree escapes task_worktree_root")
    stat = File.lstat(worktree)
    assert(stat.directory? && !stat.symlink?, "Task worktree must be a real directory")

    evidence = string(active["execution_evidence_root"], "active_work.execution_evidence_root")
    evidence_base = File.realpath(string(project["execution_evidence_root_base"],
                                         "project.execution_evidence_root_base"))
    evidence_real = File.realpath(evidence)
    assert(evidence_real.start_with?(evidence_base + File::SEPARATOR), "Task Evidence root escapes configured base")
    evidence_stat = File.lstat(evidence)
    assert(evidence_stat.directory? && !evidence_stat.symlink?, "Task Evidence root must be a real directory")

    assert(authority_record["branch"] == branch, "authority record branch mismatch")
    assert(Pathname.new(authority_record["worktree"].to_s).absolute?, "authority record worktree must be absolute")
    assert(Pathname.new(authority_record["evidence_root"].to_s).absolute?,
           "authority record Evidence root must be absolute")
    assert(File.realpath(authority_record["worktree"]) == worktree_real, "authority record worktree mismatch")
    assert(File.realpath(authority_record["evidence_root"]) == evidence_real, "authority record Evidence root mismatch")
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail!("active Task resource is unavailable (#{e.class})")
  end

  # Schema v2 is intentionally route-scoped. It validates the exact Founder
  # packet format selected by Truth, while every Task identity and limit is
  # read from packet/Truth/descriptor bytes rather than from Task constants.
  def v2_assert(condition, category, message)
    fail_category!(category, message) unless condition
  end

  def validate_external_effects_v2(value, label)
    effects = value.is_a?(Hash) ? value : nil
    v2_assert(!effects.nil? && effects.keys.sort == EXTERNAL_EFFECT_KEYS.sort,
              "EXTERNAL_EFFECT", "#{label} must contain exactly the six external-effect keys")
    v2_assert(effects == FALSE_EXTERNAL_EFFECTS, "EXTERNAL_EFFECT", "#{label} must remain exactly false")
    effects
  end

  def validate_legacy_v1_slot!(active_task_id, first_task_id)
    v2_assert(active_task_id == first_task_id, "LEGACY_V1",
              "legacy schema v1 may authorize only first Task / slot 1")
  end

  def validate_cumulative_hours_v2(total, maximum)
    v2_assert(total.is_a?(Integer) && total >= 0 && maximum.is_a?(Integer) && maximum.positive? && total <= maximum,
              "BUDGET", "cumulative scheduled engineering hours exceed route maximum")
  end

  def v2_identity(value, label)
    record = hash(value, label)
    v2_assert(record.keys.sort == %w[byte_length path sha256], "SCHEMA", "#{label} keys drifted")
    string(record["path"], "#{label}.path")
    digest = string(record["sha256"], "#{label}.sha256")
    v2_assert(SHA256_RE.match?(digest), "SCHEMA", "#{label}.sha256 must be lowercase SHA-256")
    v2_assert(integer(record["byte_length"], "#{label}.byte_length").positive?, "SCHEMA",
              "#{label}.byte_length must be positive")
    record
  end

  def v2_one_match(text, pattern, label)
    matches = text.scan(pattern)
    v2_assert(matches.length == 1, "PACKET_FORMAT", "packet must contain exactly one #{label}")
    match = matches.first
    match.is_a?(Array) && match.length == 1 ? match.first : match
  end

  def markdown_section(text, number, label)
    match = text.match(/^## #{Regexp.escape(number.to_s)}\.[^\n]*\n(.*?)(?=^## \d+\.|\z)/m)
    v2_assert(!match.nil?, "PACKET_FORMAT", "packet is missing #{label}")
    match[1]
  end

  def direct_cooperative_packet_claims(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    v2_assert(text.valid_encoding?, "PACKET_FORMAT", "direct packet must be valid UTF-8")
    section0 = markdown_section(text, 0, "Section 0")
    section2 = markdown_section(text, 2, "Section 2")
    section3 = markdown_section(text, 3, "Section 3")
    section5 = markdown_section(text, 5, "Section 5")
    section6 = markdown_section(text, 6, "Section 6")
    section8 = markdown_section(text, 8, "Section 8")
    section11 = markdown_section(text, 11, "Section 11")

    parent_commit = v2_one_match(section0, /- canonical commit: `([0-9a-f]{40})`/, "canonical commit")
    parent_tree = v2_one_match(section0, /- canonical tree: `([0-9a-f]{40})`/, "canonical tree")
    route_id = v2_one_match(section0, /- route_id: `([A-Z0-9_]+)`/, "route id")
    task_id = v2_one_match(section0, /- task_id: `(AIOS-P1-[0-9]{3}(?:_[A-Z0-9_]+)?)`/, "Task id")
    task_slot = Integer(v2_one_match(section0, /- task_slot: `(\d+)`/, "Task slot"), 10)
    lineage = v2_one_match(section0, /- execution_lineage_id: `([A-Z0-9_]+)`/, "execution lineage")
    objective = v2_one_match(section3, /`([^`]*minimum data-driven cooperative-local authority kernel[^`]*)`/m,
                             "engineering objective")

    inherited_path = v2_one_match(
      section5,
      /原 atomic route packet\s+`([^`]+)`\s+的 Section 8、9、10；/m,
      "inherited packet path"
    )
    inherited_length = Integer(v2_one_match(section5, /原 packet byte length: `(\d+)`/, "inherited packet length"), 10)
    inherited_sha = v2_one_match(section5, /原 packet SHA-256: `([0-9a-f]{64})`/, "inherited packet SHA-256")

    started_at = v2_one_match(section6, /- route started_at_utc: `([^`]+)`/, "route start")
    deadline_at = v2_one_match(section6, /- route deadline_utc: `([^`]+)`/, "route deadline")
    max_tasks = Integer(v2_one_match(section6, /- route maximum engineering Tasks: `(\d+)`/, "maximum Tasks"), 10)
    max_hours = Integer(v2_one_match(section6, /- route maximum scheduled engineering hours: `(\d+)`/,
                                     "maximum scheduled hours"), 10)
    max_days = Integer(v2_one_match(section6, /- route maximum calendar days: `(\d+)`/, "maximum calendar days"), 10)
    max_active_tasks = Integer(v2_one_match(section6, /- maximum active Tasks: `(\d+)`/, "maximum active Tasks"), 10)
    max_active_branches = Integer(v2_one_match(section6, /- maximum active Task branches: `(\d+)`/,
                                               "maximum active branches"), 10)
    max_active_worktrees = Integer(v2_one_match(section6, /- maximum active Task worktrees: `(\d+)`/,
                                                "maximum active worktrees"), 10)
    max_active_candidates = Integer(v2_one_match(section6, /- maximum active candidates at any time: `(\d+)`/,
                                                 "maximum active candidates"), 10)
    max_final_candidates = Integer(v2_one_match(section6, /- maximum final candidates per Task: `(\d+)`/,
                                                "maximum final candidates"), 10)
    max_final_reviews = Integer(v2_one_match(section6, /- maximum final review rounds per Task: `(\d+)`/,
                                             "maximum final reviews"), 10)
    capability_hours = Integer(v2_one_match(section6, /- P1-063 real engineering: at most `(\d+) engineering hours/,
                                            "P1-063 engineering hours"), 10)
    kernel_hours = Integer(v2_one_match(section6, /- minimum authority-kernel enabling work: at most `(\d+) engineering hours`/,
                                        "authority-kernel hours"), 10)
    combined = v2_one_match(section6, /- combined Task 1 cap: `(\d+) engineering hours \/ (\d+) calendar days`/,
                            "Task 1 combined cap")
    repair_count = Integer(v2_one_match(section6, /initial implementation plus at most `(\d+)` bounded same-Task repair/,
                                        "Task 1 repair count"), 10)
    task_candidates = Integer(v2_one_match(section6, /- exact final candidates for Task 1: `(\d+)`/,
                                           "Task 1 candidate count"), 10)
    task_reviews = Integer(v2_one_match(section6, /- final review rounds for Task 1: `(\d+)`/,
                                        "Task 1 review count"), 10)

    preserved_branch = v2_one_match(section2, /- branch: `([^`]+)`/, "preserved branch")
    preserved_worktree = v2_one_match(section2, /- worktree: `([^`]+)`/, "preserved worktree")
    token = v2_one_match(section11, /authorization_token=([A-Z0-9_]+)/, "authorization token")
    effect_names = section8.scan(/^- (network|Provider|Secret|remote|production|public)$/).flatten.map(&:downcase)
    v2_assert(effect_names.sort == EXTERNAL_EFFECT_KEYS.sort, "PACKET_FORMAT",
              "direct packet external-effect declarations drifted")

    {
      "route_id" => route_id,
      "task_id" => task_id,
      "task_slot" => task_slot,
      "execution_lineage_id" => lineage,
      "objective" => objective,
      "authorization_token" => token,
      "activation_parent" => { "commit" => parent_commit, "tree" => parent_tree },
      "inherited_packet" => { "path" => inherited_path, "sha256" => inherited_sha,
                                "byte_length" => inherited_length },
      "route_started_at_utc" => started_at,
      "route_deadline_utc" => deadline_at,
      "maximum_engineering_tasks" => max_tasks,
      "maximum_scheduled_engineering_hours" => max_hours,
      "maximum_calendar_days" => max_days,
      "maximum_active_tasks" => max_active_tasks,
      "maximum_active_task_branches" => max_active_branches,
      "maximum_active_task_worktrees" => max_active_worktrees,
      "maximum_active_candidates" => max_active_candidates,
      "maximum_final_candidates_per_task" => max_final_candidates,
      "maximum_final_review_rounds_per_task" => max_final_reviews,
      "task_1_scheduled_engineering_hours" => Integer(combined[0], 10),
      "task_1_calendar_days" => Integer(combined[1], 10),
      "task_1_authority_kernel_hours" => kernel_hours,
      "task_1_capability_hours" => capability_hours,
      "task_1_implementation_iterations" => repair_count + 1,
      "task_1_final_candidates" => task_candidates,
      "task_1_final_reviews" => task_reviews,
      "external_effects" => FALSE_EXTERNAL_EFFECTS,
      "preserved_branch" => preserved_branch,
      "preserved_worktree" => preserved_worktree
    }
  rescue ArgumentError
    fail_category!("PACKET_FORMAT", "direct packet contains a non-integer numeric claim")
  end

  def inherited_sections_claims(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    v2_assert(text.valid_encoding?, "PACKET_FORMAT", "inherited packet must be valid UTF-8")
    section8 = markdown_section(text, 8, "inherited Section 8")
    section9 = markdown_section(text, 9, "inherited Section 9")
    section10 = markdown_section(text, 10, "inherited Section 10")
    v2_assert(section8.include?("single semantic core") && section8.include?("append-only accounting sequence") &&
              section8.include?("task_slot") && section8.include?("64 accepted") && section8.include?("21-day"),
              "PACKET_FORMAT", "inherited authority-kernel requirements drifted")
    asset_ids = section9.scan(/P1-(\d{3}) accepted/).flatten.map { |digits| "p1_#{digits}" }.uniq
    v2_assert(!asset_ids.empty?, "PACKET_FORMAT", "inherited allowed inputs are missing")
    effects = {}
    section10.scan(/^- (network|Provider|Secret|remote|production|public): (true|false)$/).each do |name, value|
      effects[name.downcase] = value == "true"
    end
    v2_assert(effects == FALSE_EXTERNAL_EFFECTS, "PACKET_FORMAT",
              "inherited external-effect boundary is not exactly false")
    claim = v2_one_match(section10, /The maximum accepted claim is (.*?)(?:\n\n|\z)/m,
                         "inherited maximum claim").strip
    { "accepted_asset_ids" => asset_ids.sort, "external_effects" => effects, "claim" => claim }
  end

  def validate_goal_v2(truth, authority_record = nil)
    goal = hash(truth["goal"], "goal")
    v2_assert(goal["control_plane_status_observed"] == "ACTIVE", "GOAL_IDENTITY", "Goal must remain ACTIVE")
    source = string(goal["source_attachment_path"], "goal.source_attachment_path")
    raw = secure_read(source, "Goal source attachment")
    raw_sha = string(goal["observed_raw_body_sha256"], "goal.observed_raw_body_sha256")
    raw_length = integer(goal["observed_raw_body_byte_length"], "goal.observed_raw_body_byte_length")
    v2_assert(raw.bytesize == raw_length && sha256(raw) == raw_sha, "GOAL_IDENTITY", "Goal raw identity mismatch")
    canonical = canonical_goal_bytes(raw)
    canonical_sha = string(goal["observed_body_sha256"], "goal.observed_body_sha256")
    canonical_length = integer(goal["observed_body_byte_length"], "goal.observed_body_byte_length")
    v2_assert(canonical.bytesize == canonical_length && sha256(canonical) == canonical_sha,
              "GOAL_IDENTITY", "Goal canonical identity mismatch")
    return unless authority_record

    identity = hash(authority_record["goal_identity"], "authority goal_identity")
    v2_assert(identity["source_path"] == source && identity["raw_byte_length"] == raw_length &&
              identity["raw_sha256"] == raw_sha && identity["canonical_byte_length"] == canonical_length &&
              identity["canonical_sha256"] == canonical_sha &&
              identity["canonicalization"] == goal["body_canonicalization"],
              "GOAL_IDENTITY", "Authority Goal identity mismatch")
  end

  def validate_v2_packet(root, truth)
    route = hash(truth["current_phase_route"], "current_phase_route")
    kernel = hash(route["authority_kernel"], "current_phase_route.authority_kernel")
    v2_assert(kernel["schema_version"] == "2.0", "SCHEMA", "authority kernel schema must be 2.0")
    v2_assert(kernel["packet_format"] == "FOUNDER_DIRECT_COOPERATIVE_LOCAL_V1", "SCHEMA",
              "unsupported v2 packet format")
    v2_assert(kernel["semantic_core"] == "scripts/validate-current-task-authority.rb" &&
              kernel["safety_entry"] == "scripts/check-p1-safety-boundary.sh" &&
              kernel["safety_delegates_to_semantic_core"] == true &&
              kernel["legacy_v1_task_slot_limit"] == 1 &&
              kernel["descriptor_canonicalization"] == "SORTED_KEY_UTF8_JSON_V1" &&
              kernel["clock_assurance"] == "UNTRUSTED_WALL_CLOCK",
              "SCHEMA", "authority kernel declaration drifted")

    packet_identity = v2_identity(route["decision_packet"], "current_phase_route.decision_packet")
    packet_path = string(packet_identity["path"], "decision packet path")
    v2_assert(Pathname.new(packet_path).absolute?, "PACKET_IDENTITY", "decision packet path must be absolute")
    packet_bytes = validate_identity(packet_path, packet_identity, "Founder direct decision packet")
    claims = direct_cooperative_packet_claims(packet_bytes)
    v2_assert(route["route_id"] == claims["route_id"] &&
              route["authorization_token"] == claims["authorization_token"] &&
              route["activation_parent"] == claims["activation_parent"],
              "ROUTE_IDENTITY", "Truth route identity does not equal direct packet")
    validate_commit_tree(root, claims.dig("activation_parent", "commit"),
                         claims.dig("activation_parent", "tree"), "v2 activation parent")

    inherited = hash(route["inherited_engineering_packet"], "current_phase_route.inherited_engineering_packet")
    inherited_identity = {
      "path" => inherited["path"], "sha256" => inherited["sha256"], "byte_length" => inherited["byte_length"]
    }
    v2_identity(inherited_identity, "inherited engineering packet")
    v2_assert(inherited_identity == claims["inherited_packet"] && inherited["inherited_sections"] == [8, 9, 10],
              "PACKET_IDENTITY", "inherited packet binding drifted")
    inherited_bytes = validate_identity(inherited_identity["path"], inherited_identity,
                                        "inherited engineering packet")
    inherited_claims = inherited_sections_claims(inherited_bytes)
    [route, claims, inherited_claims, packet_identity]
  end

  def descriptor_list_ids(value, label)
    array(value, label).map do |record|
      item = hash(record, "#{label} entry")
      string(item["id"], "#{label} id")
    end
  end

  def validate_allowed_write_paths(paths, contract_path, truth, task_slot, claims)
    if task_slot == claims["task_slot"]
      allowed_exact = %w[
        scripts/validate-current-task-authority.rb
        scripts/test-current-task-authority.rb
        scripts/check-p1-safety-boundary.sh
        docs/aios/truth/project_state.yaml
        Makefile
        docs/PROJECT_CODE_MAP.md
      ] + [contract_path]
      paths.each do |path|
        safe_scope_path(path, "write allowlist path")
        permitted = allowed_exact.include?(path) || path.start_with?("evaluation-harness/") ||
                    (path.start_with?("scripts/") && !path.start_with?("scripts/validate-aios-governance"))
        v2_assert(permitted, "WRITE_SCOPE", "write allowlist path is outside direct Task packet: #{path}")
      end
      return
    end

    boundary = hash(truth["phase_boundary"], "phase_boundary")
    roots = flatten_write_roots(boundary["role_write_roots"])
    immutable = array(boundary["immutable_authority_paths"], "phase_boundary.immutable_authority_paths")
    paths.each do |path|
      safe_scope_path(path, "write allowlist path")
      v2_assert(roots.any? { |root_path| scope_within_root?(path, root_path) }, "WRITE_SCOPE",
                "future Task write path is outside Phase role roots: #{path}")
      v2_assert(immutable.none? { |item| scope_within_root?(path, item) || scope_within_root?(item, path) },
                "WRITE_SCOPE", "future Task write path overlaps immutable authority: #{path}")
    end
  end

  def validate_v2_task_bindings(root, truth, route, event, claims, inherited_claims, packet_identity)
    contract_identity = v2_identity(event["contract"], "scheduled Task contract")
    contract_path = repo_path(root, contract_identity["path"], "scheduled Task contract path")
    contract_bytes = validate_identity(contract_path, contract_identity, "scheduled Task contract")
    contract = parse_structured(contract_bytes, contract_path, "scheduled Task contract")
    v2_assert(contract["schema_version"] == "AIOS_TASK_DESCRIPTOR/2.0" &&
              contract["record_type"] == "PHASE_DELEGATED_ENGINEERING_TASK" && contract["status"] == "ACTIVE",
              "DESCRIPTOR_BINDING", "Task descriptor/Contract lifecycle identity drifted")

    authority_identity = v2_identity(event["authority"], "scheduled Task authority")
    v2_assert(Pathname.new(authority_identity["path"]).absolute?, "AUTHORITY_BINDING",
              "Task authority path must be absolute")
    authority_bytes = validate_identity(authority_identity["path"], authority_identity, "scheduled Task authority")
    authority = parse_structured(authority_bytes, authority_identity["path"], "scheduled Task authority")

    allowlist_identity = v2_identity(event["write_allowlist"], "scheduled write allowlist")
    v2_assert(Pathname.new(allowlist_identity["path"]).absolute?, "WRITE_SCOPE",
              "write allowlist path must be absolute")
    allowlist_bytes = validate_identity(allowlist_identity["path"], allowlist_identity, "scheduled write allowlist")
    allowlist = parse_structured(allowlist_bytes, allowlist_identity["path"], "scheduled write allowlist")

    descriptor = hash(contract["descriptor_payload"], "contract descriptor_payload")
    descriptor_sha = string(contract["descriptor_payload_sha256"], "contract descriptor_payload_sha256")
    v2_assert(contract["descriptor_canonicalization"] == "SORTED_KEY_UTF8_JSON_V1" &&
              canonical_digest(descriptor) == descriptor_sha && event["descriptor_payload_sha256"] == descriptor_sha,
              "DESCRIPTOR_BINDING", "descriptor payload digest mismatch")
    final_digest_input = {
      "descriptor_payload_sha256" => descriptor_sha,
      "contract" => contract_identity,
      "authority" => authority_identity,
      "write_allowlist" => allowlist_identity
    }
    final_digest = canonical_digest(final_digest_input)
    v2_assert(event["descriptor_digest"] == final_digest, "DESCRIPTOR_BINDING",
              "final descriptor digest mismatch")

    task = hash(contract["task"], "contract task")
    expected_task = {
      "task_id" => event["task_id"], "route_id" => route["route_id"],
      "task_slot" => event["task_slot"], "execution_lineage_id" => event["execution_lineage_id"]
    }
    expected_task.each do |key, expected|
      v2_assert(task[key] == expected && descriptor[key] == expected, "DESCRIPTOR_BINDING",
                "Task #{key} projection mismatch")
    end
    v2_assert(SAFE_TASK_ID_RE.match?(event["task_id"].to_s), "DESCRIPTOR_BINDING", "Task id form is invalid")

    accepted_input_ids = descriptor_list_ids(contract["accepted_inputs"], "contract accepted_inputs")
    accepted_substrate_ids = descriptor_list_ids(contract["accepted_substrates"], "contract accepted_substrates")
    used_asset_ids = accepted_input_ids + accepted_substrate_ids
    v2_assert(descriptor["accepted_input_ids"] == accepted_input_ids &&
              descriptor["accepted_substrate_ids"] == accepted_substrate_ids &&
              used_asset_ids.uniq.length == used_asset_ids.length && !used_asset_ids.empty? &&
              (used_asset_ids - inherited_claims["accepted_asset_ids"]).empty?,
              "ACCEPTED_ASSET", "accepted input/substrate descriptor binding mismatch")
    if event["task_slot"] == claims["task_slot"]
      v2_assert(used_asset_ids.sort == inherited_claims["accepted_asset_ids"], "ACCEPTED_ASSET",
                "direct Task 1 must bind all inherited accepted assets")
    end
    accepted_input_ids.each do |input_id|
      input = hash(route.dig("accepted_inputs", input_id), "route accepted input #{input_id}")
      contract_record = contract["accepted_inputs"].find { |record| record["id"] == input_id }
      v2_assert(input["task_id"] == contract_record["task_id"] && input["status"] == contract_record["status"],
                "ACCEPTED_ASSET", "accepted input #{input_id} identity mismatch")
    end
    accepted_substrate_ids.each do |substrate_id|
      substrate = hash(route.dig("accepted_substrates", substrate_id), "route accepted substrate #{substrate_id}")
      contract_record = contract["accepted_substrates"].find { |record| record["id"] == substrate_id }
      v2_assert(substrate["task_id"] == contract_record["task_id"] && substrate["status"] == contract_record["status"],
                "ACCEPTED_ASSET", "accepted substrate #{substrate_id} identity mismatch")
    end

    budget = hash(contract["budget"], "contract budget")
    budget_bindings = {
      "scheduled_engineering_hours" => event["scheduled_engineering_hours"],
      "implementation_iterations_cap" => event["implementation_iterations_cap"],
      "final_candidates_cap" => event["final_candidates_cap"],
      "final_review_rounds_cap" => event["final_review_rounds_cap"]
    }
    budget_bindings.each do |key, expected|
      v2_assert(budget[key] == expected && descriptor[key] == expected, "BUDGET", "Task #{key} mismatch")
    end
    v2_assert(budget["contract_corrections_cap"] == 0, "BUDGET", "Contract corrections must remain forbidden")
    if event["task_slot"] == claims["task_slot"]
      v2_assert(budget["authority_kernel_engineering_hours_cap"] == claims["task_1_authority_kernel_hours"] &&
                budget["p1_063_engineering_hours_cap"] == claims["task_1_capability_hours"] &&
                budget["task_calendar_days_cap"] == claims["task_1_calendar_days"] &&
                budget["authority_kernel_engineering_hours_cap"] + budget["p1_063_engineering_hours_cap"] <=
                  budget["scheduled_engineering_hours"],
                "PACKET_BINDING", "Task 1 component/calendar budgets do not match direct packet")
    end
    validate_external_effects_v2(contract["external_effects"], "contract external_effects")
    validate_external_effects_v2(descriptor["external_effects"], "descriptor external_effects")
    v2_assert(descriptor["claim_boundary"] == task["claim_boundary"], "DESCRIPTOR_BINDING",
              "claim boundary projection mismatch")
    v2_assert(descriptor["authority_id"] == route["authorization_token"] &&
              descriptor["authority_record_path"] == authority_identity["path"] &&
              descriptor["contract_path"] == contract_identity["path"] &&
              descriptor["objective"].is_a?(String) && !descriptor["objective"].empty? &&
              task["objective"].is_a?(String) && !task["objective"].empty?,
              "DESCRIPTOR_BINDING", "descriptor authority/path/objective binding mismatch")

    authorization = hash(contract["authorization"], "contract authorization")
    v2_assert(authorization["authorization_id"] == route["authorization_token"] &&
              authorization["decision_packet"] == packet_identity &&
              authorization.dig("authority_record", "path") == authority_identity["path"] &&
              authorization["write_allowlist"] == allowlist_identity,
              "AUTHORITY_BINDING", "Contract authorization binding mismatch")
    v2_assert(contract["canonical_parent"]&.slice("commit", "tree") == event["canonical_parent"],
              "PARENT_CHAIN", "Contract canonical parent mismatch")

    v2_assert(authority["schema_version"] == "AIOS_TASK_AUTHORITY/2.0" &&
              authority["record_type"] == "FOUNDER_PACKET_DERIVED_PHASE_TASK_AUTHORITY" &&
              authority["status"] == "ACTIVE" &&
              authority.dig("authorization", "token") == route["authorization_token"] &&
              authority.dig("authorization", "packet_path") == packet_identity["path"] &&
              authority.dig("authorization", "packet_byte_length") == packet_identity["byte_length"] &&
              authority.dig("authorization", "packet_sha256") == packet_identity["sha256"] &&
              authority.dig("authorization", "direct_task_authority") == true &&
              authority.dig("authorization", "separate_preimplementation_contract_review_gate") == false,
              "AUTHORITY_BINDING", "Authority packet binding mismatch")
    authority_task = hash(authority["task"], "authority task")
    {
      "task_id" => event["task_id"], "task_slot" => event["task_slot"],
      "execution_lineage_id" => event["execution_lineage_id"],
      "scheduled_engineering_hours" => event["scheduled_engineering_hours"],
      "implementation_iterations_cap" => event["implementation_iterations_cap"],
      "final_candidates_cap" => event["final_candidates_cap"],
      "final_review_rounds_cap" => event["final_review_rounds_cap"]
    }.each do |key, expected|
      v2_assert(authority_task[key] == expected, "AUTHORITY_BINDING", "Authority Task #{key} mismatch")
    end
    v2_assert(authority.dig("route", "route_id") == route["route_id"] &&
              authority["descriptor"] == {
                "path" => contract_identity["path"], "byte_length" => contract_identity["byte_length"],
                "sha256" => contract_identity["sha256"], "payload_canonicalization" => "SORTED_KEY_UTF8_JSON_V1",
                "payload_sha256" => descriptor_sha
              } && authority["write_allowlist"]&.slice("path", "byte_length", "sha256") == allowlist_identity &&
              authority["canonical_parent"]&.slice("commit", "tree") == event["canonical_parent"],
              "AUTHORITY_BINDING", "Authority descriptor/route/parent binding mismatch")
    authority_route = hash(authority["route"], "authority route")
    contract_envelope = hash(contract["route_envelope"], "contract route_envelope")
    route_caps = {
      "maximum_engineering_tasks" => claims["maximum_engineering_tasks"],
      "maximum_scheduled_engineering_hours" => claims["maximum_scheduled_engineering_hours"],
      "maximum_calendar_days" => claims["maximum_calendar_days"],
      "maximum_active_tasks" => claims["maximum_active_tasks"],
      "maximum_active_task_branches" => claims["maximum_active_task_branches"],
      "maximum_active_task_worktrees" => claims["maximum_active_task_worktrees"],
      "maximum_active_candidates" => claims["maximum_active_candidates"]
    }
    route_caps.each do |key, expected|
      v2_assert(authority_route[key] == expected && contract_envelope[key] == expected,
                "AUTHORITY_BINDING", "Task route envelope #{key} mismatch")
    end
    v2_assert(authority_route["started_at_utc"] == claims["route_started_at_utc"] &&
              authority_route["deadline_utc"] == claims["route_deadline_utc"],
              "ROUTE_WINDOW", "Authority route window mismatch")
    validate_external_effects_v2(authority["external_effects"], "authority external_effects")
    v2_assert(authority["claim_boundary"] == descriptor["claim_boundary"], "DESCRIPTOR_BINDING",
              "Authority claim boundary mismatch")
    reviewer_policy = hash(authority.dig("roles", "final_reviewers"), "authority final reviewers")
    v2_assert(reviewer_policy["independent_of_implementers"] == true &&
              reviewer_policy["roles"] == %w[CTO Security Quality] && reviewer_policy["review_rounds"] == 1,
              "AUTHORITY_BINDING", "independent final-review policy drifted")

    v2_assert(allowlist["schema_version"] == "AIOS_INTERNAL_WRITE_ALLOWLIST/1" &&
              allowlist["authorization_token"] == route["authorization_token"] &&
              allowlist["authorization_packet"] == packet_identity && allowlist["route_id"] == route["route_id"] &&
              allowlist["task_id"] == event["task_id"] && allowlist["task_slot"] == event["task_slot"] &&
              allowlist["execution_lineage_id"] == event["execution_lineage_id"] &&
              allowlist["canonical_parent"] == event["canonical_parent"],
              "WRITE_SCOPE", "write allowlist authority binding mismatch")
    v2_assert(allowlist.dig("freeze_policy", "paths_may_not_expand_after_first_source_mutation") == true &&
              allowlist.dig("freeze_policy", "accepted_p1_035_p1_048_p1_055_bytes_are_read_only") == true,
              "WRITE_SCOPE", "write allowlist freeze policy drifted")
    validate_external_effects_v2(allowlist.dig("freeze_policy", "external_effects"),
                                 "write allowlist external_effects")
    path_records = array(allowlist["allowed_source_paths"], "allowed_source_paths")
    paths = path_records.map { |record| string(hash(record, "allowed source path")["path"], "allowed source path.path") }
    v2_assert(paths.uniq.length == paths.length, "WRITE_SCOPE", "write allowlist contains duplicate paths")
    validate_allowed_write_paths(paths, contract_identity["path"], truth, event["task_slot"], claims)

    execution = hash(authority["execution"], "authority execution")
    contract_execution = hash(contract["execution"], "contract execution")
    %w[branch worktree evidence_root].each do |key|
      v2_assert(execution[key] == contract_execution[key] && execution[key] == allowlist[key],
                "RESOURCE_SET", "Task #{key} binding mismatch")
    end
    v2_assert(contract_execution["scheduled_at_utc"] == event["scheduled_at_utc"] &&
              contract_execution["task_deadline_utc"] == event["task_deadline_utc"] &&
              authority_task["scheduled_at_utc"] == event["scheduled_at_utc"] &&
              authority_task["deadline_utc"] == event["task_deadline_utc"],
              "ROUTE_WINDOW", "Task schedule window projection mismatch")
    evidence_root = File.realpath(execution["evidence_root"])
    v2_assert(File.realpath(authority_identity["path"]).start_with?(evidence_root + File::SEPARATOR) &&
              File.realpath(allowlist_identity["path"]).start_with?(evidence_root + File::SEPARATOR),
              "RESOURCE_SET", "Authority or allowlist escaped the Task Evidence root")
    validate_goal_v2(truth, authority)
    {
      "contract" => contract, "authority" => authority, "allowlist" => allowlist,
      "paths" => paths, "descriptor_digest" => final_digest, "descriptor" => descriptor,
      "execution" => execution
    }
  end

  def validate_v2_envelope(route, claims, now)
    envelope = hash(route["envelope"], "current_phase_route.envelope")
    expected = {
      "max_engineering_tasks" => claims["maximum_engineering_tasks"],
      "max_engineering_hours" => claims["maximum_scheduled_engineering_hours"],
      "max_calendar_days" => claims["maximum_calendar_days"],
      "max_active_tasks" => claims["maximum_active_tasks"],
      "max_task_branches" => claims["maximum_active_task_branches"],
      "max_task_worktrees" => claims["maximum_active_task_worktrees"],
      "max_active_candidates" => claims["maximum_active_candidates"],
      "max_candidate_review_rounds_per_task" => claims["maximum_final_review_rounds_per_task"]
    }
    expected.each do |key, value|
      v2_assert(envelope[key] == value, "BUDGET", "route envelope #{key} does not match packet")
    end
    v2_assert(envelope["max_contract_corrections_per_task"] == 0 && envelope["max_same_task_repairs"] == 1,
              "BUDGET", "v2 repair/correction envelope drifted")
    v2_assert(envelope["successor_replacement_normalization_closure_feasibility_or_remediation_chain_allowed"] == false &&
              envelope["p2_entry_authorized"] == false && envelope["p3_entry_authorized"] == false,
              "PHASE_BOUNDARY", "route envelope expands the authorized phase")
    validate_external_effects_v2(envelope["external_effects"], "route envelope external_effects")

    started_at = utc_time(claims["route_started_at_utc"], "packet route start")
    deadline_at = utc_time(claims["route_deadline_at_utc"] || claims["route_deadline_utc"], "packet route deadline")
    v2_assert((deadline_at - started_at).to_i == claims["maximum_calendar_days"] * 86_400,
              "ROUTE_WINDOW", "route window duration does not match packet")
    v2_assert(now >= started_at, "ROUTE_WINDOW", "route has not started")
    [envelope, started_at, deadline_at]
  end

  def validate_v2_current_parent_prefix(root, route, transitions, remaining)
    parent_commit, _stderr, parent_status = git(root, "rev-parse", "HEAD^", allow_failure: true)
    return unless parent_status.success?

    parent_truth_bytes, _show_stderr, show_status = git(
      root, "show", "#{parent_commit.strip}:docs/aios/truth/project_state.yaml", allow_failure: true
    )
    return unless show_status.success?

    parent_truth = parse_yaml(parent_truth_bytes, "current canonical parent Truth")
    parent_route = parent_truth["current_phase_route"]
    return unless parent_route.is_a?(Hash) && parent_route.dig("authority_kernel", "schema_version") == "2.0"

    v2_assert(parent_route["route_id"] == route["route_id"] &&
              parent_route["authorization_token"] == route["authorization_token"] &&
              parent_route["decision_packet"] == route["decision_packet"] &&
              parent_route["activation_parent"] == route["activation_parent"],
              "PARENT_CHAIN", "route identity changed across current canonical parent")
    parent_transitions = array(parent_route.dig("accounting", "transitions"),
                               "current canonical parent transitions")
    v2_assert(transitions.length >= parent_transitions.length &&
              transitions.first(parent_transitions.length) == parent_transitions,
              "PARENT_CHAIN", "current ledger deleted, mutated, reset, or reordered its canonical-parent prefix")
    parent_remaining = hash(parent_route.dig("accounting", "remaining"),
                            "current canonical parent remaining budget")
    v2_assert(remaining["task_slots"] <= parent_remaining["task_slots"] &&
              remaining["scheduled_engineering_hours"] <= parent_remaining["scheduled_engineering_hours"],
              "BUDGET", "remaining route budget increased across current canonical parent")
  end

  def validate_v2_accounting(root, truth, route, claims, inherited_claims, packet_identity, now)
    accounting = hash(route["accounting"], "current_phase_route.accounting")
    v2_assert(accounting["schema_version"] == "2.0" && accounting["route_id"] == route["route_id"],
              "ACCOUNTING_SEQUENCE", "route accounting identity mismatch")
    envelope, started_at, deadline_at = validate_v2_envelope(route, claims, now)
    accounting_expected = {
      "route_started_at_utc" => claims["route_started_at_utc"],
      "route_deadline_utc" => claims["route_deadline_utc"],
      "maximum_engineering_tasks" => claims["maximum_engineering_tasks"],
      "maximum_scheduled_engineering_hours" => claims["maximum_scheduled_engineering_hours"],
      "maximum_calendar_days" => claims["maximum_calendar_days"],
      "maximum_active_tasks" => claims["maximum_active_tasks"],
      "maximum_active_task_branches" => claims["maximum_active_task_branches"],
      "maximum_active_task_worktrees" => claims["maximum_active_task_worktrees"],
      "maximum_active_candidates" => claims["maximum_active_candidates"]
    }
    accounting_expected.each do |key, value|
      v2_assert(accounting[key] == value, "ACCOUNTING_SEQUENCE", "accounting #{key} mismatch")
    end

    transitions = array(accounting["transitions"], "accounting.transitions")
    v2_assert(!transitions.empty?, "ACCOUNTING_SEQUENCE", "route accounting must contain a schedule transition")
    open = nil
    scheduled = []
    lineages = []
    total_hours = 0
    bindings = {}
    transitions.each_with_index do |raw_event, index|
      event = hash(raw_event, "accounting transition #{index + 1}")
      v2_assert(event["sequence"] == index + 1, "ACCOUNTING_SEQUENCE", "accounting sequence gap or reorder")
      parent = hash(event["canonical_parent"], "transition canonical_parent")
      validate_commit_tree(root, parent["commit"], parent["tree"], "transition #{index + 1} canonical parent")
      _out, _err, ancestor = git(root, "merge-base", "--is-ancestor", parent["commit"], "HEAD", allow_failure: true)
      v2_assert(ancestor.success?, "PARENT_CHAIN", "transition canonical parent is not an ancestor")
      if index.zero?
        v2_assert(parent == route["activation_parent"], "PARENT_CHAIN",
                  "first transition parent must equal route activation parent")
      else
        parent_truth_bytes, _stderr, parent_status = git(
          root, "show", "#{parent['commit']}:docs/aios/truth/project_state.yaml", allow_failure: true
        )
        v2_assert(parent_status.success?, "PARENT_CHAIN", "transition parent Truth is unavailable")
        parent_truth = parse_yaml(parent_truth_bytes, "transition parent Truth")
        parent_route = parent_truth["current_phase_route"]
        v2_assert(parent_route.is_a?(Hash) && parent_route["route_id"] == route["route_id"],
                  "PARENT_CHAIN", "transition parent route identity drifted")
        parent_prefix = parent_route.dig("accounting", "transitions")
        v2_assert(parent_prefix == transitions.first(index), "PARENT_CHAIN",
                  "transition parent ledger is not the exact append-only prefix")
        parent_remaining = parent_route.dig("accounting", "remaining")
        if parent_remaining.is_a?(Hash)
          current_remaining = hash(accounting["remaining"], "accounting.remaining")
          v2_assert(current_remaining["task_slots"] <= parent_remaining["task_slots"] &&
                    current_remaining["scheduled_engineering_hours"] <= parent_remaining["scheduled_engineering_hours"],
                    "BUDGET", "remaining route budget increased across canonical parent")
        end
      end

      case event["transition"]
      when "SCHEDULED"
        v2_assert(open.nil?, "ACCOUNTING_SEQUENCE", "predecessor-open scheduling or multiple open Tasks")
        expected_slot = scheduled.length + 1
        v2_assert(event["task_slot"] == expected_slot && expected_slot <= envelope["max_engineering_tasks"],
                  "ACCOUNTING_SEQUENCE", "Task slot gap, duplicate, or route overflow")
        v2_assert(event["status"] == "OPEN", "ACCOUNTING_SEQUENCE", "scheduled Task must be OPEN")
        v2_assert(!lineages.include?(event["execution_lineage_id"]), "ACCOUNTING_SEQUENCE",
                  "execution lineage was reused")
        v2_assert(!historical_execution_lineage_ids(truth).include?(event["execution_lineage_id"]),
                  "ACCOUNTING_SEQUENCE", "execution lineage reuses historical Truth")
        lineages << string(event["execution_lineage_id"], "execution_lineage_id")
        hours = integer(event["scheduled_engineering_hours"], "scheduled engineering hours")
        v2_assert(hours.positive?, "BUDGET", "scheduled engineering hours must be positive")
        total_hours += hours
        validate_cumulative_hours_v2(total_hours, envelope["max_engineering_hours"])
        v2_assert(integer(event["implementation_iterations_cap"], "implementation cap").between?(1, 2),
                  "BUDGET", "implementation iteration cap exceeds two")
        v2_assert(event["final_candidates_cap"] == 1 && event["final_review_rounds_cap"] == 1,
                  "BUDGET", "candidate or final-review cap exceeds one")
        v2_assert(integer(event["implementation_iterations_used"], "implementation iterations used").between?(0, event["implementation_iterations_cap"]),
                  "BUDGET", "implementation iteration usage exceeds cap")
        v2_assert(integer(event["final_candidates_used"], "final candidates used").between?(0, 1) &&
                  integer(event["final_review_rounds_used"], "final reviews used").between?(0, 1),
                  "BUDGET", "candidate/review usage exceeds cap")
        scheduled_at = utc_time(event["scheduled_at_utc"], "Task scheduled_at_utc")
        task_deadline = utc_time(event["task_deadline_utc"], "Task deadline_at_utc")
        v2_assert(scheduled_at >= started_at && scheduled_at <= deadline_at && task_deadline <= deadline_at &&
                  task_deadline > scheduled_at, "ROUTE_WINDOW", "Task schedule escapes route window")
        if expected_slot == claims["task_slot"]
          v2_assert(event["task_id"] == claims["task_id"] &&
                    event["execution_lineage_id"] == claims["execution_lineage_id"] &&
                    hours == claims["task_1_scheduled_engineering_hours"] &&
                    event["implementation_iterations_cap"] == claims["task_1_implementation_iterations"] &&
                    event["final_candidates_cap"] == claims["task_1_final_candidates"] &&
                    event["final_review_rounds_cap"] == claims["task_1_final_reviews"] &&
                    (task_deadline - scheduled_at).to_i <= claims["task_1_calendar_days"] * 86_400,
                    "PACKET_BINDING", "Task 1 schedule does not equal direct packet")
        end
        bindings[event["task_slot"]] = validate_v2_task_bindings(
          root, truth, route, event, claims, inherited_claims, packet_identity
        )
        scheduled << event
        open = event
      when "USAGE_RECORDED"
        v2_assert(!open.nil? && event["task_slot"] == open["task_slot"] &&
                  event["task_id"] == open["task_id"] &&
                  event["execution_lineage_id"] == open["execution_lineage_id"] &&
                  event["descriptor_digest"] == open["descriptor_digest"],
                  "ACCOUNTING_SEQUENCE", "usage transition does not bind the unique open Task")
        usage_fields = %w[implementation_iterations_used final_candidates_used final_review_rounds_used]
        usage_fields.each do |key|
          value = integer(event[key], "usage transition #{key}")
          v2_assert(value >= open[key] && value <= open[key.sub("_used", "_cap")],
                    "BUDGET", "#{key} decreased or exceeded its cap")
        end
        open = open.merge(event.slice(*usage_fields))
      when "TERMINAL"
        v2_assert(!open.nil? && event["task_slot"] == open["task_slot"] &&
                  event["task_id"] == open["task_id"] && event["execution_lineage_id"] == open["execution_lineage_id"] &&
                  event["descriptor_digest"] == open["descriptor_digest"],
                  "ACCOUNTING_SEQUENCE", "terminal transition does not close the unique open Task")
        v2_assert(event["status"].is_a?(String) && event["status"].start_with?("TERMINAL_"),
                  "ACCOUNTING_SEQUENCE", "terminal transition status is invalid")
        open = nil
      else
        fail_category!("ACCOUNTING_SEQUENCE", "unsupported accounting transition #{event['transition'].inspect}")
      end
    end

    remaining = hash(accounting["remaining"], "accounting.remaining")
    expected_remaining = {
      "task_slots" => envelope["max_engineering_tasks"] - scheduled.length,
      "scheduled_engineering_hours" => envelope["max_engineering_hours"] - total_hours
    }
    v2_assert(remaining == expected_remaining && accounting["open_task_count"] == (open ? 1 : 0),
              "BUDGET", "derived accounting counters drifted")
    validate_v2_current_parent_prefix(root, route, transitions, remaining)
    v2_assert(now <= deadline_at || open.nil?, "ROUTE_WINDOW", "active route exceeded its untrusted wall-clock deadline")
    [open, bindings, transitions]
  end

  def validate_v2_active_projection(truth, route, open, bindings, packet_identity)
    active = hash(truth["active_work"], "active_work")
    if open.nil?
      v2_assert(active["current_task"] == "NONE", "ACTIVE_PROJECTION",
                "active_work must be NONE when ledger has no open Task")
      current = route["current_task"]
      v2_assert(current.nil? || (current.is_a?(Hash) && current["status"].to_s.start_with?("TERMINAL")),
                "ACTIVE_PROJECTION", "route current_task remains active after terminal accounting")
      return
    end
    project = hash(truth["project"], "project")
    v2_assert(route["status"] == "ACTIVE" && %w[ACTIVE EXECUTING].include?(project["phase_execution_status"]) &&
              %w[ACTIVE EXECUTING].include?(project["p1_execution_status"]),
              "ACTIVE_PROJECTION", "open Task requires active route/project execution")
    binding = bindings.fetch(open["task_slot"])
    expected = {
      "route_id" => route["route_id"], "current_task" => open["task_id"],
      "task_slot" => open["task_slot"], "execution_lineage_id" => open["execution_lineage_id"],
      "descriptor_digest" => open["descriptor_digest"], "current_task_contract" => open["contract"],
      "authority_record" => open["authority"], "write_allowlist" => open["write_allowlist"],
      "activation_parent_commit" => open.dig("canonical_parent", "commit"),
      "activation_parent_tree" => open.dig("canonical_parent", "tree")
    }
    expected.each do |key, value|
      v2_assert(active[key] == value, "ACTIVE_PROJECTION", "active_work.#{key} is not derived from open Task")
    end
    v2_assert(active["current_task_status"].is_a?(String) && active["current_task_status"].start_with?("ACTIVE"),
              "ACTIVE_PROJECTION", "active Task status is not active")
    v2_assert(active["current_task_contract_sha256"] == open.dig("contract", "sha256") &&
              active["current_execution_authorization"] == packet_identity["path"] &&
              active["current_execution_authorization_sha256"] == packet_identity["sha256"] &&
              active["authorization_id"] == route["authorization_token"] &&
              active["execution_nonce"] == open["execution_lineage_id"] &&
              active["execution_nonce_status"] == "UNIQUE_WITHIN_ROUTE_SLOT_AND_LINEAGE",
              "ACTIVE_PROJECTION", "active authority/nonce projection mismatch")
    v2_assert(active["task_branch"] == binding.dig("execution", "branch") &&
              active["task_worktree"] == binding.dig("execution", "worktree") &&
              active["execution_evidence_root"] == binding.dig("execution", "evidence_root") &&
              active["allowlisted_paths"] == binding["paths"],
              "ACTIVE_PROJECTION", "active resource/write projection mismatch")
    budget = hash(active["budget"], "active_work.budget")
    contract_budget = hash(binding.dig("contract", "budget"), "contract budget")
    budget_expected = {
      "engineering_hours" => contract_budget["scheduled_engineering_hours"],
      "calendar_days" => contract_budget["task_calendar_days_cap"],
      "implementation_iterations" => contract_budget["implementation_iterations_cap"],
      "candidates" => contract_budget["final_candidates_cap"],
      "final_review_rounds" => contract_budget["final_review_rounds_cap"]
    }
    optional_components = {
      "authority_kernel_engineering_hours" => "authority_kernel_engineering_hours_cap",
      "p1_063_engineering_hours" => "p1_063_engineering_hours_cap"
    }
    optional_components.each do |active_key, contract_key|
      budget_expected[active_key] = contract_budget[contract_key] if contract_budget.key?(contract_key)
    end
    budget_expected.each do |key, expected|
      v2_assert(budget[key] == expected, "BUDGET", "active Task budget #{key} projection mismatch")
    end
    v2_assert((budget.keys - budget_expected.keys).empty?, "BUDGET", "active Task budget has unbound fields")
    validate_external_effects_v2(active["external_effects"], "active_work.external_effects")
    roles = hash(active["roles"], "active_work.roles")
    owner = string(roles["owner"], "active_work.roles.owner")
    worker = string(roles["worker"], "active_work.roles.worker")
    reviewers = array(roles["independent_reviewers"], "active_work.roles.independent_reviewers")
    v2_assert(reviewers.length == 3 && reviewers.all? { |reviewer| reviewer.is_a?(String) && !reviewer.empty? } &&
              ([owner, worker] + reviewers).uniq.length == 5,
              "ACTIVE_PROJECTION", "active Task requires three distinct independent reviewers")
    v2_assert(active["founder_reserved_authorization"] == packet_identity["path"] &&
              active["founder_reserved_authorization_sha256"] == packet_identity["sha256"] &&
              active["founder_decision_required"] == false && active["user_action_required"] == "NONE",
              "ACTIVE_PROJECTION", "active Founder authorization projection mismatch")
    current = hash(route["current_task"], "current_phase_route.current_task")
    %w[task_id task_slot execution_lineage_id descriptor_digest].each do |key|
      source_key = key == "task_id" ? "current_task" : key
      v2_assert(current[key] == active[source_key], "ACTIVE_PROJECTION", "route current_task #{key} mismatch")
    end
    candidate_status = string(current["candidate_status"], "current_phase_route.current_task.candidate_status")
    if open["final_candidates_used"].zero?
      v2_assert(candidate_status == "NOT_CREATED", "ACTIVE_PROJECTION",
                "candidate status claims a candidate before accounting")
    else
      v2_assert(candidate_status != "NOT_CREATED", "ACTIVE_PROJECTION",
                "candidate accounting is not projected by current_task")
    end
    goal_authority = truth.dig("goal", "current_task_authority")
    v2_assert(goal_authority.is_a?(String) && goal_authority != "NONE", "ACTIVE_PROJECTION",
              "Goal does not project active Task authority")
  end

  def validate_v2_worktrees(root, truth, route, open, bindings, claims)
    project = hash(truth["project"], "project")
    canonical = File.realpath(string(project["canonical_repository"], "project.canonical_repository"))
    records = worktrees(root)
    preserved = hash(route["preserved_inactive_terminal_worktree"], "preserved inactive worktree")
    v2_assert(preserved["branch"] == claims["preserved_branch"] &&
              preserved["worktree"] == claims["preserved_worktree"] &&
              preserved["counts_as_active_task_branch_or_worktree"] == false,
              "RESOURCE_SET", "preserved inactive worktree does not equal packet")
    expected_paths = [canonical, File.realpath(preserved["worktree"])]
    active_path = nil
    if open
      active_path = File.realpath(bindings.fetch(open["task_slot"]).dig("execution", "worktree"))
      configured_worktree_root = File.realpath(string(project["task_worktree_root"], "project.task_worktree_root"))
      configured_evidence_root = File.realpath(
        string(project["execution_evidence_root_base"], "project.execution_evidence_root_base")
      )
      evidence_path = File.realpath(bindings.fetch(open["task_slot"]).dig("execution", "evidence_root"))
      v2_assert(active_path.start_with?(configured_worktree_root + File::SEPARATOR) &&
                evidence_path.start_with?(configured_evidence_root + File::SEPARATOR),
                "RESOURCE_SET", "active Task worktree or Evidence root escaped configured base")
      expected_paths << active_path
    end
    actual_paths = records.map { |record| File.realpath(record["path"]) }
    v2_assert(actual_paths.sort == expected_paths.uniq.sort, "RESOURCE_SET",
              "Git worktree set must equal canonical + packet-preserved + unique open Task")
    canonical_record = records.find { |record| File.realpath(record["path"]) == canonical }
    v2_assert(canonical_record && canonical_record["branch"] == project["canonical_branch"], "RESOURCE_SET",
              "canonical worktree branch mismatch")
    preserved_record = records.find { |record| File.realpath(record["path"]) == File.realpath(preserved["worktree"]) }
    v2_assert(preserved_record && preserved_record["branch"] == preserved["branch"] &&
              preserved_record["head"] == route.dig("activation_parent", "commit"),
              "RESOURCE_SET", "preserved terminal worktree identity drifted")
    if open
      active_record = records.find { |record| File.realpath(record["path"]) == active_path }
      v2_assert(active_record && active_record["branch"] == bindings.fetch(open["task_slot"]).dig("execution", "branch"),
                "RESOURCE_SET", "active Task worktree branch mismatch")
      _out, _err, status = git(root, "merge-base", "--is-ancestor", open.dig("canonical_parent", "commit"),
                                active_record["head"], allow_failure: true)
      v2_assert(status.success?, "PARENT_CHAIN", "active Task worktree does not descend from canonical parent")
    end
    root_real = File.realpath(root)
    v2_assert([canonical, active_path].compact.include?(root_real), "REPOSITORY",
              "validator must run from canonical or declared active Task worktree")
    current_record = records.find { |record| File.realpath(record["path"]) == root_real }
    v2_assert(git(canonical, "status", "--porcelain=v1", "--untracked-files=all").first.empty?,
              "REPOSITORY", "canonical repository must be clean")
    v2_assert(current_record && git(root, "status", "--porcelain=v1", "--untracked-files=all").first.empty?,
              "REPOSITORY", "validation worktree must be clean")
    tracked = git(root, "ls-files").first.lines.map(&:strip).select { |path| path.split("/").include?(".sourcelens-audit") }
    v2_assert(tracked.empty?, "EVIDENCE_GIT_LEAK", "external Evidence material leaked into Git")
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail_category!("RESOURCE_SET", "v2 worktree resource unavailable (#{e.class})")
  end


  def validate_phase_boundary_v2(truth)
    boundary = hash(truth["phase_boundary"], "phase_boundary")
    v2_assert(boundary["phase"] == "P1", "PHASE_BOUNDARY", "phase boundary must remain P1")
    task_kinds = array(boundary["allowed_task_kinds"], "phase_boundary.allowed_task_kinds")
    v2_assert(!task_kinds.empty? && task_kinds.all? { |kind| kind.is_a?(String) && kind.start_with?("EVALUATION_FOUNDATION_") },
              "PHASE_BOUNDARY", "P1 task-kind boundary drifted")
    allowed = array(boundary["allowed_capabilities"], "phase_boundary.allowed_capabilities")
    deferred = array(boundary["deferred_capabilities"], "phase_boundary.deferred_capabilities")
    forbidden = %w[
      P2_REPOSITORY_INTELLIGENCE_CAPABILITY_CLAIM P3_SINGLE_AGENT_RUNTIME AGENT_SHELL
      MODEL_INITIATED_CANONICAL_WRITE PLATFORM_IDENTITY SUPERVISOR ROOT_CUSTODY STRONG_ISOLATION
      MULTI_AGENT_RUNTIME
    ]
    v2_assert((allowed & forbidden).empty? && (forbidden - deferred).empty?, "PHASE_BOUNDARY",
              "P1 boundary admits a deferred capability")
    validate_external_effects_v2(boundary["default_external_effects"], "phase_boundary.default_external_effects")
  end

  def validate_v2!(root, truth, now: Time.now.utc)
    v2_assert(truth["record_type"] == "sourcelens_aios_current_truth", "SCHEMA", "unexpected Truth record_type")
    project = hash(truth["project"], "project")
    v2_assert(project["current_phase"] == "P1" && project["p0_status"] == "COMPLETE" &&
              project["p1_entry_status"] == "AUTHORIZED", "PHASE_BOUNDARY", "P1 phase boundary drifted")
    validate_phase_boundary_v2(truth)
    route, claims, inherited_claims, packet_identity = validate_v2_packet(root, truth)
    v2_assert(route["phase"] == "P1" && route["phase_entry_status"] == "AUTHORIZED" &&
              %w[AUTHORIZED_READY ACTIVE TERMINAL].include?(route["status"]),
              "ROUTE_IDENTITY", "v2 route lifecycle is not valid")
    validate_authority_documents(root, truth)
    open, bindings, = validate_v2_accounting(
      root, truth, route, claims, inherited_claims, packet_identity, now.utc
    )
    validate_v2_active_projection(truth, route, open, bindings, packet_identity)
    validate_v2_worktrees(root, truth, route, open, bindings, claims)
    open ? "ACTIVE_TASK_V2" : "ROUTE_NONE_V2"
  end

  def worktrees(root)
    records = []
    current = nil
    git(root, "worktree", "list", "--porcelain").first.each_line do |line|
      line = line.chomp
      if line.start_with?("worktree ")
        records << current if current
        current = { "path" => line.delete_prefix("worktree ") }
      elsif current && line.start_with?("HEAD ")
        current["head"] = line.delete_prefix("HEAD ")
      elsif current && line.start_with?("branch ")
        current["branch"] = line.delete_prefix("branch ").delete_prefix("refs/heads/")
      elsif current && line == "bare"
        current["bare"] = true
      end
    end
    records << current if current
    records
  end

  def validate_repository_and_worktrees(root, truth)
    project = hash(truth["project"], "project")
    canonical = string(project["canonical_repository"], "project.canonical_repository")
    assert(File.realpath(root) == File.realpath(canonical),
           "validator must run from the configured canonical repository, not a secondary worktree")
    branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD").first.strip
    assert(branch == project["canonical_branch"], "canonical repository is not on configured canonical branch")
    assert(git(root, "status", "--porcelain=v1", "--untracked-files=all").first.empty?,
           "canonical repository must be clean during authority validation")

    active = hash(truth["active_work"], "active_work")
    records = worktrees(root)
    expected_paths = [File.realpath(canonical)]
    if active["current_task"] != "NONE"
      expected_paths << File.realpath(string(active["task_worktree"], "active_work.task_worktree"))
    end
    actual_paths = records.map { |record| File.realpath(record["path"]) }.sort
    assert(actual_paths == expected_paths.sort, "Git worktree set does not equal canonical plus declared active Task")
    canonical_record = records.find { |record| File.realpath(record["path"]) == File.realpath(canonical) }
    assert(canonical_record && canonical_record["branch"] == project["canonical_branch"],
           "canonical worktree branch identity mismatch")
    return if active["current_task"] == "NONE"

    task_record = records.find { |record| File.realpath(record["path"]) == File.realpath(active["task_worktree"]) }
    assert(task_record && task_record["branch"] == active["task_branch"], "active Task worktree branch mismatch")
    _out, _err, lineage_status = git(root, "merge-base", "--is-ancestor",
                                      active["activation_parent_commit"], task_record["head"], allow_failure: true)
    assert(lineage_status.success?, "active Task worktree does not descend from its declared activation parent")
  end

  def validate!(root: nil, truth_path: nil, now: Time.now.utc)
    probe = truth_path ? File.dirname(File.expand_path(truth_path)) : Dir.pwd
    root ||= git(probe, "rev-parse", "--show-toplevel").first.strip
    root = File.realpath(root)
    truth_path ||= File.join(root, "docs/aios/truth/project_state.yaml")
    truth_path = File.expand_path(truth_path)
    truth = parse_yaml(secure_read(truth_path, "canonical Truth"), "canonical Truth")
    schema_version = truth.dig("current_phase_route", "authority_kernel", "schema_version")
    return validate_v2!(root, truth, now: now) if schema_version == "2.0"

    assert(truth["record_type"] == "sourcelens_aios_current_truth", "unexpected Truth record_type")
    validate_repository_and_worktrees(root, truth)
    validate_goal(truth)
    validate_authority_documents(root, truth)
    route, route_id, first_task, = validate_route(root, truth)
    first_task_in_history = historical_task_ids(truth).include?(first_task["task_id"])
    if %w[ELIGIBLE_NOT_ACTIVATED ACTIVE].include?(first_task["status"])
      assert(!first_task_in_history, "first Task id reuses historical Truth while eligible or active")
    end
    if hash(truth["active_work"], "active_work")["current_task"] == "NONE"
      validate_none_state(truth, route, first_task)
      "READY_NONE"
    else
      validate_legacy_v1_slot!(truth.dig("active_work", "current_task"), first_task["task_id"])
      validate_active_state(root, truth, route, route_id, first_task)
      "ACTIVE_TASK"
    end
  rescue AuthorityValidationError => e
    raise e unless schema_version.nil? || schema_version.to_s.start_with?("1")

    raise AuthorityValidationError.new(e.message, category: "LEGACY_V1")
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    truth_path = nil
    unless ARGV.empty?
      if ARGV.length == 2 && ARGV[0] == "--truth"
        truth_path = ARGV[1]
      else
        raise AuthorityValidationError.new("unsupported arguments", category: "CLI")
      end
    end
    state = CurrentTaskAuthority.validate!(truth_path: truth_path)
    puts "CURRENT_TASK_AUTHORITY: PASS category=PASS state=#{state}"
    exit 0
  rescue AuthorityValidationError => e
    warn "CURRENT_TASK_AUTHORITY: NON_PASS category=#{e.category} detail=#{e.message}"
    exit 1
  rescue StandardError => e
    warn "CURRENT_TASK_AUTHORITY: NON_PASS category=UNEXPECTED detail=#{e.class}: #{e.message}"
    exit 1
  end
end

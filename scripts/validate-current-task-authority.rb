#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

class AuthorityValidationError < StandardError; end
class DuplicateJsonKeyError < StandardError; end

module CurrentTaskAuthority
  module_function

  SHA256_RE = /\A[0-9a-f]{64}\z/.freeze
  COMMIT_RE = /\A[0-9a-f]{40}\z/.freeze
  SAFE_TASK_ID_RE = /\AAIOS-P[12]-[0-9]{3}(?:_[A-Z0-9_]+)?\z/.freeze
  ROUTE_ID_RE = /\AP[12]_[A-Z0-9_]+_ROUTE_V[1-9][0-9]*\z/.freeze
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

  class DuplicateRejectingHash < Hash
    def []=(key, value)
      raise DuplicateJsonKeyError, key if key?(key)

      super
    end
  end

  def fail!(message)
    raise AuthorityValidationError, message
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

  def parse_json(bytes, label)
    JSON.parse(bytes, object_class: DuplicateRejectingHash)
  rescue DuplicateJsonKeyError => e
    fail!("#{label} contains duplicate JSON key #{e.message.inspect}")
  rescue JSON::ParserError => e
    fail!("#{label} is invalid JSON: #{e.message}")
  end

  def parse_structured(bytes, path, label)
    if File.extname(path).downcase == ".json"
      value = parse_json(bytes, label)
      hash(value, label)
    else
      parse_yaml(bytes, label)
    end
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

  def sha256(bytes)
    Digest::SHA256.hexdigest(bytes)
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

  def validate_structured_predecessor_gate(root, truth, route, first_task, claims, next_task_id, state)
    return unless claims["structured_decision"]

    automatic_entry = claims["automatic_entry"]
    predecessor_id = automatic_entry["after_task_id"]
    expected_next_id = automatic_entry["next_task_id"]
    return if next_task_id == predecessor_id

    assert(next_task_id == expected_next_id,
           "structured automatic entry cannot activate an undeclared successor Task")
    assert(automatic_entry["requires_task_gate_pass"] == true,
           "structured automatic entry requires predecessor Task Gate PASS")
    assert(first_task["task_id"] == predecessor_id &&
           ACCEPTED_GATE_STATUS_RE.match?(first_task["status"].to_s),
           "structured automatic entry predecessor first_task is not Task Gate accepted")

    task_plan = array(route["task_plan"], "current_phase_route.task_plan")
    predecessor = task_plan.find { |item| item.is_a?(Hash) && item["task_id"] == predecessor_id }
    successor = task_plan.find { |item| item.is_a?(Hash) && item["task_id"] == expected_next_id }
    assert(predecessor && ACCEPTED_GATE_STATUS_RE.match?(predecessor["status"].to_s),
           "structured automatic entry predecessor task_plan is not Task Gate accepted")
    expected_successor_status = state == "ACTIVE" ? "ACTIVE" : "ELIGIBLE_NOT_ACTIVATED"
    assert(successor && successor["status"] == expected_successor_status,
           "structured automatic entry successor task_plan status mismatch")

    history = accepted_history_record(truth, predecessor_id, "structured automatic entry predecessor")
    assert(history["route_id"] == route["route_id"],
           "structured automatic entry predecessor history route mismatch")
    contract_path_value = history["contract"] || history["contract_path"]
    contract_path = repo_path(root, contract_path_value,
                              "structured automatic entry predecessor contract")
    contract_sha = string(history["task_contract_sha256"],
                          "structured automatic entry predecessor task_contract_sha256")
    validate_sha_only(contract_path, contract_sha,
                      "structured automatic entry predecessor contract")
    accepted_commit = string(history["accepted_candidate_commit"],
                             "structured automatic entry predecessor accepted_candidate_commit")
    accepted_tree = string(history["accepted_candidate_tree"],
                           "structured automatic entry predecessor accepted_candidate_tree")
    validate_commit_tree(root, accepted_commit, accepted_tree,
                         "structured automatic entry predecessor accepted candidate")
    _out, _err, ancestor_status = git(root, "merge-base", "--is-ancestor",
                                      accepted_commit, "HEAD", allow_failure: true)
    assert(ancestor_status.success?,
           "structured automatic entry predecessor accepted candidate is not canonical")
    %w[cto_target_verdict security_target_verdict quality_target_verdict].each do |key|
      assert(history[key] == "PASS",
             "structured automatic entry predecessor #{key} is not PASS")
    end
    assert(history["reviewed_tree_equals_integrated_tree"] == true,
           "structured automatic entry predecessor reviewed/integrated tree mismatch")
    assert(history["canonical_make_verify"] == "PASS",
           "structured automatic entry predecessor canonical make verify is not PASS")
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

  def founder_reserved_profiles_from_packet(text)
    matches = text.scan(
      /<!-- BEGIN (FOUNDER_[A-Z0-9_]*PROFILE_JSON) -->\s*```json\s*(.*?)\s*```\s*<!-- END \1 -->/m
    )
    assert(!matches.empty?, "decision packet must contain at least one Founder-reserved profile")
    markers = matches.map(&:first)
    assert(markers.uniq.length == markers.length,
           "decision packet Founder-reserved profile markers must be unique")
    matches.map do |marker, bytes|
      profile = JSON.parse(bytes)
      hash(profile, "Founder-reserved profile #{marker}")
    rescue JSON::ParserError => e
      fail!("Founder-reserved profile #{marker} is invalid JSON: #{e.message}")
    end
  end

  def validate_founder_reserved_profile_v1(value, route_id, task_id, label)
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

  def validate_founder_reserved_profile_v2(value, route_id, task_id, label)
    profile = exact_keys(
      value,
      %w[schema_version profile_id decision_basis route_id task_id transport model secret call_limits token_limits monetary_limits egress external_effects claim_limits],
      label
    )
    assert(profile["schema_version"] == "2.0", "#{label} schema version drifted")
    string(profile["profile_id"], "#{label}.profile_id")
    string(profile["decision_basis"], "#{label}.decision_basis")
    assert(profile["route_id"] == route_id, "#{label} route id mismatch")
    assert(profile["task_id"] == task_id, "#{label} Task id mismatch")

    transport = exact_keys(
      profile["transport"],
      %w[scheme host port base_path completion_path api_format method follow_redirects use_proxy dns_resolution fallback_endpoint_allowed expected_peer_address expected_peer_port],
      "#{label}.transport"
    )
    assert(transport == {
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
    }, "#{label}.transport exceeds the literal local-gateway boundary")

    model = exact_keys(profile["model"], %w[requested_model substitution_allowed provider_provenance],
                       "#{label}.model")
    assert(model["requested_model"] == "gpt-5.6-luna", "#{label}.model requested model drifted")
    exact_false(model["substitution_allowed"], "#{label}.model.substitution_allowed")
    assert(
      model["provider_provenance"] ==
        "FOUNDER_ATTESTED_OPENAI_COMPATIBLE_LOCAL_GATEWAY_MODEL_NOT_INDEPENDENTLY_VERIFIED",
      "#{label}.model provider provenance must remain Founder-attested and independently unverified"
    )

    secret = exact_keys(profile["secret"], %w[allowed_sources persist prohibited_sinks], "#{label}.secret")
    assert(array(secret["allowed_sources"], "#{label}.secret.allowed_sources") ==
           %w[LOCAL_PROCESS_ENV CONTROLLED_TEMPORARY_SECRET_FILE],
           "#{label}.secret allowed sources drifted")
    exact_false(secret["persist"], "#{label}.secret.persist")
    assert(array(secret["prohibited_sinks"], "#{label}.secret.prohibited_sinks") ==
           %w[REPOSITORY EVIDENCE LOG TRACE PROMPT REVIEW VAULT],
           "#{label}.secret prohibited sinks drifted")

    calls = exact_keys(profile["call_limits"], %w[provider_requests_max automatic_retry_max],
                       "#{label}.call_limits")
    provider_requests_max = integer(calls["provider_requests_max"],
                                    "#{label}.call_limits.provider_requests_max")
    assert(provider_requests_max.between?(1, 144),
           "#{label}.call limits drifted: provider_requests_max must be in 1..144")
    assert(calls["automatic_retry_max"] == 0,
           "#{label}.call limits drifted: automatic_retry_max must equal 0")

    tokens = exact_keys(profile["token_limits"], %w[input_tokens_max output_tokens_max],
                        "#{label}.token_limits")
    input_tokens_max = integer(tokens["input_tokens_max"], "#{label}.token_limits.input_tokens_max")
    output_tokens_max = integer(tokens["output_tokens_max"], "#{label}.token_limits.output_tokens_max")
    assert(input_tokens_max.between?(1, 3_000_000),
           "#{label}.token limits drifted: input_tokens_max must be in 1..3000000")
    assert(output_tokens_max.between?(1, 300_000),
           "#{label}.token limits drifted: output_tokens_max must be in 1..300000")

    monetary = exact_keys(
      profile["monetary_limits"],
      %w[currency max_spend unavailable_metering_status],
      "#{label}.monetary_limits"
    )
    assert(monetary["currency"] == "USD",
           "#{label}.monetary limits drifted: currency must equal USD")
    max_spend = monetary["max_spend"]
    finite_spend = max_spend.is_a?(Numeric) && (!max_spend.respond_to?(:finite?) || max_spend.finite?)
    assert(finite_spend && max_spend.between?(0, 25),
           "#{label}.monetary limits drifted: max_spend must be numeric in 0..25")
    assert(monetary["unavailable_metering_status"] == "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
           "#{label}.monetary limits drifted: unavailable metering status changed")

    egress = exact_keys(profile["egress"], %w[restricted_source_allowed], "#{label}.egress")
    exact_false(egress["restricted_source_allowed"], "#{label}.egress.restricted_source_allowed")

    validate_external_effects(profile["external_effects"], "#{label}.external_effects",
                              LOCAL_GATEWAY_EXTERNAL_EFFECTS)
    claims = exact_keys(
      profile["claim_limits"],
      %w[direct_openai_provenance_proven adapter_conformance_is_model_performance remote production public],
      "#{label}.claim_limits"
    )
    exact_false(claims["direct_openai_provenance_proven"],
                "#{label}.claim_limits.direct_openai_provenance_proven")
    exact_false(claims["adapter_conformance_is_model_performance"],
                "#{label}.claim_limits.adapter_conformance_is_model_performance")
    %w[remote production public].each do |key|
      exact_false(claims[key], "#{label}.claim_limits.#{key}")
    end
    profile
  end

  def validate_founder_reserved_profile_v3(value, route_id, task_id, label)
    profile = exact_keys(
      value,
      %w[schema_version profile_id decision_basis route_id task_id transport model secret call_limits token_limits monetary_limits egress effect_partition external_effects claim_limits],
      label
    )
    assert(profile["schema_version"] == "3.0", "#{label} schema version drifted")
    string(profile["profile_id"], "#{label}.profile_id")
    assert(profile["decision_basis"].is_a?(String) &&
           profile["decision_basis"].match?(/\AFOUNDER_PACKET_SHA256:[0-9a-f]{64}\z/),
           "#{label}.decision_basis must bind the exact Founder packet")
    assert(profile["route_id"] == route_id, "#{label} route id mismatch")
    assert(profile["task_id"] == task_id, "#{label} Task id mismatch")

    transport = exact_keys(
      profile["transport"],
      %w[scheme host port completion_path api_format method follow_redirects use_proxy dns_resolution fallback_endpoint_allowed expected_peer_address expected_peer_port],
      "#{label}.transport"
    )
    assert(transport == {
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
    }, "#{label}.transport exceeds the literal operator-owned loopback boundary")

    model = exact_keys(profile["model"], %w[requested_model substitution_allowed provider_provenance],
                       "#{label}.model")
    assert(model == {
      "requested_model" => "gpt-5.6-luna",
      "substitution_allowed" => false,
      "provider_provenance" =>
        "FOUNDER_ATTESTED_OPENAI_COMPATIBLE_LOCAL_GATEWAY_MODEL_NOT_INDEPENDENTLY_VERIFIED"
    }, "#{label}.model boundary drifted")

    secret = exact_keys(profile["secret"], %w[source entry_sessions persist prohibited_sinks],
                        "#{label}.secret")
    assert(secret["source"] == "FOUNDER_OPERATOR_NO_ECHO_TTY",
           "#{label}.secret source must remain the Founder/operator no-echo TTY")
    assert(secret["entry_sessions"] == 1, "#{label}.secret entry sessions must equal 1")
    exact_false(secret["persist"], "#{label}.secret.persist")
    assert(array(secret["prohibited_sinks"], "#{label}.secret.prohibited_sinks") ==
           %w[ARGV ENVIRONMENT SHELL_HISTORY REPOSITORY TEMPORARY_PLAINTEXT_FILE EVIDENCE LOG TRACE PROMPT REVIEW VAULT],
           "#{label}.secret prohibited sinks drifted")

    calls = exact_keys(
      profile["call_limits"],
      %w[diagnostic_requests_max formal_requests_exact provider_requests_max automatic_retry_max],
      "#{label}.call_limits"
    )
    assert(calls == {
      "diagnostic_requests_max" => 3,
      "formal_requests_exact" => 36,
      "provider_requests_max" => 39,
      "automatic_retry_max" => 0
    }, "#{label}.call limits drifted")

    tokens = exact_keys(profile["token_limits"], %w[input_tokens_max output_tokens_max],
                        "#{label}.token_limits")
    assert(tokens == {
      "input_tokens_max" => 500_000,
      "output_tokens_max" => 100_000
    }, "#{label}.token limits drifted")

    money = exact_keys(profile["monetary_limits"],
                       %w[currency max_spend unavailable_metering_status],
                       "#{label}.monetary_limits")
    assert(money == {
      "currency" => "USD",
      "max_spend" => 25,
      "unavailable_metering_status" => "UNKNOWN_GATEWAY_METERING_UNAVAILABLE"
    }, "#{label}.monetary limits drifted")

    egress = exact_keys(
      profile["egress"],
      %w[restricted_source_allowed allowed_artifacts derived_context_policy forbidden_categories],
      "#{label}.egress"
    )
    assert(egress["restricted_source_allowed"] == true,
           "#{label}.egress must retain the exact restricted synthetic disclosure decision")
    artifacts = array(egress["allowed_artifacts"], "#{label}.egress.allowed_artifacts")
    assert(artifacts.length == 16, "#{label}.egress must bind exactly 16 disclosed artifacts")
    artifact_paths = artifacts.map.with_index do |artifact_value, index|
      artifact = exact_keys(artifact_value, %w[class byte_length sha256 path],
                            "#{label}.egress.allowed_artifacts[#{index}]")
      string(artifact["class"], "#{label}.egress.allowed_artifacts[#{index}].class")
      bytes = integer(artifact["byte_length"], "#{label}.egress.allowed_artifacts[#{index}].byte_length")
      assert(bytes.positive?, "#{label}.egress artifact byte length must be positive")
      digest = string(artifact["sha256"], "#{label}.egress.allowed_artifacts[#{index}].sha256")
      assert(SHA256_RE.match?(digest), "#{label}.egress artifact SHA-256 is invalid")
      path = string(artifact["path"], "#{label}.egress.allowed_artifacts[#{index}].path")
      assert(path.start_with?("evaluation-harness/datasets/p1-representative-task-dataset-v1/"),
             "#{label}.egress artifact escapes the accepted synthetic dataset")
      assert(!path.include?("/test/") &&
             !path.end_with?("/expected-base-failure.json") &&
             !path.end_with?("/reference-solution.patch"),
             "#{label}.egress artifact includes a forbidden test, oracle or reference patch")
      path
    end
    assert(artifact_paths.uniq.length == artifact_paths.length,
           "#{label}.egress artifact paths must be unique")
    assert(egress["derived_context_policy"] ==
           "ONLY_SELECT_AND_FRAME_EXACT_ALLOWLISTED_BYTES_WITH_TASK_RELATIVE_PATH_AND_HASH",
           "#{label}.egress derived-context policy drifted")
    assert(array(egress["forbidden_categories"], "#{label}.egress.forbidden_categories") ==
           %w[TEST_BYTES TEST_OUTPUT_OR_ORACLE EXPECTED_FAILURE_ORACLE REFERENCE_SOLUTION_PATCH VALIDATOR_OR_EVALUATOR HIDDEN_OR_POST_RESULT GOVERNANCE_TRUTH_CONTRACT_REVIEW_EVIDENCE OTHER_REPOSITORY_OR_USER_FILE SECRET_CREDENTIAL_TOKEN_AUTHORIZATION_HEADER],
           "#{label}.egress forbidden categories drifted")

    partition = exact_keys(profile["effect_partition"], %w[canonical_aios operator_launcher],
                           "#{label}.effect_partition")
    validate_external_effects(partition["canonical_aios"], "#{label}.effect_partition.canonical_aios",
                              FALSE_EXTERNAL_EFFECTS)
    validate_external_effects(partition["operator_launcher"], "#{label}.effect_partition.operator_launcher",
                              LOCAL_GATEWAY_EXTERNAL_EFFECTS)
    # Schema v3 deliberately separates the canonical AIOS authority boundary
    # from the Founder/operator-owned launcher. The active Task, Contract and
    # phase-delegated authority remain offline; the exact Founder packet is
    # the only authority for the launcher's bounded effects.
    validate_external_effects(profile["external_effects"], "#{label}.external_effects",
                              FALSE_EXTERNAL_EFFECTS)

    claims = exact_keys(
      profile["claim_limits"],
      %w[direct_openai_provenance_proven gateway_upstream_behavior upstream_request_count actual_monetary_cost byte_identical_stochastic_resampling hostile_principal_isolation production remote public p2_entry],
      "#{label}.claim_limits"
    )
    assert(claims == {
      "direct_openai_provenance_proven" => false,
      "gateway_upstream_behavior" => "UNKNOWN",
      "upstream_request_count" => "UNKNOWN",
      "actual_monetary_cost" => "UNKNOWN_UNLESS_TRUSTWORTHY_GATEWAY_EVIDENCE_EXISTS",
      "byte_identical_stochastic_resampling" => false,
      "hostile_principal_isolation" => false,
      "production" => false,
      "remote" => false,
      "public" => false,
      "p2_entry" => false
    }, "#{label}.claim limits drifted")
    profile
  end

  def validate_founder_reserved_profile(value, route_id, task_id, label)
    profile = hash(value, label)
    case profile["schema_version"]
    when "1.0"
      validate_founder_reserved_profile_v1(profile, route_id, task_id, label)
    when "2.0"
      validate_founder_reserved_profile_v2(profile, route_id, task_id, label)
    when "3.0"
      validate_founder_reserved_profile_v3(profile, route_id, task_id, label)
    else
      fail!("#{label} schema version is unsupported")
    end
  end

  def validate_exact_profile_binding(actual, expected, message)
    assert(actual == expected, message)
    actual
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

  def phase_gate_route_packet_claims(text)
    record_type = one_packet_match(
      text,
      /- record_type: `(founder_p1_phase_gate_route_decision_packet)`/,
      "P1 Phase Gate route record type"
    )
    assert(record_type == "founder_p1_phase_gate_route_decision_packet",
           "unsupported P1 Phase Gate route record type")
    route_id = one_packet_match(text, /路线 ID：`(P1_[A-Z0-9_]+_ROUTE_V1)`/,
                                "Route ID declaration")
    authorization_token = one_packet_match(
      text,
      /`authorization_token=([A-Z0-9_]+)`/,
      "Founder authorization token declaration"
    )
    first_task_section = one_packet_match(text, /## 3\. Task 1[^\n]*\n(.*?)\n## 4\. Task 2/m,
                                          "first Task section")
    first_task_id = one_packet_match(
      first_task_section,
      /Task ID：`(AIOS-P1-[0-9]{3}_[A-Z0-9_]+)`/,
      "first Task ID declaration"
    )
    task_ids = text.scan(/Task ID：`(AIOS-P1-[0-9]{3}_[A-Z0-9_]+)`/).flatten
    assert(task_ids.uniq.length == task_ids.length,
           "decision packet Task IDs must be unique")
    route_budget = one_packet_match(
      text,
      /- maximum engineering Tasks: `(\d+)`\s+- maximum engineering hours: `(\d+)`\s+- maximum calendar days: `(\d+)`/m,
      "Phase envelope declaration"
    )
    first_task_budget = one_packet_match(
      text,
      /- Task 1: `(\d+) hours \/ (\d+) days`/,
      "first Task budget declaration"
    )
    implementation_iterations = one_packet_match(
      text,
      /- per Task pre-freeze implementation\/test iterations: `(\d+)`/,
      "per-Task implementation iteration declaration"
    )
    candidates = one_packet_match(text, /- per Task exact candidates: `(\d+)`/,
                                  "per-Task candidate declaration")
    parent_commit = one_packet_match(text, /- canonical commit: `([0-9a-f]{40})`/,
                                     "activation parent commit")
    parent_tree = one_packet_match(text, /- canonical tree: `([0-9a-f]{40})`/,
                                   "activation parent tree")
    founder_reserved_profiles = if text.include?("PROFILE_JSON")
                                  founder_reserved_profiles_from_packet(text)
                                else
                                  []
                                end
    founder_reserved_profile = founder_reserved_profiles.first
    if founder_reserved_profile
      assert(task_ids.length == Integer(route_budget[0], 10),
             "decision packet Task declarations must equal the Phase Task envelope")
      assert(founder_reserved_profiles.length == task_ids.length,
             "decision packet Founder profile set must equal the declared Task set")
      founder_reserved_profiles.each_with_index do |profile, index|
        validate_founder_reserved_profile(
          profile,
          route_id,
          task_ids[index],
          "decision packet Founder-reserved profile #{index + 1}"
        )
      end
      profile_task_ids = founder_reserved_profiles.map { |profile| profile["task_id"] }
      assert(profile_task_ids == task_ids,
             "decision packet Founder profile Task order must equal the declared Task order")
    else
      assert(text.include?("network、Provider、Secret、remote、production、public effects"),
             "offline Phase Gate packet must explicitly prohibit all six external effects")
    end
    iteration_count = Integer(implementation_iterations, 10)
    assert(iteration_count.positive?, "first Task implementation iterations must be positive")
    {
      "route_id" => route_id,
      "first_task_id" => first_task_id,
      "authorization_token" => authorization_token,
      "max_engineering_tasks" => Integer(route_budget[0], 10),
      "max_engineering_hours" => Integer(route_budget[1], 10),
      "max_calendar_days" => Integer(route_budget[2], 10),
      "first_task_engineering_hours" => Integer(first_task_budget[0], 10),
      "first_task_calendar_days" => Integer(first_task_budget[1], 10),
      "first_task_implementation_iterations" => iteration_count,
      "first_task_candidates" => Integer(candidates, 10),
      "max_contract_corrections_per_task" => nil,
      "max_same_task_repairs" => iteration_count - 1,
      "activation_parent_commit" => parent_commit,
      "activation_parent_tree" => parent_tree,
      "task_ids" => task_ids,
      "founder_reserved_profile" => founder_reserved_profile,
      "founder_reserved_profiles" => founder_reserved_profiles,
      "external_effects" => founder_reserved_profile ?
        founder_reserved_profile["external_effects"] : FALSE_EXTERNAL_EFFECTS,
      "text" => text
    }
  rescue ArgumentError
    fail!("decision packet contains a non-integer Phase envelope")
  end

  def operator_capture_route_packet_claims(text)
    route_id = one_packet_match(
      text,
      /I authorize one new P1 Phase route:\s+`(P1_[A-Z0-9_]+_ROUTE_V1)`/m,
      "operator-capture Route ID declaration"
    )
    first_task_id = one_packet_match(
      text,
      /and one engineering Task:\s+`(AIOS-P1-[0-9]{3}_[A-Z0-9_]+)`/m,
      "operator-capture Task ID declaration"
    )
    authorization_token = one_packet_match(
      text,
      /`(AUTHORIZE_P1_OPERATOR_OWNED_CREDENTIAL_CAPTURE_AND_OFFLINE_EXIT_GATE_ROUTE_V1)`/,
      "operator-capture Founder authorization token"
    )
    envelope = {
      "max_engineering_tasks" => Integer(one_packet_match(
        text, /- maximum engineering Tasks: `(\d+)`/, "maximum engineering Tasks"
      ), 10),
      "max_engineering_hours" => Integer(one_packet_match(
        text, /- maximum engineering hours: `(\d+)`/, "maximum engineering hours"
      ), 10),
      "max_calendar_days" => Integer(one_packet_match(
        text, /- maximum calendar days: `(\d+)`/, "maximum calendar days"
      ), 10)
    }
    parent_commit = one_packet_match(text, /- canonical commit:\s+`([0-9a-f]{40})`/,
                                     "operator-capture activation parent commit")
    parent_tree = one_packet_match(text, /- canonical tree:\s+`([0-9a-f]{40})`/,
                                   "operator-capture activation parent tree")
    assert(text.include?("initial implementation plus at most one\n  same-Task code-only repair"),
           "operator-capture implementation iteration declaration drifted")
    assert(text.include?("- maximum active candidates: `1`"),
           "operator-capture candidate declaration drifted")

    artifact_rows = text.scan(
      /^\| ([^|]+?) \| (\d+) \| `([0-9a-f]{64})` \| `([^`]+)` \|$/
    ).map do |klass, length, digest, path|
      {
        "class" => klass.strip,
        "byte_length" => Integer(length, 10),
        "sha256" => digest,
        "path" => path
      }
    end
    assert(artifact_rows.length == 16,
           "operator-capture packet must contain exactly 16 disclosed artifact identities")

    profile = {
      "schema_version" => "3.0",
      "profile_id" => "P1_123_OPERATOR_OWNED_CAPTURE_AND_OFFLINE_EXIT_V1",
      "decision_basis" => "FOUNDER_PACKET_SHA256:#{sha256(text.b)}",
      "route_id" => route_id,
      "task_id" => first_task_id,
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
        "diagnostic_requests_max" => 3,
        "formal_requests_exact" => 36,
        "provider_requests_max" => 39,
        "automatic_retry_max" => 0
      },
      "token_limits" => {
        "input_tokens_max" => 500_000,
        "output_tokens_max" => 100_000
      },
      "monetary_limits" => {
        "currency" => "USD",
        "max_spend" => 25,
        "unavailable_metering_status" => "UNKNOWN_GATEWAY_METERING_UNAVAILABLE"
      },
      "egress" => {
        "restricted_source_allowed" => true,
        "allowed_artifacts" => artifact_rows,
        "derived_context_policy" =>
          "ONLY_SELECT_AND_FRAME_EXACT_ALLOWLISTED_BYTES_WITH_TASK_RELATIVE_PATH_AND_HASH",
        "forbidden_categories" => %w[
          TEST_BYTES TEST_OUTPUT_OR_ORACLE EXPECTED_FAILURE_ORACLE
          REFERENCE_SOLUTION_PATCH VALIDATOR_OR_EVALUATOR HIDDEN_OR_POST_RESULT
          GOVERNANCE_TRUTH_CONTRACT_REVIEW_EVIDENCE OTHER_REPOSITORY_OR_USER_FILE
          SECRET_CREDENTIAL_TOKEN_AUTHORIZATION_HEADER
        ]
      },
      "effect_partition" => {
        "canonical_aios" => FALSE_EXTERNAL_EFFECTS.dup,
        "operator_launcher" => LOCAL_GATEWAY_EXTERNAL_EFFECTS.dup
      },
      "external_effects" => FALSE_EXTERNAL_EFFECTS.dup,
      "claim_limits" => {
        "direct_openai_provenance_proven" => false,
        "gateway_upstream_behavior" => "UNKNOWN",
        "upstream_request_count" => "UNKNOWN",
        "actual_monetary_cost" => "UNKNOWN_UNLESS_TRUSTWORTHY_GATEWAY_EVIDENCE_EXISTS",
        "byte_identical_stochastic_resampling" => false,
        "hostile_principal_isolation" => false,
        "production" => false,
        "remote" => false,
        "public" => false,
        "p2_entry" => false
      }
    }
    validate_founder_reserved_profile_v3(profile, route_id, first_task_id,
                                         "operator-capture decision packet profile")
    {
      "route_id" => route_id,
      "first_task_id" => first_task_id,
      "authorization_token" => authorization_token,
      "max_engineering_tasks" => envelope["max_engineering_tasks"],
      "max_engineering_hours" => envelope["max_engineering_hours"],
      "max_calendar_days" => envelope["max_calendar_days"],
      "first_task_engineering_hours" => envelope["max_engineering_hours"],
      "first_task_calendar_days" => envelope["max_calendar_days"],
      "first_task_implementation_iterations" => 2,
      "first_task_candidates" => 1,
      "max_contract_corrections_per_task" => nil,
      "max_same_task_repairs" => 1,
      "activation_parent_commit" => parent_commit,
      "activation_parent_tree" => parent_tree,
      "task_ids" => [first_task_id],
      "founder_reserved_profile" => profile,
      "founder_reserved_profiles" => [profile],
      "external_effects" => profile["external_effects"],
      "text" => text
    }
  rescue ArgumentError
    fail!("operator-capture decision packet contains a non-integer envelope")
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

  def founder_phase_route_decision_claims(bytes, decision_path: nil, root: nil)
    if decision_path
      assert(File.extname(decision_path).downcase == ".json",
             "structured Founder route decision path must use the .json extension")
    end
    decision = hash(parse_json(bytes, "structured Founder route decision"),
                    "structured Founder route decision")
    assert(canonical_json(decision).b == bytes.b,
           "structured Founder route decision must be recursively key-sorted canonical JSON with one trailing LF")
    exact_keys(
      decision,
      %w[
        activation_parent authorization_token automatic_entry claim_boundary envelope
        external_effects goal_identity ordered_tasks phase record_type route_id
        schema_version source_founder_packet_identity
      ],
      "structured Founder route decision"
    )
    assert(decision["schema_version"] == "1.0",
           "structured Founder route decision schema_version must equal 1.0")
    assert(decision["record_type"] == "founder_phase_route_decision",
           "structured Founder route decision record_type is unsupported")

    phase = string(decision["phase"], "structured Founder route decision.phase")
    assert(%w[P1 P2].include?(phase), "structured Founder route decision phase must be P1 or P2")
    route_id = string(decision["route_id"], "structured Founder route decision.route_id")
    assert(ROUTE_ID_RE.match?(route_id), "structured Founder route decision route_id has invalid form")
    assert(route_id.start_with?("#{phase}_"),
           "structured Founder route decision route_id phase prefix mismatch")
    authorization_token = string(
      decision["authorization_token"],
      "structured Founder route decision.authorization_token"
    )
    assert(authorization_token == "AUTHORIZE_#{route_id}",
           "structured Founder route decision authorization token does not match route_id")

    parent = exact_keys(
      decision["activation_parent"],
      %w[commit tree],
      "structured Founder route decision.activation_parent"
    )
    assert(COMMIT_RE.match?(string(parent["commit"], "structured decision activation parent commit")),
           "structured decision activation parent commit must be a full commit id")
    assert(COMMIT_RE.match?(string(parent["tree"], "structured decision activation parent tree")),
           "structured decision activation parent tree must be a full tree id")
    validate_commit_tree(root, parent["commit"], parent["tree"],
                         "structured decision activation parent") if root

    source_packet = exact_keys(
      decision["source_founder_packet_identity"],
      %w[authorization_token byte_length path sha256],
      "structured Founder route decision.source_founder_packet_identity"
    )
    assert(source_packet["authorization_token"] == authorization_token,
           "structured Founder source packet authorization token mismatch")
    source_path = string(source_packet["path"], "structured Founder source packet path")
    assert(Pathname.new(source_path).absolute?,
           "structured Founder source packet path must be absolute")
    assert(integer(source_packet["byte_length"],
                   "structured Founder source packet byte_length").positive?,
           "structured Founder source packet byte_length must be positive")
    validate_identity(source_path, source_packet, "Founder source packet")

    goal_identity = exact_keys(
      decision["goal_identity"],
      %w[canonical_byte_length canonical_sha256 canonicalization raw_byte_length raw_sha256],
      "structured Founder route decision.goal_identity"
    )
    expected_goal_identity = {
      "canonical_byte_length" => GOAL_CANONICAL_BYTE_LENGTH,
      "canonical_sha256" => GOAL_CANONICAL_SHA256,
      "canonicalization" => "UTF8_LF_WITH_EXACTLY_ONE_TRAILING_LF",
      "raw_byte_length" => GOAL_RAW_BYTE_LENGTH,
      "raw_sha256" => GOAL_RAW_SHA256
    }
    assert(goal_identity == expected_goal_identity,
           "structured Founder route decision Goal identity mismatch")

    envelope = exact_keys(
      decision["envelope"],
      %w[
        max_active_candidates max_active_tasks max_calendar_days max_engineering_hours
        max_engineering_tasks max_same_task_repairs_per_task max_task_branches
        max_task_worktrees p3_entry_authorized
      ],
      "structured Founder route decision.envelope"
    )
    %w[
      max_active_candidates max_active_tasks max_calendar_days max_engineering_hours
      max_engineering_tasks max_task_branches max_task_worktrees
    ].each do |key|
      assert(integer(envelope[key], "structured decision envelope.#{key}").positive?,
             "structured decision envelope.#{key} must be positive")
    end
    max_repairs = integer(
      envelope["max_same_task_repairs_per_task"],
      "structured decision envelope.max_same_task_repairs_per_task"
    )
    assert(max_repairs >= 0,
           "structured decision envelope.max_same_task_repairs_per_task must be non-negative")
    %w[max_active_candidates max_active_tasks max_task_branches max_task_worktrees].each do |key|
      assert(envelope[key] == 1, "structured decision envelope.#{key} must equal 1")
    end
    exact_false(envelope["p3_entry_authorized"],
                "structured decision envelope.p3_entry_authorized")

    external_effects = exact_keys(
      decision["external_effects"],
      EXTERNAL_EFFECT_KEYS,
      "structured Founder route decision.external_effects"
    )
    external_effects.each do |key, value|
      assert(value == true || value == false,
             "structured Founder route decision.external_effects.#{key} must be boolean")
    end
    claim_boundary = string(
      decision["claim_boundary"],
      "structured Founder route decision.claim_boundary"
    )

    task_values = array(decision["ordered_tasks"],
                        "structured Founder route decision.ordered_tasks")
    assert(task_values.length >= 2,
           "structured Founder route decision requires at least two ordered Tasks for automatic entry")
    assert(task_values.length == envelope["max_engineering_tasks"],
           "structured Founder route decision Task count does not equal route envelope")
    task_budgets = task_values.map.with_index do |value, index|
      task = exact_keys(
        value,
        %w[
          calendar_days engineering_hours max_candidates max_implementation_iterations
          max_same_task_repairs task_id task_slot
        ],
        "structured Founder route decision.ordered_tasks[#{index}]"
      )
      assert(integer(task["task_slot"], "structured decision Task slot") == index + 1,
             "structured Founder route decision Task slots must be contiguous and ordered")
      task_id = string(task["task_id"], "structured decision Task id")
      assert(SAFE_TASK_ID_RE.match?(task_id), "structured decision Task id has invalid form")
      assert(task_id.start_with?("AIOS-#{phase}-"),
             "structured Founder route decision Task phase prefix mismatch")
      %w[calendar_days engineering_hours max_candidates max_implementation_iterations].each do |key|
        assert(integer(task[key], "structured decision Task #{key}").positive?,
               "structured decision Task #{key} must be positive")
      end
      task_repairs = integer(task["max_same_task_repairs"],
                             "structured decision Task max_same_task_repairs")
      assert(task_repairs >= 0, "structured decision Task max_same_task_repairs must be non-negative")
      assert(task_repairs == max_repairs,
             "structured decision Task repair budget does not equal route envelope")
      assert(task["max_implementation_iterations"] == task_repairs + 1,
             "structured decision Task implementation iterations must equal initial plus repairs")
      assert(task["max_candidates"] == envelope["max_active_candidates"],
             "structured decision Task candidate budget does not equal route envelope")
      task
    end
    task_ids = task_budgets.map { |task| task["task_id"] }
    assert(task_ids.uniq.length == task_ids.length,
           "structured Founder route decision Task ids must be unique")
    assert(task_budgets.sum { |task| task["engineering_hours"] } == envelope["max_engineering_hours"],
           "structured Founder route decision Task engineering budgets do not equal route envelope")
    assert(task_budgets.sum { |task| task["calendar_days"] } == envelope["max_calendar_days"],
           "structured Founder route decision Task calendar budgets do not equal route envelope")

    automatic_entry = exact_keys(
      decision["automatic_entry"],
      %w[after_task_id next_task_id requires_task_gate_pass],
      "structured Founder route decision.automatic_entry"
    )
    assert(automatic_entry["after_task_id"] == task_ids[0] &&
           automatic_entry["next_task_id"] == task_ids[1],
           "structured Founder route decision automatic entry must bind ordered Task 1 to Task 2")
    assert(automatic_entry["requires_task_gate_pass"] == true,
           "structured Founder route decision automatic entry requires Task Gate PASS")

    {
      "structured_decision" => true,
      "authorization_token" => authorization_token,
      "route_id" => route_id,
      "phase" => phase,
      "activation_parent_commit" => parent["commit"],
      "activation_parent_tree" => parent["tree"],
      "max_engineering_tasks" => envelope["max_engineering_tasks"],
      "max_engineering_hours" => envelope["max_engineering_hours"],
      "max_calendar_days" => envelope["max_calendar_days"],
      "max_same_task_repairs" => max_repairs,
      "max_contract_corrections_per_task" => 0,
      "first_task_id" => task_ids.first,
      "first_task_engineering_hours" => task_budgets.first["engineering_hours"],
      "first_task_calendar_days" => task_budgets.first["calendar_days"],
      "first_task_implementation_iterations" => task_budgets.first["max_implementation_iterations"],
      "first_task_candidates" => task_budgets.first["max_candidates"],
      "task_ids" => task_ids,
      "task_budgets" => task_budgets,
      "automatic_entry" => automatic_entry,
      "claim_boundary" => claim_boundary,
      "source_founder_packet_identity" => source_packet,
      "goal_identity" => goal_identity,
      "founder_reserved_profile" => nil,
      "founder_reserved_profiles" => [],
      "external_effects" => external_effects
    }
  end

  def packet_claims(packet_bytes, packet_path = nil, root: nil)
    stripped = packet_bytes.dup.force_encoding(Encoding::BINARY).sub(/\A[[:space:]]+/, "")
    if File.extname(packet_path.to_s).downcase == ".json" ||
       stripped.start_with?("{".b) || stripped.start_with?("[".b)
      return founder_phase_route_decision_claims(
        packet_bytes,
        decision_path: packet_path,
        root: root
      )
    end

    text = packet_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(text.valid_encoding?, "decision packet must be valid UTF-8")
    if text.include?("AUTHORIZE_P2_ACCEPTED_REPOSITORY_GRAPH_INDEX_AND_GRAPH_CONDITIONED_CONTEXT_ROUTE_V1") ||
       text.include?("AUTHORIZE_P2_SCANNER_FIRST_EXACT_GRAPH_AUTHORITY_AND_GRAPH_CONDITIONED_CONTEXT_ROUTE_V1")
      p2_graph_route_packet_claims(text)
    elsif text.include?("AUTHORIZE_P1_PARTIAL_EXIT_WITH_DISCLOSED_RESIDUALS_AND_DIRECT_P2_REPOSITORY_INTELLIGENCE_PHASE_ENTRY_V1")
      p2_repository_intelligence_route_packet_claims(text)
    elsif text.include?("AUTHORIZE_P1_OPERATOR_OWNED_CREDENTIAL_CAPTURE_AND_OFFLINE_EXIT_GATE_ROUTE_V1")
      operator_capture_route_packet_claims(text)
    elsif text.include?("founder_p1_phase_gate_route_decision_packet")
      phase_gate_route_packet_claims(text)
    elsif text.include?("FOUNDER_PROJECT_LEVEL_ARCHITECTURE_ROUTE_AND_PHASE_REENTRY_DECISION_PACKET")
      project_route_packet_claims(text)
    else
      legacy_route_packet_claims(text)
    end
  end

  def p2_graph_route_packet_claims(text)
    supported_tokens = [
      "AUTHORIZE_P2_ACCEPTED_REPOSITORY_GRAPH_INDEX_AND_GRAPH_CONDITIONED_CONTEXT_ROUTE_V1",
      "AUTHORIZE_P2_SCANNER_FIRST_EXACT_GRAPH_AUTHORITY_AND_GRAPH_CONDITIONED_CONTEXT_ROUTE_V1"
    ].freeze
    present_tokens = supported_tokens.select { |candidate| text.scan(candidate).length == 1 }
    assert(present_tokens.length == 1 &&
           supported_tokens.sum { |candidate| text.scan(candidate).length } == 1,
           "P2 graph decision packet must contain the exact authorization token once")
    token = present_tokens.first
    route_id = one_packet_match(
      text,
      /Start one new P2 architecture route:\s+`(P2_[A-Z0-9_]+_ROUTE_V[0-9]+)`/,
      "P2 graph route id"
    )
    parent_commit = one_packet_match(
      text,
      /- canonical commit: `([0-9a-f]{40})`/,
      "P2 graph activation parent commit"
    )
    parent_tree = one_packet_match(
      text,
      /- canonical tree: `([0-9a-f]{40})`/,
      "P2 graph activation parent tree"
    )
    max_engineering_tasks = Integer(one_packet_match(
      text, /- maximum engineering Tasks: `([0-9]+)`/, "P2 graph Task envelope"
    ), 10)
    max_engineering_hours = Integer(one_packet_match(
      text, /- maximum engineering hours: `([0-9]+)`/, "P2 graph hour envelope"
    ), 10)
    max_calendar_days = Integer(one_packet_match(
      text, /- maximum calendar days: `([0-9]+)`/, "P2 graph calendar envelope"
    ), 10)
    task_sections = text.scan(
      /^## [0-9]+\. Task [0-9]+\b[^\n]*\n(.*?)(?=^## |\z)/m
    ).flatten
    task_budgets = task_sections.map do |section|
      budget = one_packet_match(
        section,
        /Budget:\s+`([0-9]+) engineering hours \/ ([0-9]+) calendar days`/,
        "P2 graph Task budget"
      )
      {
        "task_id" => one_packet_match(
          section,
          /Task ID:\s+`(AIOS-P2-[0-9]{3}_[A-Z0-9_]+)`/,
          "P2 graph Task id"
        ),
        "engineering_hours" => Integer(budget[0], 10),
        "calendar_days" => Integer(budget[1], 10)
      }
    end
    task_ids = task_budgets.map { |budget| budget["task_id"] }
    assert(task_ids.length == max_engineering_tasks && task_ids.uniq.length == task_ids.length,
           "P2 graph decision packet Task set is not closed")
    assert(task_budgets.sum { |budget| budget["engineering_hours"] } == max_engineering_hours,
           "P2 graph Task hours do not equal the route envelope")
    assert(task_budgets.sum { |budget| budget["calendar_days"] } == max_calendar_days,
           "P2 graph Task days do not equal the route envelope")
    assert(text.include?("each Task: initial implementation plus at most one same-Task code-only repair"),
           "P2 graph implementation iteration boundary drifted")
    assert(text.include?("one exact candidate and one fresh final review cycle per Task"),
           "P2 graph candidate boundary drifted")
    assert(text.include?("network, Provider, Secret, remote, production and public effects: all `false`"),
           "P2 graph external-effect boundary drifted")
    primary_metric_min_delta = Float(one_packet_match(
      text,
      /target recall@10 exceeds the frozen lexical baseline by at least `([0-9]+(?:\.[0-9]+)?)`\s+absolute/,
      "P2 graph primary metric"
    ))
    {
      "text" => text,
      "authorization_token" => token,
      "route_id" => route_id,
      "activation_parent_commit" => parent_commit,
      "activation_parent_tree" => parent_tree,
      "max_engineering_tasks" => max_engineering_tasks,
      "max_engineering_hours" => max_engineering_hours,
      "max_calendar_days" => max_calendar_days,
      "max_same_task_repairs" => 1,
      "max_contract_corrections_per_task" => 0,
      "first_task_id" => task_ids.first,
      "first_task_engineering_hours" => task_budgets.first["engineering_hours"],
      "first_task_calendar_days" => task_budgets.first["calendar_days"],
      "first_task_implementation_iterations" => 2,
      "first_task_candidates" => 1,
      "task_ids" => task_ids,
      "task_budgets" => task_budgets,
      "primary_metric_min_delta" => primary_metric_min_delta,
      "founder_reserved_profile" => nil,
      "founder_reserved_profiles" => [],
      "external_effects" => FALSE_EXTERNAL_EFFECTS
    }
  rescue ArgumentError
    fail!("P2 graph decision packet contains a non-integer Phase envelope")
  end

  def p2_repository_intelligence_route_packet_claims(text)
    token = "AUTHORIZE_P1_PARTIAL_EXIT_WITH_DISCLOSED_RESIDUALS_AND_DIRECT_P2_REPOSITORY_INTELLIGENCE_PHASE_ENTRY_V1"
    assert(text.scan(token).length == 1, "P2 decision packet must contain the exact authorization token once")
    route_id = one_packet_match(
      text,
      /- route ID: `(P[0-9]_[A-Z0-9_]+_ROUTE_V[0-9]+)`/,
      "P2 route id"
    )
    parent_commit = one_packet_match(
      text,
      /- canonical commit: `([0-9a-f]{40})`/,
      "P2 activation parent commit"
    )
    parent_tree = one_packet_match(
      text,
      /- canonical tree: `([0-9a-f]{40})`/,
      "P2 activation parent tree"
    )
    max_engineering_tasks = Integer(one_packet_match(
      text, /- maximum engineering Tasks: `([0-9]+)`/, "P2 Task envelope"
    ), 10)
    max_engineering_hours = Integer(one_packet_match(
      text, /- maximum engineering hours: `([0-9]+)`/, "P2 hour envelope"
    ), 10)
    max_calendar_days = Integer(one_packet_match(
      text, /- maximum calendar days: `([0-9]+)`/, "P2 calendar envelope"
    ), 10)
    task_sections = text.scan(/^## [0-9]+\. Task [0-9]+\s*$\n(.*?)(?=^## |\z)/m).flatten
    task_budgets = task_sections.map do |section|
      {
        "task_id" => one_packet_match(
          section, /- Task ID: `(AIOS-P[0-9]-[0-9]{3}_[A-Z0-9_]+)`/, "P2 Task id"
        ),
        "engineering_hours" => Integer(one_packet_match(
          section, /- budget: `([0-9]+) engineering hours \//, "P2 Task engineering budget"
        ), 10),
        "calendar_days" => Integer(one_packet_match(
          section, /- budget: `[0-9]+ engineering hours \/ ([0-9]+) calendar days`/,
          "P2 Task calendar budget"
        ), 10)
      }
    end
    task_ids = task_budgets.map { |budget| budget["task_id"] }
    assert(task_ids.length == max_engineering_tasks && task_ids.uniq.length == task_ids.length,
           "P2 decision packet Task set is not closed")
    assert(task_budgets.sum { |budget| budget["engineering_hours"] } == max_engineering_hours,
           "P2 Task hours do not equal the route envelope")
    assert(task_budgets.sum { |budget| budget["calendar_days"] } == max_calendar_days,
           "P2 Task days do not equal the route envelope")
    assert(text.include?("each Task: initial implementation plus at most one same-Task code-only repair"),
           "P2 implementation iteration boundary drifted")
    assert(text.include?("Each Task may freeze one exact candidate"),
           "P2 candidate boundary drifted")
    assert(text.include?("- network, Provider, Secret, remote, production and public effects: `false`"),
           "P2 external-effect boundary drifted")
    primary_metric_min_delta = Float(one_packet_match(
      text,
      /file-localization recall@10 improves by at least `([0-9]+(?:\.[0-9]+)?)` absolute/,
      "P2 primary metric"
    ))
    {
      "text" => text,
      "authorization_token" => token,
      "route_id" => route_id,
      "activation_parent_commit" => parent_commit,
      "activation_parent_tree" => parent_tree,
      "max_engineering_tasks" => max_engineering_tasks,
      "max_engineering_hours" => max_engineering_hours,
      "max_calendar_days" => max_calendar_days,
      "max_same_task_repairs" => 1,
      "max_contract_corrections_per_task" => 0,
      "first_task_id" => task_ids.first,
      "first_task_engineering_hours" => task_budgets.first["engineering_hours"],
      "first_task_calendar_days" => task_budgets.first["calendar_days"],
      "first_task_implementation_iterations" => 2,
      "first_task_candidates" => 1,
      "task_ids" => task_ids,
      "task_budgets" => task_budgets,
      "primary_metric_min_delta" => primary_metric_min_delta,
      "founder_reserved_profile" => nil,
      "founder_reserved_profiles" => [],
      "external_effects" => FALSE_EXTERNAL_EFFECTS
    }
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
    claims = packet_claims(packet_bytes, packet_path, root: root)
    assert(route_id == claims["route_id"], "Truth route id does not match exact decision packet")
    if claims["structured_decision"]
      assert(route["phase"] == claims["phase"],
             "Truth route phase does not match structured Founder decision")
      assert(route["automatic_entry"] == claims["automatic_entry"],
             "Truth automatic entry does not match structured Founder decision")
      assert(route["claim_boundary"] == claims["claim_boundary"],
             "Truth claim boundary does not match structured Founder decision")
    end
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
       max_task_branches max_task_worktrees max_active_candidates].each do |key|
      assert(integer(envelope[key], "current_phase_route.envelope.#{key}") > 0,
             "current_phase_route.envelope.#{key} must be positive")
    end
    assert(integer(envelope["max_same_task_repairs"],
                   "current_phase_route.envelope.max_same_task_repairs") >= 0,
           "current_phase_route.envelope.max_same_task_repairs must be non-negative")
    contract_corrections = integer(envelope["max_contract_corrections_per_task"],
                                   "current_phase_route.envelope.max_contract_corrections_per_task")
    assert(contract_corrections >= 0,
           "current_phase_route.envelope.max_contract_corrections_per_task must be non-negative")
    %w[max_active_tasks max_task_branches max_task_worktrees max_active_candidates].each do |key|
      assert(envelope[key] == 1, "current_phase_route.envelope.#{key} must equal 1")
    end
    exact_false(envelope["successor_replacement_normalization_closure_feasibility_or_remediation_chain_allowed"],
                "route envelope correction-chain permission")
    expected_p2_entry = project["current_phase"] == "P2"
    assert(envelope["p2_entry_authorized"] == expected_p2_entry,
           "route envelope P2 entry must match current phase")
    exact_false(envelope["p3_entry_authorized"], "route envelope P3 entry")
    if claims["founder_reserved_profile"]
      route_profile = validate_founder_reserved_profile(
        route["founder_reserved_profile"], route_id, claims["first_task_id"],
        "current_phase_route.founder_reserved_profile"
      )
      validate_exact_profile_binding(
        route_profile,
        claims["founder_reserved_profile"],
        "Truth Founder-reserved profile does not equal the exact decision packet"
      )
      route_profiles = array(
        route["founder_reserved_profiles"],
        "current_phase_route.founder_reserved_profiles"
      )
      assert(route_profiles.length == claims["founder_reserved_profiles"].length,
             "Truth Founder profile set does not equal the exact decision packet")
      validated_route_profiles = route_profiles.each_with_index.map do |profile, index|
        validate_founder_reserved_profile(
          profile,
          route_id,
          claims["task_ids"][index],
          "current_phase_route.founder_reserved_profiles[#{index}]"
        )
      end
      validate_exact_profile_binding(
        validated_route_profiles,
        claims["founder_reserved_profiles"],
        "Truth Founder profile set does not equal the exact decision packet"
      )
      profile_task_ids = validated_route_profiles.map { |profile| profile["task_id"] }
      assert(profile_task_ids == claims["task_ids"] && profile_task_ids.uniq.length == profile_task_ids.length,
             "Truth Founder profile Task set is not closed")
      assert(validated_route_profiles.all? { |profile| profile["external_effects"] == route_profile["external_effects"] },
             "Truth Founder profiles must share one exact route external-effect ceiling")
      expected_effects = route_profile["external_effects"]
    else
      assert(!route.key?("founder_reserved_profile") || route["founder_reserved_profile"].nil?,
             "offline route must not invent a Founder-reserved provider profile")
      assert(!route.key?("founder_reserved_profiles") || route["founder_reserved_profiles"].nil?,
             "offline route must not invent a Founder-reserved provider profile set")
      expected_effects = claims.fetch("external_effects", FALSE_EXTERNAL_EFFECTS)
    end
    validate_external_effects(envelope["external_effects"], "current_phase_route.envelope.external_effects",
                              expected_effects)
    %w[max_engineering_tasks max_engineering_hours max_calendar_days].each do |key|
      assert(envelope[key] == claims[key], "route envelope #{key} does not match exact decision packet")
    end
    assert(envelope["max_same_task_repairs"] == claims["max_same_task_repairs"],
           "route envelope max_same_task_repairs does not match exact decision packet")
    unless claims["max_contract_corrections_per_task"].nil?
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
    if route.key?("accepted_input_ids")
      accepted_input_ids = array(route["accepted_input_ids"], "current_phase_route.accepted_input_ids")
      accepted_input_ids.each_with_index do |input_id, index|
        string(input_id, "current_phase_route.accepted_input_ids[#{index}]")
      end
      assert(accepted.keys.sort == accepted_input_ids.sort &&
             accepted_input_ids.uniq.length == accepted_input_ids.length,
             "current_phase_route.accepted_inputs does not equal its closed Truth input set")
    else
      assert(!accepted.empty?, "current_phase_route.accepted_inputs must not be empty")
    end
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
      source_phase = record.fetch("source_phase", project["current_phase"])
      assert(%w[P0 P1 P2].include?(source_phase), "accepted input #{input_id} source phase is invalid")
      validate_accepted_contract(current_contract, contract_path, task_id, source_phase,
                                 "accepted input #{input_id} current contract")
      validate_accepted_contract(historical_contract, record["task_contract_path"], task_id,
                                 source_phase, "accepted input #{input_id} accepted-commit contract")
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
    task_plan = array(route["task_plan"], "current_phase_route.task_plan")
    task_plan_ids = task_plan.map.with_index do |descriptor, index|
      item = hash(descriptor, "current_phase_route.task_plan[#{index}]")
      assert(item["task_slot"] == index + 1,
             "current_phase_route.task_plan slots must be contiguous and ordered")
      packet_budget = claims["task_budgets"].is_a?(Array) ? claims["task_budgets"][index] : nil
      if packet_budget
        assert(item["engineering_hours"] == packet_budget["engineering_hours"] &&
               item["calendar_days"] == packet_budget["calendar_days"],
               "current_phase_route.task_plan budget does not equal the exact decision packet")
        if claims["structured_decision"]
          %w[max_implementation_iterations max_same_task_repairs max_candidates].each do |key|
            assert(item[key] == packet_budget[key],
                   "current_phase_route.task_plan #{key} does not equal the structured Founder decision")
          end
        end
      end
      string(item["task_id"], "current_phase_route.task_plan[#{index}].task_id")
    end
    assert(task_plan_ids == claims["task_ids"] && task_plan_ids.uniq.length == task_plan_ids.length,
           "current_phase_route.task_plan Task set does not equal the exact decision packet")
    goal = hash(truth["goal"], "goal")
    if claims["structured_decision"]
      goal_binding = exact_keys(route["goal_identity"],
                                %w[raw_sha256 raw_byte_length canonicalization canonical_sha256 canonical_byte_length],
                                "current_phase_route.goal_identity")
      structured_goal = claims["goal_identity"]
      assert(goal_binding == {
        "raw_sha256" => structured_goal["raw_sha256"],
        "raw_byte_length" => structured_goal["raw_byte_length"],
        "canonicalization" => structured_goal["canonicalization"],
        "canonical_sha256" => structured_goal["canonical_sha256"],
        "canonical_byte_length" => structured_goal["canonical_byte_length"]
      }, "current Phase route Goal identity mismatch")
    elsif !claims["text"].include?(goal["observed_body_sha256"].to_s)
      goal_binding = exact_keys(route["goal_identity"],
                                %w[raw_sha256 raw_byte_length canonicalization canonical_sha256 canonical_byte_length],
                                "current_phase_route.goal_identity")
      assert(goal_binding == {
        "raw_sha256" => goal["observed_raw_body_sha256"],
        "raw_byte_length" => goal["observed_raw_body_byte_length"],
        "canonicalization" => goal["body_canonicalization"],
        "canonical_sha256" => goal["observed_body_sha256"],
        "canonical_byte_length" => goal["observed_body_byte_length"]
      }, "current Phase route Goal identity mismatch")
    end
    [route, route_id, first_task, accepted, claims]
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

  def null_identity(record, label)
    item = hash(record, label)
    assert(item.keys.sort == %w[byte_length path sha256], "#{label} must contain path, sha256 and byte_length")
    item.each { |key, value| assert(value.nil?, "#{label}.#{key} must be null while Task is NONE") }
  end

  def validate_none_state(root, truth, route, first_task, claims)
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
      phase_status_key = "#{project['current_phase'].downcase}_execution_status"
      assert(project["phase_execution_status"] == "AUTHORIZED_READY" &&
             project[phase_status_key] == "AUTHORIZED_READY",
             "initial Task NONE requires project AUTHORIZED_READY")
      assert(first_task["status"] == "ELIGIBLE_NOT_ACTIVATED",
             "initial Task NONE requires an eligible, non-activated first Task")
    else
      phase_status_key = "#{project['current_phase'].downcase}_execution_status"
      assert(%w[ACTIVE EXECUTING].include?(project["phase_execution_status"]) &&
             %w[ACTIVE EXECUTING].include?(project[phase_status_key]),
             "between-Task NONE requires active project execution")
      assert(first_task["status"] != "ACTIVE", "between-Task NONE cannot leave first Task active")
      validate_structured_predecessor_gate(
        root, truth, route, first_task, claims,
        claims.dig("automatic_entry", "next_task_id"),
        "READY"
      ) if claims["structured_decision"]
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
    expected_effects = claims["structured_decision"] ?
      claims.fetch("external_effects") : FALSE_EXTERNAL_EFFECTS
    validate_external_effects(active["external_effects"], "active_work.external_effects", expected_effects)
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

  def validate_active_state(root, truth, route, route_id, first_task, claims)
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
    phase_status_key = "#{project['current_phase'].downcase}_execution_status"
    assert(%w[ACTIVE EXECUTING].include?(project[phase_status_key]),
           "active Task requires active current-phase execution")
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
    expected_goal_identity = {
      "raw_sha256" => goal["observed_raw_body_sha256"],
      "raw_byte_length" => goal["observed_raw_body_byte_length"],
      "canonicalization" => goal["body_canonicalization"],
      "canonical_sha256" => goal["observed_body_sha256"],
      "canonical_byte_length" => goal["observed_body_byte_length"]
    }
    [contract, authority_record].each_with_index do |record, index|
      label = index.zero? ? "contract" : "authority record"
      binding = exact_keys(contract_field(record, "goal_identity"), expected_goal_identity.keys,
                           "#{label} Goal identity")
      assert(binding == expected_goal_identity, "#{label} Goal identity mismatch")
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
    assert(claims["task_ids"].include?(task_id),
           "active Task is outside the exact Founder decision Task set")
    plan_descriptor = array(route["task_plan"], "current_phase_route.task_plan").find do |item|
      item.is_a?(Hash) && item["task_id"] == task_id
    end
    assert(plan_descriptor, "active Task is absent from the closed route task_plan")
    validate_structured_predecessor_gate(
      root, truth, route, first_task, claims, task_id, "ACTIVE"
    )
    if claims["structured_decision"]
      packet_task = claims["task_budgets"].find { |item| item["task_id"] == task_id }
      assert(packet_task, "active Task has no structured Founder decision descriptor")
      {
        "max_engineering_hours" => "engineering_hours",
        "max_calendar_days" => "calendar_days",
        "max_implementation_iterations" => "max_implementation_iterations",
        "max_candidates" => "max_candidates"
      }.each do |descriptor_key, packet_key|
        assert(task_descriptor[descriptor_key] == packet_task[packet_key],
               "active Task #{descriptor_key} does not equal the structured Founder decision")
      end
    end
    budget = hash(active["budget"], "active_work.budget")
    if claims["structured_decision"]
      packet_task = claims["task_budgets"].find { |item| item["task_id"] == task_id }
      expected_task_budget = {
        "engineering_hours" => packet_task["engineering_hours"],
        "calendar_days" => packet_task["calendar_days"],
        "implementation_iterations" => packet_task["max_implementation_iterations"],
        "candidates" => packet_task["max_candidates"]
      }
      assert(budget == expected_task_budget,
             "active Task budget does not equal the structured Founder decision")
    end
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
    assert(contract_budget == budget, "contract budget mismatch")
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
    assert((scopes - contract_scopes).empty?,
           "active authority grants a path outside the reviewed Contract maximum scope")
    authority_scopes = normalize_scopes(contract_field(authority_record, "allowlisted_paths"),
                                        "authority record allowlisted_paths")
    assert(scopes == authority_scopes, "authority record allowlisted paths mismatch")
    boundary = hash(truth["phase_boundary"], "phase_boundary")
    route_roots = array(route.fetch("additional_write_roots", []),
                        "current_phase_route.additional_write_roots").map.with_index do |path, index|
      safe_scope_path(path, "current_phase_route.additional_write_roots[#{index}]")
    end
    roots = flatten_write_roots(boundary["role_write_roots"]) + route_roots
    immutable = array(boundary["immutable_authority_paths"], "phase_boundary.immutable_authority_paths")
    scopes.each do |scope|
      assert(roots.any? { |root_path| scope_within_root?(scope, root_path) },
             "allowlisted path is outside the current Phase role roots: #{scope}")
      assert(immutable.none? { |path| scope_within_root?(scope, path) || scope_within_root?(path, scope) },
             "allowlisted path overlaps immutable authority: #{scope}")
    end

    if claims["founder_reserved_profile"]
      selected_profile = claims["founder_reserved_profiles"].find do |profile|
        profile["task_id"] == task_id
      end
      assert(selected_profile, "active Task has no exact Founder-reserved profile")
      route_profile = array(
        route["founder_reserved_profiles"],
        "current_phase_route.founder_reserved_profiles"
      ).find { |profile| profile.is_a?(Hash) && profile["task_id"] == task_id }
      assert(route_profile, "Truth Founder profile set has no active Task profile")
      expected_effects = validate_founder_reserved_profile(
        route_profile, route_id, task_id, "current_phase_route active Founder-reserved profile"
      )["external_effects"]
      validate_exact_profile_binding(
        route_profile,
        selected_profile,
        "Truth active Founder-reserved profile does not equal the exact decision packet"
      )
    else
      expected_effects = claims.fetch("external_effects", FALSE_EXTERNAL_EFFECTS)
    end
    validate_external_effects(active["external_effects"], "active_work.external_effects", expected_effects)
    validate_external_effects(contract_field(contract, "external_effects"), "contract external_effects", expected_effects)
    validate_external_effects(contract_field(authority_record, "external_effects"), "authority external_effects",
                              expected_effects)
    if claims["founder_reserved_profile"]
      contract_profile = validate_founder_reserved_profile(
        contract_field(contract, "founder_reserved_profile"), route_id, task_id, "contract Founder-reserved profile"
      )
      authority_profile = validate_founder_reserved_profile(
        contract_field(authority_record, "founder_reserved_profile"), route_id, task_id,
        "authority Founder-reserved profile"
      )
      validate_exact_profile_binding(
        contract_profile,
        selected_profile,
        "contract Founder-reserved profile mismatch"
      )
      validate_exact_profile_binding(
        authority_profile,
        selected_profile,
        "authority Founder-reserved profile mismatch"
      )
    else
      assert(contract_field(contract, "founder_reserved_profile").nil?,
             "offline Contract must not invent a Founder-reserved provider profile")
      assert(contract_field(authority_record, "founder_reserved_profile").nil?,
             "offline authority must not invent a Founder-reserved provider profile")
    end
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
    route = hash(truth["current_phase_route"], "current_phase_route")
    inherited = array(route.fetch("inherited_worktree_inventory", []),
                      "current_phase_route.inherited_worktree_inventory")
    inherited_records = inherited.map.with_index do |value, index|
      record = exact_keys(value, %w[path head branch status],
                          "current_phase_route.inherited_worktree_inventory[#{index}]")
      path = string(record["path"], "inherited worktree path")
      assert(Pathname.new(path).absolute?, "inherited worktree path must be absolute")
      assert(COMMIT_RE.match?(string(record["head"], "inherited worktree head")),
             "inherited worktree head must be a full commit id")
      string(record["branch"], "inherited worktree branch")
      assert(record["status"] == "INHERITED_TERMINAL_OUT_OF_SCOPE_NOT_CURRENT",
             "inherited worktree status is not terminal and out of scope")
      record.merge("realpath" => File.realpath(path))
    end
    assert(inherited_records.map { |record| record["realpath"] }.uniq.length == inherited_records.length,
           "inherited worktree inventory contains duplicate paths")
    expected_paths = [File.realpath(canonical)] + inherited_records.map { |record| record["realpath"] }
    if active["current_task"] != "NONE"
      expected_paths << File.realpath(string(active["task_worktree"], "active_work.task_worktree"))
    end
    actual_paths = records.map { |record| File.realpath(record["path"]) }.sort
    assert(actual_paths == expected_paths.sort, "Git worktree set does not equal canonical plus declared active Task")
    canonical_record = records.find { |record| File.realpath(record["path"]) == File.realpath(canonical) }
    assert(canonical_record && canonical_record["branch"] == project["canonical_branch"],
           "canonical worktree branch identity mismatch")
    inherited_records.each do |expected|
      actual = records.find { |record| File.realpath(record["path"]) == expected["realpath"] }
      assert(actual && actual["head"] == expected["head"] && actual["branch"] == expected["branch"],
             "inherited terminal worktree inventory drifted")
    end
    return if active["current_task"] == "NONE"

    task_record = records.find { |record| File.realpath(record["path"]) == File.realpath(active["task_worktree"]) }
    assert(task_record && task_record["branch"] == active["task_branch"], "active Task worktree branch mismatch")
    _out, _err, lineage_status = git(root, "merge-base", "--is-ancestor",
                                      active["activation_parent_commit"], task_record["head"], allow_failure: true)
    assert(lineage_status.success?, "active Task worktree does not descend from its declared activation parent")
  end

  def validate!
    root = git(Dir.pwd, "rev-parse", "--show-toplevel").first.strip
    truth_path = File.join(root, "docs/aios/truth/project_state.yaml")
    truth = parse_yaml(secure_read(truth_path, "canonical Truth"), "canonical Truth")
    assert(truth["record_type"] == "sourcelens_aios_current_truth", "unexpected Truth record_type")
    validate_repository_and_worktrees(root, truth)
    validate_goal(truth)
    validate_authority_documents(root, truth)
    route, route_id, first_task, _accepted, claims = validate_route(root, truth)
    first_task_in_history = historical_task_ids(truth).include?(first_task["task_id"])
    if %w[ELIGIBLE_NOT_ACTIVATED ACTIVE].include?(first_task["status"])
      assert(!first_task_in_history, "first Task id reuses historical Truth while eligible or active")
    end
    if hash(truth["active_work"], "active_work")["current_task"] == "NONE"
      validate_none_state(root, truth, route, first_task, claims)
      "READY_NONE"
    else
      validate_active_state(root, truth, route, route_id, first_task, claims)
      "ACTIVE_TASK"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    state = CurrentTaskAuthority.validate!
    puts "CURRENT_TASK_AUTHORITY: PASS state=#{state}"
    exit 0
  rescue AuthorityValidationError => e
    warn "CURRENT_TASK_AUTHORITY: NON_PASS #{e.message}"
    exit 1
  rescue StandardError => e
    warn "CURRENT_TASK_AUTHORITY: NON_PASS unexpected #{e.class}: #{e.message}"
    exit 1
  end
end

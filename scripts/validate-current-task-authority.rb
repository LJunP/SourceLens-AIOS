#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "validate-founder-delegation-continuity"

class AuthorityValidationError < StandardError; end
class DuplicateJsonKeyError < StandardError; end

module CurrentTaskAuthority
  module_function

  SHA256_RE = /\A[0-9a-f]{64}\z/.freeze
  COMMIT_RE = /\A[0-9a-f]{40}\z/.freeze
  SAFE_TASK_ID_RE = /\AAIOS-P[12]-[0-9]{3}(?:_[A-Z0-9_]+)?\z/.freeze
  ROUTE_ID_RE = /\AP[12]_[A-Z0-9_]+_ROUTE_V[1-9][0-9]*\z/.freeze
  SINGLE_TASK_EXPANSION_DECISION_VERSIONS = %w[1.2 1.3].freeze
  CUMULATIVE_CAPACITY_DECISION_VERSIONS = %w[1.4].freeze
  TASK_EFFECT_DECISION_VERSIONS = %w[1.1 1.2 1.3].freeze
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
  DELEGATED_TASK_ROUTE_SCHEMA = "phase-delegated-independent-task/v1"
  DELEGATED_TASK_CONTRACT_TYPE = "aios_phase_delegated_independent_task_contract"
  DELEGATED_TASK_AUTHORITY_TYPE = "aios_phase_delegated_independent_task_authority"
  ACTIVE_STATUSES = %w[ACTIVE AUTHORIZED_ACTIVE EXECUTING].freeze
  AUTHORIZED_ROUTE_STATUSES = %w[AUTHORIZED_READY ACTIVE PHASE_GATE_READY].freeze
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
    assert(before.nlink == 1, "#{label} must not be hardlinked: #{path}")

    flags = File::RDONLY
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    bytes = nil
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino, opened.nlink] == [before.dev, before.ino, before.nlink],
             "#{label} changed while opening: #{path}")
      bytes = file.read
      after = file.stat
      assert([after.dev, after.ino, after.nlink, after.size, after.mtime.to_f] ==
             [opened.dev, opened.ino, opened.nlink, opened.size, opened.mtime.to_f],
             "#{label} changed while reading: #{path}")
    end
    final = File.lstat(path)
    assert([final.dev, final.ino, final.nlink, final.size, final.mtime.to_f] ==
           [before.dev, before.ino, before.nlink, before.size, before.mtime.to_f],
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

  def validate_accepted_gate_history(root, truth, route, task_id, label)
    history = accepted_history_record(truth, task_id, label)
    assert(history["route_id"] == route["route_id"],
           "#{label} history route mismatch")
    contract_path_value = history["contract"] || history["contract_path"]
    contract_path = repo_path(root, contract_path_value, "#{label} contract")
    contract_sha = string(
      history["task_contract_sha256"],
      "#{label} task_contract_sha256"
    )
    current_contract = validate_sha_only(contract_path, contract_sha, "#{label} contract")
    current_contract_record = validate_accepted_contract(
      current_contract,
      contract_path,
      task_id,
      route["phase"],
      "#{label} current contract"
    )
    assert(contract_field(current_contract_record, "route_id") == route["route_id"],
           "#{label} current contract route mismatch")
    accepted_commit = string(
      history["accepted_candidate_commit"],
      "#{label} accepted_candidate_commit"
    )
    accepted_tree = string(
      history["accepted_candidate_tree"],
      "#{label} accepted_candidate_tree"
    )
    validate_commit_tree(root, accepted_commit, accepted_tree, "#{label} accepted candidate")
    _out, _err, ancestor_status = git(
      root,
      "merge-base",
      "--is-ancestor",
      accepted_commit,
      "HEAD",
      allow_failure: true
    )
    assert(ancestor_status.success?, "#{label} accepted candidate is not canonical")
    historical_contract, _historical_contract_error, historical_contract_status = git(
      root,
      "show",
      "#{accepted_commit}:#{contract_path_value}",
      allow_failure: true
    )
    assert(historical_contract_status.success?,
           "#{label} accepted commit does not contain the declared contract path")
    assert(sha256(historical_contract) == contract_sha,
           "#{label} accepted commit does not bind the declared contract bytes")
    assert(historical_contract == current_contract,
           "#{label} current and accepted-commit contract bytes differ")
    historical_contract_record = validate_accepted_contract(
      historical_contract,
      contract_path_value,
      task_id,
      route["phase"],
      "#{label} accepted-commit contract"
    )
    assert(contract_field(historical_contract_record, "route_id") == route["route_id"],
           "#{label} accepted-commit contract route mismatch")
    verdict_keys = %w[cto_target_verdict security_target_verdict quality_target_verdict]
    unless verdict_keys.all? { |key| history[key] == "PASS" }
      validate_founder_residual_gate_acceptance(history, verdict_keys, label)
    end
    assert(history["reviewed_tree_equals_integrated_tree"] == true,
           "#{label} reviewed/integrated tree mismatch")
    assert(history["canonical_make_verify"] == "PASS",
           "#{label} canonical make verify is not PASS")
    history
  end

  def validate_founder_residual_gate_acceptance(history, verdict_keys, label)
    assert(history["status"] == "FOUNDER_GATE_ACCEPTED_COMPLETE",
           "#{label} Reviewer NON_PASS requires an exact Founder Gate acceptance")
    residual = exact_keys(
      history["founder_residual_acceptance"],
      %w[
        acceptance_scope capability_acceptance_authorized candidate_bytes_modified
        decision preserved_non_pass_review preserved_non_pass_role
        review_non_pass_preserved review_non_pass_rewritten_as_pass
      ],
      "#{label} founder_residual_acceptance"
    )
    assert(residual["acceptance_scope"] == "DOCUMENTATION_ONLY_OUTSIDE_CORRECTION_ALLOWLIST",
           "#{label} Founder residual scope is not the bounded documentation-only scope")
    assert(residual["capability_acceptance_authorized"] == true,
           "#{label} Founder residual does not authorize capability acceptance")
    assert(residual["candidate_bytes_modified"] == false,
           "#{label} Founder residual cannot authorize modified candidate bytes")
    assert(residual["review_non_pass_preserved"] == true,
           "#{label} Founder residual must preserve the Reviewer NON_PASS")
    assert(residual["review_non_pass_rewritten_as_pass"] == false,
           "#{label} Founder residual cannot rewrite Reviewer NON_PASS as PASS")

    role = string(residual["preserved_non_pass_role"],
                  "#{label} founder_residual_acceptance.preserved_non_pass_role")
    verdict_key = "#{role}_target_verdict"
    assert(verdict_keys.include?(verdict_key),
           "#{label} Founder residual preserved Reviewer role is invalid")
    assert(history[verdict_key] == "NON_PASS",
           "#{label} Founder residual does not preserve the exact Reviewer NON_PASS")
    assert((verdict_keys - [verdict_key]).all? { |key| history[key] == "PASS" },
           "#{label} Founder residual requires exactly one preserved Reviewer NON_PASS")

    review = exact_keys(
      residual["preserved_non_pass_review"],
      %w[byte_length path sha256],
      "#{label} founder_residual_acceptance.preserved_non_pass_review"
    )
    review_path = string(review["path"], "#{label} preserved NON_PASS Review path")
    assert(Pathname.new(review_path).absolute?,
           "#{label} preserved NON_PASS Review path must be absolute")
    validate_identity(review_path, review, "#{label} preserved NON_PASS Review")
    assert(history["#{role}_review_path"] == review_path &&
           history["#{role}_review_sha256"] == review["sha256"] &&
           history["#{role}_review_byte_length"] == review["byte_length"],
           "#{label} preserved NON_PASS Review identity does not equal Task history")

    decision = exact_keys(
      residual["decision"],
      %w[authorization_token byte_length path sha256],
      "#{label} founder_residual_acceptance.decision"
    )
    decision_path = string(decision["path"], "#{label} Founder residual decision path")
    assert(Pathname.new(decision_path).absolute?,
           "#{label} Founder residual decision path must be absolute")
    decision_bytes = validate_identity(decision_path, decision, "#{label} Founder residual decision")
    decision_text = decision_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(decision_text.valid_encoding?, "#{label} Founder residual decision is not valid UTF-8")
    declarations = decision_text.scan(/^authorization_token=([A-Z0-9_]+)$/)
    token = string(decision["authorization_token"],
                   "#{label} Founder residual decision authorization_token")
    assert(declarations == [[token]],
           "#{label} Founder residual decision must contain exactly one matching anchored authorization_token")
  end

  def validate_structured_predecessor_gate(root, truth, route, first_task, claims, next_task_id, state)
    return unless claims["structured_decision"]
    return if next_task_id == claims["task_ids"].first

    next_index = claims["task_ids"].index(next_task_id)
    assert(next_index && next_index.positive?,
           "structured automatic entry cannot activate an undeclared successor Task")
    automatic_entry = claims.fetch("automatic_entries").find do |entry|
      entry["next_task_id"] == next_task_id
    end
    assert(automatic_entry,
           "structured automatic entry cannot activate an undeclared successor Task")
    predecessor_id = automatic_entry["after_task_id"]
    expected_next_id = automatic_entry["next_task_id"]
    assert(predecessor_id == claims["task_ids"][next_index - 1] &&
           expected_next_id == next_task_id,
           "structured automatic entry is not the exact adjacent predecessor edge")
    assert(automatic_entry["requires_task_gate_pass"] == true,
           "structured automatic entry requires predecessor Task Gate PASS")

    task_plan = array(route["task_plan"], "current_phase_route.task_plan")
    successor = task_plan.find { |item| item.is_a?(Hash) && item["task_id"] == expected_next_id }
    expected_successor_status = state == "ACTIVE" ? "ACTIVE" : "ELIGIBLE_NOT_ACTIVATED"
    assert(successor && successor["status"] == expected_successor_status,
           "structured automatic entry successor task_plan status mismatch")

    claims["task_ids"].take(next_index).each_with_index do |accepted_task_id, index|
      descriptor = task_plan.fetch(index)
      assert(descriptor.is_a?(Hash) && descriptor["task_id"] == accepted_task_id &&
             ACCEPTED_GATE_STATUS_RE.match?(descriptor["status"].to_s),
             "structured automatic entry accepted task_plan prefix is incomplete")
      if index.zero?
        assert(first_task["task_id"] == accepted_task_id &&
               first_task["status"] == descriptor["status"],
               "structured automatic entry first_task does not equal its task_plan state")
      end

      validate_accepted_gate_history(
        root,
        truth,
        route,
        accepted_task_id,
        "structured automatic entry accepted prefix Task #{index + 1}"
      )
    end
  end

  def validate_structured_task_state_vector(route, first_task, claims, target_task_id:, target_state:)
    return unless claims["structured_decision"]

    task_plan = array(route["task_plan"], "current_phase_route.task_plan")
    assert(task_plan.length == claims["task_ids"].length,
           "structured route task_plan length drifted")
    target_index = if target_state == "COMPLETE"
                     task_plan.length
                   else
                     claims["task_ids"].index(target_task_id)
                   end
    assert(target_index, "structured route state vector target Task is undeclared")
    task_plan.each_with_index do |descriptor, index|
      item = hash(descriptor, "current_phase_route.task_plan[#{index}]")
      assert(item["task_id"] == claims["task_ids"][index],
             "structured route state vector Task order drifted")
      expected = if index < target_index
                   :accepted
                 elsif index == target_index
                   target_state
                 else
                   "PENDING_PREDECESSOR_TASK_GATE"
                 end
      if expected == :accepted
        assert(ACCEPTED_GATE_STATUS_RE.match?(item["status"].to_s),
               "structured route state vector accepted prefix is incomplete")
      else
        assert(item["status"] == expected,
               "structured route state vector status mismatch at Task #{index + 1}")
      end
    end
    assert(first_task["task_id"] == claims["task_ids"].first &&
           first_task["status"] == task_plan.first["status"],
           "structured route first_task and task_plan state diverged")
    active_count = task_plan.count { |item| item.is_a?(Hash) && item["status"] == "ACTIVE" }
    eligible_count = task_plan.count do |item|
      item.is_a?(Hash) && item["status"] == "ELIGIBLE_NOT_ACTIVATED"
    end
    expected_active = target_state == "ACTIVE" ? 1 : 0
    expected_eligible = target_state == "ELIGIBLE_NOT_ACTIVATED" ? 1 : 0
    assert(active_count == expected_active && eligible_count == expected_eligible,
           "structured route state vector active/eligible cardinality drifted")
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
    actual = record.keys.sort
    expected_sorted = expected.sort
    missing = expected_sorted - actual
    extra = actual - expected_sorted
    assert(actual == expected_sorted,
           "#{label} keys drifted: missing=#{missing.inspect} extra=#{extra.inspect}")
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

  def validate_founder_reserved_profile_v4(value, route_id, task_id, label)
    profile = exact_keys(
      value,
      %w[
        schema_version profile_id decision_basis route_id task_id transport model
        secret call_limits monetary_limits external_effects claim_limits
      ],
      label
    )
    assert(profile["schema_version"] == "4.0", "#{label} schema version drifted")
    string(profile["profile_id"], "#{label}.profile_id")
    assert(profile["decision_basis"].is_a?(String) &&
           profile["decision_basis"].match?(/\AFOUNDER_PACKET_SHA256:[0-9a-f]{64}\z/),
           "#{label}.decision_basis must bind the exact Founder packet")
    assert(profile["route_id"] == route_id, "#{label} route id mismatch")
    assert(profile["task_id"] == task_id, "#{label} Task id mismatch")

    transport = exact_keys(
      profile["transport"],
      %w[
        scheme host port completion_path api_format method follow_redirects
        use_proxy dns_resolution fallback_endpoint_allowed expected_peer_address
        expected_peer_port
      ],
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

    model = exact_keys(
      profile["model"],
      %w[requested_model substitution_allowed provider_provenance],
      "#{label}.model"
    )
    string(model["requested_model"], "#{label}.model.requested_model")
    exact_false(model["substitution_allowed"], "#{label}.model.substitution_allowed")
    assert(
      model["provider_provenance"] ==
        "FOUNDER_ATTESTED_OPENAI_COMPATIBLE_LOCAL_GATEWAY_MODEL_NOT_INDEPENDENTLY_VERIFIED",
      "#{label}.model provider provenance must remain Founder-attested and independently unverified"
    )

    secret = exact_keys(
      profile["secret"],
      %w[source entry_sessions persist prohibited_sinks],
      "#{label}.secret"
    )
    assert(secret["source"] == "FOUNDER_OPERATOR_NO_ECHO_TTY",
           "#{label}.secret source must remain the Founder/operator no-echo TTY")
    assert(secret["entry_sessions"] == 1, "#{label}.secret entry sessions must equal 1")
    exact_false(secret["persist"], "#{label}.secret.persist")
    assert(array(secret["prohibited_sinks"], "#{label}.secret.prohibited_sinks") ==
           %w[
             ARGV ENVIRONMENT SHELL_HISTORY REPOSITORY TEMPORARY_PLAINTEXT_FILE
             EVIDENCE LOG TRACE PROMPT REVIEW VAULT
           ],
           "#{label}.secret prohibited sinks drifted")

    calls = exact_keys(
      profile["call_limits"],
      %w[diagnostic_requests_max formal_requests_exact provider_requests_max automatic_retry_max],
      "#{label}.call_limits"
    )
    diagnostic_requests = integer(
      calls["diagnostic_requests_max"],
      "#{label}.call_limits.diagnostic_requests_max"
    )
    formal_requests = integer(
      calls["formal_requests_exact"],
      "#{label}.call_limits.formal_requests_exact"
    )
    provider_requests = integer(
      calls["provider_requests_max"],
      "#{label}.call_limits.provider_requests_max"
    )
    assert(diagnostic_requests.between?(0, 3),
           "#{label}.call limits drifted: diagnostic_requests_max must be in 0..3")
    assert(formal_requests.between?(1, 144),
           "#{label}.call limits drifted: formal_requests_exact must be in 1..144")
    assert(provider_requests.between?(1, 144),
           "#{label}.call limits drifted: provider_requests_max must be in 1..144")
    assert(provider_requests == diagnostic_requests + formal_requests,
           "#{label}.call limits must reserve the exact diagnostic plus formal request total")
    assert(calls["automatic_retry_max"] == 0,
           "#{label}.call limits drifted: automatic_retry_max must equal 0")

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

    validate_external_effects(
      profile["external_effects"],
      "#{label}.external_effects",
      LOCAL_GATEWAY_EXTERNAL_EFFECTS
    )
    claims = exact_keys(
      profile["claim_limits"],
      %w[
        direct_openai_provenance_proven gateway_upstream_behavior
        upstream_request_count actual_monetary_cost hostile_principal_isolation
        production remote public p2_entry
      ],
      "#{label}.claim_limits"
    )
    assert(claims == {
      "direct_openai_provenance_proven" => false,
      "gateway_upstream_behavior" => "UNKNOWN",
      "upstream_request_count" => "UNKNOWN",
      "actual_monetary_cost" => "UNKNOWN_UNLESS_TRUSTWORTHY_GATEWAY_EVIDENCE_EXISTS",
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
    when "4.0"
      validate_founder_reserved_profile_v4(profile, route_id, task_id, label)
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

  def source_founder_packet_v1_3_claims(packet_bytes, decision, root)
    text = packet_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(text.valid_encoding?, "structured Founder route decision v1.3 source packet must be valid UTF-8")
    declared_token = one_packet_match(
      text,
      /^- Exact authorization token:\n  `([A-Z0-9_]+)`$/,
      "v1.3 exact authorization token declaration"
    )
    message_token = one_packet_match(
      text,
      /^- Exact Founder message:\n  `([A-Z0-9_]+)；[^`\n]+`$/,
      "v1.3 exact Founder message"
    )
    expected_token = decision.fetch("authorization_token")
    assert(declared_token == expected_token && message_token == expected_token,
           "structured Founder route decision v1.3 source packet token binding drift")
    packet_tokens = text.scan(/AUTHORIZE_[A-Za-z0-9_]+/)
    assert(packet_tokens == [expected_token, expected_token],
           "structured Founder route decision v1.3 source packet authorization token occurrences drift")

    parent = decision.fetch("activation_parent")
    assert(one_packet_match(text, /^- Branch: `([^`]+)`$/, "v1.3 canonical branch") == "main",
           "structured Founder route decision v1.3 source packet branch drift")
    assert(one_packet_match(text, /^- Commit: `([0-9a-f]{40})`$/, "v1.3 canonical commit") == parent["commit"],
           "structured Founder route decision v1.3 source packet commit drift")
    assert(one_packet_match(text, /^- Tree: `([0-9a-f]{40})`$/, "v1.3 canonical tree") == parent["tree"],
           "structured Founder route decision v1.3 source packet tree drift")
    truth_sha = one_packet_match(
      text,
      /^- Truth SHA-256:\n  `([0-9a-f]{64})`$/,
      "v1.3 activation-parent Truth SHA-256"
    )
    parent_truth = git(root, "show", "#{parent['commit']}:docs/aios/truth/project_state.yaml").first.b
    assert(truth_sha == sha256(parent_truth),
           "structured Founder route decision v1.3 source packet Truth SHA-256 drift")

    task_id = one_packet_match(
      text,
      /^- Task ID:\n  `(AIOS-P[12]-[0-9]{3}(?:_[A-Z0-9_]+)?)`$/,
      "v1.3 exact Task id"
    )
    route_id = one_packet_match(
      text,
      /^- Route ID: `(P[12]_[A-Z0-9_]+_ROUTE_V[1-9][0-9]*)`$/,
      "v1.3 exact Route id"
    )
    assert(task_id == decision.dig("ordered_tasks", 0, "task_id") &&
           route_id == decision.fetch("route_id"),
           "structured Founder route decision v1.3 source packet Task or Route binding drift")

    cumulative = {
      "engineering_tasks" => Integer(one_packet_match(
        text, /- `([0-9]+) engineering Tasks` maximum;/, "v1.3 cumulative Task ceiling"
      ), 10),
      "engineering_hours" => Integer(one_packet_match(
        text, /- `([0-9]+) engineering hours` maximum;/, "v1.3 cumulative hour ceiling"
      ), 10),
      "calendar_days" => Integer(one_packet_match(
        text, /- `([0-9]+) calendar days` maximum;/, "v1.3 cumulative day ceiling"
      ), 10)
    }
    envelope = decision.fetch("envelope")
    assert(cumulative == {
      "engineering_tasks" => envelope.fetch("max_engineering_tasks"),
      "engineering_hours" => envelope.fetch("max_engineering_hours"),
      "calendar_days" => envelope.fetch("max_calendar_days")
    }, "structured Founder route decision v1.3 source packet cumulative envelope drift")
    incremental = one_packet_match(
      text,
      /The incremental reservation is exactly `([0-9]+) Task \/ ([0-9]+) engineering hours \/ ([0-9]+)\s+calendar days`\./m,
      "v1.3 incremental Task envelope"
    ).map { |value| Integer(value, 10) }
    task = decision.dig("ordered_tasks", 0)
    assert(incremental == [1, task.fetch("engineering_hours"), task.fetch("calendar_days")],
           "structured Founder route decision v1.3 source packet incremental envelope drift")
    assert(text.scan(/^- Product mutation: prohibited\. The Task evaluates current canonical Code QA\.$/).length == 1,
           "structured Founder route decision v1.3 source packet product mutation boundary drift")
    assert(text.scan(/zero network, Provider, Secret, remote, production or public effects\./).length == 1,
           "structured Founder route decision v1.3 source packet external effect boundary drift")
    assert(text.scan(/P3 HOLD, production readiness or public state\./).length == 1 &&
           text.scan(/no second Task,[\s\S]*?Phase exit or Long-term Goal completion\./).length == 1,
           "structured Founder route decision v1.3 source packet Phase or Goal boundary drift")
    true
  rescue ArgumentError
    fail!("structured Founder route decision v1.3 source packet contains a non-integer envelope")
  end

  def source_founder_packet_v1_4_claims(packet_bytes, decision, root)
    text = packet_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(text.valid_encoding?,
           "structured Founder route decision v1.4 source packet must be valid UTF-8")
    expected_token = decision.fetch("authorization_token")
    declared_token = one_packet_match(
      text,
      /^- Exact authorization token:\n  `([A-Z0-9_]+)`$/,
      "v1.4 exact authorization token declaration"
    )
    message_token = one_packet_match(
      text,
      /^- Exact Founder message:\n  `([A-Z0-9_]+)；[^`\n]+`$/,
      "v1.4 exact Founder message"
    )
    assert(declared_token == expected_token && message_token == expected_token &&
           text.scan(/AUTHORIZE_[A-Za-z0-9_]+/) == [expected_token, expected_token],
           "structured Founder route decision v1.4 source packet token binding drift")

    parent = decision.fetch("activation_parent")
    assert(one_packet_match(text, /^- Branch: `([^`]+)`$/, "v1.4 canonical branch") == "main",
           "structured Founder route decision v1.4 source packet branch drift")
    assert(one_packet_match(text, /^- Commit: `([0-9a-f]{40})`$/, "v1.4 canonical commit") == parent["commit"] &&
           one_packet_match(text, /^- Tree: `([0-9a-f]{40})`$/, "v1.4 canonical tree") == parent["tree"],
           "structured Founder route decision v1.4 source packet parent drift")
    parent_truth = git(root, "show", "#{parent['commit']}:docs/aios/truth/project_state.yaml").first.b
    parent_truth_record = parse_yaml(parent_truth, "v1.4 activation-parent Truth")
    truth_sha = one_packet_match(
      text, /^- Truth SHA-256:\n  `([0-9a-f]{64})`$/,
      "v1.4 activation-parent Truth SHA-256"
    )
    assert(truth_sha == sha256(parent_truth),
           "structured Founder route decision v1.4 source packet Truth SHA-256 drift")

    plan = decision.fetch("recovery_plan_identity")
    assert(one_packet_match(text, /^- Recovery plan: `([^`]+)`$/, "v1.4 recovery plan path") == plan["path"] &&
           Integer(one_packet_match(text, /^- Recovery plan bytes: `([0-9]+)`$/, "v1.4 recovery plan bytes"), 10) == plan["byte_length"] &&
           one_packet_match(text, /^- Recovery plan SHA-256: `([0-9a-f]{64})`$/, "v1.4 recovery plan SHA-256") == plan["sha256"],
           "structured Founder route decision v1.4 source packet recovery plan drift")

    prior = decision.fetch("prior_consumed_envelope").fetch("consumed")
    envelope = decision.fetch("envelope")
    prior_values = one_packet_match(
      text,
      /The prior consumed envelope is exactly `([0-9]+) Tasks \/ ([0-9]+) engineering hours \/ ([0-9]+) calendar days`\./,
      "v1.4 prior envelope"
    ).map { |value| Integer(value, 10) }
    cumulative_values = one_packet_match(
      text,
      /The cumulative envelope is exactly `([0-9]+) Tasks \/ ([0-9]+) engineering hours \/ ([0-9]+) calendar days`\./,
      "v1.4 cumulative envelope"
    ).map { |value| Integer(value, 10) }
    incremental_values = one_packet_match(
      text,
      /The (?:incremental capacity|executable remainder) is exactly `([0-9]+) Tasks \/ ([0-9]+) engineering hours \/ ([0-9]+) calendar days`\./,
      "v1.4 incremental envelope"
    ).map { |value| Integer(value, 10) }
    slots = decision.fetch("capacity_slots")
    assert(prior_values == [prior["engineering_tasks"], prior["engineering_hours"], prior["calendar_days"]] &&
           cumulative_values == [envelope["max_engineering_tasks"], envelope["max_engineering_hours"], envelope["max_calendar_days"]] &&
           incremental_values == [slots.length, slots.sum { |slot| slot["engineering_hours"] }, slots.sum { |slot| slot["calendar_days"] }],
           "structured Founder route decision v1.4 source packet envelope drift")
    parent_envelope = hash(parent_truth_record["phase_execution_envelope"],
                           "v1.4 activation-parent phase execution envelope")
    if parent_envelope["status"] == "ACTIVE_REMAINING_CAPACITY"
      superseded_values = one_packet_match(
        text,
        /The superseded unused capacity is exactly `([0-9]+) Tasks? \/ ([0-9]+) engineering hours \/ ([0-9]+) calendar days`\./,
        "v1.4 superseded unused capacity"
      ).map { |value| Integer(value, 10) }
      terminal_lineage_boundary =
        text.scan(/P2-068 is preserved only as closed terminal accounting\./).length == 1 ||
        (expected_token ==
          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE_V5" &&
         text.scan(/P2-069 remains the independently accepted benchmark foundation\. P2-070, P2-071, P2-072, P2-073 and P2-074 are preserved only as closed terminal accounting\./).length == 1) ||
        (expected_token ==
          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE_V6" &&
         text.scan(/P2-069 remains the independently accepted benchmark foundation\. P2-070, P2-071, P2-072, P2-073, P2-074 and P2-075 are preserved only as closed terminal accounting\./).length == 1) ||
        (expected_token ==
          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V7" &&
         text.scan(/P2-069 remains the independently accepted benchmark foundation\. P2-070, P2-071, P2-072, P2-073, P2-074, P2-075 and P2-076 are preserved only as closed terminal accounting\./).length == 1) ||
        (expected_token ==
          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE_V8" &&
         text.scan(/P2-069 remains the independently accepted benchmark foundation\. P2-070, P2-071, P2-072, P2-073, P2-074, P2-075, P2-076 and P2-077 are preserved only as closed terminal accounting\./).length == 1)
      remaining = parent_envelope.fetch("remaining")
      assert(superseded_values == [remaining["engineering_tasks"], remaining["engineering_hours"], remaining["calendar_days"]] &&
             text.scan(/Only unused capacity is superseded; all [0-9]+ consumed Task outcomes and their Evidence remain immutable\./).length == 1 &&
             terminal_lineage_boundary,
             "structured Founder route decision v1.4 resequencing boundary drift")
    else
      assert(parent_envelope["status"] == "EXHAUSTED",
             "structured Founder route decision v1.4 activation-parent lifecycle drift")
    end
    assert(text.scan(/Task IDs remain unallocated until (?:(?:the preceding milestone and )?Task )?admission pass(?:es)?\./).length == 1,
           "structured Founder route decision v1.4 source packet preallocation boundary drift")
    external_effect_boundary =
      text.scan(/zero network, Provider, Secret, remote, production or public effects\./).length == 1 ||
      text.scan(/authorizes zero network, Provider, Secret, remote, production, public, deletion, database, P3 or long-term Goal effects\./).length == 1 ||
      text.scan(/It authorizes exactly one fresh process-local H2 in-memory test database destroyed at process exit and authorizes no connection to or modification of any existing, user, canonical, Codex-control-plane or operational database\. It authorizes zero network, Provider, Secret, remote, production, public, deletion, P3 or long-term Goal effects\./).length == 1
    assert(external_effect_boundary,
           "structured Founder route decision v1.4 source packet external effect boundary drift")
    assert(text.scan(/P3 remains HOLD and the SourceLens project and [Ll]ong-term Goal remain ACTIVE\./).length == 1,
           "structured Founder route decision v1.4 source packet Phase or Goal boundary drift")
    true
  rescue ArgumentError
    fail!("structured Founder route decision v1.4 source packet contains a non-integer envelope")
  end

  def validate_v1_4_prior_consumed_envelope(root, decision, parent, phase)
    assert(root,
           "structured Founder route decision v1.4 requires a repository root for prior accounting validation")
    prior = exact_keys(
      decision["prior_consumed_envelope"],
      %w[
        consumed source_route_id task_ledger_canonical_byte_length
        task_ledger_canonical_sha256 task_ledger_canonicalization task_ledger_entry_count
      ],
      "structured Founder route decision.prior_consumed_envelope"
    )
    consumed = exact_keys(
      prior["consumed"],
      %w[calendar_days engineering_hours engineering_tasks],
      "structured Founder route decision.prior_consumed_envelope.consumed"
    )
    consumed.each do |key, value|
      assert(integer(value, "structured decision prior consumed #{key}").positive?,
             "structured decision prior consumed #{key} must be positive")
    end
    assert(prior["task_ledger_canonicalization"] == "RECURSIVE_KEY_SORT_COMPACT_JSON_UTF8",
           "structured decision prior Task ledger canonicalization mismatch")
    ledger_count = integer(prior["task_ledger_entry_count"],
                           "structured decision prior Task ledger entry count")
    ledger_length = integer(prior["task_ledger_canonical_byte_length"],
                            "structured decision prior Task ledger canonical byte length")
    ledger_sha = string(prior["task_ledger_canonical_sha256"],
                        "structured decision prior Task ledger canonical SHA-256")
    assert(ledger_count.positive? && ledger_length.positive? && SHA256_RE.match?(ledger_sha),
           "structured decision prior Task ledger identity is invalid")

    parent_truth_bytes = git(root, "show", "#{parent['commit']}:docs/aios/truth/project_state.yaml").first
    parent_truth = parse_yaml(parent_truth_bytes, "structured decision activation-parent Truth")
    parent_envelope = hash(parent_truth["phase_execution_envelope"],
                           "structured decision activation-parent phase_execution_envelope")
    parent_limits = exact_keys(
      parent_envelope["limits"],
      %w[active_candidates active_tasks calendar_days engineering_hours engineering_tasks task_branches task_worktrees],
      "structured decision activation-parent envelope limits"
    )
    parent_consumed = exact_keys(
      parent_envelope["consumed"],
      %w[calendar_days engineering_hours engineering_tasks],
      "structured decision activation-parent envelope consumed"
    )
    parent_remaining = exact_keys(
      parent_envelope["remaining"],
      %w[calendar_days engineering_hours engineering_tasks],
      "structured decision activation-parent envelope remaining"
    )
    parent_control = hash(parent_truth["founder_escalation_control"],
                          "structured decision activation-parent Founder control")
    parent_budget_limits = parent_limits.slice(
      "calendar_days", "engineering_hours", "engineering_tasks"
    )
    accounting_conserved = parent_budget_limits.all? do |key, value|
      value == parent_consumed.fetch(key) + parent_remaining.fetch(key)
    end
    assert(parent_envelope["phase"] == phase && parent_envelope["reserved"].nil? &&
           accounting_conserved,
           "structured decision activation-parent envelope accounting is not conserved")
    if parent_envelope["status"] == "EXHAUSTED"
      assert(parent_consumed == parent_budget_limits && parent_remaining.values.all?(&:zero?) &&
             parent_control.dig("reserved_trigger", "category") == decision["exact_reserved_trigger"] &&
             parent_control["founder_decision_required"] == true,
             "structured decision does not resolve the exact exhausted activation-parent trigger")
    else
      product_selector_recovery = %w[
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_RECOVERY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V1
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V2
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V3
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V4
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE_V5
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE_V6
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V7
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE_V8
      ].include?(decision["authorization_token"])
      versioned_slots = array(decision["capacity_slots"],
                              "structured decision resequenced capacity slots").all? do |slot|
        slot.is_a?(Hash) && slot["capacity_slot_id"].to_s.match?(
          /\AP2_RECOVERY_CAPACITY_SLOT_V[1-9][0-9]*_[1-9][0-9]*\z/
        )
      end
      assert(parent_envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
             parent_remaining.values.all?(&:positive?) &&
             (product_selector_recovery ?
               parent_control.dig("reserved_trigger", "category") == decision["exact_reserved_trigger"] &&
                 parent_control["founder_decision_required"] == true :
               parent_control.dig("reserved_trigger", "category") == "NONE" &&
                 parent_control["founder_decision_required"] == false) &&
             parent_truth.dig("active_work", "current_task") == "NONE" &&
             parent_truth.dig("p2_recovery_control", "task_creation_allowed") == false &&
             (!product_selector_recovery ||
               %w[
                 CLEAN_ROOM_SLOT_V2_2_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_LOCKED
                 CLEAN_ROOM_SLOT_V3_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
                 CLEAN_ROOM_SLOT_V4_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
                 CLEAN_ROOM_SLOT_V5_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
                 CLEAN_ROOM_SLOT_V6_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
                 CLEAN_ROOM_SLOT_V7_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
                 CLEAN_ROOM_SLOT_V8_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
                 CLEAN_ROOM_SLOT_V9_1_PRODUCT_SELECTOR_DEV_TERMINAL_NON_PASS_SLOT_V2_3_RELOCKED
               ].include?(parent_truth.dig("p2_recovery_control", "status"))) &&
             versioned_slots,
             "structured decision active-parent resequencing precondition drift")
    end
    assert(prior["source_route_id"] == parent_envelope.dig("authority_basis", "source_route_id") &&
           consumed == parent_consumed,
           "structured decision prior consumed envelope does not equal activation parent")
    parent_ledger = array(parent_envelope["task_ledger"],
                          "structured decision activation-parent Task ledger")
    parent_ledger_bytes = JSON.generate(recursively_sorted(parent_ledger)).b
    assert(ledger_count == parent_ledger.length && ledger_count == consumed["engineering_tasks"] &&
           ledger_length == parent_ledger_bytes.bytesize &&
           ledger_sha == sha256(parent_ledger_bytes),
           "structured decision prior Task ledger identity does not equal activation parent")
    [prior, consumed, parent_limits]
  end

  def source_founder_packet_v4_profile_claims(packet_bytes, expected_authorization_token, label)
    text = packet_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(text.valid_encoding?, "#{label} must be valid UTF-8")
    authorization_token = one_packet_match(
      text,
      /^authorization_token=([A-Z0-9_]+)$/,
      "#{label} authorization_token declaration"
    )
    assert(authorization_token == expected_authorization_token,
           "#{label} authorization token does not match the structured decision")
    task_sections = text.scan(
      /^[0-9]+\. Task ([0-9]+)强制语义\s*\n(.*?)(?=^[0-9]+\. |\z)/m
    )
    provider_sections = task_sections.select do |_slot, body|
      body.scan(/^- endpoint:\s*$/).length == 1
    end
    assert(provider_sections.length == 1,
           "#{label} must contain exactly one Provider profile Task section")
    task_slot, profile_text = provider_sections.first
    endpoint = one_packet_match(
      profile_text,
      /^- endpoint:\s*\n  ([^\r\n]+)$/,
      "#{label} endpoint declaration"
    )
    model = one_packet_match(
      profile_text,
      /^- model:\s*\n  ([^\r\n]+)$/,
      "#{label} model declaration"
    )
    diagnostic_requests = one_packet_match(
      profile_text,
      /^- diagnostic Provider requests maximum: ([0-9]+)$/,
      "#{label} diagnostic Provider request ceiling"
    )
    formal_requests = one_packet_match(
      profile_text,
      /^- formal Provider requests: exactly ([0-9]+)$/,
      "#{label} formal Provider request count"
    )
    provider_requests = one_packet_match(
      profile_text,
      /^- total Provider requests maximum: ([0-9]+)$/,
      "#{label} total Provider request ceiling"
    )
    automatic_retries = one_packet_match(
      profile_text,
      /^- automatic retries: ([0-9]+)$/,
      "#{label} automatic retry ceiling"
    )
    monetary = one_packet_match(
      profile_text,
      /^- monetary exposure maximum: ([A-Z]{3}) ([0-9]+(?:\.[0-9]+)?)$/,
      "#{label} monetary exposure ceiling"
    )
    one_packet_match(
      profile_text,
      /^- Secret仅允许operator-owned no-echo读取一次；$/,
      "#{label} operator-owned no-echo Secret declaration"
    )
    task_slot_number = Integer(task_slot, 10)
    assert(task_slot_number.positive?, "#{label} Provider profile Task slot must be positive")
    {
      "endpoint" => endpoint,
      "model" => model,
      "task_slot" => task_slot_number,
      "diagnostic_requests_max" => Integer(diagnostic_requests, 10),
      "formal_requests_exact" => Integer(formal_requests, 10),
      "provider_requests_max" => Integer(provider_requests, 10),
      "automatic_retry_max" => Integer(automatic_retries, 10),
      "currency" => monetary[0],
      "max_spend" => Float(monetary[1]),
      "secret_entry_sessions" => 1
    }
  rescue ArgumentError
    fail!("#{label} contains an invalid numeric profile declaration")
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
    schema_version = string(
      decision["schema_version"],
      "structured Founder route decision.schema_version"
    )
    assert(%w[1.0 1.1 1.2 1.3 1.4].include?(schema_version),
           "structured Founder route decision schema_version must equal 1.0, 1.1, 1.2, 1.3 or 1.4")
    root_keys = %w[
      activation_parent authorization_token automatic_entry claim_boundary envelope
      external_effects goal_identity ordered_tasks phase record_type route_id
      schema_version source_founder_packet_identity
    ]
    root_keys << "automatic_entries" if TASK_EFFECT_DECISION_VERSIONS.include?(schema_version) ||
                                         CUMULATIVE_CAPACITY_DECISION_VERSIONS.include?(schema_version)
    root_keys.concat(%w[exact_reserved_trigger new_task_ids prior_consumed_envelope]) if
      SINGLE_TASK_EXPANSION_DECISION_VERSIONS.include?(schema_version)
    root_keys.concat(%w[capacity_slots exact_reserved_trigger prior_consumed_envelope recovery_plan_identity]) if
      CUMULATIVE_CAPACITY_DECISION_VERSIONS.include?(schema_version)
    exact_keys(
      decision,
      root_keys,
      "structured Founder route decision"
    )
    assert(decision["record_type"] == "founder_phase_route_decision",
           "structured Founder route decision record_type is unsupported")
    if SINGLE_TASK_EXPANSION_DECISION_VERSIONS.include?(schema_version) ||
       CUMULATIVE_CAPACITY_DECISION_VERSIONS.include?(schema_version)
      assert(decision["exact_reserved_trigger"] ==
             "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE",
             "structured Founder route decision v1.2 exact reserved trigger drift")
    end

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
    if %w[1.3 1.4].include?(schema_version)
      token_match = /\AAUTHORIZE_(P[12]_[A-Z0-9]+(?:_[A-Z0-9]+)*)_V([1-9][0-9]*)\z/.match(
        authorization_token
      )
      assert(token_match,
             "structured Founder route decision v1.3+ authorization token has invalid exact form")
      token_base = token_match[1]
      assert(!token_base.end_with?("_ROUTE"),
             "structured Founder route decision v1.3+ authorization token already contains a route suffix")
      expected_route_id = "#{token_base}_ROUTE_V#{token_match[2]}"
      assert(route_id == expected_route_id,
             "structured Founder route decision v1.3+ authorization token does not bijectively bind route_id")
      inverse_token = "AUTHORIZE_#{route_id.sub(/_ROUTE_V([1-9][0-9]*)\z/, '_V\\1')}"
      assert(inverse_token == authorization_token,
             "structured Founder route decision v1.3+ route_id does not invert to the exact authorization token")
    else
      assert(authorization_token == "AUTHORIZE_#{route_id}",
             "structured Founder route decision authorization token does not match route_id")
    end

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
    assert(integer(source_packet["byte_length"],
                   "structured Founder source packet byte_length").positive?,
           "structured Founder source packet byte_length must be positive")
    source_packet_bytes = if schema_version == "1.4"
                            assert(root, "v1.4 Founder source packet requires a repository root")
                            source_full = repo_path(root, source_path,
                                                    "structured Founder source packet path")
                            validate_identity(source_full, source_packet, "Founder source packet")
                          else
                            assert(Pathname.new(source_path).absolute?,
                                   "structured Founder source packet path must be absolute")
                            validate_identity(source_path, source_packet, "Founder source packet")
                          end
    if schema_version == "1.3"
      source_founder_packet_v1_3_claims(source_packet_bytes, decision, root)
    elsif schema_version == "1.4"
      source_founder_packet_v1_4_claims(source_packet_bytes, decision, root)
    end

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

    if schema_version == "1.4"
      assert(phase == "P2", "structured Founder route decision v1.4 is restricted to P2 recovery")
      assert(array(decision["ordered_tasks"],
                   "structured Founder route decision.ordered_tasks").empty?,
             "structured Founder route decision v1.4 may not preallocate Task ids")
      assert(decision["automatic_entry"].nil?,
             "structured Founder route decision v1.4 automatic_entry must be null")
      automatic_entries = array(decision["automatic_entries"],
                                "structured Founder route decision.automatic_entries")
      assert(automatic_entries.empty?,
             "structured Founder route decision v1.4 prohibits automatic successor links")

      recovery_plan = exact_keys(
        decision["recovery_plan_identity"],
        %w[byte_length path sha256],
        "structured Founder route decision.recovery_plan_identity"
      )
      assert(recovery_plan["path"] == "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml" &&
             integer(recovery_plan["byte_length"], "recovery plan byte_length").positive? &&
             SHA256_RE.match?(string(recovery_plan["sha256"], "recovery plan sha256")),
             "structured Founder route decision recovery plan identity is invalid")
      recovery_plan_bytes = git(root, "show", "#{parent['commit']}:#{recovery_plan['path']}").first.b
      assert(recovery_plan_bytes.bytesize == recovery_plan["byte_length"] &&
             sha256(recovery_plan_bytes) == recovery_plan["sha256"],
             "structured Founder route decision recovery plan does not equal activation parent")

      prior_consumed_envelope, prior_consumed, =
        validate_v1_4_prior_consumed_envelope(root, decision, parent, phase)
      product_selector_recovery = %w[
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_RECOVERY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V1
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V2
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V3
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V4
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE_V5
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE_V6
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V7
        AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE_V8
      ].include?(authorization_token)
      slot_generations = []
      slots = array(decision["capacity_slots"],
                    "structured Founder route decision.capacity_slots").map.with_index do |value, index|
        slot = exact_keys(
          value,
          %w[
            calendar_days capacity_slot_id engineering_hours max_candidates
            max_implementation_iterations max_same_task_repairs milestone_id
            product_mutation_allowed slot task_id unlock_requirement
          ],
          "structured Founder route decision.capacity_slots[#{index}]"
        )
        slot_match = /\AP2_RECOVERY_CAPACITY_SLOT_(?:(V[1-9][0-9]*)_)?([1-9][0-9]*)\z/.match(
          slot["capacity_slot_id"].to_s
        )
        slot_generations << slot_match&.[](1)
        expected_capacity_slot_id = if authorization_token ==
                                       "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_RECOVERY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V1"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V3_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    elsif authorization_token ==
                                          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V2"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V4_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    elsif authorization_token ==
                                          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V3"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V5_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    elsif authorization_token ==
                                          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V4"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V6_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    elsif authorization_token ==
                                          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE_V5"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V7_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    elsif authorization_token ==
                                          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE_V6"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V8_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    elsif authorization_token ==
                                          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V7"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V9_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    elsif authorization_token ==
                                          "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE_V8"
                                      %w[P2_RECOVERY_CAPACITY_SLOT_V10_1 P2_RECOVERY_CAPACITY_SLOT_V2_3][index]
                                    end
        assert(slot_match &&
               (product_selector_recovery ? slot["capacity_slot_id"] == expected_capacity_slot_id :
                 Integer(slot_match[2], 10) == index + 1) &&
               slot["slot"] == index + 1 &&
               slot["task_id"].nil?,
               "structured Founder route decision capacity slot identity drift")
        assert(slot["engineering_hours"].is_a?(Integer) && slot["engineering_hours"].positive? &&
               slot["calendar_days"].is_a?(Integer) && slot["calendar_days"].positive? &&
               slot["max_candidates"] == 2 && slot["max_implementation_iterations"] == 2 &&
               slot["max_same_task_repairs"] == 1,
               "structured Founder route decision capacity slot budget drift")
        slot
      end
      assert(product_selector_recovery || slot_generations.uniq.length == 1,
             "structured Founder route decision capacity slot generation drift")
      expected_slots = if product_selector_recovery
                         [
                           ["P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED", "P2_RECOVERY_BASELINE_ACCEPTED", true],
                           ["P2_RECOVERY_FORMAL_HELD_MATRIX_COMPLETE", "P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED", false]
                         ]
                       else
                         [
                           ["P2_RECOVERY_BASELINE_ACCEPTED", "BENCHMARK_SOURCE_PACK_ADMISSION_ACCEPTED", false],
                           ["P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED", "P2_RECOVERY_BASELINE_ACCEPTED", true],
                           ["P2_RECOVERY_FORMAL_HELD_MATRIX_COMPLETE", "P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED", false]
                         ]
                       end
      assert(slots.length == expected_slots.length && slots.each_with_index.all? do |slot, index|
        [slot["milestone_id"], slot["unlock_requirement"], slot["product_mutation_allowed"]] ==
          expected_slots[index]
      end, "structured Founder route decision recovery milestone ordering drift")
      assert(envelope["max_same_task_repairs_per_task"] == 1 &&
             envelope["max_engineering_tasks"] == prior_consumed["engineering_tasks"] + slots.length &&
             envelope["max_engineering_hours"] == prior_consumed["engineering_hours"] + slots.sum { |slot| slot["engineering_hours"] } &&
             envelope["max_calendar_days"] == prior_consumed["calendar_days"] + slots.sum { |slot| slot["calendar_days"] },
             "structured Founder route decision v1.4 cumulative envelope does not equal prior plus capacity slots")
      assert(external_effects == FALSE_EXTERNAL_EFFECTS,
             "structured Founder route decision v1.4 may not authorize external effects")

      return {
        "structured_decision" => true,
        "structured_decision_version" => schema_version,
        "authorization_token" => authorization_token,
        "route_id" => route_id,
        "phase" => phase,
        "activation_parent_commit" => parent["commit"],
        "activation_parent_tree" => parent["tree"],
        "max_engineering_tasks" => envelope["max_engineering_tasks"],
        "max_engineering_hours" => envelope["max_engineering_hours"],
        "max_calendar_days" => envelope["max_calendar_days"],
        "max_same_task_repairs" => 1,
        "max_contract_corrections_per_task" => 0,
        "first_task_id" => nil,
        "task_ids" => [],
        "task_budgets" => [],
        "capacity_slots" => slots,
        "automatic_entry" => nil,
        "automatic_entries" => automatic_entries,
        "new_task_ids" => [],
        "prior_consumed_envelope" => prior_consumed_envelope,
        "recovery_plan_identity" => recovery_plan,
        "task_effects" => {},
        "claim_boundary" => claim_boundary,
        "source_founder_packet_identity" => source_packet,
        "goal_identity" => goal_identity,
        "founder_reserved_profile" => nil,
        "founder_reserved_profiles" => [],
        "external_effects" => external_effects
      }
    end

    task_values = array(decision["ordered_tasks"],
                        "structured Founder route decision.ordered_tasks")
    if SINGLE_TASK_EXPANSION_DECISION_VERSIONS.include?(schema_version)
      assert(task_values.length == 1,
             "structured Founder route decision v1.2 requires exactly one newly authorized Task")
    else
      assert(task_values.length >= 2,
             "structured Founder route decision requires at least two ordered Tasks for automatic entry")
      assert(task_values.length == envelope["max_engineering_tasks"],
             "structured Founder route decision Task count does not equal route envelope")
    end
    task_budgets = task_values.map.with_index do |value, index|
      task_keys = %w[
        calendar_days engineering_hours max_candidates max_implementation_iterations
        max_same_task_repairs task_id task_slot
      ]
      task_keys.concat(%w[external_effects founder_reserved_profile]) if
        TASK_EFFECT_DECISION_VERSIONS.include?(schema_version)
      task = exact_keys(
        value,
        task_keys,
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
      assert(task_repairs <= max_repairs,
             "structured decision Task repair budget exceeds route envelope maximum")
      assert(task["max_implementation_iterations"] == task_repairs + 1,
             "structured decision Task implementation iterations must equal initial plus repairs")
      assert(task["max_candidates"] == envelope["max_active_candidates"],
             "structured decision Task candidate budget does not equal route envelope")
      if TASK_EFFECT_DECISION_VERSIONS.include?(schema_version)
        task_effects = exact_keys(
          task["external_effects"],
          EXTERNAL_EFFECT_KEYS,
          "structured Founder route decision.ordered_tasks[#{index}].external_effects"
        )
        task_effects.each do |key, effect|
          assert(effect == true || effect == false,
                 "structured Founder route decision Task #{index + 1} external_effects.#{key} must be boolean")
        end
        task_profile = task["founder_reserved_profile"]
        if task_effects == LOCAL_GATEWAY_EXTERNAL_EFFECTS
          assert(task_profile.is_a?(Hash),
                 "structured Founder route decision Provider Task requires an exact Founder-reserved profile")
          validated_profile = validate_founder_reserved_profile_v4(
            task_profile,
            route_id,
            task_id,
            "structured Founder route decision.ordered_tasks[#{index}].founder_reserved_profile"
          )
          assert(
            validated_profile["decision_basis"] ==
              "FOUNDER_PACKET_SHA256:#{source_packet['sha256']}",
            "structured Founder route decision Provider profile does not bind the exact source packet"
          )
          assert(validated_profile["external_effects"] == task_effects,
                 "structured Founder route decision Provider profile effects mismatch")
        else
          assert(task_effects == FALSE_EXTERNAL_EFFECTS,
                 "structured Founder route decision Task effects must be offline or exact local-gateway effects")
          assert(task_profile.nil?,
                 "structured Founder route decision offline Task must not carry a Founder-reserved profile")
        end
      end
      task
    end
    task_ids = task_budgets.map { |task| task["task_id"] }
    assert(task_ids.uniq.length == task_ids.length,
           "structured Founder route decision Task ids must be unique")
    assert(task_budgets.map { |task| task["max_same_task_repairs"] }.max == max_repairs,
           "structured decision route repair ceiling must equal the maximum Task repair budget")

    prior_consumed_envelope = nil
    new_task_ids = task_ids
    if SINGLE_TASK_EXPANSION_DECISION_VERSIONS.include?(schema_version)
      prior_consumed_envelope = exact_keys(
        decision["prior_consumed_envelope"],
        %w[
          consumed source_route_id task_ledger_canonical_byte_length
          task_ledger_canonical_sha256 task_ledger_canonicalization task_ledger_entry_count
        ],
        "structured Founder route decision.prior_consumed_envelope"
      )
      prior_consumed = exact_keys(
        prior_consumed_envelope["consumed"],
        %w[calendar_days engineering_hours engineering_tasks],
        "structured Founder route decision.prior_consumed_envelope.consumed"
      )
      prior_consumed.each do |key, value|
        assert(integer(value, "structured decision prior consumed #{key}").positive?,
               "structured decision prior consumed #{key} must be positive")
      end
      source_route_id = string(
        prior_consumed_envelope["source_route_id"],
        "structured decision prior consumed source_route_id"
      )
      assert(ROUTE_ID_RE.match?(source_route_id),
             "structured decision prior consumed source_route_id has invalid form")
      assert(source_route_id.start_with?("#{phase}_"),
             "structured decision prior consumed source_route_id phase prefix mismatch")
      assert(prior_consumed_envelope["task_ledger_canonicalization"] ==
             "RECURSIVE_KEY_SORT_COMPACT_JSON_UTF8",
             "structured decision prior Task ledger canonicalization mismatch")
      ledger_count = integer(
        prior_consumed_envelope["task_ledger_entry_count"],
        "structured decision prior Task ledger entry count"
      )
      ledger_length = integer(
        prior_consumed_envelope["task_ledger_canonical_byte_length"],
        "structured decision prior Task ledger canonical byte length"
      )
      ledger_sha = string(
        prior_consumed_envelope["task_ledger_canonical_sha256"],
        "structured decision prior Task ledger canonical SHA-256"
      )
      assert(ledger_count.positive? && ledger_length.positive? && SHA256_RE.match?(ledger_sha),
             "structured decision prior Task ledger identity is invalid")
      assert(root,
             "structured Founder route decision v1.2 requires a repository root for prior accounting validation")
      parent_truth_bytes = git(
        root,
        "show",
        "#{parent['commit']}:docs/aios/truth/project_state.yaml"
      ).first
      parent_truth = parse_yaml(parent_truth_bytes, "structured decision activation-parent Truth")
      parent_envelope = hash(
        parent_truth["phase_execution_envelope"],
        "structured decision activation-parent phase_execution_envelope"
      )
      assert(parent_envelope["phase"] == phase && parent_envelope["status"] == "EXHAUSTED",
             "structured decision prior accounting requires an exhausted same-Phase parent envelope")
      parent_limits = exact_keys(
        parent_envelope["limits"],
        %w[
          active_candidates active_tasks calendar_days engineering_hours engineering_tasks
          task_branches task_worktrees
        ],
        "structured decision activation-parent envelope limits"
      )
      parent_consumed = exact_keys(
        parent_envelope["consumed"],
        %w[calendar_days engineering_hours engineering_tasks],
        "structured decision activation-parent envelope consumed"
      )
      parent_remaining = exact_keys(
        parent_envelope["remaining"],
        %w[calendar_days engineering_hours engineering_tasks],
        "structured decision activation-parent envelope remaining"
      )
      assert(parent_envelope["reserved"].nil? && parent_consumed == parent_limits.slice(
        "calendar_days", "engineering_hours", "engineering_tasks"
      ) && parent_remaining.values.all?(&:zero?),
             "structured decision activation-parent envelope is not exactly exhausted")
      parent_source_route_id = string(
        hash(parent_envelope["authority_basis"],
             "structured decision activation-parent authority_basis")["source_route_id"],
        "structured decision activation-parent source_route_id"
      )
      assert(source_route_id == parent_source_route_id,
             "structured decision prior consumed source_route_id does not equal activation parent")
      assert(prior_consumed == parent_consumed,
             "structured decision prior consumed envelope does not equal activation parent")
      parent_ledger = array(
        parent_envelope["task_ledger"],
        "structured decision activation-parent Task ledger"
      )
      parent_ledger_bytes = JSON.generate(recursively_sorted(parent_ledger)).b
      assert(ledger_count == parent_ledger.length &&
             ledger_count == parent_consumed["engineering_tasks"],
             "structured decision prior Task ledger count does not equal activation parent")
      assert(ledger_length == parent_ledger_bytes.bytesize,
             "structured decision prior Task ledger byte length does not equal activation parent")
      assert(ledger_sha == sha256(parent_ledger_bytes),
             "structured decision prior Task ledger SHA-256 does not equal activation parent")

      new_task_ids = array(
        decision["new_task_ids"],
        "structured Founder route decision.new_task_ids"
      )
      assert(new_task_ids == task_ids && new_task_ids.length == 1,
             "structured Founder route decision new_task_ids must equal the sole ordered Task")
      assert(envelope["max_engineering_tasks"] ==
             prior_consumed["engineering_tasks"] + task_budgets.length,
             "structured Founder route decision cumulative Task envelope does not equal prior plus new")
      assert(envelope["max_engineering_hours"] ==
             prior_consumed["engineering_hours"] +
               task_budgets.sum { |task| task["engineering_hours"] },
             "structured Founder route decision cumulative engineering hours do not equal prior plus new")
      assert(envelope["max_calendar_days"] ==
             prior_consumed["calendar_days"] + task_budgets.sum { |task| task["calendar_days"] },
             "structured Founder route decision cumulative calendar days do not equal prior plus new")
    else
      assert(task_budgets.sum { |task| task["engineering_hours"] } == envelope["max_engineering_hours"],
             "structured Founder route decision Task engineering budgets do not equal route envelope")
      assert(task_budgets.sum { |task| task["calendar_days"] } == envelope["max_calendar_days"],
             "structured Founder route decision Task calendar budgets do not equal route envelope")
    end

    automatic_entry = if SINGLE_TASK_EXPANSION_DECISION_VERSIONS.include?(schema_version)
                        assert(decision["automatic_entry"].nil?,
                               "structured Founder route decision v1.2 automatic_entry must be null")
                        nil
                      else
                        entry = exact_keys(
                          decision["automatic_entry"],
                          %w[after_task_id next_task_id requires_task_gate_pass],
                          "structured Founder route decision.automatic_entry"
                        )
                        assert(entry["after_task_id"] == task_ids[0] &&
                               entry["next_task_id"] == task_ids[1],
                               "structured Founder route decision automatic entry must bind ordered Task 1 to Task 2")
                        assert(entry["requires_task_gate_pass"] == true,
                               "structured Founder route decision automatic entry requires Task Gate PASS")
                        entry
                      end
    automatic_entries = if SINGLE_TASK_EXPANSION_DECISION_VERSIONS.include?(schema_version)
                          entries = array(
                            decision["automatic_entries"],
                            "structured Founder route decision.automatic_entries"
                          )
                          assert(entries.empty?,
                                 "structured Founder route decision v1.2 prohibits automatic successor links")
                          entries
                        elsif schema_version == "1.1"
                          entries = array(
                            decision["automatic_entries"],
                            "structured Founder route decision.automatic_entries"
                          ).map.with_index do |value, index|
                            entry = exact_keys(
                              value,
                              %w[after_task_id next_task_id requires_task_gate_pass],
                              "structured Founder route decision.automatic_entries[#{index}]"
                            )
                            assert(entry["after_task_id"] == task_ids[index] &&
                                   entry["next_task_id"] == task_ids[index + 1],
                                   "structured Founder route decision automatic entries must bind every adjacent Task")
                            assert(entry["requires_task_gate_pass"] == true,
                                   "structured Founder route decision automatic entry requires Task Gate PASS")
                            entry
                          end
                          assert(entries.length == task_ids.length - 1,
                                 "structured Founder route decision automatic entry count must equal Task count minus one")
                          assert(entries.first == automatic_entry,
                                 "structured Founder route decision first automatic entry projection mismatch")
                          entries
                        else
                          [automatic_entry]
                        end
    task_effects = if TASK_EFFECT_DECISION_VERSIONS.include?(schema_version)
                     task_budgets.to_h do |task|
                       [task["task_id"], task.fetch("external_effects")]
                     end
                   else
                     task_ids.to_h { |task_id| [task_id, external_effects] }
                   end
    founder_reserved_profiles = if TASK_EFFECT_DECISION_VERSIONS.include?(schema_version)
                                  task_budgets.map do |task|
                                    task["founder_reserved_profile"]
                                  end.compact
                                else
                                  []
                                end
    if TASK_EFFECT_DECISION_VERSIONS.include?(schema_version) && !founder_reserved_profiles.empty?
      assert(founder_reserved_profiles.length == 1,
             "structured Founder route decision supports exactly one source-bound Provider profile")
      source_profile = source_founder_packet_v4_profile_claims(
        source_packet_bytes,
        authorization_token,
        "Founder source packet"
      )
      profile = founder_reserved_profiles.first
      source_profile_task = task_budgets.fetch(source_profile["task_slot"] - 1) do
        fail!("Founder source packet Provider profile Task slot is outside the structured Task set")
      end
      assert(profile["task_id"] == source_profile_task["task_id"],
             "structured Founder Provider profile Task does not equal the source Founder packet Task slot")
      transport = profile.fetch("transport")
      endpoint = "#{transport.fetch('scheme')}://#{transport.fetch('host')}:#{transport.fetch('port')}" \
                 "#{transport.fetch('completion_path')}"
      assert(endpoint == source_profile["endpoint"],
             "structured Founder Provider endpoint does not equal the source Founder packet")
      assert(profile.dig("model", "requested_model") == source_profile["model"],
             "structured Founder Provider model does not equal the source Founder packet")
      expected_calls = {
        "diagnostic_requests_max" => source_profile["diagnostic_requests_max"],
        "formal_requests_exact" => source_profile["formal_requests_exact"],
        "provider_requests_max" => source_profile["provider_requests_max"],
        "automatic_retry_max" => source_profile["automatic_retry_max"]
      }
      assert(profile["call_limits"] == expected_calls,
             "structured Founder Provider request limits do not equal the source Founder packet")
      assert(profile.dig("monetary_limits", "currency") == source_profile["currency"] &&
             profile.dig("monetary_limits", "max_spend").to_f == source_profile["max_spend"],
             "structured Founder Provider monetary limit does not equal the source Founder packet")
      assert(profile.dig("secret", "entry_sessions") == source_profile["secret_entry_sessions"],
             "structured Founder Provider Secret entry count does not equal the source Founder packet")
    end
    if TASK_EFFECT_DECISION_VERSIONS.include?(schema_version)
      projected_route_effects = EXTERNAL_EFFECT_KEYS.to_h do |key|
        [key, task_effects.values.any? { |effects| effects[key] }]
      end
      assert(projected_route_effects == external_effects,
             "structured Founder route external effects must equal the union of Task effect ceilings")
    end

    {
      "structured_decision" => true,
      "structured_decision_version" => schema_version,
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
      "automatic_entries" => automatic_entries,
      "new_task_ids" => new_task_ids,
      "prior_consumed_envelope" => prior_consumed_envelope,
      "task_effects" => task_effects,
      "claim_boundary" => claim_boundary,
      "source_founder_packet_identity" => source_packet,
      "goal_identity" => goal_identity,
      "founder_reserved_profile" =>
        founder_reserved_profiles.find { |profile| profile["task_id"] == task_ids.first },
      "founder_reserved_profiles" => founder_reserved_profiles,
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
      if TASK_EFFECT_DECISION_VERSIONS.include?(claims["structured_decision_version"])
        assert(route["automatic_entries"] == claims["automatic_entries"],
               "Truth automatic entries do not match structured Founder decision")
      end
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
    if TASK_EFFECT_DECISION_VERSIONS.include?(claims["structured_decision_version"])
      expected_profiles = claims.fetch("founder_reserved_profiles")
      route_profiles = array(
        route.fetch("founder_reserved_profiles", []),
        "current_phase_route.founder_reserved_profiles"
      )
      assert(route_profiles.length == expected_profiles.length,
             "Truth Founder profile set does not equal the exact structured decision")
      validated_route_profiles = route_profiles.map.with_index do |profile, index|
        profile_task_id = string(
          hash(profile, "current_phase_route.founder_reserved_profiles[#{index}]")["task_id"],
          "current_phase_route.founder_reserved_profiles[#{index}].task_id"
        )
        assert(claims["task_ids"].include?(profile_task_id),
               "Truth Founder profile Task is outside the structured decision")
        validate_founder_reserved_profile(
          profile,
          route_id,
          profile_task_id,
          "current_phase_route.founder_reserved_profiles[#{index}]"
        )
      end
      validate_exact_profile_binding(
        validated_route_profiles,
        expected_profiles,
        "Truth Founder profile set does not equal the exact structured decision"
      )
      profile_task_ids = validated_route_profiles.map { |profile| profile["task_id"] }
      assert(profile_task_ids.uniq.length == profile_task_ids.length,
             "Truth Founder profile Task set contains duplicates")
      expected_primary = expected_profiles.find do |profile|
        profile["task_id"] == claims["first_task_id"]
      end
      if expected_primary
        route_primary = validate_founder_reserved_profile(
          route["founder_reserved_profile"],
          route_id,
          claims["first_task_id"],
          "current_phase_route.founder_reserved_profile"
        )
        validate_exact_profile_binding(
          route_primary,
          expected_primary,
          "Truth primary Founder profile does not equal the exact structured decision"
        )
      else
        assert(!route.key?("founder_reserved_profile") || route["founder_reserved_profile"].nil?,
               "structured offline first Task must not invent a primary Founder profile")
      end
      expected_effects = claims.fetch("external_effects")
    elsif claims["founder_reserved_profile"]
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
          if TASK_EFFECT_DECISION_VERSIONS.include?(claims["structured_decision_version"])
            assert(item["external_effects"] == packet_budget["external_effects"],
                   "current_phase_route.task_plan external effects do not equal the structured Founder decision")
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
    route_complete = route["status"] == "PHASE_GATE_READY"
    assert(initial_ready || between_tasks || route_complete,
           "Task NONE requires a ready, active or Phase-Gate-ready route")
    if initial_ready
      phase_status_key = "#{project['current_phase'].downcase}_execution_status"
      assert(project["phase_execution_status"] == "AUTHORIZED_READY" &&
             project[phase_status_key] == "AUTHORIZED_READY",
             "initial Task NONE requires project AUTHORIZED_READY")
      assert(first_task["status"] == "ELIGIBLE_NOT_ACTIVATED",
             "initial Task NONE requires an eligible, non-activated first Task")
      validate_structured_task_state_vector(
        route,
        first_task,
        claims,
        target_task_id: first_task["task_id"],
        target_state: "ELIGIBLE_NOT_ACTIVATED"
      )
    elsif between_tasks
      phase_status_key = "#{project['current_phase'].downcase}_execution_status"
      assert(%w[ACTIVE EXECUTING].include?(project["phase_execution_status"]) &&
             %w[ACTIVE EXECUTING].include?(project[phase_status_key]),
             "between-Task NONE requires active project execution")
      assert(first_task["status"] != "ACTIVE", "between-Task NONE cannot leave first Task active")
      eligible = array(route["task_plan"], "current_phase_route.task_plan").select do |item|
        item.is_a?(Hash) && item["status"] == "ELIGIBLE_NOT_ACTIVATED"
      end
      assert(eligible.length == 1,
             "between-Task NONE requires exactly one eligible next Task")
      validate_structured_task_state_vector(
        route,
        first_task,
        claims,
        target_task_id: eligible.first["task_id"],
        target_state: "ELIGIBLE_NOT_ACTIVATED"
      )
      validate_structured_predecessor_gate(
        root, truth, route, first_task, claims,
        eligible.first["task_id"],
        "READY"
      ) if claims["structured_decision"]
    else
      phase_status_key = "#{project['current_phase'].downcase}_execution_status"
      assert(project["phase_execution_status"] == "STOPPED_AT_FOUNDER_PHASE_GATE" &&
             project[phase_status_key] == "STOPPED_AT_FOUNDER_PHASE_GATE",
             "completed route requires project Founder Phase Gate status")
      assert(route["next_eligible_action"] == "FOUNDER_PHASE_GATE",
             "completed route next eligible action must be FOUNDER_PHASE_GATE")
      validate_structured_task_state_vector(
        route,
        first_task,
        claims,
        target_task_id: nil,
        target_state: "COMPLETE"
      )
      claims["task_ids"].each do |accepted_task_id|
        validate_accepted_gate_history(
          root,
          truth,
          route,
          accepted_task_id,
          "completed structured route accepted Task"
        )
      end
    end
    assert(!route.key?("active_task") || route["active_task"].nil?,
           "Task NONE route must not retain an active_task descriptor")
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
    expected_resource_state = if initial_ready
                                "NOT_CREATED_ROUTE_READY"
                              elsif route_complete
                                "NONE_PHASE_GATE_READY"
                              else
                                "NONE_PHASE_ACTIVE"
                              end
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
    expected_effects = if TASK_EFFECT_DECISION_VERSIONS.include?(claims["structured_decision_version"])
                         FALSE_EXTERNAL_EFFECTS
                       elsif claims["structured_decision"]
                         claims.fetch("external_effects")
                       else
                         FALSE_EXTERNAL_EFFECTS
                       end
    validate_external_effects(active["external_effects"], "active_work.external_effects", expected_effects)
    if route_complete
      assert(active["founder_decision_required"] == true,
             "completed route requires Founder Phase Gate decision")
      assert(active["escalation_reason"].nil?,
             "completed route escalation_reason must remain null")
      assert(active["user_action_required"] == "FOUNDER_PHASE_GATE_DECISION",
             "completed route user_action_required mismatch")
    else
      exact_false(active["founder_decision_required"], "active_work.founder_decision_required")
      assert(active["escalation_reason"].nil?, "Task NONE escalation_reason must be null")
      assert(active["user_action_required"] == "NONE", "Task NONE user_action_required must be NONE")
    end
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

  def phase_delegated_goal_identity(truth)
    goal = hash(truth["goal"], "goal")
    {
      "raw_sha256" => goal["observed_raw_body_sha256"],
      "raw_byte_length" => goal["observed_raw_body_byte_length"],
      "canonicalization" => goal["body_canonicalization"],
      "canonical_sha256" => goal["observed_body_sha256"],
      "canonical_byte_length" => goal["observed_body_byte_length"]
    }
  end

  def phase_delegated_binding(truth, route)
    envelope = hash(truth["phase_execution_envelope"], "phase_execution_envelope")
    authority_basis = hash(envelope["authority_basis"], "phase_execution_envelope.authority_basis")
    preceding_route_ref = string(
      route["preceding_terminal_route_ref"],
      "current_phase_route.preceding_terminal_route_ref"
    )
    preceding_route = hash(truth[preceding_route_ref], preceding_route_ref)
    preceding_task = if preceding_route["selected_task"].is_a?(Hash)
                       preceding_route["selected_task"]
                     else
                       array(preceding_route["task_plan"], "preceding terminal task_plan").find do |task|
                         task.is_a?(Hash) && task["status"] == preceding_route["status"]
                       end
                     end
    preceding_task = hash(preceding_task, "preceding terminal Task")
    assert(preceding_task["status"] == preceding_route["status"],
           "phase-delegated Task preceding terminal Task status drift")
    ledger = array(envelope["task_ledger"], "phase_execution_envelope.task_ledger")
    source_entry = ledger.find do |entry|
      entry.is_a?(Hash) && entry["task_id"] == preceding_task["task_id"] &&
        entry["status"] == preceding_task["status"]
    end
    assert(source_entry, "phase-delegated Task has no exact terminal source ledger entry")
    reservation = hash(envelope["reserved"], "phase_execution_envelope.reserved")
    reserved_snapshot = reservation.slice(
      "task_id", "route_id", "status", "capacity_source_task_id", "budget"
    )
    reserved_snapshot["status"] = "ELIGIBLE_NOT_ACTIVATED"
    {
      "policy" => route["policy"],
      "delegation_amendment" => authority_basis["delegation_amendment"],
      "source_decision" => authority_basis["source_decision"],
      "source_terminal_event" => {
        "task_id" => preceding_task["task_id"],
        "status" => preceding_task["status"],
        "outcome_receipt" => source_entry["outcome_receipt"]
      },
      "phase_envelope_snapshot" => {
        "limits" => envelope["limits"],
        "consumed" => envelope["consumed"],
        "reserved" => reserved_snapshot,
        "remaining" => envelope["remaining"]
      },
      "founder_packet_for_task" => nil
    }
  end

  def validate_phase_delegated_contract_policy_fields(contract)
    why_now = string(contract["why_now"], "phase-delegated Task Contract why_now")
    assert(!why_now.strip.empty?, "phase-delegated Task Contract why_now must not be blank")
    assert(contract["task_gate_owner"] == "MASTER_CEO_AGENT",
           "phase-delegated Task Contract task_gate_owner must equal MASTER_CEO_AGENT")
    assert(contract["founder_gate"] == "RESERVED_DECISIONS_ONLY",
           "phase-delegated Task Contract founder_gate must equal RESERVED_DECISIONS_ONLY")
    true
  end

  def validate_p2_073_preactivation_gate(contract)
    gate = exact_keys(
      contract["preactivation_gate"],
      %w[
        status exact_system_sandbox_exec sandbox_profile_order exact_java_major
        exact_bridge_rule required_bindings failure_lifecycle
      ],
      "P2-073 preactivation_gate"
    )
    assert(gate["status"] == "REQUIRED_BEFORE_ANY_WORKER_PRODUCT_SOURCE_WRITE" &&
           gate["exact_system_sandbox_exec"] == "/usr/bin/sandbox-exec" &&
           gate["sandbox_profile_order"] == ["(allow default)", "(deny network*)"] &&
           gate["exact_java_major"] == 17 &&
           gate["failure_lifecycle"] ==
             "TERMINATE_BEFORE_PRODUCT_EXECUTION_WITH_ZERO_PRODUCT_SOURCE_WRITES",
           "P2-073 preactivation lifecycle or sandbox identity drift")
    bridge_rule = string(gate["exact_bridge_rule"], "P2-073 exact_bridge_rule")
    assert(bridge_rule.include?("stdin payload") && bridge_rule.include?("EOF") &&
           bridge_rule.include?("stdout") && bridge_rule.include?("stderr") &&
           bridge_rule.include?("System.in") && bridge_rule.include?("System.out") &&
           bridge_rule.include?("System.err"),
           "P2-073 exact bridge stream lifecycle rule is incomplete")
    expected_bindings = [
      "exact /usr/bin/sandbox-exec identity and outer argv",
      "exact sandbox profile bytes and SHA-256",
      "exact cwd and closed environment",
      "exact JDK 17 java and javac identities",
      "exact bridge source, compiled class and classpath identities",
      "exact stdin payload, EOF event, stdout, stderr and exit status transcript",
      "exact write-root inventory proving all compiler and fixture writes stayed inside the Task worktree or Evidence root"
    ]
    assert(array(gate["required_bindings"], "P2-073 required_bindings") == expected_bindings,
           "P2-073 preactivation required binding set drift")
    gate
  end

  def validate_p2_074_preactivation_gate(contract)
    gate = exact_keys(
      contract["preactivation_gate"],
      %w[
        required_before_product_source_write exact_authority_roots_before_mkdir
        os_write_confinement_probe_required compiler_test_replay_negative_fresh_roots_required
        explicit_classpath_and_sourcepath_required annotation_processing_disabled_or_fully_bound
        exact_runtime_binary_identity_required complete_source_to_class_identity_required
        reviewer_manifest_direct_raw_leaf_binding_required product_path_static_and_runtime_binding_required
      ],
      "P2-074 preactivation_gate"
    )
    assert(gate.values.all? { |value| value == true },
           "P2-074 preactivation gate requirements must all be true")
    gate
  end

  def validate_p2_075_preactivation_gate(contract)
    gate = exact_keys(
      contract["preactivation_gate"],
      %w[
        required_before_product_source_write independent_architecture_freeze_required
        deterministic_query_intent_required package_type_member_entity_coverage_required
        normalized_path_first_tie_break_required product_owned_ranking_and_budget_selection_required
        exact_authority_roots_before_mkdir os_write_confinement_probe_required
        compiler_test_replay_negative_fresh_roots_required explicit_classpath_and_sourcepath_required
        annotation_processing_disabled_or_fully_bound exact_runtime_binary_identity_required
        complete_source_to_class_identity_required reviewer_manifest_direct_raw_leaf_binding_required
        product_path_static_and_runtime_binding_required
      ],
      "P2-075 preactivation_gate"
    )
    assert(gate.values.all? { |value| value == true },
           "P2-075 preactivation gate requirements must all be true")
    gate
  end

  def validate_p2_076_preactivation_gate(contract)
    gate = exact_keys(
      contract["preactivation_gate"],
      %w[
        required_before_product_source_write b1_seed_parity_freeze_required
        product_owned_static_java_graph_required package_type_member_import_reference_edges_required
        one_hop_only predeclared_candidate_parameter_set_limit
        normalized_path_first_tie_break_required top_k utf8_byte_budget
        task_specific_oracle_branches_forbidden post_result_tuning_forbidden held_reads_forbidden
        exact_authority_roots_before_mkdir os_write_confinement_probe_required
        compiler_test_replay_negative_fresh_roots_required explicit_classpath_and_sourcepath_required
        annotation_processing_disabled_or_fully_bound exact_runtime_binary_identity_required
        complete_source_to_class_identity_required reviewer_manifest_direct_raw_leaf_binding_required
        product_path_static_and_runtime_binding_required
      ],
      "P2-076 preactivation_gate"
    )
    boolean_keys = gate.keys - %w[predeclared_candidate_parameter_set_limit top_k utf8_byte_budget]
    assert(boolean_keys.all? { |key| gate[key] == true } &&
           gate["predeclared_candidate_parameter_set_limit"] == 2 &&
           gate["top_k"] == 10 && gate["utf8_byte_budget"] == 131_072,
           "P2-076 B1 graph-fusion preactivation gate drift")
    gate
  end

  def validate_p2_077_preactivation_gate(contract)
    gate = exact_keys(
      contract["preactivation_gate"],
      %w[
        required_before_product_source_write independent_semantic_architecture_freeze_required
        b1_seed_parity_freeze_required product_owned_deterministic_java_source_analysis_required
        package_type_member_ownership_resolution_required
        import_invocation_inheritance_reference_edges_required
        query_and_b1_seeded_forward_backward_bounded_impact_cones_required
        predeclared_candidate_parameter_set_limit normalized_path_first_tie_break_required
        top_k utf8_byte_budget dev_oracle_labels_forbidden task_specific_branches_forbidden
        post_result_tuning_forbidden held_reads_forbidden exact_authority_roots_before_mkdir
        os_write_confinement_probe_required compiler_test_replay_negative_fresh_roots_required
        explicit_classpath_and_sourcepath_required annotation_processing_disabled_or_fully_bound
        exact_runtime_binary_identity_required complete_source_to_class_identity_required
        reviewer_manifest_direct_raw_leaf_binding_required product_path_static_and_runtime_binding_required
      ],
      "P2-077 preactivation_gate"
    )
    numeric_keys = %w[predeclared_candidate_parameter_set_limit top_k utf8_byte_budget]
    boolean_keys = gate.keys - numeric_keys
    assert(boolean_keys.all? { |key| gate[key] == true } &&
           gate["predeclared_candidate_parameter_set_limit"] == 2 &&
           gate["top_k"] == 10 && gate["utf8_byte_budget"] == 131_072,
           "P2-077 semantic-symbol-impact-cone preactivation gate drift")
    gate
  end

  def validate_p2_078_preactivation_gate(contract)
    gate = exact_keys(
      contract["preactivation_gate"],
      %w[
        required_before_product_source_write
        independent_scan_time_compiler_attributed_architecture_freeze_required
        full_source_scan_path_only public_jdk17_compiler_api_only
        complete_normalized_java_compilation_units_required declaration_proven_ownership_required
        resolved_element_to_element_edges_required code_graph_persistence_service_required
        fresh_process_local_h2_in_memory_test_database_only
        existing_or_operational_datasource_unreachable_required
        real_code_qa_controller_retrieval_path_required
        dev_evaluator_same_production_selection_api_required
        query_time_chunk_compilation_or_reconstruction_forbidden benchmark_only_bridge_forbidden
        simple_name_broadcast_forbidden reference_sites_as_owners_forbidden
        unresolved_or_ambiguous_edges_forbidden b1_seed_parity_freeze_required
        predeclared_candidate_parameter_set_limit normalized_path_first_tie_break_required
        top_k utf8_byte_budget dev_oracle_labels_forbidden task_ids_as_inputs_forbidden
        task_specific_branches_forbidden post_result_tuning_forbidden held_reads_forbidden
        full_source_to_persisted_graph_identity_required graph_to_selected_chunk_traceability_required
        exact_authority_roots_before_mkdir af_inet_and_af_inet6_deny_network_probes_required
        os_write_confinement_probe_required compiler_test_replay_negative_fresh_roots_required
        explicit_classpath_and_sourcepath_required annotation_processing_disabled_or_fully_bound
        exact_runtime_binary_identity_required complete_source_to_class_identity_required
        per_replay_sandbox_and_write_inventories_required
        real_evaluator_bound_held_oracle_negatives_required
        reviewer_manifest_direct_raw_leaf_binding_required product_path_static_and_runtime_binding_required
      ],
      "P2-078 preactivation_gate"
    )
    numeric_keys = %w[predeclared_candidate_parameter_set_limit top_k utf8_byte_budget]
    boolean_keys = gate.keys - numeric_keys
    assert(boolean_keys.all? { |key| gate[key] == true } &&
           gate["predeclared_candidate_parameter_set_limit"] == 2 &&
           gate["top_k"] == 10 && gate["utf8_byte_budget"] == 131_072,
           "P2-078 JDK17 scan-time compiler-attributed persisted-graph preactivation gate drift")
    gate
  end

  def validate_p2_product_selector_protocol_contract_fields(authority, contract)
    task_id = contract["task_id"]
    label, expected_canonical = case task_id
                                when "AIOS-P2-074_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_DEV"
                                  ["P2-074", {
                                    "commit" => "8988b239e164f1897b95678e81f6465b2e41cbe7",
                                    "tree" => "ff5fb7c59de62af2146ba12a93e01303b33673af"
                                  }]
                                when "AIOS-P2-075_CLEAN_ROOM_QUERY_ENTITY_COVERAGE_PRODUCT_SELECTOR_ARCHITECTURE_PIVOT_DEV"
                                  ["P2-075", {
                                    "commit" => "3d3b94e73b293597bf89eb210897737903d968a0",
                                    "tree" => "0693d9ab4e2b1c5aa90b16e732669dd67e121f49"
                                  }]
                                when "AIOS-P2-076_CLEAN_ROOM_B1_ANCHORED_GRAPH_FUSION_PRODUCT_SELECTOR_DEV"
                                  ["P2-076", {
                                    "commit" => "09da8ea278db587520e0a835deb474415b14ab1c",
                                    "tree" => "4955c0b59e310db17c30c75721e88051f296df1e"
                                  }]
                                when "AIOS-P2-077_CLEAN_ROOM_SEMANTIC_SYMBOL_IMPACT_CONE_PRODUCT_SELECTOR_DEV"
                                  ["P2-077", {
                                    "commit" => "8ce9f963e3bd366efe35fa1d91de7023445d380f",
                                    "tree" => "3fc27c5d547c3d1e61932ac4749ddb0b328ff4b0"
                                  }]
                                when "AIOS-P2-078_CLEAN_ROOM_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_PRODUCT_SELECTOR_DEV"
                                  ["P2-078", {
                                    "commit" => "14fb98412d4a796cfd0fda92345e43ab7df3bc2d",
                                    "tree" => "d861467de31c91deebf4b8adc1ff36945ed73c3a"
                                  }]
                                else
                                  fail!("unsupported Product Selector protocol contract")
                                end
    baseline = exact_keys(
      contract["baseline_ref"],
      %w[
        artifact_id baseline_id macro_precision macro_recall macro_reciprocal_rank
        top_k utf8_byte_budget
      ],
      "#{label} baseline_ref"
    )
    assert(baseline == {
      "artifact_id" => "P2_RECOVERY_BASELINE_ACCEPTED",
      "baseline_id" => "B1_DETERMINISTIC_BM25_FILE_RETRIEVAL",
      "macro_precision" => 0.15595238095238093,
      "macro_recall" => 0.8958333333333334,
      "macro_reciprocal_rank" => 0.8229166666666666,
      "top_k" => 10,
      "utf8_byte_budget" => 131_072
    }, "#{label} accepted baseline metric identity drift")

    dependencies = array(contract["dependencies"], "#{label} dependencies")
    assert(dependencies.length == 2, "#{label} requires exact canonical and accepted baseline dependencies")
    canonical = exact_keys(dependencies.fetch(0), %w[kind identity], "#{label} canonical dependency")
    canonical_identity = exact_keys(
      canonical["identity"], %w[commit tree], "#{label} canonical source identity"
    )
    assert(canonical["kind"] == "CANONICAL_SOURCE" && canonical_identity == expected_canonical,
           "#{label} canonical source dependency drift")

    accepted = exact_keys(
      dependencies.fetch(1), %w[kind identity], "#{label} accepted baseline dependency"
    )
    identity = exact_keys(
      accepted["identity"],
      %w[
        artifact_id root source_pack benchmark_manifest dev_task_cards b1_results
        dev_held_non_overlap_proof
      ],
      "#{label} accepted baseline identity"
    )
    assert(accepted["kind"] == "ACCEPTED_BASELINE_ARTIFACT" &&
           identity["artifact_id"] == "P2_RECOVERY_BASELINE_ACCEPTED",
           "#{label} accepted baseline artifact kind drift")
    root = string(identity["root"], "#{label} accepted baseline root")
    stat = File.lstat(root)
    assert(File.expand_path(root) == root && stat.directory? && !stat.symlink? &&
           File.realpath(root) == root,
           "#{label} accepted baseline root must be a canonical non-symlink directory")
    %w[
      source_pack benchmark_manifest dev_task_cards b1_results dev_held_non_overlap_proof
    ].each do |key|
      leaf = exact_keys(identity[key], %w[relative_path byte_length sha256], "#{label} #{key}")
      relative_path = safe_scope_path(leaf["relative_path"], "#{label} #{key} relative path")
      leaf_path = File.join(root, relative_path)
      validate_identity(leaf_path, leaf, "#{label} accepted baseline #{key}")
    end

    task_spec_ref = exact_keys(
      contract["task_spec_ref"], %w[path sha256 byte_length], "#{label} task spec"
    )
    expected_read_context = [
      authority["current_facts"],
      authority.dig("strategy", "path"),
      authority.dig("execution_protocol", "path"),
      authority.dig("founder_delegation_policy", "path"),
      authority.dig("evaluation_protocol", "path"),
      "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml",
      task_spec_ref["path"],
      "P2_069_ACCEPTED_EVIDENCE_ROOT/accepted-source-pack-v1/SOURCE_PACK.json",
      "P2_069_ACCEPTED_EVIDENCE_ROOT/runs/repair-replay-1/candidate/BENCHMARK_MANIFEST.json",
      "P2_069_ACCEPTED_EVIDENCE_ROOT/runs/repair-replay-1/candidate/DEV_TASK_CARDS.json",
      "P2_069_ACCEPTED_EVIDENCE_ROOT/runs/repair-replay-1/candidate/B1_RESULTS.json",
      "P2_069_ACCEPTED_EVIDENCE_ROOT/runs/repair-replay-1/candidate/DEV_HELD_NON_OVERLAP_PROOF.json"
    ]
    read_context = array(contract["read_context"], "#{label} read_context")
    assert(read_context == expected_read_context && read_context.uniq.length == read_context.length,
           "#{label} read_context is not the exact clean-room minimum set")
    true
  end

  def validate_phase_delegated_baseline_ids(source_route, value)
    baseline_ids = array(value, "phase-delegated baseline ids")
    if %w[1.0 1.1].include?(source_route["schema_version"])
      assert(baseline_ids.length == 2 && baseline_ids.uniq.length == 2 &&
             baseline_ids.any? { |item| item.is_a?(String) && item.start_with?("B0_") } &&
             baseline_ids.any? { |item| item.is_a?(String) && item.start_with?("B1_") },
             "phase-delegated capability Contract requires exact B0 and B1 controls")
    else
      assert(baseline_ids.length >= 2 && baseline_ids.uniq.length == baseline_ids.length &&
             baseline_ids.all? { |item| item.is_a?(String) && !item.strip.empty? },
             "phase-delegated capability Contract baseline ids must be distinct non-empty controls")
    end
    baseline_ids
  end

  def effective_phase_source_identity(root, source_route)
    pointer = source_route["source_identity_correction"]
    return {
      "decision_packet" => source_route["decision_packet"],
      "original_founder_packet" => source_route["original_founder_packet"]
    } if pointer.nil?

    correction_identity = exact_keys(
      pointer, %w[path sha256 byte_length], "phase source identity correction"
    )
    correction_path = repo_path(root, correction_identity["path"], "phase source identity correction")
    correction = parse_structured(
      validate_identity(correction_path, correction_identity, "phase source identity correction"),
      correction_path,
      "phase source identity correction"
    )
    exact_keys(
      correction,
      %w[
        anchor_commit anchor_identity authority_effect authorization_token corrected_identity
        invariants reason_code record_type route_id schema_version
      ],
      "phase source identity correction"
    )
    assert(correction["schema_version"] == "founder-phase-route-source-identity-correction/v1" &&
           correction["record_type"] == "mechanical_source_identity_correction" &&
           correction["route_id"] == source_route["route_id"] &&
           correction["authorization_token"] == source_route["authorization_token"] &&
           correction["authority_effect"] == "NONE" &&
           correction["reason_code"] == "TRUNCATED_ACTIVATION_PARENT_TRUTH_SHA256_ONLY",
           "phase source identity correction boundary drift")
    anchor = exact_keys(
      correction["anchor_identity"],
      %w[decision_packet original_founder_packet],
      "phase source anchor identity"
    )
    corrected = exact_keys(
      correction["corrected_identity"],
      %w[decision_packet original_founder_packet],
      "phase source corrected identity"
    )
    assert(anchor["decision_packet"] == source_route["decision_packet"] &&
           anchor["original_founder_packet"] == source_route["original_founder_packet"],
           "phase source identity correction does not bind the immutable Route anchor")
    corrected.each do |key, identity|
      exact_keys(identity, %w[path byte_length sha256], "corrected phase source #{key}")
      path = repo_path(root, identity["path"], "corrected phase source #{key}")
      validate_identity(path, identity, "corrected phase source #{key}")
    end
    invariants = exact_keys(
      correction["invariants"],
      %w[
        external_effect_permission_changed founder_token_changed git_history_rewritten
        phase_envelope_changed route_authority_changed task_capacity_changed
      ],
      "phase source identity correction invariants"
    )
    assert(invariants.values.all? { |value| value == false },
           "phase source identity correction changes authority")
    corrected
  end

  def validate_phase_delegated_protocol_contract_fields(root, truth, route, contract)
    status_mapping = exact_keys(
      contract["protocol_status_mapping"],
      %w[ELIGIBLE_NOT_ACTIVATED ACTIVE],
      "phase-delegated Task Contract protocol status mapping"
    )
    assert(status_mapping == {
      "ELIGIBLE_NOT_ACTIVATED" => "ready",
      "ACTIVE" => "in_progress"
    } && status_mapping.key?(contract["status"]),
           "phase-delegated Task Contract status does not map to the Master protocol lifecycle")

    source_route = hash(truth[route["source_authority_route_ref"]],
                        "phase-delegated source authority Route")
    effective_source_identity = effective_phase_source_identity(root, source_route)
    task_spec_ref = exact_keys(
      contract["task_spec_ref"],
      %w[path sha256 byte_length],
      "phase-delegated Task Contract task_spec_ref"
    )
    assert(task_spec_ref == effective_source_identity["original_founder_packet"],
           "phase-delegated Task Contract task_spec_ref is not the immutable Founder packet")
    validate_identity(
      repo_path(root, task_spec_ref["path"], "phase-delegated Task Contract immutable task spec"),
      task_spec_ref,
      "phase-delegated Task Contract immutable task spec"
    )
    source_decision = truth.dig("phase_execution_envelope", "authority_basis", "source_decision")
    assert(source_decision == effective_source_identity["decision_packet"],
           "phase-delegated source decision does not equal the corrected effective identity")

    roles = hash(contract["roles"], "phase-delegated Task Contract roles")
    assert(contract["owner_role"] == roles["owner"] &&
           contract["worker_role"] == roles["worker"],
           "phase-delegated Task Contract owner or worker alias drift")
    assert(contract["independent_reviewer"] == roles["independent_reviewers"],
           "phase-delegated Task Contract independent reviewer alias drift")
    assert(contract["write_scope"] == contract["allowlisted_paths"],
           "phase-delegated Task Contract write_scope alias drift")

    risk = string(contract["risk_level"], "phase-delegated Task Contract risk_level")
    assert(%w[low medium high critical].include?(risk),
           "phase-delegated Task Contract risk_level is outside the protocol enum")

    authority = hash(truth["authority"], "authority")
    if %w[
      AIOS-P2-074_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_DEV
      AIOS-P2-075_CLEAN_ROOM_QUERY_ENTITY_COVERAGE_PRODUCT_SELECTOR_ARCHITECTURE_PIVOT_DEV
      AIOS-P2-076_CLEAN_ROOM_B1_ANCHORED_GRAPH_FUSION_PRODUCT_SELECTOR_DEV
      AIOS-P2-077_CLEAN_ROOM_SEMANTIC_SYMBOL_IMPACT_CONE_PRODUCT_SELECTOR_DEV
      AIOS-P2-078_CLEAN_ROOM_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_PRODUCT_SELECTOR_DEV
    ].include?(contract["task_id"])
      return validate_p2_product_selector_protocol_contract_fields(authority, contract)
    end

    baseline = exact_keys(
      contract["baseline_ref"],
      %w[artifact_id relative_path byte_length sha256 baseline_ids],
      "phase-delegated Task Contract baseline_ref"
    )
    assert(string(baseline["artifact_id"], "phase-delegated baseline artifact_id") ==
             baseline["artifact_id"] &&
           safe_scope_path(baseline["relative_path"], "phase-delegated baseline relative_path") ==
             baseline["relative_path"] &&
           integer(baseline["byte_length"], "phase-delegated baseline byte_length").positive? &&
           SHA256_RE.match?(string(baseline["sha256"], "phase-delegated baseline sha256")),
           "phase-delegated Task Contract baseline identity is invalid")
    validate_phase_delegated_baseline_ids(source_route, baseline["baseline_ids"])

    dependencies = array(contract["dependencies"], "phase-delegated Task Contract dependencies")
    expected_dependencies = [
      {
        "kind" => "CANONICAL_SOURCE",
        "identity" => source_route["activation_parent"]
      },
      {
        "kind" => "BASELINE_ARTIFACT",
        "identity" => baseline
      }
    ]
    assert(dependencies == expected_dependencies,
           "phase-delegated Task Contract dependencies are not the closed source and baseline set")

    expected_read_context = [
      authority["current_facts"],
      authority.dig("strategy", "path"),
      authority.dig("execution_protocol", "path"),
      authority.dig("founder_delegation_policy", "path"),
      authority.dig("evaluation_protocol", "path"),
      task_spec_ref["path"],
      "TASK_EVIDENCE_ROOT/#{baseline['relative_path']}"
    ]
    read_context = array(contract["read_context"], "phase-delegated Task Contract read_context")
    assert(read_context == expected_read_context && read_context.uniq.length == read_context.length,
           "phase-delegated Task Contract read_context is not the closed minimum set")
    true
  end

  def validate_phase_delegated_current_projections(truth, route, task)
    task_id = task["task_id"]
    route_id = route["route_id"]
    next_action = route["next_eligible_action"]
    active_task = task["status"] == "ACTIVE"
    expected_task = active_task ? task_id : "NONE"
    expected_action = active_task ? "COMPLETE_CURRENT_TASK_GATE" :
      "MASTER_ACTIVATE_PHASE_DELEGATED_TASK"
    phase_claim = hash(truth["phase_execution_claim"], "phase_execution_claim")
    boundary = hash(truth["claim_boundary"], "claim_boundary")
    envelope = hash(truth["phase_execution_envelope"], "phase_execution_envelope")
    active = hash(truth["active_work"], "active_work")
    control = hash(truth["founder_escalation_control"], "founder_escalation_control")
    assert(phase_claim["current_route_claim"] == route_id &&
           boundary["current_phase_route"] == route_id,
           "current Route projections do not equal the active phase-delegated Route")
    assert(phase_claim["current_task_claim"] == expected_task &&
           boundary["current_task"] == expected_task && active["current_task"] == expected_task,
           "current Task projections do not equal the exact phase-delegated lifecycle")
    assert(boundary["next_eligible_action"] == next_action &&
           active["next_eligible_action"] == next_action &&
           control["next_eligible_action"] == next_action &&
           next_action == expected_action,
           "current next-action projections do not equal the exact phase-delegated lifecycle")
    assert(phase_claim["real_engineering_progress"] == boundary["real_engineering_progress"],
           "current real-engineering-progress projections drift")
    envelope_claim_key = "#{route.fetch('phase').downcase}_phase_envelope_status"
    assert(boundary[envelope_claim_key] == envelope["status"],
           "current claim-boundary Phase envelope status drifts from the authoritative envelope")
    assert(phase_claim["product_capability_changed"] == false,
           "active authority must not project a product capability change")
    true
  end

  def validate_phase_delegated_ready_activation_parent(root, parent, route, task)
    truth_bytes = git(
      root,
      "show",
      "#{parent.fetch('commit')}:docs/aios/truth/project_state.yaml"
    ).first
    ready = parse_yaml(truth_bytes, "phase-delegated activation-parent Truth")
    ready_route = hash(ready["current_phase_route"], "phase-delegated activation-parent Route")
    ready_task = hash(ready_route["selected_task"],
                      "phase-delegated activation-parent selected Task")
    assert(ready_route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA &&
           ready_route["route_id"] == route["route_id"] &&
           ready_route["phase"] == route["phase"] &&
           ready_route["status"] == "AUTHORIZED_READY" &&
           ready_route["execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
           ready_route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" &&
           ready_route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
           "phase-delegated activation parent is not the exact READY Route")
    comparable_task_keys = %w[
      task_id task_kind capability objective capacity_source_task_id budget
      max_same_task_repairs independence
    ]
    comparable_task_keys << "repair_accounting" if task.key?("repair_accounting")
    assert(ready_task["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           comparable_task_keys.all? { |key| ready_task[key] == task[key] },
           "phase-delegated activation parent is not the same eligible Task reservation")

    ready_envelope = hash(ready["phase_execution_envelope"],
                          "phase-delegated activation-parent envelope")
    ready_reservation = hash(ready_envelope["reserved"],
                             "phase-delegated activation-parent reservation")
    assert(ready_envelope["status"] == "TASK_CAPACITY_RESERVED" &&
           ready_reservation["task_id"] == task["task_id"] &&
           ready_reservation["route_id"] == route["route_id"] &&
           ready_reservation["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           ready_reservation["capacity_source_task_id"] == task["capacity_source_task_id"] &&
           ready_reservation["budget"] == {
             "engineering_tasks" => 1,
             "engineering_hours" => task.dig("budget", "engineering_hours"),
             "calendar_days" => task.dig("budget", "calendar_days")
           } && ready_reservation["contract"] == ready_task["contract"] &&
           ready_reservation["authority"].nil?,
           "phase-delegated activation parent reservation is not exact READY without authority")

    ready_contract_identity = exact_keys(
      ready_task["contract"],
      %w[path sha256 byte_length],
      "phase-delegated activation-parent Contract identity"
    )
    ready_contract_bytes = git(
      root,
      "show",
      "#{parent.fetch('commit')}:#{ready_contract_identity.fetch('path')}"
    ).first
    assert(ready_contract_bytes.bytesize == ready_contract_identity["byte_length"] &&
           sha256(ready_contract_bytes) == ready_contract_identity["sha256"],
           "phase-delegated activation-parent Contract identity is not Git-bound")
    ready_contract = parse_structured(
      ready_contract_bytes,
      ready_contract_identity["path"],
      "phase-delegated activation-parent Contract"
    )
    assert(ready_contract["record_type"] == DELEGATED_TASK_CONTRACT_TYPE &&
           ready_contract["task_id"] == task["task_id"] &&
           ready_contract["route_id"] == route["route_id"] &&
           ready_contract["status"] == "ELIGIBLE_NOT_ACTIVATED",
           "phase-delegated activation-parent Contract is not exact READY")

    ready_active = hash(ready["active_work"], "phase-delegated activation-parent active_work")
    assert(ready_active["current_task"] == "NONE" &&
           ready_active["current_task_status"] == "NONE" &&
           ready_active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
           ready_active["current_execution_authorization"].nil? &&
           ready_active["current_execution_authorization_sha256"].nil? &&
           ready_active["execution_nonce"].nil? && ready_active["authorization_id"].nil? &&
           ready_active["activation_parent_commit"].nil? &&
           ready_active["activation_parent_tree"].nil? &&
           ready_active["task_branch"].nil? && ready_active["task_worktree"].nil? &&
           ready_active["execution_evidence_root"].nil? &&
           array(ready_active["allowlisted_paths"],
                 "phase-delegated activation-parent allowlisted paths").empty?,
           "phase-delegated activation-parent Truth pre-creates active resources")
    null_identity(ready_active["authority_record"],
                  "phase-delegated activation-parent authority record")
    assert(hash(ready["goal"], "phase-delegated activation-parent Goal")["current_task_authority"] ==
           "NONE",
           "phase-delegated activation-parent Goal pre-activates the Task")
    {
      "identity" => ready_contract_identity,
      "contract" => ready_contract
    }
  rescue Psych::Exception => e
    fail!("phase-delegated activation-parent Truth is invalid YAML: #{e.message}")
  end

  def validate_phase_delegated_contract(root, truth, route, task)
    identity = exact_keys(task["contract"], %w[path sha256 byte_length],
                          "phase-delegated Task Contract identity")
    path = repo_path(root, identity["path"], "phase-delegated Task Contract path")
    bytes = validate_identity(path, identity, "phase-delegated Task Contract")
    source_route = hash(truth[route["source_authority_route_ref"]],
                        "phase-delegated source authority Route")
    parsed_contract = parse_structured(bytes, path, "phase-delegated Task Contract")
    contract_schema_version = parsed_contract["schema_version"]
    contract_keys = %w[
        schema_version record_type task_id phase route_id status task_kind capability
        objective why_now task_spec_ref owner_role worker_role write_scope read_context
        dependencies risk_level baseline_ref independent_reviewer protocol_status_mapping
        task_gate_owner founder_gate capacity_source_task_id budget
        max_same_task_repairs roles allowlisted_paths external_effects
        goal_identity phase_delegation_binding acceptance_criteria required_evidence
        rollback stop_conditions forbidden_actions claim_boundary
    ]
    contract_keys << "write_ownership" if contract_schema_version == "1.1"
    contract_keys << "repair_accounting" if task.key?("repair_accounting")
    contract_keys << "preactivation_gate" if %w[
      AIOS-P2-073_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_SANDBOX_STREAM_LIFECYCLE_DEV
      AIOS-P2-074_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_DEV
      AIOS-P2-075_CLEAN_ROOM_QUERY_ENTITY_COVERAGE_PRODUCT_SELECTOR_ARCHITECTURE_PIVOT_DEV
      AIOS-P2-076_CLEAN_ROOM_B1_ANCHORED_GRAPH_FUSION_PRODUCT_SELECTOR_DEV
      AIOS-P2-077_CLEAN_ROOM_SEMANTIC_SYMBOL_IMPACT_CONE_PRODUCT_SELECTOR_DEV
      AIOS-P2-078_CLEAN_ROOM_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_PRODUCT_SELECTOR_DEV
    ].include?(parsed_contract["task_id"])
    contract = exact_keys(
      parsed_contract,
      contract_keys,
      "phase-delegated Task Contract"
    )
    assert(%w[1.0 1.1].include?(contract["schema_version"]) &&
           contract["record_type"] == DELEGATED_TASK_CONTRACT_TYPE,
           "phase-delegated Task Contract type drift")
    validate_phase_delegated_contract_schema_binding!(source_route, contract)
    validate_phase_delegated_contract_policy_fields(contract)
    if parsed_contract["task_id"] ==
       "AIOS-P2-073_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_SANDBOX_STREAM_LIFECYCLE_DEV"
      validate_p2_073_preactivation_gate(contract)
    elsif parsed_contract["task_id"] ==
          "AIOS-P2-074_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_DEV"
      validate_p2_074_preactivation_gate(contract)
    elsif parsed_contract["task_id"] ==
          "AIOS-P2-075_CLEAN_ROOM_QUERY_ENTITY_COVERAGE_PRODUCT_SELECTOR_ARCHITECTURE_PIVOT_DEV"
      validate_p2_075_preactivation_gate(contract)
    elsif parsed_contract["task_id"] ==
          "AIOS-P2-076_CLEAN_ROOM_B1_ANCHORED_GRAPH_FUSION_PRODUCT_SELECTOR_DEV"
      validate_p2_076_preactivation_gate(contract)
    elsif parsed_contract["task_id"] ==
          "AIOS-P2-077_CLEAN_ROOM_SEMANTIC_SYMBOL_IMPACT_CONE_PRODUCT_SELECTOR_DEV"
      validate_p2_077_preactivation_gate(contract)
    elsif parsed_contract["task_id"] ==
          "AIOS-P2-078_CLEAN_ROOM_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_PRODUCT_SELECTOR_DEV"
      validate_p2_078_preactivation_gate(contract)
    end
    validate_phase_delegated_protocol_contract_fields(root, truth, route, contract)
    projected_keys = %w[
      task_id status task_kind capability objective capacity_source_task_id budget max_same_task_repairs
    ]
    projected_keys << "repair_accounting" if task.key?("repair_accounting")
    projected_keys.each do |key|
      assert(contract[key] == task[key], "phase-delegated Task Contract #{key} drift")
    end
    assert(contract["phase"] == route["phase"] && contract["route_id"] == route["route_id"],
           "phase-delegated Task Contract Phase or Route drift")
    assert(contract["goal_identity"] == phase_delegated_goal_identity(truth),
           "phase-delegated Task Contract Goal identity drift")
    assert(contract["phase_delegation_binding"] == phase_delegated_binding(truth, route),
           "phase-delegated Task Contract delegation binding drift")
    assert(contract["claim_boundary"].is_a?(String) && !contract["claim_boundary"].empty?,
           "phase-delegated Task Contract claim boundary missing")
    %w[acceptance_criteria required_evidence stop_conditions forbidden_actions].each do |key|
      values = array(contract[key], "phase-delegated Task Contract #{key}")
      assert(!values.empty? && values.all? { |item| item.is_a?(String) && !item.empty? },
             "phase-delegated Task Contract #{key} is empty or invalid")
    end
    assert(contract["rollback"].is_a?(String) && !contract["rollback"].empty?,
           "phase-delegated Task Contract rollback is missing")
    [contract, identity]
  end

  def validate_phase_delegated_contract_schema_binding!(source_route, contract)
    return contract unless %w[1.3 1.4].include?(source_route["schema_version"])
    assert(contract["schema_version"] == "1.1" && contract.key?("write_ownership"),
           "v1.3+ Founder source Route requires a role-partitioned Task Contract v1.1")
    contract
  end

  def validate_phase_delegated_common_scope(truth, route, task, contract)
    budget = exact_keys(task["budget"],
                        %w[engineering_hours calendar_days implementation_iterations candidates],
                        "phase-delegated Task budget")
    assert(contract["budget"] == budget, "phase-delegated Task Contract budget drift")
    repairs = integer(task["max_same_task_repairs"], "phase-delegated Task repair budget")
    assert(contract["max_same_task_repairs"] == repairs,
           "phase-delegated Task Contract repair budget drift")
    envelope = hash(truth["phase_execution_envelope"], "phase_execution_envelope")
    source_route_key = string(
      hash(envelope["authority_basis"], "phase_execution_envelope.authority_basis")["source_route_ref"],
      "phase execution source Route reference"
    )
    source_route = hash(truth[source_route_key], source_route_key)
    capacity_source = FounderDelegationContinuity.source_capacity_task!(
      source_route,
      task["capacity_source_task_id"]
    )
    if task.key?("repair_accounting")
      task_repair_accounting = FounderDelegationContinuity.validate_repair_accounting!(
        task["repair_accounting"],
        capacity_source["max_same_task_repairs"],
        repairs,
        "phase-delegated selected Task repair_accounting"
      )
      contract_repair_accounting = FounderDelegationContinuity.validate_repair_accounting!(
        contract["repair_accounting"],
        capacity_source["max_same_task_repairs"],
        repairs,
        "phase-delegated Task Contract repair_accounting"
      )
      assert(contract_repair_accounting == task_repair_accounting,
             "phase-delegated Task repair accounting projection drift")
    end
    assert(repairs <= budget["implementation_iterations"] - 1,
           "phase-delegated Task repairs exceed implementation iterations minus one")
    assert(budget["engineering_hours"] <= capacity_source["engineering_hours"] &&
           budget["calendar_days"] <= capacity_source["calendar_days"] &&
           budget["implementation_iterations"] <= capacity_source["max_implementation_iterations"] &&
           budget["candidates"] <= capacity_source["max_candidates"] &&
           repairs <= capacity_source["max_same_task_repairs"],
           "phase-delegated Task exceeds Founder-bound source capacity slot")
    roles = exact_keys(contract["roles"], %w[owner worker independent_reviewers],
                       "phase-delegated Task Contract roles")
    owner = string(roles["owner"], "phase-delegated Task owner")
    worker = string(roles["worker"], "phase-delegated Task worker")
    reviewers = array(roles["independent_reviewers"], "phase-delegated Task reviewers")
    assert(reviewers.length == 3 && reviewers.all? { |reviewer| reviewer.is_a?(String) && !reviewer.empty? },
           "phase-delegated Task requires exactly three independent reviewers")
    assert(([owner, worker] + reviewers).uniq.length == 5,
           "phase-delegated Task role identities must be distinct")

    scopes = normalize_scopes(contract["allowlisted_paths"],
                              "phase-delegated Task Contract allowlisted_paths")
    ownership = contract["schema_version"] == "1.1" ?
      validate_phase_delegated_write_ownership!(contract, roles, scopes) : nil
    boundary = hash(truth["phase_boundary"], "phase_boundary")
    validate_phase_delegated_role_root_binding!(ownership, boundary) if ownership
    roots = flatten_write_roots(boundary["role_write_roots"])
    immutable = array(boundary["immutable_authority_paths"], "phase_boundary.immutable_authority_paths")
    scopes.each do |scope|
      assert(roots.any? { |root_path| scope_within_root?(scope, root_path) },
             "phase-delegated Task path is outside current Phase roots: #{scope}")
      assert(immutable.none? { |path| scope_within_root?(scope, path) || scope_within_root?(path, scope) },
             "phase-delegated Task path overlaps immutable authority: #{scope}")
    end
    validate_external_effects(contract["external_effects"],
                              "phase-delegated Task Contract external_effects",
                              FALSE_EXTERNAL_EFFECTS)
    [budget, repairs, roles, scopes]
  end

  def validate_phase_delegated_write_ownership!(contract, roles, scopes)
    ownership = exact_keys(
      contract["write_ownership"],
      %w[schema_version cross_role_write_allowed owner worker independent_reviewers],
      "phase-delegated Task Contract write_ownership"
    )
    assert(ownership["schema_version"] == "role-write-ownership/v1" &&
           ownership["cross_role_write_allowed"] == false,
           "phase-delegated Task write ownership policy drift")

    owner_record = exact_keys(
      ownership["owner"], %w[role write_paths],
      "phase-delegated Task owner write ownership"
    )
    worker_record = exact_keys(
      ownership["worker"], %w[role write_paths],
      "phase-delegated Task worker write ownership"
    )
    reviewer_records = array(
      ownership["independent_reviewers"],
      "phase-delegated Task reviewer write ownership"
    ).map do |record|
      exact_keys(record, %w[role write_paths],
                 "phase-delegated Task reviewer write ownership record")
    end
    assert(owner_record["role"] == roles["owner"] &&
           worker_record["role"] == roles["worker"] &&
           reviewer_records.map { |record| record["role"] } == roles["independent_reviewers"],
           "phase-delegated Task write ownership role projection drift")

    records = [owner_record, worker_record] + reviewer_records
    path_sets = records.map do |record|
      declared_paths = array(
        record["write_paths"],
        "phase-delegated Task write paths for #{record['role']}"
      )
      declared_paths.empty? ? [] : normalize_scopes(
        declared_paths,
        "phase-delegated Task write paths for #{record['role']}"
      )
    end
    assert(path_sets.flatten.length == path_sets.flatten.uniq.length,
           "phase-delegated Task write ownership paths overlap across roles")
    path_sets.each_with_index do |left_paths, left_index|
      path_sets.each_with_index do |right_paths, right_index|
        next unless right_index > left_index
        left_paths.product(right_paths).each do |left_path, right_path|
          assert(!scope_within_root?(left_path, right_path) &&
                 !scope_within_root?(right_path, left_path),
                 "phase-delegated Task write ownership ancestor paths overlap across roles")
        end
      end
    end
    assert(path_sets.flatten.sort == scopes.sort,
           "phase-delegated Task write ownership does not exactly partition the allowlist")
    ownership
  end

  def validate_phase_delegated_active_write_ownership!(contract, authority, active, roles, scopes)
    ownership = validate_phase_delegated_write_ownership!(contract, roles, scopes)
    worker_paths = normalize_scopes(
      ownership.dig("worker", "write_paths"),
      "phase-delegated effective Worker write paths"
    )
    assert(authority["write_ownership"] == ownership &&
           active["write_ownership"] == ownership,
           "phase-delegated active role write ownership projection drift")
    assert(normalize_scopes(
             authority["effective_worker_write_paths"],
             "phase-delegated authority effective Worker paths"
           ) == worker_paths &&
           normalize_scopes(
             active["effective_worker_write_paths"],
             "phase-delegated active effective Worker paths"
           ) == worker_paths,
           "phase-delegated Worker effective write set exceeds its role partition")
    ownership
  end

  def validate_phase_delegated_role_root_binding!(ownership, boundary)
    role_roots = hash(boundary["role_write_roots"], "phase boundary role_write_roots")
    bindings = [
      [ownership["owner"], array(role_roots["integration"], "integration write roots")],
      [ownership["worker"], array(role_roots["worker"], "Worker write roots")]
    ]
    array(ownership["independent_reviewers"], "reviewer ownership records").each do |record|
      bindings << [record, array(role_roots["quality"], "Quality write roots")]
    end
    bindings.each do |record, roots|
      array(record["write_paths"], "role-owned write paths").each do |path|
        assert(roots.any? { |root_path| scope_within_root?(path, root_path) },
               "phase-delegated role write path is outside its assigned Phase role roots")
      end
    end
    ownership
  end

  def validate_phase_delegated_none_state(truth, route, task, contract_identity)
    active = hash(truth["active_work"], "active_work")
    assert(task["status"] == "ELIGIBLE_NOT_ACTIVATED", "phase-delegated READY Task status drift")
    assert(hash(truth["goal"], "goal")["current_task_authority"] == "NONE",
           "phase-delegated READY Task requires Goal authority NONE")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY",
           "phase-delegated READY active_work lifecycle drift")
    assert(active["current_task_contract"] == contract_identity &&
           active["current_task_contract_sha256"] == contract_identity["sha256"],
           "phase-delegated READY Contract identity drift")
    null_identity(active["authority_record"], "phase-delegated READY authority_record")
    %w[
      current_execution_authorization current_execution_authorization_sha256 execution_nonce
      authorization_id activation_parent_commit activation_parent_tree task_branch task_worktree
      execution_evidence_root offsite_target founder_reserved_authorization
      founder_reserved_authorization_sha256
    ].each do |key|
      assert(active[key].nil?, "phase-delegated READY active_work.#{key} must be null")
    end
    assert(active["execution_nonce_status"] == "NOT_APPLICABLE_TASK_NONE",
           "phase-delegated READY execution nonce status drift")
    assert(array(active["allowlisted_paths"], "phase-delegated READY paths").empty?,
           "phase-delegated READY paths must be empty")
    active_budget = hash(active["budget"], "phase-delegated READY budget")
    assert(active_budget.values.all?(&:nil?), "phase-delegated READY budget must be null")
    active_roles = hash(active["roles"], "phase-delegated READY roles")
    assert(active_roles["owner"].nil? && active_roles["worker"].nil? &&
           array(active_roles["independent_reviewers"], "phase-delegated READY reviewers").empty?,
           "phase-delegated READY roles must be empty")
    validate_external_effects(active["external_effects"], "phase-delegated READY effects",
                              FALSE_EXTERNAL_EFFECTS)
    exact_false(active["founder_decision_required"], "phase-delegated READY Founder decision")
    exact_false(active["phase_route_decision_required"], "phase-delegated READY Phase decision")
    assert(active["founder_reserved_authorization"].nil? &&
           active["founder_reserved_authorization_sha256"].nil? &&
           active["next_eligible_action"] == route["next_eligible_action"],
           "phase-delegated READY action or Founder binding drift")
  end

  def validate_java_ctx_v1_oos_nonpass_repair_receipt(record, task, accounting,
                                                       external_effects, source_activation)
    repair_receipt = exact_keys(
      record,
      %w[
        aggregate_oos_result canonical_or_external_install_performed
        held_outcomes_opened_or_executed next_action normalized_root oos_audit_receipt
        same_task_repair schema_version sole_repair_scope source_activation status
        superseded_prefreeze_inventory_v1 superseded_quality_core_v1 task_id
        v1_install_allowed v1_product_or_validation_execution_allowed v1_worker_access_allowed
      ],
      "Java context same-Task repair receipt"
    )
    receipt_accounting = exact_keys(
      repair_receipt["same_task_repair"],
      %w[
        initial_implementation_iterations_are_not_repairs maximum_same_task_repairs
        no_further_repair_allowance remaining_same_task_repairs same_task_repair_used
      ],
      "Java context same-Task repair receipt accounting"
    )
    validate_external_effects(
      external_effects,
      "Java context same-Task repair receipt authority effects",
      FALSE_EXTERNAL_EFFECTS
    )
    assert(repair_receipt["schema_version"] ==
             "java-ctx-v1-oos-nonpass-supersession/v1" &&
           repair_receipt["task_id"] == task["task_id"] &&
           repair_receipt["source_activation"] == source_activation &&
           repair_receipt["status"] ==
             "PREFREEZE_OOS_IDENTITY_INTERSECTION_NON_PASS_SUPERSEDED_NO_INSTALL_NO_WORKER" &&
           repair_receipt["normalized_root"] ==
             "PREFREEZE_OOS_CONTAMINATED_IDENTITY_UNDERBOUND_AND_INTERSECTION" &&
           repair_receipt["canonical_or_external_install_performed"] == false &&
           repair_receipt["held_outcomes_opened_or_executed"] == false &&
           repair_receipt["v1_install_allowed"] == false &&
           repair_receipt["v1_product_or_validation_execution_allowed"] == false &&
           repair_receipt["v1_worker_access_allowed"] == false &&
           accounting["classification"] == "QUALITY_PREFREEZE_OOS_REPAIR" &&
           receipt_accounting == {
             "initial_implementation_iterations_are_not_repairs" => true,
             "maximum_same_task_repairs" => accounting["authorized"],
             "no_further_repair_allowance" => accounting["remaining"].zero?,
             "remaining_same_task_repairs" => accounting["remaining"],
             "same_task_repair_used" => accounting["used"]
           },
           "Java context same-Task repair receipt projection drift")
    true
  end

  def validate_phase_delegated_repair_receipt(bytes, path, task, accounting,
                                               external_effects, source_activation)
    record = parse_structured(bytes, path, "phase-delegated same-Task repair receipt")
    schema_version = string(
      record["schema_version"],
      "phase-delegated same-Task repair receipt schema_version"
    )
    case schema_version
    when "java-ctx-v1-oos-nonpass-supersession/v1"
      validate_java_ctx_v1_oos_nonpass_repair_receipt(
        record,
        task,
        accounting,
        external_effects,
        source_activation
      )
    else
      fail!("unsupported phase-delegated same-Task repair receipt schema #{schema_version.inspect}")
    end
  end

  def validate_phase_delegated_active_state(root, truth, route, task, contract, contract_identity,
                                            budget, repairs, roles, scopes)
    project = hash(truth["project"], "project")
    active = hash(truth["active_work"], "active_work")
    task_id = task["task_id"]
    assert(task["status"] == "ACTIVE" && active["current_task"] == task_id &&
           ACTIVE_STATUSES.include?(active["current_task_status"]),
           "phase-delegated ACTIVE Task lifecycle drift")
    assert(hash(truth["goal"], "goal")["current_task_authority"] == task_id,
           "phase-delegated ACTIVE Goal authority drift")
    assert(active["current_task_contract"] == contract_identity &&
           active["current_task_contract_sha256"] == contract_identity["sha256"],
           "phase-delegated ACTIVE Contract identity drift")

    authority_identity = exact_keys(active["authority_record"], %w[path sha256 byte_length],
                                    "phase-delegated authority identity")
    reservation = hash(truth.dig("phase_execution_envelope", "reserved"),
                       "phase-delegated active reservation")
    reserved_authority = exact_keys(
      reservation["authority"],
      %w[path sha256 byte_length],
      "phase-delegated reserved authority identity"
    )
    assert(reserved_authority == authority_identity &&
           active["current_execution_authorization"] == authority_identity["path"] &&
           active["current_execution_authorization_sha256"] == authority_identity["sha256"],
           "phase-delegated reserved authority does not equal active authority")
    authority_path = string(authority_identity["path"], "phase-delegated authority path")
    assert(Pathname.new(authority_path).absolute?, "phase-delegated authority path must be absolute")
    assert(File.expand_path(authority_path) == authority_path &&
           File.realpath(authority_path) == authority_path,
           "phase-delegated authority path must be canonical and not traverse symlinks")
    authority_bytes = validate_identity(authority_path, authority_identity, "phase-delegated authority")
    source_route = hash(truth[route["source_authority_route_ref"]],
                        "phase-delegated source authority Route")
    authority_keys = %w[
        schema_version record_type task_id phase route_id status authorization_id
        task_contract_sha256 contract_lifecycle_transition execution_nonce activation_parent branch worktree evidence_root
        capacity_source_task_id budget max_same_task_repairs roles allowlisted_paths external_effects goal_identity
        phase_delegation_binding founder_reserved_authorization founder_reserved_profile
    ]
    authority_keys.concat(%w[write_ownership effective_worker_write_paths]) if
      contract["schema_version"] == "1.1"
    authority_keys << "repair_accounting" if task.key?("repair_accounting")
    authority = exact_keys(
      parse_structured(authority_bytes, authority_path, "phase-delegated authority"),
      authority_keys,
      "phase-delegated authority"
    )
    expected_authority_schema = contract["schema_version"] == "1.1" ? "1.1" : "1.0"
    assert(authority["schema_version"] == expected_authority_schema &&
           authority["record_type"] == DELEGATED_TASK_AUTHORITY_TYPE,
           "phase-delegated authority type drift")
    assert(authority["task_id"] == task_id && authority["phase"] == route["phase"] &&
           authority["route_id"] == route["route_id"] && authority["status"] == "ACTIVE",
           "phase-delegated authority lifecycle drift")
    assert(authority["task_contract_sha256"] == contract_identity["sha256"],
           "phase-delegated authority Contract SHA drift")
    assert(authority["capacity_source_task_id"] == task["capacity_source_task_id"] &&
           reservation["capacity_source_task_id"] == task["capacity_source_task_id"],
           "phase-delegated authority capacity source drift")
    assert(authority["budget"] == budget && authority["max_same_task_repairs"] == repairs &&
           authority["roles"] == roles &&
           normalize_scopes(authority["allowlisted_paths"], "phase-delegated authority paths") == scopes,
           "phase-delegated authority scope drift")
    if contract["schema_version"] == "1.1"
      validate_phase_delegated_active_write_ownership!(
        contract, authority, active, roles, scopes
      )
    end
    if task.key?("repair_accounting")
      capacity_source = FounderDelegationContinuity.source_capacity_task!(
        source_route,
        task["capacity_source_task_id"]
      )
      authority_repair_accounting = FounderDelegationContinuity.validate_repair_accounting!(
        authority["repair_accounting"],
        capacity_source["max_same_task_repairs"],
        repairs,
        "phase-delegated authority repair_accounting"
      )
      assert(authority_repair_accounting == task["repair_accounting"] &&
             authority_repair_accounting == contract["repair_accounting"],
             "phase-delegated authority repair accounting projection drift")
    end
    assert(authority["goal_identity"] == phase_delegated_goal_identity(truth) &&
           authority["phase_delegation_binding"] == phase_delegated_binding(truth, route),
           "phase-delegated authority binding drift")
    validate_external_effects(authority["external_effects"], "phase-delegated authority effects",
                              FALSE_EXTERNAL_EFFECTS)
    assert(authority["founder_reserved_authorization"].nil? && authority["founder_reserved_profile"].nil?,
           "phase-delegated authority must not invent Founder authorization")

    authorization_id = string(active["authorization_id"], "phase-delegated authorization_id")
    execution_nonce = string(active["execution_nonce"], "phase-delegated execution_nonce")
    assert(active["execution_nonce_status"] == "ACTIVE" &&
           authority["authorization_id"] == authorization_id && authority["execution_nonce"] == execution_nonce,
           "phase-delegated execution identity drift")
    assert(active["current_execution_authorization"] == authority_path &&
           active["current_execution_authorization_sha256"] == authority_identity["sha256"],
           "phase-delegated authority active_work projection drift")

    parent = exact_keys(authority["activation_parent"], %w[commit tree],
                        "phase-delegated authority activation_parent")
    assert(parent["commit"] == active["activation_parent_commit"] &&
           parent["tree"] == active["activation_parent_tree"],
           "phase-delegated activation parent projection drift")
    validate_commit_tree(root, parent["commit"], parent["tree"], "phase-delegated activation parent")
    _out, _err, ancestor = git(root, "merge-base", "--is-ancestor", parent["commit"], "HEAD",
                               allow_failure: true)
    assert(ancestor.success?, "phase-delegated activation parent is not canonical")
    ready_contract_state = validate_phase_delegated_ready_activation_parent(root, parent, route, task)
    transition = exact_keys(
      authority["contract_lifecycle_transition"],
      %w[schema_version transition classification changed_fields ready_contract active_contract],
      "phase-delegated Contract lifecycle transition"
    )
    assert(transition["schema_version"] ==
             "phase-delegated-task-contract-lifecycle-transition/v1" &&
           transition["transition"] == "ELIGIBLE_NOT_ACTIVATED_TO_ACTIVE" &&
           transition["classification"] ==
             "AUTHORITY_ACTIVATION_LIFECYCLE_TRANSITION_NOT_CORRECTION_OR_REPAIR" &&
           transition["changed_fields"] == ["status"] &&
           transition["ready_contract"] == ready_contract_state["identity"] &&
           transition["active_contract"] == contract_identity,
           "phase-delegated Contract lifecycle transition binding drift")
    ready_contract_projection = ready_contract_state["contract"].reject do |key, _value|
      key == "status"
    end
    active_contract_projection = contract.reject { |key, _value| key == "status" }
    assert(ready_contract_state.dig("contract", "status") == "ELIGIBLE_NOT_ACTIVATED" &&
           contract["status"] == "ACTIVE" &&
           ready_contract_projection == active_contract_projection,
           "phase-delegated READY and ACTIVE Contracts differ outside the lifecycle status")

    assert(active["budget"] == budget && active["roles"] == roles &&
           normalize_scopes(active["allowlisted_paths"], "phase-delegated active paths") == scopes,
           "phase-delegated active_work scope drift")
    validate_external_effects(active["external_effects"], "phase-delegated active effects",
                              FALSE_EXTERNAL_EFFECTS)
    branch = string(active["task_branch"], "phase-delegated task branch")
    worktree = string(active["task_worktree"], "phase-delegated task worktree")
    evidence = string(active["execution_evidence_root"], "phase-delegated Evidence root")
    assert(branch != project["canonical_branch"] && authority["branch"] == branch,
           "phase-delegated branch identity drift")
    worktree_base = File.realpath(string(project["task_worktree_root"], "project.task_worktree_root"))
    evidence_base = File.realpath(string(project["execution_evidence_root_base"],
                                        "project.execution_evidence_root_base"))
    worktree_stat = File.lstat(worktree)
    evidence_stat = File.lstat(evidence)
    assert(Pathname.new(worktree).absolute? && Pathname.new(evidence).absolute? &&
           File.expand_path(worktree) == worktree && File.expand_path(evidence) == evidence,
           "phase-delegated Task resource paths must be canonical absolute paths")
    assert(worktree_stat.directory? && !worktree_stat.symlink? &&
           evidence_stat.directory? && !evidence_stat.symlink?,
           "phase-delegated Task resources must be non-symlink directories")
    worktree_real = File.realpath(worktree)
    evidence_real = File.realpath(evidence)
    assert(worktree_real == worktree && evidence_real == evidence,
           "phase-delegated Task resource path must not traverse symlinked components")
    assert(worktree_real.start_with?(worktree_base + File::SEPARATOR) &&
           evidence_real.start_with?(evidence_base + File::SEPARATOR),
           "phase-delegated Task resource escapes configured roots")
    assert(authority["worktree"] == worktree_real && authority["evidence_root"] == evidence_real,
           "phase-delegated Task resource identity drift")
    baseline = contract["baseline_ref"]
    unless %w[
      AIOS-P2-074_CLEAN_ROOM_JAVA_MAINTENANCE_CONTEXT_SELECTOR_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_DEV
      AIOS-P2-075_CLEAN_ROOM_QUERY_ENTITY_COVERAGE_PRODUCT_SELECTOR_ARCHITECTURE_PIVOT_DEV
      AIOS-P2-076_CLEAN_ROOM_B1_ANCHORED_GRAPH_FUSION_PRODUCT_SELECTOR_DEV
      AIOS-P2-077_CLEAN_ROOM_SEMANTIC_SYMBOL_IMPACT_CONE_PRODUCT_SELECTOR_DEV
      AIOS-P2-078_CLEAN_ROOM_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_PRODUCT_SELECTOR_DEV
    ].include?(task["task_id"])
      baseline_path = File.join(evidence_real, baseline["relative_path"])
      validate_identity(baseline_path, baseline, "phase-delegated active baseline Artifact")
    end
    if task.key?("repair_accounting")
      repair_receipt = authority.dig("repair_accounting", "receipt")
      repair_receipt_path = File.join(evidence_real, repair_receipt["relative_path"])
      repair_receipt_bytes = validate_identity(
        repair_receipt_path,
        repair_receipt,
        "phase-delegated consumed repair receipt"
      )
      validate_phase_delegated_repair_receipt(
        repair_receipt_bytes,
        repair_receipt_path,
        task,
        authority["repair_accounting"],
        authority["external_effects"],
        source_route["activation_parent"]
      )
    end
    worktree_head = git(worktree_real, "rev-parse", "HEAD").first.strip
    worktree_branch = git(worktree_real, "symbolic-ref", "--quiet", "--short", "HEAD",
                          allow_failure: true)
    assert(COMMIT_RE.match?(worktree_head) && worktree_branch.last.success? &&
           worktree_branch.first.strip == branch,
           "phase-delegated Task worktree branch or HEAD identity drift")
    _out, _err, worktree_descendant = git(
      worktree_real,
      "merge-base",
      "--is-ancestor",
      parent["commit"],
      worktree_head,
      allow_failure: true
    )
    assert(worktree_descendant.success?,
           "phase-delegated Task worktree HEAD is not descended from the exact READY activation parent")

    historical_active = truth.select do |key, value|
      key.to_s.start_with?("historical_") && value.is_a?(Hash) &&
        value["current_task"].is_a?(String) && value["current_task"] != "NONE"
    end.values
    historical_active.each do |record|
      assert(execution_nonce != record["execution_nonce"] &&
             authorization_id != record["authorization_id"] &&
             branch != record["task_branch"] &&
             worktree != record["task_worktree"] &&
             evidence != record["execution_evidence_root"] &&
             contract_identity["path"] != record.dig("current_task_contract", "path") &&
             authority_path != record.dig("authority_record", "path"),
             "phase-delegated Task reuses historical execution lineage identity")
      if record["task_worktree"].is_a?(String) && File.exist?(record["task_worktree"])
        assert(worktree_real != File.realpath(record["task_worktree"]),
               "phase-delegated Task reuses historical physical worktree")
      end
      next unless record["execution_evidence_root"].is_a?(String) &&
                  File.exist?(record["execution_evidence_root"])

      historical_evidence = File.realpath(record["execution_evidence_root"])
      overlap = evidence_real == historical_evidence ||
                evidence_real.start_with?(historical_evidence + File::SEPARATOR) ||
                historical_evidence.start_with?(evidence_real + File::SEPARATOR)
      assert(!overlap, "phase-delegated Task Evidence overlaps historical execution lineage")
    end
    assert(active["task_resource_state"] == "ACTIVE_UNIQUE_PHASE_DELEGATED" &&
           active["next_eligible_action"] == "COMPLETE_CURRENT_TASK_GATE",
           "phase-delegated ACTIVE resource state drift")
    exact_false(active["founder_decision_required"], "phase-delegated ACTIVE Founder decision")
    exact_false(active["phase_route_decision_required"], "phase-delegated ACTIVE Phase decision")
    assert(active["founder_reserved_authorization"].nil? &&
           active["founder_reserved_authorization_sha256"].nil?,
           "phase-delegated ACTIVE must not retain Founder packet")
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => e
    fail!("phase-delegated Task resource is unavailable (#{e.class})")
  end

  def validate_phase_delegated_task(root, truth)
    disposition = FounderDelegationContinuity.validate_truth!(root: root, truth: truth)
    assert(disposition == FounderDelegationContinuity::CONTINUE_DISPOSITION,
           "phase-delegated Task requires autonomous continuation disposition")
    route = hash(truth["current_phase_route"], "current_phase_route")
    task = hash(route["selected_task"], "current_phase_route.selected_task")
    source_route = hash(
      truth[route["source_authority_route_ref"]],
      "current_phase_route source authority Route"
    )
    validate_phase_delegated_current_projections(truth, route, task) if
      SINGLE_TASK_EXPANSION_DECISION_VERSIONS.include?(source_route["schema_version"])
    contract, contract_identity = validate_phase_delegated_contract(root, truth, route, task)
    budget, repairs, roles, scopes = validate_phase_delegated_common_scope(truth, route, task, contract)
    if hash(truth["active_work"], "active_work")["current_task"] == "NONE"
      validate_phase_delegated_none_state(truth, route, task, contract_identity)
      "READY_NONE"
    else
      validate_phase_delegated_active_state(root, truth, route, task, contract, contract_identity,
                                            budget, repairs, roles, scopes)
      "ACTIVE_TASK"
    end
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
                        assert(!route.key?("active_task") || route["active_task"].nil?,
                               "first Task must not retain a separate active_task descriptor")
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
    assert(task_descriptor["status"] == "ACTIVE" &&
           task_descriptor["status"] == plan_descriptor["status"],
           "route active_task descriptor status must equal ACTIVE task_plan state")
    assert(task_descriptor["task_slot"] == plan_descriptor["task_slot"],
           "route active_task descriptor slot does not equal task_plan")
    assert(task_descriptor["contract_path"] == contract_identity["path"],
           "route active_task descriptor contract path mismatch")
    validate_structured_task_state_vector(
      route,
      first_task,
      claims,
      target_task_id: task_id,
      target_state: "ACTIVE"
    )
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

    selected_profile = claims.fetch("founder_reserved_profiles", []).find do |profile|
      profile["task_id"] == task_id
    end
    if selected_profile
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
      expected_effects = if TASK_EFFECT_DECISION_VERSIONS.include?(claims["structured_decision_version"])
                           claims.fetch("task_effects").fetch(task_id)
                         else
                           claims.fetch("external_effects", FALSE_EXTERNAL_EFFECTS)
                         end
    end
    validate_external_effects(active["external_effects"], "active_work.external_effects", expected_effects)
    validate_external_effects(contract_field(contract, "external_effects"), "contract external_effects", expected_effects)
    validate_external_effects(contract_field(authority_record, "external_effects"), "authority external_effects",
                              expected_effects)
    if selected_profile
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
    inherited_source = if %w[
      strict-phase-recovery-hold/v1
      phase-delegated-continuation-hold/v1
      phase-delegated-independent-task/v1
      founder-reserved-decision-hold/v1
    ].include?(route["schema_version"])
                         source_key = string(
                           route["inherited_worktree_inventory_source"],
                           "current_phase_route.inherited_worktree_inventory_source"
                         )
                         hash(truth[source_key], source_key)
                       else
                         route
                       end
    inherited = array(inherited_source.fetch("inherited_worktree_inventory", []),
                      "current_phase_route.inherited_worktree_inventory")
    inherited_records = inherited.map.with_index do |value, index|
      record = exact_keys(value, %w[path head branch status],
                          "current_phase_route.inherited_worktree_inventory[#{index}]")
      path = string(record["path"], "inherited worktree path")
      assert(Pathname.new(path).absolute?, "inherited worktree path must be absolute")
      assert(COMMIT_RE.match?(string(record["head"], "inherited worktree head")),
             "inherited worktree head must be a full commit id")
      string(record["branch"], "inherited worktree branch")
      assert(%w[
        INHERITED_TERMINAL_OUT_OF_SCOPE_NOT_CURRENT
        INHERITED_CLOSED_OUT_OF_SCOPE_NOT_CURRENT
      ].include?(record["status"]),
             "inherited worktree status is not closed and out of scope")
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

  def validate_phase_recovery_hold(truth)
    project = hash(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[
        schema_version route_id status execution_status scheduling_status phase
        phase_entry_status policy founder_phase_route_decision_required
        next_eligible_action missing_exit_items external_effects additional_write_roots
        inherited_worktree_inventory_source
      ],
      "current_phase_route strict recovery hold"
    )
    assert(route["schema_version"] == "strict-phase-recovery-hold/v1",
           "strict recovery route schema drift")
    assert(route["route_id"] == "P1_STRICT_SEQUENCE_RECOVERY_PENDING_TASK_SELECTION",
           "strict recovery route id drift")
    assert(route["status"] == "AUTHORIZED_READY" &&
           route["execution_status"] == "STRICT_PHASE_RECOVERY_HOLD_READY_FOR_P1_TASK_SELECTION" &&
           route["scheduling_status"] == "READY_FOR_P1_EXIT_TASK_SELECTION",
           "strict recovery route lifecycle drift")
    assert(project["current_phase"] == "P1" && route["phase"] == "P1" &&
           route["phase_entry_status"] == "AUTHORIZED",
           "strict recovery route is not aligned to P1")
    assert(project["p1_execution_status"] == "PARTIAL_EXIT_WITH_DISCLOSED_RESIDUALS_6_OF_8_75_PERCENT" &&
           project["p2_entry_status"] == "HOLD_PENDING_STRICT_P1_EXIT" &&
           project["p2_execution_status"] == "HOLD_PENDING_STRICT_P1_EXIT",
           "strict recovery project state drift")
    assert(route["founder_phase_route_decision_required"] == false &&
           route["next_eligible_action"] == "SELECT_HIGHEST_VALUE_P1_EXIT_TASK",
           "strict recovery scheduling authority drift")
    validate_external_effects(
      route["external_effects"],
      "strict recovery external effects",
      FALSE_EXTERNAL_EFFECTS
    )
    assert(route["additional_write_roots"] == [], "strict recovery may not grant write roots")
    ledger = hash(truth["strict_phase_gate_ledger"], "strict_phase_gate_ledger")
    p1 = hash(hash(ledger["phases"], "strict_phase_gate_ledger.phases")["P1"], "strict P1 Gate")
    items = hash(p1["required_items"], "strict P1 required items")
    missing = items.each_with_object([]) do |(item_id, item), result|
      result << item_id unless item.is_a?(Hash) && item["status"] == "ACCEPTED"
    end
    assert(p1["status"] == "INCOMPLETE" && !missing.empty?,
           "strict recovery hold requires a dynamically incomplete P1 Gate")
    assert(route["missing_exit_items"] == missing, "strict recovery route missing-item projection drift")
    active = hash(truth["active_work"], "active_work")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE",
           "strict recovery hold requires Task NONE")
    goal = hash(truth["goal"], "goal")
    assert(goal["current_task_authority"] == "NONE",
           "strict recovery hold requires Goal Task authority NONE")
    historical = hash(
      truth[route["inherited_worktree_inventory_source"]],
      route["inherited_worktree_inventory_source"]
    )
    assert(historical["phase"] == "P2" &&
           historical["status"] == "TERMINAL_TASK_1_NON_PASS" &&
           historical["scheduling_status"] == "STOPPED_AT_FOUNDER_P2_PHASE_GATE",
           "historical P2 terminal route boundary drift")
    "READY_NONE"
  end

  def validate_strict_p1_claim_projection(truth)
    ledger = hash(truth["strict_phase_gate_ledger"], "strict_phase_gate_ledger")
    phases = hash(ledger["phases"], "strict_phase_gate_ledger.phases")
    p1 = hash(phases["P1"], "strict P1 Gate")
    item_ids = array(p1["required_item_ids"], "strict P1 required item ids")
    items = hash(p1["required_items"], "strict P1 required items")
    assert(item_ids == items.keys && !item_ids.empty?,
           "strict P1 required item ordering or set drift")
    accepted_count = item_ids.count do |item_id|
      item = hash(items[item_id], "strict P1 required item #{item_id}")
      item["status"] == "ACCEPTED"
    end
    percent = (accepted_count * 100) / item_ids.length
    expected = "#{accepted_count}_OF_#{item_ids.length}_#{percent}_PERCENT"
    boundary = hash(truth["claim_boundary"], "claim_boundary")
    assert(boundary["p1_strict_completion"] == expected,
           "claim-boundary strict P1 completion drifts from the authoritative Gate ledger")
    expected
  end

  def validate!
    root = git(Dir.pwd, "rev-parse", "--show-toplevel").first.strip
    truth_path = File.join(root, "docs/aios/truth/project_state.yaml")
    truth = parse_yaml(secure_read(truth_path, "canonical Truth"), "canonical Truth")
    assert(truth["record_type"] == "sourcelens_aios_current_truth", "unexpected Truth record_type")
    validate_strict_p1_claim_projection(truth)
    validate_repository_and_worktrees(root, truth)
    validate_goal(truth)
    validate_authority_documents(root, truth)
    route = hash(truth["current_phase_route"], "current_phase_route")
    delegation = truth["phase_delegation"]
    if delegation.is_a?(Hash) &&
       delegation["decision_source"].to_s.include?("V1_8_NON_DOWNGRADE_DIRECTIVE")
      assert(truth["phase_execution_envelope"].is_a?(Hash),
             "active Phase delegation requires a phase execution envelope")
      assert([
        FounderDelegationContinuity::CONTINUATION_ROUTE_SCHEMA,
        FounderDelegationContinuity::RESERVED_ROUTE_SCHEMA,
        FounderDelegationContinuity::STRATEGIC_HOLD_ROUTE_SCHEMA,
        DELEGATED_TASK_ROUTE_SCHEMA
      ].include?(route["schema_version"]),
             "active Phase delegation requires a closed delegated Route schema")
    end
    return validate_phase_recovery_hold(truth) if
      route["schema_version"] == "strict-phase-recovery-hold/v1"
    if route["schema_version"] == FounderDelegationContinuity::CONTINUATION_ROUTE_SCHEMA
      disposition = FounderDelegationContinuity.validate_truth!(root: root, truth: truth)
      assert(disposition == FounderDelegationContinuity::CONTINUE_DISPOSITION,
             "delegated continuation hold requires autonomous Phase continuation")
      return "READY_NONE"
    end
    if route["schema_version"] == FounderDelegationContinuity::RESERVED_ROUTE_SCHEMA
      disposition = FounderDelegationContinuity.validate_truth!(root: root, truth: truth)
      assert(disposition == FounderDelegationContinuity::FOUNDER_DISPOSITION,
             "Founder reserved hold requires an exact reserved trigger")
      return "FOUNDER_RESERVED_DECISION"
    end
    if route["schema_version"] == FounderDelegationContinuity::STRATEGIC_HOLD_ROUTE_SCHEMA
      disposition = FounderDelegationContinuity.validate_truth!(root: root, truth: truth)
      assert(disposition == FounderDelegationContinuity::STRATEGIC_HOLD_DISPOSITION,
             "Founder strategic hold requires an exact resolved decision")
      return "FOUNDER_RESOLVED_STRATEGIC_HOLD"
    end
    if route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA
      return validate_phase_delegated_task(root, truth)
    end
    route, route_id, first_task, _accepted, claims = validate_route(root, truth)
    first_task_in_history = historical_task_ids(truth).include?(first_task["task_id"])
    if %w[ELIGIBLE_NOT_ACTIVATED ACTIVE].include?(first_task["status"])
      assert(!first_task_in_history, "first Task id reuses historical Truth while eligible or active")
    end
    if hash(truth["active_work"], "active_work")["current_task"] == "NONE"
      validate_none_state(root, truth, route, first_task, claims)
      route["status"] == "PHASE_GATE_READY" ? "PHASE_GATE_READY" : "READY_NONE"
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

#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

class AuthorityValidationError < StandardError; end

module CurrentTaskAuthority
  module_function

  SHA256_RE = /\A[0-9a-f]{64}\z/.freeze
  COMMIT_RE = /\A[0-9a-f]{40}\z/.freeze
  SAFE_TASK_ID_RE = /\AAIOS-P1-[0-9]{3}(?:_[A-Z0-9_]+)?\z/.freeze
  EXTERNAL_EFFECT_KEYS = %w[network provider secret remote production public].freeze
  ACTIVE_STATUSES = %w[ACTIVE AUTHORIZED_ACTIVE EXECUTING].freeze
  AUTHORIZED_ROUTE_STATUSES = %w[AUTHORIZED_READY ACTIVE].freeze
  ROUTE_PACKET_SHA256 = "7320cebe730c076c3ec273469e908f33cfdd865079845b690089043a49955f19".freeze
  ROUTE_PACKET_BYTE_LENGTH = 21_400
  GOAL_RAW_SHA256 = "28bc384fbac9d69c6de3ef8709a5be5a0473309b0fe0e54b01bead13d4fa9cf1".freeze
  GOAL_RAW_BYTE_LENGTH = 19_433
  GOAL_CANONICAL_SHA256 = "b1be2cb56da4a1ad8b16fb3d8e8d5ccc413c047da30bd4cbdb161ebc1df5f70a".freeze
  GOAL_CANONICAL_BYTE_LENGTH = 19_434

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

  def validate_external_effects(value, label)
    effects = hash(value, label)
    assert(effects.keys.sort == EXTERNAL_EFFECT_KEYS.sort, "#{label} must contain exactly the six external-effect keys")
    EXTERNAL_EFFECT_KEYS.each { |key| exact_false(effects[key], "#{label}.#{key}") }
  end

  def one_packet_match(text, pattern, label)
    matches = text.scan(pattern)
    assert(matches.length == 1, "decision packet must contain exactly one #{label}")
    match = matches.first
    match.is_a?(Array) && match.length == 1 ? match.first : match
  end

  def packet_claims(packet_bytes)
    text = packet_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(text.valid_encoding?, "decision packet must be valid UTF-8")
    route_id = one_packet_match(text, /Route ID：`([^`]+)`/, "Route ID declaration")
    first_task_id = one_packet_match(text, /Task ID：`([^`]+)`/, "first Task ID declaration")
    authorization_token = one_packet_match(
      text,
      /Founder Project-Level Route Decision — ([A-Z0-9_]+)/,
      "Founder authorization token declaration"
    )
    envelope = one_packet_match(
      text,
      /新路线 Phase envelope 为最多 (\d+) 个工程 Task、(\d+) engineering hours、(\d+) calendar days/,
      "Phase envelope declaration"
    )
    first_task_budget = one_packet_match(
      text,
      /预算：`(\d+) engineering hours \/ (\d+) calendar days`，最多([一二两三四五六七八九十]+)次同 Task implementation iteration，([一二两三四五六七八九十]+)个最终 candidate/,
      "first Task budget declaration"
    )
    contract_corrections = one_packet_match(
      text,
      /每个 Task 一份最小 working Contract，最多([一二两三四五六七八九十]+)次[^\n]+contract correction/,
      "per-Task contract correction declaration"
    )
    same_task_repairs = one_packet_match(
      text,
      /initial implementation 加([一二两三四五六七八九十]+)次同 Task bounded repair/,
      "same-Task repair declaration"
    )
    parent = one_packet_match(
      text,
      /canonical repository 为 `[^`]+`，`main` clean，当前 HEAD 为 `([0-9a-f]{40})`，tree 为 `([0-9a-f]{40})`/,
      "activation parent declaration"
    )
    {
      "route_id" => route_id,
      "first_task_id" => first_task_id,
      "authorization_token" => authorization_token,
      "max_engineering_tasks" => Integer(envelope[0], 10),
      "max_engineering_hours" => Integer(envelope[1], 10),
      "max_calendar_days" => Integer(envelope[2], 10),
      "first_task_engineering_hours" => Integer(first_task_budget[0], 10),
      "first_task_calendar_days" => Integer(first_task_budget[1], 10),
      "first_task_implementation_iterations" => chinese_integer(first_task_budget[2]),
      "first_task_candidates" => chinese_integer(first_task_budget[3]),
      "max_contract_corrections_per_task" => chinese_integer(contract_corrections),
      "max_same_task_repairs" => chinese_integer(same_task_repairs),
      "activation_parent_commit" => parent[0],
      "activation_parent_tree" => parent[1],
      "text" => text
    }
  rescue ArgumentError
    fail!("decision packet contains a non-integer Phase envelope")
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
    assert(packet["sha256"] == ROUTE_PACKET_SHA256 && packet["byte_length"] == ROUTE_PACKET_BYTE_LENGTH,
           "Truth does not bind the authorized route decision packet identity")
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
    validate_external_effects(envelope["external_effects"], "current_phase_route.envelope.external_effects")
    %w[max_engineering_tasks max_engineering_hours max_calendar_days].each do |key|
      assert(envelope[key] == claims[key], "route envelope #{key} does not match exact decision packet")
    end
    %w[max_contract_corrections_per_task max_same_task_repairs].each do |key|
      assert(envelope[key] == claims[key], "route envelope #{key} does not match exact decision packet")
    end

    accepted = hash(route["accepted_inputs"], "current_phase_route.accepted_inputs")
    assert(!accepted.empty?, "current_phase_route.accepted_inputs must not be empty")
    accepted.each do |input_id, record_value|
      record = hash(record_value, "accepted input #{input_id}")
      string(record["task_id"], "accepted input #{input_id}.task_id")
      assert(record["status"].to_s.include?("ACCEPTED") || record["status"].to_s.include?("COMPLETE"),
             "accepted input #{input_id} is not accepted")
      validate_commit_tree(root, record["accepted_candidate_commit"], record["accepted_candidate_tree"],
                           "accepted input #{input_id}")
      _out, _err, ancestor_status = git(root, "merge-base", "--is-ancestor",
                                         record["accepted_candidate_commit"], "HEAD", allow_failure: true)
      assert(ancestor_status.success?, "accepted input #{input_id} is not an ancestor of canonical HEAD")
      contract_path = repo_path(root, record["task_contract_path"], "accepted input #{input_id}.task_contract_path")
      validate_sha_only(contract_path, record["task_contract_sha256"], "accepted input #{input_id} contract")
      historical_contract = git(root, "show",
                                "#{record['accepted_candidate_commit']}:#{record['task_contract_path']}").first
      assert(sha256(historical_contract) == record["task_contract_sha256"],
             "accepted input #{input_id} commit does not bind the declared contract bytes")
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
    assert(claims["text"].include?(goal["observed_raw_body_sha256"].to_s) &&
           claims["text"].include?(goal["observed_body_sha256"].to_s),
           "Goal identities are not bound by the exact decision packet")
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

    validate_external_effects(active["external_effects"], "active_work.external_effects")
    validate_external_effects(contract_field(contract, "external_effects"), "contract external_effects")
    validate_external_effects(contract_field(authority_record, "external_effects"), "authority external_effects")
    exact_false(active["founder_decision_required"], "active_work.founder_decision_required")
    assert(active["founder_reserved_authorization"].nil? && active["founder_reserved_authorization_sha256"].nil?,
           "active cooperative-local Task must not claim Founder-reserved authorization")

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

  def validate!
    root = git(Dir.pwd, "rev-parse", "--show-toplevel").first.strip
    truth_path = File.join(root, "docs/aios/truth/project_state.yaml")
    truth = parse_yaml(secure_read(truth_path, "canonical Truth"), "canonical Truth")
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
      validate_active_state(root, truth, route, route_id, first_task)
      "ACTIVE_TASK"
    end
  end
end

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

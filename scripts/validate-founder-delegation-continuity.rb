#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "psych"
require "yaml"

class FounderDelegationContinuityError < StandardError; end
class FounderDelegationDuplicateJsonKeyError < StandardError; end

class FounderDelegationClosedJsonHash < Hash
  def []=(key, value)
    raise FounderDelegationDuplicateJsonKeyError, key if key?(key)
    super
  end
end

module FounderDelegationContinuity
  module_function

  POLICY_PATH = "docs/aios/FOUNDER_DELEGATION_POLICY.md"
  POLICY_VERSION = "1.8"
  CONTINUATION_ROUTE_SCHEMA = "phase-delegated-continuation-hold/v1"
  RESERVED_ROUTE_SCHEMA = "founder-reserved-decision-hold/v1"
  STRATEGIC_HOLD_ROUTE_SCHEMA = "founder-resolved-strategic-hold/v1"
  DELEGATED_TASK_ROUTE_SCHEMA = "phase-delegated-independent-task/v1"
  DELEGATION_AMENDMENT_SCHEMA = "founder-phase-delegation-amendment/v1"
  DELEGATION_AMENDMENT_ID = "FOUNDER_PHASE_DELEGATION_CONTINUITY_AMENDMENT_2026_08_08"
  CONTINUE_ACTION = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
  SINGLE_TASK_READY_EVENT = "FOUNDER_EXPANDED_SINGLE_TASK_READY"
  SINGLE_TASK_ACTIVE_EVENT = "FOUNDER_EXPANDED_SINGLE_TASK_ACTIVE"
  CONTINUE_DISPOSITION = "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
  FOUNDER_DISPOSITION = "FOUNDER_DECISION_REQUIRED"
  STRATEGIC_HOLD_DISPOSITION = "FOUNDER_RESERVED_DECISION_RESOLVED_STRATEGIC_HOLD"
  STRATEGIC_HOLD_STATUS = "TERMINAL_RESEARCH_NON_PASS_STRATEGIC_HOLD"
  STRATEGIC_HOLD_ACTION = "NO_ENGINEERING_ACTION_STRATEGIC_HOLD"
  STRATEGIC_HOLD_DECISION_SCHEMA =
    "founder-p2-terminal-research-non-pass-strategic-hold-decision/v1"
  FALSE_EXTERNAL_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze
  PRE_CANDIDATE_TERMINAL_RECEIPT_ADAPTERS = {
    "phase-delegated-pre-candidate-dev-iteration-exhausted-terminal-receipt/v1" => {
      "formal_dev_repeat_count" => 3,
      "run_receipt_schema" => "p2-064-formal-dev-repeat-003-terminal-run-receipt/v1",
      "full_inventory_schema" => "p2-064-formal-dev-repeat-003-full-file-inventory/v1",
      "full_inventory_projection" => {
        "file_count" => 453,
        "directory_count" => 212,
        "symlink_count" => 0,
        "aggregate_regular_file_bytes" => 3_212_007,
        "file_projection_sha256" =>
          "0901133df7485bf8087d937d2b3f65629144b95cbe85d75f76f928dd7e0e148d",
        "directory_projection_sha256" =>
          "40d3b7ab3c68a9afcb11dbc12bb34d002076d49c78470ecc35ecd293d1944564",
        "run_root" => "/private/tmp/p2-064-dev-adapter-preflight/formal-dev-repeat-003"
      }.freeze,
      "quality_receipt_schema" => "p2-064-quality-terminal-non-pass-receipt/v1",
      "terminal_review_schema" => "p2-064-independent-terminal-task-review-receipt/v1",
      "snapshot_manifest_schema" => "p2-064-terminal-product-dirty-snapshot-manifest/v1",
      "patch_replay_schema" => "p2-064-terminal-product-dirty-patch-replay-verification/v1",
      "quality_capability_credit_path" =>
        %w[capability_and_phase_effect p2_064_capability_credit].freeze,
      "review_capability_credit_path" =>
        %w[product_review_and_capability_boundary p2_064_capability_credit].freeze
    }.freeze
  }.freeze
  RESERVED_TRIGGERS = %w[
    PHASE_ENTRY_OR_EXIT
    MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
    MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
    NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT
    IRREVERSIBLE_ASSET_REMOVAL
    MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT
    CRITICAL_RESIDUAL_RISK_ACCEPTANCE
  ].freeze
  RESERVED_EVENT_KINDS = {
    "PHASE_ENTRY_OR_EXIT" => "PHASE_EXIT_GATE_ELIGIBLE",
    "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" => "FOUNDER_RESERVED_STRATEGY_CHANGE_REQUESTED",
    "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE" =>
      "PHASE_ENVELOPE_EXPANSION_REQUIRED",
    "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT" =>
      "EXTERNAL_EFFECT_PERMISSION_REQUIRED",
    "IRREVERSIBLE_ASSET_REMOVAL" => "IRREVERSIBLE_ASSET_ACTION_REQUIRED",
    "MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT" =>
      "MATERIAL_LEGAL_PRIVACY_COMMERCIAL_COMMITMENT_REQUIRED",
    "CRITICAL_RESIDUAL_RISK_ACCEPTANCE" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE_REQUIRED"
  }.freeze
  ORDINARY_TERMINAL_EVENTS = %w[
    TASK_TERMINAL_IMPLEMENTATION_NON_PASS
    TASK_TERMINAL_FINAL_REVIEW_NON_PASS
    TASK_TERMINAL_REPAIR_BUDGET_EXHAUSTED
    TASK_TERMINAL_TASK_BUDGET_EXHAUSTED
    TASK_TERMINAL_CANONICAL_VERIFY_NON_PASS
  ].freeze
  FOUNDER_RESERVED_DECISIONS = %w[
    mission_icp_year_one_or_phase_route_change
    phase_entry_or_exit
    material_scope_budget_or_permission_expansion_beyond_phase_envelope
    network_provider_secret_remote_production_or_public_effect
    irreversible_asset_removal
    material_legal_privacy_commercial_commitment
    critical_residual_risk_acceptance
  ].freeze
  AGENT_DELEGATED_DECISIONS = %w[
    select_reject_sequence_and_freeze_phase_local_tasks
    assign_roles_workers_reviewers_and_disjoint_write_ownership
    authorize_and_execute_local_task_branch_worktree_and_commands
    perform_in_scope_implementation_tests_repairs_evidence_replay_and_rollback
    accept_return_or_terminally_stop_tasks_after_independent_review
    integrate_task_to_local_canonical_main_after_task_gate
    choose_the_next_independent_phase_local_task_after_task_completion_or_stop
    continue_phase_without_founder_reapproval_after_ordinary_task_terminal
  ].freeze
  ESCALATION_CONDITIONS = %w[
    founder_reserved_decision_required
    phase_boundary_or_strategy_conflict
    high_risk_external_effect_required
    irreversible_action_required
    critical_risk_requires_acceptance
  ].freeze
  PHASE_DELEGATION_ANTI_LOOP = {
    "routine_founder_task_approval_required" => false,
    "per_file_or_command_approval_required" => false,
    "route_or_task_may_downgrade_phase_delegation" => false,
    "reviewer_non_pass_may_trigger_founder_gate" => false,
    "phase_gate_requires_exit_gate_eligibility" => true,
    "phase_execution_envelope_survives_route_terminal" => true,
    "ordinary_repairs_stay_in_same_task" => true,
    "successor_replacement_correction_chain_allowed" => false,
    "task_id_hardcoding_in_current_authority_validator_allowed" => false,
    "historical_execution_lineage_reuse_allowed" => false,
    "mandatory_exit_capability_permanent_ban_from_historical_stop" => false,
    "peripheral_work_before_exit_capabilities_allowed" => false
  }.freeze

  def fail!(message)
    raise FounderDelegationContinuityError, message
  end

  def assert(condition, message)
    fail!(message) unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} must be an array")
    value
  end

  def integer(value, label)
    assert(value.is_a?(Integer), "#{label} must be an integer")
    value
  end

  def exact_keys(value, keys, label)
    record = mapping(value, label)
    assert(record.keys.sort == keys.sort, "#{label} keys are not closed")
    record
  end

  def reject_duplicate_keys!(text)
    tree = Psych.parse_stream(text)
    walk = nil
    walk = lambda do |node, location|
      case node
      when Psych::Nodes::Mapping
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          assert(key_node.is_a?(Psych::Nodes::Scalar), "non-scalar YAML key at #{location}")
          key = key_node.value
          assert(!seen.key?(key), "duplicate YAML key at #{location}: #{key}")
          seen[key] = true
          walk.call(value_node, "#{location}.#{key}")
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index { |child, index| walk.call(child, "#{location}[#{index}]") }
      else
        children = node.respond_to?(:children) ? node.children : nil
        children&.each { |child| walk.call(child, location) }
      end
    end
    walk.call(tree, "Truth")
  rescue Psych::SyntaxError => e
    fail!("Truth YAML is invalid: #{e.message}")
  end

  def parse_truth(path)
    pathname = Pathname.new(path)
    assert(pathname.file? && !pathname.symlink?, "Truth must be a non-symlink regular file")
    bytes = pathname.binread
    text = bytes.dup.force_encoding("UTF-8")
    assert(text.valid_encoding?, "Truth encoding is invalid")
    reject_duplicate_keys!(text)
    truth = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
    mapping(truth, "Truth")
  end

  def git(root, *arguments)
    stdout, stderr, status = Open3.capture3("git", *arguments, chdir: root.to_s)
    assert(status.success?, "Git command failed: git #{arguments.join(' ')}: #{stderr.strip}")
    stdout
  end

  def commit_tree_identity!(root, value, label)
    identity = exact_keys(value, %w[commit tree], label)
    commit = identity["commit"].to_s
    tree = identity["tree"].to_s
    assert(commit.match?(/\A[0-9a-f]{40}\z/) && tree.match?(/\A[0-9a-f]{40}\z/),
           "#{label} Git identity is invalid")
    _stdout, _stderr, exists = Open3.capture3(
      "git", "cat-file", "-e", "#{commit}^{commit}", chdir: root.to_s
    )
    assert(exists.success?, "#{label} commit does not exist")
    actual_tree = git(root, "rev-parse", "#{commit}^{tree}").strip
    assert(actual_tree == tree, "#{label} tree does not match its commit")
    identity
  end

  def assert_git_ancestor!(root, ancestor, descendant, label)
    _stdout, _stderr, status = Open3.capture3(
      "git", "merge-base", "--is-ancestor", ancestor, descendant, chdir: root.to_s
    )
    assert(status.success?, "#{label} ancestor relation does not hold")
  end

  def value_at_path(value, path)
    array(path, "schema adapter field path").reduce(value) do |current, key|
      current.is_a?(Hash) ? current[key] : nil
    end
  end

  def parse_yaml_bytes(bytes, label)
    text = bytes.dup.force_encoding("UTF-8")
    assert(text.valid_encoding?, "#{label} encoding is invalid")
    reject_duplicate_keys!(text)
    value = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
    mapping(value, label)
  rescue Psych::SyntaxError => e
    fail!("#{label} YAML is invalid: #{e.message}")
  end

  def truth_at_commit(root, commit, label)
    assert(commit.to_s.match?(/\A[0-9a-f]{40}\z/), "#{label} commit identity is invalid")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{commit}:docs/aios/truth/project_state.yaml", chdir: root.to_s
    )
    assert(status.success?, "#{label} Truth cannot be read: #{stderr.strip}")
    parse_yaml_bytes(bytes, "#{label} Truth")
  end

  def canonical_json_projection(value)
    recursively_sorted = lambda do |item|
      case item
      when Hash
        item.keys.sort.to_h { |key| [key, recursively_sorted.call(item[key])] }
      when Array
        item.map { |child| recursively_sorted.call(child) }
      else
        item
      end
    end
    JSON.generate(recursively_sorted.call(value))
  end

  def route_by_id(truth, route_id)
    candidates = truth.each_value.select do |value|
      value.is_a?(Hash) && value["route_id"] == route_id
    end
    assert(candidates.length == 1, "source Route anchor is missing or ambiguous")
    candidates.first
  end

  def first_truth_anchor!(root, search_literal, label)
    commits = git(
      root,
      "log",
      "--reverse",
      "--format=%H",
      "-S#{search_literal}",
      "--",
      "docs/aios/truth/project_state.yaml"
    ).lines.map(&:strip).reject(&:empty?)
    assert(!commits.empty?, "#{label} has no immutable Git anchor")
    commits.each do |commit|
      bytes, stderr, status = Open3.capture3(
        "git", "show", "#{commit}:docs/aios/truth/project_state.yaml", chdir: root.to_s
      )
      next unless status.success?
      truth = parse_yaml_bytes(bytes, "#{label} anchor Truth")
      return [commit, truth] if yield(truth)
    end
    fail!("#{label} immutable Git anchor could not be resolved")
  end

  def first_task_ledger_anchor!(root, entry, search_literal, label)
    truth_path = "docs/aios/truth/project_state.yaml"
    introduction = git(
      root,
      "log",
      "--reverse",
      "--format=%H",
      "-S#{search_literal}",
      "--",
      truth_path
    ).lines.map(&:strip).reject(&:empty?).first
    assert(introduction, "#{label} has no immutable Git introduction")
    commits = git(
      root,
      "log",
      "--reverse",
      "--format=%H",
      "#{introduction}^..HEAD",
      "--",
      truth_path
    ).lines.map(&:strip).reject(&:empty?)
    commits.each do |commit|
      bytes, _stderr, status = Open3.capture3("git", "show", "#{commit}:#{truth_path}", chdir: root.to_s)
      next unless status.success?

      truth = parse_yaml_bytes(bytes, "#{label} anchor Truth")
      item = array(
        truth.dig("phase_execution_envelope", "task_ledger"),
        "candidate anchored phase execution source task ledger"
      ).find do |candidate|
        next false unless candidate.is_a?(Hash) && candidate["task_id"] == entry["task_id"] &&
                          candidate.keys.sort == entry.keys.sort

        if entry.key?("founder_residual_acceptance")
          candidate.dig("founder_residual_acceptance", "source_founder_packet", "sha256") == search_literal
        else
          candidate.dig("outcome_receipt", "sha256") == search_literal
        end
      end
      return [commit, item] if item
    end
    fail!("#{label} immutable Git anchor could not be resolved")
  end

  def repo_identity_bytes(root, identity, label)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    relative = Pathname.new(record["path"].to_s)
    assert(!relative.absolute?, "#{label} path must be repository-relative")
    clean = relative.cleanpath
    assert(clean.to_s == relative.to_s && clean.to_s != "." && !clean.to_s.start_with?("../"),
           "#{label} path is unsafe")
    path = root.join(clean)
    assert(path.file? && !path.symlink?, "#{label} must be a non-symlink regular file")
    assert(path.realpath.to_s.start_with?(root.realpath.to_s + File::SEPARATOR),
           "#{label} escapes the repository")
    bytes = path.binread
    assert(bytes.bytesize == record["byte_length"], "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == record["sha256"], "#{label} SHA-256 mismatch")
    bytes
  end

  def validate_identity(identity, label)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    path = Pathname.new(record["path"].to_s)
    assert(path.absolute?, "#{label} path must be absolute")
    stat = path.lstat
    assert(stat.file? && !stat.symlink?, "#{label} must be a non-symlink regular file")
    assert(stat.nlink == 1, "#{label} must not be hardlinked")
    clean = path.cleanpath
    assert(path.realpath == clean, "#{label} path resolves through a symlink")
    bytes = path.binread
    assert(bytes.bytesize == record["byte_length"], "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == record["sha256"], "#{label} SHA-256 mismatch")
    bytes
  end

  def validate_repair_accounting!(value, authorized_repair_capacity, remaining_repairs, label)
    accounting = exact_keys(
      value,
      %w[authorized used remaining classification receipt],
      label
    )
    authorized = integer(accounting["authorized"], "#{label}.authorized")
    used = integer(accounting["used"], "#{label}.used")
    remaining = integer(accounting["remaining"], "#{label}.remaining")
    assert(authorized >= 0 && authorized <= authorized_repair_capacity &&
           used >= 0 && remaining >= 0 && used + remaining == authorized &&
           remaining == remaining_repairs,
           "#{label} must conserve its bounded same-Task repair allowance and project the exact remaining budget")
    classification = accounting["classification"]
    assert(classification.is_a?(String) && !classification.strip.empty?,
           "#{label} classification must be a non-empty string")
    receipt = exact_keys(
      accounting["receipt"],
      %w[relative_path byte_length sha256],
      "#{label}.receipt"
    )
    relative = Pathname.new(receipt["relative_path"].to_s)
    clean = relative.cleanpath
    assert(!relative.absolute? && clean.to_s == relative.to_s &&
           clean.to_s != "." && clean.to_s != ".." &&
           !clean.to_s.start_with?("../") && !clean.to_s.end_with?("/"),
           "#{label} receipt path is not a safe TASK_EVIDENCE_ROOT-relative path")
    assert(receipt["byte_length"].is_a?(Integer) && receipt["byte_length"].positive? &&
           receipt["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/),
           "#{label} receipt identity is invalid")
    accounting
  end

  def parse_bound_json(identity, label)
    bytes = validate_identity(identity, label)
    value = JSON.parse(
      bytes,
      object_class: FounderDelegationClosedJsonHash,
      array_class: Array,
      create_additions: false
    )
    mapping(value, label)
  rescue JSON::ParserError => e
    fail!("#{label} JSON is invalid: #{e.message}")
  rescue FounderDelegationDuplicateJsonKeyError => e
    fail!("#{label} contains duplicate JSON key: #{e.message}")
  end

  def validate_policy!(root, truth)
    authority = mapping(truth["authority"], "authority")
    policy = exact_keys(
      authority["founder_delegation_policy"],
      %w[path version sha256 status],
      "authority.founder_delegation_policy"
    )
    assert(policy["path"] == POLICY_PATH, "Founder delegation policy path drift")
    assert(policy["version"].to_s == POLICY_VERSION, "Founder delegation policy version drift")
    assert(policy["status"] == "FOUNDER_DIRECTIVE_ACTIVE", "Founder delegation policy is not active")
    path = root.join(POLICY_PATH)
    assert(path.file? && !path.symlink?, "Founder delegation policy file missing or symlinked")
    assert(Digest::SHA256.file(path).hexdigest == policy["sha256"],
           "Founder delegation policy SHA-256 drift")
    _anchor_commit, anchor_truth = first_truth_anchor!(root, "version: \"1.8\"", "Founder delegation policy") do |candidate|
      candidate.dig("authority", "founder_delegation_policy", "version").to_s == POLICY_VERSION
    end
    anchor_policy = mapping(
      mapping(anchor_truth["authority"], "Founder delegation policy anchor authority")["founder_delegation_policy"],
      "Founder delegation policy anchor"
    )
    assert(anchor_policy.slice("path", "version", "sha256", "status") == policy,
           "Founder delegation policy identity drifts from its first canonical Git anchor")
    policy
  end

  def validate_delegation_amendment!(root, identity, phase, policy)
    amendment = parse_bound_json(identity, "Founder delegation continuity amendment")
    exact_keys(
      amendment,
      %w[
        schema_version record_type decision_id phase effective_policy delegated_authority
        constraints claim_boundary
      ],
      "Founder delegation continuity amendment"
    )
    assert(amendment["schema_version"] == DELEGATION_AMENDMENT_SCHEMA &&
           amendment["record_type"] == "founder_phase_delegation_amendment" &&
           amendment["decision_id"] == DELEGATION_AMENDMENT_ID && amendment["phase"] == phase,
           "Founder delegation continuity amendment identity drift")
    assert(exact_keys(amendment["effective_policy"], %w[path version], "delegation amendment policy") ==
           policy.slice("path", "version"),
           "delegation amendment policy binding drift")
    assert(exact_keys(
      amendment["delegated_authority"],
      %w[
        select_new_independent_task_after_ordinary_terminal
        reallocate_unused_task_specific_capacity_within_same_phase_objective
        founder_reapproval_required
      ],
      "delegation amendment authority"
    ) == {
      "select_new_independent_task_after_ordinary_terminal" => true,
      "reallocate_unused_task_specific_capacity_within_same_phase_objective" => true,
      "founder_reapproval_required" => false
    }, "delegation amendment authority drift")
    assert(exact_keys(
      amendment["constraints"],
      %w[
        numeric_phase_ceiling_expansion_allowed external_effect_expansion_allowed
        phase_change_allowed rejected_lineage_reuse_allowed successor_or_replacement_chain_allowed
        maximum_active_tasks maximum_task_branches maximum_task_worktrees maximum_active_candidates
      ],
      "delegation amendment constraints"
    ) == {
      "numeric_phase_ceiling_expansion_allowed" => false,
      "external_effect_expansion_allowed" => false,
      "phase_change_allowed" => false,
      "rejected_lineage_reuse_allowed" => false,
      "successor_or_replacement_chain_allowed" => false,
      "maximum_active_tasks" => 1,
      "maximum_task_branches" => 1,
      "maximum_task_worktrees" => 1,
      "maximum_active_candidates" => 1
    }, "delegation amendment constraints drift")
    assert(amendment["claim_boundary"].is_a?(String) && !amendment["claim_boundary"].empty?,
           "delegation amendment claim boundary missing")

    _anchor_commit, anchor_truth = first_truth_anchor!(root, identity["sha256"],
                                                       "Founder delegation continuity amendment") do |candidate|
      candidate.dig("phase_execution_envelope", "authority_basis", "delegation_amendment", "sha256") ==
        identity["sha256"]
    end
    anchored = anchor_truth.dig("phase_execution_envelope", "authority_basis", "delegation_amendment")
    assert(anchored == identity,
           "Founder delegation continuity amendment drifts from its first canonical Git anchor")
    amendment
  end

  def validate_phase_delegation!(truth, phase)
    delegation = exact_keys(
      truth["phase_delegation"],
      %w[
        status model decision_source phase_gate_owner task_selection_owner
        task_authorization_owner task_gate_owner founder_reserved_decisions
        agent_delegated_decisions escalation_conditions anti_loop claim_boundary
      ],
      "phase_delegation"
    )
    assert([
      "ACTIVE_#{phase}_PHASE_DELEGATION",
      "ACTIVE_#{phase}_PHASE_DELEGATED_CONTINUATION"
    ].include?(delegation["status"]),
           "Phase delegation status drift")
    assert(delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION",
           "Phase delegation model drift")
    assert(delegation["decision_source"].to_s.include?("V1_8_NON_DOWNGRADE_DIRECTIVE"),
           "Phase delegation decision source drift")
    assert(delegation["phase_gate_owner"] == "HUMAN_FOUNDER" &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT_WITHIN_CURRENT_PHASE_ENVELOPE" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT_AFTER_REQUIRED_INDEPENDENT_REVIEW",
           "Phase delegation ownership drift")
    assert(delegation["founder_reserved_decisions"] == FOUNDER_RESERVED_DECISIONS,
           "Founder reserved decision set drift")
    assert(delegation["agent_delegated_decisions"] == AGENT_DELEGATED_DECISIONS,
           "Agent delegated decision set drift")
    assert(delegation["escalation_conditions"] == ESCALATION_CONDITIONS,
           "Founder escalation condition set drift")
    anti_loop = exact_keys(
      delegation["anti_loop"],
      PHASE_DELEGATION_ANTI_LOOP.keys + ["maximum_same_task_bounded_contract_repairs"],
      "phase_delegation.anti_loop"
    )
    PHASE_DELEGATION_ANTI_LOOP.each do |key, expected|
      assert(anti_loop[key] == expected, "Phase delegation anti-loop control drift: #{key}")
    end
    assert(integer(anti_loop["maximum_same_task_bounded_contract_repairs"],
                   "phase_delegation maximum same-Task repairs").positive?,
           "Phase delegation same-Task repair ceiling must be positive")
    assert(delegation["claim_boundary"].is_a?(String) && !delegation["claim_boundary"].empty?,
           "Phase delegation claim boundary missing")
    delegation
  end

  def historical_route_ref!(truth, route)
    reference = route["historical_terminal_route_ref"]
    inventory_reference = route["inherited_worktree_inventory_source"]
    assert(reference.is_a?(String) &&
           reference.match?(/\Ahistorical_p(?:0|[1-9]|1[0-2])_[a-z0-9_]+_phase_route\z/),
           "historical terminal route reference is invalid")
    assert(inventory_reference == reference,
           "historical terminal route and worktree inventory references diverge")
    mapping(truth[reference], reference)
    reference
  end

  def phase_gate_state(truth, phase)
    phases = mapping(mapping(truth["strict_phase_gate_ledger"], "strict_phase_gate_ledger")["phases"],
                     "strict_phase_gate_ledger.phases")
    record = mapping(phases[phase], "strict phase record #{phase}")
    items = mapping(record["required_items"], "strict phase required items #{phase}")
    ids = array(record["required_item_ids"], "strict phase required item ids #{phase}")
    assert(ids == items.keys, "strict phase required item ordering or set drift")
    accepted = items.values.all? { |item| item.is_a?(Hash) && item["status"] == "ACCEPTED" }
    gate = mapping(record["founder_phase_gate"], "strict phase Founder gate #{phase}")
    [record, accepted, gate["status"]]
  end

  def source_route_static_projection(route)
    {
      "route_id" => route["route_id"],
      "phase" => route["phase"],
      "phase_entry_status" => route["phase_entry_status"],
      "authorization_token" => route["authorization_token"],
      "decision_packet" => route["decision_packet"],
      "original_founder_packet" => route["original_founder_packet"],
      "activation_parent" => route["activation_parent"],
      "goal_identity" => route["goal_identity"],
      "objective" => route["objective"],
      "claim_boundary" => route["claim_boundary"],
      "envelope" => route["envelope"],
      "founder_reserved_profile" => route["founder_reserved_profile"],
      "founder_reserved_profiles" => route["founder_reserved_profiles"],
      "exact_reserved_trigger" => route["exact_reserved_trigger"],
      "prior_consumed_envelope" => route["prior_consumed_envelope"],
      "new_task_ids" => route["new_task_ids"],
      "automatic_entry" => route["automatic_entry"],
      "automatic_entries" => route["automatic_entries"],
      "task_plan" => array(route["task_plan"], "source Route task plan").map do |task|
        mapping(task, "source Route Task").reject { |key, _value| key == "status" }
      end
    }
  end

  def validate_source_route_authority!(root, historical_route)
    route_id = historical_route["route_id"]
    _anchor_commit, anchor_truth = first_truth_anchor!(root, route_id, "Phase source Route") do |candidate|
      candidate.any? do |_key, value|
        value.is_a?(Hash) && value["route_id"] == route_id
      end
    end
    anchor_route = route_by_id(anchor_truth, route_id)
    assert(source_route_static_projection(historical_route) == source_route_static_projection(anchor_route),
           "historical source Route static authority drifts from its first canonical Git anchor")

    decision = parse_bound_json(
      historical_route["decision_packet"],
      "phase execution envelope source decision"
    )
    decision_schema = decision["schema_version"]
    decision_keys = %w[
      activation_parent authorization_token automatic_entries automatic_entry claim_boundary
      envelope external_effects goal_identity ordered_tasks phase record_type route_id
      schema_version source_founder_packet_identity
    ]
    decision_keys.concat(%w[exact_reserved_trigger new_task_ids prior_consumed_envelope]) if
      decision_schema == "1.2"
    exact_keys(decision, decision_keys, "phase execution envelope source decision")
    assert(decision["record_type"] == "founder_phase_route_decision" &&
           %w[1.1 1.2].include?(decision_schema),
           "phase execution envelope requires a structured Founder route decision v1.1 or v1.2")
    assert(decision["phase"] == historical_route["phase"] &&
           decision["route_id"] == historical_route["route_id"] &&
           decision["authorization_token"] == historical_route["authorization_token"],
           "phase execution envelope source decision identity drift")
    assert(decision["activation_parent"] == historical_route["activation_parent"],
           "source Route activation parent drifts from structured Founder decision")
    assert(decision["automatic_entry"] == historical_route["automatic_entry"] &&
           decision["automatic_entries"] == historical_route["automatic_entries"],
           "source Route automatic-entry semantics drift from structured Founder decision")
    if decision_schema == "1.2"
      assert(decision["exact_reserved_trigger"] ==
               "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE" &&
             historical_route["exact_reserved_trigger"] == decision["exact_reserved_trigger"],
             "single-Task expansion exact reserved trigger drift")
      assert(decision["automatic_entry"].nil? && decision["automatic_entries"] == [],
             "single-Task expansion decision must have no automatic successor")
      assert(decision["new_task_ids"] == historical_route["new_task_ids"],
             "source Route new Task set drifts from structured Founder decision")
      assert(decision["prior_consumed_envelope"] == historical_route["prior_consumed_envelope"],
             "source Route prior consumed accounting drifts from structured Founder decision")
    end
    assert(decision["claim_boundary"] == historical_route["claim_boundary"] &&
           decision["goal_identity"] == historical_route["goal_identity"],
           "source Route claim or Goal binding drifts from structured Founder decision")
    source_identity = exact_keys(
      decision["source_founder_packet_identity"],
      %w[authorization_token path byte_length sha256],
      "phase execution envelope source Founder packet identity"
    )
    assert(source_identity["authorization_token"] == historical_route["authorization_token"],
           "source Founder packet authorization token drift")
    source_file_identity = source_identity.slice("path", "byte_length", "sha256")
    assert(source_file_identity == historical_route["original_founder_packet"],
           "source Founder packet identity drift")
    validate_identity(
      source_file_identity,
      "phase execution envelope source Founder packet"
    )

    decision_envelope = exact_keys(
      decision["envelope"],
      %w[
        max_active_candidates max_active_tasks max_calendar_days max_engineering_hours
        max_engineering_tasks max_same_task_repairs_per_task max_task_branches
        max_task_worktrees p3_entry_authorized
      ],
      "structured Founder route envelope"
    )
    route_envelope = mapping(historical_route["envelope"], "historical route envelope")
    envelope_pairs = {
      "max_active_candidates" => "max_active_candidates",
      "max_active_tasks" => "max_active_tasks",
      "max_calendar_days" => "max_calendar_days",
      "max_engineering_hours" => "max_engineering_hours",
      "max_engineering_tasks" => "max_engineering_tasks",
      "max_same_task_repairs_per_task" => "max_same_task_repairs",
      "max_task_branches" => "max_task_branches",
      "max_task_worktrees" => "max_task_worktrees",
      "p3_entry_authorized" => "p3_entry_authorized"
    }
    envelope_pairs.each do |decision_key, route_key|
      assert(decision_envelope[decision_key] == route_envelope[route_key],
             "historical route envelope drifts from structured Founder decision: #{route_key}")
    end
    assert(decision["external_effects"] == route_envelope["external_effects"],
           "historical route effects drift from structured Founder decision")

    decision_tasks = array(decision["ordered_tasks"], "structured Founder ordered Tasks").map do |task|
      record = exact_keys(
        task,
        %w[
          calendar_days engineering_hours external_effects founder_reserved_profile
          max_candidates max_implementation_iterations max_same_task_repairs task_id task_slot
        ],
        "structured Founder ordered Task"
      )
      assert(record["founder_reserved_profile"].nil?,
             "offline delegated continuation source Task may not carry a Founder profile")
      record.reject { |key, _value| key == "founder_reserved_profile" }
    end
    route_tasks = array(historical_route["task_plan"], "historical route task plan").map do |task|
      record = mapping(task, "historical route Task")
      assert(record["engineering_hours"] == record["max_engineering_hours"] &&
             record["calendar_days"] == record["max_calendar_days"],
             "historical route Task budget aliases drift")
      {
        "calendar_days" => record["calendar_days"],
        "engineering_hours" => record["engineering_hours"],
        "external_effects" => record["external_effects"],
        "max_candidates" => record["max_candidates"],
        "max_implementation_iterations" => record["max_implementation_iterations"],
        "max_same_task_repairs" => record["max_same_task_repairs"],
        "task_id" => record["task_id"],
        "task_slot" => record["task_slot"]
      }
    end
    assert(route_tasks == decision_tasks,
           "historical route Task plan drifts from structured Founder decision")

    if decision_schema == "1.2"
      new_task_ids = array(decision["new_task_ids"], "structured Founder new Task ids")
      assert(new_task_ids.length == 1 && new_task_ids.uniq.length == 1,
             "single-Task expansion decision must authorize exactly one new Task")
      task_ids = decision_tasks.map { |task| task["task_id"] }
      assert(task_ids == new_task_ids && decision_tasks.length == 1 &&
             decision_tasks.first["task_slot"] == 1,
             "single-Task expansion decision must contain only one route-local Task")

      parent_truth = truth_at_commit(
        root,
        decision.dig("activation_parent", "commit"),
        "single-Task expansion activation parent"
      )
      parent_envelope = mapping(
        parent_truth["phase_execution_envelope"],
        "single-Task expansion activation-parent envelope"
      )
      parent_limits = exact_keys(
        parent_envelope["limits"],
        %w[engineering_tasks engineering_hours calendar_days active_tasks task_branches task_worktrees active_candidates],
        "single-Task expansion activation-parent limits"
      )
      parent_consumed = exact_keys(
        parent_envelope["consumed"],
        %w[engineering_tasks engineering_hours calendar_days],
        "single-Task expansion activation-parent consumed"
      )
      parent_remaining = exact_keys(
        parent_envelope["remaining"],
        %w[engineering_tasks engineering_hours calendar_days],
        "single-Task expansion activation-parent remaining"
      )
      assert(parent_envelope["phase"] == historical_route["phase"] &&
             parent_envelope["status"] == "EXHAUSTED" && parent_envelope["reserved"].nil? &&
             parent_remaining.values.all?(&:zero?) &&
             parent_consumed == parent_limits.slice("engineering_tasks", "engineering_hours", "calendar_days"),
             "single-Task expansion requires an exact exhausted activation-parent envelope")
      parent_control = mapping(
        parent_truth["founder_escalation_control"],
        "single-Task expansion activation-parent Founder control"
      )
      assert(parent_control.dig("reserved_trigger", "category") ==
               decision["exact_reserved_trigger"] &&
             parent_control["founder_decision_required"] == true,
             "single-Task expansion does not resolve the exact activation-parent reserved trigger")
      parent_source_ref = parent_envelope.dig("authority_basis", "source_route_ref")
      parent_source_route = mapping(
        parent_truth[parent_source_ref],
        "single-Task expansion activation-parent source Route"
      )
      prior = exact_keys(
        decision["prior_consumed_envelope"],
        %w[
          source_route_id consumed task_ledger_entry_count task_ledger_canonicalization
          task_ledger_canonical_byte_length task_ledger_canonical_sha256
        ],
        "single-Task expansion prior consumed envelope"
      )
      prior_consumed = exact_keys(
        prior["consumed"],
        %w[engineering_tasks engineering_hours calendar_days],
        "single-Task expansion prior consumed totals"
      )
      parent_ledger = array(
        parent_envelope["task_ledger"],
        "single-Task expansion activation-parent Task ledger"
      )
      parent_ledger_bytes = canonical_json_projection(parent_ledger).b
      assert(prior["source_route_id"] == parent_source_route["route_id"] &&
             prior_consumed == parent_consumed &&
             prior["task_ledger_entry_count"] == parent_ledger.length &&
             prior["task_ledger_canonicalization"] == "RECURSIVE_KEY_SORT_COMPACT_JSON_UTF8" &&
             prior["task_ledger_canonical_byte_length"] == parent_ledger_bytes.bytesize &&
             prior["task_ledger_canonical_sha256"] == Digest::SHA256.hexdigest(parent_ledger_bytes),
             "single-Task expansion prior consumed envelope is not hash-bound to activation-parent accounting")

      new_task = decision_tasks.first
      assert(decision_envelope["max_engineering_tasks"] == parent_limits["engineering_tasks"] + 1 &&
             decision_envelope["max_engineering_hours"] == parent_limits["engineering_hours"] + new_task["engineering_hours"] &&
             decision_envelope["max_calendar_days"] == parent_limits["calendar_days"] + new_task["calendar_days"] &&
             decision_envelope["max_same_task_repairs_per_task"] == new_task["max_same_task_repairs"],
             "single-Task expansion envelope delta does not equal its only new Task")
      route_new_tasks = array(historical_route["task_plan"], "single-Task expansion route Task plan")
      route_task_status = route_new_tasks.first["status"].to_s
      route_task_consumed = route_task_status.start_with?("TERMINAL_") ||
                            route_task_status.include?("ACCEPTED")
      assert(route_new_tasks.length == 1 && route_new_tasks.first["task_id"] == new_task_ids.first &&
             (%w[ELIGIBLE_NOT_ACTIVATED ACTIVE].include?(route_task_status) || route_task_consumed),
             "single-Task expansion source capacity must be its only READY, ACTIVE or consumed Task")
      assert(historical_route["first_task"] == route_new_tasks.first,
             "single-Task expansion first Task must exactly equal its sole Task plan entry including lifecycle")
    end
    decision
  end

  def source_capacity_task!(source_route, capacity_source_task_id)
    matches = array(source_route["task_plan"], "source Route task plan").select do |task|
      task.is_a?(Hash) && task["task_id"] == capacity_source_task_id
    end
    assert(matches.length == 1, "delegated Task capacity source is missing or ambiguous")
    source = mapping(matches.first, "delegated Task capacity source")
    assert(source["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "delegated Task capacity source exceeds the offline Phase boundary")
    source
  end

  def validate_founder_terminal_accounting_residual!(entry)
    residual = exact_keys(
      entry["founder_residual_acceptance"],
      %w[
        schema_version authorization_token acceptance_scope source_founder_packet
        preserved_security_review terminal_receipt capability_credit formal_reruns
        terminal_accounting_residual_accepted general_validator_gap_accepted
        rejected_terminal_sync_candidate_accepted security_review_rewritten_as_pass
        production_security_claimed claim_boundary
      ],
      "phase execution Founder terminal accounting residual acceptance"
    )
    assert(residual["schema_version"] == "founder-terminal-accounting-residual-acceptance/v1",
           "Founder terminal accounting residual schema drift")
    assert(residual["authorization_token"].is_a?(String) &&
           !residual["authorization_token"].empty?,
           "Founder terminal accounting residual token is invalid")
    assert(residual["acceptance_scope"] == "EXACT_TERMINAL_STATE_ACCOUNTING_ONLY" &&
           residual["terminal_accounting_residual_accepted"] == true &&
           residual["general_validator_gap_accepted"] == false &&
           residual["rejected_terminal_sync_candidate_accepted"] == false &&
           residual["security_review_rewritten_as_pass"] == false &&
           residual["production_security_claimed"] == false,
           "Founder terminal accounting residual claim boundary drift")
    assert(residual["capability_credit"] == 0 && residual["formal_reruns"] == 0,
           "Founder terminal accounting residual cannot create capability or rerun credit")
    assert(residual["claim_boundary"].is_a?(String) && !residual["claim_boundary"].empty?,
           "Founder terminal accounting residual claim boundary missing")

    packet = exact_keys(
      residual["source_founder_packet"],
      %w[path sha256 byte_length],
      "Founder terminal accounting source packet"
    )
    packet_bytes = validate_identity(packet, "Founder terminal accounting source packet")
    packet_text = packet_bytes.dup.force_encoding(Encoding::UTF_8)
    assert(packet_text.valid_encoding?, "Founder terminal accounting source packet is not UTF-8")
    declaration = "authorization_token=#{residual['authorization_token']}"
    assert(packet_text.lines.count { |line| line.chomp == declaration } == 1,
           "Founder terminal accounting authorization token is not uniquely anchored")

    terminal_receipt = exact_keys(
      residual["terminal_receipt"],
      %w[path sha256 byte_length],
      "Founder terminal accounting terminal receipt"
    )
    assert(terminal_receipt == entry["outcome_receipt"],
           "Founder terminal accounting receipt identity drift")
    validate_identity(terminal_receipt, "Founder terminal accounting terminal receipt")

    review_identity = exact_keys(
      residual["preserved_security_review"],
      %w[path sha256 byte_length],
      "Founder terminal accounting preserved Security Review"
    )
    review = parse_bound_json(review_identity, "Founder terminal accounting preserved Security Review")
    assert(review["task_id"] == entry["task_id"] && review["target_verdict"] == "NON_PASS",
           "Founder terminal accounting does not preserve the exact Security NON_PASS")
    residual
  end

  def validate_predeclared_task_terminal_outcome!(root, entry, contract, receipt,
                                                   ledger_anchor_commit:)
    outcome = exact_keys(
      contract["terminal_outcome"],
      %w[
        status candidate_commit candidate_tree sealed_formal_value_result cto_review
        security_review quality_review terminal_receipt capability_credit
        candidate_integrated canonical_make_verify
      ],
      "predeclared Task terminal outcome"
    )
    assert(outcome["status"] == entry["status"],
           "predeclared Task terminal outcome status drift")
    terminal_receipt = exact_keys(
      outcome["terminal_receipt"],
      %w[path byte_length sha256],
      "predeclared Task terminal receipt"
    )
    assert(terminal_receipt == entry["outcome_receipt"],
           "predeclared Task terminal receipt identity drift")
    assert(outcome["capability_credit"] == 0 && outcome["candidate_integrated"] == false &&
           outcome["canonical_make_verify"].to_s.start_with?("NOT_INVOKED"),
           "predeclared terminal Task cannot create capability, integration or verification credit")

    adapter = PRE_CANDIDATE_TERMINAL_RECEIPT_ADAPTERS[receipt["schema_version"]]
    if adapter
      exact_keys(
        receipt,
        %w[
          activation_parent authorization_effects candidate canonical_before_terminal_sync
          canonical_make_verify capability_credit claim_boundary evidence_bindings
          execution_accounting forbidden_continuations held_validation independent_terminal_review
          next_action outcome prior_product_review recorded_at_utc route_id run003_unknowns
          schema_version task_id terminal_status
        ],
        "phase-delegated pre-candidate DEV iteration-exhausted terminal receipt"
      )
      canonical_sources = array(
        contract["dependencies"], "pre-candidate terminal Contract dependencies"
      ).select { |dependency| dependency.is_a?(Hash) && dependency["kind"] == "CANONICAL_SOURCE" }
      assert(canonical_sources.length == 1,
             "pre-candidate terminal Contract must contain exactly one CANONICAL_SOURCE")
      canonical_source = exact_keys(
        canonical_sources.first,
        %w[kind identity],
        "pre-candidate terminal Contract CANONICAL_SOURCE"
      )
      activation_parent = commit_tree_identity!(
        root,
        receipt["activation_parent"],
        "pre-candidate terminal activation parent"
      )
      contract_activation_parent = commit_tree_identity!(
        root,
        canonical_source["identity"],
        "pre-candidate terminal Contract CANONICAL_SOURCE"
      )
      assert(activation_parent == contract_activation_parent,
             "pre-candidate terminal activation parent drifts from the Contract CANONICAL_SOURCE")
      canonical_before = commit_tree_identity!(
        root,
        receipt["canonical_before_terminal_sync"],
        "pre-candidate canonical-before-terminal-sync"
      )
      assert_git_ancestor!(
        root,
        activation_parent["commit"],
        canonical_before["commit"],
        "pre-candidate activation-parent to canonical-before-terminal-sync"
      )
      assert(ledger_anchor_commit.to_s.match?(/\A[0-9a-f]{40}\z/),
             "pre-candidate terminal ledger introduction anchor is missing")
      resolved_anchor, resolved_entry = first_task_ledger_anchor!(
        root,
        entry,
        entry.dig("outcome_receipt", "sha256"),
        "pre-candidate terminal ledger entry"
      )
      assert(resolved_anchor == ledger_anchor_commit && resolved_entry == entry,
             "pre-candidate terminal ledger entry introduction anchor drift")
      anchor_parents = git(
        root, "rev-list", "--parents", "-n", "1", ledger_anchor_commit
      ).split
      assert(anchor_parents.length == 2 && anchor_parents.first == ledger_anchor_commit,
             "pre-candidate terminal-sync candidate must have exactly one parent")
      assert(anchor_parents.last == canonical_before["commit"] &&
             git(root, "rev-parse", "#{ledger_anchor_commit}^^{tree}").strip ==
               canonical_before["tree"],
             "pre-candidate canonical-before identity is not the exact terminal-sync candidate parent")
      assert(receipt["terminal_status"] == entry["status"],
             "pre-candidate DEV iteration-exhausted terminal status drift")
      assert(receipt["authorization_effects"] == FALSE_EXTERNAL_EFFECTS &&
             receipt["capability_credit"] == 0 &&
             receipt["canonical_make_verify"] == "NOT_INVOKED_TERMINAL_PRE_CANDIDATE_NON_PASS" &&
             !receipt["claim_boundary"].to_s.empty?,
             "pre-candidate DEV iteration-exhausted claim boundary drift")

      candidate = exact_keys(
        receipt["candidate"], %w[commit created frozen integrated tree],
        "pre-candidate DEV iteration-exhausted candidate"
      )
      assert(candidate == {
               "commit" => nil,
               "created" => false,
               "frozen" => false,
               "integrated" => false,
               "tree" => nil
             },
             "pre-candidate DEV iteration-exhausted receipt cannot claim a candidate")
      assert(outcome["candidate_commit"].nil? && outcome["candidate_tree"].nil? &&
             outcome["sealed_formal_value_result"] == "NOT_STARTED_CANDIDATE_ABSENT" &&
             outcome["cto_review"] == "NOT_STARTED_CANDIDATE_ABSENT" &&
             outcome["security_review"] == "NOT_STARTED_CANDIDATE_ABSENT" &&
             outcome["quality_review"] == "NOT_STARTED_CANDIDATE_ABSENT" &&
             outcome["canonical_make_verify"] == receipt["canonical_make_verify"],
             "pre-candidate DEV iteration-exhausted Contract outcome projection drift")

      accounting = exact_keys(
        receipt["execution_accounting"],
        %w[
          admissible_dev_transactions candidate_limit candidates_created_or_frozen
          control_or_treatment_outcomes formal_dev_repeat_count held_entries_opened
          held_identity_or_content_reads held_validation_runs implementation_iterations_authorized
          implementation_iterations_consumed implementation_iterations_remaining
          independent_evaluator_invocations matrix_records metric_comparisons metric_verdicts
          mockmvc_perform_count quality_repairs_authorized quality_repairs_classification
          quality_repairs_consumed quality_repairs_remaining run003_child_exit_code
          run003_init_sent_count run003_run_request_count run003_valid_ready_count
        ],
        "pre-candidate DEV iteration-exhausted accounting"
      )
      contract_budget = mapping(contract["budget"], "pre-candidate terminal Contract budget")
      repairs = mapping(contract["repair_accounting"],
                        "pre-candidate terminal Contract repair accounting")
      assert(accounting["implementation_iterations_authorized"] ==
               contract_budget["implementation_iterations"] &&
             accounting["implementation_iterations_consumed"] ==
               accounting["implementation_iterations_authorized"] &&
             accounting["implementation_iterations_remaining"] == 0 &&
             accounting["candidate_limit"] == contract_budget["candidates"] &&
             accounting["candidates_created_or_frozen"] == 0 &&
             accounting["quality_repairs_authorized"] == repairs["authorized"] &&
             accounting["quality_repairs_consumed"] == repairs["used"] &&
             accounting["quality_repairs_remaining"] == repairs["remaining"] &&
             accounting["quality_repairs_classification"] == repairs["classification"],
             "pre-candidate DEV iteration or repair budget accounting drift")
      assert(accounting["admissible_dev_transactions"] == 0 &&
             accounting["matrix_records"] == 0 &&
             accounting["independent_evaluator_invocations"] == 0 &&
             accounting["metric_comparisons"] == 0 && accounting["metric_verdicts"] == 0 &&
             accounting["mockmvc_perform_count"] == 0 &&
             accounting["held_entries_opened"] == 0 &&
             accounting["held_identity_or_content_reads"] == 0 &&
             accounting["held_validation_runs"] == 0 &&
             accounting["control_or_treatment_outcomes"] == { "A0" => 0, "B0" => 0, "B1" => 0 } &&
             accounting["formal_dev_repeat_count"] == adapter["formal_dev_repeat_count"] &&
             accounting["run003_child_exit_code"].is_a?(Integer) &&
             !accounting["run003_child_exit_code"].zero? &&
             accounting["run003_init_sent_count"] == 1 &&
             accounting["run003_valid_ready_count"] == 0 &&
             accounting["run003_run_request_count"] == 0,
             "pre-candidate DEV iteration-exhausted execution counters drift")

      held = exact_keys(
        receipt["held_validation"],
        %w[candidate_prerequisite_met content_read identity_read opened outcome_read run_count status],
        "pre-candidate DEV iteration-exhausted held validation"
      )
      assert(held == {
               "candidate_prerequisite_met" => false,
               "content_read" => false,
               "identity_read" => false,
               "opened" => false,
               "outcome_read" => false,
               "run_count" => 0,
               "status" => "NOT_OPENED_NOT_RUN_UNCOMPUTED"
             },
             "pre-candidate DEV iteration-exhausted receipt cannot claim held validation")

      terminal = exact_keys(
        receipt["outcome"],
        %w[
          candidate_integrated dev_gate held_validation_result independent_terminal_review
          p2_capability_progress_percent p2_exit_item_status p3_status
          terminal_lifecycle_event_kind
        ],
        "pre-candidate DEV iteration-exhausted outcome"
      )
      assert(terminal == {
               "candidate_integrated" => false,
               "dev_gate" => "NON_PASS_NO_ADMISSIBLE_DEV_MATRIX",
               "held_validation_result" => "NOT_OPENED_NOT_RUN_UNCOMPUTED",
               "independent_terminal_review" => "NON_PASS",
               "p2_capability_progress_percent" => 0,
               "p2_exit_item_status" => "MISSING",
               "p3_status" => "HOLD",
               "terminal_lifecycle_event_kind" => "TASK_TERMINAL_TASK_BUDGET_EXHAUSTED"
             },
             "pre-candidate DEV iteration-exhausted Phase outcome drift")
      next_action = exact_keys(
        receipt["next_action"],
        %w[action founder_decision_required owner reason selected_task_id],
        "pre-candidate DEV iteration-exhausted next action"
      )
      assert(next_action["action"] == "FOUNDER_RESERVED_DECISION" &&
             next_action["founder_decision_required"] == true &&
             next_action["owner"] == "HUMAN_FOUNDER" &&
             next_action["selected_task_id"].nil? &&
             !next_action["reason"].to_s.empty?,
             "pre-candidate DEV iteration-exhausted next action drift")

      unknowns = exact_keys(
        receipt["run003_unknowns"],
        %w[chunk_and_save exact_child_fatal spring_application_context_successfully_returned],
        "pre-candidate DEV iteration-exhausted unknowns"
      )
      assert(unknowns.values.all? { |value| value.to_s.start_with?("UNKNOWN") },
             "pre-candidate DEV iteration-exhausted UNKNOWN boundary drift")
      forbidden = array(receipt["forbidden_continuations"],
                        "pre-candidate DEV iteration-exhausted forbidden continuations")
      assert(%w[
               AUTOMATIC_NEW_P2_TASK CANDIDATE_FREEZE CONTRACT_CORRECTION
               FURTHER_IMPLEMENTATION_ITERATION FURTHER_SAME_TASK_REPAIR HELD_VALIDATION
               P3_ENTRY REPLACEMENT SUCCESSOR V5_OR_FORMAL_DEV_RERUN
             ].all? { |value| forbidden.include?(value) },
             "pre-candidate DEV iteration-exhausted forbidden continuations drift")

      evidence = exact_keys(
        receipt["evidence_bindings"],
        %w[
          formal_dev_repeat_002_quality_adjudication
          formal_dev_repeat_003_full_file_inventory formal_dev_repeat_003_matrix
          formal_dev_repeat_003_terminal_quality_non_pass
          formal_dev_repeat_003_terminal_receipt independent_adapter_review_pass_v4
          independent_terminal_task_review iteration1_product_review
          product_dirty_delta_patch product_dirty_patch_replay_verification
          product_dirty_snapshot_files product_dirty_snapshot_manifest
        ],
        "pre-candidate DEV iteration-exhausted Evidence bindings"
      )
      evidence.each do |key, identity|
        next if key == "product_dirty_snapshot_files"
        validate_identity(
          exact_keys(identity, %w[path byte_length sha256],
                     "pre-candidate DEV Evidence #{key}"),
          "pre-candidate DEV Evidence #{key}"
        )
      end
      full_inventory = parse_bound_json(
        evidence["formal_dev_repeat_003_full_file_inventory"],
        "pre-candidate DEV run003 full file inventory"
      )
      exact_keys(
        full_inventory,
        %w[
          aggregate_regular_file_bytes directory_count directory_projection_sha256
          file_count file_projection_sha256 files run_root schema_version status symlink_count
        ],
        "pre-candidate DEV run003 full file inventory"
      )
      inventory_projection = adapter["full_inventory_projection"]
      inventory_binding_projection = inventory_projection.reject { |key, _value| key == "run_root" }
      assert(full_inventory["schema_version"] == adapter["full_inventory_schema"] &&
             full_inventory["status"] == "TERMINAL_RUN_ROOT_READ_ONLY_FROZEN" &&
             full_inventory.slice(*inventory_projection.keys) == inventory_projection,
             "pre-candidate DEV run003 full inventory projection drift")
      inventory_files = array(
        full_inventory["files"], "pre-candidate DEV run003 full inventory files"
      ).map.with_index do |row, index|
        record = exact_keys(
          row,
          %w[relative_path byte_length sha256 mode nlink],
          "pre-candidate DEV run003 full inventory file[#{index}]"
        )
        relative_path = record["relative_path"]
        assert(relative_path.is_a?(String) && !relative_path.empty? &&
               relative_path.valid_encoding? && !relative_path.include?("\0"),
               "pre-candidate DEV run003 full inventory file[#{index}] path is invalid")
        relative = Pathname.new(relative_path)
        clean = relative.cleanpath
        assert(!relative.absolute? && clean.to_s == relative_path &&
               relative_path != "." && relative_path != ".." &&
               !relative_path.start_with?("../") && !relative_path.end_with?("/"),
               "pre-candidate DEV run003 full inventory file[#{index}] path is unsafe")
        assert(record["byte_length"].is_a?(Integer) && record["byte_length"] >= 0 &&
               record["sha256"].is_a?(String) &&
               record["sha256"].match?(/\A[0-9a-f]{64}\z/) &&
               record["mode"].is_a?(String) && record["mode"].match?(/\A0[0-7]{3}\z/) &&
               record["nlink"].is_a?(Integer) && record["nlink"] == 1,
               "pre-candidate DEV run003 full inventory file[#{index}] identity is invalid")
        record
      end
      inventory_relative_paths = inventory_files.map { |row| row["relative_path"] }
      assert(inventory_files.length == full_inventory["file_count"] &&
             inventory_relative_paths.uniq.length == inventory_relative_paths.length,
             "pre-candidate DEV run003 full inventory file identities are not unique and complete")
      inventory_byte_sum = inventory_files.sum { |row| row["byte_length"] }
      assert(inventory_byte_sum == full_inventory["aggregate_regular_file_bytes"],
             "pre-candidate DEV run003 full inventory aggregate byte sum drift")
      inventory_file_projection = Digest::SHA256.hexdigest(JSON.generate(inventory_files))
      assert(inventory_file_projection == full_inventory["file_projection_sha256"],
             "pre-candidate DEV run003 full inventory file projection drift")
      matrix_basename = File.basename(evidence.dig("formal_dev_repeat_003_matrix", "path").to_s)
      inventory_matrix_rows = inventory_files.select do |row|
        row["relative_path"] == matrix_basename
      end
      assert(inventory_matrix_rows.length == 1,
             "pre-candidate DEV run003 full inventory matrix identity is missing or ambiguous")
      inventory_matrix = inventory_matrix_rows.first
      assert(inventory_matrix == {
               "relative_path" => matrix_basename,
               "byte_length" => evidence.dig("formal_dev_repeat_003_matrix", "byte_length"),
               "sha256" => evidence.dig("formal_dev_repeat_003_matrix", "sha256"),
               "mode" => "0600",
               "nlink" => 1
             } && inventory_matrix["byte_length"] == 0 &&
             inventory_matrix["sha256"] == Digest::SHA256.hexdigest(""),
             "pre-candidate DEV run003 full inventory matrix projection drift")
      snapshot_files = array(evidence["product_dirty_snapshot_files"],
                             "pre-candidate DEV dirty snapshot files")
      assert(snapshot_files.length == 4,
             "pre-candidate DEV dirty snapshot must contain exactly four files")
      snapshot_identity_keys = snapshot_files.map do |identity|
        [identity["path"], identity["byte_length"], identity["sha256"]]
      end
      assert(snapshot_identity_keys.uniq.length == snapshot_identity_keys.length,
             "pre-candidate DEV dirty snapshot identities must be unique")
      snapshot_files.each_with_index do |identity, index|
        validate_identity(
          exact_keys(identity, %w[path byte_length sha256],
                     "pre-candidate DEV dirty snapshot file[#{index}]"),
          "pre-candidate DEV dirty snapshot file[#{index}]"
        )
      end
      snapshot_master_projection = snapshot_files.map do |identity|
        relative = identity["path"].split("/product/dirty-snapshot/", 2)[1]
        assert(relative.is_a?(String) && !relative.empty?,
               "pre-candidate DEV dirty snapshot identity is outside the frozen snapshot root")
        {
          "relative_path" => relative,
          "byte_length" => identity["byte_length"],
          "sha256" => identity["sha256"],
          "final_installed_path" => identity["path"]
        }
      end.sort_by { |row| row["relative_path"] }
      assert(snapshot_master_projection.map { |row| row["relative_path"] }.uniq.length == 4,
             "pre-candidate DEV dirty snapshot relative paths must be unique")

      run = parse_bound_json(
        evidence["formal_dev_repeat_003_terminal_receipt"],
        "pre-candidate DEV run003 terminal receipt"
      )
      exact_keys(
        run,
        %w[
          schema_version task_id created_at_utc status terminal run_root exact_v4_bindings
          run_inputs_and_preflight observed_execution matrix terminal_accounting
          epistemic_boundary mutation_counters
        ],
        "pre-candidate DEV run003 terminal receipt"
      )
      observed = mapping(run["observed_execution"], "pre-candidate DEV run003 observation")
      run_matrix = mapping(run["matrix"], "pre-candidate DEV run003 matrix")
      run_root = exact_keys(
        run["run_root"],
        %w[path preservation_policy full_file_inventory session_root session_root_regular_file_count],
        "pre-candidate DEV run003 root"
      )
      run_inventory = exact_keys(
        run_root["full_file_inventory"],
        %w[
          path byte_length sha256 file_count directory_count symlink_count
          aggregate_regular_file_bytes file_projection_sha256 directory_projection_sha256
        ],
        "pre-candidate DEV run003 full inventory binding"
      )
      run_accounting = mapping(run["terminal_accounting"],
                               "pre-candidate DEV run003 terminal accounting")
      assert(run["schema_version"] == adapter["run_receipt_schema"] &&
             run["task_id"] == entry["task_id"] && run["terminal"] == true &&
             run_root["path"] == full_inventory["run_root"] &&
             run_root["preservation_policy"] == "READ_ONLY_DO_NOT_MODIFY_DELETE_OR_RERUN" &&
             run_inventory.slice("byte_length", "sha256") ==
               evidence["formal_dev_repeat_003_full_file_inventory"].slice("byte_length", "sha256") &&
             run_inventory.slice(*inventory_binding_projection.keys) ==
               inventory_binding_projection &&
             run_inventory["file_projection_sha256"] == full_inventory["file_projection_sha256"] &&
             run_inventory["directory_projection_sha256"] ==
               full_inventory["directory_projection_sha256"] &&
             observed["child_exit_code"] == accounting["run003_child_exit_code"] &&
             observed["init_sent_count"] == accounting["run003_init_sent_count"] &&
             observed["valid_ready_count"] == 0 && observed["run_request_count"] == 0 &&
             observed["mockmvc_perform_count"] == 0 &&
             observed["evaluator_invocation_count"] == 0 &&
             observed["admissible_dev_transaction_count"] == 0 &&
             observed["metric_comparison_count"] == 0 && observed["metric_verdict_count"] == 0 &&
             run_matrix.slice("relative_path", "byte_length", "sha256", "mode", "nlink") ==
               inventory_matrix &&
             run_matrix["byte_length"] == 0 && run_matrix["line_count"] == 0 &&
             run_matrix["record_count"] == 0 && run_matrix["admissible"] == false &&
             run_accounting["implementation_iterations_consumed"] ==
               accounting["implementation_iterations_consumed"] &&
             run_accounting["implementation_iterations_remaining"] == 0 &&
             run_accounting["quality_repairs_remaining"] == 0 &&
             run_accounting["candidate_frozen"] == false &&
             run_accounting["held_opened_or_executed"] == false &&
             run_accounting["v5_allowed"] == false && run_accounting["rerun_allowed"] == false,
             "pre-candidate DEV run003 lifecycle drift")

      quality = parse_bound_json(
        evidence["formal_dev_repeat_003_terminal_quality_non_pass"],
        "pre-candidate DEV terminal Quality receipt"
      )
      quality_authority = mapping(
        quality["authoritative_bindings"], "pre-candidate DEV terminal Quality authority bindings"
      )
      quality_prior = exact_keys(
        quality_authority["prior_quality_iteration2_adjudication"],
        %w[path byte_length sha256 binding_rule],
        "pre-candidate DEV terminal Quality iteration2 authority"
      )
      quality_run = mapping(quality["run003"], "pre-candidate DEV terminal Quality run003")
      quality_matrix = exact_keys(
        quality_run["matrix"],
        %w[path byte_length line_count record_count mode nlink sha256],
        "pre-candidate DEV terminal Quality matrix"
      )
      quality_adapter_review = exact_keys(
        quality_run["v4_independent_adapter_review"],
        %w[path byte_length mode sha256 verdict blocking_root_count closed_root],
        "pre-candidate DEV terminal Quality adapter Review"
      )
      assert(quality["schema_version"] == adapter["quality_receipt_schema"] &&
             quality["task_id"] == entry["task_id"] && quality["route_id"] == entry["route_id"] &&
             quality["verdict"] == "NON_PASS" && quality["status"] == entry["status"] &&
             quality["terminal"] == true &&
             quality_prior.slice("byte_length", "sha256") ==
               evidence["formal_dev_repeat_002_quality_adjudication"].slice("byte_length", "sha256") &&
             quality_run["run_root"] == full_inventory["run_root"] &&
             quality_run["run_root_file_count"] == full_inventory["file_count"] &&
             quality_matrix.slice("path", "byte_length", "sha256", "mode", "nlink") == {
               "path" => inventory_matrix["relative_path"],
               "byte_length" => inventory_matrix["byte_length"],
               "sha256" => inventory_matrix["sha256"],
               "mode" => inventory_matrix["mode"],
               "nlink" => inventory_matrix["nlink"]
             } && quality_matrix["line_count"] == 0 && quality_matrix["record_count"] == 0 &&
             quality_adapter_review.slice("byte_length", "sha256") ==
               evidence["independent_adapter_review_pass_v4"].slice("byte_length", "sha256") &&
             quality_adapter_review["verdict"] == "PASS" &&
             quality["terminal_lifecycle_event_kind"] ==
               terminal["terminal_lifecycle_event_kind"] &&
             quality.dig("closed_counters", "implementation_iterations", "used") ==
               accounting["implementation_iterations_consumed"] &&
             quality.dig("closed_counters", "dev", "admissible_transactions") == 0 &&
             quality.dig("closed_counters", "held_validation", "runs") == 0 &&
             value_at_path(quality, adapter["quality_capability_credit_path"]) == 0,
             "pre-candidate DEV terminal Quality lifecycle drift")

      review_binding = exact_keys(
        receipt["independent_terminal_review"], %w[identity target_verdict],
        "pre-candidate DEV independent terminal Review binding"
      )
      review_identity = exact_keys(
        review_binding["identity"], %w[path byte_length sha256],
        "pre-candidate DEV independent terminal Review identity"
      )
      assert(review_identity == evidence["independent_terminal_task_review"] &&
             review_binding["target_verdict"] == "NON_PASS",
             "pre-candidate DEV independent terminal Review binding drift")
      review = parse_bound_json(review_identity, "pre-candidate DEV independent terminal Review")
      review_authority = mapping(
        review["authority_bindings"], "pre-candidate DEV independent terminal Review authority"
      )
      review_iteration2_quality = exact_keys(
        review_authority["iteration2_quality_authority"],
        %w[path byte_length sha256 binding_rule],
        "pre-candidate DEV independent terminal Review iteration2 Quality"
      )
      review_terminal_quality = exact_keys(
        review_authority["run003_terminal_quality_receipt"],
        %w[path byte_length mode sha256 verdict status],
        "pre-candidate DEV independent terminal Review terminal Quality"
      )
      review_run = mapping(
        review["exact_run003_bindings"], "pre-candidate DEV independent terminal Review run003"
      )
      review_inventory = exact_keys(
        review_run["full_file_inventory"],
        %w[
          path byte_length mode sha256 file_count directory_count symlink_count
          aggregate_regular_file_bytes file_projection_sha256 directory_projection_sha256
          independently_recomputed_current_exact_match
        ],
        "pre-candidate DEV independent terminal Review full inventory"
      )
      review_run_receipt = exact_keys(
        review_run["run_terminal_receipt"],
        %w[path byte_length mode sha256],
        "pre-candidate DEV independent terminal Review run receipt"
      )
      review_matrix = exact_keys(
        review_run["matrix"],
        %w[relative_path byte_length mode nlink sha256 line_count record_count admissible],
        "pre-candidate DEV independent terminal Review matrix"
      )
      review_adapter = exact_keys(
        review_run["v4_review"],
        %w[relative_path byte_length sha256 exact_equal_to_frozen_source],
        "pre-candidate DEV independent terminal Review adapter child"
      )
      review_product = exact_keys(
        review.dig("product_review_and_capability_boundary", "iteration1_product_review"),
        %w[path byte_length mode sha256 target_verdict scope],
        "pre-candidate DEV independent terminal Review product child"
      )
      assert(review["schema_version"] == adapter["terminal_review_schema"] &&
             review["task_id"] == entry["task_id"] && review["route_id"] == entry["route_id"] &&
             review["target_verdict"] == "NON_PASS" &&
             review_iteration2_quality.slice("byte_length", "sha256") ==
               evidence["formal_dev_repeat_002_quality_adjudication"].slice("byte_length", "sha256") &&
             review_terminal_quality.slice("byte_length", "sha256") ==
               evidence["formal_dev_repeat_003_terminal_quality_non_pass"].slice("byte_length", "sha256") &&
             review_terminal_quality["verdict"] == "NON_PASS" &&
             review_terminal_quality["status"] == entry["status"] &&
             review_run["run_root"] == full_inventory["run_root"] &&
             review_inventory.slice("byte_length", "sha256") ==
               evidence["formal_dev_repeat_003_full_file_inventory"].slice("byte_length", "sha256") &&
             review_inventory.slice(*inventory_binding_projection.keys) ==
               inventory_binding_projection &&
             review_inventory["file_projection_sha256"] ==
               full_inventory["file_projection_sha256"] &&
             review_inventory["directory_projection_sha256"] ==
               full_inventory["directory_projection_sha256"] &&
             review_inventory["independently_recomputed_current_exact_match"] == true &&
             review_run_receipt.slice("byte_length", "sha256") ==
               evidence["formal_dev_repeat_003_terminal_receipt"].slice("byte_length", "sha256") &&
             review_matrix == run_matrix &&
             review_adapter.slice("byte_length", "sha256") ==
               evidence["independent_adapter_review_pass_v4"].slice("byte_length", "sha256") &&
             review_adapter["exact_equal_to_frozen_source"] == true &&
             review_product.slice("byte_length", "sha256") ==
               evidence["iteration1_product_review"].slice("byte_length", "sha256") &&
             review_product["target_verdict"] == "PASS" &&
             review.dig("run003_execution_assessment", "admissible_dev_transaction_count") == 0 &&
             review.dig("lifecycle_accounting", "implementation_iterations_consumed") ==
               accounting["implementation_iterations_consumed"] &&
             review.dig("lifecycle_accounting", "candidates_created_or_frozen") == 0 &&
             review.dig("lifecycle_accounting", "held_validation_runs") == 0 &&
             value_at_path(review, adapter["review_capability_credit_path"]) == 0,
             "pre-candidate DEV independent terminal Review lifecycle drift")

      prior_review = exact_keys(
        receipt["prior_product_review"], %w[capability_credit identity scope verdict],
        "pre-candidate DEV prior product Review"
      )
      assert(prior_review["identity"] == evidence["iteration1_product_review"] &&
             prior_review["verdict"] == "PASS" && prior_review["capability_credit"] == 0 &&
             !prior_review["scope"].to_s.empty?,
             "pre-candidate DEV prior product Review boundary drift")

      snapshot = parse_bound_json(
        evidence["product_dirty_snapshot_manifest"],
        "pre-candidate DEV product dirty snapshot manifest"
      )
      snapshot_rows = array(
        snapshot["files"], "pre-candidate DEV snapshot manifest files"
      ).map.with_index do |row, index|
        record = exact_keys(
          row,
          %w[relative_path git_status tracked_at_active dirty active_base snapshot patch_replay],
          "pre-candidate DEV snapshot manifest file[#{index}]"
        )
        dirty = exact_keys(
          record["dirty"], %w[byte_length sha256 git_blob_sha1 mode nlink],
          "pre-candidate DEV snapshot manifest dirty file[#{index}]"
        )
        snapshot_identity = exact_keys(
          record["snapshot"], %w[path byte_length sha256 exact_dirty_bytes_equal],
          "pre-candidate DEV snapshot manifest snapshot file[#{index}]"
        )
        replay_identity = exact_keys(
          record["patch_replay"], %w[path byte_length sha256 exact_dirty_bytes_equal],
          "pre-candidate DEV snapshot manifest replay file[#{index}]"
        )
        {
          "relative_path" => record["relative_path"],
          "dirty" => dirty,
          "snapshot" => snapshot_identity,
          "patch_replay" => replay_identity
        }
      end
      snapshot_content_projection = snapshot_rows.map do |row|
        {
          "relative_path" => row["relative_path"],
          "byte_length" => row.dig("dirty", "byte_length"),
          "sha256" => row.dig("dirty", "sha256")
        }
      end.sort_by { |row| row["relative_path"] }
      master_content_projection = snapshot_master_projection.map do |row|
        row.slice("relative_path", "byte_length", "sha256")
      end
      assert(snapshot["schema_version"] == adapter["snapshot_manifest_schema"] &&
             snapshot["task_id"] == entry["task_id"] &&
             snapshot.dig("dirty_worktree", "dirty_path_count") == 4 &&
             snapshot.dig("dirty_worktree", "no_other_dirty_paths") == true &&
             snapshot.dig("patch", "sha256") == evidence.dig("product_dirty_delta_patch", "sha256") &&
             snapshot.dig("patch", "byte_length") ==
               evidence.dig("product_dirty_delta_patch", "byte_length") &&
             snapshot.dig("patch", "git_apply_check").to_s.start_with?("PASS") &&
             snapshot.dig("patch", "replay_exact_dirty_bytes") == true &&
             snapshot.dig("snapshot", "file_count") == 4 &&
             snapshot.dig("snapshot", "all_exact_dirty_bytes") == true &&
             snapshot_rows.length == 4 &&
             snapshot_rows.map { |row| row["relative_path"] }.uniq.length == 4 &&
             snapshot_content_projection == master_content_projection &&
             snapshot_rows.all? do |row|
               dirty = row["dirty"]
               row["snapshot"].slice("byte_length", "sha256") ==
                 dirty.slice("byte_length", "sha256") &&
                 row["snapshot"]["exact_dirty_bytes_equal"] == true &&
                 row["patch_replay"].slice("byte_length", "sha256") ==
                   dirty.slice("byte_length", "sha256") &&
                 row["patch_replay"]["exact_dirty_bytes_equal"] == true &&
                 dirty["mode"] == "0644" && dirty["nlink"] == 1
             end,
             "pre-candidate DEV product dirty snapshot manifest drift")

      review_dirty = mapping(
        review["dirty_delta_snapshot_binding"],
        "pre-candidate DEV independent terminal Review dirty snapshot binding"
      )
      review_dirty_paths = array(
        review_dirty["paths"],
        "pre-candidate DEV independent terminal Review dirty snapshot paths"
      ).map.with_index do |row, index|
        exact_keys(
          row, %w[git_status relative_path byte_length mode sha256],
          "pre-candidate DEV independent terminal Review dirty path[#{index}]"
        )
      end
      review_dirty_projection = review_dirty_paths.map do |row|
        row.slice("relative_path", "byte_length", "sha256")
      end.sort_by { |row| row["relative_path"] }
      assert(review_dirty["head"] == canonical_before["commit"] &&
             review_dirty["tree"] == canonical_before["tree"] &&
             review_dirty["activation_parent_commit"] == activation_parent["commit"] &&
             review_dirty["activation_parent_tree"] == activation_parent["tree"] &&
             review_dirty["dirty_path_count"] == 4 &&
             review_dirty_paths.map { |row| row["relative_path"] }.uniq.length == 4 &&
             review_dirty_paths.all? { |row| row["mode"] == "0644" } &&
             review_dirty_projection == master_content_projection,
             "pre-candidate DEV independent terminal Review dirty snapshot identity drift")

      replay = parse_bound_json(
        evidence["product_dirty_patch_replay_verification"],
        "pre-candidate DEV product dirty patch replay verification"
      )
      replay_rows = array(replay["files"], "pre-candidate DEV patch replay files").map.with_index do |row, index|
        exact_keys(
          row,
          %w[byte_length exact_snapshot_bytes_equal final_installed_path relative_path sha256],
          "pre-candidate DEV patch replay file[#{index}]"
        )
      end
      replay_projection = replay_rows.map do |row|
        row.slice("relative_path", "byte_length", "sha256", "final_installed_path")
      end.sort_by { |row| row["relative_path"] }
      assert(replay["schema_version"] ==
               adapter["patch_replay_schema"] &&
             replay["task_id"] == entry["task_id"] && replay["status"] == "PASS" &&
             replay["base_commit"] == receipt.dig("canonical_before_terminal_sync", "commit") &&
             replay["base_tree"] == receipt.dig("canonical_before_terminal_sync", "tree") &&
             replay.dig("patch", "sha256") == evidence.dig("product_dirty_delta_patch", "sha256") &&
             replay.dig("patch", "byte_length") == evidence.dig("product_dirty_delta_patch", "byte_length") &&
             replay.dig("patch", "git_apply_check").to_s.start_with?("PASS") &&
             replay_rows.length == 4 &&
             replay_rows.map { |row| row["relative_path"] }.uniq.length == 4 &&
             replay_rows.all? { |row| row["exact_snapshot_bytes_equal"] == true } &&
             replay_projection == snapshot_master_projection,
             "pre-candidate DEV product dirty patch replay drift")
      return
    end

    if receipt["schema_version"] ==
       "phase-delegated-preworker-start-safety-stop-terminal-receipt/v1"
      exact_keys(
        receipt,
        %w[
          schema_version task_id route_id status recorded_at activation_parent
          canonical_before_terminal_sync stop_condition quality_receipt
          public_freeze_attempt product_preflight execution final_reviews
          capability_credit canonical_make_verify next_action forbidden_continuations
          authorization_effects claim_boundary
        ],
        "phase-delegated pre-Worker start-safety terminal receipt"
      )
      stop = exact_keys(
        receipt["stop_condition"],
        %w[
          kind normalized_root_cause contract_stop_condition
          required_change_outside_task_allowlist same_task_repair_applicable
        ],
        "phase-delegated pre-Worker start-safety stop condition"
      )
      assert(stop["kind"] == "PREWORKER_PRODUCT_DATASET_COMPATIBILITY_NON_PASS" &&
             stop["normalized_root_cause"].to_s.match?(/\AP[0-9]+\.[A-Z0-9_.]+\z/) &&
             !stop["contract_stop_condition"].to_s.empty? &&
             stop["required_change_outside_task_allowlist"] == true &&
             stop["same_task_repair_applicable"] == false,
             "phase-delegated pre-Worker start-safety stop condition drift")

      quality_identity = exact_keys(
        receipt["quality_receipt"], %w[path byte_length sha256],
        "phase-delegated pre-Worker Quality receipt"
      )
      quality = parse_bound_json(quality_identity, "phase-delegated pre-Worker Quality receipt")
      exact_keys(
        quality,
        %w[
          schema_version record_type task_id created_at_utc create_once status worker_gate
          normalized_root_cause controlling_finding authority_binding public_freeze_attempt
          accepted_input_verification current_product_identity verification terminal_accounting
          external_effects founder_escalation claim_boundary
        ],
        "phase-delegated pre-Worker Quality receipt"
      )
      assert(quality["task_id"] == entry["task_id"] && quality["create_once"] == true &&
             quality["status"] == "TERMINAL_PREFREEZE_QUALITY_NON_PASS" &&
             quality["worker_gate"] == "STOP" &&
             quality["normalized_root_cause"] == stop["normalized_root_cause"] &&
             quality.dig("terminal_accounting", "worker_product_mutation") == false &&
             quality.dig("terminal_accounting", "candidate_absent") == true &&
             quality.dig("terminal_accounting", "implementation_iterations_used") == 0 &&
             quality.dig("terminal_accounting", "capability_credit") == 0 &&
             quality["external_effects"] == FALSE_EXTERNAL_EFFECTS,
             "phase-delegated pre-Worker Quality receipt lifecycle drift")

      public_identity = exact_keys(
        receipt["public_freeze_attempt"], %w[path byte_length sha256],
        "phase-delegated pre-Worker public freeze attempt"
      )
      repo_identity_bytes(root, public_identity,
                          "phase-delegated pre-Worker public freeze attempt")
      assert(quality["public_freeze_attempt"].slice("path", "byte_length", "sha256") ==
             public_identity,
             "phase-delegated pre-Worker public freeze attempt binding drift")

      preflight = exact_keys(
        receipt["product_preflight"],
        %w[
          task_count source_artifact_count mjs_artifact_count non_mjs_artifact_count
          admissible_code_chunk_count admissible_symbol_count admissible_relation_count
          same_scan_graph_edge_count product_code_diff_paths
        ],
        "phase-delegated pre-Worker product preflight"
      )
      assert(preflight == {
               "task_count" => 6,
               "source_artifact_count" => 20,
               "mjs_artifact_count" => 20,
               "non_mjs_artifact_count" => 0,
               "admissible_code_chunk_count" => 0,
               "admissible_symbol_count" => 0,
               "admissible_relation_count" => 0,
               "same_scan_graph_edge_count" => 0,
               "product_code_diff_paths" => []
             },
             "phase-delegated pre-Worker product compatibility facts drift")

      execution = exact_keys(
        receipt["execution"],
        %w[
          worker_started product_mutation implementation_iterations_used
          same_task_repairs_used dev_benchmark_runs validation_runs candidate_created
          candidate_commit candidate_tree candidate_integrated
        ],
        "phase-delegated pre-Worker execution"
      )
      assert(execution == {
               "worker_started" => false,
               "product_mutation" => false,
               "implementation_iterations_used" => 0,
               "same_task_repairs_used" => 0,
               "dev_benchmark_runs" => 0,
               "validation_runs" => 0,
               "candidate_created" => false,
               "candidate_commit" => nil,
               "candidate_tree" => nil,
               "candidate_integrated" => false
             },
             "phase-delegated pre-Worker stop cannot claim execution or candidate")
      reviews = exact_keys(receipt["final_reviews"], %w[cto security quality],
                           "phase-delegated pre-Worker final reviews")
      assert(reviews.values.all? { |value| value == "NOT_STARTED_PREFREEZE_STOP" } &&
             outcome["cto_review"] == reviews["cto"] &&
             outcome["security_review"] == reviews["security"] &&
             outcome["quality_review"] == reviews["quality"] &&
             outcome["candidate_commit"].nil? && outcome["candidate_tree"].nil? &&
             outcome["sealed_formal_value_result"] == "NOT_STARTED_PREFREEZE_STOP_CONDITION" &&
             receipt["capability_credit"] == 0 &&
             receipt["canonical_make_verify"].to_s.start_with?("NOT_INVOKED") &&
             receipt["next_action"] == CONTINUE_ACTION &&
             receipt["authorization_effects"] == FALSE_EXTERNAL_EFFECTS &&
             !receipt["claim_boundary"].to_s.empty?,
             "phase-delegated pre-Worker terminal claim boundary drift")
      return
    end

    if receipt["schema_version"] == "phase-delegated-formal-dev-terminal-nonpass-receipt/v1"
      exact_keys(
        receipt,
        %w[
          schema_version task_id route_id terminal_status recorded_at_utc
          activation_parent canonical_before_terminal_sync formal_dev failure
          source_identity outcome external_effects next_action claim_boundary
        ],
        "phase-delegated formal DEV terminal NON_PASS receipt"
      )
      assert(receipt["terminal_status"] == entry["status"],
             "phase-delegated formal DEV terminal status drift")

      formal = exact_keys(
        receipt["formal_dev"],
        %w[
          root terminal_receipt manifest root_index closed_inventory
          completed_subprocess_runs endpoint_call_attempt_count
          endpoint_response_count denominator_completed metrics_status
          rerun_permitted
        ],
        "phase-delegated formal DEV terminal execution"
      )
      formal_receipt = exact_keys(
        formal["terminal_receipt"], %w[path byte_length sha256],
        "phase-delegated formal DEV inner terminal receipt"
      )
      validate_identity(formal_receipt, "phase-delegated formal DEV inner terminal receipt")
      manifest = exact_keys(
        formal["manifest"], %w[byte_length payload_rows sha256],
        "phase-delegated formal DEV manifest projection"
      )
      root_index = exact_keys(
        formal["root_index"], %w[byte_length entries sha256],
        "phase-delegated formal DEV root index projection"
      )
      inventory = exact_keys(
        formal["closed_inventory"],
        %w[file_count total_bytes manifest_rows_verified root_index_rows_verified],
        "phase-delegated formal DEV closed inventory"
      )
      assert(Pathname.new(formal["root"]).absolute? && File.directory?(formal["root"]) &&
             manifest["byte_length"].is_a?(Integer) && manifest["byte_length"].positive? &&
             manifest["payload_rows"].is_a?(Integer) && manifest["payload_rows"].positive? &&
             manifest["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
             root_index["byte_length"].is_a?(Integer) && root_index["byte_length"].positive? &&
             root_index["entries"].is_a?(Integer) && root_index["entries"].positive? &&
             root_index["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
             inventory["file_count"].is_a?(Integer) && inventory["file_count"].positive? &&
             inventory["total_bytes"].is_a?(Integer) && inventory["total_bytes"].positive? &&
             inventory["manifest_rows_verified"] == manifest["payload_rows"] &&
             inventory["root_index_rows_verified"] == root_index["entries"],
             "phase-delegated formal DEV inventory projection drift")
      assert(formal["completed_subprocess_runs"] == 1 &&
             formal["endpoint_call_attempt_count"] == 1 &&
             formal["endpoint_response_count"] == 0 &&
             formal["denominator_completed"] == 0 &&
             formal["metrics_status"] == "ABSENT_NOT_COMPUTED" &&
             formal["rerun_permitted"] == false,
             "phase-delegated formal DEV terminal run accounting drift")

      failure = exact_keys(
        receipt["failure"],
        %w[
          stage fact product_metric_failure initial_nonpass_receipt_sha256
          partial_run_ledger_sha256 stderr_sha256 stdout_sha256
        ],
        "phase-delegated formal DEV failure"
      )
      assert(failure["stage"] == "HARNESS_INPUT_ADAPTER_INVOCATION_SCHEMA" &&
             !failure["fact"].to_s.empty? && failure["product_metric_failure"] == false &&
             %w[
               initial_nonpass_receipt_sha256 partial_run_ledger_sha256
               stderr_sha256 stdout_sha256
             ].all? { |key| failure[key].to_s.match?(/\A[0-9a-f]{64}\z/) },
             "phase-delegated formal DEV failure projection drift")
      source = exact_keys(
        receipt["source_identity"],
        %w[source_manifest_sha256 canonical_diff_sha256 pre_post_source_and_git_status_exact],
        "phase-delegated formal DEV source identity"
      )
      assert(source["source_manifest_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
             source["canonical_diff_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
             source["pre_post_source_and_git_status_exact"] == true,
             "phase-delegated formal DEV source identity drift")

      terminal = exact_keys(
        receipt["outcome"],
        %w[
          dev_gate candidate_created sealed_read sealed_decrypted sealed_evaluated
          final_reviews_started candidate_integrated canonical_make_verify
          capability_credit
        ],
        "phase-delegated formal DEV outcome"
      )
      assert(terminal == {
               "dev_gate" => "NON_PASS",
               "candidate_created" => false,
               "sealed_read" => false,
               "sealed_decrypted" => false,
               "sealed_evaluated" => false,
               "final_reviews_started" => false,
               "candidate_integrated" => false,
               "canonical_make_verify" => "NOT_INVOKED_FORMAL_DEV_STOP",
               "capability_credit" => 0
             } && receipt["external_effects"] == FALSE_EXTERNAL_EFFECTS,
             "phase-delegated formal DEV terminal outcome drift")
      assert(outcome["candidate_commit"].nil? && outcome["candidate_tree"].nil? &&
             outcome["sealed_formal_value_result"] == "NOT_STARTED_AFTER_FORMAL_DEV_NON_PASS" &&
             outcome["cto_review"] == "NOT_STARTED_AFTER_FORMAL_DEV_NON_PASS" &&
             outcome["security_review"] == "NOT_STARTED_AFTER_FORMAL_DEV_NON_PASS" &&
             outcome["quality_review"] == "NOT_STARTED_AFTER_FORMAL_DEV_NON_PASS" &&
             outcome["capability_credit"] == 0 && outcome["candidate_integrated"] == false &&
             outcome["canonical_make_verify"] == terminal["canonical_make_verify"],
             "phase-delegated formal DEV Contract outcome projection drift")
      next_action = exact_keys(
        receipt["next_action"],
        %w[founder_decision_required owner action selected_task_id],
        "phase-delegated formal DEV next action"
      )
      assert(next_action["founder_decision_required"] == false &&
             next_action["owner"] == "MASTER_CEO_AGENT" &&
             next_action["action"] == CONTINUE_ACTION &&
             next_action["selected_task_id"].to_s.match?(/\AAIOS-P2-[0-9]{3}_[A-Z0-9_]+\z/) &&
             !receipt["claim_boundary"].to_s.empty?,
             "phase-delegated formal DEV next action or claim boundary drift")
      return
    end

    if receipt["schema_version"] == "phase-delegated-presealed-stop-terminal-receipt/v1"
      exact_keys(
        receipt,
        %w[
          schema_version task_id route_id status recorded_at activation_parent
          canonical_before_terminal_sync stop_condition quality_freeze
          public_dev_prevalidation official_dev_execution candidate sealed_validation
          final_reviews preservation capability_credit canonical_make_verify next_action
          forbidden_continuations authorization_effects
        ],
        "phase-delegated presealed stop terminal receipt"
      )
      candidate = exact_keys(
        receipt["candidate"],
        %w[created commit tree source_manifest_created integrated],
        "phase-delegated presealed stop candidate"
      )
      assert(candidate == {
               "created" => false,
               "commit" => nil,
               "tree" => nil,
               "source_manifest_created" => false,
               "integrated" => false
             },
             "phase-delegated presealed stop cannot claim a candidate")
      assert(outcome["candidate_commit"].nil? && outcome["candidate_tree"].nil? &&
             outcome["sealed_formal_value_result"] == "NOT_STARTED_PRESEALED_STOP_CONDITION",
             "phase-delegated presealed stop candidate or sealed projection drift")

      stop = exact_keys(
        receipt["stop_condition"],
        %w[kind normalized_root_cause attempts same_task_repairs_consumed additional_repairs_forbidden_by_anti_loop],
        "phase-delegated presealed stop condition"
      )
      attempts = array(stop["attempts"], "phase-delegated presealed stop attempts")
      assert(stop["kind"] == "ADJACENT_NORMALIZED_ROOT_CAUSE_REPEAT" &&
             stop["normalized_root_cause"].is_a?(String) &&
             !stop["normalized_root_cause"].empty? && attempts.length == 2 &&
             stop["same_task_repairs_consumed"].is_a?(Integer) &&
             stop["same_task_repairs_consumed"].positive? &&
             stop["additional_repairs_forbidden_by_anti_loop"] == true,
             "phase-delegated presealed anti-loop stop condition drift")
      attempts.each_with_index do |attempt, index|
        expected_attempt_keys = %w[
          attempt status reason_code raw_execve_environment
          worker_stderr_byte_length worker_stderr_sha256
          observer_raw_byte_length observer_raw_sha256
        ]
        expected_attempt_keys << "observed_value" if index == 1
        attempt = exact_keys(
          attempt, expected_attempt_keys,
          "phase-delegated presealed stop attempt"
        )
        assert(attempt["status"] == "NON_PASS" &&
               attempt["reason_code"].is_a?(String) && !attempt["reason_code"].empty? &&
               attempt["raw_execve_environment"] == "EXACT_FROZEN_FOUR_KEYS" &&
               attempt["worker_stderr_byte_length"].is_a?(Integer) &&
               attempt["worker_stderr_byte_length"].positive? &&
               attempt["worker_stderr_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
               attempt["observer_raw_byte_length"].is_a?(Integer) &&
               attempt["observer_raw_byte_length"].positive? &&
               attempt["observer_raw_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/),
               "phase-delegated presealed stop attempt is not a real fail-closed result")
      end

      official = exact_keys(
        receipt["official_dev_execution"],
        %w[runs evidence_root evidence_root_status external_effects_claim],
        "phase-delegated presealed official DEV execution"
      )
      assert(official["runs"] == 0 && official["evidence_root_status"] == "ABSENT" &&
             official["external_effects_claim"] == "NOT_MADE_OFFICIAL_TRANSACTION_ABSENT" &&
             Pathname.new(official["evidence_root"]).absolute? &&
             !File.exist?(official["evidence_root"]) && !File.symlink?(official["evidence_root"]),
             "phase-delegated presealed stop must precede official DEV Evidence")
      sealed = exact_keys(
        receipt["sealed_validation"],
        %w[started runs reruns result],
        "phase-delegated presealed sealed validation"
      )
      assert(sealed == { "started" => false, "runs" => 0, "reruns" => 0,
                         "result" => "NOT_AVAILABLE" },
             "phase-delegated presealed stop cannot claim sealed execution")

      reviews = exact_keys(receipt["final_reviews"], %w[cto security quality],
                           "phase-delegated presealed final reviews")
      assert(outcome["cto_review"] == reviews["cto"] &&
             outcome["security_review"] == reviews["security"] &&
             outcome["quality_review"] == reviews["quality"] &&
             reviews.values.all? { |value| value == "NOT_STARTED_CANDIDATE_ABSENT" },
             "phase-delegated presealed stop Review projection drift")
      preservation = exact_keys(
        receipt["preservation"],
        %w[
          rejected_engineering_snapshot rejected_engineering_file_manifest
          temp_runtime_failure_snapshot temp_runtime_failure_file_manifest
          reuse_as_engineering_input
        ],
        "phase-delegated presealed preservation"
      )
      preservation.reject { |key, _value| key == "reuse_as_engineering_input" }.each do |key, identity|
        validate_identity(
          exact_keys(identity, %w[path byte_length sha256],
                     "phase-delegated presealed preservation #{key}"),
          "phase-delegated presealed preservation #{key}"
        )
      end
      assert(preservation["reuse_as_engineering_input"] == false &&
             receipt["capability_credit"] == 0 &&
             receipt["canonical_make_verify"].to_s.start_with?("NOT_INVOKED") &&
             receipt["next_action"] == "FOUNDER_RESERVED_DECISION_PHASE_ENVELOPE_EXHAUSTED" &&
             array(receipt["forbidden_continuations"],
                   "phase-delegated presealed forbidden continuations").sort ==
               %w[
                 CANDIDATE_FREEZE CLOSURE CORRECTION FEASIBILITY NORMALIZATION
                 OFFICIAL_DEV_EXECUTION REMEDIATION REPLACEMENT RUN_4
                 SEALED_VALIDATION SECOND_ENVIRONMENT_CONTRACT_REPAIR SUCCESSOR
               ].sort &&
             receipt["authorization_effects"] == FALSE_EXTERNAL_EFFECTS,
             "phase-delegated presealed stop claim boundary drift")
      return
    end

    if receipt["schema_version"] == "phase-delegated-presealed-formal-admission-stop-terminal-receipt/v1"
      exact_keys(
        receipt,
        %w[
          schema_version task_id route_id status recorded_at activation_parent
          canonical_before_terminal_sync rejected_engineering stop_condition quality_freeze
          formal_dev_execution candidate sealed_validation final_reviews preservation
          capability_credit canonical_make_verify next_action forbidden_continuations
          authorization_effects
        ],
        "phase-delegated presealed formal admission stop terminal receipt"
      )
      rejected = exact_keys(
        receipt["rejected_engineering"],
        %w[commit tree parent branch candidate_designated integrated],
        "phase-delegated rejected engineering identity"
      )
      assert(rejected.values_at("commit", "tree", "parent").all? do |value|
               value.to_s.match?(/\A[0-9a-f]{40}\z/)
             end && rejected["branch"].to_s.start_with?("codex/") &&
             rejected["candidate_designated"] == false && rejected["integrated"] == false,
             "phase-delegated rejected engineering claim drift")

      candidate = exact_keys(
        receipt["candidate"],
        %w[created commit tree source_manifest_created integrated],
        "phase-delegated presealed formal admission stop candidate"
      )
      assert(candidate == {
               "created" => false,
               "commit" => nil,
               "tree" => nil,
               "source_manifest_created" => false,
               "integrated" => false
             },
             "phase-delegated formal admission stop cannot claim a candidate")
      assert(outcome["candidate_commit"].nil? && outcome["candidate_tree"].nil? &&
             outcome["sealed_formal_value_result"] == "NOT_STARTED_PRESEALED_STOP_CONDITION",
             "phase-delegated formal admission stop candidate projection drift")

      stop = exact_keys(
        receipt["stop_condition"],
        %w[kind normalized_root_cause attempts same_task_repairs_consumed additional_repairs_forbidden_by_anti_loop],
        "phase-delegated formal admission anti-loop stop"
      )
      attempts = array(stop["attempts"], "phase-delegated formal admission attempts")
      assert(stop["kind"] == "ADJACENT_NORMALIZED_ROOT_CAUSE_REPEAT" &&
             stop["normalized_root_cause"].to_s.match?(/\AP[0-9]+\.[A-Z0-9_.]+\z/) &&
             attempts.length == 2 && stop["same_task_repairs_consumed"].is_a?(Integer) &&
             stop["same_task_repairs_consumed"].positive? &&
             stop["additional_repairs_forbidden_by_anti_loop"] == true,
             "phase-delegated formal admission anti-loop stop drift")
      seen_reasons = []
      attempts.each_with_index do |value, index|
        attempt = exact_keys(
          value,
          %w[
            attempt status reason_code implementation_commit implementation_tree
            expected_literal actual_literal transaction execution_receipt
            transaction_runs evaluation_exit evaluation_report_created
          ],
          "phase-delegated formal admission attempt[#{index}]"
        )
        assert(attempt["status"] == "NON_PASS" &&
               attempt["reason_code"].to_s.match?(/\A[A-Z0-9_]+\z/) &&
               attempt["implementation_commit"].to_s.match?(/\A[0-9a-f]{40}\z/) &&
               attempt["implementation_tree"].to_s.match?(/\A[0-9a-f]{40}\z/) &&
               !attempt["expected_literal"].to_s.empty? && !attempt["actual_literal"].to_s.empty? &&
               attempt["expected_literal"] != attempt["actual_literal"] &&
               attempt["transaction_runs"] == 16 && attempt["evaluation_exit"] != 0 &&
               attempt["evaluation_report_created"] == false,
               "phase-delegated formal admission attempt is not a real fail-closed result")
        validate_identity(
          exact_keys(attempt["transaction"], %w[path byte_length sha256],
                     "phase-delegated formal admission transaction"),
          "phase-delegated formal admission transaction"
        )
        validate_identity(
          exact_keys(attempt["execution_receipt"], %w[path byte_length sha256],
                     "phase-delegated formal admission execution receipt"),
          "phase-delegated formal admission execution receipt"
        )
        seen_reasons << attempt["reason_code"]
      end
      assert(seen_reasons.uniq.length == 2 &&
             attempts[0]["implementation_commit"] != attempts[1]["implementation_commit"],
             "phase-delegated formal admission attempts are not distinct adjacent failures")

      quality = exact_keys(
        receipt["quality_freeze"],
        %w[pre_dev_source_manifest_v1 pre_dev_source_manifest_v2 formal_sealed_validation_runs],
        "phase-delegated formal admission Quality freeze"
      )
      %w[pre_dev_source_manifest_v1 pre_dev_source_manifest_v2].each do |key|
        validate_identity(
          exact_keys(quality[key], %w[path byte_length sha256],
                     "phase-delegated formal admission #{key}"),
          "phase-delegated formal admission #{key}"
        )
      end
      assert(quality["formal_sealed_validation_runs"] == 0,
             "phase-delegated formal admission stop cannot claim sealed execution")

      official = exact_keys(
        receipt["formal_dev_execution"],
        %w[attempts completed_raw_transactions accepted_evaluation_reports latest_raw_reconstruction official_dev_status capability_credit],
        "phase-delegated formal DEV execution"
      )
      raw = exact_keys(
        official["latest_raw_reconstruction"],
        %w[
          runs root_replay_pairs_passed lexical_macro_recall graph_macro_recall
          graph_strictly_greater per_task_regressions false_accepts forbidden_context
          baseline_isolation network provider secret remote production public unknown
        ],
        "phase-delegated formal DEV raw reconstruction"
      )
      assert(official["attempts"] == 2 && official["completed_raw_transactions"] == 2 &&
             official["accepted_evaluation_reports"] == 0 &&
             official["official_dev_status"] == "NON_PASS_ADMISSION_NO_ACCEPTED_REPORT" &&
             official["capability_credit"] == 0 && raw["runs"] == 16 &&
             raw["root_replay_pairs_passed"] == 8 && raw["graph_strictly_greater"] == true &&
             raw["graph_macro_recall"].is_a?(Numeric) && raw["lexical_macro_recall"].is_a?(Numeric) &&
             raw["graph_macro_recall"] > raw["lexical_macro_recall"] &&
             raw["per_task_regressions"] == 0 && raw["false_accepts"] == 0 &&
             raw["forbidden_context"] == 0 && raw["baseline_isolation"] == "PASS" &&
             %w[network provider secret remote production public unknown].all? { |key| raw[key] == 0 },
             "phase-delegated formal DEV raw result projection drift")

      sealed = exact_keys(receipt["sealed_validation"], %w[started runs reruns result],
                          "phase-delegated formal admission sealed validation")
      assert(sealed == { "started" => false, "runs" => 0, "reruns" => 0,
                         "result" => "NOT_AVAILABLE" },
             "phase-delegated formal admission stop cannot claim sealed validation")
      reviews = exact_keys(receipt["final_reviews"], %w[cto security quality],
                           "phase-delegated formal admission final reviews")
      assert(reviews.values.all? { |value| value == "NOT_STARTED_CANDIDATE_ABSENT" } &&
             outcome["cto_review"] == reviews["cto"] &&
             outcome["security_review"] == reviews["security"] &&
             outcome["quality_review"] == reviews["quality"],
             "phase-delegated formal admission Review projection drift")
      preservation = exact_keys(
        receipt["preservation"],
        %w[
          rejected_engineering_bundle formal_dev_v1_execution_receipt
          formal_dev_v2_execution_receipt formal_dev_v2_raw_reconstruction_report
          reuse_as_engineering_input
        ],
        "phase-delegated formal admission preservation"
      )
      preservation.reject { |key, _value| key == "reuse_as_engineering_input" }.each do |key, identity|
        validate_identity(
          exact_keys(identity, %w[path byte_length sha256],
                     "phase-delegated formal admission preservation #{key}"),
          "phase-delegated formal admission preservation #{key}"
        )
      end
      assert(preservation["reuse_as_engineering_input"] == false &&
             receipt["capability_credit"] == 0 &&
             receipt["canonical_make_verify"].to_s.start_with?("NOT_INVOKED") &&
             receipt["next_action"] == "FOUNDER_RESERVED_DECISION_PHASE_ENVELOPE_EXHAUSTED" &&
             array(receipt["forbidden_continuations"],
                   "phase-delegated formal admission forbidden continuations").sort ==
               %w[
                 CANONICAL_MAKE_VERIFY CANDIDATE_FREEZE CLOSURE CORRECTION FEASIBILITY
                 FINAL_REVIEW INTEGRATION NORMALIZATION REMEDIATION REPLACEMENT
                 SEALED_VALIDATION SECOND_SAME_TASK_SCHEMA_REPAIR SUCCESSOR
                 THIRD_FORMAL_DEV_ATTEMPT
               ].sort && receipt["authorization_effects"] == FALSE_EXTERNAL_EFFECTS,
             "phase-delegated formal admission stop claim boundary drift")
      return
    end

    candidate = exact_keys(
      receipt["candidate"],
      %w[commit tree source_manifest integrated],
      "predeclared Task terminal candidate"
    )
    assert(candidate["commit"] == outcome["candidate_commit"] &&
           candidate["tree"] == outcome["candidate_tree"] &&
           candidate["integrated"] == false && receipt["capability_credit"] == 0,
           "predeclared Task terminal candidate or capability projection drift")
    validate_identity(
      exact_keys(candidate["source_manifest"], %w[path byte_length sha256],
                 "predeclared Task candidate source manifest"),
      "predeclared Task candidate source manifest"
    )

    reviews = exact_keys(receipt["final_reviews"], %w[cto security quality],
                         "predeclared Task final reviews")
    verdicts = {}
    bound_non_pass = 0
    reviews.each do |role, value|
      review_record = mapping(value, "predeclared Task final #{role} review")
      allowed_keys = review_record.key?("path") ? %w[path byte_length sha256 verdict] : %w[verdict]
      review_record = exact_keys(review_record, allowed_keys,
                                 "predeclared Task final #{role} review")
      verdicts[role] = review_record["verdict"]
      next unless review_record.key?("path")

      review = parse_bound_json(
        review_record.slice("path", "byte_length", "sha256"),
        "predeclared Task final #{role} review"
      )
      target_verdict = review["TARGET_VERDICT"] || review["target_verdict"]
      assert(review["task_id"] == entry["task_id"] &&
             review["review_role"].to_s.downcase == role &&
             target_verdict == review_record["verdict"],
             "predeclared Task final Review lifecycle drift")
      reviewed_candidate = review["candidate"] || review["target"]
      reviewed_candidate = mapping(reviewed_candidate, "predeclared Task reviewed candidate")
      reviewed_commit = reviewed_candidate["commit"] || reviewed_candidate["candidate_commit"]
      reviewed_tree = reviewed_candidate["tree"] || reviewed_candidate["candidate_tree"]
      assert(reviewed_commit == candidate["commit"] && reviewed_tree == candidate["tree"],
             "predeclared Task final Review candidate binding drift")
      bound_non_pass += 1 if target_verdict == "NON_PASS"
    end
    assert(bound_non_pass.positive?,
           "predeclared terminal Task requires a hash-bound final Reviewer NON_PASS")
    assert(outcome["cto_review"] == verdicts["cto"] &&
           outcome["security_review"] == verdicts["security"] &&
           outcome["quality_review"] == verdicts["quality"],
           "predeclared Task terminal Review projection drift")
  end

  def validate_single_task_expansion_ledger!(root, entries, source_tasks, source_decision)
    return [] unless source_decision["schema_version"] == "1.2"

    ids = array(entries, "single-Task expansion phase execution Task ledger").map do |entry|
      mapping(entry, "single-Task expansion phase execution Task ledger entry")["task_id"]
    end
    assert(ids.uniq.length == ids.length,
           "phase execution task ledger contains duplicate Task ids")
    tasks = array(source_tasks, "single-Task expansion source Tasks")
    new_task_ids = array(source_decision["new_task_ids"], "single-Task expansion new Task ids")
    assert(tasks.length == 1 && new_task_ids.length == 1 &&
           tasks.first["task_id"] == new_task_ids.first,
           "single-Task expansion source Task set is not exact")
    parent_truth = truth_at_commit(
      root,
      source_decision.dig("activation_parent", "commit"),
      "single-Task expansion activation parent"
    )
    parent_entries = array(
      parent_truth.dig("phase_execution_envelope", "task_ledger"),
      "single-Task expansion activation-parent Task ledger"
    )
    assert(entries.first(parent_entries.length) == parent_entries,
           "single-Task expansion prior ledger prefix drifts from activation-parent accounting")
    suffix = entries.drop(parent_entries.length)
    source_status = mapping(tasks.first, "single-Task expansion source Task")["status"].to_s
    source_consumed = source_status.start_with?("TERMINAL_") || source_status.include?("ACCEPTED")
    if source_consumed
      assert(suffix.length == 1 && suffix.first.is_a?(Hash) &&
             suffix.first["task_id"] == new_task_ids.first,
             "single-Task expansion consumed source Task requires exactly one sole new ledger suffix")
    else
      assert(suffix.empty?,
             "single-Task expansion READY or ACTIVE source Task cannot appear in the consumed ledger")
    end
    parent_entries
  end

  def validate_consumed_task_ledger!(root, ledger, source_route, phase, anchored_source_entries,
                                     source_decision)
    entries = array(ledger, "phase execution task ledger")
    ids = entries.map { |entry| mapping(entry, "phase execution task ledger entry")["task_id"] }
    assert(ids.uniq.length == ids.length, "phase execution task ledger contains duplicate Task ids")
    source_tasks = array(source_route["task_plan"], "source Route task plan")
    prior_ledger = validate_single_task_expansion_ledger!(
      root, entries, source_tasks, source_decision
    )
    source_consumed = source_tasks.select do |task|
      status = mapping(task, "source Route Task")["status"].to_s
      status.start_with?("TERMINAL_") || status.include?("ACCEPTED")
    end
    assert((source_consumed.map { |task| task["task_id"] } - ids).empty?,
           "phase execution task ledger omits a consumed source Route Task")
    source_ineligible_ids = source_tasks.reject { |task| source_consumed.include?(task) }
                                      .map { |task| task["task_id"] }
    assert((ids & source_ineligible_ids).empty?,
           "phase execution task ledger consumes an ineligible source Route Task")

    entries.each_with_index do |value, index|
      candidate = mapping(value, "phase execution task ledger[#{index}]")
      expected_entry_keys = %w[task_id route_id status budget contract outcome_receipt]
      expected_entry_keys << "founder_residual_acceptance" if candidate.key?("founder_residual_acceptance")
      entry = exact_keys(candidate, expected_entry_keys, "phase execution task ledger[#{index}]")
      assert(entry["task_id"].to_s.match?(/\AAIOS-P(?:0|[1-9]|1[0-2])-[0-9]{3}_[A-Z0-9_]+\z/),
             "phase execution task ledger Task id is invalid")
      assert(entry["route_id"].is_a?(String) && !entry["route_id"].empty?,
             "phase execution task ledger Route id is invalid")
      assert(entry["status"].to_s.start_with?("TERMINAL_") ||
             entry["status"].to_s.include?("ACCEPTED"),
             "phase execution task ledger status is not consumed")
      budget = exact_keys(
        entry["budget"],
        %w[engineering_tasks engineering_hours calendar_days],
        "phase execution task ledger budget"
      )
      assert(budget["engineering_tasks"] == 1 &&
             budget["engineering_hours"].is_a?(Integer) && budget["engineering_hours"].positive? &&
             budget["calendar_days"].is_a?(Integer) && budget["calendar_days"].positive?,
             "phase execution task ledger budget is invalid")

      contract_bytes = repo_identity_bytes(root, entry["contract"], "phase execution consumed Task Contract")
      contract = parse_yaml_bytes(contract_bytes, "phase execution consumed Task Contract")
      assert(contract["task_id"] == entry["task_id"] && contract["phase"] == phase &&
             contract["route_id"] == entry["route_id"] && contract["status"] == entry["status"],
             "phase execution consumed Task Contract lifecycle drift")
      contract_budget = mapping(contract["budget"], "phase execution consumed Task Contract budget")
      assert(contract_budget["engineering_hours"] == budget["engineering_hours"] &&
             contract_budget["calendar_days"] == budget["calendar_days"],
             "phase execution consumed Task Contract budget drift")

      receipt = parse_bound_json(entry["outcome_receipt"], "phase execution Task outcome receipt")
      receipt_status = receipt["terminal_status"] || receipt["outcome_status"] || receipt["status"]
      assert(receipt["task_id"] == entry["task_id"] && receipt["route_id"] == entry["route_id"] &&
             receipt_status == entry["status"],
             "phase execution Task outcome receipt lifecycle drift")

      source_task = source_tasks.find { |task| task["task_id"] == entry["task_id"] }
      prior_entry = prior_ledger.find { |item| item.is_a?(Hash) && item["task_id"] == entry["task_id"] }
      assert(source_task || prior_entry == entry,
             "phase execution ledger only accepts source Tasks or exact hash-bound prior accounting")
      ledger_anchor_commit = nil
      anchored = array(anchored_source_entries, "anchored source task ledger").find do |item|
        item.is_a?(Hash) && item["task_id"] == entry["task_id"]
      end
      unless anchored
        anchor_literal = if entry.key?("founder_residual_acceptance")
                           entry.dig("founder_residual_acceptance", "source_founder_packet", "sha256")
                         else
                           entry.dig("outcome_receipt", "sha256")
                         end
        ledger_anchor_commit, anchored = first_task_ledger_anchor!(
          root,
          entry,
          anchor_literal,
          "phase execution source Task ledger entry"
        )
      end
      assert(anchored == entry,
             "phase execution source Task ledger drifts from its first canonical anchor")

      if entry.key?("founder_residual_acceptance")
        validate_founder_terminal_accounting_residual!(entry)
      elsif array(anchored_source_entries, "anchored source task ledger").any? do |item|
              item.is_a?(Hash) && item["task_id"] == entry["task_id"]
            end
        # The original delegation-amendment ledger predates typed terminal
        # outcome receipts; its exact immutable anchor remains authoritative.
      else
        validate_predeclared_task_terminal_outcome!(
          root,
          entry,
          contract,
          receipt,
          ledger_anchor_commit: ledger_anchor_commit
        )
      end
      if source_task
        assert(source_task["status"] == entry["status"] &&
               source_task["engineering_hours"] == budget["engineering_hours"] &&
               source_task["calendar_days"] == budget["calendar_days"],
               "phase execution source Task ledger binding drift")
      else
        assert(prior_entry == entry,
               "phase execution prior consumed Task ledger binding drift")
      end
    end
    entries
  end

  def validate_phase_envelope!(root, truth, source_route, phase, policy, source_decision)
    envelope = exact_keys(
      truth["phase_execution_envelope"],
      %w[
        schema_version phase status authority_basis accounting_basis limits task_ledger
        consumed reserved remaining external_effects
      ],
      "phase_execution_envelope"
    )
    assert(envelope["schema_version"] == "phase-execution-envelope/v1",
           "phase execution envelope schema drift")
    assert(envelope["phase"] == phase, "phase execution envelope phase drift")
    assert(%w[ACTIVE_REMAINING_CAPACITY TASK_CAPACITY_RESERVED EXHAUSTED].include?(envelope["status"]),
           "phase execution envelope status is invalid")
    authority = exact_keys(
      envelope["authority_basis"],
      %w[
        phase_entry_status policy_path policy_version policy_sha256 source_route_ref
        source_route_id source_decision delegation_amendment
      ],
      "phase execution envelope authority_basis"
    )
    assert(authority["phase_entry_status"] == "AUTHORIZED" &&
           authority["policy_path"] == POLICY_PATH &&
           authority["policy_version"] == POLICY_VERSION &&
           authority["policy_sha256"] == policy["sha256"] &&
           authority["source_route_id"] == source_route["route_id"] &&
           truth[authority["source_route_ref"]] == source_route,
           "phase execution envelope authority binding drift")
    assert(authority["source_decision"] == source_route["decision_packet"],
           "phase execution envelope source Decision identity drift")
    validate_identity(authority["source_decision"], "phase execution envelope source Decision")
    validate_delegation_amendment!(root, authority["delegation_amendment"], phase, policy)
    _amendment_anchor_commit, amendment_anchor_truth = first_truth_anchor!(
      root,
      authority.dig("delegation_amendment", "sha256"),
      "Founder delegation continuity amendment ledger"
    ) do |candidate|
      candidate.dig("phase_execution_envelope", "authority_basis", "delegation_amendment", "sha256") ==
        authority.dig("delegation_amendment", "sha256")
    end
    assert(envelope["accounting_basis"] == "DECLARED_TASK_BUDGET_RESERVATION_NOT_WALL_CLOCK",
           "phase execution envelope accounting basis drift")

    route_envelope = mapping(source_route["envelope"], "historical route envelope")
    limits = exact_keys(
      envelope["limits"],
      %w[engineering_tasks engineering_hours calendar_days active_tasks task_branches task_worktrees active_candidates],
      "phase execution envelope limits"
    )
    expected_limits = {
      "engineering_tasks" => route_envelope["max_engineering_tasks"],
      "engineering_hours" => route_envelope["max_engineering_hours"],
      "calendar_days" => route_envelope["max_calendar_days"],
      "active_tasks" => route_envelope["max_active_tasks"],
      "task_branches" => route_envelope["max_task_branches"],
      "task_worktrees" => route_envelope["max_task_worktrees"],
      "active_candidates" => route_envelope["max_active_candidates"]
    }
    assert(limits == expected_limits, "phase execution envelope limits drift from source route")

    anchored_source_entries = array(
      amendment_anchor_truth.dig("phase_execution_envelope", "task_ledger"),
      "anchored phase execution source task ledger"
    )
    ledger = validate_consumed_task_ledger!(
      root,
      envelope["task_ledger"],
      source_route,
      phase,
      anchored_source_entries,
      source_decision
    )
    expected_consumed = {
      "engineering_tasks" => ledger.sum { |entry| entry.dig("budget", "engineering_tasks") },
      "engineering_hours" => ledger.sum { |entry| entry.dig("budget", "engineering_hours") },
      "calendar_days" => ledger.sum { |entry| entry.dig("budget", "calendar_days") }
    }
    consumed = exact_keys(envelope["consumed"], %w[engineering_tasks engineering_hours calendar_days],
                          "phase execution envelope consumed")
    reserved = envelope["reserved"]
    reserved_budget = if reserved.nil?
                        { "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0 }
                      else
                        record = exact_keys(
                          reserved,
                          %w[task_id route_id status capacity_source_task_id budget contract authority],
                          "phase execution reserved Task"
                        )
                        assert(%w[ELIGIBLE_NOT_ACTIVATED ACTIVE].include?(record["status"]),
                               "phase execution reservation lifecycle drift")
                        exact_keys(
                          record["budget"],
                          %w[engineering_tasks engineering_hours calendar_days],
                          "phase execution reserved Task budget"
                        )
                      end
    assert(reserved_budget["engineering_tasks"].between?(0, 1) &&
           reserved_budget["engineering_hours"].is_a?(Integer) && reserved_budget["engineering_hours"] >= 0 &&
           reserved_budget["calendar_days"].is_a?(Integer) && reserved_budget["calendar_days"] >= 0,
           "phase execution reserved Task budget is invalid")
    assert(reserved.nil? || (reserved_budget["engineering_tasks"] == 1 &&
           reserved_budget["engineering_hours"].positive? && reserved_budget["calendar_days"].positive?),
           "phase execution reserved Task budget must reserve one positive Task")
    unless reserved.nil?
      capacity_source = source_capacity_task!(source_route, reserved["capacity_source_task_id"])
      consumed_source_ids = ledger.map { |entry| entry["task_id"] }
      assert(!consumed_source_ids.include?(capacity_source["task_id"]),
             "phase execution reservation reuses consumed source capacity")
    end
    remaining = exact_keys(envelope["remaining"], %w[engineering_tasks engineering_hours calendar_days],
                           "phase execution envelope remaining")
    assert(consumed == expected_consumed, "phase execution envelope consumed accounting drift")
    expected_remaining = {
      "engineering_tasks" => limits["engineering_tasks"] - consumed["engineering_tasks"] - reserved_budget["engineering_tasks"],
      "engineering_hours" => limits["engineering_hours"] - consumed["engineering_hours"] - reserved_budget["engineering_hours"],
      "calendar_days" => limits["calendar_days"] - consumed["calendar_days"] - reserved_budget["calendar_days"]
    }
    assert(remaining == expected_remaining, "phase execution envelope remaining accounting drift")
    assert(remaining.values.all? { |value| value >= 0 },
           "phase execution envelope remaining accounting is negative")
    derived_status = if reserved
                       "TASK_CAPACITY_RESERVED"
                     elsif remaining.values.all?(&:positive?)
                       "ACTIVE_REMAINING_CAPACITY"
                     else
                       "EXHAUSTED"
                     end
    assert(envelope["status"] == derived_status,
           "phase execution envelope status does not match reservation and remaining capacity")
    assert(envelope["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "phase execution envelope external effects exceed offline boundary")
    assert(route_envelope["external_effects"] == FALSE_EXTERNAL_EFFECTS,
           "source route external effects exceed offline boundary")
    envelope
  end

  def validate_reserved_trigger_evidence!(trigger, event, phase, historical_route, phase_envelope)
    evidence = parse_bound_json(trigger["evidence"], "Founder reserved trigger evidence")
    exact_keys(
      evidence,
      %w[schema_version category phase source_event source_route_id condition supporting_evidence],
      "Founder reserved trigger evidence"
    )
    assert(%w[founder-reserved-trigger-evidence/v1 founder-reserved-trigger-evidence/v2]
             .include?(evidence["schema_version"]),
           "Founder reserved trigger evidence schema drift")
    assert(evidence["category"] == trigger["category"] && evidence["phase"] == phase,
           "Founder reserved trigger Evidence category or Phase drift")
    assert(evidence["source_event"] == event,
           "Founder reserved trigger Evidence source event drift")
    assert(evidence["source_route_id"] == historical_route["route_id"],
           "Founder reserved trigger Evidence source Route drift")

    condition_keys = %w[
      phase_route_change material_scope_or_permission_expansion requested_budget
      requested_external_effects irreversible_asset_action
      material_legal_privacy_commercial_commitment critical_residual_risk_acceptance
    ]
    condition_keys << "requested_budget_status" if evidence["schema_version"] == "founder-reserved-trigger-evidence/v2"
    condition = exact_keys(evidence["condition"], condition_keys,
                           "Founder reserved trigger condition")
    requested_budget = nil
    if evidence["schema_version"] == "founder-reserved-trigger-evidence/v1"
      requested_budget = exact_keys(
        condition["requested_budget"],
        %w[engineering_tasks engineering_hours calendar_days],
        "Founder reserved trigger requested budget"
      )
      requested_budget.each do |key, value|
        assert(value.is_a?(Integer) && value >= 0,
               "Founder reserved trigger requested budget #{key} is invalid")
      end
    else
      assert(condition["requested_budget"].nil? &&
             condition["requested_budget_status"] == "NOT_PROPOSED_FOUNDER_DECIDES_IF_P2_CONTINUES",
             "exhausted Phase decision Evidence must not invent a new Founder budget")
    end
    requested_effects = exact_keys(
      condition["requested_external_effects"],
      FALSE_EXTERNAL_EFFECTS.keys,
      "Founder reserved trigger requested external effects"
    )
    requested_effects.each do |key, value|
      assert(value == true || value == false,
             "Founder reserved trigger requested external effect #{key} is not boolean")
    end
    boolean_keys = %w[
      phase_route_change material_scope_or_permission_expansion irreversible_asset_action
      material_legal_privacy_commercial_commitment critical_residual_risk_acceptance
    ]
    boolean_keys.each do |key|
      assert(condition[key] == true || condition[key] == false,
             "Founder reserved trigger condition #{key} is not boolean")
    end

    limits = mapping(phase_envelope["limits"], "phase execution envelope limits")
    budget_expands = if requested_budget
                       requested_budget.any? do |key, value|
                         value > limits.fetch(key)
                       end
                     else
                       consumed = mapping(phase_envelope["consumed"],
                                          "phase execution envelope consumed")
                       remaining = mapping(phase_envelope["remaining"],
                                           "phase execution envelope remaining")
                       %w[engineering_tasks engineering_hours calendar_days].all? do |key|
                         limits.fetch(key) == consumed.fetch(key) && remaining.fetch(key).zero?
                       end && phase_envelope["status"] == "EXHAUSTED" &&
                         phase_envelope["reserved"].nil?
                     end
    effect_expands = requested_effects.values.any?(true)
    signals = {
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" => condition["phase_route_change"],
      "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE" =>
        condition["material_scope_or_permission_expansion"] && budget_expands,
      "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT" => effect_expands,
      "IRREVERSIBLE_ASSET_REMOVAL" => condition["irreversible_asset_action"],
      "MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT" =>
        condition["material_legal_privacy_commercial_commitment"],
      "CRITICAL_RESIDUAL_RISK_ACCEPTANCE" => condition["critical_residual_risk_acceptance"]
    }
    assert(signals.fetch(trigger["category"]),
           "Founder reserved trigger Evidence does not prove its category")
    other_signals = signals.reject { |category, _value| category == trigger["category"] }
    assert(other_signals.values.none?(true),
           "Founder reserved trigger Evidence contains ambiguous reserved conditions")

    support = array(evidence["supporting_evidence"], "Founder reserved trigger supporting Evidence")
    expected_support = array(phase_envelope["task_ledger"], "phase execution task ledger").map do |entry|
      mapping(entry, "phase execution task ledger entry")["outcome_receipt"]
    end
    assert(!support.empty? && support == expected_support,
           "Founder budget expansion trigger must bind every consumed Task outcome receipt")
    support.each_with_index do |identity, index|
      validate_identity(identity, "Founder reserved trigger supporting Evidence[#{index}]")
    end
    evidence
  end

  def validate_strategic_hold_decision!(root, truth, resolution, phase, phase_gate_status,
                                        phase_envelope)
    resolution = exact_keys(
      resolution,
      %w[status authorization_token packet structured_decision],
      "Founder strategic-hold resolution"
    )
    assert(resolution["status"] == "FOUNDER_DECISION_RECORDED",
           "Founder strategic-hold resolution status drift")
    assert(resolution["authorization_token"] ==
           "AUTHORIZE_P2_TERMINAL_RESEARCH_NON_PASS_AND_STRATEGIC_HOLD_V1",
           "Founder strategic-hold authorization token drift")
    packet_identity = exact_keys(
      resolution["packet"], %w[path byte_length sha256],
      "Founder strategic-hold packet"
    )
    validate_identity(packet_identity, "Founder strategic-hold packet")
    decision_identity = exact_keys(
      resolution["structured_decision"], %w[path byte_length sha256],
      "Founder strategic-hold structured decision"
    )
    decision = parse_bound_json(decision_identity, "Founder strategic-hold structured decision")
    exact_keys(
      decision,
      %w[schema_version decision_id authorization_token accepted_at_utc canonical_start goal phase decision phase_envelope phase_exit_gate prohibited_engineering_chains external_effects packet],
      "Founder strategic-hold structured decision"
    )
    assert(decision["schema_version"] == STRATEGIC_HOLD_DECISION_SCHEMA,
           "Founder strategic-hold structured decision schema drift")
    assert(decision["decision_id"] ==
           "FOUNDER_P2_TERMINAL_RESEARCH_NON_PASS_AND_STRATEGIC_HOLD_2026_08_09" &&
           decision["authorization_token"] == resolution["authorization_token"],
           "Founder strategic-hold structured decision identity drift")
    assert(decision["accepted_at_utc"].is_a?(String) &&
           decision["accepted_at_utc"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/),
           "Founder strategic-hold decision timestamp is invalid")

    start = exact_keys(decision["canonical_start"], %w[commit tree main_clean],
                       "Founder strategic-hold canonical start")
    assert(start["commit"].to_s.match?(/\A[0-9a-f]{40}\z/) &&
           start["tree"].to_s.match?(/\A[0-9a-f]{40}\z/) && start["main_clean"] == true,
           "Founder strategic-hold canonical start identity drift")
    assert(git(root, "rev-parse", "#{start["commit"]}^{tree}").strip == start["tree"],
           "Founder strategic-hold canonical start tree drift")
    _out, _err, ancestor = Open3.capture3(
      "git", "merge-base", "--is-ancestor", start["commit"], "HEAD", chdir: root.to_s
    )
    assert(ancestor.success?, "Founder strategic-hold canonical start is not an ancestor")

    goal = exact_keys(decision["goal"], %w[status canonical_sha256 canonical_byte_length],
                      "Founder strategic-hold Goal")
    truth_goal = mapping(truth["goal"], "goal")
    assert(goal == {
      "status" => "ACTIVE",
      "canonical_sha256" => truth_goal["observed_body_sha256"],
      "canonical_byte_length" => truth_goal["observed_body_byte_length"]
    }, "Founder strategic-hold Goal identity drift")
    assert(decision["phase"] == phase && phase == "P2",
           "Founder strategic-hold Phase drift")

    disposition = exact_keys(
      decision["decision"],
      %w[disposition current_task p2_capability_progress_percent envelope_expanded new_task_authorized p3_entry_authorized remote_write_authorized engineering_action_eligible next_founder_intervention],
      "Founder strategic-hold disposition"
    )
    assert(disposition == {
      "disposition" => STRATEGIC_HOLD_STATUS,
      "current_task" => "NONE",
      "p2_capability_progress_percent" => 0,
      "envelope_expanded" => false,
      "new_task_authorized" => false,
      "p3_entry_authorized" => false,
      "remote_write_authorized" => false,
      "engineering_action_eligible" => false,
      "next_founder_intervention" =>
        "EXPLICIT_NEW_STRATEGY_CONSTITUTION_P2_OBJECTIVE_EXIT_GATE_OR_PHASE_ROUTE_DECISION"
    }, "Founder strategic-hold disposition drift")

    decision_envelope = exact_keys(
      decision["phase_envelope"], %w[status limits consumed remaining reserved],
      "Founder strategic-hold Phase envelope"
    )
    %w[limits consumed remaining].each do |key|
      exact_keys(decision_envelope[key], %w[engineering_tasks engineering_hours calendar_days],
                 "Founder strategic-hold Phase envelope #{key}")
    end
    expected_envelope = {
      "status" => phase_envelope["status"],
      "limits" => mapping(phase_envelope["limits"], "phase execution envelope limits").slice(
        "engineering_tasks", "engineering_hours", "calendar_days"
      ),
      "consumed" => phase_envelope["consumed"],
      "remaining" => phase_envelope["remaining"],
      "reserved" => phase_envelope["reserved"]
    }
    assert(decision_envelope == expected_envelope && decision_envelope["status"] == "EXHAUSTED",
           "Founder strategic-hold Phase envelope drift")

    exit_gate = exact_keys(
      decision["phase_exit_gate"],
      %w[status missing_required_item missing_required_item_status phase_complete],
      "Founder strategic-hold Phase Exit Gate"
    )
    required_item = "CONTEXT_BENCHMARK_BEATS_SIMPLE_RETRIEVAL_BASELINES"
    ledger_item = truth.dig("strict_phase_gate_ledger", "phases", phase, "required_items", required_item)
    assert(exit_gate == {
      "status" => phase_gate_status,
      "missing_required_item" => required_item,
      "missing_required_item_status" => mapping(ledger_item, "P2 required Exit item")["status"],
      "phase_complete" => false
    } && phase_gate_status == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "Founder strategic-hold Phase Exit Gate drift")
    assert(array(decision["prohibited_engineering_chains"],
                 "Founder strategic-hold prohibited chains") == %w[
                   P2_061 SUCCESSOR REPLACEMENT CORRECTION NORMALIZATION CLOSURE FEASIBILITY REMEDIATION
                 ], "Founder strategic-hold prohibited chain drift")
    assert(exact_keys(decision["external_effects"], FALSE_EXTERNAL_EFFECTS.keys,
                      "Founder strategic-hold external effects") == FALSE_EXTERNAL_EFFECTS,
           "Founder strategic-hold external effect drift")
    assert(exact_keys(decision["packet"], %w[path byte_length sha256],
                      "Founder strategic-hold packet binding") == packet_identity,
           "Founder strategic-hold packet binding drift")
    decision_identity
  end

  def validate_control!(truth, phase, phase_gate_status, phase_complete, historical_route,
                        phase_envelope, root: Pathname.new(`git rev-parse --show-toplevel`.strip))
    control = mapping(truth["founder_escalation_control"], "founder_escalation_control")
    strategic_hold = control["schema_version"] == "founder-escalation-control/v2"
    control_keys = %w[
      schema_version disposition source_event reserved_trigger phase_gate_status
      founder_decision_required next_action_owner next_eligible_action
    ]
    control_keys << "resolution" if strategic_hold
    exact_keys(control, control_keys, "founder_escalation_control")
    assert(%w[founder-escalation-control/v1 founder-escalation-control/v2]
             .include?(control["schema_version"]),
           "Founder escalation control schema drift")
    assert(control["phase_gate_status"] == phase_gate_status,
           "Founder escalation control Phase Gate projection drift")
    event = exact_keys(control["source_event"], %w[kind task_id status],
                       "Founder escalation source_event")
    trigger = exact_keys(control["reserved_trigger"], %w[category evidence],
                         "Founder escalation reserved_trigger")
    current_route = mapping(truth["current_phase_route"], "current_phase_route")
    source_route_ref = phase_envelope.dig("authority_basis", "source_route_ref")
    source_route = mapping(truth[source_route_ref], "phase execution source Route")
    single_task_projection =
      source_route["schema_version"] == "1.2" &&
      current_route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA &&
      %w[ELIGIBLE_NOT_ACTIVATED ACTIVE].include?(current_route.dig("selected_task", "status"))
    if single_task_projection
      task_status = current_route.dig("selected_task", "status")
      assert(event == {
        "kind" => task_status == "ACTIVE" ? SINGLE_TASK_ACTIVE_EVENT : SINGLE_TASK_READY_EVENT,
        "task_id" => current_route.dig("selected_task", "task_id"),
        "status" => task_status
      }, "single-Task Founder expansion control does not project the exact READY or ACTIVE Task")
    elsif ORDINARY_TERMINAL_EVENTS.include?(event["kind"])
      historical_tasks = if historical_route["task_plan"].is_a?(Array)
                           historical_route["task_plan"]
                         elsif historical_route["selected_task"].is_a?(Hash)
                           [historical_route["selected_task"]]
                         else
                           fail!("ordinary terminal historical route has no closed Task descriptor")
                         end
      matching_tasks = historical_tasks.select do |task|
        task.is_a?(Hash) && task["task_id"] == event["task_id"]
      end
      assert(matching_tasks.length == 1, "ordinary terminal event Task identity drift")
      terminal_task = matching_tasks.first
      assert(event["status"] == terminal_task["status"] && event["status"] == historical_route["status"],
             "ordinary terminal event status drift")
      assert(event["status"].to_s.start_with?("TERMINAL_") && event["status"].to_s.include?("NON_PASS"),
             "ordinary terminal event is not a terminal NON_PASS")
    end

    if strategic_hold
      assert(trigger["category"] ==
             "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE",
             "Founder strategic hold must resolve the exact exhausted-envelope trigger")
      assert(event == {
        "kind" => "PHASE_ENVELOPE_EXPANSION_REQUIRED",
        "task_id" => nil,
        "status" => "PENDING_FOUNDER_RESERVED_DECISION"
      }, "Founder strategic hold source event drift")
      assert(phase_envelope["status"] == "EXHAUSTED" && phase_envelope["reserved"].nil?,
             "Founder strategic hold requires exact exhausted unreserved accounting")
      validate_reserved_trigger_evidence!(
        trigger, event, phase, historical_route, phase_envelope
      )
      validate_strategic_hold_decision!(
        root, truth, control["resolution"], phase, phase_gate_status, phase_envelope
      )
      assert(control["disposition"] == STRATEGIC_HOLD_DISPOSITION &&
             control["founder_decision_required"] == false &&
             control["next_action_owner"] == "NONE" &&
             control["next_eligible_action"] == STRATEGIC_HOLD_ACTION,
             "Founder strategic-hold control projection drift")
      return control
    end

    if trigger["category"] == "NONE"
      assert(trigger["evidence"].nil?, "no reserved trigger may not carry evidence")
      assert(!phase_complete, "completed Phase cannot use ordinary continuation disposition")
      assert(control["disposition"] == CONTINUE_DISPOSITION,
             "no-trigger lifecycle must continue inside the Phase")
      assert(control["founder_decision_required"] == false,
             "no-trigger lifecycle cannot require Founder decision")
      assert(control["next_action_owner"] == "MASTER_CEO_AGENT",
             "no-trigger lifecycle next action owner must be Master")
      if single_task_projection
        expected_action = current_route.dig("selected_task", "status") == "ACTIVE" ?
          "COMPLETE_CURRENT_TASK_GATE" : "MASTER_ACTIVATE_PHASE_DELEGATED_TASK"
        assert(control["next_eligible_action"] == expected_action &&
               control["next_eligible_action"] == current_route["next_eligible_action"],
               "single-Task Founder expansion control next action does not match the exact Task lifecycle")
      else
        assert(ORDINARY_TERMINAL_EVENTS.include?(event["kind"]),
               "no-trigger continuation requires an ordinary terminal lifecycle event")
        assert(control["next_eligible_action"] == CONTINUE_ACTION,
               "ordinary terminal lifecycle next action drift")
      end
      return control
    end

    assert(RESERVED_TRIGGERS.include?(trigger["category"]), "unknown Founder reserved trigger")
    assert(%w[PHASE_ENTRY_OR_EXIT MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE]
             .include?(trigger["category"]),
           "terminal transition only supports mechanically derived Phase exit or envelope expansion")
    expected_event_kind = RESERVED_EVENT_KINDS.fetch(trigger["category"])
    assert(event["kind"] == expected_event_kind,
           "Founder reserved trigger source event kind drift")
    if trigger["category"] == "PHASE_ENTRY_OR_EXIT"
      assert(event["task_id"].nil? && event["status"] == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "Phase exit source event drift")
      assert(phase_complete && phase_gate_status == "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "Phase exit escalation requires a complete eligible Exit Gate")
      assert(trigger["evidence"].nil?, "Phase Gate ledger is the Phase exit trigger evidence")
    else
      assert(event["status"] == "PENDING_FOUNDER_RESERVED_DECISION",
             "Founder reserved source event status drift")
      assert(event["task_id"].nil?,
             "Phase envelope expansion source event may not impersonate a Task outcome")
      assert(phase_envelope["status"] == "EXHAUSTED" && phase_envelope["reserved"].nil?,
             "Phase envelope expansion requires exact unreserved exhausted accounting")
      validate_reserved_trigger_evidence!(
        trigger,
        event,
        phase,
        historical_route,
        phase_envelope
      )
    end
    assert(control["disposition"] == FOUNDER_DISPOSITION,
           "reserved trigger requires Founder decision disposition")
    assert(control["founder_decision_required"] == true,
           "reserved trigger requires Founder decision flag")
    assert(control["next_action_owner"] == "HUMAN_FOUNDER",
           "reserved trigger next action owner must be Founder")
    assert(control["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
           "reserved trigger next action drift")
    control
  end

  def validate_continue_state!(truth, policy, historical_route, historical_route_ref, phase_envelope, control)
    project = mapping(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[schema_version route_id status execution_status scheduling_status phase phase_entry_status policy founder_phase_route_decision_required next_eligible_action phase_execution_envelope_ref historical_terminal_route_ref external_effects additional_write_roots inherited_worktree_inventory_source],
      "current_phase_route delegated continuation hold"
    )
    assert(route["schema_version"] == CONTINUATION_ROUTE_SCHEMA, "delegated continuation route schema drift")
    assert(route["route_id"] == "#{route["phase"]}_PHASE_DELEGATED_CONTINUATION_PENDING_TASK_SELECTION",
           "delegated continuation route id drift")
    assert(route["status"] == "AUTHORIZED_READY" &&
           route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
           route["scheduling_status"] == "MASTER_SELECTING_NEXT_INDEPENDENT_PHASE_LOCAL_TASK",
           "delegated continuation route lifecycle drift")
    assert(route["phase"] == project["current_phase"] && route["phase_entry_status"] == "AUTHORIZED",
           "delegated continuation route Phase drift")
    assert(route["policy"] == policy.slice("path", "version", "sha256"),
           "delegated continuation route policy binding drift")
    assert(route["founder_phase_route_decision_required"] == false,
           "delegated continuation route cannot require Founder decision")
    assert(route["next_eligible_action"] == CONTINUE_ACTION,
           "delegated continuation route next action drift")
    assert(route["phase_execution_envelope_ref"] == "phase_execution_envelope",
           "delegated continuation route Phase envelope reference drift")
    assert(route["historical_terminal_route_ref"] == historical_route_ref &&
           route["inherited_worktree_inventory_source"] == historical_route_ref,
           "delegated continuation historical route reference drift")
    assert(truth[route["historical_terminal_route_ref"]].equal?(historical_route) ||
           truth[route["historical_terminal_route_ref"]] == historical_route,
           "delegated continuation historical route binding drift")
    assert(route["external_effects"] == FALSE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "delegated continuation hold may not grant effects or write roots")

    assert(project["p2_entry_status"] == "AUTHORIZED" &&
           project["p2_execution_status"] == "ACTIVE" &&
           project["phase_execution_status"] == "ACTIVE" &&
           project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY",
           "project Phase continuation status drift")

    active = mapping(truth["active_work"], "active_work")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE",
           "delegated continuation requires current Task NONE")
    assert(active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_CONTINUATION_READY",
           "delegated continuation Task resource state drift")
    assert(active["founder_decision_required"] == false &&
           active["founder_decision_required_scope"].nil? &&
           active["escalation_reason"].nil? &&
           active["user_action_required"] == "NONE" &&
           active["phase_route_decision_required"] == false &&
           active["phase_route_user_action_required"] == "NONE" &&
           active["next_eligible_action"] == CONTINUE_ACTION,
           "active_work ordinary terminal projection drift")
    assert(active["founder_reserved_authorization"].nil? &&
           active["founder_reserved_authorization_sha256"].nil?,
           "ordinary continuation must not invent Founder-reserved authorization")
    assert(mapping(active["external_effects"], "active_work.external_effects") == FALSE_EXTERNAL_EFFECTS,
           "active_work external effects drift")
    assert(control["disposition"] == CONTINUE_DISPOSITION,
           "continue state requires no-reserved-trigger disposition")
    assert(phase_envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
           mapping(phase_envelope["remaining"], "phase execution envelope remaining").values.all?(&:positive?),
           "ordinary continuation requires positive Phase envelope capacity")
  end

  def validate_delegated_task_state!(truth, policy, preceding_route, preceding_route_ref,
                                     phase_envelope, control)
    project = mapping(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[
        schema_version route_id status execution_status scheduling_status phase
        phase_entry_status policy founder_phase_route_decision_required next_eligible_action
        phase_execution_envelope_ref source_authority_route_ref preceding_terminal_route_ref
        selected_task external_effects additional_write_roots inherited_worktree_inventory_source
      ],
      "current_phase_route delegated independent Task"
    )
    assert(route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA,
           "delegated independent Task route schema drift")
    assert(route["phase"] == project["current_phase"] && route["phase_entry_status"] == "AUTHORIZED",
           "delegated independent Task route Phase drift")
    assert(route["policy"] == policy.slice("path", "version", "sha256"),
           "delegated independent Task route policy binding drift")
    assert(route["founder_phase_route_decision_required"] == false,
           "delegated independent Task route cannot require Founder decision")
    assert(route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["source_authority_route_ref"] ==
             phase_envelope.dig("authority_basis", "source_route_ref") &&
           route["preceding_terminal_route_ref"] == preceding_route_ref &&
           route["inherited_worktree_inventory_source"] == preceding_route_ref &&
           truth[preceding_route_ref] == preceding_route,
           "delegated independent Task route authority references drift")
    assert(route["external_effects"] == FALSE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "delegated independent Task route may not expand effects or write roots")

    source_route = mapping(
      truth[phase_envelope.dig("authority_basis", "source_route_ref")],
      "delegated independent Task source Route"
    )
    task_keys = %w[
      task_id status task_kind capability objective capacity_source_task_id budget max_same_task_repairs
      contract independence
    ]
    task_keys << "repair_accounting" if route["selected_task"].is_a?(Hash) &&
                                                route["selected_task"].key?("repair_accounting")
    task = exact_keys(
      route["selected_task"],
      task_keys,
      "delegated independent Task descriptor"
    )
    task_id = task["task_id"]
    assert(task_id.to_s.match?(/\AAIOS-#{route['phase']}-[0-9]{3}_[A-Z0-9_]+\z/),
           "delegated independent Task id is invalid")
    assert(route["route_id"] == "#{task_id}_PHASE_DELEGATED_ROUTE",
           "delegated independent Task Route id drift")
    boundary = mapping(truth["phase_boundary"], "phase_boundary")
    assert(array(boundary["allowed_task_kinds"], "Phase allowed Task kinds").include?(task["task_kind"]),
           "delegated Task kind is outside the current Phase")
    assert(array(boundary["allowed_capabilities"], "Phase allowed capabilities").include?(task["capability"]),
           "delegated Task capability is outside the current Phase")
    assert(task["objective"].is_a?(String) && !task["objective"].empty?,
           "delegated independent Task objective missing")
    capacity_source = source_capacity_task!(source_route, task["capacity_source_task_id"])
    if source_route["schema_version"] == "1.2"
      assert(capacity_source["status"] == task["status"],
             "single-Task source capacity lifecycle does not equal the delegated Task")
      assert(source_route["first_task"] == capacity_source &&
             array(source_route["task_plan"], "single-Task source Route task plan").length == 1,
             "single-Task source capacity does not equal its only first Task")
    end
    assert(!capacity_source["status"].to_s.start_with?("TERMINAL_") &&
           !capacity_source["status"].to_s.include?("ACCEPTED"),
           "delegated independent Task capacity source is already consumed")
    budget = exact_keys(
      task["budget"],
      %w[engineering_hours calendar_days implementation_iterations candidates],
      "delegated independent Task budget"
    )
    budget.each do |key, value|
      assert(value.is_a?(Integer) && value.positive?, "delegated independent Task budget #{key} is invalid")
    end
    assert(budget["candidates"] == 1,
           "delegated independent Task candidate budget must equal one")
    max_repairs = integer(task["max_same_task_repairs"], "delegated Task same-Task repair budget")
    assert(max_repairs >= 0,
           "delegated Task same-Task repair budget must not be negative")
    assert(max_repairs <= budget["implementation_iterations"] - 1,
           "delegated Task repairs exceed implementation iterations minus one")
    assert(
           max_repairs <= capacity_source["max_same_task_repairs"] &&
           max_repairs <= truth.dig("phase_delegation", "anti_loop", "maximum_same_task_bounded_contract_repairs"),
           "delegated Task same-Task repair budget exceeds Phase delegation")
    if task.key?("repair_accounting")
      validate_repair_accounting!(
        task["repair_accounting"],
        capacity_source["max_same_task_repairs"],
        max_repairs,
        "delegated independent Task repair_accounting"
      )
    end
    assert(budget["engineering_hours"] <= capacity_source["engineering_hours"] &&
           budget["calendar_days"] <= capacity_source["calendar_days"] &&
           budget["implementation_iterations"] <= capacity_source["max_implementation_iterations"] &&
           budget["candidates"] <= capacity_source["max_candidates"],
           "delegated independent Task budget exceeds its Founder-bound source capacity slot")
    independence = exact_keys(
      task["independence"],
      %w[
        new_task_id new_execution_nonce new_branch new_worktree new_contract new_evidence_root
        rejected_lineage_read rejected_lineage_compare rejected_lineage_copy
        same_phase_objective successor_or_replacement
      ],
      "delegated independent Task independence"
    )
    assert(independence == {
      "new_task_id" => true,
      "new_execution_nonce" => true,
      "new_branch" => true,
      "new_worktree" => true,
      "new_contract" => true,
      "new_evidence_root" => true,
      "rejected_lineage_read" => false,
      "rejected_lineage_compare" => false,
      "rejected_lineage_copy" => false,
      "same_phase_objective" => true,
      "successor_or_replacement" => false
    }, "delegated independent Task independence classification drift")
    historical_ids = truth.select { |key, value| key.to_s.start_with?("historical_") && value.is_a?(Hash) }
                          .flat_map do |historical_key, historical|
      task_plan_ids = Array(historical["task_plan"]).each_with_object([]) do |item, ids|
        next unless item.is_a?(Hash)
        source_task_status = source_route["schema_version"] == "1.2" ?
          task["status"] : "ACTIVE"
        next if historical_key == route["source_authority_route_ref"] &&
                item["task_id"] == task_id && item["status"] == source_task_status
        ids << item["task_id"] if item["task_id"]
      end
      selected_id = historical.dig("selected_task", "task_id")
      task_plan_ids + [selected_id].compact
    end
    assert(!historical_ids.include?(task_id), "delegated independent Task reuses a historical Task id")

    reservation = mapping(phase_envelope["reserved"], "delegated independent Task reservation")
    expected_reservation_budget = {
      "engineering_tasks" => 1,
      "engineering_hours" => budget["engineering_hours"],
      "calendar_days" => budget["calendar_days"]
    }
    assert(reservation["task_id"] == task_id && reservation["route_id"] == route["route_id"] &&
           reservation["capacity_source_task_id"] == task["capacity_source_task_id"] &&
           reservation["status"] == task["status"] && reservation["budget"] == expected_reservation_budget &&
           reservation["contract"] == task["contract"],
           "delegated independent Task reservation binding drift")
    assert(phase_envelope["status"] == "TASK_CAPACITY_RESERVED",
           "delegated independent Task requires exact Phase capacity reservation")

    active = mapping(truth["active_work"], "active_work")
    assert(control["disposition"] == CONTINUE_DISPOSITION,
           "delegated independent Task requires autonomous continuation disposition")
    if task["status"] == "ELIGIBLE_NOT_ACTIVATED"
      assert(route["status"] == "AUTHORIZED_READY" &&
             route["execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
             route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" &&
             route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
             "delegated independent Task READY lifecycle drift")
      assert(reservation["authority"].nil?, "READY delegated Task may not pre-create active authority")
      assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
             active["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
             "delegated independent Task READY active_work drift")
      assert(project["current_route_execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
             mapping(truth["goal"], "goal")["current_task_authority"] == "NONE",
             "delegated independent Task READY project or Goal projection drift")
    elsif task["status"] == "ACTIVE"
      assert(route["status"] == "ACTIVE" && route["execution_status"] == "ACTIVE" &&
             route["scheduling_status"] == "ACTIVE_PHASE_DELEGATED_TASK" &&
             route["next_eligible_action"] == "COMPLETE_CURRENT_TASK_GATE",
             "delegated independent Task ACTIVE lifecycle drift")
      reserved_authority = exact_keys(
        reservation["authority"],
        %w[path byte_length sha256],
        "ACTIVE delegated Task reserved authority"
      )
      active_authority = exact_keys(
        active["authority_record"],
        %w[path byte_length sha256],
        "ACTIVE delegated Task active_work authority"
      )
      assert(reserved_authority == active_authority &&
             active["current_execution_authorization"] == reserved_authority["path"] &&
             active["current_execution_authorization_sha256"] == reserved_authority["sha256"],
             "ACTIVE delegated Task reserved authority identity drift")
      validate_identity(reserved_authority, "ACTIVE delegated Task reserved authority")
      assert(active["current_task"] == task_id && active["current_task_status"] == "ACTIVE" &&
             active["task_resource_state"] == "ACTIVE_UNIQUE_PHASE_DELEGATED" &&
             active["next_eligible_action"] == "COMPLETE_CURRENT_TASK_GATE",
             "delegated independent Task ACTIVE active_work drift")
      assert(project["current_route_execution_status"] == "ACTIVE_PHASE_DELEGATED_TASK" &&
             mapping(truth["goal"], "goal")["current_task_authority"] == task_id,
             "delegated independent Task ACTIVE project or Goal projection drift")
      historical_active = truth.select do |key, value|
        key.to_s.start_with?("historical_") && value.is_a?(Hash) &&
          value["current_task"].is_a?(String) && value["current_task"] != "NONE"
      end.values
      historical_active.each do |record|
        assert(active["execution_nonce"] != record["execution_nonce"] &&
               active["authorization_id"] != record["authorization_id"] &&
               active["task_branch"] != record["task_branch"] &&
               active["task_worktree"] != record["task_worktree"] &&
               active["execution_evidence_root"] != record["execution_evidence_root"] &&
               task.dig("contract", "path") != record.dig("current_task_contract", "path") &&
               reserved_authority["path"] != record.dig("authority_record", "path"),
               "delegated independent Task reuses historical execution lineage identity")
      end
    else
      fail!("delegated independent Task status is invalid")
    end
    assert(active["founder_reserved_authorization"].nil? &&
           active["founder_reserved_authorization_sha256"].nil? &&
           active["founder_decision_required"] == false &&
           active["phase_route_decision_required"] == false &&
           active["user_action_required"] == "NONE" &&
           active["phase_route_user_action_required"] == "NONE",
           "delegated independent Task must not invent a Founder authorization or action")
    assert(project["p2_entry_status"] == "AUTHORIZED" &&
           project["p2_execution_status"] == "ACTIVE" &&
           project["phase_execution_status"] == "ACTIVE",
           "delegated independent Task requires active P2 Phase execution")
  end

  def validate_reserved_state!(truth, policy, historical_route_ref, phase_envelope, control)
    project = mapping(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[schema_version route_id status execution_status scheduling_status phase phase_entry_status policy founder_phase_route_decision_required next_eligible_action phase_execution_envelope_ref historical_terminal_route_ref external_effects additional_write_roots inherited_worktree_inventory_source],
      "current_phase_route Founder reserved hold"
    )
    assert(route["schema_version"] == RESERVED_ROUTE_SCHEMA,
           "Founder reserved disposition requires the exact reserved-decision hold schema")
    assert(route["route_id"].to_s.match?(/\AP(?:0|[1-9]|1[0-2])_FOUNDER_RESERVED_DECISION_HOLD\z/),
           "Founder reserved hold route id drift")
    assert(route["status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
           route["execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
           route["scheduling_status"] == "STOPPED_AT_FOUNDER_RESERVED_DECISION",
           "Founder reserved hold route lifecycle drift")
    assert(route["phase"] == project["current_phase"] && route["phase_entry_status"] == "AUTHORIZED",
           "Founder reserved hold Phase drift")
    assert(route["policy"] == policy.slice("path", "version", "sha256"),
           "Founder reserved hold policy binding drift")
    assert(route["founder_phase_route_decision_required"] == true &&
           route["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
           "Founder reserved hold decision projection drift")
    assert(route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["historical_terminal_route_ref"] == historical_route_ref &&
           route["inherited_worktree_inventory_source"] == historical_route_ref,
           "Founder reserved hold reference drift")
    assert(route["external_effects"] == FALSE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "Founder reserved hold may not grant effects or write roots")

    assert(project["phase_execution_status"] == "STOPPED_AT_FOUNDER_RESERVED_DECISION" &&
           project["current_route_execution_status"] == "FOUNDER_RESERVED_DECISION_REQUIRED",
           "project Founder reserved hold status drift")
    active = mapping(truth["active_work"], "active_work")
    category = mapping(control["reserved_trigger"], "Founder reserved trigger")["category"]
    if phase_envelope["status"] == "EXHAUSTED"
      assert(category == "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE",
             "exhausted Phase capacity requires the exact envelope-expansion trigger")
    end
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE",
           "Founder reserved hold requires current Task NONE")
    assert(active["task_resource_state"] == "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD",
           "Founder reserved hold Task resource state drift")
    assert(active["founder_decision_required"] == true &&
           active["founder_decision_required_scope"] == category &&
           active["escalation_reason"] == category &&
           active["user_action_required"] == "FOUNDER_RESERVED_DECISION" &&
           active["phase_route_decision_required"] == true &&
           active["phase_route_user_action_required"] == "FOUNDER_RESERVED_DECISION" &&
           active["next_eligible_action"] == "FOUNDER_RESERVED_DECISION",
           "active_work Founder reserved decision projection drift")
  end

  def validate_strategic_hold_state!(truth, policy, historical_route_ref, phase_envelope, control)
    project = mapping(truth["project"], "project")
    route = exact_keys(
      truth["current_phase_route"],
      %w[schema_version route_id status execution_status scheduling_status phase phase_entry_status policy founder_phase_route_decision_required next_eligible_action phase_execution_envelope_ref historical_terminal_route_ref founder_decision external_effects additional_write_roots inherited_worktree_inventory_source],
      "current_phase_route Founder strategic hold"
    )
    assert(route["schema_version"] == STRATEGIC_HOLD_ROUTE_SCHEMA,
           "Founder resolved hold requires the exact strategic-hold schema")
    assert(route["route_id"] == "#{route["phase"]}_TERMINAL_RESEARCH_NON_PASS_STRATEGIC_HOLD" &&
           route["status"] == STRATEGIC_HOLD_STATUS &&
           route["execution_status"] == STRATEGIC_HOLD_STATUS &&
           route["scheduling_status"] == "FOUNDER_RESOLVED_NO_ENGINEERING_ACTION",
           "Founder strategic-hold route lifecycle drift")
    assert(route["phase"] == project["current_phase"] && route["phase_entry_status"] == "AUTHORIZED",
           "Founder strategic-hold Phase drift")
    assert(route["policy"] == policy.slice("path", "version", "sha256"),
           "Founder strategic-hold policy binding drift")
    assert(route["founder_phase_route_decision_required"] == false &&
           route["next_eligible_action"] == STRATEGIC_HOLD_ACTION,
           "Founder strategic-hold next action drift")
    assert(route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["historical_terminal_route_ref"] == historical_route_ref &&
           route["inherited_worktree_inventory_source"] == historical_route_ref,
           "Founder strategic-hold historical reference drift")
    decision_identity = exact_keys(
      route["founder_decision"], %w[path byte_length sha256],
      "Founder strategic-hold Route decision"
    )
    assert(decision_identity == control.dig("resolution", "structured_decision"),
           "Founder strategic-hold Route decision binding drift")
    validate_identity(decision_identity, "Founder strategic-hold Route decision")
    assert(route["external_effects"] == FALSE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "Founder strategic hold may not grant effects or write roots")
    assert(phase_envelope["status"] == "EXHAUSTED" && phase_envelope["reserved"].nil? &&
           mapping(phase_envelope["remaining"], "phase execution envelope remaining").values.all?(&:zero?),
           "Founder strategic hold requires exhausted zero-remaining capacity")

    assert(project["p2_execution_status"] == STRATEGIC_HOLD_STATUS &&
           project["phase_execution_status"] == STRATEGIC_HOLD_STATUS &&
           project["current_route_execution_status"] == STRATEGIC_HOLD_STATUS,
           "project Founder strategic-hold status drift")
    active = mapping(truth["active_work"], "active_work")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["task_resource_state"] == "NO_ACTIVE_TASK_FOUNDER_RESOLVED_STRATEGIC_HOLD",
           "Founder strategic hold requires Task NONE")
    assert(active["founder_reserved_authorization"] == decision_identity["path"] &&
           active["founder_reserved_authorization_sha256"] == decision_identity["sha256"],
           "Founder strategic-hold active authorization drift")
    assert(active["founder_decision_required"] == false &&
           active["founder_decision_required_scope"].nil? &&
           active["escalation_reason"].nil? &&
           active["user_action_required"] == "NONE" &&
           active["phase_route_decision_required"] == false &&
           active["phase_route_user_action_required"] == "NONE" &&
           active["next_eligible_action"] == STRATEGIC_HOLD_ACTION,
           "active_work Founder strategic-hold projection drift")
    assert(mapping(truth["goal"], "goal")["current_task_authority"] == "NONE",
           "Founder strategic hold must not grant Goal Task authority")
  end

  def validate_non_transition_state!(truth)
    route = mapping(truth["current_phase_route"], "current_phase_route")
    active = mapping(truth["active_work"], "active_work")
    assert(route["founder_phase_route_decision_required"] != true,
           "ordinary active or ready Route cannot self-authorize a Founder interruption")
    assert(active["founder_decision_required"] != true &&
           active["phase_route_decision_required"] != true,
           "ordinary active or ready Task cannot self-authorize a Founder interruption")
    assert(active["next_eligible_action"].to_s !~ /FOUNDER/ &&
           active["user_action_required"].to_s !~ /FOUNDER/,
           "ordinary active or ready Task cannot route its next action to Founder")
    if truth["founder_escalation_control"].is_a?(Hash)
      control = truth["founder_escalation_control"]
      assert(control["founder_decision_required"] != true &&
             control["disposition"] != FOUNDER_DISPOSITION,
             "Founder escalation control cannot interrupt a non-reserved Route")
    end
    "ACTIVE_OR_READY_PHASE_TASK_NO_FOUNDER_INTERRUPT"
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    assert(truth["record_type"] == "sourcelens_aios_current_truth", "unexpected Truth record type")
    policy = validate_policy!(root, truth)
    project = mapping(truth["project"], "project")
    phase = project["current_phase"]
    assert(phase.is_a?(String) && phase.match?(/\AP(?:0|[1-9]|1[0-2])\z/), "current Phase is invalid")
    validate_phase_delegation!(truth, phase)
    assert(truth["phase_execution_envelope"].is_a?(Hash),
           "active Phase delegation requires a phase execution envelope")
    phase_record, phase_complete, phase_gate_status = phase_gate_state(truth, phase)
    if phase_complete
      assert(%w[EXIT_GATE_READY COMPLETE].include?(phase_record["status"]),
             "strict Phase complete items require Exit Gate ready or complete status")
    else
      assert(phase_record["status"] == "INCOMPLETE",
             "strict Phase incomplete items require INCOMPLETE status")
    end

    route = mapping(truth["current_phase_route"], "current_phase_route")
    unless [CONTINUATION_ROUTE_SCHEMA, RESERVED_ROUTE_SCHEMA, STRATEGIC_HOLD_ROUTE_SCHEMA,
            DELEGATED_TASK_ROUTE_SCHEMA].include?(route["schema_version"])
      assert(!truth["phase_execution_envelope"].is_a?(Hash),
             "active Phase delegation envelope requires a closed delegated Route schema")
      return validate_non_transition_state!(truth)
    end
    historical_route_ref = if route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA
                             route["preceding_terminal_route_ref"]
                           else
                             historical_route_ref!(truth, route)
                           end
    historical_route = mapping(truth[historical_route_ref], historical_route_ref)
    assert(historical_route["phase"] == phase && historical_route["phase_entry_status"] == "AUTHORIZED",
           "historical terminal route Phase drift")
    assert(historical_route["status"].to_s.start_with?("TERMINAL_") &&
           historical_route["execution_status"] == historical_route["status"],
           "historical route is not an exact terminal lifecycle")
    source_route_ref = truth.dig("phase_execution_envelope", "authority_basis", "source_route_ref")
    assert(source_route_ref.is_a?(String), "phase execution envelope source Route reference missing")
    source_route = mapping(truth[source_route_ref], source_route_ref)
    source_decision = validate_source_route_authority!(root, source_route)
    phase_envelope = validate_phase_envelope!(
      root, truth, source_route, phase, policy, source_decision
    )
    control = validate_control!(
      truth,
      phase,
      phase_gate_status,
      phase_complete,
      historical_route,
      phase_envelope,
      root: root
    )
    if route["schema_version"] == DELEGATED_TASK_ROUTE_SCHEMA
      validate_delegated_task_state!(
        truth,
        policy,
        historical_route,
        historical_route_ref,
        phase_envelope,
        control
      )
    elsif control["disposition"] == CONTINUE_DISPOSITION
      validate_continue_state!(
        truth,
        policy,
        historical_route,
        historical_route_ref,
        phase_envelope,
        control
      )
    elsif control["disposition"] == STRATEGIC_HOLD_DISPOSITION
      validate_strategic_hold_state!(
        truth,
        policy,
        historical_route_ref,
        phase_envelope,
        control
      )
    else
      validate_reserved_state!(truth, policy, historical_route_ref, phase_envelope, control)
    end
    control["disposition"]
  end

  def validate!(truth_path: nil, root: nil)
    root ||= `git rev-parse --show-toplevel`.strip
    fail!("cannot resolve repository root") if root.empty?
    truth_path ||= File.join(root, "docs/aios/truth/project_state.yaml")
    validate_truth!(root: root, truth: parse_truth(truth_path))
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    truth_path = if ARGV.empty?
                   nil
                 elsif ARGV.length == 2 && ARGV.first == "--fixture"
                   ARGV.last
                 else
                   raise FounderDelegationContinuityError, "usage: validate-founder-delegation-continuity.rb [--fixture TRUTH]"
                 end
    disposition = FounderDelegationContinuity.validate!(truth_path: truth_path)
    puts "FOUNDER_DELEGATION_CONTINUITY: PASS disposition=#{disposition}"
  rescue FounderDelegationContinuityError => e
    warn "FOUNDER_DELEGATION_CONTINUITY: NON_PASS #{e.message}"
    exit 1
  rescue StandardError => e
    warn "FOUNDER_DELEGATION_CONTINUITY: NON_PASS unexpected #{e.class}: #{e.message}"
    exit 1
  end
end

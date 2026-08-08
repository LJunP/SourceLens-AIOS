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
  DELEGATED_TASK_ROUTE_SCHEMA = "phase-delegated-independent-task/v1"
  DELEGATION_AMENDMENT_SCHEMA = "founder-phase-delegation-amendment/v1"
  DELEGATION_AMENDMENT_ID = "FOUNDER_PHASE_DELEGATION_CONTINUITY_AMENDMENT_2026_08_08"
  CONTINUE_ACTION = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
  CONTINUE_DISPOSITION = "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
  FOUNDER_DISPOSITION = "FOUNDER_DECISION_REQUIRED"
  FALSE_EXTERNAL_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
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

  def parse_yaml_bytes(bytes, label)
    text = bytes.dup.force_encoding("UTF-8")
    assert(text.valid_encoding?, "#{label} encoding is invalid")
    reject_duplicate_keys!(text)
    value = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
    mapping(value, label)
  rescue Psych::SyntaxError => e
    fail!("#{label} YAML is invalid: #{e.message}")
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
      "envelope" => route["envelope"],
      "founder_reserved_profile" => route["founder_reserved_profile"],
      "founder_reserved_profiles" => route["founder_reserved_profiles"],
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
    exact_keys(
      decision,
      %w[
        activation_parent authorization_token automatic_entries automatic_entry claim_boundary
        envelope external_effects goal_identity ordered_tasks phase record_type route_id
        schema_version source_founder_packet_identity
      ],
      "phase execution envelope source decision"
    )
    assert(decision["record_type"] == "founder_phase_route_decision" &&
           decision["schema_version"] == "1.1",
           "phase execution envelope requires a structured Founder route decision v1.1")
    assert(decision["phase"] == historical_route["phase"] &&
           decision["route_id"] == historical_route["route_id"] &&
           decision["authorization_token"] == historical_route["authorization_token"],
           "phase execution envelope source decision identity drift")
    assert(decision["activation_parent"] == historical_route["activation_parent"],
           "source Route activation parent drifts from structured Founder decision")
    assert(decision["automatic_entry"] == historical_route["automatic_entry"] &&
           decision["automatic_entries"] == historical_route["automatic_entries"],
           "source Route automatic-entry semantics drift from structured Founder decision")
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

  def validate_predeclared_task_terminal_outcome!(entry, contract, receipt)
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

  def validate_consumed_task_ledger!(root, ledger, source_route, phase, anchored_source_entries)
    entries = array(ledger, "phase execution task ledger")
    ids = entries.map { |entry| mapping(entry, "phase execution task ledger entry")["task_id"] }
    assert(ids.uniq.length == ids.length, "phase execution task ledger contains duplicate Task ids")
    source_tasks = array(source_route["task_plan"], "source Route task plan")
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
      assert(source_task,
             "phase execution ledger only accepts anchored source Route consumed Tasks")
      anchored = array(anchored_source_entries, "anchored source task ledger").find do |item|
        item.is_a?(Hash) && item["task_id"] == entry["task_id"]
      end
      unless anchored
        anchor_literal = if entry.key?("founder_residual_acceptance")
                           entry.dig("founder_residual_acceptance", "source_founder_packet", "sha256")
                         else
                           entry.dig("outcome_receipt", "sha256")
                         end
        _ledger_anchor_commit, anchored = first_task_ledger_anchor!(
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
        validate_predeclared_task_terminal_outcome!(entry, contract, receipt)
      end
      assert(source_task["status"] == entry["status"] &&
             source_task["engineering_hours"] == budget["engineering_hours"] &&
             source_task["calendar_days"] == budget["calendar_days"],
             "phase execution source Task ledger binding drift")
    end
    entries
  end

  def validate_phase_envelope!(root, truth, source_route, phase, policy)
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
      anchored_source_entries
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
    assert(evidence["schema_version"] == "founder-reserved-trigger-evidence/v1",
           "Founder reserved trigger evidence schema drift")
    assert(evidence["category"] == trigger["category"] && evidence["phase"] == phase,
           "Founder reserved trigger Evidence category or Phase drift")
    assert(evidence["source_event"] == event,
           "Founder reserved trigger Evidence source event drift")
    assert(evidence["source_route_id"] == historical_route["route_id"],
           "Founder reserved trigger Evidence source Route drift")

    condition = exact_keys(
      evidence["condition"],
      %w[
        phase_route_change material_scope_or_permission_expansion requested_budget
        requested_external_effects irreversible_asset_action
        material_legal_privacy_commercial_commitment critical_residual_risk_acceptance
      ],
      "Founder reserved trigger condition"
    )
    requested_budget = exact_keys(
      condition["requested_budget"],
      %w[engineering_tasks engineering_hours calendar_days],
      "Founder reserved trigger requested budget"
    )
    requested_budget.each do |key, value|
      assert(value.is_a?(Integer) && value >= 0,
             "Founder reserved trigger requested budget #{key} is invalid")
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
    budget_expands = requested_budget.any? do |key, value|
      value > limits.fetch(key)
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

  def validate_control!(truth, phase, phase_gate_status, phase_complete, historical_route, phase_envelope)
    control = exact_keys(
      truth["founder_escalation_control"],
      %w[schema_version disposition source_event reserved_trigger phase_gate_status founder_decision_required next_action_owner next_eligible_action],
      "founder_escalation_control"
    )
    assert(control["schema_version"] == "founder-escalation-control/v1",
           "Founder escalation control schema drift")
    assert(control["phase_gate_status"] == phase_gate_status,
           "Founder escalation control Phase Gate projection drift")
    event = exact_keys(control["source_event"], %w[kind task_id status],
                       "Founder escalation source_event")
    trigger = exact_keys(control["reserved_trigger"], %w[category evidence],
                         "Founder escalation reserved_trigger")
    if ORDINARY_TERMINAL_EVENTS.include?(event["kind"])
      matching_tasks = array(historical_route["task_plan"], "historical route task plan").select do |task|
        task.is_a?(Hash) && task["task_id"] == event["task_id"]
      end
      assert(matching_tasks.length == 1, "ordinary terminal event Task identity drift")
      terminal_task = matching_tasks.first
      assert(event["status"] == terminal_task["status"] && event["status"] == historical_route["status"],
             "ordinary terminal event status drift")
      assert(event["status"].to_s.start_with?("TERMINAL_") && event["status"].to_s.include?("NON_PASS"),
             "ordinary terminal event is not a terminal NON_PASS")
    end

    if trigger["category"] == "NONE"
      assert(trigger["evidence"].nil?, "no reserved trigger may not carry evidence")
      assert(ORDINARY_TERMINAL_EVENTS.include?(event["kind"]),
             "no-trigger continuation requires an ordinary terminal lifecycle event")
      assert(!phase_complete, "completed Phase cannot use ordinary continuation disposition")
      assert(control["disposition"] == CONTINUE_DISPOSITION,
             "ordinary terminal lifecycle must continue inside the Phase")
      assert(control["founder_decision_required"] == false,
             "ordinary terminal lifecycle cannot require Founder decision")
      assert(control["next_action_owner"] == "MASTER_CEO_AGENT",
             "ordinary terminal lifecycle next action owner must be Master")
      assert(control["next_eligible_action"] == CONTINUE_ACTION,
             "ordinary terminal lifecycle next action drift")
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

    task = exact_keys(
      route["selected_task"],
      %w[
        task_id status task_kind capability objective capacity_source_task_id budget max_same_task_repairs
        contract independence
      ],
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
    source_route = mapping(
      truth[phase_envelope.dig("authority_basis", "source_route_ref")],
      "delegated independent Task source Route"
    )
    capacity_source = source_capacity_task!(source_route, task["capacity_source_task_id"])
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
        next if historical_key == route["source_authority_route_ref"] &&
                item["task_id"] == task_id && item["status"] == "ACTIVE"
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
    unless [CONTINUATION_ROUTE_SCHEMA, RESERVED_ROUTE_SCHEMA, DELEGATED_TASK_ROUTE_SCHEMA].include?(route["schema_version"])
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
    validate_source_route_authority!(root, source_route)
    phase_envelope = validate_phase_envelope!(root, truth, source_route, phase, policy)
    control = validate_control!(
      truth,
      phase,
      phase_gate_status,
      phase_complete,
      historical_route,
      phase_envelope
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

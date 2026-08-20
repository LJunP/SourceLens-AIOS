#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "validate-p3-004-task-authority"
require_relative "validate-p3-final-transactional-route"

class P3PhaseEntryValidationError < StandardError; end

module P3PhaseEntryValidation
  module_function

  ROUTE_SCHEMA = "p3-phase-entry-active/v1"
  DECISION_SCHEMA = "founder-p3-single-agent-runtime-minimum-trust-phase-entry-decision/v1"
  DECISION_ID = "AUTHORIZE_P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY_V1"
  DECISION_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-phase-entry-20260819/decision/FOUNDER_P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY_V1.json"
  DECISION_BYTES = 4105
  DECISION_SHA256 = "23a50848a182fa7865f8e96c78bd9001ff2db6682d8d19dc49a0d4768994d6eb"
  CONSTITUTION_PATH = "docs/aios/STRATEGIC_CONSTITUTION.md"
  CONSTITUTION_BYTES = 9397
  CONSTITUTION_SHA256 = "7835ff584ad535b27c31bba174681abb625102a04b136ea6ee7535d57e18aaba"
  ENTRY_COMMIT = "bb257afad03b1dc512de68b27a2d64bc7bfb68d2"
  ENTRY_TREE = "f1bd3b594969ec37348b127f57c85e6fafd47702"
  FALSE_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze
  LIMITS = {
    "engineering_tasks" => 8,
    "engineering_hours" => 256,
    "calendar_days" => 64,
    "active_tasks" => 1,
    "task_branches" => 1,
    "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  ZERO_CAPACITY = {
    "engineering_tasks" => 0,
    "engineering_hours" => 0,
    "calendar_days" => 0
  }.freeze
  FULL_CAPACITY = {
    "engineering_tasks" => 8,
    "engineering_hours" => 256,
    "calendar_days" => 64
  }.freeze
  MILESTONES = %w[
    DURABLE_STATE_AND_CHECKPOINT_RESUME
    CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT
    BOUNDED_ISOLATED_EXECUTION_WITH_COMPLETE_OBSERVABLE_TRACES
    INDEPENDENT_P3_EXIT_GATE_AUDIT
  ].freeze
  HOST_OWNED_ROUTE_SCHEMA = "p3-host-owned-fixed-state-workflow-route/v1"
  HOST_OWNED_DECISION_SCHEMA =
    "founder-p3-host-owned-fixed-state-workflow-minimal-atomic-strategy-installation/v1"
  HOST_OWNED_DECISION_ID =
    "AUTHORIZE_P3_HOST_OWNED_FIXED_STATE_WORKFLOW_MINIMAL_ATOMIC_STRATEGY_INSTALLATION_AFTER_EVIDENCE_ONLY_NON_PASS_V1"
  HOST_OWNED_OPERATION_TYPE =
    "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_MINIMAL_ATOMIC_STRATEGY_INSTALLATION_AFTER_EVIDENCE_ONLY_NON_PASS"
  HOST_OWNED_ROUTE_ID = "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_MINIMAL_ATOMIC_ROUTE"
  HOST_OWNED_NEXT_ACTION =
    "MASTER_ACTIVATE_HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION_VERTICAL_SLICE"
  HOST_OWNED_TERMINAL_ACTION =
    "FOUNDER_DECIDE_P3_ROUTE_AFTER_SLOT_1_NON_PASS_OR_HOLD"
  HOST_OWNED_TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-owned-fixed-workflow-structural-permission-20260820/task-p3-006/terminal/P3_006_TERMINAL_SLOT_1_TASK_GATE_NON_PASS_RECEIPT_V1C.json",
    "byte_length" => 8302,
    "sha256" => "30be3b0fd7757bc218d8c0f72354ed049135a83316a582c31bada8bc3d2b082a"
  }.freeze
  HOST_OWNED_INSTALLATION_PATHS = %w[
    docs/aios/STRATEGIC_CONSTITUTION.md
    docs/aios/truth/project_state.yaml
    scripts/validate-p3-phase-entry.rb
    scripts/validate-founder-delegation-continuity.rb
    scripts/validate-current-task-authority.rb
    scripts/test-p3-phase-entry.rb
    scripts/validate-aios-governance.sh
  ].freeze
  HOST_OWNED_TASK_ACTIVATION_CONTROL_PATHS = %w[
    docs/aios/truth/project_state.yaml
    scripts/validate-p3-phase-entry.rb
    scripts/validate-founder-delegation-continuity.rb
    scripts/test-p3-phase-entry.rb
  ].freeze
  HOST_OWNED_TASK_TERMINAL_CONTROL_PATHS = %w[
    docs/aios/truth/project_state.yaml
    scripts/validate-p3-phase-entry.rb
    scripts/validate-founder-delegation-continuity.rb
    scripts/test-p3-phase-entry.rb
  ].freeze
  HOST_OWNED_MILESTONES = %w[
    DURABLE_STATE_AND_CHECKPOINT_RESUME
    HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION
    FIXED_HANDLER_RESUME_ISOLATION_AND_COMPLETE_TRACE
    INDEPENDENT_P3_EXIT_GATE_AUDIT
  ].freeze
  HOST_OWNED_STRICT_ITEMS = %w[
    RESUME
    ISOLATION
    PERMISSION
    COMPLETE_OBSERVABLE_TRACE
  ].freeze

  def assert(condition, message)
    raise P3PhaseEntryValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} must be an array")
    value
  end

  def exact_keys(value, expected, label)
    mapping(value, label)
    assert(value.keys.sort == expected.sort, "#{label} keys drift")
    value
  end

  def exact_identity(path, bytes, sha256, label)
    pathname = Pathname.new(path)
    assert(pathname.file? && !pathname.symlink?, "#{label} must be a regular non-symlink file")
    content = pathname.binread
    assert(content.bytesize == bytes, "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(content) == sha256, "#{label} SHA-256 mismatch")
    content
  end

  def git(root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    raise P3PhaseEntryValidationError, "git #{args.join(' ')} failed: #{stderr}" unless status.success?
    stdout.strip
  end

  def git_blob(root, commit, path, label)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, "show", "#{commit}:#{path}")
    raise P3PhaseEntryValidationError, "#{label} unavailable: #{stderr}" unless status.success?
    stdout
  end

  def exact_git_blob(root, commit, path, bytes, sha256, label)
    content = git_blob(root, commit, path, label)
    assert(content.bytesize == bytes, "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(content) == sha256, "#{label} SHA-256 mismatch")
    content
  end

  def deep_sort(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
    when Array
      value.map { |item| deep_sort(item) }
    else
      value
    end
  end

  def canonical_json(value)
    JSON.generate(deep_sort(value))
  end

  def closed_file_identity(identity, label, create_once: false)
    exact_keys(identity, %w[path byte_length sha256], label)
    path = Pathname.new(identity.fetch("path"))
    assert(path.absolute?, "#{label} path must be absolute")
    stat = path.lstat rescue nil
    assert(stat&.file? && !path.symlink?, "#{label} must be a regular non-symlink file")
    assert((stat.mode & 0o777) == 0o444 && stat.nlink == 1,
           "#{label} create-once mode/link drift") if create_once
    bytes = path.binread
    assert(bytes.bytesize == identity.fetch("byte_length"), "#{label} byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"),
           "#{label} SHA-256 mismatch")
    bytes
  end

  def decision_identity
    {"path" => DECISION_PATH, "byte_length" => DECISION_BYTES, "sha256" => DECISION_SHA256}
  end

  def validate_decision!(root)
    bytes = exact_identity(DECISION_PATH, DECISION_BYTES, DECISION_SHA256, "P3 entry decision")
    decision = JSON.parse(bytes)
    assert(decision["schema_version"] == DECISION_SCHEMA &&
           decision["record_type"] == "sourcelens_aios_founder_p3_phase_entry_decision" &&
           decision["decision_id"] == DECISION_ID &&
           decision["authority"] == "HUMAN_FOUNDER" &&
           decision["source_kind"] == "CURRENT_DIRECT_FOUNDER_REPLY_V1" &&
           decision["reserved_trigger"] == "PHASE_ENTRY_OR_EXIT" &&
           decision["operation_type"] == "P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY",
           "P3 entry decision identity drift")
    binding = mapping(decision["canonical_binding"], "P3 entry canonical binding")
    assert(binding["branch"] == "main" && binding["commit"] == ENTRY_COMMIT &&
           binding["tree"] == ENTRY_TREE &&
           git(root, "rev-parse", "#{ENTRY_COMMIT}^{tree}") == ENTRY_TREE,
           "P3 entry canonical commit/tree mismatch")
    constitution = mapping(binding["governing_artifact"], "P3 entry governing artifact")
    assert(constitution == {
      "path" => CONSTITUTION_PATH,
      "byte_length" => CONSTITUTION_BYTES,
      "sha256" => CONSTITUTION_SHA256
    }, "P3 entry Constitution binding drift")
    exact_git_blob(root, ENTRY_COMMIT, CONSTITUTION_PATH, CONSTITUTION_BYTES,
                   CONSTITUTION_SHA256, "P3 entry governing Constitution")
    predecessor = mapping(decision["predecessor_gate"], "P3 predecessor Gate")
    assert(predecessor == {
      "phase" => "P2",
      "status" => "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED",
      "research_exit_percent" => 100,
      "original_capability_gate" => "CONTEXT_BENCHMARK_BEATS_SIMPLE_RETRIEVAL_BASELINES",
      "original_capability_gate_status" => "MISSING_NOT_ACCEPTED",
      "original_capability_progress_percent" => 0,
      "candidate_integrated" => false,
      "held_source_reads" => 0
    }, "P3 entry predecessor truth boundary drift")
    assert(decision.dig("phase_envelope", "limits") == LIMITS &&
           decision.dig("phase_envelope", "initial_consumed") == ZERO_CAPACITY &&
           decision.dig("phase_envelope", "initial_remaining") == FULL_CAPACITY &&
           decision.dig("phase_envelope", "external_capabilities") == 0,
           "P3 entry envelope drift")
    assert(decision["milestone_order"] == MILESTONES,
           "P3 entry milestone order drift")
    effects = mapping(decision["external_effects"], "P3 entry external effects")
    assert(effects.values.all? { |value| value == false },
           "P3 entry grants an external effect")
    decision
  rescue JSON::ParserError => e
    raise P3PhaseEntryValidationError, "P3 entry decision JSON invalid: #{e.message}"
  end

  def validate_host_owned_decision!(root, route)
    route_identity = exact_keys(
      route["founder_route_decision"],
      %w[decision_id reserved_trigger path byte_length sha256],
      "host-owned Founder decision identity"
    )
    assert(route_identity["decision_id"] == HOST_OWNED_DECISION_ID &&
           route_identity["reserved_trigger"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
           "host-owned Founder decision classification drift")
    bytes = closed_file_identity(
      route_identity.slice("path", "byte_length", "sha256"),
      "host-owned Founder decision",
      create_once: true
    )
    decision = JSON.parse(bytes)
    exact_keys(
      decision,
      %w[
        schema_version record_type decision_id authority source_kind reserved_trigger
        operation_type source_attachment canonical_binding bound_evidence
        formal_p3_objective_amendment_reaffirmed objective unchanged_boundaries
        strict_exit_gate architecture prior_task_ledger phase_envelope ordered_slots
        installation lineage external_effects lifecycle
      ],
      "host-owned Founder decision"
    )
    assert(decision["schema_version"] == HOST_OWNED_DECISION_SCHEMA &&
           decision["record_type"] == "sourcelens_aios_founder_p3_objective_and_phase_route_decision" &&
           decision["decision_id"] == HOST_OWNED_DECISION_ID &&
           decision["authority"] == "HUMAN_FOUNDER" &&
           decision["source_kind"] == "CURRENT_DIRECT_FOUNDER_REPLY_V1" &&
           decision["reserved_trigger"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           decision["operation_type"] == HOST_OWNED_OPERATION_TYPE &&
           decision["formal_p3_objective_amendment_reaffirmed"] == true,
           "host-owned Founder decision content drift")
    closed_file_identity(decision["source_attachment"], "direct Founder source attachment")

    binding = exact_keys(
      decision["canonical_binding"],
      %w[branch commit tree truth governing_artifact founder_delegation_policy repository_execution_rules],
      "host-owned canonical binding"
    )
    assert(binding["branch"] == "main" &&
           binding["commit"] == route.dig("activation_parent", "commit") &&
           binding["tree"] == route.dig("activation_parent", "tree") &&
           git(root, "rev-parse", "#{binding.fetch("commit")}^{tree}") == binding["tree"],
           "host-owned activation parent commit/tree drift")
    git(root, "merge-base", "--is-ancestor", binding.fetch("commit"), "HEAD")

    parent_truth_identity = exact_keys(
      binding["truth"], %w[path byte_length sha256], "activation-parent Truth identity"
    )
    parent_truth_bytes = exact_git_blob(
      root, binding.fetch("commit"), parent_truth_identity.fetch("path"),
      parent_truth_identity.fetch("byte_length"), parent_truth_identity.fetch("sha256"),
      "activation-parent Truth"
    )
    parent_truth = YAML.safe_load(
      parent_truth_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(parent_truth.is_a?(Hash), "activation-parent Truth must be a mapping")

    parent_constitution = exact_keys(
      binding["governing_artifact"],
      %w[path version byte_length sha256],
      "activation-parent Constitution identity"
    )
    assert(parent_constitution["version"] == "2.4", "activation-parent Constitution version drift")
    exact_git_blob(
      root, binding.fetch("commit"), parent_constitution.fetch("path"),
      parent_constitution.fetch("byte_length"), parent_constitution.fetch("sha256"),
      "activation-parent Constitution"
    )
    policy = exact_keys(
      binding["founder_delegation_policy"],
      %w[path version byte_length sha256],
      "Founder Delegation Policy identity"
    )
    assert(policy["version"] == "1.8", "Founder Delegation Policy version drift")
    exact_identity(root.join(policy.fetch("path")), policy.fetch("byte_length"),
                   policy.fetch("sha256"), "Founder Delegation Policy")
    rules = exact_keys(
      binding["repository_execution_rules"],
      %w[path byte_length sha256],
      "repository execution rules identity"
    )
    exact_identity(root.join(rules.fetch("path")), rules.fetch("byte_length"),
                   rules.fetch("sha256"), "repository execution rules")

    evidence = exact_keys(
      decision["bound_evidence"],
      %w[p3_phase_entry_decision accepted_p3_001_receipt prior_strategic_decision_identity_only prior_installation_terminal_receipt],
      "host-owned bound Evidence"
    )
    evidence.each do |name, identity|
      closed_file_identity(identity, "host-owned bound Evidence #{name}")
    end

    strict = exact_keys(
      decision["strict_exit_gate"],
      %w[changed required_items independent_exit_gate_audit_required partial_or_governance_substitute_allowed],
      "host-owned strict Exit decision"
    )
    assert(strict["changed"] == false && strict["required_items"] == HOST_OWNED_STRICT_ITEMS &&
           strict["independent_exit_gate_audit_required"] == true &&
           strict["partial_or_governance_substitute_allowed"] == false,
           "host-owned strict Exit decision drift")
    architecture = mapping(decision["architecture"], "host-owned architecture")
    assert(architecture["id"] == "HOST_OWNED_FIXED_STATE_WORKFLOW_WITH_EFFECT_FREE_AGENT_PAYLOADS" &&
           architecture["state_graph"] == %w[INSPECT AGENT_EFFECT_FREE_PAYLOAD APPLY_IN_DISPOSABLE_WORKSPACE DECLARED_TEST RECORD_RESULT] &&
           architecture["agent_runtime_may_emit"] == "CURRENT_STATE_TYPED_EFFECT_FREE_DTO_ONLY" &&
           architecture["one_fixed_product_handler_per_state"] == true &&
           architecture["dispatch_intent_create_once_before_spawn"] == true &&
           architecture["persistence_failure_prevents_execution"] == true &&
           architecture["ambiguous_inflight_recovery"] == "FAIL_CLOSED_NO_EFFECT_REPLAY",
           "host-owned architecture decision drift")
    assert(array(architecture["agent_runtime_forbidden_fields"], "Agent forbidden fields").include?("argv") &&
           array(architecture["forbidden_architectures"], "forbidden architectures").include?("GENERIC_INTERPRETER"),
           "host-owned architecture did not close Agent action selection")

    installation = mapping(decision["installation"], "host-owned installation envelope")
    assert(installation["candidate_generations"] == 1 && installation["same_install_repairs"] == 0 &&
           installation["fresh_independent_read_only_governance_reviewers"] == 1 &&
           installation["max_governance_hours"] == 2 && installation["max_calendar_days"] == 1 &&
           installation["repository_mutation_allowlist"] == HOST_OWNED_INSTALLATION_PATHS &&
           installation["auxiliary_pre_review_truth_snapshot_allowed"] == false &&
           installation["chronology_marker_allowed"] == false &&
           installation["historical_suffix_copy_allowed"] == false &&
           installation["blocker_detail_copy_allowed"] == false &&
           installation["full_history_handoff_allowed"] == false,
           "host-owned installation envelope drift")
    effects = mapping(decision["external_effects"], "host-owned external effects")
    assert(effects.values.all? { |value| value == false },
           "host-owned decision grants an external effect")
    [decision, parent_truth]
  rescue JSON::ParserError => e
    raise P3PhaseEntryValidationError, "host-owned Founder decision JSON invalid: #{e.message}"
  rescue Psych::SyntaxError => e
    raise P3PhaseEntryValidationError, "activation-parent Truth YAML invalid: #{e.message}"
  end

  def validate_host_owned_repository_scope!(root, truth = nil)
    root = Pathname.new(root).realpath
    stdout, stderr, status = Open3.capture3(
      "git", "-C", root.to_s, "status", "--porcelain=v1", "--untracked-files=all"
    )
    raise P3PhaseEntryValidationError, "host-owned repository status failed: #{stderr}" unless status.success?
    lines = stdout.lines.map(&:chomp)
    paths = lines.map do |line|
      assert(line.bytesize >= 4 && !line.include?(" -> "),
             "host-owned installation status entry is not a single path")
      line[3..]
    end
    return if paths.empty?

    installation = paths.sort == HOST_OWNED_INSTALLATION_PATHS.sort &&
      lines.none? { |line| line.start_with?("??") }
    unless truth
      truth = YAML.safe_load(
        root.join("docs/aios/truth/project_state.yaml").binread,
        permitted_classes: [], permitted_symbols: [], aliases: false
      )
    end
    contract_path = truth.dig("active_work", "current_task_contract", "path")
    activation_paths = HOST_OWNED_TASK_ACTIVATION_CONTROL_PATHS + [contract_path]
    activation = contract_path.is_a?(String) && !contract_path.empty? &&
      paths.sort == activation_paths.sort &&
      lines.select { |line| line.start_with?("??") }.map { |line| line[3..] } == [contract_path]
    terminalization = paths.sort == HOST_OWNED_TASK_TERMINAL_CONTROL_PATHS.sort &&
      lines.none? { |line| line.start_with?("??") }
    assert(installation || activation || terminalization,
           "host-owned repository mutation set is neither exact installation, Task activation nor Task terminalization")
  end

  def validate_host_owned_constitution!(root, truth, decision)
    path = root.join(CONSTITUTION_PATH)
    bytes = exact_identity(path, path.size, Digest::SHA256.file(path).hexdigest,
                           "current Strategic Constitution")
    text = bytes.dup.force_encoding("UTF-8")
    assert(text.valid_encoding?, "current Strategic Constitution UTF-8 invalid")
    assert(text.lines.include?("- Version: `2.6`\n") &&
           text.lines.include?("- Effective date: 2026-08-20\n"),
           "Strategic Constitution v2.6 identity markers missing")
    expected_row = "| P3 Single-Agent Runtime + Minimum Trust | #{decision.fetch("objective")} | Resume, isolation, permission and trace tests |\n"
    assert(text.lines.grep(/^\| P3 Single-Agent Runtime \+ Minimum Trust \|/) == [expected_row],
           "Strategic Constitution P3 objective or strict Exit drift")
    assert(text.include?(HOST_OWNED_DECISION_ID) &&
           text.include?("Constitution v2.5 was never installed and has no authority."),
           "Strategic Constitution append-only P3 ADR drift")
    strategy = exact_keys(
      truth.dig("authority", "strategy"),
      %w[path version sha256 status],
      "current strategy authority"
    )
    assert(strategy == {
      "path" => CONSTITUTION_PATH,
      "version" => "2.6",
      "sha256" => Digest::SHA256.hexdigest(bytes),
      "status" => "FROZEN"
    }, "current strategy authority identity drift")

    section_header = "## 9. Phase route\n"
    start = text.index(section_header)
    assert(start, "Strategic Constitution Phase route section missing")
    finish = text.index(/^## /, start + section_header.bytesize)
    section = text[start...(finish || text.length)].gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    authority = exact_keys(
      truth.dig("strict_phase_gate_ledger", "phase_route_authority"),
      %w[path version section section_byte_length section_sha256],
      "strict Phase route authority"
    )
    assert(authority == {
      "path" => CONSTITUTION_PATH,
      "version" => "2.6",
      "section" => "## 9. Phase route",
      "section_byte_length" => section.bytesize,
      "section_sha256" => Digest::SHA256.hexdigest(section)
    }, "strict Phase route authority identity drift")
  end

  def decision_slot_projection(decision)
    array(decision["ordered_slots"], "host-owned ordered slots").map do |slot|
      mapping(slot, "host-owned ordered slot").merge("status" => slot.fetch("initial_status"))
    end
  end

  def envelope_slot_projection(decision)
    decision_slot_projection(decision).map do |slot|
      slot.slice(
        "ordinal", "slot_id", "kind", "milestone", "status", "predecessor",
        "predecessor_status_required", "budget"
      )
    end
  end

  def validate_host_owned_active_task!(root, truth, decision, current_envelope)
    active = mapping(truth["active_work"], "host-owned active work")
    task_id = active["current_task"]
    assert(task_id.is_a?(String) && task_id.match?(/\AAIOS-P3-[0-9]{3}_[A-Z0-9_]+\z/),
           "host-owned active Task id is invalid")

    contract_identity = exact_keys(
      active["current_task_contract"], %w[path sha256 byte_length],
      "host-owned active Task Contract identity"
    )
    contract_path = Pathname.new(contract_identity.fetch("path"))
    assert(!contract_path.absolute? && contract_path.each_filename.first(3).to_a == %w[docs aios tasks],
           "host-owned active Task Contract path is outside docs/aios/tasks")
    contract_bytes = exact_identity(
      root.join(contract_path), contract_identity.fetch("byte_length"),
      contract_identity.fetch("sha256"), "host-owned active Task Contract"
    )
    contract = YAML.safe_load(
      contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
    )
    mapping(contract, "host-owned active Task Contract")
    first_slot = array(decision["ordered_slots"], "host-owned ordered slots").first
    assert(contract["schema_version"] == "p3-host-owned-fixed-workflow-task-contract/v1" &&
           contract["record_type"] == "sourcelens_aios_p3_host_owned_fixed_workflow_task_contract" &&
           contract["task_id"] == task_id && contract["route_id"] == HOST_OWNED_ROUTE_ID &&
           contract["phase"] == "P3" && contract["slot_id"] == first_slot["slot_id"] &&
           contract["task_kind"] == first_slot["kind"] && contract["status"] == "ACTIVE" &&
           contract["milestone"] == first_slot["milestone"],
           "host-owned active Task Contract lifecycle drift")
    assert(contract["state_graph"] == decision.dig("architecture", "state_graph") &&
           contract.dig("structural_permission_invariants", "agent_forbidden_fields") ==
             decision.dig("architecture", "agent_runtime_forbidden_fields") &&
           contract.dig("structural_permission_invariants", "fail_before_handler_invocation") ==
             decision.dig("architecture", "fail_before_effect_on") &&
           contract.dig("structural_permission_invariants", "legacy_agent_runtime_effect_path") ==
             "UNREACHABLE",
           "host-owned active Task structural permission contract drift")
    expected_budget = first_slot.fetch("budget").merge(
      "candidate_generations" => first_slot.fetch("max_candidate_generations"),
      "same_task_repairs" => first_slot.fetch("max_same_task_repairs"),
      "review_cycles" => first_slot.fetch("max_review_cycles"),
      "active_candidates" => 1
    )
    assert(contract["budget"] == expected_budget &&
           contract.dig("authority", "activation_parent") == {
             "branch" => "main",
             "commit" => active["activation_parent_commit"],
             "tree" => active["activation_parent_tree"]
           } && contract.dig("authority", "accepted_predecessor", "milestone") ==
             first_slot["predecessor"] &&
           contract.dig("authority", "task_gate_owner") == "MASTER_CEO_AGENT" &&
           contract["external_effects"] == FALSE_EFFECTS,
           "host-owned active Task Contract authority or budget drift")

    authority_identity = exact_keys(
      active["authority_record"], %w[path sha256 byte_length],
      "host-owned active Task authority identity"
    )
    assert(active["current_execution_authorization"] == authority_identity["path"] &&
           active["current_execution_authorization_sha256"] == authority_identity["sha256"],
           "host-owned active Task authority aliases drift")
    authority_bytes = closed_file_identity(
      authority_identity.slice("path", "byte_length", "sha256"),
      "host-owned active Task authority", create_once: true
    )
    authority = JSON.parse(authority_bytes)
    assert(authority["schema_version"] ==
             "p3-host-owned-fixed-workflow-phase-delegated-task-authority/v1" &&
           authority["record_type"] ==
             "sourcelens_aios_p3_host_owned_fixed_workflow_phase_delegated_task_authority" &&
           authority["task_id"] == task_id && authority["route_id"] == HOST_OWNED_ROUTE_ID &&
           authority["slot_id"] == first_slot["slot_id"] &&
           authority["milestone"] == first_slot["milestone"] &&
           authority["authorization_id"] == active["authorization_id"] &&
           authority["execution_nonce"] == active["execution_nonce"] &&
           authority["contract"] == contract_identity &&
           authority["branch"] == active["task_branch"] &&
           authority["worktree"] == active["task_worktree"] &&
           authority["evidence_root"] == active["execution_evidence_root"] &&
           authority["allowlisted_paths"] == active["allowlisted_paths"] &&
           authority["budget"].slice(*expected_budget.keys) == expected_budget &&
           authority["external_effects"] == FALSE_EFFECTS &&
           authority["founder_decision_required"] == false && authority["create_once"] == true,
           "host-owned active Task authority drift")
    assert(active["budget"] == expected_budget.reject { |key, _| key == "active_candidates" } &&
           active["roles"] == authority["roles"],
           "host-owned active Task active-work budget or roles drift")
    expected_route_decision = truth.dig("current_phase_route", "founder_route_decision")
      .slice("decision_id", "path", "byte_length", "sha256")
    assert(authority.dig("authority_basis", "phase_route_decision") == expected_route_decision,
           "host-owned active Task Founder authority binding drift")
    assert(authority.dig("authority_basis", "activation_parent") == {
      "branch" => "main",
      "commit" => active["activation_parent_commit"],
      "tree" => active["activation_parent_tree"]
    }, "host-owned active Task activation parent drift")
    assert(git(root, "rev-parse", "#{active.fetch('activation_parent_commit')}^{tree}") ==
             active["activation_parent_tree"],
           "host-owned active Task activation parent commit/tree mismatch")
    assert(Pathname.new(active["task_worktree"]).cleanpath.to_s.start_with?(
             "/Users/lijunpeng/Developer/.sourcelens-worktrees/"),
           "host-owned active Task worktree is outside the configured root")
    assert(Pathname.new(active["execution_evidence_root"]).cleanpath.to_s.start_with?(
             "/Users/lijunpeng/Developer/.sourcelens-audit/"),
           "host-owned active Task Evidence root is outside the configured root")

    current_task_entry = array(current_envelope["task_ledger"], "current P3 Task ledger").last
    assert(current_task_entry == {
      "task_id" => task_id,
      "route_id" => HOST_OWNED_ROUTE_ID,
      "status" => "ACTIVE",
      "milestone" => first_slot["milestone"],
      "slot_id" => first_slot["slot_id"],
      "budget" => first_slot["budget"],
      "contract" => contract_identity.slice("path", "byte_length", "sha256"),
      "authority" => authority_identity.slice("path", "byte_length", "sha256"),
      "activation_parent" => {
        "commit" => active["activation_parent_commit"],
        "tree" => active["activation_parent_tree"]
      }
    }, "host-owned active Task ledger entry drift")
    [contract, authority]
  rescue JSON::ParserError => e
    raise P3PhaseEntryValidationError, "host-owned active Task authority JSON invalid: #{e.message}"
  rescue Psych::SyntaxError => e
    raise P3PhaseEntryValidationError, "host-owned active Task Contract YAML invalid: #{e.message}"
  end

  def validate_host_owned_terminal_task!(root, truth, decision, current_envelope)
    route = mapping(truth["current_phase_route"], "host-owned terminal Route")
    terminal = exact_keys(
      route["terminal_task"],
      %w[
        task_id status slot_id milestone candidate manifest
        independent_review_verdicts terminal_receipt accepted
        delivery_credit strict_exit_credit
      ],
      "host-owned terminal Task"
    )
    first_slot = array(decision["ordered_slots"], "host-owned ordered slots").first
    assert(terminal["task_id"] ==
             "AIOS-P3-006_HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION_VERTICAL_SLICE" &&
           terminal["status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           terminal["slot_id"] == first_slot["slot_id"] &&
           terminal["milestone"] == first_slot["milestone"] &&
           terminal["candidate"] == {
             "commit" => "3025a9bfe634bbe58776ed13942a15dc3afd9dc8",
             "tree" => "5cfa4fe182b880b2dbeaa02e747537e5401fccb2",
             "integrated" => false
           } && terminal["independent_review_verdicts"] == {
             "cto" => "NON_PASS",
             "security" => "NON_PASS",
             "quality_evaluation" => "NON_PASS"
           } && terminal["accepted"] == false && terminal["delivery_credit"] == 0 &&
           terminal["strict_exit_credit"] == 0,
           "host-owned terminal Task outcome drift")
    manifest_identity = exact_keys(
      terminal["manifest"], %w[path byte_length sha256], "host-owned terminal manifest"
    )
    closed_file_identity(manifest_identity, "host-owned terminal manifest", create_once: true)
    receipt_identity = exact_keys(
      terminal["terminal_receipt"], %w[path byte_length sha256],
      "host-owned terminal receipt identity"
    )
    assert(receipt_identity == HOST_OWNED_TERMINAL_RECEIPT,
           "host-owned terminal receipt identity drift")
    receipt = JSON.parse(closed_file_identity(
      receipt_identity, "host-owned terminal receipt", create_once: true
    ))
    assert(receipt["schema"] == "p3-task-terminal-receipt/v1" &&
           receipt["receipt_id"] == "P3_006_TERMINAL_SLOT_1_TASK_GATE_NON_PASS_RECEIPT_V1C" &&
           receipt.dig("correction", "prior_receipt_canonicalized") == false &&
           receipt.dig("correction", "prior_receipt_do_not_use") == true &&
           receipt.dig("task", "task_id") == terminal["task_id"] &&
           receipt.dig("task", "slot_id") == terminal["slot_id"] &&
           receipt.dig("candidate", "final_commit") == terminal.dig("candidate", "commit") &&
           receipt.dig("candidate", "final_tree") == terminal.dig("candidate", "tree") &&
           receipt.dig("candidate", "integrated") == false &&
           receipt.dig("terminal_result", "task_lifecycle") == "TERMINAL_TASK_GATE_NON_PASS" &&
           receipt.dig("terminal_result", "route_lifecycle") ==
             "TERMINAL_SLOT_1_NON_PASS_DOWNSTREAM_LOCKED_NO_REPLACEMENT" &&
           receipt.dig("terminal_result", "phase_lifecycle") == "ACTIVE_INCOMPLETE_ROUTE_HOLD" &&
           receipt.dig("terminal_result", "long_term_goal_lifecycle") == "ACTIVE" &&
           receipt.dig("terminal_result", "task_gate_accepted") == false &&
           receipt.dig("terminal_result", "candidate_integration_allowed") == false &&
           receipt.dig("terminal_result", "slot_2_unlocked") == false &&
           receipt.dig("terminal_result", "slot_3_unlocked") == false &&
           receipt.dig("terminal_result", "p3_delivery_progress_percent") == 25 &&
           receipt.dig("terminal_result", "p3_strict_exit_progress_percent") == 0 &&
           receipt.dig("terminal_result", "p4_status") == "HOLD" &&
           receipt.dig("terminal_result", "project_actually_completed") == false &&
           receipt.dig("no_auto_successor", "present") == true,
           "host-owned terminal receipt content drift")

    contract = exact_keys(
      receipt.dig("task", "contract"), %w[path byte_length sha256],
      "host-owned terminal Contract identity"
    )
    exact_identity(root.join(contract.fetch("path")), contract.fetch("byte_length"),
                   contract.fetch("sha256"), "host-owned terminal Contract")
    authority = exact_keys(
      receipt.dig("task", "authority").slice("path", "byte_length", "sha256"),
      %w[path byte_length sha256], "host-owned terminal authority identity"
    )
    closed_file_identity(authority, "host-owned terminal authority", create_once: true)
    task_card = exact_keys(
      receipt.dig("task", "frozen_task_card"), %w[path byte_length sha256],
      "host-owned frozen Task Card identity"
    )
    closed_file_identity(task_card, "host-owned frozen Task Card", create_once: true)
    assert(receipt.dig("candidate", "manifest").slice("path", "byte_length", "sha256") ==
             manifest_identity,
           "host-owned terminal manifest receipt binding drift")
    array(receipt["cycle_2_independent_reviews"], "cycle-2 reviews").each do |review|
      assert(review["verdict"] == "NON_PASS", "host-owned terminal review verdict drift")
      closed_file_identity(
        review.slice("path", "byte_length", "sha256"),
        "host-owned terminal #{review.fetch('role')} review", create_once: true
      )
    end
    bundle = receipt.dig("candidate", "recoverable_terminal_bundle")
    closed_file_identity(
      bundle.slice("path", "byte_length", "sha256"),
      "host-owned rejected candidate terminal bundle", create_once: true
    )

    expected_entry = {
      "task_id" => terminal["task_id"],
      "route_id" => HOST_OWNED_ROUTE_ID,
      "status" => "TERMINAL_TASK_GATE_NON_PASS",
      "milestone" => first_slot["milestone"],
      "slot_id" => first_slot["slot_id"],
      "budget" => first_slot["budget"],
      "contract" => contract,
      "authority" => authority,
      "activation_parent" => {
        "commit" => receipt.dig("candidate", "route_installation_commit"),
        "tree" => receipt.dig("candidate", "route_installation_tree")
      },
      "candidate" => terminal["candidate"],
      "candidate_manifest" => manifest_identity,
      "independent_review_verdicts" => terminal["independent_review_verdicts"],
      "terminal_receipt" => receipt_identity
    }
    assert(array(current_envelope["task_ledger"], "current P3 Task ledger").last == expected_entry,
           "host-owned terminal Task ledger entry drift")
    receipt
  rescue JSON::ParserError => e
    raise P3PhaseEntryValidationError, "host-owned terminal receipt JSON invalid: #{e.message}"
  end

  def validate_host_owned_route!(root, truth, project, route)
    decision, parent_truth = validate_host_owned_decision!(root, route)
    validate_host_owned_repository_scope!(root, truth)
    validate_host_owned_constitution!(root, truth, decision)
    active_task = route["status"] == "ACTIVE_SLOT_1"
    terminal_task = route["status"] == "TERMINAL_SLOT_1_TASK_GATE_NON_PASS"
    ready_route = route["status"] == "AUTHORIZED_READY_SLOT_1"
    assert([active_task, terminal_task, ready_route].count(true) == 1,
           "host-owned current Route lifecycle drift")
    expected_route_status = if terminal_task
                              "TERMINAL_SLOT_1_TASK_GATE_NON_PASS"
                            elsif active_task
                              "ACTIVE_SLOT_1"
                            else
                              "AUTHORIZED_READY_SLOT_1"
                            end
    expected_execution_status = if terminal_task
                                  "ROUTE_TERMINAL_SLOT_1_NON_PASS"
                                elsif active_task
                                  "PHASE_DELEGATED_TASK_ACTIVE"
                                else
                                  "PHASE_DELEGATED_CONTINUATION_READY"
                                end
    expected_scheduling_status = if terminal_task
                                   "DOWNSTREAM_SLOTS_LOCKED_NO_REPLACEMENT"
                                 elsif active_task
                                   "SLOT_1_ACTIVE_DOWNSTREAM_LOCKED"
                                 else
                                   "SLOT_1_ELIGIBLE_NOT_ACTIVATED"
                                 end
    expected_next_action = if terminal_task
                             HOST_OWNED_TERMINAL_ACTION
                           elsif active_task
                             "COMPLETE_CURRENT_TASK_GATE"
                           else
                             HOST_OWNED_NEXT_ACTION
                           end

    exact_keys(
      route,
      %w[
        schema_version route_id status execution_status scheduling_status phase
        phase_entry_status policy founder_phase_route_decision_required
        founder_reserved_trigger_resolved next_eligible_action
        phase_execution_envelope_ref phase_entry_route_ref
        accepted_foundation_route_ref historical_terminal_route_ref terminal_task
        founder_route_decision activation_parent objective_id
        strict_exit_gate_changed strict_exit_gate_required_items prior_task_ledger
        ordered_slots p3_entry_authorized p4_entry_authorized
        long_term_goal_status external_effects additional_write_roots
      ].reject { |key| key == "terminal_task" && !terminal_task },
      "host-owned current Route"
    )
    assert(route["schema_version"] == HOST_OWNED_ROUTE_SCHEMA &&
           route["route_id"] == HOST_OWNED_ROUTE_ID &&
           route["status"] == expected_route_status &&
           route["execution_status"] == expected_execution_status &&
           route["scheduling_status"] == expected_scheduling_status &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == terminal_task &&
           route["founder_reserved_trigger_resolved"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           route["next_eligible_action"] == expected_next_action &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["accepted_foundation_route_ref"] == "historical_p3_001_phase_route" &&
           route["historical_terminal_route_ref"] == "historical_p3_005_phase_route" &&
           route["objective_id"] == "HOST_OWNED_FIXED_STATE_WORKFLOW_WITH_EFFECT_FREE_AGENT_PAYLOADS" &&
           route["strict_exit_gate_changed"] == false &&
           route["strict_exit_gate_required_items"] == HOST_OWNED_STRICT_ITEMS &&
           route["p3_entry_authorized"] == true && route["p4_entry_authorized"] == false &&
           route["long_term_goal_status"] == "ACTIVE" &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "host-owned current Route lifecycle drift")
    assert(route["policy"] == {
      "path" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
      "version" => "1.8",
      "sha256" => "12126e9617011b6395f187939c9a1d7860d84bd3832c1b1b67357fb017e1ee29"
    }, "host-owned Route policy drift")
    assert(route["activation_parent"] == decision["canonical_binding"].slice("branch", "commit", "tree").merge(
      "truth" => decision.dig("canonical_binding", "truth"),
      "constitution" => decision.dig("canonical_binding", "governing_artifact")
    ), "host-owned Route activation parent drift")
    assert(route["prior_task_ledger"] == decision["prior_task_ledger"].slice(
      "entry_count", "canonicalization", "canonical_byte_length", "canonical_sha256"
    ), "host-owned Route prior ledger identity drift")
    expected_route_slots = decision_slot_projection(decision)
    if terminal_task
      expected_route_slots[0]["status"] = "TERMINAL_TASK_GATE_NON_PASS"
      expected_route_slots[1]["status"] = "LOCKED_SLOT_1_NON_PASS_NO_REPLACEMENT"
      expected_route_slots[2]["status"] = "LOCKED_SLOT_1_NON_PASS_NO_REPLACEMENT"
    elsif active_task
      expected_route_slots.first["status"] = "ACTIVE"
    end
    assert(route["ordered_slots"] == expected_route_slots,
           "host-owned Route slot dependency projection drift")
    assert(expected_route_slots.map { |slot| slot["ordinal"] } == [1, 2, 3] &&
           expected_route_slots.map { |slot| slot["status"] } == [
             terminal_task ? "TERMINAL_TASK_GATE_NON_PASS" :
               (active_task ? "ACTIVE" : "ELIGIBLE_NOT_ACTIVATED"),
             terminal_task ? "LOCKED_SLOT_1_NON_PASS_NO_REPLACEMENT" :
               "LOCKED_PREDECESSOR_NOT_ACCEPTED",
             terminal_task ? "LOCKED_SLOT_1_NON_PASS_NO_REPLACEMENT" :
               "LOCKED_PREDECESSOR_NOT_ACCEPTED"
           ] &&
           expected_route_slots.map { |slot| slot["kind"] } == [
             "PRODUCT_IMPLEMENTATION", "PRODUCT_IMPLEMENTATION", "EVALUATION_ONLY"
           ], "host-owned Route slot order/kind drift")

    parent_ledger = array(parent_truth.dig("phase_execution_envelope", "task_ledger"),
                          "activation-parent P3 Task ledger")
    current_envelope = mapping(truth["phase_execution_envelope"], "host-owned P3 Phase envelope")
    current_ledger = array(current_envelope["task_ledger"], "current P3 Task ledger")
    prior_identity = mapping(decision["prior_task_ledger"], "host-owned prior ledger decision")
    serialized = canonical_json(parent_ledger)
    task_consumed = active_task || terminal_task
    expected_current_ledger_length = parent_ledger.length + (task_consumed ? 1 : 0)
    assert(parent_ledger == current_ledger.first(parent_ledger.length) &&
           current_ledger.length == expected_current_ledger_length &&
           parent_ledger.length == prior_identity["entry_count"] &&
           serialized.bytesize == prior_identity["canonical_byte_length"] &&
           Digest::SHA256.hexdigest(serialized) == prior_identity["canonical_sha256"],
           "host-owned P3 Task ledger drift")
    phase_envelope = mapping(decision["phase_envelope"], "host-owned decision Phase envelope")
    slot_budget = decision.dig("ordered_slots", 0, "budget")
    expected_consumed = phase_envelope["consumed"].each_with_object({}) do |(key, value), result|
      result[key] = value + slot_budget.fetch(key)
    end
    expected_remaining = phase_envelope["remaining"].each_with_object({}) do |(key, value), result|
      result[key] = value - slot_budget.fetch(key)
    end
    expected_envelope_slots = envelope_slot_projection(decision)
    if terminal_task
      expected_envelope_slots[0]["status"] = "TERMINAL_TASK_GATE_NON_PASS"
      expected_envelope_slots[1]["status"] = "LOCKED_SLOT_1_NON_PASS_NO_REPLACEMENT"
      expected_envelope_slots[2]["status"] = "LOCKED_SLOT_1_NON_PASS_NO_REPLACEMENT"
    elsif active_task
      expected_envelope_slots.first["status"] = "ACTIVE"
    end
    assert(current_envelope["schema_version"] == "phase-execution-envelope/v1" &&
           current_envelope["phase"] == "P3" &&
           current_envelope["status"] == (terminal_task ?
             "HOLD_INCOMPLETE_SLOT_1_NON_PASS_DOWNSTREAM_LOCKED" :
             (active_task ? "ACTIVE_SLOT_1_TASK_IN_PROGRESS" :
               "ACTIVE_REMAINING_CAPACITY_SLOT_1_ELIGIBLE")) &&
           current_envelope["accounting_basis"] == "NON_RESETTABLE_DECLARED_TASK_BUDGET_RESERVATION" &&
           current_envelope["limits"] == phase_envelope["limits"] &&
           current_envelope["consumed"] == (task_consumed ? expected_consumed : phase_envelope["consumed"]) &&
           current_envelope["remaining"] == (task_consumed ? expected_remaining : phase_envelope["remaining"]) &&
           current_envelope["reserved"] == {} &&
           current_envelope["remaining_capacity_usable"] == !terminal_task &&
           current_envelope["remaining_capacity_lock_reason"] == (terminal_task ?
             "SLOT_1_NON_PASS_DOWNSTREAM_DEPENDENCIES_LOCKED_BY_EXACT_FOUNDER_ROUTE" : "NONE") &&
           current_envelope["milestone_order"] == HOST_OWNED_MILESTONES &&
           current_envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           current_envelope["ordered_slots"] == expected_envelope_slots &&
           current_envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25,
             "strict_exit_gate_percent" => 0
           } && current_envelope["external_effects"] == FALSE_EFFECTS,
           "host-owned P3 Phase envelope drift")
    active_contract, = active_task ?
      validate_host_owned_active_task!(root, truth, decision, current_envelope) : [nil, nil]
    validate_host_owned_terminal_task!(root, truth, decision, current_envelope) if terminal_task
    assert(current_envelope["authority_basis"] == {
      "phase_entry_status" => "AUTHORIZED",
      "policy_path" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
      "policy_version" => "1.8",
      "policy_sha256" => "12126e9617011b6395f187939c9a1d7860d84bd3832c1b1b67357fb017e1ee29",
      "source_route_ref" => "current_phase_route",
      "source_route_id" => HOST_OWNED_ROUTE_ID,
      "phase_entry_decision" => decision["bound_evidence"]["p3_phase_entry_decision"],
      "founder_route_decision" => route["founder_route_decision"].slice("path", "sha256", "byte_length")
    }, "host-owned P3 Phase envelope authority drift")

    assert(project["current_phase"] == "P3" &&
           project["phase_name"] == "Single-Agent Runtime + Minimum Trust" &&
           project["p2_execution_status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           project["phase_execution_status"] == (terminal_task ?
             "HOLD_INCOMPLETE_ROUTE_TERMINAL_SLOT_1_NON_PASS" :
             (active_task ? "ACTIVE_SLOT_1_TASK_IN_PROGRESS" :
               "ACTIVE_SLOT_1_ELIGIBLE_NOT_ACTIVATED")) &&
           project["current_route_execution_status"] == (terminal_task ?
             "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_ROUTE_TERMINAL_SLOT_1_NON_PASS" :
             (active_task ? "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_ROUTE_SLOT_1_ACTIVE" :
               "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_ROUTE_READY_SLOT_1")) &&
           project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == (terminal_task ?
             "HOLD_INCOMPLETE_SLOT_1_NON_PASS_DOWNSTREAM_LOCKED" :
             (active_task ? "ACTIVE_INCOMPLETE_SLOT_1_TASK_IN_PROGRESS" :
               "ACTIVE_INCOMPLETE_SLOT_1_ELIGIBLE")) &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "host-owned project projection drift")

    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"), "strict P3 Gate")
    assert(p3["status"] == "INCOMPLETE" && p3["entry_authorized"] == true &&
           p3["execution_started"] == true &&
           p3.dig("exit_gate_authority", "required_exit_evidence") ==
             "Resume, isolation, permission and trace tests" &&
           p3["required_item_ids"] == ["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"] &&
           p3.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") == "MISSING" &&
           p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "host-owned strict P3 Exit projection drift")

    boundary = mapping(truth["phase_boundary"], "host-owned Phase boundary")
    assert(boundary["phase"] == "P3" &&
           boundary["phase_execution_status"] == (terminal_task ?
             "HOLD_INCOMPLETE_ROUTE_TERMINAL_SLOT_1_NON_PASS" :
             (active_task ? "ACTIVE_SLOT_1_TASK_IN_PROGRESS" :
               "ACTIVE_SLOT_1_ELIGIBLE_NOT_ACTIVATED")) &&
           boundary["task_creation_allowed"] == ready_route &&
           boundary["task_creation_scope"] == (terminal_task ?
             "NONE_ROUTE_TERMINAL_DOWNSTREAM_LOCKED" :
             (active_task ? "NONE_ACTIVE_TASK" : "HOST_OWNED_FIXED_WORKFLOW_SLOT_1_ONLY")) &&
           boundary["task_creation_lock_after_activation"] == true &&
           boundary["p3_entry_authorized"] == true &&
           boundary["allowed_task_kinds"] == %w[
             HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION_VERTICAL_SLICE
             FIXED_HANDLER_CRASH_ISOLATION_AND_TRACE_CUSTODY
             INDEPENDENT_P3_STRICT_EXIT_GATE_AUDIT
           ] && boundary["next_eligible_action"] == expected_next_action &&
           boundary["escalation_reason"] == (terminal_task ?
             "P3_ROUTE_CHANGE_REQUIRED_AFTER_SLOT_1_NON_PASS_LOCKED_ALL_REMAINING_DECLARED_SLOTS" : nil) &&
           boundary["user_action_required"] == (terminal_task ?
             "FOUNDER_STRATEGIC_DECISION" : "NONE") &&
           boundary["phase_route_decision_required"] == terminal_task &&
           boundary["phase_route_user_action_required"] == (terminal_task ?
             HOST_OWNED_TERMINAL_ACTION : "NONE") &&
           boundary["default_external_effects"] == FALSE_EFFECTS,
           "host-owned Phase boundary drift")

    control = mapping(truth["founder_escalation_control"], "host-owned Founder escalation control")
    expected_source_event = if terminal_task
                              {
                                "kind" => "P3_PHASE_DELEGATED_SLOT_1_TASK_TERMINAL",
                                "decision_id" => route.dig("terminal_task", "task_id"),
                                "status" =>
                                  "TERMINAL_TASK_GATE_NON_PASS_DOWNSTREAM_LOCKED_NO_REPLACEMENT"
                              }
                            elsif active_task
                              {
                                "kind" => "P3_PHASE_DELEGATED_SLOT_1_TASK_ACTIVATED",
                                "decision_id" => truth.dig("active_work", "current_task"),
                                "status" => "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_SLOT_1_ACTIVE"
                              }
                            else
                              {
                                "kind" => "FOUNDER_P3_OBJECTIVE_AND_PHASE_ROUTE_DECISION_INSTALLED",
                                "decision_id" => HOST_OWNED_DECISION_ID,
                                "status" => "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_ROUTE_READY_SLOT_1"
                              }
                            end
    expected_reserved = terminal_task ? {
      "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
      "evidence" => {
        "terminal_receipt" => HOST_OWNED_TERMINAL_RECEIPT,
        "reason" =>
          "CURRENT_P3_ROUTE_HAS_NO_EXECUTABLE_SLOT_AFTER_SLOT_1_NON_PASS_AND_ANY_CONTINUATION_REQUIRES_A_NEW_PHASE_ROUTE_DECISION"
      }
    } : {"category" => "NONE", "evidence" => nil}
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == (terminal_task ?
             "FOUNDER_DECISION_REQUIRED" : "NO_RESERVED_TRIGGER_CONTINUE_PHASE") &&
           control["source_event"] == expected_source_event &&
           control["reserved_trigger"] == expected_reserved &&
           control["resolved_strategy_decision"] == route["founder_route_decision"].merge(
             "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
             "result" => "P3_HOST_OWNED_FIXED_STATE_WORKFLOW_ROUTE_INSTALLED_SLOT_1_ELIGIBLE"
           ) && control["phase_gate_status"] == "INCOMPLETE" &&
           control["founder_decision_required"] == terminal_task &&
           control["next_action_owner"] == (terminal_task ? "HUMAN_FOUNDER" : "MASTER_CEO_AGENT") &&
           control["next_eligible_action"] == expected_next_action,
           "host-owned Founder escalation projection drift")

    delegation = mapping(truth["phase_delegation"], "host-owned Phase delegation")
    assert(delegation["status"] == (terminal_task ?
             "P3_HOLD_INCOMPLETE_SLOT_1_NON_PASS_FOUNDER_ROUTE_DECISION_REQUIRED" :
             (active_task ? "ACTIVE_P3_HOST_OWNED_FIXED_STATE_WORKFLOW_SLOT_1_TASK" :
               "ACTIVE_P3_HOST_OWNED_FIXED_STATE_WORKFLOW_ROUTE_SLOT_1_ELIGIBLE")) &&
           delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION" &&
           delegation["decision_source"] == HOST_OWNED_DECISION_ID &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation["p3_entry_authorized"] == true &&
           delegation.dig("anti_loop", "route_or_task_may_downgrade_phase_delegation") == false &&
           delegation.dig("anti_loop", "phase_execution_envelope_survives_route_terminal") == true,
           "host-owned Phase delegation drift")

    active = mapping(truth["active_work"], "host-owned active work")
    assert(active["current_task"] == (active_task ? active_contract["task_id"] : "NONE") &&
           active["current_task_status"] == (active_task ? "ACTIVE" : "NONE") &&
           (active_task ? active["execution_nonce"].is_a?(String) : active["execution_nonce"].nil?) &&
           active["execution_nonce_status"] == (terminal_task ?
             "CONSUMED_TERMINAL_NON_PASS" : (active_task ? "ACTIVE_SINGLE_USE" : "NOT_ISSUED")) &&
           active["task_resource_state"] == (terminal_task ?
             "NONE_ROUTE_TERMINAL_SLOT_1_NON_PASS" :
             (active_task ? "ACTIVE_PHASE_DELEGATED_SLOT_1" :
               "NOT_CREATED_PHASE_DELEGATED_SLOT_1_READY")) &&
           active["founder_reserved_authorization"] == route.dig("founder_route_decision", "path") &&
           active["founder_reserved_authorization_sha256"] == route.dig("founder_route_decision", "sha256") &&
           active["founder_decision_required"] == terminal_task &&
           active["founder_decision_required_scope"] == (terminal_task ?
             "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" : nil) &&
           active["user_action_required"] == (terminal_task ?
             "FOUNDER_STRATEGIC_DECISION" : "NONE") &&
           active["phase_route_decision_required"] == terminal_task &&
           active["phase_route_user_action_required"] == (terminal_task ?
             HOST_OWNED_TERMINAL_ACTION : "NONE") &&
           active["next_eligible_action"] == expected_next_action &&
           active["external_effects"] == FALSE_EFFECTS,
           "host-owned active-work projection drift")
    if terminal_task
      assert(active["current_task_contract"].nil? &&
             active["current_task_contract_sha256"].nil? &&
             active["current_execution_authorization"].nil? &&
             active["current_execution_authorization_sha256"].nil? &&
             active["authority_record"].nil? && active["authorization_id"].nil? &&
             active["task_branch"].nil? && active["task_worktree"].nil? &&
             active["execution_evidence_root"].nil? && active["allowlisted_paths"] == [] &&
             mapping(active["budget"], "terminal active-work budget").values.all?(&:nil?) &&
             active.dig("roles", "independent_reviewers") == [] &&
             active.dig("last_completed_task", "task_id") ==
               route.dig("terminal_task", "task_id") &&
             active.dig("last_completed_task", "terminal_receipt") ==
               HOST_OWNED_TERMINAL_RECEIPT,
             "host-owned terminal active-work closure drift")
    end

    execution_claim = mapping(truth["phase_execution_claim"], "host-owned execution claim")
    assert(execution_claim["current_route_claim"] == HOST_OWNED_ROUTE_ID &&
           execution_claim["current_task_claim"] == (active_task ? active["current_task"] : "NONE") &&
           execution_claim["product_capability_changed"] == false &&
           execution_claim["p3_entry_authorized"] == true &&
           execution_claim["p3_exit_gate_progress_percent"] == 0 &&
           execution_claim["p3_delivery_progress_percent"] == 25 &&
           execution_claim["phase_local_allowed"] == (terminal_task ? [] : [active_task ?
             "COMPLETE_HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION_VERTICAL_SLICE" :
             "ACTIVATE_HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION_VERTICAL_SLICE"]),
           "host-owned execution claim drift")
    claim = mapping(truth["claim_boundary"], "host-owned claim boundary")
    expected_current_task = active_task ? active["current_task"] : "NONE"
    assert(claim["current_phase_route"] == HOST_OWNED_ROUTE_ID &&
           claim["current_task"] == expected_current_task &&
           claim["selected_task"] == (terminal_task ?
             "NONE_ROUTE_TERMINAL_SLOT_1_NON_PASS" :
             (active_task ? expected_current_task : "NONE_SLOT_1_ELIGIBLE_NOT_ACTIVATED")) &&
           claim["current_task_status"] == (active_task ? "ACTIVE" : "NONE") &&
           claim["next_eligible_action"] == expected_next_action &&
           claim["p3_status"] == (terminal_task ?
             "HOLD_INCOMPLETE_SLOT_1_NON_PASS_DOWNSTREAM_LOCKED" :
             (active_task ? "ACTIVE_INCOMPLETE_SLOT_1_TASK_IN_PROGRESS" :
               "ACTIVE_INCOMPLETE_SLOT_1_ELIGIBLE")) &&
           claim["p3_phase_envelope_status"] == current_envelope["status"] &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_delivery_progress_percent"] == 25 &&
           claim["p3_accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           claim["p3_host_owned_fixed_state_workflow_route_decision_sha256"] ==
             route.dig("founder_route_decision", "sha256") &&
           claim["long_term_goal_status"] == "ACTIVE",
           "host-owned claim boundary drift")
    if terminal_task
      assert(claim["p3_capability_milestone_status"] ==
               "HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION_NOT_ACCEPTED_P3_006_TERMINAL_NON_PASS" &&
             claim["p3_006_status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
             claim["p3_006_candidate_commit"] == route.dig("terminal_task", "candidate", "commit") &&
             claim["p3_006_candidate_tree"] == route.dig("terminal_task", "candidate", "tree") &&
             claim["p3_006_candidate_integrated"] == false &&
             claim["p3_006_review_verdicts"] ==
               route.dig("terminal_task", "independent_review_verdicts") &&
             claim["p3_006_terminal_blocker_count"] == 3 &&
             claim["p3_006_terminal_receipt_sha256"] == HOST_OWNED_TERMINAL_RECEIPT["sha256"] &&
             claim["p3_006_delivery_credit"] == 0 &&
             claim["p3_006_strict_exit_credit"] == 0,
             "host-owned terminal claim boundary drift")
    end
    goal = mapping(truth["goal"], "Long-term Goal projection")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] == expected_current_task,
           "host-owned route must keep the Long-term Goal active")
    historical = mapping(truth["historical_p3_005_phase_route"], "historical P3-005 Route")
    assert(historical["schema_version"] == "p3-zero-authority-action-envelope-task-route/v1" &&
           historical["status"] == "TERMINAL_SLOT_1_INDEPENDENT_REVIEW_NON_PASS",
           "historical P3-005 terminal accounting drift")
    if terminal_task
      "P3_HOST_OWNED_FIXED_STATE_ROUTE_SLOT_1_TERMINAL_NON_PASS"
    elsif active_task
      "P3_HOST_OWNED_FIXED_STATE_ROUTE_SLOT_1_ACTIVE"
    else
      "P3_HOST_OWNED_FIXED_STATE_ROUTE_SLOT_1_ELIGIBLE"
    end
  end

  def validate_continuation!(truth, project, route)
    milestone_frozen = route["status"] ==
      "TERMINAL_PREACTIVATION_TEMP_ROOT_CONFINEMENT_NON_PASS"
    expected_phase_execution_status = milestone_frozen ?
      "ACTIVE_INCOMPLETE_IMPLEMENTATION_MILESTONE_FROZEN" : "ACTIVE"
    assert(project["current_phase"] == "P3" &&
           project["phase_name"] == "Single-Agent Runtime + Minimum Trust" &&
           project["p2_execution_status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           project["p3_entry_status"] == "AUTHORIZED" && project["p3_execution_status"] == "ACTIVE" &&
           project["phase_execution_status"] == expected_phase_execution_status &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "project P3 continuation projection drift")

    assert(route["schema_version"] == "p3-phase-delegated-task/v1" && route["phase"] == "P3" &&
           route["phase_entry_status"] == "AUTHORIZED" &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["founder_phase_route_decision_required"] == milestone_frozen &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "current P3 continuation Route drift")

    entry_route = mapping(truth["historical_p3_phase_entry_route"], "historical P3 entry Route")
    assert(entry_route["schema_version"] == ROUTE_SCHEMA &&
           entry_route["route_id"] == "P3_PHASE_ENTRY_ACTIVE_PENDING_TASK_SELECTION" &&
           entry_route["phase_entry_status"] == "AUTHORIZED" &&
           entry_route["founder_phase_entry_decision"] == decision_identity.merge(
             "decision_id" => DECISION_ID, "reserved_trigger" => "PHASE_ENTRY_OR_EXIT"
           ) && entry_route["p3_entry_authorized"] == true &&
           entry_route["p4_entry_authorized"] == false && entry_route["long_term_goal_status"] == "ACTIVE" &&
           entry_route["external_effects"] == FALSE_EFFECTS,
           "historical P3 entry Route drift")

    predecessor = mapping(truth["historical_p2_research_exit_phase_route"], "historical P2 research Exit")
    assert(predecessor["status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           predecessor["original_capability_gate_status"] == "MISSING_NOT_ACCEPTED" &&
           predecessor["strict_capability_progress_percent"] == 0 &&
           predecessor["revised_research_exit_percent"] == 100,
           "historical P2 research Exit drift")

    envelope = mapping(truth["phase_execution_envelope"], "P3 Phase envelope")
    consumed = mapping(envelope["consumed"], "P3 consumed capacity")
    remaining = mapping(envelope["remaining"], "P3 remaining capacity")
    reserved = envelope["reserved"].is_a?(Hash) ? envelope["reserved"] : {}
    unconsumed_reservation = reserved["status"] == "ELIGIBLE_NOT_ACTIVATED" ?
      mapping(reserved["budget"], "P3 reserved capacity") : ZERO_CAPACITY
    expected_envelope_status = milestone_frozen ?
      "ACTIVE_INCOMPLETE_CAPABILITY_MILESTONE_FROZEN" : "ACTIVE_REMAINING_CAPACITY"
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" &&
           envelope["phase"] == "P3" && envelope["status"] == expected_envelope_status &&
           envelope["limits"] == LIMITS && envelope["milestone_order"] == MILESTONES &&
           envelope["accepted_milestones"].is_a?(Array) &&
           MILESTONES.first(envelope["accepted_milestones"].length) == envelope["accepted_milestones"] &&
           consumed["engineering_tasks"] + remaining["engineering_tasks"] +
             unconsumed_reservation["engineering_tasks"] == 8 &&
           consumed["engineering_hours"] + remaining["engineering_hours"] +
             unconsumed_reservation["engineering_hours"] == 256 &&
           consumed["calendar_days"] + remaining["calendar_days"] +
             unconsumed_reservation["calendar_days"] == 64 &&
           envelope["remaining_capacity_usable"] == !milestone_frozen &&
           envelope["external_effects"] == FALSE_EFFECTS &&
           envelope.dig("authority_basis", "source_route_ref") == "historical_p3_phase_entry_route" &&
           envelope.dig("authority_basis", "source_decision") == decision_identity,
           "P3 continuation envelope drift")

    phases = mapping(mapping(truth["strict_phase_gate_ledger"], "strict Phase Gate ledger")["phases"],
                     "strict Phase Gate phases")
    p2 = mapping(phases["P2"], "strict P2 Gate")
    p3 = mapping(phases["P3"], "strict P3 Gate")
    assert(p2["status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           p2.dig("original_capability_gate", "status") == "MISSING_NOT_ACCEPTED" &&
           p2.dig("original_capability_gate", "strict_progress_percent") == 0,
           "strict P2 conclusion drift during P3 continuation")
    assert(p3["status"] == "INCOMPLETE" && p3["entry_authorized"] == true &&
           p3["execution_started"] == true &&
           p3["phase_entry_decision"] == decision_identity.merge("decision_id" => DECISION_ID) &&
           p3.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") == "MISSING" &&
           p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "strict P3 Gate continuation projection drift")

    boundary = mapping(truth["phase_boundary"], "P3 Phase boundary")
    assert(boundary["phase"] == "P3" &&
           boundary["phase_execution_status"] == expected_phase_execution_status &&
           boundary["task_creation_allowed"] == !milestone_frozen &&
           boundary["p3_entry_authorized"] == true &&
           boundary["default_external_effects"] == FALSE_EFFECTS,
           "P3 Phase boundary drift")

    control = mapping(truth["founder_escalation_control"], "Founder escalation control")
    expected_disposition = milestone_frozen ?
      "FOUNDER_DECISION_REQUIRED" : "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
    expected_trigger = milestone_frozen ? "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" : "NONE"
    expected_owner = milestone_frozen ? "HUMAN_FOUNDER" : "MASTER_CEO_AGENT"
    assert(control["disposition"] == expected_disposition &&
           control.dig("reserved_trigger", "category") == expected_trigger &&
           control["phase_gate_status"] == "INCOMPLETE" &&
           control["founder_decision_required"] == milestone_frozen &&
           control["next_action_owner"] == expected_owner &&
           control["next_eligible_action"] == route["next_eligible_action"],
           "P3 Founder escalation continuation drift")

    active = mapping(truth["active_work"], "active work")
    expected_user_action = milestone_frozen ?
      "FOUNDER_RESERVED_PHASE_ROUTE_DECISION" : "NONE"
    assert(active["founder_reserved_authorization"] == DECISION_PATH &&
           active["founder_reserved_authorization_sha256"] == DECISION_SHA256 &&
           active["founder_decision_required"] == milestone_frozen &&
           active["user_action_required"] == expected_user_action &&
           active["phase_route_decision_required"] == milestone_frozen &&
           active["external_effects"] == FALSE_EFFECTS,
           "P3 active-work continuation drift")
    if route["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" ||
       milestone_frozen
      assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["next_eligible_action"] == route["next_eligible_action"],
             "P3 completed-Task active-work projection drift")
    end

    claim = mapping(truth["claim_boundary"], "claim boundary")
    assert(claim["current_phase_route"] == route["route_id"] &&
           claim["next_eligible_action"] == route["next_eligible_action"] &&
           claim["p2_original_capability_gate_status"] == "MISSING_NOT_ACCEPTED" &&
           claim["p2_original_capability_progress_percent"] == 0 &&
           claim["p3_status"] == "ACTIVE_INCOMPLETE" && claim["p3_entry_authorized"] == true &&
           claim["p3_phase_envelope_status"] == envelope["status"] &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_accepted_milestones"] == envelope["accepted_milestones"],
           "P3 continuation claim boundary drift")
    milestone_frozen ? "P3_ENTRY_ACTIVE_MILESTONE_FROZEN" : "P3_ENTRY_ACTIVE_CONTINUATION"
  end

  def validate!(root:, truth:)
    root = Pathname.new(root).realpath
    validate_decision!(root)
    project = mapping(truth["project"], "project")
    route = mapping(truth["current_phase_route"], "current P3 Route")
    if route["schema_version"] == P3FinalTransactionalRouteValidation::ROUTE_SCHEMA
      return P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: truth)
    end
    if route["schema_version"] == HOST_OWNED_ROUTE_SCHEMA
      return validate_host_owned_route!(root, truth, project, route)
    end
    if route["schema_version"] == "p3-zero-authority-action-envelope-route/v1"
      require_relative "validate-p3-zero-authority-route" unless
        defined?(P3ZeroAuthorityRouteValidation)
      assert(defined?(P3ZeroAuthorityRouteValidation),
             "P3 zero-authority Route validator is unavailable")
      return P3ZeroAuthorityRouteValidation.validate_truth!(root: root, truth: truth)
    end
    if route["schema_version"] == "p3-zero-authority-action-envelope-task-route/v1"
      require_relative "validate-p3-005-task-authority" unless
        defined?(P3Task005AuthorityValidation)
      assert(defined?(P3Task005AuthorityValidation),
             "P3-005 Task authority validator is unavailable")
      return P3Task005AuthorityValidation.validate!(root: root, truth: truth)
    end
    if route["schema_version"] == P3Task004AuthorityValidation::ROUTE_SCHEMA
      return P3Task004AuthorityValidation.validate!(root: root, truth: truth)
    end
    return validate_continuation!(truth, project, route) unless route["schema_version"] == ROUTE_SCHEMA

    assert(project["current_phase"] == "P3" &&
           project["phase_name"] == "Single-Agent Runtime + Minimum Trust" &&
           project["p2_execution_status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE" &&
           project["phase_execution_status"] == "ACTIVE" &&
           project["current_route_execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "project P3 entry projection drift")

    assert(route["schema_version"] == ROUTE_SCHEMA &&
           route["route_id"] == "P3_PHASE_ENTRY_ACTIVE_PENDING_TASK_SELECTION" &&
           route["status"] == "AUTHORIZED_READY" &&
           route["execution_status"] == "PHASE_DELEGATED_CONTINUATION_READY" &&
           route["scheduling_status"] == "MASTER_SELECTING_FIRST_P3_DURABLE_STATE_TASK" &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == false &&
           route["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["historical_predecessor_route_ref"] == "historical_p2_research_exit_phase_route" &&
           route["p2_research_exit_status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           route["p2_original_capability_gate_status"] == "MISSING_NOT_ACCEPTED" &&
           route["p2_original_capability_progress_percent"] == 0 &&
           route["p3_entry_authorized"] == true && route["p4_entry_authorized"] == false &&
           route["long_term_goal_status"] == "ACTIVE" &&
           route["external_effects"] == FALSE_EFFECTS && route["additional_write_roots"] == [],
           "current P3 Route drift")
    entry = mapping(route["founder_phase_entry_decision"], "P3 Route entry decision")
    assert(entry == decision_identity.merge(
      "decision_id" => DECISION_ID,
      "reserved_trigger" => "PHASE_ENTRY_OR_EXIT"
    ), "current P3 Route decision identity drift")

    predecessor = mapping(truth["historical_p2_research_exit_phase_route"], "historical P2 research Exit")
    assert(predecessor["status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           predecessor["original_capability_gate_status"] == "MISSING_NOT_ACCEPTED" &&
           predecessor["strict_capability_progress_percent"] == 0 &&
           predecessor["revised_research_exit_percent"] == 100 &&
           predecessor["phase_execution_envelope_ref"] == "historical_p2_phase_execution_envelope",
           "historical P2 research Exit drift")

    envelope = mapping(truth["phase_execution_envelope"], "P3 Phase envelope")
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" &&
           envelope["phase"] == "P3" && envelope["status"] == "ACTIVE_REMAINING_CAPACITY" &&
           envelope["accounting_basis"] == "NON_RESETTABLE_DECLARED_TASK_BUDGET_RESERVATION" &&
           envelope["limits"] == LIMITS && envelope["task_ledger"] == [] &&
           envelope["consumed"] == ZERO_CAPACITY && envelope["reserved"].nil? &&
           envelope["remaining"] == FULL_CAPACITY && envelope["remaining_capacity_usable"] == true &&
           envelope["milestone_order"] == MILESTONES && envelope["accepted_milestones"] == [] &&
           envelope["external_effects"] == FALSE_EFFECTS,
           "P3 Phase envelope drift")
    assert(envelope.dig("authority_basis", "source_route_ref") == "current_phase_route" &&
           envelope.dig("authority_basis", "source_route_id") == route["route_id"] &&
           envelope.dig("authority_basis", "source_decision") == decision_identity,
           "P3 Phase envelope authority drift")

    ledger = mapping(truth["strict_phase_gate_ledger"], "strict Phase Gate ledger")
    phases = mapping(ledger["phases"], "strict Phase Gate phases")
    p2 = mapping(phases["P2"], "strict P2 Gate")
    p3 = mapping(phases["P3"], "strict P3 Gate")
    assert(p2["status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           p2.dig("original_capability_gate", "status") == "MISSING_NOT_ACCEPTED" &&
           p2.dig("original_capability_gate", "strict_progress_percent") == 0,
           "strict P2 conclusion drift during P3 entry")
    assert(p3["status"] == "INCOMPLETE" && p3["entry_authorized"] == true &&
           p3["execution_started"] == false &&
           p3["phase_entry_decision"] == decision_identity.merge("decision_id" => DECISION_ID) &&
           p3.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") == "MISSING" &&
           p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "strict P3 Gate entry projection drift")

    boundary = mapping(truth["phase_boundary"], "P3 Phase boundary")
    assert(boundary["phase"] == "P3" && boundary["phase_execution_status"] == "ACTIVE" &&
           boundary["task_creation_allowed"] == true && boundary["p3_entry_authorized"] == true &&
           boundary["allowed_task_kinds"].first == "SINGLE_AGENT_RUNTIME_DURABLE_STATE_AND_RESUME" &&
           boundary["allowed_capabilities"].include?("CHECKPOINT_RESUME") &&
           boundary["default_external_effects"] == FALSE_EFFECTS,
           "P3 Phase boundary drift")

    control = mapping(truth["founder_escalation_control"], "Founder escalation control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control.dig("source_event", "kind") == "P3_PHASE_ENTRY_INSTALLED" &&
           control.dig("reserved_trigger", "category") == "NONE" &&
           control.dig("reserved_trigger", "evidence").nil? &&
           control["resolved_phase_entry_decision"] == decision_identity.merge(
             "category" => "PHASE_ENTRY_OR_EXIT",
             "decision_id" => DECISION_ID,
             "result" => "P3_ENTRY_AUTHORIZED_ACTIVE"
           ) && control["phase_gate_status"] == "INCOMPLETE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK",
           "P3 Founder escalation projection drift")

    active = mapping(truth["active_work"], "active work")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["execution_nonce_status"] == "NOT_ISSUED" &&
           active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_CONTINUATION_READY" &&
           active["founder_reserved_authorization"] == DECISION_PATH &&
           active["founder_reserved_authorization_sha256"] == DECISION_SHA256 &&
           active["founder_decision_required"] == false && active["user_action_required"] == "NONE" &&
           active["phase_route_decision_required"] == false &&
           active["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
           active["external_effects"] == FALSE_EFFECTS,
           "P3 active-work entry projection drift")

    claim = mapping(truth["claim_boundary"], "claim boundary")
    assert(claim["current_phase_route"] == route["route_id"] && claim["current_task"] == "NONE" &&
           claim["next_eligible_action"] == "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" &&
           claim["p2_original_capability_gate_status"] == "MISSING_NOT_ACCEPTED" &&
           claim["p2_original_capability_progress_percent"] == 0 &&
           claim["p3_status"] == "ACTIVE_INCOMPLETE" && claim["p3_entry_authorized"] == true &&
           claim["p3_phase_envelope_status"] == envelope["status"] &&
           claim["p3_exit_gate_progress_percent"] == 0 && claim["p3_accepted_milestones"] == [],
           "P3 claim boundary drift")
    "P3_ENTRY_ACTIVE_TASK_SELECTION_READY"
  end
end

if $PROGRAM_NAME == __FILE__
  p3_zero_authority_route_validator = File.join(__dir__, "validate-p3-zero-authority-route.rb")
  require_relative "validate-p3-zero-authority-route" if File.file?(p3_zero_authority_route_validator)
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.load_file(root.join("docs/aios/truth/project_state.yaml"))
    state = P3PhaseEntryValidation.validate!(root: root, truth: truth)
    puts "P3_PHASE_ENTRY: PASS state=#{state}"
  rescue P3PhaseEntryValidationError, JSON::ParserError, Psych::SyntaxError => e
    warn "P3_PHASE_ENTRY: NON_PASS #{e.message}"
    exit 1
  end
end

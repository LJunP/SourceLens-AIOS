#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

class P3FinalTransactionalRouteValidationError < StandardError; end

module P3FinalTransactionalRouteValidation
  module_function

  ROUTE_SCHEMA = "p3-final-transactional-host-workflow-and-strict-exit-route/v1"
  ROUTE_ID = "P3_FINAL_TRANSACTIONAL_HOST_WORKFLOW_AND_STRICT_EXIT_AUDIT_ROUTE"
  DECISION_SCHEMA =
    "founder-p3-one-final-independent-transactional-host-workflow-and-strict-exit-audit-route-rebaseline/v1"
  DECISION_ID =
    "AUTHORIZE_P3_ONE_FINAL_INDEPENDENT_TRANSACTIONAL_HOST_WORKFLOW_AND_STRICT_EXIT_AUDIT_ROUTE_REBASELINE_V1"
  OPERATION_TYPE =
    "P3_ONE_FINAL_INDEPENDENT_TRANSACTIONAL_HOST_WORKFLOW_AND_STRICT_EXIT_AUDIT_ROUTE_REBASELINE"
  DECISION_PATH =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-route-20260820/decision/FOUNDER_P3_ONE_FINAL_INDEPENDENT_TRANSACTIONAL_HOST_WORKFLOW_AND_STRICT_EXIT_AUDIT_ROUTE_REBASELINE_V1.json"
  DECISION_BYTES = 12_316
  DECISION_SHA256 = "7daa36b2d85a215861051845cf3712b209c1f711c351e1a092e01725b13d1c3d"
  POLICY = {
    "path" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
    "version" => "1.8",
    "sha256" => "12126e9617011b6395f187939c9a1d7860d84bd3832c1b1b67357fb017e1ee29"
  }.freeze
  FALSE_EFFECTS = {
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false
  }.freeze
  MILESTONES = %w[
    DURABLE_STATE_AND_CHECKPOINT_RESUME
    HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION
    FIXED_HANDLER_RESUME_ISOLATION_AND_COMPLETE_TRACE
    INDEPENDENT_P3_EXIT_GATE_AUDIT
  ].freeze
  STRICT_ITEMS = %w[RESUME ISOLATION PERMISSION COMPLETE_OBSERVABLE_TRACE].freeze
  READY_ACTION = "MASTER_ACTIVATE_ONE_FINAL_TRANSACTIONAL_HOST_WORKFLOW_PRODUCT_TASK"
  READY_STATE = "P3_FINAL_TRANSACTIONAL_ROUTE_PRODUCT_SLOT_ELIGIBLE"
  TASK_ID = "AIOS-P3-007_FINAL_TRANSACTIONAL_HOST_WORKFLOW_PERMISSION_ISOLATION_TRACE"
  TASK_SLOT_ID = "P3_FINAL_TRANSACTIONAL_HOST_WORKFLOW_SLOT_1_PRODUCT"
  TASK_CONTRACT = {
    "path" => "docs/aios/tasks/P3-007_FINAL_TRANSACTIONAL_HOST_WORKFLOW_PERMISSION_ISOLATION_TRACE.yaml",
    "byte_length" => 10_889,
    "sha256" => "7fd8a89571ea5982912b40bca613a09273da37dc6bb0011cd3a1a4a3511f7096"
  }.freeze
  TASK_AUTHORITY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007/authority/P3_007_PHASE_DELEGATED_FINAL_TRANSACTIONAL_PRODUCT_TASK_AUTHORITY_V1.json",
    "byte_length" => 6157,
    "sha256" => "4280025239d81182c68dbbcf198eddf8aa3b34a0bce6714922e8081719d3efb5"
  }.freeze
  TASK_BRANCH = "codex/p3-007-final-transactional-host-workflow"
  TASK_WORKTREE =
    "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-007-final-transactional-host-workflow"
  TASK_EVIDENCE_ROOT =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007"
  TASK_CUSTODY_ROOT = "/Users/lijunpeng/Developer/.sourcelens-custody/p3-007-maven-repository"
  TASK_AUTHORIZATION_ID = "0e7dd486-694a-4dac-9281-30470efadbbc"
  TASK_EXECUTION_NONCE = "da3cff61-d23d-49fe-bea9-623786cf86e5"
  TASK_ACTIVATION_PARENT = {
    "commit" => "c94b15474ba22fd6213c4ff5683531d3202cc709",
    "tree" => "67851678f97a36bda593aa186b9fdce6589b629f"
  }.freeze
  PREACTIVATION_ACTION = "P3_007_COMPLETE_PREACTIVATION_BEFORE_PRODUCT_WRITE"
  IMPLEMENT_ACTION = "P3_007_IMPLEMENT_AND_VERIFY_FINAL_TRANSACTIONAL_PRODUCT"
  ACTIVE_PREACTIVATION_STATE = "P3_007_ACTIVE_PREACTIVATION_REQUIRED"
  ACTIVE_IMPLEMENTATION_STATE = "P3_007_ACTIVE_IMPLEMENTATION_AUTHORIZED"
  TASK_BUDGET = {
    "engineering_tasks" => 1,
    "engineering_hours" => 32,
    "calendar_days" => 8,
    "candidate_generations" => 2,
    "same_task_repairs" => 1,
    "review_cycles" => 2
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
  CONSUMED = {
    "engineering_tasks" => 6,
    "engineering_hours" => 192,
    "calendar_days" => 48
  }.freeze
  REMAINING = {
    "engineering_tasks" => 2,
    "engineering_hours" => 64,
    "calendar_days" => 16
  }.freeze

  def assert(condition, message)
    raise P3FinalTransactionalRouteValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
    value
  end

  def array(value, label)
    assert(value.is_a?(Array), "#{label} must be an array")
    value
  end

  def exact_keys(value, keys, label)
    mapping(value, label)
    assert(value.keys.sort == keys.sort, "#{label} keys drift")
    value
  end

  def read_identity!(identity, label, create_once: false)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    path = Pathname.new(record["path"])
    stat = path.lstat
    assert(stat.file? && !path.symlink?, "#{label} must be a non-symlink regular file")
    assert(!create_once || ((stat.mode & 0o777) == 0o444 && stat.nlink == 1),
           "#{label} create-once mode/link drift")
    bytes = path.binread
    assert(bytes.bytesize == record["byte_length"], "#{label} byte length drift")
    assert(Digest::SHA256.hexdigest(bytes) == record["sha256"], "#{label} SHA-256 drift")
    bytes
  rescue Errno::ENOENT, Errno::ELOOP => e
    raise P3FinalTransactionalRouteValidationError, "#{label} unavailable: #{e.message}"
  end

  def read_repo_identity!(root, identity, label)
    record = mapping(identity, label)
    relative = Pathname.new(record.fetch("path"))
    assert(!relative.absolute? && relative.cleanpath.to_s == relative.to_s &&
           !relative.to_s.start_with?("../"), "#{label} path invalid")
    path = root.join(relative)
    assert(path.file? && !path.symlink?, "#{label} must be a repository regular file")
    bytes = path.binread
    assert(bytes.bytesize == record.fetch("byte_length") &&
           Digest::SHA256.hexdigest(bytes) == record.fetch("sha256"),
           "#{label} identity drift")
    bytes
  end

  def git!(root, *args)
    stdout, stderr, status = Open3.capture3("git", *args, chdir: root.to_s)
    assert(status.success?, "git #{args.join(' ')} failed: #{stderr.strip}")
    stdout.strip
  end

  def canonical(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical(value[key])] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def canonical_json(value)
    JSON.generate(canonical(value))
  end

  def load_parent_truth!(root, decision)
    binding = mapping(decision["canonical_binding"], "decision canonical binding")
    commit = binding.fetch("commit")
    tree = binding.fetch("tree")
    assert(binding["branch"] == "main" && commit.match?(/\A[0-9a-f]{40}\z/) &&
           tree.match?(/\A[0-9a-f]{40}\z/), "decision activation parent invalid")
    assert(git!(root, "rev-parse", "#{commit}^{tree}") == tree,
           "decision activation parent tree drift")
    _out, _err, ancestor = Open3.capture3("git", "merge-base", "--is-ancestor", commit, "HEAD",
                                          chdir: root.to_s)
    assert(ancestor.success?, "decision activation parent is not an ancestor of HEAD")
    truth_identity = mapping(binding["truth"], "decision activation-parent Truth")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{commit}:#{truth_identity.fetch('path')}", chdir: root.to_s
    )
    assert(status.success?, "activation-parent Truth unavailable: #{stderr.strip}")
    assert(bytes.bytesize == truth_identity.fetch("byte_length") &&
           Digest::SHA256.hexdigest(bytes) == truth_identity.fetch("sha256"),
           "activation-parent Truth identity drift")
    YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def validate_decision!(root)
    decision_identity = {
      "path" => DECISION_PATH,
      "byte_length" => DECISION_BYTES,
      "sha256" => DECISION_SHA256
    }
    bytes = read_identity!(decision_identity, "Founder route decision", create_once: true)
    decision = JSON.parse(bytes)
    exact_keys(decision, %w[
      schema_version record_type decision_id authority source_kind reserved_trigger operation_type
      created_at source_attachment canonical_binding bound_evidence decision objective strict_exit_gate
      prior_task_ledger phase_envelope ordered_slots architecture preactivation slot_1_acceptance lineage
      target external_effects lifecycle
    ], "Founder route decision")
    assert(decision["schema_version"] == DECISION_SCHEMA && decision["decision_id"] == DECISION_ID &&
           decision["authority"] == "HUMAN_FOUNDER" &&
           decision["source_kind"] == "CURRENT_DIRECT_FOUNDER_REPLY_V1" &&
           decision["reserved_trigger"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           decision["operation_type"] == OPERATION_TYPE,
           "Founder route decision authority drift")
    source = mapping(decision["source_attachment"], "Founder source attachment")
    source_bytes = read_identity!(source, "Founder source attachment")
    assert(source_bytes.include?(DECISION_ID) && source_bytes.include?(OPERATION_TYPE) &&
           source_bytes.include?(decision.dig("canonical_binding", "commit")) &&
           source_bytes.include?(decision.dig("canonical_binding", "tree")) &&
           source_bytes.include?("No Phase envelope expansion") &&
           source_bytes.include?("no network, Provider, Secret, remote write, production, public release") &&
           source_bytes.include?("P4 HOLD") && source_bytes.include?("Long-term Goal ACTIVE"),
           "Founder source attachment does not bind the declared route boundaries")
    binding = mapping(decision["canonical_binding"], "decision canonical binding")
    read_repo_identity!(root, binding.fetch("governing_artifact"), "Strategic Constitution")
    read_repo_identity!(root, binding.fetch("founder_delegation_policy"), "Founder delegation policy")
    read_repo_identity!(root, binding.fetch("repository_execution_rules"), "repository execution rules")
    evidence = mapping(decision["bound_evidence"], "decision bound Evidence")
    %w[p3_phase_entry_decision accepted_p3_001_receipt p3_006_terminal_receipt superseded_route_decision].each do |key|
      read_identity!(evidence.fetch(key), "decision Evidence #{key}")
    end
    assert(decision["decision"] == {
      "supersedes_only" => "P3_006_TERMINAL_ROUTE_DOWNSTREAM_SLOT_LOCK_SCHEDULING_PROJECTION",
      "preserves_p3_006_terminal_non_pass" => true,
      "preserves_p3_006_candidate_unintegrated" => true,
      "preserves_six_consumed_tasks" => true,
      "p3_objective_changed" => false,
      "strict_exit_gate_changed" => false,
      "phase_envelope_expanded" => false,
      "new_external_capability" => false
    }, "Founder route decision scope drift")
    assert(decision.dig("objective", "id") ==
             "HOST_OWNED_FIXED_STATE_WORKFLOW_WITH_EFFECT_FREE_AGENT_PAYLOADS" &&
           decision.dig("objective", "constitution_version") == "2.6" &&
           decision.dig("objective", "constitution_unchanged") == true &&
           decision.dig("strict_exit_gate", "changed") == false &&
           decision.dig("strict_exit_gate", "required_items") == STRICT_ITEMS,
           "P3 Objective or strict Exit Gate drift")
    assert(decision.dig("phase_envelope", "limits") == LIMITS &&
           decision.dig("phase_envelope", "consumed") == CONSUMED &&
           decision.dig("phase_envelope", "remaining") == REMAINING &&
           decision.dig("phase_envelope", "new_capacity") == {
             "engineering_tasks" => 0, "engineering_hours" => 0,
             "calendar_days" => 0, "external_capabilities" => 0
           }, "P3 Phase envelope decision drift")
    slots = array(decision["ordered_slots"], "decision ordered slots")
    assert(slots.length == 2 && slots.map { |slot| slot["ordinal"] } == [1, 2] &&
           slots.map { |slot| slot["kind"] } == ["PRODUCT_IMPLEMENTATION", "EVALUATION_ONLY"] &&
           slots[0]["max_candidate_generations"] == 2 &&
           slots[0]["max_same_task_repairs"] == 1 && slots[0]["max_review_cycles"] == 2 &&
           slots[0]["third_product_attempt_allowed"] == false &&
           slots[1]["max_candidate_generations"] == 0 && slots[1]["formal_dispatches"] == 1 &&
           slots[1]["rerun_to_pass_allowed"] == false && slots[1]["mutable_inputs"] == [],
           "P3 ordered two-slot decision drift")
    assert(decision["external_effects"].values.all? { |value| value == false },
           "P3 route decision grants an external effect")
    [decision, decision_identity]
  rescue JSON::ParserError, Psych::SyntaxError => e
    raise P3FinalTransactionalRouteValidationError, "Founder route decision invalid: #{e.message}"
  end

  def slot_projection(decision)
    decision.fetch("ordered_slots").map do |slot|
      slot.merge("status" => slot.fetch("initial_status"))
    end
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end

  def load_task_activation_truth!(root)
    assert(git!(root, "rev-parse", "#{TASK_ACTIVATION_PARENT.fetch('commit')}^{tree}") ==
             TASK_ACTIVATION_PARENT.fetch("tree"), "P3-007 activation-parent tree drift")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{TASK_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
      chdir: root.to_s
    )
    assert(status.success?, "P3-007 activation-parent Truth unavailable: #{stderr.strip}")
    truth = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    state = validate_truth!(root: root, truth: truth)
    assert(state == READY_STATE, "P3-007 activation parent is not the accepted ready Route")
    truth
  end

  def validate_task_inputs!(root)
    contract_bytes = read_repo_identity!(root, TASK_CONTRACT, "P3-007 Contract")
    contract = YAML.safe_load(
      contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(contract["schema_version"] == "p3-final-transactional-product-task-contract/v1" &&
           contract["record_type"] == "sourcelens_aios_p3_final_transactional_product_task_contract" &&
           contract["task_id"] == TASK_ID && contract["phase"] == "P3" &&
           contract["route_id"] == ROUTE_ID && contract["slot_id"] == TASK_SLOT_ID &&
           contract["status"] == "AUTHORIZED_ACTIVE_PREACTIVATION_REQUIRED" &&
           contract["milestones"] == [
             "HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION",
             "FIXED_HANDLER_RESUME_ISOLATION_AND_COMPLETE_TRACE"
           ] && contract.dig("authority", "activation_parent") ==
             TASK_ACTIVATION_PARENT.merge(
               "branch" => "main",
               "kind" => "FINAL_TRANSACTIONAL_PRODUCT_TASK_RESOURCE_CREATION_PARENT"
             ) && contract["budget"] == TASK_BUDGET &&
           contract.dig("architecture", "persisted_state_is_authoritative") == true &&
           contract.dig("architecture", "sole_next_state_verified_before_model_invocation") == true &&
           contract.dig("architecture", "model_allowed_state") == "AGENT_EFFECT_FREE_PAYLOAD" &&
           contract.dig("architecture", "agent_authority") == "ZERO_EFFECT_AUTHORITY" &&
           contract.dig("preactivation", "required_before_product_source_write") == true &&
           contract.dig("preactivation", "dependency_custody", "formal_maven_repo_local_must_equal_custody_root") == true &&
           contract.dig("preactivation", "dependency_custody", "mutable_user_m2_formal_read_forbidden") == true &&
           contract.dig("task_resources", "branch") == TASK_BRANCH &&
           contract.dig("task_resources", "worktree") == TASK_WORKTREE &&
           contract.dig("task_resources", "evidence_root") == TASK_EVIDENCE_ROOT &&
           contract.dig("task_resources", "dependency_custody_root") == TASK_CUSTODY_ROOT &&
           contract["external_effects"] == FALSE_EFFECTS,
           "P3-007 Contract semantics drift")

    authority_bytes = read_identity!(TASK_AUTHORITY, "P3-007 authority", create_once: true)
    authority = JSON.parse(authority_bytes)
    exact_keys(authority, %w[
      schema_version record_type authorization_id execution_nonce issued_at phase task_id route_id
      slot_id milestones authority_basis contract branch worktree evidence_root dependency_custody_root
      fresh_test_database_root allowlisted_product_paths allowlisted_test_paths preactivation_gate
      execution_envelope budget roles activation_guards external_effects task_gate_owner
      founder_decision_required pass_lifecycle non_pass_lifecycle next_eligible_action
    ], "P3-007 authority")
    assert(authority["schema_version"] == "p3-final-transactional-product-task-authority/v1" &&
           authority["record_type"] ==
             "sourcelens_aios_phase_delegated_final_transactional_product_task_authority" &&
           authority["authorization_id"] == TASK_AUTHORIZATION_ID &&
           authority["execution_nonce"] == TASK_EXECUTION_NONCE && authority["phase"] == "P3" &&
           authority["task_id"] == TASK_ID && authority["route_id"] == ROUTE_ID &&
           authority["slot_id"] == TASK_SLOT_ID && authority["contract"] == TASK_CONTRACT &&
           authority["branch"] == TASK_BRANCH && authority["worktree"] == TASK_WORKTREE &&
           authority["evidence_root"] == TASK_EVIDENCE_ROOT &&
           authority["dependency_custody_root"] == TASK_CUSTODY_ROOT &&
           authority["budget"] == TASK_BUDGET &&
           authority.dig("authority_basis", "activation_parent") ==
             TASK_ACTIVATION_PARENT.merge(
               "branch" => "main",
               "kind" => "FINAL_TRANSACTIONAL_PRODUCT_TASK_RESOURCE_CREATION_PARENT"
             ) && authority.dig("preactivation_gate", "status") ==
             "PENDING_BEFORE_PRODUCT_SOURCE_WRITE" &&
           authority.dig("preactivation_gate", "formal_user_m2_read_allowed") == false &&
           authority.dig("preactivation_gate", "product_source_write_allowed_before_pass") == false &&
           authority.dig("execution_envelope", "maven_repo_local") == TASK_CUSTODY_ROOT &&
           authority.dig("execution_envelope", "mutable_user_m2_formal_read") == false &&
           authority.dig("activation_guards", "p3_006_terminal_receipt_only") == true &&
           authority.dig("activation_guards", "p3_006_rejected_engineering_lineage_read") == false &&
           authority.dig("activation_guards", "p3_002_through_p3_005_rejected_engineering_lineage_read") == false &&
           authority["external_effects"] == FALSE_EFFECTS &&
           authority["founder_decision_required"] == false,
           "P3-007 authority semantics drift")
    [contract, authority]
  rescue JSON::ParserError, Psych::SyntaxError => e
    raise P3FinalTransactionalRouteValidationError, "P3-007 Task input invalid: #{e.message}"
  end

  def validate_task_worktree!(root)
    worktree = Pathname.new(TASK_WORKTREE)
    assert(worktree.directory? && !worktree.symlink?, "P3-007 worktree unavailable")
    branch = git!(worktree, "symbolic-ref", "--quiet", "--short", "HEAD")
    assert(branch == TASK_BRANCH, "P3-007 worktree branch drift")
    _out, _err, status = Open3.capture3(
      "git", "merge-base", "--is-ancestor", TASK_ACTIVATION_PARENT.fetch("commit"), "HEAD",
      chdir: worktree.to_s
    )
    assert(status.success?, "P3-007 worktree does not descend from activation parent")
    canonical_branch = git!(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    assert(canonical_branch == "main", "canonical repository is not on main")
  end

  def validate_preactivation_receipt!(preactivation)
    receipt_identity = exact_keys(
      preactivation.fetch("receipt"), %w[path byte_length sha256], "P3-007 preactivation receipt"
    )
    receipt_bytes = read_identity!(receipt_identity, "P3-007 preactivation receipt", create_once: true)
    receipt = JSON.parse(receipt_bytes)
    assert(receipt["schema_version"] == "p3-007-preactivation-pass-receipt/v1" &&
           receipt["record_type"] == "sourcelens_aios_p3_task_preactivation_pass_receipt" &&
           receipt["task_id"] == TASK_ID && receipt["authorization_id"] == TASK_AUTHORIZATION_ID &&
           receipt["execution_nonce"] == TASK_EXECUTION_NONCE &&
           receipt["contract"] == TASK_CONTRACT && receipt["authority"] == TASK_AUTHORITY &&
           receipt.dig("worktree", "path") == TASK_WORKTREE &&
           receipt.dig("worktree", "branch") == TASK_BRANCH &&
           receipt.dig("dependency_custody", "root") == TASK_CUSTODY_ROOT &&
           receipt.dig("dependency_custody", "status") == "PASS_IMMUTABLE_COMPLETE_INVENTORY" &&
           receipt.dig("execution_envelope", "status") == "PASS" &&
           receipt.dig("sandbox_preflight", "status") == "PASS" &&
           receipt["external_effects"] == FALSE_EFFECTS && receipt["result"] == "PASS" &&
           receipt["product_source_write_authorized"] == true,
           "P3-007 preactivation receipt semantics drift")
    receipt_identity
  rescue JSON::ParserError => e
    raise P3FinalTransactionalRouteValidationError, "P3-007 preactivation receipt invalid: #{e.message}"
  end

  def validate_active_task!(root, truth, decision, decision_identity, parent_truth, route)
    task_parent_truth = load_task_activation_truth!(root)
    assert(truth["historical_p3_final_transactional_route_ready"] ==
             task_parent_truth["current_phase_route"],
           "P3 final transactional ready Route historical copy drift")
    validate_task_inputs!(root)
    validate_task_worktree!(root)

    active = mapping(truth["active_work"], "P3-007 active work")
    preactivation = mapping(active["preactivation"], "P3-007 preactivation")
    preactivation_pass = preactivation["status"] == "PASS_PRODUCT_SOURCE_WRITE_AUTHORIZED"
    if preactivation_pass
      receipt_identity = validate_preactivation_receipt!(preactivation)
      assert(preactivation == {
        "status" => "PASS_PRODUCT_SOURCE_WRITE_AUTHORIZED",
        "receipt" => receipt_identity,
        "dependency_custody_root" => TASK_CUSTODY_ROOT,
        "product_source_write_authorized" => true
      }, "P3-007 passed preactivation projection drift")
    else
      assert(preactivation == {
        "status" => "PENDING_BEFORE_PRODUCT_SOURCE_WRITE",
        "receipt" => nil,
        "dependency_custody_root" => TASK_CUSTODY_ROOT,
        "product_source_write_authorized" => false
      }, "P3-007 pending preactivation projection drift")
    end

    action = preactivation_pass ? IMPLEMENT_ACTION : PREACTIVATION_ACTION
    task_state = preactivation_pass ? "ACTIVE_IMPLEMENTATION" : "ACTIVE_PREACTIVATION_REQUIRED"
    route_execution = preactivation_pass ?
      "ACTIVE_PRODUCT_TASK_IMPLEMENTATION" : "ACTIVE_PRODUCT_TASK_PREACTIVATION"
    project_route_execution = preactivation_pass ?
      "P3_FINAL_TRANSACTIONAL_HOST_WORKFLOW_PRODUCT_TASK_ACTIVE_IMPLEMENTATION" :
      "P3_FINAL_TRANSACTIONAL_HOST_WORKFLOW_PRODUCT_TASK_ACTIVE_PREACTIVATION"

    slots = slot_projection(decision)
    slots[0]["status"] = task_state
    expected_route = deep_copy(task_parent_truth.fetch("current_phase_route"))
    expected_route["lifecycle_stage"] = "PRODUCT_TASK_ACTIVE"
    expected_route["execution_status"] = route_execution
    expected_route["scheduling_status"] = "ACTIVE_SINGLE_PRODUCT_TASK"
    expected_route["next_eligible_action"] = action
    expected_route["ordered_slots"] = slots
    expected_route["active_task"] = {
      "task_id" => TASK_ID,
      "status" => task_state,
      "slot_id" => TASK_SLOT_ID,
      "contract" => TASK_CONTRACT,
      "authority" => TASK_AUTHORITY,
      "branch" => TASK_BRANCH,
      "worktree" => TASK_WORKTREE,
      "evidence_root" => TASK_EVIDENCE_ROOT,
      "dependency_custody_root" => TASK_CUSTODY_ROOT,
      "budget" => TASK_BUDGET
    }
    assert(route == expected_route, "P3-007 active Route projection drift")

    parent_ledger = array(parent_truth.dig("phase_execution_envelope", "task_ledger"),
                          "activation-parent P3 Task ledger")
    task_entry = {
      "task_id" => TASK_ID,
      "route_id" => ROUTE_ID,
      "status" => task_state,
      "milestone" => "HOST_OWNED_FIXED_WORKFLOW_STRUCTURAL_PERMISSION_AND_FIXED_HANDLER_RESUME_ISOLATION_AND_COMPLETE_TRACE",
      "slot_id" => TASK_SLOT_ID,
      "budget" => TASK_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days"),
      "contract" => TASK_CONTRACT,
      "authority" => TASK_AUTHORITY,
      "activation_parent" => TASK_ACTIVATION_PARENT,
      "preactivation_status" => preactivation.fetch("status")
    }
    expected_envelope = deep_copy(task_parent_truth.fetch("phase_execution_envelope"))
    expected_envelope["status"] = "ACTIVE_FINAL_PRODUCT_TASK"
    expected_envelope["task_ledger"] = parent_ledger + [task_entry]
    expected_envelope["consumed"] = {
      "engineering_tasks" => 7, "engineering_hours" => 224, "calendar_days" => 56
    }
    expected_envelope["reserved"] = {
      "task_id" => TASK_ID,
      "slot_id" => TASK_SLOT_ID,
      "status" => task_state,
      "budget" => TASK_BUDGET.slice("engineering_tasks", "engineering_hours", "calendar_days"),
      "contract" => TASK_CONTRACT,
      "authority" => TASK_AUTHORITY
    }
    expected_envelope["remaining"] = {
      "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8
    }
    expected_envelope["remaining_capacity_usable"] = true
    expected_envelope["remaining_capacity_lock_reason"] = "ACTIVE_PRODUCT_TASK_SINGLE_TASK_LOCK"
    expected_envelope["ordered_slots"] = slots
    assert(truth["phase_execution_envelope"] == expected_envelope,
           "P3-007 active Phase envelope drift")

    expected_project = deep_copy(task_parent_truth.fetch("project"))
    expected_project["phase_execution_status"] = "ACTIVE_FINAL_PRODUCT_TASK"
    expected_project["current_route_execution_status"] = project_route_execution
    expected_project["p3_execution_status"] = "ACTIVE_INCOMPLETE_FINAL_PRODUCT_TASK"
    assert(truth["project"] == expected_project, "P3-007 active project projection drift")

    expected_boundary = deep_copy(task_parent_truth.fetch("phase_boundary"))
    expected_boundary["phase_execution_status"] = "ACTIVE_FINAL_PRODUCT_TASK"
    expected_boundary["task_creation_allowed"] = false
    expected_boundary["task_creation_scope"] = "NONE_ACTIVE_SINGLE_PRODUCT_TASK"
    expected_boundary["next_eligible_action"] = action
    assert(truth["phase_boundary"] == expected_boundary,
           "P3-007 active Phase boundary drift")

    expected_control = deep_copy(task_parent_truth.fetch("founder_escalation_control"))
    expected_control["source_event"] = {
      "kind" => "P3_FINAL_TRANSACTIONAL_PRODUCT_TASK_ACTIVE",
      "decision_id" => TASK_ID,
      "status" => task_state
    }
    expected_control["next_eligible_action"] = action
    assert(truth["founder_escalation_control"] == expected_control,
           "P3-007 active Founder control drift")

    delegation = mapping(truth["phase_delegation"], "P3-007 Phase delegation")
    assert(delegation["status"] == "ACTIVE_P3_FINAL_TRANSACTIONAL_PRODUCT_TASK" &&
           delegation["decision_source"] == DECISION_ID &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation.dig("anti_loop", "route_or_task_may_downgrade_phase_delegation") == false,
           "P3-007 active Phase delegation drift")

    assert(active["current_task"] == TASK_ID && active["current_task_status"] == task_state &&
           active["current_task_contract"] == TASK_CONTRACT &&
           active["current_task_contract_sha256"] == TASK_CONTRACT["sha256"] &&
           active["current_execution_authorization"] == TASK_AUTHORITY["path"] &&
           active["current_execution_authorization_sha256"] == TASK_AUTHORITY["sha256"] &&
           active["authority_record"] == TASK_AUTHORITY &&
           active["execution_nonce"] == TASK_EXECUTION_NONCE &&
           active["execution_nonce_status"] == "ACTIVE" &&
           active["authorization_id"] == TASK_AUTHORIZATION_ID &&
           active["activation_parent_commit"] == TASK_ACTIVATION_PARENT["commit"] &&
           active["activation_parent_tree"] == TASK_ACTIVATION_PARENT["tree"] &&
           active["task_resource_state"] == task_state && active["task_branch"] == TASK_BRANCH &&
           active["task_worktree"] == TASK_WORKTREE &&
           active["execution_evidence_root"] == TASK_EVIDENCE_ROOT &&
           active["dependency_custody_root"] == TASK_CUSTODY_ROOT &&
           active["budget"] == TASK_BUDGET && active["external_effects"] == FALSE_EFFECTS &&
           active["founder_decision_required"] == false && active["user_action_required"] == "NONE" &&
           active["phase_route_decision_required"] == false && active["next_eligible_action"] == action &&
           active["last_completed_task"] == task_parent_truth.dig("active_work", "last_completed_task"),
           "P3-007 active-work projection drift")

    execution = mapping(truth["phase_execution_claim"], "P3-007 execution claim")
    assert(execution["current_route_claim"] == ROUTE_ID && execution["current_task_claim"] == TASK_ID &&
           execution["p3_entry_authorized"] == true && execution["p3_exit_gate_progress_percent"] == 0 &&
           execution["p3_delivery_progress_percent"] == 25 &&
           execution["phase_local_allowed"] == [action] && execution["task_creation_allowed"] == false &&
           execution["remaining_capacity_usable"] == true && execution["held_read_allowed"] == false &&
           execution["candidate_integration_allowed"] == false &&
           execution["next_eligible_action"] == action,
           "P3-007 active execution claim drift")
    claim = mapping(truth["claim_boundary"], "P3-007 claim boundary")
    assert(claim["current_phase_route"] == ROUTE_ID && claim["current_task"] == TASK_ID &&
           claim["selected_task"] == TASK_ID && claim["current_task_status"] == task_state &&
           claim["next_eligible_action"] == action &&
           claim["p3_status"] == "ACTIVE_INCOMPLETE_FINAL_PRODUCT_TASK" &&
           claim["p3_phase_envelope_status"] == "ACTIVE_FINAL_PRODUCT_TASK" &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_delivery_progress_percent"] == 25 &&
           claim["p3_capability_milestone_status"] ==
             "FINAL_TRANSACTIONAL_HOST_WORKFLOW_PRODUCT_TASK_ACTIVE_NOT_ACCEPTED" &&
           claim["p3_007_preactivation_status"] == preactivation.fetch("status") &&
           claim["p3_006_status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           claim["p3_006_candidate_integrated"] == false &&
           claim["long_term_goal_status"] == "ACTIVE",
           "P3-007 active claim boundary drift")
    goal = mapping(truth["goal"], "Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] == TASK_ID,
           "P3-007 active Task must preserve the Long-term Goal")
    preactivation_pass ? ACTIVE_IMPLEMENTATION_STATE : ACTIVE_PREACTIVATION_STATE
  end

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
    decision, decision_identity = validate_decision!(root)
    parent_truth = load_parent_truth!(root, decision)
    assert(truth["historical_p3_host_owned_fixed_state_workflow_phase_route"] ==
             parent_truth["current_phase_route"],
           "superseded P3 host-owned Route historical copy drift")

    route = mapping(truth["current_phase_route"], "current final transactional P3 Route")
    if route["lifecycle_stage"] == "PRODUCT_TASK_ACTIVE"
      return validate_active_task!(root, truth, decision, decision_identity, parent_truth, route)
    end
    expected_slots = slot_projection(decision)
    assert(route == {
      "schema_version" => ROUTE_SCHEMA,
      "route_id" => ROUTE_ID,
      "status" => "ACTIVE",
      "lifecycle_stage" => "READY_PRODUCT_SLOT",
      "execution_status" => "READY_PRODUCT_SLOT",
      "scheduling_status" => "PRODUCT_SLOT_ELIGIBLE",
      "phase" => "P3",
      "phase_entry_status" => "AUTHORIZED",
      "policy" => POLICY,
      "founder_phase_route_decision_required" => false,
      "founder_reserved_trigger_resolved" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
      "next_eligible_action" => READY_ACTION,
      "phase_execution_envelope_ref" => "phase_execution_envelope",
      "phase_entry_route_ref" => "historical_p3_phase_entry_route",
      "accepted_foundation_route_ref" => "historical_p3_001_phase_route",
      "superseded_route_ref" => "historical_p3_host_owned_fixed_state_workflow_phase_route",
      "founder_route_decision" => decision_identity.merge(
        "decision_id" => DECISION_ID,
        "reserved_trigger" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
      ),
      "activation_parent" => decision.fetch("canonical_binding").slice("branch", "commit", "tree").merge(
        "truth" => decision.dig("canonical_binding", "truth"),
        "constitution" => decision.dig("canonical_binding", "governing_artifact")
      ),
      "objective_id" => decision.dig("objective", "id"),
      "strict_exit_gate_changed" => false,
      "strict_exit_gate_required_items" => STRICT_ITEMS,
      "prior_task_ledger" => decision.fetch("prior_task_ledger").slice(
        "entry_count", "canonicalization", "canonical_byte_length", "canonical_sha256"
      ),
      "ordered_slots" => expected_slots,
      "p3_entry_authorized" => true,
      "p4_entry_authorized" => false,
      "long_term_goal_status" => "ACTIVE",
      "external_effects" => FALSE_EFFECTS,
      "additional_write_roots" => []
    }, "current final transactional P3 Route drift")

    parent_ledger = array(parent_truth.dig("phase_execution_envelope", "task_ledger"),
                          "activation-parent P3 Task ledger")
    ledger_identity = mapping(decision["prior_task_ledger"], "decision prior Task ledger")
    serialized = canonical_json(parent_ledger)
    assert(parent_ledger.length == 6 && parent_ledger.length == ledger_identity["entry_count"] &&
           serialized.bytesize == ledger_identity["canonical_byte_length"] &&
           Digest::SHA256.hexdigest(serialized) == ledger_identity["canonical_sha256"],
           "activation-parent P3 Task ledger identity drift")
    envelope = mapping(truth["phase_execution_envelope"], "P3 Phase envelope")
    assert(envelope["schema_version"] == "phase-execution-envelope/v1" &&
           envelope["phase"] == "P3" && envelope["status"] == "ACTIVE_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           envelope["accounting_basis"] == "NON_RESETTABLE_DECLARED_TASK_BUDGET_RESERVATION" &&
           envelope["limits"] == LIMITS && envelope["task_ledger"] == parent_ledger &&
           envelope["consumed"] == CONSUMED && envelope["reserved"] == {} &&
           envelope["remaining"] == REMAINING && envelope["remaining_capacity_usable"] == true &&
           envelope["remaining_capacity_lock_reason"] == "NONE" &&
           envelope["milestone_order"] == MILESTONES &&
           envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["ordered_slots"] == expected_slots &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25,
             "strict_exit_gate_percent" => 0
           } && envelope["external_effects"] == FALSE_EFFECTS,
           "P3 final transactional Phase envelope drift")
    assert(envelope["authority_basis"] == {
      "phase_entry_status" => "AUTHORIZED",
      "policy_path" => POLICY["path"],
      "policy_version" => POLICY["version"],
      "policy_sha256" => POLICY["sha256"],
      "source_route_ref" => "current_phase_route",
      "source_route_id" => ROUTE_ID,
      "phase_entry_decision" => decision.dig("bound_evidence", "p3_phase_entry_decision"),
      "founder_route_decision" => decision_identity
    }, "P3 final transactional envelope authority drift")

    project = mapping(truth["project"], "project")
    assert(project["current_phase"] == "P3" &&
           project["phase_name"] == "Single-Agent Runtime + Minimum Trust" &&
           project["p2_execution_status"] == "COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED" &&
           project["phase_execution_status"] == "ACTIVE_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           project["current_route_execution_status"] ==
             "P3_FINAL_TRANSACTIONAL_HOST_WORKFLOW_ROUTE_READY_PRODUCT_SLOT" &&
           project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE_INCOMPLETE_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           project["p4_entry_status"] == "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "project P3 final transactional projection drift")
    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"), "strict P3 Gate")
    assert(p3["status"] == "INCOMPLETE" && p3["entry_authorized"] == true &&
           p3["execution_started"] == true &&
           p3.dig("exit_gate_authority", "required_exit_evidence") ==
             "Resume, isolation, permission and trace tests" &&
           p3["required_item_ids"] == ["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"] &&
           p3.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") == "MISSING" &&
           p3.dig("founder_phase_gate", "status") == "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "strict P3 Exit Gate drift")

    boundary = mapping(truth["phase_boundary"], "P3 Phase boundary")
    assert(boundary["phase"] == "P3" &&
           boundary["phase_execution_status"] == "ACTIVE_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           boundary["task_creation_allowed"] == true &&
           boundary["task_creation_scope"] ==
             "ONE_FINAL_TRANSACTIONAL_HOST_WORKFLOW_PERMISSION_ISOLATION_AND_TRACE_PRODUCT_TASK_ONLY" &&
           boundary["task_creation_lock_after_activation"] == true &&
           boundary["p3_entry_authorized"] == true &&
           boundary["allowed_task_kinds"] == [
             "ONE_FINAL_TRANSACTIONAL_HOST_WORKFLOW_PERMISSION_ISOLATION_AND_TRACE_PRODUCT_TASK",
             "INDEPENDENT_P3_STRICT_EXIT_GATE_AUDIT"
           ] && boundary["escalation_reason"].nil? && boundary["user_action_required"] == "NONE" &&
           boundary["phase_route_decision_required"] == false &&
           boundary["phase_route_user_action_required"] == "NONE" &&
           boundary["next_eligible_action"] == READY_ACTION &&
           boundary["default_external_effects"] == FALSE_EFFECTS,
           "P3 final transactional Phase boundary drift")

    control = mapping(truth["founder_escalation_control"], "Founder escalation control")
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control["source_event"] == {
             "kind" => "FOUNDER_P3_FINAL_TRANSACTIONAL_ROUTE_DECISION_INSTALLED",
             "decision_id" => DECISION_ID,
             "status" => "P3_FINAL_TRANSACTIONAL_ROUTE_READY_PRODUCT_SLOT"
           } && control["reserved_trigger"] == {"category" => "NONE", "evidence" => nil} &&
           control["resolved_strategy_decision"] == decision_identity.merge(
             "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
             "decision_id" => DECISION_ID,
             "reserved_trigger" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
             "result" => "P3_FINAL_TRANSACTIONAL_ROUTE_INSTALLED_PRODUCT_SLOT_ELIGIBLE"
           ) && control["phase_gate_status"] == "INCOMPLETE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == READY_ACTION,
           "P3 final transactional Founder escalation projection drift")

    delegation = mapping(truth["phase_delegation"], "P3 Phase delegation")
    assert(delegation["status"] == "ACTIVE_P3_FINAL_TRANSACTIONAL_ROUTE_PRODUCT_SLOT_ELIGIBLE" &&
           delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION" &&
           delegation["decision_source"] == DECISION_ID &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation["p3_entry_authorized"] == true &&
           delegation.dig("anti_loop", "route_or_task_may_downgrade_phase_delegation") == false &&
           delegation.dig("anti_loop", "phase_execution_envelope_survives_route_terminal") == true,
           "P3 final transactional delegation drift")
    active = mapping(truth["active_work"], "active work")
    assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
           active["execution_nonce_status"] == "NOT_ISSUED" &&
           active["task_resource_state"] == "NOT_CREATED_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           active["founder_reserved_authorization"] == DECISION_PATH &&
           active["founder_reserved_authorization_sha256"] == DECISION_SHA256 &&
           active["founder_decision_required"] == false && active["user_action_required"] == "NONE" &&
           active["phase_route_decision_required"] == false &&
           active["next_eligible_action"] == READY_ACTION && active["external_effects"] == FALSE_EFFECTS &&
           active["last_completed_task"] == parent_truth.dig("active_work", "last_completed_task"),
           "P3 final transactional active-work projection drift")
    execution = mapping(truth["phase_execution_claim"], "P3 phase execution claim")
    assert(execution["current_route_claim"] == ROUTE_ID && execution["current_task_claim"] == "NONE" &&
           execution["p3_entry_authorized"] == true &&
           execution["p3_exit_gate_progress_percent"] == 0 &&
           execution["p3_delivery_progress_percent"] == 25 &&
           execution["phase_local_allowed"] == [READY_ACTION] &&
           execution["task_creation_allowed"] == true &&
           execution["remaining_capacity_usable"] == true &&
           execution["held_read_allowed"] == false &&
           execution["candidate_integration_allowed"] == false &&
           execution["next_eligible_action"] == READY_ACTION,
           "P3 final transactional execution claim drift")
    claim = mapping(truth["claim_boundary"], "P3 claim boundary")
    assert(claim["current_phase_route"] == ROUTE_ID && claim["current_task"] == "NONE" &&
           claim["selected_task"] == "NONE_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           claim["current_task_status"] == "NONE" && claim["next_eligible_action"] == READY_ACTION &&
           claim["p3_status"] == "ACTIVE_INCOMPLETE_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           claim["p3_entry_authorized"] == true &&
           claim["p3_phase_envelope_status"] == "ACTIVE_FINAL_PRODUCT_SLOT_ELIGIBLE" &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_delivery_progress_percent"] == 25 &&
           claim["p3_accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           claim["p3_capability_milestone_status"] ==
             "FINAL_TRANSACTIONAL_HOST_WORKFLOW_PRODUCT_SLOT_ELIGIBLE_NOT_ACCEPTED" &&
           claim["p3_final_transactional_route_decision_sha256"] == DECISION_SHA256 &&
           claim["p3_006_status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           claim["p3_006_candidate_integrated"] == false && claim["p3_006_delivery_credit"] == 0 &&
           claim["p3_006_strict_exit_credit"] == 0 && claim["long_term_goal_status"] == "ACTIVE",
           "P3 final transactional claim boundary drift")
    goal = mapping(truth["goal"], "Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] == "NONE", "Long-term Goal must remain active")
    READY_STATE
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(root.join("docs/aios/truth/project_state.yaml").binread,
                           permitted_classes: [], permitted_symbols: [], aliases: false)
    state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: truth)
    puts "P3_FINAL_TRANSACTIONAL_ROUTE: PASS state=#{state}"
  rescue P3FinalTransactionalRouteValidationError, JSON::ParserError, Psych::SyntaxError => e
    warn "P3_FINAL_TRANSACTIONAL_ROUTE: NON_PASS #{e.message}"
    exit 1
  end
end

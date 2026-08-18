#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

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

  def assert(condition, message)
    raise P3PhaseEntryValidationError, message unless condition
  end

  def mapping(value, label)
    assert(value.is_a?(Hash), "#{label} must be a mapping")
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
    exact_identity(root.join(CONSTITUTION_PATH), CONSTITUTION_BYTES, CONSTITUTION_SHA256,
                   "P3 entry governing Constitution")
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

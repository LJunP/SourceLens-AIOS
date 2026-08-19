#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"

class P3Task004AuthorityValidationError < StandardError; end

module P3Task004AuthorityValidation
  module_function

  ROUTE_SCHEMA = "p3-founder-exception-task-route/v1"
  TASK_ID = "AIOS-P3-004_HERMETIC_SUREFIRE_AND_PERSISTED_CAPABILITY_LEDGER"
  ROUTE_ID = "#{TASK_ID}_FOUNDER_EXCEPTION_ROUTE"
  CONTRACT_PATH = "docs/aios/tasks/P3-004_HERMETIC_SUREFIRE_AND_PERSISTED_CAPABILITY_LEDGER.yaml"
  CONTRACT_BYTES = 9407
  CONTRACT_SHA256 = "0243f29a7f36e550dda4359f13dbacd52f8eb408ae0f57804b3f8b69f2052945"
  DECISION_ID = "AUTHORIZE_P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_ONLY_TERMINAL_V1"
  DECISION_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-hermetic-capability-route-20260819/decision/FOUNDER_P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_TERMINAL_V1.json"
  DECISION_BYTES = 5092
  DECISION_SHA256 = "8470fcea6bf99bca1326233c4d2fed704aa5ab9ec28df3da2a43aa8842924a30"
  P3_001_GATE_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001/terminal/P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json"
  P3_001_GATE_BYTES = 3055
  P3_001_GATE_SHA256 = "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
  P3_003_TERMINAL_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-persisted-tool-capability-ledger-20260819/task-p3-003/terminal/P3_003_TERMINAL_PREACTIVATION_TEMP_ROOT_CONFINEMENT_NON_PASS_RECEIPT_V1.json"
  P3_003_TERMINAL_BYTES = 8569
  P3_003_TERMINAL_SHA256 = "1a488dea0c6750fdb679a27492fc031b5db7ad0e0fd9700e716d9a8dd1b59ed0"
  STAGE_A_RECEIPT_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-hermetic-capability-route-20260819/task-p3-004/preactivation/stage-a-v1/P3_004_STAGE_A_HERMETIC_SUREFIRE_PREACTIVATION_PASS_RECEIPT_V1.json"
  STAGE_A_RECEIPT_BYTES = 8094
  STAGE_A_RECEIPT_SHA256 = "d00b1f958cf83dda994cee1a88b78c216443f8a513ab66867182b54007637453"
  BRANCH = "codex/p3-004-hermetic-capability-ledger"
  WORKTREE = "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-004-hermetic-capability-ledger"
  EVIDENCE_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-hermetic-capability-route-20260819/task-p3-004"
  CANDIDATE_COMMIT = "b31e0f27cec5ba4b0b2e1b3d5e258cc95a5bb210"
  CANDIDATE_TREE = "77a74fdf308083beab30a25bd84793e08e20e45c"
  CANDIDATE_MANIFEST_PATH = File.join(EVIDENCE_ROOT, "candidate", "P3_004_CANDIDATE_MANIFEST_V1.json")
  CANDIDATE_MANIFEST_BYTES = 6550
  CANDIDATE_MANIFEST_SHA256 = "80de3073d2da3fee8156cfd72e025e3fcadc5415909360b28c9b7d7b78d34715"
  TEST_RECEIPT_PATH = File.join(EVIDENCE_ROOT, "tests", "P3_004_FINAL_CLEAN_OFFLINE_TEST_RECEIPT_V1.json")
  TEST_RECEIPT_BYTES = 8272
  TEST_RECEIPT_SHA256 = "1c6122d2953bf16ad304c98f72bb56a9215fca2c9b96e99562aa1ee0f840b3c5"
  REVIEW_PATH = File.join(EVIDENCE_ROOT, "reviews", "P3_004_INDEPENDENT_REVIEW_CYCLE_1_NON_PASS_V1.json")
  REVIEW_BYTES = 4547
  REVIEW_SHA256 = "a073ae3a8ef898779d8fffe198c5ace41756e9b5ea42382c6f4770c537ebc7e1"
  TERMINAL_PATH = File.join(EVIDENCE_ROOT, "terminal", "P3_004_TERMINAL_FINAL_CAPABILITY_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS_RECEIPT_V1.json")
  TERMINAL_BYTES = 6451
  TERMINAL_SHA256 = "3ec5d1ee27c7a0376efe2a45806d92fc2c66ea2c875b1584866f69f1cdd83583"
  CLEANUP_PATH = File.join(EVIDENCE_ROOT, "terminal", "P3_004_TERMINAL_CANDIDATE_PRESERVATION_AND_CLEANUP_RECEIPT_V1.json")
  CLEANUP_BYTES = 2084
  CLEANUP_SHA256 = "265aaeaddb06cf54499e68a724c3c8522ecd59e83c4dc2b2fdaed88d47c7ddfd"
  BUNDLE_PATH = File.join(EVIDENCE_ROOT, "snapshots", "P3_004_REJECTED_CANDIDATE_V1.bundle")
  BUNDLE_BYTES = 9_747_713
  BUNDLE_SHA256 = "a9541c40f0a8486b090cfc222eeccc0260968fe9ba9774065f0705fb5a4eead2"
  BUDGET = {"engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8}.freeze
  FULL_BUDGET = BUDGET.merge(
    "candidate_generations" => 1, "same_task_repairs" => 1, "review_cycles" => 2
  ).freeze
  FALSE_EFFECTS = {
    "network" => false, "provider" => false, "secret" => false,
    "remote" => false, "production" => false, "public" => false
  }.freeze

  def assert(condition, message)
    raise P3Task004AuthorityValidationError, message unless condition
  end

  def exact_file(path, bytes, sha256, label)
    pathname = Pathname.new(path)
    assert(pathname.file? && !pathname.symlink?, "#{label} must be a regular non-symlink file")
    content = pathname.binread
    assert(content.bytesize == bytes && Digest::SHA256.hexdigest(content) == sha256,
           "#{label} identity drift")
    content
  end

  def identity(path, bytes, sha256)
    {"path" => path, "byte_length" => bytes, "sha256" => sha256}
  end

  def contract_identity
    identity(CONTRACT_PATH, CONTRACT_BYTES, CONTRACT_SHA256)
  end

  def decision_identity
    identity(DECISION_PATH, DECISION_BYTES, DECISION_SHA256)
  end

  def stage_a_receipt_identity
    identity(STAGE_A_RECEIPT_PATH, STAGE_A_RECEIPT_BYTES, STAGE_A_RECEIPT_SHA256)
  end

  def git(root, *args)
    stdout, stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
    raise P3Task004AuthorityValidationError, "git #{args.join(' ')} failed: #{stderr}" unless status.success?
    stdout.strip
  end

  def validate_decision!
    decision = JSON.parse(exact_file(DECISION_PATH, DECISION_BYTES, DECISION_SHA256,
                                     "P3-004 Founder route decision"))
    assert(decision["decision_id"] == DECISION_ID &&
           decision["reserved_trigger"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           decision["operation_type"] ==
             "P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_TERMINAL" &&
           decision.dig("route", "new_task_limit") == 1 &&
           decision.dig("route", "implementation_attempt") ==
             "3_OF_3_FINAL_FOUNDER_EXCEPTION" &&
           decision.dig("phase_envelope", "expanded") == false &&
           decision.dig("phase_envelope", "limits") == {
             "engineering_tasks" => 8, "engineering_hours" => 256, "calendar_days" => 64
           } && decision.fetch("external_effects").values.all? { |value| value == false } &&
           decision.dig("lifecycle", "p4_entry_authorized") == false &&
           decision.dig("lifecycle", "long_term_goal_closure_authorized") == false,
           "P3-004 Founder route decision semantics drift")
  end

  def validate_contract!(root)
    contract = YAML.safe_load(
      exact_file(root.join(CONTRACT_PATH), CONTRACT_BYTES, CONTRACT_SHA256, "P3-004 Contract"),
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(contract["schema_version"] == "p3-task-contract/v1" &&
           contract["task_id"] == TASK_ID && contract["route_id"] == ROUTE_ID &&
           contract["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
           contract["milestone"] == "CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT" &&
           contract["implementation_attempt"] == "3_OF_3_FINAL_FOUNDER_EXCEPTION" &&
           contract.dig("authority", "founder_route_decision", "decision_id") == DECISION_ID &&
           contract.dig("ordered_stages", "stage_a", "product_source_write_allowed") == false &&
           contract.dig("ordered_stages", "stage_a", "required_execution", "test") ==
             "AgentSandboxToolTest" && contract["budget"] == FULL_BUDGET.merge(
               "phase_envelope_expanded" => false
             ) && contract["external_effects"] == FALSE_EFFECTS &&
           contract.dig("lineage", "p3_002_rejected_engineering_lineage_read") == false &&
           contract.dig("lineage", "p3_003_access_mode") == "EXACT_TERMINAL_RECEIPT_ONLY",
           "P3-004 Contract semantics drift")
  end

  def validate_predecessors!
    gate = JSON.parse(exact_file(P3_001_GATE_PATH, P3_001_GATE_BYTES, P3_001_GATE_SHA256,
                                 "P3-001 accepted Task Gate receipt"))
    terminal = JSON.parse(exact_file(P3_003_TERMINAL_PATH, P3_003_TERMINAL_BYTES,
                                     P3_003_TERMINAL_SHA256, "P3-003 terminal receipt"))
    assert(gate["accepted_milestone"] == "DURABLE_STATE_AND_CHECKPOINT_RESUME" &&
           gate["task_lifecycle"] == "ACCEPTED_INTEGRATED",
           "P3-001 predecessor milestone drift")
    assert(terminal["task_lifecycle"] ==
             "TERMINAL_PREACTIVATION_TEMP_ROOT_CONFINEMENT_NON_PASS" &&
           terminal.dig("worktree_at_execution", "product_source_writes") == 0 &&
           terminal.dig("worktree_at_execution", "candidate_created") == false &&
           terminal.dig("worktree_at_execution", "integrated") == false,
           "P3-003 terminal boundary drift")
  end

  def validate_authority!(authority_identity, active)
    authority = JSON.parse(exact_file(
      authority_identity.fetch("path"), authority_identity.fetch("byte_length"),
      authority_identity.fetch("sha256"), "P3-004 Task authority"
    ))
    assert(authority["schema_version"] == "p3-founder-exception-task-authority/v1" &&
           authority["task_id"] == TASK_ID && authority["route_id"] == ROUTE_ID &&
           authority["status"] == "ACTIVE" &&
           authority["authorization_id"] == active["authorization_id"] &&
           authority["execution_nonce"] == active["execution_nonce"] &&
           authority["branch"] == BRANCH && authority["worktree"] == WORKTREE &&
           authority["evidence_root"] == EVIDENCE_ROOT &&
           authority["contract"] == contract_identity &&
           authority["founder_route_decision"] == decision_identity &&
           authority["budget"] == FULL_BUDGET && authority["external_effects"] == FALSE_EFFECTS &&
           authority.dig("stage_a", "product_source_write_allowed") == false &&
           authority.dig("lineage", "p3_002_rejected_engineering_lineage_read") == false &&
           authority.dig("lineage", "p3_003_access_mode") == "EXACT_TERMINAL_RECEIPT_ONLY",
           "P3-004 Task authority semantics drift")
    authority
  end

  def validate_stage_a_receipt!
    receipt = JSON.parse(exact_file(
      STAGE_A_RECEIPT_PATH, STAGE_A_RECEIPT_BYTES, STAGE_A_RECEIPT_SHA256,
      "P3-004 Stage A receipt"
    ))
    assert(receipt["task_id"] == TASK_ID && receipt["status"] == "PASS" &&
           receipt["authorization_id"] == "f900df4e-549f-4631-a713-a90887b0cd6e" &&
           receipt["execution_nonce"] == "6e4529a2-42b2-424f-831e-3bec650ae493" &&
           receipt.dig("source_state", "product_source_writes") == 0 &&
           receipt.dig("execution", "exit_code") == 0 &&
           receipt.dig("execution", "tests_run") == 10 &&
           receipt.dig("execution", "failures") == 0 &&
           receipt.dig("execution", "errors") == 0 &&
           receipt.dig("execution", "skipped") == 0 &&
           receipt.dig("execution", "sandbox_deny_network") == true &&
           receipt.dig("execution", "sandbox_deny_writes_outside_task_worktree") == true &&
           receipt.dig("temp_root_proof", "all_observed_paths_within_expected_root") == true &&
           receipt.dig("temp_root_proof", "all_observed_paths_absent_after_execution") == true &&
           receipt.dig("stage_transition", "stage_b_unlocked") == true &&
           receipt.fetch("external_effects").values.all? { |value| value == false },
           "P3-004 Stage A receipt semantics drift")
    receipt.fetch("raw_evidence").each do |raw|
      exact_file(raw.fetch("path"), raw.fetch("byte_length"), raw.fetch("sha256"),
                 "P3-004 Stage A raw Evidence")
    end
    receipt
  end

  def terminal_identity
    identity(TERMINAL_PATH, TERMINAL_BYTES, TERMINAL_SHA256)
  end

  def validate_terminal_evidence!
    candidate_manifest = JSON.parse(exact_file(
      CANDIDATE_MANIFEST_PATH, CANDIDATE_MANIFEST_BYTES, CANDIDATE_MANIFEST_SHA256,
      "P3-004 candidate manifest"
    ))
    test_receipt = JSON.parse(exact_file(
      TEST_RECEIPT_PATH, TEST_RECEIPT_BYTES, TEST_RECEIPT_SHA256,
      "P3-004 final test receipt"
    ))
    review = JSON.parse(exact_file(REVIEW_PATH, REVIEW_BYTES, REVIEW_SHA256,
                                   "P3-004 independent review"))
    terminal = JSON.parse(exact_file(TERMINAL_PATH, TERMINAL_BYTES, TERMINAL_SHA256,
                                     "P3-004 terminal receipt"))
    cleanup = JSON.parse(exact_file(CLEANUP_PATH, CLEANUP_BYTES, CLEANUP_SHA256,
                                    "P3-004 preservation cleanup receipt"))
    exact_file(BUNDLE_PATH, BUNDLE_BYTES, BUNDLE_SHA256, "P3-004 rejected candidate bundle")

    assert(candidate_manifest.dig("source_state", "final_candidate", "commit") == CANDIDATE_COMMIT &&
           candidate_manifest.dig("source_state", "final_candidate", "tree") == CANDIDATE_TREE &&
           candidate_manifest.dig("lifecycle", "task_gate_accepted") == false &&
           candidate_manifest.dig("lifecycle", "capability_milestone_accepted") == false,
           "P3-004 candidate manifest boundary drift")
    assert(test_receipt.dig("candidate", "commit") == CANDIDATE_COMMIT &&
           test_receipt.dig("candidate", "tree") == CANDIDATE_TREE &&
           test_receipt.dig("execution", "tests_run") == 956 &&
           test_receipt.dig("execution", "failures") == 0 &&
           test_receipt.dig("execution", "errors") == 0 &&
           test_receipt.dig("execution", "skipped") == 1 &&
           test_receipt.dig("execution", "sandbox_deny_network") == true &&
           test_receipt.dig("execution", "sandbox_deny_writes_outside_exact_task_worktree") == true,
           "P3-004 final test receipt drift")
    assert(review["target_verdict"] == "NON_PASS" && review["review_cycle"] == 1 &&
           review["frozen_blocker_count"] == 3 &&
           review["repair_budget_status"] == "EXHAUSTED_BEFORE_REVIEW" &&
           review.fetch("frozen_blockers").map { |finding| finding["category"] }.sort ==
             %w[AUTHORITY_OR_EXTERNAL_EFFECT_SAFETY PRODUCT_CORRECTNESS RESULT_INTEGRITY].sort &&
           review.fetch("external_effects").values.all? { |value| value == false },
           "P3-004 independent review drift")
    assert(terminal["task_lifecycle"] ==
             "TERMINAL_FINAL_CAPABILITY_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS" &&
           terminal["route_lifecycle"] == terminal["task_lifecycle"] &&
           terminal["phase_lifecycle"] == "ACTIVE_INCOMPLETE_CAPABILITY_MILESTONE_FROZEN" &&
           terminal["long_term_goal_lifecycle"] == "ACTIVE" &&
           terminal.dig("candidate", "commit") == CANDIDATE_COMMIT &&
           terminal.dig("candidate", "tree") == CANDIDATE_TREE &&
           terminal.dig("candidate", "integrated") == false &&
           terminal.dig("independent_review", "verdict") == "NON_PASS" &&
           terminal["milestone_implementation_freeze"] == true &&
           terminal["automatic_successor_allowed"] == false &&
           terminal["replacement_allowed"] == false &&
           terminal["second_review_cycle_allowed"] == false &&
           terminal.dig("progress", "delivery_percent") == 25 &&
           terminal.dig("progress", "strict_p3_exit_percent") == 0 &&
           terminal["next_action_owner"] == "HUMAN_FOUNDER" &&
           terminal["founder_reserved_trigger"] ==
             "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           terminal.fetch("external_effects").values.all? { |value| value == false },
           "P3-004 terminal receipt semantics drift")
    assert(cleanup.dig("content_addressed_snapshot", "path") == BUNDLE_PATH &&
           cleanup.dig("content_addressed_snapshot", "byte_length") == BUNDLE_BYTES &&
           cleanup.dig("content_addressed_snapshot", "sha256") == BUNDLE_SHA256 &&
           cleanup.dig("content_addressed_snapshot", "contained_commit") == CANDIDATE_COMMIT &&
           cleanup.dig("cleanup", "worktree_removed") == true &&
           cleanup.dig("cleanup", "local_branch_removed") == true &&
           cleanup.dig("cleanup", "candidate_recoverable_from_bundle") == true &&
           cleanup["progress_credit"] == 0,
           "P3-004 preservation cleanup receipt drift")
    assert(git(Pathname.new(__dir__).join("..").realpath, "bundle", "list-heads", BUNDLE_PATH) ==
             "#{CANDIDATE_COMMIT} refs/heads/#{BRANCH}",
           "P3-004 candidate bundle ref drift")
    [terminal, review]
  end

  def validate!(root:, truth:)
    root = Pathname.new(root).realpath
    validate_decision!
    validate_contract!(root)
    validate_predecessors!
    project = truth.fetch("project")
    route = truth.fetch("current_phase_route")
    task = route.fetch("selected_task")
    envelope = truth.fetch("phase_execution_envelope")
    active = truth.fetch("active_work")
    terminal_state = route["status"] ==
      "TERMINAL_FINAL_CAPABILITY_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS"

    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["p3_execution_status"] == "ACTIVE" &&
           project["p4_entry_status"] ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3-004 project Phase projection drift")
    assert(route["schema_version"] == ROUTE_SCHEMA && route["route_id"] == ROUTE_ID &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["founder_phase_route_decision_required"] == terminal_state &&
           route["founder_route_decision"].slice("path", "byte_length", "sha256") ==
             decision_identity && route["external_effects"] == FALSE_EFFECTS &&
           route["additional_write_roots"] == [],
           "P3-004 Route projection drift")
    assert(task["task_id"] == TASK_ID, "P3-004 selected Task id drift")
    assert(task["contract"] == contract_identity && task["budget"] == FULL_BUDGET &&
           task.dig("independence", "p3_002_rejected_lineage_read_compare_copy_or_reuse") == false &&
           task.dig("independence", "p3_003_access_mode") == "EXACT_TERMINAL_RECEIPT_ONLY",
           "P3-004 selected Task identity drift")
    assert(envelope["phase"] == "P3" && envelope["accepted_milestones"] ==
             ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25,
             "strict_exit_gate_percent" => 0
           } && envelope["external_effects"] == FALSE_EFFECTS,
           "P3-004 envelope milestone projection drift")

    if terminal_state
      terminal, review = validate_terminal_evidence!
      terminal_identity_hash = terminal_identity
      ledger = envelope.fetch("task_ledger")
      assert(project["phase_execution_status"] ==
               "ACTIVE_INCOMPLETE_CAPABILITY_MILESTONE_FROZEN" &&
             project["current_route_execution_status"] == route["status"],
             "P3-004 terminal project projection drift")
      assert(route["execution_status"] == route["status"] &&
             route["scheduling_status"] ==
               "FOUNDER_PHASE_ROUTE_DECISION_REQUIRED_CAPABILITY_MILESTONE_FROZEN" &&
             route["next_eligible_action"] ==
               "FOUNDER_DECIDE_P3_PHASE_ROUTE_WITH_CAPABILITY_MILESTONE_FROZEN" &&
             task["status"] == route["status"] && task["candidate_created"] == true &&
             task["product_source_writes"] == 10 && task["integrated"] == false &&
             task.dig("candidate", "commit") == CANDIDATE_COMMIT &&
             task.dig("candidate", "tree") == CANDIDATE_TREE &&
             task.dig("independent_review", "verdict") == "NON_PASS" &&
             task.dig("independent_review", "frozen_blocker_count") == 3 &&
             task["terminal_receipt"] == terminal_identity_hash &&
             task["milestone_status"] == "NOT_ACCEPTED_FINAL_EXCEPTION_NON_PASS" &&
             task["same_task_repair_allowed"] == false &&
             task["second_review_cycle_allowed"] == false &&
             task["automatic_successor_allowed"] == false,
             "P3-004 terminal Task projection drift")
      assert(envelope["status"] == "ACTIVE_INCOMPLETE_CAPABILITY_MILESTONE_FROZEN" &&
             ledger.length == 4 && ledger.last["task_id"] == TASK_ID &&
             ledger.last["status"] == route["status"] &&
             ledger.last["terminal_receipt"] == terminal_identity_hash &&
             ledger.last.dig("candidate", "commit") == CANDIDATE_COMMIT &&
             ledger.last.dig("candidate", "integrated") == false &&
             envelope["consumed"] == {
               "engineering_tasks" => 4, "engineering_hours" => 128, "calendar_days" => 32
             } && envelope["remaining"] == {
               "engineering_tasks" => 4, "engineering_hours" => 128, "calendar_days" => 32
             } && envelope["reserved"] == {} && envelope["remaining_capacity_usable"] == false,
             "P3-004 terminal envelope projection drift")
      assert(active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["task_resource_state"] == "NO_ACTIVE_TASK_CAPABILITY_MILESTONE_FROZEN" &&
             active["execution_nonce_status"] == "CONSUMED_TERMINAL" &&
             active["task_branch"].nil? && active["task_worktree"].nil? &&
             active.dig("authority_record", "path").nil? &&
             active["founder_decision_required"] == true &&
             active["founder_decision_required_scope"] ==
               "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
             active["user_action_required"] == "FOUNDER_RESERVED_PHASE_ROUTE_DECISION" &&
             active["phase_route_decision_required"] == true &&
             active.dig("last_completed_task", "task_id") == TASK_ID &&
             active.dig("last_completed_task", "terminal_receipt") == terminal_identity_hash &&
             active["next_eligible_action"] == route["next_eligible_action"],
             "P3-004 terminal active-work projection drift")
      claim = truth.fetch("claim_boundary")
      assert(claim["current_phase_route"] == ROUTE_ID && claim["current_task"] == "NONE" &&
             claim["selected_task"] == TASK_ID &&
             claim["next_eligible_action"] == route["next_eligible_action"] &&
             claim["p3_status"] == "ACTIVE_INCOMPLETE" && claim["p3_entry_authorized"] == true &&
             claim["p3_phase_envelope_status"] == envelope["status"] &&
             claim["p3_exit_gate_progress_percent"] == 0 &&
             claim["p3_delivery_progress_percent"] == 25 &&
             claim["p3_accepted_milestones"] == envelope["accepted_milestones"] &&
             claim["p3_capability_milestone_status"] ==
               "NOT_ACCEPTED_P3_004_FINAL_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS_FROZEN" &&
             claim["p3_004_product_source_writes"] == 10 &&
             claim["p3_004_candidate_created"] == true &&
             claim["p3_004_candidate_integrated"] == false &&
             claim["p3_004_review_verdict"] == "NON_PASS" &&
             claim["p3_004_terminal_receipt_sha256"] == TERMINAL_SHA256 &&
             claim["p3_004_delivery_credit"] == 0 && claim["p3_004_strict_exit_credit"] == 0,
             "P3-004 terminal claim boundary drift")
      control = truth.fetch("founder_escalation_control")
      assert(control["disposition"] == "FOUNDER_DECISION_REQUIRED" &&
             control.dig("source_event", "kind") ==
               "P3_CAPABILITY_MILESTONE_FINAL_FOUNDER_EXCEPTION_TASK_TERMINAL" &&
             control.dig("source_event", "task_id") == TASK_ID &&
             control.dig("source_event", "status") == route["status"] &&
             control.dig("reserved_trigger", "category") ==
               "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
             control.dig("reserved_trigger", "evidence") == terminal_identity_hash &&
             control["founder_decision_required"] == true &&
             control["next_action_owner"] == "HUMAN_FOUNDER" &&
             control["next_eligible_action"] == route["next_eligible_action"],
             "P3-004 terminal Founder escalation projection drift")
      assert(!Pathname.new(WORKTREE).exist? && git(root, "branch", "--list", BRANCH).empty?,
             "P3-004 terminal worktree or local branch was not closed")
      assert(terminal.dig("independent_review", "sha256") == REVIEW_SHA256 &&
             review["target_verdict"] == "NON_PASS",
             "P3-004 terminal review binding drift")
      return "P3_004_TERMINAL_FINAL_CAPABILITY_EXCEPTION_INDEPENDENT_REVIEW_NON_PASS"
    end

    claim = truth.fetch("claim_boundary")
    expected_claim_task = route["status"] == "AUTHORIZED_TASK_SELECTED_NOT_ACTIVATED" ? "NONE" : TASK_ID
    assert(claim["current_phase_route"] == ROUTE_ID && claim["current_task"] == expected_claim_task &&
           claim["selected_task"] == TASK_ID &&
           claim["next_eligible_action"] == route["next_eligible_action"] &&
           claim["p3_status"] == "ACTIVE_INCOMPLETE" && claim["p3_entry_authorized"] == true &&
           claim["p3_phase_envelope_status"] == envelope["status"] &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_delivery_progress_percent"] == 25 &&
           claim["p3_accepted_milestones"] == envelope["accepted_milestones"] &&
           claim["p3_capability_milestone_status"].start_with?("NOT_ACCEPTED_") &&
           claim["p3_004_product_source_writes"] == 0 &&
           claim["p3_004_candidate_created"] == false &&
           claim["p3_004_delivery_credit"] == 0 && claim["p3_004_strict_exit_credit"] == 0,
           "P3 continuation claim boundary drift")
    control = truth.fetch("founder_escalation_control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == route["next_eligible_action"],
           "P3-004 Founder escalation projection drift")

    if route["status"] == "AUTHORIZED_TASK_SELECTED_NOT_ACTIVATED"
      assert(project["phase_execution_status"] ==
               "ACTIVE_INCOMPLETE_FINAL_CAPABILITY_ROUTE_AUTHORIZED" &&
             project["current_route_execution_status"] ==
               "FOUNDER_EXCEPTION_TASK_SELECTED_NOT_ACTIVATED" &&
             route["execution_status"] == "PENDING_PHASE_DELEGATED_ACTIVATION" &&
             route["next_eligible_action"] == "MASTER_ACTIVATE_EXACT_P3_004" &&
             task["status"] == "ELIGIBLE_NOT_ACTIVATED" && task["product_source_writes"] == 0 &&
             envelope["task_ledger"].length == 3 && envelope["consumed"] == {
               "engineering_tasks" => 3, "engineering_hours" => 96, "calendar_days" => 24
             } && envelope["remaining"] == {
               "engineering_tasks" => 5, "engineering_hours" => 160, "calendar_days" => 40
             } && envelope["remaining_capacity_usable"] == true && envelope["reserved"].nil? &&
             active["current_task"] == "NONE" && active["current_task_status"] == "NONE" &&
             active["current_task_contract"] == contract_identity &&
             active["task_resource_state"] == "NOT_CREATED_FOUNDER_EXCEPTION_TASK_READY" &&
             active["execution_nonce_status"] == "NOT_ISSUED_PREACTIVATION" &&
             active["task_branch"].nil? && active["task_worktree"].nil? &&
             active["execution_evidence_root"].nil? &&
             active.dig("authority_record", "path").nil? &&
             active["next_eligible_action"] == "MASTER_ACTIVATE_EXACT_P3_004",
             "P3-004 READY projection drift")
      return "P3_004_READY_FOR_MASTER_ACTIVATION"
    end

    assert(%w[ACTIVE_STAGE_A_PREACTIVATION_REQUIRED ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION].include?(
             route["status"]
           ), "P3-004 lifecycle state is unsupported")
    authority_identity = active.fetch("authority_record")
    authority = validate_authority!(authority_identity, active)
    ledger = envelope.fetch("task_ledger")
    assert(ledger.length == 4 && ledger.last["task_id"] == TASK_ID &&
           ledger.last["authority"] == authority_identity && envelope["consumed"] == {
             "engineering_tasks" => 4, "engineering_hours" => 128, "calendar_days" => 32
           } && envelope["remaining"] == {
             "engineering_tasks" => 4, "engineering_hours" => 128, "calendar_days" => 32
           } && envelope.dig("reserved", "task_id") == TASK_ID &&
           envelope.dig("reserved", "authority") == authority_identity &&
           active["current_task"] == TASK_ID && active["task_branch"] == BRANCH &&
           active["task_worktree"] == WORKTREE && active["execution_evidence_root"] == EVIDENCE_ROOT,
           "P3-004 ACTIVE accounting projection drift")
    if route["status"] == "ACTIVE_STAGE_A_PREACTIVATION_REQUIRED"
      assert(task["status"] == route["status"] && task["product_source_writes"] == 0 &&
             route["next_eligible_action"] == "RUN_STAGE_A_HERMETIC_PREACTIVATION" &&
             active["current_task_status"] == route["status"] &&
             active["next_eligible_action"] == "RUN_STAGE_A_HERMETIC_PREACTIVATION",
             "P3-004 Stage A projection drift")
      return "P3_004_ACTIVE_STAGE_A_PREACTIVATION_REQUIRED"
    end

    assert(task["status"] == "ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION" &&
           route["next_eligible_action"] == "IMPLEMENT_PERSISTED_CAPABILITY_LEDGER" &&
           active["current_task_status"] == "ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION" &&
           active["next_eligible_action"] == "IMPLEMENT_PERSISTED_CAPABILITY_LEDGER" &&
           task.dig("stage_a", "status") == "PASS" &&
           task.dig("stage_a", "receipt") == stage_a_receipt_identity &&
           envelope.dig("task_ledger", -1, "stage_a_receipt") == stage_a_receipt_identity,
           "P3-004 Stage B projection drift")
    validate_stage_a_receipt!
    stage_a_commit = task.dig("stage_a", "commit")
    assert(stage_a_commit == "f188591f56ac846b98280f94e28abb47e7a55ad6" &&
           task.dig("stage_a", "tree") == "039c5127541f79b9c3ceed7280c8bbf907b56031" &&
           git(WORKTREE, "merge-base", "--is-ancestor", stage_a_commit, "HEAD").empty?,
           "P3-004 Stage A commit ancestry drift")
    "P3_004_ACTIVE_STAGE_B_PRODUCT_IMPLEMENTATION"
  rescue KeyError, JSON::ParserError, Errno::ENOENT => e
    raise P3Task004AuthorityValidationError, e.message
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = Pathname.new(__dir__).join("..").realpath
    truth = YAML.safe_load(root.join("docs/aios/truth/project_state.yaml").binread,
                           permitted_classes: [], permitted_symbols: [], aliases: false)
    state = P3Task004AuthorityValidation.validate!(root: root, truth: truth)
    puts "P3_004_TASK_AUTHORITY: PASS state=#{state}"
  rescue P3Task004AuthorityValidationError, Psych::SyntaxError => e
    warn "P3_004_TASK_AUTHORITY: NON_PASS #{e.message}"
    exit 1
  end
end

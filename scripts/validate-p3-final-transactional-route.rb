#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"
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
  TERMINAL_STATE = "P3_007_TERMINAL_TASK_GATE_NON_PASS"
  TERMINAL_ACTION = "FOUNDER_DECIDE_P3_STRATEGY_AFTER_FINAL_PRODUCT_SLOT_NON_PASS_OR_HOLD"
  HOLD_STATE = "P3_FINAL_TRANSACTIONAL_ROUTE_FOUNDER_RESOLVED_STRATEGIC_HOLD"
  HOLD_ACTION = "NO_ENGINEERING_ACTION_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD"
  HOLD_DISPOSITION = "FOUNDER_RESERVED_DECISION_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD"
  HOLD_ACTIVATION_PARENT = {
    "commit" => "9bfd116e96c353a5be2114da0aa09f75f439d064",
    "tree" => "a73d8ecaf58431e648f1186bf5937012f869e732"
  }.freeze
  HOLD_DECISION_SCHEMA =
    "founder-p3-final-transactional-route-exhausted-strategic-hold-decision/v1"
  HOLD_DECISION_ID =
    "DECIDE_P3_KEEP_STRICT_EXIT_AND_HOLD_AFTER_P3_007_FINAL_TRANSACTIONAL_ROUTE_NON_PASS_V1"
  HOLD_DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-route-hold-20260820/decision/FOUNDER_P3_KEEP_STRICT_EXIT_AND_HOLD_AFTER_P3_007_FINAL_TRANSACTIONAL_ROUTE_NON_PASS_V1.json",
    "byte_length" => 6356,
    "sha256" => "156e4fc85a4cd7c80ecd967ef8ce65b7520b6ad183943994f84b081881cd58cf"
  }.freeze
  HOST_AUTHORIZED_ROUTE_SCHEMA =
    "p3-host-authorized-transactional-trust-boundary-rebaseline-route/v1"
  HOST_AUTHORIZED_ROUTE_ID =
    "P3_HOST_AUTHORIZED_TRANSACTIONAL_TRUST_BOUNDARY_REBASELINE_ROUTE_V1"
  HOST_AUTHORIZED_ROUTE_STATE =
    "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_ELIGIBLE"
  HOST_AUTHORIZED_ROUTE_ACTION =
    "MASTER_ACTIVATE_MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION_TASK"
  HOST_AUTHORIZED_FOUNDATION_ACTIVE_STATE =
    "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_ACTIVE"
  HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION =
    "WORKER_BEGIN_EXECUTABLE_FOUNDATION_WITHIN_FIRST_ENGINEERING_HOUR"
  HOST_AUTHORIZED_FOUNDATION_TERMINAL_STATE =
    "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_TERMINAL_NON_PASS"
  HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION =
    "NONE_ROUTE_TERMINAL_NO_AUTOMATIC_SUCCESSOR_OR_FOUNDER_REQUEST"
  TIK_ROUTE_SCHEMA =
    "p3-trusted-invocation-kernel-process-real-clean-room-route/v1"
  TIK_ROUTE_ID =
    "P3_TRUSTED_INVOCATION_KERNEL_PROCESS_REAL_CLEAN_ROOM_ROUTE_V1"
  TIK_EXTERNAL_EFFECTS = {
    "network" => false,
    "dns" => false,
    "af_inet" => false,
    "af_inet6" => false,
    "provider" => false,
    "secret" => false,
    "real_secret_read" => false,
    "remote" => false,
    "production" => false,
    "public" => false,
    "dependency_download" => false,
    "existing_database_mutation" => false,
    "write_outside_exact_authorized_roots" => false,
    "irreversible_asset_deletion" => false
  }.freeze
  TIK_ROUTE_STATE = "P3_TIK_PROCESS_REAL_FOUNDATION_ELIGIBLE"
  TIK_ROUTE_ACTION = "ACTIVATE_P3_TIK_F1_PROCESS_REAL_CONFORMANCE_FOUNDATION"
  TIK_DECISION_SCHEMA =
    "founder-p3-trusted-invocation-kernel-process-real-clean-room-route-rebaseline/v1"
  TIK_DECISION_ID =
    "AUTHORIZE_P3_TRUSTED_INVOCATION_KERNEL_PROCESS_REAL_CLEAN_ROOM_ROUTE_REBASELINE_V1"
  TIK_DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821/decision/FOUNDER_P3_TRUSTED_INVOCATION_KERNEL_PROCESS_REAL_CLEAN_ROOM_ROUTE_REBASELINE_V1.json",
    "byte_length" => 29_696,
    "sha256" => "aaf69bcd7a11c80a7af0410cca549fc084c69e4a52560175104dbc5e06e976d4"
  }.freeze
  TIK_AUTHORIZATION_BODY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821/decision/FOUNDER_AUTHORIZATION_BODY_V1.txt",
    "byte_length" => 20_308,
    "sha256" => "f7bcecb200c5a7ce9564b63cadf6cd9b5fdf3b11398b48f53e37d635551b6ca7"
  }.freeze
  TIK_ACTIVATION_PARENT = {
    "branch" => "main",
    "commit" => "655a44bb083cf2c292e9b5ebbdd23c9c247f46ee",
    "tree" => "d6c3b8392665caa2d9f83f09f8d6ad8ff0e48248",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_879_743,
      "sha256" => "b7f9305b0250190401bbeeb90d8f6ab68b49cb9a56b003a4349a0ef27891f2e6"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "2.7",
      "byte_length" => 11_364,
      "sha256" => "ee51ed9eeae32ee36d0490d0a270d0822e579ced686e0425b2f45379f17e83c9"
    }
  }.freeze
  TIK_CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "2.8",
    "byte_length" => 11_788,
    "sha256" => "6ca11702c8b364f6e241b16912185868ca160eeaf1d158786f20d5682bb37cd1"
  }.freeze
  TIK_LIMITS = {
    "engineering_tasks" => 11,
    "engineering_hours" => 336,
    "calendar_days" => 84,
    "active_tasks" => 1,
    "task_branches" => 1,
    "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  TIK_CONSUMED = {
    "engineering_tasks" => 8,
    "engineering_hours" => 240,
    "calendar_days" => 60
  }.freeze
  TIK_ROUTE_CAPACITY = {
    "engineering_tasks" => 3,
    "engineering_hours" => 96,
    "calendar_days" => 24
  }.freeze
  TIK_TASK_IDS = %w[
    AIOS-P3-TIK-F1_PROCESS_REAL_BLACK_BOX_CONFORMANCE_FOUNDATION
    AIOS-P3-TIK-P1_HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_KERNEL
    AIOS-P3-TIK-A1_ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT
  ].freeze
  TIK_TASK_BRANCHES = %w[
    codex/p3-tik-f1-process-real-conformance-foundation
    codex/p3-tik-p1-host-authorized-transactional-invocation-kernel
    codex/p3-tik-a1-one-shot-strict-exit-audit
  ].freeze
  TIK_TASK_WORKTREES = %w[
    /Users/lijunpeng/Developer/.sourcelens-worktrees/p3-tik-f1-process-real-conformance-foundation
    /Users/lijunpeng/Developer/.sourcelens-worktrees/p3-tik-p1-host-authorized-transactional-invocation-kernel
    /Users/lijunpeng/Developer/.sourcelens-worktrees/p3-tik-a1-one-shot-strict-exit-audit
  ].freeze
  TIK_TASK_EVIDENCE_ROOTS = %w[
    /Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821/task-foundation
    /Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821/task-product
    /Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821/task-audit
  ].freeze
  TIK_STAGE_BUDGETS = [
    {"engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6},
    {"engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 12},
    {"engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6}
  ].freeze
  TIK_FULL_STAGE_BUDGETS = [
    {
      "engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6,
      "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
    },
    {
      "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 12,
      "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
    },
    {
      "engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6,
      "product_candidates" => 0, "same_task_repairs" => 0, "formal_dispatches" => 1
    }
  ].map(&:freeze).freeze
  TIK_STAGE_KINDS = %w[EVALUATION_FOUNDATION PRODUCT_IMPLEMENTATION EVALUATION_ONLY].freeze
  TIK_REVIEW_ROLES = %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT].freeze
  TIK_FINDING_CATEGORIES = %w[
    EXIT_GATE_VALIDITY AUTHORITY_OR_EXTERNAL_EFFECT_SAFETY RESULT_INTEGRITY
    PRODUCT_CORRECTNESS
  ].freeze
  TIK_STAGE_ALLOWED_PATHS = [
    %w[
      backend-spring/src/test/java/com/sourcelens/module/execution/trustboundary/processreal
      backend-spring/src/test/resources/p3-tik-process-real-foundation
      docs/PROJECT_CODE_MAP.md
    ],
    %w[
      backend-spring/src/main/java/com/sourcelens/module/execution/trustboundary
      backend-spring/src/main/java/com/sourcelens/module/execution/service/ExecutionCheckpointService.java
      backend-spring/src/main/java/com/sourcelens/module/execution/mapper/ExecutionCheckpointStore.java
      backend-spring/src/main/java/com/sourcelens/module/sandbox/macos
      backend-spring/src/main/resources/db/migration/V034__add_trusted_invocation_kernel.sql
      backend-spring/src/test/java/com/sourcelens/module/execution/trustboundary/kernel
      backend-spring/src/test/resources/p3-tik-kernel
      docs/PROJECT_CODE_MAP.md
    ],
    []
  ].map(&:freeze).freeze
  TIK_STAGE_CAPABILITIES = [
    %w[
      P3_001_CHECKPOINT_PUBLIC_BEHAVIOR_COMPOSITION
      PROCESS_REAL_BLACK_BOX_CONFORMANCE_HARNESS
      FROZEN_SUBJECT_ADAPTER_CLI_PROTOCOL
      FILE_BACKED_FRESH_PROCESS_RESTART
      FROZEN_CRASH_AND_ADVERSARIAL_MATRIX
      DETERMINISTIC_DOUBLE_REPLAY
      FAULT_MUTANT_SENSITIVITY
      AUTO_GENERATED_BYTE_MANIFEST
    ],
    %w[
      P3_001_CHECKPOINT_PUBLIC_BEHAVIOR_COMPOSITION
      COMPILE_TIME_CLOSED_ACTION_ALGEBRA
      IMMUTABLE_HOST_WORKFLOW_SPEC
      HOST_POSITIVE_AUTHORIZATION
      CONTENT_ADDRESSED_HOST_CUSTODY
      CREATE_ONCE_PRE_EFFECT_AUTHORIZATION_AND_DISPATCH_INTENT
      SANDBOX_EXEC_HASH_BOUND_DISPOSABLE_ISOLATION
      FRESH_PROCESS_DURABLE_CRASH_RECONCILIATION
      EXACTLY_ONE_TERMINAL_INVOCATION_TRACE
      CHECKPOINT_ADVANCEMENT_AFTER_TERMINAL_TRACE_ACCEPTANCE
    ],
    %w[
      ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT
      FROZEN_CANDIDATE_AND_FOUNDATION_REPLAY
      PERMISSION_ADVERSARIAL_CRASH_AND_TRACE_MATRIX
      EXACT_EVIDENCE_IDENTITY_AUDIT
    ]
  ].map(&:freeze).freeze
  TIK_DEFERRED_PLATFORM_CAPABILITIES = %w[
    P4_SOFTWARE_ENGINEER_AGENT_ALPHA OPEN_AGENT_SHELL MODEL_INITIATED_CANONICAL_WRITE
    PLATFORM_IDENTITY SUPERVISOR ROOT_CUSTODY STRONG_ISOLATION MULTI_AGENT_RUNTIME
  ].freeze
  TIK_IMMUTABLE_AUTHORITY_PATHS = %w[
    AGENTS.md docs/aios/STRATEGIC_CONSTITUTION.md docs/aios/MASTER_EXECUTION_PROTOCOL.md
    docs/aios/FOUNDER_DELEGATION_POLICY.md docs/aios/EVALUATION_PROTOCOL.md
  ].freeze
  TIK_STAGE_OBJECTIVES = [
    "Freeze a process-real black-box conformance foundation and subject CLI protocol that independently detects every authorized crash, injection, custody, isolation, replay, trace and manifest failure without modifying product source.",
    "Implement the one fixed VERIFY_CUSTODY_SHA256_V1 trusted invocation kernel against the frozen Stage 1 subject protocol with durable pre-effect authorization, OS-enforced isolation, exactly-one terminal trace and terminal-gated P3-001 checkpoint advancement.",
    "Execute exactly one independent formal held audit of the locked Stage 2 product candidate and frozen Stage 1 foundation without mutating product, evaluator, inputs, schedule, metric, threshold or Evidence generator."
  ].freeze
  TIK_STAGE_CLAIM_BOUNDARIES = [
    "PROCESS_REAL_BLACK_BOX_CONFORMANCE_FOUNDATION_ONLY_NO_PRODUCT_CAPABILITY_CLAIM",
    "MACOS_JDK17_LOCAL_ONE_FIXED_READ_ONLY_CUSTODY_SHA256_WORKFLOW_ONLY_NO_PRODUCTION_CLAIM",
    "ONE_SHOT_FORMAL_P3_STRICT_EXIT_EVIDENCE_ONLY_NO_P4_OR_PRODUCTION_CLAIM"
  ].freeze
  TIK_STAGE_GATE_REQUIREMENTS = [
    %w[
      FOCUSED_MATRIX_PASS UNSAFE_OR_UNAUTHORIZED_EFFECT_COUNT_ZERO SECRET_READ_COUNT_ZERO
      OUTSIDE_ROOT_WRITE_COUNT_ZERO NETWORK_CAPABILITY_COUNT_ZERO DUPLICATE_TERMINAL_COUNT_ZERO
      CHECKPOINT_BEFORE_TERMINAL_COUNT_ZERO REPLAY_SEMANTIC_MISMATCH_COUNT_ZERO
      MANIFEST_IDENTITY_MISMATCH_COUNT_ZERO THREE_INDEPENDENT_REVIEWS_PASS
    ],
    %w[
      FROZEN_FOUNDATION_HARNESS_PASS NON_EMPTY_TESTABLE_PRODUCT_SOURCE_DIFF CLEAN_JDK17_BUILD_PASS
      FULL_MAVEN_SUITE_PASS FILE_BACKED_PROCESS_REAL_INTEGRATION_PASS
      SOURCE_COMPILED_MIGRATION_PROFILE_COMMAND_AND_MANIFEST_IDENTITY_CLOSED
      ROLLBACK_RECOVERY_REPLAY_PASS THREE_INDEPENDENT_REVIEWS_PASS
    ],
    %w[
      EXACTLY_ONE_FORMAL_DISPATCH P3_001_RESUME_PASS HOST_ONLY_POSITIVE_AUTHORIZATION_PASS
      AGENT_PROPOSAL_ZERO_AUTHORITY_PASS DURABLE_PRE_EFFECT_INTENT_PASS ACTUAL_OS_ISOLATION_PASS
      CRASH_RECONCILIATION_PASS EXACTLY_ONE_TERMINAL_TRACE_PASS TERMINAL_BEFORE_CHECKPOINT_PASS
      PERMISSION_ADVERSARIAL_MATRIX_PASS COMPLETE_TRACE_AND_EVIDENCE_IDENTITY_PASS
      ZERO_UNSAFE_SECRET_NETWORK_OUTSIDE_WRITE_AND_FALSE_SUCCESS THREE_INDEPENDENT_REVIEWS_PASS
    ]
  ].map(&:freeze).freeze
  TIK_STAGE_1_ZERO_FAILURE_GATES = %w[
    UNSAFE_OR_UNAUTHORIZED_EFFECT_COUNT_ZERO SECRET_READ_COUNT_ZERO OUTSIDE_ROOT_WRITE_COUNT_ZERO
    NETWORK_CAPABILITY_COUNT_ZERO DUPLICATE_TERMINAL_COUNT_ZERO CHECKPOINT_BEFORE_TERMINAL_COUNT_ZERO
    REPLAY_SEMANTIC_MISMATCH_COUNT_ZERO MANIFEST_IDENTITY_MISMATCH_COUNT_ZERO
  ].freeze
  TIK_STAGE_1_REQUIRED_MATRICES = %w[
    FRESH_PROCESS_CRASH_CUT_MATRIX INJECTION_AND_UNKNOWN_FIELD_MATRIX
    STATE_RESOURCE_BUDGET_NONCE_MATRIX CUSTODY_TRAVERSAL_SYMLINK_AND_BYTE_SWAP_MATRIX
    SECRET_OUTSIDE_WRITE_DNS_AF_INET_AF_INET6_MATRIX TERMINAL_CHECKPOINT_BINDING_MATRIX
    COMPILED_PROFILE_MANIFEST_AND_FINDING_SET_HASH_DRIFT_MATRIX
    DETERMINISTIC_DOUBLE_REPLAY_AND_FAULT_SENSITIVITY_MATRIX
  ].freeze
  TIK_STAGE_2_ALLOWED_SOURCE_ROOTS = [
    "backend-spring/src/main/java/com/sourcelens/module/execution/trustboundary/**",
    "MINIMUM_EXISTING_EXECUTION_SERVICE_OR_STORE_CHANGES_FOR_TERMINAL_GATED_CHECKPOINT_ONLY",
    "backend-spring/src/main/java/com/sourcelens/module/sandbox/FAIL_CLOSED_MACOS_SANDBOX_EXEC_ONLY",
    "backend-spring/src/main/resources/db/migration/NEXT_SINGLE_UNUSED_MIGRATION_ONLY",
    "DIRECT_TASK_TESTS_AND_RESOURCES_ONLY"
  ].freeze
  TIK_STAGE_3_MUTATION_BAN = %w[
    PRODUCT_SOURCE TEST_EVALUATOR_OR_FOUNDATION SUBJECT_PROTOCOL
    MIGRATION_WORKFLOW_SPEC_OR_CUSTODY_BYTES EXECUTABLE_PROFILE_METRIC_THRESHOLD_OR_FAULT_SCHEDULE
    CANDIDATE_OR_EVIDENCE_GENERATOR
  ].freeze
  TIK_PASS_GATE_RESULTS = [
    {
      "focused_matrix" => "PASS",
      "unsafe_or_unauthorized_effect_count" => 0,
      "secret_read_count" => 0,
      "outside_root_write_count" => 0,
      "network_capability_count" => 0,
      "duplicate_terminal_count" => 0,
      "checkpoint_before_terminal_count" => 0,
      "replay_semantic_mismatch_count" => 0,
      "manifest_identity_mismatch_count" => 0,
      "independent_reference_subject_reachable" => true,
      "fresh_process_restart" => true,
      "deterministic_double_replay" => true,
      "fault_mutant_sensitivity" => true
    },
    {
      "frozen_foundation_harness" => "PASS",
      "non_empty_testable_product_source_diff" => true,
      "clean_jdk17_build" => "PASS",
      "full_maven_suite" => "PASS",
      "file_backed_process_real_integration" => "PASS",
      "source_compiled_migration_profile_commands_and_manifest_identity" => "PASS",
      "rollback_recovery_replay" => "PASS",
      "unsafe_or_unauthorized_effect_count" => 0,
      "secret_read_count" => 0,
      "outside_root_write_count" => 0,
      "network_capability_count" => 0
    },
    {
      "formal_dispatch_count" => 1,
      "p3_001_resume" => "PASS",
      "host_only_positive_authorization" => "PASS",
      "agent_proposal_zero_authority" => "PASS",
      "durable_pre_effect_intent" => "PASS",
      "actual_os_isolation" => "PASS",
      "crash_reconciliation" => "PASS",
      "exactly_one_terminal_trace" => "PASS",
      "terminal_before_checkpoint" => "PASS",
      "permission_and_adversarial_matrix" => "PASS",
      "complete_trace_and_evidence_identity" => "PASS",
      "unsafe_action_count" => 0,
      "secret_read_count" => 0,
      "network_capability_count" => 0,
      "outside_root_write_count" => 0,
      "false_success_count" => 0
    }
  ].map(&:freeze).freeze
  TIK_STAGE_RESOURCE_PREFIXES = %w[P3_TIK_F1 P3_TIK_P1 P3_TIK_A1].freeze
  TIK_STAGE_RESOURCE_ROOT_NAMES = %w[task-foundation task-product task-audit].freeze
  TIK_STAGE_RESOURCES = TIK_STAGE_RESOURCE_PREFIXES.each_with_index.map do |prefix, index|
    evidence_root = TIK_TASK_EVIDENCE_ROOTS.fetch(index)
    {
      "branch" => TIK_TASK_BRANCHES.fetch(index),
      "worktree" => TIK_TASK_WORKTREES.fetch(index),
      "evidence_root" => evidence_root,
      "contract_path" => "#{evidence_root}/contract/#{prefix}_TASK_CONTRACT_V1.json",
      "authority_path" => "#{evidence_root}/authority/#{prefix}_PHASE_DELEGATED_TASK_AUTHORITY_V1.json",
      "candidate_manifest_path" => if index == 2
        "#{evidence_root}/candidate/#{prefix}_LOCKED_CANDIDATE_MANIFEST_V1.json"
      else
        "#{evidence_root}/candidate/#{prefix}_CANDIDATE_MANIFEST_V1.json"
      end,
      "cycle_1_candidate_manifest_path" =>
        "#{evidence_root}/candidate/CYCLE_1_#{prefix}_CANDIDATE_MANIFEST_V1.json",
      "cycle_1_gate_evidence_path" =>
        "#{evidence_root}/gate/CYCLE_1_#{prefix}_GATE_EVIDENCE_V1.json",
      "gate_evidence_path" => "#{evidence_root}/gate/#{prefix}_GATE_EVIDENCE_V1.json",
      "rejected_bundle_path" =>
        "#{evidence_root}/terminal/#{prefix}_REJECTED_CANDIDATE_BUNDLE_V1.bundle",
      "bundle_attestation_path" =>
        "#{evidence_root}/terminal/#{prefix}_REJECTED_BUNDLE_VERIFICATION_ATTESTATION_V1.json",
      "cycle_1_finding_set_path" =>
        "#{evidence_root}/reviews/cycle-1/#{prefix}_FROZEN_FINDING_SET_V1.json",
      "cycle_1_cto_review_path" =>
        "#{evidence_root}/reviews/cycle-1/CTO_REVIEW_V1.json",
      "cycle_1_security_review_path" =>
        "#{evidence_root}/reviews/cycle-1/SECURITY_REVIEW_V1.json",
      "cycle_1_quality_review_path" =>
        "#{evidence_root}/reviews/cycle-1/QUALITY_EVALUATION_REVIEW_V1.json",
      "cto_review_path" => "#{evidence_root}/reviews/CTO_REVIEW_V1.json",
      "security_review_path" => "#{evidence_root}/reviews/SECURITY_REVIEW_V1.json",
      "quality_review_path" => "#{evidence_root}/reviews/QUALITY_EVALUATION_REVIEW_V1.json",
      "task_gate_pass_receipt_path" =>
        "#{evidence_root}/terminal/#{prefix}_TASK_GATE_PASS_RECEIPT_V1.json",
      "task_gate_non_pass_receipt_path" =>
        "#{evidence_root}/terminal/#{prefix}_TERMINAL_TASK_GATE_NON_PASS_RECEIPT_V1.json"
    }.freeze
  end.freeze
  TIK_LIFECYCLE_STATES = {
    "FOUNDATION_STAGE_ELIGIBLE" => TIK_ROUTE_STATE,
    "FOUNDATION_TASK_ACTIVE" => "P3_TIK_PROCESS_REAL_FOUNDATION_TASK_ACTIVE",
    "PRODUCT_STAGE_ELIGIBLE" => "P3_TIK_PROCESS_REAL_PRODUCT_ELIGIBLE",
    "PRODUCT_TASK_ACTIVE" => "P3_TIK_PROCESS_REAL_PRODUCT_TASK_ACTIVE",
    "AUDIT_STAGE_ELIGIBLE" => "P3_TIK_PROCESS_REAL_AUDIT_ELIGIBLE",
    "AUDIT_TASK_ACTIVE" => "P3_TIK_PROCESS_REAL_AUDIT_TASK_ACTIVE",
    "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
      "P3_TIK_PROCESS_REAL_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
    "ROUTE_TERMINAL_NON_PASS" => "P3_TIK_PROCESS_REAL_ROUTE_TERMINAL_NON_PASS"
  }.freeze
  TIK_LIFECYCLE_SPECS = {
    "FOUNDATION_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE_FOUNDATION_STAGE_ELIGIBLE",
      "stage_statuses" => %w[ELIGIBLE_NOT_ACTIVATED LOCKED_FOUNDATION_NOT_ACCEPTED LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => nil,
      "completed_stages" => 0,
      "delivery" => 25,
      "strict_exit" => 0,
      "next_action" => TIK_ROUTE_ACTION,
      "task_creation_allowed" => true,
      "founder_gate" => false
    },
    "FOUNDATION_TASK_ACTIVE" => {
      "route_status" => "ACTIVE_FOUNDATION_TASK",
      "stage_statuses" => %w[ACTIVE LOCKED_FOUNDATION_NOT_ACCEPTED LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => 0,
      "completed_stages" => 0,
      "delivery" => 25,
      "strict_exit" => 0,
      "next_action" => "EXECUTE_P3_TIK_F1_PROCESS_REAL_CONFORMANCE_FOUNDATION",
      "task_creation_allowed" => false,
      "founder_gate" => false
    },
    "PRODUCT_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE_PRODUCT_STAGE_ELIGIBLE",
      "stage_statuses" => %w[ACCEPTED ELIGIBLE_NOT_ACTIVATED LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => nil,
      "completed_stages" => 1,
      "delivery" => 50,
      "strict_exit" => 0,
      "next_action" => "ACTIVATE_P3_TIK_P1_HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_KERNEL",
      "task_creation_allowed" => true,
      "founder_gate" => false
    },
    "PRODUCT_TASK_ACTIVE" => {
      "route_status" => "ACTIVE_PRODUCT_TASK",
      "stage_statuses" => %w[ACCEPTED ACTIVE LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => 1,
      "completed_stages" => 1,
      "delivery" => 50,
      "strict_exit" => 0,
      "next_action" => "EXECUTE_P3_TIK_P1_HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_KERNEL",
      "task_creation_allowed" => false,
      "founder_gate" => false
    },
    "AUDIT_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE_AUDIT_STAGE_ELIGIBLE",
      "stage_statuses" => %w[ACCEPTED ACCEPTED ELIGIBLE_NOT_ACTIVATED],
      "active_stage" => nil,
      "completed_stages" => 2,
      "delivery" => 75,
      "strict_exit" => 0,
      "next_action" => "ACTIVATE_P3_TIK_A1_ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT",
      "task_creation_allowed" => true,
      "founder_gate" => false
    },
    "AUDIT_TASK_ACTIVE" => {
      "route_status" => "ACTIVE_AUDIT_TASK",
      "stage_statuses" => %w[ACCEPTED ACCEPTED ACTIVE],
      "active_stage" => 2,
      "completed_stages" => 2,
      "delivery" => 75,
      "strict_exit" => 0,
      "next_action" => "EXECUTE_P3_TIK_A1_ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT",
      "task_creation_allowed" => false,
      "founder_gate" => false
    },
    "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" => {
      "route_status" => "COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
      "stage_statuses" => %w[ACCEPTED ACCEPTED ACCEPTED],
      "active_stage" => nil,
      "completed_stages" => 3,
      "delivery" => 100,
      "strict_exit" => 100,
      "next_action" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "task_creation_allowed" => false,
      "founder_gate" => true
    }
  }.freeze
  TIK_STAGE_IDS = %w[
    PROCESS_REAL_BLACK_BOX_CONFORMANCE_FOUNDATION
    HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_KERNEL_PRODUCT
    ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT
  ].freeze
  TIK_OLD_TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/terminal/P3_HATB_F1_TERMINAL_FOUNDATION_TASK_GATE_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 9_883,
    "sha256" => "bbbb76ad9a3a5ff81d02103771540a29135e39c10e8187b3cb123f9508d80756"
  }.freeze
  HPE_ROUTE_SCHEMA = "p3-host-process-enforced-minimal-slice-route/v1"
  HPE_ROUTE_ID = "P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_V1"
  HPE_DECISION_SCHEMA =
    "founder-p3-host-process-enforced-minimal-slice-route-rebaseline/v1"
  HPE_DECISION_ID =
    "AUTHORIZE_P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_REBASELINE_AFTER_TIK_F1_TERMINAL_V1"
  HPE_DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-process-enforced-minimal-slice-20260821/decision/FOUNDER_P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_REBASELINE_AFTER_TIK_F1_TERMINAL_V1.json",
    "byte_length" => 25_969,
    "sha256" => "ce9ee638c3112d098f0e1ebf55f862a30a053e479eeaf780980c9cde8425019d"
  }.freeze
  HPE_AUTHORIZATION_BODY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-process-enforced-minimal-slice-20260821/decision/FOUNDER_AUTHORIZATION_BODY_V1.txt",
    "byte_length" => 17_085,
    "sha256" => "b4be5e40155710913c2e6b61214f07b5df4cd176cbd8cf07f7eecf24f2283202"
  }.freeze
  HPE_AUTHORIZATION_ATTACHMENT = {
    "path" => "/Users/lijunpeng/.codex/attachments/e77ae6e2-1ec9-49dc-8853-f7ad62f9a76d/pasted-text.txt",
    "byte_length" => 17_084,
    "sha256" => "50332522517e407a1c7d8ffce03a4c5edcc3dec04bc6228a0d09705516ac68bb"
  }.freeze
  HPE_CANONICAL_START = {
    "repository" => "/Users/lijunpeng/Developer/SourceLens-AIOS",
    "branch" => "main",
    "commit" => "b6d7b398278f3e64ef8ee5761c9324cdebf0e8f3",
    "tree" => "2de5445ca28cb73b0093d02780f9248ad4b8b049",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_899_425,
      "sha256" => "fdc473bebc781271dbec7a622a936556b92bc46d44aef55314fa251052fb2ac1"
    },
    "constitution" => TIK_CONSTITUTION,
    "long_term_goal_status" => "ACTIVE",
    "terminal_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821/task-foundation/terminal/P3_TIK_F1_TERMINAL_TASK_GATE_NON_PASS_RECEIPT_V1.json",
      "byte_length" => 5_205,
      "sha256" => "5e9350b2e21973203f146523fec0a4d5ee4c86a0602269eb9795c787a55c0c8b"
    },
    "rejected_bundle_attestation" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821/task-foundation/terminal/P3_TIK_F1_REJECTED_BUNDLE_VERIFICATION_ATTESTATION_V1.json",
      "byte_length" => 2_882,
      "sha256" => "9abe2565c0d408c8b407f95cc5513e60aaa7efd07749c6246ad48d81e4543f8e"
    }
  }.freeze
  HPE_EXTERNAL_EFFECTS = TIK_EXTERNAL_EFFECTS
  HPE_REVIEW_ROLES = TIK_REVIEW_ROLES
  HPE_FINDING_CATEGORIES = TIK_FINDING_CATEGORIES
  HPE_LIFECYCLE_STATES = {
    "FOUNDATION_STAGE_ELIGIBLE" => "P3_HPE_FOUNDATION_STAGE_ELIGIBLE",
    "FOUNDATION_TASK_ACTIVE" => "P3_HPE_FOUNDATION_TASK_ACTIVE",
    "PRODUCT_STAGE_ELIGIBLE" => "P3_HPE_PRODUCT_STAGE_ELIGIBLE",
    "PRODUCT_TASK_ACTIVE" => "P3_HPE_PRODUCT_TASK_ACTIVE",
    "AUDIT_STAGE_ELIGIBLE" => "P3_HPE_AUDIT_STAGE_ELIGIBLE",
    "AUDIT_TASK_ACTIVE" => "P3_HPE_AUDIT_TASK_ACTIVE",
    "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
      "P3_HPE_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
    "ROUTE_TERMINAL_NON_PASS" => "P3_HPE_ROUTE_TERMINAL_NON_PASS"
  }.freeze
  HPE_LIFECYCLE_SPECS = {
    "FOUNDATION_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE_FOUNDATION_STAGE_ELIGIBLE",
      "stage_statuses" => %w[ELIGIBLE_NOT_ACTIVATED LOCKED_FOUNDATION_NOT_ACCEPTED LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => nil, "completed_stages" => 0, "delivery" => 25,
      "strict_exit" => 0,
      "next_action" => "ACTIVATE_P3_HPE_F1_HOST_PROCESS_CONFINEMENT_COMPATIBILITY_FOUNDATION",
      "task_creation_allowed" => true, "founder_gate" => false
    },
    "FOUNDATION_TASK_ACTIVE" => {
      "route_status" => "ACTIVE_FOUNDATION_TASK",
      "stage_statuses" => %w[ACTIVE LOCKED_FOUNDATION_NOT_ACCEPTED LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => 0, "completed_stages" => 0, "delivery" => 25,
      "strict_exit" => 0,
      "next_action" => "EXECUTE_P3_HPE_F1_HOST_PROCESS_CONFINEMENT_COMPATIBILITY_FOUNDATION",
      "task_creation_allowed" => false, "founder_gate" => false
    },
    "PRODUCT_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE_PRODUCT_STAGE_ELIGIBLE",
      "stage_statuses" => %w[ACCEPTED ELIGIBLE_NOT_ACTIVATED LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => nil, "completed_stages" => 1, "delivery" => 50,
      "strict_exit" => 0,
      "next_action" => "ACTIVATE_P3_HPE_P1_DURABLE_HOST_INVOCATION_KERNEL_PRODUCT",
      "task_creation_allowed" => true, "founder_gate" => false
    },
    "PRODUCT_TASK_ACTIVE" => {
      "route_status" => "ACTIVE_PRODUCT_TASK",
      "stage_statuses" => %w[ACCEPTED ACTIVE LOCKED_PRODUCT_NOT_ACCEPTED],
      "active_stage" => 1, "completed_stages" => 1, "delivery" => 50,
      "strict_exit" => 0,
      "next_action" => "EXECUTE_P3_HPE_P1_DURABLE_HOST_INVOCATION_KERNEL_PRODUCT",
      "task_creation_allowed" => false, "founder_gate" => false
    },
    "AUDIT_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE_AUDIT_STAGE_ELIGIBLE",
      "stage_statuses" => %w[ACCEPTED ACCEPTED ELIGIBLE_NOT_ACTIVATED],
      "active_stage" => nil, "completed_stages" => 2, "delivery" => 75,
      "strict_exit" => 0,
      "next_action" => "ACTIVATE_P3_HPE_A1_ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT",
      "task_creation_allowed" => true, "founder_gate" => false
    },
    "AUDIT_TASK_ACTIVE" => {
      "route_status" => "ACTIVE_AUDIT_TASK",
      "stage_statuses" => %w[ACCEPTED ACCEPTED ACTIVE],
      "active_stage" => 2, "completed_stages" => 2, "delivery" => 75,
      "strict_exit" => 0,
      "next_action" => "EXECUTE_P3_HPE_A1_ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT",
      "task_creation_allowed" => false, "founder_gate" => false
    },
    "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" => {
      "route_status" => "COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
      "stage_statuses" => %w[ACCEPTED ACCEPTED ACCEPTED],
      "active_stage" => nil, "completed_stages" => 3, "delivery" => 100,
      "strict_exit" => 100,
      "next_action" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "task_creation_allowed" => false, "founder_gate" => true
    }
  }.freeze
  HOST_AUTHORIZED_DECISION_SCHEMA =
    "founder-p3-minimum-trust-host-authorized-transactional-boundary-objective-route-rebaseline/v1"
  HOST_AUTHORIZED_DECISION_ID =
    "AUTHORIZE_P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007_V1"
  HOST_AUTHORIZED_DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/decision/FOUNDER_P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007_V1.json",
    "byte_length" => 12_013,
    "sha256" => "96b18ed2c356ff41b52a1379d56991f02585ecb47c55b963da4de02db66a2d84"
  }.freeze
  HOST_AUTHORIZED_ACTIVATION_PARENT = {
    "branch" => "main",
    "commit" => "8e4fd7037bd72c6c80561079ddd82991aac0f37e",
    "tree" => "79c4e0dc0960e152b780fb0690fd4f7a15d7b3d9",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_860_604,
      "sha256" => "ffb8ad7ea3474d3592e90b417c2aa5696ad54f4e6d6042fecc7da5d3e3ef2e47"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "2.6",
      "byte_length" => 10_360,
      "sha256" => "bae35e3e0d9cc93e5ad94b42a661651b2684c3922711fc569a643a00ef07953b"
    }
  }.freeze
  HOST_AUTHORIZED_CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "2.7",
    "byte_length" => 11_364,
    "sha256" => "ee51ed9eeae32ee36d0490d0a270d0822e579ced686e0425b2f45379f17e83c9"
  }.freeze
  HOST_AUTHORIZED_OBJECTIVE =
    "Build and independently validate one host-authorized transactional Single-Agent workflow in which every Agent output is non-authoritative proposal data and can neither create authority nor directly supply an executable, handler, filesystem path, environment value, credential, network target, or unrestricted argument map. The trusted host alone derives each invocation from an immutable task/workflow specification, the accepted P3-001 checkpoint state, a compile-time closed action algebra, content-addressed host-custody handles, and positive state/resource/budget authorization; it durably records an invocation-local authorization decision and dispatch intent before any effect, executes only inside a disposable OS-enforced isolation boundary, and blocks checkpoint advancement until exactly one append-only terminal invocation trace has been durably accepted or crash-reconciled. A generic tool registry, dynamic grant, broker/interpreter, finite semantic denylist, best-effort post-effect audit, network/Provider/Secret/remote/production/public effect, or P4 entry is not permitted."
  HOST_AUTHORIZED_LIMITS = {
    "engineering_tasks" => 10,
    "engineering_hours" => 288,
    "calendar_days" => 72,
    "active_tasks" => 1,
    "task_branches" => 1,
    "task_worktrees" => 1,
    "active_candidates" => 1
  }.freeze
  HOST_AUTHORIZED_CONSUMED = {
    "engineering_tasks" => 7,
    "engineering_hours" => 224,
    "calendar_days" => 56
  }.freeze
  HOST_AUTHORIZED_REMAINING = {
    "engineering_tasks" => 3,
    "engineering_hours" => 64,
    "calendar_days" => 16
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_ACTIVATION_PARENT = {
    "branch" => "main",
    "commit" => "0a7d4c25111e468a531c2ff88731358bf4f3def4",
    "tree" => "b23ddd50c099e5ecdf69c110931cf015bb085e64",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_874_141,
      "sha256" => "34a97c2ce89f66dfab15edcc4a78ac7094c056e0cd0b1e50ce1b6fc994332302"
    }
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_TASK_ID =
    "AIOS-P3-HATB-F1_MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION"
  HOST_AUTHORIZED_FOUNDATION_CONTRACT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/contract/P3_HATB_F1_MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION_TASK_CONTRACT_V1.yaml",
    "byte_length" => 7089,
    "sha256" => "6efc2370cf812662de46d4cd4bf6c4c22e6b7c141d90554fca01417dc9aac3b1"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_AUTHORITY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/authority/P3_HATB_F1_PHASE_DELEGATED_TASK_AUTHORITY_V1.json",
    "byte_length" => 4989,
    "sha256" => "18ba0c5797452c477da5f35f71a4b7fbccc9827cbb3b07707c9bc623978ec38e"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_AUTHORIZATION_ID =
    "18ae6829-7d30-44e3-86cc-81d969bed1f6"
  HOST_AUTHORIZED_FOUNDATION_EXECUTION_NONCE =
    "75201f2d-66e0-48eb-b911-8eb9d62f57c1"
  HOST_AUTHORIZED_FOUNDATION_BRANCH =
    "codex/p3-hatb-f1-minimum-trust-foundation"
  HOST_AUTHORIZED_FOUNDATION_WORKTREE =
    "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-hatb-f1-minimum-trust-foundation"
  HOST_AUTHORIZED_FOUNDATION_EVIDENCE_ROOT =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation"
  HOST_AUTHORIZED_FOUNDATION_ALLOWLIST = [
    "backend-spring/src/test/java/com/sourcelens/module/execution/trustboundary/foundation",
    "backend-spring/src/test/resources/p3-host-authorized-transactional-foundation"
  ].freeze
  HOST_AUTHORIZED_FOUNDATION_BUDGET = {
    "engineering_tasks" => 1,
    "engineering_hours" => 16,
    "calendar_days" => 4,
    "candidate_generations" => 2,
    "same_task_repairs" => 1,
    "review_cycles" => 2
  }.freeze
  HOST_AUTHORIZED_PRIOR_LEDGER = {
    "ref" => "historical_p3_final_transactional_route_hold_phase_execution_envelope.task_ledger",
    "entry_count" => 7,
    "canonicalization" => "RECURSIVE_KEY_SORT_COMPACT_JSON_UTF8",
    "canonical_byte_length" => 10_678,
    "canonical_sha256" => "960671374bb73de0a941a1df787e8e22b59834337699f157f0d97029c9e751dc"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE = {
    "commit" => "624b1fc13c4e3ebbd34fbe6f9959fc3cb773ee51",
    "tree" => "a57aa9a96b5bcb3a4a54f8224facdf05680fd3be",
    "integrated" => false
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_CANDIDATE_2_MANIFEST = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/candidate/P3_HATB_F1_CANDIDATE_2_REVIEW_MANIFEST_V1.json",
    "byte_length" => 10_216,
    "sha256" => "4a56556934c33b20563dae2f23a5d5d8e7b369a5b5772db8ae75562c647c38aa"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_FROZEN_FINDING_SET = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/reviews/P3_HATB_F1_CYCLE_1_FROZEN_FINDING_SET_V1.json",
    "byte_length" => 2340,
    "sha256" => "b24fc1a2dcc93da21d0e4ac65d760e18d6eb72af27c66196a24a27d13087b365"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_MANIFEST_FALSE_FINDING_SET_SHA256 =
    "b24fc1a219bcf5864ff9648b8423da148a6f35a3047731bda1c4edb07b70d233"
  HOST_AUTHORIZED_FOUNDATION_CYCLE_2_REVIEWS = [
    {
      "reviewer_role" => "CTO_AGENT", "verdict" => "NON_PASS",
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/reviews/P3_HATB_F1_CTO_CYCLE_2_FINAL_NON_PASS_REVIEW_V1.json",
      "byte_length" => 2488,
      "sha256" => "e3431ad6f4e46cbf60947a5ebb52ab7b3cdd318b009846b0c83b3544e4d5a91f"
    },
    {
      "reviewer_role" => "SECURITY_AGENT", "verdict" => "NON_PASS",
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/reviews/P3_HATB_F1_SECURITY_CYCLE_2_FINAL_NON_PASS_REVIEW_V1.json",
      "byte_length" => 3955,
      "sha256" => "51e22ba5939b70d74b38c6991d146c64df0155714e45c4f0d828aa8a179ebb87"
    },
    {
      "reviewer_role" => "QUALITY_EVALUATION_AGENT", "verdict" => "NON_PASS",
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/reviews/P3_HATB_F1_QUALITY_EVALUATION_CYCLE_2_FINAL_NON_PASS_REVIEW_V1.json",
      "byte_length" => 2933,
      "sha256" => "84de9ed73c7ac43f9df799ca78ccbbee35111f745a82beefff3770b4bf961b7b"
    }
  ].freeze
  HOST_AUTHORIZED_FOUNDATION_FOCUSED_EVIDENCE = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/tests/P3_HATB_F1_CANDIDATE_2_FOCUSED_SUREFIRE_REPORTS_V1.tar",
    "byte_length" => 125_952,
    "sha256" => "7cabdd0ceac5ed4b0bbec150ae67d94a38a327f238df3fdcc5008055d7bd3381"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_FULL_EVIDENCE = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/tests/P3_HATB_F1_CANDIDATE_2_FULL_SUREFIRE_REPORTS_V1.tar",
    "byte_length" => 4_056_064,
    "sha256" => "475ae14e7e599055ee5bce29a5176aabd4c67a403a6e92bb6933da77a96bc6b3"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_TERMINAL_BUNDLE = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/terminal/P3_HATB_F1_CANDIDATE_2_UNINTEGRATED_GIT_BUNDLE_V1.bundle",
    "byte_length" => 10_615_471,
    "sha256" => "7248a1cde52b3bf9b5a61b3f4631ea7dce09c71c64c3679e299a4ecb9e998e98"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_CLEANUP_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/terminal/P3_HATB_F1_TASK_WORKTREE_BRANCH_CLEANUP_RECEIPT_V1.json",
    "byte_length" => 2174,
    "sha256" => "e530b6d7dcf03f64785eec98e5e492f319fcd4177dded8d5b29ff6d57249ff5e"
  }.freeze
  HOST_AUTHORIZED_FOUNDATION_TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/task-foundation/terminal/P3_HATB_F1_TERMINAL_FOUNDATION_TASK_GATE_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 9883,
    "sha256" => "bbbb76ad9a3a5ff81d02103771540a29135e39c10e8187b3cb123f9508d80756"
  }.freeze
  PREACTIVATION_COMMIT = "87637233f847d6fb666419b63bef70990056e58f"
  PREACTIVATION_TREE = "e96dcae00a9da63cb327381fd25c40f9b384f7e0"
  FINAL_CANDIDATE = {
    "commit" => "8679ed31f9cee2612c34ee3be744ba3e43cfa747",
    "tree" => "fcbe9038ca1d2d60735b46597db80863003eab71",
    "integrated" => false
  }.freeze
  REPAIR_MANIFEST = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007/repair/candidate-2/P3_007_REPAIR_CANDIDATE_2_REVIEW_MANIFEST_V1.json",
    "byte_length" => 36_195,
    "sha256" => "08cc965ca10df27e70bccab2a74440503c6e4261ff7ebb10b7f2306151903589"
  }.freeze
  TERMINAL_RECEIPT = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007/terminal/P3_007_TERMINAL_FINAL_TRANSACTIONAL_PRODUCT_TASK_GATE_NON_PASS_RECEIPT_V1.json",
    "byte_length" => 7849,
    "sha256" => "7ba2ef033ca2ff3033d02c20c818d6c9754bb2d49aea467904c28de35e0c0bd9"
  }.freeze
  TERMINAL_BUNDLE = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007/terminal/P3_007_REJECTED_CANDIDATE_COMMITS_V1.bundle",
    "byte_length" => 36_317,
    "sha256" => "a7f93e1a1dea722b9362c5f0b2a3347c67f0a8fa8498991f5b2422b5a666b369"
  }.freeze
  CYCLE_2_REVIEWS = [
    {
      "role" => "CTO_AGENT", "verdict" => "PASS",
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007/review/cycle-2/P3_007_CTO_CYCLE_2_PASS_REVIEW_V1.json",
      "byte_length" => 3549,
      "sha256" => "6e78243459debe76c4b543a4ee35427689f8e4c15371f2de13d1ba631b8e4025"
    },
    {
      "role" => "SECURITY_AGENT", "verdict" => "NON_PASS",
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007/review/cycle-2/P3_007_SECURITY_CYCLE_2_NON_PASS_REVIEW_V1.json",
      "byte_length" => 4996,
      "sha256" => "069bd6b8937a40cacdb274da6131930b6ad1824da8f942826ab5567dd84fcf38"
    },
    {
      "role" => "QUALITY_EVALUATION_AGENT", "verdict" => "PASS",
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-final-transactional-host-workflow-20260820/task-p3-007/review/cycle-2/P3_007_QUALITY_EVALUATION_CYCLE_2_PASS_REVIEW_V1.json",
      "byte_length" => 4030,
      "sha256" => "0d7811ebf82590a5ac3574c4c13fc979f2b4a603538a4dd0868c6d14c2429825"
    }
  ].freeze
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

  TXC_ROUTE_SCHEMA = "p3-txc-control-recovery-direct-product-route/v1"
  TXC_ROUTE_ID = "P3_TXC_CONTROL_RECOVERY_DIRECT_PRODUCT_REENTRY_ROUTE_V1"
  TXC_DECISION_SCHEMA = "founder-p3-txc-control-plane-recovery-direct-product-reentry/v1"
  TXC_DECISION_ID =
    "AUTHORIZE_P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY_AFTER_POSTINSTALL_PROTOCOL_ERROR_V1"
  TXC_OPERATION_TYPE =
    "P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY_AFTER_POSTINSTALL_PROTOCOL_ERROR"
  TXC_DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-txc-control-recovery-20260822/decision/FOUNDER_P3_TXCR_CONTROL_RECOVERY_ACCEPTED_STRUCTURED_DECISION_V1.json",
    "byte_length" => 22_892,
    "sha256" => "d804694d69119c67ce0421c5dadac894db956a032599e800cc53590615536184"
  }.freeze
  TXC_AUTHORIZATION_BODY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-txc-control-recovery-20260822/decision/FOUNDER_AUTHORIZATION_BODY_V1.txt",
    "byte_length" => 18_433,
    "sha256" => "769ff349511f275f4bb2f1647f2bf224864658181002c24c6ab944ab21b5eee4"
  }.freeze
  TXC_POLICY = {
    "path" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
    "version" => "1.8",
    "sha256" => "12126e9617011b6395f187939c9a1d7860d84bd3832c1b1b67357fb017e1ee29"
  }.freeze
  TXC_CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "3.0",
    "byte_length" => 14_949,
    "sha256" => "12f9d9bbcf708002f9221eb6051b2da7d302197518151634ca2f7c0cc903c56c"
  }.freeze
  TXC_STRICT_GATE_ID =
    "HOST_AUTHORIZED_DURABLE_TRANSACTIONAL_INVOCATION_WITH_EXTERNAL_ISOLATION_ATTESTATION"
  TXC_STRICT_ITEMS = %w[
    AUTHORIZATION_AND_INTENT_DURABILITY
    CRASH_ORPHAN_RECONCILIATION_AND_RESUME
    EXACTLY_ONE_TERMINAL_TRACE_AND_CHECKPOINT_GATE
    PINNED_EXTERNAL_ISOLATION_ATTESTATION
  ].freeze
  TXC_COMPATIBILITY_ITEM = "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"
  TXC_READY_ACTION = "MASTER_ACTIVATE_P3_TXCR_PRODUCT_TASK"
  TXC_LIFECYCLE_STATES = {
    "PRODUCT_STAGE_ELIGIBLE" => "P3_TXC_PRODUCT_STAGE_ELIGIBLE",
    "PRODUCT_TASK_ACTIVE" => "P3_TXC_PRODUCT_TASK_ACTIVE",
    "AUDIT_STAGE_ELIGIBLE" => "P3_TXC_AUDIT_STAGE_ELIGIBLE",
    "AUDIT_TASK_ACTIVE" => "P3_TXC_AUDIT_TASK_ACTIVE",
    "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
      "P3_TXC_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
    "ROUTE_TERMINAL_NON_PASS" => "P3_TXC_ROUTE_TERMINAL_NON_PASS"
  }.freeze
  TXC_LIFECYCLE_SPECS = {
    "PRODUCT_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE",
      "execution_status" => "READY_PRODUCT_TASK_ACTIVATION",
      "scheduling_status" => "MASTER_PHASE_DELEGATED_CONTINUATION",
      "stage_statuses" => ["ELIGIBLE_NOT_ACTIVATED", "LOCKED_PREDECESSOR_NOT_ACCEPTED"],
      "current_task_ordinal" => nil,
      "delivery_percent" => 25,
      "strict_exit_percent" => 0,
      "accepted_stages" => 0,
      "next_action" => TXC_READY_ACTION,
      "founder_decision_required" => false,
      "next_action_owner" => "MASTER_CEO_AGENT"
    },
    "PRODUCT_TASK_ACTIVE" => {
      "route_status" => "ACTIVE",
      "execution_status" => "PRODUCT_TASK_ACTIVE",
      "scheduling_status" => "TASK_ENVELOPE_EXECUTION",
      "stage_statuses" => ["ACTIVE", "LOCKED_PREDECESSOR_NOT_ACCEPTED"],
      "current_task_ordinal" => 1,
      "delivery_percent" => 25,
      "strict_exit_percent" => 0,
      "accepted_stages" => 0,
      "next_action" => "EXECUTE_P3_TXCR_PRODUCT_TASK",
      "founder_decision_required" => false,
      "next_action_owner" => "MASTER_CEO_AGENT"
    },
    "AUDIT_STAGE_ELIGIBLE" => {
      "route_status" => "ACTIVE",
      "execution_status" => "READY_AUDIT_TASK_ACTIVATION",
      "scheduling_status" => "MASTER_PHASE_DELEGATED_CONTINUATION",
      "stage_statuses" => ["ACCEPTED_INTEGRATED", "ELIGIBLE_NOT_ACTIVATED"],
      "current_task_ordinal" => nil,
      "delivery_percent" => 75,
      "strict_exit_percent" => 0,
      "accepted_stages" => 1,
      "next_action" => "MASTER_ACTIVATE_P3_TXCR_ONE_SHOT_AUDIT_TASK",
      "founder_decision_required" => false,
      "next_action_owner" => "MASTER_CEO_AGENT"
    },
    "AUDIT_TASK_ACTIVE" => {
      "route_status" => "ACTIVE",
      "execution_status" => "AUDIT_TASK_ACTIVE",
      "scheduling_status" => "ONE_SHOT_AUDIT_EXECUTION",
      "stage_statuses" => ["ACCEPTED_INTEGRATED", "ACTIVE"],
      "current_task_ordinal" => 2,
      "delivery_percent" => 75,
      "strict_exit_percent" => 0,
      "accepted_stages" => 1,
      "next_action" => "EXECUTE_P3_TXCR_ONE_SHOT_AUDIT",
      "founder_decision_required" => false,
      "next_action_owner" => "MASTER_CEO_AGENT"
    },
    "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" => {
      "route_status" => "COMPLETE",
      "execution_status" => "COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
      "scheduling_status" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
      "stage_statuses" => ["ACCEPTED_INTEGRATED", "ACCEPTED_INTEGRATED"],
      "current_task_ordinal" => nil,
      "delivery_percent" => 100,
      "strict_exit_percent" => 100,
      "accepted_stages" => 2,
      "next_action" => "FOUNDER_P3_PHASE_GATE_DECISION",
      "founder_decision_required" => true,
      "next_action_owner" => "HUMAN_FOUNDER"
    },
    "ROUTE_TERMINAL_NON_PASS" => {
      "route_status" => "HOLD_INCOMPLETE_ROUTE_TERMINAL_NON_PASS",
      "execution_status" => "ROUTE_TERMINAL_NON_PASS",
      "scheduling_status" => "FOUNDER_STRATEGIC_DECISION_REQUIRED",
      "current_task_ordinal" => nil,
      "delivery_percent" => nil,
      "strict_exit_percent" => nil,
      "accepted_stages" => nil,
      "next_action" => "FOUNDER_DECIDE_P3_AFTER_TXC_ROUTE_TERMINAL_NON_PASS",
      "founder_decision_required" => true,
      "next_action_owner" => "HUMAN_FOUNDER"
    }
  }.freeze
  TXC_CURRENT_FALSE_EFFECTS = {
    "docker" => false,
    "network" => false,
    "dns" => false,
    "af_inet" => false,
    "af_inet6" => false,
    "provider" => false,
    "secret" => false,
    "credential" => false,
    "remote" => false,
    "production" => false,
    "public" => false,
    "dependency_download" => false,
    "existing_database_mutation" => false,
    "write_outside_exact_authorized_roots" => false,
    "irreversible_asset_deletion" => false
  }.freeze
  TXC_TASK_FALSE_EFFECTS = {
    "docker" => false,
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false,
    "existing_database_mutation" => false,
    "write_outside_exact_authorized_roots" => false,
    "irreversible_asset_deletion" => false
  }.freeze
  TXC_ENVELOPE_FALSE_EFFECTS = {
    "docker" => false,
    "network" => false,
    "provider" => false,
    "secret" => false,
    "remote" => false,
    "production" => false,
    "public" => false,
    "p4_entry" => false
  }.freeze
  TXC_IMMUTABLE_AUTHORITY_PATHS = %w[
    AGENTS.md
    docs/aios/STRATEGIC_CONSTITUTION.md
    docs/aios/MASTER_EXECUTION_PROTOCOL.md
    docs/aios/FOUNDER_DELEGATION_POLICY.md
    docs/aios/EVALUATION_PROTOCOL.md
  ].freeze
  TXC_REVIEWERS = %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT].freeze
  TXC_DEFERRED_CAPABILITIES = %w[P4_ENTRY PROVIDER SECRET REMOTE PRODUCTION PUBLIC].freeze
  TXC_STAGING_ALLOWED_VALIDATORS = %w[
    scripts/validate-founder-action-handoff.rb
    scripts/validate-founder-delegation-continuity.rb
    scripts/validate-current-task-authority.rb
    scripts/validate-p3-final-transactional-route.rb
    scripts/test-p3-final-transactional-route.rb
    scripts/validate-aios-governance.sh
  ].freeze
  TXC_STAGE0_EVIDENCE_ROOT =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-txc-control-recovery-20260822/stage0"
  TXC_INSTALLED_MANIFEST_PATHS = [1, 2].map do |generation|
    "#{TXC_STAGE0_EVIDENCE_ROOT}/P3_TXCR_ATOMIC_STAGING_MANIFEST_GENERATION_#{generation}_V1.json"
  end.freeze
  TXCR_STAGING_ROOT_RECORD = {
    "path" => "#{TXC_STAGE0_EVIDENCE_ROOT}/P3_TXCR_STAGE0_STAGING_ROOT_RECORD_V1.json",
    "byte_length" => 683,
    "sha256" => "b38834184394072f5c68e3bac0008653f6ad16130eb94be358bb945333b48acb"
  }.freeze
  TXCR_RECOVERY_BASELINE = {
    "repository" => "/Users/lijunpeng/Developer/SourceLens-AIOS",
    "branch" => "main",
    "commit" => "e23f48a3a4e68453d81c41dc774940a52378534f",
    "tree" => "de999ff5fa6e16b78573a6ff805da2af18b7f748",
    "parent_install_commit" => "1804f04c34b3ef264ab994926405519a05f85f02",
    "install_tree" => "592691e3703640d9535d3a891a6a53ab9c1442b2",
    "install_parent_commit" => "84a5bc600aafcb396c81598959d54cc5a32a0bcd",
    "install_parent_tree" => "de999ff5fa6e16b78573a6ff805da2af18b7f748",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_928_850,
      "sha256" => "0ffe94417d134fca97197232f27f856e6f0949b7bf8d09626b67dc185cb59e58"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "byte_length" => 11_788,
      "sha256" => "6ca11702c8b364f6e241b16912185868ca160eeaf1d158786f20d5682bb37cd1"
    }
  }.freeze
  TXCR_HISTORICAL_TERMINAL_IDENTITIES = {
    "hpe_terminal_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-process-enforced-minimal-slice-20260821/task-foundation/terminal/P3_HPE_F1_TERMINAL_TASK_GATE_NON_PASS_RECEIPT_V1.json",
      "byte_length" => 4_982,
      "sha256" => "faf7973733cae1b544128de6e650daa19274e13046ed64c8df752a3dea622dea"
    },
    "oci_stage0_terminal_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-pinned-oci-transactional-worker-20260821/P3_OCI_STAGE0_TERMINAL_NON_PASS_RECEIPT_V1.json",
      "byte_length" => 5_313,
      "sha256" => "77816a22044f2d2e8a7fc8c86d7195d8a38c281218ec5013f57ab663a91e9837"
    },
    "oci_recovery_terminal_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-pinned-oci-transactional-worker-20260821/P3_OCI_STAGE0_RECOVERY_TERMINAL_NON_PASS_RECEIPT_V1.json",
      "byte_length" => 5_086,
      "sha256" => "0b793db8584032e0432102f94ef97b54ae8f22cf4b9f541781123cfe52ea30e1"
    },
    "prior_txc_stage0_terminal_receipt" => {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-transactional-coordinator-external-oci-20260822/stage0/P3_TXC_ATOMIC_STAGE0_POST_INSTALL_TERMINAL_NON_PASS_RECEIPT_V1.json",
      "byte_length" => 5_885,
      "sha256" => "4b3f2fed918396200ce0bab0d76f49a9604feb86ea74392aa86d554d2228ddb0"
    }
  }.freeze

  THTCB_ROUTE_SCHEMA = "p3-trusted-host-tcb-clean-room-final-route/v1"
  THTCB_ROUTE_ID = "P3_TRUSTED_HOST_TCB_CLEAN_ROOM_FINAL_ROUTE_V1"
  THTCB_STATE = "P3_THTCB_PRODUCT_ELIGIBLE"
  THTCB_ACTION = "MASTER_ACTIVATE_AIOS_P3_THTCB_P1_PRODUCT"
  THTCB_PRODUCT_ACTIVE_STATE = "P3_THTCB_PRODUCT_TASK_ACTIVE"
  THTCB_PRODUCT_ACTIVE_ACTION = "EXECUTE_AIOS_P3_THTCB_P1_PRODUCT"
  THTCB_LIFECYCLE_STATES = {
    "PRODUCT_ELIGIBLE_NOT_ACTIVATED" => THTCB_STATE,
    "PRODUCT_TASK_ACTIVE" => THTCB_PRODUCT_ACTIVE_STATE
  }.freeze
  THTCB_DECISION_SCHEMA = "p3-trusted-host-tcb-founder-decision/v1"
  THTCB_DECISION_ID =
    "AUTHORIZE_P3_TRUSTED_HOST_TCB_TRANSACTIONAL_EXECUTION_OBJECTIVE_EXIT_GATE_AND_CLEAN_ROOM_FINAL_ROUTE_V1"
  THTCB_OPERATION_TYPE =
    "P3_TRUSTED_HOST_TCB_TRANSACTIONAL_EXECUTION_OBJECTIVE_EXIT_GATE_AND_CLEAN_ROOM_FINAL_ROUTE"
  THTCB_DECISION = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-host-tcb-clean-room-20260822/decision/FOUNDER_P3_THTCB_ACCEPTED_STRUCTURED_DECISION_V1.json",
    "byte_length" => 14_404,
    "sha256" => "e7fc49d6022294423525fd2d764c0658045045197ac114a4327c07b34f743fb6"
  }.freeze
  THTCB_AUTHORIZATION_BODY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-host-tcb-clean-room-20260822/decision/FOUNDER_AUTHORIZATION_BODY_V1.txt",
    "byte_length" => 19_057,
    "sha256" => "4427ba6c96a5fd6fba9822e516ec8fe4707573a75f7447da95b7d0fcbda1445d"
  }.freeze
  THTCB_CANONICAL_START = {
    "repository" => "/Users/lijunpeng/Developer/SourceLens-AIOS",
    "branch" => "main",
    "commit" => "f6a1c69dc28b399e0bc7562a9d591b6b11b953be",
    "tree" => "6326179fd4d879b4ba2f4e92ccc59f27144aad41",
    "truth" => {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_890_557,
      "sha256" => "8243e189ae3b0374a885ec1de5c2889de1b1eacdd92046a9d846add9cafcb96a"
    },
    "constitution" => {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "3.0",
      "byte_length" => 14_949,
      "sha256" => "12f9d9bbcf708002f9221eb6051b2da7d302197518151634ca2f7c0cc903c56c"
    }
  }.freeze
  THTCB_CONSTITUTION = {
    "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
    "version" => "3.1",
    "byte_length" => 16_879,
    "sha256" => "42483622fe6ff66eeb44ecc63139efef6d457a9b1cdad8d389e3f4f15e7065a4"
  }.freeze
  THTCB_STRICT_GATE_ID =
    "TRUSTED_HOST_TCB_DURABLE_TRANSACTIONAL_EXECUTION_WITH_PROCESS_REAL_CONTAINMENT"
  THTCB_STRICT_ITEMS = %w[
    AUTHORIZATION_AND_INTENT_DURABILITY
    CRASH_ORPHAN_RECONCILIATION_AND_RESUME
    EXACTLY_ONE_TERMINAL_TRACE_AND_CHECKPOINT_GATE
    TRUSTED_HOST_TCB_PROCESS_REAL_CONTAINMENT_ATTESTATION
  ].freeze
  THTCB_TCB = %w[
    LOCAL_OS_AND_KERNEL
    CURRENT_SOURCELENS_TRUSTED_HOST_PROCESS
    HOST_CONTROLLED_DURABLE_DATABASE
    SEALED_HOST_CUSTODY_ROOT
    EXACT_DOCKER_CLI_EXECUTABLE
    DOCKER_UNIX_SOCKET
    DOCKER_DESKTOP_DAEMON
    PINNED_LOCAL_OCI_IMAGE
  ].freeze
  THTCB_INCLUDED_THREATS = %w[
    ARBITRARY_AGENT_PROPOSAL
    HOSTILE_WORKFLOW_PAYLOAD
    DUPLICATE_OR_REPLAYED_PROPOSAL
    CRASH_TIMEOUT_PARTIAL_IO_AND_ORPHAN
    CONTAINER_NETWORK_FILESYSTEM_PERMISSION_AND_RESOURCE_ACQUISITION
    NON_TCB_PATH_OR_CONTENT_DRIFT
    FORGED_OR_INCONSISTENT_INVOCATION_CHECKPOINT_OR_TERMINAL_STATE
  ].freeze
  THTCB_EXCLUDED_THREATS = %w[
    ROOT_OR_ADMIN_ATTACKER
    SAME_USER_PROCESS_WITH_TCB_WRITE_AUTHORITY
    COMPETING_DOCKER_CLIENT_WITH_EQUIVALENT_DAEMON_AUTHORITY
    COMPROMISED_DOCKER_DAEMON_CLI_OR_SOCKET
    OS_KERNEL_COMPROMISE
    PHYSICAL_HOST_COMPROMISE
  ].freeze
  THTCB_INSTALLED_PROJECTION_SHA256 = {
    "current_phase_route" => "c18720f88a6604c42a260f69870994e2c9383e88ccbf0119d584b8fb81e9c677",
    "phase_execution_envelope" => "4586390a1facb494e1d5b73dc86033ffcc711142820c2db1ec70890ddc100117",
    "founder_escalation_control" => "74b523ddaa88ab7e957d409d757b0ebfc4ba909eb9f4a4d736cf49959233475a",
    "phase_delegation" => "673bd058777b640dcc0a27959ffddc6600a7ddf906f15e26e9c2210ad8974bb5",
    "phase_boundary" => "83aa2a3046d8c81c7c2f4d315c8ee367cebf5446e006243045ea6ab3bb16e64e",
    "active_work" => "797a250ec944796762e9f9c7f2c3e8fe90862cf3802afecdc75d6f1d7f0e7945",
    "phase_execution_claim" => "4a844d4dade9b2f9cef1942d1a4cc2b8f0ff97759bb27ae2d872fbcc04375d8e",
    "claim_boundary" => "3790a27a89859604383e3bcb30dace56f0e7246663a52306285e2ba99c37bec1",
    "project" => "1cabe3f7150412a8165c1cc2ab0a222e3b410b445e2936d913a60004215d4f69",
    "goal" => "f0c06b59befd79ea7ea4d9d54a15e05736bdd5f3d2646766d8eb574368d2071d",
    "strict_p3" => "2a8c19c8cc8f067b306820e5e426482986dea7e103d5b277d589d5fe412d1953"
  }.freeze
  THTCB_ACTIVE_PROJECTION_SHA256 = {
    "current_phase_route" => "dd05767daa135857de875e3740f463898f3ab708b6c27dca7821873480d5efc3",
    "phase_execution_envelope" => "f1e66dfe90c69c88b013833856bf0659baafd27bd3bb5d9c86dc6a2aa25c2f00",
    "founder_escalation_control" => "45cc578f4cd90ca56e0505070420a92e01ff82c83aaf417d428c5f8afa69f2fd",
    "phase_delegation" => "266248b61e2fe574fd280197232f9f09002f909f75fd0d0cb1bde609acba8746",
    "phase_boundary" => "c3d22015c4b6a91d118096950c5927cfa90cbeb0f71995f01275385be0a9965a",
    "active_work" => "1765858b1bb73c631fb5221a09860053dc387cc5c96faf46aab20bee5a2bb2b0",
    "phase_execution_claim" => "259c4d63b3ab5e4c759f3d7fd53ee662d2519f004af5d7af0d4dadd55110c351",
    "claim_boundary" => "23066f947178cecd642fe3436b56d94d3ae04388d82d3b009781dbdce736d5ca",
    "project" => "428743521610d1ede7280c38c3d4163d541d22504e2dc572db8904b29549f5d5",
    "goal" => "ab8ea1f9078fbb3ca6ec85cbda66526558a0247a5f90583a49983dbbdf1e50ba",
    "strict_p3" => "2a8c19c8cc8f067b306820e5e426482986dea7e103d5b277d589d5fe412d1953"
  }.freeze
  THTCB_PRODUCT_TASK_ID =
    "AIOS-P3-THTCB-P1_TRUSTED_HOST_TRANSACTIONAL_COORDINATOR_PRODUCT"
  THTCB_AUDIT_TASK_ID = "AIOS-P3-THTCB-A1_ONE_SHOT_STRICT_EXIT_AUDIT"
  THTCB_PRODUCT_CONTRACT = {
    "path" => "docs/aios/tasks/P3-THTCB-P1_TRUSTED_HOST_TRANSACTIONAL_COORDINATOR_PRODUCT.yaml",
    "byte_length" => 11_744,
    "sha256" => "a29b79209ff8add45eb8c357ca6b7cf1b55164104c484c0cb41b713bebaa977c"
  }.freeze
  THTCB_PRODUCT_AUTHORITY = {
    "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-host-tcb-clean-room-20260822/task-product/authority/P3_THTCB_P1_PHASE_DELEGATED_TASK_AUTHORITY_V1.json",
    "byte_length" => 7_978,
    "sha256" => "87d11c3fbbe4e7f5488ad5e043db80d264e68e72f1067cbf24b1db4ff7e0e7f4"
  }.freeze
  THTCB_PRODUCT_ACTIVATION_PARENT = {
    "commit" => "8da75bcb4c3c29667a3762854833103814fb192f",
    "tree" => "3c8c33f5d1c547de00e3a7f5e515238ff9d7b56c"
  }.freeze
  THTCB_PRODUCT_AUTHORIZATION_ID = "16c2425e-bc41-47d4-81e1-37c0d735a907"
  THTCB_PRODUCT_EXECUTION_NONCE = "b315aa7f-e39f-47b3-accc-489f812c3800"
  THTCB_PRODUCT_RESOURCES = {
    "branch" => "codex/p3-thtcb-p1-trusted-host-transactional-coordinator",
    "worktree" => "/Users/lijunpeng/Developer/.sourcelens-worktrees/p3-thtcb-p1-trusted-host-transactional-coordinator",
    "evidence_root" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-host-tcb-clean-room-20260822/task-product",
    "dependency_custody_root" => "/Users/lijunpeng/Developer/.sourcelens-custody/p3-thtcb-jre17"
  }.freeze
  THTCB_PRODUCT_BUDGET = {
    "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 10,
    "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
  }.freeze
  THTCB_AUDIT_BUDGET = {
    "engineering_tasks" => 1, "engineering_hours" => 16, "calendar_days" => 6,
    "formal_dispatches" => 1, "product_changes" => 0, "same_task_repairs" => 0,
    "rerun_to_pass_allowed" => false
  }.freeze
  THTCB_PRODUCT_WORKER_PATHS = [
    "backend-spring/src/main/java/com/sourcelens/module/execution/transactional",
    "backend-spring/src/main/resources/db/migration/V034__add_trusted_host_transactional_invocations.sql",
    "backend-spring/src/test/java/com/sourcelens/module/execution/transactional",
    "scripts/p3-thtcb-process-real-probe.sh"
  ].freeze
  THTCB_PRODUCT_MASTER_PATHS = [
    THTCB_PRODUCT_CONTRACT.fetch("path"),
    "docs/aios/truth/project_state.yaml",
    "scripts/validate-p3-final-transactional-route.rb",
    "scripts/test-p3-final-transactional-route.rb",
    "scripts/validate-founder-delegation-continuity.rb",
    "scripts/validate-current-task-authority.rb"
  ].freeze
  THTCB_HISTORICAL_PROJECTIONS = {
    "historical_p3_txc_control_recovery_route_terminal" => "current_phase_route",
    "historical_p3_txc_control_recovery_phase_execution_envelope" =>
      "phase_execution_envelope",
    "historical_p3_txc_control_recovery_founder_escalation_control" =>
      "founder_escalation_control",
    "historical_p3_txc_control_recovery_phase_delegation" => "phase_delegation",
    "historical_p3_txc_control_recovery_phase_boundary" => "phase_boundary",
    "historical_p3_txc_control_recovery_active_work" => "active_work",
    "historical_p3_txc_control_recovery_phase_execution_claim" => "phase_execution_claim"
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
    constitution = mapping(binding.fetch("governing_artifact"), "Strategic Constitution")
    constitution_bytes, constitution_stderr, constitution_status = Open3.capture3(
      "git", "show", "#{binding.fetch('commit')}:#{constitution.fetch('path')}", chdir: root.to_s
    )
    assert(constitution_status.success?,
           "bound Strategic Constitution unavailable: #{constitution_stderr.strip}")
    assert(constitution_bytes.bytesize == constitution.fetch("byte_length") &&
           Digest::SHA256.hexdigest(constitution_bytes) == constitution.fetch("sha256"),
           "bound Strategic Constitution identity drift")
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

  def load_preactivation_truth!(root)
    assert(git!(root, "rev-parse", "#{PREACTIVATION_COMMIT}^{tree}") == PREACTIVATION_TREE,
           "P3-007 preactivation Truth tree drift")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{PREACTIVATION_COMMIT}:docs/aios/truth/project_state.yaml",
      chdir: root.to_s
    )
    assert(status.success?, "P3-007 preactivation Truth unavailable: #{stderr.strip}")
    truth = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(truth.dig("current_phase_route", "lifecycle_stage") == "PRODUCT_TASK_ACTIVE" &&
           truth.dig("active_work", "current_task") == TASK_ID,
           "P3-007 preactivation Truth is not the exact active Task state")
    truth
  end

  def validate_terminal_evidence!(root)
    read_identity!(REPAIR_MANIFEST, "P3-007 repair manifest", create_once: true)
    review_receipts = CYCLE_2_REVIEWS.map do |review|
      identity = review.slice("path", "byte_length", "sha256")
      parsed = JSON.parse(read_identity!(identity, "P3-007 #{review.fetch('role')} cycle-2 review",
                                         create_once: true))
      assert(parsed["task_id"] == TASK_ID && parsed["review_cycle"] == 2 &&
             parsed["role"] == review.fetch("role") &&
             parsed["target_verdict"] == review.fetch("verdict") &&
             parsed.dig("candidate", "commit") == FINAL_CANDIDATE.fetch("commit") &&
             parsed.dig("candidate", "tree") == FINAL_CANDIDATE.fetch("tree") &&
             parsed.dig("safety", "write_executed") == false &&
             parsed.dig("safety", "network_executed") == false &&
             parsed.dig("safety", "forbidden_lineage_touched") == false,
             "P3-007 #{review.fetch('role')} cycle-2 review semantics drift")
      review.slice("role", "verdict").merge(identity).merge("mode" => "0444")
    end

    receipt = JSON.parse(read_identity!(TERMINAL_RECEIPT, "P3-007 terminal receipt",
                                        create_once: true))
    assert(receipt["schema"] == "p3-task-terminal-receipt/v1" &&
           receipt.dig("task", "task_id") == TASK_ID &&
           receipt.dig("task", "route_id") == ROUTE_ID &&
           receipt.dig("task", "slot_id") == TASK_SLOT_ID &&
           receipt.dig("task", "contract") == TASK_CONTRACT &&
           receipt.dig("task", "authority", "path") == TASK_AUTHORITY.fetch("path") &&
           receipt.dig("task", "authority", "byte_length") == TASK_AUTHORITY.fetch("byte_length") &&
           receipt.dig("task", "authority", "sha256") == TASK_AUTHORITY.fetch("sha256") &&
           receipt.dig("candidate", "final_commit") == FINAL_CANDIDATE.fetch("commit") &&
           receipt.dig("candidate", "final_tree") == FINAL_CANDIDATE.fetch("tree") &&
           receipt.dig("candidate", "integrated") == false &&
           receipt.dig("candidate", "manifest") == REPAIR_MANIFEST.merge("mode" => "0444") &&
           receipt["cycle_2_independent_reviews"] == review_receipts &&
           receipt.fetch("terminal_blockers").map { |finding| finding["finding_id"] } ==
             ["P1-SEC-001", "P1-SEC-002"] &&
           receipt.dig("terminal_result", "task_lifecycle") == "TERMINAL_TASK_GATE_NON_PASS" &&
           receipt.dig("terminal_result", "candidate_integration_allowed") == false &&
           receipt.dig("terminal_result", "strict_exit_audit_slot_unlocked") == false &&
           receipt.dig("terminal_result", "p3_delivery_progress_percent") == 25 &&
           receipt.dig("terminal_result", "p3_strict_exit_progress_percent") == 0 &&
           receipt.dig("terminal_result", "long_term_goal_lifecycle") == "ACTIVE" &&
           receipt.dig("no_auto_successor", "present") == true &&
           receipt.fetch("external_effects").values.all? { |value| value == false },
           "P3-007 terminal receipt semantics drift")

    read_identity!(TERMINAL_BUNDLE, "P3-007 rejected candidate bundle", create_once: true)
    bundle_heads, bundle_stderr, bundle_status = Open3.capture3(
      "git", "bundle", "list-heads", TERMINAL_BUNDLE.fetch("path"), chdir: root.to_s
    )
    assert(bundle_status.success?, "P3-007 terminal bundle invalid: #{bundle_stderr.strip}")
    assert(bundle_heads.lines.any? do |line|
      line.start_with?(FINAL_CANDIDATE.fetch("commit")) && line.include?(TASK_BRANCH)
    end, "P3-007 terminal bundle candidate ref drift")
    assert(git!(root, "diff", "--name-only", PREACTIVATION_COMMIT, "HEAD", "--", "backend-spring").empty?,
           "P3-007 rejected candidate product bytes entered canonical main")
    [receipt, review_receipts]
  rescue JSON::ParserError => e
    raise P3FinalTransactionalRouteValidationError, "P3-007 terminal Evidence invalid: #{e.message}"
  end

  def validate_terminal_task!(root, truth, decision, decision_identity, parent_truth, route)
    validate_task_inputs!(root)
    active_truth = load_preactivation_truth!(root)
    receipt, _review_receipts = validate_terminal_evidence!(root)
    review_verdicts = {
      "cto" => "PASS", "security" => "NON_PASS", "quality_evaluation" => "PASS"
    }
    terminal_task = {
      "task_id" => TASK_ID,
      "status" => "TERMINAL_TASK_GATE_NON_PASS",
      "slot_id" => TASK_SLOT_ID,
      "milestones" => MILESTONES.slice(1, 2),
      "candidate" => FINAL_CANDIDATE,
      "manifest" => REPAIR_MANIFEST,
      "independent_review_verdicts" => review_verdicts,
      "terminal_receipt" => TERMINAL_RECEIPT,
      "accepted" => false,
      "delivery_credit" => 0,
      "strict_exit_credit" => 0
    }
    slots = deep_copy(active_truth.dig("current_phase_route", "ordered_slots"))
    slots[0]["status"] = "TERMINAL_TASK_GATE_NON_PASS"
    slots[1]["status"] = "LOCKED_PRODUCT_SLOT_NON_PASS_NO_REPLACEMENT"
    expected_route = deep_copy(active_truth.fetch("current_phase_route"))
    expected_route["status"] = "TERMINAL_PRODUCT_SLOT_NON_PASS"
    expected_route["lifecycle_stage"] = "PRODUCT_TASK_TERMINAL_NON_PASS"
    expected_route["execution_status"] = "TERMINAL_PRODUCT_TASK_GATE_NON_PASS"
    expected_route["scheduling_status"] = "EVALUATION_SLOT_PERMANENTLY_LOCKED_NO_REPLACEMENT"
    expected_route["founder_phase_route_decision_required"] = true
    expected_route["next_eligible_action"] = TERMINAL_ACTION
    expected_route["ordered_slots"] = slots
    expected_route.delete("active_task")
    expected_route["terminal_task"] = terminal_task
    assert(route == expected_route, "P3-007 terminal Route projection drift")

    expected_envelope = deep_copy(active_truth.fetch("phase_execution_envelope"))
    expected_envelope["status"] = "HOLD_INCOMPLETE_FINAL_PRODUCT_SLOT_NON_PASS"
    terminal_ledger_entry = deep_copy(expected_envelope.fetch("task_ledger").last)
    terminal_ledger_entry["status"] = "TERMINAL_TASK_GATE_NON_PASS"
    terminal_ledger_entry["candidate"] = FINAL_CANDIDATE
    terminal_ledger_entry["candidate_manifest"] = REPAIR_MANIFEST
    terminal_ledger_entry["independent_review_verdicts"] = review_verdicts
    terminal_ledger_entry["terminal_receipt"] = TERMINAL_RECEIPT
    expected_envelope["task_ledger"][-1] = terminal_ledger_entry
    expected_envelope["reserved"] = {}
    expected_envelope["remaining_capacity_usable"] = false
    expected_envelope["remaining_capacity_lock_reason"] =
      "PRODUCT_SLOT_NON_PASS_EVALUATION_SLOT_PERMANENTLY_LOCKED_BY_EXACT_FOUNDER_ROUTE"
    expected_envelope["ordered_slots"] = slots
    assert(truth["phase_execution_envelope"] == expected_envelope,
           "P3-007 terminal Phase envelope drift")

    expected_project = deep_copy(active_truth.fetch("project"))
    expected_project["phase_execution_status"] = "HOLD_INCOMPLETE_FINAL_PRODUCT_SLOT_NON_PASS"
    expected_project["current_route_execution_status"] =
      "P3_FINAL_TRANSACTIONAL_HOST_WORKFLOW_ROUTE_TERMINAL_PRODUCT_SLOT_NON_PASS"
    expected_project["p3_execution_status"] =
      "HOLD_INCOMPLETE_FINAL_PRODUCT_SLOT_NON_PASS_EVALUATION_LOCKED"
    assert(truth["project"] == expected_project, "P3-007 terminal project projection drift")
    assert(truth.dig("strict_phase_gate_ledger", "phases", "P3") ==
             active_truth.dig("strict_phase_gate_ledger", "phases", "P3"),
           "P3-007 terminal state changed the strict P3 Exit Gate")

    expected_boundary = deep_copy(active_truth.fetch("phase_boundary"))
    expected_boundary["phase_execution_status"] = "HOLD_INCOMPLETE_FINAL_PRODUCT_SLOT_NON_PASS"
    expected_boundary["task_creation_scope"] = "NONE_ROUTE_TERMINAL_PRODUCT_SLOT_NON_PASS"
    expected_boundary["escalation_reason"] =
      "P3_STRATEGY_CHANGE_REQUIRED_AFTER_FINAL_PRODUCT_SLOT_NON_PASS_LOCKED_THE_ONLY_REMAINING_EVALUATION_SLOT"
    expected_boundary["user_action_required"] = "FOUNDER_STRATEGIC_DECISION"
    expected_boundary["phase_route_decision_required"] = true
    expected_boundary["phase_route_user_action_required"] = TERMINAL_ACTION
    expected_boundary["next_eligible_action"] = TERMINAL_ACTION
    assert(truth["phase_boundary"] == expected_boundary, "P3-007 terminal Phase boundary drift")

    expected_control = deep_copy(active_truth.fetch("founder_escalation_control"))
    expected_control["disposition"] = "FOUNDER_DECISION_REQUIRED"
    expected_control["source_event"] = {
      "kind" => "P3_FINAL_TRANSACTIONAL_PRODUCT_TASK_TERMINAL",
      "decision_id" => TASK_ID,
      "status" => "TERMINAL_TASK_GATE_NON_PASS_EVALUATION_SLOT_PERMANENTLY_LOCKED"
    }
    expected_control["reserved_trigger"] = {
      "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
      "evidence" => {
        "terminal_receipt" => TERMINAL_RECEIPT,
        "reason" => "CURRENT_EXACT_P3_ROUTE_HAS_NO_EXECUTABLE_SLOT_AFTER_FINAL_PRODUCT_SLOT_NON_PASS_AND_ANY_CONTINUATION_REQUIRES_A_FOUNDER_PHASE_STRATEGY_DECISION"
      }
    }
    expected_control["founder_decision_required"] = true
    expected_control["next_action_owner"] = "HUMAN_FOUNDER"
    expected_control["next_eligible_action"] = TERMINAL_ACTION
    assert(truth["founder_escalation_control"] == expected_control,
           "P3-007 terminal Founder escalation projection drift")

    expected_delegation = deep_copy(active_truth.fetch("phase_delegation"))
    expected_delegation["status"] = "HOLD_P3_FINAL_TRANSACTIONAL_ROUTE_TERMINAL"
    expected_delegation["claim_boundary"] =
      "P3-001 remains ACCEPTED; P3-002 through P3-007 remain immutable terminal accounting with no failed candidate integrated. P3-007 consumed the final product slot and is TERMINAL_TASK_GATE_NON_PASS after both candidate generations, the sole same-Task repair and the second independent review cycle. Neither product milestone is accepted, the evaluation-only strict Exit audit is permanently locked by the exact Founder route, and there is no product successor or replacement. P3 is HOLD_INCOMPLETE at delivery 25% and strict Exit 0%; P4 remains HOLD and the Long-term Goal remains ACTIVE."
    assert(truth["phase_delegation"] == expected_delegation,
           "P3-007 terminal Phase delegation drift")

    expected_active = deep_copy(active_truth.fetch("active_work"))
    preactivation = expected_active.delete("preactivation")
    expected_active["current_task"] = "NONE"
    expected_active["current_task_status"] = "NONE"
    expected_active["current_task_contract"] = nil
    expected_active["current_task_contract_sha256"] = nil
    expected_active["current_execution_authorization"] = nil
    expected_active["current_execution_authorization_sha256"] = nil
    expected_active["authority_record"] = nil
    expected_active["execution_nonce"] = nil
    expected_active["execution_nonce_status"] = "CONSUMED_TERMINAL_NON_PASS"
    expected_active["authorization_id"] = nil
    expected_active["task_resource_state"] = "NONE_ROUTE_TERMINAL_PRODUCT_SLOT_NON_PASS"
    expected_active["task_branch"] = nil
    expected_active["task_worktree"] = nil
    expected_active["execution_evidence_root"] = nil
    expected_active["dependency_custody_root"] = nil
    expected_active["allowlisted_paths"] = []
    expected_active["budget"] = TASK_BUDGET.transform_values { nil }
    expected_active["roles"] = {
      "owner" => "MASTER_CEO_AGENT", "worker" => nil, "quality_owner" => nil,
      "independent_reviewers" => []
    }
    expected_active["founder_decision_required"] = true
    expected_active["founder_decision_required_scope"] =
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
    expected_active["escalation_reason"] =
      "CURRENT_EXACT_P3_ROUTE_HAS_NO_EXECUTABLE_SLOT_AFTER_FINAL_PRODUCT_SLOT_NON_PASS"
    expected_active["user_action_required"] = "FOUNDER_STRATEGIC_DECISION"
    expected_active["phase_route_decision_required"] = true
    expected_active["phase_route_user_action_required"] = TERMINAL_ACTION
    expected_active["last_completed_task"] = {
      "task_id" => TASK_ID,
      "status" => "TERMINAL_TASK_GATE_NON_PASS",
      "candidate_commit" => FINAL_CANDIDATE.fetch("commit"),
      "candidate_tree" => FINAL_CANDIDATE.fetch("tree"),
      "candidate_integrated" => false,
      "product_source_writes" => 16,
      "independent_review_verdicts" => review_verdicts,
      "frozen_blocker_count" => 2,
      "terminal_receipt" => TERMINAL_RECEIPT
    }
    expected_active["last_task_preactivation"] = preactivation
    expected_active["next_eligible_action"] = TERMINAL_ACTION
    assert(truth["active_work"] == expected_active, "P3-007 terminal active-work drift")

    expected_execution = deep_copy(active_truth.fetch("phase_execution_claim"))
    expected_execution["current_task_claim"] = "NONE"
    expected_execution["real_engineering_progress"] =
      "P1_COMPLETE_P2_RESEARCH_EXIT_COMPLETE_CAPABILITY_NOT_ACCEPTED_P3_HOLD_INCOMPLETE_P3_007_TERMINAL_NON_PASS_PRODUCT_MILESTONES_NOT_ACCEPTED_P3_DELIVERY_25_P3_EXIT_GATE_ZERO"
    expected_execution["phase_local_allowed"] = []
    expected_execution["phase_local_frozen_capabilities"] = [
      "P3_006_TERMINAL_NON_PASS_CANDIDATE_UNINTEGRATED",
      "P3_007_TERMINAL_NON_PASS_CANDIDATE_UNINTEGRATED_PRODUCT_MILESTONES_NOT_ACCEPTED",
      "INDEPENDENT_P3_EXIT_GATE_AUDIT_PERMANENTLY_LOCKED_PRODUCT_SLOT_NON_PASS"
    ]
    expected_execution["remaining_capacity_usable"] = false
    expected_execution["next_eligible_action"] = TERMINAL_ACTION
    assert(truth["phase_execution_claim"] == expected_execution,
           "P3-007 terminal execution claim drift")

    expected_claim = deep_copy(active_truth.fetch("claim_boundary"))
    expected_claim["current_task"] = "NONE"
    expected_claim["selected_task"] = "NONE_ROUTE_TERMINAL_PRODUCT_SLOT_NON_PASS"
    expected_claim["current_task_status"] = "NONE"
    expected_claim["next_eligible_action"] = TERMINAL_ACTION
    expected_claim["real_engineering_progress"] = expected_execution["real_engineering_progress"]
    expected_claim["p3_status"] = "HOLD_INCOMPLETE_FINAL_PRODUCT_SLOT_NON_PASS_EVALUATION_LOCKED"
    expected_claim["p3_phase_envelope_status"] = "HOLD_INCOMPLETE_FINAL_PRODUCT_SLOT_NON_PASS"
    expected_claim["p3_capability_milestone_status"] =
      "FINAL_TRANSACTIONAL_HOST_WORKFLOW_PRODUCT_MILESTONES_NOT_ACCEPTED_P3_007_TERMINAL_NON_PASS"
    expected_claim["p3_007_status"] = "TERMINAL_TASK_GATE_NON_PASS"
    expected_claim["p3_007_candidate_commit"] = FINAL_CANDIDATE.fetch("commit")
    expected_claim["p3_007_candidate_tree"] = FINAL_CANDIDATE.fetch("tree")
    expected_claim["p3_007_candidate_integrated"] = false
    expected_claim["p3_007_review_verdicts"] = review_verdicts
    expected_claim["p3_007_terminal_blocker_count"] = 2
    expected_claim["p3_007_terminal_receipt_sha256"] = TERMINAL_RECEIPT.fetch("sha256")
    expected_claim["p3_007_delivery_credit"] = 0
    expected_claim["p3_007_strict_exit_credit"] = 0
    expected_claim["p3_007_evaluation_slot_unlocked"] = false
    assert(truth["claim_boundary"] == expected_claim, "P3-007 terminal claim boundary drift")

    goal = mapping(truth["goal"], "Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] == "NONE" &&
           goal.fetch("note").include?(TERMINAL_RECEIPT.fetch("sha256")),
           "P3-007 terminal state must preserve the active Long-term Goal")
    assert(truth["verification_scope"] ==
             "P3_007_TERMINAL_TASK_GATE_NON_PASS_PRODUCT_MILESTONES_NOT_ACCEPTED_EVALUATION_SLOT_PERMANENTLY_LOCKED_P3_HOLD_INCOMPLETE_DELIVERY_25_STRICT_EXIT_ZERO_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
           "P3-007 terminal verification scope drift")
    TERMINAL_STATE
  end

  def load_hold_activation_truth!(root)
    assert(git!(root, "rev-parse", "#{HOLD_ACTIVATION_PARENT.fetch('commit')}^{tree}") ==
             HOLD_ACTIVATION_PARENT.fetch("tree"),
           "P3 strategic HOLD activation-parent tree drift")
    bytes, stderr, status = Open3.capture3(
      "git", "show",
      "#{HOLD_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
      chdir: root.to_s
    )
    assert(status.success?, "P3 strategic HOLD activation Truth unavailable: #{stderr.strip}")
    truth = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert(truth.dig("current_phase_route", "lifecycle_stage") ==
             "PRODUCT_TASK_TERMINAL_NON_PASS" &&
           truth.dig("current_phase_route", "terminal_task", "terminal_receipt") == TERMINAL_RECEIPT,
           "P3 strategic HOLD activation Truth is not the exact P3-007 terminal state")
    truth
  end

  def validate_hold_decision!
    bytes = read_identity!(HOLD_DECISION, "P3 final transactional strategic HOLD decision",
                           create_once: true)
    hold = JSON.parse(bytes)
    assert(hold["schema_version"] == HOLD_DECISION_SCHEMA &&
           hold["record_type"] == "sourcelens_aios_founder_p3_phase_strategic_hold_decision" &&
           hold["decision_id"] == HOLD_DECISION_ID &&
           hold["authority"] == "HUMAN_FOUNDER" &&
           hold["source"] == "CURRENT_DIRECT_FOUNDER_REPLY_V1" &&
           hold["reserved_trigger"] == "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           hold["phase"] == "P3",
           "P3 strategic HOLD decision authority drift")
    assert(hold["canonical_start"] == {
      "commit" => HOLD_ACTIVATION_PARENT.fetch("commit"),
      "tree" => HOLD_ACTIVATION_PARENT.fetch("tree"),
      "branch" => "main",
      "main_clean" => true,
      "truth" => {
        "path" => "docs/aios/truth/project_state.yaml",
        "byte_length" => 1_860_281,
        "sha256" => "8a933a9f55522ab9adf764d96a02af2f39edf5144bd52902be1c6ce28a9d2e31"
      }
    }, "P3 strategic HOLD canonical binding drift")
    assert(hold["governing_artifact"] == {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "2.6",
      "byte_length" => 10_360,
      "sha256" => "bae35e3e0d9cc93e5ad94b42a661651b2684c3922711fc569a643a00ef07953b"
    } && hold["terminal_receipt"] == TERMINAL_RECEIPT,
           "P3 strategic HOLD governing identity drift")
    assert(hold.dig("decision", "disposition") ==
             "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED" &&
           hold.dig("decision", "p3_objective") ==
             "UNCHANGED_STRATEGIC_CONSTITUTION_V2_6" &&
           hold.dig("decision", "strict_exit_gate") ==
             "UNCHANGED_RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS" &&
           hold.dig("decision", "current_task") == "NONE" &&
           hold.dig("decision", "new_task_authorized") == false &&
           hold.dig("decision", "candidate_integration_authorized") == false &&
           hold.dig("decision", "evaluation_slot_unlock_authorized") == false &&
           hold.dig("decision", "p4_entry_authorized") == false &&
           hold.dig("decision", "engineering_action_eligible") == false,
           "P3 strategic HOLD decision boundary drift")
    assert(hold.dig("truth_boundary", "p3_001_durable_state_and_checkpoint_resume") ==
             "ACCEPTED" &&
           hold.dig("truth_boundary", "p3_002_through_p3_007_terminal_facts_preserved") ==
             true &&
           hold.dig("truth_boundary", "p3_007_candidate") == FINAL_CANDIDATE &&
           hold.dig("truth_boundary", "host_owned_fixed_workflow_structural_permission") ==
             "NOT_ACCEPTED" &&
           hold.dig("truth_boundary", "fixed_handler_resume_isolation_and_complete_trace") ==
             "NOT_ACCEPTED" &&
           hold.dig("truth_boundary", "p3_delivery_progress_percent") == 25 &&
           hold.dig("truth_boundary", "strict_p3_exit_progress_percent") == 0 &&
           hold.dig("truth_boundary", "evaluation_only_strict_exit_audit") ==
             "PERMANENTLY_LOCKED_PRODUCT_SLOT_NON_PASS",
           "P3 strategic HOLD truth boundary drift")
    assert(hold.dig("budget", "expansion") == {
      "engineering_tasks" => 0, "engineering_hours" => 0,
      "calendar_days" => 0, "external_capabilities" => 0
    } && hold.dig("budget", "consumed") == {
      "engineering_tasks" => 7, "engineering_hours" => 224, "calendar_days" => 56
    } && hold.dig("budget", "remaining_locked") == {
      "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8
    } && hold.dig("budget", "remaining_capacity_usable") == false &&
           hold.dig("budget", "remaining_capacity_resequencing_authorized") == false,
           "P3 strategic HOLD budget drift")
    assert(hold.fetch("external_effects").values.all? { |value| value == false } &&
           hold.dig("long_term_goal", "status") == "ACTIVE" &&
           hold.dig("long_term_goal", "termination_authorized") == false &&
           hold.dig("long_term_goal", "project_complete") == false &&
           hold.dig("long_term_goal", "codex_goal_action") == "NONE_KEEP_ACTIVE",
           "P3 strategic HOLD external or Goal boundary drift")
    hold
  rescue JSON::ParserError => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 strategic HOLD decision JSON invalid: #{e.message}"
  end

  def validate_strategic_hold!(root, truth, decision, decision_identity, parent_truth, route)
    terminal_truth = load_hold_activation_truth!(root)
    terminal_state = validate_terminal_task!(
      root, terminal_truth, decision, decision_identity, parent_truth,
      terminal_truth.fetch("current_phase_route")
    )
    assert(terminal_state == TERMINAL_STATE, "P3 strategic HOLD terminal parent is invalid")
    hold = validate_hold_decision!
    hold_projection = HOLD_DECISION.merge(
      "decision_id" => HOLD_DECISION_ID,
      "reserved_trigger" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
    )
    assert(git!(root, "diff", "--name-only", HOLD_ACTIVATION_PARENT.fetch("commit"),
                HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("commit"),
                "--", "backend-spring", "docs/aios/STRATEGIC_CONSTITUTION.md").empty?,
           "P3 strategic HOLD changed product source or the Constitution")

    expected_route = deep_copy(terminal_truth.fetch("current_phase_route"))
    expected_route["status"] = "FOUNDER_RESOLVED_STRATEGIC_HOLD"
    expected_route["lifecycle_stage"] = "FOUNDER_RESOLVED_STRATEGIC_HOLD"
    expected_route["execution_status"] = "NO_ENGINEERING_ACTION"
    expected_route["scheduling_status"] =
      "FOUNDER_RESOLVED_NO_ENGINEERING_ACTION_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD"
    expected_route["founder_phase_route_decision_required"] = false
    expected_route["next_eligible_action"] = HOLD_ACTION
    expected_route["founder_hold_decision"] = hold_projection
    assert(route == expected_route, "P3 strategic HOLD Route projection drift")

    expected_envelope = deep_copy(terminal_truth.fetch("phase_execution_envelope"))
    expected_envelope["status"] = "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
    expected_envelope["remaining_capacity_lock_reason"] =
      "FOUNDER_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_STRATEGIC_HOLD_NO_ENGINEERING_ACTION"
    assert(truth["phase_execution_envelope"] == expected_envelope,
           "P3 strategic HOLD Phase envelope drift")

    expected_project = deep_copy(terminal_truth.fetch("project"))
    expected_project["phase_execution_status"] =
      "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
    expected_project["current_route_execution_status"] =
      "FOUNDER_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_STRATEGIC_HOLD"
    expected_project["p3_execution_status"] =
      "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
    assert(truth["project"] == expected_project, "P3 strategic HOLD project projection drift")
    assert(truth.dig("strict_phase_gate_ledger", "phases", "P3") ==
             terminal_truth.dig("strict_phase_gate_ledger", "phases", "P3"),
           "P3 strategic HOLD changed the strict P3 Exit Gate")

    expected_boundary = deep_copy(terminal_truth.fetch("phase_boundary"))
    expected_boundary["phase_execution_status"] =
      "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
    expected_boundary["task_creation_scope"] =
      "NONE_FOUNDER_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_STRATEGIC_HOLD"
    expected_boundary["escalation_reason"] = nil
    expected_boundary["user_action_required"] = "NONE"
    expected_boundary["phase_route_decision_required"] = false
    expected_boundary["phase_route_user_action_required"] = "NONE"
    expected_boundary["next_eligible_action"] = HOLD_ACTION
    assert(truth["phase_boundary"] == expected_boundary,
           "P3 strategic HOLD Phase boundary drift")

    terminal_control = terminal_truth.fetch("founder_escalation_control")
    expected_control = {
      "schema_version" => "founder-escalation-control/v2",
      "disposition" => HOLD_DISPOSITION,
      "source_event" => {
        "kind" => "FOUNDER_P3_FINAL_TRANSACTIONAL_ROUTE_STRATEGIC_HOLD_DECISION",
        "decision_id" => HOLD_DECISION_ID,
        "status" => "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
      },
      "reserved_trigger" => {
        "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
        "evidence" => TERMINAL_RECEIPT
      },
      "resolved_strategy_decision" => hold_projection.merge(
        "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
        "result" => "P3_HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
      ),
      "resolved_phase_entry_decision" => terminal_control.fetch("resolved_phase_entry_decision"),
      "phase_gate_status" => "INCOMPLETE",
      "founder_decision_required" => false,
      "next_action_owner" => "NONE",
      "next_eligible_action" => HOLD_ACTION
    }
    assert(truth["founder_escalation_control"] == expected_control,
           "P3 strategic HOLD Founder control drift")

    expected_delegation = deep_copy(terminal_truth.fetch("phase_delegation"))
    expected_delegation["status"] =
      "HOLD_P3_PHASE_LEVEL_DELEGATION_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
    expected_delegation["decision_source"] = HOLD_DECISION_ID
    expected_delegation["claim_boundary"] =
      "The exact Founder P3 strategic HOLD decision keeps the Constitution v2.6 Objective and strict Exit Gate unchanged, preserves P3-001 as the sole accepted milestone and P3-002 through P3-007 as immutable terminal accounting, makes the remaining nominal Phase capacity unusable, authorizes no Task or candidate integration, keeps P4 HOLD and keeps the Long-term Goal ACTIVE."
    assert(truth["phase_delegation"] == expected_delegation,
           "P3 strategic HOLD Phase delegation drift")

    expected_active = deep_copy(terminal_truth.fetch("active_work"))
    expected_active["task_resource_state"] =
      "NO_ACTIVE_TASK_FOUNDER_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD"
    expected_active["founder_decision_required"] = false
    expected_active["founder_decision_required_scope"] = nil
    expected_active["escalation_reason"] = nil
    expected_active["user_action_required"] = "NONE"
    expected_active["phase_route_decision_required"] = false
    expected_active["phase_route_user_action_required"] = "NONE"
    expected_active["next_eligible_action"] = HOLD_ACTION
    assert(truth["active_work"] == expected_active,
           "P3 strategic HOLD active-work drift")

    expected_execution = deep_copy(terminal_truth.fetch("phase_execution_claim"))
    expected_execution["real_engineering_progress"] =
      "P1_COMPLETE_P2_RESEARCH_EXIT_COMPLETE_CAPABILITY_NOT_ACCEPTED_P3_FOUNDER_RESOLVED_STRATEGIC_HOLD_P3_007_TERMINAL_NON_PASS_PRODUCT_MILESTONES_NOT_ACCEPTED_P3_DELIVERY_25_P3_EXIT_GATE_ZERO"
    expected_execution["phase_local_frozen_capabilities"] =
      terminal_truth.dig("phase_execution_claim", "phase_local_frozen_capabilities") +
      ["FOUNDER_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_STRATEGIC_HOLD_NO_ENGINEERING_ACTION"]
    expected_execution["next_eligible_action"] = HOLD_ACTION
    assert(truth["phase_execution_claim"] == expected_execution,
           "P3 strategic HOLD execution claim drift")

    expected_claim = deep_copy(terminal_truth.fetch("claim_boundary"))
    expected_claim["selected_task"] =
      "NONE_FOUNDER_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD"
    expected_claim["next_eligible_action"] = HOLD_ACTION
    expected_claim["real_engineering_progress"] = expected_execution.fetch("real_engineering_progress")
    expected_claim["p3_status"] = "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
    expected_claim["p3_phase_envelope_status"] =
      "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED"
    expected_claim["p3_capability_milestone_status"] =
      "FINAL_TRANSACTIONAL_PRODUCT_MILESTONES_NOT_ACCEPTED_FOUNDER_RESOLVED_STRATEGIC_HOLD"
    assert(truth["claim_boundary"] == expected_claim,
           "P3 strategic HOLD claim boundary drift")

    goal = mapping(truth["goal"], "Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] == "NONE" &&
           goal.fetch("note").include?(HOLD_DECISION.fetch("sha256")),
           "P3 strategic HOLD must keep the Long-term Goal active")
    assert(truth["verification_scope"] ==
             "FOUNDER_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_STRATEGIC_HOLD_P3_007_TERMINAL_NON_PASS_PRODUCT_MILESTONES_NOT_ACCEPTED_P3_DELIVERY_25_STRICT_EXIT_ZERO_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
           "P3 strategic HOLD verification scope drift")
    assert(hold.dig("phase_lifecycle", "p3") ==
             "HOLD_INCOMPLETE_FINAL_TRANSACTIONAL_ROUTE_EXHAUSTED",
           "P3 strategic HOLD lifecycle drift")
    HOLD_STATE
  end

  def load_host_authorized_activation_truth!(root)
    assert(git!(root, "rev-parse", "#{HOST_AUTHORIZED_ACTIVATION_PARENT.fetch('commit')}^{tree}") ==
             HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("tree"),
           "P3 host-authorized activation-parent tree drift")
    bytes, stderr, status = Open3.capture3(
      "git", "show",
      "#{HOST_AUTHORIZED_ACTIVATION_PARENT.fetch('commit')}:#{HOST_AUTHORIZED_ACTIVATION_PARENT.dig('truth', 'path')}",
      chdir: root.to_s
    )
    assert(status.success?, "P3 host-authorized activation Truth unavailable: #{stderr.strip}")
    assert(bytes.bytesize == HOST_AUTHORIZED_ACTIVATION_PARENT.dig("truth", "byte_length") &&
           Digest::SHA256.hexdigest(bytes) ==
             HOST_AUTHORIZED_ACTIVATION_PARENT.dig("truth", "sha256"),
           "P3 host-authorized activation Truth identity drift")
    YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def validate_host_authorized_bound_identity!(record, label, create_once: false)
    mapping(record, label)
    identity = record.slice("path", "byte_length", "sha256")
    bytes = read_identity!(identity, label, create_once: create_once)
    if record.key?("mode")
      stat = Pathname.new(record.fetch("path")).lstat
      assert(record["mode"] == format("%04o", stat.mode & 0o7777) &&
             record["nlink"] == stat.nlink,
             "#{label} declared mode/link drift")
    end
    bytes
  end

  def validate_host_authorized_decision!(root)
    bytes = read_identity!(HOST_AUTHORIZED_DECISION,
                           "P3 host-authorized Founder decision", create_once: true)
    decision = JSON.parse(bytes)
    exact_keys(decision, %w[
      schema_version record_type decision_id authority source approved_at_utc source_reply
      canonical_start bound_predecessor_evidence reserved_triggers strategy_change p3_objective
      route phase_accounting lineage_boundary architecture_boundary installation external_effects
      anti_cycle lifecycle long_term_goal
    ], "P3 host-authorized Founder decision")
    assert(decision["schema_version"] == HOST_AUTHORIZED_DECISION_SCHEMA &&
           decision["record_type"] ==
             "sourcelens_aios_founder_p3_objective_and_route_rebaseline_decision" &&
           decision["decision_id"] == HOST_AUTHORIZED_DECISION_ID &&
           decision["authority"] == "HUMAN_FOUNDER" &&
           decision["source"] == "CURRENT_DIRECT_FOUNDER_REPLY_V1",
           "P3 host-authorized Founder authority drift")

    source = exact_keys(decision["source_reply"], %w[
      path raw_byte_length raw_sha256 canonicalization canonical_byte_length canonical_sha256
    ], "P3 host-authorized Founder source reply")
    source_path = Pathname.new(source.fetch("path"))
    source_stat = source_path.lstat
    assert(source_stat.file? && !source_path.symlink?,
           "P3 host-authorized Founder source reply must be a regular file")
    source_bytes = source_path.binread
    assert(source_bytes.bytesize == source.fetch("raw_byte_length") &&
           Digest::SHA256.hexdigest(source_bytes) == source.fetch("raw_sha256"),
           "P3 host-authorized Founder source reply raw identity drift")
    source_text = source_bytes.dup.force_encoding("UTF-8")
    assert(source_text.valid_encoding?, "P3 host-authorized Founder source reply encoding invalid")
    canonical_source = source_text.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    assert(source["canonicalization"] == "UTF8_LF_WITH_EXACTLY_ONE_TRAILING_LF" &&
           canonical_source.bytesize == source.fetch("canonical_byte_length") &&
           Digest::SHA256.hexdigest(canonical_source) == source.fetch("canonical_sha256") &&
           canonical_source.lines.first.chomp == HOST_AUTHORIZED_DECISION_ID,
           "P3 host-authorized Founder source reply canonical identity drift")

    assert(decision["canonical_start"] == {
      "branch" => HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("branch"),
      "commit" => HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("commit"),
      "tree" => HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("tree"),
      "main_clean" => true,
      "truth" => HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("truth"),
      "constitution" => HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("constitution")
    }, "P3 host-authorized canonical-start binding drift")
    assert(git!(root, "rev-parse", "#{HOST_AUTHORIZED_ACTIVATION_PARENT.fetch('commit')}^{tree}") ==
             HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("tree"),
           "P3 host-authorized canonical-start Git identity drift")

    evidence = exact_keys(decision["bound_predecessor_evidence"], %w[
      p3_strategic_hold_decision p3_strategic_hold_audit p3_007_terminal_receipt
      p3_001_accepted_receipt
    ], "P3 host-authorized predecessor Evidence")
    validate_host_authorized_bound_identity!(
      evidence.fetch("p3_strategic_hold_decision"), "P3 strategic HOLD decision", create_once: true
    )
    validate_host_authorized_bound_identity!(
      evidence.fetch("p3_strategic_hold_audit"), "P3 strategic HOLD audit", create_once: true
    )
    validate_host_authorized_bound_identity!(
      evidence.fetch("p3_007_terminal_receipt"), "P3-007 terminal receipt"
    )
    validate_host_authorized_bound_identity!(
      evidence.fetch("p3_001_accepted_receipt"), "P3-001 accepted receipt"
    )
    assert(decision["reserved_triggers"] == [
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
      "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
    ], "P3 host-authorized reserved-trigger set drift")

    strategy = mapping(decision["strategy_change"], "P3 host-authorized strategy change")
    assert(strategy == {
      "constitution_from" => "2.6",
      "constitution_to" => "2.7",
      "changed_clause" => "P3_OBJECTIVE_ONLY_PLUS_APPEND_ONLY_CHANGE_CONTROL_ADR",
      "mission_changed" => false,
      "icp_changed" => false,
      "year_one_outcome_changed" => false,
      "strict_phase_sequence_changed" => false,
      "strict_p3_exit_gate_changed" => false,
      "strict_p3_exit_gate" => "Resume, isolation, permission and trace tests",
      "p4_entry_authorized" => false
    }, "P3 host-authorized strategy boundary drift")
    assert(decision["p3_objective"] == HOST_AUTHORIZED_OBJECTIVE,
           "P3 host-authorized Objective drift")

    route = mapping(decision["route"], "P3 host-authorized route")
    stages = array(route["ordered_stages"], "P3 host-authorized ordered stages")
    assert(route["route_id"] == HOST_AUTHORIZED_ROUTE_ID &&
           route["status_after_installation"] == "ACTIVE_FOUNDATION_STAGE_ELIGIBLE" &&
           stages.length == 3 && stages.map { |stage| stage["ordinal"] } == [1, 2, 3] &&
           stages.map { |stage| stage["stage_id"] } == %w[
             MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION
             HOST_AUTHORIZED_TRANSACTIONAL_TRUST_BOUNDARY_PRODUCT
             INDEPENDENT_P3_STRICT_EXIT_AUDIT
           ] && stages.map { |stage| stage["kind"] } == %w[
             EVALUATION_FOUNDATION PRODUCT_IMPLEMENTATION EVALUATION_ONLY
           ] && stages.map { |stage| stage.dig("budget", "engineering_hours") } == [16, 32, 16] &&
           stages.map { |stage| stage.dig("budget", "calendar_days") } == [4, 8, 4] &&
           stages.all? { |stage| stage.dig("budget", "engineering_tasks") == 1 } &&
           stages[0]["product_source_mutation_allowed"] == false &&
           stages[1]["product_source_diff_required"] == "NON_EMPTY_TESTABLE" &&
           stages[2]["formal_dispatches"] == 1 &&
           stages[2]["rerun_to_pass_allowed"] == false,
           "P3 host-authorized ordered-stage boundary drift")

    accounting = mapping(decision["phase_accounting"], "P3 host-authorized accounting")
    assert(accounting["historical_limits"] == {
      "engineering_tasks" => 8, "engineering_hours" => 256, "calendar_days" => 64
    } && accounting["consumed_preserved"] == HOST_AUTHORIZED_CONSUMED &&
           accounting["historical_nominal_remaining_preserved"] == {
             "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8
           } && accounting["added_capacity"] == {
             "engineering_tasks" => 2, "engineering_hours" => 32, "calendar_days" => 8
           } && accounting["cumulative_ceiling"] == HOST_AUTHORIZED_LIMITS.slice(
             "engineering_tasks", "engineering_hours", "calendar_days"
           ) && accounting["new_route_capacity"] == HOST_AUTHORIZED_REMAINING &&
           accounting["budget_reset_allowed"] == false &&
           accounting["capacity_transfer_or_reordering_allowed"] == false,
           "P3 host-authorized non-resettable accounting drift")

    lineage = mapping(decision["lineage_boundary"], "P3 host-authorized lineage boundary")
    assert(lineage["p3_001_accepted_foundation"] ==
             "READ_ONLY_PUBLIC_BEHAVIOR_COMPOSITION_ALLOWED" &&
           lineage["p3_001_semantics_mutation_allowed"] == false &&
           lineage["p3_002_through_p3_007_terminal_facts_preserved"] == true &&
           lineage["p3_002_through_p3_007_branch_worktree_code_tests_evaluator_candidate_engineering_evidence_read_allowed"] == false &&
           lineage["p3_002_through_p3_007_compare_copy_execute_fix_reuse_or_cleanup_allowed"] == false,
           "P3 host-authorized lineage boundary drift")
    architecture = mapping(decision["architecture_boundary"],
                           "P3 host-authorized architecture boundary")
    %w[
      agent_output_authoritative generic_tool_registry_allowed dynamic_grant_allowed
      broker_or_interpreter_allowed finite_semantic_denylist_allowed
      best_effort_post_effect_audit_allowed plain_process_builder_fallback_allowed
    ].each { |key| assert(architecture[key] == false, "P3 forbidden architecture accepted: #{key}") }
    %w[
      compile_time_closed_action_algebra_required exhaustive_direct_dispatch_required
      host_positive_authorization_required
      host_resolves_executable_path_environment_and_resource_from_exact_id_or_hash
      pre_effect_durable_authorization_decision_required
      pre_effect_create_once_dispatch_intent_required disposable_os_enforced_isolation_required
      fail_closed_crash_reconciliation_required exactly_one_terminal_trace_per_invocation_required
      checkpoint_completion_after_terminal_trace_acceptance_only
    ].each { |key| assert(architecture[key] == true, "P3 required architecture missing: #{key}") }
    assert(decision.dig("installation", "engineering_progress_credit") == 0 &&
           decision.dig("installation", "delivery_progress_after_pass_percent") == 25 &&
           decision.dig("installation", "strict_exit_progress_after_pass_percent") == 0 &&
           decision.dig("installation", "task_creation_before_installation_pass_allowed") == false &&
           decision.dig("installation", "independent_read_only_installation_audit_required") == true &&
           decision.fetch("external_effects").values.all? { |value| value == false } &&
           decision.dig("anti_cycle", "second_product_implementation_task_authorized") == false &&
           decision.dig("anti_cycle", "successor_replacement_remediation_normalization_feasibility_authorized") == false &&
           decision.dig("anti_cycle", "p3_008_or_numbered_v2_v3_route_authorized") == false &&
           decision.dig("long_term_goal", "status") == "ACTIVE" &&
           decision.dig("long_term_goal", "parallel_goal_authorized") == false &&
           decision.dig("long_term_goal", "project_complete") == false &&
           decision.dig("long_term_goal", "goal_completion_or_termination_authorized") == false,
           "P3 host-authorized installation, anti-cycle, effect or Goal boundary drift")
    decision
  rescue JSON::ParserError, Psych::SyntaxError => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 host-authorized Founder decision invalid: #{e.message}"
  end

  def load_host_authorized_foundation_ready_truth!(root)
    parent = HOST_AUTHORIZED_FOUNDATION_ACTIVATION_PARENT
    assert(git!(root, "rev-parse", "#{parent.fetch('commit')}^{tree}") == parent.fetch("tree"),
           "P3 foundation activation-parent tree drift")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{parent.fetch('commit')}:#{parent.dig('truth', 'path')}",
      chdir: root.to_s
    )
    assert(status.success?, "P3 foundation-ready Truth unavailable: #{stderr.strip}")
    assert(bytes.bytesize == parent.dig("truth", "byte_length") &&
           Digest::SHA256.hexdigest(bytes) == parent.dig("truth", "sha256"),
           "P3 foundation-ready Truth identity drift")
    YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def validate_host_authorized_foundation_task_resources!(root)
    declared_budget = HOST_AUTHORIZED_FOUNDATION_BUDGET.merge(
      "governance_and_preworker_percent_max" => 10,
      "executable_foundation_start_within_engineering_hour" => 1
    )
    installation_audit = {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-host-authorized-transactional-boundary-rebaseline-20260820/audit/P3_HOST_AUTHORIZED_TRANSACTIONAL_REBASELINE_INSTALLATION_INDEPENDENT_AUDIT_PASS_RECEIPT_V1.json",
      "byte_length" => 11_611,
      "sha256" => "a85d5eef337b43e5cc6e02622bdf438c569a5dd8a9fb27c389dc8665888206a6"
    }
    workspace_hygiene = {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/workspace-hygiene-p2-local-branches-20260820/P2_HISTORICAL_LOCAL_BRANCH_CLEANUP_RECEIPT_V1.json",
      "byte_length" => 4902,
      "sha256" => "47fe08d36f0c198d927bb5e17e967a2bbaf1d685fef65aa1714873e6de9a0b76"
    }
    activation_parent = HOST_AUTHORIZED_FOUNDATION_ACTIVATION_PARENT.slice(
      "branch", "commit", "tree"
    ).merge("kind" => "HOST_AUTHORIZED_FOUNDATION_TASK_RESOURCE_CREATION_PARENT")

    contract_bytes = read_identity!(
      HOST_AUTHORIZED_FOUNDATION_CONTRACT, "P3 foundation Contract", create_once: true
    )
    contract = YAML.safe_load(
      contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
    )
    exact_keys(contract, %w[
      schema_version record_type task_id phase route_id stage_id status authority objective
      why_now scope budget acceptance non_goals lineage implementation_discipline
      stop_conditions non_pass_lifecycle external_effects
    ], "P3 foundation Contract")
    assert(contract["schema_version"] == "p3-host-authorized-foundation-task-contract/v1" &&
           contract["record_type"] ==
             "sourcelens_aios_p3_host_authorized_transactional_foundation_task_contract" &&
           contract["task_id"] == HOST_AUTHORIZED_FOUNDATION_TASK_ID &&
           contract["phase"] == "P3" && contract["route_id"] == HOST_AUTHORIZED_ROUTE_ID &&
           contract["stage_id"] == "MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION" &&
           contract["status"] == "ELIGIBLE_FOR_MASTER_ACTIVATION" &&
           contract.dig("authority", "founder_decision") ==
             HOST_AUTHORIZED_DECISION.merge("decision_id" => HOST_AUTHORIZED_DECISION_ID) &&
           contract.dig("authority", "installation_audit") == installation_audit &&
           contract.dig("authority", "workspace_hygiene_receipt") == workspace_hygiene &&
           contract.dig("authority", "activation_parent") == activation_parent &&
           contract.dig("scope", "allowed_paths") == HOST_AUTHORIZED_FOUNDATION_ALLOWLIST &&
           contract.dig("scope", "product_source_mutation_allowed") == false &&
           contract.dig("scope", "product_build_configuration_mutation_allowed") == false &&
           contract.dig("scope", "database_migration_mutation_allowed") == false &&
           contract.dig("scope", "test_only_executable_oracle_required") == true &&
           contract["budget"] == declared_budget &&
           contract.dig("lineage", "p3_002_through_p3_007_branch_worktree_code_tests_evaluator_candidate_engineering_evidence_read") == false &&
           contract.dig("lineage", "pre_fix_historical_replay_observation_as_task_input") == false &&
           contract["external_effects"] == FALSE_EFFECTS,
           "P3 foundation Contract semantics drift")

    authority_bytes = read_identity!(
      HOST_AUTHORIZED_FOUNDATION_AUTHORITY, "P3 foundation authority", create_once: true
    )
    authority = JSON.parse(authority_bytes)
    exact_keys(authority, %w[
      schema_version record_type authorization_id execution_nonce issued_at_utc phase route_id
      stage_id task_id authority_basis contract branch worktree evidence_root allowlisted_paths
      budget roles activation_guards lineage_guards external_effects task_gate_owner
      founder_decision_required user_action_required next_eligible_action
    ], "P3 foundation authority")
    assert(authority["schema_version"] == "p3-host-authorized-foundation-task-authority/v1" &&
           authority["record_type"] ==
             "sourcelens_aios_p3_host_authorized_foundation_phase_delegated_task_authority" &&
           authority["authorization_id"] == HOST_AUTHORIZED_FOUNDATION_AUTHORIZATION_ID &&
           authority["execution_nonce"] == HOST_AUTHORIZED_FOUNDATION_EXECUTION_NONCE &&
           authority["phase"] == "P3" && authority["route_id"] == HOST_AUTHORIZED_ROUTE_ID &&
           authority["stage_id"] == "MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION" &&
           authority["task_id"] == HOST_AUTHORIZED_FOUNDATION_TASK_ID &&
           authority.dig("authority_basis", "founder_decision") ==
             HOST_AUTHORIZED_DECISION.merge("decision_id" => HOST_AUTHORIZED_DECISION_ID) &&
           authority.dig("authority_basis", "installation_audit") == installation_audit &&
           authority.dig("authority_basis", "workspace_hygiene_receipt") == workspace_hygiene &&
           authority.dig("authority_basis", "activation_parent") == activation_parent &&
           authority["contract"] == HOST_AUTHORIZED_FOUNDATION_CONTRACT &&
           authority["branch"] == HOST_AUTHORIZED_FOUNDATION_BRANCH &&
           authority["worktree"] == HOST_AUTHORIZED_FOUNDATION_WORKTREE &&
           authority["evidence_root"] == HOST_AUTHORIZED_FOUNDATION_EVIDENCE_ROOT &&
           authority["allowlisted_paths"] == HOST_AUTHORIZED_FOUNDATION_ALLOWLIST &&
           authority["budget"] == declared_budget &&
           authority.dig("activation_guards", "product_source_mutation_allowed") == false &&
           authority.dig("activation_guards", "product_build_configuration_mutation_allowed") == false &&
           authority.dig("activation_guards", "database_migration_mutation_allowed") == false &&
           authority.dig("activation_guards", "stage_2_unlock_before_task_gate_pass_allowed") == false &&
           authority.dig("activation_guards", "stage_3_unlock_allowed") == false &&
           authority.dig("lineage_guards", "p3_002_through_p3_007_rejected_lineage_read_allowed") == false &&
           authority.dig("lineage_guards", "pre_fix_historical_replay_observation_as_task_input_allowed") == false &&
           authority["external_effects"] == FALSE_EFFECTS &&
           authority["founder_decision_required"] == false &&
           authority["user_action_required"] == "NONE" &&
           authority["next_eligible_action"] == HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION,
           "P3 foundation authority semantics drift")

    read_identity!(installation_audit, "P3 installation audit", create_once: true)
    read_identity!(workspace_hygiene, "P3 workspace-hygiene receipt", create_once: true)

    evidence_root = Pathname.new(HOST_AUTHORIZED_FOUNDATION_EVIDENCE_ROOT)
    assert(evidence_root.directory? && !evidence_root.symlink?,
           "P3 foundation Evidence root unavailable")
    %w[contract authority tests reviews candidate terminal].each do |child|
      path = evidence_root.join(child)
      assert(path.directory? && !path.symlink?,
             "P3 foundation Evidence directory unavailable: #{child}")
    end

    worktree = Pathname.new(HOST_AUTHORIZED_FOUNDATION_WORKTREE)
    assert(worktree.directory? && !worktree.symlink?, "P3 foundation worktree unavailable")
    assert(git!(worktree, "symbolic-ref", "--quiet", "--short", "HEAD") ==
             HOST_AUTHORIZED_FOUNDATION_BRANCH,
           "P3 foundation worktree branch drift")
    _out, _err, descendant = Open3.capture3(
      "git", "merge-base", "--is-ancestor",
      HOST_AUTHORIZED_FOUNDATION_ACTIVATION_PARENT.fetch("commit"), "HEAD",
      chdir: worktree.to_s
    )
    assert(descendant.success?, "P3 foundation worktree activation ancestry drift")
    branches = git!(root, "branch", "--format=%(refname:short)").lines.map(&:strip).reject(&:empty?)
    assert(branches.sort == ["main", HOST_AUTHORIZED_FOUNDATION_BRANCH].sort,
           "P3 foundation local-branch topology drift")
    assert(git!(root, "symbolic-ref", "--quiet", "--short", "HEAD") == "main",
           "P3 canonical repository is not on main")
    [contract, authority]
  rescue JSON::ParserError, Psych::SyntaxError => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 foundation Task resource invalid: #{e.message}"
  end

  def validate_host_authorized_foundation_terminal!(root, truth)
    decision = JSON.parse(read_identity!(
      HOST_AUTHORIZED_DECISION, "P3 host-authorized Founder decision", create_once: true
    ))
    assert(decision["schema_version"] == HOST_AUTHORIZED_DECISION_SCHEMA &&
           decision["decision_id"] == HOST_AUTHORIZED_DECISION_ID &&
           decision.dig("lifecycle", "stage_1_non_pass") ==
             "TERMINAL_LOCK_PRODUCT_AND_AUDIT_RETURN_P3_HOLD" &&
           decision.dig("anti_cycle", "successor_replacement_remediation_normalization_feasibility_authorized") == false &&
           decision.dig("anti_cycle", "p3_008_or_numbered_v2_v3_route_authorized") == false &&
           decision.dig("long_term_goal", "status") == "ACTIVE",
           "P3 foundation terminal Founder boundary drift")

    contract = YAML.safe_load(
      read_identity!(HOST_AUTHORIZED_FOUNDATION_CONTRACT,
                     "P3 foundation terminal Contract", create_once: true),
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(contract["task_id"] == HOST_AUTHORIZED_FOUNDATION_TASK_ID &&
           contract["route_id"] == HOST_AUTHORIZED_ROUTE_ID &&
           contract["stage_id"] == "MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION" &&
           contract["budget"] == HOST_AUTHORIZED_FOUNDATION_BUDGET.merge(
             "governance_and_preworker_percent_max" => 10,
             "executable_foundation_start_within_engineering_hour" => 1
           ) &&
           contract.dig("implementation_discipline", "candidate_generation_limit") == 2 &&
           contract.dig("implementation_discipline", "same_task_repair_limit") == 1 &&
           contract.dig("implementation_discipline", "review_cycle_limit") == 2 &&
           contract.dig("lineage", "p3_002_through_p3_007_branch_worktree_code_tests_evaluator_candidate_engineering_evidence_read") == false &&
           contract["external_effects"] == FALSE_EFFECTS,
           "P3 foundation terminal Contract boundary drift")

    authority = JSON.parse(read_identity!(
      HOST_AUTHORIZED_FOUNDATION_AUTHORITY,
      "P3 foundation terminal authority", create_once: true
    ))
    assert(authority["authorization_id"] == HOST_AUTHORIZED_FOUNDATION_AUTHORIZATION_ID &&
           authority["execution_nonce"] == HOST_AUTHORIZED_FOUNDATION_EXECUTION_NONCE &&
           authority["task_id"] == HOST_AUTHORIZED_FOUNDATION_TASK_ID &&
           authority["contract"] == HOST_AUTHORIZED_FOUNDATION_CONTRACT &&
           authority["external_effects"] == FALSE_EFFECTS &&
           authority.dig("lineage_guards", "p3_002_through_p3_007_rejected_lineage_read_allowed") == false &&
           authority.dig("activation_guards", "long_term_goal_close_allowed") == false,
           "P3 foundation terminal authority drift")

    manifest = JSON.parse(read_identity!(
      HOST_AUTHORIZED_FOUNDATION_CANDIDATE_2_MANIFEST,
      "P3 foundation Candidate 2 manifest", create_once: true
    ))
    read_identity!(HOST_AUTHORIZED_FOUNDATION_FROZEN_FINDING_SET,
                   "P3 foundation frozen finding set", create_once: true)
    assert(manifest.dig("candidate", "commit") ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("commit") &&
           manifest.dig("candidate", "tree") ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("tree") &&
           manifest.dig("cycle_1_frozen_finding_set", "byte_length") == 2340 &&
           manifest.dig("cycle_1_frozen_finding_set", "sha256") ==
             HOST_AUTHORIZED_FOUNDATION_MANIFEST_FALSE_FINDING_SET_SHA256 &&
           manifest.dig("cycle_1_frozen_finding_set", "sha256") !=
             HOST_AUTHORIZED_FOUNDATION_FROZEN_FINDING_SET.fetch("sha256"),
           "P3 foundation final manifest regression identity drift")

    HOST_AUTHORIZED_FOUNDATION_CYCLE_2_REVIEWS.each do |review_identity|
      identity = review_identity.slice("path", "byte_length", "sha256")
      review = JSON.parse(read_identity!(
        identity, "P3 foundation #{review_identity.fetch('reviewer_role')} Cycle 2 Review",
        create_once: true
      ))
      assert(review["reviewer_role"] == review_identity.fetch("reviewer_role") &&
             review["cycle"] == 2 && review["verdict"] == "NON_PASS" &&
             review.dig("candidate", "commit") ==
               HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("commit") &&
             review.dig("candidate", "tree") ==
               HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("tree") &&
             review.dig("scope_lineage_attestation", "p3_002_through_p3_007_rejected_lineage_read_or_reuse") == false,
             "P3 foundation Cycle 2 Review semantics drift")
    end

    read_identity!(HOST_AUTHORIZED_FOUNDATION_FOCUSED_EVIDENCE,
                   "P3 foundation focused test archive", create_once: true)
    read_identity!(HOST_AUTHORIZED_FOUNDATION_FULL_EVIDENCE,
                   "P3 foundation full test archive", create_once: true)
    read_identity!(HOST_AUTHORIZED_FOUNDATION_TERMINAL_BUNDLE,
                   "P3 foundation terminal candidate bundle", create_once: true)
    cleanup = JSON.parse(read_identity!(
      HOST_AUTHORIZED_FOUNDATION_CLEANUP_RECEIPT,
      "P3 foundation cleanup receipt", create_once: true
    ))
    assert(cleanup.dig("terminal_candidate", "commit") ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("commit") &&
           cleanup.dig("terminal_candidate", "tree") ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("tree") &&
           cleanup.dig("post_cleanup_topology", "local_branches") == ["main"] &&
           cleanup.fetch("removed_targets").all? { |target| target["exists_after_cleanup"] == false },
           "P3 foundation cleanup receipt drift")

    receipt = JSON.parse(read_identity!(
      HOST_AUTHORIZED_FOUNDATION_TERMINAL_RECEIPT,
      "P3 foundation terminal receipt", create_once: true
    ))
    expected_reviews = HOST_AUTHORIZED_FOUNDATION_CYCLE_2_REVIEWS.map do |review|
      review.slice("reviewer_role", "verdict", "path", "byte_length", "sha256")
    end
    assert(receipt["schema_version"] == "p3-host-authorized-foundation-terminal-receipt/v1" &&
           receipt["task_id"] == HOST_AUTHORIZED_FOUNDATION_TASK_ID &&
           receipt["route_id"] == HOST_AUTHORIZED_ROUTE_ID &&
           receipt["terminal_disposition"] == "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           receipt["accepted"] == false &&
           receipt["integrated_to_canonical_main"] == false &&
           receipt["cycle_2_final_independent_reviews"] == expected_reviews &&
           receipt.dig("cycle_1_frozen_finding_set", "actual_sha256") ==
             HOST_AUTHORIZED_FOUNDATION_FROZEN_FINDING_SET.fetch("sha256") &&
           receipt.dig("cycle_1_frozen_finding_set", "candidate_2_manifest_claimed_sha256") ==
             HOST_AUTHORIZED_FOUNDATION_MANIFEST_FALSE_FINDING_SET_SHA256 &&
           receipt.dig("cycle_1_frozen_finding_set", "identity_match") == false &&
           receipt.dig("budget_accounting", "candidate_generations", "consumed") == 2 &&
           receipt.dig("budget_accounting", "same_task_repairs", "consumed") == 1 &&
           receipt.dig("budget_accounting", "review_cycles", "consumed") == 2 &&
           receipt.dig("test_execution_evidence", "focused", "tests") == 15 &&
           receipt.dig("test_execution_evidence", "full", "tests") == 993 &&
           receipt.dig("test_execution_evidence", "task_gate_effect") ==
             "TEST_PASS_DOES_NOT_OVERRIDE_INDEPENDENT_REVIEW_NON_PASS" &&
           receipt.dig("lifecycle_isolation", "TASK_LIFECYCLE") ==
             "TERMINAL_TASK_GATE_NON_PASS" &&
           receipt.dig("lifecycle_isolation", "ROUTE_LIFECYCLE") ==
             "TERMINAL_STAGE_1_NON_PASS_DEPENDENT_STAGES_LOCKED_NO_SUCCESSOR" &&
           receipt.dig("lifecycle_isolation", "PHASE_LIFECYCLE") == "HOLD_INCOMPLETE" &&
           receipt.dig("lifecycle_isolation", "LONG_TERM_GOAL_LIFECYCLE") == "ACTIVE" &&
           receipt.dig("next_step_authorization_handoff", "user_action_required") == false &&
           receipt.dig("next_step_authorization_handoff", "next_eligible_action") ==
             HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION,
           "P3 foundation terminal receipt semantics drift")

    bundle_path = HOST_AUTHORIZED_FOUNDATION_TERMINAL_BUNDLE.fetch("path")
    _verify_out, verify_err, verify_status = Open3.capture3(
      "git", "bundle", "verify", bundle_path, chdir: root.to_s
    )
    assert(verify_status.success?, "P3 foundation terminal bundle invalid: #{verify_err.strip}")
    heads = git!(root, "bundle", "list-heads", bundle_path)
    assert(heads ==
             "#{HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch('commit')} refs/heads/#{HOST_AUTHORIZED_FOUNDATION_BRANCH}",
           "P3 foundation terminal bundle head drift")
    branches = git!(root, "branch", "--format=%(refname:short)").lines.map(&:strip).reject(&:empty?)
    assert(branches == ["main"], "P3 foundation terminal local-branch topology drift")
    worktrees = git!(root, "worktree", "list", "--porcelain").lines.grep(/^worktree /)
    assert(worktrees == ["worktree #{root}\n"], "P3 foundation terminal worktree topology drift")
    assert(!Pathname.new(HOST_AUTHORIZED_FOUNDATION_WORKTREE).exist?,
           "P3 foundation terminal worktree was not removed")

    project = mapping(truth["project"], "P3 foundation terminal project")
    assert(project["current_phase"] == "P3" &&
           project["phase_execution_status"] ==
             "HOLD_P3_HOST_AUTHORIZED_TRANSACTIONAL_ROUTE_TERMINAL_FOUNDATION_NON_PASS" &&
           project["current_route_execution_status"] ==
             "P3_HOST_AUTHORIZED_TRANSACTIONAL_ROUTE_TERMINAL_FOUNDATION_NON_PASS" &&
           project["p3_execution_status"] ==
             "HOLD_INCOMPLETE_FOUNDATION_TASK_GATE_NON_PASS" &&
           project["p4_entry_status"] ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3 foundation terminal project projection drift")

    route = mapping(truth["current_phase_route"], "P3 foundation terminal Route")
    stages = array(route["ordered_stages"], "P3 foundation terminal ordered stages")
    assert(route["schema_version"] == HOST_AUTHORIZED_ROUTE_SCHEMA &&
           route["route_id"] == HOST_AUTHORIZED_ROUTE_ID &&
           route["founder_reserved_triggers_resolved"] == [
             "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
             "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
           ] &&
           route["founder_route_decision"] == HOST_AUTHORIZED_DECISION.merge(
             "decision_id" => HOST_AUTHORIZED_DECISION_ID,
             "reserved_triggers" => [
               "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
               "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
             ]
           ) &&
           route["objective_id"] == "MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY" &&
           route["status"] == "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           route["lifecycle_stage"] == "FOUNDATION_TASK_TERMINAL_NON_PASS" &&
           route["execution_status"] == "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           route["scheduling_status"] == "HOLD_DEPENDENT_STAGES_LOCKED_NO_SUCCESSOR" &&
           route["next_eligible_action"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION &&
           route["terminal_task_ref"] == "active_work.last_completed_task" &&
           !route.key?("active_task_ref") &&
           stages.map { |stage| stage["stage_id"] } == %w[
             MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION
             HOST_AUTHORIZED_TRANSACTIONAL_TRUST_BOUNDARY_PRODUCT
             INDEPENDENT_P3_STRICT_EXIT_AUDIT
           ] &&
           stages.map { |stage| stage["status"] } == [
             "TERMINAL_TASK_GATE_NON_PASS", "LOCKED_FOUNDATION_NOT_ACCEPTED",
             "LOCKED_PRODUCT_NOT_ACCEPTED"
           ] &&
           route.dig("terminal_task", "candidate_commit") ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("commit") &&
           route.dig("terminal_task", "candidate_tree") ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("tree") &&
           route.dig("terminal_task", "independent_review_verdicts") == {
             "cto" => "NON_PASS", "security" => "NON_PASS",
             "quality_evaluation" => "NON_PASS"
           } &&
           route.dig("terminal_task", "terminal_receipt") ==
             HOST_AUTHORIZED_FOUNDATION_TERMINAL_RECEIPT &&
           route["long_term_goal_status"] == "ACTIVE" && route["external_effects"] == FALSE_EFFECTS,
           "P3 foundation terminal Route projection drift")

    p3_gate = truth.dig("strict_phase_gate_ledger", "phases", "P3")
    assert(p3_gate.is_a?(Hash) && p3_gate["status"] == "INCOMPLETE" &&
           p3_gate["required_item_ids"] ==
             ["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"] &&
           p3_gate.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") ==
             "MISSING" &&
           p3_gate.dig("founder_phase_gate", "status") ==
             "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "P3 foundation terminal strict Exit projection drift")

    envelope = mapping(truth["phase_execution_envelope"],
                       "P3 foundation terminal Phase envelope")
    assert(envelope["status"] == "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           envelope["limits"] == HOST_AUTHORIZED_LIMITS &&
           envelope["route_capacity"] == HOST_AUTHORIZED_REMAINING &&
           envelope["consumed"] == {
             "engineering_tasks" => 8, "engineering_hours" => 240,
             "calendar_days" => 60
           } && envelope["reserved"] == {} &&
           envelope["remaining"] == {
             "engineering_tasks" => 2, "engineering_hours" => 48,
             "calendar_days" => 12
           } && envelope["remaining_capacity_usable"] == false &&
           envelope["remaining_capacity_lock_reason"] ==
             "FOUNDATION_TASK_GATE_NON_PASS_ROUTE_TERMINAL_DEPENDENT_STAGES_LOCKED_NO_REORDER_OR_SUCCESSOR" &&
           envelope.dig("last_consumed_stage", "task_id") ==
             HOST_AUTHORIZED_FOUNDATION_TASK_ID &&
           envelope.dig("last_consumed_stage", "terminal_receipt_sha256") ==
             HOST_AUTHORIZED_FOUNDATION_TERMINAL_RECEIPT.fetch("sha256") &&
           envelope.dig("ordered_stages", 0, "status") == "TERMINAL_TASK_GATE_NON_PASS" &&
           envelope.dig("ordered_stages", 1, "status") == "LOCKED_FOUNDATION_NOT_ACCEPTED" &&
           envelope.dig("ordered_stages", 2, "status") == "LOCKED_PRODUCT_NOT_ACCEPTED" &&
           envelope["accepted_milestones"] == ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] &&
           envelope["delivery_progress"] == {
             "accepted" => 1, "total" => 4, "percent" => 25,
             "strict_exit_gate_percent" => 0
           } && envelope["external_effects"] == FALSE_EFFECTS,
           "P3 foundation terminal Phase envelope projection drift")

    control = mapping(truth["founder_escalation_control"],
                      "P3 foundation terminal Founder control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_ROUTE_TERMINAL" &&
           control.dig("source_event", "kind") ==
             "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_TERMINAL" &&
           control.dig("source_event", "status") == "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           control.dig("reserved_trigger", "category") == "NONE" &&
           control["phase_gate_status"] == "INCOMPLETE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "NONE" &&
           control["next_eligible_action"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION,
           "P3 foundation terminal Founder control drift")

    delegation = mapping(truth["phase_delegation"], "P3 foundation terminal delegation")
    assert(delegation["status"] ==
             "HOLD_P3_HOST_AUTHORIZED_TRANSACTIONAL_ROUTE_TERMINAL_FOUNDATION_NON_PASS" &&
           delegation["decision_source"] == HOST_AUTHORIZED_DECISION_ID &&
           delegation.fetch("claim_boundary").include?("TERMINAL_TASK_GATE_NON_PASS") &&
           delegation.fetch("claim_boundary").include?("Long-term Goal remains ACTIVE"),
           "P3 foundation terminal delegation drift")

    boundary = mapping(truth["phase_boundary"], "P3 foundation terminal Phase boundary")
    assert(boundary["phase_execution_status"] ==
             "HOLD_P3_HOST_AUTHORIZED_TRANSACTIONAL_ROUTE_TERMINAL_FOUNDATION_NON_PASS" &&
           boundary["task_creation_allowed"] == false &&
           boundary["task_creation_scope"] == "NONE_ROUTE_TERMINAL_FOUNDATION_NON_PASS" &&
           boundary["founder_decision_required"] == false &&
           boundary["user_action_required"] == "NONE" &&
           boundary["phase_route_decision_required"] == false &&
           boundary["next_eligible_action"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION,
           "P3 foundation terminal Phase boundary drift")

    active = mapping(truth["active_work"], "P3 foundation terminal active_work")
    completed = mapping(active["last_completed_task"], "P3 foundation terminal completed Task")
    assert(active["current_task"] == "NONE" &&
           active["current_task_status"] ==
             "NONE_ROUTE_TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           active["current_task_contract"] == HOST_AUTHORIZED_FOUNDATION_CONTRACT &&
           active["authority_record"] == HOST_AUTHORIZED_FOUNDATION_AUTHORITY &&
           active["execution_nonce_status"] == "CONSUMED_TERMINAL_NON_PASS" &&
           active["task_resource_state"] ==
             "TERMINAL_EVIDENCE_PRESERVED_BRANCH_AND_WORKTREE_REMOVED" &&
           active["task_branch"].nil? && active["task_worktree"].nil? &&
           active["budget"] == HOST_AUTHORIZED_FOUNDATION_BUDGET &&
           active["budget_consumed"] == HOST_AUTHORIZED_FOUNDATION_BUDGET &&
           active["founder_decision_required"] == false &&
           active["user_action_required"] == "NONE" &&
           active["next_eligible_action"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION &&
           completed["task_id"] == HOST_AUTHORIZED_FOUNDATION_TASK_ID &&
           completed["candidate_commit"] ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("commit") &&
           completed["candidate_tree"] ==
             HOST_AUTHORIZED_FOUNDATION_FINAL_CANDIDATE.fetch("tree") &&
           completed["candidate_integrated"] == false &&
           completed["independent_review_verdicts"].values == %w[NON_PASS NON_PASS NON_PASS] &&
           completed["terminal_receipt"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_RECEIPT &&
           completed["recovery_bundle"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_BUNDLE,
           "P3 foundation terminal active_work drift")

    execution = mapping(truth["phase_execution_claim"],
                        "P3 foundation terminal execution claim")
    assert(execution["current_route_claim"] == HOST_AUTHORIZED_ROUTE_ID &&
           execution["current_task_claim"] == "NONE" &&
           execution["phase_local_allowed"] == [] &&
           execution["phase_local_frozen_capabilities"].include?(
             "P3_002_THROUGH_P3_007_REJECTED_LINEAGE_FROZEN_UNREADABLE"
           ) &&
           execution["p3_delivery_progress_percent"] == 25 &&
           execution["p3_exit_gate_progress_percent"] == 0 &&
           execution["task_creation_allowed"] == false &&
           execution["remaining_capacity_usable"] == false &&
           execution["candidate_integration_allowed"] == false &&
           execution["next_eligible_action"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION,
           "P3 foundation terminal execution claim drift")

    claim = mapping(truth["claim_boundary"], "P3 foundation terminal claim boundary")
    assert(claim["current_task"] == "NONE" && claim["selected_task"] == "NONE" &&
           claim["p3_status"] == "HOLD_INCOMPLETE_FOUNDATION_TASK_GATE_NON_PASS" &&
           claim["p3_phase_envelope_status"] ==
             "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           claim["p3_delivery_progress_percent"] == 25 &&
           claim["p3_exit_gate_progress_percent"] == 0 &&
           claim["p3_hatb_f1_status"] == "TERMINAL_TASK_GATE_NON_PASS" &&
           claim["p3_hatb_f1_candidate_integrated"] == false &&
           claim["p3_hatb_f1_terminal_receipt_sha256"] ==
             HOST_AUTHORIZED_FOUNDATION_TERMINAL_RECEIPT.fetch("sha256") &&
           claim["next_eligible_action"] == HOST_AUTHORIZED_FOUNDATION_TERMINAL_ACTION,
           "P3 host-authorized claim boundary projection drift")

    goal = mapping(truth["goal"], "P3 foundation terminal Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] == "NONE" &&
           goal.fetch("note").include?(HOST_AUTHORIZED_FOUNDATION_TERMINAL_RECEIPT.fetch("sha256")) &&
           truth["verification_scope"] ==
             "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_TERMINAL_GATE_NON_PASS_UNINTEGRATED_P3_HOLD_INCOMPLETE_DELIVERY_25_STRICT_EXIT_ZERO_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
           "P3 foundation terminal Goal or verification scope drift")
    HOST_AUTHORIZED_FOUNDATION_TERMINAL_STATE
  rescue JSON::ParserError, Psych::SyntaxError => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 foundation terminal Evidence invalid: #{e.message}"
  end

  def validate_host_authorized_foundation_active!(root, truth)
    ready_truth = load_host_authorized_foundation_ready_truth!(root)
    validate_host_authorized_foundation_ready!(
      root, ready_truth, active_task_paths: HOST_AUTHORIZED_FOUNDATION_ALLOWLIST
    )
    validate_host_authorized_foundation_task_resources!(root)

    expected = deep_copy(ready_truth)
    expected["last_verified_at"] = "2026-08-20T15:30:23Z"
    expected["verification_scope"] =
      "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_ACTIVE_TEST_ONLY_EXECUTABLE_ORACLE_P3_DELIVERY_25_STRICT_EXIT_ZERO_P4_HOLD_LONG_TERM_GOAL_ACTIVE"
    expected.dig("goal")["current_task_authority"] = HOST_AUTHORIZED_FOUNDATION_TASK_ID

    project = expected.fetch("project")
    project["phase_execution_status"] =
      "ACTIVE_P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK"
    project["current_route_execution_status"] =
      "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_ACTIVE"
    project["p3_execution_status"] = "ACTIVE_INCOMPLETE_FOUNDATION_TASK"

    route = expected.fetch("current_phase_route")
    route["lifecycle_stage"] = "FOUNDATION_TASK_ACTIVE"
    route["execution_status"] = "FOUNDATION_TASK_ACTIVE"
    route["scheduling_status"] = "ACTIVE_FOUNDATION_TASK"
    route["next_eligible_action"] = HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION
    route["active_task_ref"] = "active_work"
    route.dig("ordered_stages", 0)["status"] = "ACTIVE"

    envelope = expected.fetch("phase_execution_envelope")
    envelope["status"] = "ACTIVE_FOUNDATION_TASK"
    envelope["consumed"] = {
      "engineering_tasks" => 8, "engineering_hours" => 240, "calendar_days" => 60
    }
    envelope["reserved"] = {
      "task_id" => HOST_AUTHORIZED_FOUNDATION_TASK_ID,
      "stage_id" => "MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION",
      "engineering_tasks" => 1, "engineering_hours" => 16, "calendar_days" => 4,
      "contract_sha256" => HOST_AUTHORIZED_FOUNDATION_CONTRACT.fetch("sha256"),
      "authority_sha256" => HOST_AUTHORIZED_FOUNDATION_AUTHORITY.fetch("sha256")
    }
    envelope["remaining"] = {
      "engineering_tasks" => 2, "engineering_hours" => 48, "calendar_days" => 12
    }
    envelope["remaining_capacity_usable"] = false
    envelope["remaining_capacity_lock_reason"] =
      "ACTIVE_FOUNDATION_TASK_SINGLE_TASK_INVARIANT"
    envelope.dig("ordered_stages", 0)["status"] = "ACTIVE"

    escalation = expected.fetch("founder_escalation_control")
    escalation["source_event"] = {
      "kind" => "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_ACTIVATED",
      "decision_id" => HOST_AUTHORIZED_DECISION_ID,
      "status" => "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_ACTIVE"
    }
    escalation.dig("resolved_strategy_decision")["result"] =
      "P3_HOST_AUTHORIZED_TRANSACTIONAL_ROUTE_ACTIVE_FOUNDATION_TASK"
    escalation["next_eligible_action"] = HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION

    delegation = expected.fetch("phase_delegation")
    delegation["status"] = "ACTIVE_P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK"
    delegation["claim_boundary"] =
      "Constitution v2.7 installs only the host-authorized transactional P3 Objective and its three ordered stages. The single test-only foundation Task is ACTIVE with its full 1-Task, 16-hour, 4-day declared budget reserved and consumed for non-resettable accounting. P3-001 remains ACCEPTED; P3-002 through P3-007 remain immutable terminal accounting and unreadable rejected lineage. Activation gives zero delivery or strict Exit credit, keeps product and audit locked, keeps P4 HOLD and keeps the same Long-term Goal ACTIVE."

    boundary = expected.fetch("phase_boundary")
    boundary["phase_execution_status"] =
      "ACTIVE_P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK"
    boundary["task_creation_allowed"] = false
    boundary["task_creation_scope"] = "NONE_ACTIVE_FOUNDATION_TASK"
    boundary["next_eligible_action"] = HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION

    active = expected.fetch("active_work")
    active["current_task"] = HOST_AUTHORIZED_FOUNDATION_TASK_ID
    active["current_task_status"] = "ACTIVE_TEST_ONLY_EXECUTABLE_FOUNDATION"
    active["current_task_contract"] = HOST_AUTHORIZED_FOUNDATION_CONTRACT
    active["current_task_contract_sha256"] =
      HOST_AUTHORIZED_FOUNDATION_CONTRACT.fetch("sha256")
    active["current_execution_authorization"] =
      HOST_AUTHORIZED_FOUNDATION_AUTHORITY.fetch("path")
    active["current_execution_authorization_sha256"] =
      HOST_AUTHORIZED_FOUNDATION_AUTHORITY.fetch("sha256")
    active["authority_record"] = HOST_AUTHORIZED_FOUNDATION_AUTHORITY
    active["execution_nonce"] = HOST_AUTHORIZED_FOUNDATION_EXECUTION_NONCE
    active["execution_nonce_status"] = "ACTIVE_SINGLE_USE"
    active["authorization_id"] = HOST_AUTHORIZED_FOUNDATION_AUTHORIZATION_ID
    active["activation_parent_commit"] =
      HOST_AUTHORIZED_FOUNDATION_ACTIVATION_PARENT.fetch("commit")
    active["activation_parent_tree"] =
      HOST_AUTHORIZED_FOUNDATION_ACTIVATION_PARENT.fetch("tree")
    active["task_resource_state"] = "ACTIVE_FROZEN_CONTRACT_AND_AUTHORITY"
    active["task_branch"] = HOST_AUTHORIZED_FOUNDATION_BRANCH
    active["task_worktree"] = HOST_AUTHORIZED_FOUNDATION_WORKTREE
    active["execution_evidence_root"] = HOST_AUTHORIZED_FOUNDATION_EVIDENCE_ROOT
    active["allowlisted_paths"] = HOST_AUTHORIZED_FOUNDATION_ALLOWLIST
    active["budget"] = HOST_AUTHORIZED_FOUNDATION_BUDGET
    active["roles"] = {
      "owner" => "MASTER_CEO_AGENT",
      "worker" => "IMPLEMENTATION_AGENT",
      "quality_owner" => "QUALITY_EVALUATION_AGENT",
      "independent_reviewers" => %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT]
    }
    active["next_eligible_action"] = HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION

    execution = expected.fetch("phase_execution_claim")
    execution["current_task_claim"] =
      "AIOS-P3-HATB-F1_MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION_ACTIVE"
    execution["real_engineering_progress"] =
      "P1_COMPLETE_P2_RESEARCH_EXIT_COMPLETE_CAPABILITY_NOT_ACCEPTED_P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_TASK_ACTIVE_ZERO_ACCEPTED_PROGRESS_P3_DELIVERY_25_P3_EXIT_GATE_ZERO"
    execution["phase_local_allowed"] = [HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION]
    execution["task_creation_allowed"] = false
    execution["remaining_capacity_usable"] = false
    execution["next_eligible_action"] = HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION

    claim = expected.fetch("claim_boundary")
    claim["current_task"] = HOST_AUTHORIZED_FOUNDATION_TASK_ID
    claim["selected_task"] = HOST_AUTHORIZED_FOUNDATION_TASK_ID
    claim["current_task_status"] = "ACTIVE_TEST_ONLY_EXECUTABLE_FOUNDATION"
    claim["next_eligible_action"] = HOST_AUTHORIZED_FOUNDATION_ACTIVE_ACTION
    claim["real_engineering_progress"] = execution.fetch("real_engineering_progress")
    claim["p3_status"] = "ACTIVE_INCOMPLETE_FOUNDATION_TASK"
    claim["p3_phase_envelope_status"] = "ACTIVE_FOUNDATION_TASK"
    claim["p3_capability_milestone_status"] =
      "HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_ACTIVE_NOT_ACCEPTED"

    assert(truth == expected, "P3 host-authorized active foundation projection drift")
    HOST_AUTHORIZED_FOUNDATION_ACTIVE_STATE
  end

  def validate_host_authorized_foundation_ready!(root, truth, active_task_paths: [])
    parent_truth = load_host_authorized_activation_truth!(root)
    decision = validate_host_authorized_decision!(root)
    constitution_bytes = read_repo_identity!(root, HOST_AUTHORIZED_CONSTITUTION,
                                             "Strategic Constitution v2.7")
    assert(constitution_bytes.include?("- Version: `2.7`") &&
           constitution_bytes.include?(HOST_AUTHORIZED_OBJECTIVE) &&
           constitution_bytes.include?(HOST_AUTHORIZED_DECISION_ID),
           "Strategic Constitution v2.7 P3 Objective or ADR drift")
    changed_paths = git!(root, "diff", "--name-only",
                         HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("commit"), "--").lines.map(&:strip)
    allowed_paths = decision.dig("installation", "allowed_repository_changes")
    path_allowed = lambda do |path|
      allowed_paths.include?(path) || active_task_paths.any? do |prefix|
        path == prefix || path.start_with?("#{prefix}/")
      end
    end
    assert(changed_paths.all? { |path| path_allowed.call(path) },
           "P3 host-authorized installation changed a path outside its exact allowlist")
    assert(changed_paths.none? do |path|
             path.start_with?("backend-spring/") &&
               active_task_paths.none? do |prefix|
                 path == prefix || path.start_with?("#{prefix}/")
               end
           end,
           "P3 host-authorized installation changed product source")

    assert(truth["historical_p3_final_transactional_route_hold"] ==
             parent_truth["current_phase_route"],
           "P3 host-authorized historical HOLD Route drift")
    assert(truth["historical_p3_final_transactional_route_hold_phase_execution_envelope"] ==
             parent_truth["phase_execution_envelope"],
           "P3 host-authorized historical HOLD envelope drift")
    assert(truth["historical_p3_final_transactional_route_hold_founder_escalation_control"] ==
             parent_truth["founder_escalation_control"],
           "P3 host-authorized historical HOLD escalation-control drift")

    decision_projection = HOST_AUTHORIZED_DECISION.merge(
      "decision_id" => HOST_AUTHORIZED_DECISION_ID,
      "reserved_triggers" => decision.fetch("reserved_triggers")
    )
    stage_statuses = [
      "ELIGIBLE_NOT_ACTIVATED",
      "LOCKED_FOUNDATION_NOT_ACCEPTED",
      "LOCKED_PRODUCT_NOT_ACCEPTED"
    ]
    stage_projection = decision.dig("route", "ordered_stages").each_with_index.map do |stage, index|
      deep_copy(stage).merge("status" => stage_statuses.fetch(index))
    end
    expected_route = {
      "schema_version" => HOST_AUTHORIZED_ROUTE_SCHEMA,
      "route_id" => HOST_AUTHORIZED_ROUTE_ID,
      "status" => "ACTIVE",
      "lifecycle_stage" => "READY_FOUNDATION_STAGE",
      "execution_status" => "READY_FOUNDATION_STAGE",
      "scheduling_status" => "FOUNDATION_TASK_ELIGIBLE",
      "phase" => "P3",
      "phase_entry_status" => "AUTHORIZED",
      "policy" => POLICY,
      "founder_phase_route_decision_required" => false,
      "founder_reserved_triggers_resolved" => decision.fetch("reserved_triggers"),
      "next_eligible_action" => HOST_AUTHORIZED_ROUTE_ACTION,
      "phase_execution_envelope_ref" => "phase_execution_envelope",
      "phase_entry_route_ref" => "historical_p3_phase_entry_route",
      "accepted_p3_001_foundation_route_ref" => "historical_p3_001_phase_route",
      "historical_predecessor_route_ref" => "historical_p3_final_transactional_route_hold",
      "founder_route_decision" => decision_projection,
      "activation_parent" => HOST_AUTHORIZED_ACTIVATION_PARENT,
      "constitution" => HOST_AUTHORIZED_CONSTITUTION,
      "objective_id" => "MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY",
      "strict_exit_gate_changed" => false,
      "strict_exit_gate_required_items" => STRICT_ITEMS,
      "prior_task_ledger" => HOST_AUTHORIZED_PRIOR_LEDGER,
      "ordered_stages" => stage_projection,
      "p3_entry_authorized" => true,
      "p4_entry_authorized" => false,
      "long_term_goal_status" => "ACTIVE",
      "external_effects" => FALSE_EFFECTS,
      "additional_write_roots" => []
    }
    assert(truth["current_phase_route"] == expected_route,
           "P3 host-authorized current Route projection drift")

    expected_envelope = {
      "schema_version" => "p3-host-authorized-transactional-phase-envelope/v1",
      "phase" => "P3",
      "status" => "ACTIVE_FOUNDATION_STAGE_ELIGIBLE",
      "authority_basis" => {
        "phase_entry_status" => "AUTHORIZED",
        "policy_path" => POLICY.fetch("path"),
        "policy_version" => POLICY.fetch("version"),
        "policy_sha256" => POLICY.fetch("sha256"),
        "source_route_ref" => "current_phase_route",
        "source_route_id" => HOST_AUTHORIZED_ROUTE_ID,
        "phase_entry_decision" => parent_truth.dig(
          "phase_execution_envelope", "authority_basis", "phase_entry_decision"
        ),
        "founder_route_decision" => decision_projection
      },
      "accounting_basis" => "NON_RESETTABLE_DECLARED_TASK_BUDGET_RESERVATION",
      "historical_accounting" => {
        "limits" => {
          "engineering_tasks" => 8, "engineering_hours" => 256, "calendar_days" => 64
        },
        "consumed" => HOST_AUTHORIZED_CONSUMED,
        "nominal_remaining" => {
          "engineering_tasks" => 1, "engineering_hours" => 32, "calendar_days" => 8
        },
        "task_ledger" => HOST_AUTHORIZED_PRIOR_LEDGER
      },
      "limits" => HOST_AUTHORIZED_LIMITS,
      "route_capacity" => HOST_AUTHORIZED_REMAINING,
      "consumed" => HOST_AUTHORIZED_CONSUMED,
      "reserved" => {},
      "remaining" => HOST_AUTHORIZED_REMAINING,
      "remaining_capacity_usable" => true,
      "remaining_capacity_lock_reason" => "NONE",
      "milestone_order" => [
        "DURABLE_STATE_AND_CHECKPOINT_RESUME",
        "MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION",
        "HOST_AUTHORIZED_TRANSACTIONAL_TRUST_BOUNDARY_PRODUCT",
        "INDEPENDENT_P3_EXIT_GATE_AUDIT"
      ],
      "accepted_milestones" => ["DURABLE_STATE_AND_CHECKPOINT_RESUME"],
      "ordered_stages" => stage_projection,
      "delivery_progress" => {
        "accepted" => 1, "total" => 4, "percent" => 25,
        "strict_exit_gate_percent" => 0
      },
      "external_effects" => FALSE_EFFECTS
    }
    assert(truth["phase_execution_envelope"] == expected_envelope,
           "P3 host-authorized Phase envelope projection drift")

    project = truth.fetch("project")
    expected_project = deep_copy(parent_truth.fetch("project"))
    expected_project["phase_execution_status"] =
      "ACTIVE_P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_ELIGIBLE"
    expected_project["current_route_execution_status"] =
      "P3_HOST_AUTHORIZED_TRANSACTIONAL_ROUTE_READY_FOUNDATION_STAGE"
    expected_project["p3_execution_status"] =
      "ACTIVE_INCOMPLETE_FOUNDATION_STAGE_ELIGIBLE"
    assert(project == expected_project, "P3 host-authorized project projection drift")

    authority = mapping(truth["authority"], "canonical authority")
    assert(authority["strategy"] == HOST_AUTHORIZED_CONSTITUTION.merge("status" => "FROZEN"),
           "P3 host-authorized Constitution authority projection drift")
    phase_authority = truth.dig("strict_phase_gate_ledger", "phase_route_authority")
    assert(phase_authority == {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "2.7",
      "section" => "## 9. Phase route",
      "section_byte_length" => 4047,
      "section_sha256" => "c5bb58c7d745031f8e3f223dd0a84449e6039f575ad8fa67ade7ec922db8444a"
    }, "P3 host-authorized strict Phase-route authority drift")
    p3_gate = truth.dig("strict_phase_gate_ledger", "phases", "P3")
    assert(p3_gate == parent_truth.dig("strict_phase_gate_ledger", "phases", "P3"),
           "P3 host-authorized installation changed strict P3 Exit evidence")

    expected_boundary = deep_copy(parent_truth.fetch("phase_boundary"))
    expected_boundary["phase_execution_status"] =
      "ACTIVE_P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_ELIGIBLE"
    expected_boundary["task_creation_allowed"] = true
    expected_boundary["task_creation_scope"] =
      "MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION_ONLY"
    expected_boundary["allowed_task_kinds"] = [
      "MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION",
      "HOST_AUTHORIZED_TRANSACTIONAL_TRUST_BOUNDARY_PRODUCT",
      "INDEPENDENT_P3_STRICT_EXIT_AUDIT"
    ]
    expected_boundary["allowed_capabilities"] = [
      "P3_001_CHECKPOINT_PUBLIC_BEHAVIOR_COMPOSITION",
      "COMPILE_TIME_CLOSED_ACTION_ALGEBRA",
      "HOST_POSITIVE_AUTHORIZATION",
      "CREATE_ONCE_PRE_EFFECT_AUTHORIZATION_AND_DISPATCH_INTENT",
      "DISPOSABLE_OS_ENFORCED_ISOLATION",
      "CRASH_RECONCILIATION",
      "EXACTLY_ONE_TERMINAL_INVOCATION_TRACE",
      "CHECKPOINT_ADVANCEMENT_AFTER_TERMINAL_TRACE_ACCEPTANCE"
    ]
    expected_boundary["escalation_reason"] = nil
    expected_boundary["user_action_required"] = "NONE"
    expected_boundary["phase_route_decision_required"] = false
    expected_boundary["phase_route_user_action_required"] = "NONE"
    expected_boundary["next_eligible_action"] = HOST_AUTHORIZED_ROUTE_ACTION
    assert(truth["phase_boundary"] == expected_boundary,
           "P3 host-authorized Phase boundary projection drift")

    expected_control = {
      "schema_version" => "founder-escalation-control/v2",
      "disposition" => "NO_RESERVED_TRIGGER_CONTINUE_PHASE",
      "source_event" => {
        "kind" => "FOUNDER_P3_HOST_AUTHORIZED_TRANSACTIONAL_REBASELINE_INSTALLED",
        "decision_id" => HOST_AUTHORIZED_DECISION_ID,
        "status" => "P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_ELIGIBLE"
      },
      "reserved_trigger" => {"category" => "NONE", "evidence" => nil},
      "resolved_strategy_decision" => decision_projection.merge(
        "category" => "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
        "result" => "P3_HOST_AUTHORIZED_TRANSACTIONAL_ROUTE_INSTALLED_FOUNDATION_ELIGIBLE"
      ),
      "resolved_phase_entry_decision" =>
        parent_truth.dig("founder_escalation_control", "resolved_phase_entry_decision"),
      "phase_gate_status" => "INCOMPLETE",
      "founder_decision_required" => false,
      "next_action_owner" => "MASTER_CEO_AGENT",
      "next_eligible_action" => HOST_AUTHORIZED_ROUTE_ACTION
    }
    assert(truth["founder_escalation_control"] == expected_control,
           "P3 host-authorized Founder escalation projection drift")

    expected_delegation = deep_copy(parent_truth.fetch("phase_delegation"))
    expected_delegation["status"] =
      "ACTIVE_P3_HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_ELIGIBLE"
    expected_delegation["decision_source"] = HOST_AUTHORIZED_DECISION_ID
    expected_delegation["claim_boundary"] =
      "Constitution v2.7 installs only the host-authorized transactional P3 Objective and its three ordered stages. P3-001 remains ACCEPTED; P3-002 through P3-007 remain immutable terminal accounting and unreadable rejected lineage. The non-resettable cumulative ceiling is 10 Tasks, 288 hours and 72 days with 7 Tasks, 224 hours and 56 days already consumed. Installation gives zero engineering or delivery credit, unlocks only the foundation Task, keeps strict Exit at 0%, keeps P4 HOLD and keeps the same Long-term Goal ACTIVE."
    assert(truth["phase_delegation"] == expected_delegation,
           "P3 host-authorized Phase delegation projection drift")

    expected_active = deep_copy(parent_truth.fetch("active_work"))
    expected_active["activation_parent_commit"] =
      HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("commit")
    expected_active["activation_parent_tree"] =
      HOST_AUTHORIZED_ACTIVATION_PARENT.fetch("tree")
    expected_active["task_resource_state"] =
      "NOT_CREATED_FOUNDATION_STAGE_ELIGIBLE"
    expected_active["founder_reserved_authorization"] =
      HOST_AUTHORIZED_DECISION.fetch("path")
    expected_active["founder_reserved_authorization_sha256"] =
      HOST_AUTHORIZED_DECISION.fetch("sha256")
    expected_active["founder_decision_required"] = false
    expected_active["founder_decision_required_scope"] = nil
    expected_active["escalation_reason"] = nil
    expected_active["user_action_required"] = "NONE"
    expected_active["phase_route_decision_required"] = false
    expected_active["phase_route_user_action_required"] = "NONE"
    expected_active["next_eligible_action"] = HOST_AUTHORIZED_ROUTE_ACTION
    assert(truth["active_work"] == expected_active,
           "P3 host-authorized active-work projection drift")

    expected_execution = deep_copy(parent_truth.fetch("phase_execution_claim"))
    expected_execution["current_route_claim"] = HOST_AUTHORIZED_ROUTE_ID
    expected_execution["real_engineering_progress"] =
      "P1_COMPLETE_P2_RESEARCH_EXIT_COMPLETE_CAPABILITY_NOT_ACCEPTED_P3_HOST_AUTHORIZED_TRANSACTIONAL_REBASELINE_INSTALLED_ZERO_ENGINEERING_PROGRESS_P3_DELIVERY_25_P3_EXIT_GATE_ZERO"
    expected_execution["phase_local_allowed"] = [HOST_AUTHORIZED_ROUTE_ACTION]
    expected_execution["phase_local_frozen_capabilities"] = [
      "P3_002_THROUGH_P3_007_REJECTED_LINEAGE_FROZEN_UNREADABLE",
      "SECOND_PRODUCT_IMPLEMENTATION_TASK_NOT_AUTHORIZED",
      "DEPENDENT_PRODUCT_AND_AUDIT_STAGES_LOCKED_UNTIL_PREDECESSOR_ACCEPTED"
    ]
    expected_execution["task_creation_allowed"] = true
    expected_execution["remaining_capacity_usable"] = true
    expected_execution["next_eligible_action"] = HOST_AUTHORIZED_ROUTE_ACTION
    expected_execution["accepted_outcomes"] =
      Array(parent_truth.dig("phase_execution_claim", "accepted_outcomes")) + [
        "P3_HOST_AUTHORIZED_TRANSACTIONAL_OBJECTIVE_ROUTE_REBASELINE_INSTALLED_ZERO_ENGINEERING_PROGRESS"
      ]
    assert(truth["phase_execution_claim"] == expected_execution,
           "P3 host-authorized execution-claim projection drift")

    expected_claim = deep_copy(parent_truth.fetch("claim_boundary"))
    expected_claim["current_phase_route"] = HOST_AUTHORIZED_ROUTE_ID
    expected_claim["selected_task"] = "NONE_FOUNDATION_STAGE_ELIGIBLE"
    expected_claim["next_eligible_action"] = HOST_AUTHORIZED_ROUTE_ACTION
    expected_claim["real_engineering_progress"] =
      expected_execution.fetch("real_engineering_progress")
    expected_claim["p3_status"] = "ACTIVE_INCOMPLETE_FOUNDATION_STAGE_ELIGIBLE"
    expected_claim["p3_phase_envelope_status"] = "ACTIVE_FOUNDATION_STAGE_ELIGIBLE"
    expected_claim["p3_capability_milestone_status"] =
      "HOST_AUTHORIZED_TRANSACTIONAL_FOUNDATION_ELIGIBLE_NOT_ACCEPTED"
    expected_claim["p3_host_authorized_transactional_route_decision_sha256"] =
      HOST_AUTHORIZED_DECISION.fetch("sha256")
    assert(truth["claim_boundary"] == expected_claim,
           "P3 host-authorized claim boundary projection drift")

    goal = mapping(truth["goal"], "Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] == "NONE" &&
           goal.fetch("note").include?(HOST_AUTHORIZED_DECISION.fetch("sha256")),
           "P3 host-authorized installation must keep the same Long-term Goal active")
    assert(truth["verification_scope"] ==
             "P3_HOST_AUTHORIZED_TRANSACTIONAL_OBJECTIVE_AND_ROUTE_REBASELINE_INSTALLED_FOUNDATION_ELIGIBLE_P3_DELIVERY_25_STRICT_EXIT_ZERO_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
           "P3 host-authorized verification scope drift")
    HOST_AUTHORIZED_ROUTE_STATE
  end

  def read_tik_external_identity!(identity, label, create_once: false)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    path = Pathname.new(record.fetch("path"))
    assert(path.absolute? && path.cleanpath.to_s == path.to_s,
           "#{label} path must be absolute and normalized")
    stat = path.lstat
    assert(stat.file? && !path.symlink?, "#{label} must be a non-symlink regular file")
    assert(path.realpath.to_s == path.cleanpath.to_s,
           "#{label} must not resolve through a symlink")
    assert(!create_once || ((stat.mode & 0o777) == 0o444 && stat.nlink == 1),
           "#{label} create-once mode/link drift")
    bytes = path.binread
    assert(bytes.bytesize == record.fetch("byte_length"), "#{label} byte length drift")
    assert(Digest::SHA256.hexdigest(bytes) == record.fetch("sha256"),
           "#{label} SHA-256 drift")
    bytes
  rescue Errno::ENOENT, Errno::ELOOP => e
    raise P3FinalTransactionalRouteValidationError, "#{label} unavailable: #{e.message}"
  end

  def parse_tik_json!(bytes, label)
    duplicate_guard = Class.new(Hash) do
      def []=(key, value)
        raise JSON::ParserError, "duplicate JSON member #{key.inspect}" if key?(key)

        super
      end
    end
    JSON.parse(bytes, object_class: duplicate_guard)
  rescue JSON::ParserError => e
    raise P3FinalTransactionalRouteValidationError, "#{label} JSON invalid: #{e.message}"
  end

  def tik_timestamp!(value, label)
    assert(value.is_a?(String) &&
           value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/),
           "#{label} must be an exact UTC RFC3339 second timestamp")
    value
  end

  def tik_uuid!(value, label)
    assert(value.is_a?(String) &&
           value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/),
           "#{label} must be a lowercase RFC4122 UUID")
    value
  end

  def tik_assert_path_under!(path_string, root_string, label, expected_path: nil)
    path = Pathname.new(path_string)
    root = Pathname.new(root_string)
    assert(path.absolute? && root.absolute? && path.cleanpath.to_s == path.to_s &&
           root.cleanpath.to_s == root.to_s, "#{label} path/root must be absolute and normalized")
    assert(expected_path.nil? || path.to_s == expected_path,
           "#{label} path is not the exact authorized target")
    relative = path.relative_path_from(root).to_s
    assert(relative != "." && !relative.start_with?("../"), "#{label} escapes its Evidence root")
    current = path.parent
    loop do
      stat = current.lstat
      assert(stat.directory? && !current.symlink?, "#{label} ancestor is not a real directory")
      assert(current.realpath.to_s == current.cleanpath.to_s,
             "#{label} ancestor resolves through a symlink")
      break if current == root
      assert(current.to_s.start_with?("#{root}#{File::SEPARATOR}"),
             "#{label} ancestor escaped its Evidence root")
      current = current.parent
    end
    path
  rescue ArgumentError, Errno::ENOENT, Errno::ELOOP => e
    raise P3FinalTransactionalRouteValidationError, "#{label} rooted path invalid: #{e.message}"
  end

  def read_tik_rooted_json!(identity, label, root_path:, expected_path:)
    record = exact_keys(identity, %w[path byte_length sha256], "#{label} identity")
    tik_assert_path_under!(record.fetch("path"), root_path, label, expected_path: expected_path)
    bytes = read_tik_external_identity!(record, label, create_once: true)
    [record, parse_tik_json!(bytes, label)]
  end

  def tik_git_bytes!(root, revision, relative_path, label)
    assert(relative_path.is_a?(String) && !Pathname.new(relative_path).absolute? &&
           Pathname.new(relative_path).cleanpath.to_s == relative_path &&
           !relative_path.start_with?("../"), "#{label} repository path invalid")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{revision}:#{relative_path}", chdir: root.to_s
    )
    assert(status.success?, "#{label} unavailable from Git: #{stderr.strip}")
    bytes
  end

  def tik_git_tree_entry!(root, revision, relative_path, label)
    line = git!(root, "ls-tree", revision, "--", relative_path)
    match = line.match(/\A(\d{6}) (\S+) ([0-9a-f]{40})\t(.+)\z/)
    assert(match && match[4] == relative_path && %w[100644 100755].include?(match[1]) &&
           match[2] == "blob",
           "#{label} must be an exact regular Git blob, never a symlink, gitlink or tree")
    {
      "git_mode" => match[1], "object_type" => match[2], "git_blob_sha1" => match[3]
    }
  end

  def validate_tik_activation_parent_record!(root, activation_parent, stage_index)
    parent = exact_keys(activation_parent, %w[branch commit tree], "P3 TIK Task activation parent")
    assert(parent["branch"] == "main" && parent["commit"].match?(/\A[0-9a-f]{40}\z/) &&
           parent["tree"].match?(/\A[0-9a-f]{40}\z/),
           "P3 TIK Task activation-parent identity invalid")
    assert(parent["commit"] != TIK_ACTIVATION_PARENT.fetch("commit"),
           "P3 TIK Task cannot bind the preinstallation parent")
    assert(git!(root, "rev-parse", "#{parent.fetch('commit')}^{tree}") == parent.fetch("tree"),
           "P3 TIK Task activation-parent tree drift")
    git!(root, "merge-base", "--is-ancestor", TIK_ACTIVATION_PARENT.fetch("commit"),
         parent.fetch("commit"))
    git!(root, "merge-base", "--is-ancestor", parent.fetch("commit"), "main")
    constitution = tik_git_bytes!(root, parent.fetch("commit"), TIK_CONSTITUTION.fetch("path"),
                                  "P3 TIK activation-parent Constitution")
    assert(constitution.bytesize == TIK_CONSTITUTION.fetch("byte_length") &&
           Digest::SHA256.hexdigest(constitution) == TIK_CONSTITUTION.fetch("sha256"),
           "P3 TIK Task activation parent predates the frozen Constitution")
    parent_truth_bytes = tik_git_bytes!(
      root, parent.fetch("commit"), "docs/aios/truth/project_state.yaml",
      "P3 TIK activation-parent Truth"
    )
    parent_truth = YAML.safe_load(
      parent_truth_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
    )
    expected_lifecycle = %w[
      FOUNDATION_STAGE_ELIGIBLE PRODUCT_STAGE_ELIGIBLE AUDIT_STAGE_ELIGIBLE
    ].fetch(stage_index)
    assert(parent_truth.dig("current_phase_route", "schema_version") == TIK_ROUTE_SCHEMA &&
           parent_truth.dig("current_phase_route", "route_id") == TIK_ROUTE_ID &&
           parent_truth.dig("current_phase_route", "lifecycle_stage") == expected_lifecycle &&
           parent_truth.dig("current_phase_route", "founder_route_decision", "sha256") ==
             TIK_DECISION.fetch("sha256") &&
           parent_truth.dig("active_work", "current_task") == "NONE" &&
           parent_truth.dig("goal", "control_plane_status_observed") == "ACTIVE",
           "P3 TIK activation parent is not the exact predecessor-accepted ready state")
    if stage_index == 1
      _stdout, _stderr, status = Open3.capture3(
        "git", "cat-file", "-e",
        "#{parent.fetch('commit')}:backend-spring/src/main/resources/db/migration/V034__add_trusted_invocation_kernel.sql",
        chdir: root.to_s
      )
      assert(!status.success?, "P3 TIK V034 migration target was already occupied at activation")
    end
    parent
  rescue Psych::Exception => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 TIK activation-parent Truth invalid: #{e.message}"
  end

  def validate_tik_contract!(root, identity, stage_index)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    contract_identity, contract = read_tik_rooted_json!(
      identity, "P3 TIK Task Contract", root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("contract_path")
    )
    exact_keys(contract, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id task_kind status
      objective claim_boundary founder_decision activation_parent resources allowlisted_paths budget
      workflow_id capabilities required_reviewers gate_requirements product_source_mutation_allowed
      external_effects rejected_lineage_read_allowed created_at_utc
    ], "P3 TIK Task Contract")
    activation_parent = validate_tik_activation_parent_record!(
      root, contract["activation_parent"], stage_index
    )
    assert(contract["schema_version"] == "p3-tik-task-contract/v1" &&
           contract["record_type"] == "P3_TIK_TASK_CONTRACT" && contract["phase"] == "P3" &&
           contract["route_id"] == TIK_ROUTE_ID && contract["stage_ordinal"] == stage_index + 1 &&
           contract["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           contract["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           contract["task_kind"] == TIK_STAGE_KINDS.fetch(stage_index) &&
           contract["status"] == "FROZEN_SINGLE_TASK_CONTRACT" &&
           contract["objective"] == TIK_STAGE_OBJECTIVES.fetch(stage_index) &&
           contract["claim_boundary"] == TIK_STAGE_CLAIM_BOUNDARIES.fetch(stage_index) &&
           contract["founder_decision"] ==
             TIK_DECISION.merge("decision_id" => TIK_DECISION_ID) &&
           contract["resources"] == resource &&
           contract["allowlisted_paths"] == TIK_STAGE_ALLOWED_PATHS.fetch(stage_index) &&
           contract["budget"] == TIK_FULL_STAGE_BUDGETS.fetch(stage_index) &&
           contract["workflow_id"] == "VERIFY_CUSTODY_SHA256_V1" &&
           contract["capabilities"] == TIK_STAGE_CAPABILITIES.fetch(stage_index) &&
           contract["required_reviewers"] == TIK_REVIEW_ROLES &&
           contract["gate_requirements"] == TIK_STAGE_GATE_REQUIREMENTS.fetch(stage_index) &&
           contract["product_source_mutation_allowed"] == (stage_index == 1) &&
           contract["external_effects"] == TIK_EXTERNAL_EFFECTS &&
           contract["rejected_lineage_read_allowed"] == false,
           "P3 TIK Task Contract authority/scope drift")
    tik_timestamp!(contract["created_at_utc"], "P3 TIK Task Contract created_at_utc")
    [contract_identity, contract, activation_parent]
  end

  def validate_tik_authority!(root, identity, stage_index, contract_identity, activation_parent)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    authority_identity, authority = read_tik_rooted_json!(
      identity, "P3 TIK Task authority", root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("authority_path")
    )
    exact_keys(authority, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id task_kind status
      issuer authorization_scope authorization_id execution_nonce issued_at_utc contract
      founder_decision activation_parent resources allowlisted_paths budget workflow_id capabilities
      required_reviewers external_effects rejected_lineage_read_allowed consumption
    ], "P3 TIK Task authority")
    assert(authority["schema_version"] == "p3-tik-task-authority/v1" &&
           authority["record_type"] == "P3_TIK_TASK_AUTHORITY" && authority["phase"] == "P3" &&
           authority["route_id"] == TIK_ROUTE_ID &&
           authority["stage_ordinal"] == stage_index + 1 &&
           authority["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           authority["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           authority["task_kind"] == TIK_STAGE_KINDS.fetch(stage_index) &&
           authority["status"] == "AUTHORIZED_SINGLE_USE" &&
           authority["issuer"] == "MASTER_CEO_AGENT" &&
           authority["authorization_scope"] ==
             "EXECUTE_EXACT_TASK_CONTRACT_ONLY_NO_SELF_ACCEPTANCE" &&
           authority["contract"] == contract_identity &&
           authority["founder_decision"] ==
             TIK_DECISION.merge("decision_id" => TIK_DECISION_ID) &&
           authority["activation_parent"] == activation_parent &&
           authority["resources"] == resource &&
           authority["allowlisted_paths"] == TIK_STAGE_ALLOWED_PATHS.fetch(stage_index) &&
           authority["budget"] == TIK_FULL_STAGE_BUDGETS.fetch(stage_index) &&
           authority["workflow_id"] == "VERIFY_CUSTODY_SHA256_V1" &&
           authority["capabilities"] == TIK_STAGE_CAPABILITIES.fetch(stage_index) &&
           authority["required_reviewers"] == TIK_REVIEW_ROLES &&
           authority["external_effects"] == TIK_EXTERNAL_EFFECTS &&
           authority["rejected_lineage_read_allowed"] == false &&
           authority["consumption"] == {
             "consumed_on" => "TASK_ACTIVATION", "reuse_allowed" => false,
             "parallel_task_allowed" => false
           }, "P3 TIK Task authority cross-binding drift")
    tik_uuid!(authority["authorization_id"], "P3 TIK authorization_id")
    tik_uuid!(authority["execution_nonce"], "P3 TIK execution_nonce")
    tik_timestamp!(authority["issued_at_utc"], "P3 TIK authority issued_at_utc")
    [authority_identity, authority]
  end

  def tik_repository_path_allowed?(path, stage_index)
    return false unless path.is_a?(String) && !Pathname.new(path).absolute? &&
                        Pathname.new(path).cleanpath.to_s == path && !path.start_with?("../")

    TIK_STAGE_ALLOWED_PATHS.fetch(stage_index).any? do |allowed|
      path == allowed || path.start_with?("#{allowed}/")
    end
  end

  def validate_tik_candidate_manifest!(root, identity, stage_index, contract_identity,
                                       authority_identity, activation_parent, terminal: false,
                                       expected_path: nil, expected_candidate_id: nil)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    manifest_identity, manifest = read_tik_rooted_json!(
      identity, "P3 TIK candidate manifest", root_path: resource.fetch("evidence_root"),
      expected_path: expected_path || resource.fetch("candidate_manifest_path")
    )
    manifest_keys = %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id candidate
      activation_parent contract authority generated_from_actual_bytes repository_files
      external_files inventory_canonicalization inventory_sha256 created_at_utc
    ]
    manifest_keys << "frozen_predecessor_inputs" if stage_index.positive?
    exact_keys(manifest, manifest_keys, "P3 TIK candidate manifest")
    candidate = exact_keys(manifest["candidate"],
                           %w[candidate_id candidate_kind commit tree source_branch],
                           "P3 TIK candidate identity")
    expected_kind = %w[FOUNDATION_CANDIDATE PRODUCT_CANDIDATE LOCKED_STAGE_2_PRODUCT].fetch(stage_index)
    expected_branch = stage_index == 2 ? TIK_TASK_BRANCHES.fetch(1) : TIK_TASK_BRANCHES.fetch(stage_index)
    candidate_id_valid = if expected_candidate_id
      candidate["candidate_id"] == expected_candidate_id
    elsif stage_index == 2
      candidate["candidate_id"] == "LOCKED_STAGE_2_PRODUCT"
    else
      %w[CANDIDATE_1 CANDIDATE_2].include?(candidate["candidate_id"])
    end
    assert(candidate_id_valid && candidate["candidate_kind"] == expected_kind &&
           candidate["source_branch"] == expected_branch &&
           candidate["commit"].is_a?(String) && candidate["commit"].match?(/\A[0-9a-f]{40}\z/) &&
           candidate["tree"].is_a?(String) && candidate["tree"].match?(/\A[0-9a-f]{40}\z/),
           "P3 TIK candidate identity is invalid or exceeds Candidate 2")
    unless terminal
      assert(git!(root, "rev-parse", "#{candidate.fetch('commit')}^{tree}") ==
               candidate.fetch("tree"), "P3 TIK candidate commit/tree drift")
    end
    repository_files = array(manifest["repository_files"], "P3 TIK repository inventory")
    paths = repository_files.map do |entry|
      exact_keys(entry, %w[
        relative_path git_mode object_type git_blob_sha1 byte_length sha256
      ], "P3 TIK repository file identity")
      path = entry.fetch("relative_path")
      assert(tik_repository_path_allowed?(path, stage_index),
             "P3 TIK candidate repository path exceeds the stage allowlist: #{path}")
      assert(entry["byte_length"].is_a?(Integer) && entry["byte_length"] >= 0 &&
             entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[0-9a-f]{64}\z/),
             "P3 TIK candidate repository identity is not closed: #{path}")
      declared_tree_entry = entry.slice("git_mode", "object_type", "git_blob_sha1")
      assert(%w[100644 100755].include?(declared_tree_entry["git_mode"]) &&
             declared_tree_entry["object_type"] == "blob" &&
             declared_tree_entry["git_blob_sha1"].is_a?(String) &&
             declared_tree_entry["git_blob_sha1"].match?(/\A[0-9a-f]{40}\z/),
             "P3 TIK candidate repository Git identity is not closed: #{path}")
      unless terminal
        assert(tik_git_tree_entry!(root, candidate.fetch("commit"), path,
                                   "P3 TIK candidate repository file") == declared_tree_entry,
               "P3 TIK candidate repository mode/type/blob identity drift: #{path}")
        bytes = tik_git_bytes!(root, candidate.fetch("commit"), path,
                               "P3 TIK candidate repository file")
        assert(bytes.bytesize == entry.fetch("byte_length") &&
               Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
               "P3 TIK candidate repository inventory identity drift: #{path}")
      end
      path
    end
    assert(paths.uniq.length == paths.length && paths == paths.sort,
           "P3 TIK repository inventory must be unique and sorted")
    if terminal
      # A terminal Route binds the rejected candidate through the immutable manifest/reviews/bundle
      # without replaying or reopening its Git lineage.
      assert(stage_index != 2 || repository_files.empty?,
             "P3 TIK terminal Audit manifest cannot claim repository mutations")
    elsif stage_index == 2
      assert(repository_files.empty?, "P3 TIK Audit manifest cannot contain repository mutations")
      git!(root, "merge-base", "--is-ancestor", candidate.fetch("commit"),
           activation_parent.fetch("commit"))
    else
      git!(root, "merge-base", "--is-ancestor", activation_parent.fetch("commit"),
           candidate.fetch("commit"))
      changed = git!(root, "diff", "--name-status", "--diff-filter=ACMRD",
                     activation_parent.fetch("commit"), candidate.fetch("commit"))
        .lines.map(&:strip).reject(&:empty?).map do |line|
          status, path, unexpected = line.split("\t", 3)
          assert(unexpected.nil? && %w[A M].include?(status) && path,
                 "P3 TIK candidate contains a deletion, rename, copy or unknown Git delta")
          path
        end.sort
      assert(changed == paths,
             "P3 TIK candidate manifest is not generated from the exact changed-file set")
      assert(!changed.empty?, "P3 TIK Foundation/Product candidate diff must be non-empty")
    end
    external_files = array(manifest["external_files"], "P3 TIK external Evidence inventory")
    assert(!external_files.empty?, "P3 TIK candidate manifest requires real external Evidence")
    reserved_paths = resource.values_at(
      "contract_path", "authority_path", "gate_evidence_path", "cycle_1_gate_evidence_path",
      "rejected_bundle_path", "bundle_attestation_path",
      "cycle_1_candidate_manifest_path", "cycle_1_finding_set_path",
      "cycle_1_cto_review_path", "cycle_1_security_review_path",
      "cycle_1_quality_review_path",
      "candidate_manifest_path", "cto_review_path", "security_review_path", "quality_review_path",
      "task_gate_pass_receipt_path", "task_gate_non_pass_receipt_path"
    )
    external_paths = external_files.map do |entry|
      record = exact_keys(entry, %w[path byte_length sha256], "P3 TIK external Evidence identity")
      assert(!reserved_paths.include?(record.fetch("path")),
             "P3 TIK manifest cannot inventory itself, reviews or terminal receipt")
      tik_assert_path_under!(record.fetch("path"), resource.fetch("evidence_root"),
                             "P3 TIK external Evidence")
      read_tik_external_identity!(record, "P3 TIK external Evidence", create_once: true)
      record.fetch("path")
    end
    assert(external_paths.uniq.length == external_paths.length && external_paths == external_paths.sort,
           "P3 TIK external Evidence inventory must be unique and sorted")
    inventory = {
      "repository_files" => repository_files,
      "external_files" => external_files
    }
    assert(manifest["schema_version"] == "p3-tik-candidate-manifest/v1" &&
           manifest["record_type"] == "P3_TIK_CANDIDATE_MANIFEST" &&
           manifest["phase"] == "P3" && manifest["route_id"] == TIK_ROUTE_ID &&
           manifest["stage_ordinal"] == stage_index + 1 &&
           manifest["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           manifest["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           manifest["activation_parent"] == activation_parent &&
           manifest["contract"] == contract_identity && manifest["authority"] == authority_identity &&
           manifest["generated_from_actual_bytes"] == true &&
           manifest["inventory_canonicalization"] == "RECURSIVE_KEY_SORT_COMPACT_JSON_UTF8" &&
           manifest["inventory_sha256"] == Digest::SHA256.hexdigest(
             JSON.generate(canonical(inventory))
           ), "P3 TIK candidate manifest semantic or inventory binding drift")
    if stage_index.positive?
      predecessor_keys = %w[
        foundation_candidate_manifest foundation_gate_evidence foundation_task_gate_receipt
      ]
      predecessor_keys += %w[
        product_candidate_manifest product_gate_evidence product_task_gate_receipt
      ] if stage_index == 2
      predecessors = exact_keys(manifest["frozen_predecessor_inputs"], predecessor_keys,
                                "P3 TIK frozen predecessor inputs")
      predecessors.each do |name, predecessor_identity|
        exact_keys(predecessor_identity, %w[path byte_length sha256],
                   "P3 TIK frozen predecessor input #{name}")
      end
    end
    tik_timestamp!(manifest["created_at_utc"], "P3 TIK candidate manifest created_at_utc")
    [manifest_identity, manifest, candidate]
  end

  def validate_tik_gate_evidence!(identity, stage_index, contract_identity, authority_identity,
                                  manifest_identity, manifest, terminal: false,
                                  expected_path: nil)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    evidence_identity, evidence = read_tik_rooted_json!(
      identity, "P3 TIK Gate Evidence", root_path: resource.fetch("evidence_root"),
      expected_path: expected_path || resource.fetch("gate_evidence_path")
    )
    exact_keys(evidence, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id disposition
      candidate_manifest contract authority generated_from_actual_bytes evidence_files
      executed_checks gate_results recorded_at_utc
    ], "P3 TIK Gate Evidence")
    evidence_files = array(evidence["evidence_files"], "P3 TIK Gate Evidence files")
    assert(evidence_files == manifest.fetch("external_files") && !evidence_files.empty?,
           "P3 TIK Gate Evidence is not bound to the manifest raw Evidence inventory")
    evidence_paths = evidence_files.map { |entry| entry.fetch("path") }
    assert(evidence_paths == evidence_paths.sort && evidence_paths.uniq.length == evidence_paths.length,
           "P3 TIK Gate Evidence file inventory must be unique and sorted")

    expected_results = TIK_PASS_GATE_RESULTS.fetch(stage_index)
    gate_results = exact_keys(evidence["gate_results"], expected_results.keys,
                              "P3 TIK Gate Evidence results")
    checks = array(evidence["executed_checks"], "P3 TIK executed Gate checks")
    observations = checks.map do |raw_identity|
      raw_identity = exact_keys(raw_identity, %w[path byte_length sha256],
                                "P3 TIK executed Gate observation identity")
      assert(evidence_files.include?(raw_identity),
             "P3 TIK executed Gate check references unmanifested Evidence")
      observation_bytes = read_tik_external_identity!(
        raw_identity, "P3 TIK executed Gate observation", create_once: true
      )
      observation = parse_tik_json!(observation_bytes, "P3 TIK executed Gate observation")
      exact_keys(observation, %w[
        schema_version record_type phase route_id stage_ordinal stage_id task_id
        candidate gate_key observed_value command recorded_at_utc
      ], "P3 TIK executed Gate observation")
      gate_key = observation.fetch("gate_key")
      assert(observation["schema_version"] == "p3-tik-gate-observation/v1" &&
             observation["record_type"] == "P3_TIK_GATE_OBSERVATION" &&
             observation["phase"] == "P3" && observation["route_id"] == TIK_ROUTE_ID &&
             observation["stage_ordinal"] == stage_index + 1 &&
             observation["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
             observation["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
             observation["candidate"] == manifest.fetch("candidate") &&
             expected_results.key?(gate_key),
             "P3 TIK executed Gate observation semantic binding drift")
      command = exact_keys(observation["command"], %w[cwd argv exit_code],
                           "P3 TIK executed Gate command")
      cwd = Pathname.new(command.fetch("cwd"))
      allowed_cwds = [resource.fetch("worktree"), resource.fetch("evidence_root")]
      assert(cwd.absolute? && cwd.cleanpath.to_s == cwd.to_s &&
             allowed_cwds.any? { |allowed| cwd.to_s == allowed || cwd.to_s.start_with?("#{allowed}/") } &&
             command["argv"].is_a?(Array) && !command["argv"].empty? &&
             command["argv"].all? { |part| part.is_a?(String) && !part.empty? } &&
             command["exit_code"].is_a?(Integer),
             "P3 TIK Gate command record is not closed")
      tik_timestamp!(observation["recorded_at_utc"],
                     "P3 TIK Gate observation recorded_at_utc")
      [gate_key, observation.fetch("observed_value"), command.fetch("exit_code")]
    end
    check_keys = observations.map(&:first)
    assert(check_keys.sort == expected_results.keys.sort && check_keys.uniq.length == check_keys.length,
           "P3 TIK Gate Evidence does not cover the exact frozen Gate set")
    observed_results = observations.to_h { |gate_key, observed_value, _exit_code| [gate_key, observed_value] }
    assert(gate_results == observed_results,
           "P3 TIK Gate results were not derived from the parsed observation bytes")
    allowed_dispositions = terminal ? %w[PASS_CANDIDATE NON_PASS_CANDIDATE] : ["PASS_CANDIDATE"]
    assert(evidence["schema_version"] == "p3-tik-gate-evidence/v1" &&
           evidence["record_type"] == "P3_TIK_GATE_EVIDENCE" && evidence["phase"] == "P3" &&
           evidence["route_id"] == TIK_ROUTE_ID && evidence["stage_ordinal"] == stage_index + 1 &&
           evidence["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           evidence["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           allowed_dispositions.include?(evidence["disposition"]) &&
           evidence["candidate_manifest"] == manifest_identity &&
           evidence["contract"] == contract_identity && evidence["authority"] == authority_identity &&
           evidence["generated_from_actual_bytes"] == true,
           "P3 TIK Gate Evidence semantic cross-binding drift")
    if evidence["disposition"] == "NON_PASS_CANDIDATE"
      assert(gate_results != expected_results ||
             observations.any? { |_gate_key, _observed_value, exit_code| exit_code != 0 },
             "P3 TIK NON_PASS Gate Evidence contains no mechanically recorded failure")
    else
      assert(gate_results == expected_results &&
             observations.all? { |_gate_key, _observed_value, exit_code| exit_code == 0 },
             "P3 TIK PASS Gate Evidence does not contain exact passing observations")
    end
    tik_timestamp!(evidence["recorded_at_utc"], "P3 TIK Gate Evidence recorded_at_utc")
    [evidence_identity, evidence]
  end

  def tik_validate_findings!(value, label, include_role: false)
    findings = array(value, label)
    findings.each do |finding|
      keys = %w[finding_id severity category summary]
      keys << "role" if include_role
      exact_keys(finding, keys, label)
      assert(finding["finding_id"].is_a?(String) && !finding["finding_id"].empty? &&
             %w[P0 P1].include?(finding["severity"]) &&
             TIK_FINDING_CATEGORIES.include?(finding["category"]) &&
             finding["summary"].is_a?(String) && !finding["summary"].empty? &&
             (!include_role || TIK_REVIEW_ROLES.include?(finding["role"])),
             "#{label} schema drift")
    end
    findings
  end

  def validate_tik_review_record!(identity, role, stage_index, contract_identity,
                                  authority_identity, manifest_identity,
                                  gate_evidence_identity, expected_path:, expected_cycle:)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    review_identity, review = read_tik_rooted_json!(
      identity, "P3 TIK #{role} review", root_path: resource.fetch("evidence_root"),
      expected_path: expected_path
    )
    exact_keys(review, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id role review_cycle
      candidate_manifest gate_evidence contract authority independence verdict finding_categories
      blocking_findings cycle_1_review cycle_1_finding_set cycle_2_closure reviewed_at_utc
    ], "P3 TIK independent review")
    findings = tik_validate_findings!(review["blocking_findings"], "P3 TIK blocking finding")
    finding_ids = findings.map { |finding| finding.fetch("finding_id") }
    assert(finding_ids.uniq.length == finding_ids.length,
           "P3 TIK review contains duplicate finding identities")
    categories = array(review["finding_categories"], "P3 TIK review finding categories")
    assert(categories.uniq.length == categories.length &&
           categories.all? { |category| TIK_FINDING_CATEGORIES.include?(category) } &&
           findings.map { |finding| finding["category"] }.uniq.sort == categories.sort,
           "P3 TIK review finding-category binding drift")
    assert(review["schema_version"] == "p3-tik-independent-review/v1" &&
           review["record_type"] == "P3_TIK_INDEPENDENT_REVIEW" && review["phase"] == "P3" &&
           review["route_id"] == TIK_ROUTE_ID && review["stage_ordinal"] == stage_index + 1 &&
           review["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           review["task_id"] == TIK_TASK_IDS.fetch(stage_index) && review["role"] == role &&
           review["review_cycle"] == expected_cycle &&
           review["candidate_manifest"] == manifest_identity &&
           review["gate_evidence"] == gate_evidence_identity &&
           review["contract"] == contract_identity && review["authority"] == authority_identity &&
           review["independence"] == {
             "implemented_candidate" => false, "issued_task_authority" => false
           } && %w[PASS NON_PASS].include?(review["verdict"]),
           "P3 TIK independent review cross-binding drift")
    if review["verdict"] == "PASS"
      assert(findings.empty? && categories.empty?, "P3 TIK PASS review retains blocking findings")
    else
      assert(!findings.empty?, "P3 TIK NON_PASS review lacks a blocking finding")
    end
    tik_timestamp!(review["reviewed_at_utc"], "P3 TIK review reviewed_at_utc")
    [review_identity, review]
  end

  def validate_tik_cycle_1_finding_set!(root, identity, stage_index, contract_identity,
                                        authority_identity, activation_parent, terminal: false)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    finding_set_identity, finding_set = read_tik_rooted_json!(
      identity, "P3 TIK Cycle 1 frozen finding set",
      root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("cycle_1_finding_set_path")
    )
    exact_keys(finding_set, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id contract authority
      cycle_1_candidate_manifest cycle_1_gate_evidence cycle_1_reviews
      complete_p0_p1_set_frozen findings frozen_at_utc
    ], "P3 TIK Cycle 1 frozen finding set")
    manifest_identity, manifest, = validate_tik_candidate_manifest!(
      root, finding_set["cycle_1_candidate_manifest"], stage_index, contract_identity,
      authority_identity, activation_parent,
      terminal: terminal,
      expected_path: resource.fetch("cycle_1_candidate_manifest_path"),
      expected_candidate_id: "CANDIDATE_1"
    )
    gate_identity, = validate_tik_gate_evidence!(
      finding_set["cycle_1_gate_evidence"], stage_index, contract_identity, authority_identity,
      manifest_identity, manifest, terminal: false,
      expected_path: resource.fetch("cycle_1_gate_evidence_path")
    )
    review_projection = exact_keys(finding_set["cycle_1_reviews"],
                                   %w[cto security quality_evaluation],
                                   "P3 TIK Cycle 1 review identities")
    reviews = {}
    {
      "cto" => ["CTO_AGENT", "cycle_1_cto_review_path"],
      "security" => ["SECURITY_AGENT", "cycle_1_security_review_path"],
      "quality_evaluation" => ["QUALITY_EVALUATION_AGENT", "cycle_1_quality_review_path"]
    }.each do |key, (role, path_key)|
      review_identity, review = validate_tik_review_record!(
        review_projection.fetch(key), role, stage_index, contract_identity, authority_identity,
        manifest_identity, gate_identity, expected_path: resource.fetch(path_key), expected_cycle: 1
      )
      assert(review["cycle_1_review"].nil? && review["cycle_1_finding_set"].nil? &&
             review["cycle_2_closure"].nil?,
             "P3 TIK Cycle 1 review contains a future-cycle projection")
      assert(review_identity == review_projection.fetch(key),
             "P3 TIK Cycle 1 review identity projection drift")
      reviews[role] = review
    end
    expected_findings = reviews.flat_map do |role, review|
      review.fetch("blocking_findings").map { |finding| finding.merge("role" => role) }
    end.sort_by { |finding| [finding.fetch("role"), finding.fetch("finding_id")] }
    frozen_findings = tik_validate_findings!(
      finding_set["findings"], "P3 TIK Cycle 1 frozen finding", include_role: true
    )
    frozen_ids = frozen_findings.map { |finding| finding.fetch("finding_id") }
    assert(frozen_findings == expected_findings && !frozen_findings.empty? &&
           frozen_ids.uniq.length == frozen_ids.length &&
           finding_set["schema_version"] == "p3-tik-cycle-1-finding-set/v1" &&
           finding_set["record_type"] == "P3_TIK_CYCLE_1_FROZEN_FINDING_SET" &&
           finding_set["phase"] == "P3" && finding_set["route_id"] == TIK_ROUTE_ID &&
           finding_set["stage_ordinal"] == stage_index + 1 &&
           finding_set["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           finding_set["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           finding_set["contract"] == contract_identity &&
           finding_set["authority"] == authority_identity &&
           finding_set["cycle_1_candidate_manifest"] == manifest_identity &&
           finding_set["cycle_1_gate_evidence"] == gate_identity &&
           finding_set["complete_p0_p1_set_frozen"] == true,
           "P3 TIK Cycle 1 frozen finding-set binding drift")
    tik_timestamp!(finding_set["frozen_at_utc"], "P3 TIK Cycle 1 finding-set frozen_at_utc")
    [finding_set_identity, reviews, frozen_findings]
  end

  def validate_tik_review!(root, identity, role, stage_index, contract_identity,
                           authority_identity, activation_parent, manifest_identity,
                           gate_evidence_identity, terminal: false)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    path_key = {
      "CTO_AGENT" => "cto_review_path", "SECURITY_AGENT" => "security_review_path",
      "QUALITY_EVALUATION_AGENT" => "quality_review_path"
    }.fetch(role)
    # Read once to select the frozen one- or two-cycle schema, then re-read through the exact verifier.
    preview_identity, preview = read_tik_rooted_json!(
      identity, "P3 TIK #{role} review", root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch(path_key)
    )
    cycle = preview["review_cycle"]
    assert([1, 2].include?(cycle) && !(stage_index == 2 && cycle == 2),
           "P3 TIK review cycle exceeds the stage budget")
    review_identity, review = validate_tik_review_record!(
      preview_identity, role, stage_index, contract_identity, authority_identity,
      manifest_identity, gate_evidence_identity,
      expected_path: resource.fetch(path_key), expected_cycle: cycle
    )
    if cycle == 1
      assert(review["cycle_1_review"].nil? && review["cycle_1_finding_set"].nil? &&
             review["cycle_2_closure"].nil?,
             "P3 TIK Cycle 1 final review contains a future-cycle projection")
    else
      finding_set_identity, cycle_1_reviews, frozen_findings =
        validate_tik_cycle_1_finding_set!(
          root, review["cycle_1_finding_set"], stage_index, contract_identity,
          authority_identity, activation_parent, terminal: terminal
        )
      assert(review["cycle_1_finding_set"] == finding_set_identity,
             "P3 TIK Cycle 2 review finding-set identity drift")
      prior_review = cycle_1_reviews.fetch(role)
      prior_identity_key = {
        "CTO_AGENT" => "cycle_1_cto_review_path",
        "SECURITY_AGENT" => "cycle_1_security_review_path",
        "QUALITY_EVALUATION_AGENT" => "cycle_1_quality_review_path"
      }.fetch(role)
      prior_identity = exact_keys(review["cycle_1_review"], %w[path byte_length sha256],
                                  "P3 TIK Cycle 2 prior review identity")
      assert(prior_identity.fetch("path") == resource.fetch(prior_identity_key) &&
             prior_review["role"] == role,
             "P3 TIK Cycle 2 review is not bound to its exact Cycle 1 review")
      read_tik_external_identity!(prior_identity, "P3 TIK Cycle 2 prior review", create_once: true)
      closure = exact_keys(review["cycle_2_closure"],
                           %w[closed_finding_ids unresolved_finding_ids regression_findings],
                           "P3 TIK Cycle 2 closure")
      initial_ids = prior_review.fetch("blocking_findings").map { |finding| finding.fetch("finding_id") }
      closed = array(closure["closed_finding_ids"], "P3 TIK closed Cycle 1 findings")
      unresolved = array(closure["unresolved_finding_ids"], "P3 TIK unresolved Cycle 1 findings")
      regressions = tik_validate_findings!(closure["regression_findings"],
                                           "P3 TIK Cycle 2 direct regression")
      regression_ids = regressions.map { |finding| finding.fetch("finding_id") }
      globally_frozen_ids = frozen_findings.map { |finding| finding.fetch("finding_id") }
      assert(closed.uniq.length == closed.length && unresolved.uniq.length == unresolved.length &&
             regression_ids.uniq.length == regression_ids.length &&
             (regression_ids & globally_frozen_ids).empty? &&
             (closed & unresolved).empty? && (closed + unresolved).sort == initial_ids.sort,
             "P3 TIK Cycle 2 closure does not partition the frozen Cycle 1 finding set")
      expected_current_findings = prior_review.fetch("blocking_findings").select do |finding|
        unresolved.include?(finding.fetch("finding_id"))
      end + regressions
      current_findings = review.fetch("blocking_findings")
      assert(current_findings.sort_by { |finding| finding.fetch("finding_id") } ==
               expected_current_findings.sort_by { |finding| finding.fetch("finding_id") },
             "P3 TIK Cycle 2 review drip-fed a non-frozen, non-regression finding")
      if review["verdict"] == "PASS"
        assert(unresolved.empty? && regressions.empty? && closed.sort == initial_ids.sort,
               "P3 TIK Cycle 2 PASS did not close the complete frozen finding set")
      end
      assert(frozen_findings == frozen_findings.sort_by do |finding|
               [finding.fetch("role"), finding.fetch("finding_id")]
             end, "P3 TIK frozen finding set ordering drift")
    end
    [review_identity, review]
  end

  def validate_tik_terminal_bundle!(root, bundle, stage_index, activation_parent,
                                    candidate, manifest)
    bundle_path = bundle.fetch("path")
    _verify_out, verify_err, verify_status = Open3.capture3(
      "git", "bundle", "verify", bundle_path, chdir: root.to_s
    )
    assert(verify_status.success?,
           "P3 TIK rejected candidate bundle verification failed: #{verify_err.strip}")
    expected_ref = "refs/heads/#{candidate.fetch('source_branch')}"
    heads = git!(root, "bundle", "list-heads", bundle_path).lines.map(&:strip)
    assert(heads == ["#{candidate.fetch('commit')} #{expected_ref}"],
           "P3 TIK rejected candidate bundle does not contain the exact sole candidate head")

    evidence_root = TIK_STAGE_RESOURCES.fetch(stage_index).fetch("evidence_root")
    terminal_root = Pathname.new(evidence_root).join("terminal")
    terminal_stat = terminal_root.lstat
    assert(terminal_stat.directory? && !terminal_root.symlink? &&
           terminal_root.realpath.to_s == terminal_root.cleanpath.to_s,
           "P3 TIK terminal bundle verifier root is not a real authorized directory")
    Dir.mktmpdir(".p3-tik-bundle-verifier-", terminal_root.to_s) do |temporary_root|
      replay = Pathname.new(temporary_root).join("candidate.git")
      _init_out, init_err, init_status = Open3.capture3("git", "init", "--bare", replay.to_s)
      assert(init_status.success?, "P3 TIK bundle replay init failed: #{init_err.strip}")
      _fetch_out, fetch_err, fetch_status = Open3.capture3(
        "git", "-C", replay.to_s, "fetch", "--no-tags", bundle_path,
        "#{expected_ref}:refs/heads/candidate"
      )
      assert(fetch_status.success?,
             "P3 TIK rejected candidate bundle is not self-contained: #{fetch_err.strip}")
      assert(git!(replay, "rev-parse", "refs/heads/candidate") == candidate.fetch("commit") &&
             git!(replay, "rev-parse", "#{candidate.fetch('commit')}^{tree}") ==
               candidate.fetch("tree"),
             "P3 TIK bundle candidate commit/tree drift")
      if stage_index == 2
        git!(root, "merge-base", "--is-ancestor", candidate.fetch("commit"),
             activation_parent.fetch("commit"))
        assert(manifest.fetch("repository_files").empty?,
               "P3 TIK Audit terminal bundle unexpectedly carries repository mutations")
      else
        git!(replay, "merge-base", "--is-ancestor", activation_parent.fetch("commit"),
             candidate.fetch("commit"))
        changed = git!(
          replay, "diff", "--name-status", "--diff-filter=ACMRD",
          activation_parent.fetch("commit"), candidate.fetch("commit")
        ).lines.map(&:strip).reject(&:empty?).map do |line|
          status, path, unexpected = line.split("\t", 3)
          assert(unexpected.nil? && %w[A M].include?(status) && path,
                 "P3 TIK terminal bundle contains deletion, rename, copy or unknown delta")
          path
        end.sort
        expected_paths = manifest.fetch("repository_files").map do |entry|
          replay_tree_entry = tik_git_tree_entry!(
            replay, candidate.fetch("commit"), entry.fetch("relative_path"),
            "P3 TIK terminal bundle candidate file"
          )
          assert(replay_tree_entry == entry.slice("git_mode", "object_type", "git_blob_sha1"),
                 "P3 TIK terminal bundle mode/type/blob differs from the immutable manifest")
          bytes = tik_git_bytes!(replay, candidate.fetch("commit"), entry.fetch("relative_path"),
                                 "P3 TIK terminal bundle candidate file")
          assert(bytes.bytesize == entry.fetch("byte_length") &&
                 Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
                 "P3 TIK terminal bundle candidate bytes differ from the immutable manifest")
          entry.fetch("relative_path")
        end.sort
        assert(changed == expected_paths && !changed.empty?,
               "P3 TIK terminal bundle changed set differs from the immutable manifest")
      end
    end
  end

  def validate_tik_bundle_attestation!(root, identity, stage_index, activation_parent,
                                       contract_identity, authority_identity, manifest_identity,
                                       candidate, bundle)
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    attestation_identity, attestation = read_tik_rooted_json!(
      identity, "P3 TIK rejected-bundle verification attestation",
      root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("bundle_attestation_path")
    )
    exact_keys(attestation, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id
      activation_parent contract authority candidate_manifest candidate bundle validator
      checks verified_while_task_active future_current_state_lineage_replay_allowed
      verified_at_utc
    ], "P3 TIK rejected-bundle verification attestation")
    validator = exact_keys(attestation["validator"],
                           %w[path commit tree byte_length sha256],
                           "P3 TIK terminalization validator identity")
    validator_bytes = tik_git_bytes!(
      root, activation_parent.fetch("commit"), validator.fetch("path"),
      "P3 TIK terminalization validator"
    )
    checks = exact_keys(attestation["checks"], %w[
      bundle_verify_pass sole_head_matches_candidate candidate_commit_tree_matches
      activation_parent_relation_matches changed_set_matches_manifest
      repository_bytes_match_manifest git_mode_type_blob_match_manifest
      rejected_lineage_replay_count
    ], "P3 TIK rejected-bundle verification checks")
    assert(attestation["schema_version"] == "p3-tik-rejected-bundle-attestation/v1" &&
           attestation["record_type"] == "P3_TIK_REJECTED_BUNDLE_VERIFICATION_ATTESTATION" &&
           attestation["phase"] == "P3" && attestation["route_id"] == TIK_ROUTE_ID &&
           attestation["stage_ordinal"] == stage_index + 1 &&
           attestation["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           attestation["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           attestation["activation_parent"] == activation_parent &&
           attestation["contract"] == contract_identity &&
           attestation["authority"] == authority_identity &&
           attestation["candidate_manifest"] == manifest_identity &&
           attestation["candidate"] == candidate && attestation["bundle"] == bundle &&
           validator["path"] == "scripts/validate-p3-final-transactional-route.rb" &&
           validator["commit"] == activation_parent.fetch("commit") &&
           validator["tree"] == activation_parent.fetch("tree") &&
           validator_bytes.bytesize == validator["byte_length"] &&
           Digest::SHA256.hexdigest(validator_bytes) == validator["sha256"] &&
           checks == {
             "bundle_verify_pass" => true, "sole_head_matches_candidate" => true,
             "candidate_commit_tree_matches" => true,
             "activation_parent_relation_matches" => true,
             "changed_set_matches_manifest" => true,
             "repository_bytes_match_manifest" => true,
             "git_mode_type_blob_match_manifest" => true,
             "rejected_lineage_replay_count" => 1
           } && attestation["verified_while_task_active"] == true &&
           attestation["future_current_state_lineage_replay_allowed"] == false,
           "P3 TIK rejected-bundle verification attestation semantic drift")
    tik_timestamp!(attestation["verified_at_utc"],
                   "P3 TIK rejected-bundle attestation verified_at_utc")
    [attestation_identity, attestation]
  end

  def tik_identity_for_exact_create_once_file!(path_string, root_path, label)
    tik_assert_path_under!(path_string, root_path, label, expected_path: path_string)
    path = Pathname.new(path_string)
    stat = path.lstat
    assert(stat.file? && !path.symlink? && (stat.mode & 0o777) == 0o444 && stat.nlink == 1,
           "#{label} is not an immutable single-link regular file")
    bytes = path.binread
    identity = {
      "path" => path.to_s,
      "byte_length" => bytes.bytesize,
      "sha256" => Digest::SHA256.hexdigest(bytes)
    }
    read_tik_external_identity!(identity, label, create_once: true)
    identity
  rescue Errno::ENOENT, Errno::ELOOP => e
    raise P3FinalTransactionalRouteValidationError, "#{label} unavailable: #{e.message}"
  end

  def tik_reserve_exclusive_create_once_file!(path_string, root_path, label)
    tik_assert_path_under!(path_string, root_path, label, expected_path: path_string)
    path = Pathname.new(path_string)
    flags = File::WRONLY | File::CREAT | File::EXCL
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    [path, File.open(path.to_s, flags, 0o400)]
  rescue Errno::EEXIST, Errno::ELOOP => e
    raise P3FinalTransactionalRouteValidationError, "#{label} one-shot reservation failed: #{e.message}"
  end

  def tik_finalize_reserved_create_once_json!(path, file, value, label)
    bytes = JSON.pretty_generate(value) + "\n"
    begin
      written = file.write(bytes)
      assert(written == bytes.bytesize, "#{label} short write")
      file.flush
      file.fsync
      file.chmod(0o444)
    ensure
      file.close unless file.closed?
    end
    identity = {
      "path" => path.to_s,
      "byte_length" => bytes.bytesize,
      "sha256" => Digest::SHA256.hexdigest(bytes)
    }
    read_tik_external_identity!(identity, label, create_once: true)
    identity
  end

  def create_tik_terminal_bundle_attestation!(root:, truth:)
    state = validate_truth!(root: root, truth: truth)
    lifecycle = truth.dig("current_phase_route", "lifecycle_stage")
    stage_index = {
      "FOUNDATION_TASK_ACTIVE" => 0,
      "PRODUCT_TASK_ACTIVE" => 1
    }[lifecycle]
    assert(stage_index && state == TIK_LIFECYCLE_STATES.fetch(lifecycle),
           "P3 TIK rejected-bundle attestation is allowed only while a mutable stage Task is active")
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    active = mapping(truth["active_work"], "P3 TIK active work for terminalization")
    contract_identity, _contract, activation_parent = validate_tik_contract!(
      root, active.fetch("current_task_contract"), stage_index
    )
    authority_identity, _authority = validate_tik_authority!(
      root, active.fetch("authority_record"), stage_index, contract_identity, activation_parent
    )
    manifest_identity = tik_identity_for_exact_create_once_file!(
      resource.fetch("candidate_manifest_path"), resource.fetch("evidence_root"),
      "P3 TIK terminalization candidate manifest"
    )
    manifest_identity, manifest, candidate = validate_tik_candidate_manifest!(
      root, manifest_identity, stage_index, contract_identity, authority_identity,
      activation_parent, terminal: false
    )
    bundle_identity = tik_identity_for_exact_create_once_file!(
      resource.fetch("rejected_bundle_path"), resource.fetch("evidence_root"),
      "P3 TIK rejected candidate bundle"
    )
    attestation_path, attestation_file = tik_reserve_exclusive_create_once_file!(
      resource.fetch("bundle_attestation_path"), resource.fetch("evidence_root"),
      "P3 TIK rejected-bundle verification attestation"
    )
    begin
      validate_tik_terminal_bundle!(
        root, bundle_identity, stage_index, activation_parent, candidate, manifest
      )
      validator_path = "scripts/validate-p3-final-transactional-route.rb"
      validator_bytes = tik_git_bytes!(
        root, activation_parent.fetch("commit"), validator_path,
        "P3 TIK terminalization validator"
      )
      attestation = {
        "schema_version" => "p3-tik-rejected-bundle-attestation/v1",
        "record_type" => "P3_TIK_REJECTED_BUNDLE_VERIFICATION_ATTESTATION",
        "phase" => "P3",
        "route_id" => TIK_ROUTE_ID,
        "stage_ordinal" => stage_index + 1,
        "stage_id" => TIK_STAGE_IDS.fetch(stage_index),
        "task_id" => TIK_TASK_IDS.fetch(stage_index),
        "activation_parent" => activation_parent,
        "contract" => contract_identity,
        "authority" => authority_identity,
        "candidate_manifest" => manifest_identity,
        "candidate" => candidate,
        "bundle" => bundle_identity,
        "validator" => {
          "path" => validator_path,
          "commit" => activation_parent.fetch("commit"),
          "tree" => activation_parent.fetch("tree"),
          "byte_length" => validator_bytes.bytesize,
          "sha256" => Digest::SHA256.hexdigest(validator_bytes)
        },
        "checks" => {
          "bundle_verify_pass" => true,
          "sole_head_matches_candidate" => true,
          "candidate_commit_tree_matches" => true,
          "activation_parent_relation_matches" => true,
          "changed_set_matches_manifest" => true,
          "repository_bytes_match_manifest" => true,
          "git_mode_type_blob_match_manifest" => true,
          "rejected_lineage_replay_count" => 1
        },
        "verified_while_task_active" => true,
        "future_current_state_lineage_replay_allowed" => false,
        "verified_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      }
      identity = tik_finalize_reserved_create_once_json!(
        attestation_path, attestation_file, attestation,
        "P3 TIK rejected-bundle verification attestation"
      )
    ensure
      attestation_file.close unless attestation_file.closed?
    end
    validate_tik_bundle_attestation!(
      root, identity, stage_index, activation_parent, contract_identity, authority_identity,
      manifest_identity, candidate, bundle_identity
    )
    identity
  end

  def validate_tik_stage_receipt!(root, completed, stage_index, terminal: false)
    receipt_key = terminal ? "terminal_receipt" : "task_gate_receipt"
    expected_completed_keys = %w[
      task_id status contract authority candidate_manifest gate_evidence independent_reviews
    ] + [receipt_key]
    exact_keys(completed, expected_completed_keys, "P3 TIK completed Task projection")
    expected_status = terminal ? "TERMINAL_TASK_GATE_NON_PASS" : "ACCEPTED_TASK_GATE_PASS"
    assert(completed["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           completed["status"] == expected_status,
           "P3 TIK completed Task identity or disposition drift")
    contract_identity, _contract, activation_parent = validate_tik_contract!(
      root, completed["contract"], stage_index
    )
    authority_identity, authority = validate_tik_authority!(
      root, completed["authority"], stage_index, contract_identity, activation_parent
    )
    manifest_identity, manifest, candidate = validate_tik_candidate_manifest!(
      root, completed["candidate_manifest"], stage_index, contract_identity, authority_identity,
      activation_parent, terminal: terminal
    )
    gate_evidence_identity, gate_evidence = validate_tik_gate_evidence!(
      completed["gate_evidence"], stage_index, contract_identity, authority_identity,
      manifest_identity, manifest, terminal: terminal
    )
    review_projection = exact_keys(completed["independent_reviews"],
                                   %w[cto security quality_evaluation],
                                   "P3 TIK completed review identities")
    reviews = {}
    {
      "cto" => "CTO_AGENT", "security" => "SECURITY_AGENT",
      "quality_evaluation" => "QUALITY_EVALUATION_AGENT"
    }.each do |key, role|
      identity_record, review = validate_tik_review!(
        root, review_projection.fetch(key), role, stage_index, contract_identity,
        authority_identity, activation_parent, manifest_identity, gate_evidence_identity,
        terminal: terminal
      )
      assert(identity_record == review_projection.fetch(key),
             "P3 TIK review identity projection drift")
      reviews[key] = review
    end
    resource = TIK_STAGE_RESOURCES.fetch(stage_index)
    expected_receipt_path = resource.fetch(
      terminal ? "task_gate_non_pass_receipt_path" : "task_gate_pass_receipt_path"
    )
    receipt_identity, receipt = read_tik_rooted_json!(
      completed.fetch(receipt_key), "P3 TIK stage Gate receipt",
      root_path: resource.fetch("evidence_root"), expected_path: expected_receipt_path
    )
    exact_keys(receipt, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id disposition contract
      authority candidate_manifest gate_evidence independent_reviews gate_results integration
      budget_consumption next_lifecycle delivery_percent strict_exit_percent external_effects
      recorded_at_utc
    ], "P3 TIK stage Gate receipt")
    assert(receipt["schema_version"] == "p3-tik-stage-gate-receipt/v1" &&
           receipt["record_type"] == "P3_TIK_STAGE_GATE_RECEIPT" && receipt["phase"] == "P3" &&
           receipt["route_id"] == TIK_ROUTE_ID && receipt["stage_ordinal"] == stage_index + 1 &&
           receipt["stage_id"] == TIK_STAGE_IDS.fetch(stage_index) &&
           receipt["task_id"] == TIK_TASK_IDS.fetch(stage_index) &&
           receipt["disposition"] == expected_status && receipt["contract"] == contract_identity &&
           receipt["authority"] == authority_identity &&
           receipt["candidate_manifest"] == manifest_identity &&
           receipt["gate_evidence"] == gate_evidence_identity &&
           receipt["independent_reviews"] == review_projection &&
           receipt["external_effects"] == TIK_EXTERNAL_EFFECTS,
           "P3 TIK stage Gate receipt cross-binding drift")
    gate_results = exact_keys(receipt["gate_results"], TIK_PASS_GATE_RESULTS.fetch(stage_index).keys,
                              "P3 TIK stage Gate results")
    assert(gate_results == gate_evidence.fetch("gate_results"),
           "P3 TIK stage Gate receipt does not bind the parsed Gate Evidence results")
    if terminal
      assert(reviews.values.any? { |review| review["verdict"] == "NON_PASS" },
             "P3 TIK terminal receipt lacks an independent NON_PASS verdict")
    else
      assert(reviews.values.all? { |review| review["verdict"] == "PASS" } &&
             gate_results == TIK_PASS_GATE_RESULTS.fetch(stage_index),
             "P3 TIK PASS receipt lacks exact Gate results or three independent PASS reviews")
    end
    integration = exact_keys(receipt["integration"], %w[
      candidate_commit candidate_tree integrated canonical_main_commit canonical_main_tree
      integration_delta_files rejected_candidate_bundle bundle_verification_attestation
    ], "P3 TIK receipt integration")
    assert(integration["candidate_commit"] == candidate["commit"] &&
           integration["candidate_tree"] == candidate["tree"],
           "P3 TIK receipt candidate identity drift")
    if terminal
      assert(integration["integrated"] == false && integration["canonical_main_commit"].nil? &&
             integration["canonical_main_tree"].nil? &&
             integration["integration_delta_files"] == [],
             "P3 TIK terminal candidate cannot be integrated")
      if stage_index < 2
        bundle = exact_keys(integration["rejected_candidate_bundle"],
                            %w[path byte_length sha256], "P3 TIK rejected candidate bundle")
        tik_assert_path_under!(
          bundle.fetch("path"), resource.fetch("evidence_root"),
          "P3 TIK rejected candidate bundle", expected_path: resource.fetch("rejected_bundle_path")
        )
        read_tik_external_identity!(bundle, "P3 TIK rejected candidate bundle", create_once: true)
        validate_tik_bundle_attestation!(
          root, integration["bundle_verification_attestation"], stage_index,
          activation_parent, contract_identity, authority_identity, manifest_identity,
          candidate, bundle
        )
      else
        assert(integration["rejected_candidate_bundle"].nil? &&
               integration["bundle_verification_attestation"].nil?,
               "P3 TIK Audit terminal receipt cannot reopen the already accepted Product lineage")
      end
    else
      assert(integration["integrated"] == true && integration["rejected_candidate_bundle"].nil? &&
             integration["bundle_verification_attestation"].nil? &&
             integration["canonical_main_commit"].is_a?(String) &&
             integration["canonical_main_commit"].match?(/\A[0-9a-f]{40}\z/) &&
             integration["canonical_main_tree"].is_a?(String) &&
             git!(root, "rev-parse", "#{integration.fetch('canonical_main_commit')}^{tree}") ==
               integration.fetch("canonical_main_tree"),
             "P3 TIK PASS receipt lacks an exact canonical integration identity")
      git!(root, "merge-base", "--is-ancestor", candidate.fetch("commit"),
           integration.fetch("canonical_main_commit"))
      git!(root, "merge-base", "--is-ancestor", integration.fetch("canonical_main_commit"), "main")
      integration_delta = array(integration["integration_delta_files"],
                                "P3 TIK integration delta inventory")
      delta_paths = integration_delta.map do |entry|
        exact_keys(entry, %w[relative_path byte_length sha256],
                   "P3 TIK integration delta identity")
        path = entry.fetch("relative_path")
        assert(path == "docs/aios/truth/project_state.yaml" &&
               entry["byte_length"].is_a?(Integer) && entry["byte_length"].positive? &&
               entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[0-9a-f]{64}\z/),
               "P3 TIK integration delta exceeds the exact canonical Truth projection")
        bytes = tik_git_bytes!(root, integration.fetch("canonical_main_commit"), path,
                               "P3 TIK integration delta")
        assert(bytes.bytesize == entry.fetch("byte_length") &&
               Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
               "P3 TIK integration delta identity drift")
        path
      end
      assert(delta_paths == delta_paths.sort && delta_paths.uniq.length == delta_paths.length,
             "P3 TIK integration delta inventory must be unique and sorted")
      actual_delta_paths = git!(
        root, "diff", "--name-status", "--diff-filter=ACMRD", candidate.fetch("commit"),
        integration.fetch("canonical_main_commit")
      ).lines.map(&:strip).reject(&:empty?).map do |line|
        status, path, unexpected = line.split("\t", 3)
        assert(unexpected.nil? && %w[A M].include?(status) && path,
               "P3 TIK integration contains deletion, rename, copy or unknown delta")
        path
      end.sort
      assert(actual_delta_paths == delta_paths && delta_paths == ["docs/aios/truth/project_state.yaml"],
             "P3 TIK canonical integration is not the exact reviewed candidate plus Truth delta")
      manifest.fetch("repository_files").each do |entry|
        integrated_tree_entry = tik_git_tree_entry!(
          root, integration.fetch("canonical_main_commit"), entry.fetch("relative_path"),
          "P3 TIK integrated candidate file"
        )
        assert(integrated_tree_entry == entry.slice("git_mode", "object_type", "git_blob_sha1"),
               "P3 TIK integrated candidate mode/type/blob differs from the reviewed candidate")
        integrated_bytes = tik_git_bytes!(
          root, integration.fetch("canonical_main_commit"), entry.fetch("relative_path"),
          "P3 TIK integrated candidate file"
        )
        assert(integrated_bytes.bytesize == entry.fetch("byte_length") &&
               Digest::SHA256.hexdigest(integrated_bytes) == entry.fetch("sha256"),
               "P3 TIK integrated candidate bytes differ from the reviewed candidate")
      end
    end
    budget = exact_keys(receipt["budget_consumption"], %w[
      charged_budget candidate_generations_used same_task_repairs_used review_cycles_used
      formal_dispatches_used
    ], "P3 TIK receipt budget consumption")
    review_cycles = reviews.values.map { |review| review.fetch("review_cycle") }
    assert(review_cycles.uniq.length == 1 &&
           (review_cycles.first == 1 ||
            reviews.values.map { |review| review.fetch("cycle_1_finding_set") }.uniq.length == 1),
           "P3 TIK final reviews mix cycles or Cycle 1 finding sets")
    assert(budget["charged_budget"] == TIK_FULL_STAGE_BUDGETS.fetch(stage_index) &&
           budget["review_cycles_used"].is_a?(Integer) &&
           budget["review_cycles_used"].between?(1, 2) &&
           review_cycles.first == budget["review_cycles_used"],
           "P3 TIK receipt budget/review-cycle accounting drift")
    if stage_index == 2
      assert(budget["candidate_generations_used"] == 0 &&
             budget["same_task_repairs_used"] == 0 && budget["formal_dispatches_used"] == 1,
             "P3 TIK Audit budget or one-shot dispatch drift")
    else
      assert(budget["candidate_generations_used"].is_a?(Integer) &&
             budget["candidate_generations_used"].between?(1, 2) &&
             budget["same_task_repairs_used"].is_a?(Integer) &&
             budget["same_task_repairs_used"].between?(0, 1) &&
             budget["formal_dispatches_used"] == 0,
             "P3 TIK implementation/Foundation budget drift")
      if review_cycles.first == 2
        assert(candidate["candidate_id"] == "CANDIDATE_2" &&
               budget["candidate_generations_used"] == 2 &&
               budget["same_task_repairs_used"] == 1,
               "P3 TIK Cycle 2 review is not the one allowed Candidate 2 repair")
      end
    end
    expected_next = if terminal
      "ROUTE_TERMINAL_NON_PASS"
    else
      %w[PRODUCT_STAGE_ELIGIBLE AUDIT_STAGE_ELIGIBLE COMPLETE_AWAITING_FOUNDER_PHASE_GATE]
        .fetch(stage_index)
    end
    assert(receipt["next_lifecycle"] == expected_next &&
           receipt["delivery_percent"] == (terminal ? [25, 50, 75].fetch(stage_index) :
             [50, 75, 100].fetch(stage_index)) &&
           receipt["strict_exit_percent"] == (terminal ? 0 : [0, 0, 100].fetch(stage_index)),
           "P3 TIK receipt lifecycle/progress projection drift")
    tik_timestamp!(receipt["recorded_at_utc"], "P3 TIK receipt recorded_at_utc")
    assert(receipt_identity == completed.fetch(receipt_key),
           "P3 TIK terminal/PASS receipt identity projection drift")
    {
      "receipt" => receipt_identity,
      "authority" => authority,
      "candidate" => candidate,
      "manifest" => manifest,
      "manifest_identity" => manifest_identity,
      "gate_evidence_identity" => gate_evidence_identity,
      "terminal" => terminal
    }
  end

  def validate_tik_git_identity!(root, relative_path, identity, label)
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{TIK_ACTIVATION_PARENT.fetch('commit')}:#{relative_path}",
      chdir: root.to_s
    )
    assert(status.success?, "#{label} unavailable at activation parent: #{stderr.strip}")
    assert(bytes.bytesize == identity.fetch("byte_length") &&
           Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"),
           "#{label} activation-parent identity drift")
  end

  def validate_tik_decision!(root)
    tik_assert_path_under!(
      TIK_DECISION.fetch("path"),
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821",
      "P3 TIK Founder decision", expected_path: TIK_DECISION.fetch("path")
    )
    bytes = read_tik_external_identity!(
      TIK_DECISION, "P3 TIK Founder decision", create_once: true
    )
    decision = parse_tik_json!(bytes, "P3 TIK Founder decision")
    exact_keys(decision, %w[
      schema_version record_type decision_id authority source approved_at_utc source_reply
      canonical_start bound_predecessor_accounting reserved_triggers strategy_invariants
      installed_constitution route normative_requirements architecture_boundary lineage_boundary
      phase_accounting installation review_and_gate external_effects lifecycle
    ], "P3 TIK Founder decision")
    assert(decision["schema_version"] == TIK_DECISION_SCHEMA &&
           decision["record_type"] ==
             "sourcelens_aios_founder_p3_phase_route_rebaseline_decision" &&
           decision["decision_id"] == TIK_DECISION_ID &&
           decision["authority"] == "HUMAN_FOUNDER" &&
           decision["source"] == "CURRENT_DIRECT_FOUNDER_REPLY_EXACT_BODY",
           "P3 TIK Founder authority drift")
    tik_timestamp!(decision["approved_at_utc"], "P3 TIK Founder approved_at_utc")

    source = exact_keys(decision["source_reply"], %w[
      attachment_identity installed_copy_identity exact_bytes_equal canonicalization
      normative_source
    ], "P3 TIK Founder source reply")
    attachment = exact_keys(source["attachment_identity"], %w[path byte_length sha256],
                            "P3 TIK Founder attachment identity")
    installed = exact_keys(source["installed_copy_identity"],
                           %w[path byte_length sha256 mode nlink],
                           "P3 TIK installed Founder body identity")
    assert(attachment == {
      "path" => "/Users/lijunpeng/.codex/attachments/fcde1e74-f319-4f03-9545-a4162d359c5e/pasted-text.txt",
      "byte_length" => TIK_AUTHORIZATION_BODY.fetch("byte_length"),
      "sha256" => TIK_AUTHORIZATION_BODY.fetch("sha256")
    } && installed.slice("path", "byte_length", "sha256") == TIK_AUTHORIZATION_BODY &&
           installed["mode"] == "0444" && installed["nlink"] == 1 &&
           source["exact_bytes_equal"] == true &&
           source["canonicalization"] == "BYTE_EXACT_NO_TRANSFORMATION" &&
           source["normative_source"] == "INSTALLED_COPY_IDENTITY",
           "P3 TIK Founder source declaration drift")
    tik_assert_path_under!(
      TIK_AUTHORIZATION_BODY.fetch("path"),
      "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821",
      "P3 TIK Founder authorization body", expected_path: TIK_AUTHORIZATION_BODY.fetch("path")
    )
    source_bytes = read_tik_external_identity!(
      TIK_AUTHORIZATION_BODY, "P3 TIK Founder authorization body", create_once: true
    )
    attachment_bytes = read_tik_external_identity!(
      attachment, "P3 TIK current Founder attachment"
    )
    assert(attachment_bytes == source_bytes,
           "P3 TIK attachment and installed authorization body are not byte-exact equal")
    assert(source_bytes.lines.first&.chomp == TIK_DECISION_ID,
           "P3 TIK Founder authorization token drift")

    start = exact_keys(decision["canonical_start"], %w[
      branch commit tree main_clean single_canonical_worktree truth constitution
      master_execution_protocol founder_delegation_policy evaluation_protocol
    ], "P3 TIK canonical start")
    assert(start["branch"] == "main" &&
           start["commit"] == TIK_ACTIVATION_PARENT.fetch("commit") &&
           start["tree"] == TIK_ACTIVATION_PARENT.fetch("tree") &&
           start["main_clean"] == true && start["single_canonical_worktree"] == true &&
           start["truth"] == TIK_ACTIVATION_PARENT.fetch("truth") &&
           start["constitution"] == TIK_ACTIVATION_PARENT.fetch("constitution") &&
           start["master_execution_protocol"] == {
             "path" => "docs/aios/MASTER_EXECUTION_PROTOCOL.md", "version" => "1.0",
             "byte_length" => 9_591,
             "sha256" => "47c444c50c7521a7515dfb2fbee0c8c81cc72b32c42eba549d080eeb0c1bcedf"
           } && start["founder_delegation_policy"] == {
             "path" => "docs/aios/FOUNDER_DELEGATION_POLICY.md", "version" => "1.8",
             "byte_length" => 17_346,
             "sha256" => "12126e9617011b6395f187939c9a1d7860d84bd3832c1b1b67357fb017e1ee29"
           } && start["evaluation_protocol"] == {
             "path" => "docs/aios/EVALUATION_PROTOCOL.md", "version" => "1.1",
             "byte_length" => 10_127,
             "sha256" => "da029143561fbb3c213d4a358b25e085542c6cd26ae8150a53cbb5998177eed8"
           }, "P3 TIK canonical authority binding drift")
    assert(git!(root, "rev-parse", "#{start.fetch('commit')}^{tree}") == start.fetch("tree"),
           "P3 TIK activation-parent tree drift")
    validate_tik_git_identity!(root, start.dig("truth", "path"), start.fetch("truth"),
                               "P3 TIK preinstallation Truth")
    validate_tik_git_identity!(root, start.dig("constitution", "path"),
                               start.fetch("constitution"),
                               "P3 TIK preinstallation Constitution")
    %w[master_execution_protocol founder_delegation_policy evaluation_protocol].each do |key|
      read_repo_identity!(root, start.fetch(key), "P3 TIK bound #{key}")
    end

    predecessor = exact_keys(decision["bound_predecessor_accounting"], %w[
      prior_seven_task_ledger terminal_route_decision terminal_foundation_receipt
      p3_001_accepted_receipt
    ], "P3 TIK predecessor accounting")
    assert(predecessor["prior_seven_task_ledger"] == {
      "ref" => "historical_p3_final_transactional_route_hold_phase_execution_envelope.task_ledger",
      "entry_count" => 7,
      "canonicalization" => "RECURSIVE_KEY_SORT_COMPACT_JSON_UTF8",
      "canonical_byte_length" => 10_678,
      "canonical_sha256" =>
        "960671374bb73de0a941a1df787e8e22b59834337699f157f0d97029c9e751dc"
    }, "P3 TIK prior seven-Task ledger binding drift")
    old_decision = predecessor.fetch("terminal_route_decision")
    old_receipt = predecessor.fetch("terminal_foundation_receipt")
    assert(old_decision.slice("path", "byte_length", "sha256") == HOST_AUTHORIZED_DECISION &&
           old_decision["mode"] == "0444" && old_decision["nlink"] == 1,
           "P3 TIK old decision identity/accounting drift")
    assert(old_receipt.slice("path", "byte_length", "sha256") == TIK_OLD_TERMINAL_RECEIPT &&
           old_receipt["mode"] == "0444" && old_receipt["nlink"] == 1,
           "P3 TIK old terminal receipt identity/accounting drift")
    read_tik_external_identity!(HOST_AUTHORIZED_DECISION,
                                "P3 TIK old route decision identity", create_once: true)
    read_tik_external_identity!(TIK_OLD_TERMINAL_RECEIPT,
                                "P3 TIK old terminal receipt identity", create_once: true)
    p3_001 = predecessor.fetch("p3_001_accepted_receipt")
    assert(p3_001 == {
      "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p3-durable-execution-checkpoint-resume-20260819/task-p3-001/terminal/P3_001_TASK_GATE_PASS_INTEGRATION_RECEIPT_V1.json",
      "byte_length" => 3_055,
      "sha256" => "e4ea37f8e6770b8dea9f8939f81444f01ebca4104a8dd2f84d33c4787180e2c0"
    }, "P3 TIK accepted P3-001 receipt identity drift")
    read_tik_external_identity!(p3_001, "P3 TIK accepted P3-001 receipt identity")

    assert(decision["reserved_triggers"] == [
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
      "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
    ], "P3 TIK reserved-trigger set drift")
    strategy = exact_keys(decision["strategy_invariants"], %w[
      constitution_from constitution_to change mission_changed icp_changed year_one_outcome_changed
      p3_objective_changed p3_strict_exit_gate_changed strict_phase_sequence_changed
      p3_delivery_percent_at_install p3_strict_exit_percent_at_install p3_001_status
      p4_entry_authorized project_actual_completion long_term_goal_status
    ], "P3 TIK strategy invariants")
    assert(strategy["constitution_from"] == "2.7" && strategy["constitution_to"] == "2.8" &&
           strategy["change"] == "APPEND_ONLY_DECISION_BINDING_ONLY" &&
           %w[mission_changed icp_changed year_one_outcome_changed p3_objective_changed
              p3_strict_exit_gate_changed strict_phase_sequence_changed p4_entry_authorized
              project_actual_completion].all? { |key| strategy[key] == false } &&
           strategy["p3_delivery_percent_at_install"] == 25 &&
           strategy["p3_strict_exit_percent_at_install"] == 0 &&
           strategy["p3_001_status"] == "ACCEPTED" &&
           strategy["long_term_goal_status"] == "ACTIVE",
           "P3 TIK strategy boundary drift")
    assert(decision["installed_constitution"] == TIK_CONSTITUTION.merge(
      "phase_route_section_byte_length" => 4_047,
      "phase_route_section_sha256" =>
        "c5bb58c7d745031f8e3f223dd0a84449e6039f575ad8fa67ade7ec922db8444a"
    ), "P3 TIK installed Constitution identity drift")
    read_repo_identity!(root, TIK_CONSTITUTION, "P3 TIK installed Constitution")

    route = exact_keys(decision["route"], %w[
      route_id route_kind evidence_root status_after_installation critical_path workflow stages
    ], "P3 TIK decision route")
    assert(route["route_id"] == TIK_ROUTE_ID &&
           route["route_kind"] ==
             "FOUNDER_AUTHORIZED_ARCHITECTURALLY_DISTINCT_CLEAN_ROOM_PHASE_ROUTE" &&
           route["evidence_root"] ==
             "/Users/lijunpeng/Developer/.sourcelens-audit/p3-trusted-invocation-kernel-process-real-20260821" &&
           route["status_after_installation"] == "ACTIVE_FOUNDATION_STAGE_ELIGIBLE" &&
           route["critical_path"] == TIK_TASK_IDS,
           "P3 TIK decision route identity drift")
    assert(exact_keys(route["workflow"], %w[
      workflow_id agent_input_role host_executable fixed_argv_prefix host_sandbox_executable
      effect_class
    ], "P3 TIK workflow") == {
      "workflow_id" => "VERIFY_CUSTODY_SHA256_V1",
      "agent_input_role" => "NON_AUTHORITATIVE_CLOSED_SCHEMA_PROPOSAL_ONLY",
      "host_executable" => "/usr/bin/openssl", "fixed_argv_prefix" => %w[dgst -sha256],
      "host_sandbox_executable" => "/usr/bin/sandbox-exec",
      "effect_class" => "LOCAL_READ_ONLY_IDEMPOTENT_CUSTODY_SHA256_VERIFICATION"
    }, "P3 TIK fixed workflow drift")
    stages = array(route["stages"], "P3 TIK decision stages")
    exact_keys(stages.fetch(0), %w[
      ordinal task_id stage_id kind status_after_installation budget
      product_source_mutation_allowed required_subject_protocol required_durability
      pass_delivery_percent pass_strict_exit_percent pass_unlocks_only resources
    ], "P3 TIK Foundation stage")
    exact_keys(stages.fetch(1), %w[
      ordinal task_id stage_id kind status_after_installation budget product_source_diff_required
      stage_1_mutation_allowed pass_delivery_percent pass_strict_exit_percent pass_unlocks_only
      resources
    ], "P3 TIK Product stage")
    exact_keys(stages.fetch(2), %w[
      ordinal task_id stage_id kind status_after_installation budget rerun_to_pass_allowed
      pass_delivery_percent pass_strict_exit_percent pass_unlocks_only resources
    ], "P3 TIK Audit stage")
    assert(stages.length == 3 && stages.map { |stage| stage["ordinal"] } == [1, 2, 3] &&
           stages.map { |stage| stage["task_id"] } == TIK_TASK_IDS &&
           stages.map { |stage| stage["stage_id"] } == TIK_STAGE_IDS &&
           stages.map { |stage| stage["kind"] } == TIK_STAGE_KINDS &&
           stages.map { |stage| stage["budget"] } == TIK_FULL_STAGE_BUDGETS &&
           stages.map { |stage| stage["resources"] } == TIK_STAGE_RESOURCES &&
           stages[0]["product_source_mutation_allowed"] == false &&
           stages[0]["budget"] == {
             "engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6,
             "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
           } &&
           stages[0]["pass_unlocks_only"] ==
             "AIOS-P3-TIK-P1_HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_KERNEL" &&
           stages[1]["budget"] == {
             "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 12,
             "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
           } &&
           stages[1]["stage_1_mutation_allowed"] == false &&
           stages[1]["pass_unlocks_only"] ==
             "AIOS-P3-TIK-A1_ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT" &&
           stages[2]["budget"] == {
             "engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6,
             "product_candidates" => 0, "same_task_repairs" => 0, "formal_dispatches" => 1
           } &&
           stages[2]["rerun_to_pass_allowed"] == false &&
           stages[2]["pass_unlocks_only"] ==
             "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
           "P3 TIK ordered-stage boundary drift")
    normative = mapping(decision["normative_requirements"], "P3 TIK normative requirements")
    exact_keys(normative, %w[
      source_body_is_complete_and_normative structured_summary_may_not_reduce_or_expand_source_body
      bound_source_sections stage_1_zero_failure_gates stage_1_required_matrices
      stage_1_allowed_repository_paths stage_2_allowed_source_roots
      stage_2_allowed_repository_paths stage_3_allowed_repository_paths stage_3_mutation_ban
    ], "P3 TIK normative requirements")
    assert(normative["source_body_is_complete_and_normative"] == true &&
           normative["structured_summary_may_not_reduce_or_expand_source_body"] == true &&
           normative["bound_source_sections"] == %w[
             STRATEGY_AND_SCOPE_INVARIANTS VERIFY_CUSTODY_SHA256_V1_WORKFLOW
             STAGE_0_STAGE_1_STAGE_2_STAGE_3_ORDER_AND_GATES TOTAL_BUDGET_AND_ANTI_CYCLE
             ANTI_DRIFT_AND_ANTI_OVER_GOVERNANCE ROLES_AND_AUTONOMOUS_EXECUTION
             AUTHORIZATION_LIFECYCLE
           ] && normative["stage_1_zero_failure_gates"] == TIK_STAGE_1_ZERO_FAILURE_GATES &&
           normative["stage_1_required_matrices"] == TIK_STAGE_1_REQUIRED_MATRICES &&
           normative["stage_1_allowed_repository_paths"] == TIK_STAGE_ALLOWED_PATHS.fetch(0) &&
           normative["stage_2_allowed_source_roots"] == TIK_STAGE_2_ALLOWED_SOURCE_ROOTS &&
           normative["stage_2_allowed_repository_paths"] == TIK_STAGE_ALLOWED_PATHS.fetch(1) &&
           normative["stage_3_allowed_repository_paths"] == TIK_STAGE_ALLOWED_PATHS.fetch(2) &&
           normative["stage_3_mutation_ban"] == TIK_STAGE_3_MUTATION_BAN,
           "P3 TIK normative source-body binding drift")

    accounting = mapping(decision["phase_accounting"], "P3 TIK accounting")
    exact_keys(accounting, %w[
      consumed_preserved rebound_locked_capacity added_capacity cumulative_ceiling
      new_route_capacity max_concurrent_active_tasks max_concurrent_task_branches
      max_concurrent_task_worktrees max_concurrent_candidates
      budget_reset_or_future_phase_borrow_allowed
    ], "P3 TIK accounting")
    assert(accounting["consumed_preserved"] == TIK_CONSUMED &&
           accounting["rebound_locked_capacity"] == {
             "engineering_tasks" => 2, "engineering_hours" => 48, "calendar_days" => 12
           } && accounting["added_capacity"] == {
             "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 12
           } && accounting["cumulative_ceiling"] == TIK_LIMITS.slice(
             "engineering_tasks", "engineering_hours", "calendar_days"
           ) && accounting["new_route_capacity"] == TIK_ROUTE_CAPACITY &&
           accounting["budget_reset_or_future_phase_borrow_allowed"] == false &&
           accounting.values_at("max_concurrent_active_tasks", "max_concurrent_task_branches",
                                "max_concurrent_task_worktrees", "max_concurrent_candidates") ==
             [1, 1, 1, 1], "P3 TIK non-resettable accounting drift")
    lineage = exact_keys(decision["lineage_boundary"], %w[
      p3_001_public_accepted_behavior_composition_allowed p3_001_semantics_mutation_allowed
      p3_002_through_p3_007_terminal_identity_and_accounting_preserved
      p3_hatb_f1_terminal_identity_and_accounting_preserved
      rejected_branch_worktree_candidate_code_tests_evaluator_partial_implementation_or_engineering_evidence_read_allowed
      rejected_lineage_compare_copy_execute_fix_reuse_or_cleanup_allowed
      candidate_3_successor_replacement_remediation_normalization_feasibility_or_v2_v3_allowed
    ], "P3 TIK lineage boundary")
    assert(lineage["p3_001_public_accepted_behavior_composition_allowed"] == true &&
           lineage["p3_001_semantics_mutation_allowed"] == false &&
           lineage["p3_002_through_p3_007_terminal_identity_and_accounting_preserved"] == true &&
           lineage["p3_hatb_f1_terminal_identity_and_accounting_preserved"] == true &&
           lineage["rejected_branch_worktree_candidate_code_tests_evaluator_partial_implementation_or_engineering_evidence_read_allowed"] == false &&
           lineage["rejected_lineage_compare_copy_execute_fix_reuse_or_cleanup_allowed"] == false &&
           lineage["candidate_3_successor_replacement_remediation_normalization_feasibility_or_v2_v3_allowed"] == false,
           "P3 TIK clean-room lineage boundary drift")
    architecture = mapping(decision["architecture_boundary"], "P3 TIK architecture")
    exact_keys(architecture, %w[
      compile_time_closed_action_algebra_required immutable_host_workflow_spec_required
      content_addressed_host_custody_required nofollow_realpath_ancestor_and_hash_validation_required
      create_once_private_materialization_from_open_channel_required
      durable_positive_authorization_budget_nonce_and_dispatch_intent_before_effect_required
      sandbox_exec_hash_bound_profile_required deny_network_secret_read_and_outside_root_write_required
      closed_environment_required exactly_one_append_only_terminal_trace_required
      fresh_process_crash_reconciliation_required terminal_trace_bound_p3_001_checkpoint_gate_required
      generic_tool_registry_or_dynamic_broker_allowed open_shell_or_arbitrary_command_allowed
      unsandboxed_process_builder_fallback_allowed
      agent_selected_executable_handler_path_argv_environment_credential_network_profile_or_budget_allowed
    ], "P3 TIK architecture")
    architecture.each do |key, value|
      expected = key.end_with?("_allowed") ? false : true
      assert(value == expected, "P3 TIK architecture invariant drift: #{key}")
    end
    effects = mapping(decision["external_effects"], "P3 TIK external effects")
    assert(effects.keys.sort == %w[
      af_inet af_inet6 dependency_download dns existing_database_mutation
      irreversible_asset_deletion network production provider public real_secret_read
      remote secret write_outside_exact_authorized_roots
    ].sort && effects.values.all? { |value| value == false },
           "P3 TIK external-effect boundary drift")
    installation = exact_keys(decision["installation"], %w[
      wall_clock_hours_max engineering_progress_credit delivery_progress_after_pass_percent
      strict_exit_progress_after_pass_percent constitution_version allowed_repository_changes
      new_governance_framework_allowed rules_freeze_count_for_route post_install_state
      stage_1_activation_deadline
    ], "P3 TIK installation")
    assert(installation == {
      "wall_clock_hours_max" => 2,
      "engineering_progress_credit" => 0,
      "delivery_progress_after_pass_percent" => 25,
      "strict_exit_progress_after_pass_percent" => 0,
      "constitution_version" => "2.8",
      "allowed_repository_changes" => %w[
        docs/aios/STRATEGIC_CONSTITUTION.md
        docs/aios/truth/project_state.yaml
        scripts/validate-p3-final-transactional-route.rb
        scripts/test-p3-final-transactional-route.rb
        scripts/validate-founder-delegation-continuity.rb
        scripts/validate-current-task-authority.rb
        scripts/validate-founder-action-handoff.rb
        scripts/test-founder-action-handoff.rb
        scripts/validate-aios-governance.sh
      ],
      "new_governance_framework_allowed" => false,
      "rules_freeze_count_for_route" => 1,
      "post_install_state" => {
        "founder_decision_required" => false,
        "user_action_required" => "NONE",
        "next_action_owner" => "MASTER_CEO_AGENT",
        "next_eligible_action" => TIK_ROUTE_ACTION
      },
      "stage_1_activation_deadline" =>
        "WITHIN_FIRST_ENGINEERING_HOUR_AFTER_GOVERNANCE_PASS"
    }, "P3 TIK installation boundary drift")
    assert(decision["review_and_gate"] == {
      "required_independent_roles" => %w[CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT],
      "blocking_finding_categories" => TIK_FINDING_CATEGORIES,
      "stage_2_cycle_1_freezes_complete_p0_p1_set" => true,
      "stage_2_cycle_2_closure_or_direct_regression_only" => true,
      "implementer_self_acceptance_allowed" => false,
      "record_schemas" => {
        "task_contract" => "p3-tik-task-contract/v1",
        "task_authority" => "p3-tik-task-authority/v1",
        "candidate_manifest" => "p3-tik-candidate-manifest/v1",
        "gate_observation" => "p3-tik-gate-observation/v1",
        "gate_evidence" => "p3-tik-gate-evidence/v1",
        "cycle_1_finding_set" => "p3-tik-cycle-1-finding-set/v1",
        "independent_review" => "p3-tik-independent-review/v1",
        "rejected_bundle_attestation" => "p3-tik-rejected-bundle-attestation/v1",
        "stage_gate_receipt" => "p3-tik-stage-gate-receipt/v1"
      },
      "gate_receipt_semantics" => {
        "pass_requires_exact_contract_authority_candidate_manifest_and_three_independent_pass_reviews" => true,
        "non_pass_requires_exact_contract_authority_candidate_manifest_and_at_least_one_independent_non_pass_review" => true,
        "arbitrary_identity_only_blob_can_unlock_stage" => false,
        "manifest_inventory_generated_from_actual_bytes" => true,
        "candidate_repository_entries_bind_regular_git_mode_type_and_blob" => true,
        "mutable_stage_terminal_bundle_verified_once_while_active" => true,
        "terminal_current_state_rejected_lineage_replay_allowed" => false,
        "gate_results_derived_from_parsed_hash_bound_observation_bytes" => true,
        "cycle_1_findings_and_cycle_2_closure_are_hash_bound" => true,
        "product_and_audit_bind_exact_accepted_predecessor_inputs" => true,
        "pass_integration_requires_exact_reviewed_candidate_plus_truth_only_delta" => true,
        "deletion_rename_copy_or_unreviewed_integration_delta_allowed" => false
      }
    }, "P3 TIK review boundary drift")
    assert(decision["lifecycle"] == {
      "authorization_consumed_on" => "STAGE_1_ACTIVATION",
      "reuse_for_parallel_or_second_route_allowed" => false,
      "stage_non_pass" =>
        "TERMINAL_STOP_STAGE_AND_ROUTE_PRESERVE_EVIDENCE_P3_HOLD_INCOMPLETE_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
      "stage_3_pass" =>
        "P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
      "goal_completion_or_termination_authorized" => false,
      "automatic_follow_on_authorization_chain_allowed" => false,
      "terminal_founder_escalation_requires" => %w[
        SEMANTIC_TERMINAL_NON_PASS_RECEIPT NO_ACTIVE_TASK_OR_TASK_RESOURCE
        REMAINING_ROUTE_CAPACITY_MECHANICALLY_LOCKED_UNUSABLE
        EXACT_AUTHORIZATION_PROHIBITS_REUSE_OR_FOLLOW_ON_TASK
        CONTINUATION_REQUIRES_FOUNDER_ROUTE_CHANGE
      ]
    }, "P3 TIK lifecycle boundary drift")
    decision
  end

  def tik_sum_budget(completed_stages)
    result = TIK_CONSUMED.dup
    TIK_STAGE_BUDGETS.first(completed_stages).each do |budget|
      result.keys.each { |key| result[key] += budget.fetch(key) }
    end
    result
  end

  def tik_remaining(consumed)
    {
      "engineering_tasks" => TIK_LIMITS.fetch("engineering_tasks") - consumed.fetch("engineering_tasks"),
      "engineering_hours" => TIK_LIMITS.fetch("engineering_hours") - consumed.fetch("engineering_hours"),
      "calendar_days" => TIK_LIMITS.fetch("calendar_days") - consumed.fetch("calendar_days")
    }
  end

  def tik_lifecycle_spec(route)
    lifecycle = route["lifecycle_stage"]
    return [lifecycle, TIK_LIFECYCLE_SPECS[lifecycle]] if TIK_LIFECYCLE_SPECS.key?(lifecycle)
    return [lifecycle, nil] unless lifecycle == "ROUTE_TERMINAL_NON_PASS"

    ordinal = route["terminal_stage_ordinal"]
    return [lifecycle, nil] unless ordinal.to_s.match?(/\A[1-3]\z/)

    ordinal = ordinal.to_i
    statuses = 3.times.map do |index|
      if index < ordinal - 1
        "ACCEPTED"
      elsif index == ordinal - 1
        "TERMINAL_TASK_GATE_NON_PASS"
      else
        "LOCKED_ROUTE_TERMINAL"
      end
    end
    [lifecycle, {
      "route_status" => "HOLD_INCOMPLETE_ROUTE_TERMINAL_NON_PASS",
      "stage_statuses" => statuses,
      "active_stage" => nil,
      "completed_stages" => ordinal,
      "delivery" => [25, 50, 75].fetch(ordinal - 1),
      "strict_exit" => 0,
      "next_action" => "FOUNDER_DECIDE_P3_AFTER_TIK_ROUTE_TERMINAL_NON_PASS",
      "task_creation_allowed" => false,
      "founder_gate" => true,
      "terminal" => true,
      "terminal_stage_index" => ordinal - 1
    }]
  end

  def tik_expected_route_stages(statuses)
    [
      {
        "ordinal" => 1, "task_id" => TIK_TASK_IDS.fetch(0),
        "stage_id" => TIK_STAGE_IDS.fetch(0), "kind" => TIK_STAGE_KINDS.fetch(0),
        "budget" => TIK_FULL_STAGE_BUDGETS.fetch(0),
        "product_source_mutation_allowed" => false,
        "frozen_subject_protocol_required" => true,
        "file_backed_fresh_process_restart_required" => true,
        "required_reviewers" => TIK_REVIEW_ROLES,
        "delivery_percent_on_pass" => 50, "strict_exit_percent_on_pass" => 0,
        "pass_unlocks_only" => "HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_KERNEL_PRODUCT",
        "status" => statuses.fetch(0)
      },
      {
        "ordinal" => 2, "task_id" => TIK_TASK_IDS.fetch(1),
        "stage_id" => TIK_STAGE_IDS.fetch(1), "kind" => TIK_STAGE_KINDS.fetch(1),
        "budget" => TIK_FULL_STAGE_BUDGETS.fetch(1),
        "product_source_diff_required" => "NON_EMPTY_TESTABLE",
        "stage_1_mutation_allowed" => false,
        "required_reviewers" => TIK_REVIEW_ROLES,
        "delivery_percent_on_pass" => 75, "strict_exit_percent_on_pass" => 0,
        "pass_unlocks_only" => "ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT",
        "status" => statuses.fetch(1)
      },
      {
        "ordinal" => 3, "task_id" => TIK_TASK_IDS.fetch(2),
        "stage_id" => TIK_STAGE_IDS.fetch(2), "kind" => TIK_STAGE_KINDS.fetch(2),
        "budget" => TIK_FULL_STAGE_BUDGETS.fetch(2), "rerun_to_pass_allowed" => false,
        "required_reviewers" => TIK_REVIEW_ROLES,
        "delivery_percent_on_pass" => 100, "strict_exit_percent_on_pass" => 100,
        "pass_unlocks_only" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
        "status" => statuses.fetch(2)
      }
    ]
  end

  def tik_expected_envelope_stages(statuses)
    tik_expected_route_stages(statuses).map do |stage|
      stage.reject do |key, _value|
        %w[required_reviewers frozen_subject_protocol_required
           file_backed_fresh_process_restart_required stage_1_mutation_allowed].include?(key)
      end
    end
  end

  def tik_boundary_stage_index(spec)
    return spec.fetch("active_stage") if spec["active_stage"]
    return nil unless spec.fetch("task_creation_allowed")

    spec.fetch("completed_stages")
  end

  def tik_boundary_deferred_capabilities(stage_index)
    future = if stage_index
      TIK_STAGE_CAPABILITIES.drop(stage_index + 1).flatten.uniq -
        TIK_STAGE_CAPABILITIES.fetch(stage_index)
    else
      []
    end
    future + TIK_DEFERRED_PLATFORM_CAPABILITIES
  end

  def tik_expected_phase_boundary(lifecycle, spec)
    stage_index = tik_boundary_stage_index(spec)
    phase_status = {
      "FOUNDATION_STAGE_ELIGIBLE" => "ACTIVE_P3_TIK_PROCESS_REAL_FOUNDATION_ELIGIBLE",
      "FOUNDATION_TASK_ACTIVE" => "ACTIVE_P3_TIK_PROCESS_REAL_FOUNDATION_TASK",
      "PRODUCT_STAGE_ELIGIBLE" => "ACTIVE_P3_TIK_PROCESS_REAL_PRODUCT_ELIGIBLE",
      "PRODUCT_TASK_ACTIVE" => "ACTIVE_P3_TIK_PROCESS_REAL_PRODUCT_TASK",
      "AUDIT_STAGE_ELIGIBLE" => "ACTIVE_P3_TIK_PROCESS_REAL_AUDIT_ELIGIBLE",
      "AUDIT_TASK_ACTIVE" => "ACTIVE_P3_TIK_PROCESS_REAL_AUDIT_TASK",
      "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
        "P3_TIK_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
      "ROUTE_TERMINAL_NON_PASS" => "P3_TIK_HOLD_INCOMPLETE_ROUTE_TERMINAL_NON_PASS"
    }.fetch(lifecycle)
    scope = if spec.fetch("task_creation_allowed")
      "#{TIK_TASK_IDS.fetch(stage_index).tr('-', '_')}_ONLY"
    elsif spec["active_stage"]
      "NONE_ACTIVE_TIK_TASK"
    elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
      "NONE_ROUTE_TERMINAL_EXACT_AUTHORIZATION_EXHAUSTED"
    else
      "NONE_P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
    end
    write_roots = if stage_index
      {
        "worker" => TIK_STAGE_ALLOWED_PATHS.fetch(stage_index),
        "quality" => [],
        "integration" => if stage_index == 2
          ["docs/aios/truth/project_state.yaml"]
        else
          %w[docs/aios/truth/project_state.yaml docs/PROJECT_CODE_MAP.md]
        end,
        "external_evidence" => "EXTERNAL_TASK_EVIDENCE_ROOT_ONLY"
      }
    else
      {
        "worker" => [], "quality" => [], "integration" => [],
        "external_evidence" => "EXTERNAL_TASK_EVIDENCE_ROOT_ONLY"
      }
    end
    founder_scope = if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      "PHASE_ENTRY_OR_EXIT"
    elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
    end
    {
      "phase" => "P3",
      "phase_execution_status" => phase_status,
      "task_creation_allowed" => spec.fetch("task_creation_allowed"),
      "task_creation_scope" => scope,
      "task_creation_lock_after_activation" => true,
      "p3_entry_authorized" => true,
      "allowed_task_kinds" => stage_index ? [TIK_STAGE_IDS.fetch(stage_index)] : [],
      "allowed_capabilities" => stage_index ? TIK_STAGE_CAPABILITIES.fetch(stage_index) : [],
      "role_write_roots" => write_roots,
      "immutable_authority_paths" => TIK_IMMUTABLE_AUTHORITY_PATHS,
      "allowed_independent_reviewers" =>
        ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
      "required_reviewers_by_risk" => {
        "low" => ["Quality and Evaluation Agent"],
        "medium" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
        "high" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
        "critical" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
      },
      "founder_reserved_risk_levels" => ["critical"],
      "deferred_capabilities" => tik_boundary_deferred_capabilities(stage_index),
      "default_external_effects" => TIK_EXTERNAL_EFFECTS,
      "founder_decision_required" => spec.fetch("founder_gate"),
      "founder_decision_required_scope" => founder_scope,
      "escalation_reason" => if lifecycle == "ROUTE_TERMINAL_NON_PASS"
        "EXACT_TIK_ROUTE_TERMINAL_AND_REMAINING_ROUTE_CAPACITY_UNUSABLE_CONTINUATION_REQUIRES_FOUNDER_ROUTE_CHANGE"
      elsif lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
        "P3_STRICT_EXIT_ACCEPTED_FOUNDER_PHASE_GATE_REQUIRED"
      end,
      "user_action_required" => if lifecycle == "ROUTE_TERMINAL_NON_PASS"
        "FOUNDER_P3_ROUTE_CHANGE_DECISION"
      elsif lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
        "FOUNDER_P3_PHASE_GATE_DECISION"
      else
        "NONE"
      end,
      "phase_route_decision_required" => lifecycle == "ROUTE_TERMINAL_NON_PASS",
      "phase_route_user_action_required" => lifecycle == "ROUTE_TERMINAL_NON_PASS" ?
        "FOUNDER_P3_ROUTE_CHANGE_DECISION" : "NONE",
      "next_eligible_action" => spec.fetch("next_action")
    }
  end

  def validate_tik_workspace_topology!(root, active_index, activation_parent = nil,
                                       preactivation_resource_action: nil,
                                       preactivation_stage_index: nil)
    assert(git!(root, "symbolic-ref", "--short", "HEAD") == "main",
           "P3 TIK canonical checkout must remain on main")
    assert(git!(root, "status", "--porcelain").empty?,
           "P3 TIK canonical checkout must be clean")
    branches = git!(root, "for-each-ref", "--format=%(refname:short)", "refs/heads")
      .lines.map(&:strip).reject(&:empty?).sort
    partial_branch = %w[
      WORKTREE_CREATE ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE TASK_ACTIVATION
    ].include?(preactivation_resource_action)
    partial_worktree = %w[
      ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE TASK_ACTIVATION
    ].include?(preactivation_resource_action)
    expected_branches = ["main"]
    expected_branches << TIK_TASK_BRANCHES.fetch(active_index) if active_index
    expected_branches << TIK_TASK_BRANCHES.fetch(preactivation_stage_index) if partial_branch
    assert(branches == expected_branches.sort,
           "P3 TIK branch topology exceeds main plus the active Task")
    records = git!(root, "worktree", "list", "--porcelain").split(/\n\n+/).map do |block|
      block.lines.each_with_object({}) do |line, record|
        key, value = line.strip.split(" ", 2)
        assert(%w[worktree HEAD branch].include?(key) && value && !record.key?(key),
               "P3 TIK worktree porcelain contains detached, duplicate or unknown state")
        record[key] = value
      end
    end
    worktrees = records.map { |record| record.fetch("worktree") }
    expected_worktrees = [root.to_s]
    expected_worktrees << TIK_TASK_WORKTREES.fetch(active_index) if active_index
    expected_worktrees << TIK_TASK_WORKTREES.fetch(preactivation_stage_index) if partial_worktree
    assert(worktrees.sort == expected_worktrees.sort,
           "P3 TIK worktree topology exceeds the canonical and active Task worktrees")
    canonical = records.find { |record| record["worktree"] == root.to_s }
    assert(canonical && canonical.keys.sort == %w[HEAD branch worktree] &&
           canonical["branch"] == "refs/heads/main" &&
           canonical["HEAD"] == git!(root, "rev-parse", "main"),
           "P3 TIK canonical worktree branch/HEAD association drift")
    if partial_branch
      branch = TIK_TASK_BRANCHES.fetch(preactivation_stage_index)
      assert(git!(root, "rev-parse", branch) == git!(root, "rev-parse", "main"),
             "P3 TIK preactivation branch does not point to the exact canonical parent")
    end
    if partial_worktree
      task = records.find do |record|
        record["worktree"] == TIK_TASK_WORKTREES.fetch(preactivation_stage_index)
      end
      branch = TIK_TASK_BRANCHES.fetch(preactivation_stage_index)
      assert(task && task.keys.sort == %w[HEAD branch worktree] &&
             task["branch"] == "refs/heads/#{branch}" &&
             task["HEAD"] == git!(root, "rev-parse", branch),
             "P3 TIK preactivation worktree is detached or on the wrong branch/HEAD")
    end
    return unless active_index

    task = records.find { |record| record["worktree"] == TIK_TASK_WORKTREES.fetch(active_index) }
    expected_branch = TIK_TASK_BRANCHES.fetch(active_index)
    assert(task && task.keys.sort == %w[HEAD branch worktree] &&
           task["branch"] == "refs/heads/#{expected_branch}" &&
           task["HEAD"] == git!(root, "rev-parse", expected_branch),
           "P3 TIK active worktree is detached, on the wrong branch, or at the wrong HEAD")
    assert(activation_parent, "P3 TIK active worktree lacks an activation parent")
    assert(git!(root, "rev-parse", "#{activation_parent.fetch('commit')}^{tree}") ==
             activation_parent.fetch("tree"),
           "P3 TIK active-Task activation-parent tree drift")
    main_commit = git!(root, "rev-parse", "main")
    main_lineage = git!(root, "rev-list", "--parents", "-n", "1", main_commit).split
    assert(main_lineage.length == 2 && main_lineage[1] == activation_parent.fetch("commit"),
           "P3 TIK active canonical main is not the single activation projection commit")
    activation_delta = git!(
      root, "diff", "--name-status", "--diff-filter=ACMRD",
      activation_parent.fetch("commit"), main_commit
    ).lines.map(&:strip).reject(&:empty?)
    assert(activation_delta == ["M\tdocs/aios/truth/project_state.yaml"],
           "P3 TIK active canonical main drifted beyond the exact Truth activation delta")
    git!(root, "merge-base", "--is-ancestor", activation_parent.fetch("commit"), task.fetch("HEAD"))
  end

  def validate_tik_route!(root, truth, preactivation_resource_action: nil)
    decision = validate_tik_decision!(root)
    route = mapping(truth["current_phase_route"], "P3 TIK current route")
    lifecycle, spec = tik_lifecycle_spec(route)
    assert(spec, "P3 TIK lifecycle stage is not closed-schema")
    preactivation_actions = %w[
      BRANCH_CREATE WORKTREE_CREATE ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE TASK_ACTIVATION
    ]
    assert(preactivation_resource_action.nil? ||
           (preactivation_actions.include?(preactivation_resource_action) &&
            spec.fetch("task_creation_allowed") && spec["active_stage"].nil?),
           "P3 TIK partial preactivation topology mode is not authorized for this lifecycle")
    route_keys = %w[
      schema_version route_id status lifecycle_stage execution_status scheduling_status phase
      phase_entry_status policy founder_phase_route_decision_required
      founder_reserved_triggers_resolved next_eligible_action phase_execution_envelope_ref
      phase_entry_route_ref accepted_p3_001_foundation_route_ref historical_predecessor_route_ref
      founder_route_decision activation_parent constitution objective_id workflow_id
      workflow_claim_limit strict_exit_gate_changed strict_exit_gate_required_items
      prior_consumed_accounting rejected_lineage_policy ordered_stages p3_entry_authorized
      p4_entry_authorized long_term_goal_status external_effects additional_write_roots
    ]
    route_keys << "terminal_stage_ordinal" if lifecycle == "ROUTE_TERMINAL_NON_PASS"
    exact_keys(route, route_keys, "P3 TIK current route")
    assert(route["schema_version"] == TIK_ROUTE_SCHEMA && route["route_id"] == TIK_ROUTE_ID &&
           route["status"] == spec.fetch("route_status") && route["phase"] == "P3" &&
           route["execution_status"] == {
             "FOUNDATION_STAGE_ELIGIBLE" => "READY_TO_ACTIVATE_FOUNDATION",
             "FOUNDATION_TASK_ACTIVE" => "FOUNDATION_TASK_ACTIVE",
             "PRODUCT_STAGE_ELIGIBLE" => "READY_TO_ACTIVATE_PRODUCT",
             "PRODUCT_TASK_ACTIVE" => "PRODUCT_TASK_ACTIVE",
             "AUDIT_STAGE_ELIGIBLE" => "READY_TO_ACTIVATE_AUDIT",
             "AUDIT_TASK_ACTIVE" => "AUDIT_TASK_ACTIVE",
             "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
               "P3_COMPLETE_STRICT_EXIT_ACCEPTED_AWAITING_FOUNDER_PHASE_GATE",
             "ROUTE_TERMINAL_NON_PASS" => "TERMINAL_TIK_STAGE_GATE_NON_PASS"
           }.fetch(lifecycle) &&
           route["scheduling_status"] == {
             "FOUNDATION_STAGE_ELIGIBLE" => "MASTER_CONTINUES_PHASE",
             "FOUNDATION_TASK_ACTIVE" => "ACTIVE_FOUNDATION_TASK",
             "PRODUCT_STAGE_ELIGIBLE" => "MASTER_CONTINUES_PHASE",
             "PRODUCT_TASK_ACTIVE" => "ACTIVE_PRODUCT_TASK",
             "AUDIT_STAGE_ELIGIBLE" => "MASTER_CONTINUES_PHASE",
             "AUDIT_TASK_ACTIVE" => "ACTIVE_AUDIT_TASK",
             "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
               "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION",
             "ROUTE_TERMINAL_NON_PASS" => "FOUNDER_RESERVED_ROUTE_CHANGE_DECISION_REQUIRED"
           }.fetch(lifecycle) &&
           route["phase_entry_status"] == "AUTHORIZED" && route["policy"] == POLICY &&
           route["founder_phase_route_decision_required"] == spec.fetch("founder_gate") &&
           route["founder_reserved_triggers_resolved"] == [
             "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE",
             "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
           ] && route["next_eligible_action"] == spec.fetch("next_action") &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["accepted_p3_001_foundation_route_ref"] == "historical_p3_001_phase_route" &&
           route["historical_predecessor_route_ref"] ==
             "historical_p3_host_authorized_transactional_route_terminal",
           "P3 TIK route lifecycle or authority projection drift")
    decision_projection = TIK_DECISION.merge(
      "decision_id" => TIK_DECISION_ID,
      "source_body" => TIK_AUTHORIZATION_BODY,
      "reserved_triggers" => decision.fetch("reserved_triggers")
    )
    assert(route["founder_route_decision"] == decision_projection &&
           route["activation_parent"] == TIK_ACTIVATION_PARENT &&
           route["constitution"] == TIK_CONSTITUTION &&
           route["objective_id"] == "MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY" &&
           route["workflow_id"] == "VERIFY_CUSTODY_SHA256_V1" &&
           route["workflow_claim_limit"] ==
             "MACOS_JDK17_LOCAL_SYNTHETIC_ONE_FIXED_READ_ONLY_CUSTODY_SHA256_WORKFLOW_ONLY" &&
           route["strict_exit_gate_changed"] == false &&
           route["strict_exit_gate_required_items"] == STRICT_ITEMS &&
           route["prior_consumed_accounting"] == TIK_CONSUMED &&
           route["rejected_lineage_policy"] ==
             "TERMINAL_IDENTITY_ACCOUNTING_ONLY_NO_BRANCH_WORKTREE_CANDIDATE_CODE_TEST_EVALUATOR_OR_ENGINEERING_EVIDENCE_READ" &&
           route["p3_entry_authorized"] == true && route["p4_entry_authorized"] == false &&
           route["long_term_goal_status"] == "ACTIVE" &&
           route["external_effects"] == TIK_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "P3 TIK route invariant projection drift")

    stages = array(route["ordered_stages"], "P3 TIK current ordered stages")
    assert(stages == tik_expected_route_stages(spec.fetch("stage_statuses")),
           "P3 TIK stage ordering, budget or lock drift")

    old_route = mapping(truth["historical_p3_host_authorized_transactional_route_terminal"],
                        "P3 TIK historical terminal route identity/accounting")
    assert(old_route["schema_version"] == HOST_AUTHORIZED_ROUTE_SCHEMA &&
           old_route["route_id"] == HOST_AUTHORIZED_ROUTE_ID &&
           old_route["status"] == "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           old_route.dig("founder_route_decision", "sha256") ==
             HOST_AUTHORIZED_DECISION.fetch("sha256") &&
           old_route.dig("terminal_task", "terminal_receipt") == TIK_OLD_TERMINAL_RECEIPT &&
           old_route.dig("terminal_task", "accepted") == false,
           "P3 TIK predecessor terminal identity/accounting drift")
    old_envelope = mapping(
      truth["historical_p3_host_authorized_transactional_phase_execution_envelope"],
      "P3 TIK historical terminal envelope accounting"
    )
    assert(old_envelope["status"] == "TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           old_envelope["consumed"] == TIK_CONSUMED &&
           old_envelope.dig("last_consumed_stage", "terminal_receipt_sha256") ==
             TIK_OLD_TERMINAL_RECEIPT.fetch("sha256"),
           "P3 TIK eight-Task predecessor accounting drift")

    envelope = mapping(truth["phase_execution_envelope"], "P3 TIK Phase envelope")
    consumed = tik_sum_budget(spec.fetch("completed_stages"))
    remaining = tik_remaining(consumed)
    active_index = spec["active_stage"]
    expected_reserved = active_index.nil? ? {} : TIK_FULL_STAGE_BUDGETS.fetch(active_index)
    exact_keys(envelope, %w[
      schema_version phase status authority_basis accounting_basis prior_terminal_envelope_ref
      consumed rebound_locked_capacity added_capacity limits route_capacity reserved remaining
      remaining_capacity_usable remaining_capacity_lock_reason milestone_order accepted_milestones
      ordered_stages delivery_progress governance_progress_credit external_effects
    ], "P3 TIK Phase envelope")
    accepted_stage_count = spec["terminal"] ? spec.fetch("completed_stages") - 1 :
      spec.fetch("completed_stages")
    expected_accepted_milestones = ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] +
      TIK_STAGE_IDS.first(accepted_stage_count)
    expected_capacity_lock = if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      "ROUTE_TERMINAL_EXACT_AUTHORIZATION_PROHIBITS_REUSE_OR_FOLLOW_ON_TASK"
    elsif lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      "P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
    elsif active_index
      "ACTIVE_TASK_CONSUMES_SINGLE_TASK_SLOT"
    else
      "NONE"
    end
    assert(envelope["schema_version"] ==
             "p3-trusted-invocation-kernel-process-real-phase-envelope/v1" &&
           envelope["phase"] == "P3" && envelope["status"] == spec.fetch("route_status") &&
           envelope.dig("authority_basis", "phase_entry_status") == "AUTHORIZED" &&
           envelope.dig("authority_basis", "policy_path") == POLICY.fetch("path") &&
           envelope.dig("authority_basis", "policy_version") == POLICY.fetch("version") &&
           envelope.dig("authority_basis", "policy_sha256") == POLICY.fetch("sha256") &&
           envelope.dig("authority_basis", "source_route_ref") == "current_phase_route" &&
           envelope.dig("authority_basis", "source_route_id") == TIK_ROUTE_ID &&
           envelope.dig("authority_basis", "founder_route_decision") ==
             TIK_DECISION.merge("decision_id" => TIK_DECISION_ID,
                                "reserved_triggers" => decision.fetch("reserved_triggers")) &&
           envelope["accounting_basis"] == "NON_RESETTABLE_DECLARED_TASK_BUDGET_RESERVATION" &&
           envelope["prior_terminal_envelope_ref"] ==
             "historical_p3_host_authorized_transactional_phase_execution_envelope" &&
           envelope["limits"] == TIK_LIMITS && envelope["route_capacity"] == TIK_ROUTE_CAPACITY &&
           envelope["consumed"] == consumed && envelope["reserved"] == expected_reserved &&
           envelope["remaining"] == remaining &&
           envelope["remaining_capacity_usable"] == spec.fetch("task_creation_allowed") &&
           envelope["remaining_capacity_lock_reason"] == expected_capacity_lock &&
           envelope["milestone_order"] == [
             "DURABLE_STATE_AND_CHECKPOINT_RESUME", *TIK_STAGE_IDS
           ] && envelope["accepted_milestones"] == expected_accepted_milestones &&
           envelope["ordered_stages"] == tik_expected_envelope_stages(spec.fetch("stage_statuses")) &&
           envelope.dig("delivery_progress", "percent") == spec.fetch("delivery") &&
           envelope.dig("delivery_progress", "strict_exit_gate_percent") ==
             spec.fetch("strict_exit") && envelope["governance_progress_credit"] == 0 &&
           envelope["external_effects"] == TIK_EXTERNAL_EFFECTS,
           "P3 TIK Phase envelope or accounting drift")
    assert(envelope["rebound_locked_capacity"] == {
      "engineering_tasks" => 2, "engineering_hours" => 48, "calendar_days" => 12
    } && envelope["added_capacity"] == {
      "engineering_tasks" => 1, "engineering_hours" => 48, "calendar_days" => 12
    }, "P3 TIK rebound/additional capacity drift")

    active = exact_keys(truth["active_work"], %w[
      current_task current_task_status current_task_contract current_task_contract_sha256
      current_execution_authorization current_execution_authorization_sha256 authority_record
      execution_nonce execution_nonce_status authorization_id activation_parent_commit
      activation_parent_tree stage0_installation_parent task_resource_state task_branch
      task_worktree execution_evidence_root dependency_custody_root allowlisted_paths
      current_task_budget next_stage_budget roles external_effects offsite_target
      founder_reserved_authorization founder_reserved_authorization_sha256
      founder_decision_required founder_decision_required_scope escalation_reason
      user_action_required phase_route_decision_required phase_route_user_action_required
      completed_tasks last_completed_task_identity_accounting next_eligible_action
    ], "P3 TIK active_work")
    completed_tasks = array(active["completed_tasks"], "P3 TIK completed Task chain")
    assert(completed_tasks.length == spec.fetch("completed_stages"),
           "P3 TIK completed Task chain length does not match lifecycle")
    completed_results = completed_tasks.each_with_index.map do |completed, task_index|
      terminal_task = spec["terminal"] && task_index == completed_tasks.length - 1
      validate_tik_stage_receipt!(root, completed, task_index, terminal: terminal_task)
    end
    if completed_results.length >= 2
      foundation = completed_results.fetch(0)
      product = completed_results.fetch(1)
      assert(product.fetch("manifest").fetch("frozen_predecessor_inputs") == {
        "foundation_candidate_manifest" => foundation.fetch("manifest_identity"),
        "foundation_gate_evidence" => foundation.fetch("gate_evidence_identity"),
        "foundation_task_gate_receipt" => foundation.fetch("receipt")
      }, "P3 TIK Product candidate is not bound to the exact accepted Foundation")
    end
    if completed_results.length >= 3
      foundation = completed_results.fetch(0)
      product = completed_results.fetch(1)
      audit = completed_results.fetch(2)
      assert(audit.fetch("candidate").slice("commit", "tree", "source_branch") ==
               product.fetch("candidate").slice("commit", "tree", "source_branch") &&
             audit.fetch("manifest").fetch("frozen_predecessor_inputs") == {
               "foundation_candidate_manifest" => foundation.fetch("manifest_identity"),
               "foundation_gate_evidence" => foundation.fetch("gate_evidence_identity"),
               "foundation_task_gate_receipt" => foundation.fetch("receipt"),
               "product_candidate_manifest" => product.fetch("manifest_identity"),
               "product_gate_evidence" => product.fetch("gate_evidence_identity"),
               "product_task_gate_receipt" => product.fetch("receipt")
             },
             "P3 TIK Audit did not freeze the exact accepted Foundation/Product inputs")
    end
    active_activation_parent = nil
    if active_index
      assert(active["current_task"] == TIK_TASK_IDS.fetch(active_index) &&
             active["current_task_status"] == "ACTIVE" &&
             active["execution_nonce_status"] == "ACTIVE" &&
             active["task_branch"] == TIK_TASK_BRANCHES.fetch(active_index) &&
             active["task_worktree"] == TIK_TASK_WORKTREES.fetch(active_index) &&
             active["execution_evidence_root"] == TIK_TASK_EVIDENCE_ROOTS.fetch(active_index) &&
             active["dependency_custody_root"] ==
               "#{TIK_TASK_EVIDENCE_ROOTS.fetch(active_index)}/custody" &&
             active["allowlisted_paths"] == TIK_STAGE_ALLOWED_PATHS.fetch(active_index) &&
             active["current_task_budget"] == TIK_FULL_STAGE_BUDGETS.fetch(active_index) &&
             active["next_stage_budget"] == {} &&
             active["task_resource_state"] == "ACTIVE_UNIQUE_TIK_STAGE" &&
             active["offsite_target"].nil?,
             "P3 TIK active Task projection drift")
      contract_identity, _contract, active_activation_parent = validate_tik_contract!(
        root, active["current_task_contract"], active_index
      )
      authority_identity, authority = validate_tik_authority!(
        root, active["authority_record"], active_index, contract_identity,
        active_activation_parent
      )
      assert(active["current_task_contract_sha256"] == contract_identity["sha256"] &&
             active["current_execution_authorization"] == authority_identity["path"] &&
             active["current_execution_authorization_sha256"] == authority_identity["sha256"] &&
             active["authorization_id"] == authority["authorization_id"] &&
             active["execution_nonce"] == authority["execution_nonce"] &&
             active["activation_parent_commit"] == active_activation_parent["commit"] &&
             active["activation_parent_tree"] == active_activation_parent["tree"],
             "P3 TIK active Contract/authority pointer drift")
      custody = Pathname.new(active.fetch("dependency_custody_root"))
      assert(custody.directory? && !custody.symlink? &&
             custody.realpath.to_s == custody.cleanpath.to_s,
             "P3 TIK active custody root is missing or symlinked")
    else
      assert(active["current_task"] == "NONE" && active["current_task_contract"].nil? &&
             active["current_task_contract_sha256"].nil? &&
             active["current_execution_authorization"].nil? &&
             active["current_execution_authorization_sha256"].nil? &&
             active["authority_record"].nil? && active["execution_nonce"].nil? &&
             active["authorization_id"].nil? && active["activation_parent_commit"].nil? &&
             active["activation_parent_tree"].nil? && active["task_branch"].nil? &&
             active["task_worktree"].nil? && active["execution_evidence_root"].nil? &&
             active["dependency_custody_root"].nil? && active["allowlisted_paths"] == [] &&
             active["current_task_budget"] == {
               "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0
             },
             "P3 TIK no-Task lifecycle retained active Task authority")
      expected_no_task_status = {
        "FOUNDATION_STAGE_ELIGIBLE" => "NONE_FOUNDATION_STAGE_ELIGIBLE",
        "PRODUCT_STAGE_ELIGIBLE" => "NONE_PRODUCT_STAGE_ELIGIBLE",
        "AUDIT_STAGE_ELIGIBLE" => "NONE_AUDIT_STAGE_ELIGIBLE",
        "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" => "NONE_P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
        "ROUTE_TERMINAL_NON_PASS" => "NONE_ROUTE_TERMINAL_NON_PASS"
      }.fetch(lifecycle)
      expected_resource_state = {
        "FOUNDATION_STAGE_ELIGIBLE" => "NOT_CREATED_FOUNDATION_STAGE_ELIGIBLE",
        "PRODUCT_STAGE_ELIGIBLE" => "NOT_CREATED_PRODUCT_STAGE_ELIGIBLE",
        "AUDIT_STAGE_ELIGIBLE" => "NOT_CREATED_AUDIT_STAGE_ELIGIBLE",
        "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" => "COMPLETE_NO_TASK_RESOURCES",
        "ROUTE_TERMINAL_NON_PASS" => "TERMINAL_ROUTE_NO_TASK_RESOURCES"
      }.fetch(lifecycle)
      next_index = tik_boundary_stage_index(spec)
      assert(active["current_task_status"] == expected_no_task_status &&
             active["task_resource_state"] == expected_resource_state &&
             active["execution_nonce_status"] ==
               (lifecycle == "FOUNDATION_STAGE_ELIGIBLE" ? "NOT_ISSUED" : "NO_CURRENT_TASK") &&
             active["next_stage_budget"] ==
               (next_index ? TIK_FULL_STAGE_BUDGETS.fetch(next_index) : {}),
             "P3 TIK no-Task lifecycle/resource projection drift")
    end
    route_authorities = completed_results.map { |result| result.fetch("authority") }
    route_authorities << authority if active_index
    authorization_ids = route_authorities.map { |record| record.fetch("authorization_id") }
    execution_nonces = route_authorities.map { |record| record.fetch("execution_nonce") }
    assert(authorization_ids.uniq.length == authorization_ids.length &&
           execution_nonces.uniq.length == execution_nonces.length,
           "P3 TIK authorization ID or execution nonce was reused across stages")
    expected_roles = {
      "owner" => "MASTER_CEO_AGENT", "worker" => "IMPLEMENTATION_AGENT",
      "quality_owner" => "QUALITY_EVALUATION_AGENT", "independent_reviewers" => TIK_REVIEW_ROLES
    }
    assert(active["stage0_installation_parent"] == TIK_ACTIVATION_PARENT.slice("commit", "tree") &&
           active["roles"] == expected_roles && active["external_effects"] == TIK_EXTERNAL_EFFECTS &&
           active["founder_reserved_authorization"] == TIK_DECISION.fetch("path") &&
           active["founder_reserved_authorization_sha256"] == TIK_DECISION.fetch("sha256") &&
           active["next_eligible_action"] == spec.fetch("next_action"),
           "P3 TIK active-work authority or effect drift")
    assert(active["last_completed_task_identity_accounting"] == {
      "task_id" => "AIOS-P3-HATB-F1_MINIMUM_TRUST_EXECUTABLE_ACCEPTANCE_FOUNDATION",
      "status" => "TERMINAL_TASK_GATE_NON_PASS",
      "consumed" => {
        "engineering_tasks" => 1, "engineering_hours" => 16, "calendar_days" => 4,
        "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
      },
      "terminal_receipt" => TIK_OLD_TERMINAL_RECEIPT
    }, "P3 TIK predecessor terminal accounting drift")

    control = exact_keys(truth["founder_escalation_control"], %w[
      schema_version disposition source_event reserved_trigger resolved_strategy_decision
      resolved_phase_entry_decision phase_gate_status founder_decision_required next_action_owner
      next_eligible_action
    ], "P3 TIK Founder control")
    reserved_trigger = exact_keys(control["reserved_trigger"], %w[category evidence],
                                  "P3 TIK Founder reserved trigger")
    if spec.fetch("founder_gate")
      expected_trigger = lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" ?
        "PHASE_ENTRY_OR_EXIT" : "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
      assert(control["disposition"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
             reserved_trigger["category"] == expected_trigger &&
             control["founder_decision_required"] == true &&
             control["next_action_owner"] == "HUMAN_FOUNDER" &&
             control["next_eligible_action"] == spec.fetch("next_action"),
             "P3 TIK Founder Gate projection drift")
      if lifecycle == "ROUTE_TERMINAL_NON_PASS"
        terminal_result = completed_results.fetch(spec.fetch("terminal_stage_index"))
        assert(envelope["remaining_capacity_usable"] == false &&
               envelope["remaining_capacity_lock_reason"] ==
                 "ROUTE_TERMINAL_EXACT_AUTHORIZATION_PROHIBITS_REUSE_OR_FOLLOW_ON_TASK" &&
               reserved_trigger["evidence"] == {
                 "reason" =>
                   "EXACT_TIK_ROUTE_TERMINAL_NO_AUTHORIZED_REUSE_OR_FOLLOW_ON_TASK_CONTINUATION_REQUIRES_ROUTE_CHANGE",
                 "terminal_stage_ordinal" => spec.fetch("terminal_stage_index") + 1,
                 "terminal_receipt" => terminal_result.fetch("receipt"),
                 "founder_decision" => TIK_DECISION.merge("decision_id" => TIK_DECISION_ID)
               }, "P3 TIK terminal state lacks mechanical exhausted-route Founder predicate")
      else
        assert(reserved_trigger["evidence"] == {
          "strict_exit_percent" => 100,
          "final_stage_receipt" => completed_results.fetch(2).fetch("receipt"),
          "p4_entry_status" => "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY"
        }, "P3 TIK Phase Gate evidence drift")
      end
    else
      assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
             reserved_trigger == {"category" => "NONE", "evidence" => nil} &&
             control["founder_decision_required"] == false &&
             control["next_action_owner"] == "MASTER_CEO_AGENT" &&
             control["next_eligible_action"] == spec.fetch("next_action"),
             "P3 TIK delegated continuation projection drift")
    end
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control.dig("resolved_strategy_decision", "decision_id") == TIK_DECISION_ID &&
           control.dig("resolved_strategy_decision", "sha256") == TIK_DECISION.fetch("sha256"),
           "P3 TIK resolved strategy decision drift")

    boundary = mapping(truth["phase_boundary"], "P3 TIK phase boundary")
    expected_boundary = tik_expected_phase_boundary(lifecycle, spec)
    assert(boundary == expected_boundary, "P3 TIK phase-boundary authority projection drift")
    assert(active["founder_decision_required"] == expected_boundary["founder_decision_required"] &&
           active["founder_decision_required_scope"] ==
             expected_boundary["founder_decision_required_scope"] &&
           active["escalation_reason"] == expected_boundary["escalation_reason"] &&
           active["user_action_required"] == expected_boundary["user_action_required"] &&
           active["phase_route_decision_required"] ==
             expected_boundary["phase_route_decision_required"] &&
           active["phase_route_user_action_required"] ==
             expected_boundary["phase_route_user_action_required"],
           "P3 TIK active-work Founder/user-action projection drift")
    execution = mapping(truth["phase_execution_claim"], "P3 TIK execution claim")
    assert(execution["current_route_claim"] == TIK_ROUTE_ID &&
           execution["p3_delivery_progress_percent"] == spec.fetch("delivery") &&
           execution["p3_exit_gate_progress_percent"] == spec.fetch("strict_exit") &&
           execution["task_creation_allowed"] == spec.fetch("task_creation_allowed") &&
           execution["remaining_capacity_usable"] == spec.fetch("task_creation_allowed") &&
           execution["held_read_allowed"] == false &&
           execution["candidate_integration_allowed"] == false &&
           execution["next_eligible_action"] == spec.fetch("next_action") &&
           execution["phase_local_allowed"] ==
             (spec.fetch("founder_gate") ? [] : [spec.fetch("next_action")]) &&
           execution["phase_local_frozen_capabilities"].include?(
             "P3_002_THROUGH_P3_007_REJECTED_LINEAGE_FROZEN_UNREADABLE"
           ) && execution["phase_local_frozen_capabilities"].include?(
             "P3_HATB_F1_REJECTED_ENGINEERING_LINEAGE_FROZEN_UNREADABLE"
           ), "P3 TIK execution-claim drift")
    claim = mapping(truth["claim_boundary"], "P3 TIK claim boundary")
    assert(claim["current_phase_route"] == TIK_ROUTE_ID &&
           claim["p3_delivery_progress_percent"] == spec.fetch("delivery") &&
           claim["p3_exit_gate_progress_percent"] == spec.fetch("strict_exit") &&
           claim["p3_tik_process_real_route_decision_sha256"] == TIK_DECISION.fetch("sha256") &&
           claim["p3_tik_process_real_route_stage"] == lifecycle &&
           claim["p3_tik_process_real_route_delivery_credit"] == spec.fetch("delivery") - 25 &&
           claim["p3_tik_process_real_route_strict_exit_credit"] == spec.fetch("strict_exit") &&
           claim["next_eligible_action"] == spec.fetch("next_action"),
           "P3 TIK claim-boundary drift")
    goal = mapping(truth["goal"], "P3 TIK Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] ==
             (active_index ? TIK_TASK_IDS.fetch(active_index) : "NONE") &&
           truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "p4_entry_status") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3 TIK Goal, Phase or P4 boundary drift")
    gate = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"),
                   "P3 strict Exit Gate")
    if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      assert(gate.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") ==
               "ACCEPTED" && gate.dig("founder_phase_gate", "status") ==
               "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "P3 TIK complete lifecycle lacks strict Exit acceptance")
    else
      assert(gate["status"] == "INCOMPLETE" &&
             gate.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") ==
               "MISSING" && gate.dig("founder_phase_gate", "status") ==
               "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
             "P3 TIK incomplete lifecycle falsely accepted strict Exit")
    end
    if lifecycle == "FOUNDATION_STAGE_ELIGIBLE"
      assert(truth["verification_scope"] ==
               "P3_TRUSTED_INVOCATION_KERNEL_PROCESS_REAL_CLEAN_ROOM_ROUTE_INSTALLED_FOUNDATION_ELIGIBLE_ZERO_ENGINEERING_PROGRESS_DELIVERY_25_STRICT_EXIT_ZERO_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
             "P3 TIK installation verification scope drift")
    end
    validate_tik_workspace_topology!(
      root, active_index, active_activation_parent,
      preactivation_resource_action: preactivation_resource_action,
      preactivation_stage_index: preactivation_resource_action ? tik_boundary_stage_index(spec) : nil
    )
    TIK_LIFECYCLE_STATES.fetch(lifecycle)
  rescue ArgumentError, KeyError, TypeError => e
    raise P3FinalTransactionalRouteValidationError, "P3 TIK route invalid: #{e.message}"
  end

  def validate_hpe_decision!(root)
    bytes = read_tik_external_identity!(HPE_DECISION, "P3 HPE Founder decision", create_once: true)
    decision = parse_tik_json!(bytes, "P3 HPE Founder decision")
    exact_keys(decision, %w[
      schema_version record_type decision_id approved_at_utc authority source_reply canonical_start
      route installation local_executables lifecycle
    ], "P3 HPE Founder decision")
    assert(decision["schema_version"] == HPE_DECISION_SCHEMA &&
           decision["record_type"] ==
             "FOUNDER_P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_REBASELINE" &&
           decision["decision_id"] == HPE_DECISION_ID &&
           decision["authority"] == "HUMAN_FOUNDER",
           "P3 HPE Founder decision identity drift")
    tik_timestamp!(decision["approved_at_utc"], "P3 HPE Founder decision timestamp")

    source = exact_keys(decision["source_reply"],
                        %w[attachment canonicalization canonical_body canonicalized_bytes_equal],
                        "P3 HPE Founder source reply")
    assert(source["attachment"] == HPE_AUTHORIZATION_ATTACHMENT &&
           source["canonicalization"] == "UTF8_LF_WITH_EXACTLY_ONE_TRAILING_LF" &&
           source["canonical_body"] == HPE_AUTHORIZATION_BODY &&
           source["canonicalized_bytes_equal"] == true,
           "P3 HPE Founder source identity drift")
    body = read_tik_external_identity!(HPE_AUTHORIZATION_BODY,
                                       "P3 HPE installed Founder body", create_once: true)
    assert(body.valid_encoding? && body.end_with?("\n") && !body.end_with?("\n\n") &&
           body.scan(HPE_DECISION_ID).length == 1,
           "P3 HPE installed Founder body canonicalization/token drift")
    if File.exist?(HPE_AUTHORIZATION_ATTACHMENT.fetch("path"))
      raw = read_tik_external_identity!(HPE_AUTHORIZATION_ATTACHMENT,
                                        "P3 HPE Founder attachment")
      normalized = raw.dup.force_encoding(Encoding::UTF_8)
      assert(normalized.valid_encoding?, "P3 HPE Founder attachment is not UTF-8")
      normalized = normalized.gsub("\r\n", "\n").gsub("\r", "\n").sub(/\n*\z/, "") + "\n"
      assert(normalized.b == body.b, "P3 HPE attachment/body canonical bytes differ")
    end

    assert(decision["canonical_start"] == HPE_CANONICAL_START,
           "P3 HPE canonical-start identity drift")
    assert(git!(root, "rev-parse", "#{HPE_CANONICAL_START.fetch('commit')}^{tree}") ==
             HPE_CANONICAL_START.fetch("tree"), "P3 HPE canonical-start tree drift")
    start_truth = tik_git_bytes!(root, HPE_CANONICAL_START.fetch("commit"),
                                 HPE_CANONICAL_START.dig("truth", "path"),
                                 "P3 HPE canonical-start Truth")
    assert(start_truth.bytesize == HPE_CANONICAL_START.dig("truth", "byte_length") &&
           Digest::SHA256.hexdigest(start_truth) == HPE_CANONICAL_START.dig("truth", "sha256"),
           "P3 HPE canonical-start Truth drift")
    constitution = (root / TIK_CONSTITUTION.fetch("path")).binread
    assert(constitution.bytesize == TIK_CONSTITUTION.fetch("byte_length") &&
           Digest::SHA256.hexdigest(constitution) == TIK_CONSTITUTION.fetch("sha256"),
           "P3 HPE Constitution identity drift")
    read_tik_external_identity!(HPE_CANONICAL_START.fetch("terminal_receipt"),
                                "P3 TIK terminal receipt identity accounting", create_once: true)
    read_tik_external_identity!(HPE_CANONICAL_START.fetch("rejected_bundle_attestation"),
                                "P3 TIK rejected-bundle attestation identity accounting",
                                create_once: true)

    route = exact_keys(decision["route"], %w[
      schema_version route_id objective_id workflow_id strict_exit_gate_changed
      strict_exit_gate_required_items external_effects cumulative_ceiling consumed_preserved
      route_capacity stages progression rejected_lineage_policy anti_loop
    ], "P3 HPE authorized route")
    assert(route["schema_version"] == HPE_ROUTE_SCHEMA && route["route_id"] == HPE_ROUTE_ID &&
           route["objective_id"] == "MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY" &&
           route["workflow_id"] == "VERIFY_CUSTODY_SHA256_V1" &&
           route["strict_exit_gate_changed"] == false &&
           route["strict_exit_gate_required_items"] ==
             %w[RESUME ISOLATION PERMISSION COMPLETE_OBSERVABLE_TRACE] &&
           route["external_effects"] == HPE_EXTERNAL_EFFECTS &&
           route["cumulative_ceiling"] == {
             "engineering_tasks" => 12, "engineering_hours" => 336,
             "calendar_days" => 84, "active_tasks" => 1, "task_branches" => 1,
             "task_worktrees" => 1, "active_candidates" => 1
           } && route["consumed_preserved"] == {
             "engineering_tasks" => 9, "engineering_hours" => 264, "calendar_days" => 66
           } && route["route_capacity"] == {
             "engineering_tasks" => 3, "engineering_hours" => 72, "calendar_days" => 18
           }, "P3 HPE objective, Exit Gate, effect or budget drift")
    stages = array(route["stages"], "P3 HPE stages")
    assert(stages.length == 3 && stages.map { |stage| stage.fetch("ordinal") } == [1, 2, 3] &&
           stages.map { |stage| stage.fetch("task_id") }.uniq.length == 3 &&
           stages.map { |stage| stage.fetch("resources").fetch("branch") }.uniq.length == 3 &&
           stages.map { |stage| stage.fetch("resources").fetch("worktree") }.uniq.length == 3 &&
           stages.map { |stage| stage.fetch("resources").fetch("evidence_root") }.uniq.length == 3,
           "P3 HPE stages are not a unique ordered three-stage route")
    expected_kinds = %w[EVALUATION_FOUNDATION PRODUCT_IMPLEMENTATION EVALUATION_ONLY]
    expected_budgets = [
      {"engineering_tasks" => 1, "engineering_hours" => 8, "calendar_days" => 2,
       "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2},
      {"engineering_tasks" => 1, "engineering_hours" => 44, "calendar_days" => 10,
       "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2},
      {"engineering_tasks" => 1, "engineering_hours" => 20, "calendar_days" => 6,
       "product_candidates" => 0, "same_task_repairs" => 0, "formal_dispatches" => 1}
    ]
    stages.each_with_index do |stage, index|
      assert(stage["kind"] == expected_kinds.fetch(index) &&
             stage["budget"] == expected_budgets.fetch(index) &&
             stage["required_reviewers"] == HPE_REVIEW_ROLES &&
             stage["delivery_percent_on_pass"] == [50, 75, 100].fetch(index) &&
             stage["strict_exit_percent_on_pass"] == [0, 0, 100].fetch(index) &&
             array(stage["allowlisted_repository_paths"], "P3 HPE stage allowlist").uniq ==
               stage["allowlisted_repository_paths"] &&
             array(stage["capabilities"], "P3 HPE stage capabilities").uniq ==
               stage["capabilities"] &&
             array(stage["gate_requirements"], "P3 HPE stage Gate requirements").uniq ==
               stage["gate_requirements"], "P3 HPE stage #{index + 1} semantic drift")
      assert(stage.fetch("gate_requirements").count("THREE_INDEPENDENT_REVIEWS_PASS") == 1,
             "P3 HPE stage #{index + 1} must reserve exactly one receipt-level Review Gate")
      resources = mapping(stage["resources"], "P3 HPE stage resources")
      resources.each do |key, value|
        next if key == "branch"
        next if key == "worktree"
        path = Pathname.new(value)
        evidence_root = Pathname.new(resources.fetch("evidence_root"))
        assert(path.absolute? && path.cleanpath.to_s == path.to_s,
               "P3 HPE stage #{index + 1} #{key} path is not absolute and normalized")
        next if key == "evidence_root"

        relative = path.relative_path_from(evidence_root).to_s
        assert(relative != "." && !relative.start_with?("../"),
               "P3 HPE stage #{index + 1} #{key} escapes its Evidence root")
      end
    end
    assert(stages[0]["product_source_mutation_allowed"] == false &&
           stages[1]["product_source_diff_required"] == "NON_EMPTY_TESTABLE" &&
           stages[1]["stage_1_mutation_allowed"] == false &&
           stages[2]["allowlisted_repository_paths"] == [] &&
           stages[2]["rerun_to_pass_allowed"] == false,
           "P3 HPE stage mutation boundary drift")
    assert(route["anti_loop"] == {
      "maximum_candidate_generations_per_implementation_task" => 2,
      "maximum_same_task_repairs" => 1, "maximum_review_cycles" => 2,
      "candidate_3_allowed" => false,
      "successor_replacement_normalization_closure_feasibility_remediation_allowed" => false,
      "rerun_to_pass_allowed" => false, "rules_freeze_count" => 1,
      "governance_progress_credit" => 0
    }, "P3 HPE anti-loop boundary drift")

    installation = exact_keys(decision["installation"], %w[
      decision_path body_path constitution_mutation_allowed allowed_repository_paths
      create_once_required decision_and_body_mode governance_and_delivery_progress_credit
      stage_1_prep_budget_percent_max worker_must_start_within_first_engineering_hour
      rules_freeze_count
    ], "P3 HPE installation")
    assert(installation["decision_path"] == HPE_DECISION.fetch("path") &&
           installation["body_path"] == HPE_AUTHORIZATION_BODY.fetch("path") &&
           installation["constitution_mutation_allowed"] == false &&
           installation["create_once_required"] == true &&
           installation["decision_and_body_mode"] == "0444" &&
           installation["governance_and_delivery_progress_credit"] == 0 &&
           installation["stage_1_prep_budget_percent_max"] == 10 &&
           installation["worker_must_start_within_first_engineering_hour"] == true &&
           installation["rules_freeze_count"] == 1,
           "P3 HPE installation boundary drift")
    array(decision["local_executables"], "P3 HPE local executable identities").each do |identity|
      exact_keys(identity, %w[id path byte_length sha256], "P3 HPE local executable")
      read_tik_external_identity!(identity.slice("path", "byte_length", "sha256"),
                                  "P3 HPE local executable #{identity.fetch('id')}")
    end
    lifecycle = exact_keys(decision["lifecycle"], %w[states non_pass project_and_goal],
                           "P3 HPE lifecycle")
    assert(lifecycle["states"] == HPE_LIFECYCLE_STATES.keys &&
           lifecycle["non_pass"] ==
             "ANY_STAGE_NON_PASS_TERMINATES_ROUTE_WITH_NO_CANDIDATE_3_SUCCESSOR_REPLACEMENT_OR_RERUN_TO_PASS" &&
           lifecycle["project_and_goal"] ==
             "P4_HOLD_PROJECT_INCOMPLETE_LONG_TERM_GOAL_ACTIVE_UNTIL_ACTUAL_PROJECT_COMPLETION",
           "P3 HPE lifecycle freeze drift")
    decision
  end

  def hpe_stages(decision)
    decision.fetch("route").fetch("stages")
  end

  def hpe_stage(decision, stage_index)
    hpe_stages(decision).fetch(stage_index)
  end

  def hpe_stage_resource(decision, stage_index)
    hpe_stage(decision, stage_index).fetch("resources")
  end

  def hpe_identity(identity)
    exact_keys(identity, %w[path byte_length sha256], "P3 HPE artifact identity")
  end

  def hpe_founder_decision_projection
    HPE_DECISION.merge(
      "decision_id" => HPE_DECISION_ID,
      "source_body" => HPE_AUTHORIZATION_BODY,
      "reserved_triggers" => %w[
        MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
        MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
      ]
    )
  end

  def hpe_boundary_stage_index(spec)
    return spec.fetch("active_stage") unless spec["active_stage"].nil?
    return nil unless spec.fetch("task_creation_allowed")

    spec.fetch("completed_stages")
  end

  def hpe_stage_projection(stage, status)
    base = stage.slice(
      "ordinal", "task_id", "stage_id", "kind", "objective", "claim_boundary", "budget",
      "allowlisted_repository_paths", "capabilities", "gate_requirements", "required_reviewers",
      "delivery_percent_on_pass", "strict_exit_percent_on_pass", "pass_unlocks_only"
    )
    %w[
      product_source_mutation_allowed product_source_diff_required stage_1_mutation_allowed
      product_mutation_ban rerun_to_pass_allowed
    ].each { |key| base[key] = stage[key] if stage.key?(key) }
    base.merge("status" => status)
  end

  def hpe_expected_phase_boundary(decision, lifecycle, spec)
    stage_index = hpe_boundary_stage_index(spec)
    stage = stage_index ? hpe_stage(decision, stage_index) : nil
    founder_scope = if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      "PHASE_ENTRY_OR_EXIT"
    elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
    end
    {
      "phase" => "P3",
      "phase_execution_status" => "P3_HPE_#{lifecycle}",
      "task_creation_allowed" => spec.fetch("task_creation_allowed"),
      "task_creation_scope" => if stage
        "#{stage.fetch('task_id').tr('-', '_')}_ONLY"
      elsif spec["active_stage"]
        "NONE_ACTIVE_HPE_TASK"
      elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
        "NONE_ROUTE_TERMINAL_EXACT_AUTHORIZATION_EXHAUSTED"
      else
        "NONE_P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      end,
      "task_creation_lock_after_activation" => true,
      "p3_entry_authorized" => true,
      "allowed_task_kinds" => stage ? [stage.fetch("stage_id")] : [],
      "allowed_capabilities" => stage ? stage.fetch("capabilities") : [],
      "role_write_roots" => {
        "worker" => stage ? stage.fetch("allowlisted_repository_paths") : [],
        "quality" => [],
        "integration" => if stage_index == 2
          ["docs/aios/truth/project_state.yaml"]
        elsif stage
          %w[docs/aios/truth/project_state.yaml docs/PROJECT_CODE_MAP.md]
        else
          []
        end,
        "external_evidence" => "EXTERNAL_TASK_EVIDENCE_ROOT_ONLY"
      },
      "immutable_authority_paths" => TIK_IMMUTABLE_AUTHORITY_PATHS,
      "allowed_independent_reviewers" =>
        ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
      "required_reviewers_by_risk" => {
        "low" => ["Quality and Evaluation Agent"],
        "medium" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
        "high" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
        "critical" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
      },
      "founder_reserved_risk_levels" => ["critical"],
      "deferred_capabilities" => TIK_DEFERRED_PLATFORM_CAPABILITIES,
      "default_external_effects" => HPE_EXTERNAL_EFFECTS,
      "founder_decision_required" => spec.fetch("founder_gate"),
      "founder_decision_required_scope" => founder_scope,
      "escalation_reason" => if lifecycle == "ROUTE_TERMINAL_NON_PASS"
        "EXACT_HPE_ROUTE_TERMINAL_AND_ROUTE_CAPACITY_UNUSABLE_CONTINUATION_REQUIRES_FOUNDER_ROUTE_CHANGE"
      elsif lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
        "P3_STRICT_EXIT_ACCEPTED_FOUNDER_PHASE_GATE_REQUIRED"
      end,
      "user_action_required" => if lifecycle == "ROUTE_TERMINAL_NON_PASS"
        "FOUNDER_P3_ROUTE_CHANGE_DECISION"
      elsif lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
        "FOUNDER_P3_PHASE_GATE_DECISION"
      else
        "NONE"
      end,
      "phase_route_decision_required" => lifecycle == "ROUTE_TERMINAL_NON_PASS",
      "phase_route_user_action_required" => lifecycle == "ROUTE_TERMINAL_NON_PASS" ?
        "FOUNDER_P3_ROUTE_CHANGE_DECISION" : "NONE",
      "next_eligible_action" => spec.fetch("next_action")
    }
  end

  def validate_hpe_activation_parent!(root, decision, activation_parent, stage_index)
    parent = exact_keys(activation_parent, %w[branch commit tree],
                        "P3 HPE Task activation parent")
    assert(parent["branch"] == "main" && parent["commit"].match?(/\A[0-9a-f]{40}\z/) &&
           parent["tree"].match?(/\A[0-9a-f]{40}\z/) &&
           parent["commit"] != HPE_CANONICAL_START.fetch("commit") &&
           git!(root, "rev-parse", "#{parent.fetch('commit')}^{tree}") == parent.fetch("tree"),
           "P3 HPE activation-parent identity invalid")
    git!(root, "merge-base", "--is-ancestor", HPE_CANONICAL_START.fetch("commit"),
         parent.fetch("commit"))
    git!(root, "merge-base", "--is-ancestor", parent.fetch("commit"), "main")
    parent_truth_bytes = tik_git_bytes!(root, parent.fetch("commit"),
                                        "docs/aios/truth/project_state.yaml",
                                        "P3 HPE activation-parent Truth")
    parent_truth = YAML.safe_load(parent_truth_bytes, permitted_classes: [],
                                  permitted_symbols: [], aliases: false)
    expected_lifecycle = %w[
      FOUNDATION_STAGE_ELIGIBLE PRODUCT_STAGE_ELIGIBLE AUDIT_STAGE_ELIGIBLE
    ].fetch(stage_index)
    assert(parent_truth.dig("current_phase_route", "schema_version") == HPE_ROUTE_SCHEMA &&
           parent_truth.dig("current_phase_route", "route_id") == HPE_ROUTE_ID &&
           parent_truth.dig("current_phase_route", "lifecycle_stage") == expected_lifecycle &&
           parent_truth.dig("current_phase_route", "founder_route_decision", "sha256") ==
             HPE_DECISION.fetch("sha256") &&
           parent_truth.dig("active_work", "current_task") == "NONE" &&
           parent_truth.dig("goal", "control_plane_status_observed") == "ACTIVE",
           "P3 HPE activation parent is not the exact predecessor-accepted ready state")
    if stage_index == 1
      _stdout, _stderr, status = Open3.capture3(
        "git", "cat-file", "-e",
        "#{parent.fetch('commit')}:backend-spring/src/main/resources/db/migration/V034__add_host_invocation_kernel.sql",
        chdir: root.to_s
      )
      assert(!status.success?, "P3 HPE exact V034 migration target is already occupied")
    end
    parent
  rescue Psych::Exception => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 HPE activation-parent Truth invalid: #{e.message}"
  end

  def validate_hpe_contract!(root, decision, identity, stage_index)
    stage = hpe_stage(decision, stage_index)
    resource = stage.fetch("resources")
    contract_identity, contract = read_tik_rooted_json!(
      identity, "P3 HPE Task Contract", root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("contract_path")
    )
    exact_keys(contract, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id task_kind status
      objective claim_boundary founder_decision activation_parent resources
      allowlisted_repository_paths capabilities gate_requirements budget external_effects roles
      stage_constraints anti_loop preactivation_host_residual_preflight created_at_utc
    ], "P3 HPE Task Contract")
    residual_preflight = validate_hpe_residual_preflight!(
      decision, contract["preactivation_host_residual_preflight"], stage_index
    )
    expected_constraints = stage.reject do |key, _value|
      %w[
        ordinal stage_id task_id kind objective claim_boundary budget resources
        allowlisted_repository_paths capabilities gate_requirements required_reviewers
        delivery_percent_on_pass strict_exit_percent_on_pass pass_unlocks_only
      ].include?(key)
    end
    assert(contract["schema_version"] == "p3-hpe-phase-delegated-task-contract/v1" &&
           contract["record_type"] == "P3_HPE_PHASE_DELEGATED_TASK_CONTRACT" &&
           contract["phase"] == "P3" && contract["route_id"] == HPE_ROUTE_ID &&
           contract["stage_ordinal"] == stage_index + 1 &&
           contract["stage_id"] == stage.fetch("stage_id") &&
           contract["task_id"] == stage.fetch("task_id") &&
           contract["task_kind"] == stage.fetch("kind") &&
           contract["status"] == "FROZEN_PREACTIVATION" &&
           contract["objective"] == stage.fetch("objective") &&
           contract["claim_boundary"] == stage.fetch("claim_boundary") &&
           contract["founder_decision"] == hpe_founder_decision_projection &&
           contract["resources"] == resource &&
           contract["allowlisted_repository_paths"] ==
             stage.fetch("allowlisted_repository_paths") &&
           contract["capabilities"] == stage.fetch("capabilities") &&
           contract["gate_requirements"] == stage.fetch("gate_requirements") &&
           contract["budget"] == stage.fetch("budget") &&
           contract["external_effects"] == HPE_EXTERNAL_EFFECTS &&
           contract["roles"] == {
             "owner" => "MASTER_CEO_AGENT", "worker" => "IMPLEMENTATION_AGENT",
             "independent_reviewers" => HPE_REVIEW_ROLES
           } && contract["stage_constraints"] == expected_constraints &&
           contract["anti_loop"] == decision.dig("route", "anti_loop") &&
           contract["preactivation_host_residual_preflight"] == residual_preflight,
           "P3 HPE Task Contract semantic or authority drift")
    tik_timestamp!(contract["created_at_utc"], "P3 HPE Contract timestamp")
    activation_parent = validate_hpe_activation_parent!(
      root, decision, contract.fetch("activation_parent"), stage_index
    )
    [contract_identity, contract, activation_parent]
  end

  def validate_hpe_authority!(root, decision, identity, stage_index, contract_identity,
                              activation_parent)
    stage = hpe_stage(decision, stage_index)
    resource = stage.fetch("resources")
    authority_identity, authority = read_tik_rooted_json!(
      identity, "P3 HPE Task authority", root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("authority_path")
    )
    exact_keys(authority, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id status
      authority_scope issuer issued_at_utc contract founder_decision activation_parent resources
      allowlisted_repository_paths capabilities gate_requirements budget external_effects roles
      preactivation_host_residual_preflight authorization_id execution_nonce reuse_allowed
    ], "P3 HPE Task authority")
    assert(authority["schema_version"] == "p3-hpe-phase-delegated-task-authority/v1" &&
           authority["record_type"] == "P3_HPE_PHASE_DELEGATED_TASK_AUTHORITY" &&
           authority["phase"] == "P3" && authority["route_id"] == HPE_ROUTE_ID &&
           authority["stage_ordinal"] == stage_index + 1 &&
           authority["stage_id"] == stage.fetch("stage_id") &&
           authority["task_id"] == stage.fetch("task_id") &&
           authority["status"] == "AUTHORIZED_SINGLE_USE" &&
           authority["authority_scope"] == "P3_PHASE_DELEGATED_TASK" &&
           authority["issuer"] == "MASTER_CEO_AGENT" &&
           authority["contract"] == contract_identity &&
           authority["founder_decision"] == hpe_founder_decision_projection &&
           authority["activation_parent"] == activation_parent &&
           authority["resources"] == resource &&
           authority["allowlisted_repository_paths"] ==
             stage.fetch("allowlisted_repository_paths") &&
           authority["capabilities"] == stage.fetch("capabilities") &&
           authority["gate_requirements"] == stage.fetch("gate_requirements") &&
           authority["budget"] == stage.fetch("budget") &&
           authority["external_effects"] == HPE_EXTERNAL_EFFECTS &&
           authority["roles"] == {
             "owner" => "MASTER_CEO_AGENT", "worker" => "IMPLEMENTATION_AGENT",
             "independent_reviewers" => HPE_REVIEW_ROLES
           } && authority["preactivation_host_residual_preflight"] ==
             (stage_index.zero? ?
               validate_hpe_residual_preflight!(
                 decision, authority["preactivation_host_residual_preflight"], stage_index
               ) : nil) && authority["reuse_allowed"] == false,
           "P3 HPE Task authority semantic or cross-binding drift")
    tik_timestamp!(authority["issued_at_utc"], "P3 HPE authority timestamp")
    tik_uuid!(authority["authorization_id"], "P3 HPE authorization ID")
    tik_uuid!(authority["execution_nonce"], "P3 HPE execution nonce")
    [authority_identity, authority]
  end

  def hpe_repository_path_allowed?(decision, path, stage_index)
    return false unless path.is_a?(String) && !Pathname.new(path).absolute? &&
                        Pathname.new(path).cleanpath.to_s == path && !path.start_with?("../")

    hpe_stage(decision, stage_index).fetch("allowlisted_repository_paths").any? do |allowed|
      path == allowed || path.start_with?("#{allowed}/")
    end
  end

  def hpe_residual_preflight_path(decision)
    "#{hpe_stage_resource(decision, 0).fetch('evidence_root')}/custody/" \
      "P3_HPE_F1_HOST_RESIDUAL_ISOLATION_PREFLIGHT_V1.json"
  end

  def validate_hpe_residual_preflight!(decision, identity, stage_index)
    return nil unless stage_index.zero?

    preflight_identity, preflight = read_tik_rooted_json!(
      identity, "P3 HPE host-residual isolation preflight",
      root_path: hpe_stage_resource(decision, 0).fetch("evidence_root"),
      expected_path: hpe_residual_preflight_path(decision)
    )
    exact_keys(preflight, %w[
      schema_version record_type phase route_id stage_id task_id disclosed_residual_count
      observed_residual_count_at_preflight accepted_state_set inspected_task_roots
      hpe_path_owner_count tcp_listener_count hpe_lock_or_db_owner_count
      existing_database_mutation_performed irreversible_deletion_performed result observed_at_utc
    ], "P3 HPE host-residual preflight")
    stage = hpe_stage(decision, 0)
    roots = [stage.dig("resources", "worktree"), stage.dig("resources", "evidence_root")]
    assert(preflight["schema_version"] == "p3-hpe-host-residual-isolation-preflight/v1" &&
           preflight["record_type"] == "P3_HPE_HOST_RESIDUAL_ISOLATION_PREFLIGHT" &&
           preflight["phase"] == "P3" && preflight["route_id"] == HPE_ROUTE_ID &&
           preflight["stage_id"] == stage.fetch("stage_id") &&
           preflight["task_id"] == stage.fetch("task_id") &&
           preflight["disclosed_residual_count"] == 28 &&
           preflight["observed_residual_count_at_preflight"].is_a?(Integer) &&
           preflight["observed_residual_count_at_preflight"].between?(0, 28) &&
           preflight["accepted_state_set"] == ["UE"] &&
           preflight["inspected_task_roots"] == roots &&
           preflight["hpe_path_owner_count"] == 0 &&
           preflight["tcp_listener_count"] == 0 &&
           preflight["hpe_lock_or_db_owner_count"] == 0 &&
           preflight["existing_database_mutation_performed"] == false &&
           preflight["irreversible_deletion_performed"] == false &&
           preflight["result"] == "PASS_NO_NEW_TASK_RESOURCE_OVERLAP",
           "P3 HPE host-residual preflight does not prove the exact no-overlap boundary")
    tik_timestamp!(preflight["observed_at_utc"], "P3 HPE residual preflight timestamp")
    preflight_identity
  end

  def validate_hpe_live_residual_isolation!(decision, stage_index)
    return true unless stage_index.zero?

    ps_out, ps_err, ps_status = Open3.capture3("ps", "-axo", "pid=,ppid=,state=,command=")
    assert(ps_status.success?, "P3 HPE residual ps preflight failed: #{ps_err.strip}")
    ue = ps_out.lines.each_with_object([]) do |line, residuals|
      pid, ppid, state, command = line.strip.split(/\s+/, 4)
      next unless state == "UE"

      residuals << {"pid" => pid, "ppid" => ppid, "command" => command.to_s}
    end
    assert(ue.length <= 28, "P3 HPE residual UE process count expanded beyond disclosure")
    roots = [hpe_stage_resource(decision, stage_index).fetch("worktree"),
             hpe_stage_resource(decision, stage_index).fetch("evidence_root")]
    assert(ue.none? { |process| roots.any? { |path| process.fetch("command").include?(path) } },
           "P3 HPE residual process command owns a new Task root")
    return true if ue.empty?

    pids = ue.map { |process| process.fetch("pid") }.join(",")
    lsof_out, lsof_err, lsof_status = Open3.capture3("lsof", "-nP", "-a", "-p", pids)
    assert(lsof_status.success?, "P3 HPE residual lsof preflight failed: #{lsof_err.strip}")
    assert(roots.none? { |path| lsof_out.include?(path) },
           "P3 HPE residual process owns a new worktree or Evidence path")
    listen_out, _listen_err, listen_status = Open3.capture3(
      "lsof", "-nP", "-a", "-p", pids, "-iTCP", "-sTCP:LISTEN"
    )
    assert(!listen_status.success? && listen_out.empty?,
           "P3 HPE residual process retains a TCP listener")
    true
  end

  def hpe_executable_gate_requirements(stage)
    gates = array(stage["gate_requirements"], "P3 HPE stage Gate requirements")
    executable = gates - ["THREE_INDEPENDENT_REVIEWS_PASS"]
    assert(!executable.empty? && executable.length == gates.length - 1,
           "P3 HPE executable Gate set does not partition the receipt-level Review Gate")
    executable
  end

  def hpe_json_pointer(value, pointer, label)
    assert(pointer.is_a?(String) && pointer.start_with?("/") && pointer.length > 1,
           "#{label} JSON pointer is invalid")
    pointer.split("/")[1..].reduce(value) do |current, encoded|
      token = encoded.gsub("~1", "/").gsub("~0", "~")
      if current.is_a?(Hash)
        assert(current.key?(token), "#{label} JSON pointer is missing #{token.inspect}")
        current.fetch(token)
      elsif current.is_a?(Array)
        assert(token.match?(/\A(?:0|[1-9][0-9]*)\z/) && token.to_i < current.length,
               "#{label} JSON pointer array index is invalid")
        current.fetch(token.to_i)
      else
        fail!("#{label} JSON pointer traverses a scalar")
      end
    end
  end

  def validate_hpe_candidate_manifest!(root, decision, identity, stage_index,
                                       contract_identity, authority_identity,
                                       activation_parent, terminal: false,
                                       expected_path: nil, expected_candidate_id: nil)
    stage = hpe_stage(decision, stage_index)
    resource = stage.fetch("resources")
    manifest_identity, manifest = read_tik_rooted_json!(
      identity, "P3 HPE candidate manifest", root_path: resource.fetch("evidence_root"),
      expected_path: expected_path || resource.fetch("candidate_manifest_path")
    )
    keys = %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id candidate
      activation_parent contract authority generated_from_actual_bytes repository_files
      external_files inventory_canonicalization inventory_sha256 created_at_utc
    ]
    keys << "frozen_predecessor_inputs" if stage_index.positive?
    exact_keys(manifest, keys, "P3 HPE candidate manifest")
    candidate = exact_keys(manifest["candidate"],
                           %w[candidate_id candidate_kind commit tree source_branch],
                           "P3 HPE candidate identity")
    expected_kind = %w[FOUNDATION_CANDIDATE PRODUCT_CANDIDATE LOCKED_STAGE_2_PRODUCT].fetch(stage_index)
    expected_branch = stage_index == 2 ? hpe_stage_resource(decision, 1).fetch("branch") :
      resource.fetch("branch")
    valid_candidate_id = if expected_candidate_id
      candidate["candidate_id"] == expected_candidate_id
    elsif stage_index == 2
      candidate["candidate_id"] == "LOCKED_STAGE_2_PRODUCT"
    else
      %w[CANDIDATE_1 CANDIDATE_2].include?(candidate["candidate_id"])
    end
    assert(valid_candidate_id && candidate["candidate_kind"] == expected_kind &&
           candidate["source_branch"] == expected_branch &&
           candidate["commit"].is_a?(String) && candidate["commit"].match?(/\A[0-9a-f]{40}\z/) &&
           candidate["tree"].is_a?(String) && candidate["tree"].match?(/\A[0-9a-f]{40}\z/),
           "P3 HPE candidate identity is invalid or exceeds Candidate 2")
    unless terminal
      assert(git!(root, "rev-parse", "#{candidate.fetch('commit')}^{tree}") ==
               candidate.fetch("tree"), "P3 HPE candidate commit/tree drift")
    end

    repository_files = array(manifest["repository_files"], "P3 HPE repository inventory")
    paths = repository_files.map do |entry|
      exact_keys(entry, %w[
        relative_path git_mode object_type git_blob_sha1 byte_length sha256
      ], "P3 HPE repository file identity")
      path = entry.fetch("relative_path")
      assert(hpe_repository_path_allowed?(decision, path, stage_index),
             "P3 HPE candidate repository path exceeds the stage allowlist: #{path}")
      assert(%w[100644 100755].include?(entry["git_mode"]) &&
             entry["object_type"] == "blob" &&
             entry["git_blob_sha1"].is_a?(String) &&
             entry["git_blob_sha1"].match?(/\A[0-9a-f]{40}\z/) &&
             entry["byte_length"].is_a?(Integer) && entry["byte_length"] >= 0 &&
             entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[0-9a-f]{64}\z/),
             "P3 HPE candidate repository identity is not closed: #{path}")
      unless terminal
        assert(tik_git_tree_entry!(root, candidate.fetch("commit"), path,
                                   "P3 HPE candidate repository file") ==
                 entry.slice("git_mode", "object_type", "git_blob_sha1"),
               "P3 HPE candidate repository mode/type/blob drift: #{path}")
        bytes = tik_git_bytes!(root, candidate.fetch("commit"), path,
                               "P3 HPE candidate repository file")
        assert(bytes.bytesize == entry.fetch("byte_length") &&
               Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
               "P3 HPE candidate repository bytes drift: #{path}")
      end
      path
    end
    assert(paths == paths.sort && paths.uniq.length == paths.length,
           "P3 HPE repository inventory must be unique and sorted")
    if stage_index == 2
      assert(repository_files.empty?, "P3 HPE Audit cannot contain repository mutations")
      git!(root, "merge-base", "--is-ancestor", candidate.fetch("commit"),
           activation_parent.fetch("commit")) unless terminal
    elsif !terminal
      git!(root, "merge-base", "--is-ancestor", activation_parent.fetch("commit"),
           candidate.fetch("commit"))
      changed = git!(root, "diff", "--name-status", "--diff-filter=ACMRD",
                     activation_parent.fetch("commit"), candidate.fetch("commit"))
        .lines.map(&:strip).reject(&:empty?).map do |line|
          status, path, unexpected = line.split("\t", 3)
          assert(unexpected.nil? && %w[A M].include?(status) && path,
                 "P3 HPE candidate contains a deletion, rename, copy or unknown Git delta")
          path
        end.sort
      assert(changed == paths && !changed.empty?,
             "P3 HPE candidate manifest does not bind the exact non-empty changed set")
      if stage_index == 0
        assert(changed.none? { |path| path.start_with?("backend-spring/src/main/") },
               "P3 HPE Foundation candidate mutated product source")
      else
        assert(changed.any? { |path| path.start_with?("backend-spring/src/main/") },
               "P3 HPE Product candidate lacks a non-empty product source diff")
      end
    end

    external_files = array(manifest["external_files"], "P3 HPE external Evidence inventory")
    assert(!external_files.empty?, "P3 HPE candidate manifest requires real external Evidence")
    reserved_paths = resource.reject { |key, _| %w[branch worktree evidence_root].include?(key) }.values
    reserved_paths << hpe_residual_preflight_path(decision) if stage_index.zero?
    external_paths = external_files.map do |entry|
      record = exact_keys(entry, %w[path byte_length sha256], "P3 HPE external Evidence identity")
      assert(!reserved_paths.include?(record.fetch("path")),
             "P3 HPE manifest cannot inventory a control, review or receipt leaf")
      tik_assert_path_under!(record.fetch("path"), resource.fetch("evidence_root"),
                             "P3 HPE external Evidence")
      read_tik_external_identity!(record, "P3 HPE external Evidence", create_once: true)
      record.fetch("path")
    end
    assert(external_paths == external_paths.sort && external_paths.uniq.length == external_paths.length,
           "P3 HPE external Evidence inventory must be unique and sorted")
    inventory = {"repository_files" => repository_files, "external_files" => external_files}
    assert(manifest["schema_version"] == "p3-hpe-candidate-manifest/v1" &&
           manifest["record_type"] == "P3_HPE_CANDIDATE_MANIFEST" &&
           manifest["phase"] == "P3" && manifest["route_id"] == HPE_ROUTE_ID &&
           manifest["stage_ordinal"] == stage_index + 1 &&
           manifest["stage_id"] == stage.fetch("stage_id") &&
           manifest["task_id"] == stage.fetch("task_id") &&
           manifest["activation_parent"] == activation_parent &&
           manifest["contract"] == contract_identity &&
           manifest["authority"] == authority_identity &&
           manifest["generated_from_actual_bytes"] == true &&
           manifest["inventory_canonicalization"] == "RECURSIVE_KEY_SORT_COMPACT_JSON_UTF8" &&
           manifest["inventory_sha256"] ==
             Digest::SHA256.hexdigest(JSON.generate(canonical(inventory))),
           "P3 HPE candidate manifest semantic or inventory binding drift")
    if stage_index.positive?
      expected_keys = %w[
        foundation_candidate_manifest foundation_gate_evidence foundation_task_gate_receipt
      ]
      expected_keys += %w[
        product_candidate_manifest product_gate_evidence product_task_gate_receipt
      ] if stage_index == 2
      predecessors = exact_keys(manifest["frozen_predecessor_inputs"], expected_keys,
                                "P3 HPE frozen predecessor inputs")
      predecessors.each do |name, predecessor_identity|
        exact_keys(predecessor_identity, %w[path byte_length sha256],
                   "P3 HPE frozen predecessor input #{name}")
      end
    end
    tik_timestamp!(manifest["created_at_utc"], "P3 HPE candidate manifest timestamp")
    [manifest_identity, manifest, candidate]
  end

  def validate_hpe_gate_evidence!(decision, identity, stage_index, contract_identity,
                                  authority_identity, manifest_identity, manifest,
                                  terminal: false, allow_non_pass: false, expected_path: nil)
    stage = hpe_stage(decision, stage_index)
    resource = stage.fetch("resources")
    evidence_identity, evidence = read_tik_rooted_json!(
      identity, "P3 HPE Gate Evidence", root_path: resource.fetch("evidence_root"),
      expected_path: expected_path || resource.fetch("gate_evidence_path")
    )
    exact_keys(evidence, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id disposition
      candidate_manifest contract authority generated_from_actual_bytes evidence_files
      executed_checks gate_results external_effects recorded_at_utc
    ], "P3 HPE Gate Evidence")
    evidence_files = array(evidence["evidence_files"], "P3 HPE Gate Evidence files")
    assert(evidence_files == manifest.fetch("external_files") && !evidence_files.empty?,
           "P3 HPE Gate Evidence does not bind the candidate raw Evidence inventory")
    expected_gates = hpe_executable_gate_requirements(stage)
    results = exact_keys(evidence["gate_results"], expected_gates, "P3 HPE Gate results")
    checks = array(evidence["executed_checks"], "P3 HPE executed Gate checks")
    observations = checks.map do |raw_identity|
      raw_identity = exact_keys(raw_identity, %w[path byte_length sha256],
                                "P3 HPE Gate observation identity")
      assert(evidence_files.include?(raw_identity),
             "P3 HPE Gate observation is not in the candidate Evidence inventory")
      observation = parse_tik_json!(
        read_tik_external_identity!(raw_identity, "P3 HPE Gate observation", create_once: true),
        "P3 HPE Gate observation"
      )
      exact_keys(observation, %w[
        schema_version record_type phase route_id stage_ordinal stage_id task_id candidate
        gate_key observed_status command source_identities derivation recorded_at_utc
      ], "P3 HPE Gate observation")
      command = exact_keys(observation["command"], %w[cwd argv exit_code],
                           "P3 HPE Gate command")
      cwd = Pathname.new(command.fetch("cwd"))
      cwd_allowed = [resource.fetch("worktree"), resource.fetch("evidence_root")].any? do |allowed|
        cwd.to_s == allowed || cwd.to_s.start_with?("#{allowed}/")
      end
      assert(observation["schema_version"] == "p3-hpe-gate-observation/v1" &&
             observation["record_type"] == "P3_HPE_GATE_OBSERVATION" &&
             observation["phase"] == "P3" && observation["route_id"] == HPE_ROUTE_ID &&
             observation["stage_ordinal"] == stage_index + 1 &&
             observation["stage_id"] == stage.fetch("stage_id") &&
             observation["task_id"] == stage.fetch("task_id") &&
             observation["candidate"] == manifest.fetch("candidate") &&
             expected_gates.include?(observation["gate_key"]) &&
             %w[PASS NON_PASS].include?(observation["observed_status"]) &&
             cwd.absolute? && cwd.cleanpath.to_s == cwd.to_s && cwd_allowed &&
             command["argv"].is_a?(Array) && !command["argv"].empty? &&
             command["argv"].all? { |part| part.is_a?(String) && !part.empty? } &&
             command["exit_code"].is_a?(Integer) &&
             observation["source_identities"].is_a?(Array),
             "P3 HPE Gate observation semantic binding drift")
      derivation = exact_keys(observation["derivation"], %w[
        schema_version rule source_assertions command_exit_assertion_index
      ], "P3 HPE Gate observation derivation")
      source_assertions = array(derivation["source_assertions"],
                                "P3 HPE Gate source assertions")
      assert(derivation["schema_version"] == "p3-hpe-gate-raw-derivation/v1" &&
             derivation["rule"] ==
               "ALL_JSON_POINTER_PASS_VALUES_MATCH_AND_COMMAND_EXIT_ZERO" &&
             !source_assertions.empty? &&
             derivation["command_exit_assertion_index"].is_a?(Integer) &&
             derivation["command_exit_assertion_index"].between?(0,
                                                                  source_assertions.length - 1),
             "P3 HPE Gate derivation rule is invalid")
      source_projection = []
      actual_values = source_assertions.map do |source_assertion|
        assertion = exact_keys(source_assertion, %w[
          source_identity json_pointer pass_value
        ], "P3 HPE Gate source assertion")
        source_identity = exact_keys(assertion["source_identity"], %w[path byte_length sha256],
                                     "P3 HPE Gate observation source identity")
        assert(evidence_files.include?(source_identity),
               "P3 HPE Gate observation source is not manifest-bound")
        source_projection << source_identity
        source = parse_tik_json!(
          read_tik_external_identity!(source_identity, "P3 HPE Gate raw source",
                                      create_once: true),
          "P3 HPE Gate raw source"
        )
        hpe_json_pointer(source, assertion.fetch("json_pointer"),
                         "P3 HPE Gate source assertion")
      end
      expected_sources = source_projection.uniq.sort_by { |source| source.fetch("path") }
      actual_sources = observation["source_identities"].map do |source_identity|
        exact_keys(source_identity, %w[path byte_length sha256],
                   "P3 HPE Gate observation source identity")
      end
      assert(actual_sources == actual_sources.sort_by { |source| source.fetch("path") } &&
             actual_sources.uniq == actual_sources && actual_sources == expected_sources,
             "P3 HPE Gate observation source inventory is not closed")
      exit_index = derivation.fetch("command_exit_assertion_index")
      pass_values = source_assertions.map { |source_assertion| source_assertion.fetch("pass_value") }
      assert(actual_values.fetch(exit_index) == command.fetch("exit_code"),
             "P3 HPE Gate command exit code is not derived from retained raw bytes")
      derived_status = if command.fetch("exit_code").zero? && actual_values == pass_values
        "PASS"
      else
        "NON_PASS"
      end
      assert(observation["observed_status"] == derived_status,
             "P3 HPE Gate observation status is not mechanically derived from raw bytes")
      tik_timestamp!(observation["recorded_at_utc"], "P3 HPE Gate observation timestamp")
      [observation.fetch("gate_key"), observation.fetch("observed_status"),
       command.fetch("exit_code")]
    end
    assert(observations.map(&:first).sort == expected_gates.sort &&
           observations.map(&:first).uniq.length == observations.length &&
           results == observations.to_h { |gate, status, _exit| [gate, status] },
           "P3 HPE Gate Evidence is not derived from the exact frozen observation set")
    assert(evidence["schema_version"] == "p3-hpe-gate-evidence/v1" &&
           evidence["record_type"] == "P3_HPE_GATE_EVIDENCE" && evidence["phase"] == "P3" &&
           evidence["route_id"] == HPE_ROUTE_ID && evidence["stage_ordinal"] == stage_index + 1 &&
           evidence["stage_id"] == stage.fetch("stage_id") &&
           evidence["task_id"] == stage.fetch("task_id") &&
           evidence["candidate_manifest"] == manifest_identity &&
           evidence["contract"] == contract_identity && evidence["authority"] == authority_identity &&
           evidence["generated_from_actual_bytes"] == true &&
           evidence["external_effects"] == HPE_EXTERNAL_EFFECTS &&
           ((terminal || allow_non_pass) ? %w[PASS_CANDIDATE NON_PASS_CANDIDATE] :
             ["PASS_CANDIDATE"])
             .include?(evidence["disposition"]),
           "P3 HPE Gate Evidence semantic cross-binding drift")
    if evidence["disposition"] == "PASS_CANDIDATE"
      assert(results.values.all? { |status| status == "PASS" } &&
             observations.all? { |_gate, _status, exit_code| exit_code == 0 },
             "P3 HPE PASS Gate Evidence contains a non-PASS result")
    else
      assert(results.values.any? { |status| status != "PASS" } ||
             observations.any? { |_gate, _status, exit_code| exit_code != 0 },
             "P3 HPE NON_PASS Gate Evidence contains no mechanical failure")
    end
    tik_timestamp!(evidence["recorded_at_utc"], "P3 HPE Gate Evidence timestamp")
    [evidence_identity, evidence]
  end

  def hpe_validate_findings!(value, label, include_role: false)
    findings = array(value, label)
    findings.each do |finding|
      keys = %w[finding_id severity category summary exact_evidence minimal_closure]
      keys << "role" if include_role
      exact_keys(finding, keys, label)
      assert(finding["finding_id"].is_a?(String) && !finding["finding_id"].empty? &&
             %w[P0 P1].include?(finding["severity"]) &&
             HPE_FINDING_CATEGORIES.include?(finding["category"]) &&
             finding["summary"].is_a?(String) && !finding["summary"].empty? &&
             finding["exact_evidence"].is_a?(Array) && !finding["exact_evidence"].empty? &&
             finding["exact_evidence"].all? { |line| line.is_a?(String) && !line.empty? } &&
             finding["minimal_closure"].is_a?(String) && !finding["minimal_closure"].empty? &&
             (!include_role || HPE_REVIEW_ROLES.include?(finding["role"])),
             "#{label} schema drift")
    end
    findings
  end

  def validate_hpe_review_record!(decision, identity, role, stage_index, contract_identity,
                                  authority_identity, manifest_identity, gate_identity,
                                  expected_path:, expected_cycle:)
    stage = hpe_stage(decision, stage_index)
    resource = stage.fetch("resources")
    review_identity, review = read_tik_rooted_json!(
      identity, "P3 HPE #{role} review", root_path: resource.fetch("evidence_root"),
      expected_path: expected_path
    )
    exact_keys(review, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id role review_cycle
      candidate_manifest gate_evidence contract authority independence verdict finding_categories
      blocking_findings cycle_1_review cycle_1_finding_set cycle_2_closure reviewed_at_utc
    ], "P3 HPE independent review")
    findings = hpe_validate_findings!(review["blocking_findings"], "P3 HPE blocking finding")
    ids = findings.map { |finding| finding.fetch("finding_id") }
    categories = array(review["finding_categories"], "P3 HPE review categories")
    assert(ids.uniq.length == ids.length && categories.uniq.length == categories.length &&
           categories.all? { |category| HPE_FINDING_CATEGORIES.include?(category) } &&
           categories.sort == findings.map { |finding| finding.fetch("category") }.uniq.sort &&
           review["schema_version"] == "p3-hpe-independent-review/v1" &&
           review["record_type"] == "P3_HPE_INDEPENDENT_REVIEW" && review["phase"] == "P3" &&
           review["route_id"] == HPE_ROUTE_ID && review["stage_ordinal"] == stage_index + 1 &&
           review["stage_id"] == stage.fetch("stage_id") &&
           review["task_id"] == stage.fetch("task_id") && review["role"] == role &&
           review["review_cycle"] == expected_cycle &&
           review["candidate_manifest"] == manifest_identity &&
           review["gate_evidence"] == gate_identity && review["contract"] == contract_identity &&
           review["authority"] == authority_identity &&
           review["independence"] == {
             "implemented_candidate" => false, "issued_task_authority" => false,
             "read_other_reviews" => false, "read_rejected_lineage" => false
           } && %w[PASS NON_PASS].include?(review["verdict"]),
           "P3 HPE independent review semantic or independence drift")
    if review["verdict"] == "PASS"
      assert(findings.empty? && categories.empty?, "P3 HPE PASS review retains blockers")
    else
      assert(!findings.empty?, "P3 HPE NON_PASS review lacks a blocker")
    end
    tik_timestamp!(review["reviewed_at_utc"], "P3 HPE review timestamp")
    [review_identity, review]
  end

  def validate_hpe_cycle_1_finding_set!(root, decision, identity, stage_index,
                                        contract_identity, authority_identity,
                                        activation_parent, terminal: false)
    resource = hpe_stage_resource(decision, stage_index)
    set_identity, finding_set = read_tik_rooted_json!(
      identity, "P3 HPE Cycle 1 frozen finding set",
      root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("cycle_1_finding_set_path")
    )
    exact_keys(finding_set, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id contract authority
      cycle_1_candidate_manifest cycle_1_gate_evidence cycle_1_reviews
      complete_p0_p1_set_frozen findings frozen_at_utc
    ], "P3 HPE Cycle 1 frozen finding set")
    manifest_identity, manifest, = validate_hpe_candidate_manifest!(
      root, decision, finding_set["cycle_1_candidate_manifest"], stage_index,
      contract_identity, authority_identity, activation_parent, terminal: terminal,
      expected_path: resource.fetch("cycle_1_candidate_manifest_path"),
      expected_candidate_id: "CANDIDATE_1"
    )
    gate_identity, = validate_hpe_gate_evidence!(
      decision, finding_set["cycle_1_gate_evidence"], stage_index, contract_identity,
      authority_identity, manifest_identity, manifest, terminal: false,
      allow_non_pass: true,
      expected_path: resource.fetch("cycle_1_gate_evidence_path")
    )
    review_projection = exact_keys(finding_set["cycle_1_reviews"],
                                   %w[cto security quality_evaluation],
                                   "P3 HPE Cycle 1 review identities")
    reviews = {}
    {
      "cto" => ["CTO_AGENT", "cycle_1_cto_review_path"],
      "security" => ["SECURITY_AGENT", "cycle_1_security_review_path"],
      "quality_evaluation" => ["QUALITY_EVALUATION_AGENT", "cycle_1_quality_review_path"]
    }.each do |key, (role, path_key)|
      review_identity, review = validate_hpe_review_record!(
        decision, review_projection.fetch(key), role, stage_index, contract_identity,
        authority_identity, manifest_identity, gate_identity,
        expected_path: resource.fetch(path_key), expected_cycle: 1
      )
      assert(review_identity == review_projection.fetch(key) &&
             review["cycle_1_review"].nil? && review["cycle_1_finding_set"].nil? &&
             review["cycle_2_closure"].nil?,
             "P3 HPE Cycle 1 review projection or lifecycle drift")
      reviews[role] = review
    end
    expected_findings = reviews.flat_map do |role, review|
      review.fetch("blocking_findings").map { |finding| finding.merge("role" => role) }
    end.sort_by { |finding| [finding.fetch("role"), finding.fetch("finding_id")] }
    frozen = hpe_validate_findings!(finding_set["findings"],
                                    "P3 HPE Cycle 1 frozen finding", include_role: true)
    ids = frozen.map { |finding| finding.fetch("finding_id") }
    stage = hpe_stage(decision, stage_index)
    assert(frozen == expected_findings && !frozen.empty? && ids.uniq.length == ids.length &&
           finding_set["schema_version"] == "p3-hpe-cycle-1-finding-set/v1" &&
           finding_set["record_type"] == "P3_HPE_CYCLE_1_FROZEN_FINDING_SET" &&
           finding_set["phase"] == "P3" && finding_set["route_id"] == HPE_ROUTE_ID &&
           finding_set["stage_ordinal"] == stage_index + 1 &&
           finding_set["stage_id"] == stage.fetch("stage_id") &&
           finding_set["task_id"] == stage.fetch("task_id") &&
           finding_set["contract"] == contract_identity &&
           finding_set["authority"] == authority_identity &&
           finding_set["cycle_1_candidate_manifest"] == manifest_identity &&
           finding_set["cycle_1_gate_evidence"] == gate_identity &&
           finding_set["complete_p0_p1_set_frozen"] == true,
           "P3 HPE Cycle 1 frozen finding-set binding drift")
    tik_timestamp!(finding_set["frozen_at_utc"], "P3 HPE finding-set timestamp")
    [set_identity, reviews, frozen]
  end

  def validate_hpe_review!(root, decision, identity, role, stage_index, contract_identity,
                           authority_identity, activation_parent, manifest_identity,
                           gate_identity, terminal: false)
    resource = hpe_stage_resource(decision, stage_index)
    path_key = {
      "CTO_AGENT" => "cto_review_path", "SECURITY_AGENT" => "security_review_path",
      "QUALITY_EVALUATION_AGENT" => "quality_review_path"
    }.fetch(role)
    preview_identity, preview = read_tik_rooted_json!(
      identity, "P3 HPE #{role} review", root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch(path_key)
    )
    cycle = preview["review_cycle"]
    assert([1, 2].include?(cycle) && !(stage_index == 2 && cycle == 2),
           "P3 HPE review cycle exceeds the stage budget")
    review_identity, review = validate_hpe_review_record!(
      decision, preview_identity, role, stage_index, contract_identity, authority_identity,
      manifest_identity, gate_identity, expected_path: resource.fetch(path_key),
      expected_cycle: cycle
    )
    if cycle == 1
      assert(review["cycle_1_review"].nil? && review["cycle_1_finding_set"].nil? &&
             review["cycle_2_closure"].nil?,
             "P3 HPE Cycle 1 final review contains future-cycle state")
    else
      finding_set_identity, cycle_1_reviews, frozen = validate_hpe_cycle_1_finding_set!(
        root, decision, review["cycle_1_finding_set"], stage_index, contract_identity,
        authority_identity, activation_parent, terminal: terminal
      )
      prior = cycle_1_reviews.fetch(role)
      prior_path_key = {
        "CTO_AGENT" => "cycle_1_cto_review_path",
        "SECURITY_AGENT" => "cycle_1_security_review_path",
        "QUALITY_EVALUATION_AGENT" => "cycle_1_quality_review_path"
      }.fetch(role)
      prior_identity = exact_keys(review["cycle_1_review"], %w[path byte_length sha256],
                                  "P3 HPE Cycle 2 prior review identity")
      assert(review["cycle_1_finding_set"] == finding_set_identity &&
             prior_identity.fetch("path") == resource.fetch(prior_path_key),
             "P3 HPE Cycle 2 prior-input binding drift")
      read_tik_external_identity!(prior_identity, "P3 HPE Cycle 2 prior review", create_once: true)
      closure = exact_keys(review["cycle_2_closure"],
                           %w[closed_finding_ids unresolved_finding_ids regression_findings],
                           "P3 HPE Cycle 2 closure")
      initial = prior.fetch("blocking_findings")
      initial_ids = initial.map { |finding| finding.fetch("finding_id") }
      closed = array(closure["closed_finding_ids"], "P3 HPE closed findings")
      unresolved = array(closure["unresolved_finding_ids"], "P3 HPE unresolved findings")
      regressions = hpe_validate_findings!(closure["regression_findings"],
                                           "P3 HPE direct regression")
      regression_ids = regressions.map { |finding| finding.fetch("finding_id") }
      frozen_ids = frozen.map { |finding| finding.fetch("finding_id") }
      assert(closed.uniq.length == closed.length && unresolved.uniq.length == unresolved.length &&
             regression_ids.uniq.length == regression_ids.length &&
             (closed & unresolved).empty? && (closed + unresolved).sort == initial_ids.sort &&
             (regression_ids & frozen_ids).empty?,
             "P3 HPE Cycle 2 closure does not partition the frozen findings")
      expected_current = initial.select do |finding|
        unresolved.include?(finding.fetch("finding_id"))
      end + regressions
      assert(review.fetch("blocking_findings").sort_by { |finding| finding.fetch("finding_id") } ==
               expected_current.sort_by { |finding| finding.fetch("finding_id") },
             "P3 HPE Cycle 2 review drip-fed a non-regression finding")
      if review["verdict"] == "PASS"
        assert(unresolved.empty? && regressions.empty? && closed.sort == initial_ids.sort,
               "P3 HPE Cycle 2 PASS did not close its complete Cycle 1 finding set")
      end
    end
    [review_identity, review]
  end

  def validate_hpe_terminal_bundle!(root, decision, bundle, stage_index, activation_parent,
                                    candidate, manifest)
    bundle_path = bundle.fetch("path")
    _verify_out, verify_err, verify_status = Open3.capture3(
      "git", "bundle", "verify", bundle_path, chdir: root.to_s
    )
    assert(verify_status.success?,
           "P3 HPE rejected candidate bundle verification failed: #{verify_err.strip}")
    expected_ref = "refs/heads/#{candidate.fetch('source_branch')}"
    heads = git!(root, "bundle", "list-heads", bundle_path).lines.map(&:strip)
    assert(heads == ["#{candidate.fetch('commit')} #{expected_ref}"],
           "P3 HPE rejected candidate bundle does not contain the exact sole candidate head")

    resource = hpe_stage_resource(decision, stage_index)
    terminal_root = Pathname.new(resource.fetch("evidence_root")).join("terminal")
    terminal_stat = terminal_root.lstat
    assert(terminal_stat.directory? && !terminal_root.symlink? &&
           terminal_root.realpath.to_s == terminal_root.cleanpath.to_s,
           "P3 HPE terminal bundle verifier root is not a real authorized directory")
    Dir.mktmpdir(".p3-hpe-bundle-verifier-", terminal_root.to_s) do |temporary_root|
      replay = Pathname.new(temporary_root).join("candidate.git")
      _init_out, init_err, init_status = Open3.capture3("git", "init", "--bare", replay.to_s)
      assert(init_status.success?, "P3 HPE bundle replay init failed: #{init_err.strip}")
      _fetch_out, fetch_err, fetch_status = Open3.capture3(
        "git", "-C", replay.to_s, "fetch", "--no-tags", bundle_path,
        "#{expected_ref}:refs/heads/candidate"
      )
      assert(fetch_status.success?,
             "P3 HPE rejected candidate bundle is not self-contained: #{fetch_err.strip}")
      assert(git!(replay, "rev-parse", "refs/heads/candidate") == candidate.fetch("commit") &&
             git!(replay, "rev-parse", "#{candidate.fetch('commit')}^{tree}") ==
               candidate.fetch("tree"),
             "P3 HPE bundle candidate commit/tree drift")
      git!(replay, "merge-base", "--is-ancestor", activation_parent.fetch("commit"),
           candidate.fetch("commit"))
      changed = git!(
        replay, "diff", "--name-status", "--diff-filter=ACMRD",
        activation_parent.fetch("commit"), candidate.fetch("commit")
      ).lines.map(&:strip).reject(&:empty?).map do |line|
        status, path, unexpected = line.split("\t", 3)
        assert(unexpected.nil? && %w[A M].include?(status) && path,
               "P3 HPE terminal bundle contains deletion, rename, copy or unknown delta")
        path
      end.sort
      expected_paths = manifest.fetch("repository_files").map do |entry|
        path = entry.fetch("relative_path")
        assert(tik_git_tree_entry!(replay, candidate.fetch("commit"), path,
                                   "P3 HPE terminal bundle candidate file") ==
                 entry.slice("git_mode", "object_type", "git_blob_sha1"),
               "P3 HPE terminal bundle mode/type/blob differs from the immutable manifest")
        bytes = tik_git_bytes!(replay, candidate.fetch("commit"), path,
                               "P3 HPE terminal bundle candidate file")
        assert(bytes.bytesize == entry.fetch("byte_length") &&
               Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
               "P3 HPE terminal bundle bytes differ from the immutable manifest")
        path
      end.sort
      assert(changed == expected_paths && !changed.empty?,
             "P3 HPE terminal bundle changed set differs from the immutable manifest")
    end
    {
      "bundle_verified_once" => true, "sole_head_matches_candidate" => true,
      "candidate_commit_tree_matches" => true,
      "activation_parent_relation_matches" => true,
      "changed_set_matches_manifest" => true,
      "repository_mode_type_bytes_match_manifest" => true,
      "rejected_lineage_replay_count" => 1
    }
  end

  def validate_hpe_terminal_attestation!(root, decision, identity, stage_index,
                                         activation_parent, contract_identity,
                                         authority_identity, manifest_identity,
                                         candidate, bundle_identity)
    resource = hpe_stage_resource(decision, stage_index)
    attestation_identity, attestation = read_tik_rooted_json!(
      identity, "P3 HPE rejected-bundle attestation", root_path: resource.fetch("evidence_root"),
      expected_path: resource.fetch("bundle_attestation_path")
    )
    exact_keys(attestation, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id activation_parent
      contract authority candidate_manifest candidate bundle validator verification_status
      failure_reason checks verified_once_while_active future_current_state_lineage_replay_allowed
      verified_at_utc
    ], "P3 HPE rejected-bundle attestation")
    stage = hpe_stage(decision, stage_index)
    validator = exact_keys(attestation["validator"], %w[path commit tree byte_length sha256],
                           "P3 HPE terminalization validator identity")
    validator_bytes = tik_git_bytes!(
      root, activation_parent.fetch("commit"), validator.fetch("path"),
      "P3 HPE terminalization validator"
    )
    checks = exact_keys(attestation["checks"], %w[
      bundle_verified_once sole_head_matches_candidate candidate_commit_tree_matches
      activation_parent_relation_matches changed_set_matches_manifest
      repository_mode_type_bytes_match_manifest rejected_lineage_replay_count
    ], "P3 HPE rejected-bundle checks")
    pass_checks = {
      "bundle_verified_once" => true, "sole_head_matches_candidate" => true,
      "candidate_commit_tree_matches" => true,
      "activation_parent_relation_matches" => true,
      "changed_set_matches_manifest" => true,
      "repository_mode_type_bytes_match_manifest" => true,
      "rejected_lineage_replay_count" => 1
    }
    assert(attestation["schema_version"] == "p3-hpe-rejected-bundle-attestation/v1" &&
           attestation["record_type"] == "P3_HPE_REJECTED_BUNDLE_ATTESTATION" &&
           attestation["phase"] == "P3" && attestation["route_id"] == HPE_ROUTE_ID &&
           attestation["stage_ordinal"] == stage_index + 1 &&
           attestation["stage_id"] == stage.fetch("stage_id") &&
           attestation["task_id"] == stage.fetch("task_id") &&
           attestation["activation_parent"] == activation_parent &&
           attestation["contract"] == contract_identity &&
           attestation["authority"] == authority_identity &&
           attestation["candidate_manifest"] == manifest_identity &&
           attestation["candidate"] == candidate && attestation["bundle"] == bundle_identity &&
           validator["path"] == "scripts/validate-p3-final-transactional-route.rb" &&
           validator["commit"] == activation_parent.fetch("commit") &&
           validator["tree"] == activation_parent.fetch("tree") &&
           validator_bytes.bytesize == validator["byte_length"] &&
           Digest::SHA256.hexdigest(validator_bytes) == validator["sha256"] &&
           %w[PASS NON_PASS].include?(attestation["verification_status"]) &&
           attestation["verified_once_while_active"] == true &&
           attestation["future_current_state_lineage_replay_allowed"] == false,
           "P3 HPE rejected-bundle attestation binding drift")
    if attestation["verification_status"] == "PASS"
      assert(attestation["failure_reason"].nil? && checks == pass_checks,
             "P3 HPE PASS bundle attestation does not close every check")
    else
      assert(attestation["failure_reason"].is_a?(String) &&
             !attestation["failure_reason"].empty? && checks != pass_checks &&
             checks["rejected_lineage_replay_count"] == 1,
             "P3 HPE NON_PASS bundle attestation lacks its one-shot failure")
    end
    tik_timestamp!(attestation["verified_at_utc"], "P3 HPE bundle attestation timestamp")
    [attestation_identity, attestation]
  end

  def create_hpe_terminal_bundle_attestation!(root:, truth:)
    state = validate_truth!(root: root, truth: truth)
    lifecycle = truth.dig("current_phase_route", "lifecycle_stage")
    stage_index = {"FOUNDATION_TASK_ACTIVE" => 0, "PRODUCT_TASK_ACTIVE" => 1}[lifecycle]
    assert(stage_index && state == HPE_LIFECYCLE_STATES.fetch(lifecycle),
           "P3 HPE bundle attestation is allowed only while a mutable stage Task is active")
    decision = validate_hpe_decision!(Pathname.new(root).realpath)
    resource = hpe_stage_resource(decision, stage_index)
    active = mapping(truth["active_work"], "P3 HPE active work for terminalization")
    contract_identity, _contract, activation_parent = validate_hpe_contract!(
      root, decision, active.fetch("current_task_contract"), stage_index
    )
    authority_identity, _authority = validate_hpe_authority!(
      root, decision, active.fetch("authority_record"), stage_index,
      contract_identity, activation_parent
    )
    manifest_identity = tik_identity_for_exact_create_once_file!(
      resource.fetch("candidate_manifest_path"), resource.fetch("evidence_root"),
      "P3 HPE terminalization candidate manifest"
    )
    manifest_identity, manifest, candidate = validate_hpe_candidate_manifest!(
      root, decision, manifest_identity, stage_index, contract_identity, authority_identity,
      activation_parent, terminal: false
    )
    bundle_identity = tik_identity_for_exact_create_once_file!(
      resource.fetch("rejected_bundle_path"), resource.fetch("evidence_root"),
      "P3 HPE rejected candidate bundle"
    )
    attestation_path, attestation_file = tik_reserve_exclusive_create_once_file!(
      resource.fetch("bundle_attestation_path"), resource.fetch("evidence_root"),
      "P3 HPE rejected-bundle attestation"
    )
    verification_status = "PASS"
    failure_reason = nil
    checks = nil
    begin
      checks = validate_hpe_terminal_bundle!(
        root, decision, bundle_identity, stage_index, activation_parent, candidate, manifest
      )
    rescue P3FinalTransactionalRouteValidationError => error
      verification_status = "NON_PASS"
      failure_reason = error.message
      checks = {
        "bundle_verified_once" => false, "sole_head_matches_candidate" => false,
        "candidate_commit_tree_matches" => false,
        "activation_parent_relation_matches" => false,
        "changed_set_matches_manifest" => false,
        "repository_mode_type_bytes_match_manifest" => false,
        "rejected_lineage_replay_count" => 1
      }
    end
    validator_path = "scripts/validate-p3-final-transactional-route.rb"
    validator_bytes = tik_git_bytes!(root, activation_parent.fetch("commit"), validator_path,
                                     "P3 HPE terminalization validator")
    attestation = {
      "schema_version" => "p3-hpe-rejected-bundle-attestation/v1",
      "record_type" => "P3_HPE_REJECTED_BUNDLE_ATTESTATION",
      "phase" => "P3", "route_id" => HPE_ROUTE_ID,
      "stage_ordinal" => stage_index + 1,
      "stage_id" => hpe_stage(decision, stage_index).fetch("stage_id"),
      "task_id" => hpe_stage(decision, stage_index).fetch("task_id"),
      "activation_parent" => activation_parent,
      "contract" => contract_identity, "authority" => authority_identity,
      "candidate_manifest" => manifest_identity, "candidate" => candidate,
      "bundle" => bundle_identity,
      "validator" => {
        "path" => validator_path, "commit" => activation_parent.fetch("commit"),
        "tree" => activation_parent.fetch("tree"), "byte_length" => validator_bytes.bytesize,
        "sha256" => Digest::SHA256.hexdigest(validator_bytes)
      },
      "verification_status" => verification_status, "failure_reason" => failure_reason,
      "checks" => checks, "verified_once_while_active" => true,
      "future_current_state_lineage_replay_allowed" => false,
      "verified_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    identity = tik_finalize_reserved_create_once_json!(
      attestation_path, attestation_file, attestation,
      "P3 HPE rejected-bundle attestation"
    )
    validate_hpe_terminal_attestation!(
      root, decision, identity, stage_index, activation_parent, contract_identity,
      authority_identity, manifest_identity, candidate, bundle_identity
    )
    identity.merge("verification_status" => verification_status)
  ensure
    attestation_file.close if defined?(attestation_file) && attestation_file &&
                              !attestation_file.closed?
  end

  def validate_hpe_stage_receipt!(root, decision, completed, stage_index, terminal: false)
    receipt_key = terminal ? "terminal_receipt" : "task_gate_receipt"
    exact_keys(completed, %w[
      task_id status contract authority candidate_manifest gate_evidence independent_reviews
    ] + [receipt_key], "P3 HPE completed Task projection")
    stage = hpe_stage(decision, stage_index)
    expected_status = terminal ? "TERMINAL_TASK_GATE_NON_PASS" : "ACCEPTED_TASK_GATE_PASS"
    assert(completed["task_id"] == stage.fetch("task_id") &&
           completed["status"] == expected_status,
           "P3 HPE completed Task identity or disposition drift")
    contract_identity, _contract, activation_parent = validate_hpe_contract!(
      root, decision, completed["contract"], stage_index
    )
    authority_identity, authority = validate_hpe_authority!(
      root, decision, completed["authority"], stage_index, contract_identity, activation_parent
    )
    manifest_identity, manifest, candidate = validate_hpe_candidate_manifest!(
      root, decision, completed["candidate_manifest"], stage_index, contract_identity,
      authority_identity, activation_parent, terminal: terminal
    )
    gate_identity, gate = validate_hpe_gate_evidence!(
      decision, completed["gate_evidence"], stage_index, contract_identity, authority_identity,
      manifest_identity, manifest, terminal: terminal
    )
    review_projection = exact_keys(completed["independent_reviews"],
                                   %w[cto security quality_evaluation],
                                   "P3 HPE review identities")
    reviews = {}
    {"cto" => "CTO_AGENT", "security" => "SECURITY_AGENT",
     "quality_evaluation" => "QUALITY_EVALUATION_AGENT"}.each do |key, role|
      identity_record, review = validate_hpe_review!(
        root, decision, review_projection.fetch(key), role, stage_index, contract_identity,
        authority_identity, activation_parent, manifest_identity, gate_identity,
        terminal: terminal
      )
      assert(identity_record == review_projection.fetch(key),
             "P3 HPE review identity projection drift")
      reviews[key] = review
    end
    review_cycles = reviews.values.map { |review| review.fetch("review_cycle") }
    assert(review_cycles.uniq.length == 1,
           "P3 HPE final reviews must use the same final review cycle")
    resource = stage.fetch("resources")
    expected_receipt_path = resource.fetch(
      terminal ? "task_gate_non_pass_receipt_path" : "task_gate_pass_receipt_path"
    )
    receipt_identity, receipt = read_tik_rooted_json!(
      completed.fetch(receipt_key), "P3 HPE stage Gate receipt",
      root_path: resource.fetch("evidence_root"), expected_path: expected_receipt_path
    )
    exact_keys(receipt, %w[
      schema_version record_type phase route_id stage_ordinal stage_id task_id disposition
      contract authority candidate_manifest gate_evidence independent_reviews review_cycle
      gate_results integration budget_consumption next_lifecycle delivery_percent
      strict_exit_percent external_effects recorded_at_utc
    ], "P3 HPE stage Gate receipt")
    review_gate_status = reviews.values.all? { |review| review["verdict"] == "PASS" } ?
      "PASS" : "NON_PASS"
    expected_receipt_gate_results = gate.fetch("gate_results").merge(
      "THREE_INDEPENDENT_REVIEWS_PASS" => review_gate_status
    )
    exact_keys(receipt["gate_results"], stage.fetch("gate_requirements"),
               "P3 HPE receipt Gate results")
    assert(receipt["schema_version"] == "p3-hpe-stage-gate-receipt/v1" &&
           receipt["record_type"] == "P3_HPE_STAGE_GATE_RECEIPT" && receipt["phase"] == "P3" &&
           receipt["route_id"] == HPE_ROUTE_ID && receipt["stage_ordinal"] == stage_index + 1 &&
           receipt["stage_id"] == stage.fetch("stage_id") &&
           receipt["task_id"] == stage.fetch("task_id") &&
           receipt["disposition"] == expected_status && receipt["contract"] == contract_identity &&
           receipt["authority"] == authority_identity &&
           receipt["candidate_manifest"] == manifest_identity &&
           receipt["gate_evidence"] == gate_identity &&
           receipt["independent_reviews"] == review_projection &&
           receipt["review_cycle"] == review_cycles.first &&
           receipt["gate_results"] == expected_receipt_gate_results &&
           receipt["budget_consumption"] == stage.fetch("budget") &&
           receipt["external_effects"] == HPE_EXTERNAL_EFFECTS,
           "P3 HPE stage Gate receipt cross-binding drift")
    if terminal
      assert(reviews.values.any? { |review| review["verdict"] == "NON_PASS" } ||
             gate["disposition"] == "NON_PASS_CANDIDATE",
             "P3 HPE terminal receipt lacks a mechanical or independent NON_PASS")
    else
      assert(reviews.values.all? { |review| review["verdict"] == "PASS" } &&
             gate["disposition"] == "PASS_CANDIDATE" &&
             receipt.fetch("gate_results").values.all? { |status| status == "PASS" },
             "P3 HPE PASS receipt lacks exact Gate PASS and three independent PASS reviews")
    end
    integration = exact_keys(receipt["integration"], %w[
      candidate_commit candidate_tree integrated canonical_main_commit canonical_main_tree
      integration_delta_files rejected_candidate_bundle bundle_verification_attestation
    ], "P3 HPE receipt integration")
    assert(integration["candidate_commit"] == candidate["commit"] &&
           integration["candidate_tree"] == candidate["tree"],
           "P3 HPE receipt candidate identity drift")
    if terminal
      assert(integration["integrated"] == false &&
             integration["canonical_main_commit"].is_a?(String) &&
             integration["canonical_main_commit"].match?(/\A[0-9a-f]{40}\z/) &&
             integration["canonical_main_tree"].is_a?(String) &&
             git!(root, "rev-parse", "#{integration.fetch('canonical_main_commit')}^{tree}") ==
               integration.fetch("canonical_main_tree") &&
             integration["integration_delta_files"] == [],
             "P3 HPE terminal candidate cannot be integrated and lacks its canonical anchor")
      git!(root, "merge-base", "--is-ancestor", activation_parent.fetch("commit"),
           integration.fetch("canonical_main_commit"))
      git!(root, "merge-base", "--is-ancestor", integration.fetch("canonical_main_commit"),
           "main")
      terminal_anchor_delta = git!(
        root, "diff", "--name-status", "--diff-filter=ACMRD",
        activation_parent.fetch("commit"), integration.fetch("canonical_main_commit")
      ).lines.map(&:strip).reject(&:empty?)
      assert(terminal_anchor_delta == ["M\tdocs/aios/truth/project_state.yaml"],
             "P3 HPE terminal canonical anchor exceeds the active Truth projection")
      if stage_index < 2
        bundle = exact_keys(integration["rejected_candidate_bundle"],
                            %w[path byte_length sha256], "P3 HPE rejected bundle")
        tik_assert_path_under!(bundle.fetch("path"), resource.fetch("evidence_root"),
                               "P3 HPE rejected bundle",
                               expected_path: resource.fetch("rejected_bundle_path"))
        read_tik_external_identity!(bundle, "P3 HPE rejected bundle", create_once: true)
        validate_hpe_terminal_attestation!(
          root, decision, integration["bundle_verification_attestation"], stage_index,
          activation_parent, contract_identity, authority_identity, manifest_identity,
          candidate, bundle
        )
      else
        assert(integration["rejected_candidate_bundle"].nil? &&
               integration["bundle_verification_attestation"].nil?,
               "P3 HPE Audit terminal receipt cannot reopen Product lineage")
      end
    else
      assert(integration["integrated"] == true &&
             integration["rejected_candidate_bundle"].nil? &&
             integration["bundle_verification_attestation"].nil? &&
             integration["canonical_main_commit"].is_a?(String) &&
             integration["canonical_main_commit"].match?(/\A[0-9a-f]{40}\z/) &&
             integration["canonical_main_tree"].is_a?(String) &&
             git!(root, "rev-parse", "#{integration.fetch('canonical_main_commit')}^{tree}") ==
               integration.fetch("canonical_main_tree"),
             "P3 HPE PASS receipt lacks exact canonical integration")
      git!(root, "merge-base", "--is-ancestor", candidate.fetch("commit"),
           integration.fetch("canonical_main_commit"))
      git!(root, "merge-base", "--is-ancestor", activation_parent.fetch("commit"),
           integration.fetch("canonical_main_commit"))
      git!(root, "merge-base", "--is-ancestor", integration.fetch("canonical_main_commit"), "main")
      changed = git!(
        root, "diff", "--name-status", "--diff-filter=ACMRD",
        activation_parent.fetch("commit"), integration.fetch("canonical_main_commit")
      ).lines.map(&:strip).reject(&:empty?).map do |line|
        status, path, unexpected = line.split("\t", 3)
        assert(unexpected.nil? && %w[A M].include?(status) && path,
               "P3 HPE integration contains a deletion, rename, copy or unknown Git delta")
        path
      end.sort
      expected_integration_paths = (
        manifest.fetch("repository_files").map { |entry| entry.fetch("relative_path") } +
        ["docs/aios/truth/project_state.yaml"]
      ).sort
      assert(changed == expected_integration_paths,
             "P3 HPE canonical integration contains unreviewed or missing repository bytes")
      manifest.fetch("repository_files").each do |entry|
        path = entry.fetch("relative_path")
        assert(tik_git_tree_entry!(root, integration.fetch("canonical_main_commit"), path,
                                   "P3 HPE integrated repository file") ==
                 entry.slice("git_mode", "object_type", "git_blob_sha1"),
               "P3 HPE integrated repository mode/type/blob drift: #{path}")
        bytes = tik_git_bytes!(root, integration.fetch("canonical_main_commit"), path,
                               "P3 HPE integrated repository file")
        assert(bytes.bytesize == entry.fetch("byte_length") &&
               Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256"),
               "P3 HPE integrated repository bytes drift: #{path}")
      end
      delta = array(integration["integration_delta_files"], "P3 HPE integration delta")
      assert(delta.length == 1, "P3 HPE integration permits exactly one Truth projection delta")
      entry = exact_keys(delta.first, %w[relative_path byte_length sha256],
                         "P3 HPE integration Truth identity")
      assert(entry["relative_path"] == "docs/aios/truth/project_state.yaml" &&
             entry["byte_length"].is_a?(Integer) && entry["byte_length"].positive? &&
             entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[0-9a-f]{64}\z/),
             "P3 HPE integration delta exceeds canonical Truth")
      truth_bytes = tik_git_bytes!(root, integration.fetch("canonical_main_commit"),
                                   entry.fetch("relative_path"), "P3 HPE integrated Truth")
      assert(truth_bytes.bytesize == entry.fetch("byte_length") &&
             Digest::SHA256.hexdigest(truth_bytes) == entry.fetch("sha256"),
             "P3 HPE integrated Truth identity drift")
    end
    expected_next = terminal ? "ROUTE_TERMINAL_NON_PASS" :
      %w[PRODUCT_STAGE_ELIGIBLE AUDIT_STAGE_ELIGIBLE COMPLETE_AWAITING_FOUNDER_PHASE_GATE]
        .fetch(stage_index)
    assert(receipt["next_lifecycle"] == expected_next &&
           receipt["delivery_percent"] == (terminal ? [25, 50, 75].fetch(stage_index) :
             stage.fetch("delivery_percent_on_pass")) &&
           receipt["strict_exit_percent"] == (terminal ? 0 :
             stage.fetch("strict_exit_percent_on_pass")),
           "P3 HPE receipt lifecycle/progress drift")
    tik_timestamp!(receipt["recorded_at_utc"], "P3 HPE receipt timestamp")
    {
      "receipt" => receipt_identity, "contract" => contract_identity,
      "authority_identity" => authority_identity, "authority" => authority,
      "manifest_identity" => manifest_identity, "manifest" => manifest,
      "gate_identity" => gate_identity, "gate" => gate,
      "candidate" => candidate, "integration" => integration
    }
  end

  def hpe_lifecycle_spec(route)
    lifecycle = route["lifecycle_stage"]
    return [lifecycle, HPE_LIFECYCLE_SPECS.fetch(lifecycle)] if
      HPE_LIFECYCLE_SPECS.key?(lifecycle)
    return [lifecycle, nil] unless lifecycle == "ROUTE_TERMINAL_NON_PASS"

    ordinal = route["terminal_stage_ordinal"]
    return [lifecycle, nil] unless ordinal.is_a?(Integer) && ordinal.between?(1, 3)

    statuses = Array.new(3, "LOCKED_ROUTE_TERMINAL")
    (ordinal - 1).times { |index| statuses[index] = "ACCEPTED" }
    statuses[ordinal - 1] = "TERMINAL_TASK_GATE_NON_PASS"
    [lifecycle, {
      "route_status" => "HOLD_INCOMPLETE_ROUTE_TERMINAL_NON_PASS",
      "stage_statuses" => statuses, "active_stage" => nil,
      "completed_stages" => ordinal, "delivery" => 25 + ((ordinal - 1) * 25),
      "strict_exit" => 0, "next_action" => "FOUNDER_DECIDE_P3_AFTER_HPE_ROUTE_TERMINAL_NON_PASS",
      "task_creation_allowed" => false, "founder_gate" => true, "terminal" => true,
      "terminal_stage_index" => ordinal - 1
    }]
  end

  def hpe_budget_sum(decision, completed_count)
    total = {"engineering_tasks" => 9, "engineering_hours" => 264, "calendar_days" => 66}
    hpe_stages(decision).first(completed_count).each do |stage|
      %w[engineering_tasks engineering_hours calendar_days].each do |key|
        total[key] += stage.fetch("budget").fetch(key)
      end
    end
    total
  end

  def hpe_remaining(consumed)
    {
      "engineering_tasks" => 12 - consumed.fetch("engineering_tasks"),
      "engineering_hours" => 336 - consumed.fetch("engineering_hours"),
      "calendar_days" => 84 - consumed.fetch("calendar_days")
    }
  end

  def validate_hpe_workspace_topology!(root, decision, active_index, activation_parent = nil,
                                       preactivation_resource_action: nil,
                                       preactivation_stage_index: nil,
                                       completed_results: [])
    assert(git!(root, "symbolic-ref", "--short", "HEAD") == "main",
           "P3 HPE canonical checkout must remain on main")
    assert(git!(root, "status", "--porcelain").empty?,
           "P3 HPE canonical checkout must be clean")
    branches = git!(root, "for-each-ref", "--format=%(refname:short)", "refs/heads")
      .lines.map(&:strip).reject(&:empty?).sort
    partial_branch = %w[
      WORKTREE_CREATE ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE TASK_ACTIVATION
    ].include?(preactivation_resource_action)
    partial_worktree = %w[
      ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE TASK_ACTIVATION
    ].include?(preactivation_resource_action)
    expected_branches = ["main"]
    expected_branches << hpe_stage_resource(decision, active_index).fetch("branch") if active_index
    if partial_branch
      expected_branches << hpe_stage_resource(decision, preactivation_stage_index).fetch("branch")
    end
    assert(branches == expected_branches.sort,
           "P3 HPE branch topology exceeds main plus the active Task")
    records = git!(root, "worktree", "list", "--porcelain").split(/\n\n+/).map do |block|
      block.lines.each_with_object({}) do |line, record|
        key, value = line.strip.split(" ", 2)
        assert(%w[worktree HEAD branch].include?(key) && value && !record.key?(key),
               "P3 HPE worktree topology contains detached, duplicate or unknown state")
        record[key] = value
      end
    end
    expected_worktrees = [root.to_s]
    expected_worktrees << hpe_stage_resource(decision, active_index).fetch("worktree") if active_index
    if partial_worktree
      expected_worktrees << hpe_stage_resource(decision, preactivation_stage_index).fetch("worktree")
    end
    assert(records.map { |record| record.fetch("worktree") }.sort == expected_worktrees.sort,
           "P3 HPE worktree topology exceeds canonical plus the active Task")
    canonical_record = records.find { |record| record["worktree"] == root.to_s }
    assert(canonical_record && canonical_record.keys.sort == %w[HEAD branch worktree] &&
           canonical_record["branch"] == "refs/heads/main" &&
           canonical_record["HEAD"] == git!(root, "rev-parse", "main"),
           "P3 HPE canonical worktree association drift")
    partial_index = preactivation_stage_index
    if partial_branch
      branch = hpe_stage_resource(decision, partial_index).fetch("branch")
      assert(git!(root, "rev-parse", branch) == git!(root, "rev-parse", "main"),
             "P3 HPE preactivation branch is not at exact canonical main")
    end
    if partial_worktree
      resource = hpe_stage_resource(decision, partial_index)
      task = records.find { |record| record["worktree"] == resource.fetch("worktree") }
      assert(task && task.keys.sort == %w[HEAD branch worktree] &&
             task["branch"] == "refs/heads/#{resource.fetch('branch')}" &&
             task["HEAD"] == git!(root, "rev-parse", resource.fetch("branch")),
             "P3 HPE preactivation worktree association drift")
    end
    main_commit = git!(root, "rev-parse", "main")
    if active_index
      resource = hpe_stage_resource(decision, active_index)
      task = records.find { |record| record["worktree"] == resource.fetch("worktree") }
      assert(task && task.keys.sort == %w[HEAD branch worktree] &&
             task["branch"] == "refs/heads/#{resource.fetch('branch')}" &&
             task["HEAD"] == git!(root, "rev-parse", resource.fetch("branch")) &&
             activation_parent,
             "P3 HPE active worktree association or activation-parent drift")
      main_lineage = git!(root, "rev-list", "--parents", "-n", "1", main_commit).split
      assert(main_lineage.length == 2 && main_lineage[1] == activation_parent.fetch("commit"),
             "P3 HPE active canonical main is not the sole Truth activation projection")
      delta = git!(root, "diff", "--name-status", "--diff-filter=ACMRD",
                   activation_parent.fetch("commit"), main_commit)
        .lines.map(&:strip).reject(&:empty?)
      assert(delta == ["M\tdocs/aios/truth/project_state.yaml"],
             "P3 HPE active canonical main drifted beyond the exact Truth activation delta")
      git!(root, "merge-base", "--is-ancestor", activation_parent.fetch("commit"),
           task.fetch("HEAD"))
    elsif completed_results.empty?
      git!(root, "merge-base", "--is-ancestor", HPE_CANONICAL_START.fetch("commit"), "main")
      main_lineage = git!(root, "rev-list", "--parents", "-n", "1", main_commit).split
      assert(main_lineage.length == 2 &&
             main_lineage[1] == HPE_CANONICAL_START.fetch("commit"),
             "P3 HPE Stage 0 must be one exact canonical installation commit")
      installation_paths = decision.dig("installation", "allowed_repository_paths")
      changed = git!(root, "diff", "--name-only", "--diff-filter=ACMRD",
                     HPE_CANONICAL_START.fetch("commit"), "main")
        .lines.map(&:strip).reject(&:empty?)
      assert((changed - installation_paths).empty? && changed.include?("docs/aios/truth/project_state.yaml"),
             "P3 HPE Stage 0 canonical delta exceeds the single authorized rule freeze")
    else
      canonical_anchor = completed_results.last.fetch("integration")
      anchor_commit = canonical_anchor.fetch("canonical_main_commit")
      anchor_tree = canonical_anchor.fetch("canonical_main_tree")
      assert(anchor_commit.is_a?(String) && anchor_tree.is_a?(String) &&
             git!(root, "rev-parse", "#{anchor_commit}^{tree}") == anchor_tree,
             "P3 HPE completed lifecycle canonical anchor drift")
      main_lineage = git!(root, "rev-list", "--parents", "-n", "1", main_commit).split
      assert(main_lineage.length == 2 && main_lineage[1] == anchor_commit,
             "P3 HPE completed lifecycle must have one exact Truth synchronization commit")
      sync_delta = git!(root, "diff", "--name-status", "--diff-filter=ACMRD",
                        anchor_commit, main_commit).lines.map(&:strip).reject(&:empty?)
      assert(sync_delta == ["M\tdocs/aios/truth/project_state.yaml"],
             "P3 HPE completed lifecycle sync exceeds the exact Truth projection")
    end
  end

  def validate_hpe_route!(root, truth, preactivation_resource_action: nil)
    decision = validate_hpe_decision!(root)
    route = mapping(truth["current_phase_route"], "P3 HPE current route")
    lifecycle, spec = hpe_lifecycle_spec(route)
    assert(spec, "P3 HPE lifecycle stage is not closed-schema")
    preactivation_actions = %w[
      BRANCH_CREATE WORKTREE_CREATE ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE TASK_ACTIVATION
    ]
    assert(preactivation_resource_action.nil? ||
           (preactivation_actions.include?(preactivation_resource_action) &&
            spec.fetch("task_creation_allowed") && spec["active_stage"].nil?),
           "P3 HPE partial preactivation mode is not authorized for this lifecycle")
    route_keys = %w[
      schema_version route_id status lifecycle_stage execution_status scheduling_status phase
      phase_entry_status policy founder_phase_route_decision_required
      founder_reserved_triggers_resolved next_eligible_action phase_execution_envelope_ref
      phase_entry_route_ref accepted_p3_001_foundation_route_ref historical_predecessor_route_ref
      founder_route_decision canonical_start constitution objective_id workflow_id
      workflow_claim_limit strict_exit_gate_changed strict_exit_gate_required_items
      prior_consumed_accounting rejected_lineage_policy ordered_stages p3_entry_authorized
      p4_entry_authorized long_term_goal_status external_effects additional_write_roots
    ]
    route_keys << "terminal_stage_ordinal" if lifecycle == "ROUTE_TERMINAL_NON_PASS"
    exact_keys(route, route_keys, "P3 HPE current route")
    execution_status = {
      "FOUNDATION_STAGE_ELIGIBLE" => "READY_TO_ACTIVATE_FOUNDATION",
      "FOUNDATION_TASK_ACTIVE" => "FOUNDATION_TASK_ACTIVE",
      "PRODUCT_STAGE_ELIGIBLE" => "READY_TO_ACTIVATE_PRODUCT",
      "PRODUCT_TASK_ACTIVE" => "PRODUCT_TASK_ACTIVE",
      "AUDIT_STAGE_ELIGIBLE" => "READY_TO_ACTIVATE_AUDIT",
      "AUDIT_TASK_ACTIVE" => "AUDIT_TASK_ACTIVE",
      "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
        "P3_COMPLETE_STRICT_EXIT_ACCEPTED_AWAITING_FOUNDER_PHASE_GATE",
      "ROUTE_TERMINAL_NON_PASS" => "TERMINAL_HPE_STAGE_GATE_NON_PASS"
    }.fetch(lifecycle)
    scheduling_status = if spec.fetch("founder_gate")
      lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" ?
        "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION" :
        "FOUNDER_RESERVED_ROUTE_CHANGE_DECISION_REQUIRED"
    elsif spec["active_stage"]
      "ACTIVE_#{%w[FOUNDATION PRODUCT AUDIT].fetch(spec.fetch('active_stage'))}_TASK"
    else
      "MASTER_CONTINUES_PHASE"
    end
    assert(route["schema_version"] == HPE_ROUTE_SCHEMA && route["route_id"] == HPE_ROUTE_ID &&
           route["status"] == spec.fetch("route_status") && route["phase"] == "P3" &&
           route["execution_status"] == execution_status &&
           route["scheduling_status"] == scheduling_status &&
           route["phase_entry_status"] == "AUTHORIZED" && route["policy"] == POLICY &&
           route["founder_phase_route_decision_required"] == spec.fetch("founder_gate") &&
           route["founder_reserved_triggers_resolved"] == %w[
             MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
             MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
           ] && route["next_eligible_action"] == spec.fetch("next_action") &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["accepted_p3_001_foundation_route_ref"] == "historical_p3_001_phase_route" &&
           route["historical_predecessor_route_ref"] ==
             "historical_p3_tik_process_real_route_terminal" &&
           route["founder_route_decision"] == hpe_founder_decision_projection &&
           route["canonical_start"] == HPE_CANONICAL_START &&
           route["constitution"] == TIK_CONSTITUTION &&
           route["objective_id"] == "MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY" &&
           route["workflow_id"] == "VERIFY_CUSTODY_SHA256_V1" &&
           route["workflow_claim_limit"] ==
             "MACOS_JDK17_LOCAL_ONE_FIXED_READ_ONLY_CUSTODY_SHA256_WORKFLOW_ONLY_NO_PRODUCTION_CLAIM" &&
           route["strict_exit_gate_changed"] == false &&
           route["strict_exit_gate_required_items"] ==
             %w[RESUME ISOLATION PERMISSION COMPLETE_OBSERVABLE_TRACE] &&
           route["prior_consumed_accounting"] == decision.dig("route", "consumed_preserved") &&
           route["rejected_lineage_policy"] == decision.dig("route", "rejected_lineage_policy") &&
           route["p3_entry_authorized"] == true && route["p4_entry_authorized"] == false &&
           route["long_term_goal_status"] == "ACTIVE" &&
           route["external_effects"] == HPE_EXTERNAL_EFFECTS && route["additional_write_roots"] == [],
           "P3 HPE route lifecycle, authority or claim-boundary drift")
    expected_stages = hpe_stages(decision).each_with_index.map do |stage, index|
      hpe_stage_projection(stage, spec.fetch("stage_statuses").fetch(index))
    end
    assert(route["ordered_stages"] == expected_stages,
           "P3 HPE stage ordering, budget, capability or lock drift")

    start_truth = YAML.safe_load(
      tik_git_bytes!(root, HPE_CANONICAL_START.fetch("commit"),
                     "docs/aios/truth/project_state.yaml", "P3 HPE predecessor Truth"),
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(truth["historical_p3_tik_process_real_route_terminal"] ==
             start_truth["current_phase_route"] &&
           truth["historical_p3_tik_process_real_phase_execution_envelope"] ==
             start_truth["phase_execution_envelope"] &&
           truth["historical_p3_tik_process_real_founder_escalation_control"] ==
             start_truth["founder_escalation_control"] &&
           truth["historical_p3_tik_process_real_phase_delegation"] ==
             start_truth["phase_delegation"] &&
           truth["historical_p3_tik_process_real_phase_boundary"] ==
             start_truth["phase_boundary"] &&
           truth["historical_p3_tik_process_real_terminal_active_work"] ==
             start_truth["active_work"],
           "P3 HPE predecessor terminal current-state accounting drift")

    envelope = exact_keys(truth["phase_execution_envelope"], %w[
      schema_version phase status authority_basis accounting_basis prior_terminal_envelope_ref
      consumed rebound_locked_capacity added_capacity limits route_capacity reserved remaining
      remaining_capacity_usable remaining_capacity_lock_reason milestone_order accepted_milestones
      ordered_stages delivery_progress governance_progress_credit external_effects
    ], "P3 HPE Phase envelope")
    consumed = hpe_budget_sum(decision, spec.fetch("completed_stages"))
    active_index = spec["active_stage"]
    expected_reserved = active_index.nil? ? {} : hpe_stage(decision, active_index).fetch("budget")
    accepted_count = spec["terminal"] ? spec.fetch("completed_stages") - 1 :
      spec.fetch("completed_stages")
    expected_accepted = ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] +
      hpe_stages(decision).first(accepted_count).map { |stage| stage.fetch("stage_id") }
    lock_reason = if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      "ROUTE_TERMINAL_EXACT_AUTHORIZATION_PROHIBITS_REUSE_OR_FOLLOW_ON_TASK"
    elsif lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      "P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
    elsif active_index
      "ACTIVE_TASK_CONSUMES_SINGLE_TASK_SLOT"
    else
      "NONE"
    end
    authority_basis = mapping(envelope["authority_basis"], "P3 HPE envelope authority basis")
    assert(envelope["schema_version"] ==
             "p3-host-process-enforced-minimal-slice-phase-envelope/v1" &&
           envelope["phase"] == "P3" && envelope["status"] == spec.fetch("route_status") &&
           authority_basis["phase_entry_status"] == "AUTHORIZED" &&
           authority_basis["policy_path"] == POLICY.fetch("path") &&
           authority_basis["policy_version"] == POLICY.fetch("version") &&
           authority_basis["policy_sha256"] == POLICY.fetch("sha256") &&
           authority_basis["source_route_ref"] == "current_phase_route" &&
           authority_basis["source_route_id"] == HPE_ROUTE_ID &&
           authority_basis["founder_route_decision"] ==
             HPE_DECISION.merge("decision_id" => HPE_DECISION_ID,
                                "reserved_triggers" => %w[
                                  MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
                                  MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
                                ]) &&
           envelope["accounting_basis"] == "NON_RESETTABLE_DECLARED_TASK_BUDGET_RESERVATION" &&
           envelope["prior_terminal_envelope_ref"] ==
             "historical_p3_tik_process_real_phase_execution_envelope" &&
           envelope["consumed"] == consumed && envelope["rebound_locked_capacity"] == {
             "engineering_tasks" => 2, "engineering_hours" => 72, "calendar_days" => 18
           } && envelope["added_capacity"] == {
             "engineering_tasks" => 1, "engineering_hours" => 0, "calendar_days" => 0
           } && envelope["limits"] == decision.dig("route", "cumulative_ceiling") &&
           envelope["route_capacity"] == decision.dig("route", "route_capacity") &&
           envelope["reserved"] == expected_reserved &&
           envelope["remaining"] == hpe_remaining(consumed) &&
           envelope["remaining_capacity_usable"] == spec.fetch("task_creation_allowed") &&
           envelope["remaining_capacity_lock_reason"] == lock_reason &&
           envelope["milestone_order"] == [
             "DURABLE_STATE_AND_CHECKPOINT_RESUME",
             *hpe_stages(decision).map { |stage| stage.fetch("stage_id") }
           ] && envelope["accepted_milestones"] == expected_accepted &&
           envelope["ordered_stages"] == expected_stages &&
           envelope["delivery_progress"] == {
             "accepted" => spec.fetch("delivery") / 25, "total" => 4,
             "percent" => spec.fetch("delivery"),
             "strict_exit_gate_percent" => spec.fetch("strict_exit")
           } && envelope["governance_progress_credit"] == 0 &&
           envelope["external_effects"] == HPE_EXTERNAL_EFFECTS,
           "P3 HPE Phase envelope, accounting or progress drift")

    active = exact_keys(truth["active_work"], %w[
      current_task current_task_status current_task_contract current_task_contract_sha256
      current_execution_authorization current_execution_authorization_sha256 authority_record
      execution_nonce execution_nonce_status authorization_id activation_parent_commit
      activation_parent_tree stage0_installation_parent task_resource_state task_branch
      task_worktree execution_evidence_root dependency_custody_root allowlisted_paths
      current_task_budget next_stage_budget roles external_effects offsite_target
      founder_reserved_authorization founder_reserved_authorization_sha256
      founder_decision_required founder_decision_required_scope escalation_reason
      user_action_required phase_route_decision_required phase_route_user_action_required
      completed_tasks last_completed_task_identity_accounting next_eligible_action
    ], "P3 HPE active_work")
    completed = array(active["completed_tasks"], "P3 HPE completed Task chain")
    assert(completed.length == spec.fetch("completed_stages"),
           "P3 HPE completed Task chain length drift")
    completed_results = completed.each_with_index.map do |entry, index|
      terminal_task = spec["terminal"] && index == completed.length - 1
      validate_hpe_stage_receipt!(root, decision, entry, index, terminal: terminal_task)
    end
    if completed_results.length >= 2 &&
       (!spec["terminal"] || spec.fetch("terminal_stage_index", 99) > 1)
      foundation = completed_results.fetch(0)
      product = completed_results.fetch(1)
      assert(product.dig("manifest", "frozen_predecessor_inputs") == {
        "foundation_candidate_manifest" => foundation.fetch("manifest_identity"),
        "foundation_gate_evidence" => foundation.fetch("gate_identity"),
        "foundation_task_gate_receipt" => foundation.fetch("receipt")
      }, "P3 HPE Product is not bound to exact accepted Foundation")
    end
    if completed_results.length >= 3 && !spec["terminal"]
      foundation, product, audit = completed_results
      assert(audit.fetch("candidate").slice("commit", "tree", "source_branch") ==
               product.fetch("candidate").slice("commit", "tree", "source_branch") &&
             audit.dig("manifest", "frozen_predecessor_inputs") == {
               "foundation_candidate_manifest" => foundation.fetch("manifest_identity"),
               "foundation_gate_evidence" => foundation.fetch("gate_identity"),
               "foundation_task_gate_receipt" => foundation.fetch("receipt"),
               "product_candidate_manifest" => product.fetch("manifest_identity"),
               "product_gate_evidence" => product.fetch("gate_identity"),
               "product_task_gate_receipt" => product.fetch("receipt")
             }, "P3 HPE Audit did not freeze exact accepted Foundation/Product")
    end
    active_parent = nil
    current_authority = nil
    if active_index
      stage = hpe_stage(decision, active_index)
      resource = stage.fetch("resources")
      assert(active["current_task"] == stage.fetch("task_id") &&
             active["current_task_status"] == "ACTIVE" &&
             active["execution_nonce_status"] == "ACTIVE" &&
             active["task_branch"] == resource.fetch("branch") &&
             active["task_worktree"] == resource.fetch("worktree") &&
             active["execution_evidence_root"] == resource.fetch("evidence_root") &&
             active["dependency_custody_root"] == "#{resource.fetch('evidence_root')}/custody" &&
             active["allowlisted_paths"] == stage.fetch("allowlisted_repository_paths") &&
             active["current_task_budget"] == stage.fetch("budget") &&
             active["next_stage_budget"] == {} &&
             active["task_resource_state"] == "ACTIVE_UNIQUE_HPE_STAGE" &&
             active["offsite_target"].nil?, "P3 HPE active Task projection drift")
      contract_identity, _contract, active_parent = validate_hpe_contract!(
        root, decision, active["current_task_contract"], active_index
      )
      authority_identity, current_authority = validate_hpe_authority!(
        root, decision, active["authority_record"], active_index,
        contract_identity, active_parent
      )
      assert(active["current_task_contract_sha256"] == contract_identity["sha256"] &&
             active["current_execution_authorization"] == authority_identity["path"] &&
             active["current_execution_authorization_sha256"] == authority_identity["sha256"] &&
             active["authorization_id"] == current_authority["authorization_id"] &&
             active["execution_nonce"] == current_authority["execution_nonce"] &&
             active["activation_parent_commit"] == active_parent["commit"] &&
             active["activation_parent_tree"] == active_parent["tree"],
             "P3 HPE active Contract/authority pointer drift")
      custody = Pathname.new(active.fetch("dependency_custody_root"))
      assert(custody.directory? && !custody.symlink? &&
             custody.realpath.to_s == custody.cleanpath.to_s,
             "P3 HPE active custody root is missing or symlinked")
    else
      assert(active["current_task"] == "NONE" && active["current_task_contract"].nil? &&
             active["current_task_contract_sha256"].nil? &&
             active["current_execution_authorization"].nil? &&
             active["current_execution_authorization_sha256"].nil? &&
             active["authority_record"].nil? && active["execution_nonce"].nil? &&
             active["authorization_id"].nil? && active["activation_parent_commit"].nil? &&
             active["activation_parent_tree"].nil? && active["task_branch"].nil? &&
             active["task_worktree"].nil? && active["execution_evidence_root"].nil? &&
             active["dependency_custody_root"].nil? && active["allowlisted_paths"] == [] &&
             active["current_task_budget"] == {
               "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0
             }, "P3 HPE no-Task lifecycle retained active authority")
      next_index = hpe_boundary_stage_index(spec)
      expected_status = {
        "FOUNDATION_STAGE_ELIGIBLE" => "NONE_FOUNDATION_STAGE_ELIGIBLE",
        "PRODUCT_STAGE_ELIGIBLE" => "NONE_PRODUCT_STAGE_ELIGIBLE",
        "AUDIT_STAGE_ELIGIBLE" => "NONE_AUDIT_STAGE_ELIGIBLE",
        "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
          "NONE_P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
        "ROUTE_TERMINAL_NON_PASS" => "NONE_ROUTE_TERMINAL_NON_PASS"
      }.fetch(lifecycle)
      expected_resource = {
        "FOUNDATION_STAGE_ELIGIBLE" => "NOT_CREATED_HPE_FOUNDATION_STAGE_ELIGIBLE",
        "PRODUCT_STAGE_ELIGIBLE" => "NOT_CREATED_HPE_PRODUCT_STAGE_ELIGIBLE",
        "AUDIT_STAGE_ELIGIBLE" => "NOT_CREATED_HPE_AUDIT_STAGE_ELIGIBLE",
        "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" => "COMPLETE_NO_TASK_RESOURCES",
        "ROUTE_TERMINAL_NON_PASS" => "TERMINAL_ROUTE_NO_TASK_RESOURCES"
      }.fetch(lifecycle)
      assert(active["current_task_status"] == expected_status &&
             active["task_resource_state"] == expected_resource &&
             active["execution_nonce_status"] ==
               (lifecycle == "FOUNDATION_STAGE_ELIGIBLE" ? "NOT_ISSUED" : "NO_CURRENT_TASK") &&
             active["next_stage_budget"] ==
               (next_index ? hpe_stage(decision, next_index).fetch("budget") : {}),
             "P3 HPE no-Task lifecycle/resource projection drift")
    end
    authorities = completed_results.map { |result| result.fetch("authority") }
    authorities << current_authority if current_authority
    assert(authorities.map { |authority| authority.fetch("authorization_id") }.uniq.length ==
             authorities.length &&
           authorities.map { |authority| authority.fetch("execution_nonce") }.uniq.length ==
             authorities.length, "P3 HPE authorization ID or nonce was reused")
    boundary = hpe_expected_phase_boundary(decision, lifecycle, spec)
    assert(truth["phase_boundary"] == boundary,
           "P3 HPE phase-boundary authority projection drift")
    assert(active["stage0_installation_parent"] ==
             HPE_CANONICAL_START.slice("commit", "tree") &&
           active["roles"] == {
             "owner" => "MASTER_CEO_AGENT", "worker" => "IMPLEMENTATION_AGENT",
             "quality_owner" => "QUALITY_EVALUATION_AGENT",
             "independent_reviewers" => HPE_REVIEW_ROLES
           } && active["external_effects"] == HPE_EXTERNAL_EFFECTS &&
           active["founder_reserved_authorization"] == HPE_DECISION.fetch("path") &&
           active["founder_reserved_authorization_sha256"] == HPE_DECISION.fetch("sha256") &&
           active["next_eligible_action"] == spec.fetch("next_action") &&
           active["founder_decision_required"] == boundary["founder_decision_required"] &&
           active["founder_decision_required_scope"] ==
             boundary["founder_decision_required_scope"] &&
           active["escalation_reason"] == boundary["escalation_reason"] &&
           active["user_action_required"] == boundary["user_action_required"] &&
           active["phase_route_decision_required"] == boundary["phase_route_decision_required"] &&
           active["phase_route_user_action_required"] ==
             boundary["phase_route_user_action_required"],
           "P3 HPE active-work authority/effect/user-action drift")
    assert(active["last_completed_task_identity_accounting"] == {
      "task_id" => "AIOS-P3-TIK-F1_PROCESS_REAL_BLACK_BOX_CONFORMANCE_FOUNDATION",
      "status" => "TERMINAL_TASK_GATE_NON_PASS",
      "consumed" => {
        "engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6,
        "candidate_generations" => 2, "same_task_repairs" => 1, "review_cycles" => 2
      },
      "terminal_receipt" => HPE_CANONICAL_START.fetch("terminal_receipt"),
      "rejected_bundle_attestation" => HPE_CANONICAL_START.fetch("rejected_bundle_attestation")
    }, "P3 HPE predecessor terminal accounting drift")

    control = exact_keys(truth["founder_escalation_control"], %w[
      schema_version disposition source_event reserved_trigger resolved_strategy_decision
      resolved_phase_entry_decision phase_gate_status founder_decision_required next_action_owner
      next_eligible_action
    ], "P3 HPE Founder escalation control")
    trigger = exact_keys(control["reserved_trigger"], %w[category evidence],
                         "P3 HPE Founder reserved trigger")
    if spec.fetch("founder_gate")
      expected_category = lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" ?
        "PHASE_ENTRY_OR_EXIT" : "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
      assert(control["disposition"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
             trigger["category"] == expected_category && trigger["evidence"].is_a?(Hash) &&
             control["founder_decision_required"] == true &&
             control["next_action_owner"] == "HUMAN_FOUNDER" &&
             control["next_eligible_action"] == spec.fetch("next_action"),
             "P3 HPE Founder Gate projection drift")
    else
      assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
             trigger == {"category" => "NONE", "evidence" => nil} &&
             control["founder_decision_required"] == false &&
             control["next_action_owner"] == "MASTER_CEO_AGENT" &&
             control["next_eligible_action"] == spec.fetch("next_action"),
             "P3 HPE delegated continuation projection drift")
    end
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control.dig("resolved_strategy_decision", "decision_id") == HPE_DECISION_ID &&
           control.dig("resolved_strategy_decision", "sha256") == HPE_DECISION.fetch("sha256"),
           "P3 HPE resolved strategy decision drift")

    delegation = mapping(truth["phase_delegation"], "P3 HPE phase delegation")
    assert(delegation["status"] == "P3_HPE_#{lifecycle}" &&
           delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION" &&
           delegation["decision_source"] == HPE_DECISION_ID &&
           delegation["phase_gate_owner"] == "HUMAN_FOUNDER" &&
           delegation["task_selection_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_authorization_owner"] == "MASTER_CEO_AGENT" &&
           delegation["task_gate_owner"] == "MASTER_CEO_AGENT" &&
           delegation["p3_entry_authorized"] == true,
           "P3 HPE Phase delegation drift")
    execution = mapping(truth["phase_execution_claim"], "P3 HPE execution claim")
    assert(execution["current_route_claim"] == HPE_ROUTE_ID &&
           execution["p3_delivery_progress_percent"] == spec.fetch("delivery") &&
           execution["p3_exit_gate_progress_percent"] == spec.fetch("strict_exit") &&
           execution["task_creation_allowed"] == spec.fetch("task_creation_allowed") &&
           execution["remaining_capacity_usable"] == spec.fetch("task_creation_allowed") &&
           execution["held_read_allowed"] == false &&
           execution["candidate_integration_allowed"] == false &&
           execution["next_eligible_action"] == spec.fetch("next_action"),
           "P3 HPE execution claim drift")
    claim = mapping(truth["claim_boundary"], "P3 HPE claim boundary")
    assert(claim["current_phase_route"] == HPE_ROUTE_ID &&
           claim["current_task"] == active["current_task"] &&
           claim["next_eligible_action"] == spec.fetch("next_action") &&
           claim["p3_delivery_progress_percent"] == spec.fetch("delivery") &&
           claim["p3_exit_gate_progress_percent"] == spec.fetch("strict_exit") &&
           claim["p3_hpe_route_decision_sha256"] == HPE_DECISION.fetch("sha256") &&
           claim["p3_hpe_route_stage"] == lifecycle &&
           claim["p3_hpe_route_delivery_credit"] == spec.fetch("delivery") - 25 &&
           claim["p3_hpe_route_strict_exit_credit"] == spec.fetch("strict_exit"),
           "P3 HPE claim-boundary drift")
    goal = mapping(truth["goal"], "P3 HPE Long-term Goal")
    assert(goal["control_plane_status_observed"] == "ACTIVE" &&
           goal["current_task_authority"] ==
             (active_index ? hpe_stage(decision, active_index).fetch("task_id") : "NONE") &&
           goal.fetch("note").start_with?("Founder decision #{HPE_DECISION_ID}") &&
           truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "p4_entry_status") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY",
           "P3 HPE Goal, Phase or P4 boundary drift")
    gate = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"),
                   "P3 strict Exit Gate")
    if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      assert(gate.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") ==
               "ACCEPTED" && gate.dig("founder_phase_gate", "status") ==
               "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "P3 HPE complete lifecycle lacks strict Exit acceptance")
    else
      assert(gate["status"] == "INCOMPLETE" &&
             gate.dig("required_items", "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS", "status") ==
               "MISSING" && gate.dig("founder_phase_gate", "status") ==
               "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
             "P3 HPE incomplete lifecycle falsely accepted strict Exit")
    end
    if lifecycle == "FOUNDATION_STAGE_ELIGIBLE"
      assert(truth["verification_scope"] ==
               "P3_HPE_ROUTE_INSTALLED_FOUNDATION_ELIGIBLE_ZERO_ENGINEERING_PROGRESS_DELIVERY_25_STRICT_EXIT_ZERO_P4_HOLD_LONG_TERM_GOAL_ACTIVE",
             "P3 HPE installation verification scope drift")
    end
    validate_hpe_workspace_topology!(
      root, decision, active_index, active_parent,
      preactivation_resource_action: preactivation_resource_action,
      preactivation_stage_index: preactivation_resource_action ? hpe_boundary_stage_index(spec) : nil,
      completed_results: completed_results
    )
    HPE_LIFECYCLE_STATES.fetch(lifecycle)
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3FinalTransactionalRouteValidationError, "P3 HPE route invalid: #{e.message}"
  end

  def validate_txc_identity!(identity, expected, label, create_once: true)
    record = exact_keys(identity, %w[path byte_length sha256], label)
    assert(record == expected, "#{label} identity drift")
    read_identity!(record, label, create_once: create_once)
  end

  def parse_txc_json!(bytes, label)
    value = JSON.parse(bytes)
    assert(value.is_a?(Hash), "#{label} must be a JSON mapping")
    value
  rescue JSON::ParserError => e
    raise P3FinalTransactionalRouteValidationError, "#{label} JSON invalid: #{e.message}"
  end

  def validate_txc_decision!
    decision = parse_txc_json!(
      validate_txc_identity!(TXC_DECISION, TXC_DECISION, "P3 TXC Founder decision"),
      "P3 TXC Founder decision"
    )
    exact_keys(decision, %w[
      schema_version record_type decision_id operation_type approved_at_utc authority
      source_reply canonical_start reserved_triggers strategic_change control_plane_recovery
      route external_effects anti_loop lifecycle
    ], "P3 TXC Founder decision")
    assert(decision["schema_version"] == TXC_DECISION_SCHEMA &&
           decision["record_type"] ==
             "FOUNDER_P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY" &&
           decision["decision_id"] == TXC_DECISION_ID &&
           decision["operation_type"] == TXC_OPERATION_TYPE &&
           decision["authority"] == "HUMAN_FOUNDER",
           "P3 TXC Founder decision closed identity drift")

    source = exact_keys(decision["source_reply"], %w[
      source first_line_token authorization_token_count attachment installed_body canonicalization
      attachment_and_installed_body_byte_equal
    ], "P3 TXC source reply")
    assert(source["source"] == "CURRENT_DIRECT_USER_MESSAGE_ATTACHMENT" &&
           source["first_line_token"] == TXC_DECISION_ID &&
           source["authorization_token_count"] == 1 &&
           source["canonicalization"] == "EXACT_UTF8_LF_BYTES_NO_TRANSFORMATION" &&
           source["attachment_and_installed_body_byte_equal"] == true,
           "P3 TXC source reply mode drift")
    installed = exact_keys(source["installed_body"], %w[path byte_length sha256],
                           "P3 TXC installed body")
    assert(installed == TXC_AUTHORIZATION_BODY, "P3 TXC installed body identity drift")
    body = read_identity!(installed, "P3 TXC installed body", create_once: true)
    attachment = exact_keys(source["attachment"], %w[path byte_length sha256],
                            "P3 TXC source attachment")
    attachment_bytes = read_identity!(attachment, "P3 TXC source attachment")
    assert(attachment.slice("byte_length", "sha256") ==
             installed.slice("byte_length", "sha256") && attachment_bytes == body,
           "P3 TXC source and installed body bytes differ")
    body_text = body.dup.force_encoding("UTF-8")
    assert(body_text.valid_encoding? && body_text.lines.first&.chomp == TXC_DECISION_ID,
           "P3 TXC Founder body token or encoding drift")

    start = exact_keys(decision["canonical_start"], %w[
      repository branch commit tree truth constitution current_phase current_task
      p3_delivery_percent p3_strict_exit_percent p4_status
      project_actual_completion long_term_goal_status exact_recovery_chain terminal_receipt
    ], "P3 TXC canonical start")
    assert(start.slice("repository", "branch", "commit", "tree") == {
      "repository" => TXCR_RECOVERY_BASELINE.fetch("repository"),
      "branch" => TXCR_RECOVERY_BASELINE.fetch("branch"),
      "commit" => TXCR_RECOVERY_BASELINE.fetch("commit"),
      "tree" => TXCR_RECOVERY_BASELINE.fetch("tree")
    } && start["current_phase"] == "P3" && start["current_task"] == "NONE" &&
      start["p3_delivery_percent"] == 25 && start["p3_strict_exit_percent"] == 0 &&
      start["p4_status"] == "HOLD" && start["project_actual_completion"] == false &&
      start["long_term_goal_status"] == "ACTIVE",
      "P3 TXC canonical baseline drift")
    assert(start["truth"] == {
      "path" => "docs/aios/truth/project_state.yaml",
      "byte_length" => 1_928_850,
      "sha256" => "0ffe94417d134fca97197232f27f856e6f0949b7bf8d09626b67dc185cb59e58"
    } && start["constitution"] == {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md", "version" => "2.8",
      "byte_length" => 11_788,
      "sha256" => "6ca11702c8b364f6e241b16912185868ca160eeaf1d158786f20d5682bb37cd1"
    }, "P3 TXC baseline artifact identity drift")
    assert(start["exact_recovery_chain"] == {
      "current_revert_commit" => TXCR_RECOVERY_BASELINE.fetch("commit"),
      "current_revert_tree" => TXCR_RECOVERY_BASELINE.fetch("tree"),
      "current_revert_parent_install_commit" =>
        TXCR_RECOVERY_BASELINE.fetch("parent_install_commit"),
      "install_commit" => TXCR_RECOVERY_BASELINE.fetch("parent_install_commit"),
      "install_tree" => TXCR_RECOVERY_BASELINE.fetch("install_tree"),
      "install_parent_baseline_commit" =>
        TXCR_RECOVERY_BASELINE.fetch("install_parent_commit"),
      "baseline_tree" => TXCR_RECOVERY_BASELINE.fetch("install_parent_tree"),
      "predicate_scope" => "THIS_EXACT_INSTALL_REVERT_CHAIN_ONLY",
      "arbitrary_revert_or_descendant_allowed" => false
    }, "P3 TXC exact recovery chain drift")
    read_identity!(start.fetch("terminal_receipt"), "P3 TXC prior Stage0 terminal receipt",
                   create_once: true)

    assert(decision["reserved_triggers"] == %w[
      MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
      MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
      NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT
    ], "P3 TXC reserved trigger set drift")
    strategic = mapping(decision["strategic_change"], "P3 TXC strategic change")
    assert(strategic["constitution_target_version"] == "3.0" &&
           strategic["mission_changed"] == false && strategic["primary_icp_changed"] == false &&
           strategic["year_one_outcome_changed"] == false &&
           strategic["p0_through_p2_accepted_facts_changed"] == false &&
           strategic["p3_001_accepted_semantics_changed"] == false &&
           strategic["p4_through_p12_order_changed"] == false &&
           strategic["p3_objective_id"] == "HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_COORDINATOR" &&
           strategic["p3_strict_exit_gate"] == TXC_STRICT_GATE_ID &&
           strategic["p3_strict_exit_required_items"] == TXC_STRICT_ITEMS,
           "P3 TXC structured strategic change drift")

    route = mapping(decision["route"], "P3 TXC decision Route")
    assert(route["schema_version"] == TXC_ROUTE_SCHEMA && route["route_id"] == TXC_ROUTE_ID &&
           route["objective_id"] == "HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_COORDINATOR" &&
           route["workflow_id"] == "SHA256_READ_ONLY_CUSTODY_V1" &&
           route["cumulative_ceiling"] == {
             "engineering_tasks" => 12, "engineering_hours" => 336,
             "calendar_days" => 84, "active_tasks" => 1, "task_branches" => 1,
             "task_worktrees" => 1, "active_candidates" => 1
           } && route["consumed_preserved"] == {
             "engineering_tasks" => 10, "engineering_hours" => 272, "calendar_days" => 68
           } && route["remaining"] == {
             "engineering_tasks" => 2, "engineering_hours" => 64, "calendar_days" => 16
           }, "P3 TXC decision Route accounting drift")
    stages = array(route["stages"], "P3 TXC decision stages")
    assert(stages.length == 2 && stages.map { |stage| stage["ordinal"] } == [1, 2] &&
           stages.map { |stage| stage["task_id"] } == %w[
             AIOS-P3-TXCR-P1_TRANSACTIONAL_INVOCATION_COORDINATOR_PRODUCT
             AIOS-P3-TXCR-A1_ONE_SHOT_STRICT_EXIT_AUDIT
           ], "P3 TXC stage order drift")
    assert(route.dig("progression", "stage0_pass") == {
      "delivery_percent" => 25, "strict_exit_percent" => 0,
      "effect" => "PRODUCT_STAGE_ELIGIBLE"
    } && route.dig("progression", "stage1_pass") == {
      "delivery_percent" => 75, "strict_exit_percent" => 0,
      "effect" => "AUDIT_STAGE_ELIGIBLE"
    } && route.dig("progression", "stage2_pass") == {
      "delivery_percent" => 100, "strict_exit_percent" => 100,
      "effect" => "ELIGIBLE_AWAITING_FOUNDER_P3_PHASE_GATE_DECISION"
    }, "P3 TXC progression drift")

    staging = mapping(decision["control_plane_recovery"], "P3 TXC control recovery")
    assert(staging["decision_root"] ==
             "/Users/lijunpeng/Developer/.sourcelens-audit/p3-txc-control-recovery-20260822/decision" &&
           staging["stage0_evidence_root"] == TXC_STAGE0_EVIDENCE_ROOT &&
           staging["staging_root_command"] ==
             "mktemp -d /private/tmp/sourcelens-p3-txcr-stage.XXXXXX" &&
           staging["clone_mode"] == "LOCAL_NO_NETWORK_NO_HARDLINK_NO_REMOTE" &&
           staging["baseline_commit"] == TXCR_RECOVERY_BASELINE.fetch("commit") &&
           staging["baseline_tree"] == TXCR_RECOVERY_BASELINE.fetch("tree") &&
           staging["candidate_generations_max"] == 2 &&
           staging["same_staging_repairs_max"] == 1 &&
           staging["generation_3_allowed"] == false &&
           staging["ephemeral_candidate_may_be_canonical_ancestor"] == false &&
           staging["rejected_product_engineering_lineage_read_or_reuse_allowed"] == false &&
           staging.dig("closed_dual_modes", "manifest_environment_variable") ==
             "SOURCELENS_ATOMIC_STAGING_MANIFEST" &&
           staging.dig("closed_dual_modes", "with_exact_manifest") ==
             "ATOMIC_STAGING_FIXTURE_MODE" &&
           staging.dig("closed_dual_modes", "without_manifest_on_clean_installed_canonical") ==
             "CANONICAL_INSTALLED_REPLAY_MODE" &&
           staging["natural_language_or_full_founder_body_controls_lifecycle"] == false &&
           staging["canonical_post_install_repair_allowed"] == false &&
           staging["canonical_post_install_rerun_to_pass_allowed"] == false &&
           staging["canonical_exact_revert_on_non_pass_count_max"] == 1,
           "P3 TXC atomic staging boundary drift")
    assert(staging["repository_allowlist"] == %w[
      docs/aios/STRATEGIC_CONSTITUTION.md
      docs/aios/truth/project_state.yaml
      scripts/validate-founder-action-handoff.rb
      scripts/validate-founder-delegation-continuity.rb
      scripts/validate-current-task-authority.rb
      scripts/validate-p3-final-transactional-route.rb
      scripts/test-p3-final-transactional-route.rb
    ], "P3 TXC atomic repository allowlist drift")

    product = mapping(stages[0]["product_scope"], "P3 TXC Product scope")
    audit = mapping(stages[1]["audit_scope"], "P3 TXC Audit scope")
    scope = {"product" => product, "audit" => audit}
    assert(product["task_id"] == stages[0]["task_id"] &&
           product["kind"] == "PRODUCT_IMPLEMENTATION" &&
           product["compile_time_action_algebra"] == ["SHA256_READ_ONLY_CUSTODY"] &&
           product.dig("stream_capture", "stdout_bytes_max") == 1_048_576 &&
           product.dig("stream_capture", "stderr_bytes_max") == 1_048_576 &&
           product.dig("container_profile", "pull_policy") == "NEVER" &&
           product.dig("container_profile", "network") == "NONE" &&
           product.dig("container_profile", "root_filesystem_read_only") == true &&
           product.dig("container_profile", "docker_socket_mount_allowed") == false &&
           product["fresh_review_roles"] == %w[
             CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT
           ], "P3 TXC Product structured scope drift")
    assert(audit["task_id"] == stages[1]["task_id"] && audit["kind"] == "EVALUATION_ONLY" &&
           audit["formal_dispatches"] == 1 && audit["product_changes"] == 0 &&
           audit["same_task_repairs"] == 0 && audit["rerun_to_pass_allowed"] == false &&
           audit["required_gate_items"] == TXC_STRICT_ITEMS &&
           audit["fresh_review_roles"] == %w[
             CTO_AGENT SECURITY_AGENT QUALITY_EVALUATION_AGENT
           ], "P3 TXC Audit structured scope drift")
    assert(decision.dig("external_effects", "provider") == false &&
           decision.dig("external_effects", "secret") == false &&
           decision.dig("external_effects", "credential") == false &&
           decision.dig("external_effects", "remote") == false &&
           decision.dig("external_effects", "production") == false &&
           decision.dig("external_effects", "public") == false &&
           decision.dig("external_effects", "p4_entry") == false &&
           decision.dig("external_effects", "existing_database_mutation") == false &&
           decision.dig("external_effects", "write_outside_exact_authorized_roots") == false &&
           decision.dig("external_effects", "irreversible_asset_deletion") == false,
           "P3 TXC prohibited capability became enabled")
    [decision, scope]
  rescue ArgumentError, KeyError, TypeError => e
    raise P3FinalTransactionalRouteValidationError, "P3 TXC decision invalid: #{e.message}"
  end

  def txc_expected_stages(decision, scope, statuses)
    decision.fetch("route").fetch("stages").each_with_index.map do |stage, index|
      {
        "ordinal" => stage.fetch("ordinal"),
        "stage_id" => stage.fetch("stage_id"),
        "task_id" => stage.fetch("task_id"),
        "kind" => index.zero? ? scope.dig("product", "kind") : scope.dig("audit", "kind"),
        "status" => statuses.fetch(index),
        "budget" => stage.fetch("budget"),
        "resources" => stage.fetch("resources")
      }
    end
  end

  def txc_manifest_identity_bytes!(identity, label)
    path = Pathname.new(identity.fetch("path"))
    assert(path.absolute? && path.cleanpath.to_s == path.to_s &&
           path.to_s.start_with?(TXC_STAGE0_EVIDENCE_ROOT + File::SEPARATOR),
           "#{label} path escaped Stage0 Evidence root")
    read_identity!(identity, label, create_once: true)
  end

  def txc_git_bytes!(root, *args)
    stdout, stderr, status = Open3.capture3("git", *args, chdir: root.to_s)
    assert(status.success?, "git #{args.join(' ')} failed: #{stderr.strip}")
    stdout.b
  end

  def validate_txc_recovery_baseline!(root:)
    root = Pathname.new(root).realpath
    expected = TXCR_RECOVERY_BASELINE
    assert(root.to_s == expected.fetch("repository"),
           "P3 TXCR recovery baseline must be the exact canonical repository")
    assert(git!(root, "symbolic-ref", "--quiet", "--short", "HEAD") ==
             expected.fetch("branch") &&
           git!(root, "rev-parse", "HEAD") == expected.fetch("commit") &&
           git!(root, "rev-parse", "HEAD^{tree}") == expected.fetch("tree") &&
           git!(root, "rev-parse", "HEAD^") == expected.fetch("parent_install_commit") &&
           git!(root, "rev-parse", "HEAD^^{tree}") == expected.fetch("install_tree") &&
           git!(root, "rev-parse", "HEAD^^") == expected.fetch("install_parent_commit") &&
           git!(root, "rev-parse", "HEAD^^^{tree}") == expected.fetch("install_parent_tree") &&
           git!(root, "status", "--porcelain=v1", "--untracked-files=all").empty?,
           "P3 TXCR exact install/revert recovery chain drift")
    branches = git!(root, "for-each-ref", "--format=%(refname:short)", "refs/heads")
      .lines.map(&:strip).reject(&:empty?)
    worktrees = git!(root, "worktree", "list", "--porcelain").lines
      .grep(/^worktree /).map { |line| Pathname.new(line.delete_prefix("worktree ").strip).realpath.to_s }
    assert(branches == ["main"] && worktrees == [root.to_s],
           "P3 TXCR recovery baseline topology drift")
    %w[truth constitution].each do |key|
      identity = expected.fetch(key)
      bytes = root.join(identity.fetch("path")).binread
      assert(bytes.bytesize == identity.fetch("byte_length") &&
             Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"),
             "P3 TXCR recovery baseline #{key} identity drift")
    end
    baseline_truth = YAML.safe_load(
      root.join(expected.dig("truth", "path")).binread,
      permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(baseline_truth.dig("current_phase_route", "schema_version") == HPE_ROUTE_SCHEMA &&
           baseline_truth.dig("current_phase_route", "lifecycle_stage") ==
             "ROUTE_TERMINAL_NON_PASS" &&
           baseline_truth.dig("active_work", "current_task") == "NONE",
           "P3 TXCR recovery baseline Truth is not the exact terminal HPE state")
    "P3_TXCR_EXACT_RECOVERY_BASELINE_RECOGNIZED"
  end

  def txc_validate_atomic_manifest_values!(manifest, root:, decision:, canonical_mode: :staging)
    exact_keys(manifest, %w[
      schema_version mode generation created_at_utc recorded_staging_root
      staging_root_record staging_repository canonical_repository baseline candidate frozen_patch
      closed_inventory allowed_validators external_effects
    ], "P3 TXC atomic staging manifest")
    assert(manifest["schema_version"] == "p3-txcr-atomic-staging-manifest/v1" &&
           manifest["mode"] == "ATOMIC_STAGING_FIXTURE_MODE" &&
           [1, 2].include?(manifest["generation"]) &&
           %i[staging installed].include?(canonical_mode),
           "P3 TXC staging manifest schema/generation drift")
    staging = decision.fetch("control_plane_recovery")
    canonical_start = decision.fetch("canonical_start")
    record_identity = exact_keys(manifest["staging_root_record"], %w[path byte_length sha256],
                                 "P3 TXCR staging-root record")
    assert(record_identity == TXCR_STAGING_ROOT_RECORD,
           "P3 TXCR staging-root record identity drift")
    record = parse_txc_json!(
      read_identity!(record_identity, "P3 TXCR staging-root record", create_once: true),
      "P3 TXCR staging-root record"
    )
    exact_keys(record, %w[
      schema_version record_type created_at_utc creation_command staging_root realpath file_type
      mode_octal nlink_at_creation uid gid repository_relative_path clone_mode
      canonical_authority task_resource candidate product_progress_credit
    ], "P3 TXCR staging-root record")
    assert(record["schema_version"] == "p3-txcr-stage0-staging-root-record/v1" &&
           record["record_type"] == "P3_TXCR_STAGE0_STAGING_ROOT_RECORD" &&
           record["creation_command"] == staging.fetch("staging_root_command") &&
           record["staging_root"] == record["realpath"] &&
           record["repository_relative_path"] == staging.fetch("staging_repository_relative_path") &&
           record["clone_mode"] == staging.fetch("clone_mode") &&
           record["canonical_authority"] == false && record["task_resource"] == false &&
           record["candidate"] == false && record["product_progress_credit"] == 0,
           "P3 TXCR staging-root record semantics drift")
    expected_staging_repository = File.join(record.fetch("realpath"),
                                            record.fetch("repository_relative_path"))
    assert(manifest["recorded_staging_root"] == record.fetch("realpath") &&
           manifest["staging_repository"] == expected_staging_repository &&
           manifest["canonical_repository"] == canonical_start.fetch("repository"),
           "P3 TXC staging/canonical root binding drift")
    assert(root.realpath.to_s == Pathname.new(manifest["staging_repository"]).realpath.to_s &&
           root.realpath.to_s.start_with?(Pathname.new(manifest["recorded_staging_root"]).realpath.to_s +
                                           File::SEPARATOR),
           "P3 TXC validator root is outside the recorded staging repository")
    baseline = exact_keys(manifest["baseline"], %w[commit tree], "P3 TXC staging baseline")
    candidate = exact_keys(manifest["candidate"], %w[
      commit tree parent_commit parent_tree branch
    ], "P3 TXC staging candidate")
    assert(baseline == canonical_start.slice("commit", "tree") &&
           candidate["parent_commit"] == baseline["commit"] &&
           candidate["parent_tree"] == baseline["tree"] &&
           candidate["branch"] == "main",
           "P3 TXC staging candidate parent or branch drift")
    assert(git!(root, "rev-parse", "HEAD") == candidate["commit"] &&
           git!(root, "rev-parse", "HEAD^{tree}") == candidate["tree"] &&
           git!(root, "rev-parse", "HEAD^") == candidate["parent_commit"] &&
           git!(root, "rev-parse", "HEAD^^{tree}") == candidate["parent_tree"] &&
           git!(root, "symbolic-ref", "--quiet", "--short", "HEAD") == candidate["branch"] &&
           git!(root, "status", "--porcelain=v1", "--untracked-files=all").empty?,
           "P3 TXC staging candidate Git identity is not clean and exact")
    assert(git!(root, "remote").empty?, "P3 TXC staging clone retained a remote")

    canonical_root = Pathname.new(manifest["canonical_repository"]).realpath
    assert(root.realpath != canonical_root,
           "ATOMIC_STAGING_FIXTURE_MODE cannot run from canonical root")
    canonical_head = git!(canonical_root, "rev-parse", "HEAD")
    canonical_tree = git!(canonical_root, "rev-parse", "HEAD^{tree}")
    canonical_clean = git!(canonical_root, "status", "--porcelain=v1", "--untracked-files=all").empty?
    canonical_main = git!(canonical_root, "symbolic-ref", "--quiet", "--short", "HEAD") == "main"
    if canonical_mode == :staging
      assert(canonical_head == baseline["commit"] && canonical_tree == baseline["tree"] &&
             canonical_main && canonical_clean,
             "P3 TXC canonical baseline drifted during staging")
    else
      assert(git!(canonical_root, "rev-parse", "HEAD^") == baseline["commit"] &&
             git!(canonical_root, "rev-parse", "HEAD^^{tree}") == baseline["tree"] &&
             canonical_tree == candidate["tree"] && canonical_main && canonical_clean,
             "P3 TXC canonical installed commit is not one exact child with the frozen tree")
    end
    canonical_truth = canonical_root.join(canonical_start.dig("truth", "path"))
    canonical_truth_bytes = canonical_truth.binread
    if canonical_mode == :staging
      assert(canonical_truth_bytes.bytesize == canonical_start.dig("truth", "byte_length") &&
             Digest::SHA256.hexdigest(canonical_truth_bytes) ==
               canonical_start.dig("truth", "sha256"),
             "P3 TXC canonical Truth drifted during staging")
    else
      installed_truth = YAML.safe_load(
        canonical_truth_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
      )
      assert(installed_truth.dig("current_phase_route", "schema_version") == TXC_ROUTE_SCHEMA &&
             installed_truth.dig("current_phase_route", "lifecycle_stage") ==
               "PRODUCT_STAGE_ELIGIBLE",
             "P3 TXC canonical installed Truth is not the exact reentry lifecycle")
    end
    canonical_worktrees = git!(canonical_root, "worktree", "list", "--porcelain").lines
      .grep(/^worktree /).map { |line| Pathname.new(line.delete_prefix("worktree ").strip).realpath.to_s }
    assert(canonical_worktrees == [canonical_root.to_s],
           "P3 TXC canonical topology gained an active worktree during staging")

    expected_validators = TXC_STAGING_ALLOWED_VALIDATORS
    assert(manifest["allowed_validators"] == expected_validators,
           "P3 TXC staging allowed-validator set drift")
    effects = exact_keys(manifest["external_effects"], %w[
      network docker product_source_write task_creation remote production public
    ], "P3 TXC staging effects")
    assert(effects.values.all? { |value| value == false },
           "P3 TXC staging manifest claims an external or engineering effect")

    changed_paths = git!(root, "diff", "--name-only", baseline["commit"], candidate["commit"])
      .lines.map(&:strip).reject(&:empty?)
    allowed_paths = staging.fetch("repository_allowlist")
    assert(!changed_paths.empty? && (changed_paths - allowed_paths).empty? &&
           changed_paths.sort == changed_paths.uniq.sort,
           "P3 TXC staging candidate escaped the repository allowlist")
    patch_identity = exact_keys(manifest["frozen_patch"], %w[path byte_length sha256],
                                "P3 TXC frozen patch")
    patch_bytes = txc_manifest_identity_bytes!(patch_identity, "P3 TXC frozen patch")
    actual_patch = txc_git_bytes!(root, "diff", "--binary",
                                 baseline["commit"], candidate["commit"])
    assert(patch_bytes == actual_patch, "P3 TXC frozen patch bytes differ from candidate diff")

    inventory_identity = exact_keys(manifest["closed_inventory"], %w[path byte_length sha256],
                                    "P3 TXC closed inventory")
    inventory = parse_txc_json!(
      txc_manifest_identity_bytes!(inventory_identity, "P3 TXC closed inventory"),
      "P3 TXC closed inventory"
    )
    exact_keys(inventory, %w[schema_version baseline candidate files],
               "P3 TXC closed inventory")
    assert(inventory["schema_version"] == "p3-txcr-closed-inventory/v1" &&
           inventory["baseline"] == baseline &&
           inventory["candidate"] == candidate.slice("commit", "tree") &&
           array(inventory["files"], "P3 TXC inventory files").map { |entry| entry["path"] } ==
             changed_paths,
           "P3 TXC closed inventory binding drift")
    inventory["files"].each do |entry|
      exact_keys(entry, %w[path before after], "P3 TXC inventory entry")
      path = entry.fetch("path")
      before = txc_git_bytes!(root, "show", "#{baseline.fetch('commit')}:#{path}")
      after = root.join(path).binread
      assert(entry["before"] == {
        "byte_length" => before.bytesize, "sha256" => Digest::SHA256.hexdigest(before)
      } && entry["after"] == {
        "byte_length" => after.bytesize, "sha256" => Digest::SHA256.hexdigest(after)
      }, "P3 TXC inventory byte identity drift for #{path}")
    end
    {
      "manifest" => manifest,
      "baseline" => baseline,
      "candidate" => candidate,
      "changed_paths" => changed_paths,
      "canonical_root" => canonical_root.to_s,
      "staging_root" => root.to_s,
      "canonical_mode" => canonical_mode.to_s
    }
  end

  def atomic_staging_context!(root:, truth:)
    manifest_path_string = ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"]
    return nil if manifest_path_string.nil? || manifest_path_string.empty?

    root = Pathname.new(root).realpath
    assert(truth.dig("current_phase_route", "schema_version") == TXC_ROUTE_SCHEMA,
           "ATOMIC_STAGING_FIXTURE_MODE is restricted to the P3 TXC Route")
    decision, = validate_txc_decision!
    manifest_path = Pathname.new(manifest_path_string)
    assert(manifest_path.absolute? && manifest_path.cleanpath.to_s == manifest_path.to_s &&
           manifest_path.dirname.realpath.to_s == TXC_STAGE0_EVIDENCE_ROOT &&
           manifest_path.basename.to_s.match?(
             /\AP3_TXCR_ATOMIC_STAGING_MANIFEST_GENERATION_[12]_V1\.json\z/
           ), "P3 TXC staging manifest path is not the recorded create-once target")
    stat = manifest_path.lstat
    assert(stat.file? && !manifest_path.symlink? && (stat.mode & 0o777) == 0o444 &&
           stat.nlink == 1, "P3 TXC staging manifest is not create-once")
    manifest = parse_txc_json!(manifest_path.binread, "P3 TXC atomic staging manifest")
    expected_generation = manifest_path.basename.to_s[/GENERATION_([12])_V1/, 1].to_i
    assert(manifest["generation"] == expected_generation,
           "P3 TXC manifest filename/generation drift")
    txc_validate_atomic_manifest_values!(
      manifest, root: root, decision: decision, canonical_mode: :staging
    )
  rescue Errno::ENOENT, Errno::ELOOP => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 TXC atomic staging manifest unavailable: #{e.message}"
  end

  def txc_installed_context!(root:, truth:)
    root = Pathname.new(root).realpath
    assert(ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"].to_s.empty?,
           "P3 TXC installed replay cannot use staging fixture mode")
    assert(truth.dig("current_phase_route", "schema_version") == TXC_ROUTE_SCHEMA,
           "P3 TXC installed replay requires the current TXC Route")
    decision, = validate_txc_decision!
    canonical_root = Pathname.new(decision.dig("canonical_start", "repository")).realpath
    baseline = decision.fetch("canonical_start").slice("commit", "tree")
    head = git!(root, "rev-parse", "HEAD")
    tree = git!(root, "rev-parse", "HEAD^{tree}")

    candidates = TXC_INSTALLED_MANIFEST_PATHS.each_with_object([]) do |path_string, matches|
      path = Pathname.new(path_string)
      next unless path.exist?

      stat = path.lstat
      assert(stat.file? && !path.symlink? && (stat.mode & 0o777) == 0o444 && stat.nlink == 1,
             "P3 TXC installed manifest is not create-once")
      manifest = parse_txc_json!(path.binread, "P3 TXC installed manifest")
      next unless manifest.dig("candidate", "tree") == tree

      matches << [path, manifest]
    end
    assert(candidates.length == 1,
           "P3 TXC installed replay did not resolve exactly one matching frozen manifest")
    manifest_path, manifest = candidates.first
    expected_generation = manifest_path.basename.to_s[/GENERATION_([12])_V1/, 1].to_i
    staging_repo = Pathname.new(manifest.fetch("staging_repository")).realpath
    actual_installed = root == canonical_root
    preinstall_simulation = root == staging_repo
    assert(actual_installed || preinstall_simulation,
           "P3 TXC installed replay escaped canonical or the exact recorded simulation clone")
    assert(git!(root, "rev-parse", "HEAD^") == baseline.fetch("commit") &&
           git!(root, "rev-parse", "HEAD^^{tree}") == baseline.fetch("tree") &&
           git!(root, "symbolic-ref", "--quiet", "--short", "HEAD") == "main" &&
           git!(root, "status", "--porcelain=v1", "--untracked-files=all").empty?,
           "P3 TXC installed replay requires one clean atomic child of the exact baseline")
    assert(manifest["generation"] == expected_generation,
           "P3 TXC installed manifest filename/generation drift")
    context = txc_validate_atomic_manifest_values!(
      manifest, root: staging_repo, decision: decision,
      canonical_mode: actual_installed ? :installed : :staging
    )
    assert(context.dig("candidate", "tree") == tree &&
           context.dig("baseline", "commit") == baseline.fetch("commit"),
           "P3 TXC installed context candidate/baseline drift")
    context.merge(
      "manifest_path" => manifest_path.to_s,
      "head" => head,
      "tree" => tree,
      "mode" => actual_installed ? "CANONICAL_INSTALLED_REPLAY_MODE" :
        "CANONICAL_INSTALLED_REPLAY_PREINSTALL_SIMULATION_MODE"
    )
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise P3FinalTransactionalRouteValidationError,
          "P3 TXC installed replay artifact unavailable: #{error.message}"
  end

  def validate_txc_workspace!(root, truth, active_ordinal, lifecycle)
    return atomic_staging_context!(root: root, truth: truth) if
      ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"]

    return txc_installed_context!(root: root, truth: truth) if
      lifecycle == "PRODUCT_STAGE_ELIGIBLE"

    project = mapping(truth["project"], "P3 TXC project")
    canonical_root = Pathname.new(project.fetch("canonical_repository")).realpath
    assert(root.realpath == canonical_root,
           "P3 TXC canonical validation must run from canonical repository")
    assert(git!(root, "symbolic-ref", "--quiet", "--short", "HEAD") ==
             project.fetch("canonical_branch") &&
           git!(root, "status", "--porcelain=v1", "--untracked-files=all").empty?,
           "P3 TXC canonical main must be clean")
    records = git!(root, "worktree", "list", "--porcelain").lines
      .grep(/^worktree /).map { |line| Pathname.new(line.delete_prefix("worktree ").strip).realpath.to_s }
    expected = [canonical_root.to_s]
    if active_ordinal
      expected << Pathname.new(truth.dig("active_work", "task_worktree")).realpath.to_s
    end
    assert(records.sort == expected.sort,
           "P3 TXC worktree topology is not canonical plus the one active Task")
    nil
  end

  def validate_txc_current_gate!(truth, lifecycle, decision_identity)
    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"),
                 "P3 TXC strict Gate")
    compat = mapping(p3.dig("required_items", TXC_COMPATIBILITY_ITEM),
                     "P3 TXC compatibility Gate item")
    current = exact_keys(p3["current_exit_gate"], %w[
      gate_id authority required_item_ids required_items
      same_frozen_candidate_required compatibility_projection
    ], "P3 TXC current Exit Gate")
    assert(current["gate_id"] == TXC_STRICT_GATE_ID &&
           current["authority"] == decision_identity.merge("decision_id" => TXC_DECISION_ID) &&
           current["required_item_ids"] == TXC_STRICT_ITEMS &&
           current["required_items"].keys == TXC_STRICT_ITEMS &&
           current["same_frozen_candidate_required"] == true &&
           current["compatibility_projection"] == {
             "item_id" => TXC_COMPATIBILITY_ITEM,
             "status" => lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" ? "ACCEPTED" : "MISSING",
             "acceptance_requires_all_current_items" => true
           }, "P3 TXC current strict Gate projection drift")
    if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      identities = current["required_item_ids"].map do |item_id|
        item = exact_keys(current.dig("required_items", item_id), %w[
          status candidate_commit candidate_tree evidence
        ], "P3 TXC strict item #{item_id}")
        assert(item["status"] == "ACCEPTED" &&
               item["candidate_commit"].to_s.match?(/\A[0-9a-f]{40}\z/) &&
               item["candidate_tree"].to_s.match?(/\A[0-9a-f]{40}\z/),
               "P3 TXC strict item #{item_id} is not accepted from a frozen candidate")
        read_identity!(item["evidence"], "P3 TXC strict item #{item_id} Evidence",
                       create_once: true)
        item.slice("candidate_commit", "candidate_tree")
      end
      assert(identities.uniq.length == 1 && compat["status"] == "ACCEPTED" &&
             p3["status"] == "COMPLETE" &&
             p3.dig("founder_phase_gate", "status") ==
               "ELIGIBLE_AWAITING_FOUNDER_DECISION",
             "P3 TXC complete Gate did not bind one frozen candidate")
    else
      current["required_item_ids"].each do |item_id|
        item = exact_keys(current.dig("required_items", item_id), %w[
          status candidate_commit candidate_tree evidence
        ], "P3 TXC strict item #{item_id}")
        assert(item == {
          "status" => "MISSING", "candidate_commit" => nil,
          "candidate_tree" => nil, "evidence" => nil
        }, "P3 TXC incomplete strict item #{item_id} falsely claims Evidence")
      end
      assert(compat["status"] == "MISSING" && p3["status"] == "INCOMPLETE" &&
             p3.dig("founder_phase_gate", "status") ==
               "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
             "P3 TXC incomplete Gate falsely became eligible")
    end
  end

  def txc_budget_accounting(stage)
    stage.fetch("budget").slice("engineering_tasks", "engineering_hours", "calendar_days")
  end

  def txc_lifecycle_accounting(decision, lifecycle, spec, statuses)
    stages = decision.fetch("route").fetch("stages")
    terminal_index = lifecycle == "ROUTE_TERMINAL_NON_PASS" ?
      statuses.index("TERMINAL_NON_PASS") : nil
    accepted_count = terminal_index || spec.fetch("accepted_stages")
    consumed_count = terminal_index ? terminal_index + 1 : accepted_count
    active_index = spec["current_task_ordinal"] && spec.fetch("current_task_ordinal") - 1
    consumed = decision.dig("route", "consumed_preserved").dup
    stages.first(consumed_count).each do |stage|
      txc_budget_accounting(stage).each { |key, value| consumed[key] += value }
    end
    reserved = active_index ? txc_budget_accounting(stages.fetch(active_index)) : {}
    remaining = %w[engineering_tasks engineering_hours calendar_days].to_h do |key|
      [key, decision.dig("route", "cumulative_ceiling", key) - consumed.fetch(key) -
        reserved.fetch(key, 0)]
    end
    assert(remaining.values.all? { |value| value >= 0 },
           "P3 TXC lifecycle accounting exceeded the cumulative envelope")
    delivery = if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      terminal_index.zero? ? 25 : 75
    else
      spec.fetch("delivery_percent")
    end
    strict_exit = lifecycle == "ROUTE_TERMINAL_NON_PASS" ? 0 :
      spec.fetch("strict_exit_percent")
    {
      "consumed" => consumed,
      "reserved" => reserved,
      "remaining" => remaining,
      "accepted_stage_count" => accepted_count,
      "active_stage_index" => active_index,
      "terminal_stage_index" => terminal_index,
      "delivery_percent" => delivery,
      "strict_exit_percent" => strict_exit
    }
  end

  def txc_envelope_status(lifecycle)
    return "COMPLETE_P3_TXC_STRICT_EXIT_AWAITING_FOUNDER_PHASE_GATE" if
      lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
    return "HOLD_INCOMPLETE_P3_TXC_ROUTE_TERMINAL_NON_PASS" if
      lifecycle == "ROUTE_TERMINAL_NON_PASS"

    "ACTIVE_P3_TXC_#{lifecycle}"
  end

  def txc_expected_envelope_stages(decision, statuses)
    decision.fetch("route").fetch("stages").each_with_index.map do |stage, index|
      {
        "ordinal" => stage.fetch("ordinal"),
        "task_id" => stage.fetch("task_id"),
        "status" => statuses.fetch(index),
        "budget" => txc_budget_accounting(stage)
      }
    end
  end

  def txc_expected_phase_boundary(decision, scope, lifecycle, spec, accounting)
    stage_index = case lifecycle
                  when "PRODUCT_STAGE_ELIGIBLE", "PRODUCT_TASK_ACTIVE" then 0
                  when "AUDIT_STAGE_ELIGIBLE", "AUDIT_TASK_ACTIVE" then 1
                  end
    stage = stage_index && decision.dig("route", "stages", stage_index)
    active = !spec["current_task_ordinal"].nil?
    task_creation_allowed = %w[PRODUCT_STAGE_ELIGIBLE AUDIT_STAGE_ELIGIBLE].include?(lifecycle)
    founder_scope = if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      "PHASE_ENTRY_OR_EXIT"
    elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
      "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
    else
      "NONE"
    end
    task_scope = case lifecycle
                 when "PRODUCT_STAGE_ELIGIBLE"
                   "ONE_P3_TXC_PRODUCT_TASK_THEN_ONE_LOCKED_ONE_SHOT_AUDIT"
                 when "PRODUCT_TASK_ACTIVE"
                   "NONE_ACTIVE_P3_TXC_PRODUCT_TASK"
                 when "AUDIT_STAGE_ELIGIBLE"
                   "ONE_P3_TXC_ONE_SHOT_AUDIT_TASK"
                 when "AUDIT_TASK_ACTIVE"
                   "NONE_ACTIVE_P3_TXC_AUDIT_TASK"
                 when "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
                   "NONE_P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
                 else
                   "NONE_ROUTE_TERMINAL_EXACT_AUTHORIZATION_EXHAUSTED"
                 end
    product_resources = decision.dig("route", "stages", 0, "resources")
    audit_resources = decision.dig("route", "stages", 1, "resources")
    worker_roots = if stage_index == 0
      [product_resources.fetch("worktree"), product_resources.fetch("evidence_root")]
    elsif stage_index == 1
      [audit_resources.fetch("evidence_root")]
    else
      []
    end
    quality_roots = if stage_index == 0
      [product_resources.fetch("evidence_root"), audit_resources.fetch("evidence_root")]
    elsif stage_index == 1
      [audit_resources.fetch("evidence_root")]
    else
      []
    end
    allowed_kinds = if lifecycle == "PRODUCT_STAGE_ELIGIBLE"
      ["PRODUCT_IMPLEMENTATION", "EVALUATION_ONLY_AFTER_PRODUCT_ACCEPTANCE"]
    elsif lifecycle == "AUDIT_STAGE_ELIGIBLE"
      ["EVALUATION_ONLY"]
    else
      []
    end
    capabilities = if stage_index == 0
      %w[
        HOST_AUTHORIZED_TRANSACTIONAL_INVOCATION_COORDINATOR
        SHA256_READ_ONLY_CUSTODY
        PINNED_EXTERNAL_OCI_ATTESTATION
      ]
    elsif stage_index == 1
      ["PINNED_EXTERNAL_OCI_ATTESTATION"]
    else
      []
    end
    {
      "phase" => "P3",
      "phase_execution_status" => txc_envelope_status(lifecycle),
      "task_creation_allowed" => task_creation_allowed,
      "task_creation_scope" => task_scope,
      "task_creation_lock_after_activation" => true,
      "p3_entry_authorized" => true,
      "allowed_task_kinds" => allowed_kinds,
      "allowed_capabilities" => capabilities,
      "role_write_roots" => {
        "worker" => worker_roots,
        "quality" => quality_roots,
        "integration" => stage ? [decision.dig("canonical_start", "repository")] : [],
        "external_evidence" => "EXTERNAL_TASK_EVIDENCE_ROOT_ONLY"
      },
      "immutable_authority_paths" => TXC_IMMUTABLE_AUTHORITY_PATHS,
      "allowed_independent_reviewers" =>
        ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
      "required_reviewers_by_risk" => {
        "high" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"],
        "critical" => ["CTO Agent", "Security Agent", "Quality and Evaluation Agent"]
      },
      "founder_reserved_risk_levels" => ["critical"],
      "deferred_capabilities" => TXC_DEFERRED_CAPABILITIES,
      "default_external_effects" => TXC_ENVELOPE_FALSE_EFFECTS,
      "founder_decision_required" => spec.fetch("founder_decision_required"),
      "founder_decision_required_scope" => founder_scope,
      "escalation_reason" => if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
        "P3_TXC_STRICT_EXIT_ACCEPTED_FOUNDER_PHASE_GATE_REQUIRED"
      elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
        "EXACT_P3_TXC_ROUTE_TERMINAL_CONTINUATION_REQUIRES_FOUNDER_ROUTE_CHANGE"
      end,
      "user_action_required" => if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
        "FOUNDER_P3_PHASE_GATE_DECISION"
      elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
        "FOUNDER_P3_ROUTE_CHANGE_DECISION"
      else
        "NONE"
      end,
      "phase_route_decision_required" => lifecycle == "ROUTE_TERMINAL_NON_PASS",
      "phase_route_user_action_required" => lifecycle == "ROUTE_TERMINAL_NON_PASS" ?
        "FOUNDER_P3_ROUTE_CHANGE_DECISION" : "NONE",
      "next_eligible_action" => spec.fetch("next_action")
    }
  end

  def txc_expected_project_statuses(lifecycle)
    if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      {
        "phase_execution_status" => "COMPLETE_P3_TXC_STRICT_EXIT_AWAITING_FOUNDER_PHASE_GATE",
        "current_route_execution_status" => "P3_TXC_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
        "p3_execution_status" => "COMPLETE_STRICT_EXIT_AWAITING_FOUNDER_PHASE_GATE"
      }
    elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
      {
        "phase_execution_status" => "HOLD_INCOMPLETE_P3_TXC_ROUTE_TERMINAL_NON_PASS",
        "current_route_execution_status" => "P3_TXC_ROUTE_TERMINAL_NON_PASS",
        "p3_execution_status" => "HOLD_INCOMPLETE_TXC_ROUTE_TERMINAL_NON_PASS"
      }
    else
      {
        "phase_execution_status" => "ACTIVE_P3_TXC_#{lifecycle}",
        "current_route_execution_status" => "P3_TXC_#{lifecycle}",
        "p3_execution_status" => "ACTIVE_INCOMPLETE_TXC_#{lifecycle}"
      }
    end
  end

  def txc_expected_execution_claim(lifecycle, spec, accounting, active)
    product_accepted = accounting.fetch("accepted_stage_count") >= 1
    founder_gate = spec.fetch("founder_decision_required")
    task_creation_allowed = %w[PRODUCT_STAGE_ELIGIBLE AUDIT_STAGE_ELIGIBLE].include?(lifecycle)
    frozen = if product_accepted
      lifecycle == "AUDIT_TASK_ACTIVE" ? ["P3_TXC_FROZEN_PRODUCT_CANDIDATE_MUTATION"] : []
    else
      ["P3_TXC_AUDIT_UNTIL_PRODUCT_ACCEPTED"]
    end
    {
      "current_route_claim" => TXC_ROUTE_ID,
      "current_task_claim" => active.fetch("current_task"),
      "real_engineering_progress" => product_accepted ? 1 : 0,
      "product_capability_changed" => product_accepted,
      "accepted_outcomes" => ["DURABLE_STATE_AND_CHECKPOINT_RESUME"] +
        (product_accepted ? ["TRANSACTIONAL_INVOCATION_COORDINATOR_PRODUCT"] : []),
      "revised_research_exit_percent" => 100,
      "original_capability_progress_percent" => 0,
      "p3_entry_authorized" => true,
      "p3_exit_gate_progress_percent" => accounting.fetch("strict_exit_percent"),
      "p3_delivery_progress_percent" => accounting.fetch("delivery_percent"),
      "phase_local_allowed" => founder_gate ? [] : [spec.fetch("next_action")],
      "phase_local_frozen_capabilities" => frozen,
      "historical_terminal_rules" => [
        "IDENTITY_ACCOUNTING_ONLY", "NO_REJECTED_ENGINEERING_LINEAGE_READ_OR_REUSE"
      ],
      "mandatory_priority_rule" => "PRODUCT_TASK_THEN_ONE_SHOT_AUDIT",
      "not_authorized_in_current_phase" => %w[P4 PROVIDER SECRET REMOTE PRODUCTION PUBLIC],
      "deferred_to_p2_or_later" => [],
      "deferred_to_p3_or_later" => [],
      "forbidden_without_separate_founder_authority" => %w[
        PHASE_ROUTE_CHANGE ENVELOPE_EXPANSION UNDECLARED_EXTERNAL_EFFECT
      ],
      "task_creation_allowed" => task_creation_allowed,
      "remaining_capacity_usable" => task_creation_allowed,
      "held_read_allowed" => false,
      "candidate_integration_allowed" => false,
      "next_eligible_action" => spec.fetch("next_action")
    }
  end

  def validate_txc_route!(root, truth)
    decision, scope = validate_txc_decision!
    decision_identity = TXC_DECISION
    route = mapping(truth["current_phase_route"], "P3 TXC current Route")
    lifecycle = route["lifecycle_stage"]
    spec = TXC_LIFECYCLE_SPECS[lifecycle]
    assert(spec, "P3 TXC lifecycle is outside the closed state machine")
    base_keys = %w[
      schema_version route_id status lifecycle_stage execution_status scheduling_status
      phase phase_entry_status policy founder_phase_route_decision_required
      founder_reserved_triggers_resolved next_eligible_action phase_execution_envelope_ref
      phase_entry_route_ref accepted_p3_001_foundation_route_ref historical_predecessor_route_ref
      founder_route_decision canonical_start constitution objective_id workflow_id
      strict_exit_gate cumulative_accounting ordered_stages progression p3_entry_authorized
      p4_entry_authorized long_term_goal_status current_external_effects
      future_external_effect_authority_ref anti_loop historical_terminal_identities
      rejected_lineage_policy additional_write_roots
    ]
    optional_keys = %w[active_task completed_stages terminal_result]
    assert((route.keys - base_keys - optional_keys).empty? && (base_keys - route.keys).empty?,
           "P3 TXC Route keys drift")
    assert(route["schema_version"] == TXC_ROUTE_SCHEMA && route["route_id"] == TXC_ROUTE_ID &&
           route["status"] == spec["route_status"] &&
           route["execution_status"] == spec["execution_status"] &&
           route["scheduling_status"] == spec["scheduling_status"] &&
           route["phase"] == "P3" && route["phase_entry_status"] == "AUTHORIZED" &&
           route["policy"] == TXC_POLICY &&
           route["founder_phase_route_decision_required"] == spec["founder_decision_required"] &&
           route["founder_reserved_triggers_resolved"] == decision["reserved_triggers"] &&
           route["next_eligible_action"] == spec["next_action"] &&
           route["phase_execution_envelope_ref"] == "phase_execution_envelope" &&
           route["phase_entry_route_ref"] == "historical_p3_phase_entry_route" &&
           route["accepted_p3_001_foundation_route_ref"] ==
             "historical_p3_001_phase_route" &&
           route["historical_predecessor_route_ref"] ==
             "P3_TXC_STAGE0_TERMINAL_IDENTITY_ONLY" &&
           route["objective_id"] == decision.dig("route", "objective_id") &&
           route["workflow_id"] == decision.dig("route", "workflow_id") &&
           route["p3_entry_authorized"] == true && route["p4_entry_authorized"] == false &&
           route["long_term_goal_status"] == "ACTIVE" &&
           route["current_external_effects"] == TXC_CURRENT_FALSE_EFFECTS &&
           route["future_external_effect_authority_ref"] == "founder_route_decision" &&
           route["rejected_lineage_policy"] ==
             "HISTORICAL_IDENTITIES_ONLY_NO_REJECTED_ENGINEERING_LINEAGE_READ_COMPARE_COPY_EXECUTE_REPAIR_OR_REUSE" &&
           route["additional_write_roots"] == [],
           "P3 TXC Route structured projection drift")
    expected_decision_projection = TXC_DECISION.merge(
      "decision_id" => TXC_DECISION_ID,
      "operation_type" => TXC_OPERATION_TYPE,
      "source_body" => TXC_AUTHORIZATION_BODY
    )
    assert(route["founder_route_decision"] == expected_decision_projection &&
           route["canonical_start"] == decision["canonical_start"].slice(
             "repository", "branch", "commit", "tree", "truth", "constitution",
             "exact_recovery_chain", "terminal_receipt"
           ) && route["constitution"] == TXC_CONSTITUTION,
           "P3 TXC Founder decision or canonical binding drift")
    read_repo_identity!(root, TXC_CONSTITUTION, "P3 TXC Constitution")
    assert(route["strict_exit_gate"] == {
      "gate_id" => TXC_STRICT_GATE_ID,
      "required_item_ids" => TXC_STRICT_ITEMS,
      "compatibility_aggregate_item_id" => TXC_COMPATIBILITY_ITEM,
      "same_frozen_candidate_required" => true
    }, "P3 TXC strict Gate declaration drift")
    statuses = spec["stage_statuses"]
    if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      statuses = route.fetch("ordered_stages").map { |stage| stage.fetch("status") }
      assert(statuses.length == 2 && statuses.count("TERMINAL_NON_PASS") == 1 &&
             statuses.drop(statuses.index("TERMINAL_NON_PASS") + 1).all? do |status|
               status == "LOCKED_ROUTE_TERMINAL"
             end, "P3 TXC terminal stage disposition drift")
    end
    lifecycle_accounting = txc_lifecycle_accounting(decision, lifecycle, spec, statuses)
    expected_accounting = {
      "limits" => decision.dig("route", "cumulative_ceiling"),
      "consumed" => lifecycle_accounting.fetch("consumed"),
      "remaining" => lifecycle_accounting.fetch("remaining")
    }
    assert(route["cumulative_accounting"] == expected_accounting,
           "P3 TXC cumulative accounting reset or expansion")
    assert(route["ordered_stages"] == txc_expected_stages(decision, scope, statuses),
           "P3 TXC ordered stage projection drift")
    assert(route["progression"] == {
      "delivery_percent" => lifecycle_accounting.fetch("delivery_percent"),
      "strict_exit_percent" => lifecycle_accounting.fetch("strict_exit_percent"),
      "accepted_stages" => lifecycle_accounting.fetch("accepted_stage_count"),
      "total_stages" => 2
    }, "P3 TXC progress projection drift")
    assert(route["anti_loop"] == {
      "foundation_task_allowed" => false,
      "third_product_task_allowed" => false,
      "successor_or_replacement_allowed" => false,
      "normalization_closure_feasibility_or_remediation_allowed" => false,
      "candidate_3_allowed" => false,
      "second_same_task_repair_allowed" => false,
      "third_review_cycle_allowed" => false,
      "v2_or_v3_authorization_chain_allowed" => false,
      "rerun_to_pass_allowed" => false,
      "governance_progress_credit" => 0
    }, "P3 TXC anti-loop boundary drift")
    expected_historical = TXCR_HISTORICAL_TERMINAL_IDENTITIES
    assert(route["historical_terminal_identities"] == expected_historical,
           "P3 TXC historical terminal identity set drift")
    expected_historical.each do |label, identity|
      read_identity!(identity, "P3 TXC historical #{label}")
    end

    envelope = exact_keys(truth["phase_execution_envelope"], %w[
      schema_version phase status authority_basis accounting_basis consumed limits reserved
      remaining remaining_capacity_usable remaining_capacity_lock_reason milestone_order
      accepted_milestones ordered_stages delivery_progress governance_progress_credit
      external_effects
    ], "P3 TXC Phase envelope")
    task_creation_allowed = %w[PRODUCT_STAGE_ELIGIBLE AUDIT_STAGE_ELIGIBLE].include?(lifecycle)
    accepted_milestones = ["DURABLE_STATE_AND_CHECKPOINT_RESUME"]
    accepted_milestones << "TRANSACTIONAL_INVOCATION_COORDINATOR_PRODUCT" if
      lifecycle_accounting.fetch("accepted_stage_count") >= 1
    accepted_milestones << TXC_STRICT_GATE_ID if
      lifecycle_accounting.fetch("accepted_stage_count") >= 2
    capacity_lock = if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      "ROUTE_TERMINAL_EXACT_AUTHORIZATION_PROHIBITS_REUSE_OR_FOLLOW_ON_TASK"
    elsif lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
      "P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
    elsif spec["current_task_ordinal"]
      "ACTIVE_TASK_CONSUMES_SINGLE_TASK_SLOT"
    else
      "NONE"
    end
    accepted_counter = {
      25 => 1,
      75 => 3,
      100 => 4
    }.fetch(lifecycle_accounting.fetch("delivery_percent"))
    assert(envelope == {
      "schema_version" => "phase-execution-envelope/v1",
      "phase" => "P3",
      "status" => txc_envelope_status(lifecycle),
      "authority_basis" => {
        "phase_entry_status" => "AUTHORIZED",
        "source_route_ref" => "current_phase_route",
        "source_route_id" => TXC_ROUTE_ID,
        "founder_route_decision" => TXC_DECISION
      },
      "accounting_basis" => "NON_RESETTABLE_CUMULATIVE_P3_FOUNDER_ENVELOPE",
      "consumed" => lifecycle_accounting.fetch("consumed"),
      "limits" => decision.dig("route", "cumulative_ceiling"),
      "reserved" => lifecycle_accounting.fetch("reserved"),
      "remaining" => lifecycle_accounting.fetch("remaining"),
      "remaining_capacity_usable" => task_creation_allowed,
      "remaining_capacity_lock_reason" => capacity_lock,
      "milestone_order" => [
        "DURABLE_STATE_AND_CHECKPOINT_RESUME",
        "TRANSACTIONAL_INVOCATION_COORDINATOR_PRODUCT",
        TXC_STRICT_GATE_ID
      ],
      "accepted_milestones" => accepted_milestones,
      "ordered_stages" => txc_expected_envelope_stages(decision, statuses),
      "delivery_progress" => {
        "accepted" => accepted_counter,
        "total" => 4,
        "percent" => lifecycle_accounting.fetch("delivery_percent"),
        "strict_exit_gate_percent" => lifecycle_accounting.fetch("strict_exit_percent")
      },
      "governance_progress_credit" => 0,
      "external_effects" => TXC_ENVELOPE_FALSE_EFFECTS
    }, "P3 TXC Phase envelope closed lifecycle projection drift")

    validate_txc_current_gate!(truth, lifecycle, decision_identity)
    expected_boundary = txc_expected_phase_boundary(
      decision, scope, lifecycle, spec, lifecycle_accounting
    )
    active = exact_keys(truth["active_work"], %w[
      current_task current_task_status current_task_contract current_task_contract_sha256
      current_execution_authorization current_execution_authorization_sha256 authority_record
      execution_nonce execution_nonce_status authorization_id activation_parent_commit
      activation_parent_tree stage0_installation_parent task_resource_state task_branch
      task_worktree execution_evidence_root dependency_custody_root allowlisted_paths
      current_task_budget next_stage_budget roles external_effects offsite_target
      founder_reserved_authorization founder_reserved_authorization_sha256
      founder_decision_required founder_decision_required_scope escalation_reason
      user_action_required phase_route_decision_required phase_route_user_action_required
      completed_tasks historical_terminal_accounting next_eligible_action
    ], "P3 TXC active work")
    active_ordinal = spec["current_task_ordinal"]
    if active_ordinal
      stage = route.fetch("ordered_stages").fetch(active_ordinal - 1)
      assert(active["current_task"] == stage["task_id"] &&
             active["current_task_status"] == "ACTIVE" &&
             active["task_branch"] == stage.dig("resources", "branch") &&
             active["task_worktree"] == stage.dig("resources", "worktree") &&
             active["execution_evidence_root"] == stage.dig("resources", "evidence_root") &&
             active["current_task_budget"] == stage["budget"] &&
             active["next_stage_budget"] == {} &&
             active["task_resource_state"] == "ACTIVE_UNIQUE_P3_TXC_STAGE" &&
             active["execution_nonce_status"] == "ACTIVE" &&
             active["offsite_target"].nil?,
             "P3 TXC active Task resource projection drift")
      contract = exact_keys(active.fetch("current_task_contract"), %w[path byte_length sha256],
                            "P3 TXC active Contract")
      authority = exact_keys(active.fetch("authority_record"), %w[path byte_length sha256],
                             "P3 TXC active authority")
      read_identity!(contract, "P3 TXC active Contract", create_once: true)
      read_identity!(authority, "P3 TXC active authority", create_once: true)
      expected_allowlist = active_ordinal == 1 ?
        scope.dig("product", "repository_allowlist") : []
      expected_custody = if active_ordinal == 1
        "#{stage.dig('resources', 'evidence_root')}/custody"
      else
        "#{decision.dig('route', 'stages', 0, 'resources', 'evidence_root')}/custody"
      end
      expected_effects = TXC_TASK_FALSE_EFFECTS.dup
      if active_ordinal == 1
        expected_effects["docker"] = true
        expected_effects["network"] = true
      else
        expected_effects["docker"] = true
      end
      assert(active["current_task_contract_sha256"] == contract["sha256"] &&
             active["current_execution_authorization"] == authority["path"] &&
             active["current_execution_authorization_sha256"] == authority["sha256"] &&
             active["execution_nonce"].to_s.match?(/\A[0-9a-f-]{36}\z/) &&
             active["authorization_id"].to_s.match?(/\A[0-9a-f-]{36}\z/) &&
             active["activation_parent_commit"].to_s.match?(/\A[0-9a-f]{40}\z/) &&
             active["activation_parent_tree"].to_s.match?(/\A[0-9a-f]{40}\z/) &&
             active["dependency_custody_root"] == expected_custody &&
             active["allowlisted_paths"] == expected_allowlist &&
             active["external_effects"] == expected_effects,
             "P3 TXC active Contract/authority/scope/effect projection drift")
    else
      assert(active["current_task"] == "NONE" && active["authority_record"].nil? &&
             active["current_task_contract"].nil? &&
             active["current_task_contract_sha256"].nil? &&
             active["current_execution_authorization"].nil? &&
             active["current_execution_authorization_sha256"].nil? &&
             active["execution_nonce"].nil? && active["task_branch"].nil? &&
             active["authorization_id"].nil? &&
             active["activation_parent_commit"].nil? &&
             active["activation_parent_tree"].nil? &&
             active["task_worktree"].nil? && active["execution_evidence_root"].nil?,
             "P3 TXC no-Task lifecycle retained active authority/resources")
      expected_no_task_status = {
        "PRODUCT_STAGE_ELIGIBLE" => "NONE_PRODUCT_STAGE_ELIGIBLE",
        "AUDIT_STAGE_ELIGIBLE" => "NONE_AUDIT_STAGE_ELIGIBLE",
        "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" =>
          "NONE_P3_COMPLETE_AWAITING_FOUNDER_PHASE_GATE",
        "ROUTE_TERMINAL_NON_PASS" => "NONE_ROUTE_TERMINAL_NON_PASS"
      }.fetch(lifecycle)
      expected_resource_state = {
        "PRODUCT_STAGE_ELIGIBLE" => "NOT_CREATED_PRODUCT_STAGE_ELIGIBLE",
        "AUDIT_STAGE_ELIGIBLE" => "NOT_CREATED_AUDIT_STAGE_ELIGIBLE",
        "COMPLETE_AWAITING_FOUNDER_PHASE_GATE" => "COMPLETE_NO_TASK_RESOURCES",
        "ROUTE_TERMINAL_NON_PASS" => "TERMINAL_ROUTE_NO_TASK_RESOURCES"
      }.fetch(lifecycle)
      next_index = lifecycle == "PRODUCT_STAGE_ELIGIBLE" ? 0 :
        (lifecycle == "AUDIT_STAGE_ELIGIBLE" ? 1 : nil)
      assert(active["current_task_status"] == expected_no_task_status &&
             active["task_resource_state"] == expected_resource_state &&
             active["execution_nonce_status"] ==
               (lifecycle == "PRODUCT_STAGE_ELIGIBLE" ? "NOT_ISSUED" : "NO_CURRENT_TASK") &&
             active["dependency_custody_root"].nil? && active["allowlisted_paths"] == [] &&
             active["current_task_budget"] == {
               "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0
             } &&
             active["next_stage_budget"] ==
               (next_index ? decision.dig("route", "stages", next_index, "budget") : {}) &&
             active["external_effects"] == TXC_TASK_FALSE_EFFECTS &&
             active["offsite_target"].nil?,
             "P3 TXC no-Task lifecycle/scope/budget/effect projection drift")
    end
    expected_completed_count = if lifecycle == "ROUTE_TERMINAL_NON_PASS"
      lifecycle_accounting.fetch("terminal_stage_index") + 1
    else
      lifecycle_accounting.fetch("accepted_stage_count")
    end
    completed = array(active["completed_tasks"], "P3 TXC completed Task chain")
    assert(completed.length == expected_completed_count,
           "P3 TXC completed Task chain length drift")
    completed.each_with_index do |entry, index|
      record = exact_keys(entry, %w[task_id status receipt],
                          "P3 TXC completed Task #{index + 1}")
      expected_status = lifecycle == "ROUTE_TERMINAL_NON_PASS" &&
        index == lifecycle_accounting.fetch("terminal_stage_index") ?
          "TERMINAL_NON_PASS" : "ACCEPTED_INTEGRATED"
      assert(record["task_id"] == decision.dig("route", "stages", index, "task_id") &&
             record["status"] == expected_status,
             "P3 TXC completed Task identity/status drift")
      read_identity!(record["receipt"], "P3 TXC completed Task #{index + 1} receipt",
                     create_once: true)
    end
    expected_roles = {
      "owner" => "MASTER_CEO_AGENT",
      "worker" => "IMPLEMENTATION_AGENT",
      "quality_owner" => "QUALITY_EVALUATION_AGENT",
      "independent_reviewers" => TXC_REVIEWERS
    }
    assert(active["stage0_installation_parent"] ==
             decision.dig("canonical_start").slice("commit", "tree") &&
           active["roles"] == expected_roles &&
           active["historical_terminal_accounting"] == {
             "consumed_engineering_tasks" => 10,
             "consumed_engineering_hours" => 272,
             "consumed_calendar_days" => 68,
             "latest_terminal_task_id" =>
               "AIOS-P3-HPE-F1_HOST_PROCESS_CONFINEMENT_COMPATIBILITY_FOUNDATION",
             "latest_terminal_receipt_sha256" =>
               TXCR_HISTORICAL_TERMINAL_IDENTITIES.dig(
                 "hpe_terminal_receipt", "sha256"
               )
           },
           "P3 TXC active-work role/install/history projection drift")
    assert(active["founder_reserved_authorization"] == TXC_DECISION["path"] &&
           active["founder_reserved_authorization_sha256"] == TXC_DECISION["sha256"] &&
           active["founder_decision_required"] == spec["founder_decision_required"] &&
           active["founder_decision_required_scope"] ==
             expected_boundary["founder_decision_required_scope"] &&
           active["escalation_reason"] == expected_boundary["escalation_reason"] &&
           active["user_action_required"] == expected_boundary["user_action_required"] &&
           active["phase_route_decision_required"] ==
             expected_boundary["phase_route_decision_required"] &&
           active["phase_route_user_action_required"] ==
             expected_boundary["phase_route_user_action_required"] &&
           active["next_eligible_action"] == spec["next_action"],
           "P3 TXC active-work authority drift")

    control = mapping(truth["founder_escalation_control"], "P3 TXC Founder control")
    expected_disposition = spec["founder_decision_required"] ?
      "FOUNDER_RESERVED_DECISION_REQUIRED" : "NO_RESERVED_TRIGGER_CONTINUE_PHASE"
    expected_trigger = if lifecycle == "COMPLETE_AWAITING_FOUNDER_PHASE_GATE"
                         "PHASE_ENTRY_OR_EXIT"
                       elsif lifecycle == "ROUTE_TERMINAL_NON_PASS"
                         "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
                       else
                         "NONE"
                       end
    assert(control["schema_version"] == "founder-escalation-control/v2" &&
           control["disposition"] == expected_disposition &&
           control.dig("reserved_trigger", "category") == expected_trigger &&
           control["founder_decision_required"] == spec["founder_decision_required"] &&
           control["next_action_owner"] == spec["next_action_owner"] &&
           control["next_eligible_action"] == spec["next_action"] &&
           control.dig("resolved_strategy_decision", "decision_id") == TXC_DECISION_ID &&
           control.dig("resolved_strategy_decision", "sha256") == TXC_DECISION["sha256"],
           "P3 TXC Founder escalation projection drift")
    delegation = exact_keys(truth["phase_delegation"], %w[
      status model decision_source phase_gate_owner task_selection_owner
      task_authorization_owner task_gate_owner p3_entry_authorized
      founder_reserved_decisions agent_delegated_decisions escalation_conditions
      anti_loop claim_boundary
    ], "P3 TXC Phase delegation")
    assert(delegation == {
      "status" => txc_envelope_status(lifecycle),
      "model" => "PHASE_LEVEL_FOUNDER_DELEGATION",
      "decision_source" => TXC_DECISION_ID,
      "phase_gate_owner" => "HUMAN_FOUNDER",
      "task_selection_owner" => "MASTER_CEO_AGENT",
      "task_authorization_owner" => "MASTER_CEO_AGENT",
      "task_gate_owner" => "MASTER_CEO_AGENT",
      "p3_entry_authorized" => true,
      "founder_reserved_decisions" => %w[
        PHASE_ENTRY_OR_EXIT
        MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
        MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
        NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT
        IRREVERSIBLE_ASSET_REMOVAL
        MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT
        CRITICAL_RESIDUAL_RISK_ACCEPTANCE
      ],
      "agent_delegated_decisions" => %w[
        PRODUCT_TASK_ACTIVATION
        TASK_CONTRACT_AND_AUTHORITY
        IMPLEMENTATION_AND_SAME_TASK_REPAIR
        TEST_EVIDENCE_REVIEW_TASK_GATE
        LOCAL_CANONICAL_INTEGRATION
        AUDIT_TASK_ACTIVATION_AFTER_PRODUCT_ACCEPTANCE
      ],
      "escalation_conditions" => ["EXACT_FOUNDER_RESERVED_TRIGGER_ONLY"],
      "anti_loop" => {
        "route_or_task_may_downgrade_phase_delegation" => false,
        "phase_execution_envelope_survives_route_terminal" => false,
        "ordinary_task_failure_requests_founder" => false,
        "successor_or_replacement_allowed" => false
      },
      "claim_boundary" => "P3_TXC_TWO_ORDERED_TASKS_ONLY_P4_HOLD_LONG_TERM_GOAL_ACTIVE"
    }, "P3 TXC Phase delegation closed projection drift")
    boundary = mapping(truth["phase_boundary"], "P3 TXC Phase boundary")
    assert(boundary == expected_boundary,
           "P3 TXC Phase boundary closed authority projection drift")

    project = mapping(truth["project"], "P3 TXC project")
    expected_project_statuses = txc_expected_project_statuses(lifecycle)
    assert(project["current_phase"] == "P3" && project["p3_entry_status"] == "AUTHORIZED" &&
           project["phase_execution_status"] ==
             expected_project_statuses["phase_execution_status"] &&
           project["current_route_execution_status"] ==
             expected_project_statuses["current_route_execution_status"] &&
           project["p3_execution_status"] == expected_project_statuses["p3_execution_status"] &&
           project["p4_entry_status"] ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_task_authority") == active["current_task"],
           "P3 TXC project/Goal boundary drift")
    execution = mapping(truth["phase_execution_claim"], "P3 TXC execution claim")
    claim = mapping(truth["claim_boundary"], "P3 TXC claim boundary")
    assert(execution == txc_expected_execution_claim(
             lifecycle, spec, lifecycle_accounting, active
           ), "P3 TXC execution claim closed projection drift")
    assert(claim["current_phase_route"] == TXC_ROUTE_ID &&
           claim["current_task"] == active["current_task"] &&
           claim["next_eligible_action"] == spec["next_action"] &&
           claim["p3_exit_gate_progress_percent"] ==
             lifecycle_accounting.fetch("strict_exit_percent") &&
           claim["p3_delivery_progress_percent"] ==
             lifecycle_accounting.fetch("delivery_percent") &&
           claim["p3_txc_route_decision_sha256"] == TXC_DECISION["sha256"] &&
           claim["p3_txc_route_stage"] == lifecycle &&
           claim["p3_txc_route_delivery_credit"] ==
             lifecycle_accounting.fetch("delivery_percent") - 25 &&
           claim["p3_txc_route_strict_exit_credit"] ==
             lifecycle_accounting.fetch("strict_exit_percent") &&
           claim["long_term_goal_status"] == "ACTIVE",
           "P3 TXC execution/claim projection drift")
    validate_txc_workspace!(root, truth, active_ordinal, lifecycle)
    TXC_LIFECYCLE_STATES.fetch(lifecycle)
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3FinalTransactionalRouteValidationError, "P3 TXC route invalid: #{e.message}"
  end

  def thtcb_projection_sha256(value)
    Digest::SHA256.hexdigest(canonical_json(value))
  end

  def validate_thtcb_repository_context!(root, decision, lifecycle_stage)
    canonical_root = Pathname.new(THTCB_CANONICAL_START.fetch("repository")).realpath
    if root != canonical_root
      staged_root = ENV["SOURCELENS_THTCB_STRATEGIC_STAGING_ROOT"]
      assert(staged_root && Pathname.new(staged_root).realpath == root,
             "P3 THTCB non-canonical root is not the exact declared strategic staging root")
    else
      assert(git!(root, "rev-parse", "--abbrev-ref", "HEAD") == "main",
             "P3 THTCB canonical installation must remain on main")
    end
    assert(git!(root, "rev-parse", "#{THTCB_CANONICAL_START.fetch('commit')}^{tree}") ==
             THTCB_CANONICAL_START.fetch("tree"),
           "P3 THTCB canonical-start tree drift")
    _out, _err, ancestor = Open3.capture3(
      "git", "merge-base", "--is-ancestor", THTCB_CANONICAL_START.fetch("commit"), "HEAD",
      chdir: root.to_s
    )
    assert(ancestor.success?, "P3 THTCB canonical start is not an ancestor of HEAD")
    allowed = array(
      decision.dig("strategic_installation", "allowed_repository_paths"),
      "P3 THTCB strategic installation path allowlist"
    )
    if lifecycle_stage == "PRODUCT_TASK_ACTIVE"
      allowed = (allowed + THTCB_PRODUCT_MASTER_PATHS).uniq
    end
    changed = git!(root, "diff", "--name-only", THTCB_CANONICAL_START.fetch("commit")).lines
      .map(&:strip).reject(&:empty?)
    untracked = git!(root, "ls-files", "--others", "--exclude-standard").lines
      .map(&:strip).reject(&:empty?)
    assert(((changed + untracked).uniq - allowed).empty?,
           "P3 THTCB strategic installation escaped its exact repository path allowlist")
  rescue Errno::ENOENT, Errno::ELOOP => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 THTCB repository context unavailable: #{e.message}"
  end

  def load_thtcb_canonical_start_truth!(root)
    identity = THTCB_CANONICAL_START.fetch("truth")
    bytes, stderr, status = Open3.capture3(
      "git", "show", "#{THTCB_CANONICAL_START.fetch('commit')}:#{identity.fetch('path')}",
      chdir: root.to_s
    )
    assert(status.success?, "P3 THTCB canonical-start Truth unavailable: #{stderr.strip}")
    assert(bytes.bytesize == identity.fetch("byte_length") &&
           Digest::SHA256.hexdigest(bytes) == identity.fetch("sha256"),
           "P3 THTCB canonical-start Truth identity drift")
    YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def validate_thtcb_decision!(root, lifecycle_stage)
    bytes = read_identity!(THTCB_DECISION, "P3 THTCB Founder decision", create_once: true)
    decision = JSON.parse(bytes)
    assert(decision["schema_version"] == THTCB_DECISION_SCHEMA &&
           decision["record_type"] == "FOUNDER_ACCEPTED_STRATEGIC_DECISION" &&
           decision["decision_id"] == THTCB_DECISION_ID &&
           decision["operation_type"] == THTCB_OPERATION_TYPE &&
           decision["status"] == "ACCEPTED_CURRENT_DIRECT_FOUNDER_MESSAGE",
           "P3 THTCB Founder decision identity or lifecycle drift")
    body = read_identity!(THTCB_AUTHORIZATION_BODY, "P3 THTCB authorization body",
                          create_once: true)
    body_text = body.dup.force_encoding(Encoding::UTF_8)
    assert(body_text.valid_encoding? && body_text.lines.first&.chomp == THTCB_DECISION_ID,
           "P3 THTCB authorization body token drift")
    assert(decision.dig("source", "installed_body") ==
             THTCB_AUTHORIZATION_BODY.merge(
               "byte_equal_to_attachment" => true, "mode" => "0444", "nlink" => 1
             ), "P3 THTCB installed authorization body projection drift")
    start = mapping(decision["canonical_start"], "P3 THTCB canonical start")
    assert(start.slice("repository", "branch", "commit", "tree") ==
             THTCB_CANONICAL_START.slice("repository", "branch", "commit", "tree") &&
           start["clean"] == true && start["truth"] == THTCB_CANONICAL_START.fetch("truth") &&
           start["constitution"] == THTCB_CANONICAL_START.fetch("constitution"),
           "P3 THTCB canonical-start decision binding drift")
    assert(decision.dig("authority", "primary_reserved_trigger") ==
             "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE" &&
           decision.dig("authority", "phase_entry_remains_authorized") == true &&
           decision.dig("authority", "p4_entry_authorized") == false &&
           decision.dig("authority", "long_term_goal_status") == "ACTIVE",
           "P3 THTCB authority-layer projection drift")
    assert(decision.dig("strategic_change", "constitution_version") == "3.1" &&
           decision.dig("strategic_change", "objective_id") ==
             "TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION" &&
           decision.dig("strategic_change", "strict_exit_gate_id") == THTCB_STRICT_GATE_ID &&
           decision.dig("strategic_change", "required_gate_items") == THTCB_STRICT_ITEMS,
           "P3 THTCB strategic Objective or strict Exit Gate drift")
    assert(decision.dig("threat_model", "trusted_computing_base") == THTCB_TCB &&
           decision.dig("threat_model", "included_threats") == THTCB_INCLUDED_THREATS &&
           decision.dig("threat_model", "excluded_as_tcb_compromise") ==
             THTCB_EXCLUDED_THREATS,
           "P3 THTCB threat-model boundary drift")
    assert(decision.dig("route", "route_id") == THTCB_ROUTE_ID &&
           decision.dig("route", "foundation_task_allowed") == false &&
           decision.dig("route", "cumulative_ceiling") == {
             "engineering_tasks" => 13, "engineering_hours" => 384,
             "calendar_days" => 94
           } && decision.dig("route", "consumed_preserved") == {
             "engineering_tasks" => 11, "engineering_hours" => 320,
             "calendar_days" => 78
           } && decision.dig("route", "remaining") == {
             "engineering_tasks" => 2, "engineering_hours" => 64,
             "calendar_days" => 16
           }, "P3 THTCB non-resettable cumulative envelope drift")
    assert(decision.dig("lifecycle", "project_actual_completion") == false &&
           decision.dig("lifecycle", "long_term_goal_status") == "ACTIVE" &&
           decision.dig("lifecycle", "codex_goal_completion_authorized") == false,
           "P3 THTCB project or Long-term Goal lifecycle drift")
    validate_thtcb_repository_context!(root, decision, lifecycle_stage)
    decision
  rescue JSON::ParserError => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 THTCB Founder decision is not valid JSON: #{e.message}"
  end

  def validate_thtcb_installed_route!(root, truth)
    root = Pathname.new(root).realpath
    assert(truth["record_type"] == "sourcelens_aios_current_truth",
           "P3 THTCB canonical Truth record type drift")
    decision = validate_thtcb_decision!(root, "PRODUCT_ELIGIBLE_NOT_ACTIVATED")
    baseline = load_thtcb_canonical_start_truth!(root)
    THTCB_HISTORICAL_PROJECTIONS.each do |historical_key, baseline_key|
      assert(truth[historical_key] == baseline[baseline_key],
             "P3 THTCB immutable historical projection drift: #{historical_key}")
    end
    constitution_bytes = read_repo_identity!(
      root, THTCB_CONSTITUTION, "P3 THTCB Strategic Constitution v3.1"
    )
    assert(constitution_bytes.include?("- Version: `3.1`") &&
           constitution_bytes.include?("`#{THTCB_STRICT_GATE_ID}`") &&
           constitution_bytes.include?("`TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION`"),
           "P3 THTCB Constitution semantic anchor drift")

    THTCB_INSTALLED_PROJECTION_SHA256.each do |key, expected_sha|
      value = if key == "strict_p3"
                truth.dig("strict_phase_gate_ledger", "phases", "P3")
              else
                truth[key]
              end
      assert(!value.nil? && thtcb_projection_sha256(value) == expected_sha,
             "P3 THTCB closed projection drift: #{key}")
    end

    route = mapping(truth["current_phase_route"], "P3 THTCB current Route")
    assert(route["schema_version"] == THTCB_ROUTE_SCHEMA &&
           route["route_id"] == THTCB_ROUTE_ID && route["phase"] == "P3" &&
           route["status"] == "ACTIVE_PRODUCT_ELIGIBLE" &&
           route["lifecycle_stage"] == "PRODUCT_ELIGIBLE_NOT_ACTIVATED" &&
           route["next_eligible_action"] == THTCB_ACTION &&
           route["founder_route_decision"] == THTCB_DECISION.merge(
             "decision_id" => THTCB_DECISION_ID,
             "operation_type" => THTCB_OPERATION_TYPE,
             "source_body" => THTCB_AUTHORIZATION_BODY
           ) && route["canonical_start"].slice("repository", "branch", "commit", "tree",
                                                "truth", "constitution") ==
             THTCB_CANONICAL_START && route["constitution"] == THTCB_CONSTITUTION &&
           route["objective_id"] == "TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION" &&
           route["workflow_id"] == "SHA256_READ_ONLY_CUSTODY_V1" &&
           route.dig("threat_model", "trusted_computing_base") == THTCB_TCB &&
           route.dig("threat_model", "included_threats") == THTCB_INCLUDED_THREATS &&
           route.dig("threat_model", "excluded_as_tcb_compromise") ==
             THTCB_EXCLUDED_THREATS && route.dig("strict_exit_gate", "gate_id") ==
             THTCB_STRICT_GATE_ID &&
           route.dig("strict_exit_gate", "required_item_ids") == THTCB_STRICT_ITEMS,
           "P3 THTCB Route semantic projection drift")
    assert(route.dig("ordered_stages", 0, "task_id") ==
             "AIOS-P3-THTCB-P1_TRUSTED_HOST_TRANSACTIONAL_COORDINATOR_PRODUCT" &&
           route.dig("ordered_stages", 0, "status") ==
             "ELIGIBLE_MASTER_ACTIVATE_IMMEDIATELY" &&
           route.dig("ordered_stages", 1, "task_id") ==
             "AIOS-P3-THTCB-A1_ONE_SHOT_STRICT_EXIT_AUDIT" &&
           route.dig("ordered_stages", 1, "status") ==
             "LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED",
           "P3 THTCB Product-then-Audit order drift")
    assert(route.dig("cumulative_accounting", "limits") ==
             decision.dig("route", "cumulative_ceiling").merge(
               "active_tasks" => 1, "task_branches" => 1,
               "task_worktrees" => 1, "active_candidates" => 1
             ) && route.dig("cumulative_accounting", "consumed") ==
             decision.dig("route", "consumed_preserved") &&
           route.dig("cumulative_accounting", "remaining") ==
             decision.dig("route", "remaining"),
           "P3 THTCB Route accounting drift")
    assert(route.dig("anti_loop", "foundation_task_allowed") == false &&
           route.dig("anti_loop", "candidate_3_allowed") == false &&
           route.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           route.dig("anti_loop", "third_review_cycle_allowed") == false &&
           route.dig("anti_loop", "successor_or_replacement_allowed") == false &&
           route.dig("anti_loop", "governance_progress_credit") == 0,
           "P3 THTCB anti-cycle boundary drift")

    envelope = mapping(truth["phase_execution_envelope"], "P3 THTCB Phase envelope")
    assert(envelope["status"] == "ACTIVE_P3_THTCB_PRODUCT_ELIGIBLE" &&
           envelope["consumed"] == decision.dig("route", "consumed_preserved") &&
           envelope["remaining"] == decision.dig("route", "remaining") &&
           envelope["remaining_capacity_usable"] == true &&
           envelope["governance_progress_credit"] == 0,
           "P3 THTCB Phase envelope semantic drift")
    control = mapping(truth["founder_escalation_control"],
                      "P3 THTCB Founder escalation control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control.dig("reserved_trigger", "category") == "NONE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == THTCB_ACTION,
           "P3 THTCB Founder interruption boundary drift")
    boundary = mapping(truth["phase_boundary"], "P3 THTCB Phase boundary")
    active = mapping(truth["active_work"], "P3 THTCB active work")
    assert(boundary["task_creation_allowed"] == true &&
           boundary["task_creation_scope"] == "EXACT_AIOS_P3_THTCB_P1_PRODUCT_ONLY" &&
           boundary["founder_decision_required"] == false &&
           boundary["next_eligible_action"] == THTCB_ACTION &&
           active["current_task"] == "NONE" &&
           active["selected_task"] ==
             "AIOS-P3-THTCB-P1_TRUSTED_HOST_TRANSACTIONAL_COORDINATOR_PRODUCT" &&
           active["current_task_status"] ==
             "NONE_PRODUCT_ELIGIBLE_PENDING_MASTER_ACTIVATION" &&
           active["task_resource_state"] == "NOT_CREATED_MASTER_ACTIVATION_REQUIRED" &&
           active["founder_decision_required"] == false &&
           active["user_action_required"] == "NONE" &&
           active["next_eligible_action"] == THTCB_ACTION,
           "P3 THTCB Product activation boundary drift")
    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"),
                 "P3 THTCB strict Exit Gate")
    assert(p3["status"] == "INCOMPLETE" &&
           p3.dig("current_exit_gate", "gate_id") == THTCB_STRICT_GATE_ID &&
           p3.dig("current_exit_gate", "authority") == THTCB_DECISION.merge(
             "decision_id" => THTCB_DECISION_ID
           ) && p3.dig("current_exit_gate", "required_item_ids") == THTCB_STRICT_ITEMS &&
           THTCB_STRICT_ITEMS.all? do |item_id|
             p3.dig("current_exit_gate", "required_items", item_id, "status") == "MISSING"
           end && p3.dig("founder_phase_gate", "status") ==
             "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "P3 THTCB strict Exit Gate false acceptance or identity drift")
    assert(truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "p3_execution_status") == "ACTIVE_THTCB_PRODUCT_ELIGIBLE" &&
           truth.dig("project", "p4_entry_status") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_task_authority") == "NONE" &&
           truth.dig("goal", "current_strategic_decision", "decision_id") ==
             THTCB_DECISION_ID,
           "P3 THTCB project, P4 or Long-term Goal lifecycle drift")
    THTCB_STATE
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 THTCB route invalid: #{e.message}"
  end

  def validate_thtcb_projection_set!(truth, expected)
    expected.each do |key, expected_sha|
      value = if key == "strict_p3"
                truth.dig("strict_phase_gate_ledger", "phases", "P3")
              else
                truth[key]
              end
      assert(!value.nil? && thtcb_projection_sha256(value) == expected_sha,
             "P3 THTCB closed projection drift: #{key}")
    end
  end

  def validate_thtcb_product_records!(root)
    contract_bytes = read_repo_identity!(
      root, THTCB_PRODUCT_CONTRACT, "P3 THTCB Product Task Contract"
    )
    contract = YAML.safe_load(
      contract_bytes, permitted_classes: [], permitted_symbols: [], aliases: false
    )
    assert(contract["schema_version"] == "p3-thtcb-product-task-contract/v1" &&
           contract["record_type"] == "sourcelens_aios_phase_delegated_product_task_contract" &&
           contract["task_id"] == THTCB_PRODUCT_TASK_ID && contract["phase"] == "P3" &&
           contract["route_id"] == THTCB_ROUTE_ID && contract["status"] == "ACTIVE" &&
           contract["kind"] == "PRODUCT_IMPLEMENTATION" &&
           contract.dig("authority", "founder_decision") ==
             THTCB_DECISION.merge("decision_id" => THTCB_DECISION_ID) &&
           contract.dig("authority", "activation_parent").slice("commit", "tree") ==
             THTCB_PRODUCT_ACTIVATION_PARENT &&
           contract.dig("authority", "authorization_id") == THTCB_PRODUCT_AUTHORIZATION_ID &&
           contract.dig("authority", "execution_nonce") == THTCB_PRODUCT_EXECUTION_NONCE &&
           contract.dig("action_algebra", "allowed") == ["SHA256_READ_ONLY_CUSTODY_V1"] &&
           contract.dig("scope", "worker_allowed_paths") == THTCB_PRODUCT_WORKER_PATHS &&
           contract.dig("scope", "master_control_paths") == THTCB_PRODUCT_MASTER_PATHS &&
           contract.dig("scope", "task_branch") == THTCB_PRODUCT_RESOURCES.fetch("branch") &&
           contract.dig("scope", "task_worktree") == THTCB_PRODUCT_RESOURCES.fetch("worktree") &&
           contract.dig("scope", "evidence_root") == THTCB_PRODUCT_RESOURCES.fetch("evidence_root") &&
           contract.dig("scope", "dependency_custody_root") ==
             THTCB_PRODUCT_RESOURCES.fetch("dependency_custody_root") &&
           contract["budget"].slice(*THTCB_PRODUCT_BUDGET.keys) == THTCB_PRODUCT_BUDGET &&
           contract.dig("lineage", "rejected_engineering_lineage_read") == false &&
           contract.dig("lineage", "rejected_engineering_lineage_compare") == false &&
           contract.dig("lineage", "rejected_engineering_lineage_copy") == false &&
           contract.dig("lineage", "rejected_engineering_lineage_execute") == false &&
           contract.dig("lineage", "rejected_engineering_lineage_repair_or_reuse") == false &&
           contract.dig("anti_loop", "candidate_3_allowed") == false &&
           contract.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           contract.dig("anti_loop", "third_review_cycle_allowed") == false &&
           contract.dig("anti_loop", "successor_or_replacement_allowed") == false,
           "P3 THTCB Product Contract semantic boundary drift")
    read_identity!(contract.fetch("accepted_input").fetch("task_gate_receipt"),
                   "P3 THTCB accepted P3-001 receipt")

    authority_bytes = read_identity!(
      THTCB_PRODUCT_AUTHORITY, "P3 THTCB Product Task authority", create_once: true
    )
    authority = JSON.parse(authority_bytes)
    assert(authority["schema_version"] == "p3-thtcb-phase-delegated-task-authority/v1" &&
           authority["record_type"] ==
             "SOURCELENS_AIOS_PHASE_DELEGATED_PRODUCT_TASK_AUTHORITY" &&
           authority["status"] == "AUTHORIZED_ACTIVE" && authority["phase"] == "P3" &&
           authority["route_id"] == THTCB_ROUTE_ID &&
           authority["task_id"] == THTCB_PRODUCT_TASK_ID &&
           authority["authorization_id"] == THTCB_PRODUCT_AUTHORIZATION_ID &&
           authority["execution_nonce"] == THTCB_PRODUCT_EXECUTION_NONCE &&
           authority["execution_nonce_status"] == "ACTIVE_SINGLE_USE" &&
           authority["founder_decision"] ==
             THTCB_DECISION.merge("decision_id" => THTCB_DECISION_ID) &&
           authority.fetch("activation_parent").slice("commit", "tree") ==
             THTCB_PRODUCT_ACTIVATION_PARENT && authority["contract"] == THTCB_PRODUCT_CONTRACT &&
           authority["resources"] == THTCB_PRODUCT_RESOURCES &&
           authority.dig("write_authority", "worker_allowed_repository_paths") ==
             THTCB_PRODUCT_WORKER_PATHS &&
           authority.dig("write_authority", "master_control_paths") ==
             THTCB_PRODUCT_MASTER_PATHS && authority["budget"] == THTCB_PRODUCT_BUDGET &&
           authority.dig("trusted_computing_base", "included") == THTCB_TCB &&
           authority.dig("external_effects", "docker", "authorized") == true &&
           authority.dig("external_effects", "jre17_custody_acquisition", "authorized") == true &&
           authority.dig("external_effects", "jre17_custody_acquisition",
                         "single_use_non_resettable") == true &&
           authority.dig("external_effects", "provider") == false &&
           authority.dig("external_effects", "secret") == false &&
           authority.dig("external_effects", "remote") == false &&
           authority.dig("external_effects", "production") == false &&
           authority.dig("external_effects", "public") == false &&
           authority.dig("external_effects", "p4_entry") == false &&
           authority.dig("lineage", "rejected_engineering_lineage_read") == false &&
           authority.dig("lineage", "rejected_engineering_lineage_compare") == false &&
           authority.dig("lineage", "rejected_engineering_lineage_copy") == false &&
           authority.dig("lineage", "rejected_engineering_lineage_execute") == false &&
           authority.dig("lineage", "rejected_engineering_lineage_repair_or_reuse") == false &&
           authority.dig("anti_loop", "candidate_3_allowed") == false &&
           authority.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           authority.dig("anti_loop", "third_review_cycle_allowed") == false &&
           authority.dig("anti_loop", "successor_or_replacement_allowed") == false &&
           authority.dig("lifecycle", "project_actual_completion") == false &&
           authority.dig("lifecycle", "long_term_goal_status") == "ACTIVE" &&
           authority.dig("lifecycle", "codex_goal_completion_authorized") == false,
           "P3 THTCB Product authority semantic boundary drift")
    assert(git!(root, "rev-parse", "#{THTCB_PRODUCT_ACTIVATION_PARENT.fetch('commit')}^{tree}") ==
             THTCB_PRODUCT_ACTIVATION_PARENT.fetch("tree"),
           "P3 THTCB Product activation-parent tree drift")
    _out, _err, ancestor = Open3.capture3(
      "git", "merge-base", "--is-ancestor",
      THTCB_PRODUCT_ACTIVATION_PARENT.fetch("commit"), "HEAD", chdir: root.to_s
    )
    assert(ancestor.success?, "P3 THTCB Product activation parent is not an ancestor of HEAD")
    [contract, authority]
  rescue JSON::ParserError => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 THTCB Product authority is not valid JSON: #{e.message}"
  end

  def validate_thtcb_product_active_route!(root, truth)
    root = Pathname.new(root).realpath
    assert(truth["record_type"] == "sourcelens_aios_current_truth",
           "P3 THTCB canonical Truth record type drift")
    decision = validate_thtcb_decision!(root, "PRODUCT_TASK_ACTIVE")
    baseline = load_thtcb_canonical_start_truth!(root)
    THTCB_HISTORICAL_PROJECTIONS.each do |historical_key, baseline_key|
      assert(truth[historical_key] == baseline[baseline_key],
             "P3 THTCB immutable historical projection drift: #{historical_key}")
    end
    constitution_bytes = read_repo_identity!(
      root, THTCB_CONSTITUTION, "P3 THTCB Strategic Constitution v3.1"
    )
    assert(constitution_bytes.include?("- Version: `3.1`") &&
           constitution_bytes.include?("`#{THTCB_STRICT_GATE_ID}`") &&
           constitution_bytes.include?("`TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION`"),
           "P3 THTCB Constitution semantic anchor drift")
    validate_thtcb_projection_set!(truth, THTCB_ACTIVE_PROJECTION_SHA256)
    validate_thtcb_product_records!(root)

    route = mapping(truth["current_phase_route"], "P3 THTCB current Route")
    expected_active_task = {
      "task_id" => THTCB_PRODUCT_TASK_ID,
      "contract" => THTCB_PRODUCT_CONTRACT,
      "authority" => THTCB_PRODUCT_AUTHORITY,
      "activation_parent" => THTCB_PRODUCT_ACTIVATION_PARENT,
      "authorization_id" => THTCB_PRODUCT_AUTHORIZATION_ID,
      "execution_nonce" => THTCB_PRODUCT_EXECUTION_NONCE,
      "resources" => THTCB_PRODUCT_RESOURCES,
      "budget" => THTCB_PRODUCT_BUDGET
    }
    assert(route["schema_version"] == THTCB_ROUTE_SCHEMA &&
           route["route_id"] == THTCB_ROUTE_ID && route["phase"] == "P3" &&
           route["status"] == "ACTIVE" && route["lifecycle_stage"] == "PRODUCT_TASK_ACTIVE" &&
           route["execution_status"] == "PRODUCT_TASK_ACTIVE" &&
           route["scheduling_status"] == "TASK_ENVELOPE_EXECUTION" &&
           route["next_eligible_action"] == THTCB_PRODUCT_ACTIVE_ACTION &&
           route["founder_route_decision"] == THTCB_DECISION.merge(
             "decision_id" => THTCB_DECISION_ID, "operation_type" => THTCB_OPERATION_TYPE,
             "source_body" => THTCB_AUTHORIZATION_BODY
           ) && route["constitution"] == THTCB_CONSTITUTION &&
           route["objective_id"] == "TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION" &&
           route["workflow_id"] == "SHA256_READ_ONLY_CUSTODY_V1" &&
           route.dig("strict_exit_gate", "gate_id") == THTCB_STRICT_GATE_ID &&
           route.dig("strict_exit_gate", "required_item_ids") == THTCB_STRICT_ITEMS &&
           route.dig("ordered_stages", 0, "task_id") == THTCB_PRODUCT_TASK_ID &&
           route.dig("ordered_stages", 0, "status") == "ACTIVE" &&
           route.dig("ordered_stages", 0, "budget") == THTCB_PRODUCT_BUDGET &&
           route.dig("ordered_stages", 1, "task_id") == THTCB_AUDIT_TASK_ID &&
           route.dig("ordered_stages", 1, "status") ==
             "LOCKED_PENDING_PRODUCT_ACCEPTED_AND_INTEGRATED" &&
           route.dig("ordered_stages", 1, "budget") == THTCB_AUDIT_BUDGET &&
           route["active_task"] == expected_active_task &&
           route.dig("anti_loop", "foundation_task_allowed") == false &&
           route.dig("anti_loop", "candidate_3_allowed") == false &&
           route.dig("anti_loop", "second_same_task_repair_allowed") == false &&
           route.dig("anti_loop", "third_review_cycle_allowed") == false &&
           route.dig("anti_loop", "successor_or_replacement_allowed") == false &&
           route.dig("anti_loop", "governance_progress_credit") == 0,
           "P3 THTCB active Product Route semantic projection drift")

    envelope = mapping(truth["phase_execution_envelope"], "P3 THTCB Phase envelope")
    assert(envelope["status"] == "ACTIVE_P3_THTCB_PRODUCT_TASK" &&
           envelope["consumed"] == decision.dig("route", "consumed_preserved") &&
           envelope["reserved"] == THTCB_PRODUCT_BUDGET.merge("task_id" => THTCB_PRODUCT_TASK_ID) &&
           envelope["remaining"] == {
             "engineering_tasks" => 1, "engineering_hours" => 16, "calendar_days" => 6
           } && envelope["remaining_capacity_usable"] == false &&
           envelope["remaining_capacity_lock_reason"] ==
             "ACTIVE_PRODUCT_RESERVATION_AUDIT_LOCKED" &&
           envelope["governance_progress_credit"] == 0,
           "P3 THTCB active Product envelope drift")
    control = mapping(truth["founder_escalation_control"],
                      "P3 THTCB Founder escalation control")
    assert(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
           control.dig("source_event", "kind") == "P3_THTCB_PRODUCT_TASK_ACTIVE" &&
           control.dig("reserved_trigger", "category") == "NONE" &&
           control["founder_decision_required"] == false &&
           control["next_action_owner"] == "MASTER_CEO_AGENT" &&
           control["next_eligible_action"] == THTCB_PRODUCT_ACTIVE_ACTION,
           "P3 THTCB active Product Founder interruption boundary drift")
    boundary = mapping(truth["phase_boundary"], "P3 THTCB Phase boundary")
    active = mapping(truth["active_work"], "P3 THTCB active work")
    assert(boundary["phase_execution_status"] == "ACTIVE_P3_THTCB_PRODUCT_TASK" &&
           boundary["task_creation_allowed"] == false &&
           boundary["task_creation_scope"] == "CURRENT_TASK_ONLY" &&
           boundary["allowed_task_kinds"] == ["PRODUCT_IMPLEMENTATION"] &&
           boundary["founder_decision_required"] == false &&
           boundary["next_eligible_action"] == THTCB_PRODUCT_ACTIVE_ACTION &&
           active["current_task"] == THTCB_PRODUCT_TASK_ID &&
           active["selected_task"] == THTCB_PRODUCT_TASK_ID &&
           active["current_task_status"] == "ACTIVE_IMPLEMENTATION" &&
           active["current_task_contract"] ==
             THTCB_PRODUCT_CONTRACT.slice("path", "sha256", "byte_length") &&
           active["authority_record"] ==
             THTCB_PRODUCT_AUTHORITY.slice("path", "sha256", "byte_length") &&
           active["execution_nonce"] == THTCB_PRODUCT_EXECUTION_NONCE &&
           active["execution_nonce_status"] == "ACTIVE_SINGLE_USE" &&
           active["authorization_id"] == THTCB_PRODUCT_AUTHORIZATION_ID &&
           active["activation_parent_commit"] == THTCB_PRODUCT_ACTIVATION_PARENT.fetch("commit") &&
           active["activation_parent_tree"] == THTCB_PRODUCT_ACTIVATION_PARENT.fetch("tree") &&
           active["task_resource_state"] == "ACTIVE_CREATED" &&
           active["task_branch"] == THTCB_PRODUCT_RESOURCES.fetch("branch") &&
           active["task_worktree"] == THTCB_PRODUCT_RESOURCES.fetch("worktree") &&
           active["execution_evidence_root"] == THTCB_PRODUCT_RESOURCES.fetch("evidence_root") &&
           active["dependency_custody_root"] ==
             THTCB_PRODUCT_RESOURCES.fetch("dependency_custody_root") &&
           active["allowlisted_paths"] == THTCB_PRODUCT_WORKER_PATHS &&
           active["current_task_budget"] == THTCB_PRODUCT_BUDGET &&
           active["next_stage_budget"] == THTCB_AUDIT_BUDGET &&
           active["founder_decision_required"] == false &&
           active["user_action_required"] == "NONE" &&
           active["next_eligible_action"] == THTCB_PRODUCT_ACTIVE_ACTION,
           "P3 THTCB active Product Task authority projection drift")
    p3 = mapping(truth.dig("strict_phase_gate_ledger", "phases", "P3"),
                 "P3 THTCB strict Exit Gate")
    assert(p3["status"] == "INCOMPLETE" &&
           p3.dig("current_exit_gate", "gate_id") == THTCB_STRICT_GATE_ID &&
           p3.dig("current_exit_gate", "required_item_ids") == THTCB_STRICT_ITEMS &&
           THTCB_STRICT_ITEMS.all? { |item_id|
             p3.dig("current_exit_gate", "required_items", item_id, "status") == "MISSING"
           } && p3.dig("founder_phase_gate", "status") ==
             "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
           "P3 THTCB active Product strict Exit Gate false acceptance")
    assert(truth.dig("project", "current_phase") == "P3" &&
           truth.dig("project", "phase_execution_status") == "ACTIVE_P3_THTCB_PRODUCT_TASK" &&
           truth.dig("project", "p3_execution_status") == "ACTIVE_THTCB_PRODUCT_TASK" &&
           truth.dig("project", "p4_entry_status") ==
             "HOLD_PENDING_STRICT_P3_EXIT_AND_SEPARATE_FOUNDER_PHASE_ENTRY" &&
           truth.dig("goal", "control_plane_status_observed") == "ACTIVE" &&
           truth.dig("goal", "current_task_authority") == THTCB_PRODUCT_TASK_ID &&
           truth.dig("goal", "current_strategic_decision", "decision_id") == THTCB_DECISION_ID &&
           truth.dig("phase_execution_claim", "current_task_claim") == THTCB_PRODUCT_TASK_ID &&
           truth.dig("phase_execution_claim", "real_engineering_progress") == 0 &&
           truth.dig("phase_execution_claim", "product_capability_changed") == false &&
           truth.dig("phase_execution_claim", "candidate_integration_allowed") == false &&
           truth.dig("claim_boundary", "p3_thtcb_route_stage") == "PRODUCT_TASK_ACTIVE" &&
           truth.dig("claim_boundary", "p3_thtcb_product_candidate_integrated") == false &&
           truth.dig("claim_boundary", "p3_thtcb_audit_unlocked") == false,
           "P3 THTCB active Product project, Goal or claim boundary drift")
    THTCB_PRODUCT_ACTIVE_STATE
  rescue ArgumentError, KeyError, TypeError, Psych::Exception => e
    raise P3FinalTransactionalRouteValidationError,
          "P3 THTCB active Product route invalid: #{e.message}"
  end

  def validate_truth!(root:, truth:, preactivation_resource_action: nil)
    if truth.dig("current_phase_route", "schema_version") == THTCB_ROUTE_SCHEMA
      lifecycle = truth.dig("current_phase_route", "lifecycle_stage")
      return validate_thtcb_installed_route!(root, truth) if
        lifecycle == "PRODUCT_ELIGIBLE_NOT_ACTIVATED"
      return validate_thtcb_product_active_route!(root, truth) if
        lifecycle == "PRODUCT_TASK_ACTIVE"
      raise P3FinalTransactionalRouteValidationError,
            "P3 THTCB lifecycle is not closed-schema: #{lifecycle.inspect}"
    end
    root = Pathname.new(root).realpath
    if truth.dig("current_phase_route", "schema_version") == TXC_ROUTE_SCHEMA
      return validate_txc_route!(root, truth)
    end
    if truth.dig("current_phase_route", "schema_version") == HPE_ROUTE_SCHEMA
      return validate_hpe_route!(
        root, truth, preactivation_resource_action: preactivation_resource_action
      )
    end
    if truth.dig("current_phase_route", "schema_version") == TIK_ROUTE_SCHEMA
      return validate_tik_route!(
        root, truth, preactivation_resource_action: preactivation_resource_action
      )
    end
    if truth.dig("current_phase_route", "schema_version") == HOST_AUTHORIZED_ROUTE_SCHEMA
      if truth.dig("current_phase_route", "lifecycle_stage") ==
         "FOUNDATION_TASK_TERMINAL_NON_PASS"
        return validate_host_authorized_foundation_terminal!(root, truth)
      end
      if truth.dig("current_phase_route", "lifecycle_stage") == "FOUNDATION_TASK_ACTIVE"
        return validate_host_authorized_foundation_active!(root, truth)
      end
      return validate_host_authorized_foundation_ready!(root, truth)
    end
    decision, decision_identity = validate_decision!(root)
    parent_truth = load_parent_truth!(root, decision)
    assert(truth["historical_p3_host_owned_fixed_state_workflow_phase_route"] ==
             parent_truth["current_phase_route"],
           "superseded P3 host-owned Route historical copy drift")

    route = mapping(truth["current_phase_route"], "current final transactional P3 Route")
    if route["lifecycle_stage"] == "PRODUCT_TASK_ACTIVE"
      return validate_active_task!(root, truth, decision, decision_identity, parent_truth, route)
    end
    if route["lifecycle_stage"] == "PRODUCT_TASK_TERMINAL_NON_PASS"
      return validate_terminal_task!(root, truth, decision, decision_identity, parent_truth, route)
    end
    if route["lifecycle_stage"] == "FOUNDER_RESOLVED_STRATEGIC_HOLD"
      return validate_strategic_hold!(root, truth, decision, decision_identity, parent_truth, route)
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
    if ARGV == ["--create-hpe-terminal-bundle-attestation"]
      identity = P3FinalTransactionalRouteValidation.create_hpe_terminal_bundle_attestation!(
        root: root, truth: truth
      )
      puts "P3_HPE_TERMINAL_BUNDLE_ATTESTATION: CREATED " \
           "verification_status=#{identity.fetch('verification_status')} " \
           "path=#{identity.fetch('path')} bytes=#{identity.fetch('byte_length')} " \
           "sha256=#{identity.fetch('sha256')}"
    elsif ARGV == ["--create-tik-terminal-bundle-attestation"]
      identity = P3FinalTransactionalRouteValidation.create_tik_terminal_bundle_attestation!(
        root: root, truth: truth
      )
      puts "P3_TIK_TERMINAL_BUNDLE_ATTESTATION: PASS " \
           "path=#{identity.fetch('path')} bytes=#{identity.fetch('byte_length')} " \
           "sha256=#{identity.fetch('sha256')}"
    elsif ARGV.empty?
      state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: truth)
      puts "P3_FINAL_TRANSACTIONAL_ROUTE: PASS state=#{state}"
    else
      raise P3FinalTransactionalRouteValidationError,
            "unsupported arguments; use no arguments, --create-hpe-terminal-bundle-attestation " \
            "or --create-tik-terminal-bundle-attestation"
    end
  rescue P3FinalTransactionalRouteValidationError, JSON::ParserError, Psych::SyntaxError => e
    warn "P3_FINAL_TRANSACTIONAL_ROUTE: NON_PASS #{e.message}"
    exit 1
  end
end

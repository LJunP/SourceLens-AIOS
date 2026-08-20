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
    assert(active["current_task"] == "NONE_ROUTE_TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
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
           execution["current_task_claim"] ==
             "NONE_ROUTE_TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
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
    assert(claim["current_task"] == "NONE_ROUTE_TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
           claim["selected_task"] == "NONE_ROUTE_TERMINAL_FOUNDATION_TASK_GATE_NON_PASS" &&
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
           goal["current_task_authority"] == "NONE_ROUTE_TERMINAL" &&
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

  def validate_truth!(root:, truth:)
    root = Pathname.new(root).realpath
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
    state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: truth)
    puts "P3_FINAL_TRANSACTIONAL_ROUTE: PASS state=#{state}"
  rescue P3FinalTransactionalRouteValidationError, JSON::ParserError, Psych::SyntaxError => e
    warn "P3_FINAL_TRANSACTIONAL_ROUTE: NON_PASS #{e.message}"
    exit 1
  end
end

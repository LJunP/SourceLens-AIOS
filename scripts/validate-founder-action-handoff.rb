#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "validate-p3-final-transactional-route"

module FounderActionHandoff
  ROOT = File.expand_path("..", __dir__)
  DEFAULT_TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
  RECOVERY_PLAN = "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml"
  SCHEMA_VERSION = "user-action-handoff/v1"
  ACTION_CLASSES = %w[NONE_CONTINUE AUTHORIZATION_REQUIRED MATERIAL_REQUIRED].freeze
  CURRENT_STATES = %w[COMPLETE CONTINUING WAITING_USER].freeze
  FOUNDER_TRIGGERS = %w[
    PHASE_ENTRY_OR_EXIT
    MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
    MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
    NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT
    IRREVERSIBLE_ASSET_REMOVAL
    MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT
    CRITICAL_RESIDUAL_RISK_ACCEPTANCE
  ].freeze
  PROJECT_AUTHORIZATION_VALUES = %w[YES NO NOT_APPLICABLE UNKNOWN].freeze
  APP_APPROVAL_VALUES = %w[YES NO UNKNOWN].freeze
  WRITE_VALUES = %w[YES NO NOT_APPLICABLE].freeze
  RECOMMENDED_DECISIONS = %w[APPROVE DENY DEFER].freeze
  FOUNDER_OPERATION_TYPES = %w[
    READ_ONLY_HTTPS_ACQUISITION
    READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL
    READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL
    READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL_REISSUE
    P2_BENCHMARK_SOURCE_FINAL_CANDIDATE_COMPLETION_ENVELOPE
    P2_RECOVERY_CLEAN_ROOM_RESEQUENCING_AND_MINIMAL_ENVELOPE_EXPANSION
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE
    P2_EXACT_FROZEN_P2_078_ONE_SHOT_FORMAL_HELD_ROUTE_UNLOCK
    P2_EXACT_FROZEN_P2_078_EVALUATION_AND_EVIDENCE_ADAPTER_PLUS_ONE_SHOT_FORMAL_HELD_SEQUENCE
    P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY
    P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_TERMINAL
    P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE_RESEQUENCING
    P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007
    P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_REBASELINE_AFTER_TIK_F1_TERMINAL
    P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY_AFTER_POSTINSTALL_PROTOCOL_ERROR
  ].freeze
  APP_OPERATION_TYPES = %w[APP_FILESYSTEM_BATCH_WRITE].freeze
  READ_ONLY_HTTPS_OPERATION = "一次全新、独立、clean-room V6 benchmark source acquisition"
  READ_ONLY_HTTPS_METHOD = "仅允许无凭据 HTTPS GET/HEAD"
  READ_ONLY_HTTPS_TARGETS = "github.com、api.github.com、codeload.github.com、raw.githubusercontent.com、repo.maven.apache.org、downloads.gradle.org、plugins.gradle.org、plugins-artifacts.gradle.org"
  READ_ONLY_HTTPS_BUDGET = "4,294,967,296 PROCESS_DELIVERED_TCP_STREAM_OCTETS"
  STANDARD_CURL_OPERATION_PATTERN = /\A一次全新、独立、clean-room (V[1-9][0-9]*) benchmark source acquisition using exact system curl\z/
  STANDARD_CURL_BUDGET = "4,294,967,296 CREATE_ONCE_PERSISTED_HTTP_RESPONSE_BODY_OCTETS"
  STANDARD_CURL_METRIC_EXCLUSIONS = "This budget does not cap or claim DNS, TLS, HTTP header, kernel, wire, or raw TCP octets"
  STANDARD_CURL_RETRY_POLICY = "Retries are disabled"
  STANDARD_CURL_IDENTITY_BINDING = "Exact system curl identity must be bound before the first network request"
  MILESTONE_CURL_OPERATION = "P2 benchmark-source admission milestone using exact system curl"
  MILESTONE_CURL_METHOD = "仅允许无凭据 HTTPS GET/HEAD；普通 acquisition Route NON_PASS 不消费本 milestone capability"
  MILESTONE_CURL_TOKEN = "AUTHORIZE_P2_BENCHMARK_SOURCE_ADMISSION_MILESTONE_STANDARD_CURL_CAPABILITY_V1"
  MILESTONE_CURL_DURATION = "Until P2 benchmark-source admission is ACCEPTED, the cumulative body budget is exhausted, Founder explicitly revokes the capability, or a terminal safety condition occurs"
  MILESTONE_CURL_BUDGET = "One non-resettable cumulative 4,294,967,296 CREATE_ONCE_PERSISTED_HTTP_RESPONSE_BODY_OCTETS ceiling shared across all independent Routes under this capability"
  MILESTONE_CURL_CONSUMPTION = "Ordinary Route NON_PASS does not consume this capability; the capability ends only on source-admission ACCEPTED, cumulative budget exhaustion, explicit Founder revocation, credential exposure, unauthorized write or external effect, or scope escape"
  MILESTONE_CURL_PASS = "PASS permits only create-once source-pack installation and activation of existing P2 recovery slot 1; it does not grant the 25% milestone"
  MILESTONE_CURL_NON_PASS = "Ordinary Route NON_PASS preserves this capability and returns control to Master for an independent Phase-local route; credential exposure, unauthorized write or external effect, or scope escape terminates the capability without automatic successor authorization"
  MILESTONE_CURL_REISSUE_OPERATION = "P2 benchmark-source admission milestone capability reissue after exact terminal safety event using exact system curl"
  MILESTONE_CURL_REISSUE_METHOD = "仅允许无凭据 HTTPS GET/HEAD；普通 independent acquisition Route NON_PASS 不消费本 reissued milestone capability；Maven、Gradle、Git、浏览器及其他子进程永久禁止直接联网"
  MILESTONE_CURL_REISSUE_TOKEN = "AUTHORIZE_P2_BENCHMARK_SOURCE_ADMISSION_MILESTONE_STANDARD_CURL_CAPABILITY_REISSUE_V2"
  MILESTONE_CURL_REISSUE_DURATION = "From direct Founder approval until P2 benchmark-source admission is ACCEPTED, the inherited cumulative body budget is exhausted, Founder explicitly revokes the capability, or a terminal safety condition occurs"
  MILESTONE_CURL_REISSUE_BUDGET = "One inherited non-resettable cumulative 4,294,967,296 CREATE_ONCE_PERSISTED_HTTP_RESPONSE_BODY_OCTETS ceiling shared across original capability V1 and this reissue V2; prior success, failure, ambiguity, outstanding reservations and ordinals remain consumed and cannot be reset"
  MILESTONE_CURL_REISSUE_CONSUMPTION = "Ordinary Route NON_PASS does not consume this reissued capability; it ends only on source-admission ACCEPTED, inherited cumulative budget exhaustion, explicit Founder revocation, credential exposure, unauthorized write or external effect, scope escape, or direct network access by Maven, Gradle, Git, browser, or any non-curl subprocess"
  MILESTONE_CURL_REISSUE_PASS = "PASS permits only create-once source-pack installation and activation of existing P2 recovery slot 1; it does not grant the 25% milestone"
  MILESTONE_CURL_REISSUE_NON_PASS = "Ordinary independent Route NON_PASS preserves this reissued capability and returns control to Master for another independent Phase-local route without a new Founder request; any terminal safety condition ends it without automatic successor authorization"
  FINAL_CANDIDATE_COMPLETION_OPERATION = "Complete P2 benchmark-source admission by using repository ordinals 31..48 and issue/PR ordinals 61..96 to find one new public nonfork JDK17-compatible Java repository with exactly two merged bug-fix PR tasks"
  FINAL_CANDIDATE_COMPLETION_METHOD = "Use only the existing exact standard-curl 8-host GET/HEAD network boundary; stop candidate search immediately after one two-task repository closes every pre-freeze gate"
  FINAL_CANDIDATE_COMPLETION_TOKEN = "AUTHORIZE_P2_BENCHMARK_SOURCE_ADMISSION_FINAL_CANDIDATE_COMPLETION_ENVELOPE_V1"
  FINAL_CANDIDATE_COMPLETION_DURATION = "Until exactly one replacement final candidate reaches a terminal admission/review result, the added ordinals are exhausted, the expanded cumulative body ceiling is exhausted, Founder explicitly revokes the envelope, or a terminal safety condition occurs"
  FINAL_CANDIDATE_COMPLETION_BUDGET = "Expand the same non-resettable cumulative body ceiling from 4,294,967,296 to 5,368,709,120 CREATE_ONCE_PERSISTED_HTTP_RESPONSE_BODY_OCTETS; inherit SUCCESS actual=849,647,528, FAILURE/AMBIGUOUS=3,277,324,220 and outstanding=0, yielding available=1,241,737,372; no refund, reset or second expansion"
  FINAL_CANDIDATE_COMPLETION_CONSUMPTION = "This envelope is consumed by one replacement final candidate or exhaustion of repository ordinals 31..48, issue/PR ordinals 61..96, or the expanded cumulative body ceiling; it authorizes no second replacement, further ordinal expansion, fresh budget, or automatic execution of a successor"
  FINAL_CANDIDATE_COMPLETION_PASS = "PASS permits only installation of the accepted DEV public and HELD custody source packs and activation of existing P2 recovery slot 1; it does not grant the 25% milestone, formal benchmark, product mutation or P3"
  FINAL_CANDIDATE_COMPLETION_NON_PASS = "NON_PASS ends only this completion envelope and preserves exact terminal Evidence; P2, SourceLens and the long-term Goal remain active, P3 remains HOLD, source admission remains false and progress contribution remains 0; the mandatory next-step copy-ready handoff is still delivered even though no successor may be executed without direct Founder approval"
  RECOVERY_RESEQUENCE_TOKEN = "AUTHORIZE_P2_CLEAN_ROOM_RECOVERY_RESEQUENCING_AND_MINIMAL_ENVELOPE_EXPANSION_V1"
  RECOVERY_RESEQUENCE_OPERATION = "Supersede only the unused slot-2 and slot-3 scheduling projection from P2_VALUE_FIRST_RECOVERY_ENVELOPE_EXPANSION_DECISION_V1 with one new clean-room three-stage sequence: independent benchmark foundation, product selector DEV, then formal HELD evaluation"
  RECOVERY_RESEQUENCE_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 15 engineering tasks, 432 engineering hours and 108 calendar days to 16 engineering tasks, 464 engineering hours and 116 calendar days; preserve consumed 13 tasks, 368 hours and 92 days, leaving exactly 3 tasks, 96 hours and 24 days for the new sequence"
  RECOVERY_RESEQUENCE_ORDER = "Require independent acceptance of P2_RECOVERY_BASELINE_ACCEPTED before product DEV activation, and independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before one formal HELD evaluation; no milestone receives credit before its own independent acceptance"
  RECOVERY_RESEQUENCE_LINEAGE = "Preserve P2-068 only as closed terminal accounting and prohibit reading, comparing, copying or reusing its rejected branch, worktree, code, benchmark implementation or engineering Evidence in the new benchmark-foundation Task"
  RECOVERY_RESEQUENCE_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  RECOVERY_RESEQUENCE_DURATION = "Until the P2 Exit Gate is ACCEPTED, the exact 3-task 96-hour 24-day executable remainder is exhausted, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  RECOVERY_RESEQUENCE_CONSUMPTION = "The envelope is non-resettable: each activated Task consumes exactly one 32-hour 8-day slot; a Task NON_PASS consumes that slot, unlocks no replacement or automatic successor, and any further scope requires a new exact Founder decision"
  RECOVERY_RESEQUENCE_PASS = "Benchmark-foundation PASS unlocks only product DEV; product DEV PASS unlocks only one formal HELD evaluation; formal HELD completion may establish Phase-Gate eligibility but does not itself authorize P3 entry or close the long-term Goal"
  RECOVERY_RESEQUENCE_NON_PASS = "Any Task NON_PASS preserves its exact terminal Evidence, consumes its slot, leaves dependent slots locked, creates no replacement or remediation chain, keeps P2 and the long-term Goal active with P3 HOLD, and contributes zero P2 progress"
  PRODUCT_SELECTOR_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_RECOVERY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V1"
  PRODUCT_SELECTOR_RECOVERY_OPERATION = "Add exactly one clean-room independent Product Selector DEV recovery slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070 only as closed terminal accounting"
  PRODUCT_SELECTOR_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_RECOVERY_DURATION = "Until the new independent Product Selector DEV Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 16 engineering tasks, 464 engineering hours and 116 calendar days to 17 engineering tasks, 496 engineering hours and 124 calendar days; preserve consumed 15 tasks, 432 hours and 108 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one new Product Selector DEV slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_RECOVERY_CONSUMPTION = "The new Product Selector DEV Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot and creates no replacement, remediation chain or automatic successor"
  PRODUCT_SELECTOR_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the new slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement or automatic successor, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE_V2"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_OPERATION = "Add exactly one final clean-room independent Product Selector DEV execution-integrity recovery slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070/P2-071 only as closed terminal accounting"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070 or P2-071 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_PREFLIGHT = "Before any Worker write, freeze and mechanically validate one execution envelope: every compiler, test, replay and negative-fixture write stays inside the exact Task worktree or Evidence root; exact Git source-to-class, JDK, classpath, sandbox-exec outer argv, cwd, closed environment, exit, stdout, stderr, Surefire and fixture inventories are create-once bound; any failure terminates before product execution"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_DURATION = "Until the new independent Product Selector DEV Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 17 engineering tasks, 496 engineering hours and 124 calendar days to 18 engineering tasks, 528 engineering hours and 132 calendar days; preserve consumed 16 tasks, 464 hours and 116 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one new Product Selector DEV execution-integrity slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_CONSUMPTION = "The new Product Selector DEV Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot and creates no replacement, remediation chain or automatic successor"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_INTEGRITY_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the new slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement or automatic successor, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  PRODUCT_SELECTOR_STREAM_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V3"
  PRODUCT_SELECTOR_STREAM_RECOVERY_OPERATION = "Add exactly one new clean-room independent Product Selector DEV sandbox-stream-lifecycle recovery slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070/P2-071/P2-072 only as closed terminal accounting"
  PRODUCT_SELECTOR_STREAM_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_STREAM_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070, P2-071 or P2-072 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_STREAM_RECOVERY_PREFLIGHT = "Before any Worker product-source write, freeze and mechanically validate one exact sandbox-stream lifecycle probe under the exact macOS sandbox profile: Node must spawn the exact JDK 17 bridge, write the bound stdin payload, signal EOF, receive the bound stdout result, retain stderr, and observe normal exit without closing System.in, System.out or System.err; bind exact sandbox-exec outer argv, cwd, closed environment, classpath and stream transcript; any failure terminates before product execution"
  PRODUCT_SELECTOR_STREAM_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_STREAM_RECOVERY_DURATION = "Until the new independent Product Selector DEV Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_STREAM_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 18 engineering tasks, 528 engineering hours and 132 calendar days to 19 engineering tasks, 560 engineering hours and 140 calendar days; preserve consumed 17 tasks, 496 hours and 124 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one new Product Selector DEV sandbox-stream-lifecycle slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_STREAM_RECOVERY_CONSUMPTION = "The new Product Selector DEV Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot and creates no replacement, remediation chain or automatic successor"
  PRODUCT_SELECTOR_STREAM_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_STREAM_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the new slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement or automatic successor, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V4"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_OPERATION = "Add exactly one final clean-room independent Product Selector DEV product-path-and-evidence-closure slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070/P2-071/P2-072/P2-073 only as closed terminal accounting"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070, P2-071, P2-072 or P2-073 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_PREFLIGHT = "Before any Worker product-source write, freeze and mechanically validate one exact closure envelope: one production-owned selection API used by the canonical CodeQaRetrievalService and the evaluator must own ranking, top-k 10, the 131072-byte UTF-8 budget and normalized-path-first tie-breaking; exact authority-bound worktree and Evidence roots must be verified before any mkdir and enforced by OS-level write confinement; compiler, Surefire, replay and negative transactions must use fresh roots, explicit closed classpath/sourcepath, disabled or fully bound processors, exact runtime binary and complete source-to-class identities; the reviewer manifest must directly bind DEV task cards, B1 results, DEV/HELD non-overlap proof, Surefire XML and stdout, per-run write/post-state inventories and every negative pre/post state; any failure terminates before product execution"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_DURATION = "Until the new independent Product Selector DEV Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 19 engineering tasks, 560 engineering hours and 140 calendar days to 20 engineering tasks, 592 engineering hours and 148 calendar days; preserve consumed 18 tasks, 528 hours and 132 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one new Product Selector DEV product-path-and-evidence-closure slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_CONSUMPTION = "The new Product Selector DEV Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot and creates no replacement, remediation chain or automatic successor"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_CLOSURE_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the new slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement or automatic successor, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE_V5"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_OPERATION = "Add exactly one clean-room independent Product Selector DEV query-entity-coverage architecture-pivot slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070/P2-071/P2-072/P2-073/P2-074 only as closed terminal accounting"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070, P2-071, P2-072, P2-073 or P2-074 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_ARCHITECTURE = "Before any Worker product-source write, freeze one independently authored materially different selector architecture based on deterministic query intent, package/type/member entity coverage and normalized-path-first budgeted selection; it must use the canonical product path and accepted P2-069 DEV cards without reading rejected implementations, must not open HELD, and must preserve the already validated authority, OS write confinement, fresh compiler and Surefire roots, explicit runtime identities and reviewer Evidence closure requirements"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_DURATION = "Until the new independent Product Selector DEV architecture-pivot Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 20 engineering tasks, 592 engineering hours and 148 calendar days to 21 engineering tasks, 624 engineering hours and 156 calendar days; preserve consumed 19 tasks, 560 hours and 140 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one new Product Selector DEV architecture-pivot slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_CONSUMPTION = "The new Product Selector DEV architecture-pivot Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot and creates no replacement, remediation chain or automatic successor"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_PIVOT_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the new slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement or automatic successor, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE_V6"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_OPERATION = "Add exactly one clean-room independent Product Selector DEV B1-anchored graph-fusion slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070/P2-071/P2-072/P2-073/P2-074/P2-075 only as closed terminal accounting"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070, P2-071, P2-072, P2-073, P2-074 or P2-075 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and source pack, and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_ARCHITECTURE = "Before any Worker product-source write, freeze one independently authored B1-anchored graph-fusion architecture: reproduce the accepted P2-069 B1 lexical seed ranking from accepted inputs, build a product-owned static Java package/type/member/import/reference graph from candidate source, and fuse lexical plus one-hop structural ranks using no more than two predeclared deterministic candidate parameter sets; enforce normalized-path-first ties, top-k 10 and the 131072-byte UTF-8 budget; prohibit task-specific oracle branches, post-result tuning and every HELD read; require exact B1-seed parity, authority, OS write confinement, fresh compiler and Surefire roots, runtime identities and reviewer Evidence closure before product execution"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_ACCEPTANCE = "The DEV Task may PASS only if one exact candidate independently and simultaneously exceeds the accepted P2-069 B1 macro precision 0.15595238095238093, macro recall 0.8958333333333334 and macro MRR 0.8229166666666666, has zero per-task recall regressions, passes product tests and replay, and receives independent Task Gate acceptance; otherwise it is NON_PASS without HELD access"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_DURATION = "Until the new independent Product Selector DEV B1-anchored graph-fusion Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 21 engineering tasks, 624 engineering hours and 156 calendar days to 22 engineering tasks, 656 engineering hours and 164 calendar days; preserve consumed 20 tasks, 592 hours and 148 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one new Product Selector DEV B1-anchored graph-fusion slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_CONSUMPTION = "The new Product Selector DEV B1-anchored graph-fusion Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot and creates no replacement, remediation chain or automatic successor"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the new slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement or automatic successor, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE_V7"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_OPERATION = "Add exactly one clean-room independent Product Selector DEV semantic-symbol-impact-cone slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070/P2-071/P2-072/P2-073/P2-074/P2-075/P2-076 only as closed terminal accounting"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070, P2-071, P2-072, P2-073, P2-074, P2-075 or P2-076 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and source pack, and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_ARCHITECTURE = "Before any Worker product-source write, freeze one independently authored semantic-symbol-impact-cone architecture: use deterministic product-owned Java source analysis to resolve package/type/member ownership plus import, invocation, inheritance and reference edges from accepted source bytes; seed bounded forward and backward impact cones only from the query and B1 lexical candidates; select under normalized-path-first ties, top-k 10 and the 131072-byte UTF-8 budget using no more than two predeclared deterministic parameter sets; prohibit DEV oracle labels as implementation inputs, task-specific branches, post-result tuning and every HELD read; require exact B1-seed parity, authority, OS write confinement, fresh compiler and Surefire roots, runtime identities and reviewer Evidence closure before product execution"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_ACCEPTANCE = "The DEV Task may PASS only if one exact candidate independently and simultaneously exceeds the accepted P2-069 B1 macro precision 0.15595238095238093, macro recall 0.8958333333333334 and macro MRR 0.8229166666666666, has zero per-task recall regressions, passes product tests and replay, and receives independent Task Gate acceptance; otherwise it is NON_PASS without HELD access"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote, production, public release, deletion, database modification, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_DURATION = "Until the new independent Product Selector DEV semantic-symbol-impact-cone Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 22 engineering tasks, 656 engineering hours and 164 calendar days to 23 engineering tasks, 688 engineering hours and 172 calendar days; preserve consumed 21 tasks, 624 hours and 156 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one new Product Selector DEV semantic-symbol-impact-cone slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_CONSUMPTION = "The new Product Selector DEV semantic-symbol-impact-cone Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot and creates no replacement, remediation chain or automatic successor"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the new slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement, remediation chain, automatic successor or automatic request for another heuristic retry, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_TOKEN = "AUTHORIZE_P2_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE_V8"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_OPERATION = "Add exactly one final clean-room independent Product Selector DEV JDK17 scan-time compiler-attributed persisted-graph slot before the existing locked formal HELD slot; preserve the accepted P2-069 baseline and P2-070/P2-071/P2-072/P2-073/P2-074/P2-075/P2-076/P2-077 only as closed terminal accounting"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_ORDER = "Require independent acceptance of P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED before the existing formal HELD slot unlocks; no milestone receives credit before its own independent acceptance"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_LINEAGE = "Prohibit reading, comparing, copying or reusing the rejected P2-070, P2-071, P2-072, P2-073, P2-074, P2-075, P2-076 or P2-077 branch, worktree, code, evaluator implementation or engineering Evidence as implementation input; use only canonical main, the accepted P2-069 baseline and source pack, and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_ARCHITECTURE = "Before any Worker product-source write, freeze one independently authored non-regex production architecture whose only attribution boundary is the existing full-source scan path: AnalysisService must pass complete normalized Java compilation units from the authority-bound repository root to a product-owned JDK17 graph builder using only the public JavaCompiler, JavacTask, Trees and Elements APIs; the builder must persist declaration-proven package/type/member ownership and resolved Element-to-Element import, invocation, inheritance and reference edges through CodeGraphPersistenceService; persistence integration proof must use only a fresh process-local H2 in-memory test database under the bound test profile and must prove that no existing or operational datasource is reachable; the real CodeQaController and CodeQaRetrievalService path, and the DEV evaluator through that same production selection API, must consume only the persisted graph plus accepted CodeChunk records, never compile or reconstruct candidate chunks at query time and never use a benchmark-only bridge; prohibit simple-name broadcast, reference sites as owners and unresolved or ambiguous edges; begin from the exact accepted B1 ranking and permit only deterministic graph-attributed substitutions under normalized-path-first ties, top-k 10 and the 131072-byte UTF-8 budget using no more than two predeclared parameter sets; prohibit DEV oracle labels, task IDs, task-specific branches, post-result tuning and every HELD read; require exact full-source-to-persisted-graph identity, graph-to-selected-chunk traceability, B1 parity, authority, AF_INET and AF_INET6 deny-network probes, OS write confinement, fresh compiler and Surefire roots, complete source-to-class and per-replay sandbox/write inventories, real evaluator-bound HELD/oracle negatives and reviewer Evidence closure before product execution"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_ACCEPTANCE = "The DEV Task may PASS only if one exact candidate independently and simultaneously exceeds the accepted P2-069 B1 macro precision 0.15595238095238093, macro recall 0.8958333333333334 and macro MRR 0.8229166666666666, has zero per-task recall regressions, passes product tests and two byte-exact sandboxed replays, and receives independent CTO, Security and Quality/Evaluation Task Gate acceptance; otherwise it is NON_PASS without HELD access"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_TARGET = "Local SourceLens canonical main, one future active Task branch and worktree, create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit, and one fresh process-local H2 in-memory test database that is destroyed at process exit; no connection to or modification of any existing, user, canonical, Codex-control-plane or operational database; no network, Provider, Secret, remote, production, public release, deletion, P3 entry or long-term Goal termination"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_DURATION = "Until the new independent Product Selector DEV JDK17 scan-time compiler-attributed persisted-graph Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this envelope, or a terminal safety condition occurs"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 23 engineering tasks, 688 engineering hours and 172 calendar days to 24 engineering tasks, 720 engineering hours and 180 calendar days; preserve consumed 22 tasks, 656 hours and 164 days, leaving exactly 2 tasks, 64 hours and 16 days in order: one final Product Selector DEV JDK17 scan-time compiler-attributed persisted-graph slot, then the existing formal HELD slot"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_CONSUMPTION = "The new Product Selector DEV Task consumes exactly one 32-hour 8-day slot; the existing formal HELD slot remains locked until Product Selector DEV is independently ACCEPTED; Product DEV NON_PASS consumes the new slot, creates no replacement, remediation chain or automatic successor, and forbids another Product DEV retry request under the unchanged acceptance Gate; any further Founder handoff must be a Phase route, objective or Exit-Gate strategy decision"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_PASS = "Product Selector DEV PASS establishes only P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED, raises delivery progress to 70% and unlocks only the existing formal HELD evaluation slot; strict P2 Exit progress remains 0% until the Exit Gate is independently ACCEPTED, and neither P3 entry nor long-term Goal closure is authorized"
  PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_NON_PASS = "Product Selector DEV NON_PASS preserves exact terminal Evidence, consumes the final Product DEV slot, leaves formal HELD locked, keeps P2 delivery progress at 25% and strict progress at 0%, creates no replacement, remediation chain, automatic successor or further Product DEV retry authorization handoff under the unchanged Gate, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  P2_078_PARETO_RESIDUAL_ADMISSION_TOKEN = "AUTHORIZE_P2_EXACT_FROZEN_P2_078_ONE_SHOT_FORMAL_HELD_ROUTE_UNLOCK_V1"
  P2_078_PARETO_RESIDUAL_ADMISSION_OPERATION = "Supersede only the Product Selector DEV milestone prerequisite for the existing formal HELD slot with one exact immutable P2-078 candidate preactivation and one-shot formal HELD route; add no Task slot, implementation attempt, parameter set or Phase budget"
  P2_078_PARETO_RESIDUAL_ADMISSION_PERMISSION = "Permit reading and executing only frozen candidate e0c0f4d78b64b95b359746ab7c2fec4beed4311f tree 405bd708c7e724b792c37b9eb568e492cb94c70d and its manifest-bound P2-078 Evidence for preactivation, formal HELD evaluation and PASS-only byte-exact integration; override rejected-lineage access only for this exact candidate, with no code, evaluator, dataset, split, oracle, metric, threshold, ranking, parameter or DEV result mutation and no DEV rerun"
  P2_078_PARETO_RESIDUAL_ADMISSION_CRITERION = "Disclose that P2-078 remains terminal NON_PASS because DEV precision and recall equal rather than strictly exceed B1 while MRR strictly improves and per-task recall has zero regression; do not retroactively PASS that Task or change the P2 Exit Gate, and determine capability only through the original preregistered one-shot formal HELD criterion"
  P2_078_PARETO_RESIDUAL_ADMISSION_REVIEW = "Before any HELD read, require independent candidate identity, raw Evidence, product correctness, authority, source-to-class provenance, replay and closed-environment preactivation PASS; any blocker or identity drift is terminal NON_PASS with zero HELD reads and no successor"
  P2_078_PARETO_RESIDUAL_ADMISSION_ORDER = "Use only the existing P2_RECOVERY_CAPACITY_SLOT_V2_3: preactivation occurs inside that formal HELD Task before opening HELD; preactivation PASS permits exactly one formal HELD dispatch, while formal HELD PASS permits only byte-exact candidate integration and P2 Exit-Gate eligibility"
  P2_078_PARETO_RESIDUAL_ADMISSION_TARGET = "Local SourceLens canonical main, exact frozen P2-078 candidate branch and worktree, manifest-bound P2-078 Evidence under /Users/lijunpeng/Developer/.sourcelens-audit, and the existing formal HELD slot; no network, Provider, Secret, remote, production, public release, deletion, database modification, new product implementation, new Task capacity, P3 entry or long-term Goal termination"
  P2_078_PARETO_RESIDUAL_ADMISSION_DURATION = "Until the existing formal HELD slot reaches PASS or NON_PASS, Founder explicitly revokes this route, or a terminal safety condition occurs"
  P2_078_PARETO_RESIDUAL_ADMISSION_BUDGET = "No Phase envelope expansion: preserve the 24-Task, 720-engineering-hour and 180-calendar-day limits, consumed 23 Tasks, 688 hours and 172 days, and use only the existing final 1-Task, 32-hour, 8-day formal HELD slot"
  P2_078_PARETO_RESIDUAL_ADMISSION_RISK = "The material risk is post-result selection of one DEV Pareto candidate and exact access to rejected candidate bytes; it is bounded by immutable candidate and Evidence identities, an explicit non-PASS history, zero implementation or retuning, preactivation before HELD, one untouched HELD dispatch and unchanged Exit-Gate criteria"
  P2_078_PARETO_RESIDUAL_ADMISSION_DENY = "Do not create a Task, read the frozen candidate or open HELD; create no Product DEV successor; P2 delivery remains 25%, strict progress remains 0%, P2 and the long-term Goal remain active, and P3 remains HOLD"
  P2_078_PARETO_RESIDUAL_ADMISSION_CONSUMPTION = "The existing formal HELD Task consumes the final 32-hour 8-day slot whether preactivation or formal evaluation PASSes or NON_PASSes; it authorizes no product mutation, DEV rerun, second candidate, replacement, remediation chain or automatic successor"
  P2_078_PARETO_RESIDUAL_ADMISSION_PASS = "Formal HELD PASS permits byte-exact integration of only the frozen P2-078 candidate, accepts K1 and K2, and makes the unchanged P2 Exit Gate eligible for independent acceptance and Founder Phase Gate; it does not itself authorize P3 entry or long-term Goal closure"
  P2_078_PARETO_RESIDUAL_ADMISSION_NON_PASS = "Preactivation or formal HELD NON_PASS preserves exact terminal Evidence, consumes the existing final slot, integrates nothing, keeps strict P2 progress at 0% and the implementation freeze active, creates no replacement or automatic successor, keeps P2 and the long-term Goal active, and keeps P3 HOLD"
  P2_EVALUATION_ADAPTER_TOKEN = "AUTHORIZE_P2_EXACT_FROZEN_P2_078_EVALUATION_AND_EVIDENCE_ADAPTER_PLUS_ONE_SHOT_FORMAL_HELD_SEQUENCE_V1"
  P2_EVALUATION_ADAPTER_OPERATION = "Add exactly two ordered Tasks after terminal P2-079: one evaluation-and-Evidence adapter Task for the exact frozen P2-078 candidate, followed only after independent adapter acceptance by one immutable-candidate one-shot formal HELD Task; add no Product DEV implementation attempt"
  P2_EVALUATION_ADAPTER_PERMISSION = "Permit exact P2-078 candidate commit e0c0f4d78b64b95b359746ab7c2fec4beed4311f tree 405bd708c7e724b792c37b9eb568e492cb94c70d and its manifest-bound Evidence as read-only execution input while preserving P2-078 and P2-079 as terminal NON_PASS; permit new evaluator-adapter source only under evaluation-harness, with no product-source mutation, candidate retuning, dataset, split, oracle, metric, threshold, ranking or parameter mutation"
  P2_EVALUATION_ADAPTER_PREFLIGHT = "Before any HELD read, independently author and mechanically validate on canonical main one split-neutral evaluator adapter that accepts explicit task-card input without hard-coded DEV cardinality or DEV-only paths; prove the frozen 8-card DEV and 4-card HELD schemas using only non-HELD synthetic fixtures, exact authority-bound roots, closed runtime identities, sandboxed write confinement and create-once Evidence"
  P2_EVALUATION_ADAPTER_EVIDENCE = "Within the same adapter Task and without modifying old Evidence, extract only historical Git blob 838fb82bec44fccd9d3eec1d732d0358c5060633 from commit 5d75f146db21da0e05b5bd5b47ed23e096dd162d and blob 43ac4a9a1a30dc8b1441acccc9e0f79f3d3b20d6 from commit 5733350eace33556254d2a25be075d184f4d2383, verify their preregistered byte lengths and SHA-256 identities, install them create-once under the new stable Evidence root, and build a new relative-path manifest that independently reaches 166 of 166 exact leaves; historical path drift remains disclosed and is never rewritten as an old-manifest PASS"
  P2_EVALUATION_ADAPTER_COMPATIBILITY = "After the adapter is frozen and before HELD access, permit exactly one non-selective DEV compatibility replay against the accepted P2-069 eight DEV cards and exact P2-078 candidate; it must byte-exact reproduce the already recorded P2-078 DEV task outputs and aggregates, cannot change candidate or adapter after observing results, and any mismatch is terminal NON_PASS with zero HELD reads"
  P2_EVALUATION_ADAPTER_FORMAL = "Adapter Task PASS freezes and may integrate only the evaluator adapter, then unlocks exactly one formal HELD Task; before the first HELD read freeze the exact candidate, adapter, dataset, split, oracle, metric, threshold, ranking, parameters, commands and Evidence, then execute exactly one untouched four-task HELD dispatch with no mutation, retuning, replacement, second candidate or rerun"
  P2_EVALUATION_ADAPTER_TARGET = "Local SourceLens canonical main, exact frozen P2-078 candidate and manifest-bound Evidence, exact two declared historical Git commits and blobs, accepted P2-069 baseline and source pack, at most one active Task branch and worktree at a time, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote write, production, public release, deletion, existing database modification, P3 entry or long-term Goal termination"
  P2_EVALUATION_ADAPTER_DURATION = "Until the unchanged P2 Exit Gate is independently ACCEPTED, either of the exact two Tasks reaches terminal NON_PASS, Founder explicitly revokes this route, or a terminal safety condition occurs"
  P2_EVALUATION_ADAPTER_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 24 engineering tasks, 720 engineering hours and 180 calendar days to 26 engineering tasks, 784 engineering hours and 196 calendar days; preserve consumed 24 tasks, 720 hours and 180 days, leaving exactly two 32-hour 8-day slots and no other P2 capacity"
  P2_EVALUATION_ADAPTER_RISK = "The material risks are read-only execution of one terminal candidate, one new evaluator adapter, content-addressed rebinding of two exact historical blobs and 64 engineering hours of added capacity; risk is bounded by immutable product bytes, no overwrite of old Evidence, byte-exact DEV compatibility, zero pre-PASS HELD reads, one formal dispatch and an unchanged Exit Gate, and the expansion is reversible only before the first new Task is activated"
  P2_EVALUATION_ADAPTER_DENY = "Do not create a new Task, read P2-078 rejected bytes or read HELD; keep P2 delivery at 25 percent, strict P2 progress at 0 percent, P2 and the long-term Goal active, P3 HOLD, and all P2-070 through P2-079 terminal facts immutable"
  P2_EVALUATION_ADAPTER_CONSUMPTION = "Each activated Task consumes exactly one 32-hour 8-day slot; adapter NON_PASS leaves formal HELD locked, formal HELD NON_PASS integrates no product candidate, either NON_PASS ends this route, and neither outcome creates a replacement, remediation chain, automatic successor or another Product DEV attempt"
  P2_EVALUATION_ADAPTER_PASS = "Adapter Task PASS permits integration of only the split-neutral evaluator adapter and unlocks one formal HELD Task with zero delivery or strict progress credit; formal HELD PASS permits byte-exact integration of only the frozen P2-078 product candidate, accepts the candidate-admission and formal-HELD delivery nodes, and makes the unchanged P2 Exit Gate eligible for independent acceptance, but does not authorize P3 entry or long-term Goal closure"
  P2_EVALUATION_ADAPTER_NON_PASS = "Any NON_PASS preserves exact terminal Evidence, contributes zero strict P2 progress, integrates no product candidate, keeps P2 and the long-term Goal active and P3 HOLD, and requires a new Founder Phase strategy decision rather than an automatic retry"
  P3_PHASE_ENTRY_TOKEN = "AUTHORIZE_P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY_V1"
  P3_PHASE_ENTRY_OPERATION = "Authorize P3 Phase entry for Single-Agent Runtime plus Minimum Trust under Strategic Constitution v2.4, with the Phase objective limited to a durable planner, executor, tool, state and checkpoint loop and the unchanged Exit evidence limited to resume, isolation, permission and trace tests"
  P3_PHASE_ENTRY_DELEGATION = "Permit Master to autonomously select, activate, implement, repair, independently review and locally integrate one bounded P3 Task at a time inside the Phase envelope; Founder is not asked for ordinary Task, file, command, branch, worktree, test, Evidence or Task-Gate approvals"
  P3_PHASE_ENTRY_ORDER = "Require value-first milestones in order: durable state and checkpoint resume, capability-scoped tool and permission enforcement, bounded isolated execution with complete observable traces, then independent P3 Exit-Gate audit; no milestone receives credit before independent acceptance"
  P3_PHASE_ENTRY_TARGET = "Local SourceLens canonical main, at most one active P3 Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote write, production, public release, irreversible deletion, database mutation outside fresh Task-local test fixtures, P4 entry or long-term Goal termination"
  P3_PHASE_ENTRY_DURATION = "Until the P3 Exit Gate is independently ACCEPTED and reaches Founder Phase Gate, the non-resettable Phase envelope is exhausted, Founder explicitly revokes P3 entry, or a terminal safety condition occurs"
  P3_PHASE_ENTRY_BUDGET = "One non-resettable P3 Phase envelope of at most 8 engineering Tasks, 256 engineering hours and 64 calendar days; each activated Task consumes its declared reservation, ordinary Task NON_PASS creates no automatic budget expansion, and external capabilities remain zero"
  P3_PHASE_ENTRY_CONSUMPTION = "The envelope persists across ordinary independent P3 Task PASS or NON_PASS until the P3 Exit Gate is accepted, capacity is exhausted, Founder revokes it, or a terminal safety condition occurs; no Task outcome authorizes P4 entry, external effects or long-term Goal closure"
  P3_PHASE_ENTRY_PASS = "PASS installs P3 entry, sets P3 ACTIVE, keeps exactly one current Task, allows Master to begin the highest-value minimal P3 engineering Task, and keeps the Long-term Goal ACTIVE; later P3 Exit-Gate PASS still requires an independent Founder Phase Gate before P4"
  P3_PHASE_ENTRY_NON_PASS = "If installation identity, predecessor Gate or scope validation is NON_PASS, create no P3 Task, preserve P2 COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED, keep P3 ELIGIBLE_AWAITING_SEPARATE_FOUNDER_PHASE_ENTRY, keep P4 HOLD and the Long-term Goal ACTIVE, and create no repair or replacement authorization chain"
  P3_FINAL_CAPABILITY_TOKEN = "AUTHORIZE_P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_ONLY_TERMINAL_V1"
  P3_FINAL_CAPABILITY_OPERATION = "Authorize exactly one final P3 capability-scoped tool and permission enforcement Task after P3-003 terminated before product write; this is a one-time Phase-route exception to the two-implementation-Task milestone cap and does not reset P3-002 or P3-003 consumption"
  P3_FINAL_CAPABILITY_ORDER = "Stage A may change only backend-spring/pom.xml or Task-local test configuration needed to bind forked Surefire and JUnit temp creation inside the exact new Task worktree, then must PASS the exact legacy AgentSandboxToolTest under sandbox-exec deny network before any product-source write; Stage B may then independently implement the persistent capability ledger, and no later P3 milestone unlocks before independent acceptance"
  P3_FINAL_CAPABILITY_LINEAGE = "Preserve P3-002 and P3-003 as closed terminal accounting; prohibit reading, comparing, copying or reusing P3-002 candidate engineering lineage, and use P3-003 only through its exact terminal receipt as preactivation root-cause Evidence; implementation inputs are canonical main, accepted P3-001 and a new Task identity, nonce, branch, worktree, Contract and Evidence root"
  P3_FINAL_CAPABILITY_TARGET = "Local SourceLens canonical main, at most one new active P3 Task branch and worktree, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote write, production, public release, irreversible deletion, existing-database mutation, P4 entry or long-term Goal termination"
  P3_FINAL_CAPABILITY_DURATION = "Until the one final capability Task reaches Task Gate PASS or NON_PASS, Founder explicitly revokes this route, or a terminal safety condition occurs"
  P3_FINAL_CAPABILITY_BUDGET = "No P3 Phase envelope expansion: preserve the 8-Task, 256-engineering-hour and 64-calendar-day limits, consumed 3 Tasks, 96 hours and 24 days, and use exactly one of the remaining Tasks with at most 32 hours and 8 days; activation leaves 4 Tasks, 128 hours and 32 days after this reservation"
  P3_FINAL_CAPABILITY_CONSUMPTION = "This is the sole final exception for the capability milestone: activation consumes exactly one Task, 32-hour and 8-day reservation with one candidate generation, at most one same-Task repair and at most two review cycles; any preactivation or Task NON_PASS creates no successor, replacement, remediation chain, V2 authorization or further capability implementation attempt"
  P3_FINAL_CAPABILITY_PASS = "PASS accepts only CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT, raises P3 delivery progress from 25% to 50%, keeps strict P3 Exit progress at 0%, and unlocks only the bounded isolated-execution-with-complete-traces milestone under the remaining Phase authority; it does not authorize P4 entry or long-term Goal closure"
  P3_FINAL_CAPABILITY_NON_PASS = "NON_PASS preserves exact terminal Evidence, consumes the final exception Task, permanently freezes further capability-milestone implementation inside the current P3 route, keeps P3 ACTIVE_INCOMPLETE at 25% delivery and 0% strict Exit, creates no automatic successor, keeps P4 HOLD and keeps the Long-term Goal ACTIVE"
  P3_ZERO_AUTHORITY_ROUTE_TOKEN = "AUTHORIZE_P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE_RESEQUENCING_V1"
  P3_ZERO_AUTHORITY_ROUTE_DECISION = "Supersede only the scheduling effect of DECIDE_P3_KEEP_STRICT_EXIT_AND_HOLD_CAPABILITY_MILESTONE_AFTER_P3_004_FINAL_EXCEPTION_NON_PASS_V1 and its prohibition on new P3 engineering, solely for this materially different Phase route; preserve that decision, P3-002/P3-003/P3-004 terminal facts and all failed-candidate non-integration facts as immutable accounting"
  P3_ZERO_AUTHORITY_ROUTE_OBJECTIVE = "Keep Strategic Constitution v2.4 and the P3 Objective unchanged: deliver one durable planner, executor, tool, state and checkpoint loop with Minimum Trust"
  P3_ZERO_AUTHORITY_ROUTE_EXIT_GATE = "Keep the strict P3 Exit Gate unchanged: resume, isolation, permission and complete observable trace tests must all be independently ACCEPTED, followed by one independent P3 Exit-Gate audit; no research-NON_PASS completion and no weakened substitute evidence"
  P3_ZERO_AUTHORITY_ROUTE_ARCHITECTURE = "Replace the failed mutable in-process capability-grant/ledger approach with a zero-authority Agent plus an immutable Task Action Envelope and an out-of-process default-deny broker: AgentRuntime may request actions but cannot mint, mutate, widen or execute authority; every tool request must bind exact task, workflow, checkpoint, repository commit/tree, normalized root, tool, argument constraints, read/write roots, executable identity, closed environment, network policy, timeout, budget, nonce and expiry from a create-once envelope issued outside AgentRuntime; the broker must durably persist an ALLOW or DENY decision before any tool body and fail closed if that persistence fails; effectful actions run only in a disposable Task worktree under exact /usr/bin/sandbox-exec deny-network and write confinement with no fallback to the current local ProcessBuilder path; completed action receipts are idempotently bound into the accepted P3-001 checkpoint chain so resume cannot duplicate effects; request, decision, argv, cwd, environment identity, stdout, stderr, exit, file pre/post state, patch, rollback and checkpoint events form one complete replayable trace"
  P3_ZERO_AUTHORITY_ROUTE_MILESTONES = "Preserve DURABLE_STATE_AND_CHECKPOINT_RESUME as ACCEPTED; replace only the frozen CAPABILITY_SCOPED_TOOL_AND_PERMISSION_ENFORCEMENT implementation projection with ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PERMISSION_ENFORCEMENT; retain BOUNDED_ISOLATED_EXECUTION_WITH_COMPLETE_OBSERVABLE_TRACES and INDEPENDENT_P3_EXIT_GATE_AUDIT as required milestones"
  P3_ZERO_AUTHORITY_ROUTE_ORDER = "Use exactly four ordered remaining slots: slot 1 ZERO_AUTHORITY_AGENT_ACTION_REQUEST_BOUNDARY removes all direct effectful dispatch from AgentRuntime and freezes typed action requests with fail-closed pre-effect denial recording; slot 2 IMMUTABLE_TASK_ACTION_ENVELOPE_BROKER_AND_PERMISSION_ENFORCEMENT implements the independent broker and accepts the new permission milestone only after fresh independent review; slot 3 BOUNDED_ISOLATED_EXECUTION_TRACE_CHECKPOINT_REPLAY_AND_ROLLBACK integrates the accepted checkpoint kernel with one controlled synthetic end-to-end execution, crash/resume without duplicate effects, complete trace and exact rollback; slot 4 INDEPENDENT_P3_EXIT_GATE_AUDIT performs evaluation only and may not mutate product, oracle, criteria or prior Evidence"
  P3_ZERO_AUTHORITY_ROUTE_LINEAGE = "Implementation inputs are only canonical main, the accepted P3-001 checkpoint foundation and newly authored Task Contracts; prohibit reading, comparing, copying or reusing P3-002/P3-003/P3-004 branches, worktrees, code, tests, evaluator implementations or engineering Evidence; terminal receipts may be used only for identity and accounting; prohibit recreating a mutable dynamic capability-grant ledger under a new name"
  P3_ZERO_AUTHORITY_ROUTE_INSTALLATION = "Permit one create-once structured Founder decision, one minimal closed-profile extension of the existing Founder handoff/P3 route validators solely to recognize this exact token, operation type and resolved-HOLD-to-new-route transition, and the mechanically identical current Truth/route projection; Constitution v2.4 remains byte-exact unchanged; installation, validator work and governance synchronization receive zero engineering or delivery credit and no Task may be created before installation and relevant authority/predecessor checks PASS"
  P3_ZERO_AUTHORITY_ROUTE_VALIDATOR_BOUNDARY = "The previously observed historical Founder Knowledge Sync inconsistency is disclosed but is neither repaired nor waived by this route and receives zero progress; if it mechanically falsifies a P3-bound identity or a validator required by this route, preactivation stops before Task creation without an automatic governance repair chain"
  P3_ZERO_AUTHORITY_ROUTE_TARGET = "Local SourceLens canonical main, at most one active P3 Task branch and worktree, Task-contract allowlisted backend-spring agent/execution/sandbox code, corresponding tests and fresh Task-local database fixtures, plus create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no existing-database mutation, network, Provider, Secret, remote write, production, public release, irreversible deletion, P4 entry or long-term Goal termination"
  P3_ZERO_AUTHORITY_ROUTE_DURATION = "Until the strict P3 Exit Gate is independently ACCEPTED and reaches the Founder Phase Gate, all exact four remaining slots are consumed, Founder explicitly revokes this route, or a terminal safety condition occurs"
  P3_ZERO_AUTHORITY_ROUTE_BUDGET = "No P3 Phase envelope expansion: preserve limits of 8 engineering Tasks, 256 engineering hours and 64 calendar days, preserve consumed 4 Tasks, 128 hours and 32 days, and unlock exactly the remaining 4 Tasks, 128 hours and 32 days in the declared order; each Task reserves at most 32 hours and 8 days, only one Task/branch/worktree/candidate may be active, each engineering Task permits at most 2 candidate generations, 1 same-Task repair and 2 review cycles, governance/pre-Worker preparation is capped at 10 percent and real Worker implementation must start within the first engineering hour"
  P3_ZERO_AUTHORITY_ROUTE_CONSUMPTION = "Each activated Task consumes exactly one 32-hour/8-day slot; any Task NON_PASS preserves exact terminal Evidence, locks every dependent slot, returns P3 to HOLD under this route and creates no successor, replacement, remediation, V2/V3 or automatic Founder request"
  P3_ZERO_AUTHORITY_ROUTE_PASS = "Installation PASS sets P3 ACTIVE on this route with delivery 25 percent and strict Exit 0 percent and unlocks only slot 1; later milestone PASS effects follow the declared progress map; final Exit-audit PASS authorizes only Founder P3 Phase-Gate consideration and does not authorize P4 entry or project/Goal completion"
  P3_ZERO_AUTHORITY_ROUTE_NON_PASS = "Any installation identity, authority, predecessor or validator mismatch stops before Task creation and preserves the current HOLD; any Task NON_PASS consumes its slot, integrates no failed candidate, leaves P4 HOLD and Long-term Goal ACTIVE, and creates no automatic retry chain"
  P3_HOST_AUTHORIZED_ROUTE_TOKEN = "AUTHORIZE_P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007_V1"
  P3_HOST_AUTHORIZED_ROUTE_PRIMARY_TRIGGER = "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
  P3_HOST_AUTHORIZED_ROUTE_CAPACITY_TRIGGER = "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
  P3_HOST_AUTHORIZED_ROUTE_OBJECTIVE = "Build and independently validate one host-authorized transactional Single-Agent workflow in which every Agent output is non-authoritative proposal data and can neither create authority nor directly supply an executable, handler, filesystem path, environment value, credential, network target, or unrestricted argument map. The trusted host alone derives each invocation from an immutable task/workflow specification, the accepted P3-001 checkpoint state, a compile-time closed action algebra, content-addressed host-custody handles, and positive state/resource/budget authorization; it durably records an invocation-local authorization decision and dispatch intent before any effect, executes only inside a disposable OS-enforced isolation boundary, and blocks checkpoint advancement until exactly one append-only terminal invocation trace has been durably accepted or crash-reconciled. A generic tool registry, dynamic grant, broker/interpreter, finite semantic denylist, best-effort post-effect audit, network/Provider/Secret/remote/production/public effect, or P4 entry is not permitted."
  P3_HOST_AUTHORIZED_ROUTE_ORDER = "我批准创建 P3_HOST_AUTHORIZED_TRANSACTIONAL_TRUST_BOUNDARY_REBASELINE_ROUTE_V1，只允许以下三个顺序阶段："
  P3_HOST_AUTHORIZED_ROUTE_LINEAGE = "P3-002 至 P3-007 的 branch、worktree、code、tests、evaluator、candidate 和 engineering Evidence 永久冻结，不读取、不比较、不复制、不执行、不修复、不复用；只允许使用 canonical Truth 与 terminal receipt 中的身份和 accounting。P3-001 的 accepted source、schema、migration 和 tests 保持只读 foundation；新实现只允许组合其已接受公开行为。若必须修改 P3-001 accepted semantics，新路线立即 NON_PASS 并返回 HOLD。"
  P3_HOST_AUTHORIZED_ROUTE_TARGET = "本地 SourceLens canonical main；"
  P3_HOST_AUTHORIZED_ROUTE_BUDGET = "将累计 P3 ceiling 精确扩为 10 engineering Tasks / 288 engineering hours / 72 calendar days；"
  P3_HOST_AUTHORIZED_ROUTE_DURATION = "本授权从我直接回复本完整 exact text 且 Agent 再次核验全部 current identities PASS 时生效；在 strict P3 Exit 独立 ACCEPTED 并到达 Founder P3 Phase Gate、3 Tasks / 64 hours / 16 days 容量耗尽、出现 terminal safety condition、任一 identity 漂移或我明确撤销时终止。"
  P3_HOST_AUTHORIZED_ROUTE_CONSUMPTION = "未激活容量不得重排、转赠或解释为后继授权。"
  P3_HOST_AUTHORIZED_ROUTE_PASS = "安装 PASS 只安装 Constitution v2.7、route、Truth projection 和 validators，保持当前 25% delivery / 0% strict Exit，工程进度贡献为 0；"
  P3_HOST_AUTHORIZED_ROUTE_NON_PASS = "安装 NON_PASS 保持当前 HOLD，不创建治理修复链。"
  P3_HOST_AUTHORIZED_ROUTE_CANONICAL_BODY_BYTES = 12_584
  P3_HOST_AUTHORIZED_ROUTE_CANONICAL_BODY_SHA256 = "34e8dd59ec03386623b61c381af3f1d7fa7fe44fde9402bcd39300f3f80b9a8f"
  P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_COMMIT = "8e4fd7037bd72c6c80561079ddd82991aac0f37e"
  P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TREE = "79c4e0dc0960e152b780fb0690fd4f7a15d7b3d9"
  P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_PATH = "docs/aios/truth/project_state.yaml"
  P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_BYTES = 1_860_604
  P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_SHA256 = "ffb8ad7ea3474d3592e90b417c2aa5696ad54f4e6d6042fecc7da5d3e3ef2e47"
  P3_HPE_ROUTE_TOKEN =
    "AUTHORIZE_P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_REBASELINE_AFTER_TIK_F1_TERMINAL_V1"
  P3_HPE_ROUTE_OPERATION_TYPE =
    "P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_REBASELINE_AFTER_TIK_F1_TERMINAL"
  P3_HPE_ROUTE_PRIMARY_TRIGGER = "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
  P3_HPE_ROUTE_CAPACITY_SCOPE =
    "批准一次 P3 路线变更与最小 Task 数量扩展。"
  P3_HPE_ROUTE_OPERATION =
    "授权一次 P3 Host-Process-Enforced Minimal Slice 路线变更，只允许安装一个更小的 process-real Foundation、一个非空产品实现 Task 和一个 one-shot strict Exit audit；不得恢复或修复已终态 TIK Task。"
  P3_HPE_ROUTE_ORDER =
    "严格顺序为 HOST_PROCESS_CONFINEMENT_COMPATIBILITY_FOUNDATION → DURABLE_HOST_INVOCATION_KERNEL_PRODUCT → ONE_SHOT_INDEPENDENT_STRICT_EXIT_AUDIT；前一 Stage 未独立 ACCEPTED 时后一 Stage 必须保持 LOCKED。"
  P3_HPE_ROUTE_LINEAGE =
    "P3-002 至 P3-007、P3-HATB-F1 与本次 P3-TIK-F1 的 rejected branch、worktree、code、tests、evaluator、candidate、raw engineering Evidence 和 bundle lineage 均禁止读取、比较、复制、执行、修复或复用；新路线只能使用 canonical main、accepted P3-001 public behavior、新 Founder decision 以及旧 terminal receipt/attestation 的 identity 与 accounting。"
  P3_HPE_ROUTE_TARGET =
    "本路线只作用于本地 SourceLens canonical main、上述三个依序且短生命周期的 Task branch/worktree、对应 create-once Evidence roots，以及 exact Task Contract allowlist；不授权 remote push、tag、release、部署或对外发布。"
  P3_HPE_ROUTE_BUDGET =
    "将 P3 累计 ceiling 精确改为 12 engineering Tasks / 336 engineering hours / 84 calendar days，保留 consumed 9 / 264 / 66，只释放本路线按顺序使用的 3 Tasks / 72 hours / 18 days；不授权任何额外小时、日历、网络或第二次路线扩张。"
  P3_HPE_ROUTE_DURATION =
    "本授权在以下任一条件发生时终止：Stage 3 formal PASS/NON_PASS 并形成 exact terminal/Phase-Gate receipt；3 Tasks / 72 hours / 18 days 容量耗尽；任一 identity 漂移；出现 unauthorized external effect、scope escape、credential exposure、existing DB mutation、outside-root write 或 irreversible deletion；我明确撤销。"
  P3_HPE_ROUTE_CONSUMPTION =
    "任一 Stage NON_PASS 都终止本路线：失败 candidate 不集成，保留 exact receipt/bundle/attestation，dependent stages 保持 LOCKED；不得创建 Candidate 3、successor、replacement、normalization、closure、feasibility、remediation、V2/V3 路线或 rerun-to-pass。"
  P3_HPE_ROUTE_PASS =
    "PASS lifecycle：安装 PASS 仅使 Stage 1 eligible，仍为 P3 delivery 25% / strict Exit 0%；Stage 1 PASS → 50%/0%；Stage 2 PASS → 75%/0%；Stage 3 PASS → 100%/100% 并仅等待 Founder P3 Phase Gate。"
  P3_HPE_ROUTE_NON_PASS =
    "NON_PASS lifecycle：安装 NON_PASS 不创建 Task；Stage 1 或 Stage 2 NON_PASS 不集成 candidate并锁定后续 Stage；Stage 3 NON_PASS 保留 one-shot 真实结果且不得重跑。任何 NON_PASS 都保持 P4 HOLD、项目未完成、长期 Goal ACTIVE，并交付下一步 handoff，但不得自动执行另一条路线。"
  P3_HPE_ROUTE_CANONICAL_BODY_BYTES = 17_085
  P3_HPE_ROUTE_CANONICAL_BODY_SHA256 =
    "b4be5e40155710913c2e6b61214f07b5df4cd176cbd8cf07f7eecf24f2283202"
  P3_HPE_ROUTE_PREINSTALL_COMMIT =
    "b6d7b398278f3e64ef8ee5761c9324cdebf0e8f3"
  P3_HPE_ROUTE_PREINSTALL_TREE =
    "2de5445ca28cb73b0093d02780f9248ad4b8b049"
  P3_HPE_ROUTE_PREINSTALL_TRUTH_PATH = "docs/aios/truth/project_state.yaml"
  P3_HPE_ROUTE_PREINSTALL_TRUTH_BYTES = 1_899_425
  P3_HPE_ROUTE_PREINSTALL_TRUTH_SHA256 =
    "fdc473bebc781271dbec7a622a936556b92bc46d44aef55314fa251052fb2ac1"
  P3_TXC_ROUTE_TOKEN =
    "AUTHORIZE_P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY_AFTER_POSTINSTALL_PROTOCOL_ERROR_V1"
  P3_TXC_ROUTE_OPERATION_TYPE =
    "P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY_AFTER_POSTINSTALL_PROTOCOL_ERROR"
  P3_TXC_ROUTE_PRIMARY_TRIGGER = "MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE"
  P3_TXC_ROUTE_DECISION_PATH =
    "/Users/lijunpeng/Developer/.sourcelens-audit/p3-txc-control-recovery-20260822/decision/FOUNDER_P3_TXCR_CONTROL_RECOVERY_ACCEPTED_STRUCTURED_DECISION_V1.json"
  P3_TXC_ROUTE_DECISION_BYTES = 22_892
  P3_TXC_ROUTE_DECISION_SHA256 =
    "d804694d69119c67ce0421c5dadac894db956a032599e800cc53590615536184"
  P3_TXC_ROUTE_CANONICAL_BODY_BYTES = 18_433
  P3_TXC_ROUTE_CANONICAL_BODY_SHA256 =
    "769ff349511f275f4bb2f1647f2bf224864658181002c24c6ab944ab21b5eee4"
  P3_TXC_ROUTE_PREINSTALL_COMMIT = "e23f48a3a4e68453d81c41dc774940a52378534f"
  P3_TXC_ROUTE_PREINSTALL_TREE = "de999ff5fa6e16b78573a6ff805da2af18b7f748"
  P3_TXC_ROUTE_PREINSTALL_TRUTH_PATH = "docs/aios/truth/project_state.yaml"
  P3_TXC_ROUTE_PREINSTALL_TRUTH_BYTES = 1_928_850
  P3_TXC_ROUTE_PREINSTALL_TRUTH_SHA256 =
    "0ffe94417d134fca97197232f27f856e6f0949b7bf8d09626b67dc185cb59e58"
  P3_TXC_ROUTE_DECISION_DATA = begin
    bytes = File.binread(P3_TXC_ROUTE_DECISION_PATH)
    raise "P3 TXC decision byte identity drift" unless
      bytes.bytesize == P3_TXC_ROUTE_DECISION_BYTES &&
      Digest::SHA256.hexdigest(bytes) == P3_TXC_ROUTE_DECISION_SHA256
    JSON.parse(bytes)
  end.freeze
  P3_TXC_ROUTE_PROFILE = begin
    decision = P3_TXC_ROUTE_DECISION_DATA
    route = decision.fetch("route")
    staging = decision.fetch("control_plane_recovery")
    lifecycle = decision.fetch("lifecycle")
    {
      "operations" => [
        decision.fetch("operation_type"),
        route.fetch("route_id"),
        route.fetch("objective_id"),
        decision.dig("strategic_change", "p3_strict_exit_gate"),
        "EXACT_CONTROL_PLANE_RECOVERY"
      ],
      "targets" => [
        decision.dig("canonical_start", "repository"),
        staging.fetch("stage0_evidence_root"),
        route.dig("stages", 0, "resources", "worktree"),
        route.dig("stages", 0, "resources", "evidence_root"),
        route.dig("stages", 1, "resources", "worktree"),
        route.dig("stages", 1, "resources", "evidence_root")
      ],
      "budget_or_external_effects" => JSON.generate({
        "ceiling" => route.fetch("cumulative_ceiling"),
        "consumed" => route.fetch("consumed_preserved"),
        "remaining" => route.fetch("remaining"),
        "external_effects" => decision.fetch("external_effects")
      }),
      "token" => P3_TXC_ROUTE_TOKEN,
      "duration" => JSON.generate({
        "control_patch_generations_max" => staging.fetch("candidate_generations_max"),
        "same_staging_repairs_max" => staging.fetch("same_staging_repairs_max"),
        "product_budget" => route.dig("stages", 0, "budget"),
        "audit_budget" => route.dig("stages", 1, "budget")
      }),
      "authorization_expiry_or_consumption_rule" => JSON.generate(lifecycle),
      "pass_lifecycle" => JSON.generate({
        "stage0" => lifecycle.fetch("stage0_pass"),
        "stage1" => lifecycle.fetch("stage1_pass"),
        "stage2" => lifecycle.fetch("stage2_pass")
      }),
      "non_pass_lifecycle" => JSON.generate({
        "stage0" => lifecycle.fetch("stage0_non_pass"),
        "stage1" => lifecycle.fetch("stage1_non_pass"),
        "stage2" => lifecycle.fetch("stage2_non_pass")
      }),
      "risk_and_reversibility" => JSON.generate({
        "canonical_post_install_repair_allowed" =>
          staging.fetch("canonical_post_install_repair_allowed"),
        "canonical_post_install_rerun_to_pass_allowed" =>
          staging.fetch("canonical_post_install_rerun_to_pass_allowed"),
        "canonical_exact_revert_on_non_pass_count_max" =>
          staging.fetch("canonical_exact_revert_on_non_pass_count_max"),
        "anti_loop" => decision.fetch("anti_loop")
      }),
      "deny_or_defer_effect" => JSON.generate({
        "provider" => decision.dig("external_effects", "provider"),
        "secret" => decision.dig("external_effects", "secret"),
        "remote" => decision.dig("external_effects", "remote"),
        "production" => decision.dig("external_effects", "production"),
        "public" => decision.dig("external_effects", "public"),
        "p4_entry" => decision.dig("external_effects", "p4_entry")
      })
    }
  end.freeze
  FOUNDER_NETWORK_OPERATION_PROFILES = {
    "READ_ONLY_HTTPS_ACQUISITION" => {
      "operations" => [READ_ONLY_HTTPS_OPERATION, READ_ONLY_HTTPS_METHOD],
      "targets" => [READ_ONLY_HTTPS_TARGETS],
      "budget_or_external_effects" => READ_ONLY_HTTPS_BUDGET
    },
    "READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL" => {
      "operation_tail" => [
        READ_ONLY_HTTPS_METHOD,
        STANDARD_CURL_METRIC_EXCLUSIONS,
        STANDARD_CURL_RETRY_POLICY,
        STANDARD_CURL_IDENTITY_BINDING
      ],
      "targets" => [READ_ONLY_HTTPS_TARGETS],
      "budget_or_external_effects" => STANDARD_CURL_BUDGET
    },
    "READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL" => {
      "operations" => [
        MILESTONE_CURL_OPERATION,
        MILESTONE_CURL_METHOD,
        STANDARD_CURL_METRIC_EXCLUSIONS,
        STANDARD_CURL_RETRY_POLICY,
        STANDARD_CURL_IDENTITY_BINDING
      ],
      "targets" => [READ_ONLY_HTTPS_TARGETS],
      "budget_or_external_effects" => MILESTONE_CURL_BUDGET,
      "token" => MILESTONE_CURL_TOKEN,
      "duration" => MILESTONE_CURL_DURATION,
      "authorization_expiry_or_consumption_rule" => MILESTONE_CURL_CONSUMPTION,
      "pass_lifecycle" => MILESTONE_CURL_PASS,
      "non_pass_lifecycle" => MILESTONE_CURL_NON_PASS
    },
    "READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL_REISSUE" => {
      "operations" => [
        MILESTONE_CURL_REISSUE_OPERATION,
        MILESTONE_CURL_REISSUE_METHOD,
        STANDARD_CURL_METRIC_EXCLUSIONS,
        STANDARD_CURL_RETRY_POLICY,
        STANDARD_CURL_IDENTITY_BINDING
      ],
      "targets" => [READ_ONLY_HTTPS_TARGETS],
      "budget_or_external_effects" => MILESTONE_CURL_REISSUE_BUDGET,
      "token" => MILESTONE_CURL_REISSUE_TOKEN,
      "duration" => MILESTONE_CURL_REISSUE_DURATION,
      "authorization_expiry_or_consumption_rule" => MILESTONE_CURL_REISSUE_CONSUMPTION,
      "pass_lifecycle" => MILESTONE_CURL_REISSUE_PASS,
      "non_pass_lifecycle" => MILESTONE_CURL_REISSUE_NON_PASS
    },
    "P2_BENCHMARK_SOURCE_FINAL_CANDIDATE_COMPLETION_ENVELOPE" => {
      "operations" => [
        FINAL_CANDIDATE_COMPLETION_OPERATION,
        FINAL_CANDIDATE_COMPLETION_METHOD,
        STANDARD_CURL_METRIC_EXCLUSIONS,
        STANDARD_CURL_RETRY_POLICY,
        STANDARD_CURL_IDENTITY_BINDING
      ],
      "targets" => [READ_ONLY_HTTPS_TARGETS],
      "budget_or_external_effects" => FINAL_CANDIDATE_COMPLETION_BUDGET,
      "token" => FINAL_CANDIDATE_COMPLETION_TOKEN,
      "duration" => FINAL_CANDIDATE_COMPLETION_DURATION,
      "authorization_expiry_or_consumption_rule" => FINAL_CANDIDATE_COMPLETION_CONSUMPTION,
      "pass_lifecycle" => FINAL_CANDIDATE_COMPLETION_PASS,
      "non_pass_lifecycle" => FINAL_CANDIDATE_COMPLETION_NON_PASS
    },
    "P2_RECOVERY_CLEAN_ROOM_RESEQUENCING_AND_MINIMAL_ENVELOPE_EXPANSION" => {
      "operations" => [
        RECOVERY_RESEQUENCE_OPERATION,
        RECOVERY_RESEQUENCE_ORDER,
        RECOVERY_RESEQUENCE_LINEAGE
      ],
      "targets" => [RECOVERY_RESEQUENCE_TARGET],
      "budget_or_external_effects" => RECOVERY_RESEQUENCE_BUDGET,
      "token" => RECOVERY_RESEQUENCE_TOKEN,
      "duration" => RECOVERY_RESEQUENCE_DURATION,
      "authorization_expiry_or_consumption_rule" => RECOVERY_RESEQUENCE_CONSUMPTION,
      "pass_lifecycle" => RECOVERY_RESEQUENCE_PASS,
      "non_pass_lifecycle" => RECOVERY_RESEQUENCE_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_RECOVERY_ORDER,
        PRODUCT_SELECTOR_RECOVERY_LINEAGE
      ],
      "targets" => [PRODUCT_SELECTOR_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_RECOVERY_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_INTEGRITY_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_INTEGRITY_RECOVERY_ORDER,
        PRODUCT_SELECTOR_INTEGRITY_RECOVERY_LINEAGE,
        PRODUCT_SELECTOR_INTEGRITY_RECOVERY_PREFLIGHT
      ],
      "targets" => [PRODUCT_SELECTOR_INTEGRITY_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_INTEGRITY_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_INTEGRITY_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_INTEGRITY_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_INTEGRITY_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_INTEGRITY_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_INTEGRITY_RECOVERY_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_STREAM_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_STREAM_RECOVERY_ORDER,
        PRODUCT_SELECTOR_STREAM_RECOVERY_LINEAGE,
        PRODUCT_SELECTOR_STREAM_RECOVERY_PREFLIGHT
      ],
      "targets" => [PRODUCT_SELECTOR_STREAM_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_STREAM_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_STREAM_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_STREAM_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_STREAM_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_STREAM_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_STREAM_RECOVERY_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_CLOSURE_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_CLOSURE_RECOVERY_ORDER,
        PRODUCT_SELECTOR_CLOSURE_RECOVERY_LINEAGE,
        PRODUCT_SELECTOR_CLOSURE_RECOVERY_PREFLIGHT
      ],
      "targets" => [PRODUCT_SELECTOR_CLOSURE_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_CLOSURE_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_CLOSURE_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_CLOSURE_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_CLOSURE_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_CLOSURE_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_CLOSURE_RECOVERY_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_PIVOT_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_PIVOT_RECOVERY_ORDER,
        PRODUCT_SELECTOR_PIVOT_RECOVERY_LINEAGE,
        PRODUCT_SELECTOR_PIVOT_RECOVERY_ARCHITECTURE
      ],
      "targets" => [PRODUCT_SELECTOR_PIVOT_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_PIVOT_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_PIVOT_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_PIVOT_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_PIVOT_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_PIVOT_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_PIVOT_RECOVERY_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_ORDER,
        PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_LINEAGE,
        PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_ARCHITECTURE,
        PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_ACCEPTANCE
      ],
      "targets" => [PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_GRAPH_FUSION_RECOVERY_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_ORDER,
        PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_LINEAGE,
        PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_ARCHITECTURE,
        PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_ACCEPTANCE
      ],
      "targets" => [PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_SEMANTIC_IMPACT_RECOVERY_NON_PASS
    },
    "P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE" => {
      "operations" => [
        PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_OPERATION,
        PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_ORDER,
        PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_LINEAGE,
        PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_ARCHITECTURE,
        PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_ACCEPTANCE
      ],
      "targets" => [PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_TARGET],
      "budget_or_external_effects" => PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_BUDGET,
      "token" => PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_TOKEN,
      "duration" => PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_DURATION,
      "authorization_expiry_or_consumption_rule" => PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_CONSUMPTION,
      "pass_lifecycle" => PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_PASS,
      "non_pass_lifecycle" => PRODUCT_SELECTOR_COMPILER_ATTRIBUTED_RECOVERY_NON_PASS
    },
    "P2_EXACT_FROZEN_P2_078_ONE_SHOT_FORMAL_HELD_ROUTE_UNLOCK" => {
      "operations" => [
        P2_078_PARETO_RESIDUAL_ADMISSION_OPERATION,
        P2_078_PARETO_RESIDUAL_ADMISSION_PERMISSION,
        P2_078_PARETO_RESIDUAL_ADMISSION_CRITERION,
        P2_078_PARETO_RESIDUAL_ADMISSION_REVIEW,
        P2_078_PARETO_RESIDUAL_ADMISSION_ORDER
      ],
      "targets" => [P2_078_PARETO_RESIDUAL_ADMISSION_TARGET],
      "budget_or_external_effects" => P2_078_PARETO_RESIDUAL_ADMISSION_BUDGET,
      "token" => P2_078_PARETO_RESIDUAL_ADMISSION_TOKEN,
      "duration" => P2_078_PARETO_RESIDUAL_ADMISSION_DURATION,
      "authorization_expiry_or_consumption_rule" => P2_078_PARETO_RESIDUAL_ADMISSION_CONSUMPTION,
      "pass_lifecycle" => P2_078_PARETO_RESIDUAL_ADMISSION_PASS,
      "non_pass_lifecycle" => P2_078_PARETO_RESIDUAL_ADMISSION_NON_PASS
    },
    "P2_EXACT_FROZEN_P2_078_EVALUATION_AND_EVIDENCE_ADAPTER_PLUS_ONE_SHOT_FORMAL_HELD_SEQUENCE" => {
      "operations" => [
        P2_EVALUATION_ADAPTER_OPERATION,
        P2_EVALUATION_ADAPTER_PERMISSION,
        P2_EVALUATION_ADAPTER_PREFLIGHT,
        P2_EVALUATION_ADAPTER_EVIDENCE,
        P2_EVALUATION_ADAPTER_COMPATIBILITY,
        P2_EVALUATION_ADAPTER_FORMAL
      ],
      "targets" => [P2_EVALUATION_ADAPTER_TARGET],
      "budget_or_external_effects" => P2_EVALUATION_ADAPTER_BUDGET,
      "token" => P2_EVALUATION_ADAPTER_TOKEN,
      "duration" => P2_EVALUATION_ADAPTER_DURATION,
      "authorization_expiry_or_consumption_rule" => P2_EVALUATION_ADAPTER_CONSUMPTION,
      "pass_lifecycle" => P2_EVALUATION_ADAPTER_PASS,
      "non_pass_lifecycle" => P2_EVALUATION_ADAPTER_NON_PASS
    },
    "P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY" => {
      "operations" => [
        P3_PHASE_ENTRY_OPERATION,
        P3_PHASE_ENTRY_DELEGATION,
        P3_PHASE_ENTRY_ORDER
      ],
      "targets" => [P3_PHASE_ENTRY_TARGET],
      "budget_or_external_effects" => P3_PHASE_ENTRY_BUDGET,
      "token" => P3_PHASE_ENTRY_TOKEN,
      "duration" => P3_PHASE_ENTRY_DURATION,
      "authorization_expiry_or_consumption_rule" => P3_PHASE_ENTRY_CONSUMPTION,
      "pass_lifecycle" => P3_PHASE_ENTRY_PASS,
      "non_pass_lifecycle" => P3_PHASE_ENTRY_NON_PASS
    },
    "P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_TERMINAL" => {
      "operations" => [
        P3_FINAL_CAPABILITY_OPERATION,
        P3_FINAL_CAPABILITY_ORDER,
        P3_FINAL_CAPABILITY_LINEAGE
      ],
      "targets" => [P3_FINAL_CAPABILITY_TARGET],
      "budget_or_external_effects" => P3_FINAL_CAPABILITY_BUDGET,
      "token" => P3_FINAL_CAPABILITY_TOKEN,
      "duration" => P3_FINAL_CAPABILITY_DURATION,
      "authorization_expiry_or_consumption_rule" => P3_FINAL_CAPABILITY_CONSUMPTION,
      "pass_lifecycle" => P3_FINAL_CAPABILITY_PASS,
      "non_pass_lifecycle" => P3_FINAL_CAPABILITY_NON_PASS
    },
    "P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE_RESEQUENCING" => {
      "operations" => [
        P3_ZERO_AUTHORITY_ROUTE_DECISION,
        P3_ZERO_AUTHORITY_ROUTE_OBJECTIVE,
        P3_ZERO_AUTHORITY_ROUTE_EXIT_GATE,
        P3_ZERO_AUTHORITY_ROUTE_ARCHITECTURE,
        P3_ZERO_AUTHORITY_ROUTE_MILESTONES,
        P3_ZERO_AUTHORITY_ROUTE_ORDER,
        P3_ZERO_AUTHORITY_ROUTE_LINEAGE,
        P3_ZERO_AUTHORITY_ROUTE_INSTALLATION,
        P3_ZERO_AUTHORITY_ROUTE_VALIDATOR_BOUNDARY
      ],
      "targets" => [P3_ZERO_AUTHORITY_ROUTE_TARGET],
      "budget_or_external_effects" => P3_ZERO_AUTHORITY_ROUTE_BUDGET,
      "token" => P3_ZERO_AUTHORITY_ROUTE_TOKEN,
      "duration" => P3_ZERO_AUTHORITY_ROUTE_DURATION,
      "authorization_expiry_or_consumption_rule" => P3_ZERO_AUTHORITY_ROUTE_CONSUMPTION,
      "pass_lifecycle" => P3_ZERO_AUTHORITY_ROUTE_PASS,
      "non_pass_lifecycle" => P3_ZERO_AUTHORITY_ROUTE_NON_PASS
    },
    "P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007" => {
      "operations" => [
        P3_HOST_AUTHORIZED_ROUTE_PRIMARY_TRIGGER,
        P3_HOST_AUTHORIZED_ROUTE_CAPACITY_TRIGGER,
        P3_HOST_AUTHORIZED_ROUTE_OBJECTIVE,
        P3_HOST_AUTHORIZED_ROUTE_ORDER,
        P3_HOST_AUTHORIZED_ROUTE_LINEAGE
      ],
      "targets" => [P3_HOST_AUTHORIZED_ROUTE_TARGET],
      "budget_or_external_effects" => P3_HOST_AUTHORIZED_ROUTE_BUDGET,
      "token" => P3_HOST_AUTHORIZED_ROUTE_TOKEN,
      "duration" => P3_HOST_AUTHORIZED_ROUTE_DURATION,
      "authorization_expiry_or_consumption_rule" => P3_HOST_AUTHORIZED_ROUTE_CONSUMPTION,
      "pass_lifecycle" => P3_HOST_AUTHORIZED_ROUTE_PASS,
      "non_pass_lifecycle" => P3_HOST_AUTHORIZED_ROUTE_NON_PASS
    },
    P3_HPE_ROUTE_OPERATION_TYPE => {
      "operations" => [
        P3_HPE_ROUTE_PRIMARY_TRIGGER,
        P3_HPE_ROUTE_CAPACITY_SCOPE,
        P3_HPE_ROUTE_OPERATION,
        P3_HPE_ROUTE_ORDER,
        P3_HPE_ROUTE_LINEAGE
      ],
      "targets" => [P3_HPE_ROUTE_TARGET],
      "budget_or_external_effects" => P3_HPE_ROUTE_BUDGET,
      "token" => P3_HPE_ROUTE_TOKEN,
      "duration" => P3_HPE_ROUTE_DURATION,
      "authorization_expiry_or_consumption_rule" => P3_HPE_ROUTE_CONSUMPTION,
      "pass_lifecycle" => P3_HPE_ROUTE_PASS,
      "non_pass_lifecycle" => P3_HPE_ROUTE_NON_PASS
    },
    P3_TXC_ROUTE_OPERATION_TYPE => P3_TXC_ROUTE_PROFILE
  }.freeze
  PROSPECTIVE_PREFLIGHT = "PROSPECTIVE_RESERVED_EFFECT_REQUIRED_BY_EXACT_USER_REQUEST_AND_NOT_EXPRESSIBLE_BY_CURRENT_OFFLINE_ESCALATION_PROJECTION"
  NO_ACTION_SENTENCE = "你现在无需操作，我将在现有授权范围内继续执行。"
  PLACEHOLDER = /(TBD|TODO|待补|待定|PLACEHOLDER|\{[^}]+\}|<[^>]+>)/i
  FOUNDER_AUTHORIZATION_TOKEN = /(?<![A-Za-z0-9_])AUTHORIZE_[A-Z0-9_]+(?![A-Za-z0-9_])/
  MARKERS = %w[USER_ACTION_REQUIRED RECOMMENDED_SINGLE_ACTION COPY_READY_TEXT_OR_EXACT_STEPS AGENT_CONTINUATION_AFTER_ACTION].freeze
  TERMINAL_HANDOFF_INTERPRETATION = "EXECUTION_PROHIBITION_ONLY_DOES_NOT_SUPPRESS_COPY_READY_HANDOFF"
  PROSPECTIVE_TRIGGER_EFFECTS = {
    "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT" => "NETWORK",
    "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE" => "MATERIAL_SCOPE"
  }.freeze
  SHA256 = /\A[0-9a-f]{64}\z/
  COMMIT = /\A[0-9a-f]{40}\z/

  class ValidationError < StandardError; end
  class DuplicateJsonKeyError < StandardError; end

  class DuplicateRejectingHash < Hash
    def []=(key, value)
      raise DuplicateJsonKeyError, "duplicate JSON key: #{key}" if key?(key)

      super
    end
  end

  module_function

  def assert!(condition, message)
    raise ValidationError, message unless condition
  end

  def exact_object!(value, keys, label)
    assert!(value.is_a?(Hash), "#{label} must be an object")
    assert!(value.keys.sort == keys.sort, "#{label} must be a closed object")
    value
  end

  def nonempty_string!(value, label)
    assert!(value.is_a?(String) && !value.strip.empty?, "#{label} must be a non-empty string")
    assert!(!value.match?(PLACEHOLDER), "#{label} contains a placeholder")
    value
  end

  def nonempty_strings!(value, label)
    assert!(value.is_a?(Array) && !value.empty?, "#{label} must be a non-empty array")
    value.each_with_index { |entry, index| nonempty_string!(entry, "#{label}[#{index}]") }
    value
  end

  def structured_json_object_string!(value, label)
    assert!(value.is_a?(String) && !value.strip.empty?,
            "#{label} must be a non-empty structured JSON string")
    parsed = JSON.parse(value)
    assert!(parsed.is_a?(Hash) && !parsed.empty?,
            "#{label} must encode a non-empty JSON object")
    value
  rescue JSON::ParserError => error
    raise ValidationError, "#{label} is not valid structured JSON: #{error.message}"
  end

  def read_regular!(path, label)
    candidate = Pathname.new(path)
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(candidate, flags) do |file|
      stat = file.stat
      assert!(stat.file? && stat.nlink == 1, "#{label} must be regular nlink1")
      file.binmode
      file.read
    end
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise ValidationError, "#{label} unavailable: #{error.message}"
  end

  def parse_json!(bytes, label)
    value = JSON.parse(bytes, object_class: DuplicateRejectingHash)
    assert!(value.is_a?(Hash), "#{label} must be a JSON object")
    value
  rescue JSON::ParserError, DuplicateJsonKeyError => error
    raise ValidationError, "#{label} JSON invalid: #{error.message}"
  end

  def canonical_truth_path
    Pathname.new(DEFAULT_TRUTH).realpath
  end

  def validate_truth_path!(truth_path)
    candidate = Pathname.new(truth_path)
    assert!(candidate.exist? && !candidate.symlink? && candidate.realpath == canonical_truth_path,
            "handoff check requires the canonical Truth path")
  end

  def git_output!(*args)
    output, error, status = Open3.capture3("git", "-C", ROOT, *args)
    assert!(status.success?, "Git identity lookup failed: #{error.strip}")
    output.strip
  end

  def current_git_identity
    {
      "commit" => git_output!("rev-parse", "HEAD"),
      "tree" => git_output!("rev-parse", "HEAD^{tree}"),
      "branch" => git_output!("branch", "--show-current")
    }
  end

  def validate_common!(package, truth_bytes, test_fixture: false)
    exact_object!(package, %w[
      schema_version action_class truth_sha256 current_state basis affected_scope
      project_authorized app_filesystem_approval_required write_not_executed
      recommended_single_action copy_ready_text_or_exact_steps
      agent_continuation_after_action resume_condition safe_default state_preservation
      canonical_identity governing_artifact validator_evidence user_request_evidence authorization material
      terminal_next_step_handoff
    ], "handoff package")
    assert!(package["schema_version"] == SCHEMA_VERSION, "handoff schema version mismatch")
    assert!(ACTION_CLASSES.include?(package["action_class"]), "handoff action class invalid")
    assert!(CURRENT_STATES.include?(package["current_state"]), "handoff current state invalid")
    assert!(package["truth_sha256"] == Digest::SHA256.hexdigest(truth_bytes), "handoff Truth SHA-256 mismatch")
    basis = exact_object!(package["basis"], %w[facts inferences unknowns], "handoff basis")
    nonempty_strings!(basis["facts"], "handoff facts")
    %w[inferences unknowns].each do |key|
      assert!(basis[key].is_a?(Array), "handoff #{key} must be an array")
      basis[key].each_with_index { |entry, index| nonempty_string!(entry, "handoff #{key}[#{index}]") }
    end
    %w[affected_scope agent_continuation_after_action resume_condition safe_default state_preservation].each do |key|
      nonempty_string!(package[key], "handoff #{key}")
    end
    assert!(PROJECT_AUTHORIZATION_VALUES.include?(package["project_authorized"]), "project authorization value invalid")
    assert!(APP_APPROVAL_VALUES.include?(package["app_filesystem_approval_required"]), "app approval value invalid")
    assert!(WRITE_VALUES.include?(package["write_not_executed"]), "write-not-executed value invalid")

    identity = exact_object!(package["canonical_identity"], %w[commit tree branch], "canonical identity")
    assert!(identity["commit"].is_a?(String) && identity["commit"].match?(COMMIT), "canonical commit invalid")
    assert!(identity["tree"].is_a?(String) && identity["tree"].match?(COMMIT), "canonical tree invalid")
    nonempty_string!(identity["branch"], "canonical branch")
    frozen_p3_operation_type = package.dig("authorization", "operation_type")
    frozen_p3_fixture = test_fixture && [
      "P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007",
      P3_HPE_ROUTE_OPERATION_TYPE,
      P3_TXC_ROUTE_OPERATION_TYPE
    ].include?(frozen_p3_operation_type)
    if frozen_p3_fixture
      expected_fixture_identity = if frozen_p3_operation_type == P3_TXC_ROUTE_OPERATION_TYPE
        {
          "commit" => P3_TXC_ROUTE_PREINSTALL_COMMIT,
          "tree" => P3_TXC_ROUTE_PREINSTALL_TREE,
          "branch" => "main"
        }
      elsif frozen_p3_operation_type == P3_HPE_ROUTE_OPERATION_TYPE
        {
          "commit" => P3_HPE_ROUTE_PREINSTALL_COMMIT,
          "tree" => P3_HPE_ROUTE_PREINSTALL_TREE,
          "branch" => "main"
        }
      else
        {
          "commit" => P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_COMMIT,
          "tree" => P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TREE,
          "branch" => "main"
        }
      end
      assert!(identity == expected_fixture_identity,
              "P3 rebaseline fixture canonical Git identity drift")
    else
      assert!(identity == current_git_identity, "handoff canonical Git identity drift")
    end

    artifact = exact_object!(package["governing_artifact"], %w[path byte_length sha256], "governing artifact")
    nonempty_string!(artifact["path"], "governing artifact path")
    assert!(artifact["byte_length"].is_a?(Integer) && artifact["byte_length"].positive?, "governing artifact byte length invalid")
    assert!(artifact["sha256"].is_a?(String) && artifact["sha256"].match?(SHA256), "governing artifact SHA-256 invalid")
    if frozen_p3_fixture
      expected_fixture_artifact = if frozen_p3_operation_type == P3_TXC_ROUTE_OPERATION_TYPE
        {
          "path" => P3_TXC_ROUTE_PREINSTALL_TRUTH_PATH,
          "byte_length" => P3_TXC_ROUTE_PREINSTALL_TRUTH_BYTES,
          "sha256" => P3_TXC_ROUTE_PREINSTALL_TRUTH_SHA256
        }
      elsif frozen_p3_operation_type == P3_HPE_ROUTE_OPERATION_TYPE
        {
          "path" => P3_HPE_ROUTE_PREINSTALL_TRUTH_PATH,
          "byte_length" => P3_HPE_ROUTE_PREINSTALL_TRUTH_BYTES,
          "sha256" => P3_HPE_ROUTE_PREINSTALL_TRUTH_SHA256
        }
      else
        {
          "path" => P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_PATH,
          "byte_length" => P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_BYTES,
          "sha256" => P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_SHA256
        }
      end
      assert!(artifact == expected_fixture_artifact,
              "P3 rebaseline fixture governing artifact identity drift")
    else
      artifact_path = Pathname.new(ROOT).join(artifact["path"]).cleanpath
      assert!(artifact_path.to_s.start_with?(ROOT + File::SEPARATOR), "governing artifact escaped repository")
      artifact_bytes = read_regular!(artifact_path, "governing artifact")
      assert!(artifact["byte_length"] == artifact_bytes.bytesize &&
              artifact["sha256"] == Digest::SHA256.hexdigest(artifact_bytes), "governing artifact identity drift")
    end

    request = package["user_request_evidence"]
    if request
      exact_object!(request, %w[source exact_token requested_external_effect], "user request evidence")
      assert!(request["source"] == "CURRENT_DIRECT_USER_MESSAGE" &&
              PROSPECTIVE_TRIGGER_EFFECTS.value?(request["requested_external_effect"]),
              "direct user request binding invalid")
      nonempty_string!(request["exact_token"], "direct user request token")
    end

    evidence = exact_object!(package["validator_evidence"], %w[
      validator command expected_disposition expected_founder_decision_required expected_trigger
      expected_next_action_owner prospective_preflight
    ], "validator evidence")
    assert!(evidence["validator"] == "scripts/validate-founder-delegation-continuity.rb", "validator identity invalid")
    assert!(evidence["command"] == "ruby scripts/validate-founder-delegation-continuity.rb", "validator command invalid")
    nonempty_string!(evidence["expected_disposition"], "expected validator disposition")
    assert!([true, false].include?(evidence["expected_founder_decision_required"]), "expected Founder decision flag invalid")
    nonempty_string!(evidence["expected_trigger"], "expected validator trigger")
    nonempty_string!(evidence["expected_next_action_owner"], "expected validator next owner")
    if evidence["prospective_preflight"]
      preflight = exact_object!(evidence["prospective_preflight"], %w[
        status capability_gap current_disposition current_trigger requested_trigger
        exact_external_effect policy_path policy_byte_length policy_sha256
        ordinary_task_failure_is_not_trigger
      ], "prospective preflight")
      assert!(preflight["status"] == "PASS" && preflight["capability_gap"] == PROSPECTIVE_PREFLIGHT,
              "prospective preflight status invalid")
      assert!(preflight["current_disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
              preflight["current_trigger"] == "NONE" &&
              PROSPECTIVE_TRIGGER_EFFECTS[preflight["requested_trigger"]] == preflight["exact_external_effect"] &&
              preflight["ordinary_task_failure_is_not_trigger"] == true,
              "prospective preflight scope invalid")
      assert!(preflight["policy_path"] == "docs/aios/FOUNDER_DELEGATION_POLICY.md",
              "prospective preflight policy path invalid")
      policy_path = Pathname.new(ROOT).join(preflight["policy_path"])
      policy_bytes = read_regular!(policy_path, "Founder delegation policy")
      assert!(preflight["policy_byte_length"] == policy_bytes.bytesize &&
              preflight["policy_sha256"] == Digest::SHA256.hexdigest(policy_bytes),
              "prospective preflight policy identity drift")
      assert!(policy_bytes.include?(preflight["requested_trigger"]),
              "Founder policy does not bind the prospective reserved effect")
    end
  end

  def validate_terminal_handoff!(package, terminal_receipt_path)
    handoff = package["terminal_next_step_handoff"]
    if handoff.nil?
      assert!(terminal_receipt_path.nil?, "terminal receipt supplied without a terminal handoff binding")
      return
    end

    exact_object!(handoff, %w[
      terminal_level terminal_status receipt_path receipt_byte_length receipt_sha256
      no_automatic_successor_clause_present no_automatic_successor_interpretation
      next_step_user_action_required copy_ready_handoff_required copy_ready_handoff_suppressed
    ], "terminal next-step handoff")
    assert!(%w[TASK ROUTE PHASE GOAL].include?(handoff["terminal_level"]), "terminal handoff level invalid")
    nonempty_string!(handoff["terminal_status"], "terminal handoff status")
    nonempty_string!(handoff["receipt_path"], "terminal handoff receipt path")
    assert!(handoff["receipt_byte_length"].is_a?(Integer) && handoff["receipt_byte_length"].positive?,
            "terminal handoff receipt byte length invalid")
    assert!(handoff["receipt_sha256"].is_a?(String) && handoff["receipt_sha256"].match?(SHA256),
            "terminal handoff receipt SHA-256 invalid")
    assert!(terminal_receipt_path.is_a?(String) && !terminal_receipt_path.empty?,
            "terminal handoff requires an independently supplied terminal receipt")
    receipt_realpath = Pathname.new(terminal_receipt_path).realpath
    assert!(receipt_realpath == Pathname.new(handoff["receipt_path"]).realpath,
            "terminal handoff receipt path drift")
    receipt_bytes = read_regular!(receipt_realpath, "terminal handoff receipt")
    assert!(handoff["receipt_byte_length"] == receipt_bytes.bytesize &&
            handoff["receipt_sha256"] == Digest::SHA256.hexdigest(receipt_bytes),
            "terminal handoff receipt identity drift")
    %w[
      no_automatic_successor_clause_present next_step_user_action_required
      copy_ready_handoff_required copy_ready_handoff_suppressed
    ].each do |key|
      assert!([true, false].include?(handoff[key]), "terminal handoff #{key} must be boolean")
    end
    assert!(handoff["copy_ready_handoff_required"] == true && handoff["copy_ready_handoff_suppressed"] == false,
            "terminal outcome cannot suppress the mandatory next-step handoff")
    if handoff["no_automatic_successor_clause_present"]
      assert!(handoff["no_automatic_successor_interpretation"] == TERMINAL_HANDOFF_INTERPRETATION,
              "no-automatic-successor clause was misinterpreted as suppressing handoff delivery")
    else
      assert!(handoff["no_automatic_successor_interpretation"] == "NOT_APPLICABLE",
              "terminal handoff interpretation must be NOT_APPLICABLE without a no-auto clause")
    end
    if handoff["next_step_user_action_required"]
      assert!(%w[AUTHORIZATION_REQUIRED MATERIAL_REQUIRED].include?(package["action_class"]) &&
              package["current_state"] == "WAITING_USER",
              "terminal next step requiring user action cannot be silenced as NONE_CONTINUE")
    else
      assert!(package["action_class"] == "NONE_CONTINUE" && package["current_state"] != "WAITING_USER",
              "terminal next step inside existing authority must continue without a user request")
    end
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise ValidationError, "terminal handoff receipt unavailable: #{error.message}"
  end

  def validate_control!(truth, evidence, run_validator:)
    raw_control = truth["founder_escalation_control"]
    control_keys = %w[
      schema_version disposition source_event reserved_trigger phase_gate_status
      founder_decision_required next_action_owner next_eligible_action
    ]
    control_keys << "resolved_strategy_decision" if raw_control.is_a?(Hash) &&
      raw_control.key?("resolved_strategy_decision")
    control_keys << "resolved_phase_entry_decision" if raw_control.is_a?(Hash) &&
      raw_control.key?("resolved_phase_entry_decision")
    control = exact_object!(raw_control, control_keys, "canonical Founder escalation control")
    trigger = exact_object!(control["reserved_trigger"], %w[category evidence], "canonical reserved trigger")
    assert!(control["disposition"] == evidence["expected_disposition"], "validator disposition projection drift")
    assert!(control["founder_decision_required"] == evidence["expected_founder_decision_required"], "Founder decision projection drift")
    assert!(trigger["category"] == evidence["expected_trigger"], "Founder trigger projection drift")
    assert!(control["next_action_owner"] == evidence["expected_next_action_owner"], "Founder next-owner projection drift")
    if run_validator
      output, error, status = Open3.capture3("ruby", File.join(ROOT, evidence["validator"]))
      assert!(status.success?, "applicable Founder escalation validator NON_PASS: #{error.strip}")
      validator_disposition = if control["schema_version"] == "founder-escalation-control/v2" &&
        control["next_eligible_action"] == "P3_PHASE_ENTRY_DECISION"
                                "P2_RESEARCH_EXIT_COMPLETE_P3_ENTRY_DECISION_REQUIRED"
                              else
                                control["disposition"]
                              end
      assert!(output.include?("disposition=#{validator_disposition}"),
              "Founder validator output does not bind current disposition")
    end
    control
  end

  def validate_authorization!(package, truth, control, current_user_request_token)
    authorization = exact_object!(package["authorization"], %w[
      authority_layer reserved_trigger proposal_mode recommended_decision grant_scope
      risk_and_reversibility deny_or_defer_effect authorization_expiry_or_consumption_rule
      pass_lifecycle non_pass_lifecycle operation_type
    ], "authorization handoff")
    assert!(%w[FOUNDER_RESERVED APP_FILESYSTEM].include?(authorization["authority_layer"]), "authority layer invalid")
    assert!(%w[CURRENT_CANONICAL_TRIGGER PROSPECTIVE_RESERVED_EFFECT CURRENT_RESOLVED_HOLD_REENTRY NOT_APPLICABLE].include?(authorization["proposal_mode"]), "authorization proposal mode invalid")
    assert!(RECOMMENDED_DECISIONS.include?(authorization["recommended_decision"]), "recommended decision invalid")
    grant = exact_object!(authorization["grant_scope"], %w[operations targets duration budget_or_external_effects], "authorization grant scope")
    %w[operations targets].each { |key| nonempty_strings!(grant[key], "authorization #{key}") }
    structured_txc = authorization["operation_type"] == P3_TXC_ROUTE_OPERATION_TYPE
    %w[duration budget_or_external_effects].each do |key|
      if structured_txc
        structured_json_object_string!(grant[key], "authorization #{key}")
      else
        nonempty_string!(grant[key], "authorization #{key}")
      end
    end
    %w[risk_and_reversibility deny_or_defer_effect authorization_expiry_or_consumption_rule pass_lifecycle non_pass_lifecycle].each do |key|
      if structured_txc
        structured_json_object_string!(authorization[key], "authorization #{key}")
      else
        nonempty_string!(authorization[key], "authorization #{key}")
      end
    end

    evidence = package["validator_evidence"]
    if authorization["authority_layer"] == "FOUNDER_RESERVED"
      assert!(FOUNDER_TRIGGERS.include?(authorization["reserved_trigger"]), "Founder reserved trigger invalid")
      assert!(authorization["proposal_mode"] != "NOT_APPLICABLE", "Founder proposal mode invalid")
      assert!(package["project_authorized"] == "NO" && package["app_filesystem_approval_required"] == "NO",
              "Founder request mixed project and App approval layers")
      if authorization["proposal_mode"] == "CURRENT_CANONICAL_TRIGGER"
        if [P3_HPE_ROUTE_OPERATION_TYPE, P3_TXC_ROUTE_OPERATION_TYPE].include?(
             authorization["operation_type"]
           )
          txc = authorization["operation_type"] == P3_TXC_ROUTE_OPERATION_TYPE
          expected_token = txc ? P3_TXC_ROUTE_TOKEN : P3_HPE_ROUTE_TOKEN
          expected_trigger = txc ? P3_TXC_ROUTE_PRIMARY_TRIGGER : P3_HPE_ROUTE_PRIMARY_TRIGGER
          request = package["user_request_evidence"]
          assert!(control["disposition"] == "FOUNDER_RESERVED_DECISION_REQUIRED" &&
                  control["founder_decision_required"] == true &&
                  control.dig("reserved_trigger", "category") == expected_trigger &&
                  control["next_action_owner"] == "HUMAN_FOUNDER" &&
                  evidence["prospective_preflight"].nil? &&
                  request.is_a?(Hash) && current_user_request_token == expected_token &&
                  request["source"] == "CURRENT_DIRECT_USER_MESSAGE" &&
                  request["exact_token"] == current_user_request_token &&
                  request["requested_external_effect"] == "MATERIAL_SCOPE" &&
                  authorization["reserved_trigger"] == expected_trigger,
                  "P3 rebaseline lacks the exact current trigger and direct Founder token")
        else
          assert!(control["disposition"] == "FOUNDER_DECISION_REQUIRED" &&
                  control["founder_decision_required"] == true &&
                  control.dig("reserved_trigger", "category") == authorization["reserved_trigger"] &&
                  evidence["prospective_preflight"].nil?,
                  "Founder package does not match the current canonical trigger")
        end
      elsif authorization["proposal_mode"] == "PROSPECTIVE_RESERVED_EFFECT"
        assert!(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
                control["founder_decision_required"] == false &&
                control.dig("reserved_trigger", "category") == "NONE" &&
                control["next_action_owner"] == "MASTER_CEO_AGENT",
                "prospective Founder package requires the exact current offline continue state")
        assert!(evidence["prospective_preflight"].is_a?(Hash) &&
                evidence["prospective_preflight"]["status"] == "PASS" &&
                evidence["prospective_preflight"]["capability_gap"] == PROSPECTIVE_PREFLIGHT,
                "prospective Founder request lacks the structured capability-gap preflight")
        request = package["user_request_evidence"]
        assert!(request.is_a?(Hash) && current_user_request_token.is_a?(String) &&
                !current_user_request_token.empty? &&
                request["source"] == "CURRENT_DIRECT_USER_MESSAGE" &&
                request["exact_token"].b == current_user_request_token.b &&
                request["requested_external_effect"] == evidence.dig("prospective_preflight", "exact_external_effect"),
                "prospective Founder request lacks the independently supplied direct-user request binding")
        assert!(authorization["reserved_trigger"] == evidence.dig("prospective_preflight", "requested_trigger"),
                "prospective request may only cover an exact external-effect Founder trigger")
      else
        request = package["user_request_evidence"]
        assert!(control["disposition"] ==
                  "FOUNDER_RESERVED_DECISION_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD" &&
                control["founder_decision_required"] == false &&
                control.dig("reserved_trigger", "category") ==
                  P3_HOST_AUTHORIZED_ROUTE_PRIMARY_TRIGGER &&
                control["next_action_owner"] == "NONE" &&
                evidence["prospective_preflight"].nil?,
                "resolved P3 HOLD reentry does not match the exact canonical control state")
        assert!(request.is_a?(Hash) && current_user_request_token == P3_HOST_AUTHORIZED_ROUTE_TOKEN &&
                request["source"] == "CURRENT_DIRECT_USER_MESSAGE" &&
                request["exact_token"] == current_user_request_token &&
                request["requested_external_effect"] == "MATERIAL_SCOPE" &&
                authorization["reserved_trigger"] == P3_HOST_AUTHORIZED_ROUTE_PRIMARY_TRIGGER &&
                authorization["operation_type"] ==
                  "P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007",
                "resolved P3 HOLD reentry lacks the exact direct-Founder token and two-trigger profile")
      end
      assert!(FOUNDER_OPERATION_TYPES.include?(authorization["operation_type"]), "Founder operation type invalid")
      operation_type = authorization["operation_type"]
      if current_user_request_token == MILESTONE_CURL_TOKEN
        assert!(operation_type == "READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL_REISSUE",
                "a handoff after the exact V1 milestone capability request must use only the closed V2 reissue profile")
      end
      profile = FOUNDER_NETWORK_OPERATION_PROFILES[operation_type]
      assert!(profile, "Founder network operation is not bound to a closed profile")
      if operation_type == "READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL"
        operations = grant["operations"]
        match = operations.is_a?(Array) && operations.first.is_a?(String) &&
                STANDARD_CURL_OPERATION_PATTERN.match(operations.first)
        assert!(match && operations.drop(1) == profile["operation_tail"],
                "standard-curl operation is not bound to one exact acquisition version")
        acquisition_version = match[1]
        proposed_tokens = package["copy_ready_text_or_exact_steps"].scan(FOUNDER_AUTHORIZATION_TOKEN)
        assert!(proposed_tokens.length == 1, "standard-curl handoff must contain one proposed authorization token")
        token_match = /\AAUTHORIZE_P2_BENCHMARK_SOURCE_ACQUISITION_CLEAN_ROOM_CURATOR_(V[1-9][0-9]*)_STANDARD_CURL_V[1-9][0-9]*\z/.match(proposed_tokens.first)
        assert!(token_match && token_match[1] == acquisition_version,
                "standard-curl acquisition version does not match the proposed authorization token")
      else
        assert!(grant["operations"] == profile["operations"],
                "read-only HTTPS operation enum contradicts its exact grant scope")
      end
      if %w[
        READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL
        READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL_REISSUE
        P2_BENCHMARK_SOURCE_FINAL_CANDIDATE_COMPLETION_ENVELOPE
        P2_RECOVERY_CLEAN_ROOM_RESEQUENCING_AND_MINIMAL_ENVELOPE_EXPANSION
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_EXECUTION_INTEGRITY_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SANDBOX_STREAM_LIFECYCLE_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_PRODUCT_PATH_AND_EVIDENCE_CLOSURE_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_QUERY_ENTITY_COVERAGE_ARCHITECTURE_PIVOT_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_B1_ANCHORED_GRAPH_FUSION_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_SEMANTIC_SYMBOL_IMPACT_CONE_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_RECOVERY_ONE_INDEPENDENT_PRODUCT_SELECTOR_DEV_JDK17_SCAN_TIME_COMPILER_ATTRIBUTED_PERSISTED_GRAPH_SLOT_AND_RELOCKED_HELD_SEQUENCE
        P2_EXACT_FROZEN_P2_078_ONE_SHOT_FORMAL_HELD_ROUTE_UNLOCK
        P2_EXACT_FROZEN_P2_078_EVALUATION_AND_EVIDENCE_ADAPTER_PLUS_ONE_SHOT_FORMAL_HELD_SEQUENCE
        P3_SINGLE_AGENT_RUNTIME_AND_MINIMUM_TRUST_PHASE_ENTRY
        P3_ONE_FINAL_HERMETIC_CAPABILITY_LEDGER_ROUTE_AFTER_PREACTIVATION_TERMINAL
        P3_ZERO_AUTHORITY_AGENT_AND_IMMUTABLE_TASK_ACTION_ENVELOPE_PHASE_ROUTE_RESEQUENCING
        P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007
        P3_HOST_PROCESS_ENFORCED_MINIMAL_SLICE_ROUTE_REBASELINE_AFTER_TIK_F1_TERMINAL
        P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY_AFTER_POSTINSTALL_PROTOCOL_ERROR
      ].include?(operation_type)
        proposed_tokens = package["copy_ready_text_or_exact_steps"].scan(FOUNDER_AUTHORIZATION_TOKEN)
        assert!(proposed_tokens == [profile["token"]],
                "milestone-curl handoff must contain the exact non-route capability token")
        assert!(grant["duration"] == profile["duration"] &&
                authorization["authorization_expiry_or_consumption_rule"] == profile["authorization_expiry_or_consumption_rule"] &&
                authorization["pass_lifecycle"] == profile["pass_lifecycle"] &&
                authorization["non_pass_lifecycle"] == profile["non_pass_lifecycle"],
                "milestone-curl lifecycle is not bound to the closed milestone profile")
      end
      if operation_type ==
           "P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007"
        body = package["copy_ready_text_or_exact_steps"].dup.force_encoding("UTF-8")
        assert!(body.valid_encoding?, "P3 host-authorized rebaseline body encoding invalid")
        canonical_body = body.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
        assert!(canonical_body.bytesize == P3_HOST_AUTHORIZED_ROUTE_CANONICAL_BODY_BYTES &&
                Digest::SHA256.hexdigest(canonical_body) ==
                  P3_HOST_AUTHORIZED_ROUTE_CANONICAL_BODY_SHA256 &&
                canonical_body.lines.first.chomp == P3_HOST_AUTHORIZED_ROUTE_TOKEN,
                "P3 host-authorized rebaseline exact Founder body identity drift")
      end
      if operation_type == P3_HPE_ROUTE_OPERATION_TYPE
        body = package["copy_ready_text_or_exact_steps"].dup.force_encoding("UTF-8")
        assert!(body.valid_encoding?, "P3 HPE rebaseline body encoding invalid")
        canonical_body = body.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
        assert!(canonical_body.bytesize == P3_HPE_ROUTE_CANONICAL_BODY_BYTES &&
                Digest::SHA256.hexdigest(canonical_body) ==
                  P3_HPE_ROUTE_CANONICAL_BODY_SHA256 &&
                canonical_body.lines.first.chomp == P3_HPE_ROUTE_TOKEN,
                "P3 HPE rebaseline exact Founder body identity drift")
      end
      if operation_type == P3_TXC_ROUTE_OPERATION_TYPE
        body = package["copy_ready_text_or_exact_steps"].dup.force_encoding("UTF-8")
        assert!(body.valid_encoding?, "P3 TXC rebaseline body encoding invalid")
        canonical_body = body.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
        assert!(canonical_body.bytesize == P3_TXC_ROUTE_CANONICAL_BODY_BYTES &&
                Digest::SHA256.hexdigest(canonical_body) ==
                  P3_TXC_ROUTE_CANONICAL_BODY_SHA256 &&
                canonical_body.lines.first.chomp == P3_TXC_ROUTE_TOKEN,
                "P3 TXC rebaseline exact Founder body identity drift")
        assert!(authorization["risk_and_reversibility"] ==
                  profile["risk_and_reversibility"] &&
                authorization["deny_or_defer_effect"] ==
                  profile["deny_or_defer_effect"],
                "P3 TXC structured risk boundary drift")
      end
      assert!(grant["targets"] == profile["targets"] &&
              grant["budget_or_external_effects"] == profile["budget_or_external_effects"],
              "read-only HTTPS operation enum contradicts its exact grant scope")
    else
      assert!(authorization["reserved_trigger"].nil? && authorization["proposal_mode"] == "NOT_APPLICABLE",
              "App approval cannot claim a Founder trigger")
      assert!(package["project_authorized"] == "YES" && package["app_filesystem_approval_required"] == "YES",
              "App approval must remain inside an existing project authorization")
      assert!(evidence["prospective_preflight"].nil?, "App approval cannot claim a prospective Founder preflight")
      assert!(!package["copy_ready_text_or_exact_steps"].match?(/authorize_[a-z0-9_]+/i),
              "App approval steps cannot contain a Founder authorization token")
      assert!(APP_OPERATION_TYPES.include?(authorization["operation_type"]), "App operation type invalid")
    end

    copy = package["copy_ready_text_or_exact_steps"]
    identity = package["canonical_identity"]
    artifact = package["governing_artifact"]
    required_copy_fragments = [identity["commit"], identity["tree"], artifact["path"],
                               artifact["byte_length"].to_s, artifact["sha256"],
                               authorization["reserved_trigger"].to_s, authorization["operation_type"]] +
                              grant.values_at("operations", "targets").flatten +
                              grant.values_at("duration", "budget_or_external_effects") +
                              authorization.values_at("risk_and_reversibility", "deny_or_defer_effect",
                                                      "authorization_expiry_or_consumption_rule",
                                                      "pass_lifecycle", "non_pass_lifecycle")
    required_copy_fragments = [] if
      authorization["operation_type"] == P3_TXC_ROUTE_OPERATION_TYPE
    required_copy_fragments.reject(&:empty?).each do |fragment|
      present = copy.include?(fragment)
      if authorization["operation_type"] ==
           "P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007" &&
         fragment == artifact["byte_length"].to_s
        grouped_length = artifact["byte_length"].to_s.reverse.scan(/.{1,3}/).join(",").reverse
        present ||= copy.include?(grouped_length)
      end
      assert!(present,
              "copy-ready authorization omitted a declared identity, scope, or lifecycle boundary: #{fragment.inspect}")
    end
  end

  def validate_material!(package)
    material = exact_object!(package["material"], %w[
      required_items why_agent_cannot_obtain_it submission_channel redaction_allowed
      validation_rule acceptable_alternative
    ], "material handoff")
    assert!(material["required_items"].is_a?(Array) && material["required_items"].length == 1,
            "material handoff must request exactly one current item")
    exact_object!(material["required_items"].first, %w[name source_or_version format minimum_completeness], "required material item")
    material["required_items"].first.each { |key, value| nonempty_string!(value, "required material #{key}") }
    %w[why_agent_cannot_obtain_it submission_channel redaction_allowed validation_rule acceptable_alternative].each do |key|
      nonempty_string!(material[key], "material #{key}")
    end
    copy = package["copy_ready_text_or_exact_steps"]
    required_copy_fragments = material["required_items"].first.values +
                              material.values_at("submission_channel", "validation_rule", "acceptable_alternative")
    required_copy_fragments.each do |fragment|
      assert!(copy.include?(fragment), "copy-ready material step omitted a declared requirement")
    end
  end

  def validate_class!(package, truth, run_validator:, current_user_request_token:)
    evidence = package["validator_evidence"]
    control = validate_control!(truth, evidence, run_validator: run_validator)
    case package["action_class"]
    when "NONE_CONTINUE"
      delegated_continue =
        control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
        control["next_action_owner"] == "MASTER_CEO_AGENT"
      next_action = control["next_eligible_action"]
      executable_next_action = next_action.is_a?(String) && !next_action.strip.empty? &&
        !next_action.match?(/\A(?:NONE(?:_|\z)|NO_ENGINEERING_ACTION(?:_|\z))/)
      assert!(delegated_continue && executable_next_action &&
              control["founder_decision_required"] == false &&
              control.dig("reserved_trigger", "category") == "NONE" &&
              evidence["prospective_preflight"].nil?,
              "no-action handoff requires a Master-owned executable Phase continuation")
      assert!(%w[COMPLETE CONTINUING].include?(package["current_state"]), "no-action handoff cannot wait for user")
      assert!(package["project_authorized"] == "YES" && package["app_filesystem_approval_required"] == "NO",
              "no-action handoff authority projection invalid")
      assert!(package["recommended_single_action"] == "NONE", "no-action handoff action must be NONE")
      assert!(package["copy_ready_text_or_exact_steps"] == NO_ACTION_SENTENCE, "no-action sentence drift")
      assert!(package["authorization"].nil? && package["material"].nil?, "no-action handoff cannot contain a request")
      assert!(package["user_request_evidence"].nil?, "no-action handoff cannot retain a user request")
    when "AUTHORIZATION_REQUIRED"
      assert!(package["current_state"] == "WAITING_USER", "authorization handoff must wait for user")
      assert!(package["write_not_executed"] == "YES", "authorization handoff must preserve restricted write/effect")
      nonempty_string!(package["recommended_single_action"], "recommended authorization action")
      nonempty_string!(package["copy_ready_text_or_exact_steps"], "copy-ready authorization text")
      assert!(package["copy_ready_text_or_exact_steps"].bytesize >= 80, "copy-ready authorization text is incomplete")
      assert!(package["material"].nil?, "authorization handoff cannot bundle a material request")
      validate_authorization!(package, truth, control, current_user_request_token)
    when "MATERIAL_REQUIRED"
      assert!(package["current_state"] == "WAITING_USER", "material handoff must wait for user")
      assert!(package["project_authorized"] == "YES" && package["app_filesystem_approval_required"] == "NO",
              "material handoff authority projection invalid")
      assert!(package["write_not_executed"] == "YES", "material handoff must preserve restricted work")
      nonempty_string!(package["recommended_single_action"], "recommended material action")
      nonempty_string!(package["copy_ready_text_or_exact_steps"], "copy-ready material step")
      assert!(package["authorization"].nil?, "material handoff cannot bundle an authorization request")
      assert!(package["user_request_evidence"].nil?, "material handoff cannot claim a Founder request")
      validate_material!(package)
    end
  end

  def marker_count(text, marker)
    text.scan(/^\s*#{Regexp.escape(marker)}:/).length
  end

  def validate_draft!(package, draft)
    text = draft.dup.force_encoding("UTF-8")
    assert!(text.valid_encoding?, "handoff draft encoding invalid")
    assert!(!text.match?(PLACEHOLDER), "handoff draft contains a placeholder")
    assert!(!text.match?(/<!--|-->/), "handoff draft cannot hide action markers in comments")
    assert!(!text.match?(/^\s*(?:另外|另一个|第二个|备选|或者|或请|同时|also|alternatively).*(?:动作|授权|上传|批准|发布|action|authorize|upload|release)/i),
            "handoff draft contains an unstructured second user action")
    MARKERS.each { |marker| assert!(marker_count(text, marker) == 1, "handoff draft must contain exactly one #{marker}") }
    if package["action_class"] == "NONE_CONTINUE"
      assert!(text.include?(NO_ACTION_SENTENCE), "handoff draft omitted the no-action sentence")
      assert!(text.include?("USER_ACTION_REQUIRED: false"), "handoff draft omitted the no-action flag")
      assert!(text.include?("RECOMMENDED_SINGLE_ACTION: NONE"), "handoff draft omitted the no-action decision")
      assert!(text.include?("COPY_READY_TEXT_OR_EXACT_STEPS: #{NO_ACTION_SENTENCE}"), "handoff draft omitted the no-action copy text")
      assert!(text.include?("AGENT_CONTINUATION_AFTER_ACTION: #{package['agent_continuation_after_action']}"),
              "handoff draft omitted the continuing agent action")
      assert!(!text.include?("USER_ACTION_REQUIRED: true"), "no-action draft contains a contradictory user request")
    else
      required_literals = {
        "USER_ACTION_REQUIRED: true" => "user-action flag",
        "RECOMMENDED_SINGLE_ACTION: #{package['recommended_single_action']}" => "recommended action",
        "COPY_READY_TEXT_OR_EXACT_STEPS: #{package['copy_ready_text_or_exact_steps']}" => "copy-ready text or steps",
        "AGENT_CONTINUATION_AFTER_ACTION: #{package['agent_continuation_after_action']}" => "agent continuation"
      }
      required_literals.each { |literal, label| assert!(text.include?(literal), "handoff draft omitted #{label}") }
      assert!(!text.include?("USER_ACTION_REQUIRED: false"), "user-action draft contains a contradictory no-action flag")
      assert!(text.scan(/^\s*RECOMMENDED_SINGLE_ACTION:/).length == 1, "handoff draft contains multiple recommended actions")
      assert!(text.scan(Regexp.new(Regexp.escape(package["copy_ready_text_or_exact_steps"]))).length == 1,
              "handoff draft must contain exactly one copy-ready action block")
      if package.dig("authorization", "authority_layer") == "FOUNDER_RESERVED"
        assert!(text.scan(FOUNDER_AUTHORIZATION_TOKEN).length == 1,
                "Founder handoff draft must contain exactly one authorization token")
      end
    end
  end

  def validate!(truth_path:, package_path:, draft_path:, test_fixture: false, current_user_request_token: nil,
                terminal_receipt_path: nil)
    package = parse_json!(read_regular!(package_path, "handoff package"), "handoff package")
    atomic_fixture = false
    installed_fixture = false
    if ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"] &&
       package.dig("authorization", "operation_type") == P3_TXC_ROUTE_OPERATION_TYPE
      candidate_truth_path = Pathname.new(truth_path)
      expected_candidate_truth = Pathname.new(ROOT).join("docs/aios/truth/project_state.yaml").realpath
      assert!(candidate_truth_path.exist? && !candidate_truth_path.symlink? &&
              candidate_truth_path.realpath == expected_candidate_truth,
              "P3 TXC atomic handoff fixture Truth path drift")
      candidate_truth_bytes = read_regular!(candidate_truth_path, "P3 TXC staging Truth")
      candidate_truth = YAML.safe_load(candidate_truth_bytes, permitted_classes: [],
                                       permitted_symbols: [], aliases: false)
      P3FinalTransactionalRouteValidation.atomic_staging_context!(
        root: ROOT, truth: candidate_truth
      )
      truth_bytes, stderr, status = Open3.capture3(
        "git", "-C", ROOT, "show",
        "#{P3_TXC_ROUTE_PREINSTALL_COMMIT}:#{P3_TXC_ROUTE_PREINSTALL_TRUTH_PATH}"
      )
      assert!(status.success?, "P3 TXC preinstall Truth unavailable: #{stderr.strip}")
      assert!(truth_bytes.bytesize == P3_TXC_ROUTE_PREINSTALL_TRUTH_BYTES &&
              Digest::SHA256.hexdigest(truth_bytes) == P3_TXC_ROUTE_PREINSTALL_TRUTH_SHA256,
              "P3 TXC preinstall Truth byte identity drift")
      atomic_fixture = true
    elsif !test_fixture &&
          package.dig("authorization", "operation_type") == P3_TXC_ROUTE_OPERATION_TYPE
      validate_truth_path!(truth_path)
      installed_truth_bytes = read_regular!(truth_path, "P3 TXC installed Truth")
      installed_truth = YAML.safe_load(installed_truth_bytes, permitted_classes: [],
                                       permitted_symbols: [], aliases: false)
      if installed_truth.dig("current_phase_route", "schema_version") ==
         P3FinalTransactionalRouteValidation::TXC_ROUTE_SCHEMA
        P3FinalTransactionalRouteValidation.validate_truth!(root: ROOT, truth: installed_truth)
        P3FinalTransactionalRouteValidation.txc_installed_context!(
          root: ROOT, truth: installed_truth
        )
        truth_bytes, stderr, status = Open3.capture3(
          "git", "-C", ROOT, "show",
          "#{P3_TXC_ROUTE_PREINSTALL_COMMIT}:#{P3_TXC_ROUTE_PREINSTALL_TRUTH_PATH}"
        )
        assert!(status.success?, "P3 TXC installed replay baseline Truth unavailable: #{stderr.strip}")
        assert!(truth_bytes.bytesize == P3_TXC_ROUTE_PREINSTALL_TRUTH_BYTES &&
                Digest::SHA256.hexdigest(truth_bytes) == P3_TXC_ROUTE_PREINSTALL_TRUTH_SHA256,
                "P3 TXC installed replay baseline Truth identity drift")
        installed_fixture = true
      else
        truth_bytes = installed_truth_bytes
      end
    else
      validate_truth_path!(truth_path) unless test_fixture
      truth_bytes = read_regular!(truth_path, "canonical Truth")
    end
    effective_fixture = test_fixture || atomic_fixture || installed_fixture
    truth = YAML.safe_load(truth_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert!(truth.is_a?(Hash), "canonical Truth must be a mapping")
    draft = read_regular!(draft_path, "handoff draft")
    validate_common!(package, truth_bytes, test_fixture: effective_fixture)
    validate_terminal_handoff!(package, terminal_receipt_path)
    validate_class!(package, truth, run_validator: !effective_fixture,
                    current_user_request_token: current_user_request_token)
    validate_draft!(package, draft)
    true
  end
end

if $PROGRAM_NAME == __FILE__
  options = { truth_path: FounderActionHandoff::DEFAULT_TRUTH }
  OptionParser.new do |parser|
    parser.on("--truth PATH") { |path| options[:truth_path] = File.expand_path(path) }
    parser.on("--package PATH") { |path| options[:package_path] = File.expand_path(path) }
    parser.on("--draft PATH") { |path| options[:draft_path] = File.expand_path(path) }
    parser.on("--current-user-request-token TOKEN") { |token| options[:current_user_request_token] = token }
    parser.on("--terminal-receipt PATH") { |path| options[:terminal_receipt_path] = File.expand_path(path) }
  end.parse!

  begin
    FounderActionHandoff.assert!(options[:package_path], "--package is required")
    FounderActionHandoff.assert!(options[:draft_path], "--draft is required")
    FounderActionHandoff.validate!(**options)
    puts "FOUNDER_ACTION_HANDOFF_CHECK: PASS"
  rescue FounderActionHandoff::ValidationError, KeyError, TypeError => error
    warn "FOUNDER_ACTION_HANDOFF_CHECK: NON_PASS #{error.message}"
    exit 1
  end
end

#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

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
    P2_EXACT_FROZEN_P2_078_EVALUATION_ADAPTER_AND_ONE_SHOT_FORMAL_HELD_SEQUENCE
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
  P2_EVALUATION_ADAPTER_TOKEN = "AUTHORIZE_P2_EXACT_FROZEN_P2_078_EVALUATION_ADAPTER_AND_ONE_SHOT_FORMAL_HELD_SEQUENCE_V1"
  P2_EVALUATION_ADAPTER_OPERATION = "Add exactly two ordered Tasks after terminal P2-079: one evaluation-infrastructure adapter Task for the exact frozen P2-078 candidate, followed only after independent adapter acceptance by one immutable-candidate one-shot formal HELD Task; add no Product DEV implementation attempt"
  P2_EVALUATION_ADAPTER_PERMISSION = "Permit exact P2-078 candidate commit e0c0f4d78b64b95b359746ab7c2fec4beed4311f tree 405bd708c7e724b792c37b9eb568e492cb94c70d and its manifest-bound Evidence as read-only execution input while preserving P2-078 and P2-079 as terminal NON_PASS; permit new evaluator-adapter source only under evaluation-harness, with no product-source mutation, candidate retuning, dataset, split, oracle, metric, threshold, ranking or parameter mutation"
  P2_EVALUATION_ADAPTER_PREFLIGHT = "Before any HELD read, independently author and mechanically validate on canonical main one split-neutral evaluator adapter that accepts explicit task-card input without hard-coded DEV cardinality or DEV-only paths; prove the frozen 8-card DEV and 4-card HELD schemas using only non-HELD synthetic fixtures, exact authority-bound roots, closed runtime identities, sandboxed write confinement and create-once Evidence"
  P2_EVALUATION_ADAPTER_COMPATIBILITY = "After the adapter is frozen and before HELD access, permit exactly one non-selective DEV compatibility replay against the accepted P2-069 eight DEV cards and exact P2-078 candidate; it must byte-exact reproduce the already recorded P2-078 DEV task outputs and aggregates, cannot change candidate or adapter after observing results, and any mismatch is terminal NON_PASS with zero HELD reads"
  P2_EVALUATION_ADAPTER_FORMAL = "Adapter Task PASS freezes and may integrate only the evaluator adapter, then unlocks exactly one formal HELD Task; before the first HELD read freeze the exact candidate, adapter, dataset, split, oracle, metric, threshold, ranking, parameters, commands and Evidence, then execute exactly one untouched four-task HELD dispatch with no mutation, retuning, replacement, second candidate or rerun"
  P2_EVALUATION_ADAPTER_TARGET = "Local SourceLens canonical main, exact frozen P2-078 candidate and manifest-bound Evidence, accepted P2-069 baseline and source pack, at most one active Task branch and worktree at a time, and create-once Evidence under /Users/lijunpeng/Developer/.sourcelens-audit; no network, Provider, Secret, remote write, production, public release, deletion, existing database modification, P3 entry or long-term Goal termination"
  P2_EVALUATION_ADAPTER_DURATION = "Until the unchanged P2 Exit Gate is independently ACCEPTED, either of the exact two Tasks reaches terminal NON_PASS, Founder explicitly revokes this route, or a terminal safety condition occurs"
  P2_EVALUATION_ADAPTER_BUDGET = "Raise the non-resettable cumulative P2 Phase envelope from 24 engineering tasks, 720 engineering hours and 180 calendar days to 26 engineering tasks, 784 engineering hours and 196 calendar days; preserve consumed 24 tasks, 720 hours and 180 days, leaving exactly two 32-hour 8-day slots and no other P2 capacity"
  P2_EVALUATION_ADAPTER_RISK = "The material risks are read-only execution of one terminal candidate, one new evaluator adapter and 64 engineering hours of added capacity; risk is bounded by immutable product bytes, byte-exact DEV compatibility, zero pre-PASS HELD reads, one formal dispatch and an unchanged Exit Gate, and the expansion is reversible only before the first new Task is activated"
  P2_EVALUATION_ADAPTER_DENY = "Do not create a new Task, read P2-078 rejected bytes or read HELD; keep P2 delivery at 25 percent, strict P2 progress at 0 percent, P2 and the long-term Goal active, P3 HOLD, and all P2-070 through P2-079 terminal facts immutable"
  P2_EVALUATION_ADAPTER_CONSUMPTION = "Each activated Task consumes exactly one 32-hour 8-day slot; adapter NON_PASS leaves formal HELD locked, formal HELD NON_PASS integrates no product candidate, either NON_PASS ends this route, and neither outcome creates a replacement, remediation chain, automatic successor or another Product DEV attempt"
  P2_EVALUATION_ADAPTER_PASS = "Adapter Task PASS permits integration of only the split-neutral evaluator adapter and unlocks one formal HELD Task with zero delivery or strict progress credit; formal HELD PASS permits byte-exact integration of only the frozen P2-078 product candidate, accepts the candidate-admission and formal-HELD delivery nodes, and makes the unchanged P2 Exit Gate eligible for independent acceptance, but does not authorize P3 entry or long-term Goal closure"
  P2_EVALUATION_ADAPTER_NON_PASS = "Any NON_PASS preserves exact terminal Evidence, contributes zero strict P2 progress, integrates no product candidate, keeps P2 and the long-term Goal active and P3 HOLD, and requires a new Founder Phase strategy decision rather than an automatic retry"
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
    "P2_EXACT_FROZEN_P2_078_EVALUATION_ADAPTER_AND_ONE_SHOT_FORMAL_HELD_SEQUENCE" => {
      "operations" => [
        P2_EVALUATION_ADAPTER_OPERATION,
        P2_EVALUATION_ADAPTER_PERMISSION,
        P2_EVALUATION_ADAPTER_PREFLIGHT,
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
    }
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

  def validate_common!(package, truth_bytes)
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
    assert!(identity == current_git_identity, "handoff canonical Git identity drift")

    artifact = exact_object!(package["governing_artifact"], %w[path byte_length sha256], "governing artifact")
    nonempty_string!(artifact["path"], "governing artifact path")
    assert!(artifact["byte_length"].is_a?(Integer) && artifact["byte_length"].positive?, "governing artifact byte length invalid")
    assert!(artifact["sha256"].is_a?(String) && artifact["sha256"].match?(SHA256), "governing artifact SHA-256 invalid")
    artifact_path = Pathname.new(ROOT).join(artifact["path"]).cleanpath
    assert!(artifact_path.to_s.start_with?(ROOT + File::SEPARATOR), "governing artifact escaped repository")
    artifact_bytes = read_regular!(artifact_path, "governing artifact")
    assert!(artifact["byte_length"] == artifact_bytes.bytesize &&
            artifact["sha256"] == Digest::SHA256.hexdigest(artifact_bytes), "governing artifact identity drift")

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
    control = exact_object!(truth["founder_escalation_control"], %w[
      schema_version disposition source_event reserved_trigger phase_gate_status
      founder_decision_required next_action_owner next_eligible_action
    ], "canonical Founder escalation control")
    trigger = exact_object!(control["reserved_trigger"], %w[category evidence], "canonical reserved trigger")
    assert!(control["disposition"] == evidence["expected_disposition"], "validator disposition projection drift")
    assert!(control["founder_decision_required"] == evidence["expected_founder_decision_required"], "Founder decision projection drift")
    assert!(trigger["category"] == evidence["expected_trigger"], "Founder trigger projection drift")
    assert!(control["next_action_owner"] == evidence["expected_next_action_owner"], "Founder next-owner projection drift")
    if run_validator
      output, error, status = Open3.capture3("ruby", File.join(ROOT, evidence["validator"]))
      assert!(status.success?, "applicable Founder escalation validator NON_PASS: #{error.strip}")
      assert!(output.include?("disposition=#{control['disposition']}"), "Founder validator output does not bind current disposition")
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
    assert!(%w[CURRENT_CANONICAL_TRIGGER PROSPECTIVE_RESERVED_EFFECT NOT_APPLICABLE].include?(authorization["proposal_mode"]), "authorization proposal mode invalid")
    assert!(RECOMMENDED_DECISIONS.include?(authorization["recommended_decision"]), "recommended decision invalid")
    grant = exact_object!(authorization["grant_scope"], %w[operations targets duration budget_or_external_effects], "authorization grant scope")
    %w[operations targets].each { |key| nonempty_strings!(grant[key], "authorization #{key}") }
    %w[duration budget_or_external_effects].each { |key| nonempty_string!(grant[key], "authorization #{key}") }
    %w[risk_and_reversibility deny_or_defer_effect authorization_expiry_or_consumption_rule pass_lifecycle non_pass_lifecycle].each do |key|
      nonempty_string!(authorization[key], "authorization #{key}")
    end

    evidence = package["validator_evidence"]
    if authorization["authority_layer"] == "FOUNDER_RESERVED"
      assert!(FOUNDER_TRIGGERS.include?(authorization["reserved_trigger"]), "Founder reserved trigger invalid")
      assert!(authorization["proposal_mode"] != "NOT_APPLICABLE", "Founder proposal mode invalid")
      assert!(package["project_authorized"] == "NO" && package["app_filesystem_approval_required"] == "NO",
              "Founder request mixed project and App approval layers")
      if authorization["proposal_mode"] == "CURRENT_CANONICAL_TRIGGER"
        assert!(control["disposition"] == "FOUNDER_DECISION_REQUIRED" &&
                control["founder_decision_required"] == true &&
                control.dig("reserved_trigger", "category") == authorization["reserved_trigger"] &&
                evidence["prospective_preflight"].nil?,
                "Founder package does not match the current canonical trigger")
      else
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
        P2_EXACT_FROZEN_P2_078_EVALUATION_ADAPTER_AND_ONE_SHOT_FORMAL_HELD_SEQUENCE
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
    required_copy_fragments.reject(&:empty?).each do |fragment|
      assert!(copy.include?(fragment), "copy-ready authorization omitted a declared identity, scope, or lifecycle boundary")
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
      assert!(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
              control["founder_decision_required"] == false &&
              control.dig("reserved_trigger", "category") == "NONE" &&
              control["next_action_owner"] == "MASTER_CEO_AGENT" &&
              evidence["prospective_preflight"].nil?,
              "no-action handoff cannot silence a Founder action or prospective reserved effect")
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
    validate_truth_path!(truth_path) unless test_fixture
    truth_bytes = read_regular!(truth_path, "canonical Truth")
    truth = YAML.safe_load(truth_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert!(truth.is_a?(Hash), "canonical Truth must be a mapping")
    package = parse_json!(read_regular!(package_path, "handoff package"), "handoff package")
    draft = read_regular!(draft_path, "handoff draft")
    validate_common!(package, truth_bytes)
    validate_terminal_handoff!(package, terminal_receipt_path)
    validate_class!(package, truth, run_validator: !test_fixture,
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

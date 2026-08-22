# SourceLens AIOS Strategic Constitution

- Version: `3.2`
- Status: `FROZEN`
- Effective date: 2026-08-23
- Owner: Human Founder

## 1. Positioning

SourceLens AIOS is a trustworthy autonomous-agent infrastructure research platform that uses software engineering as its first validation environment.

It studies and builds the capabilities required for an Agent to understand a complex environment, execute a real task, verify the result independently, retain evidence and improve under controlled experiments.

The long-term direction is an Agent Organization Operating System. That is a three-to-five-year destination, not the first product.

## 2. Year-one objective

Build and scientifically evaluate one trustworthy software-engineering Agent.

The only year-one product loop is:

```text
Repository revision + Issue
  -> Environment Understanding
  -> Planning
  -> Isolated Execution
  -> Testing
  -> Independent Verification
  -> Risk and Rollback Evidence
  -> Patch Evidence Package
  -> Human Approval
```

A generated patch is not a successful outcome. Success requires an independently verified, traceable and reversible patch package.

## 3. Year-one ICP and JTBD

Primary ICP:

A repository maintainer or responsible engineer handling bounded, reproducible maintenance issues in a buildable Java or Java/TypeScript repository, especially when the codebase is unfamiliar, inherited or costly to review manually.

JTBD:

When I receive a concrete issue in a repository I do not fully understand, locate the relevant code, propose the smallest defensible change, execute verification in isolation, and give me enough evidence and rollback information to approve or reject the patch safely.

## 4. Non-goals for year one

- A generic Agent framework or chatbot platform.
- An AI company simulator or organization runtime.
- Autonomous production merge or unsupervised remote writes.
- Multi-tenant SaaS, enterprise RBAC, SSO or billing.
- GitHub App, webhook and private-repository expansion as a mainline objective.
- Broad CI diagnosis, PR review, dashboard or admin-console expansion.
- Support for every programming language.
- Model pretraining, RLHF infrastructure or a new foundation model.
- Production-readiness claims without production evidence.

## 5. Core assets

### Core Asset 1: Repository Intelligence and Context Selection

Task-conditioned understanding of repository structure, symbols, relations, history and evidence. This is the primary product moat, not a generic runtime framework.

### Core Asset 2: Agent Evaluation and Failure Data

Versioned tasks, environment snapshots, traces, baseline runs, hidden evaluations, failure taxonomy and reproducible research artifacts.

### Core Asset 3: Trust and Patch Evidence Protocol

Immutable repository identity, tool permissions, isolated execution, independent verification, approval, audit, rollback and per-patch evidence custody.

## 6. Product architecture

```text
Organization Layer                 future research
Trust and Independent Verification year-one hardening
Evaluation and Research Foundation scientific control plane
Memory and Learning                only after measured baseline
Single-Agent Runtime               durable task execution
Environment Intelligence           repository understanding moat
Software Engineering Environment   first validation domain
```

Evaluation is not a late feature. Minimum trust is not a late feature. Both exist before autonomous write execution.

## 7. Patch Evidence Package contract

Every candidate package must eventually bind:

- task and issue identity;
- canonical repository identity, base commit and tree hash;
- environment and dependency snapshot;
- repository evidence and selected context;
- decision rationale, not hidden chain-of-thought;
- planned and actual actions;
- patch content and patch hash;
- tests before and after, commands, exit codes and logs;
- independent verifier identity and verdict;
- policy, risk and human-approval state;
- rollback point, inverse action or disposable-workspace receipt;
- checksums for all retained artifacts.

A Patch Evidence Package is task-specific correctness evidence. A Release Evidence Package is platform regression evidence. They are different artifacts and neither substitutes for the other.

## 8. Success definition

Primary metric: `Verified Task Success Rate`.

A task counts as verified success only when the patch applies to the frozen base revision, required tests and regressions pass, the independent evaluator accepts it, no forbidden action occurred, the Evidence Package is complete, and rollback evidence is valid.

Guardrails:

- unsafe-action rate;
- cost per verified success;
- end-to-end latency;
- human intervention count;
- evidence completeness;
- replay/reproduction rate.

P0 defines measurement. P1 measures the baseline and then locks practical target deltas, confidence intervals and budgets. Statistical significance without practical effect is insufficient.

## 9. Phase route

| Phase | Objective | Required exit evidence |
| --- | --- | --- |
| P0 Strategic Foundation | Freeze truth, scope, migration and evaluation contracts | Canonical state, migration ledger, baseline protocol, reviewable worktree plan |
| P1 Agent Evaluation and Research Foundation | Build task/evaluator/trace/baseline infrastructure | Reproducible baseline suite and hidden-set protocol |
| P2 Repository Intelligence Research | Establish a representative Repository Context Benchmark and truthfully determine, within the preregistered budget, whether task-conditioned Repository Intelligence materially outperforms a simple retrieval baseline | Independently accepted representative benchmark and B1 baseline, plus reproducible terminal evidence that determines whether any frozen candidate met the preregistered superiority criterion within the frozen budget |
| P3 Single-Agent Runtime + Minimum Trust | Build and independently validate one host-authorized transactional Single-Agent workflow in which every Agent output is non-authoritative proposal data and can neither create authority nor directly supply an executable, handler, filesystem path, environment value, credential, network target, or unrestricted argument map. The trusted host alone derives each invocation from an immutable task/workflow specification, the accepted P3-001 checkpoint state, a compile-time closed action algebra, content-addressed host-custody handles, and positive state/resource/budget authorization; it durably records an invocation-local authorization decision and dispatch intent before any effect, executes only inside a disposable OS-enforced isolation boundary, and blocks checkpoint advancement until exactly one append-only terminal invocation trace has been durably accepted or crash-reconciled. A generic tool registry, dynamic grant, broker/interpreter, finite semantic denylist, best-effort post-effect audit, network/Provider/Secret/remote/production/public effect, or P4 entry is not permitted. | Resume, isolation, permission and trace tests |
| P4 Software Engineer Agent Alpha | Complete real issue-to-evidence flow | Verified patches on controlled real tasks |
| P5 Trustworthy Execution Hardening | Harden sandbox, policy, approval, risk and rollback | Adversarial and failure-recovery evidence |
| P6 Reliability Research | Establish SourceLens-Bench and failure taxonomy | Reproducible benchmark report |
| P7 Memory and Learning Research | Test working/project/experience memory | A/B or ablation evidence of practical improvement |
| P8 Multi-Agent Organization Research | Compare single and multi-Agent strategies | Multi-Agent retained only if it wins on a declared tradeoff |
| P9 Organization Runtime | Build identity, delegation and organization memory | Governed organization experiments |
| P10 Platformization | Extract SDK/tool/environment protocols | Second implementation can use the platform |
| P11 Second-Domain Validation | Test whether abstractions generalize | Evidence from a second domain |
| P12 AI Organization OS | Productize governed autonomous organizations | Long-term outcome, not a current commitment |

Phase numbers in pre-v2.3 documents are historical and must not be mixed with this route.

P2 has two mechanically separate conclusions. Its research Exit may complete with
`COMPLETE_RESEARCH_NON_PASS_CAPABILITY_NOT_ACCEPTED` when the representative benchmark and B1 baseline are independently accepted and the complete, reproducible terminal record establishes that no candidate met the frozen superiority criterion within the frozen budget. That status is an honest bounded research conclusion, not product capability acceptance. The original capability Gate
`CONTEXT_BENCHMARK_BEATS_SIMPLE_RETRIEVAL_BASELINES` remains `MISSING_NOT_ACCEPTED`, strict capability progress remains `0%`, rejected candidates remain terminal `NON_PASS`, and no candidate may be integrated under that research conclusion. P3 remains ineligible for execution until a separate Founder Phase-entry decision.

## 9A. P3 v3.1 trusted-host TCB transactional execution authority

This section supersedes only the detailed P3 objective and strict Exit Gate represented by the legacy-compatible P3 row in section 9. The section 9 row remains an aggregate compatibility projection for the existing global governance validator; it cannot independently accept P3, schedule work, or override the structured current Route.

The create-once Founder decision `AUTHORIZE_P3_TRUSTED_HOST_TCB_TRANSACTIONAL_EXECUTION_OBJECTIVE_EXIT_GATE_AND_CLEAN_ROOM_FINAL_ROUTE_V1` installs this section from canonical baseline `f6a1c69dc28b399e0bc7562a9d591b6b11b953be`, tree `6326179fd4d879b4ba2f4e92ccc59f27144aad41`. It preserves the terminal TXCR route, Candidate 2 non-integration and every earlier P3 terminal outcome as immutable accounting. The strategic installation adds no engineering, delivery or strict Exit credit.

The P3 objective is `TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION`. SourceLens must build and independently validate one trusted-host-owned, durable, transactional Single-Agent coordinator for the compile-time closed `SHA256_READ_ONLY_CUSTODY_V1` workflow. Agent output cannot create authority or choose an executable, path, argv, environment, Docker option, credential, network target, resource limit, handler or unrestricted map. The host exclusively owns positive authorization, an immutable authorization anchor separate from the mutable invocation row, pre-effect intent durability, invocation-scoped checkpoint reservation, stage-aware cleanup, crash/orphan reconciliation, terminal trace acceptance, checkpoint gating, content-addressed custody and Evidence.

The explicit trusted computing base is the local OS/kernel, current SourceLens trusted-host process, host-controlled durable database, sealed host custody root, exact Docker CLI executable, Docker Unix socket, Docker Desktop daemon and pinned local OCI image. The protected threat set includes arbitrary Agent proposal data, hostile workflow payloads, duplicate/replayed proposals, crash/timeout/partial I/O, container network/filesystem/permission/resource acquisition, non-TCB path/content drift and forged or inconsistent invocation/checkpoint/terminal state. Root/admin, a same-user process with TCB write authority, a competing Docker client with equivalent daemon authority, compromised Docker/CLI/socket, kernel compromise and physical-host compromise are TCB compromise and are outside the P3 claim. This boundary must be disclosed in every Product and Audit claim; excluded threats may not be reported as tested or prevented.

Pinned Docker Desktop OCI remains only an external containment substrate and receives no Task, business-action, source-custody or checkpoint authority. A privileged broker, separate OS principal, stronger isolation platform, generic runtime, dynamic tool registry, open shell or multi-tool platform is outside this P3 route. Those stronger-host-adversary capabilities require a later Phase decision rather than expansion of P3.

The strict P3 Exit Gate is `TRUSTED_HOST_TCB_DURABLE_TRANSACTIONAL_EXECUTION_WITH_PROCESS_REAL_CONTAINMENT`. It is complete only when one frozen candidate has independent `ACCEPTED` Evidence for every structured required item below:

- `AUTHORIZATION_AND_INTENT_DURABILITY`
- `CRASH_ORPHAN_RECONCILIATION_AND_RESUME`
- `EXACTLY_ONE_TERMINAL_TRACE_AND_CHECKPOINT_GATE`
- `TRUSTED_HOST_TCB_PROCESS_REAL_CONTAINMENT_ATTESTATION`

The legacy aggregate item `RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS` is a conservative compatibility projection of these four requirements. It must remain `MISSING` until all four current items are accepted from the same frozen candidate and may then be accepted only by the one-shot Audit receipt. Neither the compatibility projection nor prose wording is a lifecycle authority.

## 9B. P3 v3.2 task-wide reservation frontier authority

This section supersedes only the detailed P3 strict Exit Gate and transactional reservation semantics in section 9A. It preserves the P3 objective `TRUSTED_HOST_TCB_TRANSACTIONAL_SINGLE_AGENT_EXECUTION`, the full section 9A trusted computing base, included and excluded threat boundary, the compile-time closed `SHA256_READ_ONLY_CUSTODY_V1` workflow, accepted P3-001 checkpoint semantics, P4 HOLD and the active Long-term Goal. The create-once Founder decision `AUTHORIZE_P3_TASK_WIDE_RESERVATION_FRONTIER_TRANSACTIONAL_EXECUTION_FOUNDATION_PRODUCT_AND_ONE_SHOT_AUDIT_ROUTE_V1` is the append-only ADR for this change from canonical commit `7b01acd118d45db89a51efe5090543348d236383`, tree `83c6385d299b5149ce63fd0a8abede299eb7653a`. Strategic installation has zero engineering, delivery or strict Exit credit.

Before P3-001 has accepted a first checkpoint head, distinct positively authorized workflow proposals may compete for the same task. The trusted host must arbitrate that competition through one `task_id`-only active pre-effect reservation frontier plus invocation-bound append-only reservation history. Exactly one invocation may own the active frontier and enter effect; every cross-workflow or cross-step loser must fail closed before any worker or Docker effect. A successful accepted terminal may establish the first P3-001 checkpoint and thereby bind the workflow. A failed terminal may release the frontier only after terminal acceptance, confirmed cleanup and proof that no checkpoint exists. Prebinding one workflow when the task is created, deleting legitimate proposal competition or otherwise narrowing accepted P3-001 behavior is forbidden.

The strict P3 Exit Gate is strengthened to `TRUSTED_HOST_TCB_TASK_WIDE_TRANSACTIONAL_EXECUTION_WITH_PROCESS_REAL_CONTAINMENT`. It is complete only when one frozen Product candidate has current, hash-bound and independently `ACCEPTED` Evidence for all five required items:

- `TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER`
- `AUTHORIZATION_AND_INTENT_DURABILITY`
- `CRASH_ORPHAN_RECONCILIATION_AND_RESUME`
- `EXACTLY_ONE_TERMINAL_TRACE_AND_CHECKPOINT_GATE`
- `TRUSTED_HOST_TCB_PROCESS_REAL_CONTAINMENT_ATTESTATION`

The reservation acquire, verification, transition and release operations must be serialized with the same task-row lock and durable transaction. Terminal replay is invocation-local: replay of invocation A must validate A's immutable anchor, history, terminal and checkpoint identity without requiring the task-wide active frontier to be empty and without deleting, mutating or blocking a valid later reservation B. The legacy aggregate item `RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS` remains only a conservative compatibility projection and cannot become `ACCEPTED` until all five current items from the same frozen Product candidate are accepted by the one-shot Audit.

The only authorized implementation sequence is `P3_TASK_WIDE_RESERVATION_FRONTIER_TRANSACTIONAL_EXECUTION_ROUTE_V1`: one non-product executable Foundation, one clean-room Product and one one-shot Audit. Foundation acceptance creates no delivery or strict Exit credit and only unlocks Product. Product acceptance and canonical integration create delivery 75% and only unlock Audit. Audit PASS creates P3 delivery 100% and strict Exit 100% eligibility awaiting the separate Founder P3 Phase Gate; it never authorizes P4 entry. Any Foundation, Product or Audit `NON_PASS` terminates this Route without a second Foundation, Candidate 3, second repair, third review, second formal dispatch, successor, replacement, remediation, V2/V3 chain or rerun-to-pass.

## 10. Research artifacts

Every major phase must leave a reproducible artifact containing hypothesis, dataset version, environment snapshot, baseline, configuration, run IDs, raw metrics, failure taxonomy, effect size, cost, conclusion and reproduction command.

Required studies include:

- P1 Evaluation Foundation report;
- P2 Repository Context Benchmark;
- P6 Software-Agent Reliability report;
- P7 Memory Ablation study;
- P8 Single-Agent versus Multi-Agent study.

## 11. Stop conditions

A phase or experiment stops when:

- it fails to improve the declared baseline within the predeclared budget;
- cost, latency or safety exceeds its guardrail;
- added complexity has no measurable benefit;
- task representativeness or user value cannot be defended;
- evidence is not reproducible;
- it depends on an unclosed higher-severity trust blocker.

Stopping is a valid research result. It must not be hidden by adding features.

## 12. Change control

Only the Human Founder may change mission, primary ICP, year-one outcome or long-term direction. Any change requires a new constitution version and an append-only ADR. Constitution v2.4 is bound to the create-once Founder decision `AUTHORIZE_P2_RESEARCH_NON_PASS_COMPLETION_AND_PHASE_EXIT_REBASELINE_V1`; that decision is the append-only ADR for this P2 Phase-route change. Constitution v2.6 is bound to the create-once Founder decision `AUTHORIZE_P3_HOST_OWNED_FIXED_STATE_WORKFLOW_MINIMAL_ATOMIC_STRATEGY_INSTALLATION_AFTER_EVIDENCE_ONLY_NON_PASS_V1`; that decision formally amended only the P3 Objective and installed the now-exhausted host-owned fixed-state workflow route while preserving the strict P3 Exit Gate, P4 HOLD and Long-term Goal ACTIVE boundaries. Constitution v2.7 is bound to the create-once Founder decision `AUTHORIZE_P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007_V1`; that decision is the append-only ADR for replacing only the exhausted P3 implementation assumption with the host-authorized transactional trust-boundary Objective and three-stage route, while keeping mission, ICP, year-one outcome, strict P3 Exit Gate, P4 HOLD and Long-term Goal ACTIVE unchanged. Constitution v2.8 is bound to the create-once Founder decision `AUTHORIZE_P3_TRUSTED_INVOCATION_KERNEL_PROCESS_REAL_CLEAN_ROOM_ROUTE_REBASELINE_V1`; that decision preserves the v2.7 mission, ICP, year-one outcome, P3 Objective and strict Exit Gate while authorizing one architecturally distinct process-real clean-room Foundation, Product and one-shot Audit route with non-resettable capacity and no rejected-lineage reuse. Constitution v3.0 preserves the P0-P2 accepted facts, P3-001 semantics, P4-P12 order and active Long-term Goal while installing the transactional coordinator plus external OCI attestation objective and strict Gate. Its original append-only ADR is `AUTHORIZE_P3_TRANSACTIONAL_COORDINATOR_EXTERNAL_OCI_ATTESTATION_OBJECTIVE_EXIT_GATE_AND_ATOMIC_STAGED_ROUTE_REBASELINE_V1`; after the exact post-install protocol defect and required revert, the create-once decision `AUTHORIZE_P3_TXC_CONTROL_PLANE_RECOVERY_AND_DIRECT_PRODUCT_ROUTE_REENTRY_AFTER_POSTINSTALL_PROTOCOL_ERROR_V1` re-installs the same v3.0 strategic semantics from the new exact baseline and authorizes only the closed recovery plus direct two-stage reentry. Constitution v3.1 is bound to the create-once Founder decision `AUTHORIZE_P3_TRUSTED_HOST_TCB_TRANSACTIONAL_EXECUTION_OBJECTIVE_EXIT_GATE_AND_CLEAN_ROOM_FINAL_ROUTE_V1`; it formally narrows the P3 trust claim to an explicit single-host TCB, retains strict Agent/workload/crash/trace guarantees, changes the final containment item to process-real attestation inside that TCB, accepts the disclosed same-host-authority residual risk, and authorizes one clean-room Product followed by one one-shot Audit without a Foundation Task. Constitution v3.2 is bound to the create-once Founder decision `AUTHORIZE_P3_TASK_WIDE_RESERVATION_FRONTIER_TRANSACTIONAL_EXECUTION_FOUNDATION_PRODUCT_AND_ONE_SHOT_AUDIT_ROUTE_V1`; it preserves the v3.1 Objective and TCB while strengthening the strict Gate with a task-wide pre-effect reservation frontier, retaining P3-001 workflow-binding semantics and authorizing only the Foundation, Product and one-shot Audit sequence with non-resettable capacity. Constitution v2.5 was never installed and has no authority. Routine implementation choices do not modify this document.

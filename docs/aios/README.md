# SourceLens AIOS Authority Index

This directory is the canonical control plane for the SourceLens AIOS migration.

## Domain authority

| Domain | Authority |
| --- | --- |
| mission, ICP, year-one outcome, non-goals and phase route | `STRATEGIC_CONSTITUTION.md` |
| current mutable facts, current phase status, evidence pointers and active blockers | `truth/project_state.yaml` |
| roles, authority, task lifecycle, memory and review | `MASTER_EXECUTION_PROTOCOL.md` |
| TaskSpec, baselines, datasets, metrics and research artifacts | `EVALUATION_PROTOCOL.md` |
| inherited-asset disposition | `MIGRATION_LEDGER.yaml` |
| accepted decision rationale | append-only ADRs |
| historical bounded P0 task contracts | `tasks/P0-04A_TRUTH_CONTAINMENT.yaml`, `tasks/P0-04B_SLICE_F_GATE_REPAIR.yaml`, `tasks/P0-04C_AUTHORITY_DECONTAMINATION.yaml`, `tasks/P0-05_BASELINE_SLICING.yaml` |
| current P1 task contract | `tasks/P1-001_EVALUATION_HARNESS.yaml` |
| P0 Founder Gate current decision | external hash-bound Decision Record referenced by `truth/project_state.yaml` |
| P1 entry authorization | external append-only Founder authorization referenced by `truth/project_state.yaml` |

There is no global "earlier file wins" rule. Each document is authoritative only in its domain. The Truth Registry may mirror strategic values for machines but cannot change them. Historical status boards, progress logs, handoffs and pre-v2.3 roadmaps override none of these domains.

Legacy material is excluded from default Agent context. It may be opened only when an active Task Contract cites the exact file as evidence input; an isolated retrieved fragment from a legacy file can never establish current truth, priority or authority.

## Current state

`P0 Strategic Foundation` is complete by Founder Gate decision. The accepted
checkpoint is immutable and the Long-term Goal is active. The Founder has
authorized entry into `P1 Agent Evaluation and Research Foundation` and
pre-execution completion, freeze and review of AIOS-P1-001. AIOS-P1-001 execution
is not started or authorized until the Founder separately accepts and starts the
exact reviewed contract.

The external P0-A audit is stored outside the Git worktree at:

`/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p0-a-20260710-220800/`

## Evidence terms

- `DEFINED`: described in documentation or schema only.
- `IMPLEMENTED`: executable code exists.
- `TESTED`: relevant automated tests have passed against a known state.
- `GATE_PASSED`: a declared gate passed and its evidence is retained.
- `PRODUCTION_PROVEN`: repeated production evidence exists.

No lower level implies a higher level.

## Gate artifact

`P0_GATE.md` collects the P0 exit checklist and dirty-worktree recovery plan. It is derived from canonical truth and never overrides it.

`P0_INDEPENDENT_REVIEW.md` records the read-only CTO, Quality & Evaluation and
Security review cycle. Its pre-Founder recommendation and historical `NO-GO`
state remain evidence, but they do not override the later Human Founder P0 Gate
`PASS` decision recorded by the external hash-bound Decision Record.

## Codex operator entry

`CODEX_MASTER_PROMPT.md` contains the startup, specialist dispatch, independent review and Founder decision prompts. It references the canonical files and does not store current facts.

Repository-level Codex startup is enforced by the root `AGENTS.md`. It is an
execution pointer to this authority index, not an additional authority.

## P1 controlled contract definitions

The Founder accepted the checkpoint versions of TaskSpec, EnvironmentSnapshot,
SystemConfiguration, RunRecord and `BASELINE_ADAPTER_CONTRACT.md` as controlled P1
implementation definitions. P1 entry is now separately authorized, but those
definitions do not make the research harness implemented, start AIOS-P1-001, or
establish a capability claim.

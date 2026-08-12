# P2 value-first recovery envelope expansion

- Exact authorization token:
  `AUTHORIZE_P2_VALUE_FIRST_RECOVERY_ENVELOPE_EXPANSION_V1`
- Exact Founder message:
  `AUTHORIZE_P2_VALUE_FIRST_RECOVERY_ENVELOPE_EXPANSION_V1；同意以指定 canonical commit、tree 与 Recovery Plan 为唯一纠偏基础，将累计 P2 envelope 从 12 Tasks / 336 engineering hours / 84 calendar days 扩展到最多 15 / 432 / 108，并按 Benchmark Foundation、Product Selector Implementation、Formal Held Evaluation 的顺序使用三个尚未分配 Task ID 的容量槽。`

## Canonical source

- Repository: `SourceLens-AIOS`
- Branch: `main`
- Commit: `5d75f146db21da0e05b5bd5b47ed23e096dd162d`
- Tree: `35274a399dbd1b452fe9c1e4e0753763a0d59d81`
- Truth SHA-256:
  `bd33c296372964c81b1f80fab1d3890fadbaa9a5e1b1ac8f25cd86581e0d460b`
- Recovery plan: `docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml`
- Recovery plan bytes: `7433`
- Recovery plan SHA-256: `cfb383e6b89c84bfe7e574f25a6b2137f5618a7aef0a013814a7abad6d5d24ab`

## Exact cumulative expansion

This decision resolves only `MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE`.

The prior consumed envelope is exactly `12 Tasks / 336 engineering hours / 84 calendar days`.

The cumulative envelope is exactly `15 Tasks / 432 engineering hours / 108 calendar days`.

The incremental capacity is exactly `3 Tasks / 96 engineering hours / 24 calendar days`.

Task IDs remain unallocated until the preceding milestone and Task admission pass.

## Milestone order and boundaries

1. `P2_RECOVERY_BASELINE_ACCEPTED`: Benchmark Foundation; product mutation prohibited; requires accepted benchmark source-pack admission.
2. `P2_RECOVERY_PRODUCT_SELECTOR_DEV_ACCEPTED`: Product Selector Implementation; requires milestone 1 accepted.
3. `P2_RECOVERY_FORMAL_HELD_MATRIX_COMPLETE`: Formal Held Evaluation; product, dataset, split, oracle, metric, threshold and schedule mutation prohibited; requires milestone 2 accepted.

Each capacity slot is bounded to `32 engineering hours / 8 calendar days / 2 candidate generations / 2 implementation iterations / 1 same-Task repair`.

This authorization creates zero engineering or P2 progress credit by itself and authorizes zero network, Provider, Secret, remote, production or public effects.

P3 remains HOLD and the SourceLens project and Long-term Goal remain ACTIVE.

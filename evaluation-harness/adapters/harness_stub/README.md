# HARNESS_STUB

`HARNESS_STUB` is deterministic conformance plumbing for AIOS-P1-001. It reads
the frozen synthetic JSON context, sorts its integer values, and emits the
frozen response shape.

The accepted `SystemConfiguration` schema requires one of `B0`, `B1`, `B2`, or
`A0`, so the frozen Quality fixture uses `A0` as compatibility notation. This
adapter is **not** A0, B0, an Agent, a benchmark, a VTSR observation, or a
software-engineering capability claim.

The optional controlled-failure argument accepts only the frozen `/sum`
replacement mutation. It exists solely to prove that the independent evaluator
rejects a known-wrong result.

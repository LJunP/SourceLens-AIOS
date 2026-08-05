# P1-217 single-process raw-Evidence report admission

This directory documents the accepted output contract. Runtime report bytes are
created outside the repository in a unique, absent, caller-owned output root.

The implementation reconstructs the P1-207 result only from the manifest-bound
raw Evidence inventory. It never reads the excluded historical report or review
as input or oracle. The accepted claim is limited to a cooperative-local,
single-process run with no concurrent filesystem mutator.

The independent verifier enforces the complete closed report contract. It
re-derives every field from immutable raw Evidence, including the source run's
execution ID, and binds the evaluator's identity, definition, and version. Any
missing, extra, type-drifted, or mutated report field is rejected; no partial
projection is accepted.

Declared output files:

- `REPRODUCIBLE_BASELINE_REPORT.json`
- `INDEPENDENT_VERIFIER_RECEIPT.json`
- `REPORT_ADMISSION_RECEIPT.json`

No Provider, Secret, network, remote, production, or public effect is permitted.

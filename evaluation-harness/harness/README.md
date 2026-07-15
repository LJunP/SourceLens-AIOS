# AIOS-P1-001 minimum Evaluation Harness

This Node.js 20 standard-library-only harness proves one bounded property: a
frozen standalone synthetic fixture can be loaded, validated, executed through
the deterministic `HARNESS_STUB`, independently evaluated, rejected when
deliberately wrong, replayed, and bound into a checksum manifest.

It does not run B0, B1, B2, or A0; does not use a model, provider, network,
Secret, remote, or production effect; and does not claim Agent capability,
Repository Intelligence improvement, VTSR, hidden-set validity, or production
readiness.

## Interfaces

Run the full bounded conformance flow into a new create-once child of the
Worker-owned recording directory:

```sh
node evaluation-harness/harness/cli.mjs run \
  --output evaluation-harness/recording/aios-p1-001-evidence
```

Replay frozen evidence without mutating it:

```sh
node evaluation-harness/replay/cli.mjs \
  --evidence evaluation-harness/recording/aios-p1-001-evidence
```

Run Worker and Quality conformance tests:

```sh
node evaluation-harness/evaluator/self-test.mjs
node evaluation-harness/harness/self-test.mjs
```

The harness verifies the Quality Freeze Receipt before creating output. Any
drift in the Task Contract, accepted schemas, evaluator, oracle, visible
fixtures, Evaluation Protocol, or Baseline Adapter Contract fails closed.

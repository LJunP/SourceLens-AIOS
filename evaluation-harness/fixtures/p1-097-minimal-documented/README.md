# P1-097 Quality-owned executable contract

These files are owned by the P1-097 Quality Design Agent. They define the
physical inputs that the implementation worker must consume. They are not an
adapter implementation and they do not grant any external effect.

The worker entry point is fixed at:

```text
evaluation-harness/harness/p1-097-minimal-documented/run.mjs
```

Its exact CLI is:

```text
/usr/local/bin/node run.mjs --request ABSOLUTE_REGULAR_JSON --output-root ABSOLUTE_PATH
```

The request and stdout key sets are closed by `interface.json`. A positive
request exits `0` with one canonical JSON line and `status=PASS`. A rejected
negative request exits `2` with one canonical JSON line and
`status=REJECTED`. Stderr must be empty.

Every negative case is materialized into a fresh physical directory. For all
cases whose `stage` is `PRE_EXECUTION`, the Quality evaluator supplies a
controlled descriptor whose target writes `target-executed` only if it is
actually launched. The rejection is valid only when the target sentinel does
not exist, `target_execution_count` is zero, all six external-effect flags are
false, and non-owned fixtures remain byte-identical.

The implementation must not special-case a case ID. It must reject because the
physical request, descriptor, input, output-root or result violates the common
contract. The Quality evaluator reruns every case itself and does not accept a
reported case count as evidence.


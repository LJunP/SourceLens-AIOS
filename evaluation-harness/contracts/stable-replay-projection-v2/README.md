# Stable replay projection v2

This directory is the frozen public Quality contract for P1-071. It contains no
retained withheld Task Card, source, tests, oracle, or expected bytes.

The executable accepts exactly one `evidence.json` and its raw
`candidate.stdout`, validates the frozen Evidence shape and raw bindings, and
writes the canonical projection bytes to stdout. It never mutates either input
and creates no filesystem output.

Normalization is closed: tokenize only the six declared physical-path fields
and absolute ordered-argv elements; remove only `runtime.duration_ms`; recompute
only the ordered-argv digest and normalized-stdout digest/length. Every other
pointer, type, value, repository-relative path, and array order remains exact.

The development fixtures are wholly synthetic. The formal retained A/B runs
remain Quality-only outside the repository. Formal receipt/oracle identity is a
precondition to comparison but never enters projection equality.

The 12 positive and 31 negative test IDs in `test-cases.json` are closed. An
unhandled difference is `NON_PASS`; it does not authorize another normalization.

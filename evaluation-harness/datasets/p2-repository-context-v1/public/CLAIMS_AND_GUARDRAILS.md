# P2 Repository Context v1

This freeze measures whether a deterministic, offline selector localizes a
small set of production files for accepted SourceLens engineering changes.

The public development tasks may be used to implement the selector. The two
validation tasks are visible only through opaque identifiers and exact hashes
of the private issue and oracle files. A Worker must not read or infer those
private bytes before the sealed Quality evaluation.

The frozen baseline is 13 hits from 24 validation oracle files at rank 10. The
target is at least 18 hits from 24. Because each validation oracle contains 12
files and the selector may return at most 10, the theoretical maximum is 20
hits; the largest measurable improvement over baseline is therefore 7/24
(0.2916666666666667).

Passing this dataset supports only a bounded repository-context localization
claim. It does not establish semantic correctness, code generation quality,
production safety, model quality, or P2 completion.

The selector must remain offline and deterministic. Git diffs, accepted-change
content, Git-history lookup, validation issue text, validation gold, models,
embeddings, Provider calls, Secrets, and remote, production, or public effects
are forbidden. Output must contain at most ten distinct regular files and must
pass identity, contamination, replay, closed-result, efficiency, and
external-effect checks.

Every selected file must carry its exact Git-blob/SHA-256/length identity,
symbol evidence, hashed byte spans, and a typed stable rationale. Cold-index,
query, end-to-end latency and selected-byte totals must match a separately
supplied Quality-owned observer receipt. The same receipt binds a closed input
inventory and independently observed process-boundary counters. Candidate
self-attestation alone cannot establish absence of validation contamination or
external effects.

The latency acceptance gate is query-only p95 measured against the same-index
baseline and must be at most 2x. Cold-index and end-to-end latency remain
required observed evidence but are not substituted for the query-only gate.

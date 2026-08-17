# P2 clean-room benchmark foundation v1

This benchmark executes only the eight DEV tasks in the accepted source pack. The four
HELD task IDs remain manifest-only custody: their source trees, PR-file payloads and
build results are never opened by the DEV runner.

For every DEV task, the maintenance query is the frozen pull-request title followed by
its body. The retrieval corpus is every regular, non-symlink `.java` file below a
`src/main/java` directory in the frozen base tree. The oracle is the set of production
Java paths in the frozen pull-request-files response. Tests, generated files, build
outputs and non-Java files are excluded.

B0 ranks files by distinct query-token overlap. B1 is BM25 with `k1=1.2` and `b=0.75`.
Both use NFKC/case-folded camel-and-alphanumeric tokenization, the same query and corpus,
top-k 10, a 131072-byte whole-file budget, and score-descending then UTF-8 path-ascending
tie-breaking. The outputs include the full ranking, selected paths and bytes, recall,
precision, reciprocal rank and macro aggregates.

Every opened provenance leaf is checked against the accepted manifest before parsing.
Every opened corpus leaf is bound to the accepted archive identity, base tree, normalized
tree entry, pre-read mode and byte length, then post-read byte length and SHA-256. Output
files are create-once and two clean candidate roots must compare byte-for-byte.

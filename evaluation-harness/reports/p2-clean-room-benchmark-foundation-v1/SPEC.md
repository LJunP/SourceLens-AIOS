# P2 clean-room benchmark foundation v1

This benchmark executes only the eight DEV tasks in the accepted source pack. The four
HELD task IDs remain manifest-only custody: their source trees, PR-file payloads and
build results are never opened by the DEV runner.

For every DEV task, the maintenance query is the frozen pull-request title followed by
its body. The retrieval corpus is every regular `.java` entry below a `src/main/java`
directory in the manifest-bound base archive. The runner verifies the complete archive
bytes before parsing, verifies every tar header checksum, rejects every special entry,
and binds each logical corpus leaf to the accepted archive/tree plus its path, byte
length and SHA-256 before scoring. The oracle is the set of production Java paths in the
frozen pull-request-files response. Tests, generated files, build outputs and non-Java
files are excluded.

B0 ranks files by distinct query-token overlap. B1 is BM25 with `k1=1.2` and `b=0.75`.
Both use NFKC/case-folded camel-and-alphanumeric tokenization, the same query and corpus,
top-k 10, a 131072-byte whole-file budget, and score-descending then UTF-8 path-ascending
tie-breaking. The outputs include the full ranking, selected paths and bytes, recall,
precision, reciprocal rank and macro aggregates.

Every opened provenance or archive leaf is checked against the accepted manifest before
parsing. Output and manifest paths are exact non-symlink descendants of the bound Task
Evidence root. Output files are create-once and two independently bound clean candidate
roots must compare byte-for-byte. Each transaction binds the candidate commit/tree,
argv, cwd, closed environment, Node runtime, source/output roots and the exact
deny-network execution context. A derived proof commits to the complete DEV read set and
the HELD forbidden-path set and requires an empty intersection.

The exact replay commands are stored in the create-once execution-context JSON under the
Task Evidence root. Execute them under its bound `/usr/bin/sandbox-exec` profile, then run:

```text
node evaluation-harness/replay/p2-clean-room-benchmark-foundation-v1/verify-replays.mjs \
  --evidence-root "$P2_TASK_EVIDENCE_ROOT" \
  --left-run repair-replay-1 --right-run repair-replay-2
```

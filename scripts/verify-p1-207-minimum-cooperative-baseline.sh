#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CANONICAL_ROOT="/Users/lijunpeng/Developer/SourceLens-AIOS"
readonly NODE_BIN="/usr/local/bin/node"

if [[ "$#" -ne 2 ]]; then
  printf '%s\n' 'usage: verify-p1-207-minimum-cooperative-baseline.sh /absolute/absent-preformal-evidence-root /absolute/absent-preformal-review-root' >&2
  exit 64
fi

readonly EVIDENCE_ROOT="$1"
readonly REVIEW_ROOT="$2"

cd "${ROOT_DIR}"

/usr/bin/git diff --check
if [[ ! -d "${CANONICAL_ROOT}" || -L "${CANONICAL_ROOT}" ||
      "$(/usr/bin/git -C "${CANONICAL_ROOT}" rev-parse --show-toplevel)" != "${CANONICAL_ROOT}" ]]; then
  printf '%s\n' 'P1-207 canonical authority root is invalid' >&2
  exit 1
fi
(
  cd "${CANONICAL_ROOT}"
  /usr/bin/ruby scripts/validate-current-task-authority.rb
  /bin/bash scripts/check-p1-safety-boundary.sh
  /bin/bash scripts/validate-aios-governance.sh
)
"${NODE_BIN}" scripts/generate-project-code-map.mjs --check

for source in \
  evaluation-harness/harness/p1-207-minimum-cooperative-baseline/*.mjs \
  evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/*.mjs; do
  "${NODE_BIN}" --check "${source}"
done
/bin/bash -n scripts/p1-207-operator-capture.sh
/bin/bash -n scripts/verify-p1-207-minimum-cooperative-baseline.sh

if [[ "$(/usr/bin/stat -f '%Lp' scripts/p1-207-operator-capture.sh)" != "700" ]]; then
  printf '%s\n' 'P1-207 operator entry must have mode 0700' >&2
  exit 1
fi

"${NODE_BIN}" evaluation-harness/harness/p1-207-minimum-cooperative-baseline/self-test.mjs
"${NODE_BIN}" evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/postformal-control-negative-matrix.mjs
"${NODE_BIN}" evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/postformal-usage-normalization-test.mjs
"${NODE_BIN}" evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/prepare-preformal.mjs \
  "${EVIDENCE_ROOT}" "${REVIEW_ROOT}"

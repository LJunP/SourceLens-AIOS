#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CANONICAL_ROOT="/Users/lijunpeng/Developer/SourceLens-AIOS"
readonly NODE_BIN="/usr/local/bin/node"
readonly FORMAL_ENTRY="${ROOT_DIR}/evaluation-harness/harness/p1-207-minimum-cooperative-baseline/formal.mjs"

if [[ "$#" -ne 2 ]]; then
  printf '%s\n' 'usage: p1-207-operator-capture.sh /absolute/PREFORMAL_GATE_RECEIPT.json /absolute/absent-formal-evidence-root' >&2
  exit 64
fi

readonly PREFORMAL_GATE_RECEIPT="$1"
readonly FORMAL_EVIDENCE_ROOT="$2"

if [[ ! -x "${NODE_BIN}" || ! -f "${FORMAL_ENTRY}" || -L "${FORMAL_ENTRY}" ]]; then
  printf '%s\n' '{"reason_code":"P1_207_RUNTIME_INPUT_INVALID","status":"NON_PASS"}' >&2
  exit 1
fi

if [[ ! -d "${CANONICAL_ROOT}" || -L "${CANONICAL_ROOT}" ||
      "$(/usr/bin/git -C "${CANONICAL_ROOT}" rev-parse --show-toplevel)" != "${CANONICAL_ROOT}" ]]; then
  printf '%s\n' '{"reason_code":"P1_207_CANONICAL_AUTHORITY_ROOT_INVALID","status":"NON_PASS"}' >&2
  exit 1
fi

# Authority and phase-safety validation are canonical-main entry points by
# contract. The candidate implementation remains in this declared Task
# worktree; only the read-only authority checks execute from canonical main.
(
  cd "${CANONICAL_ROOT}"
  /usr/bin/ruby scripts/validate-current-task-authority.rb
  /bin/bash scripts/check-p1-safety-boundary.sh
)

# This effect-free check completes before the operator is asked for a Secret.
"${NODE_BIN}" "${FORMAL_ENTRY}" --gate-check \
  "${PREFORMAL_GATE_RECEIPT}" "${FORMAL_EVIDENCE_ROOT}"

P1_207_OPERATOR_SECRET=""
trap 'unset P1_207_OPERATOR_SECRET' EXIT
IFS= read -r -s -p 'Enter the P1-207 loopback API key once (no echo): ' P1_207_OPERATOR_SECRET
printf '\n' >&2

# Bash builtin printf transfers the Secret through stdin only. It is never an
# argv, environment, here-string, temporary file, log, prompt, or Evidence item.
set +e
printf '%s' "${P1_207_OPERATOR_SECRET}" \
  | "${NODE_BIN}" "${FORMAL_ENTRY}" --execute \
      "${PREFORMAL_GATE_RECEIPT}" "${FORMAL_EVIDENCE_ROOT}"
readonly PIPE_STATUS=("${PIPESTATUS[@]}")
set -e
unset P1_207_OPERATOR_SECRET

if [[ "${PIPE_STATUS[0]}" -ne 0 || "${PIPE_STATUS[1]}" -ne 0 ]]; then
  exit 1
fi

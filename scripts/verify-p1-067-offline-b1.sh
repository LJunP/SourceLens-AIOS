#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "P1-067 targeted verifier takes no arguments" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NODE_BIN="/usr/local/bin/node"
ADAPTER="$ROOT_DIR/evaluation-harness/adapters/offline-b1-finite-tool-v1/adapter.mjs"
RUNNER="$ROOT_DIR/evaluation-harness/harness/offline-b1-complete-evidence-v1/run.mjs"
ORACLE="$ROOT_DIR/evaluation-harness/evaluator/offline-b1-simple-tool-v1/quality-oracle.mjs"

if [[ ! -x "$NODE_BIN" || -L "$NODE_BIN" ]]; then
  echo "P1-067 requires the frozen regular executable Node path: $NODE_BIN" >&2
  exit 2
fi

for source_path in "$ADAPTER" "$RUNNER" "$ORACLE"; do
  if [[ ! -f "$source_path" || -L "$source_path" ]]; then
    echo "P1-067 source is missing, non-regular, or symlinked: $source_path" >&2
    exit 2
  fi
  "$NODE_BIN" --check "$source_path"
done

for verifier in \
  "$ROOT_DIR/scripts/verify-p1-task-dataset.sh" \
  "$ROOT_DIR/scripts/verify-p1-finite-typed-patch-ir-v1.sh" \
  "$ROOT_DIR/scripts/verify-p1-066-offline-b0.sh"; do
  if [[ ! -x "$verifier" || -L "$verifier" ]]; then
    echo "Accepted regression verifier is missing, non-executable, or symlinked: $verifier" >&2
    exit 2
  fi
  "$verifier"
done

"$NODE_BIN" "$ADAPTER" self-test
"$NODE_BIN" "$ORACLE" self-test
"$NODE_BIN" "$RUNNER" self-test

echo "AIOS P1-067 offline B1 finite-tool complete-evidence targeted verification PASS"

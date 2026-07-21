#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "P1-066 targeted verifier takes no arguments" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NODE_BIN="/usr/local/bin/node"
ADAPTER="$ROOT_DIR/evaluation-harness/adapters/offline-b0-finite-typed-v1/adapter.mjs"
RUNNER="$ROOT_DIR/evaluation-harness/harness/offline-b0-complete-evidence-v1/run.mjs"
ORACLE="$ROOT_DIR/evaluation-harness/evaluator/offline-b0-complete-evidence-v1/quality-oracle.mjs"
DATASET_VERIFIER="$ROOT_DIR/scripts/verify-p1-task-dataset.sh"
COMPILER_VERIFIER="$ROOT_DIR/scripts/verify-p1-finite-typed-patch-ir-v1.sh"

if [[ ! -x "$NODE_BIN" || -L "$NODE_BIN" ]]; then
  echo "P1-066 requires the frozen regular executable Node path: $NODE_BIN" >&2
  exit 2
fi

for source_path in "$ADAPTER" "$RUNNER" "$ORACLE"; do
  if [[ ! -f "$source_path" || -L "$source_path" ]]; then
    echo "P1-066 source is missing, non-regular, or symlinked: $source_path" >&2
    exit 2
  fi
  "$NODE_BIN" --check "$source_path"
done

for verifier in "$DATASET_VERIFIER" "$COMPILER_VERIFIER"; do
  if [[ ! -x "$verifier" || -L "$verifier" ]]; then
    echo "Accepted regression verifier is missing, non-executable, or symlinked: $verifier" >&2
    exit 2
  fi
  "$verifier"
done

# Both self-tests use only fresh, marker-owned temporary fixtures. They do not
# consume, overwrite, or clean formal Run A/Run B Evidence.
"$NODE_BIN" "$ORACLE" self-test
"$NODE_BIN" "$RUNNER" self-test

echo "AIOS P1-066 offline B0 complete-evidence targeted verification PASS"

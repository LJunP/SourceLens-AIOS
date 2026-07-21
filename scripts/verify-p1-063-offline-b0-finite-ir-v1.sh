#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NODE_BIN="/usr/local/bin/node"
ADAPTER_PATH="$ROOT_DIR/evaluation-harness/adapters/p1-063-offline-b0-finite-ir-v1/offline-adapter.mjs"
RUNNER_PATH="$ROOT_DIR/evaluation-harness/harness/p1-063-offline-b0-finite-ir-v1/runner.mjs"
QUALITY_PATH="$ROOT_DIR/evaluation-harness/evaluator/p1-063-offline-b0-finite-ir-v1/quality-evaluator.mjs"

if [[ "$#" -ne 0 ]]; then
  echo "P1-063 targeted verifier takes no arguments" >&2
  exit 2
fi

if [[ ! -x "$NODE_BIN" || -L "$NODE_BIN" ]]; then
  echo "P1-063 verification requires the frozen Node executable" >&2
  exit 1
fi

for source_path in "$ADAPTER_PATH" "$RUNNER_PATH" "$QUALITY_PATH"; do
  if [[ ! -f "$source_path" || -L "$source_path" ]]; then
    echo "P1-063 source is missing or symlinked: $source_path" >&2
    exit 1
  fi
done

"$NODE_BIN" --check "$ADAPTER_PATH"
"$NODE_BIN" --check "$RUNNER_PATH"
"$NODE_BIN" --check "$QUALITY_PATH"

cd "$ROOT_DIR"
"$NODE_BIN" evaluation-harness/evaluator/p1-063-offline-b0-finite-ir-v1/quality-evaluator.mjs self-test
"$NODE_BIN" evaluation-harness/harness/p1-063-offline-b0-finite-ir-v1/runner.mjs self-test

echo "AIOS P1-063 offline finite IR admission and B0 adapter targeted verification PASS"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NODE_BIN="/usr/local/bin/node"

if [[ "$#" -ne 0 ]]; then
  echo "P1-062 targeted verifier takes no arguments" >&2
  exit 2
fi

if [[ ! -x "$NODE_BIN" || -L "$NODE_BIN" ]]; then
  echo "P1-062 verification requires the frozen executable Node path: $NODE_BIN" >&2
  exit 1
fi

modules=(
  "evaluation-harness/adapters/local-gateway-finite-ir-b0-v1/core.mjs"
  "evaluation-harness/adapters/local-gateway-finite-ir-b0-v1/cli.mjs"
  "evaluation-harness/evaluator/local-gateway-finite-ir-b0-v1/quality-oracle.mjs"
  "evaluation-harness/evaluator/local-gateway-finite-ir-b0-v1/self-test.mjs"
  "evaluation-harness/recording/local-gateway-finite-ir-b0-v1/evidence.mjs"
  "evaluation-harness/replay/local-gateway-finite-ir-b0-v1/runner.mjs"
  "evaluation-harness/replay/local-gateway-finite-ir-b0-v1/self-test.mjs"
  "evaluation-harness/validators/local-gateway-finite-ir-b0-v1/independent-quality-replay.mjs"
  "evaluation-harness/validators/local-gateway-finite-ir-b0-v1/offline-self-test.mjs"
)

cd "$ROOT_DIR"
for module in "${modules[@]}"; do
  if [[ ! -f "$module" || -L "$module" ]]; then
    echo "P1-062 module is missing or symlinked: $module" >&2
    exit 1
  fi
  "$NODE_BIN" --check "$module"
done

"$NODE_BIN" evaluation-harness/evaluator/local-gateway-finite-ir-b0-v1/self-test.mjs
"$NODE_BIN" evaluation-harness/validators/local-gateway-finite-ir-b0-v1/offline-self-test.mjs
"$NODE_BIN" evaluation-harness/replay/local-gateway-finite-ir-b0-v1/self-test.mjs

echo "AIOS P1-062 local gateway finite IR B0 targeted verification PASS"

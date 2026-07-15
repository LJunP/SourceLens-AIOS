#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="${NODE_BIN:-/usr/local/bin/node}"

if [[ ! -x "$NODE_BIN" ]]; then
  echo "P1 harness verification requires executable Node.js at: $NODE_BIN" >&2
  exit 1
fi

cd "$ROOT_DIR"

"$NODE_BIN" evaluation-harness/evaluator/self-test.mjs
"$NODE_BIN" evaluation-harness/harness/self-test.mjs

echo "AIOS P1-001 evaluation harness verification PASS"

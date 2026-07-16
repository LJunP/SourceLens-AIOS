#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="${NODE_BIN:-/usr/local/bin/node}"

if [[ ! -x "$NODE_BIN" ]]; then
  echo "P1 environment snapshot verification requires executable Node.js at: $NODE_BIN" >&2
  exit 1
fi

cd "$ROOT_DIR"

"$NODE_BIN" --input-type=module -e '
  import { createHash } from "node:crypto";
  import { readFileSync } from "node:fs";

  const digest = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
  const contract = "docs/aios/tasks/P1-011_ENVIRONMENT_SNAPSHOT_CAPTURE_AND_REPLAY.yaml";
  const receipt = "evaluation-harness/fixtures/environment-snapshot/FREEZE_RECEIPT.json";
  const frozen = JSON.parse(readFileSync(receipt, "utf8"));
  const expectedContract = "59ad6ca86c8eeb62394265d7a81cd08b089fdb33d54d4f9e17e558249304cd7a";
  const expectedReceipt = "c38da27bb6e18bedc0323aa68f172cee265e3530ca19de7928512fa6c2836bda";

  if (digest(contract) !== expectedContract || frozen.task_contract?.sha256 !== expectedContract) {
    throw new Error("P1-011 Task Contract identity drift");
  }
  if (digest(receipt) !== expectedReceipt || frozen.status !== "FROZEN") {
    throw new Error("P1-011 Quality Freeze Receipt identity drift");
  }
  for (const artifact of frozen.frozen_files ?? []) {
    const bytes = readFileSync(artifact.path);
    if (bytes.length !== artifact.byte_length || createHash("sha256").update(bytes).digest("hex") !== artifact.sha256) {
      throw new Error(`P1-011 frozen Quality artifact drift: ${artifact.path}`);
    }
  }
'

"$NODE_BIN" evaluation-harness/environment/self-test.mjs
"$NODE_BIN" evaluation-harness/evaluator/self-test.mjs
"$NODE_BIN" evaluation-harness/harness/self-test.mjs

echo "AIOS P1-011 environment snapshot verification PASS"

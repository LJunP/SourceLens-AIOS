#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="${NODE_BIN:-/usr/local/bin/node}"

if [[ ! -x "$NODE_BIN" ]]; then
  echo "P1 representative Task Dataset verification requires executable Node.js at: $NODE_BIN" >&2
  exit 1
fi

cd "$ROOT_DIR"

"$NODE_BIN" --input-type=module -e '
  import { createHash } from "node:crypto";
  import { readFileSync } from "node:fs";

  const digest = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
  const contract = "docs/aios/tasks/P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET.yaml";
  const receipt = "evaluation-harness/datasets/p1-representative-task-dataset-v1/QUALITY_FREEZE_RECEIPT.json";
  const expectedContract = "acec5432aacd6476693db62bdb52ee326c467f17b691860688fe952f7ffbdc33";
  const expectedReceipt = "d509da3a7d8fba22b49d98ed9d5ced9e804a1541b4c427674f6c8a6950f41f9d";

  if (digest(contract) !== expectedContract) throw new Error("P1-035 Task Contract identity drift");
  if (digest(receipt) !== expectedReceipt) throw new Error("P1-035 Quality Freeze Receipt identity drift");

  const frozen = JSON.parse(readFileSync(receipt, "utf8"));
  if (frozen.task_contract?.sha256 !== expectedContract
      || frozen.dataset_id !== "SOURCELENS-P1-REPRESENTATIVE-TASKS"
      || frozen.dataset_version !== "1.0.0"
      || frozen.worker_write_access_after_freeze !== "DENIED_FOR_DATASET_ROOT") {
    throw new Error("P1-035 frozen authority binding drift");
  }
'

"$NODE_BIN" evaluation-harness/validators/task-dataset-validator.mjs
"$NODE_BIN" evaluation-harness/validators/task-dataset-self-test.mjs
"$NODE_BIN" evaluation-harness/evaluator/self-test.mjs

echo "AIOS P1-035 representative Task Dataset verification PASS"

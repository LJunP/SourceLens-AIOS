#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX="${ROOT_DIR}/evaluation-harness/evaluator/p1-125-six-task-parameterized/run-matrix.mjs"
WORKER="${ROOT_DIR}/evaluation-harness/harness/p1-125-six-task-parameterized/run.mjs"
DATASET_MANIFEST="${ROOT_DIR}/evaluation-harness/datasets/p1-representative-task-dataset-v1/dataset-manifest.json"
PROGRAM_SET="${ROOT_DIR}/evaluation-harness/fixtures/p1-125-six-task-parameterized/b1-program-set.json"

test -f "${MATRIX}" && test ! -L "${MATRIX}"
test -f "${WORKER}" && test ! -L "${WORKER}"
test -f "${DATASET_MANIFEST}" && test ! -L "${DATASET_MANIFEST}"
test -f "${PROGRAM_SET}" && test ! -L "${PROGRAM_SET}"

dataset_sha="$(openssl dgst -sha256 "${DATASET_MANIFEST}" | awk '{print $NF}')"
program_sha="$(openssl dgst -sha256 "${PROGRAM_SET}" | awk '{print $NF}')"
test "${dataset_sha}" = "22f252319ed066655b05142a391709741703e01fbb4d6b5ebfbbcb6acd782be6"
test "${program_sha}" = "17b15108853e8df23155ba6f2fafc368446d643ec8857f41116c78e2f1f1e42c"

node --check "${WORKER}"
node --check "${MATRIX}"

if [[ -n "${P1_125_FORMAL_OUTPUT_ROOT:-}" ]]; then
  OUTPUT_ROOT="${P1_125_FORMAL_OUTPUT_ROOT}"
  test ! -e "${OUTPUT_ROOT}" && test ! -L "${OUTPUT_ROOT}"
else
  owned_parent="$(mktemp -d /private/tmp/sourcelens-p1-125-verify.XXXXXX)"
  OUTPUT_ROOT="${owned_parent}/formal"
fi

node "${MATRIX}" \
  --worker-entry "${WORKER}" \
  --output-root "${OUTPUT_ROOT}"

node -e '
  const fs = require("node:fs");
  const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const effectsAreZero = Object.values(value.external_effects).every((entry) => entry === false);
  if (value.status !== "PASS"
      || value.accepted_task_count !== 6
      || value.positive_runs !== 36
      || value.distinct_positive_run_roots !== 36
      || value.exact_stable_pairs !== 18
      || value.b1_exact_rollbacks !== 12
      || value.b2_real_repository_analysis_scan_children !== 12
      || value.negative_cases !== 51
      || value.false_accepts !== 0
      || value.nonowned_residuals !== 0
      || !effectsAreZero) {
    throw new Error(`P1-125 summary NON_PASS: ${JSON.stringify(value)}`);
  }
' "${OUTPUT_ROOT}/quality-formal-summary.json"

echo "P1_125_SIX_TASK_PARAMETERIZED_ADAPTER_CONVERGENCE: PASS output=${OUTPUT_ROOT}"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EVALUATOR_DIR="${ROOT_DIR}/evaluation-harness/evaluator/p1-217-single-process-report"
SOURCE_ROOT="/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207/evidence/formal-execution-v1"
CANONICAL_ROOT="$(ruby -ryaml -e 'truth = YAML.safe_load(File.binread(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false); puts truth.fetch("project").fetch("canonical_repository")' "${ROOT_DIR}/docs/aios/truth/project_state.yaml")"

(
  cd "${CANONICAL_ROOT}"
  ruby scripts/validate-current-task-authority.rb
  bash scripts/check-p1-safety-boundary.sh
)
node --check "${EVALUATOR_DIR}/core.mjs"
node --check "${EVALUATOR_DIR}/independent-verifier.mjs"
node --check "${EVALUATOR_DIR}/cli.mjs"
node --check "${EVALUATOR_DIR}/test.mjs"
node "${EVALUATOR_DIR}/test.mjs"

owned_parent="$(mktemp -d /private/tmp/p1-217-verify.XXXXXX)"
trap 'node -e '\''require("fs").rmSync(process.argv[1], { recursive: true, force: true })'\'' "${owned_parent}"' EXIT
output_root="${owned_parent}/report-output"
node "${EVALUATOR_DIR}/cli.mjs" "${SOURCE_ROOT}" "${output_root}"
test -f "${output_root}/REPRODUCIBLE_BASELINE_REPORT.json"
test -f "${output_root}/INDEPENDENT_VERIFIER_RECEIPT.json"
test -f "${output_root}/REPORT_ADMISSION_RECEIPT.json"

echo 'P1_217_SINGLE_PROCESS_RAW_EVIDENCE_REPORT_ADMISSION: PASS'

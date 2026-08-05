#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd -P)"
EVALUATOR_DIR="${REPO_ROOT}/evaluation-harness/evaluator/p1-219-dataset-derived-preregistration"
ARTIFACT_PATH="${REPO_ROOT}/evaluation-harness/reports/p1-219-dataset-derived-preregistration/P2_CONTEXT_ENGINE_PREREGISTRATION.json"

cd "${REPO_ROOT}"
node --check "${EVALUATOR_DIR}/lib.mjs"
node --check "${EVALUATOR_DIR}/generate.mjs"
node --check "${EVALUATOR_DIR}/verify.mjs"
node --check "${EVALUATOR_DIR}/test.mjs"
node "${EVALUATOR_DIR}/test.mjs"
node "${EVALUATOR_DIR}/verify.mjs" "${ARTIFACT_PATH}"

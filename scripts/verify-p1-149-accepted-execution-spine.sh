#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NODE_BIN="/usr/local/bin/node"
readonly P1_055_CHECK="${ROOT_DIR}/scripts/verify-p1-finite-typed-patch-ir-v1.sh"
readonly P1_129_WORKER="${ROOT_DIR}/evaluation-harness/harness/p1-125-six-task-parameterized/run.mjs"
readonly P1_129_MATRIX="${ROOT_DIR}/evaluation-harness/evaluator/p1-125-six-task-parameterized/run-matrix.mjs"
readonly P1_149_PREFLIGHT="${ROOT_DIR}/evaluation-harness/harness/p1-149-accepted-execution-spine/run-preflight.mjs"
readonly P1_149_EVALUATOR="${ROOT_DIR}/evaluation-harness/evaluator/p1-149-accepted-execution-spine/evaluate.mjs"

if [[ ! -x "${NODE_BIN}" ]]; then
  printf '%s\n' '{"reason_code":"NODE_EXECUTABLE_UNAVAILABLE","status":"NON_PASS"}' >&2
  exit 1
fi

for required_path in \
  "${P1_055_CHECK}" \
  "${P1_129_WORKER}" \
  "${P1_129_MATRIX}" \
  "${P1_149_PREFLIGHT}" \
  "${P1_149_EVALUATOR}"; do
  if [[ ! -f "${required_path}" || -L "${required_path}" ]]; then
    printf '%s\n' '{"reason_code":"P1_149_REQUIRED_INPUT_INVALID","status":"NON_PASS"}' >&2
    exit 1
  fi
done

umask 077
P1_149_VERIFIER_ROOT="$(mktemp -d /private/tmp/sourcelens-p1-149-verifier.XXXXXXXX)"
chmod 700 "${P1_149_VERIFIER_ROOT}"
readonly P1_149_VERIFIER_ROOT
readonly P1_149_VERIFIER_DEV="$(/usr/bin/stat -f '%d' "${P1_149_VERIFIER_ROOT}")"
readonly P1_149_VERIFIER_INO="$(/usr/bin/stat -f '%i' "${P1_149_VERIFIER_ROOT}")"
readonly P1_129_OUTPUT_ROOT="${P1_149_VERIFIER_ROOT}/accepted-adapter-control"
readonly P1_149_EVIDENCE_ROOT="${P1_149_VERIFIER_ROOT}/execution-spine-preflight"

cleanup_owned_root() {
  "${NODE_BIN}" --input-type=module - \
    "${P1_149_VERIFIER_ROOT}" \
    "${P1_149_VERIFIER_DEV}" \
    "${P1_149_VERIFIER_INO}" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const [root, expectedDevText, expectedInoText] = process.argv.slice(2);
const fail = (reasonCode) => {
  process.stderr.write(`${JSON.stringify({ reason_code: reasonCode, status: "NON_PASS" })}\n`);
  process.exit(1);
};

if (!root.startsWith("/private/tmp/sourcelens-p1-149-verifier.")) {
  fail("P1_149_CLEANUP_SCOPE_INVALID");
}

let rootStat;
try {
  rootStat = fs.lstatSync(root, { bigint: true });
} catch (error) {
  if (error?.code === "ENOENT") process.exit(0);
  fail("P1_149_CLEANUP_ROOT_LSTAT_FAILED");
}

if (
  !rootStat.isDirectory()
  || rootStat.isSymbolicLink()
  || rootStat.uid !== BigInt(process.getuid())
  || rootStat.dev !== BigInt(expectedDevText)
  || rootStat.ino !== BigInt(expectedInoText)
  || fs.realpathSync(root) !== root
) {
  fail("P1_149_CLEANUP_ROOT_IDENTITY_MISMATCH");
}

const removeNoFollow = (target) => {
  const stat = fs.lstatSync(target, { bigint: true });
  if (stat.dev !== rootStat.dev || stat.uid !== rootStat.uid) {
    fail("P1_149_CLEANUP_CHILD_IDENTITY_MISMATCH");
  }
  if (stat.isSymbolicLink() || stat.isFile()) {
    fs.unlinkSync(target);
    return;
  }
  if (!stat.isDirectory()) fail("P1_149_CLEANUP_CHILD_TYPE_INVALID");
  for (const entry of fs.readdirSync(target)) {
    removeNoFollow(path.join(target, entry));
  }
  fs.rmdirSync(target);
};

removeNoFollow(root);
if (fs.existsSync(root)) fail("P1_149_CLEANUP_NOT_EXACT");
NODE
}

trap cleanup_owned_root EXIT

while IFS= read -r module_path; do
  "${NODE_BIN}" --check "${module_path}"
done <<EOF
${ROOT_DIR}/evaluation-harness/harness/p1-149-accepted-execution-spine/core.mjs
${ROOT_DIR}/evaluation-harness/harness/p1-149-accepted-execution-spine/patch-ir-v2.mjs
${ROOT_DIR}/evaluation-harness/harness/p1-149-accepted-execution-spine/accepted-inputs.mjs
${ROOT_DIR}/evaluation-harness/harness/p1-149-accepted-execution-spine/execution.mjs
${ROOT_DIR}/evaluation-harness/harness/p1-149-accepted-execution-spine/negative-matrix.mjs
${P1_149_PREFLIGHT}
${ROOT_DIR}/evaluation-harness/replay/p1-149-accepted-execution-spine/replay.mjs
${P1_149_EVALUATOR}
EOF

"${P1_055_CHECK}"

"${NODE_BIN}" "${P1_129_MATRIX}" \
  --worker-entry "${P1_129_WORKER}" \
  --output-root "${P1_129_OUTPUT_ROOT}"
"${NODE_BIN}" -e '
const fs = require("node:fs");
const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const zeroEffects = Object.values(value.external_effects).every((entry) => entry === false);
if (
  value.status !== "PASS"
  || value.accepted_task_count !== 6
  || value.positive_runs !== 36
  || value.distinct_positive_run_roots !== 36
  || value.exact_stable_pairs !== 18
  || value.b1_exact_rollbacks !== 12
  || value.b2_real_repository_analysis_scan_children !== 12
  || value.negative_cases !== 53
  || value.false_accepts !== 0
  || value.nonowned_residuals !== 0
  || !zeroEffects
) {
  throw new Error(`P1-129 accepted adapter control NON_PASS: ${JSON.stringify(value)}`);
}
' "${P1_129_OUTPUT_ROOT}/quality-formal-summary.json"

"${NODE_BIN}" "${P1_149_PREFLIGHT}" "${P1_149_EVIDENCE_ROOT}" >/dev/null
"${NODE_BIN}" -e '
const fs = require("node:fs");
const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const zeroEffects = Object.values(value.external_effects).every((entry) => entry === false);
if (
  value.status !== "PASS"
  || value.accepted_tasks !== 6
  || value.real_patch_operations !== 8
  || value.execution_spines !== 6
  || value.fixed_readiness_projection_cells !== 36
  || value.formal_baseline_cells !== 0
  || value.p1_capability_credit !== false
  || value.false_accepts !== 0
  || !zeroEffects
) {
  throw new Error(`P1-149 preflight summary NON_PASS: ${JSON.stringify(value)}`);
}
' "${P1_149_EVIDENCE_ROOT}/preflight-summary.json"

"${NODE_BIN}" "${P1_149_EVALUATOR}" "${P1_149_EVIDENCE_ROOT}" \
  | "${NODE_BIN}" -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const value = JSON.parse(input);
  const zeroEffects = Object.values(value.external_effects).every((entry) => entry === false);
  if (
    value.status !== "PASS"
    || value.formal_baseline_claimed !== false
    || value.p1_completion_credit_claimed !== false
    || value.task_evaluations?.length !== 6
    || value.readiness_cells?.length !== 36
    || value.taxonomy?.denominator !== 36
    || value.taxonomy?.accepted_execution_spine_readiness !== 36
    || value.false_accepts !== 0
    || !zeroEffects
  ) {
    throw new Error(`P1-149 independent evaluator NON_PASS: ${JSON.stringify(value)}`);
  }
});
'

printf '%s\n' 'P1_149_ACCEPTED_EXECUTION_SPINE_CONVERGENCE: PASS'

#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NODE_BIN="/usr/local/bin/node"
readonly TASK_ROOT="/Users/lijunpeng/Developer/.sourcelens-audit/p1-116-closed-profile-rollback-route-20260725/task-2"
readonly FORMAL_ROOT="${TASK_ROOT}/formal-evidence-v1"
readonly PREREGISTRATION="${ROOT_DIR}/evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/preregistration.json"
readonly EXECUTABLE_RECEIPT="${TASK_ROOT}/EXACT_EXECUTABLE_IDENTITY_FREEZE_RECEIPT.json"
readonly PRE_SECRET_RECEIPT="${TASK_ROOT}/P1_117_PRE_SECRET_PRE_PROVIDER_RECEIPT.json"
readonly MATRIX_VIEW="${TASK_ROOT}/FROZEN_MATRIX_CANONICAL_VIEW.json"
readonly ORACLE_VIEW="${TASK_ROOT}/FROZEN_EVALUATION_ORACLE_CANONICAL_VIEW.json"
readonly AGGREGATE="${TASK_ROOT}/INDEPENDENT_AGGREGATE.json"
readonly FORMAL_MANIFEST="${TASK_ROOT}/FORMAL_EVIDENCE_MANIFEST.json"
readonly BASELINE_REPORT="${TASK_ROOT}/BASELINE_REPORT.json"
readonly RUNTIME_RECEIPT="${FORMAL_ROOT}/formal-runtime-receipt.json"
readonly EVALUATOR="${ROOT_DIR}/evaluation-harness/evaluator/p1-117-clean-room-empirical-baseline/recompute.mjs"
readonly WORKER_SELF_TEST="${ROOT_DIR}/evaluation-harness/harness/p1-117-clean-room-empirical-baseline/self-test.mjs"
readonly QUALITY_SELF_TEST="${ROOT_DIR}/evaluation-harness/validators/p1-117-clean-room-empirical-baseline/self-test.mjs"

if [[ ! -x "${NODE_BIN}" ]]; then
  printf '%s\n' '{"reason":"NODE_EXECUTABLE_UNAVAILABLE","status":"NON_PASS"}' >&2
  exit 1
fi

"${NODE_BIN}" --input-type=module - "${ROOT_DIR}" "${TASK_ROOT}" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import {
  identityOf,
  parseCanonicalJson,
  parseFrozenJson,
  readAbsoluteBoundFile,
  readBoundFile,
  sameJson,
} from "./evaluation-harness/validators/p1-117-clean-room-empirical-baseline/core.mjs";
import {
  validateExecutableFreezeReceipt,
  validateMatrix,
  validateP2Preregistration,
} from "./evaluation-harness/validators/p1-117-clean-room-empirical-baseline/preflight.mjs";

const [repositoryRoot, taskRoot] = process.argv.slice(2);
const fail = (reason) => {
  process.stderr.write(`${JSON.stringify({ reason, status: "NON_PASS" })}\n`);
  process.exit(1);
};
const expected = new Map([
  ["evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/preregistration.json", ["c37cbaaab15101882966420c540cf478416cb5d7ad570842c92c20c8bc5a80e6", 12300]],
  [`${taskRoot}/EXACT_EXECUTABLE_IDENTITY_FREEZE_RECEIPT.json`, ["c16f32c3b25b498f6db0ea3c17026e5cb373f99f66318d75fe0048952e1dbbee", 10947]],
  [`${taskRoot}/P1_117_PRE_SECRET_PRE_PROVIDER_RECEIPT.json`, ["2ab97ac75852bced5eff19d84a54a1d7d2865ac869d2f5a1144d788ce50b140d", 809]],
  [`${taskRoot}/FROZEN_MATRIX_CANONICAL_VIEW.json`, ["cf774c44e6394cf20350d71a10600f4a7cc628fd8e830bb8e5a9bfe4d8a54fcb", 68681]],
  [`${taskRoot}/FROZEN_EVALUATION_ORACLE_CANONICAL_VIEW.json`, ["d7bf4baf52763dc4a966fd4cf7c2d81c205097a612623afaa477cd3f7375ff64", 975]],
  [`${taskRoot}/INDEPENDENT_AGGREGATE.json`, ["c0d1f25d9b64c40ef70beec081fb38500785fba8cf80e7a4259931eaa3ecf9e0", 618]],
  [`${taskRoot}/FORMAL_EVIDENCE_MANIFEST.json`, ["d81c07078dba6bec3b347bf45fbbfb13c15a152a0bb3488e82fc3fafbd511bb5", 166909]],
  [`${taskRoot}/BASELINE_REPORT.json`, ["4b3dcd915008a2840a145e0f7d8160eca5dfe60ec72d6371ca4be59744d59f9b", 2927]],
  [`${taskRoot}/formal-evidence-v1/formal-runtime-receipt.json`, ["f9031532abe09bfebd2498bb6fe66cbfcafc76fbe15df0813819771c02bec5f0", 678]],
]);
const bytesAt = (listedPath) => {
  const absolute = path.isAbsolute(listedPath)
    ? listedPath
    : path.join(repositoryRoot, listedPath);
  const stat = fs.lstatSync(absolute);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) {
    fail("P1_117_REQUIRED_IDENTITY_TYPE_INVALID");
  }
  return fs.readFileSync(absolute);
};
for (const [listedPath, [sha256, byteLength]] of expected) {
  const bytes = bytesAt(listedPath);
  if (
    bytes.length !== byteLength
    || crypto.createHash("sha256").update(bytes).digest("hex") !== sha256
  ) {
    fail("P1_117_REQUIRED_IDENTITY_MISMATCH");
  }
}

const preregistrationPath =
  "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/preregistration.json";
const preregistrationBytes = bytesAt(preregistrationPath);
const preregistrationBinding = {
  path: preregistrationPath,
  ...identityOf(preregistrationBytes),
};
const preregistration = parseFrozenJson(
  preregistrationBytes,
  "PREREGISTRATION_SCHEMA_INVALID",
);
if (
  preregistration.status !== "FROZEN_BEFORE_SECRET_OR_PROVIDER"
  || preregistration.authority_binding_semantics
    !== "EXECUTION_TIME_PRE_PROVIDER_SNAPSHOT_NOT_LIVE_POST_COMPLETION_EQUALITY"
  || preregistration.freeze_boundary.secret_reads_before_freeze !== 0
  || preregistration.freeze_boundary.provider_requests_before_freeze !== 0
  || preregistration.freeze_boundary.network_connections_before_freeze !== 0
) {
  fail("P1_117_PREREGISTRATION_BOUNDARY_INVALID");
}

for (const [name, binding] of Object.entries(preregistration.frozen_artifacts)) {
  readBoundFile(
    repositoryRoot,
    binding,
    `${name.toUpperCase()}_IDENTITY_MISMATCH`,
  );
}
for (const binding of Object.values(preregistration.external_authorities)) {
  readAbsoluteBoundFile(binding, "EXTERNAL_AUTHORITY_IDENTITY_MISMATCH");
}
for (const name of ["evaluation_protocol", "baseline_adapter_contract", "task_contract"]) {
  readBoundFile(
    repositoryRoot,
    preregistration.canonical_authorities[name],
    "CANONICAL_AUTHORITY_IDENTITY_MISMATCH",
  );
}

const matrix = parseFrozenJson(
  readBoundFile(
    repositoryRoot,
    preregistration.frozen_artifacts.matrix_plan,
    "MATRIX_IDENTITY_MISMATCH",
  ).bytes,
  "MATRIX_SCHEMA_INVALID",
);
validateMatrix(repositoryRoot, matrix);
validateP2Preregistration(parseFrozenJson(
  readBoundFile(
    repositoryRoot,
    preregistration.frozen_artifacts.p2_context_preregistration,
    "P2_PREREGISTRATION_IDENTITY_MISMATCH",
  ).bytes,
  "P2_PREREGISTRATION_BUDGET_INVALID",
));
const executableReceipt = parseCanonicalJson(
  bytesAt(`${taskRoot}/EXACT_EXECUTABLE_IDENTITY_FREEZE_RECEIPT.json`),
  "EXECUTABLE_FREEZE_RECEIPT_INVALID",
);
validateExecutableFreezeReceipt(
  repositoryRoot,
  matrix,
  executableReceipt,
  preregistration.frozen_artifacts.matrix_plan,
  preregistrationBinding,
);

const preSecret = parseCanonicalJson(
  bytesAt(`${taskRoot}/P1_117_PRE_SECRET_PRE_PROVIDER_RECEIPT.json`),
  "PRE_SECRET_RECEIPT_INVALID",
);
if (
  preSecret.status !== "PASS"
  || preSecret.offline_preflight.scheduled_runs !== 36
  || preSecret.offline_preflight.provider_requests !== 0
  || preSecret.offline_preflight.secret_reads !== 0
  || preSecret.offline_preflight.network_connections !== 0
) {
  fail("P1_117_PRE_SECRET_RECEIPT_INVALID");
}

const runtimeReceipt = parseCanonicalJson(
  bytesAt(`${taskRoot}/formal-evidence-v1/formal-runtime-receipt.json`),
  "FORMAL_RUNTIME_RECEIPT_INVALID",
);
if (
  runtimeReceipt.status !== "COMPLETE"
  || runtimeReceipt.scheduled_runs !== 36
  || runtimeReceipt.completed_run_manifests !== 36
  || runtimeReceipt.provider_requests !== 36
  || runtimeReceipt.automatic_retries !== 0
  || runtimeReceipt.secret_reads !== 1
  || runtimeReceipt.provider_session_closed !== true
  || runtimeReceipt.owned_secret_buffer_overwrite_attempted !== true
  || runtimeReceipt.whole_process_memory_zeroization_claim !== "NOT_CLAIMED"
) {
  fail("P1_117_FORMAL_RUNTIME_RECEIPT_INVALID");
}

const manifest = parseCanonicalJson(
  bytesAt(`${taskRoot}/FORMAL_EVIDENCE_MANIFEST.json`),
  "FORMAL_EVIDENCE_MANIFEST_INVALID",
);
const formalRoot = path.join(taskRoot, "formal-evidence-v1");
const actualFiles = [];
const visit = (directory) => {
  for (const name of fs.readdirSync(directory).sort()) {
    const absolute = path.join(directory, name);
    const stat = fs.lstatSync(absolute);
    if (stat.isSymbolicLink()) fail("P1_117_FORMAL_EVIDENCE_SYMLINK");
    if (stat.isDirectory()) visit(absolute);
    else if (stat.isFile() && stat.nlink === 1) {
      const bytes = fs.readFileSync(absolute);
      actualFiles.push({
        path: path.relative(formalRoot, absolute).split(path.sep).join("/"),
        ...identityOf(bytes),
      });
    } else fail("P1_117_FORMAL_EVIDENCE_TYPE_INVALID");
  }
};
visit(formalRoot);
if (
  manifest.status !== "COMPLETE"
  || manifest.root !== formalRoot
  || manifest.file_count !== 926
  || !sameJson(manifest.files, actualFiles)
) {
  fail("P1_117_FORMAL_EVIDENCE_MANIFEST_MISMATCH");
}

const aggregate = parseCanonicalJson(
  bytesAt(`${taskRoot}/INDEPENDENT_AGGREGATE.json`),
  "AGGREGATE_INVALID",
);
if (
  aggregate.scheduled !== 36
  || aggregate.eligible !== 36
  || aggregate.verified_successes !== 0
  || aggregate.failures !== 36
  || aggregate.invalids !== 0
  || aggregate.vtsr_fraction !== "0/36"
  || aggregate.reason_distribution.PROVIDER_HTTP_NON_PASS !== 36
  || aggregate.false_accepts !== 0
  || aggregate.accounting.provider_requests !== 36
  || aggregate.accounting.successful_loopback_connections !== 36
  || aggregate.accounting.automatic_retries !== 0
) {
  fail("P1_117_AGGREGATE_RESULT_MISMATCH");
}
parseCanonicalJson(
  bytesAt(`${taskRoot}/FROZEN_MATRIX_CANONICAL_VIEW.json`),
  "MATRIX_CANONICAL_VIEW_INVALID",
);
parseCanonicalJson(
  bytesAt(`${taskRoot}/FROZEN_EVALUATION_ORACLE_CANONICAL_VIEW.json`),
  "ORACLE_CANONICAL_VIEW_INVALID",
);
const report = parseCanonicalJson(
  bytesAt(`${taskRoot}/BASELINE_REPORT.json`),
  "BASELINE_REPORT_INVALID",
);
if (
  report.status !== "COMPLETE_PENDING_CANDIDATE_REVIEW_AND_CANONICAL_GATE"
  || !sameJson(report.result, {
    eligible: 36,
    failures: 36,
    false_accepts: 0,
    invalids: 0,
    reason_distribution: { PROVIDER_HTTP_NON_PASS: 36 },
    scheduled: 36,
    verified_successes: 0,
    vtsr_fraction: "0/36",
  })
) {
  fail("P1_117_BASELINE_REPORT_MISMATCH");
}
NODE

while IFS= read -r module; do
  "${NODE_BIN}" --check "${module}" >/dev/null
done < <(
  find \
    "${ROOT_DIR}/evaluation-harness/evaluator/p1-117-clean-room-empirical-baseline" \
    "${ROOT_DIR}/evaluation-harness/harness/p1-117-clean-room-empirical-baseline" \
    "${ROOT_DIR}/evaluation-harness/recording/p1-117-clean-room-empirical-baseline" \
    "${ROOT_DIR}/evaluation-harness/replay/p1-117-clean-room-empirical-baseline" \
    "${ROOT_DIR}/evaluation-harness/validators/p1-117-clean-room-empirical-baseline" \
    -type f -name '*.mjs' | LC_ALL=C sort
)

"${NODE_BIN}" "${WORKER_SELF_TEST}" >/dev/null
"${NODE_BIN}" "${QUALITY_SELF_TEST}" >/dev/null
cmp -s \
  <(
    "${NODE_BIN}" "${EVALUATOR}" \
      --repository-root "${ROOT_DIR}" \
      --artifact-root "${FORMAL_ROOT}" \
      --matrix "${MATRIX_VIEW}" \
      --oracle "${ORACLE_VIEW}"
  ) \
  "${AGGREGATE}"

printf '%s\n' \
  'P1_117_CLEAN_ROOM_EMPIRICAL_BASELINE: PASS scheduled=36 eligible=36 verified=0 failures=36 reason=PROVIDER_HTTP_NON_PASS'

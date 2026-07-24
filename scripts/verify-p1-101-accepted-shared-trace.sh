#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NODE_BIN="/usr/local/bin/node"
readonly WORKER_ENTRY="${ROOT_DIR}/evaluation-harness/harness/p1-101-accepted-shared-trace/run.mjs"
readonly QUALITY_SELF_TEST="${ROOT_DIR}/evaluation-harness/evaluator/p1-101-accepted-shared-trace/self-test.mjs"
readonly QUALITY_MATRIX="${ROOT_DIR}/evaluation-harness/evaluator/p1-101-accepted-shared-trace/run-matrix.mjs"

if [[ ! -x "${NODE_BIN}" ]]; then
  printf '%s\n' '{"reason":"NODE_EXECUTABLE_UNAVAILABLE","status":"NON_PASS"}' >&2
  exit 1
fi

for required_path in "${WORKER_ENTRY}" "${QUALITY_SELF_TEST}" "${QUALITY_MATRIX}"; do
  if [[ ! -f "${required_path}" || -L "${required_path}" ]]; then
    printf '%s\n' '{"reason":"P1_101_REQUIRED_INPUT_INVALID","status":"NON_PASS"}' >&2
    exit 1
  fi
done

umask 077
P1_101_VERIFIER_ROOT="$(mktemp -d /private/tmp/sourcelens-p1-101-verifier.XXXXXXXX)"
chmod 700 "${P1_101_VERIFIER_ROOT}"
readonly P1_101_VERIFIER_ROOT
readonly P1_101_VERIFIER_DEV="$(/usr/bin/stat -f '%d' "${P1_101_VERIFIER_ROOT}")"
readonly P1_101_VERIFIER_INO="$(/usr/bin/stat -f '%i' "${P1_101_VERIFIER_ROOT}")"
readonly P1_101_MATRIX_ROOT="${P1_101_VERIFIER_ROOT}/matrix-output"

cleanup_owned_root() {
  "${NODE_BIN}" --input-type=module - \
    "${P1_101_VERIFIER_ROOT}" \
    "${P1_101_VERIFIER_DEV}" \
    "${P1_101_VERIFIER_INO}" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const [root, expectedDevText, expectedInoText] = process.argv.slice(2);
const fail = (reason) => {
  process.stderr.write(`${JSON.stringify({ reason, status: "NON_PASS" })}\n`);
  process.exit(1);
};

if (!root.startsWith("/private/tmp/sourcelens-p1-101-verifier.")) {
  fail("P1_101_CLEANUP_SCOPE_INVALID");
}

let rootStat;
try {
  rootStat = fs.lstatSync(root, { bigint: true });
} catch (error) {
  if (error?.code === "ENOENT") process.exit(0);
  fail("P1_101_CLEANUP_ROOT_LSTAT_FAILED");
}

if (
  !rootStat.isDirectory() ||
  rootStat.isSymbolicLink() ||
  rootStat.uid !== BigInt(process.getuid()) ||
  rootStat.dev !== BigInt(expectedDevText) ||
  rootStat.ino !== BigInt(expectedInoText) ||
  fs.realpathSync(root) !== root
) {
  fail("P1_101_CLEANUP_ROOT_IDENTITY_MISMATCH");
}

const removeNoFollow = (target) => {
  const stat = fs.lstatSync(target, { bigint: true });
  if (stat.dev !== rootStat.dev || stat.uid !== rootStat.uid) {
    fail("P1_101_CLEANUP_CHILD_IDENTITY_MISMATCH");
  }
  if (stat.isSymbolicLink() || stat.isFile()) {
    fs.unlinkSync(target);
    return;
  }
  if (!stat.isDirectory()) fail("P1_101_CLEANUP_CHILD_TYPE_INVALID");
  for (const entry of fs.readdirSync(target)) {
    removeNoFollow(path.join(target, entry));
  }
  fs.rmdirSync(target);
};

removeNoFollow(root);
if (fs.existsSync(root)) fail("P1_101_CLEANUP_NOT_EXACT");
NODE
}

trap cleanup_owned_root EXIT

"${NODE_BIN}" --check "${WORKER_ENTRY}"
"${NODE_BIN}" --check "${QUALITY_SELF_TEST}"
"${NODE_BIN}" --check "${QUALITY_MATRIX}"
"${NODE_BIN}" "${QUALITY_SELF_TEST}"
"${NODE_BIN}" "${QUALITY_MATRIX}" \
  --worker-entry "${WORKER_ENTRY}" \
  --output-root "${P1_101_MATRIX_ROOT}"

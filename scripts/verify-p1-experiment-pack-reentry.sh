#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NODE_BIN="/usr/local/bin/node"
HARNESS_PATH="$ROOT_DIR/evaluation-harness/harness/experiment-pack-reentry-v1/experiment-pack.mjs"
TASK_CARD_PATH="$ROOT_DIR/evaluation-harness/fixtures/experiment-pack-reentry-v1/task-card.json"
FREEZE_RECEIPT_PATH="/Users/lijunpeng/Developer/.sourcelens-audit/p1-048-actual-experiment-pack/quality-freeze/TASK_CARD_FREEZE_RECEIPT.json"
DATASET_VERIFIER="$ROOT_DIR/scripts/verify-p1-task-dataset.sh"
AUTHORIZED_EVIDENCE_ROOT="/Users/lijunpeng/Developer/.sourcelens-audit/p1-048-actual-experiment-pack"
EXPECTED_TASK_ID="AIOS-P1-048_ACTUAL_EXECUTION_EXPERIMENT_PACK"
EXPECTED_CONTROL_ID="SL-P1-REP-006-DEDUPE-REFACTOR"

EXPECTED_TASK_CARD_SHA256="15cb56812e348fcca3238467db4e7cdedd9b9210ddedc1568d44b1eeb82f854f"
EXPECTED_TASK_CARD_BYTES="10348"
EXPECTED_TASK_CARD_BLOB="e788aefa84f7d43da086e240bb901b59596c1632"
EXPECTED_RECEIPT_SHA256="846bcbd51ec64acbc2236ed9b7f3aee821a7300f5a23b762b707e953ad2bae66"
EXPECTED_RECEIPT_BYTES="4140"

VERIFY_EVIDENCE_ROOT_IDENTITY=""
VERIFY_RUN_A_ID=""
VERIFY_RUN_B_ID=""
VERIFY_RUN_A_IDENTITY=""
VERIFY_RUN_B_IDENTITY=""

cleanup() {
  local cleanup_status=0

  if [[ -z "$VERIFY_RUN_A_ID" && -z "$VERIFY_RUN_B_ID" ]]; then
    return 0
  fi

  if [[ -z "$VERIFY_EVIDENCE_ROOT_IDENTITY" ]]; then
    echo "Refusing to clean verifier runs without the authorized Evidence root identity" >&2
    return 1
  fi

  if ! "$NODE_BIN" --input-type=module - \
    "$AUTHORIZED_EVIDENCE_ROOT" \
    "$VERIFY_EVIDENCE_ROOT_IDENTITY" \
    "$EXPECTED_TASK_ID" \
    "$EXPECTED_CONTROL_ID" \
    "$VERIFY_RUN_A_ID" \
    "$VERIFY_RUN_A_IDENTITY" \
    "$VERIFY_RUN_B_ID" \
    "$VERIFY_RUN_B_IDENTITY" <<'NODE'
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { basename, dirname, join, relative, sep } from "node:path";

const [root, expectedRootIdentity, taskId, controlId, runA, tokenA, runB, tokenB] = process.argv.slice(2);
const runPattern = /^[a-z0-9][a-z0-9._-]{0,63}$/;

function fail(message) {
  throw new Error(message);
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function identity(path, requireDirectory = false) {
  const stat = lstatSync(path);
  if (stat.isSymbolicLink()) fail(`symlink forbidden during cleanup: ${path}`);
  if (requireDirectory ? !stat.isDirectory() : (!stat.isFile() || stat.nlink !== 1)) {
    fail(`unexpected cleanup object identity: ${path}`);
  }
  return requireDirectory
    ? { dev: String(stat.dev), ino: String(stat.ino) }
    : { dev: String(stat.dev), ino: String(stat.ino), byte_length: stat.size, sha256: digest(readFileSync(path)) };
}

function sameIdentity(actual, expected, label) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) fail(`${label} identity drift`);
}

function directRunPath(runId) {
  if (!runPattern.test(runId)) fail(`invalid verifier run id: ${runId}`);
  const path = join(root, runId);
  if (dirname(path) !== root || basename(path) !== runId || relative(root, path).includes(sep)) {
    fail(`verifier run is not a direct child: ${runId}`);
  }
  return path;
}

function readJsonArtifact(path) {
  const artifactIdentity = identity(path);
  return { artifactIdentity, value: JSON.parse(readFileSync(path, "utf8")) };
}

function validateRun(runId, encodedToken) {
  const path = directRunPath(runId);
  let directoryStat;
  try {
    directoryStat = lstatSync(path);
  } catch (error) {
    if (error.code === "ENOENT" && encodedToken === "") return null;
    throw error;
  }
  if (encodedToken === "") fail(`unbound verifier run exists and will be preserved: ${path}`);
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) fail(`verifier run directory drift: ${path}`);

  const token = JSON.parse(Buffer.from(encodedToken, "base64url").toString("utf8"));
  if (token.run_id !== runId) fail(`verifier run token mismatch: ${runId}`);
  sameIdentity(identity(path, true), token.directory, `${runId} directory`);

  const resultPath = join(path, "result.json");
  const manifestPath = join(path, "manifest.json");
  const result = readJsonArtifact(resultPath);
  const manifest = readJsonArtifact(manifestPath);
  sameIdentity(result.artifactIdentity, token.result, `${runId} result.json`);
  sameIdentity(manifest.artifactIdentity, token.manifest, `${runId} manifest.json`);

  for (const [label, document] of [["result", result.value], ["manifest", manifest.value]]) {
    if (document.task_id !== taskId || document.control_id !== controlId
        || document.run_id !== runId || document.verdict !== "PASS") {
      fail(`${runId} ${label} binding drift`);
    }
  }
  if (result.value.physical_path !== path
      || result.value.evidence_root?.physical_path !== root
      || result.value.evidence_root?.realpath !== root) {
    fail(`${runId} physical Evidence binding drift`);
  }

  return path;
}

const rootStat = lstatSync(root);
if (!rootStat.isDirectory() || rootStat.isSymbolicLink() || realpathSync(root) !== root) {
  fail("authorized Evidence root identity invalid during cleanup");
}
const actualRootIdentity = `${rootStat.dev}:${rootStat.ino}`;
if (actualRootIdentity !== expectedRootIdentity) fail("authorized Evidence root identity drift");

const paths = [];
for (const [runId, token] of [[runA, tokenA], [runB, tokenB]]) {
  if (runId !== "") {
    const path = validateRun(runId, token);
    if (path !== null) paths.push(path);
  }
}

for (const path of paths) rmSync(path, { recursive: true, force: false });
for (const path of paths) {
  try {
    lstatSync(path);
    fail(`verifier run cleanup did not remove: ${path}`);
  } catch (error) {
    if (error.message?.startsWith("verifier run cleanup")) throw error;
    if (error.code !== "ENOENT") throw error;
  }
}

const finalRootStat = lstatSync(root);
const finalRootIdentity = `${finalRootStat.dev}:${finalRootStat.ino}`;
if (finalRootIdentity !== expectedRootIdentity) fail("authorized Evidence root changed during cleanup");
NODE
  then
    echo "Verifier-owned Evidence cleanup validation failed; preserving all unverified objects" >&2
    return 1
  fi

  VERIFY_RUN_A_ID=""
  VERIFY_RUN_B_ID=""
  VERIFY_RUN_A_IDENTITY=""
  VERIFY_RUN_B_IDENTITY=""
  VERIFY_EVIDENCE_ROOT_IDENTITY=""
  return "$cleanup_status"
}

bind_run_identity() {
  local run_id="$1"

  "$NODE_BIN" --input-type=module - \
    "$AUTHORIZED_EVIDENCE_ROOT" \
    "$VERIFY_EVIDENCE_ROOT_IDENTITY" \
    "$EXPECTED_TASK_ID" \
    "$EXPECTED_CONTROL_ID" \
    "$run_id" <<'NODE'
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, realpathSync } from "node:fs";
import { basename, dirname, join, relative, sep } from "node:path";

const [root, expectedRootIdentity, taskId, controlId, runId] = process.argv.slice(2);
const runPattern = /^[a-z0-9][a-z0-9._-]{0,63}$/;

function fail(message) {
  throw new Error(message);
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function fileIdentity(path) {
  const stat = lstatSync(path);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) {
    fail(`Evidence artifact identity invalid: ${path}`);
  }
  return {
    dev: String(stat.dev),
    ino: String(stat.ino),
    byte_length: stat.size,
    sha256: digest(readFileSync(path)),
  };
}

const rootStat = lstatSync(root);
if (!rootStat.isDirectory() || rootStat.isSymbolicLink() || realpathSync(root) !== root) {
  fail("authorized Evidence root identity invalid");
}
if (`${rootStat.dev}:${rootStat.ino}` !== expectedRootIdentity) {
  fail("authorized Evidence root identity drift while binding run");
}
if (!runPattern.test(runId)) fail("invalid verifier run id");
const runPath = join(root, runId);
if (dirname(runPath) !== root || basename(runPath) !== runId || relative(root, runPath).includes(sep)) {
  fail("verifier run is not a direct child of the authorized root");
}
const runStat = lstatSync(runPath);
if (!runStat.isDirectory() || runStat.isSymbolicLink() || realpathSync(runPath) !== runPath) {
  fail("verifier run directory identity invalid");
}

const resultPath = join(runPath, "result.json");
const manifestPath = join(runPath, "manifest.json");
const resultIdentity = fileIdentity(resultPath);
const manifestIdentity = fileIdentity(manifestPath);
const result = JSON.parse(readFileSync(resultPath, "utf8"));
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
for (const [label, document] of [["result", result], ["manifest", manifest]]) {
  if (document.task_id !== taskId || document.control_id !== controlId
      || document.run_id !== runId || document.verdict !== "PASS") {
    fail(`${label} task/control/run/PASS binding mismatch`);
  }
}
if (result.physical_path !== runPath
    || result.evidence_root?.physical_path !== root
    || result.evidence_root?.realpath !== root) {
  fail("result physical Evidence binding mismatch");
}

const token = {
  run_id: runId,
  directory: { dev: String(runStat.dev), ino: String(runStat.ino) },
  result: resultIdentity,
  manifest: manifestIdentity,
};
process.stdout.write(Buffer.from(JSON.stringify(token), "utf8").toString("base64url"));
NODE
}

on_exit() {
  local prior_status=$?
  local cleanup_status=0

  trap - EXIT
  cleanup || cleanup_status=$?
  if [[ "$prior_status" -ne 0 ]]; then
    exit "$prior_status"
  fi
  exit "$cleanup_status"
}

trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -x "$NODE_BIN" ]]; then
  echo "AIOS P1-048 verifier requires executable Node.js at: $NODE_BIN" >&2
  exit 1
fi

if [[ ! -f "$HARNESS_PATH" || -L "$HARNESS_PATH" ]]; then
  echo "AIOS P1-048 harness is missing or not a regular non-symlink file: $HARNESS_PATH" >&2
  exit 1
fi

if [[ ! -x "$DATASET_VERIFIER" || -L "$DATASET_VERIFIER" ]]; then
  echo "Accepted P1-035 regression verifier is missing, non-executable, or symlinked: $DATASET_VERIFIER" >&2
  exit 1
fi

"$NODE_BIN" --input-type=module - \
  "$TASK_CARD_PATH" \
  "$FREEZE_RECEIPT_PATH" \
  "$EXPECTED_TASK_CARD_SHA256" \
  "$EXPECTED_TASK_CARD_BYTES" \
  "$EXPECTED_TASK_CARD_BLOB" \
  "$EXPECTED_RECEIPT_SHA256" \
  "$EXPECTED_RECEIPT_BYTES" <<'NODE'
import { createHash } from "node:crypto";
import { lstatSync, readFileSync } from "node:fs";

const [
  taskCardPath,
  receiptPath,
  expectedTaskCardSha256,
  expectedTaskCardBytesText,
  expectedTaskCardBlob,
  expectedReceiptSha256,
  expectedReceiptBytesText,
] = process.argv.slice(2);

function digest(buffer, algorithm = "sha256") {
  return createHash(algorithm).update(buffer).digest("hex");
}

function requireFrozenRegularFile(path, expectedBytes, expectedSha256, label) {
  const stat = lstatSync(path);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) {
    throw new Error(`${label} must be a regular, non-symlinked, nlink=1 file`);
  }
  const bytes = readFileSync(path);
  if (stat.size !== expectedBytes || bytes.length !== expectedBytes) {
    throw new Error(`${label} byte length drift`);
  }
  if (digest(bytes) !== expectedSha256) {
    throw new Error(`${label} SHA-256 drift`);
  }
  return bytes;
}

const expectedTaskCardBytes = Number(expectedTaskCardBytesText);
const expectedReceiptBytes = Number(expectedReceiptBytesText);
const cardBytes = requireFrozenRegularFile(
  taskCardPath,
  expectedTaskCardBytes,
  expectedTaskCardSha256,
  "P1-048 Task Card",
);
const receiptBytes = requireFrozenRegularFile(
  receiptPath,
  expectedReceiptBytes,
  expectedReceiptSha256,
  "P1-048 Quality freeze receipt",
);

const gitBlob = createHash("sha1")
  .update(Buffer.from(`blob ${cardBytes.length}\0`, "utf8"))
  .update(cardBytes)
  .digest("hex");
if (gitBlob !== expectedTaskCardBlob) throw new Error("P1-048 Task Card Git blob drift");

const card = JSON.parse(cardBytes.toString("utf8"));
const receipt = JSON.parse(receiptBytes.toString("utf8"));
if (card.task_id !== "AIOS-P1-048_ACTUAL_EXECUTION_EXPERIMENT_PACK"
    || card.control_id !== "SL-P1-REP-006-DEDUPE-REFACTOR") {
  throw new Error("P1-048 Task Card task/control binding drift");
}
if (receipt.task_id !== card.task_id
    || receipt.control_id !== card.control_id
    || receipt.target_verdict !== "PASS"
    || receipt.freeze_effective !== true) {
  throw new Error("P1-048 Quality freeze PASS binding is not effective");
}
if (receipt.task_card?.sha256 !== expectedTaskCardSha256
    || receipt.task_card?.byte_length !== expectedTaskCardBytes
    || receipt.task_card?.git_blob !== expectedTaskCardBlob
    || receipt.task_card?.file_type !== "regular"
    || receipt.task_card?.nlink !== 1) {
  throw new Error("P1-048 Quality freeze receipt does not bind the exact Task Card");
}
NODE

"$NODE_BIN" --check "$HARNESS_PATH"

cd "$ROOT_DIR"

"$NODE_BIN" \
  evaluation-harness/harness/experiment-pack-reentry-v1/experiment-pack.mjs \
  self-test \
  --task-card evaluation-harness/fixtures/experiment-pack-reentry-v1/task-card.json

NODE_BIN="$NODE_BIN" ./scripts/verify-p1-task-dataset.sh

IFS=$'\t' read -r VERIFY_EVIDENCE_ROOT_IDENTITY VERIFY_RUN_A_ID VERIFY_RUN_B_ID < <(
  "$NODE_BIN" --input-type=module - "$AUTHORIZED_EVIDENCE_ROOT" <<'NODE'
import { randomBytes } from "node:crypto";
import { lstatSync, realpathSync } from "node:fs";
import { basename, dirname, join } from "node:path";

const root = process.argv[2];
const rootStat = lstatSync(root);
if (!rootStat.isDirectory() || rootStat.isSymbolicLink() || realpathSync(root) !== root) {
  throw new Error("authorized Evidence root must be an exact real non-symlink directory");
}

function pathIsAbsent(path) {
  try {
    lstatSync(path);
    return false;
  } catch (error) {
    if (error.code === "ENOENT") return true;
    throw error;
  }
}

function freshRunId() {
  for (let attempt = 0; attempt < 32; attempt += 1) {
    const runId = `verifier-${randomBytes(16).toString("hex")}`;
    const path = join(root, runId);
    if (dirname(path) === root && basename(path) === runId && pathIsAbsent(path)) return runId;
  }
  throw new Error("could not allocate an absent cryptographically unique verifier run id");
}

const runA = freshRunId();
let runB = freshRunId();
while (runB === runA) runB = freshRunId();
process.stdout.write(`${rootStat.dev}:${rootStat.ino}\t${runA}\t${runB}\n`);
NODE
)

if [[ -z "$VERIFY_EVIDENCE_ROOT_IDENTITY" || -z "$VERIFY_RUN_A_ID" || -z "$VERIFY_RUN_B_ID" \
      || "$VERIFY_RUN_A_ID" == "$VERIFY_RUN_B_ID" ]]; then
  echo "Failed to allocate two distinct verifier-owned run identities" >&2
  exit 1
fi

"$NODE_BIN" \
  evaluation-harness/harness/experiment-pack-reentry-v1/experiment-pack.mjs \
  run \
  --task-card evaluation-harness/fixtures/experiment-pack-reentry-v1/task-card.json \
  --evidence-root "$AUTHORIZED_EVIDENCE_ROOT" \
  --run-id "$VERIFY_RUN_A_ID"

VERIFY_RUN_A_IDENTITY="$(bind_run_identity "$VERIFY_RUN_A_ID")"

"$NODE_BIN" \
  evaluation-harness/harness/experiment-pack-reentry-v1/experiment-pack.mjs \
  run \
  --task-card evaluation-harness/fixtures/experiment-pack-reentry-v1/task-card.json \
  --evidence-root "$AUTHORIZED_EVIDENCE_ROOT" \
  --run-id "$VERIFY_RUN_B_ID"

VERIFY_RUN_B_IDENTITY="$(bind_run_identity "$VERIFY_RUN_B_ID")"

/usr/bin/cmp -s \
  "$AUTHORIZED_EVIDENCE_ROOT/$VERIFY_RUN_A_ID/stable-projection.json" \
  "$AUTHORIZED_EVIDENCE_ROOT/$VERIFY_RUN_B_ID/stable-projection.json"

"$NODE_BIN" --input-type=module - \
  "$EXPECTED_TASK_ID" \
  "$EXPECTED_CONTROL_ID" \
  "$VERIFY_RUN_A_ID" \
  "$AUTHORIZED_EVIDENCE_ROOT/$VERIFY_RUN_A_ID/result.json" \
  "$AUTHORIZED_EVIDENCE_ROOT/$VERIFY_RUN_A_ID/stable-projection.json" \
  "$VERIFY_RUN_B_ID" \
  "$AUTHORIZED_EVIDENCE_ROOT/$VERIFY_RUN_B_ID/result.json" \
  "$AUTHORIZED_EVIDENCE_ROOT/$VERIFY_RUN_B_ID/stable-projection.json" <<'NODE'
import { lstatSync, readFileSync } from "node:fs";

const [taskId, controlId, runA, resultA, stableA, runB, resultB, stableB] = process.argv.slice(2);
for (const [runId, resultPath, stablePath] of [[runA, resultA, stableA], [runB, resultB, stableB]]) {
  for (const path of [resultPath, stablePath]) {
    const stat = lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) {
      throw new Error(`Smoke artifact is not a regular, non-symlinked, nlink=1 file: ${path}`);
    }
  }
  const result = JSON.parse(readFileSync(resultPath, "utf8"));
  const stable = JSON.parse(readFileSync(stablePath, "utf8"));
  if (result.task_id !== taskId || result.control_id !== controlId
      || result.run_id !== runId || result.verdict !== "PASS") {
    throw new Error(`Smoke result binding did not PASS: ${resultPath}`);
  }
  if (stable.task_id !== taskId || stable.control_id !== controlId || stable.verdict !== "PASS") {
    throw new Error(`Smoke stable projection binding did not PASS: ${stablePath}`);
  }
}
NODE

cleanup
trap - EXIT
echo "AIOS P1-048 actual Experiment Pack targeted verification PASS"

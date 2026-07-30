#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NODE_BIN="/usr/local/bin/node"
readonly HARNESS_DIR="${ROOT_DIR}/evaluation-harness/harness/p1-165-fail-closed-response-admission"
readonly EVALUATOR_DIR="${ROOT_DIR}/evaluation-harness/evaluator/p1-165-fail-closed-response-admission"
readonly PREFLIGHT="${HARNESS_DIR}/preflight.mjs"
readonly EVALUATOR="${EVALUATOR_DIR}/evaluate.mjs"
readonly MATRIX="${EVALUATOR_DIR}/matrix.json"

if [[ ! -x "${NODE_BIN}" ]]; then
  printf '%s\n' '{"reason_code":"NODE_EXECUTABLE_UNAVAILABLE","status":"NON_PASS"}' >&2
  exit 1
fi

for required_path in \
  "${HARNESS_DIR}/contract.mjs" \
  "${HARNESS_DIR}/transport.mjs" \
  "${HARNESS_DIR}/observer.mjs" \
  "${HARNESS_DIR}/admission.mjs" \
  "${PREFLIGHT}" \
  "${EVALUATOR}" \
  "${MATRIX}"; do
  if [[ ! -f "${required_path}" || -L "${required_path}" ]]; then
    printf '%s\n' \
      "{\"path\":\"${required_path}\",\"reason_code\":\"P1_165_REQUIRED_INPUT_INVALID\",\"status\":\"NON_PASS\"}" >&2
    exit 1
  fi
done

while IFS= read -r module_path; do
  "${NODE_BIN}" --check "${module_path}"
done <<EOF
${HARNESS_DIR}/contract.mjs
${HARNESS_DIR}/transport.mjs
${HARNESS_DIR}/observer.mjs
${HARNESS_DIR}/admission.mjs
${PREFLIGHT}
${EVALUATOR}
EOF

"${NODE_BIN}" -e '
const fs = require("node:fs");
const crypto = require("node:crypto");
const matrixBytes = fs.readFileSync(process.argv[1]);
if (
  matrixBytes.length !== 59333
  || crypto.createHash("sha256").update(matrixBytes).digest("hex")
    !== "70cde8ec13a8d1f74d309b8d5a1b06579a571a7dfe29b4b8ba9b4cf90bc5bcc6"
) {
  throw new Error("P1-165 negative matrix exact identity drifted");
}
const matrix = JSON.parse(matrixBytes.toString("utf8"));
const expectedCategories = [
  "CLOSED_KEYSET_AND_JOIN",
  "CONCURRENCY",
  "CRITICAL_REASON_PROPAGATION",
  "FILESYSTEM_AND_CLOSED_INVENTORY",
  "LIVENESS",
  "RAW_OS_OBSERVER",
  "SECRET_REFLECTION",
  "TRANSPORT_BOUNDARY_AND_TERMINAL",
  "USAGE_CONTRACT",
];
if (
  matrix.schema_version !== "p1-165-quality-matrix/v1"
  || matrix.task_id !== "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL"
  || !Array.isArray(matrix.categories)
  || JSON.stringify(matrix.categories.map((entry) => entry.category_id).sort())
    !== JSON.stringify(expectedCategories)
) {
  throw new Error("P1-165 negative matrix contract is invalid");
}
const cases = matrix.categories.flatMap((category) => category.cases ?? []);
const ids = cases.map((entry) => entry.case_id);
const expectedStimulusKinds = new Map([
  ["CLOSED_KEYSET_AND_JOIN", "CLOSED_RECORD"],
  ["CONCURRENCY", "CONCURRENCY"],
  ["CRITICAL_REASON_PROPAGATION", "PROPAGATION"],
  ["FILESYSTEM_AND_CLOSED_INVENTORY", "FILESYSTEM"],
  ["LIVENESS", "LIVENESS"],
  ["RAW_OS_OBSERVER", "OBSERVER"],
  ["SECRET_REFLECTION", "SECRET"],
  ["TRANSPORT_BOUNDARY_AND_TERMINAL", "TRANSPORT"],
  ["USAGE_CONTRACT", "USAGE"],
]);
const typedStimulusPlan = matrix.categories.every((category) =>
  category.cases.every((entry) => {
    const outputBoundary =
      Object.hasOwn(entry, "output_tokens")
        || Object.hasOwn(entry, "full_spine_required");
    const expectedCaseKeys = outputBoundary
      ? [
          "case_id",
          "expected_persistence",
          "expected_reason_code",
          "expected_status",
          "full_spine_required",
          "output_tokens",
          "stimulus",
        ]
      : [
          "case_id",
          "expected_persistence",
          "expected_reason_code",
          "expected_status",
          "stimulus",
        ];
    return JSON.stringify(Object.keys(entry).sort())
      === JSON.stringify(expectedCaseKeys)
    && entry.stimulus !== null
    && typeof entry.stimulus === "object"
    && !Array.isArray(entry.stimulus)
    && JSON.stringify(Object.keys(entry.stimulus).sort())
      === JSON.stringify(["kind", "parameters", "variant"])
    && entry.stimulus.kind === expectedStimulusKinds.get(category.category_id)
    && typeof entry.stimulus.variant === "string"
    && entry.stimulus.variant.length > 0
    && entry.stimulus.parameters !== null
    && typeof entry.stimulus.parameters === "object"
    && !Array.isArray(entry.stimulus.parameters);
  }));
const typedUsageCases = cases.filter((entry) =>
  entry.stimulus.kind === "USAGE"
    && entry.stimulus.parameters.output_tokens !== null);
if (
  cases.length !== 99
  || ids.some((value) => typeof value !== "string" || value.length === 0)
  || new Set(ids).size !== ids.length
  || !typedStimulusPlan
  || typedUsageCases.length !== 3
  || JSON.stringify(typedUsageCases.map(
    (entry) => entry.stimulus.parameters.output_tokens,
  ))
    !== JSON.stringify([2047, 2048, 2049])
  || typedUsageCases.some((entry) =>
    !Number.isSafeInteger(entry.stimulus.parameters.output_tokens)
      || typeof entry.stimulus.parameters.full_spine_required !== "boolean"
      || entry.stimulus.parameters.full_spine_required
        !== (entry.stimulus.parameters.output_tokens === 2048))
) {
  throw new Error("P1-165 negative matrix is incomplete or ambiguous");
}
' "${MATRIX}"

"${NODE_BIN}" --input-type=module - "${PREFLIGHT}" "${EVALUATOR}" <<'NODE'
import { pathToFileURL } from "node:url";

const [preflightPath, evaluatorPath] = process.argv.slice(2);
const { validateMatrixChildInputEnvelope } = await import(
  pathToFileURL(preflightPath).href
);
const { expectedCellArtifactPaths } = await import(
  pathToFileURL(evaluatorPath).href
);
const valid = {
  case_id: "CASE_INPUT_KEYSET_SELF_TEST",
  category_id: "SELF_TEST",
  schema_version: "p1-165-matrix-case-input/v1",
  stimulus: {},
  synthetic_observer_fixture: {},
  task_id: "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL",
};
validateMatrixChildInputEnvelope(valid, valid.case_id);
for (const invalid of [
  { ...valid, extra: true },
  Object.fromEntries(
    Object.entries(valid).filter(([key]) => key !== "synthetic_observer_fixture"),
  ),
]) {
  let rejected = false;
  try {
    validateMatrixChildInputEnvelope(invalid, valid.case_id);
  } catch (error) {
    rejected = error?.code === "IDENTITY_MISMATCH";
  }
  if (!rejected) {
    throw new Error("P1-165 matrix child input keyset self-test failed");
  }
}
const expectedCellPaths = expectedCellArtifactPaths();
if (
  expectedCellPaths.length !== 37
  || new Set(expectedCellPaths).size !== expectedCellPaths.length
  || !expectedCellPaths.includes("observer/synthetic-fixture.json")
) {
  throw new Error("P1-165 expected cell artifact path self-test failed");
}
NODE

capture_p1_168_prior_attempt() {
  "${NODE_BIN}" --input-type=module <<'NODE'
import { createHash } from "node:crypto";
import {
  constants as fsConstants,
  closeSync,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
} from "node:fs";
import { isAbsolute, join } from "node:path";

const preflightRoot =
  "/Users/lijunpeng/Developer/.sourcelens-audit/"
  + "p1-exact-p1-165-snapshot-recovery-strict-exit-20260730/"
  + "task-1-p1-168/preflight";
const evidenceRoot = join(preflightRoot, "complete-matrix-v1");
const stageRoot = join(
  preflightRoot,
  ".complete-matrix-v1.p1-165-stage-45fd79a51496b6aefb578548",
);
const expectedArtifacts = {
  manifest: {
    path: join(evidenceRoot, "RAW_EVIDENCE_MANIFEST.json"),
    byte_length: 807791,
    sha256: "b7282c25ee11c3936b8cf007ac813b134f3ab15751147bd3871f0be350be4478",
  },
  atomic_commit_receipt: {
    path: `${evidenceRoot}.p1-165-atomic-commit-receipt.json`,
    byte_length: 18418,
    sha256: "8291cd5e6efe86f1d38b22848ba643e6a72a03001a90d0e6288717d4578d309b",
  },
  wrapper_stdout: {
    path: join(preflightRoot, "COMPLETE_MATRIX_V1_STDOUT.log"),
    byte_length: 3830,
    sha256: "3bb1847b69bc08dcbedbdb118fc9339e6d6f48769dea281056ff4f1bf24bbbce",
  },
  wrapper_stderr: {
    path: join(preflightRoot, "COMPLETE_MATRIX_V1_STDERR.log"),
    byte_length: 4219,
    sha256: "486e415179cdac7b3261eb385513bef6d6f10fef35de3e91e422e0f2176278a9",
  },
  wrapper_exit: {
    path: join(preflightRoot, "COMPLETE_MATRIX_V1_EXIT.json"),
    byte_length: 88,
    sha256: "9afcddfcdb36e232adf62cdc9689a4fc71e930c7b42b02614a0903d69f0110a0",
  },
  evaluator_stdout: {
    path: join(preflightRoot, "P1_168_V1_INDEPENDENT_EVALUATOR_STDOUT.log"),
    byte_length: 4764,
    sha256: "14352e4b33ebd72f6b852ec6e01209163c3e714e22396fd3c9fc88273952d506",
  },
  evaluator_stderr: {
    path: join(preflightRoot, "P1_168_V1_INDEPENDENT_EVALUATOR_STDERR.log"),
    byte_length: 0,
    sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  },
  evaluator_exit: {
    path: join(preflightRoot, "P1_168_V1_INDEPENDENT_EVALUATOR_EXIT.json"),
    byte_length: 1386,
    sha256: "51e07eb1c55ae2d18fae2edc8a565858998cf8e5475bdccc767d6235a72e3b3e",
  },
};

const fail = (message) => {
  throw new Error(`P1-168 prior attempt verification failed: ${message}`);
};
const sha256 = (bytes) =>
  createHash("sha256").update(bytes).digest("hex");
const canonicalJson = (value) => {
  if (value === null) return "null";
  if (typeof value === "string" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) fail("non-finite canonical number");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (typeof value !== "object") fail("unsupported canonical value");
  return `{${Object.keys(value).sort().map(
    (key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`,
  ).join(",")}}`;
};
const readExact = (expected, label) => {
  const before = lstatSync(expected.path);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  if (
    !before.isFile()
    || before.isSymbolicLink()
    || before.nlink !== 1
    || (uid !== null && before.uid !== uid)
  ) {
    fail(`${label} path boundary drifted`);
  }
  let descriptor;
  try {
    descriptor = openSync(
      expected.path,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const opened = fstatSync(descriptor);
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    const finalStat = lstatSync(expected.path);
    if (
      !opened.isFile()
      || opened.nlink !== 1
      || opened.dev !== before.dev
      || opened.ino !== before.ino
      || after.dev !== opened.dev
      || after.ino !== opened.ino
      || !finalStat.isFile()
      || finalStat.isSymbolicLink()
      || finalStat.nlink !== 1
      || finalStat.dev !== opened.dev
      || finalStat.ino !== opened.ino
      || finalStat.size !== opened.size
      || bytes.length !== expected.byte_length
      || sha256(bytes) !== expected.sha256
    ) {
      fail(`${label} exact bytes drifted`);
    }
    return { ...expected, bytes };
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
};

const stageStat = lstatSync(stageRoot);
const uid = typeof process.getuid === "function" ? process.getuid() : null;
if (
  !stageStat.isDirectory()
  || stageStat.isSymbolicLink()
  || (uid !== null && stageStat.uid !== uid)
  || realpathSync(stageRoot) !== stageRoot
) {
  fail("aborted stage root drifted");
}
const stageEntries = [];
let stageBytes = 0;
let directoryCount = 0;
const visit = (directory, relativeDirectory, depth) => {
  const directoryStat = lstatSync(directory);
  directoryCount += 1;
  if (
    !directoryStat.isDirectory()
    || directoryStat.isSymbolicLink()
    || (uid !== null && directoryStat.uid !== uid)
    || (directoryStat.mode & 0o022) !== 0
    || directoryCount > 1024
    || depth > 32
  ) {
    fail("aborted stage directory boundary drifted");
  }
  for (const name of readdirSync(directory).sort()) {
    const absolutePath = join(directory, name);
    const relativePath = relativeDirectory === ""
      ? name
      : `${relativeDirectory}/${name}`;
    const stat = lstatSync(absolutePath);
    if (stat.isSymbolicLink() || (uid !== null && stat.uid !== uid)) {
      fail("aborted stage unsafe entry");
    }
    if (stat.isDirectory()) {
      visit(absolutePath, relativePath, depth + 1);
      continue;
    }
    if (
      !stat.isFile()
      || stat.nlink !== 1
      || stat.size > 32 * 1024 * 1024
      || stageEntries.length >= 1024
      || stageBytes + stat.size > 256 * 1024 * 1024
    ) {
      fail("aborted stage file boundary drifted");
    }
    const bytes = readFileSync(absolutePath);
    stageEntries.push({
      path: relativePath,
      type: "REGULAR_FILE",
      mode: (stat.mode & 0o777).toString(8).padStart(3, "0"),
      byte_length: bytes.length,
      sha256: sha256(bytes),
    });
    stageBytes += bytes.length;
  }
};
visit(stageRoot, "", 0);
stageEntries.sort((left, right) => left.path.localeCompare(right.path));
const stageInventory = {
  entry_count: stageEntries.length,
  total_bytes: stageBytes,
  sha256: sha256(
    Buffer.from(`${canonicalJson(stageEntries)}\n`, "utf8"),
  ),
};
const expectedStageInventory = {
  entry_count: 744,
  total_bytes: 161608624,
  sha256: "18e90cfb2d16c6fe78f152cb96321c44c2706df3591a9dbb997d2ef8f142659b",
};
if (canonicalJson(stageInventory) !== canonicalJson(expectedStageInventory)) {
  fail("aborted stage closed inventory drifted");
}

const observedArtifacts = {};
const artifactBytes = {};
for (const [name, expected] of Object.entries(expectedArtifacts)) {
  const observed = readExact(expected, name);
  observedArtifacts[name] = {
    path: observed.path,
    byte_length: observed.byte_length,
    sha256: observed.sha256,
  };
  artifactBytes[name] = observed.bytes;
}

const completeRootStat = lstatSync(evidenceRoot);
if (
  !completeRootStat.isDirectory()
  || completeRootStat.isSymbolicLink()
  || (uid !== null && completeRootStat.uid !== uid)
  || (completeRootStat.mode & 0o777) !== 0o700
  || realpathSync(evidenceRoot) !== evidenceRoot
) {
  fail("complete Evidence root identity drifted");
}
const completeEntries = [];
let completeBytes = 0;
let completeDirectoryCount = 0;
const visitCompleteRoot = (directory, relativeDirectory, depth) => {
  const directoryStat = lstatSync(directory);
  completeDirectoryCount += 1;
  if (
    !directoryStat.isDirectory()
    || directoryStat.isSymbolicLink()
    || (uid !== null && directoryStat.uid !== uid)
    || (directoryStat.mode & 0o777) !== 0o700
    || completeDirectoryCount > 1024
    || depth > 32
  ) {
    fail("complete Evidence root directory boundary drifted");
  }
  for (const name of readdirSync(directory).sort()) {
    const absolutePath = join(directory, name);
    const relativePath = relativeDirectory === ""
      ? name
      : `${relativeDirectory}/${name}`;
    const before = lstatSync(absolutePath);
    if (before.isSymbolicLink() || (uid !== null && before.uid !== uid)) {
      fail("complete Evidence root contains an unsafe entry");
    }
    if (before.isDirectory()) {
      visitCompleteRoot(absolutePath, relativePath, depth + 1);
      continue;
    }
    if (
      !before.isFile()
      || before.nlink !== 1
      || (before.mode & 0o777) !== 0o600
      || before.size > 32 * 1024 * 1024
      || completeEntries.length >= 4096
      || completeBytes + before.size > 256 * 1024 * 1024
    ) {
      fail("complete Evidence root file boundary drifted");
    }
    let descriptor;
    try {
      descriptor = openSync(
        absolutePath,
        fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
      );
      const opened = fstatSync(descriptor);
      const bytes = readFileSync(descriptor);
      const after = fstatSync(descriptor);
      const finalStat = lstatSync(absolutePath);
      if (
        !opened.isFile()
        || opened.nlink !== 1
        || opened.dev !== before.dev
        || opened.ino !== before.ino
        || opened.size !== before.size
        || after.dev !== opened.dev
        || after.ino !== opened.ino
        || after.size !== opened.size
        || !finalStat.isFile()
        || finalStat.isSymbolicLink()
        || finalStat.nlink !== 1
        || finalStat.dev !== opened.dev
        || finalStat.ino !== opened.ino
        || finalStat.size !== opened.size
        || (finalStat.mode & 0o777) !== 0o600
      ) {
        fail("complete Evidence root file changed during read");
      }
      completeEntries.push({
        path: relativePath,
        type: "REGULAR_FILE",
        mode: "600",
        byte_length: bytes.length,
        sha256: sha256(bytes),
      });
      completeBytes += bytes.length;
    } finally {
      if (descriptor !== undefined) closeSync(descriptor);
    }
  }
};
visitCompleteRoot(evidenceRoot, "", 0);
completeEntries.sort((left, right) => left.path.localeCompare(right.path));
const manifest = JSON.parse(artifactBytes.manifest.toString("utf8"));
if (
  Buffer.compare(
    artifactBytes.manifest,
    Buffer.from(`${canonicalJson(manifest)}\n`, "utf8"),
  ) !== 0
  || canonicalJson(Object.keys(manifest).sort())
    !== canonicalJson([
      "entries",
      "entry_count",
      "matrix_sha256",
      "schema_version",
      "task_id",
    ])
  || manifest.schema_version !== "p1-165-raw-evidence-manifest/v1"
  || manifest.task_id
    !== "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL"
  || manifest.entry_count !== 3829
  || manifest.matrix_sha256
    !== "f9a38ecc512d4c2c8ba536eb3023dc6dfb6f78cfc5203be5853fe68321a5a298"
  || !Array.isArray(manifest.entries)
  || manifest.entries.length !== manifest.entry_count
) {
  fail("complete Evidence manifest schema drifted");
}
const declaredPaths = new Set();
for (const entry of manifest.entries) {
  if (
    entry === null
    || typeof entry !== "object"
    || Array.isArray(entry)
    || canonicalJson(Object.keys(entry).sort())
      !== canonicalJson(["byte_length", "nlink", "path", "sha256", "type"])
    || typeof entry.path !== "string"
    || entry.path.length === 0
    || entry.path.includes("\0")
    || entry.path.includes("\\")
    || isAbsolute(entry.path)
    || entry.path.split("/").includes("..")
    || declaredPaths.has(entry.path)
    || entry.type !== "REGULAR_FILE"
    || entry.nlink !== 1
    || !Number.isSafeInteger(entry.byte_length)
    || entry.byte_length < 0
    || !/^[0-9a-f]{64}$/.test(entry.sha256)
  ) {
    fail("complete Evidence manifest entry is ambiguous or invalid");
  }
  declaredPaths.add(entry.path);
}
const liveDeclaredEntries = completeEntries
  .filter((entry) => entry.path !== "RAW_EVIDENCE_MANIFEST.json")
  .map((entry) => ({
    path: entry.path,
    type: entry.type,
    nlink: 1,
    byte_length: entry.byte_length,
    sha256: entry.sha256,
  }));
if (canonicalJson(manifest.entries) !== canonicalJson(liveDeclaredEntries)) {
  fail("complete Evidence manifest does not bind every live payload file");
}
const completeInventory = {
  entry_count: completeEntries.length,
  total_bytes: completeBytes,
  sha256: sha256(
    Buffer.from(`${canonicalJson(completeEntries)}\n`, "utf8"),
  ),
};
if (canonicalJson(completeInventory) !== canonicalJson({
  entry_count: 3830,
  total_bytes: 167164014,
  sha256: "d083c053e8de09efbfed2d2109c7c861ad0d7fc00e7c8b0dd92c808e32d91a64",
})) {
  fail("complete Evidence root closed inventory drifted");
}
const completeEvidenceRoot = {
  root: {
    path: evidenceRoot,
    type: "DIRECTORY",
    mode: completeRootStat.mode & 0o777,
    owned_by_current_uid:
      uid === null || completeRootStat.uid === uid,
    symlink: false,
  },
  manifest: {
    identity: observedArtifacts.manifest,
    schema_version: manifest.schema_version,
    matrix_sha256: manifest.matrix_sha256,
    declared_entry_count: manifest.entry_count,
    entries_exact: true,
  },
  inventory: completeInventory,
  undeclared_files: 0,
  missing_files: 0,
  duplicate_manifest_paths: 0,
  reordered_manifest_entries: 0,
  status: "PASS",
};

const wrapperExit = JSON.parse(artifactBytes.wrapper_exit.toString("utf8"));
const evaluatorExit = JSON.parse(artifactBytes.evaluator_exit.toString("utf8"));
const evaluatorResult =
  JSON.parse(artifactBytes.evaluator_stdout.toString("utf8"));
if (
  wrapperExit.status !== "NON_PASS"
  || wrapperExit.exit_status !== 1
  || evaluatorExit.status !== "NON_PASS"
  || evaluatorExit.exit_status !== 1
  || evaluatorExit.signal !== null
  || evaluatorResult.status !== "NON_PASS"
  || evaluatorResult.reason_code !== "PROCESS_RECORD_INVALID"
) {
  fail("terminal verdict drifted");
}
process.stdout.write(JSON.stringify({
  schema_version: "p1-168-prior-attempt-disclosure/v2",
  status: "TERMINAL_NON_PASS",
  evidence_root: evidenceRoot,
  root_preserved: true,
  source_hash_stale: true,
  accepted_evidence: false,
  reused_as_accepted: false,
  artifacts: observedArtifacts,
  complete_evidence_root: completeEvidenceRoot,
  wrapper: {
    status: wrapperExit.status,
    exit_status: wrapperExit.exit_status,
  },
  independent_evaluator: {
    status: evaluatorResult.status,
    reason_code: evaluatorResult.reason_code,
    exit_status: evaluatorExit.exit_status,
    signal: evaluatorExit.signal,
  },
  aborted_precommit_stage: {
    status: "PRECOMMIT_ABORTED_QUALITY_INTERCEPT",
    exit_status: 130,
    root: {
      path: stageRoot,
      type: "DIRECTORY",
      mode: stageStat.mode & 0o777,
      owned_by_current_uid: uid === null || stageStat.uid === uid,
      symlink: false,
    },
    inventory: stageInventory,
    final_root_created: false,
    accepted_evidence: false,
    stage_reused: false,
  },
}));
NODE
}

P1_168_PRIOR_ATTEMPT_BEFORE="$(capture_p1_168_prior_attempt)"
readonly P1_168_PRIOR_ATTEMPT_BEFORE

umask 077
PRESERVE_EVIDENCE=false
OWNED_PARENT=""
OWNED_PARENT_DEV=""
OWNED_PARENT_INO=""

if [[ "$#" -eq 0 ]]; then
  OWNED_PARENT="$(mktemp -d /private/tmp/sourcelens-p1-165-verifier.XXXXXXXX)"
  chmod 700 "${OWNED_PARENT}"
  OWNED_PARENT_DEV="$(/usr/bin/stat -f '%d' "${OWNED_PARENT}")"
  OWNED_PARENT_INO="$(/usr/bin/stat -f '%i' "${OWNED_PARENT}")"
  EVIDENCE_ROOT="${OWNED_PARENT}/evidence"
elif [[ "$#" -eq 1 ]]; then
  EVIDENCE_ROOT="$1"
  PRESERVE_EVIDENCE=true
  if [[ "${EVIDENCE_ROOT}" != /* || -e "${EVIDENCE_ROOT}" || -L "${EVIDENCE_ROOT}" ]]; then
    printf '%s\n' \
      "{\"reason_code\":\"EVIDENCE_ROOT_NOT_ABSENT_ABSOLUTE\",\"status\":\"NON_PASS\"}" >&2
    exit 1
  fi
else
  printf '%s\n' 'usage: verify-p1-165-fail-closed-response-admission.sh [absolute-absent-evidence-root]' >&2
  exit 2
fi
readonly PRESERVE_EVIDENCE OWNED_PARENT OWNED_PARENT_DEV OWNED_PARENT_INO EVIDENCE_ROOT

"${NODE_BIN}" --input-type=module - "${EVIDENCE_ROOT}" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const [root] = process.argv.slice(2);
const fail = (reasonCode) => {
  process.stderr.write(`${JSON.stringify({ reason_code: reasonCode, status: "NON_PASS" })}\n`);
  process.exit(1);
};
if (
  typeof root !== "string"
  || !path.isAbsolute(root)
  || path.resolve(root) !== root
  || fs.existsSync(root)
) {
  fail("EVIDENCE_ROOT_NOT_ABSENT_ABSOLUTE");
}
const parent = path.dirname(root);
let parentStat;
try {
  parentStat = fs.lstatSync(parent, { bigint: true });
} catch {
  fail("EVIDENCE_PARENT_INVALID");
}
if (
  !parentStat.isDirectory()
  || parentStat.isSymbolicLink()
  || parentStat.uid !== BigInt(process.getuid())
  || fs.realpathSync(parent) !== parent
) {
  fail("EVIDENCE_PARENT_INVALID");
}
NODE

cleanup_owned_parent() {
  if [[ "${PRESERVE_EVIDENCE}" == "true" || -z "${OWNED_PARENT}" ]]; then
    return
  fi
  "${NODE_BIN}" --input-type=module - \
    "${OWNED_PARENT}" \
    "${OWNED_PARENT_DEV}" \
    "${OWNED_PARENT_INO}" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const [root, expectedDevText, expectedInoText] = process.argv.slice(2);
const fail = (reasonCode) => {
  process.stderr.write(`${JSON.stringify({ reason_code: reasonCode, status: "NON_PASS" })}\n`);
  process.exit(1);
};

if (!root.startsWith("/private/tmp/sourcelens-p1-165-verifier.")) {
  fail("P1_165_CLEANUP_SCOPE_INVALID");
}

let rootStat;
try {
  rootStat = fs.lstatSync(root, { bigint: true });
} catch (error) {
  if (error?.code === "ENOENT") process.exit(0);
  fail("P1_165_CLEANUP_ROOT_LSTAT_FAILED");
}

if (
  !rootStat.isDirectory()
  || rootStat.isSymbolicLink()
  || rootStat.uid !== BigInt(process.getuid())
  || rootStat.dev !== BigInt(expectedDevText)
  || rootStat.ino !== BigInt(expectedInoText)
  || fs.realpathSync(root) !== root
) {
  fail("P1_165_CLEANUP_ROOT_IDENTITY_MISMATCH");
}

const removeNoFollow = (target) => {
  const stat = fs.lstatSync(target, { bigint: true });
  if (stat.dev !== rootStat.dev || stat.uid !== rootStat.uid) {
    fail("P1_165_CLEANUP_CHILD_IDENTITY_MISMATCH");
  }
  if (stat.isSymbolicLink()) {
    fs.unlinkSync(target);
    return;
  }
  if (stat.isFile()) {
    if (stat.nlink !== 1n) fail("P1_165_CLEANUP_HARDLINK_REJECTED");
    fs.unlinkSync(target);
    return;
  }
  if (!stat.isDirectory()) fail("P1_165_CLEANUP_CHILD_TYPE_INVALID");
  for (const entry of fs.readdirSync(target)) {
    removeNoFollow(path.join(target, entry));
  }
  fs.rmdirSync(target);
};

removeNoFollow(root);
if (fs.existsSync(root)) fail("P1_165_CLEANUP_NOT_EXACT");
NODE
}

trap cleanup_owned_parent EXIT

set +e
PREFLIGHT_RESULT="$("${NODE_BIN}" "${PREFLIGHT}" "${EVIDENCE_ROOT}")"
PREFLIGHT_STATUS=$?
set -e
printf '%s\n' "${PREFLIGHT_RESULT}"
if [[ "${PREFLIGHT_STATUS}" -ne 0 ]]; then
  exit "${PREFLIGHT_STATUS}"
fi

printf '%s\n' "${PREFLIGHT_RESULT}" | "${NODE_BIN}" -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const { dirname } = require("node:path");
  const { isDeepStrictEqual } = require("node:util");
  const value = JSON.parse(input);
  const expectedRoot = process.argv[1];
  const rootDir = process.argv[2];
  const expectedPriorAttempt = JSON.parse(process.argv[3]);
  const effectKeys = ["network", "production", "provider", "public", "remote", "secret"];
  const zeroEffects =
    value.external_effects
    && JSON.stringify(Object.keys(value.external_effects).sort()) === JSON.stringify(effectKeys)
    && Object.values(value.external_effects).every((entry) => entry === false);
  const boundaries = value.output_token_boundaries;
  const regressionKeys = [
    "forged_observer_empty_row_precedence",
    "inventory_ordering",
    "non_regular_before_hardlink_precedence",
    "profile_verification_parent",
    "typed_2048_full_spine_stimulus",
  ];
  const regressions = value.historical_root_cause_regressions;
  const exactRegressions =
    regressions !== null
    && typeof regressions === "object"
    && !Array.isArray(regressions)
    && JSON.stringify(Object.keys(regressions).sort())
      === JSON.stringify(regressionKeys)
    && Object.values(regressions).every((status) => status === "PASS");
  const exactBoundaries =
    boundaries !== null
    && typeof boundaries === "object"
    && !Array.isArray(boundaries)
    && JSON.stringify(Object.keys(boundaries).sort()) === JSON.stringify(["2047", "2048", "2049"])
    && boundaries["2047"] === "ACCEPTED"
    && boundaries["2048"] === "ACCEPTED"
    && boundaries["2049"] === "REJECTED";
  const atomicReceipt = value.atomic_commit_receipt;
  const gateEnvelope = value.p1_168_gate_envelope;
  const sourceBundle = value.current_kernel_source_bundle;
  const exactGateEnvelope =
    gateEnvelope?.path === "raw/p1-168/task-gate-envelope.json"
    && Number.isSafeInteger(gateEnvelope.byte_length)
    && gateEnvelope.byte_length > 0
    && /^[0-9a-f]{64}$/.test(gateEnvelope.sha256);
  const exactSourceBundle =
    sourceBundle?.path === "raw/p1-168/current-kernel-source-bundle.json"
    && Number.isSafeInteger(sourceBundle.byte_length)
    && sourceBundle.byte_length > 0
    && /^[0-9a-f]{64}$/.test(sourceBundle.sha256)
    && sourceBundle.source_file_count === 9;
  const exactReproduction =
    JSON.stringify(value.reproduction?.executed_argv)
      === JSON.stringify([
        `${rootDir}/scripts/verify-p1-165-fail-closed-response-admission.sh`,
        expectedRoot,
      ])
    && JSON.stringify(value.reproduction?.independent_evaluator_argv)
      === JSON.stringify([
        process.execPath,
        `${rootDir}/evaluation-harness/evaluator/p1-165-fail-closed-response-admission/evaluate.mjs`,
        expectedRoot,
      ])
    && JSON.stringify(value.reproduction?.fresh_run_argv_template)
      === JSON.stringify([
        `${rootDir}/scripts/verify-p1-165-fail-closed-response-admission.sh`,
        "<ABSOLUTE_NORMALIZED_ABSENT_EVIDENCE_ROOT>",
      ])
    && value.reproduction?.fresh_root_requirement
      === "ABSOLUTE_NORMALIZED_ABSENT_NON_SYMLINK_CREATE_ONCE"
    && value.reproduction?.cwd === rootDir
    && value.reproduction?.runtime?.node_executable === process.execPath
    && value.reproduction?.runtime?.node_version === process.version
    && value.reproduction?.runtime?.platform === process.platform
    && value.reproduction?.runtime?.architecture === process.arch;
  const exactAtomicReceipt =
    atomicReceipt !== null
    && typeof atomicReceipt === "object"
    && !Array.isArray(atomicReceipt)
    && JSON.stringify(Object.keys(atomicReceipt).sort())
      === JSON.stringify(["byte_length", "path", "sha256"])
    && atomicReceipt.path
      === `${expectedRoot}.p1-165-atomic-commit-receipt.json`
    && Number.isSafeInteger(atomicReceipt.byte_length)
    && atomicReceipt.byte_length > 0
    && /^[0-9a-f]{64}$/.test(atomicReceipt.sha256);
  const exactIdentity = (identity, path, byteLength, sha256) =>
    identity !== null
    && typeof identity === "object"
    && !Array.isArray(identity)
    && JSON.stringify(Object.keys(identity).sort())
      === JSON.stringify(["byte_length", "path", "sha256"])
    && identity.path === path
    && identity.byte_length === byteLength
    && identity.sha256 === sha256;
  const historicalRoot =
    "/Users/lijunpeng/Developer/.sourcelens-audit/"
    + "p1-exact-p1-165-snapshot-recovery-strict-exit-20260730/"
    + "task-1-p1-168/preflight";
  const v2Root = `${historicalRoot}/complete-matrix-v2`;
  const makeRoot =
    `${dirname(historicalRoot)}/task-gate/worktree-make-verify-v1`;
  const lineage = value.prior_complete_matrix_v2_and_global_gate;
  const v2 = lineage?.complete_matrix_v2;
  const makeVerify = lineage?.worktree_make_verify_v1;
  const exactV2Lineage =
    lineage !== null
    && typeof lineage === "object"
    && !Array.isArray(lineage)
    && JSON.stringify(Object.keys(lineage).sort())
      === JSON.stringify([
        "complete_matrix_v2",
        "worktree_make_verify_v1",
      ])
    && v2?.schema_version
      === "p1-168-prior-complete-matrix-disclosure/v1"
    && v2.status
      === "PREFLIGHT_PASS_BUT_GLOBAL_HARNESS_GATE_NON_PASS"
    && v2.evidence_root === v2Root
    && v2.root_preserved === true
    && v2.accepted_evidence === false
    && v2.reused_as_accepted === false
    && exactIdentity(
      v2.artifacts?.manifest,
      `${v2Root}/RAW_EVIDENCE_MANIFEST.json`,
      807791,
      "330af09c3a3a3ac42f143061e050808191a06f7cb0c41e3992dfc1000f0a8239",
    )
    && exactIdentity(
      v2.artifacts?.atomic_commit_receipt,
      `${v2Root}.p1-165-atomic-commit-receipt.json`,
      18418,
      "1c7bbf6341c28e9cdf491ea21b006b57d40daec080d3ea311a1225274ea5745d",
    )
    && exactIdentity(
      v2.artifacts?.wrapper_stdout,
      `${historicalRoot}/COMPLETE_MATRIX_V2_STDOUT.log`,
      21125,
      "3e4df6fa93607aeed3685c779a6dd41a0a359cc180cea6dd9e526ab4aff762a5",
    )
    && exactIdentity(
      v2.artifacts?.wrapper_stderr,
      `${historicalRoot}/COMPLETE_MATRIX_V2_STDERR.log`,
      0,
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
    && exactIdentity(
      v2.artifacts?.wrapper_exit,
      `${historicalRoot}/COMPLETE_MATRIX_V2_EXIT.json`,
      84,
      "2810eace602c06ea4cf51746a7a407da9489ddc883a95cf6596f899cd05bd9d4",
    )
    && v2.complete_evidence_root?.inventory?.entry_count === 3830
    && v2.complete_evidence_root?.inventory?.total_bytes === 167175907
    && v2.complete_evidence_root?.inventory?.sha256
      === "41e2680bad8f5622678cc900321c7f767bfabad7a003e31f97f65836d89218ff"
    && v2.complete_evidence_root?.manifest?.matrix_sha256
      === "289ebf1022b1531e11c56d3bc8ae2ff2c2c874d841017703b64097a50d1dd393"
    && v2.complete_evidence_root?.manifest?.declared_entry_count === 3829
    && v2.complete_evidence_root?.manifest?.entries_exact === true
    && v2.complete_evidence_root?.undeclared_files === 0
    && v2.complete_evidence_root?.missing_files === 0
    && v2.complete_evidence_root?.status === "PASS"
    && v2.wrapper?.status === "PASS"
    && v2.wrapper?.exit_status === 0
    && v2.independent_evaluator?.result_embedded_in_wrapper_stdout === true
    && v2.independent_evaluator?.status === "PASS"
    && v2.independent_evaluator?.reason_code === "PASS"
    && makeVerify?.schema_version
      === "p1-168-task-worktree-make-verify/v1"
    && makeVerify.status === "NON_PASS"
    && makeVerify.exit_status === 2
    && makeVerify.normalized_root_cause
      === "P1168.WORKTREE_VERIFY.HARNESS_NETWORK_CAPABILITY_BOUNDARY"
    && makeVerify.accepted_evidence === false
    && makeVerify.reused_as_accepted === false
    && exactIdentity(
      makeVerify.artifacts?.receipt,
      `${makeRoot}/receipt.json`,
      620,
      "7735055e1758fbff34ea3d4e0c891928eaefd3a490749d49f55b4ae3d5af4a6e",
    )
    && exactIdentity(
      makeVerify.artifacts?.stdout,
      `${makeRoot}/stdout.log`,
      211,
      "273c5a28583bd7c34eca150da4f63cbbd4785bb632c61c4eaed47294bb34065c",
    )
    && exactIdentity(
      makeVerify.artifacts?.stderr,
      `${makeRoot}/stderr.log`,
      804,
      "b01b73f5f7f0a6ee2b7381d845154f0ce6ef8e3fddd9d18033fa8b36996d14f9",
    );
  const summaryChecks = {
    accepted_p1_101_replays: value.accepted_p1_101_replays === 36,
    accepted_p1_149_execution_spines:
      value.accepted_p1_149_execution_spines === 36,
    admitted_matrix_cases: value.admitted_matrix_cases === 14,
    atomic_commit_receipt: exactAtomicReceipt,
    b0_cells: value.b0_cells === 12,
    b1_cells: value.b1_cells === 12,
    b2_cells: value.b2_cells === 12,
    external_effects: zeroEffects,
    false_accepts: value.false_accepts === 0,
    gate_envelope: exactGateEnvelope,
    historical_regressions: exactRegressions,
    integration_negative_cases: value.integration_negative_cases === 14,
    live_loopback_calibration:
      value.live_loopback_calibration === "DEFERRED_TO_P1_169",
    live_loopback_calibration_connections:
      value.live_loopback_calibration_connections === 0,
    matrix_cases: value.matrix_cases === 99,
    negative_cases:
      Number.isInteger(value.negative_cases) && value.negative_cases === 85,
    ordinary_failure_denominator_cases:
      value.ordinary_failure_denominator_cases === 6,
    output_token_boundaries: exactBoundaries,
    persistence_before_admission: value.persistence_before_admission === 0,
    prior_complete_matrix_v2_and_global_gate: exactV2Lineage,
    prior_interrupted_attempt: isDeepStrictEqual(
      value.prior_interrupted_attempt,
      expectedPriorAttempt,
    ),
    provider_requests: value.provider_requests === 0,
    real_b2_repository_analysis_scan_children:
      value.real_b2_repository_analysis_scan_children === 12,
    reference_leaks: value.reference_leaks === 0,
    reproduction: exactReproduction,
    safe_failure_receipts: value.safe_failure_receipts === 100,
    secret_reads: value.secret_reads === 0,
    source_bundle: exactSourceBundle,
    status: value.status === "PASS",
    synthetic_cells: value.synthetic_cells === 36,
    synthetic_observer_fixture_source:
      value.observer_fixture_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE",
    synthetic_observer_fixtures: value.synthetic_observer_fixtures === 37,
    task_id:
      value.task_id
        === "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL",
    unsafe_failure_receipts: value.unsafe_failure_receipts === 0,
    expected_non_pass_cases: value.expected_non_pass_cases === 100,
  };
  const failedChecks = Object.entries(summaryChecks)
    .filter(([, passed]) => passed !== true)
    .map(([name]) => name);
  if (failedChecks.length !== 0) {
    throw new Error(
      `P1-165 preflight summary NON_PASS checks=${JSON.stringify(failedChecks)}`
      + ` summary=${JSON.stringify(value)}`,
    );
  }
});
' "${EVIDENCE_ROOT}" "${ROOT_DIR}" "${P1_168_PRIOR_ATTEMPT_BEFORE}"

set +e
EVALUATOR_RESULT="$("${NODE_BIN}" "${EVALUATOR}" "${EVIDENCE_ROOT}")"
EVALUATOR_STATUS=$?
set -e
printf '%s\n' "${EVALUATOR_RESULT}"
if [[ "${EVALUATOR_STATUS}" -ne 0 ]]; then
  exit "${EVALUATOR_STATUS}"
fi

printf '%s\n' "${EVALUATOR_RESULT}" | "${NODE_BIN}" -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const { isDeepStrictEqual } = require("node:util");
  const value = JSON.parse(input);
  const expectedRoot = process.argv[1];
  const rootDir = process.argv[2];
  const expectedPriorAttempt = JSON.parse(process.argv[3]);
  const preflightSummary = JSON.parse(process.argv[4]);
  const counts = value.counts ?? {};
  const p1168Gate = value.p1_168_task_gate_receipt;
  const exactP1168Gate =
    p1168Gate?.schema_version === "p1-168-independent-task-gate-receipt/v1"
    && p1168Gate.task_id
      === "AIOS-P1-168_EXACT_RESPONSE_ADMISSION_MATRIX_RECOVERY_AND_GATE"
    && p1168Gate.status === "PASS"
    && p1168Gate.gate_envelope_identity?.path
      === "raw/p1-168/task-gate-envelope.json"
    && p1168Gate.source_bundle_identity?.path
      === "raw/p1-168/current-kernel-source-bundle.json"
    && p1168Gate.source_file_count === 9
    && isDeepStrictEqual(
      p1168Gate.prior_interrupted_attempt,
      expectedPriorAttempt,
    )
    && isDeepStrictEqual(
      p1168Gate.prior_complete_matrix_v2_and_global_gate,
      preflightSummary.prior_complete_matrix_v2_and_global_gate,
    )
    && p1168Gate.task_contract?.byte_length === 14548
    && p1168Gate.task_contract?.sha256
      === "f959e5f58cace3e795d481454ad9863d0a9195e336bd0eda7d79baf458f10c87"
    && p1168Gate.task_authority?.byte_length === 2516
    && p1168Gate.task_authority?.sha256
      === "48c57f94e26a365339f4ed6b3285086f7b2dee61ed9d923c664551ae5d625292"
    && p1168Gate.restore_receipt?.byte_length === 3400
    && p1168Gate.restore_receipt?.sha256
      === "a2350df713fd3ec0719cecd3bce14539bebce6583205bea757e99969049b1984"
    && JSON.stringify(p1168Gate.reproduction?.executed_argv)
      === JSON.stringify([
        `${rootDir}/scripts/verify-p1-165-fail-closed-response-admission.sh`,
        expectedRoot,
      ])
    && JSON.stringify(p1168Gate.reproduction?.independent_evaluator_argv)
      === JSON.stringify([
        process.execPath,
        `${rootDir}/evaluation-harness/evaluator/p1-165-fail-closed-response-admission/evaluate.mjs`,
        expectedRoot,
      ])
    && JSON.stringify(p1168Gate.reproduction?.fresh_run_argv_template)
      === JSON.stringify([
        `${rootDir}/scripts/verify-p1-165-fail-closed-response-admission.sh`,
        "<ABSOLUTE_NORMALIZED_ABSENT_EVIDENCE_ROOT>",
      ])
    && p1168Gate.reproduction?.fresh_root_requirement
      === "ABSOLUTE_NORMALIZED_ABSENT_NON_SYMLINK_CREATE_ONCE"
    && p1168Gate.reproduction?.cwd === rootDir
    && p1168Gate.reproduction?.runtime?.node_executable === process.execPath
    && p1168Gate.reproduction?.runtime?.node_version === process.version
    && p1168Gate.inner_result?.schema_version
      === "p1-165-independent-evaluation/v1"
    && p1168Gate.inner_result?.task_id
      === "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL"
    && p1168Gate.inner_result?.matrix_cases === 99
    && p1168Gate.inner_result?.status === "PASS"
    && p1168Gate.inner_result?.manifest_sha256 === value.manifest?.sha256
    && p1168Gate.inner_result?.manifest_entries
      === value.manifest?.entry_count;
  const regressionKeys = [
    "forged_observer_empty_row_precedence",
    "inventory_ordering",
    "non_regular_before_hardlink_precedence",
    "profile_verification_parent",
    "typed_2048_full_spine_stimulus",
  ];
  const regressions = value.historical_root_cause_regressions;
  const exactRegressions =
    regressions !== null
    && typeof regressions === "object"
    && !Array.isArray(regressions)
    && JSON.stringify(Object.keys(regressions).sort())
      === JSON.stringify(regressionKeys)
    && Object.values(regressions).every((status) => status === "PASS");
  const effectKeys = ["network", "production", "provider", "public", "remote", "secret"];
  const zeroEffects =
    value.external_effects
    && JSON.stringify(Object.keys(value.external_effects).sort()) === JSON.stringify(effectKeys)
    && Object.values(value.external_effects).every((entry) => entry === false);
  const acceptedAdapterProcess = value.accepted_adapter_process;
  const acceptedAdapterProcessKeys = [
    "accepted_authority_bundle_exact",
    "accepted_p1_129_source_preserved_read_only",
    "all_current_b2_fixture_roots_absent",
    "b2_independent_scan_reexecutions",
    "calibration_roots_absent",
    "cooperative_local_accepted_evidence_path_residual",
    "distinct_b2_child_pids",
    "external_write_denial",
    "historical_reviewed_binary_exact_bytes_claim",
    "home_read_denial",
    "home_write_denial",
    "hostile_global_read_isolation_claim",
    "hostile_process_isolation_claim",
    "live_network_calibration",
    "live_network_connections_created",
    "live_network_probe_executed",
    "network_denial_fixture_only",
    "owned_write_allowance",
    "sandbox_calibration_exact",
    "status",
    "trusted_accepted_source_required",
  ];
  const exactAcceptedAdapterProcess =
    acceptedAdapterProcess !== null
    && typeof acceptedAdapterProcess === "object"
    && !Array.isArray(acceptedAdapterProcess)
    && JSON.stringify(Object.keys(acceptedAdapterProcess).sort())
      === JSON.stringify(acceptedAdapterProcessKeys);
  if (
    value.schema_version !== "p1-165-independent-evaluation/v1"
    || value.task_id !== "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL"
    || value.status !== "PASS"
    || value.reason_code !== "PASS"
    || !exactP1168Gate
    || value.matrix?.case_count !== 99
    || !Number.isSafeInteger(value.manifest?.entry_count)
    || value.manifest.entry_count < 1
    || counts.cases_observed !== value.matrix.case_count
    || counts.cases_passed !== value.matrix.case_count
    || counts.false_accepts !== 0
    || counts.unsafe_persistence !== 0
    || counts.synthetic_cells !== 36
    || counts.b0_cells !== 12
    || counts.b1_cells !== 12
    || counts.b2_cells !== 12
    || counts.p1_149_spines !== 36
    || counts.p1_101_replays !== 36
    || value.p1_101_rollbacks !== 36
    || counts.b2_scan_children !== 12
    || !exactAcceptedAdapterProcess
    || acceptedAdapterProcess.status !== "PASS"
    || acceptedAdapterProcess.accepted_authority_bundle_exact !== true
    || acceptedAdapterProcess.sandbox_calibration_exact !== true
    || acceptedAdapterProcess.network_denial_fixture_only !== true
    || acceptedAdapterProcess.live_network_probe_executed !== false
    || acceptedAdapterProcess.live_network_connections_created !== 0
    || acceptedAdapterProcess.live_network_calibration
      !== "DEFERRED_TO_P1_169"
    || acceptedAdapterProcess.home_read_denial !== true
    || acceptedAdapterProcess.home_write_denial !== true
    || acceptedAdapterProcess.external_write_denial !== true
    || acceptedAdapterProcess.owned_write_allowance !== true
    || acceptedAdapterProcess.calibration_roots_absent !== true
    || acceptedAdapterProcess
      .accepted_p1_129_source_preserved_read_only !== true
    || acceptedAdapterProcess.b2_independent_scan_reexecutions !== 12
    || acceptedAdapterProcess.distinct_b2_child_pids !== 12
    || acceptedAdapterProcess
      .all_current_b2_fixture_roots_absent !== true
    || acceptedAdapterProcess
      .historical_reviewed_binary_exact_bytes_claim !== false
    || acceptedAdapterProcess
      .cooperative_local_accepted_evidence_path_residual !== true
    || acceptedAdapterProcess
      .hostile_global_read_isolation_claim !== false
    || acceptedAdapterProcess
      .hostile_process_isolation_claim !== false
    || acceptedAdapterProcess.trusted_accepted_source_required !== true
    || value.distinct_adapter_roots !== 36
    || value.distinct_spine_run_ids !== 36
    || value.closed_spine_artifact_sets !== 36
    || value.production_admission_receipts !== 36
    || value.production_cell_closures !== 36
    || value.matrix_case_production_admissions !== 14
    || value.matrix_case_safe_failure_receipts !== 85
    || !exactRegressions
    || value.independent_reexecution_spines !== 36
    || value.independent_case_reexecutions !== 99
    || counts.ordinary_failed_denominator_cases !== 6
    || counts.integration_negative_cases !== 14
    || counts.exact_output_token_boundary_spines !== 1
    || counts.safe_failure_receipts_total !== 100
    || counts.provider_requests !== 0
    || counts.secret_reads !== 0
    || counts.network_effects !== 0
    || value.usage?.unknown_preserved !== true
    || value.usage?.boundaries?.["2047"] !== "ACCEPTED"
    || value.usage?.boundaries?.["2048"] !== "ACCEPTED_FULL_SPINE"
    || value.usage?.boundaries?.["2049"] !== "REJECTED_BEFORE_PERSISTENCE"
    || value.usage?.exact_boundary_spines !== 1
    || value.ordinary_failure_control?.status !== "PASS"
    || value.ordinary_failure_control?.failed_denominator_cases !== 6
    || value.ordinary_failure_control?.early_failures !== 4
    || value.ordinary_failure_control?.late_failures !== 2
    || value.ordinary_failure_control?.continued_to_accepted_cell !== true
    || value.ordinary_failure_control?.worker_success_fields_trusted !== false
    || value.output_token_control?.status !== "PASS"
    || value.output_token_control?.boundaries?.["2047"] !== "ACCEPTED"
    || value.output_token_control?.boundaries?.["2048"] !== "ACCEPTED_FULL_SPINE"
    || value.output_token_control?.boundaries?.["2049"]
      !== "REJECTED_BEFORE_PERSISTENCE"
    || value.output_token_control?.overflow_high_level_replay?.status !== "PASS"
    || value.output_token_control?.overflow_high_level_replay?.reason_code
      !== "PROVIDER_OUTPUT_USAGE_EXCEEDED"
    || value.output_token_control?.overflow_high_level_replay
      ?.admitted_response_persisted !== false
    || value.output_token_control?.overflow_high_level_replay
      ?.admission_receipt_persisted !== false
    || value.integration_negative_control?.status !== "PASS"
    || value.integration_negative_control?.cases !== 14
    || value.integration_negative_control?.final_responses_persisted !== 0
    || value.integration_negative_control?.attempt_roots_remaining !== 0
    || value.integration_negative_control?.false_accepts !== 0
    || value.atomic_commit?.status !== "PASS"
    || value.atomic_commit?.atomic_rename !== true
    || value.atomic_commit?.expected_non_pass_cases !== 100
    || typeof value.atomic_commit?.staged_root_path !== "string"
    || value.atomic_commit.staged_root_path.length === 0
    || value.atomic_commit?.staged_root_absent !== true
    || value.atomic_commit?.stage_path_absent !== true
    || value.atomic_commit?.commit_lock_absent !== true
    || value.accepted_input_provenance?.status !== "PASS"
    || value.accepted_input_provenance?.accepted_inputs !== 4
    || value.accepted_input_provenance?.git_ancestry_checks !== 4
    || value.accepted_input_provenance?.accepted_verifier_receipts !== 4
    || value.accepted_input_provenance?.raw_truth_command_reexecuted !== true
    || value.secret_scan?.status !== "PASS"
    || value.secret_scan?.leaks !== 0
    || value.secret_scan?.whole_stage_composition_scanned !== true
    || value.concurrency?.status !== "PASS"
    || value.concurrency?.children !== 4
    || value.concurrency?.winners !== 1
    || value.concurrency?.create_once_rejections !== 3
    || value.concurrency?.slots_expected !== 4
    || value.concurrency?.slots_observed !== 4
    || value.concurrency?.duplicate_slots !== 0
    || value.concurrency?.missing_slots !== 0
    || value.concurrency?.fixture_cleaned !== true
    || value.concurrency?.matrix_component_cases_replayed !== 7
    || value.liveness?.status !== "PASS"
    || value.liveness?.children !== 5
    || value.liveness?.heartbeats !== 6
    || value.liveness?.normal_progress !== "PASS"
    || value.liveness?.missing_receipt !== "DETECTED"
    || value.liveness?.matrix_component_cases_replayed !== 5
    || value.liveness?.worker_stall !== "DETECTED"
    || value.liveness?.observer_stall !== "DETECTED"
    || value.liveness?.evidence_writer_stall !== "DETECTED"
    || value.raw_only !== true
    || value.worker_summary_trusted !== false
    || !zeroEffects
    || !Array.isArray(value.failures)
    || value.failures.length !== 0
  ) {
    throw new Error(`P1-165 independent evaluation NON_PASS: ${JSON.stringify(value)}`);
  }
});
' \
  "${EVIDENCE_ROOT}" \
  "${ROOT_DIR}" \
  "${P1_168_PRIOR_ATTEMPT_BEFORE}" \
  "${PREFLIGHT_RESULT}"

P1_168_PRIOR_ATTEMPT_AFTER="$(capture_p1_168_prior_attempt)"
if [[ "${P1_168_PRIOR_ATTEMPT_AFTER}" != "${P1_168_PRIOR_ATTEMPT_BEFORE}" ]]; then
  printf '%s\n' \
    '{"reason_code":"P1_168_PRIOR_ATTEMPT_CHANGED_DURING_RUN","status":"NON_PASS"}' >&2
  exit 1
fi

printf '%s\n' 'P1_165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL: PASS'
printf '%s\n' 'P1_168_EXACT_RESPONSE_ADMISSION_MATRIX_RECOVERY_AND_GATE: PASS'

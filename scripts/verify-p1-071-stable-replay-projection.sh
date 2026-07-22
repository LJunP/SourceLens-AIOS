#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NODE_BIN="/usr/local/bin/node"

if [[ ! -x "${NODE_BIN}" ]]; then
  printf '%s\n' '{"reason":"NODE_EXECUTABLE_UNAVAILABLE","status":"NON_PASS"}' >&2
  exit 1
fi

umask 077
VERIFIER_ROOT="$(mktemp -d /private/tmp/sourcelens-p1-071-verifier.XXXXXXXX)"
chmod 700 "${VERIFIER_ROOT}"
readonly VERIFIER_ROOT
readonly VERIFIER_DEV="$(/usr/bin/stat -f '%d' "${VERIFIER_ROOT}")"
readonly VERIFIER_INO="$(/usr/bin/stat -f '%i' "${VERIFIER_ROOT}")"
readonly DRIVER="${VERIFIER_ROOT}/driver.mjs"

cleanup_owned_root() {
  "${NODE_BIN}" --input-type=module - "${VERIFIER_ROOT}" "${VERIFIER_DEV}" "${VERIFIER_INO}" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const [root, expectedDevText, expectedInoText] = process.argv.slice(2);
const fail = (reason) => {
  process.stderr.write(`${JSON.stringify({ reason, status: "NON_PASS" })}\n`);
  process.exit(1);
};
if (!root.startsWith("/private/tmp/sourcelens-p1-071-verifier.")) fail("CLEANUP_SCOPE_INVALID");
let stat;
try { stat = fs.lstatSync(root, { bigint: true }); } catch (error) {
  if (error?.code === "ENOENT") process.exit(0);
  fail("CLEANUP_ROOT_LSTAT_FAILED");
}
if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== BigInt(process.getuid()) ||
    stat.dev !== BigInt(expectedDevText) || stat.ino !== BigInt(expectedInoText) ||
    fs.realpathSync(root) !== root) fail("CLEANUP_ROOT_IDENTITY_MISMATCH");

const removeNoFollow = (target) => {
  const targetStat = fs.lstatSync(target, { bigint: true });
  if (targetStat.dev !== stat.dev || targetStat.uid !== stat.uid) fail("CLEANUP_CHILD_IDENTITY_MISMATCH");
  if (targetStat.isSymbolicLink() || targetStat.isFile()) {
    fs.unlinkSync(target);
    return;
  }
  if (!targetStat.isDirectory()) fail("CLEANUP_CHILD_IDENTITY_MISMATCH");
  for (const entry of fs.readdirSync(target)) removeNoFollow(path.join(target, entry));
  fs.rmdirSync(target);
};
removeNoFollow(root);
if (fs.existsSync(root)) fail("CLEANUP_NOT_EXACT");
NODE
}

trap 'cleanup_owned_root' EXIT

set -o noclobber
cat >"${DRIVER}" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const [repo, verifierRoot] = process.argv.slice(2);
const node = "/usr/local/bin/node";
const harnessRoot = path.join(repo, "evaluation-harness");
const runner = path.join(harnessRoot, "harness/blind-admission-v1/run.mjs");
const recorder = path.join(harnessRoot, "recording/blind-admission-v1/recorder.mjs");
const validator = path.join(harnessRoot, "validators/blind-admission-v1/validator.mjs");
const oracle = path.join(harnessRoot, "evaluator/blind-admission-v1/public-conformance-oracle.mjs");
const task = path.join(harnessRoot, "fixtures/blind-admission-v1/visible-task-card.json");
const source = path.join(harnessRoot, "fixtures/blind-admission-v1/visible-source.json");
const expected = path.join(harnessRoot, "fixtures/blind-admission-v1/visible-expected.json");
const runtime = path.join(harnessRoot, "fixtures/blind-admission-v1/runtime-profile.json");
const taskContract = path.join(repo, "docs/aios/tasks/P1-071_STABLE_REPLAY_PROJECTION_AND_EXACT_HARNESS_ADMISSION_VERTICAL_SLICE.yaml");
const projectionContract = path.join(harnessRoot, "contracts/stable-replay-projection-v2/stable-replay-projection-v2.contract.json");
const projectionReadme = path.join(harnessRoot, "contracts/stable-replay-projection-v2/README.md");
const catalogPath = path.join(harnessRoot, "fixtures/stable-replay-projection-v2/test-cases.json");
const syntheticPair = path.join(harnessRoot, "fixtures/stable-replay-projection-v2/synthetic-pair.json");
const projector = path.join(harnessRoot, "replay/stable-replay-projection-v2/project.mjs");
const env = { LANG: "C", LC_ALL: "C", PATH: "/usr/bin:/bin:/usr/sbin:/sbin", TZ: "UTC" };

const fail = (reason, detail = undefined) => {
  const value = detail === undefined ? { reason, status: "NON_PASS" } : { detail, reason, status: "NON_PASS" };
  process.stderr.write(`${JSON.stringify(value)}\n`);
  process.exit(1);
};
const sha = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const gitBlobSha1 = (bytes) => crypto.createHash("sha1").update(Buffer.concat([
  Buffer.from(`blob ${bytes.length}\0`, "utf8"), bytes
])).digest("hex");
const normalize = (value) => Array.isArray(value)
  ? value.map(normalize)
  : value && typeof value === "object"
    ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, normalize(value[key])]))
    : value;
const shaJson = (value) => sha(Buffer.from(JSON.stringify(normalize(value)), "utf8"));
const identity = (file) => {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) fail("INPUT_TYPE_INVALID", file);
  const bytes = fs.readFileSync(file);
  return { byte_length: bytes.length, sha256: sha(bytes) };
};
const exactIdentity = (left, right) => left.sha256 === right.sha256 && left.byte_length === right.byte_length;
const mkdirOwned = (target) => {
  fs.mkdirSync(target, { mode: 0o700 });
  const stat = fs.lstatSync(target);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o700) {
    fail("OWNED_DIRECTORY_INVALID", target);
  }
};
const writeOnce = (file, bytes, mode = 0o400) => fs.writeFileSync(file, bytes, { flag: "wx", mode });

for (const file of [runner, recorder, validator, oracle, task, source, expected, runtime, taskContract, projectionContract, projectionReadme, catalogPath, syntheticPair]) {
  if (!fs.existsSync(file)) fail("REQUIRED_PUBLIC_INPUT_MISSING", file);
}
if (!fs.existsSync(projector)) fail("PROJECTOR_MISSING", projector);

const rootStat = fs.lstatSync(verifierRoot);
if (!rootStat.isDirectory() || rootStat.isSymbolicLink() || rootStat.uid !== process.getuid() ||
    (rootStat.mode & 0o777) !== 0o700 || fs.realpathSync(verifierRoot) !== verifierRoot) fail("VERIFIER_ROOT_INVALID");

let catalog;
try { catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8")); } catch { fail("CATALOG_PARSE_NON_PASS"); }
const positiveIds = catalog.positive_cases?.map(({ id }) => id) ?? [];
const negativeIds = catalog.negative_cases?.map(({ id }) => id) ?? [];
if (catalog.status !== "FROZEN_CLOSED" || catalog.counts?.positive !== 12 || catalog.counts?.negative !== 31 ||
    positiveIds.length !== 12 || negativeIds.length !== 31 || new Set([...positiveIds, ...negativeIds]).size !== 43) {
  fail("CATALOG_IDENTITY_NON_PASS");
}

const ids = {
  catalog: identity(catalogPath),
  projectionContract: identity(projectionContract),
  projectionReadme: identity(projectionReadme),
  recorder: identity(recorder),
  runner: identity(runner),
  runtime: identity(runtime),
  source: identity(source),
  syntheticPair: identity(syntheticPair),
  task: identity(task),
  taskContract: identity(taskContract),
  validator: identity(validator)
};

const exactQualityInputs = new Map([
  [projectionReadme, { byte_length: 1134, sha256: "bcf730a395ef4e0207c89eb8181917aead2031b3914f646fbd86bca748c73452" }],
  [projectionContract, { byte_length: 8366, sha256: "49064285a28d09433e4a16412e4dd7198c0dbddea985875633a6ad1cf4b270c8" }],
  [catalogPath, { byte_length: 8335, sha256: "db458da01142f60d50037fc0946bd225e3580a8cea27b69e23e9cd2d5d2f3361" }],
  [syntheticPair, { byte_length: 4881, sha256: "6fe4e523e0d6f6bad1883b51156eb40f3f085abe04639f520462d0601e87b017" }],
  [taskContract, { byte_length: 15128, sha256: "c02505bc0bac2a187f0c96290b33e562f6e06e15b2c22f4e747b42cf9d4d29c2" }]
]);
for (const [file, expectedIdentity] of exactQualityInputs) {
  if (!exactIdentity(identity(file), expectedIdentity)) fail("INPUT_IDENTITY_MISMATCH", file);
}

const exactP1069Blobs = new Map([
  ["evaluation-harness/contracts/blind-admission-v1/admission-envelope.schema.json", ["7275c8e8164956950b7f70d1ab53a677ac95b8bf", 0o644]],
  ["evaluation-harness/contracts/blind-admission-v1/evidence.schema.json", ["e4ddb7fea0727f2908b9d411cf2921ca2d70f79b", 0o644]],
  ["evaluation-harness/evaluator/blind-admission-v1/public-conformance-oracle.mjs", ["55b044882ff009bbb2d1be8835a7b9d04723cae8", 0o644]],
  ["evaluation-harness/fixtures/blind-admission-v1/negative-cases.json", ["7550a29fe9e2d333a9f355d62e469191014528d8", 0o644]],
  ["evaluation-harness/fixtures/blind-admission-v1/runtime-profile.json", ["7cda06d2e72fdda2563768389a508c343da68d80", 0o644]],
  ["evaluation-harness/fixtures/blind-admission-v1/visible-expected.json", ["9ba9455b332c75dcdb88eeae88eb14f09951a759", 0o644]],
  ["evaluation-harness/fixtures/blind-admission-v1/visible-source.json", ["684fba8ff7cb09b5b7091c22a361a8a0032014d7", 0o644]],
  ["evaluation-harness/fixtures/blind-admission-v1/visible-task-card.json", ["bdedcb3250cc99ab64d67ea94f2eb3d02c813c99", 0o644]],
  ["evaluation-harness/harness/blind-admission-v1/run.mjs", ["f7b5fd9f37c4d9f4823afcc8d24a2e8e1791ff46", 0o644]],
  ["evaluation-harness/recording/blind-admission-v1/recorder.mjs", ["40e79fa615b79d5064d2bdd577d51aab67dc5b63", 0o644]],
  ["evaluation-harness/validators/blind-admission-v1/validator.mjs", ["c3bfab157ab346a7b801f93765d435ec7e1d0eb3", 0o644]],
  ["scripts/verify-p1-069-blind-admission-harness.sh", ["e312e2e4dfde004d0ef88352267a02fe93028620", 0o755]]
]);
for (const [relative, [expectedBlob, expectedMode]] of exactP1069Blobs) {
  const file = path.join(repo, relative);
  const stat = fs.lstatSync(file);
  const bytes = fs.readFileSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || (stat.mode & 0o777) !== expectedMode || gitBlobSha1(bytes) !== expectedBlob) {
    fail("INPUT_IDENTITY_MISMATCH", relative);
  }
}

const buildArgs = (ownedRoot) => {
  const values = {
    "task-card": task,
    "task-card-sha256": ids.task.sha256,
    "task-card-byte-length": String(ids.task.byte_length),
    source,
    "source-sha256": ids.source.sha256,
    "source-byte-length": String(ids.source.byte_length),
    "runtime-profile": runtime,
    "runtime-profile-sha256": ids.runtime.sha256,
    "runtime-profile-byte-length": String(ids.runtime.byte_length),
    "owned-root": ownedRoot,
    "source-root": path.join(ownedRoot, "source"),
    "evidence-root": path.join(ownedRoot, "evidence"),
    "canonical-root": repo,
    "case-id": "canonical-public-regression",
    "contract-sha256": ids.taskContract.sha256,
    "contract-byte-length": String(ids.taskContract.byte_length),
    "authority-sha256": "11".repeat(32),
    "authority-byte-length": "1",
    "quality-freeze-sha256": ids.projectionContract.sha256,
    "quality-freeze-byte-length": String(ids.projectionContract.byte_length),
    "commitment-sha256": ids.catalog.sha256,
    "commitment-byte-length": String(ids.catalog.byte_length),
    "candidate-commit": "44".repeat(20),
    "candidate-tree": "55".repeat(20),
    "candidate-module-sha256": ids.runner.sha256,
    "candidate-module-byte-length": String(ids.runner.byte_length),
    "recorder-module-sha256": ids.recorder.sha256,
    "recorder-module-byte-length": String(ids.recorder.byte_length),
    "validator-module-sha256": ids.validator.sha256,
    "validator-module-byte-length": String(ids.validator.byte_length),
    "logical-cwd": repo,
    "environment-sha256": shaJson(env),
    "timeout-ms": "5000"
  };
  const order = [
    "task-card", "task-card-sha256", "task-card-byte-length", "source", "source-sha256", "source-byte-length",
    "runtime-profile", "runtime-profile-sha256", "runtime-profile-byte-length", "owned-root", "source-root", "evidence-root",
    "canonical-root", "case-id", "contract-sha256", "contract-byte-length", "authority-sha256", "authority-byte-length",
    "quality-freeze-sha256", "quality-freeze-byte-length", "commitment-sha256", "commitment-byte-length", "candidate-commit", "candidate-tree",
    "candidate-module-sha256", "candidate-module-byte-length", "recorder-module-sha256", "recorder-module-byte-length",
    "validator-module-sha256", "validator-module-byte-length", "logical-cwd", "environment-sha256", "timeout-ms"
  ];
  return order.flatMap((key) => [`--${key}`, values[key]]);
};

const writeObservation = (file, evidencePath, args, run) => {
  const evidenceId = identity(evidencePath);
  const taskJson = JSON.parse(fs.readFileSync(task, "utf8"));
  const runtimeJson = JSON.parse(fs.readFileSync(runtime, "utf8"));
  const observation = {
    schema_version: "blind-admission-quality-observation/v1",
    candidate_evidence: evidenceId,
    identities: {
      task_card_sha256: ids.task.sha256,
      source_sha256: ids.source.sha256,
      runtime_profile_sha256: ids.runtime.sha256,
      executing_module_sha256: ids.runner.sha256
    },
    task_id: taskJson.task_id,
    process: {
      actual_arch: process.arch,
      platform: process.platform,
      executable_path: node,
      executable_realpath: fs.realpathSync(node),
      executable_sha256: identity(node).sha256,
      executable_version: process.version,
      exit_code: run.status,
      stdout_sha256: sha(run.stdout),
      stderr_sha256: sha(run.stderr)
    },
    command: {
      ordered_argv_sha256: shaJson([node, runner, ...args]),
      logical_cwd: repo,
      environment_sha256: shaJson(env),
      timeout_ms: 5000
    },
    rollback: {
      source_root_initial_state: "ABSENT",
      source_root_final_state: "ABSENT",
      path_set_before: [], path_set_after: [],
      clean_state_before: true, clean_state_after: true, exact: true
    },
    external_effects: { network: false, provider: false, secret: false, remote: false, production: false, public: false }
  };
  writeOnce(file, Buffer.from(`${JSON.stringify(observation, null, 2)}\n`, "utf8"));
};

const freshPublicRun = (arm) => {
  const runRoot = path.join(verifierRoot, `fresh-${arm}`);
  const ownedRoot = path.join(runRoot, "candidate-owned");
  mkdirOwned(runRoot);
  mkdirOwned(ownedRoot);
  const args = buildArgs(ownedRoot);
  const run = spawnSync(node, [runner, ...args], { cwd: repo, env, encoding: null, timeout: 6000, maxBuffer: 65536, shell: false });
  if (run.error || run.status !== 0 || run.signal !== null || run.stderr.length !== 0) {
    fail("PUBLIC_HARNESS_NON_PASS", { arm, status: run.status, stderr: run.stderr?.toString("utf8") });
  }
  const evidencePath = path.join(ownedRoot, "evidence/evidence.json");
  const stdoutPath = path.join(runRoot, "candidate.stdout");
  const observationPath = path.join(runRoot, "public-observation.json");
  if (!fs.existsSync(evidencePath) || fs.existsSync(path.join(ownedRoot, "source"))) fail("PUBLIC_RUN_ROLLBACK_NON_PASS", arm);
  writeOnce(stdoutPath, run.stdout);
  writeObservation(observationPath, evidencePath, args, run);
  const oracleRun = spawnSync(node, [oracle, "--evidence", evidencePath, "--expected", expected, "--observation", observationPath,
    "--task-card", task, "--source", source, "--runtime-profile", runtime, "--candidate-module", runner],
    { cwd: repo, env, encoding: "utf8", timeout: 5000, maxBuffer: 65536, shell: false });
  let oracleJson;
  try { oracleJson = JSON.parse(oracleRun.stdout); } catch { oracleJson = null; }
  if (oracleRun.error || oracleRun.status !== 0 || oracleRun.stderr.length !== 0 || oracleJson?.verdict !== "PASS") {
    fail("PUBLIC_ORACLE_NON_PASS", { arm, status: oracleRun.status, stderr: oracleRun.stderr });
  }
  return { evidencePath, evidenceId: identity(evidencePath), stdoutPath, stdoutId: identity(stdoutPath), runRoot };
};

for (const file of [runner, recorder, validator, oracle, projector]) {
  const syntax = spawnSync(node, ["--check", file], { cwd: repo, env, encoding: "utf8", shell: false });
  if (syntax.status !== 0 || syntax.stderr.length !== 0) fail("NODE_SYNTAX_NON_PASS", file);
}

const runA = freshPublicRun("a");
const runB = freshPublicRun("b");
if (runA.evidencePath === runB.evidencePath || fs.realpathSync(runA.evidencePath) === fs.realpathSync(runB.evidencePath)) {
  fail("PUBLIC_RUNS_NOT_PHYSICALLY_DISTINCT");
}

const deepClone = (value) => JSON.parse(JSON.stringify(value));
const jsonBytes = (value) => Buffer.from(`${JSON.stringify(value)}\n`, "utf8");
const stableBytes = (value) => Buffer.from(`${JSON.stringify(normalize(value))}\n`, "utf8");
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const exactFalseEffects = (value) => {
  const keys = ["network", "provider", "secret", "remote", "production", "public"];
  return Object.keys(value ?? {}).length === keys.length && keys.every((key) => value[key] === false);
};
const pointerTypeMaps = (value) => {
  const full = [];
  const scalar = [];
  const escape = (component) => component.replaceAll("~", "~0").replaceAll("/", "~1");
  const visit = (current, pointer) => {
    const type = current === null ? "null" : Array.isArray(current) ? "array" : typeof current;
    const entry = { pointer, type };
    full.push(entry);
    if (type !== "object" && type !== "array") {
      scalar.push(entry);
      return;
    }
    if (type === "array") {
      current.forEach((child, index) => visit(child, `${pointer}/${index}`));
      return;
    }
    for (const key of Object.keys(current)) visit(current[key], `${pointer}/${escape(key)}`);
  };
  visit(value, "");
  const byPointer = (left, right) => left.pointer < right.pointer ? -1 : left.pointer > right.pointer ? 1 : 0;
  full.sort(byPointer); scalar.sort(byPointer);
  return { full, scalar };
};
const snapshotTree = (target) => {
  const rows = [];
  const visit = (entry, relative) => {
    const stat = fs.lstatSync(entry);
    if (stat.isSymbolicLink()) {
      rows.push([relative, "symlink", fs.readlinkSync(entry)]);
      return;
    }
    if (stat.isFile()) {
      const bytes = fs.readFileSync(entry);
      rows.push([relative, "file", stat.mode & 0o777, stat.uid, bytes.length, sha(bytes)]);
      return;
    }
    if (!stat.isDirectory()) fail("FILESYSTEM_OUTPUT_INVALID_TYPE", relative);
    rows.push([relative, "directory", stat.mode & 0o777, stat.uid]);
    for (const child of fs.readdirSync(entry).sort()) visit(path.join(entry, child), relative ? `${relative}/${child}` : child);
  };
  visit(target, "");
  return JSON.stringify(rows);
};

const projectorSource = fs.readFileSync(projector, "utf8");
const forbiddenProjectorPatterns = [
  /node:(?:child_process|cluster|dgram|dns|http|https|net|tls|worker_threads|wasi)/,
  /\b(?:fetch|WebSocket|EventSource)\s*\(/,
  /\b(?:eval|Function)\s*\(/,
  /\bimport\s*\(/
];
if (forbiddenProjectorPatterns.some((pattern) => pattern.test(projectorSource))) fail("PROJECTOR_EXTERNAL_EFFECT_SURFACE_FORBIDDEN");

const executeCli = (args, cwd, readable = []) => {
  const before = snapshotTree(cwd);
  const nodeArgs = [
    "--no-warnings", "--experimental-permission",
    `--allow-fs-read=${path.dirname(projector)}`,
    ...readable.map((entry) => `--allow-fs-read=${entry}`),
    projector, ...args
  ];
  const result = spawnSync(node, nodeArgs, {
    cwd, env, encoding: null, timeout: 5000, maxBuffer: 262144, shell: false
  });
  if (snapshotTree(cwd) !== before) fail("PROJECTOR_FILESYSTEM_OUTPUT_DETECTED", cwd);
  return result;
};
const executeProjector = (evidencePath, stdoutPath, cwd) => {
  const beforeEvidence = identity(evidencePath);
  const beforeStdout = identity(stdoutPath);
  const result = executeCli(["--evidence", evidencePath, "--candidate-stdout", stdoutPath], cwd, [evidencePath, stdoutPath]);
  if (!exactIdentity(beforeEvidence, identity(evidencePath)) || !exactIdentity(beforeStdout, identity(stdoutPath))) {
    fail("PROJECTOR_INPUT_MUTATION");
  }
  return result;
};
const requireSuccess = (result, label) => {
  if (result.error || result.status !== 0 || result.signal !== null || result.stderr.length !== 0 || result.stdout.length === 0) {
    fail("PROJECTOR_POSITIVE_NON_PASS", { label, status: result.status, stderr: result.stderr?.toString("utf8") });
  }
  return result.stdout;
};
const requireNonPass = (result, expectedReason, label) => {
  if (result.error || result.status !== 1 || result.signal !== null || result.stdout.length !== 0) {
    fail("NEGATIVE_FALSE_ACCEPT", { label, status: result.status, stdout_bytes: result.stdout?.length });
  }
  let parsed;
  try { parsed = JSON.parse(result.stderr.toString("utf8")); } catch { fail("NON_PASS_STDERR_INVALID", label); }
  const expectedBytes = Buffer.from(`${JSON.stringify({ reason: expectedReason, status: "NON_PASS" })}\n`, "utf8");
  if (!result.stderr.equals(expectedBytes) || parsed?.reason !== expectedReason || parsed?.status !== "NON_PASS" || Object.keys(parsed).length !== 2) {
    fail("NON_PASS_REASON_MISMATCH", { actual: result.stderr.toString("utf8"), expected: expectedReason, label });
  }
};
const requireAnyNonPass = (result, label) => {
  if (result.error || result.status !== 1 || result.signal !== null || result.stdout.length !== 0) fail("CLI_FALSE_ACCEPT", label);
  let parsed;
  try { parsed = JSON.parse(result.stderr.toString("utf8")); } catch { fail("NON_PASS_STDERR_INVALID", label); }
  const expectedBytes = Buffer.from(`${JSON.stringify({ reason: parsed.reason, status: "NON_PASS" })}\n`, "utf8");
  if (typeof parsed.reason !== "string" || parsed.reason.length === 0 || parsed.status !== "NON_PASS" ||
      Object.keys(parsed).length !== 2 || !result.stderr.equals(expectedBytes)) fail("CLI_NON_PASS_CONTRACT_MISMATCH", label);
};

const tokenForPath = (value, roles) => {
  const matches = roles.filter(({ root }) => value === root || value.startsWith(`${root}/`));
  if (matches.length !== 1) fail("INDEPENDENT_ORACLE_PATH_ROLE_NON_UNIQUE", value);
  const [{ root, token }] = matches;
  return `${token}${value.slice(root.length)}`;
};
const independentProjection = (evidenceBytes, stdoutBytes) => {
  const evidence = JSON.parse(evidenceBytes.toString("utf8"));
  const stdout = JSON.parse(stdoutBytes.toString("utf8"));
  const suffix = "/candidate-owned/evidence/evidence.json";
  if (typeof stdout.evidence_path !== "string" || !stdout.evidence_path.endsWith(suffix)) fail("INDEPENDENT_ORACLE_STDOUT_SUFFIX_INVALID");
  const runRoot = stdout.evidence_path.slice(0, -suffix.length);
  const roles = [
    { root: evidence.runtime.executable_path, token: "$EXECUTABLE" },
    { root: evidence.runtime.logical_cwd, token: "$CANDIDATE_ROOT" },
    { root: runRoot, token: "$RUN_ROOT" }
  ];
  const output = deepClone(evidence);
  const pathTargets = [
    ["runtime", "executable_path"],
    ["runtime", "executable_realpath"],
    ["runtime", "logical_cwd"],
    ["runtime", "child", "executable_path"],
    ["runtime", "child", "module_path"],
    ["runtime", "child", "logical_cwd"]
  ];
  for (const keys of pathTargets) {
    let cursor = output;
    for (const key of keys.slice(0, -1)) cursor = cursor[key];
    const last = keys.at(-1);
    cursor[last] = tokenForPath(cursor[last], roles);
  }
  output.runtime.ordered_argv = output.runtime.ordered_argv.map((value) =>
    typeof value === "string" && value.startsWith("/") ? tokenForPath(value, roles) : value);
  output.runtime.ordered_argv_sha256 = sha(Buffer.from(JSON.stringify(output.runtime.ordered_argv), "utf8"));
  const normalizedStdout = stableBytes({ candidate_status: stdout.candidate_status, evidence_path: tokenForPath(stdout.evidence_path, roles) });
  output.runtime.stdout_sha256 = sha(normalizedStdout);
  output.runtime.stdout_byte_length = normalizedStdout.length;
  delete output.runtime.duration_ms;
  return stableBytes(output);
};

const publicPositive = new Set();
const publicNegative = new Set();
const markPositive = (id) => {
  if (!positiveIds.includes(id) || id === "P12_WITHHELD_EQUALITY" || publicPositive.has(id)) fail("POSITIVE_COVERAGE_INVALID", id);
  publicPositive.add(id);
};
const markNegative = (id) => {
  if (!negativeIds.includes(id) || id === "N30_RECEIPT_IDENTITY_OR_VERDICT" || publicNegative.has(id)) fail("NEGATIVE_COVERAGE_INVALID", id);
  publicNegative.add(id);
};

const projectionA = requireSuccess(executeProjector(runA.evidencePath, runA.stdoutPath, runA.runRoot), "fresh-a");
const projectionB = requireSuccess(executeProjector(runB.evidencePath, runB.stdoutPath, runB.runRoot), "fresh-b");
const evidenceABytes = fs.readFileSync(runA.evidencePath);
const stdoutABytes = fs.readFileSync(runA.stdoutPath);
const evidenceBBytes = fs.readFileSync(runB.evidencePath);
const stdoutBBytes = fs.readFileSync(runB.stdoutPath);
const evidenceA = JSON.parse(evidenceABytes.toString("utf8"));
const pointerMaps = pointerTypeMaps(evidenceA);
if (pointerMaps.scalar.length !== 166 || pointerMaps.full.length !== 182 ||
    sha(stableBytes(pointerMaps.scalar)) !== "830ac39ff24e505ee98b908cf1ed48eca5d126ed8ee65aced61a84288bd34f5f" ||
    sha(stableBytes(pointerMaps.full)) !== "07beb1ff8847077517c6ebd9d11bcb29f4e37867a9e8bd61a6ed197e2f47451d") {
  fail("EXACT_POINTER_TYPE_MAP_NON_PASS");
}

if (!projectionA.equals(independentProjection(evidenceABytes, stdoutABytes)) ||
    !projectionB.equals(independentProjection(evidenceBBytes, stdoutBBytes))) fail("TRANSFORM_SET_NOT_CLOSED");
if (!projectionA.equals(projectionB)) fail("VISIBLE_PAIR_PROJECTION_BYTES_MISMATCH");
let parsedProjection;
try { parsedProjection = JSON.parse(projectionA.toString("utf8")); } catch { fail("PROJECTION_JSON_INVALID"); }
if (!projectionA.equals(stableBytes(parsedProjection))) fail("PROJECTION_CANONICAL_BYTES_MISMATCH");
if (parsedProjection.runtime?.duration_ms !== undefined || parsedProjection.case_id !== evidenceA.case_id ||
    parsedProjection.runtime?.executable_sha256 !== evidenceA.runtime?.executable_sha256) fail("TRANSFORM_SET_NOT_CLOSED");
if (parsedProjection.runtime?.executable_path !== "$EXECUTABLE" || parsedProjection.runtime?.executable_realpath !== "$EXECUTABLE" ||
    parsedProjection.runtime?.logical_cwd !== "$CANDIDATE_ROOT" || parsedProjection.runtime?.child?.executable_path !== "$EXECUTABLE" ||
    parsedProjection.runtime?.child?.module_path !== "$CANDIDATE_ROOT/evaluation-harness/recording/blind-admission-v1/recorder.mjs" ||
    parsedProjection.runtime?.child?.logical_cwd !== "$RUN_ROOT/candidate-owned/source") fail("PATH_TOKENIZATION_NON_PASS");
if (parsedProjection.patch?.relative_path !== evidenceA.patch?.relative_path ||
    JSON.stringify(parsedProjection.result?.path_set) !== JSON.stringify(evidenceA.result?.path_set) ||
    parsedProjection.runtime?.environment?.PATH !== evidenceA.runtime?.environment?.PATH) fail("REPO_RELATIVE_PRESERVATION_NON_PASS");
if (parsedProjection.runtime?.ordered_argv_sha256 !== sha(Buffer.from(JSON.stringify(parsedProjection.runtime.ordered_argv), "utf8"))) {
  fail("TOKENIZED_ARGV_DIGEST_NON_PASS");
}
const normalizedStdoutExpected = stableBytes({ candidate_status: "COMPLETED", evidence_path: "$RUN_ROOT/candidate-owned/evidence/evidence.json" });
if (parsedProjection.runtime?.stdout_sha256 !== sha(normalizedStdoutExpected) || parsedProjection.runtime?.stdout_byte_length !== normalizedStdoutExpected.length) {
  fail("STDOUT_NORMALIZATION_NON_PASS");
}
if (!exactFalseEffects(evidenceA.external_effects) || !exactFalseEffects(JSON.parse(evidenceBBytes).external_effects)) fail("EXTERNAL_EFFECT_FORBIDDEN");

for (const id of ["P01_EXACT_RAW_IDENTITY", "P02_STRICT_JSON_AND_SCHEMA", "P03_EXACT_POINTER_TYPES",
  "P04_CANDIDATE_AND_RUN_IDENTITY", "P05_ROOT_DERIVATION", "P06_PATH_TOKENIZATION", "P07_REPO_RELATIVE_PRESERVATION",
  "P08_ARGV_DIGEST", "P09_STDOUT_NORMALIZATION", "P10_CLOSED_TRANSFORM", "P11_VISIBLE_EQUALITY"]) markPositive(id);

const createCase = (id, evidenceBytes = evidenceABytes, stdoutBytes = stdoutABytes) => {
  const caseRoot = path.join(verifierRoot, `case-${id.toLowerCase()}`);
  const goldenRoot = path.join(caseRoot, "fresh-golden");
  const mutantRoot = path.join(caseRoot, "fresh-mutant");
  mkdirOwned(caseRoot); mkdirOwned(goldenRoot); mkdirOwned(mutantRoot);
  writeOnce(path.join(goldenRoot, "evidence.json"), evidenceABytes);
  writeOnce(path.join(goldenRoot, "candidate.stdout"), stdoutABytes);
  const evidencePath = path.join(mutantRoot, "evidence.json");
  const stdoutPath = path.join(mutantRoot, "candidate.stdout");
  writeOnce(evidencePath, evidenceBytes);
  writeOnce(stdoutPath, stdoutBytes);
  return { caseRoot, evidencePath, stdoutPath };
};
const mutateEvidence = (mutator, base = evidenceABytes) => {
  const value = JSON.parse(base.toString("utf8"));
  mutator(value);
  return jsonBytes(value);
};
const rebindStdout = (evidenceBytes, stdoutBytes) => mutateEvidence((value) => {
  value.runtime.stdout_sha256 = sha(stdoutBytes);
  value.runtime.stdout_byte_length = stdoutBytes.length;
}, evidenceBytes);
const rebindArgv = (value) => { value.runtime.ordered_argv_sha256 = sha(Buffer.from(JSON.stringify(value.runtime.ordered_argv), "utf8")); };
const expectMutationNonPass = (id, reason, evidenceBytes, stdoutBytes = stdoutABytes) => {
  const item = createCase(id, evidenceBytes, stdoutBytes);
  requireNonPass(executeProjector(item.evidencePath, item.stdoutPath, item.caseRoot), reason, id);
  markNegative(id);
};
const expectMutationSuccess = (id, evidenceBytes, stdoutBytes = stdoutABytes) => {
  const item = createCase(id, evidenceBytes, stdoutBytes);
  const bytes = requireSuccess(executeProjector(item.evidencePath, item.stdoutPath, item.caseRoot), id);
  if (!bytes.equals(independentProjection(evidenceBytes, stdoutBytes))) fail("GENERIC_STRING_MUST_REMAIN_EXACT", id);
  markNegative(id);
  return bytes;
};

{
  const item = createCase("N01_INPUT_HASH_OR_LENGTH_DRIFT");
  const golden = path.join(item.caseRoot, "fresh-golden", "catalog.json");
  const mutant = path.join(item.caseRoot, "fresh-mutant", "catalog.json");
  const bytes = fs.readFileSync(catalogPath);
  writeOnce(golden, bytes);
  writeOnce(mutant, Buffer.concat([bytes, Buffer.from(" ")]));
  if (exactIdentity(identity(mutant), ids.catalog)) fail("INPUT_IDENTITY_FALSE_ACCEPT");
  markNegative("N01_INPUT_HASH_OR_LENGTH_DRIFT");
}
{
  const stdoutJson = JSON.parse(stdoutABytes);
  const duplicate = Buffer.from(`{"candidate_status":"${stdoutJson.candidate_status}","candidate_status":"${stdoutJson.candidate_status}","evidence_path":${JSON.stringify(stdoutJson.evidence_path)}}\n`, "utf8");
  expectMutationNonPass("N02_JSON_DUPLICATE_KEY", "DUPLICATE_JSON_KEY", rebindStdout(evidenceABytes, duplicate), duplicate);
}
{
  const compact = mutateEvidence(() => {});
  const nonfinite = Buffer.from(compact.toString("utf8").replace(/"duration_ms":[^,}]+/, '"duration_ms":1e999'), "utf8");
  expectMutationNonPass("N03_JSON_EXTRA_VALUE_OR_NONFINITE", "INVALID_JSON_VALUE", nonfinite);
}
expectMutationNonPass("N04_POINTER_MISSING", "POINTER_SET_MISMATCH", mutateEvidence((value) => { delete value.runtime.executable_version; }));
expectMutationNonPass("N05_POINTER_ADDED", "POINTER_SET_MISMATCH", mutateEvidence((value) => { value.identities.executable_sha256 = "00".repeat(32); }));
expectMutationNonPass("N06_TYPE_DRIFT", "POINTER_TYPE_MISMATCH", mutateEvidence((value) => { value.external_effects.network = 0; }));
expectMutationNonPass("N07_EXECUTABLE_DIGEST_MISSING_OR_CHANGED", "EXECUTABLE_DIGEST_MISSING_OR_CHANGED", mutateEvidence((value) => { delete value.runtime.executable_sha256; }));
expectMutationNonPass("N08_ROOT_NOT_ABSOLUTE", "PATH_NOT_ABSOLUTE_POSIX", mutateEvidence((value) => { value.runtime.logical_cwd = "relative/candidate"; }));
expectMutationNonPass("N09_ROOT_LEXICAL_ALIAS", "PATH_LEXICAL_ALIAS", mutateEvidence((value) => { value.runtime.logical_cwd = "/worktrees/../candidate"; }));
{
  const changedStdout = jsonBytes({ candidate_status: "COMPLETED", evidence_path: `${repo}/synthetic-overlap/candidate-owned/evidence/evidence.json` });
  expectMutationNonPass("N10_ROOT_EQUAL_OR_OVERLAP", "ROOT_ROLE_OVERLAP", rebindStdout(evidenceABytes, changedStdout), changedStdout);
}
expectMutationNonPass("N11_PATH_UNMATCHED", "PATH_ROLE_NOT_UNIQUE", mutateEvidence((value) => { value.runtime.child.module_path = "/undeclared/recorder.mjs"; }));
expectMutationNonPass("N12_PATH_AMBIGUOUS", "ROOT_ROLE_OVERLAP", mutateEvidence((value) => {
  value.runtime.logical_cwd = value.runtime.executable_path;
  for (const flag of ["--canonical-root", "--logical-cwd"]) value.runtime.ordered_argv[value.runtime.ordered_argv.indexOf(flag) + 1] = value.runtime.executable_path;
  rebindArgv(value);
}));
expectMutationNonPass("N13_PREFIX_NOT_COMPONENT", "PATH_ROLE_NOT_UNIQUE", mutateEvidence((value) => { value.runtime.child.logical_cwd = `${runA.runRoot}-escape/source`; }));
expectMutationNonPass("N14_UNDECLARED_ABSOLUTE_PATH_FIELD", "UNDECLARED_ABSOLUTE_PATH_FIELD", mutateEvidence((value) => { value.result.files[0].content = "/undeclared/value"; }));
expectMutationSuccess("N15_GENERIC_STRING_REPLACEMENT", mutateEvidence((value) => { value.result.files[0].content = `prefix-${repo}-suffix`; }));
expectMutationNonPass("N16_REPO_RELATIVE_ESCAPE", "REPO_PATH_INVALID", mutateEvidence((value) => { value.patch.relative_path = "../escape.txt"; }));
expectMutationNonPass("N17_ARGV_NON_ARRAY_OR_NON_STRING", "POINTER_TYPE_MISMATCH", mutateEvidence((value) => { value.runtime.ordered_argv[1] = 7; }));
{
  const changed = mutateEvidence((value) => {
    const argv = value.runtime.ordered_argv;
    const casePair = argv.splice(argv.length - 2, 2);
    argv.splice(argv.length - 2, 0, ...casePair);
    rebindArgv(value);
  });
  const item = createCase("N18_ARGV_ORDER_OR_CARDINALITY", changed);
  const bytes = requireSuccess(executeProjector(item.evidencePath, item.stdoutPath, item.caseRoot), "N18_ARGV_ORDER_OR_CARDINALITY");
  if (bytes.equals(projectionA)) fail("PAIR_PROJECTION_FALSE_EQUAL", "N18_ARGV_ORDER_OR_CARDINALITY");
  markNegative("N18_ARGV_ORDER_OR_CARDINALITY");
}
expectMutationNonPass("N19_RAW_ARGV_DIGEST_MISMATCH", "RAW_ARGV_SHA256_MISMATCH", mutateEvidence((value) => { value.runtime.ordered_argv_sha256 = "0".repeat(64); }));
expectMutationNonPass("N20_REQUIRED_ARGV_BINDING", "ARGV_BINDING_MISMATCH", mutateEvidence((value) => {
  const stdout = JSON.parse(stdoutABytes);
  const suffix = "/candidate-owned/evidence/evidence.json";
  const runRoot = stdout.evidence_path.slice(0, -suffix.length);
  value.runtime.ordered_argv[value.runtime.ordered_argv.indexOf("--owned-root") + 1] = `${runRoot}/wrong-owned-root`;
  rebindArgv(value);
}));
{
  const changedStdout = Buffer.from("[]\n", "utf8");
  expectMutationNonPass("N21_STDOUT_NOT_OBJECT", "STDOUT_NOT_OBJECT", rebindStdout(evidenceABytes, changedStdout), changedStdout);
}
{
  const stdout = { ...JSON.parse(stdoutABytes), extra: true };
  const changedStdout = jsonBytes(stdout);
  expectMutationNonPass("N22_STDOUT_KEY_SET", "STDOUT_KEY_SET_MISMATCH", rebindStdout(evidenceABytes, changedStdout), changedStdout);
}
{
  const stdout = { ...JSON.parse(stdoutABytes), candidate_status: 7 };
  const changedStdout = jsonBytes(stdout);
  expectMutationNonPass("N23_STDOUT_VALUE_TYPE", "STDOUT_VALUE_TYPE_MISMATCH", rebindStdout(evidenceABytes, changedStdout), changedStdout);
}
{
  const stdout = { ...JSON.parse(stdoutABytes), candidate_status: "REJECTED" };
  const changedStdout = jsonBytes(stdout);
  expectMutationNonPass("N24_STDOUT_STATUS_MISMATCH", "STDOUT_STATUS_MISMATCH", rebindStdout(evidenceABytes, changedStdout), changedStdout);
}
{
  const stdout = JSON.parse(stdoutABytes);
  stdout.evidence_path = `${runA.runRoot}/wrong/evidence.json`;
  const changedStdout = jsonBytes(stdout);
  expectMutationNonPass("N25_STDOUT_EVIDENCE_PATH_MISMATCH", "STDOUT_EVIDENCE_PATH_MISMATCH", rebindStdout(evidenceABytes, changedStdout), changedStdout);
}
expectMutationNonPass("N26_RAW_STDOUT_BINDING_MISMATCH", "RAW_STDOUT_BINDING_MISMATCH", evidenceABytes, Buffer.concat([stdoutABytes, Buffer.from(" ")]));
{
  const item = createCase("N27_FORBIDDEN_TRANSFORM");
  const goldenProjection = path.join(item.caseRoot, "fresh-golden", "projection.json");
  const mutantProjection = path.join(item.caseRoot, "fresh-mutant", "projection.json");
  writeOnce(goldenProjection, projectionA);
  const value = JSON.parse(projectionA);
  value.runtime.duration_ms = evidenceA.runtime.duration_ms;
  writeOnce(mutantProjection, stableBytes(value));
  if (fs.readFileSync(mutantProjection).equals(independentProjection(evidenceABytes, stdoutABytes))) fail("TRANSFORM_SET_FALSE_ACCEPT");
  markNegative("N27_FORBIDDEN_TRANSFORM");
}
{
  const changed = mutateEvidence((value) => { value.case_id = "synthetic-case-002"; });
  const item = createCase("N28_CASE_ID_MISMATCH", changed);
  const bytes = requireSuccess(executeProjector(item.evidencePath, item.stdoutPath, item.caseRoot), "N28_CASE_ID_MISMATCH");
  if (JSON.parse(changed).case_id === evidenceA.case_id || bytes.equals(projectionA)) fail("PAIR_CASE_ID_FALSE_ACCEPT");
  markNegative("N28_CASE_ID_MISMATCH");
}
{
  const changed = mutateEvidence((value) => { value.task_id = "SYNTHETIC-DIFFERENT"; });
  const item = createCase("N29_PAIR_SEMANTIC_MISMATCH", changed);
  const bytes = requireSuccess(executeProjector(item.evidencePath, item.stdoutPath, item.caseRoot), "N29_PAIR_SEMANTIC_MISMATCH");
  if (bytes.equals(projectionA)) fail("PAIR_PROJECTION_FALSE_EQUAL", "N29_PAIR_SEMANTIC_MISMATCH");
  markNegative("N29_PAIR_SEMANTIC_MISMATCH");
}
{
  const item = createCase("N31_CANONICAL_BYTES");
  const goldenProjection = path.join(item.caseRoot, "fresh-golden", "projection.json");
  const mutantProjection = path.join(item.caseRoot, "fresh-mutant", "projection.json");
  writeOnce(goldenProjection, projectionA);
  writeOnce(mutantProjection, Buffer.from(`${JSON.stringify(JSON.parse(projectionA), null, 2)}\n`, "utf8"));
  if (fs.readFileSync(mutantProjection).equals(stableBytes(JSON.parse(projectionA)))) fail("PROJECTION_CANONICAL_FALSE_ACCEPT");
  markNegative("N31_CANONICAL_BYTES");
}

const cliCases = [
  [],
  ["--evidence", runA.evidencePath],
  ["--evidence", runA.evidencePath, "--candidate-stdout", runA.stdoutPath, "--unknown", "x"],
  ["--evidence", runA.evidencePath, "--evidence", runA.evidencePath, "--candidate-stdout", runA.stdoutPath],
  ["positional", "--evidence", runA.evidencePath, "--candidate-stdout", runA.stdoutPath]
];
for (let index = 0; index < cliCases.length; index += 1) {
  const cliRoot = path.join(verifierRoot, `cli-negative-${index + 1}`);
  mkdirOwned(cliRoot);
  requireAnyNonPass(executeCli(cliCases[index], cliRoot, [runA.evidencePath, runA.stdoutPath]), `CLI-${index + 1}`);
}

const expectedPublicPositive = positiveIds.filter((id) => id !== "P12_WITHHELD_EQUALITY");
const expectedPublicNegative = negativeIds.filter((id) => id !== "N30_RECEIPT_IDENTITY_OR_VERDICT");
if (publicPositive.size !== expectedPublicPositive.length || expectedPublicPositive.some((id) => !publicPositive.has(id))) {
  fail("PUBLIC_POSITIVE_COVERAGE_INCOMPLETE", [...publicPositive].sort());
}
if (publicNegative.size !== expectedPublicNegative.length || expectedPublicNegative.some((id) => !publicNegative.has(id))) {
  fail("PUBLIC_NEGATIVE_COVERAGE_INCOMPLETE", [...publicNegative].sort());
}

for (const [name, original] of Object.entries(ids)) {
  const file = {
    catalog: catalogPath, projectionContract, projectionReadme, recorder, runner, runtime, source, syntheticPair,
    task, taskContract, validator
  }[name];
  if (!exactIdentity(original, identity(file))) fail("PUBLIC_INPUT_MUTATION", name);
}

process.stdout.write(`P1_071_PUBLIC_TARGETED_VERIFIER_OK public_positive=${publicPositive.size}/${expectedPublicPositive.length} public_negative=${publicNegative.size}/${expectedPublicNegative.length} local_catalog=41/41 formal_required=2/2 cli_negative=${cliCases.length}/${cliCases.length} fresh_public_runs=2 visible_pair=PASS P12_WITHHELD_EQUALITY=FORMAL_QUALITY_REQUIRED N30_RECEIPT_IDENTITY_OR_VERDICT=FORMAL_QUALITY_REQUIRED rollback=PASS external_effects=FALSE`);
NODE
set +o noclobber
chmod 400 "${DRIVER}"

set +e
DRIVER_OUTPUT="$("${NODE_BIN}" "${DRIVER}" "${ROOT_DIR}" "${VERIFIER_ROOT}")"
DRIVER_STATUS=$?
set -e

cleanup_owned_root
trap - EXIT

if [[ ${DRIVER_STATUS} -ne 0 ]]; then
  exit "${DRIVER_STATUS}"
fi
if [[ -e "${VERIFIER_ROOT}" || -L "${VERIFIER_ROOT}" ]]; then
  printf '%s\n' '{"reason":"CLEANUP_NOT_EXACT","status":"NON_PASS"}' >&2
  exit 1
fi
printf '%s cleanup=PASS\n' "${DRIVER_OUTPUT}"

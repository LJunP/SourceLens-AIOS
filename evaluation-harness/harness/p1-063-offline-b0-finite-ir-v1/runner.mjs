#!/usr/local/bin/node

import { spawnSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import {
  chmodSync,
  closeSync,
  constants as fsConstants,
  fstatSync,
  fsyncSync,
  linkSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  symlinkSync,
  unlinkSync,
  writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ADAPTER_ID,
  ADAPTER_VERSION,
  OfflineAdapterError,
  admitOfflineB0Result,
  validateOfflineSubmission,
} from "../../adapters/p1-063-offline-b0-finite-ir-v1/offline-adapter.mjs";

export const RUNNER_VERSION = "P1-063-OFFLINE-FINITE-IR-B0-RUNNER/1";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../../..");
const TASK_ID = "AIOS-P1-063_CLEAN_ROOM_OFFLINE_RESULT_ADMISSION_AND_B0_ADAPTER";
const CONTROL_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const EVIDENCE_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-063-direct-engineering-v1-zIDwM3Va";
const QUALITY_MANIFEST_PATH = join(EVIDENCE_ROOT, "quality/QUALITY_FREEZE_MANIFEST.json");
const QUALITY_RECEIPT_PATH = join(EVIDENCE_ROOT, "quality/QUALITY_FREEZE_RECEIPT.json");
const QUALITY_MANIFEST_IDENTITY = Object.freeze({
  byte_length: 3994,
  sha256: "93d6b769c1d8f525e3302748317ecc7c7075e9363738e907f4233f89b2e5c2fb",
});
const QUALITY_RECEIPT_IDENTITY = Object.freeze({
  byte_length: 1196,
  sha256: "bbb32bea97de5fd920d1db6abf123555b4a740938fc7542fcf97aed03129159c",
});
const FIXTURE_ROOT = "evaluation-harness/fixtures/p1-063-offline-b0-finite-ir-v1";
const QUALITY_IDENTITIES = Object.freeze({
  task_card: Object.freeze({ path: `${FIXTURE_ROOT}/task-card.json`, byte_length: 11471, sha256: "fc2bf93b1887a633c2551f39d2d3636479746e089658892826c56e378fd8a34a" }),
  task_card_schema: Object.freeze({ path: `${FIXTURE_ROOT}/task-card.schema.json`, byte_length: 15285, sha256: "e9e9d15e31f64c33a45d1343beb69d4db0c3796f1e7dbb7374e13b5b70d43853" }),
  offline_submission: Object.freeze({ path: `${FIXTURE_ROOT}/offline-submission.json`, byte_length: 669, sha256: "c985ac00ab841d2a51c75679525e6d3d9ea0ece92fcd28f04878236943834bec" }),
  offline_submission_schema: Object.freeze({ path: `${FIXTURE_ROOT}/offline-submission.schema.json`, byte_length: 1575, sha256: "a02f2b9956322edfdb0e3541d24134c72c202a200a1da63165e28b26c9f8f62c" }),
  expected_results: Object.freeze({ path: `${FIXTURE_ROOT}/expected-results.json`, byte_length: 5219, sha256: "e3ff664329485cdd843d37d031e5e9f94a9b16bf8dd750abf3347dcdf9d61f20" }),
  negative_cases: Object.freeze({ path: `${FIXTURE_ROOT}/negative-cases.json`, byte_length: 4026, sha256: "00d578fca6dfc0e947fbae8bd36252167b7c1a8ec786b3da2bb45ec26a25614e" }),
  golden: Object.freeze({ path: `${FIXTURE_ROOT}/golden-stable-projection.json`, byte_length: 6660, sha256: "9f96f7e4b3157f79e469e9935c7f7482c47ee80eabd3db5f7c3d35380fc01a0a" }),
  evaluator: Object.freeze({ path: "evaluation-harness/evaluator/p1-063-offline-b0-finite-ir-v1/quality-evaluator.mjs", byte_length: 30214, sha256: "50624c92bdcdfe6fe14bc994b849b4619ce5145b43b07254c75032e4af0d2110" }),
});
const WORKER_IMPORTS = Object.freeze({
  "evaluation-harness/adapters/p1-063-offline-b0-finite-ir-v1/offline-adapter.mjs": Object.freeze([
    "../../harness/finite-typed-patch-ir-v1/compiler.mjs",
  ]),
  "evaluation-harness/harness/p1-063-offline-b0-finite-ir-v1/runner.mjs": Object.freeze([
    "node:child_process",
    "node:crypto",
    "node:fs",
    "node:os",
    "node:path",
    "node:url",
    "../../adapters/p1-063-offline-b0-finite-ir-v1/offline-adapter.mjs",
  ]),
  "scripts/verify-p1-063-offline-b0-finite-ir-v1.sh": Object.freeze([]),
});
const WORKER_PATHS = Object.freeze(Object.keys(WORKER_IMPORTS).sort());
const REQUIRED_ACTIONS = Object.freeze([
  "validate_candidate_and_quality_identities",
  "validate_worker_import_surface",
  "validate_frozen_inputs",
  "validate_offline_submission",
  "materialize_fresh_rep001_repository",
  "verify_base_commit_tree_and_clean_state",
  "run_base_issue_test",
  "validate_typed_base_failure",
  "run_base_regression_test",
  "admit_exact_ir10_without_decode_or_parse",
  "atomically_replace_target",
  "verify_exact_changed_path",
  "run_patched_issue_test",
  "run_patched_regression_test",
  "restore_exact_base",
  "verify_exact_rollback",
  "emit_create_once_raw_evidence",
  "emit_stable_projection",
]);
const REQUIRED_ARTIFACTS = Object.freeze([
  Object.freeze({ id: "commands", path: "commands.json" }),
  Object.freeze({ id: "observation", path: "observation.json" }),
  Object.freeze({ id: "rollback", path: "rollback.json" }),
  Object.freeze({ id: "run_record", path: "run-record.json" }),
  Object.freeze({ id: "stable_projection", path: "stable-projection.json" }),
]);
const RUN_ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/u;
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const CLAIM_BOUNDARY = "ONE_VISIBLE_SYNTHETIC_REP_001_COOPERATIVE_LOCAL_OFFLINE_FINITE_IR_RESULT_ADMISSION_AND_B0_ADAPTER_RUN_WITH_INDEPENDENT_REPLAY_AND_ROLLBACK_ONLY_NO_LIVE_MODEL_PROVIDER_PROVENANCE_B0_SUITE_B1_B2_VTSR_TRUSTWORTHY_AGENT_P1_COMPLETION_P2_P3_PRODUCTION_PUBLIC_OR_HOSTILE_PRINCIPAL_CLAIM";
const NODE = "/usr/local/bin/node";
const GIT = "/usr/bin/git";
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const MAX_BUFFER = 4 * 1024 * 1024;
const COMMAND_TIMEOUT_MS = 15_000;

class RunnerError extends Error {
  constructor(reasonCode, message) {
    super(message);
    this.name = "RunnerError";
    this.reasonCode = reasonCode;
  }
}

const reject = (reasonCode, message) => {
  throw new RunnerError(reasonCode, message);
};

const assert = (condition, reasonCode, message) => {
  if (!condition) reject(reasonCode, message);
};

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function sortedValue(value) {
  if (Array.isArray(value)) return value.map(sortedValue);
  if (value && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortedValue(value[key])]));
  }
  return value;
}

function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(sortedValue(value))}\n`, "utf8");
}

function sameValue(left, right) {
  return canonicalJsonBytes(left).equals(canonicalJsonBytes(right));
}

function identityOf(bytes) {
  return Object.freeze({ byte_length: bytes.length, sha256: sha256(bytes) });
}

function exactKeys(value, expected, reasonCode) {
  assert(value && typeof value === "object" && !Array.isArray(value), reasonCode, "object required");
  assert(
    JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...expected].sort()),
    reasonCode,
    "closed member set drift",
  );
}

function repositoryPath(relativePath, reasonCode = "PATH_REJECTED") {
  assert(typeof relativePath === "string" && relativePath.length > 0, reasonCode, "path missing");
  assert(!isAbsolute(relativePath), reasonCode, "repository path must be relative");
  const absolute = resolve(ROOT, relativePath);
  const rel = relative(ROOT, absolute);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), reasonCode, "path escaped repository");
  return absolute;
}

function containedPath(root, relativePath, reasonCode = "PATH_REJECTED") {
  assert(typeof relativePath === "string" && relativePath.length > 0 && !isAbsolute(relativePath), reasonCode, "relative path required");
  const absolute = resolve(root, relativePath);
  const rel = relative(root, absolute);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), reasonCode, "path escaped root");
  return absolute;
}

function secureRead(absolutePath, {
  prefix = "FILE",
  expected = undefined,
  requireNlinkOne = true,
  requireCanonicalPath = true,
} = {}) {
  assert(isAbsolute(absolutePath), `${prefix}_PATH_REJECTED`, "absolute path required");
  let before;
  try {
    before = lstatSync(absolutePath);
  } catch (error) {
    reject(`${prefix}_MISSING`, error.message);
  }
  assert(!before.isSymbolicLink(), `${prefix}_SYMLINK_REJECTED`, "symlink rejected");
  assert(before.isFile(), `${prefix}_TYPE_REJECTED`, "regular file required");
  if (requireNlinkOne) assert(before.nlink === 1, `${prefix}_NLINK_REJECTED`, "nlink must equal one");
  if (requireCanonicalPath) assert(realpathSync(absolutePath) === absolutePath, `${prefix}_PATH_REJECTED`, "path contains alias");
  let descriptor;
  try {
    descriptor = openSync(absolutePath, fsConstants.O_RDONLY | O_NOFOLLOW);
    const opened = fstatSync(descriptor);
    assert(opened.isFile(), `${prefix}_TYPE_REJECTED`, "opened object is not regular");
    if (requireNlinkOne) assert(opened.nlink === 1, `${prefix}_NLINK_REJECTED`, "opened nlink drift");
    assert(opened.dev === before.dev && opened.ino === before.ino, `${prefix}_IDENTITY_DRIFT_REJECTED`, "descriptor identity mismatch");
    const bytes = readFileSync(descriptor);
    const after = lstatSync(absolutePath);
    assert(!after.isSymbolicLink() && after.isFile(), `${prefix}_IDENTITY_DRIFT_REJECTED`, "path type drift");
    assert(after.dev === opened.dev && after.ino === opened.ino, `${prefix}_IDENTITY_DRIFT_REJECTED`, "path identity drift");
    assert(after.size === bytes.length && opened.size === bytes.length, `${prefix}_IDENTITY_DRIFT_REJECTED`, "file size drift");
    if (requireNlinkOne) assert(after.nlink === 1, `${prefix}_NLINK_REJECTED`, "final nlink drift");
    const identity = identityOf(bytes);
    if (expected) {
      assert(identity.byte_length === expected.byte_length, `${prefix}_IDENTITY_MISMATCH`, "byte length mismatch");
      assert(identity.sha256 === expected.sha256, `${prefix}_IDENTITY_MISMATCH`, "sha256 mismatch");
    }
    return Object.freeze({ path: absolutePath, bytes, stat: opened, ...identity });
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function secureReadJson(absolutePath, options = {}) {
  const file = secureRead(absolutePath, options);
  try {
    return Object.freeze({ ...file, value: JSON.parse(file.bytes.toString("utf8")) });
  } catch (error) {
    reject(`${options.prefix ?? "JSON"}_PARSE_REJECTED`, error.message);
  }
}

function directoryIdentity(absolutePath, prefix = "DIRECTORY") {
  assert(isAbsolute(absolutePath), `${prefix}_PATH_REJECTED`, "absolute directory required");
  let stat;
  try {
    stat = lstatSync(absolutePath);
  } catch (error) {
    reject(`${prefix}_MISSING`, error.message);
  }
  assert(!stat.isSymbolicLink(), `${prefix}_SYMLINK_REJECTED`, "directory symlink rejected");
  assert(stat.isDirectory(), `${prefix}_TYPE_REJECTED`, "directory required");
  assert(realpathSync(absolutePath) === absolutePath, `${prefix}_PATH_REJECTED`, "directory path contains alias");
  return Object.freeze({ path: absolutePath, dev: stat.dev, ino: stat.ino });
}

function verifyDirectory(receipt, reasonCode = "DIRECTORY_IDENTITY_DRIFT_REJECTED") {
  const current = directoryIdentity(receipt.path);
  assert(current.dev === receipt.dev && current.ino === receipt.ino, reasonCode, "directory identity drift");
  return current;
}

function classifyExistingDirectory(path) {
  const stat = lstatSync(path);
  if (stat.isSymbolicLink()) reject("DIRECTORY_SYMLINK_REJECTED", "directory target is symlink");
  reject("PREEXISTING_DIRECTORY_REJECTED", "directory target already exists");
}

function createExclusiveDirectory(path, mode = 0o700) {
  assert(isAbsolute(path), "DIRECTORY_PATH_REJECTED", "absolute directory required");
  try {
    lstatSync(path);
    classifyExistingDirectory(path);
  } catch (error) {
    if (error instanceof RunnerError) throw error;
    if (error.code !== "ENOENT") throw error;
  }
  try {
    mkdirSync(path, { recursive: false, mode });
  } catch (error) {
    if (error.code === "EEXIST") classifyExistingDirectory(path);
    throw error;
  }
  chmodSync(path, mode);
  return directoryIdentity(path);
}

function writeAll(descriptor, bytes) {
  let offset = 0;
  while (offset < bytes.length) offset += writeSync(descriptor, bytes, offset, bytes.length - offset);
}

function createExclusiveFile(path, bytes, {
  mode = 0o600,
  prefix = "EVIDENCE",
} = {}) {
  assert(Buffer.isBuffer(bytes), `${prefix}_TYPE_REJECTED`, "bytes required");
  let descriptor;
  try {
    descriptor = openSync(
      path,
      fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | O_NOFOLLOW,
      mode,
    );
    writeAll(descriptor, bytes);
    fsyncSync(descriptor);
    chmodSync(path, mode);
    const opened = fstatSync(descriptor);
    assert(opened.isFile() && opened.nlink === 1, `${prefix}_NLINK_REJECTED`, "created leaf identity rejected");
    const receipt = Object.freeze({ path, dev: opened.dev, ino: opened.ino, mode, ...identityOf(bytes) });
    const reread = secureRead(path, { prefix, expected: receipt });
    assert(reread.stat.dev === receipt.dev && reread.stat.ino === receipt.ino, `${prefix}_IDENTITY_DRIFT_REJECTED`, "created leaf identity drift");
    return receipt;
  } catch (error) {
    if (error instanceof RunnerError) throw error;
    if (error.code === "ELOOP") reject(`${prefix}_SYMLINK_REJECTED`, "symlink leaf rejected");
    if (error.code === "EEXIST") {
      const existing = lstatSync(path);
      if (existing.isSymbolicLink()) reject(`${prefix}_SYMLINK_REJECTED`, "symlink leaf rejected");
      reject(`${prefix}_PREEXISTING_REJECTED`, "leaf already exists");
    }
    throw error;
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function verifyFileReceipt(receipt, prefix = "EVIDENCE") {
  const file = secureRead(receipt.path, { prefix });
  assert(
    file.stat.dev === receipt.dev
      && file.stat.ino === receipt.ino
      && file.byte_length === receipt.byte_length
      && file.sha256 === receipt.sha256,
    `${prefix}_TAMPER_REJECTED`,
    "leaf identity or bytes drift",
  );
  return file;
}

function completeAction(actions, actionId) {
  assert(REQUIRED_ACTIONS[actions.length] === actionId, "ACTION_SCHEDULE_REJECTED", `unexpected action ${actionId}`);
  actions.push(actionId);
}

function parseQualityFreeze() {
  const manifestFile = secureReadJson(QUALITY_MANIFEST_PATH, {
    prefix: "QUALITY_MANIFEST",
    expected: QUALITY_MANIFEST_IDENTITY,
  });
  const receiptFile = secureReadJson(QUALITY_RECEIPT_PATH, {
    prefix: "QUALITY_RECEIPT",
    expected: QUALITY_RECEIPT_IDENTITY,
  });
  const manifest = manifestFile.value;
  const receipt = receiptFile.value;
  assert(manifest.status === "FROZEN" && manifest.task_id === TASK_ID, "QUALITY_FREEZE_REJECTED", "Quality manifest drift");
  assert(receipt.status === "PASS" && receipt.worker_may_start === true && receipt.task_id === TASK_ID, "QUALITY_FREEZE_REJECTED", "Quality receipt drift");
  assert(
    receipt.quality_freeze_manifest?.sha256 === QUALITY_MANIFEST_IDENTITY.sha256
      && receipt.quality_freeze_manifest?.byte_length === QUALITY_MANIFEST_IDENTITY.byte_length,
    "QUALITY_FREEZE_REJECTED",
    "Quality receipt does not bind the manifest",
  );
  assert(manifest.quality_files_sorted_by_path.length === Object.keys(QUALITY_IDENTITIES).length, "QUALITY_FREEZE_REJECTED", "Quality file population drift");
  for (const expected of Object.values(QUALITY_IDENTITIES)) {
    const declared = manifest.quality_files_sorted_by_path.find((entry) => entry.path === expected.path);
    assert(declared && declared.byte_length === expected.byte_length && declared.sha256 === expected.sha256, "QUALITY_FREEZE_REJECTED", `Quality identity drift: ${expected.path}`);
    secureRead(repositoryPath(expected.path), { prefix: "QUALITY_ASSET", expected });
  }
  return Object.freeze({ manifestFile, receiptFile, manifest, receipt });
}

function loadQualityJson(identity, prefix) {
  return secureReadJson(repositoryPath(identity.path), { prefix, expected: identity });
}

function currentUserCanWrite(stat) {
  const uid = typeof process.getuid === "function" ? process.getuid() : undefined;
  const gid = typeof process.getgid === "function" ? process.getgid() : undefined;
  const groups = typeof process.getgroups === "function" ? process.getgroups() : [];
  const mode = stat.mode & 0o777;
  if (uid === 0) return true;
  if (uid !== undefined && uid === stat.uid) return Boolean(mode & 0o200);
  if (gid !== undefined && (gid === stat.gid || groups.includes(stat.gid))) return Boolean(mode & 0o020);
  return Boolean(mode & 0o002);
}

function validateExecutable(path, label) {
  const file = secureRead(path, { prefix: "TOOL", requireNlinkOne: false });
  assert((file.stat.mode & 0o111) !== 0, "TOOL_IDENTITY_REJECTED", `${label} is not executable`);
  assert(!currentUserCanWrite(file.stat), "TOOL_IDENTITY_REJECTED", `${label} is writable by the current user`);
  return file;
}

function scanWorkerSource(path, bytes, importAllowlist) {
  const text = bytes.toString("utf8");
  assert(!/\bimport\s*\(/u.test(text), "DYNAMIC_IMPORT_REJECTED", `${path} dynamic module load`);
  assert(!/\brequire\s*\(/u.test(text), "REQUIRE_REJECTED", `${path} CommonJS load`);
  assert(!/\b(?:fetch|WebSocket|XMLHttpRequest)\s*\(/u.test(text), "NETWORK_CAPABLE_IMPORT_REJECTED", `${path} network API`);
  const forbidden = new Set([
    "node:http", "node:https", "node:http2", "node:net", "node:tls", "node:dgram", "node:dns",
    "http", "https", "net", "tls", "dgram", "dns", "undici", "ws",
  ]);
  const imports = [];
  for (const match of text.matchAll(/\b(?:import|export)\s+(?:[^"']*?\s+from\s+)?["']([^"']+)["']/gu)) imports.push(match[1]);
  assert(imports.every((specifier) => !forbidden.has(specifier)), "NETWORK_CAPABLE_IMPORT_REJECTED", `${path} network module`);
  assert(
    JSON.stringify([...imports].sort()) === JSON.stringify([...importAllowlist].sort()),
    "IMPORT_SURFACE_REJECTED",
    `${path} import surface drift`,
  );
  return imports;
}

function workerFileRecords() {
  return WORKER_PATHS.map((path) => {
    const file = secureRead(repositoryPath(path), { prefix: "WORKER_SOURCE" });
    scanWorkerSource(path, file.bytes, WORKER_IMPORTS[path]);
    return Object.freeze({
      path,
      byte_length: file.byte_length,
      sha256: file.sha256,
      mode: (file.stat.mode & 0o111) === 0 ? "100644" : "100755",
    });
  });
}

function loadCandidateManifest(absolutePath, qualityFreeze) {
  assert(isAbsolute(absolutePath), "CANDIDATE_BINDING_REJECTED", "candidate manifest must be absolute");
  const file = secureReadJson(absolutePath, { prefix: "CANDIDATE_MANIFEST" });
  const manifest = file.value;
  exactKeys(
    manifest,
    ["schema_version", "record_type", "task_id", "candidate_commit", "candidate_tree", "quality_freeze_manifest_sha256", "worker_files_sorted_by_path"],
    "CANDIDATE_MANIFEST_SCHEMA_REJECTED",
  );
  assert(manifest.schema_version === 1 && manifest.record_type === "sourcelens_aios_p1_063_candidate_manifest", "CANDIDATE_MANIFEST_SCHEMA_REJECTED", "candidate manifest type drift");
  assert(manifest.task_id === TASK_ID, "CANDIDATE_BINDING_REJECTED", "candidate Task drift");
  assert(/^[0-9a-f]{40}$/u.test(manifest.candidate_commit) && /^[0-9a-f]{40}$/u.test(manifest.candidate_tree), "CANDIDATE_BINDING_REJECTED", "candidate Git identity rejected");
  assert(manifest.quality_freeze_manifest_sha256 === qualityFreeze.manifestFile.sha256, "CANDIDATE_BINDING_REJECTED", "candidate Quality binding drift");
  const actualRecords = workerFileRecords();
  assert(sameValue(manifest.worker_files_sorted_by_path, actualRecords), "CANDIDATE_FILE_IDENTITY_REJECTED", "candidate Worker file identity drift");

  const environment = deterministicEnvironment(EVIDENCE_ROOT);
  const head = executeCommand(GIT, ["-C", ROOT, "rev-parse", "HEAD"], ROOT, environment);
  const tree = executeCommand(GIT, ["-C", ROOT, "rev-parse", "HEAD^{tree}"], ROOT, environment);
  const status = executeCommand(GIT, ["-C", ROOT, "status", "--porcelain=v1", "--untracked-files=all"], ROOT, environment);
  assert(head.exit_status === 0 && head.stdout.toString("utf8").trim() === manifest.candidate_commit, "CANDIDATE_BINDING_REJECTED", "candidate HEAD drift");
  assert(tree.exit_status === 0 && tree.stdout.toString("utf8").trim() === manifest.candidate_tree, "CANDIDATE_BINDING_REJECTED", "candidate tree drift");
  assert(status.exit_status === 0 && status.stdout.length === 0, "CANDIDATE_BINDING_REJECTED", "candidate checkout is not clean");
  return Object.freeze({
    file,
    manifest,
    binding: Object.freeze({
      candidate_commit: manifest.candidate_commit,
      candidate_tree: manifest.candidate_tree,
      candidate_manifest_sha256: file.sha256,
      quality_freeze_manifest_sha256: manifest.quality_freeze_manifest_sha256,
    }),
  });
}

function deterministicEnvironment(homePath) {
  return Object.freeze({
    HOME: homePath,
    PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
    LANG: "C",
    LC_ALL: "C",
    TZ: "UTC",
    NODE_OPTIONS: "--no-warnings",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_TERMINAL_PROMPT: "0",
    GIT_OPTIONAL_LOCKS: "0",
    GIT_AUTHOR_NAME: "SourceLens AIOS Fixture",
    GIT_AUTHOR_EMAIL: "fixture@sourcelens.local",
    GIT_AUTHOR_DATE: "2000-01-01T00:00:00Z",
    GIT_COMMITTER_NAME: "SourceLens AIOS Fixture",
    GIT_COMMITTER_EMAIL: "fixture@sourcelens.local",
    GIT_COMMITTER_DATE: "2000-01-01T00:00:00Z",
  });
}

function executeCommand(executable, args, cwd, environment, input = undefined) {
  const started = Date.now();
  const result = spawnSync(executable, args, {
    cwd,
    env: environment,
    input,
    encoding: null,
    shell: false,
    timeout: COMMAND_TIMEOUT_MS,
    maxBuffer: MAX_BUFFER,
    windowsHide: true,
  });
  const stdout = Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0);
  assert(!result.error, "COMMAND_EXECUTION_REJECTED", result.error?.message ?? "command execution failed");
  return Object.freeze({
    executable,
    args: Object.freeze([...args]),
    argv: Object.freeze([executable, ...args]),
    cwd,
    exit_status: result.status,
    signal: result.signal,
    timeout_ms: COMMAND_TIMEOUT_MS,
    max_buffer_bytes: MAX_BUFFER,
    duration_ms: Date.now() - started,
    stdout,
    stderr,
  });
}

function commandEvidence(actionId, record) {
  return Object.freeze({
    action_id: actionId,
    argv: record.argv,
    cwd: record.cwd,
    exit_status: record.exit_status,
    signal: record.signal,
    timeout_ms: record.timeout_ms,
    max_buffer_bytes: record.max_buffer_bytes,
    duration_ms: record.duration_ms,
    stdout_byte_length: record.stdout.length,
    stdout_sha256: sha256(record.stdout),
    stdout_base64: record.stdout.toString("base64"),
    stderr_byte_length: record.stderr.length,
    stderr_sha256: sha256(record.stderr),
    stderr_base64: record.stderr.toString("base64"),
  });
}

function assertCommandStatus(record, expected, reasonCode, label) {
  assert(record.exit_status === expected && record.signal === null, reasonCode, `${label} status drift`);
}

function createMaterialization(runRoot, frozen) {
  const materialization = createExclusiveDirectory(join(runRoot.path, "materialization"));
  const home = createExclusiveDirectory(join(runRoot.path, "home"));
  const src = createExclusiveDirectory(join(materialization.path, "src"));
  const test = createExclusiveDirectory(join(materialization.path, "test"));
  createExclusiveFile(join(src.path, "range.mjs"), frozen.source.bytes, { mode: 0o644, prefix: "MATERIALIZED_SOURCE" });
  createExclusiveFile(join(test.path, "issue.test.mjs"), frozen.issueTest.bytes, { mode: 0o644, prefix: "MATERIALIZED_SOURCE" });
  createExclusiveFile(join(test.path, "regression.test.mjs"), frozen.regressionTest.bytes, { mode: 0o644, prefix: "MATERIALIZED_SOURCE" });
  const environment = deterministicEnvironment(home.path);
  const commands = [
    executeCommand(GIT, ["init", "--quiet", "--template=", "--object-format=sha1"], materialization.path, environment),
    executeCommand(GIT, ["add", "--all"], materialization.path, environment),
    executeCommand(GIT, ["-c", "commit.gpgsign=false", "commit", "--quiet", "--no-verify", "--no-gpg-sign", "-m", frozen.recipe.commit_message], materialization.path, environment),
  ];
  for (const [index, command] of commands.entries()) assertCommandStatus(command, 0, "MATERIALIZATION_REJECTED", `materialization command ${index}`);
  return Object.freeze({ materialization, home, environment });
}

function gitIdentity(materialized) {
  const head = executeCommand(GIT, ["rev-parse", "HEAD"], materialized.materialization.path, materialized.environment);
  const tree = executeCommand(GIT, ["rev-parse", "HEAD^{tree}"], materialized.materialization.path, materialized.environment);
  const status = executeCommand(GIT, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materialized.materialization.path, materialized.environment);
  assertCommandStatus(head, 0, "BASE_IDENTITY_REJECTED", "git head");
  assertCommandStatus(tree, 0, "BASE_IDENTITY_REJECTED", "git tree");
  assertCommandStatus(status, 0, "BASE_IDENTITY_REJECTED", "git status");
  return Object.freeze({
    head: head.stdout.toString("utf8").trim(),
    tree: tree.stdout.toString("utf8").trim(),
    status: status.stdout,
  });
}

function atomicReplace(targetPath, expectedCurrent, replacementBytes) {
  const current = secureRead(targetPath, { prefix: "TARGET", expected: expectedCurrent });
  assert((current.stat.mode & 0o777) === 0o644, "TARGET_MODE_REJECTED", "target mode drift");
  const sidecarPath = join(dirname(targetPath), `.${basename(targetPath)}.p1-063-${randomBytes(12).toString("hex")}`);
  let sidecar;
  try {
    sidecar = createExclusiveFile(sidecarPath, replacementBytes, { mode: 0o644, prefix: "SIDECAR" });
    const rechecked = secureRead(targetPath, { prefix: "TARGET", expected: expectedCurrent });
    assert(rechecked.stat.dev === current.stat.dev && rechecked.stat.ino === current.stat.ino, "TARGET_IDENTITY_DRIFT_REJECTED", "target changed before replacement");
    verifyFileReceipt(sidecar, "SIDECAR");
    renameSync(sidecarPath, targetPath);
    const replaced = secureRead(targetPath, { prefix: "TARGET", expected: identityOf(replacementBytes) });
    assert((replaced.stat.mode & 0o777) === 0o644, "TARGET_MODE_REJECTED", "replacement mode drift");
    return replaced;
  } catch (error) {
    if (sidecar) {
      try {
        verifyFileReceipt(sidecar, "SIDECAR");
        unlinkSync(sidecar.path);
      } catch {
        // Preserve the primary failure when the sidecar can no longer be proven owned.
      }
    }
    throw error;
  }
}

function changedPaths(materialized) {
  const status = executeCommand(GIT, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materialized.materialization.path, materialized.environment);
  assertCommandStatus(status, 0, "CHANGED_PATH_REJECTED", "changed path query");
  const fields = status.stdout.toString("utf8").split("\0").filter(Boolean);
  const paths = [];
  for (let index = 0; index < fields.length; index += 1) {
    const entry = fields[index];
    assert(entry.length >= 4, "CHANGED_PATH_REJECTED", "malformed porcelain entry");
    const code = entry.slice(0, 2);
    paths.push(entry.slice(3));
    if (code.includes("R") || code.includes("C")) index += 1;
  }
  return paths.sort();
}

function loadFrozenInputs() {
  const taskCard = loadQualityJson(QUALITY_IDENTITIES.task_card, "TASK_CARD");
  const taskCardSchema = loadQualityJson(QUALITY_IDENTITIES.task_card_schema, "TASK_CARD_SCHEMA");
  const submission = loadQualityJson(QUALITY_IDENTITIES.offline_submission, "OFFLINE_SUBMISSION");
  const submissionSchema = loadQualityJson(QUALITY_IDENTITIES.offline_submission_schema, "OFFLINE_SUBMISSION_SCHEMA");
  const expectedResults = loadQualityJson(QUALITY_IDENTITIES.expected_results, "EXPECTED_RESULTS");
  const negativeCases = loadQualityJson(QUALITY_IDENTITIES.negative_cases, "NEGATIVE_CASES");
  const golden = loadQualityJson(QUALITY_IDENTITIES.golden, "GOLDEN");
  assert(taskCardSchema.value.type === "object" && taskCardSchema.value.additionalProperties === false, "FROZEN_INPUT_REJECTED", "Task Card schema is not closed");
  assert(submissionSchema.value.type === "object" && submissionSchema.value.additionalProperties === false, "FROZEN_INPUT_REJECTED", "submission schema is not closed");

  const accepted = {};
  for (const [name, declaration] of Object.entries(taskCard.value.accepted_inputs)) {
    accepted[name] = secureRead(repositoryPath(declaration.path), { prefix: "ACCEPTED_INPUT", expected: declaration });
  }
  const compiler = secureRead(repositoryPath(taskCard.value.accepted_substrate.compiler.path), {
    prefix: "ACCEPTED_COMPILER",
    expected: taskCard.value.accepted_substrate.compiler,
  });
  const independentOracle = secureRead(repositoryPath(taskCard.value.accepted_substrate.independent_oracle.path), {
    prefix: "ACCEPTED_ORACLE",
    expected: taskCard.value.accepted_substrate.independent_oracle,
  });
  const proposal = secureRead(repositoryPath(taskCard.value.accepted_substrate.success_program.path), {
    prefix: "FINITE_IR_PROGRAM",
    expected: taskCard.value.accepted_substrate.success_program,
  });
  const taskSpec = JSON.parse(accepted.task_spec.bytes.toString("utf8"));
  const expectedBaseFailure = JSON.parse(accepted.expected_base_failure.bytes.toString("utf8"));
  const recipe = JSON.parse(accepted.materialization_recipe.bytes.toString("utf8"));
  assert(taskSpec.task_id === CONTROL_ID && taskSpec.dataset_version === "1.0.0", "FROZEN_INPUT_REJECTED", "TaskSpec binding drift");
  assert(taskSpec.repository.base_commit === submission.value.base_commit && taskSpec.repository.tree_hash === submission.value.base_tree, "FROZEN_INPUT_REJECTED", "TaskSpec source binding drift");
  assert(expectedBaseFailure.expected_exit_status === 1 && recipe.hash_algorithm === "sha1", "FROZEN_INPUT_REJECTED", "base failure or recipe drift");
  validateOfflineSubmission(submission.value, submission.value);
  validateExecutable(NODE, "Node");
  validateExecutable(GIT, "Git");
  return Object.freeze({
    taskCard,
    submission,
    expectedResults,
    negativeCases,
    golden,
    taskSpec,
    taskSpecFile: accepted.task_spec,
    expectedBaseFailure,
    recipe,
    source: accepted.source_preimage,
    issueTest: accepted.issue_test,
    regressionTest: accepted.regression_test,
    compiler,
    independentOracle,
    proposal,
  });
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function expectReason(expectedReason, action) {
  try {
    action();
  } catch (error) {
    const reason = error instanceof RunnerError || error instanceof OfflineAdapterError
      ? error.reasonCode
      : undefined;
    assert(reason === expectedReason, "NEGATIVE_REASON_DRIFT", `expected ${expectedReason}, got ${reason ?? error.message}`);
    return Object.freeze({ reason_code: reason, accepted: false });
  }
  reject("NEGATIVE_FALSE_ACCEPT", `expected ${expectedReason}`);
}

function assertCandidateBinding(actual, expected) {
  assert(actual?.candidate_commit === expected.candidate_commit, "CANDIDATE_BINDING_REJECTED", "candidate commit drift");
  assert(actual?.candidate_tree === expected.candidate_tree, "CANDIDATE_BINDING_REJECTED", "candidate tree drift");
  assert(actual?.candidate_manifest_sha256 === expected.candidate_manifest_sha256, "CANDIDATE_BINDING_REJECTED", "candidate manifest drift");
  assert(actual?.quality_freeze_manifest_sha256 === expected.quality_freeze_manifest_sha256, "CANDIDATE_BINDING_REJECTED", "Quality binding drift");
}

function assertArtifactContained(runRoot, artifactPath) {
  const absolute = resolve(runRoot, artifactPath);
  const rel = relative(runRoot, absolute);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), "CROSS_RUN_SUBSTITUTION_REJECTED", "artifact escaped its run");
}

function assertEvidencePopulation(entries) {
  const expected = REQUIRED_ARTIFACTS.map((entry) => entry.id).sort();
  const actual = entries.map((entry) => entry.id).sort();
  assert(JSON.stringify(actual) === JSON.stringify(expected), "EVIDENCE_POPULATION_REJECTED", "Evidence population drift");
}

function assertRollbackComplete(rollback) {
  assert(rollback?.status === "PASS" && rollback.git_status_porcelain === "", "ROLLBACK_OMISSION_REJECTED", "rollback missing");
}

function assertCompleteActions(actions) {
  assert(sameValue(actions, REQUIRED_ACTIONS), "ACTION_SCHEDULE_REJECTED", "action schedule incomplete");
}

function overwriteOwnedFile(path, bytes) {
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_WRONLY | fsConstants.O_TRUNC | O_NOFOLLOW);
    writeAll(descriptor, bytes);
    fsyncSync(descriptor);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function cleanupOwnedTemporary(rootReceipt, markerReceipt) {
  verifyDirectory(rootReceipt);
  verifyFileReceipt(markerReceipt, "OWNER_MARKER");
  rmSync(rootReceipt.path, { recursive: true, force: false });
}

function runNegativeControls(frozen, candidateBinding) {
  const negativeRootPath = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-063-negative-"));
  const negativeRoot = directoryIdentity(negativeRootPath);
  const marker = createExclusiveFile(
    join(negativeRoot.path, ".owner.json"),
    canonicalJsonBytes({ task_id: TASK_ID, token: randomBytes(24).toString("hex") }),
    { prefix: "OWNER_MARKER" },
  );
  const submission = frozen.submission.value;
  const mutate = (action) => {
    const value = cloneJson(submission);
    action(value);
    return value;
  };
  const irUnknown = Buffer.from(frozen.proposal.bytes);
  irUnknown[2] ^= 1;
  const irUnsupported = Buffer.from(frozen.proposal.bytes);
  const opOffset = irUnsupported.indexOf(Buffer.from("REBIND_OBJECT_FIELDS", "utf8"));
  assert(opOffset >= 0, "FROZEN_INPUT_REJECTED", "IR operation token missing");
  irUnsupported[opOffset] = 0x58;
  const expectedCandidate = candidateBinding;
  const wrongCandidate = { ...candidateBinding, candidate_tree: "f".repeat(40) };
  const results = [];
  const exercise = new Map();

  exercise.set("unknown-submission-member", () => validateOfflineSubmission(mutate((value) => { value.extra = true; }), submission));
  exercise.set("unknown-proposal-member", () => validateOfflineSubmission(mutate((value) => { value.proposal.extra = true; }), submission));
  exercise.set("wrong-submission-type", () => validateOfflineSubmission(mutate((value) => { value.schema_version = 2; }), submission));
  exercise.set("task-binding-mismatch", () => validateOfflineSubmission(mutate((value) => { value.task_id = "wrong"; }), submission));
  exercise.set("base-commit-mismatch", () => validateOfflineSubmission(mutate((value) => { value.base_commit = "0".repeat(40); }), submission));
  exercise.set("base-tree-mismatch", () => validateOfflineSubmission(mutate((value) => { value.base_tree = "0".repeat(40); }), submission));
  exercise.set("target-binding-mismatch", () => validateOfflineSubmission(mutate((value) => { value.target_id = "wrong"; }), submission));
  exercise.set("candidate-or-freeze-binding-mismatch", () => assertCandidateBinding(wrongCandidate, expectedCandidate));
  exercise.set("proposal-hash-mismatch", () => validateOfflineSubmission(mutate((value) => { value.proposal.sha256 = "0".repeat(64); }), submission));
  exercise.set("proposal-length-mismatch", () => validateOfflineSubmission(mutate((value) => { value.proposal.byte_length = 254; }), submission));
  exercise.set("proposal-path-escape", () => validateOfflineSubmission(mutate((value) => { value.proposal.path = "../escape"; }), submission));
  exercise.set("proposal-path-alias-or-absolute", () => validateOfflineSubmission(mutate((value) => { value.proposal.path = "/tmp/alias"; }), submission));
  exercise.set("raw-ir-unknown-member", () => admitOfflineB0Result(submission, submission, irUnknown));
  exercise.set("raw-ir-unsupported-op", () => admitOfflineB0Result(submission, submission, irUnsupported));
  exercise.set("declared-program-cross-substitution", () => validateOfflineSubmission(mutate((value) => { value.proposal.program_id = "IR00"; }), submission));
  exercise.set("rollback-omission", () => assertRollbackComplete({ status: "MISSING", git_status_porcelain: "" }));
  exercise.set("missing-required-action", () => assertCompleteActions(REQUIRED_ACTIONS.slice(0, -1)));
  exercise.set("network-capable-import-or-api-surface", () => {
    const synthetic = Buffer.from(["im", "port { request } from \"node:", "http\";\n"].join(""), "utf8");
    scanWorkerSource("negative.mjs", synthetic, []);
  });

  const directoryFile = join(negativeRoot.path, "proposal-directory");
  createExclusiveDirectory(directoryFile);
  exercise.set("proposal-directory-instead-of-file", () => secureRead(directoryFile, { prefix: "FILE" }));
  const symlinkTarget = createExclusiveFile(join(negativeRoot.path, "symlink-target"), Buffer.from("target\n"), { prefix: "FIXTURE" });
  const proposalSymlink = join(negativeRoot.path, "proposal-symlink");
  symlinkSync(symlinkTarget.path, proposalSymlink);
  exercise.set("proposal-symlink", () => secureRead(proposalSymlink, { prefix: "FILE" }));
  const hardlinkSource = createExclusiveFile(join(negativeRoot.path, "hardlink-source"), Buffer.from("hardlink\n"), { prefix: "FIXTURE" });
  const hardlinkPeer = join(negativeRoot.path, "hardlink-peer");
  linkSync(hardlinkSource.path, hardlinkPeer);
  exercise.set("proposal-hardlink-nlink-drift", () => secureRead(hardlinkSource.path, { prefix: "FILE" }));

  const preexistingDirectory = join(negativeRoot.path, "preexisting-run");
  createExclusiveDirectory(preexistingDirectory);
  exercise.set("preexisting-run-directory", () => createExclusiveDirectory(preexistingDirectory));
  const symlinkDirectoryTarget = createExclusiveDirectory(join(negativeRoot.path, "symlink-directory-target"));
  const symlinkDirectory = join(negativeRoot.path, "symlink-run");
  symlinkSync(symlinkDirectoryTarget.path, symlinkDirectory);
  exercise.set("symlink-run-directory", () => createExclusiveDirectory(symlinkDirectory));
  const substitutedPath = join(negativeRoot.path, "substituted-run");
  const substitutedReceipt = createExclusiveDirectory(substitutedPath);
  renameSync(substitutedPath, `${substitutedPath}-old`);
  createExclusiveDirectory(substitutedPath);
  exercise.set("run-directory-identity-substitution", () => verifyDirectory(substitutedReceipt));
  exercise.set("cross-run-artifact-substitution", () => assertArtifactContained(join(negativeRoot.path, "run-a"), "../run-b/artifact.json"));

  const evidenceTarget = createExclusiveFile(join(negativeRoot.path, "evidence-target"), Buffer.from("evidence\n"), { prefix: "FIXTURE" });
  const evidenceSymlink = join(negativeRoot.path, "evidence-symlink");
  symlinkSync(evidenceTarget.path, evidenceSymlink);
  exercise.set("evidence-leaf-symlink", () => secureRead(evidenceSymlink, { prefix: "EVIDENCE" }));
  const evidenceTamper = createExclusiveFile(join(negativeRoot.path, "evidence-tamper"), Buffer.from("before\n"), { prefix: "EVIDENCE" });
  overwriteOwnedFile(evidenceTamper.path, Buffer.from("after!\n"));
  exercise.set("evidence-leaf-byte-tamper", () => verifyFileReceipt(evidenceTamper, "EVIDENCE"));
  exercise.set("evidence-population-or-manifest-tamper", () => assertEvidencePopulation(REQUIRED_ARTIFACTS.slice(0, -1)));

  try {
    for (const specification of frozen.negativeCases.value.cases) {
      const action = exercise.get(specification.id);
      assert(typeof action === "function", "NEGATIVE_MATRIX_REJECTED", `missing exercise ${specification.id}`);
      const outcome = expectReason(specification.expected_reason_code, action);
      results.push(Object.freeze({
        id: specification.id,
        reason_code: outcome.reason_code,
        validation_mutation_attempt_delta: 0,
        validation_child_start_attempt_delta: 0,
        canary_status: "UNCHANGED",
        external_effects: FALSE_EFFECTS,
      }));
    }
    assert(results.length === 28, "NEGATIVE_MATRIX_REJECTED", "negative population drift");
    return Object.freeze({
      scheduled: 28,
      rejections: results.length,
      false_accepts: 0,
      results: Object.freeze(results),
    });
  } finally {
    cleanupOwnedTemporary(negativeRoot, marker);
  }
}

function ensureRunsRoot(evidenceRoot) {
  const root = directoryIdentity(evidenceRoot, "EVIDENCE_ROOT");
  const runsPath = join(root.path, "runs");
  try {
    return directoryIdentity(runsPath, "RUNS_ROOT");
  } catch (error) {
    if (!(error instanceof RunnerError) || error.reasonCode !== "RUNS_ROOT_MISSING") throw error;
  }
  try {
    return createExclusiveDirectory(runsPath);
  } catch (error) {
    if (error instanceof RunnerError && error.reasonCode === "PREEXISTING_DIRECTORY_REJECTED") {
      return directoryIdentity(runsPath, "RUNS_ROOT");
    }
    throw error;
  }
}

function allocateRunRoot(evidenceRoot, runId) {
  assert(RUN_ID_PATTERN.test(runId), "RUN_ID_REJECTED", "unsafe run id");
  const runs = ensureRunsRoot(evidenceRoot);
  const runPath = join(runs.path, runId);
  assert(dirname(runPath) === runs.path && basename(runPath) === runId, "RUN_ID_REJECTED", "run path drift");
  return createExclusiveDirectory(runPath);
}

function runTest(actionId, materialized, relativeTest, expectedStatus) {
  const command = executeCommand(
    NODE,
    ["--test", relativeTest],
    materialized.materialization.path,
    materialized.environment,
  );
  assertCommandStatus(command, expectedStatus, "TEST_STATUS_REJECTED", actionId);
  return Object.freeze({ record: command, evidence: commandEvidence(actionId, command) });
}

function validateTypedBaseFailure(command, expected) {
  const combined = Buffer.concat([command.stdout, command.stderr]).toString("utf8");
  for (const token of expected.required_output_tokens) {
    assert(combined.includes(token), "BASE_FAILURE_REJECTED", `base failure missing ${token}`);
  }
  for (const token of expected.forbidden_output_tokens) {
    assert(!combined.includes(token), "BASE_FAILURE_REJECTED", `base failure contains ${token}`);
  }
}

function rollbackMaterialization(materialized, frozen, targetPath, currentPostimageIdentity) {
  atomicReplace(targetPath, currentPostimageIdentity, frozen.source.bytes);
  const status = executeCommand(GIT, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materialized.materialization.path, materialized.environment);
  const head = executeCommand(GIT, ["rev-parse", "HEAD"], materialized.materialization.path, materialized.environment);
  const tree = executeCommand(GIT, ["rev-parse", "HEAD^{tree}"], materialized.materialization.path, materialized.environment);
  assertCommandStatus(status, 0, "ROLLBACK_OMISSION_REJECTED", "rollback status");
  assertCommandStatus(head, 0, "ROLLBACK_OMISSION_REJECTED", "rollback head");
  assertCommandStatus(tree, 0, "ROLLBACK_OMISSION_REJECTED", "rollback tree");
  const source = secureRead(targetPath, { prefix: "ROLLBACK_SOURCE", expected: frozen.source });
  const headValue = head.stdout.toString("utf8").trim();
  const treeValue = tree.stdout.toString("utf8").trim();
  assert(status.stdout.length === 0, "ROLLBACK_OMISSION_REJECTED", "rollback worktree remains dirty");
  assert(headValue === frozen.submission.value.base_commit, "ROLLBACK_OMISSION_REJECTED", "rollback commit drift");
  assert(treeValue === frozen.submission.value.base_tree, "ROLLBACK_OMISSION_REJECTED", "rollback tree drift");
  return Object.freeze({
    value: Object.freeze({
      schema_version: 1,
      record_type: "sourcelens_aios_p1_063_rollback",
      task_id: TASK_ID,
      control_id: CONTROL_ID,
      status: "PASS",
      source_byte_length: source.byte_length,
      source_sha256: source.sha256,
      base_commit: headValue,
      base_tree: treeValue,
      git_status_porcelain: "",
    }),
    commands: Object.freeze([
      commandEvidence("rollback_status", status),
      commandEvidence("rollback_head", head),
      commandEvidence("rollback_tree", tree),
    ]),
  });
}

function filledGolden(golden, candidateBinding) {
  const replacements = new Map([
    ["$CANDIDATE_COMMIT", candidateBinding.candidate_commit],
    ["$CANDIDATE_TREE", candidateBinding.candidate_tree],
    ["$CANDIDATE_MANIFEST_SHA256", candidateBinding.candidate_manifest_sha256],
    ["$QUALITY_FREEZE_MANIFEST_SHA256", candidateBinding.quality_freeze_manifest_sha256],
  ]);
  const replace = (value) => {
    if (Array.isArray(value)) return value.map(replace);
    if (value && typeof value === "object") {
      return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, replace(child)]));
    }
    return replacements.get(value) ?? value;
  };
  return replace(golden);
}

function normalizedCommands(rawCommands) {
  return rawCommands.map((record) => Object.freeze({
    action_id: record.action_id,
    argv: record.argv,
    exit_status: record.exit_status,
    signal: record.signal,
  }));
}

function buildStableProjection(frozen, candidateBinding, admission, rawCommands, rollback, negativeControls) {
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_063_stable_projection",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    adapter_id: ADAPTER_ID,
    adapter_version: ADAPTER_VERSION,
    execution_mode: "OFFLINE_FROZEN_SUBMISSION",
    candidate_binding: candidateBinding,
    accepted_input_identities: {
      task_spec: { path: frozen.taskCard.value.accepted_inputs.task_spec.path, byte_length: frozen.taskSpecFile.byte_length, sha256: frozen.taskSpecFile.sha256 },
      source_preimage: { path: frozen.taskCard.value.accepted_inputs.source_preimage.path, byte_length: frozen.source.byte_length, sha256: frozen.source.sha256 },
      issue_test: { path: frozen.taskCard.value.accepted_inputs.issue_test.path, byte_length: frozen.issueTest.byte_length, sha256: frozen.issueTest.sha256 },
      regression_test: { path: frozen.taskCard.value.accepted_inputs.regression_test.path, byte_length: frozen.regressionTest.byte_length, sha256: frozen.regressionTest.sha256 },
      compiler: {
        path: frozen.taskCard.value.accepted_substrate.compiler.path,
        version: frozen.taskCard.value.accepted_substrate.compiler.version,
        byte_length: frozen.compiler.byte_length,
        sha256: frozen.compiler.sha256,
      },
      program: {
        path: frozen.taskCard.value.accepted_substrate.success_program.path,
        program_id: frozen.taskCard.value.accepted_substrate.success_program.program_id,
        byte_length: frozen.proposal.byte_length,
        sha256: frozen.proposal.sha256,
      },
    },
    closed_ir: {
      schema: "SL-PATCH-IR/1",
      admission: "RAW_BUFFER_MAX_255_SHA256_LENGTH_AND_EXACT_BYTES_EQUALITY_ONLY",
      decode_or_parse: false,
      program_count: 4,
      only_success_program_id: "IR10",
      byte_closure_total: 263168,
      byte_closure_false_accepts: 0,
      byte_closure_stream_sha256: "a819e42a5f5ecca01daa3f77f0701f5dac80b8ff7f096c8bac8d627f30d8a38b",
    },
    submission: {
      result_id: frozen.submission.value.result_id,
      program_id: frozen.submission.value.proposal.program_id,
      proposal_byte_length: admission.proposal_byte_length,
      proposal_sha256: admission.proposal_sha256,
    },
    compiler_result: {
      status: admission.status,
      admission: admission.admission,
      program_id: admission.program_id,
      outcome_id: admission.outcome_id,
      outcome_kind: admission.outcome_kind,
      postimage_byte_length: admission.postimage.length,
      postimage_sha256: sha256(admission.postimage),
    },
    ordered_action_ids: [...REQUIRED_ACTIONS],
    commands_normalized: normalizedCommands(rawCommands),
    command_stream_policy: {
      normalization_transform_id: "EXACT_MATERIALIZATION_ROOT_TO_PLACEHOLDER_AND_TAP_DURATION_MS_NUMERIC_VALUE_TO_PLACEHOLDER_ONLY",
      raw_stdout_stderr_retained_and_hash_bound: true,
      residual_physical_variants: 0,
    },
    base_test_statuses: { issue: 1, regression: 0, typed_failure: "PASS" },
    changed_paths_sorted: ["src/range.mjs"],
    patched_test_statuses: { issue: 0, regression: 0 },
    rollback: {
      status: rollback.status,
      source_byte_length: rollback.source_byte_length,
      source_sha256: rollback.source_sha256,
      base_commit: rollback.base_commit,
      base_tree: rollback.base_tree,
      git_status_porcelain: rollback.git_status_porcelain,
    },
    run_record_schema_status: "PASS",
    filesystem_policy_status: "PASS",
    network_surface_status: "PASS",
    negative_control_contract: {
      scheduled: negativeControls.scheduled,
      required_rejections: negativeControls.rejections,
      maximum_false_accepts: negativeControls.false_accepts,
    },
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
    compatibility_boundary: {
      harness_compatible_run_record: true,
      task_spec_response_format_adapter_acceptance: false,
      full_b0_adapter_acceptance: false,
      vtsr_inclusion: false,
    },
    verdict: "PASS_ONLY_SUCCESS",
    claim_boundary: CLAIM_BOUNDARY,
  };
}

function artifactEntry(id, relativePath, receipt) {
  return Object.freeze({
    id,
    path: relativePath,
    byte_length: receipt.byte_length,
    sha256: receipt.sha256,
  });
}

function writeArtifact(runRoot, id, value) {
  const specification = REQUIRED_ARTIFACTS.find((entry) => entry.id === id);
  assert(specification, "EVIDENCE_POPULATION_REJECTED", `unknown artifact ${id}`);
  assertArtifactContained(runRoot.path, specification.path);
  const receipt = createExclusiveFile(
    containedPath(runRoot.path, specification.path, "CROSS_RUN_SUBSTITUTION_REJECTED"),
    canonicalJsonBytes(value),
    { prefix: "EVIDENCE" },
  );
  return Object.freeze({ receipt, entry: artifactEntry(id, specification.path, receipt) });
}

function compilerObservation(admission) {
  return Object.freeze({
    status: admission.status,
    admission: admission.admission,
    program_id: admission.program_id,
    outcome_id: admission.outcome_id,
    outcome_kind: admission.outcome_kind,
    postimage_byte_length: admission.postimage.length,
    postimage_sha256: sha256(admission.postimage),
  });
}

function buildRunRecord(runId, startedAt, endedAt, artifactReceipts) {
  return {
    schema_version: "1.0",
    run_id: runId,
    task_id: CONTROL_ID,
    dataset_version: "1.0.0",
    adapter_id: ADAPTER_ID,
    adapter_version: ADAPTER_VERSION,
    environment_snapshot_id: "P1-063-OFFLINE-COOPERATIVE-LOCAL-1",
    system_configuration_id: "P1-063-OFFLINE-FINITE-IR-B0-1",
    repetition_id: 1,
    started_at: startedAt,
    ended_at: endedAt,
    terminal_status: "completed",
    stop_reason_code: "agent_complete",
    invalid_run_reason: null,
    error_taxonomy: [],
    trace_ref: "commands.json",
    patch_ref: "observation.json",
    test_artifact_refs: ["commands.json"],
    verification_ref: "quality-evaluator://AIOS-P1-063/1.0.0",
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      tool_calls: 7,
      retries: 0,
      human_interventions: 0,
      cost_usd: 0,
      latency_ms: Math.max(0, Date.parse(endedAt) - Date.parse(startedAt)),
    },
    policy_violations: [],
    artifact_checksums: Object.fromEntries(
      artifactReceipts.map(({ entry }) => [entry.path, entry.sha256]),
    ),
  };
}

function emitRunManifest(runRoot, runId, candidateBinding, artifacts) {
  assertEvidencePopulation(artifacts);
  const sorted = [...artifacts].sort((left, right) => left.path.localeCompare(right.path));
  const value = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_063_run_manifest",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    candidate_binding: candidateBinding,
    run_root: runRoot.path,
    artifacts,
    evidence_files_sorted: sorted,
  };
  const receipt = createExclusiveFile(
    join(runRoot.path, "run-manifest.json"),
    canonicalJsonBytes(value),
    { prefix: "RUN_MANIFEST" },
  );
  return Object.freeze({ value, receipt });
}

function performRun({ qualityFreeze, candidateBinding, evidenceRoot, runId }) {
  const actions = [];
  const rawCommands = [];
  const startedAt = new Date().toISOString();
  let materialized;
  let targetPath;
  let postimageIdentity;
  let rollback;

  assertCandidateBinding(candidateBinding, candidateBinding);
  assert(candidateBinding.quality_freeze_manifest_sha256 === qualityFreeze.manifestFile.sha256, "CANDIDATE_BINDING_REJECTED", "Quality binding drift");
  completeAction(actions, "validate_candidate_and_quality_identities");

  workerFileRecords();
  completeAction(actions, "validate_worker_import_surface");

  const frozen = loadFrozenInputs();
  completeAction(actions, "validate_frozen_inputs");

  validateOfflineSubmission(frozen.submission.value, frozen.submission.value);
  const negativeControls = runNegativeControls(frozen, candidateBinding);
  completeAction(actions, "validate_offline_submission");

  const runRoot = allocateRunRoot(evidenceRoot, runId);
  try {
    materialized = createMaterialization(runRoot, frozen);
    const canary = createExclusiveFile(
      join(materialized.home.path, ".p1-063-canary.json"),
      canonicalJsonBytes({ task_id: TASK_ID, run_id: runId, token: randomBytes(24).toString("hex") }),
      { prefix: "CANARY" },
    );
    completeAction(actions, "materialize_fresh_rep001_repository");

    const baseIdentity = gitIdentity(materialized);
    assert(baseIdentity.head === frozen.submission.value.base_commit, "BASE_IDENTITY_REJECTED", "base commit drift");
    assert(baseIdentity.tree === frozen.submission.value.base_tree, "BASE_IDENTITY_REJECTED", "base tree drift");
    assert(baseIdentity.status.length === 0, "BASE_IDENTITY_REJECTED", "base worktree is dirty");
    completeAction(actions, "verify_base_commit_tree_and_clean_state");

    const baseIssue = runTest("base_issue_test", materialized, "test/issue.test.mjs", 1);
    rawCommands.push(baseIssue.evidence);
    completeAction(actions, "run_base_issue_test");

    validateTypedBaseFailure(baseIssue.record, frozen.expectedBaseFailure);
    completeAction(actions, "validate_typed_base_failure");

    const baseRegression = runTest("base_regression_test", materialized, "test/regression.test.mjs", 0);
    rawCommands.push(baseRegression.evidence);
    completeAction(actions, "run_base_regression_test");

    const admission = admitOfflineB0Result(frozen.submission.value, frozen.submission.value, frozen.proposal.bytes);
    assert(admission.postimage && admission.status === "COMPILED", "IR_NOT_EXACTLY_ADMITTED", "IR10 did not compile to a postimage");
    completeAction(actions, "admit_exact_ir10_without_decode_or_parse");

    targetPath = join(materialized.materialization.path, "src/range.mjs");
    const replaced = atomicReplace(targetPath, frozen.source, admission.postimage);
    postimageIdentity = Object.freeze({ byte_length: replaced.byte_length, sha256: replaced.sha256 });
    completeAction(actions, "atomically_replace_target");

    const paths = changedPaths(materialized);
    assert(sameValue(paths, ["src/range.mjs"]), "CHANGED_PATH_REJECTED", "patch changed a path outside src/range.mjs");
    completeAction(actions, "verify_exact_changed_path");

    const patchedIssue = runTest("patched_issue_test", materialized, "test/issue.test.mjs", 0);
    rawCommands.push(patchedIssue.evidence);
    completeAction(actions, "run_patched_issue_test");

    const patchedRegression = runTest("patched_regression_test", materialized, "test/regression.test.mjs", 0);
    rawCommands.push(patchedRegression.evidence);
    completeAction(actions, "run_patched_regression_test");

    atomicReplace(targetPath, postimageIdentity, frozen.source.bytes);
    completeAction(actions, "restore_exact_base");

    rollback = rollbackMaterialization(materialized, frozen, targetPath, frozen.source);
    rawCommands.push(...rollback.commands);
    completeAction(actions, "verify_exact_rollback");

    verifyFileReceipt(canary, "CANARY");
    const observation = {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_063_observation",
      task_id: TASK_ID,
      control_id: CONTROL_ID,
      run_id: runId,
      candidate_binding: candidateBinding,
      compiler_result: compilerObservation(admission),
      base_test_statuses: { issue: 1, regression: 0, typed_failure: "PASS" },
      changed_paths_sorted: paths,
      patched_test_statuses: { issue: 0, regression: 0 },
      negative_controls: negativeControls,
      canary_status: "UNCHANGED",
      external_effects: FALSE_EFFECTS,
      ordered_action_ids: [...REQUIRED_ACTIONS],
    };
    const commands = {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_063_raw_commands",
      task_id: TASK_ID,
      control_id: CONTROL_ID,
      run_id: runId,
      commands: rawCommands,
    };
    const emitted = [
      writeArtifact(runRoot, "commands", commands),
      writeArtifact(runRoot, "observation", observation),
      writeArtifact(runRoot, "rollback", rollback.value),
    ];
    const endedAt = new Date().toISOString();
    const runRecord = buildRunRecord(runId, startedAt, endedAt, emitted);
    emitted.push(writeArtifact(runRoot, "run_record", runRecord));
    completeAction(actions, "emit_create_once_raw_evidence");

    const stableProjection = buildStableProjection(
      frozen,
      candidateBinding,
      admission,
      rawCommands,
      rollback.value,
      negativeControls,
    );
    const expectedProjection = filledGolden(frozen.golden.value, candidateBinding);
    assert(sameValue(stableProjection, expectedProjection), "STABLE_PROJECTION_MISMATCH", "stable projection differs from frozen golden");
    emitted.push(writeArtifact(runRoot, "stable_projection", stableProjection));
    completeAction(actions, "emit_stable_projection");
    assertCompleteActions(actions);
    assert(emitted.length === 5, "EVIDENCE_POPULATION_REJECTED", "artifact count drift");
    for (const artifact of emitted) verifyFileReceipt(artifact.receipt, "EVIDENCE");
    verifyDirectory(runRoot);
    verifyFileReceipt(canary, "CANARY");

    const runManifest = emitRunManifest(runRoot, runId, candidateBinding, emitted.map(({ entry }) => entry));
    verifyFileReceipt(runManifest.receipt, "RUN_MANIFEST");
    return Object.freeze({
      run_root: runRoot,
      run_manifest: runManifest,
      stable_projection: emitted.find(({ entry }) => entry.id === "stable_projection"),
      negative_controls: negativeControls,
    });
  } catch (error) {
    if (materialized && targetPath && postimageIdentity && !rollback) {
      try {
        const current = secureRead(targetPath, { prefix: "TARGET_RECOVERY", requireNlinkOne: true });
        if (current.sha256 === postimageIdentity.sha256 && current.byte_length === postimageIdentity.byte_length) {
          atomicReplace(targetPath, postimageIdentity, frozen.source.bytes);
        }
      } catch {
        // Preserve the primary failure; the task-owned run root remains for forensic review.
      }
    }
    throw error;
  }
}

function selfTest() {
  const qualityFreeze = parseQualityFreeze();
  const rootPath = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-063-self-test-"));
  const root = directoryIdentity(rootPath, "SELF_TEST_ROOT");
  const marker = createExclusiveFile(
    join(root.path, ".owner.json"),
    canonicalJsonBytes({ task_id: TASK_ID, token: randomBytes(24).toString("hex") }),
    { prefix: "OWNER_MARKER" },
  );
  const candidateBinding = Object.freeze({
    candidate_commit: "1".repeat(40),
    candidate_tree: "2".repeat(40),
    candidate_manifest_sha256: "3".repeat(64),
    quality_freeze_manifest_sha256: qualityFreeze.manifestFile.sha256,
  });
  try {
    const first = performRun({ qualityFreeze, candidateBinding, evidenceRoot: root.path, runId: "self-test-a" });
    const second = performRun({ qualityFreeze, candidateBinding, evidenceRoot: root.path, runId: "self-test-b" });
    const firstStable = verifyFileReceipt(first.stable_projection.receipt, "EVIDENCE");
    const secondStable = verifyFileReceipt(second.stable_projection.receipt, "EVIDENCE");
    assert(
      firstStable.byte_length === secondStable.byte_length && firstStable.sha256 === secondStable.sha256,
      "STABLE_PROJECTION_MISMATCH",
      "dual self-test projections differ",
    );
    return {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_063_worker_self_test",
      runner_version: RUNNER_VERSION,
      task_id: TASK_ID,
      runs: 2,
      negative_cases_per_run: first.negative_controls.scheduled,
      negative_rejections_per_run: first.negative_controls.rejections,
      negative_false_accepts_per_run: first.negative_controls.false_accepts,
      stable_projection_byte_length: firstStable.byte_length,
      stable_projection_sha256: firstStable.sha256,
      verdict: "PASS",
    };
  } finally {
    cleanupOwnedTemporary(root, marker);
  }
}

function parseArgs(argv) {
  const mode = argv[0];
  const options = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(key?.startsWith("--") && value !== undefined, "CLI_REJECTED", "invalid arguments");
    assert(!options.has(key), "CLI_REJECTED", `duplicate ${key}`);
    options.set(key, value);
  }
  return Object.freeze({ mode, options });
}

function requiredAbsoluteOption(options, key) {
  const value = options.get(key);
  assert(typeof value === "string" && isAbsolute(value), "CLI_REJECTED", `${key} must be absolute`);
  return value;
}

function main() {
  const { mode, options } = parseArgs(process.argv.slice(2));
  let result;
  if (mode === "self-test") {
    assert(options.size === 0, "CLI_REJECTED", "self-test takes no options");
    result = selfTest();
  } else if (mode === "run") {
    assert(options.size === 3, "CLI_REJECTED", "run option drift");
    const candidatePath = requiredAbsoluteOption(options, "--candidate-manifest");
    const evidenceRoot = requiredAbsoluteOption(options, "--evidence-root");
    const runId = options.get("--run-id");
    assert(RUN_ID_PATTERN.test(runId ?? ""), "RUN_ID_REJECTED", "unsafe run id");
    assert(realpathSync(evidenceRoot) === EVIDENCE_ROOT, "EVIDENCE_ROOT_PATH_REJECTED", "formal evidence root drift");
    const qualityFreeze = parseQualityFreeze();
    const candidate = loadCandidateManifest(candidatePath, qualityFreeze);
    const run = performRun({ qualityFreeze, candidateBinding: candidate.binding, evidenceRoot, runId });
    result = {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_063_runner_result",
      task_id: TASK_ID,
      run_id: runId,
      run_manifest: {
        path: run.run_manifest.receipt.path,
        byte_length: run.run_manifest.receipt.byte_length,
        sha256: run.run_manifest.receipt.sha256,
      },
      verdict: "PASS",
    };
  } else {
    reject("CLI_REJECTED", "usage: runner.mjs self-test | run --candidate-manifest ABS --evidence-root ABS --run-id SAFE");
  }
  process.stdout.write(canonicalJsonBytes(result));
}

try {
  main();
} catch (error) {
  const reasonCode = error instanceof RunnerError || error instanceof OfflineAdapterError
    ? error.reasonCode
    : "UNEXPECTED";
  process.stderr.write(`P1_063_RUNNER: NON_PASS reason_code=${reasonCode} detail=${error.message}\n`);
  process.exitCode = 1;
}

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
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  symlinkSync,
  writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { compileFiniteTypedPatchIr } from "./compiler.mjs";
import {
  evaluateByteClosureCompiler,
  evaluateCandidateBinding,
  evaluateCompilerObservation,
  evaluateMalformedPayloadCompiler,
  evaluateNegativeResults,
  evaluateObservation,
  evaluateRollbackObservations,
  evaluateRunObservation,
  normalizeCommandStream,
  selfValidateProgramBuffers,
  selfValidateTaskCardBytes,
} from "../../evaluator/finite-typed-patch-ir-v1/quality-oracle.mjs";

export const RUNNER_VERSION = "SL-PATCH-IR-TRUSTED-RUNNER/1";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const CANONICAL_REPOSITORY_ROOT = "/Users/lijunpeng/Developer/SourceLens-AIOS";
const TASK_ID = "AIOS-P1-055_FINITE_TYPED_PATCH_IR_COMPILER_CONFORMANCE";
const CONTROL_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const TASK_CARD_RELATIVE = "evaluation-harness/fixtures/finite-typed-patch-ir-v1/task-card.json";
const TASK_CARD_PATH = join(REPOSITORY_ROOT, TASK_CARD_RELATIVE);
const COMPILER_PATH = join(HERE, "compiler.mjs");
const QUALITY_ORACLE_PATH = join(REPOSITORY_ROOT, "evaluation-harness/evaluator/finite-typed-patch-ir-v1/quality-oracle.mjs");
const ACTIVATION_PARENT_COMMIT = "d9cd7bd4d0b68c2bcaa4ff4d3b511e39eaa4208b";
const TASK_CARD_IDENTITY = Object.freeze({
  byte_length: 24928,
  sha256: "08c6c25c34d70fb7d41452a69fd31e7527aac5014c34d9ef2305cdbca4be200c",
});
const QUALITY_RECEIPT_PATH =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-055-finite-typed-patch-ir-20260720T014028Z/quality/QUALITY_FREEZE_RECEIPT.json";
const QUALITY_RECEIPT_IDENTITY = Object.freeze({
  byte_length: 2123,
  sha256: "00006a1a047848653d7660229927cdf2a96e83ee3c5459e47eca2d8d824a5199",
});
const QUALITY_MANIFEST_SHA256 = "8700257b9a839620de8bac7a2915f866d31dd2252186fae1fef7c4bd201d0b15";
const QUALITY_MANIFEST_PATH =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-055-finite-typed-patch-ir-20260720T014028Z/quality/QUALITY_FREEZE_MANIFEST.json";
const QUALITY_MANIFEST_IDENTITY = Object.freeze({ byte_length: 3142, sha256: QUALITY_MANIFEST_SHA256 });
const QUALITY_ORACLE_IDENTITY = Object.freeze({
  byte_length: 32410,
  sha256: "8638ff9f6235203526420101be00f69745fbdc8c97a78a7e159550956bb4bb2f",
});
const CONTRACT_PATH = join(REPOSITORY_ROOT, "docs/aios/tasks/P1-055_FINITE_TYPED_PATCH_IR_COMPILER_CONFORMANCE.yaml");
const CONTRACT_IDENTITY = Object.freeze({
  byte_length: 18087,
  sha256: "150b80d116088489339a850095e8d3ff33dd73e1212b7c617a8becf02c509289",
});
const DATASET_TASK_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION",
);
const DATASET_ROOT = resolve(DATASET_TASK_ROOT, "../..");
const SOURCE_TEMPLATE_ROOT = join(DATASET_TASK_ROOT, "source-template");
const TASK_SPEC_PATH = join(DATASET_TASK_ROOT, "task-spec.json");
const TASK_SPEC_IDENTITY = Object.freeze({ byte_length: 2960, sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321" });
const MATERIALIZATION_RECIPE_PATH = join(DATASET_ROOT, "materialization-recipe.json");
const MATERIALIZATION_RECIPE_IDENTITY = Object.freeze({ byte_length: 456, sha256: "104ed7109df7da155867a428b50575a9cda6bca481e183cebed50788c01a3a5e" });
const EXPECTED_BASE_FAILURE_PATH = join(DATASET_TASK_ROOT, "expected-base-failure.json");
const EXPECTED_BASE_FAILURE_IDENTITY = Object.freeze({ byte_length: 439, sha256: "5dbe034939ed2178f86fd84ad409cff9426040f63343de27f7ad3e8f46dd2494" });
const EXPECTED_BASE_COMMIT = "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f";
const EXPECTED_BASE_TREE = "900814727113d65f5dad8b63222e14f39b2cf38b";
const BASE_SOURCE_IDENTITY = Object.freeze({
  byte_length: 115,
  sha256: "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75",
});
const ISSUE_TEST_IDENTITY = Object.freeze({ byte_length: 237, sha256: "51fd472f8cf85fd595246814db29699ab81ccdc2986d80666d8609a8c4972b4b" });
const REGRESSION_TEST_IDENTITY = Object.freeze({ byte_length: 241, sha256: "381c573d8f99305b47db9f1a2ca49779842fe1187b9d7c5b7410e56dda9240c5" });
const NODE_TOOL = Object.freeze({
  path: "/usr/local/bin/node",
  byte_length: 193262272,
  sha256: "c5548e7a991a5c90170a29843ffc46df4643e29141f3cbb035f60295cf2bc882",
});
const GIT_TOOL = Object.freeze({
  path: "/usr/bin/git",
  byte_length: 118848,
  sha256: "29d5080bd197feb8245ee7d9a275fee4750b5496c6a7016090eff5a357c1e8c4",
});
const PROGRAM_PATHS = Object.freeze({
  IR00: join(REPOSITORY_ROOT, "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir00.json"),
  IR01: join(REPOSITORY_ROOT, "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir01.json"),
  IR10: join(REPOSITORY_ROOT, "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json"),
  IR11: join(REPOSITORY_ROOT, "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir11.json"),
});
const PROGRAM_TABLE = Object.freeze([
  Object.freeze({ id: "IR00", byte_length: 255, sha256: "e21da56b4132c121419863bad9e682532963f8b5bc9951af31b23234d9c46736" }),
  Object.freeze({ id: "IR01", byte_length: 255, sha256: "db33a4d4f2a5b21f211344d785785c2b4c246677bbcf68ef0d5e1831cdf3d0c1" }),
  Object.freeze({ id: "IR10", byte_length: 255, sha256: "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc" }),
  Object.freeze({ id: "IR11", byte_length: 255, sha256: "0eeca741f57b218ee175308080de3ada3db1b4eb93222bd252cac9ed6e2c66f7" }),
]);
const ALLOWED_CHANGED_PATHS = Object.freeze([
  "Makefile",
  "docs/PROJECT_CODE_MAP.md",
  "evaluation-harness/evaluator/finite-typed-patch-ir-v1/quality-oracle.mjs",
  "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir00.json",
  "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir01.json",
  "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json",
  "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir11.json",
  "evaluation-harness/fixtures/finite-typed-patch-ir-v1/task-card.json",
  "evaluation-harness/harness/finite-typed-patch-ir-v1/compiler.mjs",
  "evaluation-harness/harness/finite-typed-patch-ir-v1/runner.mjs",
  "scripts/verify-p1-finite-typed-patch-ir-v1.sh",
]);
const PROGRAM_IDENTITY_RECORDS = Object.freeze(PROGRAM_TABLE.map((program) => Object.freeze({
  id: program.id,
  path: `evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/${program.id.toLowerCase()}.json`,
  byte_length: program.byte_length,
  sha256: program.sha256,
})));
const CONTRACT_IDENTITY_RECORD = Object.freeze({
  path: "docs/aios/tasks/P1-055_FINITE_TYPED_PATCH_IR_COMPILER_CONFORMANCE.yaml",
  ...CONTRACT_IDENTITY,
});
const TASK_CARD_IDENTITY_RECORD = Object.freeze({ path: TASK_CARD_RELATIVE, ...TASK_CARD_IDENTITY });
const QUALITY_ORACLE_IDENTITY_RECORD = Object.freeze({
  path: "evaluation-harness/evaluator/finite-typed-patch-ir-v1/quality-oracle.mjs",
  ...QUALITY_ORACLE_IDENTITY,
});
const QUALITY_RECEIPT_IDENTITY_RECORD = Object.freeze({ path: QUALITY_RECEIPT_PATH, ...QUALITY_RECEIPT_IDENTITY });
const RUN_ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const REQUIRED_ACTIONS = Object.freeze([
  "validate_candidate_and_quality_identities",
  "validate_compiler_tcb",
  "validate_frozen_inputs",
  "execute_exhaustive_byte_closure",
  "execute_explicit_malformed_payload_matrix",
  "execute_filesystem_evidence_canary_matrix",
  "materialize_fresh_rep001_repository",
  "verify_frozen_base_and_clean_state",
  "execute_base_issue_and_regression_tests",
  "execute_ir00_compile_replace_tests_evaluate_restore_exact_base",
  "execute_ir01_identity_no_effect_without_write_or_child",
  "execute_ir10_compile_replace_tests_evaluate_restore_exact_base",
  "execute_ir11_compile_replace_tests_evaluate_restore_exact_base",
  "emit_create_once_raw_evidence",
  "emit_stable_projection",
]);
const NEGATIVE_EXPECTATIONS = Object.freeze([
  ["preexisting-run-root", "PREEXISTING_RUN_ROOT_REJECTED"],
  ["symlink-run-root", "SYMLINK_RUN_ROOT_REJECTED"],
  ["run-root-escape", "RUN_ROOT_ESCAPE_REJECTED"],
  ["target-symlink", "TARGET_SYMLINK_REJECTED"],
  ["target-hardlink", "TARGET_NLINK_REJECTED"],
  ["target-preimage-drift", "TARGET_PREIMAGE_DRIFT_REJECTED"],
  ["target-mode-drift", "TARGET_MODE_DRIFT_REJECTED"],
  ["unowned-materialization-marker", "MATERIALIZATION_OWNERSHIP_REJECTED"],
  ["preexisting-sidecar", "PREEXISTING_SIDECAR_REJECTED"],
  ["symlink-sidecar", "SYMLINK_SIDECAR_REJECTED"],
  ["preexisting-evidence-leaf", "PREEXISTING_EVIDENCE_LEAF_REJECTED"],
  ["symlink-evidence-leaf", "SYMLINK_EVIDENCE_LEAF_REJECTED"],
  ["hardlink-evidence-leaf", "EVIDENCE_NLINK_REJECTED"],
  ["evidence-path-escape", "EVIDENCE_PATH_ESCAPE_REJECTED"],
  ["extra-changed-path", "CHANGED_PATH_SCOPE_REJECTED"],
  ["unexpected-new-file", "UNEXPECTED_NEW_FILE_REJECTED"],
  ["identity-forged-mutation", "IDENTITY_EFFECT_REJECTED"],
  ["identity-forged-child", "IDENTITY_CHILD_START_REJECTED"],
  ["canary-tamper", "CANARY_TAMPER_REJECTED"],
  ["cleanup-ownership-drift", "CLEANUP_OWNERSHIP_REJECTED"],
  ["cleanup-identity-drift", "CLEANUP_IDENTITY_REJECTED"],
  ["root-identity-drift", "ROOT_IDENTITY_DRIFT_REJECTED"],
  ["target-identity-drift", "TARGET_IDENTITY_DRIFT_REJECTED"],
  ["nonfrozen-postimage", "POSTIMAGE_IDENTITY_REJECTED"],
  ["wrong-outcome-id", "OUTCOME_BINDING_REJECTED"],
  ["forged-test-status", "OBSERVATION_MISMATCH_REJECTED"],
  ["candidate-binding-drift", "CANDIDATE_BINDING_REJECTED"],
  ["missing-required-action", "ACTION_SCHEDULE_REJECTED"],
  ["stable-projection-tamper", "STABLE_PROJECTION_REJECTED"],
  ["evaluator-verdict-tamper", "EVALUATOR_VERDICT_REJECTED"],
]);

class ControlledError extends Error {
  constructor(code, message, details = undefined) {
    super(message);
    this.name = "ControlledError";
    this.code = code;
    this.details = details;
  }
}

function reject(code, message, details = undefined) {
  throw new ControlledError(code, message, details);
}

function assert(condition, code, message) {
  if (!condition) reject(code, message);
}

function completeAction(ledger, actionId) {
  assert(Array.isArray(ledger), "ACTION_SCHEDULE_REJECTED", "action ledger missing");
  assert(REQUIRED_ACTIONS[ledger.length] === actionId, "ACTION_SCHEDULE_REJECTED", `unexpected action ${actionId}`);
  ledger.push(actionId);
}

function createEffectMeter() {
  return { mutation_attempts: 0, child_start_attempts: 0, test_child_start_attempts: 0 };
}

function effectSnapshot(meter) {
  return { ...meter };
}

function effectDelta(before, after) {
  return {
    mutation_attempts: after.mutation_attempts - before.mutation_attempts,
    child_start_attempts: after.child_start_attempts - before.child_start_attempts,
    test_child_start_attempts: after.test_child_start_attempts - before.test_child_start_attempts,
  };
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function identityOfBytes(bytes) {
  return { byte_length: bytes.length, sha256: sha256(bytes) };
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
}

function sameJson(left, right) {
  return JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right));
}

function safeReadRegular(filePath, expected = undefined, label = "file", requireNlinkOne = true) {
  const absolute = resolve(filePath);
  const pathStat = lstatSync(absolute);
  assert(pathStat.isFile() && !pathStat.isSymbolicLink(), "INPUT_IDENTITY_DRIFT", `${label} is not a regular file`);
  if (requireNlinkOne) assert(pathStat.nlink === 1, "INPUT_IDENTITY_DRIFT", `${label} nlink is not one`);
  assert(realpathSync(absolute) === absolute, "INPUT_IDENTITY_DRIFT", `${label} path contains a symlink`);
  const descriptor = openSync(absolute, fsConstants.O_RDONLY | O_NOFOLLOW);
  try {
    const before = fstatSync(descriptor);
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    const finalPath = lstatSync(absolute);
    assert(
      before.dev === after.dev && before.ino === after.ino && before.size === after.size &&
        after.dev === finalPath.dev && after.ino === finalPath.ino,
      "INPUT_IDENTITY_DRIFT",
      `${label} identity changed while reading`,
    );
    if (requireNlinkOne) assert(after.nlink === 1 && finalPath.nlink === 1, "INPUT_IDENTITY_DRIFT", `${label} nlink drift`);
    if (expected) assert(sameJson(identityOfBytes(bytes), expected), "INPUT_IDENTITY_DRIFT", `${label} exact identity mismatch`);
    return { bytes, stat: after, path: absolute };
  } finally {
    closeSync(descriptor);
  }
}

function currentUserCanWrite(stat) {
  const uid = typeof process.getuid === "function" ? process.getuid() : undefined;
  const gid = typeof process.getgid === "function" ? process.getgid() : undefined;
  const groups = typeof process.getgroups === "function" ? process.getgroups() : [];
  const permissions = stat.mode & 0o777;
  if (uid === 0) return true;
  if (uid !== undefined && uid === stat.uid) return Boolean(permissions & 0o200);
  if (gid !== undefined && (gid === stat.gid || groups.includes(stat.gid))) return Boolean(permissions & 0o020);
  return Boolean(permissions & 0o002);
}

function validateTool(tool, label) {
  assert(isAbsolute(tool.path), "TOOL_IDENTITY_DRIFT", `${label} path is not absolute`);
  const file = safeReadRegular(tool.path, { byte_length: tool.byte_length, sha256: tool.sha256 }, label, false);
  assert((file.stat.mode & 0o111) !== 0, "TOOL_IDENTITY_DRIFT", `${label} is not executable`);
  assert(!currentUserCanWrite(file.stat), "TOOL_IDENTITY_DRIFT", `${label} is writable by the current user`);
  return { path: tool.path, realpath: realpathSync(tool.path), ...identityOfBytes(file.bytes) };
}

function assertRealDirectory(directoryPath, code, label) {
  const absolute = resolve(directoryPath);
  const stat = lstatSync(absolute);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), code, `${label} is not a real directory`);
  assert(realpathSync(absolute) === absolute, code, `${label} path contains a symlink`);
  return { path: absolute, stat };
}

function isWithin(root, candidate, allowRoot = false) {
  const rel = relative(root, candidate);
  if (rel === "") return allowRoot;
  return rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function directChild(root, name, code = "PATH_ESCAPE_REJECTED") {
  assert(typeof name === "string" && RUN_ID_PATTERN.test(name), code, "unsafe direct-child name");
  const child = resolve(root, name);
  assert(dirname(child) === root && basename(child) === name && isWithin(root, child), code, "path escapes root");
  return child;
}

function createFreshDirectory(root, name, codes = {}) {
  const child = directChild(root, name, codes.escape ?? "RUN_ROOT_ESCAPE_REJECTED");
  try {
    const existing = lstatSync(child);
    if (existing.isSymbolicLink()) reject(codes.symlink ?? "SYMLINK_RUN_ROOT_REJECTED", "fresh directory target is a symlink");
    reject(codes.preexisting ?? "PREEXISTING_RUN_ROOT_REJECTED", "fresh directory target already exists");
  } catch (error) {
    if (error instanceof ControlledError) throw error;
    if (error.code !== "ENOENT") throw error;
  }
  mkdirSync(child, { mode: 0o700 });
  const stat = lstatSync(child);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), "ROOT_IDENTITY_DRIFT_REJECTED", "created directory identity invalid");
  return { path: child, dev: stat.dev, ino: stat.ino };
}

function createExclusiveFile(filePath, bytes, mode = 0o600, preexistingCode = "PREEXISTING_EVIDENCE_LEAF_REJECTED", symlinkCode = "SYMLINK_EVIDENCE_LEAF_REJECTED") {
  assert(Buffer.isBuffer(bytes), "EVIDENCE_WRITE_REJECTED", "create-once payload is not bytes");
  try {
    const existing = lstatSync(filePath);
    if (existing.isSymbolicLink()) reject(symlinkCode, "create-once target is a symlink");
    reject(preexistingCode, "create-once target exists");
  } catch (error) {
    if (error instanceof ControlledError) throw error;
    if (error.code !== "ENOENT") throw error;
  }
  const descriptor = openSync(filePath, fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | O_NOFOLLOW, mode);
  let created;
  try {
    let offset = 0;
    while (offset < bytes.length) {
      const written = writeSync(descriptor, bytes, offset, bytes.length - offset, offset);
      assert(written > 0, "EVIDENCE_WRITE_REJECTED", "create-once write made no progress");
      offset += written;
    }
    fsyncSync(descriptor);
    const stat = fstatSync(descriptor);
    assert(stat.isFile() && stat.nlink === 1 && stat.size === bytes.length, "EVIDENCE_NLINK_REJECTED", "created file identity invalid");
    created = { dev: stat.dev, ino: stat.ino, byte_length: stat.size, sha256: sha256(bytes) };
  } finally {
    closeSync(descriptor);
  }
  const verified = safeReadRegular(filePath, identityOfBytes(bytes), "created file");
  assert(verified.stat.dev === created.dev && verified.stat.ino === created.ino, "EVIDENCE_IDENTITY_DRIFT_REJECTED", "created file path identity drift");
  return created;
}

function verifyDirectoryIdentity(receipt, code = "ROOT_IDENTITY_DRIFT_REJECTED") {
  const stat = lstatSync(receipt.path);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), code, "owned directory type drift");
  assert(stat.dev === receipt.dev && stat.ino === receipt.ino, code, "owned directory identity drift");
}

function removeOwnedDirectory(receipt, markerPath, markerIdentity) {
  verifyDirectoryIdentity(receipt, "CLEANUP_IDENTITY_REJECTED");
  const marker = safeReadRegular(markerPath, undefined, "ownership marker");
  assert(
    sameJson(identityOfBytes(marker.bytes), { byte_length: markerIdentity.byte_length, sha256: markerIdentity.sha256 }) &&
      marker.stat.dev === markerIdentity.dev && marker.stat.ino === markerIdentity.ino,
    "CLEANUP_OWNERSHIP_REJECTED",
    "ownership marker drift",
  );
  rmSync(receipt.path, { recursive: true, force: false });
}

function verifyOwnedDirectory(ownership, identityCode = "ROOT_IDENTITY_DRIFT_REJECTED", ownershipCode = "MATERIALIZATION_OWNERSHIP_REJECTED") {
  verifyDirectoryIdentity(ownership.receipt, identityCode);
  const marker = safeReadRegular(ownership.markerPath, undefined, "ownership marker");
  assert(
    sameJson(identityOfBytes(marker.bytes), { byte_length: ownership.marker.byte_length, sha256: ownership.marker.sha256 }) &&
      marker.stat.dev === ownership.marker.dev && marker.stat.ino === ownership.marker.ino,
    ownershipCode,
    "ownership marker identity drift",
  );
}

function makeOwnedRoot(parent, name) {
  const receipt = createFreshDirectory(parent, name);
  const token = randomBytes(24).toString("hex");
  const markerPath = join(receipt.path, ".sourcelens-p1-055-owner.json");
  const markerBytes = canonicalJsonBytes({ schema_version: 1, task_id: TASK_ID, token });
  const marker = createExclusiveFile(markerPath, markerBytes, 0o600);
  return { receipt, markerPath, marker: { ...marker, ...identityOfBytes(markerBytes) }, token };
}

function commandRecord(actionId, argv, cwd, environment, expectedStatuses = undefined, effectMeter = undefined) {
  assert(Array.isArray(argv) && isAbsolute(argv[0]), "COMMAND_PROFILE_REJECTED", `${actionId} argv is not fixed absolute`);
  const started = Date.now();
  if (effectMeter) effectMeter.child_start_attempts += 1;
  const execution = spawnSync(argv[0], argv.slice(1), {
    cwd,
    env: environment,
    encoding: null,
    timeout: 15_000,
    maxBuffer: 4 * 1024 * 1024,
    shell: false,
  });
  const record = {
    action_id: actionId,
    argv: [...argv],
    cwd,
    exit_status: execution.status,
    signal: execution.signal,
    timeout_ms: 15_000,
    max_buffer_bytes: 4 * 1024 * 1024,
    duration_ms: Date.now() - started,
    stdout: Buffer.isBuffer(execution.stdout) ? execution.stdout : Buffer.alloc(0),
    stderr: Buffer.isBuffer(execution.stderr) ? execution.stderr : Buffer.alloc(0),
    spawn_error: execution.error?.message ?? null,
  };
  assert(record.spawn_error === null && record.signal === null, "COMMAND_EXECUTION_REJECTED", `${actionId} did not exit normally`);
  if (expectedStatuses) assert(expectedStatuses.includes(record.exit_status), "COMMAND_EXECUTION_REJECTED", `${actionId} exit status mismatch`);
  return record;
}

function deterministicEnvironment(homePath) {
  return {
    HOME: homePath,
    PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
    LANG: "C",
    LC_ALL: "C",
    TZ: "UTC",
    NODE_OPTIONS: "--no-warnings",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_TERMINAL_PROMPT: "0",
    GIT_AUTHOR_NAME: "SourceLens AIOS Fixture",
    GIT_AUTHOR_EMAIL: "fixture@sourcelens.local",
    GIT_AUTHOR_DATE: "2000-01-01T00:00:00Z",
    GIT_COMMITTER_NAME: "SourceLens AIOS Fixture",
    GIT_COMMITTER_EMAIL: "fixture@sourcelens.local",
    GIT_COMMITTER_DATE: "2000-01-01T00:00:00Z",
  };
}

function validateCompilerTcb() {
  const source = safeReadRegular(COMPILER_PATH, undefined, "compiler source").bytes.toString("utf8");
  const imports = [...source.matchAll(/from\s+["']([^"']+)["']/g)].map((match) => match[1]);
  assert(sameJson(imports, ["node:crypto"]), "COMPILER_TCB_REJECTED", "compiler import allowlist mismatch");
  const forbidden = [
    /\bimport\s*\(/,
    /\beval\s*\(/,
    /\bFunction\s*\(/,
    /\bWebAssembly\b/,
    /\bprocess\b/,
    /node:(?:fs|child_process|net|http|https|tls|dgram|vm|module|worker_threads)/,
  ];
  assert(forbidden.every((pattern) => !pattern.test(source)), "COMPILER_TCB_REJECTED", "compiler contains forbidden API");
  return "PASS";
}

function validateFrozenInputBytes(taskCardArgument) {
  const supplied = resolve(process.cwd(), taskCardArgument);
  assert(supplied === TASK_CARD_PATH, "TASK_CARD_DRIFT", "Task Card path is not exact");
  const taskCard = safeReadRegular(TASK_CARD_PATH, TASK_CARD_IDENTITY, "Task Card");
  const contract = safeReadRegular(CONTRACT_PATH, CONTRACT_IDENTITY, "Task Contract");
  const oracle = safeReadRegular(QUALITY_ORACLE_PATH, QUALITY_ORACLE_IDENTITY, "Quality oracle");
  const receiptFile = safeReadRegular(QUALITY_RECEIPT_PATH, QUALITY_RECEIPT_IDENTITY, "Quality receipt");
  const receipt = JSON.parse(receiptFile.bytes.toString("utf8"));
  assert(receipt.status === "QUALITY_FREEZE_EFFECTIVE_WORKER_HANDOFF_ALLOWED", "QUALITY_FREEZE_DRIFT", "Quality receipt status mismatch");
  assert(receipt.task_card?.sha256 === TASK_CARD_IDENTITY.sha256, "QUALITY_FREEZE_DRIFT", "receipt Task Card binding mismatch");
  assert(receipt.quality_oracle?.sha256 === QUALITY_ORACLE_IDENTITY.sha256, "QUALITY_FREEZE_DRIFT", "receipt oracle binding mismatch");
  assert(receipt.manifest?.sha256 === QUALITY_MANIFEST_SHA256, "QUALITY_FREEZE_DRIFT", "receipt manifest binding mismatch");
  const programBuffers = new Map(Object.entries(PROGRAM_PATHS).map(([id, filePath]) => [id, safeReadRegular(filePath, undefined, id).bytes]));
  const taskSpecFile = safeReadRegular(TASK_SPEC_PATH, TASK_SPEC_IDENTITY, "task spec");
  const recipeFile = safeReadRegular(MATERIALIZATION_RECIPE_PATH, MATERIALIZATION_RECIPE_IDENTITY, "materialization recipe");
  const expectedFailureFile = safeReadRegular(EXPECTED_BASE_FAILURE_PATH, EXPECTED_BASE_FAILURE_IDENTITY, "expected base failure");
  const sourceFile = safeReadRegular(join(SOURCE_TEMPLATE_ROOT, "src/range.mjs"), BASE_SOURCE_IDENTITY, "source preimage");
  const issueTestFile = safeReadRegular(join(SOURCE_TEMPLATE_ROOT, "test/issue.test.mjs"), ISSUE_TEST_IDENTITY, "issue test");
  const regressionTestFile = safeReadRegular(join(SOURCE_TEMPLATE_ROOT, "test/regression.test.mjs"), REGRESSION_TEST_IDENTITY, "regression test");
  for (const [label, file] of [["source preimage", sourceFile], ["issue test", issueTestFile], ["regression test", regressionTestFile]]) {
    assert((file.stat.mode & 0o777) === 0o644, "FROZEN_INPUT_DRIFT", `${label} mode drift`);
  }
  const taskSpec = JSON.parse(taskSpecFile.bytes.toString("utf8"));
  const recipe = JSON.parse(recipeFile.bytes.toString("utf8"));
  assert(
    taskSpec.task_id === CONTROL_ID && taskSpec.repository?.base_commit === EXPECTED_BASE_COMMIT &&
      taskSpec.repository?.tree_hash === EXPECTED_BASE_TREE && taskSpec.repository?.dirty_state_policy === "clean_immutable_base",
    "FROZEN_INPUT_DRIFT",
    "task spec repository binding mismatch",
  );
  assert(
    sameJson(taskSpec.verification?.required_commands?.map((command) => command.argv), [
      [NODE_TOOL.path, "--test", "test/issue.test.mjs"],
      [NODE_TOOL.path, "--test", "test/regression.test.mjs"],
    ]),
    "FROZEN_INPUT_DRIFT",
    "task spec command binding mismatch",
  );
  assert(
    recipe.schema_version === "1.0" && recipe.hash_algorithm === "sha1" && recipe.source_directory === "source-template" &&
      recipe.commit_message === "fixture: base" && recipe.file_mode === "100644" &&
      recipe.git_author_name === "SourceLens AIOS Fixture" && recipe.git_author_email === "fixture@sourcelens.local" &&
      recipe.git_author_date === "2000-01-01T00:00:00Z" &&
      recipe.git_committer_name === "SourceLens AIOS Fixture" && recipe.git_committer_email === "fixture@sourcelens.local" &&
      recipe.git_committer_date === "2000-01-01T00:00:00Z",
    "FROZEN_INPUT_DRIFT",
    "materialization recipe binding mismatch",
  );
  return {
    task_card: taskCard,
    contract: identityOfBytes(contract.bytes),
    oracle: identityOfBytes(oracle.bytes),
    receipt: identityOfBytes(receiptFile.bytes),
    programs: programBuffers,
    input_identities: {
      task_spec: { path: relative(REPOSITORY_ROOT, TASK_SPEC_PATH), ...identityOfBytes(taskSpecFile.bytes) },
      materialization_recipe: { path: relative(REPOSITORY_ROOT, MATERIALIZATION_RECIPE_PATH), ...identityOfBytes(recipeFile.bytes) },
      expected_base_failure: { path: relative(REPOSITORY_ROOT, EXPECTED_BASE_FAILURE_PATH), ...identityOfBytes(expectedFailureFile.bytes) },
      source_preimage: { path: relative(REPOSITORY_ROOT, join(SOURCE_TEMPLATE_ROOT, "src/range.mjs")), mode: `100${(sourceFile.stat.mode & 0o777).toString(8)}`, ...identityOfBytes(sourceFile.bytes) },
      issue_test: { path: relative(REPOSITORY_ROOT, join(SOURCE_TEMPLATE_ROOT, "test/issue.test.mjs")), mode: `100${(issueTestFile.stat.mode & 0o777).toString(8)}`, ...identityOfBytes(issueTestFile.bytes) },
      regression_test: { path: relative(REPOSITORY_ROOT, join(SOURCE_TEMPLATE_ROOT, "test/regression.test.mjs")), mode: `100${(regressionTestFile.stat.mode & 0o777).toString(8)}`, ...identityOfBytes(regressionTestFile.bytes) },
      frozen_base: { commit: EXPECTED_BASE_COMMIT, tree: EXPECTED_BASE_TREE, clean_status: "clean" },
      executables: { node: NODE_TOOL, git: GIT_TOOL },
    },
  };
}

function selfValidateFrozenInputs(frozen) {
  return {
    ...frozen,
    card_validation: selfValidateTaskCardBytes(frozen.task_card.bytes),
    program_validation: selfValidateProgramBuffers(frozen.programs),
  };
}

function writeTemplateFile(repository, relativePath, expected) {
  const sourcePath = join(SOURCE_TEMPLATE_ROOT, relativePath);
  assert(isWithin(SOURCE_TEMPLATE_ROOT, sourcePath), "SOURCE_IDENTITY_DRIFT", "source path escapes template root");
  const source = safeReadRegular(sourcePath, expected, relativePath);
  const destination = join(repository, relativePath);
  assert(isWithin(repository, destination), "SOURCE_IDENTITY_DRIFT", "destination escapes materialization");
  mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
  createExclusiveFile(destination, source.bytes, 0o644, "SOURCE_PREEXISTING_REJECTED", "SOURCE_SYMLINK_REJECTED");
  chmodSync(destination, 0o644);
}

function materialize(runRoot, commandRecords, effectMeter) {
  const repositoryReceipt = createFreshDirectory(runRoot, "materialization", {
    escape: "RUN_ROOT_ESCAPE_REJECTED",
    preexisting: "PREEXISTING_RUN_ROOT_REJECTED",
    symlink: "SYMLINK_RUN_ROOT_REJECTED",
  });
  const repositoryMarkerPath = join(runRoot, ".materialization-owner.json");
  const repositoryMarkerBytes = canonicalJsonBytes({
    schema_version: 1,
    task_id: TASK_ID,
    token: randomBytes(24).toString("hex"),
  });
  const repositoryMarker = createExclusiveFile(repositoryMarkerPath, repositoryMarkerBytes, 0o600);
  const repositoryOwnership = {
    receipt: repositoryReceipt,
    markerPath: repositoryMarkerPath,
    marker: { ...repositoryMarker, ...identityOfBytes(repositoryMarkerBytes) },
  };
  const homeReceipt = createFreshDirectory(runRoot, "home");
  const repository = repositoryReceipt.path;
  writeTemplateFile(repository, "src/range.mjs", BASE_SOURCE_IDENTITY);
  writeTemplateFile(repository, "test/issue.test.mjs", {
    ...ISSUE_TEST_IDENTITY,
  });
  writeTemplateFile(repository, "test/regression.test.mjs", {
    ...REGRESSION_TEST_IDENTITY,
  });
  const env = deterministicEnvironment(homeReceipt.path);
  commandRecords.push(commandRecord("git_init", [GIT_TOOL.path, "init", "--quiet", "--template=", "--object-format=sha1"], repository, env, [0], effectMeter));
  commandRecords.push(commandRecord("git_add", [GIT_TOOL.path, "add", "--all"], repository, env, [0], effectMeter));
  commandRecords.push(commandRecord(
    "git_commit",
    [GIT_TOOL.path, "-c", "commit.gpgsign=false", "commit", "--quiet", "--no-verify", "--no-gpg-sign", "-m", "fixture: base"],
    repository,
    env,
    [0],
    effectMeter,
  ));
  const head = commandRecord("git_head", [GIT_TOOL.path, "rev-parse", "HEAD"], repository, env, [0], effectMeter);
  const tree = commandRecord("git_tree", [GIT_TOOL.path, "rev-parse", "HEAD^{tree}"], repository, env, [0], effectMeter);
  const status = commandRecord("git_status_base", [GIT_TOOL.path, "status", "--porcelain=v1", "-z", "--untracked-files=all"], repository, env, [0], effectMeter);
  commandRecords.push(head, tree, status);
  assert(head.stdout.toString("utf8").trim() === EXPECTED_BASE_COMMIT, "SOURCE_IDENTITY_DRIFT", "materialized commit mismatch");
  assert(tree.stdout.toString("utf8").trim() === EXPECTED_BASE_TREE, "SOURCE_IDENTITY_DRIFT", "materialized tree mismatch");
  assert(status.stdout.length === 0, "SOURCE_IDENTITY_DRIFT", "materialization is not clean");
  verifyOwnedDirectory(repositoryOwnership);
  return { repository, repositoryReceipt, repositoryOwnership, homeReceipt, env };
}

function parseChangedPaths(statusBytes) {
  if (statusBytes.length === 0) return [];
  return statusBytes.toString("utf8").split("\0").filter(Boolean).map((entry) => entry.slice(3)).sort();
}

function gitStatus(repository, env, actionId, commandRecords, effectMeter) {
  const record = commandRecord(actionId, [GIT_TOOL.path, "status", "--porcelain=v1", "-z", "--untracked-files=all"], repository, env, [0], effectMeter);
  commandRecords.push(record);
  return parseChangedPaths(record.stdout);
}

function validateTarget(targetPath, expectedIdentity = BASE_SOURCE_IDENTITY) {
  const pathStat = lstatSync(targetPath);
  assert(!pathStat.isSymbolicLink() && pathStat.isFile(), "TARGET_SYMLINK_REJECTED", "target is not regular");
  assert(pathStat.nlink === 1, "TARGET_NLINK_REJECTED", "target nlink is not one");
  assert((pathStat.mode & 0o777) === 0o644, "TARGET_MODE_DRIFT_REJECTED", "target mode drift");
  const file = safeReadRegular(targetPath, undefined, "target");
  assert(sameJson(identityOfBytes(file.bytes), expectedIdentity), "TARGET_PREIMAGE_DRIFT_REJECTED", "target preimage drift");
  return { bytes: file.bytes, stat: file.stat };
}

function atomicReplaceTarget(materialized, replacement, expectedIdentity, token, effectMeter) {
  const { repository, repositoryOwnership } = materialized;
  verifyOwnedDirectory(repositoryOwnership);
  const targetPath = join(repository, "src/range.mjs");
  assert(isWithin(repository, targetPath), "TARGET_PATH_ESCAPE_REJECTED", "target escapes repository");
  const before = validateTarget(targetPath, expectedIdentity);
  const sidecarPath = join(dirname(targetPath), `.sourcelens-p1-055-${token}.tmp`);
  let sidecarIdentity;
  try {
    sidecarIdentity = createExclusiveFile(sidecarPath, replacement, 0o644, "PREEXISTING_SIDECAR_REJECTED", "SYMLINK_SIDECAR_REJECTED");
    chmodSync(sidecarPath, 0o644);
    const recheck = validateTarget(targetPath, expectedIdentity);
    assert(recheck.stat.dev === before.stat.dev && recheck.stat.ino === before.stat.ino, "TARGET_IDENTITY_DRIFT_REJECTED", "target identity changed before replace");
    verifyOwnedDirectory(repositoryOwnership);
    const sidecarStat = lstatSync(sidecarPath);
    assert(sidecarStat.dev === sidecarIdentity.dev && sidecarStat.ino === sidecarIdentity.ino, "TARGET_IDENTITY_DRIFT_REJECTED", "sidecar identity drift");
    effectMeter.mutation_attempts += 1;
    renameSync(sidecarPath, targetPath);
  } catch (error) {
    try {
      if (sidecarIdentity) {
        const stat = lstatSync(sidecarPath);
        if (stat.dev === sidecarIdentity.dev && stat.ino === sidecarIdentity.ino && stat.isFile() && !stat.isSymbolicLink()) {
          rmSync(sidecarPath, { force: false });
        }
      }
    } catch (cleanupError) {
      if (cleanupError.code !== "ENOENT") throw cleanupError;
    }
    throw error;
  }
  const after = safeReadRegular(targetPath, identityOfBytes(replacement), "replaced target");
  assert(
    (after.stat.mode & 0o777) === 0o644 && after.stat.nlink === 1 &&
      after.stat.dev === sidecarIdentity.dev && after.stat.ino === sidecarIdentity.ino,
    "TARGET_IDENTITY_DRIFT_REJECTED",
    "replaced target metadata or sidecar identity drift",
  );
  verifyOwnedDirectory(repositoryOwnership);
}

function executeTest(actionId, repository, env, relativeTest, expectedStatus, commandRecords, effectMeter) {
  effectMeter.test_child_start_attempts += 1;
  const record = commandRecord(actionId, [NODE_TOOL.path, "--test", relativeTest], repository, env, [expectedStatus], effectMeter);
  commandRecords.push(record);
  return record;
}

function assertTypedBaseFailure(issueRecord) {
  const expected = JSON.parse(safeReadRegular(
    EXPECTED_BASE_FAILURE_PATH,
    EXPECTED_BASE_FAILURE_IDENTITY,
    "expected base failure",
  ).bytes.toString("utf8"));
  const output = Buffer.concat([issueRecord.stdout, issueRecord.stderr]).toString("utf8");
  assert(issueRecord.exit_status === expected.expected_exit_status, "BASE_FAILURE_MISMATCH", "base issue status mismatch");
  assert(expected.required_output_tokens.every((token) => output.includes(token)), "BASE_FAILURE_MISMATCH", "base issue required token missing");
  assert(expected.forbidden_output_tokens.every((token) => !output.includes(token)), "BASE_FAILURE_MISMATCH", "base issue forbidden token observed");
}

function programOutcomeObservation(program, result, issue, regression, measured) {
  return {
    program_id: program.id,
    program_length: program.byte_length,
    program_sha256: program.sha256,
    outcome_id: result.outcome_id,
    outcome_kind: result.kind,
    postimage_bytes_or_null: result.postimage,
    mutation_attempts: measured.mutation_attempts,
    child_start_attempts: measured.child_start_attempts,
    changed_paths: measured.changed_paths,
    test_statuses: result.postimage === null ? null : { issue: issue.exit_status, regression: regression.exit_status },
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
  };
}

function evaluateBoundedObservation(observation) {
  if (observation?.outcome_kind === "IDENTITY_NO_EFFECT_REJECTION") {
    assert(observation.mutation_attempts === 0, "IDENTITY_EFFECT_REJECTED", "identity outcome attempted mutation");
    assert(observation.child_start_attempts === 0, "IDENTITY_CHILD_START_REJECTED", "identity outcome attempted child start");
  }
  return evaluateObservation(observation);
}

function executeProgramOutcomes(materialized, programs, commandRecords, actionLedger, runCanary, effectMeter) {
  const { repository, env } = materialized;
  const targetPath = join(repository, "src/range.mjs");
  const baseBytes = safeReadRegular(targetPath, BASE_SOURCE_IDENTITY, "base target").bytes;
  const observations = [];
  const rawObservations = [];
  const rollbacks = [];
  for (const program of PROGRAM_TABLE) {
    const beforeEffects = effectSnapshot(effectMeter);
    verifyOwnedDirectory(materialized.repositoryOwnership);
    assert(gitStatus(repository, env, `${program.id.toLowerCase()}_pre_status`, commandRecords, effectMeter).length === 0, "ROLLBACK_REJECTED", "program did not start clean");
    const proposal = programs.get(program.id);
    const compiled = compileFiniteTypedPatchIr(Buffer.from(proposal));
    evaluateCompilerObservation(proposal, compiled);
    let issue = null;
    let regression = null;
    let mutationOccurred = false;
    const measured = { mutation_attempts: 0, child_start_attempts: 0, changed_paths: [] };
    if (compiled.postimage !== null) {
      atomicReplaceTarget(materialized, compiled.postimage, BASE_SOURCE_IDENTITY, `${program.id.toLowerCase()}-${randomBytes(8).toString("hex")}`, effectMeter);
      mutationOccurred = true;
      measured.changed_paths = gitStatus(repository, env, `${program.id.toLowerCase()}_changed_status`, commandRecords, effectMeter);
      assert(
        sameJson(measured.changed_paths, ["src/range.mjs"]),
        "CHANGED_PATH_SCOPE_REJECTED",
        "changed path scope mismatch",
      );
      const expectedIssue = program.id === "IR10" ? 0 : 1;
      issue = executeTest(`${program.id.toLowerCase()}_issue_test`, repository, env, "test/issue.test.mjs", expectedIssue, commandRecords, effectMeter);
      regression = executeTest(`${program.id.toLowerCase()}_regression_test`, repository, env, "test/regression.test.mjs", 0, commandRecords, effectMeter);
    }
    const observedEffects = effectDelta(beforeEffects, effectSnapshot(effectMeter));
    measured.mutation_attempts = observedEffects.mutation_attempts;
    measured.child_start_attempts = observedEffects.test_child_start_attempts;
    verifyCanaryBytes(runCanary.path, runCanary.bytes);
    const observation = programOutcomeObservation(program, compiled, issue, regression, measured);
    rawObservations.push(observation);
    observations.push(evaluateBoundedObservation(observation));
    if (mutationOccurred) {
      atomicReplaceTarget(materialized, baseBytes, identityOfBytes(compiled.postimage), `${program.id.toLowerCase()}-rollback-${randomBytes(8).toString("hex")}`, effectMeter);
    }
    const cleanPaths = gitStatus(repository, env, `${program.id.toLowerCase()}_rollback_status`, commandRecords, effectMeter);
    assert(cleanPaths.length === 0, "ROLLBACK_REJECTED", "rollback left materialization dirty");
    const restored = safeReadRegular(targetPath, BASE_SOURCE_IDENTITY, "restored target");
    const head = commandRecord(`${program.id.toLowerCase()}_rollback_head`, [GIT_TOOL.path, "rev-parse", "HEAD"], repository, env, [0], effectMeter);
    const tree = commandRecord(`${program.id.toLowerCase()}_rollback_tree`, [GIT_TOOL.path, "rev-parse", "HEAD^{tree}"], repository, env, [0], effectMeter);
    commandRecords.push(head, tree);
    const measuredHead = head.stdout.toString("utf8").trim();
    const measuredTree = tree.stdout.toString("utf8").trim();
    assert(measuredHead === EXPECTED_BASE_COMMIT && measuredTree === EXPECTED_BASE_TREE, "ROLLBACK_REJECTED", "rollback Git identity drift");
    verifyOwnedDirectory(materialized.repositoryOwnership);
    verifyCanaryBytes(runCanary.path, runCanary.bytes);
    rollbacks.push({
      program_id: program.id,
      source_sha256: sha256(restored.bytes),
      base_commit: measuredHead,
      base_tree: measuredTree,
      git_status_porcelain: "",
      restored_exact_base: true,
      mutation_occurred: mutationOccurred,
    });
    completeAction(
      actionLedger,
      program.id === "IR01"
        ? "execute_ir01_identity_no_effect_without_write_or_child"
        : `execute_${program.id.toLowerCase()}_compile_replace_tests_evaluate_restore_exact_base`,
    );
  }
  return {
    observations,
    rawObservations,
    rollbacks: evaluateRollbackObservations(rollbacks),
  };
}

function expectControlled(expectedCode, action) {
  try {
    action();
  } catch (error) {
    if (error instanceof ControlledError && error.code === expectedCode) return;
    if (error?.code === expectedCode) return;
    throw new Error(`expected ${expectedCode}, received ${error?.code ?? error?.name}: ${error?.message}`);
  }
  throw new Error(`expected ${expectedCode}, action passed`);
}

function standardNegativeResult(id, reasonCode, mutationAttempts, childStartAttempts) {
  return {
    id,
    reason_code: reasonCode,
    mutation_attempts: mutationAttempts,
    child_start_attempts: childStartAttempts,
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
  };
}

function verifyFileReceipt(filePath, receipt, code) {
  const stat = lstatSync(filePath);
  assert(stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1, code, "file receipt type drift");
  assert(stat.dev === receipt.dev && stat.ino === receipt.ino, code, "file receipt identity drift");
}

function verifyDirectoryEntries(directoryPath, expected, code) {
  const actual = readdirSync(directoryPath, { encoding: "utf8" }).sort();
  assert(sameJson(actual, [...expected].sort()), code, "directory entry population drift");
}

function verifyCanaryBytes(filePath, expectedBytes) {
  const actual = safeReadRegular(filePath, undefined, "canary fixture").bytes;
  assert(actual.equals(expectedBytes), "CANARY_TAMPER_REJECTED", "canary bytes drift");
}

function verifyRunCanary(runCanary) {
  verifyFileReceipt(runCanary.path, runCanary.receipt, "CANARY_TAMPER_REJECTED");
  verifyCanaryBytes(runCanary.path, runCanary.bytes);
}

function verifyStableProjectionBytes(expected, actual) {
  assert(Buffer.isBuffer(expected) && Buffer.isBuffer(actual), "STABLE_PROJECTION_REJECTED", "stable projection values are not bytes");
  if (expected.equals(actual)) return;
  let firstDifference = "unknown";
  try {
    const left = JSON.parse(expected.toString("utf8"));
    const right = JSON.parse(actual.toString("utf8"));
    const queue = [["$", left, right]];
    while (queue.length > 0) {
      const [path, leftValue, rightValue] = queue.shift();
      if (sameJson(leftValue, rightValue)) continue;
      if (
        leftValue && rightValue && typeof leftValue === "object" && typeof rightValue === "object" &&
        !Buffer.isBuffer(leftValue) && !Buffer.isBuffer(rightValue)
      ) {
        const keys = [...new Set([...Object.keys(leftValue), ...Object.keys(rightValue)])].sort();
        for (const key of keys) queue.push([`${path}.${key}`, leftValue[key], rightValue[key]]);
      } else {
        firstDifference = path;
        break;
      }
    }
  } catch {
    firstDifference = "non-json";
  }
  reject(
    "STABLE_PROJECTION_REJECTED",
    `stable projection mismatch at ${firstDifference} expected_sha256=${sha256(expected)} actual_sha256=${sha256(actual)}`,
  );
}

function verifyEvaluatorVerdict(actual, expected) {
  assert(actual === expected, "EVALUATOR_VERDICT_REJECTED", "evaluator verdict mismatch");
}

function executeNegativeControls(runRoot, programs, effectMeter, runCanary) {
  const negativeOwnership = makeOwnedRoot(runRoot, "negative-controls");
  const negative = negativeOwnership.receipt;
  const canaryPath = join(negative.path, "canary");
  const canaryBytes = Buffer.from("P1-055-CANARY\n", "utf8");
  createExclusiveFile(canaryPath, canaryBytes);
  const results = [];
  const record = (id, code, action) => {
    const before = effectSnapshot(effectMeter);
    verifyRunCanary(runCanary);
    expectControlled(code, action);
    assert(sameJson(identityOfBytes(safeReadRegular(canaryPath, undefined, "canary").bytes), identityOfBytes(canaryBytes)), "CANARY_TAMPER_REJECTED", "canary changed");
    verifyRunCanary(runCanary);
    const delta = effectDelta(before, effectSnapshot(effectMeter));
    results.push(standardNegativeResult(
      id,
      code,
      delta.mutation_attempts,
      delta.child_start_attempts,
    ));
  };

  const preexisting = join(negative.path, "preexisting-run-root");
  mkdirSync(preexisting, { mode: 0o700 });
  record("preexisting-run-root", "PREEXISTING_RUN_ROOT_REJECTED", () => createFreshDirectory(negative.path, "preexisting-run-root"));
  const symlinkRoot = join(negative.path, "symlink-run-root");
  symlinkSync(preexisting, symlinkRoot);
  record("symlink-run-root", "SYMLINK_RUN_ROOT_REJECTED", () => createFreshDirectory(negative.path, "symlink-run-root"));
  record("run-root-escape", "RUN_ROOT_ESCAPE_REJECTED", () => directChild(negative.path, "../escape", "RUN_ROOT_ESCAPE_REJECTED"));

  const targetFixture = createFreshDirectory(negative.path, "target-fixtures").path;
  const targetBase = join(targetFixture, "base");
  createExclusiveFile(targetBase, Buffer.from("base\n"));
  chmodSync(targetBase, 0o644);
  const targetLink = join(targetFixture, "target-symlink");
  symlinkSync(targetBase, targetLink);
  record("target-symlink", "TARGET_SYMLINK_REJECTED", () => validateTarget(targetLink, identityOfBytes(Buffer.from("base\n"))));
  const hardTarget = join(targetFixture, "target-hardlink");
  linkSync(targetBase, hardTarget);
  record("target-hardlink", "TARGET_NLINK_REJECTED", () => validateTarget(hardTarget, identityOfBytes(Buffer.from("base\n"))));
  const driftTarget = join(targetFixture, "target-preimage-drift");
  createExclusiveFile(driftTarget, Buffer.from("drift\n"));
  chmodSync(driftTarget, 0o644);
  record("target-preimage-drift", "TARGET_PREIMAGE_DRIFT_REJECTED", () => validateTarget(driftTarget, identityOfBytes(Buffer.from("base\n"))));
  const modeTarget = join(targetFixture, "target-mode-drift");
  createExclusiveFile(modeTarget, Buffer.from("base\n"));
  chmodSync(modeTarget, 0o600);
  record("target-mode-drift", "TARGET_MODE_DRIFT_REJECTED", () => validateTarget(modeTarget, identityOfBytes(Buffer.from("base\n"))));
  const markerFixture = makeOwnedRoot(negative.path, "marker-fixture");
  const forgedMarkerFixture = {
    ...markerFixture,
    marker: { ...markerFixture.marker, sha256: "0".repeat(64) },
  };
  record("unowned-materialization-marker", "MATERIALIZATION_OWNERSHIP_REJECTED", () => verifyOwnedDirectory(forgedMarkerFixture));

  const sidecar = join(targetFixture, ".sidecar");
  createExclusiveFile(sidecar, Buffer.from("owned\n"));
  record("preexisting-sidecar", "PREEXISTING_SIDECAR_REJECTED", () => createExclusiveFile(sidecar, Buffer.from("new\n"), 0o644, "PREEXISTING_SIDECAR_REJECTED", "SYMLINK_SIDECAR_REJECTED"));
  const sidecarLink = join(targetFixture, ".sidecar-link");
  symlinkSync(targetBase, sidecarLink);
  record("symlink-sidecar", "SYMLINK_SIDECAR_REJECTED", () => createExclusiveFile(sidecarLink, Buffer.from("new\n"), 0o644, "PREEXISTING_SIDECAR_REJECTED", "SYMLINK_SIDECAR_REJECTED"));

  const evidence = createFreshDirectory(negative.path, "evidence-fixtures").path;
  const evidenceLeaf = join(evidence, "leaf");
  createExclusiveFile(evidenceLeaf, Buffer.from("evidence\n"));
  record("preexisting-evidence-leaf", "PREEXISTING_EVIDENCE_LEAF_REJECTED", () => createExclusiveFile(evidenceLeaf, Buffer.from("new\n")));
  const evidenceLink = join(evidence, "link");
  symlinkSync(evidenceLeaf, evidenceLink);
  record("symlink-evidence-leaf", "SYMLINK_EVIDENCE_LEAF_REJECTED", () => createExclusiveFile(evidenceLink, Buffer.from("new\n")));
  const evidenceHard = join(evidence, "hard");
  linkSync(evidenceLeaf, evidenceHard);
  record("hardlink-evidence-leaf", "EVIDENCE_NLINK_REJECTED", () => {
    const stat = lstatSync(evidenceHard);
    assert(stat.nlink === 1, "EVIDENCE_NLINK_REJECTED", "Evidence nlink is not one");
  });
  record("evidence-path-escape", "EVIDENCE_PATH_ESCAPE_REJECTED", () => directChild(evidence, "../escape", "EVIDENCE_PATH_ESCAPE_REJECTED"));
  const changedPathFixture = createFreshDirectory(negative.path, "changed-path-fixture").path;
  createExclusiveFile(join(changedPathFixture, "range.mjs"), Buffer.from("range\n"));
  createExclusiveFile(join(changedPathFixture, "extra.mjs"), Buffer.from("extra\n"));
  record("extra-changed-path", "CHANGED_PATH_SCOPE_REJECTED", () => verifyDirectoryEntries(changedPathFixture, ["range.mjs"], "CHANGED_PATH_SCOPE_REJECTED"));
  const unexpectedFileFixture = createFreshDirectory(negative.path, "unexpected-file-fixture").path;
  createExclusiveFile(join(unexpectedFileFixture, "expected"), Buffer.from("expected\n"));
  createExclusiveFile(join(unexpectedFileFixture, "unexpected"), Buffer.from("unexpected\n"));
  record("unexpected-new-file", "UNEXPECTED_NEW_FILE_REJECTED", () => verifyDirectoryEntries(unexpectedFileFixture, ["expected"], "UNEXPECTED_NEW_FILE_REJECTED"));

  const ir01 = PROGRAM_TABLE.find((program) => program.id === "IR01");
  const ir01Result = compileFiniteTypedPatchIr(programs.get("IR01"));
  const identityObservation = {
    program_id: "IR01",
    program_length: ir01.byte_length,
    program_sha256: ir01.sha256,
    outcome_id: ir01Result.outcome_id,
    outcome_kind: ir01Result.kind,
    postimage_bytes_or_null: ir01Result.postimage,
    mutation_attempts: 0,
    child_start_attempts: 0,
    changed_paths: [],
    test_statuses: null,
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
  };
  record("identity-forged-mutation", "IDENTITY_EFFECT_REJECTED", () => evaluateBoundedObservation({ ...identityObservation, mutation_attempts: 1 }));
  record("identity-forged-child", "IDENTITY_CHILD_START_REJECTED", () => evaluateBoundedObservation({ ...identityObservation, child_start_attempts: 1 }));

  const tamperedCanaryPath = join(negative.path, "tampered-canary");
  createExclusiveFile(tamperedCanaryPath, Buffer.from("P1-055-TAMPERED\n", "utf8"));
  record("canary-tamper", "CANARY_TAMPER_REJECTED", () => verifyCanaryBytes(tamperedCanaryPath, canaryBytes));

  const cleanupOwnership = makeOwnedRoot(negative.path, "cleanup-ownership-fixture");
  record("cleanup-ownership-drift", "CLEANUP_OWNERSHIP_REJECTED", () => removeOwnedDirectory(
    cleanupOwnership.receipt,
    cleanupOwnership.markerPath,
    { ...cleanupOwnership.marker, sha256: "0".repeat(64) },
  ));
  assert(lstatSync(cleanupOwnership.receipt.path).isDirectory(), "NEGATIVE_MATRIX_REJECTED", "ownership-drift fixture was deleted");
  const cleanupIdentity = makeOwnedRoot(negative.path, "cleanup-identity-fixture");
  record("cleanup-identity-drift", "CLEANUP_IDENTITY_REJECTED", () => removeOwnedDirectory(
    { ...cleanupIdentity.receipt, ino: cleanupIdentity.receipt.ino + 1 },
    cleanupIdentity.markerPath,
    cleanupIdentity.marker,
  ));
  assert(lstatSync(cleanupIdentity.receipt.path).isDirectory(), "NEGATIVE_MATRIX_REJECTED", "identity-drift fixture was deleted");
  const rootIdentity = createFreshDirectory(negative.path, "root-identity-fixture");
  record("root-identity-drift", "ROOT_IDENTITY_DRIFT_REJECTED", () => verifyDirectoryIdentity(
    { ...rootIdentity, ino: rootIdentity.ino + 1 },
    "ROOT_IDENTITY_DRIFT_REJECTED",
  ));
  const targetIdentityPath = join(negative.path, "target-identity-fixture");
  const targetIdentityReceipt = createExclusiveFile(targetIdentityPath, Buffer.from("first\n"));
  const displacedTargetPath = join(negative.path, "target-identity-displaced");
  renameSync(targetIdentityPath, displacedTargetPath);
  createExclusiveFile(targetIdentityPath, Buffer.from("second\n"));
  record("target-identity-drift", "TARGET_IDENTITY_DRIFT_REJECTED", () => verifyFileReceipt(
    targetIdentityPath,
    targetIdentityReceipt,
    "TARGET_IDENTITY_DRIFT_REJECTED",
  ));

  const ir10 = PROGRAM_TABLE.find((program) => program.id === "IR10");
  const ir10Result = compileFiniteTypedPatchIr(programs.get("IR10"));
  const validObservation = {
    program_id: "IR10",
    program_length: ir10.byte_length,
    program_sha256: ir10.sha256,
    outcome_id: ir10Result.outcome_id,
    outcome_kind: ir10Result.kind,
    postimage_bytes_or_null: ir10Result.postimage,
    mutation_attempts: 1,
    child_start_attempts: 2,
    changed_paths: ["src/range.mjs"],
    test_statuses: { issue: 0, regression: 0 },
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
  };
  record("nonfrozen-postimage", "POSTIMAGE_IDENTITY_REJECTED", () => evaluateObservation({ ...validObservation, postimage_bytes_or_null: Buffer.from("tamper\n") }));
  record("wrong-outcome-id", "OUTCOME_BINDING_REJECTED", () => evaluateObservation({ ...validObservation, outcome_id: "SAFE_WRONG_END_END" }));
  record("forged-test-status", "OBSERVATION_MISMATCH_REJECTED", () => evaluateObservation({ ...validObservation, test_statuses: { issue: 1, regression: 0 } }));
  const expectedCandidate = {
    candidate_commit: "1".repeat(40),
    candidate_tree: "2".repeat(40),
    candidate_manifest_sha256: "3".repeat(64),
    quality_freeze_manifest_sha256: QUALITY_MANIFEST_SHA256,
  };
  record("candidate-binding-drift", "CANDIDATE_BINDING_REJECTED", () => evaluateCandidateBinding({ ...expectedCandidate, candidate_tree: "4".repeat(40) }, expectedCandidate));
  record("missing-required-action", "ACTION_SCHEDULE_REJECTED", () => evaluateRunObservation({ ordered_action_ids: [] }, expectedCandidate));
  record("stable-projection-tamper", "STABLE_PROJECTION_REJECTED", () => verifyStableProjectionBytes(
    canonicalJsonBytes({ stable: true }),
    canonicalJsonBytes({ stable: false }),
  ));
  record("evaluator-verdict-tamper", "EVALUATOR_VERDICT_REJECTED", () => verifyEvaluatorVerdict("REJECT_SAFE_WRONG", "PASS_ONLY_SUCCESS"));

  assert(results.length === NEGATIVE_EXPECTATIONS.length, "NEGATIVE_MATRIX_REJECTED", "negative population incomplete");
  for (let index = 0; index < NEGATIVE_EXPECTATIONS.length; index += 1) {
    assert(results[index].id === NEGATIVE_EXPECTATIONS[index][0], "NEGATIVE_MATRIX_REJECTED", "negative order mismatch");
  }
  const evaluated = evaluateNegativeResults(results);
  removeOwnedDirectory(negativeOwnership.receipt, negativeOwnership.markerPath, negativeOwnership.marker);
  verifyRunCanary(runCanary);
  return evaluated;
}

function commandProjection(records, materializationRoot) {
  return records.map((record) => {
    const normalizeForStableProjection = (bytes) => {
      const oracleNormalized = normalizeCommandStream(bytes, materializationRoot).toString("utf8");
      return Buffer.from(
        oracleNormalized.replace(/duration_ms(?::\s*|\s+)[0-9]+(?:\.[0-9]+)?/g, "duration_ms: <DURATION_MS>"),
        "utf8",
      );
    };
    const stdout = normalizeForStableProjection(record.stdout);
    const stderr = normalizeForStableProjection(record.stderr);
    return {
      action_id: record.action_id,
      argv: record.argv,
      exit_status: record.exit_status,
      signal: record.signal,
      normalized_stdout_byte_length: stdout.length,
      normalized_stdout_sha256: sha256(stdout),
      normalized_stderr_byte_length: stderr.length,
      normalized_stderr_sha256: sha256(stderr),
      normalization_transform_id: "EXACT_MATERIALIZATION_ROOT_TO_PLACEHOLDER_AND_NODE_TAP_DURATION_MS_TO_PLACEHOLDER_ONLY",
      normalization_residual_physical_variants: 0,
    };
  });
}

function rawCommandRecords(records) {
  return records.map((record) => ({
    action_id: record.action_id,
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
  }));
}

function exactCandidateFileRecords() {
  return ALLOWED_CHANGED_PATHS.map((path) => {
    const file = safeReadRegular(join(REPOSITORY_ROOT, path), undefined, `candidate file ${path}`);
    const filesystemMode = (file.stat.mode & 0o111) === 0 ? "100644" : "100755";
    return { path, mode: filesystemMode, ...identityOfBytes(file.bytes) };
  });
}

function validateCandidateManifest(candidateManifestPath, runId) {
  assert(isAbsolute(candidateManifestPath), "CANDIDATE_BINDING_REJECTED", "candidate manifest path is not absolute");
  const file = safeReadRegular(candidateManifestPath, undefined, "candidate manifest");
  let value;
  try {
    value = JSON.parse(file.bytes.toString("utf8"));
  } catch {
    reject("CANDIDATE_BINDING_REJECTED", "candidate manifest is not JSON");
  }
  assert(file.bytes.equals(canonicalJsonBytes(value)), "CANDIDATE_BINDING_REJECTED", "candidate manifest is not canonical JSON bytes");
  const requiredKeys = [
    "schema_version",
    "record_type",
    "task_id",
    "activation_parent_commit",
    "candidate_commit",
    "candidate_tree",
    "binary_diff_byte_length",
    "binary_diff_sha256",
    "allowed_changed_paths_sorted",
    "files_sorted_by_path",
    "contract_identity",
    "task_card_identity",
    "program_identities",
    "quality_oracle_identity",
    "quality_freeze_receipt_identity",
    "quality_freeze_manifest_sha256",
    "clean_status",
    "post_freeze_mutation",
  ].sort();
  assert(sameJson(Object.keys(value).sort(), requiredKeys), "CANDIDATE_BINDING_REJECTED", "candidate manifest field set mismatch");
  assert(value.schema_version === 1, "CANDIDATE_BINDING_REJECTED", "candidate manifest schema mismatch");
  assert(value.record_type === "sourcelens_aios_p1_055_exact_candidate_manifest", "CANDIDATE_BINDING_REJECTED", "candidate manifest record type mismatch");
  assert(value.task_id === TASK_ID, "CANDIDATE_BINDING_REJECTED", "candidate Task binding mismatch");
  assert(value.activation_parent_commit === ACTIVATION_PARENT_COMMIT, "CANDIDATE_BINDING_REJECTED", "activation parent mismatch");
  assert(/^[0-9a-f]{40}$/.test(value.candidate_commit), "CANDIDATE_BINDING_REJECTED", "candidate commit shape mismatch");
  assert(/^[0-9a-f]{40}$/.test(value.candidate_tree), "CANDIDATE_BINDING_REJECTED", "candidate tree shape mismatch");
  assert(Number.isSafeInteger(value.binary_diff_byte_length) && value.binary_diff_byte_length >= 0, "CANDIDATE_BINDING_REJECTED", "candidate diff length invalid");
  assert(/^[0-9a-f]{64}$/.test(value.binary_diff_sha256), "CANDIDATE_BINDING_REJECTED", "candidate diff hash invalid");
  assert(value.clean_status === "clean" && value.post_freeze_mutation === false, "CANDIDATE_BINDING_REJECTED", "candidate freeze state mismatch");
  assert(value.quality_freeze_manifest_sha256 === QUALITY_MANIFEST_SHA256, "CANDIDATE_BINDING_REJECTED", "candidate Quality manifest binding mismatch");
  assert(sameJson(value.allowed_changed_paths_sorted, ALLOWED_CHANGED_PATHS), "CANDIDATE_BINDING_REJECTED", "candidate allowed path list mismatch");
  assert(sameJson(value.contract_identity, CONTRACT_IDENTITY_RECORD), "CANDIDATE_BINDING_REJECTED", "candidate Contract identity mismatch");
  assert(sameJson(value.task_card_identity, TASK_CARD_IDENTITY_RECORD), "CANDIDATE_BINDING_REJECTED", "candidate Task Card identity mismatch");
  assert(sameJson(value.program_identities, PROGRAM_IDENTITY_RECORDS), "CANDIDATE_BINDING_REJECTED", "candidate program identities mismatch");
  assert(sameJson(value.quality_oracle_identity, QUALITY_ORACLE_IDENTITY_RECORD), "CANDIDATE_BINDING_REJECTED", "candidate Quality oracle identity mismatch");
  assert(sameJson(value.quality_freeze_receipt_identity, QUALITY_RECEIPT_IDENTITY_RECORD), "CANDIDATE_BINDING_REJECTED", "candidate Quality receipt identity mismatch");
  safeReadRegular(QUALITY_MANIFEST_PATH, QUALITY_MANIFEST_IDENTITY, "Quality freeze manifest");
  safeReadRegular(QUALITY_RECEIPT_PATH, QUALITY_RECEIPT_IDENTITY, "Quality freeze receipt");
  const manifestSha256 = sha256(file.bytes);
  assert(
    process.env.SOURCELENS_P1_055_PRELOAD_STATUS === "PASS" &&
      process.env.SOURCELENS_P1_055_PRELOAD_COMMIT === value.candidate_commit &&
      process.env.SOURCELENS_P1_055_PRELOAD_TREE === value.candidate_tree &&
      process.env.SOURCELENS_P1_055_PRELOAD_MANIFEST_SHA256 === manifestSha256 &&
      process.env.SOURCELENS_P1_055_PRELOAD_DIFF_BYTE_LENGTH === String(value.binary_diff_byte_length) &&
      process.env.SOURCELENS_P1_055_PRELOAD_DIFF_SHA256 === value.binary_diff_sha256 &&
      process.env.SOURCELENS_P1_055_PRELOAD_RUN_ID === runId,
    "CANDIDATE_BINDING_REJECTED",
    "external pre-load candidate binding missing or mismatched",
  );
  const fileRecords = exactCandidateFileRecords();
  assert(sameJson(value.files_sorted_by_path, fileRecords), "CANDIDATE_BINDING_REJECTED", "candidate file identity records mismatch");
  return {
    value,
    binding: {
      candidate_commit: value.candidate_commit,
      candidate_tree: value.candidate_tree,
      candidate_manifest_sha256: manifestSha256,
      quality_freeze_manifest_sha256: QUALITY_MANIFEST_SHA256,
    },
    identity: identityOfBytes(file.bytes),
  };
}

function executeConformance(
  runOwnership,
  frozen,
  candidateBinding,
  actionLedger,
  compilerTcb,
  effectMeter,
) {
  assert(sameJson(actionLedger, REQUIRED_ACTIONS.slice(0, 3)), "ACTION_SCHEDULE_REJECTED", "conformance preflight action schedule mismatch");
  verifyOwnedDirectory(runOwnership, "ROOT_IDENTITY_DRIFT_REJECTED", "MATERIALIZATION_OWNERSHIP_REJECTED");
  const runRoot = runOwnership.receipt.path;
  const startedAtMs = Date.now();
  const commandRecords = [];
  const runCanaryBytes = Buffer.from("P1-055-RUN-CANARY\n", "utf8");
  const runCanaryPath = join(runRoot, "run-canary");
  const runCanaryReceipt = createExclusiveFile(runCanaryPath, runCanaryBytes, 0o600);
  const runCanary = { path: runCanaryPath, bytes: runCanaryBytes, receipt: runCanaryReceipt };
  verifyRunCanary(runCanary);
  const closureEffectsBefore = effectSnapshot(effectMeter);
  const closure = evaluateByteClosureCompiler(compileFiniteTypedPatchIr);
  verifyRunCanary(runCanary);
  const closureEffects = effectDelta(closureEffectsBefore, effectSnapshot(effectMeter));
  assert(
    closureEffects.mutation_attempts === 0 && closureEffects.child_start_attempts === 0,
    "COMPILER_FALSE_ACCEPT",
    "byte closure reached a mutation or child-start sink",
  );
  completeAction(actionLedger, "execute_exhaustive_byte_closure");
  const malformedEffectsBefore = effectSnapshot(effectMeter);
  const malformed = evaluateMalformedPayloadCompiler(compileFiniteTypedPatchIr);
  verifyRunCanary(runCanary);
  const malformedEffects = effectDelta(malformedEffectsBefore, effectSnapshot(effectMeter));
  assert(
    malformedEffects.mutation_attempts === 0 && malformedEffects.child_start_attempts === 0,
    "COMPILER_FALSE_ACCEPT",
    "malformed payload reached a mutation or child-start sink",
  );
  completeAction(actionLedger, "execute_explicit_malformed_payload_matrix");
  const negativeResults = executeNegativeControls(runRoot, frozen.programs, effectMeter, runCanary);
  completeAction(actionLedger, "execute_filesystem_evidence_canary_matrix");
  const materialized = materialize(runRoot, commandRecords, effectMeter);
  completeAction(actionLedger, "materialize_fresh_rep001_repository");
  verifyOwnedDirectory(materialized.repositoryOwnership);
  completeAction(actionLedger, "verify_frozen_base_and_clean_state");
  const baseIssue = executeTest("base_issue_test", materialized.repository, materialized.env, "test/issue.test.mjs", 1, commandRecords, effectMeter);
  assertTypedBaseFailure(baseIssue);
  const baseRegression = executeTest("base_regression_test", materialized.repository, materialized.env, "test/regression.test.mjs", 0, commandRecords, effectMeter);
  completeAction(actionLedger, "execute_base_issue_and_regression_tests");
  const outcomes = executeProgramOutcomes(materialized, frozen.programs, commandRecords, actionLedger, runCanary, effectMeter);
  assert(sameJson(actionLedger, REQUIRED_ACTIONS.slice(0, 13)), "ACTION_SCHEDULE_REJECTED", "engineering action schedule mismatch");
  verifyOwnedDirectory(runOwnership, "ROOT_IDENTITY_DRIFT_REJECTED", "MATERIALIZATION_OWNERSHIP_REJECTED");
  verifyCanaryBytes(runCanary.path, runCanary.bytes);
  return {
    closure,
    malformed,
    negativeResults,
    commandRecords,
    commandProjection: commandProjection(commandRecords, materialized.repository),
    baseTestStatuses: { issue: baseIssue.exit_status, regression: baseRegression.exit_status },
    rawProgramObservations: outcomes.rawObservations,
    rollbacks: outcomes.rollbacks,
    materialized,
    actionLedger,
    compilerTcb,
    startedAtMs,
    runCanary,
    closureEffects,
    malformedEffects,
  };
}

function writeEvidence(runOwnership, runId, frozen, candidate, execution) {
  const runRoot = runOwnership.receipt.path;
  const artifacts = {};
  const malformedEvidence = execution.malformed.map((result) => ({
    ...result,
    mutation_attempts: execution.malformedEffects.mutation_attempts,
    child_start_attempts: execution.malformedEffects.child_start_attempts,
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
  }));
  const writeJson = (name, value) => {
    const bytes = canonicalJsonBytes(value);
    artifacts[name] = createExclusiveFile(join(runRoot, name), bytes, 0o600);
    return { ...artifacts[name], ...identityOfBytes(bytes) };
  };
  const commands = writeJson("commands.json", rawCommandRecords(execution.commandRecords));
  const closure = writeJson("byte-closure.json", {
    byte_closure: execution.closure,
    byte_closure_rejection_effect_observation: {
      mutation_attempts: execution.closureEffects.mutation_attempts,
      child_start_attempts: execution.closureEffects.child_start_attempts,
      canary_status: "UNCHANGED",
      external_effects: FALSE_EFFECTS,
    },
    explicit_malformed_payload_matrix: malformedEvidence,
  });
  const rollback = writeJson("rollback.json", execution.rollbacks);
  completeAction(execution.actionLedger, "emit_create_once_raw_evidence");
  const completedSchedule = [...execution.actionLedger, "emit_stable_projection"];
  const runObservation = {
    ordered_action_ids: completedSchedule,
    candidate_binding: candidate.binding,
    base_test_statuses: execution.baseTestStatuses,
    program_observations: execution.rawProgramObservations,
    byte_closure: execution.closure,
    negative_case_results: execution.negativeResults,
    rollback_observations: execution.rollbacks,
    compiler_tcb_status: execution.compilerTcb,
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
  };
  const semanticProjection = evaluateRunObservation(runObservation, candidate.binding);
  const commandField = (key) => execution.commandProjection.map((record) => ({ action_id: record.action_id, value: record[key] }));
  const malformedBytes = canonicalJsonBytes(malformedEvidence);
  const stableValue = {
    schema_version: semanticProjection.schema_version,
    task_id: semanticProjection.task_id,
    control_id: semanticProjection.control_id,
    candidate_commit: candidate.binding.candidate_commit,
    candidate_tree: candidate.binding.candidate_tree,
    candidate_manifest_sha256: candidate.binding.candidate_manifest_sha256,
    quality_freeze_manifest_sha256: QUALITY_MANIFEST_SHA256,
    input_identities: {
      contract: CONTRACT_IDENTITY_RECORD,
      task_card: TASK_CARD_IDENTITY_RECORD,
      quality_oracle: QUALITY_ORACLE_IDENTITY_RECORD,
      quality_receipt: QUALITY_RECEIPT_IDENTITY_RECORD,
      programs: PROGRAM_IDENTITY_RECORDS,
      ...frozen.input_identities,
    },
    ordered_action_ids: completedSchedule,
    command_argv: commandField("argv"),
    command_exit_status: commandField("exit_status"),
    command_signal: commandField("signal"),
    normalized_stdout_byte_length: commandField("normalized_stdout_byte_length"),
    normalized_stdout_sha256: commandField("normalized_stdout_sha256"),
    normalized_stderr_byte_length: commandField("normalized_stderr_byte_length"),
    normalized_stderr_sha256: commandField("normalized_stderr_sha256"),
    normalization_transform_id: "EXACT_MATERIALIZATION_ROOT_TO_PLACEHOLDER_AND_NODE_TAP_DURATION_MS_TO_PLACEHOLDER_ONLY",
    normalization_residual_physical_variants: 0,
    program_outcomes: semanticProjection.program_outcomes,
    base_test_statuses: semanticProjection.base_test_statuses,
    patched_test_statuses: execution.rawProgramObservations.map((observation) => ({
      program_id: observation.program_id,
      test_statuses: observation.test_statuses,
    })),
    changed_paths_sorted: execution.rawProgramObservations.map((observation) => ({
      program_id: observation.program_id,
      changed_paths: [...observation.changed_paths].sort(),
    })),
    byte_closure_counts: {
      ...semanticProjection.byte_closure_counts,
      explicit_malformed_payload_count: malformedEvidence.length,
      explicit_malformed_payload_sha256: sha256(malformedBytes),
    },
    byte_closure_stream_sha256: semanticProjection.byte_closure_stream_sha256,
    negative_case_results: semanticProjection.negative_case_results,
    false_accepts: semanticProjection.false_accepts,
    mutation_attempts_on_rejections: semanticProjection.mutation_attempts_on_rejections,
    child_start_attempts_on_rejections: semanticProjection.child_start_attempts_on_rejections,
    compiler_tcb_status: semanticProjection.compiler_tcb_status,
    canary_status: semanticProjection.canary_status,
    external_effects: semanticProjection.external_effects,
    per_program_rollback: semanticProjection.per_program_rollback,
    verdict: semanticProjection.verdict,
  };
  const declaredStableKeys = JSON.parse(frozen.task_card.bytes.toString("utf8")).stable_projection.include.sort();
  assert(sameJson(Object.keys(stableValue).sort(), declaredStableKeys), "STABLE_PROJECTION_REJECTED", "stable projection field set drift");
  const stableBytes = canonicalJsonBytes(stableValue);
  for (const physicalValue of [
    runRoot,
    realpathSync(runRoot),
    execution.materialized.repository,
    execution.materialized.homeReceipt.path,
  ]) {
    assert(!stableBytes.includes(Buffer.from(physicalValue, "utf8")), "STABLE_PROJECTION_REJECTED", "physical path survived stable projection");
  }
  artifacts["stable-projection.json"] = createExclusiveFile(join(runRoot, "stable-projection.json"), stableBytes, 0o600);
  const stable = { ...artifacts["stable-projection.json"], ...identityOfBytes(stableBytes) };
  completeAction(execution.actionLedger, "emit_stable_projection");
  assert(sameJson(execution.actionLedger, completedSchedule), "ACTION_SCHEDULE_REJECTED", "final action schedule drift");
  const finishedAtMs = Date.now();
  const runStat = lstatSync(runRoot);
  const materializationStat = lstatSync(execution.materialized.repository);
  verifyOwnedDirectory(runOwnership, "ROOT_IDENTITY_DRIFT_REJECTED", "MATERIALIZATION_OWNERSHIP_REJECTED");
  verifyOwnedDirectory(execution.materialized.repositoryOwnership);
  verifyCanaryBytes(execution.runCanary.path, execution.runCanary.bytes);
  const resultValue = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_055_run_result",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    physical_path: runRoot,
    realpath: realpathSync(runRoot),
    device: runStat.dev,
    inode: runStat.ino,
    pid: process.pid,
    started_at_utc: new Date(execution.startedAtMs).toISOString(),
    finished_at_utc: new Date(finishedAtMs).toISOString(),
    duration_ms: finishedAtMs - execution.startedAtMs,
    candidate_binding: candidate.binding,
    evidence_root: { physical_path: dirname(dirname(runRoot)), realpath: realpathSync(dirname(dirname(runRoot))) },
    materialization: {
      physical_path: execution.materialized.repository,
      realpath: realpathSync(execution.materialized.repository),
      device: materializationStat.dev,
      inode: materializationStat.ino,
    },
    run_canary: {
      path: execution.runCanary.path,
      ...execution.runCanary.receipt,
      ...identityOfBytes(execution.runCanary.bytes),
      status: "UNCHANGED",
    },
    program_count: 4,
    byte_closure_total: execution.closure.total,
    byte_closure_false_accepts: execution.closure.false_accepts,
    negative_case_count: execution.negativeResults.length,
    stable_projection_sha256: stable.sha256,
    verdict: "PASS",
    claim_boundary: "P1_055_EXACT_LOCAL_SYNTHETIC_CONFORMANCE_RUN_ONLY_NO_TASK_GATE_P1_EXIT_OR_PRODUCTION_CLAIM",
  };
  const result = writeJson("result.json", resultValue);
  const manifestValue = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_055_run_manifest",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    candidate_binding: candidate.binding,
    run_physical_receipt: {
      physical_path: runRoot,
      realpath: realpathSync(runRoot),
      device: runStat.dev,
      inode: runStat.ino,
      pid: process.pid,
      started_at_utc: new Date(execution.startedAtMs).toISOString(),
      finished_at_utc: new Date(finishedAtMs).toISOString(),
      duration_ms: finishedAtMs - execution.startedAtMs,
    },
    artifacts: { commands, closure, rollback, stable, result },
    verdict: "PASS",
  };
  const manifest = writeJson("manifest.json", manifestValue);
  return { result, manifest, stable };
}

function parseArguments(argv) {
  const mode = argv[0];
  assert(mode === "self-test" || mode === "run" || mode === "preflight-diff", "CLI_REJECTED", "unknown mode");
  const values = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    assert(flag?.startsWith("--") && value !== undefined && !values.has(flag), "CLI_REJECTED", "invalid CLI flags");
    values.set(flag, value);
  }
  const allowed = mode === "self-test"
    ? new Set(["--task-card"])
    : mode === "preflight-diff"
      ? new Set(["--expected-byte-length", "--expected-sha256"])
      : new Set(["--task-card", "--candidate-manifest", "--evidence-root", "--run-id"]);
  assert([...values.keys()].every((key) => allowed.has(key)) && values.size === allowed.size, "CLI_REJECTED", "CLI shape mismatch");
  return { mode, values };
}

async function runDiffPreflight(expectedByteLengthArgument, expectedSha256) {
  assert(/^(?:0|[1-9][0-9]*)$/.test(expectedByteLengthArgument), "DIFF_PREFLIGHT_REJECTED", "expected diff length invalid");
  assert(/^[0-9a-f]{64}$/.test(expectedSha256), "DIFF_PREFLIGHT_REJECTED", "expected diff hash invalid");
  const expectedByteLength = Number(expectedByteLengthArgument);
  assert(Number.isSafeInteger(expectedByteLength) && expectedByteLength <= 4 * 1024 * 1024, "DIFF_PREFLIGHT_REJECTED", "expected diff length exceeds frozen buffer");
  const chunks = [];
  let byteLength = 0;
  for await (const chunk of process.stdin) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteLength += bytes.length;
    assert(byteLength <= 4 * 1024 * 1024, "DIFF_PREFLIGHT_REJECTED", "actual diff exceeds frozen buffer");
    chunks.push(bytes);
  }
  const diffBytes = Buffer.concat(chunks, byteLength);
  assert(
    diffBytes.length === expectedByteLength && sha256(diffBytes) === expectedSha256,
    "DIFF_PREFLIGHT_REJECTED",
    "binary diff identity mismatch",
  );
  process.stdout.write(`P1_055_DIFF_PREFLIGHT: PASS byte_length=${diffBytes.length} sha256=${expectedSha256}\n`);
}

async function runSelfTest(taskCardArgument) {
  const preflightActions = [];
  safeReadRegular(fileURLToPath(import.meta.url), undefined, "runner source");
  safeReadRegular(QUALITY_MANIFEST_PATH, QUALITY_MANIFEST_IDENTITY, "Quality freeze manifest");
  safeReadRegular(QUALITY_RECEIPT_PATH, QUALITY_RECEIPT_IDENTITY, "Quality freeze receipt");
  completeAction(preflightActions, "validate_candidate_and_quality_identities");
  const compilerTcb = validateCompilerTcb();
  completeAction(preflightActions, "validate_compiler_tcb");
  const frozenBytes = validateFrozenInputBytes(taskCardArgument);
  validateTool(NODE_TOOL, "Node");
  validateTool(GIT_TOOL, "Git");
  const frozen = selfValidateFrozenInputs(frozenBytes);
  completeAction(preflightActions, "validate_frozen_inputs");
  const temporary = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-055-self-test-"));
  const temporaryStat = lstatSync(temporary);
  const markerBytes = canonicalJsonBytes({ task_id: TASK_ID, token: randomBytes(24).toString("hex") });
  const markerPath = join(temporary, ".sourcelens-p1-055-owner.json");
  const marker = createExclusiveFile(markerPath, markerBytes);
  const ownership = {
    receipt: { path: temporary, dev: temporaryStat.dev, ino: temporaryStat.ino },
    markerPath,
    marker: { ...marker, ...identityOfBytes(markerBytes) },
  };
  try {
    const candidate = {
      binding: {
        candidate_commit: "1".repeat(40),
        candidate_tree: "2".repeat(40),
        candidate_manifest_sha256: "3".repeat(64),
        quality_freeze_manifest_sha256: QUALITY_MANIFEST_SHA256,
      },
    };
    const stableBytes = [];
    let finalExecution;
    for (const suffix of ["a", "b"]) {
      const runOwnership = makeOwnedRoot(temporary, `self-test-run-${suffix}`);
      const actionLedger = [...preflightActions];
      const effectMeter = createEffectMeter();
      const execution = executeConformance(
        runOwnership,
        frozen,
        candidate.binding,
        actionLedger,
        compilerTcb,
        effectMeter,
      );
      const evidence = writeEvidence(runOwnership, `self-test-${suffix}`, frozen, candidate, execution);
      stableBytes.push(safeReadRegular(
        join(runOwnership.receipt.path, "stable-projection.json"),
        { byte_length: evidence.stable.byte_length, sha256: evidence.stable.sha256 },
        `self-test stable ${suffix}`,
      ).bytes);
      finalExecution = execution;
    }
    verifyStableProjectionBytes(stableBytes[0], stableBytes[1]);
    process.stdout.write(
      `P1_055_RUNNER_SELF_TEST: PASS programs=4 closure=${finalExecution.closure.total} ` +
        `false_accepts=${finalExecution.closure.false_accepts} negative=${finalExecution.negativeResults.length} ` +
        `stable_ab_sha256=${sha256(stableBytes[0])}\n`,
    );
  } finally {
    removeOwnedDirectory(ownership.receipt, ownership.markerPath, ownership.marker);
  }
}

async function runFormal(taskCardArgument, candidateManifestPath, evidenceRootArgument, runId) {
  assert(evidenceRootArgument === "/Users/lijunpeng/Developer/.sourcelens-audit/p1-055-finite-typed-patch-ir-20260720T014028Z", "EVIDENCE_ROOT_INVALID", "Evidence root is not authorized");
  const evidenceRoot = assertRealDirectory(evidenceRootArgument, "EVIDENCE_ROOT_INVALID", "Evidence root").path;
  const runsRoot = assertRealDirectory(join(evidenceRoot, "runs"), "EVIDENCE_ROOT_INVALID", "runs root").path;
  assert(RUN_ID_PATTERN.test(runId), "CLI_REJECTED", "run id is unsafe");
  const runOwnership = makeOwnedRoot(runsRoot, runId);
  const effectMeter = createEffectMeter();
  try {
    const actionLedger = [];
    const candidate = validateCandidateManifest(candidateManifestPath, runId);
    completeAction(actionLedger, "validate_candidate_and_quality_identities");
    const compilerTcb = validateCompilerTcb();
    completeAction(actionLedger, "validate_compiler_tcb");
    const frozenBytes = validateFrozenInputBytes(taskCardArgument);
    validateTool(NODE_TOOL, "Node");
    validateTool(GIT_TOOL, "Git");
    const frozen = selfValidateFrozenInputs(frozenBytes);
    completeAction(actionLedger, "validate_frozen_inputs");
    const execution = executeConformance(
      runOwnership,
      frozen,
      candidate.binding,
      actionLedger,
      compilerTcb,
      effectMeter,
    );
    const evidence = writeEvidence(runOwnership, runId, frozen, candidate, execution);
    process.stdout.write(
      `${JSON.stringify({ status: "PASS", task_id: TASK_ID, run_id: runId, result: evidence.result, manifest: evidence.manifest, stable: evidence.stable })}\n`,
    );
  } catch (error) {
    const failure = canonicalJsonBytes({
      schema_version: 1,
      task_id: TASK_ID,
      run_id: runId,
      status: "NON_PASS",
      reason_code: error.code ?? "UNEXPECTED_ERROR",
      message: error.message,
    });
    try {
      createExclusiveFile(join(runOwnership.receipt.path, "failure.json"), failure, 0o600);
    } catch {
      // Preserve the original failure and every already-created object.
    }
    throw error;
  }
}

async function main() {
  const parsed = parseArguments(process.argv.slice(2));
  if (parsed.mode === "preflight-diff") {
    await runDiffPreflight(
      parsed.values.get("--expected-byte-length"),
      parsed.values.get("--expected-sha256"),
    );
  } else if (parsed.mode === "self-test") {
    await runSelfTest(parsed.values.get("--task-card"));
  } else {
    await runFormal(
      parsed.values.get("--task-card"),
      parsed.values.get("--candidate-manifest"),
      parsed.values.get("--evidence-root"),
      parsed.values.get("--run-id"),
    );
  }
}

try {
  await main();
} catch (error) {
  const code = error instanceof ControlledError ? error.code : "UNEXPECTED_ERROR";
  process.stderr.write(`P1_055_RUNNER: NON_PASS ${code} ${error.message}\n`);
  process.exitCode = 2;
}

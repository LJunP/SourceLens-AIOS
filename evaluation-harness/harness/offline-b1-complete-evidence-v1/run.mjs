#!/usr/local/bin/node

import { createHash, randomBytes } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import {
  chmodSync,
  closeSync,
  constants as fsConstants,
  fstatSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  unlinkSync,
  writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ADAPTER_VERSION,
  OfflineB1AdapterError,
  admitOfflineB1ToolPlan,
} from "../../adapters/offline-b1-finite-tool-v1/adapter.mjs";
import {
  QUALITY_ORACLE_VERSION,
  compareStableRuns,
  evaluateRunEvidence,
  validateFiniteToolPlan,
  validateQualityAssets,
  validateTaskCard,
} from "../../evaluator/offline-b1-simple-tool-v1/quality-oracle.mjs";
import { validate as validateSchema } from "../../evaluator/schema-validator.mjs";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(MODULE_DIR, "../../..");
const FIXTURE_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/fixtures/offline-b1-simple-tool-v1");
const TASK_CARD_PATH = join(FIXTURE_ROOT, "task-card.json");
const QUALITY_FREEZE_PATH =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-067-offline-b1-7jPPTE1B/quality-correction-1-final/CORRECTED_QUALITY_FREEZE_MANIFEST.json";
const AUTHORIZED_EVIDENCE_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-067-offline-b1-7jPPTE1B";
const TASK_ID = "AIOS-P1-067_OFFLINE_B1_SIMPLE_TOOL_COMPATIBILITY_ADAPTER_VERTICAL_SLICE";
const CONTROL_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const CLAIM_BOUNDARY =
  "ONE_VISIBLE_SYNTHETIC_REP_001_COOPERATIVE_LOCAL_OFFLINE_B1_FINITE_TYPED_SIMPLE_TOOL_COMPATIBILITY_ADAPTER_COMPLETE_EVIDENCE_OBSERVATION_ONLY_NO_LIVE_MODEL_EMPIRICAL_BASELINE_VTSR_P1_EXIT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM";
const AGENT_STATUS = "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED";
const RUN_ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const NODE_PATH = "/usr/local/bin/node";
const GIT_PATH = "/usr/bin/git";
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const EXPECTED_BASE = Object.freeze({
  commit: "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f",
  tree: "900814727113d65f5dad8b63222e14f39b2cf38b",
  source: Object.freeze({
    byte_length: 115,
    sha256: "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75",
  }),
});
const EXPECTED_POSTIMAGE = Object.freeze({
  byte_length: 127,
  sha256: "e8304b77da9b8c33f64ecdc568db7e97297ace72ecb796971bb3f5eda09d9001",
});
const EXPECTED_IDENTITIES = Object.freeze({
  task_card: Object.freeze({
    byte_length: 17440,
    sha256: "f3bfcdecc1c2a9905fbcf404cccd627bdcf77b092e0f2a66b1b3f005c08b3af3",
  }),
  quality_oracle: Object.freeze({
    byte_length: 162742,
    sha256: "1f50299309c1ab3e7e57e8a2d015bc898323a105a205aad027a14cbca664065c",
  }),
  quality_freeze: Object.freeze({
    byte_length: 5562,
    sha256: "2a07e57f45b95b17b7a5c75c0889429615b8c23589488093d67010bd44d68c37",
  }),
  positive_plan: Object.freeze({
    byte_length: 1583,
    sha256: "8752ffa0a5325c7dcd72697ceeaf878f2b6fbadb8fb44890d215e7b1d85f1b0f",
  }),
  node: Object.freeze({
    byte_length: 193262272,
    sha256: "c5548e7a991a5c90170a29843ffc46df4643e29141f3cbb035f60295cf2bc882",
  }),
  git: Object.freeze({
    byte_length: 118848,
    sha256: "29d5080bd197feb8245ee7d9a275fee4750b5496c6a7016090eff5a357c1e8c4",
  }),
});
const QUALITY_ASSET_IDENTITIES = Object.freeze({
  target_runtime: Object.freeze({ byte_length: 1688, sha256: "482afa2abc0367224b783b5d065a676354e5cff9fb19c8bd7022970ff7dd02c6" }),
  environment_snapshot: Object.freeze({ byte_length: 2087, sha256: "333d30e7a7c960570bec5b409710e4dfba68aa6a46c51c396df5bc248726f149" }),
  system_configuration: Object.freeze({ byte_length: 1108, sha256: "8e7333d5acd3f6ac84d595c91fef3a053f2722e46ac09f4beb54fafe7965e5e9" }),
  compatibility_profile: Object.freeze({ byte_length: 4454, sha256: "6a4f462eab6b46bfc0d675dd902f09b57cf5b8c541e9ef07caadc0675e8ae6b8" }),
  positive_tool_plan: EXPECTED_IDENTITIES.positive_plan,
  negative_cases: Object.freeze({ byte_length: 8704, sha256: "01b88bff780869b5f403348333cdfdd93b889b082eacfa8456efb2ef26fbbd06" }),
});
const QUALITY_ASSET_PATHS = Object.freeze({
  target_runtime: join(FIXTURE_ROOT, "target-runtime-oci-manifest.json"),
  environment_snapshot: join(FIXTURE_ROOT, "environment-snapshot.json"),
  system_configuration: join(FIXTURE_ROOT, "system-configuration.json"),
  compatibility_profile: join(FIXTURE_ROOT, "compatibility-profile.json"),
  positive_tool_plan: join(FIXTURE_ROOT, "positive-tool-plan.json"),
  negative_cases: join(FIXTURE_ROOT, "negative-cases.json"),
});
const RUNNER_RELATIVE_PATH = "evaluation-harness/harness/offline-b1-complete-evidence-v1/run.mjs";
const ADAPTER_RELATIVE_PATH = "evaluation-harness/adapters/offline-b1-finite-tool-v1/adapter.mjs";
const ORACLE_RELATIVE_PATH = "evaluation-harness/evaluator/offline-b1-simple-tool-v1/quality-oracle.mjs";
const TASK_CARD_RELATIVE_PATH = "evaluation-harness/fixtures/offline-b1-simple-tool-v1/task-card.json";
const EXECUTING_MODULE_PATHS = Object.freeze({
  adapter: ADAPTER_RELATIVE_PATH,
  quality_oracle: ORACLE_RELATIVE_PATH,
  runner: RUNNER_RELATIVE_PATH,
  task_card: TASK_CARD_RELATIVE_PATH,
});
const SOURCE_INPUTS = Object.freeze({
  source_preimage: Object.freeze({
    relative_path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/src/range.mjs",
    destination: "src/range.mjs",
    byte_length: 115,
    sha256: EXPECTED_BASE.source.sha256,
  }),
  issue_test: Object.freeze({
    relative_path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/test/issue.test.mjs",
    destination: "test/issue.test.mjs",
    byte_length: 237,
    sha256: "51fd472f8cf85fd595246814db29699ab81ccdc2986d80666d8609a8c4972b4b",
  }),
  regression_test: Object.freeze({
    relative_path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/test/regression.test.mjs",
    destination: "test/regression.test.mjs",
    byte_length: 241,
    sha256: "381c573d8f99305b47db9f1a2ca49779842fe1187b9d7c5b7410e56dda9240c5",
  }),
});
const TASK_SPEC = Object.freeze({
  relative_path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/task-spec.json",
  byte_length: 2960,
  sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
});
const IR10 = Object.freeze({
  relative_path: "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json",
  byte_length: 255,
  sha256: "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc",
});
const COMMANDS = Object.freeze([
  Object.freeze({ action_id: "base_issue_test", phase: "BASE_PRECONDITION", tool_ordinal: null, argv: Object.freeze([NODE_PATH, "--test", "test/issue.test.mjs"]), expected_exit_status: 1, stdout_path: "base-issue.stdout", stderr_path: "base-issue.stderr" }),
  Object.freeze({ action_id: "base_regression_test", phase: "BASE_PRECONDITION", tool_ordinal: null, argv: Object.freeze([NODE_PATH, "--test", "test/regression.test.mjs"]), expected_exit_status: 0, stdout_path: "base-regression.stdout", stderr_path: "base-regression.stderr" }),
  Object.freeze({ action_id: "tool_issue_test", phase: "TOOL_ACTION", tool_ordinal: 2, argv: Object.freeze([NODE_PATH, "--test", "test/issue.test.mjs"]), expected_exit_status: 0, stdout_path: "tool-issue.stdout", stderr_path: "tool-issue.stderr" }),
  Object.freeze({ action_id: "tool_regression_test", phase: "TOOL_ACTION", tool_ordinal: 3, argv: Object.freeze([NODE_PATH, "--test", "test/regression.test.mjs"]), expected_exit_status: 0, stdout_path: "tool-regression.stdout", stderr_path: "tool-regression.stderr" }),
]);
const ARTIFACT_LAYOUT = Object.freeze([
  Object.freeze({ role: "candidate_provenance", path: "candidate-provenance.json" }),
  Object.freeze({ role: "tool_plan", path: "tool-plan.json" }),
  Object.freeze({ role: "observation", path: "observation.json" }),
  Object.freeze({ role: "patch", path: "patch.diff" }),
  Object.freeze({ role: "rollback", path: "rollback.json" }),
  Object.freeze({ role: "actual_executor", path: "actual-executor.json" }),
  Object.freeze({ role: "action_trace", path: "action-trace.json" }),
  Object.freeze({ role: "patch_evidence_package", path: "patch-evidence-package.json" }),
  Object.freeze({ role: "run_record", path: "run-record.json" }),
  Object.freeze({ role: "command_stream", path: "command-stream.json" }),
  ...COMMANDS.flatMap((command) => [
    Object.freeze({ role: "raw_stream", path: command.stdout_path }),
    Object.freeze({ role: "raw_stream", path: command.stderr_path }),
  ]),
]);
const PATCH_BYTES = Buffer.from(
  "diff --git a/src/range.mjs b/src/range.mjs\n" +
    "index 67aedf5..026768c 100644\n" +
    "--- a/src/range.mjs\n" +
    "+++ b/src/range.mjs\n" +
    "@@ -1,4 +1,4 @@\n" +
    " export function normalizeRange(start, end) {\n" +
    "   if (start <= end) return { start, end };\n" +
    "-  return { start, end };\n" +
    "+  return { start: end, end: start };\n" +
    " }\n",
  "utf8",
);
const FIXED_ENV = Object.freeze({
  PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
  LANG: "C",
  LC_ALL: "C",
  TZ: "UTC",
});

class RunnerError extends Error {
  constructor(code, message, details = undefined) {
    super(message);
    this.name = "RunnerError";
    this.code = code;
    this.details = details;
  }
}

class ManagedProcessError extends RunnerError {
  constructor(code, message, outcome) {
    super(code, message, outcome);
    this.name = "ManagedProcessError";
    this.outcome = outcome;
  }
}

const fail = (code, message, details = undefined) => { throw new RunnerError(code, message, details); };
const assert = (condition, code, message, details = undefined) => { if (!condition) fail(code, message, details); };
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const identityOf = (bytes) => ({ byte_length: bytes.length, sha256: sha256(bytes) });
const canonicalize = (value) => {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
};
const canonicalJsonBytes = (value) => Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
const sameJson = (left, right) => JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right));
const delay = (milliseconds) => new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

function exactStream(bytes, artifactRef = null) {
  return {
    retention: "INLINE_EXACT_BYTES",
    encoding: "base64",
    bytes_base64: bytes.toString("base64"),
    byte_length: bytes.length,
    sha256: sha256(bytes),
    artifact_ref: artifactRef,
  };
}

function recordAction(trace, actionId, category, phase, toolOrdinal, request, outcome) {
  const action = {
    sequence: trace.length + 1,
    action_id: actionId,
    category,
    phase,
    tool_ordinal: toolOrdinal,
    request,
    outcome,
  };
  trace.push(action);
  return action;
}

function recordProcessAction(trace, actionId, phase, toolOrdinal, argv, cwdRef, timeoutMs,
  expectedExitStatus, outcome, streamRefs = {}) {
  return recordAction(
    trace,
    actionId,
    "PROCESS",
    phase,
    toolOrdinal,
    {
      executable: argv[0],
      argv: [...argv],
      cwd_ref: cwdRef,
      timeout_ms: timeoutMs,
      environment_profile: "FIXED_MINIMAL_NON_SECRET",
      shell: false,
    },
    {
      status: "COMPLETED",
      expected_exit_status: expectedExitStatus,
      exit_status: outcome.exit_status,
      signal: outcome.signal,
      terminated: outcome.terminated,
      descendants_alive: outcome.descendants_alive,
      stdout: exactStream(outcome.stdout, streamRefs.stdout ?? null),
      stderr: exactStream(outcome.stderr, streamRefs.stderr ?? null),
    },
  );
}

function exactKeys(value, expected, code, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), code, `${label} is not an object`);
  assert(sameJson(Object.keys(value).sort(), [...expected].sort()), code, `${label} key set drifted`);
}

function parseJson(bytes, code, label, canonicalRequired = false) {
  assert(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 1_048_576, code, `${label} length is invalid`);
  let text;
  try { text = new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch { fail(code, `${label} is not exact UTF-8`); }
  let value;
  try { value = JSON.parse(text); } catch { fail(code, `${label} is not valid JSON`); }
  if (canonicalRequired) assert(canonicalJsonBytes(value).equals(bytes), code, `${label} is not canonical JSON`);
  return value;
}

function pathIsWithin(root, candidate, allowRoot = false) {
  const rel = relative(root, candidate);
  if (rel === "") return allowRoot;
  return rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function containedPath(root, relativePath, code = "INPUT_PATH_ESCAPE_REJECTED") {
  assert(typeof relativePath === "string" && relativePath.length > 0 && !isAbsolute(relativePath), code, "path is not relative");
  const candidate = resolve(root, relativePath);
  assert(pathIsWithin(root, candidate), code, "path escaped root");
  return candidate;
}

function assertRealDirectory(path, code, label) {
  assert(isAbsolute(path), code, `${label} is not absolute`);
  const absolute = resolve(path);
  let stat;
  try { stat = lstatSync(absolute); } catch (error) { fail(code, `${label} lstat failed`, { error: error.code ?? error.message }); }
  assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === process.getuid(), code, `${label} is not an owned real directory`);
  assert(realpathSync(absolute) === absolute, code, `${label} contains a symlink`);
  return { path: absolute, realpath: absolute, device: stat.dev, inode: stat.ino, uid: stat.uid, created_exclusive: true };
}

function safeReadRegular(path, expected = undefined, code = "INPUT_IDENTITY_REJECTED", label = "file", options = {}) {
  const absolute = resolve(path);
  let before;
  try { before = lstatSync(absolute); } catch (error) { fail(code, `${label} lstat failed`, { error: error.code ?? error.message }); }
  assert(before.isFile() && !before.isSymbolicLink(), code, `${label} is not a regular non-symlink file`);
  if (options.allowMultipleLinks !== true) assert(before.nlink === 1, code, `${label} nlink is not one`);
  if (options.requireCanonicalPath !== false) assert(realpathSync(absolute) === absolute, code, `${label} path contains a symlink`);
  let descriptor;
  try {
    descriptor = openSync(absolute, fsConstants.O_RDONLY | O_NOFOLLOW);
    const during = fstatSync(descriptor);
    assert(during.isFile() && during.dev === before.dev && during.ino === before.ino, code, `${label} identity changed during open`);
    if (options.allowMultipleLinks !== true) assert(during.nlink === 1, code, `${label} descriptor nlink drifted`);
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    assert(after.dev === during.dev && after.ino === during.ino, code, `${label} identity changed during read`);
    const identity = identityOf(bytes);
    if (expected) assert(identity.byte_length === expected.byte_length && identity.sha256 === expected.sha256, code, `${label} identity drifted`);
    return { path: absolute, bytes, identity, stat: during };
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function createExclusiveDirectory(path, mode = 0o700) {
  try { mkdirSync(path, { mode, recursive: false }); } catch (error) { fail("PREEXISTING_EVIDENCE_REJECTED", `exclusive directory creation failed: ${path}`, { error: error.code ?? error.message }); }
  const receipt = assertRealDirectory(resolve(path), "EVIDENCE_ROOT_REJECTED", "created directory");
  chmodSync(receipt.path, mode);
  return receipt;
}

function writeCreateOnce(path, bytes, mode = 0o600) {
  assert(Buffer.isBuffer(bytes), "EVIDENCE_WRITE_REJECTED", "write payload is not bytes");
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | O_NOFOLLOW, mode);
    let offset = 0;
    while (offset < bytes.length) offset += writeSync(descriptor, bytes, offset, bytes.length - offset);
    fsyncSync(descriptor);
  } catch (error) {
    fail("EVIDENCE_WRITE_REJECTED", `create-once write failed: ${path}`, { error: error.code ?? error.message });
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  chmodSync(path, mode);
  return safeReadRegular(path, identityOf(bytes), "EVIDENCE_WRITE_REJECTED", "created file");
}

function repositoryPath(relativePath) {
  return containedPath(REPOSITORY_ROOT, relativePath);
}

function processGroupAlive(pid) {
  try { process.kill(-pid, 0); return true; } catch (error) { if (error?.code === "ESRCH") return false; throw error; }
}

function signalProcessGroup(pid, signal) {
  try { process.kill(-pid, signal); } catch (error) { if (error?.code !== "ESRCH") throw error; }
}

async function ensureProcessGroupGone(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return true;
  if (processGroupAlive(pid)) signalProcessGroup(pid, "SIGTERM");
  for (let attempt = 0; attempt < 10 && processGroupAlive(pid); attempt += 1) await delay(10);
  if (processGroupAlive(pid)) signalProcessGroup(pid, "SIGKILL");
  for (let attempt = 0; attempt < 50 && processGroupAlive(pid); attempt += 1) await delay(10);
  return !processGroupAlive(pid);
}

async function runManagedProcess({ argv, cwd, env, timeoutMs, maxOutputBytes, expectedExitStatus, telemetry, label }) {
  assert(Array.isArray(argv) && argv.length > 0 && [NODE_PATH, GIT_PATH].includes(argv[0]), "COMMAND_PROFILE_REJECTED", `${label} executable is not fixed`);
  assert(isAbsolute(cwd) && realpathSync(cwd) === cwd, "COMMAND_PROFILE_REJECTED", `${label} cwd is not exact realpath`);
  telemetry.child_start_attempts += 1;
  const started = process.hrtime.bigint();
  const child = spawn(argv[0], argv.slice(1), {
    cwd,
    env,
    shell: false,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  let stdout = Buffer.alloc(0);
  let stderr = Buffer.alloc(0);
  let failureKind = null;
  let terminationTriggered = false;
  let graceTimer;
  let watchdog;
  const terminate = (kind) => {
    if (failureKind === null) failureKind = kind;
    if (terminationTriggered || !Number.isInteger(child.pid)) return;
    terminationTriggered = true;
    signalProcessGroup(child.pid, "SIGTERM");
    graceTimer = setTimeout(() => signalProcessGroup(child.pid, "SIGKILL"), 100);
  };
  const append = (stream, chunk) => {
    if (stream === "stdout") stdout = Buffer.concat([stdout, chunk]);
    else stderr = Buffer.concat([stderr, chunk]);
    if (stdout.length + stderr.length > maxOutputBytes) terminate("output_overflow");
  };
  child.stdout.on("data", (chunk) => append("stdout", chunk));
  child.stderr.on("data", (chunk) => append("stderr", chunk));
  const timeoutTimer = setTimeout(() => terminate("timeout"), timeoutMs);
  watchdog = setTimeout(() => {
    terminate(failureKind ?? "timeout");
    if (Number.isInteger(child.pid)) signalProcessGroup(child.pid, "SIGKILL");
  }, timeoutMs + 2_000);
  const closed = await new Promise((resolvePromise, rejectPromise) => {
    child.once("error", rejectPromise);
    child.once("close", (code, signal) => resolvePromise({ code, signal }));
  }).catch(async (error) => {
    if (Number.isInteger(child.pid)) await ensureProcessGroupGone(child.pid);
    throw new ManagedProcessError("COMMAND_EXECUTION_REJECTED", `${label} spawn failed`, {
      failure_kind: "spawn_error", error: error.code ?? error.message, stdout, stderr,
    });
  });
  clearTimeout(timeoutTimer);
  clearTimeout(watchdog);
  if (graceTimer) clearTimeout(graceTimer);
  if (closed.signal !== null && failureKind === null) failureKind = "signal";
  const groupGone = await ensureProcessGroupGone(child.pid);
  const durationMs = Number(process.hrtime.bigint() - started) / 1_000_000;
  const outcome = {
    exit_status: closed.code,
    signal: closed.signal,
    stdout,
    stderr,
    duration_ms: durationMs,
    failure_kind: failureKind,
    terminated: true,
    descendants_alive: !groupGone,
    process_group_pid: child.pid,
  };
  if (!groupGone) throw new ManagedProcessError("CHILD_TERMINATION_REJECTED", `${label} process group survived`, outcome);
  if (failureKind !== null) throw new ManagedProcessError("COMMAND_EXECUTION_REJECTED", `${label} ended through ${failureKind}`, outcome);
  if (closed.code !== expectedExitStatus || closed.signal !== null) {
    throw new ManagedProcessError("COMMAND_RESULT_REJECTED", `${label} exit result drifted`, outcome);
  }
  return outcome;
}

function syncGit(repository, args, label, trace = undefined, actionId = undefined) {
  const argv = [GIT_PATH, "-C", repository, ...args];
  const outcome = spawnSync(argv[0], argv.slice(1), {
    cwd: repository,
    env: { ...FIXED_ENV, HOME: "/var/empty", GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0" },
    shell: false,
    encoding: null,
    timeout: 15_000,
    maxBuffer: 4 * 1024 * 1024,
    windowsHide: true,
  });
  assert(!outcome.error && outcome.status === 0 && outcome.signal === null, "CANDIDATE_BINDING_REJECTED", `${label} failed`);
  assert(Buffer.isBuffer(outcome.stderr) && outcome.stderr.length === 0, "CANDIDATE_BINDING_REJECTED", `${label} emitted stderr`);
  const stdout = Buffer.isBuffer(outcome.stdout) ? outcome.stdout : Buffer.alloc(0);
  if (trace) {
    assert(typeof actionId === "string", "ACTION_TRACE_REJECTED", `${label} action id is missing`);
    recordProcessAction(trace, actionId, "CANDIDATE_PREFLIGHT", null, argv,
      "CANDIDATE_REPOSITORY", 15_000, 0, {
        exit_status: outcome.status,
        signal: outcome.signal,
        stdout,
        stderr: outcome.stderr,
        terminated: true,
        descendants_alive: false,
      });
  }
  return stdout;
}

function validateExecutable(path, identity, label) {
  return safeReadRegular(path, identity, "EXECUTOR_IDENTITY_REJECTED", label, { allowMultipleLinks: true });
}

function executableEvidence(file, path, version) {
  return {
    path,
    realpath: realpathSync(path),
    version,
    byte_length: file.identity.byte_length,
    sha256: file.identity.sha256,
    regular: file.stat.isFile(),
    symlink: file.stat.isSymbolicLink(),
    nlink: file.stat.nlink,
  };
}

async function captureActualExecutor(candidate, assets, telemetry, trace, runId) {
  assert(candidate?.repository && isAbsolute(candidate.repository),
    "EXECUTOR_EVIDENCE_REJECTED", "candidate repository is unavailable for executor evidence");
  const timeoutMs = 10_000;
  const argv = [GIT_PATH, "--version"];
  const outcome = await runManagedProcess({
    argv,
    cwd: candidate.repository,
    env: { ...FIXED_ENV, HOME: "/var/empty", GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0" },
    timeoutMs,
    maxOutputBytes: 1_048_576,
    expectedExitStatus: 0,
    telemetry,
    label: "actual Git version",
  });
  recordProcessAction(trace, "actual_git_version", "EXECUTOR_EVIDENCE", null,
    argv, "CANDIDATE_REPOSITORY", timeoutMs, 0, outcome);
  const gitVersion = outcome.stdout.toString("utf8").trim();
  const expected = assets.taskCard.declared_target_and_actual_executor?.actual_executor_identity;
  assert(expected && process.execPath === NODE_PATH && process.platform === expected.platform &&
    process.arch === expected.architecture && process.version === expected.node_version &&
    gitVersion === expected.git_version,
  "EXECUTOR_EVIDENCE_REJECTED", "actual executor runtime identity drifted");
  const nodeFile = validateExecutable(NODE_PATH, EXPECTED_IDENTITIES.node, "actual Node executable");
  const gitFile = validateExecutable(GIT_PATH, EXPECTED_IDENTITIES.git, "actual Git executable");
  assert(expected.node_path === NODE_PATH && expected.node_byte_length === nodeFile.identity.byte_length &&
    expected.node_sha256 === nodeFile.identity.sha256 && expected.git_path === GIT_PATH &&
    expected.git_byte_length === gitFile.identity.byte_length && expected.git_sha256 === gitFile.identity.sha256,
  "EXECUTOR_EVIDENCE_REJECTED", "Task Card actual executor binding drifted");
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_actual_executor_evidence",
    run_id: runId,
    executor_kind: "LOCAL_HOST_PROCESS",
    platform: process.platform,
    architecture: process.arch,
    node: executableEvidence(nodeFile, NODE_PATH, process.version),
    git: executableEvidence(gitFile, GIT_PATH, gitVersion),
    container_runtime_observed: false,
    declared_target_materialized: false,
    external_effects: { ...FALSE_EFFECTS },
  };
}

function validateSchemaValue(value, schemaRelativePath, label) {
  const schemaFile = safeReadRegular(repositoryPath(schemaRelativePath), undefined, "SCHEMA_VALIDATION_REJECTED", `${label} schema`);
  const schema = parseJson(schemaFile.bytes, "SCHEMA_VALIDATION_REJECTED", `${label} schema`);
  const errors = validateSchema(value, schema);
  assert(errors.length === 0, "SCHEMA_VALIDATION_REJECTED", `${label} schema failed`, { errors });
}

function currentModuleIdentities() {
  return Object.fromEntries(Object.entries(EXECUTING_MODULE_PATHS).map(([role, path]) => {
    const file = safeReadRegular(repositoryPath(path), undefined, "CANDIDATE_BINDING_REJECTED", `candidate ${role}`);
    return [role, { path, ...file.identity }];
  }));
}

function validateCandidateManifest(path, options = {}) {
  if (options.candidateBinding) {
    const repository = assertRealDirectory(options.candidateRepository,
      "CANDIDATE_BINDING_REJECTED", "self-test candidate repository");
    const observedHead = syncGit(repository.path, ["rev-parse", "HEAD"], "candidate HEAD",
      options.actionTrace, "candidate_git_head").toString("utf8").trim();
    const observedTree = syncGit(repository.path, ["rev-parse", "HEAD^{tree}"], "candidate tree",
      options.actionTrace, "candidate_git_tree").toString("utf8").trim();
    const observedStatus = syncGit(repository.path,
      ["status", "--porcelain=v1", "-z", "--untracked-files=all"], "candidate status",
      options.actionTrace, "candidate_git_status");
    assert(observedHead === options.candidateBinding.commit &&
      observedTree === options.candidateBinding.tree && observedStatus.length === 0,
    "CANDIDATE_BINDING_REJECTED", "self-test candidate Git identity drifted");
    return { binding: { ...options.candidateBinding }, repository: repository.path };
  }
  assert(typeof path === "string" && isAbsolute(path), "CANDIDATE_BINDING_REJECTED", "candidate manifest path is not absolute");
  const authorized = assertRealDirectory(AUTHORIZED_EVIDENCE_ROOT, "CANDIDATE_BINDING_REJECTED", "authorized Evidence root");
  const absolute = resolve(path);
  assert(pathIsWithin(authorized.path, absolute), "CANDIDATE_BINDING_REJECTED", "candidate manifest escaped authorized Evidence root");
  const file = safeReadRegular(absolute, undefined, "CANDIDATE_BINDING_REJECTED", "candidate manifest");
  const value = parseJson(file.bytes, "CANDIDATE_BINDING_REJECTED", "candidate manifest", true);
  exactKeys(value, ["schema_version", "record_type", "task_id", "candidate_commit", "candidate_tree", "quality_freeze_manifest_sha256", "repository", "executing_modules"], "CANDIDATE_BINDING_REJECTED", "candidate manifest");
  assert(value.schema_version === 1 && value.record_type === "sourcelens_aios_p1_067_exact_candidate_manifest" && value.task_id === TASK_ID, "CANDIDATE_BINDING_REJECTED", "candidate manifest identity drifted");
  assert(/^[0-9a-f]{40}$/.test(value.candidate_commit) && /^[0-9a-f]{40}$/.test(value.candidate_tree) && value.quality_freeze_manifest_sha256 === EXPECTED_IDENTITIES.quality_freeze.sha256, "CANDIDATE_BINDING_REJECTED", "candidate binding drifted");
  exactKeys(value.repository, ["path", "realpath", "head", "tree", "workspace_status"], "CANDIDATE_BINDING_REJECTED", "candidate repository");
  assert(value.repository.path === REPOSITORY_ROOT && value.repository.realpath === realpathSync(REPOSITORY_ROOT) && value.repository.head === value.candidate_commit && value.repository.tree === value.candidate_tree && value.repository.workspace_status === "clean", "CANDIDATE_BINDING_REJECTED", "candidate repository declaration drifted");
  const observedHead = syncGit(REPOSITORY_ROOT, ["rev-parse", "HEAD"], "candidate HEAD",
    options.actionTrace, "candidate_git_head").toString("utf8").trim();
  const observedTree = syncGit(REPOSITORY_ROOT, ["rev-parse", "HEAD^{tree}"], "candidate tree",
    options.actionTrace, "candidate_git_tree").toString("utf8").trim();
  const observedStatus = syncGit(REPOSITORY_ROOT,
    ["status", "--porcelain=v1", "-z", "--untracked-files=all"], "candidate status",
    options.actionTrace, "candidate_git_status");
  assert(observedHead === value.candidate_commit && observedTree === value.candidate_tree && observedStatus.length === 0, "CANDIDATE_BINDING_REJECTED", "candidate Git identity drifted");
  exactKeys(value.executing_modules, Object.keys(EXECUTING_MODULE_PATHS), "CANDIDATE_BINDING_REJECTED", "executing modules");
  const observedModules = currentModuleIdentities();
  assert(sameJson(value.executing_modules, observedModules), "CANDIDATE_BINDING_REJECTED", "executing module identities drifted");
  return {
    binding: { commit: value.candidate_commit, tree: value.candidate_tree, clean: true },
    repository: REPOSITORY_ROOT,
    manifest: { file, value },
  };
}

function validateFrozenInputs(taskCardArgument) {
  assert(resolve(process.cwd(), taskCardArgument) === TASK_CARD_PATH, "TASK_CARD_DRIFT", "Task Card path is not frozen path");
  safeReadRegular(TASK_CARD_PATH, EXPECTED_IDENTITIES.task_card, "TASK_CARD_DRIFT", "Task Card");
  const freezeFile = safeReadRegular(QUALITY_FREEZE_PATH, EXPECTED_IDENTITIES.quality_freeze, "QUALITY_FREEZE_REJECTED", "Quality Freeze");
  const freeze = parseJson(freezeFile.bytes, "QUALITY_FREEZE_REJECTED", "Quality Freeze", true);
  assert(freeze.status === "QUALITY_FREEZE_COMPLETE" && freeze.target_verdict === "PASS" && freeze.task_id === TASK_ID && freeze.worker_boundary?.worker_runner_failure_path_self_test_required === true, "QUALITY_FREEZE_REJECTED", "Quality Freeze is not effective");
  const taskCard = validateTaskCard();
  const quality = validateQualityAssets();
  validateExecutable(NODE_PATH, EXPECTED_IDENTITIES.node, "fixed Node executable");
  validateExecutable(GIT_PATH, EXPECTED_IDENTITIES.git, "fixed Git executable");
  for (const [name, path] of Object.entries(QUALITY_ASSET_PATHS)) safeReadRegular(path, QUALITY_ASSET_IDENTITIES[name], "QUALITY_ASSET_DRIFT", name);
  const acceptedInputFiles = Object.fromEntries(
    Object.entries(taskCard.accepted_inputs)
      .filter(([, record]) => record && typeof record.path === "string" &&
        Number.isInteger(record.byte_length) && /^[0-9a-f]{64}$/.test(record.sha256))
      .map(([name, record]) => [name, safeReadRegular(repositoryPath(record.path), record,
        "INPUT_IDENTITY_REJECTED", `accepted input ${name}`)]),
  );
  const taskSpecFile = safeReadRegular(repositoryPath(TASK_SPEC.relative_path), TASK_SPEC, "INPUT_IDENTITY_REJECTED", "TaskSpec");
  const taskSpec = parseJson(taskSpecFile.bytes, "INPUT_IDENTITY_REJECTED", "TaskSpec");
  validateSchemaValue(taskSpec, "docs/aios/schemas/task-spec.schema.json", "TaskSpec");
  validateSchemaValue(quality.environment, "docs/aios/schemas/environment-snapshot.schema.json", "EnvironmentSnapshot");
  validateSchemaValue(quality.system, "docs/aios/schemas/system-configuration.schema.json", "SystemConfiguration");
  assert(taskSpec.allowed_tools.length === 2 && sameJson(taskSpec.allowed_tools, ["local-node-test", "local-file-edit"]) || sameJson(taskSpec.allowed_tools, ["local-file-edit", "local-node-test"]), "INPUT_IDENTITY_REJECTED", "TaskSpec tools drifted");
  assert(taskSpec.network_policy === "none" && sameJson(taskSpec.allowed_network_hosts, []) && quality.system.adapter_id === "B1" && quality.system.loop_limit === 3 && sameJson(quality.system.enabled_tools, ["local-file-edit", "local-node-test"]), "INPUT_IDENTITY_REJECTED", "offline B1 configuration drifted");
  const planFile = safeReadRegular(QUALITY_ASSET_PATHS.positive_tool_plan, EXPECTED_IDENTITIES.positive_plan, "PLAN_IDENTITY_REJECTED", "positive tool plan");
  validateFiniteToolPlan(planFile.bytes);
  const ir10File = safeReadRegular(repositoryPath(IR10.relative_path), IR10, "IR_INPUT_REJECTED", "IR10");
  let admission;
  try { admission = admitOfflineB1ToolPlan(planFile.bytes, ir10File.bytes); } catch (error) { if (error instanceof OfflineB1AdapterError) fail(error.code, error.message); throw error; }
  assert(admission.status === "ADMITTED_CLOSED_FINITE_TOOL_PLAN" && admission.actions.length === 3 && admission.postimage_byte_length === EXPECTED_POSTIMAGE.byte_length && admission.postimage_sha256 === EXPECTED_POSTIMAGE.sha256, "ADMISSION_REJECTED", "adapter admission drifted");
  const sources = Object.fromEntries(Object.entries(SOURCE_INPUTS).map(([name, record]) => [name, safeReadRegular(repositoryPath(record.relative_path), record, "INPUT_IDENTITY_REJECTED", name)]));
  return {
    taskCard,
    quality,
    taskSpec,
    planFile,
    ir10File,
    admission,
    sources,
    freezeFile,
    acceptedInputFiles,
    executingModules: currentModuleIdentities(),
  };
}

async function runGit(cwd, args, environment, telemetry, label,
  trace = undefined, actionId = undefined, phase = "MATERIALIZATION", toolOrdinal = null) {
  const argv = [GIT_PATH, ...args];
  const timeoutMs = 10_000;
  const outcome = await runManagedProcess({
    argv,
    cwd,
    env: { ...FIXED_ENV, HOME: environment.HOME, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0", ...environment.gitCommit },
    timeoutMs,
    maxOutputBytes: 1_048_576,
    expectedExitStatus: 0,
    telemetry,
    label,
  });
  if (trace) {
    assert(typeof actionId === "string", "ACTION_TRACE_REJECTED", `${label} action id is missing`);
    recordProcessAction(trace, actionId, phase, toolOrdinal, argv,
      "TASK_REPOSITORY", timeoutMs, 0, outcome);
  }
  return outcome;
}

function atomicReplaceOwned(path, expectedCurrent, replacementBytes, telemetry, label) {
  const current = safeReadRegular(path, expectedCurrent, "MUTATION_REJECTED", `${label} current source`);
  const temporary = join(dirname(path), `.p1-067-${randomBytes(16).toString("hex")}.tmp`);
  telemetry.mutation_attempts += 1;
  const created = writeCreateOnce(temporary, replacementBytes, current.stat.mode & 0o777);
  try {
    renameSync(created.path, path);
  } catch (error) {
    try {
      const residue = lstatSync(created.path);
      if (residue.isFile() && !residue.isSymbolicLink() && residue.dev === created.stat.dev && residue.ino === created.stat.ino && residue.nlink === 1) unlinkSync(created.path);
    } catch {
      // Preserve any object whose exact ownership cannot be reproven.
    }
    fail("MUTATION_REJECTED", `${label} atomic rename failed`, { error: error.code ?? error.message });
  }
  const file = safeReadRegular(path, identityOf(replacementBytes), "MUTATION_REJECTED", `${label} replaced source`);
  assert(file.stat.dev === created.stat.dev && file.stat.ino === created.stat.ino &&
    file.stat.uid === created.stat.uid && file.stat.nlink === 1,
  "MUTATION_REJECTED", `${label} replacement ownership drifted`);
  return {
    file,
    temporary_receipt: {
      device: created.stat.dev,
      inode: created.stat.ino,
      uid: created.stat.uid,
      regular: true,
      symlink: false,
      nlink: 1,
      created_exclusive: true,
    },
    atomic_rename: true,
  };
}

function createdFileReceipt(file, pathRef) {
  return {
    path_ref: pathRef,
    byte_length: file.identity.byte_length,
    sha256: file.identity.sha256,
    device: file.stat.dev,
    inode: file.stat.ino,
    uid: file.stat.uid,
    regular: file.stat.isFile(),
    symlink: file.stat.isSymbolicLink(),
    nlink: file.stat.nlink,
    created_exclusive: true,
  };
}

async function materializeBase(runRoot, assets, telemetry, trace = undefined) {
  const materialization = createExclusiveDirectory(join(runRoot.path, "materialization"));
  telemetry.materialization_creations += 1;
  const home = createExclusiveDirectory(join(runRoot.path, "home"));
  const sourceDirectory = createExclusiveDirectory(join(materialization.path, "src"));
  const testDirectory = createExclusiveDirectory(join(materialization.path, "test"));
  if (trace) {
    recordAction(trace, "create_exclusive_materialization_root", "DIRECTORY_CREATION",
      "MATERIALIZATION", null,
      { parent_ref: "RUN_ROOT", required_children: ["materialization", "home", "materialization/src", "materialization/test"] },
      {
        status: "CREATED_EXCLUSIVE",
        materialization_receipt: manifestReceipt(materialization),
        home_receipt: manifestReceipt(home),
        source_directory_receipt: manifestReceipt(sourceDirectory),
        test_directory_receipt: manifestReceipt(testDirectory),
      });
  }
  const materializedFiles = [];
  for (const [name, record] of Object.entries(SOURCE_INPUTS)) {
    const file = writeCreateOnce(join(materialization.path, record.destination), assets.sources[name].bytes, 0o644);
    materializedFiles.push({
      name,
      input: { path: record.relative_path, byte_length: record.byte_length, sha256: record.sha256 },
      output: createdFileReceipt(file, record.destination),
    });
  }
  if (trace) {
    recordAction(trace, "materialize_source_inputs", "FILE_CREATION", "MATERIALIZATION", null,
      { source_count: Object.keys(SOURCE_INPUTS).length, sources: materializedFiles.map(({ name, input }) => ({ name, ...input })) },
      { status: "MATERIALIZED_EXACT_BYTES", files: materializedFiles.map(({ name, output }) => ({ name, ...output })) });
  }
  const environment = {
    HOME: home.path,
    gitCommit: {
      GIT_AUTHOR_NAME: "SourceLens AIOS Fixture",
      GIT_AUTHOR_EMAIL: "fixture@sourcelens.local",
      GIT_AUTHOR_DATE: "2000-01-01T00:00:00Z",
      GIT_COMMITTER_NAME: "SourceLens AIOS Fixture",
      GIT_COMMITTER_EMAIL: "fixture@sourcelens.local",
      GIT_COMMITTER_DATE: "2000-01-01T00:00:00Z",
    },
  };
  await runGit(materialization.path, ["init", "--quiet", "--initial-branch=main"], environment, telemetry,
    "fixture git init", trace, "materialize_git_init", "MATERIALIZATION");
  await runGit(materialization.path, ["add", "--", "src/range.mjs", "test/issue.test.mjs", "test/regression.test.mjs"], environment, telemetry,
    "fixture git add", trace, "materialize_git_add", "MATERIALIZATION");
  await runGit(materialization.path, ["commit", "--quiet", "--no-gpg-sign", "-m", "fixture: base"], environment, telemetry,
    "fixture git commit", trace, "materialize_git_commit", "MATERIALIZATION");
  const head = (await runGit(materialization.path, ["rev-parse", "HEAD"], environment, telemetry,
    "fixture git HEAD", trace, "base_git_head", "BASE_PRECONDITION")).stdout.toString("utf8").trim();
  const tree = (await runGit(materialization.path, ["rev-parse", "HEAD^{tree}"], environment, telemetry,
    "fixture git tree", trace, "base_git_tree", "BASE_PRECONDITION")).stdout.toString("utf8").trim();
  const status = (await runGit(materialization.path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], environment, telemetry,
    "fixture git status", trace, "base_git_status", "BASE_PRECONDITION")).stdout;
  assert(head === EXPECTED_BASE.commit && tree === EXPECTED_BASE.tree && status.length === 0, "BASE_IDENTITY_REJECTED", "materialized base identity drifted");
  safeReadRegular(join(materialization.path, "src/range.mjs"), EXPECTED_BASE.source, "BASE_IDENTITY_REJECTED", "materialized source");
  return { materialization, home, environment };
}

async function verifyRollback(materialized, telemetry, trace = undefined) {
  const source = safeReadRegular(join(materialized.materialization.path, "src/range.mjs"), EXPECTED_BASE.source, "ROLLBACK_REJECTED", "restored source");
  const head = (await runGit(materialized.materialization.path, ["rev-parse", "HEAD"], materialized.environment, telemetry,
    "rollback HEAD", trace, "rollback_git_head", "ROLLBACK")).stdout.toString("utf8").trim();
  const tree = (await runGit(materialized.materialization.path, ["rev-parse", "HEAD^{tree}"], materialized.environment, telemetry,
    "rollback tree", trace, "rollback_git_tree", "ROLLBACK")).stdout.toString("utf8").trim();
  const status = (await runGit(materialized.materialization.path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materialized.environment, telemetry,
    "rollback status", trace, "rollback_git_status", "ROLLBACK")).stdout;
  assert(head === EXPECTED_BASE.commit && tree === EXPECTED_BASE.tree && status.length === 0, "ROLLBACK_REJECTED", "rollback commit/tree/clean drifted");
  if (trace) {
    recordAction(trace, "rollback_source_check", "VERIFICATION", "ROLLBACK", null,
      { expected_source: EXPECTED_BASE.source, expected_head: EXPECTED_BASE.commit, expected_tree: EXPECTED_BASE.tree, expected_clean: true },
      { status: "EXACT_BASE_RESTORED", source: createdFileReceipt(source, "src/range.mjs"), head, tree, clean: true, extra_paths: [] });
  }
  return {
    source,
    head,
    tree,
    clean: true,
    extra_paths: [],
  };
}

function artifactEntry(role, path, runId, file) {
  return { role, path, byte_length: file.identity.byte_length, sha256: file.identity.sha256, run_id: runId };
}

function addArtifact(context, role, path, bytes) {
  assert(!context.artifacts.has(path), "EVIDENCE_WRITE_REJECTED", `duplicate artifact ${path}`);
  const file = writeCreateOnce(join(context.runRoot.path, path), bytes);
  const entry = artifactEntry(role, path, context.runId, file);
  context.artifacts.set(path, { role, path, bytes, file, entry });
  return entry;
}

async function executeRecordedCommand(context, definition) {
  const outcome = await runManagedProcess({
    argv: [...definition.argv],
    cwd: context.materialized.materialization.path,
    env: { ...FIXED_ENV, HOME: context.materialized.home.path },
    timeoutMs: 10_000,
    maxOutputBytes: 4 * 1024 * 1024,
    expectedExitStatus: definition.expected_exit_status,
    telemetry: context.telemetry,
    label: definition.action_id,
  });
  const stdoutEntry = addArtifact(context, "raw_stream", definition.stdout_path, outcome.stdout);
  const stderrEntry = addArtifact(context, "raw_stream", definition.stderr_path, outcome.stderr);
  const stdoutRef = { path: stdoutEntry.path, byte_length: stdoutEntry.byte_length, sha256: stdoutEntry.sha256 };
  const stderrRef = { path: stderrEntry.path, byte_length: stderrEntry.byte_length, sha256: stderrEntry.sha256 };
  recordProcessAction(context.actionTrace, definition.action_id, definition.phase,
    definition.tool_ordinal, [...definition.argv], "TASK_REPOSITORY", 10_000,
    definition.expected_exit_status, outcome, { stdout: stdoutRef, stderr: stderrRef });
  const record = {
    action_id: definition.action_id,
    phase: definition.phase,
    tool_ordinal: definition.tool_ordinal,
    argv: [...definition.argv],
    cwd_ref: "TASK_REPOSITORY",
    timeout_ms: 10_000,
    exit_status: outcome.exit_status,
    signal: outcome.signal,
    terminated: outcome.terminated,
    descendants_alive: outcome.descendants_alive,
    stdout: stdoutRef,
    stderr: stderrRef,
  };
  context.commandRecords.push(record);
  return { record, stdout: outcome.stdout, stderr: outcome.stderr };
}

function validateBaseIssueOutput(command) {
  const text = Buffer.concat([command.stdout, Buffer.from("\n"), command.stderr]).toString("utf8");
  assert(text.includes("not ok") && text.includes("REP001_NEGATIVE_RANGE_ORDER") && !/(SyntaxError|ERR_MODULE_NOT_FOUND|MODULE_NOT_FOUND|ENOENT|timeout|signal)/.test(text), "TEST_EVIDENCE_REJECTED", "base issue failure is not the frozen assertion");
}

function validateSuccessOutput(command, token, label) {
  const text = Buffer.concat([command.stdout, Buffer.from("\n"), command.stderr]).toString("utf8");
  assert(text.includes("ok") && text.includes(token) && !text.includes("not ok") && !/(SyntaxError|ERR_MODULE_NOT_FOUND|MODULE_NOT_FOUND|ENOENT|timeout|signal)/.test(text), "TEST_EVIDENCE_REJECTED", `${label} is not the frozen successful result`);
}

function buildRunRecord(context, startedAt, endedAt) {
  const checksums = Object.fromEntries(
    [...context.artifacts.entries()]
      .filter(([path]) => path !== "run-record.json")
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([path, artifact]) => [path, artifact.entry.sha256]),
  );
  return {
    schema_version: "1.0",
    run_id: context.runId,
    task_id: CONTROL_ID,
    dataset_version: "1.0.0",
    adapter_id: "B1",
    adapter_version: ADAPTER_VERSION,
    environment_snapshot_id: "ENV-SOURCELENS-P1-REP-NODE20-STDLIB-1",
    system_configuration_id: "P1-067-B1-OFFLINE-FINITE-TOOL-1",
    repetition_id: context.repetitionId,
    started_at: startedAt,
    ended_at: endedAt,
    terminal_status: "completed",
    stop_reason_code: "agent_complete",
    invalid_run_reason: null,
    error_taxonomy: [],
    trace_ref: "command-stream.json",
    patch_ref: "patch.diff",
    test_artifact_refs: COMMANDS.map((command) => command.stdout_path),
    verification_ref: null,
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      tool_calls: 3,
      retries: 0,
      human_interventions: 0,
      cost_usd: 0,
      latency_ms: Math.max(0, Math.round(Date.parse(endedAt) - Date.parse(startedAt))),
    },
    policy_violations: [],
    artifact_checksums: checksums,
  };
}

function manifestReceipt(directory) {
  return {
    realpath: directory.realpath,
    device: directory.device,
    inode: directory.inode,
    uid: directory.uid,
    created_exclusive: true,
  };
}

function identityReference(path, identity) {
  return { path, byte_length: identity.byte_length, sha256: identity.sha256 };
}

function artifactReferenceFor(context, path) {
  const artifact = context.artifacts.get(path);
  assert(artifact, "EVIDENCE_IDENTITY_REJECTED", `missing artifact reference ${path}`);
  return { path, byte_length: artifact.entry.byte_length, sha256: artifact.entry.sha256 };
}

function recordFrozenIdentityValidation(trace, assets) {
  const qualityAssets = Object.fromEntries(Object.entries(QUALITY_ASSET_PATHS).map(([name, path]) =>
    [name, identityReference(relative(REPOSITORY_ROOT, path), QUALITY_ASSET_IDENTITIES[name])]));
  const acceptedInputs = Object.fromEntries(Object.entries(assets.acceptedInputFiles).map(([name, file]) =>
    [name, identityReference(assets.taskCard.accepted_inputs[name].path, file.identity)]));
  recordAction(trace, "validate_quality_and_input_identities", "IDENTITY_VALIDATION",
    "FROZEN_INPUT_VALIDATION", null,
    {
      task_card: identityReference(TASK_CARD_RELATIVE_PATH, EXPECTED_IDENTITIES.task_card),
      quality_freeze: identityReference(QUALITY_FREEZE_PATH, EXPECTED_IDENTITIES.quality_freeze),
      quality_assets: qualityAssets,
      accepted_inputs: acceptedInputs,
      executing_modules: assets.executingModules,
    },
    {
      status: "VALIDATED_EXACT_IDENTITIES",
      all_regular: true,
      all_non_symlink: true,
      ownership_enforced: true,
      hardlink_policy_enforced: true,
    });
}

function recordClosedPlanAdmission(trace, assets) {
  recordAction(trace, "validate_closed_tool_plan_and_adapter_admission", "PLAN_ADMISSION",
    "PRE_ADMISSION", null,
    {
      tool_plan: identityReference(relative(REPOSITORY_ROOT, QUALITY_ASSET_PATHS.positive_tool_plan), assets.planFile.identity),
      ir10: identityReference(IR10.relative_path, assets.ir10File.identity),
      adapter: assets.executingModules.adapter,
      task_spec: identityReference(TASK_SPEC.relative_path, { byte_length: TASK_SPEC.byte_length, sha256: TASK_SPEC.sha256 }),
    },
    {
      status: assets.admission.status,
      admitted_action_count: assets.admission.actions.length,
      admitted_actions: assets.admission.actions,
      postimage: { byte_length: assets.admission.postimage_byte_length, sha256: assets.admission.postimage_sha256 },
      external_effects: assets.admission.external_effects,
    });
}

function recordToolRequest(context, assets, ordinal) {
  const step = assets.admission.actions[ordinal - 1];
  const mappingKey = `${step.tool_id}/${step.operation_id}`;
  recordAction(context.actionTrace, `tool_step_${ordinal}_request`, "TOOL_REQUEST",
    "TOOL_ACTION", ordinal,
    {
      plan_step: step,
      operation_mapping: assets.taskCard.fixed_operation_mapping[mappingKey],
    },
    {
      status: "REQUEST_ACCEPTED_FROM_CLOSED_PLAN",
      plan_id: assets.admission.plan_id,
      adapter_version: assets.admission.adapter_version,
      dynamic_controls_admitted: false,
      external_effects: assets.admission.external_effects,
    });
}

function buildActionTrace(context) {
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_complete_action_trace",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    action_count: context.actionTrace.length,
    actions: context.actionTrace,
  };
}

function buildPatchEvidencePackage(context, assets, rollback) {
  const checksums = Object.fromEntries([...context.artifacts.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([path, artifact]) => [path, artifact.entry.sha256]));
  const actualExecutor = artifactReferenceFor(context, "actual-executor.json");
  const trace = artifactReferenceFor(context, "action-trace.json");
  const oracleIdentity = assets.executingModules.quality_oracle;
  const testEntry = (definition) => {
    const command = context.commandRecords.find((entry) => entry.action_id === definition.action_id);
    assert(command, "PATCH_EVIDENCE_PACKAGE_REJECTED", `missing test command ${definition.action_id}`);
    return {
      action_id: definition.action_id,
      expected_exit_status: definition.expected_exit_status,
      observed_exit_status: command.exit_status,
      stdout: command.stdout,
      stderr: command.stderr,
    };
  };
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_patch_evidence_package",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    manifest: {
      candidate_binding: context.candidate.binding,
      artifact_checksums: checksums,
    },
    source_identity: {
      repository_identity: assets.quality.environment.source.repository_identity,
      base: { commit: EXPECTED_BASE.commit, tree: EXPECTED_BASE.tree, clean: true },
      target_path: "src/range.mjs",
      preimage: EXPECTED_BASE.source,
      accepted_postimage: EXPECTED_POSTIMAGE,
      final: { source: EXPECTED_BASE.source, head: rollback.head, tree: rollback.tree, clean: rollback.clean },
    },
    environment: {
      target_runtime: identityReference(relative(REPOSITORY_ROOT, QUALITY_ASSET_PATHS.target_runtime), QUALITY_ASSET_IDENTITIES.target_runtime),
      environment_snapshot: identityReference(relative(REPOSITORY_ROOT, QUALITY_ASSET_PATHS.environment_snapshot), QUALITY_ASSET_IDENTITIES.environment_snapshot),
      system_configuration: identityReference(relative(REPOSITORY_ROOT, QUALITY_ASSET_PATHS.system_configuration), QUALITY_ASSET_IDENTITIES.system_configuration),
      compatibility_profile: identityReference(relative(REPOSITORY_ROOT, QUALITY_ASSET_PATHS.compatibility_profile), QUALITY_ASSET_IDENTITIES.compatibility_profile),
      actual_executor: actualExecutor,
    },
    understanding: {
      task_spec: identityReference(TASK_SPEC.relative_path, { byte_length: TASK_SPEC.byte_length, sha256: TASK_SPEC.sha256 }),
      issue: "normalizeRange preserves reversed bounds instead of normalizing them",
      expected_base_failure: identityReference(
        assets.taskCard.accepted_inputs.expected_base_failure.path,
        assets.taskCard.accepted_inputs.expected_base_failure),
      observed_base_issue_action_id: "base_issue_test",
    },
    plan: {
      artifact: artifactReferenceFor(context, "tool-plan.json"),
      admission_status: assets.admission.status,
      adapter_version: assets.admission.adapter_version,
      plan_id: assets.admission.plan_id,
      fixed_step_count: assets.admission.actions.length,
      steps: assets.admission.actions,
      external_effects: assets.admission.external_effects,
    },
    actions: {
      action_trace: trace,
      ordered_action_ids: context.actionTrace.map((action) => action.action_id),
      tool_step_bindings: [
        { ordinal: 1, tool_id: "local-file-edit", operation_id: "apply-finite-typed-patch-ir", request_action_id: "tool_step_1_request", outcome_action_id: "tool_step_1_atomic_postimage" },
        { ordinal: 2, tool_id: "local-node-test", operation_id: "issue-test", request_action_id: "tool_step_2_request", outcome_action_id: "tool_issue_test" },
        { ordinal: 3, tool_id: "local-node-test", operation_id: "regression-test", request_action_id: "tool_step_3_request", outcome_action_id: "tool_regression_test" },
      ],
    },
    patch: {
      changed_paths: ["src/range.mjs"],
      artifact: artifactReferenceFor(context, "patch.diff"),
      preimage: EXPECTED_BASE.source,
      postimage: EXPECTED_POSTIMAGE,
      compiler: identityReference(assets.taskCard.accepted_inputs.compiler.path, assets.taskCard.accepted_inputs.compiler),
      ir10: identityReference(IR10.relative_path, IR10),
      mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT",
    },
    tests: {
      base_issue: testEntry(COMMANDS[0]),
      base_regression: testEntry(COMMANDS[1]),
      patched_issue: testEntry(COMMANDS[2]),
      patched_regression: testEntry(COMMANDS[3]),
    },
    verification: {
      status: "PENDING_INDEPENDENT_EVALUATION",
      evaluator: {
        path: oracleIdentity.path,
        version: QUALITY_ORACLE_VERSION,
        byte_length: oracleIdentity.byte_length,
        sha256: oracleIdentity.sha256,
      },
      verdict: null,
      runner_reported_pass_authoritative: false,
      adapter_reported_pass_authoritative: false,
    },
    risk: {
      claim_boundary: CLAIM_BOUNDARY,
      external_effects: { ...FALSE_EFFECTS },
      dynamic_controls_admitted: false,
      free_form_execution_admitted: false,
      child_process_group_termination_enforced: true,
      preexisting_object_overwrite_or_cleanup: false,
    },
    approval: {
      status: "PENDING_TASK_GATE",
      self_approval: false,
      independent_quality_required: true,
      task_gate_claimed: false,
    },
    rollback: {
      artifact: artifactReferenceFor(context, "rollback.json"),
      materialization_receipt: manifestReceipt(context.materialized.materialization),
      mutation_occurred: true,
      restored_source: EXPECTED_BASE.source,
      head: rollback.head,
      tree: rollback.tree,
      clean: rollback.clean,
      extra_paths: rollback.extra_paths,
      retained_materialization: true,
      cleanup_performed: false,
    },
  };
}

async function performRun(args, options = {}) {
  const telemetry = options.telemetry ?? { materialization_creations: 0, mutation_attempts: 0, child_start_attempts: 0 };
  assert(RUN_ID_PATTERN.test(args.runId), "CLI_REJECTED", "run id is invalid");
  const actionTrace = [];
  const candidate = validateCandidateManifest(args.candidateManifest, { ...options, actionTrace });
  const assets = validateFrozenInputs(args.taskCard);
  recordFrozenIdentityValidation(actionTrace, assets);
  const actualExecutor = await captureActualExecutor(candidate, assets, telemetry, actionTrace, args.runId);
  recordClosedPlanAdmission(actionTrace, assets);
  const evidenceRoot = assertRealDirectory(resolve(args.evidenceRoot), "EVIDENCE_ROOT_REJECTED", "Evidence root");
  const allowedRoot = options.selfTestRoot
    ? assertRealDirectory(options.selfTestRoot, "EVIDENCE_ROOT_REJECTED", "self-test root")
    : assertRealDirectory(AUTHORIZED_EVIDENCE_ROOT, "EVIDENCE_ROOT_REJECTED", "authorized Evidence root");
  assert(evidenceRoot.path === allowedRoot.path || pathIsWithin(allowedRoot.path, evidenceRoot.path), "EVIDENCE_ROOT_REJECTED", "Evidence root escaped allowed root");
  const runRoot = createExclusiveDirectory(join(evidenceRoot.path, args.runId));
  recordAction(actionTrace, "create_exclusive_run_root", "DIRECTORY_CREATION",
    "EVIDENCE_INITIALIZATION", null,
    { parent_ref: "EVIDENCE_ROOT", run_id: args.runId, creation_policy: "EXCLUSIVE_NOFOLLOW_OWNED_DIRECTORY" },
    { status: "CREATED_EXCLUSIVE", receipt: manifestReceipt(runRoot) });
  const context = {
    runRoot,
    runId: args.runId,
    repetitionId: args.repetitionId,
    telemetry,
    artifacts: new Map(),
    commandRecords: [],
    candidate,
    actionTrace,
  };
  addArtifact(context, "candidate_provenance", "candidate-provenance.json", canonicalJsonBytes({
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_run_provenance",
    run_id: context.runId,
    candidate_binding: candidate.binding,
  }));
  addArtifact(context, "tool_plan", "tool-plan.json", assets.planFile.bytes);
  addArtifact(context, "actual_executor", "actual-executor.json", canonicalJsonBytes(actualExecutor));
  const startedAt = new Date().toISOString();
  const materialized = await materializeBase(runRoot, assets, telemetry, actionTrace);
  context.materialized = materialized;
  const sourcePath = join(materialized.materialization.path, "src/range.mjs");
  let mutationOccurred = false;
  let pendingError;
  let rollback;
  try {
    const baseIssue = await executeRecordedCommand(context, COMMANDS[0]);
    validateBaseIssueOutput(baseIssue);
    const baseRegression = await executeRecordedCommand(context, COMMANDS[1]);
    validateSuccessOutput(baseRegression, "ordered ranges remain unchanged", "base regression");
    recordToolRequest(context, assets, 1);
    const applied = atomicReplaceOwned(sourcePath, EXPECTED_BASE.source, assets.admission.postimage, telemetry, "IR10 application");
    recordAction(actionTrace, "tool_step_1_atomic_postimage", "FILE_MUTATION", "TOOL_ACTION", 1,
      {
        target_path: "src/range.mjs",
        mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT",
        preimage: EXPECTED_BASE.source,
        postimage: EXPECTED_POSTIMAGE,
        compiler: identityReference(assets.taskCard.accepted_inputs.compiler.path, assets.taskCard.accepted_inputs.compiler),
        ir10: identityReference(IR10.relative_path, IR10),
      },
      {
        status: "ATOMIC_POSTIMAGE_APPLIED",
        atomic_rename: applied.atomic_rename,
        temporary_receipt: applied.temporary_receipt,
        source: createdFileReceipt(applied.file, "src/range.mjs"),
      });
    mutationOccurred = true;
    const status = (await runGit(materialized.materialization.path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materialized.environment, telemetry,
      "changed path status", context.actionTrace, "changed_path_git_status", "PATCH_EVIDENCE", 1)).stdout;
    assert(status.toString("utf8") === " M src/range.mjs\0", "PATCH_EVIDENCE_REJECTED", "changed path scope drifted");
    const patch = (await runGit(materialized.materialization.path, ["diff", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "--", "src/range.mjs"], materialized.environment, telemetry,
      "exact patch diff", context.actionTrace, "patch_git_diff", "PATCH_EVIDENCE", 1)).stdout;
    assert(patch.equals(PATCH_BYTES), "PATCH_EVIDENCE_REJECTED", "patch is not exact frozen IR10 diff");
    const patchEntry = addArtifact(context, "patch", "patch.diff", patch);
    recordAction(actionTrace, "patch_capture", "ARTIFACT_CREATION", "PATCH_EVIDENCE", 1,
      { source_action_id: "patch_git_diff", path: "patch.diff", creation_policy: "CREATE_ONCE_REGULAR_NOFOLLOW_NLINK_ONE" },
      { status: "CAPTURED_EXACT_PATCH", artifact: { path: patchEntry.path, byte_length: patchEntry.byte_length, sha256: patchEntry.sha256 } });
    recordToolRequest(context, assets, 2);
    const issue = await executeRecordedCommand(context, COMMANDS[2]);
    validateSuccessOutput(issue, "REP001_NEGATIVE_RANGE_ORDER", "patched issue");
    recordToolRequest(context, assets, 3);
    const regression = await executeRecordedCommand(context, COMMANDS[3]);
    validateSuccessOutput(regression, "ordered ranges remain unchanged", "patched regression");
  } catch (error) {
    pendingError = error;
  } finally {
    try {
      const current = safeReadRegular(sourcePath, undefined, "ROLLBACK_REJECTED", "source before rollback");
      if (current.identity.byte_length === EXPECTED_POSTIMAGE.byte_length && current.identity.sha256 === EXPECTED_POSTIMAGE.sha256) {
        const restored = atomicReplaceOwned(sourcePath, EXPECTED_POSTIMAGE, assets.sources.source_preimage.bytes, telemetry, "source rollback");
        recordAction(actionTrace, "rollback_atomic_restore", "FILE_MUTATION", "ROLLBACK", null,
          {
            target_path: "src/range.mjs",
            mutation_kind: "ATOMIC_COMPLETE_PREIMAGE_RESTORATION",
            current: EXPECTED_POSTIMAGE,
            restore: EXPECTED_BASE.source,
          },
          {
            status: "ATOMIC_PREIMAGE_RESTORED",
            atomic_rename: restored.atomic_rename,
            temporary_receipt: restored.temporary_receipt,
            source: createdFileReceipt(restored.file, "src/range.mjs"),
          });
      } else {
        assert(current.identity.byte_length === EXPECTED_BASE.source.byte_length && current.identity.sha256 === EXPECTED_BASE.source.sha256, "ROLLBACK_REJECTED", "source is neither exact preimage nor postimage");
      }
      rollback = await verifyRollback(materialized, telemetry, actionTrace);
    } catch (error) {
      pendingError = error;
    }
  }
  if (pendingError) throw pendingError;
  assert(mutationOccurred && rollback?.clean === true, "ROLLBACK_REJECTED", "positive run did not mutate and roll back exactly");
  addArtifact(context, "observation", "observation.json", canonicalJsonBytes({
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_run_observation",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    candidate_binding: candidate.binding,
    input_identities: {
      task_spec_sha256: TASK_SPEC.sha256,
      source_preimage_sha256: EXPECTED_BASE.source.sha256,
      postimage_sha256: EXPECTED_POSTIMAGE.sha256,
    },
    plan_identity: identityOf(assets.planFile.bytes),
    agent_status: AGENT_STATUS,
  }));
  addArtifact(context, "rollback", "rollback.json", canonicalJsonBytes({
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_rollback_receipt",
    present: true,
    run_id: context.runId,
    mutation_occurred: true,
    restored_source_byte_length: EXPECTED_BASE.source.byte_length,
    source_sha256: EXPECTED_BASE.source.sha256,
    head: rollback.head,
    tree: rollback.tree,
    clean: rollback.clean,
    extra_paths: rollback.extra_paths,
  }));
  addArtifact(context, "command_stream", "command-stream.json", canonicalJsonBytes({
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_command_stream_index",
    run_id: context.runId,
    commands: context.commandRecords,
  }));
  assert(context.commandRecords.length === COMMANDS.length, "COMMAND_STREAM_EVIDENCE_REJECTED", "command population drifted");
  recordAction(actionTrace, "retained_evidence_policy", "EVIDENCE_RETENTION", "ROLLBACK", null,
    {
      materialization_root_ref: "MATERIALIZATION_ROOT",
      policy: "RETAIN_FOR_INDEPENDENT_EVALUATION_NO_CLEANUP",
    },
    {
      status: "RETAINED_EXACT_MATERIALIZATION",
      materialization_receipt: manifestReceipt(materialized.materialization),
      deleted_paths: [],
      temporary_residue: false,
      preexisting_objects_touched: false,
    });
  const expectedActionIds = assets.taskCard.run_evidence_contract.action_trace_required_action_ids;
  assert(actionTrace.length === expectedActionIds.length &&
    sameJson(actionTrace.map((action) => action.action_id), expectedActionIds),
  "ACTION_TRACE_REJECTED", "complete action population/order drifted");
  addArtifact(context, "action_trace", "action-trace.json", canonicalJsonBytes(buildActionTrace(context)));
  addArtifact(context, "patch_evidence_package", "patch-evidence-package.json",
    canonicalJsonBytes(buildPatchEvidencePackage(context, assets, rollback)));
  const endedAt = new Date().toISOString();
  const runRecord = buildRunRecord(context, startedAt, endedAt);
  validateSchemaValue(runRecord, "docs/aios/schemas/run-record.schema.json", "RunRecord");
  addArtifact(context, "run_record", "run-record.json", canonicalJsonBytes(runRecord));
  assert(context.artifacts.size === ARTIFACT_LAYOUT.length, "EVIDENCE_IDENTITY_REJECTED", "artifact count drifted");
  const manifestArtifacts = ARTIFACT_LAYOUT.map(({ role, path }) => {
    const artifact = context.artifacts.get(path);
    assert(artifact?.role === role, "EVIDENCE_IDENTITY_REJECTED", `artifact ${path} role drifted`);
    return artifact.entry;
  });
  const manifest = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_run_manifest",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    candidate_binding: candidate.binding,
    run_root_receipt: manifestReceipt(runRoot),
    materialization_receipt: manifestReceipt(materialized.materialization),
    artifacts: manifestArtifacts,
    agent_status: AGENT_STATUS,
  };
  const manifestFile = writeCreateOnce(join(runRoot.path, "manifest.json"), canonicalJsonBytes(manifest));
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_worker_run_receipt",
    task_id: TASK_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    candidate_binding: candidate.binding,
    run_root: runRoot.path,
    materialization_root: materialized.materialization.path,
    manifest_path: manifestFile.path,
    manifest_byte_length: manifestFile.identity.byte_length,
    manifest_sha256: manifestFile.identity.sha256,
    agent_status: AGENT_STATUS,
    claim_boundary: CLAIM_BOUNDARY,
  };
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function mutatePlan(id, positive) {
  const plan = cloneJson(positive);
  if (id === "unknown-root-member") plan.unexpected = true;
  else if (id === "record-type-drift") plan.record_type = "unexpected";
  else if (id === "task-identity-drift") plan.task_binding.task_id = "OTHER";
  else if (id === "task-spec-hash-drift") plan.task_binding.task_spec_sha256 = "0".repeat(64);
  else if (id === "configuration-identity-drift") plan.configuration_binding.sha256 = "0".repeat(64);
  else if (id === "profile-identity-drift") plan.compatibility_profile_binding.sha256 = "0".repeat(64);
  else if (id === "live-model-provenance") plan.provenance.live_model_invoked = true;
  else if (id === "missing-step") plan.steps.pop();
  else if (id === "over-budget-step") plan.steps.push({ ordinal: 4, tool_id: "local-node-test", operation_id: "issue-test" });
  else if (id === "step-gap") plan.steps[1].ordinal = 3;
  else if (id === "duplicate-ordinal") plan.steps[1].ordinal = 1;
  else if (id === "reordered-steps") [plan.steps[0], plan.steps[1]] = [plan.steps[1], plan.steps[0]];
  else if (id === "forbidden-tool") plan.steps[0].tool_id = "shell";
  else if (id === "unsupported-operation") plan.steps[0].operation_id = "arbitrary";
  else if (id === "unknown-step-member") plan.steps[0].unexpected = true;
  else if (id.startsWith("dynamic-")) plan.steps[0][id.slice("dynamic-".length)] = "attacker-controlled";
  else if (id.startsWith("external-")) plan.requested_external_effects[id.slice("external-".length)] = true;
  else fail("SELF_TEST_FAILED", `unknown pre-admission case ${id}`);
  return canonicalJsonBytes(plan);
}

function expectAdapterCode(expectedCode, action) {
  try {
    action();
  } catch (error) {
    const observed = error instanceof OfflineB1AdapterError ? error.code : error.code;
    assert(observed === expectedCode, "SELF_TEST_FAILED", `expected ${expectedCode}, got ${observed ?? error.message}`);
    return observed;
  }
  fail("SELF_TEST_FAILED", `expected rejection ${expectedCode}`);
}

function failureHarnessSource(failureKind) {
  const behavior = failureKind === "output_overflow"
    ? 'setInterval(() => process.stdout.write("x".repeat(4096)), 1);'
    : failureKind === "signal"
      ? 'setTimeout(() => process.kill(process.pid, "SIGTERM"), 50);'
      : "";
  return [
    'const { spawn } = require("node:child_process");',
    `const descendant = spawn(${JSON.stringify(NODE_PATH)}, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });`,
    'descendant.once("spawn", () => {',
    '  process.stdout.write("DESCENDANT_READY\\n");',
    `  ${behavior}`,
    "});",
    "setInterval(() => {}, 1000);",
  ].join("\n");
}

async function exerciseWorkerFailurePath(root, failureKind, assets) {
  const runRoot = createExclusiveDirectory(join(root, `worker-failure-${failureKind}`));
  const telemetry = { materialization_creations: 0, mutation_attempts: 0, child_start_attempts: 0 };
  const materialized = await materializeBase(runRoot, assets, telemetry);
  const sourcePath = join(materialized.materialization.path, "src/range.mjs");
  atomicReplaceOwned(sourcePath, EXPECTED_BASE.source, assets.admission.postimage, telemetry, `${failureKind} precondition mutation`);
  let processOutcome;
  let successReported = false;
  try {
    await runManagedProcess({
      argv: [NODE_PATH, "-e", failureHarnessSource(failureKind)],
      cwd: materialized.materialization.path,
      env: { ...FIXED_ENV, HOME: materialized.home.path },
      timeoutMs: failureKind === "timeout" ? 200 : 1_000,
      maxOutputBytes: failureKind === "output_overflow" ? 8_192 : 1_048_576,
      expectedExitStatus: 0,
      telemetry,
      label: `worker ${failureKind} failure path`,
    });
    successReported = true;
  } catch (error) {
    assert(error instanceof ManagedProcessError, "SELF_TEST_FAILED", `${failureKind} did not use managed failure path`);
    processOutcome = error.outcome;
  } finally {
    const current = safeReadRegular(sourcePath, EXPECTED_POSTIMAGE, "SELF_TEST_FAILED", `${failureKind} mutated source`);
    assert(current.identity.sha256 === EXPECTED_POSTIMAGE.sha256, "SELF_TEST_FAILED", `${failureKind} source drifted before rollback`);
    atomicReplaceOwned(sourcePath, EXPECTED_POSTIMAGE, assets.sources.source_preimage.bytes, telemetry, `${failureKind} rollback`);
  }
  const rollback = await verifyRollback(materialized, telemetry);
  assert(!successReported && processOutcome?.failure_kind === failureKind && processOutcome.terminated === true && processOutcome.descendants_alive === false && processOutcome.stdout.includes(Buffer.from("DESCENDANT_READY\n")) && rollback.clean === true, "SELF_TEST_FAILED", `${failureKind} did not terminate descendants and roll back exactly`);
  return {
    failure_kind: failureKind,
    child_started: true,
    descendant_ready: true,
    terminated: true,
    descendants_alive: false,
    exact_rollback: true,
    success_reported: false,
    telemetry,
  };
}

async function createSelfTestCandidateRepository(root) {
  const repository = createExclusiveDirectory(join(root, "candidate-repository"));
  writeCreateOnce(join(repository.path, "candidate.txt"),
    Buffer.from("P1-067 CLEAN SELF-TEST CANDIDATE\n", "utf8"), 0o644);
  const environment = {
    HOME: createExclusiveDirectory(join(root, "candidate-home")).path,
    gitCommit: {
      GIT_AUTHOR_NAME: "SourceLens AIOS Self Test",
      GIT_AUTHOR_EMAIL: "self-test@sourcelens.local",
      GIT_AUTHOR_DATE: "2000-01-01T00:00:00Z",
      GIT_COMMITTER_NAME: "SourceLens AIOS Self Test",
      GIT_COMMITTER_EMAIL: "self-test@sourcelens.local",
      GIT_COMMITTER_DATE: "2000-01-01T00:00:00Z",
    },
  };
  const telemetry = { materialization_creations: 0, mutation_attempts: 0, child_start_attempts: 0 };
  await runGit(repository.path, ["init", "--quiet", "--initial-branch=main"], environment, telemetry, "self-test candidate git init");
  await runGit(repository.path, ["add", "--", "candidate.txt"], environment, telemetry, "self-test candidate git add");
  await runGit(repository.path, ["commit", "--quiet", "--no-gpg-sign", "-m", "candidate: clean self-test"], environment, telemetry, "self-test candidate git commit");
  const commit = (await runGit(repository.path, ["rev-parse", "HEAD"], environment, telemetry, "self-test candidate HEAD")).stdout.toString("utf8").trim();
  const tree = (await runGit(repository.path, ["rev-parse", "HEAD^{tree}"], environment, telemetry, "self-test candidate tree")).stdout.toString("utf8").trim();
  const status = (await runGit(repository.path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], environment, telemetry, "self-test candidate status")).stdout;
  assert(/^[0-9a-f]{40}$/.test(commit) && /^[0-9a-f]{40}$/.test(tree) && status.length === 0,
    "SELF_TEST_FAILED", "self-test candidate is not exact clean Git state");
  return { repository: repository.path, binding: { commit, tree, clean: true } };
}

async function performSelfTest() {
  const temporary = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-067-worker-"));
  const temporaryStat = lstatSync(temporary);
  const markerPath = join(temporary, ".owned-worker-self-test");
  const markerBytes = Buffer.from("P1-067-WORKER-SELF-TEST\n", "utf8");
  writeCreateOnce(markerPath, markerBytes);
  let result;
  try {
    const assets = validateFrozenInputs(TASK_CARD_PATH);
    const selfTestCandidate = await createSelfTestCandidateRepository(temporary);
    const positiveRoot = createExclusiveDirectory(join(temporary, "positive"));
    const runAReceipt = await performRun({ taskCard: TASK_CARD_PATH, evidenceRoot: positiveRoot.path, runId: "worker-run-a", repetitionId: 1 },
      { selfTestRoot: temporary, candidateBinding: selfTestCandidate.binding, candidateRepository: selfTestCandidate.repository });
    const runBReceipt = await performRun({ taskCard: TASK_CARD_PATH, evidenceRoot: positiveRoot.path, runId: "worker-run-b", repetitionId: 2 },
      { selfTestRoot: temporary, candidateBinding: selfTestCandidate.binding, candidateRepository: selfTestCandidate.repository });
    const evaluatedA = evaluateRunEvidence(runAReceipt.manifest_path,
      {
        allowedRoot: temporary,
        candidateRepository: selfTestCandidate.repository,
        qualityFreezeRoot: dirname(QUALITY_FREEZE_PATH),
      });
    const evaluatedB = evaluateRunEvidence(runBReceipt.manifest_path,
      {
        allowedRoot: temporary,
        candidateRepository: selfTestCandidate.repository,
        qualityFreezeRoot: dirname(QUALITY_FREEZE_PATH),
      });
    const comparison = compareStableRuns(evaluatedA, evaluatedB);

    const positivePlan = parseJson(assets.planFile.bytes, "SELF_TEST_FAILED", "positive plan", true);
    const negativeFile = safeReadRegular(QUALITY_ASSET_PATHS.negative_cases, QUALITY_ASSET_IDENTITIES.negative_cases, "SELF_TEST_FAILED", "negative matrix");
    const negative = parseJson(negativeFile.bytes, "SELF_TEST_FAILED", "negative matrix");
    const preAdmissionTelemetry = { materialization_creations: 0, mutation_attempts: 0, child_start_attempts: 0 };
    const preAdmissionOutcomes = [];
    for (const testCase of negative.cases.filter((entry) => entry.stage === "PRE_ADMISSION")) {
      let bytes;
      if (testCase.id === "non-canonical-json") bytes = Buffer.from(JSON.stringify(positivePlan), "utf8");
      else if (testCase.id === "duplicate-json-key") bytes = Buffer.from(assets.planFile.bytes.toString("utf8").replace('"schema_version":1,', '"schema_version":1,"schema_version":1,'), "utf8");
      else if (testCase.id === "malformed-json") bytes = Buffer.from("{", "utf8");
      else bytes = mutatePlan(testCase.id, positivePlan);
      const observed = expectAdapterCode(testCase.expected_reason_code, () => admitOfflineB1ToolPlan(bytes, assets.ir10File.bytes));
      preAdmissionOutcomes.push({ id: testCase.id, expected_reason_code: testCase.expected_reason_code, observed_reason_code: observed, admitted: false });
    }
    assert(sameJson(preAdmissionTelemetry, { materialization_creations: 0, mutation_attempts: 0, child_start_attempts: 0 }), "SELF_TEST_FAILED", "invalid pre-admission caused unsafe work");

    const failureOutcomes = [];
    for (const failureKind of ["timeout", "output_overflow", "signal"]) {
      failureOutcomes.push(await exerciseWorkerFailurePath(temporary, failureKind, assets));
    }
    result = {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_067_worker_self_test",
      task_id: TASK_ID,
      adapter_version: ADAPTER_VERSION,
      positive_run_a: { manifest_sha256: runAReceipt.manifest_sha256, evaluator_verdict: evaluatedA.verdict },
      positive_run_b: { manifest_sha256: runBReceipt.manifest_sha256, evaluator_verdict: evaluatedB.verdict },
      stable_projection: comparison,
      pre_admission_negative_case_count: preAdmissionOutcomes.length,
      pre_admission_negative_outcomes: preAdmissionOutcomes,
      pre_admission_telemetry: preAdmissionTelemetry,
      actual_worker_failure_path_count: failureOutcomes.length,
      actual_worker_failure_path_outcomes: failureOutcomes,
      false_accepts: 0,
      target_verdict: "PASS",
      claim_boundary: CLAIM_BOUNDARY,
    };
  } finally {
    const current = lstatSync(temporary);
    assert(current.isDirectory() && !current.isSymbolicLink() && current.dev === temporaryStat.dev && current.ino === temporaryStat.ino && current.uid === temporaryStat.uid, "SELF_TEST_CLEANUP_REJECTED", "self-test root identity drifted");
    const marker = safeReadRegular(markerPath, identityOf(markerBytes), "SELF_TEST_CLEANUP_REJECTED", "self-test marker");
    assert(marker.bytes.equals(markerBytes), "SELF_TEST_CLEANUP_REJECTED", "self-test marker drifted");
    rmSync(temporary, { recursive: true, force: false });
  }
  return result;
}

function parseCli(argv) {
  const mode = argv[0];
  assert(mode === "run" || mode === "self-test", "CLI_REJECTED", "mode must be run or self-test");
  if (mode === "self-test") {
    assert(argv.length === 1, "CLI_REJECTED", "self-test takes no arguments");
    return { mode };
  }
  const values = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    assert(flag?.startsWith("--") && value !== undefined && !values.has(flag), "CLI_REJECTED", "invalid or duplicate CLI flag");
    values.set(flag, value);
  }
  const allowed = new Set(["--task-card", "--candidate-manifest", "--evidence-root", "--run-id", "--repetition-id"]);
  assert(values.size === allowed.size && [...values.keys()].every((key) => allowed.has(key)), "CLI_REJECTED", "run flag set mismatch");
  const repetitionId = Number(values.get("--repetition-id"));
  assert(Number.isInteger(repetitionId) && repetitionId >= 1, "CLI_REJECTED", "repetition id is invalid");
  return {
    mode,
    taskCard: values.get("--task-card"),
    candidateManifest: values.get("--candidate-manifest"),
    evidenceRoot: values.get("--evidence-root"),
    runId: values.get("--run-id"),
    repetitionId,
  };
}

function publicError(error) {
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_worker_error",
    task_id: TASK_ID,
    reason_code: error instanceof RunnerError || error instanceof OfflineB1AdapterError ? error.code : "UNEXPECTED_ERROR",
    message: error instanceof Error ? error.message : String(error),
    agent_status: "NON_PASS",
  };
}

try {
  const args = parseCli(process.argv.slice(2));
  const result = args.mode === "self-test" ? await performSelfTest() : await performRun(args);
  process.stdout.write(canonicalJsonBytes(result));
} catch (error) {
  process.stderr.write(canonicalJsonBytes(publicError(error)));
  process.exitCode = 2;
}

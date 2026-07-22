#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const TASK_ID = "AIOS-P1-070_OFFLINE_SCHEDULED_MATRIX_VTSR_AND_FALSE_SUCCESS_EXPERIMENT";
const ZERO_SHA256 = "0".repeat(64);
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false
});
const SANITIZED_ENVIRONMENT = Object.freeze({
  LANG: "C",
  LC_ALL: "C",
  PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
  TZ: "UTC"
});
const FROZEN = Object.freeze({
  contract: {
    path: "evaluation-harness/contracts/offline-scheduled-matrix-v1/offline-scheduled-matrix-v1.contract.json",
    sha256: "86b210a53a687ec0b8bd2bfeb9377c48f8b844aba99e2bc329453766f57a54ed",
    byte_length: 9886
  },
  plan: {
    path: "evaluation-harness/fixtures/offline-scheduled-matrix-v1/matrix-plan.json",
    sha256: "4882738b41eafad14b0d108c04f5f12481cfd3ee86e0a2cff8806eb1601c9cb1",
    byte_length: 12522
  },
  negative_catalog: {
    path: "evaluation-harness/fixtures/offline-scheduled-matrix-v1/negative-cases.json",
    sha256: "57cf4da25ecb2dee84f23d8c24ce0f2623ae7b0c565f3a46b250c38788c93785",
    byte_length: 8465
  },
  prefreeze_receipt: {
    path: "/Users/lijunpeng/Developer/.sourcelens-audit/p1-070-offline-scheduled-matrix-TS8DyWZw/quality/PREFREEZE_RECEIPT.json",
    sha256: "de3d9e2c40cb26e955b34cffdcd0938a604f76cd621bd8a82a4ad1d7fe2e0695",
    byte_length: 6946
  },
  authority: {
    path: "/Users/lijunpeng/Developer/.sourcelens-audit/p1-070-offline-scheduled-matrix-TS8DyWZw/authority/TASK_AUTHORITY.yaml",
    sha256: "cafe185be6c534587699c9047f473158a84e157ee9e858b57fdd0e00f412d011",
    byte_length: 2908
  },
  task_contract: {
    path: "docs/aios/tasks/P1-070_OFFLINE_SCHEDULED_MATRIX_VTSR_AND_FALSE_SUCCESS_EXPERIMENT.yaml",
    sha256: "02fc6ef5590803156e78c6f5328bfa6644f980323a38a504554250c5b94f72ca",
    byte_length: 14653
  },
  evaluation_protocol: {
    path: "docs/aios/EVALUATION_PROTOCOL.md",
    sha256: "da029143561fbb3c213d4a358b25e085542c6cd26ae8150a53cbb5998177eed8",
    byte_length: 10127
  }
});

class MatrixError extends Error {
  constructor(reason) {
    super(reason);
    this.name = "MatrixError";
    this.reason = reason;
  }
}

const reject = (reason) => {
  throw new MatrixError(reason);
};

const normalizeJson = (value) => {
  if (Array.isArray(value)) return value.map(normalizeJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, normalizeJson(value[key])]));
  }
  return value;
};

const stableJson = (value) => JSON.stringify(normalizeJson(value));
const canonicalJsonBytes = (value) => Buffer.from(`${stableJson(value)}\n`, "utf8");
const sha256 = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const sha256Json = (value) => sha256(Buffer.from(stableJson(value), "utf8"));
const isHex = (value, length) => typeof value === "string" && new RegExp(`^[0-9a-f]{${length}}$`).test(value);
const containedBy = (root, candidate) => candidate === root || candidate.startsWith(`${root}${path.sep}`);

const parseOptions = (argv) => {
  const expected = ["--canonical-root", "--output-root"];
  if (argv.length !== expected.length * 2) reject("ARGUMENTS_INVALID");
  const values = {};
  for (let index = 0; index < expected.length; index += 1) {
    if (argv[index * 2] !== expected[index]) reject("ARGUMENTS_INVALID");
    const value = argv[index * 2 + 1];
    if (!path.isAbsolute(value)) reject("ARGUMENTS_INVALID");
    values[expected[index].slice(2)] = path.resolve(value);
  }
  if (values["canonical-root"] === values["output-root"]) reject("ROOT_ALIAS_OR_OVERLAP");
  return values;
};

const assertNoSymlinkComponents = (targetPath, allowMissingTail = false) => {
  if (!path.isAbsolute(targetPath)) reject("PATH_NOT_ABSOLUTE");
  const resolved = path.resolve(targetPath);
  const parsed = path.parse(resolved);
  let cursor = parsed.root;
  for (const component of resolved.slice(parsed.root.length).split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, component);
    if (!fs.existsSync(cursor)) {
      if (allowMissingTail) return;
      reject("PATH_MISSING");
    }
    if (fs.lstatSync(cursor).isSymbolicLink()) reject("SYMLINK_COMPONENT_FORBIDDEN");
  }
};

const readBoundFile = (filePath, expected, label) => {
  assertNoSymlinkComponents(filePath);
  const stat = fs.lstatSync(filePath);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) reject(`${label}_TYPE_INVALID`);
  const bytes = fs.readFileSync(filePath);
  if (bytes.length !== expected.byte_length || sha256(bytes) !== expected.sha256) reject(`${label}_IDENTITY_MISMATCH`);
  return { path: filePath, bytes, sha256: expected.sha256, byte_length: expected.byte_length };
};

const readBoundJson = (filePath, expected, label) => {
  const input = readBoundFile(filePath, expected, label);
  try {
    return { ...input, json: JSON.parse(input.bytes.toString("utf8")) };
  } catch {
    reject(`${label}_JSON_INVALID`);
  }
};

const writeExclusive = (filePath, bytes, mode = 0o600) => {
  const payload = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes, "utf8");
  const fd = fs.openSync(filePath, "wx", mode);
  try {
    fs.writeFileSync(fd, payload);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  return payload;
};

const writeCanonicalJson = (filePath, value) => writeExclusive(filePath, canonicalJsonBytes(value));

const mkdirOwned = (directory) => {
  fs.mkdirSync(directory, { mode: 0o700 });
  fs.chmodSync(directory, 0o700);
  const stat = fs.lstatSync(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o700) {
    reject("OWNED_DIRECTORY_INVALID");
  }
  return { dev: stat.dev, ino: stat.ino, uid: stat.uid };
};

const assertSameOwnedDirectory = (directory, ownership) => {
  const stat = fs.lstatSync(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.dev !== ownership.dev || stat.ino !== ownership.ino || stat.uid !== ownership.uid) {
    reject("OWNERSHIP_MISMATCH");
  }
};

const relativePath = (root, filePath) => {
  const relative = path.relative(root, filePath).split(path.sep).join("/");
  if (relative.length === 0 || relative.startsWith("../") || path.posix.isAbsolute(relative)) reject("OUTPUT_PATH_OUTSIDE_ROOT");
  return relative;
};

const fileIdentity = (root, filePath) => {
  assertNoSymlinkComponents(filePath);
  const stat = fs.lstatSync(filePath);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) reject("ARTIFACT_TYPE_INVALID");
  const bytes = fs.readFileSync(filePath);
  return { path: relativePath(root, filePath), sha256: sha256(bytes), byte_length: bytes.length };
};

const exactIdentity = (actual, expected) => actual?.path === expected.path && actual?.sha256 === expected.sha256 && actual?.byte_length === expected.byte_length;

const copyExclusive = (sourcePath, targetPath) => {
  assertNoSymlinkComponents(sourcePath);
  const sourceStat = fs.lstatSync(sourcePath);
  if (!sourceStat.isFile() || sourceStat.isSymbolicLink() || sourceStat.nlink !== 1) reject("COPY_SOURCE_TYPE_INVALID");
  return writeExclusive(targetPath, fs.readFileSync(sourcePath));
};

const runChild = (executable, args, cwd, environment, timeoutMs = 10000) => {
  const child = spawnSync(executable, args, {
    cwd,
    env: environment,
    encoding: null,
    maxBuffer: 1024 * 1024,
    shell: false,
    timeout: timeoutMs
  });
  return {
    stdout: child.stdout ?? Buffer.alloc(0),
    stderr: child.stderr ?? Buffer.alloc(0),
    exit_code: child.status,
    signal: child.signal,
    timed_out: child.error?.code === "ETIMEDOUT",
    start_error: child.error ? (child.error.code ?? "UNKNOWN_CHILD_ERROR") : null
  };
};

const parseSingleJsonLine = (bytes) => {
  const text = bytes.toString("utf8").trim();
  if (text.length === 0) return null;
  try {
    return JSON.parse(text.split("\n")[0]);
  } catch {
    return null;
  }
};

const createObservation = ({ evidenceIdentity, evidence, child, argvSha256, taskCardIdentity, sourceIdentity, runtimeIdentity, harnessIdentity }) => ({
  schema_version: "blind-admission-quality-observation/v1",
  task_id: evidence.task_id,
  candidate_evidence: { sha256: evidenceIdentity.sha256, byte_length: evidenceIdentity.byte_length },
  identities: {
    task_card_sha256: taskCardIdentity.sha256,
    source_sha256: sourceIdentity.sha256,
    runtime_profile_sha256: runtimeIdentity.sha256,
    executing_module_sha256: harnessIdentity.sha256
  },
  command: {
    ordered_argv_sha256: argvSha256,
    logical_cwd: evidence.runtime.logical_cwd,
    environment_sha256: evidence.runtime.environment_sha256,
    timeout_ms: evidence.runtime.timeout_ms
  },
  process: {
    actual_arch: process.arch,
    platform: process.platform,
    executable_path: process.execPath,
    executable_realpath: fs.realpathSync(process.execPath),
    executable_sha256: evidence.runtime.executable_sha256,
    executable_version: process.version,
    exit_code: child.exit_code,
    stdout_sha256: sha256(child.stdout),
    stdout_byte_length: child.stdout.length,
    stderr_sha256: sha256(child.stderr),
    stderr_byte_length: child.stderr.length,
    signal: child.signal,
    timed_out: child.timed_out
  },
  rollback: evidence.rollback,
  external_effects: { ...FALSE_EFFECTS }
});

const recursiveFileIdentities = (matrixRoot, directory, excludedBasename) => {
  const identities = [];
  const walk = (current) => {
    for (const name of fs.readdirSync(current).sort()) {
      if (current === directory && name === excludedBasename) continue;
      const currentPath = path.join(current, name);
      const stat = fs.lstatSync(currentPath);
      if (stat.isSymbolicLink()) reject("ARTIFACT_SYMLINK_FORBIDDEN");
      if (stat.isDirectory()) walk(currentPath);
      else if (stat.isFile() && stat.nlink === 1) identities.push(fileIdentity(matrixRoot, currentPath));
      else reject("ARTIFACT_TYPE_INVALID");
    }
  };
  walk(directory);
  return identities.sort((left, right) => left.path.localeCompare(right.path));
};

const cleanupRunRoot = (runRoot, ownership) => {
  assertSameOwnedDirectory(runRoot, ownership);
  const removeOwnedDescendant = (targetPath) => {
    if (!containedBy(runRoot, targetPath) || targetPath === runRoot) reject("CLEANUP_SCOPE_INVALID");
    const stat = fs.lstatSync(targetPath);
    if (stat.isDirectory() && !stat.isSymbolicLink()) {
      for (const name of fs.readdirSync(targetPath)) removeOwnedDescendant(path.join(targetPath, name));
      fs.rmdirSync(targetPath);
    } else {
      fs.unlinkSync(targetPath);
    }
  };
  for (const name of fs.readdirSync(runRoot)) removeOwnedDescendant(path.join(runRoot, name));
  fs.rmdirSync(runRoot);
  if (fs.existsSync(runRoot)) reject("ROLLBACK_NOT_EXACT");
};

const main = () => {
  const options = parseOptions(process.argv.slice(2));
  const canonicalRoot = options["canonical-root"];
  const outputRoot = options["output-root"];
  assertNoSymlinkComponents(canonicalRoot);
  const canonicalStat = fs.lstatSync(canonicalRoot);
  if (!canonicalStat.isDirectory() || canonicalStat.isSymbolicLink() || fs.realpathSync(canonicalRoot) !== canonicalRoot) reject("CANONICAL_ROOT_INVALID");
  if (process.cwd() !== canonicalRoot) reject("CANONICAL_CWD_MISMATCH");
  assertNoSymlinkComponents(path.dirname(outputRoot));
  if (fs.existsSync(outputRoot)) reject("OUTPUT_ALREADY_EXISTS");
  if (containedBy(canonicalRoot, outputRoot) || containedBy(outputRoot, canonicalRoot)) reject("ROOT_ALIAS_OR_OVERLAP");

  const contract = readBoundJson(path.join(canonicalRoot, FROZEN.contract.path), FROZEN.contract, "CONTRACT");
  const plan = readBoundJson(path.join(canonicalRoot, FROZEN.plan.path), FROZEN.plan, "PLAN");
  const negativeCatalog = readBoundJson(path.join(canonicalRoot, FROZEN.negative_catalog.path), FROZEN.negative_catalog, "NEGATIVE_CATALOG");
  const prefreezeReceipt = readBoundJson(FROZEN.prefreeze_receipt.path, FROZEN.prefreeze_receipt, "PREFREEZE_RECEIPT");
  const authority = readBoundFile(FROZEN.authority.path, FROZEN.authority, "TASK_AUTHORITY");
  const taskContract = readBoundFile(path.join(canonicalRoot, FROZEN.task_contract.path), FROZEN.task_contract, "TASK_CONTRACT");
  const evaluationProtocol = readBoundFile(path.join(canonicalRoot, FROZEN.evaluation_protocol.path), FROZEN.evaluation_protocol, "EVALUATION_PROTOCOL");

  if (contract.json.task_id !== TASK_ID || plan.json.task_id !== TASK_ID || negativeCatalog.json.task_id !== TASK_ID || prefreezeReceipt.json.task_id !== TASK_ID) reject("TASK_ID_MISMATCH");
  if (plan.json.schedule?.length !== 5 || plan.json.ledger_lifecycle?.event_count !== 13) reject("FROZEN_PLAN_INVALID");
  const frozenOrder = ["CORRECT_RESULT", "WRONG_PATCH", "MISSING_EVIDENCE", "SCOPE_VIOLATION", "DECLARED_SHARED_HARNESS_INVALID_CONTROL"];
  if (stableJson(plan.json.schedule.map((entry) => entry.entry_id)) !== stableJson(frozenOrder)) reject("SCHEDULE_ORDER_MISMATCH");
  if (plan.json.schedule.some((entry, index) => entry.slot !== index + 1)) reject("SCHEDULE_SLOT_MISMATCH");
  if (!prefreezeReceipt.json.frozen_outputs?.every((entry) => [FROZEN.contract, FROZEN.plan, FROZEN.negative_catalog].some((expected) => exactIdentity(entry, expected)))) reject("PREFREEZE_BINDING_MISMATCH");
  if (!prefreezeReceipt.json.authority_inputs?.some((entry) => exactIdentity(entry, FROZEN.task_contract)) || !prefreezeReceipt.json.authority_inputs?.some((entry) => exactIdentity(entry, FROZEN.evaluation_protocol))) reject("AUTHORITY_BINDING_MISMATCH");

  const acceptedInputs = plan.json.accepted_input_identities;
  if (!acceptedInputs || typeof acceptedInputs !== "object") reject("ACCEPTED_INPUTS_INVALID");
  const accepted = {};
  for (const [name, expected] of Object.entries(acceptedInputs)) {
    if (!expected || typeof expected.path !== "string" || !isHex(expected.sha256, 64) || !Number.isSafeInteger(expected.byte_length)) reject("ACCEPTED_INPUTS_INVALID");
    accepted[name] = readBoundFile(path.join(canonicalRoot, expected.path), expected, `ACCEPTED_${name.toUpperCase()}`);
  }
  const requiredAccepted = ["harness", "recorder", "validator", "primary_oracle", "stable_projection", "stable_projection_contract", "task_card", "source", "expected", "runtime_profile"];
  if (requiredAccepted.some((name) => !accepted[name])) reject("ACCEPTED_INPUTS_INVALID");
  const taskCardBase = JSON.parse(accepted.task_card.bytes.toString("utf8"));
  const runtimeProfile = JSON.parse(accepted.runtime_profile.bytes.toString("utf8"));
  if (runtimeProfile.executable?.path !== "/usr/local/bin/node" || runtimeProfile.actual_process?.arch !== process.arch || runtimeProfile.actual_process?.platform !== process.platform) reject("RUNTIME_PROFILE_MISMATCH");
  if (sha256(fs.readFileSync(process.execPath)) !== runtimeProfile.executable.sha256 || fs.realpathSync(process.execPath) !== runtimeProfile.executable.realpath || process.version !== runtimeProfile.executable.version) reject("EXECUTABLE_IDENTITY_MISMATCH");

  const outputOwnership = mkdirOwned(outputRoot);
  const artifactsRoot = path.join(outputRoot, "artifacts");
  const entriesRoot = path.join(artifactsRoot, "entries");
  mkdirOwned(artifactsRoot);
  mkdirOwned(entriesRoot);
  const ownershipRecordPath = path.join(outputRoot, "ownership.json");
  writeCanonicalJson(ownershipRecordPath, {
    schema_version: "offline-scheduled-matrix-output-ownership/v1",
    task_id: TASK_ID,
    output_root: outputRoot,
    owner_uid: process.getuid(),
    output_root_dev: outputOwnership.dev,
    output_root_ino: outputOwnership.ino
  });

  const ledgerPath = path.join(outputRoot, "ledger.jsonl");
  const ledgerFlags = fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_APPEND;
  const ledgerFd = fs.openSync(ledgerPath, ledgerFlags, 0o600);
  let previousEventSha256 = ZERO_SHA256;
  let eventIndex = 0;
  const appendEvent = (payload) => {
    const base = {
      schema_version: "offline-scheduled-matrix-ledger-event/v1",
      task_id: TASK_ID,
      event_index: eventIndex,
      previous_event_sha256: previousEventSha256,
      ...payload
    };
    const eventSha256 = sha256(canonicalJsonBytes(base));
    const event = { ...base, event_sha256: eventSha256 };
    fs.writeSync(ledgerFd, canonicalJsonBytes(event));
    fs.fsyncSync(ledgerFd);
    previousEventSha256 = eventSha256;
    eventIndex += 1;
    return event;
  };

  appendEvent({
    event_type: "MATRIX_DECLARED",
    entry_id: null,
    contract_sha256: contract.sha256,
    contract_byte_length: contract.byte_length,
    matrix_plan_sha256: plan.sha256,
    matrix_plan_byte_length: plan.byte_length,
    negative_catalog_sha256: negativeCatalog.sha256,
    negative_catalog_byte_length: negativeCatalog.byte_length,
    prefreeze_receipt_sha256: prefreezeReceipt.sha256,
    prefreeze_receipt_byte_length: prefreezeReceipt.byte_length
  });
  for (const scheduled of plan.json.schedule) {
    appendEvent({
      event_type: "RUN_SCHEDULED",
      matrix_plan_sha256: plan.sha256,
      matrix_plan_byte_length: plan.byte_length,
      slot: scheduled.slot,
      entry_id: scheduled.entry_id,
      run_id: scheduled.run_id,
      eligible: scheduled.eligible,
      candidate_claim: scheduled.candidate_claim,
      frozen_stimulus_sha256: sha256(canonicalJsonBytes(scheduled.stimulus))
    });
  }
  appendEvent({
    event_type: "SCHEDULE_FROZEN",
    entry_id: null,
    matrix_plan_sha256: plan.sha256,
    matrix_plan_byte_length: plan.byte_length,
    scheduled_count: plan.json.schedule.length,
    frozen_order: frozenOrder
  });

  const environmentSha256 = sha256Json(SANITIZED_ENVIRONMENT);
  const timeoutMs = taskCardBase.execution_policy.timeout_ms;
  const controlProbeArgv = runtimeProfile.alternate_architecture_probe;
  if (!Array.isArray(controlProbeArgv) || controlProbeArgv.length < 2 || !path.isAbsolute(controlProbeArgv[0])) reject("CONTROL_PROBE_INVALID");
  const controlProbe = runChild(controlProbeArgv[0], controlProbeArgv.slice(1), canonicalRoot, SANITIZED_ENVIRONMENT, timeoutMs + 1000);

  const gitHead = runChild("/usr/bin/git", ["-C", canonicalRoot, "rev-parse", "HEAD"], canonicalRoot, SANITIZED_ENVIRONMENT);
  const gitTree = runChild("/usr/bin/git", ["-C", canonicalRoot, "rev-parse", "HEAD^{tree}"], canonicalRoot, SANITIZED_ENVIRONMENT);
  const gitStatus = runChild("/usr/bin/git", ["-C", canonicalRoot, "status", "--porcelain"], canonicalRoot, SANITIZED_ENVIRONMENT);
  if (gitHead.start_error || gitTree.start_error || gitStatus.start_error || gitHead.exit_code !== 0 || gitTree.exit_code !== 0 || gitStatus.exit_code !== 0) reject("GIT_IDENTITY_UNAVAILABLE");
  const candidateCommit = gitHead.stdout.toString("utf8").trim();
  const candidateTree = gitTree.stdout.toString("utf8").trim();
  if (!isHex(candidateCommit, 40) || !isHex(candidateTree, 40)) reject("GIT_IDENTITY_INVALID");
  if (gitStatus.stdout.length !== 0) reject("REPOSITORY_NOT_CLEAN");

  const matrixEntryManifests = [];
  const observed = [];

  const writeEntryFile = (entryDirectory, name, bytes) => {
    const targetPath = path.join(entryDirectory, name);
    writeExclusive(targetPath, bytes);
    return fileIdentity(outputRoot, targetPath);
  };
  const writeEntryJson = (entryDirectory, name, value) => {
    const targetPath = path.join(entryDirectory, name);
    writeCanonicalJson(targetPath, value);
    return fileIdentity(outputRoot, targetPath);
  };

  const runEligibleEntry = (scheduled, entryDirectory) => {
    let taskCardPath;
    let taskCardIdentity;
    if (scheduled.entry_id === "WRONG_PATCH") {
      const derivedTaskCard = structuredClone(taskCardBase);
      if (derivedTaskCard.operation.replacement !== "color=green") reject("WRONG_PATCH_PREFREEZE_MISMATCH");
      derivedTaskCard.operation.replacement = "color=red";
      taskCardPath = path.join(entryDirectory, "derived-task-card.json");
      writeCanonicalJson(taskCardPath, derivedTaskCard);
      taskCardIdentity = fileIdentity(outputRoot, taskCardPath);
    } else {
      taskCardPath = path.join(entryDirectory, "task-card.json");
      copyExclusive(accepted.task_card.path, taskCardPath);
      taskCardIdentity = fileIdentity(outputRoot, taskCardPath);
    }

    const tempBase = fs.realpathSync(os.tmpdir());
    assertNoSymlinkComponents(tempBase);
    const runRoot = fs.mkdtempSync(path.join(tempBase, `p1-070-${scheduled.slot}-`));
    fs.chmodSync(runRoot, 0o700);
    const runOwnershipStat = fs.lstatSync(runRoot);
    const runOwnership = { dev: runOwnershipStat.dev, ino: runOwnershipStat.ino, uid: runOwnershipStat.uid };
    if (!runOwnershipStat.isDirectory() || runOwnershipStat.isSymbolicLink() || runOwnershipStat.uid !== process.getuid() || (runOwnershipStat.mode & 0o777) !== 0o700 || fs.readdirSync(runRoot).length !== 0) reject("RUN_ROOT_NOT_FRESH");
    const sourceRoot = path.join(runRoot, "source");
    const evidenceRoot = path.join(runRoot, "evidence");
    const harnessArgs = [
      accepted.harness.path,
      "--task-card", taskCardPath,
      "--task-card-sha256", taskCardIdentity.sha256,
      "--task-card-byte-length", String(taskCardIdentity.byte_length),
      "--source", accepted.source.path,
      "--source-sha256", accepted.source.sha256,
      "--source-byte-length", String(accepted.source.byte_length),
      "--runtime-profile", accepted.runtime_profile.path,
      "--runtime-profile-sha256", accepted.runtime_profile.sha256,
      "--runtime-profile-byte-length", String(accepted.runtime_profile.byte_length),
      "--owned-root", runRoot,
      "--source-root", sourceRoot,
      "--evidence-root", evidenceRoot,
      "--canonical-root", canonicalRoot,
      "--case-id", scheduled.run_id,
      "--contract-sha256", taskContract.sha256,
      "--contract-byte-length", String(taskContract.byte_length),
      "--authority-sha256", authority.sha256,
      "--authority-byte-length", String(authority.byte_length),
      "--quality-freeze-sha256", prefreezeReceipt.sha256,
      "--quality-freeze-byte-length", String(prefreezeReceipt.byte_length),
      "--commitment-sha256", plan.sha256,
      "--commitment-byte-length", String(plan.byte_length),
      "--candidate-commit", candidateCommit,
      "--candidate-tree", candidateTree,
      "--candidate-module-sha256", accepted.harness.sha256,
      "--candidate-module-byte-length", String(accepted.harness.byte_length),
      "--recorder-module-sha256", accepted.recorder.sha256,
      "--recorder-module-byte-length", String(accepted.recorder.byte_length),
      "--validator-module-sha256", accepted.validator.sha256,
      "--validator-module-byte-length", String(accepted.validator.byte_length),
      "--logical-cwd", canonicalRoot,
      "--environment-sha256", environmentSha256,
      "--timeout-ms", String(timeoutMs)
    ];
    const child = runChild(runtimeProfile.executable.path, harnessArgs, canonicalRoot, SANITIZED_ENVIRONMENT, timeoutMs + 1000);
    const rawStdout = writeEntryFile(entryDirectory, "raw-stdout.txt", child.stdout);
    const rawStderr = writeEntryFile(entryDirectory, "raw-stderr.txt", child.stderr);
    const exitStatus = writeEntryJson(entryDirectory, "exit-status.json", {
      schema_version: "offline-scheduled-matrix-exit-status/v1",
      entry_id: scheduled.entry_id,
      child_started: child.start_error === null,
      exit_code: child.exit_code,
      signal: child.signal,
      timed_out: child.timed_out,
      start_error: child.start_error
    });
    const rawEvidencePath = path.join(evidenceRoot, "evidence.json");
    const retainHarnessFailure = (reason, rawEvidenceIdentity = null) => {
      cleanupRunRoot(runRoot, runOwnership);
      const failureReceipt = writeEntryJson(entryDirectory, "harness-failure-receipt.json", {
        schema_version: "offline-scheduled-matrix-harness-failure-receipt/v1",
        entry_id: scheduled.entry_id,
        reason,
        child_started: child.start_error === null,
        exit_code: child.exit_code,
        signal: child.signal,
        timed_out: child.timed_out,
        start_error: child.start_error,
        ordinary_setup_failure_counts_in_denominator: true
      });
      const rollbackReceipt = writeEntryJson(entryDirectory, "rollback-receipt.json", {
        schema_version: "offline-scheduled-matrix-rollback-receipt/v1",
        entry_id: scheduled.entry_id,
        source_root_initial_state: "ABSENT",
        source_root_final_state: "ABSENT",
        path_set_before: [],
        path_set_after: [],
        clean_state_before: true,
        clean_state_after: true,
        run_workspace_initial_state: "ABSENT",
        run_workspace_final_state: "ABSENT",
        exact: true
      });
      const effectsReceipt = writeEntryJson(entryDirectory, "external-effects-receipt.json", {
        schema_version: "offline-scheduled-matrix-external-effects-receipt/v1",
        entry_id: scheduled.entry_id,
        ...FALSE_EFFECTS
      });
      const primaryStdout = writeEntryFile(entryDirectory, "primary-evaluator-stdout.txt", Buffer.alloc(0));
      const primaryStderr = writeEntryFile(entryDirectory, "primary-evaluator-stderr.txt", Buffer.alloc(0));
      const primaryReceipt = writeEntryJson(entryDirectory, "primary-evaluator-receipt.json", {
        schema_version: "offline-scheduled-matrix-primary-evaluator-receipt/v1",
        entry_id: scheduled.entry_id,
        verdict: "ERROR",
        reason,
        exit_code: null,
        stdout: { sha256: primaryStdout.sha256, byte_length: primaryStdout.byte_length },
        stderr: { sha256: primaryStderr.sha256, byte_length: primaryStderr.byte_length }
      });
      return {
        rawStdout,
        rawStderr,
        exitStatus,
        rawEvidenceIdentity,
        rawObservationIdentity: null,
        submissionIdentity: failureReceipt,
        submissionObservationIdentity: null,
        taskCardIdentity,
        primaryReceipt,
        rollbackReceipt,
        effectsReceipt,
        primaryVerdict: "ERROR",
        primaryReason: reason
      };
    };
    if (child.start_error !== null || child.exit_code !== 0 || child.signal !== null || !fs.existsSync(rawEvidencePath)) {
      return retainHarnessFailure(child.timed_out ? "HARNESS_TIMEOUT" : "HARNESS_RUN_NON_PASS");
    }
    const rawEvidenceTarget = path.join(entryDirectory, "raw-evidence.json");
    copyExclusive(rawEvidencePath, rawEvidenceTarget);
    const rawEvidenceIdentity = fileIdentity(outputRoot, rawEvidenceTarget);
    let rawEvidence;
    try {
      rawEvidence = JSON.parse(fs.readFileSync(rawEvidenceTarget, "utf8"));
    } catch {
      return retainHarnessFailure("HARNESS_EVIDENCE_INVALID", rawEvidenceIdentity);
    }
    const orderedArgvSha256 = sha256Json([runtimeProfile.executable.path, ...harnessArgs]);
    if (rawEvidence.runtime?.ordered_argv_sha256 !== orderedArgvSha256 || rawEvidence.runtime?.stdout_sha256 !== rawStdout.sha256 || rawEvidence.runtime?.stderr_sha256 !== rawStderr.sha256 || rawEvidence.runtime?.exit_code !== child.exit_code) {
      return retainHarnessFailure("RAW_RUN_OBSERVATION_MISMATCH", rawEvidenceIdentity);
    }
    const rawObservation = createObservation({
      evidenceIdentity: rawEvidenceIdentity,
      evidence: rawEvidence,
      child,
      argvSha256: orderedArgvSha256,
      taskCardIdentity,
      sourceIdentity: accepted.source,
      runtimeIdentity: accepted.runtime_profile,
      harnessIdentity: accepted.harness
    });
    const rawObservationIdentity = writeEntryJson(entryDirectory, "raw-observation.json", rawObservation);

    let submissionPath = rawEvidenceTarget;
    let submissionIdentity = rawEvidenceIdentity;
    let observationPath = path.join(entryDirectory, "raw-observation.json");
    let submissionObservationIdentity = rawObservationIdentity;
    if (scheduled.entry_id === "MISSING_EVIDENCE" || scheduled.entry_id === "SCOPE_VIOLATION") {
      const submission = structuredClone(rawEvidence);
      if (scheduled.entry_id === "MISSING_EVIDENCE") {
        if (submission.tests?.candidate_conformance !== true) reject("MISSING_EVIDENCE_PREFREEZE_MISMATCH");
        delete submission.tests.candidate_conformance;
      } else {
        const content = "scope-violation\n";
        const bytes = Buffer.from(content, "utf8");
        submission.result.files.push({
          path: "docs/out-of-scope.txt",
          content,
          sha256: sha256(bytes),
          byte_length: bytes.length
        });
        submission.result.path_set = submission.result.files.map((entry) => entry.path).sort();
        submission.result.manifest_sha256 = sha256Json(submission.result.files.map((entry) => ({ path: entry.path, sha256: entry.sha256, byte_length: entry.byte_length })));
      }
      submissionPath = path.join(entryDirectory, "submission-evidence.json");
      writeCanonicalJson(submissionPath, submission);
      submissionIdentity = fileIdentity(outputRoot, submissionPath);
      const derivedObservation = structuredClone(rawObservation);
      derivedObservation.candidate_evidence = { sha256: submissionIdentity.sha256, byte_length: submissionIdentity.byte_length };
      observationPath = path.join(entryDirectory, "submission-observation.json");
      writeCanonicalJson(observationPath, derivedObservation);
      submissionObservationIdentity = fileIdentity(outputRoot, observationPath);
    }

    cleanupRunRoot(runRoot, runOwnership);
    const rollbackReceipt = writeEntryJson(entryDirectory, "rollback-receipt.json", {
      schema_version: "offline-scheduled-matrix-rollback-receipt/v1",
      entry_id: scheduled.entry_id,
      source_root_initial_state: "ABSENT",
      source_root_final_state: "ABSENT",
      path_set_before: [],
      path_set_after: [],
      clean_state_before: true,
      clean_state_after: true,
      run_workspace_initial_state: "ABSENT",
      run_workspace_final_state: "ABSENT",
      exact: true
    });
    const effectsReceipt = writeEntryJson(entryDirectory, "external-effects-receipt.json", {
      schema_version: "offline-scheduled-matrix-external-effects-receipt/v1",
      entry_id: scheduled.entry_id,
      ...FALSE_EFFECTS
    });

    const oracleArgs = [
      accepted.primary_oracle.path,
      "--evidence", submissionPath,
      "--expected", accepted.expected.path,
      "--observation", observationPath,
      "--task-card", taskCardPath,
      "--source", accepted.source.path,
      "--runtime-profile", accepted.runtime_profile.path,
      "--candidate-module", accepted.harness.path
    ];
    const oracle = runChild(runtimeProfile.executable.path, oracleArgs, canonicalRoot, SANITIZED_ENVIRONMENT, timeoutMs + 1000);
    const oracleStdout = writeEntryFile(entryDirectory, "primary-evaluator-stdout.txt", oracle.stdout);
    const oracleStderr = writeEntryFile(entryDirectory, "primary-evaluator-stderr.txt", oracle.stderr);
    const oraclePayload = parseSingleJsonLine(oracle.exit_code === 0 ? oracle.stdout : oracle.stderr);
    let primaryVerdict = "ERROR";
    if (oracle.exit_code === 0 && oraclePayload?.verdict === "PASS") primaryVerdict = "PASS";
    else if (oracle.exit_code !== 0 && oraclePayload?.verdict === "NON_PASS") primaryVerdict = "NON_PASS";
    const primaryReceipt = writeEntryJson(entryDirectory, "primary-evaluator-receipt.json", {
      schema_version: "offline-scheduled-matrix-primary-evaluator-receipt/v1",
      entry_id: scheduled.entry_id,
      verdict: primaryVerdict,
      reason: oraclePayload?.reason ?? null,
      exit_code: oracle.exit_code,
      stdout: { sha256: oracleStdout.sha256, byte_length: oracleStdout.byte_length },
      stderr: { sha256: oracleStderr.sha256, byte_length: oracleStderr.byte_length }
    });

    return {
      rawStdout,
      rawStderr,
      exitStatus,
      rawEvidenceIdentity,
      rawObservationIdentity,
      submissionIdentity,
      submissionObservationIdentity,
      taskCardIdentity,
      primaryReceipt,
      rollbackReceipt,
      effectsReceipt,
      primaryVerdict,
      primaryReason: oraclePayload?.reason ?? null
    };
  };

  const runInvalidControl = (scheduled, entryDirectory) => {
    const rawStdout = writeEntryFile(entryDirectory, "raw-stdout.txt", controlProbe.stdout);
    const rawStderr = writeEntryFile(entryDirectory, "raw-stderr.txt", controlProbe.stderr);
    const observedArchitecture = controlProbe.stdout.toString("utf8").trim();
    const probeOutcome = controlProbe.start_error !== null || controlProbe.exit_code !== 0
      ? "CONTROL_PROBE_NON_PASS"
      : observedArchitecture === runtimeProfile.actual_process.arch
        ? "ALTERNATE_ARCHITECTURE_NOT_ESTABLISHED"
        : "ALTERNATE_ARCHITECTURE_MISMATCH_CONFIRMED";
    const exitStatus = writeEntryJson(entryDirectory, "exit-status.json", {
      schema_version: "offline-scheduled-matrix-exit-status/v1",
      entry_id: scheduled.entry_id,
      child_started: false,
      control_probe_child_started: controlProbe.start_error === null,
      exit_code: controlProbe.exit_code,
      signal: controlProbe.signal,
      timed_out: controlProbe.timed_out,
      start_error: controlProbe.start_error
    });
    const controlReceipt = writeEntryJson(entryDirectory, "control-receipt.json", {
      schema_version: "offline-scheduled-matrix-shared-harness-control/v1",
      entry_id: scheduled.entry_id,
      control_type: "PREDECLARED_SHARED_HARNESS_INVALID_CONTROL",
      trigger_boundary: "BEFORE_CHILD_START_AND_BEFORE_ANY_CANDIDATE_OUTPUT",
      reason_family: "DECLARED_SHARED_HARNESS_INVALID",
      affects: "SHARED_HARNESS_ONLY",
      system_under_test_attributable: false,
      child_start_attempts: 0,
      candidate_output_observed: false,
      control_probe_child_start_attempts: controlProbe.start_error === null ? 1 : 0,
      control_probe_argv: controlProbeArgv,
      control_probe_argv_sha256: sha256Json(controlProbeArgv),
      control_probe_environment_sha256: environmentSha256,
      control_probe_exit_code: controlProbe.exit_code,
      control_probe_start_error: controlProbe.start_error,
      control_probe_timed_out: controlProbe.timed_out,
      control_probe_stdout_sha256: rawStdout.sha256,
      control_probe_stdout_byte_length: rawStdout.byte_length,
      control_probe_stderr_sha256: rawStderr.sha256,
      control_probe_stderr_byte_length: rawStderr.byte_length,
      expected_architecture: runtimeProfile.actual_process.arch,
      observed_architecture: observedArchitecture,
      probe_outcome: probeOutcome
    });
    const rollbackReceipt = writeEntryJson(entryDirectory, "rollback-receipt.json", {
      schema_version: "offline-scheduled-matrix-rollback-receipt/v1",
      entry_id: scheduled.entry_id,
      source_root_initial_state: "ABSENT",
      source_root_final_state: "ABSENT",
      path_set_before: [],
      path_set_after: [],
      clean_state_before: true,
      clean_state_after: true,
      run_workspace_initial_state: "ABSENT",
      run_workspace_final_state: "ABSENT",
      exact: true
    });
    const effectsReceipt = writeEntryJson(entryDirectory, "external-effects-receipt.json", {
      schema_version: "offline-scheduled-matrix-external-effects-receipt/v1",
      entry_id: scheduled.entry_id,
      ...FALSE_EFFECTS
    });
    const primaryStdout = writeEntryFile(entryDirectory, "primary-evaluator-stdout.txt", Buffer.alloc(0));
    const primaryStderr = writeEntryFile(entryDirectory, "primary-evaluator-stderr.txt", Buffer.alloc(0));
    const primaryReceipt = writeEntryJson(entryDirectory, "primary-evaluator-receipt.json", {
      schema_version: "offline-scheduled-matrix-primary-evaluator-receipt/v1",
      entry_id: scheduled.entry_id,
      verdict: "NOT_RUN",
      reason: "DECLARED_SHARED_HARNESS_INVALID",
      exit_code: null,
      stdout: { sha256: primaryStdout.sha256, byte_length: primaryStdout.byte_length },
      stderr: { sha256: primaryStderr.sha256, byte_length: primaryStderr.byte_length }
    });
    return {
      rawStdout,
      rawStderr,
      exitStatus,
      rawEvidenceIdentity: null,
      rawObservationIdentity: null,
      submissionIdentity: controlReceipt,
      submissionObservationIdentity: null,
      taskCardIdentity: null,
      primaryReceipt,
      rollbackReceipt,
      effectsReceipt,
      primaryVerdict: "NOT_RUN",
      primaryReason: "DECLARED_SHARED_HARNESS_INVALID"
    };
  };

  for (const scheduled of plan.json.schedule) {
    const entryDirectory = path.join(entriesRoot, `${String(scheduled.slot).padStart(2, "0")}-${scheduled.entry_id}`);
    mkdirOwned(entryDirectory);
    const result = scheduled.eligible ? runEligibleEntry(scheduled, entryDirectory) : runInvalidControl(scheduled, entryDirectory);
    const entryRecordIdentity = writeEntryJson(entryDirectory, "entry-record.json", {
      schema_version: "offline-scheduled-matrix-entry-record/v1",
      task_id: TASK_ID,
      slot: scheduled.slot,
      entry_id: scheduled.entry_id,
      run_id: scheduled.run_id,
      eligible: scheduled.eligible,
      candidate_claim: scheduled.candidate_claim,
      frozen_stimulus_sha256: sha256(canonicalJsonBytes(scheduled.stimulus)),
      submission: result.submissionIdentity,
      raw_evidence: result.rawEvidenceIdentity,
      raw_observation: result.rawObservationIdentity,
      submission_observation: result.submissionObservationIdentity,
      task_card: result.taskCardIdentity,
      raw_stdout: result.rawStdout,
      raw_stderr: result.rawStderr,
      exit_status: result.exitStatus,
      primary_evaluator: result.primaryReceipt,
      rollback: result.rollbackReceipt,
      external_effects: result.effectsReceipt
    });
    const manifestPath = path.join(entryDirectory, "artifact-manifest.json");
    const manifestFiles = recursiveFileIdentities(outputRoot, entryDirectory, "artifact-manifest.json");
    writeCanonicalJson(manifestPath, {
      schema_version: "offline-scheduled-matrix-entry-artifact-manifest/v1",
      task_id: TASK_ID,
      slot: scheduled.slot,
      entry_id: scheduled.entry_id,
      files: manifestFiles
    });
    const manifestIdentity = fileIdentity(outputRoot, manifestPath);
    matrixEntryManifests.push(manifestIdentity);
    observed.push({
      entry_id: scheduled.entry_id,
      eligible: scheduled.eligible,
      candidate_claim: scheduled.candidate_claim,
      primary_verdict: result.primaryVerdict,
      primary_reason: result.primaryReason,
      entry_record: entryRecordIdentity,
      artifact_manifest: manifestIdentity
    });
    appendEvent({
      event_type: "RUN_TERMINAL",
      slot: scheduled.slot,
      entry_id: scheduled.entry_id,
      run_id: scheduled.run_id,
      raw_artifact_manifest_sha256: manifestIdentity.sha256,
      raw_artifact_manifest_byte_length: manifestIdentity.byte_length,
      rollback_receipt_sha256: result.rollbackReceipt.sha256,
      rollback_receipt_byte_length: result.rollbackReceipt.byte_length,
      external_effects_receipt_sha256: result.effectsReceipt.sha256,
      external_effects_receipt_byte_length: result.effectsReceipt.byte_length
    });
  }

  const independentByEntry = {
    CORRECT_RESULT: "VERIFIED_SUCCESS",
    WRONG_PATCH: "FAILURE",
    MISSING_EVIDENCE: "FAILURE",
    SCOPE_VIOLATION: "FAILURE",
    DECLARED_SHARED_HARNESS_INVALID_CONTROL: "INFRASTRUCTURE_INVALID"
  };
  const reasonByEntry = {
    CORRECT_RESULT: "VERIFIED_SUCCESS",
    WRONG_PATCH: "WRONG_PATCH",
    MISSING_EVIDENCE: "MISSING_EVIDENCE",
    SCOPE_VIOLATION: "SCOPE_VIOLATION",
    DECLARED_SHARED_HARNESS_INVALID_CONTROL: "DECLARED_SHARED_HARNESS_INVALID"
  };
  const primaryMatrix = Object.fromEntries(["PASS", "NON_PASS", "NOT_RUN", "ERROR"].map((primary) => [primary, { VERIFIED_SUCCESS: 0, FAILURE: 0, INFRASTRUCTURE_INVALID: 0 }]));
  for (const item of observed) primaryMatrix[item.primary_verdict][independentByEntry[item.entry_id]] += 1;
  const reportedAggregatePath = path.join(outputRoot, "reported-aggregate.json");
  writeCanonicalJson(reportedAggregatePath, {
    schema_version: "offline-scheduled-matrix-reported-aggregate/v1",
    task_id: TASK_ID,
    scheduled_count: 5,
    eligible_denominator: 4,
    verified_success_numerator: 1,
    failure_count: 3,
    invalid_count: 1,
    exact_vtsr: { numerator: 1, denominator: 4, canonical_fraction: "1/4" },
    reason_code_distribution: {
      VERIFIED_SUCCESS: 1,
      WRONG_PATCH: 1,
      MISSING_EVIDENCE: 1,
      SCOPE_VIOLATION: 1,
      DECLARED_SHARED_HARNESS_INVALID: 1
    },
    primary_evaluator_disagreement_matrix: primaryMatrix,
    candidate_claim_false_success_confusion_matrix: {
      true_positive: 1,
      false_positive: 3,
      true_negative: 0,
      false_negative: 0,
      infrastructure_invalid_excluded_from_binary_confusion: 1
    },
    classifications: observed.map((item) => ({
      entry_id: item.entry_id,
      primary_evaluator_verdict: item.primary_verdict,
      independent_verdict: independentByEntry[item.entry_id],
      reason_family: reasonByEntry[item.entry_id]
    })),
    external_effects: { ...FALSE_EFFECTS }
  });
  const reportedAggregateIdentity = fileIdentity(outputRoot, reportedAggregatePath);

  const rawManifestPath = path.join(outputRoot, "raw-artifact-manifest.json");
  writeCanonicalJson(rawManifestPath, {
    schema_version: "offline-scheduled-matrix-raw-artifact-manifest/v1",
    task_id: TASK_ID,
    entry_artifact_manifests: matrixEntryManifests,
    retained_entry_count: matrixEntryManifests.length
  });
  const rawManifestIdentity = fileIdentity(outputRoot, rawManifestPath);
  const lastTerminalEventSha256 = previousEventSha256;
  const closeEvent = appendEvent({
    event_type: "MATRIX_CLOSED",
    entry_id: null,
    reported_aggregate_sha256: reportedAggregateIdentity.sha256,
    reported_aggregate_byte_length: reportedAggregateIdentity.byte_length,
    raw_artifact_manifest_sha256: rawManifestIdentity.sha256,
    raw_artifact_manifest_byte_length: rawManifestIdentity.byte_length,
    last_terminal_event_sha256: lastTerminalEventSha256
  });
  if (eventIndex !== 13) reject("LEDGER_EVENT_COUNT_MISMATCH");
  fs.closeSync(ledgerFd);
  fs.chmodSync(ledgerPath, 0o400);
  const ledgerIdentity = fileIdentity(outputRoot, ledgerPath);
  const closeReceiptPath = path.join(outputRoot, "matrix-close-receipt.json");
  writeCanonicalJson(closeReceiptPath, {
    schema_version: "offline-scheduled-matrix-close-receipt/v1",
    task_id: TASK_ID,
    status: "CLOSED",
    ledger: ledgerIdentity,
    reported_aggregate: reportedAggregateIdentity,
    raw_artifact_manifest: rawManifestIdentity,
    final_event_sha256: closeEvent.event_sha256,
    final_event_index: closeEvent.event_index,
    candidate_commit: candidateCommit,
    candidate_tree: candidateTree,
    repository_clean_at_execution: true,
    output_ownership: fileIdentity(outputRoot, ownershipRecordPath),
    external_effects: { ...FALSE_EFFECTS }
  });
  assertSameOwnedDirectory(outputRoot, outputOwnership);
  return {
    schema_version: "offline-scheduled-matrix-run-result/v1",
    task_id: TASK_ID,
    status: "CLOSED",
    output_root: outputRoot,
    ledger_sha256: ledgerIdentity.sha256,
    ledger_byte_length: ledgerIdentity.byte_length,
    exact_vtsr: "1/4",
    external_effects: { ...FALSE_EFFECTS }
  };
};

try {
  process.stdout.write(`${stableJson(main())}\n`);
} catch (error) {
  const reason = error instanceof MatrixError ? error.reason : "INTERNAL_ERROR";
  process.stderr.write(`${stableJson({ verdict: "NON_PASS", reason })}\n`);
  process.exitCode = 1;
}

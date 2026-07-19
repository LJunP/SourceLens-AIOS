#!/usr/local/bin/node

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
  rmSync,
  symlinkSync,
  writeSync,
} from "node:fs";
import { createHash, randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const CANONICAL_REPOSITORY_ROOT = "/Users/lijunpeng/Developer/SourceLens-AIOS";
const TASK_CARD_RELATIVE = "evaluation-harness/fixtures/experiment-pack-reentry-v1/task-card.json";
const TASK_CARD_PATH = join(REPOSITORY_ROOT, TASK_CARD_RELATIVE);
const TASK_CARD_IDENTITY = {
  sha256: "15cb56812e348fcca3238467db4e7cdedd9b9210ddedc1568d44b1eeb82f854f",
  byte_length: 10348,
};
const QUALITY_RECEIPT_PATH =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-048-actual-experiment-pack/quality-freeze/TASK_CARD_FREEZE_RECEIPT.json";
const AUTHORIZED_EVIDENCE_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-048-actual-experiment-pack";
const QUALITY_RECEIPT_IDENTITY = {
  sha256: "846bcbd51ec64acbc2236ed9b7f3aee821a7300f5a23b762b707e953ad2bae66",
  byte_length: 4140,
};
const TASK_ID = "AIOS-P1-048_ACTUAL_EXECUTION_EXPERIMENT_PACK";
const CONTROL_ID = "SL-P1-REP-006-DEDUPE-REFACTOR";
const RUN_ID_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const EXPECTED_CHANGED_PATHS = ["src/projects.mjs", "src/unique.mjs", "src/users.mjs"];
const REQUIRED_ACTIONS = [
  "validate_frozen_inputs",
  "materialize_distinct_disposable_repository",
  "verify_base_commit_tree_and_clean_state",
  "run_base_issue_test",
  "validate_typed_base_failure",
  "run_base_regression_test",
  "validate_reference_patch",
  "apply_reference_patch",
  "verify_exact_patch_scope",
  "run_patched_issue_test",
  "run_patched_regression_test",
  "apply_inverse_patch",
  "verify_exact_rollback",
  "emit_create_once_evidence",
];
const NEGATIVE_CONTROLS = [
  ["preexisting-evidence", "PREEXISTING_EVIDENCE", "PREEXISTING_EVIDENCE_REJECTED"],
  ["symlink-evidence", "SYMLINK_EVIDENCE", "SYMLINK_EVIDENCE_REJECTED"],
  ["hardlink-or-nlink-drift", "HARDLINK_OR_NLINK_DRIFT", "HARDLINK_OR_NLINK_DRIFT_REJECTED"],
  ["path-escape", "PATH_ESCAPE", "PATH_ESCAPE_REJECTED"],
  ["empty-or-noop-patch", "EMPTY_OR_NOOP_PATCH", "EMPTY_OR_NOOP_PATCH_REJECTED"],
  ["patch-scope-drift", "PATCH_SCOPE_DRIFT", "PATCH_SCOPE_DRIFT_REJECTED"],
  ["missing-required-action", "MISSING_REQUIRED_ACTION", "MISSING_REQUIRED_ACTION_REJECTED"],
  ["artifact-identity-tamper", "ARTIFACT_IDENTITY_TAMPER", "ARTIFACT_IDENTITY_TAMPER_REJECTED"],
];
const TRANSFORM_NAME = "EXACT_MATERIALIZATION_ROOT_AND_TAP_DURATION_MS";
const TRANSFORM_VERSION = "1";
const MATERIALIZATION_PLACEHOLDER = "<MATERIALIZATION_ROOT>";
const DURATION_PLACEHOLDER = "<DURATION_MS>";
const MAX_COMMAND_BUFFER = 16 * 1024 * 1024;
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;

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

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function modeString(mode) {
  return (mode & 0o7777).toString(8).padStart(4, "0");
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object" && !Buffer.isBuffer(value)) {
    const result = {};
    for (const key of Object.keys(value).sort()) result[key] = canonicalize(value[key]);
    return result;
  }
  return value;
}

function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
}

function parseJson(bytes, label) {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    reject("INPUT_IDENTITY_DRIFT", `${label} is not valid JSON`, { error: error.message });
  }
}

function pathIsWithin(root, candidate, allowRoot = false) {
  const rel = relative(root, candidate);
  if (rel === "") return allowRoot;
  return !rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel);
}

function containedPath(root, relativePath, reasonCode = "PATH_ESCAPE_REJECTED") {
  if (typeof relativePath !== "string" || relativePath.length === 0 || isAbsolute(relativePath)) {
    reject(reasonCode, "path is not a non-empty relative path");
  }
  const candidate = resolve(root, relativePath);
  if (!pathIsWithin(root, candidate)) reject(reasonCode, "path escapes its declared root");
  return candidate;
}

function lstatOrReject(filePath, code, label) {
  try {
    return lstatSync(filePath);
  } catch (error) {
    reject(code, `${label} is unavailable`, { path: filePath, error: error.code ?? error.message });
  }
}

function readRegularFile(filePath, {
  code = "INPUT_IDENTITY_DRIFT",
  label = "file",
  requireNlinkOne = true,
  requireCanonicalPath = true,
} = {}) {
  const absolute = resolve(filePath);
  const initialPathStat = lstatOrReject(absolute, code, label);
  if (initialPathStat.isSymbolicLink() || !initialPathStat.isFile()) {
    reject(code, `${label} must be a regular non-symlink file`, { path: absolute });
  }
  if (requireNlinkOne && initialPathStat.nlink !== 1) {
    reject(code, `${label} must have nlink one`, { path: absolute, nlink: initialPathStat.nlink });
  }
  if (requireCanonicalPath && realpathSync(absolute) !== absolute) {
    reject(code, `${label} path contains a symlink`, { path: absolute });
  }

  let descriptor;
  try {
    descriptor = openSync(absolute, fsConstants.O_RDONLY | O_NOFOLLOW);
    const before = fstatSync(descriptor);
    if (!before.isFile() || (requireNlinkOne && before.nlink !== 1)) {
      reject(code, `${label} identity changed before read`, { path: absolute });
    }
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    const finalPathStat = lstatSync(absolute);
    if (
      before.dev !== after.dev || before.ino !== after.ino || before.size !== after.size ||
      before.dev !== finalPathStat.dev || before.ino !== finalPathStat.ino ||
      (requireNlinkOne && (after.nlink !== 1 || finalPathStat.nlink !== 1))
    ) {
      reject(code, `${label} identity changed while reading`, { path: absolute });
    }
    return { bytes, stat: after, path: absolute, realpath: realpathSync(absolute) };
  } catch (error) {
    if (error instanceof ControlledError) throw error;
    reject(code, `${label} could not be read safely`, { path: absolute, error: error.code ?? error.message });
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function assertIdentity(actual, expected, code = "INPUT_IDENTITY_DRIFT", label = "file") {
  const actualIdentity = { sha256: sha256(actual.bytes), byte_length: actual.bytes.length };
  if (
    actualIdentity.sha256 !== expected.sha256 ||
    actualIdentity.byte_length !== expected.byte_length
  ) {
    reject(code, `${label} exact identity does not match`, { expected, actual: actualIdentity });
  }
  return actualIdentity;
}

function readIdentityBoundFile(filePath, expected, options = {}) {
  const actual = readRegularFile(filePath, options);
  const identity = assertIdentity(actual, expected, options.code, options.label);
  return { ...actual, identity };
}

function assertRealDirectory(directoryPath, code = "EVIDENCE_ROOT_INVALID", label = "directory") {
  if (!isAbsolute(directoryPath)) reject(code, `${label} must be absolute`);
  const absolute = resolve(directoryPath);
  const stat = lstatOrReject(absolute, code, label);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    reject(code, `${label} must be an existing real non-symlink directory`, { path: absolute });
  }
  if (realpathSync(absolute) !== absolute) {
    reject(code, `${label} path contains a symlink`, { path: absolute });
  }
  return { path: absolute, stat };
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

function validateExecutable(toolName, declaration) {
  if (!isAbsolute(declaration.path)) reject("TOOL_IDENTITY_DRIFT", `${toolName} path is not absolute`);
  const actual = readIdentityBoundFile(
    declaration.path,
    { sha256: declaration.sha256, byte_length: declaration.byte_length },
    { code: "TOOL_IDENTITY_DRIFT", label: `${toolName} executable`, requireNlinkOne: false },
  );
  if ((actual.stat.mode & 0o111) === 0) reject("TOOL_IDENTITY_DRIFT", `${toolName} is not executable`);
  if (currentUserCanWrite(actual.stat)) {
    reject("TOOL_IDENTITY_DRIFT", `${toolName} executable is writable by the current user`);
  }
  return {
    path: declaration.path,
    realpath: actual.realpath,
    sha256: actual.identity.sha256,
    byte_length: actual.identity.byte_length,
    mode: modeString(actual.stat.mode),
    version: declaration.version,
    architecture: process.arch,
    platform: process.platform,
    nlink_observed: actual.stat.nlink,
    current_user_writable: false,
  };
}

function assertExactValue(actual, expected, label) {
  if (actual !== expected) reject("INPUT_IDENTITY_DRIFT", `${label} does not match the freeze`);
}

function assertPatchNonEmpty(patchBytes) {
  if (!Buffer.isBuffer(patchBytes) || patchBytes.length === 0 || patchBytes.toString("utf8").trim() === "") {
    reject("EMPTY_OR_NOOP_PATCH_REJECTED", "reference patch is empty");
  }
  if (!patchBytes.includes(Buffer.from("diff --git "))) {
    reject("EMPTY_OR_NOOP_PATCH_REJECTED", "reference patch has no diff action");
  }
}

function assertExactChangedPaths(actualPaths) {
  const normalized = [...actualPaths].sort();
  if (JSON.stringify(normalized) !== JSON.stringify(EXPECTED_CHANGED_PATHS)) {
    reject("PATCH_SCOPE_DRIFT_REJECTED", "changed paths do not match the frozen scope", {
      expected: EXPECTED_CHANGED_PATHS,
      actual: normalized,
    });
  }
}

function assertRequiredActions(actualActions) {
  if (JSON.stringify(actualActions) !== JSON.stringify(REQUIRED_ACTIONS)) {
    reject("MISSING_REQUIRED_ACTION_REJECTED", "required action sequence is incomplete or reordered");
  }
}

function validateFrozenInputs(taskCardArgument) {
  const suppliedCardPath = resolve(process.cwd(), taskCardArgument);
  if (suppliedCardPath !== TASK_CARD_PATH) {
    reject("TASK_CARD_IDENTITY_DRIFT", "task card path is not the frozen repository path", {
      expected: TASK_CARD_PATH,
      actual: suppliedCardPath,
    });
  }
  const cardFile = readIdentityBoundFile(TASK_CARD_PATH, TASK_CARD_IDENTITY, {
    code: "TASK_CARD_IDENTITY_DRIFT",
    label: "Task Card",
  });
  const card = parseJson(cardFile.bytes, "Task Card");
  const receiptFile = readIdentityBoundFile(QUALITY_RECEIPT_PATH, QUALITY_RECEIPT_IDENTITY, {
    code: "TASK_CARD_IDENTITY_DRIFT",
    label: "external Quality freeze receipt",
  });
  const receipt = parseJson(receiptFile.bytes, "external Quality freeze receipt");

  assertExactValue(card.task_id, TASK_ID, "Task Card task_id");
  assertExactValue(card.control_id, CONTROL_ID, "Task Card control_id");
  assertExactValue(receipt.task_id, TASK_ID, "Quality receipt task_id");
  assertExactValue(receipt.control_id, CONTROL_ID, "Quality receipt control_id");
  assertExactValue(receipt.target_verdict, "PASS", "Quality receipt target verdict");
  assertExactValue(receipt.freeze_effective, true, "Quality receipt freeze state");
  assertExactValue(receipt.task_card.sha256, TASK_CARD_IDENTITY.sha256, "Quality receipt card SHA-256");
  assertExactValue(receipt.task_card.byte_length, TASK_CARD_IDENTITY.byte_length, "Quality receipt card length");
  if (JSON.stringify(card.positive_execution.required_actions_in_order) !== JSON.stringify(REQUIRED_ACTIONS)) {
    reject("TASK_CARD_IDENTITY_DRIFT", "Task Card action sequence is not the frozen sequence");
  }
  if (JSON.stringify(card.positive_execution.expected_changed_paths_sorted) !== JSON.stringify(EXPECTED_CHANGED_PATHS)) {
    reject("TASK_CARD_IDENTITY_DRIFT", "Task Card changed-path scope is not frozen");
  }
  const cardNegative = card.negative_controls.map((item) => [item.id, item.family, item.expected_reason_code]);
  if (JSON.stringify(cardNegative) !== JSON.stringify(NEGATIVE_CONTROLS)) {
    reject("TASK_CARD_IDENTITY_DRIFT", "Task Card negative controls are not the exact frozen eight");
  }

  const inputRecords = {};
  const inputDeclarations = [
    ["contract", card.identity.contract],
    ["task_spec", card.inputs.task_spec],
    ["expected_base_failure", card.inputs.expected_base_failure],
    ["reference_patch", card.inputs.reference_patch],
    ["materialization_recipe", card.inputs.materialization_recipe],
  ];
  for (const [name, declaration] of inputDeclarations) {
    const inputPath = containedPath(REPOSITORY_ROOT, declaration.path, "INPUT_IDENTITY_DRIFT");
    const file = readIdentityBoundFile(inputPath, declaration, {
      code: "INPUT_IDENTITY_DRIFT",
      label: name,
    });
    inputRecords[name] = { declaration, ...file };
  }

  const sourceRoot = containedPath(REPOSITORY_ROOT, card.inputs.source_template.root, "INPUT_IDENTITY_DRIFT");
  assertRealDirectory(sourceRoot, "INPUT_IDENTITY_DRIFT", "source template root");
  const sourceFiles = [];
  for (const declaration of card.inputs.source_template.files) {
    const sourcePath = containedPath(sourceRoot, declaration.path, "INPUT_IDENTITY_DRIFT");
    const file = readIdentityBoundFile(sourcePath, declaration, {
      code: "INPUT_IDENTITY_DRIFT",
      label: `source template ${declaration.path}`,
    });
    sourceFiles.push({ declaration, ...file });
  }

  assertPatchNonEmpty(inputRecords.reference_patch.bytes);
  const taskSpec = parseJson(inputRecords.task_spec.bytes, "task spec");
  const expectedBaseFailure = parseJson(inputRecords.expected_base_failure.bytes, "expected base failure");
  const recipe = parseJson(inputRecords.materialization_recipe.bytes, "materialization recipe");
  assertExactValue(taskSpec.task_id, CONTROL_ID, "task spec ID");
  assertExactValue(taskSpec.repository.base_commit, card.inputs.frozen_base.commit, "task spec base commit");
  assertExactValue(taskSpec.repository.tree_hash, card.inputs.frozen_base.tree, "task spec base tree");
  assertExactValue(expectedBaseFailure.expected_exit_status, 1, "expected base failure status");
  assertExactValue(recipe.hash_algorithm, "sha1", "materialization hash algorithm");

  if (realpathSync(process.execPath) !== realpathSync(card.inputs.executables.node.path)) {
    reject("TOOL_IDENTITY_DRIFT", "running Node executable is not the frozen executable");
  }
  const tools = {
    git: validateExecutable("git", card.inputs.executables.git),
    node: validateExecutable("node", card.inputs.executables.node),
  };

  const stableInputIdentities = {
    task_card: { path: TASK_CARD_RELATIVE, ...TASK_CARD_IDENTITY },
    quality_receipt: {
      receipt_id: receipt.receipt_id,
      sha256: QUALITY_RECEIPT_IDENTITY.sha256,
      byte_length: QUALITY_RECEIPT_IDENTITY.byte_length,
    },
    contract: { path: card.identity.contract.path, ...inputRecords.contract.identity },
    task_spec: { path: card.inputs.task_spec.path, ...inputRecords.task_spec.identity },
    expected_base_failure: {
      path: card.inputs.expected_base_failure.path,
      ...inputRecords.expected_base_failure.identity,
    },
    reference_patch: { path: card.inputs.reference_patch.path, ...inputRecords.reference_patch.identity },
    materialization_recipe: {
      path: card.inputs.materialization_recipe.path,
      ...inputRecords.materialization_recipe.identity,
    },
    source_template: sourceFiles.map((item) => ({ path: item.declaration.path, ...item.identity })),
    tools: {
      git: {
        path: tools.git.path,
        realpath: tools.git.realpath,
        sha256: tools.git.sha256,
        byte_length: tools.git.byte_length,
        version: tools.git.version,
        architecture: tools.git.architecture,
      },
      node: {
        path: tools.node.path,
        realpath: tools.node.realpath,
        sha256: tools.node.sha256,
        byte_length: tools.node.byte_length,
        version: tools.node.version,
        architecture: tools.node.architecture,
      },
    },
  };

  return {
    card,
    receipt,
    inputRecords,
    sourceRoot,
    sourceFiles,
    taskSpec,
    expectedBaseFailure,
    recipe,
    tools,
    stableInputIdentities,
  };
}

function classifyPreexistingPath(targetPath) {
  let stat;
  try {
    stat = lstatSync(targetPath);
  } catch {
    return "PREEXISTING_EVIDENCE_REJECTED";
  }
  if (stat.isSymbolicLink()) return "SYMLINK_EVIDENCE_REJECTED";
  if (stat.isFile() && stat.nlink !== 1) return "HARDLINK_OR_NLINK_DRIFT_REJECTED";
  return "PREEXISTING_EVIDENCE_REJECTED";
}

function createExclusiveDirectory(directoryPath, mode, defaultCode = "PREEXISTING_EVIDENCE_REJECTED") {
  try {
    mkdirSync(directoryPath, { mode });
    chmodSync(directoryPath, mode);
  } catch (error) {
    if (error.code === "EEXIST" || error.code === "ELOOP") {
      const code = classifyPreexistingPath(directoryPath);
      reject(code, "refusing to use a pre-existing Evidence path", { path: directoryPath });
    }
    reject(defaultCode, "could not create an exclusive directory", {
      path: directoryPath,
      error: error.code ?? error.message,
    });
  }
  const stat = lstatSync(directoryPath);
  if (!stat.isDirectory() || stat.isSymbolicLink() || modeString(stat.mode) !== mode.toString(8).padStart(4, "0")) {
    reject(defaultCode, "created directory identity or mode is invalid", { path: directoryPath });
  }
  return stat;
}

function pathsOverlap(left, right) {
  return left === right || pathIsWithin(left, right) || pathIsWithin(right, left);
}

function authorizeEvidenceRoot(root, selfTestRoot = undefined) {
  const overlappingSourceRoot = [REPOSITORY_ROOT, CANONICAL_REPOSITORY_ROOT]
    .find((sourceRoot) => pathsOverlap(root, sourceRoot));
  if (overlappingSourceRoot !== undefined) {
    reject("CANONICAL_SOURCE_BOUNDARY_REJECTED", "Evidence root overlaps canonical source", {
      evidence_root: root,
      source_root: overlappingSourceRoot,
    });
  }
  if (selfTestRoot === undefined) {
    if (root !== AUTHORIZED_EVIDENCE_ROOT) {
      reject("EVIDENCE_ROOT_NOT_AUTHORIZED", "run Evidence root is not the exact task-authorized audit root", {
        expected: AUTHORIZED_EVIDENCE_ROOT,
        actual: root,
      });
    }
    return;
  }
  const ownedRoot = assertRealDirectory(selfTestRoot, "SELF_TEST_ROOT_INVALID", "self-test owned root").path;
  if (root !== ownedRoot && !pathIsWithin(ownedRoot, root)) {
    reject("EVIDENCE_ROOT_NOT_AUTHORIZED", "internal Evidence root is outside the self-test owned root");
  }
}

function createRunDirectory(evidenceRoot, runId, { selfTestRoot = undefined } = {}) {
  if (!RUN_ID_PATTERN.test(runId)) reject("RUN_ID_INVALID", "run ID does not match the frozen safe pattern");
  const root = assertRealDirectory(evidenceRoot).path;
  authorizeEvidenceRoot(root, selfTestRoot);
  const runPath = containedPath(root, runId);
  if ([REPOSITORY_ROOT, CANONICAL_REPOSITORY_ROOT].some((sourceRoot) => pathsOverlap(runPath, sourceRoot))) {
    reject("CANONICAL_SOURCE_BOUNDARY_REJECTED", "run output path overlaps canonical source");
  }
  const stat = createExclusiveDirectory(runPath, 0o700);
  if (realpathSync(runPath) !== runPath) reject("SYMLINK_EVIDENCE_REJECTED", "run directory is not real");
  return { root, path: runPath, stat };
}

function writeAll(descriptor, bytes) {
  let offset = 0;
  while (offset < bytes.length) offset += writeSync(descriptor, bytes, offset, bytes.length - offset);
}

function writeCreateOnceFile(filePath, bytes, mode = 0o600) {
  if (!Buffer.isBuffer(bytes)) bytes = Buffer.from(bytes);
  let descriptor;
  try {
    descriptor = openSync(
      filePath,
      fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY | O_NOFOLLOW,
      mode,
    );
    writeAll(descriptor, bytes);
    fsyncSync(descriptor);
  } catch (error) {
    if (error instanceof ControlledError) throw error;
    if (error.code === "EEXIST" || error.code === "ELOOP") {
      const code = classifyPreexistingPath(filePath);
      reject(code, "refusing to overwrite an Evidence artifact", { path: filePath });
    }
    reject("EVIDENCE_WRITE_FAILED", "could not create Evidence artifact", {
      path: filePath,
      error: error.code ?? error.message,
    });
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  const artifact = readRegularFile(filePath, {
    code: "ARTIFACT_IDENTITY_TAMPER_REJECTED",
    label: "Evidence artifact",
  });
  const identity = { sha256: sha256(bytes), byte_length: bytes.length };
  assertIdentity(artifact, identity, "ARTIFACT_IDENTITY_TAMPER_REJECTED", "Evidence artifact");
  return {
    path: filePath,
    byte_length: identity.byte_length,
    sha256: identity.sha256,
    mode: modeString(artifact.stat.mode),
    nlink: artifact.stat.nlink,
    inode: artifact.stat.ino,
  };
}

function artifactReference(artifact, runDirectory) {
  return {
    path: relative(runDirectory, artifact.path),
    physical_path: artifact.path,
    byte_length: artifact.byte_length,
    sha256: artifact.sha256,
  };
}

function deterministicEnvironment(validation, disposableHome) {
  return {
    PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
    HOME: disposableHome,
    LC_ALL: "C",
    LANG: "C",
    TZ: "UTC",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_TERMINAL_PROMPT: "0",
    GIT_AUTHOR_NAME: validation.recipe.git_author_name,
    GIT_AUTHOR_EMAIL: validation.recipe.git_author_email,
    GIT_AUTHOR_DATE: validation.recipe.git_author_date,
    GIT_COMMITTER_NAME: validation.recipe.git_committer_name,
    GIT_COMMITTER_EMAIL: validation.recipe.git_committer_email,
    GIT_COMMITTER_DATE: validation.recipe.git_committer_date,
  };
}

function completeAction(context, actionId) {
  const expected = REQUIRED_ACTIONS[context.completedActions.length];
  if (actionId !== expected) {
    reject("MISSING_REQUIRED_ACTION_REJECTED", "action completed out of frozen order", {
      expected,
      actual: actionId,
    });
  }
  context.completedActions.push(actionId);
}

function commandFileStem(index, actionId) {
  return `${String(index).padStart(3, "0")}-${actionId.replace(/[^a-z0-9_-]+/gi, "-")}`;
}

function runCommand(context, actionId, executable, args, cwd, input = undefined) {
  const commandIndex = context.commands.length;
  const startedAt = new Date().toISOString();
  const start = process.hrtime.bigint();
  const outcome = spawnSync(executable, args, {
    cwd,
    env: context.environment,
    input,
    encoding: null,
    timeout: 10_000,
    maxBuffer: MAX_COMMAND_BUFFER,
    windowsHide: true,
  });
  const durationMs = Number(process.hrtime.bigint() - start) / 1_000_000;
  const finishedAt = new Date().toISOString();
  const stdout = Buffer.isBuffer(outcome.stdout) ? outcome.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(outcome.stderr) ? outcome.stderr : Buffer.alloc(0);
  const stem = commandFileStem(commandIndex, actionId);
  const stdoutArtifact = writeCreateOnceFile(join(context.commandsDirectory, `${stem}.stdout.bin`), stdout);
  const stderrArtifact = writeCreateOnceFile(join(context.commandsDirectory, `${stem}.stderr.bin`), stderr);
  const record = {
    action_id: actionId,
    argv: [executable, ...args],
    cwd,
    exit_status: outcome.status,
    signal: outcome.signal,
    duration_ms: durationMs,
    started_at_utc: startedAt,
    finished_at_utc: finishedAt,
    stdout: artifactReference(stdoutArtifact, context.runDirectory),
    stderr: artifactReference(stderrArtifact, context.runDirectory),
  };
  context.commands.push(record);
  context.streams.push({ record, stdout, stderr });
  context.artifacts.push(stdoutArtifact, stderrArtifact);
  if (outcome.error) {
    reject("COMMAND_SPAWN_FAILED", "command could not be executed", {
      argv: record.argv,
      error: outcome.error.code ?? outcome.error.message,
    });
  }
  return record;
}

function expectStatus(record, expected, code, label) {
  if (record.exit_status !== expected || record.signal !== null) {
    reject(code, `${label} returned an unexpected status`, {
      expected,
      actual: record.exit_status,
      signal: record.signal,
    });
  }
}

function trimCommandOutput(context, record) {
  const stream = context.streams.find((item) => item.record === record);
  return stream.stdout.toString("utf8").trim();
}

function parseStatusPaths(bytes) {
  const fields = bytes.toString("utf8").split("\0").filter(Boolean);
  const paths = [];
  for (let index = 0; index < fields.length; index += 1) {
    const entry = fields[index];
    if (entry.length < 4 || entry[2] !== " ") reject("PATCH_SCOPE_DRIFT_REJECTED", "unexpected git status format");
    const status = entry.slice(0, 2);
    paths.push(entry.slice(3));
    if (status.includes("R") || status.includes("C")) index += 1;
  }
  return paths.sort();
}

function encodedPathVariants(filePath) {
  const encodedComponent = encodeURIComponent(filePath);
  return [
    filePath,
    encodeURI(filePath),
    encodedComponent,
    encodedComponent.replaceAll("%2F", "%2f"),
    pathToFileURL(filePath).href,
  ];
}

function semanticTransform(rawBytes, context) {
  const { materializationRoot, runDirectory, evidenceRoot, runId } = context;
  const originalText = rawBytes.toString("utf8");
  if (!Buffer.from(originalText, "utf8").equals(rawBytes)) {
    reject("SEMANTIC_TRANSFORM_REJECTED", "command stream is not exact UTF-8");
  }
  let rootReplacementCount = 0;
  let transformedText = originalText.replaceAll(materializationRoot, () => {
    rootReplacementCount += 1;
    return MATERIALIZATION_PLACEHOLDER;
  });
  let tapDurationNormalizationCount = 0;
  transformedText = transformedText.replace(
    /^([ \t]*(?:#[ \t]+)?duration_ms(?:[ \t]*:[ \t]*|[ \t]+))[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?([ \t]*\r?)$/gm,
    (_match, prefix, suffix) => {
      tapDurationNormalizationCount += 1;
      return `${prefix}${DURATION_PLACEHOLDER}${suffix}`;
    },
  );
  const physicalVariants = new Set([
    ...encodedPathVariants(materializationRoot),
    ...encodedPathVariants(runDirectory),
    ...encodedPathVariants(evidenceRoot),
    runId,
  ]);
  for (const variant of physicalVariants) {
    if (variant && transformedText.includes(variant)) {
      reject("SEMANTIC_TRANSFORM_RESIDUAL_PHYSICAL_VALUE", "semantic stream retains a run-specific physical value", {
        variant_kind: variant === runId ? "RUN_ID" : "PATH_VARIANT",
      });
    }
  }
  for (const line of transformedText.split("\n")) {
    if (
      /^[ \t]*(?:#[ \t]+)?duration_ms\b/.test(line) &&
      !/^[ \t]*(?:#[ \t]+)?duration_ms(?:[ \t]*:[ \t]*|[ \t]+)<DURATION_MS>[ \t]*\r?$/.test(line)
    ) {
      reject("SEMANTIC_TRANSFORM_UNRECOGNIZED_TAP_DURATION", "unrecognized TAP duration_ms line remains");
    }
  }
  const bytes = Buffer.from(transformedText, "utf8");
  return {
    bytes,
    rootReplacementCount,
    tapDurationNormalizationCount,
    residualPhysicalVariantCount: 0,
    unrecognizedTapDurationLineCount: 0,
  };
}

function buildStableProjection(context, validation, facts) {
  const commandSemantics = [];
  let totalRootReplacements = 0;
  let totalDurationNormalizations = 0;
  for (const item of context.streams) {
    const stdout = semanticTransform(item.stdout, context);
    const stderr = semanticTransform(item.stderr, context);
    totalRootReplacements += stdout.rootReplacementCount + stderr.rootReplacementCount;
    totalDurationNormalizations +=
      stdout.tapDurationNormalizationCount + stderr.tapDurationNormalizationCount;
    commandSemantics.push({
      action_id: item.record.action_id,
      stdout: {
        byte_length: stdout.bytes.length,
        sha256: sha256(stdout.bytes),
        materialization_root_replacements: stdout.rootReplacementCount,
        tap_duration_ms_normalizations: stdout.tapDurationNormalizationCount,
        residual_physical_variants: stdout.residualPhysicalVariantCount,
        unrecognized_tap_duration_ms_lines: stdout.unrecognizedTapDurationLineCount,
      },
      stderr: {
        byte_length: stderr.bytes.length,
        sha256: sha256(stderr.bytes),
        materialization_root_replacements: stderr.rootReplacementCount,
        tap_duration_ms_normalizations: stderr.tapDurationNormalizationCount,
        residual_physical_variants: stderr.residualPhysicalVariantCount,
        unrecognized_tap_duration_ms_lines: stderr.unrecognizedTapDurationLineCount,
      },
    });
  }
  return {
    schema_version: 1,
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    input_identities: validation.stableInputIdentities,
    base_commit: facts.baseCommit,
    base_tree: facts.baseTree,
    ordered_action_ids: context.completedActions,
    command_argv: context.commands.map((record) => record.argv),
    command_exit_status: context.commands.map((record) => record.exit_status),
    command_signal: context.commands.map((record) => record.signal),
    stdout_byte_length: commandSemantics.map((item) => item.stdout.byte_length),
    stdout_sha256: commandSemantics.map((item) => item.stdout.sha256),
    stderr_byte_length: commandSemantics.map((item) => item.stderr.byte_length),
    stderr_sha256: commandSemantics.map((item) => item.stderr.sha256),
    semantic_stream_transform: {
      name: TRANSFORM_NAME,
      version: TRANSFORM_VERSION,
      exact_root_replacement: {
        source: "VERIFIED_DISPOSABLE_MATERIALIZATION_ROOT",
        replacement: MATERIALIZATION_PLACEHOLDER,
        count: totalRootReplacements,
      },
      tap_duration_ms_numeric_normalization: {
        scope: "TAP_DURATION_MS_LINE_NUMERIC_VALUE_ONLY",
        replacement: DURATION_PLACEHOLDER,
        count: totalDurationNormalizations,
      },
      per_command_stream_counts: commandSemantics,
      residual_physical_variant_count: 0,
      unrecognized_tap_duration_ms_line_count: 0,
      raw_streams_modified: false,
    },
    typed_base_failure_status: "PASS",
    changed_paths_sorted: facts.changedPaths,
    patched_test_statuses: {
      issue: facts.patchedIssue.exit_status,
      regression: facts.patchedRegression.exit_status,
    },
    rollback_status: "PASS",
    rollback_tree: facts.rollbackTree,
    negative_control_reason_codes: NEGATIVE_CONTROLS.map((item) => item[2]),
    verdict: "PASS",
  };
}

function verifySourceBytes(validation, materializationRoot, code) {
  for (const source of validation.sourceFiles) {
    const destination = containedPath(materializationRoot, source.declaration.path, code);
    readIdentityBoundFile(destination, source.declaration, {
      code,
      label: `materialized ${source.declaration.path}`,
    });
  }
}

function performRun({ taskCard, evidenceRoot, runId }, { selfTestRoot = undefined } = {}) {
  const validation = validateFrozenInputs(taskCard);
  const run = createRunDirectory(evidenceRoot, runId, { selfTestRoot });
  const commandsDirectory = join(run.path, "commands");
  createExclusiveDirectory(commandsDirectory, 0o700);
  const materializationRoot = join(run.path, "materialization");
  createExclusiveDirectory(materializationRoot, 0o700);
  const disposableHome = join(run.path, "home");
  createExclusiveDirectory(disposableHome, 0o700);
  if (!pathIsWithin(run.path, realpathSync(materializationRoot))) {
    reject("PATH_ESCAPE_REJECTED", "materialization escaped the run directory");
  }
  const materializationStat = lstatSync(materializationRoot);
  const context = {
    runDirectory: run.path,
    evidenceRoot: run.root,
    runId,
    commandsDirectory,
    materializationRoot,
    environment: deterministicEnvironment(validation, disposableHome),
    commands: [],
    streams: [],
    artifacts: [],
    completedActions: [],
  };
  const startedAt = new Date().toISOString();

  const gitVersion = runCommand(
    context,
    "validate_frozen_inputs",
    validation.card.inputs.executables.git.path,
    ["--version"],
    REPOSITORY_ROOT,
  );
  expectStatus(gitVersion, 0, "TOOL_IDENTITY_DRIFT", "git version probe");
  assertExactValue(trimCommandOutput(context, gitVersion), validation.card.inputs.executables.git.version, "git version");
  const nodeVersion = runCommand(
    context,
    "validate_frozen_inputs",
    validation.card.inputs.executables.node.path,
    ["--version"],
    REPOSITORY_ROOT,
  );
  expectStatus(nodeVersion, 0, "TOOL_IDENTITY_DRIFT", "node version probe");
  assertExactValue(trimCommandOutput(context, nodeVersion), validation.card.inputs.executables.node.version, "node version");
  completeAction(context, "validate_frozen_inputs");

  for (const source of validation.sourceFiles) {
    const destination = containedPath(materializationRoot, source.declaration.path, "PATH_ESCAPE_REJECTED");
    const parent = dirname(destination);
    if (parent !== materializationRoot) {
      try {
        mkdirSync(parent, { mode: 0o700 });
        chmodSync(parent, 0o700);
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
      }
      const parentStat = lstatSync(parent);
      if (!parentStat.isDirectory() || parentStat.isSymbolicLink() || !pathIsWithin(materializationRoot, realpathSync(parent))) {
        reject("PATH_ESCAPE_REJECTED", "source destination parent is unsafe");
      }
    }
    writeCreateOnceFile(destination, source.bytes, 0o644);
  }
  verifySourceBytes(validation, materializationRoot, "INPUT_IDENTITY_DRIFT");

  const git = validation.card.inputs.executables.git.path;
  const node = validation.card.inputs.executables.node.path;
  const init = runCommand(
    context,
    "materialize_distinct_disposable_repository",
    git,
    ["init", "--quiet", "--template=", "--object-format=sha1"],
    materializationRoot,
  );
  expectStatus(init, 0, "MATERIALIZATION_FAILED", "git init");
  const add = runCommand(context, "materialize_distinct_disposable_repository", git, ["add", "--all"], materializationRoot);
  expectStatus(add, 0, "MATERIALIZATION_FAILED", "git add");
  const commit = runCommand(
    context,
    "materialize_distinct_disposable_repository",
    git,
    ["-c", "commit.gpgsign=false", "commit", "--quiet", "--no-verify", "--no-gpg-sign", "-m", validation.recipe.commit_message],
    materializationRoot,
  );
  expectStatus(commit, 0, "MATERIALIZATION_FAILED", "git commit");
  completeAction(context, "materialize_distinct_disposable_repository");

  const baseCommitRecord = runCommand(context, "verify_base_commit_tree_and_clean_state", git, ["rev-parse", "HEAD"], materializationRoot);
  expectStatus(baseCommitRecord, 0, "BASE_IDENTITY_MISMATCH", "base commit query");
  const baseTreeRecord = runCommand(context, "verify_base_commit_tree_and_clean_state", git, ["rev-parse", "HEAD^{tree}"], materializationRoot);
  expectStatus(baseTreeRecord, 0, "BASE_IDENTITY_MISMATCH", "base tree query");
  const cleanRecord = runCommand(context, "verify_base_commit_tree_and_clean_state", git, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materializationRoot);
  expectStatus(cleanRecord, 0, "BASE_IDENTITY_MISMATCH", "base status query");
  const baseCommit = trimCommandOutput(context, baseCommitRecord);
  const baseTree = trimCommandOutput(context, baseTreeRecord);
  assertExactValue(baseCommit, validation.card.inputs.frozen_base.commit, "materialized base commit");
  assertExactValue(baseTree, validation.card.inputs.frozen_base.tree, "materialized base tree");
  if (context.streams.find((item) => item.record === cleanRecord).stdout.length !== 0) {
    reject("BASE_IDENTITY_MISMATCH", "materialized base is dirty");
  }
  completeAction(context, "verify_base_commit_tree_and_clean_state");

  const baseIssue = runCommand(context, "run_base_issue_test", node, ["--test", "test/issue.test.mjs"], materializationRoot);
  expectStatus(baseIssue, validation.expectedBaseFailure.expected_exit_status, "BASE_FAILURE_MISMATCH", "base issue test");
  completeAction(context, "run_base_issue_test");
  const baseIssueStream = context.streams.find((item) => item.record === baseIssue);
  const combinedBaseOutput = Buffer.concat([baseIssueStream.stdout, baseIssueStream.stderr]).toString("utf8");
  for (const token of validation.expectedBaseFailure.required_output_tokens) {
    if (!combinedBaseOutput.includes(token)) reject("BASE_FAILURE_MISMATCH", `base failure is missing token ${token}`);
  }
  for (const token of validation.expectedBaseFailure.forbidden_output_tokens) {
    if (combinedBaseOutput.includes(token)) reject("BASE_FAILURE_MISMATCH", `base failure contains forbidden token ${token}`);
  }
  completeAction(context, "validate_typed_base_failure");

  const baseRegression = runCommand(context, "run_base_regression_test", node, ["--test", "test/regression.test.mjs"], materializationRoot);
  expectStatus(baseRegression, 0, "BASE_REGRESSION_FAILED", "base regression test");
  completeAction(context, "run_base_regression_test");

  assertPatchNonEmpty(validation.inputRecords.reference_patch.bytes);
  const patchCheck = runCommand(
    context,
    "validate_reference_patch",
    git,
    ["apply", "--check", "--whitespace=nowarn", "-"],
    materializationRoot,
    validation.inputRecords.reference_patch.bytes,
  );
  expectStatus(patchCheck, 0, "EMPTY_OR_NOOP_PATCH_REJECTED", "reference patch check");
  completeAction(context, "validate_reference_patch");
  const patchApply = runCommand(
    context,
    "apply_reference_patch",
    git,
    ["apply", "--whitespace=nowarn", "-"],
    materializationRoot,
    validation.inputRecords.reference_patch.bytes,
  );
  expectStatus(patchApply, 0, "PATCH_APPLY_FAILED", "reference patch apply");
  completeAction(context, "apply_reference_patch");

  const changedRecord = runCommand(context, "verify_exact_patch_scope", git, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materializationRoot);
  expectStatus(changedRecord, 0, "PATCH_SCOPE_DRIFT_REJECTED", "patched status query");
  const changedStream = context.streams.find((item) => item.record === changedRecord);
  const changedPaths = parseStatusPaths(changedStream.stdout);
  assertExactChangedPaths(changedPaths);
  completeAction(context, "verify_exact_patch_scope");

  const patchedIssue = runCommand(context, "run_patched_issue_test", node, ["--test", "test/issue.test.mjs"], materializationRoot);
  expectStatus(patchedIssue, 0, "PATCHED_ISSUE_TEST_FAILED", "patched issue test");
  completeAction(context, "run_patched_issue_test");
  const patchedRegression = runCommand(context, "run_patched_regression_test", node, ["--test", "test/regression.test.mjs"], materializationRoot);
  expectStatus(patchedRegression, 0, "PATCHED_REGRESSION_TEST_FAILED", "patched regression test");
  completeAction(context, "run_patched_regression_test");

  const inverse = runCommand(
    context,
    "apply_inverse_patch",
    git,
    ["apply", "--reverse", "--whitespace=nowarn", "-"],
    materializationRoot,
    validation.inputRecords.reference_patch.bytes,
  );
  expectStatus(inverse, 0, "ROLLBACK_FAILED", "inverse patch apply");
  completeAction(context, "apply_inverse_patch");
  verifySourceBytes(validation, materializationRoot, "ROLLBACK_FAILED");
  const uniquePath = containedPath(materializationRoot, "src/unique.mjs", "ROLLBACK_FAILED");
  try {
    lstatSync(uniquePath);
    reject("ROLLBACK_FAILED", "inverse patch did not remove src/unique.mjs");
  } catch (error) {
    if (error instanceof ControlledError) throw error;
    if (error.code !== "ENOENT") throw error;
  }
  const rollbackCommitRecord = runCommand(context, "verify_exact_rollback", git, ["rev-parse", "HEAD"], materializationRoot);
  expectStatus(rollbackCommitRecord, 0, "ROLLBACK_FAILED", "rollback commit query");
  const rollbackTreeRecord = runCommand(context, "verify_exact_rollback", git, ["rev-parse", "HEAD^{tree}"], materializationRoot);
  expectStatus(rollbackTreeRecord, 0, "ROLLBACK_FAILED", "rollback tree query");
  const rollbackStatusRecord = runCommand(context, "verify_exact_rollback", git, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materializationRoot);
  expectStatus(rollbackStatusRecord, 0, "ROLLBACK_FAILED", "rollback status query");
  const rollbackCommit = trimCommandOutput(context, rollbackCommitRecord);
  const rollbackTree = trimCommandOutput(context, rollbackTreeRecord);
  assertExactValue(rollbackCommit, validation.card.inputs.frozen_base.commit, "rollback commit");
  assertExactValue(rollbackTree, validation.card.inputs.frozen_base.tree, "rollback tree");
  if (context.streams.find((item) => item.record === rollbackStatusRecord).stdout.length !== 0) {
    reject("ROLLBACK_FAILED", "rollback did not restore a clean worktree");
  }
  completeAction(context, "verify_exact_rollback");

  completeAction(context, "emit_create_once_evidence");
  assertRequiredActions(context.completedActions);
  const facts = { baseCommit, baseTree, changedPaths, patchedIssue, patchedRegression, rollbackTree };
  const stableProjection = buildStableProjection(context, validation, facts);
  const stableBytes = canonicalJsonBytes(stableProjection);
  const stableArtifact = writeCreateOnceFile(join(run.path, "stable-projection.json"), stableBytes);
  context.artifacts.push(stableArtifact);
  const finishedAt = new Date().toISOString();
  const result = {
    schema_version: 1,
    record_type: "sourcelens_aios_experiment_pack_run_result",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    verdict: "PASS",
    physical_path: run.path,
    inode: run.stat.ino,
    pid: process.pid,
    started_at_utc: startedAt,
    finished_at_utc: finishedAt,
    evidence_root: {
      physical_path: run.root,
      realpath: realpathSync(run.root),
      inode: lstatSync(run.root).ino,
    },
    materialization: {
      physical_path: materializationRoot,
      realpath: realpathSync(materializationRoot),
      inode: materializationStat.ino,
      mode: modeString(materializationStat.mode),
      base_commit: baseCommit,
      base_tree: baseTree,
    },
    input_identities: validation.stableInputIdentities,
    tool_identities: validation.tools,
    ordered_action_ids: context.completedActions,
    commands: context.commands,
    typed_base_failure: {
      status: "PASS",
      assertion_id: validation.expectedBaseFailure.assertion_id,
      required_output_tokens: validation.expectedBaseFailure.required_output_tokens,
      forbidden_output_tokens: validation.expectedBaseFailure.forbidden_output_tokens,
    },
    changed_paths_sorted: changedPaths,
    patched_test_statuses: { issue: patchedIssue.exit_status, regression: patchedRegression.exit_status },
    rollback: {
      status: "PASS",
      head_commit: rollbackCommit,
      tree: rollbackTree,
      git_status_porcelain: "",
      src_unique_exists: false,
      original_source_bytes_restored: true,
    },
    stable_projection: artifactReference(stableArtifact, run.path),
  };
  const resultArtifact = writeCreateOnceFile(join(run.path, "result.json"), canonicalJsonBytes(result));
  context.artifacts.push(resultArtifact);
  const manifest = {
    schema_version: 1,
    record_type: "sourcelens_aios_experiment_pack_manifest",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    verdict: "PASS",
    input_identities: validation.stableInputIdentities,
    artifacts: context.artifacts
      .map((artifact) => artifactReference(artifact, run.path))
      .sort((left, right) => left.path.localeCompare(right.path, "en")),
  };
  const manifestArtifact = writeCreateOnceFile(join(run.path, "manifest.json"), canonicalJsonBytes(manifest));
  context.artifacts.push(manifestArtifact);
  for (const artifact of context.artifacts) {
    readIdentityBoundFile(artifact.path, artifact, {
      code: "ARTIFACT_IDENTITY_TAMPER_REJECTED",
      label: `final Evidence artifact ${relative(run.path, artifact.path)}`,
    });
  }
  return {
    run_id: runId,
    output_directory: run.path,
    stable_projection: stableArtifact.path,
    stable_projection_sha256: stableArtifact.sha256,
    stable_projection_byte_length: stableArtifact.byte_length,
    manifest: manifestArtifact.path,
    result: resultArtifact.path,
    verdict: "PASS",
  };
}

function writeOwnedFixture(filePath, bytes) {
  return writeCreateOnceFile(filePath, Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes), 0o600);
}

function verifySelfTestOwnership(rootPath, rootIdentity, markerPath, markerBytes) {
  const rootStat = lstatSync(rootPath);
  if (
    !rootStat.isDirectory() || rootStat.isSymbolicLink() || realpathSync(rootPath) !== rootPath ||
    rootStat.dev !== rootIdentity.dev || rootStat.ino !== rootIdentity.ino
  ) {
    reject("SELF_TEST_CLEANUP_REFUSED", "self-test root ownership changed; cleanup refused");
  }
  const marker = readRegularFile(markerPath, {
    code: "SELF_TEST_CLEANUP_REFUSED",
    label: "self-test ownership marker",
  });
  if (!marker.bytes.equals(markerBytes)) {
    reject("SELF_TEST_CLEANUP_REFUSED", "self-test ownership marker changed; cleanup refused");
  }
}

function runNegativeCase(results, caseRoot, specification, exercise) {
  const [id, family, expectedReasonCode] = specification;
  const fixturePath = join(caseRoot, `negative-${String(results.length + 1).padStart(2, "0")}-${id}`);
  createExclusiveDirectory(fixturePath, 0o700);
  const markerBytes = Buffer.from(`${id}:${randomBytes(16).toString("hex")}\n`, "utf8");
  writeOwnedFixture(join(fixturePath, ".owned-fixture"), markerBytes);
  let observedReasonCode = null;
  try {
    exercise(fixturePath);
  } catch (error) {
    if (error instanceof ControlledError) observedReasonCode = error.code;
    else throw error;
  }
  const accepted = observedReasonCode === null;
  if (accepted || observedReasonCode !== expectedReasonCode) {
    reject("SELF_TEST_NEGATIVE_CONTROL_FAILED", `negative control ${id} did not reject exactly`, {
      id,
      family,
      expected_reason_code: expectedReasonCode,
      observed_reason_code: observedReasonCode,
      false_accept: accepted,
    });
  }
  results.push({
    id,
    family,
    expected_reason_code: expectedReasonCode,
    observed_reason_code: observedReasonCode,
    fixture: relative(caseRoot, fixturePath),
    false_accept: false,
    verdict: "REJECTED_AS_EXPECTED",
  });
}

function performSelfTest(taskCard) {
  validateFrozenInputs(taskCard);
  const selfTestRoot = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-048-self-test-"));
  chmodSync(selfTestRoot, 0o700);
  const rootIdentity = lstatSync(selfTestRoot);
  const markerPath = join(selfTestRoot, ".self-test-owned");
  const markerBytes = Buffer.from(`AIOS-P1-048:${randomBytes(24).toString("hex")}\n`, "utf8");
  writeOwnedFixture(markerPath, markerBytes);
  const negativeResults = [];
  let outcome;
  let pendingError;
  try {
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[0], (fixture) => {
      const root = join(fixture, "evidence-root");
      createExclusiveDirectory(root, 0o700);
      createExclusiveDirectory(join(root, "already-there"), 0o700);
      createRunDirectory(root, "already-there", { selfTestRoot });
    });
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[1], (fixture) => {
      const root = join(fixture, "evidence-root");
      const target = join(fixture, "owned-symlink-target");
      createExclusiveDirectory(root, 0o700);
      createExclusiveDirectory(target, 0o700);
      symlinkSync(target, join(root, "symlink-run"));
      createRunDirectory(root, "symlink-run", { selfTestRoot });
    });
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[2], (fixture) => {
      const first = join(fixture, "artifact.bin");
      const second = join(fixture, "artifact-link.bin");
      writeOwnedFixture(first, "owned hardlink fixture\n");
      linkSync(first, second);
      readRegularFile(first, {
        code: "HARDLINK_OR_NLINK_DRIFT_REJECTED",
        label: "hardlink fixture",
      });
    });
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[3], (fixture) => {
      containedPath(fixture, "../escaped", "PATH_ESCAPE_REJECTED");
    });
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[4], () => {
      assertPatchNonEmpty(Buffer.alloc(0));
    });
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[5], () => {
      assertExactChangedPaths([...EXPECTED_CHANGED_PATHS, "test/issue.test.mjs"]);
    });
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[6], () => {
      assertRequiredActions(REQUIRED_ACTIONS.slice(0, -1));
    });
    runNegativeCase(negativeResults, selfTestRoot, NEGATIVE_CONTROLS[7], (fixture) => {
      const filePath = join(fixture, "tampered.bin");
      writeOwnedFixture(filePath, "tampered bytes\n");
      const file = readRegularFile(filePath, {
        code: "ARTIFACT_IDENTITY_TAMPER_REJECTED",
        label: "tampered fixture",
      });
      assertIdentity(
        file,
        { sha256: sha256(Buffer.from("original bytes\n")), byte_length: Buffer.byteLength("original bytes\n") },
        "ARTIFACT_IDENTITY_TAMPER_REJECTED",
        "tampered fixture",
      );
    });

    if (negativeResults.length !== 8 || negativeResults.some((item) => item.false_accept)) {
      reject("SELF_TEST_NEGATIVE_CONTROL_FAILED", "negative-control schedule was not exactly eight with zero false accepts");
    }
    const positiveRoot = join(selfTestRoot, "positive-evidence");
    createExclusiveDirectory(positiveRoot, 0o700);
    const runA = performRun(
      { taskCard, evidenceRoot: positiveRoot, runId: "self-test-run-a" },
      { selfTestRoot },
    );
    const runB = performRun(
      { taskCard, evidenceRoot: positiveRoot, runId: "self-test-run-b" },
      { selfTestRoot },
    );
    const stableA = readRegularFile(runA.stable_projection, {
      code: "SELF_TEST_POSITIVE_REPLAY_FAILED",
      label: "self-test Run A stable projection",
    }).bytes;
    const stableB = readRegularFile(runB.stable_projection, {
      code: "SELF_TEST_POSITIVE_REPLAY_FAILED",
      label: "self-test Run B stable projection",
    }).bytes;
    if (!stableA.equals(stableB)) {
      reject("SELF_TEST_POSITIVE_REPLAY_FAILED", "fresh Run A and Run B stable projections differ", {
        run_a_sha256: sha256(stableA),
        run_b_sha256: sha256(stableB),
      });
    }
    outcome = {
      schema_version: 1,
      record_type: "sourcelens_aios_experiment_pack_self_test",
      task_id: TASK_ID,
      control_id: CONTROL_ID,
      negative_controls_scheduled: 8,
      negative_controls_rejected: 8,
      false_accepts: 0,
      negative_controls: negativeResults.map(({ fixture: _fixture, ...item }) => item),
      positive_replays: 2,
      distinct_run_ids: true,
      stable_projection_exact_canonical_json_byte_equality: true,
      stable_projection_sha256: sha256(stableA),
      verdict: "PASS",
    };
  } catch (error) {
    pendingError = error;
  }
  try {
    verifySelfTestOwnership(selfTestRoot, rootIdentity, markerPath, markerBytes);
    rmSync(selfTestRoot, { recursive: true, force: false });
  } catch (cleanupError) {
    if (!pendingError) pendingError = cleanupError;
  }
  if (pendingError) throw pendingError;
  return outcome;
}

function parseArguments(argv) {
  if (argv.length === 0) reject("CLI_INVALID", "missing mode");
  const mode = argv[0];
  if (mode !== "run" && mode !== "self-test") reject("CLI_INVALID", "mode must be run or self-test");
  const values = {};
  for (let index = 1; index < argv.length; index += 2) {
    const option = argv[index];
    const value = argv[index + 1];
    if (!option?.startsWith("--") || value === undefined || value.startsWith("--")) {
      reject("CLI_INVALID", "options must be --name value pairs");
    }
    if (Object.hasOwn(values, option)) reject("CLI_INVALID", `duplicate option ${option}`);
    values[option] = value;
  }
  const allowed = mode === "run"
    ? ["--task-card", "--evidence-root", "--run-id"]
    : ["--task-card"];
  for (const option of Object.keys(values)) {
    if (!allowed.includes(option)) reject("CLI_INVALID", `unexpected option ${option}`);
  }
  for (const option of allowed) {
    if (!Object.hasOwn(values, option)) reject("CLI_INVALID", `missing option ${option}`);
  }
  return {
    mode,
    taskCard: values["--task-card"],
    evidenceRoot: values["--evidence-root"],
    runId: values["--run-id"],
  };
}

function publicError(error) {
  if (error instanceof ControlledError) {
    return {
      schema_version: 1,
      verdict: "NON_PASS",
      reason_code: error.code,
      message: error.message,
      details: error.details,
    };
  }
  return {
    schema_version: 1,
    verdict: "NON_PASS",
    reason_code: "INTERNAL_ERROR",
    message: error instanceof Error ? error.message : String(error),
  };
}

try {
  const args = parseArguments(process.argv.slice(2));
  const output = args.mode === "run" ? performRun(args) : performSelfTest(args.taskCard);
  process.stdout.write(canonicalJsonBytes(output));
} catch (error) {
  process.stderr.write(canonicalJsonBytes(publicError(error)));
  process.exitCode = 2;
}

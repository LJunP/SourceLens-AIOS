#!/usr/local/bin/node

import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
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
  symlinkSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ADAPTER_VERSION,
  OfflineB0AdapterError,
  admitOfflineB0Result,
} from "../../adapters/offline-b0-finite-typed-v1/adapter.mjs";
import { validate as validateSchema } from "../../evaluator/schema-validator.mjs";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(MODULE_DIR, "../../..");
const FIXTURE_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/fixtures/offline-b0-complete-evidence-v1");
const TASK_CARD_PATH = join(FIXTURE_ROOT, "task-card.json");
const RUNNER_RELATIVE_PATH = "evaluation-harness/harness/offline-b0-complete-evidence-v1/run.mjs";
const ADAPTER_RELATIVE_PATH = "evaluation-harness/adapters/offline-b0-finite-typed-v1/adapter.mjs";
const QUALITY_ORACLE_RELATIVE_PATH = "evaluation-harness/evaluator/offline-b0-complete-evidence-v1/quality-oracle.mjs";
const TASK_CARD_RELATIVE_PATH = "evaluation-harness/fixtures/offline-b0-complete-evidence-v1/task-card.json";
const EXECUTING_MODULE_PATHS = Object.freeze({
  adapter: ADAPTER_RELATIVE_PATH,
  quality_oracle: QUALITY_ORACLE_RELATIVE_PATH,
  runner: RUNNER_RELATIVE_PATH,
  task_card: TASK_CARD_RELATIVE_PATH,
});
const QUALITY_FREEZE_MANIFEST_PATH =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-066-engineering-first-offline-b0-SSBiXrxT/quality/QUALITY_FREEZE_MANIFEST_V3.json";
const AUTHORIZED_EVIDENCE_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-066-engineering-first-offline-b0-SSBiXrxT";
const TASK_CARD_IDENTITY = Object.freeze({
  byte_length: 17363,
  sha256: "7a01ce672230be2b163ffe9a52825e07d6671c599ca41a06acf6a5e61874a394",
});
const QUALITY_FREEZE_IDENTITY = Object.freeze({
  byte_length: 5579,
  sha256: "37756abd26ebde645fde0197185d4020eb42998c1c222bac72df1268b8e37e7b",
});
const TASK_ID = "AIOS-P1-066_ENGINEERING_FIRST_OFFLINE_B0_COMPLETE_EVIDENCE_VERTICAL_SLICE";
const CONTROL_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const CLAIM_BOUNDARY =
  "ONE_VISIBLE_SYNTHETIC_REP_001_COOPERATIVE_LOCAL_OFFLINE_B0_COMPLETE_EVIDENCE_OBSERVATION_ONLY";
const AGENT_STATUS = "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED";
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
const EXPECTED_BASE = Object.freeze({
  commit: "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f",
  tree: "900814727113d65f5dad8b63222e14f39b2cf38b",
  source_byte_length: 115,
  source_sha256: "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75",
});
const EXPECTED_POSTIMAGE = Object.freeze({
  byte_length: 127,
  sha256: "e8304b77da9b8c33f64ecdc568db7e97297ace72ecb796971bb3f5eda09d9001",
});
const SOURCE_DESTINATIONS = Object.freeze({
  source_preimage: "src/range.mjs",
  issue_test: "test/issue.test.mjs",
  regression_test: "test/regression.test.mjs",
});

class RunnerError extends Error {
  constructor(code, message, details = undefined) {
    super(message);
    this.name = "RunnerError";
    this.code = code;
    this.details = details;
  }
}

const fail = (code, message, details = undefined) => {
  throw new RunnerError(code, message, details);
};
const assert = (condition, code, message, details = undefined) => {
  if (!condition) fail(code, message, details);
};
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const identityOf = (bytes) => ({ byte_length: bytes.length, sha256: sha256(bytes) });
const canonicalize = (value) => {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
};
const sameJson = (left, right) => JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right));
const canonicalJsonBytes = (value) => Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");

function parseJsonBytes(bytes, code, label) {
  assert(Buffer.isBuffer(bytes), code, `${label} is not bytes`);
  const text = bytes.toString("utf8");
  assert(Buffer.from(text, "utf8").equals(bytes), code, `${label} is not exact UTF-8`);
  try {
    return JSON.parse(text);
  } catch {
    fail(code, `${label} is not valid JSON`);
  }
}

function exactKeys(value, keys, code, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), code, `${label} is not an object`);
  assert(sameJson(Object.keys(value).sort(), [...keys].sort()), code, `${label} key set drifted`);
}

function pathIsWithin(root, candidate, allowRoot = false) {
  const rel = relative(root, candidate);
  if (rel === "") return allowRoot;
  return rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function containedPath(root, relativePath, code = "INPUT_PATH_ESCAPE_REJECTED") {
  assert(
    typeof relativePath === "string" && relativePath.length > 0 && !isAbsolute(relativePath),
    code,
    "path is not a non-empty relative path",
  );
  const candidate = resolve(root, relativePath);
  assert(pathIsWithin(root, candidate), code, "path escaped its root");
  return candidate;
}

function safeReadRegular(path, expected = undefined, code = "INPUT_IDENTITY_REJECTED", label = "file", options = {}) {
  const absolute = resolve(path);
  let before;
  try {
    before = lstatSync(absolute);
  } catch (error) {
    fail(code, `${label} lstat failed`, { error: error.code ?? error.message });
  }
  if (before.isSymbolicLink()) fail(options.symlinkCode ?? code, `${label} is a symlink`);
  if (!before.isFile()) fail(options.typeCode ?? code, `${label} is not a regular file`);
  if (options.allowMultipleLinks !== true) assert(before.nlink === 1, code, `${label} nlink is not one`);
  if (options.requireCanonicalPath !== false) {
    assert(realpathSync(absolute) === absolute, options.symlinkCode ?? code, `${label} path contains a symlink`);
  }
  let descriptor;
  try {
    descriptor = openSync(absolute, fsConstants.O_RDONLY | O_NOFOLLOW);
    const opened = fstatSync(descriptor);
    assert(opened.isFile(), options.typeCode ?? code, `${label} descriptor is not a file`);
    if (options.allowMultipleLinks !== true) assert(opened.nlink === 1, code, `${label} descriptor nlink drifted`);
    assert(opened.dev === before.dev && opened.ino === before.ino, code, `${label} identity changed before read`);
    const bytes = readFileSync(descriptor);
    const after = lstatSync(absolute);
    assert(after.isFile() && !after.isSymbolicLink(), code, `${label} type changed after read`);
    assert(after.dev === opened.dev && after.ino === opened.ino, code, `${label} identity changed after read`);
    if (options.allowMultipleLinks !== true) assert(after.nlink === 1, code, `${label} nlink changed after read`);
    const identity = identityOf(bytes);
    if (expected !== undefined) {
      assert(identity.byte_length === expected.byte_length, code, `${label} byte length drifted`);
      assert(identity.sha256 === expected.sha256, code, `${label} SHA-256 drifted`);
    }
    return { path: absolute, bytes, identity, stat: opened };
  } catch (error) {
    if (error instanceof RunnerError) throw error;
    fail(code, `${label} could not be read`, { error: error.code ?? error.message });
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function assertRealDirectory(path, code, label) {
  assert(isAbsolute(path), code, `${label} path is not absolute`);
  const absolute = resolve(path);
  let stat;
  try {
    stat = lstatSync(absolute);
  } catch (error) {
    fail(code, `${label} lstat failed`, { error: error.code ?? error.message });
  }
  assert(stat.isDirectory() && !stat.isSymbolicLink(), code, `${label} is not a real directory`);
  const realpath = realpathSync(absolute);
  assert(realpath === absolute, code, `${label} path contains a symlink`);
  return { path: absolute, realpath, device: stat.dev, inode: stat.ino };
}

function directoryReceipt(path) {
  return assertRealDirectory(path, "RUN_ROOT_REJECTED", "directory");
}

function createExclusiveDirectory(path, mode = 0o700) {
  try {
    mkdirSync(path, { mode, recursive: false });
  } catch (error) {
    fail("PREEXISTING_EVIDENCE_REJECTED", `exclusive directory creation failed: ${path}`, {
      error: error.code ?? error.message,
    });
  }
  const receipt = assertRealDirectory(resolve(path), "RUN_ROOT_REJECTED", "created directory");
  chmodSync(receipt.path, mode);
  return receipt;
}

function writeCreateOnceFile(path, bytes, mode = 0o600) {
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
  const file = safeReadRegular(path, identityOf(bytes), "EVIDENCE_WRITE_REJECTED", "created Evidence");
  chmodSync(path, mode);
  return { path: file.path, ...file.identity };
}

function artifactReference(artifact, root) {
  const rel = relative(root, artifact.path);
  assert(pathIsWithin(root, artifact.path), "EVIDENCE_PATH_ESCAPE_REJECTED", "artifact escaped run root");
  return { path: rel, byte_length: artifact.byte_length, sha256: artifact.sha256 };
}

function validateSchemaValue(value, schemaPath, code, label) {
  const schema = parseJsonBytes(safeReadRegular(schemaPath, undefined, code, `${label} schema`).bytes, code, `${label} schema`);
  const errors = validateSchema(value, schema);
  assert(errors.length === 0, code, `${label} schema failed`, { errors });
}

function repositoryPath(relativePath) {
  return containedPath(REPOSITORY_ROOT, relativePath, "INPUT_PATH_ESCAPE_REJECTED");
}

function validateTaskCard(taskCardArgument) {
  const supplied = resolve(process.cwd(), taskCardArgument);
  assert(supplied === TASK_CARD_PATH, "TASK_CARD_DRIFT", "Task Card path is not frozen path");
  const file = safeReadRegular(TASK_CARD_PATH, TASK_CARD_IDENTITY, "TASK_CARD_DRIFT", "Task Card");
  const card = parseJsonBytes(file.bytes, "TASK_CARD_DRIFT", "Task Card");
  assert(
    card.task_id === TASK_ID &&
      card.control_id === CONTROL_ID &&
      card.worker_may_modify === false &&
      card.adapter_contract.export_name === "admitOfflineB0Result" &&
      card.adapter_contract.proposal_flow === "DECODE_TO_BUFFER_THEN_PASS_UNMODIFIED_TO_COMPILE_FINITE_TYPED_PATCH_IR" &&
      card.runner_interface.agent_success_label === AGENT_STATUS &&
      card.claim_boundary === CLAIM_BOUNDARY,
    "TASK_CARD_DRIFT",
    "Task Card frozen semantics drifted",
  );
  assert(sameJson(card.external_effects, FALSE_EFFECTS), "TASK_CARD_DRIFT", "Task Card external effects drifted");
  return { card, file };
}

function validateQualityFreeze(card) {
  const file = safeReadRegular(
    QUALITY_FREEZE_MANIFEST_PATH,
    QUALITY_FREEZE_IDENTITY,
    "QUALITY_FREEZE_REJECTED",
    "Quality Freeze manifest",
  );
  const value = parseJsonBytes(file.bytes, "QUALITY_FREEZE_REJECTED", "Quality Freeze manifest");
  assert(
    value.task_id === TASK_ID &&
      value.record_type === "sourcelens_aios_p1_066_quality_freeze_manifest_and_receipt_v3" &&
      value.status === "QUALITY_FREEZE_V3_EFFECTIVE_FINAL_REPAIR_HANDOFF_ALLOWED" &&
      value.freeze_effective === true &&
      value.worker_handoff_allowed === true &&
      value.candidate_must_bind_this_v3_manifest === true &&
      value.supersession?.superseded_manifest_may_bind_candidate === false,
    "QUALITY_FREEZE_REJECTED",
    "Quality Freeze state is not effective",
  );
  const cardRecord = value.quality_assets_sorted_by_path?.find(
    (entry) => entry.path === "evaluation-harness/fixtures/offline-b0-complete-evidence-v1/task-card.json",
  );
  assert(
    cardRecord?.byte_length === TASK_CARD_IDENTITY.byte_length && cardRecord?.sha256 === TASK_CARD_IDENTITY.sha256,
    "QUALITY_FREEZE_REJECTED",
    "Quality Freeze Task Card binding drifted",
  );
  assert(value.claim_boundary === card.claim_boundary, "QUALITY_FREEZE_REJECTED", "Quality Freeze claim drifted");
  return { value, file };
}

function readCandidateGit(repositoryRoot, argv, label) {
  const environment = {
    PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
    LANG: "C",
    LC_ALL: "C",
    TZ: "UTC",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_TERMINAL_PROMPT: "0",
    GIT_OPTIONAL_LOCKS: "0",
  };
  const outcome = spawnSync("/usr/bin/git", ["-C", repositoryRoot, ...argv], {
    cwd: repositoryRoot,
    env: environment,
    encoding: null,
    timeout: 15000,
    maxBuffer: 4 * 1024 * 1024,
    windowsHide: true,
  });
  assert(!outcome.error, "CANDIDATE_BINDING_REJECTED", `${label} could not execute`);
  assert(outcome.status === 0 && outcome.signal === null, "CANDIDATE_BINDING_REJECTED", `${label} failed`);
  const stdout = Buffer.isBuffer(outcome.stdout) ? outcome.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(outcome.stderr) ? outcome.stderr : Buffer.alloc(0);
  assert(stderr.length === 0, "CANDIDATE_BINDING_REJECTED", `${label} emitted stderr`);
  return stdout;
}

function currentExecutingModuleIdentities() {
  return Object.fromEntries(Object.entries(EXECUTING_MODULE_PATHS).map(([role, path]) => {
    const file = safeReadRegular(repositoryPath(path), undefined, "CANDIDATE_BINDING_REJECTED", `candidate ${role}`);
    return [role, { path, ...file.identity }];
  }));
}

function currentCandidateRepositoryProvenance() {
  const repository = assertRealDirectory(REPOSITORY_ROOT, "CANDIDATE_BINDING_REJECTED", "candidate repository root");
  const head = readCandidateGit(repository.path, ["rev-parse", "HEAD"], "candidate HEAD").toString("utf8").trim();
  const tree = readCandidateGit(repository.path, ["rev-parse", "HEAD^{tree}"], "candidate tree").toString("utf8").trim();
  const statusBytes = readCandidateGit(
    repository.path,
    ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
    "candidate status",
  );
  assert(/^[0-9a-f]{40}$/.test(head) && /^[0-9a-f]{40}$/.test(tree), "CANDIDATE_BINDING_REJECTED", "candidate Git identity invalid");
  assert(statusBytes.length === 0, "CANDIDATE_BINDING_REJECTED", "candidate repository is not clean");
  return {
    repository: {
      path: repository.path,
      realpath: repository.realpath,
      device: repository.device,
      inode: repository.inode,
      head,
      tree,
      workspace_status: "clean",
    },
    executing_modules: currentExecutingModuleIdentities(),
  };
}

function currentCandidateManifestValue() {
  const observed = currentCandidateRepositoryProvenance();
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_066_exact_candidate_manifest_v2",
    task_id: TASK_ID,
    candidate_commit: observed.repository.head,
    candidate_tree: observed.repository.tree,
    quality_freeze_manifest_sha256: QUALITY_FREEZE_IDENTITY.sha256,
    repository: {
      path: observed.repository.path,
      realpath: observed.repository.realpath,
      head: observed.repository.head,
      tree: observed.repository.tree,
      workspace_status: observed.repository.workspace_status,
    },
    executing_modules: observed.executing_modules,
  };
}

function validateCandidateManifest(path, { selfTestRoot = undefined } = {}) {
  assert(typeof path === "string" && isAbsolute(path), "CANDIDATE_BINDING_REJECTED", "candidate manifest path is not absolute");
  const absolute = resolve(path);
  if (selfTestRoot === undefined) {
    const root = assertRealDirectory(AUTHORIZED_EVIDENCE_ROOT, "CANDIDATE_BINDING_REJECTED", "authorized Evidence root");
    assert(pathIsWithin(root.path, absolute), "CANDIDATE_BINDING_REJECTED", "candidate manifest escaped authorized Evidence root");
  } else {
    assert(pathIsWithin(selfTestRoot, absolute), "CANDIDATE_BINDING_REJECTED", "self-test candidate manifest escaped owned root");
  }
  const file = safeReadRegular(absolute, undefined, "CANDIDATE_BINDING_REJECTED", "candidate manifest");
  const value = parseJsonBytes(file.bytes, "CANDIDATE_BINDING_REJECTED", "candidate manifest");
  exactKeys(value, [
    "schema_version",
    "record_type",
    "task_id",
    "candidate_commit",
    "candidate_tree",
    "quality_freeze_manifest_sha256",
    "repository",
    "executing_modules",
  ], "CANDIDATE_BINDING_REJECTED", "candidate manifest");
  assert(
    value.schema_version === 1 &&
      value.record_type === "sourcelens_aios_p1_066_exact_candidate_manifest_v2" &&
      value.task_id === TASK_ID,
    "CANDIDATE_BINDING_REJECTED",
    "candidate manifest identity drifted",
  );
  assert(/^[0-9a-f]{40}$/.test(value.candidate_commit), "CANDIDATE_BINDING_REJECTED", "candidate commit is invalid");
  assert(/^[0-9a-f]{40}$/.test(value.candidate_tree), "CANDIDATE_BINDING_REJECTED", "candidate tree is invalid");
  assert(
    value.quality_freeze_manifest_sha256 === QUALITY_FREEZE_IDENTITY.sha256,
    "CANDIDATE_BINDING_REJECTED",
    "candidate Quality Freeze binding drifted",
  );
  exactKeys(value.repository, ["path", "realpath", "head", "tree", "workspace_status"], "CANDIDATE_BINDING_REJECTED", "candidate repository declaration");
  assert(value.repository.path === REPOSITORY_ROOT && value.repository.realpath === realpathSync(REPOSITORY_ROOT), "CANDIDATE_BINDING_REJECTED", "candidate repository path drifted");
  assert(value.repository.head === value.candidate_commit && value.repository.tree === value.candidate_tree && value.repository.workspace_status === "clean", "CANDIDATE_BINDING_REJECTED", "candidate repository declaration drifted");
  exactKeys(value.executing_modules, Object.keys(EXECUTING_MODULE_PATHS), "CANDIDATE_BINDING_REJECTED", "candidate executing modules");
  for (const [role, expectedPath] of Object.entries(EXECUTING_MODULE_PATHS)) {
    exactKeys(value.executing_modules[role], ["path", "byte_length", "sha256"], "CANDIDATE_BINDING_REJECTED", `candidate ${role} declaration`);
    assert(value.executing_modules[role].path === expectedPath, "CANDIDATE_BINDING_REJECTED", `candidate ${role} path drifted`);
  }
  const observed = currentCandidateRepositoryProvenance();
  assert(observed.repository.head === value.candidate_commit && observed.repository.tree === value.candidate_tree, "CANDIDATE_BINDING_REJECTED", "candidate Git identity does not match manifest");
  assert(sameJson(observed.executing_modules, value.executing_modules), "CANDIDATE_BINDING_REJECTED", "candidate executing module identity drifted");
  return {
    value,
    file,
    provenance: observed,
    binding: {
      candidate_commit: value.candidate_commit,
      candidate_tree: value.candidate_tree,
      candidate_manifest_sha256: file.identity.sha256,
      quality_freeze_manifest_sha256: QUALITY_FREEZE_IDENTITY.sha256,
    },
  };
}

function readBoundRepositoryFile(record, code, label) {
  assert(record && typeof record.path === "string", code, `${label} declaration is invalid`);
  return safeReadRegular(repositoryPath(record.path), record, code, label);
}

function validateFrozenAssets(card) {
  const contract = readBoundRepositoryFile(card.contract, "QUALITY_ASSET_DRIFT", "Task Contract");
  const authority = safeReadRegular(card.authority.path, card.authority, "QUALITY_ASSET_DRIFT", "Task Authority");
  const accepted = {};
  for (const [name, record] of Object.entries(card.accepted_inputs)) {
    if (record.path) accepted[name] = readBoundRepositoryFile(record, "QUALITY_ASSET_DRIFT", `accepted ${name}`);
  }
  const quality = {};
  for (const [name, record] of Object.entries(card.quality_assets)) {
    quality[name] = readBoundRepositoryFile(record, "QUALITY_ASSET_DRIFT", `Quality ${name}`);
  }
  const taskSpec = parseJsonBytes(accepted.task_spec.bytes, "SUBMISSION_SCHEMA_REJECTED", "TaskSpec");
  const environment = parseJsonBytes(quality.environment_snapshot.bytes, "SUBMISSION_SCHEMA_REJECTED", "EnvironmentSnapshot");
  const system = parseJsonBytes(quality.system_configuration.bytes, "SUBMISSION_SCHEMA_REJECTED", "SystemConfiguration");
  const targetRuntime = parseJsonBytes(quality.target_runtime.bytes, "SUBMISSION_SCHEMA_REJECTED", "target runtime");
  const negative = parseJsonBytes(quality.negative_cases.bytes, "SUBMISSION_SCHEMA_REJECTED", "negative matrix");
  const expectedBaseFailure = parseJsonBytes(accepted.expected_base_failure.bytes, "SUBMISSION_SCHEMA_REJECTED", "expected base failure");
  const recipe = parseJsonBytes(accepted.materialization_recipe.bytes, "SUBMISSION_SCHEMA_REJECTED", "materialization recipe");
  validateSchemaValue(taskSpec, join(REPOSITORY_ROOT, "docs/aios/schemas/task-spec.schema.json"), "SUBMISSION_SCHEMA_REJECTED", "TaskSpec");
  validateSchemaValue(environment, join(REPOSITORY_ROOT, "docs/aios/schemas/environment-snapshot.schema.json"), "SUBMISSION_SCHEMA_REJECTED", "EnvironmentSnapshot");
  validateSchemaValue(system, join(REPOSITORY_ROOT, "docs/aios/schemas/system-configuration.schema.json"), "SUBMISSION_SCHEMA_REJECTED", "SystemConfiguration");
  assert(
    taskSpec.task_id === CONTROL_ID &&
      taskSpec.environment_snapshot_ref === environment.snapshot_id &&
      taskSpec.repository.base_commit === EXPECTED_BASE.commit &&
      taskSpec.repository.tree_hash === EXPECTED_BASE.tree &&
      taskSpec.repository.base_commit === environment.source.base_commit &&
      taskSpec.repository.tree_hash === environment.source.tree_hash,
    "ENVIRONMENT_BINDING_REJECTED",
    "TaskSpec and environment source binding drifted",
  );
  assert(
    taskSpec.network_policy === "none" &&
      sameJson(taskSpec.allowed_network_hosts, []) &&
      environment.network.policy === "none" &&
      sameJson(environment.network.allowed_hosts, []),
    "ENVIRONMENT_BINDING_REJECTED",
    "offline environment boundary drifted",
  );
  assert(
    system.adapter_id === "B0" &&
      system.adapter_version === ADAPTER_VERSION &&
      system.loop_limit === 1 &&
      sameJson(system.enabled_tools, []) &&
      system.model_ref === environment.model.model_ref &&
      system.prompt_ref === environment.prompt_version &&
      system.policy_ref === environment.policy_version &&
      system.response_format_ref === taskSpec.baseline_context.response_format_ref,
    "SYSTEM_CONFIGURATION_BINDING_REJECTED",
    "B0 system configuration drifted",
  );
  assert(
    targetRuntime.declared_target?.materialized === false &&
      targetRuntime.declared_target?.container_execution_observed === false &&
      targetRuntime.actual_executor_evidence_policy?.capture_per_run === true,
    "ENVIRONMENT_BINDING_REJECTED",
    "declared target truth boundary drifted",
  );
  assert(
    negative.case_count === 15 && negative.cases?.length === 15 && negative.maximum_false_accepts === 0,
    "NEGATIVE_MATRIX_REJECTED",
    "negative matrix drifted",
  );
  assert(
    expectedBaseFailure.expected_exit_status === 1 &&
      expectedBaseFailure.required_output_tokens.includes("not ok") &&
      expectedBaseFailure.required_output_tokens.includes("REP001_NEGATIVE_RANGE_ORDER"),
    "INPUT_IDENTITY_REJECTED",
    "typed base failure drifted",
  );
  assert(recipe.hash_algorithm === "sha1" && recipe.commit_message === "fixture: base", "INPUT_IDENTITY_REJECTED", "materialization recipe drifted");
  assert(
    process.platform === card.declared_target_and_actual_executor.actual_executor_identity.platform &&
      process.arch === card.declared_target_and_actual_executor.actual_executor_identity.architecture &&
      process.version === card.declared_target_and_actual_executor.actual_executor_identity.node_version &&
      realpathSync(process.execPath) === realpathSync(card.declared_target_and_actual_executor.actual_executor_identity.node_path),
    "EXECUTOR_EVIDENCE_REJECTED",
    "actual Node executor drifted",
  );
  safeReadRegular(
    card.declared_target_and_actual_executor.actual_executor_identity.node_path,
    {
      byte_length: card.declared_target_and_actual_executor.actual_executor_identity.node_byte_length,
      sha256: card.declared_target_and_actual_executor.actual_executor_identity.node_sha256,
    },
    "EXECUTOR_EVIDENCE_REJECTED",
    "Node executable",
    { allowMultipleLinks: true, requireCanonicalPath: false },
  );
  safeReadRegular(
    card.declared_target_and_actual_executor.actual_executor_identity.git_path,
    {
      byte_length: card.declared_target_and_actual_executor.actual_executor_identity.git_byte_length,
      sha256: card.declared_target_and_actual_executor.actual_executor_identity.git_sha256,
    },
    "EXECUTOR_EVIDENCE_REJECTED",
    "Git executable",
    { allowMultipleLinks: true, requireCanonicalPath: false },
  );

  const submission = parseJsonBytes(quality.positive_result.bytes, "SUBMISSION_SCHEMA_REJECTED", "positive result");
  const encoded = submission?.results?.[0]?.finite_typed_result?.bytes_base64;
  const proposalBytes = typeof encoded === "string" ? Buffer.from(encoded, "base64") : Buffer.alloc(0);
  let admission;
  try {
    admission = admitOfflineB0Result(quality.positive_result.bytes, proposalBytes);
  } catch (error) {
    if (error instanceof OfflineB0AdapterError) fail(error.code, error.message);
    throw error;
  }
  return {
    card,
    contract,
    authority,
    accepted,
    quality,
    taskSpec,
    environment,
    system,
    targetRuntime,
    negative,
    expectedBaseFailure,
    recipe,
    proposalBytes,
    admission,
  };
}

function deterministicEnvironment(card, home) {
  return {
    ...card.command_profile.environment,
    HOME: home,
  };
}

function commandStreamPath(actionId, stream) {
  return `streams/${actionId}.${stream}`;
}

function runCommand(context, actionId, argv, expectedExitStatus = undefined) {
  assert(
    Object.values(context.card.fixed_commands).some((allowed) => sameJson(allowed, argv)),
    "COMMAND_PROFILE_REJECTED",
    `command ${actionId} is not frozen`,
  );
  context.telemetry.child_start_attempts += 1;
  const started = process.hrtime.bigint();
  const outcome = spawnSync(argv[0], argv.slice(1), {
    cwd: context.materialization.path,
    env: context.environment,
    encoding: null,
    timeout: context.card.command_profile.timeout_ms,
    maxBuffer: context.card.command_profile.max_buffer_bytes,
    windowsHide: true,
  });
  const durationMs = Number(process.hrtime.bigint() - started) / 1_000_000;
  const stdout = Buffer.isBuffer(outcome.stdout) ? outcome.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(outcome.stderr) ? outcome.stderr : Buffer.alloc(0);
  const stdoutArtifact = writeCreateOnceFile(join(context.run.path, commandStreamPath(actionId, "stdout")), stdout);
  const stderrArtifact = writeCreateOnceFile(join(context.run.path, commandStreamPath(actionId, "stderr")), stderr);
  const stdoutRef = artifactReference(stdoutArtifact, context.run.path);
  const stderrRef = artifactReference(stderrArtifact, context.run.path);
  context.artifacts.push({ role: "command_stream", action_id: actionId, stream: "stdout", ...stdoutRef });
  context.artifacts.push({ role: "command_stream", action_id: actionId, stream: "stderr", ...stderrRef });
  const record = {
    action_id: actionId,
    argv: [...argv],
    argv_equivalent: [...argv],
    cwd: context.materialization.path,
    cwd_equivalent: "TASK_REPOSITORY",
    exit_status: outcome.status,
    signal: outcome.signal,
    timeout_ms: context.card.command_profile.timeout_ms,
    duration_ms: durationMs,
    stdout: stdoutRef,
    stderr: stderrRef,
  };
  context.commands.push({ record, stdout, stderr });
  if (outcome.error) {
    fail("COMMAND_EXECUTION_REJECTED", `command ${actionId} failed to execute`, {
      error: outcome.error.code ?? outcome.error.message,
    });
  }
  assert(Number.isInteger(outcome.status), "COMMAND_EXECUTION_REJECTED", `command ${actionId} has no exit status`);
  if (expectedExitStatus !== undefined) {
    assert(
      outcome.status === expectedExitStatus && outcome.signal === null,
      "COMMAND_RESULT_REJECTED",
      `command ${actionId} result drifted`,
      { expected: expectedExitStatus, actual: outcome.status, signal: outcome.signal },
    );
  }
  return { record, stdout, stderr };
}

function commandText(command) {
  return Buffer.concat([command.stdout, Buffer.from("\n"), command.stderr]).toString("utf8");
}

function trimmedStdout(command) {
  return command.stdout.toString("utf8").trim();
}

function parseGitStatus(bytes) {
  const fields = bytes.toString("utf8").split("\0").filter(Boolean);
  const paths = [];
  for (let index = 0; index < fields.length; index += 1) {
    const entry = fields[index];
    assert(entry.length >= 4 && entry[2] === " ", "CHANGED_PATH_SCOPE_REJECTED", "Git status format drifted");
    const status = entry.slice(0, 2);
    paths.push(entry.slice(3));
    if (status.includes("R") || status.includes("C")) index += 1;
  }
  return paths.sort();
}

function verifyExactFile(path, expected, code, label) {
  return safeReadRegular(path, expected, code, label);
}

function atomicReplaceOwned(path, expectedCurrent, replacementBytes, telemetry, code, mutationState = undefined) {
  const current = safeReadRegular(path, expectedCurrent, code, "owned materialized source");
  const parent = dirname(path);
  const temporary = join(parent, `.p1-066-${randomBytes(16).toString("hex")}.tmp`);
  if (mutationState) {
    mutationState.attempted = true;
    mutationState.current = "PREIMAGE_VERIFIED";
    mutationState.rename_completed = false;
  }
  telemetry.mutation_attempts += 1;
  writeCreateOnceFile(temporary, replacementBytes, current.stat.mode & 0o777);
  try {
    renameSync(temporary, path);
  } catch (error) {
    fail(code, "atomic source replacement failed", { error: error.code ?? error.message });
  }
  if (mutationState) {
    mutationState.rename_completed = true;
    mutationState.current = "POSTIMAGE_RENAME_COMPLETED";
  }
  const replaced = safeReadRegular(path, identityOf(replacementBytes), code, "replaced materialized source");
  if (mutationState) mutationState.current = "POSTIMAGE_VERIFIED";
  return replaced;
}

function exactIdentityKind(path, preimage, postimage) {
  const file = safeReadRegular(path, undefined, "ROLLBACK_REJECTED", "materialized source during rollback classification");
  if (file.identity.byte_length === preimage.byte_length && file.identity.sha256 === preimage.sha256) return "PREIMAGE";
  if (file.identity.byte_length === postimage.byte_length && file.identity.sha256 === postimage.sha256) return "POSTIMAGE";
  return "UNKNOWN";
}

function completeAction(context, actionId) {
  const expected = context.card.required_actions_in_order[context.completedActions.length];
  assert(actionId === expected, "ACTION_SCHEDULE_REJECTED", `expected ${expected}, got ${actionId}`);
  context.completedActions.push(actionId);
}

function createRunRoot(evidenceRootArgument, runId, { selfTestRoot = undefined } = {}) {
  assert(RUN_ID_PATTERN.test(runId), "CLI_REJECTED", "run id is invalid");
  const evidenceRoot = assertRealDirectory(resolve(evidenceRootArgument), "EVIDENCE_ROOT_REJECTED", "Evidence root");
  if (selfTestRoot === undefined) {
    const authorized = assertRealDirectory(AUTHORIZED_EVIDENCE_ROOT, "EVIDENCE_ROOT_REJECTED", "authorized Evidence root");
    assert(
      evidenceRoot.path === authorized.path || pathIsWithin(authorized.path, evidenceRoot.path),
      "EVIDENCE_ROOT_REJECTED",
      "Evidence root escaped authorized root",
    );
  } else {
    assert(
      evidenceRoot.path === selfTestRoot || pathIsWithin(selfTestRoot, evidenceRoot.path),
      "EVIDENCE_ROOT_REJECTED",
      "self-test Evidence root escaped owned root",
    );
  }
  const runPath = join(evidenceRoot.path, runId);
  assert(pathIsWithin(evidenceRoot.path, runPath), "EVIDENCE_ROOT_REJECTED", "run root escaped Evidence root");
  const run = createExclusiveDirectory(runPath);
  return { evidenceRoot, run };
}

function expectedBindings(card) {
  return {
    task_spec: card.accepted_inputs.task_spec,
    target_runtime: card.quality_assets.target_runtime,
    environment_snapshot: card.quality_assets.environment_snapshot,
    system_configuration: card.quality_assets.system_configuration,
    positive_result: card.quality_assets.positive_result,
    compiler: card.accepted_inputs.compiler,
    proposal: card.accepted_inputs.ir10,
  };
}

function actualExecutor(card) {
  return {
    executor_kind: "LOCAL_HOST_PROCESS",
    ...card.declared_target_and_actual_executor.actual_executor_identity,
    container_runtime_observed: false,
    declared_target_materialized: false,
  };
}

function captureCandidateEvidence(context, candidate) {
  const manifestArtifact = writeCreateOnceFile(
    join(context.run.path, "candidate-manifest.json"),
    candidate.file.bytes,
  );
  const manifestRef = artifactReference(manifestArtifact, context.run.path);
  context.artifacts.push({ role: "candidate_manifest", ...manifestRef });
  const provenance = {
    schema_version: 1,
    record_type: context.card.candidate_provenance_contract.provenance_record_type,
    task_id: TASK_ID,
    candidate_binding: candidate.binding,
    candidate_manifest_artifact: manifestRef,
    repository: candidate.provenance.repository,
    executing_modules: candidate.provenance.executing_modules,
    verification: {
      repository_root_equals_executing_module_repository_root: true,
      head_tree_and_clean_state_recomputed_at_execution: true,
      executing_module_identities_recomputed_at_execution: true,
    },
  };
  const provenanceArtifact = writeCreateOnceFile(
    join(context.run.path, "candidate-provenance.json"),
    canonicalJsonBytes(provenance),
  );
  const provenanceRef = artifactReference(provenanceArtifact, context.run.path);
  context.artifacts.push({ role: "candidate_provenance", ...provenanceRef });
  context.candidateProvenance = provenance;
  return provenance;
}

function createMaterialization(context, assets) {
  const materialization = createExclusiveDirectory(join(context.run.path, "materialization"));
  const streams = createExclusiveDirectory(join(context.run.path, "streams"));
  const home = createExclusiveDirectory(join(context.run.path, "home"));
  context.materialization = materialization;
  context.streams = streams;
  context.home = home;
  context.environment = deterministicEnvironment(context.card, home.path);
  for (const directory of ["src", "test"]) createExclusiveDirectory(join(materialization.path, directory));
  for (const [name, destinationRelative] of Object.entries(SOURCE_DESTINATIONS)) {
    const source = assets.accepted[name];
    const destination = containedPath(materialization.path, destinationRelative, "MATERIALIZATION_REJECTED");
    writeCreateOnceFile(destination, source.bytes, 0o644);
  }
  verifyExactFile(
    join(materialization.path, SOURCE_DESTINATIONS.source_preimage),
    context.card.accepted_inputs.source_preimage,
    "MATERIALIZATION_REJECTED",
    "materialized source preimage",
  );
  return materialization;
}

function buildPatchEvidencePackage(context, assets, candidate, rollbackSource, observationRef) {
  assert(context.patchRef, "PATCH_EVIDENCE_PACKAGE_REJECTED", "patch artifact is missing");
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_066_patch_evidence_package",
    task_id: TASK_ID,
    run_id: context.runId,
    manifest: {
      schema_version: 1,
      task_id: TASK_ID,
      run_id: context.runId,
      artifact_checksums_bound_by_run_manifest: true,
    },
    source_identity: {
      candidate_binding: candidate.binding,
      candidate_repository: {
        head: candidate.provenance.repository.head,
        tree: candidate.provenance.repository.tree,
        workspace_status: candidate.provenance.repository.workspace_status,
      },
      materialized_base: {
        commit: EXPECTED_BASE.commit,
        tree: EXPECTED_BASE.tree,
        workspace_status_before: "clean",
        workspace_status_after_rollback: "clean",
      },
    },
    environment: {
      target_runtime: context.card.quality_assets.target_runtime,
      environment_snapshot: context.card.quality_assets.environment_snapshot,
      system_configuration: context.card.quality_assets.system_configuration,
      actual_executor: actualExecutor(context.card),
    },
    understanding: {
      issue_id: "REP001_NEGATIVE_RANGE_ORDER",
      interpretation: "normalize a reversed finite range without changing already ordered ranges",
      repository_evidence_references: [
        context.card.accepted_inputs.task_spec.path,
        context.card.accepted_inputs.expected_base_failure.path,
        context.card.accepted_inputs.source_preimage.path,
      ],
    },
    plan: {
      bounded_intended_changes: ["src/range.mjs"],
      mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT",
      risks: ["incorrect postimage", "scope drift", "test regression", "incomplete rollback"],
    },
    actions: {
      ordered_action_ids: [...context.card.required_actions_in_order],
      command_action_ids: context.commands.map((entry) => entry.record.action_id),
      observation_artifact: observationRef,
    },
    patch: {
      changed_paths: ["src/range.mjs"],
      diff: context.patchRef,
      postimage: EXPECTED_POSTIMAGE,
    },
    tests: {
      base_issue: { action_id: "base_issue_test", exit_status: 1 },
      base_regression: { action_id: "base_regression_test", exit_status: 0 },
      patched_issue: { action_id: "patched_issue_test", exit_status: 0 },
      patched_regression: { action_id: "patched_regression_test", exit_status: 0 },
    },
    verification: {
      required: true,
      evaluator: {
        path: context.card.quality_evaluator_interface.module_path,
        version: context.card.quality_evaluator_interface.version,
      },
      status: "PENDING_INDEPENDENT_EVALUATION",
      runner_reported_pass_authoritative: false,
    },
    risk: {
      changed_path_scope: ["src/range.mjs"],
      external_effects: FALSE_EFFECTS,
      declared_target_materialized: false,
      container_execution_observed: false,
      residual_claim_boundary: CLAIM_BOUNDARY,
    },
    approval: {
      required_roles: ["CTO", "Security", "Quality"],
      actual_state: "PENDING_TASK_GATE",
      runner_self_approval: false,
    },
    rollback: {
      source_artifact_path: rollbackSource.path,
      restored_source_byte_length: EXPECTED_BASE.source_byte_length,
      restored_source_sha256: EXPECTED_BASE.source_sha256,
      restored_base_commit: EXPECTED_BASE.commit,
      restored_base_tree: EXPECTED_BASE.tree,
      restored_workspace_status: "clean",
      disposable_workspace_receipt: context.materialization,
    },
  };
}

function emitRunEvidence(context, assets, candidate, startedAt, endedAt, rollbackSource) {
  const commandRecords = context.commands.map((entry) => entry.record);
  const observation = {
    schema_version: 1,
    record_type: context.card.run_evidence_contract.observation_record_type,
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    candidate_binding: candidate.binding,
    physical_receipt: {
      run_root: context.run,
      materialization_root: context.materialization,
    },
    actual_executor: actualExecutor(context.card),
    bindings: expectedBindings(context.card),
    ordered_action_ids: [...context.completedActions, "emit_create_once_run_record_and_manifest"],
    admission: {
      status: assets.admission.status,
      result_count: assets.admission.result_count,
      program_id: assets.admission.program_id,
      outcome_id: assets.admission.outcome_id,
      postimage_byte_length: assets.admission.postimage_byte_length,
      postimage_sha256: assets.admission.postimage_sha256,
    },
    commands: commandRecords,
    base_tests: {
      issue: { action_id: "base_issue_test", exit_status: 1 },
      regression: { action_id: "base_regression_test", exit_status: 0 },
    },
    patched_tests: {
      issue: { action_id: "patched_issue_test", exit_status: 0 },
      regression: { action_id: "patched_regression_test", exit_status: 0 },
    },
    changed_paths: ["src/range.mjs"],
    rollback: {
      mutation_occurred: true,
      source_artifact_path: rollbackSource.path,
      restored_source_byte_length: EXPECTED_BASE.source_byte_length,
      restored_source_sha256: EXPECTED_BASE.source_sha256,
      base_commit: EXPECTED_BASE.commit,
      base_tree: EXPECTED_BASE.tree,
      git_status_porcelain: "",
      restored_exact_base: true,
    },
    external_effects: FALSE_EFFECTS,
    agent_status: AGENT_STATUS,
    claim_boundary: CLAIM_BOUNDARY,
  };
  const observationArtifact = writeCreateOnceFile(
    join(context.run.path, "observation.json"),
    canonicalJsonBytes(observation),
  );
  const observationRef = artifactReference(observationArtifact, context.run.path);
  context.artifacts.push({ role: "observation", ...observationRef });
  const patchEvidencePackage = buildPatchEvidencePackage(
    context,
    assets,
    candidate,
    rollbackSource,
    observationRef,
  );
  const patchEvidenceArtifact = writeCreateOnceFile(
    join(context.run.path, "patch-evidence-package.json"),
    canonicalJsonBytes(patchEvidencePackage),
  );
  const patchEvidenceRef = artifactReference(patchEvidenceArtifact, context.run.path);
  context.artifacts.push({ role: "patch_evidence_package", ...patchEvidenceRef });
  const checksums = Object.fromEntries(
    context.artifacts
      .map((record) => [record.path, record.sha256])
      .sort(([left], [right]) => left.localeCompare(right)),
  );
  const runRecord = {
    schema_version: "1.0",
    run_id: context.runId,
    task_id: CONTROL_ID,
    dataset_version: "1.0.0",
    adapter_id: "B0",
    adapter_version: assets.system.adapter_version,
    environment_snapshot_id: assets.environment.snapshot_id,
    system_configuration_id: assets.system.configuration_id,
    repetition_id: context.repetitionId,
    started_at: startedAt,
    ended_at: endedAt,
    terminal_status: "completed",
    stop_reason_code: "agent_complete",
    invalid_run_reason: null,
    error_taxonomy: [],
    trace_ref: observationRef.path,
    patch_ref: context.patchRef.path,
    test_artifact_refs: context.artifacts
      .filter((record) => record.role === "command_stream" && record.stream === "stdout" && record.action_id.includes("test"))
      .map((record) => record.path),
    verification_ref: null,
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      tool_calls: 0,
      retries: 0,
      human_interventions: 0,
      cost_usd: 0,
      latency_ms: Math.max(0, Math.round(Date.parse(endedAt) - Date.parse(startedAt))),
    },
    policy_violations: [],
    artifact_checksums: checksums,
  };
  validateSchemaValue(
    runRecord,
    join(REPOSITORY_ROOT, "docs/aios/schemas/run-record.schema.json"),
    "RUN_RECORD_REJECTED",
    "RunRecord",
  );
  const runRecordArtifact = writeCreateOnceFile(
    join(context.run.path, "run-record.json"),
    canonicalJsonBytes(runRecord),
  );
  context.artifacts.push({ role: "run_record", ...artifactReference(runRecordArtifact, context.run.path) });
  completeAction(context, "emit_create_once_run_record_and_manifest");
  const manifest = {
    schema_version: 1,
    record_type: context.card.run_evidence_contract.manifest_record_type,
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    candidate_binding: candidate.binding,
    run_root_receipt: context.run,
    artifacts: context.artifacts,
    agent_status: AGENT_STATUS,
  };
  const manifestArtifact = writeCreateOnceFile(join(context.run.path, "manifest.json"), canonicalJsonBytes(manifest));
  for (const record of context.artifacts) {
    safeReadRegular(
      join(context.run.path, record.path),
      record,
      "EVIDENCE_IDENTITY_REJECTED",
      `final artifact ${record.path}`,
    );
  }
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_066_worker_run_receipt",
    task_id: TASK_ID,
    run_id: context.runId,
    repetition_id: context.repetitionId,
    candidate_binding: candidate.binding,
    run_root: context.run.path,
    manifest_path: manifestArtifact.path,
    manifest_byte_length: manifestArtifact.byte_length,
    manifest_sha256: manifestArtifact.sha256,
    agent_status: AGENT_STATUS,
    claim_boundary: CLAIM_BOUNDARY,
  };
}

function performRun(args, options = {}) {
  const telemetry = options.telemetry ?? {
    materialization_creations: 0,
    mutation_attempts: 0,
    child_start_attempts: 0,
  };
  const { card } = validateTaskCard(args.taskCard);
  validateQualityFreeze(card);
  const candidate = validateCandidateManifest(args.candidateManifest, { selfTestRoot: options.selfTestRoot });
  const preflightContext = { card, completedActions: [] };
  completeAction(preflightContext, "validate_candidate_and_quality_identities");
  const assets = validateFrozenAssets(card);
  completeAction(preflightContext, "validate_closed_task_environment_configuration_and_result");
  completeAction(preflightContext, "admit_exact_ir10_through_accepted_compiler");

  const { run } = createRunRoot(args.evidenceRoot, args.runId, { selfTestRoot: options.selfTestRoot });
  telemetry.materialization_creations += 1;
  const context = {
    card,
    candidate,
    run,
    runId: args.runId,
    repetitionId: args.repetitionId,
    telemetry,
    artifacts: [],
    commands: [],
    completedActions: [...preflightContext.completedActions],
  };
  captureCandidateEvidence(context, candidate);
  completeAction(context, "create_fresh_task_owned_run_and_evidence_roots");
  const startedAt = new Date().toISOString();
  let mutated = false;
  let rolledBack = false;
  let pendingError;
  let rollbackSourceRef;
  let rollbackVerification;
  const mutationState = {
    attempted: false,
    rename_completed: false,
    current: "NOT_ATTEMPTED",
  };
  try {
    createMaterialization(context, assets);
    completeAction(context, "materialize_exact_rep001_base");
    const rollbackSource = writeCreateOnceFile(join(context.run.path, "rollback-source.bin"), assets.accepted.source_preimage.bytes);
    rollbackSourceRef = artifactReference(rollbackSource, context.run.path);
    context.artifacts.push({ role: "rollback_source", ...rollbackSourceRef });

    runCommand(context, "materialize_git_init", card.fixed_commands.git_init, 0);
    runCommand(context, "materialize_git_add", card.fixed_commands.git_add, 0);
    runCommand(context, "materialize_git_commit", card.fixed_commands.git_commit, 0);
    const baseHead = runCommand(context, "base_git_head", card.fixed_commands.git_head, 0);
    const baseTree = runCommand(context, "base_git_tree", card.fixed_commands.git_tree, 0);
    const baseStatus = runCommand(context, "base_git_status", card.fixed_commands.git_status, 0);
    assert(trimmedStdout(baseHead) === EXPECTED_BASE.commit, "BASE_IDENTITY_REJECTED", "base commit drifted");
    assert(trimmedStdout(baseTree) === EXPECTED_BASE.tree, "BASE_IDENTITY_REJECTED", "base tree drifted");
    assert(baseStatus.stdout.length === 0, "BASE_IDENTITY_REJECTED", "base materialization is dirty");
    verifyExactFile(
      join(context.materialization.path, "src/range.mjs"),
      card.accepted_inputs.source_preimage,
      "BASE_IDENTITY_REJECTED",
      "base source",
    );
    completeAction(context, "verify_base_commit_tree_clean_state_and_source_preimage");

    const baseIssue = runCommand(context, "base_issue_test", card.fixed_commands.issue_test, 1);
    const baseCombined = commandText(baseIssue);
    for (const token of assets.expectedBaseFailure.required_output_tokens) {
      assert(baseCombined.includes(token), "BASE_FAILURE_REJECTED", `base issue output lacks ${token}`);
    }
    for (const token of assets.expectedBaseFailure.forbidden_output_tokens) {
      assert(!baseCombined.includes(token), "BASE_FAILURE_REJECTED", `base issue output contains ${token}`);
    }
    runCommand(context, "base_regression_test", card.fixed_commands.regression_test, 0);
    completeAction(context, "execute_typed_base_issue_and_regression_tests");

    atomicReplaceOwned(
      join(context.materialization.path, "src/range.mjs"),
      card.accepted_inputs.source_preimage,
      assets.admission.postimage,
      telemetry,
      "POSTIMAGE_MUTATION_REJECTED",
      mutationState,
    );
    mutated = true;
    completeAction(context, "atomically_replace_t0_with_admitted_complete_postimage");
    const changed = runCommand(context, "changed_path_git_status", card.fixed_commands.git_status, 0);
    assert(sameJson(parseGitStatus(changed.stdout), ["src/range.mjs"]), "CHANGED_PATH_SCOPE_REJECTED", "changed path scope drifted");
    completeAction(context, "verify_exact_changed_path_scope");
    const patchCommand = runCommand(context, "patch_git_diff", card.fixed_commands.git_diff, 0);
    assert(patchCommand.stdout.length > 0, "PATCH_EVIDENCE_PACKAGE_REJECTED", "patch diff is empty");
    const patchArtifact = writeCreateOnceFile(join(context.run.path, "patch.diff"), patchCommand.stdout);
    context.patchRef = artifactReference(patchArtifact, context.run.path);
    context.artifacts.push({ role: "patch", ...context.patchRef });
    completeAction(context, "capture_exact_patch_diff_and_hash");
    runCommand(context, "patched_issue_test", card.fixed_commands.issue_test, 0);
    runCommand(context, "patched_regression_test", card.fixed_commands.regression_test, 0);
    completeAction(context, "execute_patched_issue_and_regression_tests");
    completeAction(context, "record_observable_actions_and_raw_stream_identities");
  } catch (error) {
    pendingError = error;
  } finally {
    try {
      const sourcePath = join(context.materialization.path, "src/range.mjs");
      const identityKind = exactIdentityKind(
        sourcePath,
        card.accepted_inputs.source_preimage,
        EXPECTED_POSTIMAGE,
      );
      mutationState.current = identityKind;
      if (identityKind === "POSTIMAGE") {
        const rollbackMutationState = {
          attempted: false,
          rename_completed: false,
          current: "NOT_ATTEMPTED",
        };
        atomicReplaceOwned(
          sourcePath,
          EXPECTED_POSTIMAGE,
          assets.accepted.source_preimage.bytes,
          telemetry,
          "ROLLBACK_REJECTED",
          rollbackMutationState,
        );
        rolledBack = true;
        mutationState.current = "PREIMAGE_RESTORED";
      } else if (identityKind === "PREIMAGE") {
        rolledBack = mutated;
        mutationState.current = mutationState.attempted ? "PREIMAGE_UNCHANGED_OR_ALREADY_RESTORED" : "PREIMAGE_NOT_MUTATED";
      } else {
        fail("ROLLBACK_REJECTED", "materialized source is neither exact preimage nor admitted postimage");
      }
    } catch (error) {
      pendingError = error instanceof RunnerError
        ? error
        : new RunnerError("ROLLBACK_REJECTED", error.message);
    }
  }
  if (pendingError) throw pendingError;
  assert(mutated && rolledBack, "ROLLBACK_REJECTED", "positive run did not mutate and roll back");
  completeAction(context, "restore_exact_base_source");
  verifyExactFile(
    join(context.materialization.path, "src/range.mjs"),
    card.accepted_inputs.source_preimage,
    "ROLLBACK_REJECTED",
    "rolled back source",
  );
  const rollbackHead = runCommand(context, "rollback_git_head", card.fixed_commands.git_head, 0);
  const rollbackTree = runCommand(context, "rollback_git_tree", card.fixed_commands.git_tree, 0);
  const rollbackStatus = runCommand(context, "rollback_git_status", card.fixed_commands.git_status, 0);
  assert(trimmedStdout(rollbackHead) === EXPECTED_BASE.commit, "ROLLBACK_REJECTED", "rollback commit drifted");
  assert(trimmedStdout(rollbackTree) === EXPECTED_BASE.tree, "ROLLBACK_REJECTED", "rollback tree drifted");
  assert(rollbackStatus.stdout.length === 0, "ROLLBACK_REJECTED", "rollback did not restore clean state");
  rollbackVerification = true;
  completeAction(context, "verify_exact_rollback_commit_tree_and_clean_state");
  assert(rollbackVerification && rollbackSourceRef, "ROLLBACK_REJECTED", "rollback Evidence is incomplete");
  const endedAt = new Date().toISOString();
  return emitRunEvidence(context, assets, candidate, startedAt, endedAt, rollbackSourceRef);
}

function decodeProposalForSelfTest(value) {
  const encoded = value?.results?.[0]?.finite_typed_result?.bytes_base64;
  return typeof encoded === "string" ? Buffer.from(encoded, "base64") : Buffer.alloc(0);
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function firstJsonDifference(left, right, path = "$") {
  if (Object.is(left, right)) return null;
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right)) return { path, left, right };
    if (left.length !== right.length) return { path: `${path}.length`, left: left.length, right: right.length };
    for (let index = 0; index < left.length; index += 1) {
      const difference = firstJsonDifference(left[index], right[index], `${path}[${index}]`);
      if (difference) return difference;
    }
    return null;
  }
  if (left !== null && right !== null && typeof left === "object" && typeof right === "object") {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    if (!sameJson(leftKeys, rightKeys)) return { path: `${path}.__keys`, left: leftKeys, right: rightKeys };
    for (const key of leftKeys) {
      const difference = firstJsonDifference(left[key], right[key], `${path}.${key}`);
      if (difference) return difference;
    }
    return null;
  }
  return { path, left, right };
}

function controlledReason(action) {
  try {
    action();
  } catch (error) {
    if (
      error instanceof RunnerError ||
      error instanceof OfflineB0AdapterError ||
      (error !== null && typeof error === "object" && typeof error.code === "string")
    ) {
      return error.code;
    }
    throw error;
  }
  return null;
}

function rewriteRunForBindingCase(runRoot, mutateObservation) {
  const manifestPath = join(runRoot, "manifest.json");
  const observationPath = join(runRoot, "observation.json");
  const runRecordPath = join(runRoot, "run-record.json");
  const manifest = parseJsonBytes(readFileSync(manifestPath), "SELF_TEST_FAILED", "case manifest");
  const observation = parseJsonBytes(readFileSync(observationPath), "SELF_TEST_FAILED", "case observation");
  const runRecord = parseJsonBytes(readFileSync(runRecordPath), "SELF_TEST_FAILED", "case RunRecord");
  mutateObservation(observation);
  const observationBytes = canonicalJsonBytes(observation);
  writeFileSync(observationPath, observationBytes);
  const observationRecord = manifest.artifacts.find((record) => record.role === "observation");
  Object.assign(observationRecord, identityOf(observationBytes));
  runRecord.artifact_checksums[observationRecord.path] = observationRecord.sha256;
  const runRecordBytes = canonicalJsonBytes(runRecord);
  writeFileSync(runRecordPath, runRecordBytes);
  const runRecordRecord = manifest.artifacts.find((record) => record.role === "run_record");
  Object.assign(runRecordRecord, identityOf(runRecordBytes));
  writeFileSync(manifestPath, canonicalJsonBytes(manifest));
}

function verifySelfTestRoot(root, receipt, markerPath, markerBytes) {
  const current = assertRealDirectory(root, "SELF_TEST_CLEANUP_REFUSED", "self-test root");
  assert(current.device === receipt.device && current.inode === receipt.inode, "SELF_TEST_CLEANUP_REFUSED", "self-test root identity changed");
  safeReadRegular(markerPath, identityOf(markerBytes), "SELF_TEST_CLEANUP_REFUSED", "self-test ownership marker");
}

async function performSelfTest() {
  const temporary = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-066-worker-"));
  chmodSync(temporary, 0o700);
  const rootReceipt = assertRealDirectory(resolve(temporary), "SELF_TEST_FAILED", "self-test root");
  const markerBytes = Buffer.from(`P1-066:${randomBytes(24).toString("hex")}\n`, "utf8");
  const markerPath = join(temporary, ".owned-self-test");
  writeCreateOnceFile(markerPath, markerBytes);
  let pendingError;
  let result;
  try {
    const candidateValue = currentCandidateManifestValue();
    const candidatePath = join(temporary, "candidate.json");
    writeCreateOnceFile(candidatePath, canonicalJsonBytes(candidateValue));
    const evidenceRoot = join(temporary, "positive");
    createExclusiveDirectory(evidenceRoot);
    const baseArgs = {
      taskCard: TASK_CARD_PATH,
      candidateManifest: candidatePath,
      evidenceRoot,
    };
    const runA = performRun({ ...baseArgs, runId: "self-run-a", repetitionId: 1 }, { selfTestRoot: temporary });
    const runB = performRun({ ...baseArgs, runId: "self-run-b", repetitionId: 2 }, { selfTestRoot: temporary });
    const oracle = await import("../../evaluator/offline-b0-complete-evidence-v1/quality-oracle.mjs");
    const evaluatedA = oracle.evaluateRunEvidence(runA.manifest_path);
    const evaluatedB = oracle.evaluateRunEvidence(runB.manifest_path);
    const firstStableDifference = firstJsonDifference(evaluatedA.stable_projection, evaluatedB.stable_projection);
    assert(
      firstStableDifference === null,
      "SELF_TEST_FAILED",
      `stable projection first difference ${JSON.stringify(firstStableDifference)}`,
    );
    const comparison = oracle.compareStableRuns(evaluatedA, evaluatedB);

    const positiveBytes = safeReadRegular(
      join(FIXTURE_ROOT, "positive-result.json"),
      { byte_length: 2993, sha256: "a141b29b8c35a0a48265f48507dc8c85d5c1d32840e00eb064b5ac0a7e4d0e86" },
      "SELF_TEST_FAILED",
      "positive result",
    ).bytes;
    const positive = parseJsonBytes(positiveBytes, "SELF_TEST_FAILED", "positive result");
    const negative = parseJsonBytes(
      safeReadRegular(
        join(FIXTURE_ROOT, "negative-cases.json"),
        { byte_length: 4762, sha256: "8682d743f1b26eb6cb8ca33bd763d66a60f686e06ca59b638747d8d4ec2e7342" },
        "SELF_TEST_FAILED",
        "negative matrix",
      ).bytes,
      "SELF_TEST_FAILED",
      "negative matrix",
    );
    const preAdmissionCases = new Map();
    const admissionCase = (mutate) => () => {
      const value = cloneJson(positive);
      mutate(value);
      const bytes = canonicalJsonBytes(value);
      admitOfflineB0Result(bytes, decodeProposalForSelfTest(value));
    };
    preAdmissionCases.set("environment-identity-mismatch", admissionCase((value) => {
      value.environment_binding.sha256 = "0".repeat(64);
    }));
    preAdmissionCases.set("system-configuration-mismatch", admissionCase((value) => {
      value.system_configuration_binding.configuration_id = "MISMATCH";
    }));
    preAdmissionCases.set("duplicate-result", admissionCase((value) => {
      value.results.push(cloneJson(value.results[0]));
    }));
    preAdmissionCases.set("missing-result", admissionCase((value) => {
      value.results = [];
    }));
    preAdmissionCases.set("unknown-member", admissionCase((value) => {
      value.results[0].response.unexpected = true;
    }));
    preAdmissionCases.set("malformed-schema", admissionCase((value) => {
      value.results = "not-an-array";
    }));
    preAdmissionCases.set("input-identity-drift", admissionCase((value) => {
      value.results[0].finite_typed_result.byte_length = 254;
    }));
    preAdmissionCases.set("unsupported-ir", admissionCase((value) => {
      value.results[0].finite_typed_result.bytes_base64 = "e30=";
      value.results[0].finite_typed_result.byte_length = 2;
      value.results[0].finite_typed_result.sha256 = "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a";
    }));
    preAdmissionCases.set("forbidden-external-effect-request", admissionCase((value) => {
      value.results[0].requested_external_effects.network = true;
    }));
    preAdmissionCases.set("input-path-escape", () => {
      containedPath(temporary, "../escape", "INPUT_PATH_ESCAPE_REJECTED");
    });
    preAdmissionCases.set("input-directory-as-file", () => {
      const path = join(temporary, "negative-input-directory");
      createExclusiveDirectory(path);
      safeReadRegular(path, undefined, "INPUT_IDENTITY_REJECTED", "input directory", { typeCode: "INPUT_TYPE_REJECTED" });
    });
    preAdmissionCases.set("input-symlink", () => {
      const target = join(temporary, "negative-input-target");
      writeCreateOnceFile(target, Buffer.from("target\n"));
      const link = join(temporary, "negative-input-link");
      symlinkSync(target, link);
      safeReadRegular(link, undefined, "INPUT_IDENTITY_REJECTED", "input symlink", { symlinkCode: "INPUT_SYMLINK_REJECTED" });
    });

    const negativeResults = [];
    for (const declaration of negative.cases.filter((entry) => entry.stage === "PRE_ADMISSION")) {
      const telemetry = { materialization_creations: 0, mutation_attempts: 0, child_start_attempts: 0 };
      const canaryBytes = Buffer.from(`${declaration.id}:unchanged\n`, "utf8");
      const canaryPath = join(temporary, `canary-${declaration.id}`);
      writeCreateOnceFile(canaryPath, canaryBytes);
      const action = preAdmissionCases.get(declaration.id);
      assert(typeof action === "function", "SELF_TEST_FAILED", `missing negative case ${declaration.id}`);
      const observed = controlledReason(action);
      assert(observed === declaration.expected_reason_code, "SELF_TEST_FAILED", `${declaration.id} expected ${declaration.expected_reason_code}, got ${observed}`);
      assert(
        telemetry.materialization_creations === 0 && telemetry.mutation_attempts === 0 && telemetry.child_start_attempts === 0,
        "SELF_TEST_FAILED",
        `${declaration.id} crossed pre-admission side-effect boundary`,
      );
      safeReadRegular(canaryPath, identityOf(canaryBytes), "SELF_TEST_FAILED", `${declaration.id} canary`);
      negativeResults.push({ id: declaration.id, reason_code: observed, admitted: false, ...telemetry });
    }

    const postRoot = join(temporary, "post-run-cases");
    createExclusiveDirectory(postRoot);
    const postArgs = { ...baseArgs, evidenceRoot: postRoot };
    const cross = performRun({ ...postArgs, runId: "post-cross", repetitionId: 3 }, { selfTestRoot: temporary });
    rewriteRunForBindingCase(cross.run_root, (observation) => {
      observation.run_id = "self-run-a";
    });
    let observed = controlledReason(() => oracle.evaluateRunEvidence(cross.manifest_path));
    assert(observed === "RUN_BINDING_REJECTED", "SELF_TEST_FAILED", `cross-run expected RUN_BINDING_REJECTED, got ${observed}`);
    negativeResults.push({ id: "cross-run-substitution", reason_code: observed, admitted: false });

    const tamper = performRun({ ...postArgs, runId: "post-tamper", repetitionId: 4 }, { selfTestRoot: temporary });
    writeFileSync(join(tamper.run_root, "observation.json"), Buffer.from("tampered\n", "utf8"), { flag: "a" });
    observed = controlledReason(() => oracle.evaluateRunEvidence(tamper.manifest_path));
    assert(observed === "EVIDENCE_IDENTITY_REJECTED", "SELF_TEST_FAILED", `tamper expected EVIDENCE_IDENTITY_REJECTED, got ${observed}`);
    negativeResults.push({ id: "evidence-tamper", reason_code: observed, admitted: false });

    const noRollback = performRun({ ...postArgs, runId: "post-no-rollback", repetitionId: 5 }, { selfTestRoot: temporary });
    rewriteRunForBindingCase(noRollback.run_root, (observation) => {
      observation.rollback = null;
    });
    observed = controlledReason(() => oracle.evaluateRunEvidence(noRollback.manifest_path));
    assert(observed === "ROLLBACK_EVIDENCE_MISSING", "SELF_TEST_FAILED", `rollback omission expected ROLLBACK_EVIDENCE_MISSING, got ${observed}`);
    negativeResults.push({ id: "rollback-omission", reason_code: observed, admitted: false });

    assert(negativeResults.length === 15, "SELF_TEST_FAILED", "negative case population drifted");
    assert(new Set(negativeResults.map((entry) => entry.id)).size === 15, "SELF_TEST_FAILED", "negative case IDs are not unique");
    safeReadRegular(runA.manifest_path, undefined, "SELF_TEST_FAILED", "original Run A manifest");
    safeReadRegular(runB.manifest_path, undefined, "SELF_TEST_FAILED", "original Run B manifest");
    result = {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_066_worker_self_test",
      task_id: TASK_ID,
      adapter_version: ADAPTER_VERSION,
      actual_positive_runs: 2,
      independent_quality_evaluations: 2,
      stable_projection_exact_byte_equal: comparison.stable_projection_exact_byte_equal,
      negative_case_count: negativeResults.length,
      pre_admission_case_count: negativeResults.filter((entry) => Object.hasOwn(entry, "child_start_attempts")).length,
      post_run_case_count: 3,
      negative_case_outcomes: negativeResults,
      false_accepts: 0,
      pre_admission_materialization_creations: 0,
      pre_admission_mutation_attempts: 0,
      pre_admission_child_start_attempts: 0,
      original_positive_evidence_unchanged: true,
      external_effects: FALSE_EFFECTS,
      agent_status: AGENT_STATUS,
      verdict: "PASS",
      claim_boundary: CLAIM_BOUNDARY,
    };
  } catch (error) {
    pendingError = error;
  }
  try {
    verifySelfTestRoot(temporary, rootReceipt, markerPath, markerBytes);
    rmSync(temporary, { recursive: true, force: false });
  } catch (error) {
    if (!pendingError) pendingError = error;
  }
  if (pendingError) throw pendingError;
  return result;
}

function parseCli(argv) {
  const mode = argv[0];
  assert(mode === "run" || mode === "self-test", "CLI_REJECTED", "mode must be run or self-test");
  const values = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    assert(flag?.startsWith("--") && value !== undefined && !values.has(flag), "CLI_REJECTED", "invalid CLI flags");
    values.set(flag, value);
  }
  if (mode === "self-test") {
    assert(values.size === 0 || (values.size === 1 && values.has("--output")), "CLI_REJECTED", "self-test flag set mismatch");
    if (values.has("--output")) {
      const output = resolve(values.get("--output"));
      const root = assertRealDirectory(AUTHORIZED_EVIDENCE_ROOT, "CLI_REJECTED", "authorized Evidence root");
      assert(pathIsWithin(root.path, output), "CLI_REJECTED", "self-test output escaped authorized Evidence root");
      return { mode, output };
    }
    return { mode };
  }
  const allowed = new Set(["--task-card", "--candidate-manifest", "--evidence-root", "--run-id", "--repetition-id"]);
  assert(values.size === allowed.size && [...values.keys()].every((key) => allowed.has(key)), "CLI_REJECTED", "run flag set mismatch");
  for (const flag of allowed) assert(values.has(flag), "CLI_REJECTED", `missing ${flag}`);
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
    record_type: "sourcelens_aios_p1_066_worker_error",
    task_id: TASK_ID,
    reason_code: error instanceof RunnerError || error instanceof OfflineB0AdapterError ? error.code : "UNEXPECTED_ERROR",
    message: error instanceof Error ? error.message : String(error),
    agent_status: "NON_PASS",
  };
}

try {
  const args = parseCli(process.argv.slice(2));
  const result = args.mode === "self-test" ? await performSelfTest() : performRun(args);
  const bytes = canonicalJsonBytes(result);
  if (args.output) writeCreateOnceFile(args.output, bytes);
  process.stdout.write(bytes);
} catch (error) {
  process.stderr.write(canonicalJsonBytes(publicError(error)));
  process.exitCode = 2;
}

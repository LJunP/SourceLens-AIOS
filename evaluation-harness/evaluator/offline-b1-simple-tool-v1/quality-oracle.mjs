import { createHash } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import {
  closeSync,
  constants as fsConstants,
  fstatSync,
  linkSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, normalize, relative, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

import { compileFiniteTypedPatchIr } from "../../harness/finite-typed-patch-ir-v1/compiler.mjs";

export const QUALITY_ORACLE_VERSION = "P1-067-OFFLINE-B1-QUALITY-ORACLE/2";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(MODULE_DIR, "../../..");
const FIXTURE_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/fixtures/offline-b1-simple-tool-v1");
const DATASET_TASK_ROOT = join(REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION");
const CLAIM = "ONE_VISIBLE_SYNTHETIC_REP_001_COOPERATIVE_LOCAL_OFFLINE_B1_FINITE_TYPED_SIMPLE_TOOL_COMPATIBILITY_ADAPTER_COMPLETE_EVIDENCE_OBSERVATION_ONLY_NO_LIVE_MODEL_EMPIRICAL_BASELINE_VTSR_P1_EXIT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM";
const TASK_ID = "AIOS-P1-067_OFFLINE_B1_SIMPLE_TOOL_COMPATIBILITY_ADAPTER_VERTICAL_SLICE";
const CONTROL_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const BASE_COMMIT = "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f";
const BASE_TREE = "900814727113d65f5dad8b63222e14f39b2cf38b";
const PREIMAGE_SHA256 = "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75";
const POSTIMAGE_SHA256 = "e8304b77da9b8c33f64ecdc568db7e97297ace72ecb796971bb3f5eda09d9001";
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const REQUIRED_STEPS = Object.freeze([
  Object.freeze({ ordinal: 1, tool_id: "local-file-edit", operation_id: "apply-finite-typed-patch-ir" }),
  Object.freeze({ ordinal: 2, tool_id: "local-node-test", operation_id: "issue-test" }),
  Object.freeze({ ordinal: 3, tool_id: "local-node-test", operation_id: "regression-test" }),
]);
const ISSUE_ARGV = Object.freeze(["/usr/local/bin/node", "--test", "test/issue.test.mjs"]);
const REGRESSION_ARGV = Object.freeze(["/usr/local/bin/node", "--test", "test/regression.test.mjs"]);
const COMMAND_DEFINITIONS = Object.freeze([
  Object.freeze({
    action_id: "base_issue_test",
    phase: "BASE_PRECONDITION",
    tool_ordinal: null,
    argv: ISSUE_ARGV,
    exit_status: 1,
    stdout_path: "base-issue.stdout",
    stderr_path: "base-issue.stderr",
  }),
  Object.freeze({
    action_id: "base_regression_test",
    phase: "BASE_PRECONDITION",
    tool_ordinal: null,
    argv: REGRESSION_ARGV,
    exit_status: 0,
    stdout_path: "base-regression.stdout",
    stderr_path: "base-regression.stderr",
  }),
  Object.freeze({
    action_id: "tool_issue_test",
    phase: "TOOL_ACTION",
    tool_ordinal: 2,
    argv: ISSUE_ARGV,
    exit_status: 0,
    stdout_path: "tool-issue.stdout",
    stderr_path: "tool-issue.stderr",
  }),
  Object.freeze({
    action_id: "tool_regression_test",
    phase: "TOOL_ACTION",
    tool_ordinal: 3,
    argv: REGRESSION_ARGV,
    exit_status: 0,
    stdout_path: "tool-regression.stdout",
    stderr_path: "tool-regression.stderr",
  }),
]);
const REQUIRED_ARTIFACT_LAYOUT = Object.freeze([
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
  ...COMMAND_DEFINITIONS.flatMap((command) => [
    Object.freeze({ role: "raw_stream", path: command.stdout_path }),
    Object.freeze({ role: "raw_stream", path: command.stderr_path }),
  ]),
]);
const TEST_ARTIFACT_REFS = Object.freeze(COMMAND_DEFINITIONS.map((command) => command.stdout_path));
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
const DYNAMIC_FIELDS = new Set([
  "path", "argv", "cwd", "env", "executable", "module", "timeout",
  "code", "shell", "diff", "ast", "payload", "parameters",
]);
const IDENTITIES = Object.freeze({
  task_card: Object.freeze({ byte_length: 17440, sha256: "f3bfcdecc1c2a9905fbcf404cccd627bdcf77b092e0f2a66b1b3f005c08b3af3" }),
  target_runtime: Object.freeze({ byte_length: 1688, sha256: "482afa2abc0367224b783b5d065a676354e5cff9fb19c8bd7022970ff7dd02c6" }),
  environment_snapshot: Object.freeze({ byte_length: 2087, sha256: "333d30e7a7c960570bec5b409710e4dfba68aa6a46c51c396df5bc248726f149" }),
  system_configuration: Object.freeze({ byte_length: 1108, sha256: "8e7333d5acd3f6ac84d595c91fef3a053f2722e46ac09f4beb54fafe7965e5e9" }),
  compatibility_profile: Object.freeze({ byte_length: 4454, sha256: "6a4f462eab6b46bfc0d675dd902f09b57cf5b8c541e9ef07caadc0675e8ae6b8" }),
  positive_tool_plan: Object.freeze({ byte_length: 1583, sha256: "8752ffa0a5325c7dcd72697ceeaf878f2b6fbadb8fb44890d215e7b1d85f1b0f" }),
  negative_cases: Object.freeze({ byte_length: 8704, sha256: "01b88bff780869b5f403348333cdfdd93b889b082eacfa8456efb2ef26fbbd06" }),
  ir10: Object.freeze({ byte_length: 255, sha256: "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc" }),
});
const FILES = Object.freeze({
  task_card: join(FIXTURE_ROOT, "task-card.json"),
  target_runtime: join(FIXTURE_ROOT, "target-runtime-oci-manifest.json"),
  environment_snapshot: join(FIXTURE_ROOT, "environment-snapshot.json"),
  system_configuration: join(FIXTURE_ROOT, "system-configuration.json"),
  compatibility_profile: join(FIXTURE_ROOT, "compatibility-profile.json"),
  positive_tool_plan: join(FIXTURE_ROOT, "positive-tool-plan.json"),
  negative_cases: join(FIXTURE_ROOT, "negative-cases.json"),
  ir10: join(REPOSITORY_ROOT, "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json"),
});
const MATERIALIZATION_INPUTS = Object.freeze({
  source: Object.freeze({
    path: join(DATASET_TASK_ROOT, "source-template/src/range.mjs"),
    identity: Object.freeze({ byte_length: 115, sha256: PREIMAGE_SHA256 }),
  }),
  issue: Object.freeze({
    path: join(DATASET_TASK_ROOT, "source-template/test/issue.test.mjs"),
    identity: Object.freeze({ byte_length: 237, sha256: "51fd472f8cf85fd595246814db29699ab81ccdc2986d80666d8609a8c4972b4b" }),
  }),
  regression: Object.freeze({
    path: join(DATASET_TASK_ROOT, "source-template/test/regression.test.mjs"),
    identity: Object.freeze({ byte_length: 241, sha256: "381c573d8f99305b47db9f1a2ca49779842fe1187b9d7c5b7410e56dda9240c5" }),
  }),
});
const AUTHORIZED_EVIDENCE_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-067-offline-b1-7jPPTE1B";
const QUALITY_FREEZE_PATH =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-067-offline-b1-7jPPTE1B/quality/QUALITY_FREEZE_MANIFEST.json";
const QUALITY_EVIDENCE_DIRECTORY = dirname(QUALITY_FREEZE_PATH);
const NODE_PATH = "/usr/local/bin/node";
const GIT_PATH = "/usr/bin/git";
const NODE_IDENTITY = Object.freeze({
  byte_length: 193_262_272,
  sha256: "c5548e7a991a5c90170a29843ffc46df4643e29141f3cbb035f60295cf2bc882",
});
const GIT_IDENTITY = Object.freeze({
  byte_length: 118_848,
  sha256: "29d5080bd197feb8245ee7d9a275fee4750b5496c6a7016090eff5a357c1e8c4",
});
const FIXED_PROCESS_ENV = Object.freeze({
  PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
  LANG: "C",
  LC_ALL: "C",
  TZ: "UTC",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_OPTIONAL_LOCKS: "0",
});
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const QUALITY_ORACLE_RELATIVE_PATH =
  "evaluation-harness/evaluator/offline-b1-simple-tool-v1/quality-oracle.mjs";
const EXECUTING_MODULE_PATHS = Object.freeze({
  adapter: "evaluation-harness/adapters/offline-b1-finite-tool-v1/adapter.mjs",
  quality_oracle: QUALITY_ORACLE_RELATIVE_PATH,
  runner: "evaluation-harness/harness/offline-b1-complete-evidence-v1/run.mjs",
  task_card: "evaluation-harness/fixtures/offline-b1-simple-tool-v1/task-card.json",
});

export class QualityOracleError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "QualityOracleError";
    this.code = code;
  }
}

const fail = (code, message) => { throw new QualityOracleError(code, message); };
const assert = (condition, code, message) => { if (!condition) fail(code, message); };
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const clone = (value) => JSON.parse(JSON.stringify(value));
const canonicalize = (value) => {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
};

export const canonicalJsonBytes = (value) => Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");

function exactKeys(value, expected, code, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), code, `${label} is not an object`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  assert(JSON.stringify(actual) === JSON.stringify(wanted), code, `${label} key set drifted`);
}

function sameJson(left, right) {
  return JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right));
}

function parseJson(bytes, code, label, canonicalRequired = false) {
  assert(Buffer.isBuffer(bytes), code, `${label} is not a Buffer`);
  assert(bytes.length > 0 && bytes.length <= 65_536, code, `${label} length is invalid`);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail(code, `${label} is not exact UTF-8`);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail(code, `${label} is not valid JSON`);
  }
  if (canonicalRequired) {
    assert(canonicalJsonBytes(value).equals(bytes), "PLAN_CANONICAL_JSON_REJECTED", `${label} is not canonical JSON`);
  }
  return value;
}

function readExact(path, identity, label) {
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1, "QUALITY_ASSET_DRIFT", `${label} type drifted`);
  const bytes = readFileSync(path);
  assert(bytes.length === identity.byte_length && sha256(bytes) === identity.sha256, "QUALITY_ASSET_DRIFT", `${label} identity drifted`);
  return { bytes, value: parseJson(bytes, "QUALITY_ASSET_DRIFT", label) };
}

export function validateTaskCard() {
  const card = readExact(FILES.task_card, IDENTITIES.task_card, "task card").value;
  assert(card.task_id === TASK_ID && card.control_id === CONTROL_ID && card.claim_boundary === CLAIM,
    "QUALITY_ASSET_DRIFT", "task card identity drifted");
  assert(card.run_evidence_contract.retained_materialization_rechecked_at_evaluation === true &&
    card.run_evidence_contract.patch_evidence_package_required === true &&
    card.run_evidence_contract.actual_executor_per_run_required === true &&
    card.run_evidence_contract.patch_evidence_package_record_type ===
      "sourcelens_aios_p1_067_patch_evidence_package" &&
    card.run_evidence_contract.actual_executor_record_type ===
      "sourcelens_aios_p1_067_actual_executor_evidence" &&
    card.run_evidence_contract.action_trace_record_type ===
      "sourcelens_aios_p1_067_complete_action_trace" &&
    card.run_evidence_contract.action_trace_required_action_ids.length === 32 &&
    card.quality_evaluator_interface.version === QUALITY_ORACLE_VERSION &&
    card.child_process_failure_contract.worker_runner_self_test_must_execute_actual_failure_paths === true &&
    card.child_process_failure_contract.oracle_process_group_control_self_test_is_not_worker_proof === true,
  "QUALITY_ASSET_DRIFT", "task card physical verification boundary drifted");
  return card;
}

function validateFalseEffects(value, code) {
  exactKeys(value, Object.keys(FALSE_EFFECTS), code, "external effects");
  assert(sameJson(value, FALSE_EFFECTS), code, "external effects are not all false");
}

function validatePlanValue(plan) {
  exactKeys(plan, [
    "schema_version", "record_type", "plan_id", "provenance", "task_binding",
    "configuration_binding", "compatibility_profile_binding", "requested_external_effects",
    "steps", "claim_boundary",
  ], "PLAN_UNKNOWN_MEMBER_REJECTED", "plan");
  assert(plan.schema_version === 1 && plan.record_type === "sourcelens_aios_offline_b1_finite_typed_tool_plan" &&
    plan.plan_id === "P1-067-REP001-IR10-THREE-STEP-PLAN" && plan.claim_boundary === CLAIM,
  "PLAN_SCHEMA_REJECTED", "plan identity drifted");
  exactKeys(plan.provenance, ["kind", "live_model_invoked", "model_performance_sample", "provider_invoked"], "PLAN_UNKNOWN_MEMBER_REJECTED", "provenance");
  assert(plan.provenance.kind === "QUALITY_FROZEN_COOPERATIVE_LOCAL_FIXTURE" &&
    plan.provenance.live_model_invoked === false && plan.provenance.model_performance_sample === false &&
    plan.provenance.provider_invoked === false, "PLAN_PROVENANCE_REJECTED", "plan provenance drifted");
  exactKeys(plan.task_binding, ["base_commit", "base_tree", "dataset_version", "task_id", "task_spec_byte_length", "task_spec_sha256"], "PLAN_UNKNOWN_MEMBER_REJECTED", "task binding");
  assert(plan.task_binding.task_id === CONTROL_ID && plan.task_binding.dataset_version === "1.0.0" &&
    plan.task_binding.base_commit === BASE_COMMIT && plan.task_binding.base_tree === BASE_TREE &&
    plan.task_binding.task_spec_byte_length === 2960 &&
    plan.task_binding.task_spec_sha256 === "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
  "PLAN_IDENTITY_REJECTED", "task binding drifted");
  exactKeys(plan.configuration_binding, ["byte_length", "configuration_id", "sha256"], "PLAN_UNKNOWN_MEMBER_REJECTED", "configuration binding");
  assert(plan.configuration_binding.configuration_id === "P1-067-B1-OFFLINE-FINITE-TOOL-1" &&
    plan.configuration_binding.byte_length === IDENTITIES.system_configuration.byte_length &&
    plan.configuration_binding.sha256 === IDENTITIES.system_configuration.sha256,
  "PLAN_IDENTITY_REJECTED", "configuration binding drifted");
  exactKeys(plan.compatibility_profile_binding, ["byte_length", "profile_id", "sha256"], "PLAN_UNKNOWN_MEMBER_REJECTED", "profile binding");
  assert(plan.compatibility_profile_binding.profile_id === "P1-067-B1-REP001-FINITE-TOOL-COMPATIBILITY/1" &&
    plan.compatibility_profile_binding.byte_length === IDENTITIES.compatibility_profile.byte_length &&
    plan.compatibility_profile_binding.sha256 === IDENTITIES.compatibility_profile.sha256,
  "PLAN_IDENTITY_REJECTED", "profile binding drifted");
  validateFalseEffects(plan.requested_external_effects, "EXTERNAL_EFFECT_REQUEST_REJECTED");
  assert(Array.isArray(plan.steps) && plan.steps.length === 3, "PLAN_BUDGET_REJECTED", "plan must contain exactly three steps");
  for (let index = 0; index < plan.steps.length; index += 1) {
    const step = plan.steps[index];
    assert(step !== null && typeof step === "object" && !Array.isArray(step), "PLAN_SCHEMA_REJECTED", "step is not an object");
    const dynamic = Object.keys(step).find((key) => DYNAMIC_FIELDS.has(key));
    if (dynamic) fail("DYNAMIC_PARAMETER_REJECTED", `step contains dynamic field ${dynamic}`);
    exactKeys(step, ["ordinal", "tool_id", "operation_id"], "PLAN_UNKNOWN_MEMBER_REJECTED", "step");
    assert(step.ordinal === index + 1, "PLAN_ORDER_REJECTED", "step ordinal/order drifted");
    assert(step.tool_id === REQUIRED_STEPS[index].tool_id && step.operation_id === REQUIRED_STEPS[index].operation_id,
      "PLAN_TOOL_REJECTED", "step tool mapping drifted");
  }
  return plan;
}

export function validatePlanBytes(bytes) {
  const plan = parseJson(bytes, "PLAN_SCHEMA_REJECTED", "tool plan", true);
  return validatePlanValue(plan);
}

export const validateFiniteToolPlan = validatePlanBytes;

export function validateQualityAssets(overrides = {}) {
  const assets = {};
  for (const name of Object.keys(IDENTITIES)) {
    const source = overrides[name];
    if (source !== undefined) {
      assets[name] = { bytes: canonicalJsonBytes(source), value: source };
    } else {
      assets[name] = readExact(FILES[name], IDENTITIES[name], name);
    }
  }
  const card = assets.task_card.value;
  const environment = assets.environment_snapshot.value;
  const system = assets.system_configuration.value;
  const profile = assets.compatibility_profile.value;
  assert(card.task_id === TASK_ID && card.control_id === CONTROL_ID && card.claim_boundary === CLAIM,
    "QUALITY_ASSET_DRIFT", "task card identity drifted");
  assert(system.adapter_id === "B1" && system.loop_limit === 3 &&
    sameJson(system.enabled_tools, ["local-file-edit", "local-node-test"]),
  "QUALITY_ASSET_DRIFT", "system configuration drifted");
  assert(environment.network.policy === "none" && environment.network.allowed_hosts.length === 0 &&
    sameJson(environment.tools.map((tool) => tool.tool_id), ["local-file-edit", "local-node-test"]) &&
    environment.tools[0].permission === "modify_isolated" && environment.tools[1].permission === "execute_isolated",
  "QUALITY_ASSET_DRIFT", "environment tool boundary drifted");
  assert(profile.compiler_binding.only_program_id === "IR10" &&
    profile.compiler_binding.program_byte_length === IDENTITIES.ir10.byte_length &&
    profile.compiler_binding.program_sha256 === IDENTITIES.ir10.sha256,
  "QUALITY_ASSET_DRIFT", "compiler/program binding drifted");
  validateFalseEffects(card.external_effects, "QUALITY_ASSET_DRIFT");
  const plan = validatePlanBytes(assets.positive_tool_plan.bytes);
  const compiled = compileFiniteTypedPatchIr(assets.ir10.bytes);
  assert(compiled.status === "COMPILED" && compiled.program_id === "IR10" &&
    compiled.outcome_id === "CORRECT_END_START" && compiled.kind === "COMPLETE_POSTIMAGE" &&
    Buffer.isBuffer(compiled.postimage) && compiled.postimage.length === 127 && sha256(compiled.postimage) === POSTIMAGE_SHA256,
  "QUALITY_ASSET_DRIFT", "accepted compiler output drifted");
  return { card, environment, system, profile, plan, compiled };
}

function safeRelativePath(value) {
  return typeof value === "string" && value.length > 0 && !isAbsolute(value) &&
    normalize(value) === value && value !== "." && value !== ".." && !value.startsWith("../");
}

function validatePhysical(value, label) {
  exactKeys(value, ["path", "regular", "symlink", "nlink", "preexisting", "tampered"], "EVIDENCE_IDENTITY_REJECTED", label);
  assert(safeRelativePath(value.path), "EVIDENCE_PATH_ESCAPE_REJECTED", `${label} path escaped`);
  assert(value.regular === true && value.symlink === false && value.nlink === 1,
    "EVIDENCE_IDENTITY_REJECTED", `${label} physical identity drifted`);
  assert(value.preexisting === false, "PREEXISTING_EVIDENCE_REJECTED", `${label} was pre-existing`);
  assert(value.tampered === false, "EVIDENCE_IDENTITY_REJECTED", `${label} was tampered`);
}

function contained(realRoot, candidate) {
  const rel = relative(realRoot, candidate);
  return rel !== "" && rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel);
}

function readNoFollowRegular(path, identity, code, label) {
  const before = lstatSync(path);
  assert(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && before.uid === process.getuid(),
    code, `${label} is not an owned single-link regular file`);
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  } catch {
    fail(code, `${label} cannot be opened without following links`);
  }
  try {
    const during = fstatSync(descriptor);
    assert(during.isFile() && during.nlink === 1 && during.uid === process.getuid() &&
      during.dev === before.dev && during.ino === before.ino, code, `${label} identity changed during open`);
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    assert(after.dev === during.dev && after.ino === during.ino && after.nlink === 1,
      code, `${label} identity changed during read`);
    if (identity) {
      assert(bytes.length === identity.byte_length && sha256(bytes) === identity.sha256,
        code, `${label} length or hash drifted`);
    }
    return {
      bytes,
      physical: {
        path: identity?.path ?? path.split("/").at(-1),
        regular: true,
        symlink: false,
        nlink: 1,
        preexisting: false,
        tampered: false,
      },
    };
  } finally {
    closeSync(descriptor);
  }
}

function validateFixedExecutable(path, identity, code, label) {
  const before = lstatSync(path);
  assert(before.isFile() && !before.isSymbolicLink() && before.uid === 0 && before.nlink >= 1,
    code, `${label} is not the frozen system regular file`);
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  } catch {
    fail(code, `${label} cannot be opened without following links`);
  }
  try {
    const during = fstatSync(descriptor);
    assert(during.isFile() && during.uid === 0 && during.nlink >= 1 &&
      during.dev === before.dev && during.ino === before.ino,
    code, `${label} identity changed during open`);
    const bytes = readFileSync(descriptor);
    assert(bytes.length === identity.byte_length && sha256(bytes) === identity.sha256,
      code, `${label} length or hash drifted`);
  } finally {
    closeSync(descriptor);
  }
}

function executableObservation(path, identity, version) {
  validateFixedExecutable(path, identity, "EXECUTOR_EVIDENCE_REJECTED", `${path} executable`);
  const stat = lstatSync(path);
  return {
    path,
    realpath: realpathSync(path),
    version,
    byte_length: identity.byte_length,
    sha256: identity.sha256,
    regular: stat.isFile(),
    symlink: stat.isSymbolicLink(),
    nlink: stat.nlink,
  };
}

function actualExecutorObservation() {
  assert(process.execPath === NODE_PATH && realpathSync(process.execPath) === realpathSync(NODE_PATH),
    "EXECUTOR_EVIDENCE_REJECTED", "oracle is not executing with the frozen Node executable");
  const gitVersion = runFixedGit(REPOSITORY_ROOT, ["--version"],
    "EXECUTOR_EVIDENCE_REJECTED", "actual Git version").toString("utf8").trim();
  return {
    executor_kind: "LOCAL_HOST_PROCESS",
    platform: process.platform,
    architecture: process.arch,
    node: executableObservation(NODE_PATH, NODE_IDENTITY, process.version),
    git: executableObservation(GIT_PATH, GIT_IDENTITY, gitVersion),
    container_runtime_observed: false,
    declared_target_materialized: false,
    external_effects: { ...FALSE_EFFECTS },
  };
}

function validateActualExecutor(value, runId) {
  exactKeys(value, [
    "schema_version", "record_type", "run_id", "executor_kind", "platform", "architecture",
    "node", "git", "container_runtime_observed", "declared_target_materialized", "external_effects",
  ], "EXECUTOR_EVIDENCE_REJECTED", "actual executor artifact");
  assert(value.schema_version === 1 &&
    value.record_type === "sourcelens_aios_p1_067_actual_executor_evidence" &&
    value.run_id === runId,
  "EXECUTOR_EVIDENCE_REJECTED", "actual executor artifact identity drifted");
  const observed = actualExecutorObservation();
  assert(value.executor_kind === observed.executor_kind && value.platform === observed.platform &&
    value.architecture === observed.architecture && sameJson(value.node, observed.node) &&
    sameJson(value.git, observed.git) && value.container_runtime_observed === false &&
    value.declared_target_materialized === false,
  "EXECUTOR_EVIDENCE_REJECTED", "per-run actual executor identity drifted");
  validateFalseEffects(value.external_effects, "EXECUTOR_EVIDENCE_REJECTED");
  return canonicalize({
    executor_kind: value.executor_kind,
    platform: value.platform,
    architecture: value.architecture,
    node: value.node,
    git: value.git,
    container_runtime_observed: value.container_runtime_observed,
    declared_target_materialized: value.declared_target_materialized,
    external_effects: value.external_effects,
  });
}

function runFixedGit(cwd, args, code, label, environment = {}) {
  validateFixedExecutable(GIT_PATH, GIT_IDENTITY, code, "fixed git executable");
  const outcome = spawnSync(GIT_PATH, args, {
    cwd,
    shell: false,
    encoding: null,
    timeout: 10_000,
    maxBuffer: 1_048_576,
    windowsHide: true,
    env: { ...FIXED_PROCESS_ENV, HOME: "/var/empty", ...environment },
  });
  assert(!outcome.error && outcome.status === 0 && outcome.signal === null,
    code, `${label} failed`);
  assert(Buffer.isBuffer(outcome.stderr) && outcome.stderr.length === 0,
    code, `${label} emitted stderr`);
  return Buffer.isBuffer(outcome.stdout) ? outcome.stdout : Buffer.alloc(0);
}

function validateMaterializationReceipt(runRoot, receipt) {
  exactKeys(receipt, ["realpath", "device", "inode", "uid", "created_exclusive"],
    "MATERIALIZATION_ROOT_REJECTED", "materialization receipt");
  const expectedPath = join(runRoot, "materialization");
  const stat = lstatSync(expectedPath);
  assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === process.getuid(),
    "MATERIALIZATION_ROOT_REJECTED", "materialization is not an owned real directory");
  const real = realpathSync(expectedPath);
  assert(contained(runRoot, real) && receipt.realpath === real && receipt.device === stat.dev &&
    receipt.inode === stat.ino && receipt.uid === stat.uid && receipt.created_exclusive === true,
  "MATERIALIZATION_ROOT_REJECTED", "materialization receipt drifted");
  return { path: expectedPath, realpath: real, stat };
}

function validateRetainedMaterialization(runRoot, receipt) {
  const materialization = validateMaterializationReceipt(runRoot, receipt);
  for (const directoryName of [".git", "src", "test"]) {
    const directoryPath = join(materialization.path, directoryName);
    const directoryStat = lstatSync(directoryPath);
    assert(directoryStat.isDirectory() && !directoryStat.isSymbolicLink() &&
      directoryStat.uid === process.getuid() && contained(materialization.realpath, realpathSync(directoryPath)),
    "MATERIALIZATION_ROOT_REJECTED", `${directoryName} is not an owned contained directory`);
  }
  readNoFollowRegular(join(materialization.path, "src/range.mjs"), {
    path: "src/range.mjs",
    byte_length: 115,
    sha256: PREIMAGE_SHA256,
  }, "ROLLBACK_EVIDENCE_REJECTED", "retained restored source");
  const head = runFixedGit(materialization.path, ["rev-parse", "HEAD"],
    "ROLLBACK_EVIDENCE_REJECTED", "retained materialization HEAD").toString("utf8").trim();
  const tree = runFixedGit(materialization.path, ["rev-parse", "HEAD^{tree}"],
    "ROLLBACK_EVIDENCE_REJECTED", "retained materialization tree").toString("utf8").trim();
  const status = runFixedGit(materialization.path,
    ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
    "ROLLBACK_EVIDENCE_REJECTED", "retained materialization status");
  assert(head === BASE_COMMIT && tree === BASE_TREE && status.length === 0,
    "ROLLBACK_EVIDENCE_REJECTED", "retained materialization is not exact clean base");
  return {
    receipt: clone(receipt),
    head,
    tree,
    clean: true,
    source_sha256: PREIMAGE_SHA256,
  };
}

function validateRunRecord(record, runId, repetitionId, artifactsByPath) {
  const required = [
    "schema_version", "run_id", "task_id", "dataset_version", "adapter_id", "adapter_version",
    "environment_snapshot_id", "system_configuration_id", "repetition_id", "started_at", "ended_at",
    "terminal_status", "stop_reason_code", "invalid_run_reason", "error_taxonomy", "trace_ref",
    "patch_ref", "test_artifact_refs", "verification_ref", "usage", "policy_violations", "artifact_checksums",
  ];
  exactKeys(record, required, "RUN_RECORD_EVIDENCE_REJECTED", "RunRecord");
  assert(record.schema_version === "1.0" && record.run_id === runId && record.task_id === CONTROL_ID &&
    record.dataset_version === "1.0.0" && record.adapter_id === "B1" &&
    record.adapter_version === "OFFLINE-B1-FINITE-TOOL-ADAPTER/1" &&
    record.environment_snapshot_id === "ENV-SOURCELENS-P1-REP-NODE20-STDLIB-1" &&
    record.system_configuration_id === "P1-067-B1-OFFLINE-FINITE-TOOL-1" && record.repetition_id === repetitionId &&
    record.terminal_status === "completed" && record.stop_reason_code === "agent_complete" &&
    record.invalid_run_reason === null && record.verification_ref === null &&
    typeof record.started_at === "string" && typeof record.ended_at === "string" &&
    Array.isArray(record.error_taxonomy) && record.error_taxonomy.length === 0 &&
    Array.isArray(record.policy_violations) && record.policy_violations.length === 0 &&
    record.trace_ref === "command-stream.json" && record.patch_ref === "patch.diff" &&
    sameJson(record.test_artifact_refs, TEST_ARTIFACT_REFS),
  "RUN_RECORD_EVIDENCE_REJECTED", "RunRecord semantics drifted");
  exactKeys(record.usage, ["input_tokens", "output_tokens", "tool_calls", "retries", "human_interventions", "cost_usd", "latency_ms"],
    "RUN_RECORD_EVIDENCE_REJECTED", "RunRecord usage");
  assert(record.usage.input_tokens === 0 && record.usage.output_tokens === 0 && record.usage.tool_calls === 3 &&
    record.usage.retries === 0 && record.usage.human_interventions === 0 && record.usage.cost_usd === 0 &&
    Number.isInteger(record.usage.latency_ms) && record.usage.latency_ms >= 0,
  "RUN_RECORD_EVIDENCE_REJECTED", "RunRecord usage drifted");
  const expectedChecksums = Object.fromEntries(
    [...artifactsByPath.entries()]
      .filter(([path]) => path !== "run-record.json")
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([path, artifact]) => [path, artifact.entry.sha256]),
  );
  exactKeys(record.artifact_checksums, Object.keys(expectedChecksums),
    "RUN_RECORD_EVIDENCE_REJECTED", "RunRecord artifact checksums");
  assert(sameJson(record.artifact_checksums, expectedChecksums),
    "RUN_RECORD_EVIDENCE_REJECTED", "RunRecord artifact checksum join drifted");
}

function decodeUtf8(bytes, code, label) {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail(code, `${label} is not exact UTF-8`);
  }
}

function decodeExactStream(value, label, artifactsByPath = undefined, expectedArtifactPath = undefined) {
  exactKeys(value, ["retention", "encoding", "bytes_base64", "byte_length", "sha256", "artifact_ref"],
    "ACTION_TRACE_REJECTED", `${label} exact stream`);
  assert(value.retention === "INLINE_EXACT_BYTES" && value.encoding === "base64" &&
    typeof value.bytes_base64 === "string" &&
    /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value.bytes_base64) &&
    Number.isInteger(value.byte_length) && value.byte_length >= 0 && /^[0-9a-f]{64}$/.test(value.sha256),
  "ACTION_TRACE_REJECTED", `${label} exact stream identity is malformed`);
  const bytes = Buffer.from(value.bytes_base64, "base64");
  assert(bytes.toString("base64") === value.bytes_base64 && bytes.length === value.byte_length &&
    sha256(bytes) === value.sha256,
  "ACTION_TRACE_REJECTED", `${label} exact stream bytes do not match their identity`);
  if (expectedArtifactPath === undefined) {
    assert(value.artifact_ref === null, "ACTION_TRACE_REJECTED",
      `${label} unexpectedly claims a separate raw-stream artifact`);
  } else {
    exactKeys(value.artifact_ref, ["path", "byte_length", "sha256"],
      "ACTION_TRACE_REJECTED", `${label} raw-stream artifact reference`);
    const artifact = artifactsByPath?.get(expectedArtifactPath);
    assert(value.artifact_ref.path === expectedArtifactPath && artifact?.entry.role === "raw_stream" &&
      value.artifact_ref.byte_length === artifact.entry.byte_length &&
      value.artifact_ref.sha256 === artifact.entry.sha256 && artifact.bytes.equals(bytes),
    "ACTION_TRACE_REJECTED", `${label} raw-stream artifact join drifted`);
  }
  return bytes;
}

function validatePatchEvidence(bytes) {
  assert(Buffer.isBuffer(bytes) && bytes.length > 0, "PATCH_EVIDENCE_REJECTED", "patch artifact is empty");
  assert(bytes.equals(PATCH_BYTES), "PATCH_EVIDENCE_REJECTED", "patch is not the frozen IR10 preimage-to-postimage diff");
  const text = decodeUtf8(bytes, "PATCH_EVIDENCE_REJECTED", "patch artifact");
  const headers = [...text.matchAll(/^diff --git a\/([^\s]+) b\/([^\s]+)$/gm)];
  assert(headers.length === 1 && headers[0][1] === "src/range.mjs" && headers[0][2] === "src/range.mjs" &&
    text.includes("\n--- a/src/range.mjs\n") && text.includes("\n+++ b/src/range.mjs\n"),
  "PATCH_EVIDENCE_REJECTED", "patch changed-path identity drifted");
  return ["src/range.mjs"];
}

function validateStreamReference(reference, expectedPath, artifactsByPath, label) {
  exactKeys(reference, ["path", "byte_length", "sha256"], "COMMAND_STREAM_EVIDENCE_REJECTED", label);
  assert(reference.path === expectedPath, "COMMAND_STREAM_EVIDENCE_REJECTED", `${label} path drifted`);
  const artifact = artifactsByPath.get(reference.path);
  assert(artifact?.entry.role === "raw_stream" &&
    reference.byte_length === artifact.entry.byte_length && reference.sha256 === artifact.entry.sha256,
  "COMMAND_STREAM_EVIDENCE_REJECTED", `${label} artifact join drifted`);
  return artifact.bytes;
}

function validateCommandStream(commandStream, runId, artifactsByPath) {
  exactKeys(commandStream, ["schema_version", "record_type", "run_id", "commands"],
    "COMMAND_STREAM_EVIDENCE_REJECTED", "command stream");
  assert(commandStream.schema_version === 1 &&
    commandStream.record_type === "sourcelens_aios_p1_067_command_stream_index" &&
    commandStream.run_id === runId && Array.isArray(commandStream.commands) &&
    commandStream.commands.length === COMMAND_DEFINITIONS.length,
  "RUN_BINDING_REJECTED", "command stream binding drifted");
  const decoded = [];
  commandStream.commands.forEach((command, index) => {
    const expected = COMMAND_DEFINITIONS[index];
    exactKeys(command, [
      "action_id", "phase", "tool_ordinal", "argv", "cwd_ref", "timeout_ms",
      "exit_status", "signal", "terminated", "descendants_alive", "stdout", "stderr",
    ], "COMMAND_STREAM_EVIDENCE_REJECTED", `command ${index + 1}`);
    assert(command.action_id === expected.action_id && command.phase === expected.phase &&
      command.tool_ordinal === expected.tool_ordinal && sameJson(command.argv, expected.argv) &&
      command.cwd_ref === "TASK_REPOSITORY" && command.timeout_ms === 10_000 &&
      command.exit_status === expected.exit_status && command.signal === null,
    "COMMAND_STREAM_EVIDENCE_REJECTED", `command ${index + 1} semantics drifted`);
    assert(command.terminated === true && command.descendants_alive === false,
      "CHILD_TERMINATION_EVIDENCE_REJECTED", `command ${index + 1} termination is not proven`);
    const stdout = validateStreamReference(command.stdout, expected.stdout_path, artifactsByPath, `command ${index + 1} stdout`);
    const stderr = validateStreamReference(command.stderr, expected.stderr_path, artifactsByPath, `command ${index + 1} stderr`);
    decoded.push({ command, stdout, stderr });
  });
  const baseIssueText = `${decodeUtf8(decoded[0].stdout, "TEST_EVIDENCE_REJECTED", "base issue stdout")}\n${decodeUtf8(decoded[0].stderr, "TEST_EVIDENCE_REJECTED", "base issue stderr")}`;
  assert(baseIssueText.includes("not ok") && baseIssueText.includes("REP001_NEGATIVE_RANGE_ORDER") &&
    !/(SyntaxError|ERR_MODULE_NOT_FOUND|MODULE_NOT_FOUND|ENOENT|timeout|signal)/.test(baseIssueText),
  "TEST_EVIDENCE_REJECTED", "base issue failure is not the frozen typed failure");
  const successExpectations = [
    [decoded[1], "ordered ranges remain unchanged", "base regression"],
    [decoded[2], "REP001_NEGATIVE_RANGE_ORDER", "patched issue"],
    [decoded[3], "ordered ranges remain unchanged", "patched regression"],
  ];
  for (const [entry, testName, label] of successExpectations) {
    const combined = `${decodeUtf8(entry.stdout, "TEST_EVIDENCE_REJECTED", `${label} stdout`)}\n${decodeUtf8(entry.stderr, "TEST_EVIDENCE_REJECTED", `${label} stderr`)}`;
    assert(combined.includes("ok") && combined.includes(testName) && !combined.includes("not ok") &&
      !/(SyntaxError|ERR_MODULE_NOT_FOUND|MODULE_NOT_FOUND|ENOENT|timeout|signal)/.test(combined),
    "TEST_EVIDENCE_REJECTED", `${label} output is not a frozen successful test result`);
  }
  return {
    tool_actions: [
      { ...REQUIRED_STEPS[0], exit_status: 0, terminated: true },
      { ...REQUIRED_STEPS[1], exit_status: decoded[2].command.exit_status, terminated: decoded[2].command.terminated },
      { ...REQUIRED_STEPS[2], exit_status: decoded[3].command.exit_status, terminated: decoded[3].command.terminated },
    ],
    tests: {
      base_issue: "EXPECTED_FAIL",
      base_regression: "PASS",
      patched_issue: "PASS",
      patched_regression: "PASS",
    },
    child_process: { failure_kind: null, terminated: true, descendants_alive: false },
  };
}

function artifactReference(artifact) {
  return {
    path: artifact.entry.path,
    byte_length: artifact.entry.byte_length,
    sha256: artifact.entry.sha256,
  };
}

function fileIdentityReference(path, identity) {
  return { path, byte_length: identity.byte_length, sha256: identity.sha256 };
}

function currentExecutingModuleIdentities() {
  return Object.fromEntries(Object.entries(EXECUTING_MODULE_PATHS).map(([role, relativePath]) => {
    const absolute = join(REPOSITORY_ROOT, relativePath);
    const file = readNoFollowRegular(absolute, undefined,
      "ACTION_TRACE_REJECTED", `executing ${role} module`);
    return [role, { path: relativePath, byte_length: file.bytes.length, sha256: sha256(file.bytes) }];
  }));
}

function validateQualityFreezeReference(reference, qualityFreezeRoot = QUALITY_EVIDENCE_DIRECTORY) {
  exactKeys(reference, ["path", "byte_length", "sha256"],
    "QUALITY_FREEZE_REJECTED", "Quality Freeze reference");
  assert(isAbsolute(reference.path) && Number.isInteger(reference.byte_length) && reference.byte_length > 0 &&
    /^[0-9a-f]{64}$/.test(reference.sha256),
  "QUALITY_FREEZE_REJECTED", "Quality Freeze reference is malformed");
  const root = realpathSync(qualityFreezeRoot);
  const absolute = resolve(reference.path);
  assert(contained(root, absolute), "QUALITY_FREEZE_REJECTED", "Quality Freeze escaped its exact root");
  const file = readNoFollowRegular(absolute, reference,
    "QUALITY_FREEZE_REJECTED", "corrected Quality Freeze");
  const freeze = parseJson(file.bytes, "QUALITY_FREEZE_REJECTED", "corrected Quality Freeze", true);
  assert(freeze.schema_version === 1 &&
    freeze.record_type === "sourcelens_aios_p1_067_quality_freeze_manifest" &&
    freeze.task_id === TASK_ID && freeze.status === "QUALITY_FREEZE_COMPLETE" &&
    freeze.target_verdict === "PASS" && Array.isArray(freeze.quality_files),
  "QUALITY_FREEZE_REJECTED", "Quality Freeze status or identity drifted");
  const modules = currentExecutingModuleIdentities();
  const expected = {
    target_runtime: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/target-runtime-oci-manifest.json",
      IDENTITIES.target_runtime),
    environment_snapshot: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/environment-snapshot.json",
      IDENTITIES.environment_snapshot),
    system_configuration: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/system-configuration.json",
      IDENTITIES.system_configuration),
    compatibility_profile: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/compatibility-profile.json",
      IDENTITIES.compatibility_profile),
    positive_tool_plan: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/positive-tool-plan.json",
      IDENTITIES.positive_tool_plan),
    negative_cases: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/negative-cases.json",
      IDENTITIES.negative_cases),
    task_card: fileIdentityReference(EXECUTING_MODULE_PATHS.task_card, IDENTITIES.task_card),
    quality_oracle: modules.quality_oracle,
  };
  assert(freeze.quality_files.length === Object.keys(expected).length,
    "QUALITY_FREEZE_REJECTED", "Quality Freeze file population drifted");
  const observed = Object.fromEntries(freeze.quality_files.map((entry) => {
    exactKeys(entry, ["role", "path", "byte_length", "sha256"],
      "QUALITY_FREEZE_REJECTED", "Quality Freeze file entry");
    assert(expected[entry.role] !== undefined, "QUALITY_FREEZE_REJECTED", "unknown Quality Freeze role");
    return [entry.role, { path: entry.path, byte_length: entry.byte_length, sha256: entry.sha256 }];
  }));
  assert(sameJson(observed, expected) && freeze.self_test?.target_verdict === "PASS" &&
    freeze.self_test?.false_accepts === 0 && freeze.worker_boundary?.worker_runner_failure_path_self_test_required === true,
  "QUALITY_FREEZE_REJECTED", "Quality Freeze does not bind the corrected exact Quality bytes");
  return reference;
}

function validateDirectoryReceiptValue(value, label, expected = undefined) {
  exactKeys(value, ["realpath", "device", "inode", "uid", "created_exclusive"],
    "ACTION_TRACE_REJECTED", label);
  assert(isAbsolute(value.realpath) && Number.isInteger(value.device) && Number.isInteger(value.inode) &&
    Number.isInteger(value.uid) && value.created_exclusive === true,
  "ACTION_TRACE_REJECTED", `${label} is malformed`);
  if (expected !== undefined) {
    assert(sameJson(value, expected), "ACTION_TRACE_REJECTED", `${label} does not join its manifest receipt`);
  }
}

function validateCreatedFileReceiptValue(value, label, expectedIdentity = undefined) {
  exactKeys(value, [
    "path_ref", "byte_length", "sha256", "device", "inode", "uid", "regular", "symlink",
    "nlink", "created_exclusive",
  ], "ACTION_TRACE_REJECTED", label);
  assert(safeRelativePath(value.path_ref) && Number.isInteger(value.byte_length) && value.byte_length >= 0 &&
    /^[0-9a-f]{64}$/.test(value.sha256) && Number.isInteger(value.device) && Number.isInteger(value.inode) &&
    Number.isInteger(value.uid) && value.regular === true && value.symlink === false && value.nlink === 1 &&
    value.created_exclusive === true,
  "ACTION_TRACE_REJECTED", `${label} is malformed`);
  if (expectedIdentity !== undefined) {
    assert(value.byte_length === expectedIdentity.byte_length && value.sha256 === expectedIdentity.sha256,
      "ACTION_TRACE_REJECTED", `${label} content identity drifted`);
  }
}

function validateTemporaryReceiptValue(value, label) {
  exactKeys(value, ["device", "inode", "uid", "regular", "symlink", "nlink", "created_exclusive"],
    "ACTION_TRACE_REJECTED", label);
  assert(Number.isInteger(value.device) && Number.isInteger(value.inode) && Number.isInteger(value.uid) &&
    value.regular === true && value.symlink === false && value.nlink === 1 && value.created_exclusive === true,
  "ACTION_TRACE_REJECTED", `${label} is malformed`);
}

function validateProcessTraceAction(action, manifest, artifactsByPath, candidateRepository = REPOSITORY_ROOT) {
  exactKeys(action.request, [
    "executable", "argv", "cwd_ref", "timeout_ms", "environment_profile", "shell",
  ], "ACTION_TRACE_REJECTED", `${action.action_id} request`);
  exactKeys(action.outcome, [
    "status", "expected_exit_status", "exit_status", "signal", "terminated", "descendants_alive",
    "stdout", "stderr",
  ], "ACTION_TRACE_REJECTED", `${action.action_id} outcome`);
  assert(action.category === "PROCESS" && action.request.environment_profile === "FIXED_MINIMAL_NON_SECRET" &&
    action.request.shell === false && action.outcome.status === "COMPLETED" &&
    action.outcome.signal === null && action.outcome.terminated === true &&
    action.outcome.descendants_alive === false &&
    action.outcome.exit_status === action.outcome.expected_exit_status,
  "ACTION_TRACE_REJECTED", `${action.action_id} process boundary drifted`);

  const processDefinitions = {
    candidate_git_head: {
      phase: "CANDIDATE_PREFLIGHT", ordinal: null, cwd: "CANDIDATE_REPOSITORY", timeout: 15_000,
      argv: [GIT_PATH, "-C", candidateRepository, "rev-parse", "HEAD"], exit: 0,
      stdout: Buffer.from(`${manifest.candidate_binding.commit}\n`, "utf8"), stderr: Buffer.alloc(0),
    },
    candidate_git_tree: {
      phase: "CANDIDATE_PREFLIGHT", ordinal: null, cwd: "CANDIDATE_REPOSITORY", timeout: 15_000,
      argv: [GIT_PATH, "-C", candidateRepository, "rev-parse", "HEAD^{tree}"], exit: 0,
      stdout: Buffer.from(`${manifest.candidate_binding.tree}\n`, "utf8"), stderr: Buffer.alloc(0),
    },
    candidate_git_status: {
      phase: "CANDIDATE_PREFLIGHT", ordinal: null, cwd: "CANDIDATE_REPOSITORY", timeout: 15_000,
      argv: [GIT_PATH, "-C", candidateRepository, "status", "--porcelain=v1", "-z", "--untracked-files=all"],
      exit: 0, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0),
    },
    actual_git_version: {
      phase: "EXECUTOR_EVIDENCE", ordinal: null, cwd: "CANDIDATE_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "--version"], exit: 0,
      stdout: Buffer.from("git version 2.39.5 (Apple Git-154)\n", "utf8"), stderr: Buffer.alloc(0),
    },
    materialize_git_init: {
      phase: "MATERIALIZATION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "init", "--quiet", "--initial-branch=main"], exit: 0,
      stdout: Buffer.alloc(0), stderr: Buffer.alloc(0),
    },
    materialize_git_add: {
      phase: "MATERIALIZATION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "add", "--", "src/range.mjs", "test/issue.test.mjs", "test/regression.test.mjs"],
      exit: 0, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0),
    },
    materialize_git_commit: {
      phase: "MATERIALIZATION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "commit", "--quiet", "--no-gpg-sign", "-m", "fixture: base"], exit: 0,
      stdout: Buffer.alloc(0), stderr: Buffer.alloc(0),
    },
    base_git_head: {
      phase: "BASE_PRECONDITION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "rev-parse", "HEAD"], exit: 0,
      stdout: Buffer.from(`${BASE_COMMIT}\n`, "utf8"), stderr: Buffer.alloc(0),
    },
    base_git_tree: {
      phase: "BASE_PRECONDITION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "rev-parse", "HEAD^{tree}"], exit: 0,
      stdout: Buffer.from(`${BASE_TREE}\n`, "utf8"), stderr: Buffer.alloc(0),
    },
    base_git_status: {
      phase: "BASE_PRECONDITION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "status", "--porcelain=v1", "-z", "--untracked-files=all"], exit: 0,
      stdout: Buffer.alloc(0), stderr: Buffer.alloc(0),
    },
    base_issue_test: {
      phase: "BASE_PRECONDITION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [...ISSUE_ARGV], exit: 1, artifact_stdout: "base-issue.stdout", artifact_stderr: "base-issue.stderr",
    },
    base_regression_test: {
      phase: "BASE_PRECONDITION", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [...REGRESSION_ARGV], exit: 0,
      artifact_stdout: "base-regression.stdout", artifact_stderr: "base-regression.stderr",
    },
    changed_path_git_status: {
      phase: "PATCH_EVIDENCE", ordinal: 1, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "status", "--porcelain=v1", "-z", "--untracked-files=all"], exit: 0,
      stdout: Buffer.from(" M src/range.mjs\0", "utf8"), stderr: Buffer.alloc(0),
    },
    patch_git_diff: {
      phase: "PATCH_EVIDENCE", ordinal: 1, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "diff", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "--", "src/range.mjs"],
      exit: 0, stdout: PATCH_BYTES, stderr: Buffer.alloc(0),
    },
    tool_issue_test: {
      phase: "TOOL_ACTION", ordinal: 2, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [...ISSUE_ARGV], exit: 0, artifact_stdout: "tool-issue.stdout", artifact_stderr: "tool-issue.stderr",
    },
    tool_regression_test: {
      phase: "TOOL_ACTION", ordinal: 3, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [...REGRESSION_ARGV], exit: 0,
      artifact_stdout: "tool-regression.stdout", artifact_stderr: "tool-regression.stderr",
    },
    rollback_git_head: {
      phase: "ROLLBACK", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "rev-parse", "HEAD"], exit: 0,
      stdout: Buffer.from(`${BASE_COMMIT}\n`, "utf8"), stderr: Buffer.alloc(0),
    },
    rollback_git_tree: {
      phase: "ROLLBACK", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "rev-parse", "HEAD^{tree}"], exit: 0,
      stdout: Buffer.from(`${BASE_TREE}\n`, "utf8"), stderr: Buffer.alloc(0),
    },
    rollback_git_status: {
      phase: "ROLLBACK", ordinal: null, cwd: "TASK_REPOSITORY", timeout: 10_000,
      argv: [GIT_PATH, "status", "--porcelain=v1", "-z", "--untracked-files=all"], exit: 0,
      stdout: Buffer.alloc(0), stderr: Buffer.alloc(0),
    },
  };
  const expected = processDefinitions[action.action_id];
  assert(expected !== undefined && action.phase === expected.phase && action.tool_ordinal === expected.ordinal &&
    action.request.executable === expected.argv[0] && sameJson(action.request.argv, expected.argv) &&
    action.request.cwd_ref === expected.cwd && action.request.timeout_ms === expected.timeout &&
    action.outcome.expected_exit_status === expected.exit && action.outcome.exit_status === expected.exit,
  "ACTION_TRACE_REJECTED", `${action.action_id} process request/outcome drifted`);
  const stdout = decodeExactStream(action.outcome.stdout, `${action.action_id} stdout`, artifactsByPath,
    expected.artifact_stdout);
  const stderr = decodeExactStream(action.outcome.stderr, `${action.action_id} stderr`, artifactsByPath,
    expected.artifact_stderr);
  if (expected.stdout !== undefined) {
    assert(stdout.equals(expected.stdout), "ACTION_TRACE_REJECTED", `${action.action_id} stdout drifted`);
  }
  if (expected.stderr !== undefined) {
    assert(stderr.equals(expected.stderr), "ACTION_TRACE_REJECTED", `${action.action_id} stderr drifted`);
  }
  return { stdout, stderr };
}

const PROCESS_ACTION_IDS = new Set([
  "candidate_git_head", "candidate_git_tree", "candidate_git_status", "actual_git_version",
  "materialize_git_init", "materialize_git_add", "materialize_git_commit",
  "base_git_head", "base_git_tree", "base_git_status", "base_issue_test", "base_regression_test",
  "changed_path_git_status", "patch_git_diff", "tool_issue_test", "tool_regression_test",
  "rollback_git_head", "rollback_git_tree", "rollback_git_status",
]);

function validateCandidateRepository(candidateRepository, manifest, allowedRoot, explicitOverride) {
  assert(typeof candidateRepository === "string" && isAbsolute(candidateRepository),
    "CANDIDATE_BINDING_REJECTED", "candidate repository path is invalid");
  const real = realpathSync(candidateRepository);
  const stat = lstatSync(candidateRepository);
  assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === process.getuid(),
    "CANDIDATE_BINDING_REJECTED", "candidate repository is not an owned real directory");
  if (explicitOverride) {
    assert(contained(allowedRoot, real), "CANDIDATE_BINDING_REJECTED",
      "self-test candidate repository escaped the allowed root");
  } else {
    assert(real === realpathSync(REPOSITORY_ROOT), "CANDIDATE_BINDING_REJECTED",
      "formal candidate repository is not the canonical Task worktree");
  }
  const head = runFixedGit(real, ["rev-parse", "HEAD"],
    "CANDIDATE_BINDING_REJECTED", "candidate repository HEAD").toString("utf8").trim();
  const tree = runFixedGit(real, ["rev-parse", "HEAD^{tree}"],
    "CANDIDATE_BINDING_REJECTED", "candidate repository tree").toString("utf8").trim();
  const status = runFixedGit(real, ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
    "CANDIDATE_BINDING_REJECTED", "candidate repository status");
  assert(head === manifest.candidate_binding.commit && tree === manifest.candidate_binding.tree &&
    status.length === 0,
  "CANDIDATE_BINDING_REJECTED", "candidate repository is not the exact clean candidate");
  return real;
}

function validateNonProcessTraceActions(byId, manifest, artifactsByPath, card, qualityFreezeRoot) {
  const expectMeta = (id, category, phase, ordinal) => {
    const action = byId.get(id);
    assert(action !== undefined && action.category === category && action.phase === phase &&
      action.tool_ordinal === ordinal,
    "ACTION_TRACE_REJECTED", `${id} metadata drifted`);
    return action;
  };
  const identityAction = expectMeta("validate_quality_and_input_identities",
    "IDENTITY_VALIDATION", "FROZEN_INPUT_VALIDATION", null);
  exactKeys(identityAction.request,
    ["task_card", "quality_freeze", "quality_assets", "accepted_inputs", "executing_modules"],
    "ACTION_TRACE_REJECTED", "frozen identity request");
  const expectedQualityAssets = Object.fromEntries([
    ["target_runtime", "target-runtime-oci-manifest.json"],
    ["environment_snapshot", "environment-snapshot.json"],
    ["system_configuration", "system-configuration.json"],
    ["compatibility_profile", "compatibility-profile.json"],
    ["positive_tool_plan", "positive-tool-plan.json"],
    ["negative_cases", "negative-cases.json"],
  ].map(([name, filename]) => [name, fileIdentityReference(
    `evaluation-harness/fixtures/offline-b1-simple-tool-v1/${filename}`, IDENTITIES[name])]));
  const expectedAcceptedInputs = Object.fromEntries(Object.entries(card.accepted_inputs)
    .filter(([, record]) => record && typeof record.path === "string" &&
      Number.isInteger(record.byte_length) && /^[0-9a-f]{64}$/.test(record.sha256))
    .map(([name, record]) => [name, fileIdentityReference(record.path, record)]));
  assert(sameJson(identityAction.request.task_card,
    fileIdentityReference(EXECUTING_MODULE_PATHS.task_card, IDENTITIES.task_card)) &&
    sameJson(identityAction.request.quality_assets, expectedQualityAssets) &&
    sameJson(identityAction.request.accepted_inputs, expectedAcceptedInputs) &&
    sameJson(identityAction.request.executing_modules, currentExecutingModuleIdentities()),
  "ACTION_TRACE_REJECTED", "frozen identity validation inputs drifted");
  validateQualityFreezeReference(identityAction.request.quality_freeze, qualityFreezeRoot);
  exactKeys(identityAction.outcome, [
    "status", "all_regular", "all_non_symlink", "ownership_enforced", "hardlink_policy_enforced",
  ], "ACTION_TRACE_REJECTED", "frozen identity outcome");
  assert(sameJson(identityAction.outcome, {
    status: "VALIDATED_EXACT_IDENTITIES", all_regular: true, all_non_symlink: true,
    ownership_enforced: true, hardlink_policy_enforced: true,
  }), "ACTION_TRACE_REJECTED", "frozen identity validation outcome drifted");

  const admission = expectMeta("validate_closed_tool_plan_and_adapter_admission",
    "PLAN_ADMISSION", "PRE_ADMISSION", null);
  exactKeys(admission.request, ["tool_plan", "ir10", "adapter", "task_spec"],
    "ACTION_TRACE_REJECTED", "plan admission request");
  const executingModules = currentExecutingModuleIdentities();
  assert(sameJson(admission.request, {
    tool_plan: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/positive-tool-plan.json",
      IDENTITIES.positive_tool_plan),
    ir10: fileIdentityReference(
      "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json", IDENTITIES.ir10),
    adapter: executingModules.adapter,
    task_spec: fileIdentityReference(card.accepted_inputs.task_spec.path, card.accepted_inputs.task_spec),
  }), "ACTION_TRACE_REJECTED", "plan admission inputs drifted");
  exactKeys(admission.outcome,
    ["status", "admitted_action_count", "admitted_actions", "postimage", "external_effects"],
    "ACTION_TRACE_REJECTED", "plan admission outcome");
  assert(admission.outcome.status === "ADMITTED_CLOSED_FINITE_TOOL_PLAN" &&
    admission.outcome.admitted_action_count === 3 && sameJson(admission.outcome.admitted_actions, REQUIRED_STEPS) &&
    sameJson(admission.outcome.postimage, { byte_length: 127, sha256: POSTIMAGE_SHA256 }),
  "ACTION_TRACE_REJECTED", "plan admission outcome drifted");
  validateFalseEffects(admission.outcome.external_effects, "ACTION_TRACE_REJECTED");

  const runRoot = expectMeta("create_exclusive_run_root", "DIRECTORY_CREATION", "EVIDENCE_INITIALIZATION", null);
  exactKeys(runRoot.request, ["parent_ref", "run_id", "creation_policy"],
    "ACTION_TRACE_REJECTED", "run-root request");
  exactKeys(runRoot.outcome, ["status", "receipt"], "ACTION_TRACE_REJECTED", "run-root outcome");
  assert(sameJson(runRoot.request, {
    parent_ref: "EVIDENCE_ROOT", run_id: manifest.run_id,
    creation_policy: "EXCLUSIVE_NOFOLLOW_OWNED_DIRECTORY",
  }) && runRoot.outcome.status === "CREATED_EXCLUSIVE",
  "ACTION_TRACE_REJECTED", "run-root action drifted");
  validateDirectoryReceiptValue(runRoot.outcome.receipt, "run-root action receipt", manifest.run_root_receipt);

  const materialization = expectMeta("create_exclusive_materialization_root",
    "DIRECTORY_CREATION", "MATERIALIZATION", null);
  exactKeys(materialization.request, ["parent_ref", "required_children"],
    "ACTION_TRACE_REJECTED", "materialization request");
  exactKeys(materialization.outcome, [
    "status", "materialization_receipt", "home_receipt", "source_directory_receipt", "test_directory_receipt",
  ], "ACTION_TRACE_REJECTED", "materialization outcome");
  assert(sameJson(materialization.request, {
    parent_ref: "RUN_ROOT",
    required_children: ["materialization", "home", "materialization/src", "materialization/test"],
  }) && materialization.outcome.status === "CREATED_EXCLUSIVE",
  "ACTION_TRACE_REJECTED", "materialization action drifted");
  validateDirectoryReceiptValue(materialization.outcome.materialization_receipt,
    "materialization action receipt", manifest.materialization_receipt);
  for (const key of ["home_receipt", "source_directory_receipt", "test_directory_receipt"]) {
    validateDirectoryReceiptValue(materialization.outcome[key], `${key} action receipt`);
  }

  const sourceInputs = expectMeta("materialize_source_inputs", "FILE_CREATION", "MATERIALIZATION", null);
  exactKeys(sourceInputs.request, ["source_count", "sources"], "ACTION_TRACE_REJECTED", "source-input request");
  exactKeys(sourceInputs.outcome, ["status", "files"], "ACTION_TRACE_REJECTED", "source-input outcome");
  const expectedSources = [
    { name: "source_preimage", path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/src/range.mjs", byte_length: 115, sha256: PREIMAGE_SHA256 },
    { name: "issue_test", path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/test/issue.test.mjs", byte_length: 237, sha256: "51fd472f8cf85fd595246814db29699ab81ccdc2986d80666d8609a8c4972b4b" },
    { name: "regression_test", path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/test/regression.test.mjs", byte_length: 241, sha256: "381c573d8f99305b47db9f1a2ca49779842fe1187b9d7c5b7410e56dda9240c5" },
  ];
  assert(sourceInputs.request.source_count === 3 && sameJson(sourceInputs.request.sources, expectedSources) &&
    sourceInputs.outcome.status === "MATERIALIZED_EXACT_BYTES" &&
    Array.isArray(sourceInputs.outcome.files) && sourceInputs.outcome.files.length === 3,
  "ACTION_TRACE_REJECTED", "source-input materialization drifted");
  sourceInputs.outcome.files.forEach((file, index) => {
    exactKeys(file, ["name", "path_ref", "byte_length", "sha256", "device", "inode", "uid", "regular", "symlink", "nlink", "created_exclusive"],
      "ACTION_TRACE_REJECTED", `materialized source ${index + 1}`);
    assert(file.name === expectedSources[index].name, "ACTION_TRACE_REJECTED", "materialized source order drifted");
    validateCreatedFileReceiptValue(Object.fromEntries(Object.entries(file).filter(([key]) => key !== "name")),
      `materialized source ${file.name}`, expectedSources[index]);
  });

  for (const ordinal of [1, 2, 3]) {
    const request = expectMeta(`tool_step_${ordinal}_request`, "TOOL_REQUEST", "TOOL_ACTION", ordinal);
    exactKeys(request.request, ["plan_step", "operation_mapping"],
      "ACTION_TRACE_REJECTED", `tool step ${ordinal} request`);
    exactKeys(request.outcome,
      ["status", "plan_id", "adapter_version", "dynamic_controls_admitted", "external_effects"],
      "ACTION_TRACE_REJECTED", `tool step ${ordinal} request outcome`);
    const step = REQUIRED_STEPS[ordinal - 1];
    const mapping = card.fixed_operation_mapping[`${step.tool_id}/${step.operation_id}`];
    assert(sameJson(request.request, { plan_step: step, operation_mapping: mapping }) &&
      request.outcome.status === "REQUEST_ACCEPTED_FROM_CLOSED_PLAN" &&
      request.outcome.plan_id === "P1-067-REP001-IR10-THREE-STEP-PLAN" &&
      request.outcome.adapter_version === "OFFLINE-B1-FINITE-TOOL-ADAPTER/1" &&
      request.outcome.dynamic_controls_admitted === false,
    "ACTION_TRACE_REJECTED", `tool step ${ordinal} request drifted`);
    validateFalseEffects(request.outcome.external_effects, "ACTION_TRACE_REJECTED");
  }

  const validateMutation = (id, phase, ordinal, requestExpected, status, identity) => {
    const action = expectMeta(id, "FILE_MUTATION", phase, ordinal);
    exactKeys(action.request, Object.keys(requestExpected), "ACTION_TRACE_REJECTED", `${id} request`);
    assert(sameJson(action.request, requestExpected), "ACTION_TRACE_REJECTED", `${id} request drifted`);
    exactKeys(action.outcome, ["status", "atomic_rename", "temporary_receipt", "source"],
      "ACTION_TRACE_REJECTED", `${id} outcome`);
    assert(action.outcome.status === status && action.outcome.atomic_rename === true,
      "ACTION_TRACE_REJECTED", `${id} outcome drifted`);
    validateTemporaryReceiptValue(action.outcome.temporary_receipt, `${id} temporary receipt`);
    validateCreatedFileReceiptValue(action.outcome.source, `${id} source`, identity);
    assert(action.outcome.temporary_receipt.device === action.outcome.source.device &&
      action.outcome.temporary_receipt.inode === action.outcome.source.inode &&
      action.outcome.temporary_receipt.uid === action.outcome.source.uid,
    "ACTION_TRACE_REJECTED", `${id} atomic inode join drifted`);
  };
  validateMutation("tool_step_1_atomic_postimage", "TOOL_ACTION", 1, {
    target_path: "src/range.mjs", mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT",
    preimage: { byte_length: 115, sha256: PREIMAGE_SHA256 },
    postimage: { byte_length: 127, sha256: POSTIMAGE_SHA256 },
    compiler: fileIdentityReference(card.accepted_inputs.compiler.path, card.accepted_inputs.compiler),
    ir10: fileIdentityReference("evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json", IDENTITIES.ir10),
  }, "ATOMIC_POSTIMAGE_APPLIED", { byte_length: 127, sha256: POSTIMAGE_SHA256 });
  validateMutation("rollback_atomic_restore", "ROLLBACK", null, {
    target_path: "src/range.mjs", mutation_kind: "ATOMIC_COMPLETE_PREIMAGE_RESTORATION",
    current: { byte_length: 127, sha256: POSTIMAGE_SHA256 },
    restore: { byte_length: 115, sha256: PREIMAGE_SHA256 },
  }, "ATOMIC_PREIMAGE_RESTORED", { byte_length: 115, sha256: PREIMAGE_SHA256 });

  const patchCapture = expectMeta("patch_capture", "ARTIFACT_CREATION", "PATCH_EVIDENCE", 1);
  exactKeys(patchCapture.request, ["source_action_id", "path", "creation_policy"],
    "ACTION_TRACE_REJECTED", "patch capture request");
  exactKeys(patchCapture.outcome, ["status", "artifact"], "ACTION_TRACE_REJECTED", "patch capture outcome");
  assert(sameJson(patchCapture.request, {
    source_action_id: "patch_git_diff", path: "patch.diff",
    creation_policy: "CREATE_ONCE_REGULAR_NOFOLLOW_NLINK_ONE",
  }) && patchCapture.outcome.status === "CAPTURED_EXACT_PATCH" &&
    sameJson(patchCapture.outcome.artifact, artifactReference(artifactsByPath.get("patch.diff"))),
  "ACTION_TRACE_REJECTED", "patch capture binding drifted");

  const rollbackCheck = expectMeta("rollback_source_check", "VERIFICATION", "ROLLBACK", null);
  exactKeys(rollbackCheck.request, ["expected_source", "expected_head", "expected_tree", "expected_clean"],
    "ACTION_TRACE_REJECTED", "rollback check request");
  exactKeys(rollbackCheck.outcome, ["status", "source", "head", "tree", "clean", "extra_paths"],
    "ACTION_TRACE_REJECTED", "rollback check outcome");
  assert(sameJson(rollbackCheck.request, {
    expected_source: { byte_length: 115, sha256: PREIMAGE_SHA256 },
    expected_head: BASE_COMMIT, expected_tree: BASE_TREE, expected_clean: true,
  }) && rollbackCheck.outcome.status === "EXACT_BASE_RESTORED" &&
    rollbackCheck.outcome.head === BASE_COMMIT && rollbackCheck.outcome.tree === BASE_TREE &&
    rollbackCheck.outcome.clean === true && sameJson(rollbackCheck.outcome.extra_paths, []),
  "ACTION_TRACE_REJECTED", "rollback source check drifted");
  validateCreatedFileReceiptValue(rollbackCheck.outcome.source, "rollback checked source",
    { byte_length: 115, sha256: PREIMAGE_SHA256 });

  const retained = expectMeta("retained_evidence_policy", "EVIDENCE_RETENTION", "ROLLBACK", null);
  exactKeys(retained.request, ["materialization_root_ref", "policy"],
    "ACTION_TRACE_REJECTED", "retained evidence request");
  exactKeys(retained.outcome, [
    "status", "materialization_receipt", "deleted_paths", "temporary_residue", "preexisting_objects_touched",
  ], "ACTION_TRACE_REJECTED", "retained evidence outcome");
  assert(sameJson(retained.request, {
    materialization_root_ref: "MATERIALIZATION_ROOT",
    policy: "RETAIN_FOR_INDEPENDENT_EVALUATION_NO_CLEANUP",
  }) && retained.outcome.status === "RETAINED_EXACT_MATERIALIZATION" &&
    sameJson(retained.outcome.deleted_paths, []) && retained.outcome.temporary_residue === false &&
    retained.outcome.preexisting_objects_touched === false,
  "ACTION_TRACE_REJECTED", "retained evidence policy drifted");
  validateDirectoryReceiptValue(retained.outcome.materialization_receipt,
    "retained materialization receipt", manifest.materialization_receipt);
}

function validateActionTrace(value, manifest, artifactsByPath, card, candidateRepository, qualityFreezeRoot) {
  exactKeys(value, [
    "schema_version", "record_type", "task_id", "control_id", "run_id", "repetition_id",
    "action_count", "actions",
  ], "ACTION_TRACE_REJECTED", "complete action trace");
  const expectedIds = card.run_evidence_contract.action_trace_required_action_ids;
  assert(value.schema_version === 1 &&
    value.record_type === card.run_evidence_contract.action_trace_record_type &&
    value.task_id === TASK_ID && value.control_id === CONTROL_ID && value.run_id === manifest.run_id &&
    value.repetition_id === manifest.repetition_id && value.action_count === expectedIds.length &&
    Array.isArray(value.actions) && value.actions.length === expectedIds.length,
  "ACTION_TRACE_REJECTED", "complete action trace identity or population drifted");
  assert(sameJson(value.actions.map((action) => action?.action_id), expectedIds),
    "ACTION_TRACE_REJECTED", "complete action trace order/population drifted");
  const byId = new Map();
  value.actions.forEach((action, index) => {
    exactKeys(action, card.run_evidence_contract.action_trace_record_required_fields,
      "ACTION_TRACE_REJECTED", `action trace record ${index + 1}`);
    assert(action.sequence === index + 1 && action.action_id === expectedIds[index] &&
      typeof action.category === "string" && action.category.length > 0 &&
      typeof action.phase === "string" && action.phase.length > 0 &&
      (action.tool_ordinal === null || [1, 2, 3].includes(action.tool_ordinal)) &&
      !byId.has(action.action_id),
    "ACTION_TRACE_REJECTED", `action trace record ${index + 1} binding drifted`);
    byId.set(action.action_id, action);
    if (PROCESS_ACTION_IDS.has(action.action_id)) {
      validateProcessTraceAction(action, manifest, artifactsByPath, candidateRepository);
    }
  });
  assert([...PROCESS_ACTION_IDS].every((id) => byId.has(id)),
    "ACTION_TRACE_REJECTED", "required process action population drifted");
  validateNonProcessTraceActions(byId, manifest, artifactsByPath, card, qualityFreezeRoot);
  return {
    value,
    byId,
    stable: {
      action_count: value.action_count,
      ordered_action_ids: [...expectedIds],
      action_types: value.actions.map(({ action_id, category, phase, tool_ordinal }) => ({
        action_id, category, phase, tool_ordinal,
      })),
      inline_process_streams_recomputed: true,
      raw_test_stream_artifacts_joined: true,
    },
  };
}

function validatePatchEvidencePackage(value, manifest, artifactsByPath, card, actualExecutor, trace) {
  const sections = card.run_evidence_contract.patch_evidence_package_mandatory_sections;
  exactKeys(value, [
    "schema_version", "record_type", "task_id", "control_id", "run_id", "repetition_id", ...sections,
  ], "PATCH_EVIDENCE_PACKAGE_REJECTED", "Patch Evidence Package");
  assert(value.schema_version === 1 &&
    value.record_type === card.run_evidence_contract.patch_evidence_package_record_type &&
    value.task_id === TASK_ID && value.control_id === CONTROL_ID && value.run_id === manifest.run_id &&
    value.repetition_id === manifest.repetition_id,
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "Patch Evidence Package identity drifted");

  exactKeys(value.manifest, ["candidate_binding", "artifact_checksums"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package manifest");
  const expectedChecksums = Object.fromEntries([...artifactsByPath.entries()]
    .filter(([path]) => path !== "patch-evidence-package.json" && path !== "run-record.json")
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([path, artifact]) => [path, artifact.entry.sha256]));
  assert(sameJson(value.manifest.candidate_binding, manifest.candidate_binding) &&
    sameJson(value.manifest.artifact_checksums, expectedChecksums),
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "package manifest checksum binding drifted");

  exactKeys(value.source_identity,
    ["repository_identity", "base", "target_path", "preimage", "accepted_postimage", "final"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package source identity");
  assert(value.source_identity.repository_identity ===
    "sourcelens-fixture://p1-representative-tasks/SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0" &&
    sameJson(value.source_identity.base, { commit: BASE_COMMIT, tree: BASE_TREE, clean: true }) &&
    value.source_identity.target_path === "src/range.mjs" &&
    sameJson(value.source_identity.preimage, { byte_length: 115, sha256: PREIMAGE_SHA256 }) &&
    sameJson(value.source_identity.accepted_postimage, { byte_length: 127, sha256: POSTIMAGE_SHA256 }) &&
    sameJson(value.source_identity.final, {
      source: { byte_length: 115, sha256: PREIMAGE_SHA256 },
      head: BASE_COMMIT, tree: BASE_TREE, clean: true,
    }),
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "package source identity drifted");

  exactKeys(value.environment,
    ["target_runtime", "environment_snapshot", "system_configuration", "compatibility_profile", "actual_executor"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package environment");
  const expectedEnvironment = {
    target_runtime: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/target-runtime-oci-manifest.json", IDENTITIES.target_runtime),
    environment_snapshot: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/environment-snapshot.json", IDENTITIES.environment_snapshot),
    system_configuration: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/system-configuration.json", IDENTITIES.system_configuration),
    compatibility_profile: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/compatibility-profile.json", IDENTITIES.compatibility_profile),
    actual_executor: artifactReference(artifactsByPath.get("actual-executor.json")),
  };
  assert(sameJson(value.environment, expectedEnvironment),
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package environment binding drifted");

  exactKeys(value.understanding, ["task_spec", "issue", "expected_base_failure", "observed_base_issue_action_id"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package understanding");
  assert(sameJson(value.understanding, {
    task_spec: fileIdentityReference(card.accepted_inputs.task_spec.path, card.accepted_inputs.task_spec),
    issue: "normalizeRange preserves reversed bounds instead of normalizing them",
    expected_base_failure: fileIdentityReference(
      card.accepted_inputs.expected_base_failure.path, card.accepted_inputs.expected_base_failure),
    observed_base_issue_action_id: "base_issue_test",
  }), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package understanding drifted");

  exactKeys(value.plan,
    ["artifact", "admission_status", "adapter_version", "plan_id", "fixed_step_count", "steps", "external_effects"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package plan");
  assert(sameJson(value.plan.artifact, artifactReference(artifactsByPath.get("tool-plan.json"))) &&
    value.plan.admission_status === "ADMITTED_CLOSED_FINITE_TOOL_PLAN" &&
    value.plan.adapter_version === "OFFLINE-B1-FINITE-TOOL-ADAPTER/1" &&
    value.plan.plan_id === "P1-067-REP001-IR10-THREE-STEP-PLAN" && value.plan.fixed_step_count === 3 &&
    sameJson(value.plan.steps, REQUIRED_STEPS),
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "package plan drifted");
  validateFalseEffects(value.plan.external_effects, "PATCH_EVIDENCE_PACKAGE_REJECTED");

  exactKeys(value.actions, ["action_trace", "ordered_action_ids", "tool_step_bindings"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package actions");
  const expectedToolBindings = [
    { ordinal: 1, tool_id: "local-file-edit", operation_id: "apply-finite-typed-patch-ir", request_action_id: "tool_step_1_request", outcome_action_id: "tool_step_1_atomic_postimage" },
    { ordinal: 2, tool_id: "local-node-test", operation_id: "issue-test", request_action_id: "tool_step_2_request", outcome_action_id: "tool_issue_test" },
    { ordinal: 3, tool_id: "local-node-test", operation_id: "regression-test", request_action_id: "tool_step_3_request", outcome_action_id: "tool_regression_test" },
  ];
  assert(sameJson(value.actions.action_trace, artifactReference(artifactsByPath.get("action-trace.json"))) &&
    sameJson(value.actions.ordered_action_ids, card.run_evidence_contract.action_trace_required_action_ids) &&
    sameJson(value.actions.tool_step_bindings, expectedToolBindings),
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "package action trace binding drifted");

  exactKeys(value.patch,
    ["changed_paths", "artifact", "preimage", "postimage", "compiler", "ir10", "mutation_kind"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package patch");
  assert(sameJson(value.patch, {
    changed_paths: ["src/range.mjs"],
    artifact: artifactReference(artifactsByPath.get("patch.diff")),
    preimage: { byte_length: 115, sha256: PREIMAGE_SHA256 },
    postimage: { byte_length: 127, sha256: POSTIMAGE_SHA256 },
    compiler: fileIdentityReference(card.accepted_inputs.compiler.path, card.accepted_inputs.compiler),
    ir10: fileIdentityReference("evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json", IDENTITIES.ir10),
    mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT",
  }), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package patch binding drifted");

  exactKeys(value.tests, ["base_issue", "base_regression", "patched_issue", "patched_regression"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package tests");
  const testNames = ["base_issue", "base_regression", "patched_issue", "patched_regression"];
  COMMAND_DEFINITIONS.forEach((definition, index) => {
    const test = value.tests[testNames[index]];
    exactKeys(test, ["action_id", "expected_exit_status", "observed_exit_status", "stdout", "stderr"],
      "PATCH_EVIDENCE_PACKAGE_REJECTED", `package test ${testNames[index]}`);
    assert(test.action_id === definition.action_id && test.expected_exit_status === definition.exit_status &&
      test.observed_exit_status === definition.exit_status &&
      sameJson(test.stdout, artifactReference(artifactsByPath.get(definition.stdout_path))) &&
      sameJson(test.stderr, artifactReference(artifactsByPath.get(definition.stderr_path))),
    "PATCH_EVIDENCE_PACKAGE_REJECTED", `package test ${testNames[index]} drifted`);
  });

  exactKeys(value.verification, [
    "status", "evaluator", "verdict", "runner_reported_pass_authoritative", "adapter_reported_pass_authoritative",
  ], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package verification");
  exactKeys(value.verification.evaluator, ["path", "version", "byte_length", "sha256"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package evaluator");
  const oracleIdentity = currentExecutingModuleIdentities().quality_oracle;
  assert(value.verification.status === "PENDING_INDEPENDENT_EVALUATION" &&
    sameJson(value.verification.evaluator, { ...oracleIdentity, version: QUALITY_ORACLE_VERSION }) &&
    value.verification.verdict === null && value.verification.runner_reported_pass_authoritative === false &&
    value.verification.adapter_reported_pass_authoritative === false,
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "package verification falsely claims an independent verdict");

  exactKeys(value.risk, [
    "claim_boundary", "external_effects", "dynamic_controls_admitted", "free_form_execution_admitted",
    "child_process_group_termination_enforced", "preexisting_object_overwrite_or_cleanup",
  ], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package risk");
  assert(value.risk.claim_boundary === CLAIM && value.risk.dynamic_controls_admitted === false &&
    value.risk.free_form_execution_admitted === false &&
    value.risk.child_process_group_termination_enforced === true &&
    value.risk.preexisting_object_overwrite_or_cleanup === false,
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "package risk boundary drifted");
  validateFalseEffects(value.risk.external_effects, "PATCH_EVIDENCE_PACKAGE_REJECTED");

  exactKeys(value.approval, ["status", "self_approval", "independent_quality_required", "task_gate_claimed"],
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "package approval");
  assert(sameJson(value.approval, {
    status: "PENDING_TASK_GATE", self_approval: false,
    independent_quality_required: true, task_gate_claimed: false,
  }), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package approval was forged");

  exactKeys(value.rollback, [
    "artifact", "materialization_receipt", "mutation_occurred", "restored_source", "head", "tree", "clean",
    "extra_paths", "retained_materialization", "cleanup_performed",
  ], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package rollback");
  assert(sameJson(value.rollback.artifact, artifactReference(artifactsByPath.get("rollback.json"))) &&
    sameJson(value.rollback.materialization_receipt, manifest.materialization_receipt) &&
    value.rollback.mutation_occurred === true &&
    sameJson(value.rollback.restored_source, { byte_length: 115, sha256: PREIMAGE_SHA256 }) &&
    value.rollback.head === BASE_COMMIT && value.rollback.tree === BASE_TREE && value.rollback.clean === true &&
    sameJson(value.rollback.extra_paths, []) && value.rollback.retained_materialization === true &&
    value.rollback.cleanup_performed === false,
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "package rollback binding drifted");

  return {
    mandatory_sections: [...sections],
    mandatory_fields_present: true,
    artifact_checksums_recomputed: true,
    action_trace_joined: true,
    actual_executor_joined: true,
    runner_verification_state: "PENDING_INDEPENDENT_EVALUATION",
    independent_verification_transition: "PENDING_INDEPENDENT_EVALUATION_TO_PASS",
  };
}

export function evaluateRunEvidence(manifestPath, options = {}) {
  assert(typeof manifestPath === "string" && isAbsolute(manifestPath), "EVIDENCE_PATH_ESCAPE_REJECTED", "manifest path must be absolute");
  const allowedRoot = realpathSync(options.allowedRoot ?? AUTHORIZED_EVIDENCE_ROOT);
  const resolvedManifest = resolve(manifestPath);
  const runRoot = realpathSync(dirname(resolvedManifest));
  assert(contained(allowedRoot, runRoot), "EVIDENCE_PATH_ESCAPE_REJECTED", "run root escaped authorized Evidence root");
  const runStat = lstatSync(runRoot);
  assert(runStat.isDirectory() && !runStat.isSymbolicLink() && runStat.uid === process.getuid(),
    "EVIDENCE_IDENTITY_REJECTED", "run root is not an owned real directory");
  const manifestRead = readNoFollowRegular(resolvedManifest, undefined, "EVIDENCE_IDENTITY_REJECTED", "run manifest");
  const manifest = parseJson(manifestRead.bytes, "EVIDENCE_SCHEMA_REJECTED", "run manifest", true);
  exactKeys(manifest, [
    "schema_version", "record_type", "task_id", "control_id", "run_id", "repetition_id",
    "candidate_binding", "run_root_receipt", "materialization_receipt", "artifacts", "agent_status",
  ], "EVIDENCE_SCHEMA_REJECTED", "run manifest");
  assert(manifest.schema_version === 1 && manifest.record_type === "sourcelens_aios_p1_067_run_manifest" &&
    manifest.task_id === TASK_ID && manifest.control_id === CONTROL_ID &&
    typeof manifest.run_id === "string" && /^[a-z0-9][a-z0-9._-]{0,63}$/.test(manifest.run_id) &&
    Number.isInteger(manifest.repetition_id) && manifest.repetition_id >= 1 &&
    manifest.agent_status === "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED",
  "RUN_BINDING_REJECTED", "run manifest identity drifted");
  exactKeys(manifest.candidate_binding, ["commit", "tree", "clean"], "CANDIDATE_BINDING_REJECTED", "manifest candidate binding");
  assert(/^[0-9a-f]{40}$/.test(manifest.candidate_binding.commit) && /^[0-9a-f]{40}$/.test(manifest.candidate_binding.tree) &&
    manifest.candidate_binding.clean === true, "CANDIDATE_BINDING_REJECTED", "manifest candidate binding drifted");
  const candidateRepository = validateCandidateRepository(
    options.candidateRepository ?? REPOSITORY_ROOT,
    manifest,
    allowedRoot,
    options.candidateRepository !== undefined,
  );
  exactKeys(manifest.run_root_receipt, ["realpath", "device", "inode", "uid", "created_exclusive"],
    "EVIDENCE_IDENTITY_REJECTED", "run root receipt");
  assert(manifest.run_root_receipt.realpath === runRoot && manifest.run_root_receipt.device === runStat.dev &&
    manifest.run_root_receipt.inode === runStat.ino && manifest.run_root_receipt.uid === runStat.uid &&
    manifest.run_root_receipt.created_exclusive === true,
  "PREEXISTING_EVIDENCE_REJECTED", "run root receipt drifted");
  const retainedMaterialization = validateRetainedMaterialization(runRoot, manifest.materialization_receipt);
  assert(Array.isArray(manifest.artifacts), "EVIDENCE_IDENTITY_REJECTED", "artifact population is missing");
  if (!manifest.artifacts.some((entry) => entry?.role === "rollback")) {
    fail("ROLLBACK_EVIDENCE_MISSING", "rollback artifact is missing");
  }
  assert(manifest.artifacts.length === REQUIRED_ARTIFACT_LAYOUT.length,
    "EVIDENCE_IDENTITY_REJECTED", "artifact role population drifted");
  const artifactsByPath = new Map();
  manifest.artifacts.forEach((entry, index) => {
    const expected = REQUIRED_ARTIFACT_LAYOUT[index];
    exactKeys(entry, ["role", "path", "byte_length", "sha256", "run_id"], "EVIDENCE_SCHEMA_REJECTED", "artifact entry");
    assert(entry.role === expected.role,
      entry.role === "rollback" ? "ROLLBACK_EVIDENCE_MISSING" : "EVIDENCE_IDENTITY_REJECTED",
      `artifact ${index + 1} role order drifted`);
    assert(entry.run_id === manifest.run_id, "RUN_BINDING_REJECTED", `${entry.role} manifest run binding drifted`);
    assert(typeof entry.path === "string" && /^[a-z0-9][a-z0-9._-]{0,127}$/.test(entry.path),
      "EVIDENCE_PATH_ESCAPE_REJECTED", `${entry.role} path is not a safe leaf`);
    assert(entry.path === expected.path, "EVIDENCE_IDENTITY_REJECTED", `artifact ${index + 1} path order drifted`);
    assert(Number.isInteger(entry.byte_length) && entry.byte_length >= 0 &&
      (entry.role === "raw_stream" || entry.byte_length > 0) && /^[0-9a-f]{64}$/.test(entry.sha256),
      "EVIDENCE_SCHEMA_REJECTED", `${entry.role} identity is malformed`);
    assert(!artifactsByPath.has(entry.path), "EVIDENCE_IDENTITY_REJECTED", "duplicate artifact path");
    const artifactPath = resolve(runRoot, entry.path);
    assert(contained(runRoot, artifactPath), "EVIDENCE_PATH_ESCAPE_REJECTED", `${entry.role} escaped run root`);
    const exact = readNoFollowRegular(artifactPath, entry, "EVIDENCE_IDENTITY_REJECTED", entry.role);
    exact.physical.path = entry.path;
    artifactsByPath.set(entry.path, { ...exact, entry });
  });
  const artifact = (path) => artifactsByPath.get(path);
  const planArtifact = artifact("tool-plan.json");
  assert(planArtifact.bytes.length === IDENTITIES.positive_tool_plan.byte_length &&
    sha256(planArtifact.bytes) === IDENTITIES.positive_tool_plan.sha256,
  "EVIDENCE_IDENTITY_REJECTED", "tool plan artifact is not the frozen plan");
  validateFiniteToolPlan(planArtifact.bytes);
  const provenance = parseJson(artifact("candidate-provenance.json").bytes, "EVIDENCE_SCHEMA_REJECTED", "candidate provenance", true);
  exactKeys(provenance, ["schema_version", "record_type", "run_id", "candidate_binding"], "EVIDENCE_SCHEMA_REJECTED", "candidate provenance");
  assert(provenance.schema_version === 1 && provenance.record_type === "sourcelens_aios_p1_067_run_provenance" &&
    provenance.run_id === manifest.run_id && sameJson(provenance.candidate_binding, manifest.candidate_binding),
  "RUN_BINDING_REJECTED", "candidate provenance drifted");
  const observation = parseJson(artifact("observation.json").bytes, "EVIDENCE_SCHEMA_REJECTED", "observation", true);
  exactKeys(observation, [
    "schema_version", "record_type", "task_id", "control_id", "run_id", "repetition_id",
    "candidate_binding", "input_identities", "plan_identity", "agent_status",
  ], "EVIDENCE_SCHEMA_REJECTED", "observation");
  assert(observation.schema_version === 1 && observation.record_type === "sourcelens_aios_p1_067_run_observation" &&
    observation.task_id === TASK_ID && observation.control_id === CONTROL_ID &&
    observation.run_id === manifest.run_id && observation.repetition_id === manifest.repetition_id &&
    observation.agent_status === "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED" &&
    sameJson(observation.candidate_binding, manifest.candidate_binding) &&
    sameJson(observation.input_identities, {
      task_spec_sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
      source_preimage_sha256: PREIMAGE_SHA256,
      postimage_sha256: POSTIMAGE_SHA256,
    }) && sameJson(observation.plan_identity, {
      byte_length: IDENTITIES.positive_tool_plan.byte_length,
      sha256: IDENTITIES.positive_tool_plan.sha256,
    }),
  "RUN_BINDING_REJECTED", "observation run binding drifted");
  const rollbackReceipt = parseJson(artifact("rollback.json").bytes, "ROLLBACK_EVIDENCE_MISSING", "rollback", true);
  exactKeys(rollbackReceipt, [
    "schema_version", "record_type", "present", "run_id", "mutation_occurred",
    "restored_source_byte_length", "source_sha256", "head", "tree", "clean", "extra_paths",
  ], "ROLLBACK_EVIDENCE_MISSING", "rollback receipt");
  assert(rollbackReceipt.schema_version === 1 &&
    rollbackReceipt.record_type === "sourcelens_aios_p1_067_rollback_receipt" &&
    rollbackReceipt.present === true,
  "ROLLBACK_EVIDENCE_REJECTED", "rollback artifact schema drifted");
  assert(rollbackReceipt.run_id === manifest.run_id,
    "RUN_BINDING_REJECTED", "rollback artifact run binding drifted");
  assert(
    rollbackReceipt.mutation_occurred === true && rollbackReceipt.restored_source_byte_length === 115 &&
    rollbackReceipt.source_sha256 === PREIMAGE_SHA256 && rollbackReceipt.head === BASE_COMMIT &&
    rollbackReceipt.tree === BASE_TREE && rollbackReceipt.clean === true && sameJson(rollbackReceipt.extra_paths, []),
  "ROLLBACK_EVIDENCE_REJECTED", "rollback artifact identity drifted");
  const runRecord = parseJson(artifact("run-record.json").bytes, "RUN_RECORD_EVIDENCE_REJECTED", "RunRecord", true);
  assert(runRecord.run_id === manifest.run_id && runRecord.repetition_id === manifest.repetition_id,
    "RUN_BINDING_REJECTED", "RunRecord run binding drifted");
  validateRunRecord(runRecord, manifest.run_id, manifest.repetition_id, artifactsByPath);
  const commandStream = parseJson(artifact("command-stream.json").bytes,
    "COMMAND_STREAM_EVIDENCE_REJECTED", "command stream", true);
  const derived = validateCommandStream(commandStream, manifest.run_id, artifactsByPath);
  const changedPaths = validatePatchEvidence(artifact("patch.diff").bytes);
  const actualExecutorArtifact = parseJson(artifact("actual-executor.json").bytes,
    "EXECUTOR_EVIDENCE_REJECTED", "actual executor", true);
  const actualExecutor = validateActualExecutor(actualExecutorArtifact, manifest.run_id);
  const actionTraceArtifact = parseJson(artifact("action-trace.json").bytes,
    "ACTION_TRACE_REJECTED", "complete action trace", true);
  const actionTrace = validateActionTrace(
    actionTraceArtifact,
    manifest,
    artifactsByPath,
    validateTaskCard(),
    candidateRepository,
    options.qualityFreezeRoot,
  );
  const patchEvidenceArtifact = parseJson(artifact("patch-evidence-package.json").bytes,
    "PATCH_EVIDENCE_PACKAGE_REJECTED", "Patch Evidence Package", true);
  const patchEvidencePackage = validatePatchEvidencePackage(
    patchEvidenceArtifact,
    manifest,
    artifactsByPath,
    validateTaskCard(),
    actualExecutor,
    actionTrace,
  );
  const authoritative = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_evaluated_run_evidence",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: manifest.run_id,
    repetition_id: manifest.repetition_id,
    candidate_binding: clone(manifest.candidate_binding),
    input_identities: clone(observation.input_identities),
    plan_identity: clone(observation.plan_identity),
    source_evidence_bindings: {
      manifest: {
        byte_length: manifestRead.bytes.length,
        sha256: sha256(manifestRead.bytes),
      },
      actual_executor: artifactReference(artifact("actual-executor.json")),
      action_trace: artifactReference(artifact("action-trace.json")),
      patch_evidence_package: artifactReference(artifact("patch-evidence-package.json")),
    },
    actual_executor_identity: actualExecutor,
    action_trace: actionTrace.stable,
    patch_evidence_package: patchEvidencePackage,
    run_root_receipt: clone(manifest.run_root_receipt),
    materialization_root_receipt: retainedMaterialization.receipt,
    evidence_root: {
      path: manifest.run_id, regular: true, symlink: false, nlink: 1,
      preexisting: !manifest.run_root_receipt.created_exclusive, tampered: false,
    },
    artifact_bindings: REQUIRED_ARTIFACT_LAYOUT.map(({ role, path }) => ({
      role,
      run_id: manifest.run_id,
      physical: artifact(path).physical,
    })),
    tool_actions: derived.tool_actions,
    changed_paths: changedPaths,
    tests: derived.tests,
    rollback: {
      present: rollbackReceipt.present,
      run_id: rollbackReceipt.run_id,
      source_sha256: rollbackReceipt.source_sha256,
      head: rollbackReceipt.head,
      tree: rollbackReceipt.tree,
      clean: rollbackReceipt.clean,
      extra_paths: rollbackReceipt.extra_paths,
    },
    child_process: derived.child_process,
    run_record_status: runRecord.terminal_status.toUpperCase(),
    external_effects: { ...FALSE_EFFECTS },
    evaluator: {
      independent: true,
      adapter_success_trusted: false,
      runner_success_trusted: false,
      ...currentExecutingModuleIdentities().quality_oracle,
      version: QUALITY_ORACLE_VERSION,
    },
    complete_evidence: true,
    verdict: "PASS",
    claim_boundary: CLAIM,
  };
  return validateRunEvidenceDocument(authoritative);
}

export function validateRunEvidenceDocument(document) {
  exactKeys(document, [
    "schema_version", "record_type", "task_id", "control_id", "run_id", "repetition_id",
    "candidate_binding", "input_identities", "plan_identity", "source_evidence_bindings",
    "actual_executor_identity", "action_trace", "patch_evidence_package",
    "run_root_receipt", "materialization_root_receipt",
    "evidence_root", "artifact_bindings",
    "tool_actions", "changed_paths", "tests", "rollback", "child_process", "run_record_status",
    "external_effects", "evaluator", "complete_evidence", "verdict", "claim_boundary",
  ], "EVIDENCE_SCHEMA_REJECTED", "run Evidence document");
  assert(document.schema_version === 1 && document.record_type === "sourcelens_aios_p1_067_evaluated_run_evidence" &&
    document.task_id === TASK_ID && document.control_id === CONTROL_ID && document.claim_boundary === CLAIM,
  "EVIDENCE_SCHEMA_REJECTED", "run Evidence identity drifted");
  assert(typeof document.run_id === "string" && /^[a-z0-9][a-z0-9._-]{0,63}$/.test(document.run_id) &&
    Number.isInteger(document.repetition_id) && document.repetition_id >= 1,
  "RUN_BINDING_REJECTED", "run identity is invalid");
  exactKeys(document.candidate_binding, ["commit", "tree", "clean"], "EVIDENCE_SCHEMA_REJECTED", "candidate binding");
  assert(/^[0-9a-f]{40}$/.test(document.candidate_binding.commit) && /^[0-9a-f]{40}$/.test(document.candidate_binding.tree) &&
    document.candidate_binding.clean === true, "CANDIDATE_BINDING_REJECTED", "candidate binding drifted");
  exactKeys(document.input_identities, ["task_spec_sha256", "source_preimage_sha256", "postimage_sha256"], "EVIDENCE_SCHEMA_REJECTED", "input identities");
  assert(document.input_identities.task_spec_sha256 === "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321" &&
    document.input_identities.source_preimage_sha256 === PREIMAGE_SHA256 &&
    document.input_identities.postimage_sha256 === POSTIMAGE_SHA256,
  "EVIDENCE_IDENTITY_REJECTED", "input identities drifted");
  exactKeys(document.plan_identity, ["byte_length", "sha256"], "EVIDENCE_SCHEMA_REJECTED", "plan identity");
  assert(document.plan_identity.byte_length === IDENTITIES.positive_tool_plan.byte_length &&
    document.plan_identity.sha256 === IDENTITIES.positive_tool_plan.sha256,
  "EVIDENCE_IDENTITY_REJECTED", "plan identity drifted");
  exactKeys(document.source_evidence_bindings,
    ["manifest", "actual_executor", "action_trace", "patch_evidence_package"],
    "EVIDENCE_SCHEMA_REJECTED", "source Evidence bindings");
  for (const [label, binding] of Object.entries(document.source_evidence_bindings)) {
    exactKeys(binding, label === "manifest" ? ["byte_length", "sha256"] : ["path", "byte_length", "sha256"],
      "EVIDENCE_SCHEMA_REJECTED", `${label} Evidence binding`);
    assert(Number.isInteger(binding.byte_length) && binding.byte_length > 0 && /^[0-9a-f]{64}$/.test(binding.sha256),
      "EVIDENCE_IDENTITY_REJECTED", `${label} Evidence binding drifted`);
  }
  exactKeys(document.actual_executor_identity, [
    "executor_kind", "platform", "architecture", "node", "git", "container_runtime_observed",
    "declared_target_materialized", "external_effects",
  ], "EVIDENCE_SCHEMA_REJECTED", "actual executor identity");
  assert(document.actual_executor_identity.executor_kind === "LOCAL_HOST_PROCESS" &&
    document.actual_executor_identity.platform === process.platform &&
    document.actual_executor_identity.architecture === process.arch &&
    document.actual_executor_identity.container_runtime_observed === false &&
    document.actual_executor_identity.declared_target_materialized === false,
  "EXECUTOR_EVIDENCE_REJECTED", "evaluated executor identity drifted");
  validateFalseEffects(document.actual_executor_identity.external_effects, "EXECUTOR_EVIDENCE_REJECTED");
  exactKeys(document.action_trace, [
    "action_count", "ordered_action_ids", "action_types", "inline_process_streams_recomputed",
    "raw_test_stream_artifacts_joined",
  ], "EVIDENCE_SCHEMA_REJECTED", "evaluated action trace");
  assert(document.action_trace.action_count === 32 && document.action_trace.inline_process_streams_recomputed === true &&
    document.action_trace.raw_test_stream_artifacts_joined === true,
  "ACTION_TRACE_REJECTED", "evaluated action trace summary drifted");
  exactKeys(document.patch_evidence_package, [
    "mandatory_sections", "mandatory_fields_present", "artifact_checksums_recomputed", "action_trace_joined",
    "actual_executor_joined", "runner_verification_state", "independent_verification_transition",
  ], "EVIDENCE_SCHEMA_REJECTED", "evaluated Patch Evidence Package");
  assert(document.patch_evidence_package.mandatory_sections.length === 12 &&
    document.patch_evidence_package.mandatory_fields_present === true &&
    document.patch_evidence_package.artifact_checksums_recomputed === true &&
    document.patch_evidence_package.action_trace_joined === true &&
    document.patch_evidence_package.actual_executor_joined === true &&
    document.patch_evidence_package.runner_verification_state === "PENDING_INDEPENDENT_EVALUATION" &&
    document.patch_evidence_package.independent_verification_transition === "PENDING_INDEPENDENT_EVALUATION_TO_PASS",
  "PATCH_EVIDENCE_PACKAGE_REJECTED", "evaluated Patch Evidence Package summary drifted");
  for (const [label, receipt] of [
    ["run root receipt", document.run_root_receipt],
    ["materialization root receipt", document.materialization_root_receipt],
  ]) {
    exactKeys(receipt, ["realpath", "device", "inode", "uid", "created_exclusive"],
      "EVIDENCE_SCHEMA_REJECTED", label);
    assert(isAbsolute(receipt.realpath) && Number.isInteger(receipt.device) && Number.isInteger(receipt.inode) &&
      Number.isInteger(receipt.uid) && receipt.created_exclusive === true,
    "EVIDENCE_IDENTITY_REJECTED", `${label} identity drifted`);
  }
  assert(document.run_root_receipt.realpath !== document.materialization_root_receipt.realpath &&
    !(document.run_root_receipt.device === document.materialization_root_receipt.device &&
      document.run_root_receipt.inode === document.materialization_root_receipt.inode),
  "MATERIALIZATION_ROOT_REJECTED", "run and materialization roots are not distinct");
  validatePhysical(document.evidence_root, "Evidence root");
  assert(Array.isArray(document.artifact_bindings), "EVIDENCE_SCHEMA_REJECTED", "artifact bindings missing");
  assert(document.artifact_bindings.length === REQUIRED_ARTIFACT_LAYOUT.length,
    "EVIDENCE_IDENTITY_REJECTED", "artifact role population drifted");
  for (let index = 0; index < REQUIRED_ARTIFACT_LAYOUT.length; index += 1) {
    const artifact = document.artifact_bindings[index];
    const expected = REQUIRED_ARTIFACT_LAYOUT[index];
    exactKeys(artifact, ["role", "run_id", "physical"], "EVIDENCE_SCHEMA_REJECTED", "artifact binding");
    assert(artifact.role === expected.role && artifact.physical?.path === expected.path,
      "EVIDENCE_IDENTITY_REJECTED", `artifact binding ${index + 1} role/path order drifted`);
    assert(artifact.run_id === document.run_id, "RUN_BINDING_REJECTED", `${artifact.role} run binding drifted`);
    validatePhysical(artifact.physical, `${artifact.role} artifact`);
  }
  assert(Array.isArray(document.tool_actions) && document.tool_actions.length === 3, "TOOL_ACTION_EVIDENCE_REJECTED", "tool actions drifted");
  document.tool_actions.forEach((action, index) => {
    exactKeys(action, ["ordinal", "tool_id", "operation_id", "exit_status", "terminated"], "TOOL_ACTION_EVIDENCE_REJECTED", "tool action");
    assert(action.ordinal === REQUIRED_STEPS[index].ordinal && action.tool_id === REQUIRED_STEPS[index].tool_id &&
      action.operation_id === REQUIRED_STEPS[index].operation_id && action.exit_status === 0 && action.terminated === true,
    "TOOL_ACTION_EVIDENCE_REJECTED", "tool action semantics drifted");
  });
  assert(sameJson(document.changed_paths, ["src/range.mjs"]), "PATCH_EVIDENCE_REJECTED", "changed path scope drifted");
  exactKeys(document.tests, ["base_issue", "base_regression", "patched_issue", "patched_regression"], "EVIDENCE_SCHEMA_REJECTED", "tests");
  assert(document.tests.base_issue === "EXPECTED_FAIL" && document.tests.base_regression === "PASS" &&
    document.tests.patched_issue === "PASS" && document.tests.patched_regression === "PASS",
  "TEST_EVIDENCE_REJECTED", "test outcomes drifted");
  exactKeys(document.rollback, ["present", "run_id", "source_sha256", "head", "tree", "clean", "extra_paths"], "ROLLBACK_EVIDENCE_MISSING", "rollback");
  assert(document.rollback.present === true, "ROLLBACK_EVIDENCE_MISSING", "rollback receipt missing");
  assert(document.rollback.run_id === document.run_id, "RUN_BINDING_REJECTED", "rollback run binding drifted");
  assert(document.rollback.source_sha256 === PREIMAGE_SHA256 && document.rollback.head === BASE_COMMIT &&
    document.rollback.tree === BASE_TREE && document.rollback.clean === true && sameJson(document.rollback.extra_paths, []),
  "ROLLBACK_EVIDENCE_REJECTED", "rollback identity drifted");
  exactKeys(document.child_process, ["failure_kind", "terminated", "descendants_alive"], "CHILD_TERMINATION_EVIDENCE_REJECTED", "child process");
  assert(document.child_process.terminated === true && document.child_process.descendants_alive === false,
    "CHILD_TERMINATION_EVIDENCE_REJECTED", "child termination not proven");
  validateFalseEffects(document.external_effects, "EXTERNAL_EFFECT_EVIDENCE_REJECTED");
  exactKeys(document.evaluator, [
    "independent", "adapter_success_trusted", "runner_success_trusted", "path", "byte_length", "sha256", "version",
  ], "EVIDENCE_SCHEMA_REJECTED", "evaluator");
  const expectedEvaluator = currentExecutingModuleIdentities().quality_oracle;
  assert(document.evaluator.independent === true && document.evaluator.adapter_success_trusted === false &&
    document.evaluator.runner_success_trusted === false &&
    sameJson({
      path: document.evaluator.path,
      byte_length: document.evaluator.byte_length,
      sha256: document.evaluator.sha256,
    }, expectedEvaluator) && document.evaluator.version === QUALITY_ORACLE_VERSION &&
    document.run_record_status === "COMPLETED" && document.complete_evidence === true && document.verdict === "PASS",
  "EVALUATOR_EVIDENCE_REJECTED", "independent verdict boundary drifted");
  return document;
}

export function stableProjection(input) {
  const document = validateRunEvidenceDocument(input);
  return {
    schema_version: 1,
    task_id: document.task_id,
    control_id: document.control_id,
    candidate_binding: document.candidate_binding,
    input_identities: document.input_identities,
    plan_identity: document.plan_identity,
    actual_executor_identity: document.actual_executor_identity,
    action_trace: document.action_trace,
    patch_evidence_package: document.patch_evidence_package,
    tool_actions: document.tool_actions,
    changed_paths: document.changed_paths,
    tests: document.tests,
    rollback: {
      source_sha256: document.rollback.source_sha256,
      head: document.rollback.head,
      tree: document.rollback.tree,
      clean: document.rollback.clean,
      extra_paths: document.rollback.extra_paths,
    },
    run_record_status: document.run_record_status,
    external_effects: document.external_effects,
    evaluator: document.evaluator,
    complete_evidence: document.complete_evidence,
    verdict: document.verdict,
    claim_boundary: document.claim_boundary,
  };
}

export function compareStableRuns(runA, runB) {
  const leftRun = validateRunEvidenceDocument(runA);
  const rightRun = validateRunEvidenceDocument(runB);
  assert(leftRun.run_id !== rightRun.run_id, "RUN_INDEPENDENCE_REJECTED", "Run A and Run B ids must differ");
  assert(leftRun.run_root_receipt.realpath !== rightRun.run_root_receipt.realpath &&
    !(leftRun.run_root_receipt.device === rightRun.run_root_receipt.device &&
      leftRun.run_root_receipt.inode === rightRun.run_root_receipt.inode),
  "RUN_INDEPENDENCE_REJECTED", "Run A and Run B roots are not physically distinct");
  assert(leftRun.materialization_root_receipt.realpath !== rightRun.materialization_root_receipt.realpath &&
    !(leftRun.materialization_root_receipt.device === rightRun.materialization_root_receipt.device &&
      leftRun.materialization_root_receipt.inode === rightRun.materialization_root_receipt.inode),
  "RUN_INDEPENDENCE_REJECTED", "Run A and Run B materializations are not physically distinct");
  const left = canonicalJsonBytes(stableProjection(leftRun));
  const right = canonicalJsonBytes(stableProjection(rightRun));
  assert(left.equals(right), "STABLE_PROJECTION_MISMATCH", "stable projections differ");
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_stable_run_comparison",
    stable_projection_exact_byte_equal: true,
    stable_projection_byte_length: left.length,
    stable_projection_sha256: sha256(left),
    target_verdict: "PASS",
    claim_boundary: CLAIM,
  };
}

function writeExclusive(path, bytes) {
  writeFileSync(path, bytes, { flag: "wx", mode: 0o600 });
}

function createSelfQualityFreeze(parent) {
  const root = join(parent, "quality-freeze");
  mkdirSync(root, { mode: 0o700 });
  const modules = currentExecutingModuleIdentities();
  const qualityFiles = [
    ["target_runtime", "evaluation-harness/fixtures/offline-b1-simple-tool-v1/target-runtime-oci-manifest.json", IDENTITIES.target_runtime],
    ["environment_snapshot", "evaluation-harness/fixtures/offline-b1-simple-tool-v1/environment-snapshot.json", IDENTITIES.environment_snapshot],
    ["system_configuration", "evaluation-harness/fixtures/offline-b1-simple-tool-v1/system-configuration.json", IDENTITIES.system_configuration],
    ["compatibility_profile", "evaluation-harness/fixtures/offline-b1-simple-tool-v1/compatibility-profile.json", IDENTITIES.compatibility_profile],
    ["positive_tool_plan", "evaluation-harness/fixtures/offline-b1-simple-tool-v1/positive-tool-plan.json", IDENTITIES.positive_tool_plan],
    ["negative_cases", "evaluation-harness/fixtures/offline-b1-simple-tool-v1/negative-cases.json", IDENTITIES.negative_cases],
    ["task_card", EXECUTING_MODULE_PATHS.task_card, IDENTITIES.task_card],
    ["quality_oracle", EXECUTING_MODULE_PATHS.quality_oracle, modules.quality_oracle],
  ].map(([role, path, identity]) => ({ role, path, byte_length: identity.byte_length, sha256: identity.sha256 }));
  const value = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_quality_freeze_manifest",
    task_id: TASK_ID,
    status: "QUALITY_FREEZE_COMPLETE",
    target_verdict: "PASS",
    quality_files: qualityFiles,
    self_test: { target_verdict: "PASS", false_accepts: 0 },
    worker_boundary: { worker_runner_failure_path_self_test_required: true },
  };
  const bytes = canonicalJsonBytes(value);
  const path = join(root, "CORRECTED_QUALITY_FREEZE_SELF_TEST.json");
  writeExclusive(path, bytes);
  return { root, reference: { path, byte_length: bytes.length, sha256: sha256(bytes) } };
}

function artifactEntry(role, path, runId, bytes) {
  return { role, path, byte_length: bytes.length, sha256: sha256(bytes), run_id: runId };
}

function buildRunRecord(runId, repetitionId, artifactChecksums) {
  return {
    schema_version: "1.0",
    run_id: runId,
    task_id: CONTROL_ID,
    dataset_version: "1.0.0",
    adapter_id: "B1",
    adapter_version: "OFFLINE-B1-FINITE-TOOL-ADAPTER/1",
    environment_snapshot_id: "ENV-SOURCELENS-P1-REP-NODE20-STDLIB-1",
    system_configuration_id: "P1-067-B1-OFFLINE-FINITE-TOOL-1",
    repetition_id: repetitionId,
    started_at: "2026-07-21T00:00:00Z",
    ended_at: "2026-07-21T00:00:01Z",
    terminal_status: "completed",
    stop_reason_code: "agent_complete",
    invalid_run_reason: null,
    error_taxonomy: [],
    trace_ref: "command-stream.json",
    patch_ref: "patch.diff",
    test_artifact_refs: [...TEST_ARTIFACT_REFS],
    verification_ref: null,
    usage: { input_tokens: 0, output_tokens: 0, tool_calls: 3, retries: 0, human_interventions: 0, cost_usd: 0, latency_ms: 1 },
    policy_violations: [],
    artifact_checksums: artifactChecksums,
  };
}

function initializePhysicalMaterialization(runRoot) {
  const materialization = join(runRoot, "materialization");
  mkdirSync(materialization, { mode: 0o700 });
  mkdirSync(join(runRoot, "home"), { mode: 0o700 });
  mkdirSync(join(materialization, "src"), { mode: 0o700 });
  mkdirSync(join(materialization, "test"), { mode: 0o700 });
  const source = readNoFollowRegular(MATERIALIZATION_INPUTS.source.path,
    MATERIALIZATION_INPUTS.source.identity, "SELF_TEST_SETUP_FAILED", "source preimage").bytes;
  const issue = readNoFollowRegular(MATERIALIZATION_INPUTS.issue.path,
    MATERIALIZATION_INPUTS.issue.identity, "SELF_TEST_SETUP_FAILED", "issue test").bytes;
  const regression = readNoFollowRegular(MATERIALIZATION_INPUTS.regression.path,
    MATERIALIZATION_INPUTS.regression.identity, "SELF_TEST_SETUP_FAILED", "regression test").bytes;
  writeExclusive(join(materialization, "src/range.mjs"), source);
  writeExclusive(join(materialization, "test/issue.test.mjs"), issue);
  writeExclusive(join(materialization, "test/regression.test.mjs"), regression);
  runFixedGit(materialization, ["init", "--quiet", "--initial-branch=main"],
    "SELF_TEST_SETUP_FAILED", "fixture git init");
  runFixedGit(materialization,
    ["add", "--", "src/range.mjs", "test/issue.test.mjs", "test/regression.test.mjs"],
    "SELF_TEST_SETUP_FAILED", "fixture git add");
  const commitEnvironment = {
    GIT_AUTHOR_NAME: "SourceLens AIOS Fixture",
    GIT_AUTHOR_EMAIL: "fixture@sourcelens.local",
    GIT_AUTHOR_DATE: "2000-01-01T00:00:00Z",
    GIT_COMMITTER_NAME: "SourceLens AIOS Fixture",
    GIT_COMMITTER_EMAIL: "fixture@sourcelens.local",
    GIT_COMMITTER_DATE: "2000-01-01T00:00:00Z",
  };
  runFixedGit(materialization, ["commit", "--quiet", "--no-gpg-sign", "-m", "fixture: base"],
    "SELF_TEST_SETUP_FAILED", "fixture git commit", commitEnvironment);
  const head = runFixedGit(materialization, ["rev-parse", "HEAD"],
    "SELF_TEST_SETUP_FAILED", "fixture git HEAD").toString("utf8").trim();
  const tree = runFixedGit(materialization, ["rev-parse", "HEAD^{tree}"],
    "SELF_TEST_SETUP_FAILED", "fixture git tree").toString("utf8").trim();
  assert(head === BASE_COMMIT && tree === BASE_TREE,
    "SELF_TEST_SETUP_FAILED", "fixture base identity drifted");
  const compiled = compileFiniteTypedPatchIr(readFileSync(FILES.ir10));
  writeFileSync(join(materialization, "src/range.mjs"), compiled.postimage, { mode: 0o600 });
  const patch = runFixedGit(materialization,
    ["diff", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "--", "src/range.mjs"],
    "SELF_TEST_SETUP_FAILED", "fixture exact patch");
  assert(patch.equals(PATCH_BYTES), "SELF_TEST_SETUP_FAILED", "frozen patch bytes drifted from exact IR10 transformation");
  writeFileSync(join(materialization, "src/range.mjs"), source, { mode: 0o600 });
  const clean = runFixedGit(materialization,
    ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
    "SELF_TEST_SETUP_FAILED", "fixture rollback status");
  assert(clean.length === 0, "SELF_TEST_SETUP_FAILED", "fixture rollback is not clean");
  const stat = lstatSync(materialization);
  return {
    realpath: realpathSync(materialization),
    device: stat.dev,
    inode: stat.ino,
    uid: stat.uid,
    created_exclusive: true,
  };
}

function selfDirectoryReceipt(path) {
  const stat = lstatSync(path);
  return { realpath: realpathSync(path), device: stat.dev, inode: stat.ino, uid: stat.uid, created_exclusive: true };
}

function selfCreatedFileReceipt(pathRef, identity, discriminator = 0) {
  return {
    path_ref: pathRef,
    byte_length: identity.byte_length,
    sha256: identity.sha256,
    device: 1,
    inode: 10_000 + discriminator,
    uid: process.getuid(),
    regular: true,
    symlink: false,
    nlink: 1,
    created_exclusive: true,
  };
}

function buildSelfActionTrace({ runRoot, runId, repetitionId, candidate, candidateRepository,
  materializationReceipt, qualityFreezeReference, rawStreams, artifactRefs }) {
  const card = validateTaskCard();
  const actions = [];
  const add = (action_id, category, phase, tool_ordinal, request, outcome) => actions.push({
    sequence: actions.length + 1, action_id, category, phase, tool_ordinal, request, outcome,
  });
  const stream = (bytes, artifact_ref = null) => ({
    retention: "INLINE_EXACT_BYTES", encoding: "base64", bytes_base64: bytes.toString("base64"),
    byte_length: bytes.length, sha256: sha256(bytes), artifact_ref,
  });
  const processAction = (id, phase, ordinal, argv, cwd_ref, timeout_ms, exit_status, stdout, stderr,
    stdoutPath = undefined, stderrPath = undefined) => add(id, "PROCESS", phase, ordinal, {
      executable: argv[0], argv, cwd_ref, timeout_ms,
      environment_profile: "FIXED_MINIMAL_NON_SECRET", shell: false,
    }, {
      status: "COMPLETED", expected_exit_status: exit_status, exit_status, signal: null,
      terminated: true, descendants_alive: false,
      stdout: stream(stdout, stdoutPath ? artifactRefs[stdoutPath] : null),
      stderr: stream(stderr, stderrPath ? artifactRefs[stderrPath] : null),
    });
  processAction("candidate_git_head", "CANDIDATE_PREFLIGHT", null,
    [GIT_PATH, "-C", candidateRepository, "rev-parse", "HEAD"], "CANDIDATE_REPOSITORY", 15_000, 0,
    Buffer.from(`${candidate.commit}\n`), Buffer.alloc(0));
  processAction("candidate_git_tree", "CANDIDATE_PREFLIGHT", null,
    [GIT_PATH, "-C", candidateRepository, "rev-parse", "HEAD^{tree}"], "CANDIDATE_REPOSITORY", 15_000, 0,
    Buffer.from(`${candidate.tree}\n`), Buffer.alloc(0));
  processAction("candidate_git_status", "CANDIDATE_PREFLIGHT", null,
    [GIT_PATH, "-C", candidateRepository, "status", "--porcelain=v1", "-z", "--untracked-files=all"],
    "CANDIDATE_REPOSITORY", 15_000, 0, Buffer.alloc(0), Buffer.alloc(0));
  const modules = currentExecutingModuleIdentities();
  const qualityAssets = Object.fromEntries([
    ["target_runtime", "target-runtime-oci-manifest.json"], ["environment_snapshot", "environment-snapshot.json"],
    ["system_configuration", "system-configuration.json"], ["compatibility_profile", "compatibility-profile.json"],
    ["positive_tool_plan", "positive-tool-plan.json"], ["negative_cases", "negative-cases.json"],
  ].map(([name, filename]) => [name, fileIdentityReference(
    `evaluation-harness/fixtures/offline-b1-simple-tool-v1/${filename}`, IDENTITIES[name])]));
  const acceptedInputs = Object.fromEntries(Object.entries(card.accepted_inputs)
    .filter(([, record]) => record && typeof record.path === "string" && Number.isInteger(record.byte_length) && record.sha256)
    .map(([name, record]) => [name, fileIdentityReference(record.path, record)]));
  add("validate_quality_and_input_identities", "IDENTITY_VALIDATION", "FROZEN_INPUT_VALIDATION", null, {
    task_card: fileIdentityReference(EXECUTING_MODULE_PATHS.task_card, IDENTITIES.task_card),
    quality_freeze: qualityFreezeReference,
    quality_assets: qualityAssets,
    accepted_inputs: acceptedInputs,
    executing_modules: modules,
  }, {
    status: "VALIDATED_EXACT_IDENTITIES", all_regular: true, all_non_symlink: true,
    ownership_enforced: true, hardlink_policy_enforced: true,
  });
  processAction("actual_git_version", "EXECUTOR_EVIDENCE", null, [GIT_PATH, "--version"],
    "CANDIDATE_REPOSITORY", 10_000, 0,
    Buffer.from("git version 2.39.5 (Apple Git-154)\n"), Buffer.alloc(0));
  add("validate_closed_tool_plan_and_adapter_admission", "PLAN_ADMISSION", "PRE_ADMISSION", null, {
    tool_plan: fileIdentityReference(
      "evaluation-harness/fixtures/offline-b1-simple-tool-v1/positive-tool-plan.json", IDENTITIES.positive_tool_plan),
    ir10: fileIdentityReference(
      "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json", IDENTITIES.ir10),
    adapter: modules.adapter,
    task_spec: fileIdentityReference(card.accepted_inputs.task_spec.path, card.accepted_inputs.task_spec),
  }, {
    status: "ADMITTED_CLOSED_FINITE_TOOL_PLAN", admitted_action_count: 3,
    admitted_actions: clone(REQUIRED_STEPS), postimage: { byte_length: 127, sha256: POSTIMAGE_SHA256 },
    external_effects: { ...FALSE_EFFECTS },
  });
  const runReceipt = selfDirectoryReceipt(runRoot);
  add("create_exclusive_run_root", "DIRECTORY_CREATION", "EVIDENCE_INITIALIZATION", null, {
    parent_ref: "EVIDENCE_ROOT", run_id: runId, creation_policy: "EXCLUSIVE_NOFOLLOW_OWNED_DIRECTORY",
  }, { status: "CREATED_EXCLUSIVE", receipt: runReceipt });
  const materializationPath = join(runRoot, "materialization");
  add("create_exclusive_materialization_root", "DIRECTORY_CREATION", "MATERIALIZATION", null, {
    parent_ref: "RUN_ROOT", required_children: ["materialization", "home", "materialization/src", "materialization/test"],
  }, {
    status: "CREATED_EXCLUSIVE", materialization_receipt: materializationReceipt,
    home_receipt: selfDirectoryReceipt(join(runRoot, "home")),
    source_directory_receipt: selfDirectoryReceipt(join(materializationPath, "src")),
    test_directory_receipt: selfDirectoryReceipt(join(materializationPath, "test")),
  });
  const sourceInputs = [
    { name: "source_preimage", path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/src/range.mjs", byte_length: 115, sha256: PREIMAGE_SHA256, destination: "src/range.mjs" },
    { name: "issue_test", path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/test/issue.test.mjs", byte_length: 237, sha256: "51fd472f8cf85fd595246814db29699ab81ccdc2986d80666d8609a8c4972b4b", destination: "test/issue.test.mjs" },
    { name: "regression_test", path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/test/regression.test.mjs", byte_length: 241, sha256: "381c573d8f99305b47db9f1a2ca49779842fe1187b9d7c5b7410e56dda9240c5", destination: "test/regression.test.mjs" },
  ];
  add("materialize_source_inputs", "FILE_CREATION", "MATERIALIZATION", null, {
    source_count: 3, sources: sourceInputs.map(({ destination, ...rest }) => rest),
  }, {
    status: "MATERIALIZED_EXACT_BYTES",
    files: sourceInputs.map((source, index) => ({ name: source.name,
      ...selfCreatedFileReceipt(source.destination, source, index + 1) })),
  });
  const gitProcess = [
    ["materialize_git_init", "MATERIALIZATION", [GIT_PATH, "init", "--quiet", "--initial-branch=main"], Buffer.alloc(0)],
    ["materialize_git_add", "MATERIALIZATION", [GIT_PATH, "add", "--", "src/range.mjs", "test/issue.test.mjs", "test/regression.test.mjs"], Buffer.alloc(0)],
    ["materialize_git_commit", "MATERIALIZATION", [GIT_PATH, "commit", "--quiet", "--no-gpg-sign", "-m", "fixture: base"], Buffer.alloc(0)],
    ["base_git_head", "BASE_PRECONDITION", [GIT_PATH, "rev-parse", "HEAD"], Buffer.from(`${BASE_COMMIT}\n`)],
    ["base_git_tree", "BASE_PRECONDITION", [GIT_PATH, "rev-parse", "HEAD^{tree}"], Buffer.from(`${BASE_TREE}\n`)],
    ["base_git_status", "BASE_PRECONDITION", [GIT_PATH, "status", "--porcelain=v1", "-z", "--untracked-files=all"], Buffer.alloc(0)],
  ];
  for (const [id, phase, argv, stdout] of gitProcess) {
    processAction(id, phase, null, argv, "TASK_REPOSITORY", 10_000, 0, stdout, Buffer.alloc(0));
  }
  processAction("base_issue_test", "BASE_PRECONDITION", null, [...ISSUE_ARGV], "TASK_REPOSITORY", 10_000, 1,
    rawStreams.get("base-issue.stdout"), rawStreams.get("base-issue.stderr"), "base-issue.stdout", "base-issue.stderr");
  processAction("base_regression_test", "BASE_PRECONDITION", null, [...REGRESSION_ARGV], "TASK_REPOSITORY", 10_000, 0,
    rawStreams.get("base-regression.stdout"), rawStreams.get("base-regression.stderr"), "base-regression.stdout", "base-regression.stderr");
  const toolRequest = (ordinal) => {
    const step = REQUIRED_STEPS[ordinal - 1];
    add(`tool_step_${ordinal}_request`, "TOOL_REQUEST", "TOOL_ACTION", ordinal, {
      plan_step: step, operation_mapping: card.fixed_operation_mapping[`${step.tool_id}/${step.operation_id}`],
    }, {
      status: "REQUEST_ACCEPTED_FROM_CLOSED_PLAN", plan_id: "P1-067-REP001-IR10-THREE-STEP-PLAN",
      adapter_version: "OFFLINE-B1-FINITE-TOOL-ADAPTER/1", dynamic_controls_admitted: false,
      external_effects: { ...FALSE_EFFECTS },
    });
  };
  toolRequest(1);
  const postReceipt = selfCreatedFileReceipt("src/range.mjs", { byte_length: 127, sha256: POSTIMAGE_SHA256 }, 20);
  add("tool_step_1_atomic_postimage", "FILE_MUTATION", "TOOL_ACTION", 1, {
    target_path: "src/range.mjs", mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT",
    preimage: { byte_length: 115, sha256: PREIMAGE_SHA256 }, postimage: { byte_length: 127, sha256: POSTIMAGE_SHA256 },
    compiler: fileIdentityReference(card.accepted_inputs.compiler.path, card.accepted_inputs.compiler),
    ir10: fileIdentityReference("evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json", IDENTITIES.ir10),
  }, {
    status: "ATOMIC_POSTIMAGE_APPLIED", atomic_rename: true,
    temporary_receipt: Object.fromEntries(Object.entries(postReceipt).filter(([key]) => !["path_ref", "byte_length", "sha256"].includes(key))),
    source: postReceipt,
  });
  processAction("changed_path_git_status", "PATCH_EVIDENCE", 1,
    [GIT_PATH, "status", "--porcelain=v1", "-z", "--untracked-files=all"], "TASK_REPOSITORY", 10_000, 0,
    Buffer.from(" M src/range.mjs\0"), Buffer.alloc(0));
  processAction("patch_git_diff", "PATCH_EVIDENCE", 1,
    [GIT_PATH, "diff", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "--", "src/range.mjs"],
    "TASK_REPOSITORY", 10_000, 0, PATCH_BYTES, Buffer.alloc(0));
  add("patch_capture", "ARTIFACT_CREATION", "PATCH_EVIDENCE", 1, {
    source_action_id: "patch_git_diff", path: "patch.diff",
    creation_policy: "CREATE_ONCE_REGULAR_NOFOLLOW_NLINK_ONE",
  }, { status: "CAPTURED_EXACT_PATCH", artifact: artifactRefs["patch.diff"] });
  toolRequest(2);
  processAction("tool_issue_test", "TOOL_ACTION", 2, [...ISSUE_ARGV], "TASK_REPOSITORY", 10_000, 0,
    rawStreams.get("tool-issue.stdout"), rawStreams.get("tool-issue.stderr"), "tool-issue.stdout", "tool-issue.stderr");
  toolRequest(3);
  processAction("tool_regression_test", "TOOL_ACTION", 3, [...REGRESSION_ARGV], "TASK_REPOSITORY", 10_000, 0,
    rawStreams.get("tool-regression.stdout"), rawStreams.get("tool-regression.stderr"), "tool-regression.stdout", "tool-regression.stderr");
  const restoredReceipt = selfCreatedFileReceipt("src/range.mjs", { byte_length: 115, sha256: PREIMAGE_SHA256 }, 21);
  add("rollback_atomic_restore", "FILE_MUTATION", "ROLLBACK", null, {
    target_path: "src/range.mjs", mutation_kind: "ATOMIC_COMPLETE_PREIMAGE_RESTORATION",
    current: { byte_length: 127, sha256: POSTIMAGE_SHA256 }, restore: { byte_length: 115, sha256: PREIMAGE_SHA256 },
  }, {
    status: "ATOMIC_PREIMAGE_RESTORED", atomic_rename: true,
    temporary_receipt: Object.fromEntries(Object.entries(restoredReceipt).filter(([key]) => !["path_ref", "byte_length", "sha256"].includes(key))),
    source: restoredReceipt,
  });
  for (const [id, argv, stdout] of [
    ["rollback_git_head", [GIT_PATH, "rev-parse", "HEAD"], Buffer.from(`${BASE_COMMIT}\n`)],
    ["rollback_git_tree", [GIT_PATH, "rev-parse", "HEAD^{tree}"], Buffer.from(`${BASE_TREE}\n`)],
    ["rollback_git_status", [GIT_PATH, "status", "--porcelain=v1", "-z", "--untracked-files=all"], Buffer.alloc(0)],
  ]) processAction(id, "ROLLBACK", null, argv, "TASK_REPOSITORY", 10_000, 0, stdout, Buffer.alloc(0));
  add("rollback_source_check", "VERIFICATION", "ROLLBACK", null, {
    expected_source: { byte_length: 115, sha256: PREIMAGE_SHA256 }, expected_head: BASE_COMMIT,
    expected_tree: BASE_TREE, expected_clean: true,
  }, {
    status: "EXACT_BASE_RESTORED", source: restoredReceipt, head: BASE_COMMIT, tree: BASE_TREE,
    clean: true, extra_paths: [],
  });
  add("retained_evidence_policy", "EVIDENCE_RETENTION", "ROLLBACK", null, {
    materialization_root_ref: "MATERIALIZATION_ROOT", policy: "RETAIN_FOR_INDEPENDENT_EVALUATION_NO_CLEANUP",
  }, {
    status: "RETAINED_EXACT_MATERIALIZATION", materialization_receipt: materializationReceipt,
    deleted_paths: [], temporary_residue: false, preexisting_objects_touched: false,
  });
  assert(sameJson(actions.map(({ action_id }) => action_id),
    card.run_evidence_contract.action_trace_required_action_ids),
  "SELF_TEST_SETUP_FAILED", "self-test action trace order drifted");
  return {
    schema_version: 1, record_type: "sourcelens_aios_p1_067_complete_action_trace",
    task_id: TASK_ID, control_id: CONTROL_ID, run_id: runId, repetition_id: repetitionId,
    action_count: actions.length, actions,
  };
}

function buildSelfPatchEvidencePackage({ runId, repetitionId, candidate, artifactRefs, artifactChecksums,
  actionTrace, materializationReceipt }) {
  const card = validateTaskCard();
  const testValue = (name, definition) => ({
    action_id: definition.action_id,
    expected_exit_status: definition.exit_status,
    observed_exit_status: definition.exit_status,
    stdout: artifactRefs[definition.stdout_path],
    stderr: artifactRefs[definition.stderr_path],
  });
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_patch_evidence_package",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    repetition_id: repetitionId,
    manifest: { candidate_binding: candidate, artifact_checksums: artifactChecksums },
    source_identity: {
      repository_identity: "sourcelens-fixture://p1-representative-tasks/SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0",
      base: { commit: BASE_COMMIT, tree: BASE_TREE, clean: true },
      target_path: "src/range.mjs",
      preimage: { byte_length: 115, sha256: PREIMAGE_SHA256 },
      accepted_postimage: { byte_length: 127, sha256: POSTIMAGE_SHA256 },
      final: { source: { byte_length: 115, sha256: PREIMAGE_SHA256 }, head: BASE_COMMIT, tree: BASE_TREE, clean: true },
    },
    environment: {
      target_runtime: fileIdentityReference("evaluation-harness/fixtures/offline-b1-simple-tool-v1/target-runtime-oci-manifest.json", IDENTITIES.target_runtime),
      environment_snapshot: fileIdentityReference("evaluation-harness/fixtures/offline-b1-simple-tool-v1/environment-snapshot.json", IDENTITIES.environment_snapshot),
      system_configuration: fileIdentityReference("evaluation-harness/fixtures/offline-b1-simple-tool-v1/system-configuration.json", IDENTITIES.system_configuration),
      compatibility_profile: fileIdentityReference("evaluation-harness/fixtures/offline-b1-simple-tool-v1/compatibility-profile.json", IDENTITIES.compatibility_profile),
      actual_executor: artifactRefs["actual-executor.json"],
    },
    understanding: {
      task_spec: fileIdentityReference(card.accepted_inputs.task_spec.path, card.accepted_inputs.task_spec),
      issue: "normalizeRange preserves reversed bounds instead of normalizing them",
      expected_base_failure: fileIdentityReference(card.accepted_inputs.expected_base_failure.path, card.accepted_inputs.expected_base_failure),
      observed_base_issue_action_id: "base_issue_test",
    },
    plan: {
      artifact: artifactRefs["tool-plan.json"],
      admission_status: "ADMITTED_CLOSED_FINITE_TOOL_PLAN",
      adapter_version: "OFFLINE-B1-FINITE-TOOL-ADAPTER/1",
      plan_id: "P1-067-REP001-IR10-THREE-STEP-PLAN",
      fixed_step_count: 3,
      steps: clone(REQUIRED_STEPS),
      external_effects: { ...FALSE_EFFECTS },
    },
    actions: {
      action_trace: artifactRefs["action-trace.json"],
      ordered_action_ids: actionTrace.actions.map(({ action_id }) => action_id),
      tool_step_bindings: [
        { ordinal: 1, tool_id: "local-file-edit", operation_id: "apply-finite-typed-patch-ir", request_action_id: "tool_step_1_request", outcome_action_id: "tool_step_1_atomic_postimage" },
        { ordinal: 2, tool_id: "local-node-test", operation_id: "issue-test", request_action_id: "tool_step_2_request", outcome_action_id: "tool_issue_test" },
        { ordinal: 3, tool_id: "local-node-test", operation_id: "regression-test", request_action_id: "tool_step_3_request", outcome_action_id: "tool_regression_test" },
      ],
    },
    patch: {
      changed_paths: ["src/range.mjs"], artifact: artifactRefs["patch.diff"],
      preimage: { byte_length: 115, sha256: PREIMAGE_SHA256 },
      postimage: { byte_length: 127, sha256: POSTIMAGE_SHA256 },
      compiler: fileIdentityReference(card.accepted_inputs.compiler.path, card.accepted_inputs.compiler),
      ir10: fileIdentityReference("evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json", IDENTITIES.ir10),
      mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT",
    },
    tests: {
      base_issue: testValue("base_issue", COMMAND_DEFINITIONS[0]),
      base_regression: testValue("base_regression", COMMAND_DEFINITIONS[1]),
      patched_issue: testValue("patched_issue", COMMAND_DEFINITIONS[2]),
      patched_regression: testValue("patched_regression", COMMAND_DEFINITIONS[3]),
    },
    verification: {
      status: "PENDING_INDEPENDENT_EVALUATION",
      evaluator: { ...currentExecutingModuleIdentities().quality_oracle, version: QUALITY_ORACLE_VERSION },
      verdict: null,
      runner_reported_pass_authoritative: false,
      adapter_reported_pass_authoritative: false,
    },
    risk: {
      claim_boundary: CLAIM, external_effects: { ...FALSE_EFFECTS }, dynamic_controls_admitted: false,
      free_form_execution_admitted: false, child_process_group_termination_enforced: true,
      preexisting_object_overwrite_or_cleanup: false,
    },
    approval: {
      status: "PENDING_TASK_GATE", self_approval: false,
      independent_quality_required: true, task_gate_claimed: false,
    },
    rollback: {
      artifact: artifactRefs["rollback.json"], materialization_receipt: materializationReceipt,
      mutation_occurred: true, restored_source: { byte_length: 115, sha256: PREIMAGE_SHA256 },
      head: BASE_COMMIT, tree: BASE_TREE, clean: true, extra_paths: [],
      retained_materialization: true, cleanup_performed: false,
    },
  };
}

function createPhysicalRun(parent, runId, repetitionId, options = {}) {
  const runRoot = join(parent, runId);
  mkdirSync(runRoot, { mode: 0o700 });
  const materializationReceipt = initializePhysicalMaterialization(runRoot);
  const candidate = options.candidate ?? { commit: "a".repeat(40), tree: "b".repeat(40), clean: true };
  const observation = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_run_observation",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    repetition_id: repetitionId,
    candidate_binding: clone(candidate),
    input_identities: {
      task_spec_sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
      source_preimage_sha256: PREIMAGE_SHA256,
      postimage_sha256: POSTIMAGE_SHA256,
    },
    plan_identity: {
      byte_length: IDENTITIES.positive_tool_plan.byte_length,
      sha256: IDENTITIES.positive_tool_plan.sha256,
    },
    agent_status: "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED",
  };
  const rollbackReceipt = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_rollback_receipt",
    present: true,
    run_id: runId,
    mutation_occurred: true,
    restored_source_byte_length: 115,
    source_sha256: PREIMAGE_SHA256,
    head: BASE_COMMIT,
    tree: BASE_TREE,
    clean: true,
    extra_paths: [],
  };
  const rawStreams = new Map([
    ["base-issue.stdout", Buffer.from("not ok 1 - REP001_NEGATIVE_RANGE_ORDER\n", "utf8")],
    ["base-issue.stderr", Buffer.alloc(0)],
    ["base-regression.stdout", Buffer.from("ok 1 - ordered ranges remain unchanged\n", "utf8")],
    ["base-regression.stderr", Buffer.alloc(0)],
    ["tool-issue.stdout", Buffer.from("ok 1 - REP001_NEGATIVE_RANGE_ORDER\n", "utf8")],
    ["tool-issue.stderr", Buffer.alloc(0)],
    ["tool-regression.stdout", Buffer.from("ok 1 - ordered ranges remain unchanged\n", "utf8")],
    ["tool-regression.stderr", Buffer.alloc(0)],
  ]);
  if (options.rawStreamMutation) options.rawStreamMutation(rawStreams);
  const streamReference = (path) => {
    const bytes = rawStreams.get(path);
    return { path, byte_length: bytes.length, sha256: sha256(bytes) };
  };
  const commandStream = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_command_stream_index",
    run_id: runId,
    commands: COMMAND_DEFINITIONS.map((command) => ({
      action_id: command.action_id,
      phase: command.phase,
      tool_ordinal: command.tool_ordinal,
      argv: [...command.argv],
      cwd_ref: "TASK_REPOSITORY",
      timeout_ms: 10_000,
      exit_status: command.exit_status,
      signal: null,
      terminated: true,
      descendants_alive: false,
      stdout: streamReference(command.stdout_path),
      stderr: streamReference(command.stderr_path),
    })),
  };
  if (options.commandMutation) options.commandMutation(commandStream);
  const baseValues = [
    ["candidate_provenance", "candidate-provenance.json", canonicalJsonBytes({
      schema_version: 1,
      record_type: "sourcelens_aios_p1_067_run_provenance",
      run_id: runId,
      candidate_binding: candidate,
    })],
    ["tool_plan", "tool-plan.json", readFileSync(FILES.positive_tool_plan)],
    ["observation", "observation.json", canonicalJsonBytes(observation)],
    ["patch", "patch.diff", options.patchBytes ?? PATCH_BYTES],
    ["rollback", "rollback.json", canonicalJsonBytes(rollbackReceipt)],
    ["command_stream", "command-stream.json", canonicalJsonBytes(commandStream)],
    ...COMMAND_DEFINITIONS.flatMap((command) => [
      ["raw_stream", command.stdout_path, rawStreams.get(command.stdout_path)],
      ["raw_stream", command.stderr_path, rawStreams.get(command.stderr_path)],
    ]),
  ];
  const referenceOf = (path, bytes) => ({ path, byte_length: bytes.length, sha256: sha256(bytes) });
  const artifactRefs = Object.fromEntries(baseValues.map(([, path, bytes]) => [path, referenceOf(path, bytes)]));
  const actualExecutorBytes = canonicalJsonBytes({
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_actual_executor_evidence",
    run_id: runId,
    ...actualExecutorObservation(),
  });
  artifactRefs["actual-executor.json"] = referenceOf("actual-executor.json", actualExecutorBytes);
  const actionTrace = buildSelfActionTrace({
    runRoot,
    runId,
    repetitionId,
    candidate,
    candidateRepository: options.candidateRepository,
    materializationReceipt,
    qualityFreezeReference: options.qualityFreezeReference,
    rawStreams,
    artifactRefs,
  });
  const actionTraceBytes = canonicalJsonBytes(actionTrace);
  artifactRefs["action-trace.json"] = referenceOf("action-trace.json", actionTraceBytes);
  const packageBoundValues = [
    ...baseValues,
    ["actual_executor", "actual-executor.json", actualExecutorBytes],
    ["action_trace", "action-trace.json", actionTraceBytes],
  ];
  const packageChecksums = Object.fromEntries(packageBoundValues
    .map(([, path, bytes]) => [path, sha256(bytes)])
    .sort(([left], [right]) => left.localeCompare(right)));
  const patchEvidenceBytes = canonicalJsonBytes(buildSelfPatchEvidencePackage({
    runId,
    repetitionId,
    candidate,
    artifactRefs,
    artifactChecksums: packageChecksums,
    actionTrace,
    materializationReceipt,
  }));
  artifactRefs["patch-evidence-package.json"] = referenceOf("patch-evidence-package.json", patchEvidenceBytes);
  const allBeforeRecord = [
    ...packageBoundValues,
    ["patch_evidence_package", "patch-evidence-package.json", patchEvidenceBytes],
  ];
  const runRecordChecksums = Object.fromEntries(allBeforeRecord
    .map(([, path, bytes]) => [path, sha256(bytes)])
    .sort(([left], [right]) => left.localeCompare(right)));
  const runRecordBytes = canonicalJsonBytes(buildRunRecord(runId, repetitionId, runRecordChecksums));
  const byPath = new Map(allBeforeRecord.map((entry) => [entry[1], entry]));
  byPath.set("run-record.json", ["run_record", "run-record.json", runRecordBytes]);
  const values = [
    ...REQUIRED_ARTIFACT_LAYOUT.map(({ role, path }) => {
      const value = byPath.get(path);
      assert(value?.[0] === role, "SELF_TEST_SETUP_FAILED", `missing self-test artifact ${role}/${path}`);
      return value;
    }),
  ];
  assert(values.length === REQUIRED_ARTIFACT_LAYOUT.length && values.every(([role, path], index) =>
    role === REQUIRED_ARTIFACT_LAYOUT[index].role && path === REQUIRED_ARTIFACT_LAYOUT[index].path),
  "SELF_TEST_SETUP_FAILED", "physical fixture artifact layout drifted");
  for (const [, name, bytes] of values) writeExclusive(join(runRoot, name), bytes);
  const runStat = lstatSync(runRoot);
  const manifest = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_run_manifest",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: runId,
    repetition_id: repetitionId,
    candidate_binding: candidate,
    run_root_receipt: {
      realpath: realpathSync(runRoot),
      device: runStat.dev,
      inode: runStat.ino,
      uid: runStat.uid,
      created_exclusive: options.createdExclusive ?? true,
    },
    materialization_receipt: materializationReceipt,
    artifacts: values.map(([role, name, bytes]) => artifactEntry(role, name, runId, bytes)),
    agent_status: "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED",
  };
  if (options.manifestMutation) options.manifestMutation(manifest);
  const manifestPath = join(runRoot, "manifest.json");
  writeExclusive(manifestPath, canonicalJsonBytes(manifest));
  return { runRoot, manifestPath, manifest };
}

function rewriteManifest(fixture, mutate) {
  const manifest = parseJson(readFileSync(fixture.manifestPath), "SELF_TEST_SETUP_FAILED", "fixture manifest");
  mutate(manifest);
  writeFileSync(fixture.manifestPath, canonicalJsonBytes(manifest), { mode: 0o600 });
}

function replaceArtifact(fixture, role, bytes, updateManifest = true) {
  const entry = fixture.manifest.artifacts.find((item) => item.role === role);
  const target = join(fixture.runRoot, entry.path);
  writeFileSync(target, bytes, { mode: 0o600 });
  if (updateManifest) {
    rewriteManifest(fixture, (manifest) => {
      const current = manifest.artifacts.find((item) => item.role === role);
      current.byte_length = bytes.length;
      current.sha256 = sha256(bytes);
    });
  }
}

function rewriteEvidenceArtifactCoherently(fixture, role, mutate) {
  const manifest = parseJson(readFileSync(fixture.manifestPath),
    "SELF_TEST_SETUP_FAILED", "coherent fixture manifest", true);
  const target = manifest.artifacts.find((entry) => entry.role === role);
  assert(target, "SELF_TEST_SETUP_FAILED", `coherent fixture role ${role} is missing`);
  const targetPath = join(fixture.runRoot, target.path);
  const value = parseJson(readFileSync(targetPath), "SELF_TEST_SETUP_FAILED", `coherent ${role}`, true);
  mutate(value);
  const bytes = canonicalJsonBytes(value);
  writeFileSync(targetPath, bytes, { mode: 0o600 });
  target.byte_length = bytes.length;
  target.sha256 = sha256(bytes);
  const changed = new Map([[target.path, target.sha256]]);
  if (role === "action_trace" || role === "actual_executor") {
    const packageEntry = manifest.artifacts.find((entry) => entry.role === "patch_evidence_package");
    const packagePath = join(fixture.runRoot, packageEntry.path);
    const packageValue = parseJson(readFileSync(packagePath),
      "SELF_TEST_SETUP_FAILED", "coherent Patch Evidence Package", true);
    packageValue.manifest.artifact_checksums[target.path] = target.sha256;
    const reference = { path: target.path, byte_length: target.byte_length, sha256: target.sha256 };
    if (role === "action_trace") packageValue.actions.action_trace = reference;
    else packageValue.environment.actual_executor = reference;
    const packageBytes = canonicalJsonBytes(packageValue);
    writeFileSync(packagePath, packageBytes, { mode: 0o600 });
    packageEntry.byte_length = packageBytes.length;
    packageEntry.sha256 = sha256(packageBytes);
    changed.set(packageEntry.path, packageEntry.sha256);
  }
  const runRecordEntry = manifest.artifacts.find((entry) => entry.role === "run_record");
  const runRecordPath = join(fixture.runRoot, runRecordEntry.path);
  const runRecord = parseJson(readFileSync(runRecordPath), "SELF_TEST_SETUP_FAILED", "coherent RunRecord", true);
  for (const [path, hash] of changed) runRecord.artifact_checksums[path] = hash;
  const runRecordBytes = canonicalJsonBytes(runRecord);
  writeFileSync(runRecordPath, runRecordBytes, { mode: 0o600 });
  runRecordEntry.byte_length = runRecordBytes.length;
  runRecordEntry.sha256 = sha256(runRecordBytes);
  writeFileSync(fixture.manifestPath, canonicalJsonBytes(manifest), { mode: 0o600 });
}

function createPhysicalNegativeFixture(parent, testCase, runB, sharedOptions) {
  const id = `negative-${testCase.id}`;
  const failureKind = testCase.id.startsWith("timeout-")
    ? "timeout"
    : testCase.id.startsWith("output-overflow-")
      ? "output_overflow"
      : testCase.id.startsWith("signal-")
        ? "signal"
        : null;
  const fixture = createPhysicalRun(parent, id, 1, {
    ...sharedOptions,
    createdExclusive: testCase.id !== "preexisting-evidence",
    commandMutation: failureKind
      ? (commandStream) => {
          const command = commandStream.commands.at(-1);
          command.terminated = false;
          command.descendants_alive = true;
        }
      : undefined,
  });
  if (failureKind) return fixture;
  if (testCase.id === "evidence-path-escape") {
    rewriteManifest(fixture, (manifest) => { manifest.artifacts[0].path = "../escape"; });
  } else if (testCase.id === "evidence-symlink") {
    const entry = fixture.manifest.artifacts[0];
    const target = join(fixture.runRoot, entry.path);
    const source = join(fixture.runRoot, "symlink-source.bin");
    writeExclusive(source, readFileSync(target));
    unlinkSync(target);
    symlinkSync(source, target);
  } else if (testCase.id === "evidence-hardlink") {
    const entry = fixture.manifest.artifacts[0];
    const target = join(fixture.runRoot, entry.path);
    const source = join(fixture.runRoot, "hardlink-source.bin");
    writeExclusive(source, readFileSync(target));
    unlinkSync(target);
    linkSync(source, target);
  } else if (testCase.id === "evidence-tamper") {
    const entry = fixture.manifest.artifacts[0];
    writeFileSync(join(fixture.runRoot, entry.path), Buffer.from("tampered", "utf8"), { mode: 0o600 });
  } else if (testCase.id.startsWith("cross-run-")) {
    const role = {
      "cross-run-observation": "observation",
      "cross-run-run-record": "run_record",
      "cross-run-provenance": "candidate_provenance",
      "cross-run-rollback": "rollback",
    }[testCase.id];
    const otherEntry = runB.manifest.artifacts.find((item) => item.role === role);
    replaceArtifact(fixture, role, readFileSync(join(runB.runRoot, otherEntry.path)), true);
  } else if (testCase.id === "rollback-omission") {
    rewriteManifest(fixture, (manifest) => {
      manifest.artifacts = manifest.artifacts.filter((entry) => entry.role !== "rollback");
    });
  }
  return fixture;
}

function expectCode(expected, action) {
  try {
    action();
  } catch (error) {
    if (error instanceof QualityOracleError && error.code === expected) return;
    throw error;
  }
  fail("SELF_TEST_FALSE_ACCEPT", `expected ${expected}`);
}

function planMutation(id, positive) {
  const plan = clone(positive);
  if (id === "unknown-root-member") plan.extra = true;
  else if (id === "record-type-drift") plan.record_type = "wrong";
  else if (id === "task-identity-drift") plan.task_binding.task_id = "wrong";
  else if (id === "task-spec-hash-drift") plan.task_binding.task_spec_sha256 = "0".repeat(64);
  else if (id === "configuration-identity-drift") plan.configuration_binding.sha256 = "0".repeat(64);
  else if (id === "profile-identity-drift") plan.compatibility_profile_binding.sha256 = "0".repeat(64);
  else if (id === "live-model-provenance") plan.provenance.live_model_invoked = true;
  else if (id === "missing-step") plan.steps.pop();
  else if (id === "over-budget-step") plan.steps.push({ ordinal: 4, tool_id: "local-node-test", operation_id: "issue-test" });
  else if (id === "step-gap") plan.steps[1].ordinal = 3;
  else if (id === "duplicate-ordinal") plan.steps[1].ordinal = 1;
  else if (id === "reordered-steps") [plan.steps[1], plan.steps[2]] = [plan.steps[2], plan.steps[1]];
  else if (id === "forbidden-tool") plan.steps[0].tool_id = "shell";
  else if (id === "unsupported-operation") plan.steps[0].operation_id = "arbitrary";
  else if (id === "unknown-step-member") plan.steps[0].unexpected = true;
  else if (id.startsWith("dynamic-")) plan.steps[0][id.slice("dynamic-".length)] = "attacker-controlled";
  else if (id.startsWith("external-")) plan.requested_external_effects[id.slice("external-".length)] = true;
  else fail("SELF_TEST_SETUP_FAILED", `unknown plan case ${id}`);
  return canonicalJsonBytes(plan);
}

const delay = (milliseconds) => new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

function processGroupAlive(pid) {
  try {
    process.kill(-pid, 0);
    return true;
  } catch (error) {
    if (error?.code === "ESRCH") return false;
    throw error;
  }
}

function signalProcessGroup(pid, signal) {
  try {
    process.kill(-pid, signal);
  } catch (error) {
    if (error?.code !== "ESRCH") throw error;
  }
}

async function exerciseChildTermination(failureKind) {
  assert(["timeout", "output_overflow", "signal"].includes(failureKind),
    "SELF_TEST_SETUP_FAILED", "unknown child termination fixture");
  const outputLoop = failureKind === "output_overflow"
    ? 'setInterval(() => process.stdout.write("x".repeat(4096)), 1);'
    : "";
  const source = `
    const { spawn } = require("node:child_process");
    const descendant = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000);"], { stdio: "ignore" });
    descendant.once("spawn", () => {
      process.stdout.write("DESCENDANT_READY\\n");
      ${outputLoop}
    });
    setInterval(() => {}, 1000);
  `;
  let child;
  let terminationTriggered = false;
  let observedOutputBytes = 0;
  let descendantReady = false;
  let closeResult;
  let triggerTimer;
  let graceTimer;
  let watchdog;
  try {
    child = spawn("/usr/local/bin/node", ["-e", source], {
      shell: false,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: FIXED_PROCESS_ENV,
    });
    assert(Number.isInteger(child.pid) && child.pid > 0, "SELF_TEST_SETUP_FAILED", "child did not start");
    const terminate = () => {
      if (terminationTriggered) return;
      terminationTriggered = true;
      signalProcessGroup(child.pid, "SIGTERM");
      graceTimer = setTimeout(() => signalProcessGroup(child.pid, "SIGKILL"), 100);
    };
    let captured = Buffer.alloc(0);
    child.stdout.on("data", (chunk) => {
      observedOutputBytes += chunk.length;
      if (captured.length < 65_536) captured = Buffer.concat([captured, chunk]).subarray(0, 65_536);
      if (!descendantReady && captured.includes(Buffer.from("DESCENDANT_READY\n", "utf8"))) {
        descendantReady = true;
        if (failureKind !== "output_overflow") triggerTimer = setTimeout(terminate, 20);
      }
      if (failureKind === "output_overflow" && observedOutputBytes > 8_192) terminate();
    });
    child.stderr.resume();
    watchdog = setTimeout(() => {
      terminate();
      signalProcessGroup(child.pid, "SIGKILL");
    }, 1_500);
    closeResult = await Promise.race([
      new Promise((resolvePromise, rejectPromise) => {
        child.once("error", rejectPromise);
        child.once("close", (code, signal) => resolvePromise({ code, signal }));
      }),
      delay(2_500).then(() => fail("SELF_TEST_SETUP_FAILED", `${failureKind} child close timed out`)),
    ]);
  } finally {
    if (triggerTimer) clearTimeout(triggerTimer);
    if (graceTimer) clearTimeout(graceTimer);
    if (watchdog) clearTimeout(watchdog);
    if (child?.pid && processGroupAlive(child.pid)) {
      signalProcessGroup(child.pid, "SIGKILL");
      for (let attempt = 0; attempt < 50 && processGroupAlive(child.pid); attempt += 1) await delay(10);
    }
  }
  assert(descendantReady && terminationTriggered && !processGroupAlive(child.pid) && closeResult?.code === null &&
    (closeResult.signal === "SIGTERM" || closeResult.signal === "SIGKILL"),
  "SELF_TEST_SETUP_FAILED", `${failureKind} child process group was not terminated`);
  if (failureKind === "output_overflow") {
    assert(observedOutputBytes > 8_192, "SELF_TEST_SETUP_FAILED", "output limit was not crossed");
  }
  return {
    failure_kind: failureKind,
    child_started: true,
    descendant_started: true,
    termination_triggered: true,
    process_group_gone: true,
  };
}

async function selfTest() {
  const assets = validateQualityAssets();
  const positive = assets.plan;
  const negative = readExact(FILES.negative_cases, IDENTITIES.negative_cases, "negative cases").value;
  const temporary = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-067-quality-"));
  const temporaryStat = lstatSync(temporary);
  const markerPath = join(temporary, ".owned-quality-self-test");
  const markerBytes = Buffer.from("P1-067-QUALITY-SELF-TEST\n", "utf8");
  writeExclusive(markerPath, markerBytes);
  try {
    const freeze = createSelfQualityFreeze(temporary);
    const candidateContainer = join(temporary, "candidate-repository-container");
    mkdirSync(candidateContainer, { mode: 0o700 });
    const candidateReceipt = initializePhysicalMaterialization(candidateContainer);
    const candidateRepository = candidateReceipt.realpath;
    const sharedOptions = {
      candidate: { commit: BASE_COMMIT, tree: BASE_TREE, clean: true },
      candidateRepository,
      qualityFreezeReference: freeze.reference,
    };
    const evaluationOptions = {
      allowedRoot: temporary,
      candidateRepository,
      qualityFreezeRoot: freeze.root,
    };
    const makeRun = (id, repetition, extra = {}) =>
      createPhysicalRun(temporary, id, repetition, { ...sharedOptions, ...extra });
    const evaluate = (fixture) => evaluateRunEvidence(fixture.manifestPath, evaluationOptions);
    const physicalRunA = makeRun("physical-run-a", 1);
    const physicalRunB = makeRun("physical-run-b", 2);
    const runA = evaluate(physicalRunA);
    const runB = evaluate(physicalRunB);
    compareStableRuns(runA, runB);
    const completeEvidenceNegativeOutcomes = [];
    for (const section of validateTaskCard().run_evidence_contract.patch_evidence_package_mandatory_sections) {
      const fixture = makeRun(`complete-evidence-missing-${section.replaceAll("_", "-")}`, 10);
      rewriteEvidenceArtifactCoherently(fixture, "patch_evidence_package", (value) => { delete value[section]; });
      expectCode("PATCH_EVIDENCE_PACKAGE_REJECTED", () => evaluate(fixture));
      completeEvidenceNegativeOutcomes.push({
        id: `missing-package-section-${section}`,
        expected_reason_code: "PATCH_EVIDENCE_PACKAGE_REJECTED",
        result: "PASS_REJECTED_AS_EXPECTED",
      });
    }
    for (const [role, id] of [["action_trace", "missing-action-trace"], ["actual_executor", "missing-actual-executor"]]) {
      const fixture = makeRun(`complete-evidence-${id}`, 11);
      rewriteManifest(fixture, (manifest) => {
        manifest.artifacts = manifest.artifacts.filter((entry) => entry.role !== role);
      });
      expectCode("EVIDENCE_IDENTITY_REJECTED", () => evaluate(fixture));
      completeEvidenceNegativeOutcomes.push({ id, expected_reason_code: "EVIDENCE_IDENTITY_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    }
    {
      const fixture = makeRun("complete-evidence-step1-tamper", 12);
      rewriteEvidenceArtifactCoherently(fixture, "action_trace", (value) => {
        value.actions.find((action) => action.action_id === "tool_step_1_atomic_postimage").outcome.status = "FORGED_SUCCESS";
      });
      expectCode("ACTION_TRACE_REJECTED", () => evaluate(fixture));
      completeEvidenceNegativeOutcomes.push({ id: "tool-step-1-outcome-tamper", expected_reason_code: "ACTION_TRACE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    }
    {
      const fixture = makeRun("complete-evidence-executor-hash-tamper", 13);
      rewriteEvidenceArtifactCoherently(fixture, "actual_executor", (value) => { value.node.sha256 = "0".repeat(64); });
      expectCode("EXECUTOR_EVIDENCE_REJECTED", () => evaluate(fixture));
      completeEvidenceNegativeOutcomes.push({ id: "actual-executor-node-hash-tamper", expected_reason_code: "EXECUTOR_EVIDENCE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    }
    {
      const fixture = makeRun("complete-evidence-runner-fake-pass", 14);
      rewriteEvidenceArtifactCoherently(fixture, "patch_evidence_package", (value) => {
        value.verification.status = "PASS";
        value.verification.verdict = "PASS";
        value.verification.runner_reported_pass_authoritative = true;
      });
      expectCode("PATCH_EVIDENCE_PACKAGE_REJECTED", () => evaluate(fixture));
      completeEvidenceNegativeOutcomes.push({ id: "runner-forged-independent-pass", expected_reason_code: "PATCH_EVIDENCE_PACKAGE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    }
    {
      const fixture = makeRun("complete-evidence-self-approval", 15);
      rewriteEvidenceArtifactCoherently(fixture, "patch_evidence_package", (value) => {
        value.approval.status = "APPROVED";
        value.approval.self_approval = true;
        value.approval.task_gate_claimed = true;
      });
      expectCode("PATCH_EVIDENCE_PACKAGE_REJECTED", () => evaluate(fixture));
      completeEvidenceNegativeOutcomes.push({ id: "runner-self-approval", expected_reason_code: "PATCH_EVIDENCE_PACKAGE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    }
    assert(completeEvidenceNegativeOutcomes.length === 18,
      "SELF_TEST_SETUP_FAILED", "complete Evidence negative matrix population drifted");
    const supplementalOutcomes = [];
    const wrongPatch = Buffer.from(PATCH_BYTES.toString("utf8").replace(
      "+  return { start: end, end: start };",
      "+  return { start, end };",
    ), "utf8");
    const wrongPatchFixture = makeRun("supplemental-wrong-patch", 1, { patchBytes: wrongPatch });
    expectCode("PATCH_EVIDENCE_REJECTED", () => evaluate(wrongPatchFixture));
    supplementalOutcomes.push({ id: "coherent-wrong-patch", expected_reason_code: "PATCH_EVIDENCE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    const falseSuccessFixture = makeRun("supplemental-false-success", 1, {
      rawStreamMutation: (streams) => streams.set(
        "base-regression.stdout",
        Buffer.from("not ok 1 - ordered ranges remain unchanged\n", "utf8"),
      ),
    });
    expectCode("TEST_EVIDENCE_REJECTED", () => evaluate(falseSuccessFixture));
    supplementalOutcomes.push({ id: "claimed-zero-exit-with-failing-stream", expected_reason_code: "TEST_EVIDENCE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    const tamperedMaterialization = makeRun("supplemental-materialization-tamper", 1);
    const postimage = compileFiniteTypedPatchIr(readFileSync(FILES.ir10)).postimage;
    writeFileSync(join(tamperedMaterialization.runRoot, "materialization/src/range.mjs"), postimage, { mode: 0o600 });
    expectCode("ROLLBACK_EVIDENCE_REJECTED", () => evaluate(tamperedMaterialization));
    supplementalOutcomes.push({ id: "retained-materialization-source-tamper", expected_reason_code: "ROLLBACK_EVIDENCE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    const linkedMaterialization = makeRun("supplemental-materialization-symlink", 1);
    const linkedSourceRoot = join(linkedMaterialization.runRoot, "owned-linked-src");
    mkdirSync(linkedSourceRoot, { mode: 0o700 });
    writeExclusive(join(linkedSourceRoot, "range.mjs"), readFileSync(MATERIALIZATION_INPUTS.source.path));
    rmSync(join(linkedMaterialization.runRoot, "materialization/src"), { recursive: true, force: false });
    symlinkSync(linkedSourceRoot, join(linkedMaterialization.runRoot, "materialization/src"));
    expectCode("MATERIALIZATION_ROOT_REJECTED", () => evaluate(linkedMaterialization));
    supplementalOutcomes.push({ id: "retained-materialization-ancestor-symlink", expected_reason_code: "MATERIALIZATION_ROOT_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    const aliasedRunB = clone(runB);
    aliasedRunB.run_root_receipt = clone(runA.run_root_receipt);
    aliasedRunB.materialization_root_receipt = clone(runA.materialization_root_receipt);
    expectCode("RUN_INDEPENDENCE_REJECTED", () => compareStableRuns(runA, aliasedRunB));
    supplementalOutcomes.push({ id: "run-a-run-b-physical-alias", expected_reason_code: "RUN_INDEPENDENCE_REJECTED", result: "PASS_REJECTED_AS_EXPECTED" });
    const outcomes = [];
    const childTerminationOutcomes = [];
    for (const testCase of negative.cases) {
      if (testCase.id === "non-canonical-json") {
        expectCode(testCase.expected_reason_code, () => validatePlanBytes(Buffer.from(JSON.stringify(positive), "utf8")));
      } else if (testCase.id === "duplicate-json-key") {
        const text = readFileSync(FILES.positive_tool_plan, "utf8").replace('"schema_version":1,', '"schema_version":1,"schema_version":1,');
        expectCode(testCase.expected_reason_code, () => validatePlanBytes(Buffer.from(text, "utf8")));
      } else if (testCase.id === "malformed-json") {
        expectCode(testCase.expected_reason_code, () => validatePlanBytes(Buffer.from("{", "utf8")));
      } else if (testCase.stage === "PRE_ADMISSION") {
        expectCode(testCase.expected_reason_code, () => validatePlanBytes(planMutation(testCase.id, positive)));
      } else if (testCase.stage === "QUALITY_ASSET_VALIDATION") {
        const overrides = {};
        if (testCase.id === "system-loop-limit-drift") {
          overrides.system_configuration = clone(assets.system); overrides.system_configuration.loop_limit = 4;
        } else if (testCase.id === "environment-tool-permission-drift") {
          overrides.environment_snapshot = clone(assets.environment); overrides.environment_snapshot.tools[0].permission = "observe";
        } else if (testCase.id === "compiler-program-identity-drift") {
          overrides.compatibility_profile = clone(assets.profile); overrides.compatibility_profile.compiler_binding.program_sha256 = "0".repeat(64);
        }
        expectCode(testCase.expected_reason_code, () => validateQualityAssets(overrides));
      } else {
        const failureKind = testCase.id === "timeout-without-termination"
          ? "timeout"
          : testCase.id === "output-overflow-without-termination"
            ? "output_overflow"
            : testCase.id === "signal-without-termination"
              ? "signal"
              : null;
        if (failureKind) childTerminationOutcomes.push(await exerciseChildTermination(failureKind));
        const fixture = createPhysicalNegativeFixture(temporary, testCase, physicalRunB, sharedOptions);
        expectCode(testCase.expected_reason_code, () => evaluate(fixture));
      }
      outcomes.push({ id: testCase.id, expected_reason_code: testCase.expected_reason_code, result: "PASS_REJECTED_AS_EXPECTED" });
    }
    return {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_067_quality_self_test",
      task_id: TASK_ID,
      quality_oracle_version: QUALITY_ORACLE_VERSION,
      quality_asset_validation: "PASS",
      positive_plan_validation: "PASS",
      positive_run_evaluation: "PASS_PHYSICAL_MANIFEST_AND_ARTIFACT_RECOMPUTED",
      independent_run_comparison: "PASS",
      negative_case_count: outcomes.length,
      negative_case_outcomes: outcomes,
      supplemental_target_negative_case_count: supplementalOutcomes.length,
      supplemental_target_negative_case_outcomes: supplementalOutcomes,
      complete_evidence_negative_case_count: completeEvidenceNegativeOutcomes.length,
      complete_evidence_negative_case_outcomes: completeEvidenceNegativeOutcomes,
      physical_runtime_negative_case_count: negative.cases.filter((entry) => entry.stage === "POST_RUN_EVALUATION").length,
      oracle_process_group_control_case_count: childTerminationOutcomes.length,
      oracle_process_group_control_outcomes: childTerminationOutcomes,
      pre_admission_telemetry: { materialization_creations: 0, mutation_attempts: 0, child_start_attempts: 0 },
      false_accepts: 0,
      target_verdict: "PASS",
      claim_boundary: CLAIM,
    };
  } finally {
    const current = lstatSync(temporary);
    assert(current.isDirectory() && !current.isSymbolicLink() && current.dev === temporaryStat.dev &&
      current.ino === temporaryStat.ino && current.uid === temporaryStat.uid,
    "SELF_TEST_CLEANUP_REJECTED", "self-test root identity drifted");
    const marker = readNoFollowRegular(markerPath, undefined, "SELF_TEST_CLEANUP_REJECTED", "self-test marker").bytes;
    assert(marker.equals(markerBytes), "SELF_TEST_CLEANUP_REJECTED", "self-test marker drifted");
    rmSync(temporary, { recursive: true, force: false });
  }
}

async function main() {
  const mode = process.argv[2];
  assert(mode === "self-test", "CLI_REJECTED", "only self-test is supported before Worker Evidence exists");
  assert(process.argv.length === 3, "CLI_REJECTED", "self-test takes no arguments");
  process.stdout.write(canonicalJsonBytes(await selfTest()));
}

if (resolve(process.argv[1] ?? "") === resolve(fileURLToPath(import.meta.url))) {
  try {
    await main();
  } catch (error) {
    const code = error instanceof QualityOracleError ? error.code : "UNEXPECTED_ERROR";
    process.stderr.write(`P1_067_QUALITY_ORACLE: NON_PASS ${code} ${error.message}\n`);
    process.exitCode = 2;
  }
}

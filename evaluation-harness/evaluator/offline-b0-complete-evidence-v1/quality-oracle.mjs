import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  closeSync,
  constants as fsConstants,
  fstatSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { fileURLToPath } from "node:url";

import { validate as validateSchema } from "../schema-validator.mjs";
import {
  COMPILER_VERSION,
  compileFiniteTypedPatchIr,
} from "../../harness/finite-typed-patch-ir-v1/compiler.mjs";
import { evaluateCompilerObservation } from "../finite-typed-patch-ir-v1/quality-oracle.mjs";

export const QUALITY_ORACLE_VERSION = "P1-066-OFFLINE-B0-QUALITY-ORACLE/2";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(MODULE_DIR, "../../..");
const FIXTURE_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/fixtures/offline-b0-complete-evidence-v1");
const TASK_CARD_PATH = join(FIXTURE_ROOT, "task-card.json");
const TASK_SPEC_SCHEMA_PATH = join(REPOSITORY_ROOT, "docs/aios/schemas/task-spec.schema.json");
const ENVIRONMENT_SCHEMA_PATH = join(REPOSITORY_ROOT, "docs/aios/schemas/environment-snapshot.schema.json");
const SYSTEM_SCHEMA_PATH = join(REPOSITORY_ROOT, "docs/aios/schemas/system-configuration.schema.json");
const RUN_RECORD_SCHEMA_PATH = join(REPOSITORY_ROOT, "docs/aios/schemas/run-record.schema.json");
const QUALITY_FREEZE_MANIFEST_PATH = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-066-engineering-first-offline-b0-SSBiXrxT/quality/QUALITY_FREEZE_MANIFEST_V3.json";
const AUTHORIZED_EVIDENCE_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-066-engineering-first-offline-b0-SSBiXrxT";
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
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;

const TASK_ID = "AIOS-P1-066_ENGINEERING_FIRST_OFFLINE_B0_COMPLETE_EVIDENCE_VERTICAL_SLICE";
const CONTROL_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const CLAIM_BOUNDARY = "ONE_VISIBLE_SYNTHETIC_REP_001_COOPERATIVE_LOCAL_OFFLINE_B0_COMPLETE_EVIDENCE_OBSERVATION_ONLY";
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const EXPECTED_POSTIMAGE = Object.freeze({
  byte_length: 127,
  sha256: "e8304b77da9b8c33f64ecdc568db7e97297ace72ecb796971bb3f5eda09d9001",
});
const EXPECTED_BASE = Object.freeze({
  commit: "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f",
  tree: "900814727113d65f5dad8b63222e14f39b2cf38b",
  source_byte_length: 115,
  source_sha256: "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75",
});

export class QualityOracleError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "QualityOracleError";
    this.code = code;
  }
}

const fail = (code, message) => {
  throw new QualityOracleError(code, message);
};
const assert = (condition, code, message) => {
  if (!condition) fail(code, message);
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
const sameJson = (left, right) => isDeepStrictEqual(canonicalize(left), canonicalize(right));

export function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
}

function parseJsonBytes(bytes, code, label) {
  assert(Buffer.isBuffer(bytes), code, `${label} is not bytes`);
  const text = bytes.toString("utf8");
  assert(Buffer.from(text, "utf8").equals(bytes), code, `${label} is not exact UTF-8`);
  try {
    return JSON.parse(text);
  } catch {
    fail(code, `${label} is not JSON`);
  }
}

function exactKeys(value, keys, code, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), code, `${label} is not an object`);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (!sameJson(actual, expected)) {
    const unknown = actual.filter((key) => !expected.includes(key));
    const missing = expected.filter((key) => !actual.includes(key));
    fail(code, `${label} key set mismatch unknown=${unknown.join(",")} missing=${missing.join(",")}`);
  }
}

function safeReadRegular(path, expected = undefined, code = "EVIDENCE_IDENTITY_REJECTED", label = "file") {
  let before;
  try {
    before = lstatSync(path);
  } catch (error) {
    fail(code, `${label} lstat failed: ${error.code ?? error.message}`);
  }
  assert(!before.isSymbolicLink(), code, `${label} is a symlink`);
  assert(before.isFile(), code, `${label} is not a regular file`);
  assert(before.nlink === 1, code, `${label} nlink is not one`);
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  } catch (error) {
    fail(code, `${label} open failed: ${error.code ?? error.message}`);
  }
  try {
    const opened = fstatSync(descriptor);
    assert(opened.isFile() && opened.nlink === 1, code, `${label} descriptor type or nlink drift`);
    assert(opened.dev === before.dev && opened.ino === before.ino, code, `${label} identity changed before read`);
    const bytes = readFileSync(descriptor);
    const after = lstatSync(path);
    assert(after.isFile() && !after.isSymbolicLink() && after.nlink === 1, code, `${label} changed type after read`);
    assert(after.dev === opened.dev && after.ino === opened.ino, code, `${label} identity changed after read`);
    const identity = identityOf(bytes);
    if (expected !== undefined) {
      assert(identity.byte_length === expected.byte_length, code, `${label} byte length mismatch`);
      assert(identity.sha256 === expected.sha256, code, `${label} sha256 mismatch`);
    }
    return { bytes, identity, stat: opened };
  } finally {
    closeSync(descriptor);
  }
}

function containedLeaf(root, relativePath, escapeCode = "EVIDENCE_PATH_ESCAPE_REJECTED") {
  assert(typeof relativePath === "string" && relativePath.length > 0 && !isAbsolute(relativePath), escapeCode, "artifact path must be non-empty relative path");
  const candidate = resolve(root, relativePath);
  const rel = relative(root, candidate);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) && !isAbsolute(rel), escapeCode, "artifact path escaped root");
  return candidate;
}

function readContainedArtifact(root, record, codes = {}) {
  const escapeCode = codes.escape ?? "EVIDENCE_PATH_ESCAPE_REJECTED";
  const typeCode = codes.type ?? "EVIDENCE_IDENTITY_REJECTED";
  exactKeys(record, ["path", "byte_length", "sha256"], typeCode, "artifact record");
  const path = containedLeaf(root, record.path, escapeCode);
  return safeReadRegular(path, record, typeCode, `artifact ${record.path}`);
}

function createExclusiveFile(path, bytes, mode = 0o600) {
  const descriptor = openSync(path, fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | O_NOFOLLOW, mode);
  try {
    let offset = 0;
    while (offset < bytes.length) offset += writeSync(descriptor, bytes, offset, bytes.length - offset);
  } finally {
    closeSync(descriptor);
  }
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1, "SELF_TEST_SETUP_FAILED", "exclusive file receipt invalid");
  return { path, ...identityOf(bytes) };
}

function readJsonPath(path, expected, code, label) {
  const file = safeReadRegular(path, expected, code, label);
  return { ...file, value: parseJsonBytes(file.bytes, code, label) };
}

function absoluteRepositoryPath(relativePath) {
  const path = resolve(REPOSITORY_ROOT, relativePath);
  const rel = relative(REPOSITORY_ROOT, path);
  assert(rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel), "QUALITY_ASSET_DRIFT", `repository path escaped: ${relativePath}`);
  return path;
}

function validateSchemaOrFail(value, schemaPath, code, label) {
  const schema = parseJsonBytes(safeReadRegular(schemaPath, undefined, code, `${label} schema`).bytes, code, `${label} schema`);
  const errors = validateSchema(value, schema);
  assert(errors.length === 0, code, `${label} schema errors: ${errors.join(" | ")}`);
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

export function validateTaskCard(cardInput) {
  const card = Buffer.isBuffer(cardInput)
    ? parseJsonBytes(cardInput, "TASK_CARD_DRIFT", "Task Card")
    : cardInput;
  const rootKeys = [
    "schema_version", "record_type", "status", "freeze_effective_only_with_external_quality_receipt",
    "task_id", "control_id", "quality_owner", "worker_may_modify", "activation", "authority", "contract",
    "accepted_inputs", "quality_assets", "declared_target_and_actual_executor", "adapter_contract",
    "runner_interface", "candidate_provenance_contract", "required_actions_in_order", "fixed_commands", "command_profile", "run_evidence_contract",
    "run_record_requirements", "quality_evaluator_interface", "stable_projection", "positive_expectations", "rollback",
    "negative_case_contract", "external_effects", "claim_boundary",
  ];
  exactKeys(card, rootKeys, "TASK_CARD_DRIFT", "Task Card");
  assert(card.schema_version === 1, "TASK_CARD_DRIFT", "Task Card schema version drift");
  assert(card.record_type === "sourcelens_aios_p1_066_offline_b0_quality_task_card", "TASK_CARD_DRIFT", "Task Card record type drift");
  assert(card.status === "QUALITY_FREEZE_CANDIDATE" && card.freeze_effective_only_with_external_quality_receipt === true, "TASK_CARD_DRIFT", "Task Card freeze state drift");
  assert(card.task_id === TASK_ID && card.control_id === CONTROL_ID, "TASK_CARD_DRIFT", "Task Card task binding drift");
  assert(card.activation.commit === "7081d857a4cb401294673dd566ff63dc6b2a7cb1" && card.activation.tree === "10c1ba1f2fc9529e4a9d766adbfaa7775bced852", "TASK_CARD_DRIFT", "activation identity drift");
  assert(card.contract.byte_length === 13993 && card.contract.sha256 === "923d2ad4a5d56c6f154c1e946699744facf86741131dfacc46d165e5b832c790", "TASK_CARD_DRIFT", "Contract identity drift");
  assert(card.authority.byte_length === 2624 && card.authority.sha256 === "a4eebb955d8cd23730c249e6a7453a4b94a773f8cd2090dd7dbdbb5ffe5f72e9", "TASK_CARD_DRIFT", "Authority identity drift");
  assert(card.adapter_contract.proposal_flow === "DECODE_TO_BUFFER_THEN_PASS_UNMODIFIED_TO_COMPILE_FINITE_TYPED_PATCH_IR", "TASK_CARD_DRIFT", "proposal flow drift");
  assert(card.adapter_contract.result_controlled_path_argv_cwd_env_module_or_executable === false && card.adapter_contract.free_form_code_diff_ast_or_module_execution === false, "TASK_CARD_DRIFT", "adapter safety boundary drift");
  assert(card.quality_evaluator_interface.version === QUALITY_ORACLE_VERSION, "TASK_CARD_DRIFT", "Quality oracle version drift");
  assert(sameJson(card.candidate_provenance_contract.required_executing_modules, Object.keys(EXECUTING_MODULE_PATHS).sort()), "TASK_CARD_DRIFT", "candidate provenance module contract drift");
  assert(card.negative_case_contract.case_count === 15 && card.negative_case_contract.maximum_false_accepts === 0, "TASK_CARD_DRIFT", "negative contract drift");
  assert(sameJson(card.external_effects, FALSE_EFFECTS), "TASK_CARD_DRIFT", "external effects drift");
  assert(card.claim_boundary === CLAIM_BOUNDARY, "TASK_CARD_DRIFT", "claim boundary drift");
  return card;
}

function validateResponse(response) {
  exactKeys(response, ["summary", "changed_paths", "tests"], "SUBMISSION_UNKNOWN_MEMBER_REJECTED", "result response");
  assert(typeof response.summary === "string" && response.summary.length > 0, "SUBMISSION_SCHEMA_REJECTED", "response summary invalid");
  assert(Array.isArray(response.changed_paths) && response.changed_paths.every((item) => typeof item === "string"), "SUBMISSION_SCHEMA_REJECTED", "response changed_paths invalid");
  assert(Array.isArray(response.tests) && response.tests.every((item) => typeof item === "string"), "SUBMISSION_SCHEMA_REJECTED", "response tests invalid");
  assert(sameJson(response.changed_paths, ["src/range.mjs"]), "INPUT_IDENTITY_REJECTED", "response changed path drift");
}

function decodeCanonicalBase64(value) {
  assert(typeof value === "string" && value.length > 0 && value.length % 4 === 0 && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value), "SUBMISSION_SCHEMA_REJECTED", "proposal base64 is not canonical shape");
  const bytes = Buffer.from(value, "base64");
  assert(bytes.toString("base64") === value, "SUBMISSION_SCHEMA_REJECTED", "proposal base64 is not canonical encoding");
  return bytes;
}

function validatePositiveResult(value, card) {
  const rootKeys = [
    "schema_version", "record_type", "submission_id", "provenance", "task_binding", "target_runtime_binding",
    "environment_binding", "system_configuration_binding", "compiler_binding", "response_format_binding", "results",
    "claim_boundary",
  ];
  exactKeys(value, rootKeys, "SUBMISSION_UNKNOWN_MEMBER_REJECTED", "positive result envelope");
  assert(value.schema_version === 1 && value.record_type === "sourcelens_aios_provider_neutral_offline_b0_result_envelope", "SUBMISSION_SCHEMA_REJECTED", "result envelope identity invalid");
  assert(value.provenance?.kind === "QUALITY_FROZEN_COOPERATIVE_LOCAL_FIXTURE" && value.provenance.live_model_invoked === false && value.provenance.provider_invoked === false && value.provenance.model_performance_sample === false, "SUBMISSION_SCHEMA_REJECTED", "result provenance invalid");
  assert(value.claim_boundary === CLAIM_BOUNDARY, "SUBMISSION_SCHEMA_REJECTED", "result claim boundary drift");
  assert(value.task_binding?.task_id === CONTROL_ID && value.task_binding.task_spec_byte_length === card.accepted_inputs.task_spec.byte_length && value.task_binding.task_spec_sha256 === card.accepted_inputs.task_spec.sha256 && value.task_binding.base_commit === EXPECTED_BASE.commit && value.task_binding.base_tree === EXPECTED_BASE.tree, "INPUT_IDENTITY_REJECTED", "TaskSpec or source binding drift");
  assert(value.target_runtime_binding?.target_runtime_id === "TARGET-P1-066-DARWIN-ARM64-NODE20-STDLIB-1" && value.target_runtime_binding.byte_length === card.quality_assets.target_runtime.byte_length && value.target_runtime_binding.sha256 === card.quality_assets.target_runtime.sha256 && value.target_runtime_binding.materialized === false && value.target_runtime_binding.container_execution_observed === false, "ENVIRONMENT_BINDING_REJECTED", "target runtime binding drift");
  assert(value.environment_binding?.snapshot_id === "ENV-SOURCELENS-P1-REP-NODE20-STDLIB-1" && value.environment_binding.byte_length === card.quality_assets.environment_snapshot.byte_length && value.environment_binding.sha256 === card.quality_assets.environment_snapshot.sha256, "ENVIRONMENT_BINDING_REJECTED", "environment binding drift");
  assert(value.system_configuration_binding?.configuration_id === "P1-066-B0-OFFLINE-FINITE-TYPED-1" && value.system_configuration_binding.byte_length === card.quality_assets.system_configuration.byte_length && value.system_configuration_binding.sha256 === card.quality_assets.system_configuration.sha256, "SYSTEM_CONFIGURATION_BINDING_REJECTED", "system configuration binding drift");
  assert(value.compiler_binding?.version === COMPILER_VERSION && value.compiler_binding.byte_length === card.accepted_inputs.compiler.byte_length && value.compiler_binding.sha256 === card.accepted_inputs.compiler.sha256, "INPUT_IDENTITY_REJECTED", "compiler binding drift");
  assert(value.response_format_binding?.byte_length === card.accepted_inputs.response_format.byte_length && value.response_format_binding.sha256 === card.accepted_inputs.response_format.sha256, "INPUT_IDENTITY_REJECTED", "response format binding drift");
  assert(Array.isArray(value.results), "SUBMISSION_SCHEMA_REJECTED", "results is not an array");
  assert(value.results.length === 1, "RESULT_CARDINALITY_REJECTED", "result population is not exactly one");
  const result = value.results[0];
  exactKeys(result, ["result_id", "response", "finite_typed_result", "requested_external_effects"], "SUBMISSION_UNKNOWN_MEMBER_REJECTED", "result");
  validateResponse(result.response);
  assert(sameJson(result.requested_external_effects, FALSE_EFFECTS), "EXTERNAL_EFFECT_REQUEST_REJECTED", "result requested an external effect");
  exactKeys(result.finite_typed_result, ["schema", "encoding", "bytes_base64", "byte_length", "sha256"], "SUBMISSION_UNKNOWN_MEMBER_REJECTED", "finite typed result");
  assert(result.finite_typed_result.schema === "SL-PATCH-IR/1" && result.finite_typed_result.encoding === "base64", "SUBMISSION_SCHEMA_REJECTED", "finite typed result schema or encoding invalid");
  const proposalBytes = decodeCanonicalBase64(result.finite_typed_result.bytes_base64);
  const actualIdentity = identityOf(proposalBytes);
  assert(actualIdentity.byte_length === result.finite_typed_result.byte_length && actualIdentity.sha256 === result.finite_typed_result.sha256, "INPUT_IDENTITY_REJECTED", "proposal declared identity drift");
  const compiled = compileFiniteTypedPatchIr(proposalBytes);
  if (compiled.status === "REJECTED") fail(compiled.reason_code ?? "IR_NOT_EXACTLY_ADMITTED", "accepted compiler rejected proposal bytes");
  try {
    evaluateCompilerObservation(proposalBytes, compiled);
  } catch (error) {
    fail(error.code ?? "COMPILER_OBSERVATION_REJECTED", error.message);
  }
  assert(actualIdentity.byte_length === card.accepted_inputs.ir10.byte_length && actualIdentity.sha256 === card.accepted_inputs.ir10.sha256, "INPUT_IDENTITY_REJECTED", "proposal is not frozen IR10");
  assert(compiled.program_id === "IR10" && compiled.outcome_id === "CORRECT_END_START" && Buffer.isBuffer(compiled.postimage), "COMPILER_OBSERVATION_REJECTED", "IR10 compiler outcome drift");
  assert(compiled.postimage.length === EXPECTED_POSTIMAGE.byte_length && sha256(compiled.postimage) === EXPECTED_POSTIMAGE.sha256, "COMPILER_OBSERVATION_REJECTED", "compiled postimage drift");
  return { result, proposalBytes, compiled };
}

function validateTargetRuntime(value, identity) {
  exactKeys(value, ["schema_version", "record_type", "target_runtime_id", "oci_manifest", "declared_target", "actual_executor_evidence_policy"], "QUALITY_ASSET_DRIFT", "target runtime");
  assert(value.target_runtime_id === "TARGET-P1-066-DARWIN-ARM64-NODE20-STDLIB-1", "QUALITY_ASSET_DRIFT", "target runtime id drift");
  assert(value.declared_target?.kind === "DECLARED_SYNTHETIC_TARGET" && value.declared_target.materialized === false && value.declared_target.container_execution_observed === false && value.declared_target.pullable_image === false, "QUALITY_ASSET_DRIFT", "declared target truth boundary drift");
  assert(value.actual_executor_evidence_policy?.capture_per_run === true && value.actual_executor_evidence_policy.container_runtime_observed === false && value.actual_executor_evidence_policy.must_not_claim_declared_target_was_materialized === true, "QUALITY_ASSET_DRIFT", "actual executor evidence policy drift");
  return { ...identity, target_runtime_id: value.target_runtime_id };
}

export function validateQualityAssets(taskCardInput = undefined) {
  const taskCardFile = taskCardInput === undefined
    ? safeReadRegular(TASK_CARD_PATH, undefined, "TASK_CARD_DRIFT", "Task Card")
    : null;
  const card = validateTaskCard(taskCardInput ?? taskCardFile.bytes);
  safeReadRegular(absoluteRepositoryPath(card.contract.path), card.contract, "QUALITY_ASSET_DRIFT", "Contract");
  safeReadRegular(card.authority.path, card.authority, "QUALITY_ASSET_DRIFT", "Authority");

  const accepted = {};
  for (const [name, record] of Object.entries(card.accepted_inputs)) {
    if (!record.path) continue;
    accepted[name] = safeReadRegular(absoluteRepositoryPath(record.path), record, "QUALITY_ASSET_DRIFT", `accepted ${name}`);
  }
  const quality = {};
  for (const [name, record] of Object.entries(card.quality_assets)) {
    quality[name] = readJsonPath(absoluteRepositoryPath(record.path), record, "QUALITY_ASSET_DRIFT", `Quality ${name}`);
  }

  const taskSpec = parseJsonBytes(accepted.task_spec.bytes, "QUALITY_ASSET_DRIFT", "TaskSpec");
  const environment = quality.environment_snapshot.value;
  const system = quality.system_configuration.value;
  validateSchemaOrFail(taskSpec, TASK_SPEC_SCHEMA_PATH, "QUALITY_ASSET_DRIFT", "TaskSpec");
  validateSchemaOrFail(environment, ENVIRONMENT_SCHEMA_PATH, "QUALITY_ASSET_DRIFT", "EnvironmentSnapshot");
  validateSchemaOrFail(system, SYSTEM_SCHEMA_PATH, "QUALITY_ASSET_DRIFT", "SystemConfiguration");
  validateTargetRuntime(quality.target_runtime.value, quality.target_runtime.identity);
  assert(taskSpec.environment_snapshot_ref === environment.snapshot_id, "ENVIRONMENT_BINDING_REJECTED", "TaskSpec EnvironmentSnapshot ref mismatch");
  assert(taskSpec.repository.base_commit === environment.source.base_commit && taskSpec.repository.tree_hash === environment.source.tree_hash, "ENVIRONMENT_BINDING_REJECTED", "TaskSpec source/environment mismatch");
  assert(taskSpec.network_policy === environment.network.policy && sameJson(taskSpec.allowed_network_hosts, environment.network.allowed_hosts), "ENVIRONMENT_BINDING_REJECTED", "TaskSpec network/environment mismatch");
  assert(system.adapter_id === "B0" && system.loop_limit === 1 && sameJson(system.enabled_tools, []), "SYSTEM_CONFIGURATION_BINDING_REJECTED", "B0 tools or loop drift");
  assert(system.model_ref === environment.model.model_ref && system.prompt_ref === environment.prompt_version && system.policy_ref === environment.policy_version, "SYSTEM_CONFIGURATION_BINDING_REJECTED", "system/environment model prompt policy mismatch");
  assert(system.response_format_ref === taskSpec.baseline_context.response_format_ref, "SYSTEM_CONFIGURATION_BINDING_REJECTED", "response format ref mismatch");
  assert(environment.runtime.container_image_digest === `sha256:${quality.target_runtime.identity.sha256}`, "ENVIRONMENT_BINDING_REJECTED", "declared target digest mismatch");
  const positive = validatePositiveResult(quality.positive_result.value, card);
  const negative = quality.negative_cases.value;
  assert(negative.task_id === TASK_ID && negative.case_count === 15 && negative.cases.length === 15 && new Set(negative.cases.map((entry) => entry.id)).size === 15 && negative.maximum_false_accepts === 0, "NEGATIVE_MATRIX_REJECTED", "negative case population drift");
  assert(sameJson(negative.pre_admission_rejection_assertions.external_effects, FALSE_EFFECTS), "NEGATIVE_MATRIX_REJECTED", "negative external effects drift");
  return {
    card,
    task_card_identity: taskCardFile?.identity ?? null,
    accepted,
    quality,
    taskSpec,
    environment,
    system,
    positive,
    negative,
  };
}

function validateCandidateBinding(value) {
  exactKeys(value, ["candidate_commit", "candidate_tree", "candidate_manifest_sha256", "quality_freeze_manifest_sha256"], "CANDIDATE_BINDING_REJECTED", "candidate binding");
  assert(/^[0-9a-f]{40}$/.test(value.candidate_commit), "CANDIDATE_BINDING_REJECTED", "candidate commit invalid");
  assert(/^[0-9a-f]{40}$/.test(value.candidate_tree), "CANDIDATE_BINDING_REJECTED", "candidate tree invalid");
  assert(/^[0-9a-f]{64}$/.test(value.candidate_manifest_sha256), "CANDIDATE_BINDING_REJECTED", "candidate manifest hash invalid");
  assert(/^[0-9a-f]{64}$/.test(value.quality_freeze_manifest_sha256), "CANDIDATE_BINDING_REJECTED", "Quality Freeze hash invalid");
  return canonicalize(value);
}

function readGit(repositoryRoot, argv, code, label, environment = undefined) {
  const outcome = spawnSync("/usr/bin/git", ["-C", repositoryRoot, ...argv], {
    cwd: repositoryRoot,
    env: environment ?? {
      PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
      LANG: "C",
      LC_ALL: "C",
      TZ: "UTC",
      GIT_CONFIG_NOSYSTEM: "1",
      GIT_CONFIG_GLOBAL: "/dev/null",
      GIT_TERMINAL_PROMPT: "0",
      GIT_OPTIONAL_LOCKS: "0",
    },
    encoding: null,
    timeout: 15000,
    maxBuffer: 4 * 1024 * 1024,
    windowsHide: true,
  });
  assert(!outcome.error, code, `${label} could not execute`);
  assert(outcome.status === 0 && outcome.signal === null, code, `${label} failed`);
  const stdout = Buffer.isBuffer(outcome.stdout) ? outcome.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(outcome.stderr) ? outcome.stderr : Buffer.alloc(0);
  assert(stderr.length === 0, code, `${label} emitted stderr`);
  return stdout;
}

function currentExecutingModuleIdentities() {
  return Object.fromEntries(Object.entries(EXECUTING_MODULE_PATHS).map(([role, path]) => {
    const file = safeReadRegular(absoluteRepositoryPath(path), undefined, "CANDIDATE_BINDING_REJECTED", `candidate ${role}`);
    return [role, { path, ...file.identity }];
  }));
}

function currentCandidateRepositoryProvenance() {
  const root = validateDirectoryReceipt({
    path: REPOSITORY_ROOT,
    realpath: realpathSync(REPOSITORY_ROOT),
    device: lstatSync(REPOSITORY_ROOT).dev,
    inode: lstatSync(REPOSITORY_ROOT).ino,
  }, "CANDIDATE_BINDING_REJECTED", "candidate repository root");
  const head = readGit(root.path, ["rev-parse", "HEAD"], "CANDIDATE_BINDING_REJECTED", "candidate HEAD").toString("utf8").trim();
  const tree = readGit(root.path, ["rev-parse", "HEAD^{tree}"], "CANDIDATE_BINDING_REJECTED", "candidate tree").toString("utf8").trim();
  const status = readGit(root.path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], "CANDIDATE_BINDING_REJECTED", "candidate status");
  assert(/^[0-9a-f]{40}$/.test(head) && /^[0-9a-f]{40}$/.test(tree), "CANDIDATE_BINDING_REJECTED", "candidate Git identity invalid");
  assert(status.length === 0, "CANDIDATE_BINDING_REJECTED", "candidate repository is not clean");
  return {
    repository: { ...root, head, tree, workspace_status: "clean" },
    executing_modules: currentExecutingModuleIdentities(),
  };
}

function validateCandidateProvenance(records, candidateBinding, card) {
  const qualityFreezeFile = safeReadRegular(QUALITY_FREEZE_MANIFEST_PATH, undefined, "CANDIDATE_BINDING_REJECTED", "Quality Freeze V3 manifest");
  const qualityFreeze = parseJsonBytes(qualityFreezeFile.bytes, "CANDIDATE_BINDING_REJECTED", "Quality Freeze V3 manifest");
  assert(qualityFreeze.record_type === "sourcelens_aios_p1_066_quality_freeze_manifest_and_receipt_v3" && qualityFreeze.status === "QUALITY_FREEZE_V3_EFFECTIVE_FINAL_REPAIR_HANDOFF_ALLOWED" && qualityFreeze.freeze_effective === true, "CANDIDATE_BINDING_REJECTED", "Quality Freeze V3 state drift");
  assert(candidateBinding.quality_freeze_manifest_sha256 === qualityFreezeFile.identity.sha256, "CANDIDATE_BINDING_REJECTED", "candidate Quality Freeze V3 hash drift");
  const manifestEntry = recordByRole(records, "candidate_manifest");
  assert(manifestEntry.record.sha256 === candidateBinding.candidate_manifest_sha256, "CANDIDATE_BINDING_REJECTED", "candidate manifest artifact hash drift");
  const manifest = parseJsonBytes(manifestEntry.file.bytes, "CANDIDATE_BINDING_REJECTED", "candidate manifest artifact");
  exactKeys(manifest, [
    "schema_version", "record_type", "task_id", "candidate_commit", "candidate_tree",
    "quality_freeze_manifest_sha256", "repository", "executing_modules",
  ], "CANDIDATE_BINDING_REJECTED", "candidate manifest artifact");
  assert(manifest.schema_version === 1 && manifest.record_type === card.candidate_provenance_contract.candidate_manifest_record_type && manifest.task_id === TASK_ID, "CANDIDATE_BINDING_REJECTED", "candidate manifest identity drift");
  assert(manifest.candidate_commit === candidateBinding.candidate_commit && manifest.candidate_tree === candidateBinding.candidate_tree && manifest.quality_freeze_manifest_sha256 === candidateBinding.quality_freeze_manifest_sha256, "CANDIDATE_BINDING_REJECTED", "candidate manifest binding drift");
  exactKeys(manifest.repository, ["path", "realpath", "head", "tree", "workspace_status"], "CANDIDATE_BINDING_REJECTED", "candidate repository declaration");
  assert(manifest.repository.path === REPOSITORY_ROOT && manifest.repository.realpath === realpathSync(REPOSITORY_ROOT), "CANDIDATE_BINDING_REJECTED", "candidate repository root drift");
  assert(manifest.repository.head === candidateBinding.candidate_commit && manifest.repository.tree === candidateBinding.candidate_tree && manifest.repository.workspace_status === "clean", "CANDIDATE_BINDING_REJECTED", "candidate repository declaration drift");
  exactKeys(manifest.executing_modules, Object.keys(EXECUTING_MODULE_PATHS), "CANDIDATE_BINDING_REJECTED", "candidate executing modules");
  for (const [role, path] of Object.entries(EXECUTING_MODULE_PATHS)) {
    exactKeys(manifest.executing_modules[role], ["path", "byte_length", "sha256"], "CANDIDATE_BINDING_REJECTED", `candidate ${role} declaration`);
    assert(manifest.executing_modules[role].path === path, "CANDIDATE_BINDING_REJECTED", `candidate ${role} path drift`);
  }
  const provenanceEntry = recordByRole(records, "candidate_provenance");
  const provenance = parseJsonBytes(provenanceEntry.file.bytes, "CANDIDATE_BINDING_REJECTED", "candidate provenance");
  exactKeys(provenance, ["schema_version", "record_type", "task_id", "candidate_binding", "candidate_manifest_artifact", "repository", "executing_modules", "verification"], "CANDIDATE_BINDING_REJECTED", "candidate provenance");
  assert(provenance.schema_version === 1 && provenance.record_type === card.candidate_provenance_contract.provenance_record_type && provenance.task_id === TASK_ID, "CANDIDATE_BINDING_REJECTED", "candidate provenance identity drift");
  assert(sameJson(provenance.candidate_binding, candidateBinding), "CANDIDATE_BINDING_REJECTED", "candidate provenance binding drift");
  assert(sameJson(provenance.candidate_manifest_artifact, { path: manifestEntry.record.path, byte_length: manifestEntry.record.byte_length, sha256: manifestEntry.record.sha256 }), "CANDIDATE_BINDING_REJECTED", "candidate manifest artifact reference drift");
  const observed = currentCandidateRepositoryProvenance();
  assert(provenance.repository.path === observed.repository.path && provenance.repository.realpath === observed.repository.realpath && provenance.repository.device === observed.repository.device && provenance.repository.inode === observed.repository.inode, "CANDIDATE_BINDING_REJECTED", "candidate repository physical receipt drift");
  assert(provenance.repository.head === observed.repository.head && provenance.repository.tree === observed.repository.tree && provenance.repository.workspace_status === "clean", "CANDIDATE_BINDING_REJECTED", "candidate repository Git receipt drift");
  assert(observed.repository.head === candidateBinding.candidate_commit && observed.repository.tree === candidateBinding.candidate_tree, "CANDIDATE_BINDING_REJECTED", "candidate current Git identity mismatch");
  assert(sameJson(provenance.executing_modules, observed.executing_modules) && sameJson(manifest.executing_modules, observed.executing_modules), "CANDIDATE_BINDING_REJECTED", "candidate executing module identity mismatch");
  assert(sameJson(provenance.verification, {
    repository_root_equals_executing_module_repository_root: true,
    head_tree_and_clean_state_recomputed_at_execution: true,
    executing_module_identities_recomputed_at_execution: true,
  }), "CANDIDATE_BINDING_REJECTED", "candidate provenance verification drift");
  return {
    candidate_manifest_sha256: manifestEntry.record.sha256,
    repository: {
      head: observed.repository.head,
      tree: observed.repository.tree,
      workspace_status: "clean",
    },
    executing_modules: observed.executing_modules,
    execution_time_receipt_verified: true,
    evaluation_time_recomputation_verified: true,
  };
}

function validateDirectoryReceipt(value, code, label) {
  exactKeys(value, ["path", "realpath", "device", "inode"], code, label);
  assert(isAbsolute(value.path) && isAbsolute(value.realpath), code, `${label} path is not absolute`);
  let stat;
  try {
    stat = lstatSync(value.path);
  } catch (error) {
    fail(code, `${label} lstat failed: ${error.code ?? error.message}`);
  }
  assert(stat.isDirectory() && !stat.isSymbolicLink(), code, `${label} is not a real directory`);
  assert(realpathSync(value.path) === value.realpath, code, `${label} realpath drift`);
  assert(stat.dev === value.device && stat.ino === value.inode, code, `${label} device or inode drift`);
  return { path: value.path, realpath: value.realpath, device: value.device, inode: value.inode };
}

function validateActualExecutor(actual, card) {
  const identity = card.declared_target_and_actual_executor.actual_executor_identity;
  exactKeys(actual, [
    "executor_kind", "platform", "architecture", "node_path", "node_version", "node_byte_length", "node_sha256",
    "git_path", "git_version", "git_byte_length", "git_sha256", "container_runtime_observed",
    "declared_target_materialized",
  ], "EXECUTOR_EVIDENCE_REJECTED", "actual executor");
  assert(actual.executor_kind === "LOCAL_HOST_PROCESS", "EXECUTOR_EVIDENCE_REJECTED", "executor kind drift");
  for (const key of Object.keys(identity)) {
    assert(actual[key] === identity[key], "EXECUTOR_EVIDENCE_REJECTED", `actual executor ${key} drift`);
  }
  assert(actual.container_runtime_observed === false && actual.declared_target_materialized === false, "EXECUTOR_EVIDENCE_REJECTED", "actual executor falsely claims target/container execution");
  return canonicalize(actual);
}

function validateArtifactRecords(manifest, runRoot) {
  assert(Array.isArray(manifest.artifacts), "EVIDENCE_MANIFEST_REJECTED", "manifest artifacts is not an array");
  const seenPaths = new Set();
  const records = [];
  for (const record of manifest.artifacts) {
    assert(record && typeof record === "object" && !Array.isArray(record), "EVIDENCE_MANIFEST_REJECTED", "artifact record invalid");
    if (record.role === "command_stream") {
      exactKeys(record, ["role", "action_id", "stream", "path", "byte_length", "sha256"], "EVIDENCE_MANIFEST_REJECTED", "command stream record");
      assert(typeof record.action_id === "string" && ["stdout", "stderr"].includes(record.stream), "EVIDENCE_MANIFEST_REJECTED", "command stream binding invalid");
    } else {
      exactKeys(record, ["role", "path", "byte_length", "sha256"], "EVIDENCE_MANIFEST_REJECTED", "artifact record");
      assert([
        "candidate_manifest", "candidate_provenance", "observation", "patch", "patch_evidence_package",
        "run_record", "rollback_source",
      ].includes(record.role), "EVIDENCE_MANIFEST_REJECTED", `unknown artifact role ${record.role}`);
    }
    assert(!seenPaths.has(record.path), "EVIDENCE_MANIFEST_REJECTED", `duplicate artifact path ${record.path}`);
    seenPaths.add(record.path);
    const file = readContainedArtifact(runRoot, { path: record.path, byte_length: record.byte_length, sha256: record.sha256 });
    records.push({ record, file });
  }
  for (const role of [
    "candidate_manifest", "candidate_provenance", "observation", "patch", "patch_evidence_package",
    "run_record", "rollback_source",
  ]) {
    assert(records.filter((entry) => entry.record.role === role).length === 1, "EVIDENCE_MANIFEST_REJECTED", `${role} artifact population mismatch`);
  }
  return records;
}

function recordByRole(records, role) {
  const matches = records.filter((entry) => entry.record.role === role);
  assert(matches.length === 1, "EVIDENCE_MANIFEST_REJECTED", `${role} artifact population mismatch`);
  return matches[0];
}

function commandStreamRecord(records, actionId, stream) {
  const matches = records.filter((entry) => entry.record.role === "command_stream" && entry.record.action_id === actionId && entry.record.stream === stream);
  assert(matches.length === 1, "EVIDENCE_MANIFEST_REJECTED", `${actionId} ${stream} stream population mismatch`);
  return matches[0];
}

function normalizeStream(bytes, physical) {
  const text = bytes.toString("utf8");
  assert(Buffer.from(text, "utf8").equals(bytes), "COMMAND_STREAM_REJECTED", "command stream is not exact UTF-8");
  let normalized = text;
  const replacements = [
    [physical.materialization.path, "<TASK_REPOSITORY>"],
    [physical.materialization.realpath, "<TASK_REPOSITORY>"],
    [physical.run.path, "<RUN_ROOT>"],
    [physical.run.realpath, "<RUN_ROOT>"],
  ].sort((left, right) => right[0].length - left[0].length);
  for (const [source, replacement] of replacements) {
    if (source.length > 0) normalized = normalized.split(source).join(replacement);
  }
  normalized = normalized.replace(/duration_ms(?:[ \t]*:[ \t]*|[ \t]+)[0-9]+(?:\.[0-9]+)?/g, "duration_ms: <DURATION_MS>");
  for (const [source] of replacements) {
    assert(!normalized.includes(source), "STABLE_PROJECTION_REJECTED", "physical path survived normalization");
  }
  return Buffer.from(normalized, "utf8");
}

function validateCommand(command, records, physical, card) {
  exactKeys(command, card.run_evidence_contract.command_required_fields, "COMMAND_RECORD_REJECTED", `command ${command?.action_id ?? "unknown"}`);
  assert(typeof command.action_id === "string" && command.action_id.length > 0, "COMMAND_RECORD_REJECTED", "command action id invalid");
  assert(Array.isArray(command.argv) && command.argv.every((value) => typeof value === "string"), "COMMAND_RECORD_REJECTED", `${command.action_id} argv invalid`);
  assert(Object.values(card.fixed_commands).some((allowedArgv) => sameJson(command.argv, allowedArgv)), "COMMAND_RECORD_REJECTED", `${command.action_id} argv is not Quality-frozen`);
  assert(sameJson(command.argv_equivalent, command.argv), "COMMAND_RECORD_REJECTED", `${command.action_id} argv equivalent drift`);
  assert(command.cwd === physical.materialization.path || command.cwd === physical.materialization.realpath, "COMMAND_RECORD_REJECTED", `${command.action_id} cwd is not materialization root`);
  assert(command.cwd_equivalent === "TASK_REPOSITORY", "COMMAND_RECORD_REJECTED", `${command.action_id} cwd equivalent drift`);
  assert(Number.isInteger(command.exit_status), "COMMAND_RECORD_REJECTED", `${command.action_id} exit status invalid`);
  assert(command.signal === null || typeof command.signal === "string", "COMMAND_RECORD_REJECTED", `${command.action_id} signal invalid`);
  assert(command.timeout_ms === card.command_profile.timeout_ms, "COMMAND_RECORD_REJECTED", `${command.action_id} timeout drift`);
  assert(typeof command.duration_ms === "number" && Number.isFinite(command.duration_ms) && command.duration_ms >= 0, "COMMAND_RECORD_REJECTED", `${command.action_id} duration invalid`);
  exactKeys(command.stdout, ["path", "byte_length", "sha256"], "COMMAND_RECORD_REJECTED", `${command.action_id} stdout ref`);
  exactKeys(command.stderr, ["path", "byte_length", "sha256"], "COMMAND_RECORD_REJECTED", `${command.action_id} stderr ref`);
  const stdout = commandStreamRecord(records, command.action_id, "stdout");
  const stderr = commandStreamRecord(records, command.action_id, "stderr");
  assert(sameJson(command.stdout, { path: stdout.record.path, byte_length: stdout.record.byte_length, sha256: stdout.record.sha256 }), "COMMAND_RECORD_REJECTED", `${command.action_id} stdout manifest binding drift`);
  assert(sameJson(command.stderr, { path: stderr.record.path, byte_length: stderr.record.byte_length, sha256: stderr.record.sha256 }), "COMMAND_RECORD_REJECTED", `${command.action_id} stderr manifest binding drift`);
  const normalizedStdout = normalizeStream(stdout.file.bytes, physical);
  const normalizedStderr = normalizeStream(stderr.file.bytes, physical);
  return {
    action_id: command.action_id,
    argv_equivalent: [...command.argv],
    cwd_equivalent: "TASK_REPOSITORY",
    exit_status: command.exit_status,
    signal: command.signal,
    normalized_stdout_byte_length: normalizedStdout.length,
    normalized_stdout_sha256: sha256(normalizedStdout),
    normalized_stderr_byte_length: normalizedStderr.length,
    normalized_stderr_sha256: sha256(normalizedStderr),
  };
}

function requireCommand(commands, actionId, argv, exitStatus) {
  const matches = commands.filter((entry) => entry.raw.action_id === actionId);
  assert(matches.length === 1, "COMMAND_RECORD_REJECTED", `${actionId} command population mismatch`);
  const command = matches[0];
  assert(sameJson(command.raw.argv, argv), "COMMAND_RECORD_REJECTED", `${actionId} argv drift`);
  assert(command.raw.exit_status === exitStatus && command.raw.signal === null, "COMMAND_RECORD_REJECTED", `${actionId} result drift`);
  return command;
}

function commandBytes(records, command, stream) {
  return commandStreamRecord(records, command.raw.action_id, stream).file.bytes;
}

function requiredCommandSpecifications(card) {
  return [
    ["materialize_git_init", card.fixed_commands.git_init, 0],
    ["materialize_git_add", card.fixed_commands.git_add, 0],
    ["materialize_git_commit", card.fixed_commands.git_commit, 0],
    ["base_git_head", card.fixed_commands.git_head, 0],
    ["base_git_tree", card.fixed_commands.git_tree, 0],
    ["base_git_status", card.fixed_commands.git_status, 0],
    ["base_issue_test", card.fixed_commands.issue_test, 1],
    ["base_regression_test", card.fixed_commands.regression_test, 0],
    ["changed_path_git_status", card.fixed_commands.git_status, 0],
    ["patch_git_diff", card.fixed_commands.git_diff, 0],
    ["patched_issue_test", card.fixed_commands.issue_test, 0],
    ["patched_regression_test", card.fixed_commands.regression_test, 0],
    ["rollback_git_head", card.fixed_commands.git_head, 0],
    ["rollback_git_tree", card.fixed_commands.git_tree, 0],
    ["rollback_git_status", card.fixed_commands.git_status, 0],
  ];
}

function validateCompleteCommandEvidence(commands, records, card, patchEntry) {
  const specifications = requiredCommandSpecifications(card);
  assert(commands.length === specifications.length, "COMMAND_RECORD_REJECTED", "command population is not exact");
  const expectedIds = specifications.map(([actionId]) => actionId);
  assert(sameJson(commands.map((entry) => entry.raw.action_id), expectedIds), "COMMAND_RECORD_REJECTED", "command order or population drifted");
  const byId = Object.fromEntries(specifications.map(([actionId, argv, exitStatus]) => {
    const command = requireCommand(commands, actionId, argv, exitStatus);
    return [actionId, command];
  }));
  for (const actionId of [
    "materialize_git_init", "materialize_git_add", "materialize_git_commit", "base_git_head", "base_git_tree",
    "base_git_status", "changed_path_git_status", "patch_git_diff", "rollback_git_head", "rollback_git_tree",
    "rollback_git_status",
  ]) {
    assert(commandBytes(records, byId[actionId], "stderr").length === 0, "COMMAND_STREAM_REJECTED", `${actionId} stderr is not empty`);
  }
  for (const actionId of ["materialize_git_init", "materialize_git_add", "materialize_git_commit", "base_git_status", "rollback_git_status"]) {
    assert(commandBytes(records, byId[actionId], "stdout").length === 0, "COMMAND_STREAM_REJECTED", `${actionId} stdout is not empty`);
  }
  const exactLine = (actionId, expected) => {
    const bytes = commandBytes(records, byId[actionId], "stdout");
    assert(bytes.equals(Buffer.from(`${expected}\n`, "utf8")), "COMMAND_STREAM_REJECTED", `${actionId} stdout identity drift`);
  };
  exactLine("base_git_head", EXPECTED_BASE.commit);
  exactLine("base_git_tree", EXPECTED_BASE.tree);
  exactLine("rollback_git_head", EXPECTED_BASE.commit);
  exactLine("rollback_git_tree", EXPECTED_BASE.tree);
  const changedStatus = commandBytes(records, byId.changed_path_git_status, "stdout");
  assert(changedStatus.equals(Buffer.from(" M src/range.mjs\0", "utf8")), "CHANGED_PATH_SCOPE_REJECTED", "changed-path status stream drift");
  const patchBytes = commandBytes(records, byId.patch_git_diff, "stdout");
  assert(patchBytes.length > 0 && patchBytes.equals(patchEntry.file.bytes), "PATCH_EVIDENCE_PACKAGE_REJECTED", "patch artifact is not exact command output");
  const patchText = patchBytes.toString("utf8");
  assert(Buffer.from(patchText, "utf8").equals(patchBytes), "PATCH_EVIDENCE_PACKAGE_REJECTED", "patch diff is not exact UTF-8");
  assert(patchText.startsWith("diff --git a/src/range.mjs b/src/range.mjs\n") && patchText.includes("--- a/src/range.mjs\n") && patchText.includes("+++ b/src/range.mjs\n"), "PATCH_EVIDENCE_PACKAGE_REJECTED", "patch diff path semantics drift");
  const streamActionIds = [...new Set(records.filter((entry) => entry.record.role === "command_stream").map((entry) => entry.record.action_id))];
  assert(sameJson(streamActionIds.sort(), [...expectedIds].sort()), "COMMAND_RECORD_REJECTED", "command stream population drifted");
  return { byId, patchIdentity: patchEntry.file.identity };
}

function validateRetainedMaterialization(materialization, card) {
  const head = readGit(materialization.path, ["rev-parse", "HEAD"], "ROLLBACK_REJECTED", "retained materialization HEAD").toString("utf8").trim();
  const tree = readGit(materialization.path, ["rev-parse", "HEAD^{tree}"], "ROLLBACK_REJECTED", "retained materialization tree").toString("utf8").trim();
  const status = readGit(materialization.path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], "ROLLBACK_REJECTED", "retained materialization status");
  assert(head === EXPECTED_BASE.commit && tree === EXPECTED_BASE.tree && status.length === 0, "ROLLBACK_REJECTED", "retained materialization is not exact clean base");
  safeReadRegular(join(materialization.path, "src/range.mjs"), card.accepted_inputs.source_preimage, "ROLLBACK_REJECTED", "retained restored source");
  return { head, tree, workspace_status: "clean", source: card.accepted_inputs.source_preimage };
}

function validateTests(observation, commands, records, card) {
  exactKeys(observation.base_tests, ["issue", "regression"], "TEST_EVIDENCE_REJECTED", "base tests");
  exactKeys(observation.patched_tests, ["issue", "regression"], "TEST_EVIDENCE_REJECTED", "patched tests");
  const baseIssue = requireCommand(commands, "base_issue_test", card.fixed_commands.issue_test, 1);
  const baseRegression = requireCommand(commands, "base_regression_test", card.fixed_commands.regression_test, 0);
  const patchedIssue = requireCommand(commands, "patched_issue_test", card.fixed_commands.issue_test, 0);
  const patchedRegression = requireCommand(commands, "patched_regression_test", card.fixed_commands.regression_test, 0);
  const expectedTestRef = (actionId, exitStatus) => ({ action_id: actionId, exit_status: exitStatus });
  assert(sameJson(observation.base_tests.issue, expectedTestRef("base_issue_test", 1)), "TEST_EVIDENCE_REJECTED", "base issue test binding drift");
  assert(sameJson(observation.base_tests.regression, expectedTestRef("base_regression_test", 0)), "TEST_EVIDENCE_REJECTED", "base regression test binding drift");
  assert(sameJson(observation.patched_tests.issue, expectedTestRef("patched_issue_test", 0)), "TEST_EVIDENCE_REJECTED", "patched issue test binding drift");
  assert(sameJson(observation.patched_tests.regression, expectedTestRef("patched_regression_test", 0)), "TEST_EVIDENCE_REJECTED", "patched regression test binding drift");
  const baseIssueStdout = commandStreamRecord(records, baseIssue.raw.action_id, "stdout").file.bytes.toString("utf8");
  const baseIssueStderr = commandStreamRecord(records, baseIssue.raw.action_id, "stderr").file.bytes.toString("utf8");
  const baseCombined = `${baseIssueStdout}\n${baseIssueStderr}`;
  assert(baseCombined.includes("not ok") && baseCombined.includes("REP001_NEGATIVE_RANGE_ORDER"), "TEST_EVIDENCE_REJECTED", "base issue failure is not frozen typed failure");
  for (const token of ["SyntaxError", "ERR_MODULE_NOT_FOUND", "MODULE_NOT_FOUND", "ENOENT", "timeout", "signal"]) {
    assert(!baseCombined.includes(token), "TEST_EVIDENCE_REJECTED", `base issue contains forbidden token ${token}`);
  }
  return {
    base: { issue: baseIssue.raw.exit_status, regression: baseRegression.raw.exit_status },
    patched: { issue: patchedIssue.raw.exit_status, regression: patchedRegression.raw.exit_status },
  };
}

function validateRollback(rollback, rollbackArtifact, card) {
  if (rollback === null || rollback === undefined) fail("ROLLBACK_EVIDENCE_MISSING", "rollback observation missing");
  exactKeys(rollback, [
    "mutation_occurred", "source_artifact_path", "restored_source_byte_length", "restored_source_sha256",
    "base_commit", "base_tree", "git_status_porcelain", "restored_exact_base",
  ], "ROLLBACK_REJECTED", "rollback");
  assert(rollback.source_artifact_path === rollbackArtifact.record.path, "ROLLBACK_REJECTED", "rollback source artifact binding drift");
  assert(rollbackArtifact.file.bytes.length === EXPECTED_BASE.source_byte_length && sha256(rollbackArtifact.file.bytes) === EXPECTED_BASE.source_sha256, "ROLLBACK_REJECTED", "rollback source bytes drift");
  const expected = card.rollback;
  assert(rollback.mutation_occurred === expected.mutation_occurred && rollback.restored_source_byte_length === expected.restored_source_byte_length && rollback.restored_source_sha256 === expected.restored_source_sha256, "ROLLBACK_REJECTED", "rollback source receipt drift");
  assert(rollback.base_commit === expected.restored_base_commit && rollback.base_tree === expected.restored_base_tree && rollback.git_status_porcelain === "" && rollback.restored_exact_base === true, "ROLLBACK_REJECTED", "rollback Git identity drift");
  return {
    mutation_occurred: true,
    restored_source_byte_length: EXPECTED_BASE.source_byte_length,
    restored_source_sha256: EXPECTED_BASE.source_sha256,
    base_commit: EXPECTED_BASE.commit,
    base_tree: EXPECTED_BASE.tree,
    git_status_porcelain: "",
    restored_exact_base: true,
  };
}

function validateRunRecord(value, manifest, environment, system, artifactRecords) {
  validateSchemaOrFail(value, RUN_RECORD_SCHEMA_PATH, "RUN_RECORD_REJECTED", "RunRecord");
  assert(value.run_id === manifest.run_id && value.task_id === CONTROL_ID && value.dataset_version === "1.0.0", "RUN_RECORD_REJECTED", "RunRecord run/task binding drift");
  assert(value.adapter_id === "B0" && value.adapter_version === system.adapter_version, "RUN_RECORD_REJECTED", "RunRecord adapter binding drift");
  assert(value.environment_snapshot_id === environment.snapshot_id && value.system_configuration_id === system.configuration_id, "RUN_RECORD_REJECTED", "RunRecord environment/config binding drift");
  assert(value.repetition_id === manifest.repetition_id, "RUN_RECORD_REJECTED", "RunRecord repetition binding drift");
  assert(value.terminal_status === "completed" && value.stop_reason_code === "agent_complete" && value.invalid_run_reason === null, "RUN_RECORD_REJECTED", "RunRecord terminal status drift");
  assert(value.verification_ref === null, "RUN_RECORD_REJECTED", "Runner claimed independent verification");
  const observationRecord = recordByRole(artifactRecords, "observation").record;
  const patchRecord = recordByRole(artifactRecords, "patch").record;
  assert(value.trace_ref === observationRecord.path && value.patch_ref === patchRecord.path, "RUN_RECORD_REJECTED", "RunRecord trace or patch reference drift");
  const expectedTestRefs = ["base_issue_test", "base_regression_test", "patched_issue_test", "patched_regression_test"]
    .map((actionId) => commandStreamRecord(artifactRecords, actionId, "stdout").record.path);
  assert(sameJson(value.test_artifact_refs, expectedTestRefs), "RUN_RECORD_REJECTED", "RunRecord test artifact references drift");
  assert(sameJson(value.policy_violations, []), "RUN_RECORD_REJECTED", "RunRecord policy violation present");
  const usage = value.usage;
  for (const [key, expected] of Object.entries({ input_tokens: 0, output_tokens: 0, tool_calls: 0, retries: 0, human_interventions: 0, cost_usd: 0 })) {
    assert(usage[key] === expected, "RUN_RECORD_REJECTED", `RunRecord usage ${key} drift`);
  }
  const expectedChecksums = Object.fromEntries(
    artifactRecords
      .filter((entry) => entry.record.role !== "run_record")
      .map((entry) => [entry.record.path, entry.record.sha256])
      .sort(([left], [right]) => left.localeCompare(right)),
  );
  assert(sameJson(value.artifact_checksums, expectedChecksums), "RUN_RECORD_REJECTED", "RunRecord artifact checksum set drift");
  return {
    schema_status: "PASS",
    terminal_status: "completed",
    stop_reason_code: "agent_complete",
    invalid_run_reason: null,
    verification_ref_before_independent_evaluation: null,
    policy_violations: [],
  };
}

function validateObservation(value, manifest, records, assets, physical) {
  const card = assets.card;
  exactKeys(value, card.run_evidence_contract.observation_required_fields, "RUN_OBSERVATION_REJECTED", "run observation");
  assert(value.schema_version === 1 && value.record_type === card.run_evidence_contract.observation_record_type, "RUN_OBSERVATION_REJECTED", "observation schema or record type drift");
  assert(value.task_id === TASK_ID && value.control_id === CONTROL_ID, "RUN_OBSERVATION_REJECTED", "observation task binding drift");
  assert(value.run_id === manifest.run_id && value.repetition_id === manifest.repetition_id, "RUN_BINDING_REJECTED", "observation run binding drift");
  const candidate = validateCandidateBinding(value.candidate_binding);
  assert(sameJson(candidate, manifest.candidate_binding), "RUN_BINDING_REJECTED", "observation candidate binding drift");
  exactKeys(value.physical_receipt, ["run_root", "materialization_root"], "RUN_OBSERVATION_REJECTED", "physical receipt");
  assert(sameJson(value.physical_receipt.run_root, manifest.run_root_receipt), "RUN_BINDING_REJECTED", "observation run root receipt drift");
  assert(sameJson(value.bindings, expectedBindings(card)), "INPUT_IDENTITY_REJECTED", "observation input bindings drift");
  const actualExecutor = validateActualExecutor(value.actual_executor, card);
  assert(sameJson(value.ordered_action_ids, card.required_actions_in_order), "ACTION_SCHEDULE_REJECTED", "action schedule drift");
  exactKeys(value.admission, ["status", "result_count", "program_id", "outcome_id", "postimage_byte_length", "postimage_sha256"], "ADMISSION_EVIDENCE_REJECTED", "admission");
  assert(value.admission.status === "ADMITTED_EXACT_IR10" && value.admission.result_count === 1 && value.admission.program_id === "IR10" && value.admission.outcome_id === "CORRECT_END_START", "ADMISSION_EVIDENCE_REJECTED", "admission outcome drift");
  assert(value.admission.postimage_byte_length === EXPECTED_POSTIMAGE.byte_length && value.admission.postimage_sha256 === EXPECTED_POSTIMAGE.sha256, "ADMISSION_EVIDENCE_REJECTED", "admission postimage drift");
  assert(Array.isArray(value.commands), "COMMAND_RECORD_REJECTED", "commands are not an array");
  const commandIds = value.commands.map((entry) => entry.action_id);
  assert(new Set(commandIds).size === commandIds.length, "COMMAND_RECORD_REJECTED", "duplicate command action id");
  const commands = value.commands.map((raw) => ({ raw, stable: validateCommand(raw, records, physical, card) }));
  const commandEvidence = validateCompleteCommandEvidence(commands, records, card, recordByRole(records, "patch"));
  const tests = validateTests(value, commands, records, card);
  assert(sameJson(value.changed_paths, ["src/range.mjs"]), "CHANGED_PATH_SCOPE_REJECTED", "changed path scope drift");
  const rollback = validateRollback(value.rollback, recordByRole(records, "rollback_source"), card);
  const retainedMaterialization = validateRetainedMaterialization(physical.materialization, card);
  assert(sameJson(value.external_effects, FALSE_EFFECTS), "EXTERNAL_EFFECT_OBSERVED", "external effect observed");
  assert(value.agent_status === "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED", "RUN_OBSERVATION_REJECTED", "agent status drift");
  assert(value.claim_boundary === CLAIM_BOUNDARY, "RUN_OBSERVATION_REJECTED", "observation claim boundary drift");
  return { candidate, actualExecutor, commands, commandEvidence, tests, rollback, retainedMaterialization };
}

function artifactRef(entry) {
  return { path: entry.record.path, byte_length: entry.record.byte_length, sha256: entry.record.sha256 };
}

function validatePatchEvidencePackage(records, manifest, assets, physical, evaluated, candidateProvenance) {
  const entry = recordByRole(records, "patch_evidence_package");
  const value = parseJsonBytes(entry.file.bytes, "PATCH_EVIDENCE_PACKAGE_REJECTED", "Patch Evidence Package");
  const mandatorySections = [
    "manifest", "source_identity", "environment", "understanding", "plan", "actions", "patch", "tests",
    "verification", "risk", "approval", "rollback",
  ];
  exactKeys(value, ["schema_version", "record_type", "task_id", "run_id", ...mandatorySections], "PATCH_EVIDENCE_PACKAGE_REJECTED", "Patch Evidence Package");
  assert(value.schema_version === 1 && value.record_type === "sourcelens_aios_p1_066_patch_evidence_package" && value.task_id === TASK_ID && value.run_id === manifest.run_id, "PATCH_EVIDENCE_PACKAGE_REJECTED", "Patch Evidence Package identity drift");

  exactKeys(value.manifest, ["schema_version", "task_id", "run_id", "artifact_checksums_bound_by_run_manifest"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package manifest section");
  assert(value.manifest.schema_version === manifest.schema_version && value.manifest.task_id === manifest.task_id && value.manifest.run_id === manifest.run_id && value.manifest.artifact_checksums_bound_by_run_manifest === true, "PATCH_EVIDENCE_PACKAGE_REJECTED", "package manifest binding drift");

  exactKeys(value.source_identity, ["candidate_binding", "candidate_repository", "materialized_base"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package source identity");
  assert(sameJson(value.source_identity.candidate_binding, evaluated.candidate), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package candidate binding drift");
  assert(sameJson(value.source_identity.candidate_repository, candidateProvenance.repository), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package candidate repository identity drift");
  assert(sameJson(value.source_identity.materialized_base, {
    commit: EXPECTED_BASE.commit,
    tree: EXPECTED_BASE.tree,
    workspace_status_before: "clean",
    workspace_status_after_rollback: "clean",
  }), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package materialized source identity drift");

  exactKeys(value.environment, ["target_runtime", "environment_snapshot", "system_configuration", "actual_executor"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package environment");
  assert(sameJson(value.environment, {
    target_runtime: assets.card.quality_assets.target_runtime,
    environment_snapshot: assets.card.quality_assets.environment_snapshot,
    system_configuration: assets.card.quality_assets.system_configuration,
    actual_executor: evaluated.actualExecutor,
  }), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package environment binding drift");

  exactKeys(value.understanding, ["issue_id", "interpretation", "repository_evidence_references"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package understanding");
  assert(value.understanding.issue_id === "REP001_NEGATIVE_RANGE_ORDER" && typeof value.understanding.interpretation === "string" && value.understanding.interpretation.length > 0, "PATCH_EVIDENCE_PACKAGE_REJECTED", "package understanding drift");
  assert(sameJson(value.understanding.repository_evidence_references, [
    assets.card.accepted_inputs.task_spec.path,
    assets.card.accepted_inputs.expected_base_failure.path,
    assets.card.accepted_inputs.source_preimage.path,
  ]), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package repository evidence references drift");

  exactKeys(value.plan, ["bounded_intended_changes", "mutation_kind", "risks"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package plan");
  assert(sameJson(value.plan.bounded_intended_changes, ["src/range.mjs"]) && value.plan.mutation_kind === "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT" && Array.isArray(value.plan.risks) && value.plan.risks.length > 0, "PATCH_EVIDENCE_PACKAGE_REJECTED", "package plan drift");

  exactKeys(value.actions, ["ordered_action_ids", "command_action_ids", "observation_artifact"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package actions");
  assert(sameJson(value.actions.ordered_action_ids, assets.card.required_actions_in_order), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package action schedule drift");
  assert(sameJson(value.actions.command_action_ids, requiredCommandSpecifications(assets.card).map(([actionId]) => actionId)), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package command schedule drift");
  assert(sameJson(value.actions.observation_artifact, artifactRef(recordByRole(records, "observation"))), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package observation reference drift");

  const patchEntry = recordByRole(records, "patch");
  exactKeys(value.patch, ["changed_paths", "diff", "postimage"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package patch");
  assert(sameJson(value.patch.changed_paths, ["src/range.mjs"]) && sameJson(value.patch.diff, artifactRef(patchEntry)) && sameJson(value.patch.postimage, EXPECTED_POSTIMAGE), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package patch binding drift");

  exactKeys(value.tests, ["base_issue", "base_regression", "patched_issue", "patched_regression"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package tests");
  assert(sameJson(value.tests, {
    base_issue: { action_id: "base_issue_test", exit_status: 1 },
    base_regression: { action_id: "base_regression_test", exit_status: 0 },
    patched_issue: { action_id: "patched_issue_test", exit_status: 0 },
    patched_regression: { action_id: "patched_regression_test", exit_status: 0 },
  }), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package test evidence drift");

  exactKeys(value.verification, ["required", "evaluator", "status", "runner_reported_pass_authoritative"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package verification");
  assert(value.verification.required === true && value.verification.status === "PENDING_INDEPENDENT_EVALUATION" && value.verification.runner_reported_pass_authoritative === false, "PATCH_EVIDENCE_PACKAGE_REJECTED", "package verification state drift");
  assert(sameJson(value.verification.evaluator, { path: assets.card.quality_evaluator_interface.module_path, version: QUALITY_ORACLE_VERSION }), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package evaluator identity drift");

  exactKeys(value.risk, ["changed_path_scope", "external_effects", "declared_target_materialized", "container_execution_observed", "residual_claim_boundary"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package risk");
  assert(sameJson(value.risk.changed_path_scope, ["src/range.mjs"]) && sameJson(value.risk.external_effects, FALSE_EFFECTS) && value.risk.declared_target_materialized === false && value.risk.container_execution_observed === false && value.risk.residual_claim_boundary === CLAIM_BOUNDARY, "PATCH_EVIDENCE_PACKAGE_REJECTED", "package risk boundary drift");

  exactKeys(value.approval, ["required_roles", "actual_state", "runner_self_approval"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package approval");
  assert(sameJson(value.approval.required_roles, ["CTO", "Security", "Quality"]) && value.approval.actual_state === "PENDING_TASK_GATE" && value.approval.runner_self_approval === false, "PATCH_EVIDENCE_PACKAGE_REJECTED", "package approval state drift");

  exactKeys(value.rollback, ["source_artifact_path", "restored_source_byte_length", "restored_source_sha256", "restored_base_commit", "restored_base_tree", "restored_workspace_status", "disposable_workspace_receipt"], "PATCH_EVIDENCE_PACKAGE_REJECTED", "package rollback");
  assert(value.rollback.source_artifact_path === recordByRole(records, "rollback_source").record.path && value.rollback.restored_source_byte_length === EXPECTED_BASE.source_byte_length && value.rollback.restored_source_sha256 === EXPECTED_BASE.source_sha256 && value.rollback.restored_base_commit === EXPECTED_BASE.commit && value.rollback.restored_base_tree === EXPECTED_BASE.tree && value.rollback.restored_workspace_status === "clean", "PATCH_EVIDENCE_PACKAGE_REJECTED", "package rollback binding drift");
  assert(sameJson(value.rollback.disposable_workspace_receipt, physical.materialization), "PATCH_EVIDENCE_PACKAGE_REJECTED", "package disposable workspace receipt drift");

  return {
    mandatory_sections: mandatorySections,
    mandatory_fields_present: true,
    artifact_checksums_recomputed: true,
    candidate_provenance_verified: true,
    command_population_verified: true,
    patch_diff_byte_length: patchEntry.file.identity.byte_length,
    patch_diff_sha256: patchEntry.file.identity.sha256,
    verification_transition: "PENDING_INDEPENDENT_EVALUATION_TO_PASS",
    approval_state_at_run: "PENDING_TASK_GATE",
  };
}

function stableInputIdentities(card) {
  const selected = {
    task_spec: card.accepted_inputs.task_spec,
    expected_base_failure: card.accepted_inputs.expected_base_failure,
    materialization_recipe: card.accepted_inputs.materialization_recipe,
    baseline_context: card.accepted_inputs.baseline_context,
    response_format: card.accepted_inputs.response_format,
    source_preimage: card.accepted_inputs.source_preimage,
    issue_test: card.accepted_inputs.issue_test,
    regression_test: card.accepted_inputs.regression_test,
    compiler: card.accepted_inputs.compiler,
    ir10: card.accepted_inputs.ir10,
    target_runtime: card.quality_assets.target_runtime,
    environment_snapshot: card.quality_assets.environment_snapshot,
    system_configuration: card.quality_assets.system_configuration,
    positive_result: card.quality_assets.positive_result,
    negative_cases: card.quality_assets.negative_cases,
  };
  return canonicalize(selected);
}

export function evaluateRunEvidence(runManifestPath, prevalidatedAssets = undefined) {
  assert(typeof runManifestPath === "string" && isAbsolute(runManifestPath), "RUN_MANIFEST_REJECTED", "run manifest path must be absolute");
  const assets = prevalidatedAssets ?? validateQualityAssets();
  const manifestFile = safeReadRegular(runManifestPath, undefined, "RUN_MANIFEST_REJECTED", "run manifest");
  const manifest = parseJsonBytes(manifestFile.bytes, "RUN_MANIFEST_REJECTED", "run manifest");
  exactKeys(manifest, assets.card.run_evidence_contract.manifest_required_fields, "RUN_MANIFEST_REJECTED", "run manifest");
  assert(manifest.schema_version === 1 && manifest.record_type === assets.card.run_evidence_contract.manifest_record_type, "RUN_MANIFEST_REJECTED", "run manifest schema or record type drift");
  assert(manifest.task_id === TASK_ID && manifest.control_id === CONTROL_ID, "RUN_MANIFEST_REJECTED", "run manifest task binding drift");
  assert(/^[a-z0-9][a-z0-9._-]{0,63}$/.test(manifest.run_id) && Number.isInteger(manifest.repetition_id) && manifest.repetition_id >= 1, "RUN_MANIFEST_REJECTED", "run id or repetition invalid");
  const candidate = validateCandidateBinding(manifest.candidate_binding);
  assert(manifest.agent_status === "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED", "RUN_MANIFEST_REJECTED", "manifest agent status drift");
  const runReceipt = validateDirectoryReceipt(manifest.run_root_receipt, "RUN_ROOT_REJECTED", "run root");
  assert(resolve(dirname(runManifestPath)) === resolve(runReceipt.path), "RUN_BINDING_REJECTED", "manifest is not in bound run root");
  const records = validateArtifactRecords(manifest, runReceipt.path);
  const candidateProvenance = validateCandidateProvenance(records, candidate, assets.card);
  const observationEntry = recordByRole(records, "observation");
  const runRecordEntry = recordByRole(records, "run_record");
  const observation = parseJsonBytes(observationEntry.file.bytes, "RUN_OBSERVATION_REJECTED", "run observation");
  assert(observation.physical_receipt?.materialization_root, "RUN_OBSERVATION_REJECTED", "materialization receipt missing");
  const materializationReceipt = validateDirectoryReceipt(observation.physical_receipt.materialization_root, "MATERIALIZATION_ROOT_REJECTED", "materialization root");
  const materializationRel = relative(runReceipt.path, materializationReceipt.path);
  assert(materializationRel !== "" && materializationRel !== ".." && !materializationRel.startsWith("../") && !isAbsolute(materializationRel), "MATERIALIZATION_ROOT_REJECTED", "materialization root escaped run root");
  const physical = { run: runReceipt, materialization: materializationReceipt };
  const evaluated = validateObservation(observation, manifest, records, assets, physical);
  const patchEvidencePackageStatus = validatePatchEvidencePackage(
    records,
    manifest,
    assets,
    physical,
    evaluated,
    candidateProvenance,
  );
  const runRecord = parseJsonBytes(runRecordEntry.file.bytes, "RUN_RECORD_REJECTED", "RunRecord");
  const runRecordStatus = validateRunRecord(runRecord, manifest, assets.environment, assets.system, records);

  const stableProjection = {
    schema_version: 1,
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    candidate_binding: candidate,
    candidate_provenance: candidateProvenance,
    input_identities: stableInputIdentities(assets.card),
    declared_target_runtime: {
      target_runtime_id: assets.quality.target_runtime.value.target_runtime_id,
      kind: "DECLARED_SYNTHETIC_TARGET",
      materialized: false,
      container_execution_observed: false,
    },
    actual_executor_identity: evaluated.actualExecutor,
    environment_snapshot_id: assets.environment.snapshot_id,
    system_configuration_id: assets.system.configuration_id,
    admission: canonicalize(observation.admission),
    ordered_action_ids: [...assets.card.required_actions_in_order],
    commands: evaluated.commands.map((entry) => entry.stable),
    base_tests: evaluated.tests.base,
    patched_tests: evaluated.tests.patched,
    changed_paths: ["src/range.mjs"],
    patch_evidence_package_status: patchEvidencePackageStatus,
    run_record_status: runRecordStatus,
    rollback: evaluated.rollback,
    external_effects: FALSE_EFFECTS,
    evaluator: {
      version: QUALITY_ORACLE_VERSION,
      artifact_hashes_recomputed: true,
      runner_reported_pass_authoritative: false,
      verdict: "PASS",
    },
    complete_evidence: patchEvidencePackageStatus.mandatory_fields_present === true && candidateProvenance.evaluation_time_recomputation_verified === true,
    verdict: "PASS",
    claim_boundary: CLAIM_BOUNDARY,
  };
  assert(stableProjection.complete_evidence === true, "PATCH_EVIDENCE_PACKAGE_REJECTED", "complete Evidence was not independently established");
  const declaredStableKeys = [...assets.card.stable_projection.include].sort();
  assert(sameJson(Object.keys(stableProjection).sort(), declaredStableKeys), "STABLE_PROJECTION_REJECTED", "stable projection field set drift");
  const stableBytes = canonicalJsonBytes(stableProjection);
  for (const physicalValue of [runReceipt.path, runReceipt.realpath, materializationReceipt.path, materializationReceipt.realpath]) {
    assert(!stableBytes.includes(Buffer.from(physicalValue, "utf8")), "STABLE_PROJECTION_REJECTED", "physical path survived stable projection");
  }
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_066_quality_run_evaluation",
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: manifest.run_id,
    repetition_id: manifest.repetition_id,
    candidate_binding: candidate,
    run_root_receipt: runReceipt,
    materialization_root_receipt: materializationReceipt,
    run_manifest_identity: manifestFile.identity,
    stable_projection: stableProjection,
    stable_projection_byte_length: stableBytes.length,
    stable_projection_sha256: sha256(stableBytes),
    target_verdict: "PASS",
  };
}

export function compareStableRuns(runAInput, runBInput) {
  const assets = validateQualityAssets();
  const runA = typeof runAInput === "string" ? evaluateRunEvidence(runAInput, assets) : runAInput;
  const runB = typeof runBInput === "string" ? evaluateRunEvidence(runBInput, assets) : runBInput;
  assert(runA?.target_verdict === "PASS" && runB?.target_verdict === "PASS", "STABLE_RUN_COMPARISON_REJECTED", "one run is not Quality PASS");
  assert(runA.run_id !== runB.run_id, "RUN_BINDING_REJECTED", "Run A and Run B ids are not distinct");
  assert(runA.run_root_receipt.realpath !== runB.run_root_receipt.realpath && runA.run_root_receipt.inode !== runB.run_root_receipt.inode, "RUN_BINDING_REJECTED", "Run A and Run B roots are not physically distinct");
  assert(runA.materialization_root_receipt.realpath !== runB.materialization_root_receipt.realpath && runA.materialization_root_receipt.inode !== runB.materialization_root_receipt.inode, "RUN_BINDING_REJECTED", "Run A and Run B materializations are not physically distinct");
  assert(sameJson(runA.candidate_binding, runB.candidate_binding), "CANDIDATE_BINDING_REJECTED", "Run A and Run B candidate bindings differ");
  const stableA = canonicalJsonBytes(runA.stable_projection);
  const stableB = canonicalJsonBytes(runB.stable_projection);
  assert(stableA.equals(stableB), "STABLE_PROJECTION_MISMATCH", `stable projection mismatch A=${sha256(stableA)} B=${sha256(stableB)}`);
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_066_stable_run_comparison",
    task_id: TASK_ID,
    run_a_id: runA.run_id,
    run_b_id: runB.run_id,
    candidate_binding: runA.candidate_binding,
    physical_roots_distinct: true,
    stable_projection_exact_byte_equal: true,
    stable_projection_byte_length: stableA.length,
    stable_projection_sha256: sha256(stableA),
    target_verdict: "PASS",
    claim_boundary: CLAIM_BOUNDARY,
  };
}

function directoryReceipt(path) {
  const stat = lstatSync(path);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), "SELF_TEST_SETUP_FAILED", `not a real directory: ${path}`);
  return { path, realpath: realpathSync(path), device: stat.dev, inode: stat.ino };
}

function relativeFileRecord(root, relativePath, bytes) {
  const path = join(root, relativePath);
  const receipt = createExclusiveFile(path, bytes);
  return { path: relativePath, byte_length: receipt.byte_length, sha256: receipt.sha256 };
}

function mockActualExecutor(card) {
  return {
    executor_kind: "LOCAL_HOST_PROCESS",
    ...card.declared_target_and_actual_executor.actual_executor_identity,
    container_runtime_observed: false,
    declared_target_materialized: false,
  };
}

function mockGitEnvironment(card, home) {
  return { ...card.command_profile.environment, HOME: home };
}

function initializeMockMaterialization(root, materialization, assets) {
  const card = assets.card;
  const home = join(root, "home");
  mkdirSync(home, { mode: 0o700 });
  mkdirSync(join(materialization, "src"), { mode: 0o700 });
  mkdirSync(join(materialization, "test"), { mode: 0o700 });
  createExclusiveFile(join(materialization, "src/range.mjs"), assets.accepted.source_preimage.bytes);
  createExclusiveFile(join(materialization, "test/issue.test.mjs"), assets.accepted.issue_test.bytes);
  createExclusiveFile(join(materialization, "test/regression.test.mjs"), assets.accepted.regression_test.bytes);
  const environment = mockGitEnvironment(card, home);
  const runFixed = (argv, label) => {
    const outcome = spawnSync(argv[0], argv.slice(1), {
      cwd: materialization,
      env: environment,
      encoding: null,
      timeout: card.command_profile.timeout_ms,
      maxBuffer: card.command_profile.max_buffer_bytes,
      windowsHide: true,
    });
    assert(!outcome.error && outcome.status === 0 && outcome.signal === null, "SELF_TEST_SETUP_FAILED", `${label} failed`);
    assert((outcome.stderr?.length ?? 0) === 0, "SELF_TEST_SETUP_FAILED", `${label} emitted stderr`);
    return Buffer.isBuffer(outcome.stdout) ? outcome.stdout : Buffer.alloc(0);
  };
  runFixed(card.fixed_commands.git_init, "mock git init");
  runFixed(card.fixed_commands.git_add, "mock git add");
  runFixed(card.fixed_commands.git_commit, "mock git commit");
  const head = runFixed(card.fixed_commands.git_head, "mock git head");
  const tree = runFixed(card.fixed_commands.git_tree, "mock git tree");
  const clean = runFixed(card.fixed_commands.git_status, "mock git clean status");
  assert(head.equals(Buffer.from(`${EXPECTED_BASE.commit}\n`)) && tree.equals(Buffer.from(`${EXPECTED_BASE.tree}\n`)) && clean.length === 0, "SELF_TEST_SETUP_FAILED", "mock base identity drift");
  writeFileSync(join(materialization, "src/range.mjs"), assets.positive.compiled.postimage);
  const changedStatus = runFixed(card.fixed_commands.git_status, "mock changed status");
  const patch = runFixed(card.fixed_commands.git_diff, "mock patch diff");
  writeFileSync(join(materialization, "src/range.mjs"), assets.accepted.source_preimage.bytes);
  const rollbackStatus = runFixed(card.fixed_commands.git_status, "mock rollback status");
  assert(changedStatus.equals(Buffer.from(" M src/range.mjs\0")) && patch.length > 0 && rollbackStatus.length === 0, "SELF_TEST_SETUP_FAILED", "mock patch or rollback drift");
  return { head, tree, changedStatus, patch };
}

function currentCandidateManifestForMock() {
  const observed = currentCandidateRepositoryProvenance();
  const qualityFreeze = safeReadRegular(QUALITY_FREEZE_MANIFEST_PATH, undefined, "SELF_TEST_SETUP_FAILED", "Quality Freeze V3 manifest");
  return {
    value: {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_066_exact_candidate_manifest_v2",
      task_id: TASK_ID,
      candidate_commit: observed.repository.head,
      candidate_tree: observed.repository.tree,
      quality_freeze_manifest_sha256: qualityFreeze.identity.sha256,
      repository: {
        path: observed.repository.path,
        realpath: observed.repository.realpath,
        head: observed.repository.head,
        tree: observed.repository.tree,
        workspace_status: "clean",
      },
      executing_modules: observed.executing_modules,
    },
    observed,
  };
}

function buildMockRun(parent, runId, repetitionId, assets, options = {}) {
  const root = join(parent, runId);
  mkdirSync(root, { mode: 0o700 });
  const materialization = join(root, "materialization");
  const streamsRoot = join(root, "streams");
  mkdirSync(materialization, { mode: 0o700 });
  mkdirSync(streamsRoot, { mode: 0o700 });
  const card = assets.card;
  const mock = initializeMockMaterialization(root, materialization, assets);
  const runReceipt = directoryReceipt(root);
  const materializationReceipt = directoryReceipt(materialization);
  const physical = { run_root: runReceipt, materialization_root: materializationReceipt };

  const currentCandidate = currentCandidateManifestForMock();
  const candidateManifestBytes = canonicalJsonBytes(currentCandidate.value);
  const candidateManifestRecord = relativeFileRecord(root, "candidate-manifest.json", candidateManifestBytes);
  const candidate = {
    candidate_commit: currentCandidate.value.candidate_commit,
    candidate_tree: currentCandidate.value.candidate_tree,
    candidate_manifest_sha256: candidateManifestRecord.sha256,
    quality_freeze_manifest_sha256: currentCandidate.value.quality_freeze_manifest_sha256,
  };
  const artifactRecords = [{ role: "candidate_manifest", ...candidateManifestRecord }];
  const candidateProvenance = {
    schema_version: 1,
    record_type: card.candidate_provenance_contract.provenance_record_type,
    task_id: TASK_ID,
    candidate_binding: candidate,
    candidate_manifest_artifact: candidateManifestRecord,
    repository: currentCandidate.observed.repository,
    executing_modules: currentCandidate.observed.executing_modules,
    verification: {
      repository_root_equals_executing_module_repository_root: true,
      head_tree_and_clean_state_recomputed_at_execution: true,
      executing_module_identities_recomputed_at_execution: true,
    },
  };
  const candidateProvenanceRecord = relativeFileRecord(root, "candidate-provenance.json", canonicalJsonBytes(candidateProvenance));
  artifactRecords.push({ role: "candidate_provenance", ...candidateProvenanceRecord });

  const testOutput = (label, ok, duration) => Buffer.from(`TAP version 13\n${ok ? "ok" : "not ok"} 1 - ${label}\n  location: '${materialization}/test/${label.includes("ordered") ? "regression" : "issue"}.test.mjs'\n  duration_ms: ${duration}\n`, "utf8");
  const commandDeclarations = [
    ["materialize_git_init", card.fixed_commands.git_init, 0, Buffer.alloc(0)],
    ["materialize_git_add", card.fixed_commands.git_add, 0, Buffer.alloc(0)],
    ["materialize_git_commit", card.fixed_commands.git_commit, 0, Buffer.alloc(0)],
    ["base_git_head", card.fixed_commands.git_head, 0, mock.head],
    ["base_git_tree", card.fixed_commands.git_tree, 0, mock.tree],
    ["base_git_status", card.fixed_commands.git_status, 0, Buffer.alloc(0)],
    ["base_issue_test", card.fixed_commands.issue_test, 1, testOutput("REP001_NEGATIVE_RANGE_ORDER", false, `${10 + repetitionId}.25`)],
    ["base_regression_test", card.fixed_commands.regression_test, 0, testOutput("ordered ranges remain unchanged", true, `${11 + repetitionId}.5`)],
    ["changed_path_git_status", card.fixed_commands.git_status, 0, mock.changedStatus],
    ["patch_git_diff", card.fixed_commands.git_diff, 0, mock.patch],
    ["patched_issue_test", card.fixed_commands.issue_test, 0, testOutput("REP001_NEGATIVE_RANGE_ORDER", true, `${12 + repetitionId}.75`)],
    ["patched_regression_test", card.fixed_commands.regression_test, 0, testOutput("ordered ranges remain unchanged", true, `${13 + repetitionId}.0`)],
    ["rollback_git_head", card.fixed_commands.git_head, 0, mock.head],
    ["rollback_git_tree", card.fixed_commands.git_tree, 0, mock.tree],
    ["rollback_git_status", card.fixed_commands.git_status, 0, Buffer.alloc(0)],
  ];
  const commands = [];
  for (const [actionId, argv, exitStatus, stdoutBytes] of commandDeclarations) {
    const stdout = relativeFileRecord(root, `streams/${actionId}.stdout`, stdoutBytes);
    const stderr = relativeFileRecord(root, `streams/${actionId}.stderr`, Buffer.alloc(0));
    artifactRecords.push({ role: "command_stream", action_id: actionId, stream: "stdout", ...stdout });
    artifactRecords.push({ role: "command_stream", action_id: actionId, stream: "stderr", ...stderr });
    commands.push({
      action_id: actionId,
      argv: [...argv],
      argv_equivalent: [...argv],
      cwd: materialization,
      cwd_equivalent: "TASK_REPOSITORY",
      exit_status: exitStatus,
      signal: null,
      timeout_ms: card.command_profile.timeout_ms,
      duration_ms: 100 + repetitionId,
      stdout,
      stderr,
    });
  }
  const rollbackSourceRecord = relativeFileRecord(root, "rollback-source.bin", assets.accepted.source_preimage.bytes);
  artifactRecords.push({ role: "rollback_source", ...rollbackSourceRecord });
  const patchRecord = relativeFileRecord(root, "patch.diff", mock.patch);
  artifactRecords.push({ role: "patch", ...patchRecord });
  const rollback = options.rollbackOmitted ? null : {
    mutation_occurred: true,
    source_artifact_path: rollbackSourceRecord.path,
    restored_source_byte_length: EXPECTED_BASE.source_byte_length,
    restored_source_sha256: EXPECTED_BASE.source_sha256,
    base_commit: EXPECTED_BASE.commit,
    base_tree: EXPECTED_BASE.tree,
    git_status_porcelain: "",
    restored_exact_base: true,
  };
  const observation = {
    schema_version: 1,
    record_type: card.run_evidence_contract.observation_record_type,
    task_id: TASK_ID,
    control_id: CONTROL_ID,
    run_id: options.observationRunId ?? runId,
    repetition_id: repetitionId,
    candidate_binding: candidate,
    physical_receipt: physical,
    actual_executor: mockActualExecutor(card),
    bindings: expectedBindings(card),
    ordered_action_ids: [...card.required_actions_in_order],
    admission: {
      status: "ADMITTED_EXACT_IR10",
      result_count: 1,
      program_id: "IR10",
      outcome_id: "CORRECT_END_START",
      postimage_byte_length: EXPECTED_POSTIMAGE.byte_length,
      postimage_sha256: EXPECTED_POSTIMAGE.sha256,
    },
    commands,
    base_tests: { issue: { action_id: "base_issue_test", exit_status: 1 }, regression: { action_id: "base_regression_test", exit_status: 0 } },
    patched_tests: { issue: { action_id: "patched_issue_test", exit_status: 0 }, regression: { action_id: "patched_regression_test", exit_status: 0 } },
    changed_paths: ["src/range.mjs"],
    rollback,
    external_effects: FALSE_EFFECTS,
    agent_status: "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED",
    claim_boundary: CLAIM_BOUNDARY,
  };
  const observationRecord = relativeFileRecord(root, "observation.json", canonicalJsonBytes(observation));
  artifactRecords.push({ role: "observation", ...observationRecord });
  const patchEvidencePackage = {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_066_patch_evidence_package",
    task_id: TASK_ID,
    run_id: runId,
    manifest: { schema_version: 1, task_id: TASK_ID, run_id: runId, artifact_checksums_bound_by_run_manifest: true },
    source_identity: {
      candidate_binding: candidate,
      candidate_repository: { head: candidate.candidate_commit, tree: candidate.candidate_tree, workspace_status: "clean" },
      materialized_base: { commit: EXPECTED_BASE.commit, tree: EXPECTED_BASE.tree, workspace_status_before: "clean", workspace_status_after_rollback: "clean" },
    },
    environment: {
      target_runtime: card.quality_assets.target_runtime,
      environment_snapshot: card.quality_assets.environment_snapshot,
      system_configuration: card.quality_assets.system_configuration,
      actual_executor: mockActualExecutor(card),
    },
    understanding: {
      issue_id: "REP001_NEGATIVE_RANGE_ORDER",
      interpretation: "normalize a reversed finite range without changing already ordered ranges",
      repository_evidence_references: [card.accepted_inputs.task_spec.path, card.accepted_inputs.expected_base_failure.path, card.accepted_inputs.source_preimage.path],
    },
    plan: { bounded_intended_changes: ["src/range.mjs"], mutation_kind: "ATOMIC_COMPLETE_POSTIMAGE_REPLACEMENT", risks: ["incorrect postimage", "scope drift", "test regression", "incomplete rollback"] },
    actions: { ordered_action_ids: [...card.required_actions_in_order], command_action_ids: commandDeclarations.map(([actionId]) => actionId), observation_artifact: observationRecord },
    patch: { changed_paths: ["src/range.mjs"], diff: patchRecord, postimage: EXPECTED_POSTIMAGE },
    tests: {
      base_issue: { action_id: "base_issue_test", exit_status: 1 },
      base_regression: { action_id: "base_regression_test", exit_status: 0 },
      patched_issue: { action_id: "patched_issue_test", exit_status: 0 },
      patched_regression: { action_id: "patched_regression_test", exit_status: 0 },
    },
    verification: { required: true, evaluator: { path: card.quality_evaluator_interface.module_path, version: QUALITY_ORACLE_VERSION }, status: "PENDING_INDEPENDENT_EVALUATION", runner_reported_pass_authoritative: false },
    risk: { changed_path_scope: ["src/range.mjs"], external_effects: FALSE_EFFECTS, declared_target_materialized: false, container_execution_observed: false, residual_claim_boundary: CLAIM_BOUNDARY },
    approval: { required_roles: ["CTO", "Security", "Quality"], actual_state: "PENDING_TASK_GATE", runner_self_approval: false },
    rollback: { source_artifact_path: rollbackSourceRecord.path, restored_source_byte_length: EXPECTED_BASE.source_byte_length, restored_source_sha256: EXPECTED_BASE.source_sha256, restored_base_commit: EXPECTED_BASE.commit, restored_base_tree: EXPECTED_BASE.tree, restored_workspace_status: "clean", disposable_workspace_receipt: materializationReceipt },
  };
  const patchPackageRecord = relativeFileRecord(root, "patch-evidence-package.json", canonicalJsonBytes(patchEvidencePackage));
  artifactRecords.push({ role: "patch_evidence_package", ...patchPackageRecord });
  const checksums = Object.fromEntries(artifactRecords.map((record) => [record.path, record.sha256]).sort(([left], [right]) => left.localeCompare(right)));
  const testIds = new Set(["base_issue_test", "base_regression_test", "patched_issue_test", "patched_regression_test"]);
  const runRecord = {
    schema_version: "1.0", run_id: runId, task_id: CONTROL_ID, dataset_version: "1.0.0", adapter_id: "B0",
    adapter_version: assets.system.adapter_version, environment_snapshot_id: assets.environment.snapshot_id,
    system_configuration_id: assets.system.configuration_id, repetition_id: repetitionId,
    started_at: `2026-07-21T12:4${repetitionId}:00Z`, ended_at: `2026-07-21T12:4${repetitionId}:01Z`,
    terminal_status: "completed", stop_reason_code: "agent_complete", invalid_run_reason: null, error_taxonomy: [],
    trace_ref: observationRecord.path, patch_ref: patchRecord.path,
    test_artifact_refs: artifactRecords.filter((record) => record.role === "command_stream" && record.stream === "stdout" && testIds.has(record.action_id)).map((record) => record.path),
    verification_ref: null,
    usage: { input_tokens: 0, output_tokens: 0, tool_calls: 0, retries: 0, human_interventions: 0, cost_usd: 0, latency_ms: 1000 + repetitionId },
    policy_violations: [], artifact_checksums: checksums,
  };
  const runRecordRecord = relativeFileRecord(root, "run-record.json", canonicalJsonBytes(runRecord));
  artifactRecords.push({ role: "run_record", ...runRecordRecord });
  const manifest = {
    schema_version: 1, record_type: card.run_evidence_contract.manifest_record_type, task_id: TASK_ID, control_id: CONTROL_ID,
    run_id: runId, repetition_id: repetitionId, candidate_binding: candidate, run_root_receipt: runReceipt,
    artifacts: artifactRecords, agent_status: "AGENT_COMPLETE_NOT_INDEPENDENTLY_VERIFIED",
  };
  const manifestPath = join(root, "manifest.json");
  createExclusiveFile(manifestPath, canonicalJsonBytes(manifest));
  return { root, manifestPath, observationPath: join(root, observationRecord.path) };
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function expectReason(expectedCode, action) {
  try {
    action();
  } catch (error) {
    assert(error instanceof QualityOracleError, "SELF_TEST_FAILED", `expected controlled ${expectedCode}, got ${error.name}`);
    assert(error.code === expectedCode, "SELF_TEST_FAILED", `expected ${expectedCode}, got ${error.code}: ${error.message}`);
    return expectedCode;
  }
  fail("SELF_TEST_FAILED", `expected ${expectedCode}, action passed`);
}

function rewriteMockJsonArtifact(runRoot, role, mutate) {
  const manifestPath = join(runRoot, "manifest.json");
  const manifest = parseJsonBytes(readFileSync(manifestPath), "SELF_TEST_FAILED", "mock manifest");
  const record = manifest.artifacts.find((entry) => entry.role === role);
  assert(record, "SELF_TEST_FAILED", `mock ${role} artifact missing`);
  const artifactPath = join(runRoot, record.path);
  const value = parseJsonBytes(readFileSync(artifactPath), "SELF_TEST_FAILED", `mock ${role}`);
  mutate(value);
  const bytes = canonicalJsonBytes(value);
  writeFileSync(artifactPath, bytes);
  Object.assign(record, identityOf(bytes));
  if (role !== "run_record") {
    const runRecordRecord = manifest.artifacts.find((entry) => entry.role === "run_record");
    const runRecordPath = join(runRoot, runRecordRecord.path);
    const runRecord = parseJsonBytes(readFileSync(runRecordPath), "SELF_TEST_FAILED", "mock RunRecord");
    runRecord.artifact_checksums[record.path] = record.sha256;
    const runRecordBytes = canonicalJsonBytes(runRecord);
    writeFileSync(runRecordPath, runRecordBytes);
    Object.assign(runRecordRecord, identityOf(runRecordBytes));
  }
  writeFileSync(manifestPath, canonicalJsonBytes(manifest));
}

function removeMockArtifactRecord(runRoot, role) {
  const manifestPath = join(runRoot, "manifest.json");
  const manifest = parseJsonBytes(readFileSync(manifestPath), "SELF_TEST_FAILED", "mock manifest");
  manifest.artifacts = manifest.artifacts.filter((entry) => entry.role !== role);
  writeFileSync(manifestPath, canonicalJsonBytes(manifest));
}

async function runSelfTest() {
  const assets = validateQualityAssets();
  const temporary = mkdtempSync(join(realpathSync(tmpdir()), "sourcelens-p1-066-quality-"));
  const negativeResults = [];
  const evidenceNegativeResults = [];
  try {
    const runA = buildMockRun(temporary, "self-run-a", 1, assets);
    const runB = buildMockRun(temporary, "self-run-b", 2, assets);
    const evaluatedA = evaluateRunEvidence(runA.manifestPath, assets);
    const evaluatedB = evaluateRunEvidence(runB.manifestPath, assets);
    const comparison = compareStableRuns(evaluatedA, evaluatedB);

    const positive = assets.quality.positive_result.value;
    const cases = new Map();
    cases.set("environment-identity-mismatch", () => {
      const value = cloneJson(positive);
      value.environment_binding.sha256 = "0".repeat(64);
      validatePositiveResult(value, assets.card);
    });
    cases.set("system-configuration-mismatch", () => {
      const value = cloneJson(positive);
      value.system_configuration_binding.configuration_id = "MISMATCH";
      validatePositiveResult(value, assets.card);
    });
    cases.set("duplicate-result", () => {
      const value = cloneJson(positive);
      value.results.push(cloneJson(value.results[0]));
      validatePositiveResult(value, assets.card);
    });
    cases.set("missing-result", () => {
      const value = cloneJson(positive);
      value.results = [];
      validatePositiveResult(value, assets.card);
    });
    cases.set("unknown-member", () => {
      const value = cloneJson(positive);
      value.results[0].response.unexpected = true;
      validatePositiveResult(value, assets.card);
    });
    cases.set("malformed-schema", () => {
      const value = cloneJson(positive);
      value.results = "not-an-array";
      validatePositiveResult(value, assets.card);
    });
    cases.set("input-identity-drift", () => {
      const value = cloneJson(positive);
      value.results[0].finite_typed_result.byte_length = 254;
      validatePositiveResult(value, assets.card);
    });
    cases.set("input-path-escape", () => {
      containedLeaf(temporary, "../escape", "INPUT_PATH_ESCAPE_REJECTED");
    });
    cases.set("input-directory-as-file", () => {
      const path = join(temporary, "input-directory");
      mkdirSync(path, { mode: 0o700 });
      safeReadRegular(path, undefined, "INPUT_TYPE_REJECTED", "input directory");
    });
    cases.set("input-symlink", () => {
      const target = join(temporary, "input-target");
      createExclusiveFile(target, Buffer.from("target\n"));
      const link = join(temporary, "input-link");
      symlinkSync(target, link);
      safeReadRegular(link, undefined, "INPUT_SYMLINK_REJECTED", "input symlink");
    });
    cases.set("unsupported-ir", () => {
      const value = cloneJson(positive);
      value.results[0].finite_typed_result.bytes_base64 = "e30=";
      value.results[0].finite_typed_result.byte_length = 2;
      value.results[0].finite_typed_result.sha256 = "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a";
      validatePositiveResult(value, assets.card);
    });
    cases.set("cross-run-substitution", () => {
      const run = buildMockRun(temporary, "self-run-cross", 3, assets, { observationRunId: "self-run-a" });
      evaluateRunEvidence(run.manifestPath, assets);
    });
    cases.set("evidence-tamper", () => {
      const run = buildMockRun(temporary, "self-run-tamper", 4, assets);
      appendFileSync(run.observationPath, Buffer.from("x"));
      evaluateRunEvidence(run.manifestPath, assets);
    });
    cases.set("rollback-omission", () => {
      const run = buildMockRun(temporary, "self-run-no-rollback", 5, assets, { rollbackOmitted: true });
      evaluateRunEvidence(run.manifestPath, assets);
    });
    cases.set("forbidden-external-effect-request", () => {
      const value = cloneJson(positive);
      value.results[0].requested_external_effects.network = true;
      validatePositiveResult(value, assets.card);
    });

    for (const declaration of assets.negative.cases) {
      const action = cases.get(declaration.id);
      assert(typeof action === "function", "SELF_TEST_FAILED", `missing negative implementation ${declaration.id}`);
      const reasonCode = expectReason(declaration.expected_reason_code, action);
      negativeResults.push({ id: declaration.id, reason_code: reasonCode, admitted: false });
    }
    assert(negativeResults.length === 15, "SELF_TEST_FAILED", "negative result population drift");

    let evidenceCaseIndex = 0;
    for (const [actionId] of requiredCommandSpecifications(assets.card)) {
      evidenceCaseIndex += 1;
      const run = buildMockRun(temporary, `self-missing-command-${evidenceCaseIndex}`, 20 + evidenceCaseIndex, assets);
      rewriteMockJsonArtifact(run.root, "observation", (value) => {
        value.commands = value.commands.filter((entry) => entry.action_id !== actionId);
      });
      const reasonCode = expectReason("COMMAND_RECORD_REJECTED", () => evaluateRunEvidence(run.manifestPath, assets));
      evidenceNegativeResults.push({ id: `missing-command-${actionId}`, reason_code: reasonCode, admitted: false });
    }
    {
      const run = buildMockRun(temporary, "self-missing-candidate-provenance", 50, assets);
      removeMockArtifactRecord(run.root, "candidate_provenance");
      const reasonCode = expectReason("EVIDENCE_MANIFEST_REJECTED", () => evaluateRunEvidence(run.manifestPath, assets));
      evidenceNegativeResults.push({ id: "missing-candidate-provenance", reason_code: reasonCode, admitted: false });
    }
    {
      const run = buildMockRun(temporary, "self-candidate-provenance-drift", 51, assets);
      rewriteMockJsonArtifact(run.root, "candidate_provenance", (value) => {
        value.repository.head = "0".repeat(40);
      });
      const reasonCode = expectReason("CANDIDATE_BINDING_REJECTED", () => evaluateRunEvidence(run.manifestPath, assets));
      evidenceNegativeResults.push({ id: "candidate-provenance-drift", reason_code: reasonCode, admitted: false });
    }
    {
      const run = buildMockRun(temporary, "self-missing-patch-package", 52, assets);
      removeMockArtifactRecord(run.root, "patch_evidence_package");
      const reasonCode = expectReason("EVIDENCE_MANIFEST_REJECTED", () => evaluateRunEvidence(run.manifestPath, assets));
      evidenceNegativeResults.push({ id: "missing-patch-evidence-package", reason_code: reasonCode, admitted: false });
    }
    for (const section of ["manifest", "source_identity", "environment", "understanding", "plan", "actions", "patch", "tests", "verification", "risk", "approval", "rollback"]) {
      evidenceCaseIndex += 1;
      const run = buildMockRun(temporary, `self-missing-package-${section.replaceAll("_", "-")}`, 60 + evidenceCaseIndex, assets);
      rewriteMockJsonArtifact(run.root, "patch_evidence_package", (value) => {
        delete value[section];
      });
      const reasonCode = expectReason("PATCH_EVIDENCE_PACKAGE_REJECTED", () => evaluateRunEvidence(run.manifestPath, assets));
      evidenceNegativeResults.push({ id: `missing-package-section-${section}`, reason_code: reasonCode, admitted: false });
    }
    assert(evidenceNegativeResults.length === 30, "SELF_TEST_FAILED", "Evidence negative result population drift");
    const result = {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_066_quality_self_test",
      task_id: TASK_ID,
      quality_oracle_version: QUALITY_ORACLE_VERSION,
      quality_asset_validation: "PASS",
      positive_run_evaluation: "PASS",
      independent_run_b_evaluation: "PASS",
      stable_projection_exact_byte_equal: comparison.stable_projection_exact_byte_equal,
      negative_case_count: negativeResults.length,
      negative_case_outcomes: negativeResults,
      evidence_negative_case_count: evidenceNegativeResults.length,
      evidence_negative_case_outcomes: evidenceNegativeResults,
      total_negative_case_count: negativeResults.length + evidenceNegativeResults.length,
      false_accepts: 0,
      proposal_passed_unmodified_to_accepted_compiler: true,
      declared_target_materialized: false,
      actual_executor_evidence_separate: true,
      external_effects: FALSE_EFFECTS,
      target_verdict: "PASS",
      claim_boundary: CLAIM_BOUNDARY,
    };
    return result;
  } finally {
    const resolvedTemporary = resolve(temporary);
    assert(resolvedTemporary.startsWith(`${realpathSync(tmpdir())}/sourcelens-p1-066-quality-`), "SELF_TEST_SETUP_FAILED", "temporary cleanup target invalid");
    rmSync(resolvedTemporary, { recursive: true, force: false });
  }
}

function parseCli(argv) {
  const mode = argv[0];
  assert(["self-test", "evaluate-run", "compare-runs"].includes(mode), "CLI_REJECTED", "unknown CLI mode");
  const values = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    assert(flag?.startsWith("--") && value !== undefined && !values.has(flag), "CLI_REJECTED", "invalid CLI flags");
    values.set(flag, value);
  }
  const allowed = mode === "self-test"
    ? new Set(["--output"])
    : mode === "evaluate-run"
      ? new Set(["--run-manifest", "--output"])
      : new Set(["--run-a-manifest", "--run-b-manifest", "--output"]);
  assert([...values.keys()].every((key) => allowed.has(key)), "CLI_REJECTED", "unknown CLI flag");
  if (mode === "self-test") assert(values.size === 0 || (values.size === 1 && values.has("--output")), "CLI_REJECTED", "self-test flag set mismatch");
  if (mode === "evaluate-run") assert(values.has("--run-manifest") && (values.size === 1 || values.size === 2), "CLI_REJECTED", "evaluate-run flag set mismatch");
  if (mode === "compare-runs") assert(values.has("--run-a-manifest") && values.has("--run-b-manifest") && (values.size === 2 || values.size === 3), "CLI_REJECTED", "compare-runs flag set mismatch");
  return { mode, values };
}

function emitCliResult(value, outputPath) {
  const bytes = canonicalJsonBytes(value);
  if (outputPath !== undefined) {
    assert(isAbsolute(outputPath), "CLI_REJECTED", "output path must be absolute");
    const resolvedOutput = resolve(outputPath);
    const resolvedRoot = realpathSync(AUTHORIZED_EVIDENCE_ROOT);
    const rel = relative(resolvedRoot, resolvedOutput);
    assert(rel !== "" && rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel), "CLI_REJECTED", "output escaped authorized Evidence root");
    createExclusiveFile(outputPath, bytes);
  }
  process.stdout.write(bytes);
}

async function main() {
  const { mode, values } = parseCli(process.argv.slice(2));
  if (mode === "self-test") {
    emitCliResult(await runSelfTest(), values.get("--output"));
    return;
  }
  if (mode === "evaluate-run") {
    const evaluated = evaluateRunEvidence(values.get("--run-manifest"));
    emitCliResult(evaluated, values.get("--output"));
    return;
  }
  const compared = compareStableRuns(values.get("--run-a-manifest"), values.get("--run-b-manifest"));
  emitCliResult(compared, values.get("--output"));
}

if (resolve(process.argv[1] ?? "") === resolve(fileURLToPath(import.meta.url))) {
  try {
    await main();
  } catch (error) {
    const code = error instanceof QualityOracleError ? error.code : "UNEXPECTED_ERROR";
    process.stderr.write(`P1_066_QUALITY_ORACLE: NON_PASS ${code} ${error.message}\n`);
    process.exitCode = 2;
  }
}

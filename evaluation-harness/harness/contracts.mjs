import { createHash } from "node:crypto";
import {
  existsSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalJson, validate } from "../evaluator/schema-validator.mjs";
import { sha256 } from "../recording/recorder.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPOSITORY_ROOT = resolve(HERE, "../..");
export const RECORDING_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/recording");
export const FIXTURE_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/fixtures");
export const SCHEMA_ROOT = join(REPOSITORY_ROOT, "docs/aios/schemas");
export const EVALUATOR = join(REPOSITORY_ROOT, "evaluation-harness/evaluator/evaluate.mjs");
export const ADAPTER = join(REPOSITORY_ROOT, "evaluation-harness/adapters/harness_stub/adapter.mjs");
export const FREEZE_RECEIPT = join(FIXTURE_ROOT, "oracle/FREEZE_RECEIPT.json");
export const EXPECTED_FREEZE_RECEIPT_SHA256 = "ef7f9807795a685d0aa92fc19248ed0101362861ad7d71e4fdcdbb9df0b840c6";
export const EXPECTED_TASK_CONTRACT_SHA256 = "d2974752b088ff30b0764d6b482e19ea939cd497eb2db3e26af28bf09dc2e12f";

export const INPUT_PATHS = Object.freeze({
  task: join(FIXTURE_ROOT, "visible/task-spec.json"),
  environment: join(FIXTURE_ROOT, "visible/environment-snapshot.json"),
  configuration: join(FIXTURE_ROOT, "visible/system-configuration.json"),
  context: join(FIXTURE_ROOT, "visible/context.json"),
  responseFormat: join(FIXTURE_ROOT, "visible/response-format.json"),
  controlledFailure: join(FIXTURE_ROOT, "visible/controlled-failure.json"),
  controlledFailureResult: join(FIXTURE_ROOT, "visible/controlled-failure-result.json"),
  expectedResult: join(FIXTURE_ROOT, "oracle/expected-result.json"),
  oracle: join(FIXTURE_ROOT, "oracle/oracle.json"),
});

const SCHEMAS = Object.freeze({
  task: "task-spec.schema.json",
  environment: "environment-snapshot.schema.json",
  configuration: "system-configuration.schema.json",
  runRecord: "run-record.schema.json",
});

export function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

export function writeJsonCreateOnce(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${canonicalJson(value)}\n`, { encoding: "utf8", flag: "wx" });
}

export function writeBytesCreateOnce(path, bytes) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes, { flag: "wx" });
}

export function assertFileIdentity(path, expectedSha256, expectedByteLength, label = path) {
  if (!existsSync(path) || !statSync(path).isFile()) throw new Error(`${label}: missing file`);
  const bytes = readFileSync(path);
  if (bytes.length !== expectedByteLength || sha256(bytes) !== expectedSha256) {
    throw new Error(`${label}: identity mismatch`);
  }
  return true;
}

function manifestRoot(artifacts) {
  const entries = [...artifacts].sort((left, right) => Buffer.compare(Buffer.from(left.path), Buffer.from(right.path)));
  const bytes = entries.map((entry) => `${entry.path}\0${entry.sha256}\0${entry.byte_length}\n`).join("");
  return sha256(Buffer.from(bytes, "utf8"));
}

export function verifyFrozenInputs(repositoryRoot = REPOSITORY_ROOT) {
  const root = realpathSync(repositoryRoot);
  assertFileIdentity(
    FREEZE_RECEIPT,
    EXPECTED_FREEZE_RECEIPT_SHA256,
    statSync(FREEZE_RECEIPT).size,
    "Quality Freeze Receipt bytes drifted",
  );
  const receipt = readJson(FREEZE_RECEIPT);
  if (receipt.task_contract.sha256 !== EXPECTED_TASK_CONTRACT_SHA256) {
    throw new Error("Quality Freeze Receipt Task Contract binding drifted");
  }
  const failures = [];
  for (const entry of [...receipt.quality_manifest.artifacts, ...receipt.external_bindings]) {
    const path = resolve(root, entry.path);
    const rel = relative(root, path);
    if (rel === ".." || rel.startsWith(`..${sep}`) || !existsSync(path) || !statSync(path).isFile()) {
      failures.push(`${entry.path}: missing or escaped`);
      continue;
    }
    try { assertFileIdentity(path, entry.sha256, entry.byte_length, entry.path); }
    catch { failures.push(`${entry.path}: identity mismatch`); }
  }
  if (receipt.quality_manifest.root_sha256 !== manifestRoot(receipt.quality_manifest.artifacts)) {
    failures.push("quality manifest root mismatch");
  }
  const runtimeBytes = readFileSync(realpathSync(process.execPath));
  if (process.version !== receipt.runtime_observation.version
      || runtimeBytes.length !== receipt.runtime_observation.executable_byte_length
      || sha256(runtimeBytes) !== receipt.runtime_observation.executable_sha256) {
    failures.push("Quality-frozen Node.js runtime identity mismatch");
  }
  if (failures.length > 0) throw new Error(`frozen input verification failed: ${failures.join("; ")}`);
  return receipt;
}

function validateOne(kind, instance) {
  const schema = readJson(join(SCHEMA_ROOT, SCHEMAS[kind]));
  const errors = validate(instance, schema);
  if (errors.length > 0) throw new Error(`${kind} schema failed: ${errors.join("; ")}`);
}

function assertReference(reference, expectedSha) {
  const root = realpathSync(REPOSITORY_ROOT);
  const path = realpathSync(resolve(root, reference));
  const rel = relative(root, path);
  if (rel === ".." || rel.startsWith(`..${sep}`) || rel === "") {
    throw new Error(`artifact reference escaped repository: ${reference}`);
  }
  if (!statSync(path).isFile() || sha256(readFileSync(path)) !== expectedSha) {
    throw new Error(`artifact reference hash mismatch: ${reference}`);
  }
}

export function loadAndPreflight() {
  const receipt = verifyFrozenInputs();
  const task = readJson(INPUT_PATHS.task);
  const environment = readJson(INPUT_PATHS.environment);
  const configuration = readJson(INPUT_PATHS.configuration);
  validateOne("task", task);
  validateOne("environment", environment);
  validateOne("configuration", configuration);

  const assertions = [
    [task.environment_snapshot_ref === environment.snapshot_id, "environment identity mismatch"],
    [task.repository.identity === environment.source.repository_identity, "repository identity mismatch"],
    [task.repository.base_commit === environment.source.base_commit, "source commit mismatch"],
    [task.repository.tree_hash === environment.source.tree_hash, "source tree mismatch"],
    [environment.source.worktree_clean === true, "synthetic source is not immutable"],
    [task.network_policy === "none" && task.allowed_network_hosts.length === 0, "TaskSpec network policy is not none"],
    [environment.network.policy === "none" && environment.network.allowed_hosts.length === 0, "environment network policy is not none"],
    [environment.model.provider === "none" && environment.model.model_ref === "synthetic://no-model", "provider/model boundary mismatch"],
    [environment.environment_variables.secret_names_present.length === 0, "Secret names are present"],
    [environment.secret_policy.values_retained === false, "Secret retention is enabled"],
    [configuration.model_ref === environment.model.model_ref, "model binding mismatch"],
    [configuration.prompt_ref === environment.prompt_version, "prompt binding mismatch"],
    [configuration.policy_ref === environment.policy_version, "policy binding mismatch"],
    [configuration.response_format_ref === task.baseline_context.response_format_ref, "response format binding mismatch"],
    [configuration.adapter_id === "A0" && configuration.adapter_version === "HARNESS_STUB-1.0", "schema compatibility notation mismatch"],
    [configuration.feature_flags.harness_stub_only === true, "HARNESS_STUB flag missing"],
    [configuration.feature_flags.benchmark_claim === false, "benchmark claim must be false"],
    [configuration.feature_flags.agent_capability_claim === false, "Agent capability claim must be false"],
    [configuration.feature_flags.included_in_vtsr_denominator === false, "VTSR inclusion must be false"],
    [task.budgets.max_model_tokens === 0 && task.budgets.max_cost_usd === 0, "model/cost budget is nonzero"],
  ];
  const failed = assertions.filter(([passed]) => !passed).map(([, message]) => message);
  if (failed.length > 0) throw new Error(`cross-contract preflight failed: ${failed.join("; ")}`);

  assertReference(task.baseline_context.artifact_ref, task.baseline_context.sha256);
  assertReference(task.baseline_context.response_format_ref, task.baseline_context.response_format_sha256);
  const oracle = readJson(INPUT_PATHS.oracle);
  assertReference(oracle.expected_result_ref, oracle.expected_result_sha256);

  const hashes = Object.fromEntries(Object.entries(INPUT_PATHS).map(([key, path]) => [key, sha256(readFileSync(path))]));
  return { task, environment, configuration, oracle, receipt, input_hashes: hashes };
}

export function validateRunRecord(runRecord) {
  validateOne("runRecord", runRecord);
}

export function prepareEvidenceRoot(outputPath) {
  mkdirSync(RECORDING_ROOT, { recursive: true });
  const recordingRoot = realpathSync(RECORDING_ROOT);
  const candidate = resolve(outputPath);
  const rel = relative(recordingRoot, candidate);
  if (rel === "" || rel === ".." || rel.startsWith(`..${sep}`)) {
    throw new Error("output must be a new child of evaluation-harness/recording");
  }
  if (existsSync(candidate)) throw new Error("output path already exists; evidence is create-once");
  if (realpathSync(dirname(candidate)) !== recordingRoot && !realpathSync(dirname(candidate)).startsWith(`${recordingRoot}${sep}`)) {
    throw new Error("output parent escaped recording root");
  }
  mkdirSync(candidate, { recursive: false, mode: 0o700 });
  return realpathSync(candidate);
}

export function runtimeObservation() {
  const executable = realpathSync(process.execPath);
  const bytes = readFileSync(executable);
  return {
    name: "Node.js",
    version: process.version,
    executable,
    executable_sha256: createHash("sha256").update(bytes).digest("hex"),
    executable_byte_length: bytes.length,
    dependencies: "standard_library_only",
  };
}

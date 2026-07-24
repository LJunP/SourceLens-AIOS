import {
  closeSync,
  constants as fsConstants,
  lstatSync,
  openSync,
  readFileSync,
  realpathSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(MODULE_DIR, "../../..");
const DEFAULT_FIXTURE_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-101-accepted-shared-trace",
);
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const REQUIRED_EVENT_ORDER = Object.freeze([
  "admission",
  "execution",
  "validation",
  "result",
  "rollback",
]);
const REQUIRED_POSITIVES = Object.freeze([
  "B0_A",
  "B0_B",
  "B1_A",
  "B1_B",
  "B2_A",
  "B2_B",
]);
const REQUIRED_NEGATIVES = Object.freeze([
  ["NEG_TASK_SPEC_IDENTITY_DRIFT", "PRE_EXECUTION", "TASK_SPEC_IDENTITY_DRIFT", "TASK_SPEC_IDENTITY_MISMATCH"],
  ["NEG_ENVIRONMENT_IDENTITY_DRIFT", "PRE_EXECUTION", "ENVIRONMENT_IDENTITY_DRIFT", "ENVIRONMENT_IDENTITY_MISMATCH"],
  ["NEG_SYSTEM_CONFIGURATION_IDENTITY_DRIFT", "PRE_EXECUTION", "SYSTEM_CONFIGURATION_IDENTITY_DRIFT", "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH"],
  ["NEG_EXECUTABLE_IDENTITY_DRIFT", "PRE_EXECUTION", "EXECUTABLE_IDENTITY_DRIFT", "EXECUTABLE_IDENTITY_MISMATCH"],
  ["NEG_INPUT_IDENTITY_DRIFT", "PRE_EXECUTION", "INPUT_IDENTITY_DRIFT", "INPUT_IDENTITY_MISMATCH"],
  ["NEG_EFFECT_NETWORK", "PRE_EXECUTION", "REQUEST_EFFECT_NETWORK", "EXTERNAL_EFFECT_FORBIDDEN"],
  ["NEG_EFFECT_PROVIDER", "PRE_EXECUTION", "REQUEST_EFFECT_PROVIDER", "EXTERNAL_EFFECT_FORBIDDEN"],
  ["NEG_EFFECT_SECRET", "PRE_EXECUTION", "REQUEST_EFFECT_SECRET", "EXTERNAL_EFFECT_FORBIDDEN"],
  ["NEG_EFFECT_REMOTE", "PRE_EXECUTION", "REQUEST_EFFECT_REMOTE", "EXTERNAL_EFFECT_FORBIDDEN"],
  ["NEG_EFFECT_PRODUCTION", "PRE_EXECUTION", "REQUEST_EFFECT_PRODUCTION", "EXTERNAL_EFFECT_FORBIDDEN"],
  ["NEG_EFFECT_PUBLIC", "PRE_EXECUTION", "REQUEST_EFFECT_PUBLIC", "EXTERNAL_EFFECT_FORBIDDEN"],
  ["NEG_TAMPERED_EVENT_BYTES", "POST_EXECUTION", "TAMPER_EVENT_BYTES", "TRACE_EVENT_IDENTITY_MISMATCH"],
  ["NEG_MISSING_REQUIRED_EVENT", "POST_EXECUTION", "REMOVE_REQUIRED_EVENT", "TRACE_EVENT_SEQUENCE_INVALID"],
  ["NEG_REORDERED_EVENT", "POST_EXECUTION", "REORDER_EVENTS", "TRACE_EVENT_SEQUENCE_INVALID"],
  ["NEG_OUTPUT_IDENTITY_DRIFT", "POST_EXECUTION", "OUTPUT_IDENTITY_DRIFT", "OUTPUT_IDENTITY_MISMATCH"],
  ["NEG_RUN_RECORD_IDENTITY_DRIFT", "POST_EXECUTION", "RUN_RECORD_IDENTITY_DRIFT", "RUN_RECORD_IDENTITY_MISMATCH"],
  ["NEG_CHILD_IDENTITY_DRIFT", "POST_EXECUTION", "CHILD_IDENTITY_DRIFT", "CHILD_INVOCATION_IDENTITY_MISMATCH"],
  ["NEG_UNEXPECTED_OUTPUT", "POST_EXECUTION", "ADD_UNEXPECTED_OUTPUT", "UNEXPECTED_OUTPUT"],
  ["NEG_UNDECLARED_CHILD", "POST_EXECUTION", "ADD_UNDECLARED_CHILD", "UNDECLARED_CHILD_INVOCATION"],
]);
const CONFIGURATIONS = Object.freeze({
  B0_A: "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b0-a.json",
  B0_B: "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b0-b.json",
  B1_A: "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b1-a.json",
  B1_B: "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b1-b.json",
  B2_A: "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b2-a.json",
  B2_B: "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b2-b.json",
});

export class QualityNonPass extends Error {
  constructor(reason, detail = "") {
    super(detail ? `${reason}: ${detail}` : reason);
    this.name = "QualityNonPass";
    this.reason = reason;
    this.detail = detail;
  }
}

function fail(reason, detail = "") {
  throw new QualityNonPass(reason, detail);
}

function assert(condition, reason, detail = "") {
  if (!condition) fail(reason, detail);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function exactKeys(value, keys, reason) {
  assert(value && typeof value === "object" && !Array.isArray(value), reason);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  assert(
    actual.length === expected.length && actual.every((key, index) => key === expected[index]),
    reason,
    `keys=${actual.join(",")}`,
  );
}

function contained(root, candidate, reason) {
  const rootAbsolute = resolve(root);
  const candidateAbsolute = resolve(candidate);
  const rel = relative(rootAbsolute, candidateAbsolute);
  assert(rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel)), reason);
  return candidateAbsolute;
}

function safeRead(root, relativePath, reason) {
  assert(
    typeof relativePath === "string" &&
      relativePath.length > 0 &&
      !isAbsolute(relativePath),
    reason,
  );
  const path = contained(root, join(root, relativePath), reason);
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink(), reason, relativePath);
  const fd = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  try {
    return readFileSync(fd);
  } finally {
    closeSync(fd);
  }
}

function readJson(root, relativePath, reason) {
  let value;
  const bytes = safeRead(root, relativePath, reason);
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(reason, `${relativePath}: ${error.message}`);
  }
  return { bytes, value };
}

function verifyInterface(fixtureRoot) {
  const { bytes, value } = readJson(fixtureRoot, "interface.json", "INTERFACE_INVALID");
  exactKeys(value, [
    "schema_version",
    "task_id",
    "worker_entry",
    "cli",
    "request_closed_keys",
    "request_schema",
    "bound_input_record_closed_keys",
    "mutation_closed_keys",
    "external_effect_closed_keys",
    "expected_outcome_closed_keys",
    "validation_input_closed_keys",
    "stdout_closed_keys",
    "cleanup_closed_keys",
    "positive_case_ids",
    "required_positive_event_order",
    "negative_case_catalog",
    "negative_execution_contract",
    "negative_validation_evidence",
    "pre_execution_validation_input_closed_keys",
    "post_execution_validation_input_closed_keys",
    "post_execution_mutation_targets",
    "claim_boundary",
  ], "INTERFACE_INVALID");
  assert(value.schema_version === "p1-101-quality-worker-interface/v1", "INTERFACE_INVALID");
  assert(value.task_id === "AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE", "INTERFACE_INVALID");
  assert(
    value.worker_entry === "evaluation-harness/harness/p1-101-accepted-shared-trace/run.mjs",
    "INTERFACE_INVALID",
  );
  exactKeys(value.post_execution_mutation_targets, [
    "TAMPER_EVENT_BYTES",
    "REMOVE_REQUIRED_EVENT",
    "REORDER_EVENTS",
    "OUTPUT_IDENTITY_DRIFT",
    "RUN_RECORD_IDENTITY_DRIFT",
    "CHILD_IDENTITY_DRIFT",
    "ADD_UNEXPECTED_OUTPUT",
    "ADD_UNDECLARED_CHILD",
  ], "INTERFACE_INVALID");
  assert(
    JSON.stringify(value.mutation_closed_keys) === JSON.stringify(["stage", "type"]) &&
      JSON.stringify(value.expected_outcome_closed_keys) ===
        JSON.stringify(["status", "pre_execution", "target_execution_count"]) &&
      JSON.stringify(value.validation_input_closed_keys) === JSON.stringify([
        "task_spec",
        "environment_snapshot",
        "system_configuration",
        "executable",
        "input",
      ]),
    "INTERFACE_INVALID",
  );
  exactKeys(value.negative_validation_evidence, [
    "scope",
    "source_path",
    "mutated_path",
    "receipt_path",
    "receipt_closed_keys",
    "worker_must_not_receive_expected_reason",
  ], "INTERFACE_INVALID");
  assert(
    value.negative_validation_evidence.scope === "ALL_NEGATIVES" &&
      value.negative_validation_evidence.source_path === "negative-source-input.bin" &&
      value.negative_validation_evidence.mutated_path === "negative-validation-input.bin" &&
      value.negative_validation_evidence.receipt_path === "negative-validation-receipt.json" &&
      value.negative_validation_evidence.worker_must_not_receive_expected_reason === true,
    "INTERFACE_INVALID",
  );
  assert(
    JSON.stringify(value.pre_execution_validation_input_closed_keys) === JSON.stringify([
      "schema_version",
      "validation_inputs",
      "requested_effects",
    ]) &&
      JSON.stringify(value.post_execution_validation_input_closed_keys) === JSON.stringify([
        "schema_version",
        "trace_events",
        "output_identity",
        "run_record_identity",
        "child_invocations",
        "output_inventory",
      ]),
    "INTERFACE_INVALID",
  );
  assert(
    JSON.stringify(value.positive_case_ids) === JSON.stringify(REQUIRED_POSITIVES),
    "INTERFACE_INVALID",
  );
  assert(
    JSON.stringify(value.required_positive_event_order) === JSON.stringify(REQUIRED_EVENT_ORDER),
    "INTERFACE_INVALID",
  );
  exactKeys(value.negative_execution_contract, ["PRE_EXECUTION", "POST_EXECUTION"], "INTERFACE_INVALID");
  assert(
    value.negative_execution_contract.PRE_EXECUTION.required_target_execution_count === 0 &&
      value.negative_execution_contract.PRE_EXECUTION.required_admitted === false,
    "INTERFACE_INVALID",
  );
  assert(
    value.negative_execution_contract.POST_EXECUTION.fresh_accepted_adapter_run_per_case === true &&
      value.negative_execution_contract.POST_EXECUTION.required_target_execution_count === 1 &&
      value.negative_execution_contract.POST_EXECUTION.required_admitted === false,
    "INTERFACE_INVALID",
  );
  return { bytes, value };
}

function verifyPositivePlan(fixtureRoot) {
  const { bytes, value } = readJson(fixtureRoot, "positive-plan.json", "POSITIVE_PLAN_INVALID");
  exactKeys(value, [
    "schema_version",
    "task_id",
    "accepted_fixture_root",
    "runs",
    "requirements",
    "claim_boundary",
  ], "POSITIVE_PLAN_INVALID");
  assert(value.schema_version === "p1-101-quality-positive-plan/v1", "POSITIVE_PLAN_INVALID");
  assert(value.task_id === "AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE", "POSITIVE_PLAN_INVALID");
  assert(Array.isArray(value.runs) && value.runs.length === 6, "POSITIVE_PLAN_INVALID");
  assert(
    JSON.stringify(value.runs.map((entry) => entry.case_id)) === JSON.stringify(REQUIRED_POSITIVES),
    "POSITIVE_PLAN_INVALID",
  );
  for (const run of value.runs) {
    exactKeys(run, ["case_id", "adapter_id", "repetition_id", "configuration", "pair"], "POSITIVE_PLAN_INVALID");
    assert(run.configuration === CONFIGURATIONS[run.case_id], "POSITIVE_PLAN_INVALID", run.case_id);
    assert(run.adapter_id === run.case_id.slice(0, 2) && run.pair === run.adapter_id, "POSITIVE_PLAN_INVALID");
    assert(run.repetition_id === (run.case_id.endsWith("_A") ? 1 : 2), "POSITIVE_PLAN_INVALID");
    const configurationPath = join(REPOSITORY_ROOT, run.configuration);
    const stat = lstatSync(configurationPath);
    assert(
      stat.isFile() &&
        !stat.isSymbolicLink() &&
        realpathSync(configurationPath) === configurationPath,
      "ACCEPTED_CONFIGURATION_INVALID",
      run.configuration,
    );
  }
  exactKeys(value.requirements.external_effects, Object.keys(FALSE_EFFECTS), "POSITIVE_PLAN_INVALID");
  assert(
    JSON.stringify(value.requirements.external_effects) === JSON.stringify(FALSE_EFFECTS) &&
      value.requirements.positive_runs === 6 &&
      value.requirements.distinct_run_roots === 6 &&
      value.requirements.exact_stable_pairs === 3 &&
      value.requirements.b2_real_repository_analysis_scan_children === 2 &&
      value.requirements.replay_receipts === 6 &&
      value.requirements.rollback_receipts === 6 &&
      value.requirements.raw_stochastic_pairs_different === 3 &&
      value.requirements.false_accepts === 0 &&
      value.requirements.nonowned_residuals === 0 &&
      value.requirements.undeclared_executions === 0,
    "POSITIVE_PLAN_INVALID",
  );
  assert(
    JSON.stringify(value.requirements.event_order) === JSON.stringify(REQUIRED_EVENT_ORDER),
    "POSITIVE_PLAN_INVALID",
  );
  return { bytes, value };
}

function verifyNegativeCatalog(fixtureRoot) {
  const { bytes, value } = readJson(fixtureRoot, "negative-cases.json", "NEGATIVE_CATALOG_INVALID");
  exactKeys(value, [
    "schema_version",
    "task_id",
    "false_accepts_allowed",
    "cases",
    "counts",
    "fresh_fixture_per_case",
    "claim_boundary",
  ], "NEGATIVE_CATALOG_INVALID");
  assert(value.schema_version === "p1-101-quality-negative-catalog/v1", "NEGATIVE_CATALOG_INVALID");
  assert(value.task_id === "AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE", "NEGATIVE_CATALOG_INVALID");
  assert(value.false_accepts_allowed === 0 && value.fresh_fixture_per_case === true, "NEGATIVE_CATALOG_INVALID");
  assert(Array.isArray(value.cases) && value.cases.length === REQUIRED_NEGATIVES.length, "NEGATIVE_CATALOG_INVALID");
  assert(new Set(value.cases.map((entry) => entry.case_id)).size === value.cases.length, "NEGATIVE_CATALOG_INVALID");
  for (let index = 0; index < REQUIRED_NEGATIVES.length; index += 1) {
    const entry = value.cases[index];
    const expected = REQUIRED_NEGATIVES[index];
    exactKeys(entry, ["case_id", "adapter_id", "stage", "mutation", "reason_code"], "NEGATIVE_CATALOG_INVALID");
    assert(
      entry.case_id === expected[0] &&
        entry.stage === expected[1] &&
        entry.mutation === expected[2] &&
        entry.reason_code === expected[3],
      "NEGATIVE_CATALOG_INVALID",
      entry.case_id,
    );
    assert(["B0", "B2"].includes(entry.adapter_id), "NEGATIVE_CATALOG_INVALID", entry.case_id);
  }
  exactKeys(value.counts, ["catalog_entries", "pre_execution", "post_execution", "external_effect_cases"], "NEGATIVE_CATALOG_INVALID");
  assert(
    value.counts.catalog_entries === 19 &&
      value.counts.pre_execution === 11 &&
      value.counts.post_execution === 8 &&
      value.counts.external_effect_cases === 6 &&
      value.cases.filter((entry) => entry.stage === "PRE_EXECUTION").length === 11 &&
      value.cases.filter((entry) => entry.stage === "POST_EXECUTION").length === 8,
    "NEGATIVE_CATALOG_INVALID",
  );
  return { bytes, value };
}

export function verifyQualityFixtures({ fixtureRoot = DEFAULT_FIXTURE_ROOT } = {}) {
  const root = resolve(fixtureRoot);
  const rootStat = lstatSync(root);
  assert(rootStat.isDirectory() && !rootStat.isSymbolicLink(), "FIXTURE_ROOT_INVALID");
  const interfaceResult = verifyInterface(root);
  const positiveResult = verifyPositivePlan(root);
  const negativeResult = verifyNegativeCatalog(root);
  const manifest = [
    ["interface.json", interfaceResult.bytes],
    ["negative-cases.json", negativeResult.bytes],
    ["positive-plan.json", positiveResult.bytes],
  ].map(([path, bytes]) => ({ path, sha256: sha256(bytes), byte_length: bytes.length }));
  const manifestBytes = Buffer.from(`${JSON.stringify(manifest)}\n`, "utf8");
  return {
    schema_version: "p1-101-quality-fixture-verdict/v1",
    status: "PASS",
    positive_cases: 6,
    negative_cases: 19,
    pre_execution_cases: 11,
    post_execution_cases: 8,
    fixture_manifest_sha256: sha256(manifestBytes),
    fixture_manifest: manifest,
    external_effects: { ...FALSE_EFFECTS },
  };
}

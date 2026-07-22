import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  COMPILER_VERSION,
  compileFiniteTypedPatchIr,
} from "../../harness/finite-typed-patch-ir-v1/compiler.mjs";

export const ADAPTER_VERSION = "OFFLINE-B1-FINITE-TOOL-ADAPTER/1";

const TASK_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const PLAN_ID = "P1-067-REP001-IR10-THREE-STEP-PLAN";
const CLAIM_BOUNDARY =
  "ONE_VISIBLE_SYNTHETIC_REP_001_COOPERATIVE_LOCAL_OFFLINE_B1_FINITE_TYPED_SIMPLE_TOOL_COMPATIBILITY_ADAPTER_COMPLETE_EVIDENCE_OBSERVATION_ONLY_NO_LIVE_MODEL_EMPIRICAL_BASELINE_VTSR_P1_EXIT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM";
const BASE_COMMIT = "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f";
const BASE_TREE = "900814727113d65f5dad8b63222e14f39b2cf38b";
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const REQUIRED_STEPS = Object.freeze([
  Object.freeze({
    ordinal: 1,
    tool_id: "local-file-edit",
    operation_id: "apply-finite-typed-patch-ir",
  }),
  Object.freeze({
    ordinal: 2,
    tool_id: "local-node-test",
    operation_id: "issue-test",
  }),
  Object.freeze({
    ordinal: 3,
    tool_id: "local-node-test",
    operation_id: "regression-test",
  }),
]);
const DYNAMIC_FIELDS = new Set([
  "path",
  "argv",
  "cwd",
  "env",
  "executable",
  "module",
  "timeout",
  "code",
  "shell",
  "diff",
  "ast",
  "payload",
  "parameters",
]);
const EXPECTED = Object.freeze({
  task_spec: Object.freeze({
    byte_length: 2960,
    sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
  }),
  system_configuration: Object.freeze({
    id: "P1-067-B1-OFFLINE-FINITE-TOOL-1",
    byte_length: 1108,
    sha256: "8e7333d5acd3f6ac84d595c91fef3a053f2722e46ac09f4beb54fafe7965e5e9",
  }),
  compatibility_profile: Object.freeze({
    id: "P1-067-B1-REP001-FINITE-TOOL-COMPATIBILITY/1",
    byte_length: 4454,
    sha256: "6a4f462eab6b46bfc0d675dd902f09b57cf5b8c541e9ef07caadc0675e8ae6b8",
  }),
  plan: Object.freeze({
    byte_length: 1583,
    sha256: "8752ffa0a5325c7dcd72697ceeaf878f2b6fbadb8fb44890d215e7b1d85f1b0f",
  }),
  ir10: Object.freeze({
    byte_length: 255,
    sha256: "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc",
  }),
  postimage: Object.freeze({
    byte_length: 127,
    sha256: "e8304b77da9b8c33f64ecdc568db7e97297ace72ecb796971bb3f5eda09d9001",
  }),
});

export class OfflineB1AdapterError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OfflineB1AdapterError";
    this.code = code;
  }
}

const fail = (code, message) => {
  throw new OfflineB1AdapterError(code, message);
};
const assert = (condition, code, message) => {
  if (!condition) fail(code, message);
};
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const canonicalize = (value) => {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
};
const canonicalJsonBytes = (value) =>
  Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
const sameJson = (left, right) =>
  JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right));

function exactKeys(value, expected, code, label) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    code,
    `${label} is not an object`,
  );
  assert(
    sameJson(Object.keys(value).sort(), [...expected].sort()),
    code,
    `${label} key set drifted`,
  );
}

function parseCanonicalPlan(bytes) {
  assert(Buffer.isBuffer(bytes), "PLAN_SCHEMA_REJECTED", "tool plan is not a Buffer");
  assert(bytes.length > 0 && bytes.length <= 65_536, "PLAN_SCHEMA_REJECTED", "tool plan length is invalid");
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("PLAN_SCHEMA_REJECTED", "tool plan is not exact UTF-8");
  }
  let plan;
  try {
    plan = JSON.parse(text);
  } catch {
    fail("PLAN_SCHEMA_REJECTED", "tool plan is not valid JSON");
  }
  assert(
    canonicalJsonBytes(plan).equals(bytes),
    "PLAN_CANONICAL_JSON_REJECTED",
    "tool plan is not canonical JSON",
  );
  return plan;
}

function validateFalseEffects(value) {
  exactKeys(
    value,
    Object.keys(FALSE_EFFECTS),
    "EXTERNAL_EFFECT_REQUEST_REJECTED",
    "requested external effects",
  );
  assert(
    sameJson(value, FALSE_EFFECTS),
    "EXTERNAL_EFFECT_REQUEST_REJECTED",
    "requested external effects are not all false",
  );
}

function validatePlan(plan) {
  exactKeys(
    plan,
    [
      "schema_version",
      "record_type",
      "plan_id",
      "provenance",
      "task_binding",
      "configuration_binding",
      "compatibility_profile_binding",
      "requested_external_effects",
      "steps",
      "claim_boundary",
    ],
    "PLAN_UNKNOWN_MEMBER_REJECTED",
    "tool plan",
  );
  assert(
    plan.schema_version === 1 &&
      plan.record_type === "sourcelens_aios_offline_b1_finite_typed_tool_plan" &&
      plan.plan_id === PLAN_ID &&
      plan.claim_boundary === CLAIM_BOUNDARY,
    "PLAN_SCHEMA_REJECTED",
    "tool plan identity drifted",
  );

  exactKeys(
    plan.provenance,
    ["kind", "live_model_invoked", "model_performance_sample", "provider_invoked"],
    "PLAN_UNKNOWN_MEMBER_REJECTED",
    "tool plan provenance",
  );
  assert(
    plan.provenance.kind === "QUALITY_FROZEN_COOPERATIVE_LOCAL_FIXTURE" &&
      plan.provenance.live_model_invoked === false &&
      plan.provenance.model_performance_sample === false &&
      plan.provenance.provider_invoked === false,
    "PLAN_PROVENANCE_REJECTED",
    "tool plan provenance drifted",
  );

  exactKeys(
    plan.task_binding,
    [
      "base_commit",
      "base_tree",
      "dataset_version",
      "task_id",
      "task_spec_byte_length",
      "task_spec_sha256",
    ],
    "PLAN_UNKNOWN_MEMBER_REJECTED",
    "task binding",
  );
  assert(
    plan.task_binding.task_id === TASK_ID &&
      plan.task_binding.dataset_version === "1.0.0" &&
      plan.task_binding.base_commit === BASE_COMMIT &&
      plan.task_binding.base_tree === BASE_TREE &&
      plan.task_binding.task_spec_byte_length === EXPECTED.task_spec.byte_length &&
      plan.task_binding.task_spec_sha256 === EXPECTED.task_spec.sha256,
    "PLAN_IDENTITY_REJECTED",
    "task binding drifted",
  );

  exactKeys(
    plan.configuration_binding,
    ["byte_length", "configuration_id", "sha256"],
    "PLAN_UNKNOWN_MEMBER_REJECTED",
    "configuration binding",
  );
  assert(
    plan.configuration_binding.configuration_id === EXPECTED.system_configuration.id &&
      plan.configuration_binding.byte_length === EXPECTED.system_configuration.byte_length &&
      plan.configuration_binding.sha256 === EXPECTED.system_configuration.sha256,
    "PLAN_IDENTITY_REJECTED",
    "configuration binding drifted",
  );

  exactKeys(
    plan.compatibility_profile_binding,
    ["byte_length", "profile_id", "sha256"],
    "PLAN_UNKNOWN_MEMBER_REJECTED",
    "compatibility profile binding",
  );
  assert(
    plan.compatibility_profile_binding.profile_id === EXPECTED.compatibility_profile.id &&
      plan.compatibility_profile_binding.byte_length === EXPECTED.compatibility_profile.byte_length &&
      plan.compatibility_profile_binding.sha256 === EXPECTED.compatibility_profile.sha256,
    "PLAN_IDENTITY_REJECTED",
    "compatibility profile binding drifted",
  );

  validateFalseEffects(plan.requested_external_effects);
  assert(
    Array.isArray(plan.steps) && plan.steps.length === REQUIRED_STEPS.length,
    "PLAN_BUDGET_REJECTED",
    "tool plan must contain exactly three steps",
  );
  for (let index = 0; index < plan.steps.length; index += 1) {
    const step = plan.steps[index];
    assert(
      step !== null && typeof step === "object" && !Array.isArray(step),
      "PLAN_SCHEMA_REJECTED",
      `step ${index + 1} is not an object`,
    );
    const dynamic = Object.keys(step).find((key) => DYNAMIC_FIELDS.has(key));
    if (dynamic !== undefined) {
      fail("DYNAMIC_PARAMETER_REJECTED", `step ${index + 1} contains dynamic field ${dynamic}`);
    }
    exactKeys(
      step,
      ["ordinal", "tool_id", "operation_id"],
      "PLAN_UNKNOWN_MEMBER_REJECTED",
      `step ${index + 1}`,
    );
    assert(
      step.ordinal === index + 1,
      "PLAN_ORDER_REJECTED",
      `step ${index + 1} ordinal/order drifted`,
    );
    assert(
      step.tool_id === REQUIRED_STEPS[index].tool_id &&
        step.operation_id === REQUIRED_STEPS[index].operation_id,
      "PLAN_TOOL_REJECTED",
      `step ${index + 1} tool mapping drifted`,
    );
  }
  return plan;
}

/**
 * Admit the one Quality-frozen B1 plan. The caller supplies exact IR10 bytes;
 * the adapter never accepts an executable, path, argv, cwd, environment,
 * module, timeout, source program, shell fragment, diff, or AST from the plan.
 */
export function admitOfflineB1ToolPlan(planBytes, ir10Bytes) {
  const plan = validatePlan(parseCanonicalPlan(planBytes));
  assert(Buffer.isBuffer(ir10Bytes), "IR_INPUT_REJECTED", "IR10 is not a Buffer");
  assert(
    ir10Bytes.length === EXPECTED.ir10.byte_length && sha256(ir10Bytes) === EXPECTED.ir10.sha256,
    "IR_INPUT_REJECTED",
    "IR10 identity drifted",
  );
  const compiled = compileFiniteTypedPatchIr(ir10Bytes);
  assert(
    COMPILER_VERSION === "SL-PATCH-IR-TRUSTED-COMPILER/1" &&
      compiled.status === "COMPILED" &&
      compiled.program_id === "IR10" &&
      compiled.outcome_id === "CORRECT_END_START" &&
      compiled.kind === "COMPLETE_POSTIMAGE" &&
      Buffer.isBuffer(compiled.postimage),
    "COMPILER_OBSERVATION_REJECTED",
    "compiler did not produce the exact admitted IR10 observation",
  );
  assert(
    compiled.postimage.length === EXPECTED.postimage.byte_length &&
      sha256(compiled.postimage) === EXPECTED.postimage.sha256,
    "COMPILER_OBSERVATION_REJECTED",
    "compiler postimage identity drifted",
  );

  return {
    status: "ADMITTED_CLOSED_FINITE_TOOL_PLAN",
    adapter_version: ADAPTER_VERSION,
    plan_id: PLAN_ID,
    plan_byte_length: planBytes.length,
    plan_sha256: sha256(planBytes),
    compiler_version: COMPILER_VERSION,
    program_id: compiled.program_id,
    outcome_id: compiled.outcome_id,
    postimage_byte_length: compiled.postimage.length,
    postimage_sha256: sha256(compiled.postimage),
    postimage: Buffer.from(compiled.postimage),
    actions: REQUIRED_STEPS.map((step) => ({ ...step })),
    external_effects: { ...FALSE_EFFECTS },
    claim_boundary: CLAIM_BOUNDARY,
  };
}

function adapterSelfTest() {
  const moduleDirectory = dirname(fileURLToPath(import.meta.url));
  const repositoryRoot = resolve(moduleDirectory, "../../..");
  const planBytes = readFileSync(resolve(repositoryRoot, "evaluation-harness/fixtures/offline-b1-simple-tool-v1/positive-tool-plan.json"));
  const ir10Bytes = readFileSync(resolve(repositoryRoot, "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json"));
  const admitted = admitOfflineB1ToolPlan(planBytes, ir10Bytes);
  assert(admitted.status === "ADMITTED_CLOSED_FINITE_TOOL_PLAN" && admitted.actions.length === 3 && admitted.postimage_sha256 === EXPECTED.postimage.sha256, "SELF_TEST_FAILED", "positive admission drifted");
  const positive = parseCanonicalPlan(planBytes);
  const negativeCases = [
    ["unknown-member", "PLAN_UNKNOWN_MEMBER_REJECTED", (plan) => { plan.unexpected = true; }],
    ["dynamic-argv", "DYNAMIC_PARAMETER_REJECTED", (plan) => { plan.steps[0].argv = ["attacker-controlled"]; }],
    ["reordered", "PLAN_ORDER_REJECTED", (plan) => { [plan.steps[0], plan.steps[1]] = [plan.steps[1], plan.steps[0]]; }],
    ["external-network", "EXTERNAL_EFFECT_REQUEST_REJECTED", (plan) => { plan.requested_external_effects.network = true; }],
  ];
  const outcomes = [];
  for (const [id, expectedCode, mutate] of negativeCases) {
    const plan = JSON.parse(JSON.stringify(positive));
    mutate(plan);
    let observed;
    try { admitOfflineB1ToolPlan(canonicalJsonBytes(plan), ir10Bytes); } catch (error) { observed = error instanceof OfflineB1AdapterError ? error.code : null; }
    assert(observed === expectedCode, "SELF_TEST_FAILED", `${id} expected ${expectedCode}, got ${observed}`);
    outcomes.push({ id, reason_code: observed, admitted: false });
  }
  const driftedIr = Buffer.from(ir10Bytes);
  driftedIr[0] ^= 1;
  let irObserved;
  try { admitOfflineB1ToolPlan(planBytes, driftedIr); } catch (error) { irObserved = error instanceof OfflineB1AdapterError ? error.code : null; }
  assert(irObserved === "IR_INPUT_REJECTED", "SELF_TEST_FAILED", `IR drift expected IR_INPUT_REJECTED, got ${irObserved}`);
  outcomes.push({ id: "ir10-drift", reason_code: irObserved, admitted: false });
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_067_adapter_self_test",
    adapter_version: ADAPTER_VERSION,
    positive_admission: "PASS",
    negative_case_count: outcomes.length,
    negative_outcomes: outcomes,
    false_accepts: 0,
    target_verdict: "PASS",
    claim_boundary: CLAIM_BOUNDARY,
  };
}

if (resolve(process.argv[1] ?? "") === resolve(fileURLToPath(import.meta.url))) {
  try {
    assert(process.argv.length === 3 && process.argv[2] === "self-test", "CLI_REJECTED", "adapter supports only self-test");
    process.stdout.write(canonicalJsonBytes(adapterSelfTest()));
  } catch (error) {
    const code = error instanceof OfflineB1AdapterError ? error.code : "UNEXPECTED_ERROR";
    process.stderr.write(canonicalJsonBytes({
      schema_version: 1,
      record_type: "sourcelens_aios_p1_067_adapter_error",
      reason_code: code,
      message: error instanceof Error ? error.message : String(error),
      agent_status: "NON_PASS",
    }));
    process.exitCode = 2;
  }
}

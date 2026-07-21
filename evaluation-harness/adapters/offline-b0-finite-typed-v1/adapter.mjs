import { createHash } from "node:crypto";

import {
  COMPILER_VERSION,
  compileFiniteTypedPatchIr,
} from "../../harness/finite-typed-patch-ir-v1/compiler.mjs";

export const ADAPTER_VERSION = "OFFLINE-B0-FINITE-TYPED-ADAPTER/1";

const TASK_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const CLAIM_BOUNDARY =
  "ONE_VISIBLE_SYNTHETIC_REP_001_COOPERATIVE_LOCAL_OFFLINE_B0_COMPLETE_EVIDENCE_OBSERVATION_ONLY";
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
const EXPECTED = Object.freeze({
  task_spec: {
    byte_length: 2960,
    sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
  },
  target_runtime: {
    id: "TARGET-P1-066-DARWIN-ARM64-NODE20-STDLIB-1",
    byte_length: 1688,
    sha256: "4319712be0509e870bb9478e991bff31dd8a11384349f5e71c40715f8ee75e22",
  },
  environment: {
    id: "ENV-SOURCELENS-P1-REP-NODE20-STDLIB-1",
    byte_length: 1782,
    sha256: "f6aa054ef9b03712465f4442213f72af5dff97da7dc2977e612e18617fa8fc80",
  },
  system_configuration: {
    id: "P1-066-B0-OFFLINE-FINITE-TYPED-1",
    byte_length: 986,
    sha256: "60a0bd1ac6e8b1e1b381aff7c8ec614d46afeb758d86b842ef328bb8d22ae9ea",
  },
  compiler: {
    byte_length: 3814,
    sha256: "013a58a6284270c6808f6cfe815dbea6825b8a43a0a6f885305df23890c7a4f9",
  },
  response_format: {
    byte_length: 306,
    sha256: "6b8ec1d2a6a288e5b908716714589dae963739f2b35a0a29237ff4cbc1355c4b",
  },
  proposal: {
    byte_length: 255,
    sha256: "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc",
  },
  postimage: {
    byte_length: 127,
    sha256: "e8304b77da9b8c33f64ecdc568db7e97297ace72ecb796971bb3f5eda09d9001",
  },
});

export class OfflineB0AdapterError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OfflineB0AdapterError";
    this.code = code;
  }
}

const fail = (code, message) => {
  throw new OfflineB0AdapterError(code, message);
};
const assert = (condition, code, message) => {
  if (!condition) fail(code, message);
};
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const canonicalize = (value) => {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
};
const sameJson = (left, right) => JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right));

function parseJsonBytes(bytes) {
  assert(Buffer.isBuffer(bytes), "SUBMISSION_SCHEMA_REJECTED", "submission is not a Buffer");
  const text = bytes.toString("utf8");
  assert(Buffer.from(text, "utf8").equals(bytes), "SUBMISSION_SCHEMA_REJECTED", "submission is not exact UTF-8");
  try {
    return JSON.parse(text);
  } catch {
    fail("SUBMISSION_SCHEMA_REJECTED", "submission is not valid JSON");
  }
}

function exactKeys(value, expected, label) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "SUBMISSION_SCHEMA_REJECTED",
    `${label} is not an object`,
  );
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  assert(
    sameJson(actual, wanted),
    "SUBMISSION_UNKNOWN_MEMBER_REJECTED",
    `${label} key set is not closed`,
  );
}

function exactFalseEffects(value, reasonCode, label) {
  exactKeys(value, Object.keys(FALSE_EFFECTS), label);
  assert(sameJson(value, FALSE_EFFECTS), reasonCode, `${label} is not all false`);
}

function decodeCanonicalBase64(value) {
  assert(
    typeof value === "string" &&
      value.length > 0 &&
      value.length % 4 === 0 &&
      /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value),
    "SUBMISSION_SCHEMA_REJECTED",
    "proposal base64 has invalid shape",
  );
  const bytes = Buffer.from(value, "base64");
  assert(bytes.toString("base64") === value, "SUBMISSION_SCHEMA_REJECTED", "proposal base64 is not canonical");
  return bytes;
}

function validateEnvelope(value) {
  exactKeys(value, [
    "schema_version",
    "record_type",
    "submission_id",
    "provenance",
    "task_binding",
    "target_runtime_binding",
    "environment_binding",
    "system_configuration_binding",
    "compiler_binding",
    "response_format_binding",
    "results",
    "claim_boundary",
  ], "submission envelope");
  assert(
    value.schema_version === 1 &&
      value.record_type === "sourcelens_aios_provider_neutral_offline_b0_result_envelope" &&
      typeof value.submission_id === "string" &&
      value.submission_id.length > 0,
    "SUBMISSION_SCHEMA_REJECTED",
    "submission envelope identity is invalid",
  );

  exactKeys(value.provenance, [
    "kind",
    "live_model_invoked",
    "provider_invoked",
    "model_performance_sample",
  ], "submission provenance");
  assert(
    value.provenance.kind === "QUALITY_FROZEN_COOPERATIVE_LOCAL_FIXTURE" &&
      value.provenance.live_model_invoked === false &&
      value.provenance.provider_invoked === false &&
      value.provenance.model_performance_sample === false,
    "SUBMISSION_SCHEMA_REJECTED",
    "submission provenance is invalid",
  );

  exactKeys(value.task_binding, [
    "task_id",
    "dataset_version",
    "task_spec_byte_length",
    "task_spec_sha256",
    "base_commit",
    "base_tree",
  ], "task binding");
  assert(
    value.task_binding.task_id === TASK_ID &&
      value.task_binding.dataset_version === "1.0.0" &&
      value.task_binding.task_spec_byte_length === EXPECTED.task_spec.byte_length &&
      value.task_binding.task_spec_sha256 === EXPECTED.task_spec.sha256 &&
      value.task_binding.base_commit === BASE_COMMIT &&
      value.task_binding.base_tree === BASE_TREE,
    "INPUT_IDENTITY_REJECTED",
    "task or source binding drifted",
  );

  exactKeys(value.target_runtime_binding, [
    "target_runtime_id",
    "byte_length",
    "sha256",
    "materialized",
    "container_execution_observed",
  ], "target runtime binding");
  assert(
    value.target_runtime_binding.target_runtime_id === EXPECTED.target_runtime.id &&
      value.target_runtime_binding.byte_length === EXPECTED.target_runtime.byte_length &&
      value.target_runtime_binding.sha256 === EXPECTED.target_runtime.sha256 &&
      value.target_runtime_binding.materialized === false &&
      value.target_runtime_binding.container_execution_observed === false,
    "ENVIRONMENT_BINDING_REJECTED",
    "target runtime binding drifted",
  );

  exactKeys(value.environment_binding, ["snapshot_id", "byte_length", "sha256"], "environment binding");
  assert(
    value.environment_binding.snapshot_id === EXPECTED.environment.id &&
      value.environment_binding.byte_length === EXPECTED.environment.byte_length &&
      value.environment_binding.sha256 === EXPECTED.environment.sha256,
    "ENVIRONMENT_BINDING_REJECTED",
    "environment binding drifted",
  );

  exactKeys(
    value.system_configuration_binding,
    ["configuration_id", "byte_length", "sha256"],
    "system configuration binding",
  );
  assert(
    value.system_configuration_binding.configuration_id === EXPECTED.system_configuration.id &&
      value.system_configuration_binding.byte_length === EXPECTED.system_configuration.byte_length &&
      value.system_configuration_binding.sha256 === EXPECTED.system_configuration.sha256,
    "SYSTEM_CONFIGURATION_BINDING_REJECTED",
    "system configuration binding drifted",
  );

  exactKeys(value.compiler_binding, ["version", "byte_length", "sha256"], "compiler binding");
  assert(
    value.compiler_binding.version === COMPILER_VERSION &&
      value.compiler_binding.byte_length === EXPECTED.compiler.byte_length &&
      value.compiler_binding.sha256 === EXPECTED.compiler.sha256,
    "INPUT_IDENTITY_REJECTED",
    "compiler binding drifted",
  );
  exactKeys(value.response_format_binding, ["byte_length", "sha256"], "response format binding");
  assert(
    value.response_format_binding.byte_length === EXPECTED.response_format.byte_length &&
      value.response_format_binding.sha256 === EXPECTED.response_format.sha256,
    "INPUT_IDENTITY_REJECTED",
    "response format binding drifted",
  );
  assert(value.claim_boundary === CLAIM_BOUNDARY, "SUBMISSION_SCHEMA_REJECTED", "claim boundary drifted");

  assert(Array.isArray(value.results), "SUBMISSION_SCHEMA_REJECTED", "results is not an array");
  assert(value.results.length === 1, "RESULT_CARDINALITY_REJECTED", "results must contain exactly one member");
  const result = value.results[0];
  exactKeys(result, ["result_id", "response", "finite_typed_result", "requested_external_effects"], "result");
  assert(typeof result.result_id === "string" && result.result_id.length > 0, "SUBMISSION_SCHEMA_REJECTED", "result id is invalid");

  exactKeys(result.response, ["summary", "changed_paths", "tests"], "result response");
  assert(
    typeof result.response.summary === "string" &&
      result.response.summary.length > 0 &&
      Array.isArray(result.response.changed_paths) &&
      result.response.changed_paths.every((item) => typeof item === "string") &&
      Array.isArray(result.response.tests) &&
      result.response.tests.every((item) => typeof item === "string"),
    "SUBMISSION_SCHEMA_REJECTED",
    "result response is invalid",
  );
  assert(sameJson(result.response.changed_paths, ["src/range.mjs"]), "INPUT_IDENTITY_REJECTED", "changed path declaration drifted");
  exactFalseEffects(result.requested_external_effects, "EXTERNAL_EFFECT_REQUEST_REJECTED", "requested external effects");

  const typed = result.finite_typed_result;
  exactKeys(typed, ["schema", "encoding", "bytes_base64", "byte_length", "sha256"], "finite typed result");
  assert(
    typed.schema === "SL-PATCH-IR/1" && typed.encoding === "base64",
    "SUBMISSION_SCHEMA_REJECTED",
    "finite typed result schema or encoding is invalid",
  );
  const decodedProposal = decodeCanonicalBase64(typed.bytes_base64);
  assert(
    decodedProposal.length === typed.byte_length && sha256(decodedProposal) === typed.sha256,
    "INPUT_IDENTITY_REJECTED",
    "proposal declared identity drifted",
  );
  return { result, typed, decodedProposal };
}

/**
 * Admit one Quality-frozen provider-neutral result.
 *
 * proposalBytes must be the Buffer decoded by the runner from the envelope. The
 * exact same Buffer object is passed to the accepted finite compiler. Nothing in
 * the envelope can select a path, executable, argv, cwd, environment or module.
 */
export function admitOfflineB0Result(submissionBytes, proposalBytes) {
  assert(Buffer.isBuffer(proposalBytes), "SUBMISSION_SCHEMA_REJECTED", "proposal is not a Buffer");
  const value = parseJsonBytes(submissionBytes);
  const { decodedProposal } = validateEnvelope(value);
  assert(
    decodedProposal.equals(proposalBytes),
    "INPUT_IDENTITY_REJECTED",
    "runner proposal Buffer is not the exact envelope proposal",
  );

  const compiled = compileFiniteTypedPatchIr(proposalBytes);
  if (compiled.status === "REJECTED") {
    fail(compiled.reason_code ?? "IR_NOT_EXACTLY_ADMITTED", "accepted compiler rejected proposal");
  }
  assert(
    proposalBytes.length === EXPECTED.proposal.byte_length && sha256(proposalBytes) === EXPECTED.proposal.sha256,
    "INPUT_IDENTITY_REJECTED",
    "proposal is not exact frozen IR10",
  );
  assert(
    compiled.status === "COMPILED" &&
      compiled.program_id === "IR10" &&
      compiled.outcome_id === "CORRECT_END_START" &&
      compiled.kind === "COMPLETE_POSTIMAGE" &&
      Buffer.isBuffer(compiled.postimage),
    "COMPILER_OBSERVATION_REJECTED",
    "accepted compiler observation is not exact IR10",
  );
  assert(
    compiled.postimage.length === EXPECTED.postimage.byte_length &&
      sha256(compiled.postimage) === EXPECTED.postimage.sha256,
    "COMPILER_OBSERVATION_REJECTED",
    "accepted compiler postimage identity drifted",
  );

  return {
    status: "ADMITTED_EXACT_IR10",
    result_count: 1,
    program_id: compiled.program_id,
    outcome_id: compiled.outcome_id,
    kind: compiled.kind,
    proposal_byte_length: proposalBytes.length,
    proposal_sha256: sha256(proposalBytes),
    postimage_byte_length: compiled.postimage.length,
    postimage_sha256: sha256(compiled.postimage),
    postimage: Buffer.from(compiled.postimage),
    submission_byte_length: submissionBytes.length,
    submission_sha256: sha256(submissionBytes),
  };
}

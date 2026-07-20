import { createHash } from "node:crypto";

export const QUALITY_ORACLE_VERSION = "SL-PATCH-IR-QUALITY-ORACLE/1";

export class QualityOracleError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "QualityOracleError";
    this.code = code;
  }
}

const freeze = (value) => Object.freeze(value);
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const fail = (code, message) => {
  throw new QualityOracleError(code, message);
};
const assert = (condition, code, message) => {
  if (!condition) fail(code, message);
};
const canonicalize = (value) => {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
};
const sameJson = (left, right) => JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right));

export const TASK_CARD_IDENTITY = freeze({
  byte_length: 24928,
  sha256: "08c6c25c34d70fb7d41452a69fd31e7527aac5014c34d9ef2305cdbca4be200c",
});

const PROGRAM_DEFINITIONS = [
  {
    id: "IR00",
    enum: "ARG0_ARG0",
    values: ["ARG0", "ARG0"],
    sha256: "e21da56b4132c121419863bad9e682532963f8b5bc9951af31b23234d9c46736",
    outcome_id: "SAFE_WRONG_START_START",
  },
  {
    id: "IR01",
    enum: "ARG0_ARG1",
    values: ["ARG0", "ARG1"],
    sha256: "db33a4d4f2a5b21f211344d785785c2b4c246677bbcf68ef0d5e1831cdf3d0c1",
    outcome_id: "IDENTITY_NO_EFFECT_REJECTION",
  },
  {
    id: "IR10",
    enum: "ARG1_ARG0",
    values: ["ARG1", "ARG0"],
    sha256: "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc",
    outcome_id: "CORRECT_END_START",
  },
  {
    id: "IR11",
    enum: "ARG1_ARG1",
    values: ["ARG1", "ARG1"],
    sha256: "0eeca741f57b218ee175308080de3ada3db1b4eb93222bd252cac9ed6e2c66f7",
    outcome_id: "SAFE_WRONG_END_END",
  },
];

function programBytes(values) {
  return Buffer.from(
    `{"schema":"SL-PATCH-IR/1","task":"SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0",` +
      `"base_commit":"68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f",` +
      `"base_tree":"900814727113d65f5dad8b63222e14f39b2cf38b",` +
      `"target":"T0","op":"REBIND_OBJECT_FIELDS","values":["${values[0]}","${values[1]}"]}\n`,
    "utf8",
  );
}

const PROGRAM_TABLE_INTERNAL = freeze(
  PROGRAM_DEFINITIONS.map((definition) => {
    const bytes = programBytes(definition.values);
    assert(bytes.length === 255, "ORACLE_CONSTANT_INVALID", `${definition.id} length drift`);
    assert(sha256(bytes) === definition.sha256, "ORACLE_CONSTANT_INVALID", `${definition.id} hash drift`);
    return freeze({ ...definition, values: freeze([...definition.values]), byte_length: 255, bytes });
  }),
);

export const PROGRAM_TABLE = freeze(
  PROGRAM_TABLE_INTERNAL.map(({ bytes: _bytes, ...program }) =>
    freeze({ ...program, values: freeze([...program.values]) })),
);

const BASE_POSTIMAGE = Buffer.from(
  "ZXhwb3J0IGZ1bmN0aW9uIG5vcm1hbGl6ZVJhbmdlKHN0YXJ0LCBlbmQpIHsKICBpZiAoc3RhcnQgPD0gZW5kKSByZXR1cm4geyBzdGFydCwgZW5kIH07CiAgcmV0dXJuIHsgc3RhcnQsIGVuZCB9Owp9Cg==",
  "base64",
);

const OUTCOME_DEFINITIONS = [
  {
    outcome_id: "SAFE_WRONG_START_START",
    kind: "COMPLETE_POSTIMAGE",
    postimage_base64:
      "ZXhwb3J0IGZ1bmN0aW9uIG5vcm1hbGl6ZVJhbmdlKHN0YXJ0LCBlbmQpIHsKICBpZiAoc3RhcnQgPD0gZW5kKSByZXR1cm4geyBzdGFydCwgZW5kIH07CiAgcmV0dXJuIHsgc3RhcnQ6IHN0YXJ0LCBlbmQ6IHN0YXJ0IH07Cn0K",
    postimage_byte_length: 129,
    postimage_sha256: "7c96fca76278ec86045d4eb61141d279eeda08af8c10a7465cea0f6e4656e2f1",
    issue_exit_status: 1,
    regression_exit_status: 0,
    evaluator_verdict: "REJECT_SAFE_WRONG",
    mutation_attempts: 1,
    child_start_attempts: 2,
  },
  {
    outcome_id: "IDENTITY_NO_EFFECT_REJECTION",
    kind: "IDENTITY_NO_EFFECT_REJECTION",
    postimage_base64: null,
    postimage_byte_length: null,
    postimage_sha256: null,
    issue_exit_status: null,
    regression_exit_status: null,
    evaluator_verdict: "REJECT_IDENTITY_NO_EFFECT",
    mutation_attempts: 0,
    child_start_attempts: 0,
  },
  {
    outcome_id: "CORRECT_END_START",
    kind: "COMPLETE_POSTIMAGE",
    postimage_base64:
      "ZXhwb3J0IGZ1bmN0aW9uIG5vcm1hbGl6ZVJhbmdlKHN0YXJ0LCBlbmQpIHsKICBpZiAoc3RhcnQgPD0gZW5kKSByZXR1cm4geyBzdGFydCwgZW5kIH07CiAgcmV0dXJuIHsgc3RhcnQ6IGVuZCwgZW5kOiBzdGFydCB9Owp9Cg==",
    postimage_byte_length: 127,
    postimage_sha256: "e8304b77da9b8c33f64ecdc568db7e97297ace72ecb796971bb3f5eda09d9001",
    issue_exit_status: 0,
    regression_exit_status: 0,
    evaluator_verdict: "PASS_ONLY_SUCCESS",
    mutation_attempts: 1,
    child_start_attempts: 2,
  },
  {
    outcome_id: "SAFE_WRONG_END_END",
    kind: "COMPLETE_POSTIMAGE",
    postimage_base64:
      "ZXhwb3J0IGZ1bmN0aW9uIG5vcm1hbGl6ZVJhbmdlKHN0YXJ0LCBlbmQpIHsKICBpZiAoc3RhcnQgPD0gZW5kKSByZXR1cm4geyBzdGFydCwgZW5kIH07CiAgcmV0dXJuIHsgc3RhcnQ6IGVuZCwgZW5kOiBlbmQgfTsKfQo=",
    postimage_byte_length: 125,
    postimage_sha256: "229b8e41f7db2b6b007a3d05e5e61a3fdd68a9cf3107e0384d234d203d8f306e",
    issue_exit_status: 1,
    regression_exit_status: 0,
    evaluator_verdict: "REJECT_SAFE_WRONG",
    mutation_attempts: 1,
    child_start_attempts: 2,
  },
];

const OUTCOME_TABLE_INTERNAL = freeze(
  OUTCOME_DEFINITIONS.map((definition) => {
    const postimage = definition.postimage_base64 === null
      ? null
      : Buffer.from(definition.postimage_base64, "base64");
    if (postimage === null) {
      assert(definition.postimage_byte_length === null, "ORACLE_CONSTANT_INVALID", "identity length drift");
      assert(definition.postimage_sha256 === null, "ORACLE_CONSTANT_INVALID", "identity hash drift");
    } else {
      assert(
        postimage.length === definition.postimage_byte_length,
        "ORACLE_CONSTANT_INVALID",
        `${definition.outcome_id} postimage length drift`,
      );
      assert(
        sha256(postimage) === definition.postimage_sha256,
        "ORACLE_CONSTANT_INVALID",
        `${definition.outcome_id} postimage hash drift`,
      );
    }
    return freeze({ ...definition, postimage });
  }),
);

export const OUTCOME_TABLE = freeze(
  OUTCOME_TABLE_INTERNAL.map(({ postimage: _postimage, ...outcome }) => freeze({ ...outcome })),
);

const PROGRAM_BY_SHA = new Map(PROGRAM_TABLE_INTERNAL.map((program) => [program.sha256, program]));
const OUTCOME_BY_ID = new Map(OUTCOME_TABLE_INTERNAL.map((outcome) => [outcome.outcome_id, outcome]));

function malformedPayloads() {
  const ir10 = PROGRAM_TABLE_INTERNAL.find((program) => program.id === "IR10").bytes;
  return new Map([
    ["empty", Buffer.alloc(0)],
    ["oversize-a-4097", Buffer.alloc(4097, 0x41)],
    ["utf8-bom-prefix", Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), ir10])],
    ["nul-suffix", Buffer.concat([ir10, Buffer.from([0x00])])],
    ["invalid-utf8", Buffer.from([0xff, 0xfe, 0xfd])],
    ["json-shape", Buffer.from('{"schema":"SL-PATCH-IR/1","values":[]}\n', "utf8")],
    ["path-payload", Buffer.from("../../../../canonical/main\n", "utf8")],
    ["js-payload", Buffer.from('{"values":["ARG1","process.exit(0)"]}\n', "utf8")],
    ["shell-payload", Buffer.from("$(touch /tmp/sourcelens-forbidden)\n", "utf8")],
    ["terminal-payload", Buffer.from([0x1b, 0x5d, 0x30, 0x3b, 0x74, 0x61, 0x6d, 0x70, 0x65, 0x72, 0x07, 0x0a])],
  ]);
}

function exactProgramInternal(proposalBytes) {
  if (!Buffer.isBuffer(proposalBytes) || proposalBytes.length > 255) return null;
  const digest = sha256(proposalBytes);
  const indexed = PROGRAM_BY_SHA.get(digest);
  if (!indexed || indexed.byte_length !== proposalBytes.length || !indexed.bytes.equals(proposalBytes)) return null;
  return indexed;
}

export function admitExactProgram(proposalBytes) {
  const admitted = exactProgramInternal(proposalBytes);
  if (!admitted) return null;
  return PROGRAM_TABLE.find((program) => program.id === admitted.id);
}

export function evaluateCompilerObservation(proposalBytes, compilerResult) {
  assert(Buffer.isBuffer(proposalBytes), "COMPILER_OBSERVATION_REJECTED", "proposal is not raw bytes");
  assert(compilerResult && typeof compilerResult === "object", "COMPILER_OBSERVATION_REJECTED", "compiler result missing");
  const expectedProgram = exactProgramInternal(proposalBytes);
  if (!expectedProgram) {
    assert(compilerResult.status === "REJECTED", "COMPILER_FALSE_ACCEPT", "invalid bytes were not rejected");
    assert(
      compilerResult.reason_code === "IR_NOT_EXACTLY_ADMITTED",
      "COMPILER_OBSERVATION_REJECTED",
      "invalid rejection reason drift",
    );
    assert(compilerResult.program_id === null, "COMPILER_FALSE_ACCEPT", "invalid bytes received a program id");
    assert(compilerResult.outcome_id === null, "COMPILER_FALSE_ACCEPT", "invalid bytes received an outcome id");
    assert(compilerResult.postimage === null, "COMPILER_FALSE_ACCEPT", "invalid bytes received a postimage");
    return freeze({ admission: "REJECTED", reason_code: "IR_NOT_EXACTLY_ADMITTED" });
  }

  const expectedOutcome = OUTCOME_BY_ID.get(expectedProgram.outcome_id);
  assert(compilerResult.program_id === expectedProgram.id, "COMPILER_OBSERVATION_REJECTED", "legal program id mismatch");
  assert(compilerResult.outcome_id === expectedOutcome.outcome_id, "COMPILER_OBSERVATION_REJECTED", "legal outcome mismatch");
  assert(compilerResult.kind === expectedOutcome.kind, "COMPILER_OBSERVATION_REJECTED", "legal outcome kind mismatch");
  if (expectedOutcome.postimage === null) {
    assert(
      compilerResult.status === "IDENTITY_NO_EFFECT_REJECTION",
      "COMPILER_OBSERVATION_REJECTED",
      "identity status mismatch",
    );
    assert(compilerResult.postimage === null, "COMPILER_OBSERVATION_REJECTED", "identity produced a postimage");
  } else {
    assert(compilerResult.status === "COMPILED", "COMPILER_OBSERVATION_REJECTED", "compiled status mismatch");
    assert(Buffer.isBuffer(compilerResult.postimage), "COMPILER_OBSERVATION_REJECTED", "postimage is not bytes");
    assert(compilerResult.postimage.length === expectedOutcome.postimage_byte_length, "COMPILER_OBSERVATION_REJECTED", "postimage length mismatch");
    assert(sha256(compilerResult.postimage) === expectedOutcome.postimage_sha256, "COMPILER_OBSERVATION_REJECTED", "postimage hash mismatch");
    assert(compilerResult.postimage.equals(expectedOutcome.postimage), "COMPILER_OBSERVATION_REJECTED", "postimage exact bytes mismatch");
  }
  return freeze({
    admission: "ADMITTED_EXACT_LEGAL_PROGRAM",
    program_id: expectedProgram.id,
    outcome_id: expectedOutcome.outcome_id,
  });
}

function runByteClosure(compileFunction) {
  if (compileFunction !== null) {
    assert(typeof compileFunction === "function", "COMPILER_INTERFACE_REJECTED", "compiler is not a function");
  }
  const stream = createHash("sha256");
  const counts = {
    substitution: 0,
    strict_truncation: 0,
    one_byte_prefix: 0,
    one_byte_suffix: 0,
    total: 0,
    legal_to_legal_transitions: 0,
    rejections: 0,
    false_accepts: 0,
  };
  const append = (record, candidate, family) => {
    const admitted = exactProgramInternal(candidate);
    if (compileFunction !== null) evaluateCompilerObservation(candidate, compileFunction(Buffer.from(candidate)));
    stream.update(`${record}|${sha256(candidate)}\n`);
    counts[family] += 1;
    counts.total += 1;
    if (admitted) counts.legal_to_legal_transitions += 1;
    else counts.rejections += 1;
  };

  for (const program of PROGRAM_TABLE_INTERNAL) {
    for (let position = 0; position < program.bytes.length; position += 1) {
      const original = program.bytes[position];
      for (let octet = 0; octet <= 255; octet += 1) {
        if (octet === original) continue;
        const candidate = Buffer.from(program.bytes);
        candidate[position] = octet;
        append(`S|${program.id}|${position}|${octet}`, candidate, "substitution");
      }
    }
  }
  for (const program of PROGRAM_TABLE_INTERNAL) {
    for (let length = 0; length < program.bytes.length; length += 1) {
      append(`T|${program.id}|${length}`, program.bytes.subarray(0, length), "strict_truncation");
    }
  }
  for (const program of PROGRAM_TABLE_INTERNAL) {
    for (let octet = 0; octet <= 255; octet += 1) {
      append(`P|${program.id}|${octet}`, Buffer.concat([Buffer.from([octet]), program.bytes]), "one_byte_prefix");
    }
  }
  for (const program of PROGRAM_TABLE_INTERNAL) {
    for (let octet = 0; octet <= 255; octet += 1) {
      append(`X|${program.id}|${octet}`, Buffer.concat([program.bytes, Buffer.from([octet])]), "one_byte_suffix");
    }
  }
  return freeze({ ...counts, stream_sha256: stream.digest("hex") });
}

export function computeByteClosureSummary() {
  return runByteClosure(null);
}

export function evaluateByteClosureCompiler(compileFunction) {
  return runByteClosure(compileFunction);
}

export function evaluateMalformedPayloadCompiler(compileFunction) {
  assert(typeof compileFunction === "function", "COMPILER_INTERFACE_REJECTED", "compiler is not a function");
  const results = [];
  for (const [id, bytes] of malformedPayloads()) {
    const evaluated = evaluateCompilerObservation(bytes, compileFunction(Buffer.from(bytes)));
    assert(evaluated.admission === "REJECTED", "COMPILER_FALSE_ACCEPT", `${id} was admitted`);
    results.push(freeze({ id, byte_length: bytes.length, sha256: sha256(bytes), reason_code: evaluated.reason_code }));
  }
  return freeze(results);
}

const REQUIRED_ACTIONS = freeze([
  "validate_candidate_and_quality_identities",
  "validate_compiler_tcb",
  "validate_frozen_inputs",
  "execute_exhaustive_byte_closure",
  "execute_explicit_malformed_payload_matrix",
  "execute_filesystem_evidence_canary_matrix",
  "materialize_fresh_rep001_repository",
  "verify_frozen_base_and_clean_state",
  "execute_base_issue_and_regression_tests",
  "execute_ir00_compile_replace_tests_evaluate_restore_exact_base",
  "execute_ir01_identity_no_effect_without_write_or_child",
  "execute_ir10_compile_replace_tests_evaluate_restore_exact_base",
  "execute_ir11_compile_replace_tests_evaluate_restore_exact_base",
  "emit_create_once_raw_evidence",
  "emit_stable_projection",
]);

const NEGATIVE_EXPECTATIONS = freeze([
  ["preexisting-run-root", "PREEXISTING_RUN_ROOT_REJECTED"],
  ["symlink-run-root", "SYMLINK_RUN_ROOT_REJECTED"],
  ["run-root-escape", "RUN_ROOT_ESCAPE_REJECTED"],
  ["target-symlink", "TARGET_SYMLINK_REJECTED"],
  ["target-hardlink", "TARGET_NLINK_REJECTED"],
  ["target-preimage-drift", "TARGET_PREIMAGE_DRIFT_REJECTED"],
  ["target-mode-drift", "TARGET_MODE_DRIFT_REJECTED"],
  ["unowned-materialization-marker", "MATERIALIZATION_OWNERSHIP_REJECTED"],
  ["preexisting-sidecar", "PREEXISTING_SIDECAR_REJECTED"],
  ["symlink-sidecar", "SYMLINK_SIDECAR_REJECTED"],
  ["preexisting-evidence-leaf", "PREEXISTING_EVIDENCE_LEAF_REJECTED"],
  ["symlink-evidence-leaf", "SYMLINK_EVIDENCE_LEAF_REJECTED"],
  ["hardlink-evidence-leaf", "EVIDENCE_NLINK_REJECTED"],
  ["evidence-path-escape", "EVIDENCE_PATH_ESCAPE_REJECTED"],
  ["extra-changed-path", "CHANGED_PATH_SCOPE_REJECTED"],
  ["unexpected-new-file", "UNEXPECTED_NEW_FILE_REJECTED"],
  ["identity-forged-mutation", "IDENTITY_EFFECT_REJECTED"],
  ["identity-forged-child", "IDENTITY_CHILD_START_REJECTED"],
  ["canary-tamper", "CANARY_TAMPER_REJECTED"],
  ["cleanup-ownership-drift", "CLEANUP_OWNERSHIP_REJECTED"],
  ["cleanup-identity-drift", "CLEANUP_IDENTITY_REJECTED"],
  ["root-identity-drift", "ROOT_IDENTITY_DRIFT_REJECTED"],
  ["target-identity-drift", "TARGET_IDENTITY_DRIFT_REJECTED"],
  ["nonfrozen-postimage", "POSTIMAGE_IDENTITY_REJECTED"],
  ["wrong-outcome-id", "OUTCOME_BINDING_REJECTED"],
  ["forged-test-status", "OBSERVATION_MISMATCH_REJECTED"],
  ["candidate-binding-drift", "CANDIDATE_BINDING_REJECTED"],
  ["missing-required-action", "ACTION_SCHEDULE_REJECTED"],
  ["stable-projection-tamper", "STABLE_PROJECTION_REJECTED"],
  ["evaluator-verdict-tamper", "EVALUATOR_VERDICT_REJECTED"],
]);

const FALSE_EFFECTS = freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});

export function evaluateNegativeResults(results) {
  assert(Array.isArray(results), "NEGATIVE_MATRIX_REJECTED", "negative results are not an array");
  assert(results.length === NEGATIVE_EXPECTATIONS.length, "NEGATIVE_MATRIX_REJECTED", "negative result population mismatch");
  const projection = [];
  for (let index = 0; index < NEGATIVE_EXPECTATIONS.length; index += 1) {
    const [expectedId, expectedReason] = NEGATIVE_EXPECTATIONS[index];
    const result = results[index];
    assert(result?.id === expectedId, "NEGATIVE_MATRIX_REJECTED", `negative case ${index} id mismatch`);
    assert(result.reason_code === expectedReason, "NEGATIVE_MATRIX_REJECTED", `${expectedId} reason mismatch`);
    assert(result.mutation_attempts === 0, "NEGATIVE_MATRIX_REJECTED", `${expectedId} attempted mutation`);
    assert(result.child_start_attempts === 0, "NEGATIVE_MATRIX_REJECTED", `${expectedId} started a child`);
    assert(result.canary_status === "UNCHANGED", "NEGATIVE_MATRIX_REJECTED", `${expectedId} changed canary`);
    assert(sameJson(result.external_effects, FALSE_EFFECTS), "NEGATIVE_MATRIX_REJECTED", `${expectedId} external effect drift`);
    projection.push(freeze({
      id: expectedId,
      reason_code: expectedReason,
      mutation_attempts: 0,
      child_start_attempts: 0,
      canary_status: "UNCHANGED",
      external_effects: FALSE_EFFECTS,
    }));
  }
  return freeze(projection);
}

export function evaluateRollbackObservations(rollbacks) {
  assert(Array.isArray(rollbacks) && rollbacks.length === 4, "ROLLBACK_REJECTED", "rollback population mismatch");
  const expectedIds = PROGRAM_TABLE_INTERNAL.map((program) => program.id);
  const projection = [];
  for (let index = 0; index < expectedIds.length; index += 1) {
    const rollback = rollbacks[index];
    const programId = expectedIds[index];
    assert(rollback?.program_id === programId, "ROLLBACK_REJECTED", `${programId} rollback order mismatch`);
    assert(
      rollback.source_sha256 === "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75",
      "ROLLBACK_REJECTED",
      `${programId} source was not restored`,
    );
    assert(rollback.base_commit === "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f", "ROLLBACK_REJECTED", `${programId} base commit drift`);
    assert(rollback.base_tree === "900814727113d65f5dad8b63222e14f39b2cf38b", "ROLLBACK_REJECTED", `${programId} base tree drift`);
    assert(rollback.git_status_porcelain === "", "ROLLBACK_REJECTED", `${programId} materialization is dirty`);
    assert(rollback.restored_exact_base === true, "ROLLBACK_REJECTED", `${programId} restore verdict mismatch`);
    const expectedMutation = programId !== "IR01";
    assert(rollback.mutation_occurred === expectedMutation, "ROLLBACK_REJECTED", `${programId} mutation fact mismatch`);
    projection.push(freeze({
      program_id: programId,
      source_sha256: rollback.source_sha256,
      base_commit: rollback.base_commit,
      base_tree: rollback.base_tree,
      git_status_porcelain: "",
      restored_exact_base: true,
      mutation_occurred: expectedMutation,
    }));
  }
  return freeze(projection);
}

export function evaluateCandidateBinding(actual, expected) {
  assert(actual && expected && typeof actual === "object" && typeof expected === "object", "CANDIDATE_BINDING_REJECTED", "candidate binding missing");
  for (const key of ["candidate_commit", "candidate_tree", "candidate_manifest_sha256", "quality_freeze_manifest_sha256"]) {
    assert(typeof expected[key] === "string" && expected[key].length > 0, "CANDIDATE_BINDING_REJECTED", `expected ${key} missing`);
    assert(actual[key] === expected[key], "CANDIDATE_BINDING_REJECTED", `${key} mismatch`);
  }
  return freeze({
    candidate_commit: expected.candidate_commit,
    candidate_tree: expected.candidate_tree,
    candidate_manifest_sha256: expected.candidate_manifest_sha256,
    quality_freeze_manifest_sha256: expected.quality_freeze_manifest_sha256,
  });
}

export function normalizeCommandStream(rawBytes, physicalMaterializationRoot) {
  assert(Buffer.isBuffer(rawBytes), "COMMAND_STREAM_REJECTED", "command stream is not bytes");
  assert(
    typeof physicalMaterializationRoot === "string" && physicalMaterializationRoot.startsWith("/"),
    "COMMAND_STREAM_REJECTED",
    "materialization root is not absolute",
  );
  const raw = rawBytes.toString("utf8");
  assert(Buffer.from(raw, "utf8").equals(rawBytes), "COMMAND_STREAM_REJECTED", "command stream is not exact UTF-8");
  const escaped = physicalMaterializationRoot.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const rootPattern = new RegExp(escaped, "g");
  const normalized = raw
    .replace(rootPattern, "<MATERIALIZATION_ROOT>")
    .replace(/duration_ms: [0-9]+(?:\.[0-9]+)?/g, "duration_ms: <DURATION_MS>");
  assert(!normalized.includes(physicalMaterializationRoot), "COMMAND_STREAM_REJECTED", "physical root survived normalization");
  return Buffer.from(normalized, "utf8");
}

export function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
}

export function evaluateRunObservation(observation, expectedCandidate) {
  assert(observation && typeof observation === "object", "RUN_OBSERVATION_REJECTED", "run observation missing");
  assert(sameJson(observation.ordered_action_ids, REQUIRED_ACTIONS), "ACTION_SCHEDULE_REJECTED", "action schedule mismatch");
  const candidate = evaluateCandidateBinding(observation.candidate_binding, expectedCandidate);
  assert(
    observation.base_test_statuses?.issue === 1 && observation.base_test_statuses?.regression === 0,
    "RUN_OBSERVATION_REJECTED",
    "base test statuses mismatch",
  );
  assert(Array.isArray(observation.program_observations) && observation.program_observations.length === 4, "RUN_OBSERVATION_REJECTED", "program observation population mismatch");
  const programs = observation.program_observations.map(evaluateObservation);
  const closure = observation.byte_closure;
  const expectedClosure = {
    substitution: 260100,
    strict_truncation: 1020,
    one_byte_prefix: 1024,
    one_byte_suffix: 1024,
    total: 263168,
    legal_to_legal_transitions: 8,
    rejections: 263160,
    false_accepts: 0,
    stream_sha256: "a819e42a5f5ecca01daa3f77f0701f5dac80b8ff7f096c8bac8d627f30d8a38b",
  };
  assert(sameJson(closure, expectedClosure), "RUN_OBSERVATION_REJECTED", "compiler byte closure observation mismatch");
  const negatives = evaluateNegativeResults(observation.negative_case_results);
  const rollbacks = evaluateRollbackObservations(observation.rollback_observations);
  assert(observation.compiler_tcb_status === "PASS", "RUN_OBSERVATION_REJECTED", "compiler TCB did not pass");
  assert(observation.canary_status === "UNCHANGED", "RUN_OBSERVATION_REJECTED", "run canary changed");
  assert(sameJson(observation.external_effects, FALSE_EFFECTS), "RUN_OBSERVATION_REJECTED", "run external effects drift");
  return freeze({
    schema_version: 1,
    task_id: "AIOS-P1-055_FINITE_TYPED_PATCH_IR_COMPILER_CONFORMANCE",
    control_id: "SL-P1-REP-001-RANGE-NORMALIZATION",
    candidate_binding: candidate,
    ordered_action_ids: REQUIRED_ACTIONS,
    base_test_statuses: freeze({ issue: 1, regression: 0 }),
    program_outcomes: freeze(programs),
    byte_closure_counts: freeze({ ...expectedClosure, stream_sha256: undefined }),
    byte_closure_stream_sha256: expectedClosure.stream_sha256,
    negative_case_results: negatives,
    false_accepts: 0,
    mutation_attempts_on_rejections: 0,
    child_start_attempts_on_rejections: 0,
    compiler_tcb_status: "PASS",
    canary_status: "UNCHANGED",
    external_effects: FALSE_EFFECTS,
    per_program_rollback: rollbacks,
    verdict: "PASS",
  });
}

function expectedCardProgram(program) {
  return {
    id: program.id,
    enum: program.enum,
    values: [...program.values],
    path: `evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/${program.id.toLowerCase()}.json`,
    byte_length: program.byte_length,
    sha256: program.sha256,
    outcome_id: program.outcome_id,
  };
}

function expectedCardOutcome(outcome) {
  return {
    outcome_id: outcome.outcome_id,
    kind: outcome.kind,
    postimage_utf8: outcome.postimage === null ? null : outcome.postimage.toString("utf8"),
    postimage_byte_length: outcome.postimage_byte_length,
    postimage_sha256: outcome.postimage_sha256,
    ...(outcome.postimage === null ? {} : { expected_changed_paths: ["src/range.mjs"] }),
    mutation_attempts: outcome.mutation_attempts,
    child_start_attempts: outcome.child_start_attempts,
    expected_issue_exit_status: outcome.issue_exit_status,
    expected_regression_exit_status: outcome.regression_exit_status,
    expected_evaluator_verdict: outcome.evaluator_verdict,
  };
}

export function selfValidateProgramBuffers(programBuffers) {
  const supplied = programBuffers instanceof Map ? programBuffers : new Map(Object.entries(programBuffers ?? {}));
  assert(supplied.size === PROGRAM_TABLE_INTERNAL.length, "PROGRAM_SET_DRIFT", "program set size is not four");
  for (const program of PROGRAM_TABLE_INTERNAL) {
    const actual = supplied.get(program.id);
    assert(Buffer.isBuffer(actual), "PROGRAM_SET_DRIFT", `${program.id} is not a Buffer`);
    assert(actual.length === program.byte_length, "PROGRAM_SET_DRIFT", `${program.id} length mismatch`);
    assert(sha256(actual) === program.sha256, "PROGRAM_SET_DRIFT", `${program.id} hash mismatch`);
    assert(actual.equals(program.bytes), "PROGRAM_SET_DRIFT", `${program.id} exact bytes mismatch`);
  }
  return freeze({ status: "PASS", program_count: PROGRAM_TABLE_INTERNAL.length });
}

export function selfValidateTaskCardBytes(taskCardBytes) {
  assert(Buffer.isBuffer(taskCardBytes), "TASK_CARD_DRIFT", "Task Card must be a Buffer");
  assert(taskCardBytes.length === TASK_CARD_IDENTITY.byte_length, "TASK_CARD_DRIFT", "Task Card length mismatch");
  assert(sha256(taskCardBytes) === TASK_CARD_IDENTITY.sha256, "TASK_CARD_DRIFT", "Task Card hash mismatch");
  let card;
  try {
    card = JSON.parse(taskCardBytes.toString("utf8"));
  } catch {
    fail("TASK_CARD_DRIFT", "Task Card JSON parse failed");
  }
  assert(card.schema_version === 1, "TASK_CARD_DRIFT", "schema version mismatch");
  assert(card.status === "QUALITY_FREEZE_CANDIDATE", "TASK_CARD_DRIFT", "freeze status mismatch");
  assert(card.freeze_effective_only_with_external_quality_receipt === true, "TASK_CARD_DRIFT", "receipt rule mismatch");
  assert(card.task_id === "AIOS-P1-055_FINITE_TYPED_PATCH_IR_COMPILER_CONFORMANCE", "TASK_CARD_DRIFT", "Task id mismatch");
  assert(card.finite_ir.schema === "SL-PATCH-IR/1", "TASK_CARD_DRIFT", "IR schema mismatch");
  assert(card.finite_ir.decode_or_parse_proposal === false, "TASK_CARD_DRIFT", "proposal interpretation drift");
  assert(sameJson(card.finite_ir.programs, PROGRAM_TABLE_INTERNAL.map(expectedCardProgram)), "TASK_CARD_DRIFT", "program table mismatch");
  assert(sameJson(card.finite_ir.outcomes, OUTCOME_TABLE_INTERNAL.map(expectedCardOutcome)), "TASK_CARD_DRIFT", "outcome table mismatch");
  assert(card.finite_ir.only_success_program_id === "IR10", "TASK_CARD_DRIFT", "success program mismatch");
  assert(sameJson(card.compiler_tcb.import_allowlist, ["node:crypto"]), "TASK_CARD_DRIFT", "compiler import allowlist drift");
  assert(Object.values(card.external_effects).every((value) => value === false), "TASK_CARD_DRIFT", "external effect enabled");

  const malformed = malformedPayloads();
  assert(card.explicit_malformed_payload_matrix.length === malformed.size, "TASK_CARD_DRIFT", "malformed matrix size mismatch");
  for (const declaration of card.explicit_malformed_payload_matrix) {
    const bytes = malformed.get(declaration.id);
    assert(Buffer.isBuffer(bytes), "TASK_CARD_DRIFT", `unknown malformed case ${declaration.id}`);
    assert(bytes.length === declaration.byte_length, "TASK_CARD_DRIFT", `${declaration.id} length mismatch`);
    assert(sha256(bytes) === declaration.sha256, "TASK_CARD_DRIFT", `${declaration.id} hash mismatch`);
    assert(admitExactProgram(bytes) === null, "TASK_CARD_DRIFT", `${declaration.id} unexpectedly admitted`);
  }

  const closure = computeByteClosureSummary();
  const scheduled = card.byte_closure.scheduled_counts;
  for (const key of [
    "substitution",
    "strict_truncation",
    "one_byte_prefix",
    "one_byte_suffix",
    "total",
    "legal_to_legal_transitions",
    "rejections",
    "false_accepts",
  ]) {
    assert(closure[key] === scheduled[key], "TASK_CARD_DRIFT", `byte closure ${key} mismatch`);
  }
  assert(closure.stream_sha256 === card.byte_closure.stream_sha256, "TASK_CARD_DRIFT", "byte closure digest mismatch");
  assert(BASE_POSTIMAGE.length === 115, "ORACLE_CONSTANT_INVALID", "base length drift");
  assert(
    sha256(BASE_POSTIMAGE) === "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75",
    "ORACLE_CONSTANT_INVALID",
    "base hash drift",
  );
  return freeze({
    status: "PASS",
    task_card_sha256: TASK_CARD_IDENTITY.sha256,
    program_count: PROGRAM_TABLE_INTERNAL.length,
    outcome_count: OUTCOME_TABLE_INTERNAL.length,
    byte_closure: closure,
  });
}

export function evaluateObservation(observation) {
  assert(observation && typeof observation === "object", "OBSERVATION_MISMATCH_REJECTED", "observation missing");
  assert(Number.isInteger(observation.program_length), "OBSERVATION_MISMATCH_REJECTED", "program length missing");
  assert(typeof observation.program_sha256 === "string", "OBSERVATION_MISMATCH_REJECTED", "program hash missing");
  const program = PROGRAM_BY_SHA.get(observation.program_sha256);
  assert(program && program.byte_length === observation.program_length, "OBSERVATION_MISMATCH_REJECTED", "program identity mismatch");
  assert(observation.program_id === program.id, "OBSERVATION_MISMATCH_REJECTED", "program id mismatch");
  const outcome = OUTCOME_BY_ID.get(program.outcome_id);
  assert(outcome && observation.outcome_id === outcome.outcome_id, "OUTCOME_BINDING_REJECTED", "outcome binding mismatch");
  assert(observation.outcome_kind === outcome.kind, "OUTCOME_BINDING_REJECTED", "outcome kind mismatch");
  assert(observation.canary_status === "UNCHANGED", "OBSERVATION_MISMATCH_REJECTED", "canary changed");
  assert(
    observation.external_effects && Object.values(observation.external_effects).every((value) => value === false),
    "OBSERVATION_MISMATCH_REJECTED",
    "external effect observed",
  );
  assert(observation.mutation_attempts === outcome.mutation_attempts, "OBSERVATION_MISMATCH_REJECTED", "mutation count mismatch");
  assert(observation.child_start_attempts === outcome.child_start_attempts, "OBSERVATION_MISMATCH_REJECTED", "child count mismatch");

  if (outcome.postimage === null) {
    assert(observation.postimage_bytes_or_null === null, "POSTIMAGE_IDENTITY_REJECTED", "identity outcome has postimage");
    assert(sameJson(observation.changed_paths, []), "OBSERVATION_MISMATCH_REJECTED", "identity outcome changed a path");
    assert(observation.test_statuses === null, "OBSERVATION_MISMATCH_REJECTED", "identity outcome started tests");
  } else {
    assert(Buffer.isBuffer(observation.postimage_bytes_or_null), "POSTIMAGE_IDENTITY_REJECTED", "postimage is not bytes");
    assert(observation.postimage_bytes_or_null.length === outcome.postimage_byte_length, "POSTIMAGE_IDENTITY_REJECTED", "postimage length mismatch");
    assert(sha256(observation.postimage_bytes_or_null) === outcome.postimage_sha256, "POSTIMAGE_IDENTITY_REJECTED", "postimage hash mismatch");
    assert(observation.postimage_bytes_or_null.equals(outcome.postimage), "POSTIMAGE_IDENTITY_REJECTED", "postimage bytes mismatch");
    assert(sameJson(observation.changed_paths, ["src/range.mjs"]), "OBSERVATION_MISMATCH_REJECTED", "changed paths mismatch");
    assert(
      observation.test_statuses?.issue === outcome.issue_exit_status &&
        observation.test_statuses?.regression === outcome.regression_exit_status,
      "OBSERVATION_MISMATCH_REJECTED",
      "test status mismatch",
    );
  }
  return freeze({
    program_id: program.id,
    admission: "ADMITTED_EXACT_LEGAL_PROGRAM",
    compiler_outcome: outcome.outcome_id,
    evaluator_verdict: outcome.evaluator_verdict,
    task_conformance: "EXPECTED_OUTCOME_CONFIRMED",
  });
}

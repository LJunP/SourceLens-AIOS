import {
  constants as fsConstants,
  existsSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
  closeSync,
} from "node:fs";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { isDeepStrictEqual } from "node:util";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { validate } from "../schema-validator.mjs";
import {
  QualityNonPass,
  verifyQualityFixtures,
} from "./quality-oracle.mjs";
import {
  validateReplayReceipt,
  validateRollbackReceipt,
} from "../../replay/p1-101-accepted-shared-trace/replay.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const FIXTURE_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-101-accepted-shared-trace",
);
const RUN_RECORD_SCHEMA = JSON.parse(readFileSync(
  join(REPOSITORY_ROOT, "docs/aios/schemas/run-record.schema.json"),
  "utf8",
));
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const REQUIRED_EVENTS = Object.freeze([
  "admission",
  "execution",
  "validation",
  "result",
  "rollback",
]);
const REQUIRED_BINDINGS = Object.freeze([
  "task_spec",
  "environment_snapshot",
  "system_configuration",
  "executable",
  "input",
  "output",
  "run_record",
]);
const STDOUT_KEYS = Object.freeze([
  "schema_version",
  "request_id",
  "case_id",
  "status",
  "reason_code",
  "target_execution_count",
  "admitted",
  "output_root_created",
  "run_record_ref",
  "trace_ref",
  "stable_projection_ref",
  "replay_receipt_ref",
  "rollback_receipt_ref",
  "external_effects",
  "cleanup",
]);
const REF_KEYS = Object.freeze(["path", "sha256", "byte_length"]);
const CLEANUP_KEYS = Object.freeze([
  "owned_paths_removed",
  "nonowned_paths_touched",
  "undeclared_executions",
]);
const DESCRIPTOR_BY_ADAPTER = Object.freeze({
  B0: "evaluation-harness/adapters/p1-097-minimal-documented/b0-descriptor.json",
  B1: "evaluation-harness/adapters/p1-097-minimal-documented/b1-descriptor.json",
  B2: "evaluation-harness/adapters/p1-097-minimal-documented/b2-descriptor.json",
});
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;

function fail(reason, detail = "") {
  throw new QualityNonPass(reason, detail);
}

function assert(condition, reason, detail = "") {
  if (!condition) fail(reason, detail);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]),
    );
  }
  return value;
}

function canonicalBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalValue(value))}\n`, "utf8");
}

function exactKeys(value, keys, reason, detail = "") {
  assert(value && typeof value === "object" && !Array.isArray(value), reason, detail);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  assert(
    actual.length === expected.length && actual.every((key, index) => key === expected[index]),
    reason,
    detail || `keys=${actual.join(",")}`,
  );
}

function assertContained(root, candidate, reason) {
  const rootAbsolute = resolve(root);
  const candidateAbsolute = resolve(candidate);
  const rel = relative(rootAbsolute, candidateAbsolute);
  assert(
    rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel)),
    reason,
    candidateAbsolute,
  );
  return candidateAbsolute;
}

function assertNoSymlinkComponents(root, candidate, reason) {
  const rootAbsolute = resolve(root);
  const candidateAbsolute = assertContained(rootAbsolute, candidate, reason);
  const rel = relative(rootAbsolute, candidateAbsolute);
  let cursor = rootAbsolute;
  const rootStat = lstatSync(cursor);
  assert(!rootStat.isSymbolicLink(), reason, cursor);
  if (rel === "") return candidateAbsolute;
  for (const component of rel.split(sep)) {
    cursor = join(cursor, component);
    const stat = lstatSync(cursor);
    assert(!stat.isSymbolicLink(), reason, cursor);
  }
  return candidateAbsolute;
}

function createOwnedRoot(path) {
  assert(isAbsolute(path) && resolve(path) === path, "OUTPUT_ROOT_INVALID", path);
  assert(!existsSync(path), "OUTPUT_ROOT_PREEXISTS", path);
  const parent = dirname(path);
  const parentStat = lstatSync(parent);
  assert(
    parentStat.isDirectory() &&
      !parentStat.isSymbolicLink() &&
      realpathSync(parent) === parent,
    "OUTPUT_PARENT_INVALID",
    parent,
  );
  mkdirSync(path, { mode: 0o700, recursive: false });
  const stat = lstatSync(path);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), "OUTPUT_ROOT_INVALID", path);
}

function createDirectory(path, ownedRoot) {
  assertContained(ownedRoot, path, "QUALITY_PATH_ESCAPE");
  assert(!existsSync(path), "QUALITY_PATH_PREEXISTS", path);
  mkdirSync(path, { mode: 0o700, recursive: false });
}

function writeJsonCreateOnce(path, value, ownedRoot) {
  assertContained(ownedRoot, path, "QUALITY_PATH_ESCAPE");
  const fd = openSync(
    path,
    fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | O_NOFOLLOW,
    0o600,
  );
  try {
    writeFileSync(fd, canonicalBytes(value));
  } finally {
    closeSync(fd);
  }
}

function bound(path) {
  const bytes = readFileSync(path);
  return {
    path,
    sha256: sha256(bytes),
    byte_length: bytes.length,
  };
}

function drifted(reference) {
  return {
    ...reference,
    sha256: `${reference.sha256[0] === "0" ? "1" : "0"}${reference.sha256.slice(1)}`,
  };
}

function validationInputs(adapterId, configurationPath, mutationType) {
  const descriptorPath = join(REPOSITORY_ROOT, DESCRIPTOR_BY_ADAPTER[adapterId]);
  const descriptor = JSON.parse(readFileSync(descriptorPath, "utf8"));
  const exact = {
    task_spec: bound(join(
      REPOSITORY_ROOT,
      "evaluation-harness/fixtures/p1-097-minimal-documented/task-spec.json",
    )),
    environment_snapshot: bound(join(
      REPOSITORY_ROOT,
      "evaluation-harness/fixtures/p1-097-minimal-documented/environment-snapshot.json",
    )),
    system_configuration: bound(configurationPath),
    executable: bound(resolve(REPOSITORY_ROOT, descriptor.executable.path)),
    input: bound(resolve(REPOSITORY_ROOT, descriptor.input_bindings.adapter_input.path)),
  };
  const targetByMutation = {
    TASK_SPEC_IDENTITY_DRIFT: "task_spec",
    ENVIRONMENT_IDENTITY_DRIFT: "environment_snapshot",
    SYSTEM_CONFIGURATION_IDENTITY_DRIFT: "system_configuration",
    EXECUTABLE_IDENTITY_DRIFT: "executable",
    INPUT_IDENTITY_DRIFT: "input",
  };
  const target = targetByMutation[mutationType];
  if (target) exact[target] = drifted(exact[target]);
  return exact;
}

function verifySubmittedMutation(request, catalogEntry) {
  const exact = validationInputs(
    request.adapter_id,
    request.accepted_system_configuration.path,
    null,
  );
  exactKeys(
    request.validation_inputs,
    ["task_spec", "environment_snapshot", "system_configuration", "executable", "input"],
    "VALIDATION_INPUT_INVALID",
    request.case_id,
  );
  const targetByMutation = {
    TASK_SPEC_IDENTITY_DRIFT: "task_spec",
    ENVIRONMENT_IDENTITY_DRIFT: "environment_snapshot",
    SYSTEM_CONFIGURATION_IDENTITY_DRIFT: "system_configuration",
    EXECUTABLE_IDENTITY_DRIFT: "executable",
    INPUT_IDENTITY_DRIFT: "input",
  };
  const target = targetByMutation[catalogEntry.mutation] ?? null;
  for (const name of Object.keys(exact)) {
    exactKeys(request.validation_inputs[name], REF_KEYS, "VALIDATION_INPUT_INVALID", `${request.case_id}:${name}`);
    if (name === target) {
      assert(
        request.validation_inputs[name].path === exact[name].path &&
          request.validation_inputs[name].byte_length === exact[name].byte_length &&
          request.validation_inputs[name].sha256 !== exact[name].sha256,
        "VALIDATION_INPUT_DRIFT_MISSING",
        `${request.case_id}:${name}`,
      );
    } else {
      assert(
        isDeepStrictEqual(request.validation_inputs[name], exact[name]),
        "VALIDATION_INPUT_UNDECLARED_DRIFT",
        `${request.case_id}:${name}`,
      );
    }
  }
  const trueEffects = Object.entries(request.requested_effects)
    .filter(([, enabled]) => enabled)
    .map(([name]) => name);
  if (catalogEntry.mutation.startsWith("REQUEST_EFFECT_")) {
    const expectedEffect = catalogEntry.mutation.slice("REQUEST_EFFECT_".length).toLowerCase();
    assert(
      target === null &&
        trueEffects.length === 1 &&
        trueEffects[0] === expectedEffect,
      "EXTERNAL_EFFECT_MUTATION_INVALID",
      request.case_id,
    );
  } else {
    assert(trueEffects.length === 0, "EXTERNAL_EFFECT_MUTATION_INVALID", request.case_id);
  }
  if (catalogEntry.stage === "POST_EXECUTION") {
    assert(target === null, "VALIDATION_INPUT_UNDECLARED_DRIFT", request.case_id);
  }
}

function parseJson(bytes, reason, detail = "") {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(reason, detail ? `${detail}: ${error.message}` : error.message);
  }
}

function resolveArtifact(root, reference, expectedPath, reason) {
  exactKeys(reference, REF_KEYS, reason);
  assert(
    typeof reference.path === "string" &&
      reference.path === expectedPath &&
      !isAbsolute(reference.path),
    reason,
    reference.path,
  );
  const path = join(root, reference.path);
  assert(existsSync(path), reason, reference.path);
  assertNoSymlinkComponents(root, path, reason);
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink(), reason, reference.path);
  const bytes = readFileSync(path);
  assert(
    reference.byte_length === bytes.length &&
      reference.sha256 === sha256(bytes),
    reason,
    reference.path,
  );
  return { path, bytes, reference };
}

function runWorker(workerEntry, requestPath, outputRoot) {
  const result = spawnSync(
    process.execPath,
    [workerEntry, "--request", requestPath, "--output-root", outputRoot],
    {
      cwd: REPOSITORY_ROOT,
      encoding: null,
      timeout: 360_000,
      maxBuffer: 16 * 1024 * 1024,
      env: {
        HOME: process.env.HOME,
        LC_ALL: "C",
        TZ: "UTC",
        PATH: "/usr/local/bin:/usr/bin:/bin",
      },
    },
  );
  assert(!result.error, "WORKER_INVOCATION_FAILED", result.error?.message ?? "");
  const stderr = result.stderr ?? Buffer.alloc(0);
  assert(stderr.length === 0, "WORKER_STDERR_NONEMPTY", stderr.toString("utf8"));
  const stdout = result.stdout ?? Buffer.alloc(0);
  const text = stdout.toString("utf8");
  assert(
    text.endsWith("\n") &&
      !text.endsWith("\n\n") &&
      text.trim().split("\n").length === 1,
    "WORKER_STDOUT_INVALID",
  );
  const value = parseJson(stdout, "WORKER_STDOUT_INVALID");
  assert(stdout.equals(canonicalBytes(value)), "WORKER_STDOUT_NOT_CANONICAL");
  exactKeys(value, STDOUT_KEYS, "WORKER_STDOUT_INVALID");
  exactKeys(value.external_effects, Object.keys(FALSE_EFFECTS), "WORKER_EXTERNAL_EFFECTS_INVALID");
  assert(isDeepStrictEqual(value.external_effects, FALSE_EFFECTS), "WORKER_EXTERNAL_EFFECTS_INVALID");
  exactKeys(value.cleanup, CLEANUP_KEYS, "WORKER_CLEANUP_INVALID");
  assert(
    Object.values(value.cleanup).every((count) => Number.isInteger(count) && count >= 0) &&
      value.cleanup.nonowned_paths_touched === 0 &&
      value.cleanup.undeclared_executions === 0,
    "WORKER_CLEANUP_INVALID",
  );
  return {
    exitCode: result.status,
    value,
    stdout,
  };
}

function baseRequest({
  caseId,
  adapterId,
  repetitionId,
  configuration,
  outputRoot,
  mode,
  mutation,
  preExecution,
}) {
  const effects = { ...FALSE_EFFECTS };
  if (mutation?.type?.startsWith("REQUEST_EFFECT_")) {
    const effect = mutation.type.slice("REQUEST_EFFECT_".length).toLowerCase();
    assert(Object.hasOwn(effects, effect), "NEGATIVE_CATALOG_INVALID", mutation.type);
    effects[effect] = true;
  }
  const configurationPath = join(REPOSITORY_ROOT, configuration);
  return {
    schema_version: "p1-101-quality-request/v1",
    request_id: `P1-101-${caseId}-${randomBytes(8).toString("hex")}`,
    case_id: caseId,
    mode,
    adapter_id: adapterId,
    repetition_id: repetitionId,
    accepted_system_configuration: bound(configurationPath),
    validation_inputs: validationInputs(adapterId, configurationPath, mutation?.type),
    mutation,
    requested_effects: effects,
    expected_outcome: {
      status: mode === "POSITIVE" ? "PASS" : "REJECTED",
      pre_execution: preExecution,
      target_execution_count: mode === "POSITIVE" || !preExecution ? 1 : 0,
    },
    output_root: outputRoot,
  };
}

function verifyIdentityRecord(value, reason, detail = "") {
  assert(value && typeof value === "object" && !Array.isArray(value), reason, detail);
  assert(
    typeof value.sha256 === "string" &&
      /^[0-9a-f]{64}$/.test(value.sha256) &&
      Number.isInteger(value.byte_length) &&
      value.byte_length >= 0,
    reason,
    detail,
  );
}

function verifyTrace(traceArtifact, runRecord, request) {
  let events;
  try {
    const text = traceArtifact.bytes.toString("utf8");
    assert(text.endsWith("\n") && !text.endsWith("\n\n"), "TRACE_INVALID");
    events = text.trim().split("\n").map((line) => JSON.parse(line));
  } catch (error) {
    if (error instanceof QualityNonPass) throw error;
    fail("TRACE_INVALID", error.message);
  }
  assert(events.length === 5, "TRACE_EVENT_SEQUENCE_INVALID");
  assert(
    events.every((event, index) =>
      event.event_sequence === index + 1 &&
      event.event_type === REQUIRED_EVENTS[index] &&
      event.run_id === runRecord.run_id),
    "TRACE_EVENT_SEQUENCE_INVALID",
  );
  const observedBindings = new Map();
  for (const event of events) {
    assert(
      event.identity_bindings &&
        typeof event.identity_bindings === "object" &&
        !Array.isArray(event.identity_bindings),
      "TRACE_BINDING_INVALID",
      event.event_type,
    );
    for (const [name, identity] of Object.entries(event.identity_bindings)) {
      verifyIdentityRecord(identity, "TRACE_BINDING_INVALID", `${event.event_type}:${name}`);
      if (observedBindings.has(name)) {
        assert(
          isDeepStrictEqual(observedBindings.get(name), identity),
          "TRACE_BINDING_DRIFT",
          name,
        );
      } else {
        observedBindings.set(name, identity);
      }
    }
  }
  assert(
    REQUIRED_BINDINGS.every((name) => observedBindings.has(name)),
    "TRACE_BINDING_INCOMPLETE",
    [...observedBindings.keys()].join(","),
  );
  const execution = events[1];
  if (request.adapter_id === "B2") {
    assert(
      execution.accepted_child &&
        execution.accepted_child.operation_id === "repository_analysis.scan" &&
        execution.accepted_child.adapter_id === "B2" &&
        execution.accepted_child.real_invocation === true,
      "B2_REAL_CHILD_MISSING",
    );
    verifyIdentityRecord(
      execution.accepted_child.identity,
      "B2_REAL_CHILD_MISSING",
      request.case_id,
    );
  }
  return events;
}

function verifyNegativeMutationEvidence(workerOutput, catalogEntry, request) {
  const sourcePath = join(workerOutput, "negative-source-input.bin");
  const mutatedPath = join(workerOutput, "negative-validation-input.bin");
  const receiptPath = join(workerOutput, "negative-validation-receipt.json");
  for (const path of [sourcePath, mutatedPath, receiptPath]) {
    assert(existsSync(path), "NEGATIVE_VALIDATION_EVIDENCE_MISSING", `${catalogEntry.case_id}:${path}`);
    assertNoSymlinkComponents(workerOutput, path, "NEGATIVE_VALIDATION_EVIDENCE_INVALID");
    const stat = lstatSync(path);
    assert(stat.isFile() && !stat.isSymbolicLink(), "NEGATIVE_VALIDATION_EVIDENCE_INVALID", path);
  }
  const sourceBytes = readFileSync(sourcePath);
  const mutatedBytes = readFileSync(mutatedPath);
  const receipt = parseJson(
    readFileSync(receiptPath),
    "NEGATIVE_VALIDATION_EVIDENCE_INVALID",
    catalogEntry.case_id,
  );
  exactKeys(receipt, [
    "schema_version",
    "record_type",
    "mutation_type",
    "source_identity",
    "mutated_identity",
    "observed_reason",
    "validator_invoked",
    "admitted",
    "external_effects",
  ], "NEGATIVE_VALIDATION_EVIDENCE_INVALID", catalogEntry.case_id);
  exactKeys(receipt.source_identity, REF_KEYS, "NEGATIVE_VALIDATION_EVIDENCE_INVALID");
  exactKeys(receipt.mutated_identity, REF_KEYS, "NEGATIVE_VALIDATION_EVIDENCE_INVALID");
  assert(
    receipt.schema_version === "p1-101-negative-validation-receipt/v1" &&
      receipt.record_type === "p1_101_negative_validation_receipt" &&
      receipt.mutation_type === catalogEntry.mutation &&
      receipt.observed_reason === catalogEntry.reason_code &&
      receipt.validator_invoked === true &&
      receipt.admitted === false &&
      receipt.source_identity.path === "negative-source-input.bin" &&
      receipt.source_identity.sha256 === sha256(sourceBytes) &&
      receipt.source_identity.byte_length === sourceBytes.length &&
      receipt.mutated_identity.path === "negative-validation-input.bin" &&
      receipt.mutated_identity.sha256 === sha256(mutatedBytes) &&
      receipt.mutated_identity.byte_length === mutatedBytes.length &&
      isDeepStrictEqual(receipt.external_effects, FALSE_EFFECTS) &&
      !sourceBytes.equals(mutatedBytes),
    "NEGATIVE_VALIDATION_EVIDENCE_INVALID",
    catalogEntry.case_id,
  );
  const source = parseJson(
    sourceBytes,
    "NEGATIVE_SOURCE_INPUT_INVALID",
    catalogEntry.case_id,
  );
  const mutated = parseJson(
    mutatedBytes,
    "NEGATIVE_MUTATED_INPUT_INVALID",
    catalogEntry.case_id,
  );
  if (catalogEntry.stage === "PRE_EXECUTION") {
    exactKeys(
      source,
      ["schema_version", "validation_inputs", "requested_effects"],
      "NEGATIVE_SOURCE_INPUT_INVALID",
      catalogEntry.case_id,
    );
    exactKeys(
      mutated,
      ["schema_version", "validation_inputs", "requested_effects"],
      "NEGATIVE_MUTATED_INPUT_INVALID",
      catalogEntry.case_id,
    );
    const exact = validationInputs(
      request.adapter_id,
      request.accepted_system_configuration.path,
      null,
    );
    assert(
      source.schema_version === "p1-101-preexecution-validation-input/v1" &&
        mutated.schema_version === source.schema_version &&
        isDeepStrictEqual(source.validation_inputs, exact) &&
        isDeepStrictEqual(source.requested_effects, FALSE_EFFECTS) &&
        isDeepStrictEqual(mutated.validation_inputs, request.validation_inputs) &&
        isDeepStrictEqual(mutated.requested_effects, request.requested_effects),
      "NEGATIVE_PREEXECUTION_EVIDENCE_INVALID",
      catalogEntry.case_id,
    );
    return {
      source_sha256: sha256(sourceBytes),
      mutated_sha256: sha256(mutatedBytes),
      receipt_sha256: sha256(readFileSync(receiptPath)),
    };
  }
  exactKeys(source, [
    "schema_version",
    "trace_events",
    "output_identity",
    "run_record_identity",
    "child_invocations",
    "output_inventory",
  ], "NEGATIVE_SOURCE_INPUT_INVALID", catalogEntry.case_id);
  exactKeys(mutated, [
    "schema_version",
    "trace_events",
    "output_identity",
    "run_record_identity",
    "child_invocations",
    "output_inventory",
  ], "NEGATIVE_MUTATED_INPUT_INVALID", catalogEntry.case_id);
  assert(
    source.schema_version === "p1-101-admission-validation-input/v1" &&
      mutated.schema_version === source.schema_version &&
      Array.isArray(source.trace_events) &&
      source.trace_events.length === 5 &&
      source.trace_events.every((event, index) =>
        event.event_sequence === index + 1 &&
        event.event_type === REQUIRED_EVENTS[index]) &&
      Array.isArray(source.child_invocations) &&
      Array.isArray(source.output_inventory),
    "NEGATIVE_SOURCE_INPUT_INVALID",
    catalogEntry.case_id,
  );
  const targetByMutation = {
    TAMPER_EVENT_BYTES: "trace_events",
    REMOVE_REQUIRED_EVENT: "trace_events",
    REORDER_EVENTS: "trace_events",
    OUTPUT_IDENTITY_DRIFT: "output_identity",
    RUN_RECORD_IDENTITY_DRIFT: "run_record_identity",
    CHILD_IDENTITY_DRIFT: "child_invocations",
    ADD_UNEXPECTED_OUTPUT: "output_inventory",
    ADD_UNDECLARED_CHILD: "child_invocations",
  };
  const target = targetByMutation[catalogEntry.mutation];
  assert(typeof target === "string", "NEGATIVE_MUTATION_UNKNOWN", catalogEntry.mutation);
  for (const key of [
    "output_identity",
    "run_record_identity",
    "child_invocations",
    "output_inventory",
    "trace_events",
  ]) {
    if (key !== target) {
      assert(
        isDeepStrictEqual(mutated[key], source[key]),
        "NEGATIVE_MUTATION_UNDECLARED_DRIFT",
        `${catalogEntry.case_id}:${key}`,
      );
    }
  }
  switch (catalogEntry.mutation) {
    case "TAMPER_EVENT_BYTES":
      assert(
        Array.isArray(mutated.trace_events) &&
          !isDeepStrictEqual(mutated.trace_events, source.trace_events),
        "NEGATIVE_MUTATION_NOT_MATERIALIZED",
        catalogEntry.case_id,
      );
      break;
    case "REMOVE_REQUIRED_EVENT":
      assert(mutated.trace_events.length === 4, "NEGATIVE_MUTATION_NOT_MATERIALIZED", catalogEntry.case_id);
      break;
    case "REORDER_EVENTS":
      assert(
        mutated.trace_events.length === 5 &&
          !isDeepStrictEqual(mutated.trace_events.map((event) => event.event_type), REQUIRED_EVENTS),
        "NEGATIVE_MUTATION_NOT_MATERIALIZED",
        catalogEntry.case_id,
      );
      break;
    case "OUTPUT_IDENTITY_DRIFT":
      assert(
        mutated.output_identity.sha256 !== source.output_identity.sha256,
        "NEGATIVE_MUTATION_NOT_MATERIALIZED",
        catalogEntry.case_id,
      );
      break;
    case "RUN_RECORD_IDENTITY_DRIFT":
      assert(
        mutated.run_record_identity.sha256 !== source.run_record_identity.sha256,
        "NEGATIVE_MUTATION_NOT_MATERIALIZED",
        catalogEntry.case_id,
      );
      break;
    case "CHILD_IDENTITY_DRIFT":
      assert(
        mutated.child_invocations.length === source.child_invocations.length &&
          mutated.child_invocations.some((child, index) =>
            child.operation_id !== source.child_invocations[index]?.operation_id) &&
          !isDeepStrictEqual(mutated.child_invocations, source.child_invocations),
        "NEGATIVE_MUTATION_NOT_MATERIALIZED",
        catalogEntry.case_id,
      );
      break;
    case "ADD_UNEXPECTED_OUTPUT":
      assert(
        mutated.output_inventory.length === source.output_inventory.length + 1,
        "NEGATIVE_MUTATION_NOT_MATERIALIZED",
        catalogEntry.case_id,
      );
      break;
    case "ADD_UNDECLARED_CHILD":
      assert(
        mutated.child_invocations.length === source.child_invocations.length + 1,
        "NEGATIVE_MUTATION_NOT_MATERIALIZED",
        catalogEntry.case_id,
      );
      break;
    default:
      fail("NEGATIVE_MUTATION_UNKNOWN", catalogEntry.mutation);
  }
  return {
    source_sha256: sha256(sourceBytes),
    mutated_sha256: sha256(mutatedBytes),
    receipt_sha256: sha256(readFileSync(receiptPath)),
  };
}

function regularFileInventory(root) {
  const walk = (directory) => readdirSync(directory, { withFileTypes: true })
    .flatMap((entry) => {
      const path = join(directory, entry.name);
      const rel = relative(root, path).split(sep).join("/");
      const stat = lstatSync(path);
      assert(!stat.isSymbolicLink(), "ROLLBACK_FINAL_STATE_INVALID", rel);
      if (entry.isDirectory()) return walk(path);
      assert(entry.isFile(), "ROLLBACK_FINAL_STATE_INVALID", rel);
      const bytes = readFileSync(path);
      return [{ path: rel, sha256: sha256(bytes), byte_length: bytes.length }];
    });
  return walk(root).sort((left, right) => Buffer.compare(
    Buffer.from(left.path),
    Buffer.from(right.path),
  ));
}

function verifyActualRollbackState(workerOutput, adapterId) {
  const adapterResultPath = join(workerOutput, "accepted-run/adapter-result.json");
  assert(existsSync(adapterResultPath), "ROLLBACK_FINAL_STATE_INVALID", adapterId);
  const adapterResult = parseJson(
    readFileSync(adapterResultPath),
    "ROLLBACK_FINAL_STATE_INVALID",
    adapterId,
  );
  assert(
    adapterResult.adapter_id === adapterId &&
      adapterResult.source_mutation_observed === false,
    "ROLLBACK_FINAL_STATE_INVALID",
    adapterId,
  );
  if (adapterId === "B0") {
    assert(
      adapterResult.rollback.status === "NOT_APPLICABLE_NO_SOURCE_MUTATION",
      "ROLLBACK_FINAL_STATE_INVALID",
      adapterId,
    );
    const emptyManifest = [];
    return {
      kind: "NO_SOURCE_MUTATION",
      source_root: null,
      entry_count: 0,
      manifest_sha256: sha256(canonicalBytes(emptyManifest)),
    };
  }
  const relativeSourceRoot = adapterId === "B1"
    ? "accepted-run/work/b1-disposable-source"
    : "accepted-run/work/b2-scan-source";
  const sourceRoot = join(workerOutput, relativeSourceRoot);
  assert(existsSync(sourceRoot), "ROLLBACK_FINAL_STATE_INVALID", relativeSourceRoot);
  assertNoSymlinkComponents(workerOutput, sourceRoot, "ROLLBACK_FINAL_STATE_INVALID");
  const actualInventory = regularFileInventory(sourceRoot);
  const canonicalSourceRoot = join(
    REPOSITORY_ROOT,
    "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template",
  );
  const expectedInventory = regularFileInventory(canonicalSourceRoot);
  assert(
    isDeepStrictEqual(actualInventory, expectedInventory),
    "ROLLBACK_FINAL_STATE_INVALID",
    adapterId,
  );
  if (adapterId === "B1") {
    assert(
      adapterResult.rollback.status === "PASS_EXACT" &&
        adapterResult.rollback.files.every((entry) => entry.matches === true),
      "ROLLBACK_FINAL_STATE_INVALID",
      adapterId,
    );
  } else {
    assert(
      adapterResult.rollback.status === "NOT_APPLICABLE_READ_ONLY_SCAN_SOURCE_UNCHANGED" &&
        adapterResult.rollback.source_exact_after_scan === true,
      "ROLLBACK_FINAL_STATE_INVALID",
      adapterId,
    );
  }
  return {
    kind: "DISPOSABLE_SOURCE_EXACT",
    source_root: relativeSourceRoot,
    entry_count: actualInventory.length,
    manifest_sha256: sha256(canonicalBytes(actualInventory)),
  };
}

function tamperedBytes(bytes) {
  const copy = Buffer.from(bytes);
  assert(copy.length > 0, "REPLAY_TAMPER_FIXTURE_INVALID");
  copy[Math.floor(copy.length / 2)] ^= 0x01;
  return copy;
}

function assertRejectCode(callback, expectedCode, reason) {
  let observed = null;
  try {
    callback();
  } catch (error) {
    observed = error?.code ?? null;
  }
  assert(observed === expectedCode, reason, `expected=${expectedCode} observed=${observed}`);
}

function verifyReceipts({
  traceArtifact,
  projectionArtifact,
  replayArtifact,
  rollbackArtifact,
  runRecordArtifact,
  runRecord,
  events,
  workerOutput,
  adapterId,
}) {
  const projection = parseJson(projectionArtifact.bytes, "STABLE_PROJECTION_INVALID");
  const replay = parseJson(replayArtifact.bytes, "REPLAY_RECEIPT_INVALID");
  const rollback = parseJson(rollbackArtifact.bytes, "ROLLBACK_RECEIPT_INVALID");
  exactKeys(projection, [
    "schema_version",
    "record_type",
    "task_id",
    "dataset_version",
    "adapter_id",
    "adapter_version",
    "environment_snapshot_id",
    "event_order",
    "deterministic_bindings",
    "accepted_projection",
    "child_operations",
    "external_effects",
  ], "STABLE_PROJECTION_INVALID");
  const underlyingProjection = parseJson(
    readFileSync(join(workerOutput, "accepted-run/stable-projection.json")),
    "STABLE_PROJECTION_INVALID",
  );
  const traceBindings = events[0].identity_bindings;
  const expectedDeterministicBindings = {
    task_spec: traceBindings.task_spec,
    environment_snapshot: traceBindings.environment_snapshot,
    executable: traceBindings.executable,
    input: traceBindings.input,
  };
  assert(
    projection.schema_version === "p1-101-stable-projection/v1" &&
      projection.record_type === "p1_101_accepted_shared_execution_stable_projection" &&
      projection.task_id === runRecord.task_id &&
      projection.dataset_version === runRecord.dataset_version &&
      projection.adapter_id === adapterId &&
      projection.adapter_version === runRecord.adapter_version &&
      projection.environment_snapshot_id === runRecord.environment_snapshot_id &&
      isDeepStrictEqual(projection.event_order, REQUIRED_EVENTS) &&
      isDeepStrictEqual(projection.deterministic_bindings, expectedDeterministicBindings) &&
      isDeepStrictEqual(projection.accepted_projection, underlyingProjection) &&
      isDeepStrictEqual(projection.external_effects, FALSE_EFFECTS),
    "STABLE_PROJECTION_INVALID",
    adapterId,
  );
  const expectedChildOperations = events[1].event_data.child_operations.map((operation) => ({
    sequence: operation.sequence,
    tool_class: operation.tool_class,
    operation_id: operation.operation_id,
    exit_code: operation.exit_code,
  }));
  assert(
    isDeepStrictEqual(projection.child_operations, expectedChildOperations),
    "STABLE_PROJECTION_INVALID",
    `${adapterId}:child_operations`,
  );
  validateReplayReceipt({
    traceBytes: traceArtifact.bytes,
    projectionBytes: projectionArtifact.bytes,
    runRecordBytes: runRecordArtifact.bytes,
    receipt: replay,
  });
  assertRejectCode(
    () => validateReplayReceipt({
      traceBytes: tamperedBytes(traceArtifact.bytes),
      projectionBytes: projectionArtifact.bytes,
      runRecordBytes: runRecordArtifact.bytes,
      receipt: replay,
    }),
    "TRACE_EVENT_IDENTITY_MISMATCH",
    "REPLAY_TRACE_DRIFT_NOT_REJECTED",
  );
  assertRejectCode(
    () => validateReplayReceipt({
      traceBytes: traceArtifact.bytes,
      projectionBytes: tamperedBytes(projectionArtifact.bytes),
      runRecordBytes: runRecordArtifact.bytes,
      receipt: replay,
    }),
    "OUTPUT_IDENTITY_MISMATCH",
    "REPLAY_PROJECTION_DRIFT_NOT_REJECTED",
  );
  assertRejectCode(
    () => validateReplayReceipt({
      traceBytes: traceArtifact.bytes,
      projectionBytes: projectionArtifact.bytes,
      runRecordBytes: tamperedBytes(runRecordArtifact.bytes),
      receipt: replay,
    }),
    "RUN_RECORD_IDENTITY_MISMATCH",
    "REPLAY_RUN_RECORD_DRIFT_NOT_REJECTED",
  );
  const actualCleanStateIdentity = verifyActualRollbackState(workerOutput, adapterId);
  assert(
    isDeepStrictEqual(rollback.clean_state_identity, actualCleanStateIdentity),
    "ROLLBACK_CLEAN_IDENTITY_MISMATCH",
    adapterId,
  );
  validateRollbackReceipt({
    receipt: rollback,
    runRecordBytes: runRecordArtifact.bytes,
    cleanStateIdentity: actualCleanStateIdentity,
  });
  assertRejectCode(
    () => validateRollbackReceipt({
      receipt: rollback,
      runRecordBytes: runRecordArtifact.bytes,
      cleanStateIdentity: {
        ...actualCleanStateIdentity,
        manifest_sha256: "0".repeat(64),
      },
    }),
    "ROLLBACK_STATE_IDENTITY_MISMATCH",
    "ROLLBACK_STATE_DRIFT_NOT_REJECTED",
  );
  return {
    projection,
    replay,
    rollback,
    replay_drift_rejections: 3,
    rollback_state_drift_rejections: 1,
    clean_state_identity: actualCleanStateIdentity,
  };
}

function verifyPositive(workerResult, request, workerOutput) {
  const value = workerResult.value;
  assert(
    workerResult.exitCode === 0 &&
      value.schema_version === "p1-101-quality-result/v1" &&
      value.request_id === request.request_id &&
      value.case_id === request.case_id &&
      value.status === "PASS" &&
      value.reason_code === "PASS" &&
      value.target_execution_count === 1 &&
      value.admitted === true &&
      value.output_root_created === true,
    "POSITIVE_RESULT_INVALID",
    request.case_id,
  );
  assert(existsSync(workerOutput), "POSITIVE_OUTPUT_MISSING", request.case_id);
  const runRecordArtifact = resolveArtifact(
    workerOutput,
    value.run_record_ref,
    "accepted-run/run-record.json",
    "RUN_RECORD_IDENTITY_INVALID",
  );
  const traceArtifact = resolveArtifact(
    workerOutput,
    value.trace_ref,
    "observable-trace.jsonl",
    "TRACE_IDENTITY_INVALID",
  );
  const projectionArtifact = resolveArtifact(
    workerOutput,
    value.stable_projection_ref,
    "stable-projection.json",
    "STABLE_PROJECTION_IDENTITY_INVALID",
  );
  const replayArtifact = resolveArtifact(
    workerOutput,
    value.replay_receipt_ref,
    "replay-receipt.json",
    "REPLAY_RECEIPT_IDENTITY_INVALID",
  );
  const rollbackArtifact = resolveArtifact(
    workerOutput,
    value.rollback_receipt_ref,
    "rollback-receipt.json",
    "ROLLBACK_RECEIPT_IDENTITY_INVALID",
  );
  const runRecord = parseJson(runRecordArtifact.bytes, "RUN_RECORD_INVALID");
  const schemaErrors = validate(runRecord, RUN_RECORD_SCHEMA);
  assert(schemaErrors.length === 0, "RUN_RECORD_INVALID", schemaErrors.join("; "));
  const configuration = parseJson(
    readFileSync(request.accepted_system_configuration.path),
    "SYSTEM_CONFIGURATION_INVALID",
  );
  assert(
    runRecord.adapter_id === request.adapter_id &&
      runRecord.repetition_id === request.repetition_id &&
      runRecord.system_configuration_id === configuration.configuration_id &&
      runRecord.terminal_status === "completed" &&
      runRecord.stop_reason_code === "agent_complete" &&
      runRecord.policy_violations.length === 0,
    "RUN_RECORD_BINDING_INVALID",
    request.case_id,
  );
  const events = verifyTrace(traceArtifact, runRecord, request);
  const receipts = verifyReceipts({
    traceArtifact,
    projectionArtifact,
    replayArtifact,
    rollbackArtifact,
    runRecordArtifact,
    runRecord,
    events,
    workerOutput,
    adapterId: request.adapter_id,
  });
  return {
    request,
    workerResult,
    workerOutput,
    runRecord,
    events,
    traceArtifact,
    projectionArtifact,
    replayArtifact,
    rollbackArtifact,
    ...receipts,
  };
}

function verifyNegative(workerResult, request, workerOutput, catalogEntry) {
  const value = workerResult.value;
  const expectedCount = catalogEntry.stage === "PRE_EXECUTION" ? 0 : 1;
  const falseAccept = workerResult.exitCode === 0 || value.status === "PASS" || value.admitted === true;
  assert(
    !falseAccept &&
      workerResult.exitCode === 2 &&
      value.schema_version === "p1-101-quality-result/v1" &&
      value.request_id === request.request_id &&
      value.case_id === request.case_id &&
      value.status === "REJECTED" &&
      value.reason_code === catalogEntry.reason_code &&
      value.target_execution_count === expectedCount &&
      value.admitted === false,
    "NEGATIVE_RESULT_INVALID",
    request.case_id,
  );
  assert(
    value.run_record_ref === null &&
      value.trace_ref === null &&
      value.stable_projection_ref === null &&
      value.replay_receipt_ref === null &&
      value.rollback_receipt_ref === null,
    "NEGATIVE_ADMISSION_ARTIFACT_LEAK",
    request.case_id,
  );
  if (existsSync(workerOutput)) {
    const stat = lstatSync(workerOutput);
    assert(stat.isDirectory() && !stat.isSymbolicLink(), "NEGATIVE_OUTPUT_INVALID", request.case_id);
    assert(realpathSync(workerOutput) === workerOutput, "NEGATIVE_OUTPUT_INVALID", request.case_id);
  }
  const acceptedRunRecordPath = join(workerOutput, "accepted-run/run-record.json");
  let acceptedRunId = null;
  if (catalogEntry.stage === "PRE_EXECUTION") {
    assert(
      !existsSync(acceptedRunRecordPath),
      "PRE_EXECUTION_TARGET_EXECUTED",
      request.case_id,
    );
  } else {
    assert(
      existsSync(acceptedRunRecordPath),
      "POST_EXECUTION_ACCEPTED_RUN_EVIDENCE_MISSING",
      request.case_id,
    );
    assertNoSymlinkComponents(workerOutput, acceptedRunRecordPath, "POST_EXECUTION_ACCEPTED_RUN_EVIDENCE_INVALID");
    const acceptedRunRecordBytes = readFileSync(acceptedRunRecordPath);
    const acceptedRunRecord = parseJson(
      acceptedRunRecordBytes,
      "POST_EXECUTION_ACCEPTED_RUN_EVIDENCE_INVALID",
      request.case_id,
    );
    const schemaErrors = validate(acceptedRunRecord, RUN_RECORD_SCHEMA);
    assert(
      schemaErrors.length === 0 &&
        acceptedRunRecord.adapter_id === request.adapter_id &&
        acceptedRunRecord.repetition_id === request.repetition_id &&
        acceptedRunRecord.terminal_status === "completed" &&
        acceptedRunRecord.stop_reason_code === "agent_complete",
      "POST_EXECUTION_ACCEPTED_RUN_EVIDENCE_INVALID",
      `${request.case_id}:${schemaErrors.join("; ")}`,
    );
    acceptedRunId = acceptedRunRecord.run_id;
    assert(
      !existsSync(join(workerOutput, "observable-trace.jsonl")) &&
        !existsSync(join(workerOutput, "stable-projection.json")) &&
        !existsSync(join(workerOutput, "replay-receipt.json")) &&
        !existsSync(join(workerOutput, "rollback-receipt.json")),
      "NEGATIVE_ADMISSION_ARTIFACT_LEAK",
      request.case_id,
    );
    if (request.adapter_id === "B2") {
      const adapterResultPath = join(workerOutput, "accepted-run/adapter-result.json");
      assert(
        existsSync(adapterResultPath),
        "B2_REAL_CHILD_MISSING",
        request.case_id,
      );
      assertNoSymlinkComponents(workerOutput, adapterResultPath, "B2_REAL_CHILD_MISSING");
      const adapterResult = parseJson(
        readFileSync(adapterResultPath),
        "B2_REAL_CHILD_MISSING",
        request.case_id,
      );
      assert(
        Array.isArray(adapterResult.actions) &&
          adapterResult.actions.some((action) =>
            action.operation_id === "repository_analysis.scan" &&
            action.tool_class === "repository_analysis.scan" &&
            action.exit_code === 0),
        "B2_REAL_CHILD_MISSING",
        request.case_id,
      );
    }
  }
  const validationEvidence = verifyNegativeMutationEvidence(
    workerOutput,
    catalogEntry,
    request,
  );
  return {
    case_id: request.case_id,
    stage: catalogEntry.stage,
    reason_code: value.reason_code,
    rejected: true,
    false_accept: false,
    target_execution_count: value.target_execution_count,
    admitted: value.admitted,
    accepted_run_id: acceptedRunId,
    nonowned_residuals: value.cleanup.nonowned_paths_touched,
    undeclared_executions: value.cleanup.undeclared_executions,
    external_effects: value.external_effects,
    validation_evidence: validationEvidence,
  };
}

function parseArgs(argv) {
  if (
    argv.length !== 4 ||
    argv[0] !== "--worker-entry" ||
    argv[2] !== "--output-root"
  ) {
    fail("CLI_INVALID", "Usage: run-matrix.mjs --worker-entry ABS --output-root ABSENT_ABS");
  }
  const workerEntry = argv[1];
  const outputRoot = argv[3];
  assert(isAbsolute(workerEntry) && resolve(workerEntry) === workerEntry, "CLI_INVALID");
  assert(isAbsolute(outputRoot) && resolve(outputRoot) === outputRoot, "CLI_INVALID");
  return { workerEntry, outputRoot };
}

export function runQualityMatrix({ workerEntry, outputRoot }) {
  const fixtureVerdict = verifyQualityFixtures();
  assert(
    existsSync(workerEntry) &&
      statSync(workerEntry).isFile() &&
      !lstatSync(workerEntry).isSymbolicLink(),
    "WORKER_ENTRY_INVALID",
  );
  createOwnedRoot(outputRoot);
  const positiveRoot = join(outputRoot, "positive");
  const negativeRoot = join(outputRoot, "negative");
  createDirectory(positiveRoot, outputRoot);
  createDirectory(negativeRoot, outputRoot);

  const plan = JSON.parse(readFileSync(join(FIXTURE_ROOT, "positive-plan.json"), "utf8"));
  const positives = [];
  for (const run of plan.runs) {
    const caseRoot = join(positiveRoot, run.case_id);
    createDirectory(caseRoot, outputRoot);
    const workerOutput = join(caseRoot, "worker-output");
    const request = baseRequest({
      caseId: run.case_id,
      adapterId: run.adapter_id,
      repetitionId: run.repetition_id,
      configuration: run.configuration,
      outputRoot: workerOutput,
      mode: "POSITIVE",
      mutation: null,
      preExecution: false,
    });
    const requestPath = join(caseRoot, "request.json");
    writeJsonCreateOnce(requestPath, request, outputRoot);
    positives.push(verifyPositive(
      runWorker(workerEntry, requestPath, workerOutput),
      request,
      workerOutput,
    ));
  }
  assert(
    positives.length === 6 &&
      new Set(positives.map((entry) => entry.workerOutput)).size === 6,
    "POSITIVE_MATRIX_INCOMPLETE",
  );

  const stablePairs = {};
  let rawStochasticPairsDifferent = 0;
  for (const adapterId of ["B0", "B1", "B2"]) {
    const pair = positives.filter((entry) => entry.request.adapter_id === adapterId);
    assert(pair.length === 2, "STABLE_PAIR_INVALID", adapterId);
    assert(
      pair[0].projectionArtifact.bytes.equals(pair[1].projectionArtifact.bytes),
      "STABLE_PAIR_INVALID",
      adapterId,
    );
    assert(
      !pair[0].traceArtifact.bytes.equals(pair[1].traceArtifact.bytes),
      "RAW_STOCHASTIC_DIFFERENCE_MISSING",
      adapterId,
    );
    rawStochasticPairsDifferent += 1;
    stablePairs[adapterId] = {
      byte_equal: true,
      projection_sha256: sha256(pair[0].projectionArtifact.bytes),
      raw_trace_bytes_different: true,
    };
  }

  const catalog = JSON.parse(readFileSync(join(FIXTURE_ROOT, "negative-cases.json"), "utf8"));
  const negatives = [];
  for (const entry of catalog.cases) {
    const caseRoot = join(negativeRoot, entry.case_id);
    createDirectory(caseRoot, outputRoot);
    const workerOutput = join(caseRoot, "worker-output");
    const configuration = entry.adapter_id === "B2"
      ? "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b2-a.json"
      : "evaluation-harness/fixtures/p1-097-minimal-documented/system-configurations/b0-a.json";
    const request = baseRequest({
      caseId: entry.case_id,
      adapterId: entry.adapter_id,
      repetitionId: 1,
      configuration,
      outputRoot: workerOutput,
      mode: "NEGATIVE",
      mutation: {
        stage: entry.stage,
        type: entry.mutation,
      },
      preExecution: entry.stage === "PRE_EXECUTION",
    });
    verifySubmittedMutation(request, entry);
    const requestPath = join(caseRoot, "request.json");
    writeJsonCreateOnce(requestPath, request, outputRoot);
    negatives.push(verifyNegative(
      runWorker(workerEntry, requestPath, workerOutput),
      request,
      workerOutput,
      entry,
    ));
  }
  assert(negatives.length === 19, "NEGATIVE_MATRIX_INCOMPLETE");
  assert(negatives.every((entry) => entry.rejected && !entry.false_accept), "NEGATIVE_FALSE_ACCEPT");
  assert(
    negatives.every((entry) =>
      entry.nonowned_residuals === 0 &&
      entry.undeclared_executions === 0 &&
      isDeepStrictEqual(entry.external_effects, FALSE_EFFECTS)),
    "NEGATIVE_RESIDUAL_OR_EFFECT",
  );
  const postExecutionRunIds = negatives
    .filter((entry) => entry.stage === "POST_EXECUTION")
    .map((entry) => entry.accepted_run_id);
  assert(
    postExecutionRunIds.length === 8 &&
      postExecutionRunIds.every((runId) => typeof runId === "string" && runId.length > 0) &&
      new Set(postExecutionRunIds).size === 8,
    "POST_EXECUTION_FRESH_RUN_INVALID",
  );
  const negativeEvidenceManifest = negatives.map((entry) => ({
    case_id: entry.case_id,
    source_sha256: entry.validation_evidence.source_sha256,
    mutated_sha256: entry.validation_evidence.mutated_sha256,
    receipt_sha256: entry.validation_evidence.receipt_sha256,
  }));
  const negativeEvidenceManifestSha256 = sha256(canonicalBytes(negativeEvidenceManifest));

  const summary = {
    schema_version: "p1-101-quality-formal-verdict/v1",
    task_id: "AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE",
    status: "PASS",
    fixture_manifest_sha256: fixtureVerdict.fixture_manifest_sha256,
    positive_runs: positives.length,
    distinct_positive_run_roots: new Set(positives.map((entry) => entry.workerOutput)).size,
    complete_event_sequences: positives.filter((entry) => entry.events.length === 5).length,
    b2_real_repository_analysis_scan_children: positives
      .filter((entry) => entry.request.adapter_id === "B2").length,
    exact_stable_pairs: Object.keys(stablePairs).length,
    raw_stochastic_pairs_different: rawStochasticPairsDifferent,
    stable_pairs: stablePairs,
    replay_receipts: positives.filter((entry) => entry.replay.status === "PASS").length,
    replay_drift_rejections: positives
      .reduce((sum, entry) => sum + entry.replay_drift_rejections, 0),
    rollback_receipts: positives.filter((entry) => entry.rollback.status === "PASS").length,
    actual_rollback_states_verified: positives
      .filter((entry) => entry.clean_state_identity !== null).length,
    rollback_state_drift_rejections: positives
      .reduce((sum, entry) => sum + entry.rollback_state_drift_rejections, 0),
    negative_cases: negatives.length,
    pre_execution_rejections: negatives.filter((entry) => entry.stage === "PRE_EXECUTION").length,
    post_execution_rejections: negatives.filter((entry) => entry.stage === "POST_EXECUTION").length,
    pre_execution_target_executions: negatives
      .filter((entry) => entry.stage === "PRE_EXECUTION")
      .reduce((sum, entry) => sum + entry.target_execution_count, 0),
    post_execution_target_executions: negatives
      .filter((entry) => entry.stage === "POST_EXECUTION")
      .reduce((sum, entry) => sum + entry.target_execution_count, 0),
    negative_validation_evidence_cases: negativeEvidenceManifest.length,
    negative_validation_evidence_manifest_sha256: negativeEvidenceManifestSha256,
    false_accepts: 0,
    nonowned_residuals: 0,
    undeclared_executions: 0,
    external_effects: { ...FALSE_EFFECTS },
    output_root: outputRoot,
    claim_boundary: "INDEPENDENT_P1_101_ACCEPTED_SHARED_OBSERVABLE_TRACE_QUALITY_MATRIX_ONLY",
  };
  writeJsonCreateOnce(join(outputRoot, "quality-formal-summary.json"), summary, outputRoot);
  writeJsonCreateOnce(join(outputRoot, "negative-results.json"), {
    schema_version: "p1-101-quality-negative-results/v1",
    results: negatives,
  }, outputRoot);
  return summary;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = runQualityMatrix(args);
    process.stdout.write(canonicalBytes(result));
  } catch (error) {
    process.stdout.write(canonicalBytes({
      schema_version: "p1-101-quality-formal-verdict/v1",
      status: "NON_PASS",
      reason_code: error instanceof QualityNonPass ? error.reason : "UNCAUGHT_EXCEPTION",
      error: `${error.name}: ${error.message}`,
      external_effects: FALSE_EFFECTS,
    }));
    process.exit(1);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

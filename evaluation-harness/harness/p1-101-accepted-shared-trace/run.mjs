#!/usr/bin/env node

import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  FALSE_EXTERNAL_EFFECTS,
  canonicalBytes,
  canonicalJson,
  createOwnedOutputRoot,
  executeBoundedCommand,
  exactKeys,
  parseJsonBytes,
  sha256,
  writeOwnedBytesCreateOnce,
  writeOwnedJsonCreateOnce,
} from "../p1-097-minimal-documented/core.mjs";
import {
  loadAndPreflight,
  REPOSITORY_ROOT,
} from "../p1-097-minimal-documented/contracts.mjs";
import {
  artifactIdentity,
  buildObservableTrace,
  buildStableProjection,
  projectionBytes,
} from "../../recording/p1-101-accepted-shared-trace/trace.mjs";
import {
  buildAdmissionValidationInput,
  buildRollbackReceipt,
  parseCanonicalJson,
  replayStableProjection,
  TraceValidationError,
  validateAdmissionInput,
  validateObservableTrace,
  validateReplayReceipt,
  validateRollbackReceipt,
} from "../../replay/p1-101-accepted-shared-trace/replay.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ACCEPTED_WORKER = resolve(HERE, "../p1-097-minimal-documented/run.mjs");
const ACCEPTED_FIXTURE_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-097-minimal-documented",
);
const ACCEPTED_ADAPTER_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/adapters/p1-097-minimal-documented",
);
const EFFECT_KEYS = Object.freeze(Object.keys(FALSE_EXTERNAL_EFFECTS));
const REQUEST_KEYS = Object.freeze([
  "schema_version",
  "request_id",
  "case_id",
  "mode",
  "adapter_id",
  "repetition_id",
  "accepted_system_configuration",
  "validation_inputs",
  "mutation",
  "requested_effects",
  "expected_outcome",
  "output_root",
]);
const RESULT_KEYS = Object.freeze([
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
const DESCRIPTOR_BY_ADAPTER = Object.freeze({
  B0: join(ACCEPTED_ADAPTER_ROOT, "b0-descriptor.json"),
  B1: join(ACCEPTED_ADAPTER_ROOT, "b1-descriptor.json"),
  B2: join(ACCEPTED_ADAPTER_ROOT, "b2-descriptor.json"),
});
const PRE_MUTATIONS = Object.freeze({
  TASK_SPEC_IDENTITY_DRIFT: true,
  ENVIRONMENT_IDENTITY_DRIFT: true,
  SYSTEM_CONFIGURATION_IDENTITY_DRIFT: true,
  EXECUTABLE_IDENTITY_DRIFT: true,
  INPUT_IDENTITY_DRIFT: true,
  REQUEST_EFFECT_NETWORK: true,
  REQUEST_EFFECT_PROVIDER: true,
  REQUEST_EFFECT_SECRET: true,
  REQUEST_EFFECT_REMOTE: true,
  REQUEST_EFFECT_PRODUCTION: true,
  REQUEST_EFFECT_PUBLIC: true,
});
const POST_MUTATIONS = Object.freeze({
  TAMPER_EVENT_BYTES: true,
  REMOVE_REQUIRED_EVENT: true,
  REORDER_EVENTS: true,
  OUTPUT_IDENTITY_DRIFT: true,
  RUN_RECORD_IDENTITY_DRIFT: true,
  CHILD_IDENTITY_DRIFT: true,
  ADD_UNEXPECTED_OUTPUT: true,
  ADD_UNDECLARED_CHILD: true,
});

class SharedTraceNonPass extends Error {
  constructor(code, message) {
    super(message);
    this.name = "SharedTraceNonPass";
    this.code = code;
  }
}

function fail(code, message) {
  throw new SharedTraceNonPass(code, message);
}

function assert(condition, code, message) {
  if (!condition) fail(code, message);
}

function identity(path) {
  const bytes = readFileSync(path);
  return { path, sha256: sha256(bytes), byte_length: bytes.length };
}

function relativeIdentity(path, root = REPOSITORY_ROOT) {
  const bytes = readFileSync(path);
  return {
    path: relative(root, path).split(sep).join("/"),
    sha256: sha256(bytes),
    byte_length: bytes.length,
  };
}

function parseCli(argv) {
  assert(
    argv.length === 4
      && argv[0] === "--request"
      && argv[2] === "--output-root"
      && isAbsolute(argv[1])
      && resolve(argv[1]) === argv[1]
      && isAbsolute(argv[3])
      && resolve(argv[3]) === argv[3],
    "SCHEMA_INVALID",
    "Usage: run.mjs --request ABSOLUTE_JSON --output-root ABSENT_ABSOLUTE_PATH",
  );
  return { requestPath: argv[1], outputRoot: argv[3] };
}

function bestEffortIdentity(path) {
  try {
    const value = JSON.parse(readFileSync(path, "utf8"));
    return {
      request_id: typeof value.request_id === "string" ? value.request_id : "UNKNOWN",
      case_id: typeof value.case_id === "string" ? value.case_id : "UNKNOWN",
    };
  } catch {
    return { request_id: "UNKNOWN", case_id: "UNKNOWN" };
  }
}

function validateBoundConfiguration(reference, adapterId) {
  exactKeys(reference, ["path", "sha256", "byte_length"], "accepted system configuration");
  assert(isAbsolute(reference.path), "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH", "configuration path is not absolute");
  const path = resolve(reference.path);
  const rel = relative(join(ACCEPTED_FIXTURE_ROOT, "system-configurations"), path);
  assert(
    rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel),
    "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
    "configuration is not an accepted canonical fixture",
  );
  assert(existsSync(path), "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH", "configuration missing");
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink() && realpathSync(path) === path, "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH", "configuration is not a regular canonical file");
  const bytes = readFileSync(path);
  assert(
    sha256(bytes) === reference.sha256 && bytes.length === reference.byte_length,
    "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
    "configuration bytes drifted",
  );
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch {
    fail("SYSTEM_CONFIGURATION_IDENTITY_MISMATCH", "configuration JSON invalid");
  }
  assert(value.adapter_id === adapterId, "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH", "configuration adapter differs");
  return { path, bytes, value };
}

function validateRequest(path, outputRoot) {
  assert(existsSync(path), "SCHEMA_INVALID", "request missing");
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink(), "SCHEMA_INVALID", "request is not a regular file");
  const bytes = readFileSync(path);
  const request = parseCanonicalJson(bytes, "SCHEMA_INVALID");
  exactKeys(request, REQUEST_KEYS, "shared trace request");
  assert(
    request.schema_version === "p1-101-quality-request/v1"
      && typeof request.request_id === "string"
      && request.request_id.length > 0
      && typeof request.case_id === "string"
      && request.case_id.length > 0
      && ["POSITIVE", "NEGATIVE"].includes(request.mode)
      && ["B0", "B1", "B2"].includes(request.adapter_id)
      && Number.isInteger(request.repetition_id)
      && request.repetition_id >= 1
      && request.output_root === outputRoot,
    "SCHEMA_INVALID",
    "request identity or output root invalid",
  );
  exactKeys(request.requested_effects, EFFECT_KEYS, "requested external effects");
  exactKeys(request.expected_outcome, ["status", "pre_execution", "target_execution_count"], "expected outcome");
  exactKeys(
    request.validation_inputs,
    ["task_spec", "environment_snapshot", "system_configuration", "executable", "input"],
    "pre-admission validation inputs",
  );
  const configuration = validateBoundConfiguration(request.accepted_system_configuration, request.adapter_id);
  return {
    request,
    bytes,
    requestIdentity: { path, sha256: sha256(bytes), byte_length: bytes.length },
    configuration,
  };
}

function validateMutation(request) {
  if (request.mode === "POSITIVE") {
    assert(request.mutation === null, "SCHEMA_INVALID", "positive mutation must be null");
    assert(
      canonicalJson(request.requested_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS),
      "EXTERNAL_EFFECT_FORBIDDEN",
      "positive request effects differ from all false",
    );
    return null;
  }
  exactKeys(request.mutation, ["stage", "type"], "negative mutation");
  const catalog = request.mutation.stage === "PRE_EXECUTION" ? PRE_MUTATIONS : POST_MUTATIONS;
  const expected = catalog[request.mutation.type];
  assert(
    expected === true,
    "SCHEMA_INVALID",
    "negative mutation is not in the frozen catalog",
  );
  if (request.mutation.stage === "PRE_EXECUTION") {
    if (request.mutation.type.startsWith("REQUEST_EFFECT_")) {
      const effect = request.mutation.type.slice("REQUEST_EFFECT_".length).toLowerCase();
      assert(
        EFFECT_KEYS.filter((key) => request.requested_effects[key]).length === 1
          && request.requested_effects[effect] === true,
        "SCHEMA_INVALID",
        "external-effect negative does not request exactly its declared effect",
      );
    } else {
      assert(
        canonicalJson(request.requested_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS),
        "SCHEMA_INVALID",
        "identity negative requested an external effect",
      );
    }
  } else {
    assert(
      canonicalJson(request.requested_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS),
      "SCHEMA_INVALID",
      "post-execution mutation requested an external effect",
    );
  }
  return request.mutation;
}

function canonicalAcceptedInputs(context) {
  const descriptorPath = DESCRIPTOR_BY_ADAPTER[context.request.adapter_id];
  const descriptorBytes = readFileSync(descriptorPath);
  let descriptor;
  try {
    descriptor = JSON.parse(descriptorBytes.toString("utf8"));
  } catch {
    fail("EXECUTABLE_IDENTITY_MISMATCH", "accepted descriptor JSON invalid");
  }
  const taskPath = join(ACCEPTED_FIXTURE_ROOT, "task-spec.json");
  const environmentPath = join(ACCEPTED_FIXTURE_ROOT, "environment-snapshot.json");
  return {
    task_spec: identity(taskPath),
    environment_snapshot: identity(environmentPath),
    system_configuration: identity(context.configuration.path),
    executable: identity(resolve(REPOSITORY_ROOT, descriptor.executable.path)),
    input: identity(resolve(REPOSITORY_ROOT, descriptor.input_bindings.adapter_input.path)),
  };
}

function validateBoundReference(actual, expected, code) {
  exactKeys(actual, ["path", "sha256", "byte_length"], code);
  assert(
    actual.path === expected.path
      && actual.sha256 === expected.sha256
      && actual.byte_length === expected.byte_length,
    code,
    `${code} binding differs from accepted canonical bytes`,
  );
  const bytes = readFileSync(expected.path);
  assert(
    bytes.length === actual.byte_length && sha256(bytes) === actual.sha256,
    code,
    `${code} physical bytes differ`,
  );
}

function validatePreAdmission(context) {
  const expected = canonicalAcceptedInputs(context);
  const inputs = context.request.validation_inputs;
  validateBoundReference(inputs.task_spec, expected.task_spec, "TASK_SPEC_IDENTITY_MISMATCH");
  validateBoundReference(
    inputs.environment_snapshot,
    expected.environment_snapshot,
    "ENVIRONMENT_IDENTITY_MISMATCH",
  );
  validateBoundReference(
    inputs.system_configuration,
    expected.system_configuration,
    "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
  );
  validateBoundReference(inputs.executable, expected.executable, "EXECUTABLE_IDENTITY_MISMATCH");
  validateBoundReference(inputs.input, expected.input, "INPUT_IDENTITY_MISMATCH");
  assert(
    canonicalJson(context.request.requested_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_FORBIDDEN",
    "request asks for an external effect",
  );
  return expected;
}

function observedPreAdmissionReason(context) {
  try {
    validatePreAdmission(context);
  } catch (error) {
    if (error instanceof SharedTraceNonPass) return error.code;
    throw error;
  }
  fail("NEGATIVE_FALSE_ACCEPT", "drifted pre-admission input was accepted");
}

function writeNegativeValidationEvidence({
  ownedRoot,
  mutationType,
  sourceBytes,
  mutatedBytes,
  observedReason,
}) {
  const sourceRef = writeOwnedBytesCreateOnce(
    ownedRoot,
    "negative-source-input.bin",
    sourceBytes,
  );
  const mutatedRef = writeOwnedBytesCreateOnce(
    ownedRoot,
    "negative-validation-input.bin",
    mutatedBytes,
  );
  writeOwnedJsonCreateOnce(ownedRoot, "negative-validation-receipt.json", {
    schema_version: "p1-101-negative-validation-receipt/v1",
    record_type: "p1_101_negative_validation_receipt",
    mutation_type: mutationType,
    source_identity: sourceRef,
    mutated_identity: mutatedRef,
    observed_reason: observedReason,
    validator_invoked: true,
    admitted: false,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  });
}

function executePreNegative(context, ownedRoot, mutation) {
  const source = {
    schema_version: "p1-101-preexecution-validation-input/v1",
    validation_inputs: canonicalAcceptedInputs(context),
    requested_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const mutated = {
    schema_version: "p1-101-preexecution-validation-input/v1",
    validation_inputs: context.request.validation_inputs,
    requested_effects: context.request.requested_effects,
  };
  const observedReason = observedPreAdmissionReason(context);
  writeNegativeValidationEvidence({
    ownedRoot,
    mutationType: mutation.type,
    sourceBytes: canonicalBytes(source),
    mutatedBytes: canonicalBytes(mutated),
    observedReason,
  });
  return observedReason;
}

function result({
  identityValue,
  status,
  reasonCode,
  count,
  admitted,
  outputRootCreated,
  refs = {},
}) {
  const value = {
    schema_version: "p1-101-quality-result/v1",
    request_id: identityValue.request_id,
    case_id: identityValue.case_id,
    status,
    reason_code: reasonCode,
    target_execution_count: count,
    admitted,
    output_root_created: outputRootCreated,
    run_record_ref: refs.runRecord ?? null,
    trace_ref: refs.trace ?? null,
    stable_projection_ref: refs.projection ?? null,
    replay_receipt_ref: refs.replay ?? null,
    rollback_receipt_ref: refs.rollback ?? null,
    external_effects: FALSE_EXTERNAL_EFFECTS,
    cleanup: {
      owned_paths_removed: 0,
      nonowned_paths_touched: 0,
      undeclared_executions: 0,
    },
  };
  exactKeys(value, RESULT_KEYS, "shared trace result");
  return value;
}

function parseCanonicalStdout(bytes) {
  assert(
    bytes.length > 0
      && bytes.at(-1) === 0x0a
      && !bytes.subarray(0, bytes.length - 1).includes(0x0a),
    "ACCEPTED_CHILD_NON_PASS",
    "accepted worker stdout is not exactly one line",
  );
  const value = parseJsonBytes(bytes, "accepted child stdout");
  assert(bytes.equals(canonicalBytes(value)), "ACCEPTED_CHILD_NON_PASS", "accepted child stdout is not canonical");
  return value;
}

function verifyRef(root, reference, expectedPath, code, parseJson = true) {
  exactKeys(reference, ["path", "sha256", "byte_length"], expectedPath);
  const path = resolve(reference.path);
  assert(path === join(root, expectedPath), code, `${expectedPath} path differs`);
  assert(existsSync(path), code, `${expectedPath} missing`);
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink(), code, `${expectedPath} invalid`);
  const bytes = readFileSync(path);
  assert(bytes.length === reference.byte_length && sha256(bytes) === reference.sha256, code, `${expectedPath} identity differs`);
  return {
    path,
    bytes,
    value: parseJson ? parseCanonicalJson(bytes, code) : null,
  };
}

async function executeAcceptedRun(context, ownedRoot) {
  const acceptedRoot = join(ownedRoot.root, "accepted-run");
  const descriptorPath = DESCRIPTOR_BY_ADAPTER[context.request.adapter_id];
  const taskPath = join(ACCEPTED_FIXTURE_ROOT, "task-spec.json");
  const environmentPath = join(ACCEPTED_FIXTURE_ROOT, "environment-snapshot.json");
  const descriptorBytes = readFileSync(descriptorPath);
  const childRequest = {
    schema_version: "p1-097-worker-request/v1",
    request_id: `${context.request.request_id}:accepted`,
    case_id: context.request.case_id,
    mode: "POSITIVE",
    adapter_id: context.request.adapter_id,
    repetition_id: context.request.repetition_id,
    task_spec: identity(taskPath),
    environment_snapshot: identity(environmentPath),
    system_configuration: identity(context.configuration.path),
    execution_descriptor: identity(descriptorPath),
    expected_descriptor_identity: {
      sha256: sha256(descriptorBytes),
      byte_length: descriptorBytes.length,
    },
    output_root: acceptedRoot,
    target_sentinel_path: join(acceptedRoot, "target-executed"),
    nonowned_fixture: null,
    requested_effects: FALSE_EXTERNAL_EFFECTS,
    expected_outcome: {
      status: "PASS",
      reason_code: "PASS",
      pre_execution: false,
    },
  };
  const childRequestRef = writeOwnedJsonCreateOnce(ownedRoot, "accepted-request.json", childRequest);
  const childRequestPath = join(ownedRoot.root, childRequestRef.path);
  loadAndPreflight(childRequestPath, acceptedRoot);
  const command = await executeBoundedCommand({
    argv: [
      resolve(process.execPath),
      ACCEPTED_WORKER,
      "--request",
      childRequestPath,
      "--output-root",
      acceptedRoot,
    ],
    cwd: REPOSITORY_ROOT,
    timeoutSeconds: 120,
    expectedExitCodes: [0],
    environment: {
      HOME: process.env.HOME ?? "",
      PATH: "/usr/local/bin:/usr/bin:/bin",
    },
  });
  const commandRef = writeOwnedJsonCreateOnce(ownedRoot, "accepted-child-command.json", command.ledger);
  assert(
    command.ledger.expected_exit_matched
      && command.ledger.exit_status === 0
      && command.stderr.length === 0,
    "ACCEPTED_CHILD_NON_PASS",
    "accepted adapter worker did not pass",
  );
  const childResult = parseCanonicalStdout(command.stdout);
  assert(
    childResult.status === "PASS"
      && childResult.reason_code === "PASS"
      && childResult.target_execution_count === 1,
    "ACCEPTED_CHILD_NON_PASS",
    "accepted adapter result did not pass",
  );
  const childWorkerResultRef = writeOwnedBytesCreateOnce(
    ownedRoot,
    "accepted-child-result.json",
    command.stdout,
  );
  const runRecord = verifyRef(acceptedRoot, childResult.run_record_ref, "run-record.json", "RUN_RECORD_IDENTITY_MISMATCH");
  const underlyingTrace = verifyRef(
    acceptedRoot,
    childResult.trace_ref,
    "trace.jsonl",
    "TRACE_EVENT_IDENTITY_MISMATCH",
    false,
  );
  const underlyingProjection = verifyRef(acceptedRoot, childResult.stable_projection_ref, "stable-projection.json", "OUTPUT_IDENTITY_MISMATCH");
  const adapterResultPath = join(acceptedRoot, "adapter-result.json");
  const adapterResultBytes = readFileSync(adapterResultPath);
  const adapterResult = parseCanonicalJson(adapterResultBytes, "OUTPUT_IDENTITY_MISMATCH");
  let descriptor;
  try {
    descriptor = JSON.parse(descriptorBytes.toString("utf8"));
  } catch {
    fail("EXECUTABLE_IDENTITY_MISMATCH", "accepted descriptor JSON invalid");
  }
  const inputPath = resolve(REPOSITORY_ROOT, descriptor.input_bindings.adapter_input.path);
  return {
    acceptedRoot,
    childRequest,
    childRequestRef,
    command,
    commandRef,
    childWorkerResultRef,
    runRecord,
    underlyingTrace,
    underlyingProjection,
    adapterResult,
    adapterResultBytes,
    taskPath,
    environmentPath,
    descriptorPath,
    descriptor,
    inputPath,
  };
}

function traceBindings(context, accepted) {
  return {
    task_spec: relativeIdentity(accepted.taskPath),
    environment_snapshot: relativeIdentity(accepted.environmentPath),
    system_configuration: relativeIdentity(context.configuration.path),
    executable: relativeIdentity(resolve(REPOSITORY_ROOT, accepted.descriptor.executable.path)),
    input: relativeIdentity(accepted.inputPath),
    output: artifactIdentity("accepted-run/adapter-result.json", accepted.adapterResultBytes),
    run_record: artifactIdentity("accepted-run/run-record.json", accepted.runRecord.bytes),
    shared_request: {
      path: context.requestIdentity.path,
      sha256: context.requestIdentity.sha256,
      byte_length: context.requestIdentity.byte_length,
    },
    accepted_request: {
      path: "accepted-request.json",
      sha256: accepted.childRequestRef.sha256,
      byte_length: accepted.childRequestRef.byte_length,
    },
    underlying_trace: artifactIdentity("accepted-run/trace.jsonl", accepted.underlyingTrace.bytes),
    underlying_stable_projection: artifactIdentity(
      "accepted-run/stable-projection.json",
      accepted.underlyingProjection.bytes,
    ),
  };
}

function inventory(root) {
  const walk = (directory) => readdirSync(directory, { withFileTypes: true })
    .flatMap((entry) => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return walk(path);
      const bytes = readFileSync(path);
      return [{
        path: relative(root, path).split(sep).join("/"),
        sha256: sha256(bytes),
        byte_length: bytes.length,
      }];
    });
  return walk(root).sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path)));
}

function childInvocations(accepted) {
  return accepted.adapterResult.actions
    .filter((action) => action.tool_class !== null)
    .map((action) => ({
      sequence: action.sequence,
      action_id: action.action_id,
      tool_class: action.tool_class,
      operation_id: action.operation_id ?? null,
      exit_code: action.exit_code,
    }));
}

function mutateAdmissionInput(source, type) {
  const mutated = structuredClone(source);
  const driftSha = "0".repeat(64);
  switch (type) {
    case "TAMPER_EVENT_BYTES":
      mutated.trace_events[0].event_data.admitted = false;
      break;
    case "REMOVE_REQUIRED_EVENT":
      mutated.trace_events.splice(2, 1);
      break;
    case "REORDER_EVENTS":
      [mutated.trace_events[1], mutated.trace_events[2]] = [
        mutated.trace_events[2],
        mutated.trace_events[1],
      ];
      break;
    case "OUTPUT_IDENTITY_DRIFT":
      mutated.output_identity.sha256 = driftSha;
      break;
    case "RUN_RECORD_IDENTITY_DRIFT":
      mutated.run_record_identity.sha256 = driftSha;
      break;
    case "CHILD_IDENTITY_DRIFT":
      mutated.child_invocations[0].operation_id = "repository_analysis.scan.drifted";
      break;
    case "ADD_UNEXPECTED_OUTPUT":
      mutated.output_inventory.push({
        path: "accepted-run/unexpected-output.bin",
        sha256: driftSha,
        byte_length: 1,
      });
      break;
    case "ADD_UNDECLARED_CHILD":
      mutated.child_invocations.push({
        sequence: 999,
        action_id: "undeclared-child",
        tool_class: "undeclared",
        operation_id: "undeclared.child",
        exit_code: 0,
      });
      break;
    default:
      fail("SCHEMA_INVALID", "unknown post-execution mutation");
  }
  return mutated;
}

function observedValidationReason(candidate, expected) {
  try {
    validateAdmissionInput(candidate, expected);
  } catch (error) {
    if (error instanceof TraceValidationError) return error.code;
    throw error;
  }
  fail("NEGATIVE_FALSE_ACCEPT", "mutated admission input was accepted");
}

function executePostNegative(context, ownedRoot, accepted, mutation) {
  const bindings = traceBindings(context, accepted);
  const trace = buildObservableTrace({
    sharedRequestIdentity: bindings.shared_request,
    acceptedRequestIdentity: bindings.accepted_request,
    childCommandIdentity: {
      path: accepted.commandRef.path,
      sha256: accepted.commandRef.sha256,
      byte_length: accepted.commandRef.byte_length,
    },
    childWorkerResultIdentity: {
      path: accepted.childWorkerResultRef.path,
      sha256: accepted.childWorkerResultRef.sha256,
      byte_length: accepted.childWorkerResultRef.byte_length,
    },
    taskSpecIdentity: bindings.task_spec,
    environmentIdentity: bindings.environment_snapshot,
    configurationIdentity: bindings.system_configuration,
    executableIdentity: bindings.executable,
    inputIdentity: bindings.input,
    outputIdentity: bindings.output,
    runRecordIdentity: bindings.run_record,
    underlyingTraceIdentity: bindings.underlying_trace,
    underlyingProjectionIdentity: bindings.underlying_stable_projection,
    runRecord: accepted.runRecord.value,
    adapterResult: accepted.adapterResult,
    childLedger: accepted.command.ledger,
  });
  const source = buildAdmissionValidationInput({
    events: trace.events,
    outputIdentity: bindings.output,
    runRecordIdentity: bindings.run_record,
    childInvocations: childInvocations(accepted),
    outputInventory: inventory(accepted.acceptedRoot),
  });
  const expected = {
    trace_identity: {
      sha256: sha256(trace.bytes),
      byte_length: trace.bytes.length,
    },
    output_identity: source.output_identity,
    run_record_identity: source.run_record_identity,
    child_invocations: source.child_invocations,
    output_inventory: source.output_inventory,
    adapter_id: context.request.adapter_id,
  };
  validateAdmissionInput(source, expected);
  const mutated = mutateAdmissionInput(source, mutation.type);
  const observedReason = observedValidationReason(mutated, expected);
  const sourceBytes = canonicalBytes(source);
  const mutatedBytes = canonicalBytes(mutated);
  writeNegativeValidationEvidence({
    ownedRoot,
    mutationType: mutation.type,
    sourceBytes,
    mutatedBytes,
    observedReason,
  });
  return observedReason;
}

function verifyPhysicalRollback(accepted) {
  const rollback = accepted.adapterResult.rollback;
  const regularInventory = (root) => {
    const walk = (directory) => readdirSync(directory, { withFileTypes: true })
      .flatMap((entry) => {
        const path = join(directory, entry.name);
        const pathRel = relative(root, path).split(sep).join("/");
        const stat = lstatSync(path);
        assert(!stat.isSymbolicLink(), "OUTPUT_IDENTITY_MISMATCH", pathRel);
        if (entry.isDirectory()) return walk(path);
        assert(entry.isFile(), "OUTPUT_IDENTITY_MISMATCH", pathRel);
        const bytes = readFileSync(path);
        return [{ path: pathRel, sha256: sha256(bytes), byte_length: bytes.length }];
      });
    return walk(root).sort((left, right) => Buffer.compare(
      Buffer.from(left.path),
      Buffer.from(right.path),
    ));
  };
  if (accepted.adapterResult.adapter_id === "B0") {
    assert(
      rollback.status === "NOT_APPLICABLE_NO_SOURCE_MUTATION"
        && accepted.adapterResult.source_mutation_observed === false,
      "OUTPUT_IDENTITY_MISMATCH",
      "B0 no-mutation rollback boundary drifted",
    );
    return {
      kind: "NO_SOURCE_MUTATION",
      source_root: null,
      entry_count: 0,
      manifest_sha256: sha256(canonicalBytes([])),
    };
  }
  const relativeSourceRoot = accepted.adapterResult.adapter_id === "B1"
    ? "accepted-run/work/b1-disposable-source"
    : "accepted-run/work/b2-scan-source";
  const sourceRoot = join(dirname(accepted.acceptedRoot), relativeSourceRoot);
  assert(
    existsSync(sourceRoot)
      && lstatSync(sourceRoot).isDirectory()
      && !lstatSync(sourceRoot).isSymbolicLink(),
    "OUTPUT_IDENTITY_MISMATCH",
    "disposable rollback source is missing",
  );
  if (accepted.adapterResult.adapter_id === "B1") {
    assert(
      rollback.status === "PASS_EXACT"
        && rollback.pre_tree_source_sha256 === rollback.post_rollback_source_sha256
        && Array.isArray(rollback.files),
      "OUTPUT_IDENTITY_MISMATCH",
      "B1 rollback declaration is not exact",
    );
    for (const entry of rollback.files) {
      const path = resolve(sourceRoot, entry.path);
      const pathRel = relative(sourceRoot, path);
      assert(
        pathRel !== "" && pathRel !== ".." && !pathRel.startsWith(`..${sep}`)
          && existsSync(path)
          && lstatSync(path).isFile()
          && !lstatSync(path).isSymbolicLink(),
        "OUTPUT_IDENTITY_MISMATCH",
        "B1 rollback file is not a retained disposable file",
      );
      const bytes = readFileSync(path);
      assert(
        sha256(bytes) === entry.sha256
          && bytes.length === entry.byte_length
          && entry.matches === true,
        "OUTPUT_IDENTITY_MISMATCH",
        "B1 physical rollback bytes differ",
      );
    }
  } else if (accepted.adapterResult.adapter_id === "B2") {
    assert(
      rollback.status === "NOT_APPLICABLE_READ_ONLY_SCAN_SOURCE_UNCHANGED"
        && rollback.source_exact_after_scan === true
        && accepted.adapterResult.source_mutation_observed === false,
      "OUTPUT_IDENTITY_MISMATCH",
      "B2 read-only rollback boundary drifted",
    );
    assert(
      resolve(accepted.adapterResult.scan_result.repo_path) === sourceRoot,
      "OUTPUT_IDENTITY_MISMATCH",
      "B2 retained scan source is not inside the disposable run",
    );
  }
  const manifest = regularInventory(sourceRoot);
  return {
    kind: "DISPOSABLE_SOURCE_EXACT",
    source_root: relativeSourceRoot,
    entry_count: manifest.length,
    manifest_sha256: sha256(canonicalBytes(manifest)),
  };
}

async function executePositive(context, ownedRoot, accepted) {
  const bindings = traceBindings(context, accepted);
  const commandIdentity = {
    path: accepted.commandRef.path,
    sha256: accepted.commandRef.sha256,
    byte_length: accepted.commandRef.byte_length,
  };
  const workerResultIdentity = {
    path: accepted.childWorkerResultRef.path,
    sha256: accepted.childWorkerResultRef.sha256,
    byte_length: accepted.childWorkerResultRef.byte_length,
  };
  const trace = buildObservableTrace({
    sharedRequestIdentity: bindings.shared_request,
    acceptedRequestIdentity: bindings.accepted_request,
    childCommandIdentity: commandIdentity,
    childWorkerResultIdentity: workerResultIdentity,
    taskSpecIdentity: bindings.task_spec,
    environmentIdentity: bindings.environment_snapshot,
    configurationIdentity: bindings.system_configuration,
    executableIdentity: bindings.executable,
    inputIdentity: bindings.input,
    outputIdentity: bindings.output,
    runRecordIdentity: bindings.run_record,
    underlyingTraceIdentity: bindings.underlying_trace,
    underlyingProjectionIdentity: bindings.underlying_stable_projection,
    runRecord: accepted.runRecord.value,
    adapterResult: accepted.adapterResult,
    childLedger: accepted.command.ledger,
  });
  validateObservableTrace({
    traceBytes: trace.bytes,
    expectedRunId: accepted.runRecord.value.run_id,
    expectedBindings: bindings,
    expectedAdapterId: context.request.adapter_id,
  });
  const projection = buildStableProjection({
    runRecord: accepted.runRecord.value,
    taskSpecIdentity: bindings.task_spec,
    environmentIdentity: bindings.environment_snapshot,
    executableIdentity: bindings.executable,
    inputIdentity: bindings.input,
    underlyingProjection: accepted.underlyingProjection.value,
    adapterResult: accepted.adapterResult,
  });
  const projectionPayload = projectionBytes(projection);
  const replayRunRecordBytes = readFileSync(accepted.runRecord.path);
  const replayRunRecord = parseCanonicalJson(
    replayRunRecordBytes,
    "RUN_RECORD_IDENTITY_MISMATCH",
  );
  const replayAdapterResultBytes = readFileSync(
    join(accepted.acceptedRoot, "adapter-result.json"),
  );
  const replayAdapterResult = parseCanonicalJson(
    replayAdapterResultBytes,
    "OUTPUT_IDENTITY_MISMATCH",
  );
  const replayUnderlyingProjection = parseCanonicalJson(
    readFileSync(accepted.underlyingProjection.path),
    "OUTPUT_IDENTITY_MISMATCH",
  );
  const replayedProjection = buildStableProjection({
    runRecord: replayRunRecord,
    taskSpecIdentity: relativeIdentity(accepted.taskPath),
    environmentIdentity: relativeIdentity(accepted.environmentPath),
    executableIdentity: relativeIdentity(
      resolve(REPOSITORY_ROOT, accepted.descriptor.executable.path),
    ),
    inputIdentity: relativeIdentity(accepted.inputPath),
    underlyingProjection: replayUnderlyingProjection,
    adapterResult: replayAdapterResult,
  });
  const replay = replayStableProjection({
    traceBytes: trace.bytes,
    projection,
    expectedProjection: replayedProjection,
    runRecordBytes: replayRunRecordBytes,
  });
  validateReplayReceipt({
    traceBytes: trace.bytes,
    projectionBytes: projectionPayload,
    runRecordBytes: replayRunRecordBytes,
    receipt: replay,
  });
  const cleanStateIdentity = verifyPhysicalRollback(accepted);
  const rollback = buildRollbackReceipt({
    runRecordBytes: accepted.runRecord.bytes,
    adapterResult: accepted.adapterResult,
    cleanStateIdentity,
  });
  validateRollbackReceipt({
    runRecordBytes: accepted.runRecord.bytes,
    cleanStateIdentity,
    receipt: rollback,
  });
  const traceRef = writeOwnedBytesCreateOnce(ownedRoot, "observable-trace.jsonl", trace.bytes);
  const projectionRef = writeOwnedBytesCreateOnce(ownedRoot, "stable-projection.json", projectionPayload);
  const replayRef = writeOwnedJsonCreateOnce(ownedRoot, "replay-receipt.json", replay);
  const rollbackRef = writeOwnedJsonCreateOnce(ownedRoot, "rollback-receipt.json", rollback);
  return {
    runRecord: artifactIdentity("accepted-run/run-record.json", accepted.runRecord.bytes),
    trace: traceRef,
    projection: projectionRef,
    replay: replayRef,
    rollback: rollbackRef,
  };
}

async function main() {
  let cli = { requestPath: null, outputRoot: null };
  let identityValue = { request_id: "UNKNOWN", case_id: "UNKNOWN" };
  let outputRootCreated = false;
  let targetExecutionCount = 0;
  try {
    cli = parseCli(process.argv.slice(2));
    identityValue = bestEffortIdentity(cli.requestPath);
    const context = validateRequest(cli.requestPath, cli.outputRoot);
    identityValue = {
      request_id: context.request.request_id,
      case_id: context.request.case_id,
    };
    const mutation = validateMutation(context.request);
    if (mutation?.stage === "PRE_EXECUTION") {
      const ownedRoot = createOwnedOutputRoot(cli.outputRoot);
      outputRootCreated = true;
      const observedReason = executePreNegative(context, ownedRoot, mutation);
      fail(observedReason, `pre-execution negative: ${mutation.type}`);
    }
    validatePreAdmission(context);
    const ownedRoot = createOwnedOutputRoot(cli.outputRoot);
    outputRootCreated = true;
    const accepted = await executeAcceptedRun(context, ownedRoot);
    targetExecutionCount = 1;
    if (mutation?.stage === "POST_EXECUTION") {
      const observedReason = executePostNegative(context, ownedRoot, accepted, mutation);
      fail(observedReason, `post-execution negative: ${mutation.type}`);
    }
    const refs = await executePositive(context, ownedRoot, accepted);
    process.stdout.write(`${canonicalJson(result({
      identityValue,
      status: "PASS",
      reasonCode: "PASS",
      count: 1,
      admitted: true,
      outputRootCreated: true,
      refs,
    }))}\n`);
  } catch (error) {
    const reasonCode = error instanceof SharedTraceNonPass || error instanceof TraceValidationError
      ? error.code
      : (typeof error?.code === "string" ? error.code : "UNCAUGHT_EXCEPTION");
    process.stdout.write(`${canonicalJson(result({
      identityValue,
      status: "REJECTED",
      reasonCode,
      count: targetExecutionCount,
      admitted: false,
      outputRootCreated,
    }))}\n`);
    process.exitCode = 2;
  }
}

await main();

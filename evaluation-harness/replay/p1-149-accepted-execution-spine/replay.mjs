import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
} from "node:fs";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  containedPath,
  exactKeys,
  listClosedFiles,
  parseCanonicalJsonBytes,
  safeRealDirectory,
  safeRegularFile,
  sha256,
  validateArtifactPath,
} from "../../harness/p1-149-accepted-execution-spine/core.mjs";
import {
  ACCEPTED_TASK_IDS,
  loadAcceptedCompilerProfile,
  loadAcceptedTask,
  verifyAcceptedPatchIrV1Compatibility,
} from "../../harness/p1-149-accepted-execution-spine/accepted-inputs.mjs";
import {
  EXECUTION_ARTIFACT_KEYS,
  EXECUTION_SPINE_VERSION,
} from "../../harness/p1-149-accepted-execution-spine/execution.mjs";
import {
  compileNormalizedProviderResponse,
  extractPatchIrFromNormalizedResponse,
} from "../../harness/p1-149-accepted-execution-spine/patch-ir-v2.mjs";
import {
  buildStableProjection,
  EVENT_ORDER,
} from "../../recording/p1-101-accepted-shared-trace/trace.mjs";
import {
  validateReplayReceipt,
  validateRollbackReceipt,
} from "../p1-101-accepted-shared-trace/replay.mjs";

export const RAW_EVIDENCE_MANIFEST = "MANIFEST.json";
export const READINESS_CLAIM_BOUNDARY = "READINESS_ONLY_NOT_FORMAL_BASELINE";
export const FIXED_PROFILE_ORDER = Object.freeze([
  "B0_A",
  "B0_B",
  "B1_A",
  "B1_B",
  "B2_A",
  "B2_B",
]);
export const REQUIRED_TASK_ARTIFACTS = EXECUTION_ARTIFACT_KEYS;

const IDENTITY_KEYS = Object.freeze(["path", "sha256", "byte_length"]);
const MANIFEST_KEYS = Object.freeze([
  "schema_version",
  "task_ids",
  "file_count",
  "inventory_sha256",
  "entries",
]);
const FORBIDDEN_WORKER_VERDICT_KEYS = new Set([
  "cell_result",
  "success",
  "verified_success",
  "worker_success",
]);

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function assertIdentityShape(identity, label) {
  exactKeys(identity, IDENTITY_KEYS, label);
  validateArtifactPath(identity.path, `${label}.path`);
  assert(/^[0-9a-f]{64}$/.test(identity.sha256), "IDENTITY_INVALID", `${label} SHA-256 invalid`);
  assert(
    Number.isInteger(identity.byte_length) && identity.byte_length >= 0,
    "IDENTITY_INVALID",
    `${label} byte length invalid`,
  );
}

function readBoundFile(root, relativePath, label) {
  const path = containedPath(root, relativePath, label);
  const regular = safeRegularFile(path, label, true);
  const bytes = readFileSync(regular);
  return { path: regular, bytes, identity: { path: relativePath, ...bytesIdentity(bytes) } };
}

function assertExactIdentity(actual, expected, code, label) {
  assert(
    isDeepStrictEqual(actual, expected),
    code,
    `${label} identity drifted`,
    { actual, expected },
  );
}

function inventoryDigest(entries) {
  return sha256(canonicalBytes({
    schema_version: "p1-149-closed-raw-evidence-inventory/v1",
    entries,
  }));
}

function assertSingleLinkInventory(root, entries) {
  for (const entry of entries) {
    const path = containedPath(root, entry.path, "closed inventory entry");
    const stat = lstatSync(path);
    assert(
      stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
      "CLOSED_INVENTORY_PATH_INVALID",
      `closed inventory entry is not an owned single-link regular file: ${entry.path}`,
    );
  }
}

function assertClosedDirectoryStructure(root) {
  const visit = (directory, isRoot = false) => {
    const names = readdirSync(directory).sort();
    assert(
      isRoot || names.length > 0,
      "CLOSED_INVENTORY_EMPTY_DIRECTORY",
      "closed raw Evidence contains an unbound empty directory",
    );
    for (const name of names) {
      const path = join(directory, name);
      const stat = lstatSync(path);
      assert(
        !stat.isSymbolicLink(),
        "SYMLINK_REJECTED",
        "closed raw Evidence contains a symlink",
      );
      if (stat.isDirectory()) {
        visit(path, false);
      } else {
        assert(
          stat.isFile() && stat.nlink === 1,
          "CLOSED_INVENTORY_PATH_INVALID",
          "closed raw Evidence contains a non-regular or multiply-linked entry",
        );
      }
    }
  };
  visit(root, true);
}

export function buildClosedEvidenceManifest(root, taskIds = ACCEPTED_TASK_IDS) {
  const absolute = safeRealDirectory(root, "raw Evidence root");
  assert(
    isDeepStrictEqual(taskIds, ACCEPTED_TASK_IDS),
    "TASK_SET_INVALID",
    "raw Evidence manifest must bind the exact accepted six-task order",
  );
  assertClosedDirectoryStructure(absolute);
  const entries = listClosedFiles(absolute)
    .filter((entry) => entry.path !== RAW_EVIDENCE_MANIFEST);
  assertSingleLinkInventory(absolute, entries);
  return {
    schema_version: "p1-149-closed-raw-evidence-manifest/v1",
    task_ids: [...ACCEPTED_TASK_IDS],
    file_count: entries.length,
    inventory_sha256: inventoryDigest(entries),
    entries,
  };
}

export function validateClosedEvidenceRoot(root) {
  const absolute = safeRealDirectory(root, "frozen raw Evidence root");
  const manifestArtifact = readBoundFile(
    absolute,
    RAW_EVIDENCE_MANIFEST,
    "closed raw Evidence manifest",
  );
  const manifest = parseCanonicalJsonBytes(
    manifestArtifact.bytes,
    "closed raw Evidence manifest",
  );
  exactKeys(manifest, MANIFEST_KEYS, "closed raw Evidence manifest");
  assert(
    manifest.schema_version === "p1-149-closed-raw-evidence-manifest/v1",
    "CLOSED_INVENTORY_INVALID",
    "closed raw Evidence manifest schema invalid",
  );
  assert(
    isDeepStrictEqual(manifest.task_ids, ACCEPTED_TASK_IDS),
    "TASK_SET_INVALID",
    "closed raw Evidence task set or order drifted",
  );
  const rebuilt = buildClosedEvidenceManifest(absolute, manifest.task_ids);
  assert(
    isDeepStrictEqual(manifest, rebuilt),
    "CLOSED_INVENTORY_DRIFT",
    "frozen raw Evidence inventory differs from the closed manifest",
  );
  assert(
    Number.isInteger(manifest.file_count)
      && manifest.file_count === manifest.entries.length
      && manifest.inventory_sha256 === inventoryDigest(manifest.entries),
    "CLOSED_INVENTORY_INVALID",
    "closed raw Evidence inventory accounting is invalid",
  );
  const manifestStat = lstatSync(manifestArtifact.path);
  assert(
    manifestStat.isFile()
      && !manifestStat.isSymbolicLink()
      && manifestStat.nlink === 1,
    "CLOSED_INVENTORY_PATH_INVALID",
    "closed raw Evidence manifest is not an owned single-link regular file",
  );
  return {
    schema_version: "p1-149-closed-raw-evidence-validation/v1",
    status: "PASS",
    task_ids: [...manifest.task_ids],
    file_count: manifest.file_count,
    inventory_sha256: manifest.inventory_sha256,
    manifest_identity: bytesIdentity(manifestArtifact.bytes),
  };
}

function parseCanonicalArtifact(artifacts, name, label = name) {
  return parseCanonicalJsonBytes(artifacts[name].bytes, label);
}

function parseCanonicalTrace(traceBytes) {
  const text = new TextDecoder("utf-8", { fatal: true }).decode(traceBytes);
  assert(
    text.endsWith("\n") && !text.endsWith("\n\n"),
    "TRACE_FRAMING_INVALID",
    "P1-101 trace framing invalid",
  );
  let events;
  try {
    events = text.slice(0, -1).split("\n").map((line) => JSON.parse(line));
  } catch (error) {
    assert(false, "TRACE_JSON_INVALID", `P1-101 trace JSON invalid: ${error.message}`);
  }
  assert(
    traceBytes.equals(Buffer.from(`${events.map((event) => canonicalJson(event)).join("\n")}\n`, "utf8")),
    "TRACE_NOT_CANONICAL",
    "P1-101 trace is not canonical JSONL",
  );
  return events;
}

function assertFalseEffects(value, label) {
  assert(
    isDeepStrictEqual(value, FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_FORBIDDEN",
    `${label} contains a non-false external effect`,
  );
}

function assertNoWorkerVerdict(value, label, path = []) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => assertNoWorkerVerdict(child, label, [...path, String(index)]));
    return;
  }
  if (value === null || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    assert(
      !FORBIDDEN_WORKER_VERDICT_KEYS.has(key),
      "UNTRUSTED_WORKER_VERDICT_REJECTED",
      `${label} contains forbidden worker verdict field: ${[...path, key].join(".")}`,
    );
    assertNoWorkerVerdict(child, label, [...path, key]);
  }
}

function verifyRecursiveIdentityBindings(taskRoot, value, label, path = []) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => (
      verifyRecursiveIdentityBindings(taskRoot, child, label, [...path, String(index)])
    ));
    return;
  }
  if (value === null || typeof value !== "object") return;
  const keys = Object.keys(value).sort();
  if (isDeepStrictEqual(keys, [...IDENTITY_KEYS].sort())) {
    const identityLabel = `${label}.${path.join(".") || "identity"}`;
    assertIdentityShape(value, identityLabel);
    const artifact = readBoundFile(taskRoot, value.path, identityLabel);
    assertExactIdentity(
      value,
      artifact.identity,
      "INTERNAL_IDENTITY_MISMATCH",
      identityLabel,
    );
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    verifyRecursiveIdentityBindings(taskRoot, child, label, [...path, key]);
  }
}

function validateCompilerArtifacts(taskId, artifacts) {
  const provider = artifacts["provider-response.json"].bytes;
  const extracted = extractPatchIrFromNormalizedResponse(provider);
  assert(
    extracted.response.task_id === taskId,
    "RESPONSE_TASK_BINDING_MISMATCH",
    "Provider response task binding drifted",
  );
  assert(
    extracted.patchIrBytes.equals(artifacts["patch-ir.json"].bytes),
    "PATCH_IR_IDENTITY_MISMATCH",
    "frozen Patch IR does not equal the exact response content",
  );
  const profile = loadAcceptedCompilerProfile(taskId);
  const rebuilt = compileNormalizedProviderResponse(provider, profile);
  const expectedPlanBytes = canonicalBytes(rebuilt.compiled.plan);
  assert(
    expectedPlanBytes.equals(artifacts["compiler-plan.json"].bytes),
    "COMPILER_PLAN_MISMATCH",
    "trusted compiler did not reconstruct the frozen compiler plan",
  );
  return {
    provider_response_identity: bytesIdentity(provider),
    patch_ir_identity: bytesIdentity(extracted.patchIrBytes),
    compiler_plan_identity: bytesIdentity(expectedPlanBytes),
    compiler_version: rebuilt.compiled.compiler_version,
  };
}

function artifactIdentity(artifacts, name) {
  return { path: name, ...bytesIdentity(artifacts[name].bytes) };
}

function validateTrace(taskId, artifacts, runRecord, stableProjection, values) {
  const traceBytes = artifacts["p1-101-trace.jsonl"].bytes;
  const events = parseCanonicalTrace(traceBytes);
  assert(
    events.length === EVENT_ORDER.length,
    "TRACE_EVENT_SEQUENCE_INVALID",
    "P1-101 trace event count invalid",
  );
  const runId = events[0]?.run_id;
  const binding = loadAcceptedTask(taskId);
  const expectedBindings = {
    task_spec: binding.task_spec.identity,
    environment_snapshot: artifactIdentity(artifacts, "environment.json"),
    system_configuration: artifactIdentity(artifacts, "system-configuration.json"),
    executable: artifactIdentity(artifacts, "executable.json"),
    input: artifactIdentity(artifacts, "input.json"),
    output: artifactIdentity(artifacts, "execution-spine.json"),
    run_record: artifactIdentity(artifacts, "run-record.json"),
    shared_request: artifactIdentity(artifacts, "input.json"),
    accepted_request: artifactIdentity(artifacts, "provider-response.json"),
    underlying_trace: artifactIdentity(artifacts, "execution-trace.jsonl"),
    underlying_stable_projection:
      artifactIdentity(artifacts, "execution-projection.json"),
  };
  for (const [index, event] of events.entries()) {
    assert(
      event.event_sequence === index + 1
        && event.event_type === EVENT_ORDER[index]
        && event.run_id === runId,
      "TRACE_EVENT_SEQUENCE_INVALID",
      "P1-101 event sequence, type, or run join drifted",
    );
    assert(
      isDeepStrictEqual(event.identity_bindings, expectedBindings),
      "TRACE_BINDING_MISMATCH",
      "P1-101 event identity bindings do not equal independently reconstructed bindings",
    );
    assertFalseEffects(event.external_effects, `P1-101 ${event.event_type} event`);
  }
  assert(
    typeof runId === "string"
      && runId.length > 0
      && runRecord.run_id === runId
      && runRecord.task_id === taskId,
    "RUN_RECORD_BINDING_MISMATCH",
    "RunRecord does not join the frozen trace and task",
  );
  assert(
    isDeepStrictEqual(stableProjection.event_order, EVENT_ORDER)
      && stableProjection.task_id === taskId,
    "STABLE_PROJECTION_BINDING_MISMATCH",
    "stable projection does not bind the frozen task and event order",
  );
  assertFalseEffects(stableProjection.external_effects, "P1-101 stable projection");
  const resultEvent = events[3];
  const rollbackEvent = events[4];
  const executionEvent = events[1];
  const plan = values["compiler-plan.json"];
  const expectedChildOperations = [
    ...plan.operations.map((operation, index) => ({
      sequence: index + 1,
      action_id: `apply-${index + 1}`,
      tool_class: "local-file-edit",
      operation_id: `patch_ir.${operation.op}`,
      exit_code: 0,
    })),
    ...binding.task.verification.required_commands.map((command, index) => ({
      sequence: plan.operations.length + index + 1,
      action_id: `test-${command.command_id}`,
      tool_class: "local-node-test",
      operation_id: `task_test.${command.command_id}`,
      exit_code: commandExit(values["test-receipt.json"], command.command_id),
    })),
    {
      sequence: plan.operations.length
        + binding.task.verification.required_commands.length
        + 1,
      action_id: "rollback",
      tool_class: "local-file-edit",
      operation_id: "repository.rollback",
      exit_code: 0,
    },
  ];
  assert(
    executionEvent.accepted_child?.adapter_id === "P1_149_EXECUTION_SPINE"
      && executionEvent.accepted_child?.operation_id === null
      && executionEvent.accepted_child?.real_invocation === true
      && isDeepStrictEqual(
        executionEvent.accepted_child?.identity,
        artifactIdentity(artifacts, "child-command.json"),
      ),
    "CHILD_INVOCATION_IDENTITY_MISMATCH",
    "P1-101 execution event does not bind the generic execution spine child",
  );
  assert(
    isDeepStrictEqual(
      executionEvent.event_data?.child_command,
      artifactIdentity(artifacts, "child-command.json"),
    )
      && isDeepStrictEqual(
        executionEvent.event_data?.child_worker_result,
        artifactIdentity(artifacts, "worker-result.json"),
      )
      && isDeepStrictEqual(
        executionEvent.event_data?.child_operations,
        expectedChildOperations,
      ),
    "CHILD_INVOCATION_IDENTITY_MISMATCH",
    "P1-101 execution event child Evidence differs from independently reconstructed operations",
  );
  assert(
    events[0].event_data?.admitted === true
      && events[0].event_data?.request_id === runId
      && events[0].event_data?.accepted_adapter_version === EXECUTION_SPINE_VERSION
      && events[2].event_data?.terminal_status === runRecord.terminal_status
      && events[2].event_data?.stop_reason_code === runRecord.stop_reason_code
      && isDeepStrictEqual(
        events[2].event_data?.policy_violations,
        runRecord.policy_violations,
      )
      && isDeepStrictEqual(
        events[2].event_data?.observed_external_effects,
        FALSE_EXTERNAL_EFFECTS,
      ),
    "TRACE_EVENT_SEMANTICS_INVALID",
    "P1-101 admission or validation event semantics drifted",
  );
  assert(
    resultEvent.event_data?.run_record?.sha256
      === artifacts["run-record.json"].identity.sha256
      && resultEvent.event_data?.run_record?.byte_length
      === artifacts["run-record.json"].identity.byte_length,
    "RUN_RECORD_BINDING_MISMATCH",
    "P1-101 result event does not bind the frozen RunRecord",
  );
  assert(
    resultEvent.event_data?.adapter_id === "P1_149_EXECUTION_SPINE"
      && resultEvent.event_data?.adapter_version === EXECUTION_SPINE_VERSION
      && isDeepStrictEqual(
        resultEvent.event_data?.output,
        artifactIdentity(artifacts, "execution-spine.json"),
      )
      && isDeepStrictEqual(
        resultEvent.event_data?.run_record,
        artifactIdentity(artifacts, "run-record.json"),
      ),
    "TRACE_EVENT_SEMANTICS_INVALID",
    "P1-101 result event semantics drifted",
  );
  const rollback = values["rollback-receipt.json"];
  const expectedAdapterRollback = {
    status: rollback.status,
    applied_operation_count: rollback.applied_operation_count,
    pre_snapshot: rollback.pre_snapshot,
    restored_snapshot: rollback.restored_snapshot,
  };
  assert(
    rollbackEvent.event_data?.source_state_restored === true
      && isDeepStrictEqual(
        rollbackEvent.event_data?.rollback,
        expectedAdapterRollback,
      ),
    "ROLLBACK_STATE_IDENTITY_MISMATCH",
    "P1-101 rollback event does not prove the independently reconstructed restored state",
  );
  assert(
    events.every((event, index) => (
      index === 1 ? event.accepted_child !== null : event.accepted_child === null
    )),
    "TRACE_EVENT_SEMANTICS_INVALID",
    "P1-101 accepted child appears outside the execution event",
  );
  return { events, run_id: runId, identity_bindings: expectedBindings };
}

function validateP1101Receipts(artifacts, expectedCleanStateIdentity) {
  const replayReceipt = parseCanonicalArtifact(
    artifacts,
    "p1-101-replay-receipt.json",
    "P1-101 replay receipt",
  );
  validateReplayReceipt({
    traceBytes: artifacts["p1-101-trace.jsonl"].bytes,
    projectionBytes: artifacts["p1-101-stable-projection.json"].bytes,
    runRecordBytes: artifacts["run-record.json"].bytes,
    receipt: replayReceipt,
  });
  const rollbackReceipt = parseCanonicalArtifact(
    artifacts,
    "p1-101-adapter-rollback-receipt.json",
    "P1-101 adapter rollback receipt",
  );
  validateRollbackReceipt({
    runRecordBytes: artifacts["run-record.json"].bytes,
    cleanStateIdentity: expectedCleanStateIdentity,
    receipt: rollbackReceipt,
  });
  return {
    replay_receipt_identity: bytesIdentity(artifacts["p1-101-replay-receipt.json"].bytes),
    adapter_rollback_receipt_identity:
      bytesIdentity(artifacts["p1-101-adapter-rollback-receipt.json"].bytes),
  };
}

function validateSnapshot(value, label) {
  exactKeys(value, ["schema_version", "entries"], label);
  assert(
    value.schema_version === "p1-149-directory-snapshot/v1"
      && Array.isArray(value.entries)
      && isDeepStrictEqual(
        value.entries.map((entry) => entry.path),
        value.entries.map((entry) => entry.path).sort(),
      ),
    "SNAPSHOT_INVALID",
    `${label} is not a sorted P1-149 directory snapshot`,
  );
  for (const entry of value.entries) {
    exactKeys(
      entry,
      ["path", "type", "mode", "byte_length", "sha256"],
      `${label} entry`,
    );
    validateArtifactPath(entry.path, `${label} entry path`);
    assert(
      entry.type === "REGULAR_FILE"
        && /^[0-7]{3}$/.test(entry.mode)
        && Number.isInteger(entry.byte_length)
        && entry.byte_length >= 0
        && /^[0-9a-f]{64}$/.test(entry.sha256),
      "SNAPSHOT_INVALID",
      `${label} entry invalid`,
    );
  }
}

function validateCommandReceipt(receipt, expectedCommandId, label) {
  exactKeys(
    receipt,
    [
      "schema_version",
      "command_id",
      "role",
      "argv",
      "expected_exit_codes",
      "observed_exit_status",
      "observed_signal",
      "stdout",
      "stderr",
      "external_effects",
    ],
    label,
  );
  assert(
    receipt.schema_version === "p1-149-test-command-receipt/v1"
      && receipt.command_id === expectedCommandId
      && Array.isArray(receipt.argv)
      && receipt.argv.length >= 1
      && receipt.argv.every((value) => typeof value === "string" && !value.includes("\0"))
      && isDeepStrictEqual(receipt.expected_exit_codes, [0])
      && (receipt.observed_exit_status === null
        || Number.isInteger(receipt.observed_exit_status))
      && (receipt.observed_signal === null
        || typeof receipt.observed_signal === "string"),
    "TEST_RECEIPT_INVALID",
    `${label} command semantics invalid`,
  );
  for (const streamName of ["stdout", "stderr"]) {
    const stream = receipt[streamName];
    exactKeys(stream, ["base64", "identity"], `${label} ${streamName}`);
    exactKeys(stream.identity, ["sha256", "byte_length"], `${label} ${streamName} identity`);
    assert(
      typeof stream.base64 === "string"
        && /^[0-9a-f]{64}$/.test(stream.identity.sha256)
        && Number.isInteger(stream.identity.byte_length)
        && stream.identity.byte_length >= 0,
      "TEST_RECEIPT_INVALID",
      `${label} ${streamName} encoding invalid`,
    );
    const bytes = Buffer.from(stream.base64, "base64");
    assert(
      bytes.toString("base64") === stream.base64
        && isDeepStrictEqual(bytesIdentity(bytes), stream.identity),
      "TEST_RECEIPT_INVALID",
      `${label} ${streamName} identity drifted`,
    );
  }
  assertFalseEffects(receipt.external_effects, label);
}

function validateTestReceipt(receipt, taskId, stage, label) {
  exactKeys(
    receipt,
    ["schema_version", "task_id", "stage", "commands", "external_effects"],
    label,
  );
  assert(
    receipt.schema_version === "p1-149-test-receipt/v1"
      && receipt.task_id === taskId
      && receipt.stage === stage
      && Array.isArray(receipt.commands)
      && receipt.commands.length === 2,
    "TEST_RECEIPT_INVALID",
    `${label} binding invalid`,
  );
  validateCommandReceipt(receipt.commands[0], "issue-test", `${label} issue-test`);
  validateCommandReceipt(receipt.commands[1], "regression-test", `${label} regression-test`);
  assertFalseEffects(receipt.external_effects, label);
}

function commandExit(receipt, commandId) {
  const command = receipt.commands.find((candidate) => candidate.command_id === commandId);
  assert(command, "TEST_RECEIPT_INVALID", `missing test command: ${commandId}`);
  return command.observed_exit_status;
}

function validateExecutionTrace(traceBytes, taskId, expectedIdentities) {
  const events = parseCanonicalTrace(traceBytes);
  const order = [
    ["response_admitted", "provider-response.json"],
    ["ir_compiled", "compiler-plan.json"],
    ["owned_copy_applied", "apply-receipt.json"],
    ["oracle_and_tests_observed", "oracle-receipt.json"],
    ["exact_rollback_observed", "rollback-receipt.json"],
  ];
  assert(
    events.length === order.length,
    "EXECUTION_TRACE_SEQUENCE_INVALID",
    "execution trace event count invalid",
  );
  for (const [index, event] of events.entries()) {
    exactKeys(
      event,
      ["schema_version", "sequence", "event_type", "task_id", "identity"],
      `execution trace event ${index + 1}`,
    );
    const [eventType, artifactName] = order[index];
    exactKeys(event.identity, ["sha256", "byte_length"], `execution trace event ${index + 1} identity`);
    assert(
      event.schema_version === "p1-149-execution-event/v1"
        && event.sequence === index + 1
        && event.event_type === eventType
        && event.task_id === taskId
        && isDeepStrictEqual(event.identity, expectedIdentities[artifactName]),
      "EXECUTION_TRACE_SEQUENCE_INVALID",
      `execution trace event ${index + 1} binding drifted`,
    );
  }
  return events;
}

function validateWorkerAndRunRecord(taskId, values, artifacts) {
  const worker = values["worker-result.json"];
  exactKeys(
    worker,
    [
      "schema_version",
      "run_id",
      "task_id",
      "execution_projection",
      "oracle_receipt",
      "rollback_receipt",
      "observed_classification",
      "evaluator_must_reconstruct_from_raw_evidence",
      "external_effects",
    ],
    "worker result",
  );
  assert(
    worker.schema_version === "p1-149-worker-result/v1"
      && worker.task_id === taskId
      && worker.evaluator_must_reconstruct_from_raw_evidence === true
      && ["VERIFIED_SUCCESS", "FAILED"].includes(worker.observed_classification),
    "WORKER_RESULT_INVALID",
    "worker result contract invalid",
  );
  assertFalseEffects(worker.external_effects, "worker result");
  const expectedBytesOnly = (name) => bytesIdentity(artifacts[name].bytes);
  assert(
    isDeepStrictEqual(worker.execution_projection, expectedBytesOnly("execution-projection.json"))
      && isDeepStrictEqual(worker.oracle_receipt, expectedBytesOnly("oracle-receipt.json"))
      && isDeepStrictEqual(worker.rollback_receipt, expectedBytesOnly("rollback-receipt.json")),
    "WORKER_RESULT_BINDING_MISMATCH",
    "worker result raw artifact bindings drifted",
  );

  const runRecord = values["run-record.json"];
  exactKeys(
    runRecord,
    [
      "schema_version",
      "run_id",
      "task_id",
      "dataset_version",
      "adapter_id",
      "adapter_version",
      "environment_snapshot_id",
      "terminal_status",
      "stop_reason_code",
      "policy_violations",
      "execution_projection",
      "external_effects",
    ],
    "P1-149 RunRecord",
  );
  assert(
    runRecord.schema_version === "p1-149-run-record/v1"
      && runRecord.run_id === worker.run_id
      && runRecord.task_id === taskId
      && runRecord.dataset_version === "1.0.0"
      && runRecord.adapter_id === "P1_149_EXECUTION_SPINE"
      && runRecord.adapter_version === EXECUTION_SPINE_VERSION
      && runRecord.terminal_status === "COMPLETED"
      && runRecord.stop_reason_code === "NONE"
      && isDeepStrictEqual(runRecord.policy_violations, [])
      && isDeepStrictEqual(
        runRecord.execution_projection,
        expectedBytesOnly("execution-projection.json"),
      ),
    "RUN_RECORD_BINDING_MISMATCH",
    "P1-149 RunRecord binding drifted",
  );
  assertFalseEffects(runRecord.external_effects, "P1-149 RunRecord");
  return { worker, runRecord };
}

function reconstructExecutionProjection(taskId, artifacts, values, compiler) {
  const binding = loadAcceptedTask(taskId);
  const pre = values["pre-snapshot.json"];
  const post = values["post-snapshot.json"];
  validateSnapshot(pre, "pre-application snapshot");
  validateSnapshot(post, "post-application snapshot");
  const preIdentity = bytesIdentity(artifacts["pre-snapshot.json"].bytes);
  const postIdentity = bytesIdentity(artifacts["post-snapshot.json"].bytes);
  const plan = values["compiler-plan.json"];
  const apply = values["apply-receipt.json"];
  exactKeys(
    apply,
    [
      "schema_version",
      "task_id",
      "compiler_plan",
      "pre_snapshot",
      "post_snapshot",
      "applied_operations",
      "changed_paths",
      "target",
      "canonical_source_written",
      "external_effects",
    ],
    "apply receipt",
  );
  assert(
    apply.schema_version === "p1-149-apply-receipt/v1"
      && apply.task_id === taskId
      && isDeepStrictEqual(apply.compiler_plan, compiler.compiler_plan_identity)
      && isDeepStrictEqual(apply.pre_snapshot, preIdentity)
      && isDeepStrictEqual(apply.post_snapshot, postIdentity)
      && apply.target === "UNIQUE_OWNED_DISPOSABLE_REPOSITORY_COPY"
      && apply.canonical_source_written === false
      && isDeepStrictEqual(
        apply.changed_paths,
        plan.operations.map((operation) => operation.path),
      ),
    "APPLY_RECEIPT_INVALID",
    "apply receipt does not bind the exact compiled plan and snapshots",
  );
  assertFalseEffects(apply.external_effects, "apply receipt");

  const preTests = values["pre-test-receipt.json"];
  const tests = values["test-receipt.json"];
  validateTestReceipt(preTests, taskId, "PRE_APPLICATION", "pre-application test receipt");
  validateTestReceipt(tests, taskId, "POST_APPLICATION", "post-application test receipt");
  assert(
    commandExit(preTests, "issue-test") !== 0
      && commandExit(preTests, "regression-test") === 0,
    "ACCEPTED_BASELINE_DRIFT",
    "pre-application tests do not exhibit the accepted bounded issue",
  );

  const issueExit = commandExit(tests, "issue-test");
  const regressionExit = commandExit(tests, "regression-test");
  const derivedClassification =
    issueExit === 0 && regressionExit === 0 ? "VERIFIED_SUCCESS" : "FAILED";
  const oracle = values["oracle-receipt.json"];
  exactKeys(
    oracle,
    [
      "schema_version",
      "task_id",
      "observed_precondition",
      "independently_observed_postcondition",
      "test_receipt",
      "result_classification",
      "external_effects",
    ],
    "oracle receipt",
  );
  assert(
    oracle.schema_version === "p1-149-oracle-receipt/v1"
      && oracle.task_id === taskId
      && oracle.observed_precondition.issue_test_failed === true
      && oracle.observed_precondition.regression_test_passed === true
      && isDeepStrictEqual(oracle.test_receipt, bytesIdentity(artifacts["test-receipt.json"].bytes))
      && oracle.result_classification === derivedClassification
      && oracle.independently_observed_postcondition.issue_test_passed === (issueExit === 0)
      && oracle.independently_observed_postcondition.regression_test_passed
        === (regressionExit === 0)
      && oracle.independently_observed_postcondition.changed_paths_equal_compiler_plan === true,
    "ORACLE_RECEIPT_INVALID",
    "oracle receipt differs from independently reconstructed raw test evidence",
  );
  assertFalseEffects(oracle.external_effects, "oracle receipt");

  const rollback = values["rollback-receipt.json"];
  exactKeys(
    rollback,
    [
      "schema_version",
      "task_id",
      "status",
      "applied_operation_count",
      "pre_snapshot",
      "restored_snapshot",
      "canonical_source_written",
      "external_effects",
    ],
    "rollback receipt",
  );
  assert(
    rollback.schema_version === "p1-149-rollback-receipt/v1"
      && rollback.task_id === taskId
      && rollback.status === "PASS_EXACT"
      && rollback.applied_operation_count === plan.operations.length
      && isDeepStrictEqual(rollback.pre_snapshot, preIdentity)
      && isDeepStrictEqual(rollback.restored_snapshot, preIdentity)
      && rollback.canonical_source_written === false,
    "ROLLBACK_STATE_IDENTITY_MISMATCH",
    "rollback receipt did not restore the exact pre-application snapshot",
  );
  assertFalseEffects(rollback.external_effects, "rollback receipt");

  const expected = {
    schema_version: "p1-149-execution-stable-projection/v1",
    execution_spine_version: EXECUTION_SPINE_VERSION,
    task_id: taskId,
    dataset: {
      id: binding.manifest.dataset_id,
      version: binding.manifest.dataset_version,
      manifest_sha256: binding.manifest_identity.sha256,
    },
    compiler: {
      version: compiler.compiler_version,
      input_schema: "SL-PATCH-IR/2",
      finite_operation_limit: 3,
      total_postimage_byte_limit: 65536,
    },
    application: {
      target: "UNIQUE_OWNED_DISPOSABLE_REPOSITORY_COPY",
      pre_snapshot: preIdentity,
      verification_commands: binding.task.verification.required_commands.map(
        (command) => command.command_id,
      ),
    },
    validation: {
      independent_evaluator_required: true,
      raw_outcome_retained_outside_stable_projection: true,
    },
    rollback: {
      exact_pre_application_snapshot_required: true,
    },
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  assert(
    isDeepStrictEqual(values["execution-projection.json"], expected),
    "EXECUTION_PROJECTION_MISMATCH",
    "execution projection was not independently reconstructed from raw artifacts",
  );
  return {
    binding,
    plan,
    preIdentity,
    postIdentity,
    issueExit,
    regressionExit,
    derivedClassification,
    executionProjection: expected,
    rollback,
  };
}

function reconstructP1101StableProjection(
  taskId,
  artifacts,
  values,
  runRecord,
  reconstruction,
) {
  const binding = reconstruction.binding;
  const adapterResult = {
    run_id: runRecord.run_id,
    adapter_version: EXECUTION_SPINE_VERSION,
    actions: [
      ...reconstruction.plan.operations.map((operation, index) => ({
        sequence: index + 1,
        action_id: `apply-${index + 1}`,
        tool_class: "local-file-edit",
        operation_id: `patch_ir.${operation.op}`,
        exit_code: 0,
      })),
      ...binding.task.verification.required_commands.map((command, index) => ({
        sequence: reconstruction.plan.operations.length + index + 1,
        action_id: `test-${command.command_id}`,
        tool_class: "local-node-test",
        operation_id: `task_test.${command.command_id}`,
        exit_code: commandExit(values["test-receipt.json"], command.command_id),
      })),
      {
        sequence: reconstruction.plan.operations.length
          + binding.task.verification.required_commands.length
          + 1,
        action_id: "rollback",
        tool_class: "local-file-edit",
        operation_id: "repository.rollback",
        exit_code: 0,
      },
    ],
    observed_external_effects: FALSE_EXTERNAL_EFFECTS,
    rollback: {
      status: "PASS_EXACT",
      applied_operation_count: reconstruction.plan.operations.length,
      pre_snapshot: reconstruction.preIdentity,
      restored_snapshot: reconstruction.preIdentity,
    },
  };
  const identity = (name) => ({ path: name, ...bytesIdentity(artifacts[name].bytes) });
  const expected = buildStableProjection({
    runRecord,
    taskSpecIdentity: binding.task_spec.identity,
    environmentIdentity: identity("environment.json"),
    executableIdentity: identity("executable.json"),
    inputIdentity: identity("input.json"),
    underlyingProjection: reconstruction.executionProjection,
    adapterResult,
  });
  assert(
    isDeepStrictEqual(values["p1-101-stable-projection.json"], expected),
    "STABLE_PROJECTION_MISMATCH",
    "P1-101 stable projection was not independently reconstructed from raw artifacts",
  );
  return expected;
}

function assertRollbackAndTaxonomy(taskId, artifacts, values, compiler) {
  const joined = validateWorkerAndRunRecord(taskId, values, artifacts);
  const reconstruction = reconstructExecutionProjection(
    taskId,
    artifacts,
    values,
    compiler,
  );
  validateExecutionTrace(
    artifacts["execution-trace.jsonl"].bytes,
    taskId,
    Object.fromEntries(
      REQUIRED_TASK_ARTIFACTS.map((name) => [name, bytesIdentity(artifacts[name].bytes)]),
    ),
  );
  const stableProjection = reconstructP1101StableProjection(
    taskId,
    artifacts,
    values,
    joined.runRecord,
    reconstruction,
  );
  return {
    runRecord: joined.runRecord,
    reconstruction,
    stableProjection,
  };
}

function taskArtifactMap(evidenceRoot, taskId, manifestEntries) {
  const taskRootRelative = `tasks/${taskId}`;
  const taskRoot = containedPath(evidenceRoot, taskRootRelative, `${taskId} Evidence directory`);
  safeRealDirectory(taskRoot, `${taskId} Evidence directory`);
  const paths = manifestEntries
    .map((entry) => entry.path)
    .filter((path) => path.startsWith(`${taskRootRelative}/`))
    .map((path) => path.slice(taskRootRelative.length + 1))
    .sort();
  assert(
    isDeepStrictEqual(paths, [...REQUIRED_TASK_ARTIFACTS].sort()),
    "TASK_ARTIFACT_SET_INVALID",
    `${taskId} raw artifact set is not closed`,
    { actual: paths, expected: [...REQUIRED_TASK_ARTIFACTS].sort() },
  );
  const artifacts = {};
  for (const name of REQUIRED_TASK_ARTIFACTS) {
    const artifact = readBoundFile(taskRoot, name, `${taskId} ${name}`);
    const rootEntry = manifestEntries.find(
      (entry) => entry.path === `${taskRootRelative}/${name}`,
    );
    assert(rootEntry, "CLOSED_INVENTORY_INVALID", `${taskId} ${name} is absent from top inventory`);
    assertExactIdentity(
      { sha256: rootEntry.sha256, byte_length: rootEntry.byte_length },
      bytesIdentity(artifact.bytes),
      "CLOSED_INVENTORY_DRIFT",
      `${taskId} ${name}`,
    );
    artifacts[name] = {
      ...artifact,
      identity: { path: name, ...bytesIdentity(artifact.bytes) },
    };
  }
  return { taskRoot, artifacts };
}

export function verifyFrozenTaskEvidence(evidenceRoot, taskId, manifest = null) {
  assert(
    ACCEPTED_TASK_IDS.includes(taskId),
    "UNKNOWN_TASK_REJECTED",
    "frozen task is outside the accepted six-task set",
  );
  const root = safeRealDirectory(evidenceRoot, "frozen raw Evidence root");
  const manifestValue = manifest ?? parseCanonicalJsonBytes(
    readBoundFile(root, RAW_EVIDENCE_MANIFEST, "closed raw Evidence manifest").bytes,
    "closed raw Evidence manifest",
  );
  const { taskRoot, artifacts } = taskArtifactMap(root, taskId, manifestValue.entries);
  const values = {};
  for (const name of REQUIRED_TASK_ARTIFACTS.filter((name) => name.endsWith(".json"))) {
    values[name] = parseCanonicalArtifact(artifacts, name, `${taskId} ${name}`);
  }
  assertNoWorkerVerdict(values["execution-spine.json"], `${taskId} execution spine`);
  assertNoWorkerVerdict(values["run-record.json"], `${taskId} RunRecord`);
  verifyRecursiveIdentityBindings(
    taskRoot,
    values["execution-spine.json"],
    `${taskId} execution spine`,
  );
  const compiler = validateCompilerArtifacts(taskId, artifacts);
  const trace = validateTrace(
    taskId,
    artifacts,
    values["run-record.json"],
    values["p1-101-stable-projection.json"],
    values,
  );
  const reconstructed = assertRollbackAndTaxonomy(
    taskId,
    artifacts,
    values,
    compiler,
  );
  const p1101 = validateP1101Receipts(
    artifacts,
    reconstructed.reconstruction.preIdentity,
  );
  return {
    schema_version: "p1-149-frozen-task-evidence-validation/v1",
    status: "PASS",
    task_id: taskId,
    run_id: trace.run_id,
    task_root: `tasks/${taskId}`,
    provider_response_identity: compiler.provider_response_identity,
    patch_ir_identity: compiler.patch_ir_identity,
    compiler_plan_identity: compiler.compiler_plan_identity,
    compiler_version: compiler.compiler_version,
    trace_identity: bytesIdentity(artifacts["p1-101-trace.jsonl"].bytes),
    stable_projection_identity:
      bytesIdentity(artifacts["p1-101-stable-projection.json"].bytes),
    rollback_receipt_identity: bytesIdentity(artifacts["rollback-receipt.json"].bytes),
    independently_reconstructed_projection_identity:
      bytesIdentity(canonicalBytes(reconstructed.stableProjection)),
    ...p1101,
  };
}

export function verifyFrozenExecutionEvidence(root) {
  const closed = validateClosedEvidenceRoot(root);
  const absolute = safeRealDirectory(root, "frozen raw Evidence root");
  const manifest = parseCanonicalJsonBytes(
    readBoundFile(absolute, RAW_EVIDENCE_MANIFEST, "closed raw Evidence manifest").bytes,
    "closed raw Evidence manifest",
  );
  for (const required of ["run-plan.json", "p1-055-v1-compatibility.json"]) {
    assert(
      manifest.entries.some((entry) => entry.path === required),
      "CLOSED_INVENTORY_INVALID",
      `required raw Evidence artifact missing: ${required}`,
    );
  }
  const runPlanArtifact = readBoundFile(
    absolute,
    "run-plan.json",
    "P1-149 preflight run plan",
  );
  const runPlan = parseCanonicalJsonBytes(
    runPlanArtifact.bytes,
    "P1-149 preflight run plan",
  );
  exactKeys(
    runPlan,
    ["schema_version", "task_ids", "execution_order", "claim_boundary"],
    "P1-149 preflight run plan",
  );
  assert(
    runPlan.schema_version === "p1-149-preflight-run-plan/v1"
      && isDeepStrictEqual(runPlan.task_ids, ACCEPTED_TASK_IDS)
      && runPlan.claim_boundary === READINESS_CLAIM_BOUNDARY
      && Array.isArray(runPlan.execution_order)
      && runPlan.execution_order.length === ACCEPTED_TASK_IDS.length,
    "RUN_PLAN_INVALID",
    "P1-149 preflight run plan root binding invalid",
  );
  for (const [index, entry] of runPlan.execution_order.entries()) {
    exactKeys(
      entry,
      ["ordinal", "task_id", "artifact_root", "response", "stable_projection"],
      `P1-149 run plan entry ${index + 1}`,
    );
    const taskId = ACCEPTED_TASK_IDS[index];
    assert(
      entry.ordinal === index + 1
        && entry.task_id === taskId
        && entry.artifact_root === `tasks/${taskId}`,
      "RUN_PLAN_INVALID",
      `P1-149 run plan entry ${index + 1} order or task binding drifted`,
    );
    for (const [key, expectedPath] of [
      ["response", `tasks/${taskId}/provider-response.json`],
      ["stable_projection", `tasks/${taskId}/p1-101-stable-projection.json`],
    ]) {
      assertIdentityShape(entry[key], `P1-149 run plan ${taskId} ${key}`);
      assert(
        entry[key].path === expectedPath,
        "RUN_PLAN_INVALID",
        `P1-149 run plan ${taskId} ${key} path drifted`,
      );
      const artifact = readBoundFile(
        absolute,
        expectedPath,
        `P1-149 run plan ${taskId} ${key}`,
      );
      assertExactIdentity(
        entry[key],
        { path: expectedPath, ...bytesIdentity(artifact.bytes) },
        "RUN_PLAN_INVALID",
        `P1-149 run plan ${taskId} ${key}`,
      );
    }
  }
  const v1Artifact = readBoundFile(
    absolute,
    "p1-055-v1-compatibility.json",
    "P1-055 v1 compatibility receipt",
  );
  const expectedV1Bytes = canonicalBytes(verifyAcceptedPatchIrV1Compatibility());
  assert(
    v1Artifact.bytes.equals(expectedV1Bytes),
    "P1_055_V1_COMPATIBILITY_DRIFT",
    "frozen P1-055 v1 compatibility receipt was not independently reconstructed",
  );
  const taskResults = ACCEPTED_TASK_IDS.map(
    (taskId) => verifyFrozenTaskEvidence(absolute, taskId, manifest),
  );
  assert(
    taskResults.length === 6
      && new Set(taskResults.map((entry) => entry.task_id)).size === 6
      && taskResults.every((entry) => entry.status === "PASS"),
    "TASK_SET_INVALID",
    "frozen raw Evidence did not validate all six accepted tasks exactly once",
  );
  return {
    schema_version: "p1-149-frozen-execution-evidence-validation/v1",
    status: "PASS",
    claim_boundary: READINESS_CLAIM_BOUNDARY,
    closed_inventory: closed,
    run_plan_identity: bytesIdentity(runPlanArtifact.bytes),
    p1_055_v1_compatibility_identity: bytesIdentity(v1Artifact.bytes),
    task_results: taskResults,
    external_effects: deepClone(FALSE_EXTERNAL_EFFECTS),
  };
}

export function readFrozenProviderResponse(root, taskId) {
  const absolute = safeRealDirectory(root, "frozen raw Evidence root");
  const relativePath = `tasks/${taskId}/provider-response.json`;
  const artifact = readBoundFile(absolute, relativePath, `${taskId} Provider response`);
  return Buffer.from(artifact.bytes);
}

export function readFrozenStableProjection(root, taskId) {
  const absolute = safeRealDirectory(root, "frozen raw Evidence root");
  const relativePath = `tasks/${taskId}/p1-101-stable-projection.json`;
  return parseCanonicalJsonBytes(
    readBoundFile(absolute, relativePath, `${taskId} stable projection`).bytes,
    `${taskId} stable projection`,
  );
}

export function buildReadinessCells(projectionByTask) {
  assert(
    projectionByTask instanceof Map
      && projectionByTask.size === ACCEPTED_TASK_IDS.length
      && ACCEPTED_TASK_IDS.every((taskId) => projectionByTask.has(taskId)),
    "READINESS_PROJECTION_SET_INVALID",
    "readiness projection set does not cover all six accepted tasks",
  );
  const cells = [];
  for (const [taskIndex, taskId] of ACCEPTED_TASK_IDS.entries()) {
    const projection = projectionByTask.get(taskId);
    const projectionIdentity = bytesIdentity(canonicalBytes(projection));
    for (const [profileIndex, profileId] of FIXED_PROFILE_ORDER.entries()) {
      cells.push({
        schema_version: "p1-149-readiness-cell/v1",
        ordinal: (taskIndex * FIXED_PROFILE_ORDER.length) + profileIndex + 1,
        task_id: taskId,
        profile_id: profileId,
        classification: "ACCEPTED_EXECUTION_SPINE_READINESS",
        included_in_denominator: true,
        projection_identity: projectionIdentity,
        claim_boundary: READINESS_CLAIM_BOUNDARY,
      });
    }
  }
  assert(
    cells.length === 36
      && cells.every((cell, index) => (
        cell.ordinal === index + 1
        && cell.included_in_denominator === true
        && cell.claim_boundary === READINESS_CLAIM_BOUNDARY
      )),
    "READINESS_DENOMINATOR_INVALID",
    "fixed readiness denominator is not exactly 36",
  );
  return cells;
}

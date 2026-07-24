import { isDeepStrictEqual } from "node:util";

import {
  FALSE_EXTERNAL_EFFECTS,
  canonicalBytes,
  canonicalJson,
  parseJsonBytes,
  sha256,
} from "../../harness/p1-097-minimal-documented/core.mjs";
import { EVENT_ORDER } from "../../recording/p1-101-accepted-shared-trace/trace.mjs";

export class TraceValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "TraceValidationError";
    this.code = code;
  }
}

function fail(code, message) {
  throw new TraceValidationError(code, message);
}

function assert(condition, code, message) {
  if (!condition) fail(code, message);
}

function parseTrace(traceBytes) {
  const text = traceBytes.toString("utf8");
  assert(text.endsWith("\n") && !text.endsWith("\n\n"), "TRACE_EVENT_IDENTITY_MISMATCH", "trace framing invalid");
  let events;
  try {
    events = text.trim().split("\n").map((line) => JSON.parse(line));
  } catch {
    fail("TRACE_EVENT_IDENTITY_MISMATCH", "trace JSON invalid");
  }
  assert(
    traceBytes.equals(Buffer.from(`${events.map((event) => canonicalJson(event)).join("\n")}\n`, "utf8")),
    "TRACE_EVENT_IDENTITY_MISMATCH",
    "trace is not canonical JSONL",
  );
  return events;
}

function bytesIdentity(bytes) {
  return { sha256: sha256(bytes), byte_length: bytes.length };
}

function traceBytesForEvents(events) {
  return Buffer.from(`${events.map((event) => canonicalJson(event)).join("\n")}\n`, "utf8");
}

export function buildAdmissionValidationInput({
  events,
  outputIdentity,
  runRecordIdentity,
  childInvocations,
  outputInventory,
}) {
  return {
    schema_version: "p1-101-admission-validation-input/v1",
    trace_events: structuredClone(events),
    output_identity: structuredClone(outputIdentity),
    run_record_identity: structuredClone(runRecordIdentity),
    child_invocations: structuredClone(childInvocations),
    output_inventory: structuredClone(outputInventory),
  };
}

export function validateAdmissionInput(candidate, expected) {
  assert(
    Array.isArray(candidate.trace_events),
    "TRACE_EVENT_IDENTITY_MISMATCH",
    "trace events are not an array",
  );
  const events = candidate.trace_events;
  assert(
    events.length === EVENT_ORDER.length
      && events.every((event, index) => (
        event.event_sequence === index + 1
        && event.event_type === EVENT_ORDER[index]
      )),
    "TRACE_EVENT_SEQUENCE_INVALID",
    "required trace sequence is missing or reordered",
  );
  assert(
    isDeepStrictEqual(bytesIdentity(traceBytesForEvents(events)), expected.trace_identity),
    "TRACE_EVENT_IDENTITY_MISMATCH",
    "trace event bytes differ from the frozen identity",
  );
  assert(
    isDeepStrictEqual(candidate.output_identity, expected.output_identity),
    "OUTPUT_IDENTITY_MISMATCH",
    "output identity drifted",
  );
  assert(
    isDeepStrictEqual(candidate.run_record_identity, expected.run_record_identity),
    "RUN_RECORD_IDENTITY_MISMATCH",
    "RunRecord identity drifted",
  );
  assert(
    isDeepStrictEqual(candidate.child_invocations, expected.child_invocations),
    expected.adapter_id === "B2"
      ? "CHILD_INVOCATION_IDENTITY_MISMATCH"
      : "UNDECLARED_CHILD_INVOCATION",
    "child invocation set drifted",
  );
  assert(
    isDeepStrictEqual(candidate.output_inventory, expected.output_inventory),
    "UNEXPECTED_OUTPUT",
    "output inventory contains an undeclared artifact",
  );
  return true;
}

export function validateObservableTrace({
  traceBytes,
  expectedRunId,
  expectedBindings,
  expectedAdapterId,
}) {
  const events = parseTrace(traceBytes);
  assert(events.length === EVENT_ORDER.length, "TRACE_EVENT_SEQUENCE_INVALID", "required event missing");
  for (const [index, event] of events.entries()) {
    assert(
      event.event_sequence === index + 1
        && event.event_type === EVENT_ORDER[index]
        && event.run_id === expectedRunId,
      "TRACE_EVENT_SEQUENCE_INVALID",
      "trace order or join invalid",
    );
    assert(
      isDeepStrictEqual(event.identity_bindings, expectedBindings),
      "TRACE_EVENT_IDENTITY_MISMATCH",
      "identity binding drifted",
    );
    assert(
      isDeepStrictEqual(event.external_effects, FALSE_EXTERNAL_EFFECTS),
      "EXTERNAL_EFFECT_FORBIDDEN",
      "trace contains external effects",
    );
  }
  const execution = events[1];
  assert(
    execution.accepted_child?.adapter_id === expectedAdapterId
      && execution.accepted_child?.real_invocation === true,
    expectedAdapterId === "B2"
      ? "CHILD_INVOCATION_IDENTITY_MISMATCH"
      : "UNDECLARED_CHILD_INVOCATION",
    "accepted child binding invalid",
  );
  if (expectedAdapterId === "B2") {
    assert(
      execution.accepted_child.operation_id === "repository_analysis.scan",
      "CHILD_INVOCATION_IDENTITY_MISMATCH",
      "B2 repository_analysis.scan child missing",
    );
  }
  return events;
}

export function replayStableProjection({
  traceBytes,
  projection,
  expectedProjection,
  runRecordBytes,
}) {
  assert(
    isDeepStrictEqual(projection, expectedProjection),
    "OUTPUT_IDENTITY_MISMATCH",
    "stable projection differs from replayed projection",
  );
  const projectionBytes = canonicalBytes(projection);
  return {
    schema_version: "p1-101-replay-receipt/v1",
    record_type: "p1_101_replay_receipt",
    status: "PASS",
    trace_identity: {
      sha256: sha256(traceBytes),
      byte_length: traceBytes.length,
    },
    projection_identity: {
      sha256: sha256(projectionBytes),
      byte_length: projectionBytes.length,
    },
    run_record_identity: {
      sha256: sha256(runRecordBytes),
      byte_length: runRecordBytes.length,
    },
    exact_projection_reproduced: true,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

export function validateReplayReceipt({
  traceBytes,
  projectionBytes,
  runRecordBytes,
  receipt,
}) {
  assert(receipt.status === "PASS", "REPLAY_RECEIPT_INVALID", "replay status is not PASS");
  assert(
    isDeepStrictEqual(receipt.trace_identity, bytesIdentity(traceBytes)),
    "TRACE_EVENT_IDENTITY_MISMATCH",
    "replay trace identity drifted",
  );
  assert(
    isDeepStrictEqual(receipt.projection_identity, bytesIdentity(projectionBytes)),
    "OUTPUT_IDENTITY_MISMATCH",
    "replay projection identity drifted",
  );
  assert(
    isDeepStrictEqual(receipt.run_record_identity, bytesIdentity(runRecordBytes)),
    "RUN_RECORD_IDENTITY_MISMATCH",
    "replay RunRecord identity drifted",
  );
  assert(
    receipt.exact_projection_reproduced === true
      && isDeepStrictEqual(receipt.external_effects, FALSE_EXTERNAL_EFFECTS),
    "REPLAY_RECEIPT_INVALID",
    "replay receipt semantics drifted",
  );
  return true;
}

export function buildRollbackReceipt({ runRecordBytes, adapterResult, cleanStateIdentity }) {
  const sourceStateRestored = adapterResult.rollback.status === "PASS_EXACT"
    || adapterResult.rollback.status === "NOT_APPLICABLE_NO_SOURCE_MUTATION"
    || adapterResult.rollback.status === "NOT_APPLICABLE_READ_ONLY_SCAN_SOURCE_UNCHANGED";
  assert(sourceStateRestored, "OUTPUT_IDENTITY_MISMATCH", "accepted adapter rollback did not restore source");
  return {
    schema_version: "p1-101-rollback-receipt/v1",
    record_type: "p1_101_rollback_receipt",
    status: "PASS",
    source_state_restored: true,
    run_record_identity: {
      sha256: sha256(runRecordBytes),
      byte_length: runRecordBytes.length,
    },
    clean_state_identity: cleanStateIdentity,
    adapter_rollback: adapterResult.rollback,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

export function validateRollbackReceipt({
  runRecordBytes,
  cleanStateIdentity,
  receipt,
}) {
  assert(
    receipt.status === "PASS" && receipt.source_state_restored === true,
    "ROLLBACK_RECEIPT_INVALID",
    "rollback status is not exact PASS",
  );
  assert(
    isDeepStrictEqual(receipt.run_record_identity, bytesIdentity(runRecordBytes)),
    "RUN_RECORD_IDENTITY_MISMATCH",
    "rollback RunRecord identity drifted",
  );
  assert(
    isDeepStrictEqual(receipt.clean_state_identity, cleanStateIdentity),
    "ROLLBACK_STATE_IDENTITY_MISMATCH",
    "rollback clean-state identity drifted",
  );
  assert(
    isDeepStrictEqual(receipt.external_effects, FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_FORBIDDEN",
    "rollback receipt contains external effects",
  );
  return true;
}

export function parseCanonicalJson(bytes, code) {
  const value = parseJsonBytes(bytes, code);
  assert(bytes.equals(canonicalBytes(value)), code, "artifact is not canonical JSON");
  return value;
}

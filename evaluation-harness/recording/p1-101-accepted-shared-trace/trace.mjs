import {
  FALSE_EXTERNAL_EFFECTS,
  canonicalBytes,
  canonicalJson,
  sha256,
} from "../../harness/p1-097-minimal-documented/core.mjs";

export const EVENT_ORDER = Object.freeze([
  "admission",
  "execution",
  "validation",
  "result",
  "rollback",
]);

function identity(bytes) {
  return { sha256: sha256(bytes), byte_length: bytes.length };
}

function childOperations(adapterResult) {
  return adapterResult.actions
    .filter((action) => action.tool_class !== null)
    .map((action) => ({
      sequence: action.sequence,
      action_id: action.action_id,
      tool_class: action.tool_class,
      operation_id: action.operation_id ?? null,
      exit_code: action.exit_code,
    }));
}

export function buildObservableTrace({
  sharedRequestIdentity,
  acceptedRequestIdentity,
  childCommandIdentity,
  childWorkerResultIdentity,
  taskSpecIdentity,
  environmentIdentity,
  configurationIdentity,
  executableIdentity,
  inputIdentity,
  outputIdentity,
  runRecordIdentity,
  underlyingTraceIdentity,
  underlyingProjectionIdentity,
  runRecord,
  adapterResult,
  childLedger,
}) {
  const identityBindings = {
    task_spec: taskSpecIdentity,
    environment_snapshot: environmentIdentity,
    system_configuration: configurationIdentity,
    executable: executableIdentity,
    input: inputIdentity,
    output: outputIdentity,
    run_record: runRecordIdentity,
    shared_request: sharedRequestIdentity,
    accepted_request: acceptedRequestIdentity,
    underlying_trace: underlyingTraceIdentity,
    underlying_stable_projection: underlyingProjectionIdentity,
  };
  const operations = childOperations(adapterResult);
  const acceptedChild = runRecord.adapter_id === "B2"
    ? {
        adapter_id: "B2",
        operation_id: "repository_analysis.scan",
        real_invocation: operations.some((operation) => (
          operation.operation_id === "repository_analysis.scan"
          && operation.tool_class === "repository_analysis.scan"
          && operation.exit_code === 0
        )),
        identity: childCommandIdentity,
      }
    : {
        adapter_id: runRecord.adapter_id,
        operation_id: null,
        real_invocation: true,
        identity: childCommandIdentity,
      };
  const common = {
    schema_version: "p1-101-observable-trace-event/v1",
    run_id: runRecord.run_id,
    identity_bindings: identityBindings,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const data = [
    {
      admitted: true,
      request_id: adapterResult.run_id,
      accepted_adapter_version: adapterResult.adapter_version,
    },
    {
      started_at: childLedger.started_at,
      ended_at: childLedger.ended_at,
      latency_ms: childLedger.latency_ms,
      child_command: childCommandIdentity,
      child_worker_result: childWorkerResultIdentity,
      child_operations: operations,
    },
    {
      terminal_status: runRecord.terminal_status,
      stop_reason_code: runRecord.stop_reason_code,
      policy_violations: runRecord.policy_violations,
      observed_external_effects: adapterResult.observed_external_effects,
    },
    {
      adapter_id: runRecord.adapter_id,
      adapter_version: runRecord.adapter_version,
      output: outputIdentity,
      run_record: runRecordIdentity,
    },
    {
      source_state_restored: adapterResult.rollback.status === "PASS_EXACT"
        || adapterResult.rollback.status === "NOT_APPLICABLE_NO_SOURCE_MUTATION"
        || adapterResult.rollback.status === "NOT_APPLICABLE_READ_ONLY_SCAN_SOURCE_UNCHANGED",
      rollback: adapterResult.rollback,
    },
  ];
  const events = EVENT_ORDER.map((eventType, index) => ({
    ...common,
    event_sequence: index + 1,
    event_type: eventType,
    accepted_child: index === 1 ? acceptedChild : null,
    event_data: data[index],
  }));
  return {
    events,
    bytes: Buffer.from(`${events.map((event) => canonicalJson(event)).join("\n")}\n`, "utf8"),
  };
}

export function buildStableProjection({
  runRecord,
  taskSpecIdentity,
  environmentIdentity,
  executableIdentity,
  inputIdentity,
  underlyingProjection,
  adapterResult,
}) {
  return {
    schema_version: "p1-101-stable-projection/v1",
    record_type: "p1_101_accepted_shared_execution_stable_projection",
    task_id: runRecord.task_id,
    dataset_version: runRecord.dataset_version,
    adapter_id: runRecord.adapter_id,
    adapter_version: runRecord.adapter_version,
    environment_snapshot_id: runRecord.environment_snapshot_id,
    event_order: EVENT_ORDER,
    deterministic_bindings: {
      task_spec: taskSpecIdentity,
      environment_snapshot: environmentIdentity,
      executable: executableIdentity,
      input: inputIdentity,
    },
    accepted_projection: underlyingProjection,
    child_operations: childOperations(adapterResult).map((operation) => ({
      sequence: operation.sequence,
      tool_class: operation.tool_class,
      operation_id: operation.operation_id,
      exit_code: operation.exit_code,
    })),
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

export function artifactIdentity(path, bytes) {
  return { path, ...identity(bytes) };
}

export function projectionBytes(value) {
  return canonicalBytes(value);
}

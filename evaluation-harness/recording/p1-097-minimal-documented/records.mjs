import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  canonicalBytes,
  canonicalJson,
  sha256,
} from "../../harness/p1-097-minimal-documented/core.mjs";
import { validateRunRecordSchema } from "../../harness/p1-097-minimal-documented/contracts.mjs";

export function buildTrace({
  contracts,
  commandLedger,
  adapterResult,
  adapterResultIdentity,
}) {
  assert(
    Array.isArray(adapterResult.actions)
      && adapterResult.actions.every((action, index) => (
        action.sequence === index + 1
        && action.action_id === `${adapterResult.run_id}:${index + 1}`
      )),
    "TRACE_JOIN_INVALID",
    "observable actions do not join to the unique run ID in sequence",
  );
  const common = {
    schema_version: "p1-097-observable-trace-event/v1",
    run_id: adapterResult.run_id,
    task_id: contracts.task.value.task_id,
    dataset_version: contracts.task.value.dataset_version,
    adapter_id: contracts.request.adapter_id,
    adapter_version: contracts.descriptor.adapter_version,
    environment_snapshot_id: contracts.environment.value.snapshot_id,
    system_configuration_id: contracts.configuration.value.configuration_id,
    repetition_id: contracts.request.repetition_id,
  };
  const started = {
    ...common,
    record_type: "p1_097_run_started",
    event_sequence: 1,
    started_at: commandLedger.started_at,
    input_bindings: {
      request: contracts.requestIdentity,
      descriptor: {
        path: contracts.descriptorRecord.path,
        sha256: sha256(contracts.descriptorRecord.bytes),
        byte_length: contracts.descriptorRecord.bytes.length,
      },
      task_spec: {
        path: contracts.task.path,
        sha256: sha256(contracts.task.bytes),
        byte_length: contracts.task.bytes.length,
      },
      environment_snapshot: {
        path: contracts.environment.path,
        sha256: sha256(contracts.environment.bytes),
        byte_length: contracts.environment.bytes.length,
      },
      system_configuration: {
        path: contracts.configuration.path,
        sha256: sha256(contracts.configuration.bytes),
        byte_length: contracts.configuration.bytes.length,
      },
      adapter_input: {
        path: contracts.adapterInput.path,
        sha256: sha256(contracts.adapterInput.bytes),
        byte_length: contracts.adapterInput.bytes.length,
      },
      auxiliary_inputs: Object.fromEntries(
        Object.entries(contracts.auxiliaryInputs).map(([name, record]) => [name, {
          path: record.path,
          sha256: sha256(record.bytes),
          byte_length: record.bytes.length,
        }]),
      ),
    },
    command: commandLedger,
    limits: {
      wall_clock_seconds: contracts.descriptor.timeout_seconds,
      max_model_tokens: contracts.descriptor.limits.max_model_tokens,
      max_tool_calls: contracts.descriptor.limits.max_tool_calls,
      max_cost_usd: contracts.descriptor.limits.max_cost_usd,
    },
    requested_external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const actionEvents = adapterResult.actions.map((action, index) => ({
    ...common,
    record_type: "p1_097_observable_action",
    event_sequence: index + 2,
    action,
  }));
  const completed = {
    ...common,
    record_type: "p1_097_run_completed",
    event_sequence: actionEvents.length + 2,
    ended_at: commandLedger.ended_at,
    result_identity: adapterResultIdentity,
    usage: adapterResult.usage,
    observed_external_effects: FALSE_EXTERNAL_EFFECTS,
    terminal_status: adapterResult.terminal_status,
    stop_reason_code: adapterResult.stop_reason_code,
  };
  return [started, ...actionEvents, completed];
}

export function buildRunRecord({
  contracts,
  commandLedger,
  adapterResult,
  traceIdentity,
  adapterResultIdentity,
}) {
  assert(
    adapterResult.run_id === `${contracts.request.request_id}:${contracts.request.adapter_id}:${contracts.request.repetition_id}`
      && adapterResult.task_id === contracts.task.value.task_id
      && adapterResult.adapter_id === contracts.request.adapter_id
      && adapterResult.adapter_version === contracts.descriptor.adapter_version
      && adapterResult.system_configuration_id === contracts.configuration.value.configuration_id
      && adapterResult.repetition_id === contracts.request.repetition_id,
    "RUN_RECORD_BINDING_INVALID",
    "adapter result identity does not bind the request and contract documents",
  );
  const runRecord = {
    schema_version: "1.0",
    run_id: adapterResult.run_id,
    task_id: contracts.task.value.task_id,
    dataset_version: contracts.task.value.dataset_version,
    adapter_id: contracts.request.adapter_id,
    adapter_version: contracts.descriptor.adapter_version,
    environment_snapshot_id: contracts.environment.value.snapshot_id,
    system_configuration_id: contracts.configuration.value.configuration_id,
    repetition_id: contracts.request.repetition_id,
    started_at: commandLedger.started_at,
    ended_at: commandLedger.ended_at,
    terminal_status: adapterResult.terminal_status,
    stop_reason_code: adapterResult.stop_reason_code,
    invalid_run_reason: null,
    error_taxonomy: [],
    trace_ref: traceIdentity.path,
    patch_ref: contracts.request.adapter_id === "B1" ? adapterResultIdentity.path : null,
    test_artifact_refs: [adapterResultIdentity.path],
    verification_ref: null,
    usage: adapterResult.usage,
    policy_violations: [],
    artifact_checksums: {
      trace: traceIdentity.sha256,
      adapter_result: adapterResultIdentity.sha256,
      descriptor: sha256(contracts.descriptorRecord.bytes),
      task_spec: sha256(contracts.task.bytes),
      environment_snapshot: sha256(contracts.environment.bytes),
      system_configuration: sha256(contracts.configuration.bytes),
      adapter_input: sha256(contracts.adapterInput.bytes),
      command_stdout: commandLedger.stdout_sha256,
      command_stderr: commandLedger.stderr_sha256,
    },
  };
  validateRunRecordSchema(runRecord);
  return runRecord;
}

export function assertAdapterResultShape(result, contracts) {
  const required = [
    "schema_version",
    "record_type",
    "run_id",
    "task_id",
    "adapter_id",
    "adapter_version",
    "system_configuration_id",
    "repetition_id",
    "terminal_status",
    "stop_reason_code",
    "actions",
    "usage",
    "target_execution_sentinel",
    "requested_external_effects",
    "observed_external_effects",
    "result",
    "provenance",
    "source_mutation_observed",
    "rollback",
  ];
  const adapterSpecific = {
    B0: [],
    B1: ["verification_ledgers"],
    B2: [
      "p0_binding_checks",
      "materialized_analyzer",
      "toolchain",
      "toolchain_ledgers",
      "scan_ledger",
      "scan_result",
    ],
  };
  const expected = [...required, ...adapterSpecific[contracts.request.adapter_id]].sort();
  assert(
    result !== null
      && typeof result === "object"
      && !Array.isArray(result)
      && canonicalJson(Object.keys(result).sort()) === canonicalJson(expected),
    "OUTPUT_SET_INVALID",
    "adapter result key set differs from the declared adapter output",
  );
  assert(
    result.schema_version === "1.0"
      && result.record_type === "p1_097_documented_adapter_result"
      && result.terminal_status === "completed"
      && result.stop_reason_code === "agent_complete"
      && canonicalJson(result.requested_external_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS)
      && canonicalJson(result.observed_external_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS)
      && result.source_mutation_observed === false,
    "RUN_RECORD_BINDING_INVALID",
    "adapter result terminal or effect boundary is invalid",
  );
  assert(
    result.usage !== null
      && typeof result.usage === "object"
      && result.usage.input_tokens <= contracts.descriptor.limits.max_model_tokens
      && result.usage.output_tokens <= contracts.descriptor.limits.max_model_tokens
      && result.usage.tool_calls <= contracts.descriptor.limits.max_tool_calls
      && result.usage.cost_usd <= contracts.descriptor.limits.max_cost_usd,
    "LIMIT_CONTRACT_INVALID",
    "adapter usage exceeds the descriptor limits",
  );
  return true;
}

export function identityFor(relativePath, value) {
  const bytes = canonicalBytes(value);
  return {
    bytes,
    identity: {
      path: relativePath,
      sha256: sha256(bytes),
      byte_length: bytes.length,
    },
  };
}

export function traceIdentityFor(relativePath, events) {
  assert(
    Array.isArray(events)
      && events.length >= 2
      && events.every((event, index) => (
        event.event_sequence === index + 1
        && event.run_id === events[0].run_id
      )),
    "TRACE_JOIN_INVALID",
    "trace events are missing, out of sequence or not joined",
  );
  const bytes = Buffer.from(`${events.map((event) => canonicalJson(event)).join("\n")}\n`, "utf8");
  return {
    bytes,
    identity: {
      path: relativePath,
      sha256: sha256(bytes),
      byte_length: bytes.length,
    },
  };
}

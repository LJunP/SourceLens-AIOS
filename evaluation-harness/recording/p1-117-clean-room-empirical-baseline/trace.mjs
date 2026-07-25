import {
  canonicalBytes,
} from "../../harness/p1-097-minimal-documented/core.mjs";

const ORDER = Object.freeze([
  "admission",
  "execution",
  "validation",
  "result",
  "rollback",
]);

export function buildTrace({
  entry,
  admission,
  materialization,
  selectedOperationId,
  scannerCommand = null,
  tests,
  terminal,
  rollback,
}) {
  const eventData = [
    {
      request_safe_identity: admission.request_safe_identity,
      task_spec: entry.task_spec,
      environment_snapshot: materialization.environment_snapshot,
      dataset_task_binding: materialization.dataset_task_binding,
      source_template_binding: materialization.source_template_binding,
      source_template_manifest: materialization.source_template_manifest,
      wrapper: entry.executable,
      configuration: entry.system_configuration,
    },
    {
      selected_operation_id: selectedOperationId,
      trusted_finite_compiler: selectedOperationId === null ? "NOT_RUN" : "EXECUTED_LOCAL",
      local_tool_ledger: entry.system === "B1"
        ? {
            schema_version: "p1-117-b1-local-tool-ledger/v1",
            run_id: entry.run_id,
            operations: tests.b1_local_tool_ledger,
          }
        : null,
      child_invocation: entry.system === "B2"
        ? {
            operation_id: "repository_analysis.scan",
            real_invocation: true,
            accepted_binding_sha256: entry.accepted_scanner_binding.sha256,
            command_ledger_sha256: scannerCommand.command_ledger_sha256,
            scanner_artifact_sha256: scannerCommand.scanner_pre_call_identity.sha256,
            scanner_pre_call_identity: scannerCommand.scanner_pre_call_identity,
          }
        : null,
    },
    {
      issue_specific_exit_status: tests.issue_specific?.exit_status ?? null,
      regression_exit_status: tests.regression?.exit_status ?? null,
      policy_violations: tests.policy_violations,
    },
    {
      terminal_status: terminal.status,
      reason_code: terminal.reason_code,
      selected_operation_id: selectedOperationId,
    },
    {
      status: rollback.status,
      source_state_restored: rollback.source_state_restored,
      nonowned_paths_touched: rollback.nonowned_paths_touched,
    },
  ];
  return Buffer.concat(ORDER.map((eventType, index) => canonicalBytes({
    schema_version: "p1-117-observable-trace-event/v1",
    run_id: entry.run_id,
    event_sequence: index + 1,
    event_type: eventType,
    data: eventData[index],
    ...(eventType === "execution" && entry.system === "B2"
      ? { child_invocation: eventData[index].child_invocation }
      : {}),
    ...(eventType === "execution" && entry.system === "B1"
      ? { local_tool_ledger: eventData[index].local_tool_ledger }
      : {}),
  })));
}

export function parseTrace(bytes) {
  const text = bytes.toString("utf8");
  if (!text.endsWith("\n") || text.endsWith("\n\n")) {
    throw new Error("TRACE_IDENTITY_MISMATCH");
  }
  const events = text.slice(0, -1).split("\n").map((line, index) => {
    const value = JSON.parse(line);
    if (!Buffer.from(`${line}\n`, "utf8").equals(canonicalBytes(value))) {
      throw new Error("TRACE_IDENTITY_MISMATCH");
    }
    if (
      value.event_type !== ORDER[index]
      || value.event_sequence !== index + 1
    ) {
      throw new Error("TRACE_SEQUENCE_INVALID");
    }
    return value;
  });
  if (events.length !== ORDER.length) throw new Error("TRACE_SEQUENCE_INVALID");
  return events;
}

export const TRACE_EVENT_ORDER = ORDER;

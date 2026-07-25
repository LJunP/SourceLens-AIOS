import {
  canonicalBytes,
  sha256,
} from "../../harness/p1-097-minimal-documented/core.mjs";
import {
  parseTrace,
} from "../../recording/p1-117-clean-room-empirical-baseline/trace.mjs";

export function buildStableProjection({
  entry,
  selectedOperationId,
  responseOutcome,
  tests,
  terminal,
  externalTruthBinding,
}) {
  return canonicalBytes({
    schema_version: "p1-117-stable-projection/v1",
    run: {
      run_id: entry.run_id,
      task_id: entry.task_id,
      system: entry.system,
      variant: entry.variant,
      repetition_id: entry.repetition_id,
    },
    selected_operation_id: selectedOperationId,
    response_outcome: responseOutcome,
    verification: {
      issue_specific_exit_status: tests.issue_specific?.exit_status ?? null,
      regression_exit_status: tests.regression?.exit_status ?? null,
      policy_violations: tests.policy_violations,
    },
    terminal: {
      status: terminal.status,
      reason_code: terminal.reason_code,
      invalid_run_reason: terminal.invalid_run_reason,
    },
    truth_binding: {
      task_spec: externalTruthBinding.task_spec,
      environment_snapshot: externalTruthBinding.environment_snapshot,
      dataset_task_binding: externalTruthBinding.dataset_task_binding,
      source_template_binding: externalTruthBinding.source_template_binding,
      source_template_manifest: externalTruthBinding.source_template_manifest,
      executable: externalTruthBinding.executable,
      system_configuration: externalTruthBinding.system_configuration,
      accepted_scanner_binding: externalTruthBinding.accepted_scanner_binding,
    },
  });
}

export function replayExact({
  entry,
  traceBytes,
  stableProjectionBytes,
  projectionInputs,
}) {
  const events = parseTrace(traceBytes);
  if (!events.every((event) => event.run_id === entry.run_id)) {
    throw new Error("REPLAY_MISMATCH");
  }
  const recomputed = buildStableProjection({
    entry,
    ...projectionInputs,
  });
  if (!recomputed.equals(stableProjectionBytes)) {
    throw new Error("REPLAY_MISMATCH");
  }
  return {
    schema_version: "p1-117-replay-receipt/v1",
    status: "PASS",
    run_id: entry.run_id,
    trace_sha256: sha256(traceBytes),
    stable_projection_identity: {
      sha256: sha256(stableProjectionBytes),
      byte_length: stableProjectionBytes.length,
    },
    replayed_event_count: events.length,
  };
}

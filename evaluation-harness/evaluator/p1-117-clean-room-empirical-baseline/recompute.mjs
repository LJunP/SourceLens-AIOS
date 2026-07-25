#!/usr/bin/env node

import {
  closeSync,
  constants as fsConstants,
  existsSync,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
} from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  P117QualityNonPass,
  SHA256_PATTERN,
  assert,
  canonicalJsonBytes,
  exactKeys,
  identityOf,
  parseCanonicalJson,
  parseFrozenJson,
  readBoundFile,
  sameJson,
  sha256,
} from "../../validators/p1-117-clean-room-empirical-baseline/core.mjs";
import {
  loadSafeDisclosure,
  validateChatCompletionsRequest,
  validateProviderResponseOutcome,
} from "../../validators/p1-117-clean-room-empirical-baseline/disclosure.mjs";

const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const REQUIRED_EVIDENCE_ROLES = Object.freeze([
  "request_safe",
  "response_safe",
  "run_record",
  "trace",
  "external_truth_binding",
  "stable_projection",
  "replay_receipt",
  "rollback_receipt",
  "test_receipt",
]);
const TRACE_ORDER = Object.freeze([
  "admission",
  "execution",
  "validation",
  "result",
  "rollback",
]);
const B1_OPERATION_ORDER = Object.freeze([
  "file_listing",
  "lexical_search",
  "trusted_finite_operation_compiler",
  "verification_ledger",
]);
const INVALID_REASONS = new Set([
  "SHARED_HARNESS_FAILURE",
  "ENVIRONMENT_MATERIALIZATION_FAILURE",
  "EVALUATOR_UNAVAILABLE",
  "CORRUPT_FIXTURE",
]);

function readArtifact(root, binding, reasonCode) {
  exactKeys(binding, ["relative_path", "sha256", "byte_length"], reasonCode);
  assert(
    typeof binding.relative_path === "string"
      && binding.relative_path.length > 0
      && !isAbsolute(binding.relative_path)
      && !binding.relative_path.includes("\0")
      && !binding.relative_path.split("/").includes(".."),
    reasonCode,
  );
  const path = resolve(root, binding.relative_path);
  const rel = relative(root, path);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), reasonCode);
  let before;
  try {
    before = lstatSync(path);
  } catch {
    throw new P117QualityNonPass(reasonCode);
  }
  assert(before.isFile() && !before.isSymbolicLink() && before.nlink === 1, reasonCode);
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  } catch {
    throw new P117QualityNonPass(reasonCode);
  }
  try {
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.nlink === 1,
      reasonCode,
    );
    const bytes = readFileSync(descriptor);
    const after = lstatSync(path);
    assert(
      after.isFile()
        && after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && after.mtimeMs === opened.mtimeMs,
      reasonCode,
    );
    const identity = identityOf(bytes);
    assert(
      identity.sha256 === binding.sha256
        && identity.byte_length === binding.byte_length,
      reasonCode,
    );
    return bytes;
  } finally {
    closeSync(descriptor);
  }
}

function validateDigestIdentity(value, reasonCode) {
  exactKeys(value, ["sha256", "byte_length"], reasonCode);
  assert(
    SHA256_PATTERN.test(value.sha256)
      && Number.isSafeInteger(value.byte_length)
      && value.byte_length >= 0,
    reasonCode,
  );
}

function validateB1LocalToolLedger(value, entry, selectedOperationId) {
  exactKeys(
    value,
    ["schema_version", "run_id", "operations"],
    "B1_LOCAL_TOOL_LEDGER_INVALID",
  );
  assert(
    value.schema_version === "p1-117-b1-local-tool-ledger/v1"
      && value.run_id === entry.run_id
      && Array.isArray(value.operations)
      && value.operations.length === B1_OPERATION_ORDER.length,
    "B1_LOCAL_TOOL_LEDGER_INVALID",
  );
  for (const [index, operation] of value.operations.entries()) {
    exactKeys(
      operation,
      [
        "sequence",
        "operation_id",
        "status",
        "input_identity",
        "output_identity",
        "executable_identity",
      ],
      "B1_LOCAL_TOOL_LEDGER_INVALID",
    );
    assert(
      operation.sequence === index + 1
        && operation.operation_id === B1_OPERATION_ORDER[index],
      "B1_LOCAL_TOOL_LEDGER_INVALID",
    );
    if (
      operation.operation_id === "trusted_finite_operation_compiler"
      && operation.status === "NOT_RUN_PRECONDITION_FAILED"
    ) {
      assert(
        selectedOperationId === null
          &&
        operation.input_identity === null
          && operation.output_identity === null
          && operation.executable_identity === null,
        "B1_LOCAL_TOOL_LEDGER_INVALID",
      );
      continue;
    }
    const expectedStatus = operation.operation_id === "trusted_finite_operation_compiler"
      ? "EXECUTED_LOCAL"
      : "EXECUTED_LOCAL_RESULT_WITHHELD_FROM_PROVIDER";
    assert(operation.status === expectedStatus, "B1_LOCAL_TOOL_LEDGER_INVALID");
    if (operation.operation_id === "trusted_finite_operation_compiler") {
      assert(
        typeof selectedOperationId === "string"
          && entry.finite_operation_ids.includes(selectedOperationId),
        "B1_LOCAL_TOOL_LEDGER_INVALID",
      );
    }
    validateDigestIdentity(operation.input_identity, "B1_LOCAL_TOOL_LEDGER_INVALID");
    validateDigestIdentity(operation.output_identity, "B1_LOCAL_TOOL_LEDGER_INVALID");
    validateDigestIdentity(operation.executable_identity, "B1_LOCAL_TOOL_LEDGER_INVALID");
  }
}

function validateScannerPreCallIdentity(value) {
  exactKeys(
    value,
    [
      "path",
      "sha256",
      "byte_length",
      "type",
      "dev",
      "ino",
      "uid",
      "gid",
      "mode",
      "verification_status",
    ],
    "B2_SCANNER_PRECALL_IDENTITY_INVALID",
  );
  assert(
    typeof value.path === "string"
      && value.path.length > 0
      && SHA256_PATTERN.test(value.sha256)
      && Number.isSafeInteger(value.byte_length)
      && value.byte_length >= 0
      && value.type === "REGULAR_FILE"
      && typeof value.dev === "string"
      && /^[0-9]+$/.test(value.dev)
      && typeof value.ino === "string"
      && /^[0-9]+$/.test(value.ino)
      && Number.isSafeInteger(value.uid)
      && value.uid >= 0
      && Number.isSafeInteger(value.gid)
      && value.gid >= 0
      && Number.isSafeInteger(value.mode)
      && value.mode >= 0
      && value.mode <= 0o7777
      && value.verification_status === "PASS",
    "B2_SCANNER_PRECALL_IDENTITY_INVALID",
  );
}

export function validateTraceEvidence(bytes, entry, taskBinding = null) {
  const text = bytes.toString("utf8");
  assert(text.endsWith("\n") && !text.endsWith("\n\n"), "TRACE_IDENTITY_MISMATCH");
  let events;
  try {
    events = text.slice(0, -1).split("\n").map((line) => {
      const event = JSON.parse(line);
      assert(
        Buffer.from(`${line}\n`, "utf8").equals(canonicalJsonBytes(event)),
        "TRACE_IDENTITY_MISMATCH",
      );
      return event;
    });
  } catch {
    throw new P117QualityNonPass("TRACE_IDENTITY_MISMATCH");
  }
  assert(events.length === TRACE_ORDER.length, "TRACE_SEQUENCE_INVALID");
  for (const [index, event] of events.entries()) {
    assert(
      event.event_type === TRACE_ORDER[index]
        && event.event_sequence === index + 1,
      "TRACE_SEQUENCE_INVALID",
    );
    assert(event.run_id === entry.run_id, "TRACE_IDENTITY_MISMATCH");
  }
  if (taskBinding !== null) {
    assert(
      sameJson(events[0].data?.task_spec, entry.task_spec)
        && sameJson(events[0].data?.environment_snapshot, taskBinding.environment_snapshot)
        && sameJson(events[0].data?.dataset_task_binding, taskBinding.dataset_task_binding)
        && sameJson(events[0].data?.source_template_binding, taskBinding.source_template_binding)
        && sameJson(events[0].data?.source_template_manifest, {
          sha256: taskBinding.source_template_binding.manifest_sha256,
          byte_length: taskBinding.source_template_binding.manifest_byte_length,
          file_count: taskBinding.source_template_binding.file_count,
        })
        && sameJson(events[0].data?.wrapper, entry.executable)
        && sameJson(events[0].data?.configuration, entry.system_configuration),
      "TRACE_MATERIALIZATION_BINDING_MISMATCH",
    );
  }
  if (entry.system === "B1") {
    assert(
      events[1].local_tool_ledger !== undefined
        && events[1].data?.local_tool_ledger !== undefined
        && sameJson(events[1].local_tool_ledger, events[1].data.local_tool_ledger),
      "B1_LOCAL_TOOL_LEDGER_INVALID",
    );
    validateB1LocalToolLedger(
      events[1].data?.local_tool_ledger,
      entry,
      events[1].data?.selected_operation_id,
    );
  }
  if (entry.system === "B2") {
    const execution = events[1];
    assert(
      execution.child_invocation !== undefined
        && execution.data?.child_invocation !== undefined
        && sameJson(execution.child_invocation, execution.data.child_invocation)
        && execution.child_invocation?.operation_id === "repository_analysis.scan"
        && execution.child_invocation?.real_invocation === true
        && execution.child_invocation?.accepted_binding_sha256
          === entry.accepted_scanner_binding.sha256
        && SHA256_PATTERN.test(execution.child_invocation?.command_ledger_sha256)
        && SHA256_PATTERN.test(execution.child_invocation?.scanner_artifact_sha256),
      "B2_SCANNER_CHILD_REQUIRED",
    );
    validateScannerPreCallIdentity(
      execution.child_invocation.scanner_pre_call_identity,
    );
    assert(
      execution.child_invocation.scanner_artifact_sha256
        === execution.child_invocation.scanner_pre_call_identity.sha256,
      "B2_SCANNER_PRECALL_IDENTITY_INVALID",
    );
  }
  return events;
}

function validateCost(cost) {
  exactKeys(cost, ["status", "currency", "amount"], "COST_ACCOUNTING_INVALID");
  assert(cost.currency === "USD", "COST_ACCOUNTING_INVALID");
  if (cost.status === "UNKNOWN_GATEWAY_METERING_UNAVAILABLE") {
    assert(cost.amount === null, "COST_ACCOUNTING_INVALID");
    return { available: false, amount: 0 };
  }
  assert(
    cost.status === "AVAILABLE"
      && typeof cost.amount === "number"
      && Number.isFinite(cost.amount)
      && cost.amount >= 0,
    "COST_ACCOUNTING_INVALID",
  );
  return { available: true, amount: cost.amount };
}

export function validateRunRecordEvidence(value, entry) {
  assert(
    value.schema_version === "1.0"
      && value.run_id === entry.run_id
      && value.task_id === entry.task_id
      && value.adapter_id === entry.system
      && value.repetition_id === 1,
    "RUN_RECORD_IDENTITY_MISMATCH",
  );
  assert(Array.isArray(value.policy_violations), "RUN_RECORD_SCHEMA_INVALID");
  return value;
}

function validateTruthBinding(value, entry, taskBinding) {
  exactKeys(
    value,
    [
      "schema_version",
      "status",
      "run_id",
      "task_spec",
      "environment_snapshot",
      "dataset_task_binding",
      "source_template_binding",
      "source_template_manifest",
      "executable",
      "system_configuration",
      "accepted_scanner_binding",
      "b2_scanner_command_ledger",
    ],
    "EXTERNAL_TRUTH_BINDING_MISMATCH",
  );
  assert(
    value.schema_version === "p1-117-external-truth-binding/v1"
      && value.status === "PASS"
      && value.run_id === entry.run_id
      && sameJson(value.task_spec, entry.task_spec)
      && sameJson(value.environment_snapshot, taskBinding.environment_snapshot)
      && sameJson(value.dataset_task_binding, taskBinding.dataset_task_binding)
      && sameJson(value.source_template_binding, taskBinding.source_template_binding)
      && sameJson(value.source_template_manifest, {
        sha256: taskBinding.source_template_binding.manifest_sha256,
        byte_length: taskBinding.source_template_binding.manifest_byte_length,
        file_count: taskBinding.source_template_binding.file_count,
      })
      && sameJson(value.executable, entry.executable)
      && sameJson(value.system_configuration, entry.system_configuration),
    "EXTERNAL_TRUTH_BINDING_MISMATCH",
  );
  if (entry.system === "B2") {
    assert(
      sameJson(value.accepted_scanner_binding, entry.accepted_scanner_binding),
      "SCANNER_BINDING_IDENTITY_MISMATCH",
    );
    assert(
      value.b2_scanner_command_ledger?.schema_version
        === "p1-117-b2-scanner-command/v1"
        && value.b2_scanner_command_ledger?.run_id === entry.run_id
        && value.b2_scanner_command_ledger?.operation_id
          === "repository_analysis.scan"
        && sameJson(
          value.b2_scanner_command_ledger?.accepted_binding,
          entry.accepted_scanner_binding,
        ),
      "B2_SCANNER_CHILD_REQUIRED",
    );
    validateScannerPreCallIdentity(
      value.b2_scanner_command_ledger.scanner_pre_call_identity,
    );
  } else {
    assert(
      value.accepted_scanner_binding === null
        && value.b2_scanner_command_ledger === null,
      "EXTERNAL_TRUTH_BINDING_MISMATCH",
    );
  }
}

export function validateReplayEvidence(value, projectionBytes, entry) {
  assert(
    value.status === "PASS"
      && value.run_id === entry.run_id
      && sameJson(value.stable_projection_identity, identityOf(projectionBytes)),
    "REPLAY_MISMATCH",
  );
}

export function validateRollbackEvidence(value, entry) {
  assert(value.nonowned_paths_touched === 0, "NONOWNED_CLEANUP_FORBIDDEN");
  assert(
    value.status === "PASS_EXACT"
      && value.run_id === entry.run_id
      && value.source_state_restored === true,
    "ROLLBACK_IDENTITY_MISMATCH",
  );
}

export function validateTestEvidence(value, entry, selectedOperationId) {
  assert(
    value.run_id === entry.run_id
      && value.trusted_compiler_operation_id === selectedOperationId
      && (value.issue_specific?.exit_status === null
        || (Number.isSafeInteger(value.issue_specific?.exit_status)
          && value.issue_specific.exit_status >= 0))
      && (value.regression?.exit_status === null
        || (Number.isSafeInteger(value.regression?.exit_status)
          && value.regression.exit_status >= 0))
      && Array.isArray(value.policy_violations),
    "TEST_RECEIPT_SCHEMA_INVALID",
  );
  return value.issue_specific.exit_status === 0
    && value.regression.exit_status === 0
    && value.policy_violations.length === 0;
}

export function validateRunManifest(manifest, entry) {
  exactKeys(
    manifest,
    ["schema_version", "entry", "terminal", "selected_operation_id", "evidence", "accounting", "observed_effects"],
    "RUN_MANIFEST_SCHEMA_INVALID",
  );
  assert(manifest.schema_version === "p1-117-run-manifest/v1", "RUN_MANIFEST_SCHEMA_INVALID");
  assert(sameJson(manifest.entry, {
    slot: entry.slot,
    entry_id: entry.entry_id,
    run_id: entry.run_id,
    task_id: entry.task_id,
    system: entry.system,
    variant: entry.variant,
    repetition_id: entry.repetition_id,
  }), "RUN_RESULT_IDENTITY_MISMATCH");
  exactKeys(manifest.terminal, ["status", "reason_code", "invalid_run_reason", "post_hoc_excluded"], "RUN_MANIFEST_SCHEMA_INVALID");
  assert(manifest.terminal.post_hoc_excluded === false, "POST_HOC_EXCLUSION_FORBIDDEN");
  exactKeys(manifest.evidence, REQUIRED_EVIDENCE_ROLES, "EVIDENCE_INCOMPLETE");
  exactKeys(
    manifest.accounting,
    ["provider_requests", "automatic_retries", "input_tokens", "output_tokens", "latency_ms", "cost", "successful_loopback_connections"],
    "ACCOUNTING_SCHEMA_INVALID",
  );
  assert(
    manifest.accounting.provider_requests === 1
      && manifest.accounting.automatic_retries === 0
      && Number.isSafeInteger(manifest.accounting.input_tokens)
      && manifest.accounting.input_tokens >= 0
      && manifest.accounting.input_tokens <= 12000
      && Number.isSafeInteger(manifest.accounting.output_tokens)
      && manifest.accounting.output_tokens >= 0
      && manifest.accounting.output_tokens <= 2048
      && Number.isSafeInteger(manifest.accounting.latency_ms)
      && manifest.accounting.latency_ms >= 0
      && Number.isSafeInteger(manifest.accounting.successful_loopback_connections)
      && manifest.accounting.successful_loopback_connections >= 0
      && manifest.accounting.successful_loopback_connections <= 1,
    "ACCOUNTING_CAP_EXCEEDED",
  );
  exactKeys(
    manifest.observed_effects,
    ["non_loopback_network_connections", "remote", "production", "public", "restricted_source_egress", "secret_sink_writes"],
    "OBSERVED_EFFECT_SCHEMA_INVALID",
  );
  assert(
    manifest.observed_effects.non_loopback_network_connections === 0
      && manifest.observed_effects.remote === false
      && manifest.observed_effects.production === false
      && manifest.observed_effects.public === false
      && manifest.observed_effects.restricted_source_egress === false
      && manifest.observed_effects.secret_sink_writes === 0,
    "FORBIDDEN_EXTERNAL_EFFECT",
  );
}

export function validateResultPopulation(schedule, manifests) {
  assert(Array.isArray(manifests), "SCHEDULED_RUN_MISSING");
  const runIds = manifests.map((manifest) => manifest.entry?.run_id);
  assert(runIds.length === schedule.length, "SCHEDULED_RUN_MISSING");
  assert(new Set(runIds).size === runIds.length, "RUN_RESULT_DUPLICATE");
  assert(
    schedule.every((entry, index) => runIds[index] === entry.run_id),
    "MATRIX_ORDER_MISMATCH",
  );
  return true;
}

export function validateEvidenceIdentity(
  bytes,
  binding,
  reasonCode = "EVIDENCE_IDENTITY_MISMATCH",
) {
  assert(
    binding.sha256 === identityOf(bytes).sha256
      && binding.byte_length === bytes.length,
    reasonCode,
  );
  return true;
}

export function validateReportedAggregate(actual, reported) {
  assert(sameJson(actual, reported), "AGGREGATE_RECOMPUTATION_MISMATCH");
  return true;
}

function accountingTotals({
  requests,
  reservedInput,
  reservedOutput,
  observedInput,
  observedOutput,
}) {
  return {
    provider_requests_accounted: requests,
    input_tokens_accounted: reservedInput,
    output_tokens_accounted: reservedOutput,
    input_tokens_observed: observedInput,
    output_tokens_observed: observedOutput,
    automatic_retries: 0,
    cost_observed_usd: null,
    cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
  };
}

export function validateAccountingLedger(bytes, schedule, manifests) {
  const text = bytes.toString("utf8");
  assert(text.endsWith("\n") && !text.endsWith("\n\n"), "ACCOUNTING_LEDGER_INVALID");
  let events;
  try {
    events = text.slice(0, -1).split("\n").map((line) => {
      const event = JSON.parse(line);
      assert(
        Buffer.from(`${line}\n`, "utf8").equals(canonicalJsonBytes(event)),
        "ACCOUNTING_LEDGER_INVALID",
      );
      return event;
    });
  } catch (error) {
    if (error instanceof P117QualityNonPass) throw error;
    throw new P117QualityNonPass("ACCOUNTING_LEDGER_INVALID");
  }
  assert(
    events.length === 74
      && schedule.length === 36
      && manifests.length === 36,
    "ACCOUNTING_LEDGER_SEQUENCE_INVALID",
  );
  for (const [index, event] of events.entries()) {
    assert(
      event.schema_version === "p1-117-accounting-event/v1"
        && event.sequence === index + 1,
      "ACCOUNTING_LEDGER_SEQUENCE_INVALID",
    );
  }
  const caps = {
    provider_requests_max: 60,
    automatic_retry_max: 0,
    input_tokens_max: 500000,
    output_tokens_max: 100000,
    currency: "USD",
    max_spend: 25,
  };
  assert(
    events[0].event_type === "LEDGER_OPENED"
      && events[0].run_id === null
      && sameJson(events[0].data, {
        caps,
        cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
      })
      && sameJson(events[0].totals, accountingTotals({
        requests: 0,
        reservedInput: 0,
        reservedOutput: 0,
        observedInput: 0,
        observedOutput: 0,
      })),
    "ACCOUNTING_LEDGER_SEQUENCE_INVALID",
  );
  let observedInput = 0;
  let observedOutput = 0;
  for (const [index, entry] of schedule.entries()) {
    const manifest = manifests[index];
    const requestCount = index + 1;
    const reserved = events[index * 2 + 1];
    const observed = events[index * 2 + 2];
    assert(
      reserved.event_type === "REQUEST_RESERVED"
        && observed.event_type === "RESPONSE_OBSERVED"
        && reserved.run_id === entry.run_id
        && observed.run_id === entry.run_id
        && manifest.entry.run_id === entry.run_id,
      "ACCOUNTING_LEDGER_SEQUENCE_INVALID",
    );
    assert(
      sameJson(reserved.data, {
        input_token_upper_bound: 12000,
        input_token_upper_bound_method: "QUALITY_FROZEN_PER_RUN_RESERVATION",
        output_token_upper_bound: 2048,
        request_count: 1,
        automatic_retry_count: 0,
      }),
      "ACCOUNTING_LEDGER_CAP_MISMATCH",
    );
    assert(
      observed.data.provider_requests === 1
        && observed.data.automatic_retries === 0
        && observed.data.successful_loopback_connections
          === manifest.accounting.successful_loopback_connections
        && (observed.data.prompt_tokens ?? 0) === manifest.accounting.input_tokens
        && (observed.data.completion_tokens ?? 0) === manifest.accounting.output_tokens
        && observed.data.latency_ms === manifest.accounting.latency_ms
        && observed.data.observed_cost_usd === null
        && observed.data.cost_status === "UNKNOWN_GATEWAY_METERING_UNAVAILABLE"
        && observed.data.monetary_cap_empirically_enforced === false,
      "ACCOUNTING_LEDGER_MANIFEST_MISMATCH",
    );
    assert(
      observed.data.prompt_tokens === null
        || (Number.isSafeInteger(observed.data.prompt_tokens)
          && observed.data.prompt_tokens >= 0
          && observed.data.prompt_tokens <= 12000),
      "ACCOUNTING_LEDGER_CAP_MISMATCH",
    );
    assert(
      observed.data.completion_tokens === null
        || (Number.isSafeInteger(observed.data.completion_tokens)
          && observed.data.completion_tokens >= 0
          && observed.data.completion_tokens <= 2048),
      "ACCOUNTING_LEDGER_CAP_MISMATCH",
    );
    observedInput += manifest.accounting.input_tokens;
    observedOutput += manifest.accounting.output_tokens;
    const afterReserve = accountingTotals({
      requests: requestCount,
      reservedInput: requestCount * 12000,
      reservedOutput: requestCount * 2048,
      observedInput: observedInput - manifest.accounting.input_tokens,
      observedOutput: observedOutput - manifest.accounting.output_tokens,
    });
    const afterObserve = accountingTotals({
      requests: requestCount,
      reservedInput: requestCount * 12000,
      reservedOutput: requestCount * 2048,
      observedInput,
      observedOutput,
    });
    assert(
      sameJson(reserved.totals, afterReserve)
        && sameJson(observed.totals, afterObserve),
      "ACCOUNTING_LEDGER_TOTALS_INVALID",
    );
  }
  const closed = events.at(-1);
  const beforeCloseBytes = Buffer.concat(
    events.slice(0, -1).map((event) => canonicalJsonBytes(event)),
  );
  const finalTotals = accountingTotals({
    requests: 36,
    reservedInput: 432000,
    reservedOutput: 73728,
    observedInput,
    observedOutput,
  });
  assert(
    closed.event_type === "LEDGER_CLOSED"
      && closed.run_id === null
      && closed.data?.status === "COMPLETE"
      && closed.data?.ledger_sha256_before_close === sha256(beforeCloseBytes)
      && sameJson(closed.totals, finalTotals)
      && observedInput <= caps.input_tokens_max
      && observedOutput <= caps.output_tokens_max,
    "ACCOUNTING_LEDGER_CLOSE_INVALID",
  );
  return { events, totals: finalTotals };
}

export function validateFormalRuntimeReceipt({
  receipt,
  ledgerBytes,
  manifestPopulation,
  requests,
}) {
  exactKeys(
    receipt,
    [
      "schema_version",
      "status",
      "scheduled_runs",
      "completed_run_manifests",
      "provider_requests",
      "automatic_retries",
      "secret_reads",
      "provider_session_closed",
      "owned_secret_buffer_overwrite_attempted",
      "whole_process_memory_zeroization_claim",
      "accounting_ledger",
      "run_manifest_population",
      "cost",
    ],
    "FORMAL_RUNTIME_RECEIPT_INVALID",
  );
  const populationBytes = canonicalJsonBytes(manifestPopulation);
  assert(
    receipt.schema_version === "p1-117-formal-runtime-receipt/v1"
      && receipt.status === "COMPLETE"
      && receipt.scheduled_runs === 36
      && receipt.completed_run_manifests === 36
      && receipt.provider_requests === requests
      && receipt.provider_requests === 36
      && receipt.automatic_retries === 0
      && receipt.secret_reads === 1
      && receipt.provider_session_closed === true
      && receipt.owned_secret_buffer_overwrite_attempted === true
      && receipt.whole_process_memory_zeroization_claim === "NOT_CLAIMED"
      && sameJson(receipt.accounting_ledger, identityOf(ledgerBytes))
      && sameJson(receipt.run_manifest_population, {
        count: 36,
        aggregate_sha256: sha256(populationBytes),
        aggregate_byte_length: populationBytes.length,
      })
      && sameJson(receipt.cost, {
        status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
        currency: "USD",
        amount: null,
      }),
    "FORMAL_RUNTIME_RECEIPT_INVALID",
  );
  return true;
}

function percentile(sorted, fraction) {
  if (sorted.length === 0) return null;
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
}

export function recompute({
  repositoryRoot,
  artifactRoot,
  matrix,
  oracle,
}) {
  const seen = new Set();
  const outcomes = [];
  const manifestValues = [];
  const manifestPopulation = [];
  const reasonDistribution = {};
  const latencyValues = [];
  let requests = 0;
  let inputTokens = 0;
  let outputTokens = 0;
  let availableCost = 0;
  let unavailableCostCount = 0;
  let successfulLoopbackConnections = 0;
  for (const entry of matrix.schedule) {
    const taskBinding = matrix.task_bindings.find(
      (binding) => binding.task_id === entry.task_id,
    );
    assert(taskBinding !== undefined, "DATASET_TASK_BINDING_MISMATCH");
    const runRoot = resolve(artifactRoot, entry.run_id);
    const manifestPath = join(runRoot, "run-manifest.json");
    assert(existsSync(manifestPath), "SCHEDULED_RUN_MISSING");
    const manifestBytes = readFileSync(manifestPath);
    const manifest = parseCanonicalJson(
      manifestBytes,
      "RUN_MANIFEST_SCHEMA_INVALID",
    );
    validateRunManifest(manifest, entry);
    assert(!seen.has(manifest.entry.run_id), "RUN_RESULT_DUPLICATE");
    seen.add(manifest.entry.run_id);
    manifestValues.push(manifest);
    manifestPopulation.push({
      run_id: entry.run_id,
      ...identityOf(manifestBytes),
    });
    const safe = loadSafeDisclosure(repositoryRoot, matrix, entry);
    const evidence = Object.fromEntries(
      REQUIRED_EVIDENCE_ROLES.map((role) => [
        role,
        readArtifact(runRoot, manifest.evidence[role], role === "run_record"
          ? "RUN_RECORD_IDENTITY_MISMATCH"
          : role === "trace"
            ? "TRACE_IDENTITY_MISMATCH"
            : role === "stable_projection"
              ? "STABLE_PROJECTION_IDENTITY_MISMATCH"
              : "EVIDENCE_IDENTITY_MISMATCH"),
      ]),
    );
    const configuration = parseFrozenJson(
      readBoundFile(
        repositoryRoot,
        entry.system_configuration,
        "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
      ).bytes,
      "SYSTEM_CONFIGURATION_SCHEMA_INVALID",
    );
    validateChatCompletionsRequest({
      repositoryRoot,
      requestBytes: evidence.request_safe,
      entry,
      configuration,
      disclosure: safe.disclosure,
      responseSchemaIdentity: matrix.response_schema,
    });
    const response = validateProviderResponseOutcome(
      evidence.response_safe,
      entry.finite_operation_ids,
    );
    assert(
      response.selectedOperationId === manifest.selected_operation_id,
      "PROVIDER_RESPONSE_IDENTITY_MISMATCH",
    );
    const runRecord = validateRunRecordEvidence(
      parseCanonicalJson(evidence.run_record, "RUN_RECORD_SCHEMA_INVALID"),
      entry,
    );
    validateTraceEvidence(evidence.trace, entry, taskBinding);
    validateTruthBinding(
      parseCanonicalJson(evidence.external_truth_binding, "EXTERNAL_TRUTH_BINDING_MISMATCH"),
      entry,
      taskBinding,
    );
    parseCanonicalJson(evidence.stable_projection, "STABLE_PROJECTION_IDENTITY_MISMATCH");
    validateReplayEvidence(
      parseCanonicalJson(evidence.replay_receipt, "REPLAY_MISMATCH"),
      evidence.stable_projection,
      entry,
    );
    validateRollbackEvidence(
      parseCanonicalJson(evidence.rollback_receipt, "ROLLBACK_IDENTITY_MISMATCH"),
      entry,
    );
    const testsPass = validateTestEvidence(
      parseCanonicalJson(evidence.test_receipt, "INDEPENDENT_TEST_NON_PASS"),
      entry,
      manifest.selected_operation_id,
    );

    requests += manifest.accounting.provider_requests;
    inputTokens += manifest.accounting.input_tokens;
    outputTokens += manifest.accounting.output_tokens;
    latencyValues.push(manifest.accounting.latency_ms);
    successfulLoopbackConnections += manifest.accounting.successful_loopback_connections;
    const cost = validateCost(manifest.accounting.cost);
    if (cost.available) availableCost += cost.amount;
    else unavailableCostCount += 1;

    const invalid = manifest.terminal.status === "INFRASTRUCTURE_INVALID";
    if (invalid) {
      assert(
        INVALID_REASONS.has(manifest.terminal.invalid_run_reason),
        "POST_HOC_EXCLUSION_FORBIDDEN",
      );
    } else {
      assert(manifest.terminal.invalid_run_reason === null, "POST_HOC_EXCLUSION_FORBIDDEN");
    }
    const success = !invalid
      && manifest.terminal.status === "COMPLETED"
      && manifest.selected_operation_id === oracle.expected_operations[entry.task_id]
      && response.accepted
      && testsPass
      && runRecord.policy_violations.length === 0;
    const reason = invalid
      ? manifest.terminal.invalid_run_reason
      : success
        ? "VERIFIED_SUCCESS"
        : manifest.terminal.reason_code;
    reasonDistribution[reason] = (reasonDistribution[reason] ?? 0) + 1;
    outcomes.push({ run_id: entry.run_id, invalid, success, reason });
  }
  assert(seen.size === 36, "MATRIX_POPULATION_MISMATCH");
  assert(requests === 36, "PROVIDER_REQUEST_CAP_EXCEEDED");
  assert(inputTokens <= 500000 && outputTokens <= 100000, "ACCOUNTING_CAP_EXCEEDED");
  assert(successfulLoopbackConnections <= 36, "ACCOUNTING_CAP_EXCEEDED");
  assert(availableCost <= 25, "COST_CAP_EXCEEDED");
  const ledgerPath = join(artifactRoot, "accounting-ledger.jsonl");
  assert(existsSync(ledgerPath), "ACCOUNTING_LEDGER_MISSING");
  const ledgerBytes = readFileSync(ledgerPath);
  validateAccountingLedger(ledgerBytes, matrix.schedule, manifestValues);
  const runtimeReceiptPath = join(artifactRoot, "formal-runtime-receipt.json");
  assert(existsSync(runtimeReceiptPath), "FORMAL_RUNTIME_RECEIPT_MISSING");
  const runtimeReceipt = parseCanonicalJson(
    readFileSync(runtimeReceiptPath),
    "FORMAL_RUNTIME_RECEIPT_INVALID",
  );
  validateFormalRuntimeReceipt({
    receipt: runtimeReceipt,
    ledgerBytes,
    manifestPopulation,
    requests,
  });
  const invalids = outcomes.filter((outcome) => outcome.invalid).length;
  const eligible = 36 - invalids;
  const successes = outcomes.filter((outcome) => outcome.success).length;
  const failures = eligible - successes;
  const sortedLatency = [...latencyValues].sort((left, right) => left - right);
  return {
    schema_version: "p1-117-independent-aggregate/v1",
    record_type: "INDEPENDENT_RAW_EVIDENCE_RECOMPUTATION",
    claim_boundary: "FINITE_SAFE_DISCLOSURE_CONSTRAINED_VISIBLE_SYNTHETIC_DESCRIPTIVE_BASELINE",
    scheduled: 36,
    eligible,
    verified_successes: successes,
    failures,
    invalids,
    vtsr_fraction: `${successes}/${eligible}`,
    reason_distribution: Object.fromEntries(
      Object.entries(reasonDistribution).sort(([left], [right]) => left.localeCompare(right)),
    ),
    accounting: {
      provider_requests: requests,
      successful_loopback_connections: successfulLoopbackConnections,
      automatic_retries: 0,
      input_tokens: inputTokens,
      output_tokens: outputTokens,
      available_cost_usd: availableCost,
      unavailable_cost_count: unavailableCostCount,
      latency_ms: {
        min: sortedLatency[0],
        median: percentile(sortedLatency, 0.5),
        p95: percentile(sortedLatency, 0.95),
        max: sortedLatency[sortedLatency.length - 1],
      },
    },
    false_accepts: 0,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const args = Object.fromEntries(
      Array.from({ length: process.argv.slice(2).length / 2 }, (_, index) => {
        const offset = index * 2 + 2;
        return [process.argv[offset], process.argv[offset + 1]];
      }),
    );
    for (const name of ["--repository-root", "--artifact-root", "--matrix", "--oracle"]) {
      assert(typeof args[name] === "string" && isAbsolute(args[name]), "CLI_ARGUMENT_MISMATCH");
    }
    const result = recompute({
      repositoryRoot: resolve(args["--repository-root"]),
      artifactRoot: resolve(args["--artifact-root"]),
      matrix: parseCanonicalJson(readFileSync(args["--matrix"]), "MATRIX_SCHEMA_INVALID"),
      oracle: parseCanonicalJson(readFileSync(args["--oracle"]), "ORACLE_SCHEMA_INVALID"),
    });
    process.stdout.write(canonicalOutput(result));
  } catch (error) {
    const reasonCode = error instanceof P117QualityNonPass
      ? error.reasonCode
      : "UNEXPECTED_EVALUATOR_ERROR";
    process.stdout.write(`${JSON.stringify({status: "NON_PASS", reason_code: reasonCode})}\n`);
    process.exitCode = 2;
  }
}

function canonicalOutput(value) {
  const sort = (input) => Array.isArray(input)
    ? input.map(sort)
    : input !== null && typeof input === "object"
      ? Object.fromEntries(Object.keys(input).sort().map((key) => [key, sort(input[key])]))
      : input;
  return `${JSON.stringify(sort(value))}\n`;
}

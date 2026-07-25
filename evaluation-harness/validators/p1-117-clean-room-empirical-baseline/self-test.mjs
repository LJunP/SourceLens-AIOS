#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  P117QualityNonPass,
  canonicalJsonBytes,
  identityOf,
  parseFrozenJson,
  sha256,
} from "./core.mjs";
import {
  buildChatCompletionsRequest,
  buildProviderPayload,
  validateChatCompletionsRequest,
  validateProviderPayload,
  validateProviderResponseOutcome,
  validateSafeDisclosures,
} from "./disclosure.mjs";
import {
  FIXTURE_ROOT,
  REPOSITORY_ROOT,
  loadMatrix,
  validateConfiguration,
  validateFreezeBoundaryState,
  validateMatrix,
  validateP2Preregistration,
  validatePreregistrationMutation,
  validateSnapshotAlias,
} from "./preflight.mjs";
import {
  validateAccountingLedger,
  validateEvidenceIdentity,
  validateFormalRuntimeReceipt,
  validateReplayEvidence,
  validateReportedAggregate,
  validateResultPopulation,
  validateRollbackEvidence,
  validateRunManifest,
  validateRunRecordEvidence,
  validateTraceEvidence,
} from "../../evaluator/p1-117-clean-room-empirical-baseline/recompute.mjs";
import {
  guardResponseBytesBeforeIdentity,
} from "../../harness/p1-117-clean-room-empirical-baseline/provider-client.mjs";

const cases = [];
const consumedFixtures = new Set();
function fixture(caseId, value) {
  const fixtureId = `QUALITY-ONE-TIME-${caseId}`;
  if (consumedFixtures.has(fixtureId)) throw new Error(`fixture reused: ${fixtureId}`);
  consumedFixtures.add(fixtureId);
  return structuredClone(value);
}
function check(name, fn) {
  fn();
  cases.push({ case_id: name, status: "PASS" });
}

function rejects(name, expected, fn) {
  try {
    fn();
  } catch (error) {
    const actualReason = error instanceof P117QualityNonPass
      ? error.reasonCode
      : error?.code;
    if (actualReason === expected) {
      cases.push({ case_id: name, status: "PASS", reason_code: expected });
      return;
    }
    throw error;
  }
  throw new Error(`${name} did not reject`);
}

const fixturePath = (name) => join(REPOSITORY_ROOT, FIXTURE_ROOT, name);
const disclosures = parseFrozenJson(
  readFileSync(fixturePath("safe-disclosures.json")),
  "SAFE_DISCLOSURE_SCHEMA_INVALID",
);
const responseSchemaBytes = readFileSync(fixturePath("response-schema.json"));
const responseSchemaIdentity = {
  path: `${FIXTURE_ROOT}/response-schema.json`,
  sha256: "550ca74981e0e32b37fc02f434fdb0f9c53c0c5f54b4dbba0b204f16f524193f",
  byte_length: responseSchemaBytes.length,
};

check("QUALITY_SAFE_DISCLOSURES_6_OF_6", () => {
  validateSafeDisclosures(disclosures);
});

const exampleEntry = {
  run_id: "P1-117-RUN-001-REP001-B0-A",
  task_id: "SL-P1-REP-001-RANGE-NORMALIZATION",
  system: "B0",
  variant: "A",
  finite_operation_ids: disclosures.tasks[0].finite_operations.map(
    (operation) => operation.operation_id,
  ),
  accepted_scanner_binding: null,
};
const exampleConfiguration = {
  model_ref: "gpt-5.6-luna",
  temperature: 0,
  max_output_tokens: 2048,
};
const built = buildChatCompletionsRequest({
  entry: exampleEntry,
  configuration: exampleConfiguration,
  disclosure: disclosures.tasks[0],
  responseSchemaIdentity,
});

check("CHAT_COMPLETIONS_EXACT_REQUEST_PASS", () => {
  validateChatCompletionsRequest({
    repositoryRoot: REPOSITORY_ROOT,
    requestBytes: canonicalJsonBytes(built.body),
    entry: exampleEntry,
    configuration: exampleConfiguration,
    disclosure: disclosures.tasks[0],
    responseSchemaIdentity,
  });
});

rejects(
  "CHAT_COMPLETIONS_USER_CONTENT_DRIFT_REJECTED",
  "CHAT_COMPLETIONS_REQUEST_IDENTITY_MISMATCH",
  () => {
    const mutated = structuredClone(built.body);
    mutated.messages[1].content += "source bytes";
    validateChatCompletionsRequest({
      repositoryRoot: REPOSITORY_ROOT,
      requestBytes: canonicalJsonBytes(mutated),
      entry: exampleEntry,
      configuration: exampleConfiguration,
      disclosure: disclosures.tasks[0],
      responseSchemaIdentity,
    });
  },
);

rejects(
  "CHAT_COMPLETIONS_SYSTEM_INSTRUCTION_DRIFT_REJECTED",
  "CHAT_COMPLETIONS_REQUEST_IDENTITY_MISMATCH",
  () => {
    const mutated = structuredClone(built.body);
    mutated.messages[0].content += " drift";
    validateChatCompletionsRequest({
      repositoryRoot: REPOSITORY_ROOT,
      requestBytes: canonicalJsonBytes(mutated),
      entry: exampleEntry,
      configuration: exampleConfiguration,
      disclosure: disclosures.tasks[0],
      responseSchemaIdentity,
    });
  },
);

check("PROVIDER_SELECTION_ACCEPTED", () => {
  const result = validateProviderResponseOutcome(
    canonicalJsonBytes({
      schema_version: "p1-117-provider-selection/v1",
      selected_operation_id: "REP001_ASCENDING_ENDPOINTS",
    }),
    exampleEntry.finite_operation_ids,
  );
  if (!result.accepted) throw new Error("accepted response rejected");
});

check("UNKNOWN_OPERATION_IS_FAILED_RUN_NOT_EVALUATOR_ERROR", () => {
  const result = validateProviderResponseOutcome(
    canonicalJsonBytes({
      schema_version: "p1-117-provider-selection/v1",
      selected_operation_id: "REP001_UNKNOWN_OPERATION",
    }),
    exampleEntry.finite_operation_ids,
  );
  if (result.accepted || result.reasonCode !== "UNKNOWN_OPERATION_ID") {
    throw new Error("unknown operation semantics drifted");
  }
});

check("SAFE_REJECTION_IS_FAILED_RUN_NOT_EVALUATOR_ERROR", () => {
  const result = validateProviderResponseOutcome(
    canonicalJsonBytes({
      schema_version: "p1-117-provider-response-safe-rejection/v1",
      status: "REJECTED",
      reason_code: "PROVIDER_RESPONSE_SCHEMA_INVALID",
      raw_response_sha256: "a".repeat(64),
      raw_response_byte_length: 17,
      raw_response_retained: false,
    }),
    exampleEntry.finite_operation_ids,
  );
  if (result.accepted || result.selectedOperationId !== null) {
    throw new Error("safe rejection semantics drifted");
  }
});

const { matrix } = loadMatrix();
check("MATRIX_EXACT_36_ENTRY_VALIDATION", () => validateMatrix(REPOSITORY_ROOT, matrix));

const negativeCatalog = parseFrozenJson(
  readFileSync(fixturePath("negative-cases.json")),
  "NEGATIVE_CATALOG_INVALID",
);
check("NEGATIVE_CATALOG_CLOSED_48_CASES", () => {
  if (
    negativeCatalog.cases.length !== 48
      || new Set(negativeCatalog.cases.map((entry) => entry.case_id)).size !== 48
      || negativeCatalog.cases.some((entry) => !["PRE_EXECUTION", "POST_EXECUTION"].includes(entry.stage))
  ) {
    throw new Error("negative catalog drifted");
  }
});

function canonicalJsonl(events) {
  return Buffer.from(
    `${events.map((event) => canonicalJsonBytes(event).toString("utf8").slice(0, -1)).join("\n")}\n`,
    "utf8",
  );
}

function traceEvents(entry, includeB2Child = true) {
  const taskBinding = matrix.task_bindings.find(
    (binding) => binding.task_id === entry.task_id,
  );
  const admissionData = {
    task_spec: entry.task_spec,
    environment_snapshot: taskBinding.environment_snapshot,
    dataset_task_binding: taskBinding.dataset_task_binding,
    source_template_binding: taskBinding.source_template_binding,
    source_template_manifest: {
      sha256: taskBinding.source_template_binding.manifest_sha256,
      byte_length: taskBinding.source_template_binding.manifest_byte_length,
      file_count: taskBinding.source_template_binding.file_count,
    },
    wrapper: entry.executable,
    configuration: entry.system_configuration,
  };
  const identity = () => ({ sha256: "a".repeat(64), byte_length: 1 });
  const localToolLedger = entry.system === "B1"
    ? {
        schema_version: "p1-117-b1-local-tool-ledger/v1",
        run_id: entry.run_id,
        operations: [
          "file_listing",
          "lexical_search",
          "trusted_finite_operation_compiler",
          "verification_ledger",
        ].map((operationId, index) => ({
          sequence: index + 1,
          operation_id: operationId,
          status: operationId === "trusted_finite_operation_compiler"
            ? "EXECUTED_LOCAL"
            : "EXECUTED_LOCAL_RESULT_WITHHELD_FROM_PROVIDER",
          input_identity: identity(),
          output_identity: identity(),
          executable_identity: identity(),
        })),
      }
    : null;
  const scannerPreCallIdentity = {
    path: "/owned/scanner",
    sha256: "b".repeat(64),
    byte_length: 1,
    type: "REGULAR_FILE",
    dev: "1",
    ino: "2",
    uid: 3,
    gid: 4,
    mode: 0o700,
    verification_status: "PASS",
  };
  const childInvocation = entry.system === "B2" && includeB2Child
    ? {
        operation_id: "repository_analysis.scan",
        real_invocation: true,
        accepted_binding_sha256: entry.accepted_scanner_binding.sha256,
        command_ledger_sha256: "c".repeat(64),
        scanner_artifact_sha256: "b".repeat(64),
        scanner_pre_call_identity: scannerPreCallIdentity,
      }
    : null;
  return ["admission", "execution", "validation", "result", "rollback"].map(
    (eventType, index) => ({
      event_sequence: index + 1,
      event_type: eventType,
      run_id: entry.run_id,
      ...(index === 0
        ? { data: admissionData }
        : index === 1
        ? {
            data: {
              local_tool_ledger: localToolLedger,
              child_invocation: childInvocation,
            },
          }
        : {}),
      ...(index === 1 && childInvocation !== null
        ? { child_invocation: structuredClone(childInvocation) }
        : {}),
      ...(index === 1 && localToolLedger !== null
        ? { local_tool_ledger: structuredClone(localToolLedger) }
        : {}),
    }),
  );
}

const goldenManifest = (entry) => ({
  schema_version: "p1-117-run-manifest/v1",
  entry: {
    slot: entry.slot,
    entry_id: entry.entry_id,
    run_id: entry.run_id,
    task_id: entry.task_id,
    system: entry.system,
    variant: entry.variant,
    repetition_id: entry.repetition_id,
  },
  terminal: {
    status: "COMPLETED",
    reason_code: "AGENT_COMPLETE",
    invalid_run_reason: null,
    post_hoc_excluded: false,
  },
  selected_operation_id: entry.finite_operation_ids[0],
  evidence: Object.fromEntries(
    [
      "request_safe", "response_safe", "run_record", "trace",
      "external_truth_binding", "stable_projection", "replay_receipt",
      "rollback_receipt", "test_receipt",
    ].map((role) => [
      role,
      { relative_path: `${role}.json`, sha256: "a".repeat(64), byte_length: 1 },
    ]),
  ),
  accounting: {
    provider_requests: 1,
    automatic_retries: 0,
    input_tokens: 1,
    output_tokens: 1,
    latency_ms: 1,
    cost: {
      status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
      currency: "USD",
      amount: null,
    },
    successful_loopback_connections: 1,
  },
  observed_effects: {
    non_loopback_network_connections: 0,
    remote: false,
    production: false,
    public: false,
    restricted_source_egress: false,
    secret_sink_writes: 0,
  },
});

const negativeExecutions = [];
function negative(caseId, expectedReason, fn) {
  const owned = fixture(caseId, { case_id: caseId, consumed: false });
  rejects(caseId, expectedReason, () => {
    if (owned.consumed) throw new Error(`fixture reuse: ${caseId}`);
    owned.consumed = true;
    fn();
  });
  negativeExecutions.push({
    case_id: caseId,
    fixture_id: `QUALITY-ONE-TIME-${caseId}`,
    expected_reason_code: expectedReason,
    provider_requests: 0,
    secret_reads: 0,
    network_connections: 0,
  });
}

negative("N01_PREREGISTRATION_MISSING", "PREREGISTRATION_MISSING", () => {
  validateFreezeBoundaryState({
    preregistrationPresent: false,
    preregistrationIdentityMatches: true,
    executableReceiptPresent: true,
    executableIdentitiesMatch: true,
  });
});
negative("N02_PREREGISTRATION_MUTATED", "PREREGISTRATION_IDENTITY_MISMATCH", () => {
  validateFreezeBoundaryState({
    preregistrationPresent: true,
    preregistrationIdentityMatches: false,
    executableReceiptPresent: true,
    executableIdentitiesMatch: true,
  });
});
negative("N03_EXECUTABLE_RECEIPT_MISSING", "EXECUTABLE_FREEZE_RECEIPT_MISSING", () => {
  validateFreezeBoundaryState({
    preregistrationPresent: true,
    preregistrationIdentityMatches: true,
    executableReceiptPresent: false,
    executableIdentitiesMatch: true,
  });
});
negative("N04_EXECUTABLE_IDENTITY_DRIFT", "EXECUTABLE_IDENTITY_MISMATCH", () => {
  validateFreezeBoundaryState({
    preregistrationPresent: true,
    preregistrationIdentityMatches: true,
    executableReceiptPresent: true,
    executableIdentitiesMatch: false,
  });
});
negative("N05_UNKNOWN_MATRIX_ENTRY", "MATRIX_POPULATION_MISMATCH", () => {
  const candidate = fixture("N05-MATRIX", matrix);
  candidate.schedule.push(structuredClone(candidate.schedule[0]));
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N06_DUPLICATE_MATRIX_ENTRY", "MATRIX_DUPLICATE", () => {
  const candidate = fixture("N06-MATRIX", matrix);
  candidate.schedule[1].run_id = candidate.schedule[0].run_id;
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N07_MATRIX_REORDERED", "MATRIX_ORDER_MISMATCH", () => {
  const candidate = fixture("N07-MATRIX", matrix);
  [candidate.schedule[0], candidate.schedule[1]] = [candidate.schedule[1], candidate.schedule[0]];
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N08_TASKSPEC_IDENTITY_DRIFT", "TASKSPEC_IDENTITY_MISMATCH", () => {
  const candidate = fixture("N08-MATRIX", matrix);
  candidate.schedule[0].task_spec.sha256 = "0".repeat(64);
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N09_DATASET_IDENTITY_DRIFT", "DATASET_IDENTITY_MISMATCH", () => {
  const candidate = fixture("N09-MATRIX", matrix);
  candidate.dataset_manifest.sha256 = "0".repeat(64);
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N10_SAFE_DISCLOSURE_DRIFT", "SAFE_DISCLOSURE_IDENTITY_MISMATCH", () => {
  const candidate = fixture("N10-MATRIX", matrix);
  candidate.safe_disclosures.sha256 = "0".repeat(64);
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N11_CONFIGURATION_IDENTITY_DRIFT", "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH", () => {
  const candidate = fixture("N11-MATRIX", matrix);
  candidate.schedule[0].system_configuration.sha256 = "0".repeat(64);
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N12_SCANNER_BINDING_DRIFT", "SCANNER_BINDING_IDENTITY_MISMATCH", () => {
  const candidate = fixture("N12-MATRIX", matrix);
  candidate.schedule[4].accepted_scanner_binding.sha256 = "0".repeat(64);
  validateMatrix(REPOSITORY_ROOT, candidate);
});

const configBytes = readFileSync(
  join(REPOSITORY_ROOT, matrix.schedule[0].system_configuration.path),
);
const goldenConfiguration = parseFrozenJson(
  configBytes,
  "SYSTEM_CONFIGURATION_SCHEMA_INVALID",
);
for (const [caseId, reason, mutate] of [
  ["N13_PROVIDER_REQUEST_CAP_EXCEEDED", "PROVIDER_REQUEST_CAP_EXCEEDED", (value) => { value.provider_requests_exact = 2; }],
  ["N14_INPUT_TOKEN_CAP_EXCEEDED", "INPUT_TOKEN_CAP_EXCEEDED", (value) => { value.input_tokens_reserved = 500001; }],
  ["N15_OUTPUT_TOKEN_CAP_EXCEEDED", "OUTPUT_TOKEN_CAP_EXCEEDED", (value) => { value.max_output_tokens = 100001; }],
  ["N16_AUTOMATIC_RETRY_REQUESTED", "AUTOMATIC_RETRY_FORBIDDEN", (value) => { value.automatic_retries = 1; }],
  ["N17_NON_LOOPBACK_ENDPOINT", "LOOPBACK_ENDPOINT_REQUIRED", (value) => { value.endpoint_policy.host = "example.invalid"; }],
  ["N18_REDIRECT_PROXY_DNS_FALLBACK", "TRANSPORT_POLICY_INVALID", (value) => { value.endpoint_policy.follow_redirects = true; }],
]) {
  negative(caseId, reason, () => {
    const value = fixture(`${caseId}-CONFIG`, goldenConfiguration);
    mutate(value);
    validateConfiguration(value, matrix.schedule[0], matrix);
  });
}

negative("N19_RESTRICTED_SOURCE_PAYLOAD", "RESTRICTED_SOURCE_EGRESS_FORBIDDEN", () => {
  const disclosure = fixture("N19-DISCLOSURE", disclosures.tasks[0]);
  disclosure.safe_problem_statement = readFileSync(
    join(
      REPOSITORY_ROOT,
      "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/source-template/src/range.mjs",
    ),
    "utf8",
  ).split("\n").find((line) => line.trim().length >= 16).trim();
  const payload = buildProviderPayload({
    entry: exampleEntry,
    disclosure,
    responseSchemaIdentity,
  });
  validateProviderPayload({
    repositoryRoot: REPOSITORY_ROOT,
    payloadBytes: canonicalJsonBytes(payload),
    entry: exampleEntry,
    disclosure,
    responseSchemaIdentity,
  });
});
negative("N20_SECRET_SINK_REQUESTED", "SECRET_SINK_FORBIDDEN", () => {
  const disclosure = fixture("N20-DISCLOSURE", disclosures.tasks[0]);
  disclosure.safe_problem_statement = "Authorization: Bearer prohibited-secret";
  const payload = buildProviderPayload({
    entry: exampleEntry,
    disclosure,
    responseSchemaIdentity,
  });
  validateProviderPayload({
    repositoryRoot: REPOSITORY_ROOT,
    payloadBytes: canonicalJsonBytes(payload),
    entry: exampleEntry,
    disclosure,
    responseSchemaIdentity,
  });
});

const manifests = matrix.schedule.map(goldenManifest);
function goldenAccountingLedgerBytes(values) {
  const caps = {
    provider_requests_max: 60,
    automatic_retry_max: 0,
    input_tokens_max: 500000,
    output_tokens_max: 100000,
    currency: "USD",
    max_spend: 25,
  };
  const totals = (requestCount, observedCount) => ({
    provider_requests_accounted: requestCount,
    input_tokens_accounted: requestCount * 12000,
    output_tokens_accounted: requestCount * 2048,
    input_tokens_observed: observedCount,
    output_tokens_observed: observedCount,
    automatic_retries: 0,
    cost_observed_usd: null,
    cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
  });
  const events = [{
    schema_version: "p1-117-accounting-event/v1",
    sequence: 1,
    event_type: "LEDGER_OPENED",
    run_id: null,
    data: {
      caps,
      cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
    },
    totals: totals(0, 0),
  }];
  for (const [index, entry] of matrix.schedule.entries()) {
    const requestCount = index + 1;
    events.push({
      schema_version: "p1-117-accounting-event/v1",
      sequence: events.length + 1,
      event_type: "REQUEST_RESERVED",
      run_id: entry.run_id,
      data: {
        input_token_upper_bound: 12000,
        input_token_upper_bound_method: "QUALITY_FROZEN_PER_RUN_RESERVATION",
        output_token_upper_bound: 2048,
        request_count: 1,
        automatic_retry_count: 0,
      },
      totals: totals(requestCount, index),
    });
    events.push({
      schema_version: "p1-117-accounting-event/v1",
      sequence: events.length + 1,
      event_type: "RESPONSE_OBSERVED",
      run_id: entry.run_id,
      data: {
        status_code: 200,
        peer_address: "127.0.0.1",
        provider_requests: 1,
        successful_loopback_connections:
          values[index].accounting.successful_loopback_connections,
        outcome: "RESPONSE_WRAPPER_ACCEPTED",
        automatic_retries: 0,
        prompt_tokens: values[index].accounting.input_tokens,
        completion_tokens: values[index].accounting.output_tokens,
        latency_ms: values[index].accounting.latency_ms,
        observed_cost_usd: null,
        cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
        monetary_cap_empirically_enforced: false,
      },
      totals: totals(requestCount, requestCount),
    });
  }
  const beforeClose = Buffer.concat(events.map(canonicalJsonBytes));
  events.push({
    schema_version: "p1-117-accounting-event/v1",
    sequence: 74,
    event_type: "LEDGER_CLOSED",
    run_id: null,
    data: {
      status: "COMPLETE",
      ledger_sha256_before_close: sha256(beforeClose),
    },
    totals: totals(36, 36),
  });
  return canonicalJsonl(events);
}
const goldenLedgerBytes = goldenAccountingLedgerBytes(manifests);
const goldenManifestPopulation = matrix.schedule.map((entry) => ({
  run_id: entry.run_id,
  sha256: "d".repeat(64),
  byte_length: 1,
}));
const goldenManifestPopulationBytes = canonicalJsonBytes(goldenManifestPopulation);
const goldenRuntimeReceipt = {
  schema_version: "p1-117-formal-runtime-receipt/v1",
  status: "COMPLETE",
  scheduled_runs: 36,
  completed_run_manifests: 36,
  provider_requests: 36,
  automatic_retries: 0,
  secret_reads: 1,
  provider_session_closed: true,
  owned_secret_buffer_overwrite_attempted: true,
  whole_process_memory_zeroization_claim: "NOT_CLAIMED",
  accounting_ledger: identityOf(goldenLedgerBytes),
  run_manifest_population: {
    count: 36,
    aggregate_sha256: sha256(goldenManifestPopulationBytes),
    aggregate_byte_length: goldenManifestPopulationBytes.length,
  },
  cost: {
    status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
    currency: "USD",
    amount: null,
  },
};

check("ACCOUNTING_LEDGER_AND_RUNTIME_RECEIPT_POSITIVE", () => {
  validateAccountingLedger(goldenLedgerBytes, matrix.schedule, manifests);
  validateFormalRuntimeReceipt({
    receipt: goldenRuntimeReceipt,
    ledgerBytes: goldenLedgerBytes,
    manifestPopulation: goldenManifestPopulation,
    requests: 36,
  });
});

negative("N21_MISSING_SCHEDULED_RUN", "SCHEDULED_RUN_MISSING", () => {
  validateResultPopulation(matrix.schedule, fixture("N21-MANIFESTS", manifests).slice(0, -1));
});
negative("N22_DUPLICATE_RUN_RESULT", "RUN_RESULT_DUPLICATE", () => {
  const candidate = fixture("N22-MANIFESTS", manifests);
  candidate[35].entry.run_id = candidate[34].entry.run_id;
  validateResultPopulation(matrix.schedule, candidate);
});
negative("N23_TRACE_EVENT_MISSING", "TRACE_SEQUENCE_INVALID", () => {
  const events = fixture("N23-TRACE", traceEvents(matrix.schedule[0]));
  events.splice(2, 1);
  validateTraceEvidence(canonicalJsonl(events), matrix.schedule[0]);
});
negative("N24_TRACE_EVENT_REORDERED", "TRACE_SEQUENCE_INVALID", () => {
  const events = fixture("N24-TRACE", traceEvents(matrix.schedule[0]));
  [events[2], events[3]] = [events[3], events[2]];
  validateTraceEvidence(canonicalJsonl(events), matrix.schedule[0]);
});
negative("N25_TRACE_IDENTITY_DRIFT", "TRACE_IDENTITY_MISMATCH", () => {
  const events = fixture("N25-TRACE", traceEvents(matrix.schedule[0]));
  events[2].run_id = "DRIFT";
  validateTraceEvidence(canonicalJsonl(events), matrix.schedule[0]);
});
negative("N26_RUN_RECORD_DRIFT", "RUN_RECORD_IDENTITY_MISMATCH", () => {
  validateRunRecordEvidence({
    schema_version: "1.0",
    run_id: "DRIFT",
    task_id: matrix.schedule[0].task_id,
    adapter_id: "B0",
    repetition_id: 1,
    policy_violations: [],
  }, matrix.schedule[0]);
});
negative("N27_STABLE_PROJECTION_DRIFT", "STABLE_PROJECTION_IDENTITY_MISMATCH", () => {
  const bytes = Buffer.from("stable\n", "utf8");
  validateEvidenceIdentity(
    bytes,
    { sha256: "0".repeat(64), byte_length: bytes.length },
    "STABLE_PROJECTION_IDENTITY_MISMATCH",
  );
});
negative("N28_REPLAY_MISMATCH", "REPLAY_MISMATCH", () => {
  const projection = canonicalJsonBytes({ projection: "stable" });
  validateReplayEvidence({
    status: "PASS",
    run_id: matrix.schedule[0].run_id,
    stable_projection_identity: { sha256: "0".repeat(64), byte_length: projection.length },
  }, projection, matrix.schedule[0]);
});
negative("N29_ROLLBACK_IDENTITY_DRIFT", "ROLLBACK_IDENTITY_MISMATCH", () => {
  validateRollbackEvidence({
    status: "PASS_EXACT",
    run_id: "DRIFT",
    nonowned_paths_touched: 0,
    source_state_restored: true,
  }, matrix.schedule[0]);
});
negative("N30_NONOWNED_CLEANUP", "NONOWNED_CLEANUP_FORBIDDEN", () => {
  validateRollbackEvidence({
    status: "PASS_EXACT",
    run_id: matrix.schedule[0].run_id,
    nonowned_paths_touched: 1,
    source_state_restored: true,
  }, matrix.schedule[0]);
});
negative("N31_EVIDENCE_ROLE_MISSING", "EVIDENCE_INCOMPLETE", () => {
  const candidate = fixture("N31-MANIFEST", goldenManifest(matrix.schedule[0]));
  delete candidate.evidence.response_safe;
  validateRunManifest(candidate, matrix.schedule[0]);
});
negative("N32_EVIDENCE_HASH_DRIFT", "EVIDENCE_IDENTITY_MISMATCH", () => {
  const bytes = Buffer.from("evidence\n", "utf8");
  validateEvidenceIdentity(bytes, { sha256: "0".repeat(64), byte_length: bytes.length });
});
negative("N33_POST_HOC_EXCLUSION", "POST_HOC_EXCLUSION_FORBIDDEN", () => {
  const candidate = fixture("N33-MANIFEST", goldenManifest(matrix.schedule[0]));
  candidate.terminal.post_hoc_excluded = true;
  validateRunManifest(candidate, matrix.schedule[0]);
});
negative("N34_RESULT_AWARE_PREREGISTRATION_MUTATION", "PREREGISTRATION_MUTATION_FORBIDDEN", () => {
  validatePreregistrationMutation({
    resultAwareMutation: true,
  });
});
negative("N35_B2_CHILD_MISSING", "B2_SCANNER_CHILD_REQUIRED", () => {
  const entry = matrix.schedule[4];
  validateTraceEvidence(canonicalJsonl(traceEvents(entry, false)), entry);
});
negative("N36_AGGREGATE_MISMATCH", "AGGREGATE_RECOMPUTATION_MISMATCH", () => {
  validateReportedAggregate({ numerator: 1, denominator: 36 }, { numerator: 2, denominator: 36 });
});
negative("N37_B1_LOCAL_TOOL_LEDGER_INCOMPLETE", "B1_LOCAL_TOOL_LEDGER_INVALID", () => {
  const entry = matrix.schedule[2];
  const events = fixture("N37-TRACE", traceEvents(entry));
  events[1].data.local_tool_ledger.operations[1].output_identity = null;
  validateTraceEvidence(canonicalJsonl(events), entry);
});
negative("N38_B2_SCANNER_PRECALL_IDENTITY_INCOMPLETE", "B2_SCANNER_PRECALL_IDENTITY_INVALID", () => {
  const entry = matrix.schedule[4];
  const events = fixture("N38-TRACE", traceEvents(entry));
  delete events[1].child_invocation.scanner_pre_call_identity.ino;
  delete events[1].data.child_invocation.scanner_pre_call_identity.ino;
  validateTraceEvidence(canonicalJsonl(events), entry);
});
negative("N39_NON200_SECRET_ECHO_BEFORE_IDENTITY", "SECRET_SINK_FORBIDDEN", () => {
  const secret = Buffer.from("quality-dummy-secret", "utf8");
  const rawNon200 = Buffer.from(
    `{"error":"echo quality-dummy-secret","status":500}\n`,
    "utf8",
  );
  try {
    guardResponseBytesBeforeIdentity(rawNon200, secret);
  } catch (error) {
    if (
      error.raw_response_identity_created !== false
        || error.evidence_created !== false
    ) {
      throw new Error("Secret echo guard created a derived identity or Evidence");
    }
    throw error;
  }
});
negative("N40_ENVIRONMENT_SNAPSHOT_IDENTITY_DRIFT", "ENVIRONMENT_SNAPSHOT_IDENTITY_MISMATCH", () => {
  const candidate = fixture("N40-MATRIX", matrix);
  candidate.task_bindings[0].environment_snapshot.sha256 = "0".repeat(64);
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N41_SOURCE_TEMPLATE_MANIFEST_DRIFT", "SOURCE_TEMPLATE_IDENTITY_MISMATCH", () => {
  const candidate = fixture("N41-MATRIX", matrix);
  candidate.task_bindings[0].source_template_binding.manifest_sha256 = "0".repeat(64);
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N42_DATASET_TASK_BINDING_DRIFT", "DATASET_TASK_BINDING_MISMATCH", () => {
  const candidate = fixture("N42-MATRIX", matrix);
  candidate.task_bindings[0].dataset_task_binding.base_commit = "0".repeat(40);
  validateMatrix(REPOSITORY_ROOT, candidate);
});
negative("N43_SHARED_SNAPSHOT_ALIAS_MISBOUND", "ENVIRONMENT_SNAPSHOT_TASK_BINDING_MISMATCH", () => {
  const binding = matrix.task_bindings[0];
  const taskSpec = parseFrozenJson(
    readFileSync(join(REPOSITORY_ROOT, binding.task_spec.path)),
    "TASKSPEC_SCHEMA_INVALID",
  );
  const snapshot = parseFrozenJson(
    readFileSync(join(REPOSITORY_ROOT, binding.environment_snapshot.path)),
    "ENVIRONMENT_SNAPSHOT_SCHEMA_INVALID",
  );
  snapshot.snapshot_id_alias = "ENV-DRIFT";
  validateSnapshotAlias(snapshot, taskSpec, binding);
});
negative("N44_TRACE_MATERIALIZATION_BINDING_DRIFT", "TRACE_MATERIALIZATION_BINDING_MISMATCH", () => {
  const entry = matrix.schedule[0];
  const binding = matrix.task_bindings[0];
  const events = fixture("N44-TRACE", traceEvents(entry));
  events[0].data.environment_snapshot.sha256 = "0".repeat(64);
  validateTraceEvidence(canonicalJsonl(events), entry, binding);
});
negative("N45_P2_PROPOSED_BUDGET_PLACEHOLDER", "P2_PREREGISTRATION_BUDGET_INVALID", () => {
  const value = parseFrozenJson(
    readFileSync(fixturePath("p2-context-engine-preregistration.json")),
    "P2_PREREGISTRATION_BUDGET_INVALID",
  );
  value.budget.provider_requests_max = "FOUNDER_TO_FREEZE_AT_P2_ENTRY";
  validateP2Preregistration(value);
});
negative("N46_ACCOUNTING_LEDGER_EVENT_MISSING", "ACCOUNTING_LEDGER_SEQUENCE_INVALID", () => {
  const events = goldenLedgerBytes.toString("utf8").trimEnd()
    .split("\n").map((line) => JSON.parse(line));
  events.splice(2, 1);
  validateAccountingLedger(canonicalJsonl(events), matrix.schedule, manifests);
});
negative("N47_ACCOUNTING_LEDGER_CLOSE_HASH_DRIFT", "ACCOUNTING_LEDGER_CLOSE_INVALID", () => {
  const events = goldenLedgerBytes.toString("utf8").trimEnd()
    .split("\n").map((line) => JSON.parse(line));
  events.at(-1).data.ledger_sha256_before_close = "0".repeat(64);
  validateAccountingLedger(canonicalJsonl(events), matrix.schedule, manifests);
});
negative("N48_FORMAL_RUNTIME_RECEIPT_POPULATION_DRIFT", "FORMAL_RUNTIME_RECEIPT_INVALID", () => {
  const receipt = fixture("N48-RUNTIME-RECEIPT", goldenRuntimeReceipt);
  receipt.run_manifest_population.aggregate_sha256 = "0".repeat(64);
  validateFormalRuntimeReceipt({
    receipt,
    ledgerBytes: goldenLedgerBytes,
    manifestPopulation: goldenManifestPopulation,
    requests: 36,
  });
});

check("B1_PRECONDITION_FAILURE_REMAINS_IDENTITY_BOUND_FAILED_RUN", () => {
  const entry = matrix.schedule[2];
  const events = traceEvents(entry);
  const compiler = events[1].data.local_tool_ledger.operations[2];
  events[1].data.selected_operation_id = null;
  compiler.status = "NOT_RUN_PRECONDITION_FAILED";
  compiler.input_identity = null;
  compiler.output_identity = null;
  compiler.executable_identity = null;
  events[1].local_tool_ledger = structuredClone(events[1].data.local_tool_ledger);
  validateTraceEvidence(canonicalJsonl(events), entry);
});

check("TRACE_MATERIALIZATION_CROSS_BIND_PASS", () => {
  const entry = matrix.schedule[0];
  validateTraceEvidence(
    canonicalJsonl(traceEvents(entry)),
    entry,
    matrix.task_bindings[0],
  );
});

rejects(
  "B2_NUMERIC_INODE_TYPE_DRIFT_REJECTED",
  "B2_SCANNER_PRECALL_IDENTITY_INVALID",
  () => {
    const entry = matrix.schedule[4];
    const events = fixture("B2-NUMERIC-INODE-TRACE", traceEvents(entry));
    events[1].child_invocation.scanner_pre_call_identity.ino = 2;
    events[1].data.child_invocation.scanner_pre_call_identity.ino = 2;
    validateTraceEvidence(canonicalJsonl(events), entry);
  },
);

if (negativeExecutions.length !== negativeCatalog.cases.length) {
  throw new Error("negative execution count differs from frozen catalog");
}
for (const [index, execution] of negativeExecutions.entries()) {
  const frozen = negativeCatalog.cases[index];
  if (
    execution.case_id !== frozen.case_id
      || execution.expected_reason_code !== frozen.reason_code
  ) {
    throw new Error(`negative execution drifted at ${index}`);
  }
}

process.stdout.write(`${JSON.stringify({
  status: "PASS",
  assertion_count: cases.length,
  cases,
  negative_execution_count: negativeExecutions.length,
  negative_executions: negativeExecutions,
  one_time_fixture_count: consumedFixtures.size,
  fixture_reuse_count: 0,
  provider_requests: 0,
  secret_reads: 0,
  network_connections: 0,
})}\n`);

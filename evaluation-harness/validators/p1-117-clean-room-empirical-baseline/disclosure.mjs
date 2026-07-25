import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  assert,
  canonicalJsonBytes,
  exactKeys,
  identityOf,
  isObject,
  parseCanonicalJson,
  parseFrozenJson,
  readBoundFile,
  sameJson,
} from "./core.mjs";

const DATASET_ROOT = "evaluation-harness/datasets/p1-representative-task-dataset-v1";
const SYSTEM_MODES = Object.freeze({
  B0: "ISSUE_ONLY_SAFE_PROBLEM_STATEMENT_AND_FINITE_OPERATIONS",
  B1: "SAFE_PROBLEM_OPERATIONS_AND_QUALITY_FROZEN_SAFE_TOOL_FACTS",
  B2: "SAFE_PROBLEM_OPERATIONS_AND_NONCONTENT_ACCEPTED_SCANNER_METRICS",
});
export const SYSTEM_INSTRUCTION = [
  "Select exactly one operation from the supplied finite_operations catalog.",
  "Return exact JSON with only schema_version and selected_operation_id.",
  "schema_version must be p1-117-provider-selection/v1.",
  "Do not return prose, markdown, source, tests, patches, secrets, tool requests, or any additional key.",
].join(" ");

function validateOperations(operations, taskId) {
  assert(Array.isArray(operations) && operations.length === 3, "SAFE_DISCLOSURE_SCHEMA_INVALID");
  const ids = new Set();
  const prefixMatch = taskId.match(/REP-(\d{3})/);
  assert(prefixMatch !== null, "SAFE_DISCLOSURE_SCHEMA_INVALID");
  const operationPrefix = `REP${prefixMatch[1]}_`;
  for (const operation of operations) {
    exactKeys(operation, ["operation_id", "description"], "SAFE_DISCLOSURE_SCHEMA_INVALID");
    assert(
      typeof operation.operation_id === "string"
        && operation.operation_id.startsWith(operationPrefix)
        && typeof operation.description === "string"
        && operation.description.length > 0
        && !ids.has(operation.operation_id),
      "SAFE_DISCLOSURE_SCHEMA_INVALID",
    );
    ids.add(operation.operation_id);
  }
  return [...ids];
}

export function validateSafeDisclosures(value) {
  assert(value.schema_version === "p1-117-safe-disclosures/v1", "SAFE_DISCLOSURE_SCHEMA_INVALID");
  assert(value.classification?.restricted_source_allowed === false, "RESTRICTED_SOURCE_EGRESS_FORBIDDEN");
  assert(value.classification?.contains_dataset_source_bytes === false, "RESTRICTED_SOURCE_EGRESS_FORBIDDEN");
  assert(value.classification?.contains_dataset_test_bytes === false, "RESTRICTED_SOURCE_EGRESS_FORBIDDEN");
  assert(value.classification?.contains_reference_patch_bytes === false, "RESTRICTED_SOURCE_EGRESS_FORBIDDEN");
  assert(value.classification?.contains_expected_operation_ids === false, "ORACLE_LEAKAGE_FORBIDDEN");
  assert(Array.isArray(value.tasks) && value.tasks.length === 6, "SAFE_DISCLOSURE_POPULATION_MISMATCH");
  const taskIds = new Set();
  for (const task of value.tasks) {
    exactKeys(
      task,
      ["task_id", "safe_problem_statement", "finite_operations", "safe_tool_facts"],
      "SAFE_DISCLOSURE_SCHEMA_INVALID",
    );
    assert(!taskIds.has(task.task_id), "SAFE_DISCLOSURE_POPULATION_MISMATCH");
    taskIds.add(task.task_id);
    validateOperations(task.finite_operations, task.task_id);
    assert(Array.isArray(task.safe_tool_facts) && task.safe_tool_facts.length > 0, "SAFE_DISCLOSURE_SCHEMA_INVALID");
    for (const fact of task.safe_tool_facts) {
      exactKeys(fact, ["fact_id", "value"], "SAFE_DISCLOSURE_SCHEMA_INVALID");
      assert(typeof fact.fact_id === "string" && typeof fact.value === "string", "SAFE_DISCLOSURE_SCHEMA_INVALID");
    }
  }
  return value.tasks;
}

function validateScannerObservation(value, acceptedBindingSha256) {
  exactKeys(
    value,
    ["operation_id", "accepted_binding_sha256", "scanner_artifact_sha256", "file_count", "language_counts", "source_content_included"],
    "SCANNER_OBSERVATION_INVALID",
  );
  assert(value.operation_id === "repository_analysis.scan", "SCANNER_OBSERVATION_INVALID");
  assert(value.accepted_binding_sha256 === acceptedBindingSha256, "SCANNER_BINDING_IDENTITY_MISMATCH");
  assert(/^[0-9a-f]{64}$/.test(value.scanner_artifact_sha256), "SCANNER_OBSERVATION_INVALID");
  assert(Number.isSafeInteger(value.file_count) && value.file_count >= 0, "SCANNER_OBSERVATION_INVALID");
  assert(isObject(value.language_counts), "SCANNER_OBSERVATION_INVALID");
  for (const [language, count] of Object.entries(value.language_counts)) {
    assert(/^[A-Za-z0-9_.+-]{1,32}$/.test(language), "SCANNER_OBSERVATION_INVALID");
    assert(Number.isSafeInteger(count) && count >= 0, "SCANNER_OBSERVATION_INVALID");
  }
  assert(value.source_content_included === false, "RESTRICTED_SOURCE_EGRESS_FORBIDDEN");
}

export function buildProviderPayload({
  entry,
  disclosure,
  responseSchemaIdentity,
  scannerObservation = null,
}) {
  const common = {
    schema_version: "p1-117-provider-safe-request/v1",
    run_id: entry.run_id,
    task_id: entry.task_id,
    system: entry.system,
    variant: entry.variant,
    disclosure_mode: SYSTEM_MODES[entry.system],
    safe_problem_statement: disclosure.safe_problem_statement,
    finite_operations: disclosure.finite_operations,
    response_schema: responseSchemaIdentity,
  };
  if (entry.system === "B0") return common;
  if (entry.system === "B1") return { ...common, safe_tool_facts: disclosure.safe_tool_facts };
  validateScannerObservation(
    scannerObservation,
    entry.accepted_scanner_binding.sha256,
  );
  return { ...common, scanner_observation: scannerObservation };
}

export function providerPayloadBytes(input) {
  return canonicalJsonBytes(buildProviderPayload(input));
}

export function buildChatCompletionsRequest({
  entry,
  configuration,
  disclosure,
  responseSchemaIdentity,
  scannerObservation = null,
}) {
  const payloadBytes = providerPayloadBytes({
    entry,
    disclosure,
    responseSchemaIdentity,
    scannerObservation,
  });
  return {
    payloadBytes,
    body: {
      model: configuration.model_ref,
      messages: [
        { role: "system", content: SYSTEM_INSTRUCTION },
        { role: "user", content: payloadBytes.toString("utf8") },
      ],
      temperature: configuration.temperature,
      max_tokens: configuration.max_output_tokens,
      response_format: { type: "json_object" },
    },
  };
}

export function validateChatCompletionsRequest({
  repositoryRoot,
  requestBytes,
  entry,
  configuration,
  disclosure,
  responseSchemaIdentity,
}) {
  const request = parseCanonicalJson(requestBytes, "CHAT_COMPLETIONS_REQUEST_INVALID");
  const scannerObservation = entry.system === "B2"
    ? request.messages?.[1]?.content
      ? parseCanonicalJson(
          Buffer.from(request.messages[1].content, "utf8"),
          "PROVIDER_PAYLOAD_SCHEMA_INVALID",
        ).scanner_observation
      : null
    : null;
  const expected = buildChatCompletionsRequest({
    entry,
    configuration,
    disclosure,
    responseSchemaIdentity,
    scannerObservation,
  });
  assert(
    requestBytes.equals(canonicalJsonBytes(expected.body)),
    "CHAT_COMPLETIONS_REQUEST_IDENTITY_MISMATCH",
  );
  validateProviderPayload({
    repositoryRoot,
    payloadBytes: expected.payloadBytes,
    entry,
    disclosure,
    responseSchemaIdentity,
  });
  return { request, payloadBytes: expected.payloadBytes };
}

function forbiddenFragments(repositoryRoot) {
  const manifest = JSON.parse(
    readFileSync(join(repositoryRoot, DATASET_ROOT, "dataset-manifest.json"), "utf8"),
  );
  const fragments = [];
  for (const artifact of manifest.artifacts) {
    if (
      artifact.path.includes("/source-template/")
      || artifact.path.includes("/test/")
      || artifact.path.endsWith("/reference-solution.patch")
    ) {
      const text = readFileSync(join(repositoryRoot, DATASET_ROOT, artifact.path), "utf8");
      for (const line of text.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (trimmed.length >= 16) fragments.push(trimmed);
      }
    }
  }
  return [...new Set(fragments)];
}

export function validateProviderPayload({
  repositoryRoot,
  payloadBytes,
  entry,
  disclosure,
  responseSchemaIdentity,
}) {
  const payload = parseCanonicalJson(payloadBytes, "PROVIDER_PAYLOAD_SCHEMA_INVALID");
  const expectedKeys = [
    "schema_version", "run_id", "task_id", "system", "variant",
    "disclosure_mode", "safe_problem_statement", "finite_operations",
    "response_schema",
  ];
  if (entry.system === "B1") expectedKeys.push("safe_tool_facts");
  if (entry.system === "B2") expectedKeys.push("scanner_observation");
  exactKeys(payload, expectedKeys, "PROVIDER_PAYLOAD_SCHEMA_INVALID");
  const rebuilt = buildProviderPayload({
    entry,
    disclosure,
    responseSchemaIdentity,
    scannerObservation: payload.scanner_observation ?? null,
  });
  assert(sameJson(payload, rebuilt), "PAYLOAD_NOT_EXACT_SAFE_DISCLOSURE");
  const text = payloadBytes.toString("utf8");
  for (const fragment of forbiddenFragments(repositoryRoot)) {
    assert(!text.includes(fragment), "RESTRICTED_SOURCE_EGRESS_FORBIDDEN");
  }
  assert(!/authorization\s*:/i.test(text), "SECRET_SINK_FORBIDDEN");
  return payload;
}

export function validateProviderResponse(bytes, allowedOperationIds) {
  const response = parseCanonicalJson(bytes, "PROVIDER_RESPONSE_SCHEMA_INVALID");
  exactKeys(response, ["schema_version", "selected_operation_id"], "PROVIDER_RESPONSE_SCHEMA_INVALID");
  assert(response.schema_version === "p1-117-provider-selection/v1", "PROVIDER_RESPONSE_SCHEMA_INVALID");
  assert(
    allowedOperationIds.includes(response.selected_operation_id),
    "UNKNOWN_OPERATION_ID",
  );
  return response;
}

export function validateProviderResponseOutcome(bytes, allowedOperationIds) {
  const value = parseCanonicalJson(bytes, "RESPONSE_SAFE_EVIDENCE_INVALID");
  if (value.schema_version === "p1-117-provider-selection/v1") {
    exactKeys(value, ["schema_version", "selected_operation_id"], "RESPONSE_SAFE_EVIDENCE_INVALID");
    if (!allowedOperationIds.includes(value.selected_operation_id)) {
      return { accepted: false, selectedOperationId: null, reasonCode: "UNKNOWN_OPERATION_ID" };
    }
    return {
      accepted: true,
      selectedOperationId: value.selected_operation_id,
      reasonCode: null,
    };
  }
  exactKeys(
    value,
    [
      "schema_version", "status", "reason_code", "raw_response_sha256",
      "raw_response_byte_length", "raw_response_retained",
    ],
    "RESPONSE_SAFE_EVIDENCE_INVALID",
  );
  const reasons = new Set([
    "PROVIDER_RESPONSE_SCHEMA_INVALID",
    "PROVIDER_RESPONSE_NOT_CANONICAL",
    "UNKNOWN_OPERATION_ID",
    "PROVIDER_HTTP_NON_PASS",
    "PROVIDER_TIMEOUT",
    "PROVIDER_TRANSPORT_ERROR",
    "PROVIDER_USAGE_INVALID",
  ]);
  assert(
    value.schema_version === "p1-117-provider-response-safe-rejection/v1"
      && value.status === "REJECTED"
      && reasons.has(value.reason_code)
      && /^[0-9a-f]{64}$/.test(value.raw_response_sha256)
      && Number.isSafeInteger(value.raw_response_byte_length)
      && value.raw_response_byte_length >= 0
      && value.raw_response_retained === false,
    "RESPONSE_SAFE_EVIDENCE_INVALID",
  );
  return { accepted: false, selectedOperationId: null, reasonCode: value.reason_code };
}

export function loadSafeDisclosure(repositoryRoot, matrix, entry) {
  const binding = matrix.safe_disclosures;
  const file = readBoundFile(repositoryRoot, binding, "SAFE_DISCLOSURE_IDENTITY_MISMATCH");
  const value = parseFrozenJson(file.bytes, "SAFE_DISCLOSURE_SCHEMA_INVALID");
  const tasks = validateSafeDisclosures(value);
  const disclosure = tasks[entry.safe_disclosure_task_index];
  assert(disclosure?.task_id === entry.task_id, "SAFE_DISCLOSURE_TASK_MISMATCH");
  assert(
    sameJson(
      disclosure.finite_operations.map((item) => item.operation_id),
      entry.finite_operation_ids,
    ),
    "FINITE_OPERATION_CATALOG_MISMATCH",
  );
  return { value, disclosure, identity: { path: binding.path, ...identityOf(file.bytes) } };
}

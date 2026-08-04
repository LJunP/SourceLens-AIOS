import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  EXECUTION_ARTIFACT_KEYS,
} from "../p1-149-accepted-execution-spine/execution.mjs";
import {
  ACCEPTED_INPUTS,
  CLAIM_BOUNDARY,
  ENDPOINT,
  MODEL,
  REPOSITORY_ROOT,
  ROUTE_ID,
  TASK_ID,
  buildFormalPlan,
  datasetIdentity,
} from "./plan.mjs";
import {
  FALSE_EXTERNAL_EFFECTS,
  MANIFEST_EXCLUDED_PATHS,
  artifactIdentityAt,
  assert,
  buildClosedManifest,
  canonicalBytes,
  canonicalJson,
  exactKeys,
  parseExactJsonBytes,
  readBoundFile,
  safeRegularFile,
  verifyClosedManifest,
  writeBytesCreateOnce,
  writeJsonCreateOnce,
} from "./shared.mjs";

export const FORMAL_PLAN_KEYS = Object.freeze([
  "schema_version", "task_id", "route_id", "claim_boundary", "denominator",
  "endpoint", "model", "accepted_inputs", "cells", "external_effects",
]);
export const REQUEST_RECEIPT_KEYS = Object.freeze([
  "schema_version", "execution_id", "cell_id", "task_id", "profile_id",
  "repetition_id", "endpoint", "model", "request", "request_sequence",
  "preformal_gate", "effect_authorized", "provider_request", "automatic_retry",
  "created_at",
]);
export const RESPONSE_RECEIPT_KEYS = Object.freeze([
  "schema_version", "execution_id", "cell_id", "request_receipt", "response",
  "http_status", "peer_address", "peer_port", "response_id", "usage",
  "completion_status", "provider_request", "automatic_retry", "received_at",
]);
export const TRANSPORT_RECEIPT_KEYS = Object.freeze([
  "schema_version", "execution_id", "cell_id", "request_receipt",
  "transport_status", "reason_code", "http_status", "peer_address", "peer_port",
  "response", "provider_request", "automatic_retry", "observed_at",
]);
export const TERMINAL_KEYS = Object.freeze([
  "schema_version", "execution_id", "cell_id", "task_id", "request_receipt",
  "response_receipt", "execution_manifest", "classification", "reason_code",
  "provider_request_count", "automatic_retries", "terminal_at",
]);
export const RUN_RECEIPT_KEYS = Object.freeze([
  "schema_version", "task_id", "execution_id", "status", "diagnostic",
  "denominator", "scheduled_cells", "terminal_cells", "provider_requests",
  "diagnostic_provider_requests", "formal_provider_requests", "automatic_retries",
  "taxonomy", "external_effects", "secret_reads", "secret_persisted",
  "report_rebuild_required", "completed_at",
]);
export const ENVIRONMENT_RECEIPT_KEYS = Object.freeze([
  "schema_version", "task_id", "repository", "node", "platform", "architecture",
  "dataset_manifest", "accepted_inputs", "endpoint", "model", "external_effects",
]);
export const CONFIGURATION_RECEIPT_KEYS = Object.freeze([
  "schema_version", "task_id", "route_id", "claim_boundary", "denominator",
  "diagnostic_requests_max", "formal_requests_exact", "provider_requests_max",
  "automatic_retry_max", "endpoint", "model", "secret_entry",
  "manifest_exclusions", "external_effects",
]);

function gitText(args) {
  const result = spawnSync("/usr/bin/git", args, {
    cwd: REPOSITORY_ROOT,
    shell: false,
    encoding: "utf8",
    env: {
      PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      LANG: "C",
      LC_ALL: "C",
      TZ: "UTC",
    },
  });
  assert(!result.error && result.status === 0, "SOURCE_IDENTITY_UNAVAILABLE", `git ${args.join(" ")} failed`);
  return result.stdout.trim();
}

export function repositoryIdentity() {
  return {
    commit: gitText(["rev-parse", "HEAD"]),
    tree: gitText(["rev-parse", "HEAD^{tree}"]),
    dirty: gitText(["status", "--porcelain", "--untracked-files=all"]) !== "",
  };
}

export function writeRootReceipts(root) {
  const plan = buildFormalPlan();
  exactKeys(plan, FORMAL_PLAN_KEYS, "formal plan");
  const formalPlan = writeJsonCreateOnce(root, "plan/FORMAL_PLAN.json", plan);
  const environment = {
    schema_version: "p1-207-environment-receipt/v1",
    task_id: TASK_ID,
    repository: repositoryIdentity(),
    node: process.version,
    platform: process.platform,
    architecture: process.arch,
    dataset_manifest: datasetIdentity(),
    accepted_inputs: ACCEPTED_INPUTS,
    endpoint: ENDPOINT,
    model: MODEL,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  exactKeys(environment, ENVIRONMENT_RECEIPT_KEYS, "environment receipt");
  const environmentReceipt = writeJsonCreateOnce(root, "ENVIRONMENT_RECEIPT.json", environment);
  const configuration = {
    schema_version: "p1-207-configuration-receipt/v1",
    task_id: TASK_ID,
    route_id: ROUTE_ID,
    claim_boundary: CLAIM_BOUNDARY,
    denominator: 36,
    diagnostic_requests_max: 1,
    formal_requests_exact: 36,
    provider_requests_max: 37,
    automatic_retry_max: 0,
    endpoint: ENDPOINT,
    model: MODEL,
    secret_entry: "OPERATOR_OWNED_NO_ECHO_STDIN_ONCE",
    manifest_exclusions: MANIFEST_EXCLUDED_PATHS,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  exactKeys(configuration, CONFIGURATION_RECEIPT_KEYS, "configuration receipt");
  const configurationReceipt = writeJsonCreateOnce(root, "CONFIGURATION_RECEIPT.json", configuration);
  return { formalPlan, environmentReceipt, configurationReceipt };
}

function receiptPath(cellId, name) {
  return cellId.startsWith("diagnostic-")
    ? `diagnostic/${name}`
    : `cells/${cellId}/${name}`;
}

export function writeRequestEvidence(root, {
  executionId,
  cell,
  requestBytes,
  requestSequence,
  preformalGate,
  providerRequest,
}) {
  const request = writeBytesCreateOnce(root, receiptPath(cell.cell_id, "request.json"), requestBytes);
  const receipt = {
    schema_version: "p1-207-request-receipt/v1",
    execution_id: executionId,
    cell_id: cell.cell_id,
    task_id: cell.task_id,
    profile_id: cell.profile_id,
    repetition_id: cell.repetition_id,
    endpoint: ENDPOINT,
    model: MODEL,
    request,
    request_sequence: requestSequence,
    preformal_gate: preformalGate,
    effect_authorized: providerRequest,
    provider_request: providerRequest,
    automatic_retry: false,
    created_at: new Date().toISOString(),
  };
  exactKeys(receipt, REQUEST_RECEIPT_KEYS, "request receipt");
  const identity = writeJsonCreateOnce(root, receiptPath(cell.cell_id, "request-receipt.json"), receipt);
  return { request, receipt, identity };
}

export function writeResponseEvidence(root, {
  executionId,
  cell,
  requestReceipt,
  responseBytes,
  httpStatus,
  peerAddress,
  peerPort,
  responseId,
  usage,
  completionStatus,
  providerRequest,
}) {
  const response = writeRawResponseEvidence(root, cell.cell_id, responseBytes);
  return writeResponseReceiptEvidence(root, {
    executionId,
    cell,
    requestReceipt,
    response,
    httpStatus,
    peerAddress,
    peerPort,
    responseId,
    usage,
    completionStatus,
    providerRequest,
  });
}

export function writeRawResponseEvidence(root, cellId, responseBytes) {
  return writeBytesCreateOnce(root, receiptPath(cellId, "response.raw"), responseBytes);
}

export function writeResponseReceiptEvidence(root, {
  executionId,
  cell,
  requestReceipt,
  response,
  httpStatus,
  peerAddress,
  peerPort,
  responseId,
  usage,
  completionStatus,
  providerRequest,
}) {
  const receipt = {
    schema_version: "p1-207-response-receipt/v1",
    execution_id: executionId,
    cell_id: cell.cell_id,
    request_receipt: requestReceipt,
    response,
    http_status: httpStatus,
    peer_address: peerAddress,
    peer_port: peerPort,
    response_id: responseId,
    usage,
    completion_status: completionStatus,
    provider_request: providerRequest,
    automatic_retry: false,
    received_at: new Date().toISOString(),
  };
  exactKeys(receipt, RESPONSE_RECEIPT_KEYS, "response receipt");
  const identity = writeJsonCreateOnce(root, receiptPath(cell.cell_id, "response-receipt.json"), receipt);
  return { response, receipt, identity };
}

export function writeTransportEvidence(root, {
  executionId,
  cell,
  requestReceipt,
  transportStatus,
  reasonCode,
  httpStatus,
  peerAddress,
  peerPort,
  response = null,
  providerRequest,
}) {
  const receipt = {
    schema_version: "p1-207-transport-receipt/v1",
    execution_id: executionId,
    cell_id: cell.cell_id,
    request_receipt: requestReceipt,
    transport_status: transportStatus,
    reason_code: reasonCode,
    http_status: httpStatus,
    peer_address: peerAddress,
    peer_port: peerPort,
    response,
    provider_request: providerRequest,
    automatic_retry: false,
    observed_at: new Date().toISOString(),
  };
  exactKeys(receipt, TRANSPORT_RECEIPT_KEYS, "transport receipt");
  const identity = writeJsonCreateOnce(root, receiptPath(cell.cell_id, "transport-receipt.json"), receipt);
  return { receipt, identity };
}

export function writeExecutionEvidence(root, cellId, execution) {
  const names = Object.keys(execution.artifacts).sort();
  assert(
    canonicalJson(names) === canonicalJson([...EXECUTION_ARTIFACT_KEYS].sort()),
    "EXECUTION_ARTIFACT_SET_INVALID",
    `${cellId} execution artifact set is not closed`,
  );
  for (const name of EXECUTION_ARTIFACT_KEYS) {
    const bytes = execution.artifacts[name];
    assert(Buffer.isBuffer(bytes), "EXECUTION_ARTIFACT_INVALID", `${cellId}/${name} is not bytes`);
    writeBytesCreateOnce(root, `cells/${cellId}/execution/${name}`, bytes);
  }
  return artifactIdentityAt(root, `cells/${cellId}/execution/execution-spine.json`);
}

export function writeTerminalEvidence(root, {
  executionId,
  cell,
  requestReceipt,
  responseReceipt = null,
  executionManifest = null,
  classification,
  reasonCode,
  providerRequestCount,
}) {
  const terminal = {
    schema_version: "p1-207-cell-terminal/v1",
    execution_id: executionId,
    cell_id: cell.cell_id,
    task_id: cell.task_id,
    request_receipt: requestReceipt,
    response_receipt: responseReceipt,
    execution_manifest: executionManifest,
    classification,
    reason_code: reasonCode,
    provider_request_count: providerRequestCount,
    automatic_retries: 0,
    terminal_at: new Date().toISOString(),
  };
  exactKeys(terminal, TERMINAL_KEYS, "cell terminal");
  return writeJsonCreateOnce(root, receiptPath(cell.cell_id, "terminal.json"), terminal);
}

export function writeRunReceipt(root, receipt) {
  exactKeys(receipt, RUN_RECEIPT_KEYS, "run receipt");
  return writeJsonCreateOnce(root, "RUN_RECEIPT.json", receipt);
}

export function closeEvidenceManifest(root, rootRole) {
  const manifest = buildClosedManifest(root, {
    exclude: MANIFEST_EXCLUDED_PATHS,
    taskId: TASK_ID,
    rootRole,
  });
  const identity = writeJsonCreateOnce(root, "EVIDENCE_MANIFEST.json", manifest);
  const verification = verifyClosedManifest(root, manifest, { exclude: MANIFEST_EXCLUDED_PATHS });
  return { manifest, identity, verification };
}

export function loadCanonicalJson(root, relativePath, label) {
  const path = safeRegularFile(join(root, ...relativePath.split("/")), label);
  const bytes = readFileSync(path);
  return parseExactJsonBytes(bytes, { label, canonical: true });
}

export function verifyCellBinding(root, cell) {
  const base = cell.cell_id.startsWith("diagnostic-") ? "diagnostic" : `cells/${cell.cell_id}`;
  const requestReceiptPath = `${base}/request-receipt.json`;
  const responseReceiptPath = `${base}/response-receipt.json`;
  const transportReceiptPath = `${base}/transport-receipt.json`;
  const terminalPath = `${base}/terminal.json`;
  const requestReceipt = loadCanonicalJson(root, requestReceiptPath, `${cell.cell_id} request receipt`);
  const responseReceipt = loadCanonicalJson(root, responseReceiptPath, `${cell.cell_id} response receipt`);
  const transportReceipt = loadCanonicalJson(root, transportReceiptPath, `${cell.cell_id} transport receipt`);
  const terminal = loadCanonicalJson(root, terminalPath, `${cell.cell_id} terminal`);
  exactKeys(requestReceipt, REQUEST_RECEIPT_KEYS, "request receipt");
  exactKeys(responseReceipt, RESPONSE_RECEIPT_KEYS, "response receipt");
  exactKeys(transportReceipt, TRANSPORT_RECEIPT_KEYS, "transport receipt");
  exactKeys(terminal, TERMINAL_KEYS, "terminal");
  const requestReceiptIdentity = artifactIdentityAt(root, requestReceiptPath);
  const responseReceiptIdentity = artifactIdentityAt(root, responseReceiptPath);
  readBoundFile(root, requestReceipt.request, `${cell.cell_id} request`);
  readBoundFile(root, responseReceipt.response, `${cell.cell_id} response`);
  assert(
    requestReceipt.cell_id === cell.cell_id
      && requestReceipt.task_id === cell.task_id
      && responseReceipt.cell_id === cell.cell_id
      && canonicalJson(responseReceipt.request_receipt) === canonicalJson(requestReceiptIdentity)
      && transportReceipt.cell_id === cell.cell_id
      && canonicalJson(transportReceipt.request_receipt) === canonicalJson(requestReceiptIdentity)
      && canonicalJson(transportReceipt.response) === canonicalJson(responseReceipt.response)
      && terminal.cell_id === cell.cell_id
      && terminal.task_id === cell.task_id
      && canonicalJson(terminal.request_receipt) === canonicalJson(requestReceiptIdentity)
      && canonicalJson(terminal.response_receipt) === canonicalJson(responseReceiptIdentity),
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    `${cell.cell_id} receipt chain is not exact`,
  );
  if (terminal.execution_manifest !== null) {
    readBoundFile(root, terminal.execution_manifest, `${cell.cell_id} execution manifest`);
  }
  return { requestReceipt, responseReceipt, transportReceipt, terminal };
}

export function validateClosedTaxonomy(taxonomy, denominator = 36) {
  exactKeys(taxonomy, ["successful", "failed", "invalid", "excluded", "denominator"], "taxonomy");
  for (const key of ["successful", "failed", "invalid", "excluded", "denominator"]) {
    assert(Number.isSafeInteger(taxonomy[key]) && taxonomy[key] >= 0, "TAXONOMY_INVALID", `${key} is invalid`);
  }
  assert(
    taxonomy.denominator === denominator
      && taxonomy.successful + taxonomy.failed + taxonomy.invalid + taxonomy.excluded === denominator,
    "TAXONOMY_NOT_CLOSED",
    "taxonomy does not close to the frozen denominator",
  );
  return taxonomy;
}

#!/usr/bin/env node

import { pathToFileURL } from "node:url";

import {
  executeSpine,
} from "../p1-149-accepted-execution-spine/execution.mjs";
import {
  closeEvidenceManifest,
  validateClosedTaxonomy,
  writeExecutionEvidence,
  writeRawResponseEvidence,
  writeRequestEvidence,
  writeResponseReceiptEvidence,
  writeRootReceipts,
  writeRunReceipt,
  writeTerminalEvidence,
  writeTransportEvidence,
} from "./evidence.mjs";
import {
  ENDPOINT,
  MODEL,
  TASK_ID,
  buildDiagnosticRequest,
  buildFormalPlan,
  buildFormalRequest,
} from "./plan.mjs";
import {
  normalizePatchResponse,
  parseChatCompletionBytes,
} from "./response.mjs";
import {
  FALSE_EXTERNAL_EFFECTS,
  P1207NonPass,
  assert,
  assertNoSecretBytes,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  createOwnedRoot,
  exactKeys,
  writeBytesCreateOnce,
} from "./shared.mjs";
import { verifyPreformalGate } from "./gate-consumer.mjs";
import {
  readSecretOnce,
  requestLoopback,
} from "./transport.mjs";

const FORMAL_EXTERNAL_EFFECTS = Object.freeze({
  network: true,
  provider: true,
  secret: true,
  remote: false,
  production: false,
  public: false,
});

function errorReason(error) {
  return error?.reasonCode ?? error?.code ?? error?.name ?? "UNKNOWN_ERROR";
}

function isModelOutcomeReason(reason) {
  return [
    "JSON_", "CHAT_", "PROVIDER_", "RESPONSE_", "IR_",
  ].some((prefix) => reason.startsWith(prefix));
}

function diagnosticCell() {
  return {
    cell_id: "diagnostic-001",
    task_id: TASK_ID,
    profile_id: "DIAGNOSTIC",
    repetition_id: 0,
  };
}

async function recordTransportResponse(root, {
  executionId,
  cell,
  requestReceipt,
  transport,
  diagnostic = false,
}) {
  const hasResponseEvidence = transport.http_status !== null || transport.response_bytes.length > 0;
  // Raw bytes are persisted before any JSON or semantic parsing.
  const response = hasResponseEvidence
    ? writeRawResponseEvidence(root, cell.cell_id, transport.response_bytes)
    : null;
  const transportReceipt = writeTransportEvidence(root, {
    executionId,
    cell,
    requestReceipt,
    transportStatus: transport.transport_status,
    reasonCode: transport.reason_code,
    httpStatus: transport.http_status,
    peerAddress: transport.peer_address,
    peerPort: transport.peer_port,
    response,
    providerRequest: true,
  });
  if (response === null) {
    return {
      response: null,
      receipt: null,
      identity: null,
      parsed: null,
      parseReason: null,
      completionStatus: transport.reason_code,
      transportReceipt,
    };
  }
  let parsed = null;
  let parseReason = null;
  try {
    parsed = parseChatCompletionBytes(transport.response_bytes, { diagnostic });
  } catch (error) {
    parseReason = errorReason(error);
  }
  const completionStatus = transport.transport_status !== "RECEIVED"
    ? transport.reason_code
    : !(transport.http_status >= 200 && transport.http_status < 300)
      ? "HTTP_NON_2XX"
      : parseReason ?? parsed.completion_status;
  const recorded = writeResponseReceiptEvidence(root, {
    executionId,
    cell,
    requestReceipt,
    response,
    httpStatus: transport.http_status,
    peerAddress: transport.peer_address,
    peerPort: transport.peer_port,
    responseId: parsed?.response_id ?? null,
    usage: parsed?.usage ?? null,
    completionStatus,
    providerRequest: true,
  });
  return { ...recorded, parsed, parseReason, completionStatus, transportReceipt };
}

async function closeDiagnosticFailure(root, {
  executionId,
  request,
  response,
  reasonCode,
  secretBytes,
}) {
  const cell = diagnosticCell();
  writeTerminalEvidence(root, {
    executionId,
    cell,
    requestReceipt: request.identity,
    responseReceipt: response?.identity ?? null,
    executionManifest: null,
    classification: "FAILED",
    reasonCode,
    providerRequestCount: 1,
  });
  assertNoSecretBytes(root, secretBytes);
  const taxonomy = validateClosedTaxonomy({
    successful: 0,
    failed: 0,
    invalid: 0,
    excluded: 36,
    denominator: 36,
  });
  writeRunReceipt(root, {
    schema_version: "p1-207-run-receipt/v1",
    task_id: TASK_ID,
    execution_id: executionId,
    status: "NON_PASS",
    diagnostic: { status: "NON_PASS", reason_code: reasonCode, provider_requests: 1 },
    denominator: 36,
    scheduled_cells: 0,
    terminal_cells: 0,
    provider_requests: 1,
    diagnostic_provider_requests: 1,
    formal_provider_requests: 0,
    automatic_retries: 0,
    taxonomy,
    external_effects: FORMAL_EXTERNAL_EFFECTS,
    secret_reads: 1,
    secret_persisted: false,
    report_rebuild_required: false,
    completed_at: new Date().toISOString(),
  });
  const closed = closeEvidenceManifest(root, "FORMAL_DIAGNOSTIC_NON_PASS_EVIDENCE");
  return closed;
}

export async function runFormal(gatePath, evidenceRoot, input = process.stdin) {
  const verifiedGate = verifyPreformalGate(gatePath);
  createOwnedRoot(evidenceRoot);
  writeRootReceipts(evidenceRoot);
  const localGateIdentity = writeBytesCreateOnce(evidenceRoot, "PREFORMAL_GATE_RECEIPT.json", verifiedGate.gate_bytes);
  const plan = buildFormalPlan();
  const executionId = `P1-207-${Date.now()}`;
  const secretBytes = await readSecretOnce(input);
  let providerRequests = 0;
  try {
    const dCell = diagnosticCell();
    const diagnosticRequestBytes = canonicalBytes(buildDiagnosticRequest());
    const diagnosticRequest = writeRequestEvidence(evidenceRoot, {
      executionId,
      cell: dCell,
      requestBytes: diagnosticRequestBytes,
      requestSequence: 1,
      preformalGate: localGateIdentity,
      providerRequest: true,
    });
    providerRequests += 1;
    const diagnosticTransport = await requestLoopback({
      requestBytes: diagnosticRequestBytes,
      secretBytes,
    });
    const diagnosticResponse = await recordTransportResponse(evidenceRoot, {
      executionId,
      cell: dCell,
      requestReceipt: diagnosticRequest.identity,
      transport: diagnosticTransport,
      diagnostic: true,
    });
    const diagnosticReason = diagnosticTransport.transport_status !== "RECEIVED"
      ? diagnosticTransport.reason_code
      : !(diagnosticTransport.http_status >= 200 && diagnosticTransport.http_status < 300)
        ? "HTTP_NON_2XX"
        : diagnosticResponse?.parseReason;
    if (diagnosticReason !== null && diagnosticReason !== undefined) {
      await closeDiagnosticFailure(evidenceRoot, {
        executionId,
        request: diagnosticRequest,
        response: diagnosticResponse,
        reasonCode: diagnosticReason,
        secretBytes,
      });
      return {
        schema_version: "p1-207-formal-result/v1",
        task_id: TASK_ID,
        status: "NON_PASS",
        reason_code: "DIAGNOSTIC_STRICT_COMPLETION_NON_PASS",
        diagnostic_reason: diagnosticReason,
        evidence_root: evidenceRoot,
        provider_requests: providerRequests,
        formal_provider_requests: 0,
        automatic_retries: 0,
      };
    }
    writeTerminalEvidence(evidenceRoot, {
      executionId,
      cell: dCell,
      requestReceipt: diagnosticRequest.identity,
      responseReceipt: diagnosticResponse.identity,
      executionManifest: null,
      classification: "SUCCESSFUL",
      reasonCode: "STRICT_DIAGNOSTIC_COMPLETION",
      providerRequestCount: 1,
    });

    const taxonomy = { successful: 0, failed: 0, invalid: 0, excluded: 0, denominator: 36 };
    let formalProviderRequests = 0;
    for (const cell of plan.cells) {
      const requestBytes = canonicalBytes(buildFormalRequest(cell));
      const request = writeRequestEvidence(evidenceRoot, {
        executionId,
        cell,
        requestBytes,
        requestSequence: cell.ordinal + 1,
        preformalGate: localGateIdentity,
        providerRequest: true,
      });
      providerRequests += 1;
      formalProviderRequests += 1;
      const transport = await requestLoopback({ requestBytes, secretBytes });
      const response = await recordTransportResponse(evidenceRoot, {
        executionId,
        cell,
        requestReceipt: request.identity,
        transport,
      });
      let classification = "FAILED";
      let reasonCode = transport.reason_code;
      let executionManifest = null;
      if (transport.transport_status === "RECEIVED" && transport.http_status >= 200 && transport.http_status < 300) {
        if (response?.parseReason !== null) {
          classification = "INVALID";
          reasonCode = response.parseReason;
        } else {
          try {
            const normalized = normalizePatchResponse({ cell, rawResponseBytes: transport.response_bytes });
            const execution = await executeSpine({
              taskId: cell.task_id,
              responseBytes: normalized.normalized_response_bytes,
              runId: `P1-207-FORMAL-${cell.cell_id}`,
            });
            executionManifest = writeExecutionEvidence(evidenceRoot, cell.cell_id, execution);
            classification = execution.summary.worker_observed_classification === "VERIFIED_SUCCESS"
              ? "SUCCESSFUL"
              : "FAILED";
            reasonCode = classification === "SUCCESSFUL" ? "VERIFIED_SUCCESS" : "ORACLE_OR_TEST_FAILED";
          } catch (error) {
            reasonCode = errorReason(error);
            if (!isModelOutcomeReason(reasonCode)) throw error;
            classification = "INVALID";
          }
        }
      } else if (transport.transport_status === "RECEIVED") {
        reasonCode = "HTTP_NON_2XX";
      }
      taxonomy[classification.toLowerCase().replace("successful", "successful")] += 1;
      writeTerminalEvidence(evidenceRoot, {
        executionId,
        cell,
        requestReceipt: request.identity,
        responseReceipt: response?.identity ?? null,
        executionManifest,
        classification,
        reasonCode,
        providerRequestCount: 1,
      });
    }
    assert(formalProviderRequests === 36 && providerRequests === 37, "PROVIDER_ACCOUNTING_INVALID", "formal Provider accounting is not exact");
    validateClosedTaxonomy(taxonomy);
    assertNoSecretBytes(evidenceRoot, secretBytes);
    writeRunReceipt(evidenceRoot, {
      schema_version: "p1-207-run-receipt/v1",
      task_id: TASK_ID,
      execution_id: executionId,
      status: "PASS",
      diagnostic: { status: "PASS", reason_code: "STRICT_DIAGNOSTIC_COMPLETION", provider_requests: 1 },
      denominator: 36,
      scheduled_cells: 36,
      terminal_cells: 36,
      provider_requests: 37,
      diagnostic_provider_requests: 1,
      formal_provider_requests: 36,
      automatic_retries: 0,
      taxonomy,
      external_effects: FORMAL_EXTERNAL_EFFECTS,
      secret_reads: 1,
      secret_persisted: false,
      report_rebuild_required: true,
      completed_at: new Date().toISOString(),
    });
    const closed = closeEvidenceManifest(evidenceRoot, "FORMAL_RAW_EVIDENCE");
    return {
      schema_version: "p1-207-formal-result/v1",
      task_id: TASK_ID,
      status: "PASS",
      evidence_root: evidenceRoot,
      denominator: 36,
      provider_requests: 37,
      diagnostic_provider_requests: 1,
      formal_provider_requests: 36,
      automatic_retries: 0,
      taxonomy,
      evidence_manifest: closed.identity,
      report_rebuild_required: true,
    };
  } finally {
    secretBytes.fill(0);
  }
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  try {
    const [mode, gatePath, evidenceRoot] = process.argv.slice(2);
    assert(["--gate-check", "--execute"].includes(mode), "CLI_USAGE_INVALID", "mode must be --gate-check or --execute");
    assert(typeof gatePath === "string" && typeof evidenceRoot === "string", "CLI_USAGE_INVALID", "gate path and evidence root are required");
    if (mode === "--gate-check") {
      verifyPreformalGate(gatePath);
      process.stdout.write(`${canonicalJson({
        schema_version: "p1-207-preformal-gate-check/v1",
        task_id: TASK_ID,
        status: "PASS",
        secret_reads: 0,
        provider_requests: 0,
        external_effects: FALSE_EXTERNAL_EFFECTS,
      })}\n`);
    } else {
      const result = await runFormal(gatePath, evidenceRoot);
      process.stdout.write(`${canonicalJson(result)}\n`);
      if (result.status !== "PASS") process.exitCode = 1;
    }
  } catch (error) {
    const reasonCode = errorReason(error);
    process.stdout.write(`${canonicalJson({
      schema_version: "p1-207-command-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: reasonCode,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

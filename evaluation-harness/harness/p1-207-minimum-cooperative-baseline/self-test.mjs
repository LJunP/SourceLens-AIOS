#!/usr/bin/env node

import {
  buildAcceptedReferenceResponse,
} from "../p1-149-accepted-execution-spine/accepted-inputs.mjs";
import {
  cleanupOwnedRoot,
  createDisposableRoot,
} from "../p1-149-accepted-execution-spine/core.mjs";
import {
  executeSpine,
} from "../p1-149-accepted-execution-spine/execution.mjs";
import {
  verifyCellBinding,
  writeExecutionEvidence,
  writeRequestEvidence,
  writeResponseEvidence,
  writeTerminalEvidence,
  writeTransportEvidence,
} from "./evidence.mjs";
import {
  buildFormalPlan,
  buildFormalRequest,
} from "./plan.mjs";
import {
  normalizePatchResponse,
  parseChatCompletionBytes,
  validateObservedPeer,
  validateUsage,
} from "./response.mjs";
import {
  P1207NonPass,
  assert,
  canonicalBytes,
  canonicalJson,
  parseExactJsonBytes,
} from "./shared.mjs";

function expect(reasonCode, action) {
  try {
    action();
    throw new Error(`expected ${reasonCode}`);
  } catch (error) {
    if (error instanceof P1207NonPass && error.reasonCode === reasonCode) return;
    throw error;
  }
}

function syntheticChat(cell, irBytes) {
  return canonicalBytes({
    id: `self-test-${cell.cell_id}`,
    object: "chat.completion",
    model: "gpt-5.6-luna",
    choices: [{
      index: 0,
      message: { role: "assistant", content: irBytes.toString("utf8") },
      finish_reason: "stop",
    }],
    usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
  });
}

function diagnosticChat(content) {
  return canonicalBytes({
    id: "self-test-diagnostic",
    object: "chat.completion",
    model: "gpt-5.6-luna",
    choices: [{
      index: 0,
      message: { role: "assistant", content },
      finish_reason: "stop",
    }],
    usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
  });
}

const plan = buildFormalPlan();
assert(plan.cells.length === 36 && new Set(plan.cells.map((cell) => cell.cell_id)).size === 36,
  "SELF_TEST_FAILED", "formal plan is not a unique 36-cell set");
assert(new Set(plan.cells.map((cell) => `${cell.task_id}:${cell.profile_id}`)).size === 36,
  "SELF_TEST_FAILED", "formal task/profile combinations are not closed");

const cell = plan.cells[0];
const requestBytes = canonicalBytes(buildFormalRequest(cell));
parseExactJsonBytes(requestBytes, { label: "self-test request", canonical: true });
const accepted = buildAcceptedReferenceResponse(cell.task_id, "P1-207-SELF-TEST");
const normalized = normalizePatchResponse({ cell, rawResponseBytes: syntheticChat(cell, accepted.ir_bytes) });
const execution = executeSpine({
  taskId: cell.task_id,
  responseBytes: normalized.normalized_response_bytes,
  runId: "P1-207-SELF-TEST",
});
assert(execution.summary.worker_observed_classification === "VERIFIED_SUCCESS"
    && execution.summary.p1_101_replay === "PASS"
    && execution.summary.rollback_exact === true,
  "SELF_TEST_FAILED", "accepted execution spine did not verify and replay");

const disposable = createDisposableRoot("p1207-self-test");
try {
  const executionId = "P1-207-SELF-TEST";
  const request = writeRequestEvidence(disposable.root, {
    executionId,
    cell,
    requestBytes,
    requestSequence: 1,
    preformalGate: null,
    providerRequest: false,
  });
  const rawResponseBytes = syntheticChat(cell, accepted.ir_bytes);
  const response = writeResponseEvidence(disposable.root, {
    executionId,
    cell,
    requestReceipt: request.identity,
    responseBytes: rawResponseBytes,
    httpStatus: 200,
    peerAddress: null,
    peerPort: null,
    responseId: normalized.chat.response_id,
    usage: normalized.chat.usage,
    completionStatus: "SYNTHETIC_LOCAL_COMPLETION",
    providerRequest: false,
  });
  writeTransportEvidence(disposable.root, {
    executionId,
    cell,
    requestReceipt: request.identity,
    transportStatus: "SYNTHETIC_LOCAL",
    reasonCode: "NONE",
    httpStatus: null,
    peerAddress: null,
    peerPort: null,
    response: response.response,
    providerRequest: false,
  });
  const executionManifest = writeExecutionEvidence(disposable.root, cell.cell_id, execution);
  writeTerminalEvidence(disposable.root, {
    executionId,
    cell,
    requestReceipt: request.identity,
    responseReceipt: response.identity,
    executionManifest,
    classification: "SUCCESSFUL",
    reasonCode: "VERIFIED_SUCCESS",
    providerRequestCount: 0,
  });
  const binding = verifyCellBinding(disposable.root, cell);
  assert(binding.transportReceipt.transport_status === "SYNTHETIC_LOCAL",
    "SELF_TEST_FAILED", "transport receipt was not independently bound");
} finally {
  cleanupOwnedRoot(disposable);
}

expect("JSON_DUPLICATE_KEY", () => parseExactJsonBytes(Buffer.from('{"a":1,"a":2}', "utf8")));
expect("JSON_INTEGER_UNSAFE", () => parseExactJsonBytes(Buffer.from('{"a":9007199254740992}', "utf8")));
expect("PROVIDER_USAGE_MISSING", () => validateUsage(null));
expect("PROVIDER_USAGE_INVALID", () => validateUsage({ prompt_tokens: -1, completion_tokens: 1, total_tokens: 0 }));
expect("PROVIDER_USAGE_TOTAL_DRIFT", () => validateUsage({ prompt_tokens: 1, completion_tokens: 1, total_tokens: 3 }));
const diagnostic = parseChatCompletionBytes(diagnosticChat(" \nREADY\t"), { diagnostic: true });
assert(diagnostic.completion_status === "STRICT_DIAGNOSTIC_COMPLETION",
  "SELF_TEST_FAILED", "trimmed exact READY diagnostic did not pass");
expect("DIAGNOSTIC_CONTENT_INVALID", () => parseChatCompletionBytes(diagnosticChat("READY."), { diagnostic: true }));
expect("NON_LOOPBACK_PEER_REJECTED", () => validateObservedPeer("192.0.2.1", 8787));
expect("LOOPBACK_PORT_DRIFT", () => validateObservedPeer("127.0.0.1", 8788));

process.stdout.write(`${canonicalJson({
  schema_version: "p1-207-harness-self-test/v1",
  status: "PASS",
  plan_cells: 36,
  accepted_execution_spines: 1,
  accepted_p1_101_replays: 1,
  transport_receipt_bindings: 1,
  negative_cases: 8,
  provider_requests: 0,
  secret_reads: 0,
})}\n`);

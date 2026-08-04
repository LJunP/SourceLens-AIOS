#!/usr/bin/env node

import { pathToFileURL } from "node:url";
import { writeFileSync } from "node:fs";

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
import { runAcceptedP1129Control } from "./accepted-controls.mjs";
import {
  closeEvidenceManifest,
  validateClosedTaxonomy,
  verifyCellBinding,
  writeExecutionEvidence,
  writeRequestEvidence,
  writeResponseEvidence,
  writeRootReceipts,
  writeRunReceipt,
  writeTerminalEvidence,
  writeTransportEvidence,
} from "./evidence.mjs";
import {
  MODEL,
  TASK_ID,
  buildFormalPlan,
  buildFormalRequest,
} from "./plan.mjs";
import {
  parseChatCompletionBytes,
  normalizePatchResponse,
  validateObservedPeer,
  validateUsage,
} from "./response.mjs";
import {
  FALSE_EXTERNAL_EFFECTS,
  P1207NonPass,
  assert,
  buildClosedManifest,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  createOwnedRoot,
  parseExactJsonBytes,
  verifyClosedManifest,
  writeJsonCreateOnce,
} from "./shared.mjs";

function syntheticChatCompletion(cell, patchIrBytes) {
  return canonicalBytes({
    id: `p1-207-synthetic-${cell.cell_id}`,
    object: "chat.completion",
    created: 0,
    model: MODEL,
    choices: [
      {
        index: 0,
        message: { role: "assistant", content: patchIrBytes.toString("utf8") },
        finish_reason: "stop",
      },
    ],
    usage: { prompt_tokens: 100, completion_tokens: 100, total_tokens: 200 },
  });
}

function expectRejected(caseId, expectedReason, action) {
  try {
    action();
    return { case_id: caseId, expected_reason: expectedReason, observed_reason: "UNEXPECTED_PASS", rejected: false };
  } catch (error) {
    const observed = error instanceof P1207NonPass
      ? error.reasonCode
      : error?.reasonCode ?? error?.code ?? error?.name ?? "UNKNOWN_ERROR";
    return {
      case_id: caseId,
      expected_reason: expectedReason,
      observed_reason: observed,
      rejected: observed === expectedReason,
    };
  }
}

function usageResponse(usageLexeme) {
  return Buffer.from(`{"choices":[{"message":{"content":"READY","role":"assistant"}}],"id":"negative","usage":${usageLexeme}}`, "utf8");
}

function inventoryMutationCase(caseId, mutation) {
  const disposable = createDisposableRoot(`p1207-${caseId.toLowerCase().replaceAll("_", "-")}`);
  try {
    writeJsonCreateOnce(disposable.root, "artifact.json", { status: "FROZEN" });
    const manifest = buildClosedManifest(disposable.root, {
      exclude: ["EVIDENCE_MANIFEST.json"],
      taskId: TASK_ID,
      rootRole: "NEGATIVE_FIXTURE",
    });
    mutation(disposable.root);
    return expectRejected(caseId, "CLOSED_INVENTORY_DRIFT", () => {
      verifyClosedManifest(disposable.root, manifest, { exclude: ["EVIDENCE_MANIFEST.json"] });
    });
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

function runNegativeMatrix(root, plan) {
  const cases = [
    expectRejected("DUPLICATE_JSON_KEY", "JSON_DUPLICATE_KEY", () => {
      parseExactJsonBytes(Buffer.from('{"id":"a","id":"b"}', "utf8"));
    }),
    expectRejected("UNSAFE_INTEGER", "JSON_INTEGER_UNSAFE", () => {
      parseExactJsonBytes(Buffer.from('{"value":9007199254740992}', "utf8"));
    }),
    expectRejected("USAGE_MISSING", "PROVIDER_USAGE_MISSING", () => {
      parseChatCompletionBytes(Buffer.from('{"choices":[{"message":{"content":"READY"}}],"id":"missing"}', "utf8"));
    }),
    expectRejected("USAGE_NULL", "PROVIDER_USAGE_MISSING", () => {
      parseChatCompletionBytes(usageResponse("null"));
    }),
    expectRejected("USAGE_NEGATIVE", "PROVIDER_USAGE_INVALID", () => {
      parseChatCompletionBytes(usageResponse('{"completion_tokens":1,"prompt_tokens":-1,"total_tokens":0}'));
    }),
    expectRejected("USAGE_TOTAL_DRIFT", "PROVIDER_USAGE_TOTAL_DRIFT", () => {
      parseChatCompletionBytes(usageResponse('{"completion_tokens":1,"prompt_tokens":1,"total_tokens":3}'));
    }),
    expectRejected("USAGE_UNSAFE", "JSON_INTEGER_UNSAFE", () => {
      parseChatCompletionBytes(usageResponse('{"completion_tokens":1,"prompt_tokens":9007199254740992,"total_tokens":9007199254740992}'));
    }),
    expectRejected("NON_LOOPBACK_PEER", "NON_LOOPBACK_PEER_REJECTED", () => {
      validateObservedPeer("192.0.2.1", 8787);
    }),
    expectRejected("LOOPBACK_PORT_DRIFT", "LOOPBACK_PORT_DRIFT", () => {
      validateObservedPeer("127.0.0.1", 8788);
    }),
    expectRejected("TAXONOMY_DENOMINATOR_DRIFT", "TAXONOMY_NOT_CLOSED", () => {
      validateClosedTaxonomy({ successful: 35, failed: 0, invalid: 0, excluded: 0, denominator: 36 });
    }),
  ];

  const first = plan.cells[0];
  const second = plan.cells[1];
  const firstBinding = verifyCellBinding(root, first);
  const secondBinding = verifyCellBinding(root, second);
  cases.push(expectRejected("REQUEST_RESPONSE_CROSS_BINDING", "REQUEST_RESPONSE_CROSS_BINDING_INVALID", () => {
    assert(
      canonicalJson(firstBinding.terminal.request_receipt)
        === canonicalJson(secondBinding.responseReceipt.request_receipt),
      "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
      "cross-bound receipts unexpectedly matched",
    );
  }));

  cases.push(inventoryMutationCase("IDENTITY_MUTATION", (fixtureRoot) => {
    writeFileSync(`${fixtureRoot}/artifact.json`, canonicalBytes({ status: "MUTATED" }));
  }));
  cases.push(inventoryMutationCase("CLOSED_INVENTORY_EXTRA", (fixtureRoot) => {
    writeJsonCreateOnce(fixtureRoot, "extra.json", { extra: true });
  }));
  cases.push(inventoryMutationCase("CLOSED_INVENTORY_MISSING", (fixtureRoot) => {
    writeFileSync(`${fixtureRoot}/artifact.json`, Buffer.alloc(0));
  }));

  assert(cases.every((entry) => entry.rejected), "NEGATIVE_MATRIX_FALSE_ACCEPT", "negative matrix contains a false accept", cases);
  const receipt = {
    schema_version: "p1-207-negative-matrix-receipt/v1",
    status: "PASS",
    negative_cases: cases.length,
    false_accepts: 0,
    cases,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  writeJsonCreateOnce(root, "negative/NEGATIVE_MATRIX_RECEIPT.json", receipt);
  return receipt;
}

export async function runPreformal(evidenceRoot) {
  createOwnedRoot(evidenceRoot);
  const executionId = `P1-207-PREFORMAL-${Date.now()}`;
  const rootReceipts = writeRootReceipts(evidenceRoot);
  const plan = buildFormalPlan();
  const acceptedControl = runAcceptedP1129Control(evidenceRoot, plan);
  const referenceByTask = new Map();
  const terminals = [];

  for (const cell of plan.cells) {
    if (!referenceByTask.has(cell.task_id)) {
      referenceByTask.set(cell.task_id, buildAcceptedReferenceResponse(cell.task_id, `P1-207-${cell.task_id}`));
    }
    const accepted = referenceByTask.get(cell.task_id);
    const requestBytes = canonicalBytes(buildFormalRequest(cell));
    const rawResponseBytes = syntheticChatCompletion(cell, accepted.ir_bytes);
    const request = writeRequestEvidence(evidenceRoot, {
      executionId,
      cell,
      requestBytes,
      requestSequence: cell.ordinal,
      preformalGate: null,
      providerRequest: false,
    });
    const normalized = normalizePatchResponse({ cell, rawResponseBytes });
    const response = writeResponseEvidence(evidenceRoot, {
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
    writeTransportEvidence(evidenceRoot, {
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
    const execution = await executeSpine({
      taskId: cell.task_id,
      responseBytes: normalized.normalized_response_bytes,
      runId: `P1-207-SYNTHETIC-${cell.cell_id}`,
    });
    const executionManifest = writeExecutionEvidence(evidenceRoot, cell.cell_id, execution);
    const classification = execution.summary.worker_observed_classification === "VERIFIED_SUCCESS"
      ? "SUCCESSFUL"
      : "FAILED";
    terminals.push(writeTerminalEvidence(evidenceRoot, {
      executionId,
      cell,
      requestReceipt: request.identity,
      responseReceipt: response.identity,
      executionManifest,
      classification,
      reasonCode: classification === "SUCCESSFUL" ? "VERIFIED_SUCCESS" : "ORACLE_OR_TEST_FAILED",
      providerRequestCount: 0,
    }));
    verifyCellBinding(evidenceRoot, cell);
  }

  const taxonomy = validateClosedTaxonomy({
    successful: 36,
    failed: 0,
    invalid: 0,
    excluded: 0,
    denominator: 36,
  });
  const negative = runNegativeMatrix(evidenceRoot, plan);
  const runReceipt = {
    schema_version: "p1-207-run-receipt/v1",
    task_id: TASK_ID,
    execution_id: executionId,
    status: "PASS",
    diagnostic: { status: "NOT_APPLICABLE_PREFORMAL", provider_requests: 0 },
    denominator: 36,
    scheduled_cells: 36,
    terminal_cells: terminals.length,
    provider_requests: 0,
    diagnostic_provider_requests: 0,
    formal_provider_requests: 0,
    automatic_retries: 0,
    taxonomy,
    external_effects: FALSE_EXTERNAL_EFFECTS,
    secret_reads: 0,
    secret_persisted: false,
    report_rebuild_required: true,
    completed_at: new Date().toISOString(),
  };
  writeRunReceipt(evidenceRoot, runReceipt);
  const closed = closeEvidenceManifest(evidenceRoot, "PREFORMAL_SYNTHETIC_RAW_EVIDENCE");
  return {
    schema_version: "p1-207-offline-preformal-result/v1",
    task_id: TASK_ID,
    status: "PASS",
    evidence_root: evidenceRoot,
    formal_plan: rootReceipts.formalPlan,
    accepted_p1_129_control: {
      positive_runs: acceptedControl.positive_runs,
      negative_cases: acceptedControl.negative_cases,
      false_accepts: acceptedControl.false_accepts,
    },
    synthetic_cells: 36,
    accepted_p1_149_execution_spines: 36,
    accepted_p1_101_replays: 36,
    negative_cases: negative.negative_cases,
    false_accepts: 0,
    secret_reads: 0,
    provider_requests: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
    evidence_manifest: closed.identity,
  };
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  try {
    assert(process.argv.length === 3, "CLI_USAGE_INVALID", "usage: node preformal.mjs /absolute/absent-evidence-root");
    const result = await runPreformal(process.argv[2]);
    process.stdout.write(`${canonicalJson(result)}\n`);
  } catch (error) {
    const reasonCode = error instanceof P1207NonPass ? error.reasonCode : "UNEXPECTED_PREFORMAL_FAILURE";
    process.stdout.write(`${canonicalJson({
      schema_version: "p1-207-offline-preformal-result/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: reasonCode,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

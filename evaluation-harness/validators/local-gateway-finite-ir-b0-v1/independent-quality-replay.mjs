#!/usr/bin/env node

import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertOwnedProductionRunRoot,
  canonicalJsonBytes,
  createRunRoot,
  EVIDENCE_ROOT,
  productionRunRoot,
  readRegular,
  sha256,
  validateRunId,
  writeCreateOnce,
} from "../../recording/local-gateway-finite-ir-b0-v1/evidence.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const QUALITY_ORACLE_PATH = join(
  REPOSITORY_ROOT,
  "evaluation-harness/evaluator/local-gateway-finite-ir-b0-v1/quality-oracle.mjs",
);
const QUALITY_ORACLE_IDENTITY = Object.freeze({
  byte_length: 9283,
  sha256: "d1dd9952f6145a050cf4ebd9d067545fba5034e979bece6759e61a425b325c96",
});
const REQUEST_IDENTITY = Object.freeze({
  byte_length: 2472,
  sha256: "5232ec0f745240139dae5abaeb045c8a8b17bd627d34ceed71495a22a936abe2",
});

class QualityReplayError extends Error {
  constructor(code) {
    super(code);
    this.name = "QualityReplayError";
    this.code = code;
  }
}

const assert = (condition, code) => {
  if (!condition) throw new QualityReplayError(code);
};

const identity = (bytes) => ({ byte_length: bytes.length, sha256: sha256(bytes) });

function parseArguments() {
  const args = process.argv.slice(2);
  assert(args.length === 5 && args[0] === "run", "ARGUMENTS_INVALID");
  const values = Object.create(null);
  for (let index = 1; index < args.length; index += 2) {
    const flag = args[index];
    assert(["--provider-run-id", "--evaluation-id"].includes(flag) && values[flag] === undefined,
      "ARGUMENTS_INVALID");
    values[flag] = args[index + 1];
  }
  const providerRunId = validateRunId(values["--provider-run-id"]);
  const evaluationId = validateRunId(values["--evaluation-id"]);
  assert(providerRunId !== evaluationId, "RUN_IDS_MUST_DIFFER");
  return Object.freeze({ providerRunId, evaluationId });
}

async function loadExactOracle() {
  const bytes = readRegular(QUALITY_ORACLE_PATH, QUALITY_ORACLE_IDENTITY.byte_length);
  assert(bytes.length === QUALITY_ORACLE_IDENTITY.byte_length && sha256(bytes) === QUALITY_ORACLE_IDENTITY.sha256,
    "QUALITY_ORACLE_IDENTITY_DRIFT");
  const oracle = await import(`data:text/javascript;base64,${bytes.toString("base64")}`);
  assert(oracle.QUALITY_ORACLE_VERSION === "P1-062-INDEPENDENT-QUALITY-ORACLE/1",
    "QUALITY_ORACLE_VERSION_DRIFT");
  return oracle;
}

async function main() {
  assert(process.env.P1_062_LOCAL_GATEWAY_API_KEY === undefined, "CREDENTIAL_ENVIRONMENT_FORBIDDEN");
  const { providerRunId, evaluationId } = parseArguments();
  const { root: providerRoot } = assertOwnedProductionRunRoot(providerRunId);
  const requestBytes = readRegular(join(providerRoot, "request-body.json"), 32768);
  assert(requestBytes.length === REQUEST_IDENTITY.byte_length && sha256(requestBytes) === REQUEST_IDENTITY.sha256,
    "REQUEST_BODY_IDENTITY_DRIFT");
  const responseBytes = readRegular(join(providerRoot, "raw-response.json"), 131072);
  const receiptBytes = readRegular(join(providerRoot, "transport-receipt.json"), 65536);
  const slotBytes = readRegular(join(EVIDENCE_ROOT, "source-bearing-call-slot.json"), 8192);
  let receipt;
  let slot;
  try {
    receipt = JSON.parse(receiptBytes.toString("utf8"));
    slot = JSON.parse(slotBytes.toString("utf8"));
  } catch {
    throw new QualityReplayError("TRANSPORT_RECEIPT_INVALID");
  }
  assert(receiptBytes.equals(canonicalJsonBytes(receipt)) && receipt.terminal_code === "RESPONSE_RETAINED" &&
    receipt.source_bearing_submission_count === 1 && receipt.automatic_retry_count === 0 &&
    receipt.redirect_follow_count === 0 && receipt.proxy_use_count === 0 && receipt.dns_lookup_count === 0 &&
    receipt.peer?.address === "127.0.0.1" && receipt.peer?.port === 8787 && receipt.peer?.family === "IPv4" &&
    Number.isSafeInteger(receipt.http_status) && receipt.http_status >= 200 && receipt.http_status < 300 &&
    receipt.authorization_header_persisted_hashed_or_logged === false &&
    receipt.request_body?.byte_length === REQUEST_IDENTITY.byte_length &&
    receipt.request_body?.sha256 === REQUEST_IDENTITY.sha256,
  "TRANSPORT_RECEIPT_INVALID");
  assert(slotBytes.equals(canonicalJsonBytes(slot)) && slot.schema === "P1-062-SOURCE-BEARING-CALL-SLOT/1" &&
    slot.consumed === true && slot.ordinal === 1 && slot.automatic_retry_allowed === false &&
    slot.request_body?.byte_length === REQUEST_IDENTITY.byte_length &&
    slot.request_body?.sha256 === REQUEST_IDENTITY.sha256,
  "GLOBAL_CALL_SLOT_INVALID");
  assert(receipt.response_body?.byte_length === responseBytes.length &&
    receipt.response_body?.sha256 === sha256(responseBytes) &&
    receipt.response_body?.path === join(providerRoot, "raw-response.json"),
  "TRANSPORT_RESPONSE_IDENTITY_DRIFT");

  const oracle = await loadExactOracle();
  const projection = oracle.evaluateChatCompletionResponse(responseBytes);
  const evaluationRoot = productionRunRoot(evaluationId);
  createRunRoot(evaluationRoot);
  const projectionBytes = canonicalJsonBytes(projection);
  const projectionReceipt = writeCreateOnce(join(evaluationRoot, "quality-projection.json"), projectionBytes);
  const replayReceipt = writeCreateOnce(join(evaluationRoot, "quality-replay-receipt.json"), canonicalJsonBytes({
    schema: "P1-062-INDEPENDENT-QUALITY-REPLAY-RECEIPT/1",
    evaluation_id: evaluationId,
    provider_run_id: providerRunId,
    oracle: { path: QUALITY_ORACLE_PATH, ...QUALITY_ORACLE_IDENTITY },
    retained_response: identity(responseBytes),
    transport_receipt: identity(receiptBytes),
    global_call_slot: identity(slotBytes),
    request_body: REQUEST_IDENTITY,
    projection: {
      path: "quality-projection.json",
      byte_length: projectionReceipt.byte_length,
      sha256: projectionReceipt.sha256,
    },
    result_status: projection.status,
    credential_available: false,
    network_provider_remote_production_public_effects: false,
  }));
  process.stdout.write(canonicalJsonBytes({
    schema: "P1-062-INDEPENDENT-QUALITY-REPLAY-CLI-RESULT/1",
    status: "COMPLETE",
    evaluation_id: evaluationId,
    result_status: projection.status,
    projection: identity(projectionBytes),
    receipt: identity(readRegular(replayReceipt.path)),
  }));
}

main().catch((error) => {
  process.stderr.write(canonicalJsonBytes({
    schema: "P1-062-INDEPENDENT-QUALITY-REPLAY-CLI-ERROR/1",
    status: "NON_PASS",
    reason_code: error instanceof QualityReplayError ? error.code : "QUALITY_REPLAY_INTERNAL_FAILURE",
  }));
  process.exitCode = 1;
});

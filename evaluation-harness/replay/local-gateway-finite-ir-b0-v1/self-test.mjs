#!/usr/local/bin/node

import assert from "node:assert/strict";
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { buildRequestBody } from "../../adapters/local-gateway-finite-ir-b0-v1/core.mjs";
import {
  canonicalJsonBytes,
  createRunRoot,
  readRegular,
  sha256,
  writeCreateOnce,
} from "../../recording/local-gateway-finite-ir-b0-v1/evidence.mjs";
import {
  compareReplayProjectionsAtRoots,
  runReplayAtRoots,
} from "./runner.mjs";

const contentFor = (left, right) =>
  `{\"schema\":\"SL-PATCH-IR-CHOICE/1\",\"task\":\"SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0\",` +
  `\"values\":[\"${left}\",\"${right}\"]}`;
const IR10_CONTENT = contentFor("ARG1", "ARG0");

function identity(bytes) {
  return { byte_length: bytes.length, sha256: sha256(bytes) };
}

function createProviderRun(runParent, runId, rawResponse) {
  const root = join(runParent, runId);
  createRunRoot(root);
  const request = buildRequestBody();
  writeCreateOnce(join(root, "request-body.json"), request.bytes);
  writeCreateOnce(join(root, "egress-manifest.json"), canonicalJsonBytes(request.egress_manifest));
  writeCreateOnce(join(root, "source-bearing-call-slot.json"), canonicalJsonBytes({
    schema: "P1-062-SOURCE-BEARING-CALL-SLOT/1",
    consumed: true,
    ordinal: 1,
    automatic_retry_allowed: false,
    request_body: request.identity,
  }));
  const response = writeCreateOnce(join(root, "raw-response.json"), rawResponse);
  writeCreateOnce(join(root, "transport-receipt.json"), canonicalJsonBytes({
    schema: "P1-062-TRANSPORT-RECEIPT/1",
    adapter_version: "P1-062-LOCAL-GATEWAY-FINITE-IR-ADAPTER/1",
    terminal_code: "RESPONSE_RETAINED",
    request_body: request.identity,
    source_bearing_submission_count: 1,
    automatic_retry_count: 0,
    redirect_follow_count: 0,
    proxy_use_count: 0,
    dns_lookup_count: 0,
    peer: { address: "127.0.0.1", port: 8787, family: "IPv4" },
    http_status: 200,
    response_body: response,
    started_at: "2000-01-01T00:00:00.000Z",
    ended_at: "2000-01-01T00:00:01.000Z",
    latency_ms: 1000,
    authorization_header_persisted_hashed_or_logged: false,
    upstream_request_count: "UNKNOWN",
    monetary_cost: "UNKNOWN_USER_MANAGED_GATEWAY",
  }));
  return root;
}

function cleanupOwnedSelfTestRoot(root, expected) {
  const stat = lstatSync(root);
  assert.equal(stat.dev, expected.dev);
  assert.equal(stat.ino, expected.ino);
  assert.equal(realpathSync(root), root);
  const marker = readRegular(join(root, "self-test-ownership.json"), expected.marker.byte_length);
  assert.deepEqual(identity(marker), identity(expected.markerBytes));
  rmSync(root, { recursive: true, force: false, maxRetries: 0 });
  assert.equal(existsSync(root), false);
}

assert.equal(process.env.P1_062_LOCAL_GATEWAY_API_KEY, undefined,
  "self-test must not inherit the P1-062 credential");

const created = mkdtempSync(join(tmpdir(), "sourcelens-p1-062-replay-self-test-"));
const testRoot = realpathSync(created);
chmodSync(testRoot, 0o700);
const rootStat = lstatSync(testRoot);
const markerBytes = canonicalJsonBytes({
  schema: "P1-062-REPLAY-SELF-TEST-OWNERSHIP/1",
  created_exclusively: true,
});
const marker = writeCreateOnce(join(testRoot, "self-test-ownership.json"), markerBytes);
const ownership = { dev: rootStat.dev, ino: rootStat.ino, marker, markerBytes };

let pendingError;
try {
  const runParent = join(testRoot, "run");
  mkdirSync(runParent, { mode: 0o700 });

  const acceptedResponse = Buffer.from(JSON.stringify({
    id: "chatcmpl-p1-062-replay-self-test",
    object: "chat.completion",
    created: 1784600000,
    model: "gpt-5.6-luna",
    choices: [{
      index: 0,
      message: { role: "assistant", content: IR10_CONTENT },
      finish_reason: "stop",
    }],
    usage: { prompt_tokens: 300, completion_tokens: 30, total_tokens: 330 },
  }), "utf8");
  const providerRoot = createProviderRun(runParent, "provider-positive", acceptedResponse);
  const runARoot = join(runParent, "run-a");
  const runBRoot = join(runParent, "run-b");
  const providerCallSlot = join(providerRoot, "source-bearing-call-slot.json");
  const runA = await runReplayAtRoots({
    providerRoot,
    callSlotPath: providerCallSlot,
    evaluationRoot: runARoot,
    evaluationId: "run-a",
  });
  const runB = await runReplayAtRoots({
    providerRoot,
    callSlotPath: providerCallSlot,
    evaluationRoot: runBRoot,
    evaluationId: "run-b",
  });
  assert.equal(runA.parse_status, "ACCEPTED");
  assert.equal(runA.fixed_tests_pass, true);
  assert.equal(runB.parse_status, "ACCEPTED");
  assert.equal(runB.fixed_tests_pass, true);
  assert.deepEqual(runA.stable_projection_identity, runB.stable_projection_identity);
  const comparison = compareReplayProjectionsAtRoots({
    runARoot,
    runBRoot,
    runAId: "run-a",
    runBId: "run-b",
  });
  assert.equal(readRegular(comparison.path).length, comparison.identity.byte_length);

  const remainingStates = [
    { id: "ir00", content: contentFor("ARG0", "ARG0"), mutation: true },
    { id: "ir01", content: contentFor("ARG0", "ARG1"), mutation: false },
    { id: "ir11", content: contentFor("ARG1", "ARG1"), mutation: true },
  ];
  for (const state of remainingStates) {
    const response = Buffer.from(JSON.stringify({
      id: `chatcmpl-p1-062-replay-${state.id}`,
      object: "chat.completion",
      created: 1784600000,
      model: "gpt-5.6-luna",
      choices: [{
        index: 0,
        message: { role: "assistant", content: state.content },
        finish_reason: "stop",
      }],
    }), "utf8");
    const stateProvider = createProviderRun(runParent, `provider-${state.id}`, response);
    const stateRunRoot = join(runParent, `run-${state.id}`);
    const replay = await runReplayAtRoots({
      providerRoot: stateProvider,
      callSlotPath: join(stateProvider, "source-bearing-call-slot.json"),
      evaluationRoot: stateRunRoot,
      evaluationId: `run-${state.id}`,
    });
    assert.equal(replay.parse_status, "ACCEPTED");
    assert.equal(replay.fixed_tests_pass, false);
    const projection = JSON.parse(readRegular(replay.stable_projection_path).toString("utf8"));
    assert.equal(projection.parse.program_id, state.id.toUpperCase());
    assert.equal(projection.selected_outcome.mutation_applied, state.mutation);
    assert.equal(projection.rollback.status, "PASS");
  }

  const rejectedProviderRoot = createProviderRun(runParent, "provider-rejected", Buffer.from("{", "utf8"));
  const rejectedRoot = join(runParent, "run-rejected");
  const rejected = await runReplayAtRoots({
    providerRoot: rejectedProviderRoot,
    callSlotPath: join(rejectedProviderRoot, "source-bearing-call-slot.json"),
    evaluationRoot: rejectedRoot,
    evaluationId: "run-rejected",
  });
  assert.equal(rejected.parse_status, "REJECTED");
  assert.equal(rejected.fixed_tests_pass, false);
  const rejectedProjection = JSON.parse(readRegular(rejected.stable_projection_path).toString("utf8"));
  assert.equal(rejectedProjection.parse.reason_code, "OUTER_JSON_INVALID_OR_DUPLICATE");
  assert.equal(rejectedProjection.selected_outcome.mutation_applied, false);
  assert.equal(rejectedProjection.rollback.status, "PASS");

  process.stdout.write(canonicalJsonBytes({
    schema: "P1-062-REPLAY-SELF-TEST-RESULT/1",
    status: "PASS",
    positive_dual_run_exact_projection_equality: true,
    four_state_replay_pass: true,
    positive_stable_projection: runA.stable_projection_identity,
    rejected_response_replayed_without_mutation: true,
    network_provider_secret_effects: false,
  }));
} catch (error) {
  pendingError = error;
} finally {
  try {
    cleanupOwnedSelfTestRoot(testRoot, ownership);
  } catch (cleanupError) {
    if (!pendingError) pendingError = cleanupError;
  }
}

if (pendingError) throw pendingError;

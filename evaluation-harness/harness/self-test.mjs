#!/usr/bin/env node

import {
  appendFileSync, cpSync, readFileSync, readdirSync, rmSync, statSync,
} from "node:fs";
import { join } from "node:path";
import { canonicalJson } from "../evaluator/schema-validator.mjs";
import { MANIFEST_NAME, verifyManifest } from "../recording/manifest.mjs";
import { recordCommand, sha256 } from "../recording/recorder.mjs";
import { compareReplayArtifacts } from "../replay/replay.mjs";
import {
  EXPECTED_FREEZE_RECEIPT_SHA256, FREEZE_RECEIPT, RECORDING_ROOT, REPOSITORY_ROOT,
  assertFileIdentity, prepareEvidenceRoot, readJson, verifyFrozenInputs,
} from "./contracts.mjs";
import { runHarness } from "./run.mjs";

let assertions = 0;
function assert(condition, message) {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
  assertions += 1;
}

function expectFailure(action, message) {
  try { action(); }
  catch { assertions += 1; return; }
  throw new Error(`ASSERTION FAILED: ${message}`);
}

function filesRecursively(root, current = root) {
  return readdirSync(current, { withFileTypes: true }).flatMap((entry) => {
    const path = join(current, entry.name);
    return entry.isDirectory() ? filesRecursively(root, path) : [path];
  });
}

async function main() {
  const suffix = `${process.pid}-${Date.now()}`;
  const evidenceRoot = join(RECORDING_ROOT, `.worker-self-test-${suffix}`);
  const corruptRoot = join(RECORDING_ROOT, `.worker-corrupt-${suffix}`);
  const extraRoot = join(RECORDING_ROOT, `.worker-extra-${suffix}`);
  const cleanup = [evidenceRoot, corruptRoot, extraRoot];
  const freezeBefore = sha256(readFileSync(FREEZE_RECEIPT));
  try {
    const freeze = verifyFrozenInputs();
    assert(freezeBefore === EXPECTED_FREEZE_RECEIPT_SHA256, "freeze receipt identity must match the Worker binding");
    assert(freeze.validation.expected_assertion_count === 93, "Quality self-test contract must remain frozen");

    const quality = await recordCommand({
      argv: [process.execPath, join(REPOSITORY_ROOT, "evaluation-harness/evaluator/self-test.mjs")],
      cwd: REPOSITORY_ROOT,
      timeoutSeconds: 10,
      environment: { LC_ALL: "C", TZ: "UTC" },
    });
    assert(quality.ledger.exit_status === 0 && quality.ledger.signal === null, "Quality self-test must exit 0");
    assert(quality.stderr.length === 0, "Quality self-test must not emit stderr");
    const qualityResult = JSON.parse(quality.stdout.toString("utf8"));
    assert(qualityResult.self_test === "PASS" && qualityResult.assertions === 93, "Quality self-test result must match the freeze receipt");

    const run = await runHarness(evidenceRoot);
    assert(run.status === "PASS", "harness run must PASS");
    assert(run.replay_equal, "in-run replay must match");
    assert(run.controlled_failure_rejected, "controlled failure must be rejected");
    assert(run.promotion_probe_rejected, "promotion probe must be rejected");

    const manifest = readJson(join(evidenceRoot, MANIFEST_NAME));
    const verified = verifyManifest(evidenceRoot, manifest);
    assert(verified.valid, "evidence manifest must verify");
    assert(verified.manifest_sha256 === run.evidence_manifest_sha256, "returned manifest identity must match stored bytes");

    const summary = readJson(join(evidenceRoot, "evidence-summary.json"));
    assert(summary.execution_mode === "HARNESS_STUB_CONFORMANCE_ONLY", "execution mode must be HARNESS_STUB-only");
    assert(summary.benchmark_claim === false, "benchmark claim must remain false");
    assert(summary.agent_capability_claim === false, "Agent capability claim must remain false");
    assert(summary.included_in_vtsr_denominator === false, "run must remain outside VTSR");

    const positive = readJson(join(evidenceRoot, "positive/run-record.json"));
    const failure = readJson(join(evidenceRoot, "controlled-failure/run-record.json"));
    const promotedVerdict = readJson(join(evidenceRoot, "promotion-probe/evaluator-verdict.json"));
    assert(positive.terminal_status === "completed" && positive.stop_reason_code === "agent_complete", "positive RunRecord must complete");
    assert(failure.terminal_status === "failed" && failure.stop_reason_code === "test_failure", "controlled failure RunRecord must remain failed");
    assert(promotedVerdict.verdict === "FAIL" && promotedVerdict.reason_codes.includes("RESULT_SHA256_MISMATCH"), "promotion probe must remain rejected");

    const adapterLedger = readJson(join(evidenceRoot, "positive/adapter-command-ledger.json"));
    assert(Array.isArray(adapterLedger.argv) && adapterLedger.argv[0] === process.execPath, "ledger must contain actual executable argv");
    assert(adapterLedger.cwd === REPOSITORY_ROOT, "ledger must contain actual cwd");
    assert(adapterLedger.exit_status === 0 && adapterLedger.signal === null && adapterLedger.timed_out === false, "ledger must contain clean termination");
    assert(/^[0-9a-f]{64}$/.test(adapterLedger.stdout_sha256) && /^[0-9a-f]{64}$/.test(adapterLedger.stderr_sha256), "ledger stream hashes must be closed SHA-256 values");

    const beforeReplay = sha256(readFileSync(join(evidenceRoot, MANIFEST_NAME)));
    const replay = await recordCommand({
      argv: [process.execPath, join(REPOSITORY_ROOT, "evaluation-harness/replay/cli.mjs"), "--evidence", evidenceRoot],
      cwd: REPOSITORY_ROOT,
      timeoutSeconds: 10,
      environment: { LC_ALL: "C", TZ: "UTC" },
    });
    assert(replay.ledger.exit_status === 0 && replay.stderr.length === 0, "fresh replay CLI must exit 0 without stderr");
    const replayResult = JSON.parse(replay.stdout.toString("utf8"));
    assert(replayResult.status === "PASS" && replayResult.projection_byte_equal, "fresh replay projection must match");
    assert(replayResult.evaluator_output_byte_equal, "fresh replay evaluator bytes must match");
    assert(sha256(readFileSync(join(evidenceRoot, MANIFEST_NAME))) === beforeReplay, "fresh replay must not mutate evidence");

    const originalProjection = readJson(join(evidenceRoot, "positive/deterministic-projection.json"));
    const replayProjection = readJson(join(evidenceRoot, "replay/deterministic-projection.json"));
    const originalVerdict = readFileSync(join(evidenceRoot, "positive/evaluator-verdict.json"));
    const changedProjection = { ...replayProjection, result_sha256: "0".repeat(64) };
    const replayMismatch = compareReplayArtifacts(originalProjection, changedProjection, originalVerdict, originalVerdict);
    assert(replayMismatch.status === "FAIL" && replayMismatch.projection_byte_equal === false, "replay projection drift must fail closed");

    cpSync(evidenceRoot, corruptRoot, { recursive: true, errorOnExist: true });
    appendFileSync(join(corruptRoot, "evidence-summary.json"), "\n");
    expectFailure(() => verifyManifest(corruptRoot, readJson(join(corruptRoot, MANIFEST_NAME))), "artifact mutation must invalidate manifest");

    cpSync(evidenceRoot, extraRoot, { recursive: true, errorOnExist: true });
    appendFileSync(join(extraRoot, "unexpected.txt"), "unexpected\n", { flag: "wx" });
    expectFailure(() => verifyManifest(extraRoot, readJson(join(extraRoot, MANIFEST_NAME))), "extra artifact must invalidate manifest population");

    expectFailure(() => prepareEvidenceRoot(join(REPOSITORY_ROOT, `.forbidden-output-${suffix}`)), "output outside recording root must fail closed");
    expectFailure(
      () => assertFileIdentity(FREEZE_RECEIPT, "0".repeat(64), statSync(FREEZE_RECEIPT).size, "synthetic freeze drift"),
      "freeze identity drift must fail closed",
    );

    for (const path of filesRecursively(join(REPOSITORY_ROOT, "evaluation-harness"))) {
      if (!path.endsWith(".mjs") || path.includes("/evaluator/") || path.endsWith("/harness/self-test.mjs")) continue;
      const source = readFileSync(path, "utf8");
      for (const forbidden of ["node:http", "node:https", "node:net", "node:tls", "fetch("]) {
        assert(!source.includes(forbidden), `${path} must not contain network surface ${forbidden}`);
      }
    }

    assert(sha256(readFileSync(FREEZE_RECEIPT)) === freezeBefore, "Quality Freeze Receipt must remain byte-identical");
    verifyFrozenInputs();
    return {
      schema_version: "1.0",
      self_test: "PASS",
      assertions,
      quality_self_test_assertions: qualityResult.assertions,
      positive_verdict: summary.positive_verdict,
      controlled_failure_verdict: summary.controlled_failure_verdict,
      promotion_probe_verdict: summary.promotion_probe_verdict,
      replay_equal: replayResult.projection_byte_equal && replayResult.evaluator_output_byte_equal,
      manifest_mutation_rejected: true,
      manifest_population_drift_rejected: true,
      claim_boundary: summary.claim_boundary,
    };
  } finally {
    for (const path of cleanup) rmSync(path, { recursive: true, force: true });
  }
}

try {
  process.stdout.write(`${canonicalJson(await main())}\n`);
} catch (error) {
  process.stderr.write(`AIOS_P1_001_WORKER_SELF_TEST_ERROR: ${error.stack ?? error.message}\n`);
  process.exit(1);
}

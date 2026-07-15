import { mkdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { canonicalJson } from "../evaluator/schema-validator.mjs";
import { buildManifest, verifyManifest } from "../recording/manifest.mjs";
import { recordCommand, sha256 } from "../recording/recorder.mjs";
import {
  ADAPTER, EVALUATOR, EXPECTED_FREEZE_RECEIPT_SHA256, FIXTURE_ROOT, INPUT_PATHS,
  REPOSITORY_ROOT, SCHEMA_ROOT, loadAndPreflight, prepareEvidenceRoot,
  runtimeObservation, validateRunRecord, writeBytesCreateOnce, writeJsonCreateOnce,
} from "./contracts.mjs";

const COMMAND_ENVIRONMENT = Object.freeze({ LC_ALL: "C", TZ: "UTC" });

function relativeOutput(root, path) {
  return relative(root, path).split("\\").join("/");
}

function resultFromStdout(execution) {
  if (execution.ledger.timed_out || execution.ledger.signal !== null || execution.ledger.exit_status !== 0) {
    throw new Error(`HARNESS_STUB execution failed: ${canonicalJson(execution.ledger)}`);
  }
  if (execution.stderr.length !== 0) throw new Error("HARNESS_STUB wrote stderr");
  try { return JSON.parse(execution.stdout.toString("utf8")); }
  catch (error) { throw new Error(`HARNESS_STUB stdout is not JSON: ${error.message}`); }
}

function buildRunRecord({ contracts, execution, resultSha, scenario, outputRoot, scenarioRoot }) {
  const failed = scenario === "controlled-failure";
  const runKind = scenario === "replay" ? "positive" : scenario;
  const record = {
    schema_version: "1.0",
    run_id: `AIOS-P1-001-${runKind.toUpperCase()}`,
    task_id: contracts.task.task_id,
    dataset_version: contracts.task.dataset_version,
    adapter_id: contracts.configuration.adapter_id,
    adapter_version: contracts.configuration.adapter_version,
    environment_snapshot_id: contracts.environment.snapshot_id,
    system_configuration_id: contracts.configuration.configuration_id,
    repetition_id: 1,
    started_at: execution.ledger.started_at,
    ended_at: execution.ledger.ended_at,
    terminal_status: failed ? "failed" : "completed",
    stop_reason_code: failed ? "test_failure" : "agent_complete",
    invalid_run_reason: null,
    error_taxonomy: failed ? ["verification"] : [],
    trace_ref: relativeOutput(outputRoot, join(scenarioRoot, "adapter-command-ledger.json")),
    patch_ref: null,
    test_artifact_refs: [relativeOutput(outputRoot, join(scenarioRoot, "result.json"))],
    verification_ref: "quality-evaluator://AIOS-P1-001/1.0.0",
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      tool_calls: 1,
      retries: 0,
      human_interventions: 0,
      cost_usd: 0,
      latency_ms: execution.ledger.latency_ms,
    },
    policy_violations: [],
    artifact_checksums: {
      result: resultSha,
      adapter_stdout: execution.ledger.stdout_sha256,
      adapter_stderr: execution.ledger.stderr_sha256,
    },
  };
  validateRunRecord(record);
  return record;
}

async function invokeEvaluator({ runRecordPath, resultPath }) {
  const argv = Object.freeze([
    process.execPath, EVALUATOR,
    "--task", INPUT_PATHS.task,
    "--environment", INPUT_PATHS.environment,
    "--configuration", INPUT_PATHS.configuration,
    "--run-record", runRecordPath,
    "--result", resultPath,
    "--oracle", INPUT_PATHS.oracle,
    "--schema-root", SCHEMA_ROOT,
    "--artifact-root", REPOSITORY_ROOT,
  ]);
  const execution = await recordCommand({
    argv,
    cwd: REPOSITORY_ROOT,
    timeoutSeconds: 10,
    environment: COMMAND_ENVIRONMENT,
  });
  if (execution.ledger.timed_out || execution.ledger.signal !== null || execution.stderr.length !== 0) {
    throw new Error("Quality evaluator did not terminate cleanly");
  }
  let verdict;
  try { verdict = JSON.parse(execution.stdout.toString("utf8")); }
  catch (error) { throw new Error(`Quality evaluator stdout is not JSON: ${error.message}`); }
  return { execution, verdict };
}

export async function executeScenario({ contracts, outputRoot, name }) {
  const scenarioRoot = join(outputRoot, name);
  mkdirSync(scenarioRoot, { mode: 0o700 });
  const adapterArgv = [process.execPath, ADAPTER, "--context", INPUT_PATHS.context];
  if (name === "controlled-failure") {
    adapterArgv.push("--controlled-failure", INPUT_PATHS.controlledFailure);
  }
  const adapterExecution = await recordCommand({
    argv: Object.freeze(adapterArgv),
    cwd: REPOSITORY_ROOT,
    timeoutSeconds: contracts.task.budgets.wall_clock_seconds,
    environment: COMMAND_ENVIRONMENT,
  });
  resultFromStdout(adapterExecution);
  const resultPath = join(scenarioRoot, "result.json");
  const adapterLedgerPath = join(scenarioRoot, "adapter-command-ledger.json");
  writeBytesCreateOnce(resultPath, adapterExecution.stdout);
  writeJsonCreateOnce(adapterLedgerPath, adapterExecution.ledger);

  const runRecord = buildRunRecord({
    contracts,
    execution: adapterExecution,
    resultSha: sha256(adapterExecution.stdout),
    scenario: name,
    outputRoot,
    scenarioRoot,
  });
  const runRecordPath = join(scenarioRoot, "run-record.json");
  writeJsonCreateOnce(runRecordPath, runRecord);

  const evaluated = await invokeEvaluator({ runRecordPath, resultPath });
  writeJsonCreateOnce(join(scenarioRoot, "evaluator-command-ledger.json"), evaluated.execution.ledger);
  writeBytesCreateOnce(join(scenarioRoot, "evaluator-verdict.json"), evaluated.execution.stdout);

  if (name !== "controlled-failure") {
    if (evaluated.execution.ledger.exit_status !== 0 || evaluated.verdict.verdict !== "PASS") {
      throw new Error("positive scenario did not PASS the frozen evaluator");
    }
  } else if (evaluated.execution.ledger.exit_status !== 1
      || evaluated.verdict.verdict !== "FAIL"
      || !evaluated.verdict.reason_codes.includes("RESULT_SHA256_MISMATCH")) {
    throw new Error("controlled failure was not rejected for the frozen wrong-result reason");
  }

  const projection = {
    schema_version: "1.0",
    scenario: name,
    task_id: runRecord.task_id,
    dataset_version: runRecord.dataset_version,
    adapter_id: runRecord.adapter_id,
    adapter_version: runRecord.adapter_version,
    environment_snapshot_id: runRecord.environment_snapshot_id,
    system_configuration_id: runRecord.system_configuration_id,
    result_sha256: sha256(adapterExecution.stdout),
    evaluator_identity_sha256: evaluated.verdict.evaluator_identity_sha256,
    evaluator_verdict: evaluated.verdict.verdict,
    evaluator_reason_codes: evaluated.verdict.reason_codes,
    evaluator_output_sha256: evaluated.execution.ledger.stdout_sha256,
    terminal_status: runRecord.terminal_status,
    stop_reason_code: runRecord.stop_reason_code,
  };
  writeJsonCreateOnce(join(scenarioRoot, "deterministic-projection.json"), projection);
  return { runRecord, projection, evaluated, resultPath, runRecordPath };
}

async function executePromotionProbe({ contracts, outputRoot, controlled }) {
  const root = join(outputRoot, "promotion-probe");
  mkdirSync(root, { mode: 0o700 });
  const promoted = {
    ...controlled.runRecord,
    run_id: "AIOS-P1-001-CONTROLLED-FAILURE-PROMOTION-PROBE",
    terminal_status: "completed",
    stop_reason_code: "agent_complete",
    error_taxonomy: [],
  };
  validateRunRecord(promoted);
  const recordPath = join(root, "run-record.json");
  writeJsonCreateOnce(recordPath, promoted);
  const evaluated = await invokeEvaluator({ runRecordPath: recordPath, resultPath: controlled.resultPath });
  writeJsonCreateOnce(join(root, "evaluator-command-ledger.json"), evaluated.execution.ledger);
  writeBytesCreateOnce(join(root, "evaluator-verdict.json"), evaluated.execution.stdout);
  if (evaluated.execution.ledger.exit_status !== 1
      || evaluated.verdict.verdict !== "FAIL"
      || !evaluated.verdict.reason_codes.includes("RESULT_SHA256_MISMATCH")) {
    throw new Error("controlled failure was promoted to success");
  }
  return evaluated;
}

export async function runHarness(outputPath) {
  const contracts = loadAndPreflight();
  const runtime = runtimeObservation();
  const outputRoot = prepareEvidenceRoot(outputPath);
  writeJsonCreateOnce(join(outputRoot, "preflight.json"), {
    schema_version: "1.0",
    record_type: "aios_p1_001_cross_contract_preflight",
    status: "PASS",
    freeze_receipt_sha256: EXPECTED_FREEZE_RECEIPT_SHA256,
    input_hashes: contracts.input_hashes,
    runtime,
    claim_boundary: "Cooperative-local harness conformance observation only.",
  });

  const primary = await executeScenario({ contracts, outputRoot, name: "positive" });
  const controlled = await executeScenario({ contracts, outputRoot, name: "controlled-failure" });
  const promotion = await executePromotionProbe({ contracts, outputRoot, controlled });
  const replay = await executeScenario({ contracts, outputRoot, name: "replay" });

  const primaryBytes = Buffer.from(`${canonicalJson(primary.projection)}\n`, "utf8");
  const replayComparable = { ...replay.projection, scenario: "positive" };
  const replayBytes = Buffer.from(`${canonicalJson(replayComparable)}\n`, "utf8");
  const replayEqual = primaryBytes.equals(replayBytes);
  const comparison = {
    schema_version: "1.0",
    primary_projection_sha256: sha256(primaryBytes),
    replay_projection_sha256: sha256(replayBytes),
    projection_byte_equal: replayEqual,
    primary_result_sha256: primary.projection.result_sha256,
    replay_result_sha256: replay.projection.result_sha256,
    evaluator_output_byte_equal: primary.evaluated.execution.stdout.equals(replay.evaluated.execution.stdout),
  };
  if (!comparison.projection_byte_equal || !comparison.evaluator_output_byte_equal) {
    throw new Error("fresh replay did not reproduce the normalized verdict and artifact identity");
  }
  writeJsonCreateOnce(join(outputRoot, "replay-comparison.json"), comparison);

  const summary = {
    schema_version: "1.0",
    task_id: "AIOS-P1-001",
    execution_mode: "HARNESS_STUB_CONFORMANCE_ONLY",
    positive_verdict: primary.evaluated.verdict.verdict,
    controlled_failure_verdict: controlled.evaluated.verdict.verdict,
    promotion_probe_verdict: promotion.verdict.verdict,
    replay_equal: replayEqual,
    included_in_vtsr_denominator: false,
    benchmark_claim: false,
    agent_capability_claim: false,
    claim_boundary: contracts.oracle.claim_boundary,
  };
  writeJsonCreateOnce(join(outputRoot, "evidence-summary.json"), summary);

  const manifest = buildManifest(outputRoot, {
    freeze_receipt_sha256: EXPECTED_FREEZE_RECEIPT_SHA256,
    runtime,
    primary_projection_sha256: comparison.primary_projection_sha256,
    replay_projection_sha256: comparison.replay_projection_sha256,
    replay_equal: replayEqual,
    controlled_failure_rejected: controlled.evaluated.verdict.verdict === "FAIL",
    promotion_probe_rejected: promotion.verdict.verdict === "FAIL",
  });
  writeJsonCreateOnce(join(outputRoot, "evidence-manifest.json"), manifest);
  const verification = verifyManifest(outputRoot, manifest);
  return {
    schema_version: "1.0",
    status: "PASS",
    task_id: "AIOS-P1-001",
    evidence_root: outputRoot,
    evidence_manifest_sha256: verification.manifest_sha256,
    replay_equal: replayEqual,
    controlled_failure_rejected: true,
    promotion_probe_rejected: true,
    claim_boundary: summary.claim_boundary,
  };
}

#!/usr/bin/env node

import {
  closeSync,
  constants,
  existsSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  rmdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

import {
  canonicalBytes,
  sha256,
} from "../p1-097-minimal-documented/core.mjs";
import {
  identityOf,
  parseFrozenJson,
  readBoundFile,
} from "../../validators/p1-117-clean-room-empirical-baseline/core.mjs";
import {
  loadSafeDisclosure,
  validateProviderResponse,
} from "../../validators/p1-117-clean-room-empirical-baseline/disclosure.mjs";
import {
  loadMatrix,
  validateMatrix,
} from "../../validators/p1-117-clean-room-empirical-baseline/preflight.mjs";
import {
  SecretSinkForbidden,
  AppendOnlyAccountingLedger,
  PROVIDER_SESSION_CLOSURE_CLAIM,
  conservativeInputTokenUpperBound,
  guardResponseBytesBeforeIdentity,
} from "./provider-client.mjs";
import {
  applyEvaluateAndRollback,
  createLocalRunContext,
  trustedCompilerOperationIds,
} from "./local-execution.mjs";
import {
  REPOSITORY_ROOT,
  offlinePreflight,
} from "./preflight.mjs";
import {
  buildTrace,
  parseTrace,
} from "../../recording/p1-117-clean-room-empirical-baseline/trace.mjs";
import {
  buildStableProjection,
  replayExact,
} from "../../replay/p1-117-clean-room-empirical-baseline/replay.mjs";
import {
  summarizeRunManifestPopulation,
} from "./runtime.mjs";
import {
  validateFormalRuntimeReceipt,
  validateTraceEvidence,
} from "../../evaluator/p1-117-clean-room-empirical-baseline/recompute.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function identity(path) {
  const bytes = readFileSync(resolve(REPOSITORY_ROOT, path));
  return { path, ...identityOf(bytes) };
}

function absoluteIdentity(path) {
  const bytes = readFileSync(path);
  return { path, ...identityOf(bytes) };
}

function writeExclusive(path, bytes) {
  const fd = openSync(
    path,
    constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | (constants.O_NOFOLLOW ?? 0),
    0o600,
  );
  try {
    writeFileSync(fd, bytes);
  } finally {
    closeSync(fd);
  }
}

function runCompilerMatrix(matrix) {
  const temporary = realpathSync(
    mkdtempSync(join(tmpdir(), "p1-117-compiler-self-test-")),
  );
  let runs = 0;
  try {
    for (const operationId of trustedCompilerOperationIds) {
      const entry = matrix.schedule.find((candidate) => (
        candidate.system === "B0"
          && candidate.finite_operation_ids.includes(operationId)
      ));
      assert(entry, `missing matrix entry for ${operationId}`);
      const runRoot = join(temporary, `run-${String(runs + 1).padStart(2, "0")}`);
      mkdirSync(runRoot, { mode: 0o700, recursive: false });
      const taskBinding = matrix.task_bindings.find(
        (candidate) => candidate.task_id === entry.task_id,
      );
      const context = createLocalRunContext({ entry, taskBinding, runRoot });
      const result = applyEvaluateAndRollback(context, operationId);
      assert(
        result.tests.length === 2
          && result.rollback.exact === true
          && result.rollback.source_state_restored === true
          && result.rollback.nonowned_paths_touched === 0,
        `compiler or rollback self-test failed for ${operationId}`,
      );
      rmdirSync(runRoot);
      runs += 1;
    }
  } finally {
    rmdirSync(temporary);
  }
  return runs;
}

async function buildRequestSelfTest(matrix) {
  const entry = matrix.schedule.find((candidate) => candidate.system === "B0");
  const configuration = parseFrozenJson(
    readBoundFile(
      REPOSITORY_ROOT,
      entry.system_configuration,
      "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
    ).bytes,
    "SYSTEM_CONFIGURATION_SCHEMA_INVALID",
  );
  const safe = loadSafeDisclosure(REPOSITORY_ROOT, matrix, entry);
  const wrapper = await import(resolve(REPOSITORY_ROOT, entry.executable.path));
  const request = wrapper.buildProviderRequest({
    entry,
    configuration,
    disclosure: safe.disclosure,
    responseSchemaIdentity: matrix.response_schema,
  });
  assert(request.bytes.length > 0, "request-safe bytes missing");
  const response = canonicalBytes({
    schema_version: "p1-117-provider-selection/v1",
    selected_operation_id: entry.finite_operation_ids[0],
  });
  assert(
    validateProviderResponse(response, entry.finite_operation_ids)
      .selected_operation_id === entry.finite_operation_ids[0],
    "exact response selection rejected",
  );
}

async function allRequestBoundsSelfTest(matrix) {
  let validated = 0;
  for (const entry of matrix.schedule) {
    const configuration = parseFrozenJson(
      readBoundFile(
        REPOSITORY_ROOT,
        entry.system_configuration,
        "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
      ).bytes,
      "SYSTEM_CONFIGURATION_SCHEMA_INVALID",
    );
    const safe = loadSafeDisclosure(REPOSITORY_ROOT, matrix, entry);
    const wrapper = await import(resolve(REPOSITORY_ROOT, entry.executable.path));
    const scannerObservation = entry.system === "B2"
      ? {
          operation_id: "repository_analysis.scan",
          real_invocation: true,
          exit_code: 0,
          accepted_binding_sha256: entry.accepted_scanner_binding.sha256,
          scanner_artifact_sha256: "a".repeat(64),
          file_count: 0,
          language_counts: {},
          source_bytes_disclosed_to_provider: false,
        }
      : null;
    const request = wrapper.buildProviderRequest({
      entry,
      configuration,
      disclosure: safe.disclosure,
      responseSchemaIdentity: matrix.response_schema,
      scannerObservation,
    });
    const bound = conservativeInputTokenUpperBound(request.bytes);
    assert(
      bound.tokens <= configuration.input_tokens_reserved
        && configuration.input_tokens_reserved === 12000,
      `request bound exceeds reservation: ${entry.run_id}`,
    );
    validated += 1;
  }
  assert(validated === 36, "request-bound self-test did not cover all 36 runs");
}

function b1TraceReplaySelfTest(matrix) {
  const entry = matrix.schedule.find((candidate) => candidate.system === "B1");
  const temporary = realpathSync(
    mkdtempSync(join(tmpdir(), "p1-117-b1-trace-self-test-")),
  );
  const runRoot = join(temporary, "run");
  mkdirSync(runRoot, { mode: 0o700, recursive: false });
  try {
    const taskBinding = matrix.task_bindings.find(
      (candidate) => candidate.task_id === entry.task_id,
    );
    const context = createLocalRunContext({ entry, taskBinding, runRoot });
    const execution = applyEvaluateAndRollback(
      context,
      entry.finite_operation_ids[0],
    );
    assert(
      execution.b1_operations.length === 4
        && execution.b1_operations.map((record) => record.operation_id).join(",")
          === "file_listing,lexical_search,trusted_finite_operation_compiler,verification_ledger",
      "B1 local tool ledger is incomplete or reordered",
    );
    const tests = {
      issue_specific: execution.issue_specific,
      regression: execution.regression,
      policy_violations: [],
      b1_local_tool_ledger: execution.b1_operations,
    };
    const terminal = {
      status: execution.tests_pass ? "COMPLETED" : "FAILED",
      reason_code: execution.tests_pass ? "TESTS_PASS_PENDING_INDEPENDENT_ORACLE" : "INDEPENDENT_TEST_NON_PASS",
      invalid_run_reason: null,
      post_hoc_excluded: false,
    };
    const rollback = {
      status: "PASS_EXACT",
      source_state_restored: true,
      nonowned_paths_touched: 0,
    };
    const truth = {
      task_spec: entry.task_spec,
      environment_snapshot: context.materialization_binding.environment_snapshot,
      dataset_task_binding: context.materialization_binding.dataset_task_binding,
      source_template_binding: context.materialization_binding.source_template_binding,
      source_template_manifest: context.materialization_binding.source_template_manifest,
      executable: entry.executable,
      system_configuration: entry.system_configuration,
      accepted_scanner_binding: null,
    };
    const trace = buildTrace({
      entry,
      admission: {
        request_safe_identity: {
          relative_path: "request-safe.json",
          sha256: "0".repeat(64),
          byte_length: 1,
        },
      },
      materialization: context.materialization_binding,
      selectedOperationId: entry.finite_operation_ids[0],
      tests,
      terminal,
      rollback,
    });
    const parsed = parseTrace(trace);
    validateTraceEvidence(trace, entry, taskBinding);
    assert(
      parsed[1].data.local_tool_ledger.operations.length === 4,
      "B1 ledger missing from trace",
    );
    const projectionInputs = {
      selectedOperationId: entry.finite_operation_ids[0],
      responseOutcome: { status: "ACCEPTED", reason_code: null },
      tests,
      terminal,
      externalTruthBinding: truth,
    };
    const projection = buildStableProjection({ entry, ...projectionInputs });
    const replay = replayExact({
      entry,
      traceBytes: trace,
      stableProjectionBytes: projection,
      projectionInputs,
    });
    assert(replay.status === "PASS", "B1 exact replay failed");
  } finally {
    rmdirSync(runRoot);
    rmdirSync(temporary);
  }
}

function b2TraceSchemaSelfTest(matrix) {
  const entry = matrix.schedule.find((candidate) => candidate.system === "B2");
  const taskBinding = matrix.task_bindings.find(
    (candidate) => candidate.task_id === entry.task_id,
  );
  const scannerIdentity = {
    path: "/owned/self-test/scanner",
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
  const trace = buildTrace({
    entry,
    admission: {
      request_safe_identity: {
        relative_path: "request-safe.json",
        sha256: "0".repeat(64),
        byte_length: 1,
      },
    },
    materialization: {
      environment_snapshot: taskBinding.environment_snapshot,
      dataset_task_binding: taskBinding.dataset_task_binding,
      source_template_binding: taskBinding.source_template_binding,
      source_template_manifest: {
        sha256: taskBinding.source_template_binding.manifest_sha256,
        byte_length: taskBinding.source_template_binding.manifest_byte_length,
        file_count: taskBinding.source_template_binding.file_count,
      },
    },
    selectedOperationId: entry.finite_operation_ids[0],
    scannerCommand: {
      command_ledger_sha256: "c".repeat(64),
      scanner_pre_call_identity: scannerIdentity,
    },
    tests: {
      issue_specific: { exit_status: 0 },
      regression: { exit_status: 0 },
      policy_violations: [],
      b1_local_tool_ledger: [],
    },
    terminal: {
      status: "COMPLETED",
      reason_code: "TESTS_PASS_PENDING_INDEPENDENT_ORACLE",
      invalid_run_reason: null,
      post_hoc_excluded: false,
    },
    rollback: {
      status: "PASS_EXACT",
      source_state_restored: true,
      nonowned_paths_touched: 0,
    },
  });
  validateTraceEvidence(trace, entry, taskBinding);
}

function accountingCloseSelfTest() {
  const temporary = realpathSync(
    mkdtempSync(join(tmpdir(), "p1-117-accounting-self-test-")),
  );
  const ledgerPath = join(temporary, "ledger.jsonl");
  try {
    const ledger = AppendOnlyAccountingLedger.create(ledgerPath, {
      provider_requests_max: 60,
      automatic_retry_max: 0,
      input_tokens_max: 500000,
      output_tokens_max: 100000,
      currency: "USD",
      max_spend: 25,
    });
    ledger.reserve("P1-117-SELF-TEST", {
      inputTokenBound: 12000,
      inputTokenBoundMethod: "QUALITY_FROZEN_PER_RUN_RESERVATION",
      outputTokenBound: 2048,
    });
    ledger.observe("P1-117-SELF-TEST", {
      usage: {},
      status_code: null,
      peer_address: null,
      provider_requests: 1,
      successful_loopback_connections: 0,
      automatic_retries: 0,
      reason_code: "PROVIDER_TRANSPORT_ERROR",
      latency_ms: 0,
    });
    ledger.close();
    ledger.close();
    assert(ledger.closed === true, "accounting ledger did not close");
    assert(
      readFileSync(ledgerPath, "utf8").trim().split("\n").length === 4,
      "accounting close event sequence drifted",
    );
  } finally {
    if (existsSync(ledgerPath)) unlinkSync(ledgerPath);
    rmdirSync(temporary);
  }
}

function sessionClosureClaimSelfTest() {
  assert(
    PROVIDER_SESSION_CLOSURE_CLAIM.provider_session_closed === true
      && PROVIDER_SESSION_CLOSURE_CLAIM.owned_secret_buffer_overwrite_attempted === true
      && PROVIDER_SESSION_CLOSURE_CLAIM.whole_process_memory_zeroization_claim === "NOT_CLAIMED"
      && !Object.hasOwn(
        PROVIDER_SESSION_CLOSURE_CLAIM,
        "provider_session_closed_and_secret_zeroized",
      ),
    "Provider session closure claim is broader than observable evidence",
  );
}

function manifestPopulationSelfTest(matrix) {
  const records = matrix.schedule.map((entry, index) => ({
    run_id: entry.run_id,
    sha256: String(index + 1).padStart(64, "0"),
    byte_length: index + 1,
  }));
  const summary = summarizeRunManifestPopulation(records);
  assert(
    summary.count === 36
      && /^[0-9a-f]{64}$/.test(summary.aggregate_sha256)
      && summary.aggregate_byte_length > 0,
    "run-manifest population summary is invalid",
  );
}

function formalRuntimeReceiptCrossCheck(matrix) {
  const manifestPopulation = matrix.schedule.map((entry, index) => ({
    run_id: entry.run_id,
    sha256: String(index + 1).padStart(64, "0"),
    byte_length: index + 1,
  }));
  const ledgerBytes = Buffer.from("synthetic-accounting-ledger-self-test\n", "utf8");
  const receipt = {
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
    accounting_ledger: identityOf(ledgerBytes),
    run_manifest_population: summarizeRunManifestPopulation(manifestPopulation),
    cost: {
      status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
      currency: "USD",
      amount: null,
    },
  };
  validateFormalRuntimeReceipt({
    receipt,
    ledgerBytes,
    manifestPopulation,
    requests: 36,
  });
  let rejectedLegacyField = false;
  try {
    validateFormalRuntimeReceipt({
      receipt: {
        ...receipt,
        process_wide_secret_memory_zeroization_claimed: false,
      },
      ledgerBytes,
      manifestPopulation,
      requests: 36,
    });
  } catch {
    rejectedLegacyField = true;
  }
  assert(rejectedLegacyField, "formal runtime receipt accepted an undeclared legacy field");
}

async function fullOfflinePreflightSelfTest(matrix, matrixBinding) {
  const temporary = mkdtempSync(join(HERE, ".offline-preflight-self-test-"));
  const preregistrationPath = join(temporary, "preregistration.json");
  try {
    const qualityPreregistration = parseFrozenJson(
      readFileSync(
        resolve(
          REPOSITORY_ROOT,
          "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/preregistration.json",
        ),
      ),
      "PREREGISTRATION_SCHEMA_INVALID",
    );
    const artifactNames = {
      matrix_plan: matrixBinding,
      safe_disclosures: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/safe-disclosures.json",
      ),
      response_schema: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/response-schema.json",
      ),
      response_safe_schema: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/response-safe-schema.json",
      ),
      b0_descriptor: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/b0-descriptor.json",
      ),
      b1_descriptor: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/b1-descriptor.json",
      ),
      b2_descriptor: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/b2-descriptor.json",
      ),
      evaluation_oracle: structuredClone(
        qualityPreregistration.frozen_artifacts.evaluation_oracle,
      ),
      formal_run_contract: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/formal-run-contract.json",
      ),
      negative_cases: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/negative-cases.json",
      ),
      p2_context_preregistration: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/p2-context-engine-preregistration.json",
      ),
      independent_evaluator: identity(
        "evaluation-harness/evaluator/p1-117-clean-room-empirical-baseline/recompute.mjs",
      ),
      validator_core: identity(
        "evaluation-harness/validators/p1-117-clean-room-empirical-baseline/core.mjs",
      ),
      disclosure_validator: identity(
        "evaluation-harness/validators/p1-117-clean-room-empirical-baseline/disclosure.mjs",
      ),
      preflight_validator: identity(
        "evaluation-harness/validators/p1-117-clean-room-empirical-baseline/preflight.mjs",
      ),
      validator_entry: identity(
        "evaluation-harness/validators/p1-117-clean-room-empirical-baseline/validate.mjs",
      ),
      validator_self_test: identity(
        "evaluation-harness/validators/p1-117-clean-room-empirical-baseline/self-test.mjs",
      ),
      environment_snapshot_rep001: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/environment-snapshots/rep001.json",
      ),
      environment_snapshot_rep002: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/environment-snapshots/rep002.json",
      ),
      environment_snapshot_rep003: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/environment-snapshots/rep003.json",
      ),
      environment_snapshot_rep004: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/environment-snapshots/rep004.json",
      ),
      environment_snapshot_rep005: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/environment-snapshots/rep005.json",
      ),
      environment_snapshot_rep006: identity(
        "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline/environment-snapshots/rep006.json",
      ),
    };
    const preregistration = {
      schema_version: "p1-117-preregistration/v1",
      status: "FROZEN_BEFORE_SECRET_OR_PROVIDER",
      freeze_boundary: {
        secret_reads_before_freeze: 0,
        provider_requests_before_freeze: 0,
        mutation_after_freeze: "FORBIDDEN",
      },
      frozen_artifacts: artifactNames,
      canonical_authorities: Object.fromEntries(
        Object.entries(qualityPreregistration.canonical_authorities).map(
          ([name, binding]) => [name, identity(binding.path)],
        ),
      ),
      external_authorities: {
        ...Object.fromEntries(
          Object.entries(qualityPreregistration.external_authorities).map(
            ([name, binding]) => [name, absoluteIdentity(binding.path)],
          ),
        ),
        p1_117_task_authority: absoluteIdentity(
          "/Users/lijunpeng/Developer/.sourcelens-audit/p1-116-closed-profile-rollback-route-20260725/task-2/PHASE_DELEGATED_TASK_AUTHORITY.yaml",
        ),
      },
      executable_identity_boundary: "RECEIPT_REQUIRED_AFTER_IMPLEMENTATION_BEFORE_SECRET_OR_PROVIDER",
    };
    const preregistrationBytes = canonicalBytes(preregistration);
    writeExclusive(preregistrationPath, preregistrationBytes);
    const preregistrationBinding = {
      path: relative(REPOSITORY_ROOT, preregistrationPath).split(sep).join("/"),
      ...identityOf(preregistrationBytes),
    };
    const artifactsByPath = new Map();
    for (const entry of matrix.schedule) {
      artifactsByPath.set(entry.executable.path, entry.executable);
      artifactsByPath.set(entry.system_configuration.path, entry.system_configuration);
    }
    for (const path of [
      "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/runtime.mjs",
      "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/provider-client.mjs",
      "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/preflight.mjs",
      "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/local-execution.mjs",
      "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/scanner.mjs",
      "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/systems/common.mjs",
      "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/self-test.mjs",
      "evaluation-harness/recording/p1-117-clean-room-empirical-baseline/trace.mjs",
      "evaluation-harness/replay/p1-117-clean-room-empirical-baseline/replay.mjs",
    ]) {
      artifactsByPath.set(path, identity(path));
    }
    const receipt = {
      schema_version: "p1-117-executable-identity-freeze-receipt/v1",
      status: "FROZEN_BEFORE_SECRET_OR_PROVIDER",
      frozen_at: "1970-01-01T00:00:00.000Z",
      matrix_plan: matrixBinding,
      preregistration: preregistrationBinding,
      artifacts: [...artifactsByPath.values()]
        .sort((left, right) => left.path.localeCompare(right.path)),
      pre_freeze_effects: {
        secret_reads: 0,
        provider_requests: 0,
        network_connections: 0,
      },
    };
    const result = await offlinePreflight({
      preregistrationBinding,
      executableReceipt: receipt,
    });
    assert(
      result.status === "PASS"
        && result.schedule_count === 36
        && result.provider_requests === 0
        && result.secret_reads === 0,
      "full offline preflight did not PASS",
    );
  } finally {
    if (existsSync(preregistrationPath)) unlinkSync(preregistrationPath);
    rmdirSync(temporary);
  }
}

async function main() {
  const loaded = loadMatrix(REPOSITORY_ROOT);
  validateMatrix(REPOSITORY_ROOT, loaded.matrix);
  const compilerRuns = runCompilerMatrix(loaded.matrix);
  await buildRequestSelfTest(loaded.matrix);
  await allRequestBoundsSelfTest(loaded.matrix);
  b1TraceReplaySelfTest(loaded.matrix);
  b2TraceSchemaSelfTest(loaded.matrix);
  accountingCloseSelfTest();
  sessionClosureClaimSelfTest();
  manifestPopulationSelfTest(loaded.matrix);
  formalRuntimeReceiptCrossCheck(loaded.matrix);
  await fullOfflinePreflightSelfTest(loaded.matrix, loaded.binding);
  const secret = Buffer.from("self-test-secret", "utf8");
  let blocked = false;
  try {
    guardResponseBytesBeforeIdentity(
      Buffer.from("HTTP 500 echoed self-test-secret", "utf8"),
      secret,
    );
  } catch (error) {
    blocked = error instanceof SecretSinkForbidden
      && error.code === "SECRET_SINK_FORBIDDEN"
      && error.raw_response_identity_created === false
      && error.evidence_created === false;
  }
  assert(blocked, "Secret-derived response identity guard did not fail closed");
  process.stdout.write(`${JSON.stringify({
    status: "PASS",
    compiler_operation_runs: compilerRuns,
    matrix_runs: loaded.matrix.schedule.length,
    provider_requests: 0,
    secret_reads: 0,
  })}\n`);
}

await main();

#!/usr/bin/env node

import {
  closeSync,
  constants,
  existsSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

import {
  canonicalBytes,
  sha256,
} from "../p1-097-minimal-documented/core.mjs";
import {
  identityOf,
  parseCanonicalJson,
  parseFrozenJson,
  readBoundFile,
} from "../../validators/p1-117-clean-room-empirical-baseline/core.mjs";
import {
  loadSafeDisclosure,
  validateProviderResponse,
} from "../../validators/p1-117-clean-room-empirical-baseline/disclosure.mjs";
import {
  AppendOnlyAccountingLedger,
  FormalProviderSession,
  conservativeInputTokenUpperBound,
  executeLoopbackChatCompletion,
} from "./provider-client.mjs";
import {
  REPOSITORY_ROOT,
  offlinePreflight,
} from "./preflight.mjs";
import {
  abandonLocalRunContext,
  applyEvaluateAndRollback,
  createLocalRunContext,
} from "./local-execution.mjs";
import {
  invokeAcceptedScanner,
  prepareAcceptedScanner,
} from "./scanner.mjs";
import {
  buildTrace,
} from "../../recording/p1-117-clean-room-empirical-baseline/trace.mjs";
import {
  buildStableProjection,
  replayExact,
} from "../../replay/p1-117-clean-room-empirical-baseline/replay.mjs";

const CAPS = Object.freeze({
  provider_requests_max: 60,
  automatic_retry_max: 0,
  input_tokens_max: 500000,
  output_tokens_max: 100000,
  currency: "USD",
  max_spend: 25,
});
const RESPONSE_REASONS = new Set([
  "PROVIDER_RESPONSE_SCHEMA_INVALID",
  "PROVIDER_RESPONSE_NOT_CANONICAL",
  "UNKNOWN_OPERATION_ID",
  "PROVIDER_HTTP_NON_PASS",
  "PROVIDER_TIMEOUT",
  "PROVIDER_TRANSPORT_ERROR",
  "PROVIDER_USAGE_INVALID",
]);

function assert(condition, code, message) {
  if (!condition) {
    const error = new Error(message);
    error.code = code;
    throw error;
  }
}

export function summarizeRunManifestPopulation(records) {
  assert(
    Array.isArray(records)
      && records.length === 36
      && new Set(records.map((record) => record.run_id)).size === 36
      && records.every((record) => (
        record !== null
        && typeof record === "object"
        && Object.keys(record).sort().join(",") === "byte_length,run_id,sha256"
        && typeof record.run_id === "string"
        && /^[0-9a-f]{64}$/.test(record.sha256)
        && Number.isSafeInteger(record.byte_length)
        && record.byte_length > 0
      )),
    "RUN_MANIFEST_POPULATION_INVALID",
    "run-manifest population must be 36 ordered exact identities",
  );
  const bytes = canonicalBytes(records);
  return {
    count: records.length,
    aggregate_sha256: sha256(bytes),
    aggregate_byte_length: bytes.length,
  };
}

function createDirectoryOnce(path) {
  const parent = dirname(path);
  const parentStat = lstatSync(parent);
  assert(
    parentStat.isDirectory()
      && !parentStat.isSymbolicLink()
      && realpathSync(parent) === parent,
    "OUTPUT_PARENT_INVALID",
    `output parent is invalid: ${parent}`,
  );
  assert(!existsSync(path), "OUTPUT_ROOT_PREEXISTS", `output path preexists: ${path}`);
  mkdirSync(path, { mode: 0o700, recursive: false });
  assert(realpathSync(path) === path, "OUTPUT_ROOT_INVALID", `output root is invalid: ${path}`);
}

function writeCreateOnce(path, bytes) {
  const descriptor = openSync(
    path,
    constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | (constants.O_NOFOLLOW ?? 0),
    0o600,
  );
  try {
    writeFileSync(descriptor, bytes);
  } finally {
    closeSync(descriptor);
  }
  const stat = lstatSync(path);
  assert(
    stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
    "EVIDENCE_CREATE_INVALID",
    `Evidence output is not an owned regular file: ${path}`,
  );
  return {
    relative_path: path.slice(dirname(path).length + 1),
    sha256: sha256(bytes),
    byte_length: bytes.length,
  };
}

function writeRunEvidence(runRoot, filename, bytes) {
  const path = join(runRoot, filename);
  const binding = writeCreateOnce(path, bytes);
  return {
    relative_path: filename,
    sha256: binding.sha256,
    byte_length: binding.byte_length,
  };
}

function responseSafeRejection(reasonCode, identity) {
  assert(RESPONSE_REASONS.has(reasonCode), "RESPONSE_REASON_INVALID", reasonCode);
  return canonicalBytes({
    schema_version: "p1-117-provider-response-safe-rejection/v1",
    status: "REJECTED",
    reason_code: reasonCode,
    raw_response_sha256: identity.sha256,
    raw_response_byte_length: identity.byte_length,
    raw_response_retained: false,
  });
}

function classifyProviderSelection(providerResult, allowedOperationIds) {
  if (!providerResult.accepted_transport_wrapper) {
    return {
      selected_operation_id: null,
      reason_code: providerResult.reason_code,
      outcome: "REJECTED",
      response_safe_bytes: providerResult.response_safe_rejection_bytes,
    };
  }
  const content = providerResult.response_content_bytes;
  try {
    const selection = validateProviderResponse(content, allowedOperationIds);
    return {
      selected_operation_id: selection.selected_operation_id,
      reason_code: null,
      outcome: "ACCEPTED",
      response_safe_bytes: content,
    };
  } catch (error) {
    const reasonCode = RESPONSE_REASONS.has(error.reasonCode)
      ? error.reasonCode
      : "PROVIDER_RESPONSE_SCHEMA_INVALID";
    return {
      selected_operation_id: null,
      reason_code: reasonCode,
      outcome: "REJECTED",
      response_safe_bytes: responseSafeRejection(reasonCode, {
        sha256: sha256(content),
        byte_length: content.length,
      }),
    };
  }
}

function testReceipt(entry, selectedOperationId, execution) {
  return {
    schema_version: "p1-117-test-receipt/v1",
    run_id: entry.run_id,
    trusted_compiler_operation_id: selectedOperationId,
    issue_specific: {
      exit_status: execution.issue_specific?.exit_status ?? null,
      passed: execution.issue_specific?.passed ?? false,
      stdout_sha256: execution.issue_specific?.stdout_sha256 ?? null,
      stderr_sha256: execution.issue_specific?.stderr_sha256 ?? null,
    },
    regression: {
      exit_status: execution.regression?.exit_status ?? null,
      passed: execution.regression?.passed ?? false,
      stdout_sha256: execution.regression?.stdout_sha256 ?? null,
      stderr_sha256: execution.regression?.stderr_sha256 ?? null,
    },
    compiler: execution.compiler,
    b1_local_tool_ledger: execution.b1_operations,
    ordinary_failure: execution.ordinary_failure,
    policy_violations: [],
  };
}

function terminalOutcome(providerSelection, execution) {
  if (providerSelection.outcome !== "ACCEPTED") {
    return {
      status: "FAILED",
      reason_code: providerSelection.reason_code,
      invalid_run_reason: null,
      post_hoc_excluded: false,
    };
  }
  if (execution.ordinary_failure !== null) {
    return {
      status: "ERROR",
      reason_code: execution.ordinary_failure.reason_code,
      invalid_run_reason: null,
      post_hoc_excluded: false,
    };
  }
  if (!execution.tests_pass) {
    return {
      status: "FAILED",
      reason_code: "INDEPENDENT_TEST_NON_PASS",
      invalid_run_reason: null,
      post_hoc_excluded: false,
    };
  }
  return {
    status: "COMPLETED",
    reason_code: "TESTS_PASS_PENDING_INDEPENDENT_ORACLE",
    invalid_run_reason: null,
    post_hoc_excluded: false,
  };
}

function buildRunRecord({
  entry,
  selectedOperationId,
  terminal,
  providerResult,
  execution,
}) {
  return {
    schema_version: "1.0",
    run_id: entry.run_id,
    task_id: entry.task_id,
    adapter_id: entry.system,
    repetition_id: entry.repetition_id,
    terminal_status: terminal.status,
    terminal_reason: terminal.reason_code,
    selected_operation_id: selectedOperationId,
    provider: {
      request_count: 1,
      successful_loopback_connections: providerResult.successful_loopback_connections,
      automatic_retries: 0,
      status_code: providerResult.status_code,
      raw_response_identity: providerResult.raw_response_identity,
    },
    verification: {
      issue_specific_exit_status: execution.issue_specific?.exit_status ?? null,
      regression_exit_status: execution.regression?.exit_status ?? null,
    },
    policy_violations: [],
  };
}

function externalTruthBinding(entry, materializationBinding, scannerInvocation) {
  return {
    schema_version: "p1-117-external-truth-binding/v1",
    status: "PASS",
    run_id: entry.run_id,
    task_spec: entry.task_spec,
    environment_snapshot: materializationBinding.environment_snapshot,
    dataset_task_binding: materializationBinding.dataset_task_binding,
    source_template_binding: materializationBinding.source_template_binding,
    source_template_manifest: materializationBinding.source_template_manifest,
    executable: entry.executable,
    system_configuration: entry.system_configuration,
    accepted_scanner_binding: entry.accepted_scanner_binding,
    b2_scanner_command_ledger: scannerInvocation?.command_ledger ?? null,
  };
}

async function executeRun({
  entry,
  taskBinding,
  matrix,
  artifactRoot,
  providerSession,
  accountingLedger,
  preparedScanner,
}) {
  const runRoot = join(artifactRoot, entry.run_id);
  createDirectoryOnce(runRoot);
  const configurationFile = readBoundFile(
    REPOSITORY_ROOT,
    entry.system_configuration,
    "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
  );
  const configuration = parseFrozenJson(
    configurationFile.bytes,
    "SYSTEM_CONFIGURATION_SCHEMA_INVALID",
  );
  const safe = loadSafeDisclosure(REPOSITORY_ROOT, matrix, entry);
  const context = createLocalRunContext({ entry, taskBinding, runRoot });
  let scannerInvocation = null;
  let requestSafe;
  let providerResult;
  let observedInput;
  let observedOutput;
  let selection;
  let responseSafe;
  let execution;
  try {
    if (entry.system === "B2") {
      scannerInvocation = invokeAcceptedScanner({
        preparedScanner,
        sourceRoot: context.sourceRoot,
        runId: entry.run_id,
      });
    }
    const wrapper = await import(
      pathToFileURL(resolve(REPOSITORY_ROOT, entry.executable.path)).href
    );
    const builtRequest = wrapper.buildProviderRequest({
      entry,
      configuration,
      disclosure: safe.disclosure,
      responseSchemaIdentity: matrix.response_schema,
      scannerObservation: scannerInvocation?.provider_safe_observation ?? null,
    });
    const computedInputBound = conservativeInputTokenUpperBound(
      builtRequest.bytes,
    );
    assert(
      computedInputBound.tokens <= configuration.input_tokens_reserved,
      "PROVIDER_CAP_WOULD_BE_EXCEEDED",
      `request input bound exceeds the frozen reservation for ${entry.run_id}`,
    );
    requestSafe = writeRunEvidence(runRoot, "request-safe.json", builtRequest.bytes);
    accountingLedger.reserve(entry.run_id, {
      inputTokenBound: configuration.input_tokens_reserved,
      inputTokenBoundMethod: "QUALITY_FROZEN_PER_RUN_RESERVATION",
      outputTokenBound: configuration.max_output_tokens,
    });
    providerResult = await executeLoopbackChatCompletion({
      requestBytes: builtRequest.bytes,
      session: providerSession,
    });
    observedInput = providerResult.usage.prompt_tokens ?? 0;
    observedOutput = providerResult.usage.completion_tokens ?? 0;
    assert(
      Number.isSafeInteger(observedInput)
        && observedInput >= 0
        && observedInput <= configuration.input_tokens_reserved
        && Number.isSafeInteger(observedOutput)
        && observedOutput >= 0
        && observedOutput <= configuration.max_output_tokens,
      "PROVIDER_CAP_EXCEEDED",
      `Provider usage exceeded the per-run reservation for ${entry.run_id}`,
    );
    accountingLedger.observe(entry.run_id, providerResult);
    selection = classifyProviderSelection(providerResult, entry.finite_operation_ids);
    responseSafe = writeRunEvidence(
      runRoot,
      "response-safe.json",
      selection.response_safe_bytes,
    );
    execution = applyEvaluateAndRollback(context, selection.selected_operation_id);
  } catch (error) {
    if (existsSync(context.tree.root)) {
      try {
        abandonLocalRunContext(context);
      } catch (cleanupError) {
        error.owned_cleanup_failure = cleanupError.code
          ?? cleanupError.reasonCode
          ?? cleanupError.message;
      }
    }
    throw error;
  }
  const tests = testReceipt(entry, selection.selected_operation_id, execution);
  const terminal = terminalOutcome(selection, execution);
  const rollback = {
    schema_version: "p1-117-rollback-receipt/v1",
    status: execution.rollback.exact === true ? "PASS_EXACT" : "NON_PASS",
    run_id: entry.run_id,
    source_state_restored: execution.rollback.source_state_restored === true,
    nonowned_paths_touched: execution.rollback.nonowned_paths_touched,
    removed_object_count: execution.rollback.removed_object_count,
    root_final_state: execution.rollback.root_final_state,
    cleanup_receipt_sha256: sha256(canonicalBytes(execution.rollback)),
  };
  assert(
    rollback.status === "PASS_EXACT"
      && rollback.source_state_restored
      && rollback.nonowned_paths_touched === 0,
    "ROLLBACK_IDENTITY_MISMATCH",
    `exact rollback failed for ${entry.run_id}`,
  );
  const truth = externalTruthBinding(
    entry,
    context.materialization_binding,
    scannerInvocation,
  );
  const runRecord = buildRunRecord({
    entry,
    selectedOperationId: selection.selected_operation_id,
    terminal,
    providerResult,
    execution,
  });
  const traceBytes = buildTrace({
    entry,
    admission: { request_safe_identity: requestSafe },
    materialization: context.materialization_binding,
    selectedOperationId: selection.selected_operation_id,
    scannerCommand: scannerInvocation === null
      ? null
      : {
          command_ledger_sha256: sha256(canonicalBytes(scannerInvocation.command_ledger)),
          scanner_pre_call_identity: scannerInvocation.scanner_pre_call_identity,
        },
    tests,
    terminal,
    rollback,
  });
  const projectionInputs = {
    selectedOperationId: selection.selected_operation_id,
    responseOutcome: {
      status: selection.outcome,
      reason_code: selection.reason_code,
    },
    tests,
    terminal,
    externalTruthBinding: truth,
  };
  const stableProjection = buildStableProjection({ entry, ...projectionInputs });
  const replay = replayExact({
    entry,
    traceBytes,
    stableProjectionBytes: stableProjection,
    projectionInputs,
  });
  const evidenceBytes = {
    run_record: canonicalBytes(runRecord),
    trace: traceBytes,
    external_truth_binding: canonicalBytes(truth),
    stable_projection: stableProjection,
    replay_receipt: canonicalBytes(replay),
    rollback_receipt: canonicalBytes(rollback),
    test_receipt: canonicalBytes(tests),
  };
  const evidence = {
    request_safe: requestSafe,
    response_safe: responseSafe,
  };
  for (const [role, bytes] of Object.entries(evidenceBytes)) {
    evidence[role] = writeRunEvidence(runRoot, `${role.replaceAll("_", "-")}.json`, bytes);
  }
  const manifest = {
    schema_version: "p1-117-run-manifest/v1",
    entry: {
      slot: entry.slot,
      entry_id: entry.entry_id,
      run_id: entry.run_id,
      task_id: entry.task_id,
      system: entry.system,
      variant: entry.variant,
      repetition_id: entry.repetition_id,
    },
    terminal,
    selected_operation_id: selection.selected_operation_id,
    evidence,
    accounting: {
      provider_requests: 1,
      automatic_retries: 0,
      input_tokens: observedInput,
      output_tokens: observedOutput,
      latency_ms: providerResult.latency_ms,
      cost: {
        status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
        currency: "USD",
        amount: null,
      },
      successful_loopback_connections: providerResult.successful_loopback_connections,
    },
    observed_effects: {
      non_loopback_network_connections: 0,
      remote: false,
      production: false,
      public: false,
      restricted_source_egress: false,
      secret_sink_writes: 0,
    },
  };
  const manifestBytes = canonicalBytes(manifest);
  writeCreateOnce(join(runRoot, "run-manifest.json"), manifestBytes);
  return {
    run_id: entry.run_id,
    sha256: sha256(manifestBytes),
    byte_length: manifestBytes.length,
  };
}

export async function runFormalBaseline({
  artifactRoot,
  preregistrationBinding,
  executableReceipt,
  transientSecretSource,
}) {
  assert(
    typeof artifactRoot === "string"
      && isAbsolute(artifactRoot)
      && resolve(artifactRoot) === artifactRoot,
    "OUTPUT_ROOT_INVALID",
    "formal artifact root must be an absolute normalized path",
  );
  const preflight = await offlinePreflight({
    preregistrationBinding,
    executableReceipt,
  });
  createDirectoryOnce(artifactRoot);
  const {
    matrix: preflightMatrix,
    formal_contract: preflightFormalContract,
    ...persistablePreflight
  } = preflight;
  writeCreateOnce(
    join(artifactRoot, "offline-preflight-receipt.json"),
    canonicalBytes(persistablePreflight),
  );
  const scannerRoot = join(artifactRoot, "accepted-scanner");
  const preparedScanner = prepareAcceptedScanner({
    bindingReference: preflightMatrix.accepted_scanner_binding,
    outputRoot: scannerRoot,
  });
  const ledger = AppendOnlyAccountingLedger.create(
    join(artifactRoot, "accounting-ledger.jsonl"),
    CAPS,
  );
  let session = null;
  let sessionClosure = null;
  const manifests = [];
  try {
    session = FormalProviderSession.open({
      transientSecretSource,
      preflightReceipt: preflight,
    });
    for (const entry of preflightMatrix.schedule) {
      const taskBinding = preflightMatrix.task_bindings.find(
        (candidate) => candidate.task_id === entry.task_id,
      );
      assert(
        taskBinding !== undefined,
        "TASK_ENVIRONMENT_BINDING_INVALID",
        `missing task binding for ${entry.task_id}`,
      );
      manifests.push(await executeRun({
        entry,
        taskBinding,
        matrix: preflightMatrix,
        artifactRoot,
        providerSession: session,
        accountingLedger: ledger,
        preparedScanner,
      }));
    }
  } finally {
    try {
      sessionClosure = session?.close() ?? null;
    } finally {
      ledger.close();
    }
  }
  assert(
    manifests.length === 36
      && session.status === "CLOSED"
      && sessionClosure?.provider_session_closed === true
      && sessionClosure?.owned_secret_buffer_overwrite_attempted === true
      && sessionClosure?.whole_process_memory_zeroization_claim === "NOT_CLAIMED",
    "FORMAL_RUN_INCOMPLETE",
    "formal run did not complete all 36 scheduled entries",
  );
  const accountingLedgerBytes = readFileSync(ledger.path);
  const manifestPopulation = summarizeRunManifestPopulation(manifests);
  const receipt = {
    schema_version: "p1-117-formal-runtime-receipt/v1",
    status: "COMPLETE",
    scheduled_runs: 36,
    completed_run_manifests: manifests.length,
    provider_requests: ledger.totals.provider_requests_accounted,
    automatic_retries: ledger.totals.automatic_retries,
    secret_reads: 1,
    accounting_ledger: {
      sha256: sha256(accountingLedgerBytes),
      byte_length: accountingLedgerBytes.length,
    },
    run_manifest_population: manifestPopulation,
    provider_session_closed: sessionClosure.provider_session_closed,
    owned_secret_buffer_overwrite_attempted:
      sessionClosure.owned_secret_buffer_overwrite_attempted,
    whole_process_memory_zeroization_claim:
      sessionClosure.whole_process_memory_zeroization_claim,
    cost: {
      status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
      currency: "USD",
      amount: null,
    },
  };
  writeCreateOnce(join(artifactRoot, "formal-runtime-receipt.json"), canonicalBytes(receipt));
  return receipt;
}

function parseCli(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(
      [
        "--artifact-root",
        "--preregistration",
        "--executable-receipt",
        "--secret-env",
        "--secret-file",
      ].includes(key)
        && typeof value === "string"
        && !Object.hasOwn(values, key),
      "CLI_ARGUMENT_MISMATCH",
      "runtime arguments are invalid",
    );
    values[key] = value;
  }
  assert(
    values["--artifact-root"]
      && values["--preregistration"]
      && values["--executable-receipt"]
      && Boolean(values["--secret-env"]) !== Boolean(values["--secret-file"]),
    "CLI_ARGUMENT_MISMATCH",
    "runtime requires artifact root, preregistration, executable receipt, and one Secret source",
  );
  return values;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const args = parseCli(process.argv.slice(2));
    const preregistrationPath = resolve(args["--preregistration"]);
    const preregistrationBytes = readFileSync(preregistrationPath);
    const rel = relative(REPOSITORY_ROOT, preregistrationPath).split(sep).join("/");
    const executableReceipt = parseCanonicalJson(
      readFileSync(resolve(args["--executable-receipt"])),
      "EXECUTABLE_FREEZE_RECEIPT_INVALID",
    );
    const receipt = await runFormalBaseline({
      artifactRoot: resolve(args["--artifact-root"]),
      preregistrationBinding: {
        path: rel,
        ...identityOf(preregistrationBytes),
      },
      executableReceipt,
      transientSecretSource: args["--secret-env"]
        ? { kind: "LOCAL_PROCESS_ENV", env_name: args["--secret-env"] }
        : { kind: "CONTROLLED_TEMPORARY_SECRET_FILE", path: resolve(args["--secret-file"]) },
    });
    process.stdout.write(`${JSON.stringify(receipt)}\n`);
  } catch (error) {
    process.stdout.write(`${JSON.stringify({
      status: "NON_PASS",
      reason_code: error.code ?? error.reasonCode ?? "UNEXPECTED_RUNTIME_ERROR",
    })}\n`);
    process.exitCode = 2;
  }
}

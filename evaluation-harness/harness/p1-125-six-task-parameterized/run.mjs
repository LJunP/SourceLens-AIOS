#!/usr/bin/env node

import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ConformanceNonPass,
  FALSE_EXTERNAL_EFFECTS,
  assert,
  canonicalBytes,
  canonicalJson,
  createOwnedOutputRoot,
  executeBoundedCommand,
  parseJsonBytes,
  sha256,
  writeOwnedBytesCreateOnce,
  writeOwnedJsonCreateOnce,
} from "./core.mjs";
import {
  REPOSITORY_ROOT,
  loadAndPreflight,
} from "./contracts.mjs";
import {
  assertAdapterResultShape,
  buildRunRecord,
  buildTrace,
  identityFor,
  traceIdentityFor,
} from "../../recording/p1-125-six-task-parameterized/records.mjs";
import {
  buildStableProjection,
  projectionIdentity,
} from "../../replay/p1-125-six-task-parameterized/project.mjs";

const RESULT_KEYS = Object.freeze([
  "schema_version",
  "request_id",
  "case_id",
  "status",
  "reason_code",
  "target_execution_count",
  "output_root_created",
  "run_record_ref",
  "stable_projection_ref",
  "trace_ref",
  "external_effects",
  "cleanup",
]);

const INTERNAL_REASON_MAP = Object.freeze({
  INVALID_JSON: "SCHEMA_INVALID",
  INVALID_RECORD_SHAPE: "SCHEMA_INVALID",
  PATH_NOT_ABSOLUTE: "SCHEMA_INVALID",
  PATH_MISSING: "INPUT_IDENTITY_MISMATCH",
  PATH_ESCAPE_REJECTED: "INPUT_IDENTITY_MISMATCH",
  SYMLINK_REJECTED: "INPUT_IDENTITY_MISMATCH",
  IDENTITY_INVALID: "INPUT_IDENTITY_MISMATCH",
  IDENTITY_MISMATCH: "INPUT_IDENTITY_MISMATCH",
  EXTERNAL_EFFECT_REQUEST_REJECTED: "EXTERNAL_EFFECT_FORBIDDEN",
  OUTPUT_ROOT_PREEXISTS: "OUTPUT_ROOT_INVALID",
  OUTPUT_ROOT_PARENT_DRIFT: "OUTPUT_ROOT_INVALID",
  OUTPUT_ROOT_CREATE_FAILED: "OUTPUT_ROOT_INVALID",
  NON_OWNED_ROOT_REJECTED: "OUTPUT_ROOT_INVALID",
  CREATE_ONCE_WRITE_FAILED: "ARTIFACT_IDENTITY_MISMATCH",
  MALFORMED_ARGV_REJECTED: "COMMAND_CONTRACT_INVALID",
  WORKING_DIRECTORY_REJECTED: "COMMAND_CONTRACT_INVALID",
  EXPECTED_EXIT_CONTRACT_REJECTED: "COMMAND_CONTRACT_INVALID",
  ENVIRONMENT_CONTRACT_REJECTED: "COMMAND_CONTRACT_INVALID",
  TIMEOUT_CONTRACT_REJECTED: "LIMIT_CONTRACT_INVALID",
  CAPTURE_LIMIT_EXCEEDED: "LIMIT_CONTRACT_INVALID",
  EXECUTABLE_REJECTED: "EXECUTABLE_INVALID",
});

function parseCli(argv) {
  assert(
    argv.length === 4
      && argv[0] === "--request"
      && argv[2] === "--output-root"
      && isAbsolute(argv[1])
      && resolve(argv[1]) === argv[1]
      && isAbsolute(argv[3])
      && resolve(argv[3]) === argv[3],
    "SCHEMA_INVALID",
    "Usage: run.mjs --request ABSOLUTE_REGULAR_JSON --output-root ABSENT_ABSOLUTE_PATH",
  );
  return { requestPath: argv[1], outputRoot: argv[3] };
}

function bestEffortRequestIdentity(requestPath) {
  const fallback = { request_id: "UNKNOWN", case_id: "UNKNOWN" };
  if (typeof requestPath !== "string" || !isAbsolute(requestPath)) return fallback;
  try {
    const value = JSON.parse(readFileSync(requestPath, "utf8"));
    return {
      request_id: typeof value.request_id === "string" && value.request_id.length > 0
        ? value.request_id
        : fallback.request_id,
      case_id: typeof value.case_id === "string" && value.case_id.length > 0
        ? value.case_id
        : fallback.case_id,
    };
  } catch {
    return fallback;
  }
}

function targetExecutionCount(sentinelPath) {
  if (typeof sentinelPath !== "string" || !isAbsolute(sentinelPath) || !existsSync(sentinelPath)) {
    return 0;
  }
  try {
    const stat = lstatSync(sentinelPath);
    return stat.isFile() && !stat.isSymbolicLink() && stat.size > 0 ? 1 : 0;
  } catch {
    return 0;
  }
}

function resultRecord({
  identity,
  status,
  reasonCode,
  targetCount,
  outputRootCreated,
  runRecordRef = null,
  stableProjectionRef = null,
  traceRef = null,
}) {
  const result = {
    schema_version: "p1-125-worker-result/v1",
    request_id: identity.request_id,
    case_id: identity.case_id,
    status,
    reason_code: reasonCode,
    target_execution_count: targetCount,
    output_root_created: outputRootCreated,
    run_record_ref: runRecordRef,
    stable_projection_ref: stableProjectionRef,
    trace_ref: traceRef,
    external_effects: FALSE_EXTERNAL_EFFECTS,
    cleanup: {
      owned_paths_removed: 0,
      nonowned_paths_touched: 0,
    },
  };
  assert(
    canonicalJson(Object.keys(result).sort()) === canonicalJson([...RESULT_KEYS].sort()),
    "INVALID_RECORD_SHAPE",
    "worker result key set drifted",
  );
  return result;
}

function reasonCode(error) {
  const code = error instanceof ConformanceNonPass
    ? error.code
    : (typeof error?.code === "string" ? error.code : "UNCAUGHT_EXCEPTION");
  return INTERNAL_REASON_MAP[code] ?? code;
}

function absoluteIdentity(root, identity) {
  return {
    path: resolve(root, identity.path),
    sha256: identity.sha256,
    byte_length: identity.byte_length,
  };
}

function boundInput(record) {
  return {
    path: record.path,
    sha256: sha256(record.bytes),
    byte_length: record.bytes.length,
  };
}

function buildAdapterExecutionRequest(contracts, outputRoot, sentinelPath) {
  return {
    schema_version: "1.0",
    record_type: "p1_125_adapter_execution_request",
    run_id: `${contracts.request.request_id}:${contracts.request.adapter_id}:${contracts.request.repetition_id}`,
    adapter_id: contracts.request.adapter_id,
    repetition_id: contracts.request.repetition_id,
    task_spec: boundInput(contracts.task),
    environment_snapshot: boundInput(contracts.environment),
    system_configuration: boundInput(contracts.configuration),
    adapter_input: boundInput(contracts.adapterInput),
    auxiliary_inputs: Object.fromEntries(
      Object.entries(contracts.auxiliaryInputs).map(([name, record]) => [name, boundInput(record)]),
    ),
    run_root: outputRoot,
    sentinel_path: sentinelPath,
    limits: {
      wall_clock_seconds: contracts.descriptor.timeout_seconds,
      max_model_tokens: contracts.descriptor.limits.max_model_tokens,
      max_tool_calls: contracts.descriptor.limits.max_tool_calls,
      max_cost_usd: contracts.descriptor.limits.max_cost_usd,
    },
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

function parseCanonicalTargetOutput(stdout) {
  assert(
    stdout.length > 0
      && stdout.at(-1) === 0x0a
      && !stdout.subarray(0, stdout.length - 1).includes(0x0a),
    "OUTPUT_SET_INVALID",
    "adapter stdout must be exactly one JSON line",
  );
  const value = parseJsonBytes(stdout, "adapter stdout");
  assert(
    stdout.equals(canonicalBytes(value)),
    "OUTPUT_SET_INVALID",
    "adapter stdout is not canonical JSON",
  );
  return value;
}

function assertSentinel(contracts, sentinelPath, adapterResult) {
  assert(existsSync(sentinelPath), "RUN_RECORD_BINDING_INVALID", "target sentinel was not created");
  const stat = lstatSync(sentinelPath);
  assert(
    stat.isFile() && !stat.isSymbolicLink() && stat.size > 0,
    "RUN_RECORD_BINDING_INVALID",
    "target sentinel is not a non-empty regular file",
  );
  const bytes = readFileSync(sentinelPath);
  assert(
    adapterResult.target_execution_sentinel.sha256 === sha256(bytes)
      && adapterResult.target_execution_sentinel.byte_length === bytes.length
      && targetExecutionCount(contracts.request.target_sentinel_path) === 1,
    "RUN_RECORD_BINDING_INVALID",
    "target sentinel identity differs from the adapter result",
  );
}

function assertDeclaredOutputSet(root, adapterId) {
  const allowedTopLevel = new Set([
    "adapter-execution-request.json",
    "adapter-command-ledger.json",
    "adapter-result.json",
    "target-executed",
    "trace.jsonl",
    "run-record.json",
    "stable-projection.json",
  ]);
  if (adapterId !== "B0") allowedTopLevel.add("work");
  const observed = readdirSync(root, { withFileTypes: true });
  assert(
    observed.every((entry) => allowedTopLevel.has(entry.name))
      && observed.every((entry) => (
        entry.name === "work"
          ? entry.isDirectory() && !entry.isSymbolicLink()
          : entry.isFile() && !entry.isSymbolicLink()
      )),
    "OUTPUT_SET_INVALID",
    "adapter output root contains an undeclared top-level entry",
  );
}

async function executePositive(contracts, outputRootPath) {
  const ownedRoot = createOwnedOutputRoot(outputRootPath);
  const root = ownedRoot.root;
  const sentinelPath = contracts.request.target_sentinel_path;
  const executionRequest = buildAdapterExecutionRequest(contracts, root, sentinelPath);
  const executionRequestRef = writeOwnedJsonCreateOnce(
    ownedRoot,
    "adapter-execution-request.json",
    executionRequest,
  );
  const executionRequestPath = resolve(root, executionRequestRef.path);
  const nodeExecutable = resolve(process.execPath);
  const command = await executeBoundedCommand({
    argv: [
      nodeExecutable,
      contracts.executable,
      "--request",
      executionRequestPath,
      "--run-root",
      root,
      "--sentinel",
      sentinelPath,
    ],
    cwd: REPOSITORY_ROOT,
    timeoutSeconds: contracts.descriptor.timeout_seconds,
    expectedExitCodes: contracts.descriptor.expected_exit_codes,
    environment: {
      HOME: process.env.HOME ?? "",
      PATH: "/usr/local/bin:/usr/bin:/bin",
    },
  });

  writeOwnedJsonCreateOnce(ownedRoot, "adapter-command-ledger.json", command.ledger);
  if (!command.ledger.expected_exit_matched && command.stdout.length > 0) {
    const rejected = parseCanonicalTargetOutput(command.stdout);
    if (
      rejected !== null
        && typeof rejected === "object"
        && rejected.verdict === "NON_PASS"
        && typeof rejected.reason_code === "string"
        && rejected.reason_code.length > 0
    ) {
      throw new ConformanceNonPass(
        rejected.reason_code,
        "adapter rejected the bound target before producing accepted output",
      );
    }
  }
  assert(
    command.ledger.expected_exit_matched
      && command.ledger.exit_status === 0
      && command.ledger.timed_out === false
      && command.ledger.signal === null
      && command.stderr.length === 0,
    "COMMAND_CONTRACT_INVALID",
    "adapter command did not satisfy the finite expected-exit contract",
  );

  const adapterResult = parseCanonicalTargetOutput(command.stdout);
  assertAdapterResultShape(adapterResult, contracts);
  assertSentinel(contracts, sentinelPath, adapterResult);
  const adapterResultRecord = identityFor("adapter-result.json", adapterResult);
  writeOwnedBytesCreateOnce(ownedRoot, adapterResultRecord.identity.path, adapterResultRecord.bytes);

  const traceEvents = buildTrace({
    contracts,
    commandLedger: command.ledger,
    adapterResult,
    adapterResultIdentity: adapterResultRecord.identity,
  });
  const traceRecord = traceIdentityFor("trace.jsonl", traceEvents);
  writeOwnedBytesCreateOnce(ownedRoot, traceRecord.identity.path, traceRecord.bytes);

  const runRecord = buildRunRecord({
    contracts,
    commandLedger: command.ledger,
    adapterResult,
    traceIdentity: traceRecord.identity,
    adapterResultIdentity: adapterResultRecord.identity,
  });
  const runRecordValue = identityFor("run-record.json", runRecord);
  writeOwnedBytesCreateOnce(ownedRoot, runRecordValue.identity.path, runRecordValue.bytes);

  const stableProjection = buildStableProjection({ runRecord, adapterResult });
  const stableProjectionValue = projectionIdentity(stableProjection);
  const stableProjectionRef = {
    path: "stable-projection.json",
    sha256: stableProjectionValue.sha256,
    byte_length: stableProjectionValue.byte_length,
  };
  writeOwnedBytesCreateOnce(ownedRoot, stableProjectionRef.path, stableProjectionValue.bytes);
  assertDeclaredOutputSet(root, contracts.request.adapter_id);

  return {
    root,
    targetCount: 1,
    runRecordRef: absoluteIdentity(root, runRecordValue.identity),
    stableProjectionRef: absoluteIdentity(root, stableProjectionRef),
    traceRef: absoluteIdentity(root, traceRecord.identity),
  };
}

async function main() {
  let cli = { requestPath: null, outputRoot: null };
  let identity = { request_id: "UNKNOWN", case_id: "UNKNOWN" };
  let sentinelPath = null;
  let outputRootCreated = false;
  try {
    cli = parseCli(process.argv.slice(2));
    identity = bestEffortRequestIdentity(cli.requestPath);
    const contracts = loadAndPreflight(cli.requestPath, cli.outputRoot);
    identity = {
      request_id: contracts.request.request_id,
      case_id: contracts.request.case_id,
    };
    sentinelPath = contracts.request.target_sentinel_path;
    const completed = await executePositive(contracts, cli.outputRoot);
    outputRootCreated = true;
    process.stdout.write(`${canonicalJson(resultRecord({
      identity,
      status: "PASS",
      reasonCode: "PASS",
      targetCount: completed.targetCount,
      outputRootCreated: true,
      runRecordRef: completed.runRecordRef,
      stableProjectionRef: completed.stableProjectionRef,
      traceRef: completed.traceRef,
    }))}\n`);
  } catch (error) {
    if (cli.outputRoot && existsSync(cli.outputRoot)) {
      try {
        outputRootCreated = lstatSync(cli.outputRoot).isDirectory()
          && !lstatSync(cli.outputRoot).isSymbolicLink();
      } catch {
        outputRootCreated = false;
      }
    }
    process.stdout.write(`${canonicalJson(resultRecord({
      identity,
      status: "REJECTED",
      reasonCode: reasonCode(error),
      targetCount: targetExecutionCount(sentinelPath),
      outputRootCreated,
    }))}\n`);
    process.exitCode = 2;
  }
}

await main();

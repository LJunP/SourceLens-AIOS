import { spawnSync } from "node:child_process";
import {
  existsSync,
  readFileSync,
  unlinkSync,
} from "node:fs";
import { join } from "node:path";

import {
  MAX_COMMAND_OUTPUT_BYTES,
  REPOSITORY_ROOT,
  FALSE_EXTERNAL_EFFECTS,
  applyFileBytesAtomic,
  assert,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  cleanupOwnedRoot,
  containedPath,
  copyClosedTree,
  createDisposableRoot,
  directorySnapshot,
  exactKeys,
  safeRegularFile,
  sha256,
} from "./core.mjs";
import {
  loadAcceptedTask,
  loadAcceptedCompilerProfile,
} from "./accepted-inputs.mjs";
import {
  COMPILER_VERSION,
  compileNormalizedProviderResponse,
} from "./patch-ir-v2.mjs";
import {
  artifactIdentity,
  buildObservableTrace,
  buildStableProjection,
  projectionBytes,
} from "../../recording/p1-101-accepted-shared-trace/trace.mjs";
import {
  buildRollbackReceipt,
  replayStableProjection,
  validateObservableTrace,
  validateReplayReceipt,
  validateRollbackReceipt,
} from "../../replay/p1-101-accepted-shared-trace/replay.mjs";

export const EXECUTION_SPINE_VERSION = "P1-149-ACCEPTED-EXECUTION-SPINE/1";
export const EXECUTION_ARTIFACT_KEYS = Object.freeze([
  "provider-response.json",
  "patch-ir.json",
  "compiler-plan.json",
  "pre-snapshot.json",
  "pre-test-receipt.json",
  "post-snapshot.json",
  "apply-receipt.json",
  "oracle-receipt.json",
  "test-receipt.json",
  "rollback-receipt.json",
  "environment.json",
  "system-configuration.json",
  "executable.json",
  "input.json",
  "child-command.json",
  "worker-result.json",
  "execution-trace.jsonl",
  "execution-projection.json",
  "run-record.json",
  "execution-spine.json",
  "p1-101-trace.jsonl",
  "p1-101-stable-projection.json",
  "p1-101-replay-receipt.json",
  "p1-101-adapter-rollback-receipt.json",
]);

const ADAPTER_ID = "P1_149_EXECUTION_SPINE";
const TRACE_SOURCE_PATH =
  "evaluation-harness/recording/p1-101-accepted-shared-trace/trace.mjs";
const REPLAY_SOURCE_PATH =
  "evaluation-harness/replay/p1-101-accepted-shared-trace/replay.mjs";
const COMPILER_SOURCE_PATH =
  "evaluation-harness/harness/p1-149-accepted-execution-spine/patch-ir-v2.mjs";
const EXECUTION_SOURCE_PATH =
  "evaluation-harness/harness/p1-149-accepted-execution-spine/execution.mjs";
const CORE_SOURCE_PATH =
  "evaluation-harness/harness/p1-149-accepted-execution-spine/core.mjs";
const ACCEPTED_INPUTS_SOURCE_PATH =
  "evaluation-harness/harness/p1-149-accepted-execution-spine/accepted-inputs.mjs";

function artifactBytesIdentity(path, bytes) {
  return { path, ...bytesIdentity(bytes) };
}

function encodeCommandOutput(bytes) {
  return {
    base64: bytes.toString("base64"),
    identity: bytesIdentity(bytes),
  };
}

function runEvidenceCommand(command, repositoryRoot) {
  exactKeys(
    command,
    [
      "command_id",
      "role",
      "argv",
      "working_directory",
      "timeout_seconds",
      "expected_exit_codes",
      "non_secret_environment",
    ],
    "accepted verification command",
  );
  assert(
    command.working_directory === "TASK_REPOSITORY"
      && Array.isArray(command.argv)
      && command.argv.length >= 1
      && command.argv.every((value) => typeof value === "string" && !value.includes("\0"))
      && Number.isInteger(command.timeout_seconds)
      && command.timeout_seconds >= 1
      && command.timeout_seconds <= 60
      && canonicalJson(command.expected_exit_codes) === canonicalJson([0])
      && canonicalJson(command.non_secret_environment) === canonicalJson({}),
    "ACCEPTED_COMMAND_DRIFT",
    "accepted verification command is outside the closed offline command contract",
  );
  const executable = safeRegularFile(command.argv[0], "accepted verification executable");
  const result = spawnSync(executable, command.argv.slice(1), {
    cwd: repositoryRoot,
    shell: false,
    timeout: command.timeout_seconds * 1000,
    maxBuffer: MAX_COMMAND_OUTPUT_BYTES,
    encoding: null,
    env: {
      PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      LANG: "C",
      LC_ALL: "C",
      TZ: "UTC",
      NODE_OPTIONS: "--no-warnings",
    },
  });
  assert(
    !result.error,
    result.error?.code === "ETIMEDOUT" ? "COMMAND_TIMEOUT" : "COMMAND_EXECUTION_FAILED",
    `accepted verification command failed to execute: ${result.error?.message ?? "unknown error"}`,
  );
  const stdout = Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0);
  return {
    schema_version: "p1-149-test-command-receipt/v1",
    command_id: command.command_id,
    role: command.role,
    argv: [executable, ...command.argv.slice(1)],
    expected_exit_codes: [...command.expected_exit_codes],
    observed_exit_status: result.status,
    observed_signal: result.signal,
    stdout: encodeCommandOutput(stdout),
    stderr: encodeCommandOutput(stderr),
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

function runAcceptedTests(binding, repositoryRoot, stage) {
  const commands = binding.task.verification?.required_commands;
  assert(
    Array.isArray(commands)
      && commands.length === 2
      && commands.map((command) => command.command_id).join(",")
        === "issue-test,regression-test",
    "ACCEPTED_COMMAND_DRIFT",
    "accepted issue/regression command set drifted",
  );
  return {
    schema_version: "p1-149-test-receipt/v1",
    task_id: binding.task.task_id,
    stage,
    commands: commands.map((command) => runEvidenceCommand(command, repositoryRoot)),
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

function commandExit(receipt, commandId) {
  const command = receipt.commands.find((candidate) => candidate.command_id === commandId);
  assert(command, "TEST_RECEIPT_INVALID", `test receipt is missing ${commandId}`);
  return command.observed_exit_status;
}

function changedEntries(beforeEntries, afterEntries) {
  const before = new Map(beforeEntries.map((entry) => [entry.path, entry]));
  const after = new Map(afterEntries.map((entry) => [entry.path, entry]));
  return [...new Set([...before.keys(), ...after.keys()])]
    .filter((path) => canonicalJson(before.get(path) ?? null) !== canonicalJson(after.get(path) ?? null))
    .sort();
}

function restoreCompiledPlan(repositoryRoot, binding, plan) {
  for (const operation of [...plan.operations].reverse()) {
    const target = containedPath(repositoryRoot, operation.path, "rollback target");
    const current = readFileSync(safeRegularFile(target, "rollback target", true));
    assert(
      current.length === operation.postimage.byte_length
        && sha256(current) === operation.postimage.sha256,
      "ROLLBACK_POSTIMAGE_DRIFT",
      "rollback target no longer equals the applied postimage",
    );
    if (operation.op === "CREATE_REGULAR_FILE") {
      unlinkSync(target);
      assert(!existsSync(target), "ROLLBACK_FAILED", "created target remains after rollback");
      continue;
    }
    const original = binding.source_files.find((entry) => entry.path === operation.path);
    assert(original, "ROLLBACK_PREIMAGE_MISSING", "accepted rollback preimage is missing");
    const originalBytes = readFileSync(
      safeRegularFile(join(binding.source_root, ...operation.path.split("/")), "accepted rollback preimage"),
    );
    applyFileBytesAtomic(repositoryRoot, {
      op: "REPLACE_REGULAR_FILE",
      path: operation.path,
      before: {
        kind: "REGULAR_FILE",
        sha256: operation.postimage.sha256,
        byte_length: operation.postimage.byte_length,
      },
      postimage: {
        base64: originalBytes.toString("base64"),
        sha256: original.sha256,
        byte_length: original.byte_length,
      },
    });
  }
}

function sourceIdentity(relativePath) {
  const bytes = readFileSync(
    safeRegularFile(join(REPOSITORY_ROOT, ...relativePath.split("/")), `${relativePath} source`),
  );
  return { path: relativePath, ...bytesIdentity(bytes) };
}

function executionTraceBytes(events) {
  return Buffer.from(`${events.map((event) => canonicalJson(event)).join("\n")}\n`, "utf8");
}

function makeArtifactMap(entries) {
  const artifacts = {};
  for (const [path, bytes] of entries) {
    assert(
      typeof path === "string"
        && Buffer.isBuffer(bytes)
        && !Object.hasOwn(artifacts, path),
      "EXECUTION_ARTIFACT_INVALID",
      "execution artifact map is invalid",
    );
    artifacts[path] = Buffer.from(bytes);
  }
  return artifacts;
}

function manifestEntries(artifacts, paths) {
  return [...paths]
    .sort()
    .map((path) => {
      const bytes = artifacts[path];
      assert(Buffer.isBuffer(bytes), "EXECUTION_ARTIFACT_MISSING", `execution artifact is missing: ${path}`);
      return artifactBytesIdentity(path, bytes);
    });
}

function expectedP1101Bindings({
  taskSpecIdentity,
  environmentIdentity,
  configurationIdentity,
  executableIdentity,
  inputIdentity,
  outputIdentity,
  runRecordIdentity,
  childRequestIdentity,
  responseIdentity,
  executionTraceIdentity,
  executionProjectionIdentity,
}) {
  return {
    task_spec: taskSpecIdentity,
    environment_snapshot: environmentIdentity,
    system_configuration: configurationIdentity,
    executable: executableIdentity,
    input: inputIdentity,
    output: outputIdentity,
    run_record: runRecordIdentity,
    shared_request: childRequestIdentity,
    accepted_request: responseIdentity,
    underlying_trace: executionTraceIdentity,
    underlying_stable_projection: executionProjectionIdentity,
  };
}

function validateRunId(runId) {
  assert(
    typeof runId === "string"
      && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$/.test(runId),
    "RUN_ID_INVALID",
    "execution run id is invalid",
  );
  return runId;
}

export function executeSpine({ taskId, responseBytes, runId = null }) {
  assert(Buffer.isBuffer(responseBytes), "RESPONSE_BYTES_INVALID", "Provider response must be raw bytes");
  const binding = loadAcceptedTask(taskId);
  const profile = loadAcceptedCompilerProfile(taskId);
  const { patch_ir_bytes: patchIrBytes, compiled } =
    compileNormalizedProviderResponse(responseBytes, profile);
  const selectedRunId = validateRunId(
    runId ?? `P1-149-${taskId}-${sha256(responseBytes).slice(0, 16)}`,
  );
  const disposable = createDisposableRoot("execution");
  try {
    const repositoryRoot = join(disposable.root, "repository");
    copyClosedTree(binding.source_root, repositoryRoot);
    const preSnapshot = directorySnapshot(repositoryRoot);
    const preTests = runAcceptedTests(binding, repositoryRoot, "PRE_APPLICATION");
    assert(
      commandExit(preTests, "issue-test") !== 0
        && commandExit(preTests, "regression-test") === 0,
      "ACCEPTED_BASELINE_DRIFT",
      "accepted source no longer demonstrates the bounded issue with passing regression coverage",
    );

    const compilerPlanBytes = canonicalBytes(compiled.plan);
    const preSnapshotBytes = preSnapshot.bytes;
    const preTestBytes = canonicalBytes(preTests);

    for (const operation of compiled.plan.operations) {
      applyFileBytesAtomic(repositoryRoot, operation);
    }
    const postSnapshot = directorySnapshot(repositoryRoot);
    const postSnapshotBytes = postSnapshot.bytes;
    const changed = changedEntries(preSnapshot.entries, postSnapshot.entries);
    const plannedPaths = compiled.plan.operations.map((operation) => operation.path);
    assert(
      canonicalJson(changed) === canonicalJson(plannedPaths),
      "APPLY_SCOPE_DRIFT",
      "owned-copy changes differ from the compiled finite plan",
      { changed, planned: plannedPaths },
    );
    const applyReceipt = {
      schema_version: "p1-149-apply-receipt/v1",
      task_id: taskId,
      compiler_plan: bytesIdentity(compilerPlanBytes),
      pre_snapshot: preSnapshot.identity,
      post_snapshot: postSnapshot.identity,
      applied_operations: compiled.plan.operations.map((operation, index) => ({
        sequence: index + 1,
        op: operation.op,
        path: operation.path,
        before: operation.before,
        postimage: {
          sha256: operation.postimage.sha256,
          byte_length: operation.postimage.byte_length,
        },
      })),
      changed_paths: changed,
      target: "UNIQUE_OWNED_DISPOSABLE_REPOSITORY_COPY",
      canonical_source_written: false,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
    const applyReceiptBytes = canonicalBytes(applyReceipt);

    const postTests = runAcceptedTests(binding, repositoryRoot, "POST_APPLICATION");
    const testReceiptBytes = canonicalBytes(postTests);
    const issueExit = commandExit(postTests, "issue-test");
    const regressionExit = commandExit(postTests, "regression-test");
    const oracleReceipt = {
      schema_version: "p1-149-oracle-receipt/v1",
      task_id: taskId,
      observed_precondition: {
        issue_test_failed: commandExit(preTests, "issue-test") !== 0,
        regression_test_passed: commandExit(preTests, "regression-test") === 0,
      },
      independently_observed_postcondition: {
        issue_test_passed: issueExit === 0,
        regression_test_passed: regressionExit === 0,
        changed_paths_equal_compiler_plan:
          canonicalJson(changed) === canonicalJson(plannedPaths),
      },
      test_receipt: bytesIdentity(testReceiptBytes),
      result_classification:
        issueExit === 0 && regressionExit === 0 ? "VERIFIED_SUCCESS" : "FAILED",
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
    const oracleReceiptBytes = canonicalBytes(oracleReceipt);

    restoreCompiledPlan(repositoryRoot, binding, compiled.plan);
    const cleanSnapshot = directorySnapshot(repositoryRoot);
    assert(
      preSnapshot.bytes.equals(cleanSnapshot.bytes),
      "ROLLBACK_STATE_IDENTITY_MISMATCH",
      "rollback did not restore the exact pre-application owned-copy snapshot",
    );
    const rollback = {
      status: "PASS_EXACT",
      applied_operation_count: compiled.plan.operations.length,
      pre_snapshot: preSnapshot.identity,
      restored_snapshot: cleanSnapshot.identity,
    };
    const rollbackReceipt = {
      schema_version: "p1-149-rollback-receipt/v1",
      task_id: taskId,
      ...rollback,
      canonical_source_written: false,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
    const rollbackReceiptBytes = canonicalBytes(rollbackReceipt);

    const responseArtifactBytes = Buffer.from(responseBytes);
    const irArtifactBytes = Buffer.from(patchIrBytes);
    const environmentBytes = canonicalBytes({
      schema_version: "p1-149-environment-snapshot/v1",
      environment_snapshot_id: binding.task.environment_snapshot_ref,
      node_version: process.version,
      platform: process.platform,
      architecture: process.arch,
      locale: "C",
      timezone: "UTC",
      external_effects: FALSE_EXTERNAL_EFFECTS,
    });
    const configurationBytes = canonicalBytes({
      schema_version: "p1-149-system-configuration/v1",
      execution_spine_version: EXECUTION_SPINE_VERSION,
      patch_ir_schema: "SL-PATCH-IR/2",
      compiler_version: COMPILER_VERSION,
      accepted_trace_schema: "p1-101-observable-trace-event/v1",
      task_id: taskId,
      dataset_id: binding.manifest.dataset_id,
      dataset_version: binding.manifest.dataset_version,
      dataset_manifest: binding.manifest_identity,
      operation_limit: 3,
      total_postimage_byte_limit: 65536,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    });
    const executableBytes = canonicalBytes({
      schema_version: "p1-149-executable-identity/v1",
      execution_spine_version: EXECUTION_SPINE_VERSION,
      execution_spine: sourceIdentity(EXECUTION_SOURCE_PATH),
      compiler: {
        version: COMPILER_VERSION,
        source: sourceIdentity(COMPILER_SOURCE_PATH),
      },
      runtime_support: [
        sourceIdentity(CORE_SOURCE_PATH),
        sourceIdentity(ACCEPTED_INPUTS_SOURCE_PATH),
      ],
      accepted_p1_101_trace: sourceIdentity(TRACE_SOURCE_PATH),
      accepted_p1_101_replay: sourceIdentity(REPLAY_SOURCE_PATH),
    });
    const inputBytes = canonicalBytes({
      schema_version: "p1-149-execution-input/v1",
      task_id: taskId,
      task_spec: binding.task_spec.identity,
      source_template_snapshot: preSnapshot.identity,
    });
    const childCommandBytes = canonicalBytes({
      schema_version: "p1-149-child-command/v1",
      task_id: taskId,
      compiled_operations: compiled.plan.operations.map((operation, index) => ({
        sequence: index + 1,
        op: operation.op,
        path: operation.path,
      })),
      verification_commands: binding.task.verification.required_commands.map((command) => ({
        command_id: command.command_id,
        argv: command.argv,
        timeout_seconds: command.timeout_seconds,
      })),
      rollback: "EXACT_PRE_APPLICATION_SNAPSHOT",
    });

    const executionProjection = {
      schema_version: "p1-149-execution-stable-projection/v1",
      execution_spine_version: EXECUTION_SPINE_VERSION,
      task_id: taskId,
      dataset: {
        id: binding.manifest.dataset_id,
        version: binding.manifest.dataset_version,
        manifest_sha256: binding.manifest_identity.sha256,
      },
      compiler: {
        version: COMPILER_VERSION,
        input_schema: "SL-PATCH-IR/2",
        finite_operation_limit: 3,
        total_postimage_byte_limit: 65536,
      },
      application: {
        target: "UNIQUE_OWNED_DISPOSABLE_REPOSITORY_COPY",
        pre_snapshot: preSnapshot.identity,
        verification_commands: binding.task.verification.required_commands.map(
          (command) => command.command_id,
        ),
      },
      validation: {
        independent_evaluator_required: true,
        raw_outcome_retained_outside_stable_projection: true,
      },
      rollback: {
        exact_pre_application_snapshot_required: true,
      },
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
    const executionProjectionBytes = canonicalBytes(executionProjection);
    const executionEvents = [
      {
        schema_version: "p1-149-execution-event/v1",
        sequence: 1,
        event_type: "response_admitted",
        task_id: taskId,
        identity: bytesIdentity(responseArtifactBytes),
      },
      {
        schema_version: "p1-149-execution-event/v1",
        sequence: 2,
        event_type: "ir_compiled",
        task_id: taskId,
        identity: bytesIdentity(compilerPlanBytes),
      },
      {
        schema_version: "p1-149-execution-event/v1",
        sequence: 3,
        event_type: "owned_copy_applied",
        task_id: taskId,
        identity: bytesIdentity(applyReceiptBytes),
      },
      {
        schema_version: "p1-149-execution-event/v1",
        sequence: 4,
        event_type: "oracle_and_tests_observed",
        task_id: taskId,
        identity: bytesIdentity(oracleReceiptBytes),
      },
      {
        schema_version: "p1-149-execution-event/v1",
        sequence: 5,
        event_type: "exact_rollback_observed",
        task_id: taskId,
        identity: bytesIdentity(rollbackReceiptBytes),
      },
    ];
    const executionTrace = executionTraceBytes(executionEvents);
    const workerResultBytes = canonicalBytes({
      schema_version: "p1-149-worker-result/v1",
      run_id: selectedRunId,
      task_id: taskId,
      execution_projection: bytesIdentity(executionProjectionBytes),
      oracle_receipt: bytesIdentity(oracleReceiptBytes),
      rollback_receipt: bytesIdentity(rollbackReceiptBytes),
      observed_classification: oracleReceipt.result_classification,
      evaluator_must_reconstruct_from_raw_evidence: true,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    });
    const runRecord = {
      schema_version: "p1-149-run-record/v1",
      run_id: selectedRunId,
      task_id: taskId,
      dataset_version: binding.manifest.dataset_version,
      adapter_id: ADAPTER_ID,
      adapter_version: EXECUTION_SPINE_VERSION,
      environment_snapshot_id: binding.task.environment_snapshot_ref,
      terminal_status: "COMPLETED",
      stop_reason_code: "NONE",
      policy_violations: [],
      execution_projection: bytesIdentity(executionProjectionBytes),
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
    const runRecordBytes = canonicalBytes(runRecord);

    const preManifestArtifacts = makeArtifactMap([
      ["provider-response.json", responseArtifactBytes],
      ["patch-ir.json", irArtifactBytes],
      ["compiler-plan.json", compilerPlanBytes],
      ["pre-snapshot.json", preSnapshotBytes],
      ["pre-test-receipt.json", preTestBytes],
      ["post-snapshot.json", postSnapshotBytes],
      ["apply-receipt.json", applyReceiptBytes],
      ["oracle-receipt.json", oracleReceiptBytes],
      ["test-receipt.json", testReceiptBytes],
      ["rollback-receipt.json", rollbackReceiptBytes],
      ["environment.json", environmentBytes],
      ["system-configuration.json", configurationBytes],
      ["executable.json", executableBytes],
      ["input.json", inputBytes],
      ["child-command.json", childCommandBytes],
      ["worker-result.json", workerResultBytes],
      ["execution-trace.jsonl", executionTrace],
      ["execution-projection.json", executionProjectionBytes],
      ["run-record.json", runRecordBytes],
    ]);
    const executionSpineBytes = canonicalBytes({
      schema_version: "p1-149-execution-spine-manifest/v1",
      execution_spine_version: EXECUTION_SPINE_VERSION,
      run_id: selectedRunId,
      task_id: taskId,
      artifacts: manifestEntries(preManifestArtifacts, Object.keys(preManifestArtifacts)),
      external_effects: FALSE_EXTERNAL_EFFECTS,
    });
    preManifestArtifacts["execution-spine.json"] = executionSpineBytes;

    const adapterResult = {
      run_id: selectedRunId,
      adapter_version: EXECUTION_SPINE_VERSION,
      actions: [
        ...compiled.plan.operations.map((operation, index) => ({
          sequence: index + 1,
          action_id: `apply-${index + 1}`,
          tool_class: "local-file-edit",
          operation_id: `patch_ir.${operation.op}`,
          exit_code: 0,
        })),
        ...binding.task.verification.required_commands.map((command, index) => ({
          sequence: compiled.plan.operations.length + index + 1,
          action_id: `test-${command.command_id}`,
          tool_class: "local-node-test",
          operation_id: `task_test.${command.command_id}`,
          exit_code: commandExit(postTests, command.command_id),
        })),
        {
          sequence: compiled.plan.operations.length
            + binding.task.verification.required_commands.length
            + 1,
          action_id: "rollback",
          tool_class: "local-file-edit",
          operation_id: "repository.rollback",
          exit_code: 0,
        },
      ],
      observed_external_effects: FALSE_EXTERNAL_EFFECTS,
      rollback,
    };
    const identity = (path) => artifactIdentity(path, preManifestArtifacts[path]);
    const responseIdentity = identity("provider-response.json");
    const environmentIdentity = identity("environment.json");
    const configurationIdentity = identity("system-configuration.json");
    const executableIdentity = identity("executable.json");
    const inputIdentity = identity("input.json");
    const outputIdentity = identity("execution-spine.json");
    const runRecordIdentity = identity("run-record.json");
    const executionTraceIdentity = identity("execution-trace.jsonl");
    const executionProjectionIdentity = identity("execution-projection.json");
    const childCommandIdentity = identity("child-command.json");
    const childWorkerResultIdentity = identity("worker-result.json");
    const taskSpecIdentity = binding.task_spec.identity;
    const p1101Bindings = expectedP1101Bindings({
      taskSpecIdentity,
      environmentIdentity,
      configurationIdentity,
      executableIdentity,
      inputIdentity,
      outputIdentity,
      runRecordIdentity,
      childRequestIdentity: inputIdentity,
      responseIdentity,
      executionTraceIdentity,
      executionProjectionIdentity,
    });
    const startedAt = new Date().toISOString();
    const p1101Trace = buildObservableTrace({
      sharedRequestIdentity: inputIdentity,
      acceptedRequestIdentity: responseIdentity,
      childCommandIdentity,
      childWorkerResultIdentity,
      taskSpecIdentity,
      environmentIdentity,
      configurationIdentity,
      executableIdentity,
      inputIdentity,
      outputIdentity,
      runRecordIdentity,
      underlyingTraceIdentity: executionTraceIdentity,
      underlyingProjectionIdentity: executionProjectionIdentity,
      runRecord,
      adapterResult,
      childLedger: {
        started_at: startedAt,
        ended_at: new Date().toISOString(),
        latency_ms: 0,
      },
    });
    validateObservableTrace({
      traceBytes: p1101Trace.bytes,
      expectedRunId: selectedRunId,
      expectedBindings: p1101Bindings,
      expectedAdapterId: ADAPTER_ID,
    });
    const stableProjection = buildStableProjection({
      runRecord,
      taskSpecIdentity,
      environmentIdentity,
      executableIdentity,
      inputIdentity,
      underlyingProjection: executionProjection,
      adapterResult,
    });
    const stableProjectionBytes = projectionBytes(stableProjection);
    const replayReceipt = replayStableProjection({
      traceBytes: p1101Trace.bytes,
      projection: stableProjection,
      expectedProjection: buildStableProjection({
        runRecord,
        taskSpecIdentity,
        environmentIdentity,
        executableIdentity,
        inputIdentity,
        underlyingProjection: executionProjection,
        adapterResult,
      }),
      runRecordBytes,
    });
    const replayReceiptBytes = canonicalBytes(replayReceipt);
    validateReplayReceipt({
      traceBytes: p1101Trace.bytes,
      projectionBytes: stableProjectionBytes,
      runRecordBytes,
      receipt: replayReceipt,
    });
    const p1101RollbackReceipt = buildRollbackReceipt({
      runRecordBytes,
      adapterResult,
      cleanStateIdentity: cleanSnapshot.identity,
    });
    const p1101RollbackReceiptBytes = canonicalBytes(p1101RollbackReceipt);
    validateRollbackReceipt({
      runRecordBytes,
      cleanStateIdentity: cleanSnapshot.identity,
      receipt: p1101RollbackReceipt,
    });

    const artifacts = makeArtifactMap([
      ...Object.entries(preManifestArtifacts),
      ["p1-101-trace.jsonl", p1101Trace.bytes],
      ["p1-101-stable-projection.json", stableProjectionBytes],
      ["p1-101-replay-receipt.json", replayReceiptBytes],
      ["p1-101-adapter-rollback-receipt.json", p1101RollbackReceiptBytes],
    ]);
    assert(
      canonicalJson(Object.keys(artifacts).sort())
        === canonicalJson([...EXECUTION_ARTIFACT_KEYS].sort()),
      "EXECUTION_ARTIFACT_SET_DRIFT",
      "execution artifact set differs from the closed API",
    );
    return {
      schema_version: "p1-149-execution-spine-result/v1",
      task_id: taskId,
      run_id: selectedRunId,
      artifacts,
      stable_projection: stableProjection,
      summary: {
        status: "EXECUTED",
        real_patch_operations: compiled.plan.operations.length,
        issue_test_exit_status: issueExit,
        regression_test_exit_status: regressionExit,
        worker_observed_classification: oracleReceipt.result_classification,
        rollback_exact: true,
        p1_101_trace_events: p1101Trace.events.length,
        p1_101_replay: replayReceipt.status,
        external_effects: FALSE_EXTERNAL_EFFECTS,
      },
    };
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

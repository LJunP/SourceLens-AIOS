#!/usr/bin/env node

import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  assertContained,
  assertExistingPathWithoutSymlink,
  assertFalseEffects,
  assertRelativeArtifactPath,
  canonicalJson,
  exactKeys,
  executeBoundedCommand,
  sha256,
} from "../../harness/p1-125-six-task-parameterized/core.mjs";
import {
  ADAPTER_VERSION,
  commonResultBase,
  createContainedDirectory,
  emit,
  loadExecutionRequest,
  markTargetStarted,
  parseEntryArguments,
  readBoundJson,
  validateEntryPaths,
  writeContainedFileCreateOnce,
} from "./common.mjs";
import { validateTaskProgram } from "./dataset-bindings.mjs";

export const ADAPTER_ID = "B1";

const B1_TOOLS = Object.freeze([
  "file_listing",
  "file_read",
  "lexical_search",
  "structured_patch",
  "verification_command",
]);
const B1_FORBIDDEN = Object.freeze([
  "sourcelens_graph",
  "ranker",
  "memory",
  "additional_agent",
  "network",
]);

function walkRegularFiles(root) {
  const files = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      assert(!entry.isSymbolicLink(), "SYMLINK_REJECTED", "B1 source contains a symlink");
      if (entry.isDirectory()) visit(path);
      else {
        assert(entry.isFile(), "SOURCE_TYPE_REJECTED", "B1 source contains a non-regular entry");
        const bytes = readFileSync(path);
        files.push({
          absolute_path: path,
          relative_path: relative(root, path).split(sep).join("/"),
          sha256: sha256(bytes),
          byte_length: bytes.length,
          mode: statSync(path).mode & 0o777,
        });
      }
    }
  };
  visit(root);
  return files.sort((left, right) => left.relative_path.localeCompare(right.relative_path));
}

function materializeTaskSource(repositoryRoot, taskSource, destinationRoot) {
  assert(
    typeof taskSource === "string"
      && !isAbsolute(taskSource)
      && taskSource.includes("/source-template")
      && !taskSource.split(/[\\/]/).includes(".."),
    "B1_INPUT_REJECTED",
    "B1 task source must be a bounded source-template path",
  );
  const sourceRoot = assertContained(repositoryRoot, resolve(repositoryRoot, taskSource), "B1 task source");
  assertExistingPathWithoutSymlink(sourceRoot, "B1 task source");
  assert(statSync(sourceRoot).isDirectory(), "B1_INPUT_REJECTED", "B1 task source is not a directory");
  const inventory = walkRegularFiles(sourceRoot);
  assert(inventory.length > 0, "B1_INPUT_REJECTED", "B1 task source is empty");
  for (const entry of inventory) {
    const mode = (entry.mode & 0o111) === 0 ? 0o600 : 0o700;
    writeContainedFileCreateOnce(destinationRoot, entry.relative_path, readFileSync(entry.absolute_path), mode);
  }
  return inventory.map(({ absolute_path: _absolutePath, ...entry }) => entry);
}

function verifyInventory(root, inventory) {
  return inventory.map((entry) => {
    const path = assertContained(root, join(root, entry.relative_path), entry.relative_path);
    assertExistingPathWithoutSymlink(path, entry.relative_path);
    const bytes = readFileSync(path);
    return {
      path: entry.relative_path,
      sha256: sha256(bytes),
      byte_length: bytes.length,
      matches: sha256(bytes) === entry.sha256 && bytes.length === entry.byte_length,
    };
  });
}

function validateConfiguration(configuration, request) {
  assert(
    configuration.adapter_id === ADAPTER_ID
      && configuration.adapter_version === ADAPTER_VERSION
      && Number.isInteger(configuration.loop_limit)
      && configuration.loop_limit === 5
      && canonicalJson(configuration.enabled_tools) === canonicalJson(B1_TOOLS),
    "B1_CONFIGURATION_REJECTED",
    "B1 configuration does not expose the exact finite tool set",
  );
  assert(
    B1_FORBIDDEN.every((key) => configuration.feature_flags[key] === false),
    "B1_FORBIDDEN_FEATURE_REJECTED",
    "B1 forbidden feature flag is enabled or missing",
  );
  assert(
    request.limits.max_tool_calls >= 6
      && request.limits.max_cost_usd === 0
      && request.limits.max_model_tokens === 0,
    "B1_BUDGET_REJECTED",
    "B1 conformance requires six finite local actions and zero model/cost budgets",
  );
}

function validateInput(input, task) {
  exactKeys(input, [
    "schema_version",
    "program_id",
    "dataset_id",
    "dataset_version",
    "dataset_manifest_sha256",
    "task_id",
    "task_spec_path",
    "task_source",
    "allowed_tool_classes",
    "forbidden_features",
    "actions",
    "expected_action_count",
    "rollback",
    "external_effects",
    "claim_boundary",
  ], "B1 finite program");
  assert(
    input.schema_version === "p1-125-b1-finite-program/v1"
      && typeof input.program_id === "string"
      && input.program_id.length > 0
      && input.expected_action_count === 6
      && input.actions.length === input.expected_action_count
      && canonicalJson(input.allowed_tool_classes) === canonicalJson(B1_TOOLS)
      && canonicalJson(input.forbidden_features) === canonicalJson(B1_FORBIDDEN)
      && input.claim_boundary === "FINITE_COOPERATIVE_LOCAL_B1_SIX_TASK_PROGRAM_ONLY",
    "B1_INPUT_REJECTED",
    "B1 finite program identity or boundary is invalid",
  );
  assertFalseEffects(input.external_effects, "B1 program external effects");
  const expectedClasses = [
    "file_listing",
    "file_read",
    "lexical_search",
    "structured_patch",
    "verification_command",
    "verification_command",
  ];
  input.actions.forEach((action, index) => {
    assert(
      action.ordinal === index + 1 && action.tool_class === expectedClasses[index],
      "B1_INPUT_REJECTED",
      "B1 finite action sequence drifted",
    );
  });
  exactKeys(input.rollback, [
    "required",
    "changed_paths",
    "created_paths",
  ], "B1 rollback");
  assert(
    input.rollback.required === true
      && Array.isArray(input.rollback.changed_paths)
      && Array.isArray(input.rollback.created_paths),
    "B1_INPUT_REJECTED",
    "B1 rollback identities are invalid",
  );
}

function validateVerificationCommand(command, sourceRoot, request) {
  const allowedKeys = [
    "command_id",
    "role",
    "argv",
    "working_directory",
    "timeout_seconds",
    "expected_exit_codes",
  ];
  if (Object.hasOwn(command, "non_secret_environment")) allowedKeys.push("non_secret_environment");
  exactKeys(command, allowedKeys, "verification command");
  assert(
    typeof command.command_id === "string"
      && command.command_id.length > 0
      && ["issue_specific", "regression", "static", "security"].includes(command.role)
      && command.working_directory === "TASK_REPOSITORY",
    "B1_VERIFICATION_COMMAND_REJECTED",
    "verification command metadata is invalid",
  );
  assert(
    Array.isArray(command.argv)
      && command.argv.length === 3
      && command.argv[1] === "--test"
      && typeof command.argv[2] === "string"
      && !isAbsolute(command.argv[2])
      && !command.argv[2].split(/[\\/]/).includes(".."),
    "MALFORMED_ARGV_REJECTED",
    "B1 verification argv is outside the finite Node test grammar",
  );
  assert(
    realpathSync(command.argv[0]) === realpathSync(process.execPath),
    "COMMAND_DRIFT_REJECTED",
    "B1 verification executable is not the bound Node runtime",
  );
  assert(
    Number.isInteger(command.timeout_seconds)
      && command.timeout_seconds >= 1
      && command.timeout_seconds <= request.limits.wall_clock_seconds,
    "TIMEOUT_CONTRACT_REJECTED",
    "B1 verification timeout exceeds the run contract",
  );
  assert(
    Array.isArray(command.expected_exit_codes)
      && canonicalJson(command.expected_exit_codes) === canonicalJson([0]),
    "EXPECTED_EXIT_CONTRACT_REJECTED",
    "B1 expected-exit contract is invalid",
  );
  return {
    argv: [realpathSync(process.execPath), "--test", command.argv[2]],
    cwd: sourceRoot,
    timeoutSeconds: command.timeout_seconds,
    expectedExitCodes: command.expected_exit_codes,
    environment: command.non_secret_environment ?? {},
  };
}

function actionAt(input, ordinal, toolClass) {
  const action = input.actions[ordinal - 1];
  assert(action.ordinal === ordinal && action.tool_class === toolClass, "B1_INPUT_REJECTED", "B1 action order drifted");
  return action;
}

export async function executeB1(executionRequestPath) {
  const loaded = loadExecutionRequest(executionRequestPath, ADAPTER_ID);
  const taskRecord = readBoundJson(loaded.request.task_spec, "TaskSpec");
  const task = taskRecord.value;
  const environment = readBoundJson(loaded.request.environment_snapshot, "EnvironmentSnapshot").value;
  const configuration = readBoundJson(loaded.request.system_configuration, "B1 SystemConfiguration").value;
  const input = readBoundJson(loaded.request.adapter_input, "B1 finite program").value;
  validateConfiguration(configuration, loaded.request);
  validateInput(input, task);
  assert(
    Object.keys(loaded.request.auxiliary_inputs).length === 0,
    "B1_INPUT_REJECTED",
    "B1 does not admit auxiliary inputs",
  );
  assert(
    environment.model.provider === "none-offline"
      && task.network_policy === "none"
      && environment.network.policy === "none",
    "B1_EXTERNAL_BOUNDARY_REJECTED",
    "B1 environment is not provider-neutral and offline",
  );

  const sentinel = markTargetStarted(loaded.request, loaded.sentinel, {
    mode: "FINITE_TOOL_AGENT_CONFORMANCE",
  });
  const sourceRoot = createContainedDirectory(loaded.runRoot, "work/b1-disposable-source");
  const repositoryRoot = resolve(fileURLToPath(new URL("../../..", import.meta.url)));
  validateTaskProgram(repositoryRoot, task, taskRecord.path, input);
  const originalInventory = materializeTaskSource(repositoryRoot, input.task_source, sourceRoot);
  const originalBytes = new Map(originalInventory.map((entry) => [
    entry.relative_path,
    readFileSync(join(sourceRoot, entry.relative_path)),
  ]));
  const actions = [];

  const listing = actionAt(input, 1, "file_listing");
  exactKeys(listing, ["ordinal", "tool_class", "relative_path"], "B1 file listing");
  assert(listing.relative_path === ".", "B1_INPUT_REJECTED", "B1 listing must target the disposable root");
  const listedFiles = walkRegularFiles(sourceRoot).map((entry) => entry.relative_path);
  actions.push({
    sequence: 1,
    action_id: `${loaded.request.run_id}:1`,
    action_type: "tool_call",
    tool_class: "file_listing",
    paths: listedFiles,
    exit_code: 0,
  });

  const read = actionAt(input, 2, "file_read");
  exactKeys(read, ["ordinal", "tool_class", "relative_path"], "B1 file read");
  assertRelativeArtifactPath(read.relative_path, "B1 read path");
  const readPath = assertContained(sourceRoot, join(sourceRoot, read.relative_path), "B1 read path");
  const readBytes = readFileSync(readPath);
  actions.push({
    sequence: 2,
    action_id: `${loaded.request.run_id}:2`,
    action_type: "tool_call",
    tool_class: "file_read",
    path: read.relative_path,
    sha256: sha256(readBytes),
    byte_length: readBytes.length,
    exit_code: 0,
  });

  const search = actionAt(input, 3, "lexical_search");
  exactKeys(search, ["ordinal", "tool_class", "query", "relative_path"], "B1 lexical search");
  assert(typeof search.query === "string" && search.query.length > 0, "B1_INPUT_REJECTED", "B1 search query is empty");
  assertRelativeArtifactPath(search.relative_path, "B1 search path");
  const searchRoot = assertContained(sourceRoot, join(sourceRoot, search.relative_path), "B1 search root");
  const searchFiles = walkRegularFiles(searchRoot);
  let matches = 0;
  for (const entry of searchFiles) {
    matches += readFileSync(entry.absolute_path, "utf8").split(search.query).length - 1;
  }
  assert(matches >= 1, "LEXICAL_SEARCH_REJECTED", "B1 lexical search produced no match");
  actions.push({
    sequence: 3,
    action_id: `${loaded.request.run_id}:3`,
    action_type: "tool_call",
    tool_class: "lexical_search",
    path: search.relative_path,
    query_sha256: sha256(Buffer.from(search.query, "utf8")),
    matches,
    exit_code: 0,
  });

  const patch = actionAt(input, 4, "structured_patch");
  exactKeys(patch, [
    "ordinal",
    "tool_class",
    "changes",
  ], "B1 structured patch");
  assert(
    Array.isArray(patch.changes)
      && patch.changes.length >= 1
      && patch.changes.length <= 3
      && canonicalJson(patch.changes.map((entry) => entry.relative_path))
        === canonicalJson(input.rollback.changed_paths),
    "B1_INPUT_REJECTED",
    "B1 structured change set is invalid",
  );
  const preparedChanges = patch.changes.map((change) => {
    exactKeys(change, [
      "relative_path",
      "operation",
      "before_sha256",
      "after_sha256",
      "replacement",
    ], "B1 structured change");
    exactKeys(change.replacement, ["old", "new"], "B1 replacement");
    assertRelativeArtifactPath(change.relative_path, "B1 patch path");
    const path = assertContained(sourceRoot, join(sourceRoot, change.relative_path), "B1 patch path");
    assert(
      ["replace_once", "create"].includes(change.operation)
        && typeof change.replacement.new === "string"
        && /^[0-9a-f]{64}$/.test(change.after_sha256),
      "B1_INPUT_REJECTED",
      "B1 structured change operation is invalid",
    );
    if (change.operation === "create") {
      assert(
        change.before_sha256 === null
          && change.replacement.old === null
          && !existsSync(path),
        "INPUT_IDENTITY_REJECTED",
        "B1 create target already exists or has a preimage",
      );
      const afterBytes = Buffer.from(change.replacement.new, "utf8");
      assert(sha256(afterBytes) === change.after_sha256, "INPUT_IDENTITY_REJECTED", "B1 create postimage mismatch");
      return { ...change, path, afterBytes };
    }
    const beforeBytes = readFileSync(path);
    const beforeText = new TextDecoder("utf-8", { fatal: true }).decode(beforeBytes);
    assert(
      sha256(beforeBytes) === change.before_sha256
        && typeof change.replacement.old === "string"
        && change.replacement.old.length > 0
        && beforeText.split(change.replacement.old).length - 1 === 1,
      "INPUT_IDENTITY_REJECTED",
      "B1 replacement preimage is missing, ambiguous or drifted",
    );
    const afterBytes = Buffer.from(beforeText.replace(change.replacement.old, change.replacement.new), "utf8");
    assert(sha256(afterBytes) === change.after_sha256, "INPUT_IDENTITY_REJECTED", "B1 replacement postimage mismatch");
    return { ...change, path, afterBytes };
  });

  const verificationLedgers = [];
  let rollback;
  try {
    for (const change of preparedChanges) {
      if (change.operation === "create") {
        writeFileSync(change.path, change.afterBytes, { flag: "wx", mode: 0o600 });
      } else {
        writeFileSync(change.path, change.afterBytes, { flag: "w" });
      }
    }
    actions.push({
      sequence: 4,
      action_id: `${loaded.request.run_id}:4`,
      action_type: "tool_call",
      tool_class: "structured_patch",
      paths: preparedChanges.map((change) => ({
        path: change.relative_path,
        operation: change.operation,
        before_sha256: change.before_sha256,
        after_sha256: change.after_sha256,
      })),
      exit_code: 0,
    });
    for (let ordinal = 5; ordinal <= 6; ordinal += 1) {
      const declared = actionAt(input, ordinal, "verification_command");
      exactKeys(declared, ["ordinal", "tool_class", "command_id"], "B1 verification action");
      const command = task.verification.required_commands.find((entry) => entry.command_id === declared.command_id);
      assert(command, "B1_INPUT_REJECTED", `unknown verification command: ${declared.command_id}`);
      const executed = await executeBoundedCommand(validateVerificationCommand(command, sourceRoot, loaded.request));
      verificationLedgers.push({ command_id: command.command_id, ledger: executed.ledger });
      actions.push({
        sequence: ordinal,
        action_id: `${loaded.request.run_id}:${ordinal}`,
        action_type: "tool_call",
        tool_class: "verification_command",
        command_id: command.command_id,
        stdout_sha256: executed.ledger.stdout_sha256,
        stderr_sha256: executed.ledger.stderr_sha256,
        exit_code: executed.ledger.exit_status,
        expected_exit_matched: executed.ledger.expected_exit_matched,
      });
      assert(executed.ledger.expected_exit_matched, "VERIFICATION_COMMAND_FAILED", `B1 verification failed: ${command.command_id}`);
    }
  } finally {
    for (const path of input.rollback.created_paths) {
      const createdPath = assertContained(sourceRoot, join(sourceRoot, path), "B1 rollback create path");
      if (existsSync(createdPath)) unlinkSync(createdPath);
    }
    for (const [path, bytes] of originalBytes.entries()) {
      writeFileSync(join(sourceRoot, path), bytes, { flag: "w" });
    }
    const observed = verifyInventory(sourceRoot, originalInventory);
    rollback = {
      status: observed.every((entry) => entry.matches) ? "PASS_EXACT" : "NON_PASS",
      source_root: "work/b1-disposable-source",
      files: observed,
      changed_paths: input.rollback.changed_paths,
      created_paths_removed: input.rollback.created_paths,
    };
  }
  assert(
    rollback.status === "PASS_EXACT"
      && input.rollback.created_paths.every((path) => !existsSync(join(sourceRoot, path))),
    "ROLLBACK_NON_PASS",
    "B1 source did not roll back exactly",
  );
  assert(actions.length <= loaded.request.limits.max_tool_calls, "TOOL_BUDGET_EXHAUSTED", "B1 exceeded the declared tool budget");

  const result = {
    ...commonResultBase({
      request: loaded.request,
      task,
      configuration,
      actions,
      usage: {
        input_tokens: 0,
        output_tokens: 0,
        tool_calls: actions.length,
        retries: 0,
        human_interventions: 0,
        cost_usd: 0,
        latency_ms: verificationLedgers.reduce((sum, entry) => sum + entry.ledger.latency_ms, 0),
      },
      targetSentinel: sentinel,
    }),
    result: {
      summary: "Finite local tool conformance program applied, verified and rolled back.",
      changed_paths: input.rollback.changed_paths,
      tests: verificationLedgers.map((entry) => entry.command_id),
    },
    provenance: {
      kind: "QUALITY_FROZEN_FINITE_TOOL_CONFORMANCE_PROGRAM",
      live_model_invoked: false,
      provider_invoked: false,
      model_performance_sample: false,
    },
    verification_ledgers: verificationLedgers,
    source_mutation_observed: false,
    rollback,
  };
  assertFalseEffects(result.requested_external_effects, "B1 result requested external effects");
  assertFalseEffects(result.observed_external_effects, "B1 observed external effects");
  return result;
}

async function main() {
  const args = parseEntryArguments(process.argv.slice(2));
  const loaded = loadExecutionRequest(args.requestPath, ADAPTER_ID);
  validateEntryPaths(args, loaded);
  emit(await executeB1(args.requestPath));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stdout.write(`${canonicalJson({
      schema_version: "1.0",
      record_type: "p1_125_adapter_failure",
      adapter_id: ADAPTER_ID,
      verdict: "NON_PASS",
      reason_code: error.code ?? "UNCAUGHT_EXCEPTION",
      message: `${error.name}: ${error.message}`,
      requested_external_effects: FALSE_EXTERNAL_EFFECTS,
      observed_external_effects: FALSE_EXTERNAL_EFFECTS,
    })}\n`);
    process.exit(1);
  });
}

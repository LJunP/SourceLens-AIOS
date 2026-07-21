#!/usr/local/bin/node

import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  chmodSync,
  constants as fsConstants,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  renameSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ADAPTER_VERSION,
  AdapterError,
  buildRequestBody,
  compileSelection,
  parseChatCompletion,
  parseJsonNoDuplicates,
} from "../../adapters/local-gateway-finite-ir-b0-v1/core.mjs";
import {
  assertOwnedProductionRunRoot,
  assertOwnedRunRoot,
  canonicalJsonBytes,
  createRunRoot,
  EVIDENCE_ROOT,
  productionRunRoot,
  readRegular,
  sha256,
  validateRunId,
  writeCreateOnce,
} from "../../recording/local-gateway-finite-ir-b0-v1/evidence.mjs";

export const REPLAY_VERSION = "P1-062-LOCAL-GATEWAY-FINITE-IR-REPLAY/1";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const DATASET_TASK_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION",
);
const MATERIALIZATION_RECIPE_PATH = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1/materialization-recipe.json",
);
const EXPECTED_BASE_FAILURE_PATH = join(DATASET_TASK_ROOT, "expected-base-failure.json");
const NODE = "/usr/local/bin/node";
const GIT = "/usr/bin/git";
const EXPECTED_BASE_COMMIT = "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f";
const EXPECTED_BASE_TREE = "900814727113d65f5dad8b63222e14f39b2cf38b";
const MAX_COMMAND_OUTPUT_BYTES = 1024 * 1024;
const SOURCE_FILES = Object.freeze([
  Object.freeze({
    relative_path: "src/range.mjs",
    byte_length: 115,
    sha256: "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75",
  }),
  Object.freeze({
    relative_path: "test/issue.test.mjs",
    byte_length: 237,
    sha256: "51fd472f8cf85fd595246814db29699ab81ccdc2986d80666d8609a8c4972b4b",
  }),
  Object.freeze({
    relative_path: "test/regression.test.mjs",
    byte_length: 241,
    sha256: "381c573d8f99305b47db9f1a2ca49779842fe1187b9d7c5b7410e56dda9240c5",
  }),
]);
const MATERIALIZATION_RECIPE_IDENTITY = Object.freeze({
  byte_length: 456,
  sha256: "104ed7109df7da155867a428b50575a9cda6bca481e183cebed50788c01a3a5e",
});
const EXPECTED_BASE_FAILURE_IDENTITY = Object.freeze({
  byte_length: 439,
  sha256: "5dbe034939ed2178f86fd84ad409cff9426040f63343de27f7ad3e8f46dd2494",
});
const FALSE_EXTERNAL_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const RESPONSE_REJECTION_CODES = new Set([
  "OUTER_JSON_INVALID_OR_DUPLICATE",
  "OUTER_NOT_OBJECT",
  "OBJECT_MISMATCH",
  "ID_INVALID",
  "CREATED_INVALID",
  "MODEL_MISMATCH",
  "CHOICES_NOT_SINGLE",
  "CHOICE_INVALID",
  "CHOICE_INDEX_INVALID",
  "FINISH_REASON_NOT_STOP",
  "MESSAGE_INVALID",
  "MESSAGE_ROLE_NOT_ASSISTANT",
  "MESSAGE_CONTENT_NOT_STRING",
  "MESSAGE_CONTENT_TOO_LARGE",
  "MESSAGE_REFUSAL_PRESENT",
  "MESSAGE_TOOL_CALL_PRESENT",
  "USAGE_INVALID",
  "CONTENT_NOT_EXACTLY_ADMITTED",
]);

export class ReplayError extends Error {
  constructor(code, details = undefined) {
    super(code);
    this.name = "ReplayError";
    this.code = code;
    this.details = details;
  }
}

function assert(condition, code, details = undefined) {
  if (!condition) throw new ReplayError(code, details);
}

function identity(bytes) {
  return Object.freeze({ byte_length: bytes.length, sha256: sha256(bytes) });
}

function sameIdentity(actual, expected) {
  return actual?.byte_length === expected.byte_length && actual?.sha256 === expected.sha256;
}

function assertExactFile(path, expected, code) {
  const bytes = readRegular(path, expected.byte_length);
  assert(sameIdentity(identity(bytes), expected), code);
  return bytes;
}

function assertRealDirectory(path, code) {
  const absolute = resolve(path);
  const stat = lstatSync(absolute);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), code);
  assert(realpathSync(absolute) === absolute, code);
  return Object.freeze({ path: absolute, dev: stat.dev, ino: stat.ino });
}

function assertWithin(root, candidate, code) {
  const base = resolve(root);
  const absolute = resolve(candidate);
  assert(absolute.startsWith(`${base}${sep}`), code);
  return absolute;
}

function assertExecutable(path, code) {
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink() && realpathSync(path) === path, code);
  assert((stat.mode & 0o111) !== 0 && (stat.mode & 0o022) === 0, code);
  return Object.freeze({ path, byte_length: stat.size, mode: stat.mode & 0o777 });
}

function parseClosedJsonFile(path, maxBytes, label) {
  const bytes = readRegular(path, maxBytes);
  const value = parseJsonNoDuplicates(bytes, maxBytes, label);
  assert(bytes.equals(canonicalJsonBytes(value)), `${label}_NOT_CANONICAL`);
  return value;
}

function validateProviderRun(providerRoot, callSlotPath) {
  const root = assertRealDirectory(providerRoot, "PROVIDER_RUN_ROOT_INVALID");
  const ownershipBytes = readRegular(join(root.path, "ownership.json"), 4096);
  const ownership = parseJsonNoDuplicates(ownershipBytes, 4096, "PROVIDER_OWNERSHIP");
  assert(ownershipBytes.equals(canonicalJsonBytes(ownership)), "PROVIDER_RUN_OWNERSHIP_INVALID");
  assert(JSON.stringify(Object.keys(ownership).sort()) === JSON.stringify([
    "created_exclusively",
    "nonce",
    "root_basename",
    "root_device",
    "root_inode",
    "schema",
  ]), "PROVIDER_RUN_OWNERSHIP_INVALID");
  assert(ownership.schema === "P1-062-RUN-OWNERSHIP/1" && ownership.created_exclusively === true &&
    ownership.root_basename === basename(root.path) && ownership.root_device === String(root.dev) &&
    ownership.root_inode === String(root.ino) && /^[0-9a-f]{64}$/u.test(ownership.nonce),
  "PROVIDER_RUN_OWNERSHIP_INVALID");

  const globalCallSlot = resolve(EVIDENCE_ROOT, "source-bearing-call-slot.json");
  const localTestCallSlot = resolve(root.path, "source-bearing-call-slot.json");
  const resolvedCallSlot = resolve(callSlotPath);
  assert(resolvedCallSlot === globalCallSlot || resolvedCallSlot === localTestCallSlot,
    "CALL_SLOT_PATH_INVALID");

  const expectedRequest = buildRequestBody();
  const requestBytes = readRegular(join(root.path, "request-body.json"), 32768);
  assert(requestBytes.equals(expectedRequest.bytes), "PROVIDER_REQUEST_IDENTITY_DRIFT");
  const egressManifestBytes = readRegular(join(root.path, "egress-manifest.json"), 32768);
  assert(egressManifestBytes.equals(canonicalJsonBytes(expectedRequest.egress_manifest)),
    "PROVIDER_EGRESS_MANIFEST_IDENTITY_DRIFT");

  const slot = parseClosedJsonFile(resolvedCallSlot, 8192, "CALL_SLOT");
  assert(slot.schema === "P1-062-SOURCE-BEARING-CALL-SLOT/1" && slot.consumed === true &&
    slot.ordinal === 1 && slot.automatic_retry_allowed === false &&
    sameIdentity(slot.request_body, expectedRequest.identity), "SOURCE_BEARING_CALL_SLOT_INVALID");

  const responsePath = join(root.path, "raw-response.json");
  const responseBytes = readRegular(responsePath, 131072);
  const responseIdentity = identity(responseBytes);
  const receiptBytes = readRegular(join(root.path, "transport-receipt.json"), 65536);
  const receipt = parseJsonNoDuplicates(receiptBytes, 65536, "TRANSPORT_RECEIPT");
  assert(receiptBytes.equals(canonicalJsonBytes(receipt)), "TRANSPORT_RECEIPT_NOT_CANONICAL");
  assert(receipt.schema === "P1-062-TRANSPORT-RECEIPT/1" && receipt.terminal_code === "RESPONSE_RETAINED",
    "TRANSPORT_NOT_REPLAYABLE");
  assert(receipt.source_bearing_submission_count === 1 && receipt.automatic_retry_count === 0 &&
    receipt.redirect_follow_count === 0 && receipt.proxy_use_count === 0 && receipt.dns_lookup_count === 0,
  "TRANSPORT_COUNTERS_INVALID");
  assert(Number.isSafeInteger(receipt.http_status) && receipt.http_status >= 200 && receipt.http_status < 300,
    "TRANSPORT_STATUS_INVALID");
  assert(receipt.peer?.address === "127.0.0.1" && receipt.peer?.family === "IPv4",
    "TRANSPORT_PEER_INVALID");
  assert(sameIdentity(receipt.request_body, expectedRequest.identity), "TRANSPORT_REQUEST_IDENTITY_DRIFT");
  assert(sameIdentity(receipt.response_body, responseIdentity), "TRANSPORT_RESPONSE_IDENTITY_DRIFT");
  assert(receipt.response_body.path === responsePath, "TRANSPORT_RESPONSE_PATH_DRIFT");
  assert(receipt.authorization_header_persisted_hashed_or_logged === false,
    "TRANSPORT_CREDENTIAL_BOUNDARY_INVALID");

  return Object.freeze({
    root: root.path,
    response_bytes: responseBytes,
    response_identity: responseIdentity,
    request_identity: expectedRequest.identity,
    egress_manifest_identity: identity(egressManifestBytes),
    transport_receipt_identity: identity(receiptBytes),
    http_status: receipt.http_status,
    peer: Object.freeze({ address: receipt.peer.address, port: receipt.peer.port, family: receipt.peer.family }),
  });
}

function fixedEnvironment(homePath, recipe) {
  return Object.freeze({
    HOME: homePath,
    LANG: "C",
    LC_ALL: "C",
    PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    TZ: "UTC",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_AUTHOR_NAME: recipe.git_author_name,
    GIT_AUTHOR_EMAIL: recipe.git_author_email,
    GIT_AUTHOR_DATE: recipe.git_author_date,
    GIT_COMMITTER_NAME: recipe.git_committer_name,
    GIT_COMMITTER_EMAIL: recipe.git_committer_email,
    GIT_COMMITTER_DATE: recipe.git_committer_date,
  });
}

function runCommand(records, commandId, executable, args, cwd, env, timeoutMs = 10000) {
  assert(/^[a-z0-9-]+$/u.test(commandId), "COMMAND_ID_INVALID");
  const result = spawnSync(executable, args, {
    cwd,
    env,
    encoding: null,
    timeout: timeoutMs,
    killSignal: "SIGKILL",
    maxBuffer: MAX_COMMAND_OUTPUT_BYTES,
    windowsHide: true,
  });
  const stdout = Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0);
  assert(stdout.length <= MAX_COMMAND_OUTPUT_BYTES && stderr.length <= MAX_COMMAND_OUTPUT_BYTES,
    "COMMAND_OUTPUT_TOO_LARGE", commandId);
  assert(!result.error, result.error?.code === "ETIMEDOUT" ? "COMMAND_TIMEOUT" : "COMMAND_SPAWN_FAILED", commandId);
  assert(result.signal === null, "COMMAND_SIGNALLED", commandId);
  const record = Object.freeze({
    command_id: commandId,
    executable,
    argv: Object.freeze([executable, ...args]),
    cwd,
    exit_status: result.status,
    stdout,
    stderr,
  });
  records.push(record);
  return record;
}

function expectStatus(record, expected, code) {
  assert(record.exit_status === expected, code, {
    command_id: record.command_id,
    expected,
    actual: record.exit_status,
  });
}

function outputText(record) {
  return Buffer.concat([record.stdout, record.stderr]).toString("utf8");
}

function trimmedOutput(record) {
  return record.stdout.toString("utf8").trim();
}

function parseStatus(record) {
  expectStatus(record, 0, "GIT_STATUS_FAILED");
  if (record.stdout.length === 0) return [];
  return record.stdout.toString("utf8").split("\0").filter(Boolean).map((entry) => {
    assert(entry.length >= 4 && entry[2] === " ", "GIT_STATUS_FORMAT_INVALID");
    return entry.slice(3);
  }).sort();
}

function makeMaterialization() {
  const createdPath = mkdtempSync(join(tmpdir(), "sourcelens-p1-062-replay-"));
  const root = realpathSync(createdPath);
  chmodSync(root, 0o700);
  const stat = lstatSync(root);
  const marker = Object.freeze({
    schema: "P1-062-REPLAY-MATERIALIZATION-OWNERSHIP/1",
    created_exclusively: true,
    nonce: randomBytes(32).toString("hex"),
  });
  const markerReceipt = writeCreateOnce(join(root, "ownership.json"), canonicalJsonBytes(marker));
  return Object.freeze({ root, dev: stat.dev, ino: stat.ino, marker: markerReceipt });
}

function cleanupMaterialization(ownership) {
  const current = assertRealDirectory(ownership.root, "MATERIALIZATION_ROOT_IDENTITY_DRIFT");
  assert(current.dev === ownership.dev && current.ino === ownership.ino,
    "MATERIALIZATION_ROOT_IDENTITY_DRIFT");
  const markerBytes = readRegular(join(ownership.root, "ownership.json"), ownership.marker.byte_length);
  assert(sameIdentity(identity(markerBytes), ownership.marker), "MATERIALIZATION_OWNERSHIP_DRIFT");
  rmSync(ownership.root, { recursive: true, force: false, maxRetries: 0 });
  assert(!existsSync(ownership.root), "MATERIALIZATION_CLEANUP_FAILED");
}

function materializeRepository(ownership, records) {
  const recipeBytes = assertExactFile(
    MATERIALIZATION_RECIPE_PATH,
    MATERIALIZATION_RECIPE_IDENTITY,
    "MATERIALIZATION_RECIPE_IDENTITY_DRIFT",
  );
  const recipe = parseJsonNoDuplicates(recipeBytes, recipeBytes.length, "MATERIALIZATION_RECIPE");
  assert(recipe.hash_algorithm === "sha1" && recipe.file_mode === "100644" &&
    recipe.commit_message === "fixture: base", "MATERIALIZATION_RECIPE_INVALID");

  const repository = assertWithin(ownership.root, join(ownership.root, "repository"), "MATERIALIZATION_PATH_ESCAPE");
  const home = assertWithin(ownership.root, join(ownership.root, "home"), "MATERIALIZATION_PATH_ESCAPE");
  mkdirSync(repository, { mode: 0o700 });
  mkdirSync(home, { mode: 0o700 });
  mkdirSync(join(repository, "src"), { mode: 0o700 });
  mkdirSync(join(repository, "test"), { mode: 0o700 });

  for (const source of SOURCE_FILES) {
    const sourcePath = join(DATASET_TASK_ROOT, "source-template", source.relative_path);
    const sourceBytes = assertExactFile(sourcePath, source, "SOURCE_TEMPLATE_IDENTITY_DRIFT");
    writeCreateOnce(join(repository, source.relative_path), sourceBytes, 0o644);
  }

  const env = fixedEnvironment(home, recipe);
  expectStatus(runCommand(records, "git-init", GIT, ["init", "--quiet"], repository, env), 0,
    "MATERIALIZATION_GIT_INIT_FAILED");
  expectStatus(runCommand(records, "git-add", GIT, ["add", "--all"], repository, env), 0,
    "MATERIALIZATION_GIT_ADD_FAILED");
  expectStatus(runCommand(records, "git-commit", GIT,
    ["-c", "commit.gpgSign=false", "commit", "--quiet", "-m", recipe.commit_message], repository, env), 0,
  "MATERIALIZATION_GIT_COMMIT_FAILED");

  const head = runCommand(records, "base-head", GIT, ["rev-parse", "HEAD"], repository, env);
  const tree = runCommand(records, "base-tree", GIT, ["rev-parse", "HEAD^{tree}"], repository, env);
  const status = runCommand(records, "base-status", GIT,
    ["status", "--porcelain=v1", "-z", "--untracked-files=all"], repository, env);
  expectStatus(head, 0, "BASE_IDENTITY_QUERY_FAILED");
  expectStatus(tree, 0, "BASE_IDENTITY_QUERY_FAILED");
  assert(trimmedOutput(head) === EXPECTED_BASE_COMMIT, "BASE_COMMIT_MISMATCH");
  assert(trimmedOutput(tree) === EXPECTED_BASE_TREE, "BASE_TREE_MISMATCH");
  assert(parseStatus(status).length === 0, "BASE_NOT_CLEAN");

  return Object.freeze({ repository, env });
}

function executeFixedTests(records, prefix, materialized) {
  const issue = runCommand(records, `${prefix}-issue-test`, NODE,
    ["--test", "test/issue.test.mjs"], materialized.repository, materialized.env);
  const regression = runCommand(records, `${prefix}-regression-test`, NODE,
    ["--test", "test/regression.test.mjs"], materialized.repository, materialized.env);
  return Object.freeze({ issue, regression });
}

function validateBaseFailure(tests) {
  const expectedBytes = assertExactFile(
    EXPECTED_BASE_FAILURE_PATH,
    EXPECTED_BASE_FAILURE_IDENTITY,
    "EXPECTED_BASE_FAILURE_IDENTITY_DRIFT",
  );
  const expected = parseJsonNoDuplicates(expectedBytes, expectedBytes.length, "EXPECTED_BASE_FAILURE");
  expectStatus(tests.issue, expected.expected_exit_status, "BASE_ISSUE_STATUS_MISMATCH");
  expectStatus(tests.regression, 0, "BASE_REGRESSION_STATUS_MISMATCH");
  const combined = outputText(tests.issue);
  for (const token of expected.required_output_tokens) {
    assert(combined.includes(token), "BASE_FAILURE_REQUIRED_TOKEN_MISSING", token);
  }
  for (const token of expected.forbidden_output_tokens) {
    assert(!combined.includes(token), "BASE_FAILURE_FORBIDDEN_TOKEN_PRESENT", token);
  }
}

function parseProviderResponse(responseBytes) {
  try {
    const selection = parseChatCompletion(responseBytes);
    return Object.freeze({ status: "ACCEPTED", reason_code: null, selection });
  } catch (error) {
    const responseRejection = error instanceof AdapterError &&
      (error.code.startsWith("JSON_") || error.code.startsWith("RAW_RESPONSE_") ||
        RESPONSE_REJECTION_CODES.has(error.code));
    if (!responseRejection) throw error;
    return Object.freeze({ status: "REJECTED", reason_code: error.code, selection: null });
  }
}

function assertTargetIdentity(path, expected) {
  const bytes = readRegular(path, Math.max(expected.byte_length, 4096));
  assert(sameIdentity(identity(bytes), expected), "TARGET_IDENTITY_DRIFT");
  return bytes;
}

function applyCompilerOutcome(materialized, compiler) {
  const target = join(materialized.repository, "src/range.mjs");
  assertTargetIdentity(target, SOURCE_FILES[0]);
  if (compiler === null || compiler.postimage === null) {
    return Object.freeze({ mutation_applied: false, postimage_identity: null });
  }
  const replacement = join(materialized.repository, "src/range.mjs.p1-062-replacement");
  const replacementReceipt = writeCreateOnce(replacement, compiler.postimage, 0o644);
  renameSync(replacement, target);
  const installed = assertTargetIdentity(target, replacementReceipt);
  return Object.freeze({ mutation_applied: true, postimage_identity: identity(installed) });
}

function verifyAndRollback(records, materialized, mutationApplied) {
  const changed = runCommand(records, "selected-status", GIT,
    ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materialized.repository, materialized.env);
  const changedPaths = parseStatus(changed);
  assert(JSON.stringify(changedPaths) === JSON.stringify(mutationApplied ? ["src/range.mjs"] : []),
    "SELECTED_CHANGED_PATHS_MISMATCH");
  const restore = runCommand(records, "rollback-restore", GIT,
    ["restore", "--source=HEAD", "--staged", "--worktree", "--", "src/range.mjs"],
    materialized.repository, materialized.env);
  expectStatus(restore, 0, "ROLLBACK_RESTORE_FAILED");
  const head = runCommand(records, "rollback-head", GIT, ["rev-parse", "HEAD"], materialized.repository,
    materialized.env);
  const tree = runCommand(records, "rollback-tree", GIT, ["rev-parse", "HEAD^{tree}"], materialized.repository,
    materialized.env);
  const status = runCommand(records, "rollback-status", GIT,
    ["status", "--porcelain=v1", "-z", "--untracked-files=all"], materialized.repository, materialized.env);
  expectStatus(head, 0, "ROLLBACK_IDENTITY_QUERY_FAILED");
  expectStatus(tree, 0, "ROLLBACK_IDENTITY_QUERY_FAILED");
  assert(trimmedOutput(head) === EXPECTED_BASE_COMMIT && trimmedOutput(tree) === EXPECTED_BASE_TREE,
    "ROLLBACK_BASE_IDENTITY_MISMATCH");
  assert(parseStatus(status).length === 0, "ROLLBACK_NOT_CLEAN");
  assertTargetIdentity(join(materialized.repository, "src/range.mjs"), SOURCE_FILES[0]);
  return Object.freeze({ changed_paths: Object.freeze(changedPaths) });
}

function stableProjection(provider, parsed, compiler, application, selectedTests, rollback) {
  const selection = parsed.selection;
  return Object.freeze({
    schema: "P1-062-REPLAY-STABLE-PROJECTION/1",
    replay_version: REPLAY_VERSION,
    adapter_version: ADAPTER_VERSION,
    task: "SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0",
    retained_provider_response: provider.response_identity,
    parse: parsed.status === "ACCEPTED" ? Object.freeze({
      status: "ACCEPTED",
      reason_code: null,
      response_id_identity: selection.response_id_identity,
      returned_model: selection.returned_model,
      usage: selection.usage,
      content_identity: selection.content_identity,
      values: selection.values,
      program_id: selection.program_id,
      program_sha256: selection.program_sha256,
    }) : Object.freeze({
      status: "REJECTED",
      reason_code: parsed.reason_code,
      response_id_identity: null,
      returned_model: null,
      usage: null,
      content_identity: null,
      values: null,
      program_id: null,
      program_sha256: null,
    }),
    compiler: compiler === null ? null : Object.freeze({
      status: compiler.status,
      program_id: compiler.program_id,
      outcome_id: compiler.outcome_id,
      kind: compiler.kind,
      proposal_length: compiler.proposal_length,
      proposal_sha256: compiler.proposal_sha256,
      postimage_identity: compiler.postimage === null ? null : identity(compiler.postimage),
    }),
    base: Object.freeze({
      commit: EXPECTED_BASE_COMMIT,
      tree: EXPECTED_BASE_TREE,
      clean: true,
      issue_test_exit_status: 1,
      regression_test_exit_status: 0,
    }),
    selected_outcome: Object.freeze({
      mutation_applied: application.mutation_applied,
      postimage_identity: application.postimage_identity,
      changed_paths: rollback.changed_paths,
      issue_test_exit_status: selectedTests.issue.exit_status,
      regression_test_exit_status: selectedTests.regression.exit_status,
      fixed_tests_pass: selectedTests.issue.exit_status === 0 && selectedTests.regression.exit_status === 0,
    }),
    rollback: Object.freeze({
      status: "PASS",
      commit: EXPECTED_BASE_COMMIT,
      tree: EXPECTED_BASE_TREE,
      clean: true,
      source_identity: Object.freeze({
        byte_length: SOURCE_FILES[0].byte_length,
        sha256: SOURCE_FILES[0].sha256,
      }),
    }),
    execution_effects: FALSE_EXTERNAL_EFFECTS,
    claim_boundary: "ONE_RETAINED_P1_062_RESPONSE_LOCAL_FINITE_IR_REPLAY_ONLY",
  });
}

function writeCommandEvidence(evaluationRoot, records) {
  const outputRoot = join(evaluationRoot, "command-outputs");
  mkdirSync(outputRoot, { mode: 0o700 });
  const ledger = [];
  for (const record of records) {
    const stdout = writeCreateOnce(join(outputRoot, `${record.command_id}.stdout`), record.stdout);
    const stderr = writeCreateOnce(join(outputRoot, `${record.command_id}.stderr`), record.stderr);
    ledger.push({
      command_id: record.command_id,
      argv: record.argv,
      cwd: record.cwd,
      exit_status: record.exit_status,
      stdout: { path: `command-outputs/${record.command_id}.stdout`, ...identity(record.stdout) },
      stderr: { path: `command-outputs/${record.command_id}.stderr`, ...identity(record.stderr) },
    });
    assert(sameIdentity(stdout, ledger.at(-1).stdout) && sameIdentity(stderr, ledger.at(-1).stderr),
      "COMMAND_EVIDENCE_WRITE_MISMATCH");
  }
  return writeCreateOnce(join(evaluationRoot, "command-ledger.json"), canonicalJsonBytes({
    schema: "P1-062-REPLAY-COMMAND-LEDGER/1",
    commands: ledger,
    inherited_environment_used: false,
    secret_environment_available: false,
  }));
}

function safeErrorCode(error) {
  if (error instanceof ReplayError || error instanceof AdapterError) return error.code;
  return "REPLAY_INTERNAL_FAILURE";
}

export async function runReplayAtRoots({ providerRoot, callSlotPath, evaluationRoot, evaluationId }) {
  assert(process.env.P1_062_LOCAL_GATEWAY_API_KEY === undefined,
    "CREDENTIAL_ENVIRONMENT_FORBIDDEN");
  validateRunId(evaluationId);
  assert(basename(evaluationRoot) === evaluationId, "EVALUATION_RUN_ID_MISMATCH");
  assert(resolve(providerRoot) !== resolve(evaluationRoot), "PROVIDER_AND_EVALUATION_ROOT_MUST_DIFFER");
  assert(typeof callSlotPath === "string", "CALL_SLOT_PATH_REQUIRED");
  const provider = validateProviderRun(providerRoot, callSlotPath);
  const evaluationIdentity = createRunRoot(evaluationRoot);
  const records = [];
  let materialization = null;
  const startedAt = new Date().toISOString();
  try {
    assertExecutable(NODE, "NODE_TOOL_INVALID");
    assertExecutable(GIT, "GIT_TOOL_INVALID");
    const parsed = parseProviderResponse(provider.response_bytes);
    const compiler = parsed.status === "ACCEPTED" ? await compileSelection(parsed.selection) : null;

    materialization = makeMaterialization();
    const materialized = materializeRepository(materialization, records);
    const baseTests = executeFixedTests(records, "base", materialized);
    validateBaseFailure(baseTests);
    const application = applyCompilerOutcome(materialized, compiler);
    const selectedTests = executeFixedTests(records, "selected", materialized);
    const rollback = verifyAndRollback(records, materialized, application.mutation_applied);
    const projection = stableProjection(provider, parsed, compiler, application, selectedTests, rollback);
    const projectionBytes = canonicalJsonBytes(projection);

    const removedMaterializationPath = materialization.root;
    cleanupMaterialization(materialization);
    materialization = null;
    assertOwnedRunRoot(evaluationRoot, evaluationIdentity);

    const commandLedger = writeCommandEvidence(evaluationRoot, records);
    const stable = writeCreateOnce(join(evaluationRoot, "stable-projection.json"), projectionBytes);
    const receipt = writeCreateOnce(join(evaluationRoot, "replay-receipt.json"), canonicalJsonBytes({
      schema: "P1-062-REPLAY-RECEIPT/1",
      replay_version: REPLAY_VERSION,
      evaluation_id: evaluationId,
      provider_run_id: basename(provider.root),
      provider_request_identity: provider.request_identity,
      provider_egress_manifest_identity: provider.egress_manifest_identity,
      provider_response_identity: provider.response_identity,
      transport_receipt_identity: provider.transport_receipt_identity,
      http_status: provider.http_status,
      peer: provider.peer,
      parse_status: parsed.status,
      parse_reason_code: parsed.reason_code,
      fixed_tests_pass: projection.selected_outcome.fixed_tests_pass,
      rollback_status: "PASS",
      cleanup: { status: "PASS", removed_owned_materialization_path: removedMaterializationPath },
      command_ledger: { path: "command-ledger.json", ...identity(readRegular(commandLedger.path)) },
      stable_projection: { path: "stable-projection.json", ...identity(projectionBytes) },
      started_at: startedAt,
      ended_at: new Date().toISOString(),
      external_effects: FALSE_EXTERNAL_EFFECTS,
      credential_available_to_replay: false,
    }));
    const manifest = writeCreateOnce(join(evaluationRoot, "replay-evidence-manifest.json"), canonicalJsonBytes({
      schema: "P1-062-REPLAY-EVIDENCE-MANIFEST/1",
      evaluation_id: evaluationId,
      artifacts: [
        { path: "command-ledger.json", ...identity(readRegular(commandLedger.path)) },
        { path: "stable-projection.json", ...identity(projectionBytes) },
        { path: "replay-receipt.json", ...identity(readRegular(receipt.path)) },
      ],
      retained_provider_response: provider.response_identity,
      stable_projection_sha256: stable.sha256,
      create_once: true,
    }));
    return Object.freeze({
      evaluation_id: evaluationId,
      stable_projection_path: stable.path,
      stable_projection_identity: identity(projectionBytes),
      replay_receipt_path: receipt.path,
      replay_manifest_path: manifest.path,
      parse_status: parsed.status,
      fixed_tests_pass: projection.selected_outcome.fixed_tests_pass,
    });
  } catch (error) {
    if (materialization !== null && existsSync(materialization.root)) {
      cleanupMaterialization(materialization);
    }
    try {
      assertOwnedRunRoot(evaluationRoot, evaluationIdentity);
      writeCreateOnce(join(evaluationRoot, "replay-terminal-failure.json"), canonicalJsonBytes({
        schema: "P1-062-REPLAY-TERMINAL-FAILURE/1",
        evaluation_id: evaluationId,
        reason_code: safeErrorCode(error),
        started_at: startedAt,
        ended_at: new Date().toISOString(),
        external_effects: FALSE_EXTERNAL_EFFECTS,
        credential_available_to_replay: false,
      }));
    } catch {
      // Preserve the original failure; create-once Evidence may already expose the partial state.
    }
    throw error;
  }
}

export function compareReplayProjectionsAtRoots({ runARoot, runBRoot, runAId, runBId }) {
  validateRunId(runAId);
  validateRunId(runBId);
  assert(runAId !== runBId, "REPLAY_RUN_IDS_MUST_DIFFER");
  assert(basename(runARoot) === runAId && basename(runBRoot) === runBId, "REPLAY_RUN_ID_MISMATCH");
  assertRealDirectory(runARoot, "RUN_A_ROOT_INVALID");
  assertRealDirectory(runBRoot, "RUN_B_ROOT_INVALID");
  const bytesA = readRegular(join(runARoot, "stable-projection.json"), 65536);
  const bytesB = readRegular(join(runBRoot, "stable-projection.json"), 65536);
  assert(bytesA.equals(bytesB), "STABLE_PROJECTION_MISMATCH", {
    run_a: identity(bytesA),
    run_b: identity(bytesB),
  });
  const comparison = writeCreateOnce(join(runBRoot, "stable-projection-comparison.json"), canonicalJsonBytes({
    schema: "P1-062-STABLE-PROJECTION-COMPARISON/1",
    run_a_id: runAId,
    run_b_id: runBId,
    run_a_projection: identity(bytesA),
    run_b_projection: identity(bytesB),
    exact_canonical_json_byte_equality: true,
  }));
  return Object.freeze({ path: comparison.path, identity: identity(readRegular(comparison.path)) });
}

function exactArguments(argv, expectedFlags) {
  assert(argv.length === expectedFlags.length * 2, "ARGUMENT_COUNT_INVALID");
  const values = Object.create(null);
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    assert(expectedFlags.includes(flag) && values[flag] === undefined, "ARGUMENT_INVALID", flag);
    values[flag] = argv[index + 1];
  }
  for (const flag of expectedFlags) assert(typeof values[flag] === "string", "ARGUMENT_MISSING", flag);
  return values;
}

async function main(argv) {
  assert(process.env.P1_062_LOCAL_GATEWAY_API_KEY === undefined,
    "CREDENTIAL_ENVIRONMENT_FORBIDDEN");
  const command = argv[0];
  if (command === "run") {
    const values = exactArguments(argv.slice(1), ["--provider-run-id", "--evaluation-id"]);
    const providerRunId = validateRunId(values["--provider-run-id"]);
    const evaluationId = validateRunId(values["--evaluation-id"]);
    assertOwnedProductionRunRoot(providerRunId);
    const result = await runReplayAtRoots({
      providerRoot: productionRunRoot(providerRunId),
      callSlotPath: join(EVIDENCE_ROOT, "source-bearing-call-slot.json"),
      evaluationRoot: productionRunRoot(evaluationId),
      evaluationId,
    });
    process.stdout.write(canonicalJsonBytes({
      schema: "P1-062-REPLAY-CLI-RESULT/1",
      status: "COMPLETE",
      evaluation_id: result.evaluation_id,
      parse_status: result.parse_status,
      fixed_tests_pass: result.fixed_tests_pass,
      stable_projection: result.stable_projection_identity,
    }));
    return;
  }
  if (command === "compare") {
    const values = exactArguments(argv.slice(1), ["--run-a-id", "--run-b-id"]);
    const runAId = validateRunId(values["--run-a-id"]);
    const runBId = validateRunId(values["--run-b-id"]);
    const result = compareReplayProjectionsAtRoots({
      runARoot: productionRunRoot(runAId),
      runBRoot: productionRunRoot(runBId),
      runAId,
      runBId,
    });
    process.stdout.write(canonicalJsonBytes({
      schema: "P1-062-REPLAY-COMPARISON-CLI-RESULT/1",
      status: "PASS",
      comparison: result.identity,
    }));
    return;
  }
  throw new ReplayError("COMMAND_INVALID");
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(canonicalJsonBytes({
      schema: "P1-062-REPLAY-CLI-ERROR/1",
      status: "NON_PASS",
      reason_code: safeErrorCode(error),
    }));
    process.exitCode = 1;
  });
}

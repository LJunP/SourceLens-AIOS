#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  constants as fsConstants,
  closeSync,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
  realpathSync,
  statSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";

import { canonicalJson, validate } from "../schema-validator.mjs";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(MODULE_DIR, "../../..");
const FIXTURE_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-097-minimal-documented",
);
const SCHEMA_ROOT = join(REPOSITORY_ROOT, "docs/aios/schemas");
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const EXPECTED_INTERFACE_COUNTS = Object.freeze({
  request: 16,
  descriptor: 15,
  stdout: 12,
});
const EXPECTED_POSITIVE_CASES = Object.freeze([
  "B0_A", "B0_B", "B1_A", "B1_B", "B2_A", "B2_B",
]);
const REQUIRED_NEGATIVE_CASES = Object.freeze([
  "NEG_DESCRIPTOR_TAMPER",
  "NEG_MISSING_EXECUTABLE",
  "NEG_COMMAND_DRIFT",
  "NEG_INPUT_IDENTITY_TAMPER",
  "NEG_RUN_RECORD_TASK",
  "NEG_OUTPUT_UNEXPECTED_ENTRY",
  "NEG_OUTPUT_ROOT_SYMLINK",
  "NEG_NONOWNED_CLEANUP",
  "NEG_FORBIDDEN_TOOL",
  "NEG_HIDDEN_DATA",
  "NEG_NETWORK_ACCESS",
  "NEG_ARGV_NOT_ARRAY",
  "NEG_CWD_DRIFT",
  "NEG_TIMEOUT_ZERO",
  "NEG_EXPECTED_EXIT_EMPTY",
  "NEG_EFFECT_NETWORK",
  "NEG_EFFECT_PROVIDER",
  "NEG_EFFECT_SECRET",
  "NEG_EFFECT_REMOTE",
  "NEG_EFFECT_PRODUCTION",
  "NEG_EFFECT_PUBLIC",
]);
const CONFIG_FILES = Object.freeze([
  "b0-a.json", "b0-b.json", "b1-a.json",
  "b1-b.json", "b2-a.json", "b2-b.json",
]);

export class QualityNonPass extends Error {
  constructor(reason, detail = "") {
    super(detail ? `${reason}: ${detail}` : reason);
    this.name = "QualityNonPass";
    this.reason = reason;
  }
}

function fail(reason, detail = "") {
  throw new QualityNonPass(reason, detail);
}

function assert(condition, reason, detail = "") {
  if (!condition) fail(reason, detail);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function identity(bytes) {
  return { sha256: sha256(bytes), byte_length: bytes.length };
}

function exactKeys(value, keys, reason) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    reason,
    "expected object",
  );
  assert(
    isDeepStrictEqual(Object.keys(value).sort(), [...keys].sort()),
    reason,
    `keys=${Object.keys(value).sort().join(",")}`,
  );
}

function containedPath(root, path, reason) {
  assert(isAbsolute(root) && resolve(root) === root, reason);
  assert(isAbsolute(path) && resolve(path) === path, reason);
  const rel = relative(root, path);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), reason);
  return rel;
}

function safeRead(path, expectedIdentity = null, reason = "FIXTURE_READ_INVALID") {
  containedPath(REPOSITORY_ROOT, path, reason);
  let before;
  try {
    before = lstatSync(path);
  } catch (error) {
    fail(reason, error.message);
  }
  assert(before.isFile() && !before.isSymbolicLink() && before.nlink === 1, reason);
  let fd;
  try {
    fd = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
    const opened = fstatSync(fd);
    assert(
      opened.isFile() &&
        opened.nlink === 1 &&
        opened.dev === before.dev &&
        opened.ino === before.ino,
      reason,
    );
    const bytes = readFileSync(fd);
    const after = lstatSync(path);
    assert(
      after.isFile() &&
        !after.isSymbolicLink() &&
        after.dev === opened.dev &&
        after.ino === opened.ino &&
        after.size === opened.size,
      reason,
    );
    if (expectedIdentity) {
      exactKeys(expectedIdentity, ["sha256", "byte_length"], reason);
      assert(isDeepStrictEqual(identity(bytes), expectedIdentity), reason, path);
    }
    return bytes;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function readJson(path, reason = "FIXTURE_JSON_INVALID") {
  const bytes = safeRead(path, null, reason);
  try {
    return { bytes, json: JSON.parse(bytes.toString("utf8")) };
  } catch (error) {
    fail(reason, `${path}: ${error.message}`);
  }
}

function readFixture(relativePath, reason = "FIXTURE_JSON_INVALID") {
  return readJson(join(FIXTURE_ROOT, relativePath), reason);
}

function schema(name) {
  return readJson(join(SCHEMA_ROOT, name), "SCHEMA_READ_INVALID").json;
}

function assertSchema(instance, schemaName, label) {
  const errors = validate(instance, schema(schemaName));
  assert(errors.length === 0, "SCHEMA_INVALID", `${label}: ${errors.join("; ")}`);
}

function assertFalseEffects(value, reason) {
  exactKeys(value, Object.keys(FALSE_EFFECTS), reason);
  assert(isDeepStrictEqual(value, FALSE_EFFECTS), reason);
}

function verifyInterface() {
  const { json: value } = readFixture("interface.json", "INTERFACE_INVALID");
  assert(value.schema_version === "p1-097-quality-worker-interface/v1", "INTERFACE_INVALID");
  assert(value.worker_entry === "evaluation-harness/harness/p1-097-minimal-documented/run.mjs", "INTERFACE_INVALID");
  assert(
    value.request_closed_keys.length === EXPECTED_INTERFACE_COUNTS.request &&
      new Set(value.request_closed_keys).size === EXPECTED_INTERFACE_COUNTS.request,
    "INTERFACE_REQUEST_KEYS_INVALID",
  );
  assert(
    value.descriptor_closed_keys.length === EXPECTED_INTERFACE_COUNTS.descriptor &&
      new Set(value.descriptor_closed_keys).size === EXPECTED_INTERFACE_COUNTS.descriptor,
    "INTERFACE_DESCRIPTOR_KEYS_INVALID",
  );
  assert(
    value.stdout_closed_keys.length === EXPECTED_INTERFACE_COUNTS.stdout &&
      new Set(value.stdout_closed_keys).size === EXPECTED_INTERFACE_COUNTS.stdout,
    "INTERFACE_STDOUT_KEYS_INVALID",
  );
  assert(isDeepStrictEqual(value.positive_case_ids, EXPECTED_POSITIVE_CASES), "INTERFACE_POSITIVE_CASES_INVALID");
  assert(value.cli.allowed_exit_codes.PASS === 0 && value.cli.allowed_exit_codes.REJECTED === 2, "INTERFACE_EXIT_CODES_INVALID");
  return value;
}

function verifyCrossContract(task, environment, configurations) {
  assert(task.environment_snapshot_ref === environment.snapshot_id, "PREFLIGHT_ENVIRONMENT_REFERENCE_MISMATCH");
  assert(
    task.repository.identity === environment.source.repository_identity &&
      task.repository.base_commit === environment.source.base_commit &&
      task.repository.tree_hash === environment.source.tree_hash &&
      task.repository.dirty_state_policy === "clean_immutable_base" &&
      environment.source.worktree_clean === true,
    "PREFLIGHT_SOURCE_IDENTITY_MISMATCH",
  );
  assert(
    task.network_policy === environment.network.policy &&
      isDeepStrictEqual(task.allowed_network_hosts, environment.network.allowed_hosts) &&
      task.network_policy === "none",
    "PREFLIGHT_NETWORK_POLICY_MISMATCH",
  );
  const contextPath = join(REPOSITORY_ROOT, task.baseline_context.artifact_ref);
  const responsePath = join(REPOSITORY_ROOT, task.baseline_context.response_format_ref);
  assert(sha256(safeRead(contextPath)) === task.baseline_context.sha256, "PREFLIGHT_CONTEXT_IDENTITY_MISMATCH");
  assert(sha256(safeRead(responsePath)) === task.baseline_context.response_format_sha256, "PREFLIGHT_RESPONSE_IDENTITY_MISMATCH");
  assert(environment.secret_policy.values_retained === false && environment.environment_variables.secret_names_present.length === 0, "PREFLIGHT_SECRET_POLICY_INVALID");

  const environmentTools = new Set(environment.tools.map((entry) => entry.tool_id));
  for (const configuration of configurations) {
    assert(
      configuration.model_ref === environment.model.model_ref &&
        configuration.prompt_ref === environment.prompt_version &&
        configuration.policy_ref === environment.policy_version &&
        configuration.response_format_ref === task.baseline_context.response_format_ref,
      "PREFLIGHT_CONFIGURATION_BINDING_MISMATCH",
      configuration.configuration_id,
    );
    assert(
      configuration.enabled_tools.every((tool) => task.allowed_tools.includes(tool)) &&
        configuration.enabled_tools.every((tool) => environmentTools.has(tool)),
      "PREFLIGHT_TOOL_MISMATCH",
      configuration.configuration_id,
    );
    if (configuration.adapter_id === "B0") {
      assert(configuration.loop_limit === 1 && configuration.enabled_tools.length === 0, "PREFLIGHT_B0_INVALID");
    }
    if (configuration.adapter_id === "B1") {
      const forbidden = ["sourcelens_graph", "ranker", "memory", "additional_agent", "network"];
      assert(forbidden.every((key) => configuration.feature_flags[key] === false), "PREFLIGHT_B1_INVALID");
      assert(
        isDeepStrictEqual(
          configuration.enabled_tools,
          ["file_listing", "file_read", "lexical_search", "structured_patch", "verification_command"],
        ),
        "PREFLIGHT_B1_INVALID",
      );
    }
    if (configuration.adapter_id === "B2") {
      assert(
        configuration.loop_limit === 1 &&
          isDeepStrictEqual(configuration.enabled_tools, ["repository_analysis.scan"]) &&
          configuration.feature_flags.exact_accepted_p0_snapshot === true &&
          configuration.feature_flags.canonical_source_mutation === false &&
          configuration.feature_flags.network === false,
        "PREFLIGHT_B2_INVALID",
      );
    }
  }
}

function verifyPositiveInputs() {
  const task = readFixture("task-spec.json").json;
  const environment = readFixture("environment-snapshot.json").json;
  const configurations = CONFIG_FILES.map((name) =>
    readFixture(`system-configurations/${name}`).json);
  assertSchema(task, "task-spec.schema.json", "TaskSpec");
  assertSchema(environment, "environment-snapshot.schema.json", "EnvironmentSnapshot");
  configurations.forEach((configuration) =>
    assertSchema(configuration, "system-configuration.schema.json", configuration.configuration_id));
  verifyCrossContract(task, environment, configurations);

  const plan = readFixture("positive-plan.json", "POSITIVE_PLAN_INVALID").json;
  assert(plan.runs.length === 6, "POSITIVE_PLAN_INVALID");
  assert(
    isDeepStrictEqual(plan.runs.map((entry) => entry.case_id), EXPECTED_POSITIVE_CASES),
    "POSITIVE_PLAN_INVALID",
  );
  assert(new Set(plan.runs.map((entry) => entry.configuration)).size === 6, "POSITIVE_PLAN_INVALID");
  assert(new Set(plan.runs.map((entry) => entry.pair)).size === 3, "POSITIVE_PLAN_INVALID");
  assertFalseEffects(plan.requirements.external_effects, "POSITIVE_EXTERNAL_EFFECTS_INVALID");

  const b0Result = readFixture("b0-frozen-result.json", "B0_RESULT_INVALID").json;
  const responseSchema = readJson(
    join(REPOSITORY_ROOT, task.baseline_context.response_format_ref),
    "RESPONSE_SCHEMA_INVALID",
  ).json;
  const responseErrors = validate(b0Result, responseSchema);
  assert(responseErrors.length === 0, "B0_RESULT_INVALID", responseErrors.join("; "));

  const b1 = readFixture("b1-finite-program.json", "B1_PROGRAM_INVALID").json;
  assert(
    b1.expected_action_count === 6 &&
      b1.actions.length === 6 &&
      isDeepStrictEqual(
        [...new Set(b1.actions.map((entry) => entry.tool_class))],
        ["file_listing", "file_read", "lexical_search", "structured_patch", "verification_command"],
      ),
    "B1_PROGRAM_INVALID",
  );
  assertFalseEffects(b1.external_effects, "B1_EXTERNAL_EFFECTS_INVALID");
  return { task, environment, configurations, plan };
}

function gitRevParse(...args) {
  return execFileSync("/usr/bin/git", ["-C", REPOSITORY_ROOT, "rev-parse", ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function verifyB2Binding() {
  const binding = readFixture("b2-p0-binding.json", "B2_BINDING_INVALID").json;
  const manifest = readFixture("b2-p0-source-manifest.json", "B2_MANIFEST_INVALID").json;
  assert(
    binding.accepted_p0_frozen_base_commit === "09cf8dd6a1bcee138b949d117804d652000eb7cc" &&
      binding.accepted_p0_frozen_base_tree === "daa58725d293b954887dbe5b17aab5219b618658" &&
      binding.accepted_p0_checkpoint_commit === "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10" &&
      binding.accepted_p0_checkpoint_tree === "2c0956ae8598547466f691ead21532a026006bf9" &&
      binding.analyzer_tree_at_frozen_base === "408d57e9b4926f95ad059ab2675ee88dfc533096" &&
      binding.analyzer_tree_at_checkpoint === binding.analyzer_tree_at_frozen_base &&
      binding.analyzer_tree_at_p1_097_activation === binding.analyzer_tree_at_frozen_base &&
      binding.tree_equal_across_authoritative_bindings === true,
    "B2_BINDING_INVALID",
  );
  assert(gitRevParse(`${binding.accepted_p0_frozen_base_commit}^{tree}`) === binding.accepted_p0_frozen_base_tree, "B2_BINDING_INVALID");
  assert(gitRevParse(`${binding.accepted_p0_checkpoint_commit}^{tree}`) === binding.accepted_p0_checkpoint_tree, "B2_BINDING_INVALID");
  assert(gitRevParse(`${binding.accepted_p0_frozen_base_commit}:analyzer-rust`) === binding.analyzer_tree_at_frozen_base, "B2_BINDING_INVALID");
  assert(gitRevParse(`${binding.accepted_p0_checkpoint_commit}:analyzer-rust`) === binding.analyzer_tree_at_checkpoint, "B2_BINDING_INVALID");
  assert(gitRevParse("HEAD:analyzer-rust") === binding.analyzer_tree_at_p1_097_activation, "B2_BINDING_INVALID");
  assert(manifest.entries.length === manifest.entry_count && manifest.entry_count === 10, "B2_MANIFEST_INVALID");
  let bytes = 0;
  for (const entry of manifest.entries) {
    assert(SHA256_PATTERN.test(entry.sha256) && Number.isSafeInteger(entry.byte_length), "B2_MANIFEST_INVALID");
    const fileBytes = safeRead(join(REPOSITORY_ROOT, entry.path), null, "B2_SOURCE_IDENTITY_MISMATCH");
    assert(isDeepStrictEqual(identity(fileBytes), { sha256: entry.sha256, byte_length: entry.byte_length }), "B2_SOURCE_IDENTITY_MISMATCH", entry.path);
    assert(gitRevParse(`${binding.accepted_p0_frozen_base_commit}:${entry.path}`) === entry.git_blob, "B2_SOURCE_IDENTITY_MISMATCH", entry.path);
    bytes += entry.byte_length;
  }
  assert(bytes === manifest.total_byte_length, "B2_MANIFEST_INVALID");
  return { binding, manifest };
}

function verifyNegativeCatalog() {
  const catalog = readFixture("negative-cases.json", "NEGATIVE_CATALOG_INVALID").json;
  assert(
    catalog.cases.length === catalog.counts.catalog_entries &&
      catalog.cases.length === 40 &&
      catalog.minimum_required === 21 &&
      catalog.false_accepts_allowed === 0,
    "NEGATIVE_CATALOG_INVALID",
  );
  const ids = catalog.cases.map((entry) => entry.case_id);
  assert(new Set(ids).size === ids.length, "NEGATIVE_CATALOG_INVALID");
  assert(REQUIRED_NEGATIVE_CASES.every((id) => ids.includes(id)), "NEGATIVE_CATALOG_INCOMPLETE");
  const pre = catalog.cases.filter((entry) => entry.stage === "PRE_EXECUTION").length;
  const post = catalog.cases.filter((entry) => entry.stage === "POST_EXECUTION").length;
  assert(pre === catalog.counts.pre_execution && post === catalog.counts.post_execution, "NEGATIVE_CATALOG_INVALID");
  assert(catalog.cases.every((entry) => typeof entry.mutation === "string" && typeof entry.reason_code === "string"), "NEGATIVE_CATALOG_INVALID");
  return catalog;
}

export function verifyQualityFixtures() {
  const interfaceContract = verifyInterface();
  const positive = verifyPositiveInputs();
  const b2 = verifyB2Binding();
  const negative = verifyNegativeCatalog();
  const fixtureInventory = [
    "README.md",
    "interface.json",
    "negative-cases.json",
    "task-spec.json",
    "environment-snapshot.json",
    "positive-plan.json",
    "b0-frozen-result.json",
    "b1-finite-program.json",
    "b2-p0-binding.json",
    "b2-p0-source-manifest.json",
    "controlled-target.mjs",
    ...CONFIG_FILES.map((name) => `system-configurations/${name}`),
  ].map((path) => {
    const bytes = safeRead(join(FIXTURE_ROOT, path));
    return { path: `evaluation-harness/fixtures/p1-097-minimal-documented/${path}`, ...identity(bytes) };
  });
  const evaluatorInventory = [
    "quality-oracle.mjs",
    "run-matrix.mjs",
    "self-test.mjs",
  ].map((name) => {
    const path = `evaluation-harness/evaluator/p1-097-minimal-documented/${name}`;
    const bytes = safeRead(join(REPOSITORY_ROOT, path));
    return { path, ...identity(bytes) };
  });
  const inventory = [...fixtureInventory, ...evaluatorInventory];
  return {
    schema_version: "p1-097-quality-fixture-verdict/v1",
    task_id: "AIOS-P1-097_MINIMAL_DOCUMENTED_B0_B1_B2_COMPATIBILITY_ADAPTERS",
    status: "PASS",
    interface_counts: EXPECTED_INTERFACE_COUNTS,
    positive_runs: positive.plan.runs.length,
    exact_stable_pairs: new Set(positive.plan.runs.map((entry) => entry.pair)).size,
    negative_cases: negative.cases.length,
    pre_execution_negative_cases: negative.counts.pre_execution,
    post_execution_negative_cases: negative.counts.post_execution,
    b2_analyzer_tree: b2.binding.analyzer_tree_at_frozen_base,
    external_effects: FALSE_EFFECTS,
    fixture_inventory: inventory,
    fixture_manifest_sha256: sha256(
      Buffer.from(
        inventory.map((entry) => `${entry.path}\0${entry.sha256}\0${entry.byte_length}\n`).join(""),
        "utf8",
      ),
    ),
    claim_boundary: interfaceContract.claim_boundary,
  };
}

function main() {
  if (!isDeepStrictEqual(process.argv.slice(2), ["--verify-fixtures"])) {
    process.stderr.write("Usage: quality-oracle.mjs --verify-fixtures\n");
    process.exit(64);
  }
  try {
    const result = verifyQualityFixtures();
    process.stdout.write(`${canonicalJson(result)}\n`);
  } catch (error) {
    const result = {
      schema_version: "p1-097-quality-fixture-verdict/v1",
      status: "NON_PASS",
      reason_code: error instanceof QualityNonPass ? error.reason : "UNCAUGHT_EXCEPTION",
      error: `${error.name}: ${error.message}`,
    };
    process.stdout.write(`${canonicalJson(result)}\n`);
    process.exit(1);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

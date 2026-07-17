#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  cpSync,
  mkdtempSync,
  readFileSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../..");
const DATASET_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/datasets/p1-representative-task-dataset-v1");
const VALIDATOR = join(HERE, "task-dataset-validator.mjs");

const CASES = Object.freeze([
  ["M01_DATASET_VERSION_DRIFT", "DATASET_VERSION_MISMATCH", (root) => editJson(root, "dataset-manifest.json", (value) => { value.dataset_version = "1.0.1"; })],
  ["M02_TASK_POPULATION_MISSING", "TASK_POPULATION_MISMATCH", (root) => editJson(root, "dataset-manifest.json", (value) => { value.tasks.pop(); })],
  ["M03_UNDECLARED_ARTIFACT_EXTRA", "ARTIFACT_POPULATION_MISMATCH", (root) => writeFileSync(join(root, "extra.txt"), "extra\n", { flag: "wx" })],
  ["M04_TASKSPEC_HASH_DRIFT", "ARTIFACT_IDENTITY_MISMATCH", (root) => appendFileSync(join(root, "tasks/SL-P1-REP-001-RANGE-NORMALIZATION/task-spec.json"), "\n")],
  ["M05_SOURCE_HASH_DRIFT", "ARTIFACT_IDENTITY_MISMATCH", (root) => appendFileSync(join(root, "tasks/SL-P1-REP-002-CONFIG-VALIDATION/source-template/src/config.mjs"), "\n")],
  ["M06_SPLIT_COUNT_DRIFT", "SPLIT_COUNT_MISMATCH", (root) => editJson(root, "dataset-manifest.json", (value) => { value.split_counts.development = 5; })],
  ["M07_DUPLICATE_TASK_ID", "TASK_ID_DUPLICATE", (root) => editJson(root, "dataset-manifest.json", (value) => { value.tasks[5].task_id = value.tasks[0].task_id; })],
  ["M08_ARCHETYPE_COVERAGE_MISSING", "ARCHETYPE_COVERAGE_MISMATCH", (root) => editJson(root, "dataset-manifest.json", (value) => { value.tasks[5].archetype = "bounded_logic_bug_fix"; })],
  ["M09_PROVENANCE_MISSING", "PROVENANCE_INVALID", (root) => editJson(root, "tasks/SL-P1-REP-003-SAFE-PATH-JOIN/task-spec.json", (value) => { value.source.provenance = ""; })],
  ["M10_PATH_ESCAPE", "PATH_CONTAINMENT_VIOLATION", (root) => editJson(root, "dataset-manifest.json", (value) => { value.tasks[0].task_spec_path = "../outside.json"; })],
  ["M11_SYMLINK_ARTIFACT", "SYMLINK_FORBIDDEN", (root) => {
    const target = join(root, "tasks/SL-P1-REP-004-COMMAND-RESULT-MAPPING/source-template/src/result.mjs");
    unlinkSync(target);
    symlinkSync(join(root, "shared/baseline-context.json"), target);
  }],
  ["M12_EXPECTED_FAILURE_ORACLE_DRIFT", "BASE_FAILURE_ORACLE_MISMATCH", (root) => editJson(root, "tasks/SL-P1-REP-005-PROFILE-DISPLAY-NAME/expected-base-failure.json", (value) => { value.assertion_id = "REP005_UNDECLARED"; })],
]);

let assertions = 0;
function assert(condition, message) {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
  assertions += 1;
}

function editJson(root, relativePath, mutate) {
  const path = join(root, relativePath);
  const value = JSON.parse(readFileSync(path, "utf8"));
  mutate(value);
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, { flag: "w" });
}

function invoke(datasetRoot) {
  const execution = spawnSync(process.execPath, [VALIDATOR, "--dataset-root", datasetRoot], {
    cwd: REPOSITORY_ROOT,
    encoding: "utf8",
    env: { PATH: process.env.PATH ?? "" },
    timeout: 120_000,
    maxBuffer: 1024 * 1024,
  });
  assert(execution.signal === null, "validator must not terminate by signal");
  assert(execution.stderr === "", "validator stderr must remain empty");
  assert(typeof execution.stdout === "string" && execution.stdout.endsWith("\n"), "validator must emit one newline-terminated result");
  return { status: execution.status, bytes: execution.stdout, result: JSON.parse(execution.stdout) };
}

const positive = invoke(DATASET_ROOT);
assert(positive.status === 0, "frozen dataset must exit 0");
assert(positive.result.verdict === "PASS", "frozen dataset must PASS");

const replay = invoke(DATASET_ROOT);
assert(replay.status === 0, "frozen dataset replay must exit 0");
assert(replay.result.verdict === "PASS", "frozen dataset replay must PASS");
assert(replay.bytes === positive.bytes, "unchanged validation output must be byte-identical");

const results = [];
for (const [caseId, expectedReason, mutate] of CASES) {
  const mutationRoot = mkdtempSync(join(tmpdir(), `sourcelens-p1-035-${caseId.toLowerCase()}-`));
  cpSync(DATASET_ROOT, mutationRoot, { recursive: true, force: false, errorOnExist: false });
  mutate(mutationRoot);
  const observed = invoke(mutationRoot);
  assert(observed.status === 2, `${caseId} must exit 2`);
  assert(observed.result.verdict === "FAIL", `${caseId} must FAIL`);
  assert(observed.result.reason_code === expectedReason, `${caseId} expected ${expectedReason}, got ${observed.result.reason_code}`);
  results.push({ case_id: caseId, verdict: observed.result.verdict, reason_code: observed.result.reason_code, exit_status: observed.status });
}

process.stdout.write(`${JSON.stringify({
  schema_version: "1.0",
  self_test: "PASS",
  assertions,
  positive_verdict: positive.result.verdict,
  replay_byte_equal: replay.bytes === positive.bytes,
  mutation_cases_passed: results.length,
  mutation_results: results,
})}\n`);

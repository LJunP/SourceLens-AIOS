#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  cpSync,
  lstatSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, posix, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalJson, validate } from "../evaluator/schema-validator.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../..");
const DEFAULT_DATASET_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/datasets/p1-representative-task-dataset-v1");
const TASK_SPEC_SCHEMA_PATH = join(REPOSITORY_ROOT, "docs/aios/schemas/task-spec.schema.json");
const VALIDATOR_VERSION = "AIOS-P1-035-DATASET-VALIDATOR/1.0.0";
const DATASET_ID = "SOURCELENS-P1-REPRESENTATIVE-TASKS";
const DATASET_VERSION = "1.0.0";
const CLAIM_BOUNDARY = "P1_EXIT_CAPABILITY_ENGINEERING_ARTIFACT_ONLY_NO_BENCHMARK_AGENT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM";
const QUALITY_FREEZE_RECEIPT_SHA256 = "d509da3a7d8fba22b49d98ed9d5ced9e804a1541b4c427674f6c8a6950f41f9d";
const QUALITY_FREEZE_RECEIPT_BYTES = 1571;
const EXPECTED_SPLITS = Object.freeze({ development: 4, validation: 2, hidden: 0 });
const EXPECTED_ARCHETYPES = Object.freeze([
  "behavior_preserving_refactor",
  "bounded_logic_bug_fix",
  "deterministic_error_handling",
  "input_contract_validation",
  "multi_file_behavior_change",
  "path_containment_security_fix",
]);

const EXPECTED_TASKS = Object.freeze({
  "SL-P1-REP-001-RANGE-NORMALIZATION": Object.freeze({
    split: "development", archetype: "bounded_logic_bug_fix",
    commit: "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f", tree: "900814727113d65f5dad8b63222e14f39b2cf38b",
    assertion: "REP001_NEGATIVE_RANGE_ORDER",
  }),
  "SL-P1-REP-002-CONFIG-VALIDATION": Object.freeze({
    split: "development", archetype: "input_contract_validation",
    commit: "10ad29f28c4358759711f78021b5ee897658f913", tree: "e8611a442b405a9cc5180d2675b090618ea66d5b",
    assertion: "REP002_REJECT_UNKNOWN_KEYS",
  }),
  "SL-P1-REP-003-SAFE-PATH-JOIN": Object.freeze({
    split: "development", archetype: "path_containment_security_fix",
    commit: "10c8d9177404a85d845e7f4f207ac61cbd2538fc", tree: "9a0d83cb86ce3aaed0def3d480542800641eb18e",
    assertion: "REP003_REJECT_PARENT_ESCAPE",
  }),
  "SL-P1-REP-004-COMMAND-RESULT-MAPPING": Object.freeze({
    split: "development", archetype: "deterministic_error_handling",
    commit: "289d81fede3e4ee8c3ad2b08cb8ed67135531705", tree: "4a0632cad019bfc6302ec32096bf0d3ee05ac366",
    assertion: "REP004_PRESERVE_NONZERO_EXIT",
  }),
  "SL-P1-REP-005-PROFILE-DISPLAY-NAME": Object.freeze({
    split: "validation", archetype: "multi_file_behavior_change",
    commit: "bd50586883fda10c974bd6944c502945019da99e", tree: "152201a4e29bca172c713b0669d807e3b0fc4fb3",
    assertion: "REP005_FORMAT_NAME_ACROSS_MODULES",
  }),
  "SL-P1-REP-006-DEDUPE-REFACTOR": Object.freeze({
    split: "validation", archetype: "behavior_preserving_refactor",
    commit: "dd71c92a04693e60f1cb30d577107205411cbed3", tree: "78327e74c83aed97eddcc7485dcf985865c2b815",
    assertion: "REP006_DEDUPE_PRESERVES_ORDER",
  }),
});

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function pass(metrics) {
  return {
    schema_version: "1.0",
    validator_version: VALIDATOR_VERSION,
    verdict: "PASS",
    reason_code: null,
    claim_boundary: CLAIM_BOUNDARY,
    metrics,
  };
}

function fail(reasonCode, detail) {
  return {
    schema_version: "1.0",
    validator_version: VALIDATOR_VERSION,
    verdict: "FAIL",
    reason_code: reasonCode,
    detail,
    claim_boundary: CLAIM_BOUNDARY,
  };
}

function safeRelativePath(path) {
  if (typeof path !== "string" || path.length === 0 || path.includes("\\")) return false;
  if (posix.isAbsolute(path)) return false;
  const normalized = posix.normalize(path);
  return normalized === path && normalized !== ".." && !normalized.startsWith("../");
}

function walkFiles(root) {
  const files = [];
  let symlink = null;
  function walk(current) {
    for (const entry of readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const absolute = join(current, entry.name);
      const rel = relative(root, absolute).split(sep).join("/");
      const status = lstatSync(absolute);
      if (status.isSymbolicLink()) {
        symlink ??= rel;
      } else if (status.isDirectory()) {
        walk(absolute);
      } else if (status.isFile()) {
        files.push(rel);
      }
    }
  }
  walk(root);
  return { files: files.sort(), symlink };
}

function run(argv, cwd, options = {}) {
  const execution = spawnSync(argv[0], argv.slice(1), {
    cwd,
    encoding: "utf8",
    env: options.env ?? { PATH: process.env.PATH ?? "" },
    timeout: options.timeout ?? 10_000,
    maxBuffer: 1024 * 1024,
  });
  return {
    argv,
    cwd,
    status: execution.status,
    signal: execution.signal,
    error: execution.error?.message ?? null,
    stdout: execution.stdout ?? "",
    stderr: execution.stderr ?? "",
  };
}

function commandPassed(execution) {
  return execution.error === null && execution.signal === null && execution.status === 0;
}

function materializeTask(datasetRoot, manifestTask, expected) {
  const taskRoot = join(datasetRoot, "tasks", manifestTask.task_id);
  const sourceRoot = join(taskRoot, "source-template");
  const repository = mkdtempSync(join(tmpdir(), "sourcelens-p1-035-materialize-"));
  cpSync(sourceRoot, repository, { recursive: true, force: false, errorOnExist: false });

  const git = "/usr/bin/git";
  const deterministicEnvironment = {
    PATH: process.env.PATH ?? "",
    GIT_AUTHOR_NAME: "SourceLens AIOS Fixture",
    GIT_AUTHOR_EMAIL: "fixture@sourcelens.local",
    GIT_AUTHOR_DATE: "2000-01-01T00:00:00Z",
    GIT_COMMITTER_NAME: "SourceLens AIOS Fixture",
    GIT_COMMITTER_EMAIL: "fixture@sourcelens.local",
    GIT_COMMITTER_DATE: "2000-01-01T00:00:00Z",
  };
  const init = run([git, "init", "-q"], repository, { env: deterministicEnvironment });
  const add = run([git, "add", "--all"], repository, { env: deterministicEnvironment });
  const commit = run([git, "-c", "commit.gpgsign=false", "commit", "-qm", "fixture: base"], repository, { env: deterministicEnvironment });
  if (![init, add, commit].every(commandPassed)) {
    return { failure: fail("MATERIALIZATION_COMMAND_FAILED", `${manifestTask.task_id} git materialization failed`), repository };
  }

  const commitIdentity = run([git, "rev-parse", "HEAD"], repository, { env: deterministicEnvironment });
  const treeIdentity = run([git, "rev-parse", "HEAD^{tree}"], repository, { env: deterministicEnvironment });
  const clean = run([git, "status", "--porcelain"], repository, { env: deterministicEnvironment });
  if (!commandPassed(commitIdentity) || !commandPassed(treeIdentity) || !commandPassed(clean) || clean.stdout !== "") {
    return { failure: fail("MATERIALIZATION_IDENTITY_FAILED", `${manifestTask.task_id} materialization identity is unavailable or dirty`), repository };
  }
  const actualCommit = commitIdentity.stdout.trim();
  const actualTree = treeIdentity.stdout.trim();
  if (actualCommit !== expected.commit || actualTree !== expected.tree) {
    return { failure: fail("SOURCE_IDENTITY_MISMATCH", `${manifestTask.task_id} expected ${expected.commit}:${expected.tree}, got ${actualCommit}:${actualTree}`), repository };
  }

  const oracle = readJson(join(taskRoot, "expected-base-failure.json"));
  const taskSpec = readJson(join(taskRoot, "task-spec.json"));
  const issueCommand = taskSpec.verification.required_commands.find((item) => item.command_id === "issue-test");
  const regressionCommand = taskSpec.verification.required_commands.find((item) => item.command_id === "regression-test");
  if (!issueCommand || !regressionCommand) {
    return { failure: fail("REQUIRED_COMMAND_MISSING", `${manifestTask.task_id} lacks issue or regression command`), repository };
  }

  const baseIssue = run(issueCommand.argv, repository, { timeout: issueCommand.timeout_seconds * 1000 });
  const baseOutput = `${baseIssue.stdout}\n${baseIssue.stderr}`;
  const baseTyped = baseIssue.error === null
    && baseIssue.signal === null
    && baseIssue.status === oracle.expected_exit_status
    && oracle.required_output_tokens.every((token) => baseOutput.includes(token === "exact assertion_id" ? oracle.assertion_id : token))
    && oracle.forbidden_output_tokens.every((token) => !baseOutput.includes(token));
  if (!baseTyped) {
    return { failure: fail("BASE_FAILURE_SANITY_MISMATCH", `${manifestTask.task_id} did not produce the frozen typed base failure`), repository };
  }

  const baseRegression = run(regressionCommand.argv, repository, { timeout: regressionCommand.timeout_seconds * 1000 });
  if (!commandPassed(baseRegression)) {
    return { failure: fail("BASE_REGRESSION_FAILED", `${manifestTask.task_id} base regression command failed`), repository };
  }

  const patchPath = join(taskRoot, "reference-solution.patch");
  const patchCheck = run([git, "apply", "--check", patchPath], repository, { env: deterministicEnvironment });
  const patchApply = commandPassed(patchCheck)
    ? run([git, "apply", patchPath], repository, { env: deterministicEnvironment })
    : patchCheck;
  if (!commandPassed(patchCheck) || !commandPassed(patchApply)) {
    return { failure: fail("REFERENCE_PATCH_APPLY_FAILED", `${manifestTask.task_id} reference patch did not apply`), repository };
  }

  const changed = run([git, "diff", "--name-only"], repository, { env: deterministicEnvironment });
  if (!commandPassed(changed) || changed.stdout.split("\n").filter(Boolean).some((path) => path.startsWith("test/"))) {
    return { failure: fail("REFERENCE_PATCH_SCOPE_VIOLATION", `${manifestTask.task_id} reference patch changes tests or cannot be inspected`), repository };
  }

  const solvedIssue = run(issueCommand.argv, repository, { timeout: issueCommand.timeout_seconds * 1000 });
  const solvedRegression = run(regressionCommand.argv, repository, { timeout: regressionCommand.timeout_seconds * 1000 });
  if (!commandPassed(solvedIssue) || !commandPassed(solvedRegression)) {
    return { failure: fail("SOLVED_STATE_WITNESS_FAILED", `${manifestTask.task_id} reference patch does not solve both command classes`), repository };
  }

  return {
    repository,
    commit: actualCommit,
    tree: actualTree,
    base_failure: "PASS",
    solved_state: "PASS",
  };
}

export function validateDataset(datasetRoot = DEFAULT_DATASET_ROOT) {
  try {
    const root = resolve(datasetRoot);
    const rootStatus = lstatSync(root);
    if (!rootStatus.isDirectory() || rootStatus.isSymbolicLink()) return fail("DATASET_ROOT_INVALID", root);

    const manifestPath = join(root, "dataset-manifest.json");
    const receiptPath = join(root, "QUALITY_FREEZE_RECEIPT.json");
    const manifest = readJson(manifestPath);

    if (manifest.dataset_id !== DATASET_ID) return fail("DATASET_ID_MISMATCH", String(manifest.dataset_id));
    if (manifest.dataset_version !== DATASET_VERSION) return fail("DATASET_VERSION_MISMATCH", String(manifest.dataset_version));
    if (manifest.task_count !== 6 || !Array.isArray(manifest.tasks) || manifest.tasks.length !== 6) {
      return fail("TASK_POPULATION_MISMATCH", "manifest must declare exactly six tasks");
    }
    if (JSON.stringify(manifest.split_counts) !== JSON.stringify(EXPECTED_SPLITS)) {
      return fail("SPLIT_COUNT_MISMATCH", JSON.stringify(manifest.split_counts));
    }
    const taskIds = manifest.tasks.map((task) => task.task_id);
    if (new Set(taskIds).size !== taskIds.length) return fail("TASK_ID_DUPLICATE", "task IDs must be unique");
    if (JSON.stringify([...taskIds].sort()) !== JSON.stringify(Object.keys(EXPECTED_TASKS).sort())) {
      return fail("TASK_POPULATION_MISMATCH", "task ID population differs from the frozen set");
    }
    const archetypes = manifest.tasks.map((task) => task.archetype).sort();
    if (JSON.stringify(archetypes) !== JSON.stringify(EXPECTED_ARCHETYPES)) {
      return fail("ARCHETYPE_COVERAGE_MISMATCH", JSON.stringify(archetypes));
    }
    for (const task of manifest.tasks) {
      if (!safeRelativePath(task.task_spec_path)) return fail("PATH_CONTAINMENT_VIOLATION", String(task.task_spec_path));
      const expectedPath = `tasks/${task.task_id}/task-spec.json`;
      if (task.task_spec_path !== expectedPath) return fail("PATH_CONTAINMENT_VIOLATION", String(task.task_spec_path));
    }

    const walked = walkFiles(root);
    if (walked.symlink !== null) return fail("SYMLINK_FORBIDDEN", walked.symlink);
    const declaredFiles = [...manifest.artifacts.map((artifact) => artifact.path), "dataset-manifest.json", "QUALITY_FREEZE_RECEIPT.json"].sort();
    if (JSON.stringify(walked.files) !== JSON.stringify(declaredFiles)) {
      return fail("ARTIFACT_POPULATION_MISMATCH", "actual file population differs from the manifest");
    }

    const taskSpecSchema = readJson(TASK_SPEC_SCHEMA_PATH);
    for (const task of manifest.tasks) {
      const expected = EXPECTED_TASKS[task.task_id];
      if (task.split !== expected.split || task.base_commit !== expected.commit || task.tree_hash !== expected.tree) {
        return fail("TASK_IDENTITY_MISMATCH", task.task_id);
      }
      const spec = readJson(join(root, task.task_spec_path));
      if (typeof spec.source?.provenance !== "string" || spec.source.provenance.length === 0) {
        return fail("PROVENANCE_INVALID", task.task_id);
      }
      if (spec.task_id !== task.task_id || spec.dataset_version !== DATASET_VERSION || spec.evaluation_split !== task.split) {
        return fail("TASK_SPEC_LINKAGE_MISMATCH", task.task_id);
      }
      if (spec.repository.base_commit !== task.base_commit || spec.repository.tree_hash !== task.tree_hash) {
        return fail("TASK_SPEC_LINKAGE_MISMATCH", task.task_id);
      }
      const oracle = readJson(join(root, "tasks", task.task_id, "expected-base-failure.json"));
      if (oracle.assertion_id !== expected.assertion || oracle.assertion_id !== task.assertion_id) {
        return fail("BASE_FAILURE_ORACLE_MISMATCH", task.task_id);
      }
      const specErrors = validate(spec, taskSpecSchema);
      if (specErrors.length > 0) return fail("TASK_SPEC_SCHEMA_INVALID", `${task.task_id}: ${specErrors.join("; ")}`);
    }

    if (!Array.isArray(manifest.artifacts) || manifest.artifact_count !== manifest.artifacts.length) {
      return fail("ARTIFACT_POPULATION_MISMATCH", "artifact count does not match artifact list");
    }
    for (const artifact of manifest.artifacts) {
      if (!safeRelativePath(artifact.path)) return fail("PATH_CONTAINMENT_VIOLATION", String(artifact.path));
      const bytes = readFileSync(join(root, artifact.path));
      if (bytes.length !== artifact.byte_length || sha256(bytes) !== artifact.sha256) {
        return fail("ARTIFACT_IDENTITY_MISMATCH", artifact.path);
      }
    }

    const receiptBytes = readFileSync(receiptPath);
    if (receiptBytes.length !== QUALITY_FREEZE_RECEIPT_BYTES || sha256(receiptBytes) !== QUALITY_FREEZE_RECEIPT_SHA256) {
      return fail("QUALITY_FREEZE_RECEIPT_MISMATCH", "freeze receipt bytes differ from the Worker-bound identity");
    }
    const receipt = JSON.parse(receiptBytes.toString("utf8"));
    const manifestBytes = readFileSync(manifestPath);
    const ownershipBytes = readFileSync(join(root, "OWNERSHIP_MAP.json"));
    const population = manifest.artifacts.map((artifact) => `${artifact.path}\0${artifact.sha256}\0${artifact.byte_length}\n`).join("");
    if (receipt.dataset_manifest.sha256 !== sha256(manifestBytes)
      || receipt.dataset_manifest.byte_length !== manifestBytes.length
      || receipt.ownership_map.sha256 !== sha256(ownershipBytes)
      || receipt.ownership_map.byte_length !== ownershipBytes.length
      || receipt.artifact_count !== manifest.artifacts.length
      || receipt.artifact_population_sha256 !== sha256(Buffer.from(population))) {
      return fail("QUALITY_FREEZE_BINDING_MISMATCH", "freeze receipt does not bind the current manifest population");
    }

    const datasetSchema = readJson(join(root, "dataset.schema.json"));
    const manifestErrors = validate(manifest, datasetSchema);
    if (manifestErrors.length > 0) return fail("DATASET_MANIFEST_SCHEMA_INVALID", manifestErrors.join("; "));
    if (manifest.claim_boundary !== CLAIM_BOUNDARY || receipt.claim_boundary !== CLAIM_BOUNDARY) {
      return fail("CLAIM_BOUNDARY_MISMATCH", "dataset or receipt claim boundary drifted");
    }

    let materializations = 0;
    let baseFailures = 0;
    let solvedStates = 0;
    for (const task of manifest.tasks) {
      const first = materializeTask(root, task, EXPECTED_TASKS[task.task_id]);
      if (first.failure) return first.failure;
      const second = materializeTask(root, task, EXPECTED_TASKS[task.task_id]);
      if (second.failure) return second.failure;
      try {
        if (first.commit !== second.commit || first.tree !== second.tree) {
          return fail("MATERIALIZATION_REPLAY_MISMATCH", task.task_id);
        }
        materializations += 2;
        baseFailures += 1;
        solvedStates += 1;
      } finally {
        rmSync(first.repository, { recursive: true, force: true });
        rmSync(second.repository, { recursive: true, force: true });
      }
    }

    return pass({
      task_specs_schema_valid: 6,
      deterministic_materializations: materializations,
      exact_commit_tree_replays: 6,
      base_failure_sanity_checks: baseFailures,
      solved_state_witnesses: solvedStates,
      declared_archetypes_covered: 6,
      split_counts: EXPECTED_SPLITS,
      artifact_count: manifest.artifacts.length,
    });
  } catch (error) {
    return fail("VALIDATOR_INPUT_OR_RUNTIME_ERROR", error instanceof Error ? error.message : String(error));
  }
}

function parseArguments(argv) {
  if (argv.length === 0) return { datasetRoot: DEFAULT_DATASET_ROOT };
  if (argv.length === 2 && argv[0] === "--dataset-root") return { datasetRoot: argv[1] };
  throw new Error("usage: task-dataset-validator.mjs [--dataset-root PATH]");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const { datasetRoot } = parseArguments(process.argv.slice(2));
    const result = validateDataset(datasetRoot);
    process.stdout.write(`${canonicalJson(result)}\n`);
    process.exitCode = result.verdict === "PASS" ? 0 : 2;
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 3;
  }
}

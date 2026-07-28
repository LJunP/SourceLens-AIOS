import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import {
  REPOSITORY_ROOT,
  assert,
  bytesIdentity,
  canonicalBytes,
  cleanupOwnedRoot,
  copyClosedTree,
  createDisposableRoot,
  listClosedFiles,
  runBoundedCommand,
  safeRegularFile,
  sha256,
} from "./core.mjs";
import {
  buildNormalizedProviderResponse,
  patchIrBytes,
} from "./patch-ir-v2.mjs";
import {
  COMPILER_VERSION as V1_COMPILER_VERSION,
  compileFiniteTypedPatchIr,
} from "../finite-typed-patch-ir-v1/compiler.mjs";

export const DATASET_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1",
);
export const DATASET_MANIFEST_PATH = join(DATASET_ROOT, "dataset-manifest.json");
export const DATASET_MANIFEST_SHA256 =
  "22f252319ed066655b05142a391709741703e01fbb4d6b5ebfbbcb6acd782be6";
export const ACCEPTED_TASK_IDS = Object.freeze([
  "SL-P1-REP-001-RANGE-NORMALIZATION",
  "SL-P1-REP-002-CONFIG-VALIDATION",
  "SL-P1-REP-003-SAFE-PATH-JOIN",
  "SL-P1-REP-004-COMMAND-RESULT-MAPPING",
  "SL-P1-REP-005-PROFILE-DISPLAY-NAME",
  "SL-P1-REP-006-DEDUPE-REFACTOR",
]);

function acceptedManifest() {
  const path = safeRegularFile(DATASET_MANIFEST_PATH, "accepted dataset manifest");
  const bytes = readFileSync(path);
  assert(
    bytes.length === 15313 && sha256(bytes) === DATASET_MANIFEST_SHA256,
    "ACCEPTED_DATASET_DRIFT",
    "accepted P1-035 dataset manifest identity drifted",
  );
  const manifest = JSON.parse(bytes.toString("utf8"));
  assert(
    manifest.dataset_id === "SOURCELENS-P1-REPRESENTATIVE-TASKS"
      && manifest.dataset_version === "1.0.0"
      && manifest.task_count === 6
      && JSON.stringify(manifest.tasks.map((entry) => entry.task_id))
        === JSON.stringify(ACCEPTED_TASK_IDS),
    "ACCEPTED_DATASET_DRIFT",
    "accepted P1-035 dataset task set drifted",
  );
  return { manifest, bytes };
}

function artifactMap(manifest) {
  return new Map(manifest.artifacts.map((artifact) => [artifact.path, artifact]));
}

function verifyDatasetArtifact(manifest, relativePath, label) {
  const expected = artifactMap(manifest).get(relativePath);
  assert(expected, "ACCEPTED_DATASET_DRIFT", `${label} is absent from the accepted manifest`);
  const path = safeRegularFile(join(DATASET_ROOT, ...relativePath.split("/")), label);
  const bytes = readFileSync(path);
  assert(
    bytes.length === expected.byte_length && sha256(bytes) === expected.sha256,
    "ACCEPTED_DATASET_DRIFT",
    `${label} identity drifted`,
  );
  return { path, bytes, identity: { path: relativePath, ...bytesIdentity(bytes) } };
}

export function loadAcceptedTask(taskId) {
  assert(ACCEPTED_TASK_IDS.includes(taskId), "UNKNOWN_TASK_REJECTED", "task is outside the accepted six-task set");
  const { manifest, bytes: manifestBytes } = acceptedManifest();
  const entry = manifest.tasks.find((candidate) => candidate.task_id === taskId);
  const taskArtifact = verifyDatasetArtifact(manifest, entry.task_spec_path, `${taskId} TaskSpec`);
  const task = JSON.parse(taskArtifact.bytes.toString("utf8"));
  assert(
    task.task_id === taskId
      && task.dataset_version === manifest.dataset_version
      && task.repository.base_commit === entry.base_commit
      && task.repository.tree_hash === entry.tree_hash,
    "ACCEPTED_TASK_BINDING_DRIFT",
    "TaskSpec no longer matches the accepted manifest",
  );
  const referencePath = `tasks/${taskId}/reference-solution.patch`;
  const reference = verifyDatasetArtifact(manifest, referencePath, `${taskId} accepted reference patch`);
  const sourceRoot = join(DATASET_ROOT, "tasks", taskId, "source-template");
  const sourceFiles = listClosedFiles(sourceRoot);
  const acceptedArtifacts = artifactMap(manifest);
  for (const file of sourceFiles) {
    const relativePath = `tasks/${taskId}/source-template/${file.path}`;
    const expected = acceptedArtifacts.get(relativePath);
    assert(
      expected
        && expected.sha256 === file.sha256
        && expected.byte_length === file.byte_length,
      "ACCEPTED_DATASET_DRIFT",
      `source file is not exact accepted P1-035 bytes: ${relativePath}`,
    );
  }
  return {
    manifest,
    manifest_identity: bytesIdentity(manifestBytes),
    entry,
    task,
    task_spec: taskArtifact,
    reference_patch: reference,
    source_root: sourceRoot,
    source_files: sourceFiles,
  };
}

function sourceProfile(binding, patchedSourceRoot) {
  const existingSources = binding.source_files
    .filter((entry) => entry.path.startsWith("src/"))
    .map((entry) => ({
      path: entry.path,
      sha256: entry.sha256,
      byte_length: entry.byte_length,
      mode: "100644",
    }))
    .sort((left, right) => left.path.localeCompare(right.path));
  const existingPaths = new Set(existingSources.map((entry) => entry.path));
  const patchedSources = listClosedFiles(patchedSourceRoot)
    .filter((entry) => entry.path.startsWith("src/"));
  const creatablePaths = patchedSources
    .filter((entry) => !existingPaths.has(entry.path))
    .map((entry) => entry.path)
    .sort();
  assert(
    creatablePaths.length <= 1
      && (creatablePaths.length === 0 || binding.task.task_id === "SL-P1-REP-006-DEDUPE-REFACTOR"),
    "ACCEPTED_REFERENCE_SCOPE_INVALID",
    "accepted reference introduces an unsupported source path",
  );
  return {
    task_id: binding.task.task_id,
    dataset_id: binding.manifest.dataset_id,
    dataset_version: binding.manifest.dataset_version,
    dataset_manifest_sha256: DATASET_MANIFEST_SHA256,
    base_commit: binding.entry.base_commit,
    base_tree: binding.entry.tree_hash,
    task_spec_sha256: binding.task_spec.identity.sha256,
    existing_sources: existingSources,
    creatable_paths: creatablePaths,
  };
}

function buildOperations(binding, patchedRoot) {
  const beforeEntries = new Map(
    binding.source_files
      .filter((entry) => entry.path.startsWith("src/"))
      .map((entry) => [entry.path, entry]),
  );
  const afterEntries = listClosedFiles(patchedRoot)
    .filter((entry) => entry.path.startsWith("src/"));
  const operations = [];
  for (const after of afterEntries) {
    const before = beforeEntries.get(after.path);
    if (before && before.sha256 === after.sha256 && before.byte_length === after.byte_length) continue;
    const bytes = readFileSync(join(patchedRoot, ...after.path.split("/")));
    operations.push({
      op: before ? "REPLACE_REGULAR_FILE" : "CREATE_REGULAR_FILE",
      path: after.path,
      mode: "100644",
      before: before
        ? {
            kind: "REGULAR_FILE",
            sha256: before.sha256,
            byte_length: before.byte_length,
          }
        : { kind: "ABSENT" },
      postimage: {
        base64: bytes.toString("base64"),
        sha256: after.sha256,
        byte_length: after.byte_length,
      },
    });
  }
  operations.sort((left, right) => left.path.localeCompare(right.path));
  assert(
    operations.length >= 1 && operations.length <= 3,
    "ACCEPTED_REFERENCE_SCOPE_INVALID",
    "accepted reference does not fit finite Patch IR operation bounds",
  );
  return operations;
}

function applyAcceptedReference(binding, patchedRoot) {
  const apply = runBoundedCommand(
    ["/usr/bin/git", "apply", "--whitespace=nowarn", binding.reference_patch.path],
    patchedRoot,
    15,
  );
  assert(
    apply.exit_status === 0,
    "ACCEPTED_REFERENCE_APPLY_FAILED",
    "accepted reference patch did not apply",
  );
}

export function loadAcceptedCompilerProfile(taskId) {
  const binding = loadAcceptedTask(taskId);
  const disposable = createDisposableRoot("profile");
  try {
    const patchedRoot = join(disposable.root, "patched");
    copyClosedTree(binding.source_root, patchedRoot);
    applyAcceptedReference(binding, patchedRoot);
    return sourceProfile(binding, patchedRoot);
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

export function buildAcceptedReferenceResponse(taskId, responseId = `P1-149-${taskId}`) {
  const binding = loadAcceptedTask(taskId);
  const disposable = createDisposableRoot("reference");
  try {
    const patchedRoot = join(disposable.root, "patched");
    copyClosedTree(binding.source_root, patchedRoot);
    applyAcceptedReference(binding, patchedRoot);
    const profile = sourceProfile(binding, patchedRoot);
    const ir = {
      schema_version: "SL-PATCH-IR/2",
      dataset: {
        id: binding.manifest.dataset_id,
        version: binding.manifest.dataset_version,
        manifest_sha256: DATASET_MANIFEST_SHA256,
      },
      task: {
        task_id: taskId,
        base_commit: binding.entry.base_commit,
        base_tree: binding.entry.tree_hash,
        task_spec_sha256: binding.task_spec.identity.sha256,
      },
      operations: buildOperations(binding, patchedRoot),
    };
    const irBytes = patchIrBytes(ir);
    const responseBytes = buildNormalizedProviderResponse({
      responseId,
      taskId,
      patchIrBytes: irBytes,
    });
    return {
      binding,
      profile,
      ir,
      ir_bytes: irBytes,
      response_bytes: responseBytes,
    };
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

export function verifyAcceptedPatchIrV1Compatibility() {
  assert(
    V1_COMPILER_VERSION === "SL-PATCH-IR-TRUSTED-COMPILER/1",
    "P1_055_V1_COMPATIBILITY_DRIFT",
    "accepted P1-055 compiler version drifted",
  );
  const expectations = new Map([
    ["ir00.json", "COMPILED"],
    ["ir01.json", "IDENTITY_NO_EFFECT_REJECTION"],
    ["ir10.json", "COMPILED"],
    ["ir11.json", "COMPILED"],
  ]);
  const results = [];
  for (const [name, expectedStatus] of expectations) {
    const path = join(
      REPOSITORY_ROOT,
      "evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs",
      name,
    );
    assert(existsSync(path), "P1_055_V1_COMPATIBILITY_DRIFT", `accepted v1 program missing: ${name}`);
    const bytes = readFileSync(safeRegularFile(path, `accepted v1 ${name}`));
    const result = compileFiniteTypedPatchIr(bytes);
    assert(
      result.status === expectedStatus
        && result.proposal_sha256 === sha256(bytes)
        && result.proposal_length === bytes.length,
      "P1_055_V1_COMPATIBILITY_DRIFT",
      `accepted v1 outcome drifted: ${name}`,
    );
    const mutated = Buffer.concat([bytes, Buffer.from(" ", "utf8")]);
    const rejected = compileFiniteTypedPatchIr(mutated);
    assert(
      rejected.status === "REJECTED" && rejected.reason_code === "IR_NOT_EXACTLY_ADMITTED",
      "P1_055_V1_COMPATIBILITY_DRIFT",
      `accepted v1 mutation did not reject: ${name}`,
    );
    results.push({
      program: name,
      identity: bytesIdentity(bytes),
      expected_status: expectedStatus,
      observed_status: result.status,
      mutation_rejected: true,
    });
  }
  return {
    schema_version: "p1-149-p1-055-v1-compatibility/v1",
    compiler_version: V1_COMPILER_VERSION,
    results,
    status: "PASS",
  };
}

import { readFileSync, realpathSync } from "node:fs";
import { join } from "node:path";

import {
  assert,
  canonicalJson,
  sha256,
} from "../../harness/p1-125-six-task-parameterized/core.mjs";

export const DATASET_ROOT_RELATIVE =
  "evaluation-harness/datasets/p1-representative-task-dataset-v1";
export const DATASET_MANIFEST_SHA256 =
  "22f252319ed066655b05142a391709741703e01fbb4d6b5ebfbbcb6acd782be6";
export const PROGRAM_SET_SHA256 =
  "17b15108853e8df23155ba6f2fafc368446d643ec8857f41116c78e2f1f1e42c";

export const ACCEPTED_TASK_IDS = Object.freeze([
  "SL-P1-REP-001-RANGE-NORMALIZATION",
  "SL-P1-REP-002-CONFIG-VALIDATION",
  "SL-P1-REP-003-SAFE-PATH-JOIN",
  "SL-P1-REP-004-COMMAND-RESULT-MAPPING",
  "SL-P1-REP-005-PROFILE-DISPLAY-NAME",
  "SL-P1-REP-006-DEDUPE-REFACTOR",
]);

function loadManifest(repositoryRoot) {
  const path = join(repositoryRoot, DATASET_ROOT_RELATIVE, "dataset-manifest.json");
  const bytes = readFileSync(path);
  assert(
    sha256(bytes) === DATASET_MANIFEST_SHA256,
    "DATASET_MANIFEST_DRIFT_REJECTED",
    "accepted P1-035 dataset manifest identity drifted",
  );
  const manifest = JSON.parse(bytes.toString("utf8"));
  assert(
    manifest.dataset_id === "SOURCELENS-P1-REPRESENTATIVE-TASKS"
      && manifest.dataset_version === "1.0.0"
      && manifest.task_count === 6
      && canonicalJson(manifest.tasks.map((entry) => entry.task_id))
        === canonicalJson(ACCEPTED_TASK_IDS),
    "DATASET_MANIFEST_DRIFT_REJECTED",
    "accepted dataset closed task set drifted",
  );
  return manifest;
}

export function acceptedTaskBinding(repositoryRoot, task, taskPath) {
  const manifest = loadManifest(repositoryRoot);
  const entry = manifest.tasks.find((candidate) => candidate.task_id === task.task_id);
  assert(entry, "UNKNOWN_TASK_REJECTED", "TaskSpec is outside the accepted six-task set");
  const expectedTaskPath = join(repositoryRoot, DATASET_ROOT_RELATIVE, entry.task_spec_path);
  const expectedTaskBytes = readFileSync(expectedTaskPath);
  const expectedTask = JSON.parse(expectedTaskBytes.toString("utf8"));
  assert(
    realpathSync(taskPath) === realpathSync(expectedTaskPath)
      && canonicalJson(task) === canonicalJson(expectedTask)
      && task.dataset_version === manifest.dataset_version
      && task.repository.base_commit === entry.base_commit
      && task.repository.tree_hash === entry.tree_hash,
    "TASK_DATASET_BINDING_REJECTED",
    "TaskSpec bytes or source identity differ from the accepted dataset entry",
  );
  return {
    manifest,
    entry,
    task_spec_path: `${DATASET_ROOT_RELATIVE}/${entry.task_spec_path}`,
    task_source: `${DATASET_ROOT_RELATIVE}/tasks/${task.task_id}/source-template`,
  };
}

export function validateTaskProgram(repositoryRoot, task, taskPath, program) {
  const binding = acceptedTaskBinding(repositoryRoot, task, taskPath);
  const programSetPath = join(
    repositoryRoot,
    "evaluation-harness/fixtures/p1-125-six-task-parameterized/b1-program-set.json",
  );
  const programSetBytes = readFileSync(programSetPath);
  assert(
    sha256(programSetBytes) === PROGRAM_SET_SHA256,
    "TASK_PROGRAM_SET_DRIFT_REJECTED",
    "accepted finite program set identity drifted",
  );
  const programSet = JSON.parse(programSetBytes.toString("utf8"));
  const acceptedProgram = programSet.programs.find((candidate) => candidate.task_id === task.task_id);
  assert(
    acceptedProgram
      && canonicalJson(program) === canonicalJson(acceptedProgram)
      && program.task_id === task.task_id
      && program.dataset_id === binding.manifest.dataset_id
      && program.dataset_version === binding.manifest.dataset_version
      && program.dataset_manifest_sha256 === DATASET_MANIFEST_SHA256
      && program.task_spec_path === binding.task_spec_path
      && program.task_source === binding.task_source,
    "TASK_PROGRAM_BINDING_REJECTED",
    "finite program does not match the exact TaskSpec and accepted dataset identity",
  );
  return binding;
}

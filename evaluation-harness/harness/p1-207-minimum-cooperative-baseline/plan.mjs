import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  ACCEPTED_TASK_IDS,
  DATASET_MANIFEST_PATH,
  loadAcceptedCompilerProfile,
  loadAcceptedTask,
} from "../p1-149-accepted-execution-spine/accepted-inputs.mjs";
import {
  REPOSITORY_ROOT,
} from "../p1-149-accepted-execution-spine/core.mjs";
import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  safeRegularFile,
} from "./shared.mjs";

export const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
export const ROUTE_ID = "P1_MINIMUM_COOPERATIVE_LOCAL_RESEARCH_ARTIFACT_AND_PREREGISTRATION_STRICT_EXIT_ROUTE_V1";
export const CLAIM_BOUNDARY = "COOPERATIVE_LOCAL_REPRODUCIBLE_RESEARCH_ARTIFACT_ONLY";
export const ENDPOINT = "http://127.0.0.1:8787/v1/chat/completions";
export const MODEL = "gpt-5.6-luna";
export const PROFILE_IDS = Object.freeze(["B0_A", "B0_B", "B1_A", "B1_B", "B2_A", "B2_B"]);

export const ACCEPTED_INPUTS = Object.freeze({
  p1_035: {
    task_id: "AIOS-P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET",
    accepted_candidate_commit: "686eda0cd7a93b72ac5e64301479f17e4b096fb0",
    accepted_candidate_tree: "b2740b44d0051303057deac7d719c27fd6a5578a",
  },
  p1_101: {
    task_id: "AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE",
    accepted_candidate_commit: "633f9daf133bf616cd293fb343058e2efba2a3ed",
    accepted_candidate_tree: "999f37f93692a045d455adf0ea503947ed5555a5",
  },
  p1_129: {
    task_id: "AIOS-P1-129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION",
    accepted_candidate_commit: "a772dc5d350ec6b38a84e430b01f75628429aa7b",
    accepted_candidate_tree: "905dd694922ba9a2b452d15c93dc17cefc9e53c1",
  },
  p1_149: {
    task_id: "AIOS-P1-149_ACCEPTED_EXECUTION_SPINE_CONVERGENCE",
    accepted_candidate_commit: "88600ee18848e0d2c6d7f2012d0f548021062720",
    accepted_candidate_tree: "34a16c8177bc0f72fd35a0510429ed1979f72fb3",
  },
});

function profileProjection(profileId) {
  const [adapterId, variant] = profileId.split("_");
  return {
    adapter_id: adapterId,
    profile_id: profileId,
    repetition_id: variant === "A" ? 1 : 2,
    execution_mode: adapterId === "B0"
      ? "DIRECT_MODEL_PATCH_PROPOSAL"
      : adapterId === "B1"
        ? "FINITE_TOOL_AGENT_PATCH_PROPOSAL"
        : "SOURCELENS_CONTEXT_PATCH_PROPOSAL",
  };
}

export function buildFormalPlan() {
  const cells = [];
  let ordinal = 1;
  for (const taskId of ACCEPTED_TASK_IDS) {
    for (const profileId of PROFILE_IDS) {
      const profile = profileProjection(profileId);
      cells.push({
        ordinal,
        cell_id: `formal-${String(ordinal).padStart(3, "0")}`,
        task_id: taskId,
        adapter_id: profile.adapter_id,
        profile_id: profile.profile_id,
        repetition_id: profile.repetition_id,
        baseline_id: `${taskId}:${profile.profile_id}`,
        request_shape: "CHAT_COMPLETIONS_TYPED_PATCH_IR_V1",
      });
      ordinal += 1;
    }
  }
  assert(cells.length === 36, "FORMAL_PLAN_INVALID", "formal plan denominator is not 36");
  return {
    schema_version: "p1-207-formal-plan/v1",
    task_id: TASK_ID,
    route_id: ROUTE_ID,
    claim_boundary: CLAIM_BOUNDARY,
    denominator: 36,
    endpoint: ENDPOINT,
    model: MODEL,
    accepted_inputs: ACCEPTED_INPUTS,
    cells,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

function sourceFiles(binding) {
  return binding.source_files.map((entry) => {
    const path = safeRegularFile(join(binding.source_root, ...entry.path.split("/")), `${binding.task.task_id} source`);
    const bytes = readFileSync(path);
    return {
      path: entry.path,
      sha256: entry.sha256,
      byte_length: entry.byte_length,
      utf8: bytes.toString("utf8"),
    };
  });
}

function taskPrompt(cell) {
  const binding = loadAcceptedTask(cell.task_id);
  const compilerProfile = loadAcceptedCompilerProfile(cell.task_id);
  const prompt = {
    schema_version: "p1-207-model-task-prompt/v1",
    task: {
      task_id: binding.task.task_id,
      issue: binding.task.issue,
      forbidden_changes: binding.task.forbidden_changes,
      verification: binding.task.verification,
      repository: binding.task.repository,
      task_spec_identity: binding.task_spec.identity,
    },
    experimental_profile: {
      adapter_id: cell.adapter_id,
      profile_id: cell.profile_id,
      repetition_id: cell.repetition_id,
      interpretation: profileProjection(cell.profile_id).execution_mode,
    },
    compiler_profile: compilerProfile,
    source_files: sourceFiles(binding),
    required_output: {
      schema_version: "SL-PATCH-IR/2",
      exact_top_level_keys: ["schema_version", "dataset", "task", "operations"],
      operation_types: ["REPLACE_REGULAR_FILE", "CREATE_REGULAR_FILE"],
      maximum_operations: 3,
      maximum_total_postimage_bytes: 65536,
      operation_order: "LEXICOGRAPHIC_PATH_ASCENDING",
      postimage_encoding: "STRICT_BASE64_WITH_SHA256_AND_BYTE_LENGTH",
      prose_or_markdown_forbidden: true,
    },
  };
  return canonicalJson(prompt);
}

export function buildFormalRequest(cell) {
  assert(
    buildFormalPlan().cells.some((entry) => canonicalJson(entry) === canonicalJson(cell)),
    "FORMAL_CELL_INVALID",
    "request cell is outside the frozen formal plan",
  );
  return {
    model: MODEL,
    messages: [
      {
        role: "system",
        content: "Return exactly one JSON object conforming to the supplied finite Patch IR contract. Do not use Markdown, prose, comments, tools, network access, or unstated files.",
      },
      { role: "user", content: taskPrompt(cell) },
    ],
  };
}

export function buildDiagnosticRequest() {
  return {
    model: MODEL,
    messages: [
      {
        role: "user",
        content: "Reply with exactly the word READY.",
      },
    ],
  };
}

export function datasetIdentity() {
  const bytes = readFileSync(safeRegularFile(DATASET_MANIFEST_PATH, "accepted P1-035 dataset manifest"));
  return {
    path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/dataset-manifest.json",
    ...bytesIdentity(bytes),
  };
}

export function planIdentity() {
  return bytesIdentity(canonicalBytes(buildFormalPlan()));
}

export { REPOSITORY_ROOT };

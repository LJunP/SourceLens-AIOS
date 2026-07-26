#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const DATASET_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/datasets/p1-representative-task-dataset-v1");
const MANIFEST_PATH = join(DATASET_ROOT, "dataset-manifest.json");
const DEFINITIONS_PATH = join(HERE, "program-definitions.json");

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const canonical = (value) => `${JSON.stringify(value, Object.keys(value).sort())}\n`;
const canonicalJson = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
};

const manifestBytes = readFileSync(MANIFEST_PATH);
const manifest = JSON.parse(manifestBytes);
const definitions = JSON.parse(readFileSync(DEFINITIONS_PATH, "utf8"));
if (manifest.task_count !== 6 || definitions.programs.length !== 6) throw new Error("closed task set drifted");

const programs = [];
for (const definition of definitions.programs) {
  const manifestEntry = manifest.tasks.find((entry) => entry.task_id === definition.task_id);
  if (!manifestEntry) throw new Error(`unknown definition ${definition.task_id}`);
  const taskSpecRelative = `evaluation-harness/datasets/p1-representative-task-dataset-v1/${manifestEntry.task_spec_path}`;
  const taskSpec = JSON.parse(readFileSync(join(REPOSITORY_ROOT, taskSpecRelative), "utf8"));
  const sourceRelative = `evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/${definition.task_id}/source-template`;
  const changes = definition.changes.map((change) => {
    const path = join(REPOSITORY_ROOT, sourceRelative, change.relative_path);
    const before = change.old === null ? Buffer.alloc(0) : readFileSync(path);
    if (change.old === null && existsSync(path)) throw new Error(`expected absent create target ${path}`);
    if (change.old !== null && before.toString("utf8").split(change.old).length - 1 !== 1) {
      throw new Error(`ambiguous preimage ${path}`);
    }
    const after = change.old === null
      ? Buffer.from(change.new, "utf8")
      : Buffer.from(before.toString("utf8").replace(change.old, change.new), "utf8");
    return {
      relative_path: change.relative_path,
      operation: change.old === null ? "create" : "replace_once",
      before_sha256: change.old === null ? null : sha256(before),
      after_sha256: sha256(after),
      replacement: { old: change.old, new: change.new },
    };
  });
  programs.push({
    schema_version: "p1-125-b1-finite-program/v1",
    program_id: `P1-125-B1-${definition.task_id}-FINITE-PROGRAM`,
    dataset_id: manifest.dataset_id,
    dataset_version: manifest.dataset_version,
    dataset_manifest_sha256: sha256(manifestBytes),
    task_id: definition.task_id,
    task_spec_path: taskSpecRelative,
    task_source: sourceRelative,
    allowed_tool_classes: ["file_listing", "file_read", "lexical_search", "structured_patch", "verification_command"],
    forbidden_features: ["sourcelens_graph", "ranker", "memory", "additional_agent", "network"],
    actions: [
      { ordinal: 1, tool_class: "file_listing", relative_path: "." },
      { ordinal: 2, tool_class: "file_read", relative_path: definition.read_path },
      { ordinal: 3, tool_class: "lexical_search", query: definition.search_query, relative_path: definition.search_path },
      { ordinal: 4, tool_class: "structured_patch", changes },
      { ordinal: 5, tool_class: "verification_command", command_id: taskSpec.verification.required_commands[0].command_id },
      { ordinal: 6, tool_class: "verification_command", command_id: taskSpec.verification.required_commands[1].command_id }
    ],
    expected_action_count: 6,
    rollback: {
      required: true,
      changed_paths: changes.map((entry) => entry.relative_path),
      created_paths: changes.filter((entry) => entry.operation === "create").map((entry) => entry.relative_path)
    },
    external_effects: { network: false, provider: false, secret: false, remote: false, production: false, public: false },
    claim_boundary: "FINITE_COOPERATIVE_LOCAL_B1_SIX_TASK_PROGRAM_ONLY"
  });
}

writeFileSync(
  join(HERE, "b1-program-set.json"),
  Buffer.from(`${canonicalJson({
    schema_version: "p1-125-b1-program-set/v1",
    dataset_id: manifest.dataset_id,
    dataset_version: manifest.dataset_version,
    dataset_manifest_sha256: sha256(manifestBytes),
    task_count: programs.length,
    programs,
    claim_boundary: "EXACT_ACCEPTED_SIX_TASK_FINITE_PROGRAM_SET_ONLY"
  })}\n`, "utf8"),
  { flag: "w" },
);

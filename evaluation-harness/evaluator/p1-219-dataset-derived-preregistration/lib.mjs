import { createHash } from "node:crypto";
import { lstatSync, readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";

export const TASK_ID = "AIOS-P1-219_DATASET_DERIVED_REPORT_BOUND_P2_CONTEXT_PREREGISTRATION";

export const REPORT_AUTHORITY = Object.freeze({
  path: "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-single-process-report-strict-exit-20260805/task-1-p1-217/correction-evidence-v1/report-output/REPRODUCIBLE_BASELINE_REPORT.json",
  byte_length: 12815,
  sha256: "27abd4d655b9eabd13f29bb15f84edc97b7b3d884daefe837e49846ba64a6657",
  acceptance_commit: "630ddcf4659daca287825bb8e2382deaa962606c",
  acceptance_tree: "d5c4c85247141dcb0308add95969991913735ea9",
});

export const DATASET_AUTHORITY = Object.freeze({
  path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/dataset-manifest.json",
  byte_length: 15313,
  sha256: "22f252319ed066655b05142a391709741703e01fbb4d6b5ebfbbcb6acd782be6",
});

const TOP_LEVEL_KEYS = Object.freeze([
  "artifact_type",
  "dataset_binding",
  "external_effects",
  "p2_state",
  "preregistration",
  "report_binding",
  "sample",
  "sample_derivation",
  "schema_version",
  "task_id",
]);

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function fail(code, detail) {
  throw new Error(`${code}: ${detail}`);
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("SCHEMA_INVALID", `${label} must be an object`);
  }
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (!isDeepStrictEqual(actual, wanted)) {
    fail("SCHEMA_INVALID", `${label} keyset mismatch`);
  }
}

function readBoundJson(authority, label) {
  const stat = lstatSync(authority.path);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("TYPE_OR_SYMLINK_DRIFT", `${label} is not a regular non-symlink file`);
  }
  const bytes = readFileSync(authority.path);
  if (bytes.length !== authority.byte_length) {
    fail("BYTE_LENGTH_DRIFT", `${label} byte length differs from authority`);
  }
  if (sha256(bytes) !== authority.sha256) {
    fail("SHA256_DRIFT", `${label} SHA-256 differs from authority`);
  }
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail("JSON_INVALID", `${label} is not valid JSON: ${error.message}`);
  }
}

function validateDataset(dataset) {
  exactKeys(dataset, [
    "artifact_count",
    "artifacts",
    "claim_boundary",
    "dataset_id",
    "dataset_version",
    "schema_version",
    "source_policy",
    "split_counts",
    "task_count",
    "tasks",
    "visibility",
  ], "dataset manifest");
  if (!Array.isArray(dataset.tasks) || dataset.tasks.length === 0) {
    fail("DATASET_INVALID", "tasks must be a non-empty array");
  }
  if (dataset.task_count !== dataset.tasks.length) {
    fail("DATASET_INVALID", "task_count does not equal tasks length");
  }
  const ids = new Set();
  for (const [index, task] of dataset.tasks.entries()) {
    exactKeys(task, [
      "archetype",
      "assertion_id",
      "base_commit",
      "split",
      "task_id",
      "task_spec_path",
      "tree_hash",
    ], `dataset task ${index}`);
    for (const key of Object.keys(task)) {
      if (typeof task[key] !== "string" || task[key].length === 0) {
        fail("DATASET_INVALID", `dataset task ${index}.${key} must be a non-empty string`);
      }
    }
    if (ids.has(task.task_id)) fail("DATASET_INVALID", `duplicate task_id ${task.task_id}`);
    ids.add(task.task_id);
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

export function readAuthorities({
  reportAuthority = REPORT_AUTHORITY,
  datasetAuthority = DATASET_AUTHORITY,
} = {}) {
  const report = readBoundJson(reportAuthority, "accepted report");
  const dataset = readBoundJson(datasetAuthority, "canonical dataset manifest");
  validateDataset(dataset);
  if (report.schema_version !== "p1-217-reproducible-baseline-report/v1") {
    fail("REPORT_SCHEMA_DRIFT", "accepted report schema_version mismatch");
  }
  if (report.metric?.denominator !== 36 || report.taxonomy?.denominator !== 36) {
    fail("REPORT_CONTRACT_DRIFT", "accepted report denominator mismatch");
  }
  return { report, dataset };
}

export function buildExpectedArtifact({
  reportAuthority = REPORT_AUTHORITY,
  datasetAuthority = DATASET_AUTHORITY,
} = {}) {
  const { dataset } = readAuthorities({ reportAuthority, datasetAuthority });
  return {
    schema_version: "p1-219-dataset-derived-preregistration/v1",
    artifact_type: "P2_CONTEXT_ENGINE_PREREGISTRATION",
    task_id: TASK_ID,
    report_binding: clone(reportAuthority),
    dataset_binding: {
      ...clone(datasetAuthority),
      dataset_id: dataset.dataset_id,
      dataset_version: dataset.dataset_version,
      task_count: dataset.task_count,
    },
    sample_derivation: {
      authority: "EXACT_DATASET_MANIFEST_TASKS_ARRAY",
      complete: true,
      ordered: true,
      unique: true,
      handwritten_task_id_constants_used_as_authority: false,
    },
    sample: clone(dataset.tasks),
    preregistration: {
      scope: "FUTURE_P2_CONTEXT_ENGINE_EXPERIMENT_ONLY",
      hypothesis: "For the complete ordered P1-035 task sample and an identical context-byte budget, graph-conditioned context selection will increase task-relevant evidence recall relative to the deterministic lexical baseline without increasing forbidden-context admission.",
      primary_metric: {
        id: "TASK_RELEVANT_EVIDENCE_RECALL_AT_FIXED_CONTEXT_BYTE_BUDGET",
        unit: "RATIO_0_TO_1",
        direction: "HIGHER_IS_BETTER",
        aggregation: "MACRO_MEAN_ACROSS_COMPLETE_ORDERED_TASK_SAMPLE",
        numerator: "task-relevant evidence units admitted into the selected context",
        denominator: "all task-relevant evidence units declared by the frozen task oracle",
      },
      baseline: {
        id: "DETERMINISTIC_LEXICAL_RETRIEVAL_V1",
        definition: "Rank admissible source units by normalized task-query token overlap, then break ties by canonical repository-relative path and source span.",
      },
      comparison: {
        design: "PAIRED_WITHIN_TASK_EQUAL_CONTEXT_BYTE_BUDGET",
        treatment: "GRAPH_CONDITIONED_CONTEXT_SELECTION",
        control: "DETERMINISTIC_LEXICAL_RETRIEVAL_V1",
        denominator_policy: "ALL_DATASET_TASKS_REMAIN_IN_THE_DENOMINATOR",
      },
      exclusion_rules: [
        "No task may be excluded after outcome observation.",
        "A run with identity drift, missing oracle data or budget mismatch is INVALID and remains in the denominator.",
        "An external-effect request or dataset mutation stops the experiment; it does not remove a task from the denominator.",
      ],
      uncertainty_method: {
        primary_interval: "PAIRED_TASK_LEVEL_PERCENTILE_BOOTSTRAP_95_PERCENT",
        bootstrap_resamples: 10000,
        deterministic_seed_source: "DATASET_MANIFEST_SHA256_FIRST_16_HEX",
        sensitivity_analysis: "EXACT_TWO_SIDED_SIGN_FLIP_RANDOMIZATION_OVER_ALL_TASK_LEVEL_PAIRED_DIFFERENCES",
      },
      stop_conditions: [
        "accepted report or dataset identity drift",
        "sample differs from the complete ordered unique dataset tasks array",
        "treatment and control context byte budgets differ",
        "task-relevant evidence oracle cannot be frozen before outcome inspection",
        "a scheduled task or invalid result is removed from the denominator",
        "network, Provider, Secret, remote, production or public effect is requested during this P1 Task",
        "P2 Phase entry is not separately authorized after strict P1 Exit",
      ],
    },
    p2_state: {
      status: "HOLD_PENDING_STRICT_P1_EXIT_AND_FOUNDER_P2_ENTRY",
      p2_experiment_executed: false,
      p2_entry_authorized: false,
    },
    external_effects: {
      network: false,
      provider: false,
      secret: false,
      remote: false,
      production: false,
      public: false,
    },
  };
}

export function verifyArtifactObject(artifact, options = {}) {
  exactKeys(artifact, TOP_LEVEL_KEYS, "preregistration Artifact");
  const expected = buildExpectedArtifact(options);
  if (!isDeepStrictEqual(artifact, expected)) {
    fail("ARTIFACT_AUTHORITY_MISMATCH", "Artifact differs from independently derived expected bytes model");
  }
  return {
    schema_version: "p1-219-independent-verifier-receipt/v1",
    task_id: TASK_ID,
    status: "PASS",
    sample_members: expected.sample.length,
    sample_order_exact: true,
    report_binding_exact: true,
    dataset_binding_exact: true,
    p2_experiment_executed: false,
    provider_requests: 0,
    secret_reads: 0,
    false_accepts: 0,
    external_effects: clone(expected.external_effects),
  };
}

export function verifyArtifactFile(artifactPath, options = {}) {
  const stat = lstatSync(artifactPath);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("ARTIFACT_TYPE_OR_SYMLINK_DRIFT", "Artifact is not a regular non-symlink file");
  }
  const bytes = readFileSync(artifactPath);
  let artifact;
  try {
    artifact = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail("ARTIFACT_JSON_INVALID", error.message);
  }
  return {
    receipt: verifyArtifactObject(artifact, options),
    artifact_identity: {
      path: artifactPath,
      byte_length: bytes.length,
      sha256: sha256(bytes),
    },
  };
}

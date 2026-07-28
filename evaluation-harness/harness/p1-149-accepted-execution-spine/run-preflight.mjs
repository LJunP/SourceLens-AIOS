import { fileURLToPath } from "node:url";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  canonicalBytes,
  canonicalJson,
  cleanupOwnedRoot,
  copyClosedTree,
  createDisposableRoot,
  createOwnedRoot,
  writeBytesCreateOnce,
  writeJsonCreateOnce,
} from "./core.mjs";
import {
  ACCEPTED_TASK_IDS,
  buildAcceptedReferenceResponse,
  verifyAcceptedPatchIrV1Compatibility,
} from "./accepted-inputs.mjs";
import {
  EXECUTION_ARTIFACT_KEYS,
  executeSpine,
} from "./execution.mjs";
import {
  runEvidenceNegativeMatrix,
  runPatchIrNegativeMatrix,
} from "./negative-matrix.mjs";
import {
  buildClosedEvidenceManifest,
  READINESS_CLAIM_BOUNDARY,
  validateClosedEvidenceRoot,
  verifyFrozenExecutionEvidence,
} from "../../replay/p1-149-accepted-execution-spine/replay.mjs";

const READINESS_PROFILES = Object.freeze(["B0_A", "B0_B", "B1_A", "B1_B", "B2_A", "B2_B"]);
const CLAIM_BOUNDARY = READINESS_CLAIM_BOUNDARY;

function sameJson(left, right) {
  return canonicalJson(left) === canonicalJson(right);
}

function normalizedManifestResult(value) {
  if (Buffer.isBuffer(value)) {
    return { bytes: value, manifest: JSON.parse(value.toString("utf8")) };
  }
  if (Buffer.isBuffer(value?.bytes)) {
    return { bytes: value.bytes, manifest: value.manifest ?? JSON.parse(value.bytes.toString("utf8")) };
  }
  const manifest = value?.manifest ?? value;
  return { manifest, bytes: canonicalBytes(manifest) };
}

function writeClosedManifest(handle) {
  const built = normalizedManifestResult(buildClosedEvidenceManifest(handle.root));
  return writeBytesCreateOnce(handle, "MANIFEST.json", built.bytes);
}

function assertFalseEffects(value, label) {
  assert(
    sameJson(value, FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_BOUNDARY_DRIFT",
    `${label} did not preserve the exact offline zero-effect boundary`,
  );
}

function fixedReadinessProjection(executionOrder) {
  const cells = [];
  let ordinal = 1;
  for (const execution of executionOrder) {
    for (const profileId of READINESS_PROFILES) {
      cells.push({
        ordinal,
        task_id: execution.task_id,
        profile_id: profileId,
        execution_spine: execution.stable_projection,
        classification: "READINESS_ONLY",
      });
      ordinal += 1;
    }
  }
  assert(cells.length === 36, "READINESS_PROJECTION_INVALID", "fixed readiness denominator is not 36");
  return {
    schema_version: "p1-149-fixed-execution-spine-readiness-projection/v1",
    claim_boundary: CLAIM_BOUNDARY,
    denominator: 36,
    formal_baseline: false,
    p1_capability_credit: false,
    cells,
  };
}

async function buildRawEvidence(handle) {
  const v1Compatibility = verifyAcceptedPatchIrV1Compatibility();
  const compilerMatrix = runPatchIrNegativeMatrix();
  assert(
    v1Compatibility.status === "PASS"
      && compilerMatrix.status === "PASS"
      && compilerMatrix.accepted_task_count === 6
      && compilerMatrix.false_accepts === 0,
    "COMPILER_PREFLIGHT_NON_PASS",
    "Patch IR compatibility or compiler matrix did not pass",
  );
  writeJsonCreateOnce(handle, "p1-055-v1-compatibility.json", v1Compatibility);
  writeJsonCreateOnce(handle, "patch-ir-negative-matrix.json", compilerMatrix);

  const executionOrder = [];
  const executionSummaries = [];
  let totalOperations = 0;
  for (const [index, taskId] of ACCEPTED_TASK_IDS.entries()) {
    const accepted = buildAcceptedReferenceResponse(taskId, `P1-149-PREFLIGHT-${index + 1}`);
    const runId = `P1-149-PREFLIGHT-${String(index + 1).padStart(2, "0")}`;
    const execution = await executeSpine({
      taskId,
      responseBytes: accepted.response_bytes,
      runId,
    });
    assert(
      execution?.schema_version === "p1-149-execution-spine-result/v1"
        && execution.task_id === taskId
        && execution.run_id === runId
        && execution.artifacts !== null
        && typeof execution.artifacts === "object"
        && !Array.isArray(execution.artifacts),
      "EXECUTION_SPINE_RESULT_INVALID",
      `execution spine returned an invalid result for ${taskId}`,
    );
    const artifactNames = Object.keys(execution.artifacts).sort();
    assert(
      sameJson(artifactNames, [...EXECUTION_ARTIFACT_KEYS].sort()),
      "EXECUTION_SPINE_ARTIFACT_SET_INVALID",
      `execution spine artifact set is not closed for ${taskId}`,
      { actual: artifactNames, expected: EXECUTION_ARTIFACT_KEYS },
    );

    const written = new Map();
    for (const name of EXECUTION_ARTIFACT_KEYS) {
      const bytes = execution.artifacts[name];
      assert(Buffer.isBuffer(bytes), "EXECUTION_SPINE_ARTIFACT_INVALID", `${taskId}/${name} is not raw bytes`);
      written.set(
        name,
        writeBytesCreateOnce(handle, `tasks/${taskId}/${name}`, bytes),
      );
    }
    assert(
      execution.artifacts["provider-response.json"].equals(accepted.response_bytes),
      "EXECUTION_RESPONSE_IDENTITY_DRIFT",
      `execution spine did not preserve exact normalized response bytes for ${taskId}`,
    );
    const projectionBytes = canonicalBytes(execution.stable_projection);
    assert(
      projectionBytes.equals(execution.artifacts["p1-101-stable-projection.json"]),
      "EXECUTION_PROJECTION_IDENTITY_DRIFT",
      `execution spine stable projection bytes drifted for ${taskId}`,
    );
    assertFalseEffects(execution.summary.external_effects, `${taskId} execution summary`);
    assert(
      Number.isInteger(execution.summary.real_patch_operations)
        && execution.summary.real_patch_operations >= 1,
      "EXECUTION_OPERATION_COUNT_INVALID",
      `${taskId} did not execute a real finite operation`,
    );
    totalOperations += execution.summary.real_patch_operations;
    executionSummaries.push(execution.summary);
    executionOrder.push({
      ordinal: index + 1,
      task_id: taskId,
      artifact_root: `tasks/${taskId}`,
      response: written.get("provider-response.json"),
      stable_projection: written.get("p1-101-stable-projection.json"),
    });
  }

  const runPlan = {
    schema_version: "p1-149-preflight-run-plan/v1",
    task_ids: ACCEPTED_TASK_IDS,
    execution_order: executionOrder,
    claim_boundary: CLAIM_BOUNDARY,
  };
  writeJsonCreateOnce(handle, "run-plan.json", runPlan);
  const readinessProjection = fixedReadinessProjection(executionOrder);
  writeJsonCreateOnce(handle, "readiness-projection-36.json", readinessProjection);
  return {
    compilerMatrix,
    executionSummaries,
    operationCount: totalOperations,
    readinessProjection,
    runPlan,
    v1Compatibility,
  };
}

function runEvidenceNegativesFromSnapshot(outputHandle) {
  const disposable = createDisposableRoot("negative-source");
  try {
    const sourceRoot = join(disposable.root, "evidence");
    copyClosedTree(outputHandle.root, sourceRoot);
    const built = normalizedManifestResult(buildClosedEvidenceManifest(sourceRoot));
    // sourceRoot is a child of the disposable owner, so use direct create-once
    // here; every subsequent mutation occurs only in further disposable copies.
    const manifestPath = join(sourceRoot, "MANIFEST.json");
    writeFileSync(manifestPath, built.bytes, { flag: "wx", mode: 0o600 });
    validateClosedEvidenceRoot(sourceRoot);
    verifyFrozenExecutionEvidence(sourceRoot);
    return runEvidenceNegativeMatrix({
      evidenceRoot: sourceRoot,
      verifyFrozenExecutionEvidence,
      buildClosedEvidenceManifest,
    });
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

export async function runPreflight(evidenceRoot) {
  assert(
    typeof evidenceRoot === "string" && evidenceRoot.startsWith("/"),
    "EVIDENCE_ROOT_INVALID",
    "preflight Evidence root must be an absolute absent path",
  );
  const output = createOwnedRoot(evidenceRoot);
  const built = await buildRawEvidence(output);
  const evidenceNegatives = await runEvidenceNegativesFromSnapshot(output);
  assert(
    evidenceNegatives.status === "PASS" && evidenceNegatives.false_accepts === 0,
    "EVIDENCE_NEGATIVE_MATRIX_NON_PASS",
    "Evidence negative matrix did not fail closed",
  );
  writeJsonCreateOnce(output, "evidence-negative-matrix.json", evidenceNegatives);

  const summary = {
    schema_version: "p1-149-offline-preflight/v1",
    task_id: "AIOS-P1-149_ACCEPTED_EXECUTION_SPINE_CONVERGENCE",
    accepted_tasks: 6,
    real_patch_operations: built.operationCount,
    accepted_p1_055_v1_compatibility: "PASS",
    accepted_p1_101_trace_replay: "PASS",
    execution_spines: built.executionSummaries.length,
    fixed_readiness_projection_cells: 36,
    readiness_claim: CLAIM_BOUNDARY,
    formal_baseline_cells: 0,
    p1_capability_credit: false,
    compiler_negative_cases: built.compilerMatrix.negative_case_count,
    evidence_negative_cases: evidenceNegatives.negative_case_count,
    false_accepts: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
    status: "PASS",
  };
  writeJsonCreateOnce(output, "preflight-summary.json", summary);
  const manifestIdentity = writeClosedManifest(output);
  const inventoryReceipt = validateClosedEvidenceRoot(output.root);
  const semanticReceipt = verifyFrozenExecutionEvidence(output.root);
  return {
    ...summary,
    evidence_root: output.root,
    evidence_manifest: manifestIdentity,
    inventory_verification: inventoryReceipt,
    semantic_verification: semanticReceipt,
  };
}

async function main(argv) {
  assert(argv.length === 1, "USAGE_INVALID", "usage: node run-preflight.mjs ABSENT_EVIDENCE_ROOT");
  const result = await runPreflight(resolve(argv[0]));
  process.stdout.write(`${canonicalJson(result)}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-149-preflight-failure/v1",
      status: "NON_PASS",
      reason_code: error?.code ?? error?.name ?? "UNEXPECTED_ERROR",
      message: error?.message ?? String(error),
    })}\n`);
    process.exitCode = 1;
  });
}

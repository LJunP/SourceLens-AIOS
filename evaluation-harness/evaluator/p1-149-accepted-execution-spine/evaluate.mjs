#!/usr/bin/env node

import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
} from "../../harness/p1-149-accepted-execution-spine/core.mjs";
import {
  ACCEPTED_TASK_IDS,
} from "../../harness/p1-149-accepted-execution-spine/accepted-inputs.mjs";
import {
  EXECUTION_ARTIFACT_KEYS,
  executeSpine,
} from "../../harness/p1-149-accepted-execution-spine/execution.mjs";
import {
  READINESS_CLAIM_BOUNDARY,
  buildReadinessCells,
  readFrozenProviderResponse,
  readFrozenStableProjection,
  verifyFrozenExecutionEvidence,
} from "../../replay/p1-149-accepted-execution-spine/replay.mjs";

function projectionIdentity(value) {
  return bytesIdentity(canonicalBytes(value));
}

function evaluateOneTask(evidenceRoot, taskId) {
  const responseBytes = readFrozenProviderResponse(evidenceRoot, taskId);
  const frozenProjection = readFrozenStableProjection(evidenceRoot, taskId);
  const fresh = executeSpine({
    taskId,
    responseBytes,
    runId: `P1-149-INDEPENDENT-EVALUATOR-${taskId}`,
  });
  assert(
    fresh.schema_version === "p1-149-execution-spine-result/v1"
      && fresh.task_id === taskId
      && isDeepStrictEqual(
        Object.keys(fresh.artifacts).sort(),
        [...EXECUTION_ARTIFACT_KEYS].sort(),
      ),
    "INDEPENDENT_REEXECUTION_INVALID",
    `${taskId} fresh evaluator execution did not return the closed execution-spine API`,
  );
  assert(
    isDeepStrictEqual(fresh.stable_projection, frozenProjection),
    "INDEPENDENT_RECONSTRUCTION_MISMATCH",
    `${taskId} fresh evaluator-owned execution did not reproduce the frozen stable projection`,
  );
  assert(
    isDeepStrictEqual(fresh.stable_projection.external_effects, FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_FORBIDDEN",
    `${taskId} fresh evaluator projection contains external effects`,
  );
  return {
    schema_version: "p1-149-independent-task-evaluation/v1",
    status: "PASS",
    task_id: taskId,
    raw_provider_response_identity: bytesIdentity(responseBytes),
    frozen_projection_identity: projectionIdentity(frozenProjection),
    fresh_projection_identity: projectionIdentity(fresh.stable_projection),
    fresh_owned_copy_executed: true,
    fresh_owned_copy_cleaned: true,
    worker_summary_trusted: false,
    worker_result_trusted: false,
    cell_result_trusted: false,
    external_effects: { ...FALSE_EXTERNAL_EFFECTS },
  };
}

export function evaluateFrozenExecutionEvidence(evidenceRoot) {
  const semanticValidation = verifyFrozenExecutionEvidence(evidenceRoot);
  assert(
    semanticValidation.status === "PASS"
      && semanticValidation.task_results.length === ACCEPTED_TASK_IDS.length,
    "FROZEN_EVIDENCE_NON_PASS",
    "frozen execution Evidence did not pass independent semantic validation",
  );
  const taskEvaluations = ACCEPTED_TASK_IDS.map(
    (taskId) => evaluateOneTask(evidenceRoot, taskId),
  );
  const projections = new Map(
    ACCEPTED_TASK_IDS.map(
      (taskId) => [taskId, readFrozenStableProjection(evidenceRoot, taskId)],
    ),
  );
  const cells = buildReadinessCells(projections);
  const taxonomy = {
    denominator: cells.length,
    accepted_execution_spine_readiness: cells.filter(
      (cell) => cell.classification === "ACCEPTED_EXECUTION_SPINE_READINESS",
    ).length,
    invalid: 0,
    excluded: 0,
    failed: 0,
  };
  assert(
    taxonomy.denominator === 36
      && taxonomy.accepted_execution_spine_readiness
        + taxonomy.invalid
        + taxonomy.excluded
        + taxonomy.failed
        === taxonomy.denominator,
    "READINESS_TAXONOMY_NOT_CLOSED",
    "six-task by six-profile readiness taxonomy does not close to 36",
  );
  assert(
    taskEvaluations.length === 6
      && taskEvaluations.every((entry) => (
        entry.status === "PASS"
        && entry.worker_summary_trusted === false
        && entry.worker_result_trusted === false
        && entry.cell_result_trusted === false
      )),
    "INDEPENDENT_EVALUATION_NON_PASS",
    "independent task evaluation set is incomplete",
  );
  return {
    schema_version: "p1-149-independent-evaluator-receipt/v1",
    status: "PASS",
    claim_boundary: READINESS_CLAIM_BOUNDARY,
    formal_baseline_claimed: false,
    p1_completion_credit_claimed: false,
    independent_reconstruction: {
      frozen_closed_inventory_validated: true,
      internal_identity_bindings_validated: true,
      compiler_reexecuted_from_raw_response: true,
      task_oracles_and_tests_reexecuted_in_fresh_owned_copies: true,
      trace_order_reconstructed: true,
      rollback_identity_reconstructed: true,
      worker_generated_success_fields_trusted: false,
    },
    task_evaluations: taskEvaluations,
    readiness_cells: cells,
    taxonomy,
    false_accepts: 0,
    external_effects: { ...FALSE_EXTERNAL_EFFECTS },
  };
}

function isMain() {
  return process.argv[1] !== undefined
    && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  assert(
    process.argv.length === 3,
    "CLI_USAGE_INVALID",
    "usage: node evaluate.mjs /absolute/frozen-evidence-root",
  );
  const receipt = evaluateFrozenExecutionEvidence(process.argv[2]);
  process.stdout.write(`${canonicalJson(receipt)}\n`);
}

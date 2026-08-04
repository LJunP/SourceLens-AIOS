#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalJson,
  exactKeys,
  parseExactJsonBytes,
  safeRealDirectory,
  safeRegularFile,
  writeJsonCreateOnce,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const REVIEW_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207/reviews/postformal-final-cycle-1";
const ROLES = Object.freeze(["CTO", "SECURITY", "QUALITY"]);
const FILES = Object.freeze({
  CTO: "CTO_REVIEW.json",
  SECURITY: "SECURITY_REVIEW.json",
  QUALITY: "QUALITY_REVIEW.json",
});
const REVIEW_KEYS = Object.freeze([
  "authorization", "checks", "corrected_candidate", "findings", "formal_evidence",
  "out_of_scope_observations", "postformal_outputs", "reviewed_at", "role",
  "schema_version", "source_manifest", "target_verdict", "task_id",
]);

function readCanonical(path, label) {
  const bytes = readFileSync(safeRegularFile(path, label, true));
  return { path, bytes, value: parseExactJsonBytes(bytes, { label, canonical: true }) };
}

function validateReview(record, role, manifest, manifestIdentity) {
  const review = record.value;
  exactKeys(review, REVIEW_KEYS, `${role} postformal review`);
  assert(review.schema_version === "p1-207-postformal-final-review/v1"
      && review.task_id === TASK_ID
      && review.role === role
      && review.target_verdict === "PASS"
      && isDeepStrictEqual(review.corrected_candidate, manifest.corrected_candidate)
      && isDeepStrictEqual(review.authorization, manifest.authorization)
      && isDeepStrictEqual(review.formal_evidence, manifest.formal_evidence)
      && isDeepStrictEqual(review.postformal_outputs, manifest.postformal_outputs)
      && isDeepStrictEqual(review.source_manifest, manifestIdentity)
      && Array.isArray(review.checks)
      && review.checks.length >= 1
      && review.checks.every((check) => check && typeof check === "object" && check.status === "PASS")
      && Array.isArray(review.findings)
      && review.findings.length === 0
      && Array.isArray(review.out_of_scope_observations)
      && typeof review.reviewed_at === "string"
      && Number.isFinite(Date.parse(review.reviewed_at)),
  "POSTFORMAL_FINAL_REVIEW_NON_PASS", `${role} review is not an exact bound PASS`);
}

export function freezePostformalTaskGate() {
  safeRealDirectory(REVIEW_ROOT, "postformal final review root");
  const manifestRecord = readCanonical(
    join(REVIEW_ROOT, "POSTFORMAL_CORRECTED_CANDIDATE_MANIFEST.json"),
    "postformal corrected candidate manifest",
  );
  const manifest = manifestRecord.value;
  assert(manifest.schema_version === "p1-207-postformal-corrected-candidate-manifest/v1"
      && manifest.task_id === TASK_ID
      && manifest.status === "FROZEN_EXACT_CANDIDATE"
      && manifest.formal_matrix_rerun === false
      && manifest.provider_requests === 0
      && manifest.secret_reads === 0
      && isDeepStrictEqual(manifest.external_effects, FALSE_EXTERNAL_EFFECTS),
  "POSTFORMAL_CANDIDATE_MANIFEST_INVALID", "postformal candidate manifest is not an exact zero-effect freeze");
  const manifestIdentity = {
    path: manifestRecord.path,
    ...bytesIdentity(manifestRecord.bytes),
  };
  const reviews = ROLES.map((role) => {
    const record = readCanonical(join(REVIEW_ROOT, FILES[role]), `${role} postformal review`);
    validateReview(record, role, manifest, manifestIdentity);
    return { role, verdict: "PASS", artifact: { path: record.path, ...bytesIdentity(record.bytes) } };
  });
  const gate = {
    schema_version: "p1-207-postformal-task-gate/v1",
    task_id: TASK_ID,
    status: "PASS",
    corrected_candidate: manifest.corrected_candidate,
    exact_execution_candidate: manifest.exact_execution_candidate,
    source_manifest: manifestIdentity,
    authorization: manifest.authorization,
    formal_evidence: manifest.formal_evidence,
    postformal_outputs: manifest.postformal_outputs,
    reviews,
    formal_matrix_rerun: false,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const identity = writeJsonCreateOnce(REVIEW_ROOT, "POSTFORMAL_TASK_GATE_RECEIPT.json", gate);
  return {
    schema_version: "p1-207-postformal-task-gate-freeze-result/v1",
    task_id: TASK_ID,
    status: "PASS",
    corrected_candidate: manifest.corrected_candidate,
    gate: { path: join(REVIEW_ROOT, identity.path), sha256: identity.sha256, byte_length: identity.byte_length },
    reviews: reviews.map((review) => review.artifact),
    formal_matrix_rerun: false,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  try {
    assert(process.argv.length === 2, "CLI_USAGE_INVALID", "freeze-postformal-task-gate.mjs takes no arguments");
    process.stdout.write(`${canonicalJson(freezePostformalTaskGate())}\n`);
  } catch (error) {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-207-postformal-task-gate-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: error.reasonCode ?? error.code ?? error.name,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

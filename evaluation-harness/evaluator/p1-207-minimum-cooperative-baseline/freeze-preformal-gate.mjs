#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalJson,
  exactKeys,
  parseExactJsonBytes,
  readExternalBoundFile,
  safeRealDirectory,
  safeRegularFile,
  writeJsonCreateOnce,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const AUDIT_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207";
const ROLES = Object.freeze(["CTO", "SECURITY", "QUALITY"]);
const REVIEW_FILES = Object.freeze({
  CTO: "CTO_REVIEW.json",
  SECURITY: "SECURITY_REVIEW.json",
  QUALITY: "QUALITY_REVIEW.json",
});
const REVIEW_KEYS = Object.freeze([
  "candidate", "checks", "evaluator_package", "findings", "out_of_scope_observations",
  "preformal_evidence_manifest", "reviewed_at", "role", "schema_version", "source_manifest",
  "target_verdict", "task_id",
]);

function externalIdentity(path) {
  const bytes = readFileSync(safeRegularFile(path, `review artifact ${path}`, true));
  return { path, ...bytesIdentity(bytes) };
}

function parseExternal(reference, label) {
  const record = readExternalBoundFile(reference, label);
  return { ...record, value: parseExactJsonBytes(record.bytes, { label, canonical: true }) };
}

function readCanonical(path, label) {
  const bytes = readFileSync(safeRegularFile(path, label, true));
  return { path, bytes, value: parseExactJsonBytes(bytes, { label, canonical: true }) };
}

function validateReview(record, role, bindings) {
  const review = record.value;
  exactKeys(review, REVIEW_KEYS, `${role} preformal review`);
  exactKeys(review.candidate, ["commit", "tree"], `${role} candidate identity`);
  assert(review.schema_version === "p1-207-preformal-review/v1"
      && review.task_id === TASK_ID
      && review.role === role
      && review.target_verdict === "PASS"
      && isDeepStrictEqual(review.candidate, bindings.candidate)
      && isDeepStrictEqual(review.source_manifest, bindings.sourceManifest)
      && isDeepStrictEqual(review.preformal_evidence_manifest, bindings.evidenceManifest)
      && isDeepStrictEqual(review.evaluator_package, bindings.evaluatorPackage)
      && Array.isArray(review.checks)
      && review.checks.length >= 1
      && review.checks.every((check) => check && typeof check === "object" && check.status === "PASS")
      && Array.isArray(review.findings)
      && review.findings.length === 0
      && Array.isArray(review.out_of_scope_observations)
      && typeof review.reviewed_at === "string"
      && review.reviewed_at.length >= 20,
  "PREFORMAL_REVIEW_NON_PASS", `${role} review does not bind an exact clean PASS`);
}

export function freezePreformalGate(reviewRoot, evidenceRoot) {
  assert(resolve(reviewRoot) === reviewRoot && resolve(evidenceRoot) === evidenceRoot
      && dirname(reviewRoot) === join(AUDIT_ROOT, "reviews")
      && dirname(evidenceRoot) === join(AUDIT_ROOT, "evidence")
      && /^preformal-cycle-[1-4]$/.test(basename(reviewRoot))
      && /^preformal-v[1-4]$/.test(basename(evidenceRoot))
      && basename(reviewRoot).split("-").at(-1) === basename(evidenceRoot).slice(-1),
  "PREFORMAL_ROOT_INVALID", "review and Evidence roots are not a matching Task-owned cycle");
  safeRealDirectory(reviewRoot, "preformal review root");
  safeRealDirectory(evidenceRoot, "preformal Evidence root");

  const sourceManifest = externalIdentity(join(reviewRoot, "PREFORMAL_SOURCE_MANIFEST.json"));
  const evidenceManifest = externalIdentity(join(evidenceRoot, "EVIDENCE_MANIFEST.json"));
  const evaluatorPackage = externalIdentity(join(reviewRoot, "INDEPENDENT_EVALUATOR_PACKAGE.json"));
  const source = parseExternal(sourceManifest, "preformal source manifest").value;
  const evaluator = parseExternal(evaluatorPackage, "independent evaluator package").value;
  exactKeys(evaluator, [
    "denominator", "evidence_manifest", "external_effects", "false_accepts",
    "gate_negative_matrix_receipt", "iteration", "negative_matrix_receipt",
    "raw_evaluator_receipt", "raw_evidence_only_reconstruction", "report",
    "report_rebuild_receipt", "schema_version", "source_manifest", "status", "task_id",
    "worker_receipt",
  ], "independent evaluator package");
  assert(source.schema_version === "p1-207-source-manifest/v1"
      && source.task_id === TASK_ID
      && source.repository?.dirty === false
      && /^[0-9a-f]{40}$/.test(source.repository?.commit ?? "")
      && /^[0-9a-f]{40}$/.test(source.repository?.tree ?? "")
      && evaluator.schema_version === "p1-207-preformal-independent-evaluator-package/v1"
      && evaluator.task_id === TASK_ID
      && evaluator.status === "PASS"
      && evaluator.false_accepts === 0
      && evaluator.raw_evidence_only_reconstruction === true
      && isDeepStrictEqual(evaluator.source_manifest, sourceManifest)
      && isDeepStrictEqual(evaluator.evidence_manifest, evidenceManifest)
      && isDeepStrictEqual(evaluator.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_PACKAGE_NON_PASS", "source or evaluator package is not an exact zero-effect PASS");
  const negative = parseExternal(evaluator.negative_matrix_receipt, "independent negative matrix receipt").value;
  assert(negative.schema_version === "p1-207-independent-negative-matrix/v1"
      && negative.status === "PASS"
      && negative.false_accepts === 0
      && negative.cases >= 14
      && isDeepStrictEqual(negative.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_NEGATIVE_MATRIX_NON_PASS", "independent negative matrix is not an exact zero-false-accept PASS");
  const gateNegative = parseExternal(evaluator.gate_negative_matrix_receipt, "Gate consumer negative matrix receipt").value;
  assert(gateNegative.schema_version === "p1-207-gate-consumer-negative-matrix/v1"
      && gateNegative.status === "PASS"
      && gateNegative.false_accepts === 0
      && gateNegative.cases >= 15
      && isDeepStrictEqual(gateNegative.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_GATE_NEGATIVE_MATRIX_NON_PASS", "Gate consumer negative matrix is not an exact zero-false-accept PASS");
  const candidate = { commit: source.repository.commit, tree: source.repository.tree };
  const bindings = { candidate, sourceManifest, evidenceManifest, evaluatorPackage };
  const freezerSource = source.entries.find((entry) => entry.path
    === "evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/freeze-preformal-gate.mjs");
  assert(freezerSource !== undefined, "PREFORMAL_FREEZE_ORIGIN_INVALID", "source manifest omitted the Gate freezer");
  const cycle = Number(basename(reviewRoot).split("-").at(-1));
  const freezeOrigin = {
    audit_root: AUDIT_ROOT,
    review_root: reviewRoot,
    evidence_root: evidenceRoot,
    cycle,
    freezer_source: freezerSource,
  };

  const reviews = ROLES.map((role) => {
    const path = join(reviewRoot, REVIEW_FILES[role]);
    const record = readCanonical(path, `${role} preformal review`);
    validateReview(record, role, bindings);
    return { role, verdict: "PASS", artifact: { path, ...bytesIdentity(record.bytes) } };
  });
  const gate = {
    schema_version: "p1-207-preformal-gate-receipt/v2",
    task_id: TASK_ID,
    status: "PASS",
    candidate,
    source_manifest: sourceManifest,
    preformal_evidence_manifest: evidenceManifest,
    independent_evaluator_receipt: evaluatorPackage,
    reviews,
    freeze_origin: freezeOrigin,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const identity = writeJsonCreateOnce(reviewRoot, "PREFORMAL_GATE_RECEIPT.json", gate);
  const result = {
    schema_version: "p1-207-preformal-gate-freeze-result/v2",
    task_id: TASK_ID,
    status: "PASS",
    candidate,
    gate: { path: join(reviewRoot, identity.path), sha256: identity.sha256, byte_length: identity.byte_length },
    source_manifest: sourceManifest,
    preformal_evidence_manifest: evidenceManifest,
    independent_evaluator_receipt: evaluatorPackage,
    reviews: reviews.map((review) => review.artifact),
    freeze_origin: freezeOrigin,
    false_accepts: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  writeJsonCreateOnce(reviewRoot, "PREFORMAL_GATE_FREEZE_RESULT.json", result);
  return result;
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  try {
    assert(process.argv.length === 4, "CLI_USAGE_INVALID", "usage: freeze-preformal-gate.mjs REVIEW_ROOT EVIDENCE_ROOT");
    process.stdout.write(`${canonicalJson(freezePreformalGate(process.argv[2], process.argv[3]))}\n`);
  } catch (error) {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-207-preformal-gate-freeze-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: error.reasonCode ?? error.code ?? error.name,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

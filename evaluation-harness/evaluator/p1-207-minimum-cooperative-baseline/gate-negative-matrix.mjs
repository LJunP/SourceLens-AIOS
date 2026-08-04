#!/usr/bin/env node

import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import {
  FALSE_EXTERNAL_EFFECTS,
  buildClosedManifest,
  bytesIdentity,
  canonicalBytes,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import { verifyPreformalGate } from "../../harness/p1-207-minimum-cooperative-baseline/gate-consumer.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const ROLES = Object.freeze(["CTO", "SECURITY", "QUALITY"]);
const REVIEW_FILES = Object.freeze({ CTO: "CTO_REVIEW.json", SECURITY: "SECURITY_REVIEW.json", QUALITY: "QUALITY_REVIEW.json" });

function writeCanonical(path, value) {
  const bytes = canonicalBytes(value);
  writeFileSync(path, bytes, { flag: "wx", mode: 0o600 });
  return { path, ...bytesIdentity(bytes) };
}

function makeDirectories(root) {
  for (const path of [
    join(root, "reviews"),
    join(root, "evidence"),
    join(root, "reviews/preformal-cycle-1"),
    join(root, "evidence/preformal-v1"),
    join(root, "evidence/preformal-v1/report"),
  ]) mkdirSync(path, { recursive: false, mode: 0o700 });
}

function buildFixture(auditRoot, sourceManifest, definition = {}) {
  makeDirectories(auditRoot);
  const reviewRoot = join(auditRoot, "reviews/preformal-cycle-1");
  const evidenceRoot = join(auditRoot, "evidence/preformal-v1");
  const sourcePath = join(reviewRoot, "PREFORMAL_SOURCE_MANIFEST.json");
  const sourceIdentity = writeCanonical(sourcePath, sourceManifest);
  const payloadIdentity = writeCanonical(join(evidenceRoot, "payload.json"), { status: "PASS", synthetic_cells: 36 });
  const evidenceManifest = buildClosedManifest(evidenceRoot, {
    taskId: TASK_ID,
    rootRole: "PREFORMAL_SYNTHETIC_RAW_EVIDENCE",
  });
  const evidenceManifestIdentity = writeCanonical(join(evidenceRoot, "EVIDENCE_MANIFEST.json"), evidenceManifest);
  const report = { artifact_type: "SYNTHETIC_REHEARSAL_ONLY", denominator: 36, status: "PASS" };
  const reportIdentity = writeCanonical(join(evidenceRoot, "report/REPRODUCIBLE_BASELINE_REPORT.json"), report);
  const worker = {
    schema_version: "p1-207-offline-preformal-result/v1",
    task_id: TASK_ID,
    status: "PASS",
    evidence_root: evidenceRoot,
    formal_plan: { path: "payload.json", sha256: payloadIdentity.sha256, byte_length: payloadIdentity.byte_length },
    accepted_p1_129_control: { positive_runs: 36, negative_cases: 53, false_accepts: 0 },
    synthetic_cells: 36,
    accepted_p1_149_execution_spines: 36,
    accepted_p1_101_replays: 36,
    negative_cases: 14,
    false_accepts: 0,
    secret_reads: 0,
    provider_requests: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
    evidence_manifest: { path: "EVIDENCE_MANIFEST.json", sha256: evidenceManifestIdentity.sha256, byte_length: evidenceManifestIdentity.byte_length },
  };
  const workerIdentity = writeCanonical(join(reviewRoot, "PREFORMAL_WORKER_RECEIPT.json"), worker);
  const rawEvaluator = {
    schema_version: "p1-207-independent-evaluator-receipt/v1",
    status: "PASS",
    mode: "SYNTHETIC",
    task_id: TASK_ID,
    denominator: 36,
    taxonomy: { successful: 36, failed: 0, invalid: 0, excluded: 0, denominator: 36 },
    vtsr: 1,
    closed_inventory_entries: 1,
    false_accepts: 0,
    raw_evidence_only_reconstruction: true,
    generated_report_used_as_input: false,
    worker_success_fields_trusted: false,
    accepted_spine_reexecutions: 36,
    accepted_p1_129_control: { path: "payload.json", sha256: payloadIdentity.sha256, byte_length: payloadIdentity.byte_length },
    evidence_manifest: { path: "EVIDENCE_MANIFEST.json", sha256: evidenceManifestIdentity.sha256, byte_length: evidenceManifestIdentity.byte_length },
    report,
    report_identity: { sha256: reportIdentity.sha256, byte_length: reportIdentity.byte_length },
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const rawEvaluatorIdentity = writeCanonical(join(reviewRoot, "RAW_INDEPENDENT_EVALUATOR_RECEIPT.json"), rawEvaluator);
  const rebuild = {
    schema_version: "p1-207-report-rebuild-receipt/v1",
    task_id: TASK_ID,
    status: "PASS",
    mode: "SYNTHETIC",
    raw_evidence_only: true,
    generated_report_used_as_input: false,
    evidence_manifest: evidenceManifestIdentity,
    evaluator: rawEvaluatorIdentity,
    report: reportIdentity,
    denominator: 36,
    taxonomy: rawEvaluator.taxonomy,
    false_accepts: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const rebuildIdentity = writeCanonical(join(evidenceRoot, "report/REPORT_REBUILD_RECEIPT.json"), rebuild);
  const negativeResults = Array.from({ length: 14 }, (_, index) => ({
    case_id: `RAW_NEGATIVE_${String(index + 1).padStart(2, "0")}`,
    rejected: true,
    observed_reason: "EXPECTED_REJECTION",
  }));
  const negative = {
    schema_version: "p1-207-independent-negative-matrix/v1",
    status: "PASS",
    golden_status: "PASS",
    cases: negativeResults.length,
    false_accepts: 0,
    results: negativeResults,
    disposable_root_cleaned: true,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const negativeIdentity = writeCanonical(join(reviewRoot, "INDEPENDENT_NEGATIVE_MATRIX_RECEIPT.json"), negative);
  const gateNegative = {
    schema_version: "p1-207-gate-consumer-negative-matrix/v1",
    status: "PASS",
    cases: 15,
    false_accepts: 0,
    results: Array.from({ length: 15 }, (_, index) => ({
      case_id: `GATE_NEGATIVE_${String(index + 1).padStart(2, "0")}`,
      rejected: true,
      observed_reason: "EXPECTED_REJECTION",
    })),
    disposable_root_cleaned: true,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const gateNegativeIdentity = writeCanonical(join(reviewRoot, "GATE_CONSUMER_NEGATIVE_MATRIX_RECEIPT.json"), gateNegative);
  const evaluatorPackage = {
    schema_version: "p1-207-preformal-independent-evaluator-package/v1",
    task_id: TASK_ID,
    status: "PASS",
    iteration: 1,
    source_manifest: sourceIdentity,
    worker_receipt: workerIdentity,
    evidence_manifest: evidenceManifestIdentity,
    raw_evaluator_receipt: rawEvaluatorIdentity,
    report: reportIdentity,
    report_rebuild_receipt: rebuildIdentity,
    negative_matrix_receipt: negativeIdentity,
    gate_negative_matrix_receipt: gateNegativeIdentity,
    denominator: 36,
    false_accepts: 0,
    raw_evidence_only_reconstruction: true,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  definition.mutatePackage?.(evaluatorPackage);
  const evaluatorPackageIdentity = writeCanonical(join(reviewRoot, "INDEPENDENT_EVALUATOR_PACKAGE.json"), evaluatorPackage);
  const candidate = { commit: sourceManifest.repository.commit, tree: sourceManifest.repository.tree };
  const reviews = {};
  for (const role of ROLES) {
    reviews[role] = {
      schema_version: "p1-207-preformal-review/v1",
      task_id: TASK_ID,
      role,
      target_verdict: "PASS",
      candidate,
      source_manifest: sourceIdentity,
      preformal_evidence_manifest: evidenceManifestIdentity,
      evaluator_package: evaluatorPackageIdentity,
      checks: [{ check_id: `${role}_EXACT_BINDING`, evidence: "Exact synthetic Gate fixture binding verified.", status: "PASS" }],
      findings: [],
      out_of_scope_observations: [],
      reviewed_at: "2026-08-04T00:00:00Z",
    };
  }
  definition.mutateReviews?.(reviews);
  const reviewBindings = ROLES.map((role) => {
    const identity = writeCanonical(join(reviewRoot, REVIEW_FILES[role]), reviews[role]);
    return { role, verdict: "PASS", artifact: identity };
  });
  const freezerSource = sourceManifest.entries.find((entry) => entry.path
    === "evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/freeze-preformal-gate.mjs");
  const freezeOrigin = {
    audit_root: auditRoot,
    review_root: reviewRoot,
    evidence_root: evidenceRoot,
    cycle: 1,
    freezer_source: freezerSource,
  };
  const gate = {
    schema_version: "p1-207-preformal-gate-receipt/v2",
    task_id: TASK_ID,
    status: "PASS",
    candidate,
    source_manifest: sourceIdentity,
    preformal_evidence_manifest: evidenceManifestIdentity,
    independent_evaluator_receipt: evaluatorPackageIdentity,
    reviews: reviewBindings,
    freeze_origin: freezeOrigin,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  definition.mutateGate?.(gate);
  const gatePath = join(reviewRoot, "PREFORMAL_GATE_RECEIPT.json");
  const gateIdentity = writeCanonical(gatePath, gate);
  const result = {
    schema_version: "p1-207-preformal-gate-freeze-result/v2",
    task_id: TASK_ID,
    status: "PASS",
    candidate,
    gate: gateIdentity,
    source_manifest: sourceIdentity,
    preformal_evidence_manifest: evidenceManifestIdentity,
    independent_evaluator_receipt: evaluatorPackageIdentity,
    reviews: reviewBindings.map((binding) => binding.artifact),
    freeze_origin: freezeOrigin,
    false_accepts: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  definition.mutateResult?.(result);
  const resultPath = join(reviewRoot, "PREFORMAL_GATE_FREEZE_RESULT.json");
  writeCanonical(resultPath, result);
  const fixture = { auditRoot, reviewRoot, evidenceRoot, gatePath, resultPath, sourcePath };
  definition.afterWrite?.(fixture);
  return definition.gatePath?.(fixture) ?? gatePath;
}

function runCase(parent, sourceManifest, definition) {
  const auditRoot = join(parent, definition.case_id.toLowerCase());
  mkdirSync(auditRoot, { recursive: false, mode: 0o700 });
  const gatePath = buildFixture(auditRoot, sourceManifest, definition);
  let rejected = false;
  let observedReason = null;
  try {
    verifyPreformalGate(gatePath, { auditRoot });
  } catch (error) {
    rejected = true;
    observedReason = error.reasonCode ?? error.code ?? error.name;
  }
  return { case_id: definition.case_id, rejected, observed_reason: observedReason };
}

export function runGateNegativeMatrix(sourceManifest) {
  const parent = mkdtempSync("/private/tmp/sourcelens-p1-207-gate-negative-");
  try {
    const definitions = [
      { case_id: "SUPERFICIAL_EVALUATOR", mutatePackage(value) { for (const key of Object.keys(value)) if (!["task_id", "status"].includes(key)) delete value[key]; } },
      { case_id: "SUPERFICIAL_REVIEW", mutateReviews(value) { value.CTO = { target_verdict: "PASS" }; } },
      { case_id: "STALE_CANDIDATE_REVIEW", mutateReviews(value) { value.SECURITY.candidate = { commit: "0".repeat(40), tree: "1".repeat(40) }; } },
      { case_id: "CROSS_CANDIDATE_PACKAGE", mutatePackage(value) { value.source_manifest = { ...value.source_manifest, sha256: "0".repeat(64) }; } },
      { case_id: "MISSING_REVIEWER", mutateGate(value) { value.reviews.pop(); } },
      { case_id: "DUPLICATE_REVIEWER", mutateGate(value) { value.reviews[2] = { ...value.reviews[2], role: "CTO" }; } },
      { case_id: "UNKNOWN_REVIEWER", mutateGate(value) { value.reviews[2] = { ...value.reviews[2], role: "LEGAL" }; } },
      { case_id: "GATE_EXTRA_FIELD", mutateGate(value) { value.unexpected = true; } },
      { case_id: "GATE_MISSING_FIELD", mutateGate(value) { delete value.status; } },
      { case_id: "GATE_STATUS_MUTATION", mutateGate(value) { value.status = "NON_PASS"; } },
      { case_id: "PATH_SUBSTITUTION", mutateGate(value) { value.reviews[0].artifact = value.reviews[1].artifact; } },
      { case_id: "IDENTITY_DRIFT", mutateGate(value) { value.reviews[0].artifact = { ...value.reviews[0].artifact, sha256: "f".repeat(64) }; } },
      { case_id: "SYMLINK_REVIEW", afterWrite(value) { const path = join(value.reviewRoot, "CTO_REVIEW.json"); unlinkSync(path); symlinkSync(value.sourcePath, path); } },
      { case_id: "FREEZE_RESULT_IDENTITY_DRIFT", mutateResult(value) { value.gate = { ...value.gate, sha256: "e".repeat(64) }; } },
      {
        case_id: "WRONG_GATE_ROOT",
        gatePath(value) {
          const wrongParent = join(value.auditRoot, "wrong-root");
          const wrongCycle = join(wrongParent, "preformal-cycle-1");
          mkdirSync(wrongParent, { recursive: false, mode: 0o700 });
          mkdirSync(wrongCycle, { recursive: false, mode: 0o700 });
          const path = join(wrongCycle, "PREFORMAL_GATE_RECEIPT.json");
          writeFileSync(path, readFileSync(value.gatePath), { flag: "wx", mode: 0o600 });
          return path;
        },
      },
    ];
    const goldenRoot = join(parent, "golden");
    mkdirSync(goldenRoot, { recursive: false, mode: 0o700 });
    const goldenGate = buildFixture(goldenRoot, sourceManifest);
    verifyPreformalGate(goldenGate, { auditRoot: goldenRoot });
    const results = definitions.map((definition) => runCase(parent, sourceManifest, definition));
    const falseAccepts = results.filter((result) => !result.rejected).length;
    if (falseAccepts !== 0) throw new Error(`Gate negative matrix false accepts: ${falseAccepts}`);
    return {
      schema_version: "p1-207-gate-consumer-negative-matrix/v1",
      status: "PASS",
      cases: results.length,
      false_accepts: falseAccepts,
      results,
      disposable_root_cleaned: true,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
  } finally {
    if (existsSync(parent) && parent.startsWith("/private/tmp/sourcelens-p1-207-gate-negative-")) {
      rmSync(parent, { recursive: true, force: false });
    }
  }
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  process.stderr.write("gate-negative-matrix.mjs is invoked by prepare-preformal.mjs with the exact current source manifest\n");
  process.exitCode = 64;
}

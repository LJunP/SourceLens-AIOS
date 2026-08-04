import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { isDeepStrictEqual } from "node:util";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  exactKeys,
  normalizedRelativePath,
  parseExactJsonBytes,
  readExternalBoundFile,
  safeRegularFile,
  verifyClosedManifest,
} from "./shared.mjs";
import { repositoryIdentity } from "./evidence.mjs";
import { REPOSITORY_ROOT, TASK_ID } from "./plan.mjs";

export const P1207_AUDIT_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207";

const GATE_KEYS = Object.freeze([
  "candidate", "external_effects", "freeze_origin", "independent_evaluator_receipt",
  "preformal_evidence_manifest", "reviews", "schema_version", "source_manifest",
  "status", "task_id",
]);
const FREEZE_ORIGIN_KEYS = Object.freeze([
  "audit_root", "cycle", "evidence_root", "freezer_source", "review_root",
]);
const FREEZE_RESULT_KEYS = Object.freeze([
  "candidate", "external_effects", "false_accepts", "freeze_origin", "gate",
  "independent_evaluator_receipt", "preformal_evidence_manifest", "reviews",
  "schema_version", "source_manifest", "status", "task_id",
]);
const SOURCE_MANIFEST_KEYS = Object.freeze(["entries", "repository", "schema_version", "task_id"]);
const SOURCE_ENTRY_KEYS = Object.freeze(["byte_length", "path", "sha256"]);
const REVIEW_BINDING_KEYS = Object.freeze(["artifact", "role", "verdict"]);
const REVIEW_KEYS = Object.freeze([
  "candidate", "checks", "evaluator_package", "findings", "out_of_scope_observations",
  "preformal_evidence_manifest", "reviewed_at", "role", "schema_version", "source_manifest",
  "target_verdict", "task_id",
]);
const CHECK_KEYS = Object.freeze(["check_id", "evidence", "status"]);
const PACKAGE_KEYS = Object.freeze([
  "denominator", "evidence_manifest", "external_effects", "false_accepts", "iteration",
  "gate_negative_matrix_receipt", "negative_matrix_receipt", "raw_evaluator_receipt",
  "raw_evidence_only_reconstruction", "report", "report_rebuild_receipt", "schema_version",
  "source_manifest", "status", "task_id", "worker_receipt",
]);
const WORKER_KEYS = Object.freeze([
  "accepted_p1_101_replays", "accepted_p1_129_control", "accepted_p1_149_execution_spines",
  "evidence_manifest", "evidence_root", "external_effects", "false_accepts", "formal_plan",
  "negative_cases", "provider_requests", "schema_version", "secret_reads", "status",
  "synthetic_cells", "task_id",
]);
const RAW_EVALUATOR_KEYS = Object.freeze([
  "accepted_p1_129_control", "accepted_spine_reexecutions", "closed_inventory_entries",
  "denominator", "evidence_manifest", "external_effects", "false_accepts",
  "generated_report_used_as_input", "mode", "raw_evidence_only_reconstruction", "report",
  "report_identity", "schema_version", "status", "task_id", "taxonomy", "vtsr",
  "worker_success_fields_trusted",
]);
const REBUILD_KEYS = Object.freeze([
  "denominator", "evaluator", "evidence_manifest", "external_effects", "false_accepts",
  "generated_report_used_as_input", "mode", "raw_evidence_only", "report", "schema_version",
  "status", "task_id", "taxonomy",
]);
const NEGATIVE_KEYS = Object.freeze([
  "cases", "disposable_root_cleaned", "external_effects", "false_accepts", "golden_status",
  "results", "schema_version", "status",
]);
const NEGATIVE_RESULT_KEYS = Object.freeze(["case_id", "observed_reason", "rejected"]);
const REVIEW_FILES = Object.freeze({ CTO: "CTO_REVIEW.json", SECURITY: "SECURITY_REVIEW.json", QUALITY: "QUALITY_REVIEW.json" });
const ROLES = Object.freeze(Object.keys(REVIEW_FILES));

function same(left, right) {
  return isDeepStrictEqual(left, right);
}

function exactIdentity(path, bytes) {
  return { path, ...bytesIdentity(bytes) };
}

function parseExternalAt(reference, expectedPath, label) {
  assert(reference?.path === expectedPath, "PREFORMAL_PATH_BINDING_INVALID", `${label} is not at the exact Task-owned path`);
  const record = readExternalBoundFile(reference, label);
  return { ...record, value: parseExactJsonBytes(record.bytes, { label, canonical: true }) };
}

function requiredSourcePaths() {
  const result = spawnSync("/usr/bin/git", [
    "ls-files", "--",
    "evaluation-harness/harness/p1-207-minimum-cooperative-baseline",
    "evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline",
    "scripts/p1-207-operator-capture.sh",
    "scripts/verify-p1-207-minimum-cooperative-baseline.sh",
  ], {
    cwd: REPOSITORY_ROOT,
    shell: false,
    encoding: "utf8",
    env: { PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", LANG: "C", LC_ALL: "C", TZ: "UTC" },
  });
  assert(!result.error && result.status === 0, "SOURCE_MANIFEST_INVALID", "could not resolve tracked P1-207 source set");
  const paths = result.stdout.trim().split("\n").filter(Boolean).sort();
  assert(paths.length >= 10, "SOURCE_MANIFEST_INVALID", "tracked P1-207 source set is incomplete");
  return paths;
}

function verifySourceManifest(source) {
  exactKeys(source, SOURCE_MANIFEST_KEYS, "source manifest");
  exactKeys(source.repository, ["commit", "dirty", "tree"], "source manifest repository");
  assert(source.schema_version === "p1-207-source-manifest/v1"
      && source.task_id === TASK_ID
      && source.repository.dirty === false
      && /^[0-9a-f]{40}$/.test(source.repository.commit)
      && /^[0-9a-f]{40}$/.test(source.repository.tree),
  "SOURCE_MANIFEST_INVALID", "source manifest identity is invalid");
  assert(same(repositoryIdentity(), source.repository), "REVIEWED_SOURCE_DRIFT", "current source differs from reviewed commit and tree");
  assert(Array.isArray(source.entries), "SOURCE_MANIFEST_INVALID", "source manifest entries must be an array");
  const entries = new Map();
  for (const entry of source.entries) {
    exactKeys(entry, SOURCE_ENTRY_KEYS, "source manifest entry");
    normalizedRelativePath(entry.path, "source manifest path");
    assert(!entries.has(entry.path), "SOURCE_MANIFEST_INVALID", "source manifest contains a duplicate path");
    const bytes = readFileSync(safeRegularFile(join(REPOSITORY_ROOT, ...entry.path.split("/")), `reviewed source ${entry.path}`));
    assert(same(bytesIdentity(bytes), { sha256: entry.sha256, byte_length: entry.byte_length }),
      "REVIEWED_SOURCE_DRIFT", `reviewed source bytes drifted: ${entry.path}`);
    entries.set(entry.path, entry);
  }
  for (const path of requiredSourcePaths()) assert(entries.has(path), "SOURCE_MANIFEST_INVALID", `source manifest omitted ${path}`);
  return entries;
}

function verifyWorker(worker, evidenceRoot, evidenceManifest) {
  exactKeys(worker, WORKER_KEYS, "preformal Worker receipt");
  exactKeys(worker.accepted_p1_129_control, ["false_accepts", "negative_cases", "positive_runs"], "accepted P1-129 control");
  assert(worker.schema_version === "p1-207-offline-preformal-result/v1"
      && worker.task_id === TASK_ID && worker.status === "PASS" && worker.evidence_root === evidenceRoot
      && worker.synthetic_cells === 36 && worker.accepted_p1_149_execution_spines === 36
      && worker.accepted_p1_101_replays === 36 && worker.negative_cases >= 14
      && worker.false_accepts === 0 && worker.secret_reads === 0 && worker.provider_requests === 0
      && worker.accepted_p1_129_control.positive_runs === 36
      && worker.accepted_p1_129_control.negative_cases >= 53
      && worker.accepted_p1_129_control.false_accepts === 0
      && same(worker.evidence_manifest, { path: "EVIDENCE_MANIFEST.json", sha256: evidenceManifest.sha256, byte_length: evidenceManifest.byte_length })
      && same(worker.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_WORKER_NON_PASS", "preformal Worker receipt is not an exact zero-effect 36-cell PASS");
}

function verifyRawEvaluator(raw, evidenceManifest, reportRecord) {
  exactKeys(raw, RAW_EVALUATOR_KEYS, "raw independent evaluator receipt");
  assert(raw.schema_version === "p1-207-independent-evaluator-receipt/v1"
      && raw.task_id === TASK_ID && raw.status === "PASS" && raw.mode === "SYNTHETIC"
      && raw.denominator === 36 && raw.false_accepts === 0
      && raw.raw_evidence_only_reconstruction === true
      && raw.generated_report_used_as_input === false && raw.worker_success_fields_trusted === false
      && same(raw.evidence_manifest, { path: "EVIDENCE_MANIFEST.json", sha256: evidenceManifest.sha256, byte_length: evidenceManifest.byte_length })
      && same(raw.report_identity, bytesIdentity(reportRecord.bytes)) && same(raw.report, reportRecord.value)
      && same(raw.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_EVALUATOR_NON_PASS", "raw independent evaluator receipt is not an exact reconstruction PASS");
}

function verifyRebuild(rebuild, evidenceManifest, rawEvaluatorReference, reportReference) {
  exactKeys(rebuild, REBUILD_KEYS, "report rebuild receipt");
  assert(rebuild.schema_version === "p1-207-report-rebuild-receipt/v1"
      && rebuild.task_id === TASK_ID && rebuild.status === "PASS" && rebuild.mode === "SYNTHETIC"
      && rebuild.raw_evidence_only === true && rebuild.generated_report_used_as_input === false
      && rebuild.denominator === 36 && rebuild.false_accepts === 0
      && same(rebuild.evidence_manifest, evidenceManifest)
      && same(rebuild.evaluator, rawEvaluatorReference) && same(rebuild.report, reportReference)
      && same(rebuild.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_EVALUATOR_NON_PASS", "report rebuild receipt is not an exact raw-Evidence-only PASS");
}

function verifyNegative(negative) {
  exactKeys(negative, NEGATIVE_KEYS, "independent negative matrix receipt");
  assert(negative.schema_version === "p1-207-independent-negative-matrix/v1"
      && negative.status === "PASS" && negative.golden_status === "PASS"
      && Number.isInteger(negative.cases) && negative.cases >= 14
      && negative.false_accepts === 0 && negative.disposable_root_cleaned === true
      && Array.isArray(negative.results) && negative.results.length === negative.cases
      && same(negative.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_NEGATIVE_MATRIX_NON_PASS", "independent negative matrix is not an exact zero-false-accept PASS");
  const caseIds = new Set();
  for (const result of negative.results) {
    exactKeys(result, NEGATIVE_RESULT_KEYS, "negative matrix result");
    assert(typeof result.case_id === "string" && result.case_id.length >= 1 && !caseIds.has(result.case_id)
        && result.rejected === true && typeof result.observed_reason === "string" && result.observed_reason.length >= 1,
    "PREFORMAL_NEGATIVE_MATRIX_NON_PASS", "negative matrix result is not a unique rejection");
    caseIds.add(result.case_id);
  }
}

function verifyGateNegative(negative) {
  exactKeys(negative, ["cases", "disposable_root_cleaned", "external_effects", "false_accepts", "results", "schema_version", "status"], "Gate consumer negative matrix receipt");
  assert(negative.schema_version === "p1-207-gate-consumer-negative-matrix/v1"
      && negative.status === "PASS" && Number.isInteger(negative.cases) && negative.cases >= 15
      && negative.false_accepts === 0 && negative.disposable_root_cleaned === true
      && Array.isArray(negative.results) && negative.results.length === negative.cases
      && negative.results.every((result) => result && result.rejected === true
        && typeof result.case_id === "string" && typeof result.observed_reason === "string")
      && same(negative.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_GATE_NEGATIVE_MATRIX_NON_PASS", "Gate consumer negative matrix is not a zero-false-accept PASS");
}

function verifyPackage(packageRecord, paths, bindings, cycle) {
  const evaluator = packageRecord.value;
  exactKeys(evaluator, PACKAGE_KEYS, "independent evaluator package");
  assert(evaluator.schema_version === "p1-207-preformal-independent-evaluator-package/v1"
      && evaluator.task_id === TASK_ID && evaluator.status === "PASS" && evaluator.iteration === cycle
      && evaluator.denominator === 36 && evaluator.false_accepts === 0
      && evaluator.raw_evidence_only_reconstruction === true
      && same(evaluator.source_manifest, bindings.sourceManifest)
      && same(evaluator.evidence_manifest, bindings.evidenceManifest)
      && same(evaluator.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_PACKAGE_NON_PASS", "independent evaluator package is not an exact bound PASS");

  const worker = parseExternalAt(evaluator.worker_receipt, join(paths.reviewRoot, "PREFORMAL_WORKER_RECEIPT.json"), "preformal Worker receipt");
  verifyWorker(worker.value, paths.evidenceRoot, bindings.evidenceManifest);
  const report = parseExternalAt(evaluator.report, join(paths.evidenceRoot, "report/REPRODUCIBLE_BASELINE_REPORT.json"), "synthetic report");
  const raw = parseExternalAt(evaluator.raw_evaluator_receipt, join(paths.reviewRoot, "RAW_INDEPENDENT_EVALUATOR_RECEIPT.json"), "raw independent evaluator receipt");
  verifyRawEvaluator(raw.value, bindings.evidenceManifest, report);
  const rebuild = parseExternalAt(evaluator.report_rebuild_receipt, join(paths.evidenceRoot, "report/REPORT_REBUILD_RECEIPT.json"), "report rebuild receipt");
  verifyRebuild(rebuild.value, bindings.evidenceManifest, evaluator.raw_evaluator_receipt, evaluator.report);
  const negative = parseExternalAt(evaluator.negative_matrix_receipt, join(paths.reviewRoot, "INDEPENDENT_NEGATIVE_MATRIX_RECEIPT.json"), "independent negative matrix receipt");
  verifyNegative(negative.value);
  const gateNegative = parseExternalAt(evaluator.gate_negative_matrix_receipt, join(paths.reviewRoot, "GATE_CONSUMER_NEGATIVE_MATRIX_RECEIPT.json"), "Gate consumer negative matrix receipt");
  verifyGateNegative(gateNegative.value);
}

function verifyReview(record, role, bindings) {
  const review = record.value;
  exactKeys(review, REVIEW_KEYS, `${role} preformal review`);
  exactKeys(review.candidate, ["commit", "tree"], `${role} candidate`);
  assert(review.schema_version === "p1-207-preformal-review/v1" && review.task_id === TASK_ID
      && review.role === role && review.target_verdict === "PASS"
      && same(review.candidate, bindings.candidate) && same(review.source_manifest, bindings.sourceManifest)
      && same(review.preformal_evidence_manifest, bindings.evidenceManifest)
      && same(review.evaluator_package, bindings.evaluatorPackage)
      && typeof review.reviewed_at === "string" && Number.isFinite(Date.parse(review.reviewed_at))
      && Array.isArray(review.checks) && review.checks.length >= 1
      && Array.isArray(review.findings) && review.findings.length === 0
      && Array.isArray(review.out_of_scope_observations),
  "PREFORMAL_REVIEW_NON_PASS", `${role} review is not an exact bound PASS`);
  const checkIds = new Set();
  for (const check of review.checks) {
    exactKeys(check, CHECK_KEYS, `${role} review check`);
    assert(typeof check.check_id === "string" && check.check_id.length >= 1 && !checkIds.has(check.check_id)
        && typeof check.evidence === "string" && check.evidence.length >= 1 && check.status === "PASS",
    "PREFORMAL_REVIEW_NON_PASS", `${role} review contains an invalid or NON_PASS check`);
    checkIds.add(check.check_id);
  }
}

export function verifyPreformalGate(gatePath, { auditRoot = P1207_AUDIT_ROOT } = {}) {
  assert(resolve(auditRoot) === auditRoot, "PREFORMAL_ROOT_INVALID", "Task audit root must be normalized and absolute");
  const acceptedGatePath = safeRegularFile(gatePath, "preformal Gate receipt");
  const reviewRoot = dirname(acceptedGatePath);
  const match = basename(reviewRoot).match(/^preformal-cycle-([1-4])$/);
  assert(match && dirname(reviewRoot) === join(auditRoot, "reviews")
      && basename(acceptedGatePath) === "PREFORMAL_GATE_RECEIPT.json",
  "PREFORMAL_ROOT_INVALID", "Gate is not at the exact Task-owned review-cycle path");
  const cycle = Number(match[1]);
  const evidenceRoot = join(auditRoot, "evidence", `preformal-v${cycle}`);
  const gateBytes = readFileSync(acceptedGatePath);
  const gate = parseExactJsonBytes(gateBytes, { label: "preformal Gate receipt", canonical: true });
  exactKeys(gate, GATE_KEYS, "preformal Gate receipt");
  exactKeys(gate.candidate, ["commit", "tree"], "Gate candidate");
  exactKeys(gate.freeze_origin, FREEZE_ORIGIN_KEYS, "Gate freeze origin");
  assert(gate.schema_version === "p1-207-preformal-gate-receipt/v2" && gate.task_id === TASK_ID
      && gate.status === "PASS" && same(gate.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_GATE_NON_PASS", "preformal Gate is not an exact zero-effect PASS");
  // repositoryIdentity also contains dirty; compare the candidate explicitly below.
  const current = repositoryIdentity();
  assert(current.dirty === false && gate.candidate.commit === current.commit && gate.candidate.tree === current.tree,
    "REVIEWED_SOURCE_DRIFT", "Gate candidate differs from the current clean source");

  const sourcePath = join(reviewRoot, "PREFORMAL_SOURCE_MANIFEST.json");
  const source = parseExternalAt(gate.source_manifest, sourcePath, "preformal source manifest");
  const sourceEntries = verifySourceManifest(source.value);
  const sourceManifest = exactIdentity(source.path, source.bytes);
  const candidate = { commit: source.value.repository.commit, tree: source.value.repository.tree };
  assert(same(gate.candidate, candidate), "PREFORMAL_CANDIDATE_BINDING_INVALID", "Gate candidate differs from source manifest");

  const evidenceManifestPath = join(evidenceRoot, "EVIDENCE_MANIFEST.json");
  const evidence = parseExternalAt(gate.preformal_evidence_manifest, evidenceManifestPath, "preformal Evidence manifest");
  assert(evidence.value.task_id === TASK_ID && evidence.value.root_role === "PREFORMAL_SYNTHETIC_RAW_EVIDENCE",
    "PREFORMAL_EVIDENCE_INVALID", "preformal Evidence manifest identity is invalid");
  verifyClosedManifest(evidenceRoot, evidence.value);
  const evidenceManifest = exactIdentity(evidence.path, evidence.bytes);

  const evaluatorPath = join(reviewRoot, "INDEPENDENT_EVALUATOR_PACKAGE.json");
  const evaluator = parseExternalAt(gate.independent_evaluator_receipt, evaluatorPath, "independent evaluator package");
  const evaluatorPackage = exactIdentity(evaluator.path, evaluator.bytes);
  const paths = { auditRoot, reviewRoot, evidenceRoot };
  const bindings = { candidate, sourceManifest, evidenceManifest, evaluatorPackage };
  verifyPackage(evaluator, paths, bindings, cycle);

  assert(gate.freeze_origin.audit_root === auditRoot && gate.freeze_origin.review_root === reviewRoot
      && gate.freeze_origin.evidence_root === evidenceRoot && gate.freeze_origin.cycle === cycle,
  "PREFORMAL_FREEZE_ORIGIN_INVALID", "Gate freeze origin is not the exact Task-owned cycle");
  const freezerPath = "evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/freeze-preformal-gate.mjs";
  assert(same(gate.freeze_origin.freezer_source, sourceEntries.get(freezerPath)),
    "PREFORMAL_FREEZE_ORIGIN_INVALID", "Gate freezer source identity is not reviewed exact bytes");

  assert(Array.isArray(gate.reviews) && gate.reviews.length === 3, "PREFORMAL_REVIEW_SET_INVALID", "Gate must bind exactly three reviews");
  const roles = new Set();
  const reviewArtifacts = [];
  for (const binding of gate.reviews) {
    exactKeys(binding, REVIEW_BINDING_KEYS, "preformal review binding");
    assert(ROLES.includes(binding.role) && !roles.has(binding.role) && binding.verdict === "PASS",
      "PREFORMAL_REVIEW_SET_INVALID", "Gate review role set or verdict is invalid");
    roles.add(binding.role);
    const expectedPath = join(reviewRoot, REVIEW_FILES[binding.role]);
    const artifact = parseExternalAt(binding.artifact, expectedPath, `${binding.role} preformal review`);
    verifyReview(artifact, binding.role, bindings);
    reviewArtifacts.push(exactIdentity(artifact.path, artifact.bytes));
  }
  assert(ROLES.every((role) => roles.has(role)), "PREFORMAL_REVIEW_SET_INVALID", "Gate review role set is incomplete");

  const freezeResultPath = join(reviewRoot, "PREFORMAL_GATE_FREEZE_RESULT.json");
  const freezeResultBytes = readFileSync(safeRegularFile(freezeResultPath, "preformal Gate freeze result"));
  const freezeResult = parseExactJsonBytes(freezeResultBytes, { label: "preformal Gate freeze result", canonical: true });
  exactKeys(freezeResult, FREEZE_RESULT_KEYS, "preformal Gate freeze result");
  assert(freezeResult.schema_version === "p1-207-preformal-gate-freeze-result/v2"
      && freezeResult.task_id === TASK_ID && freezeResult.status === "PASS" && freezeResult.false_accepts === 0
      && same(freezeResult.candidate, candidate) && same(freezeResult.gate, exactIdentity(acceptedGatePath, gateBytes))
      && same(freezeResult.source_manifest, sourceManifest)
      && same(freezeResult.preformal_evidence_manifest, evidenceManifest)
      && same(freezeResult.independent_evaluator_receipt, evaluatorPackage)
      && same(freezeResult.reviews, reviewArtifacts)
      && same(freezeResult.freeze_origin, gate.freeze_origin)
      && same(freezeResult.external_effects, FALSE_EXTERNAL_EFFECTS),
  "PREFORMAL_FREEZE_RESULT_INVALID", "Gate does not equal the Task-owned freeze result exact bytes");

  return {
    gate,
    gate_bytes: gateBytes,
    gate_identity: exactIdentity(acceptedGatePath, gateBytes),
    source_manifest: source.value,
    evidence_manifest: evidence.value,
    evaluator_receipt: evaluator.value,
    freeze_result: freezeResult,
  };
}

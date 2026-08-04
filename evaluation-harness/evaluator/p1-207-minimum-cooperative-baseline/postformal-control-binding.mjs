import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { isDeepStrictEqual } from "node:util";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalBytes,
  exactKeys,
  normalizedRelativePath,
  parseExactJsonBytes,
  readExternalBoundFile,
  safeRealDirectory,
  safeRegularFile,
  verifyClosedManifest,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import { REPOSITORY_ROOT } from "../../harness/p1-149-accepted-execution-spine/core.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const EXECUTION_CANDIDATE = Object.freeze({
  commit: "eeb331666ae1e81e3c6cfc2eeab65fdb7f95d818",
  tree: "4e055228a253a0d145553d6380c71defdbd9981a",
});
const AUDIT_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207";
const FORMAL_ROOT = `${AUDIT_ROOT}/evidence/formal-execution-v1`;
const PREFORMAL_ROOT = `${AUDIT_ROOT}/evidence/preformal-v2`;
const REVIEW_ROOT = `${AUDIT_ROOT}/reviews/preformal-cycle-2`;
const AUTHORIZED_GATE_IDENTITY = Object.freeze({
  path: "PREFORMAL_GATE_RECEIPT.json",
  sha256: "dfadc8eca9f4419bd138f88e09b9015890f61db9ed7c184e8b9c2cc471c81996",
  byte_length: 2880,
});
const AUTHORIZED_PACKAGE_IDENTITY = Object.freeze({
  path: `${REVIEW_ROOT}/INDEPENDENT_EVALUATOR_PACKAGE.json`,
  sha256: "29344cc0cf2b804c98b75e9a9b7c6d3ae3021a86a4001ffd629105be7d3e7707",
  byte_length: 2754,
});
const AUTHORIZED_CONTROL_IDENTITY = Object.freeze({
  path: "accepted-controls/P1_129_CONTROL_RECEIPT.json",
  sha256: "0499fbde599773b0e118271d05a990c7ec171040ac61b18ad6382d1babedcf94",
  byte_length: 49382,
});
const GATE_KEYS = Object.freeze([
  "candidate", "external_effects", "freeze_origin", "independent_evaluator_receipt",
  "preformal_evidence_manifest", "reviews", "schema_version", "source_manifest",
  "status", "task_id",
]);
const FREEZE_ORIGIN_KEYS = Object.freeze([
  "audit_root", "cycle", "evidence_root", "freezer_source", "review_root",
]);
const PACKAGE_KEYS = Object.freeze([
  "denominator", "evidence_manifest", "external_effects", "false_accepts", "iteration",
  "gate_negative_matrix_receipt", "negative_matrix_receipt", "raw_evaluator_receipt",
  "raw_evidence_only_reconstruction", "report", "report_rebuild_receipt", "schema_version",
  "source_manifest", "status", "task_id", "worker_receipt",
]);
const RAW_EVALUATOR_KEYS = Object.freeze([
  "accepted_p1_129_control", "accepted_spine_reexecutions", "closed_inventory_entries",
  "denominator", "evidence_manifest", "external_effects", "false_accepts",
  "generated_report_used_as_input", "mode", "raw_evidence_only_reconstruction", "report",
  "report_identity", "schema_version", "status", "task_id", "taxonomy", "vtsr",
  "worker_success_fields_trusted",
]);
const SOURCE_MANIFEST_KEYS = Object.freeze(["entries", "repository", "schema_version", "task_id"]);
const SOURCE_ENTRY_KEYS = Object.freeze(["byte_length", "path", "sha256"]);
const REVIEW_BINDING_KEYS = Object.freeze(["artifact", "role", "verdict"]);
const REVIEW_KEYS = Object.freeze([
  "candidate", "checks", "evaluator_package", "findings", "out_of_scope_observations",
  "preformal_evidence_manifest", "reviewed_at", "role", "schema_version", "source_manifest",
  "target_verdict", "task_id",
]);
const REVIEW_CHECK_KEYS = Object.freeze(["check_id", "evidence", "status"]);
const REPORT_KEYS = Object.freeze([
  "aggregate_results", "artifact_type", "claim_boundary", "conclusion", "configurations",
  "dataset", "decision", "effect_size", "evaluator", "failure_taxonomy",
  "falsifiable_hypothesis", "limitations", "metric", "raw_results", "reproduction",
  "research_question", "schema_version", "source_and_environment",
  "stop_or_continue_rationale", "usage_and_cost",
]);
const REPORT_SOURCE_KEYS = Object.freeze([
  "accepted_p1_129_control", "configuration_receipt", "diagnostic", "environment_receipt",
  "evidence_manifest", "evidence_root", "run_receipt", "runtime", "source_snapshot",
]);
const ROLES = Object.freeze(["CTO", "SECURITY", "QUALITY"]);
const REVIEW_FILES = Object.freeze({
  CTO: "CTO_REVIEW.json",
  SECURITY: "SECURITY_REVIEW.json",
  QUALITY: "QUALITY_REVIEW.json",
});

function same(left, right) {
  return isDeepStrictEqual(left, right);
}

function exactIdentity(reference, label) {
  exactKeys(reference, ["byte_length", "path", "sha256"], `${label} identity`);
  assert(typeof reference.path === "string"
      && /^[0-9a-f]{64}$/.test(reference.sha256)
      && Number.isInteger(reference.byte_length)
      && reference.byte_length >= 0,
  "POSTFORMAL_IDENTITY_INVALID", `${label} identity is invalid`);
  return reference;
}

function parseLocalCanonical(path, expectedIdentity, label) {
  const acceptedPath = safeRegularFile(path, label, true);
  const bytes = readFileSync(acceptedPath);
  assert(same({ path: basename(acceptedPath), ...bytesIdentity(bytes) }, expectedIdentity),
    "POSTFORMAL_IDENTITY_MISMATCH", `${label} differs from the Founder-authorized bytes`);
  return {
    path: acceptedPath,
    bytes,
    value: parseExactJsonBytes(bytes, { label, canonical: true }),
  };
}

export function readExactExternalReference(reference, expectedPath, label) {
  exactIdentity(reference, label);
  assert(reference.path === expectedPath,
    "POSTFORMAL_PATH_BINDING_INVALID", `${label} is not at the exact bound path`);
  const record = readExternalBoundFile(reference, label);
  return {
    ...record,
    value: parseExactJsonBytes(record.bytes, { label, canonical: true }),
  };
}

function git(args, { bytes = false } = {}) {
  const result = spawnSync("/usr/bin/git", args, {
    cwd: REPOSITORY_ROOT,
    shell: false,
    encoding: bytes ? null : "utf8",
    maxBuffer: 16 * 1024 * 1024,
    env: {
      PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      LANG: "C",
      LC_ALL: "C",
      TZ: "UTC",
    },
  });
  assert(!result.error && result.status === 0,
    "POSTFORMAL_GIT_OBJECT_UNAVAILABLE", `git ${args.join(" ")} failed`);
  return bytes ? result.stdout : result.stdout.trim();
}

function verifyHistoricalSourceManifest(source) {
  exactKeys(source, SOURCE_MANIFEST_KEYS, "historical source manifest");
  exactKeys(source.repository, ["commit", "dirty", "tree"], "historical source repository");
  assert(source.schema_version === "p1-207-source-manifest/v1"
      && source.task_id === TASK_ID
      && source.repository.dirty === false
      && same({ commit: source.repository.commit, tree: source.repository.tree }, EXECUTION_CANDIDATE)
      && git(["rev-parse", `${source.repository.commit}^{tree}`]) === source.repository.tree,
  "POSTFORMAL_EXECUTION_SOURCE_INVALID", "historical execution source identity drifted");
  assert(Array.isArray(source.entries) && source.entries.length >= 10,
    "POSTFORMAL_SOURCE_MANIFEST_INVALID", "historical source manifest is incomplete");
  const entries = new Map();
  for (const entry of source.entries) {
    exactKeys(entry, SOURCE_ENTRY_KEYS, "historical source entry");
    normalizedRelativePath(entry.path, "historical source path");
    assert(!entries.has(entry.path), "POSTFORMAL_SOURCE_MANIFEST_INVALID", "historical source path is duplicated");
    const bytes = git(["show", `${source.repository.commit}:${entry.path}`], { bytes: true });
    assert(same(bytesIdentity(bytes), { sha256: entry.sha256, byte_length: entry.byte_length }),
      "POSTFORMAL_EXECUTION_SOURCE_INVALID", `historical source bytes drifted: ${entry.path}`);
    entries.set(entry.path, entry);
  }
  const freezerPath = "evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/freeze-preformal-gate.mjs";
  assert(entries.has(freezerPath), "POSTFORMAL_SOURCE_MANIFEST_INVALID", "historical source manifest omitted the Gate freezer");
  return entries;
}

function verifyReview(review, role, bindings) {
  exactKeys(review, REVIEW_KEYS, `${role} preformal review`);
  exactKeys(review.candidate, ["commit", "tree"], `${role} candidate`);
  assert(review.schema_version === "p1-207-preformal-review/v1"
      && review.task_id === TASK_ID
      && review.role === role
      && review.target_verdict === "PASS"
      && same(review.candidate, EXECUTION_CANDIDATE)
      && same(review.source_manifest, bindings.sourceManifest)
      && same(review.preformal_evidence_manifest, bindings.evidenceManifest)
      && same(review.evaluator_package, bindings.evaluatorPackage)
      && typeof review.reviewed_at === "string"
      && Number.isFinite(Date.parse(review.reviewed_at))
      && Array.isArray(review.checks)
      && review.checks.length >= 1
      && Array.isArray(review.findings)
      && review.findings.length === 0
      && Array.isArray(review.out_of_scope_observations),
  "POSTFORMAL_REVIEW_BINDING_INVALID", `${role} review is not the exact bound PASS`);
  const seen = new Set();
  for (const check of review.checks) {
    exactKeys(check, REVIEW_CHECK_KEYS, `${role} review check`);
    assert(typeof check.check_id === "string" && check.check_id.length > 0 && !seen.has(check.check_id)
        && typeof check.evidence === "string" && check.evidence.length > 0
        && check.status === "PASS",
    "POSTFORMAL_REVIEW_BINDING_INVALID", `${role} review contains an invalid check`);
    seen.add(check.check_id);
  }
}

export function validateTransitiveControlObjects({
  gate,
  sourceManifest,
  evaluatorPackage,
  rawEvaluator,
  reviewRecords,
  references,
}) {
  exactKeys(gate, GATE_KEYS, "formal copied preformal Gate");
  exactKeys(gate.candidate, ["commit", "tree"], "formal Gate candidate");
  exactKeys(gate.freeze_origin, FREEZE_ORIGIN_KEYS, "formal Gate freeze origin");
  assert(gate.schema_version === "p1-207-preformal-gate-receipt/v2"
      && gate.task_id === TASK_ID
      && gate.status === "PASS"
      && same(gate.candidate, EXECUTION_CANDIDATE)
      && same(gate.external_effects, FALSE_EXTERNAL_EFFECTS)
      && gate.freeze_origin.audit_root === AUDIT_ROOT
      && gate.freeze_origin.review_root === REVIEW_ROOT
      && gate.freeze_origin.evidence_root === PREFORMAL_ROOT
      && gate.freeze_origin.cycle === 2
      && gate.source_manifest.path === `${REVIEW_ROOT}/PREFORMAL_SOURCE_MANIFEST.json`
      && gate.preformal_evidence_manifest.path === `${PREFORMAL_ROOT}/EVIDENCE_MANIFEST.json`
      && same(gate.independent_evaluator_receipt, AUTHORIZED_PACKAGE_IDENTITY),
  "POSTFORMAL_GATE_BINDING_INVALID", "formal Gate origin or candidate drifted");

  exactKeys(evaluatorPackage, PACKAGE_KEYS, "preformal evaluator package");
  assert(evaluatorPackage.schema_version === "p1-207-preformal-independent-evaluator-package/v1"
      && evaluatorPackage.task_id === TASK_ID
      && evaluatorPackage.status === "PASS"
      && evaluatorPackage.iteration === 2
      && evaluatorPackage.denominator === 36
      && evaluatorPackage.false_accepts === 0
      && evaluatorPackage.raw_evidence_only_reconstruction === true
      && same(evaluatorPackage.external_effects, FALSE_EXTERNAL_EFFECTS)
      && same(evaluatorPackage.source_manifest, gate.source_manifest)
      && same(evaluatorPackage.evidence_manifest, gate.preformal_evidence_manifest)
      && same(evaluatorPackage.raw_evaluator_receipt, references.rawEvaluator),
  "POSTFORMAL_PACKAGE_BINDING_INVALID", "preformal evaluator package drifted");

  exactKeys(rawEvaluator, RAW_EVALUATOR_KEYS, "raw preformal evaluator receipt");
  exactKeys(rawEvaluator.report, REPORT_KEYS, "raw preformal report");
  exactKeys(rawEvaluator.report.source_and_environment, REPORT_SOURCE_KEYS, "raw report source and environment");
  assert(rawEvaluator.schema_version === "p1-207-independent-evaluator-receipt/v1"
      && rawEvaluator.task_id === TASK_ID
      && rawEvaluator.status === "PASS"
      && rawEvaluator.mode === "SYNTHETIC"
      && rawEvaluator.denominator === 36
      && rawEvaluator.false_accepts === 0
      && rawEvaluator.raw_evidence_only_reconstruction === true
      && rawEvaluator.generated_report_used_as_input === false
      && rawEvaluator.worker_success_fields_trusted === false
      && rawEvaluator.accepted_spine_reexecutions === 36
      && same(rawEvaluator.external_effects, FALSE_EXTERNAL_EFFECTS)
      && same(rawEvaluator.accepted_p1_129_control, AUTHORIZED_CONTROL_IDENTITY)
      && same(rawEvaluator.report.source_and_environment.accepted_p1_129_control, AUTHORIZED_CONTROL_IDENTITY)
      && same(rawEvaluator.report.source_and_environment.source_snapshot, {
        ...EXECUTION_CANDIDATE,
        dirty: false,
      })
      && rawEvaluator.report.source_and_environment.evidence_root === PREFORMAL_ROOT
      && same(rawEvaluator.report_identity, bytesIdentity(canonicalBytes(rawEvaluator.report))),
  "POSTFORMAL_RAW_EVALUATOR_BINDING_INVALID", "raw evaluator does not transitively bind the accepted control and execution candidate");

  const sourceEntries = verifyHistoricalSourceManifest(sourceManifest);
  assert(same(gate.freeze_origin.freezer_source,
    sourceEntries.get("evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/freeze-preformal-gate.mjs")),
  "POSTFORMAL_FREEZE_SOURCE_INVALID", "Gate freezer does not bind historical reviewed source bytes");

  assert(Array.isArray(gate.reviews) && gate.reviews.length === 3,
    "POSTFORMAL_REVIEW_SET_INVALID", "formal Gate must bind exactly three reviews");
  const bindings = {
    sourceManifest: gate.source_manifest,
    evidenceManifest: gate.preformal_evidence_manifest,
    evaluatorPackage: gate.independent_evaluator_receipt,
  };
  const roles = new Set();
  for (const binding of gate.reviews) {
    exactKeys(binding, REVIEW_BINDING_KEYS, "formal Gate review binding");
    assert(ROLES.includes(binding.role) && !roles.has(binding.role) && binding.verdict === "PASS",
      "POSTFORMAL_REVIEW_SET_INVALID", "formal Gate review role is missing, duplicated, unknown or NON_PASS");
    roles.add(binding.role);
    const record = reviewRecords.get(binding.role);
    assert(record !== undefined && same(binding.artifact, record.reference),
      "POSTFORMAL_REVIEW_BINDING_INVALID", `${binding.role} review bytes are not the Gate-bound artifact`);
    verifyReview(record.value, binding.role, bindings);
  }
  assert(ROLES.every((role) => roles.has(role)),
    "POSTFORMAL_REVIEW_SET_INVALID", "formal Gate review role set is incomplete");
  return true;
}

function validatePackageReferences(packageValue) {
  const expected = new Map([
    ["worker_receipt", `${REVIEW_ROOT}/PREFORMAL_WORKER_RECEIPT.json`],
    ["report", `${PREFORMAL_ROOT}/report/REPRODUCIBLE_BASELINE_REPORT.json`],
    ["report_rebuild_receipt", `${PREFORMAL_ROOT}/report/REPORT_REBUILD_RECEIPT.json`],
    ["negative_matrix_receipt", `${REVIEW_ROOT}/INDEPENDENT_NEGATIVE_MATRIX_RECEIPT.json`],
    ["gate_negative_matrix_receipt", `${REVIEW_ROOT}/GATE_CONSUMER_NEGATIVE_MATRIX_RECEIPT.json`],
  ]);
  const records = new Map();
  for (const [field, path] of expected) {
    records.set(field, readExactExternalReference(packageValue[field], path, `preformal package ${field}`));
  }
  return records;
}

export function resolvePostformalAcceptedControlBinding(evidenceRoot) {
  const root = safeRealDirectory(resolve(evidenceRoot), "P1-207 formal Evidence root");
  assert(root === FORMAL_ROOT,
    "POSTFORMAL_FORMAL_ROOT_INVALID", "postformal evaluation is restricted to the exact completed formal Evidence root");
  const gateRecord = parseLocalCanonical(
    join(root, AUTHORIZED_GATE_IDENTITY.path),
    AUTHORIZED_GATE_IDENTITY,
    "formal copied preformal Gate",
  );
  const gate = gateRecord.value;
  exactKeys(gate, GATE_KEYS, "formal copied preformal Gate");
  const sourceRecord = readExactExternalReference(
    gate.source_manifest,
    `${REVIEW_ROOT}/PREFORMAL_SOURCE_MANIFEST.json`,
    "preformal source manifest",
  );
  const evidenceManifestRecord = readExactExternalReference(
    gate.preformal_evidence_manifest,
    `${PREFORMAL_ROOT}/EVIDENCE_MANIFEST.json`,
    "preformal Evidence manifest",
  );
  assert(evidenceManifestRecord.value.task_id === TASK_ID
      && evidenceManifestRecord.value.root_role === "PREFORMAL_SYNTHETIC_RAW_EVIDENCE",
  "POSTFORMAL_PREFORMAL_EVIDENCE_INVALID", "preformal Evidence manifest identity drifted");
  verifyClosedManifest(PREFORMAL_ROOT, evidenceManifestRecord.value, {
    exclude: evidenceManifestRecord.value.excluded_paths,
  });
  assert(same(gate.independent_evaluator_receipt, AUTHORIZED_PACKAGE_IDENTITY),
    "POSTFORMAL_PACKAGE_BINDING_INVALID", "Gate does not bind the Founder-authorized evaluator package");
  const packageRecord = readExactExternalReference(
    gate.independent_evaluator_receipt,
    AUTHORIZED_PACKAGE_IDENTITY.path,
    "preformal evaluator package",
  );
  const packageReferences = validatePackageReferences(packageRecord.value);
  const rawEvaluatorRecord = readExactExternalReference(
    packageRecord.value.raw_evaluator_receipt,
    `${REVIEW_ROOT}/RAW_INDEPENDENT_EVALUATOR_RECEIPT.json`,
    "raw preformal evaluator receipt",
  );
  const reportRecord = packageReferences.get("report");
  assert(reportRecord.bytes.equals(canonicalBytes(rawEvaluatorRecord.value.report))
      && same(bytesIdentity(reportRecord.bytes), rawEvaluatorRecord.value.report_identity),
  "POSTFORMAL_RAW_EVALUATOR_BINDING_INVALID", "raw evaluator report differs from the package-bound report bytes");

  const reviewRecords = new Map();
  for (const binding of gate.reviews ?? []) {
    if (!ROLES.includes(binding?.role) || reviewRecords.has(binding.role)) continue;
    const expectedPath = `${REVIEW_ROOT}/${REVIEW_FILES[binding.role]}`;
    const record = readExactExternalReference(binding.artifact, expectedPath, `${binding.role} preformal review`);
    reviewRecords.set(binding.role, { ...record, reference: binding.artifact });
  }
  validateTransitiveControlObjects({
    gate,
    sourceManifest: sourceRecord.value,
    evaluatorPackage: packageRecord.value,
    rawEvaluator: rawEvaluatorRecord.value,
    reviewRecords,
    references: { rawEvaluator: packageRecord.value.raw_evaluator_receipt },
  });

  assert(same(rawEvaluatorRecord.value.accepted_p1_129_control, AUTHORIZED_CONTROL_IDENTITY),
    "POSTFORMAL_CONTROL_BINDING_INVALID", "raw evaluator accepted-control identity drifted");
  const controlPath = `${PREFORMAL_ROOT}/${AUTHORIZED_CONTROL_IDENTITY.path}`;
  const controlBytes = readFileSync(safeRegularFile(controlPath, "exact preformal P1-129 control receipt", true));
  assert(same(bytesIdentity(controlBytes), {
    sha256: AUTHORIZED_CONTROL_IDENTITY.sha256,
    byte_length: AUTHORIZED_CONTROL_IDENTITY.byte_length,
  }), "POSTFORMAL_CONTROL_BINDING_INVALID", "exact preformal P1-129 control bytes drifted");

  return {
    control_root: PREFORMAL_ROOT,
    execution_candidate: EXECUTION_CANDIDATE,
    accepted_p1_129_control: AUTHORIZED_CONTROL_IDENTITY,
    binding_chain: {
      formal_gate: AUTHORIZED_GATE_IDENTITY,
      preformal_evaluator_package: AUTHORIZED_PACKAGE_IDENTITY,
      raw_evaluator_receipt: {
        path: packageRecord.value.raw_evaluator_receipt.path,
        ...bytesIdentity(rawEvaluatorRecord.bytes),
      },
      preformal_evidence_manifest: gate.preformal_evidence_manifest,
      accepted_p1_129_control: {
        path: controlPath,
        ...bytesIdentity(controlBytes),
      },
      reviewed_execution_candidate: EXECUTION_CANDIDATE,
      preformal_review_roles: ROLES,
    },
  };
}

export const POSTFORMAL_AUTHORIZED_IDENTITIES = Object.freeze({
  audit_root: AUDIT_ROOT,
  formal_root: FORMAL_ROOT,
  preformal_root: PREFORMAL_ROOT,
  review_root: REVIEW_ROOT,
  execution_candidate: EXECUTION_CANDIDATE,
  formal_gate: AUTHORIZED_GATE_IDENTITY,
  evaluator_package: AUTHORIZED_PACKAGE_IDENTITY,
  accepted_p1_129_control: AUTHORIZED_CONTROL_IDENTITY,
});

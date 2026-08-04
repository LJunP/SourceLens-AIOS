#!/usr/bin/env node

import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import {
  FALSE_EXTERNAL_EFFECTS,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  parseExactJsonBytes,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import {
  POSTFORMAL_AUTHORIZED_IDENTITIES,
  readExactExternalReference,
  resolvePostformalAcceptedControlBinding,
  validateTransitiveControlObjects,
} from "./postformal-control-binding.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const REVIEW_FILES = Object.freeze({
  CTO: "CTO_REVIEW.json",
  SECURITY: "SECURITY_REVIEW.json",
  QUALITY: "QUALITY_REVIEW.json",
});

function readCanonical(path, label) {
  const bytes = readFileSync(path);
  return {
    path,
    bytes,
    value: parseExactJsonBytes(bytes, { label, canonical: true }),
  };
}

function loadGolden() {
  const { formal_root: formalRoot, review_root: reviewRoot } = POSTFORMAL_AUTHORIZED_IDENTITIES;
  const gateRecord = readCanonical(join(formalRoot, "PREFORMAL_GATE_RECEIPT.json"), "golden formal Gate");
  const sourceRecord = readCanonical(join(reviewRoot, "PREFORMAL_SOURCE_MANIFEST.json"), "golden source manifest");
  const packageRecord = readCanonical(join(reviewRoot, "INDEPENDENT_EVALUATOR_PACKAGE.json"), "golden evaluator package");
  const rawRecord = readCanonical(join(reviewRoot, "RAW_INDEPENDENT_EVALUATOR_RECEIPT.json"), "golden raw evaluator");
  const reviewRecords = new Map();
  for (const binding of gateRecord.value.reviews) {
    const record = readCanonical(join(reviewRoot, REVIEW_FILES[binding.role]), `golden ${binding.role} review`);
    reviewRecords.set(binding.role, { ...record, reference: binding.artifact });
  }
  return {
    gate: gateRecord.value,
    sourceManifest: sourceRecord.value,
    evaluatorPackage: packageRecord.value,
    rawEvaluator: rawRecord.value,
    reviewRecords,
    references: { rawEvaluator: packageRecord.value.raw_evaluator_receipt },
  };
}

function cloneGolden() {
  const golden = loadGolden();
  return {
    ...structuredClone({
      gate: golden.gate,
      sourceManifest: golden.sourceManifest,
      evaluatorPackage: golden.evaluatorPackage,
      rawEvaluator: golden.rawEvaluator,
    }),
    references: structuredClone(golden.references),
    reviewRecords: new Map([...golden.reviewRecords].map(([role, record]) => [role, {
      reference: structuredClone(record.reference),
      value: structuredClone(record.value),
    }])),
  };
}

function runObjectCase(definition) {
  const fixture = cloneGolden();
  definition.mutate(fixture);
  try {
    validateTransitiveControlObjects(fixture);
    return { case_id: definition.case_id, rejected: false, observed_reason: "UNEXPECTED_PASS" };
  } catch (error) {
    return {
      case_id: definition.case_id,
      rejected: true,
      observed_reason: error.reasonCode ?? error.code ?? error.name,
    };
  }
}

function runPathCases(parent) {
  const results = [];
  const validPath = join(parent, "valid.json");
  const validBytes = canonicalBytes({ schema_version: "path-fixture/v1", status: "PASS" });
  writeFileSync(validPath, validBytes, { flag: "wx", mode: 0o600 });
  const validReference = { path: validPath, ...bytesIdentity(validBytes) };

  const definitions = [
    {
      case_id: "EXTERNAL_MISSING",
      invoke() {
        const path = join(parent, "missing.json");
        readExactExternalReference({ path, ...bytesIdentity(validBytes) }, path, "missing external fixture");
      },
    },
    {
      case_id: "EXTERNAL_MUTATION",
      invoke() {
        readExactExternalReference({ ...validReference, sha256: "0".repeat(64) }, validPath, "mutated external fixture");
      },
    },
    {
      case_id: "EXTERNAL_PATH_SUBSTITUTION",
      invoke() {
        readExactExternalReference(validReference, join(parent, "different.json"), "substituted external fixture");
      },
    },
    {
      case_id: "EXTERNAL_SYMLINK",
      invoke() {
        const path = join(parent, "symlink.json");
        symlinkSync(validPath, path);
        readExactExternalReference({ path, ...bytesIdentity(validBytes) }, path, "symlink external fixture");
      },
    },
  ];
  for (const definition of definitions) {
    try {
      definition.invoke();
      results.push({ case_id: definition.case_id, rejected: false, observed_reason: "UNEXPECTED_PASS" });
    } catch (error) {
      results.push({
        case_id: definition.case_id,
        rejected: true,
        observed_reason: error.reasonCode ?? error.code ?? error.name,
      });
    }
  }
  return results;
}

export function runPostformalControlNegativeMatrix() {
  const parent = mkdtempSync("/private/tmp/sourcelens-p1-207-postformal-control-");
  let cleaned = false;
  try {
    mkdirSync(join(parent, "path-cases"), { recursive: false, mode: 0o700 });
    const golden = resolvePostformalAcceptedControlBinding(POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root);
    const definitions = [
      { case_id: "GATE_EXTRA_FIELD", mutate(value) { value.gate.unexpected = true; } },
      { case_id: "GATE_MISSING_FIELD", mutate(value) { delete value.gate.status; } },
      { case_id: "GATE_WRONG_ROOT", mutate(value) { value.gate.freeze_origin.evidence_root = "/private/tmp/wrong-root"; } },
      { case_id: "GATE_CROSS_CANDIDATE", mutate(value) { value.gate.candidate.commit = "0".repeat(40); } },
      { case_id: "GATE_PACKAGE_SUBSTITUTION", mutate(value) { value.gate.independent_evaluator_receipt.sha256 = "0".repeat(64); } },
      { case_id: "MISSING_REVIEWER", mutate(value) { value.gate.reviews.pop(); } },
      { case_id: "DUPLICATE_REVIEWER", mutate(value) { value.gate.reviews[2].role = "CTO"; } },
      { case_id: "UNKNOWN_REVIEWER", mutate(value) { value.gate.reviews[2].role = "LEGAL"; } },
      { case_id: "STALE_REVIEW_CANDIDATE", mutate(value) { value.reviewRecords.get("SECURITY").value.candidate.tree = "1".repeat(40); } },
      { case_id: "REVIEW_EXTRA_FIELD", mutate(value) { value.reviewRecords.get("QUALITY").value.unexpected = true; } },
      { case_id: "PACKAGE_RAW_PATH_SUBSTITUTION", mutate(value) { value.evaluatorPackage.raw_evaluator_receipt.path = "/private/tmp/substituted.json"; } },
      { case_id: "RAW_CONTROL_IDENTITY_MUTATION", mutate(value) { value.rawEvaluator.accepted_p1_129_control.sha256 = "2".repeat(64); } },
      { case_id: "RAW_CONTROL_CROSS_BINDING", mutate(value) { value.rawEvaluator.report.source_and_environment.accepted_p1_129_control.sha256 = "3".repeat(64); } },
      { case_id: "RAW_EXECUTION_SOURCE_STALE", mutate(value) { value.rawEvaluator.report.source_and_environment.source_snapshot.commit = "4".repeat(40); } },
      { case_id: "RAW_REPORT_IDENTITY_MUTATION", mutate(value) { value.rawEvaluator.report_identity.sha256 = "5".repeat(64); } },
    ];
    const results = definitions.map(runObjectCase);
    results.push(...runPathCases(join(parent, "path-cases")));
    const falseAccepts = results.filter((result) => !result.rejected).length;
    return {
      schema_version: "p1-207-postformal-control-negative-matrix/v1",
      task_id: TASK_ID,
      status: falseAccepts === 0 ? "PASS" : "NON_PASS",
      golden_status: golden.accepted_p1_129_control.sha256
        === POSTFORMAL_AUTHORIZED_IDENTITIES.accepted_p1_129_control.sha256 ? "PASS" : "NON_PASS",
      cases: results.length,
      false_accepts: falseAccepts,
      results,
      disposable_root_cleaned: true,
      provider_requests: 0,
      secret_reads: 0,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
  } finally {
    rmSync(parent, { recursive: true, force: true });
    cleaned = true;
    void cleaned;
  }
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  try {
    const result = runPostformalControlNegativeMatrix();
    process.stdout.write(`${canonicalJson(result)}\n`);
    if (result.status !== "PASS") process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-207-postformal-control-negative-matrix-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: error.reasonCode ?? error.code ?? error.name,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { runPreformal } from "../../harness/p1-207-minimum-cooperative-baseline/preformal.mjs";
import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalJson,
  createOwnedRoot,
  safeRealDirectory,
  safeRegularFile,
  writeJsonCreateOnce,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import { REPOSITORY_ROOT } from "../../harness/p1-149-accepted-execution-spine/core.mjs";
import { evaluateEvidence } from "./evaluate.mjs";
import { runGateNegativeMatrix } from "./gate-negative-matrix.mjs";
import { runNegativeMatrix } from "./negative-matrix.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const ACTIVATION_PARENT = "5133b6fe8ecb0405f86b46a9a072f96e77cdb45d";
const AUDIT_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207";
const SOURCE_PREFIXES = Object.freeze([
  "evaluation-harness/harness/p1-207-minimum-cooperative-baseline/",
  "evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/",
]);
const EXACT_SOURCE_PATHS = Object.freeze([
  "scripts/p1-207-operator-capture.sh",
  "scripts/verify-p1-207-minimum-cooperative-baseline.sh",
]);
const ALLOWLIST_EXACT = new Set([
  ...EXACT_SOURCE_PATHS,
  "docs/aios/tasks/P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE.yaml",
  "docs/aios/truth/project_state.yaml",
  "docs/PROJECT_CODE_MAP.md",
]);

function git(args) {
  const result = spawnSync("/usr/bin/git", args, {
    cwd: REPOSITORY_ROOT,
    shell: false,
    encoding: "utf8",
    env: { PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", LANG: "C", LC_ALL: "C", TZ: "UTC" },
  });
  assert(!result.error && result.status === 0, "SOURCE_IDENTITY_UNAVAILABLE", `git ${args.join(" ")} failed`);
  return result.stdout.trim();
}

function repositoryIdentity() {
  return {
    commit: git(["rev-parse", "HEAD"]),
    tree: git(["rev-parse", "HEAD^{tree}"]),
    dirty: git(["status", "--porcelain", "--untracked-files=all"]) !== "",
  };
}

function acceptedSourcePath(path) {
  return SOURCE_PREFIXES.some((prefix) => path.startsWith(prefix)) || ALLOWLIST_EXACT.has(path);
}

function sourceManifest() {
  const repository = repositoryIdentity();
  assert(repository.dirty === false, "SOURCE_NOT_CLEAN", "preformal source must be an exact clean commit");
  const engineering = git(["ls-files", "--",
    ...SOURCE_PREFIXES.map((prefix) => prefix.slice(0, -1)),
    ...EXACT_SOURCE_PATHS,
  ]).split("\n").filter(Boolean);
  const changed = git(["diff", "--name-only", ACTIVATION_PARENT, "HEAD"])
    .split("\n").filter(Boolean);
  const paths = [...new Set([...engineering, ...changed])].sort();
  assert(paths.length >= 14 && paths.every(acceptedSourcePath),
    "SOURCE_ALLOWLIST_DRIFT", "candidate source set is incomplete or outside the Task allowlist");
  const entries = paths.map((path) => {
    const bytes = readFileSync(safeRegularFile(join(REPOSITORY_ROOT, ...path.split("/")), `candidate source ${path}`, true));
    return { path, ...bytesIdentity(bytes) };
  });
  return {
    schema_version: "p1-207-source-manifest/v1",
    task_id: TASK_ID,
    repository,
    entries,
  };
}

function externalIdentity(root, identity) {
  return { path: join(root, ...identity.path.split("/")), sha256: identity.sha256, byte_length: identity.byte_length };
}

function ensureReviewRoot(path) {
  const reviewsParent = dirname(path);
  if (!existsSync(reviewsParent)) {
    assert(dirname(reviewsParent) === AUDIT_ROOT, "REVIEW_ROOT_INVALID", "review parent is outside the Task audit root");
    safeRealDirectory(AUDIT_ROOT, "Task audit root");
    mkdirSync(reviewsParent, { recursive: false, mode: 0o700 });
  } else {
    safeRealDirectory(reviewsParent, "preformal reviews parent");
  }
  return createOwnedRoot(path);
}

function validateDestinations(evidenceRoot, reviewRoot) {
  assert(resolve(evidenceRoot) === evidenceRoot && resolve(reviewRoot) === reviewRoot,
    "PREFORMAL_ROOT_INVALID", "preformal roots must be normalized absolute paths");
  const evidenceMatch = basename(evidenceRoot).match(/^preformal-v([1-4])$/);
  const reviewMatch = basename(reviewRoot).match(/^preformal-cycle-([1-4])$/);
  assert(evidenceMatch && reviewMatch && evidenceMatch[1] === reviewMatch[1]
      && dirname(evidenceRoot) === join(AUDIT_ROOT, "evidence")
      && dirname(reviewRoot) === join(AUDIT_ROOT, "reviews")
      && !existsSync(evidenceRoot)
      && !existsSync(reviewRoot),
  "PREFORMAL_ROOT_INVALID", "preformal roots are not the matching absent owned Task paths");
  safeRealDirectory(dirname(evidenceRoot), "preformal Evidence parent");
  return Number(evidenceMatch[1]);
}

export async function preparePreformal(evidenceRoot, reviewRoot) {
  const iteration = validateDestinations(evidenceRoot, reviewRoot);
  ensureReviewRoot(reviewRoot);
  const source = sourceManifest();
  const sourceIdentity = writeJsonCreateOnce(reviewRoot, "PREFORMAL_SOURCE_MANIFEST.json", source);

  const worker = await runPreformal(evidenceRoot);
  assert(worker.status === "PASS" && worker.provider_requests === 0 && worker.secret_reads === 0
      && worker.false_accepts === 0,
  "PREFORMAL_WORKER_NON_PASS", "synthetic preformal Worker did not produce a zero-effect PASS");
  const workerIdentity = writeJsonCreateOnce(reviewRoot, "PREFORMAL_WORKER_RECEIPT.json", worker);

  const evaluator = evaluateEvidence(evidenceRoot);
  assert(evaluator.status === "PASS" && evaluator.mode === "SYNTHETIC" && evaluator.false_accepts === 0,
    "PREFORMAL_EVALUATOR_NON_PASS", "independent evaluator did not reconstruct the synthetic Evidence");
  const reportIdentity = writeJsonCreateOnce(evidenceRoot, "report/REPRODUCIBLE_BASELINE_REPORT.json", evaluator.report);
  const rawEvaluatorIdentity = writeJsonCreateOnce(reviewRoot, "RAW_INDEPENDENT_EVALUATOR_RECEIPT.json", evaluator);
  const evidenceManifestPath = join(evidenceRoot, "EVIDENCE_MANIFEST.json");
  const evidenceManifestBytes = readFileSync(safeRegularFile(evidenceManifestPath, "preformal Evidence manifest", true));
  const evidenceManifestIdentity = { path: evidenceManifestPath, ...bytesIdentity(evidenceManifestBytes) };
  const rebuild = {
    schema_version: "p1-207-report-rebuild-receipt/v1",
    task_id: TASK_ID,
    status: "PASS",
    mode: "SYNTHETIC",
    raw_evidence_only: true,
    generated_report_used_as_input: false,
    evidence_manifest: evidenceManifestIdentity,
    evaluator: externalIdentity(reviewRoot, rawEvaluatorIdentity),
    report: externalIdentity(evidenceRoot, reportIdentity),
    denominator: 36,
    taxonomy: evaluator.taxonomy,
    false_accepts: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const rebuildIdentity = writeJsonCreateOnce(evidenceRoot, "report/REPORT_REBUILD_RECEIPT.json", rebuild);

  const negative = runNegativeMatrix(evidenceRoot, { goldenReceipt: evaluator });
  assert(negative.status === "PASS" && negative.false_accepts === 0,
    "PREFORMAL_NEGATIVE_MATRIX_NON_PASS", "independent negative matrix contains a false accept");
  const negativeIdentity = writeJsonCreateOnce(reviewRoot, "INDEPENDENT_NEGATIVE_MATRIX_RECEIPT.json", negative);
  const gateNegative = runGateNegativeMatrix(source);
  assert(gateNegative.status === "PASS" && gateNegative.false_accepts === 0,
    "PREFORMAL_GATE_NEGATIVE_MATRIX_NON_PASS", "Gate consumer negative matrix contains a false accept");
  const gateNegativeIdentity = writeJsonCreateOnce(reviewRoot, "GATE_CONSUMER_NEGATIVE_MATRIX_RECEIPT.json", gateNegative);
  const evaluatorPackage = {
    schema_version: "p1-207-preformal-independent-evaluator-package/v1",
    task_id: TASK_ID,
    status: "PASS",
    iteration,
    source_manifest: externalIdentity(reviewRoot, sourceIdentity),
    worker_receipt: externalIdentity(reviewRoot, workerIdentity),
    evidence_manifest: evidenceManifestIdentity,
    raw_evaluator_receipt: externalIdentity(reviewRoot, rawEvaluatorIdentity),
    report: externalIdentity(evidenceRoot, reportIdentity),
    report_rebuild_receipt: externalIdentity(evidenceRoot, rebuildIdentity),
    negative_matrix_receipt: externalIdentity(reviewRoot, negativeIdentity),
    gate_negative_matrix_receipt: externalIdentity(reviewRoot, gateNegativeIdentity),
    denominator: 36,
    false_accepts: 0,
    raw_evidence_only_reconstruction: true,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const packageIdentity = writeJsonCreateOnce(reviewRoot, "INDEPENDENT_EVALUATOR_PACKAGE.json", evaluatorPackage);
  return {
    schema_version: "p1-207-preformal-preparation-result/v1",
    task_id: TASK_ID,
    status: "PASS",
    iteration,
    source_manifest: externalIdentity(reviewRoot, sourceIdentity),
    worker_receipt: externalIdentity(reviewRoot, workerIdentity),
    evidence_manifest: evidenceManifestIdentity,
    evaluator_package: externalIdentity(reviewRoot, packageIdentity),
    negative_matrix: externalIdentity(reviewRoot, negativeIdentity),
    gate_negative_matrix: externalIdentity(reviewRoot, gateNegativeIdentity),
    synthetic_cells: 36,
    false_accepts: 0,
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
    assert(process.argv.length === 4, "CLI_USAGE_INVALID", "usage: prepare-preformal.mjs EVIDENCE_ROOT REVIEW_ROOT");
    const result = await preparePreformal(process.argv[2], process.argv[3]);
    process.stdout.write(`${canonicalJson(result)}\n`);
  } catch (error) {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-207-preformal-preparation-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: error.reasonCode ?? error.code ?? error.name,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

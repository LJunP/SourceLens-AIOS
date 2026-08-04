#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

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
import { POSTFORMAL_AUTHORIZED_IDENTITIES } from "./postformal-control-binding.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const CANONICAL_PARENT = Object.freeze({
  commit: "96917278bc12232eb877cf8ee5a06050fa2e9310",
  tree: "b081b2f7ba6013319316371dcaab317d4425fc04",
});
const EXECUTION_CANDIDATE = POSTFORMAL_AUTHORIZED_IDENTITIES.execution_candidate;
const AUDIT_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207";
const ROUTE_AUDIT_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804";
const REVIEW_ROOT = `${AUDIT_ROOT}/reviews/postformal-final-cycle-1`;
const AUTHORIZATION = Object.freeze({
  path: `${ROUTE_AUDIT_ROOT}/founder-phase-gate/FOUNDER_P1_207_POSTFORMAL_TRANSITIVE_CONTROL_BINDING_CORRECTION_V1.md`,
  sha256: "8e7f40a46ef5d6f65f1b751885d8537b0db86e129033874a2d7436bbf496f543",
  byte_length: 4652,
});
const FORMAL_IDENTITIES = Object.freeze({
  evidence_manifest: {
    path: `${POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root}/EVIDENCE_MANIFEST.json`,
    sha256: "31e439cc3e3a993916fffd836d6883722e4570719d6a93c5b38b6a29c703504f",
    byte_length: 31196,
  },
  run_receipt: {
    path: `${POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root}/RUN_RECEIPT.json`,
    sha256: "5352b9071bffa4c1952f1c1388af8c05f9726d03fefb85e23e1164ff544fe227",
    byte_length: 745,
  },
  copied_preformal_gate: {
    path: `${POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root}/PREFORMAL_GATE_RECEIPT.json`,
    sha256: "dfadc8eca9f4419bd138f88e09b9015890f61db9ed7c184e8b9c2cc471c81996",
    byte_length: 2880,
  },
});
const POSTFORMAL_OUTPUTS = Object.freeze({
  report: `${POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root}/report/REPRODUCIBLE_BASELINE_REPORT.json`,
  evaluator: `${POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root}/reviews/INDEPENDENT_EVALUATOR_RECEIPT.json`,
  rebuild: `${POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root}/report/REPORT_REBUILD_RECEIPT.json`,
});
const CORRECTION_PREFIX = "evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/";
const CORRECTION_EXACT = new Set([
  "scripts/verify-p1-207-minimum-cooperative-baseline.sh",
  "docs/aios/tasks/P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE.yaml",
  "docs/aios/truth/project_state.yaml",
  "docs/PROJECT_CODE_MAP.md",
]);
const INHERITED_PREFIX = "evaluation-harness/harness/p1-207-minimum-cooperative-baseline/";
const INHERITED_EXACT = new Set(["scripts/p1-207-operator-capture.sh"]);

function git(args, { bytes = false } = {}) {
  const result = spawnSync("/usr/bin/git", args, {
    cwd: REPOSITORY_ROOT,
    shell: false,
    encoding: bytes ? null : "utf8",
    maxBuffer: 32 * 1024 * 1024,
    env: { PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", LANG: "C", LC_ALL: "C", TZ: "UTC" },
  });
  assert(!result.error && result.status === 0,
    "POSTFORMAL_GIT_FAILURE", `git ${args.join(" ")} failed`);
  return bytes ? result.stdout : result.stdout.trim();
}

function externalIdentity(path, label) {
  const bytes = readFileSync(safeRegularFile(path, label, true));
  return { path, ...bytesIdentity(bytes) };
}

function ensureExact(reference, label) {
  const observed = externalIdentity(reference.path, label);
  assert(observed.sha256 === reference.sha256 && observed.byte_length === reference.byte_length,
    "POSTFORMAL_EXTERNAL_IDENTITY_DRIFT", `${label} differs from the Founder-authorized identity`);
  return observed;
}

function candidateIdentity() {
  const commit = git(["rev-parse", "HEAD^{commit}"]);
  const tree = git(["rev-parse", "HEAD^{tree}"]);
  const parent = git(["rev-parse", "HEAD^"]);
  const parentTree = git(["rev-parse", `${parent}^{tree}`]);
  assert(parent === CANONICAL_PARENT.commit && parentTree === CANONICAL_PARENT.tree,
    "POSTFORMAL_CANDIDATE_PARENT_INVALID", "corrected candidate is not the single child of the exact canonical parent");
  assert(git(["status", "--porcelain", "--untracked-files=all"]) === "",
    "POSTFORMAL_CANDIDATE_DIRTY", "corrected candidate must be one clean committed tree");
  return { commit, tree, parent_commit: parent, parent_tree: parentTree };
}

function sourceManifest(candidate) {
  const changed = git(["diff", "--name-only", "--diff-filter=ACMR", CANONICAL_PARENT.commit, candidate.commit])
    .split("\n").filter(Boolean).sort();
  const deleted = git(["diff", "--name-only", "--diff-filter=D", CANONICAL_PARENT.commit, candidate.commit])
    .split("\n").filter(Boolean);
  assert(changed.length >= 20 && deleted.length === 0,
    "POSTFORMAL_SOURCE_SET_INVALID", "corrected candidate source set is incomplete or deletes canonical files");
  const entries = changed.map((path) => {
    const correctionPath = path.startsWith(CORRECTION_PREFIX) || CORRECTION_EXACT.has(path);
    const inheritedPath = path.startsWith(INHERITED_PREFIX) || INHERITED_EXACT.has(path);
    assert(correctionPath || inheritedPath,
      "POSTFORMAL_SOURCE_SCOPE_INVALID", `candidate path is outside the exact correction/inherited set: ${path}`);
    const bytes = git(["show", `${candidate.commit}:${path}`], { bytes: true });
    if (inheritedPath) {
      const executionBytes = git(["show", `${EXECUTION_CANDIDATE.commit}:${path}`], { bytes: true });
      assert(bytes.equals(executionBytes),
        "POSTFORMAL_INHERITED_SOURCE_DRIFT", `runner or harness bytes changed: ${path}`);
    }
    return {
      path,
      change_class: correctionPath ? "AUTHORIZED_POSTFORMAL_CORRECTION" : "EXACT_EXECUTION_CANDIDATE_INHERITANCE",
      ...bytesIdentity(bytes),
    };
  });
  const diffBytes = git(["diff", "--binary", "--full-index", CANONICAL_PARENT.commit, candidate.commit], { bytes: true });
  return {
    schema_version: "p1-207-postformal-source-manifest/v1",
    task_id: TASK_ID,
    corrected_candidate: candidate,
    exact_execution_candidate: EXECUTION_CANDIDATE,
    entries,
    tracked_binary_diff: bytesIdentity(diffBytes),
  };
}

export function freezePostformalCandidate() {
  assert(!existsSync(REVIEW_ROOT),
    "POSTFORMAL_REVIEW_ROOT_PREEXISTS", "postformal final review root must be create-once");
  safeRealDirectory(dirname(REVIEW_ROOT), "P1-207 reviews parent");
  createOwnedRoot(REVIEW_ROOT);
  const candidate = candidateIdentity();
  const source = sourceManifest(candidate);
  const authorization = ensureExact(AUTHORIZATION, "Founder postformal authorization");
  const formalEvidence = Object.fromEntries(Object.entries(FORMAL_IDENTITIES)
    .map(([key, value]) => [key, ensureExact(value, `formal ${key}`)]));
  const outputs = Object.fromEntries(Object.entries(POSTFORMAL_OUTPUTS)
    .map(([key, path]) => [key, externalIdentity(path, `postformal ${key}`)]));
  const manifest = {
    schema_version: "p1-207-postformal-corrected-candidate-manifest/v1",
    task_id: TASK_ID,
    status: "FROZEN_EXACT_CANDIDATE",
    corrected_candidate: candidate,
    exact_execution_candidate: EXECUTION_CANDIDATE,
    authorization,
    formal_evidence: formalEvidence,
    postformal_outputs: outputs,
    source,
    formal_matrix_rerun: false,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  };
  const identity = writeJsonCreateOnce(REVIEW_ROOT, "POSTFORMAL_CORRECTED_CANDIDATE_MANIFEST.json", manifest);
  return {
    schema_version: "p1-207-postformal-candidate-freeze-result/v1",
    task_id: TASK_ID,
    status: "PASS",
    corrected_candidate: candidate,
    manifest: { path: join(REVIEW_ROOT, identity.path), sha256: identity.sha256, byte_length: identity.byte_length },
    source_entries: source.entries.length,
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
    assert(process.argv.length === 2, "CLI_USAGE_INVALID", "freeze-postformal-candidate.mjs takes no arguments");
    process.stdout.write(`${canonicalJson(freezePostformalCandidate())}\n`);
  } catch (error) {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-207-postformal-candidate-freeze-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: error.reasonCode ?? error.code ?? error.name,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

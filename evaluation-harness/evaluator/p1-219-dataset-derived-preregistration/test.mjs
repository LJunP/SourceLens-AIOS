#!/usr/bin/env node
import {
  lstatSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildExpectedArtifact,
  DATASET_AUTHORITY,
  REPORT_AUTHORITY,
  TASK_ID,
  verifyArtifactFile,
  verifyArtifactObject,
} from "./lib.mjs";

const ownedRoot = mkdtempSync(join(tmpdir(), "p1-219-matrix-"));
let negativeCases = 0;
let falseAccepts = 0;

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function expectReject(caseId, fn) {
  negativeCases += 1;
  try {
    fn();
    falseAccepts += 1;
    console.error(`FALSE_ACCEPT ${caseId}`);
  } catch {
    // Expected rejection.
  }
}

function writeFixture(name, bytes) {
  const path = join(ownedRoot, name);
  writeFileSync(path, bytes, { flag: "wx", mode: 0o600 });
  return path;
}

try {
  const expected = buildExpectedArtifact();
  const positivePath = writeFixture(
    "P2_CONTEXT_ENGINE_PREREGISTRATION.json",
    Buffer.from(`${JSON.stringify(expected, null, 2)}\n`, "utf8"),
  );
  const positive = verifyArtifactFile(positivePath);
  if (positive.receipt.status !== "PASS" || positive.receipt.sample_members !== expected.sample.length) {
    throw new Error("positive fixture did not prove the complete dataset-derived sample");
  }

  expectReject("SAMPLE_MISSING_MEMBER", () => {
    const value = clone(expected);
    value.sample.pop();
    verifyArtifactObject(value);
  });
  expectReject("SAMPLE_EXTRA_MEMBER", () => {
    const value = clone(expected);
    value.sample.push({ ...value.sample[0], task_id: "SL-P1-REP-999-EXTRA" });
    verifyArtifactObject(value);
  });
  expectReject("SAMPLE_MEMBER_SUBSTITUTION", () => {
    const value = clone(expected);
    value.sample[5].task_id = "SL-P1-REP-006-SUBSTITUTED";
    verifyArtifactObject(value);
  });
  expectReject("SAMPLE_REORDER", () => {
    const value = clone(expected);
    [value.sample[0], value.sample[1]] = [value.sample[1], value.sample[0]];
    verifyArtifactObject(value);
  });
  expectReject("SAMPLE_DUPLICATE", () => {
    const value = clone(expected);
    value.sample[5] = clone(value.sample[4]);
    verifyArtifactObject(value);
  });
  expectReject("CROSS_DATASET_BINDING", () => {
    const value = clone(expected);
    value.dataset_binding.dataset_id = "OTHER-DATASET";
    verifyArtifactObject(value);
  });
  expectReject("DATASET_PATH_DRIFT", () => {
    const value = clone(expected);
    value.dataset_binding.path = "evaluation-harness/datasets/other/dataset-manifest.json";
    verifyArtifactObject(value);
  });
  expectReject("DATASET_BYTE_LENGTH_DRIFT", () => {
    const source = readFileSync(DATASET_AUTHORITY.path);
    const path = writeFixture("dataset-length-drift.json", Buffer.concat([source, Buffer.from(" ")]));
    buildExpectedArtifact({ datasetAuthority: { ...DATASET_AUTHORITY, path } });
  });
  expectReject("DATASET_SHA256_DRIFT", () => {
    const source = Buffer.from(readFileSync(DATASET_AUTHORITY.path));
    source[0] = source[0] === 0x7b ? 0x5b : 0x7b;
    const path = writeFixture("dataset-sha-drift.json", source);
    buildExpectedArtifact({ datasetAuthority: { ...DATASET_AUTHORITY, path } });
  });
  expectReject("DATASET_TYPE_DRIFT", () => {
    const path = join(ownedRoot, "dataset-directory");
    mkdirSync(path);
    buildExpectedArtifact({ datasetAuthority: { ...DATASET_AUTHORITY, path } });
  });
  expectReject("DATASET_SYMLINK", () => {
    const path = join(ownedRoot, "dataset-symlink.json");
    symlinkSync(DATASET_AUTHORITY.path, path);
    buildExpectedArtifact({ datasetAuthority: { ...DATASET_AUTHORITY, path } });
  });
  expectReject("REPORT_PATH_DRIFT", () => {
    const value = clone(expected);
    value.report_binding.path = "/tmp/other-report.json";
    verifyArtifactObject(value);
  });
  expectReject("REPORT_BYTE_LENGTH_DRIFT", () => {
    const source = readFileSync(REPORT_AUTHORITY.path);
    const path = writeFixture("report-length-drift.json", Buffer.concat([source, Buffer.from(" ")]));
    buildExpectedArtifact({ reportAuthority: { ...REPORT_AUTHORITY, path } });
  });
  expectReject("REPORT_SHA256_DRIFT", () => {
    const source = Buffer.from(readFileSync(REPORT_AUTHORITY.path));
    source[0] = source[0] === 0x7b ? 0x5b : 0x7b;
    const path = writeFixture("report-sha-drift.json", source);
    buildExpectedArtifact({ reportAuthority: { ...REPORT_AUTHORITY, path } });
  });
  expectReject("REPORT_TYPE_DRIFT", () => {
    const path = join(ownedRoot, "report-directory");
    mkdirSync(path);
    buildExpectedArtifact({ reportAuthority: { ...REPORT_AUTHORITY, path } });
  });
  expectReject("REPORT_SYMLINK", () => {
    const path = join(ownedRoot, "report-symlink.json");
    symlinkSync(REPORT_AUTHORITY.path, path);
    buildExpectedArtifact({ reportAuthority: { ...REPORT_AUTHORITY, path } });
  });
  expectReject("REPORT_ACCEPTANCE_COMMIT_DRIFT", () => {
    const value = clone(expected);
    value.report_binding.acceptance_commit = "0".repeat(40);
    verifyArtifactObject(value);
  });
  expectReject("REPORT_ACCEPTANCE_TREE_DRIFT", () => {
    const value = clone(expected);
    value.report_binding.acceptance_tree = "0".repeat(40);
    verifyArtifactObject(value);
  });
  expectReject("SELF_CONSISTENT_ARTIFACT_EXTERNAL_DATASET_MISMATCH", () => {
    const value = clone(expected);
    value.sample[5].task_id = "SL-P1-REP-006-SELF-CONSISTENT-BUT-WRONG";
    value.dataset_binding.sha256 = "f".repeat(64);
    value.sample_derivation.authority = "ARTIFACT_SELF_REPORT";
    verifyArtifactObject(value);
  });
  expectReject("MISSING_MANDATORY_PREREGISTRATION_FIELD", () => {
    const value = clone(expected);
    delete value.preregistration.uncertainty_method;
    verifyArtifactObject(value);
  });
  expectReject("EXTRA_TOP_LEVEL_PREREGISTRATION_FIELD", () => {
    const value = clone(expected);
    value.unreviewed_extra = true;
    verifyArtifactObject(value);
  });
  expectReject("P2_EXECUTION_OR_HOLD_RELEASE_CLAIM", () => {
    const value = clone(expected);
    value.p2_state.status = "ACTIVE";
    value.p2_state.p2_experiment_executed = true;
    value.p2_state.p2_entry_authorized = true;
    verifyArtifactObject(value);
  });

  if (negativeCases !== 22 || falseAccepts !== 0) {
    throw new Error(`matrix mismatch negative_cases=${negativeCases} false_accepts=${falseAccepts}`);
  }
  process.stdout.write(`${JSON.stringify({
    schema_version: "p1-219-prefreeze-matrix-receipt/v1",
    task_id: TASK_ID,
    status: "PASS",
    positive_cases: 1,
    sample_members: expected.sample.length,
    negative_cases: negativeCases,
    false_accepts: falseAccepts,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: expected.external_effects,
    disposable_root_cleaned: true,
  })}\n`);
} finally {
  rmSync(ownedRoot, { recursive: true, force: true });
  if (lstatSync(tmpdir()).isSymbolicLink()) {
    throw new Error("system temporary root unexpectedly became a symlink");
  }
}

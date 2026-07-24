#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

import { verifyQualityFixtures } from "./quality-oracle.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const TARGET = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-097-minimal-documented/controlled-target.mjs",
);

const result = verifyQualityFixtures();
if (result.status !== "PASS" || result.negative_cases !== 40 || result.positive_runs !== 6) {
  throw new Error("static Quality fixture verification did not PASS");
}

const tempRoot = mkdtempSync(join(tmpdir(), "p1-097-quality-self-test-"));
const sentinel = join(tempRoot, "sentinels", "target-executed");
if (existsSync(sentinel)) throw new Error("sentinel unexpectedly preexisted");

const invalid = spawnSync(process.execPath, [TARGET, "--invalid", sentinel], {
  cwd: REPOSITORY_ROOT,
  encoding: "utf8",
  timeout: 5000,
});
if (invalid.status !== 64 || existsSync(sentinel)) {
  throw new Error("controlled target invalid-argv pre-execution sentinel contract failed");
}

const valid = spawnSync(process.execPath, [TARGET, "--sentinel", sentinel], {
  cwd: REPOSITORY_ROOT,
  encoding: "utf8",
  timeout: 5000,
});
if (
  valid.status !== 0 ||
  !existsSync(sentinel) ||
  readFileSync(sentinel, "utf8") !== "TARGET_EXECUTED\n"
) {
  throw new Error("controlled target execution sentinel contract failed");
}

const commitTree = execFileSync(
  "/usr/bin/git",
  ["-C", REPOSITORY_ROOT, "rev-parse", "09cf8dd6a1bcee138b949d117804d652000eb7cc:analyzer-rust"],
  { encoding: "utf8" },
).trim();
if (commitTree !== result.b2_analyzer_tree) {
  throw new Error("accepted P0 analyzer binding self-test failed");
}

process.stdout.write(`${JSON.stringify({
  schema_version: "p1-097-quality-self-test/v1",
  status: "PASS",
  positive_runs: result.positive_runs,
  negative_cases: result.negative_cases,
  pre_execution_negative_cases: result.pre_execution_negative_cases,
  post_execution_negative_cases: result.post_execution_negative_cases,
  interface_counts: result.interface_counts,
  controlled_target_invalid_argv_prevented_execution: true,
  controlled_target_valid_argv_created_sentinel: true,
  accepted_p0_analyzer_tree_verified: true,
  fixture_manifest_sha256: result.fixture_manifest_sha256,
})}\n`);


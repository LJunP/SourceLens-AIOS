#!/usr/bin/env node
import { execFileSync, spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { canonicalBytes, identityProjection, readJson, sha256Bytes } from "./snapshot.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(here, "../..");
const fixtureRoot = join(repositoryRoot, "evaluation-harness/fixtures/environment-snapshot");
const schemaPath = join(repositoryRoot, "docs/aios/schemas/environment-snapshot.schema.json");
const cliPath = join(here, "cli.mjs");
const declarationsPath = join(fixtureRoot, "declarations.json");
const runtimeManifestPath = join(fixtureRoot, "target-runtime-oci-manifest.json");
const caseMatrix = readJson(join(fixtureRoot, "CASE_MATRIX.json"));
const declarations = readJson(declarationsPath);
const scratchParent = join(here, ".self-test-tmp");
rmSync(scratchParent, { recursive: true, force: true });
mkdirSync(scratchParent, { recursive: true });
const scratch = mkdtempSync(join(scratchParent, "run-"));

function git(root, args, env = {}) {
  return execFileSync("git", ["-C", root, ...args], {
    encoding: "utf8",
    env: { ...process.env, LC_ALL: "C", LANG: "C", ...env },
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function materialize(name) {
  const root = join(scratch, name);
  mkdirSync(root, { recursive: true });
  cpSync(join(fixtureRoot, "source-template"), root, { recursive: true });
  git(root, ["init", "--quiet"]);
  git(root, ["add", "README.md", "package-lock.json"]);
  const materialization = declarations.materialization;
  git(root, ["commit", "--quiet", "-m", materialization.commit_message], {
    GIT_AUTHOR_NAME: materialization.author_name,
    GIT_AUTHOR_EMAIL: materialization.author_email,
    GIT_COMMITTER_NAME: materialization.committer_name,
    GIT_COMMITTER_EMAIL: materialization.committer_email,
    GIT_AUTHOR_DATE: materialization.author_date,
    GIT_COMMITTER_DATE: materialization.committer_date,
  });
  if (git(root, ["rev-parse", "HEAD"]) !== materialization.expected_commit ||
      git(root, ["rev-parse", "HEAD^{tree}"]) !== materialization.expected_tree) {
    throw new Error("frozen Git materialization identity mismatch");
  }
  return root;
}

function invoke(command, sourceRoot, extras = {}, declarationsOverride = declarationsPath) {
  const snapshot = extras.snapshot ?? join(scratch, `${extras.id ?? command}-snapshot.json`);
  const args = [cliPath, command,
    "--source-root", sourceRoot,
    "--declarations", declarationsOverride,
    "--runtime-manifest", runtimeManifestPath,
    "--schema", schemaPath,
    command === "capture" ? "--output" : "--snapshot", snapshot,
  ];
  const run = spawnSync(process.execPath, args, { encoding: "utf8", cwd: repositoryRoot });
  let parsed;
  try { parsed = JSON.parse(run.stdout); } catch { parsed = null; }
  return { ...run, parsed, snapshot, argv: [process.execPath, ...args] };
}

function mutateJson(source, target, mutate) {
  const value = readJson(source);
  mutate(value);
  writeFileSync(target, canonicalBytes(value));
  return target;
}

const results = [];
function check(caseId, run, extra = true) {
  const spec = caseMatrix.cases.find((entry) => entry.id === caseId);
  const pass = run.status === spec.expected_exit_status && run.stderr === "" &&
    run.parsed?.verdict === spec.expected_verdict && run.parsed?.reason_code === spec.expected_reason_code && extra;
  results.push({ case_id: caseId, pass, expected: spec, actual: { status: run.status, stdout: run.stdout, stderr: run.stderr } });
  if (!pass) throw new Error(`${caseId} failed: ${JSON.stringify(results.at(-1))}`);
}

try {
  const sourceA = materialize("source-a");
  const sourceB = materialize("source-b");
  const q01 = invoke("capture", sourceA, { id: "q01" });
  check("Q01_CLEAN_CAPTURE_PASS", q01);

  const q02 = invoke("verify", sourceA, { id: "q02", snapshot: q01.snapshot });
  check("Q02_EXACT_VERIFY_PASS", q02);

  const q03a = invoke("capture", sourceA, { id: "q03a" });
  const q03b = invoke("capture", sourceB, { id: "q03b" });
  const snapA = readJson(q03a.snapshot);
  const snapB = readJson(q03b.snapshot);
  const replayEqual = sha256Bytes(canonicalBytes(identityProjection(snapA))) === sha256Bytes(canonicalBytes(identityProjection(snapB))) &&
    snapA.snapshot_id === snapB.snapshot_id && snapA.source.base_commit === snapB.source.base_commit && snapA.source.tree_hash === snapB.source.tree_hash;
  check("Q03_TWO_FRESH_MATERIALIZATIONS_REPLAY_PASS", q03b, q03a.status === 0 && replayEqual);

  const dirty = materialize("dirty");
  writeFileSync(join(dirty, "untracked.txt"), "dirty\n");
  check("Q04_DIRTY_SOURCE_SOURCE_NOT_CLEAN", invoke("capture", dirty, { id: "q04" }));

  const q05Snapshot = mutateJson(q01.snapshot, join(scratch, "q05.json"), (value) => { value.source.base_commit = "0".repeat(40); });
  check("Q05_COMMIT_OR_TREE_DRIFT_SOURCE_IDENTITY_MISMATCH", invoke("verify", sourceA, { snapshot: q05Snapshot }));

  const q06Snapshot = mutateJson(q01.snapshot, join(scratch, "q06.json"), (value) => { value.runtime.container_image_digest = `sha256:${"0".repeat(64)}`; });
  check("Q06_TARGET_RUNTIME_DRIFT_RUNTIME_IDENTITY_MISMATCH", invoke("verify", sourceA, { snapshot: q06Snapshot }));

  const q07Snapshot = mutateJson(q01.snapshot, join(scratch, "q07.json"), (value) => { value.dependencies.lockfiles[0].sha256 = "0".repeat(64); });
  check("Q07_LOCKFILE_BYTE_DRIFT_DEPENDENCY_IDENTITY_MISMATCH", invoke("verify", sourceA, { snapshot: q07Snapshot }));

  const q08Snapshot = mutateJson(q01.snapshot, join(scratch, "q08.json"), (value) => { value.network.policy = "declared_allowlist"; });
  check("Q08_NETWORK_PROVIDER_OR_SECRET_POLICY_DRIFT_POLICY_BOUNDARY_MISMATCH", invoke("verify", sourceA, { snapshot: q08Snapshot }));

  const q09Link = join(scratch, "source-link");
  symlinkSync(sourceA, q09Link);
  check("Q09_SOURCE_ROOT_SYMLINK_SYMLINK_FORBIDDEN", invoke("capture", q09Link, { id: "q09" }));

  const q10 = materialize("lock-symlink");
  rmSync(join(q10, "package-lock.json"));
  symlinkSync("README.md", join(q10, "package-lock.json"));
  check("Q10_LOCKFILE_SYMLINK_SYMLINK_FORBIDDEN", invoke("capture", q10, { id: "q10" }));

  const q11Declarations = mutateJson(declarationsPath, join(scratch, "q11-declarations.json"), (value) => { value.dependencies.lockfiles[0].path = "../outside-lock.json"; });
  check("Q11_SOURCE_OR_LOCKFILE_ESCAPE_PATH_CONTAINMENT_VIOLATION", invoke("capture", sourceA, { id: "q11" }, q11Declarations));

  const q12 = materialize("undeclared-lockfile");
  writeFileSync(join(q12, "npm-shrinkwrap.json"), "{}\n");
  git(q12, ["add", "npm-shrinkwrap.json"]);
  git(q12, ["commit", "--quiet", "-m", "test: add undeclared lockfile"], {
    GIT_AUTHOR_NAME: "SourceLens Quality Fixture",
    GIT_AUTHOR_EMAIL: "quality-fixture@sourcelens.invalid",
    GIT_COMMITTER_NAME: "SourceLens Quality Fixture",
    GIT_COMMITTER_EMAIL: "quality-fixture@sourcelens.invalid",
    GIT_AUTHOR_DATE: "2026-07-16T00:01:00Z",
    GIT_COMMITTER_DATE: "2026-07-16T00:01:00Z",
  });
  check("Q12_UNDECLARED_LOCKFILE_UNDECLARED_LOCKFILE", invoke("capture", q12, { id: "q12" }));

  const q13Declarations = mutateJson(declarationsPath, join(scratch, "q13-declarations.json"), (value) => { delete value.target_runtime.architecture; });
  check("Q13_MALFORMED_DECLARATION_MALFORMED_INPUT", invoke("capture", sourceA, { id: "q13" }, q13Declarations));

  process.stdout.write(`${JSON.stringify({ status: "PASS", passed: results.length, total: caseMatrix.total_cases, results })}\n`);
} finally {
  rmSync(scratchParent, { recursive: true, force: true });
}

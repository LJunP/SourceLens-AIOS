#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="/usr/local/bin/node"
TEST_DRIVER="$(mktemp /private/tmp/sourcelens-p1-069-driver.XXXXXX.mjs)"

cleanup() {
  if [[ -f "${TEST_DRIVER}" && "${TEST_DRIVER}" == /private/tmp/sourcelens-p1-069-driver.*.mjs ]]; then
    rm -f -- "${TEST_DRIVER}"
  fi
}
trap cleanup EXIT

cat >"${TEST_DRIVER}" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const repo = process.argv[2];
const node = "/usr/local/bin/node";
const harnessRoot = path.join(repo, "evaluation-harness");
const runner = path.join(harnessRoot, "harness/blind-admission-v1/run.mjs");
const recorder = path.join(harnessRoot, "recording/blind-admission-v1/recorder.mjs");
const validator = path.join(harnessRoot, "validators/blind-admission-v1/validator.mjs");
const oracle = path.join(harnessRoot, "evaluator/blind-admission-v1/public-conformance-oracle.mjs");
const task = path.join(harnessRoot, "fixtures/blind-admission-v1/visible-task-card.json");
const source = path.join(harnessRoot, "fixtures/blind-admission-v1/visible-source.json");
const expected = path.join(harnessRoot, "fixtures/blind-admission-v1/visible-expected.json");
const runtime = path.join(harnessRoot, "fixtures/blind-admission-v1/runtime-profile.json");
const contract = path.join(repo, "docs/aios/tasks/P1-069_CLEAN_ROOM_OFFLINE_BLIND_ADMISSION_PARAMETERIZED_HARNESS_VERTICAL_SLICE.yaml");
const env = { LANG: "C", LC_ALL: "C", PATH: "/usr/bin:/bin:/usr/sbin:/sbin", TZ: "UTC" };
const ownedRoots = [];

const fail = (message) => { throw new Error(message); };
const sha = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const normalize = (value) => Array.isArray(value) ? value.map(normalize) : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, normalize(value[key])])) : value;
const shaJson = (value) => sha(Buffer.from(JSON.stringify(normalize(value)), "utf8"));
const identity = (file) => { const bytes = fs.readFileSync(file); return { sha256: sha(bytes), byte_length: bytes.length }; };
const parseReason = (stderr) => { try { return JSON.parse(stderr.toString("utf8")).reason; } catch { return "INVALID_FAILURE"; } };
const freshRoot = (label) => {
  const root = fs.mkdtempSync(`/private/tmp/sourcelens-p1-069-${label}-`);
  fs.chmodSync(root, 0o700);
  ownedRoots.push(root);
  return root;
};
const removeOwned = (target) => {
  if (!target.startsWith("/private/tmp/sourcelens-p1-069-")) fail("CLEANUP_SCOPE_INVALID");
  if (!fs.existsSync(target) && !fs.lstatSync(path.dirname(target)).isDirectory()) return;
  if (!fs.existsSync(target) && !fs.lstatSync(target).isSymbolicLink()) return;
  const stat = fs.lstatSync(target);
  if (stat.isSymbolicLink() || stat.isFile()) { fs.unlinkSync(target); return; }
  if (!stat.isDirectory()) fail("CLEANUP_TYPE_INVALID");
  for (const entry of fs.readdirSync(target)) removeOwned(path.join(target, entry));
  fs.rmdirSync(target);
};

const ids = {
  task: identity(task), source: identity(source), runtime: identity(runtime),
  runner: identity(runner), recorder: identity(recorder), validator: identity(validator), contract: identity(contract)
};

const buildArgs = (ownedRoot, overrides = {}) => {
  const values = {
    "task-card": task, "task-card-sha256": ids.task.sha256, "task-card-byte-length": String(ids.task.byte_length),
    source, "source-sha256": ids.source.sha256, "source-byte-length": String(ids.source.byte_length),
    "runtime-profile": runtime, "runtime-profile-sha256": ids.runtime.sha256, "runtime-profile-byte-length": String(ids.runtime.byte_length),
    "owned-root": ownedRoot, "source-root": path.join(ownedRoot, "source"), "evidence-root": path.join(ownedRoot, "evidence"),
    "canonical-root": repo, "case-id": "canonical-public-regression",
    "contract-sha256": ids.contract.sha256, "contract-byte-length": String(ids.contract.byte_length),
    "authority-sha256": "11".repeat(32), "authority-byte-length": "1",
    "quality-freeze-sha256": "22".repeat(32), "quality-freeze-byte-length": "1",
    "commitment-sha256": "33".repeat(32), "commitment-byte-length": "1",
    "candidate-commit": "44".repeat(20), "candidate-tree": "55".repeat(20),
    "candidate-module-sha256": ids.runner.sha256, "candidate-module-byte-length": String(ids.runner.byte_length),
    "recorder-module-sha256": ids.recorder.sha256, "recorder-module-byte-length": String(ids.recorder.byte_length),
    "validator-module-sha256": ids.validator.sha256, "validator-module-byte-length": String(ids.validator.byte_length),
    "logical-cwd": repo, "environment-sha256": shaJson(env), "timeout-ms": "5000",
    ...overrides
  };
  const order = [
    "task-card","task-card-sha256","task-card-byte-length","source","source-sha256","source-byte-length",
    "runtime-profile","runtime-profile-sha256","runtime-profile-byte-length","owned-root","source-root","evidence-root",
    "canonical-root","case-id","contract-sha256","contract-byte-length","authority-sha256","authority-byte-length",
    "quality-freeze-sha256","quality-freeze-byte-length","commitment-sha256","commitment-byte-length","candidate-commit","candidate-tree",
    "candidate-module-sha256","candidate-module-byte-length","recorder-module-sha256","recorder-module-byte-length",
    "validator-module-sha256","validator-module-byte-length","logical-cwd","environment-sha256","timeout-ms"
  ];
  return order.flatMap((key) => [`--${key}`, values[key]]);
};

const spawnCandidate = (ownedRoot, overrides = {}, launcher = [node]) => {
  const args = buildArgs(ownedRoot, overrides);
  const executable = launcher[0];
  const prefix = launcher.slice(1);
  const result = spawnSync(executable, [...prefix, runner, ...args], { cwd: repo, env, encoding: null, timeout: 6000, maxBuffer: 65536, shell: false });
  return { args, result };
};

const writeObservation = (file, ownedRoot, args, run) => {
  const evidencePath = path.join(ownedRoot, "evidence/evidence.json");
  const evidenceId = identity(evidencePath);
  const taskJson = JSON.parse(fs.readFileSync(task, "utf8"));
  const runtimeJson = JSON.parse(fs.readFileSync(runtime, "utf8"));
  const observation = {
    schema_version: "blind-admission-quality-observation/v1",
    candidate_evidence: evidenceId,
    identities: { task_card_sha256: ids.task.sha256, source_sha256: ids.source.sha256, runtime_profile_sha256: ids.runtime.sha256, executing_module_sha256: ids.runner.sha256 },
    task_id: taskJson.task_id,
    process: {
      actual_arch: process.arch, platform: process.platform, executable_path: node, executable_realpath: fs.realpathSync(node),
      executable_sha256: identity(node).sha256, executable_version: process.version, exit_code: run.status,
      stdout_sha256: sha(run.stdout), stderr_sha256: sha(run.stderr)
    },
    command: { ordered_argv_sha256: shaJson([node, runner, ...args]), logical_cwd: repo, environment_sha256: shaJson(env), timeout_ms: 5000 },
    rollback: { source_root_initial_state: "ABSENT", source_root_final_state: fs.existsSync(path.join(ownedRoot, "source")) ? "PRESENT" : "ABSENT", path_set_before: [], path_set_after: [], clean_state_before: true, clean_state_after: !fs.existsSync(path.join(ownedRoot, "source")), exact: !fs.existsSync(path.join(ownedRoot, "source")) },
    external_effects: { network: false, provider: false, secret: false, remote: false, production: false, public: false }
  };
  fs.writeFileSync(file, `${JSON.stringify(observation, null, 2)}\n`, { flag: "wx", mode: 0o400 });
  return evidencePath;
};

try {
  for (const file of [runner, recorder, validator, oracle]) {
    const syntax = spawnSync(node, ["--check", file], { cwd: repo, env, encoding: "utf8", shell: false });
    if (syntax.status !== 0) fail(`SYNTAX_NON_PASS ${file}`);
  }

  const positiveRoot = freshRoot("positive");
  const metaRoot = freshRoot("meta");
  const positive = spawnCandidate(positiveRoot);
  if (positive.result.error || positive.result.status !== 0) fail(`POSITIVE_NON_PASS ${positive.result.stderr}`);
  const observation = path.join(metaRoot, "observation.json");
  const evidencePath = writeObservation(observation, positiveRoot, positive.args, positive.result);
  const oracleRun = spawnSync(node, [oracle, "--evidence", evidencePath, "--expected", expected, "--observation", observation, "--task-card", task, "--source", source, "--runtime-profile", runtime, "--candidate-module", runner], { cwd: repo, env, encoding: "utf8", shell: false });
  if (oracleRun.status !== 0 || JSON.parse(oracleRun.stdout).verdict !== "PASS") fail(`PUBLIC_ORACLE_NON_PASS ${oracleRun.stderr}`);

  const identityRoot = freshRoot("identity");
  const identityFailure = spawnCandidate(identityRoot, { "task-card-sha256": "00".repeat(32) }).result;
  if (identityFailure.status === 0 || parseReason(identityFailure.stderr) !== "TASK_CARD_IDENTITY_MISMATCH" || fs.readdirSync(identityRoot).length !== 0) fail("TASK_CARD_SUBSTITUTION_FALSE_ACCEPT");

  const outputRoot = freshRoot("preexisting");
  fs.mkdirSync(path.join(outputRoot, "evidence"), { mode: 0o700 });
  const outputFailure = spawnCandidate(outputRoot).result;
  if (outputFailure.status === 0 || parseReason(outputFailure.stderr) !== "OUTPUT_ALREADY_EXISTS") fail("PREEXISTING_OUTPUT_FALSE_ACCEPT");

  const symlinkTarget = freshRoot("symlink-target");
  const symlinkMeta = freshRoot("symlink-meta");
  const symlinkRoot = path.join(symlinkMeta, "owned-link");
  fs.symlinkSync(symlinkTarget, symlinkRoot);
  const symlinkFailure = spawnCandidate(symlinkRoot).result;
  if (symlinkFailure.status === 0 || parseReason(symlinkFailure.stderr) !== "SYMLINK_COMPONENT_FORBIDDEN") fail("SYMLINK_FALSE_ACCEPT");

  const hardlinkMeta = freshRoot("hardlink-meta");
  const hardlinkTask = path.join(hardlinkMeta, "task.json");
  const hardlinkTwin = path.join(hardlinkMeta, "task-twin.json");
  fs.copyFileSync(task, hardlinkTask, fs.constants.COPYFILE_EXCL);
  fs.linkSync(hardlinkTask, hardlinkTwin);
  const hardlinkRoot = freshRoot("hardlink-run");
  const hardlinkFailure = spawnCandidate(hardlinkRoot, { "task-card": hardlinkTask }).result;
  if (hardlinkFailure.status === 0 || parseReason(hardlinkFailure.stderr) !== "NON_UNIQUE_INPUT_LINK_COUNT") fail("HARDLINK_FALSE_ACCEPT");

  const { validateSource } = await import(pathToFileURL(validator).href);
  for (const paths of [["a","a-b","a/b"],["A","a-b","a/B"]]) {
    let rejected = false;
    try { validateSource({ schema_version: "blind-admission-source/v1", files: paths.map((filePath) => ({ path: filePath, content: "x" })) }); }
    catch (error) { rejected = error.reason === "SOURCE_MANIFEST_DRIFT"; }
    if (!rejected) fail("SOURCE_PREFIX_FALSE_ACCEPT");
  }

  const effectMeta = freshRoot("effect-meta");
  const effectTask = path.join(effectMeta, "task.json");
  const effectJson = JSON.parse(fs.readFileSync(task, "utf8"));
  effectJson.execution_policy.external_effects.network = true;
  fs.writeFileSync(effectTask, `${JSON.stringify(effectJson)}\n`, { flag: "wx", mode: 0o400 });
  const effectId = identity(effectTask);
  const effectRoot = freshRoot("effect-run");
  const effectFailure = spawnCandidate(effectRoot, { "task-card": effectTask, "task-card-sha256": effectId.sha256, "task-card-byte-length": String(effectId.byte_length) }).result;
  if (effectFailure.status === 0 || parseReason(effectFailure.stderr) !== "EXTERNAL_EFFECT_FORBIDDEN") fail("EXTERNAL_EFFECT_FALSE_ACCEPT");

  const alternateRoot = freshRoot("alternate-arch");
  const alternateFailure = spawnCandidate(alternateRoot, {}, ["/usr/bin/arch", "-x86_64", node]).result;
  if (alternateFailure.status === 0 || parseReason(alternateFailure.stderr) !== "ACTUAL_ARCHITECTURE_MISMATCH" || fs.readdirSync(alternateRoot).length !== 0) fail("ALTERNATE_ARCH_FALSE_ACCEPT");

  process.stdout.write("P1_069_BLIND_ADMISSION_OK positive=1 public_oracle=PASS negatives=8 rollback=PASS external_effects=FALSE\n");
} finally {
  for (const root of [...ownedRoots].sort((left, right) => right.length - left.length)) {
    if (fs.existsSync(root) || fs.lstatSync(path.dirname(root)).isDirectory()) {
      try { if (fs.existsSync(root) || fs.lstatSync(root).isSymbolicLink()) removeOwned(root); } catch {}
    }
  }
}
NODE

"${NODE_BIN}" "${TEST_DRIVER}" "${ROOT_DIR}"

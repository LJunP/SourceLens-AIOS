import { createHash } from "node:crypto";
import {
  closeSync,
  constants,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
} from "node:fs";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  COMPILER_VERSION,
  compileFiniteTypedPatchIr,
} from "../../harness/finite-typed-patch-ir-v1/compiler.mjs";
import {
  QUALITY_ORACLE_VERSION,
  evaluateByteClosureCompiler,
  evaluateCompilerObservation,
} from "../finite-typed-patch-ir-v1/quality-oracle.mjs";
import { validate as validateSchema } from "../schema-validator.mjs";

export const QUALITY_EVALUATOR_VERSION = "P1-063-OFFLINE-B0-QUALITY-EVALUATOR/1";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const FIXTURE_ROOT = "evaluation-harness/fixtures/p1-063-offline-b0-finite-ir-v1";
const RUN_RECORD_SCHEMA = "docs/aios/schemas/run-record.schema.json";
const EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
const TASK_ID = "AIOS-P1-063_CLEAN_ROOM_OFFLINE_RESULT_ADMISSION_AND_B0_ADAPTER";
const CONTROL_ID = "SL-P1-REP-001-RANGE-NORMALIZATION";
const HASH_RE = /^[0-9a-f]{64}$/u;
const O_NOFOLLOW = constants.O_NOFOLLOW ?? 0;

class QualityError extends Error {
  constructor(reasonCode, message) {
    super(message);
    this.name = "QualityError";
    this.reasonCode = reasonCode;
  }
}

const fail = (reasonCode, message) => {
  throw new QualityError(reasonCode, message);
};
const assert = (condition, reasonCode, message) => {
  if (!condition) fail(reasonCode, message);
};
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function sortedValue(value) {
  if (Array.isArray(value)) return value.map(sortedValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortedValue(value[key])]));
  }
  return value;
}

export function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(sortedValue(value))}\n`, "utf8");
}

function exactKeys(value, expected, reasonCode) {
  assert(value && typeof value === "object" && !Array.isArray(value), reasonCode, "expected object");
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  assert(JSON.stringify(actual) === JSON.stringify(wanted), reasonCode, `key set drift: ${actual.join(",")}`);
}

function repoPath(relativePath) {
  assert(typeof relativePath === "string" && relativePath.length > 0, "PATH_REJECTED", "empty path");
  assert(!isAbsolute(relativePath), "PATH_REJECTED", "repository path must be relative");
  const absolute = resolve(ROOT, relativePath);
  const rel = relative(ROOT, absolute);
  assert(rel !== "" && !rel.startsWith("..") && !isAbsolute(rel), "PATH_REJECTED", "repository path escape");
  return absolute;
}

function secureRead(absolutePath, reasonPrefix = "FILE") {
  assert(isAbsolute(absolutePath), `${reasonPrefix}_PATH_REJECTED`, "path must be absolute");
  let before;
  try {
    before = lstatSync(absolutePath);
  } catch (error) {
    fail(`${reasonPrefix}_MISSING`, error.message);
  }
  assert(!before.isSymbolicLink(), `${reasonPrefix}_SYMLINK_REJECTED`, "symlink rejected");
  assert(before.isFile(), `${reasonPrefix}_TYPE_REJECTED`, "regular file required");
  assert(before.nlink === 1, `${reasonPrefix}_NLINK_REJECTED`, "nlink must equal one");
  let fd;
  try {
    fd = openSync(absolutePath, constants.O_RDONLY | O_NOFOLLOW);
    const opened = fstatSync(fd);
    assert(opened.isFile(), `${reasonPrefix}_TYPE_REJECTED`, "opened descriptor is not regular");
    assert(opened.nlink === 1, `${reasonPrefix}_NLINK_REJECTED`, "opened nlink drift");
    assert(opened.dev === before.dev && opened.ino === before.ino, `${reasonPrefix}_IDENTITY_DRIFT_REJECTED`, "descriptor identity mismatch");
    const bytes = readFileSync(fd);
    const after = lstatSync(absolutePath);
    assert(!after.isSymbolicLink() && after.isFile(), `${reasonPrefix}_IDENTITY_DRIFT_REJECTED`, "path type drift");
    assert(after.dev === opened.dev && after.ino === opened.ino, `${reasonPrefix}_IDENTITY_DRIFT_REJECTED`, "path identity drift");
    assert(after.size === bytes.length && opened.size === bytes.length, `${reasonPrefix}_IDENTITY_DRIFT_REJECTED`, "size drift");
    return Object.freeze({ bytes, byte_length: bytes.length, sha256: sha256(bytes), dev: opened.dev, ino: opened.ino });
  } catch (error) {
    if (error instanceof QualityError) throw error;
    fail(`${reasonPrefix}_READ_REJECTED`, error.message);
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function readJsonAbsolute(absolutePath, reasonPrefix = "JSON") {
  const identity = secureRead(absolutePath, reasonPrefix);
  try {
    return Object.freeze({ ...identity, value: JSON.parse(identity.bytes.toString("utf8")) });
  } catch (error) {
    fail(`${reasonPrefix}_PARSE_REJECTED`, error.message);
  }
}

function readRepoJson(relativePath, reasonPrefix = "JSON") {
  return readJsonAbsolute(repoPath(relativePath), reasonPrefix);
}

function verifyIdentity(identity, expected, reasonCode = "IDENTITY_MISMATCH") {
  assert(identity.byte_length === expected.byte_length, reasonCode, "byte length mismatch");
  assert(identity.sha256 === expected.sha256, reasonCode, "sha256 mismatch");
}

function loadQualityAssets() {
  const taskCard = readRepoJson(`${FIXTURE_ROOT}/task-card.json`, "TASK_CARD");
  const assets = {};
  for (const [name, path] of Object.entries(taskCard.value.quality_assets)) {
    if (name === "evaluator") continue;
    assets[name] = readRepoJson(path, `QUALITY_${name.toUpperCase()}`);
  }
  return { taskCard, assets };
}

function validateSchemaClosure(schema, expectedTopKeys, label) {
  assert(schema.type === "object" && schema.additionalProperties === false, "SCHEMA_NOT_CLOSED", `${label} top level is open`);
  assert(Array.isArray(schema.required), "SCHEMA_REJECTED", `${label} required missing`);
  assert(JSON.stringify([...schema.required].sort()) === JSON.stringify([...expectedTopKeys].sort()), "SCHEMA_REJECTED", `${label} required drift`);
  assert(Object.keys(schema.properties ?? {}).every((key) => expectedTopKeys.includes(key)), "SCHEMA_REJECTED", `${label} properties drift`);
}

const SUBMISSION_KEYS = [
  "schema_version", "record_type", "result_id", "adapter_id", "execution_mode", "task_id",
  "dataset_version", "base_commit", "base_tree", "target_id", "proposal",
];
const PROPOSAL_KEYS = ["program_id", "path", "byte_length", "sha256"];

export function validateOfflineSubmission(submission, frozen) {
  exactKeys(submission, SUBMISSION_KEYS, "SUBMISSION_UNKNOWN_MEMBER_REJECTED");
  exactKeys(submission.proposal, PROPOSAL_KEYS, "PROPOSAL_UNKNOWN_MEMBER_REJECTED");
  assert(submission.schema_version === 1 && submission.record_type === "sourcelens_aios_p1_063_offline_b0_finite_ir_result", "SUBMISSION_TYPE_REJECTED", "submission type drift");
  assert(submission.result_id === frozen.result_id && submission.adapter_id === "B0" && submission.execution_mode === "OFFLINE_FROZEN_SUBMISSION", "SUBMISSION_TYPE_REJECTED", "submission identity drift");
  assert(submission.task_id === frozen.task_id && submission.dataset_version === frozen.dataset_version, "TASK_BINDING_REJECTED", "task binding drift");
  assert(submission.base_commit === frozen.base_commit, "BASE_COMMIT_MISMATCH_REJECTED", "base commit drift");
  assert(submission.base_tree === frozen.base_tree, "BASE_TREE_MISMATCH_REJECTED", "base tree drift");
  assert(submission.target_id === frozen.target_id, "TARGET_BINDING_REJECTED", "target drift");
  assert(submission.proposal.program_id === frozen.proposal.program_id, "PROGRAM_BINDING_REJECTED", "program id drift");
  assert(submission.proposal.path === frozen.proposal.path && !isAbsolute(submission.proposal.path) && !submission.proposal.path.split("/").includes(".."), "PROPOSAL_PATH_REJECTED", "proposal path drift");
  assert(submission.proposal.byte_length === frozen.proposal.byte_length, "PROPOSAL_LENGTH_MISMATCH_REJECTED", "proposal length drift");
  assert(submission.proposal.sha256 === frozen.proposal.sha256, "PROPOSAL_HASH_MISMATCH_REJECTED", "proposal hash drift");
  return true;
}

function verifyAcceptedInputs(taskCard) {
  for (const expected of Object.values(taskCard.accepted_inputs)) {
    const identity = secureRead(repoPath(expected.path), "ACCEPTED_INPUT");
    verifyIdentity(identity, expected, "ACCEPTED_INPUT_IDENTITY_MISMATCH");
  }
  for (const key of ["compiler", "independent_oracle", "success_program"]) {
    const expected = taskCard.accepted_substrate[key];
    const identity = secureRead(repoPath(expected.path), "ACCEPTED_SUBSTRATE");
    verifyIdentity(identity, expected, "ACCEPTED_SUBSTRATE_IDENTITY_MISMATCH");
  }
  assert(COMPILER_VERSION === taskCard.accepted_substrate.compiler.version, "COMPILER_VERSION_MISMATCH", "compiler version drift");
  assert(QUALITY_ORACLE_VERSION === taskCard.accepted_substrate.independent_oracle.version, "QUALITY_ORACLE_VERSION_MISMATCH", "oracle version drift");
}

function verifyProgramTable(expectedResults) {
  let assertions = 0;
  for (const expected of expectedResults.closed_ir.programs) {
    const path = `evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/${expected.program_id.toLowerCase()}.json`;
    const identity = secureRead(repoPath(path), "FINITE_IR_PROGRAM");
    verifyIdentity(identity, expected, "FINITE_IR_IDENTITY_MISMATCH");
    const compiled = compileFiniteTypedPatchIr(Buffer.from(identity.bytes));
    const evaluated = evaluateCompilerObservation(identity.bytes, compiled);
    assert(compiled.status === expected.compiler_status, "COMPILER_RESULT_MISMATCH", `${expected.program_id} status`);
    assert(compiled.outcome_id === expected.outcome_id, "COMPILER_RESULT_MISMATCH", `${expected.program_id} outcome`);
    assert(compiled.kind === expected.outcome_kind, "COMPILER_RESULT_MISMATCH", `${expected.program_id} kind`);
    assert(evaluated.program_id === expected.program_id && evaluated.outcome_id === expected.outcome_id, "ORACLE_RESULT_MISMATCH", `${expected.program_id} oracle`);
    if (compiled.postimage === null) {
      assert(expected.postimage_sha256 === null && expected.postimage_byte_length === null, "COMPILER_RESULT_MISMATCH", "null postimage mismatch");
    } else {
      assert(compiled.postimage.length === expected.postimage_byte_length && sha256(compiled.postimage) === expected.postimage_sha256, "COMPILER_RESULT_MISMATCH", "postimage mismatch");
    }
    assertions += 1;
  }
  return assertions;
}

const FORBIDDEN_NETWORK_SPECIFIERS = new Set([
  "node:http", "node:https", "node:http2", "node:net", "node:tls", "node:dgram", "node:dns",
  "http", "https", "net", "tls", "dgram", "dns", "undici", "ws",
]);

export function scanWorkerSource(path, bytes, importAllowlist) {
  const text = bytes.toString("utf8");
  assert(!/\bimport\s*\(/u.test(text), "DYNAMIC_IMPORT_REJECTED", `${path} dynamic import`);
  assert(!/\brequire\s*\(/u.test(text), "REQUIRE_REJECTED", `${path} require`);
  assert(!/\b(?:fetch|WebSocket|XMLHttpRequest)\s*\(/u.test(text), "NETWORK_CAPABLE_IMPORT_REJECTED", `${path} network API`);
  const imports = [];
  for (const match of text.matchAll(/\b(?:import|export)\s+(?:[^"']*?\s+from\s+)?["']([^"']+)["']/gu)) imports.push(match[1]);
  assert(imports.every((specifier) => !FORBIDDEN_NETWORK_SPECIFIERS.has(specifier)), "NETWORK_CAPABLE_IMPORT_REJECTED", `${path} network module`);
  assert(JSON.stringify([...imports].sort()) === JSON.stringify([...importAllowlist].sort()), "IMPORT_SURFACE_REJECTED", `${path} imports=${imports.join(",")}`);
  return imports;
}

function candidateManifest(absolutePath, taskCard) {
  const loaded = readJsonAbsolute(absolutePath, "CANDIDATE_MANIFEST");
  const manifest = loaded.value;
  exactKeys(manifest, taskCard.candidate_manifest_contract.required_keys, "CANDIDATE_MANIFEST_SCHEMA_REJECTED");
  assert(manifest.schema_version === 1 && manifest.record_type === taskCard.candidate_manifest_contract.record_type, "CANDIDATE_MANIFEST_SCHEMA_REJECTED", "candidate type drift");
  assert(manifest.task_id === TASK_ID, "CANDIDATE_BINDING_REJECTED", "candidate task mismatch");
  assert(/^[0-9a-f]{40}$/u.test(manifest.candidate_commit) && /^[0-9a-f]{40}$/u.test(manifest.candidate_tree), "CANDIDATE_BINDING_REJECTED", "candidate git identity rejected");
  assert(HASH_RE.test(manifest.quality_freeze_manifest_sha256), "CANDIDATE_BINDING_REJECTED", "quality freeze hash rejected");
  const expectedPaths = [...taskCard.worker_import_policy.worker_files].sort();
  assert(Array.isArray(manifest.worker_files_sorted_by_path), "CANDIDATE_MANIFEST_SCHEMA_REJECTED", "worker file list missing");
  const actualPaths = manifest.worker_files_sorted_by_path.map((entry) => entry.path);
  assert(JSON.stringify(actualPaths) === JSON.stringify(expectedPaths), "CANDIDATE_FILE_POPULATION_REJECTED", "worker file population drift");
  for (const entry of manifest.worker_files_sorted_by_path) {
    exactKeys(entry, taskCard.candidate_manifest_contract.worker_file_required_keys, "CANDIDATE_MANIFEST_SCHEMA_REJECTED");
    const identity = secureRead(repoPath(entry.path), "WORKER_SOURCE");
    verifyIdentity(identity, entry, "CANDIDATE_FILE_IDENTITY_REJECTED");
    const mode = `100${(lstatSync(repoPath(entry.path)).mode & 0o777).toString(8).padStart(3, "0")}`;
    assert(entry.mode === mode, "CANDIDATE_FILE_MODE_REJECTED", `${entry.path} mode drift`);
    scanWorkerSource(entry.path, identity.bytes, taskCard.worker_import_policy.static_import_allowlist[entry.path]);
  }
  return Object.freeze({ identity: loaded, manifest });
}

function filledGolden(golden, candidate, candidateManifestSha) {
  const replacements = new Map([
    ["$CANDIDATE_COMMIT", candidate.candidate_commit],
    ["$CANDIDATE_TREE", candidate.candidate_tree],
    ["$CANDIDATE_MANIFEST_SHA256", candidateManifestSha],
    ["$QUALITY_FREEZE_MANIFEST_SHA256", candidate.quality_freeze_manifest_sha256],
  ]);
  const replace = (value) => {
    if (Array.isArray(value)) return value.map(replace);
    if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, replace(child)]));
    return replacements.get(value) ?? value;
  };
  return replace(golden);
}

function directoryIdentity(absolutePath, prefix = "RUN_DIRECTORY") {
  assert(isAbsolute(absolutePath), `${prefix}_PATH_REJECTED`, "directory path must be absolute");
  let stat;
  try { stat = lstatSync(absolutePath); } catch (error) { fail(`${prefix}_MISSING`, error.message); }
  assert(!stat.isSymbolicLink(), `${prefix}_SYMLINK_REJECTED`, "directory symlink rejected");
  assert(stat.isDirectory(), `${prefix}_TYPE_REJECTED`, "directory required");
  return Object.freeze({ dev: stat.dev, ino: stat.ino, realpath: resolve(absolutePath) });
}

function artifactById(runManifest, id) {
  const entry = runManifest.artifacts.find((artifact) => artifact.id === id);
  assert(entry, "EVIDENCE_POPULATION_REJECTED", `missing artifact ${id}`);
  return entry;
}

function readRunArtifact(runRoot, entry) {
  exactKeys(entry, ["id", "path", "byte_length", "sha256"], "RUN_MANIFEST_SCHEMA_REJECTED");
  assert(typeof entry.path === "string" && !isAbsolute(entry.path), "CROSS_RUN_SUBSTITUTION_REJECTED", "artifact path must be relative");
  const absolute = resolve(runRoot, entry.path);
  const rel = relative(runRoot, absolute);
  assert(rel !== "" && !rel.startsWith("..") && !isAbsolute(rel), "CROSS_RUN_SUBSTITUTION_REJECTED", "artifact path escape");
  const loaded = readJsonAbsolute(absolute, "EVIDENCE");
  verifyIdentity(loaded, entry, "EVIDENCE_TAMPER_REJECTED");
  return loaded;
}

function validateObservation(observation, rollback, runRecord, projection, expectedProjection, negativeCases) {
  assert(observation.task_id === TASK_ID && observation.control_id === CONTROL_ID, "RUN_OBSERVATION_REJECTED", "observation task drift");
  assert(observation.compiler_result?.status === "COMPILED" && observation.compiler_result?.program_id === "IR10" && observation.compiler_result?.outcome_id === "CORRECT_END_START", "RUN_OBSERVATION_REJECTED", "compiler observation drift");
  assert(observation.base_test_statuses?.issue === 1 && observation.base_test_statuses?.regression === 0 && observation.base_test_statuses?.typed_failure === "PASS", "RUN_OBSERVATION_REJECTED", "base test drift");
  assert(observation.patched_test_statuses?.issue === 0 && observation.patched_test_statuses?.regression === 0, "RUN_OBSERVATION_REJECTED", "patched test drift");
  assert(JSON.stringify(observation.changed_paths_sorted) === JSON.stringify(["src/range.mjs"]), "RUN_OBSERVATION_REJECTED", "changed path drift");
  assert(observation.negative_controls?.scheduled === negativeCases.scheduled && observation.negative_controls?.rejections === negativeCases.required_rejections && observation.negative_controls?.false_accepts === 0, "NEGATIVE_CONTROL_REJECTED", "negative control drift");
  assert(observation.canary_status === "UNCHANGED" && Object.values(observation.external_effects ?? {}).every((value) => value === false), "EXTERNAL_EFFECT_REJECTED", "external effect drift");
  assert(rollback.status === "PASS" && rollback.source_sha256 === "1e3de2958c9841bbe785d903b2f5453389c4225359308b539ac2cb3194469d75" && rollback.base_commit === "68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f" && rollback.base_tree === "900814727113d65f5dad8b63222e14f39b2cf38b" && rollback.git_status_porcelain === "", "ROLLBACK_OMISSION_REJECTED", "rollback drift");
  assert(runRecord.adapter_id === "B0" && runRecord.terminal_status === "completed" && runRecord.stop_reason_code === "agent_complete", "RUN_RECORD_REJECTED", "run record terminal drift");
  assert(canonicalJsonBytes(projection).equals(canonicalJsonBytes(expectedProjection)), "STABLE_PROJECTION_MISMATCH", "projection differs from frozen golden");
}

function evaluateRun(candidatePath, runManifestPath, quality) {
  const candidate = candidateManifest(candidatePath, quality.taskCard.value);
  const loaded = readJsonAbsolute(runManifestPath, "RUN_MANIFEST");
  const manifest = loaded.value;
  exactKeys(manifest, quality.taskCard.value.run_evidence_contract.run_manifest_required_keys, "RUN_MANIFEST_SCHEMA_REJECTED");
  assert(manifest.schema_version === 1 && manifest.record_type === quality.taskCard.value.run_evidence_contract.run_manifest_record_type, "RUN_MANIFEST_SCHEMA_REJECTED", "run manifest type drift");
  assert(manifest.task_id === TASK_ID && manifest.control_id === CONTROL_ID, "RUN_BINDING_REJECTED", "run task drift");
  assert(manifest.candidate_binding?.candidate_commit === candidate.manifest.candidate_commit && manifest.candidate_binding?.candidate_tree === candidate.manifest.candidate_tree && manifest.candidate_binding?.candidate_manifest_sha256 === candidate.identity.sha256 && manifest.candidate_binding?.quality_freeze_manifest_sha256 === candidate.manifest.quality_freeze_manifest_sha256, "CANDIDATE_BINDING_REJECTED", "run candidate drift");
  const runRootIdentity = directoryIdentity(manifest.run_root);
  assert(manifest.run_id && typeof manifest.run_id === "string", "RUN_BINDING_REJECTED", "run id missing");
  const requiredIds = quality.taskCard.value.run_evidence_contract.required_artifacts.map((entry) => entry.id).sort();
  assert(JSON.stringify(manifest.artifacts.map((entry) => entry.id).sort()) === JSON.stringify(requiredIds), "EVIDENCE_POPULATION_REJECTED", "artifact population drift");
  const artifacts = {};
  for (const id of requiredIds) artifacts[id] = readRunArtifact(manifest.run_root, artifactById(manifest, id));
  assert(JSON.stringify(manifest.evidence_files_sorted) === JSON.stringify([...manifest.artifacts].sort((a, b) => a.path.localeCompare(b.path))), "EVIDENCE_POPULATION_REJECTED", "evidence index drift");
  const runRecordSchema = readRepoJson(RUN_RECORD_SCHEMA, "RUN_RECORD_SCHEMA").value;
  const runRecordErrors = validateSchema(artifacts.run_record.value, runRecordSchema);
  assert(runRecordErrors.length === 0, "RUN_RECORD_SCHEMA_REJECTED", runRecordErrors.join("; "));
  const expectedProjection = filledGolden(quality.assets.golden_stable_projection.value, candidate.manifest, candidate.identity.sha256);
  validateObservation(
    artifacts.observation.value,
    artifacts.rollback.value,
    artifacts.run_record.value,
    artifacts.stable_projection.value,
    expectedProjection,
    quality.assets.negative_cases.value,
  );
  const stableBytes = canonicalJsonBytes(artifacts.stable_projection.value);
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_063_quality_run_review",
    task_id: TASK_ID,
    run_id: manifest.run_id,
    run_root: manifest.run_root,
    run_root_device: runRootIdentity.dev,
    run_root_inode: runRootIdentity.ino,
    candidate_binding: manifest.candidate_binding,
    run_manifest_byte_length: loaded.byte_length,
    run_manifest_sha256: loaded.sha256,
    stable_projection_canonical_byte_length: stableBytes.length,
    stable_projection_canonical_sha256: sha256(stableBytes),
    verdict: "PASS",
  };
}

const REVIEW_KEYS = [
  "schema_version", "record_type", "task_id", "run_id", "run_root", "run_root_device", "run_root_inode",
  "candidate_binding", "run_manifest_byte_length", "run_manifest_sha256", "stable_projection_canonical_byte_length",
  "stable_projection_canonical_sha256", "verdict",
];

function compareRuns(runAPath, runBPath) {
  const a = readJsonAbsolute(runAPath, "RUN_A_REVIEW").value;
  const b = readJsonAbsolute(runBPath, "RUN_B_REVIEW").value;
  exactKeys(a, REVIEW_KEYS, "RUN_REVIEW_SCHEMA_REJECTED");
  exactKeys(b, REVIEW_KEYS, "RUN_REVIEW_SCHEMA_REJECTED");
  assert(a.verdict === "PASS" && b.verdict === "PASS", "RUN_REVIEW_NON_PASS", "review non-pass");
  assert(a.run_id !== b.run_id && a.run_root !== b.run_root, "CROSS_RUN_SUBSTITUTION_REJECTED", "run identity reused");
  assert(a.run_root_device !== b.run_root_device || a.run_root_inode !== b.run_root_inode, "CROSS_RUN_SUBSTITUTION_REJECTED", "run directory identity reused");
  assert(JSON.stringify(a.candidate_binding) === JSON.stringify(b.candidate_binding), "CANDIDATE_BINDING_REJECTED", "candidate binding differs");
  assert(a.stable_projection_canonical_byte_length === b.stable_projection_canonical_byte_length && a.stable_projection_canonical_sha256 === b.stable_projection_canonical_sha256, "STABLE_PROJECTION_MISMATCH", "run projections differ");
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_063_dual_run_comparison",
    task_id: TASK_ID,
    run_ids: [a.run_id, b.run_id],
    candidate_binding: a.candidate_binding,
    stable_projection_canonical_byte_length: a.stable_projection_canonical_byte_length,
    stable_projection_canonical_sha256: a.stable_projection_canonical_sha256,
    verdict: "PASS",
  };
}

function expectedFailure(fn, reasonCode) {
  try {
    fn();
  } catch (error) {
    assert(error instanceof QualityError && error.reasonCode === reasonCode, "SELF_TEST_REASON_DRIFT", `expected ${reasonCode}, got ${error.reasonCode ?? error.message}`);
    return 1;
  }
  fail("SELF_TEST_FALSE_ACCEPT", `expected ${reasonCode}`);
}

function selfTest(quality) {
  let assertions = 0;
  const taskCard = quality.taskCard.value;
  const taskSchema = quality.assets.task_card_schema.value;
  const submission = quality.assets.offline_submission.value;
  const submissionSchema = quality.assets.offline_submission_schema.value;
  validateSchemaClosure(taskSchema, Object.keys(taskCard), "task-card"); assertions += 1;
  validateSchemaClosure(submissionSchema, SUBMISSION_KEYS, "offline-submission"); assertions += 1;
  validateOfflineSubmission(submission, submission); assertions += 1;
  verifyAcceptedInputs(taskCard); assertions += 1;
  assertions += verifyProgramTable(quality.assets.expected_results.value);
  const closure = evaluateByteClosureCompiler(compileFiniteTypedPatchIr);
  const expectedClosure = quality.assets.expected_results.value.closed_ir.byte_closure;
  assert(JSON.stringify(closure) === JSON.stringify(expectedClosure), "BYTE_CLOSURE_MISMATCH", "byte closure drift"); assertions += 1;
  const negatives = quality.assets.negative_cases.value;
  assert(negatives.scheduled === 28 && negatives.required_rejections === 28 && negatives.maximum_false_accepts === 0 && new Set(negatives.cases.map((entry) => entry.id)).size === 28, "NEGATIVE_MATRIX_REJECTED", "negative matrix drift"); assertions += 1;
  const golden = quality.assets.golden_stable_projection.value;
  assert(Object.values(golden.candidate_binding).every((value) => typeof value === "string" && value.startsWith("$")), "GOLDEN_REJECTED", "candidate placeholder drift");
  assert(Object.values(golden.external_effects).every((value) => value === false) && golden.verdict === "PASS_ONLY_SUCCESS", "GOLDEN_REJECTED", "golden effect/verdict drift"); assertions += 1;
  const mutate = (fn) => { const value = structuredClone(submission); fn(value); return value; };
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.extra = true; }), submission), "SUBMISSION_UNKNOWN_MEMBER_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.proposal.extra = true; }), submission), "PROPOSAL_UNKNOWN_MEMBER_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(null, submission), "SUBMISSION_UNKNOWN_MEMBER_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.task_id = "wrong"; }), submission), "TASK_BINDING_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.base_commit = "0".repeat(40); }), submission), "BASE_COMMIT_MISMATCH_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.base_tree = "0".repeat(40); }), submission), "BASE_TREE_MISMATCH_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.target_id = "wrong"; }), submission), "TARGET_BINDING_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.proposal.program_id = "IR00"; }), submission), "PROGRAM_BINDING_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.proposal.path = "../escape"; }), submission), "PROPOSAL_PATH_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.proposal.byte_length = 254; }), submission), "PROPOSAL_LENGTH_MISMATCH_REJECTED");
  assertions += expectedFailure(() => validateOfflineSubmission(mutate((v) => { v.proposal.sha256 = "0".repeat(64); }), submission), "PROPOSAL_HASH_MISMATCH_REJECTED");
  const invalidIr = Buffer.from(secureRead(repoPath(taskCard.accepted_substrate.success_program.path), "FINITE_IR_PROGRAM").bytes);
  invalidIr[0] ^= 1;
  assert(compileFiniteTypedPatchIr(invalidIr).reason_code === "IR_NOT_EXACTLY_ADMITTED", "SELF_TEST_FALSE_ACCEPT", "invalid IR admitted"); assertions += 1;
  assertions += expectedFailure(
    () => scanWorkerSource("negative.mjs", Buffer.from("import { request } from \"node:http\";\n", "utf8"), []),
    "NETWORK_CAPABLE_IMPORT_REJECTED",
  );
  assert(taskCard.filesystem_policy.directory.nlink_gate === false && taskCard.filesystem_policy.file_leaf.nlink_required === 1, "FILESYSTEM_POLICY_REJECTED", "directory/file nlink policy drift"); assertions += 1;
  return {
    schema_version: 1,
    record_type: "sourcelens_aios_p1_063_quality_self_test",
    evaluator_version: QUALITY_EVALUATOR_VERSION,
    task_id: TASK_ID,
    assertions,
    byte_closure_total: closure.total,
    byte_closure_false_accepts: closure.false_accepts,
    negative_cases_frozen: negatives.scheduled,
    empty_sha256: EMPTY_SHA256,
    verdict: "PASS",
  };
}

function parseArgs(argv) {
  const mode = argv[0];
  const options = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(key?.startsWith("--") && value !== undefined, "CLI_REJECTED", "invalid arguments");
    assert(!options.has(key), "CLI_REJECTED", `duplicate ${key}`);
    options.set(key, value);
  }
  return { mode, options };
}

function requiredOption(options, name) {
  const value = options.get(name);
  assert(value && isAbsolute(value), "CLI_REJECTED", `${name} must be absolute`);
  return value;
}

function main() {
  const { mode, options } = parseArgs(process.argv.slice(2));
  const quality = loadQualityAssets();
  let result;
  if (mode === "self-test") {
    assert(options.size === 0, "CLI_REJECTED", "self-test takes no options");
    result = selfTest(quality);
  } else if (mode === "preflight-candidate") {
    assert(options.size === 1, "CLI_REJECTED", "preflight-candidate option drift");
    const candidate = candidateManifest(requiredOption(options, "--candidate-manifest"), quality.taskCard.value);
    result = {
      schema_version: 1,
      record_type: "sourcelens_aios_p1_063_candidate_preflight",
      task_id: TASK_ID,
      candidate_commit: candidate.manifest.candidate_commit,
      candidate_tree: candidate.manifest.candidate_tree,
      candidate_manifest_sha256: candidate.identity.sha256,
      worker_files: candidate.manifest.worker_files_sorted_by_path.length,
      verdict: "PASS",
    };
  } else if (mode === "evaluate-run") {
    assert(options.size === 2, "CLI_REJECTED", "evaluate-run option drift");
    result = evaluateRun(
      requiredOption(options, "--candidate-manifest"),
      requiredOption(options, "--run-manifest"),
      quality,
    );
  } else if (mode === "compare-runs") {
    assert(options.size === 2, "CLI_REJECTED", "compare-runs option drift");
    result = compareRuns(requiredOption(options, "--run-a-review"), requiredOption(options, "--run-b-review"));
  } else {
    fail("CLI_REJECTED", "usage: quality-evaluator.mjs self-test | preflight-candidate | evaluate-run | compare-runs");
  }
  process.stdout.write(canonicalJsonBytes(result));
}

try {
  main();
} catch (error) {
  const reasonCode = error instanceof QualityError ? error.reasonCode : "UNEXPECTED";
  process.stderr.write(`P1_063_QUALITY: NON_PASS reason_code=${reasonCode} detail=${error.message}\n`);
  process.exitCode = 1;
}

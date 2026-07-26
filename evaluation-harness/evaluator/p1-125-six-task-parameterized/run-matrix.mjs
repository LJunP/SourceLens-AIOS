#!/usr/bin/env node

import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";

import { canonicalJson, validate } from "../schema-validator.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const FIXTURE_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-125-six-task-parameterized",
);
const RUN_RECORD_SCHEMA = JSON.parse(readFileSync(
  join(REPOSITORY_ROOT, "docs/aios/schemas/run-record.schema.json"),
  "utf8",
));
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const STDOUT_KEYS = Object.freeze([
  "schema_version",
  "request_id",
  "case_id",
  "status",
  "reason_code",
  "target_execution_count",
  "output_root_created",
  "run_record_ref",
  "stable_projection_ref",
  "trace_ref",
  "external_effects",
  "cleanup",
]);
const BOUND_KEYS = Object.freeze(["path", "sha256", "byte_length"]);
const CLEANUP_KEYS = Object.freeze(["owned_paths_removed", "nonowned_paths_touched"]);
const CONFIG_BY_CASE = Object.freeze({
  B0_A: "system-configurations/b0-a.json",
  B0_B: "system-configurations/b0-b.json",
  B1_A: "system-configurations/b1-a.json",
  B1_B: "system-configurations/b1-b.json",
  B2_A: "system-configurations/b2-a.json",
  B2_B: "system-configurations/b2-b.json",
});
const DESCRIPTOR_BY_ADAPTER = Object.freeze({
  B0: "evaluation-harness/adapters/p1-125-six-task-parameterized/b0-descriptor-template.json",
  B1: "evaluation-harness/adapters/p1-125-six-task-parameterized/b1-descriptor-template.json",
  B2: "evaluation-harness/adapters/p1-125-six-task-parameterized/b2-descriptor-template.json",
});
const ACCEPTED_P0_BINDING = Object.freeze({
  frozen_base_commit: "09cf8dd6a1bcee138b949d117804d652000eb7cc",
  frozen_base_tree: "daa58725d293b954887dbe5b17aab5219b618658",
  checkpoint_commit: "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10",
  checkpoint_tree: "2c0956ae8598547466f691ead21532a026006bf9",
  analyzer_subtree: "408d57e9b4926f95ad059ab2675ee88dfc533096",
  operation_id: "repository_analysis.scan",
});

class QualityNonPass extends Error {
  constructor(reason, detail = "") {
    super(detail ? `${reason}: ${detail}` : reason);
    this.name = "QualityNonPass";
    this.reason = reason;
  }
}
const DATASET_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1",
);
const DATASET_MANIFEST = JSON.parse(readFileSync(join(DATASET_ROOT, "dataset-manifest.json"), "utf8"));
const PROGRAM_SET = JSON.parse(readFileSync(join(FIXTURE_ROOT, "b1-program-set.json"), "utf8"));

function fail(reason, detail = "") {
  throw new QualityNonPass(reason, detail);
}

function assert(condition, reason, detail = "") {
  if (!condition) fail(reason, detail);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function identity(bytes) {
  return { sha256: sha256(bytes), byte_length: bytes.length };
}

function exactKeys(value, keys, reason) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    reason,
    "expected object",
  );
  assert(
    isDeepStrictEqual(Object.keys(value).sort(), [...keys].sort()),
    reason,
    `keys=${Object.keys(value).sort().join(",")}`,
  );
}

function canonicalBytes(value) {
  return Buffer.from(`${canonicalJson(value)}\n`, "utf8");
}

function createDirectory(path) {
  assert(isAbsolute(path) && resolve(path) === path && !existsSync(path), "QUALITY_OUTPUT_ROOT_INVALID", path);
  const parent = dirname(path);
  assert(existsSync(parent) && statSync(parent).isDirectory() && !lstatSync(parent).isSymbolicLink(), "QUALITY_OUTPUT_ROOT_INVALID", parent);
  mkdirSync(path, { recursive: false, mode: 0o700 });
  assert(realpathSync(path) === path && !lstatSync(path).isSymbolicLink(), "QUALITY_OUTPUT_ROOT_INVALID", path);
}

function writeCreateOnce(path, bytes) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  writeFileSync(path, bytes, { flag: "wx", mode: 0o600 });
}

function writeJson(path, value) {
  writeCreateOnce(path, canonicalBytes(value));
}

function bound(path) {
  const bytes = readFileSync(path);
  return { path, ...identity(bytes) };
}

function cloneJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function contained(root, path, reason) {
  const absolute = isAbsolute(path) ? resolve(path) : resolve(root, path);
  const rel = relative(resolve(root), absolute);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), reason, path);
  return absolute;
}

function resolveBoundOutput(outputRoot, reference, reason) {
  exactKeys(reference, BOUND_KEYS, reason);
  assert(/^[0-9a-f]{64}$/.test(reference.sha256) && Number.isInteger(reference.byte_length), reason);
  const path = contained(outputRoot, reference.path, reason);
  assert(existsSync(path), reason, reference.path);
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1, reason, path);
  const bytes = readFileSync(path);
  assert(isDeepStrictEqual(identity(bytes), { sha256: reference.sha256, byte_length: reference.byte_length }), reason, path);
  return { path, bytes };
}

function parseCanonicalJson(bytes, reason, detail) {
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(reason, `${detail}: ${error.message}`);
  }
  assert(bytes.equals(canonicalBytes(value)), reason, `${detail}: non-canonical JSON`);
  return value;
}

function assertFalseExternalEffects(value, reason) {
  exactKeys(value, Object.keys(FALSE_EFFECTS), reason);
  assert(isDeepStrictEqual(value, FALSE_EFFECTS), reason);
}

function assertPassingLedger(ledger, reason, detail) {
  assert(
    ledger !== null &&
      typeof ledger === "object" &&
      !Array.isArray(ledger) &&
      Array.isArray(ledger.argv) &&
      ledger.argv.length >= 1 &&
      ledger.argv.every((entry) => typeof entry === "string" && !entry.includes("\0")) &&
      typeof ledger.cwd === "string" &&
      isAbsolute(ledger.cwd) &&
      ledger.timed_out === false &&
      ledger.signal === null &&
      ledger.exit_status === 0 &&
      Array.isArray(ledger.expected_exit_codes) &&
      ledger.expected_exit_codes.includes(0) &&
      ledger.expected_exit_matched === true &&
      /^[0-9a-f]{64}$/.test(ledger.stdout_sha256) &&
      Number.isInteger(ledger.stdout_byte_length) &&
      /^[0-9a-f]{64}$/.test(ledger.stderr_sha256) &&
      Number.isInteger(ledger.stderr_byte_length),
    reason,
    detail,
  );
}

function assertRegularOwnedPath(path, positiveRoot, reason) {
  const absolute = contained(positiveRoot, path, reason);
  assert(existsSync(absolute), reason, absolute);
  const stat = lstatSync(absolute);
  assert(stat.isFile() && !stat.isSymbolicLink(), reason, absolute);
  return absolute;
}

function assertResultCommon(adapterResult, runRecord, positive) {
  const task = JSON.parse(readFileSync(positive.request.task_spec.path, "utf8"));
  const configuration = JSON.parse(readFileSync(positive.request.system_configuration.path, "utf8"));
  const descriptor = JSON.parse(readFileSync(positive.request.execution_descriptor.path, "utf8"));
  assert(
    adapterResult.schema_version === "1.0" &&
      adapterResult.record_type === "p1_125_documented_adapter_result" &&
      adapterResult.run_id === runRecord.run_id &&
      adapterResult.task_id === task.task_id &&
      adapterResult.adapter_id === positive.request.adapter_id &&
      adapterResult.adapter_version === descriptor.adapter_version &&
      adapterResult.system_configuration_id === configuration.configuration_id &&
      adapterResult.repetition_id === positive.request.repetition_id &&
      adapterResult.terminal_status === "completed" &&
      adapterResult.stop_reason_code === "agent_complete" &&
      adapterResult.source_mutation_observed === false &&
      isDeepStrictEqual(adapterResult.usage, runRecord.usage),
    "ADAPTER_RESULT_BINDING_INVALID",
    positive.request.case_id,
  );
  assertFalseExternalEffects(
    adapterResult.requested_external_effects,
    "ADAPTER_RESULT_EXTERNAL_EFFECTS_INVALID",
  );
  assertFalseExternalEffects(
    adapterResult.observed_external_effects,
    "ADAPTER_RESULT_EXTERNAL_EFFECTS_INVALID",
  );
  assert(
    adapterResult.usage !== null &&
      typeof adapterResult.usage === "object" &&
      Number.isInteger(adapterResult.usage.input_tokens) &&
      Number.isInteger(adapterResult.usage.output_tokens) &&
      Number.isInteger(adapterResult.usage.tool_calls) &&
      adapterResult.usage.input_tokens <= descriptor.limits.max_model_tokens &&
      adapterResult.usage.output_tokens <= descriptor.limits.max_model_tokens &&
      adapterResult.usage.tool_calls <= descriptor.limits.max_tool_calls &&
      adapterResult.usage.cost_usd <= descriptor.limits.max_cost_usd,
    "ADAPTER_RESULT_LIMIT_INVALID",
    positive.request.case_id,
  );
  assert(
    Array.isArray(adapterResult.actions) &&
      adapterResult.actions.length >= 1 &&
      adapterResult.actions.every((action, index) => (
        action.sequence === index + 1 &&
        action.action_id === `${runRecord.run_id}:${index + 1}`
      )),
    "ADAPTER_RESULT_ACTION_JOIN_INVALID",
    positive.request.case_id,
  );
}

function assertB0Result(adapterResult, positive) {
  assert(
    adapterResult.usage.tool_calls === 0 &&
      adapterResult.actions.length === 1 &&
      adapterResult.actions[0].action_type === "frozen_result_admission" &&
      adapterResult.actions[0].tool_class === null &&
      adapterResult.provenance.kind === "QUALITY_FROZEN_PROVIDER_NEUTRAL_CONFORMANCE_RESULT" &&
      adapterResult.provenance.live_model_invoked === false &&
      adapterResult.provenance.provider_invoked === false &&
      adapterResult.provenance.model_performance_sample === false &&
      adapterResult.rollback.required === false &&
      adapterResult.rollback.status === "NOT_APPLICABLE_NO_SOURCE_MUTATION",
    "B0_INDEPENDENT_EVIDENCE_INVALID",
    positive.request.case_id,
  );
  exactKeys(adapterResult.result, ["task_id", "summary", "changed_paths", "tests"], "B0_INDEPENDENT_EVIDENCE_INVALID");
  assert(
    adapterResult.result.task_id === JSON.parse(readFileSync(positive.request.task_spec.path, "utf8")).task_id &&
      typeof adapterResult.result.summary === "string" &&
      adapterResult.result.summary.length > 0 &&
      Array.isArray(adapterResult.result.changed_paths) &&
      Array.isArray(adapterResult.result.tests),
    "B0_INDEPENDENT_EVIDENCE_INVALID",
    positive.request.case_id,
  );
}

function assertB1Result(adapterResult, positive, physicalRoot) {
  const expectedTools = [
    "file_listing",
    "file_read",
    "lexical_search",
    "structured_patch",
    "verification_command",
    "verification_command",
  ];
  assert(
    adapterResult.usage.tool_calls === 6 &&
      adapterResult.actions.length === 6 &&
      isDeepStrictEqual(adapterResult.actions.map((action) => action.tool_class), expectedTools) &&
      adapterResult.provenance.kind === "QUALITY_FROZEN_FINITE_TOOL_CONFORMANCE_PROGRAM" &&
      adapterResult.provenance.live_model_invoked === false &&
      adapterResult.provenance.provider_invoked === false &&
      adapterResult.provenance.model_performance_sample === false &&
      adapterResult.rollback.status === "PASS_EXACT" &&
      Array.isArray(adapterResult.rollback.files) &&
      adapterResult.rollback.files.length >= 1 &&
      adapterResult.rollback.files.every((entry) => entry.matches === true) &&
      Array.isArray(adapterResult.rollback.changed_paths) &&
      Array.isArray(adapterResult.rollback.created_paths_removed),
    "B1_INDEPENDENT_EVIDENCE_INVALID",
    positive.request.case_id,
  );
  assert(
    Array.isArray(adapterResult.verification_ledgers) &&
      adapterResult.verification_ledgers.length === 2,
    "B1_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: verification ledger count`,
  );
  for (const [index, entry] of adapterResult.verification_ledgers.entries()) {
    assertPassingLedger(
      entry.ledger,
      "B1_INDEPENDENT_EVIDENCE_INVALID",
      `${positive.request.case_id}: verification ledger ${index + 1}`,
    );
    const action = adapterResult.actions[index + 4];
    assert(
      action.command_id === entry.command_id &&
        action.expected_exit_matched === true &&
        action.exit_code === 0 &&
        action.stdout_sha256 === entry.ledger.stdout_sha256 &&
        action.stderr_sha256 === entry.ledger.stderr_sha256,
      "B1_INDEPENDENT_EVIDENCE_INVALID",
      `${positive.request.case_id}: action-ledger join ${index + 1}`,
    );
  }
  const sourceRoot = resolve(physicalRoot, adapterResult.rollback.source_root);
  assert(
    contained(physicalRoot, sourceRoot, "B1_INDEPENDENT_EVIDENCE_INVALID") === sourceRoot &&
      existsSync(sourceRoot) &&
      statSync(sourceRoot).isDirectory() &&
      !lstatSync(sourceRoot).isSymbolicLink(),
    "B1_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: rollback source`,
  );
  for (const file of adapterResult.rollback.files) {
    const path = assertRegularOwnedPath(join(sourceRoot, file.path), physicalRoot, "B1_INDEPENDENT_EVIDENCE_INVALID");
    const bytes = readFileSync(path);
    assert(
      sha256(bytes) === file.sha256 && bytes.length === file.byte_length,
      "B1_INDEPENDENT_EVIDENCE_INVALID",
      `${positive.request.case_id}: ${file.path}`,
    );
  }
}

function assertB2Result(adapterResult, positive, physicalRoot) {
  const binding = adapterResult.provenance?.p0_binding;
  const expectedBindingChecks = new Map([
    ["frozen_base_tree", ACCEPTED_P0_BINDING.frozen_base_tree],
    ["checkpoint_tree", ACCEPTED_P0_BINDING.checkpoint_tree],
    ["frozen_analyzer_subtree", ACCEPTED_P0_BINDING.analyzer_subtree],
    ["checkpoint_analyzer_subtree", ACCEPTED_P0_BINDING.analyzer_subtree],
  ]);
  assert(
    adapterResult.usage.tool_calls === 1 &&
      adapterResult.actions.length === 1 &&
      adapterResult.actions[0].tool_class === "repository_analysis.scan" &&
      adapterResult.actions[0].operation_id === ACCEPTED_P0_BINDING.operation_id &&
      adapterResult.actions[0].expected_exit_matched === true &&
      adapterResult.actions[0].exit_code === 0 &&
      adapterResult.provenance.kind === "EXACT_ACCEPTED_P0_FROZEN_BASE_REAL_SCAN" &&
      adapterResult.provenance.live_model_invoked === false &&
      adapterResult.provenance.provider_invoked === false &&
      adapterResult.provenance.model_performance_sample === false &&
      isDeepStrictEqual(binding, ACCEPTED_P0_BINDING) &&
      adapterResult.rollback.required === false &&
      adapterResult.rollback.status === "NOT_APPLICABLE_READ_ONLY_SCAN_SOURCE_UNCHANGED" &&
      adapterResult.rollback.source_exact_after_scan === true,
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    positive.request.case_id,
  );

  assert(
    Array.isArray(adapterResult.p0_binding_checks) &&
      adapterResult.p0_binding_checks.length === 5,
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: P0 binding checks`,
  );
  for (const check of adapterResult.p0_binding_checks) {
    assertPassingLedger(check.ledger, "B2_INDEPENDENT_EVIDENCE_INVALID", `${positive.request.case_id}: ${check.id}`);
    assert(
      Object.hasOwn(check, "expected")
        ? expectedBindingChecks.has(check.id) &&
          check.expected === expectedBindingChecks.get(check.id) &&
          check.observed === expectedBindingChecks.get(check.id)
        : check.id === "frozen_base_is_checkpoint_ancestor" && check.status === "PASS",
      "B2_INDEPENDENT_EVIDENCE_INVALID",
      `${positive.request.case_id}: ${check.id}`,
    );
  }
  assert(
    new Set(adapterResult.p0_binding_checks.map((check) => check.id)).size === 5 &&
      [...expectedBindingChecks.keys()].every((id) => adapterResult.p0_binding_checks.some((check) => check.id === id)) &&
      adapterResult.p0_binding_checks.some((check) => check.id === "frozen_base_is_checkpoint_ancestor"),
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: P0 binding check set`,
  );
  const frozenManifest = cloneJson(join(FIXTURE_ROOT, "b2-p0-source-manifest.json"));
  assert(
    adapterResult.materialized_analyzer.subtree === ACCEPTED_P0_BINDING.analyzer_subtree &&
      Array.isArray(adapterResult.materialized_analyzer.artifacts) &&
      adapterResult.materialized_analyzer.artifacts.length === frozenManifest.entry_count &&
      frozenManifest.entry_count === 10,
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: materialized analyzer`,
  );
  assertPassingLedger(
    adapterResult.materialized_analyzer.listing_ledger,
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: analyzer tree listing`,
  );
  const analyzerRoot = resolve(physicalRoot, "work/b2-p0-analyzer");
  for (const [index, artifact] of adapterResult.materialized_analyzer.artifacts.entries()) {
    const expected = frozenManifest.entries[index];
    assert(
      artifact.path === expected.path &&
        artifact.git_blob === expected.git_blob &&
        artifact.sha256 === expected.sha256 &&
        artifact.byte_length === expected.byte_length &&
        artifact.relative_path === expected.path.replace(/^analyzer-rust\//, ""),
      "B2_INDEPENDENT_EVIDENCE_INVALID",
      `${positive.request.case_id}: analyzer artifact`,
    );
    assertPassingLedger(
      artifact.ledger,
      "B2_INDEPENDENT_EVIDENCE_INVALID",
      `${positive.request.case_id}: ${artifact.path}`,
    );
    const path = assertRegularOwnedPath(
      join(analyzerRoot, artifact.relative_path),
      physicalRoot,
      "B2_INDEPENDENT_EVIDENCE_INVALID",
    );
    const bytes = readFileSync(path);
    assert(
      sha256(bytes) === expected.sha256 && bytes.length === expected.byte_length,
      "B2_INDEPENDENT_EVIDENCE_INVALID",
      `${positive.request.case_id}: physical ${artifact.path}`,
    );
  }

  const buildLedger = adapterResult.toolchain_ledgers?.offline_locked_build;
  assertPassingLedger(buildLedger, "B2_INDEPENDENT_EVIDENCE_INVALID", `${positive.request.case_id}: offline locked build`);
  assert(
    buildLedger.argv.includes("build") &&
      buildLedger.argv.includes("--offline") &&
      buildLedger.argv.includes("--locked") &&
      buildLedger.environment?.CARGO_NET_OFFLINE === "true" &&
      buildLedger.argv.includes("--manifest-path") &&
      buildLedger.argv.includes(join(analyzerRoot, "Cargo.toml")) &&
      buildLedger.argv.includes("--target-dir") &&
      buildLedger.argv.some((entry) => entry === join(physicalRoot, "work/b2-cargo-target")),
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: build is not offline and locked`,
  );
  const scanLedger = adapterResult.scan_ledger;
  assertPassingLedger(scanLedger, "B2_INDEPENDENT_EVIDENCE_INVALID", `${positive.request.case_id}: scan ledger`);
  assert(
    scanLedger.argv.length === 4 &&
      scanLedger.argv[1] === "scan" &&
      scanLedger.argv[2] === "--repo-path" &&
      scanLedger.cwd === physicalRoot,
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: scan argv`,
  );
  const executable = assertRegularOwnedPath(scanLedger.argv[0], physicalRoot, "B2_INDEPENDENT_EVIDENCE_INVALID");
  const executableBytes = readFileSync(executable);
  assert(
    sha256(executableBytes) === adapterResult.actions[0].executable_sha256 &&
      executableBytes.length === adapterResult.actions[0].executable_byte_length &&
      adapterResult.actions[0].stdout_sha256 === scanLedger.stdout_sha256 &&
      adapterResult.actions[0].stderr_sha256 === scanLedger.stderr_sha256,
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: physical analyzer executable`,
  );
  const sourceRoot = contained(physicalRoot, scanLedger.argv[3], "B2_INDEPENDENT_EVIDENCE_INVALID");
  assert(
    existsSync(sourceRoot) &&
      statSync(sourceRoot).isDirectory() &&
      !lstatSync(sourceRoot).isSymbolicLink() &&
      adapterResult.scan_result.scan_result_schema_version === 2 &&
      realpathSync(adapterResult.scan_result.repo_path) === realpathSync(sourceRoot) &&
      Array.isArray(adapterResult.scan_result.file_tree?.file_manifest) &&
      adapterResult.scan_result.file_tree.file_manifest.length >= 1,
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: physical scan result`,
  );
  const caseDescriptor = cloneJson(positive.request.execution_descriptor.path);
  const taskSourceProgram = cloneJson(caseDescriptor.input_bindings.task_source_program.path);
  const acceptedSourceRoot = resolve(REPOSITORY_ROOT, taskSourceProgram.task_source);
  const physicalSourceInventory = inventory(sourceRoot);
  assert(
    existsSync(acceptedSourceRoot) &&
      statSync(acceptedSourceRoot).isDirectory() &&
      isDeepStrictEqual(physicalSourceInventory, inventory(acceptedSourceRoot)) &&
      adapterResult.actions[0].source_manifest_sha256 === sha256(Buffer.from(canonicalJson(
        physicalSourceInventory.map((entry) => ({
          relative_path: entry.path,
          sha256: entry.sha256,
          byte_length: entry.byte_length,
        })),
      ), "utf8")),
    "B2_INDEPENDENT_EVIDENCE_INVALID",
    `${positive.request.case_id}: scan source changed`,
  );
}

function verifyAdapterResult(root, runRecord, positive) {
  assert(
    Array.isArray(runRecord.test_artifact_refs) &&
      runRecord.test_artifact_refs.length === 1 &&
      runRecord.test_artifact_refs[0] === "adapter-result.json" &&
      runRecord.patch_ref === (positive.request.adapter_id === "B1" ? "adapter-result.json" : null) &&
      runRecord.artifact_checksums !== null &&
      typeof runRecord.artifact_checksums === "object" &&
      /^[0-9a-f]{64}$/.test(runRecord.artifact_checksums.adapter_result),
    "ADAPTER_RESULT_BINDING_INVALID",
    positive.request.case_id,
  );
  const path = contained(root, runRecord.test_artifact_refs[0], "ADAPTER_RESULT_BINDING_INVALID");
  assert(existsSync(path), "ADAPTER_RESULT_BINDING_INVALID", path);
  const stat = lstatSync(path);
  assert(stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1, "ADAPTER_RESULT_BINDING_INVALID", path);
  const bytes = readFileSync(path);
  assert(sha256(bytes) === runRecord.artifact_checksums.adapter_result, "ADAPTER_RESULT_BINDING_INVALID", path);
  const adapterResult = parseCanonicalJson(bytes, "ADAPTER_RESULT_BINDING_INVALID", positive.request.case_id);
  assertResultCommon(adapterResult, runRecord, positive);
  if (positive.request.adapter_id === "B0") assertB0Result(adapterResult, positive);
  else if (positive.request.adapter_id === "B1") assertB1Result(adapterResult, positive, root);
  else if (positive.request.adapter_id === "B2") assertB2Result(adapterResult, positive, positive.outputRoot);
  else fail("ADAPTER_RESULT_BINDING_INVALID", positive.request.adapter_id);
  return adapterResult;
}

function verifyTraceEvidence(traceLines, runRecord, adapterResult, positive) {
  assert(
    runRecord.trace_ref === "trace.jsonl" &&
      positive.traceFile.path.endsWith("/trace.jsonl") &&
      runRecord.artifact_checksums.trace === sha256(positive.traceFile.bytes),
    "TRACE_JOIN_INVALID",
    `${positive.request.case_id}: RunRecord trace binding`,
  );
  assert(
    traceLines.length === adapterResult.actions.length + 2 &&
      traceLines.every((event, index) => (
        event.event_sequence === index + 1 &&
        event.run_id === runRecord.run_id &&
        event.task_id === runRecord.task_id &&
        event.adapter_id === runRecord.adapter_id &&
        event.adapter_version === runRecord.adapter_version &&
        event.system_configuration_id === runRecord.system_configuration_id &&
        event.repetition_id === runRecord.repetition_id
      )),
    "TRACE_JOIN_INVALID",
    `${positive.request.case_id}: trace event sequence`,
  );
  const started = traceLines[0];
  const completed = traceLines.at(-1);
  assert(
    started.record_type === "p1_125_run_started" &&
      started.requested_external_effects !== null &&
      isDeepStrictEqual(started.requested_external_effects, FALSE_EFFECTS) &&
      started.input_bindings?.task_spec?.sha256 === runRecord.artifact_checksums.task_spec &&
      started.input_bindings?.environment_snapshot?.sha256 === runRecord.artifact_checksums.environment_snapshot &&
      started.input_bindings?.system_configuration?.sha256 === runRecord.artifact_checksums.system_configuration,
    "TRACE_JOIN_INVALID",
    `${positive.request.case_id}: started event`,
  );
  for (let index = 0; index < adapterResult.actions.length; index += 1) {
    const event = traceLines[index + 1];
    assert(
      event.record_type === "p1_125_observable_action" &&
        isDeepStrictEqual(event.action, adapterResult.actions[index]),
      "TRACE_JOIN_INVALID",
      `${positive.request.case_id}: action ${index + 1}`,
    );
  }
  assert(
    completed.record_type === "p1_125_run_completed" &&
      completed.result_identity?.path === "adapter-result.json" &&
      completed.result_identity.sha256 === runRecord.artifact_checksums.adapter_result &&
      Number.isInteger(completed.result_identity.byte_length) &&
      isDeepStrictEqual(completed.usage, adapterResult.usage) &&
      isDeepStrictEqual(completed.observed_external_effects, FALSE_EFFECTS) &&
      completed.terminal_status === "completed" &&
      completed.stop_reason_code === "agent_complete",
    "TRACE_JOIN_INVALID",
    `${positive.request.case_id}: completed event`,
  );
}

function descriptorPath(adapterId) {
  return join(REPOSITORY_ROOT, DESCRIPTOR_BY_ADAPTER[adapterId]);
}

function baseRequest({
  caseId,
  adapterId,
  repetitionId,
  configurationPath,
  descriptor,
  taskPath,
  environmentPath,
  outputRoot,
  mode,
  reasonCode,
  preExecution,
}) {
  return {
    schema_version: "p1-125-worker-request/v1",
    request_id: `P1-125-${caseId}-${randomBytes(8).toString("hex")}`,
    case_id: caseId,
    mode,
    adapter_id: adapterId,
    repetition_id: repetitionId,
    task_spec: bound(taskPath),
    environment_snapshot: bound(environmentPath),
    system_configuration: bound(configurationPath),
    execution_descriptor: bound(descriptor),
    expected_descriptor_identity: identity(readFileSync(descriptor)),
    output_root: outputRoot,
    target_sentinel_path: join(outputRoot, "target-executed"),
    nonowned_fixture: null,
    requested_effects: { ...FALSE_EFFECTS },
    expected_outcome: {
      status: mode === "POSITIVE" ? "PASS" : "REJECTED",
      reason_code: reasonCode,
      pre_execution: preExecution,
    },
  };
}

function materializeTaskAssets({ taskEntry, adapterId, caseRoot }) {
  const taskPath = join(DATASET_ROOT, taskEntry.task_spec_path);
  const task = cloneJson(taskPath);
  const program = PROGRAM_SET.programs.find((entry) => entry.task_id === task.task_id);
  assert(program, "TASK_PROGRAM_MISSING", task.task_id);

  const environment = cloneJson(join(FIXTURE_ROOT, "environment-snapshot-template.json"));
  environment.source.repository_identity = task.repository.identity;
  environment.source.base_commit = task.repository.base_commit;
  environment.source.tree_hash = task.repository.tree_hash;
  const environmentPath = join(caseRoot, "environment-snapshot.json");
  writeJson(environmentPath, environment);

  const programPath = join(caseRoot, "b1-program.json");
  writeJson(programPath, program);
  const b0InputPath = join(caseRoot, "b0-result.json");
  writeJson(b0InputPath, {
    task_id: task.task_id,
    summary: task.issue.text,
    changed_paths: program.rollback.changed_paths,
    tests: task.verification.required_commands.map((command) => command.command_id),
  });

  const descriptor = cloneJson(descriptorPath(adapterId));
  descriptor.descriptor_id = `P1-125-${task.task_id}-${adapterId}`;
  const executablePath = join(REPOSITORY_ROOT, descriptor.executable.path);
  const executableBytes = readFileSync(executablePath);
  descriptor.executable.sha256 = sha256(executableBytes);
  descriptor.executable.byte_length = executableBytes.length;
  if (adapterId === "B0") descriptor.input_bindings.adapter_input = bound(b0InputPath);
  if (adapterId === "B1") descriptor.input_bindings.adapter_input = bound(programPath);
  if (adapterId === "B2") {
    descriptor.input_bindings.adapter_input = bound(join(FIXTURE_ROOT, "b2-p0-binding.json"));
    descriptor.input_bindings.b2_source_manifest = bound(join(FIXTURE_ROOT, "b2-p0-source-manifest.json"));
    descriptor.input_bindings.task_source_program = bound(programPath);
  }
  const descriptorForCase = join(caseRoot, "execution-descriptor.json");
  writeJson(descriptorForCase, descriptor);
  return {
    task,
    taskPath,
    environmentPath,
    program,
    programPath,
    descriptorPath: descriptorForCase,
  };
}

function runWorker(workerEntry, requestPath, outputRoot) {
  const result = spawnSync(
    process.execPath,
    [workerEntry, "--request", requestPath, "--output-root", outputRoot],
    {
      cwd: REPOSITORY_ROOT,
      encoding: null,
      timeout: 180_000,
      maxBuffer: 8 * 1024 * 1024,
      env: {
        HOME: process.env.HOME,
        LC_ALL: "C",
        TZ: "UTC",
        PATH: "/usr/local/bin:/usr/bin:/bin",
      },
    },
  );
  assert(!result.error, "WORKER_INVOCATION_FAILED", result.error?.message ?? "");
  const stderr = result.stderr ?? Buffer.alloc(0);
  assert(stderr.length === 0, "WORKER_STDERR_NONEMPTY", stderr.toString("utf8"));
  const stdout = result.stdout ?? Buffer.alloc(0);
  const text = stdout.toString("utf8");
  assert(text.endsWith("\n") && !text.endsWith("\n\n") && text.trim().split("\n").length === 1, "WORKER_STDOUT_INVALID");
  let value;
  try {
    value = JSON.parse(text);
  } catch (error) {
    fail("WORKER_STDOUT_INVALID", error.message);
  }
  assert(stdout.equals(canonicalBytes(value)), "WORKER_STDOUT_NOT_CANONICAL");
  exactKeys(value, STDOUT_KEYS, "WORKER_STDOUT_INVALID");
  exactKeys(value.external_effects, Object.keys(FALSE_EFFECTS), "WORKER_EXTERNAL_EFFECTS_INVALID");
  assert(isDeepStrictEqual(value.external_effects, FALSE_EFFECTS), "WORKER_EXTERNAL_EFFECTS_INVALID");
  exactKeys(value.cleanup, CLEANUP_KEYS, "WORKER_CLEANUP_INVALID");
  assert(
    Number.isInteger(value.cleanup.owned_paths_removed) &&
      Number.isInteger(value.cleanup.nonowned_paths_touched) &&
      value.cleanup.nonowned_paths_touched === 0,
    "WORKER_CLEANUP_INVALID",
  );
  return { exitCode: result.status, value, stdout };
}

function validatePositiveOutput(workerResult, request, outputRoot) {
  assert(workerResult.exitCode === 0, "POSITIVE_WORKER_EXIT_INVALID");
  assert(
    workerResult.value.status === "PASS" &&
      workerResult.value.reason_code === "PASS" &&
      workerResult.value.request_id === request.request_id &&
      workerResult.value.case_id === request.case_id &&
      workerResult.value.target_execution_count === 1 &&
      workerResult.value.output_root_created === true,
    "POSITIVE_WORKER_RESULT_INVALID",
  );
  assert(existsSync(request.target_sentinel_path), "POSITIVE_TARGET_NOT_EXECUTED");
  assert(
    lstatSync(request.target_sentinel_path).isFile() &&
      !lstatSync(request.target_sentinel_path).isSymbolicLink() &&
      readFileSync(request.target_sentinel_path).length > 0,
    "POSITIVE_TARGET_SENTINEL_INVALID",
  );
  const runRecordFile = resolveBoundOutput(outputRoot, workerResult.value.run_record_ref, "RUN_RECORD_IDENTITY_INVALID");
  const projectionFile = resolveBoundOutput(outputRoot, workerResult.value.stable_projection_ref, "STABLE_PROJECTION_IDENTITY_INVALID");
  const traceFile = resolveBoundOutput(outputRoot, workerResult.value.trace_ref, "TRACE_IDENTITY_INVALID");
  const positive = {
    request,
    workerResult,
    outputRoot,
    runRecord: null,
    runRecordFile,
    projectionFile,
    traceFile,
    inventory: inventory(outputRoot),
  };
  positive.runRecord = verifyOutputSnapshot(outputRoot, positive, positive.inventory);
  return positive;
}

function inventory(root) {
  const walk = (directory) => readdirSync(directory, { withFileTypes: true })
    .flatMap((entry) => {
      const path = join(directory, entry.name);
      const rel = relative(root, path).split(sep).join("/");
      if (entry.isDirectory()) return walk(path);
      const stat = lstatSync(path);
      assert(entry.isFile() && !stat.isSymbolicLink(), "OUTPUT_SET_INVALID", rel);
      const bytes = readFileSync(path);
      return [{ path: rel, ...identity(bytes) }];
    });
  return walk(root).sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path)));
}

function verifyOutputSnapshot(root, positive, expectedInventory) {
  const runRecordPath = join(root, relative(positive.outputRoot, positive.runRecordFile.path));
  const tracePath = join(root, relative(positive.outputRoot, positive.traceFile.path));
  assert(existsSync(runRecordPath), "RUN_RECORD_BINDING_INVALID");
  assert(existsSync(tracePath), "TRACE_JOIN_INVALID");
  let runRecord;
  try {
    runRecord = JSON.parse(readFileSync(runRecordPath, "utf8"));
  } catch (error) {
    fail("RUN_RECORD_BINDING_INVALID", error.message);
  }
  const schemaErrors = validate(runRecord, RUN_RECORD_SCHEMA);
  assert(schemaErrors.length === 0, "RUN_RECORD_BINDING_INVALID", schemaErrors.join("; "));
  const task = JSON.parse(readFileSync(positive.request.task_spec.path, "utf8"));
  const configuration = JSON.parse(readFileSync(positive.request.system_configuration.path, "utf8"));
  assert(
    runRecord.task_id === task.task_id &&
      runRecord.adapter_id === positive.request.adapter_id &&
      runRecord.system_configuration_id === configuration.configuration_id &&
      runRecord.repetition_id === positive.request.repetition_id &&
      (positive.runRecord === null || runRecord.run_id === positive.runRecord.run_id) &&
      runRecord.terminal_status === "completed" &&
      runRecord.stop_reason_code === "agent_complete" &&
      runRecord.policy_violations.length === 0,
    "RUN_RECORD_BINDING_INVALID",
  );
  let traceLines;
  try {
    traceLines = readFileSync(tracePath, "utf8").trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
  } catch (error) {
    fail("TRACE_JOIN_INVALID", error.message);
  }
  assert(traceLines.length >= 1 && traceLines.every((event) => event.run_id === runRecord.run_id), "TRACE_JOIN_INVALID");
  const adapterResult = verifyAdapterResult(root, runRecord, positive);
  verifyTraceEvidence(traceLines, runRecord, adapterResult, positive);

  const observed = inventory(root);
  const expectedByPath = new Map(expectedInventory.map((entry) => [entry.path, entry]));
  const observedByPath = new Map(observed.map((entry) => [entry.path, entry]));
  const extras = observed.filter((entry) => !expectedByPath.has(entry.path));
  const missing = expectedInventory.filter((entry) => !observedByPath.has(entry.path));
  assert(extras.length === 0 && missing.length === 0, "OUTPUT_SET_INVALID");
  for (const expected of expectedInventory) {
    const actual = observedByPath.get(expected.path);
    if (!isDeepStrictEqual(actual, expected)) {
      if (/command.*ledger|ledger.*command/i.test(expected.path)) {
        fail("ARTIFACT_IDENTITY_MISMATCH", expected.path);
      }
      fail("ARTIFACT_IDENTITY_MISMATCH", expected.path);
    }
  }
  return runRecord;
}

function stableComparable(bytes) {
  const value = JSON.parse(bytes.toString("utf8"));
  for (const key of ["run_id", "repetition_id", "started_at", "ended_at"]) delete value[key];
  if (value.usage && typeof value.usage === "object") delete value.usage.latency_ms;
  if (Object.hasOwn(value, "system_configuration_id")) {
    value.system_configuration_id = "PAIR_CONFIGURATION";
  }
  return canonicalBytes(value);
}

function copyJsonForCase(sourcePath, destinationPath) {
  writeCreateOnce(destinationPath, readFileSync(sourcePath));
  return destinationPath;
}

function mutateDescriptor(descriptor, mutation, caseRoot) {
  switch (mutation) {
    case "EXECUTABLE_PATH_MISSING":
      descriptor.executable.path = "evaluation-harness/adapters/p1-125-six-task-parameterized/missing-entry.mjs";
      descriptor.executable.realpath = `REPOSITORY_ROOT/${descriptor.executable.path}`;
      break;
    case "EXECUTABLE_PATH_SYMLINK": {
      const link = join(caseRoot, "physical-executable-symlink.mjs");
      symlinkSync(descriptor.executable.path.startsWith("evaluation-harness/")
        ? join(REPOSITORY_ROOT, descriptor.executable.path)
        : descriptor.executable.path, link);
      descriptor.executable.path = relative(REPOSITORY_ROOT, link).split(sep).join("/");
      descriptor.executable.realpath = `REPOSITORY_ROOT/${descriptor.executable.path}`;
      break;
    }
    case "ARGV_DIFFERS_FROM_DECLARED_COMMAND": descriptor.argv = [...descriptor.argv, "--drift"]; break;
    case "ARGV_NOT_ARRAY": descriptor.argv = "not-an-array"; break;
    case "ARGV_EMPTY": descriptor.argv = []; break;
    case "ARGV_CONTAINS_NUL": descriptor.argv = [...descriptor.argv.slice(0, -1), "NUL\u0000"]; break;
    case "WORKING_DIRECTORY_RELATIVE": descriptor.working_directory = "."; break;
    case "WORKING_DIRECTORY_DIFFERS_FROM_DECLARED_ROOT": descriptor.working_directory = "/private/tmp"; break;
    case "TIMEOUT_ZERO": descriptor.timeout_seconds = 0; break;
    case "TIMEOUT_EXCEEDS_TASK_BUDGET": descriptor.timeout_seconds = 61; break;
    case "EXPECTED_EXIT_CODES_EMPTY": descriptor.expected_exit_codes = []; break;
    case "EXPECTED_EXIT_CODES_DIFFER_FROM_TASK": descriptor.expected_exit_codes = [17]; break;
    case "TOOL_LIMIT_EXCEEDS_TASK_BUDGET": descriptor.limits.max_tool_calls = 9; break;
    case "TOKEN_LIMIT_EXCEEDS_TASK_BUDGET": descriptor.limits.max_model_tokens = 1025; break;
    case "COST_LIMIT_EXCEEDS_TASK_BUDGET": descriptor.limits.max_cost_usd = 1; break;
    case "REQUEST_FORBIDDEN_TOOL_CLASS": descriptor.allowed_tool_classes = [...descriptor.allowed_tool_classes, "open_shell"]; break;
    case "REQUEST_NETWORK_CAPABILITY": descriptor.requested_effects.network = true; break;
    default: break;
  }
}

function materializeNegative({
  negative,
  workerEntry,
  qualityRoot,
  baseAdapter = "B0",
}) {
  const caseRoot = join(qualityRoot, "negative", negative.case_id);
  createDirectory(caseRoot);
  let outputRoot = join(caseRoot, "worker-output");
  baseAdapter = negative.adapter_id ?? baseAdapter;
  const assets = materializeTaskAssets({
    taskEntry: DATASET_MANIFEST.tasks[0],
    adapterId: baseAdapter,
    caseRoot,
  });
  const configSource = join(FIXTURE_ROOT, CONFIG_BY_CASE[`${baseAdapter}_A`]);
  const configPath = copyJsonForCase(configSource, join(caseRoot, "system-configuration.json"));
  let taskPath = assets.taskPath;
  const envPath = assets.environmentPath;
  const baseDescriptorPath = assets.descriptorPath;
  const baseDescriptorBytes = readFileSync(baseDescriptorPath);
  const descriptor = JSON.parse(baseDescriptorBytes.toString("utf8"));
  const descriptorPathForCase = join(caseRoot, "mutated-execution-descriptor.json");

  mutateDescriptor(descriptor, negative.mutation, caseRoot);
  if (negative.mutation === "TASK_PROGRAM_SWAP") {
    const swapped = PROGRAM_SET.programs[1];
    const path = join(caseRoot, "tampered-program.json");
    writeJson(path, swapped);
    descriptor.input_bindings.adapter_input = bound(path);
  }
  if (["PROGRAM_MANIFEST_DRIFT", "SOURCE_TEMPLATE_DRIFT", "B1_ACTION_REORDER", "B1_ROLLBACK_DRIFT"].includes(negative.mutation)) {
    const program = cloneJson(assets.programPath);
    if (negative.mutation === "PROGRAM_MANIFEST_DRIFT") program.dataset_manifest_sha256 = "0".repeat(64);
    if (negative.mutation === "SOURCE_TEMPLATE_DRIFT") program.task_source = `${program.task_source}-drift`;
    if (negative.mutation === "B1_ACTION_REORDER") [program.actions[0], program.actions[1]] = [program.actions[1], program.actions[0]];
    if (negative.mutation === "B1_ROLLBACK_DRIFT") program.rollback.changed_paths = ["src/drift.mjs"];
    const path = join(caseRoot, "tampered-program.json");
    writeJson(path, program);
    descriptor.input_bindings.adapter_input = bound(path);
  }
  if (negative.mutation === "B2_BINDING_DRIFT") {
    const binding = cloneJson(join(FIXTURE_ROOT, "b2-p0-binding.json"));
    binding.accepted_p0_checkpoint_tree = "0".repeat(40);
    const path = join(caseRoot, "tampered-b2-binding.json");
    writeJson(path, binding);
    descriptor.input_bindings.adapter_input = bound(path);
  }
  if (negative.mutation === "DESCRIPTOR_BYTES_AFTER_EXPECTED_IDENTITY") {
    descriptor.descriptor_id = `${descriptor.descriptor_id}-PHYSICAL-TAMPER`;
  }

  if (negative.mutation === "REQUEST_HIDDEN_DATA_PATH") {
    const hiddenPath = join(caseRoot, "hidden-data.json");
    writeJson(hiddenPath, { hidden: true });
    descriptor.input_bindings.adapter_input = bound(hiddenPath);
  }
  if (negative.mutation === "RESPONSE_FORMAT_BYTES_AFTER_TASK_BINDING") {
    const responsePath = join(caseRoot, "response-format.json");
    const response = cloneJson(join(
      REPOSITORY_ROOT,
      "evaluation-harness/datasets/p1-representative-task-dataset-v1/shared/response-format.json",
    ));
    response.p1_125_tamper = true;
    writeJson(responsePath, response);
    descriptor.input_bindings.response_format = bound(responsePath);
  }
  writeJson(descriptorPathForCase, descriptor);

  const request = baseRequest({
    caseId: negative.case_id,
    adapterId: baseAdapter,
    repetitionId: 1,
    configurationPath: configPath,
    descriptor: descriptorPathForCase,
    taskPath,
    environmentPath: envPath,
    outputRoot,
    mode: "NEGATIVE",
    reasonCode: negative.reason_code,
    preExecution: negative.stage === "PRE_EXECUTION",
  });
  if (negative.mutation === "INPUT_PATH_ESCAPE") {
    request.task_spec.path = "../p1-129-input-path-escape.json";
  }
  if (negative.mutation === "NONREGULAR_INPUT") {
    const nonregularInput = join(caseRoot, "nonregular-task-spec");
    createDirectory(nonregularInput);
    request.task_spec.path = nonregularInput;
  }
  if (negative.mutation === "DESCRIPTOR_BYTES_AFTER_EXPECTED_IDENTITY") {
    request.expected_descriptor_identity = identity(baseDescriptorBytes);
  }
  if (negative.mutation === "TASK_SPEC_UNKNOWN_KEY") {
    taskPath = copyJsonForCase(assets.taskPath, join(caseRoot, "task-spec.json"));
    const value = cloneJson(taskPath);
    value.p1_125_unknown = true;
    writeFileSync(taskPath, canonicalBytes(value));
    request.task_spec = bound(taskPath);
  }
  if (negative.mutation === "ENVIRONMENT_UNKNOWN_KEY") {
    const value = cloneJson(envPath);
    value.p1_125_unknown = true;
    writeFileSync(envPath, canonicalBytes(value));
    request.environment_snapshot = bound(envPath);
  }
  if (negative.mutation === "CONFIGURATION_UNKNOWN_KEY") {
    const value = cloneJson(configPath);
    value.p1_125_unknown = true;
    writeFileSync(configPath, canonicalBytes(value));
    request.system_configuration = bound(configPath);
  }
  if (negative.mutation === "TASK_SPEC_BYTES_AFTER_BOUND_IDENTITY") {
    taskPath = copyJsonForCase(assets.taskPath, join(caseRoot, "task-spec.json"));
    request.task_spec = bound(taskPath);
    const value = cloneJson(taskPath);
    value.issue.text = `${value.issue.text} tampered`;
    writeFileSync(taskPath, canonicalBytes(value));
  }
  if (negative.mutation === "TASK_ID_UNKNOWN") {
    taskPath = copyJsonForCase(assets.taskPath, join(caseRoot, "task-spec.json"));
    const value = cloneJson(taskPath);
    value.task_id = "SL-P1-REP-999-UNDECLARED";
    writeFileSync(taskPath, canonicalBytes(value));
    request.task_spec = bound(taskPath);
  }
  if (negative.mutation === "TASK_SPEC_PATH_COPY") {
    taskPath = copyJsonForCase(assets.taskPath, join(caseRoot, "task-spec.json"));
    request.task_spec = bound(taskPath);
  }
  if (negative.mutation === "CLEANUP_REQUEST_POINTS_TO_NONOWNED_FIXTURE") {
    const nonowned = join(caseRoot, "nonowned-preserve.txt");
    writeCreateOnce(nonowned, Buffer.from("PRESERVE\n", "utf8"));
    request.nonowned_fixture = bound(nonowned);
  }
  const effectMap = {
    REQUEST_EFFECT_NETWORK: "network",
    REQUEST_EFFECT_PROVIDER: "provider",
    REQUEST_EFFECT_SECRET: "secret",
    REQUEST_EFFECT_REMOTE: "remote",
    REQUEST_EFFECT_PRODUCTION: "production",
    REQUEST_EFFECT_PUBLIC: "public",
  };
  if (effectMap[negative.mutation]) {
    request.requested_effects[effectMap[negative.mutation]] = true;
  }

  if (negative.mutation === "OUTPUT_ROOT_IS_SYMLINK") {
    const target = join(caseRoot, "safe-symlink-target");
    createDirectory(target);
    symlinkSync(target, outputRoot);
  }
  if (negative.mutation === "OUTPUT_ROOT_ANCESTOR_IS_SYMLINK") {
    const target = join(caseRoot, "safe-ancestor-target");
    createDirectory(target);
    const ancestor = join(caseRoot, "output-ancestor-link");
    symlinkSync(target, ancestor);
    outputRoot = join(ancestor, "worker-output");
    request.output_root = outputRoot;
    request.target_sentinel_path = join(outputRoot, "target-executed");
  }
  if (negative.mutation === "OUTPUT_ROOT_IS_PREEXISTING_FILE") {
    writeCreateOnce(outputRoot, Buffer.from("PREEXISTING\n", "utf8"));
  }
  if (negative.mutation === "OUTPUT_ROOT_IS_PREEXISTING_DIRECTORY") {
    createDirectory(outputRoot);
  }

  const requestPath = join(caseRoot, "request.json");
  writeJson(requestPath, request);
  const beforeNonowned = request.nonowned_fixture ? readFileSync(request.nonowned_fixture.path) : null;
  const result = runWorker(workerEntry, requestPath, outputRoot);
  assert(result.exitCode === 2, "NEGATIVE_FALSE_ACCEPT", negative.case_id);
  const expectedTargetCount = negative.stage === "TARGET_EXECUTION" ? 1 : 0;
  assert(
    result.value.status === "REJECTED" &&
      result.value.reason_code === negative.reason_code &&
      result.value.target_execution_count === expectedTargetCount &&
      result.value.external_effects.network === false &&
      result.value.cleanup.nonowned_paths_touched === 0,
    "NEGATIVE_FALSE_ACCEPT",
    `${negative.case_id}: ${canonicalJson(result.value)}`,
  );
  assert(
    existsSync(request.target_sentinel_path) === (expectedTargetCount === 1),
    "NEGATIVE_EXECUTION_STAGE_MISMATCH",
    negative.case_id,
  );
  if (request.nonowned_fixture) {
    assert(readFileSync(request.nonowned_fixture.path).equals(beforeNonowned), "NEGATIVE_NONOWNED_RESIDUAL", negative.case_id);
  }
  return {
    case_id: negative.case_id,
    expected_reason_code: negative.reason_code,
    observed_reason_code: result.value.reason_code,
    stage: negative.stage,
    rejected: true,
    target_execution_count: result.value.target_execution_count,
    target_sentinel_absent: !existsSync(request.target_sentinel_path),
    nonowned_residuals: 0,
    external_effects: result.value.external_effects,
    request: bound(requestPath),
  };
}

function runPostExecutionNegative(negative, positive, qualityRoot) {
  const root = join(qualityRoot, "negative", negative.case_id);
  cpSync(positive.outputRoot, root, { recursive: true, errorOnExist: true, force: false });
  const originalInventory = positive.inventory;
  if (negative.mutation === "ADD_UNDECLARED_OUTPUT_ENTRY") {
    writeCreateOnce(join(root, "unexpected-entry.bin"), Buffer.from("UNDECLARED\n", "utf8"));
  } else if (negative.mutation === "RUN_RECORD_TASK_ID_TAMPER") {
    const relativePath = relative(positive.outputRoot, positive.runRecordFile.path);
    const path = join(root, relativePath);
    const value = cloneJson(path);
    value.task_id = "TAMPERED-TASK";
    writeFileSync(path, canonicalBytes(value));
  } else if (negative.mutation === "RUN_RECORD_CONFIGURATION_ID_TAMPER") {
    const relativePath = relative(positive.outputRoot, positive.runRecordFile.path);
    const path = join(root, relativePath);
    const value = cloneJson(path);
    value.system_configuration_id = "TAMPERED-CONFIG";
    writeFileSync(path, canonicalBytes(value));
  } else if (negative.mutation === "TRACE_RUN_ID_TAMPER") {
    const relativePath = relative(positive.outputRoot, positive.traceFile.path);
    const path = join(root, relativePath);
    const lines = readFileSync(path, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    lines[0].run_id = "TAMPERED-RUN";
    writeFileSync(path, Buffer.from(`${lines.map(canonicalJson).join("\n")}\n`, "utf8"));
  } else if (negative.mutation === "COMMAND_LEDGER_IDENTITY_TAMPER") {
    const candidates = inventory(root).filter((entry) => /command.*ledger|ledger.*command/i.test(entry.path));
    assert(candidates.length >= 1, "POST_NEGATIVE_FIXTURE_UNAVAILABLE", negative.case_id);
    const path = join(root, candidates[0].path);
    writeFileSync(path, Buffer.concat([readFileSync(path), Buffer.from("TAMPER\n")]));
  } else if (negative.mutation === "REMOVE_DECLARED_OUTPUT_ENTRY") {
    unlinkSync(join(root, "stable-projection.json"));
  } else if (negative.mutation === "TRACE_EVENT_DUPLICATE") {
    const relativePath = relative(positive.outputRoot, positive.traceFile.path);
    const path = join(root, relativePath);
    const lines = readFileSync(path, "utf8").trim().split("\n");
    writeFileSync(path, Buffer.from(`${[lines[0], lines[0], ...lines.slice(1)].join("\n")}\n`, "utf8"));
  } else if (negative.mutation === "ADAPTER_RESULT_TERMINAL_TAMPER") {
    const path = join(root, "adapter-result.json");
    const value = cloneJson(path);
    value.terminal_status = "failed";
    writeFileSync(path, canonicalBytes(value));
  }
  let observedReason = null;
  try {
    verifyOutputSnapshot(root, positive, originalInventory);
  } catch (error) {
    if (error instanceof QualityNonPass) observedReason = error.reason;
    else throw error;
  }
  assert(observedReason !== null, "NEGATIVE_FALSE_ACCEPT", negative.case_id);
  assert(observedReason === negative.reason_code, "NEGATIVE_REASON_MISMATCH", `${negative.case_id}: ${observedReason}`);
  return {
    case_id: negative.case_id,
    expected_reason_code: negative.reason_code,
    observed_reason_code: observedReason,
    stage: negative.stage,
    rejected: true,
    target_execution_count: 1,
    target_sentinel_absent: false,
    nonowned_residuals: 0,
    external_effects: { ...FALSE_EFFECTS },
    physical_mutated_root: root,
  };
}

function parseArgs(argv) {
  if (argv.length !== 4 || argv[0] !== "--worker-entry" || argv[2] !== "--output-root") {
    fail("CLI_INVALID", "Usage: run-matrix.mjs --worker-entry ABS --output-root ABSENT_ABS");
  }
  const workerEntry = argv[1];
  const outputRoot = argv[3];
  assert(isAbsolute(workerEntry) && resolve(workerEntry) === workerEntry, "CLI_INVALID");
  assert(isAbsolute(outputRoot) && resolve(outputRoot) === outputRoot, "CLI_INVALID");
  return { workerEntry, outputRoot };
}

export function runQualityMatrix({ workerEntry, outputRoot }) {
  assert(
    DATASET_MANIFEST.task_count === 6
      && DATASET_MANIFEST.tasks.length === 6
      && PROGRAM_SET.task_count === 6
      && PROGRAM_SET.programs.length === 6,
    "CLOSED_TASK_SET_INVALID",
  );
  assert(existsSync(workerEntry) && statSync(workerEntry).isFile() && !lstatSync(workerEntry).isSymbolicLink(), "WORKER_ENTRY_INVALID");
  for (const path of Object.values(DESCRIPTOR_BY_ADAPTER)) {
    assert(existsSync(join(REPOSITORY_ROOT, path)), "WORKER_DESCRIPTOR_MISSING", path);
  }
  createDirectory(outputRoot);
  createDirectory(join(outputRoot, "positive"));
  createDirectory(join(outputRoot, "negative"));
  const positives = [];
  for (const taskEntry of DATASET_MANIFEST.tasks) {
    const taskRoot = join(outputRoot, "positive", taskEntry.task_id);
    createDirectory(taskRoot);
    for (const [profileCase, configRelative] of Object.entries(CONFIG_BY_CASE)) {
      const adapterId = profileCase.slice(0, 2);
      const repetitionId = profileCase.endsWith("_A") ? 1 : 2;
      const caseId = `${taskEntry.task_id}-${profileCase}`;
      const caseRoot = join(taskRoot, profileCase);
      createDirectory(caseRoot);
      const assets = materializeTaskAssets({ taskEntry, adapterId, caseRoot });
      const workerOutput = join(caseRoot, "worker-output");
      const request = baseRequest({
        caseId,
        adapterId,
        repetitionId,
        configurationPath: join(FIXTURE_ROOT, configRelative),
        descriptor: assets.descriptorPath,
        taskPath: assets.taskPath,
        environmentPath: assets.environmentPath,
        outputRoot: workerOutput,
        mode: "POSITIVE",
        reasonCode: "PASS",
        preExecution: false,
      });
      const requestPath = join(caseRoot, "request.json");
      writeJson(requestPath, request);
      const result = runWorker(workerEntry, requestPath, workerOutput);
      positives.push(validatePositiveOutput(result, request, workerOutput));
    }
  }

  const pairs = {};
  for (const taskEntry of DATASET_MANIFEST.tasks) {
    for (const adapterId of ["B0", "B1", "B2"]) {
      const pair = positives.filter((entry) => (
        entry.request.adapter_id === adapterId
          && JSON.parse(readFileSync(entry.request.task_spec.path, "utf8")).task_id === taskEntry.task_id
      ));
      assert(pair.length === 2, "STABLE_PAIR_INVALID", `${taskEntry.task_id}:${adapterId}`);
      const left = stableComparable(pair[0].projectionFile.bytes);
      const right = stableComparable(pair[1].projectionFile.bytes);
      assert(left.equals(right), "STABLE_PAIR_INVALID", `${taskEntry.task_id}:${adapterId}`);
      pairs[`${taskEntry.task_id}:${adapterId}`] = {
        byte_equal: true,
        projection_sha256: sha256(left),
      };
    }
  }

  const catalog = JSON.parse(readFileSync(join(FIXTURE_ROOT, "negative-cases.json"), "utf8"));
  const negativeResults = [];
  for (const negative of catalog.cases.filter((entry) => ["PRE_EXECUTION", "TARGET_EXECUTION"].includes(entry.stage))) {
    negativeResults.push(materializeNegative({
      negative,
      workerEntry,
      qualityRoot: outputRoot,
      baseAdapter: negative.adapter_id ?? "B0",
    }));
  }
  const primary = positives.find((entry) => entry.request.adapter_id === "B0");
  for (const negative of catalog.cases.filter((entry) => entry.stage === "POST_EXECUTION")) {
    negativeResults.push(runPostExecutionNegative(negative, primary, outputRoot));
  }

  assert(negativeResults.length === catalog.cases.length, "NEGATIVE_MATRIX_INCOMPLETE");
  assert(negativeResults.every((entry) => entry.rejected), "NEGATIVE_FALSE_ACCEPT");
  assert(negativeResults.every((entry) => isDeepStrictEqual(entry.external_effects, FALSE_EFFECTS)), "NEGATIVE_EXTERNAL_EFFECT");
  const summary = {
    schema_version: "p1-125-quality-formal-verdict/v1",
    task_id: "AIOS-P1-125_EXACT_SIX_TASK_PARAMETERIZED_ADAPTER_CONVERGENCE",
    status: "PASS",
    dataset_manifest_sha256: sha256(readFileSync(join(DATASET_ROOT, "dataset-manifest.json"))),
    program_set_sha256: sha256(readFileSync(join(FIXTURE_ROOT, "b1-program-set.json"))),
    accepted_task_count: DATASET_MANIFEST.tasks.length,
    positive_runs: positives.length,
    distinct_positive_run_roots: new Set(positives.map((entry) => entry.outputRoot)).size,
    exact_stable_pairs: 18,
    stable_pairs: pairs,
    b1_exact_rollbacks: positives.filter((entry) => entry.request.adapter_id === "B1").length,
    b2_real_repository_analysis_scan_children: positives.filter((entry) => entry.request.adapter_id === "B2").length,
    negative_cases: negativeResults.length,
    false_accepts: 0,
    pre_execution_rejections: negativeResults.filter((entry) => entry.stage === "PRE_EXECUTION").length,
    post_execution_rejections: negativeResults.filter((entry) => entry.stage === "POST_EXECUTION").length,
    pre_execution_target_executions: negativeResults
      .filter((entry) => entry.stage === "PRE_EXECUTION")
      .reduce((sum, entry) => sum + entry.target_execution_count, 0),
    nonowned_residuals: negativeResults.reduce((sum, entry) => sum + entry.nonowned_residuals, 0),
    external_effects: { ...FALSE_EFFECTS },
    output_root: outputRoot,
    claim_boundary: "EXACT_SIX_TASK_PARAMETERIZED_OFFLINE_ADAPTER_CONVERGENCE_ONLY",
  };
  writeJson(join(outputRoot, "quality-formal-summary.json"), summary);
  writeJson(join(outputRoot, "negative-results.json"), {
    schema_version: "p1-125-quality-negative-results/v1",
    results: negativeResults,
  });
  return summary;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = runQualityMatrix(args);
    process.stdout.write(`${canonicalJson(result)}\n`);
  } catch (error) {
    process.stdout.write(`${canonicalJson({
      schema_version: "p1-125-quality-formal-verdict/v1",
      task_id: "AIOS-P1-125_EXACT_SIX_TASK_PARAMETERIZED_ADAPTER_CONVERGENCE",
      status: "NON_PASS",
      reason_code: error instanceof QualityNonPass ? error.reason : "UNCAUGHT_EXCEPTION",
      error: `${error.name}: ${error.message}`,
      external_effects: FALSE_EFFECTS,
    })}\n`);
    process.exit(1);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

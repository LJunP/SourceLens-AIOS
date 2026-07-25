#!/usr/bin/env node

import {
  closeSync,
  constants as fsConstants,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
} from "node:fs";
import {
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from "node:path";
import { fileURLToPath } from "node:url";

import {
  P117QualityNonPass,
  assert,
  canonicalJsonBytes,
  exactKeys,
  identityOf,
  parseCanonicalJson,
  parseFrozenJson,
  readAbsoluteBoundFile,
  readBoundFile,
  sameJson,
  validateIdentity,
} from "./core.mjs";
import { loadSafeDisclosure } from "./disclosure.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPOSITORY_ROOT = resolve(HERE, "../../..");
export const FIXTURE_ROOT =
  "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline";
const TASK_IDS = Object.freeze([
  "SL-P1-REP-001-RANGE-NORMALIZATION",
  "SL-P1-REP-002-CONFIG-VALIDATION",
  "SL-P1-REP-003-SAFE-PATH-JOIN",
  "SL-P1-REP-004-COMMAND-RESULT-MAPPING",
  "SL-P1-REP-005-PROFILE-DISPLAY-NAME",
  "SL-P1-REP-006-DEDUPE-REFACTOR",
]);
const SYSTEMS = Object.freeze(["B0", "B1", "B2"]);
const VARIANTS = Object.freeze(["A", "B"]);
const MODES = Object.freeze({
  B0: "ISSUE_ONLY_SAFE_PROBLEM_STATEMENT_AND_FINITE_OPERATIONS",
  B1: "SAFE_PROBLEM_OPERATIONS_AND_QUALITY_FROZEN_SAFE_TOOL_FACTS",
  B2: "SAFE_PROBLEM_OPERATIONS_AND_NONCONTENT_ACCEPTED_SCANNER_METRICS",
});
const SYSTEM_CAPS = Object.freeze({
  B0: { provider_requests_exact: 1, automatic_retries: 0, input_tokens_reserved: 12000, max_output_tokens: 2048 },
  B1: { provider_requests_exact: 1, automatic_retries: 0, input_tokens_reserved: 12000, max_output_tokens: 2048 },
  B2: { provider_requests_exact: 1, automatic_retries: 0, input_tokens_reserved: 12000, max_output_tokens: 2048 },
});
const REQUIRED_PREREG_ARTIFACT_KEYS = Object.freeze([
  "matrix_plan",
  "safe_disclosures",
  "response_schema",
  "response_safe_schema",
  "b0_descriptor",
  "b1_descriptor",
  "b2_descriptor",
  "evaluation_oracle",
  "formal_run_contract",
  "negative_cases",
  "p2_context_preregistration",
  "independent_evaluator",
  "validator_core",
  "disclosure_validator",
  "preflight_validator",
  "validator_entry",
  "validator_self_test",
  "environment_snapshot_rep001",
  "environment_snapshot_rep002",
  "environment_snapshot_rep003",
  "environment_snapshot_rep004",
  "environment_snapshot_rep005",
  "environment_snapshot_rep006",
]);
const REQUIRED_CANONICAL_AUTHORITY_KEYS = Object.freeze([
  "truth",
  "task_contract",
  "evaluation_protocol",
  "baseline_adapter_contract",
]);
const REQUIRED_EXTERNAL_AUTHORITY_KEYS = Object.freeze([
  "founder_route_packet",
  "direct_entry_correction_packet",
  "p1_116_correction_manifest",
  "p1_116_cto_review",
  "p1_116_security_review",
  "p1_116_quality_review",
  "p1_117_task_authority",
]);
let runtimeIdentityCache = null;

function matrixBinding() {
  const path = `${FIXTURE_ROOT}/matrix-plan.json`;
  const bytes = readFileSync(resolve(REPOSITORY_ROOT, path));
  return { path, ...identityOf(bytes) };
}

export function loadMatrix(repositoryRoot = REPOSITORY_ROOT, binding = matrixBinding()) {
  const file = readBoundFile(repositoryRoot, binding, "MATRIX_IDENTITY_MISMATCH");
  const matrix = parseFrozenJson(file.bytes, "MATRIX_SCHEMA_INVALID");
  return { matrix, binding };
}

function readRuntimeIdentityOnce(path) {
  if (runtimeIdentityCache !== null) return structuredClone(runtimeIdentityCache);
  assert(
    path === process.execPath
      && path === "/usr/local/bin/node"
      && realpathSync(path) === path,
    "NODE_EXECUTABLE_IDENTITY_MISMATCH",
  );
  const before = lstatSync(path);
  assert(
    before.isFile() && !before.isSymbolicLink() && before.nlink === 1,
    "NODE_EXECUTABLE_IDENTITY_MISMATCH",
  );
  const descriptor = openSync(
    path,
    fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
  );
  try {
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.nlink === 1,
      "NODE_EXECUTABLE_IDENTITY_MISMATCH",
    );
    const bytes = readFileSync(descriptor);
    const after = lstatSync(path);
    assert(
      after.isFile()
        && after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && after.mtimeMs === opened.mtimeMs,
      "NODE_EXECUTABLE_IDENTITY_MISMATCH",
    );
    runtimeIdentityCache = {
      path,
      ...identityOf(bytes),
      type: "REGULAR_FILE",
      dev: String(opened.dev),
      ino: String(opened.ino),
      uid: opened.uid,
      gid: opened.gid,
      mode: opened.mode & 0o7777,
    };
    return structuredClone(runtimeIdentityCache);
  } finally {
    closeSync(descriptor);
  }
}

function sourceTemplateRecords(repositoryRoot, rootPath) {
  assert(
    typeof rootPath === "string"
      && rootPath.length > 0
      && !isAbsolute(rootPath)
      && !rootPath.split("/").includes(".."),
    "SOURCE_TEMPLATE_IDENTITY_MISMATCH",
  );
  const root = resolve(repositoryRoot, rootPath);
  const rel = relative(repositoryRoot, root);
  assert(
    rel !== ""
      && rel !== ".."
      && !rel.startsWith(`..${sep}`)
      && !isAbsolute(rel)
      && realpathSync(root) === root,
    "SOURCE_TEMPLATE_IDENTITY_MISMATCH",
  );
  const records = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))) {
      const absolute = join(directory, entry.name);
      const stat = lstatSync(absolute);
      assert(!stat.isSymbolicLink(), "SOURCE_TEMPLATE_IDENTITY_MISMATCH");
      if (stat.isDirectory()) {
        visit(absolute);
      } else {
        assert(
          stat.isFile() && stat.nlink === 1,
          "SOURCE_TEMPLATE_IDENTITY_MISMATCH",
        );
        const bytes = readFileSync(absolute);
        records.push({
          path: relative(root, absolute).split(sep).join("/"),
          ...identityOf(bytes),
        });
      }
    }
  };
  visit(root);
  return records;
}

export function validateSnapshotAlias(snapshot, taskSpec, binding) {
  assert(
    snapshot.task_id === binding.task_id
      && snapshot.snapshot_id_alias === taskSpec.environment_snapshot_ref
      && snapshot.snapshot_id_alias
        === "ENV-SOURCELENS-P1-REP-NODE20-STDLIB-1"
      && snapshot.snapshot_id_alias_disclosure
        === "ALL_SIX_ACCEPTED_TASKS_SHARE_THIS_REFERENCE_STRING_EXACT_FILE_BYTES_ARE_AUTHORITATIVE"
      && snapshot.authoritative_identity === "EXACT_FILE_SHA256_AND_BYTE_LENGTH"
      && sameJson(snapshot.task_spec, binding.task_spec),
    "ENVIRONMENT_SNAPSHOT_TASK_BINDING_MISMATCH",
  );
}

export function validateEnvironmentSnapshot({
  repositoryRoot,
  matrix,
  binding,
  taskSpec,
  datasetManifest,
  index,
}) {
  const loaded = readBoundFile(
    repositoryRoot,
    binding.environment_snapshot,
    "ENVIRONMENT_SNAPSHOT_IDENTITY_MISMATCH",
  );
  const snapshot = parseFrozenJson(
    loaded.bytes,
    "ENVIRONMENT_SNAPSHOT_SCHEMA_INVALID",
  );
  exactKeys(
    snapshot,
    [
      "schema_version",
      "task_id",
      "snapshot_id_alias",
      "snapshot_id_alias_disclosure",
      "authoritative_identity",
      "task_spec",
      "dataset",
      "repository",
      "source_template",
      "runtime",
      "network_policy",
    ],
    "ENVIRONMENT_SNAPSHOT_SCHEMA_INVALID",
  );
  assert(
    snapshot.schema_version === "p1-117-task-environment-snapshot/v1",
    "ENVIRONMENT_SNAPSHOT_TASK_BINDING_MISMATCH",
  );
  validateSnapshotAlias(snapshot, taskSpec, binding);
  const datasetEntry = datasetManifest.tasks[index];
  exactKeys(
    binding.dataset_task_binding,
    [
      "dataset_manifest",
      "task_entry_index",
      "task_id",
      "base_commit",
      "tree_hash",
    ],
    "DATASET_TASK_BINDING_MISMATCH",
  );
  assert(
    sameJson(binding.dataset_task_binding.dataset_manifest, matrix.dataset_manifest)
      && binding.dataset_task_binding.task_entry_index === index
      && binding.dataset_task_binding.task_id === datasetEntry.task_id
      && binding.dataset_task_binding.base_commit === datasetEntry.base_commit
      && binding.dataset_task_binding.tree_hash === datasetEntry.tree_hash
      && snapshot.dataset.dataset_id === datasetManifest.dataset_id
      && snapshot.dataset.dataset_version === datasetManifest.dataset_version
      && sameJson(snapshot.dataset.manifest, matrix.dataset_manifest)
      && snapshot.dataset.task_entry_index === index
      && snapshot.dataset.split === datasetEntry.split
      && snapshot.dataset.archetype === datasetEntry.archetype
      && snapshot.dataset.assertion_id === datasetEntry.assertion_id,
    "DATASET_TASK_BINDING_MISMATCH",
  );
  assert(
    sameJson(snapshot.repository, taskSpec.repository)
      && snapshot.repository.identity
        === `sourcelens-fixture://p1-representative-tasks/${binding.task_id}@1.0.0`
      && snapshot.repository.base_commit === datasetEntry.base_commit
      && snapshot.repository.tree_hash === datasetEntry.tree_hash
      && snapshot.repository.dirty_state_policy === "clean_immutable_base",
    "ENVIRONMENT_SNAPSHOT_TASK_BINDING_MISMATCH",
  );
  const sourceRecords = sourceTemplateRecords(
    repositoryRoot,
    snapshot.source_template.root_path,
  );
  const sourceManifestIdentity = identityOf(canonicalJsonBytes(sourceRecords));
  assert(
    sameJson(sourceRecords, snapshot.source_template.files)
      && snapshot.source_template.manifest.file_count === sourceRecords.length
      && snapshot.source_template.manifest.sha256 === sourceManifestIdentity.sha256
      && snapshot.source_template.manifest.byte_length
        === sourceManifestIdentity.byte_length
      && sameJson(binding.source_template_binding, {
        root_path: snapshot.source_template.root_path,
        manifest_sha256: sourceManifestIdentity.sha256,
        manifest_byte_length: sourceManifestIdentity.byte_length,
        file_count: sourceRecords.length,
      }),
    "SOURCE_TEMPLATE_IDENTITY_MISMATCH",
  );
  assert(
    sameJson(
      snapshot.runtime.node_executable,
      readRuntimeIdentityOnce(snapshot.runtime.node_executable?.path),
    )
      && snapshot.runtime.node_version === process.version
      && snapshot.runtime.platform === process.platform
      && snapshot.runtime.architecture === process.arch
      && snapshot.runtime.standard_library_only === true
      && snapshot.runtime.locale === "C"
      && snapshot.runtime.timezone === "UTC",
    "NODE_EXECUTABLE_IDENTITY_MISMATCH",
  );
  assert(
    sameJson(snapshot.network_policy, {
      task_local_execution: "DENY_ALL",
      allowed_hosts: [],
      provider_transport: "OUTSIDE_TASK_SNAPSHOT_GATED_SEPARATELY",
    }),
    "SNAPSHOT_NETWORK_POLICY_INVALID",
  );
  return snapshot;
}

function validateTaskBindings(repositoryRoot, matrix) {
  assert(Array.isArray(matrix.task_bindings) && matrix.task_bindings.length === 6, "TASK_BINDING_POPULATION_MISMATCH");
  const datasetManifest = parseFrozenJson(
    readBoundFile(
      repositoryRoot,
      matrix.dataset_manifest,
      "DATASET_IDENTITY_MISMATCH",
    ).bytes,
    "DATASET_IDENTITY_MISMATCH",
  );
  assert(
    datasetManifest.dataset_id === "SOURCELENS-P1-REPRESENTATIVE-TASKS"
      && datasetManifest.dataset_version === "1.0.0"
      && Array.isArray(datasetManifest.tasks)
      && datasetManifest.tasks.length === 6,
    "DATASET_IDENTITY_MISMATCH",
  );
  const byTask = new Map();
  for (const [index, binding] of matrix.task_bindings.entries()) {
    exactKeys(
      binding,
      [
        "task_id",
        "task_spec",
        "environment_snapshot",
        "dataset_task_binding",
        "source_template_binding",
        "finite_operation_ids",
      ],
      "TASK_BINDING_SCHEMA_INVALID",
    );
    assert(binding.task_id === TASK_IDS[index] && !byTask.has(binding.task_id), "TASK_BINDING_ORDER_MISMATCH");
    const file = readBoundFile(repositoryRoot, binding.task_spec, "TASKSPEC_IDENTITY_MISMATCH");
    const spec = parseFrozenJson(file.bytes, "TASKSPEC_SCHEMA_INVALID");
    assert(spec.task_id === binding.task_id, "TASKSPEC_IDENTITY_MISMATCH");
    validateEnvironmentSnapshot({
      repositoryRoot,
      matrix,
      binding,
      taskSpec: spec,
      datasetManifest,
      index,
    });
    assert(Array.isArray(binding.finite_operation_ids) && binding.finite_operation_ids.length === 3, "FINITE_OPERATION_CATALOG_MISMATCH");
    byTask.set(binding.task_id, binding);
  }
  return byTask;
}

function validateSystemBindings(matrix) {
  assert(Array.isArray(matrix.system_bindings) && matrix.system_bindings.length === 3, "SYSTEM_BINDING_POPULATION_MISMATCH");
  const bySystem = new Map();
  for (const [index, binding] of matrix.system_bindings.entries()) {
    exactKeys(
      binding,
      ["system", "wrapper_path", "configuration_path_rule", "disclosure_mode", "per_run_caps"],
      "SYSTEM_BINDING_SCHEMA_INVALID",
    );
    assert(binding.system === SYSTEMS[index], "SYSTEM_BINDING_ORDER_MISMATCH");
    assert(binding.disclosure_mode === MODES[binding.system], "SYSTEM_DISCLOSURE_MODE_MISMATCH");
    assert(sameJson(binding.per_run_caps, SYSTEM_CAPS[binding.system]), "PROVIDER_CAP_SEMANTICS_MISMATCH");
    bySystem.set(binding.system, binding);
  }
  return bySystem;
}

export function validateConfiguration(value, entry, matrix) {
  exactKeys(
    value,
    [
      "schema_version", "configuration_id", "run_id", "task_id", "system",
      "variant", "model_ref", "finite_operation_ids", "disclosure_mode",
      "response_schema", "provider_requests_exact", "automatic_retries",
      "input_tokens_reserved", "max_output_tokens", "temperature",
      "endpoint_policy", "external_effects",
    ],
    "SYSTEM_CONFIGURATION_SCHEMA_INVALID",
  );
  assert(
    value.schema_version === "p1-117-system-configuration/v1"
      && value.run_id === entry.run_id
      && value.task_id === entry.task_id
      && value.system === entry.system
      && value.variant === entry.variant
      && value.model_ref === "gpt-5.6-luna"
      && sameJson(value.finite_operation_ids, entry.finite_operation_ids)
      && value.disclosure_mode === MODES[entry.system]
      && sameJson(value.response_schema, matrix.response_schema)
      && value.temperature === (entry.variant === "A" ? 0 : 0.2),
    "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
  );
  assert(value.provider_requests_exact === 1, "PROVIDER_REQUEST_CAP_EXCEEDED");
  assert(value.automatic_retries === 0, "AUTOMATIC_RETRY_FORBIDDEN");
  assert(
    Number.isSafeInteger(value.input_tokens_reserved)
      && value.input_tokens_reserved >= 1
      && value.input_tokens_reserved <= 12000,
    "INPUT_TOKEN_CAP_EXCEEDED",
  );
  assert(
    Number.isSafeInteger(value.max_output_tokens)
      && value.max_output_tokens >= 1
      && value.max_output_tokens <= 2048,
    "OUTPUT_TOKEN_CAP_EXCEEDED",
  );
  assert(
    sameJson(value.endpoint_policy, {
      scheme: "http",
      host: "127.0.0.1",
      port: 8787,
      path: "/v1/chat/completions",
      follow_redirects: false,
      use_proxy: false,
      dns_resolution: false,
      fallback_endpoint_allowed: false,
    }),
    value.endpoint_policy?.host === "127.0.0.1"
      ? "TRANSPORT_POLICY_INVALID"
      : "LOOPBACK_ENDPOINT_REQUIRED",
  );
  assert(
    sameJson(value.external_effects, {
      network: true,
      provider: true,
      secret: true,
      remote: false,
      production: false,
      public: false,
    }),
    "EXTERNAL_EFFECT_PROFILE_INVALID",
  );
  return value;
}

export function validateP2Preregistration(value) {
  exactKeys(
    value.budget,
    [
      "status",
      "task_count",
      "system_count",
      "repetitions_per_task_system",
      "scheduled_runs",
      "provider_requests_max",
      "automatic_retries",
      "input_tokens_max",
      "output_tokens_max",
      "currency",
      "max_spend",
    ],
    "P2_PREREGISTRATION_BUDGET_INVALID",
  );
  assert(
    value.schema_version === "p1-117-p2-context-preregistration/v1"
      && value.status === "FROZEN_OFFLINE_NO_P2_ENTRY"
      && value.budget.status === "PROPOSED_NOT_AUTHORIZED"
      && value.budget.task_count === 6
      && value.budget.system_count === 2
      && value.budget.repetitions_per_task_system === 2
      && value.budget.scheduled_runs === 24
      && value.budget.provider_requests_max === 24
      && value.budget.automatic_retries === 0
      && value.budget.input_tokens_max === 288000
      && value.budget.output_tokens_max === 49152
      && value.budget.currency === "USD"
      && value.budget.max_spend === 25
      && value.authorization_boundary?.p2_entry_authorized === false
      && value.authorization_boundary?.provider_use_authorized_by_this_artifact
        === false
      && value.authorization_boundary?.implementation_authorized_by_this_artifact
        === false,
    "P2_PREREGISTRATION_BUDGET_INVALID",
  );
  return value;
}

export function validateFreezeBoundaryState({
  preregistrationPresent,
  preregistrationIdentityMatches,
  executableReceiptPresent,
  executableIdentitiesMatch,
}) {
  assert(preregistrationPresent === true, "PREREGISTRATION_MISSING");
  assert(preregistrationIdentityMatches === true, "PREREGISTRATION_IDENTITY_MISMATCH");
  assert(executableReceiptPresent === true, "EXECUTABLE_FREEZE_RECEIPT_MISSING");
  assert(executableIdentitiesMatch === true, "EXECUTABLE_IDENTITY_MISMATCH");
  return true;
}

export function validatePreregistrationMutation({ resultAwareMutation }) {
  assert(resultAwareMutation === false, "PREREGISTRATION_MUTATION_FORBIDDEN");
  return true;
}

export function validateMatrix(repositoryRoot, matrix) {
  assert(matrix.schema_version === "p1-117-matrix-plan/v1", "MATRIX_SCHEMA_INVALID");
  assert(matrix.population?.scheduled_runs === 36, "MATRIX_POPULATION_MISMATCH");
  readBoundFile(repositoryRoot, matrix.dataset_manifest, "DATASET_IDENTITY_MISMATCH");
  readBoundFile(repositoryRoot, matrix.safe_disclosures, "SAFE_DISCLOSURE_IDENTITY_MISMATCH");
  readBoundFile(repositoryRoot, matrix.response_schema, "RESPONSE_SCHEMA_IDENTITY_MISMATCH");
  readBoundFile(repositoryRoot, matrix.accepted_scanner_binding, "SCANNER_BINDING_IDENTITY_MISMATCH");
  const taskBindings = validateTaskBindings(repositoryRoot, matrix);
  const systemBindings = validateSystemBindings(matrix);
  assert(Array.isArray(matrix.schedule) && matrix.schedule.length === 36, "MATRIX_POPULATION_MISMATCH");
  const runIds = new Set();
  const entryIds = new Set();
  let slot = 0;
  for (const taskId of TASK_IDS) {
    for (const system of SYSTEMS) {
      for (const variant of VARIANTS) {
        slot += 1;
        const entry = matrix.schedule[slot - 1];
        exactKeys(
          entry,
          [
            "slot", "entry_id", "run_id", "task_id", "task_spec", "system",
            "variant", "repetition_id", "safe_disclosure",
            "safe_disclosure_task_index", "safe_disclosure_mode",
            "finite_operation_ids", "adapter_descriptor", "executable",
            "system_configuration",
            "accepted_scanner_binding",
          ],
          "MATRIX_ENTRY_SCHEMA_INVALID",
        );
        assert(
          entry.slot === slot
            && entry.task_id === taskId
            && entry.system === system
            && entry.variant === variant
            && entry.repetition_id === 1,
          "MATRIX_ORDER_MISMATCH",
        );
        assert(!runIds.has(entry.run_id) && !entryIds.has(entry.entry_id), "MATRIX_DUPLICATE");
        runIds.add(entry.run_id);
        entryIds.add(entry.entry_id);
        const taskBinding = taskBindings.get(taskId);
        assert(sameJson(entry.task_spec, taskBinding.task_spec), "TASKSPEC_IDENTITY_MISMATCH");
        validateIdentity(entry.safe_disclosure, "SAFE_DISCLOSURE_IDENTITY_MISMATCH");
        assert(sameJson(entry.safe_disclosure, matrix.safe_disclosures), "SAFE_DISCLOSURE_IDENTITY_MISMATCH");
        assert(entry.safe_disclosure_task_index === TASK_IDS.indexOf(taskId), "SAFE_DISCLOSURE_TASK_MISMATCH");
        assert(entry.safe_disclosure_mode === MODES[system], "SYSTEM_DISCLOSURE_MODE_MISMATCH");
        assert(sameJson(entry.finite_operation_ids, taskBinding.finite_operation_ids), "FINITE_OPERATION_CATALOG_MISMATCH");
        validateIdentity(entry.adapter_descriptor, "ADAPTER_DESCRIPTOR_IDENTITY_MISMATCH");
        validateIdentity(entry.executable, "EXECUTABLE_IDENTITY_MISMATCH");
        validateIdentity(entry.system_configuration, "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH");
        assert(entry.executable.path === systemBindings.get(system).wrapper_path, "EXECUTABLE_IDENTITY_MISMATCH");
        assert(
          entry.system_configuration.path.endsWith(`/${entry.run_id.toLowerCase()}.json`),
          "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
        );
        const descriptor = parseFrozenJson(
          readBoundFile(
            repositoryRoot,
            entry.adapter_descriptor,
            "ADAPTER_DESCRIPTOR_IDENTITY_MISMATCH",
          ).bytes,
          "ADAPTER_DESCRIPTOR_SCHEMA_INVALID",
        );
        assert(
          descriptor.schema_version === "p1-117-system-descriptor/v1"
            && descriptor.system === system
            && descriptor.wrapper_path === entry.executable.path
            && descriptor.disclosure_mode === MODES[system]
            && descriptor.provider_requests_per_run === 1
            && descriptor.automatic_retries === 0
            && descriptor.source_bytes_to_provider === false,
          "ADAPTER_DESCRIPTOR_IDENTITY_MISMATCH",
        );
        readBoundFile(repositoryRoot, entry.executable, "EXECUTABLE_IDENTITY_MISMATCH");
        const configuration = parseFrozenJson(
          readBoundFile(
            repositoryRoot,
            entry.system_configuration,
            "SYSTEM_CONFIGURATION_IDENTITY_MISMATCH",
          ).bytes,
          "SYSTEM_CONFIGURATION_SCHEMA_INVALID",
        );
        validateConfiguration(configuration, entry, matrix);
        if (system === "B2") {
          assert(
            sameJson(entry.accepted_scanner_binding, matrix.accepted_scanner_binding),
            "SCANNER_BINDING_IDENTITY_MISMATCH",
          );
        } else {
          assert(entry.accepted_scanner_binding === null, "SCANNER_BINDING_IDENTITY_MISMATCH");
        }
        loadSafeDisclosure(repositoryRoot, matrix, entry);
      }
    }
  }
  assert(
    sameJson(matrix.predeclared_aggregate_budget, {
      provider_requests_exact: 36,
      automatic_retries: 0,
      input_tokens_reserved: 432000,
      output_tokens_reserved: 73728,
      founder_provider_requests_ceiling: 60,
      founder_input_tokens_ceiling: 500000,
      founder_output_tokens_ceiling: 100000,
      currency: "USD",
      max_spend: 25,
      unknown_cost_amount: null,
    }),
    "PROVIDER_CAP_SEMANTICS_MISMATCH",
  );
  return { taskBindings, systemBindings };
}

export function validateExecutableFreezeReceipt(
  repositoryRoot,
  matrix,
  receipt,
  matrixPlanBinding,
  preregistrationBinding,
) {
  exactKeys(
    receipt,
    [
      "schema_version", "status", "frozen_at", "matrix_plan",
      "preregistration", "artifacts", "pre_freeze_effects",
    ],
    "EXECUTABLE_FREEZE_RECEIPT_INVALID",
  );
  assert(
    receipt.schema_version === "p1-117-executable-identity-freeze-receipt/v1"
      && receipt.status === "FROZEN_BEFORE_SECRET_OR_PROVIDER"
      && typeof receipt.frozen_at === "string"
      && !Number.isNaN(Date.parse(receipt.frozen_at))
      && sameJson(receipt.matrix_plan, matrixPlanBinding)
      && sameJson(receipt.preregistration, preregistrationBinding),
    "EXECUTABLE_FREEZE_RECEIPT_INVALID",
  );
  assert(receipt.pre_freeze_effects?.secret_reads === 0, "SECRET_READ_BEFORE_FREEZE");
  assert(receipt.pre_freeze_effects?.provider_requests === 0, "PROVIDER_REQUEST_BEFORE_FREEZE");
  assert(receipt.pre_freeze_effects?.network_connections === 0, "NETWORK_BEFORE_FREEZE");
  const required = new Map();
  for (const entry of matrix.schedule) {
    required.set(entry.executable.path, entry.executable);
    required.set(entry.system_configuration.path, entry.system_configuration);
  }
  for (const path of [
    "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/runtime.mjs",
    "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/provider-client.mjs",
    "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/preflight.mjs",
    "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/local-execution.mjs",
    "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/scanner.mjs",
    "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/systems/common.mjs",
    "evaluation-harness/recording/p1-117-clean-room-empirical-baseline/trace.mjs",
    "evaluation-harness/replay/p1-117-clean-room-empirical-baseline/replay.mjs",
    "evaluation-harness/harness/p1-117-clean-room-empirical-baseline/self-test.mjs",
  ]) {
    const matches = receipt.artifacts.filter((entry) => entry.path === path);
    assert(matches.length === 1, "EXECUTABLE_FREEZE_RECEIPT_INVALID");
    required.set(path, matches[0]);
  }
  const receiptPaths = new Set(receipt.artifacts.map((entry) => entry.path));
  assert(
    receiptPaths.size === receipt.artifacts.length
      && receiptPaths.size === required.size,
    "EXECUTABLE_FREEZE_RECEIPT_INVALID",
  );
  for (const [path, binding] of required) {
    const matches = receipt.artifacts.filter((entry) => entry.path === path);
    assert(matches.length === 1 && sameJson(matches[0], binding), "EXECUTABLE_IDENTITY_MISMATCH");
    readBoundFile(repositoryRoot, binding, "EXECUTABLE_IDENTITY_MISMATCH");
  }
  return true;
}

export function validatePreregistrationBundle({
  repositoryRoot = REPOSITORY_ROOT,
  preregistrationBinding,
  executableReceipt = null,
}) {
  const preregFile = readBoundFile(
    repositoryRoot,
    preregistrationBinding,
    "PREREGISTRATION_IDENTITY_MISMATCH",
  );
  const preregistration = parseFrozenJson(
    preregFile.bytes,
    "PREREGISTRATION_SCHEMA_INVALID",
  );
  exactKeys(
    preregistration.frozen_artifacts,
    REQUIRED_PREREG_ARTIFACT_KEYS,
    "PREREGISTRATION_SCHEMA_INVALID",
  );
  exactKeys(
    preregistration.canonical_authorities,
    REQUIRED_CANONICAL_AUTHORITY_KEYS,
    "PREREGISTRATION_SCHEMA_INVALID",
  );
  for (const binding of Object.values(preregistration.canonical_authorities)) {
    readBoundFile(repositoryRoot, binding, "CANONICAL_AUTHORITY_IDENTITY_MISMATCH");
  }
  exactKeys(
    preregistration.external_authorities,
    REQUIRED_EXTERNAL_AUTHORITY_KEYS,
    "PREREGISTRATION_SCHEMA_INVALID",
  );
  for (const binding of Object.values(preregistration.external_authorities)) {
    readAbsoluteBoundFile(binding, "EXTERNAL_AUTHORITY_IDENTITY_MISMATCH");
  }
  assert(
    preregistration.schema_version === "p1-117-preregistration/v1"
      && preregistration.status === "FROZEN_BEFORE_SECRET_OR_PROVIDER"
      && preregistration.freeze_boundary?.secret_reads_before_freeze === 0
      && preregistration.freeze_boundary?.provider_requests_before_freeze === 0
      && preregistration.freeze_boundary?.mutation_after_freeze === "FORBIDDEN",
    "PREREGISTRATION_SCHEMA_INVALID",
  );
  const matrixFile = readBoundFile(
    repositoryRoot,
    preregistration.frozen_artifacts.matrix_plan,
    "MATRIX_IDENTITY_MISMATCH",
  );
  const matrix = parseFrozenJson(matrixFile.bytes, "MATRIX_SCHEMA_INVALID");
  validateMatrix(repositoryRoot, matrix);
  for (const [name, binding] of Object.entries(preregistration.frozen_artifacts)) {
    if (name === "matrix_plan") continue;
    readBoundFile(repositoryRoot, binding, `${name.toUpperCase()}_IDENTITY_MISMATCH`);
  }
  validateP2Preregistration(parseFrozenJson(
    readBoundFile(
      repositoryRoot,
      preregistration.frozen_artifacts.p2_context_preregistration,
      "P2_CONTEXT_PREREGISTRATION_IDENTITY_MISMATCH",
    ).bytes,
    "P2_PREREGISTRATION_BUDGET_INVALID",
  ));
  if (executableReceipt === null) {
    assert(
      preregistration.executable_identity_boundary
        === "RECEIPT_REQUIRED_AFTER_IMPLEMENTATION_BEFORE_SECRET_OR_PROVIDER",
      "EXECUTABLE_FREEZE_RECEIPT_MISSING",
    );
  } else {
    validateExecutableFreezeReceipt(
      repositoryRoot,
      matrix,
      executableReceipt,
      preregistration.frozen_artifacts.matrix_plan,
      preregistrationBinding,
    );
  }
  return { preregistration, matrix };
}

function cli(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(
      ["--repository-root", "--preregistration", "--executable-receipt"].includes(key)
        && typeof value === "string"
        && !(key in result),
      "CLI_ARGUMENT_MISMATCH",
    );
    result[key] = value;
  }
  assert(result["--repository-root"] && result["--preregistration"], "CLI_ARGUMENT_MISMATCH");
  return result;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const args = cli(process.argv.slice(2));
    const repositoryRoot = resolve(args["--repository-root"]);
    const preregistrationPath = resolve(args["--preregistration"]);
    const preregistrationBytes = readFileSync(preregistrationPath);
    const relativePath = preregistrationPath.slice(repositoryRoot.length + 1);
    const executableReceipt = args["--executable-receipt"]
      ? parseFrozenJson(readFileSync(resolve(args["--executable-receipt"])), "EXECUTABLE_FREEZE_RECEIPT_INVALID")
      : null;
    validatePreregistrationBundle({
      repositoryRoot,
      preregistrationBinding: { path: relativePath, ...identityOf(preregistrationBytes) },
      executableReceipt,
    });
    process.stdout.write(`${JSON.stringify({status: "PASS", scheduled_runs: 36, provider_requests: 0, secret_reads: 0})}\n`);
  } catch (error) {
    const reasonCode = error instanceof P117QualityNonPass
      ? error.reasonCode
      : "UNEXPECTED_VALIDATOR_ERROR";
    process.stdout.write(`${JSON.stringify({status: "NON_PASS", reason_code: reasonCode, provider_requests: 0, secret_reads: 0})}\n`);
    process.exitCode = 2;
  }
}

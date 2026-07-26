import {
  existsSync,
  lstatSync,
  readFileSync,
  realpathSync,
  statSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { validate } from "../../evaluator/schema-validator.mjs";
import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  assertContained,
  assertExistingPathWithoutSymlink,
  canonicalJson,
  exactKeys,
  fail,
  parseJsonBytes,
  sha256,
} from "./core.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPOSITORY_ROOT = resolve(HERE, "../../..");
export const SCHEMA_ROOT = join(REPOSITORY_ROOT, "docs/aios/schemas");

export const REQUEST_KEYS = Object.freeze([
  "schema_version",
  "request_id",
  "case_id",
  "mode",
  "adapter_id",
  "repetition_id",
  "task_spec",
  "environment_snapshot",
  "system_configuration",
  "execution_descriptor",
  "expected_descriptor_identity",
  "output_root",
  "target_sentinel_path",
  "nonowned_fixture",
  "requested_effects",
  "expected_outcome",
]);

export const DESCRIPTOR_KEYS = Object.freeze([
  "schema_version",
  "descriptor_id",
  "adapter_id",
  "adapter_version",
  "executable",
  "argv",
  "working_directory",
  "timeout_seconds",
  "expected_exit_codes",
  "input_bindings",
  "limits",
  "allowed_tool_classes",
  "forbidden_features",
  "requested_effects",
  "output_policy",
]);

const BOUND_INPUT_KEYS = Object.freeze(["path", "sha256", "byte_length"]);
const IDENTITY_KEYS = Object.freeze(["sha256", "byte_length"]);
const EXPECTED_OUTCOME_KEYS = Object.freeze(["status", "reason_code", "pre_execution"]);
const EXECUTABLE_KEYS = Object.freeze(["path", "realpath", "sha256", "byte_length", "type"]);
const LIMIT_KEYS = Object.freeze(["max_model_tokens", "max_tool_calls", "max_cost_usd"]);
const OUTPUT_POLICY_KEYS = Object.freeze([
  "atomic_unique_owned_root",
  "preexisting_target_allowed",
  "symlink_component_allowed",
  "nonowned_cleanup_allowed",
]);
const INPUT_BINDING_KEYS = Object.freeze({
  B0: Object.freeze(["adapter_input", "response_format"]),
  B1: Object.freeze(["adapter_input", "response_format"]),
  B2: Object.freeze([
    "adapter_input",
    "b2_source_manifest",
    "response_format",
    "task_source_program",
  ]),
});
const EXTERNAL_EFFECT_KEYS = Object.freeze(Object.keys(FALSE_EXTERNAL_EFFECTS));
const SCHEMAS = Object.freeze({
  task: "task-spec.schema.json",
  environment: "environment-snapshot.schema.json",
  configuration: "system-configuration.schema.json",
  runRecord: "run-record.schema.json",
});
const DESCRIPTOR_ARGV = Object.freeze([
  "/usr/local/bin/node",
  "EXECUTABLE",
  "--request",
  "EXECUTION_REQUEST",
  "--run-root",
  "OUTPUT_ROOT",
  "--sentinel",
  "TARGET_SENTINEL",
]);
const ALLOWED_TOOL_CLASSES = Object.freeze({
  B0: [],
  B1: [
    "file_listing",
    "file_read",
    "lexical_search",
    "structured_patch",
    "verification_command",
  ],
  B2: ["repository_analysis.scan"],
});
const FORBIDDEN_FEATURES = Object.freeze({
  B0: [
    "repository_tools",
    "search",
    "terminal",
    "graph",
    "memory",
    "iteration",
    "execution_feedback",
    "hidden_data",
    "network",
  ],
  B1: [
    "sourcelens_graph",
    "ranker",
    "memory",
    "additional_agent",
    "hidden_data",
    "network",
  ],
  B2: [
    "write",
    "egress",
    "remote",
    "hidden_data",
    "network",
  ],
});

function isFalseEffects(value) {
  return value !== null
    && typeof value === "object"
    && !Array.isArray(value)
    && canonicalJson(Object.keys(value).sort()) === canonicalJson([...EXTERNAL_EFFECT_KEYS].sort())
    && EXTERNAL_EFFECT_KEYS.every((key) => value[key] === false);
}

function verifyIdentityRecord(reference, label, root = REPOSITORY_ROOT) {
  exactKeys(reference, BOUND_INPUT_KEYS, `${label} identity`);
  assert(
    typeof reference.path === "string"
      && /^[0-9a-f]{64}$/.test(reference.sha256)
      && Number.isInteger(reference.byte_length)
      && reference.byte_length >= 0,
    "INPUT_IDENTITY_MISMATCH",
    `${label} identity is invalid`,
  );
  let path;
  if (isAbsolute(reference.path)) {
    path = resolve(reference.path);
  } else {
    path = assertContained(root, resolve(root, reference.path), `${label} path`);
  }
  try {
    assertExistingPathWithoutSymlink(path, `${label} path`);
  } catch {
    fail("INPUT_IDENTITY_MISMATCH", `${label} path is missing, escaped or symlinked`);
  }
  assert(statSync(path).isFile(), "INPUT_IDENTITY_MISMATCH", `${label} is not a regular file`);
  const bytes = readFileSync(path);
  assert(
    bytes.length === reference.byte_length && sha256(bytes) === reference.sha256,
    "INPUT_IDENTITY_MISMATCH",
    `${label} bytes differ from the bound identity`,
  );
  return { path: realpathSync(path), bytes, value: parseJsonBytes(bytes, label) };
}

function validateSchema(kind, value) {
  const schema = parseJsonBytes(readFileSync(join(SCHEMA_ROOT, SCHEMAS[kind])), `${kind} schema`);
  const errors = validate(value, schema);
  assert(errors.length === 0, "SCHEMA_INVALID", `${kind} schema invalid`, errors);
}

function validateRequestShape(request, cliOutputRoot) {
  exactKeys(request, REQUEST_KEYS, "worker request");
  assert(
    request.schema_version === "p1-125-worker-request/v1"
      && typeof request.request_id === "string"
      && request.request_id.length > 0
      && typeof request.case_id === "string"
      && request.case_id.length > 0
      && ["POSITIVE", "NEGATIVE"].includes(request.mode)
      && ["B0", "B1", "B2"].includes(request.adapter_id)
      && Number.isInteger(request.repetition_id)
      && request.repetition_id >= 1,
    "SCHEMA_INVALID",
    "worker request identity or enum is invalid",
  );
  for (const key of [
    "task_spec",
    "environment_snapshot",
    "system_configuration",
    "execution_descriptor",
  ]) {
    exactKeys(request[key], BOUND_INPUT_KEYS, `${key} request binding`);
  }
  exactKeys(request.expected_descriptor_identity, IDENTITY_KEYS, "expected descriptor identity");
  assert(
    /^[0-9a-f]{64}$/.test(request.expected_descriptor_identity.sha256)
      && Number.isInteger(request.expected_descriptor_identity.byte_length)
      && request.expected_descriptor_identity.byte_length >= 0,
    "DESCRIPTOR_IDENTITY_MISMATCH",
    "expected descriptor identity is invalid",
  );
  assert(
    typeof request.output_root === "string"
      && isAbsolute(request.output_root)
      && resolve(request.output_root) === resolve(cliOutputRoot),
    "OUTPUT_ROOT_INVALID",
    "request output root differs from the CLI output root",
  );
  assert(
    request.target_sentinel_path === null
      || (typeof request.target_sentinel_path === "string" && isAbsolute(request.target_sentinel_path)),
    "COMMAND_CONTRACT_INVALID",
    "target sentinel must be an absolute path or null",
  );
  if (request.target_sentinel_path !== null) {
    const rel = relative(resolve(request.output_root), resolve(request.target_sentinel_path));
    assert(
      rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`),
      "COMMAND_CONTRACT_INVALID",
      "target sentinel escapes the declared output root",
    );
  }
  assert(
    request.nonowned_fixture === null
      || (request.nonowned_fixture !== null && typeof request.nonowned_fixture === "object" && !Array.isArray(request.nonowned_fixture)),
    "SCHEMA_INVALID",
    "nonowned fixture must be a bound input or null",
  );
  exactKeys(request.requested_effects, EXTERNAL_EFFECT_KEYS, "request effects");
  exactKeys(request.expected_outcome, EXPECTED_OUTCOME_KEYS, "expected outcome");
  assert(
    ["PASS", "REJECTED"].includes(request.expected_outcome.status)
      && typeof request.expected_outcome.reason_code === "string"
      && typeof request.expected_outcome.pre_execution === "boolean",
    "SCHEMA_INVALID",
    "expected outcome record is invalid",
  );
}

function validateDescriptorShape(descriptor, request) {
  exactKeys(descriptor, DESCRIPTOR_KEYS, "execution descriptor");
  assert(
    descriptor.schema_version === "p1-125-execution-descriptor/v1"
      && typeof descriptor.descriptor_id === "string"
      && descriptor.descriptor_id.length > 0
      && descriptor.adapter_id === request.adapter_id
      && typeof descriptor.adapter_version === "string"
      && descriptor.adapter_version.length > 0,
    "SCHEMA_INVALID",
    "descriptor identity is invalid",
  );
  exactKeys(descriptor.executable, EXECUTABLE_KEYS, "descriptor executable");
  exactKeys(descriptor.limits, LIMIT_KEYS, "descriptor limits");
  exactKeys(descriptor.output_policy, OUTPUT_POLICY_KEYS, "descriptor output policy");
  exactKeys(
    descriptor.input_bindings,
    INPUT_BINDING_KEYS[request.adapter_id],
    "descriptor input bindings",
  );
  for (const key of INPUT_BINDING_KEYS[request.adapter_id]) {
    exactKeys(descriptor.input_bindings[key], BOUND_INPUT_KEYS, `${key} descriptor binding`);
  }
  assert(
    Array.isArray(descriptor.allowed_tool_classes)
      && descriptor.allowed_tool_classes.every((item) => typeof item === "string")
      && new Set(descriptor.allowed_tool_classes).size === descriptor.allowed_tool_classes.length
      && Array.isArray(descriptor.forbidden_features)
      && descriptor.forbidden_features.every((item) => typeof item === "string")
      && new Set(descriptor.forbidden_features).size === descriptor.forbidden_features.length,
    "SCHEMA_INVALID",
    "descriptor tool or forbidden-feature arrays are invalid",
  );
  exactKeys(descriptor.requested_effects, EXTERNAL_EFFECT_KEYS, "descriptor effects");
}

function validateExecutable(descriptor) {
  const executable = descriptor.executable;
  assert(
    typeof executable.path === "string"
      && !isAbsolute(executable.path)
      && typeof executable.realpath === "string"
      && executable.realpath === `REPOSITORY_ROOT/${executable.path}`
      && /^[0-9a-f]{64}$/.test(executable.sha256)
      && Number.isInteger(executable.byte_length)
      && executable.byte_length > 0
      && executable.type === "REGULAR_FILE",
    "EXECUTABLE_INVALID",
    "descriptor executable binding is invalid",
  );
  const path = resolve(REPOSITORY_ROOT, executable.path);
  try {
    assert(!lstatSync(path).isSymbolicLink(), "EXECUTABLE_INVALID", "descriptor executable is a symlink");
    assertExistingPathWithoutSymlink(path, "descriptor executable");
  } catch {
    fail("EXECUTABLE_INVALID", "descriptor executable is missing, escaped or symlinked");
  }
  const bytes = readFileSync(path);
  assert(
    statSync(path).isFile()
      && realpathSync(path) === path
      && bytes.length === executable.byte_length
      && sha256(bytes) === executable.sha256,
    "EXECUTABLE_INVALID",
    "descriptor executable physical identity mismatch",
  );
  return path;
}

function validateCommandContract(descriptor, request, task) {
  assert(
    Array.isArray(descriptor.argv)
      && descriptor.argv.length > 0
      && descriptor.argv.every((item) => typeof item === "string" && !item.includes("\0"))
      && canonicalJson(descriptor.argv) === canonicalJson(DESCRIPTOR_ARGV),
    "COMMAND_CONTRACT_INVALID",
    "descriptor argv differs from the finite command grammar",
  );
  assert(
    descriptor.working_directory === "REPOSITORY_ROOT",
    "COMMAND_CONTRACT_INVALID",
    "descriptor working directory differs from repository root",
  );
  assert(
    Number.isInteger(descriptor.timeout_seconds)
      && descriptor.timeout_seconds >= 1
      && descriptor.timeout_seconds <= task.budgets.wall_clock_seconds,
    "LIMIT_CONTRACT_INVALID",
    "descriptor timeout is invalid or exceeds the TaskSpec budget",
  );
  assert(
    Array.isArray(descriptor.expected_exit_codes)
      && canonicalJson(descriptor.expected_exit_codes) === canonicalJson([0]),
    "COMMAND_CONTRACT_INVALID",
    "descriptor expected-exit contract differs from the TaskSpec",
  );
  assert(
    request.target_sentinel_path !== null,
    "COMMAND_CONTRACT_INVALID",
    "target sentinel is required for an executable request",
  );
}

function validateDescriptorSemantics(descriptor, request, task) {
  assert(
    canonicalJson(descriptor.allowed_tool_classes)
      === canonicalJson(ALLOWED_TOOL_CLASSES[request.adapter_id]),
    "FORBIDDEN_TOOL",
    "descriptor tool classes exceed or differ from the adapter contract",
  );
  assert(
    canonicalJson(descriptor.forbidden_features)
      === canonicalJson(FORBIDDEN_FEATURES[request.adapter_id]),
    "HIDDEN_DATA_FORBIDDEN",
    "descriptor forbidden-feature boundary drifted",
  );
  assert(
    isFalseEffects(descriptor.requested_effects)
      && isFalseEffects(request.requested_effects),
    "EXTERNAL_EFFECT_FORBIDDEN",
    "an external effect was requested",
  );
  assert(
    Number.isInteger(descriptor.limits.max_model_tokens)
      && descriptor.limits.max_model_tokens >= 0
      && descriptor.limits.max_model_tokens <= task.budgets.max_model_tokens
      && Number.isInteger(descriptor.limits.max_tool_calls)
      && descriptor.limits.max_tool_calls >= 0
      && descriptor.limits.max_tool_calls <= task.budgets.max_tool_calls
      && typeof descriptor.limits.max_cost_usd === "number"
      && Number.isFinite(descriptor.limits.max_cost_usd)
      && descriptor.limits.max_cost_usd >= 0
      && descriptor.limits.max_cost_usd <= task.budgets.max_cost_usd,
    "LIMIT_CONTRACT_INVALID",
    "descriptor resource limits exceed the TaskSpec budget",
  );
  assert(
    descriptor.output_policy.atomic_unique_owned_root === true
      && descriptor.output_policy.preexisting_target_allowed === false
      && descriptor.output_policy.symlink_component_allowed === false
      && descriptor.output_policy.nonowned_cleanup_allowed === false,
    "OUTPUT_ROOT_INVALID",
    "descriptor output policy is not atomic, unique and process-owned",
  );
  const boundPaths = Object.values(descriptor.input_bindings).map((binding) => binding.path.toLowerCase());
  assert(
    boundPaths.every((path) => !/(^|[/_.-])(hidden|oracle)([/_.-]|$)/.test(path)
      && !path.endsWith("reference-solution.patch")
      && !path.endsWith("expected-result.json")),
    "HIDDEN_DATA_FORBIDDEN",
    "descriptor requests hidden or evaluator-owned data",
  );
}

function validateCrossContract({ task, environment, configuration, descriptor, responseFormat }) {
  const failures = [];
  const check = (condition, label) => {
    if (!condition) failures.push(label);
  };
  check(task.environment_snapshot_ref === environment.snapshot_id, "environment_snapshot_ref");
  check(task.repository.identity === environment.source.repository_identity, "repository identity");
  check(task.repository.base_commit === environment.source.base_commit, "base commit");
  check(task.repository.tree_hash === environment.source.tree_hash, "tree hash");
  check(environment.source.worktree_clean === true, "environment source clean");
  check(task.network_policy === environment.network.policy, "network policy");
  check(canonicalJson(task.allowed_network_hosts) === canonicalJson(environment.network.allowed_hosts), "network hosts");
  check(task.network_policy === "none" && task.allowed_network_hosts.length === 0, "offline task");
  check(environment.model.provider === "none-offline", "provider neutral environment");
  check(environment.environment_variables.secret_names_present.length === 0, "secret names");
  check(environment.secret_policy.values_retained === false, "secret values");
  check(configuration.adapter_id === descriptor.adapter_id, "adapter ID");
  check(configuration.adapter_version === descriptor.adapter_version, "adapter version");
  check(configuration.model_ref === environment.model.model_ref, "model ref");
  check(configuration.prompt_ref === environment.prompt_version, "prompt ref");
  check(configuration.policy_ref === environment.policy_version, "policy ref");
  check(configuration.response_format_ref === task.baseline_context.response_format_ref, "response format ref");
  const environmentTools = environment.tools.map((tool) => tool.tool_id);
  if (configuration.adapter_id === "B1") {
    check(
      task.allowed_tools.includes("local-node-test")
        && task.allowed_tools.includes("local-file-edit"),
      "TaskSpec finite local tool capability",
    );
  }
  check(configuration.enabled_tools.every((tool) => environmentTools.includes(tool)), "Environment tool allowlist");
  check(sha256(responseFormat.bytes) === task.baseline_context.response_format_sha256, "response format hash");
  if (configuration.adapter_id === "B0") {
    check(configuration.enabled_tools.length === 0, "B0 tools");
    check(configuration.loop_limit === 1, "B0 loop limit");
  }
  if (configuration.adapter_id === "B1") {
    check(configuration.feature_flags.sourcelens_graph === false, "B1 graph");
    check(configuration.feature_flags.ranker === false, "B1 ranker");
    check(configuration.feature_flags.memory === false, "B1 memory");
    check(configuration.feature_flags.additional_agent === false, "B1 additional Agent");
    check(configuration.feature_flags.network === false, "B1 network");
  }
  assert(failures.length === 0, "SCHEMA_INVALID", `cross-contract preflight failed: ${failures.join(", ")}`);
}

function validateBaselineContext(task) {
  const references = [
    ["baseline context", task.baseline_context.artifact_ref, task.baseline_context.sha256],
    ["response format", task.baseline_context.response_format_ref, task.baseline_context.response_format_sha256],
  ];
  const values = {};
  for (const [label, reference, expectedSha] of references) {
    assert(
      typeof reference === "string" && !isAbsolute(reference),
      "INPUT_IDENTITY_MISMATCH",
      `${label} reference must be repository-relative`,
    );
    const path = assertContained(REPOSITORY_ROOT, resolve(REPOSITORY_ROOT, reference), label);
    try {
      assertExistingPathWithoutSymlink(path, label);
    } catch {
      fail("INPUT_IDENTITY_MISMATCH", `${label} is missing, escaped or symlinked`);
    }
    const bytes = readFileSync(path);
    assert(sha256(bytes) === expectedSha, "INPUT_IDENTITY_MISMATCH", `${label} hash mismatch`);
    values[label] = { path, bytes };
  }
  return values;
}

export function loadAndPreflight(requestPath, cliOutputRoot) {
  let requestBytes;
  try {
    assert(isAbsolute(requestPath), "SCHEMA_INVALID", "request path must be absolute");
    assertExistingPathWithoutSymlink(requestPath, "worker request");
    assert(statSync(requestPath).isFile(), "SCHEMA_INVALID", "request must be a regular file");
    requestBytes = readFileSync(requestPath);
  } catch (error) {
    fail(error.code ?? "SCHEMA_INVALID", error.message);
  }
  if (requestBytes.includes(Buffer.from("\"nonowned_fixture\":{", "utf8"))) {
    fail("NONOWNED_CLEANUP_FORBIDDEN", "non-owned fixture cleanup is forbidden");
  }
  const request = parseJsonBytes(requestBytes, "worker request");
  validateRequestShape(request, cliOutputRoot);

  if (request.nonowned_fixture !== null) {
    verifyIdentityRecord(request.nonowned_fixture, "nonowned fixture", dirname(request.nonowned_fixture.path));
    fail("NONOWNED_CLEANUP_FORBIDDEN", "non-owned fixture cleanup is forbidden");
  }
  assert(isFalseEffects(request.requested_effects), "EXTERNAL_EFFECT_FORBIDDEN", "request effects are not all false");

  const descriptorRecord = verifyIdentityRecord(request.execution_descriptor, "execution descriptor");
  assert(
    descriptorRecord.bytes.length === request.expected_descriptor_identity.byte_length
      && sha256(descriptorRecord.bytes) === request.expected_descriptor_identity.sha256,
    "DESCRIPTOR_IDENTITY_MISMATCH",
    "descriptor differs from the independently expected identity",
  );
  const descriptor = descriptorRecord.value;
  validateDescriptorShape(descriptor, request);

  const taskRecord = verifyIdentityRecord(request.task_spec, "TaskSpec");
  const environmentRecord = verifyIdentityRecord(request.environment_snapshot, "EnvironmentSnapshot");
  const configurationRecord = verifyIdentityRecord(request.system_configuration, "SystemConfiguration");
  validateSchema("task", taskRecord.value);
  validateSchema("environment", environmentRecord.value);
  validateSchema("configuration", configurationRecord.value);
  const baseline = validateBaselineContext(taskRecord.value);

  const adapterInput = verifyIdentityRecord(descriptor.input_bindings.adapter_input, "adapter input");
  const auxiliaryInputs = Object.fromEntries(
    Object.entries(descriptor.input_bindings)
      .filter(([name]) => !["adapter_input", "response_format"].includes(name))
      .map(([name, binding]) => [name, verifyIdentityRecord(binding, name)]),
  );
  const responseFormat = verifyIdentityRecord(descriptor.input_bindings.response_format, "response format");
  assert(
    responseFormat.path === realpathSync(baseline["response format"].path)
      && responseFormat.bytes.equals(baseline["response format"].bytes),
    "INPUT_IDENTITY_MISMATCH",
    "descriptor response-format binding differs from TaskSpec",
  );

  validateDescriptorSemantics(descriptor, request, taskRecord.value);
  const executable = validateExecutable(descriptor);
  validateCommandContract(descriptor, request, taskRecord.value);
  validateCrossContract({
    task: taskRecord.value,
    environment: environmentRecord.value,
    configuration: configurationRecord.value,
    descriptor,
    responseFormat,
  });

  return {
    request,
    requestPath: realpathSync(requestPath),
    requestIdentity: {
      path: realpathSync(requestPath),
      sha256: sha256(requestBytes),
      byte_length: requestBytes.length,
    },
    descriptor,
    descriptorRecord,
    task: taskRecord,
    environment: environmentRecord,
    configuration: configurationRecord,
    adapterInput,
    auxiliaryInputs,
    responseFormat,
    executable,
  };
}

export function validateRunRecordSchema(runRecord) {
  validateSchema("runRecord", runRecord);
}

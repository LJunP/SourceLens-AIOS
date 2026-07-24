import {
  existsSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  statSync,
  writeFileSync,
  closeSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  assertContained,
  assertExistingPathWithoutSymlink,
  assertFalseEffects,
  assertRelativeArtifactPath,
  canonicalBytes,
  canonicalJson,
  exactKeys,
  parseJsonBytes,
  sha256,
} from "../../harness/p1-097-minimal-documented/core.mjs";

export const ADAPTER_VERSION = "p1-097-minimal-documented-v1";

const EXECUTION_REQUEST_KEYS = Object.freeze([
  "schema_version",
  "record_type",
  "run_id",
  "adapter_id",
  "repetition_id",
  "task_spec",
  "environment_snapshot",
  "system_configuration",
  "adapter_input",
  "auxiliary_inputs",
  "run_root",
  "sentinel_path",
  "limits",
  "external_effects",
]);

const IDENTITY_KEYS = Object.freeze(["path", "sha256", "byte_length"]);

export function loadExecutionRequest(path, expectedAdapter) {
  const request = parseJsonBytes(readFileSync(path), "adapter execution request");
  exactKeys(request, EXECUTION_REQUEST_KEYS, "adapter execution request");
  assert(
    request.schema_version === "1.0"
      && request.record_type === "p1_097_adapter_execution_request"
      && request.adapter_id === expectedAdapter
      && typeof request.run_id === "string"
      && request.run_id.length > 0
      && Number.isInteger(request.repetition_id)
      && request.repetition_id >= 1,
    "ADAPTER_REQUEST_REJECTED",
    "adapter execution request identity is invalid",
  );
  for (const key of ["task_spec", "environment_snapshot", "system_configuration", "adapter_input"]) {
    exactKeys(request[key], IDENTITY_KEYS, `${key} identity`);
    assert(
      typeof request[key].path === "string"
        && isAbsolute(request[key].path)
        && /^[0-9a-f]{64}$/.test(request[key].sha256)
        && Number.isInteger(request[key].byte_length)
        && request[key].byte_length >= 0,
      "ADAPTER_REQUEST_REJECTED",
      `${key} identity is invalid`,
    );
  }
  assert(
    request.auxiliary_inputs !== null
      && typeof request.auxiliary_inputs === "object"
      && !Array.isArray(request.auxiliary_inputs),
    "ADAPTER_REQUEST_REJECTED",
    "auxiliary inputs must be an object",
  );
  for (const [name, identity] of Object.entries(request.auxiliary_inputs)) {
    assert(/^[a-z][a-z0-9_]{1,63}$/.test(name), "ADAPTER_REQUEST_REJECTED", "auxiliary input name is invalid");
    exactKeys(identity, IDENTITY_KEYS, `${name} auxiliary identity`);
    assert(
      typeof identity.path === "string"
        && isAbsolute(identity.path)
        && /^[0-9a-f]{64}$/.test(identity.sha256)
        && Number.isInteger(identity.byte_length)
        && identity.byte_length >= 0,
      "ADAPTER_REQUEST_REJECTED",
      `${name} auxiliary input identity is invalid`,
    );
  }
  assert(
    typeof request.run_root === "string"
      && isAbsolute(request.run_root)
      && typeof request.sentinel_path === "string"
      && isAbsolute(request.sentinel_path),
    "ADAPTER_REQUEST_REJECTED",
    "run root or sentinel path is invalid",
  );
  const runRoot = assertExistingPathWithoutSymlink(request.run_root, "adapter run root");
  const sentinel = assertContained(runRoot, request.sentinel_path, "target execution sentinel");
  assert(!existsSync(sentinel), "TARGET_ALREADY_STARTED", "target execution sentinel already exists");
  exactKeys(request.limits, [
    "wall_clock_seconds",
    "max_model_tokens",
    "max_tool_calls",
    "max_cost_usd",
  ], "adapter limits");
  assert(
    Number.isInteger(request.limits.wall_clock_seconds)
      && request.limits.wall_clock_seconds >= 1
      && Number.isInteger(request.limits.max_model_tokens)
      && request.limits.max_model_tokens >= 0
      && Number.isInteger(request.limits.max_tool_calls)
      && request.limits.max_tool_calls >= 0
      && typeof request.limits.max_cost_usd === "number"
      && Number.isFinite(request.limits.max_cost_usd)
      && request.limits.max_cost_usd >= 0,
    "BUDGET_CONTRACT_REJECTED",
    "adapter limits are invalid",
  );
  assertFalseEffects(request.external_effects, "adapter external effects");
  return { request, runRoot, sentinel };
}

export function readBoundJson(identity, label) {
  const path = assertExistingPathWithoutSymlink(identity.path, label);
  assert(statSync(path).isFile(), "INPUT_IDENTITY_REJECTED", `${label} is not a regular file`);
  const bytes = readFileSync(path);
  assert(
    bytes.length === identity.byte_length && sha256(bytes) === identity.sha256,
    "INPUT_IDENTITY_REJECTED",
    `${label} identity mismatch`,
  );
  return { path, bytes, value: parseJsonBytes(bytes, label) };
}

export function markTargetStarted(request, sentinel, details = {}) {
  const value = {
    schema_version: "1.0",
    record_type: "p1_097_target_execution_sentinel",
    run_id: request.run_id,
    adapter_id: request.adapter_id,
    repetition_id: request.repetition_id,
    owner_pid: process.pid,
    details,
  };
  const bytes = canonicalBytes(value);
  let descriptor;
  try {
    descriptor = openSync(sentinel, "wx", 0o600);
    writeFileSync(descriptor, bytes);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  return { path: sentinel, sha256: sha256(bytes), byte_length: bytes.length };
}

export function decodeCanonicalBase64(value, label) {
  assert(
    typeof value === "string"
      && value.length % 4 === 0
      && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value),
    "INPUT_SCHEMA_REJECTED",
    `${label} is not canonical base64`,
  );
  const bytes = Buffer.from(value, "base64");
  assert(bytes.toString("base64") === value, "INPUT_SCHEMA_REJECTED", `${label} is not canonical base64`);
  return bytes;
}

export function createContainedDirectory(root, relativePath) {
  if (relativePath === "." || relativePath === "") return root;
  assertRelativeArtifactPath(relativePath, "directory path");
  const destination = assertContained(root, join(root, relativePath), relativePath);
  let current = root;
  for (const part of relative(root, destination).split(sep)) {
    current = join(current, part);
    if (!existsSync(current)) mkdirSync(current, { recursive: false, mode: 0o700 });
    assert(!lstatSync(current).isSymbolicLink() && statSync(current).isDirectory(), "SYMLINK_REJECTED", "directory is not real");
  }
  return destination;
}

export function writeContainedFileCreateOnce(root, relativePath, bytes, mode = 0o600) {
  assert(Buffer.isBuffer(bytes), "INPUT_SCHEMA_REJECTED", "file payload must be bytes");
  assertRelativeArtifactPath(relativePath, "file path");
  const destination = assertContained(root, join(root, relativePath), relativePath);
  const parentRelative = relative(root, dirname(destination));
  if (parentRelative !== "") createContainedDirectory(root, parentRelative);
  let descriptor;
  try {
    descriptor = openSync(destination, "wx", mode);
    writeFileSync(descriptor, bytes);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  return destination;
}

export function materializeManifest({ repositoryRoot, destinationRoot, manifest }) {
  assert(Array.isArray(manifest) && manifest.length > 0, "INPUT_SCHEMA_REJECTED", "source manifest must be non-empty");
  const seen = new Set();
  const receipt = [];
  for (const entry of manifest) {
    exactKeys(entry, ["path", "sha256", "byte_length", "mode"], "source manifest entry");
    assertRelativeArtifactPath(entry.path, "source manifest path");
    assert(!seen.has(entry.path), "INPUT_SCHEMA_REJECTED", "source manifest contains duplicate paths");
    seen.add(entry.path);
    assert(
      /^[0-9a-f]{64}$/.test(entry.sha256)
        && Number.isInteger(entry.byte_length)
        && entry.byte_length >= 0
        && [0o600, 0o644, 0o700, 0o755].includes(entry.mode),
      "INPUT_SCHEMA_REJECTED",
      "source manifest entry identity is invalid",
    );
    const source = assertContained(repositoryRoot, resolve(repositoryRoot, entry.path), entry.path);
    assertExistingPathWithoutSymlink(source, entry.path);
    const sourceBytes = readFileSync(source);
    assert(
      sourceBytes.length === entry.byte_length && sha256(sourceBytes) === entry.sha256,
      "INPUT_IDENTITY_REJECTED",
      `source manifest identity mismatch: ${entry.path}`,
    );
    const relativeSourcePath = entry.path.split("/source-template/").at(-1);
    assert(relativeSourcePath !== entry.path, "INPUT_SCHEMA_REJECTED", "source manifest path lacks source-template boundary");
    const destination = writeContainedFileCreateOnce(destinationRoot, relativeSourcePath, sourceBytes, entry.mode);
    receipt.push({
      source_path: entry.path,
      materialized_path: relativeSourcePath,
      sha256: entry.sha256,
      byte_length: entry.byte_length,
      mode: entry.mode,
      destination,
    });
  }
  return receipt;
}

export function verifyMaterializedManifest(root, receipt) {
  const observed = [];
  for (const entry of receipt) {
    const path = assertContained(root, join(root, entry.materialized_path), entry.materialized_path);
    assertExistingPathWithoutSymlink(path, entry.materialized_path);
    const bytes = readFileSync(path);
    observed.push({
      path: entry.materialized_path,
      sha256: sha256(bytes),
      byte_length: bytes.length,
      matches: bytes.length === entry.byte_length && sha256(bytes) === entry.sha256,
    });
  }
  return {
    exact: observed.every((entry) => entry.matches),
    files: observed,
  };
}

export function emit(value) {
  process.stdout.write(`${canonicalJson(value)}\n`);
}

export function parseEntryArguments(argv) {
  if (argv.length !== 6
      || argv[0] !== "--request"
      || argv[2] !== "--run-root"
      || argv[4] !== "--sentinel") {
    throw new Error("Usage: entry.mjs --request FILE --run-root DIR --sentinel FILE");
  }
  return {
    requestPath: argv[1],
    runRoot: argv[3],
    sentinelPath: argv[5],
  };
}

export function validateEntryPaths(argumentsValue, loaded) {
  assert(
    resolve(argumentsValue.runRoot) === loaded.runRoot
      && resolve(argumentsValue.sentinelPath) === loaded.sentinel,
    "COMMAND_DRIFT_REJECTED",
    "entry command paths drifted from bound request",
  );
}

export function normalizeAction(action) {
  return JSON.parse(canonicalJson(action));
}

export function commonResultBase({ request, task, configuration, actions, usage, targetSentinel }) {
  return {
    schema_version: "1.0",
    record_type: "p1_097_documented_adapter_result",
    run_id: request.run_id,
    task_id: task.task_id,
    adapter_id: request.adapter_id,
    adapter_version: ADAPTER_VERSION,
    system_configuration_id: configuration.configuration_id,
    repetition_id: request.repetition_id,
    terminal_status: "completed",
    stop_reason_code: "agent_complete",
    actions: actions.map(normalizeAction),
    usage,
    target_execution_sentinel: {
      sha256: targetSentinel.sha256,
      byte_length: targetSentinel.byte_length,
    },
    requested_external_effects: FALSE_EXTERNAL_EFFECTS,
    observed_external_effects: FALSE_EXTERNAL_EFFECTS,
  };
}

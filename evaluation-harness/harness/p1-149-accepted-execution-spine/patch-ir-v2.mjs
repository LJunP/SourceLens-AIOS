import { createHash } from "node:crypto";

export const PATCH_IR_SCHEMA = "SL-PATCH-IR/2";
export const COMPILER_VERSION = "SL-PATCH-IR-TRUSTED-COMPILER/2";
export const NORMALIZED_RESPONSE_SCHEMA = "p1-149-normalized-provider-response/v1";
export const MAX_OPERATIONS = 3;
export const MAX_TOTAL_POSTIMAGE_BYTES = 64 * 1024;

export class PatchIrV2NonPass extends Error {
  constructor(code, message) {
    super(message);
    this.name = "PatchIrV2NonPass";
    this.code = code;
  }
}

function reject(code, message) {
  throw new PatchIrV2NonPass(code, message);
}

function assert(condition, code, message) {
  if (!condition) reject(code, message);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonicalJson(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    assert(Number.isFinite(value), "IR_JSON_INVALID", "non-finite JSON number");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  assert(
    value !== null && typeof value === "object" && !Buffer.isBuffer(value),
    "IR_JSON_INVALID",
    "unsupported JSON value",
  );
  return `{${Object.keys(value).sort().map(
    (key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`,
  ).join(",")}}`;
}

function canonicalBytes(value) {
  return Buffer.from(`${canonicalJson(value)}\n`, "utf8");
}

function exactKeys(value, keys, label) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "IR_SCHEMA_INVALID",
    `${label} must be an object`,
  );
  assert(
    canonicalJson(Object.keys(value).sort()) === canonicalJson([...keys].sort()),
    "IR_SCHEMA_INVALID",
    `${label} key set is not closed`,
  );
}

function parseCanonical(bytes, label) {
  assert(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 128 * 1024, "IR_JSON_INVALID", `${label} size invalid`);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    reject("IR_JSON_INVALID", `${label} is not exact UTF-8`);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch (error) {
    reject("IR_JSON_INVALID", `${label} is not valid JSON: ${error.message}`);
  }
  assert(bytes.equals(canonicalBytes(value)), "IR_JSON_NOT_CANONICAL", `${label} is not canonical JSON`);
  return value;
}

function normalizedPath(path) {
  const parts = typeof path === "string" ? path.split("/") : [];
  return typeof path === "string"
    && path.length > 0
    && path.length <= 160
    && path.startsWith("src/")
    && !path.startsWith("/")
    && !path.includes("\\")
    && !path.includes("\0")
    && !parts.some((part) => part === "" || part === "." || part === "..")
    && !parts.some((part) => part === "test" || part === "tests")
    && !parts.at(-1).includes(".test.");
}

function identity(value, label) {
  exactKeys(value, ["kind", "sha256", "byte_length"], label);
  assert(value.kind === "REGULAR_FILE", "IR_PREIMAGE_INVALID", `${label}.kind invalid`);
  assert(/^[0-9a-f]{64}$/.test(value.sha256), "IR_PREIMAGE_INVALID", `${label}.sha256 invalid`);
  assert(Number.isInteger(value.byte_length) && value.byte_length >= 0, "IR_PREIMAGE_INVALID", `${label}.byte_length invalid`);
  return value;
}

function strictBase64(value, expectedLength, expectedSha) {
  assert(
    typeof value === "string"
      && value.length > 0
      && value.length % 4 === 0
      && /^[A-Za-z0-9+/]+={0,2}$/.test(value),
    "IR_POSTIMAGE_INVALID",
    "postimage base64 invalid",
  );
  const bytes = Buffer.from(value, "base64");
  assert(bytes.toString("base64") === value, "IR_POSTIMAGE_INVALID", "postimage base64 is not canonical");
  assert(
    bytes.length === expectedLength && sha256(bytes) === expectedSha,
    "IR_POSTIMAGE_INVALID",
    "postimage identity mismatch",
  );
  return bytes;
}

function cloneAndFreeze(value) {
  if (Array.isArray(value)) {
    const cloned = value.map(cloneAndFreeze);
    return Object.freeze(cloned);
  }
  if (value !== null && typeof value === "object") {
    const cloned = Object.fromEntries(Object.entries(value).map(
      ([key, child]) => [key, cloneAndFreeze(child)],
    ));
    return Object.freeze(cloned);
  }
  return value;
}

export function buildNormalizedProviderResponse({ responseId, taskId, patchIrBytes }) {
  assert(
    typeof responseId === "string" && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(responseId),
    "RESPONSE_SCHEMA_INVALID",
    "response id invalid",
  );
  assert(
    typeof taskId === "string" && /^SL-P1-REP-[0-9]{3}-[A-Z0-9-]+$/.test(taskId),
    "RESPONSE_SCHEMA_INVALID",
    "response task id invalid",
  );
  parseCanonical(patchIrBytes, "normalized response Patch IR");
  const content = patchIrBytes.toString("utf8");
  return canonicalBytes({
    schema_version: NORMALIZED_RESPONSE_SCHEMA,
    response_id: responseId,
    task_id: taskId,
    content_type: "application/vnd.sourcelens.patch-ir+json",
    content,
    content_sha256: sha256(patchIrBytes),
    content_byte_length: patchIrBytes.length,
  });
}

export function extractPatchIrFromNormalizedResponse(responseBytes) {
  const response = parseCanonical(responseBytes, "normalized Provider response");
  exactKeys(
    response,
    [
      "schema_version",
      "response_id",
      "task_id",
      "content_type",
      "content",
      "content_sha256",
      "content_byte_length",
    ],
    "normalized Provider response",
  );
  assert(response.schema_version === NORMALIZED_RESPONSE_SCHEMA, "RESPONSE_SCHEMA_INVALID", "response schema invalid");
  assert(
    typeof response.response_id === "string" && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(response.response_id),
    "RESPONSE_SCHEMA_INVALID",
    "response id invalid",
  );
  assert(
    typeof response.task_id === "string" && /^SL-P1-REP-[0-9]{3}-[A-Z0-9-]+$/.test(response.task_id),
    "RESPONSE_SCHEMA_INVALID",
    "response task id invalid",
  );
  assert(
    response.content_type === "application/vnd.sourcelens.patch-ir+json"
      && typeof response.content === "string",
    "RESPONSE_SCHEMA_INVALID",
    "response content contract invalid",
  );
  const patchIrBytes = Buffer.from(response.content, "utf8");
  assert(
    Number.isInteger(response.content_byte_length)
      && patchIrBytes.length === response.content_byte_length
      && /^[0-9a-f]{64}$/.test(response.content_sha256)
      && sha256(patchIrBytes) === response.content_sha256,
    "RESPONSE_CONTENT_IDENTITY_MISMATCH",
    "response content identity drifted",
  );
  parseCanonical(patchIrBytes, "response Patch IR");
  return { response, patchIrBytes };
}

function validateProfile(profile) {
  exactKeys(
    profile,
    [
      "task_id",
      "dataset_id",
      "dataset_version",
      "dataset_manifest_sha256",
      "base_commit",
      "base_tree",
      "task_spec_sha256",
      "existing_sources",
      "creatable_paths",
    ],
    "compiler task profile",
  );
  assert(
    typeof profile.task_id === "string"
      && /^SL-P1-REP-[0-9]{3}-[A-Z0-9-]+$/.test(profile.task_id),
    "COMPILER_PROFILE_INVALID",
    "profile task id invalid",
  );
  assert(
    profile.dataset_id === "SOURCELENS-P1-REPRESENTATIVE-TASKS"
      && profile.dataset_version === "1.0.0",
    "COMPILER_PROFILE_INVALID",
    "profile dataset identity invalid",
  );
  assert(
    /^[0-9a-f]{64}$/.test(profile.dataset_manifest_sha256)
      && /^[0-9a-f]{40}$/.test(profile.base_commit)
      && /^[0-9a-f]{40}$/.test(profile.base_tree)
      && /^[0-9a-f]{64}$/.test(profile.task_spec_sha256),
    "COMPILER_PROFILE_INVALID",
    "profile hash identity invalid",
  );
  assert(Array.isArray(profile.existing_sources) && profile.existing_sources.length >= 1, "COMPILER_PROFILE_INVALID", "source profile empty");
  assert(Array.isArray(profile.creatable_paths), "COMPILER_PROFILE_INVALID", "creatable path set invalid");
  const existing = new Map();
  for (const entry of profile.existing_sources) {
    exactKeys(entry, ["path", "sha256", "byte_length", "mode"], "compiler source profile");
    assert(normalizedPath(entry.path), "COMPILER_PROFILE_INVALID", "profile source path invalid");
    assert(entry.mode === "100644", "COMPILER_PROFILE_INVALID", "profile source mode invalid");
    assert(/^[0-9a-f]{64}$/.test(entry.sha256), "COMPILER_PROFILE_INVALID", "profile source SHA invalid");
    assert(Number.isInteger(entry.byte_length) && entry.byte_length >= 0, "COMPILER_PROFILE_INVALID", "profile source length invalid");
    assert(!existing.has(entry.path), "COMPILER_PROFILE_INVALID", "duplicate profile source path");
    existing.set(entry.path, entry);
  }
  const creatable = new Set();
  for (const path of profile.creatable_paths) {
    assert(normalizedPath(path), "COMPILER_PROFILE_INVALID", "creatable path invalid");
    assert(!existing.has(path) && !creatable.has(path), "COMPILER_PROFILE_INVALID", "creatable path overlaps profile");
    creatable.add(path);
  }
  return { existing, creatable };
}

export function compilePatchIrV2(patchIrBytes, profile) {
  const { existing, creatable } = validateProfile(profile);
  const ir = parseCanonical(patchIrBytes, "SL-PATCH-IR/2 proposal");
  exactKeys(ir, ["schema_version", "dataset", "task", "operations"], "SL-PATCH-IR/2");
  assert(ir.schema_version === PATCH_IR_SCHEMA, "IR_SCHEMA_INVALID", "Patch IR version invalid");
  exactKeys(ir.dataset, ["id", "version", "manifest_sha256"], "Patch IR dataset");
  exactKeys(ir.task, ["task_id", "base_commit", "base_tree", "task_spec_sha256"], "Patch IR task");
  assert(
    ir.dataset.id === profile.dataset_id
      && ir.dataset.version === profile.dataset_version
      && ir.dataset.manifest_sha256 === profile.dataset_manifest_sha256,
    "IR_DATASET_BINDING_MISMATCH",
    "Patch IR dataset binding drifted",
  );
  assert(
    ir.task.task_id === profile.task_id
      && ir.task.base_commit === profile.base_commit
      && ir.task.base_tree === profile.base_tree
      && ir.task.task_spec_sha256 === profile.task_spec_sha256,
    "IR_TASK_BINDING_MISMATCH",
    "Patch IR task binding drifted",
  );
  assert(
    Array.isArray(ir.operations)
      && ir.operations.length >= 1
      && ir.operations.length <= MAX_OPERATIONS,
    "IR_OPERATION_SET_INVALID",
    "Patch IR operation count invalid",
  );
  const paths = [];
  let totalPostimageBytes = 0;
  const planOperations = ir.operations.map((operation, index) => {
    exactKeys(operation, ["op", "path", "mode", "before", "postimage"], `Patch IR operation ${index}`);
    assert(
      operation.op === "REPLACE_REGULAR_FILE" || operation.op === "CREATE_REGULAR_FILE",
      "IR_OPERATION_INVALID",
      "unsupported Patch IR operation",
    );
    assert(normalizedPath(operation.path), "IR_PATH_REJECTED", "Patch IR target path invalid");
    assert(operation.mode === "100644", "IR_MODE_REJECTED", "Patch IR mode invalid");
    assert(!paths.includes(operation.path), "IR_OPERATION_SET_INVALID", "duplicate Patch IR target");
    paths.push(operation.path);
    if (operation.op === "REPLACE_REGULAR_FILE") {
      const expected = existing.get(operation.path);
      assert(expected, "IR_PATH_REJECTED", "replace target is outside accepted source profile");
      const before = identity(operation.before, "Patch IR replace preimage");
      assert(
        before.sha256 === expected.sha256 && before.byte_length === expected.byte_length,
        "IR_PREIMAGE_INVALID",
        "replace preimage does not equal accepted source identity",
      );
    } else {
      exactKeys(operation.before, ["kind"], "Patch IR create preimage");
      assert(operation.before.kind === "ABSENT", "IR_PREIMAGE_INVALID", "create preimage must be ABSENT");
      assert(creatable.has(operation.path), "IR_PATH_REJECTED", "create target is not in the closed task profile");
    }
    exactKeys(operation.postimage, ["base64", "sha256", "byte_length"], "Patch IR postimage");
    assert(
      /^[0-9a-f]{64}$/.test(operation.postimage.sha256)
        && Number.isInteger(operation.postimage.byte_length)
        && operation.postimage.byte_length > 0,
      "IR_POSTIMAGE_INVALID",
      "postimage identity invalid",
    );
    strictBase64(
      operation.postimage.base64,
      operation.postimage.byte_length,
      operation.postimage.sha256,
    );
    totalPostimageBytes += operation.postimage.byte_length;
    return cloneAndFreeze(operation);
  });
  assert(
    canonicalJson(paths) === canonicalJson([...paths].sort()),
    "IR_OPERATION_SET_INVALID",
    "Patch IR operations must be ordered by path",
  );
  assert(
    totalPostimageBytes <= MAX_TOTAL_POSTIMAGE_BYTES,
    "IR_POSTIMAGE_LIMIT_EXCEEDED",
    "Patch IR postimages exceed the total byte limit",
  );
  const plan = cloneAndFreeze({
    schema_version: "p1-149-compiler-plan/v1",
    compiler_version: COMPILER_VERSION,
    proposal_sha256: sha256(patchIrBytes),
    proposal_byte_length: patchIrBytes.length,
    task_id: profile.task_id,
    base_commit: profile.base_commit,
    base_tree: profile.base_tree,
    operations: planOperations,
  });
  return Object.freeze({
    status: "COMPILED",
    compiler_version: COMPILER_VERSION,
    proposal_sha256: sha256(patchIrBytes),
    proposal_byte_length: patchIrBytes.length,
    plan,
  });
}

export function compileNormalizedProviderResponse(responseBytes, profile) {
  const extracted = extractPatchIrFromNormalizedResponse(responseBytes);
  assert(extracted.response.task_id === profile.task_id, "RESPONSE_TASK_BINDING_MISMATCH", "response task id drifted");
  const compiled = compilePatchIrV2(extracted.patchIrBytes, profile);
  return Object.freeze({
    response: cloneAndFreeze(extracted.response),
    patch_ir_bytes: Buffer.from(extracted.patchIrBytes),
    compiled,
  });
}

export function patchIrBytes(value) {
  return canonicalBytes(value);
}

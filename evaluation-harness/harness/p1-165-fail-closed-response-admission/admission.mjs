import {
  closeSync,
  constants as fsConstants,
  existsSync,
  fchmodSync,
  fstatSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { createHash } from "node:crypto";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from "node:path";
import {
  assertOwnedRoot,
  containedPath,
} from "../p1-149-accepted-execution-spine/core.mjs";
import {
  EXECUTION_ARTIFACT_KEYS,
} from "../p1-149-accepted-execution-spine/execution.mjs";
import {
  AdmissionNonPass,
  TASK_ID,
  assertCritical,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  exactKeys,
  failCritical,
  isCriticalReasonCode,
  validateIdentity,
  validateJoin,
  validatePolicy,
  validateUsage,
} from "./contract.mjs";
import { validateRawObservation } from "./observer.mjs";
import {
  analyzeTransport,
  parseClosedTransportRecord,
} from "./transport.mjs";

const CLOSURE_KEYS = Object.freeze([
  "admission_receipt_identity",
  "adapter_control_identity",
  "admitted_response_identity",
  "b2_scan_proof_identity",
  "body_identity",
  "denominator_included",
  "failure_receipt_identity",
  "failure_stage",
  "join",
  "outcome",
  "outcome_reason",
  "p1_101_receipt_identities",
  "p1_149_artifact_identities",
  "request_record_identity",
  "schema_version",
  "task_id",
  "worker_success_fields_trusted",
]);
const ADMISSION_RECEIPT_KEYS = Object.freeze([
  "admitted_response",
  "body_identity",
  "context_record_identity",
  "join",
  "observer_record_identity",
  "request_body_identity",
  "request_record_identity",
  "schema_version",
  "status",
  "supporting_artifacts",
  "task_id",
  "transport_record_identity",
  "usage_record_identity",
]);
const CONTEXT_RECORD_KEYS = Object.freeze([
  "adapter_result_identity",
  "join",
  "schema_version",
  "task_id",
]);
const REQUEST_RECORD_KEYS = Object.freeze([
  "context_record_identity",
  "join",
  "policy",
  "request_body_identity",
  "schema_version",
  "task_id",
]);
const SAFE_FAILURE_RECEIPT_KEYS = Object.freeze([
  "join",
  "message",
  "reason_code",
  "response_persisted",
  "schema_version",
  "secret_persisted",
  "status",
  "task_id",
]);
const RESEARCH_FAILURE_RECEIPT_KEYS = Object.freeze([
  "admission_receipt_identity",
  "failure_stage",
  "join",
  "reason_code",
  "response_admitted",
  "schema_version",
  "status",
  "task_id",
  "worker_success_fields_trusted",
]);
const RESEARCH_FAILURE_STAGES = Object.freeze([
  "MODEL",
  "JSON",
  "PATCH_IR",
  "COMPILER",
  "ORACLE",
  "TEST",
]);
const EARLY_RESEARCH_FAILURE_STAGES = new Set([
  "MODEL",
  "JSON",
  "PATCH_IR",
  "COMPILER",
]);
const SUPPORTING_ARTIFACT_KEYS = Object.freeze([
  "context_record",
  "observer_record",
  "observer_stderr",
  "observer_stdout",
  "request_body",
  "request_record",
  "transport_record",
  "usage_record",
]);
const INVENTORY_ENTRY_KEYS = Object.freeze([
  "byte_length",
  "nlink",
  "path",
  "sha256",
  "type",
]);
const NON_PASS_CASE_KEYS = Object.freeze([
  "case_id",
  "failure_receipt_path",
  "root",
]);
const MAX_EVIDENCE_TREE_DEPTH = 32;
const MAX_EVIDENCE_DIRECTORIES = 4096;
const MAX_EVIDENCE_FILES = 10000;
const MAX_EVIDENCE_TOTAL_BYTES = 512 * 1024 * 1024;

function validateRelativeArtifactPath(value, label) {
  assertCritical(
    typeof value === "string"
      && value.length > 0
      && value.length <= 4096
      && !value.includes("\0")
      && !isAbsolute(value)
      && !value.split("/").some(
        (component) => component === "" || component === "." || component === "..",
      ),
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${label} is invalid`,
  );
  return value;
}

function validateArtifactDescriptor(value, label) {
  try {
    exactKeys(value, ["path", "byte_length", "sha256"], label);
  } catch {
    failCritical("EVIDENCE_CROSS_BINDING_INVALID", `${label} key set is invalid`);
  }
  return {
    path: validateRelativeArtifactPath(value.path, `${label}.path`),
    ...validateIdentity({
      byte_length: value.byte_length,
      sha256: value.sha256,
    }, label),
  };
}

function skipJsonWhitespace(text, state) {
  while (state.index < text.length && /[\t\n\r ]/.test(text[state.index])) {
    state.index += 1;
  }
}

function scanJsonString(text, state) {
  const start = state.index;
  if (text[state.index] !== "\"") throw new Error("JSON string expected");
  state.index += 1;
  let escaped = false;
  while (state.index < text.length) {
    const character = text[state.index];
    state.index += 1;
    if (escaped) {
      if (character === "u") {
        const hex = text.slice(state.index, state.index + 4);
        if (!/^[0-9A-Fa-f]{4}$/.test(hex)) throw new Error("invalid JSON escape");
        state.index += 4;
      } else if (!/["\\/bfnrt]/.test(character)) {
        throw new Error("invalid JSON escape");
      }
      escaped = false;
    } else if (character === "\\") {
      escaped = true;
    } else if (character === "\"") {
      return JSON.parse(text.slice(start, state.index));
    } else if (character.charCodeAt(0) < 0x20) {
      throw new Error("invalid JSON control character");
    }
  }
  throw new Error("unterminated JSON string");
}

function scanJsonValue(text, state) {
  skipJsonWhitespace(text, state);
  const character = text[state.index];
  if (character === "{") {
    state.index += 1;
    skipJsonWhitespace(text, state);
    const keys = new Set();
    if (text[state.index] === "}") {
      state.index += 1;
      return;
    }
    while (state.index < text.length) {
      skipJsonWhitespace(text, state);
      const key = scanJsonString(text, state);
      if (keys.has(key)) {
        failCritical("DUPLICATE_JSON_KEY", "raw JSON contains a duplicate object key");
      }
      keys.add(key);
      skipJsonWhitespace(text, state);
      if (text[state.index] !== ":") throw new Error("JSON object colon expected");
      state.index += 1;
      scanJsonValue(text, state);
      skipJsonWhitespace(text, state);
      if (text[state.index] === "}") {
        state.index += 1;
        return;
      }
      if (text[state.index] !== ",") throw new Error("JSON object comma expected");
      state.index += 1;
    }
    throw new Error("unterminated JSON object");
  }
  if (character === "[") {
    state.index += 1;
    skipJsonWhitespace(text, state);
    if (text[state.index] === "]") {
      state.index += 1;
      return;
    }
    while (state.index < text.length) {
      scanJsonValue(text, state);
      skipJsonWhitespace(text, state);
      if (text[state.index] === "]") {
        state.index += 1;
        return;
      }
      if (text[state.index] !== ",") throw new Error("JSON array comma expected");
      state.index += 1;
    }
    throw new Error("unterminated JSON array");
  }
  if (character === "\"") {
    scanJsonString(text, state);
    return;
  }
  const remainder = text.slice(state.index);
  const primitive = /^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(remainder);
  if (primitive === null) throw new Error("invalid JSON value");
  state.index += primitive[0].length;
}

function parseRawJsonNoDuplicates(bytes, label, failureCode) {
  assertCritical(
    Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 1024 * 1024,
    failureCode,
    `${label} must be bounded non-empty bytes`,
  );
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    failCritical(failureCode, `${label} is not exact UTF-8`);
  }
  try {
    const state = { index: 0 };
    scanJsonValue(text, state);
    skipJsonWhitespace(text, state);
    if (state.index !== text.length) throw new Error("trailing JSON bytes");
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    failCritical(failureCode, `${label} is invalid JSON`);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    failCritical(failureCode, `${label} is invalid JSON`);
  }
  assertCritical(
    bytes.equals(canonicalBytes(value)),
    failureCode,
    `${label} is not canonical JSON with exactly one trailing LF`,
  );
  return value;
}

export function parseClosedContextRecord(
  bytes,
  { expected_join = null } = {},
) {
  const value = parseRawJsonNoDuplicates(
    bytes,
    "context record",
    "CONTEXT_KEYSET_INVALID",
  );
  try {
    exactKeys(value, CONTEXT_RECORD_KEYS, "context record");
  } catch {
    failCritical("CONTEXT_KEYSET_INVALID", "context record key set is not closed");
  }
  assertCritical(
    value.schema_version === "p1-165-context-record/v1"
      && value.task_id === TASK_ID,
    "CONTEXT_KEYSET_INVALID",
    "context record schema or Task identity is invalid",
  );
  const validatedJoin = validateJoin(value.join);
  if (expected_join !== null) {
    assertCritical(
      canonicalJson(validatedJoin) === canonicalJson(validateJoin(expected_join)),
      "EVIDENCE_CROSS_BINDING_INVALID",
      "context record join drifted",
    );
  }
  return {
    value: {
      schema_version: value.schema_version,
      task_id: value.task_id,
      join: validatedJoin,
      adapter_result_identity: validateArtifactDescriptor(
        value.adapter_result_identity,
        "context adapter result identity",
      ),
    },
    identity: bytesIdentity(bytes),
  };
}

export function parseClosedRequestRecord(
  bytes,
  {
    expected_join = null,
    expected_context_identity = null,
    expected_policy = null,
  } = {},
) {
  const value = parseRawJsonNoDuplicates(
    bytes,
    "request record",
    "REQUEST_KEYSET_INVALID",
  );
  try {
    exactKeys(value, REQUEST_RECORD_KEYS, "request record");
  } catch {
    failCritical("REQUEST_KEYSET_INVALID", "request record key set is not closed");
  }
  assertCritical(
    value.schema_version === "p1-165-request-record/v1"
      && value.task_id === TASK_ID,
    "REQUEST_KEYSET_INVALID",
    "request record schema or Task identity is invalid",
  );
  const validatedJoin = validateJoin(value.join);
  if (expected_join !== null) {
    assertCritical(
      canonicalJson(validatedJoin) === canonicalJson(validateJoin(expected_join)),
      "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
      "request record join drifted",
    );
  }
  const observedContextIdentity = validateIdentity(
    value.context_record_identity,
    "request context identity",
  );
  if (expected_context_identity !== null) {
    assertCritical(
      canonicalJson(observedContextIdentity)
        === canonicalJson(validateIdentity(expected_context_identity)),
      "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
      "request record does not bind the exact context record",
    );
  }
  const observedPolicy = validatePolicy(value.policy, "request policy");
  if (expected_policy !== null) {
    assertCritical(
      canonicalJson(observedPolicy) === canonicalJson(validatePolicy(expected_policy)),
      "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
      "request record policy drifted",
    );
  }
  return {
    value: {
      schema_version: value.schema_version,
      task_id: value.task_id,
      join: validatedJoin,
      context_record_identity: observedContextIdentity,
      request_body_identity: validateIdentity(
        value.request_body_identity,
        "request body identity",
      ),
      policy: observedPolicy,
    },
    identity: bytesIdentity(bytes),
  };
}

function mapCoreFailure(error, fallback = "EVIDENCE_WRITE_FAILED") {
  if (error instanceof AdmissionNonPass) throw error;
  const mapped = new Map([
    ["OWNED_ROOT_PREEXISTS", "ROOT_PREEXISTS"],
    ["OWNED_ROOT_INVALID", "PATH_ESCAPE_REJECTED"],
    ["PATH_ESCAPE_REJECTED", "PATH_ESCAPE_REJECTED"],
    ["PATH_INVALID", "PATH_ESCAPE_REJECTED"],
    ["PATH_MISSING", "PATH_MISSING"],
    ["PATH_TYPE_REJECTED", "NON_REGULAR_FILE_REJECTED"],
    ["SYMLINK_REJECTED", "SYMLINK_REJECTED"],
    ["HARDLINK_REJECTED", "HARDLINK_REJECTED"],
    ["CREATE_ONCE_FAILED", "CREATE_ONCE_FAILED"],
    ["OWNERSHIP_REJECTED", "PATH_ESCAPE_REJECTED"],
  ]);
  const code = mapped.get(error?.code) ?? fallback;
  failCritical(code, error?.message ?? String(error));
}

function ownedRoot(handle, label) {
  try {
    const root = assertOwnedRoot(handle);
    assertCritical(
      realpathSync(root) === resolve(root),
      "PATH_ESCAPE_REJECTED",
      `${label} realpath identity drifted`,
    );
    return root;
  } catch (error) {
    mapCoreFailure(error);
  }
}

function assertSeparatedRoots(left, right) {
  const leftRoot = ownedRoot(left, "Evidence root");
  const rightRoot = ownedRoot(right, "quarantine root");
  const leftToRight = relative(leftRoot, rightRoot);
  const rightToLeft = relative(rightRoot, leftRoot);
  assertCritical(
    leftRoot !== rightRoot
      && (leftToRight.startsWith(`..${sep}`) || leftToRight === "..")
      && (rightToLeft.startsWith(`..${sep}`) || rightToLeft === ".."),
    "PATH_ESCAPE_REJECTED",
    "Evidence and quarantine roots must be physically disjoint",
  );
}

function mapContained(root, relativePath, label) {
  try {
    return containedPath(root, relativePath, label);
  } catch (error) {
    mapCoreFailure(error, "PATH_ESCAPE_REJECTED");
  }
}

function ensureOwnedParent(handle, relativePath, createdDirectories = null) {
  const root = ownedRoot(handle, "owned root");
  const destination = mapContained(root, relativePath, "create-once artifact");
  const parentRelative = relative(root, dirname(destination));
  let current = root;
  for (const component of parentRelative === "" ? [] : parentRelative.split(sep)) {
    current = resolve(current, component);
    if (!existsSync(current)) {
      mkdirSync(current, { recursive: false, mode: 0o700 });
      const created = lstatSync(current);
      if (createdDirectories !== null) {
        createdDirectories.push({
          path: current,
          dev: created.dev,
          ino: created.ino,
        });
      }
    }
    const stat = lstatSync(current);
    assertCritical(
      stat.isDirectory() && !stat.isSymbolicLink(),
      "SYMLINK_REJECTED",
      "artifact parent is not a real directory",
    );
    assertCritical(
      realpathSync(current) === current,
      "PATH_ESCAPE_REJECTED",
      "artifact parent realpath drifted",
    );
  }
  return destination;
}

function removeCreatedDirectoryExact(entry) {
  if (!existsSync(entry.path)) return;
  const observed = lstatSync(entry.path);
  assertCritical(
    observed.isDirectory()
      && !observed.isSymbolicLink()
      && observed.dev === entry.dev
      && observed.ino === entry.ino,
    "PATH_ESCAPE_REJECTED",
    "rollback directory no longer equals the owned directory created here",
  );
  try {
    rmdirSync(entry.path);
  } catch (error) {
    failCritical(
      "EVIDENCE_WRITE_FAILED",
      `owned rollback directory is not empty: ${error?.code ?? error?.message}`,
    );
  }
}

function closeDescriptor(descriptor) {
  if (descriptor === null) return;
  try {
    closeSync(descriptor);
  } catch {
    // A close failure cannot make a partially written artifact acceptable.
  }
}

function validateArtifactAncestorChain(
  root,
  path,
  expectedDev,
  expectedUid,
  expectedRootIno,
) {
  if (root === null) return [];
  const relativePath = relative(root, path);
  assertCritical(
    relativePath !== ""
      && relativePath !== ".."
      && !relativePath.startsWith(`..${sep}`)
      && !isAbsolute(relativePath),
    "PATH_ESCAPE_REJECTED",
    "artifact path escapes its owned root",
  );
  const rootStat = lstatOptional(root);
  assertCritical(
    rootStat !== null
      && rootStat.isDirectory()
      && !rootStat.isSymbolicLink()
      && rootStat.dev === expectedDev
      && rootStat.uid === expectedUid
      && (expectedRootIno === null || rootStat.ino === expectedRootIno)
      && realpathSync(root) === root,
    "PATH_ESCAPE_REJECTED",
    "artifact owned root identity drifted",
  );
  const identities = [{
    path: root,
    dev: rootStat.dev,
    ino: rootStat.ino,
    uid: rootStat.uid,
  }];
  let current = root;
  const components = relativePath.split(sep).slice(0, -1);
  for (const component of components) {
    current = join(current, component);
    const stat = lstatOptional(current);
    assertCritical(
      stat !== null
        && stat.isDirectory()
        && !stat.isSymbolicLink()
        && stat.dev === expectedDev
        && stat.uid === expectedUid
        && realpathSync(current) === current,
      "PATH_ESCAPE_REJECTED",
      "artifact ancestor is not one owned real directory",
    );
    identities.push({
      path: current,
      dev: stat.dev,
      ino: stat.ino,
      uid: stat.uid,
    });
  }
  return identities;
}

function revalidateArtifactAncestorChain(identities) {
  for (const identity of identities) {
    const stat = lstatOptional(identity.path);
    assertCritical(
      stat !== null
        && stat.isDirectory()
        && !stat.isSymbolicLink()
        && stat.dev === identity.dev
        && stat.ino === identity.ino
        && stat.uid === identity.uid
        && realpathSync(identity.path) === identity.path,
      "IDENTITY_MISMATCH",
      "artifact ancestor identity drifted during read",
    );
  }
}

function readRegularFileNoFollow(path, {
  label,
  root = null,
  expected_dev = null,
  expected_ino = null,
  expected_uid = null,
  expected_root_ino = null,
  expected_mode = null,
  require_single_link = true,
  maximum_bytes = MAX_EVIDENCE_TOTAL_BYTES,
  sync = false,
}) {
  let descriptor = null;
  try {
    const before = lstatOptional(path);
    assertCritical(
      before !== null,
      "PATH_MISSING",
      `${label} is missing`,
    );
    assertCritical(
      !before.isSymbolicLink(),
      "SYMLINK_REJECTED",
      `${label} is a symlink`,
    );
    assertCritical(
      before.isFile(),
      "NON_REGULAR_FILE_REJECTED",
      `${label} is not a regular file`,
    );
    assertCritical(
      !require_single_link || before.nlink === 1,
      "HARDLINK_REJECTED",
      `${label} must have one link`,
    );
    assertCritical(
      (expected_dev === null || before.dev === expected_dev)
        && (expected_ino === null || before.ino === expected_ino)
        && (expected_uid === null || before.uid === expected_uid)
        && (
          expected_mode === null
          || (before.mode & 0o777) === expected_mode
        ),
      "IDENTITY_MISMATCH",
      `${label} ownership, mode or inode drifted before read`,
    );
    assertCritical(
      Number.isSafeInteger(maximum_bytes)
        && maximum_bytes >= 0
        && before.size <= maximum_bytes,
      "RESPONSE_TOO_LARGE",
      `${label} exceeds its read byte limit`,
    );
    const ancestors = validateArtifactAncestorChain(
      root,
      path,
      expected_dev ?? before.dev,
      expected_uid ?? before.uid,
      expected_root_ino,
    );
    descriptor = openSync(
      path,
      fsConstants.O_RDONLY
        | (fsConstants.O_NOFOLLOW ?? 0)
        | (fsConstants.O_NONBLOCK ?? 0),
    );
    const opened = fstatSync(descriptor);
    assertCritical(
      opened.isFile()
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.uid === before.uid
        && opened.nlink === before.nlink
        && opened.size === before.size
        && (!require_single_link || opened.nlink === 1)
        && (
          expected_mode === null
          || (opened.mode & 0o777) === expected_mode
        ),
      "IDENTITY_MISMATCH",
      `${label} changed while opening with no-follow`,
    );
    const bytes = readFileSync(descriptor);
    if (sync) fsyncSync(descriptor);
    const afterFd = fstatSync(descriptor);
    const afterPath = lstatOptional(path);
    assertCritical(
      afterPath !== null
        && afterPath.isFile()
        && !afterPath.isSymbolicLink()
        && afterPath.dev === opened.dev
        && afterPath.ino === opened.ino
        && afterPath.uid === opened.uid
        && afterPath.nlink === opened.nlink
        && afterPath.size === opened.size
        && afterFd.dev === opened.dev
        && afterFd.ino === opened.ino
        && afterFd.uid === opened.uid
        && afterFd.nlink === opened.nlink
        && afterFd.size === opened.size
        && bytes.length === opened.size,
      "IDENTITY_MISMATCH",
      `${label} changed during no-follow read`,
    );
    revalidateArtifactAncestorChain(ancestors);
    return { bytes, stat: opened };
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    if (error?.code === "ELOOP") {
      failCritical("SYMLINK_REJECTED", `${label} is a symlink`);
    }
    failCritical(
      "EVIDENCE_WRITE_FAILED",
      `${label} no-follow read failed: ${error?.code ?? error?.message}`,
    );
  } finally {
    closeDescriptor(descriptor);
  }
}

function unlinkCreatedExact(entry) {
  if (entry === null || !existsSync(entry.path)) return;
  const observed = lstatSync(entry.path);
  assertCritical(
    observed.isFile()
      && !observed.isSymbolicLink()
      && observed.nlink === 1
      && observed.dev === entry.dev
      && observed.ino === entry.ino,
    "HARDLINK_REJECTED",
    "rollback target no longer equals the unique file created by this invocation",
  );
  unlinkSync(entry.path);
}

function openExclusive(path) {
  try {
    if (existsSync(path)) {
      const existing = lstatSync(path);
      assertCritical(
        !existing.isSymbolicLink(),
        "SYMLINK_REJECTED",
        "create-once destination is a symlink",
      );
      assertCritical(
        existing.nlink === 1,
        "HARDLINK_REJECTED",
        "create-once destination has multiple links",
      );
      failCritical("CREATE_ONCE_FAILED", "create-once destination already exists");
    }
    const descriptor = openSync(
      path,
      fsConstants.O_CREAT
        | fsConstants.O_EXCL
        | fsConstants.O_WRONLY
        | (fsConstants.O_NOFOLLOW ?? 0),
      0o600,
    );
    fchmodSync(descriptor, 0o600);
    const stat = fstatSync(descriptor);
    assertCritical(
      stat.isFile()
        && stat.nlink === 1
        && stat.uid === currentUid()
        && (stat.mode & 0o777) === 0o600,
      "HARDLINK_REJECTED",
      "new create-once artifact is not one owned 0600 single-link regular file",
    );
    return {
      descriptor,
      created: {
        path,
        dev: stat.dev,
        ino: stat.ino,
        uid: stat.uid,
      },
    };
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    if (error?.code !== "EEXIST") {
      failCritical(
        "EVIDENCE_WRITE_FAILED",
        `create-once open failed: ${error?.code ?? error?.message}`,
      );
    }
    failCritical(
      "CREATE_ONCE_FAILED",
      `create-once open failed: ${error?.code ?? error?.message}`,
    );
  }
}

function verifyCreatedArtifact(created, bytes) {
  const persisted = readRegularFileNoFollow(created.path, {
    label: "created Evidence artifact",
    expected_dev: created.dev,
    expected_ino: created.ino,
    expected_uid: created.uid,
    expected_mode: 0o600,
    maximum_bytes: bytes.length,
  });
  assertCritical(
    persisted.bytes.equals(bytes),
    "EVIDENCE_WRITE_FAILED",
    "created Evidence artifact bytes drifted",
  );
}

function writeAdmissionArtifacts({
  evidence_handle,
  artifacts,
}) {
  assertCritical(
    Array.isArray(artifacts) && artifacts.length > 0,
    "EVIDENCE_WRITE_FAILED",
    "admission artifact set is empty",
  );
  const createdDirectories = [];
  const opened = [];
  try {
    const paths = artifacts.map((entry) => {
      assertCritical(
        entry !== null
          && typeof entry === "object"
          && Buffer.isBuffer(entry.bytes)
          && typeof entry.relative_path === "string",
        "EVIDENCE_WRITE_FAILED",
        "admission artifact is invalid",
      );
      return ensureOwnedParent(
        evidence_handle,
        entry.relative_path,
        createdDirectories,
      );
    });
    assertCritical(
      new Set(paths).size === paths.length,
      "EVIDENCE_CROSS_BINDING_INVALID",
      "admission artifact paths collide",
    );
    for (let index = 0; index < paths.length; index += 1) {
      opened.push({
        ...openExclusive(paths[index]),
        bytes: artifacts[index].bytes,
      });
    }
    for (const entry of opened) {
      writeFileSync(entry.descriptor, entry.bytes);
      fchmodSync(entry.descriptor, 0o600);
      fsyncSync(entry.descriptor);
      const finalStat = fstatSync(entry.descriptor);
      assertCritical(
        finalStat.isFile()
          && finalStat.nlink === 1
          && finalStat.dev === entry.created.dev
          && finalStat.ino === entry.created.ino
          && finalStat.uid === entry.created.uid
          && (finalStat.mode & 0o777) === 0o600,
        "IDENTITY_MISMATCH",
        "created Evidence artifact drifted before descriptor close",
      );
      verifyCreatedArtifact(entry.created, entry.bytes);
      closeDescriptor(entry.descriptor);
      entry.descriptor = null;
    }
  } catch (error) {
    for (const entry of opened) closeDescriptor(entry.descriptor);
    for (const entry of [...opened].reverse()) {
      if (entry.created !== null) unlinkCreatedExact(entry.created);
    }
    for (const directory of [...createdDirectories].reverse()) {
      removeCreatedDirectoryExact(directory);
    }
    if (error instanceof AdmissionNonPass) throw error;
    failCritical(
      "EVIDENCE_WRITE_FAILED",
      `atomic admission persistence failed: ${error?.code ?? error?.message}`,
    );
  }
}

function readQuarantineBytes(handle, relativePath, maximum) {
  const root = ownedRoot(handle, "quarantine root");
  const path = mapContained(root, relativePath, "quarantine artifact");
  return readRegularFileNoFollow(path, {
    label: "quarantine artifact",
    root,
    expected_dev: handle.dev,
    expected_uid: currentUid(),
    expected_root_ino: handle.ino,
    expected_mode: 0o600,
    require_single_link: true,
    maximum_bytes: maximum,
  }).bytes;
}

function validateExistingSupportingArtifacts({
  evidence_handle,
  supporting_artifacts,
  expected_bytes,
}) {
  try {
    exactKeys(
      supporting_artifacts,
      SUPPORTING_ARTIFACT_KEYS,
      "supporting artifacts",
    );
  } catch {
    failCritical(
      "EVIDENCE_CROSS_BINDING_INVALID",
      "supporting artifact key set is not closed",
    );
  }
  const root = ownedRoot(evidence_handle, "Evidence root");
  const result = {};
  const paths = [];
  for (const key of SUPPORTING_ARTIFACT_KEYS) {
    const descriptor = validateArtifactDescriptor(
      supporting_artifacts[key],
      `supporting_artifacts.${key}`,
    );
    const expected = expected_bytes[key];
    assertCritical(
      Buffer.isBuffer(expected),
      "EVIDENCE_CROSS_BINDING_INVALID",
      `expected bytes for ${key} are missing`,
    );
    const absolute = mapContained(root, descriptor.path, `supporting ${key}`);
    const actual = readRegularFileNoFollow(absolute, {
      label: `supporting ${key}`,
      root,
      expected_dev: evidence_handle.dev,
      expected_uid: currentUid(),
      expected_root_ino: evidence_handle.ino,
      expected_mode: 0o600,
      require_single_link: true,
      maximum_bytes: descriptor.byte_length,
    }).bytes;
    assertCritical(
      actual.equals(expected)
        && canonicalJson(bytesIdentity(actual))
          === canonicalJson({
            byte_length: descriptor.byte_length,
            sha256: descriptor.sha256,
          }),
      "IDENTITY_MISMATCH",
      `supporting ${key} bytes or identity drifted`,
    );
    result[key] = descriptor;
    paths.push(absolute);
  }
  assertCritical(
    new Set(paths).size === paths.length,
    "EVIDENCE_CROSS_BINDING_INVALID",
    "supporting artifact paths are not unique",
  );
  return result;
}

function lstatOptional(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    failCritical(
      "EVIDENCE_WRITE_FAILED",
      `lstat failed for atomic Evidence path: ${error?.code ?? error?.message}`,
    );
  }
}

function currentUid() {
  assertCritical(
    typeof process.getuid === "function"
      && Number.isSafeInteger(process.getuid())
      && process.getuid() >= 0,
    "EVIDENCE_WRITE_FAILED",
    "current process UID is unavailable",
  );
  return process.getuid();
}

function validateOwnedDirectory(path, {
  expected_dev,
  expected_uid,
  expected_ino = null,
  label,
}) {
  const stat = lstatOptional(path);
  assertCritical(
    stat !== null
      && stat.isDirectory()
      && !stat.isSymbolicLink()
      && stat.dev === expected_dev
      && stat.uid === expected_uid
      && (expected_ino === null || stat.ino === expected_ino)
      && realpathSync(path) === resolve(path),
    "PATH_ESCAPE_REJECTED",
    `${label} identity, owner, filesystem or realpath drifted`,
  );
  return stat;
}

function fsyncDirectoryExact(path, expected) {
  let descriptor = null;
  try {
    descriptor = openSync(
      path,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const stat = fstatSync(descriptor);
    assertCritical(
      stat.isDirectory()
        && stat.dev === expected.dev
        && stat.ino === expected.ino
        && stat.uid === expected.uid,
      "PATH_ESCAPE_REJECTED",
      "directory changed before fsync",
    );
    fsyncSync(descriptor);
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    failCritical(
      "EVIDENCE_WRITE_FAILED",
      `directory fsync failed: ${error?.code ?? error?.message}`,
    );
  } finally {
    closeDescriptor(descriptor);
  }
}

function inspectRegularFile(path, {
  root,
  expected_dev,
  expected_uid,
  expected_root_ino,
  expected_stat,
  sync,
}) {
  assertCritical(
    expected_stat.isFile() && !expected_stat.isSymbolicLink(),
    "NON_REGULAR_FILE_REJECTED",
    "staged Evidence leaf is not a regular file",
  );
  assertCritical(
    expected_stat.nlink === 1,
    "HARDLINK_REJECTED",
    "staged Evidence leaf has multiple links",
  );
  const inspected = readRegularFileNoFollow(path, {
    label: "staged Evidence leaf",
    root,
    expected_dev,
    expected_ino: expected_stat.ino,
    expected_uid,
    expected_root_ino,
    expected_mode: 0o600,
    require_single_link: true,
    maximum_bytes: MAX_EVIDENCE_TOTAL_BYTES,
    sync,
  });
  const relativePath = relative(root, path).split(sep).join("/");
  return {
    descriptor: {
      path: validateRelativeArtifactPath(
        relativePath,
        "staged Evidence inventory path",
      ),
      type: "REGULAR_FILE",
      nlink: 1,
      ...bytesIdentity(inspected.bytes),
    },
    bytes: inspected.bytes,
  };
}

function inspectOwnedEvidenceTree(root, {
  root_dev,
  root_uid,
  root_ino,
  sync,
}) {
  const entries = [];
  const bytesByPath = new Map();
  let directoryCount = 0;
  let totalBytes = 0;
  const visit = (directory, depth) => {
    assertCritical(
      depth <= MAX_EVIDENCE_TREE_DEPTH,
      "CLOSED_INVENTORY_DRIFT",
      "staged Evidence tree exceeds the maximum directory depth",
    );
    directoryCount += 1;
    assertCritical(
      directoryCount <= MAX_EVIDENCE_DIRECTORIES,
      "CLOSED_INVENTORY_DRIFT",
      "staged Evidence tree exceeds the maximum directory count",
    );
    const directoryStat = validateOwnedDirectory(directory, {
      expected_dev: root_dev,
      expected_uid: root_uid,
      expected_ino: directory === root ? root_ino : null,
      label: "staged Evidence directory",
    });
    const names = readdirSync(directory).sort();
    assertCritical(
      names.length > 0,
      "CLOSED_INVENTORY_DRIFT",
      "staged Evidence tree contains an empty directory",
    );
    for (const name of names) {
      assertCritical(
        name.length > 0 && name !== "." && name !== ".." && !name.includes(sep),
        "PATH_ESCAPE_REJECTED",
        "staged Evidence contains an invalid entry name",
      );
      const path = join(directory, name);
      const stat = lstatSync(path);
      assertCritical(
        !stat.isSymbolicLink(),
        "SYMLINK_REJECTED",
        "staged Evidence contains a symlink",
      );
      if (stat.isDirectory()) {
        visit(path, depth + 1);
      } else {
        assertCritical(
          stat.isFile(),
          "NON_REGULAR_FILE_REJECTED",
          "staged Evidence contains a FIFO, socket or device",
        );
        const inspected = inspectRegularFile(path, {
          root,
          expected_dev: root_dev,
          expected_uid: root_uid,
          expected_root_ino: root_ino,
          expected_stat: stat,
          sync,
        });
        totalBytes += inspected.bytes.length;
        assertCritical(
          Number.isSafeInteger(totalBytes)
            && totalBytes <= MAX_EVIDENCE_TOTAL_BYTES,
          "CLOSED_INVENTORY_DRIFT",
          "staged Evidence tree exceeds the total byte limit",
        );
        entries.push(inspected.descriptor);
        bytesByPath.set(inspected.descriptor.path, inspected.bytes);
      }
    }
    if (sync) fsyncDirectoryExact(directory, directoryStat);
  };
  visit(root, 0);
  entries.sort((left, right) => (
    left.path < right.path ? -1 : left.path > right.path ? 1 : 0
  ));
  assertCritical(
    entries.length > 0 && entries.length <= MAX_EVIDENCE_FILES,
    "CLOSED_INVENTORY_DRIFT",
    "staged Evidence inventory size is invalid",
  );
  return {
    entries,
    bytesByPath,
    directory_count: directoryCount,
    total_bytes: totalBytes,
  };
}

function validateExpectedInventory(value) {
  assertCritical(
    Array.isArray(value) && value.length > 0 && value.length <= MAX_EVIDENCE_FILES,
    "CLOSED_INVENTORY_DRIFT",
    "expected Evidence inventory is invalid",
  );
  const entries = value.map((entry, index) => {
    try {
      exactKeys(entry, INVENTORY_ENTRY_KEYS, `expected inventory[${index}]`);
    } catch {
      failCritical(
        "CLOSED_INVENTORY_DRIFT",
        `expected inventory[${index}] key set is not closed`,
      );
    }
    const identity = validateArtifactDescriptor({
      path: entry.path,
      byte_length: entry.byte_length,
      sha256: entry.sha256,
    }, `expected inventory[${index}]`);
    assertCritical(
      entry.type === "REGULAR_FILE" && entry.nlink === 1,
      "CLOSED_INVENTORY_DRIFT",
      `expected inventory[${index}] type or link count is invalid`,
    );
    return {
      path: identity.path,
      type: entry.type,
      nlink: entry.nlink,
      byte_length: identity.byte_length,
      sha256: identity.sha256,
    };
  });
  const paths = entries.map((entry) => entry.path);
  assertCritical(
    new Set(paths).size === paths.length
      && paths.every((path, index) => index === 0 || paths[index - 1] < path),
    "ORDERED_IDENTITY_SET_INVALID",
    "expected Evidence inventory is duplicated or not strictly ordered",
  );
  return entries;
}

function validateExpectedNonPassCases(value, inventory, bytesByPath) {
  assertCritical(
    Array.isArray(value) && value.length > 0 && value.length <= 10000,
    "CLOSED_INVENTORY_DRIFT",
    "expected NON_PASS case set is invalid",
  );
  const roots = [];
  const caseIds = new Set();
  const cases = value.map((entry, index) => {
    try {
      exactKeys(entry, NON_PASS_CASE_KEYS, `expected NON_PASS[${index}]`);
    } catch {
      failCritical(
        "CLOSED_INVENTORY_DRIFT",
        `expected NON_PASS[${index}] key set is not closed`,
      );
    }
    assertCritical(
      typeof entry.case_id === "string"
        && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$/.test(entry.case_id)
        && !caseIds.has(entry.case_id),
      "CLOSED_INVENTORY_DRIFT",
      `expected NON_PASS[${index}] case identity is invalid or duplicated`,
    );
    caseIds.add(entry.case_id);
    const root = validateRelativeArtifactPath(
      entry.root,
      `expected NON_PASS[${index}].root`,
    );
    const failurePath = validateRelativeArtifactPath(
      entry.failure_receipt_path,
      `expected NON_PASS[${index}].failure_receipt_path`,
    );
    assertCritical(
      failurePath === `${root}/safe-failure-receipt.json`,
      "CLOSED_INVENTORY_DRIFT",
      "expected NON_PASS receipt is not the sole canonical case artifact",
    );
    roots.push(root);
    return {
      case_id: entry.case_id,
      root,
      failure_receipt_path: failurePath,
    };
  });
  roots.sort();
  assertCritical(
    new Set(roots).size === roots.length
      && roots.every(
        (root, index) => roots.every(
          (other, otherIndex) => (
            index === otherIndex || !root.startsWith(`${other}/`)
          ),
        ),
      ),
    "CLOSED_INVENTORY_DRIFT",
    "expected NON_PASS roots are duplicated or nested",
  );
  const inventoryPaths = inventory.map((entry) => entry.path);
  for (const entry of cases) {
    const underRoot = inventoryPaths.filter(
      (path) => path.startsWith(`${entry.root}/`),
    );
    assertCritical(
      underRoot.length === 1 && underRoot[0] === entry.failure_receipt_path,
      "CLOSED_INVENTORY_DRIFT",
      `expected NON_PASS ${entry.case_id} retained artifacts other than its safe receipt`,
    );
    const receiptBytes = bytesByPath.get(entry.failure_receipt_path);
    const receipt = parseRawJsonNoDuplicates(
      receiptBytes,
      `expected NON_PASS ${entry.case_id} receipt`,
      "CLOSED_INVENTORY_DRIFT",
    );
    try {
      exactKeys(
        receipt,
        SAFE_FAILURE_RECEIPT_KEYS,
        `expected NON_PASS ${entry.case_id} receipt`,
      );
    } catch {
      failCritical(
        "CLOSED_INVENTORY_DRIFT",
        `expected NON_PASS ${entry.case_id} receipt key set drifted`,
      );
    }
    assertCritical(
      receipt.schema_version === "p1-165-safe-failure-receipt/v1"
        && receipt.task_id === TASK_ID
        && receipt.status === "NON_PASS"
        && receipt.response_persisted === false
        && receipt.secret_persisted === false
        && isCriticalReasonCode(receipt.reason_code)
        && receipt.message === "response admission failed closed before persistence",
      "CLOSED_INVENTORY_DRIFT",
      `expected NON_PASS ${entry.case_id} receipt is unsafe`,
    );
    validateJoin(receipt.join, `expected NON_PASS ${entry.case_id} join`);
  }
  return cases;
}

function assertFinalRootAbsent(path, label) {
  assertCritical(
    lstatOptional(path) === null,
    "ROOT_PREEXISTS",
    `${label} must be absent, including dangling symlinks`,
  );
}

export function commitOwnedEvidenceStage({
  stage_handle,
  final_root,
  expected_inventory,
  expected_non_pass_cases,
  secret_sentinel,
}) {
  const stageRoot = ownedRoot(stage_handle, "Evidence stage root");
  assertCritical(
    typeof final_root === "string"
      && isAbsolute(final_root)
      && resolve(final_root) === final_root
      && basename(final_root) !== ""
      && basename(final_root) !== "."
      && basename(final_root) !== "..",
    "PATH_ESCAPE_REJECTED",
    "final Evidence root must be one canonical absolute path",
  );
  const parentPath = dirname(final_root);
  assertCritical(
    dirname(stageRoot) === parentPath && stageRoot !== final_root,
    "PATH_ESCAPE_REJECTED",
    "Evidence stage and final roots must be distinct siblings",
  );
  const uid = currentUid();
  const parentInitial = lstatOptional(parentPath);
  assertCritical(
    parentInitial !== null
      && parentInitial.isDirectory()
      && !parentInitial.isSymbolicLink()
      && parentInitial.uid === uid
      && realpathSync(parentPath) === parentPath,
    "PATH_ESCAPE_REJECTED",
    "Evidence parent is not one owned real directory",
  );
  const stageInitial = validateOwnedDirectory(stageRoot, {
    expected_dev: parentInitial.dev,
    expected_uid: uid,
    expected_ino: stage_handle.ino,
    label: "Evidence stage root",
  });
  assertCritical(
    stageInitial.dev === parentInitial.dev
      && stageInitial.ino === stage_handle.ino
      && stageInitial.dev === stage_handle.dev,
    "PATH_ESCAPE_REJECTED",
    "Evidence stage and parent are not on the same frozen filesystem",
  );
  assertFinalRootAbsent(final_root, "final Evidence root");
  const expected = validateExpectedInventory(expected_inventory);
  const staged = inspectOwnedEvidenceTree(stageRoot, {
    root_dev: stageInitial.dev,
    root_uid: uid,
    root_ino: stageInitial.ino,
    sync: true,
  });
  assertCritical(
    canonicalJson(staged.entries) === canonicalJson(expected),
    "CLOSED_INVENTORY_DRIFT",
    "staged Evidence does not equal the frozen closed inventory",
  );
  const nonPassCases = validateExpectedNonPassCases(
    expected_non_pass_cases,
    staged.entries,
    staged.bytesByPath,
  );
  assertNoSecretReflection([...staged.bytesByPath.values()], secret_sentinel);

  const parentIdentity = {
    path: parentPath,
    dev: parentInitial.dev,
    ino: parentInitial.ino,
    uid: parentInitial.uid,
  };
  const stageIdentity = {
    path: stageRoot,
    dev: stageInitial.dev,
    ino: stageInitial.ino,
    uid: stageInitial.uid,
  };
  const inventoryIdentity = bytesIdentity(canonicalBytes(expected));
  const lockPath = `${final_root}.p1-165-commit-lock`;
  let lock = null;
  try {
    assertFinalRootAbsent(lockPath, "Evidence commit lock");
    lock = openExclusive(lockPath);
    const lockBytes = canonicalBytes({
      schema_version: "p1-165-evidence-commit-lock/v1",
      task_id: TASK_ID,
      final_root,
      parent: parentIdentity,
      stage: stageIdentity,
      inventory_identity: inventoryIdentity,
    });
    writeFileSync(lock.descriptor, lockBytes);
    fchmodSync(lock.descriptor, 0o600);
    fsyncSync(lock.descriptor);
    const lockStat = fstatSync(lock.descriptor);
    assertCritical(
      lockStat.isFile()
        && lockStat.nlink === 1
        && lockStat.dev === lock.created.dev
        && lockStat.ino === lock.created.ino
        && lockStat.uid === lock.created.uid
        && (lockStat.mode & 0o777) === 0o600,
      "IDENTITY_MISMATCH",
      "Evidence commit lock drifted before descriptor close",
    );
    verifyCreatedArtifact(lock.created, lockBytes);
    closeDescriptor(lock.descriptor);
    lock.descriptor = null;
    fsyncDirectoryExact(parentPath, parentInitial);

    const parentBeforeRename = validateOwnedDirectory(parentPath, {
      expected_dev: parentInitial.dev,
      expected_uid: uid,
      expected_ino: parentInitial.ino,
      label: "Evidence parent before rename",
    });
    validateOwnedDirectory(stageRoot, {
      expected_dev: stageInitial.dev,
      expected_uid: uid,
      expected_ino: stageInitial.ino,
      label: "Evidence stage immediately before rename",
    });
    const lockedStage = inspectOwnedEvidenceTree(stageRoot, {
      root_dev: stageInitial.dev,
      root_uid: uid,
      root_ino: stageInitial.ino,
      sync: true,
    });
    assertCritical(
      canonicalJson(lockedStage.entries) === canonicalJson(expected)
        && canonicalJson(lockedStage.entries) === canonicalJson(staged.entries),
      "CLOSED_INVENTORY_DRIFT",
      "staged Evidence drifted after commit lock acquisition",
    );
    validateExpectedNonPassCases(
      nonPassCases,
      lockedStage.entries,
      lockedStage.bytesByPath,
    );
    assertNoSecretReflection(
      [...lockedStage.bytesByPath.values()],
      secret_sentinel,
    );
    assertFinalRootAbsent(final_root, "final Evidence root before rename");
    renameSync(stageRoot, final_root);
    fsyncDirectoryExact(parentPath, parentBeforeRename);

    assertCritical(
      lstatOptional(stageRoot) === null,
      "IDENTITY_MISMATCH",
      "stage path remained after atomic rename",
    );
    const finalStat = validateOwnedDirectory(final_root, {
      expected_dev: stageInitial.dev,
      expected_uid: uid,
      expected_ino: stageInitial.ino,
      label: "committed final Evidence root",
    });
    const parentAfterRename = validateOwnedDirectory(parentPath, {
      expected_dev: parentInitial.dev,
      expected_uid: uid,
      expected_ino: parentInitial.ino,
      label: "Evidence parent after rename",
    });
    const committed = inspectOwnedEvidenceTree(final_root, {
      root_dev: finalStat.dev,
      root_uid: uid,
      root_ino: finalStat.ino,
      sync: false,
    });
    assertCritical(
      canonicalJson(committed.entries) === canonicalJson(expected)
        && canonicalJson(committed.entries) === canonicalJson(staged.entries),
      "CLOSED_INVENTORY_DRIFT",
      "committed final Evidence inventory drifted after rename",
    );
    validateExpectedNonPassCases(
      nonPassCases,
      committed.entries,
      committed.bytesByPath,
    );
    assertNoSecretReflection(
      [...committed.bytesByPath.values()],
      secret_sentinel,
    );
    assertCritical(
      parentAfterRename.dev === parentIdentity.dev
        && parentAfterRename.ino === parentIdentity.ino
        && parentAfterRename.uid === parentIdentity.uid,
      "IDENTITY_MISMATCH",
      "Evidence parent identity drifted after commit",
    );
    return {
      schema_version: "p1-165-atomic-evidence-commit/v1",
      task_id: TASK_ID,
      status: "PASS",
      final_root,
      parent: parentIdentity,
      committed_root: {
        path: final_root,
        dev: finalStat.dev,
        ino: finalStat.ino,
        uid: finalStat.uid,
      },
      staged_root: stageIdentity,
      inventory_identity: inventoryIdentity,
      inventory_entries: committed.entries.length,
      directory_count: committed.directory_count,
      total_bytes: committed.total_bytes,
      expected_non_pass_cases: nonPassCases.length,
      atomic_rename: true,
      lock_held_during_final_reinspection: true,
      pre_rename_reinspection: true,
      same_filesystem: true,
    };
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    if (error?.code === "EEXIST" || error?.code === "ENOTEMPTY") {
      failCritical(
        "ROOT_PREEXISTS",
        "final Evidence root appeared before atomic rename",
      );
    }
    if (error?.code === "EXDEV") {
      failCritical(
        "PATH_ESCAPE_REJECTED",
        "stage and final Evidence roots are not on one filesystem",
      );
    }
    failCritical(
      "EVIDENCE_WRITE_FAILED",
      `atomic Evidence commit failed: ${error?.code ?? error?.message}`,
    );
  } finally {
    closeDescriptor(lock?.descriptor ?? null);
    if (
      lock !== null
      && lock.created !== null
      && lstatOptional(lock.created.path) !== null
    ) {
      unlinkCreatedExact(lock.created);
      const parentNow = lstatOptional(parentPath);
      if (
        parentNow !== null
        && parentNow.dev === parentInitial.dev
        && parentNow.ino === parentInitial.ino
        && parentNow.uid === parentInitial.uid
      ) {
        fsyncDirectoryExact(parentPath, parentNow);
      }
    }
  }
}

export function quarantineResponse({
  quarantine_handle,
  relative_path,
  chunks,
  response_bytes_max,
}) {
  assertCritical(
    Number.isSafeInteger(response_bytes_max) && response_bytes_max > 0,
    "TRANSPORT_KEYSET_INVALID",
    "quarantine byte cap is invalid",
  );
  assertCritical(
    Array.isArray(chunks) && chunks.length > 0,
    "HTTP_FRAMING_INCOMPLETE",
    "quarantine requires one or more response chunks",
  );
  let total = 0;
  const chunkIdentities = chunks.map((chunk, index) => {
    assertCritical(
      Buffer.isBuffer(chunk),
      "TRANSPORT_KEYSET_INVALID",
      `quarantine chunk ${index} is not bytes`,
    );
    total += chunk.length;
    assertCritical(
      total <= response_bytes_max,
      "RESPONSE_TOO_LARGE",
      "response exceeded the cap before quarantine persistence",
    );
    return { index, ...bytesIdentity(chunk) };
  });
  const responseBytes = Buffer.concat(chunks, total);
  writeAdmissionArtifacts({
    evidence_handle: quarantine_handle,
    artifacts: [{ relative_path, bytes: responseBytes }],
  });
  return {
    path: relative_path,
    chunks: chunkIdentities,
    ...bytesIdentity(responseBytes),
  };
}

export function assertNoSecretReflection(buffers, secretSentinel) {
  assertCritical(
    Buffer.isBuffer(secretSentinel) && secretSentinel.length >= 16,
    "REQUEST_KEYSET_INVALID",
    "Secret sentinel must be at least 16 bytes",
  );
  const digest = createHash("sha256").update(secretSentinel).digest();
  const needles = [
    secretSentinel,
    Buffer.from(secretSentinel.toString("base64"), "ascii"),
    digest,
    Buffer.from(digest.toString("hex"), "ascii"),
    Buffer.from(digest.toString("hex").toUpperCase(), "ascii"),
  ];
  assertCritical(
    Array.isArray(buffers) && buffers.length > 0,
    "EVIDENCE_WRITE_FAILED",
    "Secret reflection scan requires one or more byte buffers",
  );
  for (const bytes of buffers) {
    assertCritical(
      Buffer.isBuffer(bytes),
      "EVIDENCE_WRITE_FAILED",
      "Secret reflection scan input is not bytes",
    );
  }
  const scanTargets = [...buffers, Buffer.concat(buffers)];
  for (const bytes of scanTargets) {
    assertCritical(
      needles.every((needle) => bytes.indexOf(needle) === -1),
      "SECRET_REFLECTION_DETECTED",
      "retained Evidence reflects Secret bytes, encoding or digest",
    );
  }
}

function exactTransportBinding(record, {
  join,
  requestIdentity,
  policy,
  rawBytes,
  bodyBytes,
}) {
  const keys = Object.keys(record).sort();
  const expected = [
    "application_terminal",
    "body_identity",
    "chunks",
    "eof",
    "framing",
    "http",
    "join",
    "observed_peer",
    "policy",
    "protocol_terminal",
    "raw_response_identity",
    "request_record_identity",
    "schema_version",
  ].sort();
  assertCritical(
    canonicalJson(keys) === canonicalJson(expected),
    "TRANSPORT_KEYSET_INVALID",
    "transport record key set is not closed",
  );
  assertCritical(
    record.schema_version === "p1-165-transport-record/v1",
    "TRANSPORT_KEYSET_INVALID",
    "transport record schema is invalid",
  );
  assertCritical(
    canonicalJson(validateJoin(record.join)) === canonicalJson(validateJoin(join))
      && canonicalJson(validateIdentity(record.request_record_identity))
        === canonicalJson(requestIdentity)
      && canonicalJson(validatePolicy(record.policy))
        === canonicalJson(validatePolicy(policy)),
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    "transport record request join drifted",
  );
  assertCritical(
    canonicalJson(validateIdentity(record.raw_response_identity))
      === canonicalJson(bytesIdentity(rawBytes))
      && canonicalJson(validateIdentity(record.body_identity))
        === canonicalJson(bytesIdentity(bodyBytes)),
    "IDENTITY_MISMATCH",
    "transport response identity drifted",
  );
}

export function admitAndPersistResponse({
  evidence_handle,
  quarantine_handle,
  quarantine_relative_path,
  admitted_relative_path,
  receipt_relative_path,
  join,
  request_body_bytes,
  request_record_bytes,
  context_record_bytes,
  request_record_identity,
  policy,
  transport_chunks,
  eof,
  stream_terminal_events = [],
  observer_record,
  observer_stdout_bytes,
  observer_stderr_bytes,
  observed_peer,
  usage_record,
  secret_sentinel,
  supporting_artifacts,
}) {
  assertSeparatedRoots(evidence_handle, quarantine_handle);
  const validatedJoin = validateJoin(join);
  const validatedPolicy = validatePolicy(policy);
  const contextRecord = parseClosedContextRecord(context_record_bytes, {
    expected_join: validatedJoin,
  });
  const requestRecord = parseClosedRequestRecord(request_record_bytes, {
    expected_join: validatedJoin,
    expected_context_identity: contextRecord.identity,
    expected_policy: validatedPolicy,
  });
  assertCritical(
    Buffer.isBuffer(request_body_bytes)
      && request_body_bytes.length <= 4 * 1024 * 1024,
    "REQUEST_KEYSET_INVALID",
    "request body must be bounded exact bytes",
  );
  const requestBodyIdentity = bytesIdentity(request_body_bytes);
  assertCritical(
    canonicalJson(requestBodyIdentity)
      === canonicalJson(requestRecord.value.request_body_identity),
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    "request record does not bind the exact request body bytes",
  );
  const requestIdentity = validateIdentity(
    request_record_identity,
    "expected request record identity",
  );
  assertCritical(
    canonicalJson(requestIdentity) === canonicalJson(requestRecord.identity),
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    "request record identity does not equal the exact raw request record",
  );
  const quarantineBytes = readQuarantineBytes(
    quarantine_handle,
    quarantine_relative_path,
    validatedPolicy.response_bytes_max,
  );
  assertCritical(
    Array.isArray(transport_chunks)
      && transport_chunks.length > 0
      && transport_chunks.every((entry) => Buffer.isBuffer(entry)),
    "TRANSPORT_KEYSET_INVALID",
    "transport chunks are not a non-empty byte array",
  );
  assertCritical(
    Buffer.concat(transport_chunks).equals(quarantineBytes),
    "IDENTITY_MISMATCH",
    "quarantine bytes do not equal the observed transport chunks",
  );
  const analyzed = analyzeTransport({
    join: validatedJoin,
    request_record_identity: requestIdentity,
    chunks: transport_chunks,
    eof,
    stream_terminal_events,
    policy: validatedPolicy,
    observed_peer,
  });
  exactTransportBinding(analyzed.record, {
    join: validatedJoin,
    requestIdentity,
    policy: validatedPolicy,
    rawBytes: analyzed.response_bytes,
    bodyBytes: analyzed.body_bytes,
  });
  validateRawObservation({
    record: observer_record,
    stdout_bytes: observer_stdout_bytes,
    stderr_bytes: observer_stderr_bytes,
    join: validatedJoin,
    request_record_identity: requestIdentity,
    policy: validatedPolicy,
  });
  assertCritical(
    observer_record.peer === observed_peer,
    "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
    "observer peer does not equal the transport peer",
  );
  const usage = validateUsage(usage_record, {
    join: validatedJoin,
    responseIdentity: analyzed.record.body_identity,
    policy: validatedPolicy,
  });
  const transportBytes = canonicalBytes(analyzed.record);
  const observerBytes = canonicalBytes(observer_record);
  const usageBytes = canonicalBytes(usage);

  const admittedIdentity = bytesIdentity(analyzed.response_bytes);
  const receipt = {
    schema_version: "p1-165-admission-receipt/v1",
    task_id: TASK_ID,
    join: validatedJoin,
    context_record_identity: contextRecord.identity,
    request_body_identity: requestBodyIdentity,
    request_record_identity: requestIdentity,
    transport_record_identity: bytesIdentity(transportBytes),
    observer_record_identity: bytesIdentity(observerBytes),
    usage_record_identity: bytesIdentity(usageBytes),
    admitted_response: {
      path: admitted_relative_path,
      ...admittedIdentity,
    },
    body_identity: analyzed.record.body_identity,
    status: "ADMITTED",
  };
  assertNoSecretReflection(
    [
      context_record_bytes,
      request_body_bytes,
      request_record_bytes,
      analyzed.response_bytes,
      analyzed.body_bytes,
      transportBytes,
      observer_stdout_bytes,
      observer_stderr_bytes,
      observerBytes,
      usageBytes,
    ],
    secret_sentinel,
  );
  const supporting = validateExistingSupportingArtifacts({
    evidence_handle,
    supporting_artifacts,
    expected_bytes: {
      context_record: context_record_bytes,
      request_body: request_body_bytes,
      request_record: request_record_bytes,
      transport_record: transportBytes,
      observer_stdout: observer_stdout_bytes,
      observer_stderr: observer_stderr_bytes,
      observer_record: observerBytes,
      usage_record: usageBytes,
    },
  });
  assertCritical(
    observer_record.stdout_path === supporting.observer_stdout.path
      && observer_record.stderr_path === supporting.observer_stderr.path,
    "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
    "observer record paths do not equal the bound raw observer artifacts",
  );
  receipt.supporting_artifacts = supporting;
  try {
    exactKeys(receipt, ADMISSION_RECEIPT_KEYS, "admission receipt");
  } catch {
    failCritical("EVIDENCE_WRITE_FAILED", "admission receipt schema drifted");
  }
  const finalReceiptBytes = canonicalBytes(receipt);
  assertNoSecretReflection([finalReceiptBytes], secret_sentinel);
  writeAdmissionArtifacts({
    evidence_handle,
    artifacts: [
      {
        relative_path: admitted_relative_path,
        bytes: analyzed.response_bytes,
      },
      {
        relative_path: receipt_relative_path,
        bytes: finalReceiptBytes,
      },
    ],
  });
  return {
    status: "ADMITTED",
    raw_response_bytes: analyzed.response_bytes,
    body_bytes: analyzed.body_bytes,
    transport_record: analyzed.record,
    usage_record: usage,
    receipt,
  };
}

export function writeSafeFailureReceipt({
  evidence_handle,
  relative_path,
  join,
  reason_code,
  secret_sentinel = null,
}) {
  assertCritical(
    isCriticalReasonCode(reason_code),
    "EVIDENCE_WRITE_FAILED",
    "failure receipt reason code is not in the frozen production set",
  );
  const receipt = {
    schema_version: "p1-165-safe-failure-receipt/v1",
    task_id: TASK_ID,
    join: validateJoin(join),
    status: "NON_PASS",
    reason_code,
    response_persisted: false,
    secret_persisted: false,
    message: "response admission failed closed before persistence",
  };
  try {
    exactKeys(receipt, SAFE_FAILURE_RECEIPT_KEYS, "safe failure receipt");
    const receiptBytes = canonicalBytes(receipt);
    if (secret_sentinel !== null) {
      assertNoSecretReflection([receiptBytes], secret_sentinel);
    }
    writeAdmissionArtifacts({
      evidence_handle,
      artifacts: [{ relative_path, bytes: receiptBytes }],
    });
    return { path: relative_path, ...bytesIdentity(receiptBytes) };
  } catch (error) {
    mapCoreFailure(error);
  }
}

function validateResearchFailureStage(value) {
  assertCritical(
    typeof value === "string" && RESEARCH_FAILURE_STAGES.includes(value),
    "ACCOUNTING_MISMATCH",
    "research failure stage is outside the closed stage set",
  );
  return value;
}

export function writeResearchFailureReceipt({
  evidence_handle,
  relative_path,
  join,
  failure_stage,
  reason_code,
  admission_receipt_identity,
  secret_sentinel = null,
}) {
  const stage = validateResearchFailureStage(failure_stage);
  assertCritical(
    typeof reason_code === "string"
      && /^[A-Z][A-Z0-9_]{2,159}$/.test(reason_code),
    "ACCOUNTING_MISMATCH",
    "research failure reason code is invalid",
  );
  const receipt = {
    schema_version: "p1-165-research-failure-receipt/v1",
    task_id: TASK_ID,
    join: validateJoin(join),
    admission_receipt_identity: validateIdentity(
      admission_receipt_identity,
      "research failure admission receipt identity",
    ),
    failure_stage: stage,
    reason_code,
    response_admitted: true,
    worker_success_fields_trusted: false,
    status: "FAILED",
  };
  try {
    exactKeys(
      receipt,
      RESEARCH_FAILURE_RECEIPT_KEYS,
      "research failure receipt",
    );
    const receiptBytes = canonicalBytes(receipt);
    if (secret_sentinel !== null) {
      assertNoSecretReflection([receiptBytes], secret_sentinel);
    }
    writeAdmissionArtifacts({
      evidence_handle,
      artifacts: [{ relative_path, bytes: receiptBytes }],
    });
    return { path: relative_path, ...bytesIdentity(receiptBytes) };
  } catch (error) {
    mapCoreFailure(error);
  }
}

function readBoundArtifactFromOwnedRoot({
  evidence_handle,
  descriptor,
  label,
}) {
  const validated = validateArtifactDescriptor(descriptor, label);
  const root = ownedRoot(evidence_handle, "Evidence root");
  const absolute = mapContained(root, validated.path, label);
  const actual = readRegularFileNoFollow(absolute, {
    label,
    root,
    expected_dev: evidence_handle.dev,
    expected_uid: currentUid(),
    expected_root_ino: evidence_handle.ino,
    expected_mode: 0o600,
    require_single_link: true,
    maximum_bytes: MAX_EVIDENCE_TOTAL_BYTES,
  }).bytes;
  assertCritical(
    canonicalJson(bytesIdentity(actual)) === canonicalJson({
        byte_length: validated.byte_length,
        sha256: validated.sha256,
      }),
    "IDENTITY_MISMATCH",
    `${label} actual bytes do not equal the declared identity`,
  );
  return { descriptor: validated, bytes: actual };
}

function readExactBoundArtifact({
  evidence_handle,
  descriptor,
  expected_bytes,
  label,
}) {
  assertCritical(
    Buffer.isBuffer(expected_bytes),
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${label} expected bytes are missing`,
  );
  const actual = readBoundArtifactFromOwnedRoot({
    evidence_handle,
    descriptor,
    label,
  });
  assertCritical(
    actual.bytes.equals(expected_bytes),
    "IDENTITY_MISMATCH",
    `${label} actual bytes do not equal the expected bytes`,
  );
  return actual.descriptor;
}

function validateAndReadIdentityList({
  evidence_handle,
  value,
  expected_length,
  label,
}) {
  assertCritical(
    Array.isArray(value) && value.length === expected_length,
    "ORDERED_IDENTITY_SET_INVALID",
    `${label} length is invalid`,
  );
  const artifacts = value.map((entry, index) => {
    let validated;
    try {
      validated = validateArtifactDescriptor(entry, `${label}[${index}]`);
    } catch {
      failCritical("ORDERED_IDENTITY_SET_INVALID", `${label} key set is invalid`);
    }
    return readBoundArtifactFromOwnedRoot({
      evidence_handle,
      descriptor: validated,
      label: `${label}[${index}]`,
    });
  });
  assertCritical(
    new Set(artifacts.map((entry) => entry.descriptor.path)).size
      === artifacts.length,
    "ORDERED_IDENTITY_SET_INVALID",
    `${label} contains duplicate artifact paths`,
  );
  return artifacts;
}

export function closeCellEvidence({
  evidence_handle,
  relative_path,
  join,
  request_record_identity,
  admitted_response_identity,
  body_identity,
  admission_receipt_bytes,
  admission_receipt_identity,
  adapter_control_identity,
  p1_149_artifact_identities,
  p1_101_receipt_identities,
  b2_scan_proof_identity,
  outcome,
  outcome_reason,
  failure_stage = null,
  failure_receipt_bytes = null,
  failure_receipt_identity = null,
}) {
  assertCritical(
    outcome === "SUCCESS" || outcome === "FAILED",
    "ACCOUNTING_MISMATCH",
    "ordinary research outcome must be SUCCESS or FAILED",
  );
  assertCritical(
    typeof outcome_reason === "string"
      && outcome_reason.length > 0
      && outcome_reason.length <= 160,
    "ACCOUNTING_MISMATCH",
    "cell outcome reason is invalid",
  );
  assertCritical(
    (outcome === "SUCCESS" && outcome_reason === "PASS")
      || (
        outcome === "FAILED"
        && /^[A-Z][A-Z0-9_]{2,159}$/.test(outcome_reason)
      ),
    "ACCOUNTING_MISMATCH",
    "cell outcome reason does not match its closed outcome class",
  );
  const validatedJoin = validateJoin(join);
  const cellRoot = dirname(relative_path).split(sep).join("/");
  assertCritical(
    cellRoot !== "."
      && relative_path === `${cellRoot}/cell-closure.json`,
    "EVIDENCE_CROSS_BINDING_INVALID",
    "cell closure is not at the exact current-cell closure path",
  );
  const admittedIdentity = validateIdentity(admitted_response_identity);
  const bodyIdentity = validateIdentity(body_identity);
  const requestIdentity = validateIdentity(request_record_identity);
  const persistedReceipt = readExactBoundArtifact({
    evidence_handle,
    descriptor: admission_receipt_identity,
    expected_bytes: admission_receipt_bytes,
    label: "admission receipt",
  });
  const receiptIdentity = validateIdentity({
    byte_length: persistedReceipt.byte_length,
    sha256: persistedReceipt.sha256,
  });
  const receiptValue = parseRawJsonNoDuplicates(
    readBoundArtifactFromOwnedRoot({
      evidence_handle,
      descriptor: persistedReceipt,
      label: "admission receipt",
    }).bytes,
    "admission receipt",
    "EVIDENCE_CROSS_BINDING_INVALID",
  );
  try {
    exactKeys(receiptValue, ADMISSION_RECEIPT_KEYS, "admission receipt");
  } catch {
    failCritical(
      "EVIDENCE_CROSS_BINDING_INVALID",
      "admission receipt key set drifted at cell closure",
    );
  }
  assertCritical(
    receiptValue.schema_version === "p1-165-admission-receipt/v1"
      && receiptValue.task_id === TASK_ID
      && receiptValue.status === "ADMITTED"
      && canonicalJson(validateJoin(receiptValue.join))
        === canonicalJson(validatedJoin)
      && canonicalJson(validateIdentity(receiptValue.request_record_identity))
        === canonicalJson(requestIdentity)
      && canonicalJson(validateIdentity({
        byte_length: receiptValue.admitted_response?.byte_length,
        sha256: receiptValue.admitted_response?.sha256,
      }))
        === canonicalJson(admittedIdentity)
      && canonicalJson(validateIdentity(receiptValue.body_identity))
        === canonicalJson(bodyIdentity)
      && canonicalJson(bytesIdentity(admission_receipt_bytes))
        === canonicalJson(receiptIdentity),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "cell closure inputs do not bind the exact admission receipt",
  );
  const persistedRequestRecord = readBoundArtifactFromOwnedRoot({
    evidence_handle,
    descriptor: receiptValue.supporting_artifacts?.request_record,
    label: "admission supporting request record",
  });
  const persistedContextRecord = readBoundArtifactFromOwnedRoot({
    evidence_handle,
    descriptor: receiptValue.supporting_artifacts?.context_record,
    label: "admission supporting context record",
  });
  const persistedRequestBody = readBoundArtifactFromOwnedRoot({
    evidence_handle,
    descriptor: receiptValue.supporting_artifacts?.request_body,
    label: "admission supporting request body",
  });
  const persistedTransport = readBoundArtifactFromOwnedRoot({
    evidence_handle,
    descriptor: receiptValue.supporting_artifacts?.transport_record,
    label: "admission supporting transport record",
  });
  const persistedAdmittedResponse = readBoundArtifactFromOwnedRoot({
    evidence_handle,
    descriptor: receiptValue.admitted_response,
    label: "admitted response",
  });
  const contextValue = parseClosedContextRecord(
    persistedContextRecord.bytes,
    { expected_join: validatedJoin },
  );
  const requestValue = parseClosedRequestRecord(
    persistedRequestRecord.bytes,
    {
      expected_join: validatedJoin,
      expected_context_identity: contextValue.identity,
    },
  );
  const transportValue = parseClosedTransportRecord(
    persistedTransport.bytes,
    {
      join: validatedJoin,
      request_record_identity: requestIdentity,
      policy: requestValue.value.policy,
    },
  );
  assertCritical(
    canonicalJson(bytesIdentity(persistedRequestRecord.bytes))
        === canonicalJson(requestIdentity)
      && canonicalJson(bytesIdentity(persistedRequestBody.bytes))
        === canonicalJson(validateIdentity(receiptValue.request_body_identity))
      && canonicalJson(bytesIdentity(persistedAdmittedResponse.bytes))
        === canonicalJson(admittedIdentity)
      && canonicalJson(validateIdentity(transportValue.body_identity))
        === canonicalJson(bodyIdentity),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "cell closure does not bind persisted request, response, and body Evidence",
  );
  try {
    exactKeys(
      receiptValue.supporting_artifacts,
      SUPPORTING_ARTIFACT_KEYS,
      "admission supporting artifacts",
    );
  } catch {
    failCritical(
      "EVIDENCE_CROSS_BINDING_INVALID",
      "admission supporting artifact set is not closed",
    );
  }
  const supportingDescriptors = SUPPORTING_ARTIFACT_KEYS.map((key, index) =>
    validateArtifactDescriptor(
      receiptValue.supporting_artifacts[key],
      `supporting artifact[${index}]`,
    )
  );
  assertCritical(
    persistedReceipt.path === `${cellRoot}/admission/admission-receipt.json`
      && persistedAdmittedResponse.descriptor.path
        === `${cellRoot}/admission/admitted-response.http`
      && supportingDescriptors.every(
        (descriptor) => descriptor.path.startsWith(`${cellRoot}/`),
      ),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "admission Evidence is not bound to the same cell root as its closure",
  );
  let validatedFailureStage = null;
  let validatedFailureReceipt = null;
  let expectedP1149Count = 24;
  let expectedP1101Count = 2;
  if (outcome === "SUCCESS") {
    assertCritical(
      failure_stage === null
        && failure_receipt_bytes === null
        && failure_receipt_identity === null,
      "ACCOUNTING_MISMATCH",
      "successful cell cannot carry failure stage or receipt",
    );
  } else {
    validatedFailureStage = validateResearchFailureStage(failure_stage);
    assertCritical(
      Buffer.isBuffer(failure_receipt_bytes)
        && failure_receipt_identity !== null,
      "ACCOUNTING_MISMATCH",
      "failed cell requires exact research failure receipt bytes and descriptor",
    );
    validatedFailureReceipt = readExactBoundArtifact({
      evidence_handle,
      descriptor: failure_receipt_identity,
      expected_bytes: failure_receipt_bytes,
      label: "research failure receipt",
    });
    assertCritical(
      validatedFailureReceipt.path !== relative_path,
      "EVIDENCE_CROSS_BINDING_INVALID",
      "research failure receipt path collides with cell closure path",
    );
    assertCritical(
      validatedFailureReceipt.path
        === `${cellRoot}/research-failure-receipt.json`,
      "EVIDENCE_CROSS_BINDING_INVALID",
      "research failure receipt is not bound to the same cell root",
    );
    const failureReceipt = parseRawJsonNoDuplicates(
      failure_receipt_bytes,
      "research failure receipt",
      "EVIDENCE_CROSS_BINDING_INVALID",
    );
    try {
      exactKeys(
        failureReceipt,
        RESEARCH_FAILURE_RECEIPT_KEYS,
        "research failure receipt",
      );
    } catch {
      failCritical(
        "EVIDENCE_CROSS_BINDING_INVALID",
        "research failure receipt key set drifted at cell closure",
      );
    }
    assertCritical(
      failureReceipt.schema_version === "p1-165-research-failure-receipt/v1"
        && failureReceipt.task_id === TASK_ID
        && failureReceipt.status === "FAILED"
        && failureReceipt.response_admitted === true
        && failureReceipt.worker_success_fields_trusted === false
        && failureReceipt.failure_stage === validatedFailureStage
        && failureReceipt.reason_code === outcome_reason
        && canonicalJson(validateJoin(failureReceipt.join))
          === canonicalJson(validatedJoin)
        && canonicalJson(validateIdentity(
          failureReceipt.admission_receipt_identity,
        )) === canonicalJson(receiptIdentity),
      "EVIDENCE_CROSS_BINDING_INVALID",
      "research failure receipt does not bind the exact failed cell",
    );
    if (EARLY_RESEARCH_FAILURE_STAGES.has(validatedFailureStage)) {
      expectedP1149Count = 0;
      expectedP1101Count = 0;
    }
  }
  const adapterArtifact = readBoundArtifactFromOwnedRoot({
    evidence_handle,
    descriptor: adapter_control_identity,
    label: "adapter control identity",
  });
  const p1149Artifacts = validateAndReadIdentityList({
    evidence_handle,
    value: p1_149_artifact_identities,
    expected_length: expectedP1149Count,
    label: "P1-149 artifact identities",
  });
  const p1101Artifacts = validateAndReadIdentityList({
    evidence_handle,
    value: p1_101_receipt_identities,
    expected_length: expectedP1101Count,
    label: "P1-101 receipt identities",
  });
  const p1149Identities = p1149Artifacts.map((entry) => entry.descriptor);
  const p1101Identities = p1101Artifacts.map((entry) => entry.descriptor);
  if (expectedP1149Count === EXECUTION_ARTIFACT_KEYS.length) {
    const expectedSpineRoot = `${cellRoot}/spine`;
    assertCritical(
      p1149Artifacts.every(
        (entry, index) =>
          basename(entry.descriptor.path) === EXECUTION_ARTIFACT_KEYS[index]
          && dirname(entry.descriptor.path).split(sep).join("/")
            === expectedSpineRoot,
      )
        && new Set(p1149Artifacts.map(
          (entry) => dirname(entry.descriptor.path),
        )).size === 1,
      "ORDERED_IDENTITY_SET_INVALID",
      "P1-149 artifacts are not the exact ordered execution-spine set",
    );
    const providerResponse = p1149Artifacts[
      EXECUTION_ARTIFACT_KEYS.indexOf("provider-response.json")
    ];
    const reconstructedTransport = analyzeTransport({
      join: validatedJoin,
      request_record_identity: requestIdentity,
      chunks: [persistedAdmittedResponse.bytes],
      eof: true,
      stream_terminal_events: [],
      policy: requestValue.value.policy,
      observed_peer: transportValue.observed_peer,
    });
    assertCritical(
      providerResponse.bytes.equals(reconstructedTransport.body_bytes)
        && canonicalJson(bytesIdentity(providerResponse.bytes))
          === canonicalJson(bodyIdentity),
      "EVIDENCE_CROSS_BINDING_INVALID",
      "execution spine provider response is not the exact admitted body",
    );
  }
  const p1149ByPath = new Map(
    p1149Identities.map((entry) => [entry.path, entry]),
  );
  assertCritical(
    p1101Identities.every((entry) => (
      p1149ByPath.has(entry.path)
      && canonicalJson(p1149ByPath.get(entry.path)) === canonicalJson(entry)
    )),
    "ORDERED_IDENTITY_SET_INVALID",
    "P1-101 receipts are not an exact distinct subset of P1-149 artifacts",
  );
  const spinePaths = new Set(p1149Identities.map((entry) => entry.path));
  assertCritical(
    !spinePaths.has(adapterArtifact.descriptor.path),
    "ORDERED_IDENTITY_SET_INVALID",
    "adapter control path collides with the accepted spine",
  );
  let validatedB2Child = null;
  if (validatedJoin.profile_id.startsWith("B2_")) {
    assertCritical(
      b2_scan_proof_identity !== null
        && b2_scan_proof_identity !== undefined,
      "ACCOUNTING_MISMATCH",
      "B2 cell requires one exact repository scan proof",
    );
    validatedB2Child = readBoundArtifactFromOwnedRoot({
      evidence_handle,
      descriptor: b2_scan_proof_identity,
      label: "B2 scan proof identity",
    }).descriptor;
    assertCritical(
      validatedB2Child.path !== adapterArtifact.descriptor.path
        && !spinePaths.has(validatedB2Child.path),
      "ORDERED_IDENTITY_SET_INVALID",
      "B2 scan child path collides with adapter or spine Evidence",
    );
  } else {
    assertCritical(
      b2_scan_proof_identity === null,
      "ACCOUNTING_MISMATCH",
      "B0/B1 cell must not carry a B2 scan proof",
    );
  }
  const occupiedPaths = new Set([
    persistedReceipt.path,
    persistedContextRecord.descriptor.path,
    persistedRequestRecord.descriptor.path,
    persistedRequestBody.descriptor.path,
    persistedTransport.descriptor.path,
    persistedAdmittedResponse.descriptor.path,
    adapterArtifact.descriptor.path,
    ...p1149Identities.map((entry) => entry.path),
    ...(validatedB2Child === null ? [] : [validatedB2Child.path]),
  ]);
  assertCritical(
    !occupiedPaths.has(relative_path)
      && (
        validatedFailureReceipt === null
        || (
          !occupiedPaths.has(validatedFailureReceipt.path)
          && validatedFailureReceipt.path !== relative_path
        )
      ),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "closure or failure receipt path collides with bound cell Evidence",
  );
  const closure = {
    schema_version: "p1-165-cell-closure/v2",
    task_id: TASK_ID,
    join: validatedJoin,
    request_record_identity: requestIdentity,
    admitted_response_identity: admittedIdentity,
    body_identity: bodyIdentity,
    denominator_included: true,
    admission_receipt_identity: receiptIdentity,
    adapter_control_identity: adapterArtifact.descriptor,
    p1_149_artifact_identities: p1149Identities,
    p1_101_receipt_identities: p1101Identities,
    b2_scan_proof_identity: validatedB2Child,
    outcome,
    outcome_reason,
    failure_stage: validatedFailureStage,
    failure_receipt_identity: validatedFailureReceipt,
    worker_success_fields_trusted: false,
  };
  try {
    exactKeys(closure, CLOSURE_KEYS, "cell closure");
    const closureBytes = canonicalBytes(closure);
    writeAdmissionArtifacts({
      evidence_handle,
      artifacts: [{ relative_path, bytes: closureBytes }],
    });
    return { path: relative_path, ...bytesIdentity(closureBytes) };
  } catch (error) {
    mapCoreFailure(error);
  }
}

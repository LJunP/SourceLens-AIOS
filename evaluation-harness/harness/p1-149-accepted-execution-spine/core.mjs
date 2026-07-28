import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  closeSync,
  constants as fsConstants,
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import {
  dirname,
  isAbsolute,
  join,
  posix,
  relative,
  resolve,
  sep,
} from "node:path";
import { fileURLToPath } from "node:url";

export const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
export const FALSE_EXTERNAL_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
export const MAX_ARTIFACT_BYTES = 1024 * 1024;
export const MAX_COMMAND_OUTPUT_BYTES = 4 * 1024 * 1024;

export class P1149NonPass extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = "P1149NonPass";
    this.code = code;
    this.details = details;
  }
}

export function fail(code, message, details = null) {
  throw new P1149NonPass(code, message, details);
}

export function assert(condition, code, message, details = null) {
  if (!condition) fail(code, message, details);
}

export function sha256(bytes) {
  assert(Buffer.isBuffer(bytes), "IDENTITY_INVALID", "SHA-256 input must be bytes");
  return createHash("sha256").update(bytes).digest("hex");
}

export function canonicalJson(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    assert(Number.isFinite(value), "CANONICAL_JSON_INVALID", "non-finite JSON number");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  assert(
    value !== null && typeof value === "object" && !Buffer.isBuffer(value),
    "CANONICAL_JSON_INVALID",
    "unsupported canonical JSON value",
  );
  return `{${Object.keys(value).sort().map(
    (key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`,
  ).join(",")}}`;
}

export function canonicalBytes(value) {
  return Buffer.from(`${canonicalJson(value)}\n`, "utf8");
}

export function exactKeys(value, keys, label) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "SCHEMA_INVALID",
    `${label} must be an object`,
  );
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  assert(
    canonicalJson(actual) === canonicalJson(expected),
    "SCHEMA_INVALID",
    `${label} key set is not closed`,
    { actual, expected },
  );
  return value;
}

export function parseCanonicalJsonBytes(bytes, label = "JSON artifact") {
  assert(Buffer.isBuffer(bytes), "JSON_INVALID", `${label} must be bytes`);
  assert(bytes.length > 0 && bytes.length <= MAX_ARTIFACT_BYTES, "JSON_INVALID", `${label} size is invalid`);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("JSON_INVALID", `${label} is not exact UTF-8`);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch (error) {
    fail("JSON_INVALID", `${label} is not valid JSON: ${error.message}`);
  }
  assert(
    bytes.equals(canonicalBytes(value)),
    "JSON_NOT_CANONICAL",
    `${label} must be recursively key-sorted canonical JSON with one trailing LF`,
  );
  return value;
}

export function bytesIdentity(bytes) {
  return { sha256: sha256(bytes), byte_length: bytes.length };
}

export function fileIdentity(path, root = null) {
  const absolute = safeRegularFile(path, "identity input");
  const bytes = readFileSync(absolute);
  return {
    path: root === null ? absolute : portableRelative(root, absolute),
    ...bytesIdentity(bytes),
  };
}

function pathComponents(absolutePath) {
  const absolute = resolve(absolutePath);
  const root = resolve(sep);
  const rel = relative(root, absolute);
  const components = rel === "" ? [] : rel.split(sep);
  const result = [];
  let current = root;
  for (const component of components) {
    current = join(current, component);
    result.push(current);
  }
  return result;
}

export function safeExistingPath(path, label = "path") {
  assert(typeof path === "string" && isAbsolute(path), "PATH_INVALID", `${label} must be absolute`);
  const absolute = resolve(path);
  for (const component of pathComponents(absolute)) {
    assert(existsSync(component), "PATH_MISSING", `${label} is missing: ${component}`);
    assert(!lstatSync(component).isSymbolicLink(), "SYMLINK_REJECTED", `${label} contains a symlink`);
  }
  assert(realpathSync(absolute) === absolute, "PATH_IDENTITY_DRIFT", `${label} realpath drifted`);
  return absolute;
}

export function safeRealDirectory(path, label = "directory") {
  const absolute = safeExistingPath(path, label);
  const stat = lstatSync(absolute);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), "PATH_TYPE_REJECTED", `${label} is not a real directory`);
  return absolute;
}

export function safeRegularFile(path, label = "file", requireSingleLink = false) {
  const absolute = safeExistingPath(path, label);
  const stat = lstatSync(absolute);
  assert(stat.isFile() && !stat.isSymbolicLink(), "PATH_TYPE_REJECTED", `${label} is not a regular file`);
  if (requireSingleLink) {
    assert(stat.nlink === 1, "HARDLINK_REJECTED", `${label} must have one link`);
  }
  return absolute;
}

export function portableRelative(root, candidate) {
  const rel = relative(resolve(root), resolve(candidate));
  assert(
    rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel),
    "PATH_ESCAPE_REJECTED",
    "candidate escapes root",
  );
  return rel.split(sep).join("/");
}

export function validateArtifactPath(path, label = "artifact path") {
  assert(
    typeof path === "string"
      && path.length > 0
      && path.length <= 240
      && !isAbsolute(path)
      && !path.includes("\\")
      && !path.includes("\0")
      && posix.normalize(path) === path
      && !path.split("/").some((part) => part === "" || part === "." || part === ".."),
    "PATH_INVALID",
    `${label} is not a normalized POSIX relative path`,
  );
  return path;
}

export function containedPath(root, relativePath, label = "artifact") {
  const normalized = validateArtifactPath(relativePath, label);
  const candidate = resolve(root, ...normalized.split("/"));
  portableRelative(root, candidate);
  return candidate;
}

export function createOwnedRoot(path) {
  assert(typeof path === "string" && isAbsolute(path), "OWNED_ROOT_INVALID", "owned root must be absolute");
  const absolute = resolve(path);
  assert(!existsSync(absolute), "OWNED_ROOT_PREEXISTS", "owned root must be absent");
  const parent = safeRealDirectory(dirname(absolute), "owned root parent");
  assert(parent === dirname(absolute), "OWNED_ROOT_INVALID", "owned root parent identity drifted");
  mkdirSync(absolute, { recursive: false, mode: 0o700 });
  chmodSync(absolute, 0o700);
  const stat = lstatSync(absolute);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), "OWNED_ROOT_INVALID", "owned root is not a real directory");
  return Object.freeze({
    root: realpathSync(absolute),
    dev: stat.dev,
    ino: stat.ino,
    token: randomBytes(32).toString("hex"),
    owner_pid: process.pid,
  });
}

export function createDisposableRoot(label = "work") {
  assert(/^[a-z0-9-]+$/.test(label), "OWNED_ROOT_INVALID", "disposable label is invalid");
  const parent = safeRealDirectory(realpathSync(tmpdir()), "system temporary directory");
  const root = mkdtempSync(join(parent, `sourcelens-p1-149-${label}-`));
  chmodSync(root, 0o700);
  const stat = lstatSync(root);
  return Object.freeze({
    root: realpathSync(root),
    dev: stat.dev,
    ino: stat.ino,
    token: randomBytes(32).toString("hex"),
    owner_pid: process.pid,
  });
}

export function assertOwnedRoot(handle) {
  exactKeys(handle, ["root", "dev", "ino", "token", "owner_pid"], "owned root handle");
  assert(handle.owner_pid === process.pid, "OWNERSHIP_REJECTED", "owned root belongs to another process");
  assert(/^[0-9a-f]{64}$/.test(handle.token), "OWNERSHIP_REJECTED", "owned root token is invalid");
  const root = safeRealDirectory(handle.root, "owned root");
  const stat = lstatSync(root);
  assert(stat.dev === handle.dev && stat.ino === handle.ino, "OWNERSHIP_REJECTED", "owned root identity drifted");
  return root;
}

export function cleanupOwnedRoot(handle) {
  const root = assertOwnedRoot(handle);
  rmSync(root, { recursive: true, force: false, maxRetries: 0 });
  assert(!existsSync(root), "OWNED_CLEANUP_FAILED", "owned root remains after cleanup");
}

function ensureOwnedParent(handle, relativePath) {
  const root = assertOwnedRoot(handle);
  const destination = containedPath(root, relativePath);
  const relParent = relative(root, dirname(destination));
  let current = root;
  for (const component of relParent === "" ? [] : relParent.split(sep)) {
    current = join(current, component);
    if (!existsSync(current)) mkdirSync(current, { recursive: false, mode: 0o700 });
    const stat = lstatSync(current);
    assert(stat.isDirectory() && !stat.isSymbolicLink(), "SYMLINK_REJECTED", "artifact parent is not a real directory");
  }
  return destination;
}

export function writeBytesCreateOnce(handle, relativePath, bytes, mode = 0o600) {
  assert(Buffer.isBuffer(bytes), "ARTIFACT_INVALID", "artifact payload must be bytes");
  assert(bytes.length <= MAX_ARTIFACT_BYTES, "ARTIFACT_INVALID", "artifact exceeds byte limit");
  const destination = ensureOwnedParent(handle, relativePath);
  let descriptor;
  try {
    descriptor = openSync(destination, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, mode);
    writeFileSync(descriptor, bytes);
  } catch (error) {
    fail("CREATE_ONCE_FAILED", `create-once write failed for ${relativePath}: ${error.code ?? error.message}`);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  chmodSync(destination, mode);
  return { path: relativePath, ...bytesIdentity(bytes) };
}

export function writeJsonCreateOnce(handle, relativePath, value) {
  return writeBytesCreateOnce(handle, relativePath, canonicalBytes(value));
}

export function copyClosedTree(sourceRoot, destinationRoot) {
  const source = safeRealDirectory(sourceRoot, "copy source root");
  assert(!existsSync(destinationRoot), "COPY_DESTINATION_PREEXISTS", "copy destination must be absent");
  mkdirSync(destinationRoot, { recursive: false, mode: 0o700 });
  const visit = (sourceDir, destinationDir) => {
    for (const name of readdirSync(sourceDir).sort()) {
      const sourcePath = join(sourceDir, name);
      const sourceStat = lstatSync(sourcePath);
      assert(!sourceStat.isSymbolicLink(), "SYMLINK_REJECTED", "copy source contains a symlink");
      const destinationPath = join(destinationDir, name);
      if (sourceStat.isDirectory()) {
        mkdirSync(destinationPath, { recursive: false, mode: sourceStat.mode & 0o777 });
        visit(sourcePath, destinationPath);
      } else {
        assert(sourceStat.isFile(), "PATH_TYPE_REJECTED", "copy source contains a non-regular entry");
        copyFileSync(sourcePath, destinationPath, fsConstants.COPYFILE_EXCL);
        chmodSync(destinationPath, sourceStat.mode & 0o777);
      }
    }
  };
  visit(source, destinationRoot);
  return safeRealDirectory(destinationRoot, "copied root");
}

export function listClosedFiles(root) {
  const absoluteRoot = safeRealDirectory(root, "inventory root");
  const entries = [];
  const visit = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stat = lstatSync(path);
      assert(!stat.isSymbolicLink(), "SYMLINK_REJECTED", "inventory contains a symlink");
      if (stat.isDirectory()) {
        visit(path);
      } else {
        assert(stat.isFile(), "PATH_TYPE_REJECTED", "inventory contains a non-regular entry");
        const bytes = readFileSync(path);
        entries.push({
          path: portableRelative(absoluteRoot, path),
          type: "REGULAR_FILE",
          mode: (stat.mode & 0o777).toString(8).padStart(3, "0"),
          byte_length: bytes.length,
          sha256: sha256(bytes),
        });
      }
    }
  };
  visit(absoluteRoot);
  return entries.sort((left, right) => left.path.localeCompare(right.path));
}

export function directorySnapshot(root) {
  const entries = listClosedFiles(root);
  const bytes = canonicalBytes({
    schema_version: "p1-149-directory-snapshot/v1",
    entries,
  });
  return {
    entries,
    identity: bytesIdentity(bytes),
    bytes,
  };
}

export function applyFileBytesAtomic(root, operation) {
  const target = containedPath(root, operation.path, "patch target");
  const parent = safeRealDirectory(dirname(target), "patch target parent");
  const exists = existsSync(target);
  if (operation.op === "REPLACE_REGULAR_FILE") {
    assert(exists, "PREIMAGE_MISSING", "replace target is missing");
    const path = safeRegularFile(target, "replace target", true);
    const stat = lstatSync(path);
    const before = readFileSync(path);
    assert(
      (stat.mode & 0o777) === 0o644
        && before.length === operation.before.byte_length
        && sha256(before) === operation.before.sha256,
      "PREIMAGE_IDENTITY_MISMATCH",
      "replace target preimage drifted",
    );
  } else {
    assert(operation.op === "CREATE_REGULAR_FILE", "OPERATION_INVALID", "unsupported operation");
    assert(!exists, "CREATE_TARGET_EXISTS", "create target already exists");
  }
  const content = Buffer.from(operation.postimage.base64, "base64");
  const sidecar = join(parent, `.p1-149-${randomBytes(16).toString("hex")}.tmp`);
  let descriptor;
  try {
    descriptor = openSync(sidecar, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, 0o600);
    writeFileSync(descriptor, content);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  chmodSync(sidecar, 0o644);
  renameSync(sidecar, target);
  const after = safeRegularFile(target, "patch postimage", true);
  const afterBytes = readFileSync(after);
  assert(
    afterBytes.length === operation.postimage.byte_length
      && sha256(afterBytes) === operation.postimage.sha256,
    "POSTIMAGE_IDENTITY_MISMATCH",
    "patch postimage drifted",
  );
}

export function runBoundedCommand(argv, cwd, timeoutSeconds = 15) {
  assert(
    Array.isArray(argv) && argv.length > 0 && argv.every((item) => typeof item === "string" && !item.includes("\0")),
    "COMMAND_INVALID",
    "command argv is invalid",
  );
  assert(Number.isInteger(timeoutSeconds) && timeoutSeconds >= 1 && timeoutSeconds <= 60, "COMMAND_INVALID", "timeout invalid");
  const executable = safeRegularFile(argv[0], "command executable");
  const workingDirectory = safeRealDirectory(cwd, "command cwd");
  const environment = {
    PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    LANG: "C",
    LC_ALL: "C",
    TZ: "UTC",
    NODE_OPTIONS: "--no-warnings",
  };
  const startedAt = new Date().toISOString();
  const result = spawnSync(executable, argv.slice(1), {
    cwd: workingDirectory,
    shell: false,
    timeout: timeoutSeconds * 1000,
    maxBuffer: MAX_COMMAND_OUTPUT_BYTES,
    encoding: null,
    env: environment,
  });
  const stdout = Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0);
  const stderr = Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0);
  assert(!result.error || result.error.code !== "ETIMEDOUT", "COMMAND_TIMEOUT", "command timed out");
  return {
    schema_version: "p1-149-command-receipt/v1",
    argv: [executable, ...argv.slice(1)],
    cwd: workingDirectory,
    environment,
    started_at: startedAt,
    ended_at: new Date().toISOString(),
    exit_status: result.status,
    signal: result.signal,
    stdout: bytesIdentity(stdout),
    stdout_base64: stdout.toString("base64"),
    stderr: bytesIdentity(stderr),
    stderr_base64: stderr.toString("base64"),
  };
}

export function verifyIdentity(root, identity, label = "artifact identity") {
  exactKeys(identity, ["path", "sha256", "byte_length"], label);
  validateArtifactPath(identity.path, `${label}.path`);
  assert(/^[0-9a-f]{64}$/.test(identity.sha256), "IDENTITY_INVALID", `${label} SHA-256 invalid`);
  assert(Number.isInteger(identity.byte_length) && identity.byte_length >= 0, "IDENTITY_INVALID", `${label} length invalid`);
  const path = containedPath(root, identity.path, label);
  const regular = safeRegularFile(path, label, true);
  const bytes = readFileSync(regular);
  assert(
    bytes.length === identity.byte_length && sha256(bytes) === identity.sha256,
    "IDENTITY_MISMATCH",
    `${label} bytes drifted`,
  );
  return { path: regular, bytes };
}

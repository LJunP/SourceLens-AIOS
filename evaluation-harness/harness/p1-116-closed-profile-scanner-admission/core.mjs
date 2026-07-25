import {
  constants as fsConstants,
  closeSync,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { isAbsolute, relative, resolve, sep } from "node:path";

export class P116NonPass extends Error {
  constructor(code, message, evidence = null) {
    super(message);
    this.name = "P116NonPass";
    this.code = code;
    this.evidence = evidence;
  }
}

export function fail(code, message, evidence = null) {
  throw new P116NonPass(code, message, evidence);
}

export function assert(condition, code, message, evidence = null) {
  if (!condition) fail(code, message, evidence);
}

export function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]),
    );
  }
  return value;
}

export function canonicalBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalValue(value))}\n`, "utf8");
}

export function canonicalJson(value) {
  return canonicalBytes(value).toString("utf8");
}

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function exactKeys(value, keys, code, label) {
  assert(
    value && typeof value === "object" && !Array.isArray(value),
    code,
    `${label} must be an object`,
  );
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  assert(
    actual.length === expected.length
      && actual.every((key, index) => key === expected[index]),
    code,
    `${label} key set drifted`,
    { actual, expected },
  );
  return value;
}

export function assertAbsoluteNormalized(path, code, label) {
  assert(
    typeof path === "string" && isAbsolute(path) && resolve(path) === path,
    code,
    `${label} must be an absolute normalized path`,
  );
  return path;
}

export function assertContained(root, path, code = "PATH_ESCAPE_REJECTED") {
  const normalizedRoot = assertAbsoluteNormalized(resolve(root), code, "root");
  const normalizedPath = assertAbsoluteNormalized(resolve(path), code, "path");
  const rel = relative(normalizedRoot, normalizedPath);
  assert(
    rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel)),
    code,
    `path escapes owned root: ${normalizedPath}`,
  );
  return normalizedPath;
}

export function readRegularNoFollow(path, code = "INPUT_IDENTITY_INVALID") {
  assertAbsoluteNormalized(path, code, "input path");
  const flags = fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0);
  let descriptor;
  try {
    descriptor = openSync(path, flags);
    const opened = fstatSync(descriptor);
    assert(opened.isFile(), code, `input is not a regular file: ${path}`);
    const bytes = readFileSync(descriptor);
    const current = lstatSync(path);
    assert(
      !current.isSymbolicLink()
        && current.isFile()
        && String(current.dev) === String(opened.dev)
        && String(current.ino) === String(opened.ino),
      code,
      `input identity changed while reading: ${path}`,
    );
    return { bytes, stat: opened };
  } catch (error) {
    if (error instanceof P116NonPass) throw error;
    fail(code, `cannot read regular no-follow input: ${path}: ${error.message}`);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

export function fileIdentity(path, code = "INPUT_IDENTITY_INVALID") {
  const { bytes, stat } = readRegularNoFollow(path, code);
  return {
    path,
    sha256: sha256(bytes),
    byte_length: bytes.length,
    dev: String(stat.dev),
    ino: String(stat.ino),
    uid: stat.uid,
    gid: stat.gid,
    mode: stat.mode & 0o7777,
    type: "REGULAR_FILE",
  };
}

export function writeCreateOnce(path, bytes, mode = 0o600) {
  assertAbsoluteNormalized(path, "CREATE_ONCE_FAILED", "output path");
  const flags = fsConstants.O_WRONLY
    | fsConstants.O_CREAT
    | fsConstants.O_EXCL
    | (fsConstants.O_NOFOLLOW ?? 0);
  let descriptor;
  try {
    descriptor = openSync(path, flags, mode);
    writeFileSync(descriptor, bytes);
  } catch (error) {
    fail("CREATE_ONCE_FAILED", `exclusive output creation failed: ${path}: ${error.message}`);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  return fileIdentity(path, "CREATE_ONCE_FAILED");
}

export function parseJsonFile(path, code = "INPUT_JSON_INVALID") {
  const record = readRegularNoFollow(path, code);
  let value;
  try {
    value = JSON.parse(record.bytes.toString("utf8"));
  } catch (error) {
    fail(code, `invalid JSON: ${path}: ${error.message}`);
  }
  return {
    value,
    identity: {
      path,
      sha256: sha256(record.bytes),
      byte_length: record.bytes.length,
    },
  };
}

export function directoryIdentity(path, code = "DIRECTORY_IDENTITY_INVALID") {
  assertAbsoluteNormalized(path, code, "directory path");
  let current;
  try {
    current = lstatSync(path);
  } catch (error) {
    fail(code, `directory unavailable: ${path}: ${error.message}`);
  }
  assert(
    current.isDirectory() && !current.isSymbolicLink() && realpathSync(path) === path,
    code,
    `path is not a real directory: ${path}`,
  );
  return {
    path,
    dev: String(current.dev),
    ino: String(current.ino),
    uid: current.uid,
    gid: current.gid,
    mode: current.mode & 0o7777,
    type: "DIRECTORY",
  };
}

export function sameIdentity(actual, expected) {
  const keys = ["dev", "ino", "uid", "gid", "mode", "type"];
  return keys.every((key) => actual[key] === expected[key])
    && (expected.type !== "REGULAR_FILE"
      || (actual.sha256 === expected.sha256 && actual.byte_length === expected.byte_length));
}

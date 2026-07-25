import { createHash } from "node:crypto";
import {
  closeSync,
  constants as fsConstants,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
  realpathSync,
} from "node:fs";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { isDeepStrictEqual } from "node:util";

export const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;

export class P117QualityNonPass extends Error {
  constructor(reasonCode, detail = reasonCode) {
    super(detail);
    this.name = "P117QualityNonPass";
    this.reasonCode = reasonCode;
  }
}

export function fail(reasonCode, detail) {
  throw new P117QualityNonPass(reasonCode, detail);
}

export function assert(condition, reasonCode, detail) {
  if (!condition) fail(reasonCode, detail);
}

export function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function identityOf(bytes) {
  return { sha256: sha256(bytes), byte_length: bytes.length };
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (isObject(value)) {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
    );
  }
  assert(
    value === null
      || typeof value === "string"
      || typeof value === "boolean"
      || (typeof value === "number" && Number.isFinite(value)),
    "JSON_VALUE_INVALID",
  );
  return value;
}

export function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
}

export function exactKeys(value, keys, reasonCode) {
  assert(isObject(value), reasonCode);
  assert(
    isDeepStrictEqual(Object.keys(value).sort(), [...keys].sort()),
    reasonCode,
  );
}

export function parseCanonicalJson(bytes, reasonCode) {
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail(reasonCode);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail(reasonCode);
  }
  assert(bytes.equals(canonicalJsonBytes(value)), reasonCode);
  return value;
}

export function parseFrozenJson(bytes, reasonCode) {
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail(reasonCode);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail(reasonCode);
  }
  assert(
    text.endsWith("\n") && !text.includes("\r") && !text.endsWith("\n\n"),
    reasonCode,
  );
  return value;
}

export function validateIdentity(value, reasonCode) {
  exactKeys(value, ["path", "sha256", "byte_length"], reasonCode);
  assert(
    typeof value.path === "string"
      && value.path.length > 0
      && !isAbsolute(value.path)
      && !value.path.includes("\0")
      && !value.path.split("/").includes(".."),
    reasonCode,
  );
  assert(
    typeof value.sha256 === "string"
      && SHA256_PATTERN.test(value.sha256)
      && Number.isSafeInteger(value.byte_length)
      && value.byte_length >= 0,
    reasonCode,
  );
  return value;
}

function assertNoSymlinkChain(repositoryRoot, path, reasonCode) {
  const root = realpathSync(repositoryRoot);
  const target = resolve(path);
  const rel = relative(root, target);
  assert(
    rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel),
    reasonCode,
  );
  let current = root;
  for (const component of rel.split(sep).filter(Boolean)) {
    current = resolve(current, component);
    let stat;
    try {
      stat = lstatSync(current);
    } catch {
      fail(reasonCode);
    }
    assert(!stat.isSymbolicLink(), reasonCode);
  }
}

export function readBoundFile(repositoryRoot, binding, reasonCode) {
  validateIdentity(binding, reasonCode);
  const root = realpathSync(repositoryRoot);
  const path = resolve(root, binding.path);
  const rel = relative(root, path);
  assert(
    rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel),
    reasonCode,
  );
  assertNoSymlinkChain(root, dirname(path), reasonCode);
  let before;
  try {
    before = lstatSync(path);
  } catch {
    fail(reasonCode);
  }
  assert(before.isFile() && !before.isSymbolicLink() && before.nlink === 1, reasonCode);
  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  } catch {
    fail(reasonCode);
  }
  try {
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.nlink === 1
        && opened.dev === before.dev
        && opened.ino === before.ino,
      reasonCode,
    );
    const bytes = readFileSync(descriptor);
    const after = lstatSync(path);
    assert(
      after.isFile()
        && !after.isSymbolicLink()
        && after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && after.mtimeMs === opened.mtimeMs,
      reasonCode,
    );
    assert(
      sha256(bytes) === binding.sha256 && bytes.length === binding.byte_length,
      reasonCode,
    );
    return { path, bytes };
  } finally {
    closeSync(descriptor);
  }
}

export function readAbsoluteBoundFile(binding, reasonCode) {
  exactKeys(binding, ["path", "sha256", "byte_length"], reasonCode);
  assert(
    typeof binding.path === "string"
      && isAbsolute(binding.path)
      && resolve(binding.path) === binding.path
      && typeof binding.sha256 === "string"
      && SHA256_PATTERN.test(binding.sha256)
      && Number.isSafeInteger(binding.byte_length)
      && binding.byte_length >= 0,
    reasonCode,
  );
  let current = "/";
  for (const component of binding.path.split(sep).filter(Boolean)) {
    current = resolve(current, component);
    let stat;
    try {
      stat = lstatSync(current);
    } catch {
      fail(reasonCode);
    }
    assert(!stat.isSymbolicLink(), reasonCode);
  }
  const before = lstatSync(binding.path);
  assert(before.isFile() && before.nlink === 1, reasonCode);
  let descriptor;
  try {
    descriptor = openSync(binding.path, fsConstants.O_RDONLY | O_NOFOLLOW);
  } catch {
    fail(reasonCode);
  }
  try {
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.nlink === 1
        && opened.dev === before.dev
        && opened.ino === before.ino,
      reasonCode,
    );
    const bytes = readFileSync(descriptor);
    const after = lstatSync(binding.path);
    assert(
      after.isFile()
        && after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && after.mtimeMs === opened.mtimeMs,
      reasonCode,
    );
    assert(
      sha256(bytes) === binding.sha256 && bytes.length === binding.byte_length,
      reasonCode,
    );
    return { path: binding.path, bytes };
  } finally {
    closeSync(descriptor);
  }
}

export function sameJson(left, right) {
  return isDeepStrictEqual(canonicalize(left), canonicalize(right));
}

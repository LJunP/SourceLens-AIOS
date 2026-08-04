import { createHash, randomBytes } from "node:crypto";
import {
  closeSync,
  constants as fsConstants,
  existsSync,
  fsyncSync,
  linkSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import {
  dirname,
  isAbsolute,
  join,
  posix,
  relative,
  resolve,
  sep,
} from "node:path";

export const FALSE_EXTERNAL_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});

export const MANIFEST_EXCLUDED_PATHS = Object.freeze([
  "EVIDENCE_MANIFEST.json",
  "report/REPRODUCIBLE_BASELINE_REPORT.json",
  "report/REPORT_REBUILD_RECEIPT.json",
  "reviews/INDEPENDENT_EVALUATOR_RECEIPT.json",
]);

export class P1207NonPass extends Error {
  constructor(reasonCode, message, details = null) {
    super(message);
    this.name = "P1207NonPass";
    this.reasonCode = reasonCode;
    this.details = details;
  }
}

export function fail(reasonCode, message, details = null) {
  throw new P1207NonPass(reasonCode, message, details);
}

export function assert(condition, reasonCode, message, details = null) {
  if (!condition) fail(reasonCode, message, details);
}

export function sha256(bytes) {
  assert(Buffer.isBuffer(bytes), "IDENTITY_INPUT_INVALID", "SHA-256 input must be bytes");
  return createHash("sha256").update(bytes).digest("hex");
}

export function bytesIdentity(bytes) {
  return { sha256: sha256(bytes), byte_length: bytes.length };
}

export function canonicalJson(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    assert(Number.isFinite(value), "CANONICAL_JSON_INVALID", "non-finite number cannot be canonicalized");
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

export function exactKeys(value, keys, label = "object") {
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

function decodeUtf8(bytes, label) {
  assert(Buffer.isBuffer(bytes) && bytes.length > 0, "JSON_INVALID", `${label} must be non-empty bytes`);
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("JSON_UTF8_INVALID", `${label} is not exact UTF-8`);
  }
}

// Recursive descent is intentional here. JSON.parse alone silently accepts
// duplicate object members and rounds integers larger than 2^53 - 1.
export function parseExactJsonBytes(bytes, {
  label = "JSON input",
  canonical = false,
  maximumBytes = 4 * 1024 * 1024,
} = {}) {
  assert(
    Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= maximumBytes,
    "JSON_SIZE_INVALID",
    `${label} byte length is outside the accepted bound`,
  );
  const text = decodeUtf8(bytes, label);
  let cursor = 0;

  const skipWhitespace = () => {
    while (cursor < text.length && /[\x20\x09\x0a\x0d]/.test(text[cursor])) cursor += 1;
  };

  const parseString = () => {
    assert(text[cursor] === '"', "JSON_SYNTAX_INVALID", `${label} expected a string`);
    const start = cursor;
    cursor += 1;
    let escaped = false;
    while (cursor < text.length) {
      const character = text[cursor];
      cursor += 1;
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === "\\") {
        escaped = true;
        continue;
      }
      if (character === '"') {
        const lexeme = text.slice(start, cursor);
        try {
          return JSON.parse(lexeme);
        } catch (error) {
          fail("JSON_STRING_INVALID", `${label} contains an invalid string: ${error.message}`);
        }
      }
      assert(character.charCodeAt(0) >= 0x20, "JSON_STRING_INVALID", `${label} contains a control character`);
    }
    fail("JSON_SYNTAX_INVALID", `${label} contains an unterminated string`);
  };

  const parseNumber = () => {
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(text.slice(cursor));
    assert(match !== null, "JSON_NUMBER_INVALID", `${label} contains an invalid number`);
    const lexeme = match[0];
    cursor += lexeme.length;
    if (!/[.eE]/.test(lexeme)) {
      let integer;
      try {
        integer = BigInt(lexeme);
      } catch {
        fail("JSON_NUMBER_INVALID", `${label} contains an invalid integer`);
      }
      assert(
        integer >= BigInt(Number.MIN_SAFE_INTEGER) && integer <= BigInt(Number.MAX_SAFE_INTEGER),
        "JSON_INTEGER_UNSAFE",
        `${label} contains an integer outside the exact JavaScript range`,
      );
    }
    const value = Number(lexeme);
    assert(Number.isFinite(value), "JSON_NUMBER_NONFINITE", `${label} contains a non-finite number`);
    return value;
  };

  const parseValue = (depth = 0) => {
    assert(depth <= 256, "JSON_DEPTH_EXCEEDED", `${label} nesting is too deep`);
    skipWhitespace();
    const character = text[cursor];
    if (character === '"') return parseString();
    if (character === "{") {
      cursor += 1;
      skipWhitespace();
      const result = {};
      const keys = new Set();
      if (text[cursor] === "}") {
        cursor += 1;
        return result;
      }
      while (cursor < text.length) {
        skipWhitespace();
        const key = parseString();
        assert(!keys.has(key), "JSON_DUPLICATE_KEY", `${label} contains duplicate key ${JSON.stringify(key)}`);
        keys.add(key);
        skipWhitespace();
        assert(text[cursor] === ":", "JSON_SYNTAX_INVALID", `${label} expected ':'`);
        cursor += 1;
        result[key] = parseValue(depth + 1);
        skipWhitespace();
        if (text[cursor] === "}") {
          cursor += 1;
          return result;
        }
        assert(text[cursor] === ",", "JSON_SYNTAX_INVALID", `${label} expected ',' or '}'`);
        cursor += 1;
      }
      fail("JSON_SYNTAX_INVALID", `${label} contains an unterminated object`);
    }
    if (character === "[") {
      cursor += 1;
      skipWhitespace();
      const result = [];
      if (text[cursor] === "]") {
        cursor += 1;
        return result;
      }
      while (cursor < text.length) {
        result.push(parseValue(depth + 1));
        skipWhitespace();
        if (text[cursor] === "]") {
          cursor += 1;
          return result;
        }
        assert(text[cursor] === ",", "JSON_SYNTAX_INVALID", `${label} expected ',' or ']'`);
        cursor += 1;
      }
      fail("JSON_SYNTAX_INVALID", `${label} contains an unterminated array`);
    }
    if (text.startsWith("true", cursor)) {
      cursor += 4;
      return true;
    }
    if (text.startsWith("false", cursor)) {
      cursor += 5;
      return false;
    }
    if (text.startsWith("null", cursor)) {
      cursor += 4;
      return null;
    }
    if (character === "-" || /[0-9]/.test(character ?? "")) return parseNumber();
    fail("JSON_SYNTAX_INVALID", `${label} contains an unexpected token at byte ${Buffer.byteLength(text.slice(0, cursor))}`);
  };

  const value = parseValue();
  skipWhitespace();
  assert(cursor === text.length, "JSON_TRAILING_CONTENT", `${label} contains trailing content`);
  if (canonical) {
    assert(bytes.equals(canonicalBytes(value)), "JSON_NOT_CANONICAL", `${label} is not canonical JSON with one LF`);
  }
  return value;
}

export function normalizedRelativePath(value, label = "relative path") {
  assert(
    typeof value === "string"
      && value.length > 0
      && value.length <= 512
      && !isAbsolute(value)
      && !value.includes("\\")
      && !value.includes("\0")
      && posix.normalize(value) === value
      && !value.split("/").some((part) => part === "" || part === "." || part === ".."),
    "PATH_INVALID",
    `${label} is not a normalized POSIX relative path`,
  );
  return value;
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
    assert(existsSync(component), "PATH_MISSING", `${label} is missing`);
    assert(!lstatSync(component).isSymbolicLink(), "SYMLINK_REJECTED", `${label} contains a symlink`);
  }
  assert(realpathSync(absolute) === absolute, "PATH_IDENTITY_DRIFT", `${label} realpath drifted`);
  return absolute;
}

export function safeDirectory(path, label = "directory") {
  const absolute = safeExistingPath(path, label);
  const stat = lstatSync(absolute);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), "PATH_TYPE_REJECTED", `${label} is not a real directory`);
  return absolute;
}

export const safeRealDirectory = safeDirectory;

export function safeRegularFile(path, label = "file", options = {}) {
  const singleLink = typeof options === "boolean"
    ? options
    : options.singleLink ?? true;
  const absolute = safeExistingPath(path, label);
  const stat = lstatSync(absolute);
  assert(stat.isFile() && !stat.isSymbolicLink(), "PATH_TYPE_REJECTED", `${label} is not a regular file`);
  if (singleLink) assert(stat.nlink === 1, "HARDLINK_REJECTED", `${label} has multiple hard links`);
  return absolute;
}

export function containedPath(root, relativePath, label = "artifact") {
  const acceptedRoot = resolve(root);
  const normalized = normalizedRelativePath(relativePath, label);
  const candidate = resolve(acceptedRoot, ...normalized.split("/"));
  const rel = relative(acceptedRoot, candidate);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`), "PATH_ESCAPE_REJECTED", `${label} escapes root`);
  return candidate;
}

export function createOwnedRoot(path) {
  assert(typeof path === "string" && isAbsolute(path) && resolve(path) === path, "OWNED_ROOT_INVALID", "owned root must be normalized absolute");
  assert(!existsSync(path), "OWNED_ROOT_PREEXISTS", "owned root must be absent");
  safeDirectory(dirname(path), "owned root parent");
  mkdirSync(path, { recursive: false, mode: 0o700 });
  assert(realpathSync(path) === path, "OWNED_ROOT_INVALID", "owned root identity drifted after creation");
  return path;
}

function ensureOwnedParent(root, relativePath) {
  const acceptedRoot = safeDirectory(root, "Evidence root");
  const destination = containedPath(acceptedRoot, relativePath);
  const relParent = relative(acceptedRoot, dirname(destination));
  let current = acceptedRoot;
  for (const component of relParent === "" ? [] : relParent.split(sep)) {
    current = join(current, component);
    if (!existsSync(current)) mkdirSync(current, { recursive: false, mode: 0o700 });
    const stat = lstatSync(current);
    assert(stat.isDirectory() && !stat.isSymbolicLink(), "SYMLINK_REJECTED", "artifact parent is not a real directory");
  }
  return destination;
}

export function writeBytesCreateOnce(root, relativePath, bytes) {
  assert(Buffer.isBuffer(bytes), "ARTIFACT_BYTES_INVALID", "artifact must be bytes");
  const destination = ensureOwnedParent(root, relativePath);
  assert(!existsSync(destination), "CREATE_ONCE_FAILED", `artifact already exists: ${relativePath}`);
  const temporary = `${destination}.tmp-${process.pid}-${randomBytes(12).toString("hex")}`;
  let descriptor = null;
  try {
    descriptor = openSync(
      temporary,
      fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_NOFOLLOW,
      0o600,
    );
    writeFileSync(descriptor, bytes);
    fsyncSync(descriptor);
    closeSync(descriptor);
    descriptor = null;
    linkSync(temporary, destination);
    unlinkSync(temporary);
  } catch (error) {
    if (descriptor !== null) closeSync(descriptor);
    if (existsSync(temporary)) unlinkSync(temporary);
    fail("CREATE_ONCE_FAILED", `could not create ${relativePath}: ${error.message}`);
  }
  const written = readFileSync(safeRegularFile(destination, relativePath));
  assert(written.equals(bytes), "ARTIFACT_WRITE_DRIFT", `artifact bytes drifted: ${relativePath}`);
  return { path: relativePath, ...bytesIdentity(written) };
}

export function writeJsonCreateOnce(root, relativePath, value) {
  return writeBytesCreateOnce(root, relativePath, canonicalBytes(value));
}

export function readBoundFile(root, reference, label = "bound file") {
  exactKeys(reference, ["path", "sha256", "byte_length"], `${label} identity`);
  assert(
    /^[0-9a-f]{64}$/.test(reference.sha256)
      && Number.isInteger(reference.byte_length)
      && reference.byte_length >= 0,
    "IDENTITY_INVALID",
    `${label} identity fields are invalid`,
  );
  const path = safeRegularFile(containedPath(root, reference.path, label), label);
  const bytes = readFileSync(path);
  assert(
    bytes.length === reference.byte_length && sha256(bytes) === reference.sha256,
    "IDENTITY_MISMATCH",
    `${label} bytes do not match the bound identity`,
  );
  return { path, bytes };
}

export function readExternalBoundFile(reference, label = "external bound file") {
  exactKeys(reference, ["path", "sha256", "byte_length"], `${label} identity`);
  assert(isAbsolute(reference.path), "PATH_INVALID", `${label} path must be absolute`);
  const path = safeRegularFile(reference.path, label);
  const bytes = readFileSync(path);
  assert(
    bytes.length === reference.byte_length && sha256(bytes) === reference.sha256,
    "IDENTITY_MISMATCH",
    `${label} bytes do not match the bound identity`,
  );
  return { path, bytes };
}

export function listClosedInventory(root, { exclude = [] } = {}) {
  const acceptedRoot = safeDirectory(root, "inventory root");
  const excluded = new Set(exclude.map((entry) => normalizedRelativePath(entry, "excluded path")));
  const entries = [];
  const visit = (directory, prefix = "") => {
    for (const name of readdirSync(directory).sort()) {
      const relativePath = prefix === "" ? name : `${prefix}/${name}`;
      const path = join(directory, name);
      const stat = lstatSync(path);
      assert(!stat.isSymbolicLink(), "SYMLINK_REJECTED", `inventory contains symlink: ${relativePath}`);
      if (stat.isDirectory()) {
        visit(path, relativePath);
        continue;
      }
      assert(stat.isFile(), "PATH_TYPE_REJECTED", `inventory contains non-regular entry: ${relativePath}`);
      assert(stat.nlink === 1, "HARDLINK_REJECTED", `inventory contains hardlink: ${relativePath}`);
      if (excluded.has(relativePath)) continue;
      const bytes = readFileSync(path);
      entries.push({
        path: relativePath,
        type: "REGULAR_FILE",
        sha256: sha256(bytes),
        byte_length: bytes.length,
      });
    }
  };
  visit(acceptedRoot);
  entries.sort((left, right) => left.path.localeCompare(right.path));
  return entries;
}

export function buildClosedManifest(root, {
  exclude = MANIFEST_EXCLUDED_PATHS,
  taskId,
  rootRole,
} = {}) {
  const excludedPaths = [...exclude].sort();
  const entries = listClosedInventory(root, { exclude: excludedPaths });
  return {
    schema_version: "p1-207-evidence-manifest/v1",
    task_id: taskId,
    root_role: rootRole,
    excluded_paths: excludedPaths,
    entry_count: entries.length,
    entries,
  };
}

export function verifyClosedManifest(root, manifest, { exclude = MANIFEST_EXCLUDED_PATHS } = {}) {
  exactKeys(
    manifest,
    ["schema_version", "task_id", "root_role", "excluded_paths", "entry_count", "entries"],
    "Evidence manifest",
  );
  assert(manifest.schema_version === "p1-207-evidence-manifest/v1", "MANIFEST_SCHEMA_INVALID", "manifest schema is invalid");
  const excludedPaths = [...exclude].sort();
  assert(
    canonicalJson(manifest.excluded_paths) === canonicalJson(excludedPaths),
    "MANIFEST_EXCLUSION_DRIFT",
    "manifest exclusion set drifted",
  );
  const actual = listClosedInventory(root, { exclude: excludedPaths });
  assert(
    manifest.entry_count === actual.length
      && canonicalJson(manifest.entries) === canonicalJson(actual),
    "CLOSED_INVENTORY_DRIFT",
    "closed Evidence inventory differs from manifest",
  );
  return {
    schema_version: "p1-207-closed-inventory-verification/v1",
    status: "PASS",
    entry_count: actual.length,
    manifest_identity: bytesIdentity(canonicalBytes(manifest)),
    excluded_paths: excludedPaths,
  };
}

export function artifactIdentityAt(root, relativePath) {
  const path = safeRegularFile(containedPath(root, relativePath, "artifact"), "artifact");
  const bytes = readFileSync(path);
  return { path: relativePath, ...bytesIdentity(bytes) };
}

export function assertNoSecretBytes(root, secretBytes) {
  assert(Buffer.isBuffer(secretBytes) && secretBytes.length >= 1, "SECRET_INPUT_INVALID", "Secret input must be bytes");
  const entries = listClosedInventory(root, { exclude: [] });
  for (const entry of entries) {
    const bytes = readFileSync(containedPath(root, entry.path));
    assert(!bytes.includes(secretBytes), "SECRET_PERSISTED", `Secret bytes were found in ${entry.path}`);
  }
  return true;
}

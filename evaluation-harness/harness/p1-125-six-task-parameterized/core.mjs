import { createHash, randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  realpathSync,
  statSync,
  writeFileSync,
  closeSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

export const FALSE_EXTERNAL_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});

export const MAX_CAPTURE_BYTES = 4 * 1024 * 1024;

export class ConformanceNonPass extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = "ConformanceNonPass";
    this.code = code;
    this.details = details;
  }
}

export function fail(code, message, details = null) {
  throw new ConformanceNonPass(code, message, details);
}

export function assert(condition, code, message, details = null) {
  if (!condition) fail(code, message, details);
}

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function canonicalJson(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    assert(Number.isFinite(value), "INVALID_JSON_VALUE", "non-finite number is not canonical JSON");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  assert(
    typeof value === "object" && !Buffer.isBuffer(value),
    "INVALID_JSON_VALUE",
    "unsupported canonical JSON value",
  );
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
}

export function canonicalBytes(value) {
  return Buffer.from(`${canonicalJson(value)}\n`, "utf8");
}

export function exactKeys(value, keys, label) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "INVALID_RECORD_SHAPE",
    `${label} must be an object`,
  );
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  assert(
    canonicalJson(actual) === canonicalJson(expected),
    "INVALID_RECORD_SHAPE",
    `${label} key set is not closed`,
    { actual, expected },
  );
}

export function parseJsonBytes(bytes, label = "JSON input") {
  assert(Buffer.isBuffer(bytes), "INVALID_JSON", `${label} is not bytes`);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("INVALID_JSON", `${label} is not exact UTF-8`);
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    fail("INVALID_JSON", `${label} is not valid JSON: ${error.message}`);
  }
}

export function readJson(path, label = path) {
  return parseJsonBytes(readFileSync(path), label);
}

export function assertFalseEffects(value, label = "external effects") {
  exactKeys(value, Object.keys(FALSE_EXTERNAL_EFFECTS), label);
  assert(
    canonicalJson(value) === canonicalJson(FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_REQUEST_REJECTED",
    `${label} must remain all false`,
  );
}

function pathComponents(absolutePath) {
  const resolved = resolve(absolutePath);
  const root = resolve(sep);
  const relativePath = relative(root, resolved);
  const parts = relativePath === "" ? [] : relativePath.split(sep);
  const paths = [];
  let current = root;
  for (const part of parts) {
    current = join(current, part);
    paths.push(current);
  }
  return paths;
}

export function assertExistingPathWithoutSymlink(path, label = path) {
  assert(isAbsolute(path), "PATH_NOT_ABSOLUTE", `${label} must be absolute`);
  for (const component of pathComponents(path)) {
    assert(existsSync(component), "PATH_MISSING", `${label} ancestor is missing: ${component}`);
    assert(!lstatSync(component).isSymbolicLink(), "SYMLINK_REJECTED", `${label} contains a symlink: ${component}`);
  }
  return realpathSync(path);
}

export function assertContained(root, candidate, label = candidate) {
  const absoluteRoot = resolve(root);
  const absoluteCandidate = resolve(candidate);
  const rel = relative(absoluteRoot, absoluteCandidate);
  assert(
    rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`),
    "PATH_ESCAPE_REJECTED",
    `${label} escapes owned root`,
  );
  return absoluteCandidate;
}

export function assertRelativeArtifactPath(path, label = "artifact path") {
  assert(
    typeof path === "string"
      && path.length > 0
      && !isAbsolute(path)
      && !path.split(/[\\/]/).includes("..")
      && !path.includes("\0"),
    "PATH_ESCAPE_REJECTED",
    `${label} must be a contained relative path`,
  );
  return path;
}

export function createOwnedOutputRoot(outputPath) {
  assert(typeof outputPath === "string" && isAbsolute(outputPath), "OUTPUT_ROOT_INVALID", "output root must be absolute");
  assert(!existsSync(outputPath), "OUTPUT_ROOT_PREEXISTS", "output root must be absent");
  const parent = dirname(resolve(outputPath));
  let parentReal;
  try {
    parentReal = assertExistingPathWithoutSymlink(parent, "output parent");
  } catch (error) {
    fail(
      "OUTPUT_ROOT_INVALID",
      `output parent must exist and contain no symlink component: ${error.message}`,
    );
  }
  assert(parentReal === parent, "OUTPUT_ROOT_PARENT_DRIFT", "output parent realpath drifted");

  try {
    mkdirSync(outputPath, { recursive: false, mode: 0o700 });
  } catch (error) {
    fail("OUTPUT_ROOT_CREATE_FAILED", `atomic output-root creation failed: ${error.code ?? error.message}`);
  }
  const stat = lstatSync(outputPath);
  assert(stat.isDirectory() && !stat.isSymbolicLink(), "OUTPUT_ROOT_INVALID", "created output root is not a real directory");
  chmodSync(outputPath, 0o700);
  const token = randomBytes(32).toString("hex");
  return Object.freeze({
    root: realpathSync(outputPath),
    device: stat.dev,
    inode: stat.ino,
    token,
    owner_pid: process.pid,
  });
}

export function assertOwnedRoot(handle) {
  exactKeys(handle, ["root", "device", "inode", "token", "owner_pid"], "owned-root handle");
  assert(handle.owner_pid === process.pid, "NON_OWNED_ROOT_REJECTED", "output root belongs to a different process");
  assert(typeof handle.token === "string" && /^[0-9a-f]{64}$/.test(handle.token), "NON_OWNED_ROOT_REJECTED", "ownership token is invalid");
  const root = assertExistingPathWithoutSymlink(handle.root, "owned output root");
  const stat = statSync(root);
  assert(stat.isDirectory() && stat.dev === handle.device && stat.ino === handle.inode, "NON_OWNED_ROOT_REJECTED", "output-root identity drifted");
  return root;
}

function ensureParentDirectories(handle, relativePath) {
  const root = assertOwnedRoot(handle);
  const relativeArtifact = assertRelativeArtifactPath(relativePath);
  const destination = assertContained(root, join(root, relativeArtifact));
  const parent = dirname(destination);
  const parentRelative = relative(root, parent);
  let current = root;
  for (const part of parentRelative === "" ? [] : parentRelative.split(sep)) {
    current = join(current, part);
    if (!existsSync(current)) mkdirSync(current, { recursive: false, mode: 0o700 });
    assert(!lstatSync(current).isSymbolicLink() && statSync(current).isDirectory(), "SYMLINK_REJECTED", "artifact parent is not a real directory");
  }
  return destination;
}

export function writeOwnedBytesCreateOnce(handle, relativePath, bytes, mode = 0o600) {
  assert(Buffer.isBuffer(bytes), "INVALID_ARTIFACT", "artifact payload must be bytes");
  const destination = ensureParentDirectories(handle, relativePath);
  let descriptor;
  try {
    descriptor = openSync(destination, "wx", mode);
    writeFileSync(descriptor, bytes);
  } catch (error) {
    fail("CREATE_ONCE_WRITE_FAILED", `create-once artifact write failed: ${relativePath}: ${error.code ?? error.message}`);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  chmodSync(destination, mode);
  return {
    path: relativePath,
    sha256: sha256(bytes),
    byte_length: bytes.length,
  };
}

export function writeOwnedJsonCreateOnce(handle, relativePath, value) {
  return writeOwnedBytesCreateOnce(handle, relativePath, canonicalBytes(value));
}

export function readIdentity(reference, repositoryRoot) {
  exactKeys(reference, ["path", "sha256", "byte_length"], "file identity");
  assertRelativeArtifactPath(reference.path, "file identity path");
  assert(/^[0-9a-f]{64}$/.test(reference.sha256), "IDENTITY_INVALID", "file identity SHA-256 is invalid");
  assert(Number.isInteger(reference.byte_length) && reference.byte_length >= 0, "IDENTITY_INVALID", "file identity byte length is invalid");
  const root = assertExistingPathWithoutSymlink(repositoryRoot, "repository root");
  const path = assertContained(root, resolve(root, reference.path), reference.path);
  assertExistingPathWithoutSymlink(path, reference.path);
  const stat = statSync(path);
  assert(stat.isFile(), "IDENTITY_INVALID", `${reference.path} is not a regular file`);
  const bytes = readFileSync(path);
  assert(
    bytes.length === reference.byte_length && sha256(bytes) === reference.sha256,
    "IDENTITY_MISMATCH",
    `${reference.path} identity mismatch`,
  );
  return { path, bytes, value: parseJsonBytes(bytes, reference.path) };
}

function appendBounded(chunks, chunk, state, streamName, child) {
  state.bytes += chunk.length;
  if (state.bytes > MAX_CAPTURE_BYTES) {
    state.error = `${streamName} exceeded ${MAX_CAPTURE_BYTES} bytes`;
    child.kill("SIGKILL");
    return;
  }
  chunks.push(chunk);
}

export async function executeBoundedCommand({
  argv,
  cwd,
  timeoutSeconds,
  expectedExitCodes,
  environment = {},
}) {
  assert(
    Array.isArray(argv) && argv.length >= 1 && argv.every((item) => typeof item === "string" && !item.includes("\0")),
    "MALFORMED_ARGV_REJECTED",
    "argv must be a non-empty NUL-free string array",
  );
  assert(typeof cwd === "string" && isAbsolute(cwd), "WORKING_DIRECTORY_REJECTED", "working directory must be absolute");
  const realCwd = assertExistingPathWithoutSymlink(cwd, "working directory");
  assert(realCwd === resolve(cwd), "WORKING_DIRECTORY_REJECTED", "working directory realpath drifted");
  assert(
    Number.isInteger(timeoutSeconds) && timeoutSeconds >= 1 && timeoutSeconds <= 120,
    "TIMEOUT_CONTRACT_REJECTED",
    "timeout must be an integer in [1,120]",
  );
  assert(
    Array.isArray(expectedExitCodes)
      && expectedExitCodes.length >= 1
      && expectedExitCodes.every(Number.isInteger)
      && new Set(expectedExitCodes).size === expectedExitCodes.length,
    "EXPECTED_EXIT_CONTRACT_REJECTED",
    "expected-exit contract must be a unique non-empty integer array",
  );
  assert(
    environment !== null
      && typeof environment === "object"
      && !Array.isArray(environment)
      && Object.values(environment).every((value) => typeof value === "string"),
    "ENVIRONMENT_CONTRACT_REJECTED",
    "command environment must contain only strings",
  );

  const executable = assertExistingPathWithoutSymlink(argv[0], "command executable");
  assert(statSync(executable).isFile(), "EXECUTABLE_REJECTED", "command executable is not a regular file");
  const frozenArgv = Object.freeze([executable, ...argv.slice(1)]);
  const startedAt = new Date().toISOString();
  const startedMonotonic = process.hrtime.bigint();
  const stdoutChunks = [];
  const stderrChunks = [];
  const stdoutState = { bytes: 0, error: null };
  const stderrState = { bytes: 0, error: null };
  let timedOut = false;
  const child = spawn(frozenArgv[0], frozenArgv.slice(1), {
    cwd: realCwd,
    env: { LC_ALL: "C", TZ: "UTC", ...environment },
    shell: false,
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => appendBounded(stdoutChunks, chunk, stdoutState, "stdout", child));
  child.stderr.on("data", (chunk) => appendBounded(stderrChunks, chunk, stderrState, "stderr", child));
  const timeout = setTimeout(() => {
    timedOut = true;
    child.kill("SIGKILL");
  }, timeoutSeconds * 1000);
  const termination = await new Promise((resolvePromise, rejectPromise) => {
    child.once("error", rejectPromise);
    child.once("close", (exitStatus, signal) => resolvePromise({ exitStatus, signal }));
  }).finally(() => clearTimeout(timeout));
  if (stdoutState.error || stderrState.error) {
    fail("CAPTURE_LIMIT_EXCEEDED", stdoutState.error ?? stderrState.error);
  }
  const stdout = Buffer.concat(stdoutChunks);
  const stderr = Buffer.concat(stderrChunks);
  const endedAt = new Date().toISOString();
  const latencyMs = Number((process.hrtime.bigint() - startedMonotonic) / 1_000_000n);
  return {
    stdout,
    stderr,
    ledger: {
      schema_version: "1.0",
      record_type: "p1_125_bounded_command_ledger",
      argv: frozenArgv,
      cwd: realCwd,
      environment: { LC_ALL: "C", TZ: "UTC", ...environment },
      started_at: startedAt,
      ended_at: endedAt,
      latency_ms: latencyMs,
      timeout_seconds: timeoutSeconds,
      timed_out: timedOut,
      exit_status: termination.exitStatus,
      expected_exit_codes: [...expectedExitCodes],
      expected_exit_matched: !timedOut
        && termination.signal === null
        && expectedExitCodes.includes(termination.exitStatus),
      signal: termination.signal,
      stdout_sha256: sha256(stdout),
      stdout_byte_length: stdout.length,
      stderr_sha256: sha256(stderr),
      stderr_byte_length: stderr.length,
    },
  };
}

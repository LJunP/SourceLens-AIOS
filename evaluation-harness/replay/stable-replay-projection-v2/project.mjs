#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const EXPECTED_SCALAR_COUNT = 166;
const EXPECTED_SCALAR_TYPE_MAP_SHA256 =
  "830ac39ff24e505ee98b908cf1ed48eca5d126ed8ee65aced61a84288bd34f5f";
const EXPECTED_FULL_POINTER_COUNT = 182;
const EXPECTED_FULL_TYPE_MAP_SHA256 =
  "07beb1ff8847077517c6ebd9d11bcb29f4e37867a9e8bd61a6ed197e2f47451d";

const RUN_EVIDENCE_SUFFIX = "/candidate-owned/evidence/evidence.json";
const RUN_CHILD_SOURCE_SUFFIX = "/candidate-owned/source";
const SHA256_PATTERN = /^[0-9a-f]{64}$/;

const PHYSICAL_PATHS = [
  ["/runtime/executable_path", ["runtime", "executable_path"]],
  ["/runtime/executable_realpath", ["runtime", "executable_realpath"]],
  ["/runtime/logical_cwd", ["runtime", "logical_cwd"]],
  ["/runtime/child/executable_path", ["runtime", "child", "executable_path"]],
  ["/runtime/child/module_path", ["runtime", "child", "module_path"]],
  ["/runtime/child/logical_cwd", ["runtime", "child", "logical_cwd"]],
];

const PHYSICAL_POINTER_SET = new Set(PHYSICAL_PATHS.map(([pointer]) => pointer));

class NonPass extends Error {
  constructor(reason) {
    super(reason);
    this.name = "NonPass";
    this.reason = reason;
  }
}

function nonPass(reason) {
  throw new NonPass(reason);
}

function sha256Hex(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function compareStrings(left, right) {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function jsonType(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function canonicalJson(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) nonPass("INVALID_JSON_VALUE");
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }

  if (isObject(value)) {
    const keys = Object.keys(value).sort(compareStrings);
    return `{${keys
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  }

  nonPass("INVALID_JSON_VALUE");
}

function canonicalBytes(value, trailingLf = true) {
  return Buffer.from(`${canonicalJson(value)}${trailingLf ? "\n" : ""}`, "utf8");
}

class StrictJsonParser {
  constructor(text) {
    this.text = text;
    this.index = 0;
  }

  parse() {
    this.skipWhitespace();
    const value = this.parseValue();
    this.skipWhitespace();
    if (this.index !== this.text.length) nonPass("INVALID_JSON_VALUE");
    return value;
  }

  skipWhitespace() {
    while (this.index < this.text.length) {
      const character = this.text[this.index];
      if (
        character !== " " &&
        character !== "\t" &&
        character !== "\n" &&
        character !== "\r"
      ) {
        return;
      }
      this.index += 1;
    }
  }

  parseValue() {
    const character = this.text[this.index];
    if (character === "{") return this.parseObject();
    if (character === "[") return this.parseArray();
    if (character === '"') return this.parseString();
    if (character === "t") return this.parseKeyword("true", true);
    if (character === "f") return this.parseKeyword("false", false);
    if (character === "n") return this.parseKeyword("null", null);
    if (character === "-" || (character >= "0" && character <= "9")) {
      return this.parseNumber();
    }
    nonPass("INVALID_JSON_VALUE");
  }

  parseObject() {
    this.index += 1;
    this.skipWhitespace();
    const object = Object.create(null);
    const keys = new Set();

    if (this.text[this.index] === "}") {
      this.index += 1;
      return object;
    }

    while (this.index < this.text.length) {
      if (this.text[this.index] !== '"') nonPass("INVALID_JSON_VALUE");
      const key = this.parseString();
      if (keys.has(key)) nonPass("DUPLICATE_JSON_KEY");
      keys.add(key);

      this.skipWhitespace();
      if (this.text[this.index] !== ":") nonPass("INVALID_JSON_VALUE");
      this.index += 1;
      this.skipWhitespace();
      object[key] = this.parseValue();
      this.skipWhitespace();

      const separator = this.text[this.index];
      if (separator === "}") {
        this.index += 1;
        return object;
      }
      if (separator !== ",") nonPass("INVALID_JSON_VALUE");
      this.index += 1;
      this.skipWhitespace();
    }

    nonPass("INVALID_JSON_VALUE");
  }

  parseArray() {
    this.index += 1;
    this.skipWhitespace();
    const array = [];

    if (this.text[this.index] === "]") {
      this.index += 1;
      return array;
    }

    while (this.index < this.text.length) {
      array.push(this.parseValue());
      this.skipWhitespace();

      const separator = this.text[this.index];
      if (separator === "]") {
        this.index += 1;
        return array;
      }
      if (separator !== ",") nonPass("INVALID_JSON_VALUE");
      this.index += 1;
      this.skipWhitespace();
    }

    nonPass("INVALID_JSON_VALUE");
  }

  parseString() {
    const start = this.index;
    this.index += 1;

    while (this.index < this.text.length) {
      const character = this.text[this.index];
      if (character === '"') {
        this.index += 1;
        try {
          const value = JSON.parse(this.text.slice(start, this.index));
          if (typeof value !== "string") nonPass("INVALID_JSON_VALUE");
          return value;
        } catch (error) {
          if (error instanceof NonPass) throw error;
          nonPass("INVALID_JSON_VALUE");
        }
      }

      if (character === "\\") {
        this.index += 2;
        continue;
      }

      if (character.charCodeAt(0) < 0x20) nonPass("INVALID_JSON_VALUE");
      this.index += 1;
    }

    nonPass("INVALID_JSON_VALUE");
  }

  parseKeyword(keyword, value) {
    if (this.text.slice(this.index, this.index + keyword.length) !== keyword) {
      nonPass("INVALID_JSON_VALUE");
    }
    this.index += keyword.length;
    return value;
  }

  parseNumber() {
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(
      this.text.slice(this.index),
    );
    if (match === null) nonPass("INVALID_JSON_VALUE");

    const token = match[0];
    this.index += token.length;
    const next = this.text[this.index];
    if (
      next !== undefined &&
      next !== " " &&
      next !== "\t" &&
      next !== "\n" &&
      next !== "\r" &&
      next !== "," &&
      next !== "]" &&
      next !== "}"
    ) {
      nonPass("INVALID_JSON_VALUE");
    }

    const value = Number(token);
    if (!Number.isFinite(value)) nonPass("INVALID_JSON_VALUE");
    return value;
  }
}

function strictParseBytes(bytes) {
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xef &&
    bytes[1] === 0xbb &&
    bytes[2] === 0xbf
  ) {
    nonPass("INVALID_JSON_VALUE");
  }

  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    nonPass("INVALID_JSON_VALUE");
  }
  return new StrictJsonParser(text).parse();
}

function escapePointerComponent(component) {
  return component.replaceAll("~", "~0").replaceAll("/", "~1");
}

function collectPointerTypes(value) {
  const full = [];
  const scalar = [];
  const scalarValues = [];

  function visit(current, pointer) {
    const type = jsonType(current);
    const entry = { pointer, type };
    full.push(entry);

    if (type !== "object" && type !== "array") {
      scalar.push(entry);
      scalarValues.push({ pointer, type, value: current });
      return;
    }

    if (type === "array") {
      for (let index = 0; index < current.length; index += 1) {
        visit(current[index], `${pointer}/${index}`);
      }
      return;
    }

    for (const key of Object.keys(current)) {
      visit(current[key], `${pointer}/${escapePointerComponent(key)}`);
    }
  }

  visit(value, "");
  full.sort((left, right) => compareStrings(left.pointer, right.pointer));
  scalar.sort((left, right) => compareStrings(left.pointer, right.pointer));
  scalarValues.sort((left, right) => compareStrings(left.pointer, right.pointer));
  return { full, scalar, scalarValues };
}

function getPath(root, components) {
  let current = root;
  for (const component of components) {
    if (!isObject(current) && !Array.isArray(current)) return undefined;
    if (!Object.hasOwn(current, component)) return undefined;
    current = current[component];
  }
  return current;
}

function setPath(root, components, value) {
  let current = root;
  for (let index = 0; index < components.length - 1; index += 1) {
    current = current[components[index]];
  }
  current[components.at(-1)] = value;
}

function validateEvidenceShape(evidence) {
  const executableDigest = getPath(evidence, ["runtime", "executable_sha256"]);
  if (typeof executableDigest !== "string" || !SHA256_PATTERN.test(executableDigest)) {
    nonPass("EXECUTABLE_DIGEST_MISSING_OR_CHANGED");
  }

  const pointerTypes = collectPointerTypes(evidence);
  if (
    pointerTypes.scalar.length !== EXPECTED_SCALAR_COUNT ||
    pointerTypes.full.length !== EXPECTED_FULL_POINTER_COUNT
  ) {
    nonPass("POINTER_SET_MISMATCH");
  }

  const scalarHash = sha256Hex(canonicalBytes(pointerTypes.scalar));
  const fullHash = sha256Hex(canonicalBytes(pointerTypes.full));
  if (
    scalarHash !== EXPECTED_SCALAR_TYPE_MAP_SHA256 ||
    fullHash !== EXPECTED_FULL_TYPE_MAP_SHA256
  ) {
    nonPass("POINTER_TYPE_MISMATCH");
  }

  const expectedTopLevel = [
    "candidate_status",
    "case_id",
    "external_effects",
    "identities",
    "patch",
    "result",
    "rollback",
    "runtime",
    "schema_version",
    "task_id",
    "tests",
  ];
  const actualTopLevel = Object.keys(evidence).sort(compareStrings);
  if (canonicalJson(actualTopLevel) !== canonicalJson(expectedTopLevel)) {
    nonPass("POINTER_SET_MISMATCH");
  }

  if (evidence.schema_version !== "blind-admission-evidence/v1") {
    nonPass("EVIDENCE_SCHEMA_MISMATCH");
  }
  if (evidence.case_id.length === 0 || evidence.task_id.length === 0) {
    nonPass("EVIDENCE_SCHEMA_MISMATCH");
  }
  if (evidence.candidate_status !== "COMPLETED" && evidence.candidate_status !== "REJECTED") {
    nonPass("EVIDENCE_SCHEMA_MISMATCH");
  }

  return pointerTypes;
}

function validateAbsolutePosixPath(value) {
  if (typeof value !== "string" || !value.startsWith("/")) {
    nonPass("PATH_NOT_ABSOLUTE_POSIX");
  }
  if (value.includes("\u0000")) nonPass("PATH_LEXICAL_ALIAS");
  if (value.length > 1 && value.endsWith("/")) nonPass("PATH_LEXICAL_ALIAS");
  if (value.includes("//")) nonPass("PATH_LEXICAL_ALIAS");

  const components = value.slice(1).split("/");
  if (components.some((component) => component === "." || component === "..")) {
    nonPass("PATH_LEXICAL_ALIAS");
  }
}

function isWithinAtComponentBoundary(path, root) {
  if (path === root) return true;
  if (root === "/") return path.startsWith("/");
  return path.startsWith(`${root}/`);
}

function buildRoots(executable, candidateRoot, runRoot) {
  validateAbsolutePosixPath(executable);
  validateAbsolutePosixPath(candidateRoot);
  validateAbsolutePosixPath(runRoot);

  const rootValues = [executable, candidateRoot, runRoot];
  for (let left = 0; left < rootValues.length; left += 1) {
    for (let right = left + 1; right < rootValues.length; right += 1) {
      if (
        isWithinAtComponentBoundary(rootValues[left], rootValues[right]) ||
        isWithinAtComponentBoundary(rootValues[right], rootValues[left])
      ) {
        nonPass("ROOT_ROLE_OVERLAP");
      }
    }
  }

  return [
    { name: "EXECUTABLE", root: executable, token: "$EXECUTABLE", subpaths: false },
    {
      name: "CANDIDATE_ROOT",
      root: candidateRoot,
      token: "$CANDIDATE_ROOT",
      subpaths: true,
    },
    { name: "RUN_ROOT", root: runRoot, token: "$RUN_ROOT", subpaths: true },
  ];
}

function matchingRoles(path, roles) {
  return roles.filter((role) =>
    role.subpaths ? isWithinAtComponentBoundary(path, role.root) : path === role.root,
  );
}

function tokenizePhysicalPath(path, roles) {
  validateAbsolutePosixPath(path);
  const matches = matchingRoles(path, roles);
  if (matches.length !== 1) nonPass("PATH_ROLE_NOT_UNIQUE");
  const role = matches[0];
  return `${role.token}${path.slice(role.root.length)}`;
}

function requiredFlagValue(argv, flag, expectedValue) {
  const positions = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === flag) positions.push(index);
  }

  if (
    positions.length !== 1 ||
    positions[0] + 1 >= argv.length ||
    argv[positions[0] + 1] !== expectedValue
  ) {
    nonPass("ARGV_BINDING_MISMATCH");
  }
}

function validateAndTokenizeArgv(argv, executable, candidateRoot, runRoot, roles) {
  if (!Array.isArray(argv) || argv.some((value) => typeof value !== "string")) {
    nonPass("POINTER_TYPE_MISMATCH");
  }
  if (argv.length === 0 || argv[0] !== executable) nonPass("ARGV_BINDING_MISMATCH");

  requiredFlagValue(argv, "--owned-root", `${runRoot}/candidate-owned`);
  requiredFlagValue(argv, "--source-root", `${runRoot}/candidate-owned/source`);
  requiredFlagValue(argv, "--evidence-root", `${runRoot}/candidate-owned/evidence`);
  requiredFlagValue(argv, "--canonical-root", candidateRoot);
  requiredFlagValue(argv, "--logical-cwd", candidateRoot);

  return argv.map((value) => {
    if (!value.startsWith("/")) return value;
    return tokenizePhysicalPath(value, roles);
  });
}

function deriveRunRoot(evidencePath) {
  if (!evidencePath.endsWith(RUN_EVIDENCE_SUFFIX)) {
    nonPass("STDOUT_EVIDENCE_PATH_MISMATCH");
  }
  const runRoot = evidencePath.slice(0, -RUN_EVIDENCE_SUFFIX.length);
  if (runRoot.length === 0) nonPass("STDOUT_EVIDENCE_PATH_MISMATCH");
  return runRoot;
}

function validateStdoutValue(stdoutValue, evidence) {
  if (!isObject(stdoutValue)) nonPass("STDOUT_NOT_OBJECT");

  const keys = Object.keys(stdoutValue).sort(compareStrings);
  if (canonicalJson(keys) !== '["candidate_status","evidence_path"]') {
    nonPass("STDOUT_KEY_SET_MISMATCH");
  }
  if (
    typeof stdoutValue.candidate_status !== "string" ||
    typeof stdoutValue.evidence_path !== "string"
  ) {
    nonPass("STDOUT_VALUE_TYPE_MISMATCH");
  }
  if (stdoutValue.candidate_status !== evidence.candidate_status) {
    nonPass("STDOUT_STATUS_MISMATCH");
  }

  return deriveRunRoot(stdoutValue.evidence_path);
}

function normalizedStdoutBytes(candidateStatus) {
  const normalized = Object.create(null);
  normalized.candidate_status = candidateStatus;
  normalized.evidence_path = `$RUN_ROOT${RUN_EVIDENCE_SUFFIX}`;
  return canonicalBytes(normalized);
}

function isRepoRelativePointer(pointer) {
  return (
    pointer === "/patch/relative_path" ||
    /^\/result\/files\/(?:0|[1-9][0-9]*)\/path$/.test(pointer) ||
    /^\/result\/path_set\/(?:0|[1-9][0-9]*)$/.test(pointer)
  );
}

function validateRepoRelativePath(value) {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.startsWith("/") ||
    value.endsWith("/") ||
    value.includes("//") ||
    value.includes("\u0000")
  ) {
    nonPass("REPO_PATH_INVALID");
  }

  const components = value.split("/");
  if (
    components.some(
      (component) => component.length === 0 || component === "." || component === "..",
    )
  ) {
    nonPass("REPO_PATH_INVALID");
  }
}

function validateRepositoryAndUndeclaredPaths(scalarValues) {
  for (const entry of scalarValues) {
    if (isRepoRelativePointer(entry.pointer)) validateRepoRelativePath(entry.value);
  }

  for (const entry of scalarValues) {
    if (entry.type !== "string" || !entry.value.startsWith("/")) continue;
    if (PHYSICAL_POINTER_SET.has(entry.pointer)) continue;
    if (/^\/runtime\/ordered_argv\/(?:0|[1-9][0-9]*)$/.test(entry.pointer)) continue;
    if (entry.pointer === "/runtime/environment/PATH") continue;
    if (isRepoRelativePointer(entry.pointer)) continue;
    nonPass("UNDECLARED_ABSOLUTE_PATH_FIELD");
  }
}

function cloneJson(value) {
  if (Array.isArray(value)) return value.map((item) => cloneJson(item));
  if (isObject(value)) {
    const clone = Object.create(null);
    for (const key of Object.keys(value)) clone[key] = cloneJson(value[key]);
    return clone;
  }
  return value;
}

function parseCli(argv) {
  if (argv.length !== 4) nonPass("CLI_ARGUMENT_MISMATCH");
  const accepted = new Set(["--evidence", "--candidate-stdout"]);
  const values = new Map();

  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!accepted.has(flag) || values.has(flag) || typeof value !== "string") {
      nonPass("CLI_ARGUMENT_MISMATCH");
    }
    if (!value.startsWith("/") || value.includes("\u0000")) {
      nonPass("CLI_ARGUMENT_MISMATCH");
    }
    values.set(flag, value);
  }

  if (!values.has("--evidence") || !values.has("--candidate-stdout")) {
    nonPass("CLI_ARGUMENT_MISMATCH");
  }
  return {
    evidencePath: values.get("--evidence"),
    candidateStdoutPath: values.get("--candidate-stdout"),
  };
}

async function project(cliArgv) {
  const cli = parseCli(cliArgv);
  let evidenceBytes;
  let rawStdoutBytes;
  try {
    [evidenceBytes, rawStdoutBytes] = await Promise.all([
      readFile(cli.evidencePath),
      readFile(cli.candidateStdoutPath),
    ]);
  } catch {
    nonPass("INPUT_READ_ERROR");
  }

  const evidence = strictParseBytes(evidenceBytes);
  const pointerTypes = validateEvidenceShape(evidence);

  const argv = evidence.runtime.ordered_argv;
  const rawArgvBytes = Buffer.from(JSON.stringify(argv), "utf8");
  if (sha256Hex(rawArgvBytes) !== evidence.runtime.ordered_argv_sha256) {
    nonPass("RAW_ARGV_SHA256_MISMATCH");
  }

  if (
    rawStdoutBytes.length !== evidence.runtime.stdout_byte_length ||
    sha256Hex(rawStdoutBytes) !== evidence.runtime.stdout_sha256
  ) {
    nonPass("RAW_STDOUT_BINDING_MISMATCH");
  }

  const stdoutValue = strictParseBytes(rawStdoutBytes);
  const runRoot = validateStdoutValue(stdoutValue, evidence);
  const executable = evidence.runtime.executable_path;
  const candidateRoot = evidence.runtime.logical_cwd;
  const roles = buildRoots(executable, candidateRoot, runRoot);

  if (
    evidence.runtime.executable_realpath !== executable ||
    evidence.runtime.child.executable_path !== executable
  ) {
    nonPass("ROOT_DERIVATION_MISMATCH");
  }

  const tokenizedArgv = validateAndTokenizeArgv(
    argv,
    executable,
    candidateRoot,
    runRoot,
    roles,
  );

  const tokenizedPhysicalPaths = new Map();
  for (const [pointer, components] of PHYSICAL_PATHS) {
    const physicalPath = getPath(evidence, components);
    tokenizedPhysicalPaths.set(pointer, tokenizePhysicalPath(physicalPath, roles));
  }

  if (evidence.runtime.child.logical_cwd !== `${runRoot}${RUN_CHILD_SOURCE_SUFFIX}`) {
    nonPass("PATH_MAPPING_MISMATCH");
  }

  validateRepositoryAndUndeclaredPaths(pointerTypes.scalarValues);

  const normalizedStdout = normalizedStdoutBytes(evidence.candidate_status);
  const tokenizedArgvBytes = Buffer.from(JSON.stringify(tokenizedArgv), "utf8");
  const transformed = cloneJson(evidence);

  if (!Object.hasOwn(transformed.runtime, "duration_ms")) {
    nonPass("TRANSFORM_SET_NOT_CLOSED");
  }
  delete transformed.runtime.duration_ms;

  for (const [pointer, components] of PHYSICAL_PATHS) {
    setPath(transformed, components, tokenizedPhysicalPaths.get(pointer));
  }
  transformed.runtime.ordered_argv = tokenizedArgv;
  transformed.runtime.ordered_argv_sha256 = sha256Hex(tokenizedArgvBytes);
  transformed.runtime.stdout_sha256 = sha256Hex(normalizedStdout);
  transformed.runtime.stdout_byte_length = normalizedStdout.length;

  return canonicalBytes(transformed);
}

function emitNonPass(error) {
  const reason = error instanceof NonPass ? error.reason : "INTERNAL_ERROR";
  const result = Object.create(null);
  result.reason = reason;
  result.status = "NON_PASS";
  process.stderr.write(canonicalBytes(result));
  process.exitCode = 1;
}

const entryUrl = process.argv[1] === undefined ? null : pathToFileURL(process.argv[1]).href;
if (entryUrl === import.meta.url) {
  try {
    const projection = await project(process.argv.slice(2));
    process.stdout.write(projection);
  } catch (error) {
    emitNonPass(error);
  }
}

export const __test = Object.freeze({
  buildRoots,
  canonicalBytes,
  collectPointerTypes,
  deriveRunRoot,
  normalizedStdoutBytes,
  project,
  sha256Hex,
  strictParseBytes,
  tokenizePhysicalPath,
  validateAbsolutePosixPath,
  validateAndTokenizeArgv,
});

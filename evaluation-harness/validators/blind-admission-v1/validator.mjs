import fs from "node:fs";
import path from "node:path";
import { FALSE_EXTERNAL_EFFECTS, assertNoSymlinkComponents, reject, sha256 } from "../../recording/blind-admission-v1/recorder.mjs";

const REQUIRED_OPTIONS = [
  "task-card", "task-card-sha256", "task-card-byte-length",
  "source", "source-sha256", "source-byte-length",
  "runtime-profile", "runtime-profile-sha256", "runtime-profile-byte-length",
  "owned-root", "source-root", "evidence-root", "canonical-root", "case-id",
  "contract-sha256", "contract-byte-length", "authority-sha256", "authority-byte-length", "quality-freeze-sha256", "quality-freeze-byte-length",
  "commitment-sha256", "commitment-byte-length", "candidate-commit", "candidate-tree",
  "candidate-module-sha256", "candidate-module-byte-length",
  "recorder-module-sha256", "recorder-module-byte-length",
  "validator-module-sha256", "validator-module-byte-length",
  "logical-cwd", "environment-sha256", "timeout-ms"
];

export const parseOptions = (argv) => {
  if (argv.length !== REQUIRED_OPTIONS.length * 2) reject("EXECUTION_BINDING_MISMATCH");
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const token = argv[index];
    if (!token.startsWith("--") || index + 1 >= argv.length) reject("EXECUTION_BINDING_MISMATCH");
    const key = token.slice(2);
    if (!REQUIRED_OPTIONS.includes(key) || Object.hasOwn(options, key)) reject("EXECUTION_BINDING_MISMATCH");
    options[key] = argv[index + 1];
  }
  if (Object.keys(options).length !== REQUIRED_OPTIONS.length) reject("EXECUTION_BINDING_MISMATCH");
  return options;
};

export const parsePositiveInteger = (value, label, maximum = Number.MAX_SAFE_INTEGER) => {
  if (!/^[1-9][0-9]*$/.test(value)) reject(`${label}_INVALID`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed > maximum) reject(`${label}_INVALID`);
  return parsed;
};

export const requireHex = (value, length, label) => {
  if (typeof value !== "string" || !new RegExp(`^[0-9a-f]{${length}}$`).test(value)) reject(`${label}_INVALID`);
  return value;
};

const exactKeys = (object, keys) => {
  if (!object || typeof object !== "object" || Array.isArray(object)) return false;
  const actual = Object.keys(object).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
};

const falseEffects = (value) => exactKeys(value, Object.keys(FALSE_EXTERNAL_EFFECTS)) && Object.keys(FALSE_EXTERNAL_EFFECTS).every((key) => value[key] === false);

export const validateRelativePath = (value) => {
  if (typeof value !== "string" || value.length === 0 || value.includes("\\") || path.posix.isAbsolute(value)) reject("PATH_OUTSIDE_OWNED_ROOT");
  if (!/^[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*$/.test(value)) reject("PATH_OUTSIDE_OWNED_ROOT");
  if (value.split("/").some((component) => component === "." || component === "..")) reject("PATH_OUTSIDE_OWNED_ROOT");
  return value;
};

const validateIdentity = (value, label) => {
  if (!exactKeys(value, ["artifact_id", "sha256", "byte_length"])) reject(`${label}_SCHEMA_INVALID`);
  if (!/^[A-Z0-9_-]+$/.test(value.artifact_id ?? "")) reject(`${label}_SCHEMA_INVALID`);
  requireHex(value.sha256, 64, `${label}_SHA256`);
  if (!Number.isSafeInteger(value.byte_length) || value.byte_length < 1) reject(`${label}_SCHEMA_INVALID`);
};

export const validateTaskCard = (taskCard) => {
  if (!exactKeys(taskCard, ["schema_version", "task_id", "source_artifact", "runtime_profile", "operation", "execution_policy"])) reject("TASK_CARD_SCHEMA_INVALID");
  if (taskCard.schema_version !== "blind-admission-task-card/v1" || !/^[A-Z0-9_-]{8,96}$/.test(taskCard.task_id ?? "")) reject("TASK_CARD_SCHEMA_INVALID");
  validateIdentity(taskCard.source_artifact, "SOURCE_ARTIFACT");
  validateIdentity(taskCard.runtime_profile, "RUNTIME_PROFILE");
  if (!exactKeys(taskCard.operation, ["kind", "relative_path", "match", "replacement", "expected_replacements"])) reject("TASK_CARD_SCHEMA_INVALID");
  if (taskCard.operation.kind !== "replace_exact") reject("RESULT_CONTROLLED_EXECUTION_FORBIDDEN");
  validateRelativePath(taskCard.operation.relative_path);
  if (typeof taskCard.operation.match !== "string" || taskCard.operation.match.length < 1 || taskCard.operation.match.length > 4096) reject("EMPTY_PATCH");
  if (typeof taskCard.operation.replacement !== "string" || taskCard.operation.replacement.length < 1 || taskCard.operation.replacement.length > 4096) reject("EMPTY_PATCH");
  if (!Number.isSafeInteger(taskCard.operation.expected_replacements) || taskCard.operation.expected_replacements < 1 || taskCard.operation.expected_replacements > 16) reject("TASK_CARD_SCHEMA_INVALID");
  if (!exactKeys(taskCard.execution_policy, ["timeout_ms", "stdout_max_bytes", "stderr_max_bytes", "external_effects"])) reject("TASK_CARD_SCHEMA_INVALID");
  if (!Number.isSafeInteger(taskCard.execution_policy.timeout_ms) || taskCard.execution_policy.timeout_ms < 1 || taskCard.execution_policy.timeout_ms > 10000) reject("TASK_CARD_SCHEMA_INVALID");
  if (!Number.isSafeInteger(taskCard.execution_policy.stdout_max_bytes) || taskCard.execution_policy.stdout_max_bytes < 0 || taskCard.execution_policy.stdout_max_bytes > 65536) reject("TASK_CARD_SCHEMA_INVALID");
  if (!Number.isSafeInteger(taskCard.execution_policy.stderr_max_bytes) || taskCard.execution_policy.stderr_max_bytes < 0 || taskCard.execution_policy.stderr_max_bytes > 65536) reject("TASK_CARD_SCHEMA_INVALID");
  if (!falseEffects(taskCard.execution_policy.external_effects)) reject("EXTERNAL_EFFECT_FORBIDDEN");
};

export const validateSource = (source) => {
  if (!exactKeys(source, ["schema_version", "files"]) || source.schema_version !== "blind-admission-source/v1" || !Array.isArray(source.files) || source.files.length < 1 || source.files.length > 64) reject("SOURCE_SCHEMA_INVALID");
  const seen = new Set();
  const caseFolded = new Set();
  for (const entry of source.files) {
    if (!exactKeys(entry, ["path", "content"]) || typeof entry.content !== "string") reject("SOURCE_SCHEMA_INVALID");
    validateRelativePath(entry.path);
    if (seen.has(entry.path)) reject("SOURCE_MANIFEST_DRIFT");
    const folded = entry.path.toLowerCase();
    if (caseFolded.has(folded)) reject("SOURCE_MANIFEST_DRIFT");
    seen.add(entry.path);
    caseFolded.add(folded);
  }
  for (const filePath of seen) {
    const components = filePath.split("/");
    for (let length = 1; length < components.length; length += 1) {
      if (seen.has(components.slice(0, length).join("/"))) reject("SOURCE_MANIFEST_DRIFT");
    }
  }
  for (const filePath of caseFolded) {
    const components = filePath.split("/");
    for (let length = 1; length < components.length; length += 1) {
      if (caseFolded.has(components.slice(0, length).join("/"))) reject("SOURCE_MANIFEST_DRIFT");
    }
  }
};

export const validateRuntimeProfile = (profile) => {
  if (!exactKeys(profile, ["schema_version", "profile_id", "executable", "actual_process", "alternate_architecture_probe", "external_effects"])) reject("RUNTIME_PROFILE_SCHEMA_INVALID");
  if (profile.schema_version !== "blind-admission-runtime-profile/v1" || typeof profile.profile_id !== "string") reject("RUNTIME_PROFILE_SCHEMA_INVALID");
  if (!exactKeys(profile.executable, ["path", "realpath", "sha256", "byte_length", "mode", "version"])) reject("RUNTIME_PROFILE_SCHEMA_INVALID");
  if (!path.isAbsolute(profile.executable.path) || !path.isAbsolute(profile.executable.realpath)) reject("EXECUTABLE_IDENTITY_MISMATCH");
  requireHex(profile.executable.sha256, 64, "EXECUTABLE_SHA256");
  if (!Number.isSafeInteger(profile.executable.byte_length) || profile.executable.byte_length < 1 || !/^[0-7]{4}$/.test(profile.executable.mode ?? "") || typeof profile.executable.version !== "string") reject("RUNTIME_PROFILE_SCHEMA_INVALID");
  if (!exactKeys(profile.actual_process, ["platform", "arch"]) || typeof profile.actual_process.platform !== "string" || typeof profile.actual_process.arch !== "string") reject("RUNTIME_PROFILE_SCHEMA_INVALID");
  if (!Array.isArray(profile.alternate_architecture_probe) || profile.alternate_architecture_probe.some((entry) => typeof entry !== "string")) reject("RUNTIME_PROFILE_SCHEMA_INVALID");
  if (!falseEffects(profile.external_effects)) reject("EXTERNAL_EFFECT_FORBIDDEN");
};

export const validateOpaqueBindings = (options) => {
  for (const key of ["task-card-sha256", "source-sha256", "runtime-profile-sha256", "contract-sha256", "authority-sha256", "quality-freeze-sha256", "commitment-sha256", "candidate-module-sha256", "recorder-module-sha256", "validator-module-sha256", "environment-sha256"]) requireHex(options[key], 64, key.toUpperCase().replaceAll("-", "_"));
  requireHex(options["candidate-commit"], 40, "CANDIDATE_COMMIT");
  requireHex(options["candidate-tree"], 40, "CANDIDATE_TREE");
  for (const key of ["task-card-byte-length", "source-byte-length", "runtime-profile-byte-length", "contract-byte-length", "authority-byte-length", "quality-freeze-byte-length", "commitment-byte-length", "candidate-module-byte-length", "recorder-module-byte-length", "validator-module-byte-length"]) parsePositiveInteger(options[key], key.toUpperCase().replaceAll("-", "_"));
  const timeout = parsePositiveInteger(options["timeout-ms"], "TIMEOUT", 10000);
  if (!path.isAbsolute(options["task-card"]) || !path.isAbsolute(options.source) || !path.isAbsolute(options["runtime-profile"]) || !path.isAbsolute(options["owned-root"]) || !path.isAbsolute(options["source-root"]) || !path.isAbsolute(options["evidence-root"]) || !path.isAbsolute(options["canonical-root"]) || !path.isAbsolute(options["logical-cwd"])) reject("EXECUTION_BINDING_MISMATCH");
  if (process.cwd() !== options["logical-cwd"]) reject("EXECUTION_BINDING_MISMATCH");
  if (typeof options["case-id"] !== "string" || !/^[A-Za-z0-9._-]{1,96}$/.test(options["case-id"])) reject("EXECUTION_BINDING_MISMATCH");
  return timeout;
};

export const sanitizedEnvironment = () => {
  if ((process.env.NODE_OPTIONS ?? "") !== "" || (process.env.NODE_PATH ?? "") !== "") reject("EXECUTION_BINDING_MISMATCH");
  if (Object.keys(process.env).some((key) => key.startsWith("DYLD_") && (process.env[key] ?? "") !== "")) reject("EXECUTION_BINDING_MISMATCH");
  const allowed = ["LANG", "LC_ALL", "LC_CTYPE", "PATH", "TMPDIR", "TZ"];
  return Object.fromEntries(allowed.filter((key) => Object.hasOwn(process.env, key)).map((key) => [key, process.env[key]]));
};

export const validateExecutable = (profile) => {
  if (process.platform !== profile.actual_process.platform || process.arch !== profile.actual_process.arch) reject("ACTUAL_ARCHITECTURE_MISMATCH");
  if (process.execPath !== profile.executable.path) reject("EXECUTABLE_IDENTITY_MISMATCH");
  assertNoSymlinkComponents(process.execPath);
  const realpath = fs.realpathSync(process.execPath);
  const stat = fs.statSync(process.execPath);
  const bytes = fs.readFileSync(process.execPath);
  const mode = (stat.mode & 0o777).toString(8).padStart(4, "0");
  if (realpath !== profile.executable.realpath || sha256(bytes) !== profile.executable.sha256 || bytes.length !== profile.executable.byte_length || mode !== profile.executable.mode || process.version !== profile.executable.version) reject("EXECUTABLE_IDENTITY_MISMATCH");
  return { realpath, sha256: profile.executable.sha256, byte_length: bytes.length, mode, version: process.version };
};

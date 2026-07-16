import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { lstatSync, readFileSync, realpathSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { isDeepStrictEqual } from "node:util";

import { canonicalJson, validate } from "../evaluator/schema-validator.mjs";

export const REASONS = Object.freeze({
  MALFORMED_INPUT: "MALFORMED_INPUT",
  PATH_CONTAINMENT_VIOLATION: "PATH_CONTAINMENT_VIOLATION",
  SYMLINK_FORBIDDEN: "SYMLINK_FORBIDDEN",
  SOURCE_NOT_CLEAN: "SOURCE_NOT_CLEAN",
  UNDECLARED_LOCKFILE: "UNDECLARED_LOCKFILE",
  SOURCE_IDENTITY_MISMATCH: "SOURCE_IDENTITY_MISMATCH",
  RUNTIME_IDENTITY_MISMATCH: "RUNTIME_IDENTITY_MISMATCH",
  DEPENDENCY_IDENTITY_MISMATCH: "DEPENDENCY_IDENTITY_MISMATCH",
  POLICY_BOUNDARY_MISMATCH: "POLICY_BOUNDARY_MISMATCH",
  SNAPSHOT_SCHEMA_INVALID: "SNAPSHOT_SCHEMA_INVALID",
  SNAPSHOT_ID_MISMATCH: "SNAPSHOT_ID_MISMATCH",
});

const LOCKFILE_BASENAMES = new Set([
  "Cargo.lock",
  "composer.lock",
  "Gemfile.lock",
  "go.sum",
  "npm-shrinkwrap.json",
  "package-lock.json",
  "pnpm-lock.yaml",
  "poetry.lock",
  "yarn.lock",
]);
const LOWER_HEX = /^[0-9a-f]+$/;
const SHA256 = /^[0-9a-f]{64}$/;
const GIT_HASH = /^[0-9a-f]{40,64}$/;

function compareUtf8(left, right) {
  return Buffer.compare(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
}

export class TypedFailure extends Error {
  constructor(reasonCode, message) {
    super(message);
    this.name = "TypedFailure";
    this.reasonCode = reasonCode;
  }
}

export function sha256Bytes(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function canonicalBytes(value) {
  return Buffer.from(`${canonicalJson(value)}\n`, "utf8");
}

export function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, `cannot parse JSON ${path}: ${error.message}`);
  }
}

function requireObject(value, label) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, `${label} must be an object`);
  }
  return value;
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, `${label} must be a non-empty string`);
  }
  return value;
}

function requireArray(value, label) {
  if (!Array.isArray(value)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, `${label} must be an array`);
  }
  return value;
}

function requireDeclarationShape(input) {
  const declarations = requireObject(input, "declarations");
  if (declarations.schema_version !== "1.0") {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "unsupported declaration schema_version");
  }
  requireString(declarations.repository_identity, "repository_identity");
  if (isAbsolute(declarations.repository_identity) || declarations.repository_identity.startsWith("file:")) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "repository_identity must be logical, not physical");
  }

  const materialization = requireObject(declarations.materialization, "materialization");
  requireString(materialization.expected_commit, "materialization.expected_commit");
  requireString(materialization.expected_tree, "materialization.expected_tree");
  if (!GIT_HASH.test(materialization.expected_commit) || !GIT_HASH.test(materialization.expected_tree)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "materialization Git identities must be lowercase hexadecimal");
  }

  const runtime = requireObject(declarations.target_runtime, "target_runtime");
  for (const key of ["os", "architecture", "container_image_digest", "locale", "timezone"]) {
    requireString(runtime[key], `target_runtime.${key}`);
  }
  if (!/^sha256:[0-9a-f]{64}$/.test(runtime.container_image_digest)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "target runtime digest must be sha256-prefixed lowercase hexadecimal");
  }

  const dependencies = requireObject(declarations.dependencies, "dependencies");
  for (const [index, lockfile] of requireArray(dependencies.lockfiles, "dependencies.lockfiles").entries()) {
    requireObject(lockfile, `dependencies.lockfiles[${index}]`);
    requireString(lockfile.path, `dependencies.lockfiles[${index}].path`);
    if (!SHA256.test(lockfile.sha256)) {
      throw new TypedFailure(REASONS.MALFORMED_INPUT, `dependencies.lockfiles[${index}].sha256 is invalid`);
    }
  }
  const toolchains = requireObject(dependencies.toolchains, "dependencies.toolchains");
  for (const [name, version] of Object.entries(toolchains)) {
    requireString(name, "dependencies.toolchains key");
    requireString(version, `dependencies.toolchains.${name}`);
  }
  for (const [index, cache] of requireArray(dependencies.caches, "dependencies.caches").entries()) {
    requireObject(cache, `dependencies.caches[${index}]`);
    requireString(cache.name, `dependencies.caches[${index}].name`);
    if (!new Set(["disabled", "read_only", "frozen"]).has(cache.policy)) {
      throw new TypedFailure(REASONS.MALFORMED_INPUT, `dependencies.caches[${index}].policy is invalid`);
    }
    if (cache.policy === "disabled" ? cache.digest !== null : !SHA256.test(cache.digest ?? "")) {
      throw new TypedFailure(REASONS.MALFORMED_INPUT, `dependencies.caches[${index}].digest is invalid`);
    }
  }
  requireObject(declarations.model, "model");
  for (const key of ["model_ref", "provider", "model_id", "model_version"]) {
    requireString(declarations.model[key], `model.${key}`);
  }
  requireObject(declarations.model.parameters, "model.parameters");
  requireString(declarations.prompt_version, "prompt_version");
  requireString(declarations.policy_version, "policy_version");
  for (const [index, tool] of requireArray(declarations.tools, "tools").entries()) {
    requireObject(tool, `tools[${index}]`);
    for (const key of ["tool_id", "version", "permission"]) requireString(tool[key], `tools[${index}].${key}`);
    if (!new Set(["observe", "suggest", "modify_isolated", "execute_isolated"]).has(tool.permission)) {
      throw new TypedFailure(REASONS.MALFORMED_INPUT, `tools[${index}].permission is invalid`);
    }
  }
  const network = requireObject(declarations.network, "network");
  if (!new Set(["none", "fixture_only", "declared_allowlist"]).has(network.policy)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "network.policy is invalid");
  }
  if (!requireArray(network.allowed_hosts, "network.allowed_hosts").every((host) => typeof host === "string" && host.length > 0)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "network.allowed_hosts is invalid");
  }
  const environment = requireObject(declarations.environment_variables, "environment_variables");
  const nonSecrets = requireObject(environment.non_secret_values, "environment_variables.non_secret_values");
  if (!Object.values(nonSecrets).every((value) => typeof value === "string")) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "environment non-secret values must be strings");
  }
  if (!requireArray(environment.secret_names_present, "environment_variables.secret_names_present").every((name) => typeof name === "string" && name.length > 0)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "secret_names_present is invalid");
  }
  const secretPolicy = requireObject(declarations.secret_policy, "secret_policy");
  if (typeof secretPolicy.values_retained !== "boolean") {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "secret_policy.values_retained must be boolean");
  }
  requireString(secretPolicy.redaction_policy_version, "secret_policy.redaction_policy_version");
  if (Object.hasOwn(declarations, "random_seed") && declarations.random_seed !== null && !Number.isInteger(declarations.random_seed)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "random_seed must be integer or null");
  }
  return declarations;
}

function git(sourceRoot, args) {
  try {
    return execFileSync("git", ["-C", sourceRoot, ...args], {
      encoding: "utf8",
      env: { ...process.env, LC_ALL: "C", LANG: "C" },
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, `Git observation failed: ${error.status ?? "unknown"}`);
  }
}

function assertSourceRoot(sourceRoot) {
  const supplied = resolve(sourceRoot);
  let stat;
  try {
    stat = lstatSync(supplied);
  } catch {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "source root does not exist");
  }
  if (stat.isSymbolicLink()) throw new TypedFailure(REASONS.SYMLINK_FORBIDDEN, "source root is a symlink");
  if (!stat.isDirectory()) throw new TypedFailure(REASONS.MALFORMED_INPUT, "source root is not a directory");
  return realpathSync(supplied);
}

function containedPath(sourceRoot, relativePath) {
  if (typeof relativePath !== "string" || relativePath.length === 0 || isAbsolute(relativePath)) {
    throw new TypedFailure(REASONS.PATH_CONTAINMENT_VIOLATION, "lockfile path is not repository-relative");
  }
  const normalized = relativePath.replaceAll("\\", "/");
  if (normalized.split("/").some((part) => part === ".." || part === "")) {
    throw new TypedFailure(REASONS.PATH_CONTAINMENT_VIOLATION, "lockfile path escapes source root");
  }
  const target = resolve(sourceRoot, normalized);
  const rel = relative(sourceRoot, target);
  if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) {
    throw new TypedFailure(REASONS.PATH_CONTAINMENT_VIOLATION, "lockfile path escapes source root");
  }
  let cursor = sourceRoot;
  for (const part of normalized.split("/")) {
    cursor = resolve(cursor, part);
    let stat;
    try {
      stat = lstatSync(cursor);
    } catch {
      throw new TypedFailure(REASONS.MALFORMED_INPUT, `declared lockfile is missing: ${normalized}`);
    }
    if (stat.isSymbolicLink()) throw new TypedFailure(REASONS.SYMLINK_FORBIDDEN, `symlink forbidden: ${normalized}`);
  }
  if (!lstatSync(target).isFile()) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, `declared lockfile is not a regular file: ${normalized}`);
  }
  const real = realpathSync(target);
  const realRel = relative(sourceRoot, real);
  if (realRel === ".." || realRel.startsWith(`..${sep}`) || isAbsolute(realRel)) {
    throw new TypedFailure(REASONS.PATH_CONTAINMENT_VIOLATION, "resolved lockfile escapes source root");
  }
  return { normalized, target };
}

function discoverLockfiles(root, dir = root, found = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".git") continue;
    const path = resolve(dir, entry.name);
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) {
      throw new TypedFailure(REASONS.SYMLINK_FORBIDDEN, `symlink discovered while scanning source: ${relative(root, path).split(sep).join("/")}`);
    }
    if (stat.isDirectory()) discoverLockfiles(root, path, found);
    else if (stat.isFile() && LOCKFILE_BASENAMES.has(entry.name)) {
      found.push(relative(root, path).split(sep).join("/"));
    }
  }
  return found.sort(compareUtf8);
}

function normalizeDeclarations(declarations, declaredLocks, manifestBytes) {
  const manifestDigest = `sha256:${sha256Bytes(manifestBytes)}`;
  if (manifestDigest !== declarations.target_runtime.container_image_digest) {
    throw new TypedFailure(REASONS.RUNTIME_IDENTITY_MISMATCH, "runtime manifest digest mismatch");
  }

  const lockfiles = declaredLocks.map(({ normalized, target }, index) => {
    const actual = sha256Bytes(readFileSync(target));
    if (actual !== declarations.dependencies.lockfiles[index].sha256) {
      throw new TypedFailure(REASONS.DEPENDENCY_IDENTITY_MISMATCH, `lockfile digest mismatch: ${normalized}`);
    }
    return { path: normalized, sha256: actual };
  }).sort((left, right) => Buffer.compare(Buffer.from(left.path), Buffer.from(right.path)));

  const tools = declarations.tools.map((entry, index) => {
    const tool = requireObject(entry, `tools[${index}]`);
    for (const key of ["tool_id", "version", "permission"]) requireString(tool[key], `tools[${index}].${key}`);
    return { tool_id: tool.tool_id, version: tool.version, permission: tool.permission };
  }).sort((a, b) => Buffer.compare(
    Buffer.from(`${a.tool_id}\0${a.version}\0${a.permission}`),
    Buffer.from(`${b.tool_id}\0${b.version}\0${b.permission}`),
  ));

  const caches = declarations.dependencies.caches.map((entry, index) => {
    const cache = requireObject(entry, `dependencies.caches[${index}]`);
    requireString(cache.name, `dependencies.caches[${index}].name`);
    requireString(cache.policy, `dependencies.caches[${index}].policy`);
    if (!(cache.digest === null || (typeof cache.digest === "string" && SHA256.test(cache.digest)))) {
      throw new TypedFailure(REASONS.MALFORMED_INPUT, `dependencies.caches[${index}].digest is invalid`);
    }
    return { name: cache.name, policy: cache.policy, digest: cache.digest };
  }).sort((a, b) => Buffer.compare(
    Buffer.from(`${a.name}\0${a.policy}\0${a.digest ?? ""}`),
    Buffer.from(`${b.name}\0${b.policy}\0${b.digest ?? ""}`),
  ));

  const environment = declarations.environment_variables;
  const nonSecretValues = requireObject(environment.non_secret_values, "environment_variables.non_secret_values");
  const secretNames = [...new Set(requireArray(environment.secret_names_present, "environment_variables.secret_names_present"))].sort(compareUtf8);
  if (!secretNames.every((name) => typeof name === "string" && name.length > 0)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "secret_names_present must contain non-empty strings");
  }

  return {
    lockfiles,
    toolchains: Object.fromEntries(Object.entries(declarations.dependencies.toolchains).sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b)))),
    caches,
    tools,
    environment_variables: {
      non_secret_values: Object.fromEntries(Object.entries(nonSecretValues).sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b)))),
      secret_names_present: secretNames,
    },
  };
}

function assertPolicyBoundary(declarations) {
  if (declarations.network.policy !== "none" || declarations.network.allowed_hosts?.length !== 0 ||
      declarations.model.provider !== "none" || declarations.secret_policy.values_retained !== false ||
      declarations.environment_variables.secret_names_present?.length !== 0) {
    throw new TypedFailure(REASONS.POLICY_BOUNDARY_MISMATCH, "P1-011 policy boundary requires no network, provider, or retained Secret");
  }
}

export function identityProjection(snapshot) {
  return {
    schema_version: snapshot.schema_version,
    source: {
      repository_identity: snapshot.source.repository_identity,
      base_commit: snapshot.source.base_commit,
      tree_hash: snapshot.source.tree_hash,
      worktree_clean: snapshot.source.worktree_clean,
    },
    runtime: snapshot.runtime,
    dependencies: snapshot.dependencies,
    model: snapshot.model,
    prompt_version: snapshot.prompt_version,
    policy_version: snapshot.policy_version,
    tools: snapshot.tools,
    network: snapshot.network,
    environment_variables: snapshot.environment_variables,
    secret_policy: snapshot.secret_policy,
    random_seed: Object.hasOwn(snapshot, "random_seed") ? snapshot.random_seed : null,
  };
}

export function projectionIdentity(snapshot) {
  const bytes = canonicalBytes(identityProjection(snapshot));
  const projectionSha256 = sha256Bytes(bytes);
  return { bytes, projectionSha256, snapshotId: `ENV-${projectionSha256}` };
}

export function captureSnapshot({ sourceRoot, declarationsPath, runtimeManifestPath, schemaPath, createdAt = new Date().toISOString() }) {
  const declarations = requireDeclarationShape(readJson(declarationsPath));
  const root = assertSourceRoot(sourceRoot);
  const declaredLocks = declarations.dependencies.lockfiles.map((entry) => containedPath(root, entry.path));
  let manifestBytes;
  try {
    if (lstatSync(runtimeManifestPath).isSymbolicLink()) {
      throw new TypedFailure(REASONS.SYMLINK_FORBIDDEN, "runtime manifest is a symlink");
    }
    manifestBytes = readFileSync(runtimeManifestPath);
  } catch (error) {
    if (error instanceof TypedFailure) throw error;
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "runtime manifest cannot be read");
  }
  const status = git(root, ["status", "--porcelain=v1", "--untracked-files=all"]);
  if (status.length !== 0) throw new TypedFailure(REASONS.SOURCE_NOT_CLEAN, "source worktree is not clean");
  const declaredNames = declaredLocks.map(({ normalized }) => normalized).sort(compareUtf8);
  const undeclared = discoverLockfiles(root).filter((path) => !declaredNames.includes(path));
  if (undeclared.length > 0) {
    throw new TypedFailure(REASONS.UNDECLARED_LOCKFILE, `undeclared lockfile: ${undeclared[0]}`);
  }
  const baseCommit = git(root, ["rev-parse", "HEAD"]).toLowerCase();
  const treeHash = git(root, ["rev-parse", "HEAD^{tree}"]).toLowerCase();
  if (!LOWER_HEX.test(baseCommit) || !LOWER_HEX.test(treeHash)) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "Git returned malformed identities");
  }
  if (baseCommit !== declarations.materialization.expected_commit || treeHash !== declarations.materialization.expected_tree) {
    throw new TypedFailure(REASONS.SOURCE_IDENTITY_MISMATCH, "source commit or tree differs from declaration");
  }
  const normalized = normalizeDeclarations(declarations, declaredLocks, manifestBytes);
  assertPolicyBoundary(declarations);

  const snapshot = {
    schema_version: "1.0",
    snapshot_id: "ENV-pending",
    created_at: createdAt,
    source: {
      repository_identity: declarations.repository_identity,
      base_commit: baseCommit,
      tree_hash: treeHash,
      worktree_clean: true,
    },
    runtime: { ...declarations.target_runtime },
    dependencies: {
      lockfiles: normalized.lockfiles,
      toolchains: normalized.toolchains,
      caches: normalized.caches,
    },
    model: declarations.model,
    prompt_version: declarations.prompt_version,
    policy_version: declarations.policy_version,
    tools: normalized.tools,
    network: declarations.network,
    environment_variables: normalized.environment_variables,
    secret_policy: declarations.secret_policy,
    random_seed: Object.hasOwn(declarations, "random_seed") ? declarations.random_seed : null,
  };
  const identity = projectionIdentity(snapshot);
  snapshot.snapshot_id = identity.snapshotId;
  const schemaErrors = validate(snapshot, readJson(schemaPath));
  if (schemaErrors.length > 0) {
    throw new TypedFailure(REASONS.SNAPSHOT_SCHEMA_INVALID, schemaErrors.join("; "));
  }
  return { snapshot, ...identity };
}

function compareGroup(left, right, reasonCode, label) {
  if (!isDeepStrictEqual(left, right)) throw new TypedFailure(reasonCode, `${label} mismatch`);
}

export function verifySnapshot(options) {
  const observed = captureSnapshot(options);
  const captured = readJson(options.snapshotPath);
  requireObject(captured, "snapshot");
  compareGroup(captured.source, observed.snapshot.source, REASONS.SOURCE_IDENTITY_MISMATCH, "source identity");
  compareGroup(captured.runtime, observed.snapshot.runtime, REASONS.RUNTIME_IDENTITY_MISMATCH, "runtime identity");
  compareGroup(captured.dependencies, observed.snapshot.dependencies, REASONS.DEPENDENCY_IDENTITY_MISMATCH, "dependency identity");
  compareGroup({
    model: captured.model,
    prompt_version: captured.prompt_version,
    policy_version: captured.policy_version,
    tools: captured.tools,
    network: captured.network,
    environment_variables: captured.environment_variables,
    secret_policy: captured.secret_policy,
    random_seed: Object.hasOwn(captured, "random_seed") ? captured.random_seed : null,
  }, {
    model: observed.snapshot.model,
    prompt_version: observed.snapshot.prompt_version,
    policy_version: observed.snapshot.policy_version,
    tools: observed.snapshot.tools,
    network: observed.snapshot.network,
    environment_variables: observed.snapshot.environment_variables,
    secret_policy: observed.snapshot.secret_policy,
    random_seed: observed.snapshot.random_seed,
  }, REASONS.POLICY_BOUNDARY_MISMATCH, "policy boundary");

  const schemaErrors = validate(captured, readJson(options.schemaPath));
  if (schemaErrors.length > 0) throw new TypedFailure(REASONS.SNAPSHOT_SCHEMA_INVALID, schemaErrors.join("; "));
  const capturedIdentity = projectionIdentity(captured);
  if (captured.snapshot_id !== capturedIdentity.snapshotId) {
    throw new TypedFailure(REASONS.SNAPSHOT_ID_MISMATCH, "snapshot_id does not match deterministic projection");
  }
  return { snapshot: captured, ...capturedIdentity };
}

export function writeCanonicalJson(path, value) {
  writeFileSync(path, canonicalBytes(value));
}

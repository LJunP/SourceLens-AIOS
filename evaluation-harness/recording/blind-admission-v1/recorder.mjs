import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
export const FALSE_EXTERNAL_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false
});

export class AdmissionError extends Error {
  constructor(reason) {
    super(reason);
    this.name = "AdmissionError";
    this.reason = reason;
  }
}

export const reject = (reason) => {
  throw new AdmissionError(reason);
};

export const sha256 = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");

const normalizeJson = (value) => {
  if (Array.isArray(value)) return value.map(normalizeJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, normalizeJson(value[key])]));
  }
  return value;
};

export const stableJson = (value) => JSON.stringify(normalizeJson(value));
export const sha256Json = (value) => sha256(Buffer.from(stableJson(value), "utf8"));

export const assertNoSymlinkComponents = (targetPath) => {
  if (!path.isAbsolute(targetPath)) reject("EXECUTION_BINDING_MISMATCH");
  const normalized = path.resolve(targetPath);
  const root = path.parse(normalized).root;
  let cursor = root;
  for (const component of normalized.slice(root.length).split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, component);
    if (!fs.existsSync(cursor)) break;
    if (fs.lstatSync(cursor).isSymbolicLink()) reject("SYMLINK_COMPONENT_FORBIDDEN");
  }
};

export const readBoundFile = (filePath, expectedSha256, expectedLength, label) => {
  assertNoSymlinkComponents(filePath);
  let stat;
  try {
    stat = fs.lstatSync(filePath);
  } catch {
    reject(`${label}_MISSING`);
  }
  if (!stat.isFile() || stat.isSymbolicLink()) reject(`${label}_TYPE_INVALID`);
  if (stat.nlink !== 1) reject("NON_UNIQUE_INPUT_LINK_COUNT");
  const bytes = fs.readFileSync(filePath);
  if (bytes.length !== expectedLength || sha256(bytes) !== expectedSha256) reject(`${label}_IDENTITY_MISMATCH`);
  return { bytes, sha256: expectedSha256, byte_length: expectedLength };
};

export const parseBoundJson = (filePath, expectedSha256, expectedLength, label) => {
  const input = readBoundFile(filePath, expectedSha256, expectedLength, label);
  try {
    return { ...input, json: JSON.parse(input.bytes.toString("utf8")) };
  } catch {
    reject(`${label}_JSON_INVALID`);
  }
};

const existingAncestor = (targetPath) => {
  let cursor = targetPath;
  const suffix = [];
  while (!fs.existsSync(cursor)) {
    const parent = path.dirname(cursor);
    if (parent === cursor) reject("OWNED_ROOT_PARENT_MISSING");
    suffix.unshift(path.basename(cursor));
    cursor = parent;
  }
  return { cursor, suffix };
};

export const plannedRealPath = (targetPath, label) => {
  if (!path.isAbsolute(targetPath)) reject(`${label}_NOT_ABSOLUTE`);
  const normalized = path.resolve(targetPath);
  const { cursor, suffix } = existingAncestor(normalized);
  let walk = path.parse(cursor).root;
  for (const component of cursor.slice(walk.length).split(path.sep).filter(Boolean)) {
    walk = path.join(walk, component);
    const stat = fs.lstatSync(walk);
    if (stat.isSymbolicLink()) reject("SYMLINK_COMPONENT_FORBIDDEN");
  }
  const ancestorStat = fs.lstatSync(cursor);
  if (!ancestorStat.isDirectory()) reject(`${label}_PARENT_TYPE_INVALID`);
  return path.join(fs.realpathSync(cursor), ...suffix);
};

const contains = (parent, child) => child === parent || child.startsWith(`${parent}${path.sep}`);

export const validateFreshRootPlans = ({ sourceRoot, evidenceRoot, canonicalRoot }) => {
  if (fs.existsSync(sourceRoot) || fs.lstatSync(path.dirname(sourceRoot)).isSymbolicLink()) reject("SOURCE_ROOT_ALREADY_EXISTS");
  if (fs.existsSync(evidenceRoot) || fs.lstatSync(path.dirname(evidenceRoot)).isSymbolicLink()) reject("OUTPUT_ALREADY_EXISTS");
  const sourcePlan = plannedRealPath(sourceRoot, "SOURCE_ROOT");
  const evidencePlan = plannedRealPath(evidenceRoot, "EVIDENCE_ROOT");
  const canonicalPlan = fs.realpathSync(canonicalRoot);
  if (contains(sourcePlan, evidencePlan) || contains(evidencePlan, sourcePlan)) reject("ROOT_ALIAS_OR_OVERLAP");
  if (contains(canonicalPlan, sourcePlan) || contains(sourcePlan, canonicalPlan) || contains(canonicalPlan, evidencePlan) || contains(evidencePlan, canonicalPlan)) reject("PATH_OUTSIDE_OWNED_ROOT");
  return { sourcePlan, evidencePlan, canonicalPlan };
};

export const mkdirExclusive = (dirPath) => {
  try {
    fs.mkdirSync(dirPath, { mode: 0o700 });
  } catch (error) {
    if (error?.code === "EEXIST") reject("OUTPUT_ALREADY_EXISTS");
    throw error;
  }
};

export const atomicWriteExclusive = (filePath, bytes, mode = 0o400) => {
  let descriptor;
  let created = false;
  try {
    descriptor = fs.openSync(filePath, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | (fs.constants.O_NOFOLLOW ?? 0), mode);
    created = true;
    fs.writeFileSync(descriptor, bytes);
    fs.fsyncSync(descriptor);
  } catch (error) {
    if (descriptor !== undefined) {
      fs.closeSync(descriptor);
      descriptor = undefined;
    }
    if (created && fs.existsSync(filePath)) {
      const stat = fs.lstatSync(filePath);
      if (stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1) fs.unlinkSync(filePath);
    }
    if (error?.code === "EEXIST" || error?.code === "ELOOP") reject("OUTPUT_ALREADY_EXISTS");
    throw error;
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
  }
};

export const materializeSource = (sourceRoot, sourceFiles) => {
  mkdirExclusive(sourceRoot);
  const createdFiles = [];
  const createdDirectories = [sourceRoot];
  try {
    for (const entry of sourceFiles) {
      const components = entry.path.split("/");
      let directory = sourceRoot;
      for (const component of components.slice(0, -1)) {
        directory = path.join(directory, component);
        if (!fs.existsSync(directory)) {
          fs.mkdirSync(directory, { mode: 0o700 });
          createdDirectories.push(directory);
        } else {
          const stat = fs.lstatSync(directory);
          if (!stat.isDirectory() || stat.isSymbolicLink()) reject("SYMLINK_COMPONENT_FORBIDDEN");
        }
      }
      const filePath = path.join(sourceRoot, ...components);
      atomicWriteExclusive(filePath, Buffer.from(entry.content, "utf8"), 0o600);
      createdFiles.push(filePath);
    }
    return { createdFiles, createdDirectories };
  } catch (error) {
    try {
      cleanupOwnedSource(sourceRoot, { createdFiles, createdDirectories });
    } catch {
      reject("ROLLBACK_NOT_EXACT");
    }
    throw error;
  }
};

export const cleanupOwnedSource = (sourceRoot, ownership) => {
  if (!ownership) return;
  for (const filePath of [...ownership.createdFiles].reverse()) {
    const stat = fs.lstatSync(filePath);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) reject("ROLLBACK_NOT_EXACT");
    fs.unlinkSync(filePath);
  }
  for (const directory of [...ownership.createdDirectories].sort((left, right) => right.length - left.length)) {
    const stat = fs.lstatSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) reject("ROLLBACK_NOT_EXACT");
    fs.rmdirSync(directory);
  }
  if (fs.existsSync(sourceRoot)) reject("ROLLBACK_NOT_EXACT");
};

export const writeEvidence = (evidenceRoot, evidence) => {
  mkdirExclusive(evidenceRoot);
  const bytes = Buffer.from(`${JSON.stringify(evidence, null, 2)}\n`, "utf8");
  const evidencePath = path.join(evidenceRoot, "evidence.json");
  atomicWriteExclusive(evidencePath, bytes, 0o400);
  return { path: evidencePath, sha256: sha256(bytes), byte_length: bytes.length };
};

const readStdinBounded = (maximumBytes) => {
  const chunks = [];
  let length = 0;
  const descriptor = 0;
  const buffer = Buffer.alloc(8192);
  while (true) {
    const read = fs.readSync(descriptor, buffer, 0, buffer.length, null);
    if (read === 0) break;
    length += read;
    if (length > maximumBytes) reject("RECORDER_REQUEST_TOO_LARGE");
    chunks.push(Buffer.from(buffer.subarray(0, read)));
  }
  return Buffer.concat(chunks);
};

const runRecorderChild = () => {
  let request;
  try {
    request = JSON.parse(readStdinBounded(65536).toString("utf8"));
  } catch (error) {
    if (error instanceof AdmissionError) throw error;
    reject("RECORDER_REQUEST_INVALID");
  }
  const keys = Object.keys(request ?? {}).sort();
  const expectedKeys = ["expected_replacements", "match", "relative_path", "replacement", "source_root"].sort();
  if (keys.length !== expectedKeys.length || keys.some((key, index) => key !== expectedKeys[index])) reject("RECORDER_REQUEST_INVALID");
  if (typeof request.match !== "string" || request.match.length === 0 || typeof request.replacement !== "string" || request.replacement.length === 0 || request.match === request.replacement) reject("NO_MATERIAL_CHANGE");
  if (!Number.isSafeInteger(request.expected_replacements) || request.expected_replacements < 1 || request.expected_replacements > 16) reject("MATCH_COUNT_MISMATCH");
  if (typeof request.relative_path !== "string" || !/^[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*$/.test(request.relative_path) || request.relative_path.split("/").some((part) => part === "." || part === "..")) reject("PATH_OUTSIDE_OWNED_ROOT");
  if (!path.isAbsolute(request.source_root) || fs.realpathSync(request.source_root) !== fs.realpathSync(process.cwd())) reject("EXECUTION_BINDING_MISMATCH");
  const sourceRoot = fs.realpathSync(request.source_root);
  const target = path.join(sourceRoot, ...request.relative_path.split("/"));
  const stat = fs.lstatSync(target);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || !fs.realpathSync(target).startsWith(`${sourceRoot}${path.sep}`)) reject("PATH_OUTSIDE_OWNED_ROOT");
  const before = fs.readFileSync(target, "utf8");
  let count = 0;
  let offset = 0;
  while (true) {
    const found = before.indexOf(request.match, offset);
    if (found < 0) break;
    count += 1;
    offset = found + request.match.length;
  }
  if (count === 0) reject("EMPTY_PATCH");
  if (count !== request.expected_replacements) reject("MATCH_COUNT_MISMATCH");
  const after = before.split(request.match).join(request.replacement);
  if (after === before) reject("NO_MATERIAL_CHANGE");
  const descriptor = fs.openSync(target, fs.constants.O_WRONLY | fs.constants.O_TRUNC | (fs.constants.O_NOFOLLOW ?? 0));
  try {
    fs.writeFileSync(descriptor, after, { encoding: "utf8" });
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
  const actual = fs.readFileSync(target, "utf8");
  if (actual !== after) reject("RESULT_MANIFEST_DRIFT");
  const result = {
    schema_version: "blind-admission-recorder-result/v1",
    relative_path: request.relative_path,
    replacements: count,
    before_sha256: sha256(Buffer.from(before, "utf8")),
    before_byte_length: Buffer.byteLength(before, "utf8"),
    after_sha256: sha256(Buffer.from(after, "utf8")),
    after_byte_length: Buffer.byteLength(after, "utf8")
  };
  process.stdout.write(`${stableJson(result)}\n`);
};

const invokedPath = process.argv[1] ? fs.realpathSync(process.argv[1]) : "";
if (invokedPath === fs.realpathSync(fileURLToPath(import.meta.url))) {
  try {
    runRecorderChild();
  } catch (error) {
    const reason = error instanceof AdmissionError ? error.reason : "RECORDER_INTERNAL_ERROR";
    process.stderr.write(`${stableJson({ reason, verdict: "REJECTED" })}\n`);
    process.exitCode = 1;
  }
}

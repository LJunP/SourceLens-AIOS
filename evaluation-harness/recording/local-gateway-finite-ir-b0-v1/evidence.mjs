import { createHash, randomBytes } from "node:crypto";
import {
  closeSync,
  constants as fsConstants,
  fchmodSync,
  fstatSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  realpathSync,
  writeSync,
} from "node:fs";
import { basename, dirname, isAbsolute, join, resolve, sep } from "node:path";

export const EVIDENCE_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-audit/p1-062-local-gateway-20260721T022035Z";
export const RUN_PARENT = join(EVIDENCE_ROOT, "run");
const RUN_ID = /^[a-z0-9][a-z0-9-]{0,47}$/u;
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;

export class EvidenceError extends Error {
  constructor(code) {
    super(code);
    this.name = "EvidenceError";
    this.code = code;
  }
}

export const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

export function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object" && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

export const canonicalJsonBytes = (value) =>
  Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");

function assertRealDirectory(path, code) {
  const stat = lstatSync(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || realpathSync(path) !== resolve(path)) {
    throw new EvidenceError(code);
  }
  return Object.freeze({ dev: stat.dev, ino: stat.ino, path: resolve(path) });
}

function fsyncDirectory(path) {
  const fd = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isDirectory()) throw new EvidenceError("EVIDENCE_PARENT_INVALID");
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}

export function validateRunId(runId) {
  if (typeof runId !== "string" || !RUN_ID.test(runId)) throw new EvidenceError("RUN_ID_INVALID");
  return runId;
}

export function productionRunRoot(runId) {
  validateRunId(runId);
  assertRealDirectory(EVIDENCE_ROOT, "EVIDENCE_ROOT_INVALID");
  assertRealDirectory(RUN_PARENT, "RUN_PARENT_INVALID");
  const root = join(RUN_PARENT, runId);
  if (dirname(root) !== RUN_PARENT || basename(root) !== runId) throw new EvidenceError("RUN_ROOT_ESCAPE");
  return root;
}

export function createRunRoot(root) {
  if (!isAbsolute(root)) throw new EvidenceError("RUN_ROOT_NOT_ABSOLUTE");
  const parent = dirname(root);
  const parentIdentity = assertRealDirectory(parent, "RUN_PARENT_INVALID");
  mkdirSync(root, { mode: 0o700 });
  const directoryFd = openSync(root, fsConstants.O_RDONLY | O_NOFOLLOW);
  try {
    const opened = fstatSync(directoryFd);
    if (!opened.isDirectory()) throw new EvidenceError("RUN_ROOT_INVALID");
    fchmodSync(directoryFd, 0o700);
    fsyncSync(directoryFd);
  } finally {
    closeSync(directoryFd);
  }
  const parentAfter = assertRealDirectory(parent, "RUN_PARENT_INVALID");
  if (parentAfter.dev !== parentIdentity.dev || parentAfter.ino !== parentIdentity.ino) {
    throw new EvidenceError("RUN_PARENT_IDENTITY_DRIFT");
  }
  fsyncDirectory(parent);
  const identity = assertRealDirectory(root, "RUN_ROOT_INVALID");
  const ownership = {
    schema: "P1-062-RUN-OWNERSHIP/1",
    nonce: randomBytes(32).toString("hex"),
    root_basename: basename(root),
    root_device: String(identity.dev),
    root_inode: String(identity.ino),
    created_exclusively: true,
  };
  writeCreateOnce(join(root, "ownership.json"), canonicalJsonBytes(ownership));
  return identity;
}

export function assertOwnedProductionRunRoot(runId) {
  const root = productionRunRoot(runId);
  const identity = assertRealDirectory(root, "RUN_ROOT_INVALID");
  const ownershipBytes = readRegular(join(root, "ownership.json"), 2048);
  let ownership;
  try {
    ownership = JSON.parse(ownershipBytes.toString("utf8"));
  } catch {
    throw new EvidenceError("RUN_OWNERSHIP_INVALID");
  }
  const keys = Object.keys(ownership ?? {}).sort();
  const expectedKeys = [
    "created_exclusively",
    "nonce",
    "root_basename",
    "root_device",
    "root_inode",
    "schema",
  ];
  if (
    !ownership ||
    Array.isArray(ownership) ||
    !ownershipBytes.equals(canonicalJsonBytes(ownership)) ||
    JSON.stringify(keys) !== JSON.stringify(expectedKeys) ||
    ownership.schema !== "P1-062-RUN-OWNERSHIP/1" ||
    ownership.created_exclusively !== true ||
    ownership.root_basename !== runId ||
    ownership.root_device !== String(identity.dev) ||
    ownership.root_inode !== String(identity.ino) ||
    typeof ownership.nonce !== "string" ||
    !/^[0-9a-f]{64}$/u.test(ownership.nonce)
  ) {
    throw new EvidenceError("RUN_OWNERSHIP_INVALID");
  }
  return Object.freeze({ root, identity });
}

export function assertOwnedRunRoot(root, identity) {
  const current = assertRealDirectory(root, "RUN_ROOT_INVALID");
  if (!identity || current.dev !== identity.dev || current.ino !== identity.ino) {
    throw new EvidenceError("RUN_ROOT_IDENTITY_DRIFT");
  }
}

export function writeCreateOnce(path, bytes, mode = 0o400) {
  if (!Buffer.isBuffer(bytes)) throw new EvidenceError("EVIDENCE_BYTES_REQUIRED");
  const parent = dirname(path);
  const parentIdentity = assertRealDirectory(parent, "EVIDENCE_PARENT_INVALID");
  const flags = fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | O_NOFOLLOW;
  const fd = openSync(path, flags, mode);
  let opened;
  try {
    opened = fstatSync(fd);
    if (!opened.isFile() || opened.nlink !== 1) throw new EvidenceError("EVIDENCE_LEAF_INVALID");
    let offset = 0;
    while (offset < bytes.length) offset += writeSync(fd, bytes, offset, bytes.length - offset);
    fsyncSync(fd);
    fchmodSync(fd, mode);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  const parentAfter = assertRealDirectory(parent, "EVIDENCE_PARENT_INVALID");
  if (parentAfter.dev !== parentIdentity.dev || parentAfter.ino !== parentIdentity.ino) {
    throw new EvidenceError("EVIDENCE_PARENT_IDENTITY_DRIFT");
  }
  const final = lstatSync(path);
  if (
    !opened ||
    !final.isFile() ||
    final.isSymbolicLink() ||
    final.nlink !== 1 ||
    final.size !== bytes.length ||
    final.dev !== opened.dev ||
    final.ino !== opened.ino
  ) {
    throw new EvidenceError("EVIDENCE_LEAF_INVALID");
  }
  fsyncDirectory(parent);
  return Object.freeze({ path, byte_length: bytes.length, sha256: sha256(bytes) });
}

export function readRegular(path, maxBytes = undefined) {
  const before = lstatSync(path);
  if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1 || realpathSync(path) !== resolve(path)) {
    throw new EvidenceError("INPUT_FILE_INVALID");
  }
  if (maxBytes !== undefined && before.size > maxBytes) throw new EvidenceError("INPUT_FILE_TOO_LARGE");
  const fd = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  try {
    const opened = fstatSync(fd);
    if (opened.dev !== before.dev || opened.ino !== before.ino) throw new EvidenceError("INPUT_IDENTITY_DRIFT");
    const bytes = readFileSync(fd);
    const after = fstatSync(fd);
    if (after.dev !== opened.dev || after.ino !== opened.ino || after.size !== opened.size) {
      throw new EvidenceError("INPUT_IDENTITY_DRIFT");
    }
    return bytes;
  } finally {
    closeSync(fd);
  }
}

export function assertContained(path, root) {
  const absolute = resolve(path);
  const base = resolve(root);
  if (absolute !== base && !absolute.startsWith(`${base}${sep}`)) throw new EvidenceError("PATH_ESCAPE");
  return absolute;
}

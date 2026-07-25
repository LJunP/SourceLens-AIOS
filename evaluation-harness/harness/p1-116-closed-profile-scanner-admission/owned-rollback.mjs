import {
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmdirSync,
  unlinkSync,
} from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { randomBytes } from "node:crypto";

import {
  P116NonPass,
  assert,
  assertAbsoluteNormalized,
  assertContained,
  canonicalBytes,
  directoryIdentity,
  fail,
  fileIdentity,
  sameIdentity,
  sha256,
  writeCreateOnce,
} from "./core.mjs";

function lstatOrNull(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

function normalizedRelative(root, path) {
  const absolute = assertContained(root, path);
  const rel = relative(root, absolute);
  assert(
    rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel)),
    "PATH_ESCAPE_REJECTED",
    `path escapes owned root: ${absolute}`,
  );
  return rel === "" ? "." : rel.split(sep).join("/");
}

function typeOf(stat) {
  if (stat.isSymbolicLink()) return "SYMLINK";
  if (stat.isFile()) return "REGULAR_FILE";
  if (stat.isDirectory()) return "DIRECTORY";
  return "OTHER";
}

function identityAt(path) {
  const stat = lstatOrNull(path);
  if (!stat) {
    return { path, type: "MISSING" };
  }
  if (stat.isFile() && !stat.isSymbolicLink()) {
    return fileIdentity(path, "ROLLBACK_IDENTITY_DRIFT");
  }
  return {
    path,
    dev: String(stat.dev),
    ino: String(stat.ino),
    uid: stat.uid,
    gid: stat.gid,
    mode: stat.mode & 0o7777,
    type: typeOf(stat),
  };
}

function depth(relativePath) {
  return relativePath === "." ? 0 : relativePath.split("/").length;
}

export class OwnedTree {
  static create(rootPath) {
    assertAbsoluteNormalized(rootPath, "OUTPUT_ROOT_INVALID", "owned root");
    const existing = lstatOrNull(rootPath);
    assert(existing === null, "OUTPUT_ROOT_PREEXISTS", `owned root already exists: ${rootPath}`);
    const parent = dirname(rootPath);
    const parentIdentity = directoryIdentity(parent, "OUTPUT_PARENT_INVALID");
    mkdirSync(rootPath, { mode: 0o700, recursive: false });
    const tree = new OwnedTree(rootPath, parentIdentity);
    tree.recordDirectory(".");
    const markerPayload = {
      schema_version: "p1-116-owned-root-marker/v1",
      nonce: randomBytes(32).toString("hex"),
      root_creation_identity: tree.records.get("."),
      claim_boundary: "EXACT_CREATED_OWNED_OBJECTS_ONLY",
    };
    tree.writeFile(".p1-116-owned-root.json", canonicalBytes(markerPayload), 0o600);
    tree.markerRelativePath = ".p1-116-owned-root.json";
    return tree;
  }

  constructor(rootPath, parentIdentity) {
    this.root = rootPath;
    this.parent_identity = parentIdentity;
    this.records = new Map();
    this.markerRelativePath = null;
  }

  absolute(relativePath) {
    assert(
      typeof relativePath === "string" && relativePath.length > 0,
      "PATH_INVALID",
      "owned relative path is empty",
    );
    const candidate = relativePath === "." ? this.root : resolve(this.root, relativePath);
    assert(normalizedRelative(this.root, candidate) === relativePath.split(sep).join("/"),
      "PATH_ESCAPE_REJECTED", `owned path is not normalized: ${relativePath}`);
    return candidate;
  }

  recordDirectory(relativePath) {
    const path = this.absolute(relativePath);
    const identity = directoryIdentity(path, "OWNED_DIRECTORY_INVALID");
    const record = { ...identity, path: relativePath };
    this.records.set(relativePath, record);
    return record;
  }

  createDirectory(relativePath, mode = 0o700) {
    const path = this.absolute(relativePath);
    assert(lstatOrNull(path) === null, "OWNED_PATH_PREEXISTS", `owned directory preexists: ${relativePath}`);
    const parentRelative = dirname(relativePath).split(sep).join("/");
    const parentKey = parentRelative === "." ? "." : parentRelative;
    assert(this.records.get(parentKey)?.type === "DIRECTORY", "OWNED_PARENT_INVALID",
      `owned parent is undeclared: ${parentKey}`);
    mkdirSync(path, { mode, recursive: false });
    return this.recordDirectory(relativePath);
  }

  writeFile(relativePath, bytes, mode = 0o600) {
    const path = this.absolute(relativePath);
    const parentRelative = dirname(relativePath).split(sep).join("/");
    const parentKey = parentRelative === "." ? "." : parentRelative;
    assert(this.records.get(parentKey)?.type === "DIRECTORY", "OWNED_PARENT_INVALID",
      `owned parent is undeclared: ${parentKey}`);
    const identity = writeCreateOnce(path, bytes, mode);
    const record = { ...identity, path: relativePath };
    this.records.set(relativePath, record);
    return record;
  }

  copyTemplate(sourceRoot, destinationRelative = "source") {
    const source = resolve(sourceRoot);
    const sourceIdentity = directoryIdentity(source, "SOURCE_TEMPLATE_INVALID");
    this.createDirectory(destinationRelative);
    const copied = [];
    const walk = (sourceDirectory, destinationDirectory) => {
      const entries = readdirSync(sourceDirectory, { withFileTypes: true })
        .sort((left, right) => left.name.localeCompare(right.name));
      for (const entry of entries) {
        const sourcePath = join(sourceDirectory, entry.name);
        const sourceStat = lstatSync(sourcePath);
        assert(!sourceStat.isSymbolicLink(), "SOURCE_TEMPLATE_INVALID",
          `source template contains a symlink: ${sourcePath}`);
        const destination = destinationDirectory === "."
          ? entry.name
          : `${destinationDirectory}/${entry.name}`;
        if (sourceStat.isDirectory()) {
          this.createDirectory(destination);
          walk(sourcePath, destination);
        } else {
          assert(sourceStat.isFile(), "SOURCE_TEMPLATE_INVALID",
            `source template contains a non-regular object: ${sourcePath}`);
          const bytes = readFileSync(sourcePath);
          const created = this.writeFile(destination, bytes, sourceStat.mode & 0o777);
          copied.push({
            source_path: relative(source, sourcePath).split(sep).join("/"),
            destination_path: destination,
            sha256: created.sha256,
            byte_length: created.byte_length,
          });
        }
      }
    };
    walk(source, destinationRelative);
    return { source_identity: sourceIdentity, copied };
  }

  inventory() {
    const observed = new Map();
    const walk = (absolute, relativePath) => {
      const identity = identityAt(absolute);
      observed.set(relativePath, { ...identity, path: relativePath });
      if (identity.type !== "DIRECTORY") return;
      const entries = readdirSync(absolute, { withFileTypes: true })
        .sort((left, right) => left.name.localeCompare(right.name));
      for (const entry of entries) {
        const childRelative = relativePath === "." ? entry.name : `${relativePath}/${entry.name}`;
        walk(join(absolute, entry.name), childRelative);
      }
    };
    walk(this.root, ".");
    return observed;
  }

  assertOwnedPath(path) {
    let rel;
    try {
      rel = normalizedRelative(this.root, path);
    } catch (error) {
      if (error instanceof P116NonPass && error.code === "PATH_ESCAPE_REJECTED") {
        fail("NONOWNED_CLEANUP_FORBIDDEN",
          `cleanup target is outside the exact owned root: ${path}`);
      }
      throw error;
    }
    assert(this.records.has(rel), "NONOWNED_CLEANUP_FORBIDDEN",
      `cleanup target was not created and recorded by this run: ${path}`);
    return rel;
  }

  verifyExactInventory() {
    const observed = this.inventory();
    const expectedRoot = this.records.get(".");
    const observedRoot = observed.get(".");
    assert(
      sameIdentity(observedRoot, expectedRoot),
      "ROLLBACK_IDENTITY_DRIFT",
      "owned root identity differs from the creation ledger",
      { expected: expectedRoot, actual: observedRoot },
    );
    const expectedPaths = [...this.records.keys()].sort();
    const observedPaths = [...observed.keys()].sort();
    assert(
      expectedPaths.length === observedPaths.length
        && expectedPaths.every((path, index) => path === observedPaths[index]),
      "ROLLBACK_INVENTORY_DRIFT",
      "owned-root inventory differs from the creation ledger",
      { expected_paths: expectedPaths, observed_paths: observedPaths },
    );
    for (const relativePath of expectedPaths) {
      const expected = this.records.get(relativePath);
      const actual = observed.get(relativePath);
      assert(
        sameIdentity(actual, expected),
        "ROLLBACK_IDENTITY_DRIFT",
        `owned object identity drifted: ${relativePath}`,
        { expected, actual },
      );
    }
    return observed;
  }

  cleanup() {
    const verified = this.verifyExactInventory();
    const deletionOrder = [...this.records.keys()]
      .filter((path) => path !== ".")
      .sort((left, right) => {
        const leftType = this.records.get(left).type;
        const rightType = this.records.get(right).type;
        if (leftType !== rightType) {
          if (leftType === "REGULAR_FILE") return -1;
          if (rightType === "REGULAR_FILE") return 1;
        }
        return depth(right) - depth(left) || right.localeCompare(left);
      });
    const removed = [];
    for (const relativePath of deletionOrder) {
      const path = this.absolute(relativePath);
      const expected = this.records.get(relativePath);
      const current = identityAt(path);
      assert(sameIdentity(current, expected), "ROLLBACK_IDENTITY_DRIFT",
        `owned object changed immediately before deletion: ${relativePath}`);
      if (expected.type === "REGULAR_FILE") {
        unlinkSync(path);
      } else if (expected.type === "DIRECTORY") {
        rmdirSync(path);
      } else {
        fail("ROLLBACK_TYPE_INVALID", `unsupported owned object type: ${expected.type}`);
      }
      assert(lstatOrNull(path) === null, "ROLLBACK_DELETE_FAILED",
        `owned object still exists after deletion: ${relativePath}`);
      removed.push({ path: relativePath, creation_identity: expected, deletion_identity: current });
    }
    const rootExpected = this.records.get(".");
    const rootCurrent = identityAt(this.root);
    assert(sameIdentity(rootCurrent, rootExpected), "ROLLBACK_IDENTITY_DRIFT",
      "owned root changed immediately before deletion");
    rmdirSync(this.root);
    assert(lstatOrNull(this.root) === null, "ROLLBACK_DELETE_FAILED", "owned root still exists");
    removed.push({ path: ".", creation_identity: rootExpected, deletion_identity: rootCurrent });
    return {
      schema_version: "p1-116-identity-bound-rollback/v1",
      root: this.root,
      parent_creation_identity: this.parent_identity,
      marker_relative_path: this.markerRelativePath,
      verified_object_count: verified.size,
      removed_object_count: removed.length,
      removed,
      root_final_state: "ABSENT",
      nonowned_paths_touched: 0,
      exact: true,
    };
  }
}

export function preserveDriftFixture(tree, expectedCode, mutate) {
  mutate(tree);
  try {
    tree.cleanup();
    fail("NEGATIVE_FALSE_ACCEPT", `rollback unexpectedly accepted ${expectedCode}`);
  } catch (error) {
    if (!(error instanceof P116NonPass)) throw error;
    assert(error.code === expectedCode, "NEGATIVE_REASON_DRIFT",
      `expected ${expectedCode}, observed ${error.code}`);
    assert(existsSync(tree.root), "NEGATIVE_EFFECT_OCCURRED",
      "drifted root was deleted after fail-closed rejection");
    return {
      expected_reason: expectedCode,
      observed_reason: error.code,
      rejected: true,
      root_preserved: true,
      evidence: error.evidence,
    };
  }
}

export const testOnly = Object.freeze({
  lstatOrNull,
  identityAt,
  renameSync,
  basename,
  sha256,
});

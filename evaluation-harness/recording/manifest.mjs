import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { join, relative, resolve, sep } from "node:path";
import { canonicalJson } from "../evaluator/schema-validator.mjs";
import { sha256 } from "./recorder.mjs";

export const MANIFEST_NAME = "evidence-manifest.json";

function walkFiles(root, current = root) {
  const files = [];
  for (const name of readdirSync(current).sort()) {
    const path = join(current, name);
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) throw new Error(`evidence symlink is forbidden: ${path}`);
    if (stat.isDirectory()) files.push(...walkFiles(root, path));
    else if (stat.isFile()) files.push(relative(root, path));
    else throw new Error(`unsupported evidence entry: ${path}`);
  }
  return files;
}

function entryBytes(entry) {
  return Buffer.from(`${entry.path}\0${entry.sha256}\0${entry.byte_length}\n`, "utf8");
}

export function buildManifest(evidenceRoot, metadata) {
  const root = realpathSync(evidenceRoot);
  const artifacts = walkFiles(root)
    .filter((path) => path !== MANIFEST_NAME)
    .sort()
    .map((path) => {
      const bytes = readFileSync(join(root, path));
      return { path, sha256: sha256(bytes), byte_length: bytes.length };
    });
  const encoded = Buffer.concat(artifacts.map(entryBytes));
  return {
    schema_version: "1.0",
    record_type: "aios_p1_001_harness_evidence_manifest",
    task_id: "AIOS-P1-001",
    claim_boundary: "Harness conformance only; not B0, A0, VTSR, Repository Intelligence, Agent capability, hidden-set, production, or hostile-principal evidence.",
    artifact_count: artifacts.length,
    manifest_entry_encoding: "UTF-8 path + NUL + lowercase SHA-256 + NUL + decimal byte length + LF",
    manifest_root_sha256: sha256(encoded),
    artifacts,
    ...metadata,
  };
}

export function verifyManifest(evidenceRoot, manifest) {
  const root = realpathSync(evidenceRoot);
  const expectedKeys = [
    "schema_version", "record_type", "task_id", "claim_boundary", "artifact_count",
    "manifest_entry_encoding", "manifest_root_sha256", "artifacts", "freeze_receipt_sha256",
    "runtime", "primary_projection_sha256", "replay_projection_sha256", "replay_equal",
    "controlled_failure_rejected", "promotion_probe_rejected",
  ].sort();
  if (JSON.stringify(Object.keys(manifest).sort()) !== JSON.stringify(expectedKeys)) {
    throw new Error("manifest keys do not match the closed evidence contract");
  }
  if (!Array.isArray(manifest.artifacts) || manifest.artifact_count !== manifest.artifacts.length) {
    throw new Error("manifest artifact count mismatch");
  }
  const paths = manifest.artifacts.map((entry) => entry.path);
  if (JSON.stringify(paths) !== JSON.stringify([...paths].sort()) || new Set(paths).size !== paths.length) {
    throw new Error("manifest artifact paths are not unique and sorted");
  }
  const actualPaths = walkFiles(root).filter((path) => path !== MANIFEST_NAME).sort();
  if (JSON.stringify(paths) !== JSON.stringify(actualPaths)) {
    throw new Error("manifest artifact population mismatch");
  }
  for (const entry of manifest.artifacts) {
    if (!/^[0-9a-f]{64}$/.test(entry.sha256) || !Number.isInteger(entry.byte_length)) {
      throw new Error(`invalid manifest entry for ${entry.path}`);
    }
    const candidate = resolve(root, entry.path);
    const realCandidate = realpathSync(candidate);
    const rel = relative(root, realCandidate);
    if (rel === ".." || rel.startsWith(`..${sep}`)) throw new Error(`manifest path escaped evidence root: ${entry.path}`);
    const bytes = readFileSync(realCandidate);
    if (bytes.length !== entry.byte_length || sha256(bytes) !== entry.sha256) {
      throw new Error(`manifest artifact mismatch: ${entry.path}`);
    }
  }
  const rootHash = sha256(Buffer.concat(manifest.artifacts.map(entryBytes)));
  if (rootHash !== manifest.manifest_root_sha256) throw new Error("manifest root hash mismatch");
  if (!manifest.replay_equal || !manifest.controlled_failure_rejected || !manifest.promotion_probe_rejected) {
    throw new Error("manifest acceptance booleans are not all true");
  }
  return { valid: true, manifest_sha256: sha256(Buffer.from(`${canonicalJson(manifest)}\n`, "utf8")) };
}

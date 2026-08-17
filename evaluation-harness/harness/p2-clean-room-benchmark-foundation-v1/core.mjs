import { createHash } from "node:crypto";
import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import path from "node:path";

export const SOURCE_PACK_IDENTITY = Object.freeze({
  artifactId: "P2_BENCHMARK_SOURCE_PACK_V1",
  byteLength: 94630,
  sha256: "c5f38070b8f0ed445c759f3380769c2dec5493e0f4120f681b9b1cab3fd67884",
});

export const BENCHMARK_SPEC = Object.freeze({
  schemaVersion: "p2-clean-room-benchmark-foundation/v1",
  devTaskCount: 8,
  heldTaskCount: 4,
  repositoryCount: 6,
  tasksPerRepository: 2,
  topK: 10,
  byteBudget: 131072,
  tokenization: "NFKC_CASEFOLD_CAMEL_AND_ALNUM_V1",
  b0: "DISTINCT_QUERY_TOKEN_OVERLAP_V1",
  b1: "BM25_K1_1_2_B_0_75_V1",
  tieBreak: "SCORE_DESC_THEN_REPOSITORY_RELATIVE_PATH_ASC_UTF8",
});

export class BenchmarkInputError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`);
    this.name = "BenchmarkInputError";
    this.code = code;
  }
}

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

export function stableJson(value) {
  return `${JSON.stringify(canonicalize(value), null, 2)}\n`;
}

export function assertIdentity(bytes, expected, label) {
  if (bytes.length !== expected.byteLength || sha256(bytes) !== expected.sha256) {
    throw new BenchmarkInputError("IDENTITY_DRIFT", `${label} does not match its frozen identity`);
  }
}

export function safeRelative(value, label = "path") {
  if (typeof value !== "string" || value.length === 0 || value.includes("\0")) {
    throw new BenchmarkInputError("PATH_INVALID", `${label} is empty or contains NUL`);
  }
  const normalized = value.replaceAll("\\", "/");
  if (path.posix.isAbsolute(normalized) || path.posix.normalize(normalized) !== normalized ||
      normalized === "." || normalized === ".." || normalized.startsWith("../")) {
    throw new BenchmarkInputError("PATH_ESCAPE", `${label} is not a normalized root-relative path`);
  }
  return normalized;
}

export function isProductionJava(relativePath) {
  const value = safeRelative(relativePath, "Java source path");
  const segments = value.toLowerCase().split("/");
  if (!value.endsWith(".java") || segments.includes("test") || segments.includes("tests") ||
      segments.includes("generated") || segments.includes("target") || segments.includes("build")) {
    return false;
  }
  return value === "src/main/java" || value.startsWith("src/main/java/") ||
    value.includes("/src/main/java/");
}

export function tokenize(input) {
  const expanded = String(input)
    .normalize("NFKC")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase();
  return expanded.match(/[\p{L}\p{N}_]+/gu) ?? [];
}

function frequency(tokens) {
  const result = new Map();
  for (const token of tokens) result.set(token, (result.get(token) ?? 0) + 1);
  return result;
}

export function validateSourcePack(manifest) {
  if (manifest?.schema_version !== "p2-benchmark-source-pack/v1" ||
      manifest?.artifact_id !== SOURCE_PACK_IDENTITY.artifactId ||
      manifest?.status !== "ACCEPTED_INSTALLED_CREATE_ONCE") {
    throw new BenchmarkInputError("MANIFEST_INVALID", "source pack lifecycle identity is not accepted");
  }
  if (!Array.isArray(manifest.tasks) || !Array.isArray(manifest.inventory)) {
    throw new BenchmarkInputError("MANIFEST_INVALID", "tasks and inventory must be arrays");
  }
  const ids = manifest.tasks.map((task) => task.task_id);
  if (ids.some((id) => typeof id !== "string") || new Set(ids).size !== ids.length) {
    throw new BenchmarkInputError("DUPLICATE_TASK_ID", "task IDs must be unique strings");
  }
  const devIds = manifest.split?.DEV?.task_ids;
  const heldIds = manifest.split?.HELD?.task_ids;
  if (!Array.isArray(devIds) || !Array.isArray(heldIds) ||
      devIds.length !== BENCHMARK_SPEC.devTaskCount || heldIds.length !== BENCHMARK_SPEC.heldTaskCount ||
      devIds.some((id) => heldIds.includes(id))) {
    throw new BenchmarkInputError("SPLIT_INVALID", "DEV and HELD must be closed and disjoint 8/4 sets");
  }
  const byId = new Map(manifest.tasks.map((task) => [task.task_id, task]));
  if ([...devIds, ...heldIds].some((id) => !byId.has(id)) || byId.size !== 12) {
    throw new BenchmarkInputError("SPLIT_INVALID", "split does not cover exactly twelve tasks");
  }
  for (const id of devIds) {
    if (byId.get(id).split !== "DEV") throw new BenchmarkInputError("SPLIT_INVALID", `${id} split drift`);
  }
  for (const id of heldIds) {
    if (byId.get(id).split !== "HELD") throw new BenchmarkInputError("SPLIT_INVALID", `${id} split drift`);
  }
  const repositories = new Map();
  for (const task of manifest.tasks) {
    repositories.set(task.repository, (repositories.get(task.repository) ?? 0) + 1);
  }
  if (repositories.size !== BENCHMARK_SPEC.repositoryCount ||
      [...repositories.values()].some((count) => count !== BENCHMARK_SPEC.tasksPerRepository)) {
    throw new BenchmarkInputError("REPOSITORY_CARDINALITY_INVALID", "expected six repositories with two tasks each");
  }
  const inventory = new Map();
  for (const item of manifest.inventory) {
    const relativePath = safeRelative(item.relative_path, "inventory path");
    if (inventory.has(relativePath)) throw new BenchmarkInputError("INVENTORY_DUPLICATE", relativePath);
    inventory.set(relativePath, item);
  }
  return { byId, devIds: [...devIds], heldIds: [...heldIds], inventory, repositories };
}

export function selectDevTasks(manifest, requestedIds = null) {
  const validated = validateSourcePack(manifest);
  const ids = requestedIds ?? validated.devIds;
  for (const id of ids) {
    if (!validated.devIds.includes(id)) {
      throw new BenchmarkInputError("HELD_OR_UNKNOWN_TASK_FORBIDDEN", `${id} is not executable DEV custody`);
    }
  }
  return ids.map((id) => validated.byId.get(id));
}

async function assertRoot(root, label) {
  const absolute = path.resolve(root);
  const observed = await realpath(absolute);
  if (observed !== absolute) throw new BenchmarkInputError("ROOT_SYMLINK", `${label} is not canonical`);
  const stat = await lstat(absolute);
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new BenchmarkInputError("ROOT_INVALID", `${label} must be a non-symlink directory`);
  }
  return absolute;
}

async function assertAncestorChain(root, relativePath) {
  let current = root;
  for (const segment of safeRelative(relativePath).split("/")) {
    current = path.join(current, segment);
    const stat = await lstat(current);
    if (stat.isSymbolicLink()) throw new BenchmarkInputError("SYMLINK_INPUT", relativePath);
  }
  return current;
}

export async function readBoundLeaf(root, relativePath, expected, readSet, purpose) {
  const normalized = safeRelative(relativePath, "bound leaf");
  const absoluteRoot = await assertRoot(root, "source root");
  const absolute = await assertAncestorChain(absoluteRoot, normalized);
  const stat = await lstat(absolute);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new BenchmarkInputError("LEAF_INVALID", normalized);
  const bytes = await readFile(absolute);
  assertIdentity(bytes, { byteLength: expected.byte_length, sha256: expected.sha256 }, normalized);
  readSet.set(normalized, {
    relative_path: normalized,
    purpose,
    pre_read_expected: { byte_length: expected.byte_length, sha256: expected.sha256 },
    post_read_observed: { byte_length: bytes.length, sha256: sha256(bytes) },
  });
  return bytes;
}

async function walkProductionJava(root, relative = "") {
  const absolute = relative ? await assertAncestorChain(root, relative) : root;
  const names = (await readdir(absolute)).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
  const results = [];
  for (const name of names) {
    const child = relative ? `${relative}/${name}` : name;
    const normalized = safeRelative(child, "tree leaf");
    const stat = await lstat(path.join(root, normalized));
    if (stat.isSymbolicLink()) throw new BenchmarkInputError("SYMLINK_INPUT", normalized);
    if (stat.isDirectory()) {
      results.push(...await walkProductionJava(root, normalized));
    } else if (stat.isFile() && isProductionJava(normalized)) {
      results.push({ relativePath: normalized, byteLength: stat.size, mode: stat.mode & 0o777 });
    }
  }
  return results;
}

export async function loadCorpus(sourceRoot, task, readSet) {
  const treeRelative = safeRelative(
    `source-packs/materialized/${task.base.pack_basename}/${task.base.archive.top_directory}`,
    `${task.task_id} base tree`,
  );
  const sourceRootReal = await assertRoot(sourceRoot, "accepted source root");
  const treeRoot = await assertAncestorChain(sourceRootReal, treeRelative);
  const treeStat = await lstat(treeRoot);
  if (!treeStat.isDirectory() || treeStat.isSymbolicLink()) {
    throw new BenchmarkInputError("BASE_TREE_INVALID", task.task_id);
  }
  const leaves = await walkProductionJava(treeRoot);
  if (leaves.length === 0) throw new BenchmarkInputError("EMPTY_CORPUS", task.task_id);
  const corpus = [];
  for (const leaf of leaves) {
    const absolute = await assertAncestorChain(treeRoot, leaf.relativePath);
    const bytes = await readFile(absolute);
    const observedSha = sha256(bytes);
    const sourceRelative = `${treeRelative}/${leaf.relativePath}`;
    readSet.set(sourceRelative, {
      relative_path: sourceRelative,
      purpose: `DEV_CORPUS_${task.task_id}`,
      pre_read_expected: {
        archive_relative_path: task.base.archive.relative_path,
        archive_sha256: task.base.archive.sha256,
        archive_tree: task.base.tree,
        tree_entry: leaf.relativePath,
        byte_length: leaf.byteLength,
        mode: leaf.mode,
      },
      post_read_observed: { byte_length: bytes.length, sha256: observedSha },
    });
    corpus.push({
      path: leaf.relativePath,
      byteLength: bytes.length,
      sha256: observedSha,
      tokens: tokenize(bytes.toString("utf8")),
    });
  }
  return corpus;
}

export function maintenanceQuery(pr) {
  const title = typeof pr.title === "string" ? pr.title.trim() : "";
  const body = typeof pr.body === "string" ? pr.body.trim() : "";
  if (!title) throw new BenchmarkInputError("QUERY_MISSING", "PR title is empty");
  return body ? `${title}\n\n${body}` : title;
}

export function groundTruthFromFiles(files) {
  if (!Array.isArray(files)) throw new BenchmarkInputError("PR_FILES_INVALID", "PR files payload is not an array");
  const groundTruth = files
    .map((item) => item?.filename)
    .filter((filename) => typeof filename === "string" && isProductionJava(filename))
    .map((filename) => safeRelative(filename))
    .sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
  if (groundTruth.length === 0 || new Set(groundTruth).size !== groundTruth.length) {
    throw new BenchmarkInputError("GROUND_TRUTH_INVALID", "production-Java ground truth is empty or duplicated");
  }
  return groundTruth;
}

function scoreB0(queryTokens, corpus) {
  const querySet = new Set(queryTokens);
  return corpus.map((document) => {
    const documentSet = new Set(document.tokens);
    let score = 0;
    for (const token of querySet) if (documentSet.has(token)) score += 1;
    return { ...document, score };
  });
}

function scoreB1(queryTokens, corpus) {
  const queryTerms = [...new Set(queryTokens)];
  const documentFrequency = new Map();
  for (const term of queryTerms) {
    documentFrequency.set(term, corpus.filter((document) => document.tokens.includes(term)).length);
  }
  const averageLength = corpus.reduce((sum, document) => sum + document.tokens.length, 0) / corpus.length;
  const k1 = 1.2;
  const b = 0.75;
  return corpus.map((document) => {
    const frequencies = frequency(document.tokens);
    let score = 0;
    for (const term of queryTerms) {
      const tf = frequencies.get(term) ?? 0;
      if (tf === 0) continue;
      const df = documentFrequency.get(term);
      const idf = Math.log(1 + (corpus.length - df + 0.5) / (df + 0.5));
      const denominator = tf + k1 * (1 - b + b * document.tokens.length / averageLength);
      score += idf * (tf * (k1 + 1)) / denominator;
    }
    return { ...document, score };
  });
}

export function rankDocuments(algorithm, query, corpus) {
  const queryTokens = tokenize(query);
  if (queryTokens.length === 0) throw new BenchmarkInputError("QUERY_EMPTY", "query has no tokens");
  const scored = algorithm === "B0" ? scoreB0(queryTokens, corpus) :
    algorithm === "B1" ? scoreB1(queryTokens, corpus) : null;
  if (!scored) throw new BenchmarkInputError("ALGORITHM_UNKNOWN", algorithm);
  return scored.sort((left, right) => {
    if (right.score !== left.score) return right.score - left.score;
    return Buffer.compare(Buffer.from(left.path), Buffer.from(right.path));
  });
}

export function selectWithinBudget(ranked, topK = BENCHMARK_SPEC.topK, byteBudget = BENCHMARK_SPEC.byteBudget) {
  const selected = [];
  let selectedBytes = 0;
  for (const item of ranked) {
    if (selected.length >= topK) break;
    if (selectedBytes + item.byteLength > byteBudget) continue;
    selected.push(item);
    selectedBytes += item.byteLength;
  }
  return { selected, selectedBytes };
}

export function taskMetrics(selected, groundTruth) {
  const truth = new Set(groundTruth);
  const relevant = selected.filter((item) => truth.has(item.path));
  const firstRelevant = selected.findIndex((item) => truth.has(item.path));
  return {
    recall: relevant.length / truth.size,
    precision: selected.length === 0 ? 0 : relevant.length / selected.length,
    reciprocal_rank: firstRelevant < 0 ? 0 : 1 / (firstRelevant + 1),
    relevant_selected: relevant.length,
    ground_truth_count: truth.size,
    selected_count: selected.length,
  };
}

export function compactRanked(ranked) {
  return ranked.map((item, index) => ({
    rank: index + 1,
    path: item.path,
    byte_length: item.byteLength,
    sha256: item.sha256,
    score: Number(item.score.toFixed(12)),
  }));
}

export function macroMetrics(results) {
  const keys = ["recall", "precision", "reciprocal_rank"];
  return Object.fromEntries(keys.map((key) => [
    `macro_${key}`,
    results.reduce((sum, item) => sum + item.metrics[key], 0) / results.length,
  ]));
}

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

export class EvaluationError extends Error {
  constructor(reasonCode, message) {
    super(message);
    this.name = "EvaluationError";
    this.reasonCode = reasonCode;
  }
}

const fail = (code, message) => {
  throw new EvaluationError(code, message);
};

const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, stable(value[key])]),
    );
  }
  return value;
};

export const stableJson = (value) => JSON.stringify(stable(value));
export const sha256 = (value) =>
  crypto.createHash("sha256").update(value).digest("hex");

const exactKeys = (object, keys, code = "CLOSED_RESULT_SCHEMA") => {
  if (!object || typeof object !== "object" || Array.isArray(object)) fail(code, "object required");
  const actual = Object.keys(object).sort();
  const expected = [...keys].sort();
  if (stableJson(actual) !== stableJson(expected)) {
    fail(code, `closed schema mismatch: ${actual.join(",")}`);
  }
};

const readRegular = (file) => {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("INPUT_TYPE_INVALID", `${file} must be a regular non-symlink file`);
  }
  return fs.readFileSync(file);
};

const readJson = (file) => JSON.parse(readRegular(file).toString("utf8"));

const safeRelativePath = (candidate) => {
  if (
    typeof candidate !== "string" ||
    candidate.length === 0 ||
    path.isAbsolute(candidate) ||
    candidate.includes("\0") ||
    candidate.split("/").includes("..")
  ) {
    fail("RESULT_PATH_INVALID", `unsafe repository path: ${candidate}`);
  }
};

const gitBytes = (repoRoot, snapshot, relativePath) => {
  safeRelativePath(relativePath);
  try {
    const object = `${snapshot}:${relativePath}`;
    const type = execFileSync("git", ["cat-file", "-t", object], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
    if (type !== "blob") fail("RESULT_PATH_TYPE_INVALID", `${relativePath} is not a blob`);
    return {
      bytes: execFileSync("git", ["show", object], {
        cwd: repoRoot,
        stdio: ["ignore", "pipe", "pipe"],
      }),
      blob: execFileSync("git", ["rev-parse", object], {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      }).trim(),
    };
  } catch (error) {
    if (error instanceof EvaluationError) throw error;
    fail("RESULT_PATH_NOT_IN_SNAPSHOT", `${relativePath} is absent from ${snapshot}`);
  }
};

const runProjection = (run) => ({
  task_id: run.task_id,
  snapshot_commit: run.snapshot_commit,
  ranked_items: run.ranked_items,
});

const percentile95 = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.ceil(sorted.length * 0.95) - 1];
};

const validateIdentity = (identity, source, relativePath) => {
  exactKeys(identity, ["git_blob_sha1", "sha256", "byte_length"]);
  if (
    identity.git_blob_sha1 !== source.blob ||
    identity.byte_length !== source.bytes.length ||
    identity.sha256 !== sha256(source.bytes)
  ) {
    fail("RESULT_FILE_IDENTITY_MISMATCH", `${relativePath} identity mismatch`);
  }
};

const validateEvidence = (item, source) => {
  if (!Array.isArray(item.evidence_spans) || item.evidence_spans.length === 0) {
    fail("EVIDENCE_SPAN_REQUIRED", `${item.path} requires evidence`);
  }
  const spanBytes = item.evidence_spans.map((span) => {
    exactKeys(span, ["start_byte", "end_byte", "sha256"]);
    if (
      !Number.isSafeInteger(span.start_byte) ||
      !Number.isSafeInteger(span.end_byte) ||
      span.start_byte < 0 ||
      span.end_byte <= span.start_byte ||
      span.end_byte > source.bytes.length
    ) {
      fail("EVIDENCE_SPAN_BOUNDS", `${item.path} evidence bounds invalid`);
    }
    const bytes = source.bytes.subarray(span.start_byte, span.end_byte);
    if (sha256(bytes) !== span.sha256) {
      fail("EVIDENCE_SPAN_HASH_MISMATCH", `${item.path} evidence hash mismatch`);
    }
    return bytes.toString("utf8");
  });

  if (!Array.isArray(item.symbols) || item.symbols.length === 0) {
    fail("SYMBOL_EVIDENCE_REQUIRED", `${item.path} requires at least one symbol`);
  }
  for (const symbol of item.symbols) {
    exactKeys(symbol, ["name", "evidence_span_index"]);
    if (
      typeof symbol.name !== "string" ||
      symbol.name.length < 2 ||
      !Number.isSafeInteger(symbol.evidence_span_index) ||
      !spanBytes[symbol.evidence_span_index]?.includes(symbol.name)
    ) {
      fail("SYMBOL_EVIDENCE_MISMATCH", `${item.path} symbol is not proven by its span`);
    }
  }

  const kinds = new Set([
    "lexical",
    "symbol",
    "one_hop_relation",
    "package_affinity",
    "role_diversity",
  ]);
  if (!Array.isArray(item.stable_rationale) || item.stable_rationale.length === 0) {
    fail("STABLE_RATIONALE_REQUIRED", `${item.path} requires a stable rationale`);
  }
  for (const reason of item.stable_rationale) {
    exactKeys(reason, ["kind", "anchor", "evidence_span_index"]);
    if (
      !kinds.has(reason.kind) ||
      typeof reason.anchor !== "string" ||
      reason.anchor.length < 2 ||
      !Number.isSafeInteger(reason.evidence_span_index) ||
      !spanBytes[reason.evidence_span_index]
        ?.toLowerCase()
        .includes(reason.anchor.toLowerCase())
    ) {
      fail("STABLE_RATIONALE_MISMATCH", `${item.path} rationale lacks exact evidence`);
    }
  }
};

const validateRunList = ({ list, taskMap, repoRoot, kind }) => {
  if (!Array.isArray(list) || list.length !== taskMap.size) {
    fail("RESULT_TASK_SET_MISMATCH", `${kind} must contain every validation task once`);
  }
  const seenTasks = new Set();
  for (const run of list) {
    exactKeys(run, [
      "run_id",
      "task_id",
      "snapshot_commit",
      "ranked_items",
      "metrics",
      "stable_projection_sha256",
    ]);
    const task = taskMap.get(run.task_id);
    if (!task || seenTasks.has(run.task_id)) {
      fail("RESULT_TASK_SET_MISMATCH", `unexpected or duplicate task ${run.task_id}`);
    }
    seenTasks.add(run.task_id);
    if (typeof run.run_id !== "string" || run.run_id.length < 3) fail("RUN_ID_INVALID", "run ID invalid");
    if (run.snapshot_commit !== task.parent_commit) {
      fail("SNAPSHOT_IDENTITY_MISMATCH", `snapshot mismatch for ${run.task_id}`);
    }
    if (!Array.isArray(run.ranked_items) || run.ranked_items.length > 10) {
      fail("RESULT_LIMIT_EXCEEDED", `${run.task_id} returned more than ten items`);
    }
    const seenPaths = new Set();
    let selectedBytes = 0;
    for (const [index, item] of run.ranked_items.entries()) {
      exactKeys(item, [
        "rank",
        "path",
        "identity",
        "symbols",
        "evidence_spans",
        "stable_rationale",
      ]);
      if (item.rank !== index + 1) fail("RESULT_RANK_INVALID", `${item.path} rank mismatch`);
      if (seenPaths.has(item.path)) fail("RESULT_PATH_DUPLICATE", `${item.path} duplicated`);
      seenPaths.add(item.path);
      const source = gitBytes(repoRoot, run.snapshot_commit, item.path);
      validateIdentity(item.identity, source, item.path);
      validateEvidence(item, source);
      selectedBytes += source.bytes.length;
    }
    exactKeys(run.metrics, [
      "cold_index_ms",
      "query_ms",
      "end_to_end_ms",
      "selected_bytes",
    ]);
    for (const key of ["cold_index_ms", "query_ms", "end_to_end_ms"]) {
      if (!Number.isFinite(run.metrics[key]) || run.metrics[key] <= 0) {
        fail("LATENCY_INVALID", `${run.task_id} ${key} must be finite and positive`);
      }
    }
    if (run.metrics.end_to_end_ms < run.metrics.cold_index_ms + run.metrics.query_ms) {
      fail("LATENCY_ACCOUNTING_MISMATCH", `${run.task_id} latency components exceed end-to-end`);
    }
    if (!Number.isSafeInteger(run.metrics.selected_bytes) || run.metrics.selected_bytes !== selectedBytes) {
      fail("SELECTED_BYTES_MISMATCH", `${run.task_id} byte accounting mismatch`);
    }
    if (run.stable_projection_sha256 !== sha256(stableJson(runProjection(run)))) {
      fail("RUN_PROJECTION_HASH_MISMATCH", `${run.task_id} projection hash mismatch`);
    }
  }
};

const expectedInventory = ({ repoRoot, publicRoot, privateRoot, validationSpecs }) => {
  const publicFiles = ["manifest.json", "simple-lexical-baseline-spec.json", "target-config.json", "candidate-result-contract.json", "quality-observer-contract.json"];
  const entries = publicFiles.map((name) => {
    const bytes = readRegular(path.join(publicRoot, name));
    return {
      path: `public://${name}`,
      sha256: sha256(bytes),
      byte_length: bytes.length,
      role: "public_contract",
      visible_to_selector: true,
    };
  });
  for (const task of validationSpecs.tasks) {
    const issue = Buffer.from(task.issue, "utf8");
    entries.push({
      path: `sealed://${task.task_id}/issue`,
      sha256: sha256(issue),
      byte_length: issue.length,
      role: "sealed_validation_issue",
      visible_to_selector: true,
    });
    const tree = execFileSync("git", ["rev-parse", `${task.parent_commit}^{tree}`], {
      cwd: repoRoot,
      encoding: "utf8",
    }).trim();
    const treeBytes = Buffer.from(tree, "utf8");
    entries.push({
      path: `git-tree://${task.parent_commit}`,
      sha256: sha256(treeBytes),
      byte_length: treeBytes.length,
      role: "snapshot_tree",
      visible_to_selector: true,
    });
  }
  const oraclePath = path.join(privateRoot, "validation-localization-oracle.json");
  const oracleBytes = readRegular(oraclePath);
  entries.push({
    path: "private://validation-localization-oracle.json",
    sha256: sha256(oracleBytes),
    byte_length: oracleBytes.length,
    role: "quality_only_oracle",
    visible_to_selector: false,
  });
  return entries.sort((a, b) => Buffer.from(a.path).compare(Buffer.from(b.path)));
};

const validateObserverReceipt = ({
  receipt,
  candidate,
  repoRoot,
  publicRoot,
  privateRoot,
  validationSpecs,
}) => {
  exactKeys(receipt, [
    "schema_version",
    "freeze_id",
    "observer_id",
    "observer_policy_sha256",
    "candidate_sha256",
    "closed_input_inventory",
    "closed_input_inventory_sha256",
    "run_observations",
  ], "OBSERVER_RECEIPT_SCHEMA");
  const observerPolicyBytes = readRegular(path.join(publicRoot, "quality-observer-contract.json"));
  if (
    receipt.schema_version !== "p2-repository-context-observer-receipt/v1" ||
    receipt.freeze_id !== candidate.freeze_id ||
    receipt.observer_id !== "P2CTX-QUALITY-OWNED-PROCESS-BOUNDARY-V1" ||
    receipt.observer_policy_sha256 !== sha256(observerPolicyBytes) ||
    receipt.candidate_sha256 !== sha256(stableJson(candidate))
  ) {
    fail("OBSERVER_RECEIPT_IDENTITY_MISMATCH", "observer receipt identity mismatch");
  }
  const inventory = expectedInventory({ repoRoot, publicRoot, privateRoot, validationSpecs });
  if (
    stableJson(receipt.closed_input_inventory) !== stableJson(inventory) ||
    receipt.closed_input_inventory_sha256 !== sha256(stableJson(inventory))
  ) {
    fail("OBSERVER_INPUT_INVENTORY_MISMATCH", "observer closed input inventory mismatch");
  }
  if (receipt.closed_input_inventory.some((entry) => entry.role === "quality_only_oracle" && entry.visible_to_selector)) {
    fail("VALIDATION_CONTAMINATION_DETECTED", "validation oracle was visible to selector");
  }

  const allRuns = [...candidate.baseline_runs, ...candidate.target_runs, ...candidate.replay_runs];
  if (!Array.isArray(receipt.run_observations) || receipt.run_observations.length !== allRuns.length) {
    fail("OBSERVER_RUN_SET_MISMATCH", "observer run set mismatch");
  }
  const observationMap = new Map(receipt.run_observations.map((item) => [item.run_id, item]));
  if (observationMap.size !== receipt.run_observations.length) fail("OBSERVER_RUN_SET_MISMATCH", "duplicate observer run");
  for (const run of allRuns) {
    const observation = observationMap.get(run.run_id);
    if (!observation) fail("OBSERVER_RUN_SET_MISMATCH", `missing observation ${run.run_id}`);
    exactKeys(observation, [
      "run_id",
      "task_id",
      "snapshot_commit",
      "result_projection_sha256",
      "cold_index_ms",
      "query_ms",
      "end_to_end_ms",
      "selected_bytes",
      "opened_input_inventory_sha256",
      "validation_oracle_opened_by_selector",
      "accepted_change_content_opened",
      "diff_or_history_commands",
      "network_connect_attempts",
      "provider_requests",
      "secret_read_attempts",
      "remote_writes",
      "production_effects",
      "public_effects",
    ], "OBSERVER_RECEIPT_SCHEMA");
    const visibleInputs = inventory.filter(
      (entry) =>
        entry.visible_to_selector &&
        (
          entry.role === "public_contract" ||
          entry.path === `sealed://${run.task_id}/issue` ||
          entry.path === `git-tree://${run.snapshot_commit}`
        ),
    );
    if (
      observation.task_id !== run.task_id ||
      observation.snapshot_commit !== run.snapshot_commit ||
      observation.result_projection_sha256 !== run.stable_projection_sha256 ||
      observation.cold_index_ms !== run.metrics.cold_index_ms ||
      observation.query_ms !== run.metrics.query_ms ||
      observation.end_to_end_ms !== run.metrics.end_to_end_ms ||
      observation.selected_bytes !== run.metrics.selected_bytes ||
      observation.opened_input_inventory_sha256 !== sha256(stableJson(visibleInputs))
    ) {
      fail("OBSERVER_RUN_BINDING_MISMATCH", `observer binding mismatch for ${run.run_id}`);
    }
    if (observation.validation_oracle_opened_by_selector) {
      fail("VALIDATION_CONTAMINATION_DETECTED", `${run.run_id} opened validation gold`);
    }
    if (observation.accepted_change_content_opened || observation.diff_or_history_commands !== 0) {
      fail("HISTORY_CONTAMINATION_DETECTED", `${run.run_id} used accepted change or history`);
    }
    const effects = [
      "network_connect_attempts",
      "provider_requests",
      "secret_read_attempts",
      "remote_writes",
      "production_effects",
      "public_effects",
    ];
    if (effects.some((key) => observation[key] !== 0)) {
      fail("EXTERNAL_EFFECT_DETECTED", `${run.run_id} has an independently observed effect`);
    }
  }
};

const countHits = (runs, oracleMap) =>
  runs.reduce(
    (total, run) =>
      total + run.ranked_items.filter((item) => oracleMap.get(run.task_id).has(item.path)).length,
    0,
  );

export function evaluateCandidate({
  repoRoot,
  publicRoot,
  privateRoot,
  candidate,
  observerReceipt,
}) {
  exactKeys(candidate, [
    "schema_version",
    "freeze_id",
    "configuration_id",
    "baseline_runs",
    "target_runs",
    "replay_runs",
  ]);
  const manifest = readJson(path.join(publicRoot, "manifest.json"));
  const targetConfig = readJson(path.join(publicRoot, "target-config.json"));
  const validationSpecs = readJson(path.join(privateRoot, "validation-task-specs.json"));
  const oracle = readJson(path.join(privateRoot, "validation-localization-oracle.json"));
  const frozenBaseline = readJson(path.join(privateRoot, "simple-lexical-baseline-result.json"));
  if (
    candidate.schema_version !== "p2-repository-context-candidate-result/v2" ||
    candidate.freeze_id !== manifest.freeze_id ||
    candidate.configuration_id !== targetConfig.configuration_id
  ) {
    fail("IDENTITY_MISMATCH", "candidate is not bound to the frozen evaluation");
  }

  const taskMap = new Map(validationSpecs.tasks.map((task) => [task.task_id, task]));
  const oracleMap = new Map(oracle.tasks.map((task) => [task.task_id, new Set(task.oracle_paths)]));
  validateRunList({ list: candidate.baseline_runs, taskMap, repoRoot, kind: "baseline" });
  validateRunList({ list: candidate.target_runs, taskMap, repoRoot, kind: "target" });
  validateRunList({ list: candidate.replay_runs, taskMap, repoRoot, kind: "replay" });

  const baselineIdentity = candidate.baseline_runs.map((run) => ({
    task_id: run.task_id,
    ranked_paths: run.ranked_items.map((item) => item.path),
    selected_bytes: run.metrics.selected_bytes,
  }));
  const expectedBaseline = frozenBaseline.validation_results.map((result) => ({
    task_id: result.task_id,
    ranked_paths: result.ranked_paths,
    selected_bytes: result.selected_bytes,
  }));
  if (stableJson(baselineIdentity) !== stableJson(expectedBaseline)) {
    fail("BASELINE_IDENTITY_MISMATCH", "baseline differs from frozen parent-snapshot baseline");
  }

  const replayMap = new Map(candidate.replay_runs.map((run) => [run.task_id, run]));
  for (const target of candidate.target_runs) {
    const replay = replayMap.get(target.task_id);
    if (
      !replay ||
      target.stable_projection_sha256 !== replay.stable_projection_sha256 ||
      stableJson(runProjection(target)) !== stableJson(runProjection(replay))
    ) {
      fail("REPLAY_MISMATCH", `${target.task_id} stable projection changed on replay`);
    }
  }

  validateObserverReceipt({
    receipt: observerReceipt,
    candidate,
    repoRoot,
    publicRoot,
    privateRoot,
    validationSpecs,
  });

  const baselineByTask = new Map(candidate.baseline_runs.map((run) => [run.task_id, run]));
  for (const run of candidate.target_runs) {
    if (run.metrics.selected_bytes > baselineByTask.get(run.task_id).metrics.selected_bytes * 1.5) {
      fail("SELECTED_BYTES_GUARDRAIL_EXCEEDED", `${run.task_id} selected-byte guardrail failed`);
    }
  }
  if (
    percentile95(candidate.target_runs.map((run) => run.metrics.query_ms)) >
    percentile95(candidate.baseline_runs.map((run) => run.metrics.query_ms)) * 2
  ) {
    fail("QUERY_LATENCY_GUARDRAIL_EXCEEDED", "target query-only p95 exceeded two times the same-index baseline");
  }

  const baselineHits = countHits(candidate.baseline_runs, oracleMap);
  const targetHits = countHits(candidate.target_runs, oracleMap);
  if (baselineHits !== manifest.baseline_hits) {
    fail("BASELINE_SCORE_MISMATCH", "privately recomputed baseline score mismatch");
  }
  if (targetHits < manifest.target_minimum_hits) {
    fail("TARGET_RECALL_NON_PASS", "target did not reach sealed threshold");
  }
  return {
    schema_version: "p2-repository-context-evaluation/v2",
    status: "PASS",
    freeze_id: manifest.freeze_id,
    baseline_hits: baselineHits,
    target_hits: targetHits,
    oracle_count: manifest.oracle_count,
    recall_at_10: targetHits / manifest.oracle_count,
    delta: (targetHits - baselineHits) / manifest.oracle_count,
    identity: "PASS",
    evidence: "PASS",
    replay: "PASS",
    observer_receipt: "PASS",
    validation_contamination: "NONE",
    external_effects: "NONE",
  };
}

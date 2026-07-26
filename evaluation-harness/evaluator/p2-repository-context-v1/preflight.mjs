#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import {
  EvaluationError,
  evaluateCandidate,
  sha256,
  stableJson,
} from "./evaluator.mjs";

const args = Object.fromEntries(
  process.argv.slice(2).reduce((pairs, item, index, all) => {
    if (item.startsWith("--") && all[index + 1] && !all[index + 1].startsWith("--")) {
      pairs.push([item.slice(2), all[index + 1]]);
    }
    return pairs;
  }, []),
);
const repoRoot = path.resolve(args["repo-root"] ?? process.cwd());
const publicRoot = path.resolve(
  args["public-root"] ??
    path.join(repoRoot, "evaluation-harness/datasets/p2-repository-context-v1/public"),
);
const privateRoot = path.resolve(args["private-root"] ?? "");
const die = (reasonCode, message) => {
  process.stderr.write(`${JSON.stringify({ status: "NON_PASS", reason_code: reasonCode, message })}\n`);
  process.exit(1);
};
if (!args["private-root"]) die("PRIVATE_ROOT_REQUIRED", "--private-root is required");
if (
  privateRoot === publicRoot ||
  privateRoot.startsWith(`${publicRoot}${path.sep}`) ||
  publicRoot.startsWith(`${privateRoot}${path.sep}`)
) {
  die("ROOT_SEPARATION_NON_PASS", "public and private roots must be physically separate");
}

const readRegular = (file) => {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) die("INPUT_TYPE_NON_PASS", `${file} is not regular`);
  return fs.readFileSync(file);
};
const json = (file) => JSON.parse(readRegular(file).toString("utf8"));
const digest = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const git = (...gitArgs) =>
  execFileSync("git", gitArgs, { cwd: repoRoot, encoding: "utf8" }).trim();

const publicManifest = json(path.join(publicRoot, "manifest.json"));
for (const [name, identity] of Object.entries(publicManifest.private_bindings)) {
  const bytes = readRegular(path.join(privateRoot, name));
  if (bytes.length !== identity.byte_length || digest(bytes) !== identity.sha256) {
    die("PRIVATE_BINDING_MISMATCH", `${name} does not match public binding`);
  }
}
for (const [name, identity] of Object.entries(publicManifest.contract_bindings ?? {})) {
  const bytes = readRegular(path.join(publicRoot, name));
  if (bytes.length !== identity.byte_length || digest(bytes) !== identity.sha256) {
    die("PUBLIC_CONTRACT_BINDING_MISMATCH", `${name} does not match public manifest`);
  }
}

const taskManifest = json(path.join(privateRoot, "task-manifest.json"));
const development = json(path.join(privateRoot, "development-task-specs.json"));
const validation = json(path.join(privateRoot, "validation-task-specs.json"));
const sourceManifest = json(path.join(privateRoot, "source-blob-manifest.json"));
if (
  taskManifest.freeze_id !== publicManifest.freeze_id ||
  taskManifest.task_count !== 4 ||
  development.tasks.length !== 2 ||
  validation.tasks.length !== 2
) {
  die("FREEZE_IDENTITY_MISMATCH", "task closure identity mismatch");
}
for (const task of [...development.tasks, ...validation.tasks]) {
  if (
    git("rev-parse", `${task.accepted_commit}^{tree}`) !== task.accepted_tree ||
    git("rev-parse", `${task.parent_commit}^{tree}`) !== task.parent_tree
  ) {
    die("HISTORY_IDENTITY_MISMATCH", `commit/tree mismatch for ${task.task_id}`);
  }
  try {
    execFileSync("git", ["merge-base", "--is-ancestor", task.accepted_commit, "HEAD"], {
      cwd: repoRoot,
      stdio: "ignore",
    });
  } catch {
    die("HISTORY_NOT_CANONICAL", `${task.accepted_commit} is not canonical history`);
  }
}
for (const entry of sourceManifest.entries) {
  const object = `${entry.parent_commit}:${entry.path}`;
  const bytes = execFileSync("git", ["show", object], { cwd: repoRoot });
  if (
    git("cat-file", "-t", object) !== "blob" ||
    git("rev-parse", object) !== entry.git_blob_sha1 ||
    bytes.length !== entry.byte_length ||
    digest(bytes) !== entry.sha256
  ) {
    die("SOURCE_BLOB_IDENTITY_MISMATCH", `${entry.task_id}:${entry.path}`);
  }
}

const baseline = json(path.join(privateRoot, "simple-lexical-baseline-result.json"));
const oracle = json(path.join(privateRoot, "validation-localization-oracle.json"));
const validationMap = new Map(validation.tasks.map((task) => [task.task_id, task]));
const source = (snapshot, relativePath) => {
  const object = `${snapshot}:${relativePath}`;
  return {
    bytes: execFileSync("git", ["show", object], { cwd: repoRoot }),
    blob: git("rev-parse", object),
  };
};
const rankedItem = (snapshot, relativePath, rank) => {
  const found = source(snapshot, relativePath);
  const text = found.bytes.toString("utf8");
  const symbol = text.match(/[A-Za-z_][A-Za-z0-9_-]{1,}/)?.[0];
  if (!symbol) die("PREFLIGHT_SYMBOL_FIXTURE_UNAVAILABLE", relativePath);
  const symbolBytes = Buffer.from(symbol, "utf8");
  const start = found.bytes.indexOf(symbolBytes);
  const span = found.bytes.subarray(start, start + symbolBytes.length);
  return {
    rank,
    path: relativePath,
    identity: {
      git_blob_sha1: found.blob,
      sha256: digest(found.bytes),
      byte_length: found.bytes.length,
    },
    symbols: [{ name: symbol, evidence_span_index: 0 }],
    evidence_spans: [{
      start_byte: start,
      end_byte: start + symbolBytes.length,
      sha256: digest(span),
    }],
    stable_rationale: [{
      kind: "lexical",
      anchor: symbol,
      evidence_span_index: 0,
    }],
  };
};
const run = (kind, taskId, rankedPaths, timings) => {
  const snapshot = validationMap.get(taskId).parent_commit;
  const rankedItems = rankedPaths.map((relativePath, index) =>
    rankedItem(snapshot, relativePath, index + 1),
  );
  const result = {
    run_id: `${kind}-${taskId}`,
    task_id: taskId,
    snapshot_commit: snapshot,
    ranked_items: rankedItems,
    metrics: {
      cold_index_ms: timings.cold,
      query_ms: timings.query,
      end_to_end_ms: timings.end,
      selected_bytes: rankedItems.reduce((total, item) => total + item.identity.byte_length, 0),
    },
    stable_projection_sha256: "",
  };
  result.stable_projection_sha256 = sha256(stableJson({
    task_id: result.task_id,
    snapshot_commit: result.snapshot_commit,
    ranked_items: result.ranked_items,
  }));
  return result;
};
const baselineRuns = baseline.validation_results.map((result) =>
  run("baseline", result.task_id, result.ranked_paths, { cold: 10, query: 5, end: 16 }),
);
const targetRuns = oracle.tasks.map((task, index) => {
  const frozen = baseline.validation_results.find((item) => item.task_id === task.task_id);
  const paths =
    index === 0
      ? [
        ...task.oracle_paths.slice(0, 8),
        ...frozen.ranked_paths.filter((item) => !task.oracle_paths.includes(item)).slice(0, 2),
      ]
      : task.oracle_paths.slice(0, 10);
  return run("target", task.task_id, paths, { cold: 12, query: 7, end: 20 });
});
const replayRuns = targetRuns.map((target) => ({
  ...structuredClone(target),
  run_id: `replay-${target.task_id}`,
  metrics: { ...target.metrics, cold_index_ms: 11, query_ms: 6, end_to_end_ms: 18 },
}));
const candidate = {
  schema_version: "p2-repository-context-candidate-result/v2",
  freeze_id: publicManifest.freeze_id,
  configuration_id: "LEXICAL_CAMEL_SYMBOL_RELATION_ROLE_DIVERSITY_V1",
  baseline_runs: baselineRuns,
  target_runs: targetRuns,
  replay_runs: replayRuns,
};

const inventory = [];
for (const name of [
  "manifest.json",
  "simple-lexical-baseline-spec.json",
  "target-config.json",
  "candidate-result-contract.json",
  "quality-observer-contract.json",
]) {
  const bytes = readRegular(path.join(publicRoot, name));
  inventory.push({
    path: `public://${name}`,
    sha256: digest(bytes),
    byte_length: bytes.length,
    role: "public_contract",
    visible_to_selector: true,
  });
}
for (const task of validation.tasks) {
  const issue = Buffer.from(task.issue, "utf8");
  inventory.push({
    path: `sealed://${task.task_id}/issue`,
    sha256: digest(issue),
    byte_length: issue.length,
    role: "sealed_validation_issue",
    visible_to_selector: true,
  });
  const tree = git("rev-parse", `${task.parent_commit}^{tree}`);
  const bytes = Buffer.from(tree, "utf8");
  inventory.push({
    path: `git-tree://${task.parent_commit}`,
    sha256: digest(bytes),
    byte_length: bytes.length,
    role: "snapshot_tree",
    visible_to_selector: true,
  });
}
const oracleBytes = readRegular(path.join(privateRoot, "validation-localization-oracle.json"));
inventory.push({
  path: "private://validation-localization-oracle.json",
  sha256: digest(oracleBytes),
  byte_length: oracleBytes.length,
  role: "quality_only_oracle",
  visible_to_selector: false,
});
inventory.sort((a, b) => Buffer.from(a.path).compare(Buffer.from(b.path)));

const makeObserverReceipt = (value) => ({
  schema_version: "p2-repository-context-observer-receipt/v1",
  freeze_id: value.freeze_id,
  observer_id: "P2CTX-QUALITY-OWNED-PROCESS-BOUNDARY-V1",
  observer_policy_sha256: digest(readRegular(path.join(publicRoot, "quality-observer-contract.json"))),
  candidate_sha256: sha256(stableJson(value)),
  closed_input_inventory: structuredClone(inventory),
  closed_input_inventory_sha256: sha256(stableJson(inventory)),
  run_observations: [
    ...value.baseline_runs,
    ...value.target_runs,
    ...value.replay_runs,
  ].map((item) => {
    const visible = inventory.filter(
      (entry) =>
        entry.visible_to_selector &&
        (
          entry.role === "public_contract" ||
          entry.path === `sealed://${item.task_id}/issue` ||
          entry.path === `git-tree://${item.snapshot_commit}`
        ),
    );
    return {
      run_id: item.run_id,
      task_id: item.task_id,
      snapshot_commit: item.snapshot_commit,
      result_projection_sha256: item.stable_projection_sha256,
      cold_index_ms: item.metrics.cold_index_ms,
      query_ms: item.metrics.query_ms,
      end_to_end_ms: item.metrics.end_to_end_ms,
      selected_bytes: item.metrics.selected_bytes,
      opened_input_inventory_sha256: sha256(stableJson(visible)),
      validation_oracle_opened_by_selector: false,
      accepted_change_content_opened: false,
      diff_or_history_commands: 0,
      network_connect_attempts: 0,
      provider_requests: 0,
      secret_read_attempts: 0,
      remote_writes: 0,
      production_effects: 0,
      public_effects: 0,
    };
  }),
});

const expectFailure = (name, reasonCode, mutate) => {
  const value = structuredClone(candidate);
  let receipt = makeObserverReceipt(value);
  mutate(value, receipt);
  try {
    evaluateCandidate({ repoRoot, publicRoot, privateRoot, candidate: value, observerReceipt: receipt });
    die("NEGATIVE_FALSE_ACCEPT", `${name} was accepted`);
  } catch (error) {
    if (!(error instanceof EvaluationError) || error.reasonCode !== reasonCode) {
      die("NEGATIVE_REASON_MISMATCH", `${name}: expected ${reasonCode}, received ${error.reasonCode ?? error.message}`);
    }
  }
};

let evaluation;
try {
  evaluation = evaluateCandidate({
    repoRoot,
    publicRoot,
    privateRoot,
    candidate,
    observerReceipt: makeObserverReceipt(candidate),
  });
  expectFailure("identity", "IDENTITY_MISMATCH", (value) => { value.freeze_id = "MUTATED"; });
  expectFailure("symbol", "SYMBOL_EVIDENCE_MISMATCH", (value) => { value.target_runs[0].ranked_items[0].symbols[0].name = "absent_symbol"; });
  expectFailure("evidence-span", "EVIDENCE_SPAN_HASH_MISMATCH", (value) => { value.target_runs[0].ranked_items[0].evidence_spans[0].sha256 = "0".repeat(64); });
  expectFailure("rationale", "STABLE_RATIONALE_MISMATCH", (value) => { value.target_runs[0].ranked_items[0].stable_rationale[0].anchor = "absent_anchor"; });
  expectFailure("selected-bytes", "SELECTED_BYTES_MISMATCH", (value) => { value.target_runs[0].metrics.selected_bytes += 1; });
  expectFailure("replay", "REPLAY_MISMATCH", (value) => {
    [value.replay_runs[0].ranked_items[0], value.replay_runs[0].ranked_items[1]] =
      [value.replay_runs[0].ranked_items[1], value.replay_runs[0].ranked_items[0]];
    value.replay_runs[0].ranked_items.forEach((item, index) => { item.rank = index + 1; });
    value.replay_runs[0].stable_projection_sha256 = sha256(stableJson({
      task_id: value.replay_runs[0].task_id,
      snapshot_commit: value.replay_runs[0].snapshot_commit,
      ranked_items: value.replay_runs[0].ranked_items,
    }));
  });
  expectFailure("observer-candidate-binding", "OBSERVER_RECEIPT_IDENTITY_MISMATCH", (_value, receipt) => { receipt.candidate_sha256 = "0".repeat(64); });
  expectFailure("observer-input-inventory", "OBSERVER_INPUT_INVENTORY_MISMATCH", (_value, receipt) => { receipt.closed_input_inventory.pop(); receipt.closed_input_inventory_sha256 = sha256(stableJson(receipt.closed_input_inventory)); });
  expectFailure("latency-observer-binding", "OBSERVER_RUN_BINDING_MISMATCH", (value, receipt) => {
    value.target_runs[0].metrics.end_to_end_ms += 1;
    receipt.candidate_sha256 = sha256(stableJson(value));
  });
  expectFailure("query-only-p95", "QUERY_LATENCY_GUARDRAIL_EXCEEDED", (value, receipt) => {
    value.target_runs[0].metrics.cold_index_ms = 8;
    value.target_runs[0].metrics.query_ms = 11;
    value.target_runs[0].metrics.end_to_end_ms = 24;
    receipt.candidate_sha256 = sha256(stableJson(value));
    const observation = receipt.run_observations.find(
      (item) => item.run_id === value.target_runs[0].run_id,
    );
    observation.cold_index_ms = 8;
    observation.query_ms = 11;
    observation.end_to_end_ms = 24;
  });
  expectFailure("validation-contamination", "VALIDATION_CONTAMINATION_DETECTED", (_value, receipt) => { receipt.run_observations[0].validation_oracle_opened_by_selector = true; });
  expectFailure("history-contamination", "HISTORY_CONTAMINATION_DETECTED", (_value, receipt) => { receipt.run_observations[0].diff_or_history_commands = 1; });
  expectFailure("external-effect", "EXTERNAL_EFFECT_DETECTED", (_value, receipt) => { receipt.run_observations[0].network_connect_attempts = 1; });
  expectFailure("duplicate-path", "RESULT_PATH_DUPLICATE", (value) => { value.target_runs[0].ranked_items[1] = structuredClone(value.target_runs[0].ranked_items[0]); value.target_runs[0].ranked_items[1].rank = 2; });
} catch (error) {
  die(error.reasonCode ?? "PREFLIGHT_EXCEPTION", error.message);
}

process.stdout.write(`${JSON.stringify({
  status: "PASS",
  freeze_id: publicManifest.freeze_id,
  source_blob_count: sourceManifest.entries.length,
  positive_evaluation: evaluation,
  negative_tests: 14,
  independently_observed_boundary: true,
})}\n`);

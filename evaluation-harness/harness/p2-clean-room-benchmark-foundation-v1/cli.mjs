#!/usr/bin/env node
import { mkdir } from "node:fs/promises";
import path from "node:path";
import {
  BENCHMARK_SPEC,
  SOURCE_PACK_IDENTITY,
  compactRanked,
  createOnceFile,
  groundTruthFromFiles,
  heldNonOverlapProof,
  loadCorpus,
  macroMetrics,
  maintenanceQuery,
  rankDocuments,
  readBoundLeaf,
  resolveEvidenceBoundRun,
  selectDevTasks,
  selectWithinBudget,
  sha256,
  stableJson,
  taskMetrics,
  validateSourcePack,
} from "./core.mjs";

function parseArgs(argv) {
  const result = Object.create(null);
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error(`invalid argument ${key ?? ""}`);
    result[key.slice(2)] = value;
  }
  for (const required of [
    "manifest", "source-root", "output-root", "evidence-root", "run-id",
    "candidate-commit", "candidate-tree", "execution-context", "execution-context-byte-length",
    "execution-context-sha256",
  ]) {
    if (!result[required]) throw new Error(`missing --${required}`);
  }
  return result;
}

async function createCandidateRoot(outputRoot) {
  await mkdir(outputRoot, { recursive: false, mode: 0o700 });
  const candidate = path.join(outputRoot, "candidate");
  await mkdir(candidate, { recursive: false, mode: 0o700 });
  return candidate;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (process.env.P2_TASK_EVIDENCE_ROOT !== args["evidence-root"] ||
      process.env.SOURCELENS_P2_BENCHMARK_SOURCE_ROOT !== args["source-root"]) {
    throw new Error("closed environment root binding mismatch");
  }
  const { evidenceRoot, outputRoot } = await resolveEvidenceBoundRun(
    args["evidence-root"], args["run-id"], args["output-root"],
  );
  const manifestRelative = "accepted-source-pack-v1/SOURCE_PACK.json";
  if (path.resolve(args.manifest) !== path.join(evidenceRoot, manifestRelative)) {
    throw new Error("manifest is not the exact Task Evidence source-pack leaf");
  }
  const bootstrapReadSet = new Map();
  const manifestBytes = await readBoundLeaf(
    evidenceRoot,
    manifestRelative,
    { byte_length: SOURCE_PACK_IDENTITY.byteLength, sha256: SOURCE_PACK_IDENTITY.sha256 },
    bootstrapReadSet,
    "ACCEPTED_SOURCE_PACK_MANIFEST",
  );
  const manifest = JSON.parse(manifestBytes.toString("utf8"));
  const validated = validateSourcePack(manifest);
  const tasks = selectDevTasks(manifest);
  const executionContextRelative = path.relative(evidenceRoot, path.resolve(args["execution-context"])).replaceAll("\\", "/");
  const executionContextBytes = await readBoundLeaf(
    evidenceRoot,
    executionContextRelative,
    { byte_length: Number(args["execution-context-byte-length"]), sha256: args["execution-context-sha256"] },
    bootstrapReadSet,
    "EXECUTION_CONTEXT",
  );
  const executionContext = JSON.parse(executionContextBytes.toString("utf8"));
  if (executionContext.candidate?.commit !== args["candidate-commit"] ||
      executionContext.candidate?.tree !== args["candidate-tree"] ||
      executionContext.runtime?.node_path !== process.execPath ||
      executionContext.runtime?.node_version !== process.version) {
    throw new Error("execution context does not bind the active candidate/runtime");
  }
  const readSet = new Map(bootstrapReadSet);
  const taskCards = [];
  const algorithmResults = { B0: [], B1: [] };

  for (const task of tasks) {
    const listIdentity = task.provenance.pull_request_list_response;
    const filesIdentity = task.provenance.pull_request_files_response;
    const baseCommitIdentity = task.provenance.base_commit_api.body;
    const fixCommitIdentity = task.provenance.fix_commit_api.body;
    const listBytes = await readBoundLeaf(
      args["source-root"], listIdentity.relative_path, listIdentity, readSet, `DEV_PR_LIST_${task.task_id}`,
    );
    const filesBytes = await readBoundLeaf(
      args["source-root"], filesIdentity.relative_path, filesIdentity, readSet, `DEV_PR_FILES_${task.task_id}`,
    );
    const baseCommitBytes = await readBoundLeaf(
      args["source-root"], baseCommitIdentity.relative_path, baseCommitIdentity, readSet, `DEV_BASE_COMMIT_${task.task_id}`,
    );
    const fixCommitBytes = await readBoundLeaf(
      args["source-root"], fixCommitIdentity.relative_path, fixCommitIdentity, readSet, `DEV_FIX_COMMIT_${task.task_id}`,
    );
    const baseCommit = JSON.parse(baseCommitBytes.toString("utf8"));
    const fixCommit = JSON.parse(fixCommitBytes.toString("utf8"));
    if (baseCommit.sha !== task.base.commit || baseCommit.commit?.tree?.sha !== task.base.tree ||
        fixCommit.sha !== task.fix.commit || fixCommit.commit?.tree?.sha !== task.fix.tree) {
      throw new Error(`${task.task_id} base/fix commit API identity drift`);
    }
    const prMatches = JSON.parse(listBytes.toString("utf8")).filter((item) => item.number === task.pull_request);
    if (prMatches.length !== 1) throw new Error(`${task.task_id} PR provenance is not unique`);
    const pr = prMatches[0];
    if (pr.base?.sha !== task.base.commit) throw new Error(`${task.task_id} base commit drift`);
    const query = maintenanceQuery(pr);
    const groundTruth = groundTruthFromFiles(JSON.parse(filesBytes.toString("utf8")));
    const corpus = await loadCorpus(args["source-root"], task, readSet);
    const corpusPaths = new Set(corpus.map((item) => item.path));
    if (groundTruth.some((file) => !corpusPaths.has(file))) {
      throw new Error(`${task.task_id} ground truth is absent from its base production-Java corpus`);
    }
    taskCards.push({
      schema_version: "p2-clean-room-dev-task-card/v1",
      task_id: task.task_id,
      repository: task.repository,
      split: "DEV",
      pull_request: task.pull_request,
      base: { commit: task.base.commit, tree: task.base.tree, archive: task.base.archive },
      fix: { commit: task.fix.commit, tree: task.fix.tree },
      query,
      query_sha256: sha256(Buffer.from(query, "utf8")),
      ground_truth: groundTruth,
      corpus: corpus.map((item) => ({ path: item.path, byte_length: item.byteLength, sha256: item.sha256 })),
    });
    for (const algorithm of ["B0", "B1"]) {
      const ranked = rankDocuments(algorithm, query, corpus);
      const { selected, selectedBytes } = selectWithinBudget(ranked);
      algorithmResults[algorithm].push({
        task_id: task.task_id,
        repository: task.repository,
        algorithm,
        query_sha256: sha256(Buffer.from(query, "utf8")),
        top_k: BENCHMARK_SPEC.topK,
        byte_budget: BENCHMARK_SPEC.byteBudget,
        selected_bytes: selectedBytes,
        selected_paths: selected.map((item) => item.path),
        metrics: taskMetrics(selected, groundTruth),
        raw_ranking: compactRanked(ranked),
      });
    }
  }

  const splitProof = heldNonOverlapProof(manifest, readSet);
  const candidateRoot = await createCandidateRoot(outputRoot);
  const benchmarkManifest = {
    schema_version: BENCHMARK_SPEC.schemaVersion,
    source_pack: SOURCE_PACK_IDENTITY,
    counts: {
      repositories: validated.repositories.size,
      tasks: manifest.tasks.length,
      dev_tasks: validated.devIds.length,
      held_tasks: validated.heldIds.length,
    },
    split: { DEV: validated.devIds, HELD: validated.heldIds },
    held_custody: {
      status: "SEALED_MANIFEST_FIELDS_ONLY_NOT_OPENED_NOT_SCORED",
      task_ids: validated.heldIds,
      source_trees_opened: 0,
      pull_request_file_payloads_opened: 0,
      build_results_opened: 0,
    },
    candidate: { commit: args["candidate-commit"], tree: args["candidate-tree"] },
    execution_context: {
      relative_path: executionContextRelative,
      byte_length: executionContextBytes.length,
      sha256: sha256(executionContextBytes),
    },
    spec: BENCHMARK_SPEC,
  };
  const outputs = {
    "BENCHMARK_MANIFEST.json": benchmarkManifest,
    "DEV_TASK_CARDS.json": { schema_version: "p2-clean-room-dev-task-cards/v1", tasks: taskCards },
    "READ_SET_INVENTORY.json": {
      schema_version: "p2-clean-room-read-set-inventory/v1",
      entries: [...readSet.values()].sort((a, b) => Buffer.compare(Buffer.from(a.relative_path), Buffer.from(b.relative_path))),
    },
    "DEV_HELD_NON_OVERLAP_PROOF.json": splitProof,
    "B0_RESULTS.json": {
      schema_version: "p2-clean-room-baseline-results/v1",
      algorithm: "B0",
      spec: BENCHMARK_SPEC,
      tasks: algorithmResults.B0,
      aggregate: macroMetrics(algorithmResults.B0),
    },
    "B1_RESULTS.json": {
      schema_version: "p2-clean-room-baseline-results/v1",
      algorithm: "B1",
      spec: BENCHMARK_SPEC,
      tasks: algorithmResults.B1,
      aggregate: macroMetrics(algorithmResults.B1),
    },
  };
  const inventory = [];
  for (const [name, value] of Object.entries(outputs).sort(([left], [right]) => left.localeCompare(right))) {
    const content = stableJson(value);
    await createOnceFile(path.join(candidateRoot, name), content);
    inventory.push({ relative_path: name, byte_length: Buffer.byteLength(content), sha256: sha256(Buffer.from(content)) });
  }
  const inventoryContent = stableJson({
    schema_version: "p2-clean-room-candidate-inventory/v1",
    files: inventory,
  });
  await createOnceFile(path.join(candidateRoot, "CANDIDATE_INVENTORY.json"), inventoryContent);
  const receipt = stableJson({
    schema_version: "p2-clean-room-replay-transaction/v1",
    status: "COMPLETE",
    run_id: args["run-id"],
    candidate: { commit: args["candidate-commit"], tree: args["candidate-tree"] },
    cwd: process.cwd(),
    argv: process.argv,
    environment: {
      PATH: process.env.PATH,
      LC_ALL: process.env.LC_ALL,
      NODE_DISABLE_COMPILE_CACHE: process.env.NODE_DISABLE_COMPILE_CACHE,
      P2_TASK_EVIDENCE_ROOT: process.env.P2_TASK_EVIDENCE_ROOT,
      SOURCELENS_P2_BENCHMARK_SOURCE_ROOT: process.env.SOURCELENS_P2_BENCHMARK_SOURCE_ROOT,
    },
    runtime: { node_path: process.execPath, node_version: process.version },
    source_pack: SOURCE_PACK_IDENTITY,
    source_root: args["source-root"],
    output_root: outputRoot,
    execution_context: {
      path: path.resolve(args["execution-context"]),
      byte_length: executionContextBytes.length,
      sha256: sha256(executionContextBytes),
    },
    candidate_inventory_sha256: sha256(Buffer.from(inventoryContent)),
    held_non_overlap_proof_sha256: sha256(Buffer.from(stableJson(splitProof))),
    held_open_count: splitProof.intersection_count,
    external_effects: {
      network: "ENFORCED_DENY_BY_BOUND_MACOS_SANDBOX_EXEC_PROFILE",
      provider: "NO_PROVIDER_API_IN_CANDIDATE_AND_NO_CREDENTIAL_ENV",
      secret: "CLOSED_ENV_NO_SECRET_OR_CREDENTIAL_INPUT",
      remote: "NO_REMOTE_WRITE_API_IN_CANDIDATE",
      production: "NO_PRODUCT_OR_PRODUCTION_PATH_IN_WRITE_SCOPE",
      public: "NO_PUBLICATION_API_IN_CANDIDATE",
    },
  });
  await createOnceFile(path.join(outputRoot, "TRANSACTION.json"), receipt);
}

main().catch((error) => {
  process.stderr.write(`${error.name}: ${error.message}\n`);
  process.exitCode = 1;
});

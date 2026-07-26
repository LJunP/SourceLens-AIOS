#!/usr/bin/env node

import {
  chmodSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
} from "node:fs";
import { join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  assertContained,
  assertExistingPathWithoutSymlink,
  assertFalseEffects,
  canonicalJson,
  exactKeys,
  executeBoundedCommand,
  sha256,
} from "../../harness/p1-125-six-task-parameterized/core.mjs";
import {
  ADAPTER_VERSION,
  commonResultBase,
  createContainedDirectory,
  emit,
  loadExecutionRequest,
  markTargetStarted,
  parseEntryArguments,
  readBoundJson,
  validateEntryPaths,
  writeContainedFileCreateOnce,
} from "./common.mjs";
import { validateTaskProgram } from "./dataset-bindings.mjs";

export const ADAPTER_ID = "B2";

export const ACCEPTED_P0_BINDING = Object.freeze({
  frozen_base_commit: "09cf8dd6a1bcee138b949d117804d652000eb7cc",
  frozen_base_tree: "daa58725d293b954887dbe5b17aab5219b618658",
  checkpoint_commit: "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10",
  checkpoint_tree: "2c0956ae8598547466f691ead21532a026006bf9",
  analyzer_subtree: "408d57e9b4926f95ad059ab2675ee88dfc533096",
  operation_id: "repository_analysis.scan",
});

function trimSingleLine(bytes, label) {
  const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes).trim();
  assert(!text.includes("\n") && text.length > 0, "B2_BINDING_REJECTED", `${label} is not one line`);
  return text;
}

async function runExact({ argv, cwd, timeoutSeconds = 30, expectedExitCodes = [0], environment = {} }) {
  const result = await executeBoundedCommand({
    argv,
    cwd,
    timeoutSeconds,
    expectedExitCodes,
    environment,
  });
  assert(result.ledger.expected_exit_matched, "B2_COMMAND_FAILED", `B2 command failed: ${argv.join(" ")}`, result.ledger);
  return result;
}

function validateConfiguration(configuration, request) {
  assert(
    configuration.adapter_id === ADAPTER_ID
      && configuration.adapter_version === ADAPTER_VERSION
      && configuration.loop_limit === 1
      && canonicalJson(configuration.enabled_tools) === canonicalJson(["repository_analysis.scan"])
      && configuration.feature_flags.exact_accepted_p0_snapshot === true
      && configuration.feature_flags.repository_analysis_scan === true
      && configuration.feature_flags.canonical_source_mutation === false
      && configuration.feature_flags.network === false,
    "B2_CONFIGURATION_REJECTED",
    "B2 configuration must expose only exact accepted P0 repository_analysis.scan",
  );
  assert(
    request.limits.max_tool_calls >= 1
      && request.limits.max_model_tokens === 0
      && request.limits.max_cost_usd === 0,
    "B2_BUDGET_REJECTED",
    "B2 scan conformance requires one local tool and zero model/cost budgets",
  );
}

function validateBinding(input, task) {
  exactKeys(input, [
    "schema_version",
    "operation",
    "accepted_p0_frozen_base_commit",
    "accepted_p0_frozen_base_tree",
    "accepted_p0_checkpoint_commit",
    "accepted_p0_checkpoint_tree",
    "analyzer_tree_at_frozen_base",
    "analyzer_tree_at_checkpoint",
    "analyzer_tree_at_p1_125_activation",
    "tree_equal_across_authoritative_bindings",
    "source_path",
    "source_manifest",
    "entry_source_path",
    "required_cli_suffix",
    "required_scan_result_schema_version",
    "network_allowed",
    "canonical_source_mutation_allowed",
    "claim_boundary",
  ], "B2 accepted P0 binding");
  assert(
    input.schema_version === "p1-125-b2-accepted-p0-binding/v1"
      && input.operation === ACCEPTED_P0_BINDING.operation_id
      && input.accepted_p0_frozen_base_commit === ACCEPTED_P0_BINDING.frozen_base_commit
      && input.accepted_p0_frozen_base_tree === ACCEPTED_P0_BINDING.frozen_base_tree
      && input.accepted_p0_checkpoint_commit === ACCEPTED_P0_BINDING.checkpoint_commit
      && input.accepted_p0_checkpoint_tree === ACCEPTED_P0_BINDING.checkpoint_tree
      && input.analyzer_tree_at_frozen_base === ACCEPTED_P0_BINDING.analyzer_subtree
      && input.analyzer_tree_at_checkpoint === ACCEPTED_P0_BINDING.analyzer_subtree
      && input.analyzer_tree_at_p1_125_activation === ACCEPTED_P0_BINDING.analyzer_subtree
      && input.tree_equal_across_authoritative_bindings === true
      && input.source_path === "analyzer-rust"
      && input.entry_source_path === "analyzer-rust/src/main.rs"
      && canonicalJson(input.required_cli_suffix) === canonicalJson([
        "scan",
        "--repo-path",
        "ABSOLUTE_DISPOSABLE_SOURCE_ROOT",
      ])
      && input.required_scan_result_schema_version === 2
      && input.network_allowed === false
      && input.canonical_source_mutation_allowed === false
      && input.claim_boundary === "EXACT_ACCEPTED_P0_REPOSITORY_ANALYSIS_SCAN_BINDING_ONLY",
    "B2_BINDING_REJECTED",
    "B2 accepted P0 binding differs from canonical Truth or the Quality freeze",
  );
}

function validateSourceManifest(manifest, binding) {
  exactKeys(manifest, [
    "schema_version",
    "source_root",
    "accepted_p0_frozen_base_commit",
    "accepted_p0_frozen_base_tree",
    "accepted_p0_checkpoint_commit",
    "accepted_p0_checkpoint_tree",
    "analyzer_tree",
    "entries",
    "entry_count",
    "total_byte_length",
    "claim_boundary",
  ], "B2 P0 source manifest");
  assert(
    manifest.schema_version === "p1-125-b2-p0-source-manifest/v1"
      && manifest.source_root === binding.source_path
      && manifest.accepted_p0_frozen_base_commit === ACCEPTED_P0_BINDING.frozen_base_commit
      && manifest.accepted_p0_frozen_base_tree === ACCEPTED_P0_BINDING.frozen_base_tree
      && manifest.accepted_p0_checkpoint_commit === ACCEPTED_P0_BINDING.checkpoint_commit
      && manifest.accepted_p0_checkpoint_tree === ACCEPTED_P0_BINDING.checkpoint_tree
      && manifest.analyzer_tree === ACCEPTED_P0_BINDING.analyzer_subtree
      && Array.isArray(manifest.entries)
      && manifest.entries.length === manifest.entry_count
      && manifest.entry_count === 10
      && manifest.claim_boundary === "EXACT_ACCEPTED_P0_ANALYZER_SOURCE_IDENTITY_ONLY",
    "B2_MANIFEST_REJECTED",
    "B2 source manifest header drifted",
  );
  let total = 0;
  const paths = [];
  for (const entry of manifest.entries) {
    exactKeys(entry, ["path", "git_blob", "sha256", "byte_length"], "B2 P0 manifest entry");
    assert(
      typeof entry.path === "string"
        && entry.path.startsWith("analyzer-rust/")
        && /^[0-9a-f]{40}$/.test(entry.git_blob)
        && /^[0-9a-f]{64}$/.test(entry.sha256)
        && Number.isInteger(entry.byte_length)
        && entry.byte_length >= 0,
      "B2_MANIFEST_REJECTED",
      "B2 P0 manifest entry identity is invalid",
    );
    total += entry.byte_length;
    paths.push(entry.path);
  }
  assert(
    total === manifest.total_byte_length
      && new Set(paths).size === paths.length
      && canonicalJson(paths) === canonicalJson([...paths].sort()),
    "B2_MANIFEST_REJECTED",
    "B2 P0 manifest order, uniqueness or byte total drifted",
  );
}

function validateTaskSourceProgram(program) {
  assert(
    program !== null
      && typeof program === "object"
      && program.schema_version === "p1-125-b1-finite-program/v1"
      && typeof program.task_source === "string"
      && program.task_source.includes("/source-template")
      && !program.task_source.split(/[\\/]/).includes(".."),
    "B2_SCAN_SOURCE_REJECTED",
    "B2 task source program is invalid",
  );
}

function parseLsTree(bytes) {
  const entries = bytes.toString("utf8").split("\0").filter(Boolean).map((record) => {
    const match = /^(100644|100755) blob ([0-9a-f]{40})\t(.+)$/.exec(record);
    assert(match !== null, "B2_GIT_OBJECT_REJECTED", `unsupported analyzer tree entry: ${record}`);
    return {
      mode: match[1] === "100755" ? 0o755 : 0o644,
      git_blob: match[2],
      relative_path: match[3],
      path: `analyzer-rust/${match[3]}`,
    };
  });
  assert(entries.length > 0, "B2_GIT_OBJECT_REJECTED", "accepted analyzer subtree is empty");
  return entries;
}

async function verifyP0Binding({ git, repositoryRoot }) {
  const checks = [];
  const commands = [
    ["frozen_base_tree", [git, "rev-parse", `${ACCEPTED_P0_BINDING.frozen_base_commit}^{tree}`], ACCEPTED_P0_BINDING.frozen_base_tree],
    ["checkpoint_tree", [git, "rev-parse", `${ACCEPTED_P0_BINDING.checkpoint_commit}^{tree}`], ACCEPTED_P0_BINDING.checkpoint_tree],
    ["frozen_analyzer_subtree", [git, "rev-parse", `${ACCEPTED_P0_BINDING.frozen_base_commit}:analyzer-rust`], ACCEPTED_P0_BINDING.analyzer_subtree],
    ["checkpoint_analyzer_subtree", [git, "rev-parse", `${ACCEPTED_P0_BINDING.checkpoint_commit}:analyzer-rust`], ACCEPTED_P0_BINDING.analyzer_subtree],
  ];
  for (const [id, argv, expected] of commands) {
    const result = await runExact({ argv, cwd: repositoryRoot });
    const observed = trimSingleLine(result.stdout, id);
    assert(observed === expected, "B2_BINDING_REJECTED", `${id} mismatch`);
    checks.push({ id, expected, observed, ledger: result.ledger });
  }
  const ancestry = await runExact({
    argv: [
      git,
      "merge-base",
      "--is-ancestor",
      ACCEPTED_P0_BINDING.frozen_base_commit,
      ACCEPTED_P0_BINDING.checkpoint_commit,
    ],
    cwd: repositoryRoot,
  });
  checks.push({ id: "frozen_base_is_checkpoint_ancestor", status: "PASS", ledger: ancestry.ledger });
  return checks;
}

async function materializeAnalyzer({ git, repositoryRoot, analyzerRoot, manifest }) {
  const listing = await runExact({
    argv: [
      git,
      "ls-tree",
      "-rz",
      "--full-tree",
      `${ACCEPTED_P0_BINDING.frozen_base_commit}:analyzer-rust`,
    ],
    cwd: repositoryRoot,
  });
  const gitEntries = parseLsTree(listing.stdout);
  assert(
    canonicalJson(gitEntries.map(({ path, git_blob }) => ({ path, git_blob })))
      === canonicalJson(manifest.entries.map(({ path, git_blob }) => ({ path, git_blob }))),
    "B2_MANIFEST_REJECTED",
    "Git analyzer entry set/order/path/blob differs from the frozen manifest",
  );
  const artifacts = [];
  for (let index = 0; index < gitEntries.length; index += 1) {
    const gitEntry = gitEntries[index];
    const expected = manifest.entries[index];
    const blob = await runExact({
      argv: [git, "cat-file", "blob", gitEntry.git_blob],
      cwd: repositoryRoot,
    });
    assert(
      blob.stdout.length === expected.byte_length
        && sha256(blob.stdout) === expected.sha256,
      "B2_MANIFEST_REJECTED",
      `Git blob bytes differ from manifest: ${expected.path}`,
    );
    const destination = writeContainedFileCreateOnce(
      analyzerRoot,
      gitEntry.relative_path,
      blob.stdout,
      gitEntry.mode,
    );
    chmodSync(destination, gitEntry.mode);
    artifacts.push({
      path: expected.path,
      relative_path: gitEntry.relative_path,
      mode: gitEntry.mode,
      git_blob: gitEntry.git_blob,
      sha256: sha256(blob.stdout),
      byte_length: blob.stdout.length,
      ledger: blob.ledger,
    });
  }
  assert(
    artifacts.length === manifest.entry_count
      && artifacts.reduce((sum, entry) => sum + entry.byte_length, 0) === manifest.total_byte_length,
    "B2_MANIFEST_REJECTED",
    "materialized analyzer population differs from the frozen manifest",
  );
  return { listing_ledger: listing.ledger, artifacts };
}

function walkSource(root) {
  const entries = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      assert(!entry.isSymbolicLink(), "SYMLINK_REJECTED", "B2 scan source contains a symlink");
      if (entry.isDirectory()) visit(path);
      else {
        assert(entry.isFile(), "B2_SCAN_SOURCE_REJECTED", "B2 scan source contains a non-regular entry");
        const bytes = readFileSync(path);
        entries.push({
          absolute_path: path,
          relative_path: relative(root, path).split(sep).join("/"),
          sha256: sha256(bytes),
          byte_length: bytes.length,
        });
      }
    }
  };
  visit(root);
  return entries.sort((left, right) => left.relative_path.localeCompare(right.relative_path));
}

function materializeScanSource(repositoryRoot, taskSource, destinationRoot) {
  const sourceRoot = assertContained(repositoryRoot, resolve(repositoryRoot, taskSource), "B2 scan source");
  assertExistingPathWithoutSymlink(sourceRoot, "B2 scan source");
  const entries = walkSource(sourceRoot);
  assert(entries.length > 0, "B2_SCAN_SOURCE_REJECTED", "B2 scan source is empty");
  for (const entry of entries) {
    writeContainedFileCreateOnce(destinationRoot, entry.relative_path, readFileSync(entry.absolute_path), 0o600);
  }
  return entries.map(({ absolute_path: _absolutePath, ...entry }) => entry);
}

function verifyScanSource(root, inventory) {
  return inventory.every((entry) => {
    const path = join(root, entry.relative_path);
    const bytes = readFileSync(path);
    return bytes.length === entry.byte_length && sha256(bytes) === entry.sha256;
  });
}

function toolchainPaths() {
  const userHome = process.env.HOME;
  assert(typeof userHome === "string" && userHome.startsWith("/"), "B2_TOOLCHAIN_REJECTED", "HOME is unavailable");
  const triple = process.arch === "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin";
  return {
    git: "/usr/bin/git",
    cargo: join(userHome, `.rustup/toolchains/stable-${triple}/bin/cargo`),
    rustc: join(userHome, `.rustup/toolchains/stable-${triple}/bin/rustc`),
    cargoHome: join(userHome, ".cargo"),
    rustupHome: join(userHome, ".rustup"),
  };
}

function executableIdentity(path) {
  const real = assertExistingPathWithoutSymlink(path, path);
  assert(statSync(real).isFile() && !lstatSync(real).isSymbolicLink(), "B2_TOOLCHAIN_REJECTED", "toolchain path is invalid");
  const bytes = readFileSync(real);
  return {
    path: real,
    sha256: sha256(bytes),
    byte_length: bytes.length,
  };
}

export async function executeB2(executionRequestPath) {
  const loaded = loadExecutionRequest(executionRequestPath, ADAPTER_ID);
  const taskRecord = readBoundJson(loaded.request.task_spec, "TaskSpec");
  const task = taskRecord.value;
  const environment = readBoundJson(loaded.request.environment_snapshot, "EnvironmentSnapshot").value;
  const configuration = readBoundJson(loaded.request.system_configuration, "B2 SystemConfiguration").value;
  const binding = readBoundJson(loaded.request.adapter_input, "B2 exact P0 binding").value;
  assert(
    Object.keys(loaded.request.auxiliary_inputs).sort().join(",")
      === "b2_source_manifest,task_source_program",
    "B2_INPUT_REJECTED",
    "B2 auxiliary input set is not closed",
  );
  const manifest = readBoundJson(
    loaded.request.auxiliary_inputs.b2_source_manifest,
    "B2 P0 source manifest",
  ).value;
  const taskSourceProgram = readBoundJson(
    loaded.request.auxiliary_inputs.task_source_program,
    "B2 task source program",
  ).value;
  const repositoryRoot = resolve(fileURLToPath(new URL("../../..", import.meta.url)));
  validateConfiguration(configuration, loaded.request);
  validateBinding(binding, task);
  validateSourceManifest(manifest, binding);
  validateTaskSourceProgram(taskSourceProgram);
  validateTaskProgram(repositoryRoot, task, taskRecord.path, taskSourceProgram);
  assert(
    binding.source_manifest === loaded.request.auxiliary_inputs.b2_source_manifest.path
      || binding.source_manifest.endsWith("/b2-p0-source-manifest.json"),
    "B2_BINDING_REJECTED",
    "B2 binding does not name the exact source manifest",
  );
  assert(
    environment.model.provider === "none-offline"
      && task.network_policy === "none"
      && environment.network.policy === "none",
    "B2_EXTERNAL_BOUNDARY_REJECTED",
    "B2 environment is not provider-neutral and offline",
  );

  const tools = toolchainPaths();
  const gitIdentity = executableIdentity(tools.git);
  const cargoIdentity = executableIdentity(tools.cargo);
  const rustcIdentity = executableIdentity(tools.rustc);
  const sentinel = markTargetStarted(loaded.request, loaded.sentinel, {
    mode: "EXACT_ACCEPTED_P0_REPOSITORY_ANALYSIS_SCAN",
    frozen_base_commit: ACCEPTED_P0_BINDING.frozen_base_commit,
  });
  const bindingChecks = await verifyP0Binding({ git: tools.git, repositoryRoot });
  const analyzerRoot = createContainedDirectory(loaded.runRoot, "work/b2-p0-analyzer");
  const materializedAnalyzer = await materializeAnalyzer({
    git: tools.git,
    repositoryRoot,
    analyzerRoot,
    manifest,
  });
  const sourceRoot = createContainedDirectory(loaded.runRoot, "work/b2-scan-source");
  const sourceInventory = materializeScanSource(
    repositoryRoot,
    taskSourceProgram.task_source,
    sourceRoot,
  );

  const cargoEnvironment = {
    HOME: process.env.HOME,
    CARGO_HOME: tools.cargoHome,
    CARGO_NET_OFFLINE: "true",
    RUSTUP_HOME: tools.rustupHome,
    PATH: `${resolve(tools.cargo, "..")}:/usr/bin:/bin`,
  };
  const gitVersion = await runExact({ argv: [tools.git, "--version"], cwd: repositoryRoot });
  const cargoVersion = await runExact({
    argv: [tools.cargo, "--version"],
    cwd: analyzerRoot,
    environment: cargoEnvironment,
  });
  const rustcVersion = await runExact({ argv: [tools.rustc, "--version"], cwd: analyzerRoot });
  const targetRoot = createContainedDirectory(loaded.runRoot, "work/b2-cargo-target");
  const build = await runExact({
    argv: [
      tools.cargo,
      "build",
      "--offline",
      "--locked",
      "--manifest-path",
      join(analyzerRoot, "Cargo.toml"),
      "--target-dir",
      targetRoot,
    ],
    cwd: analyzerRoot,
    timeoutSeconds: Math.min(120, loaded.request.limits.wall_clock_seconds),
    environment: cargoEnvironment,
  });
  const analyzerExecutable = assertExistingPathWithoutSymlink(
    join(targetRoot, "debug", "sourcelens-analyzer"),
    "built P0 analyzer",
  );
  const analyzerBytes = readFileSync(analyzerExecutable);
  const scan = await runExact({
    argv: [analyzerExecutable, "scan", "--repo-path", sourceRoot],
    cwd: loaded.runRoot,
    timeoutSeconds: Math.min(120, loaded.request.limits.wall_clock_seconds),
  });
  let scanResult;
  try {
    scanResult = JSON.parse(scan.stdout.toString("utf8"));
  } catch (error) {
    throw new Error(`real repository_analysis.scan output is not JSON: ${error.message}`);
  }
  assert(
    scanResult.scan_result_schema_version === binding.required_scan_result_schema_version
      && realpathSync(scanResult.repo_path) === realpathSync(sourceRoot)
      && scanResult.file_tree !== null
      && typeof scanResult.file_tree === "object"
      && Array.isArray(scanResult.file_tree.file_manifest),
    "B2_SCAN_RESULT_REJECTED",
    "real repository_analysis.scan output contract is invalid",
  );
  assert(verifyScanSource(sourceRoot, sourceInventory), "B2_SOURCE_MUTATION_REJECTED", "B2 mutated its disposable scan source");

  const actions = [{
    sequence: 1,
    action_id: `${loaded.request.run_id}:1`,
    action_type: "tool_call",
    tool_class: "repository_analysis.scan",
    operation_id: ACCEPTED_P0_BINDING.operation_id,
    executable_sha256: sha256(analyzerBytes),
    executable_byte_length: analyzerBytes.length,
    source_manifest_sha256: sha256(Buffer.from(canonicalJson(sourceInventory), "utf8")),
    stdout_sha256: scan.ledger.stdout_sha256,
    stderr_sha256: scan.ledger.stderr_sha256,
    exit_code: scan.ledger.exit_status,
    expected_exit_matched: scan.ledger.expected_exit_matched,
  }];
  const result = {
    ...commonResultBase({
      request: loaded.request,
      task,
      configuration,
      actions,
      usage: {
        input_tokens: 0,
        output_tokens: 0,
        tool_calls: 1,
        retries: 0,
        human_interventions: 0,
        cost_usd: 0,
        latency_ms: scan.ledger.latency_ms,
      },
      targetSentinel: sentinel,
    }),
    result: {
      summary: "Exact accepted P0 repository_analysis.scan completed against a disposable source.",
      changed_paths: [],
      tests: ["repository_analysis.scan"],
    },
    provenance: {
      kind: "EXACT_ACCEPTED_P0_FROZEN_BASE_REAL_SCAN",
      live_model_invoked: false,
      provider_invoked: false,
      model_performance_sample: false,
      p0_binding: ACCEPTED_P0_BINDING,
    },
    p0_binding_checks: bindingChecks,
    materialized_analyzer: {
      subtree: ACCEPTED_P0_BINDING.analyzer_subtree,
      listing_ledger: materializedAnalyzer.listing_ledger,
      artifacts: materializedAnalyzer.artifacts,
    },
    toolchain: {
      git: { ...gitIdentity, version_stdout_sha256: gitVersion.ledger.stdout_sha256 },
      cargo: { ...cargoIdentity, version_stdout_sha256: cargoVersion.ledger.stdout_sha256 },
      rustc: { ...rustcIdentity, version_stdout_sha256: rustcVersion.ledger.stdout_sha256 },
    },
    toolchain_ledgers: {
      git_version: gitVersion.ledger,
      cargo_version: cargoVersion.ledger,
      rustc_version: rustcVersion.ledger,
      offline_locked_build: build.ledger,
    },
    scan_ledger: scan.ledger,
    scan_result: scanResult,
    source_mutation_observed: false,
    rollback: {
      required: false,
      status: "NOT_APPLICABLE_READ_ONLY_SCAN_SOURCE_UNCHANGED",
      source_exact_after_scan: true,
    },
  };
  assertFalseEffects(result.requested_external_effects, "B2 result requested external effects");
  assertFalseEffects(result.observed_external_effects, "B2 observed external effects");
  return result;
}

async function main() {
  const args = parseEntryArguments(process.argv.slice(2));
  const loaded = loadExecutionRequest(args.requestPath, ADAPTER_ID);
  validateEntryPaths(args, loaded);
  emit(await executeB2(args.requestPath));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stdout.write(`${canonicalJson({
      schema_version: "1.0",
      record_type: "p1_125_adapter_failure",
      adapter_id: ADAPTER_ID,
      verdict: "NON_PASS",
      reason_code: error.code ?? "UNCAUGHT_EXCEPTION",
      message: `${error.name}: ${error.message}`,
      requested_external_effects: FALSE_EXTERNAL_EFFECTS,
      observed_external_effects: FALSE_EXTERNAL_EFFECTS,
    })}\n`);
    process.exit(1);
  });
}

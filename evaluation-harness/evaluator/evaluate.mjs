#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalJson, validate } from "./schema-validator.mjs";

export const VERSION = "1.0.0";
export const EVALUATOR_ID = "AIOS-P1-001-QUALITY-EVALUATOR";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPOSITORY_ROOT = resolve(HERE, "../..");
const SCHEMAS = Object.freeze({
  task: "task-spec.schema.json",
  environment: "environment-snapshot.schema.json",
  configuration: "system-configuration.schema.json",
  runRecord: "run-record.schema.json",
});
const ORACLE_KEYS = Object.freeze([
  "schema_version", "oracle_id", "evaluator_id", "evaluator_version", "task_id", "dataset_version",
  "adapter_id", "adapter_version", "environment_snapshot_id", "system_configuration_id",
  "expected_result_ref", "expected_result_sha256", "required_terminal_status",
  "required_stop_reason_code", "required_verification_ref", "required_feature_flags",
  "forbidden_capability_claims", "claim_boundary",
]);

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function loadJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(`invalid JSON in ${path.split(sep).at(-1)}: ${error.message}`);
  }
}

function evaluatorIdentity() {
  const manifest = ["evaluate.mjs", "schema-validator.mjs"].sort().map((name) => {
    const bytes = readFileSync(join(HERE, name));
    return `${name}\0${sha256(bytes)}\0${bytes.length}\n`;
  }).join("");
  return sha256(Buffer.from(manifest, "utf8"));
}

class ConformanceEvaluator {
  constructor(paths) {
    this.paths = paths;
    this.checks = [];
    this.reasons = [];
  }

  run() {
    const task = loadJson(this.paths.task);
    const environment = loadJson(this.paths.environment);
    const configuration = loadJson(this.paths.configuration);
    const runRecord = loadJson(this.paths.runRecord);
    const oracle = loadJson(this.paths.oracle);
    const resultBytes = readFileSync(this.paths.result);

    this.validateSchema("task", task);
    this.validateSchema("environment", environment);
    this.validateSchema("configuration", configuration);
    this.validateSchema("runRecord", runRecord);
    this.validateOracle(oracle);

    this.check("TASK_ID_MATCH", task.task_id === oracle.task_id && runRecord.task_id === task.task_id);
    this.check("DATASET_VERSION_MATCH", runRecord.dataset_version === task.dataset_version && task.dataset_version === oracle.dataset_version);
    this.check("ENVIRONMENT_REFERENCE_MATCH", task.environment_snapshot_ref === environment.snapshot_id && environment.snapshot_id === runRecord.environment_snapshot_id && environment.snapshot_id === oracle.environment_snapshot_id);
    this.check("SOURCE_IDENTITY_MATCH", this.sourceIdentityMatches(task, environment));
    this.check("NETWORK_POLICY_MATCH", this.networkPolicyMatches(task, environment));
    this.check("CONFIGURATION_ID_MATCH", configuration.configuration_id === runRecord.system_configuration_id && configuration.configuration_id === oracle.system_configuration_id);
    this.check("CONFIGURATION_BINDING_MATCH", this.configurationBindingMatches(task, environment, configuration));
    this.check("HARNESS_STUB_CLAIM_BOUNDARY", this.harnessStubBoundary(configuration, oracle));
    this.check("BASELINE_CONTEXT_HASH", this.referencedHashMatches(task.baseline_context.artifact_ref, task.baseline_context.sha256));
    this.check("RESPONSE_FORMAT_HASH", this.referencedHashMatches(task.baseline_context.response_format_ref, task.baseline_context.response_format_sha256));
    this.check("ORACLE_EXPECTED_RESULT_HASH", this.referencedHashMatches(oracle.expected_result_ref, oracle.expected_result_sha256));

    const resultSha = sha256(resultBytes);
    this.check("RESULT_SHA256_MATCH", resultSha === oracle.expected_result_sha256);
    this.check("RUN_RECORD_RESULT_HASH_MATCH", runRecord.artifact_checksums.result === resultSha);
    this.check("RUN_RECORD_ADAPTER_MATCH", runRecord.adapter_id === configuration.adapter_id && runRecord.adapter_version === configuration.adapter_version && runRecord.adapter_id === oracle.adapter_id && runRecord.adapter_version === oracle.adapter_version);
    this.check("TERMINAL_STATUS_MATCH", runRecord.terminal_status === oracle.required_terminal_status);
    this.check("STOP_REASON_MATCH", runRecord.stop_reason_code === oracle.required_stop_reason_code);
    this.check("VERIFICATION_REFERENCE_MATCH", runRecord.verification_ref === oracle.required_verification_ref);
    this.check("NO_POLICY_VIOLATIONS", Array.isArray(runRecord.policy_violations) && runRecord.policy_violations.length === 0);
    this.check("NOT_INFRASTRUCTURE_INVALID", runRecord.invalid_run_reason === null);

    return {
      schema_version: "1.0",
      evaluator_id: EVALUATOR_ID,
      evaluator_version: VERSION,
      evaluator_identity_sha256: evaluatorIdentity(),
      task_id: task.task_id,
      run_id: runRecord.run_id,
      verdict: this.reasons.length === 0 ? "PASS" : "FAIL",
      reason_codes: [...this.reasons].sort(),
      checks: this.checks,
      claim_boundary: oracle.claim_boundary,
    };
  }

  validateSchema(kind, instance) {
    const schema = loadJson(join(this.paths.schemaRoot, SCHEMAS[kind]));
    const errors = validate(instance, schema);
    if (errors.length > 0) throw new Error(`${kind} schema validation failed: ${errors.join("; ")}`);
  }

  validateOracle(oracle) {
    if (oracle === null || typeof oracle !== "object" || Array.isArray(oracle)) {
      throw new Error("oracle must be an object");
    }
    if (JSON.stringify(Object.keys(oracle).sort()) !== JSON.stringify([...ORACLE_KEYS].sort())) {
      throw new Error("oracle must contain the closed evaluator contract keys");
    }
    if (oracle.evaluator_id !== EVALUATOR_ID || oracle.evaluator_version !== VERSION) {
      throw new Error("oracle evaluator identity mismatch");
    }
    if (!/^[0-9a-f]{64}$/.test(oracle.expected_result_sha256)) {
      throw new Error("oracle expected_result_sha256 is invalid");
    }
    if (oracle.required_feature_flags === null || typeof oracle.required_feature_flags !== "object" || Array.isArray(oracle.required_feature_flags)) {
      throw new Error("oracle required_feature_flags must be an object");
    }
    if (!Array.isArray(oracle.forbidden_capability_claims)) {
      throw new Error("oracle forbidden_capability_claims must be an array");
    }
  }

  sourceIdentityMatches(task, environment) {
    const taskRepository = task.repository;
    const environmentSource = environment.source;
    return taskRepository.identity === environmentSource.repository_identity
      && taskRepository.base_commit === environmentSource.base_commit
      && taskRepository.tree_hash === environmentSource.tree_hash
      && taskRepository.dirty_state_policy === "clean_immutable_base"
      && environmentSource.worktree_clean === true;
  }

  networkPolicyMatches(task, environment) {
    return task.network_policy === "none"
      && environment.network.policy === "none"
      && task.allowed_network_hosts.length === 0
      && environment.network.allowed_hosts.length === 0;
  }

  configurationBindingMatches(task, environment, configuration) {
    const environmentTools = environment.tools.map((tool) => tool.tool_id);
    return configuration.model_ref === environment.model.model_ref
      && configuration.prompt_ref === environment.prompt_version
      && configuration.policy_ref === environment.policy_version
      && configuration.response_format_ref === task.baseline_context.response_format_ref
      && configuration.enabled_tools.every((tool) => task.allowed_tools.includes(tool))
      && configuration.enabled_tools.every((tool) => environmentTools.includes(tool));
  }

  harnessStubBoundary(configuration, oracle) {
    const requiredFlagsMatch = Object.entries(oracle.required_feature_flags)
      .every(([key, value]) => configuration.feature_flags[key] === value);
    return configuration.adapter_id === "A0"
      && configuration.adapter_version === "HARNESS_STUB-1.0"
      && configuration.adapter_id === oracle.adapter_id
      && configuration.adapter_version === oracle.adapter_version
      && requiredFlagsMatch
      && configuration.feature_flags.benchmark_claim === false
      && configuration.feature_flags.agent_capability_claim === false;
  }

  referencedHashMatches(reference, expectedSha) {
    if (typeof reference !== "string" || typeof expectedSha !== "string") return false;
    try {
      const root = realpathSync(this.paths.artifactRoot);
      const candidate = realpathSync(resolve(root, reference));
      const relativePath = relative(root, candidate);
      if (relativePath.startsWith(`..${sep}`) || relativePath === ".." || relativePath === "") return false;
      return statSync(candidate).isFile() && sha256(readFileSync(candidate)) === expectedSha;
    } catch {
      return false;
    }
  }

  check(id, passed) {
    this.checks.push({ id, status: passed ? "PASS" : "FAIL" });
    if (!passed) this.reasons.push(id.endsWith("_MATCH") ? `${id.slice(0, -6)}_MISMATCH` : id);
  }
}

function usage() {
  return "Usage: evaluate.mjs --task FILE --environment FILE --configuration FILE --run-record FILE --result FILE --oracle FILE [--schema-root DIR] [--artifact-root DIR]";
}

function parseArguments(argv) {
  if (argv.includes("--help")) return { help: true };
  const aliases = new Map([
    ["--task", "task"], ["--environment", "environment"], ["--configuration", "configuration"],
    ["--run-record", "runRecord"], ["--result", "result"], ["--oracle", "oracle"],
    ["--schema-root", "schemaRoot"], ["--artifact-root", "artifactRoot"],
  ]);
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const option = argv[index];
    const value = argv[index + 1];
    if (!aliases.has(option) || value === undefined) throw new Error(`invalid argument sequence at ${option ?? "<end>"}`);
    options[aliases.get(option)] = value;
  }
  const required = ["task", "environment", "configuration", "runRecord", "result", "oracle"];
  const missing = required.filter((key) => !options[key]);
  if (missing.length > 0) throw new Error(`missing required arguments: ${missing.join(",")}`);
  options.schemaRoot ??= join(DEFAULT_REPOSITORY_ROOT, "docs/aios/schemas");
  options.artifactRoot ??= DEFAULT_REPOSITORY_ROOT;
  return options;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) {
      process.stdout.write(`${usage()}\n`);
      process.exit(0);
    }
    const result = new ConformanceEvaluator(options).run();
    process.stdout.write(`${canonicalJson(result)}\n`);
    process.exit(result.verdict === "PASS" ? 0 : 1);
  } catch (error) {
    const failure = {
      schema_version: "1.0",
      evaluator_id: EVALUATOR_ID,
      evaluator_version: VERSION,
      verdict: "FAIL",
      reason_codes: ["EVALUATOR_INPUT_INVALID"],
      error: `${error.name}: ${error.message}`,
    };
    process.stdout.write(`${canonicalJson(failure)}\n`);
    process.exit(2);
  }
}

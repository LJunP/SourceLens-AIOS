#!/usr/bin/env node

import {
  existsSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import {
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  parseExactJsonBytes,
  safeRealDirectory,
  safeRegularFile,
  sha256,
  verifyClosedManifest,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import {
  ACCEPTED_TASK_IDS,
  loadAcceptedCompilerProfile,
  loadAcceptedTask,
} from "../../harness/p1-149-accepted-execution-spine/accepted-inputs.mjs";
import {
  EXECUTION_ARTIFACT_KEYS,
  executeSpine,
} from "../../harness/p1-149-accepted-execution-spine/execution.mjs";
import {
  REPOSITORY_ROOT,
} from "../../harness/p1-149-accepted-execution-spine/core.mjs";
import {
  buildNormalizedProviderResponse,
  compilePatchIrV2,
  patchIrBytes,
} from "../../harness/p1-149-accepted-execution-spine/patch-ir-v2.mjs";
import {
  resolvePostformalAcceptedControlBinding,
} from "./postformal-control-binding.mjs";

const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const FORMAL_EFFECTS = Object.freeze({
  network: true,
  provider: true,
  secret: true,
  remote: false,
  production: false,
  public: false,
});
const ADAPTER_IDS = Object.freeze(["B0", "B1", "B2"]);
const PROFILE_IDS = Object.freeze(["B0_A", "B0_B", "B1_A", "B1_B", "B2_A", "B2_B"]);
const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const ROUTE_ID = "P1_MINIMUM_COOPERATIVE_LOCAL_RESEARCH_ARTIFACT_AND_PREREGISTRATION_STRICT_EXIT_ROUTE_V1";
const CLAIM_BOUNDARY = "COOPERATIVE_LOCAL_REPRODUCIBLE_RESEARCH_ARTIFACT_ONLY";
const EXPECTED_ACCEPTED_INPUTS = Object.freeze({
  p1_035: {
    task_id: "AIOS-P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET",
    accepted_candidate_commit: "686eda0cd7a93b72ac5e64301479f17e4b096fb0",
    accepted_candidate_tree: "b2740b44d0051303057deac7d719c27fd6a5578a",
  },
  p1_101: {
    task_id: "AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE",
    accepted_candidate_commit: "633f9daf133bf616cd293fb343058e2efba2a3ed",
    accepted_candidate_tree: "999f37f93692a045d455adf0ea503947ed5555a5",
  },
  p1_129: {
    task_id: "AIOS-P1-129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION",
    accepted_candidate_commit: "a772dc5d350ec6b38a84e430b01f75628429aa7b",
    accepted_candidate_tree: "905dd694922ba9a2b452d15c93dc17cefc9e53c1",
  },
  p1_149: {
    task_id: "AIOS-P1-149_ACCEPTED_EXECUTION_SPINE_CONVERGENCE",
    accepted_candidate_commit: "88600ee18848e0d2c6d7f2012d0f548021062720",
    accepted_candidate_tree: "34a16c8177bc0f72fd35a0510429ed1979f72fb3",
  },
});
const EXPECTED_MANIFEST_EXCLUSIONS = Object.freeze([
  "EVIDENCE_MANIFEST.json",
  "report/REPRODUCIBLE_BASELINE_REPORT.json",
  "report/REPORT_REBUILD_RECEIPT.json",
  "reviews/INDEPENDENT_EVALUATOR_RECEIPT.json",
]);
const PLAN_KEYS = Object.freeze([
  "accepted_inputs",
  "cells",
  "claim_boundary",
  "denominator",
  "endpoint",
  "external_effects",
  "model",
  "route_id",
  "schema_version",
  "task_id",
]);
const CELL_KEYS = Object.freeze([
  "adapter_id",
  "baseline_id",
  "cell_id",
  "ordinal",
  "profile_id",
  "repetition_id",
  "request_shape",
  "task_id",
]);
const IDENTITY_KEYS = Object.freeze(["byte_length", "path", "sha256"]);
const REQUEST_RECEIPT_KEYS = Object.freeze([
  "automatic_retry",
  "cell_id",
  "created_at",
  "effect_authorized",
  "endpoint",
  "execution_id",
  "model",
  "preformal_gate",
  "profile_id",
  "provider_request",
  "repetition_id",
  "request",
  "request_sequence",
  "schema_version",
  "task_id",
]);
const RESPONSE_RECEIPT_KEYS = Object.freeze([
  "automatic_retry",
  "cell_id",
  "completion_status",
  "execution_id",
  "http_status",
  "peer_address",
  "peer_port",
  "provider_request",
  "received_at",
  "request_receipt",
  "response",
  "response_id",
  "schema_version",
  "usage",
]);
const TRANSPORT_RECEIPT_KEYS = Object.freeze([
  "automatic_retry", "cell_id", "execution_id", "http_status", "observed_at",
  "peer_address", "peer_port", "provider_request", "reason_code", "request_receipt",
  "response", "schema_version", "transport_status",
]);
const TERMINAL_KEYS = Object.freeze([
  "automatic_retries",
  "cell_id",
  "classification",
  "execution_id",
  "execution_manifest",
  "provider_request_count",
  "reason_code",
  "request_receipt",
  "response_receipt",
  "schema_version",
  "task_id",
  "terminal_at",
]);
const RUN_RECEIPT_KEYS = Object.freeze([
  "automatic_retries",
  "completed_at",
  "denominator",
  "diagnostic",
  "diagnostic_provider_requests",
  "execution_id",
  "external_effects",
  "formal_provider_requests",
  "provider_requests",
  "report_rebuild_required",
  "scheduled_cells",
  "schema_version",
  "secret_persisted",
  "secret_reads",
  "status",
  "task_id",
  "taxonomy",
  "terminal_cells",
]);
const ENVIRONMENT_KEYS = Object.freeze([
  "accepted_inputs",
  "architecture",
  "dataset_manifest",
  "endpoint",
  "external_effects",
  "model",
  "node",
  "platform",
  "repository",
  "schema_version",
  "task_id",
]);
const CONFIGURATION_KEYS = Object.freeze([
  "automatic_retry_max",
  "claim_boundary",
  "denominator",
  "diagnostic_requests_max",
  "endpoint",
  "external_effects",
  "formal_requests_exact",
  "manifest_exclusions",
  "model",
  "provider_requests_max",
  "route_id",
  "schema_version",
  "secret_entry",
  "task_id",
]);
const P1129_CONTROL_KEYS = Object.freeze([
  "accepted_task_count", "b2_real_repository_analysis_scan_children", "cells", "command",
  "disposable_root_cleaned", "evaluator_source", "exit_status", "external_effects",
  "false_accepts", "negative_cases", "negative_results", "positive_runs", "schema_version",
  "signal", "status", "stderr", "stdout", "summary", "worker_source",
]);
const P1129_CELL_KEYS = Object.freeze([
  "adapter_id", "cell_id", "copied_artifacts", "profile_id", "repetition_id", "task_id",
]);
const P1129_ARTIFACT_NAMES = Object.freeze([
  "request.json",
  "adapter-execution-request.json",
  "adapter-command-ledger.json",
  "adapter-result.json",
  "trace.jsonl",
  "run-record.json",
  "stable-projection.json",
]);

class EvaluationNonPass extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = "EvaluationNonPass";
    this.code = code;
    this.details = details;
  }
}

const REQUEST_EXPECTATION_CACHE = new Map();

function fail(code, message, details = null) {
  throw new EvaluationNonPass(code, message, details);
}

function assert(condition, code, message, details = null) {
  if (!condition) fail(code, message, details);
}

function exactKeys(value, keys, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value),
    "SCHEMA_INVALID", `${label} must be an object`);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  assert(isDeepStrictEqual(actual, expected), "SCHEMA_INVALID", `${label} key set is not closed`, {
    actual,
    expected,
  });
  return value;
}

function readExactJson(root, relativePath, label) {
  const path = safeRegularFile(join(root, ...relativePath.split("/")), label, true);
  const bytes = readFileSync(path);
  return {
    path,
    bytes,
    value: parseExactJsonBytes(bytes, { label, canonical: true }),
  };
}

function validateIdentity(root, value, label) {
  exactKeys(value, IDENTITY_KEYS, `${label} identity`);
  assert(typeof value.path === "string" && !value.path.startsWith("/") && !value.path.includes(".."),
    "IDENTITY_INVALID", `${label} path is not a safe relative path`);
  const path = safeRegularFile(join(root, ...value.path.split("/")), label, true);
  const bytes = readFileSync(path);
  assert(value.byte_length === bytes.length && value.sha256 === sha256(bytes),
    "IDENTITY_MISMATCH", `${label} bytes differ from the bound identity`);
  return { path, bytes, identity: value };
}

function validateRepositoryIdentity(value, label) {
  exactKeys(value, IDENTITY_KEYS, `${label} identity`);
  assert(typeof value.path === "string" && !value.path.startsWith("/") && !value.path.includes(".."),
    "IDENTITY_INVALID", `${label} path is not a safe repository-relative path`);
  const path = safeRegularFile(join(REPOSITORY_ROOT, ...value.path.split("/")), label, true);
  const bytes = readFileSync(path);
  assert(bytes.length === value.byte_length && sha256(bytes) === value.sha256,
    "IDENTITY_MISMATCH", `${label} repository bytes drifted`);
  return { path, bytes, identity: value };
}

function currentRepositoryIdentity() {
  const run = (args) => {
    const result = spawnSync("/usr/bin/git", args, {
      cwd: REPOSITORY_ROOT,
      shell: false,
      encoding: "utf8",
      env: { PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", LANG: "C", LC_ALL: "C", TZ: "UTC" },
    });
    assert(!result.error && result.status === 0, "SOURCE_IDENTITY_UNAVAILABLE", `git ${args.join(" ")} failed`);
    return result.stdout.trim();
  };
  return {
    commit: run(["rev-parse", "HEAD"]),
    tree: run(["rev-parse", "HEAD^{tree}"]),
    dirty: run(["status", "--porcelain", "--untracked-files=all"]) !== "",
  };
}

function validateAcceptedP1129Control(root, plan, bindingChain = null) {
  const record = readExactJson(
    root,
    "accepted-controls/P1_129_CONTROL_RECEIPT.json",
    "accepted P1-129 control receipt",
  );
  const value = record.value;
  exactKeys(value, P1129_CONTROL_KEYS, "accepted P1-129 control receipt");
  assert(value.schema_version === "p1-207-accepted-p1-129-control-receipt/v1"
      && value.status === "PASS"
      && value.accepted_task_count === 6
      && value.positive_runs === 36
      && value.negative_cases === 53
      && value.false_accepts === 0
      && value.b2_real_repository_analysis_scan_children === 12
      && value.exit_status === 0
      && value.signal === null
      && value.disposable_root_cleaned === true
      && isDeepStrictEqual(value.external_effects, FALSE_EFFECTS)
      && Array.isArray(value.cells)
      && value.cells.length === 36,
  "ACCEPTED_P1_129_CONTROL_NON_PASS", "accepted P1-129 control Gate drifted");
  validateRepositoryIdentity(value.worker_source, "accepted P1-129 Worker source");
  validateRepositoryIdentity(value.evaluator_source, "accepted P1-129 evaluator source");
  for (const [name, identity] of [
    ["stdout.log", value.stdout],
    ["stderr.log", value.stderr],
    ["quality-formal-summary.json", value.summary],
    ["negative-results.json", value.negative_results],
  ]) {
    exactKeys(identity, ["byte_length", "sha256"], `accepted P1-129 ${name} identity`);
    const bytes = readFileSync(safeRegularFile(join(root, "accepted-controls", "p1-129", name), `accepted P1-129 ${name}`, true));
    assert(bytes.length === identity.byte_length && sha256(bytes) === identity.sha256,
      "ACCEPTED_P1_129_CONTROL_NON_PASS", `accepted P1-129 ${name} identity drifted`);
  }
  const expected = new Map(plan.cells.map((cell) => [cell.cell_id, cell]));
  const seen = new Set();
  for (const cellRecord of value.cells) {
    exactKeys(cellRecord, P1129_CELL_KEYS, "accepted P1-129 cell receipt");
    const cell = expected.get(cellRecord.cell_id);
    assert(cell && !seen.has(cell.cell_id)
        && cellRecord.task_id === cell.task_id
        && cellRecord.adapter_id === cell.adapter_id
        && cellRecord.profile_id === cell.profile_id
        && cellRecord.repetition_id === cell.repetition_id
        && Array.isArray(cellRecord.copied_artifacts)
        && cellRecord.copied_artifacts.length === P1129_ARTIFACT_NAMES.length,
    "ACCEPTED_P1_129_CELL_BINDING_INVALID", "accepted P1-129 cell mapping drifted");
    seen.add(cell.cell_id);
    const artifacts = new Map();
    for (const identity of cellRecord.copied_artifacts) {
      const artifact = validateIdentity(root, identity, `${cell.cell_id} accepted P1-129 artifact`);
      const name = identity.path.split("/").at(-1);
      assert(P1129_ARTIFACT_NAMES.includes(name) && !artifacts.has(name),
        "ACCEPTED_P1_129_CELL_BINDING_INVALID", "accepted P1-129 artifact set is not closed");
      artifacts.set(name, artifact.bytes);
    }
    assert(isDeepStrictEqual([...artifacts.keys()].sort(), [...P1129_ARTIFACT_NAMES].sort()),
      "ACCEPTED_P1_129_CELL_BINDING_INVALID", "accepted P1-129 artifact set is incomplete");
    const request = parseExactJsonBytes(artifacts.get("request.json"), {
      label: `${cell.cell_id} accepted P1-129 request`, canonical: true,
    });
    const adapterResult = parseExactJsonBytes(artifacts.get("adapter-result.json"), {
      label: `${cell.cell_id} accepted P1-129 adapter result`, canonical: true,
    });
    const runRecord = parseExactJsonBytes(artifacts.get("run-record.json"), {
      label: `${cell.cell_id} accepted P1-129 run record`, canonical: true,
    });
    assert(request.adapter_id === cell.adapter_id
        && request.repetition_id === cell.repetition_id
        && adapterResult.task_id === cell.task_id
        && runRecord.task_id === cell.task_id
        && runRecord.adapter_id === cell.adapter_id,
    "ACCEPTED_P1_129_CELL_BINDING_INVALID", "accepted P1-129 raw artifacts do not bind the plan cell");
  }
  assert(seen.size === 36, "ACCEPTED_P1_129_CELL_BINDING_INVALID", "accepted P1-129 cell set is incomplete");
  const identity = { path: "accepted-controls/P1_129_CONTROL_RECEIPT.json", ...bytesIdentity(record.bytes) };
  return bindingChain === null ? identity : { ...identity, binding_chain: bindingChain };
}

// Separate recursive JSON parser for untrusted Provider response bytes. Internal
// Evidence uses the implementation's exact-canonical parser; Provider JSON is
// independently parsed here so duplicate keys and unsafe integers cannot be
// hidden by JSON.parse's last-key-wins behavior.
function parseProviderJson(bytes) {
  assert(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 4 * 1024 * 1024,
    bytes?.length > 4 * 1024 * 1024 ? "JSON_SIZE_INVALID" : "JSON_INVALID",
    "Provider response byte length is invalid");
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("JSON_UTF8_INVALID", "Provider response is not exact UTF-8");
  }
  let index = 0;
  const whitespace = () => {
    while (index < text.length && /[\x20\x09\x0a\x0d]/.test(text[index])) index += 1;
  };
  const parseString = () => {
    assert(text[index] === '"', "JSON_SYNTAX_INVALID", "expected JSON string");
    const start = index;
    index += 1;
    while (index < text.length) {
      const char = text[index];
      if (char === '"') {
        index += 1;
        try {
          return JSON.parse(text.slice(start, index));
        } catch {
          fail("JSON_STRING_INVALID", "invalid JSON string escape");
        }
      }
      if (char === "\\") {
        index += 2;
        continue;
      }
      assert(char >= " ", "JSON_STRING_INVALID", "control byte in JSON string");
      index += 1;
    }
    fail("JSON_SYNTAX_INVALID", "unterminated JSON string");
  };
  const parseNumber = () => {
    const match = text.slice(index).match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/);
    assert(match, "JSON_NUMBER_INVALID", "invalid JSON number");
    index += match[0].length;
    const number = Number(match[0]);
    assert(Number.isFinite(number), "JSON_NUMBER_NONFINITE", "non-finite Provider number");
    if (!/[.eE]/.test(match[0])) {
      assert(Number.isSafeInteger(number), "JSON_INTEGER_UNSAFE", "unsafe Provider integer");
    }
    return number;
  };
  const parseValue = () => {
    whitespace();
    const char = text[index];
    if (char === '"') return parseString();
    if (char === "{") {
      index += 1;
      whitespace();
      const result = {};
      const keys = new Set();
      if (text[index] === "}") {
        index += 1;
        return result;
      }
      while (true) {
        whitespace();
        const key = parseString();
        assert(!keys.has(key), "JSON_DUPLICATE_KEY", `duplicate Provider JSON key: ${key}`);
        keys.add(key);
        whitespace();
        assert(text[index] === ":", "JSON_SYNTAX_INVALID", "missing JSON object colon");
        index += 1;
        result[key] = parseValue();
        whitespace();
        if (text[index] === "}") {
          index += 1;
          return result;
        }
        assert(text[index] === ",", "JSON_SYNTAX_INVALID", "missing JSON object comma");
        index += 1;
      }
    }
    if (char === "[") {
      index += 1;
      whitespace();
      const result = [];
      if (text[index] === "]") {
        index += 1;
        return result;
      }
      while (true) {
        result.push(parseValue());
        whitespace();
        if (text[index] === "]") {
          index += 1;
          return result;
        }
        assert(text[index] === ",", "JSON_SYNTAX_INVALID", "missing JSON array comma");
        index += 1;
      }
    }
    if (text.startsWith("true", index)) { index += 4; return true; }
    if (text.startsWith("false", index)) { index += 5; return false; }
    if (text.startsWith("null", index)) { index += 4; return null; }
    if (char === "-" || /[0-9]/.test(char ?? "")) return parseNumber();
    fail("JSON_SYNTAX_INVALID", "unexpected Provider JSON token");
  };
  const result = parseValue();
  whitespace();
  assert(index === text.length, "JSON_TRAILING_CONTENT", "trailing Provider JSON content");
  return result;
}

export function normalizeProviderUsageForReceipt(value) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value),
    "PROVIDER_USAGE_MISSING", "Provider usage is missing or null");
  for (const key of ["prompt_tokens", "completion_tokens", "total_tokens"]) {
    assert(Number.isSafeInteger(value[key]) && value[key] >= 0,
      "PROVIDER_USAGE_INVALID", `Provider usage ${key} is not a nonnegative safe integer`);
  }
  assert(value.total_tokens === value.prompt_tokens + value.completion_tokens,
    "PROVIDER_USAGE_TOTAL_DRIFT", "Provider usage total does not equal prompt plus completion");
  return {
    prompt_tokens: value.prompt_tokens,
    completion_tokens: value.completion_tokens,
    total_tokens: value.total_tokens,
  };
}

function extractCompletion(responseBytes) {
  const response = parseProviderJson(responseBytes);
  assert(response && typeof response === "object" && !Array.isArray(response),
    "CHAT_COMPLETION_SCHEMA_INVALID", "Provider response is not an object");
  assert(typeof response.id === "string" && response.id.length >= 1 && response.id.length <= 512
      && !response.id.includes("\0"),
    "CHAT_COMPLETION_SCHEMA_INVALID", "Provider response id is missing or invalid");
  assert(Array.isArray(response.choices) && response.choices.length >= 1,
    "CHAT_COMPLETION_CHOICES_MISSING", "Provider response choices are missing");
  const choice = response.choices[0];
  assert(choice && typeof choice === "object" && !Array.isArray(choice),
    "CHAT_COMPLETION_SCHEMA_INVALID", "Provider first choice is invalid");
  assert(choice.message && typeof choice.message === "object" && !Array.isArray(choice.message)
      && typeof choice.message.content === "string"
      && choice.message.content.length >= 1
      && choice.message.content.length <= 4 * 1024 * 1024
      && !choice.message.content.includes("\0"),
  "CHAT_COMPLETION_SCHEMA_INVALID", "Provider completion content is missing or invalid");
  return {
    response_id: response.id,
    usage: normalizeProviderUsageForReceipt(response.usage),
    content_bytes: Buffer.from(choice.message.content, "utf8"),
  };
}

function validateRequestBody(request, cell, model) {
  exactKeys(request, ["messages", "model"], `${cell.cell_id} request`);
  assert(request.model === model && Array.isArray(request.messages) && request.messages.length === 2,
    "REQUEST_BODY_INVALID", `${cell.cell_id} request model or messages drifted`);
  for (const [index, message] of request.messages.entries()) {
    exactKeys(message, ["content", "role"], `${cell.cell_id} message ${index + 1}`);
    assert(typeof message.content === "string", "REQUEST_BODY_INVALID", "request content is not a string");
  }
  assert(request.messages[0].role === "system"
      && request.messages[0].content
        === "Return exactly one JSON object conforming to the supplied finite Patch IR contract. Do not use Markdown, prose, comments, tools, network access, or unstated files."
      && request.messages[1].role === "user",
  "REQUEST_BODY_INVALID", `${cell.cell_id} request role or system contract drifted`);

  const prompt = parseProviderJson(Buffer.from(request.messages[1].content, "utf8"));
  exactKeys(prompt, [
    "compiler_profile", "experimental_profile", "required_output", "schema_version", "source_files", "task",
  ], `${cell.cell_id} task prompt`);
  assert(prompt.schema_version === "p1-207-model-task-prompt/v1",
    "REQUEST_BODY_INVALID", `${cell.cell_id} prompt schema drifted`);
  if (!REQUEST_EXPECTATION_CACHE.has(cell.task_id)) {
    const binding = loadAcceptedTask(cell.task_id);
    REQUEST_EXPECTATION_CACHE.set(cell.task_id, {
      compilerProfile: loadAcceptedCompilerProfile(cell.task_id),
      expectedTask: {
        task_id: binding.task.task_id,
        issue: binding.task.issue,
        forbidden_changes: binding.task.forbidden_changes,
        verification: binding.task.verification,
        repository: binding.task.repository,
        task_spec_identity: binding.task_spec.identity,
      },
      expectedSources: binding.source_files.map((entry) => ({
        path: entry.path,
        sha256: entry.sha256,
        byte_length: entry.byte_length,
        utf8: readFileSync(join(binding.source_root, ...entry.path.split("/"))).toString("utf8"),
      })),
    });
  }
  const { compilerProfile, expectedTask, expectedSources } = REQUEST_EXPECTATION_CACHE.get(cell.task_id);
  const expectedProfile = {
    adapter_id: cell.adapter_id,
    profile_id: cell.profile_id,
    repetition_id: cell.repetition_id,
    interpretation: cell.adapter_id === "B0"
      ? "DIRECT_MODEL_PATCH_PROPOSAL"
      : cell.adapter_id === "B1"
        ? "FINITE_TOOL_AGENT_PATCH_PROPOSAL"
        : "SOURCELENS_CONTEXT_PATCH_PROPOSAL",
  };
  const expectedOutput = {
    schema_version: "SL-PATCH-IR/2",
    exact_top_level_keys: ["schema_version", "dataset", "task", "operations"],
    operation_types: ["REPLACE_REGULAR_FILE", "CREATE_REGULAR_FILE"],
    maximum_operations: 3,
    maximum_total_postimage_bytes: 65536,
    operation_order: "LEXICOGRAPHIC_PATH_ASCENDING",
    postimage_encoding: "STRICT_BASE64_WITH_SHA256_AND_BYTE_LENGTH",
    prose_or_markdown_forbidden: true,
  };
  assert(isDeepStrictEqual(prompt.task, expectedTask)
      && isDeepStrictEqual(prompt.experimental_profile, expectedProfile)
      && isDeepStrictEqual(prompt.compiler_profile, compilerProfile)
      && isDeepStrictEqual(prompt.source_files, expectedSources)
      && isDeepStrictEqual(prompt.required_output, expectedOutput),
  "REQUEST_BODY_INVALID", `${cell.cell_id} request does not bind exact accepted inputs`);
}

function validatePlan(plan) {
  exactKeys(plan, PLAN_KEYS, "formal plan");
  assert(plan.schema_version === "p1-207-formal-plan/v1"
      && plan.task_id === TASK_ID
      && plan.route_id === ROUTE_ID
      && plan.claim_boundary === CLAIM_BOUNDARY
      && plan.denominator === 36
      && plan.endpoint === "http://127.0.0.1:8787/v1/chat/completions"
      && plan.model === "gpt-5.6-luna"
      && isDeepStrictEqual(plan.accepted_inputs, EXPECTED_ACCEPTED_INPUTS)
      && isDeepStrictEqual(plan.external_effects, FALSE_EFFECTS)
      && Array.isArray(plan.cells) && plan.cells.length === 36,
  "PLAN_INVALID", "formal plan identity or denominator drifted");
  const keys = new Set();
  const combinations = new Set();
  plan.cells.forEach((cell, index) => {
    exactKeys(cell, CELL_KEYS, `formal plan cell ${index + 1}`);
    assert(cell.ordinal === index + 1
        && cell.cell_id === `formal-${String(index + 1).padStart(3, "0")}`
        && ACCEPTED_TASK_IDS.includes(cell.task_id)
        && ADAPTER_IDS.includes(cell.adapter_id)
        && PROFILE_IDS.includes(cell.profile_id)
        && cell.profile_id === `${cell.adapter_id}_${cell.repetition_id === 1 ? "A" : "B"}`
        && [1, 2].includes(cell.repetition_id)
        && cell.baseline_id === `${cell.task_id}:${cell.profile_id}`
        && cell.request_shape === "CHAT_COMPLETIONS_TYPED_PATCH_IR_V1",
    "PLAN_INVALID", `formal plan cell ${index + 1} is invalid`);
    assert(!keys.has(cell.cell_id), "PLAN_INVALID", "duplicate formal cell id");
    keys.add(cell.cell_id);
    combinations.add(`${cell.task_id}:${cell.adapter_id}:${cell.repetition_id}`);
  });
  assert(combinations.size === 36, "PLAN_INVALID", "formal plan combination set is not closed");
  return plan;
}

function readExecutionArtifacts(root, cell) {
  const executionRoot = join(root, "cells", cell.cell_id, "execution");
  const artifacts = {};
  for (const artifact of EXECUTION_ARTIFACT_KEYS) {
    const path = safeRegularFile(join(executionRoot, artifact), `${cell.cell_id} ${artifact}`, true);
    artifacts[artifact] = readFileSync(path);
  }
  const manifest = parseExactJsonBytes(artifacts["execution-spine.json"], {
    label: `${cell.cell_id} execution manifest`,
    canonical: true,
  });
  assert(manifest.task_id === cell.task_id
      && typeof manifest.run_id === "string"
      && /^P1-207-(?:SYNTHETIC|FORMAL)-formal-[0-9]{3}$/.test(manifest.run_id),
    "EXECUTION_BINDING_INVALID", `${cell.cell_id} execution manifest binding drifted`);
  assert(Array.isArray(manifest.artifacts), "EXECUTION_BINDING_INVALID", "execution manifest artifacts missing");
  for (const identity of manifest.artifacts) {
    assert(identity && typeof identity.path === "string" && Buffer.isBuffer(artifacts[identity.path]),
      "EXECUTION_BINDING_INVALID", "execution manifest contains unknown artifact");
    const actual = bytesIdentity(artifacts[identity.path]);
    assert(actual.sha256 === identity.sha256 && actual.byte_length === identity.byte_length,
      "EXECUTION_BINDING_INVALID", `execution artifact identity drifted: ${identity.path}`);
  }
  return artifacts;
}

function independentlyReexecute(cell, artifacts, executionManifest) {
  const frozenProjection = parseExactJsonBytes(
    artifacts["p1-101-stable-projection.json"],
    { label: `${cell.cell_id} frozen P1-101 stable projection`, canonical: true },
  );
  const fresh = executeSpine({
    taskId: cell.task_id,
    responseBytes: artifacts["provider-response.json"],
    runId: executionManifest.run_id,
  });
  assert(fresh.schema_version === "p1-149-execution-spine-result/v1"
      && fresh.task_id === cell.task_id
      && isDeepStrictEqual(Object.keys(fresh.artifacts).sort(), [...EXECUTION_ARTIFACT_KEYS].sort())
      && isDeepStrictEqual(fresh.stable_projection, frozenProjection)
      && fresh.summary.rollback_exact === true
      && fresh.summary.p1_101_replay === "PASS",
  "INDEPENDENT_REEXECUTION_NON_PASS", `${cell.cell_id} did not independently reproduce`);
  return {
    frozen_projection: bytesIdentity(artifacts["p1-101-stable-projection.json"]),
    fresh_projection: bytesIdentity(canonicalBytes(fresh.stable_projection)),
    accepted_execution_spine: true,
    accepted_p1_101_replay: true,
    oracle_and_tests_reexecuted: true,
    rollback_reexecuted: true,
    verified_success: fresh.summary.worker_observed_classification === "VERIFIED_SUCCESS",
  };
}

function evaluateCell(root, plan, cell, mode) {
  const prefix = `cells/${cell.cell_id}`;
  const request = readExactJson(root, `${prefix}/request.json`, `${cell.cell_id} request`);
  const requestReceipt = readExactJson(root, `${prefix}/request-receipt.json`, `${cell.cell_id} request receipt`);
  const terminal = readExactJson(root, `${prefix}/terminal.json`, `${cell.cell_id} terminal`);
  exactKeys(requestReceipt.value, REQUEST_RECEIPT_KEYS, `${cell.cell_id} request receipt`);
  exactKeys(terminal.value, TERMINAL_KEYS, `${cell.cell_id} terminal`);
  assert(requestReceipt.value.cell_id === cell.cell_id
      && requestReceipt.value.task_id === cell.task_id
      && requestReceipt.value.profile_id === cell.profile_id
      && requestReceipt.value.repetition_id === cell.repetition_id
      && requestReceipt.value.endpoint === plan.endpoint
      && requestReceipt.value.model === plan.model
      && requestReceipt.value.request_sequence === cell.ordinal + (mode === "FORMAL" ? 1 : 0)
      && requestReceipt.value.automatic_retry === false,
  "REQUEST_BINDING_INVALID", `${cell.cell_id} request receipt binding drifted`);
  validateRequestBody(request.value, cell, plan.model);
  const requestIdentity = validateIdentity(root, requestReceipt.value.request, `${cell.cell_id} request`);
  assert(requestIdentity.path === request.path, "REQUEST_BINDING_INVALID", "request path drifted");
  const requestReceiptIdentity = { path: `${prefix}/request-receipt.json`, ...bytesIdentity(requestReceipt.bytes) };
  assert(isDeepStrictEqual(terminal.value.request_receipt, requestReceiptIdentity)
      && terminal.value.cell_id === cell.cell_id
      && terminal.value.task_id === cell.task_id
      && terminal.value.execution_id === requestReceipt.value.execution_id
      && terminal.value.automatic_retries === 0,
  "TERMINAL_BINDING_INVALID", `${cell.cell_id} terminal request binding drifted`);
  if (mode === "FORMAL") {
    const gate = validateIdentity(root, requestReceipt.value.preformal_gate, `${cell.cell_id} preformal Gate`);
    assert(gate.identity.path === "PREFORMAL_GATE_RECEIPT.json",
      "REQUEST_BINDING_INVALID", "formal request does not bind the frozen preformal Gate");
  } else {
    assert(requestReceipt.value.preformal_gate === null,
      "SYNTHETIC_EFFECT_DRIFT", "synthetic request claims a preformal effect Gate");
  }

  let reconstructed = "FAILED";
  let reasonCode = "NO_STRICT_COMPLETION";
  let usage = null;
  let providerResponseId = null;
  let reexecution = null;
  const transportRecord = readExactJson(root, `${prefix}/transport-receipt.json`, `${cell.cell_id} transport receipt`);
  exactKeys(transportRecord.value, TRANSPORT_RECEIPT_KEYS, `${cell.cell_id} transport receipt`);
  const transport = transportRecord.value;
  assert(transport.schema_version === "p1-207-transport-receipt/v1"
      && transport.execution_id === requestReceipt.value.execution_id
      && transport.cell_id === cell.cell_id
      && isDeepStrictEqual(transport.request_receipt, requestReceiptIdentity)
      && transport.automatic_retry === false
      && transport.provider_request === (mode === "FORMAL"),
  "TRANSPORT_BINDING_INVALID", `${cell.cell_id} transport receipt binding drifted`);
  if (mode === "SYNTHETIC") {
    assert(transport.transport_status === "SYNTHETIC_LOCAL"
        && transport.reason_code === "NONE"
        && transport.http_status === null
        && transport.peer_address === null
        && transport.peer_port === null,
    "SYNTHETIC_EFFECT_DRIFT", `${cell.cell_id} synthetic transport claims an external effect`);
  } else {
    assert(["RECEIVED", "TRANSPORT_NON_PASS"].includes(transport.transport_status),
      "TRANSPORT_BINDING_INVALID", `${cell.cell_id} formal transport status is invalid`);
    if (transport.peer_address !== null || transport.peer_port !== null) {
      assert(transport.peer_address === "127.0.0.1" && transport.peer_port === 8787,
        "NON_LOOPBACK_REJECTED", `${cell.cell_id} Provider peer is not exact loopback`);
    }
    if (transport.transport_status === "RECEIVED") {
      assert(transport.peer_address === "127.0.0.1" && transport.peer_port === 8787,
        "NON_LOOPBACK_REJECTED", `${cell.cell_id} received response lacks exact loopback peer proof`);
    }
  }

  if (transport.response === null) {
    assert(terminal.value.response_receipt === null
        && terminal.value.execution_manifest === null
        && transport.transport_status === "TRANSPORT_NON_PASS"
        && typeof transport.reason_code === "string"
        && transport.reason_code !== "NONE",
    "TRANSPORT_BINDING_INVALID", `${cell.cell_id} response-free transport closure is invalid`);
    reconstructed = "FAILED";
    reasonCode = transport.reason_code;
  } else {
    const transportResponse = validateIdentity(root, transport.response, `${cell.cell_id} transport response`);
    assert(transportResponse.identity.path === `${prefix}/response.raw`
        && terminal.value.response_receipt !== null,
    "TRANSPORT_BINDING_INVALID", `${cell.cell_id} transport response path or terminal binding drifted`);
    const responseReceipt = readExactJson(root, `${prefix}/response-receipt.json`, `${cell.cell_id} response receipt`);
    exactKeys(responseReceipt.value, RESPONSE_RECEIPT_KEYS, `${cell.cell_id} response receipt`);
    const responseReceiptIdentity = { path: `${prefix}/response-receipt.json`, ...bytesIdentity(responseReceipt.bytes) };
    assert(isDeepStrictEqual(terminal.value.response_receipt, responseReceiptIdentity)
        && isDeepStrictEqual(responseReceipt.value.request_receipt, requestReceiptIdentity)
        && responseReceipt.value.cell_id === cell.cell_id
        && responseReceipt.value.execution_id === requestReceipt.value.execution_id
        && isDeepStrictEqual(responseReceipt.value.response, transport.response)
        && responseReceipt.value.http_status === (mode === "FORMAL" ? transport.http_status : 200)
        && responseReceipt.value.peer_address === (mode === "FORMAL" ? transport.peer_address : null)
        && responseReceipt.value.peer_port === (mode === "FORMAL" ? transport.peer_port : null)
        && responseReceipt.value.automatic_retry === false,
    "RESPONSE_BINDING_INVALID", `${cell.cell_id} response receipt binding drifted`);
    const response = validateIdentity(root, responseReceipt.value.response, `${cell.cell_id} response`);
    assert(response.path === transportResponse.path && response.bytes.equals(transportResponse.bytes),
      "RESPONSE_BINDING_INVALID", "response bytes differ from transport-bound raw bytes");
    let completion = null;
    let completionError = null;
    try {
      completion = extractCompletion(response.bytes);
    } catch (error) {
      if (!(error instanceof EvaluationNonPass)) throw error;
      completionError = error;
    }
    const expectedCompletionStatus = transport.transport_status !== (mode === "FORMAL" ? "RECEIVED" : "SYNTHETIC_LOCAL")
      ? transport.reason_code
      : !(responseReceipt.value.http_status >= 200 && responseReceipt.value.http_status < 300)
        ? "HTTP_NON_2XX"
        : completionError?.code ?? (mode === "FORMAL" ? "CHAT_COMPLETION_RECEIVED" : "SYNTHETIC_LOCAL_COMPLETION");
    assert(responseReceipt.value.response_id === (completion?.response_id ?? null)
        && isDeepStrictEqual(responseReceipt.value.usage, completion?.usage ?? null)
        && responseReceipt.value.completion_status === expectedCompletionStatus,
    "RESPONSE_BINDING_INVALID", "response receipt does not equal independently parsed raw bytes");
    usage = completion?.usage ?? null;
    providerResponseId = completion?.response_id ?? null;

    if (transport.transport_status !== (mode === "FORMAL" ? "RECEIVED" : "SYNTHETIC_LOCAL")) {
      reconstructed = "FAILED";
      reasonCode = transport.reason_code;
    } else if (!(responseReceipt.value.http_status >= 200 && responseReceipt.value.http_status < 300)) {
      reconstructed = "FAILED";
      reasonCode = "HTTP_NON_2XX";
    } else if (completionError !== null) {
      reconstructed = "INVALID";
      reasonCode = completionError.code;
    } else {
      try {
      const patchValue = parseProviderJson(completion.content_bytes);
      const irBytes = patchIrBytes(patchValue);
      compilePatchIrV2(irBytes, loadAcceptedCompilerProfile(cell.task_id));
      const expectedNormalizedResponse = buildNormalizedProviderResponse({
        responseId: `P1-207-${cell.cell_id}-${sha256(response.bytes).slice(0, 16)}`,
        taskId: cell.task_id,
        patchIrBytes: irBytes,
      });
      const artifacts = readExecutionArtifacts(root, cell);
      assert(artifacts["provider-response.json"].equals(expectedNormalizedResponse),
        "EXECUTION_BINDING_INVALID", "execution input differs from independently normalized completion content");
      const executionManifest = parseExactJsonBytes(artifacts["execution-spine.json"], {
        label: `${cell.cell_id} execution manifest`,
        canonical: true,
      });
      assert(executionManifest.run_id === `P1-207-${mode}-${cell.cell_id}`,
        "EXECUTION_BINDING_INVALID", `${cell.cell_id} execution run identity drifted`);
      reexecution = independentlyReexecute(cell, artifacts, executionManifest);
      const executionManifestIdentity = {
        path: `${prefix}/execution/execution-spine.json`,
        ...bytesIdentity(artifacts["execution-spine.json"]),
      };
      assert(isDeepStrictEqual(terminal.value.execution_manifest, executionManifestIdentity),
        "TERMINAL_BINDING_INVALID", "terminal execution manifest binding drifted");
      reconstructed = reexecution.verified_success ? "SUCCESSFUL" : "FAILED";
      reasonCode = reexecution.verified_success ? "VERIFIED_SUCCESS" : "ORACLE_OR_TEST_FAILED";
      } catch (error) {
      if (!(error instanceof EvaluationNonPass)
          && !["P1149NonPass", "PatchIrV2NonPass"].includes(error?.name)) throw error;
      reasonCode = error.code ?? error.reasonCode ?? "EXECUTION_NON_PASS";
      reconstructed = ["JSON_", "CHAT_", "PROVIDER_", "RESPONSE_", "IR_"]
        .some((prefix) => reasonCode.startsWith(prefix))
        ? "INVALID"
        : "FAILED";
      assert(terminal.value.execution_manifest === null || existsSync(join(root, terminal.value.execution_manifest.path)),
        "TERMINAL_BINDING_INVALID", "terminal binds an unavailable execution manifest");
      }
    }
  }
  assert(terminal.value.classification === reconstructed && terminal.value.reason_code === reasonCode,
    "WORKER_CLASSIFICATION_DRIFT", `${cell.cell_id} Worker classification differs from reconstruction`, {
      observed: terminal.value.classification,
      reconstructed,
      observed_reason: terminal.value.reason_code,
      reconstructed_reason: reasonCode,
    });
  const expectedProviderCount = mode === "FORMAL" ? 1 : 0;
  assert(terminal.value.provider_request_count === expectedProviderCount
      && requestReceipt.value.provider_request === (mode === "FORMAL")
      && requestReceipt.value.effect_authorized === (mode === "FORMAL"),
  "EFFECT_ACCOUNTING_INVALID", `${cell.cell_id} effect accounting drifted`);
  return {
    ordinal: cell.ordinal,
    cell_id: cell.cell_id,
    task_id: cell.task_id,
    profile_id: cell.profile_id,
    repetition_id: cell.repetition_id,
    classification: reconstructed,
    reason_code: reasonCode,
    request: bytesIdentity(request.bytes),
    response_id: providerResponseId,
    usage,
    independent_reexecution: reexecution,
  };
}

function validateFormalDiagnostic(root, plan) {
  const prefix = "diagnostic";
  const request = readExactJson(root, `${prefix}/request.json`, "diagnostic request");
  exactKeys(request.value, ["messages", "model"], "diagnostic request");
  assert(request.value.model === plan.model
      && isDeepStrictEqual(request.value.messages, [{
        role: "user",
        content: "Reply with exactly the word READY.",
      }]),
  "DIAGNOSTIC_REQUEST_INVALID", "diagnostic request is not the frozen minimal shape");
  const requestReceipt = readExactJson(root, `${prefix}/request-receipt.json`, "diagnostic request receipt");
  exactKeys(requestReceipt.value, REQUEST_RECEIPT_KEYS, "diagnostic request receipt");
  const requestIdentity = validateIdentity(root, requestReceipt.value.request, "diagnostic request");
  const requestReceiptIdentity = { path: `${prefix}/request-receipt.json`, ...bytesIdentity(requestReceipt.bytes) };
  const gate = validateIdentity(root, requestReceipt.value.preformal_gate, "diagnostic preformal Gate");
  assert(requestIdentity.path === request.path
      && gate.identity.path === "PREFORMAL_GATE_RECEIPT.json"
      && requestReceipt.value.cell_id === "diagnostic-001"
      && requestReceipt.value.task_id === TASK_ID
      && requestReceipt.value.profile_id === "DIAGNOSTIC"
      && requestReceipt.value.repetition_id === 0
      && requestReceipt.value.endpoint === plan.endpoint
      && requestReceipt.value.model === plan.model
      && requestReceipt.value.request_sequence === 1
      && requestReceipt.value.effect_authorized === true
      && requestReceipt.value.provider_request === true
      && requestReceipt.value.automatic_retry === false,
  "DIAGNOSTIC_REQUEST_INVALID", "diagnostic request receipt drifted");

  const transport = readExactJson(root, `${prefix}/transport-receipt.json`, "diagnostic transport receipt");
  exactKeys(transport.value, TRANSPORT_RECEIPT_KEYS, "diagnostic transport receipt");
  assert(transport.value.schema_version === "p1-207-transport-receipt/v1"
      && transport.value.execution_id === requestReceipt.value.execution_id
      && transport.value.cell_id === "diagnostic-001"
      && isDeepStrictEqual(transport.value.request_receipt, requestReceiptIdentity)
      && transport.value.transport_status === "RECEIVED"
      && transport.value.reason_code === "NONE"
      && transport.value.http_status >= 200
      && transport.value.http_status < 300
      && transport.value.peer_address === "127.0.0.1"
      && transport.value.peer_port === 8787
      && transport.value.response !== null
      && transport.value.provider_request === true
      && transport.value.automatic_retry === false,
  "DIAGNOSTIC_TRANSPORT_INVALID", "diagnostic transport did not produce one strict loopback 2xx response");
  const response = validateIdentity(root, transport.value.response, "diagnostic raw response");
  assert(response.identity.path === `${prefix}/response.raw`,
    "DIAGNOSTIC_RESPONSE_INVALID", "diagnostic raw response path drifted");
  const completion = extractCompletion(response.bytes);
  assert(completion.content_bytes.toString("utf8").trim() === "READY",
    "DIAGNOSTIC_CONTENT_INVALID", "diagnostic completion is not exactly READY after trimming");

  const responseReceipt = readExactJson(root, `${prefix}/response-receipt.json`, "diagnostic response receipt");
  exactKeys(responseReceipt.value, RESPONSE_RECEIPT_KEYS, "diagnostic response receipt");
  const responseReceiptIdentity = { path: `${prefix}/response-receipt.json`, ...bytesIdentity(responseReceipt.bytes) };
  assert(responseReceipt.value.execution_id === requestReceipt.value.execution_id
      && responseReceipt.value.cell_id === "diagnostic-001"
      && isDeepStrictEqual(responseReceipt.value.request_receipt, requestReceiptIdentity)
      && isDeepStrictEqual(responseReceipt.value.response, transport.value.response)
      && responseReceipt.value.http_status === transport.value.http_status
      && responseReceipt.value.peer_address === "127.0.0.1"
      && responseReceipt.value.peer_port === 8787
      && responseReceipt.value.response_id === completion.response_id
      && isDeepStrictEqual(responseReceipt.value.usage, completion.usage)
      && responseReceipt.value.completion_status === "STRICT_DIAGNOSTIC_COMPLETION"
      && responseReceipt.value.provider_request === true
      && responseReceipt.value.automatic_retry === false,
  "DIAGNOSTIC_RESPONSE_INVALID", "diagnostic response receipt differs from raw bytes");

  const terminal = readExactJson(root, `${prefix}/terminal.json`, "diagnostic terminal");
  exactKeys(terminal.value, TERMINAL_KEYS, "diagnostic terminal");
  assert(terminal.value.execution_id === requestReceipt.value.execution_id
      && terminal.value.cell_id === "diagnostic-001"
      && terminal.value.task_id === TASK_ID
      && isDeepStrictEqual(terminal.value.request_receipt, requestReceiptIdentity)
      && isDeepStrictEqual(terminal.value.response_receipt, responseReceiptIdentity)
      && terminal.value.execution_manifest === null
      && terminal.value.classification === "SUCCESSFUL"
      && terminal.value.reason_code === "STRICT_DIAGNOSTIC_COMPLETION"
      && terminal.value.provider_request_count === 1
      && terminal.value.automatic_retries === 0,
  "DIAGNOSTIC_TERMINAL_INVALID", "diagnostic terminal closure drifted");
  return {
    request: { path: `${prefix}/request.json`, ...bytesIdentity(request.bytes) },
    response: transport.value.response,
    terminal: { path: `${prefix}/terminal.json`, ...bytesIdentity(terminal.bytes) },
    usage: completion.usage,
  };
}

function wilson(successes, total, z = 1.959963984540054) {
  if (total === 0) return { lower: null, upper: null };
  const p = successes / total;
  const denominator = 1 + (z * z) / total;
  const center = (p + (z * z) / (2 * total)) / denominator;
  const margin = (z * Math.sqrt((p * (1 - p) + (z * z) / (4 * total)) / total)) / denominator;
  return { lower: center - margin, upper: center + margin };
}

function buildReport({
  root,
  plan,
  mode,
  cells,
  manifestIdentity,
  runReceiptIdentity,
  environment,
  environmentIdentity,
  configuration,
  configurationIdentity,
  acceptedP1129ControlIdentity,
  postformalFinalizerSource,
  diagnostic,
}) {
  const successful = cells.filter((cell) => cell.classification === "SUCCESSFUL").length;
  const failed = cells.filter((cell) => cell.classification === "FAILED").length;
  const invalid = cells.filter((cell) => cell.classification === "INVALID").length;
  const excluded = cells.filter((cell) => cell.classification === "EXCLUDED").length;
  const promptTokens = cells.reduce((sum, cell) => sum + (cell.usage?.prompt_tokens ?? 0), 0)
    + (diagnostic?.usage?.prompt_tokens ?? 0);
  const completionTokens = cells.reduce((sum, cell) => sum + (cell.usage?.completion_tokens ?? 0), 0)
    + (diagnostic?.usage?.completion_tokens ?? 0);
  const failureTaxonomy = {};
  for (const cell of cells.filter((entry) => entry.classification !== "SUCCESSFUL")) {
    failureTaxonomy[cell.reason_code] = (failureTaxonomy[cell.reason_code] ?? 0) + 1;
  }
  const denominator = cells.length;
  assert(denominator === 36 && successful + failed + invalid + excluded === denominator,
    "TAXONOMY_NOT_CLOSED", "independent taxonomy does not close to 36");
  const vtsr = successful / denominator;
  const report = {
    schema_version: mode === "FORMAL"
      ? "p1-207-reproducible-baseline-report/v1"
      : "p1-207-synthetic-rehearsal-report/v1",
    artifact_type: mode === "FORMAL" ? "REPRODUCIBLE_BASELINE_REPORT" : "SYNTHETIC_REHEARSAL_ONLY",
    claim_boundary: plan.claim_boundary,
    research_question: "Can the accepted canonical P1 adapter and execution spine produce independently verified outcomes under one fixed 36-cell cooperative-local matrix?",
    falsifiable_hypothesis: "All 36 scheduled cells are retained and independently reconstructed; VTSR and failures equal the frozen raw Evidence rather than Worker success claims.",
    dataset: {
      task_count: 6,
      task_ids: ACCEPTED_TASK_IDS,
      accepted_inputs: plan.accepted_inputs,
    },
    source_and_environment: {
      source_snapshot: environment.repository,
      runtime: {
        node: environment.node,
        platform: environment.platform,
        architecture: environment.architecture,
      },
      environment_receipt: environmentIdentity,
      configuration_receipt: configurationIdentity,
      evidence_manifest: manifestIdentity,
      run_receipt: runReceiptIdentity,
      accepted_p1_129_control: acceptedP1129ControlIdentity,
      ...(mode === "FORMAL" ? { postformal_finalizer_source: postformalFinalizerSource } : {}),
      diagnostic,
      evidence_root: root,
    },
    configurations: {
      endpoint: plan.endpoint,
      model: plan.model,
      adapters: ADAPTER_IDS,
      profiles: PROFILE_IDS,
      repetitions_per_adapter: 2,
      diagnostic_requests_max: configuration.diagnostic_requests_max,
      formal_requests_exact: configuration.formal_requests_exact,
      provider_requests_max: configuration.provider_requests_max,
      automatic_retries: configuration.automatic_retry_max,
    },
    evaluator: {
      schema_version: "p1-207-independent-evaluator/v1",
      worker_success_fields_trusted: false,
      raw_evidence_only_reconstruction: true,
      accepted_spine_reexecution: true,
    },
    metric: {
      primary: "VERIFIED_TASK_SUCCESS_RATE",
      denominator,
      numerator: successful,
      value: vtsr,
      confidence_interval_95_wilson: wilson(successful, denominator),
    },
    raw_results: cells,
    aggregate_results: { successful, failed, invalid, excluded, denominator },
    usage_and_cost: {
      prompt_tokens: promptTokens,
      completion_tokens: completionTokens,
      total_tokens: promptTokens + completionTokens,
      currency: "USD",
      authorized_maximum: 25,
      actual_monetary_cost: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
      cost_per_verified_success: successful === 0 ? null : "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
    },
    failure_taxonomy: failureTaxonomy,
    effect_size: "NOT_ESTIMATED_NO_PREDECLARED_SUPERIORITY_COMPARISON",
    reproduction: {
      command: `node evaluation-harness/evaluator/p1-207-minimum-cooperative-baseline/evaluate.mjs ${root}`,
      generated_report_used_as_input: false,
    },
    conclusion: mode === "FORMAL"
      ? `The cooperative-local baseline retained 36/36 cells and independently reconstructed VTSR=${vtsr}.`
      : "The production-equivalent offline rehearsal retained and reconstructed all 36 synthetic cells.",
    limitations: [
      "No hostile-principal, trusted-clock, unrewritable-history, strong-isolation, production, remote, public, P2 or P3 claim.",
      "Gateway upstream provenance and actual monetary cost are not independently verified.",
      "The fixed six-task dataset is too small for a model-superiority claim.",
    ],
    decision: mode === "FORMAL"
      ? "ACCEPT_RESEARCH_ARTIFACT_IF_ALL_TASK_GATE_REVIEWS_PASS"
      : "ELIGIBLE_FOR_INDEPENDENT_PREFORMAL_REVIEW_ONLY",
    stop_or_continue_rationale: mode === "FORMAL"
      ? "Stop at the P1-207 Task Gate; P1 capability credit requires independent reviews, exact integration and canonical verification."
      : "Continue only after fresh CTO, Security and Quality preformal PASS on the exact candidate and Evidence.",
  };
  return { report, bytes: canonicalBytes(report) };
}

export function evaluateEvidence(evidenceRoot) {
  const root = safeRealDirectory(resolve(evidenceRoot), "P1-207 Evidence root");
  const manifestRecord = readExactJson(root, "EVIDENCE_MANIFEST.json", "P1-207 Evidence manifest");
  const manifest = manifestRecord.value;
  assert(isDeepStrictEqual(manifest.excluded_paths, [...EXPECTED_MANIFEST_EXCLUSIONS].sort()),
    "MANIFEST_EXCLUSION_DRIFT", "Evidence manifest exclusion set is not the frozen closed set");
  const verifiedManifest = verifyClosedManifest(root, manifest, {
    exclude: manifest.excluded_paths,
  });
  assert(verifiedManifest.status === "PASS", "MANIFEST_NON_PASS", "closed Evidence manifest did not verify");
  const planRecord = readExactJson(root, "plan/FORMAL_PLAN.json", "formal plan");
  const plan = validatePlan(planRecord.value);
  const runRecord = readExactJson(root, "RUN_RECEIPT.json", "run receipt");
  exactKeys(runRecord.value, RUN_RECEIPT_KEYS, "run receipt");
  const mode = runRecord.value.diagnostic?.status === "NOT_APPLICABLE_PREFORMAL"
    ? "SYNTHETIC"
    : "FORMAL";
  const environmentRecord = readExactJson(root, "ENVIRONMENT_RECEIPT.json", "environment receipt");
  const configurationRecord = readExactJson(root, "CONFIGURATION_RECEIPT.json", "configuration receipt");
  exactKeys(environmentRecord.value, ENVIRONMENT_KEYS, "environment receipt");
  exactKeys(configurationRecord.value, CONFIGURATION_KEYS, "configuration receipt");
  const currentRepository = currentRepositoryIdentity();
  assert(currentRepository.dirty === false,
    "POSTFORMAL_FINALIZER_SOURCE_INVALID", "postformal finalizer source must be one clean committed candidate");
  const transitiveControl = mode === "FORMAL"
    ? resolvePostformalAcceptedControlBinding(root)
    : null;
  const expectedExecutionRepository = mode === "FORMAL"
    ? { ...transitiveControl.execution_candidate, dirty: false }
    : currentRepository;
  assert(environmentRecord.value.task_id === plan.task_id
      && environmentRecord.value.endpoint === plan.endpoint
      && environmentRecord.value.model === plan.model
      && isDeepStrictEqual(environmentRecord.value.accepted_inputs, plan.accepted_inputs)
      && isDeepStrictEqual(environmentRecord.value.external_effects, FALSE_EFFECTS)
      && environmentRecord.value.repository?.dirty === false
      && /^[0-9a-f]{40}$/.test(environmentRecord.value.repository?.commit ?? "")
      && /^[0-9a-f]{40}$/.test(environmentRecord.value.repository?.tree ?? "")
      && isDeepStrictEqual(environmentRecord.value.repository, expectedExecutionRepository),
  "ENVIRONMENT_BINDING_INVALID", "environment receipt does not bind the plan and exact execution source");
  validateRepositoryIdentity(environmentRecord.value.dataset_manifest, "accepted P1-035 dataset manifest");
  assert(configurationRecord.value.task_id === plan.task_id
      && configurationRecord.value.route_id === plan.route_id
      && configurationRecord.value.claim_boundary === plan.claim_boundary
      && configurationRecord.value.denominator === 36
      && configurationRecord.value.diagnostic_requests_max === 1
      && configurationRecord.value.formal_requests_exact === 36
      && configurationRecord.value.provider_requests_max === 37
      && configurationRecord.value.automatic_retry_max === 0
      && configurationRecord.value.endpoint === plan.endpoint
      && configurationRecord.value.model === plan.model
      && configurationRecord.value.secret_entry === "OPERATOR_OWNED_NO_ECHO_STDIN_ONCE"
      && isDeepStrictEqual(configurationRecord.value.manifest_exclusions, EXPECTED_MANIFEST_EXCLUSIONS)
      && isDeepStrictEqual(configurationRecord.value.external_effects, FALSE_EFFECTS),
  "CONFIGURATION_BINDING_INVALID", "configuration receipt differs from the Founder profile");
  const acceptedP1129ControlIdentity = validateAcceptedP1129Control(
    mode === "FORMAL" ? transitiveControl.control_root : root,
    plan,
    mode === "FORMAL" ? transitiveControl.binding_chain : null,
  );
  assert(runRecord.value.schema_version === "p1-207-run-receipt/v1"
      && runRecord.value.status === "PASS"
      && runRecord.value.task_id === plan.task_id
      && runRecord.value.denominator === 36
      && runRecord.value.scheduled_cells === 36
      && runRecord.value.terminal_cells === 36
      && runRecord.value.automatic_retries === 0
      && runRecord.value.report_rebuild_required === true,
  "RUN_RECEIPT_INVALID", "run receipt lifecycle or count drifted");
  const expectedEffects = mode === "FORMAL" ? FORMAL_EFFECTS : FALSE_EFFECTS;
  assert(isDeepStrictEqual(runRecord.value.external_effects, expectedEffects),
    "EFFECT_ACCOUNTING_INVALID", "run receipt external effects drifted");
  if (mode === "SYNTHETIC") {
    exactKeys(runRecord.value.diagnostic, ["provider_requests", "status"], "synthetic diagnostic receipt");
    assert(runRecord.value.diagnostic.status === "NOT_APPLICABLE_PREFORMAL"
        && runRecord.value.diagnostic.provider_requests === 0,
    "RUN_RECEIPT_INVALID", "synthetic diagnostic accounting drifted");
  } else {
    exactKeys(runRecord.value.diagnostic, ["provider_requests", "reason_code", "status"], "formal diagnostic receipt");
    assert(runRecord.value.diagnostic.status === "PASS"
        && runRecord.value.diagnostic.reason_code === "STRICT_DIAGNOSTIC_COMPLETION"
        && runRecord.value.diagnostic.provider_requests === 1,
    "RUN_RECEIPT_INVALID", "formal diagnostic Gate did not PASS exactly once");
  }
  const diagnostic = mode === "FORMAL" ? validateFormalDiagnostic(root, plan) : null;
  const cells = plan.cells.map((cell) => evaluateCell(root, plan, cell, mode));
  const taxonomy = {
    successful: cells.filter((cell) => cell.classification === "SUCCESSFUL").length,
    failed: cells.filter((cell) => cell.classification === "FAILED").length,
    invalid: cells.filter((cell) => cell.classification === "INVALID").length,
    excluded: cells.filter((cell) => cell.classification === "EXCLUDED").length,
    denominator: 36,
  };
  assert(isDeepStrictEqual(runRecord.value.taxonomy, taxonomy),
    "WORKER_TAXONOMY_DRIFT", "run receipt taxonomy differs from independent reconstruction");
  const providerRequestsExpected = mode === "FORMAL" ? 36 : 0;
  assert(runRecord.value.formal_provider_requests === providerRequestsExpected
      && runRecord.value.provider_requests === providerRequestsExpected
        + runRecord.value.diagnostic_provider_requests
      && runRecord.value.secret_reads === (mode === "FORMAL" ? 1 : 0)
      && runRecord.value.secret_persisted === false,
  "EFFECT_ACCOUNTING_INVALID", "run effect accounting is inconsistent");
  const manifestIdentity = { path: "EVIDENCE_MANIFEST.json", ...bytesIdentity(manifestRecord.bytes) };
  const runReceiptIdentity = { path: "RUN_RECEIPT.json", ...bytesIdentity(runRecord.bytes) };
  const environmentIdentity = { path: "ENVIRONMENT_RECEIPT.json", ...bytesIdentity(environmentRecord.bytes) };
  const configurationIdentity = { path: "CONFIGURATION_RECEIPT.json", ...bytesIdentity(configurationRecord.bytes) };
  const { report, bytes: reportBytes } = buildReport({
    root,
    plan,
    mode,
    cells,
    manifestIdentity,
    runReceiptIdentity,
    environment: environmentRecord.value,
    environmentIdentity,
    configuration: configurationRecord.value,
    configurationIdentity,
    acceptedP1129ControlIdentity,
    postformalFinalizerSource: mode === "FORMAL" ? currentRepository : null,
    diagnostic,
  });
  return {
    schema_version: mode === "FORMAL"
      ? "p1-207-postformal-independent-evaluator-receipt/v1"
      : "p1-207-independent-evaluator-receipt/v1",
    status: "PASS",
    mode,
    task_id: plan.task_id,
    denominator: 36,
    taxonomy,
    vtsr: taxonomy.successful / 36,
    closed_inventory_entries: manifest.entry_count,
    false_accepts: 0,
    raw_evidence_only_reconstruction: true,
    generated_report_used_as_input: false,
    worker_success_fields_trusted: false,
    accepted_spine_reexecutions: taxonomy.successful,
    accepted_p1_129_control: acceptedP1129ControlIdentity,
    ...(mode === "FORMAL" ? {
      execution_source: environmentRecord.value.repository,
      postformal_finalizer_source: currentRepository,
    } : {}),
    evidence_manifest: manifestIdentity,
    report,
    report_identity: bytesIdentity(reportBytes),
    external_effects: mode === "FORMAL" ? FORMAL_EFFECTS : FALSE_EFFECTS,
  };
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  try {
    assert(process.argv.length === 3 || process.argv.length === 5,
      "CLI_USAGE_INVALID", "usage: evaluate.mjs EVIDENCE_ROOT [--write-report REPORT_PATH]");
    const receipt = evaluateEvidence(process.argv[2]);
    if (process.argv.length === 5) {
      assert(process.argv[3] === "--write-report", "CLI_USAGE_INVALID", "unknown evaluator option");
      const reportPath = resolve(process.argv[4]);
      assert(!existsSync(reportPath), "REPORT_PREEXISTS", "report path must be create-once");
      writeFileSync(reportPath, canonicalBytes(receipt.report), { flag: "wx", mode: 0o600 });
    }
    process.stdout.write(`${canonicalJson(receipt)}\n`);
  } catch (error) {
    const failure = {
      schema_version: "p1-207-independent-evaluator-failure/v1",
      status: "NON_PASS",
      reason_code: error.code ?? error.reasonCode ?? "UNEXPECTED_EVALUATOR_ERROR",
      message: error.message,
    };
    process.stderr.write(`${canonicalJson(failure)}\n`);
    process.exitCode = 1;
  }
}

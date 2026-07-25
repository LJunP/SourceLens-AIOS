#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  P117QualityNonPass,
  assert,
  identityOf,
  parseCanonicalJson,
  parseFrozenJson,
  readBoundFile,
} from "../../validators/p1-117-clean-room-empirical-baseline/core.mjs";
import {
  validatePreregistrationBundle,
} from "../../validators/p1-117-clean-room-empirical-baseline/preflight.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPOSITORY_ROOT = resolve(HERE, "../../..");
export const DEFAULT_FIXTURE_ROOT = resolve(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-117-clean-room-empirical-baseline",
);

function bindingForAbsolute(repositoryRoot, path) {
  const absolute = resolve(path);
  const rel = relative(repositoryRoot, absolute);
  assert(
    rel !== ""
      && rel !== ".."
      && !rel.startsWith(`..${sep}`)
      && !isAbsolute(rel),
    "PREREGISTRATION_IDENTITY_MISMATCH",
    "preregistration path must be a repository artifact",
  );
  const bytes = readFileSync(absolute);
  return {
    path: rel.split(sep).join("/"),
    ...identityOf(bytes),
  };
}

function loadFrozenArtifact(repositoryRoot, preregistration, name, reasonCode) {
  const binding = preregistration.frozen_artifacts?.[name];
  assert(binding !== undefined, reasonCode, `missing frozen artifact: ${name}`);
  const file = readBoundFile(repositoryRoot, binding, reasonCode);
  return {
    binding: structuredClone(binding),
    value: parseFrozenJson(file.bytes, reasonCode),
  };
}

export async function offlinePreflight({
  repositoryRoot = REPOSITORY_ROOT,
  preregistrationBinding,
  executableReceipt,
} = {}) {
  assert(
    resolve(repositoryRoot) === REPOSITORY_ROOT,
    "REPOSITORY_ROOT_INVALID",
    "P1-117 repository root drifted",
  );
  assert(
    preregistrationBinding !== null
      && typeof preregistrationBinding === "object"
      && executableReceipt !== null
      && typeof executableReceipt === "object",
    "OFFLINE_PREFLIGHT_INPUT_MISSING",
    "exact preregistration binding and executable freeze receipt are required",
  );
  const quality = validatePreregistrationBundle({
    repositoryRoot,
    preregistrationBinding,
    executableReceipt,
  });
  const formal = loadFrozenArtifact(
    repositoryRoot,
    quality.preregistration,
    "formal_run_contract",
    "FORMAL_RUN_CONTRACT_IDENTITY_MISMATCH",
  );
  const negative = loadFrozenArtifact(
    repositoryRoot,
    quality.preregistration,
    "negative_cases",
    "NEGATIVE_CASE_IDENTITY_MISMATCH",
  );
  const p2 = loadFrozenArtifact(
    repositoryRoot,
    quality.preregistration,
    "p2_context_preregistration",
    "P2_PREREGISTRATION_IDENTITY_MISMATCH",
  );
  assert(
    quality.matrix.schedule.length === 36
      && quality.matrix.predeclared_aggregate_budget.provider_requests_exact === 36
      && quality.matrix.predeclared_aggregate_budget.automatic_retries === 0,
    "OFFLINE_PREFLIGHT_MATRIX_INVALID",
    "formal matrix is not the exact frozen 36-run schedule",
  );
  return {
    schema_version: "p1-117-offline-preflight/v1",
    status: "PASS",
    preregistration: structuredClone(preregistrationBinding),
    matrix_plan: structuredClone(quality.preregistration.frozen_artifacts.matrix_plan),
    executable_freeze_receipt: {
      schema_version: executableReceipt.schema_version,
      status: executableReceipt.status,
      artifact_count: executableReceipt.artifacts.length,
    },
    frozen_inputs: {
      formal_run_contract: formal.binding,
      negative_cases: negative.binding,
      p2_context_engine_preregistration: p2.binding,
    },
    schedule_count: 36,
    provider_requests: 0,
    secret_reads: 0,
    network_connections: 0,
    automatic_retries: 0,
    matrix: quality.matrix,
    formal_contract: formal.value,
  };
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(
      ["--preregistration", "--executable-receipt"].includes(key)
        && typeof value === "string"
        && !Object.hasOwn(args, key),
      "CLI_ARGUMENT_MISMATCH",
      "preflight CLI arguments are invalid",
    );
    args[key] = value;
  }
  assert(
    typeof args["--preregistration"] === "string"
      && typeof args["--executable-receipt"] === "string",
    "CLI_ARGUMENT_MISMATCH",
    "preflight requires preregistration and executable receipt paths",
  );
  return args;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const args = parseArgs(process.argv.slice(2));
    const preregistrationBinding = bindingForAbsolute(
      REPOSITORY_ROOT,
      args["--preregistration"],
    );
    const executableReceipt = parseCanonicalJson(
      readFileSync(resolve(args["--executable-receipt"])),
      "EXECUTABLE_FREEZE_RECEIPT_INVALID",
    );
    const receipt = await offlinePreflight({
      preregistrationBinding,
      executableReceipt,
    });
    process.stdout.write(`${JSON.stringify({
      status: receipt.status,
      scheduled_runs: receipt.schedule_count,
      provider_requests: 0,
      secret_reads: 0,
    })}\n`);
  } catch (error) {
    const reasonCode = error instanceof P117QualityNonPass
      ? error.reasonCode
      : error.code ?? "UNEXPECTED_PREFLIGHT_ERROR";
    process.stdout.write(`${JSON.stringify({
      status: "NON_PASS",
      reason_code: reasonCode,
      provider_requests: 0,
      secret_reads: 0,
    })}\n`);
    process.exitCode = 2;
  }
}

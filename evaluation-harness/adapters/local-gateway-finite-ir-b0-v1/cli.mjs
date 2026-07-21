#!/usr/bin/env node

import { existsSync } from "node:fs";
import { join } from "node:path";

import {
  AdapterError,
  ADAPTER_VERSION,
  buildRequestBody,
  PRODUCTION_ENDPOINT,
  submitProductionOnce,
  verifyFrozenRequest,
} from "./core.mjs";
import {
  assertOwnedProductionRunRoot,
  canonicalJsonBytes,
  createRunRoot,
  EvidenceError,
  productionRunRoot,
  writeCreateOnce,
} from "../../recording/local-gateway-finite-ir-b0-v1/evidence.mjs";

const SECRET_ENV = "P1_062_LOCAL_GATEWAY_API_KEY";
const PROXY_ENV = [
  "ALL_PROXY",
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "NO_PROXY",
  "all_proxy",
  "http_proxy",
  "https_proxy",
  "no_proxy",
];

function parseArguments() {
  const args = process.argv.slice(2);
  if (args.length !== 3 || args[1] !== "--run-id" || !["build", "submit"].includes(args[0])) {
    throw new AdapterError("CLI_ARGUMENTS_INVALID");
  }
  return Object.freeze({ command: args[0], runId: args[2] });
}

function safeOutput(value) {
  process.stdout.write(canonicalJsonBytes(value));
}

function build(runId) {
  if (process.env[SECRET_ENV] !== undefined) throw new AdapterError("CREDENTIAL_PRESENT_DURING_BUILD");
  const root = productionRunRoot(runId);
  const identity = createRunRoot(root);
  const request = buildRequestBody();
  const requestIdentity = writeCreateOnce(join(root, "request-body.json"), request.bytes);
  const manifestIdentity = writeCreateOnce(
    join(root, "egress-manifest.json"),
    canonicalJsonBytes(request.egress_manifest),
  );
  const freeze = {
    schema: "P1-062-REQUEST-FREEZE/1",
    adapter_version: ADAPTER_VERSION,
    run_id: runId,
    root_identity: { device: String(identity.dev), inode: String(identity.ino) },
    endpoint: {
      scheme: "http",
      host: PRODUCTION_ENDPOINT.host,
      port: PRODUCTION_ENDPOINT.port,
      path: PRODUCTION_ENDPOINT.path,
    },
    requested_model: "gpt-5.6-luna",
    request_body: requestIdentity,
    egress_manifest: manifestIdentity,
    source_bearing_submission_max: 1,
    automatic_retry_max: 0,
  };
  const freezeIdentity = writeCreateOnce(join(root, "request-freeze.json"), canonicalJsonBytes(freeze));
  safeOutput({
    schema: "P1-062-CLI-RESULT/1",
    command: "build",
    status: "FROZEN",
    run_id: runId,
    request_body: requestIdentity,
    egress_manifest: manifestIdentity,
    request_freeze: freezeIdentity,
  });
}

async function submit(runId) {
  for (const name of PROXY_ENV) {
    if (process.env[name]) throw new AdapterError("PROXY_ENV_FORBIDDEN");
  }
  const { root } = assertOwnedProductionRunRoot(runId);
  verifyFrozenRequest(root);
  for (const leaf of ["transport-receipt.json", "raw-response.json"]) {
    if (existsSync(join(root, leaf))) throw new AdapterError("SUBMISSION_ALREADY_TERMINAL");
  }
  let secret = process.env[SECRET_ENV];
  delete process.env[SECRET_ENV];
  if (typeof secret !== "string") throw new AdapterError("CREDENTIAL_MISSING");
  try {
    const result = await submitProductionOnce({ runId, secret });
    safeOutput({
      schema: "P1-062-CLI-RESULT/1",
      command: "submit",
      status: "TERMINAL",
      run_id: runId,
      terminal_code: result.code,
      source_bearing_submission_count: result.sent ? 1 : 0,
      http_status: result.status,
      response_retained: result.bodyIdentity !== null,
    });
    if (result.code !== "RESPONSE_RETAINED") process.exitCode = 20;
  } finally {
    secret = "";
    delete process.env[SECRET_ENV];
  }
}

try {
  const { command, runId } = parseArguments();
  if (command === "build") build(runId);
  else await submit(runId);
} catch (error) {
  delete process.env[SECRET_ENV];
  const code = error instanceof AdapterError || error instanceof EvidenceError ? error.code : "CLI_FAILURE";
  safeOutput({ schema: "P1-062-CLI-RESULT/1", status: "FAILED_SAFE", reason_code: code });
  process.exitCode = 1;
}

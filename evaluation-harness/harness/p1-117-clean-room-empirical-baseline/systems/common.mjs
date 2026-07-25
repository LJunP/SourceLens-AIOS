import {
  assert,
  canonicalBytes,
  canonicalJson,
  exactKeys,
} from "../../p1-097-minimal-documented/core.mjs";
import {
  buildChatCompletionsRequest,
  validateChatCompletionsRequest,
} from "../../../validators/p1-117-clean-room-empirical-baseline/disclosure.mjs";
import { REPOSITORY_ROOT } from "../preflight.mjs";

const CONFIGURATION_KEYS = Object.freeze([
  "schema_version",
  "configuration_id",
  "run_id",
  "task_id",
  "system",
  "variant",
  "model_ref",
  "finite_operation_ids",
  "disclosure_mode",
  "response_schema",
  "provider_requests_exact",
  "automatic_retries",
  "input_tokens_reserved",
  "max_output_tokens",
  "temperature",
  "endpoint_policy",
  "external_effects",
]);
const ENDPOINT_POLICY = Object.freeze({
  scheme: "http",
  host: "127.0.0.1",
  port: 8787,
  path: "/v1/chat/completions",
  follow_redirects: false,
  use_proxy: false,
  dns_resolution: false,
  fallback_endpoint_allowed: false,
});
const EXTERNAL_EFFECTS = Object.freeze({
  network: true,
  provider: true,
  secret: true,
  remote: false,
  production: false,
  public: false,
});
const DISCLOSURE_MODES = Object.freeze({
  B0: "ISSUE_ONLY_SAFE_PROBLEM_STATEMENT_AND_FINITE_OPERATIONS",
  B1: "SAFE_PROBLEM_OPERATIONS_AND_QUALITY_FROZEN_SAFE_TOOL_FACTS",
  B2: "SAFE_PROBLEM_OPERATIONS_AND_NONCONTENT_ACCEPTED_SCANNER_METRICS",
});

export function validateConfiguration(configuration, entry) {
  exactKeys(configuration, CONFIGURATION_KEYS, "P1-117 SystemConfiguration");
  exactKeys(configuration.response_schema, ["path", "sha256", "byte_length"], "response schema identity");
  assert(
    configuration.schema_version === "p1-117-system-configuration/v1"
      && configuration.configuration_id === `P1-117-CONFIG-${String(entry.slot).padStart(3, "0")}-${entry.run_id.split("-").slice(4).join("-")}`
      && configuration.run_id === entry.run_id
      && configuration.task_id === entry.task_id
      && configuration.system === entry.system
      && configuration.variant === entry.variant
      && configuration.model_ref === "gpt-5.6-luna"
      && canonicalJson(configuration.finite_operation_ids) === canonicalJson(entry.finite_operation_ids)
      && configuration.disclosure_mode === DISCLOSURE_MODES[entry.system]
      && canonicalJson(configuration.response_schema) === canonicalJson(entry.response_schema ?? configuration.response_schema)
      && configuration.provider_requests_exact === 1
      && configuration.automatic_retries === 0
      && configuration.input_tokens_reserved === 12000
      && configuration.max_output_tokens === 2048
      && configuration.temperature === (entry.variant === "A" ? 0 : 0.2)
      && canonicalJson(configuration.endpoint_policy) === canonicalJson(ENDPOINT_POLICY)
      && canonicalJson(configuration.external_effects) === canonicalJson(EXTERNAL_EFFECTS),
    "SYSTEM_CONFIGURATION_INVALID",
    `P1-117 configuration drifted for ${entry.run_id}`,
  );
  return configuration;
}

export function buildExactRequest({
  entry,
  configuration,
  disclosure,
  responseSchemaIdentity,
  scannerObservation = null,
}) {
  validateConfiguration(configuration, entry);
  assert(
    canonicalJson(configuration.response_schema) === canonicalJson(responseSchemaIdentity),
    "RESPONSE_SCHEMA_IDENTITY_MISMATCH",
    "configuration does not bind the exact Quality response schema",
  );
  const built = buildChatCompletionsRequest({
    entry,
    configuration,
    disclosure,
    responseSchemaIdentity,
    scannerObservation,
  });
  const bytes = canonicalBytes(built.body);
  validateChatCompletionsRequest({
    repositoryRoot: REPOSITORY_ROOT,
    requestBytes: bytes,
    entry,
    configuration,
    disclosure,
    responseSchemaIdentity,
  });
  return {
    body: built.body,
    bytes,
    payload_bytes: built.payloadBytes,
  };
}


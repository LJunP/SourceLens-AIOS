import { lstatSync, realpathSync } from "node:fs";
import { isAbsolute } from "node:path";

import {
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  exactKeys,
  parseCanonicalJsonBytes,
  sha256,
} from "../p1-149-accepted-execution-spine/core.mjs";

export {
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  exactKeys,
  parseCanonicalJsonBytes,
  sha256,
};

export const KERNEL_VERSION = "P1-165-FAIL-CLOSED-RESPONSE-ADMISSION/1";
export const TASK_ID =
  "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL";
export const MODEL_FAILURE_SCHEMA = "p1-165-model-failure/v1";
export const MODEL_FAILURE_REASON_CODE = "MODEL_OUTPUT_DECLINED";
export const RESPONSE_BYTES_MAX = 4 * 1024 * 1024;
export const FORMAL_PEER = "127.0.0.1:8787";
export const PROFILE_ORDER = Object.freeze([
  "B0_A",
  "B0_B",
  "B1_A",
  "B1_B",
  "B2_A",
  "B2_B",
]);
export const FALSE_EXTERNAL_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});

export function closedChildEnvironment(homeOverride = null) {
  const home = homeOverride ?? process.env.HOME;
  assertCritical(
    typeof home === "string"
      && isAbsolute(home)
      && !home.includes("\0"),
    "PATH_ESCAPE_REJECTED",
    "closed child HOME is unavailable",
  );
  const homeStat = lstatSync(home);
  assertCritical(
    homeStat.isDirectory()
      && !homeStat.isSymbolicLink()
      && homeStat.uid === process.getuid()
      && realpathSync(home) === home,
    "PATH_ESCAPE_REJECTED",
    "closed child HOME identity is unsafe",
  );
  const environment = {
    HOME: home,
    LANG: "C",
    LC_ALL: "C",
    PATH:
      "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    TZ: "UTC",
  };
  assertCritical(
    Object.keys(environment).sort().join(",")
      === "HOME,LANG,LC_ALL,PATH,TZ",
    "REQUEST_KEYSET_INVALID",
    "closed child environment key set drifted",
  );
  return environment;
}

export const CRITICAL_REASON_CODES = Object.freeze([
  "ACCOUNTING_MISMATCH",
  "CELL_IDENTITY_MISMATCH",
  "CLOSED_INVENTORY_DRIFT",
  "CONCURRENCY_LIMIT_EXCEEDED",
  "CONTEXT_KEYSET_INVALID",
  "CREATE_ONCE_FAILED",
  "DUPLICATE_JSON_KEY",
  "DUPLICATE_SLOT",
  "EARLY_CLOSE",
  "EVENT_ORDER_INVALID",
  "EVIDENCE_CROSS_BINDING_INVALID",
  "EVIDENCE_WRITER_STALL_DETECTED",
  "EVIDENCE_WRITE_FAILED",
  "EXTERNAL_EFFECT_FORBIDDEN",
  "HARDLINK_REJECTED",
  "HTTP_CHUNK_FRAMING_INVALID",
  "HTTP_CONTENT_LENGTH_MISMATCH",
  "HTTP_FRAMING_INCOMPLETE",
  "IDENTITY_MISMATCH",
  "MISSING_SLOT",
  "NON_LOOPBACK_PEER_FORBIDDEN",
  "NON_REGULAR_FILE_REJECTED",
  "OBSERVER_COMMAND_MISMATCH",
  "OBSERVER_EVIDENCE_FORGED",
  "OBSERVER_EVIDENCE_MISSING",
  "OBSERVER_FD_MISMATCH",
  "OBSERVER_KEYSET_INVALID",
  "OBSERVER_NON_PASS",
  "OBSERVER_PEER_MISMATCH",
  "OBSERVER_PID_MISMATCH",
  "OBSERVER_PORT_MISMATCH",
  "OBSERVER_STALL_DETECTED",
  "OBSERVER_STDERR_IDENTITY_MISMATCH",
  "OBSERVER_STDOUT_IDENTITY_MISMATCH",
  "OBSERVER_TIMESTAMP_INVALID",
  "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
  "ORDERED_IDENTITY_SET_INVALID",
  "PATH_ESCAPE_REJECTED",
  "PATH_MISSING",
  "POST_TERMINAL_BYTES",
  "RESPONSE_TOO_LARGE",
  "PROFILE_IDENTITY_MISMATCH",
  "PROGRESS_RECEIPT_MISSING",
  "PROVIDER_OUTPUT_USAGE_EXCEEDED",
  "PROVIDER_USAGE_INVALID",
  "REPETITION_IDENTITY_MISMATCH",
  "REQUEST_KEYSET_INVALID",
  "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
  "RESOURCE_LIMIT_EXCEEDED",
  "RESPONSE_TRUNCATED",
  "ROOT_PREEXISTS",
  "SECRET_REFLECTION_DETECTED",
  "SYMLINK_REJECTED",
  "TASK_IDENTITY_MISMATCH",
  "TERMINAL_EVENT_DUPLICATE",
  "TERMINAL_EVENT_MISSING",
  "TRANSPORT_KEYSET_INVALID",
  "WORKER_STALL_DETECTED",
]);

const CRITICAL_REASON_SET = new Set(CRITICAL_REASON_CODES);
const JOIN_KEYS = Object.freeze([
  "execution_id",
  "cell_id",
  "task_id",
  "profile_id",
  "repetition_id",
]);
const IDENTITY_KEYS = Object.freeze(["byte_length", "sha256"]);
const POLICY_KEYS = Object.freeze([
  "expected_peer",
  "mode",
  "output_tokens_max",
  "response_bytes_max",
]);
const USAGE_KEYS = Object.freeze([
  "input_tokens",
  "join",
  "output_tokens",
  "response_identity",
  "schema_version",
  "status",
  "total_tokens",
]);

export class AdmissionNonPass extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = "AdmissionNonPass";
    this.code = code;
    this.severity = "CRITICAL";
    this.details = details;
  }
}

export function failCritical(code, message, details = null) {
  if (!CRITICAL_REASON_SET.has(code)) {
    throw new Error(`unregistered critical reason code: ${code}`);
  }
  throw new AdmissionNonPass(code, message, details);
}

export function isCriticalReasonCode(value) {
  return typeof value === "string" && CRITICAL_REASON_SET.has(value);
}

export function assertCritical(condition, code, message, details = null) {
  if (!condition) failCritical(code, message, details);
}

function exactClosedKeys(
  value,
  keys,
  label,
  code = "EVIDENCE_CROSS_BINDING_INVALID",
) {
  try {
    exactKeys(value, keys, label);
  } catch (error) {
    failCritical(code, `${label} key set is not closed`, {
      cause: error?.code ?? code,
    });
  }
}

function isNonEmptyIdentifier(value) {
  return (
    typeof value === "string"
    && value.length > 0
    && value.length <= 160
    && /^[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(value)
  );
}

export function validateIdentity(value, label = "artifact identity") {
  exactClosedKeys(value, IDENTITY_KEYS, label, "IDENTITY_MISMATCH");
  assertCritical(
    Number.isSafeInteger(value.byte_length) && value.byte_length >= 0,
    "IDENTITY_MISMATCH",
    `${label} byte_length is invalid`,
  );
  assertCritical(
    typeof value.sha256 === "string" && /^[0-9a-f]{64}$/.test(value.sha256),
    "IDENTITY_MISMATCH",
    `${label} SHA-256 is invalid`,
  );
  return Object.freeze({
    byte_length: value.byte_length,
    sha256: value.sha256,
  });
}

export function validateJoin(value, label = "join") {
  exactClosedKeys(
    value,
    JOIN_KEYS,
    label,
    "EVIDENCE_CROSS_BINDING_INVALID",
  );
  assertCritical(
    isNonEmptyIdentifier(value.execution_id),
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${label}.execution_id is invalid`,
  );
  assertCritical(
    isNonEmptyIdentifier(value.cell_id),
    "CELL_IDENTITY_MISMATCH",
    `${label}.cell_id is invalid`,
  );
  assertCritical(
    isNonEmptyIdentifier(value.task_id),
    "TASK_IDENTITY_MISMATCH",
    `${label}.task_id is invalid`,
  );
  assertCritical(
    isNonEmptyIdentifier(value.profile_id),
    "PROFILE_IDENTITY_MISMATCH",
    `${label}.profile_id is invalid`,
  );
  assertCritical(
    isNonEmptyIdentifier(value.repetition_id),
    "REPETITION_IDENTITY_MISMATCH",
    `${label}.repetition_id is invalid`,
  );
  assertCritical(
    value.task_id === TASK_ID,
    "TASK_IDENTITY_MISMATCH",
    `${label}.task_id is not the active Task`,
  );
  assertCritical(
    PROFILE_ORDER.includes(value.profile_id),
    "PROFILE_IDENTITY_MISMATCH",
    `${label}.profile_id is outside the closed profile set`,
  );
  return Object.freeze(Object.fromEntries(JOIN_KEYS.map((key) => [key, value[key]])));
}

export function joinsEqual(left, right) {
  try {
    return canonicalJson(validateJoin(left)) === canonicalJson(validateJoin(right));
  } catch {
    return false;
  }
}

export function assertJoinEqual(left, right, label = "joined record") {
  const validatedLeft = validateJoin(left, `${label} expected join`);
  const validatedRight = validateJoin(right, `${label} observed join`);
  assertCritical(
    canonicalJson(validatedLeft) === canonicalJson(validatedRight),
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${label} join identity drifted`,
  );
  return validatedRight;
}

function validLoopbackPeer(value) {
  if (typeof value !== "string") return false;
  const match = /^127\.0\.0\.1:([1-9][0-9]{0,4})$/.exec(value);
  return match !== null && Number(match[1]) <= 65535;
}

export function validatePolicy(value, label = "admission policy") {
  exactClosedKeys(value, POLICY_KEYS, label, "TRANSPORT_KEYSET_INVALID");
  assertCritical(
    value.mode === "OWNED_CALIBRATION" || value.mode === "FORMAL_LOOPBACK",
    "TRANSPORT_KEYSET_INVALID",
    `${label}.mode is invalid`,
  );
  assertCritical(
    validLoopbackPeer(value.expected_peer),
    "NON_LOOPBACK_PEER_FORBIDDEN",
    `${label}.expected_peer is not exact IPv4 loopback`,
  );
  if (value.mode === "FORMAL_LOOPBACK") {
    assertCritical(
      value.expected_peer === FORMAL_PEER,
      "NON_LOOPBACK_PEER_FORBIDDEN",
      "formal policy peer is not the frozen loopback endpoint",
    );
  }
  assertCritical(
    Number.isSafeInteger(value.response_bytes_max)
      && value.response_bytes_max === RESPONSE_BYTES_MAX,
    "TRANSPORT_KEYSET_INVALID",
    `${label}.response_bytes_max is not the frozen cap`,
  );
  assertCritical(
    Number.isSafeInteger(value.output_tokens_max)
      && value.output_tokens_max === 2048,
    "TRANSPORT_KEYSET_INVALID",
    `${label}.output_tokens_max is not the frozen cap`,
  );
  return Object.freeze({
    mode: value.mode,
    expected_peer: value.expected_peer,
    response_bytes_max: value.response_bytes_max,
    output_tokens_max: value.output_tokens_max,
  });
}

function validateNullableTokenCount(value, label) {
  assertCritical(
    value === null || (Number.isSafeInteger(value) && value >= 0),
    "PROVIDER_USAGE_INVALID",
    `${label} must be null or a non-negative safe integer`,
  );
}

export function validateUsage(
  value,
  { join, responseIdentity, policy },
  label = "usage record",
) {
  exactClosedKeys(value, USAGE_KEYS, label, "PROVIDER_USAGE_INVALID");
  assertCritical(
    value.schema_version === "p1-165-provider-usage/v1",
    "PROVIDER_USAGE_INVALID",
    `${label}.schema_version is invalid`,
  );
  assertJoinEqual(join, value.join, label);
  const expectedIdentity = validateIdentity(responseIdentity, "expected response identity");
  const observedIdentity = validateIdentity(value.response_identity, `${label}.response_identity`);
  assertCritical(
    canonicalJson(observedIdentity) === canonicalJson(expectedIdentity),
    "IDENTITY_MISMATCH",
    `${label} is bound to different response bytes`,
  );
  const validatedPolicy = validatePolicy(policy);
  assertCritical(
    value.status === "UNKNOWN" || value.status === "OBSERVED",
    "PROVIDER_USAGE_INVALID",
    `${label}.status is invalid`,
  );
  validateNullableTokenCount(value.input_tokens, `${label}.input_tokens`);
  validateNullableTokenCount(value.output_tokens, `${label}.output_tokens`);
  validateNullableTokenCount(value.total_tokens, `${label}.total_tokens`);
  if (value.status === "UNKNOWN") {
    assertCritical(
      value.input_tokens === null
        && value.output_tokens === null
        && value.total_tokens === null,
      "PROVIDER_USAGE_INVALID",
      "UNKNOWN usage must not invent token counts",
    );
  } else {
    assertCritical(
      Number.isSafeInteger(value.input_tokens)
        && Number.isSafeInteger(value.output_tokens)
        && Number.isSafeInteger(value.total_tokens),
      "PROVIDER_USAGE_INVALID",
      "OBSERVED usage requires all token counts",
    );
    assertCritical(
      value.total_tokens === value.input_tokens + value.output_tokens,
      "PROVIDER_USAGE_INVALID",
      "OBSERVED usage total is inconsistent",
    );
    assertCritical(
      value.output_tokens <= validatedPolicy.output_tokens_max,
      "PROVIDER_OUTPUT_USAGE_EXCEEDED",
      "observed output token count exceeds the frozen cap",
    );
  }
  return Object.freeze({
    schema_version: value.schema_version,
    join: validateJoin(value.join),
    response_identity: observedIdentity,
    status: value.status,
    input_tokens: value.input_tokens,
    output_tokens: value.output_tokens,
    total_tokens: value.total_tokens,
  });
}

export function unknownUsage({ join, responseIdentity }) {
  return {
    schema_version: "p1-165-provider-usage/v1",
    join: validateJoin(join),
    response_identity: validateIdentity(responseIdentity),
    status: "UNKNOWN",
    input_tokens: null,
    output_tokens: null,
    total_tokens: null,
  };
}

export function observedUsage({
  join,
  responseIdentity,
  inputTokens,
  outputTokens,
}) {
  return {
    schema_version: "p1-165-provider-usage/v1",
    join: validateJoin(join),
    response_identity: validateIdentity(responseIdentity),
    status: "OBSERVED",
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    total_tokens: inputTokens + outputTokens,
  };
}

export function parseJsonBytesNoDuplicate(
  bytes,
  {
    label = "JSON record",
    invalid_code = "REQUEST_KEYSET_INVALID",
  } = {},
) {
  assertCritical(
    Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 1024 * 1024,
    invalid_code,
    `${label} bytes are missing or too large`,
  );
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    failCritical(invalid_code, `${label} is not exact UTF-8`);
  }
  let cursor = 0;
  const whitespace = () => {
    while (cursor < text.length && /[\u0009\u000a\u000d\u0020]/.test(text[cursor])) {
      cursor += 1;
    }
  };
  const parseString = () => {
    assertCritical(text[cursor] === '"', invalid_code, `${label} string is missing`);
    const start = cursor;
    cursor += 1;
    let escaped = false;
    while (cursor < text.length) {
      const character = text[cursor];
      if (!escaped && character === '"') {
        cursor += 1;
        try {
          return JSON.parse(text.slice(start, cursor));
        } catch {
          failCritical(invalid_code, `${label} string escape is invalid`);
        }
      }
      if (!escaped && character === "\\") escaped = true;
      else escaped = false;
      cursor += 1;
    }
    failCritical(invalid_code, `${label} string is unterminated`);
  };
  const parseValue = () => {
    whitespace();
    const character = text[cursor];
    if (character === '"') return parseString();
    if (character === "{") {
      cursor += 1;
      whitespace();
      const value = {};
      const keys = new Set();
      if (text[cursor] === "}") {
        cursor += 1;
        return value;
      }
      while (cursor < text.length) {
        whitespace();
        const key = parseString();
        assertCritical(
          !keys.has(key),
          "DUPLICATE_JSON_KEY",
          `${label} contains duplicate object key: ${key}`,
        );
        keys.add(key);
        whitespace();
        assertCritical(text[cursor] === ":", invalid_code, `${label} object colon is missing`);
        cursor += 1;
        value[key] = parseValue();
        whitespace();
        if (text[cursor] === "}") {
          cursor += 1;
          return value;
        }
        assertCritical(text[cursor] === ",", invalid_code, `${label} object comma is missing`);
        cursor += 1;
      }
      failCritical(invalid_code, `${label} object is unterminated`);
    }
    if (character === "[") {
      cursor += 1;
      whitespace();
      const value = [];
      if (text[cursor] === "]") {
        cursor += 1;
        return value;
      }
      while (cursor < text.length) {
        value.push(parseValue());
        whitespace();
        if (text[cursor] === "]") {
          cursor += 1;
          return value;
        }
        assertCritical(text[cursor] === ",", invalid_code, `${label} array comma is missing`);
        cursor += 1;
      }
      failCritical(invalid_code, `${label} array is unterminated`);
    }
    const remainder = text.slice(cursor);
    const literal = /^(true|false|null)/.exec(remainder);
    if (literal !== null) {
      cursor += literal[1].length;
      return literal[1] === "true"
        ? true
        : literal[1] === "false"
          ? false
          : null;
    }
    const number = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(remainder);
    assertCritical(number !== null, invalid_code, `${label} contains an invalid value`);
    cursor += number[0].length;
    const value = Number(number[0]);
    assertCritical(Number.isFinite(value), invalid_code, `${label} number is not finite`);
    return value;
  };
  const value = parseValue();
  whitespace();
  assertCritical(cursor === text.length, invalid_code, `${label} has trailing bytes`);
  return value;
}

export function classifyModelFailureEnvelope(bytes) {
  const value = parseJsonBytesNoDuplicate(bytes, {
    label: "model failure envelope",
    invalid_code: "REQUEST_KEYSET_INVALID",
  });
  exactClosedKeys(
    value,
    ["schema_version", "status"],
    "model failure envelope",
    "ACCOUNTING_MISMATCH",
  );
  assertCritical(
    value.schema_version === MODEL_FAILURE_SCHEMA
      && value.status === "DECLINED",
    "ACCOUNTING_MISMATCH",
    "model failure envelope is not the exact declined production outcome",
  );
  return Object.freeze({
    failure_stage: "MODEL",
    reason_code: MODEL_FAILURE_REASON_CODE,
    status: "FAILED",
  });
}

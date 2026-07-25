import { createConnection } from "node:net";
import { request as httpRequest } from "node:http";
import {
  constants,
  closeSync,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
  realpathSync,
  statSync,
  writeSync,
} from "node:fs";
import { isAbsolute, resolve } from "node:path";

import {
  assert,
  assertExistingPathWithoutSymlink,
  canonicalBytes,
  exactKeys,
  parseJsonBytes,
  sha256,
} from "../p1-097-minimal-documented/core.mjs";

const LOOPBACK = Object.freeze({
  scheme: "http",
  host: "127.0.0.1",
  port: 8787,
  path: "/v1/chat/completions",
  method: "POST",
});

const CAP_KEYS = Object.freeze([
  "provider_requests_max",
  "automatic_retry_max",
  "input_tokens_max",
  "output_tokens_max",
  "currency",
  "max_spend",
]);
const SESSION_STATE = new WeakMap();
const CHAT_COMPLETIONS_FRAMING_MARGIN_TOKENS = 1024;
export const PROVIDER_SESSION_CLOSURE_CLAIM = Object.freeze({
  provider_session_closed: true,
  owned_secret_buffer_overwrite_attempted: true,
  whole_process_memory_zeroization_claim: "NOT_CLAIMED",
});

export class SecretSinkForbidden extends Error {
  constructor() {
    super("Provider response contains the transient secret; no derived identity may be retained");
    this.name = "SecretSinkForbidden";
    this.code = "SECRET_SINK_FORBIDDEN";
    this.raw_response_identity_created = false;
    this.evidence_created = false;
  }
}

export function guardResponseBytesBeforeIdentity(rawBytes, secretBytes) {
  assert(
    Buffer.isBuffer(rawBytes) && Buffer.isBuffer(secretBytes) && secretBytes.length > 0,
    "SECRET_GUARD_INPUT_INVALID",
    "Secret containment guard requires byte buffers",
  );
  if (rawBytes.length > 0 && rawBytes.indexOf(secretBytes) !== -1) {
    throw new SecretSinkForbidden();
  }
  return {
    secret_detected: false,
    raw_response_identity_created: false,
    evidence_created: false,
  };
}

function readTransientSecret(source) {
  exactKeys(source, source.kind === "LOCAL_PROCESS_ENV"
    ? ["kind", "env_name"]
    : ["kind", "path"], "transient secret source");
  let secretText;
  if (source.kind === "LOCAL_PROCESS_ENV") {
    assert(
      typeof source.env_name === "string"
        && /^[A-Z][A-Z0-9_]{2,127}$/.test(source.env_name),
      "SECRET_SOURCE_INVALID",
      "secret environment variable name is invalid",
    );
    secretText = process.env[source.env_name];
  } else {
    assert(
      source.kind === "CONTROLLED_TEMPORARY_SECRET_FILE"
        && typeof source.path === "string"
        && isAbsolute(source.path)
        && resolve(source.path) === source.path,
      "SECRET_SOURCE_INVALID",
      "temporary secret file path is invalid",
    );
    assertExistingPathWithoutSymlink(source.path, "temporary secret file");
    const stat = lstatSync(source.path);
    assert(
      stat.isFile()
        && !stat.isSymbolicLink()
        && stat.nlink === 1
        && stat.uid === process.getuid()
        && (stat.mode & 0o077) === 0
        && realpathSync(source.path) === source.path,
      "SECRET_SOURCE_INVALID",
      "temporary secret file must be an owned, single-link, non-symlink regular file with no group/other permissions",
    );
    secretText = readFileSync(source.path, "utf8").replace(/\r?\n$/, "");
  }
  assert(
    typeof secretText === "string"
      && secretText.length >= 1
      && secretText.length <= 8192
      && !/[\r\n\0]/.test(secretText),
    "SECRET_SOURCE_INVALID",
    "transient secret is missing or malformed",
  );
  return Buffer.from(secretText, "utf8");
}

function safeResponse(rawBytes, secretBytes) {
  guardResponseBytesBeforeIdentity(rawBytes, secretBytes);
  let parsed;
  try {
    parsed = parseJsonBytes(rawBytes, "Provider response");
  } catch {
    return {
      accepted: false,
      reason_code: "PROVIDER_RESPONSE_SCHEMA_INVALID",
      content_bytes: null,
      usage: {},
    };
  }
  if (
    parsed === null
    || typeof parsed !== "object"
    || Array.isArray(parsed)
    || !Array.isArray(parsed.choices)
    || parsed.choices.length < 1
    || typeof parsed.choices[0]?.message?.content !== "string"
  ) {
    return {
      accepted: false,
      reason_code: "PROVIDER_RESPONSE_SCHEMA_INVALID",
      content_bytes: null,
      usage: {},
    };
  }
  const usage = parsed.usage ?? {};
  for (const key of ["prompt_tokens", "completion_tokens", "total_tokens"]) {
    if (
      usage[key] !== undefined
      && (!Number.isInteger(usage[key]) || usage[key] < 0)
    ) {
      return {
        accepted: false,
        reason_code: "PROVIDER_USAGE_INVALID",
        content_bytes: null,
        usage: {},
      };
    }
  }
  const contentBytes = Buffer.from(parsed.choices[0].message.content, "utf8");
  guardResponseBytesBeforeIdentity(contentBytes, secretBytes);
  return {
    accepted: true,
    reason_code: null,
    content_bytes: contentBytes,
    usage: {
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens,
      total_tokens: usage.total_tokens,
    },
  };
}

function responseRejection(reasonCode, rawBytes) {
  return canonicalBytes({
    schema_version: "p1-117-provider-response-safe-rejection/v1",
    status: "REJECTED",
    reason_code: reasonCode,
    raw_response_sha256: sha256(rawBytes),
    raw_response_byte_length: rawBytes.length,
    raw_response_retained: false,
  });
}

export function validateProviderCaps(caps) {
  exactKeys(caps, CAP_KEYS, "Provider caps");
  assert(
    Number.isInteger(caps.provider_requests_max)
      && caps.provider_requests_max >= 1
      && caps.provider_requests_max <= 60
      && caps.automatic_retry_max === 0
      && Number.isInteger(caps.input_tokens_max)
      && caps.input_tokens_max >= 1
      && caps.input_tokens_max <= 500000
      && Number.isInteger(caps.output_tokens_max)
      && caps.output_tokens_max >= 1
      && caps.output_tokens_max <= 100000
      && caps.currency === "USD"
      && typeof caps.max_spend === "number"
      && Number.isFinite(caps.max_spend)
      && caps.max_spend >= 0
      && caps.max_spend <= 25,
    "PROVIDER_CAPS_INVALID",
    "Provider caps exceed or differ from the exact P1-117 ceiling",
  );
  return caps;
}

export class FormalProviderSession {
  static open({ transientSecretSource, preflightReceipt }) {
    assert(
      preflightReceipt?.status === "PASS"
        && preflightReceipt.provider_requests === 0
        && preflightReceipt.secret_reads === 0
        && preflightReceipt.network_connections === 0
        && preflightReceipt.schedule_count === 36,
      "PROVIDER_SESSION_PREFLIGHT_REQUIRED",
      "exact 36-run offline preflight must pass before the single Secret read",
    );
    const session = new FormalProviderSession();
    SESSION_STATE.set(session, {
      secret: readTransientSecret(transientSecretSource),
      closed: false,
      requestCount: 0,
      secretReads: 1,
    });
    return Object.freeze(session);
  }

  get status() {
    const state = SESSION_STATE.get(this);
    return state?.closed === false ? "OPEN" : "CLOSED";
  }

  get requestCount() {
    return SESSION_STATE.get(this)?.requestCount ?? 0;
  }

  close() {
    const state = SESSION_STATE.get(this);
    if (!state || state.closed) {
      return {
        provider_session_closed: true,
        owned_secret_buffer_overwrite_attempted: false,
        whole_process_memory_zeroization_claim: "NOT_CLAIMED",
      };
    }
    state.secret.fill(0);
    state.secret = null;
    state.closed = true;
    SESSION_STATE.delete(this);
    return structuredClone(PROVIDER_SESSION_CLOSURE_CLAIM);
  }
}

export function conservativeInputTokenUpperBound(requestBytes) {
  assert(
    Buffer.isBuffer(requestBytes) && requestBytes.length > 0,
    "PROVIDER_REQUEST_INVALID",
    "request body is empty",
  );
  return {
    tokens: requestBytes.length + CHAT_COMPLETIONS_FRAMING_MARGIN_TOKENS,
    method: "UTF8_BYTE_LENGTH_PLUS_1024_CHAT_COMPLETIONS_FRAMING_UPPER_BOUND",
  };
}

export async function executeLoopbackChatCompletion({
  requestBytes,
  session,
  timeoutMs = 120000,
  maxResponseBytes = 4 * 1024 * 1024,
}) {
  assert(Buffer.isBuffer(requestBytes) && requestBytes.length > 0, "PROVIDER_REQUEST_INVALID", "request body is empty");
  assert(
    Number.isInteger(timeoutMs) && timeoutMs >= 1000 && timeoutMs <= 120000,
    "PROVIDER_REQUEST_INVALID",
    "timeout exceeds the bounded Provider contract",
  );
  const sessionState = SESSION_STATE.get(session);
  assert(
    session instanceof FormalProviderSession
      && sessionState?.closed === false
      && Buffer.isBuffer(sessionState.secret),
    "PROVIDER_SESSION_INVALID",
    "Provider request requires one open opaque formal-run session",
  );
  assert(
    requestBytes.indexOf(sessionState.secret) === -1,
    "SECRET_SINK_FORBIDDEN",
    "transient secret appears in the Provider request body",
  );

  const started = process.hrtime.bigint();
  let peerAddress = null;
  sessionState.requestCount += 1;
  let result;
  let transportReason = null;
  try {
    result = await new Promise((resolvePromise, rejectPromise) => {
      const request = httpRequest({
        protocol: "http:",
        host: LOOPBACK.host,
        family: 4,
        port: LOOPBACK.port,
        path: LOOPBACK.path,
        method: LOOPBACK.method,
        agent: false,
        timeout: timeoutMs,
        headers: {
          authorization: `Bearer ${sessionState.secret.toString("utf8")}`,
          "content-type": "application/json",
          "content-length": String(requestBytes.length),
          connection: "close",
        },
        createConnection: (options, oncreate) => createConnection({
          host: LOOPBACK.host,
          family: 4,
          port: LOOPBACK.port,
        }, oncreate),
      });
      request.once("socket", (socket) => {
        socket.once("connect", () => {
          peerAddress = socket.remoteAddress;
          if (peerAddress !== LOOPBACK.host || socket.remotePort !== LOOPBACK.port) {
            const error = new Error("connected peer differs from exact loopback endpoint");
            error.code = "NON_LOOPBACK_CONNECTION_FORBIDDEN";
            request.destroy(error);
          }
        });
      });
      request.once("timeout", () => {
        const error = new Error("Provider request timed out");
        error.code = "PROVIDER_TIMEOUT";
        request.destroy(error);
      });
      request.once("error", rejectPromise);
      request.once("response", (response) => {
        const chunks = [];
        let length = 0;
        response.on("data", (chunk) => {
          length += chunk.length;
          if (length > maxResponseBytes) {
            const error = new Error("Provider response exceeds the byte cap");
            error.code = "PROVIDER_RESPONSE_SCHEMA_INVALID";
            response.destroy(error);
            return;
          }
          chunks.push(chunk);
        });
        response.once("error", rejectPromise);
        response.once("end", () => {
          resolvePromise({
            statusCode: response.statusCode,
            bytes: Buffer.concat(chunks),
          });
        });
      });
      request.end(requestBytes);
    });
  } catch (error) {
    if (error.code === "NON_LOOPBACK_CONNECTION_FORBIDDEN") throw error;
    transportReason = error.code === "PROVIDER_TIMEOUT"
      ? "PROVIDER_TIMEOUT"
      : error.code === "PROVIDER_RESPONSE_SCHEMA_INVALID"
        ? "PROVIDER_RESPONSE_SCHEMA_INVALID"
        : "PROVIDER_TRANSPORT_ERROR";
    result = { statusCode: null, bytes: Buffer.alloc(0) };
  }
  const latencyMs = Number((process.hrtime.bigint() - started) / 1000000n);
  guardResponseBytesBeforeIdentity(result.bytes, sessionState.secret);
  const successfulLoopbackConnections = peerAddress === LOOPBACK.host ? 1 : 0;
  if (peerAddress !== null) {
    assert(
      peerAddress === LOOPBACK.host,
      "NON_LOOPBACK_CONNECTION_FORBIDDEN",
      "Provider peer was not exact IPv4 loopback",
    );
  }
  let response = {
    accepted: false,
    reason_code: transportReason,
    content_bytes: null,
    usage: {},
  };
  if (transportReason === null && result.statusCode !== 200) {
    response.reason_code = "PROVIDER_HTTP_NON_PASS";
  } else if (transportReason === null) {
    response = safeResponse(result.bytes, sessionState.secret);
  }
  const rejectionBytes = response.accepted
    ? null
    : responseRejection(response.reason_code, result.bytes);
  return {
    endpoint: LOOPBACK,
    status_code: result.statusCode,
    peer_address: peerAddress,
    response_content_bytes: response.content_bytes,
    response_safe_rejection_bytes: rejectionBytes,
    raw_response_identity: {
      sha256: sha256(result.bytes),
      byte_length: result.bytes.length,
      retained: false,
    },
    accepted_transport_wrapper: response.accepted,
    reason_code: response.reason_code,
    usage: response.usage,
    latency_ms: latencyMs,
    provider_requests: 1,
    successful_loopback_connections: successfulLoopbackConnections,
    automatic_retries: 0,
    secret_reads: 0,
    formal_session_secret_reads_total: sessionState.secretReads,
    redirects_followed: 0,
    proxy_used: false,
    dns_used: false,
  };
}

export class AppendOnlyAccountingLedger {
  static create(path, caps) {
    validateProviderCaps(caps);
    const fd = openSync(
      path,
      constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_APPEND
        | (constants.O_NOFOLLOW ?? 0),
      0o600,
    );
    return new AppendOnlyAccountingLedger(path, fd, caps);
  }

  constructor(path, fd, caps) {
    this.path = path;
    this.fd = fd;
    this.identity = fstatSync(fd);
    this.caps = structuredClone(caps);
    this.closed = false;
    this.sequence = 0;
    this.totals = {
      provider_requests_accounted: 0,
      input_tokens_accounted: 0,
      output_tokens_accounted: 0,
      input_tokens_observed: 0,
      output_tokens_observed: 0,
      automatic_retries: 0,
      cost_observed_usd: null,
      cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
    };
    this.append("LEDGER_OPENED", null, {
      caps: this.caps,
      cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
    });
  }

  assertOpen() {
    assert(!this.closed, "ACCOUNTING_LEDGER_CLOSED", "accounting ledger is closed");
    const stat = fstatSync(this.fd);
    assert(
      stat.dev === this.identity.dev
        && stat.ino === this.identity.ino
        && stat.uid === this.identity.uid
        && stat.isFile(),
      "ACCOUNTING_LEDGER_IDENTITY_DRIFT",
      "open accounting ledger identity drifted",
    );
  }

  append(eventType, runId, data) {
    this.assertOpen();
    this.sequence += 1;
    const event = {
      schema_version: "p1-117-accounting-event/v1",
      sequence: this.sequence,
      event_type: eventType,
      run_id: runId,
      data,
      totals: structuredClone(this.totals),
    };
    writeSync(this.fd, canonicalBytes(event));
    return event;
  }

  reserve(runId, { inputTokenBound, inputTokenBoundMethod, outputTokenBound }) {
    assert(
      Number.isInteger(inputTokenBound) && inputTokenBound >= 0
        && Number.isInteger(outputTokenBound) && outputTokenBound >= 1,
      "ACCOUNTING_RESERVATION_INVALID",
      "token reservation is invalid",
    );
    assert(
      [
        "UTF8_BYTE_LENGTH_PLUS_1024_CHAT_COMPLETIONS_FRAMING_UPPER_BOUND",
        "QUALITY_FROZEN_PER_RUN_RESERVATION",
      ].includes(inputTokenBoundMethod),
      "ACCOUNTING_RESERVATION_INVALID",
      "input token reservation must use the deterministic conservative bound",
    );
    const next = {
      provider_requests_accounted: this.totals.provider_requests_accounted + 1,
      input_tokens_accounted: this.totals.input_tokens_accounted + inputTokenBound,
      output_tokens_accounted: this.totals.output_tokens_accounted + outputTokenBound,
    };
    assert(
      next.provider_requests_accounted <= this.caps.provider_requests_max
        && next.input_tokens_accounted <= this.caps.input_tokens_max
        && next.output_tokens_accounted <= this.caps.output_tokens_max
        && this.totals.automatic_retries === 0,
      "PROVIDER_CAP_WOULD_BE_EXCEEDED",
      "Provider request or token reservation would exceed the frozen cap",
    );
    Object.assign(this.totals, next);
    return this.append("REQUEST_RESERVED", runId, {
      input_token_upper_bound: inputTokenBound,
      input_token_upper_bound_method: inputTokenBoundMethod,
      output_token_upper_bound: outputTokenBound,
      request_count: 1,
      automatic_retry_count: 0,
    });
  }

  observe(runId, result) {
    const observedInput = result.usage.prompt_tokens ?? 0;
    const observedOutput = result.usage.completion_tokens ?? 0;
    assert(
      this.totals.input_tokens_observed + observedInput <= this.caps.input_tokens_max
        && this.totals.output_tokens_observed + observedOutput <= this.caps.output_tokens_max,
      "PROVIDER_CAP_EXCEEDED",
      "Provider-reported token usage exceeds the frozen cap",
    );
    this.totals.input_tokens_observed += observedInput;
    this.totals.output_tokens_observed += observedOutput;
    return this.append("RESPONSE_OBSERVED", runId, {
      status_code: result.status_code,
      peer_address: result.peer_address,
      provider_requests: result.provider_requests,
      successful_loopback_connections: result.successful_loopback_connections,
      outcome: result.reason_code ?? "RESPONSE_WRAPPER_ACCEPTED",
      automatic_retries: result.automatic_retries,
      prompt_tokens: result.usage.prompt_tokens ?? null,
      completion_tokens: result.usage.completion_tokens ?? null,
      latency_ms: result.latency_ms,
      observed_cost_usd: null,
      cost_status: "UNKNOWN_GATEWAY_METERING_UNAVAILABLE",
      monetary_cap_empirically_enforced: false,
    });
  }

  close() {
    if (this.closed) return;
    try {
      this.append("LEDGER_CLOSED", null, {
        status: "COMPLETE",
        ledger_sha256_before_close: sha256(readFileSync(this.path)),
      });
    } finally {
      closeSync(this.fd);
      this.closed = true;
    }
  }
}

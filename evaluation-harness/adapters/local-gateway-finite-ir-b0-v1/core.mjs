import { createHash, randomBytes } from "node:crypto";
import http from "node:http";
import net from "node:net";
import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertOwnedProductionRunRoot,
  canonicalJsonBytes,
  EVIDENCE_ROOT,
  readRegular,
  sha256,
  writeCreateOnce,
} from "../../recording/local-gateway-finite-ir-b0-v1/evidence.mjs";

export const ADAPTER_VERSION = "P1-062-LOCAL-GATEWAY-FINITE-IR-ADAPTER/1";
export const REQUEST_MAX_BYTES = 32768;
export const RESPONSE_MAX_BYTES = 131072;
export const CONTENT_MAX_BYTES = 512;
export const REQUESTED_MODEL = "gpt-5.6-luna";
export const PRODUCTION_ENDPOINT = Object.freeze({
  host: "127.0.0.1",
  port: 8787,
  path: "/v1/chat/completions",
});

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const QUALITY_REQUEST_PATH = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/local-gateway-finite-ir-b0-v1/request-fixture.json",
);
const QUALITY_REQUEST_IDENTITY = Object.freeze({
  byte_length: 5235,
  sha256: "682d8098382fa512e0396d566af9f981e375d88725471d3d189ab5d8b789de79",
});
const MAPPING_PATH = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/local-gateway-finite-ir-b0-v1/four-state-mapping.json",
);
const MAPPING_IDENTITY = Object.freeze({
  byte_length: 2686,
  sha256: "1edd484643e9fa81ec5145d444988bdcc513fd5b9e0ae28e2557e8d796a04c7a",
});
const TASK_SPEC_PATH = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/task-spec.json",
);
const TASK_SPEC_IDENTITY = Object.freeze({
  byte_length: 2960,
  sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
});
const BASELINE_CONTEXT_PATH = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1/shared/baseline-context.json",
);
const BASELINE_CONTEXT_IDENTITY = Object.freeze({
  byte_length: 377,
  sha256: "64fab9efd47c193af94e3f7baee67072a32497d35c9dc1aee8a804bf32269cb9",
});
const COMPILER_PATH = join(REPOSITORY_ROOT, "evaluation-harness/harness/finite-typed-patch-ir-v1/compiler.mjs");
const COMPILER_IDENTITY = Object.freeze({
  byte_length: 3814,
  sha256: "013a58a6284270c6808f6cfe815dbea6825b8a43a0a6f885305df23890c7a4f9",
});

const utf8Decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });

export class AdapterError extends Error {
  constructor(code) {
    super(code);
    this.name = "AdapterError";
    this.code = code;
  }
}

const assert = (condition, code) => {
  if (!condition) throw new AdapterError(code);
};

const isRecord = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function readIdentity(path, identity, label) {
  const bytes = readRegular(path, identity.byte_length);
  assert(bytes.length === identity.byte_length && sha256(bytes) === identity.sha256, `${label}_IDENTITY_DRIFT`);
  return bytes;
}

class DuplicateSafeJsonParser {
  constructor(text) {
    this.text = text;
    this.offset = 0;
    this.nodes = 0;
  }

  parse() {
    this.skipSpace();
    const value = this.value(0);
    this.skipSpace();
    assert(this.offset === this.text.length, "JSON_TRAILING_BYTES");
    return value;
  }

  skipSpace() {
    while (this.offset < this.text.length && /[\u0020\u0009\u000a\u000d]/u.test(this.text[this.offset])) {
      this.offset += 1;
    }
  }

  value(depth) {
    assert(depth <= 64, "JSON_DEPTH_LIMIT");
    this.nodes += 1;
    assert(this.nodes <= 4096, "JSON_NODE_LIMIT");
    const token = this.text[this.offset];
    if (token === "{") return this.object(depth);
    if (token === "[") return this.array(depth);
    if (token === '"') return this.string();
    if (this.text.startsWith("true", this.offset)) return this.literal("true", true);
    if (this.text.startsWith("false", this.offset)) return this.literal("false", false);
    if (this.text.startsWith("null", this.offset)) return this.literal("null", null);
    return this.number();
  }

  literal(token, value) {
    this.offset += token.length;
    return value;
  }

  string() {
    const start = this.offset;
    this.offset += 1;
    while (this.offset < this.text.length) {
      const code = this.text.charCodeAt(this.offset);
      if (code === 0x22) {
        this.offset += 1;
        try {
          return JSON.parse(this.text.slice(start, this.offset));
        } catch {
          throw new AdapterError("JSON_STRING_INVALID");
        }
      }
      assert(code >= 0x20, "JSON_CONTROL_CHARACTER");
      if (code === 0x5c) {
        this.offset += 1;
        assert(this.offset < this.text.length, "JSON_ESCAPE_TRUNCATED");
        if (this.text[this.offset] === "u") {
          assert(/^[0-9a-fA-F]{4}$/u.test(this.text.slice(this.offset + 1, this.offset + 5)),
            "JSON_UNICODE_ESCAPE_INVALID");
          this.offset += 4;
        } else {
          assert(/["\\/bfnrt]/u.test(this.text[this.offset]), "JSON_ESCAPE_INVALID");
        }
      }
      this.offset += 1;
    }
    throw new AdapterError("JSON_STRING_UNTERMINATED");
  }

  number() {
    const match = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/u.exec(this.text.slice(this.offset));
    assert(match, "JSON_VALUE_INVALID");
    this.offset += match[0].length;
    const number = Number(match[0]);
    assert(Number.isFinite(number), "JSON_NUMBER_INVALID");
    return number;
  }

  array(depth) {
    this.offset += 1;
    const values = [];
    this.skipSpace();
    if (this.text[this.offset] === "]") {
      this.offset += 1;
      return values;
    }
    while (true) {
      this.skipSpace();
      values.push(this.value(depth + 1));
      this.skipSpace();
      if (this.text[this.offset] === "]") {
        this.offset += 1;
        return values;
      }
      assert(this.text[this.offset] === ",", "JSON_ARRAY_SEPARATOR_MISSING");
      this.offset += 1;
    }
  }

  object(depth) {
    this.offset += 1;
    const value = Object.create(null);
    const keys = new Set();
    this.skipSpace();
    if (this.text[this.offset] === "}") {
      this.offset += 1;
      return value;
    }
    while (true) {
      this.skipSpace();
      assert(this.text[this.offset] === '"', "JSON_OBJECT_KEY_MISSING");
      const key = this.string();
      assert(!keys.has(key), "JSON_DUPLICATE_MEMBER");
      keys.add(key);
      this.skipSpace();
      assert(this.text[this.offset] === ":", "JSON_OBJECT_COLON_MISSING");
      this.offset += 1;
      this.skipSpace();
      value[key] = this.value(depth + 1);
      this.skipSpace();
      if (this.text[this.offset] === "}") {
        this.offset += 1;
        return value;
      }
      assert(this.text[this.offset] === ",", "JSON_OBJECT_SEPARATOR_MISSING");
      this.offset += 1;
    }
  }
}

export function parseJsonNoDuplicates(bytes, maxBytes, label = "JSON") {
  assert(Buffer.isBuffer(bytes), `${label}_NOT_BUFFER`);
  assert(bytes.length <= maxBytes, `${label}_TOO_LARGE`);
  assert(!(bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf), `${label}_BOM_FORBIDDEN`);
  assert(!bytes.includes(0), `${label}_NUL_FORBIDDEN`);
  let text;
  try {
    text = utf8Decoder.decode(bytes);
  } catch {
    throw new AdapterError(`${label}_UTF8_INVALID`);
  }
  return new DuplicateSafeJsonParser(text).parse();
}

function closedKeys(value, keys, code) {
  assert(isRecord(value), `${code}_NOT_OBJECT`);
  assert(JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort()), `${code}_KEYS_DRIFT`);
}

export function buildRequestBody() {
  const fixtureBytes = readIdentity(QUALITY_REQUEST_PATH, QUALITY_REQUEST_IDENTITY, "QUALITY_REQUEST");
  const taskSpecBytes = readIdentity(TASK_SPEC_PATH, TASK_SPEC_IDENTITY, "TASK_SPEC");
  const baselineBytes = readIdentity(BASELINE_CONTEXT_PATH, BASELINE_CONTEXT_IDENTITY, "BASELINE_CONTEXT");
  const fixture = parseJsonNoDuplicates(fixtureBytes, QUALITY_REQUEST_IDENTITY.byte_length, "QUALITY_REQUEST");
  const taskSpec = parseJsonNoDuplicates(taskSpecBytes, TASK_SPEC_IDENTITY.byte_length, "TASK_SPEC");
  const baseline = parseJsonNoDuplicates(baselineBytes, BASELINE_CONTEXT_IDENTITY.byte_length, "BASELINE_CONTEXT");

  assert(fixture.model === REQUESTED_MODEL, "REQUEST_MODEL_DRIFT");
  assert(fixture.user_envelope.task.issue.text === taskSpec.issue.text, "REQUEST_ISSUE_DRIFT");
  assert(JSON.stringify(fixture.user_envelope.task.issue.allowed_clarifications) ===
    JSON.stringify(taskSpec.issue.allowed_clarifications), "REQUEST_CLARIFICATIONS_DRIFT");
  assert(JSON.stringify(fixture.user_envelope.accepted_baseline_context) === JSON.stringify(baseline),
    "REQUEST_BASELINE_CONTEXT_DRIFT");
  assert(fixture.data_manifest.forbidden_category_payload_count === 0, "REQUEST_FORBIDDEN_PAYLOAD_PRESENT");
  assert(fixture.data_manifest.credential_in_request_body === false, "REQUEST_CREDENTIAL_FLAG_DRIFT");

  const body = {
    model: REQUESTED_MODEL,
    messages: [
      { role: "system", content: fixture.system_prompt },
      { role: "user", content: JSON.stringify(fixture.user_envelope) },
    ],
    temperature: fixture.request_construction.parameters.temperature,
    stream: fixture.request_construction.parameters.stream,
    max_tokens: fixture.request_construction.parameters.max_tokens,
  };
  assert(body.temperature === 0 && body.stream === false &&
    Number.isSafeInteger(body.max_tokens) && body.max_tokens > 0 && body.max_tokens <= 1024,
  "REQUEST_PARAMETERS_DRIFT");
  const bytes = Buffer.from(JSON.stringify(body), "utf8");
  assert(bytes.length <= REQUEST_MAX_BYTES, "REQUEST_BODY_TOO_LARGE");
  return Object.freeze({
    bytes,
    identity: Object.freeze({ byte_length: bytes.length, sha256: sha256(bytes) }),
    egress_manifest: Object.freeze({
      schema: "P1-062-EGRESS-MANIFEST/1",
      quality_request_fixture: { path: QUALITY_REQUEST_PATH, ...QUALITY_REQUEST_IDENTITY },
      task_spec: { path: TASK_SPEC_PATH, ...TASK_SPEC_IDENTITY },
      baseline_context: { path: BASELINE_CONTEXT_PATH, ...BASELINE_CONTEXT_IDENTITY },
      included_artifact_ids: [
        "P1_035_REP001_ISSUE_TEXT",
        "P1_035_REP001_ALLOWED_CLARIFICATIONS",
        "P1_035_REP001_ACCEPTED_BASELINE_CONTEXT",
        "P1_062_FINITE_IR_RESPONSE_INSTRUCTION",
      ],
      forbidden_category_payload_count: 0,
      authorization_header_in_request_body: false,
      request_body: { byte_length: bytes.length, sha256: sha256(bytes) },
    }),
  });
}

export function verifyFrozenRequest(runRoot) {
  const expected = buildRequestBody();
  const requestBytes = readRegular(join(runRoot, "request-body.json"), REQUEST_MAX_BYTES);
  assert(requestBytes.equals(expected.bytes), "REQUEST_BODY_IDENTITY_DRIFT");
  const manifestBytes = readRegular(join(runRoot, "egress-manifest.json"), REQUEST_MAX_BYTES);
  assert(manifestBytes.equals(canonicalJsonBytes(expected.egress_manifest)), "EGRESS_MANIFEST_IDENTITY_DRIFT");
  return expected;
}

function contentState(content) {
  const mappingBytes = readIdentity(MAPPING_PATH, MAPPING_IDENTITY, "QUALITY_MAPPING");
  const mapping = parseJsonNoDuplicates(mappingBytes, MAPPING_IDENTITY.byte_length, "QUALITY_MAPPING");
  const states = mapping.states.filter((state) => state.canonical_content === content);
  assert(states.length === 1, "CONTENT_NOT_EXACTLY_ADMITTED");
  return states[0];
}

function validUsage(usage) {
  if (usage === undefined) return true;
  if (!isRecord(usage)) return false;
  return ["prompt_tokens", "completion_tokens", "total_tokens"].every((key) =>
    usage[key] === undefined || (Number.isSafeInteger(usage[key]) && usage[key] >= 0));
}

function projectUsage(usage) {
  if (usage === undefined) return null;
  return Object.fromEntries(
    ["prompt_tokens", "completion_tokens", "total_tokens"]
      .filter((key) => usage[key] !== undefined)
      .map((key) => [key, usage[key]]),
  );
}

export function parseChatCompletion(rawBytes) {
  assert(Buffer.isBuffer(rawBytes), "RAW_RESPONSE_NOT_BUFFER");
  assert(rawBytes.length <= RESPONSE_MAX_BYTES, "RAW_RESPONSE_TOO_LARGE");
  let outer;
  try {
    outer = parseJsonNoDuplicates(rawBytes, RESPONSE_MAX_BYTES, "RAW_RESPONSE");
  } catch {
    throw new AdapterError("OUTER_JSON_INVALID_OR_DUPLICATE");
  }
  assert(isRecord(outer), "OUTER_NOT_OBJECT");
  assert(outer.object === "chat.completion", "OBJECT_MISMATCH");
  assert(typeof outer.id === "string" && outer.id.length > 0, "ID_INVALID");
  assert(Number.isSafeInteger(outer.created) && outer.created >= 0, "CREATED_INVALID");
  assert(outer.model === REQUESTED_MODEL, "MODEL_MISMATCH");
  assert(Array.isArray(outer.choices) && outer.choices.length === 1, "CHOICES_NOT_SINGLE");
  const choice = outer.choices[0];
  assert(isRecord(choice), "CHOICE_INVALID");
  assert(choice.index === 0, "CHOICE_INDEX_INVALID");
  assert(choice.finish_reason === "stop", "FINISH_REASON_NOT_STOP");
  const message = choice.message;
  assert(isRecord(message), "MESSAGE_INVALID");
  assert(message.role === "assistant", "MESSAGE_ROLE_NOT_ASSISTANT");
  assert(typeof message.content === "string", "MESSAGE_CONTENT_NOT_STRING");
  const contentBytes = Buffer.from(message.content, "utf8");
  assert(contentBytes.length <= CONTENT_MAX_BYTES, "MESSAGE_CONTENT_TOO_LARGE");
  assert(message.refusal === undefined || message.refusal === null, "MESSAGE_REFUSAL_PRESENT");
  assert(message.tool_calls === undefined && message.function_call === undefined && message.audio === undefined,
    "MESSAGE_TOOL_CALL_PRESENT");
  const state = contentState(message.content);
  assert(validUsage(outer.usage), "USAGE_INVALID");
  const responseIdBytes = Buffer.from(outer.id, "utf8");
  return Object.freeze({
    schema: "P1-062-WORKER-PARSE/1",
    status: "ACCEPTED",
    response_identity: { byte_length: rawBytes.length, sha256: sha256(rawBytes) },
    response_id_identity: { byte_length: responseIdBytes.length, sha256: sha256(responseIdBytes) },
    returned_model: outer.model,
    usage: projectUsage(outer.usage),
    content_identity: { byte_length: contentBytes.length, sha256: sha256(contentBytes) },
    values: Object.freeze([...state.values]),
    program_id: state.program_id,
    program_path: state.program_path,
    program_byte_length: state.program_byte_length,
    program_sha256: state.program_sha256,
    expected_compiler_status: state.expected_compiler_status,
    expected_outcome_id: state.expected_outcome_id,
  });
}

function stateForSelection(selection) {
  const mappingBytes = readIdentity(MAPPING_PATH, MAPPING_IDENTITY, "QUALITY_MAPPING");
  const mapping = parseJsonNoDuplicates(mappingBytes, MAPPING_IDENTITY.byte_length, "QUALITY_MAPPING");
  const states = mapping.states.filter((state) => state.program_id === selection.program_id);
  assert(states.length === 1, "SELECTION_PROGRAM_NOT_ADMITTED");
  const state = states[0];
  assert(JSON.stringify(selection.values) === JSON.stringify(state.values), "SELECTION_VALUES_DRIFT");
  for (const key of [
    "program_path",
    "program_byte_length",
    "program_sha256",
    "expected_compiler_status",
    "expected_outcome_id",
  ]) {
    assert(selection[key] === state[key], "SELECTION_IDENTITY_DRIFT");
  }
  return state;
}

export async function compileSelection(selection) {
  assert(selection && selection.status === "ACCEPTED", "SELECTION_NOT_ACCEPTED");
  const admittedState = stateForSelection(selection);
  const compilerBytes = readIdentity(COMPILER_PATH, COMPILER_IDENTITY, "COMPILER");
  const programPath = join(REPOSITORY_ROOT, admittedState.program_path);
  const programBytes = readIdentity(programPath, {
    byte_length: admittedState.program_byte_length,
    sha256: admittedState.program_sha256,
  }, "PROGRAM");
  const compiler = await import(`data:text/javascript;base64,${compilerBytes.toString("base64")}`);
  assert(compiler.COMPILER_VERSION === "SL-PATCH-IR-TRUSTED-COMPILER/1", "COMPILER_VERSION_DRIFT");
  const result = compiler.compileFiniteTypedPatchIr(programBytes);
  assert(result.status === selection.expected_compiler_status, "COMPILER_STATUS_MISMATCH");
  assert(result.program_id === selection.program_id, "COMPILER_PROGRAM_MISMATCH");
  assert(result.outcome_id === selection.expected_outcome_id, "COMPILER_OUTCOME_MISMATCH");
  return Object.freeze({
    status: result.status,
    program_id: result.program_id,
    outcome_id: result.outcome_id,
    kind: result.kind,
    proposal_length: result.proposal_length,
    proposal_sha256: result.proposal_sha256,
    postimage: result.postimage === null ? null : Buffer.from(result.postimage),
  });
}

function credentialRepresentations(secret) {
  const bytes = Buffer.from(secret, "utf8");
  const sha256Bytes = createHash("sha256").update(bytes).digest();
  const values = new Set([
    secret,
    encodeURIComponent(secret),
    bytes.toString("base64"),
    bytes.toString("base64url"),
    bytes.toString("hex"),
    bytes.toString("hex").toUpperCase(),
    sha256Bytes.toString("hex"),
    sha256Bytes.toString("hex").toUpperCase(),
    sha256Bytes.toString("base64"),
    sha256Bytes.toString("base64url"),
  ]);
  return Object.freeze([...values].filter((value) => value.length > 0));
}

function stringContainsRepresentation(value, representations) {
  return representations.some((representation) => value.includes(representation));
}

function decodedContainsCredentialRepresentation(value, representations, secretByteLength, parentKey = "") {
  if (typeof value === "string") return stringContainsRepresentation(value, representations);
  if (typeof value === "number" && value === secretByteLength &&
    /(?:secret|credential|authorization|api.?key|token).*(?:length|size)|(?:length|size).*(?:secret|credential|authorization|api.?key|token)/iu.test(parentKey)) {
    return true;
  }
  if (Array.isArray(value)) {
    return value.some((child) =>
      decodedContainsCredentialRepresentation(child, representations, secretByteLength, parentKey));
  }
  if (isRecord(value)) {
    return Object.entries(value).some(([key, child]) =>
      decodedContainsCredentialRepresentation(child, representations, secretByteLength, key));
  }
  return false;
}

function responseReflectsSecret(rawHeaders, statusMessage, body, secret) {
  const representations = credentialRepresentations(secret);
  if (
    stringContainsRepresentation(rawHeaders.join("\n"), representations) ||
    stringContainsRepresentation(String(statusMessage ?? ""), representations) ||
    representations.some((representation) => body.includes(representation))
  ) {
    return true;
  }
  try {
    const decoded = JSON.parse(body.toString("utf8"));
    return decodedContainsCredentialRepresentation(
      decoded,
      representations,
      Buffer.byteLength(secret, "utf8"),
    );
  } catch {
    return false;
  }
}

function evidenceContainsCredentialRepresentation(root, secret) {
  const representations = credentialRepresentations(secret);
  const visit = (path) => {
    const stat = lstatSync(path);
    assert(!stat.isSymbolicLink(), "OFFLINE_EVIDENCE_SYMLINK_FORBIDDEN");
    if (stat.isDirectory()) return readdirSync(path).some((child) => visit(join(path, child)));
    assert(stat.isFile(), "OFFLINE_EVIDENCE_LEAF_INVALID");
    const bytes = readFileSync(path);
    return representations.some((representation) => bytes.includes(representation));
  };
  return visit(root);
}

function terminalReceipt({ code, request, sent, peer, status, bodyIdentity, startedAt, startedNs }) {
  return {
    schema: "P1-062-TRANSPORT-RECEIPT/1",
    adapter_version: ADAPTER_VERSION,
    terminal_code: code,
    request_body: request,
    source_bearing_submission_count: sent ? 1 : 0,
    automatic_retry_count: 0,
    redirect_follow_count: 0,
    proxy_use_count: 0,
    dns_lookup_count: 0,
    peer: peer ?? null,
    http_status: status ?? null,
    response_body: bodyIdentity ?? null,
    started_at: startedAt,
    ended_at: new Date().toISOString(),
    latency_ms: Number(process.hrtime.bigint() - startedNs) / 1_000_000,
    authorization_header_persisted_hashed_or_logged: false,
    upstream_request_count: "UNKNOWN",
    monetary_cost: "UNKNOWN_USER_MANAGED_GATEWAY",
  };
}

function connectLiteral(host, port, timeoutMs) {
  return new Promise((resolvePromise, rejectPromise) => {
    const socket = net.connect({ host, port, family: 4 });
    let settled = false;
    const finish = (error) => {
      if (settled) return;
      settled = true;
      socket.removeAllListeners("connect");
      socket.removeAllListeners("error");
      socket.removeAllListeners("timeout");
      if (error) {
        socket.destroy();
        rejectPromise(error);
      } else {
        resolvePromise(socket);
      }
    };
    socket.once("connect", () => {
      if (socket.remoteAddress !== host || socket.remotePort !== port || socket.remoteFamily !== "IPv4") {
        finish(new AdapterError("PEER_IDENTITY_MISMATCH"));
      } else {
        socket.setTimeout(0);
        finish();
      }
    });
    socket.once("error", () => finish(new AdapterError("CONNECT_FAILED")));
    socket.setTimeout(timeoutMs, () => finish(new AdapterError("CONNECT_TIMEOUT")));
  });
}

async function submitOnceInternal({ runRoot, callSlotPath, secret, endpoint, timeoutMs, testMode }) {
  assert(typeof secret === "string" && secret.length >= 24 && !/[\r\n]/u.test(secret), "CREDENTIAL_INVALID");
  assert(testMode || (endpoint.host === PRODUCTION_ENDPOINT.host && endpoint.port === PRODUCTION_ENDPOINT.port &&
    endpoint.path === PRODUCTION_ENDPOINT.path), "PRODUCTION_ENDPOINT_DRIFT");
  assert(endpoint.host === "127.0.0.1" && Number.isInteger(endpoint.port) && endpoint.port > 0 &&
    endpoint.port <= 65535 && endpoint.path === "/v1/chat/completions", "ENDPOINT_INVALID");
  assert(Number.isInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 120000, "TIMEOUT_INVALID");
  const rootStat = lstatSync(runRoot);
  assert(rootStat.isDirectory() && !rootStat.isSymbolicLink() && realpathSync(runRoot) === resolve(runRoot),
    "RUN_ROOT_INVALID");
  const expectedRequest = verifyFrozenRequest(runRoot);
  const requestBytes = expectedRequest.bytes;
  assert(!requestBytes.includes(secret), "CREDENTIAL_COLLIDES_WITH_REQUEST_BODY");
  writeCreateOnce(callSlotPath, canonicalJsonBytes({
    schema: "P1-062-SOURCE-BEARING-CALL-SLOT/1",
    consumed: true,
    ordinal: 1,
    automatic_retry_allowed: false,
    request_body: expectedRequest.identity,
  }));

  const startedAt = new Date().toISOString();
  const startedNs = process.hrtime.bigint();
  const deadlineAt = Date.now() + timeoutMs;
  let sent = false;
  let peer = null;
  let status = null;
  let bodyIdentity = null;
  let socket;
  let code = "TRANSPORT_INTERNAL_FAILURE";
  try {
    socket = await connectLiteral(endpoint.host, endpoint.port, Math.max(1, deadlineAt - Date.now()));
    peer = { address: socket.remoteAddress, port: socket.remotePort, family: socket.remoteFamily };
    assert(Date.now() < deadlineAt, "CONNECT_TIMEOUT");
    const response = await new Promise((resolvePromise, rejectPromise) => {
      let settled = false;
      let deadlineTimer;
      const fail = (reason) => {
        if (settled) return;
        settled = true;
        clearTimeout(deadlineTimer);
        rejectPromise(reason instanceof AdapterError ? reason : new AdapterError("REQUEST_FAILED_AFTER_SEND"));
      };
      const request = http.request({
        host: endpoint.host,
        port: endpoint.port,
        path: endpoint.path,
        method: "POST",
        agent: false,
        createConnection: () => socket,
        lookup: () => { throw new AdapterError("DNS_LOOKUP_FORBIDDEN"); },
        headers: {
          Accept: "application/json",
          "Accept-Encoding": "identity",
          Authorization: `Bearer ${secret}`,
          Connection: "close",
          "Content-Type": "application/json",
          "Content-Length": requestBytes.length,
        },
      }, (incoming) => {
        status = incoming.statusCode ?? null;
        const contentLength = incoming.headers["content-length"];
        if (contentLength !== undefined && (!/^\d+$/u.test(contentLength) || Number(contentLength) > RESPONSE_MAX_BYTES)) {
          incoming.destroy();
          fail(new AdapterError("RESPONSE_CONTENT_LENGTH_INVALID"));
          return;
        }
        const chunks = [];
        let length = 0;
        incoming.on("data", (chunk) => {
          length += chunk.length;
          if (length > RESPONSE_MAX_BYTES) {
            incoming.destroy();
            fail(new AdapterError("RESPONSE_BODY_TOO_LARGE"));
            return;
          }
          chunks.push(Buffer.from(chunk));
        });
        incoming.once("end", () => {
          if (settled) return;
          settled = true;
          clearTimeout(deadlineTimer);
          resolvePromise({ incoming, body: Buffer.concat(chunks) });
        });
        incoming.once("error", () => fail(new AdapterError("RESPONSE_STREAM_FAILED")));
      });
      request.once("error", () => fail(new AdapterError(sent ? "REQUEST_FAILED_AFTER_SEND" : "REQUEST_FAILED_BEFORE_SEND")));
      deadlineTimer = setTimeout(() => {
        const timeoutError = new AdapterError(sent ? "REQUEST_TIMEOUT_AFTER_SEND" : "REQUEST_TIMEOUT_BEFORE_SEND");
        request.destroy(timeoutError);
        fail(timeoutError);
      }, Math.max(1, deadlineAt - Date.now()));
      sent = true;
      request.end(requestBytes);
    });

    const { incoming, body } = response;
    if (responseReflectsSecret(incoming.rawHeaders, incoming.statusMessage, body, secret)) {
      code = "CREDENTIAL_REFLECTION_DETECTED";
    } else if (String(incoming.headers["content-encoding"] ?? "identity").trim().toLowerCase() !== "identity") {
      code = "CONTENT_ENCODING_REJECTED";
    } else if (status < 200 || status >= 300) {
      bodyIdentity = writeCreateOnce(join(runRoot, "raw-response.json"), body);
      code = status >= 300 && status < 400 ? "HTTP_REDIRECT_REJECTED" : "HTTP_NON_200";
    } else if (!/^application\/json(?:\s*;|\s*$)/iu.test(String(incoming.headers["content-type"] ?? ""))) {
      code = "CONTENT_TYPE_REJECTED";
    } else {
      bodyIdentity = writeCreateOnce(join(runRoot, "raw-response.json"), body);
      code = "RESPONSE_RETAINED";
    }
  } catch (error) {
    code = error instanceof AdapterError ? error.code : sent ? "REQUEST_FAILED_AFTER_SEND" : "CONNECT_FAILED";
  } finally {
    if (socket && !socket.destroyed) socket.destroy();
    const receipt = terminalReceipt({
      code,
      request: expectedRequest.identity,
      sent,
      peer,
      status,
      bodyIdentity,
      startedAt,
      startedNs,
    });
    writeCreateOnce(join(runRoot, "transport-receipt.json"), canonicalJsonBytes(receipt));
    secret = "";
  }
  return Object.freeze({ code, sent, status, bodyIdentity });
}

export function submitProductionOnce({ runId, secret }) {
  const { root: runRoot } = assertOwnedProductionRunRoot(runId);
  return submitOnceInternal({
    runRoot,
    callSlotPath: join(EVIDENCE_ROOT, "source-bearing-call-slot.json"),
    secret,
    endpoint: PRODUCTION_ENDPOINT,
    timeoutMs: 120000,
    testMode: false,
  });
}

const OFFLINE_SCENARIOS = new Set([
  "success",
  "redirect",
  "non-200",
  "credential-reflection",
  "credential-digest-reflection",
  "oversize",
  "reset",
  "timeout",
]);

export async function runClosedOfflineTransportScenario({ runRoot, scenario, responseBody = undefined }) {
  assert(process.env.P1_062_LOCAL_GATEWAY_API_KEY === undefined, "OFFLINE_REAL_CREDENTIAL_ENV_FORBIDDEN");
  assert(OFFLINE_SCENARIOS.has(scenario), "OFFLINE_SCENARIO_INVALID");
  assert(responseBody === undefined || Buffer.isBuffer(responseBody), "OFFLINE_RESPONSE_BODY_INVALID");
  assert(scenario === "success" ? Buffer.isBuffer(responseBody) : responseBody === undefined,
    "OFFLINE_RESPONSE_BODY_NOT_CLOSED");

  let requestCount = 0;
  let observedRequestBody = Buffer.alloc(0);
  let authorizationHeaderPresent = false;
  const secret = `sk-offline-fixture-${randomBytes(24).toString("hex")}`;
  const server = http.createServer((request, response) => {
    requestCount += 1;
    authorizationHeaderPresent = typeof request.headers.authorization === "string";
    const chunks = [];
    request.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
    request.on("end", () => {
      observedRequestBody = Buffer.concat(chunks);
      if (scenario === "reset") {
        request.socket.destroy();
        return;
      }
      if (scenario === "timeout") return;
      if (scenario === "redirect") {
        const body = Buffer.from('{"redirect":true}', "utf8");
        response.writeHead(302, {
          Location: "http://127.0.0.1:1/forbidden",
          "Content-Type": "application/json",
          "Content-Length": String(body.length),
        });
        response.end(body);
        return;
      }
      if (scenario === "non-200") {
        const body = Buffer.from('{"error":{"code":"offline-test"}}', "utf8");
        response.writeHead(503, { "Content-Type": "application/json", "Content-Length": String(body.length) });
        response.end(body);
        return;
      }
      if (scenario === "credential-reflection") {
        const escaped = `\\u${secret.charCodeAt(0).toString(16).padStart(4, "0")}${secret.slice(1)}`;
        const body = Buffer.from(`{"echo":"${escaped}"}`, "utf8");
        response.writeHead(200, { "Content-Type": "application/json", "Content-Length": String(body.length) });
        response.end(body);
        return;
      }
      if (scenario === "credential-digest-reflection") {
        const digest = createHash("sha256").update(Buffer.from(secret, "utf8")).digest("hex");
        const body = Buffer.from(`{"credential_sha256":"${digest}"}`, "utf8");
        response.writeHead(200, { "Content-Type": "application/json", "Content-Length": String(body.length) });
        response.end(body);
        return;
      }
      if (scenario === "oversize") {
        response.writeHead(200, { "Content-Type": "application/json" });
        response.end(Buffer.alloc(RESPONSE_MAX_BYTES + 1, 0x78));
        return;
      }
      response.writeHead(200, {
        "Content-Type": "application/json",
        "Content-Encoding": "identity",
        "Content-Length": String(responseBody.length),
      });
      response.end(responseBody);
    });
  });

  await new Promise((resolvePromise, rejectPromise) => {
    server.once("error", rejectPromise);
    server.listen(0, "127.0.0.1", resolvePromise);
  });
  const address = server.address();
  assert(address && typeof address === "object" && address.address === "127.0.0.1" &&
    address.port !== PRODUCTION_ENDPOINT.port, "OFFLINE_SERVER_IDENTITY_INVALID");
  try {
    const result = await submitOnceInternal({
      runRoot,
      callSlotPath: join(runRoot, "source-bearing-call-slot.json"),
      secret,
      endpoint: { host: "127.0.0.1", port: address.port, path: "/v1/chat/completions" },
      timeoutMs: scenario === "timeout" ? 50 : 1000,
      testMode: true,
    });
    const expectedRequest = buildRequestBody();
    const credentialPersistenceDetected = evidenceContainsCredentialRepresentation(runRoot, secret);
    return Object.freeze({
      result,
      request_count: requestCount,
      request_body_matches_frozen: observedRequestBody.equals(expectedRequest.bytes),
      authorization_header_present: authorizationHeaderPresent,
      credential_persistence_detected: credentialPersistenceDetected,
    });
  } finally {
    await new Promise((resolvePromise) => {
      server.close(resolvePromise);
      server.closeAllConnections?.();
    });
  }
}

export function responseHash(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

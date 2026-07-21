import assert from "node:assert/strict";
import {
  existsSync,
  lstatSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  AdapterError,
  buildRequestBody,
  compileSelection,
  parseChatCompletion,
  REQUESTED_MODEL,
  runClosedOfflineTransportScenario,
} from "../../adapters/local-gateway-finite-ir-b0-v1/core.mjs";
import {
  evaluateChatCompletionResponse,
  RAW_RESPONSE_MAX_BYTES,
} from "../../evaluator/local-gateway-finite-ir-b0-v1/quality-oracle.mjs";
import { canonicalJsonBytes } from "../../recording/local-gateway-finite-ir-b0-v1/evidence.mjs";

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const FIXTURE_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/fixtures/local-gateway-finite-ir-b0-v1");
const TEMP_PREFIX = "sourcelens-p1-062-offline-";

const fixture = JSON.parse(readFileSync(join(FIXTURE_ROOT, "fake-chat-completions-cases.json"), "utf8"));
const mapping = JSON.parse(readFileSync(join(FIXTURE_ROOT, "four-state-mapping.json"), "utf8"));

const clone = (value) => structuredClone(value);

function mutateFakeResponse(base, mutation) {
  if (mutation === "RAW_MALFORMED_OUTER") return Buffer.from("{", "utf8");
  if (mutation === "RAW_OVER_LIMIT") return Buffer.alloc(RAW_RESPONSE_MAX_BYTES + 1, 0x78);
  if (mutation === "OUTER_ARRAY") return Buffer.from("[]", "utf8");

  const response = clone(base);
  const contentByProgram = Object.fromEntries(
    mapping.states.map((state) => [state.program_id, state.canonical_content]),
  );
  switch (mutation) {
    case "NONE": break;
    case "CONTENT_IR00": response.choices[0].message.content = contentByProgram.IR00; break;
    case "CONTENT_IR01": response.choices[0].message.content = contentByProgram.IR01; break;
    case "CONTENT_IR11_DELETE_USAGE":
      response.choices[0].message.content = contentByProgram.IR11;
      delete response.usage;
      break;
    case "WRONG_OBJECT": response.object = "chat.completion.chunk"; break;
    case "EMPTY_ID": response.id = ""; break;
    case "NEGATIVE_CREATED": response.created = -1; break;
    case "WRONG_MODEL": response.model = "gpt-5.6-luna-substitute"; break;
    case "MODEL_NON_STRING": response.model = 56; break;
    case "DELETE_CHOICES": delete response.choices; break;
    case "ZERO_CHOICES": response.choices = []; break;
    case "MULTIPLE_CHOICES": response.choices.push(clone(response.choices[0])); break;
    case "CHOICE_NON_OBJECT": response.choices[0] = null; break;
    case "CHOICE_INDEX_ONE": response.choices[0].index = 1; break;
    case "FINISH_LENGTH": response.choices[0].finish_reason = "length"; break;
    case "MESSAGE_NON_OBJECT": response.choices[0].message = null; break;
    case "ROLE_TOOL": response.choices[0].message.role = "tool"; break;
    case "CONTENT_NON_STRING": response.choices[0].message.content = { schema: "not-a-string" }; break;
    case "CONTENT_OVERSIZE": response.choices[0].message.content = "x".repeat(513); break;
    case "REFUSAL_PRESENT": response.choices[0].message.refusal = "cannot comply"; break;
    case "TOOL_CALL_PRESENT": response.choices[0].message.tool_calls = []; break;
    case "FUNCTION_CALL_PRESENT": response.choices[0].message.function_call = null; break;
    case "AUDIO_PRESENT": response.choices[0].message.audio = null; break;
    case "CONTENT_MARKDOWN":
      response.choices[0].message.content = `\`\`\`json\n${contentByProgram.IR10}\n\`\`\``;
      break;
    case "CONTENT_LEADING_SPACE": response.choices[0].message.content = ` ${contentByProgram.IR10}`; break;
    case "CONTENT_TRAILING_NEWLINE": response.choices[0].message.content = `${contentByProgram.IR10}\n`; break;
    case "CONTENT_EXTRA_MEMBER":
      response.choices[0].message.content = contentByProgram.IR10.replace(/\}$/u, ',"extra":true}');
      break;
    case "CONTENT_WRONG_SCHEMA":
      response.choices[0].message.content = contentByProgram.IR10.replace(
        "SL-PATCH-IR-CHOICE/1",
        "SL-PATCH-IR-CHOICE/2",
      );
      break;
    case "CONTENT_WRONG_TASK":
      response.choices[0].message.content = contentByProgram.IR10.replace("@1.0.0", "@2.0.0");
      break;
    case "CONTENT_INVALID_VALUE":
      response.choices[0].message.content = contentByProgram.IR10.replace('"ARG0"]}', '"ARG2"]}');
      break;
    case "CONTENT_SHORT_VALUES":
      response.choices[0].message.content = contentByProgram.IR10.replace(
        '["ARG1","ARG0"]',
        '["ARG1"]',
      );
      break;
    case "CONTENT_DUPLICATE_MEMBER":
      response.choices[0].message.content = contentByProgram.IR10.replace(
        '{"schema":',
        '{"schema":"SL-PATCH-IR-CHOICE/1","schema":',
      );
      break;
    case "CONTENT_TRAILING_JSON": response.choices[0].message.content = `${contentByProgram.IR10}{}`; break;
    case "USAGE_NEGATIVE": response.usage.total_tokens = -1; break;
    case "RAW_DUPLICATE_OUTER_MODEL": {
      const raw = JSON.stringify(response).replace(
        `"model":"${REQUESTED_MODEL}"`,
        `"model":"${REQUESTED_MODEL}","model":"${REQUESTED_MODEL}"`,
      );
      return Buffer.from(raw, "utf8");
    }
    default: throw new Error(`unknown fake response mutation: ${mutation}`);
  }
  return Buffer.from(JSON.stringify(response), "utf8");
}

function workerProjection(rawBytes) {
  try {
    const projection = parseChatCompletion(rawBytes);
    return { status: "ACCEPTED", reason_code: null, program_id: projection.program_id, projection };
  } catch (error) {
    assert.ok(error instanceof AdapterError, "Worker parser must fail closed with AdapterError");
    return { status: "REJECTED", reason_code: error.code, program_id: null, projection: null };
  }
}

function makeRunRoot() {
  const base = mkdtempSync(join(realpathSync(tmpdir()), TEMP_PREFIX));
  const root = join(base, "run");
  mkdirSync(root, { mode: 0o700 });
  const request = buildRequestBody();
  writeFileSync(join(root, "request-body.json"), request.bytes, { flag: "wx", mode: 0o400 });
  writeFileSync(join(root, "egress-manifest.json"), canonicalJsonBytes(request.egress_manifest), {
    flag: "wx",
    mode: 0o400,
  });
  return { base, root, request };
}

function removeOwnedRunRoot(base) {
  const actual = realpathSync(base);
  assert.equal(dirname(actual), realpathSync(tmpdir()));
  assert.ok(basename(actual).startsWith(TEMP_PREFIX));
  assert.ok(lstatSync(actual).isDirectory());
  rmSync(actual, { recursive: true });
}

function readReceipt(root) {
  return JSON.parse(readFileSync(join(root, "transport-receipt.json"), "utf8"));
}

function jsonBodyFor(programId = "IR10") {
  const response = clone(fixture.base_response);
  response.choices[0].message.content = mapping.states.find((state) => state.program_id === programId).canonical_content;
  return Buffer.from(JSON.stringify(response), "utf8");
}

test("request body construction is byte deterministic and credential independent", () => {
  const first = buildRequestBody();
  const second = buildRequestBody();
  assert.ok(first.bytes.equals(second.bytes));
  assert.deepEqual(first.identity, second.identity);
  assert.deepEqual(first.egress_manifest.request_body, first.identity);
  assert.equal(first.egress_manifest.authorization_header_in_request_body, false);
  assert.equal(first.egress_manifest.forbidden_category_payload_count, 0);

  const body = JSON.parse(first.bytes.toString("utf8"));
  assert.deepEqual(Object.keys(body), ["model", "messages", "temperature", "stream", "max_tokens"]);
  assert.equal(body.model, REQUESTED_MODEL);
  assert.equal(body.messages.length, 2);
  assert.equal(body.temperature, 0);
  assert.equal(body.stream, false);
  assert.equal(body.max_tokens, 128);
});

test("all 38 frozen Quality cases agree with the Worker parser on admission and program identity", async (t) => {
  assert.equal(fixture.cases.length, 38);
  for (const fakeCase of fixture.cases) {
    await t.test(fakeCase.case_id, () => {
      const rawBytes = mutateFakeResponse(fixture.base_response, fakeCase.mutation);
      const quality = evaluateChatCompletionResponse(rawBytes);
      const worker = workerProjection(rawBytes);
      assert.equal(quality.status, fakeCase.expected_status);
      assert.equal(worker.status, quality.status);
      assert.equal(worker.program_id, quality.program_id);
      if (worker.status === "REJECTED") assert.equal(typeof worker.reason_code, "string");
    });
  }
});

test("Quality and Worker parsers both fail closed on a non-buffer input", () => {
  const quality = evaluateChatCompletionResponse("not-bytes");
  const worker = workerProjection("not-bytes");
  assert.equal(quality.status, "REJECTED");
  assert.equal(worker.status, "REJECTED");
  assert.equal(worker.reason_code, "RAW_RESPONSE_NOT_BUFFER");
});

test("all four admitted states reach only the accepted finite IR compiler", async (t) => {
  for (const state of mapping.states) {
    await t.test(state.program_id, async () => {
      const selection = parseChatCompletion(jsonBodyFor(state.program_id));
      const compiled = await compileSelection(selection);
      assert.equal(selection.program_id, state.program_id);
      assert.deepEqual(selection.values, state.values);
      assert.equal(compiled.status, state.expected_compiler_status);
      assert.equal(compiled.program_id, state.program_id);
      assert.equal(compiled.outcome_id, state.expected_outcome_id);
      if (compiled.status === "COMPILED") {
        assert.ok(Buffer.isBuffer(compiled.postimage));
        assert.ok(compiled.postimage.length > 0);
      } else {
        assert.equal(compiled.postimage, null);
      }
    });
  }
});

test("offline transport retains one successful local Chat Completion and no credential bytes", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({
      runRoot: owned.root,
      scenario: "success",
      responseBody: jsonBodyFor("IR10"),
    });
    assert.equal(observation.result.code, "RESPONSE_RETAINED");
    assert.equal(observation.result.sent, true);
    assert.equal(observation.result.status, 200);
    assert.equal(observation.request_count, 1);
    assert.equal(observation.request_body_matches_frozen, true);
    assert.equal(observation.authorization_header_present, true);
    assert.equal(observation.credential_persistence_detected, false);
    assert.ok(existsSync(join(owned.root, "raw-response.json")));
    const receipt = readReceipt(owned.root);
    assert.equal(receipt.source_bearing_submission_count, 1);
    assert.equal(receipt.automatic_retry_count, 0);
    assert.equal(receipt.redirect_follow_count, 0);
    assert.equal(receipt.proxy_use_count, 0);
    assert.equal(receipt.dns_lookup_count, 0);
    assert.equal(receipt.authorization_header_persisted_hashed_or_logged, false);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("offline transport rejects a redirect without following it", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({ runRoot: owned.root, scenario: "redirect" });
    assert.equal(observation.result.code, "HTTP_REDIRECT_REJECTED");
    assert.equal(observation.result.sent, true);
    assert.equal(observation.result.status, 302);
    assert.equal(observation.request_count, 1);
    assert.equal(observation.credential_persistence_detected, false);
    const receipt = readReceipt(owned.root);
    assert.equal(receipt.redirect_follow_count, 0);
    assert.equal(receipt.http_status, 302);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("offline transport records a non-200 result without retry", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({ runRoot: owned.root, scenario: "non-200" });
    assert.equal(observation.result.code, "HTTP_NON_200");
    assert.equal(observation.result.sent, true);
    assert.equal(observation.result.status, 503);
    assert.equal(observation.request_count, 1);
    assert.equal(observation.credential_persistence_detected, false);
    assert.equal(readReceipt(owned.root).automatic_retry_count, 0);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("offline transport detects an escaped credential reflection before persistence", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({
      runRoot: owned.root,
      scenario: "credential-reflection",
    });
    assert.equal(observation.result.code, "CREDENTIAL_REFLECTION_DETECTED");
    assert.equal(observation.result.sent, true);
    assert.equal(observation.result.bodyIdentity, null);
    assert.equal(observation.credential_persistence_detected, false);
    assert.equal(existsSync(join(owned.root, "raw-response.json")), false);
    const receipt = readReceipt(owned.root);
    assert.equal(receipt.response_body, null);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("offline transport detects a credential SHA-256 reflection before persistence", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({
      runRoot: owned.root,
      scenario: "credential-digest-reflection",
    });
    assert.equal(observation.result.code, "CREDENTIAL_REFLECTION_DETECTED");
    assert.equal(observation.result.bodyIdentity, null);
    assert.equal(observation.credential_persistence_detected, false);
    assert.equal(existsSync(join(owned.root, "raw-response.json")), false);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("offline transport rejects an oversized streamed response before persistence", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({ runRoot: owned.root, scenario: "oversize" });
    assert.equal(observation.result.code, "RESPONSE_BODY_TOO_LARGE");
    assert.equal(observation.result.sent, true);
    assert.equal(observation.result.bodyIdentity, null);
    assert.equal(observation.credential_persistence_detected, false);
    assert.equal(existsSync(join(owned.root, "raw-response.json")), false);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("offline transport treats a local connection reset after send as terminal", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({ runRoot: owned.root, scenario: "reset" });
    assert.equal(observation.result.code, "REQUEST_FAILED_AFTER_SEND");
    assert.equal(observation.result.sent, true);
    assert.equal(observation.request_count, 1);
    assert.equal(observation.credential_persistence_detected, false);
    assert.equal(readReceipt(owned.root).automatic_retry_count, 0);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("offline transport treats a local response timeout after send as terminal", async () => {
  const owned = makeRunRoot();
  try {
    const observation = await runClosedOfflineTransportScenario({ runRoot: owned.root, scenario: "timeout" });
    assert.equal(observation.result.code, "REQUEST_TIMEOUT_AFTER_SEND");
    assert.equal(observation.result.sent, true);
    assert.equal(observation.request_count, 1);
    assert.equal(observation.credential_persistence_detected, false);
    assert.equal(readReceipt(owned.root).automatic_retry_count, 0);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

test("the create-once call slot blocks a second local submission before connect", async () => {
  const owned = makeRunRoot();
  try {
    const first = await runClosedOfflineTransportScenario({
      runRoot: owned.root,
      scenario: "success",
      responseBody: jsonBodyFor("IR10"),
    });
    assert.equal(first.result.code, "RESPONSE_RETAINED");
    await assert.rejects(
      runClosedOfflineTransportScenario({
        runRoot: owned.root,
        scenario: "success",
        responseBody: jsonBodyFor("IR10"),
      }),
      (error) => error && error.code === "EEXIST",
    );
    assert.equal(first.request_count, 1);
    assert.equal(readReceipt(owned.root).source_bearing_submission_count, 1);
  } finally {
    removeOwnedRunRoot(owned.base);
  }
});

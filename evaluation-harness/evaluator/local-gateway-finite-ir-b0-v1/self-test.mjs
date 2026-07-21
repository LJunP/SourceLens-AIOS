import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  evaluateChatCompletionResponse,
  RAW_RESPONSE_MAX_BYTES,
  REQUESTED_MODEL,
} from "./quality-oracle.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const FIXTURE_ROOT = resolve(REPO_ROOT, "evaluation-harness/fixtures/local-gateway-finite-ir-b0-v1");
const accepted = {
  taskSpec: {
    path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks/SL-P1-REP-001-RANGE-NORMALIZATION/task-spec.json",
    bytes: 2960,
    sha256: "25de6b6f330e09c076521b42a88d60712637e0fc7de7ab1cfe1f9f5d4c223321",
  },
  baseline: {
    path: "evaluation-harness/datasets/p1-representative-task-dataset-v1/shared/baseline-context.json",
    bytes: 377,
    sha256: "64fab9efd47c193af94e3f7baee67072a32497d35c9dc1aee8a804bf32269cb9",
  },
  compiler: {
    path: "evaluation-harness/harness/finite-typed-patch-ir-v1/compiler.mjs",
    bytes: 3814,
    sha256: "013a58a6284270c6808f6cfe815dbea6825b8a43a0a6f885305df23890c7a4f9",
  },
};

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const readJson = async (path) => JSON.parse(await readFile(path, "utf8"));
const clone = (value) => structuredClone(value);

const mutateFakeResponse = (base, mutation, mapping) => {
  if (mutation === "RAW_MALFORMED_OUTER") return Buffer.from("{", "utf8");
  if (mutation === "RAW_OVER_LIMIT") return Buffer.alloc(RAW_RESPONSE_MAX_BYTES + 1, 0x78);
  if (mutation === "OUTER_ARRAY") return Buffer.from("[]", "utf8");

  const response = clone(base);
  const contentByProgram = Object.fromEntries(mapping.states.map((state) => [state.program_id, state.canonical_content]));
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
    case "CONTENT_MARKDOWN": response.choices[0].message.content = `\`\`\`json\n${contentByProgram.IR10}\n\`\`\``; break;
    case "CONTENT_LEADING_SPACE": response.choices[0].message.content = ` ${contentByProgram.IR10}`; break;
    case "CONTENT_TRAILING_NEWLINE": response.choices[0].message.content = `${contentByProgram.IR10}\n`; break;
    case "CONTENT_EXTRA_MEMBER": response.choices[0].message.content = contentByProgram.IR10.replace(/}$/, ',"extra":true}'); break;
    case "CONTENT_WRONG_SCHEMA": response.choices[0].message.content = contentByProgram.IR10.replace("SL-PATCH-IR-CHOICE/1", "SL-PATCH-IR-CHOICE/2"); break;
    case "CONTENT_WRONG_TASK": response.choices[0].message.content = contentByProgram.IR10.replace("@1.0.0", "@2.0.0"); break;
    case "CONTENT_INVALID_VALUE": response.choices[0].message.content = contentByProgram.IR10.replace('"ARG0"]}', '"ARG2"]}'); break;
    case "CONTENT_SHORT_VALUES": response.choices[0].message.content = contentByProgram.IR10.replace('["ARG1","ARG0"]', '["ARG1"]'); break;
    case "CONTENT_DUPLICATE_MEMBER": response.choices[0].message.content = contentByProgram.IR10.replace('{"schema":', '{"schema":"SL-PATCH-IR-CHOICE/1","schema":'); break;
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
};

test("request fixture binds only the accepted TaskSpec projection and baseline context", async () => {
  const fixture = await readJson(resolve(FIXTURE_ROOT, "request-fixture.json"));
  const taskSpecBytes = await readFile(resolve(REPO_ROOT, accepted.taskSpec.path));
  const baselineBytes = await readFile(resolve(REPO_ROOT, accepted.baseline.path));
  const taskSpec = JSON.parse(taskSpecBytes);
  const baseline = JSON.parse(baselineBytes);

  assert.equal(taskSpecBytes.length, accepted.taskSpec.bytes);
  assert.equal(sha256(taskSpecBytes), accepted.taskSpec.sha256);
  assert.equal(baselineBytes.length, accepted.baseline.bytes);
  assert.equal(sha256(baselineBytes), accepted.baseline.sha256);
  assert.equal(fixture.model, REQUESTED_MODEL);
  assert.equal(fixture.user_envelope.task.issue.text, taskSpec.issue.text);
  assert.deepEqual(fixture.user_envelope.task.issue.allowed_clarifications, taskSpec.issue.allowed_clarifications);
  assert.deepEqual(fixture.user_envelope.accepted_baseline_context, baseline);
  assert.deepEqual(Object.keys(fixture.user_envelope), [
    "schema", "task", "accepted_baseline_context", "finite_ir_instruction", "response_contract",
  ]);
  assert.equal(fixture.data_manifest.forbidden_category_payload_count, 0);
  assert.equal(fixture.data_manifest.credential_in_request_body, false);
  assert.equal(fixture.data_manifest.source_test_reference_patch_or_evaluator_bytes_in_messages, false);
  assert.equal(fixture.request_construction.parameters.stream, false);
  assert.equal(fixture.request_construction.parameters.temperature, 0);
  assert.equal(fixture.request_construction.parameters.max_tokens, 128);
});

test("response schema is deeply closed at the only model-controlled object", async () => {
  const schema = await readJson(resolve(FIXTURE_ROOT, "response-schema.json"));
  assert.equal(schema.type, "object");
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, ["schema", "task", "values"]);
  assert.equal(schema.properties.schema.const, "SL-PATCH-IR-CHOICE/1");
  assert.equal(schema.properties.task.const, "SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0");
  assert.equal(schema.properties.values.minItems, 2);
  assert.equal(schema.properties.values.maxItems, 2);
  assert.deepEqual(schema.properties.values.items.enum, ["ARG0", "ARG1"]);
  assert.equal(schema["x-sourcelens-canonical-content"].admitted_content_count, 4);
});

test("four-state mapping binds exact accepted compiler and program bytes", async () => {
  const mapping = await readJson(resolve(FIXTURE_ROOT, "four-state-mapping.json"));
  const compilerBytes = await readFile(resolve(REPO_ROOT, accepted.compiler.path));
  assert.equal(compilerBytes.length, accepted.compiler.bytes);
  assert.equal(sha256(compilerBytes), accepted.compiler.sha256);
  assert.deepEqual(mapping.compiler, {
    path: accepted.compiler.path,
    byte_length: accepted.compiler.bytes,
    sha256: accepted.compiler.sha256,
    version: "SL-PATCH-IR-TRUSTED-COMPILER/1",
  });
  assert.deepEqual(mapping.states.map((state) => state.program_id), ["IR00", "IR01", "IR10", "IR11"]);

  for (const state of mapping.states) {
    const programBytes = await readFile(resolve(REPO_ROOT, state.program_path));
    assert.equal(programBytes.length, state.program_byte_length, state.program_id);
    assert.equal(sha256(programBytes), state.program_sha256, state.program_id);
    const program = JSON.parse(programBytes);
    assert.equal(program.schema, "SL-PATCH-IR/1", state.program_id);
    assert.equal(program.task, mapping.task, state.program_id);
    assert.deepEqual(program.values, state.values, state.program_id);

    const response = {
      id: `chatcmpl-${state.program_id.toLowerCase()}`,
      object: "chat.completion",
      created: 1784600000,
      model: REQUESTED_MODEL,
      choices: [{ index: 0, message: { role: "assistant", content: state.canonical_content }, finish_reason: "stop" }],
    };
    const projection = evaluateChatCompletionResponse(Buffer.from(JSON.stringify(response), "utf8"));
    assert.equal(projection.status, "ACCEPTED", state.program_id);
    assert.equal(projection.program_id, state.program_id, state.program_id);
    assert.equal(projection.program_sha256, state.program_sha256, state.program_id);
    assert.equal(projection.expected_compiler_status, state.expected_compiler_status, state.program_id);
    assert.equal(projection.expected_outcome_id, state.expected_outcome_id, state.program_id);
  }
});

test("offline fake Chat Completions cases cover all admitted states and adversarial rejects", async (t) => {
  const fixture = await readJson(resolve(FIXTURE_ROOT, "fake-chat-completions-cases.json"));
  const mapping = await readJson(resolve(FIXTURE_ROOT, "four-state-mapping.json"));
  assert.equal(fixture.cases.length, 38);

  for (const fakeCase of fixture.cases) {
    await t.test(fakeCase.case_id, () => {
      const raw = mutateFakeResponse(fixture.base_response, fakeCase.mutation, mapping);
      const projection = evaluateChatCompletionResponse(raw);
      assert.equal(projection.status, fakeCase.expected_status);
      assert.equal(projection.reason_code, fakeCase.expected_reason_code);
      assert.equal(projection.program_id, fakeCase.expected_program_id);
    });
  }
});

test("independent oracle rejects non-Buffer input", () => {
  const projection = evaluateChatCompletionResponse("not bytes");
  assert.equal(projection.status, "REJECTED");
  assert.equal(projection.reason_code, "RAW_RESPONSE_NOT_BUFFER");
});

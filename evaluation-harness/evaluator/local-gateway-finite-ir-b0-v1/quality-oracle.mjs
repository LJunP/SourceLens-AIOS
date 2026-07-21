import { createHash } from "node:crypto";

export const QUALITY_ORACLE_VERSION = "P1-062-INDEPENDENT-QUALITY-ORACLE/1";
export const RAW_RESPONSE_MAX_BYTES = 131072;
export const RESPONSE_CONTENT_MAX_BYTES = 512;
export const REQUESTED_MODEL = "gpt-5.6-luna";

const TASK = "SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0";
const PREFIX = `{"schema":"SL-PATCH-IR-CHOICE/1","task":"${TASK}","values":`;
const STATES = [
  ["IR00", "ARG0", "ARG0", "e21da56b4132c121419863bad9e682532963f8b5bc9951af31b23234d9c46736", "COMPILED", "SAFE_WRONG_START_START"],
  ["IR01", "ARG0", "ARG1", "db33a4d4f2a5b21f211344d785785c2b4c246677bbcf68ef0d5e1831cdf3d0c1", "IDENTITY_NO_EFFECT_REJECTION", "IDENTITY_NO_EFFECT_REJECTION"],
  ["IR10", "ARG1", "ARG0", "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc", "COMPILED", "CORRECT_END_START"],
  ["IR11", "ARG1", "ARG1", "0eeca741f57b218ee175308080de3ada3db1b4eb93222bd252cac9ed6e2c66f7", "COMPILED", "SAFE_WRONG_END_END"],
];

const ADMITTED = new Map(STATES.map(([programId, left, right, programSha256, compilerStatus, outcomeId]) => {
  const content = `${PREFIX}["${left}","${right}"]}`;
  return [content, Object.freeze({
    values: Object.freeze([left, right]),
    program_id: programId,
    program_path: `evaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/${programId.toLowerCase()}.json`,
    program_sha256: programSha256,
    expected_compiler_status: compilerStatus,
    expected_outcome_id: outcomeId,
  })];
}));

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const isRecord = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

class ClosedJsonParser {
  constructor(text) {
    this.text = text;
    this.offset = 0;
  }

  parse() {
    this.skipWhitespace();
    const value = this.parseValue();
    this.skipWhitespace();
    if (this.offset !== this.text.length) throw new Error("trailing JSON bytes");
    return value;
  }

  skipWhitespace() {
    while (this.offset < this.text.length && /[\u0020\u000a\u000d\u0009]/u.test(this.text[this.offset])) {
      this.offset += 1;
    }
  }

  parseValue() {
    const token = this.text[this.offset];
    if (token === "{") return this.parseObject();
    if (token === "[") return this.parseArray();
    if (token === '"') return this.parseString();
    if (this.text.startsWith("true", this.offset)) return this.consumeLiteral("true", true);
    if (this.text.startsWith("false", this.offset)) return this.consumeLiteral("false", false);
    if (this.text.startsWith("null", this.offset)) return this.consumeLiteral("null", null);
    return this.parseNumber();
  }

  consumeLiteral(literal, value) {
    this.offset += literal.length;
    return value;
  }

  parseString() {
    const start = this.offset;
    this.offset += 1;
    while (this.offset < this.text.length) {
      const code = this.text.charCodeAt(this.offset);
      if (code === 0x22) {
        this.offset += 1;
        return JSON.parse(this.text.slice(start, this.offset));
      }
      if (code < 0x20) throw new Error("unescaped control character");
      if (code === 0x5c) {
        this.offset += 1;
        if (this.offset >= this.text.length) throw new Error("truncated escape");
        if (this.text[this.offset] === "u") {
          const hex = this.text.slice(this.offset + 1, this.offset + 5);
          if (!/^[0-9a-fA-F]{4}$/u.test(hex)) throw new Error("invalid unicode escape");
          this.offset += 4;
        } else if (!/["\\/bfnrt]/u.test(this.text[this.offset])) {
          throw new Error("invalid escape");
        }
      }
      this.offset += 1;
    }
    throw new Error("unterminated string");
  }

  parseNumber() {
    const match = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/u.exec(this.text.slice(this.offset));
    if (!match) throw new Error("invalid JSON value");
    this.offset += match[0].length;
    const value = Number(match[0]);
    if (!Number.isFinite(value)) throw new Error("non-finite number");
    return value;
  }

  parseArray() {
    this.offset += 1;
    const result = [];
    this.skipWhitespace();
    if (this.text[this.offset] === "]") {
      this.offset += 1;
      return result;
    }
    while (true) {
      this.skipWhitespace();
      result.push(this.parseValue());
      this.skipWhitespace();
      if (this.text[this.offset] === "]") {
        this.offset += 1;
        return result;
      }
      if (this.text[this.offset] !== ",") throw new Error("array separator missing");
      this.offset += 1;
    }
  }

  parseObject() {
    this.offset += 1;
    const result = Object.create(null);
    const keys = new Set();
    this.skipWhitespace();
    if (this.text[this.offset] === "}") {
      this.offset += 1;
      return result;
    }
    while (true) {
      this.skipWhitespace();
      if (this.text[this.offset] !== '"') throw new Error("object key missing");
      const key = this.parseString();
      if (keys.has(key)) throw new Error("duplicate object member");
      keys.add(key);
      this.skipWhitespace();
      if (this.text[this.offset] !== ":") throw new Error("object colon missing");
      this.offset += 1;
      this.skipWhitespace();
      result[key] = this.parseValue();
      this.skipWhitespace();
      if (this.text[this.offset] === "}") {
        this.offset += 1;
        return result;
      }
      if (this.text[this.offset] !== ",") throw new Error("object separator missing");
      this.offset += 1;
    }
  }
}

const rejected = (reasonCode, rawBytes) => Object.freeze({
  schema: "P1-062-QUALITY-PROJECTION/1",
  oracle_version: QUALITY_ORACLE_VERSION,
  status: "REJECTED",
  reason_code: reasonCode,
  raw_response_byte_length: Buffer.isBuffer(rawBytes) ? rawBytes.length : null,
  raw_response_sha256: Buffer.isBuffer(rawBytes) ? sha256(rawBytes) : null,
  returned_model: null,
  content_byte_length: null,
  content_sha256: null,
  values: null,
  program_id: null,
  program_path: null,
  program_sha256: null,
  expected_compiler_status: null,
  expected_outcome_id: null,
});

const usageIsValid = (usage) => {
  if (usage === undefined) return true;
  if (!isRecord(usage)) return false;
  for (const key of ["prompt_tokens", "completion_tokens", "total_tokens"]) {
    if (usage[key] !== undefined && (!Number.isSafeInteger(usage[key]) || usage[key] < 0)) return false;
  }
  return true;
};

export function evaluateChatCompletionResponse(rawBytes) {
  if (!Buffer.isBuffer(rawBytes)) return rejected("RAW_RESPONSE_NOT_BUFFER", rawBytes);
  if (rawBytes.length > RAW_RESPONSE_MAX_BYTES) return rejected("RAW_RESPONSE_TOO_LARGE", rawBytes);

  let outer;
  try {
    outer = new ClosedJsonParser(rawBytes.toString("utf8")).parse();
  } catch {
    return rejected("OUTER_JSON_INVALID_OR_DUPLICATE", rawBytes);
  }

  if (!isRecord(outer)) return rejected("OUTER_NOT_OBJECT", rawBytes);
  if (outer.object !== "chat.completion") return rejected("OBJECT_MISMATCH", rawBytes);
  if (typeof outer.id !== "string" || outer.id.length === 0) return rejected("ID_INVALID", rawBytes);
  if (!Number.isSafeInteger(outer.created) || outer.created < 0) return rejected("CREATED_INVALID", rawBytes);
  if (outer.model !== REQUESTED_MODEL) return rejected("MODEL_MISMATCH", rawBytes);
  if (!Array.isArray(outer.choices) || outer.choices.length !== 1) return rejected("CHOICES_NOT_SINGLE", rawBytes);

  const choice = outer.choices[0];
  if (!isRecord(choice)) return rejected("CHOICE_INVALID", rawBytes);
  if (choice.index !== 0) return rejected("CHOICE_INDEX_INVALID", rawBytes);
  if (choice.finish_reason !== "stop") return rejected("FINISH_REASON_NOT_STOP", rawBytes);
  if (!isRecord(choice.message)) return rejected("MESSAGE_INVALID", rawBytes);

  const message = choice.message;
  if (message.role !== "assistant") return rejected("MESSAGE_ROLE_NOT_ASSISTANT", rawBytes);
  if (typeof message.content !== "string") return rejected("MESSAGE_CONTENT_NOT_STRING", rawBytes);
  const contentBytes = Buffer.from(message.content, "utf8");
  if (contentBytes.length > RESPONSE_CONTENT_MAX_BYTES) return rejected("MESSAGE_CONTENT_TOO_LARGE", rawBytes);
  if (message.refusal !== undefined && message.refusal !== null) return rejected("MESSAGE_REFUSAL_PRESENT", rawBytes);
  if (message.tool_calls !== undefined || message.function_call !== undefined || message.audio !== undefined) {
    return rejected("MESSAGE_TOOL_CALL_PRESENT", rawBytes);
  }

  const admitted = ADMITTED.get(message.content);
  if (!admitted) return rejected("CONTENT_NOT_EXACTLY_ADMITTED", rawBytes);
  if (!usageIsValid(outer.usage)) return rejected("USAGE_INVALID", rawBytes);

  return Object.freeze({
    schema: "P1-062-QUALITY-PROJECTION/1",
    oracle_version: QUALITY_ORACLE_VERSION,
    status: "ACCEPTED",
    reason_code: null,
    raw_response_byte_length: rawBytes.length,
    raw_response_sha256: sha256(rawBytes),
    returned_model: outer.model,
    content_byte_length: contentBytes.length,
    content_sha256: sha256(contentBytes),
    values: admitted.values,
    program_id: admitted.program_id,
    program_path: admitted.program_path,
    program_sha256: admitted.program_sha256,
    expected_compiler_status: admitted.expected_compiler_status,
    expected_outcome_id: admitted.expected_outcome_id,
  });
}

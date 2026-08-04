import {
  buildNormalizedProviderResponse,
  patchIrBytes,
} from "../p1-149-accepted-execution-spine/patch-ir-v2.mjs";
import {
  assert,
  parseExactJsonBytes,
  sha256,
} from "./shared.mjs";

export const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;

function safeString(value, label, maximum = 512) {
  assert(
    typeof value === "string" && value.length >= 1 && value.length <= maximum && !value.includes("\0"),
    "CHAT_COMPLETION_SCHEMA_INVALID",
    `${label} is invalid`,
  );
  return value;
}

function safeUsageInteger(value, label) {
  assert(
    Number.isSafeInteger(value) && value >= 0,
    "PROVIDER_USAGE_INVALID",
    `${label} must be a non-negative exact integer`,
  );
  return value;
}

export function validateUsage(value) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "PROVIDER_USAGE_MISSING",
    "Provider usage is missing or null",
  );
  const promptTokens = safeUsageInteger(value.prompt_tokens, "prompt_tokens");
  const completionTokens = safeUsageInteger(value.completion_tokens, "completion_tokens");
  const totalTokens = safeUsageInteger(value.total_tokens, "total_tokens");
  assert(
    promptTokens + completionTokens === totalTokens,
    "PROVIDER_USAGE_TOTAL_DRIFT",
    "Provider usage total does not equal prompt plus completion tokens",
  );
  return {
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: totalTokens,
  };
}

export function parseChatCompletionBytes(bytes, { diagnostic = false } = {}) {
  const value = parseExactJsonBytes(bytes, {
    label: "raw Chat Completions response",
    canonical: false,
    maximumBytes: MAX_RESPONSE_BYTES,
  });
  assert(value !== null && typeof value === "object" && !Array.isArray(value), "CHAT_COMPLETION_SCHEMA_INVALID", "response root must be an object");
  const responseId = safeString(value.id, "response id", 512);
  assert(Array.isArray(value.choices) && value.choices.length >= 1, "CHAT_COMPLETION_CHOICES_MISSING", "response choices are missing");
  const choice = value.choices[0];
  assert(choice !== null && typeof choice === "object" && !Array.isArray(choice), "CHAT_COMPLETION_SCHEMA_INVALID", "first choice is invalid");
  const message = choice.message;
  assert(message !== null && typeof message === "object" && !Array.isArray(message), "CHAT_COMPLETION_SCHEMA_INVALID", "choice message is invalid");
  const content = safeString(message.content, "assistant content", MAX_RESPONSE_BYTES);
  const usage = validateUsage(value.usage);
  if (diagnostic) {
    assert(
      content.trim() === "READY",
      "DIAGNOSTIC_CONTENT_INVALID",
      "diagnostic assistant content must trim to exactly READY",
    );
  }
  const completionStatus = diagnostic
    ? "STRICT_DIAGNOSTIC_COMPLETION"
    : "CHAT_COMPLETION_RECEIVED";
  return {
    response_id: responseId,
    content,
    usage,
    completion_status: completionStatus,
  };
}

export function normalizePatchResponse({ cell, rawResponseBytes }) {
  const chat = parseChatCompletionBytes(rawResponseBytes);
  const patchValue = parseExactJsonBytes(Buffer.from(chat.content, "utf8"), {
    label: `${cell.cell_id} Patch IR content`,
    canonical: false,
    maximumBytes: 1024 * 1024,
  });
  const irBytes = patchIrBytes(patchValue);
  const responseId = `P1-207-${cell.cell_id}-${sha256(rawResponseBytes).slice(0, 16)}`;
  return {
    chat,
    patch_ir_bytes: irBytes,
    normalized_response_bytes: buildNormalizedProviderResponse({
      responseId,
      taskId: cell.task_id,
      patchIrBytes: irBytes,
    }),
  };
}

export function validateObservedPeer(address, port) {
  assert(address === "127.0.0.1", "NON_LOOPBACK_PEER_REJECTED", "observed peer is not exact IPv4 loopback");
  assert(port === 8787, "LOOPBACK_PORT_DRIFT", "observed peer port is not 8787");
  return { peer_address: address, peer_port: port };
}

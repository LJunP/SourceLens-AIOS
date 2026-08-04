#!/usr/bin/env node

import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

import { canonicalJson } from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import { normalizeProviderUsageForReceipt } from "./evaluate.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";

export function testPostformalUsageNormalization() {
  const normalized = normalizeProviderUsageForReceipt({
    prompt_tokens: 17,
    completion_tokens: 5,
    total_tokens: 22,
    prompt_tokens_details: { cached_tokens: 0 },
    completion_tokens_details: { reasoning_tokens: 0 },
  });
  const expected = { prompt_tokens: 17, completion_tokens: 5, total_tokens: 22 };
  let invalidTotalRejected = false;
  try {
    normalizeProviderUsageForReceipt({ prompt_tokens: 17, completion_tokens: 5, total_tokens: 23 });
  } catch (error) {
    invalidTotalRejected = (error.code ?? error.reasonCode) === "PROVIDER_USAGE_TOTAL_DRIFT";
  }
  const pass = isDeepStrictEqual(normalized, expected) && invalidTotalRejected;
  return {
    schema_version: "p1-207-postformal-usage-normalization-test/v1",
    task_id: TASK_ID,
    status: pass ? "PASS" : "NON_PASS",
    optional_usage_details_ignored_after_counter_validation: isDeepStrictEqual(normalized, expected),
    invalid_total_rejected: invalidTotalRejected,
    provider_requests: 0,
    secret_reads: 0,
  };
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  const result = testPostformalUsageNormalization();
  process.stdout.write(`${canonicalJson(result)}\n`);
  if (result.status !== "PASS") process.exitCode = 1;
}

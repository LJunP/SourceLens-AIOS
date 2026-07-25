import { readFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";

import { identityOf } from "./core.mjs";
import {
  REPOSITORY_ROOT,
  validatePreregistrationBundle as validateBundle,
} from "./preflight.mjs";
import {
  validateChatCompletionsRequest,
  validateProviderResponseOutcome,
} from "./disclosure.mjs";

export function validatePreregistrationBundle({
  repositoryRoot = REPOSITORY_ROOT,
  fixtureRoot,
  executableReceipt = null,
}) {
  const path = resolve(fixtureRoot, "preregistration.json");
  const bytes = readFileSync(path);
  const rel = relative(resolve(repositoryRoot), path).split(sep).join("/");
  const result = validateBundle({
    repositoryRoot: resolve(repositoryRoot),
    preregistrationBinding: { path: rel, ...identityOf(bytes) },
    executableReceipt,
  });
  return {
    status: "PASS",
    scheduled_runs: result.matrix.schedule.length,
    provider_requests: 0,
    secret_reads: 0,
    executable_identity_receipt_required_before_provider:
      executableReceipt === null,
  };
}

export function validateFormalRequest(input) {
  return validateChatCompletionsRequest(input);
}

export function validateResponseSafe(bytes, allowedOperationIds) {
  return validateProviderResponseOutcome(bytes, allowedOperationIds);
}

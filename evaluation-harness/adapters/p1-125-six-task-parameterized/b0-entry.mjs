#!/usr/bin/env node

import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  assertFalseEffects,
  canonicalJson,
  exactKeys,
} from "../../harness/p1-125-six-task-parameterized/core.mjs";
import {
  ADAPTER_VERSION,
  commonResultBase,
  emit,
  loadExecutionRequest,
  markTargetStarted,
  parseEntryArguments,
  readBoundJson,
  validateEntryPaths,
} from "./common.mjs";
import { acceptedTaskBinding } from "./dataset-bindings.mjs";

export const ADAPTER_ID = "B0";

export function executeB0(executionRequestPath) {
  const loaded = loadExecutionRequest(executionRequestPath, ADAPTER_ID);
  const taskRecord = readBoundJson(loaded.request.task_spec, "TaskSpec");
  const task = taskRecord.value;
  const environment = readBoundJson(loaded.request.environment_snapshot, "EnvironmentSnapshot").value;
  const configuration = readBoundJson(loaded.request.system_configuration, "B0 SystemConfiguration").value;
  const input = readBoundJson(loaded.request.adapter_input, "B0 frozen result input").value;
  const repositoryRoot = resolve(fileURLToPath(new URL("../../..", import.meta.url)));
  acceptedTaskBinding(repositoryRoot, task, taskRecord.path);

  assert(
    configuration.adapter_id === ADAPTER_ID
      && configuration.adapter_version === ADAPTER_VERSION
      && configuration.loop_limit === 1
      && Array.isArray(configuration.enabled_tools)
      && configuration.enabled_tools.length === 0,
    "B0_CONFIGURATION_REJECTED",
    "B0 must use its exact adapter version, no tools and loop_limit=1",
  );
  assert(
    loaded.request.limits.max_tool_calls === 0
      && loaded.request.limits.max_cost_usd === 0
      && loaded.request.limits.max_model_tokens >= 0,
    "B0_BUDGET_REJECTED",
    "B0 offline result conformance requires zero tools and zero cost",
  );
  assert(
    environment.model.provider === "none-offline"
      && configuration.feature_flags.live_model_invoked === false
      && configuration.feature_flags.provider_invoked === false
      && environment.model.parameters.live_model_invoked === false
      && environment.model.parameters.provider_invoked === false,
    "B0_PROVENANCE_REJECTED",
    "B0 must remain provider-neutral with no live model invocation",
  );

  exactKeys(input, ["task_id", "summary", "changed_paths", "tests"], "B0 frozen result input");
  assert(
    input.task_id === task.task_id
      && typeof input.summary === "string"
      && input.summary.length > 0
      && Array.isArray(input.changed_paths)
      && input.changed_paths.every((item) => typeof item === "string")
      && Array.isArray(input.tests)
      && input.tests.every((item) => typeof item === "string"),
    "B0_INPUT_REJECTED",
    "B0 result does not match the frozen response shape",
  );

  const sentinel = markTargetStarted(loaded.request, loaded.sentinel, {
    mode: "FROZEN_PROVIDER_NEUTRAL_RESULT_CONFORMANCE",
  });
  const actions = [{
    sequence: 1,
    action_id: `${loaded.request.run_id}:1`,
    action_type: "frozen_result_admission",
    tool_class: null,
    input_sha256: loaded.request.adapter_input.sha256,
    output_sha256: loaded.request.adapter_input.sha256,
    exit_code: 0,
  }];
  const result = {
    ...commonResultBase({
      request: loaded.request,
      task,
      configuration,
      actions,
      usage: {
        input_tokens: 0,
        output_tokens: 0,
        tool_calls: 0,
        retries: 0,
        human_interventions: 0,
        cost_usd: 0,
        latency_ms: 0,
      },
      targetSentinel: sentinel,
    }),
    result: input,
    provenance: {
      kind: "QUALITY_FROZEN_PROVIDER_NEUTRAL_CONFORMANCE_RESULT",
      live_model_invoked: false,
      provider_invoked: false,
      model_performance_sample: false,
    },
    source_mutation_observed: false,
    rollback: {
      required: false,
      status: "NOT_APPLICABLE_NO_SOURCE_MUTATION",
    },
  };
  assertFalseEffects(result.requested_external_effects, "B0 result requested external effects");
  assertFalseEffects(result.observed_external_effects, "B0 observed external effects");
  return result;
}

function main() {
  const args = parseEntryArguments(process.argv.slice(2));
  const loaded = loadExecutionRequest(args.requestPath, ADAPTER_ID);
  validateEntryPaths(args, loaded);
  emit(executeB0(args.requestPath));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stdout.write(`${canonicalJson({
      schema_version: "1.0",
      record_type: "p1_125_adapter_failure",
      adapter_id: ADAPTER_ID,
      verdict: "NON_PASS",
      reason_code: error.code ?? "UNCAUGHT_EXCEPTION",
      message: `${error.name}: ${error.message}`,
      requested_external_effects: FALSE_EXTERNAL_EFFECTS,
      observed_external_effects: FALSE_EXTERNAL_EFFECTS,
    })}\n`);
    process.exit(1);
  }
}

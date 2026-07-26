import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  canonicalBytes,
  canonicalJson,
  sha256,
} from "../../harness/p1-125-six-task-parameterized/core.mjs";

const REMOVED_FIELDS = Object.freeze([
  "run_id",
  "repetition_id",
  "started_at",
  "ended_at",
  "usage.latency_ms",
]);

function stableAction(action) {
  const common = {
    sequence: action.sequence,
    action_type: action.action_type,
    tool_class: action.tool_class,
    exit_code: action.exit_code,
  };
  const optional = [
    "path",
    "paths",
    "matches",
    "needle_sha256",
    "query_sha256",
    "sha256",
    "byte_length",
    "before_sha256",
    "after_sha256",
    "command_id",
    "expected_exit_matched",
    "operation_id",
  ];
  for (const key of optional) {
    if (Object.hasOwn(action, key)) common[key] = action[key];
  }
  return common;
}

function stableRollback(rollback) {
  const stable = {
    required: rollback.required ?? (rollback.status !== "NOT_APPLICABLE_NO_SOURCE_MUTATION"),
    status: rollback.status,
  };
  for (const key of [
    "pre_tree_source_sha256",
    "post_patch_source_sha256",
    "post_rollback_source_sha256",
    "source_exact_after_scan",
  ]) {
    if (Object.hasOwn(rollback, key)) stable[key] = rollback[key];
  }
  if (Array.isArray(rollback.files)) {
    stable.files = rollback.files.map((entry) => ({
      path: entry.path,
      sha256: entry.sha256,
      byte_length: entry.byte_length,
      matches: entry.matches,
    }));
  }
  return stable;
}

function stableAdapterSemantics(adapterResult) {
  const semantics = {
    result: adapterResult.result,
    provenance: {
      kind: adapterResult.provenance.kind,
      live_model_invoked: adapterResult.provenance.live_model_invoked,
      provider_invoked: adapterResult.provenance.provider_invoked,
      model_performance_sample: adapterResult.provenance.model_performance_sample,
    },
    actions: adapterResult.actions.map(stableAction),
    requested_external_effects: adapterResult.requested_external_effects,
    observed_external_effects: adapterResult.observed_external_effects,
    source_mutation_observed: adapterResult.source_mutation_observed,
    rollback: stableRollback(adapterResult.rollback),
  };
  if (adapterResult.adapter_id === "B2") {
    semantics.provenance.p0_binding = adapterResult.provenance.p0_binding;
    semantics.scan = {
      scan_result_schema_version: adapterResult.scan_result.scan_result_schema_version,
      language: adapterResult.scan_result.language,
      file_tree: adapterResult.scan_result.file_tree,
      framework: adapterResult.scan_result.framework,
      structure: adapterResult.scan_result.structure,
      code_quality: adapterResult.scan_result.code_quality,
      symbols: adapterResult.scan_result.symbols,
      relations: adapterResult.scan_result.relations,
      graph: adapterResult.scan_result.graph,
    };
  }
  return semantics;
}

export function buildStableProjection({ runRecord, adapterResult }) {
  assert(
    runRecord.run_id === adapterResult.run_id
      && runRecord.task_id === adapterResult.task_id
      && runRecord.adapter_id === adapterResult.adapter_id
      && runRecord.adapter_version === adapterResult.adapter_version,
    "RUN_RECORD_BINDING_INVALID",
    "stable projection inputs do not join",
  );
  assert(
    canonicalJson(adapterResult.requested_external_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS)
      && canonicalJson(adapterResult.observed_external_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_FORBIDDEN",
    "stable projection cannot admit external effects",
  );
  return {
    schema_version: "p1-125-stable-replay-projection/v1",
    record_type: "p1_125_documented_adapter_stable_projection",
    projection_contract: {
      removed_fields: REMOVED_FIELDS,
      system_configuration_id: "PAIR_CONFIGURATION",
      physical_artifact_identities_retained_in_raw_run_record_and_trace: true,
      stochastic_differences_retained_in_raw_evidence: true,
      additional_normalization: false,
    },
    task_id: runRecord.task_id,
    dataset_version: runRecord.dataset_version,
    adapter_id: runRecord.adapter_id,
    adapter_version: runRecord.adapter_version,
    environment_snapshot_id: runRecord.environment_snapshot_id,
    system_configuration_id: "PAIR_CONFIGURATION",
    terminal_status: runRecord.terminal_status,
    stop_reason_code: runRecord.stop_reason_code,
    invalid_run_reason: runRecord.invalid_run_reason,
    error_taxonomy: runRecord.error_taxonomy,
    usage: {
      input_tokens: runRecord.usage.input_tokens,
      output_tokens: runRecord.usage.output_tokens,
      tool_calls: runRecord.usage.tool_calls,
      retries: runRecord.usage.retries,
      human_interventions: runRecord.usage.human_interventions,
      cost_usd: runRecord.usage.cost_usd,
    },
    policy_violations: runRecord.policy_violations,
    adapter_semantics: stableAdapterSemantics(adapterResult),
  };
}

export function projectionIdentity(projection) {
  const bytes = canonicalBytes(projection);
  return {
    bytes,
    sha256: sha256(bytes),
    byte_length: bytes.length,
  };
}

#!/usr/bin/env node

import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import {
  assert,
  bytesIdentity,
  canonicalJson,
  writeJsonCreateOnce,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import { evaluateEvidence } from "./evaluate.mjs";
import { POSTFORMAL_AUTHORIZED_IDENTITIES } from "./postformal-control-binding.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";
const OUTPUTS = Object.freeze({
  report: "report/REPRODUCIBLE_BASELINE_REPORT.json",
  rebuild: "report/REPORT_REBUILD_RECEIPT.json",
  evaluator: "reviews/INDEPENDENT_EVALUATOR_RECEIPT.json",
});

export function finalizeFormal(evidenceRoot) {
  const root = resolve(evidenceRoot);
  assert(root === POSTFORMAL_AUTHORIZED_IDENTITIES.formal_root,
    "POSTFORMAL_FORMAL_ROOT_INVALID", "finalizer is restricted to the exact completed formal Evidence root");
  for (const relativePath of Object.values(OUTPUTS)) {
    assert(!existsSync(`${root}/${relativePath}`),
      "POSTFORMAL_OUTPUT_PREEXISTS", `postformal output must be create-once: ${relativePath}`);
  }

  const evaluator = evaluateEvidence(root);
  assert(evaluator.schema_version === "p1-207-postformal-independent-evaluator-receipt/v1"
      && evaluator.status === "PASS"
      && evaluator.mode === "FORMAL"
      && evaluator.task_id === TASK_ID
      && evaluator.denominator === 36
      && evaluator.false_accepts === 0
      && evaluator.raw_evidence_only_reconstruction === true
      && evaluator.generated_report_used_as_input === false
      && evaluator.worker_success_fields_trusted === false,
  "POSTFORMAL_EVALUATOR_NON_PASS", "postformal evaluator did not return the exact formal PASS contract");

  const reportIdentity = writeJsonCreateOnce(root, OUTPUTS.report, evaluator.report);
  assert(bytesIdentity(Buffer.from(`${canonicalJson(evaluator.report)}\n`, "utf8")).sha256 === reportIdentity.sha256
      && evaluator.report_identity.sha256 === reportIdentity.sha256
      && evaluator.report_identity.byte_length === reportIdentity.byte_length,
  "POSTFORMAL_REPORT_IDENTITY_INVALID", "written report differs from the independently reconstructed bytes");
  const evaluatorIdentity = writeJsonCreateOnce(root, OUTPUTS.evaluator, evaluator);
  const rebuild = {
    schema_version: "p1-207-postformal-report-rebuild-receipt/v1",
    task_id: TASK_ID,
    status: "PASS",
    mode: "FORMAL",
    denominator: evaluator.denominator,
    taxonomy: evaluator.taxonomy,
    vtsr: evaluator.vtsr,
    false_accepts: evaluator.false_accepts,
    raw_evidence_only: true,
    generated_report_used_as_input: false,
    worker_success_fields_trusted: false,
    execution_source: evaluator.execution_source,
    postformal_finalizer_source: evaluator.postformal_finalizer_source,
    evidence_manifest: evaluator.evidence_manifest,
    transitive_accepted_control_binding: evaluator.accepted_p1_129_control.binding_chain,
    report: reportIdentity,
    evaluator: evaluatorIdentity,
    external_effects: {
      network: false,
      provider: false,
      secret: false,
      remote: false,
      production: false,
      public: false,
    },
  };
  const rebuildIdentity = writeJsonCreateOnce(root, OUTPUTS.rebuild, rebuild);
  return {
    schema_version: "p1-207-postformal-finalization-result/v1",
    task_id: TASK_ID,
    status: "PASS",
    denominator: evaluator.denominator,
    taxonomy: evaluator.taxonomy,
    vtsr: evaluator.vtsr,
    report: reportIdentity,
    independent_evaluator: evaluatorIdentity,
    report_rebuild_receipt: rebuildIdentity,
    formal_manifest_bound_raw_evidence_modified: false,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: rebuild.external_effects,
  };
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  try {
    assert(process.argv.length === 3,
      "CLI_USAGE_INVALID", "usage: finalize-formal.mjs EXACT_FORMAL_EVIDENCE_ROOT");
    process.stdout.write(`${canonicalJson(finalizeFormal(process.argv[2]))}\n`);
  } catch (error) {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-207-postformal-finalization-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: error.reasonCode ?? error.code ?? error.name,
      message: error.message,
    })}\n`);
    process.exitCode = 1;
  }
}

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  cleanupOwnedRoot,
  createDisposableRoot,
} from "../p1-149-accepted-execution-spine/core.mjs";
import {
  REPOSITORY_ROOT,
} from "./plan.mjs";
import {
  FALSE_EXTERNAL_EFFECTS,
  assert,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  parseExactJsonBytes,
  safeRegularFile,
  writeBytesCreateOnce,
  writeJsonCreateOnce,
} from "./shared.mjs";

const NODE = "/usr/local/bin/node";
const WORKER = join(REPOSITORY_ROOT, "evaluation-harness/harness/p1-125-six-task-parameterized/run.mjs");
const MATRIX = join(REPOSITORY_ROOT, "evaluation-harness/evaluator/p1-125-six-task-parameterized/run-matrix.mjs");
const SELECTED_OUTPUTS = Object.freeze([
  "adapter-execution-request.json",
  "adapter-command-ledger.json",
  "adapter-result.json",
  "trace.jsonl",
  "run-record.json",
  "stable-projection.json",
]);

function sourceIdentity(path) {
  const bytes = readFileSync(safeRegularFile(path, "accepted control source"));
  return { path: path.slice(REPOSITORY_ROOT.length + 1), ...bytesIdentity(bytes) };
}

function validateSummary(summary) {
  assert(
    summary.status === "PASS"
      && summary.accepted_task_count === 6
      && summary.positive_runs === 36
      && summary.distinct_positive_run_roots === 36
      && summary.exact_stable_pairs === 18
      && summary.b1_exact_rollbacks === 12
      && summary.b2_real_repository_analysis_scan_children === 12
      && summary.negative_cases === 53
      && summary.false_accepts === 0
      && summary.nonowned_residuals === 0
      && canonicalJson(summary.external_effects) === canonicalJson(FALSE_EXTERNAL_EFFECTS),
    "ACCEPTED_P1_129_CONTROL_NON_PASS",
    "accepted P1-129 control did not preserve its exact accepted Gate",
  );
}

export function runAcceptedP1129Control(evidenceRoot, plan) {
  const disposable = createDisposableRoot("p1207-adapter-control");
  try {
    const outputRoot = join(disposable.root, "matrix");
    const result = spawnSync(NODE, [MATRIX, "--worker-entry", WORKER, "--output-root", outputRoot], {
      cwd: REPOSITORY_ROOT,
      shell: false,
      encoding: null,
      timeout: 20 * 60 * 1000,
      maxBuffer: 16 * 1024 * 1024,
      env: {
        HOME: process.env.HOME ?? "",
        PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        LANG: "C",
        LC_ALL: "C",
        TZ: "UTC",
        NODE_OPTIONS: "--no-warnings",
      },
    });
    const stdout = Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0);
    const stderr = Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0);
    assert(!result.error, "ACCEPTED_P1_129_CONTROL_EXECUTION_FAILED", result.error?.message ?? "accepted control failed", {
      status: result.status,
      signal: result.signal,
      stdout: stdout.toString("utf8").slice(0, 4096),
      stderr: stderr.toString("utf8").slice(0, 4096),
    });
    assert(result.status === 0 && result.signal === null, "ACCEPTED_P1_129_CONTROL_NON_PASS", "accepted control process was not successful", {
      status: result.status,
      signal: result.signal,
      stdout: stdout.toString("utf8").slice(0, 4096),
      stderr: stderr.toString("utf8").slice(0, 4096),
    });
    const summaryPath = join(outputRoot, "quality-formal-summary.json");
    const summaryBytes = readFileSync(safeRegularFile(summaryPath, "accepted P1-129 summary"));
    const summary = parseExactJsonBytes(summaryBytes, { label: "accepted P1-129 summary", canonical: true });
    validateSummary(summary);
    const negativeResultsBytes = readFileSync(
      safeRegularFile(join(outputRoot, "negative-results.json"), "accepted P1-129 negative results"),
    );
    writeBytesCreateOnce(evidenceRoot, "accepted-controls/p1-129/stdout.log", stdout);
    writeBytesCreateOnce(evidenceRoot, "accepted-controls/p1-129/stderr.log", stderr);
    writeBytesCreateOnce(evidenceRoot, "accepted-controls/p1-129/quality-formal-summary.json", summaryBytes);
    writeBytesCreateOnce(evidenceRoot, "accepted-controls/p1-129/negative-results.json", negativeResultsBytes);

    const cells = plan.cells.map((cell) => {
      const caseRoot = join(outputRoot, "positive", cell.task_id, cell.profile_id);
      const copiedArtifacts = [];
      const requestBytes = readFileSync(safeRegularFile(join(caseRoot, "request.json"), `${cell.cell_id} accepted adapter request`));
      copiedArtifacts.push(writeBytesCreateOnce(
        evidenceRoot,
        `accepted-controls/p1-129/cells/${cell.cell_id}/request.json`,
        requestBytes,
      ));
      for (const name of SELECTED_OUTPUTS) {
        const bytes = readFileSync(
          safeRegularFile(join(caseRoot, "worker-output", name), `${cell.cell_id} accepted adapter ${name}`),
        );
        copiedArtifacts.push(writeBytesCreateOnce(
          evidenceRoot,
          `accepted-controls/p1-129/cells/${cell.cell_id}/${name}`,
          bytes,
        ));
      }
      return {
        cell_id: cell.cell_id,
        task_id: cell.task_id,
        adapter_id: cell.adapter_id,
        profile_id: cell.profile_id,
        repetition_id: cell.repetition_id,
        copied_artifacts: copiedArtifacts,
      };
    });

    const receipt = {
      schema_version: "p1-207-accepted-p1-129-control-receipt/v1",
      status: "PASS",
      worker_source: sourceIdentity(WORKER),
      evaluator_source: sourceIdentity(MATRIX),
      command: [NODE, MATRIX, "--worker-entry", WORKER, "--output-root", "OWNED_DISPOSABLE_ROOT/matrix"],
      exit_status: result.status,
      signal: result.signal,
      stdout: bytesIdentity(stdout),
      stderr: bytesIdentity(stderr),
      summary: bytesIdentity(summaryBytes),
      negative_results: bytesIdentity(negativeResultsBytes),
      accepted_task_count: 6,
      positive_runs: 36,
      negative_cases: 53,
      false_accepts: 0,
      b2_real_repository_analysis_scan_children: 12,
      cells,
      disposable_root_cleaned: true,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
    writeJsonCreateOnce(evidenceRoot, "accepted-controls/P1_129_CONTROL_RECEIPT.json", receipt);
    return receipt;
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

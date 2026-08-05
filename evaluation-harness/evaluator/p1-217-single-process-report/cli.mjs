#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

import {
  AdmissionError,
  TASK_ID,
  admitAndReconstruct,
  assertInputUnchanged,
  validateTopology,
  writeCreateOnce,
} from './core.mjs';
import { independentlyVerify } from './independent-verifier.mjs';

const [inputRoot, outputRoot] = process.argv.slice(2);
if (!inputRoot || !outputRoot || !path.isAbsolute(inputRoot) || !path.isAbsolute(outputRoot)) {
  process.stderr.write('usage: cli.mjs <absolute-input-root> <absolute-absent-output-root>\n');
  process.exit(64);
}

let ownsOutput = false;
try {
  const topology = validateTopology(inputRoot, outputRoot);
  const rebuilt = admitAndReconstruct(inputRoot);
  fs.mkdirSync(outputRoot, { mode: 0o700 });
  ownsOutput = true;
  const reportPath = path.join(outputRoot, 'REPRODUCIBLE_BASELINE_REPORT.json');
  const reportIdentity = writeCreateOnce(reportPath, rebuilt.report);
  const independent = independentlyVerify(inputRoot, reportPath);
  const verifierIdentity = writeCreateOnce(path.join(outputRoot, 'INDEPENDENT_VERIFIER_RECEIPT.json'), independent);
  const after = assertInputUnchanged(inputRoot, rebuilt.before);
  const receipt = {
    schema_version: 'p1-217-report-admission-receipt/v1',
    task_id: TASK_ID,
    status: 'PASS',
    claim_boundary: 'COOPERATIVE_LOCAL_SINGLE_PROCESS_NO_CONCURRENT_FILESYSTEM_MUTATOR',
    topology,
    input_inventory: { entries: after.length, pre_post_exact_equality: true },
    report: { path: reportPath, ...reportIdentity },
    independent_verifier: { path: path.join(outputRoot, 'INDEPENDENT_VERIFIER_RECEIPT.json'), ...verifierIdentity },
    taxonomy: rebuilt.reconstructed.taxonomy,
    false_accepts: 0,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: { network: false, provider: false, secret: false, remote: false, production: false, public: false },
  };
  writeCreateOnce(path.join(outputRoot, 'REPORT_ADMISSION_RECEIPT.json'), receipt);
  process.stdout.write(`${JSON.stringify(receipt)}\n`);
} catch (error) {
  if (ownsOutput) {
    for (const name of ['REPORT_ADMISSION_RECEIPT.json', 'INDEPENDENT_VERIFIER_RECEIPT.json', 'REPRODUCIBLE_BASELINE_REPORT.json']) {
      const target = path.join(outputRoot, name);
      if (fs.existsSync(target) && fs.lstatSync(target).isFile()) fs.unlinkSync(target);
    }
    if (fs.existsSync(outputRoot) && fs.readdirSync(outputRoot).length === 0) fs.rmdirSync(outputRoot);
  }
  const reasonCode = error instanceof AdmissionError ? error.reasonCode : 'UNEXPECTED_ERROR';
  process.stderr.write(`${JSON.stringify({ schema_version: 'p1-217-command-failure/v1', status: 'NON_PASS', reason_code: reasonCode, message: String(error.message ?? error) })}\n`);
  process.exit(1);
}

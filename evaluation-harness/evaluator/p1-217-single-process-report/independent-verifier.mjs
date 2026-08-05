import fs from 'node:fs';
import path from 'node:path';

import {
  AdmissionError,
  TASK_ID,
  admitAndReconstruct,
  assertCompleteReportMatches,
  assertInputUnchanged,
  sha256,
} from './core.mjs';

export function independentlyVerify(inputRoot, reportPath) {
  const stat = fs.lstatSync(reportPath);
  if (stat.isSymbolicLink() || !stat.isFile()) throw new AdmissionError('REPORT_NOT_REGULAR');
  const reportBytes = fs.readFileSync(reportPath);
  let observed;
  try {
    observed = JSON.parse(reportBytes.toString('utf8'));
  } catch {
    throw new AdmissionError('REPORT_JSON_INVALID');
  }
  const rebuilt = admitAndReconstruct(inputRoot);
  assertCompleteReportMatches(observed, rebuilt.report);
  assertInputUnchanged(inputRoot, rebuilt.before);
  return {
    schema_version: 'p1-217-independent-verifier-receipt/v1',
    task_id: TASK_ID,
    status: 'PASS',
    report: {
      path: path.resolve(reportPath),
      byte_length: reportBytes.length,
      sha256: sha256(reportBytes),
    },
    raw_evidence_only_reconstruction: true,
    generated_report_used_as_input: false,
    worker_success_fields_trusted: false,
    taxonomy: rebuilt.reconstructed.taxonomy,
    false_accepts: 0,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: { network: false, provider: false, secret: false, remote: false, production: false, public: false },
  };
}

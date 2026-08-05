#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  AdmissionError,
  SOURCE_ROOT,
  admitAndReconstruct,
  assertInputUnchanged,
  sha256,
  snapshotInput,
  stableJson,
  validateTopology,
} from './core.mjs';
import { independentlyVerify } from './independent-verifier.mjs';

const ownedRoot = fs.mkdtempSync(path.join('/private/tmp', 'p1-217-tests-'));
const results = [];

function record(caseId, expected, observed, rejected) {
  results.push({ case_id: caseId, expected, observed, rejected });
  if (expected === 'PASS' ? rejected : !rejected) throw new Error(`${caseId}: unexpected result ${observed}`);
}

function expectPass(caseId, operation) {
  try {
    operation();
    record(caseId, 'PASS', 'PASS', false);
  } catch (error) {
    record(caseId, 'PASS', error.reasonCode ?? error.message, true);
  }
}

function expectReject(caseId, operation) {
  try {
    operation();
    record(caseId, 'NON_PASS', 'PASS', false);
  } catch (error) {
    if (!(error instanceof AdmissionError) && !['ENOENT', 'EEXIST'].includes(error?.code)) throw error;
    record(caseId, 'NON_PASS', error.reasonCode ?? error.code, true);
  }
}

function fixture(caseId) {
  const root = path.join(ownedRoot, caseId, 'input');
  fs.mkdirSync(path.dirname(root), { recursive: true });
  fs.cpSync(SOURCE_ROOT, root, { recursive: true, dereference: false });
  return root;
}

function readManifest(root) {
  return JSON.parse(fs.readFileSync(path.join(root, 'EVIDENCE_MANIFEST.json'), 'utf8'));
}

function writeManifest(root, manifest) {
  const bytes = Buffer.from(stableJson(manifest));
  fs.writeFileSync(path.join(root, 'EVIDENCE_MANIFEST.json'), bytes);
  return { byte_length: bytes.length, sha256: sha256(bytes) };
}

function mutateJsonEntry(root, relativePath, mutate) {
  const target = path.join(root, relativePath);
  const value = JSON.parse(fs.readFileSync(target, 'utf8'));
  mutate(value);
  const bytes = Buffer.from(stableJson(value));
  fs.writeFileSync(target, bytes);
  const manifest = readManifest(root);
  const entry = manifest.entries.find((item) => item.path === relativePath);
  entry.byte_length = bytes.length;
  entry.sha256 = sha256(bytes);
  return writeManifest(root, manifest);
}

function expectReportContractReject(caseId, mutate) {
  const report = structuredClone(admitAndReconstruct(SOURCE_ROOT).report);
  mutate(report);
  const reportPath = path.join(ownedRoot, caseId, 'REPRODUCIBLE_BASELINE_REPORT.json');
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, stableJson(report));
  expectReject(caseId, () => independentlyVerify(SOURCE_ROOT, reportPath));
}

try {
  const sourceBefore = snapshotInput(SOURCE_ROOT);
  expectPass('EXACT_IMMUTABLE_RAW_EVIDENCE_REBUILD', () => {
    const rebuilt = admitAndReconstruct(SOURCE_ROOT);
    if (JSON.stringify(rebuilt.reconstructed.taxonomy) !== JSON.stringify({ denominator: 36, successful: 0, failed: 28, invalid: 8, excluded: 0 })) throw new Error('taxonomy drift');
    assertInputUnchanged(SOURCE_ROOT, rebuilt.before);
  });

  expectReject('OUTPUT_EQUALS_INPUT', () => validateTopology(SOURCE_ROOT, SOURCE_ROOT));
  expectReject('OUTPUT_DESCENDANT_OF_INPUT', () => validateTopology(SOURCE_ROOT, path.join(SOURCE_ROOT, 'new-output')));
  expectReject('OUTPUT_ANCESTOR_OF_INPUT', () => validateTopology(SOURCE_ROOT, path.dirname(SOURCE_ROOT)));
  expectReject('PREEXISTING_OUTPUT_ROOT', () => {
    const output = path.join(ownedRoot, 'preexisting-output');
    fs.mkdirSync(output);
    validateTopology(SOURCE_ROOT, output);
  });
  expectReject('OUTPUT_ROOT_SYMLINK', () => {
    const target = path.join(ownedRoot, 'symlink-target');
    const output = path.join(ownedRoot, 'output-link');
    fs.mkdirSync(target);
    fs.symlinkSync(target, output);
    validateTopology(SOURCE_ROOT, output);
  });
  expectReject('INPUT_ROOT_SYMLINK', () => {
    const input = path.join(ownedRoot, 'input-link');
    fs.symlinkSync(SOURCE_ROOT, input);
    validateTopology(input, path.join(ownedRoot, 'safe-output'));
  });

  expectReject('MANIFEST_MISSING_ENTRY', () => {
    const root = fixture('manifest-missing');
    const manifest = readManifest(root);
    manifest.entries.pop();
    manifest.entry_count -= 1;
    admitAndReconstruct(root, { manifestIdentity: writeManifest(root, manifest), runReceiptIdentity: null });
  });
  expectReject('MANIFEST_EXTRA_ENTRY', () => {
    const root = fixture('manifest-extra');
    const manifest = readManifest(root);
    manifest.entries.push({ ...manifest.entries.at(-1), path: 'EXTRA.json' });
    manifest.entry_count += 1;
    admitAndReconstruct(root, { manifestIdentity: writeManifest(root, manifest), runReceiptIdentity: null });
  });
  expectReject('MANIFEST_DUPLICATE_PATH', () => {
    const root = fixture('manifest-duplicate');
    const manifest = readManifest(root);
    manifest.entries[1] = { ...manifest.entries[0] };
    admitAndReconstruct(root, { manifestIdentity: writeManifest(root, manifest), runReceiptIdentity: null });
  });
  expectReject('MANIFEST_REORDER', () => {
    const root = fixture('manifest-reorder');
    const manifest = readManifest(root);
    [manifest.entries[0], manifest.entries[1]] = [manifest.entries[1], manifest.entries[0]];
    admitAndReconstruct(root, { manifestIdentity: writeManifest(root, manifest), runReceiptIdentity: null });
  });
  expectReject('MANIFEST_BYTE_LENGTH_MUTATION', () => {
    const root = fixture('manifest-length');
    const manifest = readManifest(root);
    manifest.entries[0].byte_length += 1;
    admitAndReconstruct(root, { manifestIdentity: writeManifest(root, manifest), runReceiptIdentity: null });
  });
  expectReject('MANIFEST_SHA256_MUTATION', () => {
    const root = fixture('manifest-sha');
    const manifest = readManifest(root);
    manifest.entries[0].sha256 = '0'.repeat(64);
    admitAndReconstruct(root, { manifestIdentity: writeManifest(root, manifest), runReceiptIdentity: null });
  });
  expectReject('MISSING_RAW_FILE', () => {
    const root = fixture('raw-missing');
    fs.unlinkSync(path.join(root, 'cells/formal-001/request.json'));
    const manifestBytes = fs.readFileSync(path.join(root, 'EVIDENCE_MANIFEST.json'));
    admitAndReconstruct(root, { manifestIdentity: { byte_length: manifestBytes.length, sha256: sha256(manifestBytes) }, runReceiptIdentity: null });
  });
  expectReject('RAW_FILE_MUTATION', () => {
    const root = fixture('raw-mutation');
    fs.appendFileSync(path.join(root, 'cells/formal-001/request.json'), '\n');
    const manifestBytes = fs.readFileSync(path.join(root, 'EVIDENCE_MANIFEST.json'));
    admitAndReconstruct(root, { manifestIdentity: { byte_length: manifestBytes.length, sha256: sha256(manifestBytes) }, runReceiptIdentity: null });
  });
  expectReject('REQUEST_TERMINAL_CROSS_BINDING', () => {
    const root = fixture('cross-binding');
    const identity = mutateJsonEntry(root, 'cells/formal-001/terminal.json', (terminal) => { terminal.request_receipt.sha256 = '0'.repeat(64); });
    admitAndReconstruct(root, { manifestIdentity: identity, runReceiptIdentity: null });
  });
  expectReject('DUPLICATE_CELL_ID', () => {
    const root = fixture('duplicate-cell');
    const identity = mutateJsonEntry(root, 'plan/FORMAL_PLAN.json', (plan) => { plan.cells[1].cell_id = plan.cells[0].cell_id; });
    admitAndReconstruct(root, { manifestIdentity: identity, runReceiptIdentity: null });
  });
  expectReject('MISSING_CELL_TERMINAL', () => {
    const root = fixture('missing-terminal');
    fs.unlinkSync(path.join(root, 'cells/formal-036/terminal.json'));
    const manifestBytes = fs.readFileSync(path.join(root, 'EVIDENCE_MANIFEST.json'));
    admitAndReconstruct(root, { manifestIdentity: { byte_length: manifestBytes.length, sha256: sha256(manifestBytes) }, runReceiptIdentity: null });
  });
  expectReject('INVALID_TAXONOMY_MUTATION', () => {
    const root = fixture('taxonomy-mutation');
    const identity = mutateJsonEntry(root, 'cells/formal-001/terminal.json', (terminal) => { terminal.classification = 'FAILED'; terminal.reason_code = 'TRANSPORT_TIMEOUT'; terminal.response_receipt = null; });
    admitAndReconstruct(root, { manifestIdentity: identity, runReceiptIdentity: null });
  });
  expectReject('GENERATED_REPORT_INJECTED_AS_RAW', () => {
    const root = fixture('generated-report-input');
    const manifest = readManifest(root);
    manifest.entries[0] = {
      path: 'report/REPRODUCIBLE_BASELINE_REPORT.json',
      byte_length: fs.statSync(path.join(root, 'report/REPRODUCIBLE_BASELINE_REPORT.json')).size,
      sha256: sha256(fs.readFileSync(path.join(root, 'report/REPRODUCIBLE_BASELINE_REPORT.json'))),
      type: 'REGULAR_FILE',
    };
    admitAndReconstruct(root, { manifestIdentity: writeManifest(root, manifest), runReceiptIdentity: null });
  });
  expectReject('GENERATED_REPORT_USED_AS_ORACLE', () => admitAndReconstruct(SOURCE_ROOT, { generatedReportOracle: true }));

  expectReportContractReject('REPORT_TOP_LEVEL_MISSING_FIELD', (report) => { delete report.conclusion; });
  expectReportContractReject('REPORT_TOP_LEVEL_EXTRA_FIELD', (report) => { report.unexpected = false; });
  expectReportContractReject('REPORT_MANDATORY_FIELD_TYPE_DRIFT', (report) => { report.research_question = 1; });
  expectReportContractReject('REPORT_SCHEMA_VERSION_MUTATION', (report) => { report.schema_version = 'p1-217-reproducible-baseline-report/v2'; });
  expectReportContractReject('REPORT_TASK_IDENTITY_MUTATION', (report) => { report.task_id = 'AIOS-P1-999_FORGED'; });
  expectReportContractReject('REPORT_EXECUTION_IDENTITY_MUTATION', (report) => { report.source_evidence.execution_id = 'P1-207-forged'; });
  expectReportContractReject('REPORT_RESEARCH_QUESTION_MUTATION', (report) => { report.research_question += ' forged'; });
  expectReportContractReject('REPORT_HYPOTHESIS_MUTATION', (report) => { report.falsifiable_hypothesis += ' forged'; });
  expectReportContractReject('REPORT_DATASET_IDENTITY_MUTATION', (report) => { report.dataset_and_tasks.task_count = 7; });
  expectReportContractReject('REPORT_ENVIRONMENT_IDENTITY_MUTATION', (report) => { report.source_and_environment.model = 'forged-model'; });
  expectReportContractReject('REPORT_CONFIGURATION_IDENTITY_MUTATION', (report) => { report.configurations.comparison_claim = 'FORGED'; });
  expectReportContractReject('REPORT_EVALUATOR_IDENTITY_MUTATION', (report) => { report.evaluator.identity = 'FORGED'; });
  expectReportContractReject('REPORT_EVALUATOR_DEFINITION_MUTATION', (report) => { report.evaluator.definition += ' forged'; });
  expectReportContractReject('REPORT_EVALUATOR_VERSION_MUTATION', (report) => { report.evaluator.version = '2.0.0'; });
  expectReportContractReject('REPORT_UNCERTAINTY_MUTATION', (report) => { report.uncertainty.statement += ' forged'; });
  expectReportContractReject('REPORT_COST_MUTATION', (report) => { report.cost.provider_requests_observed += 1; });
  expectReportContractReject('REPORT_LIMITATIONS_MUTATION', (report) => { report.limitations.pop(); });
  expectReportContractReject('REPORT_STOP_RATIONALE_MUTATION', (report) => { report.stop_continue_rationale += ' forged'; });

  if (JSON.stringify(snapshotInput(SOURCE_ROOT)) !== JSON.stringify(sourceBefore)) throw new Error('immutable source changed');
  const negativeResults = results.filter((item) => item.expected === 'NON_PASS');
  const falseAccepts = negativeResults.filter((item) => !item.rejected).length;
  const receipt = {
    schema_version: 'p1-217-test-receipt/v1',
    task_id: 'AIOS-P1-217_SINGLE_PROCESS_RAW_EVIDENCE_REPORT_ADMISSION',
    status: 'PASS',
    positive_cases: results.length - negativeResults.length,
    negative_cases: negativeResults.length,
    report_contract_negative_cases: negativeResults.filter((item) => item.case_id.startsWith('REPORT_')).length,
    false_accepts: falseAccepts,
    immutable_input_unchanged: true,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: { network: false, provider: false, secret: false, remote: false, production: false, public: false },
    results,
  };
  if (process.argv[2]) {
    const receiptPath = path.resolve(process.argv[2]);
    const descriptor = fs.openSync(receiptPath, 'wx', 0o600);
    try {
      fs.writeFileSync(descriptor, stableJson(receipt));
      fs.fsyncSync(descriptor);
    } finally {
      fs.closeSync(descriptor);
    }
  }
  process.stdout.write(`${JSON.stringify(receipt)}\n`);
} finally {
  fs.rmSync(ownedRoot, { recursive: true, force: true });
}

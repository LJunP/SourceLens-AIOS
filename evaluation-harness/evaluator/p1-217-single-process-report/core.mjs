import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const TASK_ID = 'AIOS-P1-217_SINGLE_PROCESS_RAW_EVIDENCE_REPORT_ADMISSION';
export const SOURCE_TASK_ID = 'AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE';
export const SOURCE_ROOT = '/Users/lijunpeng/Developer/.sourcelens-audit/p1-minimum-cooperative-local-research-exit-20260804/task-1-p1-207/evidence/formal-execution-v1';
export const SOURCE_MANIFEST = Object.freeze({
  byte_length: 31196,
  sha256: '31e439cc3e3a993916fffd836d6883722e4570719d6a93c5b38b6a29c703504f',
});
export const SOURCE_RUN_RECEIPT = Object.freeze({
  byte_length: 745,
  sha256: '5352b9071bffa4c1952f1c1388af8c05f9726d03fefb85e23e1164ff544fe227',
});
export const EXPECTED_TAXONOMY = Object.freeze({
  denominator: 36,
  successful: 0,
  failed: 28,
  invalid: 8,
  excluded: 0,
});
export const REPORT_SCHEMA_VERSION = 'p1-217-reproducible-baseline-report/v1';
export const EVALUATOR_DESCRIPTOR = Object.freeze({
  identity: 'P1-217-INDEPENDENT-RAW-EVIDENCE-REPORT-EVALUATOR',
  definition: 'Reconstruct every report field from the immutable manifest-bound P1-207 raw Evidence and reject any report byte whose complete closed contract differs from that reconstruction.',
  version: '1.0.0',
});
const REPORT_TOP_LEVEL_KEYS = Object.freeze([
  'cell_results',
  'conclusion',
  'configurations',
  'cost',
  'dataset_and_tasks',
  'decision',
  'evaluator',
  'falsifiable_hypothesis',
  'limitations',
  'metric',
  'reason_code_distribution',
  'reproduction',
  'research_question',
  'schema_version',
  'source_and_environment',
  'source_evidence',
  'stop_continue_rationale',
  'task_id',
  'taxonomy',
  'uncertainty',
]);
export const EXCLUDED_GENERATED_PATHS = Object.freeze([
  'EVIDENCE_MANIFEST.json',
  'report/REPORT_REBUILD_RECEIPT.json',
  'report/REPRODUCIBLE_BASELINE_REPORT.json',
  'reviews/INDEPENDENT_EVALUATOR_RECEIPT.json',
]);

export class AdmissionError extends Error {
  constructor(reasonCode, message = reasonCode) {
    super(message);
    this.name = 'AdmissionError';
    this.reasonCode = reasonCode;
  }
}

export function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

export function stableJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function fail(reasonCode, message) {
  throw new AdmissionError(reasonCode, message);
}

function exactKeys(value, expected, reasonCode) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(reasonCode);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) fail(reasonCode);
}

function exactObject(value, expected, reasonCode) {
  const normalize = (item) => {
    if (Array.isArray(item)) return item.map(normalize);
    if (item && typeof item === 'object') {
      return Object.fromEntries(Object.keys(item).sort().map((key) => [key, normalize(item[key])]));
    }
    return item;
  };
  if (JSON.stringify(normalize(value)) !== JSON.stringify(normalize(expected))) fail(reasonCode);
}

function identityOf(bytes) {
  return { byte_length: bytes.length, sha256: sha256(bytes) };
}

function assertIdentity(bytes, expected, reasonCode) {
  exactObject(identityOf(bytes), expected, reasonCode);
}

function safeRelative(relativePath) {
  if (typeof relativePath !== 'string' || relativePath.length === 0) return false;
  if (path.isAbsolute(relativePath) || relativePath.includes('\\') || relativePath.includes('\0')) return false;
  const normalized = path.posix.normalize(relativePath);
  return normalized === relativePath && normalized !== '.' && !normalized.startsWith('../');
}

function contained(root, relativePath) {
  if (!safeRelative(relativePath)) fail('PATH_INVALID', relativePath);
  const target = path.join(root, ...relativePath.split('/'));
  const relative = path.relative(root, target);
  if (relative.startsWith('..') || path.isAbsolute(relative)) fail('PATH_ESCAPE', relativePath);
  return target;
}

function lstatRegular(target, reasonCode = 'NONREGULAR_INPUT') {
  let stat;
  try {
    stat = fs.lstatSync(target);
  } catch (error) {
    if (error?.code === 'ENOENT') fail('PATH_MISSING', target);
    throw error;
  }
  if (stat.isSymbolicLink()) fail('SYMLINK_REJECTED', target);
  if (!stat.isFile()) fail(reasonCode, target);
  return stat;
}

function readBoundFile(root, relativePath, expectedIdentity) {
  const target = contained(root, relativePath);
  const stat = lstatRegular(target);
  const bytes = fs.readFileSync(target);
  if (stat.size !== bytes.length) fail('INPUT_IDENTITY_DRIFT', relativePath);
  if (expectedIdentity) assertIdentity(bytes, expectedIdentity, 'INPUT_IDENTITY_MISMATCH');
  return bytes;
}

function parseJson(bytes, reasonCode) {
  try {
    return JSON.parse(bytes.toString('utf8'));
  } catch {
    fail(reasonCode);
  }
}

function walk(root, current = root, result = []) {
  const entries = fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const target = path.join(current, entry.name);
    const relativePath = path.relative(root, target).split(path.sep).join('/');
    const stat = fs.lstatSync(target);
    if (stat.isSymbolicLink()) fail('SYMLINK_REJECTED', relativePath);
    if (stat.isDirectory()) {
      walk(root, target, result);
      continue;
    }
    if (!stat.isFile()) fail('NONREGULAR_INPUT', relativePath);
    const bytes = fs.readFileSync(target);
    result.push({ path: relativePath, byte_length: bytes.length, sha256: sha256(bytes), type: 'REGULAR_FILE' });
  }
  return result;
}

export function snapshotInput(root) {
  const rootStat = fs.lstatSync(root);
  if (rootStat.isSymbolicLink()) fail('INPUT_ROOT_SYMLINK');
  if (!rootStat.isDirectory()) fail('INPUT_ROOT_NOT_DIRECTORY');
  return walk(root);
}

function isSameOrDescendant(candidate, ancestor) {
  const relative = path.relative(ancestor, candidate);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function closestExistingAncestor(target) {
  let current = path.resolve(target);
  const tail = [];
  while (!fs.existsSync(current)) {
    const parent = path.dirname(current);
    if (parent === current) fail('OUTPUT_ANCESTOR_MISSING');
    tail.unshift(path.basename(current));
    current = parent;
  }
  const stat = fs.lstatSync(current);
  if (stat.isSymbolicLink()) fail('OUTPUT_ANCESTOR_SYMLINK');
  if (!stat.isDirectory()) fail('OUTPUT_ANCESTOR_NOT_DIRECTORY');
  return path.join(fs.realpathSync(current), ...tail);
}

export function validateTopology(inputRoot, outputRoot) {
  const inputAbsolute = path.resolve(inputRoot);
  const outputAbsolute = path.resolve(outputRoot);
  const inputStat = fs.lstatSync(inputAbsolute);
  if (inputStat.isSymbolicLink()) fail('INPUT_ROOT_SYMLINK');
  if (!inputStat.isDirectory()) fail('INPUT_ROOT_NOT_DIRECTORY');
  const inputReal = fs.realpathSync(inputAbsolute);
  const outputExists = fs.existsSync(outputAbsolute);
  if (outputExists && fs.lstatSync(outputAbsolute).isSymbolicLink()) fail('OUTPUT_ROOT_SYMLINK');
  const outputPlannedReal = closestExistingAncestor(outputAbsolute);
  if (isSameOrDescendant(outputPlannedReal, inputReal)) fail('OUTPUT_OVERLAPS_INPUT');
  if (isSameOrDescendant(inputReal, outputPlannedReal)) fail('INPUT_OVERLAPS_OUTPUT');
  if (outputExists) fail('OUTPUT_ROOT_PREEXISTS');
  return { input_realpath: inputReal, output_planned_realpath: outputPlannedReal };
}

function validateManifest(manifest) {
  exactKeys(manifest, ['entries', 'entry_count', 'excluded_paths', 'root_role', 'schema_version', 'task_id'], 'MANIFEST_SCHEMA_INVALID');
  if (manifest.schema_version !== 'p1-207-evidence-manifest/v1' || manifest.task_id !== SOURCE_TASK_ID || manifest.root_role !== 'FORMAL_RAW_EVIDENCE') fail('MANIFEST_IDENTITY_INVALID');
  if (!Array.isArray(manifest.entries) || manifest.entry_count !== 191 || manifest.entries.length !== 191) fail('MANIFEST_ENTRY_COUNT_INVALID');
  exactObject(manifest.excluded_paths, EXCLUDED_GENERATED_PATHS, 'MANIFEST_EXCLUSIONS_INVALID');
  const paths = [];
  for (const entry of manifest.entries) {
    exactKeys(entry, ['byte_length', 'path', 'sha256', 'type'], 'MANIFEST_ENTRY_SCHEMA_INVALID');
    if (!safeRelative(entry.path) || entry.type !== 'REGULAR_FILE' || !Number.isSafeInteger(entry.byte_length) || entry.byte_length < 0 || !/^[0-9a-f]{64}$/.test(entry.sha256)) fail('MANIFEST_ENTRY_INVALID');
    if (EXCLUDED_GENERATED_PATHS.includes(entry.path)) fail('GENERATED_OUTPUT_ADMITTED_AS_RAW');
    paths.push(entry.path);
  }
  if (new Set(paths).size !== paths.length) fail('MANIFEST_DUPLICATE_PATH');
  const sorted = [...paths].sort((a, b) => a.localeCompare(b));
  if (JSON.stringify(paths) !== JSON.stringify(sorted)) fail('MANIFEST_ORDER_INVALID');
  return new Map(manifest.entries.map((entry) => [entry.path, entry]));
}

function readManifestBoundJson(root, manifestMap, relativePath, schemaVersion) {
  const expected = manifestMap.get(relativePath);
  if (!expected) fail('MANIFEST_ENTRY_MISSING', relativePath);
  const bytes = readBoundFile(root, relativePath, { byte_length: expected.byte_length, sha256: expected.sha256 });
  const value = parseJson(bytes, 'RAW_JSON_INVALID');
  if (schemaVersion && value.schema_version !== schemaVersion) fail('RAW_SCHEMA_INVALID', relativePath);
  return { bytes, value };
}

function assertRef(root, manifestMap, ref, expectedPath, reasonCode) {
  exactKeys(ref, ['byte_length', 'path', 'sha256'], reasonCode);
  if (ref.path !== expectedPath) fail(reasonCode);
  const expected = manifestMap.get(expectedPath);
  if (!expected || expected.byte_length !== ref.byte_length || expected.sha256 !== ref.sha256) fail(reasonCode);
  readBoundFile(root, expectedPath, { byte_length: ref.byte_length, sha256: ref.sha256 });
}

function validateClosedInventory(snapshot, manifest) {
  const expectedPaths = [...manifest.entries.map((entry) => entry.path), ...manifest.excluded_paths].sort((a, b) => a.localeCompare(b));
  const actualPaths = snapshot.map((entry) => entry.path).sort((a, b) => a.localeCompare(b));
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) fail('CLOSED_INVENTORY_DRIFT');
}

function reconstructCells(root, manifestMap, plan, runReceipt) {
  if (!Array.isArray(plan.cells) || plan.cells.length !== 36 || plan.denominator !== 36) fail('FORMAL_PLAN_INVALID');
  const ids = plan.cells.map((cell) => cell.cell_id);
  if (new Set(ids).size !== 36) fail('DUPLICATE_CELL_ID');
  const expectedIds = Array.from({ length: 36 }, (_, index) => `formal-${String(index + 1).padStart(3, '0')}`);
  exactObject(ids, expectedIds, 'FORMAL_CELL_SET_INVALID');
  const taxonomy = { denominator: 36, successful: 0, failed: 0, invalid: 0, excluded: 0 };
  const reasons = {};
  const cells = [];
  for (let index = 0; index < plan.cells.length; index += 1) {
    const cell = plan.cells[index];
    exactKeys(cell, ['adapter_id', 'baseline_id', 'cell_id', 'ordinal', 'profile_id', 'repetition_id', 'request_shape', 'task_id'], 'FORMAL_CELL_SCHEMA_INVALID');
    if (cell.ordinal !== index + 1 || cell.cell_id !== expectedIds[index]) fail('FORMAL_CELL_ORDER_INVALID');
    const prefix = `cells/${cell.cell_id}`;
    const requestPath = `${prefix}/request.json`;
    const requestReceiptPath = `${prefix}/request-receipt.json`;
    const terminalPath = `${prefix}/terminal.json`;
    const transportPath = `${prefix}/transport-receipt.json`;
    const request = readManifestBoundJson(root, manifestMap, requestReceiptPath, 'p1-207-request-receipt/v1').value;
    const terminal = readManifestBoundJson(root, manifestMap, terminalPath, 'p1-207-cell-terminal/v1').value;
    const transport = readManifestBoundJson(root, manifestMap, transportPath, 'p1-207-transport-receipt/v1').value;
    if (request.cell_id !== cell.cell_id || request.task_id !== cell.task_id || request.profile_id !== cell.profile_id || request.repetition_id !== cell.repetition_id || request.execution_id !== runReceipt.execution_id) fail('REQUEST_PLAN_BINDING_INVALID');
    assertRef(root, manifestMap, request.request, requestPath, 'REQUEST_BYTES_BINDING_INVALID');
    if (terminal.cell_id !== cell.cell_id || terminal.task_id !== cell.task_id || terminal.execution_id !== runReceipt.execution_id || terminal.provider_request_count !== 1 || terminal.automatic_retries !== 0) fail('TERMINAL_BINDING_INVALID');
    assertRef(root, manifestMap, terminal.request_receipt, requestReceiptPath, 'TERMINAL_REQUEST_BINDING_INVALID');
    if (transport.cell_id !== cell.cell_id || transport.execution_id !== runReceipt.execution_id || transport.peer_address !== '127.0.0.1' || transport.peer_port !== 8787 || transport.automatic_retry !== false) fail('TRANSPORT_BINDING_INVALID');
    assertRef(root, manifestMap, transport.request_receipt, requestReceiptPath, 'TRANSPORT_REQUEST_BINDING_INVALID');
    if (terminal.response_receipt === null) {
      if (transport.response !== null || transport.http_status !== null || terminal.classification !== 'FAILED' || terminal.reason_code !== 'TRANSPORT_TIMEOUT' || transport.reason_code !== 'TRANSPORT_TIMEOUT' || transport.transport_status !== 'TRANSPORT_NON_PASS') fail('TIMEOUT_CLASSIFICATION_INVALID');
    } else {
      const responseReceiptPath = `${prefix}/response-receipt.json`;
      const responsePath = `${prefix}/response.raw`;
      assertRef(root, manifestMap, terminal.response_receipt, responseReceiptPath, 'TERMINAL_RESPONSE_BINDING_INVALID');
      const responseReceipt = readManifestBoundJson(root, manifestMap, responseReceiptPath, 'p1-207-response-receipt/v1').value;
      if (responseReceipt.cell_id !== cell.cell_id || responseReceipt.execution_id !== runReceipt.execution_id || responseReceipt.peer_address !== '127.0.0.1' || responseReceipt.peer_port !== 8787 || responseReceipt.http_status !== transport.http_status) fail('RESPONSE_BINDING_INVALID');
      assertRef(root, manifestMap, responseReceipt.request_receipt, requestReceiptPath, 'RESPONSE_REQUEST_BINDING_INVALID');
      assertRef(root, manifestMap, responseReceipt.response, responsePath, 'RESPONSE_BYTES_BINDING_INVALID');
      exactObject(transport.response, responseReceipt.response, 'TRANSPORT_RESPONSE_BINDING_INVALID');
      if (terminal.classification === 'INVALID') {
        if (terminal.reason_code !== 'IR_SCHEMA_INVALID' || transport.http_status !== 200 || transport.transport_status !== 'RECEIVED') fail('INVALID_CLASSIFICATION_INVALID');
      } else if (terminal.classification === 'FAILED') {
        if (terminal.reason_code !== 'HTTP_NON_2XX' || (transport.http_status >= 200 && transport.http_status < 300)) fail('HTTP_FAILURE_CLASSIFICATION_INVALID');
      } else fail('UNSUPPORTED_CLASSIFICATION');
    }
    const key = terminal.classification.toLowerCase();
    if (!(key in taxonomy)) fail('UNSUPPORTED_CLASSIFICATION');
    taxonomy[key] += 1;
    reasons[terminal.reason_code] = (reasons[terminal.reason_code] ?? 0) + 1;
    cells.push({ cell_id: cell.cell_id, task_id: cell.task_id, profile_id: cell.profile_id, repetition_id: cell.repetition_id, classification: terminal.classification, reason_code: terminal.reason_code });
  }
  exactObject(taxonomy, EXPECTED_TAXONOMY, 'TAXONOMY_INVALID');
  exactObject(runReceipt.taxonomy, EXPECTED_TAXONOMY, 'RUN_RECEIPT_TAXONOMY_INVALID');
  return { taxonomy, reasons: Object.fromEntries(Object.entries(reasons).sort()), cells };
}

export function admitAndReconstruct(inputRoot, options = {}) {
  if (options.generatedReportOracle) fail('GENERATED_REPORT_AS_ORACLE_FORBIDDEN');
  const root = path.resolve(inputRoot);
  const before = snapshotInput(root);
  const manifestBytes = readBoundFile(root, 'EVIDENCE_MANIFEST.json', options.manifestIdentity ?? SOURCE_MANIFEST);
  const manifest = parseJson(manifestBytes, 'MANIFEST_JSON_INVALID');
  const manifestMap = validateManifest(manifest);
  validateClosedInventory(before, manifest);
  for (const entry of manifest.entries) readBoundFile(root, entry.path, { byte_length: entry.byte_length, sha256: entry.sha256 });
  const run = readManifestBoundJson(root, manifestMap, 'RUN_RECEIPT.json', 'p1-207-run-receipt/v1');
  if (options.runReceiptIdentity !== null) assertIdentity(run.bytes, options.runReceiptIdentity ?? SOURCE_RUN_RECEIPT, 'RUN_RECEIPT_IDENTITY_INVALID');
  const runReceipt = run.value;
  if (runReceipt.task_id !== SOURCE_TASK_ID || runReceipt.denominator !== 36 || runReceipt.scheduled_cells !== 36 || runReceipt.terminal_cells !== 36 || runReceipt.status !== 'PASS') fail('RUN_RECEIPT_SEMANTICS_INVALID');
  const plan = readManifestBoundJson(root, manifestMap, 'plan/FORMAL_PLAN.json', 'p1-207-formal-plan/v1').value;
  const config = readManifestBoundJson(root, manifestMap, 'CONFIGURATION_RECEIPT.json', 'p1-207-configuration-receipt/v1').value;
  const environment = readManifestBoundJson(root, manifestMap, 'ENVIRONMENT_RECEIPT.json', 'p1-207-environment-receipt/v1').value;
  const reconstructed = reconstructCells(root, manifestMap, plan, runReceipt);
  const report = {
    schema_version: REPORT_SCHEMA_VERSION,
    task_id: TASK_ID,
    source_evidence: {
      root,
      manifest: identityOf(manifestBytes),
      run_receipt: identityOf(run.bytes),
      execution_id: runReceipt.execution_id,
      admitted_raw_entries: manifest.entries.length,
      generated_outputs_excluded: [...manifest.excluded_paths],
    },
    research_question: 'What verified task success rate and failure distribution were observed in the frozen P1-207 36-cell B0/B1/B2 baseline execution?',
    falsifiable_hypothesis: 'At least one eligible scheduled run will be independently verified successful under the frozen execution contract.',
    dataset_and_tasks: {
      dataset_manifest: environment.dataset_manifest,
      scheduled_cells: 36,
      task_count: 6,
      profiles: ['B0_A', 'B0_B', 'B1_A', 'B1_B', 'B2_A', 'B2_B'],
    },
    source_and_environment: {
      repository: environment.repository,
      platform: environment.platform,
      architecture: environment.architecture,
      node: environment.node,
      model: environment.model,
      endpoint: environment.endpoint,
    },
    configurations: {
      baseline_suite: ['B0', 'B1', 'B2'],
      target_configuration: null,
      comparison_claim: 'NO_SUPERIORITY_COMPARISON_THIS_ARTIFACT',
      configuration_receipt: { route_id: config.route_id, claim_boundary: config.claim_boundary },
    },
    evaluator: { ...EVALUATOR_DESCRIPTOR },
    metric: {
      name: 'Verified Task Success Rate',
      numerator: reconstructed.taxonomy.successful,
      denominator: reconstructed.taxonomy.denominator,
      value: 0,
    },
    taxonomy: reconstructed.taxonomy,
    reason_code_distribution: reconstructed.reasons,
    cell_results: reconstructed.cells,
    uncertainty: {
      statement: 'This fixed 36-cell artifact is descriptive; it does not estimate a population effect or support a superiority claim.',
      confidence_interval: null,
      effect_size: null,
    },
    cost: {
      monetary_amount: null,
      currency: 'USD',
      reason: 'Exact monetary cost was not present in the admitted raw Evidence; it is reported as UNKNOWN rather than invented.',
      provider_requests_observed: runReceipt.provider_requests,
    },
    conclusion: 'The frozen run produced 0 independently verified successes among 36 scheduled cells. This negative result is retained as a valid research artifact.',
    limitations: [
      'Cooperative-local, single-process report admission only.',
      'The historical execution used a loopback Provider; this offline rebuild performs no network, Provider, or Secret operation.',
      'No hostile-principal, concurrent filesystem mutator, production custody, or model-superiority claim is made.',
    ],
    decision: 'ACCEPT_NEGATIVE_BASELINE_AS_REPRODUCIBLE_RESEARCH_ARTIFACT',
    stop_continue_rationale: 'The artifact closes the P1 baseline-report requirement while the 0/36 result and failure taxonomy remain explicit inputs to later preregistration.',
    reproduction: {
      command: `node evaluation-harness/evaluator/p1-217-single-process-report/cli.mjs ${root} <unique-absent-output-root>`,
      generated_report_used_as_input: false,
      worker_success_fields_trusted: false,
      raw_evidence_only_reconstruction: true,
    },
  };
  return { before, manifest, report, reconstructed };
}

export function assertInputUnchanged(root, before) {
  const after = snapshotInput(path.resolve(root));
  if (JSON.stringify(after) !== JSON.stringify(before)) fail('INPUT_CHANGED_DURING_REBUILD');
  return after;
}

export function writeCreateOnce(target, value) {
  const bytes = Buffer.from(stableJson(value));
  const descriptor = fs.openSync(target, 'wx', 0o600);
  try {
    fs.writeFileSync(descriptor, bytes);
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
  return identityOf(bytes);
}

export function reportCore(report) {
  return report;
}

function nonEmptyString(value, reasonCode) {
  if (typeof value !== 'string' || value.length === 0) fail(reasonCode);
}

export function validateCompleteReportContract(report) {
  exactKeys(report, REPORT_TOP_LEVEL_KEYS, 'REPORT_CONTRACT_TOP_LEVEL_INVALID');
  if (report.schema_version !== REPORT_SCHEMA_VERSION || report.task_id !== TASK_ID) fail('REPORT_IDENTITY_INVALID');
  exactKeys(report.source_evidence, ['admitted_raw_entries', 'execution_id', 'generated_outputs_excluded', 'manifest', 'root', 'run_receipt'], 'REPORT_SOURCE_EVIDENCE_SCHEMA_INVALID');
  nonEmptyString(report.source_evidence.execution_id, 'REPORT_EXECUTION_ID_INVALID');
  exactKeys(report.source_evidence.manifest, ['byte_length', 'sha256'], 'REPORT_MANIFEST_IDENTITY_SCHEMA_INVALID');
  exactKeys(report.source_evidence.run_receipt, ['byte_length', 'sha256'], 'REPORT_RUN_RECEIPT_IDENTITY_SCHEMA_INVALID');
  if (!Number.isSafeInteger(report.source_evidence.admitted_raw_entries) || !Array.isArray(report.source_evidence.generated_outputs_excluded)) fail('REPORT_SOURCE_EVIDENCE_INVALID');
  exactKeys(report.dataset_and_tasks, ['dataset_manifest', 'profiles', 'scheduled_cells', 'task_count'], 'REPORT_DATASET_SCHEMA_INVALID');
  exactKeys(report.source_and_environment, ['architecture', 'endpoint', 'model', 'node', 'platform', 'repository'], 'REPORT_ENVIRONMENT_SCHEMA_INVALID');
  exactKeys(report.configurations, ['baseline_suite', 'comparison_claim', 'configuration_receipt', 'target_configuration'], 'REPORT_CONFIGURATION_SCHEMA_INVALID');
  exactKeys(report.configurations.configuration_receipt, ['claim_boundary', 'route_id'], 'REPORT_CONFIGURATION_RECEIPT_SCHEMA_INVALID');
  exactKeys(report.evaluator, ['definition', 'identity', 'version'], 'REPORT_EVALUATOR_SCHEMA_INVALID');
  exactObject(report.evaluator, EVALUATOR_DESCRIPTOR, 'REPORT_EVALUATOR_IDENTITY_INVALID');
  exactKeys(report.metric, ['denominator', 'name', 'numerator', 'value'], 'REPORT_METRIC_SCHEMA_INVALID');
  exactKeys(report.taxonomy, ['denominator', 'excluded', 'failed', 'invalid', 'successful'], 'REPORT_TAXONOMY_SCHEMA_INVALID');
  exactKeys(report.uncertainty, ['confidence_interval', 'effect_size', 'statement'], 'REPORT_UNCERTAINTY_SCHEMA_INVALID');
  exactKeys(report.cost, ['currency', 'monetary_amount', 'provider_requests_observed', 'reason'], 'REPORT_COST_SCHEMA_INVALID');
  exactKeys(report.reproduction, ['command', 'generated_report_used_as_input', 'raw_evidence_only_reconstruction', 'worker_success_fields_trusted'], 'REPORT_REPRODUCTION_SCHEMA_INVALID');
  for (const [key, value] of Object.entries({
    research_question: report.research_question,
    falsifiable_hypothesis: report.falsifiable_hypothesis,
    conclusion: report.conclusion,
    decision: report.decision,
    stop_continue_rationale: report.stop_continue_rationale,
  })) nonEmptyString(value, `REPORT_${key.toUpperCase()}_INVALID`);
  if (!Array.isArray(report.limitations) || report.limitations.length === 0 || report.limitations.some((item) => typeof item !== 'string' || item.length === 0)) fail('REPORT_LIMITATIONS_INVALID');
  if (!Array.isArray(report.cell_results) || report.cell_results.length !== EXPECTED_TAXONOMY.denominator) fail('REPORT_CELL_RESULTS_INVALID');
  for (const cell of report.cell_results) exactKeys(cell, ['cell_id', 'classification', 'profile_id', 'reason_code', 'repetition_id', 'task_id'], 'REPORT_CELL_RESULT_SCHEMA_INVALID');
  return report;
}

export function assertCompleteReportMatches(observed, independentlyRebuilt) {
  validateCompleteReportContract(observed);
  validateCompleteReportContract(independentlyRebuilt);
  exactObject(observed, independentlyRebuilt, 'REPORT_COMPLETE_CONTRACT_MISMATCH');
  return true;
}

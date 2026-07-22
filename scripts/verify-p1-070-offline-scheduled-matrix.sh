#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly CANONICAL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly TASK_ID="AIOS-P1-070_OFFLINE_SCHEDULED_MATRIX_VTSR_AND_FALSE_SUCCESS_EXPERIMENT"
readonly CONTRACT_REL="evaluation-harness/contracts/offline-scheduled-matrix-v1/offline-scheduled-matrix-v1.contract.json"
readonly PLAN_REL="evaluation-harness/fixtures/offline-scheduled-matrix-v1/matrix-plan.json"
readonly CATALOG_REL="evaluation-harness/fixtures/offline-scheduled-matrix-v1/negative-cases.json"
readonly TASK_CONTRACT_REL="docs/aios/tasks/P1-070_OFFLINE_SCHEDULED_MATRIX_VTSR_AND_FALSE_SUCCESS_EXPERIMENT.yaml"
readonly PREFREEZE_RECEIPT="/Users/lijunpeng/Developer/.sourcelens-audit/p1-070-offline-scheduled-matrix-TS8DyWZw/quality/PREFREEZE_RECEIPT.json"
readonly RUNNER_REL="evaluation-harness/harness/offline-scheduled-matrix-v1/run.mjs"
readonly EVALUATOR_REL="evaluation-harness/evaluator/offline-scheduled-matrix-v1/recompute.mjs"

fail() {
  printf 'P1_070_TARGETED_VERIFIER_NON_PASS reason=%s\n' "$1" >&2
  exit 1
}

for required_tool in node mktemp cp cmp; do
  command -v "${required_tool}" >/dev/null 2>&1 || fail "MISSING_REQUIRED_TOOL_${required_tool}"
done

for required_path in \
  "${CANONICAL_ROOT}/${CONTRACT_REL}" \
  "${CANONICAL_ROOT}/${PLAN_REL}" \
  "${CANONICAL_ROOT}/${CATALOG_REL}" \
  "${CANONICAL_ROOT}/${TASK_CONTRACT_REL}" \
  "${PREFREEZE_RECEIPT}" \
  "${CANONICAL_ROOT}/${RUNNER_REL}" \
  "${CANONICAL_ROOT}/${EVALUATOR_REL}"; do
  [[ -f "${required_path}" && ! -L "${required_path}" ]] || fail "REQUIRED_INPUT_TYPE_OR_SYMLINK"
done

# Validate every accepted input and every frozen public byte against the exact
# pre-freeze receipt before executing either implementation under test.
node --input-type=module - \
  "${CANONICAL_ROOT}" \
  "${CANONICAL_ROOT}/${CONTRACT_REL}" \
  "${CANONICAL_ROOT}/${PLAN_REL}" \
  "${CANONICAL_ROOT}/${CATALOG_REL}" \
  "${PREFREEZE_RECEIPT}" <<'NODE' || fail "PREFREEZE_OR_ACCEPTED_INPUT_IDENTITY"
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';

const [root, contractPath, planPath, catalogPath, receiptPath] = process.argv.slice(2);
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const identity = (p) => {
  const st = fs.lstatSync(p);
  if (!st.isFile() || st.isSymbolicLink()) throw new Error(`unsafe type: ${p}`);
  const bytes = fs.readFileSync(p);
  return { sha256: crypto.createHash('sha256').update(bytes).digest('hex'), byte_length: bytes.length };
};
const check = (actual, expected, label) => {
  if (actual.sha256 !== expected.sha256 || actual.byte_length !== expected.byte_length) {
    throw new Error(`${label} identity mismatch`);
  }
};
const contract = readJson(contractPath);
const plan = readJson(planPath);
const catalog = readJson(catalogPath);
const receipt = readJson(receiptPath);
if (receipt.status !== 'PASS' || receipt.task_id !== 'AIOS-P1-070_OFFLINE_SCHEDULED_MATRIX_VTSR_AND_FALSE_SUCCESS_EXPERIMENT') {
  throw new Error('prefreeze receipt status/task mismatch');
}
for (const expected of [...receipt.authority_inputs, ...receipt.accepted_read_only_engineering_inputs]) {
  check(identity(path.join(root, expected.path)), expected, expected.path);
}
for (const expected of receipt.frozen_outputs) {
  check(identity(path.join(root, expected.path)), expected, expected.path);
}
for (const expected of contract.accepted_read_only_engineering_inputs) {
  check(identity(path.join(root, expected.path)), expected, `contract:${expected.path}`);
}
check(identity(contractPath), plan.contract_identity, 'plan->contract');
check(identity(contractPath), catalog.contract_identity, 'catalog->contract');
check(identity(planPath), catalog.matrix_plan_identity, 'catalog->plan');
const expectedCases = contract.mandatory_negative_case_ids;
const catalogCases = catalog.cases.map((entry) => entry.case_id);
const receiptCases = receipt.frozen_negative_catalog.required_case_ids;
if (JSON.stringify(catalogCases) !== JSON.stringify(expectedCases) || JSON.stringify(receiptCases) !== JSON.stringify(expectedCases)) {
  throw new Error('negative case set/order mismatch');
}
if (catalog.counts.mandatory !== 11 || catalog.counts.catalog_entries !== 11 || catalog.counts.allowed_false_accepts !== 0) {
  throw new Error('negative case count/budget mismatch');
}
if (plan.schedule.length !== 5 || plan.frozen_accounting_expectation.eligible_denominator !== 4 ||
    plan.frozen_accounting_expectation.verified_success_numerator !== 1 ||
    plan.frozen_accounting_expectation.failure_count !== 3 ||
    plan.frozen_accounting_expectation.invalid_count !== 1 ||
    plan.frozen_accounting_expectation.exact_vtsr.canonical_fraction !== '1/4') {
  throw new Error('frozen accounting mismatch');
}
const effectObjects = [
  contract.external_effects,
  catalog.fixture_policy.external_effects,
  plan.execution_policy.external_effects,
  receipt.external_effects,
];
const effectKeys = ['network', 'provider', 'secret', 'remote', 'production', 'public'];
for (const effects of effectObjects) {
  if (!effects || effectKeys.some((key) => effects[key] !== false)) throw new Error('external-effect prefreeze mismatch');
}
NODE

readonly TEMP_PARENT="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
RUN_ROOT="$(mktemp -d "${TEMP_PARENT%/}/p1-070-targeted-verifier.XXXXXXXX")" || fail "TEMP_ROOT_CREATE"
readonly RUN_ROOT
readonly OWNERSHIP_TOKEN="${TASK_ID}:$$:${RUN_ROOT}"
printf '%s\n' "${OWNERSHIP_TOKEN}" > "${RUN_ROOT}/.p1-070-owner"

cleanup_owned_root() {
  local marker="${RUN_ROOT}/.p1-070-owner"
  [[ -d "${RUN_ROOT}" && ! -L "${RUN_ROOT}" ]] || return 0
  [[ -f "${marker}" && ! -L "${marker}" ]] || return 0
  [[ "$(<"${marker}")" == "${OWNERSHIP_TOKEN}" ]] || return 0
  case "${RUN_ROOT}" in
    "${TEMP_PARENT%/}"/p1-070-targeted-verifier.*)
      node --input-type=module - "${RUN_ROOT}" <<'NODE'
import fs from 'node:fs';
const [ownedRoot] = process.argv.slice(2);
fs.rmSync(ownedRoot, { recursive: true, force: false });
NODE
      ;;
    *) return 0 ;;
  esac
}
trap cleanup_owned_root EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

readonly GOLDEN_ROOT="${RUN_ROOT}/golden"
node "${CANONICAL_ROOT}/${RUNNER_REL}" \
  --canonical-root "${CANONICAL_ROOT}" \
  --output-root "${GOLDEN_ROOT}" \
  >"${RUN_ROOT}/runner.stdout" 2>"${RUN_ROOT}/runner.stderr" || fail "GOLDEN_RUNNER_NON_PASS"

for golden_file in ledger.jsonl reported-aggregate.json raw-artifact-manifest.json matrix-close-receipt.json; do
  [[ -f "${GOLDEN_ROOT}/${golden_file}" && ! -L "${GOLDEN_ROOT}/${golden_file}" ]] || fail "GOLDEN_OUTPUT_MISSING_OR_UNSAFE"
done
[[ -d "${GOLDEN_ROOT}/artifacts/entries" && ! -L "${GOLDEN_ROOT}/artifacts/entries" ]] || fail "GOLDEN_ARTIFACT_ROOT_MISSING_OR_UNSAFE"

run_recompute() {
  local fixture_root="$1"
  local stdout_path="$2"
  local stderr_path="$3"
  local plan_path="${4:-${CANONICAL_ROOT}/${PLAN_REL}}"
  node "${CANONICAL_ROOT}/${EVALUATOR_REL}" \
    --contract "${CANONICAL_ROOT}/${CONTRACT_REL}" \
    --plan "${plan_path}" \
    --prefreeze-receipt "${PREFREEZE_RECEIPT}" \
    --ledger "${fixture_root}/ledger.jsonl" \
    --artifact-root "${fixture_root}" \
    --reported-aggregate "${fixture_root}/reported-aggregate.json" \
    >"${stdout_path}" 2>"${stderr_path}"
}

run_recompute "${GOLDEN_ROOT}" "${RUN_ROOT}/golden-recompute.stdout" "${RUN_ROOT}/golden-recompute.stderr" || fail "GOLDEN_RECOMPUTATION_NON_PASS"

# Independently validate the runner bytes and the evaluator receipt. The
# evaluator's stdout is data only; it is parsed as JSON and is never executed.
node --input-type=module - \
  "${GOLDEN_ROOT}" \
  "${RUN_ROOT}/golden-recompute.stdout" \
  "${CANONICAL_ROOT}/${PLAN_REL}" <<'NODE' || fail "GOLDEN_ASSERTION_MISMATCH"
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [root, recomputeStdout, planPath] = process.argv.slice(2);
const effectKeys = ['network', 'provider', 'secret', 'remote', 'production', 'public'];
const sort = (value) => Array.isArray(value)
  ? value.map(sort)
  : value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, sort(value[key])]))
    : value;
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const identity = (p) => {
  const st = fs.lstatSync(p);
  if (!st.isFile() || st.isSymbolicLink()) throw new Error(`unsafe file ${p}`);
  const bytes = fs.readFileSync(p);
  return { sha256: sha(bytes), byte_length: bytes.length };
};
const checkIdentity = (p, expected, label) => {
  const actual = identity(p);
  if (actual.sha256 !== expected.sha256 || actual.byte_length !== expected.byte_length) {
    throw new Error(`${label} identity mismatch`);
  }
};
const assertEffectsFalse = (effects, label) => {
  if (!effects || effectKeys.some((key) => effects[key] !== false)) throw new Error(`${label} external effect`);
};

const visit = (dir) => {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.lstatSync(p);
    if (st.isSymbolicLink()) throw new Error(`symlink output ${p}`);
    if (st.isDirectory()) visit(p);
    else if (!st.isFile()) throw new Error(`non-regular output ${p}`);
  }
};
visit(root);

const plan = readJson(planPath);
const expectedOrder = plan.schedule.map((entry) => entry.entry_id);
const rawLedger = fs.readFileSync(path.join(root, 'ledger.jsonl'), 'utf8');
if (!rawLedger.endsWith('\n') || rawLedger.endsWith('\n\n')) throw new Error('ledger LF format');
const events = rawLedger.slice(0, -1).split('\n').map(JSON.parse);
if (events.length !== 13) throw new Error('ledger event count');
let previous = '0'.repeat(64);
for (let i = 0; i < events.length; i += 1) {
  const event = events[i];
  if (event.event_index !== i || event.previous_event_sha256 !== previous) throw new Error('ledger sequence');
  const copy = structuredClone(event);
  delete copy.event_sha256;
  const actual = sha(Buffer.from(`${JSON.stringify(sort(copy))}\n`, 'utf8'));
  if (actual !== event.event_sha256) throw new Error('ledger hash');
  previous = event.event_sha256;
}
const scheduled = events.filter((event) => event.event_type === 'RUN_SCHEDULED').map((event) => event.entry_id);
const terminal = events.filter((event) => event.event_type === 'RUN_TERMINAL').map((event) => event.entry_id);
if (JSON.stringify(scheduled) !== JSON.stringify(expectedOrder) || JSON.stringify(terminal) !== JSON.stringify(expectedOrder)) {
  throw new Error('schedule/terminal order');
}
if (events[0].event_type !== 'MATRIX_DECLARED' || events[6].event_type !== 'SCHEDULE_FROZEN' || events[12].event_type !== 'MATRIX_CLOSED') {
  throw new Error('ledger lifecycle');
}
for (const index of [0, 6, 12]) {
  if (!Object.hasOwn(events[index], 'entry_id') || events[index].entry_id !== null) throw new Error('null entry_id lifecycle binding');
}
const scheduleEvents = events.filter((event) => event.event_type === 'RUN_SCHEDULED');
for (let index = 0; index < plan.schedule.length; index += 1) {
  const expectedStimulus = sha(Buffer.from(`${JSON.stringify(sort(plan.schedule[index].stimulus))}\n`, 'utf8'));
  if (scheduleEvents[index].frozen_stimulus_sha256 !== expectedStimulus) throw new Error('frozen stimulus identity');
}

const rawManifest = readJson(path.join(root, 'raw-artifact-manifest.json'));
if (rawManifest.retained_entry_count !== 5 || rawManifest.entry_artifact_manifests.length !== 5) throw new Error('raw manifest count');
for (const manifestRef of rawManifest.entry_artifact_manifests) {
  const manifestPath = path.join(root, manifestRef.path);
  checkIdentity(manifestPath, manifestRef, manifestRef.path);
  const manifest = readJson(manifestPath);
  for (const fileRef of manifest.files) checkIdentity(path.join(root, fileRef.path), fileRef, fileRef.path);
}

const aggregate = readJson(path.join(root, 'reported-aggregate.json'));
if (aggregate.scheduled_count !== 5 || aggregate.eligible_denominator !== 4 ||
    aggregate.verified_success_numerator !== 1 || aggregate.failure_count !== 3 || aggregate.invalid_count !== 1 ||
    aggregate.exact_vtsr?.numerator !== 1 || aggregate.exact_vtsr?.denominator !== 4 ||
    aggregate.exact_vtsr?.canonical_fraction !== '1/4') throw new Error('aggregate counts');
const expectedReasons = {
  VERIFIED_SUCCESS: 1,
  WRONG_PATCH: 1,
  MISSING_EVIDENCE: 1,
  SCOPE_VIOLATION: 1,
  DECLARED_SHARED_HARNESS_INVALID: 1,
};
if (JSON.stringify(sort(aggregate.reason_code_distribution)) !== JSON.stringify(sort(expectedReasons))) throw new Error('reason distribution');
if (aggregate.candidate_claim_false_success_confusion_matrix?.true_positive !== 1 ||
    aggregate.candidate_claim_false_success_confusion_matrix?.false_positive !== 3 ||
    aggregate.candidate_claim_false_success_confusion_matrix?.true_negative !== 0 ||
    aggregate.candidate_claim_false_success_confusion_matrix?.false_negative !== 0 ||
    aggregate.candidate_claim_false_success_confusion_matrix?.infrastructure_invalid_excluded_from_binary_confusion !== 1) {
  throw new Error('false-success matrix');
}
assertEffectsFalse(aggregate.external_effects, 'aggregate');

for (let slot = 1; slot <= 5; slot += 1) {
  const entryId = expectedOrder[slot - 1];
  const entryDir = path.join(root, 'artifacts', 'entries', `${String(slot).padStart(2, '0')}-${entryId}`);
  const rollback = readJson(path.join(entryDir, 'rollback-receipt.json'));
  if (rollback.exact !== true || rollback.clean_state_before !== true || rollback.clean_state_after !== true ||
      rollback.source_root_initial_state !== 'ABSENT' || rollback.source_root_final_state !== 'ABSENT' ||
      !Array.isArray(rollback.path_set_before) || rollback.path_set_before.length !== 0 ||
      !Array.isArray(rollback.path_set_after) || rollback.path_set_after.length !== 0) throw new Error(`rollback ${entryId}`);
  assertEffectsFalse(readJson(path.join(entryDir, 'external-effects-receipt.json')), entryId);
}

const close = readJson(path.join(root, 'matrix-close-receipt.json'));
if (close.status !== 'CLOSED' || close.final_event_index !== 12 || close.final_event_sha256 !== events[12].event_sha256) throw new Error('close receipt');
checkIdentity(path.join(root, close.ledger.path), close.ledger, 'close ledger');
checkIdentity(path.join(root, close.raw_artifact_manifest.path), close.raw_artifact_manifest, 'close raw manifest');
checkIdentity(path.join(root, close.reported_aggregate.path), close.reported_aggregate, 'close aggregate');
assertEffectsFalse(close.external_effects, 'close');

const receiptText = fs.readFileSync(recomputeStdout, 'utf8');
const receipt = JSON.parse(receiptText);
if (receipt.status !== 'PASS') throw new Error('recompute status');
const counts = receipt.recomputed ?? receipt.accounting ?? receipt;
if (counts.scheduled_count !== 5 || counts.eligible_denominator !== 4 || counts.verified_success_numerator !== 1 ||
    counts.failure_count !== 3 || counts.invalid_count !== 1 || counts.exact_vtsr_fraction?.numerator !== 1 ||
    counts.exact_vtsr_fraction?.denominator !== 4 || counts.exact_vtsr_fraction?.canonical_fraction !== '1/4') {
  throw new Error('recompute counts');
}
if (receipt.reason !== 'PASS' || !Array.isArray(receipt.entry_reports) || receipt.entry_reports.length !== 5) {
  throw new Error('recompute receipt completeness');
}
assertEffectsFalse(receipt.external_effects, 'recompute');
NODE

# Snapshot every golden byte so every negative case is demonstrably derived
# from the same closed checkpoint and no case can mutate the golden lineage.
node --input-type=module - "${GOLDEN_ROOT}" >"${RUN_ROOT}/golden-tree.identity" <<'NODE'
import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto';
const [root] = process.argv.slice(2); const rows = [];
const walk = (dir) => { for (const name of fs.readdirSync(dir).sort()) { const p = path.join(dir, name); const st = fs.lstatSync(p); if (st.isSymbolicLink()) throw new Error('symlink'); if (st.isDirectory()) walk(p); else { const b=fs.readFileSync(p); rows.push(`${path.relative(root,p)}\t${b.length}\t${crypto.createHash('sha256').update(b).digest('hex')}`); } } };
walk(root); process.stdout.write(`${rows.join('\n')}\n`);
NODE

create_case_root() {
  local case_id="$1"
  local case_root
  case_root="$(mktemp -d "${RUN_ROOT}/case-${case_id}.XXXXXXXX")" || fail "CASE_ROOT_CREATE"
  local marker_token="${TASK_ID}:${case_id}:$$:${case_root}"
  printf '{"case_id":"%s","owned_path":"%s","owner_token":"%s","task_id":"%s"}\n' \
    "${case_id}" "${case_root}" "${marker_token}" "${TASK_ID}" >"${case_root}/.p1-070-case-owner.json"
  cp -R "${GOLDEN_ROOT}/." "${case_root}/"
  printf '%s\n' "${case_root}"
}

cleanup_case_root() {
  local case_id="$1"
  local case_root="$2"
  local marker="${case_root}/.p1-070-case-owner.json"
  [[ -d "${case_root}" && ! -L "${case_root}" && -f "${marker}" && ! -L "${marker}" ]] || fail "CASE_OWNERSHIP_MARKER_MISSING"
  node --input-type=module - "${marker}" "${case_id}" "${case_root}" "${TASK_ID}" <<'NODE' || exit 1
import fs from 'node:fs';
const [markerPath, caseId, root, taskId] = process.argv.slice(2);
const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
if (marker.case_id !== caseId || marker.owned_path !== root || marker.task_id !== taskId ||
    typeof marker.owner_token !== 'string' || !marker.owner_token.endsWith(`:${root}`)) process.exit(1);
fs.rmSync(root, { recursive: true, force: false });
NODE
}

mutate_case() {
  local case_id="$1"
  local case_root="$2"
  node --input-type=module - "${case_id}" "${case_root}" "${CANONICAL_ROOT}/${PLAN_REL}" <<'NODE'
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [caseId, root, canonicalPlanPath] = process.argv.slice(2);
const sort = (value) => Array.isArray(value) ? value.map(sort) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, sort(value[key])])) : value;
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const jsonBytes = (value) => Buffer.from(`${JSON.stringify(sort(value))}\n`, 'utf8');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const assertOwnedPath = (p) => {
  const resolved = path.resolve(p);
  const resolvedRoot = path.resolve(root);
  if (!resolved.startsWith(`${resolvedRoot}${path.sep}`)) throw new Error(`mutation escaped owned root: ${p}`);
  let cursor = resolvedRoot;
  for (const component of path.relative(resolvedRoot, path.dirname(resolved)).split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, component);
    const componentStat = fs.lstatSync(cursor);
    if (!componentStat.isDirectory() || componentStat.isSymbolicLink()) throw new Error(`unsafe path component: ${cursor}`);
  }
  return resolved;
};
const makeCopiedTargetWritable = (p) => {
  const resolved = assertOwnedPath(p);
  const st = fs.lstatSync(resolved);
  if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) throw new Error(`unsafe copied mutation target: ${p}`);
  fs.chmodSync(resolved, 0o600);
};
const writeJson = (p, value) => {
  const resolved = assertOwnedPath(p);
  if (fs.existsSync(resolved)) {
    makeCopiedTargetWritable(resolved);
    fs.writeFileSync(resolved, jsonBytes(value), { flag: 'w' });
  } else {
    fs.writeFileSync(resolved, jsonBytes(value), { flag: 'wx', mode: 0o600 });
  }
  fs.chmodSync(resolved, 0o400);
};
const identity = (p) => { const bytes = fs.readFileSync(p); return { sha256: sha(bytes), byte_length: bytes.length }; };
const ledgerPath = path.join(root, 'ledger.jsonl');
const readLedger = () => fs.readFileSync(ledgerPath, 'utf8').trimEnd().split('\n').map(JSON.parse);
const writeLedger = (events) => {
  let previous = '0'.repeat(64);
  for (let index = 0; index < events.length; index += 1) {
    const event = events[index];
    event.event_index = index;
    event.previous_event_sha256 = previous;
    if (event.event_type === 'MATRIX_CLOSED') event.last_terminal_event_sha256 = previous;
    delete event.event_sha256;
    event.event_sha256 = sha(Buffer.from(`${JSON.stringify(sort(event))}\n`, 'utf8'));
    previous = event.event_sha256;
  }
  makeCopiedTargetWritable(ledgerPath);
  fs.writeFileSync(ledgerPath, `${events.map((event) => JSON.stringify(sort(event))).join('\n')}\n`, { flag: 'w' });
  fs.chmodSync(ledgerPath, 0o400);
  const closeReceiptPath = path.join(root, 'matrix-close-receipt.json');
  const closeReceipt = readJson(closeReceiptPath);
  closeReceipt.ledger = { path: 'ledger.jsonl', ...identity(ledgerPath) };
  const rawManifestPath = path.join(root, 'raw-artifact-manifest.json');
  closeReceipt.raw_artifact_manifest = { path: 'raw-artifact-manifest.json', ...identity(rawManifestPath) };
  const reportPath = path.join(root, 'reported-aggregate.json');
  closeReceipt.reported_aggregate = { path: 'reported-aggregate.json', ...identity(reportPath) };
  closeReceipt.final_event_index = events.at(-1).event_index;
  closeReceipt.final_event_sha256 = events.at(-1).event_sha256;
  writeJson(closeReceiptPath, closeReceipt);
};
const closeEvent = (events) => {
  const event = events.find((entry) => entry.event_type === 'MATRIX_CLOSED');
  if (!event) throw new Error('missing close event');
  return event;
};
const updateReportAndLedger = (mutator) => {
  const reportPath = path.join(root, 'reported-aggregate.json');
  const report = readJson(reportPath);
  mutator(report);
  writeJson(reportPath, report);
  const events = readLedger();
  Object.assign(closeEvent(events), {
    reported_aggregate_sha256: identity(reportPath).sha256,
    reported_aggregate_byte_length: identity(reportPath).byte_length,
  });
  writeLedger(events);
};
const rebindEntry = (entryDirName, mutator, directKind = null) => {
  const dir = path.join(root, 'artifacts', 'entries', entryDirName);
  const entryRecordPath = path.join(dir, 'entry-record.json');
  const entryRecord = readJson(entryRecordPath);
  const changed = mutator({ dir, entryRecord });
  for (const [recordKey, changedPath] of Object.entries(changed.recordBindings ?? {})) {
    entryRecord[recordKey] = { path: path.relative(root, changedPath), ...identity(changedPath) };
  }
  writeJson(entryRecordPath, entryRecord);
  const manifestPath = path.join(dir, 'artifact-manifest.json');
  const manifest = readJson(manifestPath);
  for (const changedPath of [entryRecordPath, ...(changed.changedPaths ?? [])]) {
    const rel = path.relative(root, changedPath);
    const ref = manifest.files.find((entry) => entry.path === rel);
    if (!ref) throw new Error(`manifest ref missing ${rel}`);
    Object.assign(ref, identity(changedPath));
  }
  writeJson(manifestPath, manifest);
  const rawManifestPath = path.join(root, 'raw-artifact-manifest.json');
  const rawManifest = readJson(rawManifestPath);
  const manifestRel = path.relative(root, manifestPath);
  const topRef = rawManifest.entry_artifact_manifests.find((entry) => entry.path === manifestRel);
  if (!topRef) throw new Error('top manifest ref missing');
  Object.assign(topRef, identity(manifestPath));
  writeJson(rawManifestPath, rawManifest);
  const events = readLedger();
  const terminal = events.find((event) => event.event_type === 'RUN_TERMINAL' && event.entry_id === entryRecord.entry_id);
  if (!terminal) throw new Error('terminal missing');
  terminal.raw_artifact_manifest_sha256 = identity(manifestPath).sha256;
  terminal.raw_artifact_manifest_byte_length = identity(manifestPath).byte_length;
  if (directKind === 'rollback') {
    terminal.rollback_receipt_sha256 = entryRecord.rollback.sha256;
    terminal.rollback_receipt_byte_length = entryRecord.rollback.byte_length;
  }
  if (directKind === 'external_effects') {
    terminal.external_effects_receipt_sha256 = entryRecord.external_effects.sha256;
    terminal.external_effects_receipt_byte_length = entryRecord.external_effects.byte_length;
  }
  const close = closeEvent(events);
  close.raw_artifact_manifest_sha256 = identity(rawManifestPath).sha256;
  close.raw_artifact_manifest_byte_length = identity(rawManifestPath).byte_length;
  if (changed.mutateReport) {
    const reportPath = path.join(root, 'reported-aggregate.json');
    const report = readJson(reportPath);
    changed.mutateReport(report);
    writeJson(reportPath, report);
    close.reported_aggregate_sha256 = identity(reportPath).sha256;
    close.reported_aggregate_byte_length = identity(reportPath).byte_length;
  }
  writeLedger(events);
};

switch (caseId) {
  case 'HISTORY_DELETE_RECHAINED': {
    const events = readLedger();
    const index = events.findIndex((event) => event.event_type === 'RUN_TERMINAL' && event.entry_id === 'WRONG_PATCH');
    if (index < 0) throw new Error('target missing');
    events.splice(index, 1);
    writeLedger(events);
    break;
  }
  case 'DENOMINATOR_REDUCTION_REBOUND':
    updateReportAndLedger((report) => { report.eligible_denominator = 3; report.exact_vtsr = { numerator: 1, denominator: 3, canonical_fraction: '1/3' }; });
    break;
  case 'POST_HOC_INVALID_RECHAINED':
    rebindEntry('02-WRONG_PATCH', ({ entryRecord }) => {
      entryRecord.eligible = false;
      return { mutateReport: (report) => {
        report.eligible_denominator = 3; report.failure_count = 2; report.invalid_count = 2;
        report.exact_vtsr = { numerator: 1, denominator: 3, canonical_fraction: '1/3' };
        const row = report.classifications.find((entry) => entry.entry_id === 'WRONG_PATCH');
        row.independent_verdict = 'INFRASTRUCTURE_INVALID'; row.reason_family = 'DECLARED_SHARED_HARNESS_INVALID';
        report.reason_code_distribution.WRONG_PATCH = 0;
        report.reason_code_distribution.DECLARED_SHARED_HARNESS_INVALID = 2;
      }};
    });
    break;
  case 'DUPLICATE_SUCCESS_TERMINAL_RECHAINED': {
    const events = readLedger();
    const terminal = events.find((event) => event.event_type === 'RUN_TERMINAL' && event.entry_id === 'CORRECT_RESULT');
    const closeIndex = events.findIndex((event) => event.event_type === 'MATRIX_CLOSED');
    events.splice(closeIndex, 0, structuredClone(terminal));
    writeLedger(events);
    break;
  }
  case 'SCHEDULE_REORDER_REINDEXED_RECHAINED': {
    const events = readLedger();
    [events[1], events[2]] = [events[2], events[1]];
    writeLedger(events);
    break;
  }
  case 'NUMERATOR_INFLATION_REBOUND':
    updateReportAndLedger((report) => { report.verified_success_numerator = 2; report.failure_count = 2; report.exact_vtsr = { numerator: 2, denominator: 4, canonical_fraction: '2/4' }; });
    break;
  case 'REASON_DISTRIBUTION_MUTATION_REBOUND':
    updateReportAndLedger((report) => { report.reason_code_distribution.VERIFIED_SUCCESS = 2; report.reason_code_distribution.WRONG_PATCH = 0; });
    break;
  case 'PLAN_IDENTITY_MUTATION': {
    const plan = readJson(canonicalPlanPath);
    plan.schedule[4].eligible = true;
    const mutatedPlan = path.join(root, 'mutated-plan.json');
    writeJson(mutatedPlan, plan);
    const planIdentity = identity(mutatedPlan);
    const events = readLedger();
    for (const event of events) {
      if (Object.hasOwn(event, 'matrix_plan_sha256')) {
        event.matrix_plan_sha256 = planIdentity.sha256;
        event.matrix_plan_byte_length = planIdentity.byte_length;
      }
    }
    writeLedger(events);
    break;
  }
  case 'TERMINAL_ARTIFACT_IDENTITY_TAMPER': {
    const target = path.join(root, 'artifacts', 'entries', '02-WRONG_PATCH', 'raw-stdout.txt');
    makeCopiedTargetWritable(target);
    fs.appendFileSync(target, 'X', 'utf8');
    fs.chmodSync(target, 0o400);
    break;
  }
  case 'ROLLBACK_FALSE':
    rebindEntry('01-CORRECT_RESULT', ({ dir }) => {
      const receiptPath = path.join(dir, 'rollback-receipt.json');
      const receipt = readJson(receiptPath);
      receipt.exact = false; receipt.source_root_final_state = 'PRESENT';
      writeJson(receiptPath, receipt);
      return { changedPaths: [receiptPath], recordBindings: { rollback: receiptPath } };
    }, 'rollback');
    break;
  case 'EXTERNAL_EFFECT_TRUE':
    rebindEntry('01-CORRECT_RESULT', ({ dir }) => {
      const receiptPath = path.join(dir, 'external-effects-receipt.json');
      const receipt = readJson(receiptPath); receipt.network = true; writeJson(receiptPath, receipt);
      return { changedPaths: [receiptPath], recordBindings: { external_effects: receiptPath } };
    }, 'external_effects');
    break;
  default: throw new Error(`unknown case ${caseId}`);
}
NODE
}

negative_count=0
false_accepts=0
while IFS=$'\t' read -r case_id expected_reason; do
  [[ -n "${case_id}" && -n "${expected_reason}" ]] || fail "NEGATIVE_CATALOG_PARSE"
  case_root="$(create_case_root "${case_id}")"
  mutate_case "${case_id}" "${case_root}" || fail "NEGATIVE_MUTATION_${case_id}"
  plan_arg="${CANONICAL_ROOT}/${PLAN_REL}"
  [[ "${case_id}" != "PLAN_IDENTITY_MUTATION" ]] || plan_arg="${case_root}/mutated-plan.json"
  if run_recompute "${case_root}" "${case_root}/recompute.stdout" "${case_root}/recompute.stderr" "${plan_arg}"; then
    recompute_status=0
  else
    recompute_status=$?
  fi
  if [[ "${recompute_status}" -eq 0 ]]; then
    false_accepts=$((false_accepts + 1))
    fail "FALSE_ACCEPT_${case_id}"
  fi
  node --input-type=module - "${case_root}/recompute.stdout" "${expected_reason}" <<'NODE' || fail "NEGATIVE_REASON_MISMATCH_${case_id}"
import fs from 'node:fs';
const [stdoutPath, expectedReason] = process.argv.slice(2);
const receipt = JSON.parse(fs.readFileSync(stdoutPath, 'utf8'));
if (receipt.status !== 'NON_PASS' || receipt.reason !== expectedReason ||
    receipt.schema_version !== 'offline-scheduled-matrix-independent-recomputation-error/v1') process.exit(1);
NODE
  cleanup_case_root "${case_id}" "${case_root}" || fail "CASE_CLEANUP_${case_id}"
  negative_count=$((negative_count + 1))
done < <(node --input-type=module - "${CANONICAL_ROOT}/${CATALOG_REL}" <<'NODE'
import fs from 'node:fs';
const [catalogPath] = process.argv.slice(2);
const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
for (const entry of catalog.cases) process.stdout.write(`${entry.case_id}\t${entry.expected_reason}\n`);
NODE
)

[[ "${negative_count}" -eq 11 && "${false_accepts}" -eq 0 ]] || fail "NEGATIVE_COUNT_OR_FALSE_ACCEPT_BUDGET"

# Re-hash the golden only after every disposable mutation has been evaluated.
node --input-type=module - "${GOLDEN_ROOT}" >"${RUN_ROOT}/golden-tree.after.identity" <<'NODE'
import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto';
const [root] = process.argv.slice(2); const rows = [];
const walk = (dir) => { for (const name of fs.readdirSync(dir).sort()) { const p = path.join(dir, name); const st = fs.lstatSync(p); if (st.isSymbolicLink()) throw new Error('symlink'); if (st.isDirectory()) walk(p); else { const b=fs.readFileSync(p); rows.push(`${path.relative(root,p)}\t${b.length}\t${crypto.createHash('sha256').update(b).digest('hex')}`); } } };
walk(root); process.stdout.write(`${rows.join('\n')}\n`);
NODE
cmp -s "${RUN_ROOT}/golden-tree.identity" "${RUN_ROOT}/golden-tree.after.identity" || fail "GOLDEN_MUTATED_BY_NEGATIVE_CASE"

printf 'P1_070_TARGETED_VERIFIER_OK golden=5/5 independent_recompute=PASS negatives=%d/11 false_accepts=%d exact_vtsr=1/4 numerator=1 denominator=4 failures=3 invalid=1 rollback=PASS external_effects=FALSE cleanup=PASS\n' \
  "${negative_count}" "${false_accepts}"

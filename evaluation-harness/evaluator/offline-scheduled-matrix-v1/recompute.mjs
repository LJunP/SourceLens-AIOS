#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  closeSync,
  constants as fsConstants,
  fstatSync,
  lstatSync,
  openSync,
  readFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { fileURLToPath } from "node:url";

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(MODULE_DIR, "../../..");
const TASK_ID =
  "AIOS-P1-070_OFFLINE_SCHEDULED_MATRIX_VTSR_AND_FALSE_SUCCESS_EXPERIMENT";
const GENESIS_SHA256 = "0".repeat(64);
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const O_NOFOLLOW = fsConstants.O_NOFOLLOW ?? 0;
const PREFREEZE_RECEIPT_IDENTITY = Object.freeze({
  sha256: "de3d9e2c40cb26e955b34cffdcd0938a604f76cd621bd8a82a4ad1d7fe2e0695",
  byte_length: 6946,
});
const FALSE_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const PRIMARY_RESULTS = Object.freeze(["PASS", "NON_PASS", "NOT_RUN", "ERROR"]);
const INDEPENDENT_VERDICTS = Object.freeze([
  "VERIFIED_SUCCESS",
  "FAILURE",
  "INFRASTRUCTURE_INVALID",
]);

export class RecomputationNonPass extends Error {
  constructor(reason) {
    super(reason);
    this.name = "RecomputationNonPass";
    this.reason = reason;
  }
}

const fail = (reason) => {
  throw new RecomputationNonPass(reason);
};
const assert = (condition, reason) => {
  if (!condition) fail(reason);
};
const isObject = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const identityOf = (bytes) => ({
  sha256: sha256(bytes),
  byte_length: bytes.length,
});

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (isObject(value)) {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])]),
    );
  }
  assert(
    value === null ||
      typeof value === "string" ||
      typeof value === "boolean" ||
      (typeof value === "number" && Number.isFinite(value)),
    "JSON_VALUE_INVALID",
  );
  return value;
}

export function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalize(value))}\n`, "utf8");
}

function sameJson(left, right) {
  return isDeepStrictEqual(canonicalize(left), canonicalize(right));
}

function exactKeys(value, keys, reason) {
  assert(isObject(value), reason);
  assert(sameJson(Object.keys(value).sort(), [...keys].sort()), reason);
}

function parseUtf8(bytes, reason) {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail(reason);
  }
}

function parseJsonBytes(bytes, reason, canonical = true) {
  const text = parseUtf8(bytes, reason);
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail(reason);
  }
  if (canonical) assert(bytes.equals(canonicalJsonBytes(value)), reason);
  return value;
}

function validateIdentity(value, reason) {
  exactKeys(value, ["sha256", "byte_length"], reason);
  assert(typeof value.sha256 === "string" && SHA256_PATTERN.test(value.sha256), reason);
  assert(Number.isSafeInteger(value.byte_length) && value.byte_length >= 0, reason);
  return value;
}

function assertAbsoluteCanonicalPath(path, reason) {
  assert(typeof path === "string" && isAbsolute(path) && !path.includes("\0"), reason);
  assert(resolve(path) === path, reason);
}

function assertDirectoryChainNoSymlink(path, reason) {
  assertAbsoluteCanonicalPath(path, reason);
  const parsedRoot = resolve(sep);
  const components = relative(parsedRoot, path).split(sep).filter(Boolean);
  let current = parsedRoot;
  for (const component of components) {
    current = join(current, component);
    let stat;
    try {
      stat = lstatSync(current);
    } catch {
      fail(reason);
    }
    assert(!stat.isSymbolicLink() && stat.isDirectory(), reason);
  }
}

function containedLeaf(root, relativePath, reason) {
  assertAbsoluteCanonicalPath(root, reason);
  assert(
    typeof relativePath === "string" &&
      relativePath.length > 0 &&
      !isAbsolute(relativePath) &&
      !relativePath.includes("\0") &&
      !relativePath.endsWith("/"),
    reason,
  );
  const candidate = resolve(root, relativePath);
  const rel = relative(root, candidate);
  assert(rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel), reason);
  assert(sameJson(rel.split(sep), relativePath.split("/")), reason);
  assertDirectoryChainNoSymlink(root, reason);
  const parentRelative = dirname(rel);
  if (parentRelative !== ".") {
    let current = root;
    for (const component of parentRelative.split(sep)) {
      current = join(current, component);
      let stat;
      try {
        stat = lstatSync(current);
      } catch {
        fail(reason);
      }
      assert(!stat.isSymbolicLink() && stat.isDirectory(), reason);
    }
  }
  return candidate;
}

function safeReadRegular(path, expected, reason) {
  assertAbsoluteCanonicalPath(path, reason);
  assertDirectoryChainNoSymlink(dirname(path), reason);
  let before;
  try {
    before = lstatSync(path);
  } catch {
    fail(reason);
  }
  assert(before.isFile() && !before.isSymbolicLink() && before.nlink === 1, reason);

  let descriptor;
  try {
    descriptor = openSync(path, fsConstants.O_RDONLY | O_NOFOLLOW);
  } catch {
    fail(reason);
  }
  try {
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile() &&
        opened.nlink === 1 &&
        opened.dev === before.dev &&
        opened.ino === before.ino,
      reason,
    );
    const bytes = readFileSync(descriptor);
    const after = lstatSync(path);
    assert(
      after.isFile() &&
        !after.isSymbolicLink() &&
        after.nlink === 1 &&
        after.dev === opened.dev &&
        after.ino === opened.ino &&
        after.size === opened.size &&
        after.mtimeMs === opened.mtimeMs,
      reason,
    );
    const identity = identityOf(bytes);
    if (expected !== undefined) {
      validateIdentity(expected, reason);
      assert(sameJson(identity, expected), reason);
    }
    return { bytes, identity };
  } finally {
    closeSync(descriptor);
  }
}

function readContained(root, record, reason) {
  exactKeys(record, ["relative_path", "sha256", "byte_length"], reason);
  const identity = validateIdentity(
    { sha256: record.sha256, byte_length: record.byte_length },
    reason,
  );
  const path = containedLeaf(root, record.relative_path, reason);
  return { ...safeReadRegular(path, identity, reason), path };
}

function pathIdentity(record, reason) {
  exactKeys(record, ["path", "sha256", "byte_length"], reason);
  assert(
    typeof record.path === "string" && record.path.length > 0,
    reason,
  );
  return {
    path: record.path,
    ...validateIdentity(
      { sha256: record.sha256, byte_length: record.byte_length },
      reason,
    ),
  };
}

function looseJson(file, reason) {
  const value = parseJsonBytes(file.bytes, reason, false);
  const pretty = Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8");
  assert(
    file.bytes.equals(canonicalJsonBytes(value)) || file.bytes.equals(pretty),
    reason,
  );
  return value;
}

function oneJsonLine(bytes, reason) {
  const text = parseUtf8(bytes, reason);
  assert(text.endsWith("\n") && !text.endsWith("\n\n") && !text.includes("\r"), reason);
  let value;
  try {
    value = JSON.parse(text.slice(0, -1));
  } catch {
    fail(reason);
  }
  assert(bytes.equals(Buffer.from(`${JSON.stringify(value)}\n`, "utf8")), reason);
  return value;
}

function parseCli(argv) {
  const names = [
    "--contract",
    "--plan",
    "--prefreeze-receipt",
    "--ledger",
    "--artifact-root",
    "--reported-aggregate",
  ];
  assert(argv.length === names.length * 2, "CLI_ARGUMENT_MISMATCH");
  const accepted = new Set(names);
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    assert(
      accepted.has(flag) &&
        !values.has(flag) &&
        typeof value === "string" &&
        isAbsolute(value) &&
        resolve(value) === value,
      "CLI_ARGUMENT_MISMATCH",
    );
    values.set(flag, value);
  }
  assert(names.every((name) => values.has(name)), "CLI_ARGUMENT_MISMATCH");
  return Object.fromEntries(names.map((name) => [name.slice(2).replaceAll("-", "_"), values.get(name)]));
}

function frozenOutput(receipt, schemaVersion, path, reason) {
  assert(Array.isArray(receipt.frozen_outputs), reason);
  const matches = receipt.frozen_outputs.filter(
    (entry) => entry.path === path && entry.schema_version === schemaVersion,
  );
  assert(matches.length === 1, reason);
  const entry = matches[0];
  assert(typeof entry.sha256 === "string" && Number.isSafeInteger(entry.byte_length), reason);
  return { sha256: entry.sha256, byte_length: entry.byte_length };
}

function validateFrozenAuthorities(cli) {
  const receiptFile = safeReadRegular(
    cli.prefreeze_receipt,
    PREFREEZE_RECEIPT_IDENTITY,
    "PREFREEZE_RECEIPT_IDENTITY_MISMATCH",
  );
  const receipt = parseJsonBytes(
    receiptFile.bytes,
    "PREFREEZE_RECEIPT_INVALID",
    false,
  );
  assert(
    receipt.schema_version === "p1-070-quality-prefreeze-receipt/v1" &&
      receipt.record_type === "CREATE_ONCE_EXACT_PREFREEZE_QUALITY_RECEIPT" &&
      receipt.status === "PASS" &&
      receipt.task_id === TASK_ID,
    "PREFREEZE_RECEIPT_INVALID",
  );

  const contractRelative =
    "evaluation-harness/contracts/offline-scheduled-matrix-v1/offline-scheduled-matrix-v1.contract.json";
  const planRelative =
    "evaluation-harness/fixtures/offline-scheduled-matrix-v1/matrix-plan.json";
  const negativeCatalogRelative =
    "evaluation-harness/fixtures/offline-scheduled-matrix-v1/negative-cases.json";
  assert(cli.contract === resolve(REPOSITORY_ROOT, contractRelative), "CONTRACT_IDENTITY_MISMATCH");
  const contractIdentity = frozenOutput(
    receipt,
    "offline-scheduled-matrix-contract/v1",
    contractRelative,
    "CONTRACT_IDENTITY_MISMATCH",
  );
  const contractFile = safeReadRegular(
    cli.contract,
    contractIdentity,
    "CONTRACT_IDENTITY_MISMATCH",
  );
  const contract = parseJsonBytes(contractFile.bytes, "CONTRACT_INVALID", false);
  assert(
    contract.schema_version === "offline-scheduled-matrix-contract/v1" &&
      contract.status === "FROZEN_PREFREEZE" &&
      contract.task_id === TASK_ID &&
      contract.prefreeze_outputs?.prefreeze_receipt?.path === cli.prefreeze_receipt,
    "CONTRACT_INVALID",
  );

  const planIdentity = frozenOutput(
    receipt,
    "offline-scheduled-matrix-plan/v1",
    planRelative,
    "PLAN_IDENTITY_MISMATCH",
  );
  const planFile = safeReadRegular(cli.plan, planIdentity, "PLAN_IDENTITY_MISMATCH");
  const plan = parseJsonBytes(planFile.bytes, "PLAN_IDENTITY_MISMATCH", false);
  assert(
    plan.schema_version === "offline-scheduled-matrix-plan/v1" &&
      plan.status === "FROZEN_BEFORE_ANY_TERMINAL_OUTPUT_INSPECTION" &&
      plan.task_id === TASK_ID &&
      sameJson(plan.contract_identity, {
        path: contractRelative,
        ...contractIdentity,
      }),
    "PLAN_IDENTITY_MISMATCH",
  );
  assert(cli.plan === resolve(REPOSITORY_ROOT, planRelative), "PLAN_IDENTITY_MISMATCH");

  const negativeCatalogIdentity = frozenOutput(
    receipt,
    "offline-scheduled-matrix-negative-catalog/v1",
    negativeCatalogRelative,
    "NEGATIVE_CATALOG_IDENTITY_MISMATCH",
  );
  const negativeCatalogFile = safeReadRegular(
    resolve(REPOSITORY_ROOT, negativeCatalogRelative),
    negativeCatalogIdentity,
    "NEGATIVE_CATALOG_IDENTITY_MISMATCH",
  );
  const negativeCatalog = parseJsonBytes(
    negativeCatalogFile.bytes,
    "NEGATIVE_CATALOG_IDENTITY_MISMATCH",
    false,
  );
  assert(
    negativeCatalog.schema_version ===
      "offline-scheduled-matrix-negative-catalog/v1" &&
      negativeCatalog.status === "FROZEN_PREFREEZE" &&
      negativeCatalog.task_id === TASK_ID &&
      sameJson(negativeCatalog.contract_identity, {
        path: contractRelative,
        ...contractIdentity,
      }) &&
      sameJson(negativeCatalog.matrix_plan_identity, {
        path: planRelative,
        ...planIdentity,
      }) &&
      sameJson(
        negativeCatalog.cases?.map((entry) => entry.case_id),
        contract.mandatory_negative_case_ids,
      ) &&
      negativeCatalog.counts?.catalog_entries === 11 &&
      negativeCatalog.counts?.allowed_false_accepts === 0,
    "NEGATIVE_CATALOG_IDENTITY_MISMATCH",
  );
  return {
    contract,
    contractIdentity,
    plan,
    planIdentity,
    negativeCatalog,
    negativeCatalogIdentity,
    receiptFile,
  };
}

function validatePlan(plan, contract) {
  assert(Array.isArray(plan.schedule), "PLAN_IDENTITY_MISMATCH");
  const expectedOrder = contract.matrix_accounting?.frozen_entry_order;
  assert(
    Array.isArray(expectedOrder) &&
      plan.schedule.length === expectedOrder.length &&
      plan.schedule.length === 5,
    "PLAN_IDENTITY_MISMATCH",
  );
  for (let index = 0; index < plan.schedule.length; index += 1) {
    const entry = plan.schedule[index];
    assert(
      isObject(entry) &&
        entry.slot === index + 1 &&
        entry.entry_id === expectedOrder[index] &&
        typeof entry.eligible === "boolean" &&
        ["CLAIMED_SUCCESS", "NO_SUCCESS_CLAIM"].includes(entry.candidate_claim) &&
        isObject(entry.stimulus),
      "PLAN_IDENTITY_MISMATCH",
    );
  }
  assert(
    plan.schedule.filter((entry) => entry.eligible).length === 4 &&
      plan.schedule.at(-1).eligible === false &&
      plan.schedule.at(-1).entry_id === "DECLARED_SHARED_HARNESS_INVALID_CONTROL" &&
      plan.schedule.at(-1).stimulus.control_type ===
        "PREDECLARED_SHARED_HARNESS_INVALID_CONTROL" &&
      plan.schedule.at(-1).stimulus.trigger_boundary ===
        "BEFORE_CHILD_START_AND_BEFORE_ANY_CANDIDATE_OUTPUT" &&
      plan.schedule.at(-1).stimulus.system_under_test_attributable === false,
    "PLAN_IDENTITY_MISMATCH",
  );
  assert(
    sameJson(contract.external_effects, FALSE_EFFECTS) &&
      sameJson(plan.execution_policy?.external_effects, FALSE_EFFECTS) &&
      contract.event_ledger?.format ===
        "UTF8_CANONICAL_JSONL_EXACTLY_ONE_LF_PER_EVENT" &&
      contract.event_ledger?.mutation_after_close === "FORBIDDEN" &&
      plan.ledger_lifecycle?.event_count === 13 &&
      plan.ledger_lifecycle?.append_only === true &&
      plan.ledger_lifecycle?.close_terminal === true,
    "PLAN_IDENTITY_MISMATCH",
  );
  return plan.schedule;
}

function validateAcceptedInputIdentities(plan) {
  assert(isObject(plan.accepted_input_identities), "ACCEPTED_INPUT_IDENTITY_MISMATCH");
  const observed = Object.create(null);
  for (const [name, record] of Object.entries(plan.accepted_input_identities)) {
    assert(
      isObject(record) &&
        typeof record.path === "string" &&
        !isAbsolute(record.path),
      "ACCEPTED_INPUT_IDENTITY_MISMATCH",
    );
    const identity = validateIdentity(
      { sha256: record.sha256, byte_length: record.byte_length },
      "ACCEPTED_INPUT_IDENTITY_MISMATCH",
    );
    const path = containedLeaf(
      REPOSITORY_ROOT,
      record.path,
      "ACCEPTED_INPUT_IDENTITY_MISMATCH",
    );
    safeReadRegular(path, identity, "ACCEPTED_INPUT_IDENTITY_MISMATCH");
    observed[name] = { path: record.path, ...identity };
  }
  return observed;
}

function parseCanonicalLedger(bytes) {
  const text = parseUtf8(bytes, "LEDGER_FORMAT_INVALID");
  assert(text.endsWith("\n") && !text.endsWith("\n\n") && !text.includes("\r"), "LEDGER_FORMAT_INVALID");
  const lineTexts = text.slice(0, -1).split("\n");
  assert(lineTexts.every((line) => line.length > 0), "LEDGER_FORMAT_INVALID");
  return lineTexts.map((line) => {
    const bytesWithLf = Buffer.from(`${line}\n`, "utf8");
    return parseJsonBytes(bytesWithLf, "LEDGER_FORMAT_INVALID", true);
  });
}

function eventDigest(event) {
  const withoutDigest = { ...event };
  delete withoutDigest.event_sha256;
  return sha256(canonicalJsonBytes(withoutDigest));
}

function validateLedger(events, plan, frozen) {
  const planIdentity = frozen.planIdentity;
  const terminalCounts = new Map();
  for (const event of events) {
    if (event?.event_type === "RUN_TERMINAL" && typeof event.entry_id === "string") {
      terminalCounts.set(event.entry_id, (terminalCounts.get(event.entry_id) ?? 0) + 1);
    }
  }
  if ([...terminalCounts.values()].some((count) => count > 1)) {
    fail("DUPLICATE_TERMINAL_EVENT");
  }
  assert(events.length === 13, "HISTORY_INTEGRITY_MISMATCH");

  const expectedLifecycle = [
    ["MATRIX_DECLARED", null],
    ...plan.map((entry) => ["RUN_SCHEDULED", entry.entry_id]),
    ["SCHEDULE_FROZEN", null],
    ...plan.map((entry) => ["RUN_TERMINAL", entry.entry_id]),
    ["MATRIX_CLOSED", null],
  ];
  let previous = GENESIS_SHA256;
  for (let index = 0; index < events.length; index += 1) {
    const event = events[index];
    assert(isObject(event), "HISTORY_INTEGRITY_MISMATCH");
    assert(
      event.schema_version === "offline-scheduled-matrix-ledger-event/v1" &&
        event.task_id === TASK_ID,
      "HISTORY_INTEGRITY_MISMATCH",
    );
    if (index >= 1 && index <= 5) {
      assert(
        event.event_type === "RUN_SCHEDULED" &&
          event.entry_id === plan[index - 1].entry_id,
        "SCHEDULE_ORDER_MISMATCH",
      );
    }
    const [expectedType, expectedEntry] = expectedLifecycle[index];
    assert(
      event.event_index === index &&
        event.event_type === expectedType &&
        (expectedEntry === null ? event.entry_id === null : event.entry_id === expectedEntry),
      "HISTORY_INTEGRITY_MISMATCH",
    );
    assert(
      event.previous_event_sha256 === previous &&
        typeof event.event_sha256 === "string" &&
        SHA256_PATTERN.test(event.event_sha256) &&
        eventDigest(event) === event.event_sha256,
      "HISTORY_INTEGRITY_MISMATCH",
    );
    previous = event.event_sha256;
  }

  const declared = events[0];
  assert(
    declared.contract_sha256 === frozen.contractIdentity.sha256 &&
      declared.contract_byte_length === frozen.contractIdentity.byte_length &&
      declared.matrix_plan_sha256 === frozen.planIdentity.sha256 &&
      declared.matrix_plan_byte_length === frozen.planIdentity.byte_length &&
      declared.negative_catalog_sha256 === frozen.negativeCatalogIdentity.sha256 &&
      declared.negative_catalog_byte_length === frozen.negativeCatalogIdentity.byte_length &&
      declared.prefreeze_receipt_sha256 === frozen.receiptFile.identity.sha256 &&
      declared.prefreeze_receipt_byte_length === frozen.receiptFile.identity.byte_length,
    "HISTORY_INTEGRITY_MISMATCH",
  );

  for (let index = 0; index < plan.length; index += 1) {
    const frozen = plan[index];
    const scheduled = events[index + 1];
    assert(
      scheduled.matrix_plan_sha256 === planIdentity.sha256 &&
        scheduled.matrix_plan_byte_length === planIdentity.byte_length &&
        scheduled.slot === frozen.slot &&
        scheduled.entry_id === frozen.entry_id &&
        scheduled.eligible === frozen.eligible &&
        scheduled.candidate_claim === frozen.candidate_claim &&
        scheduled.frozen_stimulus_sha256 === sha256(canonicalJsonBytes(frozen.stimulus)),
      "SCHEDULE_ORDER_MISMATCH",
    );
  }
  const scheduleFrozen = events[6];
  assert(
    scheduleFrozen.matrix_plan_sha256 === planIdentity.sha256 &&
      scheduleFrozen.matrix_plan_byte_length === planIdentity.byte_length &&
      scheduleFrozen.scheduled_count === plan.length &&
      sameJson(
        scheduleFrozen.frozen_order,
        plan.map((entry) => entry.entry_id),
      ),
    "SCHEDULE_ORDER_MISMATCH",
  );
  return {
    terminalEvents: events.slice(7, 12),
    closeEvent: events[12],
  };
}

function matrixCellTemplate(rows, columns) {
  return Object.fromEntries(
    rows.map((row) => [row, Object.fromEntries(columns.map((column) => [column, 0]))]),
  );
}

function validateExactEffects(value, entryId) {
  assert(isObject(value), "EXTERNAL_EFFECT_FORBIDDEN");
  assert(value.entry_id === entryId, "EXTERNAL_EFFECT_FORBIDDEN");
  const effects = isObject(value.external_effects)
    ? value.external_effects
    : Object.fromEntries(Object.keys(FALSE_EFFECTS).map((key) => [key, value[key]]));
  exactKeys(effects, Object.keys(FALSE_EFFECTS), "EXTERNAL_EFFECT_FORBIDDEN");
  assert(sameJson(effects, FALSE_EFFECTS), "EXTERNAL_EFFECT_FORBIDDEN");
}

function validateExactRollback(value, entryId) {
  assert(isObject(value), "ROLLBACK_NOT_EXACT");
  const rollback = value.rollback ?? value;
  assert(
    rollback.entry_id === entryId &&
    rollback.exact === true &&
      rollback.source_root_initial_state === "ABSENT" &&
      rollback.source_root_final_state === "ABSENT" &&
      Array.isArray(rollback.path_set_before) &&
      rollback.path_set_before.length === 0 &&
      Array.isArray(rollback.path_set_after) &&
      rollback.path_set_after.length === 0 &&
      rollback.clean_state_before === true &&
      rollback.clean_state_after === true,
    "ROLLBACK_NOT_EXACT",
  );
}

function validatePrimaryReceipt(value, entryId) {
  exactKeys(
    value,
    [
      "schema_version",
      "entry_id",
      "exit_code",
      "verdict",
      "reason",
      "stdout",
      "stderr",
    ],
    "PRIMARY_EVALUATOR_RECEIPT_INVALID",
  );
  assert(
    value.entry_id === entryId &&
      PRIMARY_RESULTS.includes(value.verdict) &&
      (value.exit_code === null || Number.isSafeInteger(value.exit_code)) &&
      (value.reason === null || typeof value.reason === "string"),
    "PRIMARY_EVALUATOR_RECEIPT_INVALID",
  );
  validateIdentity(value.stdout, "PRIMARY_EVALUATOR_RECEIPT_INVALID");
  validateIdentity(value.stderr, "PRIMARY_EVALUATOR_RECEIPT_INVALID");
  return value;
}

function identityWithoutPath(record) {
  return { sha256: record.sha256, byte_length: record.byte_length };
}

function validateEvidenceBinding(observation, submissionIdentity) {
  assert(isObject(observation), "TERMINAL_ARTIFACT_INVALID");
  assert(
    sameJson(observation.candidate_evidence, submissionIdentity),
    "TERMINAL_ARTIFACT_INVALID",
  );
}

function validateExpectedResultIdentity(evidence, expected) {
  assert(Array.isArray(expected.files) && expected.files.length > 0, "TERMINAL_ARTIFACT_INVALID");
  assert(isObject(evidence.result) && Array.isArray(evidence.result.files), "TERMINAL_ARTIFACT_INVALID");
  if (evidence.result.files.length !== expected.files.length) return false;
  for (const expectedFile of expected.files) {
    const matches = evidence.result.files.filter((file) => file?.path === expectedFile.path);
    if (matches.length !== 1) return false;
    const actualFile = matches[0];
    if (typeof actualFile.content !== "string") return false;
    const bytes = Buffer.from(actualFile.content, "utf8");
    if (
      bytes.length !== expectedFile.byte_length ||
      sha256(bytes) !== expectedFile.sha256
    ) {
      return false;
    }
  }
  return true;
}

function evidencePaths(evidence) {
  assert(isObject(evidence.result), "TERMINAL_ARTIFACT_INVALID");
  const files = evidence.result.files;
  const pathSet = evidence.result.path_set;
  assert(Array.isArray(files) && Array.isArray(pathSet), "TERMINAL_ARTIFACT_INVALID");
  const filePaths = files.map((file) => file?.path);
  assert(
    filePaths.every((path) => typeof path === "string") &&
      pathSet.every((path) => typeof path === "string"),
    "TERMINAL_ARTIFACT_INVALID",
  );
  return [...new Set([...filePaths, ...pathSet])];
}

function classifyRetainedSubmission(entry, submissionFile, expected, runtimeProfile) {
  const submission = looseJson(submissionFile, "TERMINAL_ARTIFACT_INVALID");
  if (!entry.eligible) {
    assert(
      submission.control_type === "PREDECLARED_SHARED_HARNESS_INVALID_CONTROL" &&
        submission.trigger_boundary ===
          "BEFORE_CHILD_START_AND_BEFORE_ANY_CANDIDATE_OUTPUT" &&
        submission.reason_family === "DECLARED_SHARED_HARNESS_INVALID" &&
        submission.system_under_test_attributable === false &&
        submission.child_start_attempts === 0 &&
        submission.candidate_output_observed === false &&
        sameJson(
          submission.control_probe_argv,
          runtimeProfile.alternate_architecture_probe,
        ) &&
        submission.control_probe_argv_sha256 ===
          sha256(Buffer.from(JSON.stringify(canonicalize(submission.control_probe_argv)), "utf8")) &&
        submission.control_probe_child_start_attempts === 1 &&
        submission.control_probe_exit_code === 0 &&
        submission.control_probe_start_error === null &&
        submission.control_probe_timed_out === false &&
        submission.expected_architecture === runtimeProfile.actual_process.arch &&
        typeof submission.observed_architecture === "string" &&
        submission.observed_architecture !== submission.expected_architecture &&
        submission.probe_outcome === "ALTERNATE_ARCHITECTURE_MISMATCH_CONFIRMED",
      "TERMINAL_ARTIFACT_INVALID",
    );
    return {
      verdict: "INFRASTRUCTURE_INVALID",
      reason_family: "DECLARED_SHARED_HARNESS_INVALID",
      submission,
    };
  }

  if (
    submission.verdict === "INFRASTRUCTURE_INVALID" ||
    submission.reason_family === "DECLARED_SHARED_HARNESS_INVALID" ||
    submission.control_type === "PREDECLARED_SHARED_HARNESS_INVALID_CONTROL"
  ) {
    fail("POST_HOC_INVALID_FORBIDDEN");
  }
  assert(
    submission.schema_version === "blind-admission-evidence/v1" &&
      submission.task_id === expected.task_id &&
      isObject(submission.tests) &&
      isObject(submission.external_effects) &&
      sameJson(submission.external_effects, FALSE_EFFECTS),
    "TERMINAL_ARTIFACT_INVALID",
  );

  if (!Object.hasOwn(submission.tests, "candidate_conformance")) {
    return {
      verdict: "FAILURE",
      reason_family: "MISSING_EVIDENCE",
      submission,
    };
  }

  const allowedPaths =
    entry.entry_id === "SCOPE_VIOLATION"
      ? entry.stimulus.allowed_result_paths
      : expected.files.map((file) => file.path);
  assert(Array.isArray(allowedPaths), "TERMINAL_ARTIFACT_INVALID");
  if (evidencePaths(submission).some((path) => !allowedPaths.includes(path))) {
    return {
      verdict: "FAILURE",
      reason_family: "SCOPE_VIOLATION",
      submission,
    };
  }

  if (!validateExpectedResultIdentity(submission, expected)) {
    return {
      verdict: "FAILURE",
      reason_family: "WRONG_PATCH",
      submission,
    };
  }

  assert(
    submission.tests.candidate_conformance === true &&
      submission.candidate_status === "COMPLETED" &&
      submission.patch?.kind === expected.patch.kind &&
      submission.patch?.replacements === expected.patch.replacements &&
      submission.patch?.material_change === true,
    "TERMINAL_ARTIFACT_INVALID",
  );
  return {
    verdict: "VERIFIED_SUCCESS",
    reason_family: "VERIFIED_SUCCESS",
    submission,
  };
}

function expectedPlanOutcomes(plan) {
  return new Map(
    plan.map((entry) => [
      entry.entry_id,
      {
        verdict: entry.independent_terminal_expectation.verdict,
        reason_family: entry.independent_terminal_expectation.reason_family,
      },
    ]),
  );
}

function terminalBoundIdentity(event, prefix, reason) {
  const shaKey = `${prefix}_sha256`;
  const lengthKey = `${prefix}_byte_length`;
  assert(
    typeof event[shaKey] === "string" &&
      Number.isSafeInteger(event[lengthKey]),
    reason,
  );
  return validateIdentity(
    { sha256: event[shaKey], byte_length: event[lengthKey] },
    reason,
  );
}

function readManifestArtifact(root, record, expectedPrefix, reason) {
  const normalized = pathIdentity(record, reason);
  assert(normalized.path.startsWith(`${expectedPrefix}/`), reason);
  return {
    record: normalized,
    ...readContained(root, {
      relative_path: normalized.path,
      sha256: normalized.sha256,
      byte_length: normalized.byte_length,
    }, reason),
  };
}

function artifactAt(bundle, path, reason = "TERMINAL_ARTIFACT_INVALID") {
  const matches = bundle.filter((artifact) => artifact.record.path === path);
  assert(matches.length === 1, reason);
  return matches[0];
}

function artifactByPath(bundle, identity, reason = "TERMINAL_ARTIFACT_INVALID") {
  const matches = bundle.filter(
    (artifact) =>
      artifact.record.path === identity.path &&
      artifact.record.sha256 === identity.sha256 &&
      artifact.record.byte_length === identity.byte_length,
  );
  assert(matches.length === 1, reason);
  return matches[0];
}

function readEntryBundle(matrixRoot, entry, terminalEvent) {
  const prefix = `artifacts/entries/${String(entry.slot).padStart(2, "0")}-${entry.entry_id}`;
  assert(
    terminalEvent.task_id === TASK_ID &&
      terminalEvent.slot === entry.slot &&
      terminalEvent.run_id === entry.run_id,
    "HISTORY_INTEGRITY_MISMATCH",
  );
  const manifestPath = containedLeaf(
    matrixRoot,
    `${prefix}/artifact-manifest.json`,
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  const manifestIdentity = terminalBoundIdentity(
    terminalEvent,
    "raw_artifact_manifest",
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  const manifestFile = safeReadRegular(
    manifestPath,
    manifestIdentity,
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  const manifest = parseJsonBytes(
    manifestFile.bytes,
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
    true,
  );
  exactKeys(
    manifest,
    ["schema_version", "task_id", "slot", "entry_id", "files"],
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  assert(
    manifest.task_id === TASK_ID &&
      manifest.slot === entry.slot &&
      manifest.entry_id === entry.entry_id &&
      Array.isArray(manifest.files),
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  const artifacts = manifest.files.map((record) =>
    readManifestArtifact(
      matrixRoot,
      record,
      prefix,
      "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
    ),
  );
  assert(
    new Set(artifacts.map((artifact) => artifact.record.path)).size === artifacts.length,
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );

  const entryRecordArtifact = artifactAt(
    artifacts,
    `${prefix}/entry-record.json`,
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  const record = parseJsonBytes(
    entryRecordArtifact.bytes,
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
    true,
  );
  exactKeys(
    record,
    [
      "schema_version",
      "slot",
      "entry_id",
      "run_id",
      "eligible",
      "candidate_claim",
      "frozen_stimulus_sha256",
      "submission",
      "submission_observation",
      "raw_evidence",
      "raw_observation",
      "raw_stdout",
      "raw_stderr",
      "exit_status",
      "primary_evaluator",
      "rollback",
      "external_effects",
      "task_card",
      "task_id",
    ],
    "TERMINAL_ARTIFACT_INVALID",
  );
  if (entry.eligible && record.eligible === false) fail("POST_HOC_INVALID_FORBIDDEN");
  assert(
    record.slot === entry.slot &&
      record.entry_id === entry.entry_id &&
      record.run_id === entry.run_id &&
      record.eligible === entry.eligible &&
      record.candidate_claim === entry.candidate_claim &&
      record.task_id === TASK_ID &&
      record.frozen_stimulus_sha256 === sha256(canonicalJsonBytes(entry.stimulus)),
    "TERMINAL_ARTIFACT_INVALID",
  );

  const identityNames = [
    "submission",
    "submission_observation",
    "raw_evidence",
    "raw_observation",
    "raw_stdout",
    "raw_stderr",
    "exit_status",
    "primary_evaluator",
    "rollback",
    "external_effects",
    "task_card",
  ];
  const bound = Object.create(null);
  for (const name of identityNames) {
    if (record[name] === null) {
      bound[name] = null;
      continue;
    }
    const identity = pathIdentity(record[name], "TERMINAL_ARTIFACT_INVALID");
    bound[name] = artifactByPath(artifacts, identity);
  }

  const rollbackIdentity = terminalBoundIdentity(
    terminalEvent,
    "rollback_receipt",
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  const effectsIdentity = terminalBoundIdentity(
    terminalEvent,
    "external_effects_receipt",
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );
  assert(
    sameJson(identityWithoutPath(record.rollback), rollbackIdentity) &&
      sameJson(identityWithoutPath(record.external_effects), effectsIdentity),
    "TERMINAL_ARTIFACT_IDENTITY_MISMATCH",
  );

  return {
    prefix,
    manifest,
    manifestFile,
    artifacts,
    record,
    bound,
  };
}

function observedPrimaryResult(bundle, entry) {
  const receipt = validatePrimaryReceipt(
    looseJson(bundle.bound.primary_evaluator, "PRIMARY_EVALUATOR_RECEIPT_INVALID"),
    entry.entry_id,
  );
  const primaryStdoutMatches = bundle.artifacts.filter(
    (artifact) =>
      artifact.record.path === `${bundle.prefix}/primary-evaluator-stdout.txt` &&
      sameJson(identityWithoutPath(artifact.record), receipt.stdout),
  );
  const primaryStderrMatches = bundle.artifacts.filter(
    (artifact) =>
      artifact.record.path === `${bundle.prefix}/primary-evaluator-stderr.txt` &&
      sameJson(identityWithoutPath(artifact.record), receipt.stderr),
  );
  assert(
    primaryStdoutMatches.length === 1 && primaryStderrMatches.length === 1,
    "PRIMARY_EVALUATOR_RECEIPT_INVALID",
  );

  if (!entry.eligible) {
    assert(
      receipt.verdict === "NOT_RUN" &&
        receipt.exit_code === null &&
        typeof receipt.reason === "string" &&
        receipt.reason.length > 0 &&
        primaryStdoutMatches[0].bytes.length === 0 &&
        primaryStderrMatches[0].bytes.length === 0,
      "PRIMARY_EVALUATOR_RECEIPT_INVALID",
    );
    return receipt.verdict;
  }

  if (receipt.verdict === "PASS") {
    const stdout = oneJsonLine(
      primaryStdoutMatches[0].bytes,
      "PRIMARY_EVALUATOR_RECEIPT_INVALID",
    );
    assert(
      stdout.verdict === "PASS" && receipt.reason === null,
      "PRIMARY_EVALUATOR_RECEIPT_INVALID",
    );
    assert(receipt.exit_code === 0, "PRIMARY_EVALUATOR_RECEIPT_INVALID");
  } else if (receipt.verdict === "NON_PASS") {
    const stderr = oneJsonLine(
      primaryStderrMatches[0].bytes,
      "PRIMARY_EVALUATOR_RECEIPT_INVALID",
    );
    assert(
      stderr.verdict === "NON_PASS" &&
        typeof stderr.reason === "string" &&
        stderr.reason === receipt.reason,
      "PRIMARY_EVALUATOR_RECEIPT_INVALID",
    );
    assert(receipt.exit_code !== 0, "PRIMARY_EVALUATOR_RECEIPT_INVALID");
  } else {
    assert(receipt.verdict === "ERROR", "PRIMARY_EVALUATOR_RECEIPT_INVALID");
  }
  return receipt.verdict;
}

function classifyEntry(matrixRoot, entry, terminalEvent, expected, runtimeProfile) {
  const bundle = readEntryBundle(matrixRoot, entry, terminalEvent);
  validateExactRollback(
    looseJson(bundle.bound.rollback, "ROLLBACK_NOT_EXACT"),
    entry.entry_id,
  );
  validateExactEffects(
    looseJson(bundle.bound.external_effects, "EXTERNAL_EFFECT_FORBIDDEN"),
    entry.entry_id,
  );

  const independent = classifyRetainedSubmission(
    entry,
    bundle.bound.submission,
    expected,
    runtimeProfile,
  );
  if (entry.eligible) {
    assert(
      bundle.bound.raw_evidence !== null &&
        bundle.bound.raw_observation !== null &&
        bundle.bound.submission_observation !== null &&
        bundle.bound.task_card !== null,
      "TERMINAL_ARTIFACT_INVALID",
    );
    const observation = looseJson(
      bundle.bound.submission_observation,
      "TERMINAL_ARTIFACT_INVALID",
    );
    validateEvidenceBinding(observation, identityWithoutPath(bundle.record.submission));
    const candidateStdout = oneJsonLine(
      bundle.bound.raw_stdout.bytes,
      "TERMINAL_ARTIFACT_INVALID",
    );
    assert(
      candidateStdout.candidate_status === independent.submission.candidate_status,
      "TERMINAL_ARTIFACT_INVALID",
    );
    const exitStatus = looseJson(bundle.bound.exit_status, "TERMINAL_ARTIFACT_INVALID");
    assert(
      exitStatus.entry_id === entry.entry_id &&
        exitStatus.child_started === true &&
        exitStatus.exit_code === 0 &&
        exitStatus.timed_out === false,
      "TERMINAL_ARTIFACT_INVALID",
    );
  } else {
    assert(
      bundle.bound.raw_evidence === null &&
        bundle.bound.raw_observation === null &&
        bundle.bound.submission_observation === null &&
        bundle.bound.task_card === null,
      "TERMINAL_ARTIFACT_INVALID",
    );
    const exitStatus = looseJson(bundle.bound.exit_status, "TERMINAL_ARTIFACT_INVALID");
    assert(
      exitStatus.entry_id === entry.entry_id &&
        exitStatus.child_started === false &&
        exitStatus.control_probe_child_started === true &&
        exitStatus.exit_code === independent.submission.control_probe_exit_code &&
        exitStatus.signal === null &&
        exitStatus.start_error === independent.submission.control_probe_start_error &&
        exitStatus.timed_out === independent.submission.control_probe_timed_out &&
        bundle.bound.raw_stdout.bytes.length ===
          independent.submission.control_probe_stdout_byte_length &&
        sha256(bundle.bound.raw_stdout.bytes) ===
          independent.submission.control_probe_stdout_sha256 &&
        bundle.bound.raw_stderr.bytes.length ===
          independent.submission.control_probe_stderr_byte_length &&
        sha256(bundle.bound.raw_stderr.bytes) ===
          independent.submission.control_probe_stderr_sha256 &&
        parseUtf8(bundle.bound.raw_stdout.bytes, "TERMINAL_ARTIFACT_INVALID") ===
          `${independent.submission.observed_architecture}\n`,
      "TERMINAL_ARTIFACT_INVALID",
    );
  }

  return {
    slot: entry.slot,
    entry_id: entry.entry_id,
    eligible: entry.eligible,
    candidate_claim: entry.candidate_claim,
    verdict: independent.verdict,
    reason_family: independent.reason_family,
    primary_result: observedPrimaryResult(bundle, entry),
    manifest_identity: bundle.manifestFile.identity,
    artifact_records: bundle.artifacts.map((artifact) => artifact.record),
  };
}

function finalizeAccounting(plan, classifications) {
  const eligibleDenominator = plan.filter((entry) => entry.eligible).length;
  const verifiedSuccessNumerator = classifications.filter(
    (entry) => entry.verdict === "VERIFIED_SUCCESS" && entry.eligible,
  ).length;
  const failureCount = classifications.filter(
    (entry) => entry.verdict === "FAILURE" && entry.eligible,
  ).length;
  const invalidCount = classifications.filter(
    (entry) => entry.verdict === "INFRASTRUCTURE_INVALID" && !entry.eligible,
  ).length;
  const reasonCodeDistribution = Object.fromEntries(
    [
      "VERIFIED_SUCCESS",
      "WRONG_PATCH",
      "MISSING_EVIDENCE",
      "SCOPE_VIOLATION",
      "DECLARED_SHARED_HARNESS_INVALID",
    ].map((reason) => [reason, classifications.filter((entry) => entry.reason_family === reason).length]),
  );

  const primaryEvaluatorDisagreementMatrix = matrixCellTemplate(
    PRIMARY_RESULTS,
    INDEPENDENT_VERDICTS,
  );
  for (const entry of classifications) {
    assert(PRIMARY_RESULTS.includes(entry.primary_result), "TERMINAL_ARTIFACT_INVALID");
    assert(INDEPENDENT_VERDICTS.includes(entry.verdict), "TERMINAL_ARTIFACT_INVALID");
    primaryEvaluatorDisagreementMatrix[entry.primary_result][entry.verdict] += 1;
  }

  const candidateClaimFalseSuccessConfusionMatrix = {
    true_positive: 0,
    false_positive: 0,
    true_negative: 0,
    false_negative: 0,
    infrastructure_invalid_excluded_from_binary_confusion: 0,
  };
  for (const entry of classifications) {
    if (entry.verdict === "INFRASTRUCTURE_INVALID") {
      candidateClaimFalseSuccessConfusionMatrix.infrastructure_invalid_excluded_from_binary_confusion += 1;
      continue;
    }
    const claimed = entry.candidate_claim === "CLAIMED_SUCCESS";
    const success = entry.verdict === "VERIFIED_SUCCESS";
    if (claimed && success) candidateClaimFalseSuccessConfusionMatrix.true_positive += 1;
    else if (claimed && !success) candidateClaimFalseSuccessConfusionMatrix.false_positive += 1;
    else if (!claimed && !success) candidateClaimFalseSuccessConfusionMatrix.true_negative += 1;
    else candidateClaimFalseSuccessConfusionMatrix.false_negative += 1;
  }

  return {
    scheduled_count: plan.length,
    eligible_denominator: eligibleDenominator,
    verified_success_numerator: verifiedSuccessNumerator,
    failure_count: failureCount,
    invalid_count: invalidCount,
    exact_vtsr_fraction: {
      numerator: verifiedSuccessNumerator,
      denominator: eligibleDenominator,
      canonical_fraction: `${verifiedSuccessNumerator}/${eligibleDenominator}`,
    },
    reason_code_distribution: reasonCodeDistribution,
    primary_evaluator_disagreement_matrix: primaryEvaluatorDisagreementMatrix,
    candidate_claim_false_success_confusion_matrix:
      candidateClaimFalseSuccessConfusionMatrix,
  };
}

function readRawArtifactManifest(matrixRoot, closeEvent, classifications) {
  const expectedIdentity = terminalBoundIdentity(
    closeEvent,
    "raw_artifact_manifest",
    "RAW_ARTIFACT_MANIFEST_INVALID",
  );
  const path = containedLeaf(
    matrixRoot,
    "raw-artifact-manifest.json",
    "RAW_ARTIFACT_MANIFEST_INVALID",
  );
  const file = safeReadRegular(path, expectedIdentity, "RAW_ARTIFACT_MANIFEST_INVALID");
  const value = parseJsonBytes(file.bytes, "RAW_ARTIFACT_MANIFEST_INVALID", true);
  exactKeys(
    value,
    [
      "schema_version",
      "task_id",
      "retained_entry_count",
      "entry_artifact_manifests",
    ],
    "RAW_ARTIFACT_MANIFEST_INVALID",
  );
  assert(
    value.task_id === TASK_ID &&
      value.retained_entry_count === classifications.length &&
      Array.isArray(value.entry_artifact_manifests) &&
      value.entry_artifact_manifests.length === classifications.length,
    "RAW_ARTIFACT_MANIFEST_INVALID",
  );
  const manifests = value.entry_artifact_manifests.map((record) =>
    pathIdentity(record, "RAW_ARTIFACT_MANIFEST_INVALID"),
  );
  assert(
    new Set(manifests.map((record) => record.path)).size === manifests.length,
    "RAW_ARTIFACT_MANIFEST_INVALID",
  );
  for (const record of manifests) {
    readContained(matrixRoot, {
      relative_path: record.path,
      sha256: record.sha256,
      byte_length: record.byte_length,
    }, "RAW_ARTIFACT_MANIFEST_INVALID");
  }

  for (const classification of classifications) {
    const expectedPath = `artifacts/entries/${String(classification.slot).padStart(2, "0")}-${classification.entry_id}/artifact-manifest.json`;
    const manifestMatches = manifests.filter(
      (record) =>
        record.path === expectedPath &&
        record.sha256 === classification.manifest_identity.sha256 &&
        record.byte_length === classification.manifest_identity.byte_length,
    );
    assert(manifestMatches.length === 1, "RAW_ARTIFACT_MANIFEST_INVALID");
  }
  return { file, value };
}

function expectedEntryReports(classifications) {
  return classifications.map((entry) => ({
    entry_id: entry.entry_id,
    independent_verdict: entry.verdict,
    primary_evaluator_verdict: entry.primary_result,
    reason_family: entry.reason_family,
  }));
}

function validateReportedEntryReports(reports, classifications) {
  assert(Array.isArray(reports) && reports.length === classifications.length, "REPORTED_AGGREGATE_MISMATCH");
  const expected = expectedEntryReports(classifications);
  for (let index = 0; index < reports.length; index += 1) {
    const report = reports[index];
    const target = expected[index];
    assert(isObject(report), "REPORTED_AGGREGATE_MISMATCH");
    if (
      classifications[index].eligible &&
      report.independent_verdict === "INFRASTRUCTURE_INVALID"
    ) {
      fail("POST_HOC_INVALID_FORBIDDEN");
    }
    for (const [key, value] of Object.entries(target)) {
      assert(sameJson(report[key], value), "REPORTED_AGGREGATE_MISMATCH");
    }
  }
  return expected;
}

function validateReportedAggregate(file, derived, classifications) {
  const reported = parseJsonBytes(file.bytes, "REPORTED_AGGREGATE_MISMATCH", true);
  exactKeys(
    reported,
    [
      "schema_version",
      "task_id",
      "scheduled_count",
      "eligible_denominator",
      "verified_success_numerator",
      "failure_count",
      "invalid_count",
      "exact_vtsr",
      "reason_code_distribution",
      "classifications",
      "primary_evaluator_disagreement_matrix",
      "candidate_claim_false_success_confusion_matrix",
      "external_effects",
    ],
    "REPORTED_AGGREGATE_MISMATCH",
  );
  assert(reported.task_id === TASK_ID, "REPORTED_AGGREGATE_MISMATCH");
  assert(sameJson(reported.external_effects, FALSE_EFFECTS), "EXTERNAL_EFFECT_FORBIDDEN");
  if (!sameJson(reported.reason_code_distribution, derived.reason_code_distribution)) {
    fail("REASON_DISTRIBUTION_MISMATCH");
  }
  const exactVtsr = derived.exact_vtsr_fraction;
  assert(
    reported.scheduled_count === derived.scheduled_count &&
      reported.eligible_denominator === derived.eligible_denominator &&
      reported.verified_success_numerator === derived.verified_success_numerator &&
      reported.failure_count === derived.failure_count &&
      reported.invalid_count === derived.invalid_count &&
      sameJson(reported.exact_vtsr, exactVtsr) &&
      sameJson(
        reported.primary_evaluator_disagreement_matrix,
        derived.primary_evaluator_disagreement_matrix,
      ) &&
      sameJson(
        reported.candidate_claim_false_success_confusion_matrix,
        derived.candidate_claim_false_success_confusion_matrix,
      ),
    "REPORTED_AGGREGATE_MISMATCH",
  );
  const entryReports = validateReportedEntryReports(
    reported.classifications,
    classifications,
  );
  return { reported, entryReports };
}

function validateFrozenExpectedOutcome(plan, derived, classifications) {
  const expectation = plan.frozen_accounting_expectation;
  assert(
    derived.scheduled_count === expectation.scheduled_count &&
      derived.eligible_denominator === expectation.eligible_denominator &&
      derived.verified_success_numerator === expectation.verified_success_numerator &&
      derived.failure_count === expectation.failure_count &&
      derived.invalid_count === expectation.invalid_count &&
      sameJson(derived.exact_vtsr_fraction, expectation.exact_vtsr) &&
      sameJson(derived.reason_code_distribution, expectation.reason_code_distribution) &&
      sameJson(
        derived.candidate_claim_false_success_confusion_matrix,
        expectation.candidate_claim_false_success_expectation,
      ),
    "INDEPENDENT_RECOMPUTATION_MISMATCH",
  );
  const expectedOutcomes = expectedPlanOutcomes(plan.schedule);
  for (const classification of classifications) {
    const expected = expectedOutcomes.get(classification.entry_id);
    if (classification.eligible && classification.verdict === "INFRASTRUCTURE_INVALID") {
      fail("POST_HOC_INVALID_FORBIDDEN");
    }
    assert(
      sameJson(
        { verdict: classification.verdict, reason_family: classification.reason_family },
        expected,
      ),
      "INDEPENDENT_RECOMPUTATION_MISMATCH",
    );
  }
}

function validateCloseReceipt(matrixRoot, ledgerFile, aggregateFile, rawManifestFile) {
  const path = containedLeaf(
    matrixRoot,
    "matrix-close-receipt.json",
    "MATRIX_CLOSE_RECEIPT_INVALID",
  );
  const file = safeReadRegular(path, undefined, "MATRIX_CLOSE_RECEIPT_INVALID");
  const value = parseJsonBytes(file.bytes, "MATRIX_CLOSE_RECEIPT_INVALID", true);
  assert(
    value.task_id === TASK_ID &&
      sameJson(value.closed_ledger ?? value.ledger, {
        path: "ledger.jsonl",
        ...ledgerFile.identity,
      }) &&
      sameJson(value.reported_aggregate, {
        path: "reported-aggregate.json",
        ...aggregateFile.identity,
      }) &&
      sameJson(value.raw_artifact_manifest, {
        path: "raw-artifact-manifest.json",
        ...rawManifestFile.identity,
      }),
    "MATRIX_CLOSE_RECEIPT_INVALID",
  );
  return file;
}

// This stage consumes retained bytes only. It never imports the matrix runner,
// calls worker accounting code, executes candidate output, or writes Evidence.
function recomputeArtifacts({ cli, frozen, plan, acceptedInputs, ledger, ledgerFile }) {
  const expectedRecord = frozen.plan.accepted_input_identities.expected;
  const expectedPath = containedLeaf(
    REPOSITORY_ROOT,
    expectedRecord.path,
    "ACCEPTED_INPUT_IDENTITY_MISMATCH",
  );
  const expectedFile = safeReadRegular(
    expectedPath,
    { sha256: expectedRecord.sha256, byte_length: expectedRecord.byte_length },
    "ACCEPTED_INPUT_IDENTITY_MISMATCH",
  );
  const expected = parseJsonBytes(
    expectedFile.bytes,
    "ACCEPTED_INPUT_IDENTITY_MISMATCH",
    false,
  );
  const runtimeRecord = frozen.plan.accepted_input_identities.runtime_profile;
  const runtimePath = containedLeaf(
    REPOSITORY_ROOT,
    runtimeRecord.path,
    "ACCEPTED_INPUT_IDENTITY_MISMATCH",
  );
  const runtimeFile = safeReadRegular(
    runtimePath,
    { sha256: runtimeRecord.sha256, byte_length: runtimeRecord.byte_length },
    "ACCEPTED_INPUT_IDENTITY_MISMATCH",
  );
  const runtimeProfile = parseJsonBytes(
    runtimeFile.bytes,
    "ACCEPTED_INPUT_IDENTITY_MISMATCH",
    false,
  );

  const classifications = plan.map((entry, index) =>
    classifyEntry(
      cli.artifact_root,
      entry,
      ledger.terminalEvents[index],
      expected,
      runtimeProfile,
    ),
  );
  const derived = finalizeAccounting(plan, classifications);
  validateFrozenExpectedOutcome(frozen.plan, derived, classifications);

  const aggregateIdentity = terminalBoundIdentity(
    ledger.closeEvent,
    "reported_aggregate",
    "REPORTED_AGGREGATE_MISMATCH",
  );
  const aggregateFile = safeReadRegular(
    cli.reported_aggregate,
    aggregateIdentity,
    "REPORTED_AGGREGATE_MISMATCH",
  );
  // The worker report is intentionally first opened and compared only after
  // every independent classification and count above has been derived.
  const reported = validateReportedAggregate(aggregateFile, derived, classifications);
  const rawManifest = readRawArtifactManifest(
    cli.artifact_root,
    ledger.closeEvent,
    classifications,
  );
  assert(
    ledger.closeEvent.last_terminal_event_sha256 ===
      ledger.terminalEvents.at(-1).event_sha256,
    "HISTORY_INTEGRITY_MISMATCH",
  );
  const closeReceiptFile = validateCloseReceipt(
    cli.artifact_root,
    ledgerFile,
    aggregateFile,
    rawManifest.file,
  );

  return {
    schema_version: "offline-scheduled-matrix-independent-recomputation/v1",
    record_type: "READ_ONLY_INDEPENDENT_RECOMPUTATION_RECEIPT",
    status: "PASS",
    reason: "PASS",
    task_id: TASK_ID,
    frozen_identities: {
      contract: frozen.contractIdentity,
      matrix_plan: frozen.planIdentity,
      negative_catalog: frozen.negativeCatalogIdentity,
      prefreeze_receipt: frozen.receiptFile.identity,
    },
    observed_input_identities: acceptedInputs,
    retained_identities: {
      ledger: ledgerFile.identity,
      reported_aggregate: aggregateFile.identity,
      raw_artifact_manifest: rawManifest.file.identity,
      matrix_close_receipt: closeReceiptFile.identity,
    },
    accounting: derived,
    entry_reports: reported.entryReports,
    external_effects: FALSE_EFFECTS,
    claim_boundary:
      "ONE_FROZEN_FIVE_ENTRY_COOPERATIVE_LOCAL_OFFLINE_MATRIX_READ_ONLY_RECOMPUTATION_ONLY",
  };
}

export function recompute(cliArgv) {
  const cli = parseCli(cliArgv);
  const frozen = validateFrozenAuthorities(cli);
  const plan = validatePlan(frozen.plan, frozen.contract);
  const acceptedInputs = validateAcceptedInputIdentities(frozen.plan);
  assertDirectoryChainNoSymlink(cli.artifact_root, "EVIDENCE_PATH_INVALID");
  assert(
    cli.ledger === containedLeaf(cli.artifact_root, "ledger.jsonl", "EVIDENCE_PATH_INVALID") &&
      cli.reported_aggregate ===
        containedLeaf(cli.artifact_root, "reported-aggregate.json", "EVIDENCE_PATH_INVALID"),
    "EVIDENCE_PATH_INVALID",
  );
  const ledgerFile = safeReadRegular(cli.ledger, undefined, "HISTORY_INTEGRITY_MISMATCH");
  const ledger = validateLedger(
    parseCanonicalLedger(ledgerFile.bytes),
    plan,
    frozen,
  );
  return recomputeArtifacts({
    cli,
    frozen,
    plan,
    acceptedInputs,
    ledger,
    ledgerFile,
  });
}

function emit(value) {
  process.stdout.write(canonicalJsonBytes(value));
}

function main() {
  try {
    const receipt = recompute(process.argv.slice(2));
    emit(receipt);
  } catch (error) {
    const reason =
      error instanceof RecomputationNonPass ? error.reason : "INTERNAL_RECOMPUTATION_ERROR";
    emit({
      schema_version: "offline-scheduled-matrix-independent-recomputation-error/v1",
      status: "NON_PASS",
      reason,
    });
    process.exitCode = 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

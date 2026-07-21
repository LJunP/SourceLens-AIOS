import {
  COMPILER_VERSION,
  compileFiniteTypedPatchIr,
} from "../../harness/finite-typed-patch-ir-v1/compiler.mjs";

export const ADAPTER_ID = "B0";
export const ADAPTER_VERSION = "P1-063-OFFLINE-FINITE-IR-B0/1";

const SUBMISSION_KEYS = Object.freeze([
  "schema_version",
  "record_type",
  "result_id",
  "adapter_id",
  "execution_mode",
  "task_id",
  "dataset_version",
  "base_commit",
  "base_tree",
  "target_id",
  "proposal",
]);
const PROPOSAL_KEYS = Object.freeze(["program_id", "path", "byte_length", "sha256"]);

export class OfflineAdapterError extends Error {
  constructor(reasonCode, message) {
    super(message);
    this.name = "OfflineAdapterError";
    this.reasonCode = reasonCode;
  }
}

const reject = (reasonCode, message) => {
  throw new OfflineAdapterError(reasonCode, message);
};

const assert = (condition, reasonCode, message) => {
  if (!condition) reject(reasonCode, message);
};

function exactKeys(value, expected, reasonCode) {
  assert(value && typeof value === "object" && !Array.isArray(value), reasonCode, "object required");
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  assert(JSON.stringify(actual) === JSON.stringify(wanted), reasonCode, "closed member set drift");
}

function safeRelativePath(value) {
  return typeof value === "string"
    && value.length > 0
    && !value.startsWith("/")
    && !value.split("/").some((part) => part.length === 0 || part === "." || part === "..");
}

export function validateOfflineSubmission(submission, frozenSubmission) {
  exactKeys(submission, SUBMISSION_KEYS, "SUBMISSION_UNKNOWN_MEMBER_REJECTED");
  exactKeys(submission.proposal, PROPOSAL_KEYS, "PROPOSAL_UNKNOWN_MEMBER_REJECTED");
  exactKeys(frozenSubmission, SUBMISSION_KEYS, "SUBMISSION_TYPE_REJECTED");
  exactKeys(frozenSubmission.proposal, PROPOSAL_KEYS, "SUBMISSION_TYPE_REJECTED");

  assert(
    submission.schema_version === 1
      && submission.record_type === "sourcelens_aios_p1_063_offline_b0_finite_ir_result"
      && submission.result_id === frozenSubmission.result_id
      && submission.adapter_id === ADAPTER_ID
      && submission.execution_mode === "OFFLINE_FROZEN_SUBMISSION",
    "SUBMISSION_TYPE_REJECTED",
    "offline submission identity drift",
  );
  assert(
    submission.task_id === frozenSubmission.task_id
      && submission.dataset_version === frozenSubmission.dataset_version,
    "TASK_BINDING_REJECTED",
    "task binding drift",
  );
  assert(
    submission.base_commit === frozenSubmission.base_commit,
    "BASE_COMMIT_MISMATCH_REJECTED",
    "base commit drift",
  );
  assert(
    submission.base_tree === frozenSubmission.base_tree,
    "BASE_TREE_MISMATCH_REJECTED",
    "base tree drift",
  );
  assert(
    submission.target_id === frozenSubmission.target_id,
    "TARGET_BINDING_REJECTED",
    "target binding drift",
  );
  assert(
    submission.proposal.program_id === frozenSubmission.proposal.program_id,
    "PROGRAM_BINDING_REJECTED",
    "program binding drift",
  );
  assert(
    safeRelativePath(submission.proposal.path)
      && submission.proposal.path === frozenSubmission.proposal.path,
    "PROPOSAL_PATH_REJECTED",
    "proposal path is not the exact frozen repository path",
  );
  assert(
    submission.proposal.byte_length === frozenSubmission.proposal.byte_length,
    "PROPOSAL_LENGTH_MISMATCH_REJECTED",
    "declared proposal length drift",
  );
  assert(
    submission.proposal.sha256 === frozenSubmission.proposal.sha256,
    "PROPOSAL_HASH_MISMATCH_REJECTED",
    "declared proposal hash drift",
  );
  return true;
}

export function admitOfflineB0Result(submission, frozenSubmission, proposalBytes) {
  validateOfflineSubmission(submission, frozenSubmission);
  assert(Buffer.isBuffer(proposalBytes), "IR_NOT_EXACTLY_ADMITTED", "proposal must be raw Buffer bytes");
  assert(
    proposalBytes.length === submission.proposal.byte_length,
    "PROPOSAL_LENGTH_MISMATCH_REJECTED",
    "proposal byte length differs from its declaration",
  );

  const compiled = compileFiniteTypedPatchIr(proposalBytes);
  assert(
    compiled.status !== "REJECTED",
    compiled.reason_code ?? "IR_NOT_EXACTLY_ADMITTED",
    "proposal is not an exact admitted finite IR program",
  );
  assert(
    compiled.proposal_sha256 === submission.proposal.sha256,
    "PROPOSAL_HASH_MISMATCH_REJECTED",
    "proposal bytes differ from the declared hash",
  );
  assert(
    compiled.program_id === submission.proposal.program_id,
    "PROGRAM_BINDING_REJECTED",
    "compiler program differs from the declared program",
  );

  return Object.freeze({
    adapter_id: ADAPTER_ID,
    adapter_version: ADAPTER_VERSION,
    compiler_version: COMPILER_VERSION,
    execution_mode: submission.execution_mode,
    result_id: submission.result_id,
    admission: "ADMITTED_EXACT_LEGAL_PROGRAM",
    status: compiled.status,
    reason_code: compiled.reason_code,
    program_id: compiled.program_id,
    outcome_id: compiled.outcome_id,
    outcome_kind: compiled.kind,
    postimage: compiled.postimage === null ? null : Buffer.from(compiled.postimage),
    proposal_byte_length: compiled.proposal_length,
    proposal_sha256: compiled.proposal_sha256,
  });
}

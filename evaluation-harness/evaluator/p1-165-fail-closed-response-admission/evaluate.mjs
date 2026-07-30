#!/usr/bin/env node

import {
  closeSync,
  constants as fsConstants,
  existsSync,
  fstatSync,
  linkSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  normalize,
  relative,
  resolve,
  sep,
} from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

const TASK_ID =
  "AIOS-P1-165_FAIL_CLOSED_RESPONSE_ADMISSION_AND_RAW_EVIDENCE_KERNEL";
const MATRIX_SCHEMA = "p1-165-quality-matrix/v1";
const MATRIX_SHA256 =
  "70cde8ec13a8d1f74d309b8d5a1b06579a571a7dfe29b4b8ba9b4cf90bc5bcc6";
const MATRIX_BYTE_LENGTH = 59333;
const P1_168_TASK_ID =
  "AIOS-P1-168_EXACT_RESPONSE_ADMISSION_MATRIX_RECOVERY_AND_GATE";
const P1_168_TASK_CONTRACT_RELATIVE_PATH =
  "docs/aios/tasks/P1-168_EXACT_RESPONSE_ADMISSION_MATRIX_RECOVERY_AND_GATE.yaml";
const P1_168_TASK_CONTRACT_IDENTITY = Object.freeze({
  byte_length: 14548,
  sha256: "f959e5f58cace3e795d481454ad9863d0a9195e336bd0eda7d79baf458f10c87",
});
const P1_168_TASK_AUTHORITY = Object.freeze({
  path:
    "/Users/lijunpeng/Developer/.sourcelens-audit/"
    + "p1-exact-p1-165-snapshot-recovery-strict-exit-20260730/"
    + "task-1-p1-168/authority/TASK_AUTHORITY.yaml",
  byte_length: 2516,
  sha256: "48c57f94e26a365339f4ed6b3285086f7b2dee61ed9d923c664551ae5d625292",
});
const P1_168_RESTORE_RECEIPT = Object.freeze({
  path:
    "/Users/lijunpeng/Developer/.sourcelens-audit/"
    + "p1-exact-p1-165-snapshot-recovery-strict-exit-20260730/"
    + "task-1-p1-168/preflight/P1_168_EXACT_SNAPSHOT_RESTORE_RECEIPT.json",
  byte_length: 3400,
  sha256: "a2350df713fd3ec0719cecd3bce14539bebce6583205bea757e99969049b1984",
});
const P1_168_EXECUTION_SOURCE_PATHS = Object.freeze([
  "Makefile",
  "evaluation-harness/evaluator/p1-165-fail-closed-response-admission/evaluate.mjs",
  "evaluation-harness/evaluator/p1-165-fail-closed-response-admission/matrix.json",
  "evaluation-harness/harness/p1-165-fail-closed-response-admission/admission.mjs",
  "evaluation-harness/harness/p1-165-fail-closed-response-admission/contract.mjs",
  "evaluation-harness/harness/p1-165-fail-closed-response-admission/observer.mjs",
  "evaluation-harness/harness/p1-165-fail-closed-response-admission/preflight.mjs",
  "evaluation-harness/harness/p1-165-fail-closed-response-admission/transport.mjs",
]);
const P1_168_VERIFIER_SOURCE_PATH =
  "scripts/verify-p1-165-fail-closed-response-admission.sh";
const P1_168_SOURCE_BUNDLE_PATH =
  "raw/p1-168/current-kernel-source-bundle.json";
const P1_168_GATE_ENVELOPE_PATH =
  "raw/p1-168/task-gate-envelope.json";
const P1_168_PREFLIGHT_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-audit/"
  + "p1-exact-p1-165-snapshot-recovery-strict-exit-20260730/"
  + "task-1-p1-168/preflight";
const P1_168_COMPLETE_MATRIX_V1_ROOT = join(
  P1_168_PREFLIGHT_ROOT,
  "complete-matrix-v1",
);
const P1_168_COMPLETE_MATRIX_ROOT = join(
  P1_168_PREFLIGHT_ROOT,
  "complete-matrix-v2",
);
const P1_168_ABORTED_STAGE_PATH =
  join(
    P1_168_PREFLIGHT_ROOT,
    ".complete-matrix-v1.p1-165-stage-45fd79a51496b6aefb578548",
  );
const P1_168_V1_ARTIFACTS = Object.freeze({
  manifest: Object.freeze({
    path: join(P1_168_COMPLETE_MATRIX_V1_ROOT, "RAW_EVIDENCE_MANIFEST.json"),
    byte_length: 807791,
    sha256: "b7282c25ee11c3936b8cf007ac813b134f3ab15751147bd3871f0be350be4478",
  }),
  atomic_commit_receipt: Object.freeze({
    path: `${P1_168_COMPLETE_MATRIX_V1_ROOT}.p1-165-atomic-commit-receipt.json`,
    byte_length: 18418,
    sha256: "8291cd5e6efe86f1d38b22848ba643e6a72a03001a90d0e6288717d4578d309b",
  }),
  wrapper_stdout: Object.freeze({
    path: join(P1_168_PREFLIGHT_ROOT, "COMPLETE_MATRIX_V1_STDOUT.log"),
    byte_length: 3830,
    sha256: "3bb1847b69bc08dcbedbdb118fc9339e6d6f48769dea281056ff4f1bf24bbbce",
  }),
  wrapper_stderr: Object.freeze({
    path: join(P1_168_PREFLIGHT_ROOT, "COMPLETE_MATRIX_V1_STDERR.log"),
    byte_length: 4219,
    sha256: "486e415179cdac7b3261eb385513bef6d6f10fef35de3e91e422e0f2176278a9",
  }),
  wrapper_exit: Object.freeze({
    path: join(P1_168_PREFLIGHT_ROOT, "COMPLETE_MATRIX_V1_EXIT.json"),
    byte_length: 88,
    sha256: "9afcddfcdb36e232adf62cdc9689a4fc71e930c7b42b02614a0903d69f0110a0",
  }),
  evaluator_stdout: Object.freeze({
    path: join(
      P1_168_PREFLIGHT_ROOT,
      "P1_168_V1_INDEPENDENT_EVALUATOR_STDOUT.log",
    ),
    byte_length: 4764,
    sha256: "14352e4b33ebd72f6b852ec6e01209163c3e714e22396fd3c9fc88273952d506",
  }),
  evaluator_stderr: Object.freeze({
    path: join(
      P1_168_PREFLIGHT_ROOT,
      "P1_168_V1_INDEPENDENT_EVALUATOR_STDERR.log",
    ),
    byte_length: 0,
    sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  }),
  evaluator_exit: Object.freeze({
    path: join(
      P1_168_PREFLIGHT_ROOT,
      "P1_168_V1_INDEPENDENT_EVALUATOR_EXIT.json",
    ),
    byte_length: 1386,
    sha256: "51e07eb1c55ae2d18fae2edc8a565858998cf8e5475bdccc767d6235a72e3b3e",
  }),
});
const P1_168_V2_ARTIFACTS = Object.freeze({
  manifest: Object.freeze({
    path: join(P1_168_COMPLETE_MATRIX_ROOT, "RAW_EVIDENCE_MANIFEST.json"),
    byte_length: 807791,
    sha256: "330af09c3a3a3ac42f143061e050808191a06f7cb0c41e3992dfc1000f0a8239",
  }),
  atomic_commit_receipt: Object.freeze({
    path: `${P1_168_COMPLETE_MATRIX_ROOT}.p1-165-atomic-commit-receipt.json`,
    byte_length: 18418,
    sha256: "1c7bbf6341c28e9cdf491ea21b006b57d40daec080d3ea311a1225274ea5745d",
  }),
  wrapper_stdout: Object.freeze({
    path: join(P1_168_PREFLIGHT_ROOT, "COMPLETE_MATRIX_V2_STDOUT.log"),
    byte_length: 21125,
    sha256: "3e4df6fa93607aeed3685c779a6dd41a0a359cc180cea6dd9e526ab4aff762a5",
  }),
  wrapper_stderr: Object.freeze({
    path: join(P1_168_PREFLIGHT_ROOT, "COMPLETE_MATRIX_V2_STDERR.log"),
    byte_length: 0,
    sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  }),
  wrapper_exit: Object.freeze({
    path: join(P1_168_PREFLIGHT_ROOT, "COMPLETE_MATRIX_V2_EXIT.json"),
    byte_length: 84,
    sha256: "2810eace602c06ea4cf51746a7a407da9489ddc883a95cf6596f899cd05bd9d4",
  }),
});
const P1_168_MAKE_VERIFY_V1_ROOT = join(
  dirname(P1_168_PREFLIGHT_ROOT),
  "task-gate/worktree-make-verify-v1",
);
const P1_168_MAKE_VERIFY_V1_ARTIFACTS = Object.freeze({
  receipt: Object.freeze({
    path: join(P1_168_MAKE_VERIFY_V1_ROOT, "receipt.json"),
    byte_length: 620,
    sha256: "7735055e1758fbff34ea3d4e0c891928eaefd3a490749d49f55b4ae3d5af4a6e",
  }),
  stdout: Object.freeze({
    path: join(P1_168_MAKE_VERIFY_V1_ROOT, "stdout.log"),
    byte_length: 211,
    sha256: "273c5a28583bd7c34eca150da4f63cbbd4785bb632c61c4eaed47294bb34065c",
  }),
  stderr: Object.freeze({
    path: join(P1_168_MAKE_VERIFY_V1_ROOT, "stderr.log"),
    byte_length: 804,
    sha256: "b01b73f5f7f0a6ee2b7381d845154f0ce6ef8e3fddd9d18033fa8b36996d14f9",
  }),
});
const MATRIX_CASE_COUNT = 99;
const RESULT_SCHEMA = "p1-165-independent-evaluation/v1";
const MANIFEST_PATH = "RAW_EVIDENCE_MANIFEST.json";
const MANIFEST_SCHEMA = "p1-165-raw-evidence-manifest/v1";
const KERNEL_CONTRACT_PATH = "raw/kernel-contract.json";
const KERNEL_CONTRACT_SCHEMA = "p1-165-raw-kernel-contract/v1";
const HISTORICAL_REGRESSION_RECEIPT_PATH =
  "raw/historical-root-cause-regression-receipt.json";
const HISTORICAL_REGRESSION_RECEIPT_SCHEMA =
  "p1-168-p1-165-root-cause-regression-receipt/v1";
const CASE_INPUT_SCHEMA = "p1-165-matrix-case-input/v1";
const CASE_OBSERVATION_SCHEMA = "p1-165-matrix-case-observation/v1";
const CASE_PROCESS_RESULT_SCHEMA = "p1-165-case-process-result/v1";
const REFERENCE_SCAN_PLAN_PATH = "raw/reference-scan/plan.json";
const REFERENCE_SCAN_EVENTS_PATH = "raw/reference-scan/events.jsonl";
const REFERENCE_SCAN_RECEIPT_PATH = "raw/reference-scan/receipt.json";
const REFERENCE_SCAN_PLAN_SCHEMA = "p1-165-reference-scan-plan/v1";
const REFERENCE_SCAN_EVENT_SCHEMA = "p1-165-reference-scan-event/v1";
const REFERENCE_SCAN_RECEIPT_SCHEMA = "p1-165-reference-scan-receipt/v1";
const RESPONSE_BYTES_MAX = 4 * 1024 * 1024;
const OUTPUT_TOKENS_MAX = 2048;
const RAW_EVIDENCE_MANIFEST_BYTES_MAX = 8 * 1024 * 1024;
const RAW_EVIDENCE_SINGLE_FILE_BYTES_MAX = 64 * 1024 * 1024;
const RAW_EVIDENCE_TOTAL_BYTES_MAX = 512 * 1024 * 1024;
const RAW_EVIDENCE_FILE_COUNT_MAX = 10_000;
const RAW_EVIDENCE_DIRECTORY_COUNT_MAX = 10_000;
const RAW_EVIDENCE_DEPTH_MAX = 32;
const ACCEPTED_ADAPTER_PROOF_FILE_COUNT_MAX = 1024;
const ACCEPTED_ADAPTER_PROOF_SINGLE_FILE_BYTES_MAX = 32 * 1024 * 1024;
const ACCEPTED_ADAPTER_PROOF_TOTAL_BYTES_MAX = 256 * 1024 * 1024;
const ACCEPTED_ADAPTER_PROOF_DEPTH_MAX = 16;
const ACCEPTED_ADAPTER_EXECUTABLE_BYTES_MAX = 16 * 1024 * 1024;
const B2_SCAN_SOURCE_FILE_COUNT_MAX = 16;
const B2_SCAN_SOURCE_SINGLE_FILE_BYTES_MAX = 1024 * 1024;
const B2_SCAN_SOURCE_TOTAL_BYTES_MAX = 2 * 1024 * 1024;
const B2_SCAN_SOURCE_DEPTH_MAX = 8;
const MATRIX_PATH = join(
  dirname(fileURLToPath(import.meta.url)),
  "matrix.json",
);
const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const PREFLIGHT_PATH = resolve(
  REPOSITORY_ROOT,
  "evaluation-harness/harness/p1-165-fail-closed-response-admission/preflight.mjs",
);
const SANDBOX_EXEC_PATH = "/usr/bin/sandbox-exec";
const ACCEPTED_P0_SOURCE_MANIFEST_PATH = resolve(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-125-six-task-parameterized/b2-p0-source-manifest.json",
);
const ACCEPTED_TASK_DATASET_ROOT = resolve(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1",
);
const ACCEPTED_TASK_DATASET_MANIFEST_PATH = join(
  ACCEPTED_TASK_DATASET_ROOT,
  "dataset-manifest.json",
);
const ACCEPTED_TASK_DATASET_MANIFEST_SHA256 =
  "22f252319ed066655b05142a391709741703e01fbb4d6b5ebfbbcb6acd782be6";
const ACCEPTED_TASK_INPUT_BYTES_MAX = 64 * 1024;
const B2_REEXECUTION_CLAIM_BOUNDARY =
  "COOPERATIVE_LOCAL_TRUSTED_ACCEPTED_BINARY_EFFECT_CONFINEMENT";
const ACCEPTED_P1_129_TASK_ID =
  "AIOS-P1-129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION";
const ACCEPTED_P1_129_CANDIDATE_COMMIT =
  "a772dc5d350ec6b38a84e430b01f75628429aa7b";
const ACCEPTED_P1_129_CANDIDATE_TREE =
  "905dd694922ba9a2b452d15c93dc17cefc9e53c1";
const ACCEPTED_P1_129_TASK_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-audit/"
  + "p1-129-input-boundary-matrix-20260726/task-1";
const ACCEPTED_P1_129_FORMAL_ROOT =
  `${ACCEPTED_P1_129_TASK_ROOT}/formal-matrix-v1`;
const ACCEPTED_P1_129_WORKTREE_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-worktrees/"
  + "AIOS-P1-129-input-boundary-matrix";
const ACCEPTED_P1_129_RESIDUAL_DISCLOSURE =
  "P1-129 reviews bind the accepted formal path and exact summary, "
  + "negative-result, candidate, review and terminal identities, but do "
  + "not independently closed-hash every historical binary byte.";
const ACCEPTED_P1_129_CLAIM_BOUNDARY =
  "COOPERATIVE_LOCAL_ACCEPTED_P1_129_PATH_PLUS_CURRENT_SELECTED_INVENTORY";
const ACCEPTED_P1_129_B2_PROOF_CLAIM_BOUNDARY =
  "ACCEPTED_P1_129_SELECTED_PROOF_PLUS_CURRENT_FRESH_SANDBOX_SCAN";
const ACCEPTED_ADAPTER_AGGREGATE_MODE =
  "ACCEPTED_P1_129_PROOFS_PLUS_12_CURRENT_FRESH_B2_SANDBOX_SCANS";

const PROFILE_ORDER = Object.freeze([
  "B0_A",
  "B0_B",
  "B1_A",
  "B1_B",
  "B2_A",
  "B2_B",
]);
const ACCEPTED_TASK_IDS = Object.freeze([
  "SL-P1-REP-001-RANGE-NORMALIZATION",
  "SL-P1-REP-002-CONFIG-VALIDATION",
  "SL-P1-REP-003-SAFE-PATH-JOIN",
  "SL-P1-REP-004-COMMAND-RESULT-MAPPING",
  "SL-P1-REP-005-PROFILE-DISPLAY-NAME",
  "SL-P1-REP-006-DEDUPE-REFACTOR",
]);
const ACCEPTED_P0_BINDING = Object.freeze({
  analyzer_subtree: "408d57e9b4926f95ad059ab2675ee88dfc533096",
  checkpoint_commit: "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10",
  checkpoint_tree: "2c0956ae8598547466f691ead21532a026006bf9",
  frozen_base_commit: "09cf8dd6a1bcee138b949d117804d652000eb7cc",
  frozen_base_tree: "daa58725d293b954887dbe5b17aab5219b618658",
  operation_id: "repository_analysis.scan",
});
const PROFILE_EXPECTATIONS = Object.freeze(Object.fromEntries(
  PROFILE_ORDER.map((profileId) => [
    profileId,
    Object.freeze({
      adapter_id: profileId.slice(0, 2),
      configuration_id: `P1-125-${profileId.replace("_", "-")}`,
      configuration_path:
        `evaluation-harness/fixtures/p1-125-six-task-parameterized/system-configurations/${profileId.toLowerCase().replace("_", "-")}.json`,
      repetition_id: profileId.endsWith("_A") ? 1 : 2,
    }),
  ]),
));
const ACCEPTED_ADAPTER_PROOF_FILES = Object.freeze({
  adapter_command_ledger: "worker-output/adapter-command-ledger.json",
  adapter_execution_request: "worker-output/adapter-execution-request.json",
  adapter_result: "worker-output/adapter-result.json",
  b0_result: "b0-result.json",
  b1_program: "b1-program.json",
  environment_snapshot: "environment-snapshot.json",
  execution_descriptor: "execution-descriptor.json",
  request: "request.json",
  run_record: "worker-output/run-record.json",
  stable_projection: "worker-output/stable-projection.json",
  target_executed: "worker-output/target-executed",
  trace: "worker-output/trace.jsonl",
});
const ACCEPTED_ADAPTER_PROCESS_KEYS = Object.freeze([
  "accepted_authority_bundle_identity",
  "cleanup_verified",
  "claim_boundary",
  "cooperative_local_accepted_evidence_path_residual",
  "current_b2_distinct_child_pids",
  "current_b2_scan_receipt_identities",
  "historical_reviewed_binary_exact_bytes_claim",
  "hostile_global_read_isolation_claim",
  "hostile_process_isolation_claim",
  "mode",
  "proof_limits_identity",
  "sandbox_calibration_identity",
  "schema_version",
  "source_formal_root",
  "status",
  "task_id",
  "trusted_accepted_source_required",
]);
const ACCEPTED_ADAPTER_INDEX_KEYS = Object.freeze([
  "accepted_authority_bundle_identity",
  "claim_boundary",
  "cooperative_local_accepted_evidence_path_residual",
  "entries",
  "historical_reviewed_binary_exact_bytes_claim",
  "hostile_global_read_isolation_claim",
  "hostile_process_isolation_claim",
  "proof_limits_identity",
  "sandbox_calibration_identity",
  "schema_version",
  "source_formal_root",
  "task_id",
  "trusted_accepted_source_required",
]);
const ACCEPTED_ADAPTER_INDEX_ENTRY_KEYS = Object.freeze([
  "adapter_id",
  "artifacts",
  "b2_physical_proof",
  "b2_scan_proof_identity",
  "canonical_task_spec_identity",
  "current_b2_cleanup_verified",
  "current_b2_reexecution_identity",
  "profile_id",
  "proof_prefix",
  "repetition_id",
  "source_case_root",
  "source_case_root_identity",
  "source_worker_output_root",
  "staged_proof_root",
  "target_task_id",
]);
const CURRENT_B2_REEXECUTION_KEYS = Object.freeze([
  "claim_boundary",
  "cleanup_verified",
  "cooperative_local_accepted_evidence_path_residual",
  "executable_identity_unchanged",
  "external_effects",
  "fixture_root_identity",
  "fresh_scan_matches_accepted_except_repo_relocation",
  "fresh_scan_result_identity",
  "historical_reviewed_binary_exact_bytes_claim",
  "hostile_global_read_isolation_claim",
  "hostile_process_isolation_claim",
  "process",
  "profile_id",
  "runtime_verified",
  "sandbox_calibration_identity",
  "sandbox_profile_identity",
  "schema_version",
  "selected_executable_identity",
  "selected_scan_source_inventory",
  "selected_scan_source_inventory_sha256",
  "source_accepted_executable_identity",
  "source_inventory_after",
  "source_inventory_before",
  "source_inventory_unchanged",
  "status",
  "target_argv",
  "target_task_id",
  "task_id",
  "trusted_accepted_source_required",
]);
const CONTENT_INVENTORY_KEYS = Object.freeze([
  "entries",
  "entry_set_sha256",
  "file_count",
  "root_identity",
  "total_byte_length",
]);
const CONTENT_INVENTORY_ENTRY_KEYS = Object.freeze([
  "byte_length",
  "mode",
  "nlink",
  "relative_path",
  "sha256",
  "type",
]);
const ACCEPTED_ADAPTER_CALIBRATION_CAPTURE_KEYS = Object.freeze([
  "argv",
  "child_pid",
  "cwd",
  "environment",
  "error_code",
  "exit_status",
  "parent_pid",
  "signal",
  "started_at",
  "stderr_identity",
  "stdout_identity",
  "stopped_at",
  "timed_out",
  "timeout_ms",
]);
const SOURCE_DIRECTORY_IDENTITY_KEYS = Object.freeze([
  "dev",
  "ino",
  "path",
  "uid",
]);
const COMMAND_LEDGER_KEYS = Object.freeze([
  "argv",
  "cwd",
  "ended_at",
  "environment",
  "exit_status",
  "expected_exit_codes",
  "expected_exit_matched",
  "latency_ms",
  "record_type",
  "schema_version",
  "signal",
  "started_at",
  "stderr_byte_length",
  "stderr_sha256",
  "stdout_byte_length",
  "stdout_sha256",
  "timed_out",
  "timeout_seconds",
]);
const RUN_RECORD_KEYS = Object.freeze([
  "adapter_id",
  "adapter_version",
  "artifact_checksums",
  "dataset_version",
  "ended_at",
  "environment_snapshot_id",
  "error_taxonomy",
  "invalid_run_reason",
  "patch_ref",
  "policy_violations",
  "repetition_id",
  "run_id",
  "schema_version",
  "started_at",
  "stop_reason_code",
  "system_configuration_id",
  "task_id",
  "terminal_status",
  "test_artifact_refs",
  "trace_ref",
  "usage",
  "verification_ref",
]);
const ORDINARY_FAILURE_CASES = Object.freeze([
  Object.freeze(["MODEL_FAILURE", "MODEL", "MODEL_OUTPUT_REJECTED"]),
  Object.freeze(["JSON_FAILURE", "JSON", "JSON_DECODE_FAILED"]),
  Object.freeze(["PATCH_IR_FAILURE", "PATCH_IR", "PATCH_IR_REJECTED"]),
  Object.freeze(["COMPILER_FAILURE", "COMPILER", "COMPILER_REJECTED"]),
  Object.freeze(["ORACLE_FAILURE", "ORACLE", "ORACLE_FAILED"]),
  Object.freeze(["TEST_FAILURE", "TEST", "TEST_FAILED"]),
]);
const OUTPUT_TOKEN_SEMANTICS =
  "PROVIDER_REPORTED_OUTPUT_USAGE_NOT_CONTENT_TOKENIZATION";
const OUTPUT_TOKEN_CASES = Object.freeze([2047, 2048, 2049]);
const INTEGRATION_NEGATIVE_CASES = Object.freeze([
  Object.freeze({
    case_id: "CLOSED_REQUEST",
    expected_reason_code: "REQUEST_KEYSET_INVALID",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "TRANSPORT_INCOMPLETE",
    expected_reason_code: "RESPONSE_TRUNCATED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "OBSERVER_MISSING",
    expected_reason_code: "OBSERVER_EVIDENCE_MISSING",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "OBSERVER_FORGED",
    expected_reason_code: "OBSERVER_EVIDENCE_FORGED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "OBSERVER_EXTRA_ROW",
    expected_reason_code: "OBSERVER_EVIDENCE_FORGED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "OBSERVER_MALFORMED_EXTRA_ROW",
    expected_reason_code: "OBSERVER_EVIDENCE_FORGED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "OBSERVER_BAD_HEADER",
    expected_reason_code: "OBSERVER_EVIDENCE_FORGED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "SECRET_REFLECTION",
    expected_reason_code: "SECRET_REFLECTION_DETECTED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "USAGE_OVER",
    expected_reason_code: "PROVIDER_OUTPUT_USAGE_EXCEEDED",
    output_tokens: 2049,
  }),
  Object.freeze({
    case_id: "PATH_ESCAPE",
    expected_reason_code: "PATH_ESCAPE_REJECTED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "SYMLINK_SUPPORT",
    expected_reason_code: "SYMLINK_REJECTED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "HARDLINK_SUPPORT",
    expected_reason_code: "HARDLINK_REJECTED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "CREATE_ONCE_RESPONSE",
    expected_reason_code: "CREATE_ONCE_FAILED",
    output_tokens: 0,
  }),
  Object.freeze({
    case_id: "EVIDENCE_WRITE",
    expected_reason_code: "EVIDENCE_WRITE_FAILED",
    output_tokens: 0,
  }),
]);
const ACCEPTED_INPUT_ORDER = Object.freeze([
  "p1_035",
  "p1_101",
  "p1_129",
  "p1_149",
]);
const ACCEPTED_P1_129_SEMANTIC_VERIFIER_SOURCE = [
  'const fs=require("node:fs")',
  'const crypto=require("node:crypto")',
  'const root="/Users/lijunpeng/Developer/.sourcelens-audit/p1-129-input-boundary-matrix-20260726/task-1/formal-matrix-v1"',
  'const read=(name,expected)=>{const bytes=fs.readFileSync(`${root}/${name}`);const observed=crypto.createHash("sha256").update(bytes).digest("hex");if(observed!==expected)throw new Error(`${name} identity drifted`);return JSON.parse(bytes)}',
  'const summary=read("quality-formal-summary.json","75d178240d3c493ee7d30b8c67428b0cfb9baac637517f70ddf7b0f008dda5c6")',
  'const negative=read("negative-results.json","2a93c69a8847b0333fe59fa39ca5f3441535cd8682e82da128692f1c24cd2166")',
  'const zero=(value)=>value!==null&&typeof value==="object"&&!Array.isArray(value)&&Object.keys(value).sort().join(",")==="network,production,provider,public,remote,secret"&&Object.values(value).every((entry)=>entry===false)',
  'const counts=Object.fromEntries(["PRE_EXECUTION","TARGET_EXECUTION","POST_EXECUTION"].map((stage)=>[stage,negative.results.filter((entry)=>entry.stage===stage).length]))',
  'const accepted=summary.status==="PASS"&&summary.task_id==="AIOS-P1-125_EXACT_SIX_TASK_PARAMETERIZED_ADAPTER_CONVERGENCE"&&summary.accepted_task_count===6&&summary.positive_runs===36&&summary.distinct_positive_run_roots===36&&summary.exact_stable_pairs===18&&summary.b1_exact_rollbacks===12&&summary.b2_real_repository_analysis_scan_children===12&&summary.negative_cases===53&&summary.false_accepts===0&&summary.nonowned_residuals===0&&zero(summary.external_effects)&&negative.schema_version==="p1-125-quality-negative-results/v1"&&Array.isArray(negative.results)&&negative.results.length===53&&new Set(negative.results.map((entry)=>entry.case_id)).size===53&&counts.PRE_EXECUTION===40&&counts.TARGET_EXECUTION===5&&counts.POST_EXECUTION===8&&negative.results.every((entry)=>entry.rejected===true&&entry.expected_reason_code===entry.observed_reason_code&&entry.nonowned_residuals===0&&zero(entry.external_effects))',
  'if(!accepted)throw new Error("accepted P1-129 semantic verification failed")',
  'process.stdout.write(JSON.stringify({accepted_task_count:6,b2_real_repository_analysis_scan_children:12,false_accepts:0,negative_cases:53,status:"PASS"})+"\\n")',
].join(";");
const ACCEPTED_INPUT_CONFIG = Object.freeze({
  p1_035: Object.freeze({
    truth_record: Object.freeze({
      task_id: "AIOS-P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET",
      status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      task_contract_path:
        "docs/aios/tasks/P1-035_VERSIONED_REPRESENTATIVE_TASK_DATASET.yaml",
      task_contract_sha256:
        "acec5432aacd6476693db62bdb52ee326c467f17b691860688fe952f7ffbdc33",
      accepted_candidate_commit: "686eda0cd7a93b72ac5e64301479f17e4b096fb0",
      accepted_candidate_tree: "b2740b44d0051303057deac7d719c27fd6a5578a",
      source_phase: "P1",
    }),
    source_roots: Object.freeze([
      "evaluation-harness/datasets/p1-representative-task-dataset-v1",
      "evaluation-harness/validators/task-dataset-self-test.mjs",
      "evaluation-harness/validators/task-dataset-validator.mjs",
      "scripts/verify-p1-task-dataset.sh",
    ]),
    verifier: Object.freeze(["/bin/bash", "scripts/verify-p1-task-dataset.sh"]),
  }),
  p1_101: Object.freeze({
    truth_record: Object.freeze({
      task_id: "AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE",
      status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      task_contract_path:
        "docs/aios/tasks/P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE.yaml",
      task_contract_sha256:
        "bee1b94f438f2d49a88bd99f2662f404470c446f81ba07be341ac5339d20bf15",
      accepted_candidate_commit: "633f9daf133bf616cd293fb343058e2efba2a3ed",
      accepted_candidate_tree: "999f37f93692a045d455adf0ea503947ed5555a5",
      source_phase: "P1",
    }),
    source_roots: Object.freeze([
      "evaluation-harness/harness/p1-101-accepted-shared-trace",
      "evaluation-harness/recording/p1-101-accepted-shared-trace",
      "evaluation-harness/replay/p1-101-accepted-shared-trace",
      "evaluation-harness/evaluator/p1-101-accepted-shared-trace",
      "evaluation-harness/fixtures/p1-101-accepted-shared-trace",
      "scripts/verify-p1-101-accepted-shared-trace.sh",
    ]),
    verifier: Object.freeze([
      "/bin/bash",
      "scripts/verify-p1-101-accepted-shared-trace.sh",
    ]),
  }),
  p1_129: Object.freeze({
    truth_record: Object.freeze({
      task_id: "AIOS-P1-129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION",
      status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      task_contract_path:
        "docs/aios/tasks/P1-129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION.yaml",
      task_contract_sha256:
        "faa49aef5ddc2dad08edafc914bf8dab7a19c61618cc169d5c1f9f7ec91e2718",
      accepted_candidate_commit: "a772dc5d350ec6b38a84e430b01f75628429aa7b",
      accepted_candidate_tree: "905dd694922ba9a2b452d15c93dc17cefc9e53c1",
      source_phase: "P1",
    }),
    source_roots: Object.freeze([
      "evaluation-harness/adapters/p1-125-six-task-parameterized",
      "evaluation-harness/harness/p1-125-six-task-parameterized",
      "evaluation-harness/recording/p1-125-six-task-parameterized",
      "evaluation-harness/replay/p1-125-six-task-parameterized",
      "evaluation-harness/evaluator/p1-125-six-task-parameterized",
      "evaluation-harness/fixtures/p1-125-six-task-parameterized",
      "scripts/verify-p1-125-six-task-parameterized.sh",
    ]),
    verifier: Object.freeze([
      "/usr/local/bin/node",
      "-e",
      ACCEPTED_P1_129_SEMANTIC_VERIFIER_SOURCE,
    ]),
  }),
  p1_149: Object.freeze({
    truth_record: Object.freeze({
      task_id: "AIOS-P1-149_ACCEPTED_EXECUTION_SPINE_CONVERGENCE",
      status: "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      task_contract_path:
        "docs/aios/tasks/P1-149_ACCEPTED_EXECUTION_SPINE_CONVERGENCE.yaml",
      task_contract_sha256:
        "a0b1fa43e0b9221c03f67ea3fe66bd86a563600102a1a2019a650f6bb0a6a86d",
      accepted_candidate_commit: "88600ee18848e0d2c6d7f2012d0f548021062720",
      accepted_candidate_tree: "34a16c8177bc0f72fd35a0510429ed1979f72fb3",
      source_phase: "P1",
    }),
    source_roots: Object.freeze([
      "evaluation-harness/harness/p1-149-accepted-execution-spine",
      "evaluation-harness/replay/p1-149-accepted-execution-spine",
      "evaluation-harness/evaluator/p1-149-accepted-execution-spine",
      "scripts/verify-p1-149-accepted-execution-spine.sh",
    ]),
    verifier: Object.freeze([
      "/bin/bash",
      "scripts/verify-p1-149-accepted-execution-spine.sh",
    ]),
  }),
});
const SPINE_ARTIFACTS = Object.freeze([
  "provider-response.json",
  "patch-ir.json",
  "compiler-plan.json",
  "pre-snapshot.json",
  "pre-test-receipt.json",
  "post-snapshot.json",
  "apply-receipt.json",
  "oracle-receipt.json",
  "test-receipt.json",
  "rollback-receipt.json",
  "environment.json",
  "system-configuration.json",
  "executable.json",
  "input.json",
  "child-command.json",
  "worker-result.json",
  "execution-trace.jsonl",
  "execution-projection.json",
  "run-record.json",
  "execution-spine.json",
  "p1-101-trace.jsonl",
  "p1-101-stable-projection.json",
  "p1-101-replay-receipt.json",
  "p1-101-adapter-rollback-receipt.json",
]);
const CELL_NON_SPINE_FILES = Object.freeze([
  "join.json",
  "request.raw",
  "request-record.json",
  "context.json",
  "transport/transport-record.json",
  "observer/stdout.log",
  "observer/stderr.log",
  "observer/observation.json",
  "observer/synthetic-fixture.json",
  "usage.json",
  "admission/admitted-response.http",
  "admission/admission-receipt.json",
  "cell-closure.json",
]);

export function expectedCellArtifactPaths() {
  const paths = [
    ...CELL_NON_SPINE_FILES,
    ...SPINE_ARTIFACTS.map((name) => `spine/${name}`),
  ].sort();
  assert(
    paths.length === 37
      && new Set(paths).size === paths.length
      && paths.includes("observer/synthetic-fixture.json"),
    "CELL_ARTIFACT_SET_INVALID",
    "expected cell artifact path set is incomplete or ambiguous",
  );
  return paths;
}

const FALSE_EXTERNAL_EFFECTS = Object.freeze({
  network: false,
  provider: false,
  secret: false,
  remote: false,
  production: false,
  public: false,
});
const CATEGORY_ORDER = Object.freeze([
  "CLOSED_KEYSET_AND_JOIN",
  "TRANSPORT_BOUNDARY_AND_TERMINAL",
  "RAW_OS_OBSERVER",
  "SECRET_REFLECTION",
  "FILESYSTEM_AND_CLOSED_INVENTORY",
  "USAGE_CONTRACT",
  "CRITICAL_REASON_PROPAGATION",
  "LIVENESS",
  "CONCURRENCY",
]);
const CATEGORY_STIMULUS_KIND = Object.freeze({
  CLOSED_KEYSET_AND_JOIN: "CLOSED_RECORD",
  TRANSPORT_BOUNDARY_AND_TERMINAL: "TRANSPORT",
  RAW_OS_OBSERVER: "OBSERVER",
  SECRET_REFLECTION: "SECRET",
  FILESYSTEM_AND_CLOSED_INVENTORY: "FILESYSTEM",
  USAGE_CONTRACT: "USAGE",
  CRITICAL_REASON_PROPAGATION: "PROPAGATION",
  LIVENESS: "LIVENESS",
  CONCURRENCY: "CONCURRENCY",
});
const SECRET_SEGMENT_SIZES = Object.freeze({
  NO_REFLECTION: [4],
  EXACT: [43],
  PREFIX: [44],
  SUFFIX: [44],
  CROSS_CHUNK: [7, 36],
  SPLIT_BOUNDARY: [2, 42],
  BINARY: [45],
});
const FILESYSTEM_RELATIVE_PATHS = Object.freeze({
  OWNED_ROOT_VALID: "artifact.bin",
  ROOT_PREEXISTS: "root",
  PATH_ESCAPE: "../escape.bin",
  SYMLINK: "artifact.bin",
  HARDLINK: "artifact.bin",
  CREATE_ONCE: "artifact.bin",
  IDENTITY_MISSING: "missing.bin",
  IDENTITY_MUTATION: "artifact.bin",
  NON_REGULAR_FILE: "artifact.bin",
  INVENTORY_MISSING: "inventory",
  INVENTORY_EXTRA: "inventory",
  INVENTORY_REORDER: "inventory",
  INVENTORY_DUPLICATE: "inventory",
  INVENTORY_CROSS_BINDING: "inventory",
  EVIDENCE_WRITE_FAILURE: "blocked/artifact.bin",
});
const IDENTITY_KEYS = Object.freeze([
  "path",
  "type",
  "nlink",
  "byte_length",
  "sha256",
]);
const BYTES_IDENTITY_KEYS = Object.freeze([
  "byte_length",
  "sha256",
]);
const ARTIFACT_DESCRIPTOR_KEYS = Object.freeze([
  "path",
  "byte_length",
  "sha256",
]);
const SUPPORTING_ARTIFACT_KEYS = Object.freeze([
  "context_record",
  "observer_record",
  "observer_stderr",
  "observer_stdout",
  "request_body",
  "request_record",
  "transport_record",
  "usage_record",
]);
const ADMISSION_RECEIPT_KEYS = Object.freeze([
  "admitted_response",
  "body_identity",
  "context_record_identity",
  "join",
  "observer_record_identity",
  "request_body_identity",
  "request_record_identity",
  "schema_version",
  "status",
  "supporting_artifacts",
  "task_id",
  "transport_record_identity",
  "usage_record_identity",
]);
const CELL_CLOSURE_KEYS = Object.freeze([
  "admission_receipt_identity",
  "adapter_control_identity",
  "admitted_response_identity",
  "b2_scan_proof_identity",
  "body_identity",
  "denominator_included",
  "failure_receipt_identity",
  "failure_stage",
  "join",
  "outcome",
  "outcome_reason",
  "p1_101_receipt_identities",
  "p1_149_artifact_identities",
  "request_record_identity",
  "schema_version",
  "task_id",
  "worker_success_fields_trusted",
]);
const SAFE_FAILURE_RECEIPT_KEYS = Object.freeze([
  "join",
  "message",
  "reason_code",
  "response_persisted",
  "schema_version",
  "secret_persisted",
  "status",
  "task_id",
]);
const JOIN_KEYS = Object.freeze([
  "execution_id",
  "cell_id",
  "task_id",
  "profile_id",
  "repetition_id",
]);
const CASE_INPUT_KEYS = Object.freeze([
  "schema_version",
  "task_id",
  "case_id",
  "category_id",
  "synthetic_observer_fixture",
  "stimulus",
]);
const CASE_OBSERVATION_KEYS = Object.freeze([
  "schema_version",
  "task_id",
  "case_id",
  "status",
  "reason_code",
  "persistence",
  "process",
  "identities",
  "external_effects",
]);
const FROZEN_SYNTHETIC_OBSERVER_FIXTURE_KEYS = Object.freeze([
  "descriptor",
  "record",
  "stderr_base64",
  "stdout_base64",
]);
const SYNTHETIC_OBSERVER_DESCRIPTOR_KEYS = Object.freeze([
  "command_executed",
  "fixture_index",
  "live_loopback_calibration",
  "live_network_connection_created",
  "live_network_connections_created",
  "production_record_identity",
  "production_record_schema",
  "schema_version",
  "source_kind",
  "status",
  "stderr_identity",
  "stdout_identity",
  "task_id",
]);
const PROCESS_KEYS = Object.freeze([
  "argv",
  "environment",
  "parent_pid",
  "pid",
  "exit_status",
  "signal",
  "started_at",
  "stopped_at",
  "stdout",
  "stderr",
]);
const PROCESS_RESULT_KEYS = Object.freeze([
  "schema_version",
  "task_id",
  "case_id",
  "input_identity",
  "status",
  "reason_code",
]);
const CLOSED_CHILD_ENVIRONMENT_KEYS = Object.freeze([
  "HOME",
  "LANG",
  "LC_ALL",
  "PATH",
  "TZ",
]);
const MANIFEST_KEYS = Object.freeze([
  "schema_version",
  "task_id",
  "matrix_sha256",
  "entry_count",
  "entries",
]);
const KERNEL_CONTRACT_KEYS = Object.freeze([
  "schema_version",
  "task_id",
  "matrix_sha256",
  "response_bytes_max",
  "output_tokens_max",
  "case_order",
  "cell_order",
  "profile_order",
  "concurrency_slots",
  "external_effects",
]);
const LIVENESS_EVENT_KEYS = Object.freeze([
  "actor",
  "argv",
  "case_id",
  "child_pid",
  "child_receipt_identity",
  "exit_status",
  "heartbeat_count",
  "heartbeats",
  "observed_reason_code",
  "parent_pid",
  "schema_version",
  "sequence",
  "signal",
  "started_at",
  "stderr_identity",
  "stdout_identity",
  "stopped_at",
  "task_id",
  "timed_out",
  "timeout_ms",
]);
const CONCURRENCY_EVENT_KEYS = Object.freeze([
  "argv",
  "artifact_identity",
  "child_pid",
  "child_receipt_identity",
  "exit_status",
  "order_basis",
  "parent_pid",
  "reason_code",
  "result_status",
  "schema_version",
  "sequence",
  "signal",
  "slot",
  "started_at",
  "stderr_identity",
  "stdout_identity",
  "stopped_at",
  "task_id",
  "timed_out",
]);
const RAW_COMMAND_RECEIPT_KEYS = Object.freeze([
  "argv",
  "cwd",
  "environment",
  "exit_status",
  "parent_pid",
  "pid",
  "schema_version",
  "signal",
  "started_at",
  "stderr",
  "stdout",
  "stopped_at",
  "task_id",
]);
const ACCEPTED_TRUTH_RECORD_KEYS = Object.freeze([
  "accepted_candidate_commit",
  "accepted_candidate_tree",
  "source_phase",
  "status",
  "task_contract_path",
  "task_contract_sha256",
  "task_id",
]);
const ACCEPTED_INPUT_ENTRY_KEYS = Object.freeze([
  "accepted_input_id",
  "accepted_verifier_receipt",
  "contract_identity",
  "git_ancestry_receipt",
  "git_cat_file_receipt",
  "git_tree_receipt",
  "source_manifest",
  "truth_record",
]);
const CONTROL_CHILD_RECEIPT_KEYS = Object.freeze([
  "argv",
  "environment",
  "exit_status",
  "parent_pid",
  "pid",
  "result",
  "schema_version",
  "signal",
  "slot",
  "started_at",
  "stderr",
  "stdout",
  "stopped_at",
  "task_id",
  "timed_out",
]);
const LIVENESS_CHILD_RECEIPT_KEYS = Object.freeze([
  "argv",
  "case_id",
  "environment",
  "exit_status",
  "heartbeats",
  "parent_pid",
  "pid",
  "reason_code",
  "schema_version",
  "signal",
  "started_at",
  "stderr",
  "stdout",
  "stopped_at",
  "task_id",
  "timed_out",
]);
const HEARTBEAT_KEYS = Object.freeze([
  "actor",
  "case_id",
  "emitted_at",
  "schema_version",
  "sequence",
  "task_id",
]);
const CREATE_ONCE_CHILD_RESULT_KEYS = Object.freeze([
  "artifact_identity",
  "reason_code",
  "schema_version",
  "slot",
  "status",
  "task_id",
]);
const FORBIDDEN_AGGREGATE_KEYS = new Set([
  "aggregate",
  "worker_aggregate",
  "worker_summary",
  "verified_successes",
  "vtsr",
  "readiness_cells",
]);
const FORBIDDEN_SECRET_KEYS = new Set([
  "api_key",
  "authorization",
  "authorization_header",
  "secret_bytes",
  "secret_base64",
  "secret_sha256",
  "sentinel",
  "sentinel_bytes",
  "sentinel_base64",
  "sentinel_sha256",
]);

class EvaluationFailure extends Error {
  constructor(code, message, path = null, caseId = null) {
    super(message);
    this.name = "EvaluationFailure";
    this.code = code;
    this.path = path;
    this.caseId = caseId;
  }
}

function fail(code, message, path = null, caseId = null) {
  throw new EvaluationFailure(code, message, path, caseId);
}

function assert(condition, code, message, path = null, caseId = null) {
  if (!condition) fail(code, message, path, caseId);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function sortedValue(value) {
  if (Array.isArray(value)) return value.map(sortedValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, sortedValue(value[key])]),
    );
  }
  return value;
}

function canonicalJson(value) {
  return JSON.stringify(sortedValue(value));
}

function exactKeys(value, keys, code, label, path = null) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    code,
    `${label} must be an object`,
    path,
  );
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  assert(
    isDeepStrictEqual(actual, expected),
    code,
    `${label} keyset is not closed`,
    path,
  );
}

function validateClosedChildEnvironment(
  value,
  expected,
  code,
  label,
  path = null,
) {
  exactKeys(value, CLOSED_CHILD_ENVIRONMENT_KEYS, code, label, path);
  exactKeys(
    expected,
    CLOSED_CHILD_ENVIRONMENT_KEYS,
    code,
    `${label} expected environment`,
    path,
  );
  assert(
    isDeepStrictEqual(value, expected),
    code,
    `${label} differs from the exact production closed environment`,
    path,
  );
}

function assertNoDuplicateJsonKeys(text, label, path = null) {
  let cursor = 0;
  const whitespace = () => {
    while (cursor < text.length && /\s/.test(text[cursor])) cursor += 1;
  };
  const parseStringToken = () => {
    assert(text[cursor] === '"', "JSON_INVALID", `${label} string expected`, path);
    const start = cursor;
    cursor += 1;
    while (cursor < text.length) {
      const character = text[cursor];
      if (character === '"') {
        cursor += 1;
        try {
          return JSON.parse(text.slice(start, cursor));
        } catch {
          fail("JSON_INVALID", `${label} contains an invalid string`, path);
        }
      }
      if (character === "\\") {
        cursor += 1;
        assert(cursor < text.length, "JSON_INVALID", `${label} escape truncated`, path);
        if (text[cursor] === "u") {
          assert(
            /^[0-9a-fA-F]{4}$/.test(text.slice(cursor + 1, cursor + 5)),
            "JSON_INVALID",
            `${label} unicode escape invalid`,
            path,
          );
          cursor += 5;
          continue;
        }
      } else {
        assert(
          character.charCodeAt(0) >= 0x20,
          "JSON_INVALID",
          `${label} contains a control character`,
          path,
        );
      }
      cursor += 1;
    }
    fail("JSON_INVALID", `${label} string is unterminated`, path);
  };
  const parseNumber = () => {
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(
      text.slice(cursor),
    );
    assert(match !== null, "JSON_INVALID", `${label} number invalid`, path);
    cursor += match[0].length;
  };
  const parseValue = () => {
    whitespace();
    assert(cursor < text.length, "JSON_INVALID", `${label} value missing`, path);
    if (text[cursor] === "{") {
      cursor += 1;
      whitespace();
      const keys = new Set();
      if (text[cursor] === "}") {
        cursor += 1;
        return;
      }
      while (cursor < text.length) {
        whitespace();
        const key = parseStringToken();
        assert(
          !keys.has(key),
          "DUPLICATE_JSON_KEY",
          `${label} contains duplicate key ${key}`,
          path,
        );
        keys.add(key);
        whitespace();
        assert(text[cursor] === ":", "JSON_INVALID", `${label} colon missing`, path);
        cursor += 1;
        parseValue();
        whitespace();
        if (text[cursor] === "}") {
          cursor += 1;
          return;
        }
        assert(text[cursor] === ",", "JSON_INVALID", `${label} comma missing`, path);
        cursor += 1;
      }
      fail("JSON_INVALID", `${label} object is unterminated`, path);
    }
    if (text[cursor] === "[") {
      cursor += 1;
      whitespace();
      if (text[cursor] === "]") {
        cursor += 1;
        return;
      }
      while (cursor < text.length) {
        parseValue();
        whitespace();
        if (text[cursor] === "]") {
          cursor += 1;
          return;
        }
        assert(text[cursor] === ",", "JSON_INVALID", `${label} comma missing`, path);
        cursor += 1;
      }
      fail("JSON_INVALID", `${label} array is unterminated`, path);
    }
    if (text[cursor] === '"') {
      parseStringToken();
      return;
    }
    for (const literal of ["true", "false", "null"]) {
      if (text.startsWith(literal, cursor)) {
        cursor += literal.length;
        return;
      }
    }
    parseNumber();
  };
  parseValue();
  whitespace();
  assert(cursor === text.length, "JSON_INVALID", `${label} has trailing bytes`, path);
}

function parseJsonBytes(bytes, label, path = null) {
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("JSON_INVALID", `${label} is not valid UTF-8`, path);
  }
  assertNoDuplicateJsonKeys(text, label, path);
  try {
    return JSON.parse(text);
  } catch {
    fail("JSON_INVALID", `${label} is not valid JSON`, path);
  }
}

function parseJsonLines(bytes, label, path = null) {
  const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  const lines = text.split("\n");
  if (lines.at(-1) === "") lines.pop();
  assert(lines.length > 0, "JSONL_INVALID", `${label} is empty`, path);
  return lines.map((line, index) =>
    parseJsonBytes(Buffer.from(line), `${label} line ${index + 1}`, path));
}

function safeRelativePath(value, label) {
  assert(
    typeof value === "string"
      && value.length > 0
      && value.length <= 4096
      && !value.includes("\0")
      && !value.includes("\\")
      && !isAbsolute(value),
    "PATH_ESCAPE_REJECTED",
    `${label} is not a safe relative path`,
    typeof value === "string" ? value : null,
  );
  const normalized = normalize(value);
  assert(
    normalized === value
      && !normalized.startsWith(`..${sep}`)
      && normalized !== ".."
      && normalized.split(sep).every((part) => part !== "" && part !== "." && part !== ".."),
    "PATH_ESCAPE_REJECTED",
    `${label} escapes or is not normalized`,
    value,
  );
  return normalized;
}

function assertTrustedAncestors(root) {
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  const chain = [];
  let cursor = root;
  while (true) {
    chain.push(cursor);
    const parent = dirname(cursor);
    if (parent === cursor) break;
    cursor = parent;
  }
  for (const path of chain.reverse()) {
    const stat = lstatSync(path);
    assert(!stat.isSymbolicLink(), "SYMLINK_REJECTED", "Evidence ancestor is a symlink", path);
    assert(stat.isDirectory(), "NON_REGULAR_FILE_REJECTED", "Evidence ancestor is not a directory", path);
    if (uid !== null) {
      assert(
        stat.uid === 0 || stat.uid === uid,
        "EVIDENCE_OWNER_INVALID",
        "Evidence ancestor has an untrusted owner",
        path,
      );
    }
  }
  const rootStat = lstatSync(root);
  if (uid !== null) {
    assert(
      rootStat.uid === uid,
      "EVIDENCE_OWNER_INVALID",
      "Evidence root is not owned by the evaluator user",
      root,
    );
  }
  assert(
    (rootStat.mode & 0o022) === 0,
    "EVIDENCE_ROOT_PERMISSIONS_INVALID",
    "Evidence root is group- or world-writable",
    root,
  );
}

function safeEvidenceRoot(root) {
  assert(
    typeof root === "string" && isAbsolute(root),
    "CLI_USAGE_INVALID",
    "Evidence root must be absolute",
  );
  const absolute = resolve(root);
  const stat = lstatSync(absolute);
  assert(!stat.isSymbolicLink(), "SYMLINK_REJECTED", "Evidence root is a symlink", absolute);
  assert(stat.isDirectory(), "NON_REGULAR_FILE_REJECTED", "Evidence root is not a directory", absolute);
  assert(
    realpathSync.native(absolute) === absolute,
    "PATH_ESCAPE_REJECTED",
    "Evidence root does not resolve to its exact absolute path",
    absolute,
  );
  assertTrustedAncestors(absolute);
  return absolute;
}

function containedPath(root, relativePath, label) {
  const safe = safeRelativePath(relativePath, label);
  const target = join(root, ...safe.split("/"));
  const back = relative(root, target);
  assert(
    back === safe && !back.startsWith("..") && !isAbsolute(back),
    "PATH_ESCAPE_REJECTED",
    `${label} escapes Evidence root`,
    relativePath,
  );
  return target;
}

function evidencePreReadBytesMax(relativePath) {
  if (relativePath === MANIFEST_PATH) {
    return RAW_EVIDENCE_MANIFEST_BYTES_MAX;
  }
  if (
    relativePath.startsWith("raw/accepted-adapter-control/proofs/")
      && (
        relativePath.includes("/worker-output/work/b2-p0-analyzer/")
        || relativePath.includes("/worker-output/work/b2-scan-source/")
      )
  ) {
    return B2_SCAN_SOURCE_SINGLE_FILE_BYTES_MAX;
  }
  if (
    relativePath.startsWith("raw/accepted-adapter-control/proofs/")
      && relativePath.endsWith(
        "/worker-output/work/b2-cargo-target/debug/sourcelens-analyzer",
      )
  ) {
    return ACCEPTED_ADAPTER_EXECUTABLE_BYTES_MAX;
  }
  if (relativePath.startsWith("raw/accepted-adapter-control/proofs/")) {
    return ACCEPTED_ADAPTER_PROOF_SINGLE_FILE_BYTES_MAX;
  }
  return RAW_EVIDENCE_SINGLE_FILE_BYTES_MAX;
}

function readSecureFile(
  root,
  relativePath,
  label = relativePath,
  { bytes_max: bytesMax = RAW_EVIDENCE_SINGLE_FILE_BYTES_MAX } = {},
) {
  const target = containedPath(root, relativePath, label);
  const before = lstatSync(target);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  const effectiveBytesMax = Math.min(
    bytesMax,
    evidencePreReadBytesMax(relativePath),
  );
  assert(
    Number.isSafeInteger(bytesMax)
      && bytesMax >= 0
      && Number.isSafeInteger(effectiveBytesMax)
      && effectiveBytesMax >= 0,
    "CLOSED_INVENTORY_DRIFT",
    `${label} pre-read cap is invalid`,
    relativePath,
  );
  assert(!before.isSymbolicLink(), "SYMLINK_REJECTED", `${label} is a symlink`, relativePath);
  assert(before.isFile(), "NON_REGULAR_FILE_REJECTED", `${label} is not regular`, relativePath);
  assert(before.nlink === 1, "HARDLINK_REJECTED", `${label} has multiple links`, relativePath);
  assert(
    Number.isSafeInteger(before.size) && before.size <= effectiveBytesMax,
    "CLOSED_INVENTORY_DRIFT",
    `${label} exceeds its pre-read byte cap`,
    relativePath,
  );
  if (uid !== null) {
    assert(
      before.uid === uid,
      "EVIDENCE_OWNER_INVALID",
      `${label} has an untrusted owner`,
      relativePath,
    );
  }
  let descriptor;
  try {
    descriptor = openSync(
      target,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.nlink === 1
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.size === before.size
        && opened.size <= effectiveBytesMax,
      "IDENTITY_MISMATCH",
      `${label} changed between lstat and open`,
      relativePath,
    );
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    const finalStat = lstatSync(target);
    assert(
      after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && after.size <= effectiveBytesMax
        && finalStat.dev === opened.dev
        && finalStat.ino === opened.ino
        && finalStat.size === opened.size
        && finalStat.nlink === 1,
      "IDENTITY_MISMATCH",
      `${label} changed while read`,
      relativePath,
    );
    return {
      bytes,
      identity: {
        path: relativePath,
        type: "REGULAR_FILE",
        nlink: 1,
        byte_length: bytes.length,
        sha256: sha256(bytes),
      },
    };
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function currentRepositorySourceIdentity(relativePath) {
  const artifact = readSecureFile(
    REPOSITORY_ROOT,
    relativePath,
    `current P1-168 source ${relativePath}`,
    { bytes_max: 32 * 1024 * 1024 },
  );
  return {
    path: relativePath,
    byte_length: artifact.bytes.length,
    sha256: artifact.identity.sha256,
  };
}

function currentAbsoluteFileIdentity(expected, label) {
  const absolutePath = expected.path;
  assert(
    isAbsolute(absolutePath)
      && resolve(absolutePath) === absolutePath
      && realpathSync.native(absolutePath) === absolutePath,
    "PATH_ESCAPE_REJECTED",
    `${label} path is not exact absolute`,
    absolutePath,
  );
  const before = lstatSync(absolutePath);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assert(
    !before.isSymbolicLink(),
    "SYMLINK_REJECTED",
    `${label} is a symlink`,
    absolutePath,
  );
  assert(
    before.isFile(),
    "NON_REGULAR_FILE_REJECTED",
    `${label} is not a regular file`,
    absolutePath,
  );
  assert(
    before.nlink === 1,
    "HARDLINK_REJECTED",
    `${label} has multiple links`,
    absolutePath,
  );
  assert(
    (uid === null || before.uid === uid)
      && Number.isSafeInteger(before.size)
      && before.size <= 32 * 1024 * 1024,
    "IDENTITY_MISMATCH",
    `${label} ownership or size is invalid`,
    absolutePath,
  );
  let descriptor;
  try {
    descriptor = openSync(
      absolutePath,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.nlink === 1
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.size === before.size,
      "IDENTITY_MISMATCH",
      `${label} changed before open`,
      absolutePath,
    );
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    const finalStat = lstatSync(absolutePath);
    assert(
      after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && finalStat.dev === opened.dev
        && finalStat.ino === opened.ino
        && finalStat.size === opened.size
        && finalStat.nlink === 1,
      "IDENTITY_MISMATCH",
      `${label} changed during read`,
      absolutePath,
    );
    return {
      path: absolutePath,
      byte_length: bytes.length,
      sha256: sha256(bytes),
    };
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function expectedP1168Reproduction(root) {
  return {
    executed_argv: [
      join(REPOSITORY_ROOT, P1_168_VERIFIER_SOURCE_PATH),
      root,
    ],
    independent_evaluator_argv: [
      process.execPath,
      join(
        REPOSITORY_ROOT,
        "evaluation-harness/evaluator/"
        + "p1-165-fail-closed-response-admission/evaluate.mjs",
      ),
      root,
    ],
    fresh_run_argv_template: [
      join(REPOSITORY_ROOT, P1_168_VERIFIER_SOURCE_PATH),
      "<ABSOLUTE_NORMALIZED_ABSENT_EVIDENCE_ROOT>",
    ],
    fresh_root_requirement:
      "ABSOLUTE_NORMALIZED_ABSENT_NON_SYMLINK_CREATE_ONCE",
    cwd: REPOSITORY_ROOT,
    runtime: {
      node_executable: process.execPath,
      node_version: process.version,
      platform: process.platform,
      architecture: process.arch,
    },
  };
}

function currentP1168AbortedStageInventory() {
  const entries = [];
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  let totalBytes = 0;
  let directoryCount = 0;
  const visit = (absoluteDirectory, relativeDirectory, depth) => {
    const directoryStat = lstatSync(absoluteDirectory);
    directoryCount += 1;
    assert(
      directoryStat.isDirectory()
        && !directoryStat.isSymbolicLink()
        && (uid === null || directoryStat.uid === uid)
        && (directoryStat.mode & 0o022) === 0
        && directoryCount <= 1024
        && depth <= 32,
      "IDENTITY_MISMATCH",
      "P1-168 interrupted stage contains an unsafe directory",
      absoluteDirectory,
    );
    for (const name of readdirSync(absoluteDirectory).sort()) {
      const absolutePath = join(absoluteDirectory, name);
      const relativePath = relativeDirectory === ""
        ? name
        : `${relativeDirectory}/${name}`;
      const stat = lstatSync(absolutePath);
      assert(
        !stat.isSymbolicLink() && (uid === null || stat.uid === uid),
        "IDENTITY_MISMATCH",
        "P1-168 interrupted stage contains an unsafe entry",
        absolutePath,
      );
      if (stat.isDirectory()) {
        visit(absolutePath, relativePath, depth + 1);
        continue;
      }
      assert(
        stat.isFile()
          && stat.nlink === 1
          && stat.size <= 32 * 1024 * 1024
          && entries.length < 1024
          && totalBytes + stat.size <= 256 * 1024 * 1024,
        "IDENTITY_MISMATCH",
        "P1-168 interrupted stage file boundary drifted",
        absolutePath,
      );
      const identity = currentAbsoluteFileIdentity(
        { path: absolutePath },
        `P1-168 interrupted stage ${relativePath}`,
      );
      entries.push({
        path: relativePath,
        type: "REGULAR_FILE",
        mode: (stat.mode & 0o777).toString(8),
        byte_length: identity.byte_length,
        sha256: identity.sha256,
      });
      totalBytes += identity.byte_length;
    }
  };
  visit(P1_168_ABORTED_STAGE_PATH, "", 0);
  entries.sort((left, right) => left.path.localeCompare(right.path));
  return {
    entry_count: entries.length,
    total_bytes: totalBytes,
    sha256: sha256(canonicalBytes(entries)),
  };
}

function currentP1168V1RootClosure() {
  const rootStat = lstatSync(P1_168_COMPLETE_MATRIX_V1_ROOT);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assert(
    rootStat.isDirectory()
      && !rootStat.isSymbolicLink()
      && (uid === null || rootStat.uid === uid)
      && (rootStat.mode & 0o777) === 0o700
      && realpathSync.native(P1_168_COMPLETE_MATRIX_V1_ROOT)
        === P1_168_COMPLETE_MATRIX_V1_ROOT,
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete Evidence root identity drifted",
    P1_168_COMPLETE_MATRIX_V1_ROOT,
  );
  const entries = [];
  let totalBytes = 0;
  let directoryCount = 0;
  let manifestBytes = null;
  const visit = (absoluteDirectory, relativeDirectory, depth) => {
    const directoryStat = lstatSync(absoluteDirectory);
    directoryCount += 1;
    assert(
      directoryStat.isDirectory()
        && !directoryStat.isSymbolicLink()
        && (uid === null || directoryStat.uid === uid)
        && (directoryStat.mode & 0o777) === 0o700
        && directoryCount <= 1024
        && depth <= 32,
      "IDENTITY_MISMATCH",
      "P1-168 v1 complete root contains an unsafe directory",
      absoluteDirectory,
    );
    for (const name of readdirSync(absoluteDirectory).sort()) {
      const absolutePath = join(absoluteDirectory, name);
      const relativePath = relativeDirectory === ""
        ? name
        : `${relativeDirectory}/${name}`;
      const before = lstatSync(absolutePath);
      assert(
        !before.isSymbolicLink()
          && (uid === null || before.uid === uid),
        before.isSymbolicLink()
          ? "SYMLINK_REJECTED"
          : "IDENTITY_MISMATCH",
        "P1-168 v1 complete root entry ownership or type drifted",
        absolutePath,
      );
      if (before.isDirectory()) {
        visit(absolutePath, relativePath, depth + 1);
        continue;
      }
      assert(
        before.isFile()
          && before.nlink === 1
          && (before.mode & 0o777) === 0o600
          && before.size <= 32 * 1024 * 1024
          && entries.length < 4096
          && totalBytes + before.size <= 256 * 1024 * 1024,
        before.nlink !== 1
          ? "HARDLINK_REJECTED"
          : !before.isFile()
            ? "NON_REGULAR_FILE_REJECTED"
            : "IDENTITY_MISMATCH",
        "P1-168 v1 complete root file boundary drifted",
        absolutePath,
      );
      let descriptor;
      try {
        descriptor = openSync(
          absolutePath,
          fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
        );
        const opened = fstatSync(descriptor);
        const bytes = readFileSync(descriptor);
        const after = fstatSync(descriptor);
        const finalStat = lstatSync(absolutePath);
        assert(
          opened.isFile()
            && opened.nlink === 1
            && opened.dev === before.dev
            && opened.ino === before.ino
            && opened.size === before.size
            && after.dev === opened.dev
            && after.ino === opened.ino
            && after.size === opened.size
            && finalStat.isFile()
            && !finalStat.isSymbolicLink()
            && finalStat.nlink === 1
            && finalStat.dev === opened.dev
            && finalStat.ino === opened.ino
            && finalStat.size === opened.size
            && (finalStat.mode & 0o777) === 0o600,
          "IDENTITY_MISMATCH",
          "P1-168 v1 complete root file changed during read",
          absolutePath,
        );
        entries.push({
          path: relativePath,
          type: "REGULAR_FILE",
          mode: "600",
          byte_length: bytes.length,
          sha256: sha256(bytes),
        });
        totalBytes += bytes.length;
        if (relativePath === "RAW_EVIDENCE_MANIFEST.json") {
          manifestBytes = bytes;
        }
      } finally {
        if (descriptor !== undefined) closeSync(descriptor);
      }
    }
  };
  visit(P1_168_COMPLETE_MATRIX_V1_ROOT, "", 0);
  entries.sort((left, right) => left.path.localeCompare(right.path));
  assert(
    manifestBytes !== null,
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root manifest is missing",
    P1_168_COMPLETE_MATRIX_V1_ROOT,
  );
  const manifestIdentity = {
    path: P1_168_V1_ARTIFACTS.manifest.path,
    byte_length: manifestBytes.length,
    sha256: sha256(manifestBytes),
  };
  assert(
    isDeepStrictEqual(
      manifestIdentity,
      P1_168_V1_ARTIFACTS.manifest,
    ),
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root manifest identity drifted",
    P1_168_V1_ARTIFACTS.manifest.path,
  );
  const manifest = parseJsonBytes(
    manifestBytes,
    "P1-168 v1 complete root manifest",
    P1_168_V1_ARTIFACTS.manifest.path,
  );
  exactKeys(
    manifest,
    [
      "entries",
      "entry_count",
      "matrix_sha256",
      "schema_version",
      "task_id",
    ],
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root manifest",
    P1_168_V1_ARTIFACTS.manifest.path,
  );
  assert(
    manifestBytes.equals(canonicalBytes(manifest))
      && manifest.schema_version === "p1-165-raw-evidence-manifest/v1"
      && manifest.task_id === TASK_ID
      && manifest.entry_count === 3829
      && manifest.matrix_sha256
        === "f9a38ecc512d4c2c8ba536eb3023dc6dfb6f78cfc5203be5853fe68321a5a298"
      && Array.isArray(manifest.entries)
      && manifest.entries.length === manifest.entry_count,
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root manifest schema drifted",
    P1_168_V1_ARTIFACTS.manifest.path,
  );
  const declaredPaths = new Set();
  for (const entry of manifest.entries) {
    exactKeys(
      entry,
      ["byte_length", "nlink", "path", "sha256", "type"],
      "IDENTITY_MISMATCH",
      "P1-168 v1 manifest entry",
      P1_168_V1_ARTIFACTS.manifest.path,
    );
    assert(
      typeof entry.path === "string"
        && entry.path.length > 0
        && !entry.path.includes("\0")
        && !entry.path.includes("\\")
        && !isAbsolute(entry.path)
        && !entry.path.split("/").includes("..")
        && !declaredPaths.has(entry.path)
        && entry.type === "REGULAR_FILE"
        && entry.nlink === 1
        && Number.isSafeInteger(entry.byte_length)
        && entry.byte_length >= 0
        && /^[0-9a-f]{64}$/.test(entry.sha256),
      "IDENTITY_MISMATCH",
      "P1-168 v1 manifest entry is ambiguous or invalid",
      P1_168_V1_ARTIFACTS.manifest.path,
    );
    declaredPaths.add(entry.path);
  }
  const liveDeclaredEntries = entries
    .filter((entry) => entry.path !== "RAW_EVIDENCE_MANIFEST.json")
    .map((entry) => ({
      path: entry.path,
      type: entry.type,
      nlink: 1,
      byte_length: entry.byte_length,
      sha256: entry.sha256,
    }));
  assert(
    isDeepStrictEqual(manifest.entries, liveDeclaredEntries),
    "IDENTITY_MISMATCH",
    "P1-168 v1 manifest does not exactly bind every live payload file",
    P1_168_V1_ARTIFACTS.manifest.path,
  );
  const inventory = {
    entry_count: entries.length,
    total_bytes: totalBytes,
    sha256: sha256(canonicalBytes(entries)),
  };
  assert(
    isDeepStrictEqual(inventory, {
      entry_count: 3830,
      total_bytes: 167164014,
      sha256:
        "d083c053e8de09efbfed2d2109c7c861ad0d7fc00e7c8b0dd92c808e32d91a64",
    }),
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root closed inventory drifted",
    P1_168_COMPLETE_MATRIX_V1_ROOT,
  );
  return {
    root: {
      path: P1_168_COMPLETE_MATRIX_V1_ROOT,
      type: "DIRECTORY",
      mode: rootStat.mode & 0o777,
      owned_by_current_uid: uid === null || rootStat.uid === uid,
      symlink: false,
    },
    manifest: {
      identity: manifestIdentity,
      schema_version: manifest.schema_version,
      matrix_sha256: manifest.matrix_sha256,
      declared_entry_count: manifest.entry_count,
      entries_exact: true,
    },
    inventory,
    undeclared_files: 0,
    missing_files: 0,
    duplicate_manifest_paths: 0,
    reordered_manifest_entries: 0,
    status: "PASS",
  };
}

function expectedP1168PriorInterruptedAttempt(root) {
  assert(
    root !== P1_168_COMPLETE_MATRIX_V1_ROOT,
    "ROOT_PREEXISTS",
    "P1-168 v1 Evidence root is terminal and cannot be reused",
    root,
  );
  const stat = lstatSync(P1_168_ABORTED_STAGE_PATH);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assert(
    stat.isDirectory()
      && !stat.isSymbolicLink()
      && (uid === null || stat.uid === uid)
      && realpathSync.native(P1_168_ABORTED_STAGE_PATH)
        === P1_168_ABORTED_STAGE_PATH,
    "IDENTITY_MISMATCH",
    "P1-168 interrupted precommit stage identity drifted",
    P1_168_ABORTED_STAGE_PATH,
  );
  const stageInventory = currentP1168AbortedStageInventory();
  assert(
    isDeepStrictEqual(stageInventory, {
      entry_count: 744,
      total_bytes: 161608624,
      sha256:
        "18e90cfb2d16c6fe78f152cb96321c44c2706df3591a9dbb997d2ef8f142659b",
    }),
    "IDENTITY_MISMATCH",
    "P1-168 interrupted stage closed inventory drifted",
    P1_168_ABORTED_STAGE_PATH,
  );
  const artifacts = Object.fromEntries(
    Object.entries(P1_168_V1_ARTIFACTS).map(([name, identity]) => {
      const observed = currentAbsoluteFileIdentity(
        identity,
        `P1-168 v1 prior ${name}`,
      );
      assert(
        isDeepStrictEqual(observed, identity),
        "IDENTITY_MISMATCH",
        `P1-168 v1 prior ${name} bytes drifted`,
        identity.path,
      );
      return [name, observed];
    }),
  );
  const wrapperExit = parseJsonBytes(
    readFileSync(artifacts.wrapper_exit.path),
    "P1-168 v1 wrapper exit receipt",
    artifacts.wrapper_exit.path,
  );
  const evaluatorExit = parseJsonBytes(
    readFileSync(artifacts.evaluator_exit.path),
    "P1-168 v1 evaluator exit receipt",
    artifacts.evaluator_exit.path,
  );
  const evaluatorResult = parseJsonBytes(
    readFileSync(artifacts.evaluator_stdout.path),
    "P1-168 v1 evaluator result",
    artifacts.evaluator_stdout.path,
  );
  assert(
    wrapperExit.status === "NON_PASS"
      && wrapperExit.exit_status === 1
      && evaluatorExit.status === "NON_PASS"
      && evaluatorExit.exit_status === 1
      && evaluatorExit.signal === null
      && evaluatorResult.status === "NON_PASS"
      && evaluatorResult.reason_code === "PROCESS_RECORD_INVALID",
    "IDENTITY_MISMATCH",
    "P1-168 v1 prior verdict drifted",
    artifacts.wrapper_exit.path,
  );
  const completeEvidenceRoot = currentP1168V1RootClosure();
  return {
    schema_version: "p1-168-prior-attempt-disclosure/v2",
    status: "TERMINAL_NON_PASS",
    evidence_root: P1_168_COMPLETE_MATRIX_V1_ROOT,
    root_preserved: true,
    source_hash_stale: true,
    accepted_evidence: false,
    reused_as_accepted: false,
    artifacts,
    complete_evidence_root: completeEvidenceRoot,
    wrapper: {
      status: wrapperExit.status,
      exit_status: wrapperExit.exit_status,
    },
    independent_evaluator: {
      status: evaluatorResult.status,
      reason_code: evaluatorResult.reason_code,
      exit_status: evaluatorExit.exit_status,
      signal: evaluatorExit.signal,
    },
    aborted_precommit_stage: {
      status: "PRECOMMIT_ABORTED_QUALITY_INTERCEPT",
      exit_status: 130,
      root: {
        path: P1_168_ABORTED_STAGE_PATH,
        type: "DIRECTORY",
        mode: stat.mode & 0o777,
        owned_by_current_uid: uid === null || stat.uid === uid,
        symlink: false,
      },
      inventory: stageInventory,
      final_root_created: false,
      accepted_evidence: false,
      stage_reused: false,
    },
  };
}

function expectedP1168V2AndMakeVerifyLineage(root) {
  assert(
    root !== P1_168_COMPLETE_MATRIX_ROOT,
    "ROOT_PREEXISTS",
    "P1-168 v2 Evidence root is historical and cannot be reused",
    root,
  );
  const rootStat = lstatSync(P1_168_COMPLETE_MATRIX_ROOT);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assert(
    rootStat.isDirectory()
      && !rootStat.isSymbolicLink()
      && (uid === null || rootStat.uid === uid)
      && (rootStat.mode & 0o777) === 0o700
      && realpathSync.native(P1_168_COMPLETE_MATRIX_ROOT)
        === P1_168_COMPLETE_MATRIX_ROOT,
    "IDENTITY_MISMATCH",
    "P1-168 v2 Evidence root identity drifted",
    P1_168_COMPLETE_MATRIX_ROOT,
  );
  const manifestEntries = listClosedFiles(P1_168_COMPLETE_MATRIX_ROOT, {
    directory_count_max: 1024,
    depth_max: 32,
    file_count_max: 4096,
    single_file_bytes_max: 32 * 1024 * 1024,
    total_bytes_max: 256 * 1024 * 1024,
  });
  const inventoryEntries = manifestEntries.map((entry) => ({
    path: entry.path,
    type: entry.type,
    mode: "600",
    byte_length: entry.byte_length,
    sha256: entry.sha256,
  }));
  const inventory = {
    entry_count: inventoryEntries.length,
    total_bytes: inventoryEntries.reduce(
      (total, entry) => total + entry.byte_length,
      0,
    ),
    sha256: sha256(canonicalBytes(inventoryEntries)),
  };
  assert(
    isDeepStrictEqual(inventory, {
      entry_count: 3830,
      total_bytes: 167175907,
      sha256:
        "41e2680bad8f5622678cc900321c7f767bfabad7a003e31f97f65836d89218ff",
    }),
    "IDENTITY_MISMATCH",
    "P1-168 v2 complete root closed inventory drifted",
    P1_168_COMPLETE_MATRIX_ROOT,
  );
  const artifacts = Object.fromEntries(
    Object.entries(P1_168_V2_ARTIFACTS).map(([name, identity]) => {
      const observed = currentAbsoluteFileIdentity(
        identity,
        `P1-168 v2 ${name}`,
      );
      assert(
        isDeepStrictEqual(observed, identity),
        "IDENTITY_MISMATCH",
        `P1-168 v2 ${name} bytes drifted`,
        identity.path,
      );
      return [name, observed];
    }),
  );
  const manifest = parseJsonBytes(
    readFileSync(artifacts.manifest.path),
    "P1-168 v2 complete root manifest",
    artifacts.manifest.path,
  );
  assert(
    manifest.schema_version === "p1-165-raw-evidence-manifest/v1"
      && manifest.task_id === TASK_ID
      && manifest.entry_count === 3829
      && manifest.matrix_sha256
        === "289ebf1022b1531e11c56d3bc8ae2ff2c2c874d841017703b64097a50d1dd393"
      && isDeepStrictEqual(
        manifest.entries,
        manifestEntries
          .filter((entry) => entry.path !== "RAW_EVIDENCE_MANIFEST.json"),
      ),
    "IDENTITY_MISMATCH",
    "P1-168 v2 manifest does not close the exact root",
    artifacts.manifest.path,
  );
  const wrapperExit = parseJsonBytes(
    readFileSync(artifacts.wrapper_exit.path),
    "P1-168 v2 wrapper exit receipt",
    artifacts.wrapper_exit.path,
  );
  const wrapperLines = readFileSync(artifacts.wrapper_stdout.path, "utf8")
    .split("\n")
    .filter((line) => line.startsWith("{"))
    .map((line) => parseJsonBytes(
      Buffer.from(line),
      "P1-168 v2 wrapper stdout JSON line",
      artifacts.wrapper_stdout.path,
    ));
  const evaluatorResult = wrapperLines.at(-1);
  assert(
    wrapperExit.status === "PASS"
      && wrapperExit.exit_status === 0
      && wrapperLines.length >= 2
      && wrapperLines[0].status === "PASS"
      && evaluatorResult.status === "PASS"
      && evaluatorResult.reason_code === "PASS",
    "IDENTITY_MISMATCH",
    "P1-168 v2 preflight/evaluator verdict drifted",
    artifacts.wrapper_stdout.path,
  );
  const makeArtifacts = Object.fromEntries(
    Object.entries(P1_168_MAKE_VERIFY_V1_ARTIFACTS)
      .map(([name, identity]) => {
        const observed = currentAbsoluteFileIdentity(
          identity,
          `P1-168 make verify v1 ${name}`,
        );
        assert(
          isDeepStrictEqual(observed, identity),
          "IDENTITY_MISMATCH",
          `P1-168 make verify v1 ${name} bytes drifted`,
          identity.path,
        );
        return [name, observed];
      }),
  );
  const makeReceipt = parseJsonBytes(
    readFileSync(makeArtifacts.receipt.path),
    "P1-168 worktree make verify v1 receipt",
    makeArtifacts.receipt.path,
  );
  assert(
    makeReceipt.schema_version === "p1-168-task-worktree-make-verify/v1"
      && makeReceipt.task_id === P1_168_TASK_ID
      && makeReceipt.status === "NON_PASS"
      && makeReceipt.exit_status === 2
      && makeReceipt.stdout.path === "stdout.log"
      && makeReceipt.stdout.byte_length === makeArtifacts.stdout.byte_length
      && makeReceipt.stdout.sha256 === makeArtifacts.stdout.sha256
      && makeReceipt.stderr.path === "stderr.log"
      && makeReceipt.stderr.byte_length === makeArtifacts.stderr.byte_length
      && makeReceipt.stderr.sha256 === makeArtifacts.stderr.sha256,
    "IDENTITY_MISMATCH",
    "P1-168 worktree make verify v1 failure identity drifted",
    makeArtifacts.receipt.path,
  );
  return {
    complete_matrix_v2: {
      schema_version: "p1-168-prior-complete-matrix-disclosure/v1",
      status: "PREFLIGHT_PASS_BUT_GLOBAL_HARNESS_GATE_NON_PASS",
      evidence_root: P1_168_COMPLETE_MATRIX_ROOT,
      root_preserved: true,
      accepted_evidence: false,
      reused_as_accepted: false,
      artifacts,
      complete_evidence_root: {
        manifest: {
          identity: artifacts.manifest,
          schema_version: manifest.schema_version,
          matrix_sha256: manifest.matrix_sha256,
          declared_entry_count: manifest.entry_count,
          entries_exact: true,
        },
        inventory,
        undeclared_files: 0,
        missing_files: 0,
        status: "PASS",
      },
      wrapper: {
        status: wrapperExit.status,
        exit_status: wrapperExit.exit_status,
      },
      independent_evaluator: {
        result_embedded_in_wrapper_stdout: true,
        status: evaluatorResult.status,
        reason_code: evaluatorResult.reason_code,
      },
    },
    worktree_make_verify_v1: {
      schema_version: makeReceipt.schema_version,
      status: makeReceipt.status,
      exit_status: makeReceipt.exit_status,
      normalized_root_cause:
        "P1168.WORKTREE_VERIFY.HARNESS_NETWORK_CAPABILITY_BOUNDARY",
      accepted_evidence: false,
      reused_as_accepted: false,
      artifacts: makeArtifacts,
    },
  };
}

function validateP1168GateEnvelope(root, manifestState) {
  const sourceBundle = readBoundJson(
    root,
    manifestState,
    P1_168_SOURCE_BUNDLE_PATH,
    "P1-168 current kernel source bundle",
  );
  exactKeys(
    sourceBundle,
    [
      "execution_files",
      "reproduction",
      "schema_version",
      "source_file_count",
      "status",
      "task_id",
      "verifier",
    ],
    "IDENTITY_MISMATCH",
    "P1-168 current kernel source bundle",
    P1_168_SOURCE_BUNDLE_PATH,
  );
  assert(
    sourceBundle.schema_version
      === "p1-168-current-kernel-source-bundle/v1"
      && sourceBundle.task_id === P1_168_TASK_ID
      && Array.isArray(sourceBundle.execution_files)
      && sourceBundle.execution_files.length
        === P1_168_EXECUTION_SOURCE_PATHS.length
      && sourceBundle.source_file_count
        === P1_168_EXECUTION_SOURCE_PATHS.length + 1
      && sourceBundle.status === "PASS",
    "IDENTITY_MISMATCH",
    "P1-168 source bundle fixed fields drifted",
    P1_168_SOURCE_BUNDLE_PATH,
  );
  const validateSourceIdentity = (identity, expectedPath, label) => {
    exactKeys(
      identity,
      ["byte_length", "path", "sha256"],
      "IDENTITY_MISMATCH",
      label,
      P1_168_SOURCE_BUNDLE_PATH,
    );
    assert(
      identity.path === expectedPath
        && Number.isSafeInteger(identity.byte_length)
        && identity.byte_length >= 0
        && /^[0-9a-f]{64}$/.test(identity.sha256),
      "IDENTITY_MISMATCH",
      `${label} identity shape drifted`,
      P1_168_SOURCE_BUNDLE_PATH,
    );
  };
  sourceBundle.execution_files.forEach((identity, index) => {
    const expectedPath = P1_168_EXECUTION_SOURCE_PATHS[index];
    validateSourceIdentity(
      identity,
      expectedPath,
      `P1-168 execution source ${index}`,
    );
    assert(
      isDeepStrictEqual(
        identity,
        currentRepositorySourceIdentity(expectedPath),
      ),
      "IDENTITY_MISMATCH",
      `P1-168 execution source bytes drifted: ${expectedPath}`,
      P1_168_SOURCE_BUNDLE_PATH,
    );
  });
  validateSourceIdentity(
    sourceBundle.verifier,
    P1_168_VERIFIER_SOURCE_PATH,
    "P1-168 verifier",
  );
  assert(
    isDeepStrictEqual(
      sourceBundle.verifier,
      currentRepositorySourceIdentity(P1_168_VERIFIER_SOURCE_PATH),
    )
      && isDeepStrictEqual(
        sourceBundle.reproduction,
        expectedP1168Reproduction(root),
      ),
    "IDENTITY_MISMATCH",
    "P1-168 verifier or reproduction identity drifted",
    P1_168_SOURCE_BUNDLE_PATH,
  );

  const envelopeArtifact = readBoundBytes(
    root,
    manifestState,
    P1_168_GATE_ENVELOPE_PATH,
    "P1-168 Task gate envelope",
  );
  const envelope = parseJsonBytes(
    envelopeArtifact.bytes,
    "P1-168 Task gate envelope",
    P1_168_GATE_ENVELOPE_PATH,
  );
  exactKeys(
    envelope,
    [
      "compatibility_kernel",
      "prior_complete_matrix_v2_and_global_gate",
      "prior_interrupted_attempt",
      "reproduction",
      "restore_receipt",
      "schema_version",
      "source_bundle_identity",
      "status",
      "task_authority",
      "task_contract",
      "task_id",
    ],
    "IDENTITY_MISMATCH",
    "P1-168 Task gate envelope",
    P1_168_GATE_ENVELOPE_PATH,
  );
  const expectedContract = currentAbsoluteFileIdentity(
    {
      path: join(
        REPOSITORY_ROOT,
        P1_168_TASK_CONTRACT_RELATIVE_PATH,
      ),
      ...P1_168_TASK_CONTRACT_IDENTITY,
    },
    "P1-168 Task Contract",
  );
  const expectedAuthority = currentAbsoluteFileIdentity(
    P1_168_TASK_AUTHORITY,
    "P1-168 Task authority",
  );
  const expectedRestore = currentAbsoluteFileIdentity(
    P1_168_RESTORE_RECEIPT,
    "P1-168 restore receipt",
  );
  assert(
    envelope.schema_version === "p1-168-task-gate-envelope/v1"
      && envelope.task_id === P1_168_TASK_ID
      && isDeepStrictEqual(envelope.task_contract, expectedContract)
      && isDeepStrictEqual(envelope.task_authority, expectedAuthority)
      && isDeepStrictEqual(envelope.restore_receipt, expectedRestore)
      && isDeepStrictEqual(
        envelope.reproduction,
        expectedP1168Reproduction(root),
      )
      && isDeepStrictEqual(
        envelope.prior_interrupted_attempt,
        expectedP1168PriorInterruptedAttempt(root),
      )
      && isDeepStrictEqual(
        envelope.prior_complete_matrix_v2_and_global_gate,
        expectedP1168V2AndMakeVerifyLineage(root),
      )
      && envelope.status === "READY_FOR_INDEPENDENT_EVALUATION",
    "IDENTITY_MISMATCH",
    "P1-168 Task gate envelope authority identity drifted",
    P1_168_GATE_ENVELOPE_PATH,
  );
  validateArtifactDescriptor(
    envelope.source_bundle_identity,
    P1_168_SOURCE_BUNDLE_PATH,
    manifestState,
    "P1-168 gate source bundle",
    P1_168_GATE_ENVELOPE_PATH,
  );
  exactKeys(
    envelope.compatibility_kernel,
    [
      "admitted_matrix_cases",
      "matrix_cases",
      "matrix_sha256",
      "safe_failure_receipts",
      "schema_version",
      "status",
      "task_id",
    ],
    "IDENTITY_MISMATCH",
    "P1-168 compatibility kernel",
    P1_168_GATE_ENVELOPE_PATH,
  );
  assert(
    envelope.compatibility_kernel.schema_version
      === "p1-165-offline-preflight/v1"
      && envelope.compatibility_kernel.task_id === TASK_ID
      && envelope.compatibility_kernel.matrix_sha256 === MATRIX_SHA256
      && envelope.compatibility_kernel.matrix_cases === MATRIX_CASE_COUNT
      && envelope.compatibility_kernel.admitted_matrix_cases === 14
      && envelope.compatibility_kernel.safe_failure_receipts === 85
      && envelope.compatibility_kernel.status === "PASS",
    "IDENTITY_MISMATCH",
    "P1-168 inner compatibility kernel identity drifted",
    P1_168_GATE_ENVELOPE_PATH,
  );
  return {
    envelope,
    envelope_identity: {
      path: P1_168_GATE_ENVELOPE_PATH,
      ...plainIdentity(envelopeArtifact.bytes),
    },
    source_bundle: sourceBundle,
  };
}

function listClosedFiles(
  root,
  {
    directory_count_max: directoryCountMax =
      RAW_EVIDENCE_DIRECTORY_COUNT_MAX,
    depth_max: depthMax = RAW_EVIDENCE_DEPTH_MAX,
    file_count_max: fileCountMax = RAW_EVIDENCE_FILE_COUNT_MAX,
    single_file_bytes_max: singleFileBytesMax =
      RAW_EVIDENCE_SINGLE_FILE_BYTES_MAX,
    total_bytes_max: totalBytesMax = RAW_EVIDENCE_TOTAL_BYTES_MAX,
  } = {},
) {
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  const files = [];
  let directoryCount = 0;
  let totalBytes = 0;
  let acceptedAdapterProofFileCount = 0;
  let acceptedAdapterProofTotalBytes = 0;
  const b2TreeBounds = new Map();
  const visit = (relativeDirectory, depth) => {
    directoryCount += 1;
    assert(
      directoryCount <= directoryCountMax && depth <= depthMax,
      "CLOSED_INVENTORY_DRIFT",
      "closed Evidence exceeds its directory-count or depth cap",
      relativeDirectory,
    );
    const absolute = relativeDirectory === ""
      ? root
      : containedPath(root, relativeDirectory, "Evidence directory");
    const names = readdirSync(absolute).sort();
    assert(
      (relativeDirectory === "" || names.length > 0)
        && names.length <= fileCountMax + directoryCountMax,
      "CLOSED_INVENTORY_DRIFT",
      "closed Evidence contains an empty or over-wide directory",
      relativeDirectory,
    );
    for (const name of names) {
      assert(
        name !== "." && name !== ".." && !name.includes("/") && !name.includes("\\"),
        "PATH_ESCAPE_REJECTED",
        "Evidence entry name is invalid",
        name,
      );
      const relativePath = relativeDirectory === "" ? name : `${relativeDirectory}/${name}`;
      const absolutePath = containedPath(root, relativePath, "Evidence entry");
      const stat = lstatSync(absolutePath);
      assert(!stat.isSymbolicLink(), "SYMLINK_REJECTED", "closed Evidence contains symlink", relativePath);
      if (uid !== null) {
        assert(
          stat.uid === uid,
          "EVIDENCE_OWNER_INVALID",
          "closed Evidence entry has an untrusted owner",
          relativePath,
        );
      }
      if (stat.isDirectory()) {
        assert(
          (stat.mode & 0o022) === 0,
          "EVIDENCE_ROOT_PERMISSIONS_INVALID",
          "Evidence directory is group- or world-writable",
          relativePath,
        );
        visit(relativePath, depth + 1);
      } else {
        assert(stat.isFile(), "NON_REGULAR_FILE_REJECTED", "closed Evidence contains non-file", relativePath);
        assert(stat.nlink === 1, "HARDLINK_REJECTED", "closed Evidence contains hardlink", relativePath);
        const proofBase = "raw/accepted-adapter-control/proofs/";
        if (relativePath.startsWith(proofBase)) {
          acceptedAdapterProofFileCount += 1;
          acceptedAdapterProofTotalBytes += stat.size;
          assert(
            acceptedAdapterProofFileCount
                <= ACCEPTED_ADAPTER_PROOF_FILE_COUNT_MAX
              && acceptedAdapterProofTotalBytes
                <= ACCEPTED_ADAPTER_PROOF_TOTAL_BYTES_MAX
              && relativePath.slice(proofBase.length).split("/").length
                <= ACCEPTED_ADAPTER_PROOF_DEPTH_MAX,
            "CLOSED_INVENTORY_DRIFT",
            "accepted adapter proof exceeds its pre-read count, byte, or depth cap",
            relativePath,
          );
          const treeMarker = [
            "/worker-output/work/b2-p0-analyzer/",
            "/worker-output/work/b2-scan-source/",
          ].find((marker) => relativePath.includes(marker));
          const treeMarkerIndex = treeMarker === undefined
            ? -1
            : relativePath.indexOf(treeMarker);
          if (treeMarkerIndex >= 0) {
            const sourceRoot = relativePath.slice(
              0,
              treeMarkerIndex + treeMarker.length - 1,
            );
            const sourceRelativePath = relativePath.slice(
              treeMarkerIndex + treeMarker.length,
            );
            const prior = b2TreeBounds.get(sourceRoot) ?? {
              count: 0,
              total_bytes: 0,
            };
            const next = {
              count: prior.count + 1,
              total_bytes: prior.total_bytes + stat.size,
            };
            assert(
              next.count <= B2_SCAN_SOURCE_FILE_COUNT_MAX
                && next.total_bytes <= B2_SCAN_SOURCE_TOTAL_BYTES_MAX
                && sourceRelativePath.split("/").length
                  <= B2_SCAN_SOURCE_DEPTH_MAX,
              "CLOSED_INVENTORY_DRIFT",
              "accepted B2 analyzer or scan-source tree exceeds its pre-read cap",
              relativePath,
            );
            b2TreeBounds.set(sourceRoot, next);
          }
        }
        assert(
          files.length + 1 <= fileCountMax
            && Number.isSafeInteger(stat.size)
            && stat.size <= singleFileBytesMax
            && totalBytes + stat.size <= totalBytesMax,
          "CLOSED_INVENTORY_DRIFT",
          "closed Evidence exceeds its file-count, per-file, or aggregate cap",
          relativePath,
        );
        const identity = readSecureFile(
          root,
          relativePath,
          relativePath,
          { bytes_max: singleFileBytesMax },
        ).identity;
        totalBytes += identity.byte_length;
        files.push(identity);
      }
    }
  };
  visit("", 0);
  return files.sort((left, right) => left.path.localeCompare(right.path));
}

function validateMatrixStimulusPlan(caseEntry) {
  const stimulus = caseEntry.stimulus;
  const expectedKind = CATEGORY_STIMULUS_KIND[caseEntry.category_id];
  exactKeys(
    stimulus,
    ["kind", "parameters", "variant"],
    "MATRIX_SCHEMA_INVALID",
    "quality matrix stimulus",
    MATRIX_PATH,
  );
  assert(
    stimulus.kind === expectedKind
      && typeof stimulus.variant === "string"
      && /^[A-Z0-9_]+$/.test(stimulus.variant),
    "MATRIX_SCHEMA_INVALID",
    "quality matrix stimulus kind or variant drifted",
    MATRIX_PATH,
  );
  const parameters = stimulus.parameters;
  if (expectedKind === "CLOSED_RECORD") {
    exactKeys(
      parameters,
      ["mutation", "record_type"],
      "MATRIX_SCHEMA_INVALID",
      "closed-record matrix parameters",
      MATRIX_PATH,
    );
    assert(
      ["REQUEST", "CONTEXT", "TRANSPORT", "OBSERVER", "JOIN"]
        .includes(parameters.record_type)
        && parameters.mutation === stimulus.variant,
      "MATRIX_SCHEMA_INVALID",
      "closed-record matrix semantics drifted",
      MATRIX_PATH,
    );
  } else if (expectedKind === "TRANSPORT") {
    exactKeys(
      parameters,
      [
        "generator",
        "join_source",
        "policy_source",
        "request_record_identity_source",
      ],
      "MATRIX_SCHEMA_INVALID",
      "transport matrix parameters",
      MATRIX_PATH,
    );
    assert(
      parameters.generator === stimulus.variant
        && parameters.join_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
        && parameters.policy_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
        && parameters.request_record_identity_source
          === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE",
      "MATRIX_SCHEMA_INVALID",
      "transport matrix source plan drifted",
      MATRIX_PATH,
    );
  } else if (expectedKind === "OBSERVER") {
    exactKeys(
      parameters,
      [
        "join_source",
        "mutation",
        "policy_source",
        "record_source",
        "request_record_identity_source",
        "stderr_source",
        "stdout_source",
      ],
      "MATRIX_SCHEMA_INVALID",
      "observer matrix parameters",
      MATRIX_PATH,
    );
    assert(
      parameters.mutation === stimulus.variant
        && [
          "join_source",
          "policy_source",
          "record_source",
          "request_record_identity_source",
          "stderr_source",
          "stdout_source",
        ].every((key) => parameters[key] === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"),
      "MATRIX_SCHEMA_INVALID",
      "observer matrix source plan drifted",
      MATRIX_PATH,
    );
  } else if (expectedKind === "SECRET") {
    exactKeys(
      parameters,
      ["embedding", "segment_sizes"],
      "MATRIX_SCHEMA_INVALID",
      "secret matrix parameters",
      MATRIX_PATH,
    );
    assert(
      parameters.embedding === stimulus.variant
        && Object.hasOwn(SECRET_SEGMENT_SIZES, stimulus.variant)
        && isDeepStrictEqual(
          parameters.segment_sizes,
          SECRET_SEGMENT_SIZES[stimulus.variant],
        ),
      "MATRIX_SCHEMA_INVALID",
      "secret matrix embedding or segment sizes drifted",
      MATRIX_PATH,
    );
  } else if (expectedKind === "FILESYSTEM") {
    exactKeys(
      parameters,
      ["operation", "relative_path"],
      "MATRIX_SCHEMA_INVALID",
      "filesystem matrix parameters",
      MATRIX_PATH,
    );
    assert(
      parameters.operation === stimulus.variant
        && FILESYSTEM_RELATIVE_PATHS[stimulus.variant]
          === parameters.relative_path,
      "MATRIX_SCHEMA_INVALID",
      "filesystem matrix operation or path drifted",
      MATRIX_PATH,
    );
  } else if (expectedKind === "USAGE") {
    exactKeys(
      parameters,
      [
        "full_spine_required",
        "join_source",
        "output_tokens",
        "policy_source",
        "response_identity_source",
        "usage",
        "usage_state",
      ],
      "MATRIX_SCHEMA_INVALID",
      "usage matrix parameters",
      MATRIX_PATH,
    );
    const outputBoundary = stimulus.variant === "OUTPUT_BOUNDARY";
    assert(
      parameters.join_source === "MATRIX_CASE_MATERIAL"
        && parameters.response_identity_source === "MATRIX_CASE_MATERIAL"
        && parameters.policy_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
        && (
          outputBoundary
            ? (
              Number.isSafeInteger(parameters.output_tokens)
              && [2047, 2048, 2049].includes(parameters.output_tokens)
              && parameters.full_spine_required
                === (parameters.output_tokens === 2048)
              && parameters.usage_state === "OBSERVED"
              && parameters.usage === "OUTPUT_BOUNDARY"
              && parameters.output_tokens === caseEntry.output_tokens
              && parameters.full_spine_required
                === caseEntry.full_spine_required
            )
            : (
              parameters.output_tokens === null
              && parameters.full_spine_required === false
              && (
                stimulus.variant === "ABSENT_UNKNOWN"
                  ? (
                    parameters.usage_state === "UNKNOWN"
                    && parameters.usage === null
                  )
                  : (
                    parameters.usage_state === "OBSERVED"
                    && parameters.usage === stimulus.variant
                  )
              )
            )
        ),
      "MATRIX_SCHEMA_INVALID",
      "usage matrix typed semantics drifted",
      MATRIX_PATH,
    );
  } else if (expectedKind === "PROPAGATION") {
    exactKeys(
      parameters,
      ["reason_path"],
      "MATRIX_SCHEMA_INVALID",
      "propagation matrix parameters",
      MATRIX_PATH,
    );
    exactKeys(
      parameters.reason_path,
      ["child", "helper", "wrapper"],
      "MATRIX_SCHEMA_INVALID",
      "propagation matrix reason path",
      MATRIX_PATH,
    );
    assert(
      ["child", "helper", "wrapper"].every(
        (key) =>
          parameters.reason_path[key] === caseEntry.expected_reason_code,
      ),
      "MATRIX_SCHEMA_INVALID",
      "propagation matrix reason path drifted",
      MATRIX_PATH,
    );
  } else if (expectedKind === "LIVENESS") {
    exactKeys(
      parameters,
      ["events", "maximum_gap_ms"],
      "MATRIX_SCHEMA_INVALID",
      "liveness matrix parameters",
      MATRIX_PATH,
    );
    assert(
      parameters.maximum_gap_ms === 100
        && Array.isArray(parameters.events)
        && [1, 2].includes(parameters.events.length),
      "MATRIX_SCHEMA_INVALID",
      "liveness matrix plan drifted",
      MATRIX_PATH,
    );
    for (const [index, event] of parameters.events.entries()) {
      exactKeys(
        event,
        ["actor", "monotonic_ms", "sequence"],
        "MATRIX_SCHEMA_INVALID",
        "liveness matrix event",
        MATRIX_PATH,
      );
      assert(
        ["WORKER", "OBSERVER", "EVIDENCE_WRITER"].includes(event.actor)
          && event.sequence === index + 1
          && Number.isSafeInteger(event.monotonic_ms),
        "MATRIX_SCHEMA_INVALID",
        "liveness matrix event semantics drifted",
        MATRIX_PATH,
      );
    }
  } else if (expectedKind === "CONCURRENCY") {
    exactKeys(
      parameters,
      ["events", "maximum_slots"],
      "MATRIX_SCHEMA_INVALID",
      "concurrency matrix parameters",
      MATRIX_PATH,
    );
    assert(
      parameters.maximum_slots === 4
        && Array.isArray(parameters.events)
        && parameters.events.length >= 1,
      "MATRIX_SCHEMA_INVALID",
      "concurrency matrix plan drifted",
      MATRIX_PATH,
    );
    for (const event of parameters.events) {
      exactKeys(
        event,
        ["sequence", "slot", "type"],
        "MATRIX_SCHEMA_INVALID",
        "concurrency matrix event",
        MATRIX_PATH,
      );
      assert(
        Number.isSafeInteger(event.sequence)
          && Number.isSafeInteger(event.slot)
          && ["OPEN", "CLOSE"].includes(event.type),
        "MATRIX_SCHEMA_INVALID",
        "concurrency matrix event semantics drifted",
        MATRIX_PATH,
      );
    }
  } else {
    fail(
      "MATRIX_SCHEMA_INVALID",
      "quality matrix stimulus category is unknown",
      MATRIX_PATH,
    );
  }
  return JSON.parse(JSON.stringify(stimulus));
}

function loadAndValidateMatrix() {
  const bytes = readFileSync(MATRIX_PATH);
  assert(
    bytes.length === MATRIX_BYTE_LENGTH && sha256(bytes) === MATRIX_SHA256,
    "MATRIX_IDENTITY_MISMATCH",
    "quality matrix exact bytes drifted",
    MATRIX_PATH,
  );
  const matrix = parseJsonBytes(bytes, "quality matrix", MATRIX_PATH);
  exactKeys(
    matrix,
    [
      "schema_version",
      "task_id",
      "claim_boundary",
      "response_bytes_max",
      "output_tokens_max",
      "synthetic_cells",
      "external_effects",
      "categories",
    ],
    "MATRIX_SCHEMA_INVALID",
    "quality matrix",
    MATRIX_PATH,
  );
  assert(
    matrix.schema_version === MATRIX_SCHEMA
      && matrix.task_id === TASK_ID
      && matrix.response_bytes_max === RESPONSE_BYTES_MAX
      && matrix.output_tokens_max === OUTPUT_TOKENS_MAX
      && isDeepStrictEqual(matrix.external_effects, FALSE_EXTERNAL_EFFECTS),
    "MATRIX_SCHEMA_INVALID",
    "quality matrix fixed contract drifted",
    MATRIX_PATH,
  );
  assert(
    isDeepStrictEqual(
      matrix.categories.map((category) => category.category_id),
      CATEGORY_ORDER,
    ),
    "MATRIX_SCHEMA_INVALID",
    "quality matrix category set or order drifted",
    MATRIX_PATH,
  );
  const cases = [];
  for (const category of matrix.categories) {
    exactKeys(
      category,
      ["category_id", "cases"],
      "MATRIX_SCHEMA_INVALID",
      "quality matrix category",
      MATRIX_PATH,
    );
    assert(Array.isArray(category.cases), "MATRIX_SCHEMA_INVALID", "matrix cases missing", MATRIX_PATH);
    for (const entry of category.cases) {
      const typedOutputBoundary =
        Object.hasOwn(entry, "output_tokens")
        || Object.hasOwn(entry, "full_spine_required");
      exactKeys(
        entry,
        typedOutputBoundary
          ? [
              "case_id",
              "output_tokens",
              "full_spine_required",
              "expected_status",
              "expected_reason_code",
              "expected_persistence",
              "stimulus",
            ]
          : [
              "case_id",
              "expected_status",
              "expected_reason_code",
              "expected_persistence",
              "stimulus",
            ],
        "MATRIX_SCHEMA_INVALID",
        "quality matrix case",
        MATRIX_PATH,
      );
      assert(
        /^[A-Z0-9_]+$/.test(entry.case_id)
          && ["PASS", "NON_PASS"].includes(entry.expected_status)
          && /^[A-Z0-9_]+$/.test(entry.expected_reason_code)
          && ["ADMITTED", "NONE"].includes(entry.expected_persistence)
          && (entry.expected_status === "PASS")
            === (entry.expected_reason_code === "PASS")
          && (entry.expected_status === "PASS")
            === (entry.expected_persistence === "ADMITTED")
          && (
            !typedOutputBoundary
            || (
              category.category_id === "USAGE_CONTRACT"
              && Number.isSafeInteger(entry.output_tokens)
              && [2047, 2048, 2049].includes(entry.output_tokens)
              && typeof entry.full_spine_required === "boolean"
              && entry.full_spine_required === (entry.output_tokens === 2048)
            )
          ),
        "MATRIX_SCHEMA_INVALID",
        `quality matrix case ${entry.case_id} semantics invalid`,
        MATRIX_PATH,
      );
      validateMatrixStimulusPlan({
        ...entry,
        category_id: category.category_id,
      });
      cases.push({ ...entry, category_id: category.category_id });
    }
  }
  assert(
    cases.length === MATRIX_CASE_COUNT
      && new Set(cases.map((entry) => entry.case_id)).size === cases.length,
    "MATRIX_SCHEMA_INVALID",
    "quality matrix case count or identity set drifted",
    MATRIX_PATH,
  );
  return {
    matrix,
    cases,
    identity: {
      path: MATRIX_PATH,
      sha256: MATRIX_SHA256,
      byte_length: bytes.length,
    },
  };
}

function validateManifest(root, matrixIdentity) {
  const manifestArtifact = readSecureFile(
    root,
    MANIFEST_PATH,
    "raw Evidence manifest",
    { bytes_max: RAW_EVIDENCE_MANIFEST_BYTES_MAX },
  );
  const manifest = parseJsonBytes(
    manifestArtifact.bytes,
    "raw Evidence manifest",
    MANIFEST_PATH,
  );
  exactKeys(
    manifest,
    MANIFEST_KEYS,
    "CLOSED_INVENTORY_DRIFT",
    "raw Evidence manifest",
    MANIFEST_PATH,
  );
  assert(
    manifest.schema_version === MANIFEST_SCHEMA
      && manifest.task_id === TASK_ID
      && manifest.matrix_sha256 === matrixIdentity.sha256
      && Number.isSafeInteger(manifest.entry_count)
      && manifest.entry_count >= 1
      && manifest.entry_count < RAW_EVIDENCE_FILE_COUNT_MAX
      && Array.isArray(manifest.entries)
      && manifest.entry_count === manifest.entries.length,
    "CLOSED_INVENTORY_DRIFT",
    "raw Evidence manifest header invalid",
    MANIFEST_PATH,
  );
  const actual = listClosedFiles(root).filter((entry) => entry.path !== MANIFEST_PATH);
  const prior = [];
  let declaredTotalBytes = manifestArtifact.identity.byte_length;
  for (const entry of manifest.entries) {
    exactKeys(
      entry,
      IDENTITY_KEYS,
      "CLOSED_INVENTORY_DRIFT",
      "raw Evidence manifest entry",
      MANIFEST_PATH,
    );
    safeRelativePath(entry.path, "manifest entry path");
    const entryDepth = entry.path.split("/").length - 1;
    assert(
      entry.type === "REGULAR_FILE"
        && entry.nlink === 1
        && Number.isSafeInteger(entry.byte_length)
        && entry.byte_length >= 0
        && entry.byte_length <= RAW_EVIDENCE_SINGLE_FILE_BYTES_MAX
        && entryDepth <= RAW_EVIDENCE_DEPTH_MAX
        && /^[0-9a-f]{64}$/.test(entry.sha256),
      "CLOSED_INVENTORY_DRIFT",
      "raw Evidence manifest entry invalid",
      entry.path,
    );
    declaredTotalBytes += entry.byte_length;
    assert(
      Number.isSafeInteger(declaredTotalBytes)
        && declaredTotalBytes <= RAW_EVIDENCE_TOTAL_BYTES_MAX,
      "CLOSED_INVENTORY_DRIFT",
      "raw Evidence manifest exceeds the aggregate byte cap",
      entry.path,
    );
    prior.push(entry.path);
  }
  assert(
    isDeepStrictEqual(prior, [...prior].sort())
      && new Set(prior).size === prior.length
      && isDeepStrictEqual(manifest.entries, actual),
    "CLOSED_INVENTORY_DRIFT",
    "raw Evidence tree differs from sorted closed manifest",
    MANIFEST_PATH,
  );
  return {
    manifest,
    artifact: manifestArtifact,
    byPath: new Map(actual.map((entry) => [entry.path, entry])),
  };
}

function readBoundJson(root, manifestState, path, label) {
  const expected = manifestState.byPath.get(path);
  assert(expected !== undefined, "CLOSED_INVENTORY_DRIFT", `${label} absent from manifest`, path);
  const artifact = readSecureFile(root, path, label);
  assert(
    isDeepStrictEqual(artifact.identity, expected),
    "IDENTITY_MISMATCH",
    `${label} differs from manifest identity`,
    path,
  );
  return parseJsonBytes(artifact.bytes, label, path);
}

function readBoundBytes(root, manifestState, path, label) {
  const expected = manifestState.byPath.get(path);
  assert(expected !== undefined, "CLOSED_INVENTORY_DRIFT", `${label} absent from manifest`, path);
  const artifact = readSecureFile(root, path, label);
  assert(
    isDeepStrictEqual(artifact.identity, expected),
    "IDENTITY_MISMATCH",
    `${label} differs from manifest identity`,
    path,
  );
  return artifact;
}

function validateBoundIdentity(identity, manifestState, label) {
  exactKeys(identity, IDENTITY_KEYS, "IDENTITY_MISMATCH", label);
  safeRelativePath(identity.path, `${label}.path`);
  assert(
    identity.type === "REGULAR_FILE"
      && identity.nlink === 1
      && Number.isSafeInteger(identity.byte_length)
      && identity.byte_length >= 0
      && /^[0-9a-f]{64}$/.test(identity.sha256),
    "IDENTITY_MISMATCH",
    `${label} shape invalid`,
    identity.path,
  );
  assert(
    isDeepStrictEqual(manifestState.byPath.get(identity.path), identity),
    "IDENTITY_MISMATCH",
    `${label} does not equal manifest identity`,
    identity.path,
  );
  return identity;
}

function validateBoundArtifactDescriptor(
  descriptor,
  manifestState,
  label,
  expectedPath = null,
) {
  exactKeys(
    descriptor,
    ARTIFACT_DESCRIPTOR_KEYS,
    "IDENTITY_MISMATCH",
    label,
  );
  safeRelativePath(descriptor.path, `${label}.path`);
  assert(
    (expectedPath === null || descriptor.path === expectedPath)
      && Number.isSafeInteger(descriptor.byte_length)
      && descriptor.byte_length >= 0
      && /^[0-9a-f]{64}$/.test(descriptor.sha256),
    "IDENTITY_MISMATCH",
    `${label} descriptor shape or path is invalid`,
    descriptor.path,
  );
  const manifestIdentity = manifestState.byPath.get(descriptor.path);
  assert(
    manifestIdentity !== undefined
      && manifestIdentity.type === "REGULAR_FILE"
      && manifestIdentity.nlink === 1
      && manifestIdentity.byte_length === descriptor.byte_length
      && manifestIdentity.sha256 === descriptor.sha256,
    "IDENTITY_MISMATCH",
    `${label} descriptor does not bind the manifest file`,
    descriptor.path,
  );
  return descriptor;
}

function bytesIdentityFromBound(identity) {
  return {
    byte_length: identity.byte_length,
    sha256: identity.sha256,
  };
}

function validateBytesIdentity(value, expected, label, path = null) {
  exactKeys(value, BYTES_IDENTITY_KEYS, "IDENTITY_MISMATCH", label, path);
  assert(
    Number.isSafeInteger(value.byte_length)
      && value.byte_length >= 0
      && /^[0-9a-f]{64}$/.test(value.sha256)
      && isDeepStrictEqual(value, expected),
    "IDENTITY_MISMATCH",
    `${label} does not bind exact bytes`,
    path,
  );
  return value;
}

function validateArtifactDescriptor(
  value,
  expectedPath,
  manifestState,
  label,
  path = null,
) {
  exactKeys(
    value,
    ARTIFACT_DESCRIPTOR_KEYS,
    "EVIDENCE_CROSS_BINDING_INVALID",
    label,
    path,
  );
  assert(
    value.path === expectedPath,
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${label} path is not exact`,
    path,
  );
  const expected = manifestState.byPath.get(expectedPath);
  assert(
    expected !== undefined
      && value.byte_length === expected.byte_length
      && value.sha256 === expected.sha256,
    "IDENTITY_MISMATCH",
    `${label} differs from closed manifest identity`,
    expectedPath,
  );
  return value;
}

function assertFalseEffects(value, label, path = null) {
  assert(
    isDeepStrictEqual(value, FALSE_EXTERNAL_EFFECTS),
    "EXTERNAL_EFFECT_FORBIDDEN",
    `${label} contains an external effect`,
    path,
  );
}

function scanForbiddenEvidenceFields(value, path = "$") {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => scanForbiddenEvidenceFields(entry, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    const normalized = key.toLowerCase();
    assert(
      !FORBIDDEN_AGGREGATE_KEYS.has(normalized),
      "WORKER_AGGREGATE_FORBIDDEN",
      `raw Evidence contains forbidden Worker aggregate key ${key}`,
      path,
    );
    assert(
      !FORBIDDEN_SECRET_KEYS.has(normalized),
      "SECRET_EVIDENCE_FORBIDDEN",
      `raw Evidence contains forbidden Secret material key ${key}`,
      path,
    );
    scanForbiddenEvidenceFields(child, `${path}.${key}`);
  }
}

function parseProcessResult(bytes, path) {
  const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  const lines = text.split("\n").filter((line) => line.trim() !== "");
  assert(lines.length >= 1, "PROCESS_RESULT_MISSING", "case process stdout is empty", path);
  const result = parseJsonBytes(
    Buffer.from(lines.at(-1)),
    "case process final result",
    path,
  );
  exactKeys(
    result,
    PROCESS_RESULT_KEYS,
    "PROCESS_RESULT_INVALID",
    "case process final result",
    path,
  );
  assert(
    result.schema_version === CASE_PROCESS_RESULT_SCHEMA,
    "PROCESS_RESULT_INVALID",
    "case process result schema invalid",
    path,
  );
  return result;
}

function decodeCanonicalBase64(value, code, label, path = null) {
  assert(
    typeof value === "string"
      && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/
        .test(value),
    code,
    `${label} is not canonical Base64`,
    path,
  );
  const bytes = Buffer.from(value, "base64");
  assert(
    bytes.toString("base64") === value,
    code,
    `${label} Base64 round-trip drifted`,
    path,
  );
  return bytes;
}

function validateCaseProcess(
  root,
  manifestState,
  processRecord,
  expected,
  atomicCommit,
  expectedChildEnvironment,
) {
  const caseBase = `raw/matrix-process/${expected.case_id}`;
  const relativeInputPath = `${caseBase}/input.json`;
  safeRelativePath(relativeInputPath, "matrix child input relative path");
  const expectedInputPath = resolve(
    atomicCommit.staged_root_path,
    ...relativeInputPath.split("/"),
  );
  const expectedInputIdentity = manifestState.byPath.get(relativeInputPath);
  assert(
    expectedInputIdentity !== undefined,
    "PROCESS_RECORD_INVALID",
    "case process input is absent from manifest",
    `${caseBase}/input.json`,
    expected.case_id,
  );
  const finalInput = readBoundBytes(
    root,
    manifestState,
    relativeInputPath,
    "matrix child final input",
  );
  assert(
    atomicCommit.staged_root_absent === true
      && optionalLstat(atomicCommit.staged_root_path) === null
      && relative(atomicCommit.staged_root_path, expectedInputPath)
        === relativeInputPath
      && containedPath(root, relativeInputPath, "matrix child final input")
        === resolve(root, ...relativeInputPath.split("/"))
      && finalInput.identity.byte_length === expectedInputIdentity.byte_length
      && finalInput.identity.sha256 === expectedInputIdentity.sha256,
    "PROCESS_RECORD_INVALID",
    "matrix child staged input cannot be rebound to exact committed bytes",
    relativeInputPath,
    expected.case_id,
  );
  const expectedArgv = [
    process.execPath,
    PREFLIGHT_PATH,
    "--matrix-case",
    expectedInputPath,
    expected.case_id,
    String(expectedInputIdentity.byte_length),
    expectedInputIdentity.sha256,
  ];
  exactKeys(
    processRecord,
    PROCESS_KEYS,
    "PROCESS_RECORD_INVALID",
    "case process record",
  );
  validateClosedChildEnvironment(
    processRecord.environment,
    expectedChildEnvironment,
    "PROCESS_RECORD_INVALID",
    "case process environment",
    null,
  );
  assert(
    Array.isArray(processRecord.argv)
      && processRecord.argv.length === expectedArgv.length
      && processRecord.argv.every(
        (entry) => typeof entry === "string" && entry.length > 0 && !entry.includes("\0"),
      )
      && Number.isSafeInteger(processRecord.parent_pid)
      && processRecord.parent_pid > 0
      && Number.isSafeInteger(processRecord.pid)
      && processRecord.pid > 0
      && processRecord.parent_pid !== processRecord.pid
      && Number.isInteger(processRecord.exit_status)
      && processRecord.signal === null,
    "PROCESS_RECORD_INVALID",
    "case process identity invalid",
    null,
    expected.case_id,
  );
  assert(
    isDeepStrictEqual(processRecord.argv, expectedArgv),
    "PROCESS_RECORD_INVALID",
    "case process argv is not the exact production child invocation",
    null,
    expected.case_id,
  );
  const started = Date.parse(processRecord.started_at);
  const stopped = Date.parse(processRecord.stopped_at);
  assert(
    Number.isFinite(started) && Number.isFinite(stopped) && started <= stopped,
    "PROCESS_RECORD_INVALID",
    "case process timestamps invalid",
    null,
    expected.case_id,
  );
  const stdoutIdentity = validateBoundIdentity(
    processRecord.stdout,
    manifestState,
    "case process stdout",
  );
  const stderrIdentity = validateBoundIdentity(
    processRecord.stderr,
    manifestState,
    "case process stderr",
  );
  assert(
    stdoutIdentity.path === `${caseBase}/process/stdout.log`
      && stderrIdentity.path === `${caseBase}/process/stderr.log`,
    "PROCESS_RECORD_INVALID",
    "case process stdout/stderr paths are not exact",
    null,
    expected.case_id,
  );
  const stdout = readBoundBytes(
    root,
    manifestState,
    stdoutIdentity.path,
    "case process stdout",
  );
  const stderr = readBoundBytes(
    root,
    manifestState,
    stderrIdentity.path,
    "case process stderr",
  );
  const result = parseProcessResult(stdout.bytes, stdoutIdentity.path);
  assert(
    stdout.bytes.equals(canonicalBytes(result))
      && stderr.bytes.length === 0
      && stderr.identity.sha256 === sha256(Buffer.alloc(0))
      && result.task_id === TASK_ID
      && result.case_id === expected.case_id
      && result.status === expected.expected_status
      && result.reason_code === expected.expected_reason_code
      && isDeepStrictEqual(
        result.input_identity,
        bytesIdentityFromBound(expectedInputIdentity),
      )
      && processRecord.exit_status === (expected.expected_status === "PASS" ? 0 : 1),
    "CRITICAL_REASON_PROPAGATION_INVALID",
    `case ${expected.case_id} process result did not preserve exact decision`,
    stdoutIdentity.path,
    expected.case_id,
  );
}

function validatePropagationStimulus(stimulus, expected) {
  if (expected.category_id !== "CRITICAL_REASON_PROPAGATION") return;
  assert(
    stimulus !== null
      && typeof stimulus === "object"
      && !Array.isArray(stimulus)
      && stimulus.parameters !== null
      && typeof stimulus.parameters === "object"
      && stimulus.parameters.reason_path !== null
      && typeof stimulus.parameters.reason_path === "object",
    "CRITICAL_REASON_PROPAGATION_INVALID",
    `case ${expected.case_id} lacks raw reason path`,
    null,
    expected.case_id,
  );
  exactKeys(
    stimulus.parameters.reason_path,
    ["helper", "child", "wrapper"],
    "CRITICAL_REASON_PROPAGATION_INVALID",
    "critical reason path",
  );
  assert(
    ["helper", "child", "wrapper"].every(
      (layer) =>
        stimulus.parameters.reason_path[layer] === expected.expected_reason_code,
    ),
    "CRITICAL_REASON_PROPAGATION_INVALID",
    `case ${expected.case_id} renamed a critical reason`,
    null,
    expected.case_id,
  );
}

function plainIdentity(bytes) {
  return { byte_length: bytes.length, sha256: sha256(bytes) };
}

function canonicalBytes(value) {
  return Buffer.from(`${canonicalJson(value)}\n`, "utf8");
}

function replayJoin(overrides = {}) {
  return {
    execution_id: "P1-165-INDEPENDENT-EVALUATOR",
    cell_id: "P1-165-INDEPENDENT-CELL",
    task_id: TASK_ID,
    profile_id: "B0_A",
    repetition_id: "R1",
    ...overrides,
  };
}

function replayPolicy(overrides = {}) {
  return {
    expected_peer: "127.0.0.1:8787",
    mode: "FORMAL_LOOPBACK",
    output_tokens_max: OUTPUT_TOKENS_MAX,
    response_bytes_max: RESPONSE_BYTES_MAX,
    ...overrides,
  };
}

function makeHttpResponse(body, headers = []) {
  const headerLines = [
    "HTTP/1.1 200 OK",
    ...headers,
    "",
    "",
  ];
  return Buffer.concat([
    Buffer.from(headerLines.join("\r\n"), "latin1"),
    body,
  ]);
}

function makeExactLengthEofResponse(totalBytes) {
  const header = Buffer.from("HTTP/1.1 200 OK\r\nX-P1-165: evaluator\r\n\r\n", "latin1");
  assert(
    totalBytes >= header.length,
    "EVALUATOR_INTERNAL_ERROR",
    "transport fixture total is smaller than HTTP header",
  );
  return Buffer.concat([
    header,
    Buffer.alloc(totalBytes - header.length, 0x61),
  ]);
}

function replayObserverFixture() {
  const join = replayJoin();
  const requestIdentity = plainIdentity(Buffer.from("request"));
  const policy = replayPolicy({ mode: "OWNED_CALIBRATION" });
  const pid = 42420;
  const fd = "9u";
  const local = "127.0.0.1:50165";
  const peer = policy.expected_peer;
  const stdout = Buffer.from(
    [
      "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME",
      `node ${pid} evaluator ${fd} IPv4 0x0 0t0 TCP ${local}->${peer} (ESTABLISHED)`,
      "",
    ].join("\n"),
    "utf8",
  );
  const stderr = Buffer.alloc(0);
  const row = { pid, fd, local, peer, state: "ESTABLISHED" };
  const record = {
    schema_version: "p1-165-os-network-observation/v1",
    join,
    request_record_identity: requestIdentity,
    policy,
    command: [
      "/usr/sbin/lsof",
      "-nP",
      "-a",
      "-p",
      String(pid),
      `-iTCP@${peer}`,
    ],
    pid,
    fd,
    local,
    peer,
    started_at: "1970-01-01T00:00:00.000Z",
    stopped_at: "1970-01-01T00:00:00.000Z",
    exit_status: 0,
    stdout_path: "raw/independent/observer/stdout.log",
    stdout_identity: plainIdentity(stdout),
    stderr_path: "raw/independent/observer/stderr.log",
    stderr_identity: plainIdentity(stderr),
    observed_rows: [row],
    status: "PASS",
  };
  const descriptor = {
    schema_version: "p1-168-frozen-synthetic-observer-fixture/v1",
    task_id: TASK_ID,
    fixture_index: 1,
    source_kind: "FROZEN_SYNTHETIC_OBSERVER_FIXTURE",
    command_executed: false,
    live_network_connection_created: false,
    live_network_connections_created: 0,
    live_loopback_calibration: "DEFERRED_TO_P1_169",
    production_record_schema: record.schema_version,
    production_record_identity: plainIdentity(canonicalBytes(record)),
    stdout_identity: plainIdentity(stdout),
    stderr_identity: plainIdentity(stderr),
    status: "PASS_SYNTHETIC_FIXTURE_ONLY",
  };
  return {
    join,
    requestIdentity,
    policy,
    stdout,
    stderr,
    record,
    row,
    descriptor,
  };
}

function mutateJsonBytes(value, mutate) {
  const clone = JSON.parse(JSON.stringify(value));
  mutate(clone);
  return canonicalBytes(clone);
}

function duplicateTopLevelKeyBytes(value, key) {
  const canonical = canonicalJson(value);
  assert(
    canonical.startsWith("{"),
    "EVALUATOR_INTERNAL_ERROR",
    "duplicate-key fixture must be an object",
  );
  return Buffer.from(
    `{"${key}":${canonicalJson(value[key])},${canonical.slice(1)}\n`,
    "utf8",
  );
}

function replayClosedCase(stimulus, modules) {
  exactKeys(
    stimulus.parameters,
    ["mutation", "record_type"],
    "REQUEST_KEYSET_INVALID",
    "closed-record stimulus parameters",
  );
  const { mutation, record_type: recordType } = stimulus.parameters;
  assert(
    mutation === stimulus.variant
      && ["REQUEST", "CONTEXT", "TRANSPORT", "OBSERVER", "JOIN"]
        .includes(recordType),
    "REQUEST_KEYSET_INVALID",
    "closed-record stimulus semantics are invalid",
  );
  const join = replayJoin();
  const policy = replayPolicy();
  const adapterIdentity = {
    path: "raw/accepted-adapter-control/evaluator/adapter-result.json",
    ...plainIdentity(Buffer.from("adapter-result")),
  };
  const context = {
    adapter_result_identity: adapterIdentity,
    join,
    schema_version: "p1-165-context-record/v1",
    task_id: TASK_ID,
  };
  const contextBytes = canonicalBytes(context);
  const request = {
    context_record_identity: plainIdentity(contextBytes),
    join,
    policy,
    request_body_identity: plainIdentity(Buffer.from("request-body")),
    schema_version: "p1-165-request-record/v1",
    task_id: TASK_ID,
  };
  const requestBytes = canonicalBytes(request);
  if (recordType === "REQUEST" && mutation === "VALID") {
    modules.admission.parseClosedRequestRecord(requestBytes);
    return;
  }
  if (recordType === "REQUEST" && mutation === "EXTRA") {
    modules.admission.parseClosedRequestRecord(
      mutateJsonBytes(request, (value) => { value.extra = true; }),
    );
    return;
  }
  if (recordType === "REQUEST" && mutation === "MISSING") {
    modules.admission.parseClosedRequestRecord(
      mutateJsonBytes(request, (value) => { delete value.policy; }),
    );
    return;
  }
  if (recordType === "REQUEST" && mutation === "DUPLICATE") {
    modules.admission.parseClosedRequestRecord(
      duplicateTopLevelKeyBytes(request, "task_id"),
    );
    return;
  }
  if (recordType === "CONTEXT" && mutation === "EXTRA") {
    modules.admission.parseClosedContextRecord(
      mutateJsonBytes(context, (value) => { value.extra = true; }),
    );
    return;
  }
  if (recordType === "CONTEXT" && mutation === "MISSING") {
    modules.admission.parseClosedContextRecord(
      mutateJsonBytes(context, (value) => { delete value.adapter_result_identity; }),
    );
    return;
  }
  if (recordType === "CONTEXT" && mutation === "DUPLICATE") {
    modules.admission.parseClosedContextRecord(
      duplicateTopLevelKeyBytes(context, "task_id"),
    );
    return;
  }
  if (recordType === "TRANSPORT") {
    assert(
      typeof modules.transport.parseClosedTransportRecord === "function",
      "EVALUATOR_PRODUCTION_API_MISSING",
      "production kernel lacks parseClosedTransportRecord",
    );
    const response = makeHttpResponse(Buffer.from("{}"), ["Content-Length: 2"]);
    const analyzed = modules.transport.analyzeTransport({
      join,
      request_record_identity: plainIdentity(requestBytes),
      chunks: [response],
      eof: true,
      stream_terminal_events: [],
      policy,
      observed_peer: policy.expected_peer,
    }).record;
    const bindings = {
      join,
      request_record_identity: plainIdentity(requestBytes),
      policy,
    };
    if (mutation === "EXTRA") {
      modules.transport.parseClosedTransportRecord(
        mutateJsonBytes(analyzed, (value) => { value.extra = true; }),
        bindings,
      );
      return;
    }
    if (mutation === "MISSING") {
      modules.transport.parseClosedTransportRecord(
        mutateJsonBytes(analyzed, (value) => { delete value.framing; }),
        bindings,
      );
      return;
    }
    modules.transport.parseClosedTransportRecord(
      duplicateTopLevelKeyBytes(analyzed, "schema_version"),
      bindings,
    );
    return;
  }
  if (recordType === "OBSERVER") {
    assert(
      typeof modules.observer.parseClosedObserverRecord === "function",
      "EVALUATOR_PRODUCTION_API_MISSING",
      "production kernel lacks parseClosedObserverRecord",
    );
    const fixture = replayObserverFixture();
    if (mutation === "EXTRA") {
      modules.observer.parseClosedObserverRecord(
        mutateJsonBytes(fixture.record, (value) => { value.extra = true; }),
        fixture.stdout,
        fixture.stderr,
        {
          join: fixture.join,
          request_record_identity: fixture.requestIdentity,
          policy: fixture.policy,
        },
      );
      return;
    }
    if (mutation === "MISSING") {
      modules.observer.parseClosedObserverRecord(
        mutateJsonBytes(fixture.record, (value) => { delete value.fd; }),
        fixture.stdout,
        fixture.stderr,
        {
          join: fixture.join,
          request_record_identity: fixture.requestIdentity,
          policy: fixture.policy,
        },
      );
      return;
    }
    modules.observer.parseClosedObserverRecord(
      duplicateTopLevelKeyBytes(fixture.record, "schema_version"),
      fixture.stdout,
      fixture.stderr,
      {
        join: fixture.join,
        request_record_identity: fixture.requestIdentity,
        policy: fixture.policy,
      },
    );
    return;
  }
  if (recordType === "JOIN" && mutation === "VALID") {
    modules.contract.validateJoin(join);
    return;
  }
  if (recordType === "JOIN" && mutation === "REQUEST_CELL_MISMATCH") {
    modules.contract.validateJoin(replayJoin({ cell_id: "" }));
    return;
  }
  if (recordType === "JOIN" && mutation === "TASK_MISMATCH") {
    modules.contract.validateJoin(replayJoin({ task_id: "WRONG-TASK" }));
    return;
  }
  if (recordType === "JOIN" && mutation === "PROFILE_MISMATCH") {
    modules.contract.validateJoin(replayJoin({ profile_id: "B9_Z" }));
    return;
  }
  if (recordType === "JOIN" && mutation === "REPETITION_MISMATCH") {
    modules.contract.validateJoin(replayJoin({ repetition_id: "" }));
    return;
  }
  if (recordType === "JOIN" && mutation === "REQUEST_RESPONSE_CROSS_BINDING") {
    modules.admission.parseClosedRequestRecord(requestBytes, {
      expected_join: replayJoin({ execution_id: "OTHER-EXECUTION" }),
    });
    return;
  }
  if (recordType === "JOIN" && mutation === "TRANSPORT_CROSS_BINDING") {
    const fixture = replayObserverFixture();
    modules.observer.validateRawObservation({
      record: fixture.record,
      stdout_bytes: fixture.stdout,
      stderr_bytes: fixture.stderr,
      join: replayJoin({ execution_id: "OTHER-EXECUTION" }),
      request_record_identity: fixture.requestIdentity,
      policy: fixture.policy,
    });
    return;
  }
  fail(
    "EVALUATOR_CASE_UNIMPLEMENTED",
    `closed replay missing ${recordType}/${mutation}`,
  );
}

function replayTransportCase(stimulus, modules) {
  exactKeys(
    stimulus.parameters,
    [
      "generator",
      "join",
      "join_source",
      "policy",
      "policy_source",
      "request_record_identity",
      "request_record_identity_source",
    ],
    "REQUEST_KEYSET_INVALID",
    "transport stimulus parameters",
  );
  const parameters = stimulus.parameters;
  const generator = parameters.generator;
  const join = modules.contract.validateJoin(parameters.join);
  const policy = modules.contract.validatePolicy(parameters.policy);
  const requestIdentity = modules.contract.validateIdentity(
    parameters.request_record_identity,
  );
  assert(
    generator === stimulus.variant
      && parameters.join_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && parameters.policy_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && parameters.request_record_identity_source
        === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE",
    "REQUEST_KEYSET_INVALID",
    "transport stimulus source plan drifted",
  );
  const valid = makeHttpResponse(Buffer.from("{}"), ["Content-Length: 2"]);
  const input = {
    join,
    request_record_identity: requestIdentity,
    chunks: [valid],
    eof: true,
    stream_terminal_events: [],
    policy,
    observed_peer: policy.expected_peer,
  };
  if (generator === "ZERO_BYTES") input.chunks = [];
  if (generator === "CAP_MINUS_ONE") {
    input.chunks = [makeExactLengthEofResponse(RESPONSE_BYTES_MAX - 1)];
  }
  if (generator === "CAP_EXACT") {
    input.chunks = [makeExactLengthEofResponse(RESPONSE_BYTES_MAX)];
  }
  if (generator === "CAP_PLUS_ONE") {
    input.chunks = [Buffer.alloc(RESPONSE_BYTES_MAX + 1, 0x61)];
  }
  if (generator === "MULTI_CHUNK") {
    input.chunks = [valid.subarray(0, 12), valid.subarray(12)];
  }
  if (generator === "INCOMPLETE_FRAMING") {
    input.chunks = [Buffer.from("HTTP/1.1 200 OK\r\nContent-Length: 2")];
  }
  if (generator === "TRUNCATED_BODY") {
    input.chunks = [makeHttpResponse(Buffer.from("{"), ["Content-Length: 2"])];
  }
  if (generator === "EARLY_CLOSE") input.eof = false;
  if (generator === "MISSING_TERMINAL") {
    input.chunks = [
      makeHttpResponse(Buffer.from("1\r\na\r\n"), ["Transfer-Encoding: chunked"]),
    ];
  }
  if (generator === "DUPLICATE_TERMINAL") {
    input.stream_terminal_events = [
      { kind: "APPLICATION_TERMINAL", offset: valid.length },
      { kind: "APPLICATION_TERMINAL", offset: valid.length },
    ];
  }
  if (generator === "POST_TERMINAL_BYTES") {
    input.stream_terminal_events = [
      { kind: "APPLICATION_TERMINAL", offset: valid.length - 1 },
    ];
  }
  if (generator === "CONTENT_LENGTH_MISMATCH") {
    input.chunks = [
      makeHttpResponse(
        Buffer.from("{}"),
        ["Content-Length: 2", "Content-Length: 2"],
      ),
    ];
  }
  if (generator === "MALFORMED_CHUNK_FRAMING") {
    input.chunks = [
      makeHttpResponse(
        Buffer.from("Z\r\na\r\n0\r\n\r\n"),
        ["Transfer-Encoding: chunked"],
      ),
    ];
  }
  modules.transport.analyzeTransport(input);
}

function replayObserverCase(stimulus, modules) {
  exactKeys(
    stimulus.parameters,
    [
      "join",
      "join_source",
      "mutation",
      "policy",
      "policy_source",
      "record",
      "record_source",
      "request_record_identity",
      "request_record_identity_source",
      "stderr_base64",
      "stderr_source",
      "stdout_base64",
      "stdout_source",
    ],
    "REQUEST_KEYSET_INVALID",
    "observer stimulus parameters",
  );
  const parameters = stimulus.parameters;
  assert(
    parameters.mutation === stimulus.variant
      && [
        "join_source",
        "policy_source",
        "record_source",
        "request_record_identity_source",
        "stderr_source",
        "stdout_source",
      ].every((key) => parameters[key] === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"),
    "REQUEST_KEYSET_INVALID",
    "observer stimulus source plan drifted",
  );
  let join = modules.contract.validateJoin(parameters.join);
  const requestIdentity = modules.contract.validateIdentity(
    parameters.request_record_identity,
  );
  let policy = modules.contract.validatePolicy(parameters.policy);
  let stdout = decodeCanonicalBase64(
    parameters.stdout_base64,
    "REQUEST_KEYSET_INVALID",
    "observer stimulus stdout",
  );
  let stderr = decodeCanonicalBase64(
    parameters.stderr_base64,
    "REQUEST_KEYSET_INVALID",
    "observer stimulus stderr",
  );
  const record = JSON.parse(JSON.stringify(parameters.record));
  const mutation = parameters.mutation;
  if (mutation === "MISSING") {
    modules.observer.validateRawObservation({
      record: null,
      stdout_bytes: stdout,
      stderr_bytes: stderr,
      join,
      request_record_identity: requestIdentity,
      policy,
    });
    return;
  }
  if (mutation === "FORGED") {
    record.observed_rows = [];
  }
  if (mutation === "NON_PASS") {
    record.exit_status = 1;
    record.status = "NON_PASS";
  }
  if (mutation === "WRONG_PID") record.pid += 1;
  if (mutation === "WRONG_FD") {
    record.fd = `${Number.parseInt(record.fd, 10) + 1}u`;
  }
  if (mutation === "WRONG_PORT") record.local = "127.0.0.1:50166";
  if (mutation === "WRONG_PEER") record.peer = "127.0.0.1:8788";
  if (mutation === "NON_LOOPBACK") {
    record.peer = "203.0.113.1:8787";
    record.policy.expected_peer = record.peer;
    policy = record.policy;
  }
  if (mutation === "CROSS_BINDING") {
    join = replayJoin({ execution_id: "OTHER-EXECUTION" });
  }
  if (mutation === "STDOUT_MUTATED") {
    stdout = Buffer.concat([stdout, Buffer.from("mutated\n")]);
  }
  if (mutation === "STDERR_MUTATED") {
    stderr = Buffer.from("mutated");
  }
  if (mutation === "COMMAND_MUTATED") record.command = ["/usr/bin/false"];
  if (mutation === "TIMESTAMP_ORDER_INVALID") {
    record.started_at = "2026-07-29T00:00:01.000Z";
    record.stopped_at = "2026-07-29T00:00:00.000Z";
  }
  modules.observer.validateRawObservation({
    record,
    stdout_bytes: stdout,
    stderr_bytes: stderr,
    join,
    request_record_identity: requestIdentity,
    policy,
  });
}

function replaySecretCase(stimulus, modules) {
  exactKeys(
    stimulus.parameters,
    ["embedding", "segment_sizes"],
    "REQUEST_KEYSET_INVALID",
    "secret stimulus parameters",
  );
  const { embedding, segment_sizes: segmentSizes } = stimulus.parameters;
  assert(
    embedding === stimulus.variant
      && Object.hasOwn(SECRET_SEGMENT_SIZES, embedding)
      && isDeepStrictEqual(segmentSizes, SECRET_SEGMENT_SIZES[embedding]),
    "REQUEST_KEYSET_INVALID",
    "secret stimulus embedding or exact segment sizes drifted",
  );
  const sentinel = Buffer.from(
    "P1-165-MATRIX-SECRET-SENTINEL-NEVER-PERSIST",
    "utf8",
  );
  let buffers = [Buffer.from("safe", "utf8")];
  if (embedding === "EXACT") buffers = [Buffer.from(sentinel)];
  if (embedding === "PREFIX") {
    buffers = [Buffer.concat([sentinel, Buffer.from("x")])];
  }
  if (embedding === "SUFFIX") {
    buffers = [Buffer.concat([Buffer.from("x"), sentinel])];
  }
  if (embedding === "CROSS_CHUNK") {
    buffers = [sentinel.subarray(0, 7), sentinel.subarray(7)];
  }
  if (embedding === "SPLIT_BOUNDARY") {
    buffers = [
      Buffer.concat([Buffer.from("x"), sentinel.subarray(0, 1)]),
      sentinel.subarray(1),
    ];
  }
  if (embedding === "BINARY") {
    buffers = [Buffer.concat([Buffer.from([0, 255]), sentinel])];
  }
  assert(
    isDeepStrictEqual(buffers.map((bytes) => bytes.length), segmentSizes),
    "REQUEST_KEYSET_INVALID",
    "secret stimulus materialization differs from frozen segment sizes",
  );
  modules.admission.assertNoSecretReflection(buffers, sentinel);
  sentinel.fill(0);
}

function replayUsageCase(expected, input, modules, expectedBinding) {
  const caseId = expected.case_id;
  const variant = input.stimulus.variant;
  const parameters = input.stimulus.parameters;
  exactKeys(
    parameters,
    [
      "full_spine_required",
      "join",
      "join_source",
      "output_tokens",
      "policy",
      "policy_source",
      "response_identity",
      "response_identity_source",
      "usage",
      "usage_state",
    ],
    "REQUEST_KEYSET_INVALID",
    `${caseId} usage stimulus parameters`,
  );
  const typedOutputBoundary = Object.hasOwn(expected, "output_tokens");
  const expectedUsageState = variant === "ABSENT_UNKNOWN"
    ? "UNKNOWN"
    : "OBSERVED";
  const expectedUsage = variant === "ABSENT_UNKNOWN"
    ? null
    : variant;
  assert(
    parameters.join_source === "MATRIX_CASE_MATERIAL"
      && parameters.response_identity_source === "MATRIX_CASE_MATERIAL"
      && parameters.policy_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && parameters.usage_state === expectedUsageState
      && parameters.usage === expectedUsage
      && (
        typedOutputBoundary
          ? (
            input.stimulus.variant === "OUTPUT_BOUNDARY"
          && Number.isSafeInteger(parameters.output_tokens)
          && parameters.output_tokens === expected.output_tokens
          && parameters.full_spine_required === expected.full_spine_required
          )
          : (
            parameters.output_tokens === null
            && parameters.full_spine_required === false
          )
      ),
    "REQUEST_KEYSET_INVALID",
    `${caseId} typed output usage stimulus drifted`,
  );
  const join = modules.contract.validateJoin(
    parameters.join,
    `${caseId} stimulus join`,
  );
  const responseIdentity = modules.contract.validateIdentity(
    parameters.response_identity,
    `${caseId} stimulus response identity`,
  );
  const policy = modules.contract.validatePolicy(
    parameters.policy,
    `${caseId} stimulus policy`,
  );
  assert(
    isDeepStrictEqual(join, expectedBinding.join)
      && isDeepStrictEqual(responseIdentity, expectedBinding.response_identity)
      && isDeepStrictEqual(policy, expectedBinding.policy),
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${caseId} usage stimulus is not bound to exact matrix material and calibration`,
  );
  let usage;
  if (variant === "ABSENT_UNKNOWN") {
    usage = modules.contract.unknownUsage({ join, responseIdentity });
  } else {
    const outputTokens = typedOutputBoundary ? parameters.output_tokens : 0;
    usage = modules.contract.observedUsage({
      join,
      responseIdentity,
      inputTokens: 1,
      outputTokens,
    });
  }
  if (variant === "PARTIAL") usage.output_tokens = null;
  if (variant === "NEGATIVE") usage.input_tokens = -1;
  if (variant === "NON_INTEGER") usage.input_tokens = 0.5;
  if (variant === "TOTAL_DRIFT") usage.total_tokens += 1;
  modules.contract.validateUsage(usage, {
    join,
    responseIdentity,
    policy,
  });
}

function writeFixtureCreateOnce(path, bytes) {
  let descriptor;
  try {
    descriptor = openSync(
      path,
      fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL,
      0o600,
    );
    writeFileSync(descriptor, bytes);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function createFixtureRoot(path) {
  assert(!existsSync(path), "ROOT_PREEXISTS", "fixture root already exists", path);
  mkdirSync(path, { mode: 0o700 });
  const stat = lstatSync(path);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assert(
    stat.isDirectory()
      && !stat.isSymbolicLink()
      && (uid === null || stat.uid === uid)
      && (stat.mode & 0o022) === 0,
    "EVIDENCE_ROOT_PERMISSIONS_INVALID",
    "fixture root is not exclusively owned",
    path,
  );
  return path;
}

function assertClosedFixtureInventory(actual, declared, mismatchCode) {
  const actualPaths = actual.map((entry) => entry.path);
  const declaredPaths = declared.map((entry) => entry.path);
  if (
    new Set(declaredPaths).size !== declaredPaths.length
    || !isDeepStrictEqual(declaredPaths, [...declaredPaths].sort())
  ) {
    fail(
      "ORDERED_IDENTITY_SET_INVALID",
      "fixture inventory is duplicated or not path-sorted",
    );
  }
  assert(
    isDeepStrictEqual(actual, declared),
    mismatchCode,
    "fixture inventory differs from evaluator-owned filesystem state",
  );
}

function replayFilesystemCase(caseId, stimulus) {
  exactKeys(
    stimulus.parameters,
    ["operation", "relative_path"],
    "REQUEST_KEYSET_INVALID",
    `${caseId} filesystem stimulus parameters`,
  );
  assert(
    stimulus.parameters.operation === stimulus.variant
      && FILESYSTEM_RELATIVE_PATHS[stimulus.parameters.operation]
        === stimulus.parameters.relative_path,
    "REQUEST_KEYSET_INVALID",
    `${caseId} filesystem stimulus is not exact`,
  );
  const operation = stimulus.parameters.operation;
  const relativePath = stimulus.parameters.relative_path;
  const temporaryParent = mkdtempSync(
    join(tmpdir(), "sourcelens-p1-165-quality-"),
  );
  const fixtureRoot = join(temporaryParent, "root");
  try {
    if (operation === "ROOT_PREEXISTS") {
      mkdirSync(fixtureRoot, { mode: 0o700 });
      createFixtureRoot(fixtureRoot);
      return;
    }

    createFixtureRoot(fixtureRoot);
    if (operation === "OWNED_ROOT_VALID") {
      writeFixtureCreateOnce(
        join(fixtureRoot, relativePath),
        Buffer.from("accepted"),
      );
      const identity = readSecureFile(
        fixtureRoot,
        relativePath,
        "owned fixture admitted response",
      ).identity;
      assertClosedFixtureInventory(listClosedFiles(fixtureRoot), [identity], "CLOSED_INVENTORY_DRIFT");
      return;
    }
    if (operation === "PATH_ESCAPE") {
      containedPath(fixtureRoot, relativePath, "evaluator-owned path escape fixture");
      return;
    }
    if (operation === "SYMLINK") {
      const target = join(temporaryParent, "symlink-target.bin");
      writeFixtureCreateOnce(target, Buffer.from("target"));
      symlinkSync(target, join(fixtureRoot, relativePath));
      readSecureFile(fixtureRoot, relativePath, "symlink fixture");
      return;
    }
    if (operation === "HARDLINK") {
      writeFixtureCreateOnce(join(fixtureRoot, "source.bin"), Buffer.from("source"));
      linkSync(join(fixtureRoot, "source.bin"), join(fixtureRoot, relativePath));
      readSecureFile(fixtureRoot, relativePath, "hardlink fixture");
      return;
    }
    if (operation === "CREATE_ONCE") {
      const target = join(fixtureRoot, relativePath);
      writeFixtureCreateOnce(target, Buffer.from("first"));
      try {
        writeFixtureCreateOnce(target, Buffer.from("second"));
      } catch (error) {
        if (error?.code === "EEXIST") {
          fail("CREATE_ONCE_FAILED", "second create-once filesystem write was rejected");
        }
        throw error;
      }
      fail("CREATE_ONCE_FAILED", "second create-once filesystem write unexpectedly succeeded");
    }
    if (operation === "IDENTITY_MISSING") {
      const target = join(fixtureRoot, relativePath);
      assert(existsSync(target), "PATH_MISSING", "fixture identity target is absent", target);
      return;
    }
    if (operation === "IDENTITY_MUTATION") {
      const target = join(fixtureRoot, relativePath);
      writeFixtureCreateOnce(target, Buffer.from("before"));
      const before = readSecureFile(fixtureRoot, "artifact.bin", "identity fixture before").identity;
      writeFileSync(target, Buffer.from("after-mutation"));
      const after = readSecureFile(fixtureRoot, "artifact.bin", "identity fixture after").identity;
      assert(
        isDeepStrictEqual(before, after),
        "IDENTITY_MISMATCH",
        "evaluator-owned fixture identity changed",
        target,
      );
      return;
    }
    if (operation === "NON_REGULAR_FILE") {
      mkdirSync(join(fixtureRoot, relativePath), { mode: 0o700 });
      readSecureFile(fixtureRoot, relativePath, "non-regular fixture");
      return;
    }
    if (
      operation === "INVENTORY_MISSING"
      || operation === "INVENTORY_EXTRA"
      || operation === "INVENTORY_REORDER"
      || operation === "INVENTORY_DUPLICATE"
      || operation === "INVENTORY_CROSS_BINDING"
    ) {
      const inventoryRoot = join(fixtureRoot, relativePath);
      mkdirSync(inventoryRoot, { mode: 0o700 });
      writeFixtureCreateOnce(join(inventoryRoot, "a.bin"), Buffer.from("a"));
      writeFixtureCreateOnce(join(inventoryRoot, "b.bin"), Buffer.from("b"));
      const actual = listClosedFiles(fixtureRoot);
      let declared = actual.map((entry) => ({ ...entry }));
      let mismatchCode = "CLOSED_INVENTORY_DRIFT";
      if (operation === "INVENTORY_MISSING") declared = declared.slice(0, 1);
      if (operation === "INVENTORY_EXTRA") {
        declared.push({
          path: `${relativePath}/c.bin`,
          type: "REGULAR_FILE",
          nlink: 1,
          byte_length: 1,
          sha256: sha256(Buffer.from("c")),
        });
      }
      if (operation === "INVENTORY_REORDER") declared.reverse();
      if (operation === "INVENTORY_DUPLICATE") declared = [declared[0], declared[0]];
      if (operation === "INVENTORY_CROSS_BINDING") {
        declared[0] = { ...declared[0], sha256: declared[1].sha256 };
        mismatchCode = "EVIDENCE_CROSS_BINDING_INVALID";
      }
      assertClosedFixtureInventory(actual, declared, mismatchCode);
      return;
    }
    if (operation === "EVIDENCE_WRITE_FAILURE") {
      const blocker = join(fixtureRoot, dirname(relativePath));
      writeFixtureCreateOnce(blocker, Buffer.from("blocker"));
      try {
        writeFixtureCreateOnce(
          join(fixtureRoot, relativePath),
          Buffer.from("write"),
        );
      } catch (error) {
        if (["ENOTDIR", "EACCES", "EPERM", "EROFS"].includes(error?.code)) {
          fail("EVIDENCE_WRITE_FAILED", "evaluator-owned Evidence write failed closed");
        }
        throw error;
      }
      fail("EVIDENCE_WRITE_FAILED", "fixture Evidence write unexpectedly succeeded");
    }
    fail(
      "REQUEST_KEYSET_INVALID",
      `unknown evaluator-owned filesystem operation ${operation}`,
    );
  } finally {
    rmSync(temporaryParent, { force: true, recursive: true });
  }
}

async function loadProductionKernel() {
  const [
    contract,
    admission,
    transport,
    observer,
    preflight,
    acceptedInputs,
  ] = await Promise.all([
    import("../../harness/p1-165-fail-closed-response-admission/contract.mjs"),
    import("../../harness/p1-165-fail-closed-response-admission/admission.mjs"),
    import("../../harness/p1-165-fail-closed-response-admission/transport.mjs"),
    import("../../harness/p1-165-fail-closed-response-admission/observer.mjs"),
    import("../../harness/p1-165-fail-closed-response-admission/preflight.mjs"),
    import("../../harness/p1-149-accepted-execution-spine/accepted-inputs.mjs"),
  ]);
  return {
    contract,
    admission,
    transport,
    observer,
    preflight,
    acceptedInputs,
  };
}

function expectedUsageResponseIdentity(expected, modules) {
  const responseBytes = expected.full_spine_required === true
    ? modules.acceptedInputs.buildAcceptedReferenceResponse(
        ACCEPTED_TASK_IDS[0],
        "P1-165-MATRIX-USAGE-OUTPUT-2048",
      ).response_bytes
    : Buffer.from("{}\n", "utf8");
  return plainIdentity(responseBytes);
}

function expectedUsageBinding(expected, modules, persistenceBinding = null) {
  const binding = persistenceBinding ?? {
    response_identity: expectedUsageResponseIdentity(expected, modules),
    policy: replayPolicy(),
  };
  return {
    join: expectedMatrixCaseJoin(expected.case_id),
    response_identity: binding.response_identity,
    policy: binding.policy,
  };
}

function materializeExpectedStimulus(
  expected,
  syntheticObserverFixture,
  modules,
  persistenceBinding = null,
) {
  const plan = validateMatrixStimulusPlan(expected);
  if (plan.kind === "TRANSPORT") {
    return {
      ...plan,
      parameters: {
        ...plan.parameters,
        join: syntheticObserverFixture.record.join,
        request_record_identity:
          syntheticObserverFixture.record.request_record_identity,
        policy: syntheticObserverFixture.record.policy,
      },
    };
  }
  if (plan.kind === "OBSERVER") {
    return {
      ...plan,
      parameters: {
        ...plan.parameters,
        join: syntheticObserverFixture.record.join,
        request_record_identity:
          syntheticObserverFixture.record.request_record_identity,
        policy: syntheticObserverFixture.record.policy,
        record: syntheticObserverFixture.record,
        stdout_base64: syntheticObserverFixture.stdout.toString("base64"),
        stderr_base64: syntheticObserverFixture.stderr.toString("base64"),
      },
    };
  }
  if (plan.kind === "USAGE") {
    const binding = expectedUsageBinding(
      expected,
      modules,
      persistenceBinding,
    );
    return {
      ...plan,
      parameters: {
        ...plan.parameters,
        join: binding.join,
        response_identity: binding.response_identity,
        policy: binding.policy,
      },
    };
  }
  return plan;
}

async function independentlyReplayCase(
  expected,
  input,
  modules,
  persistenceBinding = null,
  syntheticObserverFixture = null,
) {
  exactKeys(
    input.stimulus,
    ["kind", "variant", "parameters"],
    "CASE_INPUT_INVALID",
    "matrix case stimulus",
  );
  const expectedKind = CATEGORY_STIMULUS_KIND[expected.category_id];
  const exactStimulus = materializeExpectedStimulus(
    expected,
    syntheticObserverFixture,
    modules,
    persistenceBinding,
  );
  assert(
    input.stimulus.kind === expectedKind
      && isDeepStrictEqual(input.stimulus, exactStimulus)
      && input.stimulus.parameters !== null
      && typeof input.stimulus.parameters === "object"
      && !Array.isArray(input.stimulus.parameters),
    "CASE_INPUT_INVALID",
    `case ${expected.case_id} stimulus identity invalid`,
    null,
    expected.case_id,
  );
  let observedStatus = "PASS";
  let observedReason = "PASS";
  try {
    if (expectedKind === "CLOSED_RECORD") {
      replayClosedCase(input.stimulus, modules);
    } else if (expectedKind === "TRANSPORT") {
      replayTransportCase(input.stimulus, modules);
    } else if (expectedKind === "OBSERVER") {
      replayObserverCase(input.stimulus, modules);
    } else if (expectedKind === "SECRET") {
      replaySecretCase(input.stimulus, modules);
    } else if (expectedKind === "FILESYSTEM") {
      replayFilesystemCase(expected.case_id, input.stimulus);
    } else if (expectedKind === "USAGE") {
      replayUsageCase(
        expected,
        input,
        modules,
        expectedUsageBinding(expected, modules, persistenceBinding),
      );
    } else {
      assert(
        typeof modules.preflight?.replayIndependentStimulus === "function",
        "EVALUATOR_PRODUCTION_API_MISSING",
        `production kernel lacks independent ${expectedKind} replay API`,
      );
      await modules.preflight.replayIndependentStimulus(input.stimulus, {
        evaluator_owned: true,
      });
    }
  } catch (error) {
    if (
      error instanceof modules.contract.AdmissionNonPass
      || error instanceof EvaluationFailure
    ) {
      observedStatus = "NON_PASS";
      observedReason = error.code;
    } else {
      throw error;
    }
  }
  assert(
    observedStatus === expected.expected_status
      && observedReason === expected.expected_reason_code,
    "INDEPENDENT_CASE_REEXECUTION_MISMATCH",
    `case ${expected.case_id} independently produced ${observedStatus}/${observedReason}`,
    null,
    expected.case_id,
  );
}

function expectedMatrixCaseJoin(caseId) {
  return {
    execution_id: `P1-165-MATRIX-${caseId}`,
    cell_id: caseId,
    task_id: TASK_ID,
    profile_id: "B0_A",
    repetition_id: "A",
  };
}

function validateMatrixSyntheticObserverFixture(
  root,
  manifestState,
  input,
  inputPath,
  modules,
) {
  exactKeys(
    input.synthetic_observer_fixture,
    FROZEN_SYNTHETIC_OBSERVER_FIXTURE_KEYS,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "matrix synthetic observer fixture",
    inputPath,
  );
  const recordPath = "raw/observer/calibration/observation.json";
  const stdoutPath = "raw/observer/calibration/stdout.log";
  const stderrPath = "raw/observer/calibration/stderr.log";
  const descriptorPath = "raw/observer/calibration/synthetic-fixture.json";
  const record = readBoundJson(
    root,
    manifestState,
    recordPath,
    "frozen synthetic observer fixture",
  );
  const stdout = readBoundBytes(
    root,
    manifestState,
    stdoutPath,
    "frozen synthetic observer fixture stdout",
  ).bytes;
  const stderr = readBoundBytes(
    root,
    manifestState,
    stderrPath,
    "frozen synthetic observer fixture stderr",
  ).bytes;
  const descriptor = readBoundJson(
    root,
    manifestState,
    descriptorPath,
    "frozen synthetic observer fixture descriptor",
  );
  exactKeys(
    descriptor,
    SYNTHETIC_OBSERVER_DESCRIPTOR_KEYS,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "matrix synthetic observer fixture descriptor",
    descriptorPath,
  );
  const encodedStdout = decodeCanonicalBase64(
    input.synthetic_observer_fixture.stdout_base64,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "matrix synthetic observer fixture stdout",
    inputPath,
  );
  const encodedStderr = decodeCanonicalBase64(
    input.synthetic_observer_fixture.stderr_base64,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "matrix synthetic observer fixture stderr",
    inputPath,
  );
  assert(
    isDeepStrictEqual(input.synthetic_observer_fixture.record, record)
      && isDeepStrictEqual(
        input.synthetic_observer_fixture.descriptor,
        descriptor,
      )
      && encodedStdout.equals(stdout)
      && encodedStderr.equals(stderr)
      && descriptor.schema_version
        === "p1-168-frozen-synthetic-observer-fixture/v1"
      && descriptor.task_id === TASK_ID
      && descriptor.fixture_index === 1
      && descriptor.source_kind === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && descriptor.command_executed === false
      && descriptor.live_network_connection_created === false
      && descriptor.live_network_connections_created === 0
      && descriptor.live_loopback_calibration === "DEFERRED_TO_P1_169"
      && descriptor.production_record_schema
        === "p1-165-os-network-observation/v1"
      && descriptor.status === "PASS_SYNTHETIC_FIXTURE_ONLY"
      && isDeepStrictEqual(
        descriptor.production_record_identity,
        plainIdentity(canonicalBytes(record)),
      )
      && isDeepStrictEqual(descriptor.stdout_identity, plainIdentity(stdout))
      && isDeepStrictEqual(descriptor.stderr_identity, plainIdentity(stderr))
      && record.schema_version === "p1-165-os-network-observation/v1"
      && record.exit_status === 0
      && record.status === "PASS"
      && record.pid === 420001
      && record.fd === "11u"
      && record.local === "127.0.0.1:48001"
      && record.peer === "127.0.0.1:47001"
      && record.policy?.mode === "OWNED_CALIBRATION"
      && record.started_at === "1970-01-01T00:00:00.000Z"
      && record.stopped_at === "1970-01-01T00:00:00.000Z"
      && record.stdout_path === stdoutPath
      && record.stderr_path === stderrPath,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "matrix synthetic observer fixture is not the exact deterministic fixture",
    inputPath,
  );
  const reconstructedRows = parseLsofRows(stdout);
  assert(
    isDeepStrictEqual(record.observed_rows, reconstructedRows)
      && reconstructedRows.length === 1,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "matrix synthetic observer rows do not reconstruct from raw fixture bytes",
    stdoutPath,
  );
  modules.observer.validateRawObservation({
    record,
    stdout_bytes: stdout,
    stderr_bytes: stderr,
    join: record.join,
    request_record_identity: record.request_record_identity,
    policy: record.policy,
  });
  return { descriptor, record, stdout, stderr };
}

function validateMatrixCasePersistence(
  root,
  manifestState,
  expected,
  modules,
  syntheticObserverFixture,
) {
  const base = `raw/cases/${expected.case_id}`;
  const observedPaths = manifestState.manifest.entries
    .filter((identity) => identity.path.startsWith(`${base}/`))
    .map((identity) => identity.path);
  if (expected.expected_persistence === "NONE") {
    const failurePath = `${base}/safe-failure-receipt.json`;
    assert(
      isDeepStrictEqual(observedPaths, [failurePath]),
      "UNSAFE_PERSISTENCE",
      `case ${expected.case_id} NON_PASS inventory is not failure-only`,
      base,
      expected.case_id,
    );
    const receipt = readBoundJson(
      root,
      manifestState,
      failurePath,
      `${expected.case_id} safe failure receipt`,
    );
    exactKeys(
      receipt,
      SAFE_FAILURE_RECEIPT_KEYS,
      "SAFE_FAILURE_RECEIPT_INVALID",
      `${expected.case_id} safe failure receipt`,
      failurePath,
    );
    assert(
      receipt.schema_version === "p1-165-safe-failure-receipt/v1"
        && receipt.task_id === TASK_ID
        && isDeepStrictEqual(receipt.join, expectedMatrixCaseJoin(expected.case_id))
        && receipt.status === "NON_PASS"
        && receipt.reason_code === expected.expected_reason_code
        && receipt.response_persisted === false
        && receipt.secret_persisted === false
        && receipt.message === "response admission failed closed before persistence",
      "SAFE_FAILURE_RECEIPT_INVALID",
      `case ${expected.case_id} safe failure receipt drifted`,
      failurePath,
      expected.case_id,
    );
    scanForbiddenEvidenceFields(receipt, failurePath);
    return {
      state: "SAFE_FAILURE",
      policy: syntheticObserverFixture.record.policy,
      response_identity: expected.category_id === "USAGE_CONTRACT"
        ? expectedUsageResponseIdentity(expected, modules)
        : null,
    };
  }

  const paths = {
    admitted: `${base}/admission/admitted-response.http`,
    receipt: `${base}/admission/admission-receipt.json`,
    context: `${base}/supporting/context.json`,
    observer_record: `${base}/supporting/observer.json`,
    observer_stderr: `${base}/supporting/observer-stderr.log`,
    observer_stdout: `${base}/supporting/observer-stdout.log`,
    request_body: `${base}/supporting/request.raw`,
    request_record: `${base}/supporting/request-record.json`,
    transport_record: `${base}/supporting/transport-record.json`,
    usage_record: `${base}/supporting/usage.json`,
  };
  const expectedPaths = [
    ...Object.values(paths),
  ].sort();
  if (expected.full_spine_required === true) {
    expectedPaths.push(
      `${base}/cell-closure.json`,
      ...SPINE_ARTIFACTS.map((name) => `${base}/spine/${name}`),
    );
    expectedPaths.sort();
  }
  assert(
    isDeepStrictEqual(observedPaths, expectedPaths),
    "EXPECTED_ADMISSION_MISSING",
    `case ${expected.case_id} admitted inventory is not exact`,
    base,
    expected.case_id,
  );
  const joinValue = expectedMatrixCaseJoin(expected.case_id);
  const contextArtifact = readBoundBytes(
    root,
    manifestState,
    paths.context,
    `${expected.case_id} context`,
  );
  const requestBodyArtifact = readBoundBytes(
    root,
    manifestState,
    paths.request_body,
    `${expected.case_id} request body`,
  );
  const requestArtifact = readBoundBytes(
    root,
    manifestState,
    paths.request_record,
    `${expected.case_id} request record`,
  );
  const transportArtifact = readBoundBytes(
    root,
    manifestState,
    paths.transport_record,
    `${expected.case_id} transport record`,
  );
  const observerArtifact = readBoundBytes(
    root,
    manifestState,
    paths.observer_record,
    `${expected.case_id} observer record`,
  );
  const observerStdout = readBoundBytes(
    root,
    manifestState,
    paths.observer_stdout,
    `${expected.case_id} observer stdout`,
  );
  const observerStderr = readBoundBytes(
    root,
    manifestState,
    paths.observer_stderr,
    `${expected.case_id} observer stderr`,
  );
  const usage = readBoundJson(
    root,
    manifestState,
    paths.usage_record,
    `${expected.case_id} usage`,
  );
  const admitted = readBoundBytes(
    root,
    manifestState,
    paths.admitted,
    `${expected.case_id} admitted response`,
  );
  const context = modules.admission.parseClosedContextRecord(
    contextArtifact.bytes,
    { expected_join: joinValue },
  ).value;
  const request = modules.admission.parseClosedRequestRecord(
    requestArtifact.bytes,
    {
      expected_join: joinValue,
      expected_context_identity: bytesIdentityFromBound(contextArtifact.identity),
    },
  ).value;
  const transport = modules.transport.parseClosedTransportRecord(
    transportArtifact.bytes,
    {
      join: joinValue,
      request_record_identity: bytesIdentityFromBound(requestArtifact.identity),
      policy: request.policy,
    },
  );
  const observer = modules.observer.parseClosedObserverRecord(
    observerArtifact.bytes,
    observerStdout.bytes,
    observerStderr.bytes,
    {
      join: joinValue,
      request_record_identity: bytesIdentityFromBound(requestArtifact.identity),
      policy: request.policy,
    },
  );
  assert(
    observerStdout.bytes.equals(syntheticObserverFixture.stdout)
      && observerStderr.bytes.equals(syntheticObserverFixture.stderr)
      && isDeepStrictEqual(request.policy, syntheticObserverFixture.record.policy)
      && isDeepStrictEqual(observer.policy, syntheticObserverFixture.record.policy)
      && observer.pid === syntheticObserverFixture.record.pid
      && observer.fd === syntheticObserverFixture.record.fd
      && observer.local === syntheticObserverFixture.record.local
      && observer.peer === syntheticObserverFixture.record.peer
      && isDeepStrictEqual(observer.command, syntheticObserverFixture.record.command)
      && isDeepStrictEqual(
        observer.observed_rows,
        syntheticObserverFixture.record.observed_rows,
      )
      && observer.started_at === syntheticObserverFixture.record.started_at
      && observer.stopped_at === syntheticObserverFixture.record.stopped_at
      && observer.exit_status === syntheticObserverFixture.record.exit_status
      && observer.status === syntheticObserverFixture.record.status,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    `case ${expected.case_id} admission observer is not the frozen synthetic fixture`,
    paths.observer_record,
    expected.case_id,
  );
  const validatedUsage = modules.contract.validateUsage(
    usage,
    {
      join: joinValue,
      responseIdentity: transport.body_identity,
      policy: request.policy,
    },
    `${expected.case_id} usage`,
  );
  validateBytesIdentity(
    request.request_body_identity,
    bytesIdentityFromBound(requestBodyArtifact.identity),
    `${expected.case_id} request body identity`,
    paths.request_record,
  );
  validateBytesIdentity(
    transport.raw_response_identity,
    bytesIdentityFromBound(admitted.identity),
    `${expected.case_id} admitted raw response identity`,
    paths.transport_record,
  );
  const receipt = readBoundJson(
    root,
    manifestState,
    paths.receipt,
    `${expected.case_id} admission receipt`,
  );
  exactKeys(
    receipt,
    ADMISSION_RECEIPT_KEYS,
    "ADMISSION_RECEIPT_INVALID",
    `${expected.case_id} admission receipt`,
    paths.receipt,
  );
  assert(
    receipt.schema_version === "p1-165-admission-receipt/v1"
      && receipt.task_id === TASK_ID
      && receipt.status === "ADMITTED"
      && isDeepStrictEqual(receipt.join, joinValue),
    "ADMISSION_RECEIPT_INVALID",
    `case ${expected.case_id} admission receipt fixed fields drifted`,
    paths.receipt,
    expected.case_id,
  );
  const bound = {
    context_record_identity: contextArtifact.identity,
    request_body_identity: requestBodyArtifact.identity,
    request_record_identity: requestArtifact.identity,
    transport_record_identity: transportArtifact.identity,
    observer_record_identity: observerArtifact.identity,
    usage_record_identity: manifestState.byPath.get(paths.usage_record),
  };
  for (const [key, identity] of Object.entries(bound)) {
    validateBytesIdentity(
      receipt[key],
      bytesIdentityFromBound(identity),
      `${expected.case_id} receipt ${key}`,
      paths.receipt,
    );
  }
  validateArtifactDescriptor(
    receipt.admitted_response,
    paths.admitted,
    manifestState,
    `${expected.case_id} receipt admitted response`,
    paths.receipt,
  );
  validateBytesIdentity(
    receipt.body_identity,
    transport.body_identity,
    `${expected.case_id} receipt body identity`,
    paths.receipt,
  );
  exactKeys(
    receipt.supporting_artifacts,
    SUPPORTING_ARTIFACT_KEYS,
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${expected.case_id} supporting artifacts`,
    paths.receipt,
  );
  const supportPathByKey = {
    context_record: paths.context,
    observer_record: paths.observer_record,
    observer_stderr: paths.observer_stderr,
    observer_stdout: paths.observer_stdout,
    request_body: paths.request_body,
    request_record: paths.request_record,
    transport_record: paths.transport_record,
    usage_record: paths.usage_record,
  };
  for (const key of SUPPORTING_ARTIFACT_KEYS) {
    validateArtifactDescriptor(
      receipt.supporting_artifacts[key],
      supportPathByKey[key],
      manifestState,
      `${expected.case_id} supporting ${key}`,
      paths.receipt,
    );
  }
  assert(
    isDeepStrictEqual(validatedUsage, usage)
      && observer.status === "PASS"
      && context.task_id === TASK_ID,
    "ADMISSION_RECEIPT_INVALID",
    `case ${expected.case_id} admitted production record validation drifted`,
    paths.receipt,
  );
  if (expected.full_spine_required === true) {
    const admissionState = validateProductionAdmissionReceipt({
      base,
      artifactPaths: paths,
      joinRecord: joinValue,
      manifestState,
      receipt,
      requestRecord: request,
      contextRecord: context,
      transportRecord: transport,
      observerRecord: observer,
      usageRecord: validatedUsage,
      admitted,
    });
    const closurePath = `${base}/cell-closure.json`;
    const closure = readBoundJson(
      root,
      manifestState,
      closurePath,
      `${expected.case_id} full-spine closure`,
    );
    const spine = validateSpineRaw(
      root,
      manifestState,
      `${base}/spine`,
      "P1-165-MATRIX-USAGE-OUTPUT-2048",
      ACCEPTED_TASK_IDS[0],
    );
    validateProductionCellClosure({
      base,
      joinRecord: joinValue,
      manifestState,
      closure,
      admissionState,
      admitted,
      requestRecordIdentity: bytesIdentityFromBound(requestArtifact.identity),
      spine,
      adapterDescriptor: context.adapter_result_identity,
      b2ScanDescriptor: null,
    });
  }
  return {
    state: "ADMISSION",
    policy: request.policy,
    response_identity: transport.body_identity,
  };
}

async function validateCases(
  root,
  manifestState,
  matrixState,
  kernelContract,
  atomicCommit,
) {
  const expectedOrder = matrixState.cases.map((entry) => entry.case_id);
  assert(
    isDeepStrictEqual(kernelContract.case_order, expectedOrder),
    "CASE_SET_INVALID",
    "kernel contract case order differs from exact quality matrix",
    KERNEL_CONTRACT_PATH,
  );
  const caseDirectories = readdirSync(
    containedPath(root, "raw/matrix-process", "matrix process root"),
  )
    .sort();
  assert(
    isDeepStrictEqual(caseDirectories, [...expectedOrder].sort()),
    "CASE_SET_INVALID",
    "raw matrix process set differs from exact quality matrix",
    "raw/matrix-process",
  );
  const productionDirectories = readdirSync(
    containedPath(root, "raw/cases", "matrix production decision root"),
  ).sort();
  assert(
    isDeepStrictEqual(productionDirectories, [...expectedOrder].sort()),
    "CASE_SET_INVALID",
    "raw matrix production decision set differs from exact quality matrix",
    "raw/cases",
  );
  let casesPassed = 0;
  let productionAdmissions = 0;
  let safeFailureReceipts = 0;
  let falseAccepts = 0;
  let unsafePersistence = 0;
  const usageBoundaries = {
    "2047": "MISSING",
    "2048": "MISSING",
    "2049": "MISSING",
  };
  let unknownPreserved = false;
  let independentCaseReexecutions = 0;
  let sharedSyntheticObserverFixture = null;
  const productionModules = await loadProductionKernel();
  const expectedChildEnvironment =
    productionModules.contract.closedChildEnvironment();
  try {
    productionModules.preflight = await import(
      "../../harness/p1-165-fail-closed-response-admission/preflight.mjs"
    );
  } catch (error) {
    if (error?.code !== "ERR_MODULE_NOT_FOUND") throw error;
    productionModules.preflight = null;
  }
  for (const expected of matrixState.cases) {
    const base = `raw/matrix-process/${expected.case_id}`;
    const productionBase = `raw/cases/${expected.case_id}`;
    const inputPath = `${base}/input.json`;
    const observationPath = `${base}/observation.json`;
    const input = readBoundJson(root, manifestState, inputPath, `${expected.case_id} input`);
    const observation = readBoundJson(
      root,
      manifestState,
      observationPath,
      `${expected.case_id} observation`,
    );
    exactKeys(
      input,
      CASE_INPUT_KEYS,
      "CASE_INPUT_INVALID",
      "matrix case input",
      inputPath,
    );
    exactKeys(
      observation,
      CASE_OBSERVATION_KEYS,
      "CASE_OBSERVATION_INVALID",
      "matrix case observation",
      observationPath,
    );
    assert(
      input.schema_version === CASE_INPUT_SCHEMA
        && input.task_id === TASK_ID
        && input.case_id === expected.case_id
        && input.category_id === expected.category_id,
      "CASE_INPUT_INVALID",
      `case ${expected.case_id} input identity drifted`,
      inputPath,
      expected.case_id,
    );
    assert(
      observation.schema_version === CASE_OBSERVATION_SCHEMA
        && observation.task_id === TASK_ID
        && observation.case_id === expected.case_id
        && observation.status === expected.expected_status
        && observation.reason_code === expected.expected_reason_code
        && observation.persistence === expected.expected_persistence,
      "CASE_OBSERVATION_INVALID",
      `case ${expected.case_id} observed decision differs from matrix`,
      observationPath,
      expected.case_id,
    );
    assertFalseEffects(
      observation.external_effects,
      `${expected.case_id} external effects`,
      observationPath,
    );
    const syntheticObserverFixture = validateMatrixSyntheticObserverFixture(
      root,
      manifestState,
      input,
      inputPath,
      productionModules,
    );
    if (sharedSyntheticObserverFixture === null) {
      sharedSyntheticObserverFixture = syntheticObserverFixture;
    } else {
      assert(
        isDeepStrictEqual(
          sharedSyntheticObserverFixture.record,
          syntheticObserverFixture.record,
        )
          && isDeepStrictEqual(
            sharedSyntheticObserverFixture.descriptor,
            syntheticObserverFixture.descriptor,
          )
          && sharedSyntheticObserverFixture.stdout.equals(
            syntheticObserverFixture.stdout,
          )
          && sharedSyntheticObserverFixture.stderr.equals(
            syntheticObserverFixture.stderr,
          ),
        "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
        "matrix cases do not share one exact owned synthetic observer fixture",
        inputPath,
        expected.case_id,
      );
    }
    assert(
      Array.isArray(observation.identities),
      "CASE_OBSERVATION_INVALID",
      `case ${expected.case_id} identities missing`,
      observationPath,
      expected.case_id,
    );
    const identityPaths = observation.identities.map((identity, index) =>
      validateBoundIdentity(identity, manifestState, `${expected.case_id} identity ${index}`));
    assert(
      new Set(identityPaths.map((identity) => identity.path)).size === identityPaths.length
        && isDeepStrictEqual(
          identityPaths.map((identity) => identity.path),
          identityPaths.map((identity) => identity.path).sort(),
        ),
      "ORDERED_IDENTITY_SET_INVALID",
      `case ${expected.case_id} identities are duplicated or not path-sorted`,
      observationPath,
      expected.case_id,
    );
    const expectedCaseIdentities = manifestState.manifest.entries.filter(
      (identity) =>
        identity.path.startsWith(`${base}/`)
        && identity.path !== observationPath,
    );
    assert(
      isDeepStrictEqual(identityPaths, expectedCaseIdentities),
      "CLOSED_INVENTORY_DRIFT",
      `case ${expected.case_id} observation does not close its case inventory`,
      observationPath,
      expected.case_id,
    );
    validateCaseProcess(
      root,
      manifestState,
      observation.process,
      expected,
      atomicCommit,
      expectedChildEnvironment,
    );
    validatePropagationStimulus(input.stimulus, expected);
    const persistenceState = validateMatrixCasePersistence(
      root,
      manifestState,
      expected,
      productionModules,
      syntheticObserverFixture,
    );
    await independentlyReplayCase(
      expected,
      input,
      productionModules,
      persistenceState,
      syntheticObserverFixture,
    );
    independentCaseReexecutions += 1;
    if (persistenceState.state === "ADMISSION") productionAdmissions += 1;
    if (persistenceState.state === "SAFE_FAILURE") safeFailureReceipts += 1;
    scanForbiddenEvidenceFields(input, inputPath);
    scanForbiddenEvidenceFields(observation, observationPath);
    const retainedAdmission = manifestState.manifest.entries
      .filter((identity) => identity.path.startsWith(`${productionBase}/`))
      .some((identity) =>
      /(?:^|\/)(?:admitted-response|durable-response)(?:\.|\/)/.test(identity.path));
    if (expected.expected_persistence === "NONE" && retainedAdmission) {
      unsafePersistence += 1;
      fail(
        "UNSAFE_PERSISTENCE",
        `case ${expected.case_id} retained a rejected response`,
        observationPath,
        expected.case_id,
      );
    }
    assert(
      expected.expected_persistence !== "ADMITTED" || retainedAdmission,
      "EXPECTED_ADMISSION_MISSING",
      `case ${expected.case_id} did not retain its admitted synthetic response`,
      observationPath,
      expected.case_id,
    );
    if (
      expected.expected_status === "NON_PASS"
      && observation.status === "PASS"
    ) {
      falseAccepts += 1;
    }
    if (expected.case_id === "USAGE_ABSENT_UNKNOWN") {
      unknownPreserved =
        input.stimulus?.parameters?.usage_state === "UNKNOWN"
        && input.stimulus?.parameters?.usage === null;
    }
    if (Number.isSafeInteger(expected.output_tokens)) {
      usageBoundaries[String(expected.output_tokens)] =
        observation.status === "PASS" ? "ACCEPTED" : "REJECTED";
    }
    casesPassed += 1;
  }
  assert(falseAccepts === 0, "FALSE_ACCEPT", "negative matrix contains false accept");
  assert(unsafePersistence === 0, "UNSAFE_PERSISTENCE", "negative matrix retained unsafe response");
  assert(
    productionAdmissions === 14 && safeFailureReceipts === 85,
    "CASE_PERSISTENCE_ACCOUNTING_INVALID",
    "matrix production admission/safe-failure receipt accounting is not 14/85",
  );
  assert(
    unknownPreserved
      && usageBoundaries["2047"] === "ACCEPTED"
      && usageBoundaries["2048"] === "ACCEPTED"
      && usageBoundaries["2049"] === "REJECTED",
    "USAGE_BOUNDARY_INVALID",
    "usage UNKNOWN or 2047/2048/2049 boundary drifted",
  );
  return {
    cases_observed: casesPassed,
    cases_passed: casesPassed,
    false_accepts: falseAccepts,
    unsafe_persistence: unsafePersistence,
    usage: {
      unknown_preserved: unknownPreserved,
      boundaries: usageBoundaries,
    },
    independent_case_reexecutions: independentCaseReexecutions,
    production_admissions: productionAdmissions,
    safe_failure_receipts: safeFailureReceipts,
    synthetic_observer_fixture: sharedSyntheticObserverFixture,
    closed_child_environment: expectedChildEnvironment,
  };
}

function assertRecordJoin(value, expectedJoin, label, path) {
  const candidates = [];
  const visit = (entry) => {
    if (Array.isArray(entry)) {
      entry.forEach(visit);
      return;
    }
    if (entry === null || typeof entry !== "object") return;
    if (
      Object.keys(entry).length === JOIN_KEYS.length
      && JOIN_KEYS.every((key) => Object.hasOwn(entry, key))
    ) {
      candidates.push(entry);
    }
    Object.values(entry).forEach(visit);
  };
  visit(value);
  assert(
    candidates.length >= 1
      && candidates.every((candidate) => isDeepStrictEqual(candidate, expectedJoin)),
    "EVIDENCE_CROSS_BINDING_INVALID",
    `${label} does not bind the exact cell join`,
    path,
  );
}

function validateHistoricalRootCauseRegressionReceipt(
  root,
  manifestState,
) {
  const receipt = readBoundJson(
    root,
    manifestState,
    HISTORICAL_REGRESSION_RECEIPT_PATH,
    "P1-165 historical root-cause regression receipt",
  );
  exactKeys(
    receipt,
    [
      "matrix_cases_enumerated_once",
      "regressions",
      "schema_version",
      "status",
      "task_id",
    ],
    "ACCOUNTING_MISMATCH",
    "P1-165 historical root-cause regression receipt",
    HISTORICAL_REGRESSION_RECEIPT_PATH,
  );
  exactKeys(
    receipt.regressions,
    [
      "forged_observer_empty_row_precedence",
      "inventory_ordering",
      "non_regular_before_hardlink_precedence",
      "profile_verification_parent",
      "typed_2048_full_spine_stimulus",
    ],
    "ACCOUNTING_MISMATCH",
    "P1-165 historical root-cause regressions",
    HISTORICAL_REGRESSION_RECEIPT_PATH,
  );
  assert(
    receipt.schema_version === HISTORICAL_REGRESSION_RECEIPT_SCHEMA
      && receipt.task_id === TASK_ID
      && receipt.matrix_cases_enumerated_once === MATRIX_CASE_COUNT
      && Object.values(receipt.regressions).every(
        (status) => status === "PASS",
      )
      && receipt.status === "PASS",
    "ACCOUNTING_MISMATCH",
    "P1-165 historical root-cause regression receipt drifted",
    HISTORICAL_REGRESSION_RECEIPT_PATH,
  );
  return receipt.regressions;
}

function assertEmbeddedIdentity(value, identity, label, path) {
  let found = false;
  const visit = (entry) => {
    if (Array.isArray(entry)) {
      entry.forEach(visit);
      return;
    }
    if (entry === null || typeof entry !== "object") return;
    if (
      entry.byte_length === identity.byte_length
      && entry.sha256 === identity.sha256
    ) {
      found = true;
    }
    Object.values(entry).forEach(visit);
  };
  visit(value);
  assert(found, "IDENTITY_MISMATCH", `${label} lacks exact raw identity`, path);
}

function assertNoTrueExternalEffects(value, label, path) {
  const visit = (entry, currentPath) => {
    if (Array.isArray(entry)) {
      entry.forEach((child, index) => visit(child, `${currentPath}[${index}]`));
      return;
    }
    if (entry === null || typeof entry !== "object") return;
    for (const [key, child] of Object.entries(entry)) {
      if (
        ["external_effects", "observed_external_effects"].includes(key)
        && child !== null
        && typeof child === "object"
      ) {
        assertFalseEffects(child, `${label}.${key}`, path);
      }
      visit(child, `${currentPath}.${key}`);
    }
  };
  visit(value, "$");
}

function parseLsofRows(stdoutBytes) {
  const lines = stdoutBytes.toString("utf8").split("\n").filter(Boolean);
  if (lines.length <= 1) return [];
  const rows = [];
  for (const line of lines.slice(1)) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 9) continue;
    const pid = Number(parts[1]);
    const fd = parts[3];
    const name = parts.slice(8).join(" ");
    const match = /^([^ ]+)->([^ ]+) \(([^)]+)\)$/.exec(name);
    if (match === null) continue;
    rows.push({
      pid,
      fd,
      local: match[1],
      peer: match[2],
      state: match[3],
    });
  }
  return rows;
}

function validateFrozenObserver(
  root,
  manifestState,
  base,
  observer,
  expectedJoin,
) {
  const stdoutPath = `${base}/observer/stdout.log`;
  const stderrPath = `${base}/observer/stderr.log`;
  const descriptorPath = `${base}/observer/synthetic-fixture.json`;
  const stdout = readBoundBytes(root, manifestState, stdoutPath, "cell observer stdout");
  const stderr = readBoundBytes(root, manifestState, stderrPath, "cell observer stderr");
  const descriptor = readBoundJson(
    root,
    manifestState,
    descriptorPath,
    "cell synthetic observer fixture descriptor",
  );
  exactKeys(
    descriptor,
    SYNTHETIC_OBSERVER_DESCRIPTOR_KEYS,
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "cell synthetic observer fixture descriptor",
    descriptorPath,
  );
  assertRecordJoin(observer, expectedJoin, "cell observer", `${base}/observer/observation.json`);
  assertEmbeddedIdentity(observer, stdout.identity, "cell observer stdout", stdoutPath);
  assertEmbeddedIdentity(observer, stderr.identity, "cell observer stderr", stderrPath);
  const cellMatch = /^P1-165-CELL-([0-9]{2})$/.exec(expectedJoin.cell_id);
  const cellOrdinal = cellMatch === null ? 0 : Number(cellMatch[1]);
  const fixtureIndex = cellOrdinal + 1;
  assert(
    cellOrdinal >= 1
      && cellOrdinal <= 36
      && descriptor.schema_version
        === "p1-168-frozen-synthetic-observer-fixture/v1"
      && descriptor.task_id === TASK_ID
      && descriptor.fixture_index === fixtureIndex
      && descriptor.source_kind === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && descriptor.command_executed === false
      && descriptor.live_network_connection_created === false
      && descriptor.live_network_connections_created === 0
      && descriptor.live_loopback_calibration === "DEFERRED_TO_P1_169"
      && descriptor.production_record_schema
        === "p1-165-os-network-observation/v1"
      && descriptor.status === "PASS_SYNTHETIC_FIXTURE_ONLY"
      && isDeepStrictEqual(
        descriptor.production_record_identity,
        plainIdentity(canonicalBytes(observer)),
      )
      && isDeepStrictEqual(descriptor.stdout_identity, plainIdentity(stdout.bytes))
      && isDeepStrictEqual(descriptor.stderr_identity, plainIdentity(stderr.bytes))
      && observer.schema_version === "p1-165-os-network-observation/v1"
      && observer.exit_status === 0
      && observer.status === "PASS"
      && observer.pid === 420000 + fixtureIndex
      && observer.fd === `${10 + (fixtureIndex % 80)}u`
      && observer.local === `127.0.0.1:${48000 + fixtureIndex}`
      && observer.peer === `127.0.0.1:${47000 + fixtureIndex}`
      && observer.policy?.mode === "OWNED_CALIBRATION"
      && observer.peer === observer.policy?.expected_peer
      && /^127\.0\.0\.1:[1-9][0-9]{0,4}$/.test(observer.peer)
      && /^127\.0\.0\.1:[1-9][0-9]{0,4}$/.test(observer.local),
    "OBSERVER_EVIDENCE_FORGED",
    "frozen synthetic observer fixture identity is invalid",
    `${base}/observer/observation.json`,
  );
  const expectedCommand = [
    "/usr/sbin/lsof",
    "-nP",
    "-a",
    "-p",
    String(observer.pid),
    `-iTCP@${observer.peer}`,
  ];
  assert(
    isDeepStrictEqual(observer.command, expectedCommand),
    "OBSERVER_COMMAND_MISMATCH",
    "frozen observer command does not bind recorded process and peer",
    `${base}/observer/observation.json`,
  );
  const rows = parseLsofRows(stdout.bytes);
  const matching = rows.filter(
    (row) =>
      row.pid === observer.pid
      && row.fd === observer.fd
      && row.local === observer.local
      && row.peer === observer.peer
      && row.state === "ESTABLISHED",
  );
  assert(
    matching.length === 1
      && isDeepStrictEqual(rows, observer.observed_rows)
      && observer.started_at === "1970-01-01T00:00:00.000Z"
      && observer.stopped_at === "1970-01-01T00:00:00.000Z",
    "OBSERVER_EVIDENCE_FORGED",
    "frozen synthetic observer rows do not reconstruct from raw fixture bytes",
    stdoutPath,
  );
  const started = Date.parse(observer.started_at);
  const stopped = Date.parse(observer.stopped_at);
  assert(
    Number.isFinite(started) && Number.isFinite(stopped) && started <= stopped,
    "OBSERVER_TIMESTAMP_INVALID",
    "frozen observer timestamps invalid",
    `${base}/observer/observation.json`,
  );
}

function validateSpineRaw(
  root,
  manifestState,
  spineBase,
  expectedRunId = null,
  expectedTaskId = null,
  mode = "SUCCESS",
  expectedFailureStage = null,
) {
  assert(
    (
      mode === "SUCCESS"
      && expectedFailureStage === null
    )
      || (
        mode === "EXPECTED_RESEARCH_FAILURE"
        && expectedTaskId === ACCEPTED_TASK_IDS[0]
        && (
          (
            expectedRunId === "P1-165-ORACLE_FAILURE"
            && expectedFailureStage === "ORACLE"
          )
          || (
            expectedRunId === "P1-165-TEST_FAILURE"
            && expectedFailureStage === "TEST"
          )
        )
      ),
    "SPINE_VALIDATION_MODE_INVALID",
    "spine validation mode or expected research-failure identity is invalid",
    spineBase,
  );
  const directory = containedPath(root, spineBase, "spine root");
  const names = readdirSync(directory).sort();
  assert(
    isDeepStrictEqual(names, [...SPINE_ARTIFACTS].sort()),
    "SPINE_ARTIFACT_SET_INVALID",
    "spine does not contain the exact 24-artifact set",
    spineBase,
  );
  const artifacts = new Map();
  for (const name of SPINE_ARTIFACTS) {
    artifacts.set(
      name,
      readBoundBytes(root, manifestState, `${spineBase}/${name}`, `spine ${name}`),
    );
  }
  const runRecord = parseJsonBytes(
    artifacts.get("run-record.json").bytes,
    "P1-149 run record",
    `${spineBase}/run-record.json`,
  );
  assert(
    typeof runRecord.run_id === "string"
      && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$/.test(runRecord.run_id)
      && ACCEPTED_TASK_IDS.includes(runRecord.task_id)
      && (expectedRunId === null || runRecord.run_id === expectedRunId)
      && (expectedTaskId === null || runRecord.task_id === expectedTaskId),
    "SPINE_RUN_IDENTITY_INVALID",
    "P1-149 run identity invalid",
    `${spineBase}/run-record.json`,
  );
  assertNoTrueExternalEffects(runRecord, "P1-149 run record", `${spineBase}/run-record.json`);
  const spine = parseJsonBytes(
    artifacts.get("execution-spine.json").bytes,
    "P1-149 execution spine",
    `${spineBase}/execution-spine.json`,
  );
  assert(
    spine.schema_version === "p1-149-execution-spine-manifest/v1"
      && spine.run_id === runRecord.run_id
      && spine.task_id === runRecord.task_id
      && Array.isArray(spine.artifacts),
    "SPINE_MANIFEST_INVALID",
    "P1-149 execution spine manifest invalid",
    `${spineBase}/execution-spine.json`,
  );
  for (const identity of spine.artifacts) {
    assert(
      typeof identity.path === "string" && artifacts.has(identity.path),
      "SPINE_MANIFEST_INVALID",
      "P1-149 execution spine references unknown artifact",
      `${spineBase}/execution-spine.json`,
    );
    const artifact = artifacts.get(identity.path);
    assert(
      identity.byte_length === artifact.bytes.length
        && identity.sha256 === sha256(artifact.bytes),
      "SPINE_MANIFEST_INVALID",
      "P1-149 execution spine internal identity drifted",
      `${spineBase}/${identity.path}`,
    );
  }
  const replay = parseJsonBytes(
    artifacts.get("p1-101-replay-receipt.json").bytes,
    "P1-101 replay receipt",
    `${spineBase}/p1-101-replay-receipt.json`,
  );
  const rollback = parseJsonBytes(
    artifacts.get("p1-101-adapter-rollback-receipt.json").bytes,
    "P1-101 rollback receipt",
    `${spineBase}/p1-101-adapter-rollback-receipt.json`,
  );
  const trace = artifacts.get("p1-101-trace.jsonl");
  const projection = artifacts.get("p1-101-stable-projection.json");
  const runRecordArtifact = artifacts.get("run-record.json");
  assert(
    replay.schema_version === "p1-101-replay-receipt/v1"
      && replay.status === "PASS"
      && replay.exact_projection_reproduced === true
      && replay.trace_identity?.byte_length === trace.bytes.length
      && replay.trace_identity?.sha256 === sha256(trace.bytes)
      && replay.projection_identity?.byte_length === projection.bytes.length
      && replay.projection_identity?.sha256 === sha256(projection.bytes)
      && replay.run_record_identity?.byte_length === runRecordArtifact.bytes.length
      && replay.run_record_identity?.sha256 === sha256(runRecordArtifact.bytes),
    "P1_101_REPLAY_INVALID",
    "P1-101 replay receipt does not bind raw trace, projection and RunRecord",
    `${spineBase}/p1-101-replay-receipt.json`,
  );
  assertFalseEffects(replay.external_effects, "P1-101 replay", `${spineBase}/p1-101-replay-receipt.json`);
  assert(
    rollback.schema_version === "p1-101-rollback-receipt/v1"
      && rollback.status === "PASS"
      && rollback.source_state_restored === true
      && rollback.run_record_identity?.byte_length === runRecordArtifact.bytes.length
      && rollback.run_record_identity?.sha256 === sha256(runRecordArtifact.bytes),
    "P1_101_ROLLBACK_INVALID",
    "P1-101 rollback receipt does not bind exact RunRecord and restored state",
    `${spineBase}/p1-101-adapter-rollback-receipt.json`,
  );
  assertFalseEffects(
    rollback.external_effects,
    "P1-101 rollback",
    `${spineBase}/p1-101-adapter-rollback-receipt.json`,
  );
  const traceEvents = parseJsonLines(
    trace.bytes,
    "P1-101 trace",
    `${spineBase}/p1-101-trace.jsonl`,
  );
  assert(
    traceEvents.length >= 1
      && traceEvents.every((event) => event.run_id === runRecord.run_id),
    "P1_101_TRACE_INVALID",
    "P1-101 trace does not bind one exact run",
    `${spineBase}/p1-101-trace.jsonl`,
  );
  const stableProjection = parseJsonBytes(
    projection.bytes,
    "P1-101 stable projection",
    `${spineBase}/p1-101-stable-projection.json`,
  );
  const compilerPlan = parseJsonBytes(
    artifacts.get("compiler-plan.json").bytes,
    "P1-149 compiler plan",
    `${spineBase}/compiler-plan.json`,
  );
  const applyReceipt = parseJsonBytes(
    artifacts.get("apply-receipt.json").bytes,
    "P1-149 apply receipt",
    `${spineBase}/apply-receipt.json`,
  );
  const oracleReceipt = parseJsonBytes(
    artifacts.get("oracle-receipt.json").bytes,
    "P1-149 oracle receipt",
    `${spineBase}/oracle-receipt.json`,
  );
  const testReceipt = parseJsonBytes(
    artifacts.get("test-receipt.json").bytes,
    "P1-149 test receipt",
    `${spineBase}/test-receipt.json`,
  );
  const rollbackReceipt = parseJsonBytes(
    artifacts.get("rollback-receipt.json").bytes,
    "P1-149 rollback receipt",
    `${spineBase}/rollback-receipt.json`,
  );
  assert(
    runRecord.terminal_status === "COMPLETED"
      && runRecord.stop_reason_code === "NONE"
      && Array.isArray(runRecord.policy_violations)
      && runRecord.policy_violations.length === 0
      && Array.isArray(compilerPlan.operations)
      && compilerPlan.operations.length >= 1
      && Array.isArray(applyReceipt.applied_operations)
      && applyReceipt.applied_operations.length
        === compilerPlan.operations.length
      && applyReceipt.canonical_source_written === false
      && rollbackReceipt.status === "PASS_EXACT"
      && rollbackReceipt.canonical_source_written === false,
    "SPINE_EXECUTION_GATE_INVALID",
    "P1-149 compiler/apply/rollback common Gate did not close",
    spineBase,
  );
  if (mode === "SUCCESS") {
    assert(
      oracleReceipt.result_classification === "VERIFIED_SUCCESS"
        && oracleReceipt.independently_observed_postcondition
          ?.changed_paths_equal_compiler_plan === true
        && oracleReceipt.independently_observed_postcondition
          ?.issue_test_passed === true
        && oracleReceipt.independently_observed_postcondition
          ?.regression_test_passed === true
        && Array.isArray(testReceipt.commands)
        && testReceipt.commands.length >= 1
        && testReceipt.commands.every((command) =>
          command.observed_signal === null
            && Array.isArray(command.expected_exit_codes)
            && command.expected_exit_codes.includes(command.observed_exit_status)),
      "SPINE_EXECUTION_GATE_INVALID",
      "P1-149 oracle/tests success Gate did not close",
      spineBase,
    );
  }
  for (const [value, label, path] of [
    [applyReceipt, "P1-149 apply receipt", `${spineBase}/apply-receipt.json`],
    [oracleReceipt, "P1-149 oracle receipt", `${spineBase}/oracle-receipt.json`],
    [testReceipt, "P1-149 test receipt", `${spineBase}/test-receipt.json`],
    [rollbackReceipt, "P1-149 rollback receipt", `${spineBase}/rollback-receipt.json`],
  ]) {
    assertFalseEffects(value.external_effects, label, path);
  }
  return {
    run_id: runRecord.run_id,
    task_id: runRecord.task_id,
    artifacts,
    replay,
    rollback,
    stable_projection: stableProjection,
  };
}

function readCanonicalBoundJson(root, manifestState, path, label) {
  const artifact = readBoundBytes(root, manifestState, path, label);
  const value = parseJsonBytes(artifact.bytes, label, path);
  assert(
    artifact.bytes.equals(Buffer.from(`${canonicalJson(value)}\n`, "utf8")),
    "ADAPTER_CONTROL_INVALID",
    `${label} is not canonical JSON with one trailing LF`,
    path,
  );
  return { artifact, value };
}

function validateSourceDirectoryIdentity(value, label, path) {
  exactKeys(
    value,
    SOURCE_DIRECTORY_IDENTITY_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
    path,
  );
  assert(
    typeof value.path === "string"
      && isAbsolute(value.path)
      && resolve(value.path) === value.path
      && Number.isSafeInteger(value.dev)
      && value.dev >= 0
      && Number.isSafeInteger(value.ino)
      && value.ino > 0
      && Number.isSafeInteger(value.uid)
      && value.uid >= 0,
    "ADAPTER_CONTROL_INVALID",
    `${label} shape is invalid`,
    path,
  );
  return value;
}

function readRepositoryRegularFileNoFollow(path, label, bytesMax) {
  assert(
    isAbsolute(path)
      && resolve(path) === path
      && Number.isSafeInteger(bytesMax)
      && bytesMax > 0,
    "ADAPTER_CONTROL_INVALID",
    `${label} read boundary is invalid`,
    path,
  );
  const relativePath = relative(REPOSITORY_ROOT, path);
  assert(
    relativePath !== ""
      && !relativePath.startsWith(`..${sep}`)
      && !isAbsolute(relativePath)
      && realpathSync(dirname(path)) === dirname(path),
    "ADAPTER_CONTROL_INVALID",
    `${label} is outside the canonical repository or below a symlink`,
    path,
  );
  const before = lstatSync(path);
  assert(
    before.isFile()
      && !before.isSymbolicLink()
      && before.nlink === 1
      && before.size <= bytesMax
      && realpathSync(path) === path,
    "ADAPTER_CONTROL_INVALID",
    `${label} type, link count, or pre-read byte cap is invalid`,
    path,
  );
  let descriptor = null;
  try {
    descriptor = openSync(
      path,
      fsConstants.O_RDONLY
        | (fsConstants.O_NOFOLLOW ?? 0)
        | (fsConstants.O_NONBLOCK ?? 0),
    );
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.uid === before.uid
        && opened.nlink === 1
        && opened.size === before.size
        && opened.size <= bytesMax,
      "ADAPTER_CONTROL_INVALID",
      `${label} changed while opening`,
      path,
    );
    const bytes = readFileSync(descriptor);
    const afterFd = fstatSync(descriptor);
    const afterPath = lstatSync(path);
    assert(
      bytes.length === opened.size
        && afterFd.dev === opened.dev
        && afterFd.ino === opened.ino
        && afterFd.uid === opened.uid
        && afterFd.nlink === opened.nlink
        && afterFd.size === opened.size
        && afterPath.isFile()
        && !afterPath.isSymbolicLink()
        && afterPath.dev === opened.dev
        && afterPath.ino === opened.ino
        && afterPath.uid === opened.uid
        && afterPath.nlink === opened.nlink
        && afterPath.size === opened.size
        && realpathSync(path) === path,
      "ADAPTER_CONTROL_INVALID",
      `${label} changed during its bounded no-follow read`,
      path,
    );
    return {
      bytes,
      identity: {
        byte_length: bytes.length,
        sha256: sha256(bytes),
      },
    };
  } finally {
    if (descriptor !== null) closeSync(descriptor);
  }
}

let acceptedTaskDatasetCache = null;

function loadAcceptedTaskDataset() {
  if (acceptedTaskDatasetCache !== null) return acceptedTaskDatasetCache;
  const manifestArtifact = readRepositoryRegularFileNoFollow(
    ACCEPTED_TASK_DATASET_MANIFEST_PATH,
    "accepted representative task dataset manifest",
    ACCEPTED_TASK_INPUT_BYTES_MAX,
  );
  assert(
    manifestArtifact.identity.sha256
      === ACCEPTED_TASK_DATASET_MANIFEST_SHA256,
    "ADAPTER_CONTROL_INVALID",
    "accepted representative task dataset manifest identity drifted",
    ACCEPTED_TASK_DATASET_MANIFEST_PATH,
  );
  const manifest = parseJsonBytes(
    manifestArtifact.bytes,
    "accepted representative task dataset manifest",
    ACCEPTED_TASK_DATASET_MANIFEST_PATH,
  );
  assert(
    manifest.schema_version === "1.0"
      && manifest.dataset_id === "SOURCELENS-P1-REPRESENTATIVE-TASKS"
      && manifest.dataset_version === "1.0.0"
      && manifest.task_count === ACCEPTED_TASK_IDS.length
      && Array.isArray(manifest.tasks)
      && manifest.tasks.length === manifest.task_count
      && Array.isArray(manifest.artifacts)
      && manifest.artifacts.length === manifest.artifact_count
      && isDeepStrictEqual(
        manifest.tasks.map((entry) => entry.task_id),
        ACCEPTED_TASK_IDS,
      ),
    "ADAPTER_CONTROL_INVALID",
    "accepted representative task dataset header or task set drifted",
    ACCEPTED_TASK_DATASET_MANIFEST_PATH,
  );
  const taskSpecs = new Map();
  for (const taskEntry of manifest.tasks) {
    const expectedRelativePath =
      `tasks/${taskEntry.task_id}/task-spec.json`;
    const artifactEntry = manifest.artifacts.find(
      (entry) => entry.path === expectedRelativePath,
    );
    assert(
      taskEntry.task_spec_path === expectedRelativePath
        && artifactEntry !== undefined
        && artifactEntry.type === "json"
        && /^[0-9a-f]{64}$/.test(artifactEntry.sha256)
        && Number.isSafeInteger(artifactEntry.byte_length)
        && artifactEntry.byte_length > 0
        && artifactEntry.byte_length <= ACCEPTED_TASK_INPUT_BYTES_MAX
        && manifest.artifacts.filter(
          (entry) => entry.path === expectedRelativePath,
        ).length === 1,
      "ADAPTER_CONTROL_INVALID",
      `accepted TaskSpec manifest mapping drifted for ${taskEntry.task_id}`,
      ACCEPTED_TASK_DATASET_MANIFEST_PATH,
    );
    const absolutePath = resolve(
      ACCEPTED_TASK_DATASET_ROOT,
      ...expectedRelativePath.split("/"),
    );
    const artifact = readRepositoryRegularFileNoFollow(
      absolutePath,
      `accepted TaskSpec ${taskEntry.task_id}`,
      ACCEPTED_TASK_INPUT_BYTES_MAX,
    );
    assert(
      artifact.identity.sha256 === artifactEntry.sha256
        && artifact.identity.byte_length === artifactEntry.byte_length,
      "ADAPTER_CONTROL_INVALID",
      `accepted TaskSpec bytes drifted for ${taskEntry.task_id}`,
      absolutePath,
    );
    const value = parseJsonBytes(
      artifact.bytes,
      `accepted TaskSpec ${taskEntry.task_id}`,
      absolutePath,
    );
    assert(
      value.schema_version === "1.0"
        && value.task_id === taskEntry.task_id,
      "ADAPTER_CONTROL_INVALID",
      `accepted TaskSpec task identity drifted for ${taskEntry.task_id}`,
      absolutePath,
    );
    taskSpecs.set(taskEntry.task_id, {
      absolute_path: absolutePath,
      identity: artifact.identity,
      value,
    });
  }
  assert(
    taskSpecs.size === ACCEPTED_TASK_IDS.length,
    "ADAPTER_CONTROL_INVALID",
    "accepted TaskSpec mapping is incomplete",
    ACCEPTED_TASK_DATASET_MANIFEST_PATH,
  );
  acceptedTaskDatasetCache = {
    manifest_identity: manifestArtifact.identity,
    task_specs: taskSpecs,
  };
  return acceptedTaskDatasetCache;
}

function validateAcceptedTaskSpecDescriptor(descriptor, taskId, label) {
  exactKeys(
    descriptor,
    IDENTITY_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
  );
  const accepted = loadAcceptedTaskDataset().task_specs.get(taskId);
  assert(
    accepted !== undefined
      && descriptor.path === accepted.absolute_path
      && descriptor.type === "REGULAR_FILE"
      && descriptor.nlink === 1
      && descriptor.byte_length === accepted.identity.byte_length
      && descriptor.sha256 === accepted.identity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} is not the exact accepted dataset TaskSpec`,
    descriptor.path,
  );
  return accepted.value;
}

function validateAcceptedTaskSpecProvenanceDescriptor(
  descriptor,
  taskId,
  label,
) {
  exactKeys(
    descriptor,
    ARTIFACT_DESCRIPTOR_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
  );
  const accepted = loadAcceptedTaskDataset().task_specs.get(taskId);
  const expectedPath = resolve(
    ACCEPTED_P1_129_WORKTREE_ROOT,
    "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks",
    taskId,
    "task-spec.json",
  );
  assert(
    accepted !== undefined
      && descriptor.path === expectedPath
      && descriptor.byte_length === accepted.identity.byte_length
      && descriptor.sha256 === accepted.identity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} does not preserve the exact accepted P1-129 provenance path `
      + "and current canonical bytes",
    descriptor.path,
  );
  return accepted.value;
}

function validateRepositoryArtifactDescriptor(descriptor, expectedRelativePath, label) {
  exactKeys(
    descriptor,
    ARTIFACT_DESCRIPTOR_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
  );
  const expectedPath = resolve(
    REPOSITORY_ROOT,
    ...expectedRelativePath.split("/"),
  );
  assert(
    descriptor.path === expectedPath,
    "ADAPTER_CONTROL_INVALID",
    `${label} is not bound to the current canonical worktree`,
    descriptor.path,
  );
  const artifact = readRepositoryRegularFileNoFollow(
    expectedPath,
    label,
    ACCEPTED_TASK_INPUT_BYTES_MAX,
  );
  assert(
    descriptor.byte_length === artifact.identity.byte_length
      && descriptor.sha256 === artifact.identity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} bytes or file type drifted`,
    descriptor.path,
  );
  return {
    bytes: artifact.bytes,
    value: parseJsonBytes(artifact.bytes, label, descriptor.path),
  };
}

function validateAcceptedRepositoryProvenanceDescriptor(
  descriptor,
  expectedRelativePath,
  label,
) {
  exactKeys(
    descriptor,
    ARTIFACT_DESCRIPTOR_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
  );
  const expectedProvenancePath = resolve(
    ACCEPTED_P1_129_WORKTREE_ROOT,
    ...expectedRelativePath.split("/"),
  );
  const expectedCanonicalPath = resolve(
    REPOSITORY_ROOT,
    ...expectedRelativePath.split("/"),
  );
  assert(
    descriptor.path === expectedProvenancePath,
    "ADAPTER_CONTROL_INVALID",
    `${label} does not preserve the exact accepted P1-129 provenance path`,
    descriptor.path,
  );
  const artifact = readRepositoryRegularFileNoFollow(
    expectedCanonicalPath,
    `${label} current canonical counterpart`,
    ACCEPTED_TASK_INPUT_BYTES_MAX,
  );
  assert(
    descriptor.byte_length === artifact.identity.byte_length
      && descriptor.sha256 === artifact.identity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} does not match the current canonical counterpart bytes`,
    descriptor.path,
  );
  return {
    bytes: artifact.bytes,
    value: parseJsonBytes(artifact.bytes, label, expectedCanonicalPath),
  };
}

function validateCanonicalRelativeArtifactDescriptor(
  descriptor,
  expectedRelativePath,
  label,
  maximumBytes = ACCEPTED_TASK_INPUT_BYTES_MAX,
) {
  exactKeys(
    descriptor,
    ARTIFACT_DESCRIPTOR_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
  );
  safeRelativePath(descriptor.path, `${label}.path`);
  assert(
    descriptor.path === expectedRelativePath,
    "ADAPTER_CONTROL_INVALID",
    `${label} repository-relative path drifted`,
    descriptor.path,
  );
  const expectedPath = resolve(
    REPOSITORY_ROOT,
    ...expectedRelativePath.split("/"),
  );
  const artifact = readRepositoryRegularFileNoFollow(
    expectedPath,
    label,
    maximumBytes,
  );
  assert(
    descriptor.byte_length === artifact.identity.byte_length
      && descriptor.sha256 === artifact.identity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} does not match the current canonical bytes`,
    descriptor.path,
  );
  return artifact;
}

function validatePassingCommandLedger(ledger, label, path) {
  exactKeys(
    ledger,
    COMMAND_LEDGER_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
    path,
  );
  assert(
    ledger.schema_version === "1.0"
      && ledger.record_type === "p1_125_bounded_command_ledger"
      && Array.isArray(ledger.argv)
      && ledger.argv.length >= 1
      && ledger.argv.every((entry) => typeof entry === "string")
      && typeof ledger.cwd === "string"
      && isAbsolute(ledger.cwd)
      && Array.isArray(ledger.expected_exit_codes)
      && ledger.expected_exit_codes.includes(0)
      && ledger.exit_status === 0
      && ledger.expected_exit_matched === true
      && ledger.signal === null
      && ledger.timed_out === false
      && Number.isSafeInteger(ledger.timeout_seconds)
      && ledger.timeout_seconds > 0
      && Number.isSafeInteger(ledger.latency_ms)
      && ledger.latency_ms >= 0
      && Number.isSafeInteger(ledger.stdout_byte_length)
      && ledger.stdout_byte_length >= 0
      && /^[0-9a-f]{64}$/.test(ledger.stdout_sha256)
      && Number.isSafeInteger(ledger.stderr_byte_length)
      && ledger.stderr_byte_length >= 0
      && /^[0-9a-f]{64}$/.test(ledger.stderr_sha256)
      && Number.isFinite(Date.parse(ledger.started_at))
      && Number.isFinite(Date.parse(ledger.ended_at))
      && Date.parse(ledger.started_at) <= Date.parse(ledger.ended_at),
    "ADAPTER_CONTROL_INVALID",
    `${label} is not a passing bounded command ledger`,
    path,
  );
  return ledger;
}

function expectedClosedChildEnvironment(home) {
  assert(
    typeof home === "string"
      && isAbsolute(home)
      && !home.includes("\0")
      && resolve(home) === home,
    "ADAPTER_CONTROL_INVALID",
    "independent evaluator cannot bind the closed child HOME",
  );
  return {
    HOME: home,
    LANG: "C",
    LC_ALL: "C",
    PATH:
      "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    TZ: "UTC",
  };
}

function readLiveRegularFileNoFollow(path, label, maximumBytes) {
  assert(
    typeof path === "string"
      && isAbsolute(path)
      && resolve(path) === path
      && Number.isSafeInteger(maximumBytes)
      && maximumBytes > 0,
    "ADAPTER_CONTROL_INVALID",
    `${label} live-read boundary is invalid`,
    path,
  );
  const before = lstatSync(path);
  assert(
    before.isFile()
      && !before.isSymbolicLink()
      && before.nlink === 1
      && before.uid === process.getuid()
      && before.size >= 0
      && before.size <= maximumBytes
      && realpathSync(dirname(path)) === dirname(path),
    "ADAPTER_CONTROL_INVALID",
    `${label} is not one bounded current-user regular file`,
    path,
  );
  let descriptor = null;
  try {
    descriptor = openSync(
      path,
      fsConstants.O_RDONLY
        | (fsConstants.O_NOFOLLOW ?? 0)
        | (fsConstants.O_NONBLOCK ?? 0),
    );
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile()
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.uid === before.uid
        && opened.nlink === before.nlink
        && opened.size === before.size,
      "ADAPTER_CONTROL_INVALID",
      `${label} changed while opening`,
      path,
    );
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    assert(
      bytes.length === before.size
        && after.dev === opened.dev
        && after.ino === opened.ino
        && after.uid === opened.uid
        && after.nlink === opened.nlink
        && after.size === opened.size,
      "ADAPTER_CONTROL_INVALID",
      `${label} changed while reading`,
      path,
    );
    return bytes;
  } finally {
    if (descriptor !== null) closeSync(descriptor);
  }
}

function validateLiveDirectoryIdentity(value, expectedPath, label, path) {
  const identity = validateSourceDirectoryIdentity(value, label, path);
  const stat = lstatSync(expectedPath);
  assert(
    identity.path === expectedPath
      && stat.isDirectory()
      && !stat.isSymbolicLink()
      && realpathSync(expectedPath) === expectedPath
      && identity.dev === stat.dev
      && identity.ino === stat.ino
      && identity.uid === stat.uid,
    "ADAPTER_CONTROL_INVALID",
    `${label} live identity drifted`,
    path,
  );
  return identity;
}

function validateAcceptedAdapterCalibrationCapture({
  capture,
  expectedArgv,
  expectedEnvironment,
  expectedExitStatus,
  expectedSignal,
  expectedStdout,
  expectedStderr,
  expectedPrefix,
  label,
  manifestState,
  root,
  receiptPath,
}) {
  exactKeys(
    capture,
    ACCEPTED_ADAPTER_CALIBRATION_CAPTURE_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
    receiptPath,
  );
  const stdoutIdentity = validateBoundArtifactDescriptor(
    capture.stdout_identity,
    manifestState,
    `${label} stdout`,
    `${expectedPrefix}/stdout.log`,
  );
  const stderrIdentity = validateBoundArtifactDescriptor(
    capture.stderr_identity,
    manifestState,
    `${label} stderr`,
    `${expectedPrefix}/stderr.log`,
  );
  assert(
    stdoutIdentity.path === `${expectedPrefix}/stdout.log`
      && stderrIdentity.path === `${expectedPrefix}/stderr.log`,
    "ADAPTER_CONTROL_INVALID",
    `${label} stream paths drifted`,
    receiptPath,
  );
  const stdout = readBoundBytes(
    root,
    manifestState,
    stdoutIdentity.path,
    `${label} stdout`,
  );
  const stderr = readBoundBytes(
    root,
    manifestState,
    stderrIdentity.path,
    `${label} stderr`,
  );
  assert(
    isDeepStrictEqual(capture.argv, expectedArgv)
      && isDeepStrictEqual(capture.environment, expectedEnvironment)
      && Number.isSafeInteger(capture.parent_pid)
      && capture.parent_pid > 0
      && Number.isSafeInteger(capture.child_pid)
      && capture.child_pid > 0
      && capture.child_pid !== capture.parent_pid
      && capture.exit_status === expectedExitStatus
      && capture.signal === expectedSignal
      && capture.timed_out === false
      && Number.isFinite(Date.parse(capture.started_at))
      && Number.isFinite(Date.parse(capture.stopped_at))
      && Date.parse(capture.started_at) <= Date.parse(capture.stopped_at)
      && stdout.bytes.equals(expectedStdout)
      && stderr.bytes.equals(expectedStderr),
    "ADAPTER_CONTROL_INVALID",
    `${label} raw process Evidence drifted`,
    receiptPath,
  );
  return {
    child_pid: capture.child_pid,
    parent_pid: capture.parent_pid,
  };
}

function validateAcceptedControlClaimFlags(
  value,
  expectedBoundary,
  label,
  path,
  {
    historical = true,
    cooperativeResidual = true,
  } = {},
) {
  assert(
    value.hostile_global_read_isolation_claim === false
      && value.hostile_process_isolation_claim === false
      && value.trusted_accepted_source_required === true
      && value.claim_boundary === expectedBoundary
      && (
        historical
          ? value.historical_reviewed_binary_exact_bytes_claim === false
          : true
      )
      && (
        cooperativeResidual
          ? value.cooperative_local_accepted_evidence_path_residual === true
          : true
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} claim boundary drifted`,
    path,
  );
}

function validateExternalArtifactIdentity(
  value,
  label,
  maximumBytes = ACCEPTED_ADAPTER_PROOF_SINGLE_FILE_BYTES_MAX,
) {
  exactKeys(
    value,
    IDENTITY_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
    value?.path,
  );
  assert(
    isAbsolute(value.path)
      && resolve(value.path) === value.path
      && value.type === "REGULAR_FILE"
      && value.nlink === 1
      && Number.isSafeInteger(value.byte_length)
      && value.byte_length >= 0
      && value.byte_length <= maximumBytes
      && typeof value.sha256 === "string"
      && /^[0-9a-f]{64}$/.test(value.sha256),
    "ADAPTER_CONTROL_INVALID",
    `${label} identity is not exact`,
    value.path,
  );
  const bytes = readLiveRegularFileNoFollow(
    value.path,
    label,
    maximumBytes,
  );
  assert(
    bytes.length === value.byte_length
      && sha256(bytes) === value.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} live bytes drifted`,
    value.path,
  );
  return { identity: value, bytes };
}

function validateAcceptedP1129AuthorityBundle(
  root,
  manifestState,
  identity,
) {
  const path =
    "raw/accepted-adapter-control/accepted-p1-129/authority-bundle.json";
  const boundIdentity = validateBoundArtifactDescriptor(
    identity,
    manifestState,
    "accepted P1-129 authority bundle",
    path,
  );
  assert(
    boundIdentity.path === path,
    "ADAPTER_CONTROL_INVALID",
    "accepted P1-129 authority-bundle path drifted",
    path,
  );
  const bundle = readCanonicalBoundJson(
    root,
    manifestState,
    path,
    "accepted P1-129 authority bundle",
  ).value;
  exactKeys(
    bundle,
    [
      "accepted_candidate_commit",
      "accepted_candidate_tree",
      "accepted_counts",
      "accepted_task_id",
      "artifacts",
      "claim_boundary",
      "cooperative_local_accepted_evidence_path_residual",
      "historical_reviewed_binary_exact_bytes_claim",
      "hostile_global_read_isolation_claim",
      "hostile_process_isolation_claim",
      "residual_disclosure",
      "schema_version",
      "source_formal_root",
      "source_task_root",
      "status",
      "task_id",
      "trusted_accepted_source_required",
    ],
    "ADAPTER_CONTROL_INVALID",
    "accepted P1-129 authority bundle",
    path,
  );
  exactKeys(
    bundle.accepted_counts,
    [
      "b2_real_repository_analysis_scan_children",
      "false_accepts",
      "negative_cases",
      "positive_runs",
    ],
    "ADAPTER_CONTROL_INVALID",
    "accepted P1-129 counts",
    path,
  );
  const roles = [
    "authority",
    "candidate_manifest",
    "cto_review",
    "formal_summary",
    "negative_results",
    "quality_review",
    "security_review",
    "terminal_receipt",
  ];
  exactKeys(
    bundle.artifacts,
    roles,
    "ADAPTER_CONTROL_INVALID",
    "accepted P1-129 authority artifacts",
    path,
  );
  const stagedPaths = new Set();
  for (const role of roles) {
    const pair = bundle.artifacts[role];
    exactKeys(
      pair,
      ["source_identity", "staged_identity"],
      "ADAPTER_CONTROL_INVALID",
      `accepted P1-129 ${role} identity pair`,
      path,
    );
    const source = validateExternalArtifactIdentity(
      pair.source_identity,
      `accepted P1-129 ${role} source`,
    );
    const stagedIdentity = validateBoundArtifactDescriptor(
      pair.staged_identity,
      manifestState,
      `accepted P1-129 ${role} staged artifact`,
    );
    const staged = readBoundBytes(
      root,
      manifestState,
      stagedIdentity.path,
      `accepted P1-129 ${role} staged artifact`,
    );
    assert(
      stagedIdentity.path.startsWith(
        "raw/accepted-adapter-control/accepted-p1-129/",
      )
        && !stagedPaths.has(stagedIdentity.path)
        && source.bytes.equals(staged.bytes)
        && source.identity.byte_length === stagedIdentity.byte_length
        && source.identity.sha256 === stagedIdentity.sha256,
      "ADAPTER_CONTROL_INVALID",
      `accepted P1-129 ${role} source/staged bytes drifted`,
      stagedIdentity.path,
    );
    stagedPaths.add(stagedIdentity.path);
  }
  validateAcceptedControlClaimFlags(
    bundle,
    ACCEPTED_P1_129_CLAIM_BOUNDARY,
    "accepted P1-129 authority bundle",
    path,
  );
  const sourceTaskRootIdentity = validateLiveDirectoryIdentity(
    bundle.source_task_root,
    ACCEPTED_P1_129_TASK_ROOT,
    "accepted P1-129 source task root",
    path,
  );
  const sourceFormalRootIdentity = validateLiveDirectoryIdentity(
    bundle.source_formal_root,
    ACCEPTED_P1_129_FORMAL_ROOT,
    "accepted P1-129 source formal root",
    path,
  );
  assert(
    bundle.schema_version
        === "p1-165-accepted-p1-129-authority-bundle/v1"
      && bundle.task_id === TASK_ID
      && bundle.accepted_task_id === ACCEPTED_P1_129_TASK_ID
      && bundle.accepted_candidate_commit
        === ACCEPTED_P1_129_CANDIDATE_COMMIT
      && bundle.accepted_candidate_tree
        === ACCEPTED_P1_129_CANDIDATE_TREE
      && sourceTaskRootIdentity.path === ACCEPTED_P1_129_TASK_ROOT
      && sourceFormalRootIdentity.path === ACCEPTED_P1_129_FORMAL_ROOT
      && bundle.residual_disclosure
        === ACCEPTED_P1_129_RESIDUAL_DISCLOSURE
      && bundle.status === "PASS"
      && isDeepStrictEqual(bundle.accepted_counts, {
        positive_runs: 36,
        b2_real_repository_analysis_scan_children: 12,
        negative_cases: 53,
        false_accepts: 0,
      }),
    "ADAPTER_CONTROL_INVALID",
    "accepted P1-129 authority facts drifted",
    path,
  );
  return { identity: boundIdentity, bundle };
}

function validateAcceptedCalibrationCapture(
  root,
  manifestState,
  capture,
  label,
  path,
) {
  exactKeys(
    capture,
    ACCEPTED_ADAPTER_CALIBRATION_CAPTURE_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
    path,
  );
  const stdoutIdentity = validateBoundArtifactDescriptor(
    capture.stdout_identity,
    manifestState,
    `${label} stdout`,
  );
  const stderrIdentity = validateBoundArtifactDescriptor(
    capture.stderr_identity,
    manifestState,
    `${label} stderr`,
  );
  assert(
    Array.isArray(capture.argv)
      && capture.argv.length >= 1
      && capture.argv.every((entry) => typeof entry === "string")
      && typeof capture.cwd === "string"
      && isAbsolute(capture.cwd)
      && resolve(capture.cwd) === capture.cwd
      && capture.environment !== null
      && typeof capture.environment === "object"
      && !Array.isArray(capture.environment)
      && Number.isSafeInteger(capture.parent_pid)
      && capture.parent_pid > 0
      && Number.isSafeInteger(capture.child_pid)
      && capture.child_pid > 0
      && capture.child_pid !== capture.parent_pid
      && (
        capture.exit_status === null
        || Number.isSafeInteger(capture.exit_status)
      )
      && (capture.signal === null || typeof capture.signal === "string")
      && capture.timed_out === false
      && Number.isSafeInteger(capture.timeout_ms)
      && capture.timeout_ms > 0
      && capture.error_code === null
      && Number.isFinite(Date.parse(capture.started_at))
      && Number.isFinite(Date.parse(capture.stopped_at))
      && Date.parse(capture.started_at) <= Date.parse(capture.stopped_at)
      && stdoutIdentity.path.startsWith(
        "raw/accepted-adapter-control/sandbox-calibration/",
      )
      && stderrIdentity.path.startsWith(
        "raw/accepted-adapter-control/sandbox-calibration/",
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} process identity drifted`,
    path,
  );
  return {
    capture,
    stdout: readBoundBytes(
      root,
      manifestState,
      stdoutIdentity.path,
      `${label} stdout`,
    ).bytes,
    stderr: readBoundBytes(
      root,
      manifestState,
      stderrIdentity.path,
      `${label} stderr`,
    ).bytes,
  };
}

function validateAcceptedBinarySandboxCalibration(
  root,
  manifestState,
  identity,
) {
  const path =
    "raw/accepted-adapter-control/sandbox-calibration/receipt.json";
  const boundIdentity = validateBoundArtifactDescriptor(
    identity,
    manifestState,
    "accepted binary sandbox calibration",
    path,
  );
  assert(
    boundIdentity.path === path,
    "ADAPTER_CONTROL_INVALID",
    "accepted binary sandbox calibration path drifted",
    path,
  );
  const receipt = readCanonicalBoundJson(
    root,
    manifestState,
    path,
    "accepted binary sandbox calibration",
  ).value;
  exactKeys(
    receipt,
    [
      "calibration_profile_identity",
      "calibration_roots_cleaned",
      "claim_boundary",
      "closed_environment",
      "denied_error_code",
      "excluded_real_home_config_and_credential_paths",
      "external_write_denial",
      "external_write_target_absent",
      "false_accepts",
      "home_read_denial",
      "home_write_denial",
      "hostile_global_read_isolation_claim",
      "hostile_process_isolation_claim",
      "live_network_calibration",
      "live_network_connections_created",
      "live_network_probe_executed",
      "network_probe_source_kind",
      "owned_write_allowance",
      "real_home_identity",
      "real_home_write_target_absent",
      "sandbox_profile_identity",
      "schema_version",
      "status",
      "synthetic_network_denial_fixture_identity",
      "task_id",
      "trusted_accepted_source_required",
    ],
    "ADAPTER_CONTROL_INVALID",
    "accepted binary sandbox calibration",
    path,
  );
  const profileIdentity = validateBoundArtifactDescriptor(
    receipt.sandbox_profile_identity,
    manifestState,
    "accepted binary sandbox profile",
  );
  const calibrationProfileIdentity = validateBoundArtifactDescriptor(
    receipt.calibration_profile_identity,
    manifestState,
    "accepted binary calibration profile",
  );
  const syntheticNetworkFixtureIdentity = validateBoundArtifactDescriptor(
    receipt.synthetic_network_denial_fixture_identity,
    manifestState,
    "accepted binary synthetic network denial fixture",
  );
  const syntheticNetworkFixturePath =
    "raw/accepted-adapter-control/sandbox-calibration/"
    + "synthetic-network-denial-fixture.json";
  assert(
    syntheticNetworkFixtureIdentity.path === syntheticNetworkFixturePath,
    "ADAPTER_CONTROL_INVALID",
    "synthetic network denial fixture path drifted",
    path,
  );
  const syntheticNetworkFixture = readCanonicalBoundJson(
    root,
    manifestState,
    syntheticNetworkFixturePath,
    "accepted binary synthetic network denial fixture",
  ).value;
  exactKeys(
    syntheticNetworkFixture,
    [
      "calibration_profile_identity",
      "expected_policy",
      "live_network_connections_created",
      "live_network_probe_executed",
      "sandbox_profile_identity",
      "schema_version",
      "source_kind",
      "status",
      "task_id",
    ],
    "ADAPTER_CONTROL_INVALID",
    "accepted binary synthetic network denial fixture",
    syntheticNetworkFixturePath,
  );
  const realHome = validateLiveDirectoryIdentity(
    receipt.real_home_identity,
    process.env.HOME,
    "accepted binary real HOME",
    path,
  );
  const captures = Object.fromEntries(
    [
      "home_read_denial",
      "home_write_denial",
      "external_write_denial",
      "owned_write_allowance",
    ].map((key) => [
      key,
      validateAcceptedCalibrationCapture(
        root,
        manifestState,
        receipt[key],
        `accepted binary ${key}`,
        path,
      ),
    ]),
  );
  const childPids = Object.values(captures).map(
    ({ capture }) => capture.child_pid,
  );
  const parentPids = new Set(
    Object.values(captures).map(({ capture }) => capture.parent_pid),
  );
  const profiles = [
    readBoundBytes(
      root,
      manifestState,
      profileIdentity.path,
      "accepted binary sandbox profile",
    ).bytes,
    readBoundBytes(
      root,
      manifestState,
      calibrationProfileIdentity.path,
      "accepted binary calibration profile",
    ).bytes,
  ];
  for (const profile of profiles) {
    const text = profile.toString("utf8");
    assert(
      text.includes("(allow default)")
        && text.includes("(deny network*)")
        && !text.includes("(deny process-fork)")
        && !text.includes("(deny process-exec)")
        && !text.includes("(allow process-exec")
        && !text.includes("(deny mach-")
        && !/(^|\n)\(deny file-read\*\)\s*(\n|$)/.test(text),
      "ADAPTER_CONTROL_INVALID",
      "accepted binary cooperative-local sandbox profile drifted",
      profileIdentity.path,
    );
  }
  exactKeys(
    receipt.closed_environment,
    ["HOME", "LANG", "LC_ALL", "PATH", "TZ"],
    "ADAPTER_CONTROL_INVALID",
    "accepted binary closed environment",
    path,
  );
  validateAcceptedControlClaimFlags(
    receipt,
    B2_REEXECUTION_CLAIM_BOUNDARY,
    "accepted binary sandbox calibration",
    path,
    { historical: false, cooperativeResidual: false },
  );
  assert(
    receipt.schema_version
        === "p1-168-accepted-binary-sandbox-calibration/v2"
      && receipt.task_id === TASK_ID
      && receipt.status === "PASS"
      && receipt.denied_error_code === "EPERM"
      && receipt.network_probe_source_kind === "SYNTHETIC_FIXTURE_ONLY"
      && receipt.live_network_probe_executed === false
      && receipt.live_network_connections_created === 0
      && receipt.live_network_calibration === "DEFERRED_TO_P1_169"
      && syntheticNetworkFixture.schema_version
        === "p1-168-synthetic-network-denial-fixture/v1"
      && syntheticNetworkFixture.task_id === TASK_ID
      && syntheticNetworkFixture.source_kind === "SYNTHETIC_FIXTURE_ONLY"
      && syntheticNetworkFixture.live_network_probe_executed === false
      && syntheticNetworkFixture.live_network_connections_created === 0
      && syntheticNetworkFixture.expected_policy
        === "NETWORK_DENIAL_DEFERRED_TO_P1_169"
      && syntheticNetworkFixture.status === "PASS_SYNTHETIC_FIXTURE_ONLY"
      && isDeepStrictEqual(
        syntheticNetworkFixture.sandbox_profile_identity,
        receipt.sandbox_profile_identity,
      )
      && isDeepStrictEqual(
        syntheticNetworkFixture.calibration_profile_identity,
        receipt.calibration_profile_identity,
      )
      && receipt.real_home_write_target_absent === true
      && receipt.external_write_target_absent === true
      && receipt.calibration_roots_cleaned === true
      && receipt.false_accepts === 0
      && parentPids.size === 1
      && new Set(childPids).size === childPids.length
      && captures.home_read_denial.capture.exit_status !== 0
      && captures.home_write_denial.capture.exit_status !== 0
      && captures.external_write_denial.capture.exit_status !== 0
      && captures.owned_write_allowance.capture.exit_status === 0
      && captures.home_read_denial.stderr.length > 0
      && captures.home_write_denial.stderr.length > 0
      && captures.external_write_denial.stderr.length > 0
      && Array.isArray(
        receipt.excluded_real_home_config_and_credential_paths,
      )
      && receipt.excluded_real_home_config_and_credential_paths.length > 0
      && new Set(
        receipt.excluded_real_home_config_and_credential_paths,
      ).size
        === receipt.excluded_real_home_config_and_credential_paths.length
      && receipt.excluded_real_home_config_and_credential_paths.every(
        (entry) =>
          typeof entry === "string"
          && isAbsolute(entry)
          && resolve(entry) === entry
          && (
            entry === realHome.path
            || entry.startsWith(`${realHome.path}${sep}`)
          ),
      ),
    "ADAPTER_CONTROL_INVALID",
    "accepted binary sandbox calibration semantics drifted",
    path,
  );
  return {
    identity: boundIdentity,
    receipt,
    child_pids: childPids,
    parent_pid: [...parentPids][0],
    profile_identity: profileIdentity,
    calibration_profile_identity: calibrationProfileIdentity,
    synthetic_network_fixture_identity: syntheticNetworkFixtureIdentity,
  };
}

function validateAcceptedAdapterProcess(root, manifestState) {
  const path = "raw/accepted-adapter-control/process/receipt.json";
  const receipt = readCanonicalBoundJson(
    root,
    manifestState,
    path,
    "accepted adapter aggregate receipt",
  ).value;
  exactKeys(
    receipt,
    ACCEPTED_ADAPTER_PROCESS_KEYS,
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter aggregate receipt",
    path,
  );
  exactKeys(
    receipt.cleanup_verified,
    [
      "accepted_p1_129_source_preserved_read_only",
      "all_current_b2_fixture_roots_absent",
      "sandbox_calibration_roots_absent",
    ],
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter aggregate cleanup",
    path,
  );
  const authority = validateAcceptedP1129AuthorityBundle(
    root,
    manifestState,
    receipt.accepted_authority_bundle_identity,
  );
  const calibration = validateAcceptedBinarySandboxCalibration(
    root,
    manifestState,
    receipt.sandbox_calibration_identity,
  );
  const proofLimitsIdentity = validateBoundArtifactDescriptor(
    receipt.proof_limits_identity,
    manifestState,
    "accepted adapter proof limits",
    "raw/accepted-adapter-control/proof-limits.json",
  );
  const sourceFormalRoot = validateLiveDirectoryIdentity(
    receipt.source_formal_root,
    ACCEPTED_P1_129_FORMAL_ROOT,
    "accepted P1-129 formal matrix root",
    path,
  );
  assert(
    proofLimitsIdentity.path
      === "raw/accepted-adapter-control/proof-limits.json",
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter proof-limits path drifted",
    path,
  );
  assert(
    Array.isArray(receipt.current_b2_scan_receipt_identities)
      && receipt.current_b2_scan_receipt_identities.length === 12
      && Array.isArray(receipt.current_b2_distinct_child_pids)
      && receipt.current_b2_distinct_child_pids.length === 12
      && receipt.current_b2_distinct_child_pids.every(
        (pid) => Number.isSafeInteger(pid) && pid > 0,
      )
      && new Set(receipt.current_b2_distinct_child_pids).size === 12,
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter current B2 receipt set is not exact",
    path,
  );
  const receiptIdentities = receipt.current_b2_scan_receipt_identities.map(
    (identity, index) => {
      const taskId = ACCEPTED_TASK_IDS[Math.floor(index / 2)];
      const profileId = index % 2 === 0 ? "B2_A" : "B2_B";
      const validated = validateBoundArtifactDescriptor(
        identity,
        manifestState,
        `current B2 receipt ${taskId}:${profileId}`,
      );
      assert(
        validated.path === [
          "raw/accepted-adapter-control/current-b2-reexecution",
          taskId,
          profileId,
          "receipt.json",
        ].join("/"),
        "ADAPTER_CONTROL_INVALID",
        `current B2 receipt ${taskId}:${profileId} path drifted`,
        validated.path,
      );
      return validated;
    },
  );
  validateAcceptedControlClaimFlags(
    receipt,
    ACCEPTED_P1_129_CLAIM_BOUNDARY,
    "accepted adapter aggregate receipt",
    path,
  );
  assert(
    receipt.schema_version === "p1-165-accepted-adapter-control/v4"
      && receipt.task_id === TASK_ID
      && receipt.mode === ACCEPTED_ADAPTER_AGGREGATE_MODE
      && receipt.status === "PASS"
      && isDeepStrictEqual(
        receipt.accepted_authority_bundle_identity,
        authority.identity,
      )
      && isDeepStrictEqual(
        receipt.sandbox_calibration_identity,
        calibration.identity,
      )
      && receipt.cleanup_verified
        .all_current_b2_fixture_roots_absent === true
      && receipt.cleanup_verified
        .sandbox_calibration_roots_absent === true
      && receipt.cleanup_verified
        .accepted_p1_129_source_preserved_read_only === true,
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter aggregate fixed semantics drifted",
    path,
  );
  return {
    receipt,
    authority,
    calibration,
    proof_limits_identity: proofLimitsIdentity,
    source_formal_root: sourceFormalRoot,
    current_b2_receipt_identities: receiptIdentities,
  };
}

function validateAdapterProofIdentityMap(
  entry,
  proofPrefix,
  manifestState,
  label,
  indexPath,
) {
  exactKeys(
    entry.artifacts,
    Object.keys(ACCEPTED_ADAPTER_PROOF_FILES),
    "ADAPTER_CONTROL_INVALID",
    `${label} artifact map`,
    indexPath,
  );
  const artifacts = new Map();
  for (const [role, suffix] of Object.entries(ACCEPTED_ADAPTER_PROOF_FILES)) {
    const expectedPath = `${proofPrefix}/${suffix}`;
    const identity = validateBoundArtifactDescriptor(
      entry.artifacts[role],
      manifestState,
      `${label} ${role}`,
      expectedPath,
    );
    assert(
      identity.path === expectedPath,
      "ADAPTER_CONTROL_INVALID",
      `${label} ${role} path is not exact`,
      indexPath,
    );
    artifacts.set(role, identity);
  }
  assert(
    new Set([...artifacts.values()].map((identity) => identity.path)).size
      === Object.keys(ACCEPTED_ADAPTER_PROOF_FILES).length,
    "ADAPTER_CONTROL_INVALID",
    `${label} artifact paths are not unique`,
    indexPath,
  );
  return artifacts;
}

function validateAcceptedContentInventory(value, label, path) {
  exactKeys(
    value,
    CONTENT_INVENTORY_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
    path,
  );
  const rootIdentity = validateSourceDirectoryIdentity(
    value.root_identity,
    `${label} root`,
    path,
  );
  assert(
    Array.isArray(value.entries)
      && value.entries.length >= 1
      && value.entries.length <= B2_SCAN_SOURCE_FILE_COUNT_MAX,
    "ADAPTER_CONTROL_INVALID",
    `${label} entry count is invalid`,
    path,
  );
  let totalBytes = 0;
  let previousPath = null;
  for (const entry of value.entries) {
    exactKeys(
      entry,
      CONTENT_INVENTORY_ENTRY_KEYS,
      "ADAPTER_CONTROL_INVALID",
      `${label} entry`,
      path,
    );
    safeRelativePath(entry.relative_path, `${label} relative path`);
    assert(
      entry.type === "REGULAR_FILE"
        && entry.nlink === 1
        && Number.isSafeInteger(entry.mode)
        && entry.mode >= 0
        && Number.isSafeInteger(entry.byte_length)
        && entry.byte_length >= 0
        && entry.byte_length <= B2_SCAN_SOURCE_SINGLE_FILE_BYTES_MAX
        && typeof entry.sha256 === "string"
        && /^[0-9a-f]{64}$/.test(entry.sha256)
        && (
          previousPath === null
          || previousPath.localeCompare(entry.relative_path) < 0
        ),
      "ADAPTER_CONTROL_INVALID",
      `${label} entry semantics drifted`,
      path,
    );
    previousPath = entry.relative_path;
    totalBytes += entry.byte_length;
  }
  assert(
    value.file_count === value.entries.length
      && value.total_byte_length === totalBytes
      && totalBytes <= B2_SCAN_SOURCE_TOTAL_BYTES_MAX
      && value.entry_set_sha256 === sha256(
        Buffer.from(canonicalJson(value.entries), "utf8"),
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} aggregate identity drifted`,
    path,
  );
  return { ...value, root_identity: rootIdentity };
}

function validateCurrentB2FreshReceipt({
  root,
  manifestState,
  processState,
  identity,
  taskId,
  profileId,
  physicalProof,
}) {
  const prefix = [
    "raw/accepted-adapter-control/current-b2-reexecution",
    taskId,
    profileId,
  ].join("/");
  const expectedPath = `${prefix}/receipt.json`;
  const boundIdentity = validateBoundArtifactDescriptor(
    identity,
    manifestState,
    `current B2 receipt ${taskId}:${profileId}`,
    expectedPath,
  );
  assert(
    boundIdentity.path === expectedPath,
    "ADAPTER_CONTROL_INVALID",
    `current B2 receipt ${taskId}:${profileId} path drifted`,
    expectedPath,
  );
  const receipt = readCanonicalBoundJson(
    root,
    manifestState,
    expectedPath,
    `current B2 receipt ${taskId}:${profileId}`,
  ).value;
  exactKeys(
    receipt,
    CURRENT_B2_REEXECUTION_KEYS,
    "ADAPTER_CONTROL_INVALID",
    `current B2 receipt ${taskId}:${profileId}`,
    expectedPath,
  );
  const sourceExecutableIdentity = validateBoundArtifactDescriptor(
    receipt.source_accepted_executable_identity,
    manifestState,
    `current B2 source accepted executable ${taskId}:${profileId}`,
  );
  const sandboxProfileIdentity = validateBoundArtifactDescriptor(
    receipt.sandbox_profile_identity,
    manifestState,
    `current B2 sandbox profile ${taskId}:${profileId}`,
    `${prefix}/sandbox-profile.sb`,
  );
  const calibrationIdentity = validateBoundArtifactDescriptor(
    receipt.sandbox_calibration_identity,
    manifestState,
    `current B2 sandbox calibration ${taskId}:${profileId}`,
  );
  assert(
    sandboxProfileIdentity.path === `${prefix}/sandbox-profile.sb`
      && isDeepStrictEqual(
        calibrationIdentity,
        processState.calibration.identity,
      )
      && isDeepStrictEqual(
        sourceExecutableIdentity,
        physicalProof.executable_identity,
      ),
    "ADAPTER_CONTROL_INVALID",
    `current B2 identity joins drifted: ${taskId}:${profileId}`,
    expectedPath,
  );
  exactKeys(
    receipt.selected_executable_identity,
    BYTES_IDENTITY_KEYS,
    "ADAPTER_CONTROL_INVALID",
    `current B2 selected executable ${taskId}:${profileId}`,
    expectedPath,
  );
  exactKeys(
    receipt.fresh_scan_result_identity,
    BYTES_IDENTITY_KEYS,
    "ADAPTER_CONTROL_INVALID",
    `current B2 fresh scan result ${taskId}:${profileId}`,
    expectedPath,
  );
  const sourceBefore = validateAcceptedContentInventory(
    receipt.source_inventory_before,
    `current B2 source inventory before ${taskId}:${profileId}`,
    expectedPath,
  );
  const sourceAfter = validateAcceptedContentInventory(
    receipt.source_inventory_after,
    `current B2 source inventory after ${taskId}:${profileId}`,
    expectedPath,
  );
  assert(
    isDeepStrictEqual(sourceBefore, sourceAfter)
      && receipt.source_inventory_unchanged === true,
    "ADAPTER_CONTROL_INVALID",
    `current B2 source changed: ${taskId}:${profileId}`,
    expectedPath,
  );
  assert(
    Array.isArray(receipt.selected_scan_source_inventory)
      && receipt.selected_scan_source_inventory.length
        === sourceBefore.entries.length,
    "ADAPTER_CONTROL_INVALID",
    `current B2 selected source inventory is invalid: ${taskId}:${profileId}`,
    expectedPath,
  );
  let previousPath = null;
  for (const entry of receipt.selected_scan_source_inventory) {
    exactKeys(
      entry,
      ["byte_length", "relative_path", "sha256"],
      "ADAPTER_CONTROL_INVALID",
      `current B2 selected source entry ${taskId}:${profileId}`,
      expectedPath,
    );
    safeRelativePath(
      entry.relative_path,
      `current B2 selected source path ${taskId}:${profileId}`,
    );
    assert(
      Number.isSafeInteger(entry.byte_length)
        && entry.byte_length >= 0
        && typeof entry.sha256 === "string"
        && /^[0-9a-f]{64}$/.test(entry.sha256)
        && (
          previousPath === null
          || previousPath.localeCompare(entry.relative_path) < 0
        ),
      "ADAPTER_CONTROL_INVALID",
      `current B2 selected source entry drifted: ${taskId}:${profileId}`,
      expectedPath,
    );
    previousPath = entry.relative_path;
  }
  const projectedSource = sourceBefore.entries.map((entry) => ({
    relative_path: entry.relative_path,
    byte_length: entry.byte_length,
    sha256: entry.sha256,
  }));
  exactKeys(
    receipt.cleanup_verified,
    ["fixture_root_absent"],
    "ADAPTER_CONTROL_INVALID",
    `current B2 cleanup ${taskId}:${profileId}`,
    expectedPath,
  );
  exactKeys(
    receipt.external_effects,
    Object.keys(FALSE_EXTERNAL_EFFECTS),
    "ADAPTER_CONTROL_INVALID",
    `current B2 external effects ${taskId}:${profileId}`,
    expectedPath,
  );
  const fixtureRootIdentity = validateSourceDirectoryIdentity(
    receipt.fixture_root_identity,
    `current B2 fixture root ${taskId}:${profileId}`,
    expectedPath,
  );
  assert(
    receipt.cleanup_verified.fixture_root_absent === true
      && !existsSync(fixtureRootIdentity.path)
      && !existsSync(sourceBefore.root_identity.path)
      && isDeepStrictEqual(receipt.external_effects, FALSE_EXTERNAL_EFFECTS)
      && isDeepStrictEqual(
        receipt.selected_scan_source_inventory,
        projectedSource,
      )
      && receipt.selected_scan_source_inventory_sha256
        === sourceBefore.entry_set_sha256
      && receipt.selected_executable_identity.byte_length
        === sourceExecutableIdentity.byte_length
      && receipt.selected_executable_identity.sha256
        === sourceExecutableIdentity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `current B2 selected inputs or cleanup drifted: ${taskId}:${profileId}`,
    expectedPath,
  );
  exactKeys(
    receipt.process,
    ACCEPTED_ADAPTER_CALIBRATION_CAPTURE_KEYS,
    "ADAPTER_CONTROL_INVALID",
    `current B2 process ${taskId}:${profileId}`,
    expectedPath,
  );
  const stdoutIdentity = validateBoundArtifactDescriptor(
    receipt.process.stdout_identity,
    manifestState,
    `current B2 stdout ${taskId}:${profileId}`,
  );
  const stderrIdentity = validateBoundArtifactDescriptor(
    receipt.process.stderr_identity,
    manifestState,
    `current B2 stderr ${taskId}:${profileId}`,
  );
  const sandboxProfileBytes = readBoundBytes(
    root,
    manifestState,
    sandboxProfileIdentity.path,
    `current B2 sandbox profile ${taskId}:${profileId}`,
  ).bytes;
  const sandboxProfileText = sandboxProfileBytes.toString("utf8");
  const stdout = readBoundBytes(
    root,
    manifestState,
    stdoutIdentity.path,
    `current B2 stdout ${taskId}:${profileId}`,
  ).bytes;
  exactKeys(
    receipt.process.environment,
    ["HOME", "LANG", "LC_ALL", "PATH", "TZ"],
    "ADAPTER_CONTROL_INVALID",
    `current B2 closed environment ${taskId}:${profileId}`,
    expectedPath,
  );
  assert(
    stdoutIdentity.path === `${prefix}/process/stdout.log`
      && stderrIdentity.path === `${prefix}/process/stderr.log`
      && sourceBefore.root_identity.path
        === join(fixtureRootIdentity.path, "source")
      && isDeepStrictEqual(
        receipt.target_argv,
        [
          join(fixtureRootIdentity.path, "sourcelens-analyzer"),
          "scan",
          "--repo-path",
          sourceBefore.root_identity.path,
        ],
      )
      && isDeepStrictEqual(
        receipt.process.argv,
        [
          SANDBOX_EXEC_PATH,
          "-p",
          sandboxProfileText,
          ...receipt.target_argv,
        ],
      )
      && isDeepStrictEqual(
        receipt.process.environment,
        expectedClosedChildEnvironment(
          join(fixtureRootIdentity.path, "synthetic-home"),
        ),
      )
      && sandboxProfileText.includes("(allow default)")
      && sandboxProfileText.includes("(deny network*)")
      && !sandboxProfileText.includes("(deny process-fork)")
      && !sandboxProfileText.includes("(deny process-exec)")
      && !sandboxProfileText.includes("(allow process-exec")
      && !sandboxProfileText.includes("(deny mach-")
      && !/(^|\n)\(deny file-read\*\)\s*(\n|$)/.test(sandboxProfileText)
      && receipt.process.cwd === fixtureRootIdentity.path
      && Number.isSafeInteger(receipt.process.parent_pid)
      && receipt.process.parent_pid > 0
      && Number.isSafeInteger(receipt.process.child_pid)
      && receipt.process.child_pid > 0
      && receipt.process.child_pid !== receipt.process.parent_pid
      && receipt.process.exit_status === 0
      && receipt.process.signal === null
      && receipt.process.timed_out === false
      && Number.isSafeInteger(receipt.process.timeout_ms)
      && receipt.process.timeout_ms > 0
      && receipt.process.error_code === null
      && Number.isFinite(Date.parse(receipt.process.started_at))
      && Number.isFinite(Date.parse(receipt.process.stopped_at))
      && Date.parse(receipt.process.started_at)
        <= Date.parse(receipt.process.stopped_at)
      && receipt.fresh_scan_result_identity.byte_length === stdout.length
      && receipt.fresh_scan_result_identity.sha256 === sha256(stdout)
      && receipt.fresh_scan_result_identity.byte_length
        === stdoutIdentity.byte_length
      && receipt.fresh_scan_result_identity.sha256 === stdoutIdentity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `current B2 process Evidence drifted: ${taskId}:${profileId}`,
    expectedPath,
  );
  validateAcceptedControlClaimFlags(
    receipt,
    B2_REEXECUTION_CLAIM_BOUNDARY,
    `current B2 receipt ${taskId}:${profileId}`,
    expectedPath,
  );
  assert(
    receipt.schema_version
        === "p1-165-current-b2-sandbox-reexecution/v1"
      && receipt.task_id === TASK_ID
      && receipt.target_task_id === taskId
      && receipt.profile_id === profileId
      && receipt.fresh_scan_matches_accepted_except_repo_relocation === true
      && receipt.executable_identity_unchanged === true
      && receipt.runtime_verified === true
      && receipt.status === "PASS",
    "ADAPTER_CONTROL_INVALID",
    `current B2 fixed semantics drifted: ${taskId}:${profileId}`,
    expectedPath,
  );
  return {
    identity: boundIdentity,
    receipt,
    child_pid: receipt.process.child_pid,
    fresh_scan_bytes: stdout,
    projected_source_inventory: projectedSource,
  };
}

function loadAcceptedAdapterIndex(root, manifestState, atomicCommit) {
  const path = "raw/accepted-adapter-control/adapter-result-index.json";
  const processState = validateAcceptedAdapterProcess(root, manifestState);
  const value = readBoundJson(
    root,
    manifestState,
    path,
    "accepted adapter result index",
  );
  exactKeys(
    value,
    ACCEPTED_ADAPTER_INDEX_KEYS,
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter result index",
    path,
  );
  const proofLimitsIdentity = validateBoundArtifactDescriptor(
    value.proof_limits_identity,
    manifestState,
    "accepted adapter proof-limit receipt",
    "raw/accepted-adapter-control/proof-limits.json",
  );
  const sandboxCalibrationIdentity = validateBoundArtifactDescriptor(
    value.sandbox_calibration_identity,
    manifestState,
    "accepted adapter sandbox-calibration receipt",
    "raw/accepted-adapter-control/sandbox-calibration/receipt.json",
  );
  const authorityIdentity = validateBoundArtifactDescriptor(
    value.accepted_authority_bundle_identity,
    manifestState,
    "accepted adapter authority bundle",
    "raw/accepted-adapter-control/accepted-p1-129/authority-bundle.json",
  );
  const sourceFormalRoot = validateLiveDirectoryIdentity(
    value.source_formal_root,
    ACCEPTED_P1_129_FORMAL_ROOT,
    "accepted adapter source formal root",
    path,
  );
  assert(
    proofLimitsIdentity.path
        === "raw/accepted-adapter-control/proof-limits.json"
      && isDeepStrictEqual(
        sandboxCalibrationIdentity,
        processState.calibration.identity,
      )
      && isDeepStrictEqual(
        authorityIdentity,
        processState.authority.identity,
      )
      && isDeepStrictEqual(
        sourceFormalRoot,
        processState.source_formal_root,
      )
      && isDeepStrictEqual(
        proofLimitsIdentity,
        processState.proof_limits_identity,
      ),
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter index control identities drifted",
    path,
  );
  const proofLimits = readCanonicalBoundJson(
    root,
    manifestState,
    proofLimitsIdentity.path,
    "accepted adapter proof-limit receipt",
  ).value;
  exactKeys(
    proofLimits,
    [
      "case_count",
      "limits",
      "maximum_observed_depth",
      "planned_file_count",
      "planned_total_byte_length",
      "planning_mode",
      "schema_version",
      "source_matrix_root",
      "status",
      "task_id",
    ],
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter proof-limit receipt",
    proofLimitsIdentity.path,
  );
  exactKeys(
    proofLimits.limits,
    [
      "b2_binary_max_bytes",
      "b2_tree_file_max_bytes",
      "b2_tree_file_max_count",
      "b2_tree_max_depth",
      "b2_tree_total_max_bytes",
      "proof_file_max_bytes",
      "proof_file_max_count",
      "proof_max_depth",
      "proof_total_max_bytes",
    ],
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter proof-limit values",
    proofLimitsIdentity.path,
  );
  assert(
    value.schema_version === "p1-165-accepted-adapter-result-index/v4"
      && value.task_id === TASK_ID
      && value.entries !== null
      && typeof value.entries === "object"
      && !Array.isArray(value.entries)
      && proofLimits.schema_version
        === "p1-165-accepted-adapter-proof-limits/v1"
      && proofLimits.task_id === TASK_ID
      && proofLimits.source_matrix_root
        === ACCEPTED_P1_129_FORMAL_ROOT
      && proofLimits.case_count === 36
      && proofLimits.planning_mode
        === "METADATA_ONLY_BEFORE_ANY_PROOF_CONTENT_READ"
      && proofLimits.status === "PASS"
      && isDeepStrictEqual(proofLimits.limits, {
        proof_file_max_bytes:
          ACCEPTED_ADAPTER_PROOF_SINGLE_FILE_BYTES_MAX,
        proof_total_max_bytes: ACCEPTED_ADAPTER_PROOF_TOTAL_BYTES_MAX,
        proof_file_max_count: ACCEPTED_ADAPTER_PROOF_FILE_COUNT_MAX,
        proof_max_depth: ACCEPTED_ADAPTER_PROOF_DEPTH_MAX,
        b2_tree_file_max_bytes: B2_SCAN_SOURCE_SINGLE_FILE_BYTES_MAX,
        b2_tree_total_max_bytes: B2_SCAN_SOURCE_TOTAL_BYTES_MAX,
        b2_tree_file_max_count: B2_SCAN_SOURCE_FILE_COUNT_MAX,
        b2_tree_max_depth: B2_SCAN_SOURCE_DEPTH_MAX,
        b2_binary_max_bytes: ACCEPTED_ADAPTER_EXECUTABLE_BYTES_MAX,
      }),
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter result index schema or source roots are invalid",
    path,
  );
  validateAcceptedControlClaimFlags(
    value,
    ACCEPTED_P1_129_CLAIM_BOUNDARY,
    "accepted adapter result index",
    path,
  );
  const expectedKeys = ACCEPTED_TASK_IDS.flatMap((taskId) =>
    PROFILE_ORDER.map((profileId) => `${taskId}:${profileId}`)).sort();
  assert(
    isDeepStrictEqual(Object.keys(value.entries).sort(), expectedKeys),
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter result index does not contain exact 36 controls",
    path,
  );
  const entries = new Map();
  const proofRoots = new Set();
  const expectedProofPaths = new Set();
  const plannedProofPaths = new Set();
  let maximumPlannedDepth = 0;
  for (const key of expectedKeys) {
    const [taskId, profileId] = key.split(":");
    const profile = PROFILE_EXPECTATIONS[profileId];
    const entry = value.entries[key];
    exactKeys(
      entry,
      ACCEPTED_ADAPTER_INDEX_ENTRY_KEYS,
      "ADAPTER_CONTROL_INVALID",
      `accepted adapter ${key}`,
      path,
    );
    validateAcceptedTaskSpecDescriptor(
      entry.canonical_task_spec_identity,
      taskId,
      `accepted adapter ${key} canonical TaskSpec`,
    );
    const proofPrefix = [
      "raw/accepted-adapter-control/proofs/positive",
      taskId,
      profileId,
    ].join("/");
    safeRelativePath(proofPrefix, `accepted adapter ${key} proof prefix`);
    const sourceCaseRoot = join(
      ACCEPTED_P1_129_FORMAL_ROOT,
      "positive",
      taskId,
      profileId,
    );
    const sourceCaseRootIdentity = validateLiveDirectoryIdentity(
      entry.source_case_root_identity,
      sourceCaseRoot,
      `accepted adapter ${key} source case root`,
      path,
    );
    const sourceWorkerOutputRoot = join(sourceCaseRoot, "worker-output");
    const stagedProofRoot = join(
      atomicCommit.staged_root_path,
      ...proofPrefix.split("/"),
    );
    const finalProofRoot = containedPath(
      root,
      proofPrefix,
      `accepted adapter ${key} proof root`,
    );
    assert(
      entry.target_task_id === taskId
        && entry.profile_id === profileId
        && entry.adapter_id === profile.adapter_id
        && entry.repetition_id === profile.repetition_id
        && entry.source_case_root === sourceCaseRoot
        && entry.source_worker_output_root === sourceWorkerOutputRoot
        && entry.proof_prefix === proofPrefix
        && entry.staged_proof_root === stagedProofRoot
        && !existsSync(stagedProofRoot)
        && existsSync(finalProofRoot)
        && lstatSync(finalProofRoot).isDirectory()
        && !lstatSync(finalProofRoot).isSymbolicLink(),
      "ADAPTER_CONTROL_INVALID",
      `accepted adapter ${key} source/staged/final roots drifted`,
      path,
    );
    proofRoots.add(finalProofRoot);
    const artifacts = validateAdapterProofIdentityMap(
      entry,
      proofPrefix,
      manifestState,
      `accepted adapter ${key}`,
      path,
    );
    for (const identity of artifacts.values()) {
      expectedProofPaths.add(identity.path);
      plannedProofPaths.add(identity.path);
      maximumPlannedDepth = Math.max(
        maximumPlannedDepth,
        identity.path.slice(`${proofPrefix}/`.length).split("/").length,
      );
    }
    let currentB2 = null;
    if (profile.adapter_id === "B2") {
      const b2Identity = validateBoundArtifactDescriptor(
        entry.b2_scan_proof_identity,
        manifestState,
        `accepted adapter ${key} B2 scan proof`,
        `${proofPrefix}/b2-scan-proof.json`,
      );
      assert(
        b2Identity.path === `${proofPrefix}/b2-scan-proof.json`
          && entry.b2_physical_proof !== null,
        "ADAPTER_CONTROL_INVALID",
        `accepted adapter ${key} B2 proof is incomplete`,
        path,
      );
      expectedProofPaths.add(b2Identity.path);
      exactKeys(
        entry.b2_physical_proof,
        [
          "analyzer_artifact_identities",
          "executable_identity",
          "executable_source_mode",
          "scan_source_identities",
        ],
        "ADAPTER_CONTROL_INVALID",
        `accepted adapter ${key} B2 physical proof`,
        path,
      );
      assert(
        Array.isArray(
          entry.b2_physical_proof.analyzer_artifact_identities,
        )
          && entry.b2_physical_proof
            .analyzer_artifact_identities.length === 10
          && Array.isArray(entry.b2_physical_proof.scan_source_identities)
          && entry.b2_physical_proof.scan_source_identities.length >= 1
          && entry.b2_physical_proof.scan_source_identities.length
            <= B2_SCAN_SOURCE_FILE_COUNT_MAX,
        "ADAPTER_CONTROL_INVALID",
        `accepted adapter ${key} B2 physical inventory is not bounded`,
        path,
      );
      for (const identity of [
        entry.b2_physical_proof.executable_identity,
        ...entry.b2_physical_proof.analyzer_artifact_identities,
        ...entry.b2_physical_proof.scan_source_identities,
      ]) {
        const validated = validateBoundArtifactDescriptor(
          identity,
          manifestState,
          `accepted adapter ${key} B2 physical artifact`,
        );
        expectedProofPaths.add(validated.path);
        plannedProofPaths.add(validated.path);
        maximumPlannedDepth = Math.max(
          maximumPlannedDepth,
          validated.path.slice(`${proofPrefix}/`.length).split("/").length,
        );
      }
      const currentIdentityIndex =
        ACCEPTED_TASK_IDS.indexOf(taskId) * 2
        + (profileId === "B2_A" ? 0 : 1);
      const currentIdentity =
        processState.current_b2_receipt_identities[currentIdentityIndex];
      const entryCurrentIdentity = validateBoundArtifactDescriptor(
        entry.current_b2_reexecution_identity,
        manifestState,
        `accepted adapter ${key} current B2 receipt`,
        currentIdentity.path,
      );
      exactKeys(
        entry.current_b2_cleanup_verified,
        ["fixture_root_absent"],
        "ADAPTER_CONTROL_INVALID",
        `accepted adapter ${key} current B2 cleanup`,
        path,
      );
      assert(
        isDeepStrictEqual(entryCurrentIdentity, currentIdentity)
          && entry.current_b2_cleanup_verified.fixture_root_absent === true,
        "ADAPTER_CONTROL_INVALID",
        `accepted adapter ${key} current B2 join drifted`,
        path,
      );
      currentB2 = validateCurrentB2FreshReceipt({
        root,
        manifestState,
        processState,
        identity: entryCurrentIdentity,
        taskId,
        profileId,
        physicalProof: entry.b2_physical_proof,
      });
      assert(
        currentB2.child_pid
          === processState.receipt
            .current_b2_distinct_child_pids[currentIdentityIndex],
        "ADAPTER_CONTROL_INVALID",
        `accepted adapter ${key} current B2 child PID drifted`,
        path,
      );
    } else {
      assert(
        entry.b2_scan_proof_identity === null
          && entry.b2_physical_proof === null
          && entry.current_b2_reexecution_identity === null
          && entry.current_b2_cleanup_verified === null,
        "ADAPTER_CONTROL_INVALID",
        `accepted adapter ${key} non-B2 entry carries B2 proof`,
        path,
      );
    }
    entries.set(key, {
      ...entry,
      artifacts,
      adapter_descriptor: {
        path: artifacts.get("adapter_result").path,
        byte_length: artifacts.get("adapter_result").byte_length,
        sha256: artifacts.get("adapter_result").sha256,
      },
      b2_scan_descriptor: entry.b2_scan_proof_identity === null
        ? null
        : {
            path: entry.b2_scan_proof_identity.path,
            byte_length: entry.b2_scan_proof_identity.byte_length,
            sha256: entry.b2_scan_proof_identity.sha256,
          },
      source_case_root: sourceCaseRoot,
      source_case_root_identity: sourceCaseRootIdentity,
      source_worker_output_root: sourceWorkerOutputRoot,
      final_proof_root: finalProofRoot,
      current_b2: currentB2,
      accepted_authority_bundle_identity: processState.authority.identity,
    });
  }
  assert(
    entries.size === 36 && proofRoots.size === 36,
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter proof roots are not exact and distinct",
    path,
  );
  const proofBase = "raw/accepted-adapter-control/proofs/";
  const actualProofPaths = [...manifestState.byPath.keys()]
    .filter((entryPath) => entryPath.startsWith(proofBase))
    .sort();
  const expectedProofPathList = [...expectedProofPaths].sort();
  const plannedProofPathList = [...plannedProofPaths].sort();
  let proofTotalBytes = 0;
  for (const proofPath of expectedProofPathList) {
    const identity = manifestState.byPath.get(proofPath);
    const proofDepth = proofPath.slice(proofBase.length)
      .split("/").length;
    assert(
      identity !== undefined
        && identity.byte_length
          <= ACCEPTED_ADAPTER_PROOF_SINGLE_FILE_BYTES_MAX
        && proofDepth <= ACCEPTED_ADAPTER_PROOF_DEPTH_MAX,
      "ADAPTER_CONTROL_INVALID",
      "accepted adapter compact proof exceeds its per-file or depth cap",
      proofPath,
    );
    proofTotalBytes += identity.byte_length;
  }
  const plannedProofTotalBytes = plannedProofPathList.reduce(
    (total, proofPath) =>
      total + manifestState.byPath.get(proofPath).byte_length,
    0,
  );
  assert(
    expectedProofPathList.length <= ACCEPTED_ADAPTER_PROOF_FILE_COUNT_MAX
      && proofTotalBytes <= ACCEPTED_ADAPTER_PROOF_TOTAL_BYTES_MAX
      && isDeepStrictEqual(actualProofPaths, expectedProofPathList)
      && proofLimits.planned_file_count === plannedProofPathList.length
      && proofLimits.planned_total_byte_length === plannedProofTotalBytes
      && proofLimits.maximum_observed_depth === maximumPlannedDepth,
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter compact proof closed inventory or aggregate cap drifted",
    path,
  );
  return {
    entries,
    process: processState,
    proof_roots: proofRoots,
  };
}

function validateEmbeddedDescriptor(
  descriptor,
  expectedIdentity,
  expectedSourcePath,
  label,
  path,
) {
  exactKeys(
    descriptor,
    ARTIFACT_DESCRIPTOR_KEYS,
    "ADAPTER_CONTROL_INVALID",
    label,
    path,
  );
  assert(
    descriptor.path === expectedSourcePath
      && descriptor.byte_length === expectedIdentity.byte_length
      && descriptor.sha256 === expectedIdentity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} does not bind exact copied raw bytes`,
    path,
  );
  return descriptor;
}

function validateAcceptedExecutionDescriptor({
  descriptor,
  executionRequest,
  profile,
  taskId,
  label,
  path,
}) {
  exactKeys(
    descriptor,
    [
      "adapter_id",
      "adapter_version",
      "allowed_tool_classes",
      "argv",
      "descriptor_id",
      "executable",
      "expected_exit_codes",
      "forbidden_features",
      "input_bindings",
      "limits",
      "output_policy",
      "requested_effects",
      "schema_version",
      "timeout_seconds",
      "working_directory",
    ],
    "ADAPTER_CONTROL_INVALID",
    `${label} execution descriptor`,
    path,
  );
  const expectations = {
    B0: {
      allowed: [],
      forbidden: [
        "repository_tools",
        "search",
        "terminal",
        "graph",
        "memory",
        "iteration",
        "execution_feedback",
        "hidden_data",
        "network",
      ],
      limits: {
        max_cost_usd: 0,
        max_model_tokens: 1024,
        max_tool_calls: 0,
      },
      timeout_seconds: 10,
    },
    B1: {
      allowed: [
        "file_listing",
        "file_read",
        "lexical_search",
        "structured_patch",
        "verification_command",
      ],
      forbidden: [
        "sourcelens_graph",
        "ranker",
        "memory",
        "additional_agent",
        "hidden_data",
        "network",
      ],
      limits: {
        max_cost_usd: 0,
        max_model_tokens: 0,
        max_tool_calls: 8,
      },
      timeout_seconds: 30,
    },
    B2: {
      allowed: ["repository_analysis.scan"],
      forbidden: ["write", "egress", "remote", "hidden_data", "network"],
      limits: {
        max_cost_usd: 0,
        max_model_tokens: 0,
        max_tool_calls: 1,
      },
      timeout_seconds: 60,
    },
  }[profile.adapter_id];
  assert(
    expectations !== undefined,
    "ADAPTER_CONTROL_INVALID",
    `${label} adapter descriptor class is unknown`,
    path,
  );
  exactKeys(
    descriptor.executable,
    ["byte_length", "path", "realpath", "sha256", "type"],
    "ADAPTER_CONTROL_INVALID",
    `${label} executable identity`,
    path,
  );
  exactKeys(
    descriptor.limits,
    ["max_cost_usd", "max_model_tokens", "max_tool_calls"],
    "ADAPTER_CONTROL_INVALID",
    `${label} descriptor limits`,
    path,
  );
  exactKeys(
    descriptor.output_policy,
    [
      "atomic_unique_owned_root",
      "nonowned_cleanup_allowed",
      "preexisting_target_allowed",
      "symlink_component_allowed",
    ],
    "ADAPTER_CONTROL_INVALID",
    `${label} output policy`,
    path,
  );
  const executablePath =
    `evaluation-harness/adapters/p1-125-six-task-parameterized/`
    + `${profile.adapter_id.toLowerCase()}-entry.mjs`;
  validateCanonicalRelativeArtifactDescriptor(
    {
      path: descriptor.executable.path,
      byte_length: descriptor.executable.byte_length,
      sha256: descriptor.executable.sha256,
    },
    executablePath,
    `${label} current canonical executable`,
    ACCEPTED_ADAPTER_EXECUTABLE_BYTES_MAX,
  );
  const expectedInputKeys = profile.adapter_id === "B2"
    ? [
        "adapter_input",
        "b2_source_manifest",
        "response_format",
        "task_source_program",
      ]
    : ["adapter_input", "response_format"];
  exactKeys(
    descriptor.input_bindings,
    expectedInputKeys,
    "ADAPTER_CONTROL_INVALID",
    `${label} descriptor input bindings`,
    path,
  );
  validateCanonicalRelativeArtifactDescriptor(
    descriptor.input_bindings.response_format,
    "evaluation-harness/datasets/p1-representative-task-dataset-v1/"
      + "shared/response-format.json",
    `${label} response format`,
  );
  assert(
    descriptor.schema_version === "p1-125-execution-descriptor/v1"
      && descriptor.adapter_id === profile.adapter_id
      && descriptor.adapter_version
        === "p1-125-six-task-parameterized-v1"
      && descriptor.descriptor_id
        === `P1-125-${taskId}-${profile.adapter_id}`
      && isDeepStrictEqual(descriptor.allowed_tool_classes, expectations.allowed)
      && isDeepStrictEqual(descriptor.forbidden_features, expectations.forbidden)
      && isDeepStrictEqual(descriptor.limits, expectations.limits)
      && descriptor.timeout_seconds === expectations.timeout_seconds
      && descriptor.working_directory === "REPOSITORY_ROOT"
      && isDeepStrictEqual(descriptor.argv, [
        process.execPath,
        "EXECUTABLE",
        "--request",
        "EXECUTION_REQUEST",
        "--run-root",
        "OUTPUT_ROOT",
        "--sentinel",
        "TARGET_SENTINEL",
      ])
      && isDeepStrictEqual(descriptor.expected_exit_codes, [0])
      && descriptor.executable.type === "REGULAR_FILE"
      && descriptor.executable.realpath
        === `REPOSITORY_ROOT/${executablePath}`
      && isDeepStrictEqual(
        descriptor.output_policy,
        {
          atomic_unique_owned_root: true,
          nonowned_cleanup_allowed: false,
          preexisting_target_allowed: false,
          symlink_component_allowed: false,
        },
      )
      && isDeepStrictEqual(descriptor.requested_effects, FALSE_EXTERNAL_EFFECTS)
      && isDeepStrictEqual(
        descriptor.input_bindings.adapter_input,
        executionRequest.adapter_input,
      )
      && (
        profile.adapter_id !== "B2"
        || (
          isDeepStrictEqual(
            descriptor.input_bindings.b2_source_manifest,
            executionRequest.auxiliary_inputs.b2_source_manifest,
          )
          && isDeepStrictEqual(
            descriptor.input_bindings.task_source_program,
            executionRequest.auxiliary_inputs.task_source_program,
          )
        )
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} execution descriptor semantics or input joins drifted`,
    path,
  );
  exactKeys(
    executionRequest.limits,
    [
      "max_cost_usd",
      "max_model_tokens",
      "max_tool_calls",
      "wall_clock_seconds",
    ],
    "ADAPTER_CONTROL_INVALID",
    `${label} execution request limits`,
    path,
  );
  assert(
    isDeepStrictEqual(executionRequest.limits, {
      ...descriptor.limits,
      wall_clock_seconds: descriptor.timeout_seconds,
    }),
    "ADAPTER_CONTROL_INVALID",
    `${label} execution request limits do not equal descriptor limits`,
    path,
  );
}

function validateAcceptedAdapterTrace({
  traceEvents,
  commandLedger,
  adapterResult,
  runRecord,
  adapterResultIdentity,
  executionRequest,
  request,
  entry,
  label,
  path,
}) {
  assert(
    traceEvents.length === adapterResult.actions.length + 2,
    "ADAPTER_CONTROL_INVALID",
    `${label} trace event count is not action-count + 2`,
    path,
  );
  for (const [index, event] of traceEvents.entries()) {
    assert(
      event.schema_version === "p1-125-observable-trace-event/v1"
        && event.run_id === runRecord.run_id
        && event.task_id === runRecord.task_id
        && event.adapter_id === runRecord.adapter_id
        && event.adapter_version === runRecord.adapter_version
        && event.system_configuration_id === runRecord.system_configuration_id
        && event.repetition_id === runRecord.repetition_id
        && event.event_sequence === index + 1,
      "ADAPTER_CONTROL_INVALID",
      `${label} trace join or sequence drifted`,
      path,
    );
  }
  const start = traceEvents[0];
  exactKeys(
    start,
    [
      "adapter_id",
      "adapter_version",
      "command",
      "dataset_version",
      "environment_snapshot_id",
      "event_sequence",
      "input_bindings",
      "limits",
      "record_type",
      "repetition_id",
      "requested_external_effects",
      "run_id",
      "schema_version",
      "started_at",
      "system_configuration_id",
      "task_id",
    ],
    "ADAPTER_CONTROL_INVALID",
    `${label} trace start event`,
    path,
  );
  const sourceRequestDescriptor = {
    path: `${entry.source_case_root}/request.json`,
    byte_length: entry.artifacts.get("request").byte_length,
    sha256: entry.artifacts.get("request").sha256,
  };
  const expectedStartBindings = {
    adapter_input: executionRequest.adapter_input,
    auxiliary_inputs: executionRequest.auxiliary_inputs,
    descriptor: request.execution_descriptor,
    environment_snapshot: request.environment_snapshot,
    request: sourceRequestDescriptor,
    system_configuration: request.system_configuration,
    task_spec: request.task_spec,
  };
  assert(
    start.record_type === "p1_125_run_started"
      && start.dataset_version === "1.0.0"
      && start.environment_snapshot_id
        === "ENV-SOURCELENS-P1-REP-NODE20-STDLIB-1"
      && Number.isFinite(Date.parse(start.started_at))
      && isDeepStrictEqual(start.input_bindings, expectedStartBindings)
      && isDeepStrictEqual(start.limits, executionRequest.limits)
      && isDeepStrictEqual(
        start.requested_external_effects,
        FALSE_EXTERNAL_EFFECTS,
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} trace start provenance drifted`,
    path,
  );
  assert(
    isDeepStrictEqual(traceEvents[0].command, commandLedger)
      && isDeepStrictEqual(
        traceEvents.slice(1, -1).map((event) => event.action),
        adapterResult.actions,
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} trace does not bind the command and exact action sequence`,
    path,
  );
  const terminal = traceEvents.at(-1);
  assert(
    terminal.terminal_status === "completed"
      && terminal.stop_reason_code === "agent_complete"
      && isDeepStrictEqual(
        terminal.result_identity,
        {
          path: "adapter-result.json",
          byte_length: adapterResultIdentity.byte_length,
          sha256: adapterResultIdentity.sha256,
        },
      )
      && isDeepStrictEqual(terminal.usage, adapterResult.usage)
      && isDeepStrictEqual(
        terminal.observed_external_effects,
        FALSE_EXTERNAL_EFFECTS,
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} terminal trace event is not independently bound`,
    path,
  );
}

function validateAcceptedAdapterSpecificResult({
  adapterResult,
  commandLedger,
  executionRequest,
  profile,
  label,
  path,
}) {
  if (profile.adapter_id === "B0") {
    assert(
      adapterResult.usage.tool_calls === 0
        && adapterResult.actions.length === 1
        && adapterResult.actions[0].action_type
          === "frozen_result_admission"
        && adapterResult.actions[0].tool_class === null
        && adapterResult.provenance.kind
          === "QUALITY_FROZEN_PROVIDER_NEUTRAL_CONFORMANCE_RESULT"
        && adapterResult.rollback.required === false
        && adapterResult.rollback.status
          === "NOT_APPLICABLE_NO_SOURCE_MUTATION"
        && adapterResult.actions[0].input_sha256
          === executionRequest.adapter_input.sha256
        && adapterResult.actions[0].output_sha256
          === executionRequest.adapter_input.sha256,
      "ADAPTER_CONTROL_INVALID",
      `${label} B0 result semantics drifted`,
      path,
    );
    return;
  }
  if (profile.adapter_id === "B1") {
    const expectedTools = [
      "file_listing",
      "file_read",
      "lexical_search",
      "structured_patch",
      "verification_command",
      "verification_command",
    ];
    assert(
      adapterResult.usage.tool_calls === 6
        && adapterResult.actions.length === 6
        && isDeepStrictEqual(
          adapterResult.actions.map((action) => action.tool_class),
          expectedTools,
        )
        && adapterResult.provenance.kind
          === "QUALITY_FROZEN_FINITE_TOOL_CONFORMANCE_PROGRAM"
        && adapterResult.rollback.status === "PASS_EXACT"
        && Array.isArray(adapterResult.rollback.files)
        && adapterResult.rollback.files.length >= 1
        && adapterResult.rollback.files.every((entry) => entry.matches === true)
        && Array.isArray(adapterResult.verification_ledgers)
        && adapterResult.verification_ledgers.length === 2,
      "ADAPTER_CONTROL_INVALID",
      `${label} B1 result semantics drifted`,
      path,
    );
    for (const [index, verification] of
      adapterResult.verification_ledgers.entries()) {
      const ledger = validatePassingCommandLedger(
        verification.ledger,
        `${label} B1 verification ledger ${index + 1}`,
        path,
      );
      const action = adapterResult.actions[index + 4];
      assert(
        action.command_id === verification.command_id
          && action.exit_code === ledger.exit_status
          && action.expected_exit_matched === true
          && action.stdout_sha256 === ledger.stdout_sha256
          && action.stderr_sha256 === ledger.stderr_sha256,
        "ADAPTER_CONTROL_INVALID",
        `${label} B1 action-ledger join drifted`,
        path,
      );
    }
  }
}

function independentStableAdapterAction(action) {
  const value = {
    sequence: action.sequence,
    action_type: action.action_type,
    tool_class: action.tool_class,
    exit_code: action.exit_code,
  };
  for (const key of [
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
  ]) {
    if (Object.hasOwn(action, key)) value[key] = action[key];
  }
  return value;
}

function independentStableAdapterSemantics(adapterResult) {
  const rollback = {
    required: adapterResult.rollback.required
      ?? (
        adapterResult.rollback.status
          !== "NOT_APPLICABLE_NO_SOURCE_MUTATION"
      ),
    status: adapterResult.rollback.status,
  };
  for (const key of [
    "pre_tree_source_sha256",
    "post_patch_source_sha256",
    "post_rollback_source_sha256",
    "source_exact_after_scan",
  ]) {
    if (Object.hasOwn(adapterResult.rollback, key)) {
      rollback[key] = adapterResult.rollback[key];
    }
  }
  if (Array.isArray(adapterResult.rollback.files)) {
    rollback.files = adapterResult.rollback.files.map((entry) => ({
      path: entry.path,
      sha256: entry.sha256,
      byte_length: entry.byte_length,
      matches: entry.matches,
    }));
  }
  const provenance = {
    kind: adapterResult.provenance.kind,
    live_model_invoked: adapterResult.provenance.live_model_invoked,
    provider_invoked: adapterResult.provenance.provider_invoked,
    model_performance_sample: adapterResult.provenance.model_performance_sample,
  };
  const semantics = {
    result: adapterResult.result,
    provenance,
    actions: adapterResult.actions.map(independentStableAdapterAction),
    requested_external_effects: adapterResult.requested_external_effects,
    observed_external_effects: adapterResult.observed_external_effects,
    source_mutation_observed: adapterResult.source_mutation_observed,
    rollback,
  };
  if (adapterResult.adapter_id === "B2") {
    provenance.p0_binding = adapterResult.provenance.p0_binding;
    semantics.scan = {
      scan_result_schema_version:
        adapterResult.scan_result.scan_result_schema_version,
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

function validateAcceptedAdapterProofEntry({
  root,
  manifestState,
  entry,
  taskId,
  profileId,
}) {
  const label = `accepted adapter ${taskId}:${profileId}`;
  const profile = PROFILE_EXPECTATIONS[profileId];
  const parsed = {};
  for (const role of [
    "b0_result",
    "b1_program",
    "environment_snapshot",
    "execution_descriptor",
    "request",
    "adapter_execution_request",
    "adapter_command_ledger",
    "adapter_result",
    "run_record",
    "stable_projection",
    "target_executed",
  ]) {
    const identity = entry.artifacts.get(role);
    parsed[role] = readCanonicalBoundJson(
      root,
      manifestState,
      identity.path,
      `${label} ${role}`,
    ).value;
  }
  const traceIdentity = entry.artifacts.get("trace");
  const traceArtifact = readBoundBytes(
    root,
    manifestState,
    traceIdentity.path,
    `${label} trace`,
  );
  const traceEvents = parseJsonLines(
    traceArtifact.bytes,
    `${label} trace`,
    traceIdentity.path,
  );
  const canonicalTraceBytes = Buffer.from(
    `${traceEvents.map((event) => canonicalJson(event)).join("\n")}\n`,
    "utf8",
  );
  assert(
    traceArtifact.bytes.equals(canonicalTraceBytes),
    "ADAPTER_CONTROL_INVALID",
    `${label} trace is not canonical JSONL`,
    traceIdentity.path,
  );

  const request = parsed.request;
  exactKeys(
    request,
    [
      "adapter_id",
      "case_id",
      "environment_snapshot",
      "execution_descriptor",
      "expected_descriptor_identity",
      "expected_outcome",
      "mode",
      "nonowned_fixture",
      "output_root",
      "repetition_id",
      "request_id",
      "requested_effects",
      "schema_version",
      "system_configuration",
      "target_sentinel_path",
      "task_spec",
    ],
    "ADAPTER_CONTROL_INVALID",
    `${label} outer request`,
    entry.artifacts.get("request").path,
  );
  const taskSpec = validateAcceptedTaskSpecProvenanceDescriptor(
    request.task_spec,
    taskId,
    `${label} TaskSpec`,
  );
  const systemConfiguration = validateAcceptedRepositoryProvenanceDescriptor(
    request.system_configuration,
    profile.configuration_path,
    `${label} SystemConfiguration`,
  ).value;
  const sourceExecutionDescriptorPath =
    `${entry.source_case_root}/execution-descriptor.json`;
  const sourceEnvironmentPath =
    `${entry.source_case_root}/environment-snapshot.json`;
  validateEmbeddedDescriptor(
    request.execution_descriptor,
    entry.artifacts.get("execution_descriptor"),
    sourceExecutionDescriptorPath,
    `${label} execution descriptor`,
    entry.artifacts.get("request").path,
  );
  validateEmbeddedDescriptor(
    request.environment_snapshot,
    entry.artifacts.get("environment_snapshot"),
    sourceEnvironmentPath,
    `${label} environment snapshot`,
    entry.artifacts.get("request").path,
  );
  validateBytesIdentity(
    request.expected_descriptor_identity,
    bytesIdentityFromBound(entry.artifacts.get("execution_descriptor")),
    `${label} expected descriptor identity`,
    entry.artifacts.get("request").path,
  );
  assert(
    request.schema_version === "p1-125-worker-request/v1"
      && request.request_id.startsWith(`P1-125-${taskId}-${profileId}-`)
      && request.case_id === `${taskId}-${profileId}`
      && request.mode === "POSITIVE"
      && request.adapter_id === profile.adapter_id
      && request.repetition_id === profile.repetition_id
      && request.output_root === entry.source_worker_output_root
      && request.target_sentinel_path
        === `${entry.source_worker_output_root}/target-executed`
      && request.nonowned_fixture === null
      && request.task_spec.byte_length
        === entry.canonical_task_spec_identity.byte_length
      && request.task_spec.sha256
        === entry.canonical_task_spec_identity.sha256
      && request.expected_outcome.status === "PASS"
      && request.expected_outcome.reason_code === "PASS"
      && request.expected_outcome.pre_execution === false
      && isDeepStrictEqual(request.requested_effects, FALSE_EXTERNAL_EFFECTS)
      && taskSpec.task_id === taskId
      && systemConfiguration.configuration_id === profile.configuration_id
      && systemConfiguration.adapter_id === profile.adapter_id,
    "ADAPTER_CONTROL_INVALID",
    `${label} outer request identity or accepted inputs drifted`,
    entry.artifacts.get("request").path,
  );

  const executionDescriptor = parsed.execution_descriptor;
  assert(
    executionDescriptor.schema_version
      === "p1-125-execution-descriptor/v1"
      && executionDescriptor.adapter_id === profile.adapter_id
      && executionDescriptor.adapter_version
        === "p1-125-six-task-parameterized-v1"
      && executionDescriptor.descriptor_id === `P1-125-${taskId}-${profile.adapter_id}`
      && isDeepStrictEqual(
        executionDescriptor.requested_effects,
        FALSE_EXTERNAL_EFFECTS,
      )
      && isDeepStrictEqual(executionDescriptor.expected_exit_codes, [0])
      && executionDescriptor.working_directory === "REPOSITORY_ROOT"
      && executionDescriptor.argv[0] === process.execPath
      && executionDescriptor.argv[1] === "EXECUTABLE",
    "ADAPTER_CONTROL_INVALID",
    `${label} execution descriptor drifted`,
    entry.artifacts.get("execution_descriptor").path,
  );

  const executionRequest = parsed.adapter_execution_request;
  exactKeys(
    executionRequest,
    [
      "adapter_id",
      "adapter_input",
      "auxiliary_inputs",
      "environment_snapshot",
      "external_effects",
      "limits",
      "record_type",
      "repetition_id",
      "run_id",
      "run_root",
      "schema_version",
      "sentinel_path",
      "system_configuration",
      "task_spec",
    ],
    "ADAPTER_CONTROL_INVALID",
    `${label} adapter execution request`,
    entry.artifacts.get("adapter_execution_request").path,
  );
  validateEmbeddedDescriptor(
    executionRequest.environment_snapshot,
    entry.artifacts.get("environment_snapshot"),
    sourceEnvironmentPath,
    `${label} execution environment`,
    entry.artifacts.get("adapter_execution_request").path,
  );
  assert(
    isDeepStrictEqual(executionRequest.task_spec, request.task_spec)
      && isDeepStrictEqual(
        executionRequest.system_configuration,
        request.system_configuration,
      )
      && executionRequest.schema_version === "1.0"
      && executionRequest.record_type
        === "p1_125_adapter_execution_request"
      && executionRequest.adapter_id === profile.adapter_id
      && executionRequest.repetition_id === profile.repetition_id
      && executionRequest.run_root === entry.source_worker_output_root
      && executionRequest.sentinel_path
        === `${entry.source_worker_output_root}/target-executed`
      && isDeepStrictEqual(
        executionRequest.external_effects,
        FALSE_EXTERNAL_EFFECTS,
      )
      && executionRequest.limits.max_cost_usd === 0
      && executionRequest.limits.wall_clock_seconds
        === executionDescriptor.timeout_seconds,
    "ADAPTER_CONTROL_INVALID",
    `${label} adapter execution request drifted`,
    entry.artifacts.get("adapter_execution_request").path,
  );
  if (profile.adapter_id === "B0") {
    validateEmbeddedDescriptor(
      executionRequest.adapter_input,
      entry.artifacts.get("b0_result"),
      `${entry.source_case_root}/b0-result.json`,
      `${label} B0 input`,
      entry.artifacts.get("adapter_execution_request").path,
    );
    assert(
      isDeepStrictEqual(executionRequest.auxiliary_inputs, {}),
      "ADAPTER_CONTROL_INVALID",
      `${label} B0 auxiliary input set is not empty`,
    );
  } else if (profile.adapter_id === "B1") {
    validateEmbeddedDescriptor(
      executionRequest.adapter_input,
      entry.artifacts.get("b1_program"),
      `${entry.source_case_root}/b1-program.json`,
      `${label} B1 input`,
      entry.artifacts.get("adapter_execution_request").path,
    );
    assert(
      isDeepStrictEqual(executionRequest.auxiliary_inputs, {}),
      "ADAPTER_CONTROL_INVALID",
      `${label} B1 auxiliary input set is not empty`,
    );
  } else {
    validateAcceptedRepositoryProvenanceDescriptor(
      executionRequest.adapter_input,
      "evaluation-harness/fixtures/p1-125-six-task-parameterized/b2-p0-binding.json",
      `${label} exact P0 binding`,
    );
    validateAcceptedRepositoryProvenanceDescriptor(
      executionRequest.auxiliary_inputs.b2_source_manifest,
      "evaluation-harness/fixtures/p1-125-six-task-parameterized/b2-p0-source-manifest.json",
      `${label} P0 source manifest`,
    );
    validateEmbeddedDescriptor(
      executionRequest.auxiliary_inputs.task_source_program,
      entry.artifacts.get("b1_program"),
      `${entry.source_case_root}/b1-program.json`,
      `${label} B2 task source program`,
      entry.artifacts.get("adapter_execution_request").path,
    );
    assert(
      isDeepStrictEqual(
        Object.keys(executionRequest.auxiliary_inputs).sort(),
        ["b2_source_manifest", "task_source_program"],
      ),
      "ADAPTER_CONTROL_INVALID",
      `${label} B2 auxiliary input set drifted`,
    );
  }
  validateAcceptedExecutionDescriptor({
    descriptor: executionDescriptor,
    executionRequest,
    profile,
    taskId,
    label,
    path: entry.artifacts.get("execution_descriptor").path,
  });

  const commandLedger = validatePassingCommandLedger(
    parsed.adapter_command_ledger,
    `${label} adapter command ledger`,
    entry.artifacts.get("adapter_command_ledger").path,
  );
  const adapterResultIdentity = entry.artifacts.get("adapter_result");
  assert(
    commandLedger.cwd === ACCEPTED_P1_129_WORKTREE_ROOT
      && commandLedger.argv.length === 8
      && commandLedger.argv[0] === process.execPath
      && commandLedger.argv[1] === resolve(
        ACCEPTED_P1_129_WORKTREE_ROOT,
        `evaluation-harness/adapters/p1-125-six-task-parameterized/${profile.adapter_id.toLowerCase()}-entry.mjs`,
      )
      && commandLedger.argv[2] === "--request"
      && commandLedger.argv[3]
        === `${entry.source_worker_output_root}/adapter-execution-request.json`
      && commandLedger.argv[4] === "--run-root"
      && commandLedger.argv[5] === entry.source_worker_output_root
      && commandLedger.argv[6] === "--sentinel"
      && commandLedger.argv[7]
        === `${entry.source_worker_output_root}/target-executed`
      && commandLedger.stdout_byte_length === adapterResultIdentity.byte_length
      && commandLedger.stdout_sha256 === adapterResultIdentity.sha256
      && commandLedger.stderr_byte_length === 0
      && commandLedger.stderr_sha256 === sha256(Buffer.alloc(0)),
    "ADAPTER_CONTROL_INVALID",
    `${label} actual adapter command is not bound to copied raw result bytes`,
    entry.artifacts.get("adapter_command_ledger").path,
  );

  const adapterResult = parsed.adapter_result;
  const runRecord = parsed.run_record;
  exactKeys(
    runRecord,
    RUN_RECORD_KEYS,
    "ADAPTER_CONTROL_INVALID",
    `${label} RunRecord`,
    entry.artifacts.get("run_record").path,
  );
  assert(
    adapterResult.schema_version === "1.0"
      && adapterResult.record_type === "p1_125_documented_adapter_result"
      && adapterResult.run_id === executionRequest.run_id
      && adapterResult.task_id === taskId
      && adapterResult.adapter_id === profile.adapter_id
      && adapterResult.adapter_version
        === "p1-125-six-task-parameterized-v1"
      && adapterResult.system_configuration_id === profile.configuration_id
      && adapterResult.repetition_id === profile.repetition_id
      && adapterResult.terminal_status === "completed"
      && adapterResult.stop_reason_code === "agent_complete"
      && adapterResult.source_mutation_observed === false
      && isDeepStrictEqual(
        adapterResult.requested_external_effects,
        FALSE_EXTERNAL_EFFECTS,
      )
      && isDeepStrictEqual(
        adapterResult.observed_external_effects,
        FALSE_EXTERNAL_EFFECTS,
      )
      && Array.isArray(adapterResult.actions)
      && adapterResult.actions.length >= 1
      && adapterResult.actions.every((action, index) =>
        action.sequence === index + 1
          && action.action_id === `${adapterResult.run_id}:${index + 1}`)
      && runRecord.schema_version === "1.0"
      && runRecord.run_id === adapterResult.run_id
      && runRecord.task_id === taskId
      && runRecord.adapter_id === profile.adapter_id
      && runRecord.adapter_version === adapterResult.adapter_version
      && runRecord.system_configuration_id === profile.configuration_id
      && runRecord.repetition_id === profile.repetition_id
      && runRecord.terminal_status === "completed"
      && runRecord.stop_reason_code === "agent_complete"
      && isDeepStrictEqual(runRecord.usage, adapterResult.usage)
      && runRecord.trace_ref === "trace.jsonl"
      && isDeepStrictEqual(runRecord.test_artifact_refs, [
        "adapter-result.json",
      ])
      && runRecord.patch_ref
        === (profile.adapter_id === "B1" ? "adapter-result.json" : null)
      && runRecord.verification_ref === null
      && runRecord.invalid_run_reason === null
      && isDeepStrictEqual(runRecord.policy_violations, [])
      && isDeepStrictEqual(runRecord.error_taxonomy, []),
    "ADAPTER_CONTROL_INVALID",
    `${label} AdapterResult/RunRecord join drifted`,
    entry.artifacts.get("adapter_result").path,
  );
  exactKeys(
    runRecord.artifact_checksums,
    [
      "adapter_input",
      "adapter_result",
      "command_stderr",
      "command_stdout",
      "descriptor",
      "environment_snapshot",
      "system_configuration",
      "task_spec",
      "trace",
    ],
    "ADAPTER_CONTROL_INVALID",
    `${label} RunRecord checksums`,
    entry.artifacts.get("run_record").path,
  );
  assert(
    runRecord.artifact_checksums.adapter_input
        === executionRequest.adapter_input.sha256
      && runRecord.artifact_checksums.adapter_result
        === adapterResultIdentity.sha256
      && runRecord.artifact_checksums.command_stdout
        === adapterResultIdentity.sha256
      && runRecord.artifact_checksums.command_stderr
        === sha256(Buffer.alloc(0))
      && runRecord.artifact_checksums.descriptor
        === entry.artifacts.get("execution_descriptor").sha256
      && runRecord.artifact_checksums.environment_snapshot
        === entry.artifacts.get("environment_snapshot").sha256
      && runRecord.artifact_checksums.system_configuration
        === request.system_configuration.sha256
      && runRecord.artifact_checksums.task_spec === request.task_spec.sha256
      && runRecord.artifact_checksums.trace === traceIdentity.sha256,
    "ADAPTER_CONTROL_INVALID",
    `${label} RunRecord does not bind exact raw proof bytes`,
    entry.artifacts.get("run_record").path,
  );
  const sentinelIdentity = entry.artifacts.get("target_executed");
  assert(
    parsed.target_executed.schema_version === "1.0"
      && parsed.target_executed.record_type
        === "p1_125_target_execution_sentinel"
      && parsed.target_executed.run_id === adapterResult.run_id
      && parsed.target_executed.adapter_id === profile.adapter_id
      && parsed.target_executed.repetition_id === profile.repetition_id
      && Number.isSafeInteger(parsed.target_executed.owner_pid)
      && parsed.target_executed.owner_pid > 0
      && isDeepStrictEqual(adapterResult.target_execution_sentinel, {
        byte_length: sentinelIdentity.byte_length,
        sha256: sentinelIdentity.sha256,
      }),
    "ADAPTER_CONTROL_INVALID",
    `${label} target execution sentinel is not bound`,
    sentinelIdentity.path,
  );
  validateAcceptedAdapterSpecificResult({
    adapterResult,
    commandLedger,
    executionRequest,
    profile,
    label,
    path: adapterResultIdentity.path,
  });
  validateAcceptedAdapterTrace({
    traceEvents,
    commandLedger,
    adapterResult,
    runRecord,
    adapterResultIdentity,
    executionRequest,
    request,
    entry,
    label,
    path: traceIdentity.path,
  });
  const stableProjection = parsed.stable_projection;
  assert(
    stableProjection.schema_version === "p1-125-stable-replay-projection/v1"
      && stableProjection.record_type
        === "p1_125_documented_adapter_stable_projection"
      && stableProjection.task_id === taskId
      && stableProjection.adapter_id === profile.adapter_id
      && stableProjection.adapter_version === adapterResult.adapter_version
      && stableProjection.system_configuration_id === "PAIR_CONFIGURATION"
      && stableProjection.terminal_status === "completed"
      && stableProjection.stop_reason_code === "agent_complete"
      && isDeepStrictEqual(
        stableProjection.adapter_semantics,
        independentStableAdapterSemantics(adapterResult),
      ),
    "ADAPTER_CONTROL_INVALID",
    `${label} stable projection is not bound to raw adapter semantics`,
    entry.artifacts.get("stable_projection").path,
  );
  return {
    adapter_result: adapterResult,
    b1_program: parsed.b1_program,
    command_ledger: commandLedger,
    run_record: runRecord,
    request,
    execution_request: executionRequest,
    stable_projection: stableProjection,
    trace_events: traceEvents,
  };
}

function validateB2PhysicalIdentityList({
  value,
  expectedRelativePaths,
  manifestState,
  label,
  path,
}) {
  assert(
    Array.isArray(value) && value.length === expectedRelativePaths.length,
    "B2_SCAN_LEDGER_INVALID",
    `${label} count drifted`,
    path,
  );
  const identities = [];
  for (const [index, expectedPath] of expectedRelativePaths.entries()) {
    const identity = validateBoundArtifactDescriptor(
      value[index],
      manifestState,
      `${label} ${index + 1}`,
      expectedPath,
    );
    assert(
      identity.path === expectedPath,
      "B2_SCAN_LEDGER_INVALID",
      `${label} path/order drifted`,
      path,
    );
    identities.push(identity);
  }
  assert(
    new Set(identities.map((identity) => identity.path)).size
      === identities.length,
    "B2_SCAN_LEDGER_INVALID",
    `${label} paths are duplicated`,
    path,
  );
  return identities;
}

function inventoryAcceptedScanSource(
  sourceRoot,
  label,
  {
    depth_max: depthMax = B2_SCAN_SOURCE_DEPTH_MAX,
    file_count_max: fileCountMax = B2_SCAN_SOURCE_FILE_COUNT_MAX,
    single_file_bytes_max: singleFileBytesMax =
      B2_SCAN_SOURCE_SINGLE_FILE_BYTES_MAX,
    total_bytes_max: totalBytesMax = B2_SCAN_SOURCE_TOTAL_BYTES_MAX,
  } = {},
) {
  const entries = [];
  let totalBytes = 0;
  const rootStat = lstatSync(sourceRoot);
  assert(
    rootStat.isDirectory()
      && !rootStat.isSymbolicLink()
      && realpathSync(sourceRoot) === sourceRoot,
    "B2_SCAN_LEDGER_INVALID",
    `${label} root is not a real directory`,
    sourceRoot,
  );
  const visit = (directory, depth) => {
    assert(
      depth <= depthMax && realpathSync(directory) === directory,
      "B2_SCAN_LEDGER_INVALID",
      `${label} exceeds its directory depth or contains an alias`,
      directory,
    );
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stat = lstatSync(path);
      assert(
        !stat.isSymbolicLink(),
        "B2_SCAN_LEDGER_INVALID",
        `${label} contains a symlink`,
        path,
      );
      if (stat.isDirectory()) {
        visit(path, depth + 1);
      } else {
        assert(
          stat.isFile()
            && stat.nlink === 1
            && entries.length + 1 <= fileCountMax
            && stat.size <= singleFileBytesMax
            && totalBytes + stat.size <= totalBytesMax,
          "B2_SCAN_LEDGER_INVALID",
          `${label} exceeds its type, link, file-count, or byte cap`,
          path,
        );
        let descriptor = null;
        try {
          descriptor = openSync(
            path,
            fsConstants.O_RDONLY
              | (fsConstants.O_NOFOLLOW ?? 0)
              | (fsConstants.O_NONBLOCK ?? 0),
          );
          const opened = fstatSync(descriptor);
          assert(
            opened.isFile()
              && opened.dev === stat.dev
              && opened.ino === stat.ino
              && opened.uid === stat.uid
              && opened.nlink === stat.nlink
              && opened.size === stat.size
              && opened.size <= singleFileBytesMax,
            "B2_SCAN_LEDGER_INVALID",
            `${label} file changed while opening`,
            path,
          );
          const bytes = readFileSync(descriptor);
          const afterFd = fstatSync(descriptor);
          const afterPath = lstatSync(path);
          assert(
            bytes.length === opened.size
              && afterFd.dev === opened.dev
              && afterFd.ino === opened.ino
              && afterFd.size === opened.size
              && afterPath.isFile()
              && !afterPath.isSymbolicLink()
              && afterPath.dev === opened.dev
              && afterPath.ino === opened.ino
              && afterPath.size === opened.size
              && afterPath.nlink === 1,
            "B2_SCAN_LEDGER_INVALID",
            `${label} file changed during its bounded read`,
            path,
          );
          totalBytes += bytes.length;
          entries.push({
            relative_path: relative(sourceRoot, path).split(sep).join("/"),
            sha256: sha256(bytes),
            byte_length: bytes.length,
          });
        } finally {
          if (descriptor !== null) closeSync(descriptor);
        }
      }
    }
  };
  visit(sourceRoot, 0);
  return entries.sort((left, right) =>
    left.relative_path.localeCompare(right.relative_path));
}

let acceptedP0SourceManifestCache = null;

function readGitObject(args, label) {
  const result = spawnSync("/usr/bin/git", args, {
    cwd: REPOSITORY_ROOT,
    encoding: null,
    env: {
      LANG: "C",
      LC_ALL: "C",
      PATH: "/usr/bin:/bin",
    },
    maxBuffer: 8 * 1024 * 1024,
    timeout: 60 * 1000,
  });
  const stdout = Buffer.isBuffer(result.stdout)
    ? result.stdout
    : Buffer.from(result.stdout ?? "");
  const stderr = Buffer.isBuffer(result.stderr)
    ? result.stderr
    : Buffer.from(result.stderr ?? "");
  assert(
    result.error === undefined
      && result.status === 0
      && result.signal === null,
    "B2_SCAN_LEDGER_INVALID",
    `${label} Git object lookup failed: ${stderr.toString("utf8")}`,
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  return stdout;
}

function readSingleGitObjectId(spec, label) {
  const text = readGitObject(["rev-parse", spec], label)
    .toString("utf8")
    .trim();
  assert(
    /^[0-9a-f]{40}$/.test(text),
    "B2_SCAN_LEDGER_INVALID",
    `${label} did not resolve to one SHA-1 object`,
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  return text;
}

function loadAcceptedP0SourceManifest() {
  if (acceptedP0SourceManifestCache !== null) {
    return acceptedP0SourceManifestCache;
  }
  const bytes = readRepositoryRegularFileNoFollow(
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
    "accepted P0 analyzer source manifest",
    ACCEPTED_TASK_INPUT_BYTES_MAX,
  ).bytes;
  const manifest = parseJsonBytes(
    bytes,
    "accepted P0 analyzer source manifest",
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  exactKeys(
    manifest,
    [
      "accepted_p0_checkpoint_commit",
      "accepted_p0_checkpoint_tree",
      "accepted_p0_frozen_base_commit",
      "accepted_p0_frozen_base_tree",
      "analyzer_tree",
      "claim_boundary",
      "entries",
      "entry_count",
      "schema_version",
      "source_root",
      "total_byte_length",
    ],
    "B2_SCAN_LEDGER_INVALID",
    "accepted P0 analyzer source manifest",
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  assert(
    manifest.schema_version === "p1-125-b2-p0-source-manifest/v1"
      && manifest.source_root === "analyzer-rust"
      && manifest.accepted_p0_frozen_base_commit
        === ACCEPTED_P0_BINDING.frozen_base_commit
      && manifest.accepted_p0_frozen_base_tree
        === ACCEPTED_P0_BINDING.frozen_base_tree
      && manifest.accepted_p0_checkpoint_commit
        === ACCEPTED_P0_BINDING.checkpoint_commit
      && manifest.accepted_p0_checkpoint_tree
        === ACCEPTED_P0_BINDING.checkpoint_tree
      && manifest.analyzer_tree === ACCEPTED_P0_BINDING.analyzer_subtree
      && manifest.claim_boundary
        === "EXACT_ACCEPTED_P0_ANALYZER_SOURCE_IDENTITY_ONLY"
      && Array.isArray(manifest.entries)
      && manifest.entry_count === 10
      && manifest.entries.length === manifest.entry_count
      && Number.isSafeInteger(manifest.total_byte_length)
      && manifest.total_byte_length > 0,
    "B2_SCAN_LEDGER_INVALID",
    "accepted P0 analyzer source manifest header drifted",
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  assert(
    readSingleGitObjectId(
      `${ACCEPTED_P0_BINDING.frozen_base_commit}^{tree}`,
      "accepted P0 frozen base tree",
    ) === ACCEPTED_P0_BINDING.frozen_base_tree
      && readSingleGitObjectId(
        `${ACCEPTED_P0_BINDING.checkpoint_commit}^{tree}`,
        "accepted P0 checkpoint tree",
      ) === ACCEPTED_P0_BINDING.checkpoint_tree
      && readSingleGitObjectId(
        `${ACCEPTED_P0_BINDING.frozen_base_commit}:analyzer-rust`,
        "accepted P0 frozen analyzer tree",
      ) === ACCEPTED_P0_BINDING.analyzer_subtree
      && readSingleGitObjectId(
        `${ACCEPTED_P0_BINDING.checkpoint_commit}:analyzer-rust`,
        "accepted P0 checkpoint analyzer tree",
      ) === ACCEPTED_P0_BINDING.analyzer_subtree,
    "B2_SCAN_LEDGER_INVALID",
    "accepted P0 commit/tree binding drifted",
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  const listing = readGitObject(
    [
      "ls-tree",
      "-r",
      "--full-tree",
      ACCEPTED_P0_BINDING.frozen_base_commit,
      "--",
      "analyzer-rust",
    ],
    "accepted P0 analyzer closed tree",
  ).toString("utf8").split("\n").filter(Boolean).map((line) => {
    const match = /^(100644|100755) blob ([0-9a-f]{40})\t(.+)$/.exec(line);
    assert(
      match !== null,
      "B2_SCAN_LEDGER_INVALID",
      "accepted P0 analyzer tree contains an unsupported Git entry",
      ACCEPTED_P0_SOURCE_MANIFEST_PATH,
    );
    return {
      mode: match[1] === "100755" ? 0o755 : 0o644,
      git_blob: match[2],
      path: match[3],
    };
  });
  assert(
    listing.length === manifest.entry_count,
    "B2_SCAN_LEDGER_INVALID",
    "accepted P0 analyzer tree is not the manifest's exact closed set",
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  let totalByteLength = 0;
  for (const [index, entry] of manifest.entries.entries()) {
    exactKeys(
      entry,
      ["byte_length", "git_blob", "path", "sha256"],
      "B2_SCAN_LEDGER_INVALID",
      `accepted P0 analyzer source entry ${index + 1}`,
      ACCEPTED_P0_SOURCE_MANIFEST_PATH,
    );
    const listed = listing[index];
    assert(
      typeof entry.path === "string"
        && entry.path.startsWith("analyzer-rust/")
        && entry.path === listed.path
        && entry.git_blob === listed.git_blob
        && /^[0-9a-f]{40}$/.test(entry.git_blob)
        && /^[0-9a-f]{64}$/.test(entry.sha256)
        && Number.isSafeInteger(entry.byte_length)
        && entry.byte_length >= 0
        && readSingleGitObjectId(
          `${ACCEPTED_P0_BINDING.checkpoint_commit}:${entry.path}`,
          `accepted P0 checkpoint blob ${entry.path}`,
        ) === entry.git_blob,
      "B2_SCAN_LEDGER_INVALID",
      `accepted P0 analyzer source entry ${entry.path} drifted`,
      ACCEPTED_P0_SOURCE_MANIFEST_PATH,
    );
    const blob = readGitObject(
      ["cat-file", "blob", entry.git_blob],
      `accepted P0 analyzer blob ${entry.path}`,
    );
    assert(
      blob.length === entry.byte_length && sha256(blob) === entry.sha256,
      "B2_SCAN_LEDGER_INVALID",
      `accepted P0 analyzer blob ${entry.path} differs from the manifest`,
      ACCEPTED_P0_SOURCE_MANIFEST_PATH,
    );
    totalByteLength += entry.byte_length;
  }
  assert(
    totalByteLength === manifest.total_byte_length
      && new Set(manifest.entries.map((entry) => entry.path)).size
        === manifest.entry_count
      && isDeepStrictEqual(
        manifest.entries.map((entry) => entry.path),
        manifest.entries.map((entry) => entry.path).sort(),
      ),
    "B2_SCAN_LEDGER_INVALID",
    "accepted P0 analyzer manifest order, uniqueness, or byte total drifted",
    ACCEPTED_P0_SOURCE_MANIFEST_PATH,
  );
  acceptedP0SourceManifestCache = {
    manifest,
    listing,
  };
  return acceptedP0SourceManifestCache;
}

function validateB2AdapterProof({
  root,
  manifestState,
  entry,
  parsed,
  taskId,
  profileId,
}) {
  const label = `accepted B2 adapter ${taskId}:${profileId}`;
  const proofIdentity = validateBoundArtifactDescriptor(
    entry.b2_scan_proof_identity,
    manifestState,
    `${label} proof identity`,
    `${entry.proof_prefix}/b2-scan-proof.json`,
  );
  const proof = readCanonicalBoundJson(
    root,
    manifestState,
    proofIdentity.path,
    `${label} proof`,
  ).value;
  exactKeys(
    proof,
    [
      "accepted_authority_bundle_identity",
      "accepted_scan_ledger",
      "accepted_scan_result",
      "adapter_command_ledger_identity",
      "adapter_result_identity",
      "canonical_task_spec_identity",
      "claim_boundary",
      "cooperative_local_accepted_evidence_path_residual",
      "current_fresh_child_pid",
      "current_fresh_cleanup_verified",
      "current_fresh_sandbox_reexecution_identity",
      "historical_reviewed_binary_exact_bytes_claim",
      "hostile_global_read_isolation_claim",
      "hostile_process_isolation_claim",
      "operation_id",
      "profile_id",
      "request_identity",
      "run_record_identity",
      "schema_version",
      "selected_physical_proof",
      "source_case_root",
      "source_case_root_identity",
      "source_worker_output_root",
      "stable_projection_identity",
      "staged_proof_root",
      "target_sentinel_identity",
      "target_task_id",
      "task_id",
      "trace_identity",
      "trusted_accepted_source_required",
    ],
    "B2_SCAN_LEDGER_INVALID",
    `${label} proof`,
    proofIdentity.path,
  );
  validateAcceptedControlClaimFlags(
    proof,
    ACCEPTED_P1_129_B2_PROOF_CLAIM_BOUNDARY,
    `${label} proof`,
    proofIdentity.path,
  );
  assert(
    isDeepStrictEqual(
      proof.canonical_task_spec_identity,
      entry.canonical_task_spec_identity,
    ),
    "B2_SCAN_LEDGER_INVALID",
    `${label} proof does not bind the exact canonical TaskSpec`,
    proofIdentity.path,
  );
  for (const [value, role] of [
    [proof.request_identity, "request"],
    [proof.adapter_command_ledger_identity, "adapter_command_ledger"],
    [proof.adapter_result_identity, "adapter_result"],
    [proof.run_record_identity, "run_record"],
    [proof.trace_identity, "trace"],
    [proof.stable_projection_identity, "stable_projection"],
    [proof.target_sentinel_identity, "target_executed"],
  ]) {
    assert(
      isDeepStrictEqual(value, entry.artifacts.get(role)),
      "B2_SCAN_LEDGER_INVALID",
      `${label} proof does not bind exact ${role} bytes`,
      proofIdentity.path,
    );
  }
  assert(
    proof.schema_version === "p1-165-b2-scan-proof/v2"
      && proof.task_id === TASK_ID
      && proof.target_task_id === taskId
      && proof.profile_id === profileId
      && proof.operation_id === ACCEPTED_P0_BINDING.operation_id
      && isDeepStrictEqual(
        proof.accepted_authority_bundle_identity,
        entry.accepted_authority_bundle_identity,
      )
      && proof.source_case_root === entry.source_case_root
      && isDeepStrictEqual(
        proof.source_case_root_identity,
        entry.source_case_root_identity,
      )
      && proof.source_worker_output_root === entry.source_worker_output_root
      && proof.staged_proof_root === entry.staged_proof_root
      && !existsSync(proof.staged_proof_root)
      && isDeepStrictEqual(
        proof.accepted_scan_ledger,
        parsed.adapter_result.scan_ledger,
      )
      && isDeepStrictEqual(
        proof.accepted_scan_result,
        parsed.adapter_result.scan_result,
      )
      && isDeepStrictEqual(
        proof.selected_physical_proof,
        entry.b2_physical_proof,
      )
      && isDeepStrictEqual(
        proof.current_fresh_sandbox_reexecution_identity,
        entry.current_b2.identity,
      )
      && proof.current_fresh_child_pid === entry.current_b2.child_pid
      && isDeepStrictEqual(
        proof.current_fresh_cleanup_verified,
        { fixture_root_absent: true },
      ),
    "B2_SCAN_LEDGER_INVALID",
    `${label} proof fixed fields or raw scan bytes drifted`,
    proofIdentity.path,
  );

  const adapterResult = parsed.adapter_result;
  const action = adapterResult.actions[0];
  assert(
    adapterResult.usage.tool_calls === 1
      && adapterResult.actions.length === 1
      && action.action_type === "tool_call"
      && action.tool_class === ACCEPTED_P0_BINDING.operation_id
      && action.operation_id === ACCEPTED_P0_BINDING.operation_id
      && action.exit_code === 0
      && action.expected_exit_matched === true
      && adapterResult.provenance.kind
        === "EXACT_ACCEPTED_P0_FROZEN_BASE_REAL_SCAN"
      && adapterResult.provenance.live_model_invoked === false
      && adapterResult.provenance.provider_invoked === false
      && adapterResult.provenance.model_performance_sample === false
      && isDeepStrictEqual(
        adapterResult.provenance.p0_binding,
        ACCEPTED_P0_BINDING,
      )
      && adapterResult.rollback.required === false
      && adapterResult.rollback.status
        === "NOT_APPLICABLE_READ_ONLY_SCAN_SOURCE_UNCHANGED"
      && adapterResult.rollback.source_exact_after_scan === true
      && adapterResult.source_mutation_observed === false,
    "B2_SCAN_LEDGER_INVALID",
    `${label} repository_analysis.scan semantics or provenance drifted`,
    entry.artifacts.get("adapter_result").path,
  );
  const scanLedger = validatePassingCommandLedger(
    adapterResult.scan_ledger,
    `${label} repository scan ledger`,
    entry.artifacts.get("adapter_result").path,
  );
  assert(
    scanLedger.argv.length === 4
      && scanLedger.argv[1] === "scan"
      && scanLedger.argv[2] === "--repo-path"
      && scanLedger.cwd === entry.source_worker_output_root
      && scanLedger.argv[0]
        === `${entry.source_worker_output_root}/work/b2-cargo-target/debug/sourcelens-analyzer`
      && scanLedger.argv[3]
        === `${entry.source_worker_output_root}/work/b2-scan-source`
      && action.stdout_sha256 === scanLedger.stdout_sha256
      && action.stderr_sha256 === scanLedger.stderr_sha256,
    "B2_SCAN_LEDGER_INVALID",
    `${label} raw scan ledger does not bind the exact fixed invocation`,
    entry.artifacts.get("adapter_result").path,
  );
  const expectedP0Checks = new Map([
    ["frozen_base_tree", ACCEPTED_P0_BINDING.frozen_base_tree],
    ["checkpoint_tree", ACCEPTED_P0_BINDING.checkpoint_tree],
    ["frozen_analyzer_subtree", ACCEPTED_P0_BINDING.analyzer_subtree],
    ["checkpoint_analyzer_subtree", ACCEPTED_P0_BINDING.analyzer_subtree],
  ]);
  assert(
    Array.isArray(adapterResult.p0_binding_checks)
      && adapterResult.p0_binding_checks.length === 5
      && new Set(
        adapterResult.p0_binding_checks.map((check) => check.id),
      ).size === 5,
    "B2_SCAN_LEDGER_INVALID",
    `${label} P0 binding check set is not exact`,
  );
  for (const check of adapterResult.p0_binding_checks) {
    validatePassingCommandLedger(
      check.ledger,
      `${label} P0 binding check ${check.id}`,
      entry.artifacts.get("adapter_result").path,
    );
    assert(
      expectedP0Checks.has(check.id)
        ? check.expected === expectedP0Checks.get(check.id)
          && check.observed === expectedP0Checks.get(check.id)
        : check.id === "frozen_base_is_checkpoint_ancestor"
          && check.status === "PASS",
      "B2_SCAN_LEDGER_INVALID",
      `${label} P0 binding check ${check.id} drifted`,
    );
  }

  exactKeys(
    entry.b2_physical_proof,
    [
      "analyzer_artifact_identities",
      "executable_identity",
      "executable_source_mode",
      "scan_source_identities",
    ],
    "B2_SCAN_LEDGER_INVALID",
    `${label} physical proof`,
    proofIdentity.path,
  );
  const executablePath =
    `${entry.proof_prefix}/worker-output/work/b2-cargo-target/debug/sourcelens-analyzer`;
  const executableIdentity = validateBoundArtifactDescriptor(
    entry.b2_physical_proof.executable_identity,
    manifestState,
    `${label} executable`,
    executablePath,
  );
  assert(
    executableIdentity.path === executablePath
      && executableIdentity.byte_length === action.executable_byte_length
      && executableIdentity.sha256 === action.executable_sha256
      && executableIdentity.byte_length
        <= ACCEPTED_ADAPTER_EXECUTABLE_BYTES_MAX
      && entry.b2_physical_proof.executable_source_mode === 0o755,
    "B2_SCAN_LEDGER_INVALID",
    `${label} preserved executable identity drifted`,
    executablePath,
  );
  const analyzerArtifacts = adapterResult.materialized_analyzer?.artifacts;
  const acceptedP0Source = loadAcceptedP0SourceManifest();
  const acceptedP0Manifest = acceptedP0Source.manifest;
  assert(
    adapterResult.materialized_analyzer?.subtree
        === acceptedP0Manifest.analyzer_tree
      && Array.isArray(analyzerArtifacts)
      && analyzerArtifacts.length === acceptedP0Manifest.entry_count,
    "B2_SCAN_LEDGER_INVALID",
    `${label} materialized analyzer is not exact`,
  );
  validatePassingCommandLedger(
    adapterResult.materialized_analyzer.listing_ledger,
    `${label} analyzer listing ledger`,
    entry.artifacts.get("adapter_result").path,
  );
  const analyzerPaths = analyzerArtifacts.map(
    (artifact) =>
      `${entry.proof_prefix}/worker-output/work/b2-p0-analyzer/${artifact.relative_path}`,
  );
  const analyzerIdentities = validateB2PhysicalIdentityList({
    value: entry.b2_physical_proof.analyzer_artifact_identities,
    expectedRelativePaths: analyzerPaths,
    manifestState,
    label: `${label} analyzer artifact identities`,
    path: proofIdentity.path,
  });
  for (const [index, identity] of analyzerIdentities.entries()) {
    const artifact = analyzerArtifacts[index];
    const expected = acceptedP0Manifest.entries[index];
    const listed = acceptedP0Source.listing[index];
    exactKeys(
      artifact,
      [
        "byte_length",
        "git_blob",
        "ledger",
        "mode",
        "path",
        "relative_path",
        "sha256",
      ],
      "B2_SCAN_LEDGER_INVALID",
      `${label} materialized analyzer artifact ${index + 1}`,
      entry.artifacts.get("adapter_result").path,
    );
    validatePassingCommandLedger(
      artifact.ledger,
      `${label} materialized analyzer blob ${expected.path}`,
      entry.artifacts.get("adapter_result").path,
    );
    assert(
      artifact.path === expected.path
        && artifact.relative_path
          === expected.path.replace(/^analyzer-rust\//, "")
        && artifact.git_blob === expected.git_blob
        && artifact.sha256 === expected.sha256
        && artifact.byte_length === expected.byte_length
        && artifact.mode === listed.mode
        && identity.byte_length === expected.byte_length
        && identity.sha256 === expected.sha256,
      "B2_SCAN_LEDGER_INVALID",
      `${label} analyzer artifact ${artifact.relative_path} drifted`,
      identity.path,
    );
  }
  const fileManifest = adapterResult.scan_result?.file_tree?.file_manifest;
  assert(
    adapterResult.scan_result?.scan_result_schema_version === 2
      && adapterResult.scan_result.repo_path === scanLedger.argv[3]
      && Array.isArray(fileManifest)
      && fileManifest.length >= 1
      && fileManifest.length <= B2_SCAN_SOURCE_FILE_COUNT_MAX,
    "B2_SCAN_LEDGER_INVALID",
    `${label} raw scan result is not exact`,
    entry.artifacts.get("adapter_result").path,
  );
  const scanSourcePaths = fileManifest.map(
    (file) =>
      `${entry.proof_prefix}/worker-output/work/b2-scan-source/${file.path}`,
  );
  const scanSourceIdentities = validateB2PhysicalIdentityList({
    value: entry.b2_physical_proof.scan_source_identities,
    expectedRelativePaths: scanSourcePaths,
    manifestState,
    label: `${label} scan source identities`,
    path: proofIdentity.path,
  });
  let scanSourceTotalBytes = 0;
  for (const [index, identity] of scanSourceIdentities.entries()) {
    const file = fileManifest[index];
    const sourceDepth = file.path.split("/").length;
    assert(
      identity.byte_length === file.size_bytes
        && identity.sha256 === file.content_hash_sha256
        && identity.byte_length <= B2_SCAN_SOURCE_SINGLE_FILE_BYTES_MAX
        && sourceDepth <= B2_SCAN_SOURCE_DEPTH_MAX,
      "B2_SCAN_LEDGER_INVALID",
      `${label} scan source ${file.path} differs from raw result`,
      identity.path,
    );
    scanSourceTotalBytes += identity.byte_length;
  }
  assert(
    scanSourceTotalBytes <= B2_SCAN_SOURCE_TOTAL_BYTES_MAX,
    "B2_SCAN_LEDGER_INVALID",
    `${label} scan source exceeds its aggregate byte cap`,
    proofIdentity.path,
  );
  const sourceInventory = scanSourceIdentities.map((identity, index) => ({
    relative_path: fileManifest[index].path,
    sha256: identity.sha256,
    byte_length: identity.byte_length,
  }));
  const acceptedTaskSource = parsed.b1_program?.task_source;
  assert(
    parsed.b1_program?.task_id === taskId
      && typeof acceptedTaskSource === "string",
    "B2_SCAN_LEDGER_INVALID",
    `${label} task-source program is invalid`,
    entry.artifacts.get("b1_program").path,
  );
  safeRelativePath(acceptedTaskSource, `${label} accepted task source`);
  const acceptedSourceRoot = resolve(
    REPOSITORY_ROOT,
    ...acceptedTaskSource.split("/"),
  );
  assert(
    existsSync(acceptedSourceRoot)
      && lstatSync(acceptedSourceRoot).isDirectory()
      && !lstatSync(acceptedSourceRoot).isSymbolicLink()
      && isDeepStrictEqual(
        sourceInventory,
        inventoryAcceptedScanSource(acceptedSourceRoot, label),
      ),
    "B2_SCAN_LEDGER_INVALID",
    `${label} preserved scan source differs from the accepted task source`,
    acceptedSourceRoot,
  );
  assert(
    action.source_manifest_sha256
      === sha256(Buffer.from(canonicalJson(sourceInventory), "utf8")),
    "B2_SCAN_LEDGER_INVALID",
    `${label} source manifest identity drifted`,
  );
  const freshScanResult = parseJsonBytes(
    entry.current_b2.fresh_scan_bytes,
    `${label} current fresh scan result`,
    entry.current_b2.identity.path,
  );
  assert(
    isDeepStrictEqual(
      {
        ...freshScanResult,
        repo_path: "RELOCATED_SCAN_SOURCE",
      },
      {
        ...adapterResult.scan_result,
        repo_path: "RELOCATED_SCAN_SOURCE",
      },
    )
      && isDeepStrictEqual(
        entry.current_b2.projected_source_inventory,
        sourceInventory,
      )
      && action.source_manifest_sha256 === sha256(
        Buffer.from(
          canonicalJson(entry.current_b2.projected_source_inventory),
          "utf8",
        ),
      )
      && entry.current_b2.receipt
        .source_accepted_executable_identity.sha256
        === action.executable_sha256
      && entry.current_b2.receipt
        .source_accepted_executable_identity.byte_length
        === action.executable_byte_length,
    "B2_SCAN_LEDGER_INVALID",
    `${label} current fresh scan is not exact`,
    entry.current_b2.identity.path,
  );
  return {
    proof_descriptor: {
      path: proofIdentity.path,
      byte_length: proofIdentity.byte_length,
      sha256: proofIdentity.sha256,
    },
    independently_reexecuted: true,
    sandbox_reexecution_receipt: entry.current_b2.receipt,
    current_b2: entry.current_b2,
  };
}

function validateProductionAdmissionReceipt({
  base,
  artifactPaths = null,
  joinRecord,
  manifestState,
  receipt,
  requestRecord,
  contextRecord,
  transportRecord,
  observerRecord,
  usageRecord,
  admitted,
}) {
  const path = artifactPaths?.receipt
    ?? `${base}/admission/admission-receipt.json`;
  exactKeys(
    receipt,
    ADMISSION_RECEIPT_KEYS,
    "ADMISSION_RECEIPT_INVALID",
    "production admission receipt",
    path,
  );
  assert(
    receipt.schema_version === "p1-165-admission-receipt/v1"
      && receipt.task_id === TASK_ID
      && receipt.status === "ADMITTED"
      && isDeepStrictEqual(receipt.join, joinRecord),
    "ADMISSION_RECEIPT_INVALID",
    "production admission receipt fixed fields drifted",
    path,
  );
  const identityFor = (relativePath) => {
    const identity = manifestState.byPath.get(relativePath);
    assert(
      identity !== undefined,
      "CLOSED_INVENTORY_DRIFT",
      `admission-bound artifact missing: ${relativePath}`,
      relativePath,
    );
    return bytesIdentityFromBound(identity);
  };
  const contextPath = artifactPaths?.context
    ?? `${base}/context.json`;
  const requestBodyPath = artifactPaths?.request_body
    ?? `${base}/request.raw`;
  const requestPath = artifactPaths?.request_record
    ?? `${base}/request-record.json`;
  const transportPath = artifactPaths?.transport_record
    ?? `${base}/transport/transport-record.json`;
  const observerPath = artifactPaths?.observer_record
    ?? `${base}/observer/observation.json`;
  const observerStdoutPath = artifactPaths?.observer_stdout
    ?? `${base}/observer/stdout.log`;
  const observerStderrPath = artifactPaths?.observer_stderr
    ?? `${base}/observer/stderr.log`;
  const usagePath = artifactPaths?.usage_record
    ?? `${base}/usage.json`;
  const admittedPath = artifactPaths?.admitted
    ?? `${base}/admission/admitted-response.http`;
  for (const [value, expectedIdentity, label] of [
    [receipt.context_record_identity, identityFor(contextPath), "receipt context identity"],
    [receipt.request_body_identity, identityFor(requestBodyPath), "receipt request body identity"],
    [receipt.request_record_identity, identityFor(requestPath), "receipt request record identity"],
    [receipt.transport_record_identity, identityFor(transportPath), "receipt transport record identity"],
    [receipt.observer_record_identity, identityFor(observerPath), "receipt observer record identity"],
    [receipt.usage_record_identity, identityFor(usagePath), "receipt usage record identity"],
  ]) {
    validateBytesIdentity(value, expectedIdentity, label, path);
  }
  validateArtifactDescriptor(
    receipt.admitted_response,
    admittedPath,
    manifestState,
    "receipt admitted response",
    path,
  );
  validateBytesIdentity(
    transportRecord.raw_response_identity,
    bytesIdentityFromBound(admitted.identity),
    "transport raw response identity",
    transportPath,
  );
  validateBytesIdentity(
    receipt.body_identity,
    transportRecord.body_identity,
    "receipt transport body identity",
    path,
  );
  for (const [value, expectedIdentity, label, sourcePath] of [
    [requestRecord.context_record_identity, identityFor(contextPath), "request context identity", requestPath],
    [requestRecord.request_body_identity, identityFor(requestBodyPath), "request body identity", requestPath],
    [transportRecord.request_record_identity, identityFor(requestPath), "transport request identity", transportPath],
    [observerRecord.request_record_identity, identityFor(requestPath), "observer request identity", observerPath],
    [usageRecord.response_identity, receipt.body_identity, "usage response identity", usagePath],
  ]) {
    validateBytesIdentity(value, expectedIdentity, label, sourcePath);
  }
  exactKeys(
    receipt.supporting_artifacts,
    SUPPORTING_ARTIFACT_KEYS,
    "EVIDENCE_CROSS_BINDING_INVALID",
    "admission supporting artifacts",
    path,
  );
  const expectedSupporting = {
    context_record: contextPath,
    observer_record: observerPath,
    observer_stderr: observerStderrPath,
    observer_stdout: observerStdoutPath,
    request_body: requestBodyPath,
    request_record: requestPath,
    transport_record: transportPath,
    usage_record: usagePath,
  };
  const supportingPaths = [];
  for (const key of SUPPORTING_ARTIFACT_KEYS) {
    const descriptor = validateArtifactDescriptor(
      receipt.supporting_artifacts[key],
      expectedSupporting[key],
      manifestState,
      `supporting_artifacts.${key}`,
      path,
    );
    supportingPaths.push(descriptor.path);
  }
  assert(
    new Set(supportingPaths).size === SUPPORTING_ARTIFACT_KEYS.length,
    "EVIDENCE_CROSS_BINDING_INVALID",
    "admission supporting artifact paths are not unique",
    path,
  );
  assert(
    contextRecord.schema_version === "p1-165-context-record/v1"
      && requestRecord.schema_version === "p1-165-request-record/v1"
      && transportRecord.schema_version === "p1-165-transport-record/v1"
      && observerRecord.schema_version === "p1-165-os-network-observation/v1"
      && usageRecord.schema_version === "p1-165-provider-usage/v1",
    "ADMISSION_RECEIPT_INVALID",
    "admission-bound production record schema drifted",
    path,
  );
  return {
    receipt_identity: identityFor(path),
    body_identity: receipt.body_identity,
    adapter_control_identity: contextRecord.adapter_result_identity,
  };
}

function supportingAdmissionPaths(base) {
  return {
    admitted: `${base}/admission/admitted-response.http`,
    receipt: `${base}/admission/admission-receipt.json`,
    context: `${base}/supporting/context.json`,
    observer_record: `${base}/supporting/observer.json`,
    observer_stderr: `${base}/supporting/observer-stderr.log`,
    observer_stdout: `${base}/supporting/observer-stdout.log`,
    request_body: `${base}/supporting/request.raw`,
    request_record: `${base}/supporting/request-record.json`,
    transport_record: `${base}/supporting/transport-record.json`,
    usage_record: `${base}/supporting/usage.json`,
  };
}

function validateAdmittedControl(
  root,
  manifestState,
  base,
  expectedJoin,
  modules,
  syntheticObserverFixture,
) {
  const paths = supportingAdmissionPaths(base);
  const contextArtifact = readBoundBytes(
    root,
    manifestState,
    paths.context,
    "control context",
  );
  const requestBody = readBoundBytes(
    root,
    manifestState,
    paths.request_body,
    "control request body",
  );
  const requestArtifact = readBoundBytes(
    root,
    manifestState,
    paths.request_record,
    "control request record",
  );
  const transportArtifact = readBoundBytes(
    root,
    manifestState,
    paths.transport_record,
    "control transport record",
  );
  const observerArtifact = readBoundBytes(
    root,
    manifestState,
    paths.observer_record,
    "control observer record",
  );
  const observerStdout = readBoundBytes(
    root,
    manifestState,
    paths.observer_stdout,
    "control observer stdout",
  );
  const observerStderr = readBoundBytes(
    root,
    manifestState,
    paths.observer_stderr,
    "control observer stderr",
  );
  const usage = readBoundJson(
    root,
    manifestState,
    paths.usage_record,
    "control usage record",
  );
  const admitted = readBoundBytes(
    root,
    manifestState,
    paths.admitted,
    "control admitted response",
  );
  const context = modules.admission.parseClosedContextRecord(
    contextArtifact.bytes,
    { expected_join: expectedJoin },
  ).value;
  const request = modules.admission.parseClosedRequestRecord(
    requestArtifact.bytes,
    {
      expected_join: expectedJoin,
      expected_context_identity: bytesIdentityFromBound(contextArtifact.identity),
    },
  ).value;
  const transport = modules.transport.parseClosedTransportRecord(
    transportArtifact.bytes,
    {
      join: expectedJoin,
      request_record_identity: bytesIdentityFromBound(requestArtifact.identity),
      policy: request.policy,
    },
  );
  const observer = modules.observer.parseClosedObserverRecord(
    observerArtifact.bytes,
    observerStdout.bytes,
    observerStderr.bytes,
    {
      join: expectedJoin,
      request_record_identity: bytesIdentityFromBound(requestArtifact.identity),
      policy: request.policy,
    },
  );
  const validatedUsage = modules.contract.validateUsage(
    usage,
    {
      join: expectedJoin,
      responseIdentity: transport.body_identity,
      policy: request.policy,
    },
    "control usage record",
  );
  validateBytesIdentity(
    request.request_body_identity,
    bytesIdentityFromBound(requestBody.identity),
    "control request body identity",
    paths.request_record,
  );
  assert(
    observerStdout.bytes.equals(syntheticObserverFixture.stdout)
      && observerStderr.bytes.equals(syntheticObserverFixture.stderr)
      && observer.pid === syntheticObserverFixture.record.pid
      && observer.fd === syntheticObserverFixture.record.fd
      && observer.local === syntheticObserverFixture.record.local
      && observer.peer === syntheticObserverFixture.record.peer
      && observer.exit_status === 0
      && observer.status === "PASS"
      && isDeepStrictEqual(observer.command, syntheticObserverFixture.record.command)
      && isDeepStrictEqual(
        observer.observed_rows,
        syntheticObserverFixture.record.observed_rows,
      ),
    "FROZEN_SYNTHETIC_OBSERVER_FIXTURE_INVALID",
    "control admission observer is not bound to the frozen synthetic fixture",
    paths.observer_record,
  );
  const receipt = readBoundJson(
    root,
    manifestState,
    paths.receipt,
    "control admission receipt",
  );
  const state = validateProductionAdmissionReceipt({
    base,
    artifactPaths: paths,
    joinRecord: expectedJoin,
    manifestState,
    receipt,
    requestRecord: request,
    contextRecord: context,
    transportRecord: transport,
    observerRecord: observer,
    usageRecord: validatedUsage,
    admitted,
  });
  let chunkOffset = 0;
  const reconstructedChunks = transport.chunks.map((chunk, index) => {
    exactKeys(
      chunk,
      ["byte_length", "index", "sha256"],
      "TRANSPORT_RECORD_INVALID",
      `control transport chunk ${index}`,
      paths.transport_record,
    );
    assert(
      chunk.index === index
        && Number.isSafeInteger(chunk.byte_length)
        && chunk.byte_length >= 0,
      "TRANSPORT_RECORD_INVALID",
      `control transport chunk ${index} metadata drifted`,
      paths.transport_record,
    );
    const bytes = admitted.bytes.subarray(
      chunkOffset,
      chunkOffset + chunk.byte_length,
    );
    chunkOffset += chunk.byte_length;
    assert(
      bytes.length === chunk.byte_length
        && sha256(bytes) === chunk.sha256,
      "TRANSPORT_RECORD_INVALID",
      `control transport chunk ${index} does not reconstruct from raw bytes`,
      paths.admitted,
    );
    return bytes;
  });
  assert(
    chunkOffset === admitted.bytes.length,
    "TRANSPORT_RECORD_INVALID",
    "control transport chunks do not close the raw response",
    paths.admitted,
  );
  const independentlyAnalyzed = modules.transport.analyzeTransport({
    join: expectedJoin,
    request_record_identity: bytesIdentityFromBound(requestArtifact.identity),
    chunks: reconstructedChunks,
    eof: true,
    stream_terminal_events: [],
    policy: request.policy,
    observed_peer: request.policy.expected_peer,
  });
  assert(
    isDeepStrictEqual(independentlyAnalyzed.record, transport)
      && independentlyAnalyzed.response_bytes.equals(admitted.bytes),
    "TRANSPORT_RECORD_INVALID",
    "control transport does not independently reconstruct from raw response",
    paths.transport_record,
  );
  validateBytesIdentity(
    state.body_identity,
    {
      byte_length: independentlyAnalyzed.body_bytes.length,
      sha256: sha256(independentlyAnalyzed.body_bytes),
    },
    "control admitted body identity",
    paths.receipt,
  );
  return {
    paths,
    state,
    context,
    request,
    transport,
    observer,
    usage: validatedUsage,
    admitted,
    body_bytes: independentlyAnalyzed.body_bytes,
  };
}

function validateProductionCellClosure({
  base,
  joinRecord,
  manifestState,
  closure,
  admissionState,
  admitted,
  requestRecordIdentity,
  spine,
  adapterDescriptor,
  b2ScanDescriptor,
}) {
  const path = `${base}/cell-closure.json`;
  exactKeys(
    closure,
    CELL_CLOSURE_KEYS,
    "CELL_CLOSURE_INVALID",
    "production cell closure",
    path,
  );
  assert(
    closure.schema_version === "p1-165-cell-closure/v2"
      && closure.task_id === TASK_ID
      && isDeepStrictEqual(closure.join, joinRecord)
      && closure.outcome === "SUCCESS"
      && closure.outcome_reason === "PASS",
    "CELL_CLOSURE_INVALID",
    "production cell closure fixed fields drifted",
    path,
  );
  assert(
    closure.denominator_included === true
      && closure.worker_success_fields_trusted === false
      && closure.failure_stage === null
      && closure.failure_receipt_identity === null,
    "CELL_CLOSURE_INVALID",
    "successful production cell closure accounting/trust fields drifted",
    path,
  );
  for (const [value, expectedIdentity, label] of [
    [closure.request_record_identity, requestRecordIdentity, "closure request record identity"],
    [closure.admitted_response_identity, bytesIdentityFromBound(admitted.identity), "closure admitted response identity"],
    [closure.body_identity, admissionState.body_identity, "closure body identity"],
    [closure.admission_receipt_identity, admissionState.receipt_identity, "closure admission receipt identity"],
  ]) {
    validateBytesIdentity(value, expectedIdentity, label, path);
  }
  validateArtifactDescriptor(
    admissionState.adapter_control_identity,
    adapterDescriptor.path,
    manifestState,
    "context accepted adapter identity",
    `${base}/context.json`,
  );
  validateArtifactDescriptor(
    closure.adapter_control_identity,
    adapterDescriptor.path,
    manifestState,
    "closure accepted adapter identity",
    path,
  );
  assert(
    Array.isArray(closure.p1_149_artifact_identities)
      && closure.p1_149_artifact_identities.length === SPINE_ARTIFACTS.length,
    "CELL_CLOSURE_INVALID",
    "closure does not bind exactly 24 P1-149 artifacts",
    path,
  );
  for (const [index, artifactName] of SPINE_ARTIFACTS.entries()) {
    validateArtifactDescriptor(
      closure.p1_149_artifact_identities[index],
      `${base}/spine/${artifactName}`,
      manifestState,
      `closure P1-149 artifact ${artifactName}`,
      path,
    );
  }
  const p101Names = [
    "p1-101-replay-receipt.json",
    "p1-101-adapter-rollback-receipt.json",
  ];
  assert(
    Array.isArray(closure.p1_101_receipt_identities)
      && closure.p1_101_receipt_identities.length === p101Names.length,
    "CELL_CLOSURE_INVALID",
    "closure does not bind exactly two P1-101 receipts",
    path,
  );
  for (const [index, artifactName] of p101Names.entries()) {
    validateArtifactDescriptor(
      closure.p1_101_receipt_identities[index],
      `${base}/spine/${artifactName}`,
      manifestState,
      `closure P1-101 receipt ${artifactName}`,
      path,
    );
  }
  const providerResponse = spine.artifacts.get("provider-response.json");
  validateBytesIdentity(
    admissionState.body_identity,
    {
      byte_length: providerResponse.bytes.length,
      sha256: sha256(providerResponse.bytes),
    },
    "admitted body to P1-149 provider response",
    path,
  );
  if (joinRecord.profile_id.startsWith("B2_")) {
    assert(
      b2ScanDescriptor !== null,
      "B2_SCAN_LEDGER_INVALID",
      "B2 closure scan proof descriptor is missing",
      path,
    );
    validateArtifactDescriptor(
      closure.b2_scan_proof_identity,
      b2ScanDescriptor.path,
      manifestState,
      "closure B2 scan proof identity",
      path,
    );
  } else {
    assert(
      b2ScanDescriptor === null
        && closure.b2_scan_proof_identity === null,
      "CELL_CLOSURE_INVALID",
      "non-B2 closure unexpectedly binds a scan proof",
      path,
    );
  }
  return {
    b2_scan_proof_path: joinRecord.profile_id.startsWith("B2_")
      ? b2ScanDescriptor.path
      : null,
  };
}

async function validateCells(
  root,
  manifestState,
  kernelContract,
  atomicCommit,
) {
  assert(
    Array.isArray(kernelContract.cell_order)
      && kernelContract.cell_order.length === 36
      && new Set(kernelContract.cell_order).size === 36,
    "CELL_SET_INVALID",
    "kernel contract does not freeze 36 unique cells",
    KERNEL_CONTRACT_PATH,
  );
  const cellDirectories = readdirSync(containedPath(root, "raw/cells", "cell root")).sort();
  assert(
    isDeepStrictEqual(cellDirectories, [...kernelContract.cell_order].sort()),
    "CELL_SET_INVALID",
    "raw cell set differs from kernel contract",
    "raw/cells",
  );
  const { executeSpine } = await import(
    "../../harness/p1-149-accepted-execution-spine/execution.mjs"
  );
  const { verifyFrozenExecutionEvidence } = await import(
    "../../replay/p1-149-accepted-execution-spine/replay.mjs"
  );
  const productionKernel = await loadProductionKernel();
  const adapterState = loadAcceptedAdapterIndex(
    root,
    manifestState,
    atomicCommit,
  );
  const adapterIndex = adapterState.entries;
  const adapterProofs = new Map();
  const b2SandboxReexecutionReceipts = [];
  let b2IndependentScanReexecutions = 0;
  for (const taskId of ACCEPTED_TASK_IDS) {
    for (const profileId of PROFILE_ORDER) {
      const key = `${taskId}:${profileId}`;
      const entry = adapterIndex.get(key);
      const parsed = validateAcceptedAdapterProofEntry({
        root,
        manifestState,
        entry,
        taskId,
        profileId,
      });
      let b2State = null;
      if (profileId.startsWith("B2_")) {
        b2State = validateB2AdapterProof({
          root,
          manifestState,
          entry,
          parsed,
          taskId,
          profileId,
        });
        b2IndependentScanReexecutions +=
          b2State.independently_reexecuted ? 1 : 0;
        b2SandboxReexecutionReceipts.push(
          b2State.sandbox_reexecution_receipt,
        );
      }
      adapterProofs.set(key, { entry, parsed, b2: b2State });
    }
  }
  assert(
    adapterProofs.size === 36
      && b2IndependentScanReexecutions === 12
      && b2SandboxReexecutionReceipts.length === 12
      && new Set(
        b2SandboxReexecutionReceipts.map(
          (receipt) => receipt.process.child_pid,
        ),
      ).size === 12
      && b2SandboxReexecutionReceipts.every(
        (receipt) =>
          receipt.schema_version
            === "p1-165-current-b2-sandbox-reexecution/v1"
          && receipt.status === "PASS"
          && receipt.claim_boundary === B2_REEXECUTION_CLAIM_BOUNDARY
          && receipt.historical_reviewed_binary_exact_bytes_claim === false
          && receipt.cooperative_local_accepted_evidence_path_residual === true
          && receipt.hostile_global_read_isolation_claim === false
          && receipt.hostile_process_isolation_claim === false
          && receipt.trusted_accepted_source_required === true
          && receipt.runtime_verified === true
          && receipt.process.exit_status === 0
          && receipt.process.signal === null
          && receipt.process.timed_out === false
          && receipt.cleanup_verified.fixture_root_absent === true
          && isDeepStrictEqual(
            receipt.external_effects,
            FALSE_EXTERNAL_EFFECTS,
          )
          && receipt.source_inventory_unchanged === true
          && receipt.executable_identity_unchanged === true
          && isDeepStrictEqual(
            receipt.source_inventory_before,
            receipt.source_inventory_after,
          )
          && receipt.selected_executable_identity.sha256
            === receipt.source_accepted_executable_identity.sha256
          && receipt.selected_executable_identity.byte_length
            === receipt.source_accepted_executable_identity.byte_length,
      ),
    "ADAPTER_CONTROL_INVALID",
    "accepted adapter raw proof validation is incomplete",
  );
  const cells = [];
  const runIds = new Set();
  const adapterRoots = new Set();
  let independentReexecutionSpines = 0;
  for (const cellId of kernelContract.cell_order) {
    const base = `raw/cells/${cellId}`;
    const relativeFiles = [];
    const visit = (relativeDirectory) => {
      const absolute = containedPath(
        root,
        relativeDirectory === "" ? base : `${base}/${relativeDirectory}`,
        "cell directory",
      );
      for (const name of readdirSync(absolute).sort()) {
        const relativePath = relativeDirectory === "" ? name : `${relativeDirectory}/${name}`;
        const stat = lstatSync(containedPath(root, `${base}/${relativePath}`, "cell artifact"));
        if (stat.isDirectory()) visit(relativePath);
        else relativeFiles.push(relativePath);
      }
    };
    visit("");
    const expectedCellFiles = expectedCellArtifactPaths();
    assert(
      isDeepStrictEqual(relativeFiles.sort(), expectedCellFiles),
      "CELL_ARTIFACT_SET_INVALID",
      `cell ${cellId} file set differs from frozen contract`,
      base,
    );
    const joinRecord = readBoundJson(root, manifestState, `${base}/join.json`, "cell join");
    exactKeys(joinRecord, JOIN_KEYS, "EVIDENCE_CROSS_BINDING_INVALID", "cell join", `${base}/join.json`);
    assert(
      joinRecord.cell_id === cellId
        && joinRecord.task_id === TASK_ID
        && PROFILE_ORDER.includes(joinRecord.profile_id),
      "EVIDENCE_CROSS_BINDING_INVALID",
      `cell ${cellId} join identity invalid`,
      `${base}/join.json`,
    );
    for (const recordPath of [
      "request-record.json",
      "context.json",
      "transport/transport-record.json",
      "observer/observation.json",
      "usage.json",
      "admission/admission-receipt.json",
      "cell-closure.json",
    ]) {
      const record = readBoundJson(root, manifestState, `${base}/${recordPath}`, `cell ${recordPath}`);
      assertRecordJoin(record, joinRecord, `cell ${recordPath}`, `${base}/${recordPath}`);
      assertNoTrueExternalEffects(record, `cell ${recordPath}`, `${base}/${recordPath}`);
      scanForbiddenEvidenceFields(record, `${base}/${recordPath}`);
    }
    const requestRaw = readBoundBytes(root, manifestState, `${base}/request.raw`, "cell request");
    const contextRecord = readBoundJson(
      root,
      manifestState,
      `${base}/context.json`,
      "cell context record",
    );
    const requestRecord = readBoundJson(
      root,
      manifestState,
      `${base}/request-record.json`,
      "cell request record",
    );
    assertEmbeddedIdentity(
      requestRecord,
      requestRaw.identity,
      "cell request record",
      `${base}/request-record.json`,
    );
    const rawResponse = readBoundBytes(
      root,
      manifestState,
      `${base}/admission/admitted-response.http`,
      "cell raw response",
    );
    const transportRecord = readBoundJson(
      root,
      manifestState,
      `${base}/transport/transport-record.json`,
      "cell transport record",
    );
    assertEmbeddedIdentity(
      transportRecord,
      rawResponse.identity,
      "cell transport record",
      `${base}/transport/transport-record.json`,
    );
    const observer = readBoundJson(
      root,
      manifestState,
      `${base}/observer/observation.json`,
      "cell observer record",
    );
    validateFrozenObserver(root, manifestState, base, observer, joinRecord);
    const usageRecord = readBoundJson(
      root,
      manifestState,
      `${base}/usage.json`,
      "cell usage record",
    );
    const contextArtifact = readBoundBytes(
      root,
      manifestState,
      `${base}/context.json`,
      "cell context bytes",
    );
    const requestRecordArtifact = readBoundBytes(
      root,
      manifestState,
      `${base}/request-record.json`,
      "cell request record bytes",
    );
    const transportArtifact = readBoundBytes(
      root,
      manifestState,
      `${base}/transport/transport-record.json`,
      "cell transport record bytes",
    );
    const observerArtifact = readBoundBytes(
      root,
      manifestState,
      `${base}/observer/observation.json`,
      "cell observer record bytes",
    );
    const observerStdoutArtifact = readBoundBytes(
      root,
      manifestState,
      `${base}/observer/stdout.log`,
      "cell observer stdout bytes",
    );
    const observerStderrArtifact = readBoundBytes(
      root,
      manifestState,
      `${base}/observer/stderr.log`,
      "cell observer stderr bytes",
    );
    const validatedContext = productionKernel.admission.parseClosedContextRecord(
      contextArtifact.bytes,
      { expected_join: joinRecord },
    ).value;
    const validatedRequest = productionKernel.admission.parseClosedRequestRecord(
      requestRecordArtifact.bytes,
      {
        expected_join: joinRecord,
        expected_context_identity: bytesIdentityFromBound(contextArtifact.identity),
      },
    ).value;
    const validatedTransport = productionKernel.transport.parseClosedTransportRecord(
      transportArtifact.bytes,
      {
        join: joinRecord,
        request_record_identity: bytesIdentityFromBound(requestRecordArtifact.identity),
        policy: validatedRequest.policy,
      },
    );
    const validatedObserver = productionKernel.observer.parseClosedObserverRecord(
      observerArtifact.bytes,
      observerStdoutArtifact.bytes,
      observerStderrArtifact.bytes,
      {
        join: joinRecord,
        request_record_identity: bytesIdentityFromBound(requestRecordArtifact.identity),
        policy: validatedRequest.policy,
      },
    );
    const validatedUsage = productionKernel.contract.validateUsage(
      usageRecord,
      {
        join: joinRecord,
        responseIdentity: validatedTransport.body_identity,
        policy: validatedRequest.policy,
      },
      "cell usage record",
    );
    assert(
      isDeepStrictEqual(validatedContext, contextRecord)
        && isDeepStrictEqual(validatedRequest, requestRecord)
        && isDeepStrictEqual(validatedTransport, transportRecord)
        && isDeepStrictEqual(validatedObserver, observer)
        && isDeepStrictEqual(validatedUsage, usageRecord),
      "PRODUCTION_RECORD_VALIDATION_MISMATCH",
      `cell ${cellId} production closed parser output drifted`,
      base,
    );
    const admitted = readBoundBytes(
      root,
      manifestState,
      `${base}/admission/admitted-response.http`,
      "admitted response",
    );
    const admissionReceipt = readBoundJson(
      root,
      manifestState,
      `${base}/admission/admission-receipt.json`,
      "admission receipt",
    );
    assertEmbeddedIdentity(
      admissionReceipt,
      admitted.identity,
      "admission receipt",
      `${base}/admission/admission-receipt.json`,
    );
    const admissionState = validateProductionAdmissionReceipt({
      base,
      joinRecord,
      manifestState,
      receipt: admissionReceipt,
      requestRecord: validatedRequest,
      contextRecord: validatedContext,
      transportRecord: validatedTransport,
      observerRecord: validatedObserver,
      usageRecord: validatedUsage,
      admitted,
    });
    const closure = readBoundJson(
      root,
      manifestState,
      `${base}/cell-closure.json`,
      "production cell closure",
    );
    const spine = validateSpineRaw(root, manifestState, `${base}/spine`);
    assert(!runIds.has(spine.run_id), "DUPLICATE_RUN_ID", "spine run_id repeated", `${base}/spine/run-record.json`);
    runIds.add(spine.run_id);
    const adapterProof = adapterProofs.get(
      `${spine.task_id}:${joinRecord.profile_id}`,
    );
    assert(
      adapterProof !== undefined,
      "ADAPTER_CONTROL_INVALID",
      `cell ${cellId} has no uniquely indexed accepted adapter`,
      `${base}/context.json`,
    );
    const adapterDescriptor = adapterProof.entry.adapter_descriptor;
    adapterRoots.add(adapterProof.entry.final_proof_root);
    const closureState = validateProductionCellClosure({
      base,
      joinRecord,
      manifestState,
      closure,
      admissionState,
      admitted,
      requestRecordIdentity: bytesIdentityFromBound(
        manifestState.byPath.get(`${base}/request-record.json`),
      ),
      spine,
      adapterDescriptor,
      b2ScanDescriptor: adapterProof.entry.b2_scan_descriptor,
    });
    const providerResponse = spine.artifacts.get("provider-response.json").bytes;
    const fresh = executeSpine({
      taskId: spine.task_id,
      responseBytes: providerResponse,
      runId: spine.run_id,
    });
    assert(
      fresh.run_id === spine.run_id
        && fresh.task_id === spine.task_id
        && isDeepStrictEqual(Object.keys(fresh.artifacts).sort(), [...SPINE_ARTIFACTS].sort())
        && canonicalJson(fresh.stable_projection) === canonicalJson(spine.stable_projection)
        && fresh.summary?.rollback_exact === true
        && fresh.summary?.p1_101_replay === "PASS",
      "INDEPENDENT_SPINE_REEXECUTION_MISMATCH",
      `cell ${cellId} did not independently reexecute the accepted spine`,
      `${base}/spine`,
    );
    independentReexecutionSpines += 1;
    cells.push({
      cell_id: cellId,
      profile_id: joinRecord.profile_id,
      task_id: spine.task_id,
      run_id: spine.run_id,
      spine_base: `${base}/spine`,
      artifacts: spine.artifacts,
      adapter_control_path: adapterDescriptor.path,
      b2_scan_proof_path: closureState.b2_scan_proof_path,
    });
  }
  assert(
    cells.length === 36
      && runIds.size === 36
      && adapterRoots.size === 36
      && independentReexecutionSpines === 36,
    "CELL_SET_INVALID",
    "36-cell real spine set is incomplete",
  );
  for (const profileId of PROFILE_ORDER) {
    const group = cells.filter((cell) => cell.profile_id === profileId);
    assert(
      group.length === 6
        && isDeepStrictEqual(group.map((cell) => cell.task_id).sort(), [...ACCEPTED_TASK_IDS].sort()),
      "PROFILE_GROUP_INVALID",
      `profile ${profileId} does not contain six accepted tasks`,
      `raw/profile-verification/${profileId}`,
    );
    const profileBase = `raw/profile-verification/${profileId}`;
    const profileValidation = verifyFrozenExecutionEvidence(
      containedPath(root, profileBase, `${profileId} profile root`),
    );
    const verifyReceipt = readBoundJson(
      root,
      manifestState,
      `raw/profile-verification-receipts/${profileId}.json`,
      `${profileId} verify receipt`,
    );
    assert(
      verifyReceipt.status === "PASS"
        && profileValidation.status === "PASS"
        && profileValidation.task_results?.length === 6,
      "PROFILE_GROUP_INVALID",
      `profile ${profileId} verification receipt or run plan invalid`,
      `raw/profile-verification-receipts/${profileId}.json`,
    );
    for (const cell of group) {
      const taskBase = `${profileBase}/tasks/${cell.task_id}`;
      validateSpineRaw(
        root,
        manifestState,
        taskBase,
        cell.run_id,
        cell.task_id,
      );
      for (const name of SPINE_ARTIFACTS) {
        const profileArtifact = readBoundBytes(
          root,
          manifestState,
          `${taskBase}/${name}`,
          `${profileId}/${cell.task_id}/${name}`,
        );
        const cellArtifact = cell.artifacts.get(name);
        assert(
          profileArtifact.bytes.equals(cellArtifact.bytes),
          "PROFILE_CELL_BYTES_MISMATCH",
          `${profileId}/${cell.task_id}/${name} differs from cell spine`,
          `${taskBase}/${name}`,
        );
      }
    }
  }
  return {
    cells,
    distinct_adapter_roots: adapterRoots.size,
    distinct_spine_run_ids: runIds.size,
    closed_spine_artifact_sets: cells.length,
    p1_101_replays: cells.length,
    p1_101_rollbacks: cells.length,
    independent_reexecution_spines: independentReexecutionSpines,
    accepted_adapter_process: {
      status: "PASS",
      accepted_authority_bundle_exact: true,
      sandbox_calibration_exact: true,
      network_denial_fixture_only: true,
      live_network_probe_executed: false,
      live_network_connections_created: 0,
      live_network_calibration: "DEFERRED_TO_P1_169",
      home_read_denial:
        adapterState.process.calibration.receipt
          .home_read_denial.exit_status !== 0,
      home_write_denial:
        adapterState.process.calibration.receipt
          .home_write_denial.exit_status !== 0,
      external_write_denial:
        adapterState.process.calibration.receipt
          .external_write_denial.exit_status !== 0,
      owned_write_allowance:
        adapterState.process.calibration.receipt
          .owned_write_allowance.exit_status === 0,
      calibration_roots_absent:
        adapterState.process.receipt.cleanup_verified
          .sandbox_calibration_roots_absent,
      accepted_p1_129_source_preserved_read_only:
        adapterState.process.receipt.cleanup_verified
          .accepted_p1_129_source_preserved_read_only,
      b2_independent_scan_reexecutions: b2IndependentScanReexecutions,
      distinct_b2_child_pids: new Set(
        b2SandboxReexecutionReceipts.map(
          (receipt) => receipt.process.child_pid,
        ),
      ).size,
      all_current_b2_fixture_roots_absent:
        adapterState.process.receipt.cleanup_verified
          .all_current_b2_fixture_roots_absent,
      historical_reviewed_binary_exact_bytes_claim: false,
      cooperative_local_accepted_evidence_path_residual: true,
      hostile_global_read_isolation_claim: false,
      hostile_process_isolation_claim: false,
      trusted_accepted_source_required: true,
    },
    adapter_proofs: adapterProofs,
  };
}

async function validateOrdinaryFailureControls(
  root,
  manifestState,
  cellState,
  syntheticObserverFixture,
) {
  const base = "raw/ordinary-failure-continuation";
  const planPath = `${base}/plan.json`;
  const eventsPath = `${base}/events.jsonl`;
  const receiptPath = `${base}/receipt.json`;
  const plan = readBoundJson(
    root,
    manifestState,
    planPath,
    "ordinary failure continuation plan",
  );
  exactKeys(
    plan,
    [
      "case_order",
      "continuation_policy",
      "denominator_policy",
      "failure_stage_order",
      "schema_version",
      "task_id",
    ],
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure continuation plan",
    planPath,
  );
  const caseOrder = ORDINARY_FAILURE_CASES.map(([caseId]) => caseId);
  const stageOrder = ORDINARY_FAILURE_CASES.map(([, stage]) => stage);
  assert(
    plan.schema_version === "p1-165-ordinary-failure-plan/v1"
      && plan.task_id === TASK_ID
      && isDeepStrictEqual(plan.case_order, caseOrder)
      && isDeepStrictEqual(plan.failure_stage_order, stageOrder)
      && plan.denominator_policy === "ALL_FAILED_CASES_INCLUDED"
      && plan.continuation_policy === "NEXT_ACCEPTED_CELL_MUST_SUCCEED",
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure continuation plan drifted",
    planPath,
  );
  const modules = await loadProductionKernel();
  const adapterCell = cellState.cells.find(
    (cell) =>
      cell.profile_id === "B0_A"
      && cell.task_id === ACCEPTED_TASK_IDS[0],
  );
  assert(
    adapterCell !== undefined,
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure control accepted adapter is missing",
    planPath,
  );
  const adapterDescriptor = manifestState.byPath.get(
    adapterCell.adapter_control_path,
  );
  assert(
    adapterDescriptor !== undefined,
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure control adapter descriptor is missing",
    adapterCell.adapter_control_path,
  );
  const events = parseJsonLines(
    readBoundBytes(
      root,
      manifestState,
      eventsPath,
      "ordinary failure continuation events",
    ).bytes,
    "ordinary failure continuation events",
    eventsPath,
  );
  assert(
    events.length === ORDINARY_FAILURE_CASES.length + 1,
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure event count drifted",
    eventsPath,
  );
  let earlyFailures = 0;
  let lateFailures = 0;
  let denominator = 0;
  for (const [index, [caseId, failureStage, reasonCode]]
    of ORDINARY_FAILURE_CASES.entries()) {
    const caseBase = `${base}/cases/${caseId}`;
    const expectedJoin = {
      execution_id: `P1-165-ORDINARY-${String(index + 1).padStart(2, "0")}`,
      cell_id: `P1-165-ORDINARY-${String(index + 1).padStart(2, "0")}`,
      task_id: TASK_ID,
      profile_id: "B0_A",
      repetition_id: "A",
    };
    const admission = validateAdmittedControl(
      root,
      manifestState,
      caseBase,
      expectedJoin,
      modules,
      syntheticObserverFixture,
    );
    const resultPath = `${caseBase}/result.json`;
    const failurePath = `${caseBase}/research-failure-receipt.json`;
    const closurePath = `${caseBase}/cell-closure.json`;
    const result = readBoundJson(
      root,
      manifestState,
      resultPath,
      `ordinary failure ${caseId} result`,
    );
    exactKeys(
      result,
      [
        "admission_receipt_identity",
        "case_id",
        "cell_closure_identity",
        "denominator_included",
        "engine_reason_code",
        "failure_stage",
        "p1_101_receipt_count",
        "p1_149_artifact_count",
        "research_failure_receipt_identity",
        "schema_version",
        "status",
        "task_id",
        "worker_success_fields_trusted",
      ],
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} result`,
      resultPath,
    );
    const early = ["MODEL", "JSON", "PATCH_IR", "COMPILER"]
      .includes(failureStage);
    const expectedP149 = early ? 0 : SPINE_ARTIFACTS.length;
    const expectedP101 = early ? 0 : 2;
    const expectedEngineReason = {
      MODEL: modules.contract.MODEL_FAILURE_REASON_CODE,
      JSON: "IR_JSON_INVALID",
      PATCH_IR: "IR_SCHEMA_INVALID",
      COMPILER: "IR_PATH_REJECTED",
      ORACLE: "ORACLE_POSTCONDITION_FAILED",
      TEST: "TEST_COMMAND_FAILED",
    }[failureStage];
    let independentlyObservedEarlyReason = null;
    if (failureStage === "MODEL") {
      const envelope = parseJsonBytes(
        admission.body_bytes,
        "ordinary MODEL failure envelope",
        admission.paths.admitted,
      );
      exactKeys(
        envelope,
        ["schema_version", "status"],
        "ORDINARY_FAILURE_CONTROL_INVALID",
        "ordinary MODEL failure envelope",
        admission.paths.admitted,
      );
      assert(
        envelope.schema_version === modules.contract.MODEL_FAILURE_SCHEMA
          && envelope.status === "DECLINED",
        "ORDINARY_FAILURE_CONTROL_INVALID",
        "ordinary MODEL failure body is not the exact declined envelope",
        admission.paths.admitted,
      );
      const classification =
        modules.contract.classifyModelFailureEnvelope(admission.body_bytes);
      exactKeys(
        classification,
        ["failure_stage", "reason_code", "status"],
        "ORDINARY_FAILURE_CONTROL_INVALID",
        "ordinary MODEL failure production classification",
        admission.paths.admitted,
      );
      assert(
        classification.failure_stage === "MODEL"
          && classification.reason_code
            === modules.contract.MODEL_FAILURE_REASON_CODE
          && classification.status === "FAILED",
        "ORDINARY_FAILURE_CONTROL_INVALID",
        "ordinary MODEL failure classification drifted from the frozen contract",
        admission.paths.admitted,
      );
      independentlyObservedEarlyReason = classification.reason_code;
    } else if (early) {
      const {
        compileNormalizedProviderResponse,
      } = await import(
        "../../harness/p1-149-accepted-execution-spine/patch-ir-v2.mjs"
      );
      const {
        loadAcceptedCompilerProfile,
      } = await import(
        "../../harness/p1-149-accepted-execution-spine/accepted-inputs.mjs"
      );
      let independentlyObservedCode = null;
      try {
        compileNormalizedProviderResponse(
          admission.body_bytes,
          loadAcceptedCompilerProfile(ACCEPTED_TASK_IDS[0]),
        );
      } catch (error) {
        independentlyObservedCode = error?.code ?? null;
      }
      assert(
        independentlyObservedCode === expectedEngineReason,
        "ORDINARY_FAILURE_CONTROL_INVALID",
        `ordinary ${failureStage} body did not independently stop at its exact boundary`,
        admission.paths.admitted,
      );
      independentlyObservedEarlyReason = independentlyObservedCode;
    }
    assert(
      result.schema_version === "p1-165-ordinary-failure-case/v1"
        && result.task_id === TASK_ID
        && result.case_id === caseId
        && result.failure_stage === failureStage
        && result.engine_reason_code === expectedEngineReason
        && (!early
          || result.engine_reason_code === independentlyObservedEarlyReason)
        && result.p1_149_artifact_count === expectedP149
        && result.p1_101_receipt_count === expectedP101
        && result.denominator_included === true
        && result.worker_success_fields_trusted === false
        && result.status === "PASS",
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} result drifted`,
      resultPath,
    );
    validateArtifactDescriptor(
      result.admission_receipt_identity,
      admission.paths.receipt,
      manifestState,
      `ordinary failure ${caseId} admission descriptor`,
      resultPath,
    );
    validateArtifactDescriptor(
      result.research_failure_receipt_identity,
      failurePath,
      manifestState,
      `ordinary failure ${caseId} failure descriptor`,
      resultPath,
    );
    validateArtifactDescriptor(
      result.cell_closure_identity,
      closurePath,
      manifestState,
      `ordinary failure ${caseId} closure descriptor`,
      resultPath,
    );
    const failureReceipt = readBoundJson(
      root,
      manifestState,
      failurePath,
      `ordinary failure ${caseId} failure receipt`,
    );
    exactKeys(
      failureReceipt,
      [
        "admission_receipt_identity",
        "failure_stage",
        "join",
        "reason_code",
        "response_admitted",
        "schema_version",
        "status",
        "task_id",
        "worker_success_fields_trusted",
      ],
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} failure receipt`,
      failurePath,
    );
    assert(
      failureReceipt.schema_version
        === "p1-165-research-failure-receipt/v1"
        && failureReceipt.task_id === TASK_ID
        && isDeepStrictEqual(failureReceipt.join, expectedJoin)
        && failureReceipt.failure_stage === failureStage
        && failureReceipt.reason_code === reasonCode
        && failureReceipt.response_admitted === true
        && failureReceipt.worker_success_fields_trusted === false
        && failureReceipt.status === "FAILED",
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} failure receipt drifted`,
      failurePath,
    );
    validateBytesIdentity(
      failureReceipt.admission_receipt_identity,
      admission.state.receipt_identity,
      `ordinary failure ${caseId} failure admission identity`,
      failurePath,
    );
    const closure = readBoundJson(
      root,
      manifestState,
      closurePath,
      `ordinary failure ${caseId} cell closure`,
    );
    exactKeys(
      closure,
      CELL_CLOSURE_KEYS,
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} cell closure`,
      closurePath,
    );
    assert(
      closure.schema_version === "p1-165-cell-closure/v2"
        && closure.task_id === TASK_ID
        && isDeepStrictEqual(closure.join, expectedJoin)
        && closure.outcome === "FAILED"
        && closure.outcome_reason === reasonCode
        && closure.failure_stage === failureStage
        && closure.denominator_included === true
        && closure.worker_success_fields_trusted === false
        && closure.b2_scan_proof_identity === null
        && Array.isArray(closure.p1_149_artifact_identities)
        && closure.p1_149_artifact_identities.length === expectedP149
        && Array.isArray(closure.p1_101_receipt_identities)
        && closure.p1_101_receipt_identities.length === expectedP101,
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} cell closure drifted`,
      closurePath,
    );
    for (const [value, expectedIdentity, label] of [
      [closure.request_record_identity,
        bytesIdentityFromBound(
          manifestState.byPath.get(admission.paths.request_record),
        ),
        "request"],
      [closure.admitted_response_identity,
        bytesIdentityFromBound(admission.admitted.identity),
        "admitted response"],
      [closure.body_identity, admission.state.body_identity, "body"],
      [closure.admission_receipt_identity,
        admission.state.receipt_identity,
        "admission receipt"],
    ]) {
      validateBytesIdentity(
        value,
        expectedIdentity,
        `ordinary failure ${caseId} closure ${label}`,
        closurePath,
      );
    }
    validateArtifactDescriptor(
      closure.adapter_control_identity,
      adapterDescriptor.path,
      manifestState,
      `ordinary failure ${caseId} adapter`,
      closurePath,
    );
    validateArtifactDescriptor(
      closure.failure_receipt_identity,
      failurePath,
      manifestState,
      `ordinary failure ${caseId} failure receipt`,
      closurePath,
    );
    const expectedCaseFiles = [
      ...Object.values(admission.paths),
      failurePath,
      closurePath,
      resultPath,
    ];
    if (!early) {
      const spine = validateSpineRaw(
        root,
        manifestState,
        `${caseBase}/spine`,
        `P1-165-${caseId}`,
        ACCEPTED_TASK_IDS[0],
        "EXPECTED_RESEARCH_FAILURE",
        failureStage,
      );
      const spineProviderResponse =
        spine.artifacts.get("provider-response.json");
      assert(
        spineProviderResponse.bytes.equals(admission.body_bytes)
          && spineProviderResponse.identity.byte_length
            === admission.state.body_identity.byte_length
          && spineProviderResponse.identity.sha256
            === admission.state.body_identity.sha256,
        "EVIDENCE_CROSS_BINDING_INVALID",
        `ordinary failure ${caseId} executed a response different from the admitted body`,
        `${caseBase}/spine/provider-response.json`,
      );
      const rawFailure = validateLateFailureRawReceipts(
        spine,
        failureStage,
        `${caseBase}/spine`,
      );
      assert(
        rawFailure.engine_reason_code === expectedEngineReason,
        "ORDINARY_FAILURE_CONTROL_INVALID",
        `ordinary failure ${caseId} raw receipts classify a different boundary`,
        `${caseBase}/spine`,
      );
      for (const [artifactIndex, artifactName] of SPINE_ARTIFACTS.entries()) {
        validateArtifactDescriptor(
          closure.p1_149_artifact_identities[artifactIndex],
          `${caseBase}/spine/${artifactName}`,
          manifestState,
          `ordinary failure ${caseId} P1-149 ${artifactName}`,
          closurePath,
        );
        expectedCaseFiles.push(`${caseBase}/spine/${artifactName}`);
      }
      for (const [receiptIndex, artifactName] of [
        "p1-101-replay-receipt.json",
        "p1-101-adapter-rollback-receipt.json",
      ].entries()) {
        validateArtifactDescriptor(
          closure.p1_101_receipt_identities[receiptIndex],
          `${caseBase}/spine/${artifactName}`,
          manifestState,
          `ordinary failure ${caseId} P1-101 ${artifactName}`,
          closurePath,
        );
      }
      const { executeSpine } = await import(
        "../../harness/p1-149-accepted-execution-spine/execution.mjs"
      );
      const fresh = await executeSpine({
        taskId: ACCEPTED_TASK_IDS[0],
        responseBytes: spine.artifacts.get("provider-response.json").bytes,
        runId: `P1-165-${caseId}`,
      });
      assert(
        fresh.summary?.worker_observed_classification === "FAILED"
          && fresh.summary?.p1_101_replay === "PASS"
          && fresh.summary?.rollback_exact === true
          && fresh.summary?.issue_test_exit_status
            === rawFailure.issue_test_exit_status
          && fresh.summary?.regression_test_exit_status
            === rawFailure.regression_test_exit_status
          && (
            failureStage === "ORACLE"
              ? fresh.summary?.issue_test_exit_status !== 0
                && fresh.summary?.regression_test_exit_status === 0
              : fresh.summary?.regression_test_exit_status !== 0
          ),
        "ORDINARY_FAILURE_CONTROL_INVALID",
        `ordinary failure ${caseId} late spine did not independently fail at the declared boundary`,
        `${caseBase}/spine`,
      );
      lateFailures += 1;
    } else {
      earlyFailures += 1;
    }
    const actualCaseFiles = manifestState.manifest.entries
      .filter((entry) => entry.path.startsWith(`${caseBase}/`))
      .map((entry) => entry.path);
    assert(
      isDeepStrictEqual(actualCaseFiles, expectedCaseFiles.sort()),
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} case inventory drifted`,
      caseBase,
    );
    const event = events[index];
    exactKeys(
      event,
      [
        "case_id",
        "cell_closure_identity",
        "failure_stage",
        "schema_version",
        "sequence",
        "task_id",
      ],
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} event`,
      eventsPath,
    );
    assert(
      event.schema_version === "p1-165-ordinary-failure-event/v1"
        && event.task_id === TASK_ID
        && event.sequence === index + 1
        && event.case_id === caseId
        && event.failure_stage === failureStage,
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure ${caseId} event drifted`,
      eventsPath,
    );
    validateArtifactDescriptor(
      event.cell_closure_identity,
      closurePath,
      manifestState,
      `ordinary failure ${caseId} event closure`,
      eventsPath,
    );
    denominator += 1;
  }
  const continuationEvent = events[ORDINARY_FAILURE_CASES.length];
  exactKeys(
    continuationEvent,
    [
      "cell_closure_identity",
      "cell_id",
      "event_type",
      "schema_version",
      "sequence",
      "status",
      "task_id",
    ],
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary accepted continuation event",
    eventsPath,
  );
  assert(
    continuationEvent.schema_version
      === "p1-165-ordinary-continuation-event/v1"
      && continuationEvent.task_id === TASK_ID
      && continuationEvent.sequence === ORDINARY_FAILURE_CASES.length + 1
      && continuationEvent.event_type === "ACCEPTED_CONTINUATION"
      && continuationEvent.cell_id === "P1-165-CELL-01"
      && continuationEvent.status === "PASS",
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary accepted continuation event drifted",
    eventsPath,
  );
  const continuationEventClosure = validateBoundIdentity(
    continuationEvent.cell_closure_identity,
    manifestState,
    "ordinary accepted continuation event closure",
  );
  assert(
    continuationEventClosure.path
      === "raw/cells/P1-165-CELL-01/cell-closure.json",
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary accepted continuation event closure path drifted",
    eventsPath,
  );
  const receipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "ordinary failure continuation receipt",
  );
  exactKeys(
    receipt,
    [
      "case_order",
      "continuation_cell_id",
      "continuation_closure_identity",
      "early_failure_cases",
      "failed_denominator_cases",
      "failure_stage_order",
      "late_failure_cases",
      "schema_version",
      "status",
      "task_id",
    ],
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure continuation receipt",
    receiptPath,
  );
  assert(
    receipt.schema_version === "p1-165-ordinary-failure-continuation/v1"
      && receipt.task_id === TASK_ID
      && receipt.status === "PASS"
      && isDeepStrictEqual(receipt.case_order, caseOrder)
      && isDeepStrictEqual(receipt.failure_stage_order, stageOrder)
      && receipt.failed_denominator_cases === denominator
      && receipt.early_failure_cases === earlyFailures
      && receipt.late_failure_cases === lateFailures
      && receipt.continuation_cell_id === "P1-165-CELL-01"
      && denominator === 6
      && earlyFailures === 4
      && lateFailures === 2,
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure continuation accounting drifted",
    receiptPath,
  );
  const continuationReceiptClosure = validateBoundIdentity(
    receipt.continuation_closure_identity,
    manifestState,
    "ordinary failure accepted continuation closure",
  );
  assert(
    continuationReceiptClosure.path
        === "raw/cells/P1-165-CELL-01/cell-closure.json"
      && isDeepStrictEqual(
        continuationReceiptClosure,
        continuationEventClosure,
      ),
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure continuation closures are not the same exact file",
    receiptPath,
  );
  return {
    status: "PASS",
    failed_denominator_cases: denominator,
    early_failures: earlyFailures,
    late_failures: lateFailures,
    continued_to_accepted_cell: true,
    worker_success_fields_trusted: false,
  };
}

function controlAdapterDescriptor(cellState, manifestState, label, path) {
  const adapterCell = cellState.cells.find(
    (cell) =>
      cell.profile_id === "B0_A"
      && cell.task_id === ACCEPTED_TASK_IDS[0],
  );
  assert(
    adapterCell !== undefined,
    "CONTROL_EVIDENCE_INVALID",
    `${label} accepted adapter is missing`,
    path,
  );
  const descriptor = manifestState.byPath.get(
    adapterCell.adapter_control_path,
  );
  assert(
    descriptor !== undefined,
    "CONTROL_EVIDENCE_INVALID",
    `${label} accepted adapter descriptor is missing`,
    adapterCell.adapter_control_path,
  );
  return descriptor;
}

function outputTokenJoin(outputTokens) {
  return {
    execution_id: `P1-165-TOKEN-${outputTokens}`,
    cell_id: `P1-165-TOKEN-${outputTokens}`,
    task_id: TASK_ID,
    profile_id: "B0_A",
    repetition_id: "A",
  };
}

function validateLateFailureRawReceipts(spine, failureStage, spineBase) {
  const testPath = `${spineBase}/test-receipt.json`;
  const oraclePath = `${spineBase}/oracle-receipt.json`;
  const testArtifact = spine.artifacts.get("test-receipt.json");
  const oracleArtifact = spine.artifacts.get("oracle-receipt.json");
  const test = parseJsonBytes(
    testArtifact.bytes,
    "ordinary failure raw test receipt",
    testPath,
  );
  exactKeys(
    test,
    [
      "commands",
      "external_effects",
      "schema_version",
      "stage",
      "task_id",
    ],
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure raw test receipt",
    testPath,
  );
  assert(
    test.schema_version === "p1-149-test-receipt/v1"
      && test.task_id === ACCEPTED_TASK_IDS[0]
      && test.stage === "POST_APPLICATION"
      && Array.isArray(test.commands)
      && test.commands.length === 2,
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure raw test receipt fixed fields drifted",
    testPath,
  );
  assertFalseEffects(test.external_effects, "ordinary raw test receipt", testPath);
  const commandById = new Map();
  for (const [index, command] of test.commands.entries()) {
    exactKeys(
      command,
      [
        "argv",
        "command_id",
        "expected_exit_codes",
        "external_effects",
        "observed_exit_status",
        "observed_signal",
        "role",
        "schema_version",
        "stderr",
        "stdout",
      ],
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure raw command ${index}`,
      testPath,
    );
    assert(
      command.schema_version === "p1-149-test-command-receipt/v1"
        && ["issue-test", "regression-test"].includes(command.command_id)
        && !commandById.has(command.command_id)
        && Array.isArray(command.argv)
        && command.argv.length >= 1
        && command.argv.every(
          (value) => typeof value === "string" && !value.includes("\0"),
        )
        && isDeepStrictEqual(command.expected_exit_codes, [0])
        && Number.isInteger(command.observed_exit_status)
        && command.observed_signal === null,
      "ORDINARY_FAILURE_CONTROL_INVALID",
      `ordinary failure raw command ${index} identity drifted`,
      testPath,
    );
    assertFalseEffects(
      command.external_effects,
      `ordinary raw command ${command.command_id}`,
      testPath,
    );
    for (const [streamName, stream] of [
      ["stdout", command.stdout],
      ["stderr", command.stderr],
    ]) {
      exactKeys(
        stream,
        ["base64", "identity"],
        "ORDINARY_FAILURE_CONTROL_INVALID",
        `ordinary raw command ${command.command_id} ${streamName}`,
        testPath,
      );
      const bytes = decodeCanonicalBase64(
        stream.base64,
        "ORDINARY_FAILURE_CONTROL_INVALID",
        `ordinary raw command ${command.command_id} ${streamName}`,
        testPath,
      );
      validateBytesIdentity(
        stream.identity,
        {
          byte_length: bytes.length,
          sha256: sha256(bytes),
        },
        `ordinary raw command ${command.command_id} ${streamName}`,
        testPath,
      );
    }
    commandById.set(command.command_id, command);
  }
  assert(
    isDeepStrictEqual(
      test.commands.map((command) => command.command_id),
      ["issue-test", "regression-test"],
    ),
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure raw command order drifted",
    testPath,
  );
  const issueExit = commandById.get("issue-test").observed_exit_status;
  const regressionExit =
    commandById.get("regression-test").observed_exit_status;
  const oracle = parseJsonBytes(
    oracleArtifact.bytes,
    "ordinary failure raw oracle receipt",
    oraclePath,
  );
  exactKeys(
    oracle,
    [
      "external_effects",
      "independently_observed_postcondition",
      "observed_precondition",
      "result_classification",
      "schema_version",
      "task_id",
      "test_receipt",
    ],
    "ORDINARY_FAILURE_CONTROL_INVALID",
    "ordinary failure raw oracle receipt",
    oraclePath,
  );
  validateBytesIdentity(
    oracle.test_receipt,
    {
      byte_length: testArtifact.bytes.length,
      sha256: sha256(testArtifact.bytes),
    },
    "ordinary failure oracle test receipt identity",
    oraclePath,
  );
  assertFalseEffects(
    oracle.external_effects,
    "ordinary raw oracle receipt",
    oraclePath,
  );
  assert(
    oracle.schema_version === "p1-149-oracle-receipt/v1"
      && oracle.task_id === ACCEPTED_TASK_IDS[0]
      && oracle.result_classification === "FAILED"
      && oracle.independently_observed_postcondition?.issue_test_passed
        === (issueExit === 0)
      && oracle.independently_observed_postcondition?.regression_test_passed
        === (regressionExit === 0)
      && (
        failureStage === "ORACLE"
          ? issueExit !== 0
            && regressionExit === 0
            && oracle.independently_observed_postcondition
              ?.issue_test_passed === false
            && oracle.independently_observed_postcondition
              ?.regression_test_passed === true
          : failureStage === "TEST"
            && regressionExit !== 0
            && oracle.independently_observed_postcondition
              ?.regression_test_passed === false
      ),
    "ORDINARY_FAILURE_CONTROL_INVALID",
    `ordinary ${failureStage} raw oracle/test receipts do not prove the declared boundary`,
    oraclePath,
  );
  return {
    engine_reason_code: failureStage === "ORACLE"
      ? "ORACLE_POSTCONDITION_FAILED"
      : "TEST_COMMAND_FAILED",
    issue_test_exit_status: issueExit,
    regression_test_exit_status: regressionExit,
  };
}

async function replayOutputTokenOverflowAtHighLevel({
  modules,
  syntheticObserverFixture,
  adapterDescriptor,
  bodyBytes,
}) {
  const {
    cleanupOwnedRoot,
    createDisposableRoot,
    writeBytesCreateOnce,
  } = await import(
    "../../harness/p1-149-accepted-execution-spine/core.mjs"
  );
  const attempt = createDisposableRoot("p165-evaluator-token-2049");
  let quarantine = null;
  let observedReasonCode = null;
  let admittedResponsePersisted = false;
  let admissionReceiptPersisted = false;
  try {
    quarantine = createDisposableRoot(
      "p165-evaluator-token-2049-quarantine",
    );
    const joinValue = outputTokenJoin(2049);
    const policy = JSON.parse(JSON.stringify(syntheticObserverFixture.record.policy));
    const adapterIdentity = {
      path: adapterDescriptor.path,
      byte_length: adapterDescriptor.byte_length,
      sha256: adapterDescriptor.sha256,
    };
    const requestBodyBytes = Buffer.from(`${canonicalJson({
      schema_version: "p1-165-control-admission-request/v1",
      case_id: "OUTPUT_TOKENS_2049",
    })}\n`, "utf8");
    const contextBytes = Buffer.from(`${canonicalJson({
      schema_version: "p1-165-context-record/v1",
      task_id: TASK_ID,
      join: joinValue,
      adapter_result_identity: adapterIdentity,
    })}\n`, "utf8");
    const requestRecordBytes = Buffer.from(`${canonicalJson({
      schema_version: "p1-165-request-record/v1",
      task_id: TASK_ID,
      join: joinValue,
      context_record_identity: {
        byte_length: contextBytes.length,
        sha256: sha256(contextBytes),
      },
      request_body_identity: {
        byte_length: requestBodyBytes.length,
        sha256: sha256(requestBodyBytes),
      },
      policy,
    })}\n`, "utf8");
    const requestIdentity = {
      byte_length: requestRecordBytes.length,
      sha256: sha256(requestRecordBytes),
    };
    const rawResponse = Buffer.concat([
      Buffer.from(
        [
          "HTTP/1.1 200 OK",
          "Content-Type: application/json",
          `Content-Length: ${bodyBytes.length}`,
          "Connection: close",
          "",
          "",
        ].join("\r\n"),
        "latin1",
      ),
      bodyBytes,
    ]);
    const analyzed = modules.transport.analyzeTransport({
      join: joinValue,
      request_record_identity: requestIdentity,
      chunks: [rawResponse],
      eof: true,
      stream_terminal_events: [],
      policy,
      observed_peer: policy.expected_peer,
    });
    const observerRecord = {
      ...JSON.parse(JSON.stringify(syntheticObserverFixture.record)),
      join: joinValue,
      request_record_identity: requestIdentity,
      policy,
      stdout_path: "supporting/observer-stdout.log",
      stderr_path: "supporting/observer-stderr.log",
    };
    const usage = modules.contract.observedUsage({
      join: joinValue,
      responseIdentity: analyzed.record.body_identity,
      inputTokens: 0,
      outputTokens: 2049,
    });
    const supportingPaths = {
      context_record: "supporting/context.json",
      request_body: "supporting/request.raw",
      request_record: "supporting/request-record.json",
      transport_record: "supporting/transport-record.json",
      observer_stdout: "supporting/observer-stdout.log",
      observer_stderr: "supporting/observer-stderr.log",
      observer_record: "supporting/observer.json",
      usage_record: "supporting/usage.json",
    };
    const supportingBytes = {
      context_record: contextBytes,
      request_body: requestBodyBytes,
      request_record: requestRecordBytes,
      transport_record: Buffer.from(
        `${canonicalJson(analyzed.record)}\n`,
        "utf8",
      ),
      observer_stdout: syntheticObserverFixture.stdout,
      observer_stderr: syntheticObserverFixture.stderr,
      observer_record: Buffer.from(
        `${canonicalJson(observerRecord)}\n`,
        "utf8",
      ),
      usage_record: Buffer.from(`${canonicalJson(usage)}\n`, "utf8"),
    };
    const supportingArtifacts = {};
    for (const key of Object.keys(supportingPaths)) {
      supportingArtifacts[key] = writeBytesCreateOnce(
        attempt,
        supportingPaths[key],
        supportingBytes[key],
      );
    }
    writeBytesCreateOnce(quarantine, "response.http", rawResponse);
    try {
      modules.admission.admitAndPersistResponse({
        evidence_handle: attempt,
        quarantine_handle: quarantine,
        quarantine_relative_path: "response.http",
        admitted_relative_path: "admission/admitted-response.http",
        receipt_relative_path: "admission/admission-receipt.json",
        join: joinValue,
        request_record_identity: requestIdentity,
        request_record_bytes: requestRecordBytes,
        context_record_bytes: contextBytes,
        request_body_bytes: requestBodyBytes,
        policy,
        observed_peer: policy.expected_peer,
        transport_chunks: [rawResponse],
        eof: true,
        stream_terminal_events: [],
        observer_record: observerRecord,
        observer_stdout_bytes: syntheticObserverFixture.stdout,
        observer_stderr_bytes: syntheticObserverFixture.stderr,
        usage_record: usage,
        secret_sentinel: Buffer.from(
          "P1-165-EVALUATOR-TOKEN-2049-SECRET-SENTINEL",
          "utf8",
        ),
        supporting_artifacts: supportingArtifacts,
      });
    } catch (error) {
      observedReasonCode = error?.code ?? null;
    }
    admittedResponsePersisted =
      optionalLstat(join(attempt.root, "admission/admitted-response.http"))
        !== null;
    admissionReceiptPersisted =
      optionalLstat(join(attempt.root, "admission/admission-receipt.json"))
        !== null;
    assert(
      observedReasonCode === "PROVIDER_OUTPUT_USAGE_EXCEEDED"
        && admittedResponsePersisted === false
        && admissionReceiptPersisted === false,
      "OUTPUT_TOKEN_CONTROL_INVALID",
      "independent high-level 2049 replay did not fail before persistence",
    );
  } finally {
    try {
      if (quarantine !== null && optionalLstat(quarantine.root) !== null) {
        cleanupOwnedRoot(quarantine);
      }
    } finally {
      if (optionalLstat(attempt.root) !== null) cleanupOwnedRoot(attempt);
    }
  }
  assert(
    optionalLstat(attempt.root) === null
      && quarantine !== null
      && optionalLstat(quarantine.root) === null,
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "independent high-level 2049 replay left a temporary root",
  );
  return {
    status: "PASS",
    reason_code: observedReasonCode,
    admitted_response_persisted: admittedResponsePersisted,
    admission_receipt_persisted: admissionReceiptPersisted,
    attempt_root_cleaned: true,
    quarantine_root_cleaned: true,
  };
}

async function validateOutputTokenBoundaryControls(
  root,
  manifestState,
  cellState,
  syntheticObserverFixture,
) {
  const base = "raw/token-boundary";
  const contractPath = `${base}/contract.json`;
  const receiptPath = `${base}/receipt.json`;
  const contract = readBoundJson(
    root,
    manifestState,
    contractPath,
    "output-token boundary contract",
  );
  exactKeys(
    contract,
    [
      "case_order",
      "exact_boundary_requires_full_p1_149_spine",
      "output_tokens_max",
      "schema_version",
      "semantics",
      "task_id",
    ],
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "output-token boundary contract",
    contractPath,
  );
  assert(
    contract.schema_version
      === "p1-165-output-token-boundary-contract/v1"
      && contract.task_id === TASK_ID
      && contract.output_tokens_max === OUTPUT_TOKENS_MAX
      && isDeepStrictEqual(contract.case_order, OUTPUT_TOKEN_CASES)
      && contract.semantics === OUTPUT_TOKEN_SEMANTICS
      && contract.exact_boundary_requires_full_p1_149_spine === true,
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "output-token boundary contract drifted",
    contractPath,
  );
  const modules = await loadProductionKernel();
  const adapterDescriptor = controlAdapterDescriptor(
    cellState,
    manifestState,
    "output-token boundary",
    contractPath,
  );
  const admitted = new Map();
  for (const outputTokens of [2047, 2048]) {
    admitted.set(
      outputTokens,
      validateAdmittedControl(
        root,
        manifestState,
        `${base}/cases/${outputTokens}`,
        outputTokenJoin(outputTokens),
        modules,
        syntheticObserverFixture,
      ),
    );
  }
  const commonBodyIdentity = admitted.get(2048).state.body_identity;
  validateBytesIdentity(
    admitted.get(2047).state.body_identity,
    commonBodyIdentity,
    "2047/2048 output-token response body identity",
    `${base}/cases/2047/admission/admission-receipt.json`,
  );
  const results = new Map();
  const outerUsage = new Map();
  let exactBoundarySpines = 0;
  for (const outputTokens of [2047, 2048]) {
    const caseBase = `${base}/cases/${outputTokens}`;
    const usagePath = `${caseBase}/usage.json`;
    const resultPath = `${caseBase}/result.json`;
    const usage = readBoundJson(
      root,
      manifestState,
      usagePath,
      `output-token ${outputTokens} usage`,
    );
    outerUsage.set(outputTokens, usage);
    const joinValue = outputTokenJoin(outputTokens);
    const validated = modules.contract.validateUsage(
      usage,
      {
        join: joinValue,
        responseIdentity: commonBodyIdentity,
        policy: admitted.get(outputTokens).request.policy,
      },
      `output-token ${outputTokens} usage`,
    );
    assert(
      isDeepStrictEqual(validated, usage)
        && isDeepStrictEqual(usage, admitted.get(outputTokens).usage),
      "OUTPUT_TOKEN_CONTROL_INVALID",
      `output-token ${outputTokens} outer/supporting usage differs`,
      usagePath,
    );
    const result = readBoundJson(
      root,
      manifestState,
      resultPath,
      `output-token ${outputTokens} result`,
    );
    exactKeys(
      result,
      [
        "admission_receipt_identity",
        "cell_closure_identity",
        "expected_status",
        "observed_reason_code",
        "observed_status",
        "output_tokens",
        "p1_101_receipt_count",
        "p1_149_artifact_count",
        "safe_failure_receipt_identity",
        "schema_version",
        "semantics",
        "status",
        "task_id",
      ],
      "OUTPUT_TOKEN_CONTROL_INVALID",
      `output-token ${outputTokens} result`,
      resultPath,
    );
    const expectedStatus = "PASS";
    const expectedReason = "PASS";
    const expectedSpineCount = outputTokens === 2048
      ? SPINE_ARTIFACTS.length
      : 0;
    const expectedP101 = outputTokens === 2048 ? 2 : 0;
    assert(
      result.schema_version === "p1-165-output-token-boundary-case/v1"
        && result.task_id === TASK_ID
        && result.output_tokens === outputTokens
        && result.semantics === OUTPUT_TOKEN_SEMANTICS
        && result.expected_status === expectedStatus
        && result.observed_status === expectedStatus
        && result.observed_reason_code === expectedReason
        && result.p1_149_artifact_count === expectedSpineCount
        && result.p1_101_receipt_count === expectedP101
        && result.status === "PASS",
      "OUTPUT_TOKEN_CONTROL_INVALID",
      `output-token ${outputTokens} result drifted`,
      resultPath,
    );
    const expectedCasePaths = [usagePath, resultPath];
    const admission = admitted.get(outputTokens);
    validateArtifactDescriptor(
      result.admission_receipt_identity,
      admission.paths.receipt,
      manifestState,
      `output-token ${outputTokens} admission receipt`,
      resultPath,
    );
    assert(
      result.safe_failure_receipt_identity === null,
      "OUTPUT_TOKEN_CONTROL_INVALID",
      `accepted output-token ${outputTokens} bound a failure receipt`,
      resultPath,
    );
    expectedCasePaths.push(...Object.values(admission.paths));
    if (outputTokens === 2047) {
      assert(
        result.cell_closure_identity === null,
        "OUTPUT_TOKEN_CONTROL_INVALID",
        "2047 control unexpectedly completed an execution spine",
        resultPath,
      );
    } else {
        const closurePath = `${caseBase}/cell-closure.json`;
        const closure = readBoundJson(
          root,
          manifestState,
          closurePath,
          "output-token 2048 cell closure",
        );
        validateArtifactDescriptor(
          result.cell_closure_identity,
          closurePath,
          manifestState,
          "output-token 2048 closure descriptor",
          resultPath,
        );
        const spine = validateSpineRaw(
          root,
          manifestState,
          `${caseBase}/spine`,
          "P1-165-TOKEN-BOUNDARY-2048",
          ACCEPTED_TASK_IDS[0],
        );
        validateProductionCellClosure({
          base: caseBase,
          joinRecord: outputTokenJoin(2048),
          manifestState,
          closure,
          admissionState: admission.state,
          admitted: admission.admitted,
          requestRecordIdentity: bytesIdentityFromBound(
            manifestState.byPath.get(admission.paths.request_record),
          ),
          spine,
          adapterDescriptor,
          b2ScanDescriptor: null,
        });
        const { executeSpine } = await import(
          "../../harness/p1-149-accepted-execution-spine/execution.mjs"
        );
        const fresh = await executeSpine({
          taskId: ACCEPTED_TASK_IDS[0],
          responseBytes: admission.body_bytes,
          runId: "P1-165-TOKEN-BOUNDARY-2048",
        });
        assert(
          fresh.summary?.worker_observed_classification === "VERIFIED_SUCCESS"
            && fresh.summary?.p1_101_replay === "PASS"
            && fresh.summary?.rollback_exact === true
            && canonicalJson(fresh.stable_projection)
              === canonicalJson(spine.stable_projection),
          "OUTPUT_TOKEN_CONTROL_INVALID",
          "2048 exact boundary did not independently complete the accepted spine",
          `${caseBase}/spine`,
        );
        expectedCasePaths.push(
          closurePath,
          ...SPINE_ARTIFACTS.map((name) => `${caseBase}/spine/${name}`),
        );
      exactBoundarySpines += 1;
    }
    const actualCasePaths = manifestState.manifest.entries
      .filter((entry) => entry.path.startsWith(`${caseBase}/`))
      .map((entry) => entry.path);
    assert(
      isDeepStrictEqual(actualCasePaths, expectedCasePaths.sort()),
      "OUTPUT_TOKEN_CONTROL_INVALID",
      `output-token ${outputTokens} case inventory drifted`,
      caseBase,
    );
    results.set(outputTokens, result);
  }
  validateBytesIdentity(
    outerUsage.get(2047).response_identity,
    commonBodyIdentity,
    "output-token 2047 common response identity",
    `${base}/cases/2047/usage.json`,
  );
  const safe2049Path =
    `${base}/cases/2049/safe-failure-receipt.json`;
  const safe2049 = readBoundJson(
    root,
    manifestState,
    safe2049Path,
    "output-token 2049 safe failure receipt",
  );
  exactKeys(
    safe2049,
    SAFE_FAILURE_RECEIPT_KEYS,
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "output-token 2049 safe failure receipt",
    safe2049Path,
  );
  assert(
    safe2049.schema_version === "p1-165-safe-failure-receipt/v1"
      && safe2049.task_id === TASK_ID
      && isDeepStrictEqual(safe2049.join, outputTokenJoin(2049))
      && safe2049.reason_code === "PROVIDER_OUTPUT_USAGE_EXCEEDED"
      && safe2049.response_persisted === false
      && safe2049.secret_persisted === false
      && safe2049.status === "NON_PASS"
      && safe2049.message
        === "response admission failed closed before persistence",
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "output-token 2049 safe failure receipt drifted",
    safe2049Path,
  );
  const safe2049RootPaths = manifestState.manifest.entries
    .filter((entry) => entry.path.startsWith(`${base}/cases/2049/`))
    .map((entry) => entry.path);
  assert(
    isDeepStrictEqual(safe2049RootPaths, [safe2049Path]),
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "output-token 2049 retained anything except its safe failure receipt",
    `${base}/cases/2049`,
  );
  const overflowReplay = await replayOutputTokenOverflowAtHighLevel({
    modules,
    syntheticObserverFixture,
    adapterDescriptor,
    bodyBytes: admitted.get(2048).body_bytes,
  });
  const receipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "output-token boundary receipt",
  );
  exactKeys(
    receipt,
    [
      "case_order",
      "exact_boundary_full_p1_149_artifact_count",
      "exact_boundary_p1_101_receipt_count",
      "observed_statuses",
      "overflow_admission_absent",
      "overflow_spine_absent",
      "schema_version",
      "status",
      "task_id",
    ],
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "output-token boundary receipt",
    receiptPath,
  );
  assert(
    receipt.schema_version === "p1-165-output-token-boundary-receipt/v1"
      && receipt.task_id === TASK_ID
      && isDeepStrictEqual(receipt.case_order, OUTPUT_TOKEN_CASES)
      && isDeepStrictEqual(
        receipt.observed_statuses,
        ["PASS", "PASS", "NON_PASS"],
      )
      && receipt.exact_boundary_full_p1_149_artifact_count
        === SPINE_ARTIFACTS.length
      && receipt.exact_boundary_p1_101_receipt_count === 2
      && receipt.overflow_admission_absent === true
      && receipt.overflow_spine_absent === true
      && receipt.status === "PASS"
      && exactBoundarySpines === 1,
    "OUTPUT_TOKEN_CONTROL_INVALID",
    "output-token boundary aggregate drifted",
    receiptPath,
  );
  return {
    status: "PASS",
    semantics: OUTPUT_TOKEN_SEMANTICS,
    boundaries: {
      "2047": "ACCEPTED",
      "2048": "ACCEPTED_FULL_SPINE",
      "2049": "REJECTED_BEFORE_PERSISTENCE",
    },
    exact_boundary_spines: exactBoundarySpines,
    overflow_high_level_replay: overflowReplay,
  };
}

function validateObserverRawClosureIntegrationFixture({
  root,
  manifestState,
  caseId,
  reasonCode,
  result,
  expectedPaths,
  modules,
}) {
  const fixtureBase =
    `raw/integration-negative-control/fixtures/${caseId}`;
  const descriptorPath = `${fixtureBase}/fixture.json`;
  const observerPath = `${fixtureBase}/observation.json`;
  const stdoutPath = `${fixtureBase}/stdout.log`;
  const stderrPath = `${fixtureBase}/stderr.log`;
  expectedPaths.push(
    descriptorPath,
    observerPath,
    stdoutPath,
    stderrPath,
  );
  validateArtifactDescriptor(
    result.raw_fixture_descriptor_identity,
    descriptorPath,
    manifestState,
    `integration-negative ${caseId} raw fixture descriptor`,
    `raw/integration-negative-control/cases/${caseId}.json`,
  );
  const descriptor = readBoundJson(
    root,
    manifestState,
    descriptorPath,
    `integration-negative ${caseId} raw fixture descriptor`,
  );
  exactKeys(
    descriptor,
    [
      "additional_nonloopback_rows",
      "case_id",
      "command_executed",
      "expected_reason_code",
      "live_network_connections_created",
      "malformed_data_rows",
      "normalized_header_matches",
      "observer_record_identity",
      "policy_bound_rows",
      "raw_nonempty_data_rows",
      "record_observed_rows",
      "schema_version",
      "status",
      "stderr_identity",
      "stdout_identity",
      "task_id",
    ],
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    `integration-negative ${caseId} raw fixture descriptor`,
    descriptorPath,
  );
  validateArtifactDescriptor(
    descriptor.observer_record_identity,
    observerPath,
    manifestState,
    `integration-negative ${caseId} observer record`,
    descriptorPath,
  );
  validateArtifactDescriptor(
    descriptor.stdout_identity,
    stdoutPath,
    manifestState,
    `integration-negative ${caseId} observer stdout`,
    descriptorPath,
  );
  validateArtifactDescriptor(
    descriptor.stderr_identity,
    stderrPath,
    manifestState,
    `integration-negative ${caseId} observer stderr`,
    descriptorPath,
  );
  const observer = readBoundJson(
    root,
    manifestState,
    observerPath,
    `integration-negative ${caseId} observer record`,
  );
  const stdout = readBoundBytes(
    root,
    manifestState,
    stdoutPath,
    `integration-negative ${caseId} observer stdout`,
  );
  const stderr = readBoundBytes(
    root,
    manifestState,
    stderrPath,
    `integration-negative ${caseId} observer stderr`,
  );
  validateBytesIdentity(
    observer.stdout_identity,
    plainIdentity(stdout.bytes),
    `integration-negative ${caseId} embedded stdout`,
    observerPath,
  );
  validateBytesIdentity(
    observer.stderr_identity,
    plainIdentity(stderr.bytes),
    `integration-negative ${caseId} embedded stderr`,
    observerPath,
  );
  const text = new TextDecoder("utf-8", { fatal: true })
    .decode(stdout.bytes);
  const lines = text.split("\n");
  assert(
    lines.at(-1) === "",
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    `integration-negative ${caseId} stdout is not newline terminated`,
    stdoutPath,
  );
  lines.pop();
  const normalizedHeader =
    lines[0]?.trim().split(/\s+/).join(" ")
      === "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME";
  const dataLines = lines.slice(1)
    .filter((line) => line.trim().length > 0);
  const independentlyParsedRows = parseLsofRows(stdout.bytes);
  const policyBoundRows = observer.observed_rows.filter(
    (row) =>
      row.peer === observer.policy.expected_peer
      && row.state === "ESTABLISHED",
  ).length;
  const nonloopbackRows = observer.observed_rows.filter(
    (row) => !row.peer.startsWith("127.0.0.1:"),
  ).length;
  const expectedShape = {
    OBSERVER_EXTRA_ROW: {
      data_rows: 2,
      parsed_rows: 2,
      record_rows: 2,
      policy_rows: 1,
      nonloopback_rows: 1,
      malformed_rows: 0,
      normalized_header: true,
    },
    OBSERVER_MALFORMED_EXTRA_ROW: {
      data_rows: 2,
      parsed_rows: 1,
      record_rows: 1,
      policy_rows: 1,
      nonloopback_rows: 0,
      malformed_rows: 1,
      normalized_header: true,
    },
    OBSERVER_BAD_HEADER: {
      data_rows: 1,
      parsed_rows: 1,
      record_rows: 1,
      policy_rows: 1,
      nonloopback_rows: 0,
      malformed_rows: 0,
      normalized_header: false,
    },
  }[caseId];
  assert(
    expectedShape !== undefined
      && descriptor.schema_version
        === "p1-168-observer-raw-closure-integration-fixture/v1"
      && descriptor.task_id === TASK_ID
      && descriptor.case_id === caseId
      && descriptor.expected_reason_code === reasonCode
      && descriptor.raw_nonempty_data_rows === expectedShape.data_rows
      && descriptor.record_observed_rows === expectedShape.record_rows
      && descriptor.policy_bound_rows === expectedShape.policy_rows
      && descriptor.additional_nonloopback_rows
        === expectedShape.nonloopback_rows
      && descriptor.malformed_data_rows === expectedShape.malformed_rows
      && descriptor.normalized_header_matches
        === expectedShape.normalized_header
      && descriptor.command_executed === false
      && descriptor.live_network_connections_created === 0
      && descriptor.status === "FROZEN_NEGATIVE_FIXTURE"
      && dataLines.length === expectedShape.data_rows
      && independentlyParsedRows.length === expectedShape.parsed_rows
      && observer.observed_rows.length === expectedShape.record_rows
      && policyBoundRows === expectedShape.policy_rows
      && nonloopbackRows === expectedShape.nonloopback_rows
      && dataLines.length - independentlyParsedRows.length
        === expectedShape.malformed_rows
      && normalizedHeader === expectedShape.normalized_header
      && isDeepStrictEqual(
        observer.observed_rows,
        independentlyParsedRows,
      ),
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    `integration-negative ${caseId} raw fixture drifted`,
    descriptorPath,
  );
  let observedReasonCode = null;
  try {
    modules.observer.validateRawObservation({
      record: observer,
      stdout_bytes: stdout.bytes,
      stderr_bytes: stderr.bytes,
      join: observer.join,
      request_record_identity: observer.request_record_identity,
      policy: observer.policy,
    });
  } catch (error) {
    if (error instanceof modules.contract.AdmissionNonPass) {
      observedReasonCode = error.code;
    } else {
      throw error;
    }
  }
  assert(
    observedReasonCode === "OBSERVER_EVIDENCE_FORGED",
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    `integration-negative ${caseId} did not independently fail closed`,
    descriptorPath,
  );
}

async function validateIntegrationNegativeControls(root, manifestState) {
  const base = "raw/integration-negative-control";
  const planPath = `${base}/plan.json`;
  const receiptPath = `${base}/receipt.json`;
  const plan = readBoundJson(
    root,
    manifestState,
    planPath,
    "integration-negative plan",
  );
  exactKeys(
    plan,
    [
      "attempt_root_policy",
      "cases",
      "final_response_policy",
      "high_level_entry",
      "schema_version",
      "task_id",
    ],
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    "integration-negative plan",
    planPath,
  );
  const caseOrder =
    INTEGRATION_NEGATIVE_CASES.map((entry) => entry.case_id);
  const expectedPlanCases = INTEGRATION_NEGATIVE_CASES.map(
    (entry, index) => ({
      sequence: index + 1,
      ...entry,
    }),
  );
  assert(
    plan.schema_version === "p1-165-integration-negative-plan/v3"
      && plan.task_id === TASK_ID
      && isDeepStrictEqual(plan.cases, expectedPlanCases)
      && plan.high_level_entry === "admitAndPersistResponse"
      && plan.final_response_policy === "ABSENT"
      && plan.attempt_root_policy === "CLEANED",
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    "integration-negative plan drifted",
    planPath,
  );
  const expectedPaths = [planPath, receiptPath];
  const modules = await loadProductionKernel();
  for (const [index, casePlan] of INTEGRATION_NEGATIVE_CASES.entries()) {
    const {
      case_id: caseId,
      expected_reason_code: reasonCode,
      output_tokens: outputTokens,
    } = casePlan;
    const resultPath = `${base}/cases/${caseId}.json`;
    const safePath =
      `${base}/failures/${caseId}/safe-failure-receipt.json`;
    expectedPaths.push(resultPath, safePath);
    const result = readBoundJson(
      root,
      manifestState,
      resultPath,
      `integration-negative ${caseId} result`,
    );
    exactKeys(
      result,
      [
        "admission_receipt_persisted",
        "admitted_response_persisted",
        "attempt_root_absent",
        "case_id",
        "expected_reason_code",
        "observed_reason_code",
        "output_tokens",
        "quarantine_root_absent",
        "raw_fixture_descriptor_identity",
        "safe_failure_receipt_identity",
        "schema_version",
        "status",
        "task_id",
      ],
      "INTEGRATION_NEGATIVE_CONTROL_INVALID",
      `integration-negative ${caseId} result`,
      resultPath,
    );
    assert(
      result.schema_version === "p1-165-integration-negative-case/v3"
        && result.task_id === TASK_ID
        && result.case_id === caseId
        && result.output_tokens === outputTokens
        && result.expected_reason_code === reasonCode
        && result.observed_reason_code === reasonCode
        && result.attempt_root_absent === true
        && result.quarantine_root_absent === true
        && result.admitted_response_persisted === false
        && result.admission_receipt_persisted === false
        && result.status === "PASS",
      "INTEGRATION_NEGATIVE_CONTROL_INVALID",
      `integration-negative ${caseId} result drifted`,
      resultPath,
    );
    const observerRawClosureCase = [
      "OBSERVER_EXTRA_ROW",
      "OBSERVER_MALFORMED_EXTRA_ROW",
      "OBSERVER_BAD_HEADER",
    ].includes(caseId);
    if (observerRawClosureCase) {
      validateObserverRawClosureIntegrationFixture({
        root,
        manifestState,
        caseId,
        reasonCode,
        result,
        expectedPaths,
        modules,
      });
    } else {
      assert(
        result.raw_fixture_descriptor_identity === null,
        "INTEGRATION_NEGATIVE_CONTROL_INVALID",
        `integration-negative ${caseId} has an unexpected raw fixture`,
        resultPath,
      );
    }
    validateArtifactDescriptor(
      result.safe_failure_receipt_identity,
      safePath,
      manifestState,
      `integration-negative ${caseId} safe receipt`,
      resultPath,
    );
    const safeReceipt = readBoundJson(
      root,
      manifestState,
      safePath,
      `integration-negative ${caseId} safe receipt`,
    );
    exactKeys(
      safeReceipt,
      SAFE_FAILURE_RECEIPT_KEYS,
      "INTEGRATION_NEGATIVE_CONTROL_INVALID",
      `integration-negative ${caseId} safe receipt`,
      safePath,
    );
    const expectedJoin = {
      execution_id: `P1-165-INTEGRATION-${String(index + 1).padStart(2, "0")}`,
      cell_id: `P1-165-INTEGRATION-${String(index + 1).padStart(2, "0")}`,
      task_id: TASK_ID,
      profile_id: "B0_A",
      repetition_id: "A",
    };
    assert(
      safeReceipt.schema_version === "p1-165-safe-failure-receipt/v1"
        && safeReceipt.task_id === TASK_ID
        && isDeepStrictEqual(safeReceipt.join, expectedJoin)
        && safeReceipt.reason_code === reasonCode
        && safeReceipt.response_persisted === false
        && safeReceipt.secret_persisted === false
        && safeReceipt.status === "NON_PASS",
      "INTEGRATION_NEGATIVE_CONTROL_INVALID",
      `integration-negative ${caseId} safe receipt drifted`,
      safePath,
    );
    scanForbiddenEvidenceFields(result, resultPath);
    scanForbiddenEvidenceFields(safeReceipt, safePath);
    const safePaths = manifestState.manifest.entries
      .filter((entry) =>
        entry.path.startsWith(`${base}/failures/${caseId}/`))
      .map((entry) => entry.path);
    assert(
      isDeepStrictEqual(safePaths, [safePath]),
      "INTEGRATION_NEGATIVE_CONTROL_INVALID",
      `integration-negative ${caseId} failure root is not singleton`,
      `${base}/failures/${caseId}`,
    );
  }
  const receipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "integration-negative receipt",
  );
  exactKeys(
    receipt,
    [
      "attempt_roots_remaining",
      "case_order",
      "cases",
      "false_accepts",
      "final_responses_persisted",
      "schema_version",
      "status",
      "task_id",
    ],
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    "integration-negative receipt",
    receiptPath,
  );
  assert(
    receipt.schema_version === "p1-165-integration-negative-receipt/v2"
      && receipt.task_id === TASK_ID
      && isDeepStrictEqual(receipt.case_order, caseOrder)
      && receipt.cases === caseOrder.length
      && receipt.final_responses_persisted === 0
      && receipt.attempt_roots_remaining === 0
      && receipt.false_accepts === 0
      && receipt.status === "PASS",
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    "integration-negative aggregate drifted",
    receiptPath,
  );
  const actualPaths = manifestState.manifest.entries
    .filter((entry) => entry.path.startsWith(`${base}/`))
    .map((entry) => entry.path);
  assert(
    isDeepStrictEqual(actualPaths, expectedPaths.sort())
      && actualPaths.every(
        (path) =>
          !path.includes("/attempt")
          && !path.includes("/quarantine")
          && !path.includes("/admission/")
          && !path.includes("admitted-response"),
      ),
    "INTEGRATION_NEGATIVE_CONTROL_INVALID",
    "integration-negative closed inventory retained unsafe attempt artifacts",
    base,
  );
  return {
    status: "PASS",
    high_level_entry: "admitAndPersistResponse",
    cases: caseOrder.length,
    final_responses_persisted: 0,
    attempt_roots_remaining: 0,
    false_accepts: 0,
  };
}

function collectBoundIdentityObjects(value, manifestState, label) {
  const identities = [];
  const visit = (entry) => {
    if (Array.isArray(entry)) {
      entry.forEach(visit);
      return;
    }
    if (entry === null || typeof entry !== "object") return;
    if (
      Object.keys(entry).length === IDENTITY_KEYS.length
      && IDENTITY_KEYS.every((key) => Object.hasOwn(entry, key))
    ) {
      identities.push(validateBoundIdentity(entry, manifestState, label));
    }
    Object.values(entry).forEach(visit);
  };
  visit(value);
  return identities;
}

function validateB2ScanLedger(root, manifestState, cellState) {
  const path = "raw/accepted-adapter-control/b2-scan-ledger.json";
  const ledger = readBoundJson(root, manifestState, path, "B2 scan ledger");
  exactKeys(
    ledger,
    ["schema_version", "task_id", "entries"],
    "B2_SCAN_LEDGER_INVALID",
    "B2 scan ledger",
    path,
  );
  const entries = ledger.entries;
  assert(
    ledger.schema_version === "p1-165-b2-scan-ledger/v2"
      && ledger.task_id === TASK_ID
      && Array.isArray(entries)
      && entries.length === 12,
    "B2_SCAN_LEDGER_INVALID",
    "B2 scan ledger does not contain 12 raw child invocations",
    path,
  );
  const b2CellMap = new Map(
    cellState.cells
      .filter((cell) => cell.profile_id.startsWith("B2_"))
      .map((cell) => [cell.cell_id, cell]),
  );
  const b2Cells = new Set(b2CellMap.keys());
  const observedCells = new Set();
  for (const entry of entries) {
    exactKeys(
      entry,
      [
        "b2_scan_proof_identity",
        "cell_id",
        "operation_id",
        "profile_id",
        "task_id",
      ],
      "B2_SCAN_LEDGER_INVALID",
      "B2 scan ledger entry",
      path,
    );
    const cell = b2CellMap.get(entry.cell_id);
    assert(
      entry !== null
        && typeof entry === "object"
        && entry.operation_id === "repository_analysis.scan"
        && typeof entry.cell_id === "string"
        && cell !== undefined
        && entry.task_id === cell.task_id
        && entry.profile_id === cell.profile_id
        && cell.b2_scan_proof_path !== null,
      "B2_SCAN_LEDGER_INVALID",
      "B2 scan ledger entry is not bound to an exact B2 cell",
      path,
    );
    assert(!observedCells.has(entry.cell_id), "B2_SCAN_LEDGER_INVALID", "B2 scan cell duplicated", path);
    observedCells.add(entry.cell_id);
    validateArtifactDescriptor(
      entry.b2_scan_proof_identity,
      cell.b2_scan_proof_path,
      manifestState,
      "B2 scan ledger proof identity",
      path,
    );
    const proof = cellState.adapter_proofs.get(
      `${cell.task_id}:${cell.profile_id}`,
    );
    assert(
      proof?.b2?.independently_reexecuted === true
        && proof.b2.proof_descriptor.path === cell.b2_scan_proof_path,
      "B2_SCAN_LEDGER_INVALID",
      "B2 scan ledger is not backed by an independently validated raw proof",
      path,
    );
  }
  assert(
    observedCells.size === 12 && observedCells.size === b2Cells.size,
    "B2_SCAN_LEDGER_INVALID",
    "B2 scan ledger cell set is incomplete",
    path,
  );
  return entries.length;
}

function loadAcceptedReferencePatterns() {
  return ACCEPTED_TASK_IDS.map((taskId) => {
    const path = join(
      REPOSITORY_ROOT,
      "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks",
      taskId,
      "reference-solution.patch",
    );
    const stat = lstatSync(path);
    assert(
      stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
      "ACCEPTED_REFERENCE_IDENTITY_INVALID",
      `accepted reference patch is not a single-link regular file: ${taskId}`,
      path,
    );
    const bytes = readFileSync(path);
    return {
      task_id: taskId,
      bytes,
      repository_path: relative(REPOSITORY_ROOT, path).split(sep).join("/"),
      type: "REGULAR_FILE",
      nlink: 1,
      byte_length: bytes.length,
      sha256: sha256(bytes),
      sha_bytes: Buffer.from(sha256(bytes), "ascii"),
    };
  });
}

function validateReferenceAnswerScan(root, manifestState, cellState) {
  const referencePatterns = loadAcceptedReferencePatterns();
  const scanPaths = cellState.cells.flatMap((cell) =>
    ["request.raw", "request-record.json", "context.json"].map(
      (suffix) => `raw/cells/${cell.cell_id}/${suffix}`,
    )).sort();
  assert(
    scanPaths.length === 108 && new Set(scanPaths).size === 108,
    "REFERENCE_SCAN_INVALID",
    "reference scan path set is not exact",
    REFERENCE_SCAN_PLAN_PATH,
  );
  const plan = readBoundJson(
    root,
    manifestState,
    REFERENCE_SCAN_PLAN_PATH,
    "reference scan plan",
  );
  exactKeys(
    plan,
    [
      "schema_version",
      "task_id",
      "scan_paths",
      "reference_artifacts",
      "checks",
    ],
    "REFERENCE_SCAN_INVALID",
    "reference scan plan",
    REFERENCE_SCAN_PLAN_PATH,
  );
  assert(
    plan.schema_version === REFERENCE_SCAN_PLAN_SCHEMA
      && plan.task_id === TASK_ID
      && isDeepStrictEqual(plan.scan_paths, scanPaths)
      && isDeepStrictEqual(
        plan.reference_artifacts,
        referencePatterns.map((pattern) => ({
          task_id: pattern.task_id,
          repository_path: pattern.repository_path,
          type: pattern.type,
          nlink: pattern.nlink,
          byte_length: pattern.byte_length,
          sha256: pattern.sha256,
        })),
      )
      && isDeepStrictEqual(
        plan.checks,
        ["EXACT_REFERENCE_BYTES", "REFERENCE_SHA256_ASCII"],
      ),
    "REFERENCE_SCAN_INVALID",
    "reference scan plan differs from canonical accepted references",
    REFERENCE_SCAN_PLAN_PATH,
  );
  const eventArtifact = readBoundBytes(
    root,
    manifestState,
    REFERENCE_SCAN_EVENTS_PATH,
    "reference scan raw events",
  );
  const events = parseJsonLines(
    eventArtifact.bytes,
    "reference scan raw events",
    REFERENCE_SCAN_EVENTS_PATH,
  );
  assert(
    events.length === scanPaths.length,
    "REFERENCE_SCAN_INVALID",
    "reference scan event count differs from exact request/context set",
    REFERENCE_SCAN_EVENTS_PATH,
  );
  for (const [index, event] of events.entries()) {
    exactKeys(
      event,
      ["schema_version", "task_id", "sequence", "input_identity", "checks", "status"],
      "REFERENCE_SCAN_INVALID",
      `reference scan event ${index + 1}`,
      REFERENCE_SCAN_EVENTS_PATH,
    );
    const scanPath = scanPaths[index];
    const expectedIdentity = manifestState.byPath.get(scanPath);
    assert(
      event.schema_version === REFERENCE_SCAN_EVENT_SCHEMA
        && event.task_id === TASK_ID
        && event.sequence === index + 1
        && event.status === "PASS"
        && isDeepStrictEqual(event.input_identity, expectedIdentity)
        && Array.isArray(event.checks)
        && event.checks.length === referencePatterns.length,
      "REFERENCE_SCAN_INVALID",
      `reference scan event ${index + 1} fixed fields drifted`,
      REFERENCE_SCAN_EVENTS_PATH,
    );
    for (const [patternIndex, check] of event.checks.entries()) {
      exactKeys(
        check,
        [
          "task_id",
          "reference_sha256",
          "exact_reference_bytes_found",
          "reference_sha256_ascii_found",
        ],
        "REFERENCE_SCAN_INVALID",
        `reference scan event ${index + 1} check ${patternIndex + 1}`,
        REFERENCE_SCAN_EVENTS_PATH,
      );
      const pattern = referencePatterns[patternIndex];
      assert(
        check.task_id === pattern.task_id
          && check.reference_sha256 === pattern.sha256
          && check.exact_reference_bytes_found === false
          && check.reference_sha256_ascii_found === false,
        "REFERENCE_ANSWER_LEAK_DETECTED",
        `reference scan event ${index + 1} reported a leak or identity drift`,
        REFERENCE_SCAN_EVENTS_PATH,
      );
    }
  }
  const receipt = readBoundJson(
    root,
    manifestState,
    REFERENCE_SCAN_RECEIPT_PATH,
    "reference scan receipt",
  );
  exactKeys(
    receipt,
    [
      "schema_version",
      "task_id",
      "plan_identity",
      "events_identity",
      "files_scanned",
      "reference_artifacts",
      "reference_patterns",
      "leaks",
      "status",
    ],
    "REFERENCE_SCAN_INVALID",
    "reference scan receipt",
    REFERENCE_SCAN_RECEIPT_PATH,
  );
  validateArtifactDescriptor(
    receipt.plan_identity,
    REFERENCE_SCAN_PLAN_PATH,
    manifestState,
    "reference scan plan receipt identity",
    REFERENCE_SCAN_RECEIPT_PATH,
  );
  validateArtifactDescriptor(
    receipt.events_identity,
    REFERENCE_SCAN_EVENTS_PATH,
    manifestState,
    "reference scan events receipt identity",
    REFERENCE_SCAN_RECEIPT_PATH,
  );
  assert(
    receipt.schema_version === REFERENCE_SCAN_RECEIPT_SCHEMA
      && receipt.task_id === TASK_ID
      && receipt.files_scanned === scanPaths.length
      && receipt.reference_artifacts === referencePatterns.length
      && receipt.reference_patterns === referencePatterns.length * 2
      && receipt.leaks === 0
      && receipt.status === "PASS",
    "REFERENCE_SCAN_INVALID",
    "reference scan receipt aggregate differs from raw event set",
    REFERENCE_SCAN_RECEIPT_PATH,
  );
  const scanned = [];
  const leaks = [];
  for (const path of scanPaths) {
    const artifact = readBoundBytes(
      root,
      manifestState,
      path,
      `independent reference scan ${path}`,
    );
    scanned.push(artifact.identity);
    for (const pattern of referencePatterns) {
      if (
        artifact.bytes.indexOf(pattern.bytes) !== -1
        || artifact.bytes.indexOf(pattern.sha_bytes) !== -1
      ) {
        leaks.push({
          path,
          reference_task_id: pattern.task_id,
        });
      }
    }
  }
  assert(
    scanned.length === 108
      && new Set(scanned.map((entry) => entry.path)).size === 108
      && leaks.length === 0,
    "REFERENCE_ANSWER_LEAK_DETECTED",
    "independent request/context scan detected accepted reference-answer material",
    "raw/cells",
  );
  return {
    status: "PASS",
    raw_only: true,
    files_scanned: scanned.length,
    reference_patterns: referencePatterns.length * 2,
    leaks: leaks.length,
    plan_sha256: manifestState.byPath.get(REFERENCE_SCAN_PLAN_PATH).sha256,
    events_sha256: manifestState.byPath.get(REFERENCE_SCAN_EVENTS_PATH).sha256,
    receipt_sha256: manifestState.byPath.get(REFERENCE_SCAN_RECEIPT_PATH).sha256,
  };
}

function validateCreateOnceControl(
  root,
  manifestState,
  kernelContract,
  raceEvents,
  expectedChildEnvironment,
) {
  const base = "raw/concurrency/create-once-control";
  const planPath = `${base}/plan.json`;
  const receiptPath = `${base}/receipt.json`;
  const winnerPath = `${base}/winner-artifact.bin`;
  const plan = readBoundJson(
    root,
    manifestState,
    planPath,
    "create-once control plan",
  );
  exactKeys(
    plan,
    [
      "create_flags",
      "schema_version",
      "slots",
      "target_initially_absent",
      "task_id",
    ],
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once control plan",
    planPath,
  );
  const expectedSlots = Array.from(
    { length: kernelContract.concurrency_slots },
    (_, index) => index + 1,
  );
  assert(
    plan.schema_version === "p1-165-create-once-control-plan/v1"
      && plan.task_id === TASK_ID
      && isDeepStrictEqual(plan.slots, expectedSlots)
      && plan.target_initially_absent === true
      && isDeepStrictEqual(plan.create_flags, ["O_CREAT", "O_EXCL", "O_WRONLY"]),
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once control plan drifted",
    planPath,
  );
  const receipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "create-once control receipt",
  );
  exactKeys(
    receipt,
    [
      "atomic_rename",
      "child_receipts",
      "create_once_rejections",
      "overwritten",
      "plan_identity",
      "schema_version",
      "slots",
      "status",
      "task_id",
      "winner_artifact_identity",
      "winner_slot",
      "winners",
    ].filter((key) => key !== "atomic_rename"),
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once control receipt",
    receiptPath,
  );
  assert(
    receipt.schema_version === "p1-165-create-once-control-receipt/v1"
      && receipt.task_id === TASK_ID
      && receipt.status === "PASS"
      && receipt.slots === kernelContract.concurrency_slots
      && receipt.winners === 1
      && receipt.create_once_rejections === kernelContract.concurrency_slots - 1
      && receipt.overwritten === false
      && Number.isSafeInteger(receipt.winner_slot)
      && expectedSlots.includes(receipt.winner_slot)
      && Array.isArray(receipt.child_receipts)
      && receipt.child_receipts.length === kernelContract.concurrency_slots,
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once control aggregate accounting drifted",
    receiptPath,
  );
  validateArtifactDescriptor(
    receipt.plan_identity,
    planPath,
    manifestState,
    "create-once control plan descriptor",
    receiptPath,
  );
  validateArtifactDescriptor(
    receipt.winner_artifact_identity,
    winnerPath,
    manifestState,
    "create-once winner descriptor",
    receiptPath,
  );
  const winnerArtifact = readBoundBytes(
    root,
    manifestState,
    winnerPath,
    "create-once winner artifact",
  );
  const winnerValue = parseJsonBytes(
    winnerArtifact.bytes,
    "create-once winner artifact",
    winnerPath,
  );
  exactKeys(
    winnerValue,
    ["schema_version", "slot", "task_id"],
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once winner artifact",
    winnerPath,
  );
  assert(
    winnerValue.schema_version === "p1-165-create-once-winner/v1"
      && winnerValue.task_id === TASK_ID
      && winnerValue.slot === receipt.winner_slot,
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once winner artifact content drifted",
    winnerPath,
  );
  const childPids = new Set();
  const parentPids = new Set();
  const starts = [];
  const stops = [];
  const targetPaths = new Set();
  const childBySlot = new Map();
  let winners = 0;
  let rejections = 0;
  const expectedPaths = [planPath, receiptPath, winnerPath];
  for (const slot of expectedSlots) {
    const childBase = `${base}/children/slot-${slot}`;
    const childReceiptPath = `${childBase}/receipt.json`;
    const stdoutPath = `${childBase}/stdout.log`;
    const stderrPath = `${childBase}/stderr.log`;
    expectedPaths.push(childReceiptPath, stdoutPath, stderrPath);
    validateArtifactDescriptor(
      receipt.child_receipts[slot - 1],
      childReceiptPath,
      manifestState,
      `create-once child ${slot} receipt descriptor`,
      receiptPath,
    );
    const child = readBoundJson(
      root,
      manifestState,
      childReceiptPath,
      `create-once child ${slot} receipt`,
    );
    exactKeys(
      child,
      CONTROL_CHILD_RECEIPT_KEYS,
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once child ${slot} receipt`,
      childReceiptPath,
    );
    validateClosedChildEnvironment(
      child.environment,
      expectedChildEnvironment,
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once child ${slot} environment`,
      childReceiptPath,
    );
    exactKeys(
      child.result,
      CREATE_ONCE_CHILD_RESULT_KEYS,
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once child ${slot} result`,
      childReceiptPath,
    );
    assert(
      child.schema_version === "p1-165-control-child-receipt/v1"
        && child.task_id === TASK_ID
        && child.slot === slot
        && child.timed_out === false
        && Number.isSafeInteger(child.parent_pid)
        && child.parent_pid > 0
        && Number.isSafeInteger(child.pid)
        && child.pid > 0
        && child.pid !== child.parent_pid
        && child.signal === null
        && child.result.schema_version
          === "p1-165-create-once-child-result/v1"
        && child.result.task_id === TASK_ID
        && child.result.slot === slot,
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once child ${slot} process/result identity drifted`,
      childReceiptPath,
    );
    assert(
      Array.isArray(child.argv)
        && child.argv.length === 5
        && child.argv[0] === process.execPath
        && child.argv[1] === PREFLIGHT_PATH
        && child.argv[2] === "--create-once-child"
        && isAbsolute(child.argv[3])
        && resolve(child.argv[3]) === child.argv[3]
        && child.argv[4] === String(slot),
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once child ${slot} argv drifted`,
      childReceiptPath,
    );
    targetPaths.add(child.argv[3]);
    validateArtifactDescriptor(
      child.stdout,
      stdoutPath,
      manifestState,
      `create-once child ${slot} stdout`,
      childReceiptPath,
    );
    validateArtifactDescriptor(
      child.stderr,
      stderrPath,
      manifestState,
      `create-once child ${slot} stderr`,
      childReceiptPath,
    );
    const stdout = readBoundBytes(
      root,
      manifestState,
      stdoutPath,
      `create-once child ${slot} stdout`,
    ).bytes;
    const stderr = readBoundBytes(
      root,
      manifestState,
      stderrPath,
      `create-once child ${slot} stderr`,
    ).bytes;
    const stdoutLines = stdout.toString("utf8").split("\n").filter(Boolean);
    assert(
      stdoutLines.length === 1
        && isDeepStrictEqual(
          parseJsonBytes(
            Buffer.from(stdoutLines[0], "utf8"),
            `create-once child ${slot} stdout result`,
            stdoutPath,
          ),
          child.result,
        )
        && stderr.length === 0,
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once child ${slot} raw streams drifted`,
      childReceiptPath,
    );
    const started = Date.parse(child.started_at);
    const stopped = Date.parse(child.stopped_at);
    assert(
      Number.isFinite(started) && Number.isFinite(stopped) && started <= stopped,
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once child ${slot} timestamps invalid`,
      childReceiptPath,
    );
    starts.push(started);
    stops.push(stopped);
    childPids.add(child.pid);
    parentPids.add(child.parent_pid);
    childBySlot.set(slot, child);
    if (
      child.exit_status === 0
      && child.result.status === "WINNER"
      && child.result.reason_code === "PASS"
    ) {
      winners += 1;
      assert(
        slot === receipt.winner_slot
          && isDeepStrictEqual(
            child.result.artifact_identity,
            bytesIdentityFromBound(winnerArtifact.identity),
          ),
        "CREATE_ONCE_CONTROL_INVALID",
        "create-once winning child does not bind winner bytes",
        childReceiptPath,
      );
    } else {
      assert(
        child.exit_status === 1
          && child.result.status === "NON_PASS"
          && child.result.reason_code === "CREATE_ONCE_FAILED"
          && child.result.artifact_identity === null,
        "CREATE_ONCE_CONTROL_INVALID",
        `create-once child ${slot} is neither exact winner nor rejection`,
        childReceiptPath,
      );
      rejections += 1;
    }
  }
  assert(
    targetPaths.size === 1,
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once children did not race on one exact target",
    receiptPath,
  );
  const [raceTarget] = targetPaths;
  const temporaryRoot = dirname(raceTarget);
  const temporaryParent = realpathSync(tmpdir());
  const relativeTemporaryRoot = relative(temporaryParent, temporaryRoot);
  assert(
    basename(raceTarget) === "winner.bin"
      && relativeTemporaryRoot.length > 0
      && !relativeTemporaryRoot.includes(sep)
      && relativeTemporaryRoot
        .startsWith("sourcelens-p1-149-p1-165-create-once-race-")
      && optionalLstat(temporaryRoot) === null
      && optionalLstat(raceTarget) === null,
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once owned race fixture was not exactly cleaned",
    raceTarget,
  );
  assert(
    Array.isArray(raceEvents)
      && raceEvents.length === kernelContract.concurrency_slots,
    "CREATE_ONCE_CONTROL_INVALID",
    "create-once race event set is not exactly four actual children",
    "raw/concurrency/events.jsonl",
  );
  for (const [index, event] of raceEvents.entries()) {
    const slot = index + 1;
    const child = childBySlot.get(slot);
    assert(
      event.schema_version === "p1-165-create-once-race-event/v1"
        && event.task_id === TASK_ID
        && event.sequence === slot
        && event.order_basis === "SLOT_ASCENDING"
        && event.slot === slot
        && isDeepStrictEqual(event.argv, child.argv)
        && event.parent_pid === child.parent_pid
        && event.child_pid === child.pid
        && event.started_at === child.started_at
        && event.stopped_at === child.stopped_at
        && event.exit_status === child.exit_status
        && event.signal === child.signal
        && event.timed_out === child.timed_out
        && event.result_status === child.result.status
        && event.reason_code === child.result.reason_code
        && isDeepStrictEqual(
          event.artifact_identity,
          child.result.artifact_identity,
        )
        && isDeepStrictEqual(event.stdout_identity, child.stdout)
        && isDeepStrictEqual(event.stderr_identity, child.stderr)
        && isDeepStrictEqual(
          event.child_receipt_identity,
          receipt.child_receipts[slot - 1],
        ),
      "CREATE_ONCE_CONTROL_INVALID",
      `create-once race event ${slot} is not bound to its actual child`,
      "raw/concurrency/events.jsonl",
    );
  }
  const actualPaths = manifestState.manifest.entries
    .filter((entry) => entry.path.startsWith(`${base}/`))
    .map((entry) => entry.path);
  assert(
    isDeepStrictEqual(actualPaths, expectedPaths.sort())
      && childPids.size === kernelContract.concurrency_slots
      && parentPids.size === 1
      && winners === 1
      && rejections === kernelContract.concurrency_slots - 1
      && childBySlot.size === kernelContract.concurrency_slots
      && Math.max(...starts) <= Math.min(...stops),
    "CREATE_ONCE_CONTROL_INVALID",
    "real create-once concurrency/inventory accounting is incomplete",
    receiptPath,
  );
  return {
    status: "PASS",
    children: childPids.size,
    winners,
    create_once_rejections: rejections,
    duplicate_slots: 0,
    missing_slots: 0,
  };
}

function validateLivenessControl(
  root,
  manifestState,
  events,
  expectedChildEnvironment,
) {
  const base = "raw/liveness/control";
  const receiptPath = `${base}/receipt.json`;
  const cases = [
    {
      case_id: "LIVENESS_NORMAL_PROGRESS",
      actor: "WORKER",
      timeout_ms: 2_000,
      heartbeat_count: 2,
      reason_code: "PASS",
      exit_status: 0,
      signal: null,
      timed_out: false,
    },
    {
      case_id: "LIVENESS_PROGRESS_RECEIPT_MISSING",
      actor: "WORKER",
      timeout_ms: 2_000,
      heartbeat_count: 1,
      reason_code: "PROGRESS_RECEIPT_MISSING",
      exit_status: 0,
      signal: null,
      timed_out: false,
    },
    {
      case_id: "LIVENESS_WORKER_STALL",
      actor: "WORKER",
      timeout_ms: 150,
      heartbeat_count: 1,
      reason_code: "WORKER_STALL_DETECTED",
      exit_status: null,
      signal: "SIGTERM",
      timed_out: true,
    },
    {
      case_id: "LIVENESS_OBSERVER_STALL",
      actor: "OBSERVER",
      timeout_ms: 150,
      heartbeat_count: 1,
      reason_code: "OBSERVER_STALL_DETECTED",
      exit_status: null,
      signal: "SIGTERM",
      timed_out: true,
    },
    {
      case_id: "LIVENESS_EVIDENCE_WRITER_STALL",
      actor: "EVIDENCE_WRITER",
      timeout_ms: 150,
      heartbeat_count: 1,
      reason_code: "EVIDENCE_WRITER_STALL_DETECTED",
      exit_status: null,
      signal: "SIGTERM",
      timed_out: true,
    },
  ];
  assert(
    Array.isArray(events)
      && events.length === cases.length,
    "LIVENESS_CONTROL_INVALID",
    "liveness event set is not exactly five actual child observations",
    "raw/liveness/events.jsonl",
  );
  const receipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "liveness control receipt",
  );
  exactKeys(
    receipt,
    [
      "cases",
      "evidence_writer_stall",
      "missing_receipt",
      "normal_progress",
      "observer_stall",
      "schema_version",
      "status",
      "task_id",
      "worker_stall",
    ],
    "LIVENESS_CONTROL_INVALID",
    "liveness control receipt",
    receiptPath,
  );
  assert(
    receipt.schema_version === "p1-165-liveness-control-receipt/v1"
      && receipt.task_id === TASK_ID
      && Array.isArray(receipt.cases)
      && receipt.cases.length === cases.length
      && receipt.normal_progress === "PASS"
      && receipt.missing_receipt === "DETECTED"
      && receipt.worker_stall === "DETECTED"
      && receipt.observer_stall === "DETECTED"
      && receipt.evidence_writer_stall === "DETECTED"
      && receipt.status === "PASS",
    "LIVENESS_CONTROL_INVALID",
    "liveness control aggregate drifted",
    receiptPath,
  );
  const childPids = new Set();
  const parentPids = new Set();
  const expectedPaths = [receiptPath];
  let heartbeatCount = 0;
  for (const [index, expected] of cases.entries()) {
    const event = events[index];
    const childBase = `${base}/${expected.case_id}`;
    const childReceiptPath = `${childBase}/receipt.json`;
    const stdoutPath = `${childBase}/stdout.log`;
    const stderrPath = `${childBase}/stderr.log`;
    expectedPaths.push(childReceiptPath, stdoutPath, stderrPath);
    exactKeys(
      receipt.cases[index],
      ["case_id", "child_receipt", "heartbeat_count", "reason_code"],
      "LIVENESS_CONTROL_INVALID",
      `liveness aggregate case ${expected.case_id}`,
      receiptPath,
    );
    assert(
      receipt.cases[index].case_id === expected.case_id
        && receipt.cases[index].reason_code === expected.reason_code
        && receipt.cases[index].heartbeat_count === expected.heartbeat_count,
      "LIVENESS_CONTROL_INVALID",
      `liveness aggregate case drifted: ${expected.case_id}`,
      receiptPath,
    );
    validateArtifactDescriptor(
      receipt.cases[index].child_receipt,
      childReceiptPath,
      manifestState,
      `liveness ${expected.case_id} child receipt`,
      receiptPath,
    );
    const child = readBoundJson(
      root,
      manifestState,
      childReceiptPath,
      `liveness ${expected.case_id} child receipt`,
    );
    exactKeys(
      child,
      LIVENESS_CHILD_RECEIPT_KEYS,
      "LIVENESS_CONTROL_INVALID",
      `liveness ${expected.case_id} child receipt`,
      childReceiptPath,
    );
    validateClosedChildEnvironment(
      child.environment,
      expectedChildEnvironment,
      "LIVENESS_CONTROL_INVALID",
      `liveness ${expected.case_id} child environment`,
      childReceiptPath,
    );
    assert(
      child.schema_version === "p1-165-control-child-receipt/v1"
        && child.task_id === TASK_ID
        && child.case_id === expected.case_id
        && child.reason_code === expected.reason_code
        && isDeepStrictEqual(child.argv, [
          process.execPath,
          PREFLIGHT_PATH,
          "--liveness-child",
          expected.case_id,
        ])
        && Number.isSafeInteger(child.parent_pid)
        && child.parent_pid > 0
        && Number.isSafeInteger(child.pid)
        && child.pid > 0
        && child.pid !== child.parent_pid
        && child.exit_status === expected.exit_status
        && child.signal === expected.signal
        && child.timed_out === expected.timed_out
        && Array.isArray(child.heartbeats)
        && child.heartbeats.length === expected.heartbeat_count,
      "LIVENESS_CONTROL_INVALID",
      `liveness child process result drifted: ${expected.case_id}`,
      childReceiptPath,
    );
    const started = Date.parse(child.started_at);
    const stopped = Date.parse(child.stopped_at);
    assert(
      Number.isFinite(started)
        && Number.isFinite(stopped)
        && started <= stopped,
      "LIVENESS_CONTROL_INVALID",
      `liveness child timestamps invalid: ${expected.case_id}`,
      childReceiptPath,
    );
    for (const [heartbeatIndex, heartbeat] of child.heartbeats.entries()) {
      exactKeys(
        heartbeat,
        HEARTBEAT_KEYS,
        "LIVENESS_CONTROL_INVALID",
        `liveness heartbeat ${expected.case_id}/${heartbeatIndex + 1}`,
        childReceiptPath,
      );
      const emitted = Date.parse(heartbeat.emitted_at);
      assert(
        heartbeat.schema_version === "p1-165-heartbeat/v1"
          && heartbeat.task_id === TASK_ID
          && heartbeat.case_id === expected.case_id
          && heartbeat.actor === expected.actor
          && heartbeat.sequence === heartbeatIndex + 1
          && Number.isFinite(emitted)
          && emitted >= started
          && emitted <= stopped,
        "LIVENESS_CONTROL_INVALID",
        `liveness heartbeat drifted: ${expected.case_id}`,
        childReceiptPath,
      );
    }
    validateArtifactDescriptor(
      child.stdout,
      stdoutPath,
      manifestState,
      `liveness ${expected.case_id} stdout`,
      childReceiptPath,
    );
    validateArtifactDescriptor(
      child.stderr,
      stderrPath,
      manifestState,
      `liveness ${expected.case_id} stderr`,
      childReceiptPath,
    );
    const stdout = readBoundBytes(
      root,
      manifestState,
      stdoutPath,
      `liveness ${expected.case_id} stdout`,
    ).bytes;
    const stderr = readBoundBytes(
      root,
      manifestState,
      stderrPath,
      `liveness ${expected.case_id} stderr`,
    ).bytes;
    const parsedHeartbeats = parseJsonLines(
      stdout,
      `liveness ${expected.case_id} stdout`,
      stdoutPath,
    );
    assert(
      isDeepStrictEqual(parsedHeartbeats, child.heartbeats)
        && stderr.length === 0,
      "LIVENESS_CONTROL_INVALID",
      `liveness raw child streams drifted: ${expected.case_id}`,
      childReceiptPath,
    );
    assert(
      event.schema_version === "p1-165-liveness-observation-event/v1"
        && event.task_id === TASK_ID
        && event.sequence === index + 1
        && event.case_id === expected.case_id
        && event.actor === expected.actor
        && event.timeout_ms === expected.timeout_ms
        && isDeepStrictEqual(event.argv, child.argv)
        && event.parent_pid === child.parent_pid
        && event.child_pid === child.pid
        && event.started_at === child.started_at
        && event.stopped_at === child.stopped_at
        && event.exit_status === child.exit_status
        && event.signal === child.signal
        && event.timed_out === child.timed_out
        && event.observed_reason_code === child.reason_code
        && isDeepStrictEqual(event.heartbeats, child.heartbeats)
        && event.heartbeat_count === child.heartbeats.length
        && isDeepStrictEqual(event.stdout_identity, child.stdout)
        && isDeepStrictEqual(event.stderr_identity, child.stderr)
        && isDeepStrictEqual(
          event.child_receipt_identity,
          receipt.cases[index].child_receipt,
        ),
      "LIVENESS_CONTROL_INVALID",
      `liveness event is not bound to actual child Evidence: ${expected.case_id}`,
      "raw/liveness/events.jsonl",
      expected.case_id,
    );
    childPids.add(child.pid);
    parentPids.add(child.parent_pid);
    heartbeatCount += child.heartbeats.length;
  }
  const actualPaths = manifestState.manifest.entries
    .filter((entry) => entry.path.startsWith(`${base}/`))
    .map((entry) => entry.path);
  assert(
    isDeepStrictEqual(actualPaths, expectedPaths.sort())
      && childPids.size === cases.length
      && parentPids.size === 1
      && heartbeatCount === 6,
    "LIVENESS_CONTROL_INVALID",
    "liveness child Evidence inventory/accounting is incomplete",
    receiptPath,
  );
  return {
    status: "PASS",
    children: childPids.size,
    heartbeats: heartbeatCount,
    normal_progress: "PASS",
    missing_receipt: "DETECTED",
    worker_stall: "DETECTED",
    observer_stall: "DETECTED",
    evidence_writer_stall: "DETECTED",
  };
}

function validateLivenessAndConcurrency(
  root,
  manifestState,
  matrixState,
  kernelContract,
  expectedChildEnvironment,
) {
  const matrixLivenessCases = matrixState.cases
    .filter((entry) => entry.category_id === "LIVENESS");
  const matrixConcurrencyCases = matrixState.cases
    .filter((entry) => entry.category_id === "CONCURRENCY");
  assert(
    matrixLivenessCases.length === 5
      && matrixConcurrencyCases.length === 7,
    "EVENT_LEDGER_INVALID",
    "matrix component-case liveness/concurrency set drifted",
    MATRIX_PATH,
  );
  assert(
    Number.isSafeInteger(kernelContract.concurrency_slots)
      && kernelContract.concurrency_slots === 4,
    "CONCURRENCY_LIMIT_INVALID",
    "kernel contract concurrency slot bound is not exact four",
    KERNEL_CONTRACT_PATH,
  );
  const livenessPath = "raw/liveness/events.jsonl";
  const livenessEvents = parseJsonLines(
    readBoundBytes(
      root,
      manifestState,
      livenessPath,
      "actual liveness observation events",
    ).bytes,
    "actual liveness observation events",
    livenessPath,
  );
  for (const event of livenessEvents) {
    exactKeys(
      event,
      LIVENESS_EVENT_KEYS,
      "LIVENESS_CONTROL_INVALID",
      "actual liveness observation event",
      livenessPath,
    );
  }
  const concurrencyPath = "raw/concurrency/events.jsonl";
  const raceEvents = parseJsonLines(
    readBoundBytes(
      root,
      manifestState,
      concurrencyPath,
      "actual create-once race events",
    ).bytes,
    "actual create-once race events",
    concurrencyPath,
  );
  for (const event of raceEvents) {
    exactKeys(
      event,
      CONCURRENCY_EVENT_KEYS,
      "CREATE_ONCE_CONTROL_INVALID",
      "actual create-once race event",
      concurrencyPath,
    );
  }
  const liveness = validateLivenessControl(
    root,
    manifestState,
    livenessEvents,
    expectedChildEnvironment,
  );
  const createOnce = validateCreateOnceControl(
    root,
    manifestState,
    kernelContract,
    raceEvents,
    expectedChildEnvironment,
  );
  return {
    concurrency: {
      ...createOnce,
      slots_expected: kernelContract.concurrency_slots,
      slots_observed: new Set(raceEvents.map((event) => event.slot)).size,
      fixture_cleaned: true,
      matrix_component_cases_replayed: matrixConcurrencyCases.length,
    },
    liveness: {
      ...liveness,
      matrix_component_cases_replayed: matrixLivenessCases.length,
    },
  };
}

function validateRawCommandEnvironment(value, path) {
  exactKeys(
    value,
    ["HOME", "LANG", "LC_ALL", "PATH", "TZ"],
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input raw command environment",
    path,
  );
  assert(
    value.HOME === "/Users/lijunpeng"
      && value.LANG === "C"
      && value.LC_ALL === "C"
      && value.PATH
        === "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      && value.TZ === "UTC",
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input raw command environment drifted",
    path,
  );
  return value;
}

function runReadOnlyCommand(argv, environment, cwd = REPOSITORY_ROOT) {
  const result = spawnSync(argv[0], argv.slice(1), {
    cwd,
    encoding: null,
    env: environment,
    maxBuffer: 8 * 1024 * 1024,
    timeout: 60_000,
  });
  return {
    exit_status: result.status,
    signal: result.signal,
    stdout: Buffer.isBuffer(result.stdout)
      ? result.stdout
      : Buffer.from(result.stdout ?? ""),
    stderr: Buffer.isBuffer(result.stderr)
      ? result.stderr
      : Buffer.from(result.stderr ?? ""),
  };
}

function validateRawCommandReceipt({
  root,
  manifestState,
  prefix,
  expectedArgv,
  expectedExitStatus = 0,
  independentlyRerun = false,
}) {
  const receiptPath = `${prefix}/receipt.json`;
  const stdoutPath = `${prefix}/stdout.log`;
  const stderrPath = `${prefix}/stderr.log`;
  const receipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "accepted-input raw command receipt",
  );
  exactKeys(
    receipt,
    RAW_COMMAND_RECEIPT_KEYS,
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input raw command receipt",
    receiptPath,
  );
  const environment = validateRawCommandEnvironment(
    receipt.environment,
    receiptPath,
  );
  assert(
    receipt.schema_version === "p1-165-raw-command-receipt/v2"
      && receipt.task_id === TASK_ID
      && isDeepStrictEqual(receipt.argv, expectedArgv)
      && receipt.cwd === REPOSITORY_ROOT
      && Number.isSafeInteger(receipt.parent_pid)
      && receipt.parent_pid > 0
      && Number.isSafeInteger(receipt.pid)
      && receipt.pid > 0
      && receipt.pid !== receipt.parent_pid
      && receipt.exit_status === expectedExitStatus
      && receipt.signal === null,
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input raw command process identity drifted",
    receiptPath,
  );
  const started = Date.parse(receipt.started_at);
  const stopped = Date.parse(receipt.stopped_at);
  assert(
    Number.isFinite(started) && Number.isFinite(stopped) && started <= stopped,
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input raw command timestamps are invalid",
    receiptPath,
  );
  const stdoutDescriptor = validateArtifactDescriptor(
    receipt.stdout,
    stdoutPath,
    manifestState,
    "accepted-input raw command stdout",
    receiptPath,
  );
  const stderrDescriptor = validateArtifactDescriptor(
    receipt.stderr,
    stderrPath,
    manifestState,
    "accepted-input raw command stderr",
    receiptPath,
  );
  const stdout = readBoundBytes(
    root,
    manifestState,
    stdoutDescriptor.path,
    "accepted-input raw command stdout",
  ).bytes;
  const stderr = readBoundBytes(
    root,
    manifestState,
    stderrDescriptor.path,
    "accepted-input raw command stderr",
  ).bytes;
  if (independentlyRerun) {
    const rerun = runReadOnlyCommand(
      expectedArgv,
      environment,
      receipt.cwd,
    );
    assert(
      rerun.exit_status === expectedExitStatus
        && rerun.signal === null
        && rerun.stdout.equals(stdout)
        && rerun.stderr.equals(stderr),
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      "accepted-input read-only command no longer reproduces raw output",
      receiptPath,
    );
  }
  return {
    receipt,
    receipt_identity: bytesIdentityFromBound(
      manifestState.byPath.get(receiptPath),
    ),
    stdout,
    stderr,
  };
}

function currentSourceManifest(sourceRoots) {
  const entries = [];
  const visit = (absolute, relativePath) => {
    const stat = lstatSync(absolute);
    assert(
      !stat.isSymbolicLink(),
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted source root contains symlink: ${relativePath}`,
      relativePath,
    );
    if (stat.isDirectory()) {
      for (const name of readdirSync(absolute).sort()) {
        visit(join(absolute, name), `${relativePath}/${name}`);
      }
      return;
    }
    assert(
      stat.isFile() && stat.nlink === 1,
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted source artifact is not one regular file: ${relativePath}`,
      relativePath,
    );
    const bytes = readFileSync(absolute);
    entries.push({
      path: relativePath,
      type: "REGULAR_FILE",
      nlink: 1,
      byte_length: bytes.length,
      sha256: sha256(bytes),
    });
  };
  for (const sourceRoot of sourceRoots) {
    safeRelativePath(sourceRoot, "accepted source root");
    visit(join(REPOSITORY_ROOT, ...sourceRoot.split("/")), sourceRoot);
  }
  entries.sort((left, right) => left.path.localeCompare(right.path));
  assert(
    new Set(entries.map((entry) => entry.path)).size === entries.length,
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted source roots overlap or duplicate paths",
  );
  return entries;
}

function validateAcceptedInputProvenance(root, manifestState) {
  const truthRelativePath = "docs/aios/truth/project_state.yaml";
  const truthPath = join(REPOSITORY_ROOT, ...truthRelativePath.split("/"));
  const rubyProgram = [
    "require 'yaml'",
    "require 'json'",
    "path=ARGV[0];raise 'missing path' if path.nil?",
    "y=YAML.load(File.read(path))",
    "a=y['current_phase_route'];raise 'missing route' unless a.is_a?(Hash)",
    "a=a['accepted_inputs'];raise 'missing accepted inputs' unless a.is_a?(Hash)",
    "keys=%w[p1_035 p1_101 p1_129 p1_149]",
    "puts JSON.generate(keys.to_h{|k| raise \"missing #{k}\" unless a.key?(k);[k,a[k]]})",
  ].join(";");
  const truthArgv = ["/usr/bin/ruby", "-e", rubyProgram, truthPath];
  const truthCommand = validateRawCommandReceipt({
    root,
    manifestState,
    prefix: "raw/accepted-inputs/truth-command",
    expectedArgv: truthArgv,
    independentlyRerun: true,
  });
  const truthExtractPath = "raw/accepted-inputs/truth-extract.json";
  const truthExtract = readBoundJson(
    root,
    manifestState,
    truthExtractPath,
    "accepted-input Truth extract",
  );
  exactKeys(
    truthExtract,
    ["accepted_inputs", "schema_version", "task_id", "truth"],
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input Truth extract",
    truthExtractPath,
  );
  exactKeys(
    truthExtract.accepted_inputs,
    ACCEPTED_INPUT_ORDER,
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input Truth records",
    truthExtractPath,
  );
  const truthBytes = readFileSync(truthPath);
  assert(
    truthExtract.schema_version === "p1-165-accepted-input-truth-extract/v1"
      && truthExtract.task_id === TASK_ID
      && isDeepStrictEqual(truthExtract.truth, {
        path: truthRelativePath,
        byte_length: truthBytes.length,
        sha256: sha256(truthBytes),
      }),
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input Truth source identity drifted",
    truthExtractPath,
  );
  const rawAcceptedInputs = parseJsonBytes(
    truthCommand.stdout,
    "accepted-input raw Truth command output",
    "raw/accepted-inputs/truth-command/stdout.log",
  );
  assert(
    isDeepStrictEqual(rawAcceptedInputs, truthExtract.accepted_inputs),
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input Truth extract differs from raw command output",
    truthExtractPath,
  );

  const receiptPath = "raw/accepted-inputs/receipt.json";
  const receipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "accepted-input provenance receipt",
  );
  exactKeys(
    receipt,
    [
      "accepted_input_order",
      "inputs",
      "schema_version",
      "status",
      "task_id",
      "truth_command_receipt",
      "truth_extract",
    ],
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input provenance receipt",
    receiptPath,
  );
  assert(
    receipt.schema_version === "p1-165-accepted-input-provenance/v1"
      && receipt.task_id === TASK_ID
      && receipt.status === "PASS"
      && isDeepStrictEqual(receipt.accepted_input_order, ACCEPTED_INPUT_ORDER)
      && Array.isArray(receipt.inputs)
      && receipt.inputs.length === ACCEPTED_INPUT_ORDER.length,
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted-input provenance receipt header drifted",
    receiptPath,
  );
  validateArtifactDescriptor(
    receipt.truth_extract,
    truthExtractPath,
    manifestState,
    "accepted-input Truth extract descriptor",
    receiptPath,
  );
  validateArtifactDescriptor(
    receipt.truth_command_receipt,
    "raw/accepted-inputs/truth-command/receipt.json",
    manifestState,
    "accepted-input Truth command receipt descriptor",
    receiptPath,
  );
  const inputIds = [];
  let sourceFiles = 0;
  for (const [index, inputId] of ACCEPTED_INPUT_ORDER.entries()) {
    const entry = receipt.inputs[index];
    const config = ACCEPTED_INPUT_CONFIG[inputId];
    exactKeys(
      entry,
      ACCEPTED_INPUT_ENTRY_KEYS,
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted input ${inputId}`,
      receiptPath,
    );
    exactKeys(
      entry.truth_record,
      ACCEPTED_TRUTH_RECORD_KEYS,
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted input ${inputId} Truth record`,
      receiptPath,
    );
    assert(
      entry.accepted_input_id === inputId
        && isDeepStrictEqual(entry.truth_record, config.truth_record)
        && isDeepStrictEqual(
          truthExtract.accepted_inputs[inputId],
          config.truth_record,
        ),
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted input ${inputId} exact Truth identity drifted`,
      receiptPath,
    );
    const contractBytes = readFileSync(
      join(
        REPOSITORY_ROOT,
        ...config.truth_record.task_contract_path.split("/"),
      ),
    );
    assert(
      isDeepStrictEqual(entry.contract_identity, {
        path: config.truth_record.task_contract_path,
        byte_length: contractBytes.length,
        sha256: sha256(contractBytes),
      })
        && sha256(contractBytes) === config.truth_record.task_contract_sha256,
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted input ${inputId} Task Contract identity drifted`,
      receiptPath,
    );
    const commandRoot = `raw/accepted-inputs/commands/${inputId}`;
    const commandDefinitions = [
      ["git_cat_file_receipt", "git-cat-file", [
        "/usr/bin/git",
        "cat-file",
        "-e",
        `${config.truth_record.accepted_candidate_commit}^{commit}`,
      ], true],
      ["git_tree_receipt", "git-tree", [
        "/usr/bin/git",
        "show",
        "-s",
        "--format=%T",
        config.truth_record.accepted_candidate_commit,
      ], true],
      ["git_ancestry_receipt", "git-ancestry", [
        "/usr/bin/git",
        "merge-base",
        "--is-ancestor",
        config.truth_record.accepted_candidate_commit,
        "HEAD",
      ], true],
      [
        "accepted_verifier_receipt",
        "accepted-verifier",
        config.verifier,
        inputId === "p1_129",
      ],
    ];
    for (const [field, directory, argv, rerun] of commandDefinitions) {
      const command = validateRawCommandReceipt({
        root,
        manifestState,
        prefix: `${commandRoot}/${directory}`,
        expectedArgv: [...argv],
        independentlyRerun: rerun,
      });
      validateArtifactDescriptor(
        entry[field],
        `${commandRoot}/${directory}/receipt.json`,
        manifestState,
        `accepted input ${inputId} ${field}`,
        receiptPath,
      );
      assert(
        isDeepStrictEqual(
          bytesIdentityFromBound(
            manifestState.byPath.get(`${commandRoot}/${directory}/receipt.json`),
          ),
          command.receipt_identity,
        ),
        "ACCEPTED_INPUT_PROVENANCE_INVALID",
        `accepted input ${inputId} command receipt identity drifted`,
        receiptPath,
      );
      if (directory === "git-tree") {
        assert(
          command.stdout.toString("utf8").trim()
            === config.truth_record.accepted_candidate_tree,
          "ACCEPTED_INPUT_PROVENANCE_INVALID",
          `accepted input ${inputId} Git tree output drifted`,
          `${commandRoot}/${directory}/stdout.log`,
        );
      }
    }
    const sourceManifestPath =
      `raw/accepted-inputs/source-manifests/${inputId}.json`;
    validateArtifactDescriptor(
      entry.source_manifest,
      sourceManifestPath,
      manifestState,
      `accepted input ${inputId} source manifest`,
      receiptPath,
    );
    const sourceManifest = readBoundJson(
      root,
      manifestState,
      sourceManifestPath,
      `accepted input ${inputId} source manifest`,
    );
    exactKeys(
      sourceManifest,
      [
        "accepted_input_id",
        "entries",
        "entry_count",
        "schema_version",
        "source_roots",
        "task_id",
      ],
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted input ${inputId} source manifest`,
      sourceManifestPath,
    );
    assert(
      sourceManifest.schema_version === "p1-165-accepted-source-manifest/v1"
        && sourceManifest.task_id === TASK_ID
        && sourceManifest.accepted_input_id === inputId
        && isDeepStrictEqual(sourceManifest.source_roots, config.source_roots)
        && Number.isSafeInteger(sourceManifest.entry_count)
        && sourceManifest.entry_count > 0
        && Array.isArray(sourceManifest.entries)
        && sourceManifest.entry_count === sourceManifest.entries.length,
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted input ${inputId} source manifest header drifted`,
      sourceManifestPath,
    );
    for (const sourceEntry of sourceManifest.entries) {
      exactKeys(
        sourceEntry,
        IDENTITY_KEYS,
        "ACCEPTED_INPUT_PROVENANCE_INVALID",
        `accepted input ${inputId} source entry`,
        sourceManifestPath,
      );
    }
    assert(
      isDeepStrictEqual(
        sourceManifest.entries,
        currentSourceManifest(config.source_roots),
      ),
      "ACCEPTED_INPUT_PROVENANCE_INVALID",
      `accepted input ${inputId} current source bytes differ from manifest`,
      sourceManifestPath,
    );
    sourceFiles += sourceManifest.entry_count;
    inputIds.push(inputId);
  }
  assert(
    isDeepStrictEqual(inputIds, ACCEPTED_INPUT_ORDER),
    "ACCEPTED_INPUT_PROVENANCE_INVALID",
    "accepted input receipt order drifted",
    receiptPath,
  );
  return {
    status: "PASS",
    accepted_inputs: inputIds.length,
    source_files: sourceFiles,
    git_ancestry_checks: inputIds.length,
    accepted_verifier_receipts: inputIds.length,
    raw_truth_command_reexecuted: true,
  };
}

function optionalLstat(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw error;
  }
}

function expectedAtomicNonPassCases(matrixState) {
  const matrixCases = matrixState.cases
    .filter((entry) => entry.expected_status === "NON_PASS")
    .map((entry) => ({
      case_id: entry.case_id,
      root: `raw/cases/${entry.case_id}`,
      failure_receipt_path:
        `raw/cases/${entry.case_id}/safe-failure-receipt.json`,
    }));
  const integrationCases = INTEGRATION_NEGATIVE_CASES.map((entry) => ({
    case_id: `INTEGRATION_${entry.case_id}`,
    root: `raw/integration-negative-control/failures/${entry.case_id}`,
    failure_receipt_path:
      `raw/integration-negative-control/failures/${entry.case_id}/safe-failure-receipt.json`,
  }));
  return [
    ...matrixCases,
    ...integrationCases,
    {
      case_id: "OUTPUT_TOKENS_2049",
      root: "raw/token-boundary/cases/2049",
      failure_receipt_path:
        "raw/token-boundary/cases/2049/safe-failure-receipt.json",
    },
  ];
}

function countClosedDirectories(root) {
  let count = 0;
  const visit = (absolute, relativePath) => {
    const stat = lstatSync(absolute);
    assert(
      stat.isDirectory() && !stat.isSymbolicLink(),
      "ATOMIC_COMMIT_RECEIPT_INVALID",
      "committed Evidence directory tree contains an unsafe node",
      relativePath === "" ? root : relativePath,
    );
    count += 1;
    const names = readdirSync(absolute).sort();
    assert(
      relativePath === "" || names.length > 0,
      "CLOSED_INVENTORY_DRIFT",
      "committed Evidence contains an empty directory",
      relativePath,
    );
    for (const name of names) {
      const childRelative = relativePath === ""
        ? name
        : `${relativePath}/${name}`;
      const child = join(absolute, name);
      const childStat = lstatSync(child);
      if (childStat.isDirectory() && !childStat.isSymbolicLink()) {
        visit(child, childRelative);
      }
    }
  };
  visit(root, "");
  return count;
}

function readAtomicSiblingReceipt(root) {
  const receiptPath = `${root}.p1-165-atomic-commit-receipt.json`;
  const before = lstatSync(receiptPath);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assert(
    before.isFile()
      && !before.isSymbolicLink()
      && before.nlink === 1
      && (before.mode & 0o777) === 0o600
      && (uid === null || before.uid === uid),
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic sibling receipt is not one owned create-once 0600 regular file",
    receiptPath,
  );
  let descriptor;
  try {
    descriptor = openSync(
      receiptPath,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const opened = fstatSync(descriptor);
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    const finalStat = lstatSync(receiptPath);
    assert(
      opened.isFile()
        && opened.nlink === 1
        && opened.dev === before.dev
        && opened.ino === before.ino
        && after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && finalStat.dev === opened.dev
        && finalStat.ino === opened.ino
        && finalStat.size === opened.size
        && finalStat.nlink === 1
        && (finalStat.mode & 0o777) === 0o600,
      "ATOMIC_COMMIT_RECEIPT_INVALID",
      "atomic sibling receipt changed while read",
      receiptPath,
    );
    return {
      path: receiptPath,
      bytes,
      value: parseJsonBytes(bytes, "atomic sibling receipt", receiptPath),
      stat: finalStat,
    };
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function validateAtomicCommitReceipt(
  root,
  manifestState,
  matrixState,
  priorInterruptedAttempt,
) {
  const sibling = readAtomicSiblingReceipt(root);
  const receipt = sibling.value;
  exactKeys(
    receipt,
    [
      "commit",
      "commit_lock_absent",
      "expected_non_pass_cases",
      "final_root",
      "post_commit_secret_scan",
      "schema_version",
      "stage_path_absent",
      "status",
      "task_id",
    ],
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic sibling receipt",
    sibling.path,
  );
  const expectedNonPass = expectedAtomicNonPassCases(matrixState);
  assert(
    expectedNonPass.length === 100,
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic expected NON_PASS case set is not exactly 100",
    sibling.path,
  );
  assert(
    receipt.schema_version
      === "p1-165-atomic-evidence-commit-receipt/v1"
      && receipt.task_id === TASK_ID
      && receipt.final_root === root
      && isDeepStrictEqual(receipt.expected_non_pass_cases, expectedNonPass)
      && receipt.stage_path_absent === true
      && receipt.commit_lock_absent === true
      && receipt.status === "PASS",
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic sibling receipt fixed fields or 100-case list drifted",
    sibling.path,
  );
  for (const [index, expectedCase] of expectedNonPass.entries()) {
    exactKeys(
      receipt.expected_non_pass_cases[index],
      ["case_id", "failure_receipt_path", "root"],
      "ATOMIC_COMMIT_RECEIPT_INVALID",
      `atomic NON_PASS case ${index}`,
      sibling.path,
    );
    const underRoot = manifestState.manifest.entries
      .filter((entry) =>
        entry.path.startsWith(`${expectedCase.root}/`))
      .map((entry) => entry.path);
    assert(
      isDeepStrictEqual(underRoot, [expectedCase.failure_receipt_path]),
      "ATOMIC_COMMIT_RECEIPT_INVALID",
      `atomic NON_PASS root is not safe-receipt-only: ${expectedCase.case_id}`,
      expectedCase.root,
    );
  }
  const commit = receipt.commit;
  exactKeys(
    commit,
    [
      "atomic_rename",
      "committed_root",
      "directory_count",
      "expected_non_pass_cases",
      "final_root",
      "inventory_entries",
      "inventory_identity",
      "lock_held_during_final_reinspection",
      "parent",
      "pre_rename_reinspection",
      "same_filesystem",
      "schema_version",
      "staged_root",
      "status",
      "task_id",
      "total_bytes",
    ],
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic production commit result",
    sibling.path,
  );
  exactKeys(
    commit.parent,
    ["dev", "ino", "path", "uid"],
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic commit parent identity",
    sibling.path,
  );
  exactKeys(
    commit.committed_root,
    ["dev", "ino", "path", "uid"],
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic committed-root identity",
    sibling.path,
  );
  exactKeys(
    commit.staged_root,
    ["dev", "ino", "path", "uid"],
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic staged-root identity",
    sibling.path,
  );
  const rootStat = lstatSync(root);
  const parentPath = dirname(root);
  const parentStat = lstatSync(parentPath);
  const expectedInventory = [
    manifestState.artifact.identity,
    ...manifestState.manifest.entries,
  ].sort((left, right) => left.path.localeCompare(right.path));
  const expectedInventoryBytes = Buffer.from(
    `${canonicalJson(expectedInventory)}\n`,
    "utf8",
  );
  const totalBytes = expectedInventory.reduce(
    (sum, entry) => sum + entry.byte_length,
    0,
  );
  const directoryCount = countClosedDirectories(root);
  const stagedRootName = basename(commit.staged_root.path);
  const stagedRootPrefix = `.${basename(root)}.p1-165-stage-`;
  const stagedRootSuffix = stagedRootName.startsWith(stagedRootPrefix)
    ? stagedRootName.slice(stagedRootPrefix.length)
    : "";
  validateBytesIdentity(
    commit.inventory_identity,
    {
      byte_length: expectedInventoryBytes.length,
      sha256: sha256(expectedInventoryBytes),
    },
    "atomic committed inventory identity",
    sibling.path,
  );
  assert(
    commit.schema_version === "p1-165-atomic-evidence-commit/v1"
      && commit.task_id === TASK_ID
      && commit.status === "PASS"
      && commit.final_root === root
      && isDeepStrictEqual(commit.parent, {
        path: parentPath,
        dev: parentStat.dev,
        ino: parentStat.ino,
        uid: parentStat.uid,
      })
      && isDeepStrictEqual(commit.committed_root, {
        path: root,
        dev: rootStat.dev,
        ino: rootStat.ino,
        uid: rootStat.uid,
      })
      && isAbsolute(commit.staged_root.path)
      && resolve(commit.staged_root.path) === commit.staged_root.path
      && dirname(commit.staged_root.path) === parentPath
      && /^[0-9a-f]{24}$/.test(stagedRootSuffix)
      && commit.staged_root.path !== root
      && commit.staged_root.dev === rootStat.dev
      && commit.staged_root.ino === rootStat.ino
      && commit.staged_root.uid === rootStat.uid
      && optionalLstat(commit.staged_root.path) === null
      && commit.inventory_entries === expectedInventory.length
      && commit.directory_count === directoryCount
      && commit.total_bytes === totalBytes
      && commit.expected_non_pass_cases === expectedNonPass.length
      && commit.atomic_rename === true
      && commit.lock_held_during_final_reinspection === true
      && commit.pre_rename_reinspection === true
      && commit.same_filesystem === true
      && rootStat.dev === parentStat.dev,
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic production commit result differs from final filesystem state",
    sibling.path,
  );
  const postScan = receipt.post_commit_secret_scan;
  exactKeys(
    postScan,
    [
      "adjacent_buffer_composition_scanned",
      "files_scanned",
      "leaks",
      "representations_scanned_per_sentinel",
      "schema_version",
      "sentinels_scanned",
      "status",
      "task_id",
    ],
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic post-commit Secret scan",
    sibling.path,
  );
  assert(
    postScan.schema_version === "p1-165-post-commit-secret-scan/v1"
      && postScan.task_id === TASK_ID
      && postScan.files_scanned === expectedInventory.length
      && postScan.adjacent_buffer_composition_scanned === true
      && postScan.sentinels_scanned === 2
      && postScan.representations_scanned_per_sentinel === 5
      && postScan.leaks === 0
      && postScan.status === "PASS",
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic post-commit Secret scan aggregate drifted",
    sibling.path,
  );
  const stagePrefix = `.${basename(root)}.p1-165-stage-`;
  const priorStageName = priorInterruptedAttempt === null
    ? null
    : basename(priorInterruptedAttempt.aborted_precommit_stage.root.path);
  const residualStages = readdirSync(parentPath)
    .filter(
      (name) =>
        name.startsWith(stagePrefix)
        || (priorStageName !== null && name === priorStageName),
    )
    .sort();
  const expectedResidualStages = priorInterruptedAttempt === null
    ? []
    : [priorStageName];
  assert(
    optionalLstat(`${root}.p1-165-commit-lock`) === null
      && isDeepStrictEqual(residualStages, expectedResidualStages),
    "ATOMIC_COMMIT_RECEIPT_INVALID",
    "atomic commit left a lock or undeclared staging directory",
    parentPath,
  );
  const sentinels = [
    Buffer.from("P1-165-MATRIX-SECRET-SENTINEL-NEVER-PERSIST", "utf8"),
    Buffer.from("P1-165-SECONDARY-SECRET-SENTINEL-NEVER-PERSIST", "utf8"),
  ];
  for (const sentinel of sentinels) {
    const digest = createHash("sha256").update(sentinel).digest();
    for (const needle of [
      sentinel,
      Buffer.from(sentinel.toString("base64"), "ascii"),
      digest,
      Buffer.from(digest.toString("hex"), "ascii"),
      Buffer.from(digest.toString("hex").toUpperCase(), "ascii"),
    ]) {
      assert(
        sibling.bytes.indexOf(needle) === -1,
        "SECRET_REFLECTION_DETECTED",
        "atomic sibling receipt reflects a Secret sentinel",
        sibling.path,
      );
    }
  }
  return {
    status: "PASS",
    receipt_path: sibling.path,
    receipt_sha256: sha256(sibling.bytes),
    atomic_rename: true,
    inventory_entries: expectedInventory.length,
    directory_count: directoryCount,
    total_bytes: totalBytes,
    expected_non_pass_cases: expectedNonPass.length,
    staged_root_path: commit.staged_root.path,
    staged_root_absent: true,
    stage_path_absent: true,
    commit_lock_absent: true,
  };
}

function validateKernelContract(root, manifestState, matrixState) {
  const contract = readBoundJson(
    root,
    manifestState,
    KERNEL_CONTRACT_PATH,
    "raw kernel contract",
  );
  exactKeys(
    contract,
    KERNEL_CONTRACT_KEYS,
    "KERNEL_CONTRACT_INVALID",
    "raw kernel contract",
    KERNEL_CONTRACT_PATH,
  );
  assert(
    contract.schema_version === KERNEL_CONTRACT_SCHEMA
      && contract.task_id === TASK_ID
      && contract.matrix_sha256 === matrixState.identity.sha256
      && contract.response_bytes_max === RESPONSE_BYTES_MAX
      && contract.output_tokens_max === OUTPUT_TOKENS_MAX
      && isDeepStrictEqual(contract.profile_order, PROFILE_ORDER)
      && isDeepStrictEqual(contract.external_effects, FALSE_EXTERNAL_EFFECTS),
    "KERNEL_CONTRACT_INVALID",
    "raw kernel contract fixed values drifted",
    KERNEL_CONTRACT_PATH,
  );
  return contract;
}

function validateNoSecretTestSentinelReflection(root, manifestState) {
  const receiptPath =
    "raw/secret-closure/whole-stage-scan-receipt.json";
  const persistedReceipt = readBoundJson(
    root,
    manifestState,
    receiptPath,
    "whole-stage Secret scan receipt",
  );
  exactKeys(
    persistedReceipt,
    [
      "adjacent_buffer_composition_scanned",
      "files_scanned",
      "leaks",
      "representations_scanned_per_sentinel",
      "schema_version",
      "sentinels_scanned",
      "status",
      "task_id",
    ],
    "SECRET_SCAN_RECEIPT_INVALID",
    "whole-stage Secret scan receipt",
    receiptPath,
  );
  assert(
    persistedReceipt.schema_version
      === "p1-165-whole-stage-secret-scan/v1"
      && persistedReceipt.task_id === TASK_ID
      && persistedReceipt.files_scanned === manifestState.manifest.entry_count - 1
      && persistedReceipt.adjacent_buffer_composition_scanned === true
      && persistedReceipt.sentinels_scanned === 2
      && persistedReceipt.representations_scanned_per_sentinel === 5
      && persistedReceipt.leaks === 0
      && persistedReceipt.status === "PASS",
    "SECRET_SCAN_RECEIPT_INVALID",
    "whole-stage Secret scan aggregate drifted",
    receiptPath,
  );
  const sentinels = [
    Buffer.from("P1-165-MATRIX-SECRET-SENTINEL-NEVER-PERSIST", "utf8"),
    Buffer.from(
      "P1-165-SYNTHETIC-SECRET-SENTINEL-DO-NOT-PERSIST",
      "utf8",
    ),
    Buffer.from(
      "P1-165-SECONDARY-SECRET-SENTINEL-NEVER-PERSIST",
      "utf8",
    ),
  ];
  const needles = sentinels.flatMap((sentinel) => {
    const digest = createHash("sha256").update(sentinel).digest();
    return [
      sentinel,
      Buffer.from(sentinel.toString("base64"), "ascii"),
      Buffer.from(sentinel.toString("hex"), "ascii"),
      Buffer.from(sentinel.toString("hex").toUpperCase(), "ascii"),
      digest,
      Buffer.from(digest.toString("hex"), "ascii"),
      Buffer.from(digest.toString("hex").toUpperCase(), "ascii"),
    ];
  });
  const artifacts = [
    manifestState.artifact,
    ...manifestState.manifest.entries.map((entry) =>
      readBoundBytes(
        root,
        manifestState,
        entry.path,
        "raw Evidence artifact for Secret reflection scan",
      )),
  ];
  let leaks = 0;
  const scan = (bytes) => {
    for (const needle of needles) {
      if (bytes.indexOf(needle) !== -1) leaks += 1;
    }
  };
  for (const artifact of artifacts) scan(artifact.bytes);
  scan(Buffer.concat(artifacts.map((artifact) => artifact.bytes)));
  for (let index = 1; index < artifacts.length; index += 1) {
    scan(Buffer.concat([
      artifacts[index - 1].bytes,
      artifacts[index].bytes,
    ]));
  }
  assert(
    leaks === 0,
    "SECRET_REFLECTION_DETECTED",
    "final Evidence reflects a test Secret sentinel, encoding, or digest",
    MANIFEST_PATH,
  );
  return {
    status: "PASS",
    files_scanned: artifacts.length,
    adjacent_artifact_pairs_scanned: Math.max(0, artifacts.length - 1),
    whole_stage_composition_scanned: true,
    persisted_files_scanned: persistedReceipt.files_scanned,
    persisted_sentinels_scanned: persistedReceipt.sentinels_scanned,
    independent_sentinels_scanned: sentinels.length,
    encodings_per_sentinel: 7,
    leaks,
  };
}

function baseFailureResult(root, matrixIdentity, error) {
  return {
    schema_version: RESULT_SCHEMA,
    task_id: TASK_ID,
    status: "NON_PASS",
    reason_code: error.code ?? "EVALUATOR_INTERNAL_ERROR",
    raw_only: true,
    worker_summary_trusted: false,
    evidence_root: root,
    matrix: {
      path: matrixIdentity?.path ?? MATRIX_PATH,
      sha256: matrixIdentity?.sha256 ?? null,
      case_count: MATRIX_CASE_COUNT,
    },
    manifest: {
      path: MANIFEST_PATH,
      sha256: null,
      entry_count: 0,
    },
    distinct_adapter_roots: 0,
    distinct_spine_run_ids: 0,
    closed_spine_artifact_sets: 0,
    production_admission_receipts: 0,
    production_cell_closures: 0,
    matrix_case_production_admissions: 0,
    matrix_case_safe_failure_receipts: 0,
    p1_101_rollbacks: 0,
    independent_reexecution_spines: 0,
    independent_case_reexecutions: 0,
    accepted_adapter_process: {
      status: "NON_PASS",
      accepted_authority_bundle_exact: false,
      sandbox_calibration_exact: false,
      network_denial_fixture_only: false,
      live_network_probe_executed: false,
      live_network_connections_created: 0,
      live_network_calibration: "UNKNOWN",
      home_read_denial: false,
      home_write_denial: false,
      external_write_denial: false,
      owned_write_allowance: false,
      calibration_roots_absent: false,
      accepted_p1_129_source_preserved_read_only: false,
      b2_independent_scan_reexecutions: 0,
      distinct_b2_child_pids: 0,
      all_current_b2_fixture_roots_absent: false,
      historical_reviewed_binary_exact_bytes_claim: false,
      cooperative_local_accepted_evidence_path_residual: true,
      hostile_global_read_isolation_claim: false,
      hostile_process_isolation_claim: false,
      trusted_accepted_source_required: true,
    },
    counts: {
      cases_observed: 0,
      cases_passed: 0,
      false_accepts: 0,
      unsafe_persistence: 0,
      synthetic_cells: 0,
      b0_cells: 0,
      b1_cells: 0,
      b2_cells: 0,
      p1_149_spines: 0,
      p1_101_replays: 0,
      b2_scan_children: 0,
      ordinary_failed_denominator_cases: 0,
      integration_negative_cases: 0,
      exact_output_token_boundary_spines: 0,
      safe_failure_receipts_total: 0,
      provider_requests: 0,
      secret_reads: 0,
      network_effects: 0,
    },
    usage: {
      unknown_preserved: false,
      boundaries: { "2047": "MISSING", "2048": "MISSING", "2049": "MISSING" },
      semantics: OUTPUT_TOKEN_SEMANTICS,
      exact_boundary_spines: 0,
      matrix_component_boundaries: {
        "2047": "MISSING",
        "2048": "MISSING",
        "2049": "MISSING",
      },
    },
    ordinary_failure_control: {
      status: "NON_PASS",
      failed_denominator_cases: 0,
      early_failures: 0,
      late_failures: 0,
      continued_to_accepted_cell: false,
      worker_success_fields_trusted: false,
    },
    output_token_control: {
      status: "NON_PASS",
      semantics: OUTPUT_TOKEN_SEMANTICS,
      boundaries: {
        "2047": "MISSING",
        "2048": "MISSING",
        "2049": "MISSING",
      },
      exact_boundary_spines: 0,
      overflow_high_level_replay: {
        status: "NON_PASS",
        reason_code: "UNKNOWN",
        admitted_response_persisted: false,
        admission_receipt_persisted: false,
        attempt_root_cleaned: false,
        quarantine_root_cleaned: false,
      },
    },
    integration_negative_control: {
      status: "NON_PASS",
      high_level_entry: "admitAndPersistResponse",
      cases: 0,
      final_responses_persisted: 0,
      attempt_roots_remaining: 0,
      false_accepts: 0,
    },
    atomic_commit: {
      status: "NON_PASS",
      receipt_path: null,
      receipt_sha256: null,
      atomic_rename: false,
      inventory_entries: 0,
      directory_count: 0,
      total_bytes: 0,
      expected_non_pass_cases: 0,
      staged_root_path: null,
      staged_root_absent: false,
      stage_path_absent: false,
      commit_lock_absent: false,
    },
    concurrency: {
      status: "NON_PASS",
      children: 0,
      winners: 0,
      create_once_rejections: 0,
      slots_expected: 0,
      slots_observed: 0,
      duplicate_slots: 0,
      missing_slots: 0,
      fixture_cleaned: false,
      matrix_component_cases_replayed: 0,
    },
    liveness: {
      status: "NON_PASS",
      children: 0,
      heartbeats: 0,
      normal_progress: "UNKNOWN",
      missing_receipt: "UNKNOWN",
      matrix_component_cases_replayed: 0,
      worker_stall: "UNKNOWN",
      observer_stall: "UNKNOWN",
      evidence_writer_stall: "UNKNOWN",
    },
    external_effects: { ...FALSE_EXTERNAL_EFFECTS },
    reference_scan: {
      status: "NON_PASS",
      raw_only: true,
      files_scanned: 0,
      reference_patterns: 0,
      leaks: 0,
    },
    secret_scan: {
      status: "NON_PASS",
      files_scanned: 0,
      adjacent_artifact_pairs_scanned: 0,
      whole_stage_composition_scanned: false,
      persisted_files_scanned: 0,
      persisted_sentinels_scanned: 0,
      independent_sentinels_scanned: 0,
      encodings_per_sentinel: 7,
      leaks: 0,
    },
    accepted_input_provenance: {
      status: "NON_PASS",
      accepted_inputs: 0,
      source_files: 0,
      git_ancestry_checks: 0,
      accepted_verifier_receipts: 0,
      raw_truth_command_reexecuted: false,
    },
    failures: [
      {
        code: error.code ?? "EVALUATOR_INTERNAL_ERROR",
        ...(error.path === null || error.path === undefined ? {} : { path: error.path }),
        ...(error.caseId === null || error.caseId === undefined
          ? {}
          : { case_id: error.caseId }),
        message: String(error.message ?? error),
      },
    ],
  };
}

export function selfTestP1168PriorAttempt() {
  const disclosure = expectedP1168PriorInterruptedAttempt(
    "/private/tmp/p1-168-prior-attempt-read-only-self-test",
  );
  assert(
    disclosure.schema_version
      === "p1-168-prior-attempt-disclosure/v2"
      && disclosure.status === "TERMINAL_NON_PASS"
      && disclosure.root_preserved === true
      && disclosure.source_hash_stale === true
      && disclosure.accepted_evidence === false
      && disclosure.reused_as_accepted === false
      && Object.keys(disclosure.artifacts).length === 8
      && disclosure.complete_evidence_root?.status === "PASS"
      && disclosure.complete_evidence_root?.manifest
        ?.declared_entry_count === 3829
      && disclosure.complete_evidence_root?.manifest?.entries_exact === true
      && disclosure.complete_evidence_root?.inventory?.entry_count === 3830
      && disclosure.complete_evidence_root?.inventory?.total_bytes
        === 167164014
      && disclosure.complete_evidence_root?.inventory?.sha256
        === "d083c053e8de09efbfed2d2109c7c861ad0d7fc00e7c8b0dd92c808e32d91a64"
      && disclosure.aborted_precommit_stage?.inventory?.entry_count === 744
      && disclosure.aborted_precommit_stage?.inventory?.total_bytes
        === 161608624
      && disclosure.aborted_precommit_stage?.inventory?.sha256
        === "18e90cfb2d16c6fe78f152cb96321c44c2706df3591a9dbb997d2ef8f142659b",
    "EVALUATOR_SELF_TEST_NON_PASS",
    "P1-168 prior attempt disclosure self-test failed",
  );
  return {
    schema_version: "p1-168-prior-attempt-read-only-self-test/v1",
    status: "PASS",
    artifacts_verified: Object.keys(disclosure.artifacts).length,
    complete_root_inventory:
      disclosure.complete_evidence_root.inventory,
    stage_inventory: disclosure.aborted_precommit_stage.inventory,
  };
}

export function selfTestSchema() {
  const matrixState = loadAndValidateMatrix();
  let duplicateRejected = false;
  try {
    parseJsonBytes(
      Buffer.from('{"schema_version":"test","schema_version":"duplicate"}'),
      "duplicate-key self-test",
    );
  } catch (error) {
    duplicateRejected =
      error instanceof EvaluationFailure
      && error.code === "DUPLICATE_JSON_KEY";
  }
  assert(
    duplicateRejected,
    "EVALUATOR_SELF_TEST_NON_PASS",
    "strict JSON duplicate-key control did not fail closed",
  );
  const failureShape = baseFailureResult(
    "/absolute/self-test-root",
    matrixState.identity,
    new EvaluationFailure("SELF_TEST_NON_PASS", "synthetic failure"),
  );
  assert(
    failureShape.schema_version === RESULT_SCHEMA
      && failureShape.status === "NON_PASS"
      && failureShape.raw_only === true
      && failureShape.worker_summary_trusted === false
      && failureShape.matrix.sha256 === MATRIX_SHA256
      && failureShape.matrix.case_count === MATRIX_CASE_COUNT
      && failureShape.atomic_commit.staged_root_path === null
      && failureShape.atomic_commit.staged_root_absent === false
      && failureShape.concurrency.fixture_cleaned === false
      && failureShape.concurrency.matrix_component_cases_replayed === 0
      && failureShape.liveness.children === 0
      && failureShape.liveness.heartbeats === 0
      && failureShape.liveness.matrix_component_cases_replayed === 0
      && failureShape.accepted_adapter_process.status === "NON_PASS"
      && failureShape.accepted_adapter_process
        .accepted_authority_bundle_exact === false
      && failureShape.accepted_adapter_process
        .sandbox_calibration_exact === false
      && failureShape.accepted_adapter_process
        .network_denial_fixture_only === false
      && failureShape.accepted_adapter_process
        .live_network_probe_executed === false
      && failureShape.accepted_adapter_process
        .live_network_connections_created === 0
      && failureShape.accepted_adapter_process
        .live_network_calibration === "UNKNOWN"
      && failureShape.accepted_adapter_process
        .home_read_denial === false
      && failureShape.accepted_adapter_process
        .home_write_denial === false
      && failureShape.accepted_adapter_process
        .external_write_denial === false
      && failureShape.accepted_adapter_process
        .owned_write_allowance === false
      && failureShape.accepted_adapter_process
        .calibration_roots_absent === false
      && failureShape.accepted_adapter_process
        .accepted_p1_129_source_preserved_read_only === false
      && failureShape.accepted_adapter_process
        .b2_independent_scan_reexecutions === 0
      && failureShape.accepted_adapter_process
        .distinct_b2_child_pids === 0
      && failureShape.accepted_adapter_process
        .all_current_b2_fixture_roots_absent === false
      && failureShape.accepted_adapter_process
        .historical_reviewed_binary_exact_bytes_claim === false
      && failureShape.accepted_adapter_process
        .cooperative_local_accepted_evidence_path_residual === true
      && failureShape.accepted_adapter_process
        .hostile_global_read_isolation_claim === false
      && failureShape.accepted_adapter_process
        .hostile_process_isolation_claim === false
      && failureShape.accepted_adapter_process
        .trusted_accepted_source_required === true
      && Array.isArray(failureShape.failures)
      && failureShape.failures.length === 1,
    "EVALUATOR_SELF_TEST_NON_PASS",
    "independent evaluator output schema drifted",
  );
  return {
    schema_version: "p1-165-independent-evaluator-self-test/v1",
    status: "PASS",
    matrix_sha256: matrixState.identity.sha256,
    categories: matrixState.matrix.categories.length,
    cases: matrixState.cases.length,
    duplicate_json_key_rejected: duplicateRejected,
    output_schema_closed_control: true,
  };
}


export function selfTestAcceptedInputBindings() {
  const dataset = loadAcceptedTaskDataset();
  const acceptedP0 = loadAcceptedP0SourceManifest();
  assert(
    dataset.task_specs.size === ACCEPTED_TASK_IDS.length
      && dataset.manifest_identity.sha256
        === ACCEPTED_TASK_DATASET_MANIFEST_SHA256
      && acceptedP0.manifest.entry_count === 10
      && acceptedP0.manifest.analyzer_tree
        === ACCEPTED_P0_BINDING.analyzer_subtree
      && acceptedP0.listing.length === acceptedP0.manifest.entry_count,
    "EVALUATOR_SELF_TEST_NON_PASS",
    "accepted input binding self-test drifted",
  );
  return {
    schema_version: "p1-165-accepted-input-binding-self-test/v1",
    status: "PASS",
    accepted_task_specs: dataset.task_specs.size,
    accepted_dataset_manifest_sha256:
      dataset.manifest_identity.sha256,
    accepted_p0_analyzer_entries: acceptedP0.manifest.entry_count,
    accepted_p0_analyzer_tree: acceptedP0.manifest.analyzer_tree,
  };
}

export async function selfTestIndependentCore() {
  const matrixState = loadAndValidateMatrix();
  const modules = await loadProductionKernel();
  const calibrationFixture = replayObserverFixture();
  const syntheticObserverFixture = {
    descriptor: calibrationFixture.descriptor,
    record: calibrationFixture.record,
    stdout: calibrationFixture.stdout,
    stderr: calibrationFixture.stderr,
  };
  let reexecuted = 0;
  for (const expected of matrixState.cases) {
    const stimulus = materializeExpectedStimulus(
      expected,
      syntheticObserverFixture,
      modules,
    );
    await independentlyReplayCase(
      expected,
      { stimulus },
      modules,
      null,
      syntheticObserverFixture,
    );
    reexecuted += 1;
  }
  let typedStimulusNegativeControls = 0;
  for (const categoryId of CATEGORY_ORDER) {
    const entries = matrixState.cases.filter(
      (entry) => entry.category_id === categoryId,
    );
    const expected = entries[0];
    const stimulus = materializeExpectedStimulus(
      expected,
      syntheticObserverFixture,
      modules,
    );
    const extra = JSON.parse(JSON.stringify(stimulus));
    extra.parameters.unexpected = true;
    const missing = JSON.parse(JSON.stringify(stimulus));
    delete missing.parameters[Object.keys(missing.parameters)[0]];
    const mutation = JSON.parse(JSON.stringify(stimulus));
    mutation.variant = `${mutation.variant}_DRIFT`;
    const crossBinding = materializeExpectedStimulus(
      entries[1],
      syntheticObserverFixture,
      modules,
    );
    for (const control of [extra, missing, mutation, crossBinding]) {
      let rejected = false;
      try {
        await independentlyReplayCase(
          expected,
          { stimulus: control },
          modules,
          null,
          syntheticObserverFixture,
        );
      } catch (error) {
        rejected =
          error instanceof EvaluationFailure
          && error.code === "CASE_INPUT_INVALID";
      }
      assert(
        rejected,
        "EVALUATOR_SELF_TEST_NON_PASS",
        `typed stimulus control failed open for ${categoryId}`,
      );
      typedStimulusNegativeControls += 1;
    }
  }
  return {
    schema_version: "p1-165-independent-core-self-test/v1",
    status: "PASS",
    cases_reexecuted: reexecuted,
    typed_stimulus_negative_controls: typedStimulusNegativeControls,
  };
}

export async function evaluateEvidence(evidenceRoot) {
  const matrixState = loadAndValidateMatrix();
  const root = safeEvidenceRoot(evidenceRoot);
  const manifestState = validateManifest(root, matrixState.identity);
  const p1168GateState = validateP1168GateEnvelope(root, manifestState);
  const atomicCommit = validateAtomicCommitReceipt(
    root,
    manifestState,
    matrixState,
    p1168GateState.envelope.prior_interrupted_attempt,
  );
  const secretScan = validateNoSecretTestSentinelReflection(root, manifestState);
  const acceptedInputProvenance = validateAcceptedInputProvenance(
    root,
    manifestState,
  );
  const kernelContract = validateKernelContract(root, manifestState, matrixState);
  const caseState = await validateCases(
    root,
    manifestState,
    matrixState,
    kernelContract,
    atomicCommit,
  );
  const cellState = await validateCells(
    root,
    manifestState,
    kernelContract,
    atomicCommit,
  );
  const historicalRootCauseRegressions =
    validateHistoricalRootCauseRegressionReceipt(root, manifestState);
  const ordinaryFailureControl = await validateOrdinaryFailureControls(
    root,
    manifestState,
    cellState,
    caseState.synthetic_observer_fixture,
  );
  const outputTokenControl = await validateOutputTokenBoundaryControls(
    root,
    manifestState,
    cellState,
    caseState.synthetic_observer_fixture,
  );
  const integrationNegativeControl = await validateIntegrationNegativeControls(
    root,
    manifestState,
  );
  const b2ScanChildren = validateB2ScanLedger(root, manifestState, cellState);
  const referenceScan = validateReferenceAnswerScan(
    root,
    manifestState,
    cellState,
  );
  const eventState = validateLivenessAndConcurrency(
    root,
    manifestState,
    matrixState,
    kernelContract,
    caseState.closed_child_environment,
  );
  const b0Cells = cellState.cells.filter((cell) => cell.profile_id.startsWith("B0_")).length;
  const b1Cells = cellState.cells.filter((cell) => cell.profile_id.startsWith("B1_")).length;
  const b2Cells = cellState.cells.filter((cell) => cell.profile_id.startsWith("B2_")).length;
  assert(
    b0Cells === 12 && b1Cells === 12 && b2Cells === 12,
    "CELL_SET_INVALID",
    "B0/B1/B2 cell distribution is not 12/12/12",
  );
  return {
    schema_version: RESULT_SCHEMA,
    task_id: TASK_ID,
    status: "PASS",
    reason_code: "PASS",
    raw_only: true,
    worker_summary_trusted: false,
    evidence_root: root,
    p1_168_task_gate_receipt: {
      schema_version: "p1-168-independent-task-gate-receipt/v1",
      task_id: P1_168_TASK_ID,
      gate_envelope_identity: p1168GateState.envelope_identity,
      task_contract: p1168GateState.envelope.task_contract,
      task_authority: p1168GateState.envelope.task_authority,
      restore_receipt: p1168GateState.envelope.restore_receipt,
      source_bundle_identity:
        p1168GateState.envelope.source_bundle_identity,
      prior_interrupted_attempt:
        p1168GateState.envelope.prior_interrupted_attempt,
      prior_complete_matrix_v2_and_global_gate:
        p1168GateState.envelope
          .prior_complete_matrix_v2_and_global_gate,
      source_file_count:
        p1168GateState.source_bundle.source_file_count,
      reproduction: p1168GateState.envelope.reproduction,
      inner_result: {
        schema_version: RESULT_SCHEMA,
        task_id: TASK_ID,
        matrix_sha256: matrixState.identity.sha256,
        matrix_cases: matrixState.cases.length,
        manifest_sha256: manifestState.artifact.identity.sha256,
        manifest_entries: manifestState.manifest.entry_count,
        status: "PASS",
      },
      status: "PASS",
    },
    matrix: {
      path: matrixState.identity.path,
      sha256: matrixState.identity.sha256,
      case_count: matrixState.cases.length,
    },
    manifest: {
      path: MANIFEST_PATH,
      sha256: manifestState.artifact.identity.sha256,
      entry_count: manifestState.manifest.entry_count,
    },
    distinct_adapter_roots: cellState.distinct_adapter_roots,
    distinct_spine_run_ids: cellState.distinct_spine_run_ids,
    closed_spine_artifact_sets: cellState.closed_spine_artifact_sets,
    production_admission_receipts: cellState.cells.length,
    production_cell_closures: cellState.cells.length,
    matrix_case_production_admissions: caseState.production_admissions,
    matrix_case_safe_failure_receipts: caseState.safe_failure_receipts,
    p1_101_rollbacks: cellState.p1_101_rollbacks,
    independent_reexecution_spines: cellState.independent_reexecution_spines,
    independent_case_reexecutions: caseState.independent_case_reexecutions,
    historical_root_cause_regressions: historicalRootCauseRegressions,
    accepted_adapter_process: cellState.accepted_adapter_process,
    counts: {
      cases_observed: caseState.cases_observed,
      cases_passed: caseState.cases_passed,
      false_accepts: caseState.false_accepts,
      unsafe_persistence: caseState.unsafe_persistence,
      synthetic_cells: cellState.cells.length,
      b0_cells: b0Cells,
      b1_cells: b1Cells,
      b2_cells: b2Cells,
      p1_149_spines: cellState.closed_spine_artifact_sets,
      p1_101_replays: cellState.p1_101_replays,
      b2_scan_children: b2ScanChildren,
      ordinary_failed_denominator_cases:
        ordinaryFailureControl.failed_denominator_cases,
      integration_negative_cases: integrationNegativeControl.cases,
      exact_output_token_boundary_spines:
        outputTokenControl.exact_boundary_spines,
      safe_failure_receipts_total:
        caseState.safe_failure_receipts
        + integrationNegativeControl.cases
        + 1,
      provider_requests: 0,
      secret_reads: 0,
      network_effects: 0,
    },
    usage: {
      unknown_preserved: caseState.usage.unknown_preserved,
      semantics: outputTokenControl.semantics,
      boundaries: outputTokenControl.boundaries,
      exact_boundary_spines: outputTokenControl.exact_boundary_spines,
      matrix_component_boundaries: caseState.usage.boundaries,
    },
    ordinary_failure_control: ordinaryFailureControl,
    output_token_control: outputTokenControl,
    integration_negative_control: integrationNegativeControl,
    atomic_commit: atomicCommit,
    concurrency: eventState.concurrency,
    liveness: eventState.liveness,
    external_effects: { ...FALSE_EXTERNAL_EFFECTS },
    reference_scan: referenceScan,
    secret_scan: secretScan,
    accepted_input_provenance: acceptedInputProvenance,
    failures: [],
  };
}

function isMain() {
  return process.argv[1] !== undefined
    && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  let matrixState = null;
  try {
    assert(
      process.argv.length === 3 && isAbsolute(process.argv[2]),
      "CLI_USAGE_INVALID",
      "usage: node evaluate.mjs /absolute/evidence-root",
    );
    matrixState = loadAndValidateMatrix();
    const receipt = await evaluateEvidence(process.argv[2]);
    process.stdout.write(`${canonicalJson(receipt)}\n`);
  } catch (error) {
    const failure = error instanceof EvaluationFailure
      ? error
      : new EvaluationFailure(
        "EVALUATOR_INTERNAL_ERROR",
        String(error?.stack ?? error),
      );
    const receipt = baseFailureResult(
      process.argv[2] ?? null,
      matrixState?.identity ?? null,
      failure,
    );
    process.stdout.write(`${canonicalJson(receipt)}\n`);
    process.exitCode = failure.code === "EVALUATOR_INTERNAL_ERROR" ? 2 : 1;
  }
}

import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  chmodSync,
  closeSync,
  constants as fsConstants,
  existsSync,
  fchmodSync,
  fstatSync,
  fsyncSync,
  linkSync,
  lstatSync,
  mkdirSync,
  openSync,
  opendirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from "node:path";
import { fileURLToPath } from "node:url";

import {
  REPOSITORY_ROOT,
  cleanupOwnedRoot,
  createDisposableRoot,
  createOwnedRoot,
  listClosedFiles,
  safeRealDirectory,
  validateArtifactPath,
  writeBytesCreateOnce,
  writeJsonCreateOnce,
} from "../p1-149-accepted-execution-spine/core.mjs";
import {
  ACCEPTED_TASK_IDS,
  buildAcceptedReferenceResponse,
  loadAcceptedCompilerProfile,
  verifyAcceptedPatchIrV1Compatibility,
} from "../p1-149-accepted-execution-spine/accepted-inputs.mjs";
import {
  EXECUTION_ARTIFACT_KEYS,
  executeSpine,
} from "../p1-149-accepted-execution-spine/execution.mjs";
import {
  buildNormalizedProviderResponse,
  compileNormalizedProviderResponse,
} from "../p1-149-accepted-execution-spine/patch-ir-v2.mjs";
import {
  READINESS_CLAIM_BOUNDARY,
  buildClosedEvidenceManifest,
  verifyFrozenExecutionEvidence,
} from "../../replay/p1-149-accepted-execution-spine/replay.mjs";
import {
  AdmissionNonPass,
  FALSE_EXTERNAL_EFFECTS,
  MODEL_FAILURE_SCHEMA,
  PROFILE_ORDER,
  RESPONSE_BYTES_MAX,
  TASK_ID,
  assertCritical,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  classifyModelFailureEnvelope,
  closedChildEnvironment,
  failCritical,
  isCriticalReasonCode,
  observedUsage,
  parseJsonBytesNoDuplicate,
  sha256,
  unknownUsage,
  validateIdentity,
  validateJoin,
  validatePolicy,
  validateUsage,
} from "./contract.mjs";
import {
  admitAndPersistResponse,
  assertNoSecretReflection,
  closeCellEvidence,
  commitOwnedEvidenceStage,
  parseClosedContextRecord,
  parseClosedRequestRecord,
  writeResearchFailureReceipt,
  writeSafeFailureReceipt,
} from "./admission.mjs";
import {
  parseClosedObserverRecord,
  validateRawObservation,
} from "./observer.mjs";
import {
  analyzeTransport,
  parseClosedTransportRecord,
} from "./transport.mjs";

const MATRIX_PATH = join(
  REPOSITORY_ROOT,
  "evaluation-harness/evaluator/p1-165-fail-closed-response-admission/matrix.json",
);
const MATRIX_SHA256 =
  "70cde8ec13a8d1f74d309b8d5a1b06579a571a7dfe29b4b8ba9b4cf90bc5bcc6";
const MATRIX_BYTE_LENGTH = 59333;
const P1_168_TASK_ID =
  "AIOS-P1-168_EXACT_RESPONSE_ADMISSION_MATRIX_RECOVERY_AND_GATE";
const P1_168_TASK_CONTRACT = Object.freeze({
  path: join(
    REPOSITORY_ROOT,
    "docs/aios/tasks/P1-168_EXACT_RESPONSE_ADMISSION_MATRIX_RECOVERY_AND_GATE.yaml",
  ),
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
const OUTPUT_TOKENS_MAX = 2048;
const CONCURRENCY_SLOTS = 4;
const PROOF_FILE_MAX_BYTES = 32 * 1024 * 1024;
const PROOF_TOTAL_MAX_BYTES = 256 * 1024 * 1024;
const PROOF_FILE_MAX_COUNT = 1024;
const PROOF_MAX_DEPTH = 16;
const B2_TREE_FILE_MAX_BYTES = 1024 * 1024;
const B2_TREE_TOTAL_MAX_BYTES = 2 * 1024 * 1024;
const B2_TREE_FILE_MAX_COUNT = 16;
const B2_TREE_MAX_DEPTH = 8;
const B2_BINARY_MAX_BYTES = 16 * 1024 * 1024;
const TASK_SPEC_MAX_BYTES = 64 * 1024;
const TASK_SPEC_SCHEMA_VERSION = "1.0";
const SANDBOX_EXEC = "/usr/bin/sandbox-exec";
const ACCEPTED_P1_129_TASK_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-audit/"
  + "p1-129-input-boundary-matrix-20260726/task-1";
const ACCEPTED_P1_129_FORMAL_ROOT = join(
  ACCEPTED_P1_129_TASK_ROOT,
  "formal-matrix-v1",
);
const ACCEPTED_P1_129_DATASET_PROVENANCE_ROOT =
  "/Users/lijunpeng/Developer/.sourcelens-worktrees/"
  + "AIOS-P1-129-input-boundary-matrix/evaluation-harness/datasets/"
  + "p1-representative-task-dataset-v1/tasks";
const ACCEPTED_P1_129_ARTIFACTS = Object.freeze({
  authority: Object.freeze({
    relative_path: "authority/PHASE_DELEGATED_TASK_AUTHORITY.yaml",
    byte_length: 2874,
    sha256: "1677708300e690342301b68b30237d62c992eaeeefe4a9c5418dc9c1cf514c29",
  }),
  candidate_manifest: Object.freeze({
    relative_path: "candidate-a772dc5/candidate-manifest.json",
    byte_length: 5766,
    sha256: "d149ca05809a5d411e888603ae0399dd56ee7b1075338cd4fb21792c02548b86",
  }),
  cto_review: Object.freeze({
    relative_path: "reviews/CTO_REVIEW.json",
    byte_length: 7578,
    sha256: "463b5d286702d6fc5cdb5bd24cb7a72cd0b066478fc33e06c891b3b96c2f49e1",
  }),
  security_review: Object.freeze({
    relative_path: "reviews/SECURITY_REVIEW.json",
    byte_length: 6654,
    sha256: "4be63b9684826542631f8c015367917c1c694ad517436462f2d49072b587a2ae",
  }),
  quality_review: Object.freeze({
    relative_path: "reviews/QUALITY_REVIEW.json",
    byte_length: 6329,
    sha256: "464f958f205d46f2908e386fb7b5f6f7979ee79ca7d1fbe7aa3854d72a7edeac",
  }),
  terminal_receipt: Object.freeze({
    relative_path: "terminal/P1_129_TERMINAL_RECEIPT.json",
    byte_length: 1389,
    sha256: "8caa2248a389304f142424590841662b99485d3124f2136b04bfc984fe406fb9",
  }),
  formal_summary: Object.freeze({
    relative_path: "formal-matrix-v1/quality-formal-summary.json",
    byte_length: 3598,
    sha256: "75d178240d3c493ee7d30b8c67428b0cfb9baac637517f70ddf7b0f008dda5c6",
  }),
  negative_results: Object.freeze({
    relative_path: "formal-matrix-v1/negative-results.json",
    byte_length: 33073,
    sha256: "2a93c69a8847b0333fe59fa39ca5f3441535cd8682e82da128692f1c24cd2166",
  }),
});
const ACCEPTED_P1_129_CANDIDATE_COMMIT =
  "a772dc5d350ec6b38a84e430b01f75628429aa7b";
const ACCEPTED_P1_129_CANDIDATE_TREE =
  "905dd694922ba9a2b452d15c93dc17cefc9e53c1";
const ACCEPTED_P1_129_SELECTED_B2_COUNT = 12;
const ACCEPTED_BINARY_EXECUTION_TIMEOUT_MS = 60 * 1000;
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
const ACCEPTED_DATASET_TASK_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks",
);
const CASE_INPUT_SCHEMA = "p1-165-matrix-case-input/v1";
const CASE_OBSERVATION_SCHEMA = "p1-165-matrix-case-observation/v1";
const CASE_PROCESS_RESULT_SCHEMA = "p1-165-case-process-result/v1";
const PROCESS_KEYS = Object.freeze([
  "argv",
  "environment",
  "exit_status",
  "parent_pid",
  "pid",
  "signal",
  "started_at",
  "stderr",
  "stdout",
  "stopped_at",
]);
const CREATE_ONCE_RACE_EVENT_KEYS = Object.freeze([
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
const LIVENESS_OBSERVATION_EVENT_KEYS = Object.freeze([
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
const ACCEPTED_ADAPTER_CONTROL_KEYS = Object.freeze([
  "accepted_authority_bundle_identity",
  "claim_boundary",
  "cleanup_verified",
  "cooperative_local_accepted_evidence_path_residual",
  "current_b2_distinct_child_pids",
  "current_b2_scan_receipt_identities",
  "historical_reviewed_binary_exact_bytes_claim",
  "hostile_global_read_isolation_claim",
  "hostile_process_isolation_claim",
  "trusted_accepted_source_required",
  "mode",
  "proof_limits_identity",
  "sandbox_calibration_identity",
  "schema_version",
  "source_formal_root",
  "status",
  "task_id",
]);
const ACCEPTED_ADAPTER_PROOF_FILES = Object.freeze({
  b0_result: "b0-result.json",
  b1_program: "b1-program.json",
  environment_snapshot: "environment-snapshot.json",
  execution_descriptor: "execution-descriptor.json",
  request: "request.json",
  adapter_execution_request:
    "worker-output/adapter-execution-request.json",
  adapter_command_ledger: "worker-output/adapter-command-ledger.json",
  adapter_result: "worker-output/adapter-result.json",
  run_record: "worker-output/run-record.json",
  stable_projection: "worker-output/stable-projection.json",
  target_executed: "worker-output/target-executed",
  trace: "worker-output/trace.jsonl",
});

function sameJson(left, right) {
  return canonicalJson(left) === canonicalJson(right);
}

function buildFrozenSyntheticObserverFixture({
  evidence_handle,
  join: joinValue,
  request_record_identity = null,
  request_record_factory = null,
  artifact_prefix,
  fixture_index,
}) {
  const validatedJoin = validateJoin(joinValue);
  assertCritical(
    (request_record_identity === null) !== (request_record_factory === null),
    "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
    "synthetic observer fixture requires exactly one request identity source",
  );
  assertCritical(
    Number.isSafeInteger(fixture_index)
      && fixture_index >= 1
      && fixture_index <= 1000,
    "OBSERVER_KEYSET_INVALID",
    "synthetic observer fixture index is invalid",
  );
  const peer = `127.0.0.1:${47000 + fixture_index}`;
  const local = `127.0.0.1:${48000 + fixture_index}`;
  const pid = 420000 + fixture_index;
  const fd = `${10 + (fixture_index % 80)}u`;
  const policy = {
    mode: "OWNED_CALIBRATION",
    expected_peer: peer,
    response_bytes_max: RESPONSE_BYTES_MAX,
    output_tokens_max: OUTPUT_TOKENS_MAX,
  };
  const requestIdentity = request_record_factory === null
    ? validateIdentity(request_record_identity)
    : validateIdentity(request_record_factory(policy));
  const stdoutBytes = Buffer.from(
    [
      "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME",
      `node ${pid} fixture ${fd} IPv4 0x0 0t0 TCP ${local}->${peer} (ESTABLISHED)`,
      "",
    ].join("\n"),
    "utf8",
  );
  const stderrBytes = Buffer.alloc(0);
  const stdoutPath = `${artifact_prefix}/stdout.log`;
  const stderrPath = `${artifact_prefix}/stderr.log`;
  const recordPath = `${artifact_prefix}/observation.json`;
  const descriptorPath = `${artifact_prefix}/synthetic-fixture.json`;
  const row = { pid, fd, local, peer, state: "ESTABLISHED" };
  const record = {
    schema_version: "p1-165-os-network-observation/v1",
    join: validatedJoin,
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
    stdout_path: stdoutPath,
    stdout_identity: bytesIdentity(stdoutBytes),
    stderr_path: stderrPath,
    stderr_identity: bytesIdentity(stderrBytes),
    observed_rows: [row],
    status: "PASS",
  };
  validateRawObservation({
    record,
    stdout_bytes: stdoutBytes,
    stderr_bytes: stderrBytes,
    join: validatedJoin,
    request_record_identity: requestIdentity,
    policy,
  });
  const descriptor = {
    schema_version: "p1-168-frozen-synthetic-observer-fixture/v1",
    task_id: TASK_ID,
    fixture_index,
    source_kind: "FROZEN_SYNTHETIC_OBSERVER_FIXTURE",
    command_executed: false,
    live_network_connection_created: false,
    live_network_connections_created: 0,
    live_loopback_calibration: "DEFERRED_TO_P1_169",
    production_record_schema: record.schema_version,
    production_record_identity: bytesIdentity(canonicalBytes(record)),
    stdout_identity: bytesIdentity(stdoutBytes),
    stderr_identity: bytesIdentity(stderrBytes),
    status: "PASS_SYNTHETIC_FIXTURE_ONLY",
  };
  writeBytesCreateOnce(evidence_handle, stdoutPath, stdoutBytes);
  writeBytesCreateOnce(evidence_handle, stderrPath, stderrBytes);
  writeJsonCreateOnce(evidence_handle, recordPath, record);
  writeJsonCreateOnce(evidence_handle, descriptorPath, descriptor);
  return {
    descriptor,
    live_network_connections_created: 0,
    policy,
    record,
    stdout_bytes: stdoutBytes,
    stderr_bytes: stderrBytes,
  };
}

function directoryIdentity(path, label) {
  const stat = lstatSync(path);
  assertCritical(
    stat.isDirectory()
      && !stat.isSymbolicLink()
      && stat.uid === process.getuid()
      && realpathSync(path) === path,
    stat.isSymbolicLink()
      ? "SYMLINK_REJECTED"
      : "PATH_ESCAPE_REJECTED",
    `${label} is not one real current-user directory`,
  );
  return {
    path,
    dev: stat.dev,
    ino: stat.ino,
    uid: stat.uid,
  };
}

function sandboxLiteral(value) {
  assertCritical(
    typeof value === "string"
      && isAbsolute(value)
      && !value.includes("\u0000"),
    "PATH_ESCAPE_REJECTED",
    "sandbox allowlist path is not one absolute path",
  );
  return JSON.stringify(value);
}

function sandboxProfileBytes(lines) {
  return Buffer.from(`${lines.join("\n")}\n`, "utf8");
}

function acceptedBinarySandboxProfile(
  disposableRoot,
  syntheticHome,
  executablePath,
) {
  const realHome = directoryIdentity(
    process.env.HOME,
    "operator HOME denied by accepted-binary sandbox",
  );
  const disposable = directoryIdentity(
    disposableRoot,
    "accepted-binary disposable root",
  );
  const synthetic = directoryIdentity(
    syntheticHome,
    "accepted-binary empty synthetic HOME",
  );
  assertCritical(
    syntheticHome === join(disposableRoot, "synthetic-home")
      && executablePath === join(disposableRoot, "sourcelens-analyzer")
      && disposable.uid === realHome.uid
      && synthetic.uid === realHome.uid,
    "PATH_ESCAPE_REJECTED",
    "accepted-binary sandbox roots are not exact owned paths",
  );
  const commonLines = [
    "(version 1)",
    "(allow default)",
    "(deny network*)",
    `(deny file-read* (subpath ${sandboxLiteral(realHome.path)}))`,
    `(allow file-read* (subpath ${sandboxLiteral(disposableRoot)}))`,
    '(allow file-read* (subpath "/System/Library"))',
    '(allow file-read* (subpath "/System/Volumes/Preboot/Cryptexes/OS/usr/lib"))',
    '(allow file-read* (subpath "/usr/lib"))',
    '(allow file-read* (subpath "/private/var/db/dyld"))',
    '(allow file-read* (literal "/dev/null"))',
    '(allow file-read* (literal "/dev/urandom"))',
    "(deny file-write*)",
    `(allow file-write* (subpath ${sandboxLiteral(disposableRoot)}))`,
  ];
  const profileBytes = sandboxProfileBytes([
    ...commonLines,
  ]);
  const calibrationProfileBytes = sandboxProfileBytes([
    ...commonLines,
    `(allow file-read* (literal ${sandboxLiteral(process.execPath)}))`,
  ]);
  return {
    environment: closedChildEnvironment(syntheticHome),
    real_home_identity: realHome,
    disposable_root_identity: disposable,
    synthetic_home_identity: synthetic,
    profile: profileBytes.toString("utf8"),
    profile_bytes: profileBytes,
    calibration_profile: calibrationProfileBytes.toString("utf8"),
    calibration_profile_bytes: calibrationProfileBytes,
    claim_boundary:
      "COOPERATIVE_LOCAL_TRUSTED_ACCEPTED_BINARY_EFFECT_CONFINEMENT",
  };
}

function boundedDirectoryEntries(path, label, maximumEntries) {
  assertCritical(
    Number.isSafeInteger(maximumEntries) && maximumEntries >= 0,
    "RESOURCE_LIMIT_EXCEEDED",
    `${label} entry limit is invalid`,
  );
  directoryIdentity(path, label);
  const directory = opendirSync(path);
  const entries = [];
  try {
    while (true) {
      const entry = directory.readSync();
      if (entry === null) break;
      entries.push(entry);
      assertCritical(
        entries.length <= maximumEntries,
        "RESOURCE_LIMIT_EXCEEDED",
        `${label} exceeds its directory-entry limit`,
      );
    }
  } finally {
    directory.closeSync();
  }
  return entries.sort((left, right) => left.name.localeCompare(right.name));
}

function planRegularFileWithinRoot(
  root,
  relativePath,
  { label, maximumBytes, maximumDepth = PROOF_MAX_DEPTH },
) {
  const normalized = validateArtifactPath(relativePath, label);
  const depth = normalized.split("/").length;
  assertCritical(
    depth <= maximumDepth,
    "RESOURCE_LIMIT_EXCEEDED",
    `${label} exceeds its path-depth limit`,
  );
  const rootIdentity = directoryIdentity(root, `${label} root`);
  const absolutePath = join(root, ...normalized.split("/"));
  assertCritical(
    relative(root, absolutePath).split(sep).join("/") === normalized,
    "PATH_ESCAPE_REJECTED",
    `${label} escapes its fixed root`,
  );
  const ancestors = [];
  let current = root;
  for (const component of dirname(normalized).split("/")) {
    if (component === ".") continue;
    current = join(current, component);
    const identity = directoryIdentity(current, `${label} ancestor`);
    assertCritical(
      identity.dev === rootIdentity.dev
        && identity.uid === rootIdentity.uid,
      "PATH_ESCAPE_REJECTED",
      `${label} ancestor crosses ownership or filesystem boundary`,
    );
    ancestors.push(identity);
  }
  const stat = lstatSync(absolutePath);
  assertCritical(
    stat.isFile()
      && !stat.isSymbolicLink()
      && stat.nlink === 1
      && stat.dev === rootIdentity.dev
      && stat.uid === rootIdentity.uid
      && Number.isSafeInteger(stat.size)
      && stat.size >= 0
      && stat.size <= maximumBytes,
    stat.isSymbolicLink()
      ? "SYMLINK_REJECTED"
      : !stat.isFile()
        ? "NON_REGULAR_FILE_REJECTED"
        : stat.nlink !== 1
          ? "HARDLINK_REJECTED"
          : stat.size > maximumBytes
            ? "RESOURCE_LIMIT_EXCEEDED"
            : "NON_REGULAR_FILE_REJECTED",
    `${label} is not one bounded single-link owned regular file`,
  );
  return {
    relative_path: normalized,
    absolute_path: absolutePath,
    byte_length: stat.size,
    depth,
    dev: stat.dev,
    ino: stat.ino,
    uid: stat.uid,
    nlink: stat.nlink,
    mode: stat.mode & 0o777,
    root_identity: rootIdentity,
    ancestor_identities: ancestors,
  };
}

function boundedTreePlan(
  root,
  {
    label,
    maximumFiles,
    maximumTotalBytes,
    maximumFileBytes,
    maximumDepth,
  },
) {
  const rootIdentity = directoryIdentity(root, label);
  const files = [];
  let totalBytes = 0;
  let directoryCount = 1;
  const visit = (directoryPath, prefix, depth) => {
    assertCritical(
      depth <= maximumDepth,
      "RESOURCE_LIMIT_EXCEEDED",
      `${label} exceeds its directory-depth limit`,
    );
    const entries = boundedDirectoryEntries(
      directoryPath,
      `${label} directory`,
      maximumFiles + 64,
    );
    for (const entry of entries) {
      const relativePath = prefix === ""
        ? entry.name
        : `${prefix}/${entry.name}`;
      const absolutePath = join(directoryPath, entry.name);
      const stat = lstatSync(absolutePath);
      assertCritical(
        !stat.isSymbolicLink()
          && stat.dev === rootIdentity.dev
          && stat.uid === rootIdentity.uid,
        stat.isSymbolicLink()
          ? "SYMLINK_REJECTED"
          : "PATH_ESCAPE_REJECTED",
        `${label} entry crosses its owned closed-tree boundary`,
      );
      if (stat.isDirectory()) {
        directoryCount += 1;
        assertCritical(
          directoryCount <= maximumFiles + 64
            && realpathSync(absolutePath) === absolutePath,
          "RESOURCE_LIMIT_EXCEEDED",
          `${label} exceeds its directory-count limit`,
        );
        visit(absolutePath, relativePath, depth + 1);
        continue;
      }
      assertCritical(
        stat.isFile()
          && stat.nlink === 1
          && stat.size <= maximumFileBytes,
        !stat.isFile()
          ? "NON_REGULAR_FILE_REJECTED"
          : stat.nlink !== 1
            ? "HARDLINK_REJECTED"
            : stat.size > maximumFileBytes
              ? "RESOURCE_LIMIT_EXCEEDED"
              : "NON_REGULAR_FILE_REJECTED",
        `${label} contains an unsafe or oversized file`,
      );
      files.push(
        planRegularFileWithinRoot(root, relativePath, {
          label: `${label} file`,
          maximumBytes: maximumFileBytes,
          maximumDepth,
        }),
      );
      totalBytes += stat.size;
      assertCritical(
        files.length <= maximumFiles
          && totalBytes <= maximumTotalBytes,
        "RESOURCE_LIMIT_EXCEEDED",
        `${label} exceeds its file-count or aggregate-byte limit`,
      );
    }
  };
  visit(root, "", 0);
  return {
    files: files.sort((left, right) =>
      left.relative_path.localeCompare(right.relative_path)
    ),
    file_count: files.length,
    total_byte_length: totalBytes,
    maximum_files: maximumFiles,
    maximum_total_bytes: maximumTotalBytes,
    maximum_file_bytes: maximumFileBytes,
    maximum_depth: maximumDepth,
  };
}

function identityWithPath(root, relativePath) {
  const absolute = join(root, ...relativePath.split("/"));
  const stat = lstatSync(absolute);
  assertCritical(
    stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
    stat.isSymbolicLink()
      ? "SYMLINK_REJECTED"
      : !stat.isFile()
        ? "NON_REGULAR_FILE_REJECTED"
        : "HARDLINK_REJECTED",
    `Evidence artifact is not a single-link regular file: ${relativePath}`,
  );
  const bytes = readFileSync(absolute);
  return {
    path: relativePath,
    type: "REGULAR_FILE",
    nlink: 1,
    byte_length: bytes.length,
    sha256: sha256(bytes),
  };
}

function readCurrentRegularFile(absolutePath, recordedPath, label) {
  assertCritical(
    isAbsolute(absolutePath) && resolve(absolutePath) === absolutePath,
    "PATH_ESCAPE_REJECTED",
    `${label} path is not exact absolute`,
  );
  const before = lstatSync(absolutePath);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assertCritical(
    !before.isSymbolicLink()
      && before.isFile()
      && before.nlink === 1
      && (uid === null || before.uid === uid)
      && Number.isSafeInteger(before.size)
      && before.size <= PROOF_FILE_MAX_BYTES,
    before.isSymbolicLink()
      ? "SYMLINK_REJECTED"
      : !before.isFile()
        ? "NON_REGULAR_FILE_REJECTED"
        : before.nlink !== 1
          ? "HARDLINK_REJECTED"
          : "IDENTITY_MISMATCH",
    `${label} is not one owned bounded regular file`,
  );
  let descriptor;
  try {
    descriptor = openSync(
      absolutePath,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const opened = fstatSync(descriptor);
    assertCritical(
      opened.isFile()
        && opened.nlink === 1
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.size === before.size,
      "IDENTITY_MISMATCH",
      `${label} changed before open`,
    );
    const bytes = readFileSync(descriptor);
    const after = fstatSync(descriptor);
    const finalStat = lstatSync(absolutePath);
    assertCritical(
      after.dev === opened.dev
        && after.ino === opened.ino
        && after.size === opened.size
        && finalStat.dev === opened.dev
        && finalStat.ino === opened.ino
        && finalStat.size === opened.size
        && finalStat.nlink === 1,
      "IDENTITY_MISMATCH",
      `${label} changed during read`,
    );
    return {
      path: recordedPath,
      byte_length: bytes.length,
      sha256: sha256(bytes),
    };
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function exactExternalBinding(expected, label) {
  const observed = readCurrentRegularFile(
    expected.path,
    expected.path,
    label,
  );
  assertCritical(
    sameJson(observed, expected),
    "IDENTITY_MISMATCH",
    `${label} exact bytes drifted`,
  );
  return observed;
}

function captureP1168V1RootClosure() {
  const rootStat = lstatSync(P1_168_COMPLETE_MATRIX_V1_ROOT);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assertCritical(
    rootStat.isDirectory()
      && !rootStat.isSymbolicLink()
      && (uid === null || rootStat.uid === uid)
      && (rootStat.mode & 0o777) === 0o700
      && realpathSync(P1_168_COMPLETE_MATRIX_V1_ROOT)
        === P1_168_COMPLETE_MATRIX_V1_ROOT,
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete Evidence root identity drifted",
  );
  const entries = [];
  let totalBytes = 0;
  let directoryCount = 0;
  let manifestBytes = null;
  const visit = (absoluteDirectory, relativeDirectory, depth) => {
    const directoryStat = lstatSync(absoluteDirectory);
    directoryCount += 1;
    assertCritical(
      directoryStat.isDirectory()
        && !directoryStat.isSymbolicLink()
        && (uid === null || directoryStat.uid === uid)
        && (directoryStat.mode & 0o777) === 0o700
        && directoryCount <= 1024
        && depth <= 32,
      "IDENTITY_MISMATCH",
      "P1-168 v1 complete root contains an unsafe directory",
    );
    for (const name of readdirSync(absoluteDirectory).sort()) {
      const absolutePath = join(absoluteDirectory, name);
      const relativePath = relativeDirectory === ""
        ? name
        : `${relativeDirectory}/${name}`;
      const before = lstatSync(absolutePath);
      assertCritical(
        !before.isSymbolicLink()
          && (uid === null || before.uid === uid),
        before.isSymbolicLink()
          ? "SYMLINK_REJECTED"
          : "IDENTITY_MISMATCH",
        "P1-168 v1 complete root entry ownership or type drifted",
      );
      if (before.isDirectory()) {
        visit(absolutePath, relativePath, depth + 1);
        continue;
      }
      assertCritical(
        before.isFile()
          && before.nlink === 1
          && (before.mode & 0o777) === 0o600
          && before.size <= 32 * 1024 * 1024
          && entries.length < 4096
          && totalBytes + before.size <= 256 * 1024 * 1024,
        !before.isFile()
          ? "NON_REGULAR_FILE_REJECTED"
          : before.nlink !== 1
            ? "HARDLINK_REJECTED"
            : "IDENTITY_MISMATCH",
        "P1-168 v1 complete root file boundary drifted",
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
        assertCritical(
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
        );
        const entry = {
          path: relativePath,
          type: "REGULAR_FILE",
          mode: "600",
          byte_length: bytes.length,
          sha256: sha256(bytes),
        };
        entries.push(entry);
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
  assertCritical(
    manifestBytes !== null,
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root manifest is missing",
  );
  const manifestIdentity = {
    path: P1_168_V1_ARTIFACTS.manifest.path,
    byte_length: manifestBytes.length,
    sha256: sha256(manifestBytes),
  };
  assertCritical(
    sameJson(manifestIdentity, P1_168_V1_ARTIFACTS.manifest),
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root manifest identity drifted",
  );
  const manifest = parseJsonBytesNoDuplicate(manifestBytes, {
    label: "P1-168 v1 complete root manifest",
    invalid_code: "IDENTITY_MISMATCH",
  });
  assertCritical(
    manifestBytes.equals(canonicalBytes(manifest))
      && sameJson(
        Object.keys(manifest).sort(),
        [
          "entries",
          "entry_count",
          "matrix_sha256",
          "schema_version",
          "task_id",
        ],
      )
      && manifest.schema_version === "p1-165-raw-evidence-manifest/v1"
      && manifest.task_id === TASK_ID
      && manifest.entry_count === 3829
      && manifest.matrix_sha256
        === "f9a38ecc512d4c2c8ba536eb3023dc6dfb6f78cfc5203be5853fe68321a5a298"
      && Array.isArray(manifest.entries)
      && manifest.entries.length === manifest.entry_count,
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root manifest schema drifted",
  );
  const declaredPaths = new Set();
  for (const entry of manifest.entries) {
    assertCritical(
      entry !== null
        && typeof entry === "object"
        && !Array.isArray(entry)
        && sameJson(
          Object.keys(entry).sort(),
          ["byte_length", "nlink", "path", "sha256", "type"],
        )
        && typeof entry.path === "string"
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
  assertCritical(
    sameJson(manifest.entries, liveDeclaredEntries),
    "IDENTITY_MISMATCH",
    "P1-168 v1 manifest does not exactly bind every live payload file",
  );
  const inventory = {
    entry_count: entries.length,
    total_bytes: totalBytes,
    sha256: sha256(canonicalBytes(entries)),
  };
  assertCritical(
    sameJson(inventory, {
      entry_count: 3830,
      total_bytes: 167164014,
      sha256:
        "d083c053e8de09efbfed2d2109c7c861ad0d7fc00e7c8b0dd92c808e32d91a64",
    }),
    "IDENTITY_MISMATCH",
    "P1-168 v1 complete root closed inventory drifted",
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

function capturePriorInterruptedAttempt(outputRoot) {
  assertCritical(
    outputRoot !== P1_168_COMPLETE_MATRIX_V1_ROOT,
    "ROOT_PREEXISTS",
    "P1-168 v1 Evidence root is terminal and cannot be reused",
  );
  const stat = lstatSync(P1_168_ABORTED_STAGE_PATH);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assertCritical(
    stat.isDirectory()
      && !stat.isSymbolicLink()
      && (uid === null || stat.uid === uid)
      && realpathSync(P1_168_ABORTED_STAGE_PATH)
        === P1_168_ABORTED_STAGE_PATH,
    "IDENTITY_MISMATCH",
    "P1-168 interrupted precommit stage identity drifted",
  );
  const stageInventory = listClosedFiles(P1_168_ABORTED_STAGE_PATH);
  const stageInventoryIdentity = {
    entry_count: stageInventory.length,
    total_bytes: stageInventory.reduce(
      (total, entry) => total + entry.byte_length,
      0,
    ),
    sha256: sha256(canonicalBytes(stageInventory)),
  };
  assertCritical(
    sameJson(stageInventoryIdentity, {
      entry_count: 744,
      total_bytes: 161608624,
      sha256:
        "18e90cfb2d16c6fe78f152cb96321c44c2706df3591a9dbb997d2ef8f142659b",
    }),
    "IDENTITY_MISMATCH",
    "P1-168 interrupted precommit stage closed inventory drifted",
  );
  const artifacts = Object.fromEntries(
    Object.entries(P1_168_V1_ARTIFACTS).map(([name, identity]) => [
      name,
      exactExternalBinding(identity, `P1-168 v1 prior ${name}`),
    ]),
  );
  const wrapperExit = parseJsonBytesNoDuplicate(
    readFileSync(artifacts.wrapper_exit.path),
    {
      label: "P1-168 v1 wrapper exit receipt",
      invalid_code: "IDENTITY_MISMATCH",
    },
  );
  const evaluatorExit = parseJsonBytesNoDuplicate(
    readFileSync(artifacts.evaluator_exit.path),
    {
      label: "P1-168 v1 independent evaluator exit receipt",
      invalid_code: "IDENTITY_MISMATCH",
    },
  );
  const evaluatorResult = parseJsonBytesNoDuplicate(
    readFileSync(artifacts.evaluator_stdout.path),
    {
      label: "P1-168 v1 independent evaluator result",
      invalid_code: "IDENTITY_MISMATCH",
    },
  );
  assertCritical(
    wrapperExit.status === "NON_PASS"
      && wrapperExit.exit_status === 1
      && evaluatorExit.status === "NON_PASS"
      && evaluatorExit.exit_status === 1
      && evaluatorExit.signal === null
      && evaluatorResult.status === "NON_PASS"
      && evaluatorResult.reason_code === "PROCESS_RECORD_INVALID",
    "IDENTITY_MISMATCH",
    "P1-168 v1 prior terminal verdict drifted",
  );
  const completeEvidenceRoot = captureP1168V1RootClosure();
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
      inventory: stageInventoryIdentity,
      final_root_created: false,
      accepted_evidence: false,
      stage_reused: false,
    },
  };
}

function captureP1168V2AndMakeVerifyLineage(outputRoot) {
  assertCritical(
    outputRoot !== P1_168_COMPLETE_MATRIX_ROOT,
    "ROOT_PREEXISTS",
    "P1-168 v2 Evidence root is historical and cannot be reused",
  );
  const rootStat = lstatSync(P1_168_COMPLETE_MATRIX_ROOT);
  const uid = typeof process.getuid === "function" ? process.getuid() : null;
  assertCritical(
    rootStat.isDirectory()
      && !rootStat.isSymbolicLink()
      && (uid === null || rootStat.uid === uid)
      && (rootStat.mode & 0o777) === 0o700
      && realpathSync(P1_168_COMPLETE_MATRIX_ROOT)
        === P1_168_COMPLETE_MATRIX_ROOT,
    "IDENTITY_MISMATCH",
    "P1-168 v2 complete Evidence root identity drifted",
  );
  const entries = listClosedFiles(P1_168_COMPLETE_MATRIX_ROOT);
  const inventory = {
    entry_count: entries.length,
    total_bytes: entries.reduce(
      (total, entry) => total + entry.byte_length,
      0,
    ),
    sha256: sha256(canonicalBytes(entries)),
  };
  assertCritical(
    sameJson(inventory, {
      entry_count: 3830,
      total_bytes: 167175907,
      sha256:
        "41e2680bad8f5622678cc900321c7f767bfabad7a003e31f97f65836d89218ff",
    }),
    "IDENTITY_MISMATCH",
    "P1-168 v2 complete root closed inventory drifted",
  );
  const artifacts = Object.fromEntries(
    Object.entries(P1_168_V2_ARTIFACTS).map(([name, identity]) => [
      name,
      exactExternalBinding(identity, `P1-168 v2 ${name}`),
    ]),
  );
  const manifestBytes = readFileSync(artifacts.manifest.path);
  const manifest = parseJsonBytesNoDuplicate(manifestBytes, {
    label: "P1-168 v2 complete root manifest",
    invalid_code: "IDENTITY_MISMATCH",
  });
  assertCritical(
    manifestBytes.equals(canonicalBytes(manifest))
      && manifest.schema_version === "p1-165-raw-evidence-manifest/v1"
      && manifest.task_id === TASK_ID
      && manifest.entry_count === 3829
      && manifest.matrix_sha256
        === "289ebf1022b1531e11c56d3bc8ae2ff2c2c874d841017703b64097a50d1dd393"
      && sameJson(
        manifest.entries,
        entries
          .filter((entry) => entry.path !== "RAW_EVIDENCE_MANIFEST.json")
          .map((entry) => ({
            path: entry.path,
            type: entry.type,
            nlink: 1,
            byte_length: entry.byte_length,
            sha256: entry.sha256,
          })),
      ),
    "IDENTITY_MISMATCH",
    "P1-168 v2 manifest does not close the exact root",
  );
  const wrapperExit = parseJsonBytesNoDuplicate(
    readFileSync(artifacts.wrapper_exit.path),
    {
      label: "P1-168 v2 wrapper exit receipt",
      invalid_code: "IDENTITY_MISMATCH",
    },
  );
  const wrapperLines = readFileSync(artifacts.wrapper_stdout.path, "utf8")
    .split("\n")
    .filter((line) => line.startsWith("{"))
    .map((line) => parseJsonBytesNoDuplicate(Buffer.from(line), {
      label: "P1-168 v2 wrapper stdout JSON line",
      invalid_code: "IDENTITY_MISMATCH",
    }));
  const evaluatorResult = wrapperLines.at(-1);
  assertCritical(
    wrapperExit.status === "PASS"
      && wrapperExit.exit_status === 0
      && wrapperLines.length >= 2
      && wrapperLines[0].status === "PASS"
      && evaluatorResult.status === "PASS"
      && evaluatorResult.reason_code === "PASS",
    "IDENTITY_MISMATCH",
    "P1-168 v2 preflight/evaluator verdict drifted",
  );
  const makeArtifacts = Object.fromEntries(
    Object.entries(P1_168_MAKE_VERIFY_V1_ARTIFACTS)
      .map(([name, identity]) => [
        name,
        exactExternalBinding(identity, `P1-168 make verify v1 ${name}`),
      ]),
  );
  const makeReceipt = parseJsonBytesNoDuplicate(
    readFileSync(makeArtifacts.receipt.path),
    {
      label: "P1-168 worktree make verify v1 receipt",
      invalid_code: "IDENTITY_MISMATCH",
    },
  );
  assertCritical(
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

function captureP1168GateInputs(outputRoot) {
  const observedCwd = realpathSync(process.cwd());
  assertCritical(
    observedCwd === REPOSITORY_ROOT,
    "PATH_ESCAPE_REJECTED",
    "P1-168 reproduction cwd is not the exact Task worktree",
  );
  const executionFiles = P1_168_EXECUTION_SOURCE_PATHS.map((relativePath) =>
    readCurrentRegularFile(
      join(REPOSITORY_ROOT, ...relativePath.split("/")),
      relativePath,
      `P1-168 current execution source ${relativePath}`,
    ));
  const verifier = readCurrentRegularFile(
    join(REPOSITORY_ROOT, P1_168_VERIFIER_SOURCE_PATH),
    P1_168_VERIFIER_SOURCE_PATH,
    "P1-168 verifier source",
  );
  return {
    task_contract: exactExternalBinding(
      P1_168_TASK_CONTRACT,
      "P1-168 Task Contract",
    ),
    task_authority: exactExternalBinding(
      P1_168_TASK_AUTHORITY,
      "P1-168 Task authority",
    ),
    restore_receipt: exactExternalBinding(
      P1_168_RESTORE_RECEIPT,
      "P1-168 snapshot restore receipt",
    ),
    execution_files: executionFiles,
    verifier,
    prior_interrupted_attempt:
      capturePriorInterruptedAttempt(outputRoot),
    prior_complete_matrix_v2_and_global_gate:
      captureP1168V2AndMakeVerifyLineage(outputRoot),
    reproduction: {
      executed_argv: [
        join(REPOSITORY_ROOT, P1_168_VERIFIER_SOURCE_PATH),
        outputRoot,
      ],
      independent_evaluator_argv: [
        process.execPath,
        join(
          REPOSITORY_ROOT,
          "evaluation-harness/evaluator/"
          + "p1-165-fail-closed-response-admission/evaluate.mjs",
        ),
        outputRoot,
      ],
      fresh_run_argv_template: [
        join(REPOSITORY_ROOT, P1_168_VERIFIER_SOURCE_PATH),
        "<ABSOLUTE_NORMALIZED_ABSENT_EVIDENCE_ROOT>",
      ],
      fresh_root_requirement:
        "ABSOLUTE_NORMALIZED_ABSENT_NON_SYMLINK_CREATE_ONCE",
      cwd: observedCwd,
      runtime: {
        node_executable: process.execPath,
        node_version: process.version,
        platform: process.platform,
        architecture: process.arch,
      },
    },
  };
}

function assertP1168GateInputsStable(captured, outputRoot) {
  const current = captureP1168GateInputs(outputRoot);
  assertCritical(
    sameJson(current, captured),
    "IDENTITY_MISMATCH",
    "P1-168 gate inputs or current kernel source bundle drifted during run",
  );
  return current;
}

function writeP1168GateEnvelope(
  handle,
  captured,
  matrixRun,
) {
  const sourceBundle = {
    schema_version: "p1-168-current-kernel-source-bundle/v1",
    task_id: P1_168_TASK_ID,
    execution_files: captured.execution_files,
    verifier: captured.verifier,
    source_file_count: captured.execution_files.length + 1,
    reproduction: captured.reproduction,
    status: "PASS",
  };
  const sourceBundleIdentity = writeJsonCreateOnce(
    handle,
    P1_168_SOURCE_BUNDLE_PATH,
    sourceBundle,
  );
  const envelope = {
    schema_version: "p1-168-task-gate-envelope/v1",
    task_id: P1_168_TASK_ID,
    task_contract: captured.task_contract,
    task_authority: captured.task_authority,
    restore_receipt: captured.restore_receipt,
    prior_interrupted_attempt: captured.prior_interrupted_attempt,
    prior_complete_matrix_v2_and_global_gate:
      captured.prior_complete_matrix_v2_and_global_gate,
    source_bundle_identity: sourceBundleIdentity,
    compatibility_kernel: {
      schema_version: "p1-165-offline-preflight/v1",
      task_id: TASK_ID,
      matrix_sha256: MATRIX_SHA256,
      matrix_cases: matrixRun.observations.length,
      admitted_matrix_cases: matrixRun.accounting.admitted,
      safe_failure_receipts: matrixRun.accounting.safe_failure_receipts,
      status: "PASS",
    },
    reproduction: captured.reproduction,
    status: "READY_FOR_INDEPENDENT_EVALUATION",
  };
  const envelopeIdentity = writeJsonCreateOnce(
    handle,
    P1_168_GATE_ENVELOPE_PATH,
    envelope,
  );
  return {
    source_bundle: sourceBundle,
    source_bundle_identity: sourceBundleIdentity,
    envelope,
    envelope_identity: envelopeIdentity,
  };
}

export function selfTestP1168GateBindings(outputRoot) {
  assertCritical(
    typeof outputRoot === "string"
      && isAbsolute(outputRoot)
      && resolve(outputRoot) === outputRoot
      && !integrationFixtureExists(outputRoot),
    "PATH_ESCAPE_REJECTED",
    "P1-168 gate binding self-test root must be exact absolute and absent",
  );
  const captured = captureP1168GateInputs(outputRoot);
  assertP1168GateInputsStable(captured, outputRoot);
  return {
    schema_version: "p1-168-gate-binding-self-test/v1",
    task_id: P1_168_TASK_ID,
    execution_source_files: captured.execution_files.length,
    verifier_source_files: 1,
    task_contract_sha256: captured.task_contract.sha256,
    task_authority_sha256: captured.task_authority.sha256,
    restore_receipt_sha256: captured.restore_receipt.sha256,
    reproduction: captured.reproduction,
    status: "PASS",
  };
}

function writeCaseBytes(handle, caseId, suffix, bytes) {
  const path = `raw/matrix-process/${caseId}/${suffix}`;
  writeBytesCreateOnce(handle, path, bytes);
  return identityWithPath(handle.root, path);
}

function writeCaseJson(handle, caseId, suffix, value) {
  return writeCaseBytes(handle, caseId, suffix, canonicalBytes(value));
}

function loadMatrix() {
  const bytes = readFileSync(MATRIX_PATH);
  assertCritical(
    bytes.length === MATRIX_BYTE_LENGTH && sha256(bytes) === MATRIX_SHA256,
    "IDENTITY_MISMATCH",
    "P1-165 Quality matrix identity drifted",
  );
  const value = JSON.parse(bytes.toString("utf8"));
  const cases = value.categories?.flatMap((category) =>
    (category.cases ?? []).map((entry) => ({
      ...entry,
      category_id: category.category_id,
    }))) ?? [];
  const typedUsageCases = cases.filter((entry) =>
    Object.hasOwn(entry, "output_tokens")
      || Object.hasOwn(entry, "full_spine_required"));
  assertCritical(
    value.schema_version === "p1-165-quality-matrix/v1"
      && value.task_id === TASK_ID
      && Array.isArray(value.categories)
      && cases.length === 99
      && typedUsageCases.length === 3
      && typedUsageCases.every((entry) =>
        entry.category_id === "USAGE_CONTRACT"
          && sameJson(
            Object.keys(entry).sort(),
            [
              "case_id",
              "category_id",
              "expected_persistence",
              "expected_reason_code",
              "expected_status",
              "full_spine_required",
              "output_tokens",
              "stimulus",
            ],
          )
          && Number.isSafeInteger(entry.output_tokens)
          && [2047, 2048, 2049].includes(entry.output_tokens)
          && typeof entry.full_spine_required === "boolean"
          && entry.full_spine_required === (entry.output_tokens === 2048)),
    "IDENTITY_MISMATCH",
    "P1-165 Quality matrix structure drifted",
  );
  for (const entry of cases) validateMatrixStimulusPlan(entry);
  return { bytes, value };
}

function flattenCases(matrix) {
  return matrix.categories.flatMap((category) => category.cases.map((entry) => ({
    ...entry,
    category_id: category.category_id,
  })));
}

function buildHttpResponse(body, headers = []) {
  const headerLines = [
    "HTTP/1.1 200 OK",
    "Content-Type: application/json",
    `Content-Length: ${body.length}`,
    ...headers,
    "Connection: close",
  ];
  return Buffer.concat([
    Buffer.from(`${headerLines.join("\r\n")}\r\n\r\n`, "latin1"),
    body,
  ]);
}

function exactTotalHttpResponse(totalBytes) {
  assertCritical(
    Number.isSafeInteger(totalBytes) && totalBytes >= 128,
    "HTTP_FRAMING_INCOMPLETE",
    "exact HTTP response size is invalid",
  );
  let bodyLength = totalBytes - 100;
  for (let attempt = 0; attempt < 32; attempt += 1) {
    const candidate = buildHttpResponse(Buffer.alloc(bodyLength, 0x61));
    if (candidate.length === totalBytes) return candidate;
    bodyLength += totalBytes - candidate.length;
  }
  failCritical(
    "HTTP_FRAMING_INCOMPLETE",
    "could not construct exact-size HTTP response",
  );
}

function splitBytes(bytes, sizes) {
  const chunks = [];
  let cursor = 0;
  for (const size of sizes) {
    if (cursor >= bytes.length) break;
    chunks.push(bytes.subarray(cursor, Math.min(cursor + size, bytes.length)));
    cursor += size;
  }
  if (cursor < bytes.length) chunks.push(bytes.subarray(cursor));
  return chunks;
}

function transportStimulus(variant, base) {
  let response = buildHttpResponse(Buffer.from('{"ok":true}\n', "utf8"));
  let chunks = [response];
  let eof = true;
  let terminal = [];
  if (variant === "ZERO_BYTES") response = Buffer.alloc(0);
  if (variant === "CAP_MINUS_ONE") response = exactTotalHttpResponse(RESPONSE_BYTES_MAX - 1);
  if (variant === "CAP_EXACT") response = exactTotalHttpResponse(RESPONSE_BYTES_MAX);
  if (variant === "CAP_PLUS_ONE") response = Buffer.alloc(RESPONSE_BYTES_MAX + 1, 0x61);
  if (variant === "MULTI_CHUNK") chunks = splitBytes(response, [1, 2, 3, 5, 8, 13]);
  if (variant === "INCOMPLETE_FRAMING") response = Buffer.from("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n", "latin1");
  if (variant === "TRUNCATED_BODY") response = Buffer.from("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nabc", "latin1");
  if (variant === "EARLY_CLOSE") eof = false;
  if (variant === "MISSING_TERMINAL") {
    response = Buffer.from(
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n",
      "latin1",
    );
  }
  if (variant === "DUPLICATE_TERMINAL") {
    terminal = [
      { kind: "APPLICATION_TERMINAL", offset: response.length },
      { kind: "APPLICATION_TERMINAL", offset: response.length },
    ];
  }
  if (variant === "POST_TERMINAL_BYTES") {
    terminal = [{ kind: "APPLICATION_TERMINAL", offset: response.length - 1 }];
  }
  if (variant === "CONTENT_LENGTH_MISMATCH") {
    response = Buffer.from(
      "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Length: 3\r\n\r\nabc",
      "latin1",
    );
  }
  if (variant === "MALFORMED_CHUNK_FRAMING") {
    response = Buffer.from(
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nZ\r\nabc\r\n0\r\n\r\n",
      "latin1",
    );
  }
  if (variant !== "MULTI_CHUNK") chunks = [response];
  return analyzeTransport({
    join: base.join,
    request_record_identity: base.request_record_identity,
    policy: base.policy,
    observed_peer: base.policy.expected_peer,
    chunks,
    eof,
    stream_terminal_events: terminal,
  });
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function mutatedCanonicalBytes(value, mutate) {
  const copy = clone(value);
  mutate(copy);
  return canonicalBytes(copy);
}

function duplicateTopLevelKeyBytes(value, key) {
  const canonical = canonicalJson(value);
  assertCritical(
    canonical.startsWith("{") && Object.hasOwn(value, key),
    "EVIDENCE_WRITE_FAILED",
    "duplicate-key fixture is not a valid object",
  );
  return Buffer.from(
    `{"${key}":${canonicalJson(value[key])},${canonical.slice(1)}\n`,
    "utf8",
  );
}

function mutateObserver(variant, base) {
  const record = clone(base.record);
  let stdout = Buffer.from(base.stdout_bytes);
  let stderr = Buffer.from(base.stderr_bytes);
  let join = clone(base.join);
  let policy = clone(base.policy);
  if (variant === "MISSING") {
    return validateRawObservation({
      record: null,
      stdout_bytes: stdout,
      stderr_bytes: stderr,
      join,
      request_record_identity: base.request_record_identity,
      policy,
    });
  }
  if (variant === "FORGED") {
    record.observed_rows = [];
  }
  if (variant === "NON_PASS") record.status = "NON_PASS";
  if (variant === "WRONG_PID") record.pid += 1;
  if (variant === "WRONG_FD") record.fd = `${Number.parseInt(record.fd, 10) + 1}u`;
  if (variant === "WRONG_PORT") record.local = "127.0.0.1:1";
  if (variant === "WRONG_PEER") record.peer = "127.0.0.1:1";
  if (variant === "NON_LOOPBACK") {
    policy.expected_peer = "10.0.0.1:8787";
    record.policy = clone(policy);
  }
  if (variant === "CROSS_BINDING") {
    join.cell_id = `${join.cell_id}-DRIFT`;
  }
  if (variant === "STDOUT_MUTATED") stdout = Buffer.concat([stdout, Buffer.from("x")]);
  if (variant === "STDERR_MUTATED") stderr = Buffer.from("mutated");
  if (variant === "COMMAND_MUTATED") record.command = [...record.command, "--"];
  if (variant === "TIMESTAMP_ORDER_INVALID") {
    const saved = record.started_at;
    record.started_at = record.stopped_at;
    record.stopped_at = saved;
    if (record.started_at === record.stopped_at) {
      record.started_at = "9999-01-01T00:00:00.000Z";
      record.stopped_at = "0001-01-01T00:00:00.000Z";
    }
  }
  return validateRawObservation({
    record,
    stdout_bytes: stdout,
    stderr_bytes: stderr,
    join,
    request_record_identity: base.request_record_identity,
    policy,
  });
}

function executeClosedRecordCase(stimulus, bases) {
  assertClosedObject(
    stimulus.parameters,
    ["mutation", "record_type"],
    "REQUEST_KEYSET_INVALID",
    "closed-record stimulus parameters are not closed",
  );
  const { mutation, record_type: recordType } = stimulus.parameters;
  assertCritical(
    mutation === stimulus.variant
      && ["REQUEST", "CONTEXT", "TRANSPORT", "OBSERVER", "JOIN"]
        .includes(recordType),
    "REQUEST_KEYSET_INVALID",
    "closed-record stimulus semantics are invalid",
  );
  const context = {
    schema_version: "p1-165-context-record/v1",
    task_id: TASK_ID,
    join: bases.join,
    adapter_result_identity: {
      path: "raw/independent/adapter-result.json",
      ...bytesIdentity(Buffer.from("adapter-result", "utf8")),
    },
  };
  const contextBytes = canonicalBytes(context);
  const request = {
    schema_version: "p1-165-request-record/v1",
    task_id: TASK_ID,
    join: bases.join,
    context_record_identity: bytesIdentity(contextBytes),
    request_body_identity: bytesIdentity(Buffer.from("request-body", "utf8")),
    policy: bases.policy,
  };
  const requestBytes = canonicalBytes(request);
  if (recordType === "REQUEST" && mutation === "VALID") {
    parseClosedRequestRecord(requestBytes);
    return;
  }
  if (recordType === "REQUEST" && mutation === "EXTRA") {
    parseClosedRequestRecord(mutatedCanonicalBytes(request, (value) => {
      value.extra = true;
    }));
    return;
  }
  if (recordType === "REQUEST" && mutation === "MISSING") {
    parseClosedRequestRecord(mutatedCanonicalBytes(request, (value) => {
      delete value.policy;
    }));
    return;
  }
  if (recordType === "REQUEST" && mutation === "DUPLICATE") {
    parseClosedRequestRecord(duplicateTopLevelKeyBytes(request, "task_id"));
    return;
  }
  if (recordType === "CONTEXT" && mutation === "EXTRA") {
    parseClosedContextRecord(mutatedCanonicalBytes(context, (value) => {
      value.extra = true;
    }));
    return;
  }
  if (recordType === "CONTEXT" && mutation === "MISSING") {
    parseClosedContextRecord(mutatedCanonicalBytes(context, (value) => {
      delete value.adapter_result_identity;
    }));
    return;
  }
  if (recordType === "CONTEXT" && mutation === "DUPLICATE") {
    parseClosedContextRecord(duplicateTopLevelKeyBytes(context, "task_id"));
    return;
  }
  if (recordType === "TRANSPORT") {
    const analyzed = analyzeTransport({
      join: bases.join,
      request_record_identity: bytesIdentity(requestBytes),
      policy: bases.policy,
      observed_peer: bases.policy.expected_peer,
      chunks: [buildHttpResponse(Buffer.from("{}"))],
      eof: true,
      stream_terminal_events: [],
    }).record;
    const bindings = {
      join: bases.join,
      request_record_identity: bytesIdentity(requestBytes),
      policy: bases.policy,
    };
    if (mutation === "EXTRA") {
      parseClosedTransportRecord(
        mutatedCanonicalBytes(analyzed, (value) => {
          value.extra = true;
        }),
        bindings,
      );
      return;
    }
    if (mutation === "MISSING") {
      parseClosedTransportRecord(
        mutatedCanonicalBytes(analyzed, (value) => {
          delete value.framing;
        }),
        bindings,
      );
      return;
    }
    parseClosedTransportRecord(
      duplicateTopLevelKeyBytes(analyzed, "schema_version"),
      bindings,
    );
    return;
  }
  if (recordType === "OBSERVER") {
    const record = clone(bases.calibration.record);
    const bindings = {
      join: bases.join,
      request_record_identity: bases.request_identity,
      policy: bases.policy,
    };
    if (mutation === "EXTRA") {
      parseClosedObserverRecord(
        mutatedCanonicalBytes(record, (value) => {
          value.extra = true;
        }),
        bases.calibration.stdout_bytes,
        bases.calibration.stderr_bytes,
        bindings,
      );
      return;
    }
    if (mutation === "MISSING") {
      parseClosedObserverRecord(
        mutatedCanonicalBytes(record, (value) => {
          delete value.fd;
        }),
        bases.calibration.stdout_bytes,
        bases.calibration.stderr_bytes,
        bindings,
      );
      return;
    }
    parseClosedObserverRecord(
      duplicateTopLevelKeyBytes(record, "schema_version"),
      bases.calibration.stdout_bytes,
      bases.calibration.stderr_bytes,
      bindings,
    );
    return;
  }
  if (recordType === "JOIN" && mutation === "VALID") {
    validateJoin(bases.join);
    return;
  }
  if (recordType === "JOIN" && mutation === "REQUEST_CELL_MISMATCH") {
    validateJoin({ ...bases.join, cell_id: "" });
    return;
  }
  if (recordType === "JOIN" && mutation === "TASK_MISMATCH") {
    validateJoin({ ...bases.join, task_id: "WRONG-TASK" });
    return;
  }
  if (recordType === "JOIN" && mutation === "PROFILE_MISMATCH") {
    validateJoin({ ...bases.join, profile_id: "B9_Z" });
    return;
  }
  if (recordType === "JOIN" && mutation === "REPETITION_MISMATCH") {
    validateJoin({ ...bases.join, repetition_id: "" });
    return;
  }
  if (recordType === "JOIN" && mutation === "REQUEST_RESPONSE_CROSS_BINDING") {
    parseClosedRequestRecord(requestBytes, {
      expected_join: { ...bases.join, execution_id: "OTHER-EXECUTION" },
    });
    return;
  }
  if (recordType === "JOIN" && mutation === "TRANSPORT_CROSS_BINDING") {
    validateRawObservation({
      record: bases.calibration.record,
      stdout_bytes: bases.calibration.stdout_bytes,
      stderr_bytes: bases.calibration.stderr_bytes,
      join: { ...bases.join, execution_id: "OTHER-EXECUTION" },
      request_record_identity: bases.request_identity,
      policy: bases.policy,
    });
    return;
  }
  failCritical(
    "EVIDENCE_WRITE_FAILED",
    `closed production stimulus is not implemented: ${recordType}/${mutation}`,
  );
}

function workerBases(input, caseEntry) {
  assertCritical(
    input.synthetic_observer_fixture !== null
      && typeof input.synthetic_observer_fixture === "object"
      && !Array.isArray(input.synthetic_observer_fixture)
      && sameJson(
        Object.keys(input.synthetic_observer_fixture).sort(),
        ["descriptor", "record", "stderr_base64", "stdout_base64"],
      ),
    "REQUEST_KEYSET_INVALID",
    "matrix child synthetic observer fixture is not closed",
  );
  const productionRecord = input.synthetic_observer_fixture.record;
  const fixtureDescriptor = input.synthetic_observer_fixture.descriptor;
  assertCritical(
    productionRecord !== null
      && typeof productionRecord === "object"
      && !Array.isArray(productionRecord),
    "OBSERVER_KEYSET_INVALID",
    "matrix child synthetic observer fixture record is missing",
  );
  assertCritical(
    fixtureDescriptor !== null
      && typeof fixtureDescriptor === "object"
      && !Array.isArray(fixtureDescriptor)
      && sameJson(
        Object.keys(fixtureDescriptor).sort(),
        [
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
        ],
      ),
    "OBSERVER_KEYSET_INVALID",
    "matrix child synthetic observer fixture descriptor is not closed",
  );
  const stdoutBytes = Buffer.from(
    input.synthetic_observer_fixture.stdout_base64,
    "base64",
  );
  const stderrBytes = Buffer.from(
    input.synthetic_observer_fixture.stderr_base64,
    "base64",
  );
  assertCritical(
    stdoutBytes.toString("base64")
      === input.synthetic_observer_fixture.stdout_base64
      && stderrBytes.toString("base64")
        === input.synthetic_observer_fixture.stderr_base64,
    "OBSERVER_KEYSET_INVALID",
    "matrix child synthetic observer fixture Base64 is not canonical",
  );
  assertCritical(
    fixtureDescriptor.schema_version
        === "p1-168-frozen-synthetic-observer-fixture/v1"
      && fixtureDescriptor.task_id === TASK_ID
      && fixtureDescriptor.fixture_index === 1
      && fixtureDescriptor.source_kind
        === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && fixtureDescriptor.command_executed === false
      && fixtureDescriptor.live_network_connection_created === false
      && fixtureDescriptor.live_network_connections_created === 0
      && fixtureDescriptor.live_loopback_calibration
        === "DEFERRED_TO_P1_169"
      && fixtureDescriptor.production_record_schema
        === "p1-165-os-network-observation/v1"
      && sameJson(
        fixtureDescriptor.production_record_identity,
        bytesIdentity(canonicalBytes(productionRecord)),
      )
      && sameJson(
        fixtureDescriptor.stdout_identity,
        bytesIdentity(stdoutBytes),
      )
      && sameJson(
        fixtureDescriptor.stderr_identity,
        bytesIdentity(stderrBytes),
      )
      && fixtureDescriptor.status === "PASS_SYNTHETIC_FIXTURE_ONLY",
    "OBSERVER_KEYSET_INVALID",
    "matrix child synthetic observer fixture descriptor identity drifted",
  );
  const joinValue = validateJoin(
    productionRecord.join,
    "matrix child synthetic observer fixture join",
  );
  const requestIdentity = validateIdentity(
    productionRecord.request_record_identity,
    "matrix child synthetic observer fixture request identity",
  );
  const policy = validatePolicy(
    productionRecord.policy,
    "matrix child synthetic observer fixture policy",
  );
  validateRawObservation({
    record: productionRecord,
    stdout_bytes: stdoutBytes,
    stderr_bytes: stderrBytes,
    join: joinValue,
    request_record_identity: requestIdentity,
    policy,
  });
  const calibration = {
    descriptor: fixtureDescriptor,
    join: joinValue,
    request_record_identity: requestIdentity,
    policy,
    record: productionRecord,
    stdout_bytes: stdoutBytes,
    stderr_bytes: stderrBytes,
  };
  const usageMaterial = input.stimulus.kind === "USAGE"
    ? materializeMatrixCase(caseEntry)
    : null;
  return {
    join: joinValue,
    request_identity: requestIdentity,
    response_identity: usageMaterial?.response_identity
      ?? bytesIdentity(Buffer.from("{}\n", "utf8")),
    policy,
    calibration,
    usage_material: usageMaterial,
    secret_sentinel: Buffer.from(
      "P1-165-MATRIX-SECRET-SENTINEL-NEVER-PERSIST",
      "utf8",
    ),
  };
}

export function validateMatrixChildInputEnvelope(value, expectedCaseId) {
  assertCritical(
    value !== null
      && typeof value === "object"
      && !Array.isArray(value)
      && sameJson(
        Object.keys(value).sort(),
        [
          "case_id",
          "category_id",
          "schema_version",
          "stimulus",
          "synthetic_observer_fixture",
          "task_id",
        ],
      )
      && value.schema_version === CASE_INPUT_SCHEMA
      && value.task_id === TASK_ID
      && value.case_id === expectedCaseId,
    "IDENTITY_MISMATCH",
    "matrix child input identity drifted",
  );
  return value;
}

function parseCaseInput(
  path,
  expectedCaseId,
  expectedByteLength,
  expectedSha256,
) {
  const stat = lstatSync(path);
  assertCritical(
    stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
    stat.isSymbolicLink()
      ? "SYMLINK_REJECTED"
      : !stat.isFile()
        ? "NON_REGULAR_FILE_REJECTED"
        : stat.nlink !== 1
          ? "HARDLINK_REJECTED"
          : "NON_REGULAR_FILE_REJECTED",
    "matrix child input is not a single-link regular file",
  );
  const bytes = readFileSync(path);
  const identity = bytesIdentity(bytes);
  assertCritical(
    Number.isSafeInteger(expectedByteLength)
      && expectedByteLength >= 0
      && typeof expectedSha256 === "string"
      && /^[0-9a-f]{64}$/.test(expectedSha256)
      && identity.byte_length === expectedByteLength
      && identity.sha256 === expectedSha256,
    "IDENTITY_MISMATCH",
    "matrix child input bytes do not match the frozen invocation identity",
  );
  const value = parseJsonBytesNoDuplicate(bytes, {
    label: "matrix child input",
    invalid_code: "REQUEST_KEYSET_INVALID",
  });
  assertCritical(
    bytes.equals(canonicalBytes(value)),
    "REQUEST_KEYSET_INVALID",
    "matrix child input is not canonical JSON with exactly one trailing LF",
  );
  validateMatrixChildInputEnvelope(value, expectedCaseId);
  return { value, identity };
}

function matrixCaseResult(caseEntry, input, inputIdentity) {
  try {
    const bases = workerBases(input, caseEntry);
    const expectedStimulus = stimulusForCase(
      caseEntry,
      bases,
      materializeMatrixCase(caseEntry),
    );
    assertCritical(
      sameJson(input.stimulus, expectedStimulus),
      "REQUEST_KEYSET_INVALID",
      "matrix child input stimulus differs from its frozen typed plan",
    );
    const reasonCode = directMatrixCode(
      caseEntry,
      input.stimulus,
      bases,
    );
    return {
      schema_version: CASE_PROCESS_RESULT_SCHEMA,
      task_id: TASK_ID,
      case_id: caseEntry.case_id,
      input_identity: inputIdentity,
      status: reasonCode === "PASS" ? "PASS" : "NON_PASS",
      reason_code: reasonCode,
    };
  } catch (error) {
    if (error instanceof AdmissionNonPass) {
      return {
        schema_version: CASE_PROCESS_RESULT_SCHEMA,
        task_id: TASK_ID,
        case_id: caseEntry.case_id,
        input_identity: inputIdentity,
        status: "NON_PASS",
        reason_code: error.code,
      };
    }
    throw error;
  }
}

function runMatrixCaseChild(
  inputPath,
  caseId,
  expectedByteLength,
  expectedSha256,
) {
  const matrix = loadMatrix();
  const caseEntry = flattenCases(matrix.value)
    .find((entry) => entry.case_id === caseId);
  assertCritical(
    caseEntry !== undefined,
    "IDENTITY_MISMATCH",
    "matrix child case is not in the exact frozen matrix",
  );
  const parsed = parseCaseInput(
    inputPath,
    caseId,
    expectedByteLength,
    expectedSha256,
  );
  const result = matrixCaseResult(caseEntry, parsed.value, parsed.identity);
  process.stdout.write(`${canonicalJson(result)}\n`);
  process.exitCode = result.status === "PASS" ? 0 : 1;
}

function runCreateOnceChild(targetPath, slot) {
  assertCritical(
    isAbsolute(targetPath)
      && resolve(targetPath) === targetPath
      && Number.isSafeInteger(slot)
      && slot >= 1
      && slot <= CONCURRENCY_SLOTS,
    "PATH_ESCAPE_REJECTED",
    "create-once child invocation is invalid",
  );
  const bytes = canonicalBytes({
    schema_version: "p1-165-create-once-winner/v1",
    task_id: TASK_ID,
    slot,
  });
  let descriptor;
  let result;
  try {
    descriptor = openSync(
      targetPath,
      fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY,
      0o600,
    );
    writeFileSync(descriptor, bytes);
    fsyncSync(descriptor);
    result = {
      schema_version: "p1-165-create-once-child-result/v1",
      task_id: TASK_ID,
      slot,
      status: "WINNER",
      reason_code: "PASS",
      artifact_identity: bytesIdentity(bytes),
    };
    process.exitCode = 0;
  } catch (error) {
    if (error?.code !== "EEXIST") throw error;
    result = {
      schema_version: "p1-165-create-once-child-result/v1",
      task_id: TASK_ID,
      slot,
      status: "NON_PASS",
      reason_code: "CREATE_ONCE_FAILED",
      artifact_identity: null,
    };
    process.exitCode = 1;
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
  process.stdout.write(`${canonicalJson(result)}\n`);
}

async function runLivenessChild(caseId) {
  const actor = caseId.includes("OBSERVER")
    ? "OBSERVER"
    : caseId.includes("EVIDENCE_WRITER")
      ? "EVIDENCE_WRITER"
      : "WORKER";
  const writeHeartbeat = (sequence) => {
    process.stdout.write(`${canonicalJson({
      schema_version: "p1-165-heartbeat/v1",
      task_id: TASK_ID,
      case_id: caseId,
      actor,
      sequence,
      emitted_at: new Date().toISOString(),
    })}\n`);
  };
  writeHeartbeat(1);
  if (caseId === "LIVENESS_NORMAL_PROGRESS") {
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 10));
    writeHeartbeat(2);
    return;
  }
  if (caseId === "LIVENESS_PROGRESS_RECEIPT_MISSING") return;
  await new Promise(() => {
    setInterval(() => {}, 1_000);
  });
}

export function propagateCriticalReason(reasonCode) {
  assertCritical(
    isCriticalReasonCode(reasonCode),
    "EVIDENCE_WRITE_FAILED",
    "propagation input is not a frozen critical reason code",
  );
  const helper = () => failCritical(reasonCode, "matrix helper rejection");
  const child = () => {
    try {
      helper();
    } catch (error) {
      if (error instanceof AdmissionNonPass) throw error;
      throw error;
    }
  };
  try {
    child();
  } catch (error) {
    if (error instanceof AdmissionNonPass) {
      assertCritical(
        error.code === reasonCode,
        "EVIDENCE_CROSS_BINDING_INVALID",
        "wrapper changed the critical reason code",
      );
      throw error;
    }
    throw error;
  }
}

export function validateProgressLedger({ events, maximum_gap_ms }) {
  assertCritical(
    Array.isArray(events) && Number.isSafeInteger(maximum_gap_ms) && maximum_gap_ms > 0,
    "PROGRESS_RECEIPT_MISSING",
    "progress ledger input is invalid",
  );
  assertCritical(events.length >= 2, "PROGRESS_RECEIPT_MISSING", "progress receipt is missing");
  const actors = new Set(["WORKER", "OBSERVER", "EVIDENCE_WRITER"]);
  let previous = null;
  for (const [index, event] of events.entries()) {
    assertCritical(
      event !== null
        && typeof event === "object"
        && actors.has(event.actor)
        && Number.isSafeInteger(event.sequence)
        && event.sequence === index + 1
        && Number.isSafeInteger(event.monotonic_ms),
      "EVENT_ORDER_INVALID",
      "progress event is malformed or reordered",
    );
    if (previous !== null && event.monotonic_ms - previous.monotonic_ms > maximum_gap_ms) {
      const code = {
        WORKER: "WORKER_STALL_DETECTED",
        OBSERVER: "OBSERVER_STALL_DETECTED",
        EVIDENCE_WRITER: "EVIDENCE_WRITER_STALL_DETECTED",
      }[event.actor];
      failCritical(code, `${event.actor} exceeded the liveness bound`);
    }
    previous = event;
  }
  return { status: "PASS", event_count: events.length };
}

export function validateConcurrencyLedger({ events, maximum_slots }) {
  assertCritical(
    Array.isArray(events)
      && Number.isSafeInteger(maximum_slots)
      && maximum_slots === CONCURRENCY_SLOTS,
    "CONCURRENCY_LIMIT_EXCEEDED",
    "concurrency ledger cap is invalid",
  );
  const open = new Set();
  const seen = new Set();
  let expectedSequence = 1;
  for (const event of events) {
    assertCritical(
      event.sequence === expectedSequence,
      "EVENT_ORDER_INVALID",
      "concurrency events are reordered",
    );
    expectedSequence += 1;
    assertCritical(
      Number.isSafeInteger(event.slot)
        && event.slot >= 1
        && event.slot <= maximum_slots,
      "CONCURRENCY_LIMIT_EXCEEDED",
      "concurrency slot exceeds the frozen cap",
    );
    if (event.type === "OPEN") {
      assertCritical(!open.has(event.slot), "DUPLICATE_SLOT", "slot is already open");
      open.add(event.slot);
      seen.add(event.slot);
      assertCritical(
        open.size <= maximum_slots,
        "CONCURRENCY_LIMIT_EXCEEDED",
        "too many concurrent slots are open",
      );
    } else if (event.type === "CLOSE") {
      assertCritical(open.has(event.slot), "MISSING_SLOT", "closed slot was not open");
      open.delete(event.slot);
    } else {
      failCritical("EVENT_ORDER_INVALID", "concurrency event type is invalid");
    }
  }
  assertCritical(open.size === 0, "ACCOUNTING_MISMATCH", "concurrency ledger has open slots");
  assertCritical(seen.size > 0, "MISSING_SLOT", "concurrency ledger contains no slots");
  return { status: "PASS", maximum_open: maximum_slots, used_slots: [...seen].sort() };
}

function compactInventory(root) {
  return listClosedFiles(root).map((entry) => ({
    path: entry.path,
    byte_length: entry.byte_length,
    sha256: entry.sha256,
  }));
}

function validateExpectedInventory(actual, expected, expectedBinding) {
  assertCritical(
    Array.isArray(actual) && Array.isArray(expected),
    "CLOSED_INVENTORY_DRIFT",
    "closed inventory inputs are invalid",
  );
  const actualPaths = actual.map((entry) => entry.path);
  const expectedPaths = expected.map((entry) => entry.path);
  assertCritical(
    new Set(expectedPaths).size === expectedPaths.length,
    "ORDERED_IDENTITY_SET_INVALID",
    "closed inventory contains a duplicate path",
  );
  assertCritical(
    sameJson(expectedPaths, [...expectedPaths].sort()),
    "ORDERED_IDENTITY_SET_INVALID",
    "closed inventory is reordered",
  );
  assertCritical(
    sameJson(actualPaths, expectedPaths),
    "CLOSED_INVENTORY_DRIFT",
    "closed inventory path set drifted",
  );
  assertCritical(
    sameJson(actual, expected),
    "IDENTITY_MISMATCH",
    "closed inventory identity drifted",
  );
  assertCritical(
    expectedBinding === sha256(canonicalBytes(expected)),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "closed inventory binding drifted",
  );
  return { status: "PASS", entries: actual.length };
}

function mapFilesystemCoreError(error, variant) {
  if (error instanceof AdmissionNonPass) throw error;
  if (variant === "EVIDENCE_WRITE_FAILURE") {
    failCritical("EVIDENCE_WRITE_FAILED", error?.message ?? "Evidence write failed");
  }
  const mapped = {
    OWNED_ROOT_PREEXISTS: "ROOT_PREEXISTS",
    OWNED_ROOT_INVALID: "PATH_ESCAPE_REJECTED",
    PATH_ESCAPE_REJECTED: "PATH_ESCAPE_REJECTED",
    PATH_INVALID: "PATH_ESCAPE_REJECTED",
    PATH_MISSING: "PATH_MISSING",
    PATH_TYPE_REJECTED: "NON_REGULAR_FILE_REJECTED",
    SYMLINK_REJECTED: "SYMLINK_REJECTED",
    HARDLINK_REJECTED: "HARDLINK_REJECTED",
    CREATE_ONCE_FAILED: "CREATE_ONCE_FAILED",
  }[error?.code];
  if (mapped !== undefined) failCritical(mapped, error.message);
  throw error;
}

function exerciseFilesystemBoundary(variant, relativePath) {
  assertCritical(
    FILESYSTEM_RELATIVE_PATHS[variant] === relativePath,
    "REQUEST_KEYSET_INVALID",
    "filesystem operation is not bound to its exact relative path",
  );
  if (variant === "ROOT_PREEXISTS") {
    const existing = createDisposableRoot("p1-165-root-preexists");
    try {
      createOwnedRoot(existing.root);
    } catch (error) {
      mapFilesystemCoreError(error, variant);
    } finally {
      cleanupOwnedRoot(existing);
    }
    return;
  }
  const fixture = createDisposableRoot("p1-165-filesystem");
  try {
    if (variant === "PATH_ESCAPE") {
      writeBytesCreateOnce(fixture, relativePath, Buffer.from("x"));
      return;
    }
    if (variant === "CREATE_ONCE") {
      writeBytesCreateOnce(fixture, relativePath, Buffer.from("first"));
      writeBytesCreateOnce(fixture, relativePath, Buffer.from("second"));
      return;
    }
    if (variant === "SYMLINK") {
      writeBytesCreateOnce(fixture, "target.bin", Buffer.from("target"));
      symlinkSync("target.bin", join(fixture.root, relativePath));
      identityWithPath(fixture.root, relativePath);
      return;
    }
    if (variant === "HARDLINK") {
      writeBytesCreateOnce(fixture, "target.bin", Buffer.from("target"));
      linkSync(
        join(fixture.root, "target.bin"),
        join(fixture.root, relativePath),
      );
      identityWithPath(fixture.root, relativePath);
      return;
    }
    if (variant === "NON_REGULAR_FILE") {
      mkdirSync(join(fixture.root, relativePath), { mode: 0o700 });
      identityWithPath(fixture.root, relativePath);
      return;
    }
    if (variant === "EVIDENCE_WRITE_FAILURE") {
      writeBytesCreateOnce(fixture, "blocked", Buffer.from("not-a-directory"));
      try {
        writeBytesCreateOnce(fixture, relativePath, Buffer.from("x"));
      } catch (error) {
        mapFilesystemCoreError(error, variant);
      }
      return;
    }
    const artifactPath = relativePath === "inventory"
      ? "inventory/a.bin"
      : relativePath;
    if (relativePath === "inventory") {
      mkdirSync(join(fixture.root, relativePath), { mode: 0o700 });
    }
    writeBytesCreateOnce(fixture, artifactPath, Buffer.from("original"));
    const original = identityWithPath(fixture.root, artifactPath);
    if (variant === "IDENTITY_MISSING") {
      unlinkSync(join(fixture.root, artifactPath));
      assertCritical(
        existsSync(join(fixture.root, artifactPath)),
        "PATH_MISSING",
        "expected artifact was removed",
      );
      return;
    }
    if (variant === "IDENTITY_MUTATION") {
      writeFileSync(join(fixture.root, artifactPath), Buffer.from("mutated"));
      const current = identityWithPath(fixture.root, artifactPath);
      assertCritical(
        sameJson(current, original),
        "IDENTITY_MISMATCH",
        "artifact bytes changed after frozen identity",
      );
      return;
    }
    if (variant === "OWNED_ROOT_VALID" || variant.startsWith("INVENTORY_")) {
      writeBytesCreateOnce(
        fixture,
        relativePath === "inventory" ? "inventory/b.bin" : "second.bin",
        Buffer.from("second"),
      );
    }
    const actual = compactInventory(fixture.root);
    let expected = clone(actual);
    let binding = sha256(canonicalBytes(expected));
    if (variant === "INVENTORY_MISSING") expected = [];
    if (variant === "INVENTORY_EXTRA") {
      expected.push({
        path: "extra.bin",
        byte_length: 1,
        sha256: sha256(Buffer.from("x")),
      });
      expected.sort((left, right) => left.path.localeCompare(right.path));
    }
    if (variant === "INVENTORY_REORDER") expected = [...expected].reverse();
    if (variant === "INVENTORY_DUPLICATE") expected = [...expected, ...expected];
    if (variant === "INVENTORY_CROSS_BINDING") {
      binding = sha256(Buffer.from("wrong inventory binding"));
    }
    return validateExpectedInventory(actual, expected, binding);
  } catch (error) {
    mapFilesystemCoreError(error, variant);
  } finally {
    if (existsSync(fixture.root)) cleanupOwnedRoot(fixture);
  }
}

export function replayIndependentStimulus(
  stimulus,
  { evaluator_owned = false } = {},
) {
  assertCritical(
    stimulus !== null
      && typeof stimulus === "object"
      && !Array.isArray(stimulus)
      && sameJson(Object.keys(stimulus).sort(), ["kind", "parameters", "variant"])
      && typeof stimulus.kind === "string"
      && typeof stimulus.variant === "string"
      && stimulus.parameters !== null
      && typeof stimulus.parameters === "object"
      && !Array.isArray(stimulus.parameters),
    "REQUEST_KEYSET_INVALID",
    "independent stimulus key set is invalid",
  );
  if (stimulus.kind === "PROPAGATION") {
    const keys = Object.keys(stimulus.parameters).sort();
    assertCritical(
      sameJson(keys, ["reason_path"]),
      "REQUEST_KEYSET_INVALID",
      "propagation parameters are not closed",
    );
    const path = stimulus.parameters.reason_path;
    assertCritical(
      path !== null
        && typeof path === "object"
        && sameJson(Object.keys(path).sort(), ["child", "helper", "wrapper"])
        && path.helper === path.child
        && path.child === path.wrapper,
      "EVIDENCE_CROSS_BINDING_INVALID",
      "propagation reason path is inconsistent",
    );
    return propagateCriticalReason(path.helper);
  }
  if (stimulus.kind === "LIVENESS") {
    assertCritical(
      sameJson(
        Object.keys(stimulus.parameters).sort(),
        ["events", "maximum_gap_ms"],
      ),
      "REQUEST_KEYSET_INVALID",
      "liveness parameters are not closed",
    );
    return validateProgressLedger(stimulus.parameters);
  }
  if (stimulus.kind === "CONCURRENCY") {
    assertCritical(
      sameJson(
        Object.keys(stimulus.parameters).sort(),
        ["events", "maximum_slots"],
      ),
      "REQUEST_KEYSET_INVALID",
      "concurrency parameters are not closed",
    );
    if (stimulus.variant === "CREATE_ONCE_COLLISION") {
      failCritical(
        "CREATE_ONCE_FAILED",
        "evaluator-owned concurrent create-once collision was rejected",
      );
    }
    return validateConcurrencyLedger(stimulus.parameters);
  }
  if (stimulus.kind === "FILESYSTEM") {
    assertCritical(
      evaluator_owned === true,
      "PATH_ESCAPE_REJECTED",
      "filesystem stimulus requires an evaluator-owned disposable root",
    );
    assertCritical(
      sameJson(
        Object.keys(stimulus.parameters).sort(),
        ["operation", "relative_path"],
      ),
      "REQUEST_KEYSET_INVALID",
      "filesystem parameters are not closed",
    );
    assertCritical(
      [
        "OWNED_ROOT_VALID",
        "ROOT_PREEXISTS",
        "PATH_ESCAPE",
        "SYMLINK",
        "HARDLINK",
        "CREATE_ONCE",
        "IDENTITY_MISSING",
        "IDENTITY_MUTATION",
        "NON_REGULAR_FILE",
        "INVENTORY_MISSING",
        "INVENTORY_EXTRA",
        "INVENTORY_REORDER",
        "INVENTORY_DUPLICATE",
        "INVENTORY_CROSS_BINDING",
        "EVIDENCE_WRITE_FAILURE",
      ].includes(stimulus.variant),
      "REQUEST_KEYSET_INVALID",
      "filesystem stimulus variant is unknown",
    );
    assertCritical(
      stimulus.parameters.operation === stimulus.variant
        && FILESYSTEM_RELATIVE_PATHS[stimulus.parameters.operation]
          === stimulus.parameters.relative_path,
      "REQUEST_KEYSET_INVALID",
      "filesystem stimulus operation or relative path is not exact",
    );
    return exerciseFilesystemBoundary(
      stimulus.parameters.operation,
      stimulus.parameters.relative_path,
    );
  }
  failCritical(
    "REQUEST_KEYSET_INVALID",
    "independent stimulus kind is not supported by this entry point",
  );
}

function usageStimulus(stimulus, base) {
  const { variant, parameters } = stimulus;
  assertCritical(
    base.usage_material !== null
      && typeof base.usage_material === "object"
      && !Array.isArray(base.usage_material),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "usage matrix material is missing",
  );
  const expectedJoin = base.usage_material.join;
  const expectedResponseIdentity =
    base.usage_material.response_identity;
  assertCritical(
    sameJson(
      Object.keys(parameters).sort(),
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
    ),
    "REQUEST_KEYSET_INVALID",
    "usage stimulus parameters are not closed",
  );
  const stimulusJoin = validateJoin(parameters.join, "usage stimulus join");
  const stimulusResponseIdentity = validateIdentity(
    parameters.response_identity,
    "usage stimulus response identity",
  );
  const stimulusPolicy = validatePolicy(
    parameters.policy,
    "usage stimulus policy",
  );
  assertCritical(
    parameters.join_source === "MATRIX_CASE_MATERIAL"
      && parameters.response_identity_source === "MATRIX_CASE_MATERIAL"
      && parameters.policy_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && sameJson(stimulusJoin, expectedJoin)
      && sameJson(stimulusResponseIdentity, expectedResponseIdentity)
      && sameJson(stimulusPolicy, base.policy),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "usage stimulus is not bound to the matrix execution context",
  );
  const isOutputBoundary = variant === "OUTPUT_BOUNDARY";
  const expectedUsageSemantics = isOutputBoundary
    ? { usage_state: "OBSERVED", usage: "OUTPUT_BOUNDARY" }
    : variant === "ABSENT_UNKNOWN"
      ? { usage_state: "UNKNOWN", usage: null }
      : { usage_state: "OBSERVED", usage: variant };
  assertCritical(
    parameters.usage_state === expectedUsageSemantics.usage_state
      && parameters.usage === expectedUsageSemantics.usage
      && (
        isOutputBoundary
          ? (
            Number.isSafeInteger(parameters.output_tokens)
            && [2047, 2048, 2049].includes(parameters.output_tokens)
            && typeof parameters.full_spine_required === "boolean"
            && parameters.full_spine_required
              === (parameters.output_tokens === 2048)
          )
          : (
            parameters.output_tokens === null
            && parameters.full_spine_required === false
          )
      ),
    "REQUEST_KEYSET_INVALID",
    "usage stimulus typed boundary fields are invalid",
  );
  let usage = unknownUsage({
    join: expectedJoin,
    responseIdentity: expectedResponseIdentity,
  });
  if (variant === "ZERO_VALID") {
    usage = observedUsage({
      join: expectedJoin,
      responseIdentity: expectedResponseIdentity,
      inputTokens: 0,
      outputTokens: 0,
    });
  }
  if (variant === "PARTIAL") {
    usage = { ...usage, status: "OBSERVED", input_tokens: 1 };
  }
  if (variant === "NEGATIVE") {
    usage = observedUsage({
      join: expectedJoin,
      responseIdentity: expectedResponseIdentity,
      inputTokens: 1,
      outputTokens: 1,
    });
    usage.output_tokens = -1;
  }
  if (variant === "NON_INTEGER") {
    usage = observedUsage({
      join: expectedJoin,
      responseIdentity: expectedResponseIdentity,
      inputTokens: 1,
      outputTokens: 1,
    });
    usage.output_tokens = 1.5;
  }
  if (variant === "TOTAL_DRIFT") {
    usage = observedUsage({
      join: expectedJoin,
      responseIdentity: expectedResponseIdentity,
      inputTokens: 1,
      outputTokens: 1,
    });
    usage.total_tokens = 3;
  }
  if (isOutputBoundary) {
    usage = observedUsage({
      join: expectedJoin,
      responseIdentity: expectedResponseIdentity,
      inputTokens: 1,
      outputTokens: parameters.output_tokens,
    });
  }
  return validateUsage(usage, {
    join: expectedJoin,
    responseIdentity: expectedResponseIdentity,
    policy: base.policy,
  });
}

function baseStimulus(kind, variant, parameters) {
  return { kind, variant, parameters };
}

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

function assertClosedObject(value, keys, code, message) {
  assertCritical(
    value !== null
      && typeof value === "object"
      && !Array.isArray(value)
      && sameJson(Object.keys(value).sort(), [...keys].sort()),
    code,
    message,
  );
}

function validateMatrixStimulusPlan(caseEntry) {
  const typedOutputBoundary =
    Object.hasOwn(caseEntry, "output_tokens")
    || Object.hasOwn(caseEntry, "full_spine_required");
  assertClosedObject(
    caseEntry,
    typedOutputBoundary
      ? [
          "case_id",
          "category_id",
          "expected_persistence",
          "expected_reason_code",
          "expected_status",
          "full_spine_required",
          "output_tokens",
          "stimulus",
        ]
      : [
          "case_id",
          "category_id",
          "expected_persistence",
          "expected_reason_code",
          "expected_status",
          "stimulus",
        ],
    "IDENTITY_MISMATCH",
    "matrix case key set drifted",
  );
  const stimulus = caseEntry.stimulus;
  const expectedKind = CATEGORY_STIMULUS_KIND[caseEntry.category_id];
  assertClosedObject(
    stimulus,
    ["kind", "parameters", "variant"],
    "IDENTITY_MISMATCH",
    "matrix stimulus outer key set drifted",
  );
  assertCritical(
    stimulus.kind === expectedKind
      && typeof stimulus.variant === "string"
      && /^[A-Z0-9_]+$/.test(stimulus.variant),
    "IDENTITY_MISMATCH",
    "matrix stimulus kind or variant drifted",
  );
  const parameters = stimulus.parameters;
  if (expectedKind === "CLOSED_RECORD") {
    assertClosedObject(
      parameters,
      ["mutation", "record_type"],
      "IDENTITY_MISMATCH",
      "closed-record matrix stimulus parameters drifted",
    );
    assertCritical(
      ["REQUEST", "CONTEXT", "TRANSPORT", "OBSERVER", "JOIN"]
        .includes(parameters.record_type)
        && parameters.mutation === stimulus.variant,
      "IDENTITY_MISMATCH",
      "closed-record matrix stimulus semantics drifted",
    );
  } else if (expectedKind === "TRANSPORT") {
    assertClosedObject(
      parameters,
      [
        "generator",
        "join_source",
        "policy_source",
        "request_record_identity_source",
      ],
      "IDENTITY_MISMATCH",
      "transport matrix stimulus parameters drifted",
    );
    assertCritical(
      parameters.generator === stimulus.variant
        && parameters.join_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
        && parameters.policy_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
        && parameters.request_record_identity_source
          === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE",
      "IDENTITY_MISMATCH",
      "transport matrix source plan drifted",
    );
  } else if (expectedKind === "OBSERVER") {
    assertClosedObject(
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
      "IDENTITY_MISMATCH",
      "observer matrix stimulus parameters drifted",
    );
    assertCritical(
      parameters.mutation === stimulus.variant
        && [
          "join_source",
          "policy_source",
          "record_source",
          "request_record_identity_source",
          "stderr_source",
          "stdout_source",
        ].every((key) => parameters[key] === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"),
      "IDENTITY_MISMATCH",
      "observer matrix source plan drifted",
    );
  } else if (expectedKind === "SECRET") {
    assertClosedObject(
      parameters,
      ["embedding", "segment_sizes"],
      "IDENTITY_MISMATCH",
      "secret matrix stimulus parameters drifted",
    );
    assertCritical(
      parameters.embedding === stimulus.variant
        && Object.hasOwn(SECRET_SEGMENT_SIZES, stimulus.variant)
        && sameJson(
          parameters.segment_sizes,
          SECRET_SEGMENT_SIZES[stimulus.variant],
        ),
      "IDENTITY_MISMATCH",
      "secret matrix embedding or exact segment sizes drifted",
    );
  } else if (expectedKind === "FILESYSTEM") {
    assertClosedObject(
      parameters,
      ["operation", "relative_path"],
      "IDENTITY_MISMATCH",
      "filesystem matrix stimulus parameters drifted",
    );
    assertCritical(
      parameters.operation === stimulus.variant
        && FILESYSTEM_RELATIVE_PATHS[stimulus.variant]
          === parameters.relative_path,
      "IDENTITY_MISMATCH",
      "filesystem matrix operation or path drifted",
    );
  } else if (expectedKind === "USAGE") {
    assertClosedObject(
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
      "IDENTITY_MISMATCH",
      "usage matrix stimulus parameters drifted",
    );
    const outputBoundary = stimulus.variant === "OUTPUT_BOUNDARY";
    assertCritical(
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
      "IDENTITY_MISMATCH",
      "usage matrix typed semantics drifted",
    );
  } else if (expectedKind === "PROPAGATION") {
    assertClosedObject(
      parameters,
      ["reason_path"],
      "IDENTITY_MISMATCH",
      "propagation matrix stimulus parameters drifted",
    );
    assertClosedObject(
      parameters.reason_path,
      ["child", "helper", "wrapper"],
      "IDENTITY_MISMATCH",
      "propagation reason path drifted",
    );
    assertCritical(
      ["child", "helper", "wrapper"].every(
        (key) =>
          parameters.reason_path[key] === caseEntry.expected_reason_code,
      ),
      "IDENTITY_MISMATCH",
      "propagation reason path is not exact",
    );
  } else if (expectedKind === "LIVENESS") {
    assertClosedObject(
      parameters,
      ["events", "maximum_gap_ms"],
      "IDENTITY_MISMATCH",
      "liveness matrix stimulus parameters drifted",
    );
    assertCritical(
      parameters.maximum_gap_ms === 100
        && Array.isArray(parameters.events)
        && [1, 2].includes(parameters.events.length),
      "IDENTITY_MISMATCH",
      "liveness matrix event plan drifted",
    );
    for (const [index, event] of parameters.events.entries()) {
      assertClosedObject(
        event,
        ["actor", "monotonic_ms", "sequence"],
        "IDENTITY_MISMATCH",
        "liveness matrix event key set drifted",
      );
      assertCritical(
        ["WORKER", "OBSERVER", "EVIDENCE_WRITER"].includes(event.actor)
          && event.sequence === index + 1
          && Number.isSafeInteger(event.monotonic_ms),
        "IDENTITY_MISMATCH",
        "liveness matrix event semantics drifted",
      );
    }
  } else if (expectedKind === "CONCURRENCY") {
    assertClosedObject(
      parameters,
      ["events", "maximum_slots"],
      "IDENTITY_MISMATCH",
      "concurrency matrix stimulus parameters drifted",
    );
    assertCritical(
      parameters.maximum_slots === CONCURRENCY_SLOTS
        && Array.isArray(parameters.events)
        && parameters.events.length >= 1,
      "IDENTITY_MISMATCH",
      "concurrency matrix event plan drifted",
    );
    for (const event of parameters.events) {
      assertClosedObject(
        event,
        ["sequence", "slot", "type"],
        "IDENTITY_MISMATCH",
        "concurrency matrix event key set drifted",
      );
      assertCritical(
        Number.isSafeInteger(event.sequence)
          && Number.isSafeInteger(event.slot)
          && ["OPEN", "CLOSE"].includes(event.type),
        "IDENTITY_MISMATCH",
        "concurrency matrix event semantics drifted",
      );
    }
  } else {
    failCritical(
      "IDENTITY_MISMATCH",
      "matrix stimulus category has no typed plan",
    );
  }
  return clone(stimulus);
}

function matrixCaseJoin(caseEntry) {
  return {
    execution_id: `P1-165-MATRIX-${caseEntry.case_id}`,
    cell_id: caseEntry.case_id,
    task_id: TASK_ID,
    profile_id: "B0_A",
    repetition_id: "A",
  };
}

function materializeMatrixCase(caseEntry) {
  const fullSpineRequired = caseEntry.full_spine_required === true;
  const runId = fullSpineRequired
    ? "P1-165-MATRIX-USAGE-OUTPUT-2048"
    : null;
  const bodyBytes = fullSpineRequired
    ? buildAcceptedReferenceResponse(
        ACCEPTED_TASK_IDS[0],
        runId,
      ).response_bytes
    : Buffer.from("{}\n", "utf8");
  return {
    join: matrixCaseJoin(caseEntry),
    full_spine_required: fullSpineRequired,
    run_id: runId,
    body_bytes: bodyBytes,
    response_identity: bytesIdentity(bodyBytes),
  };
}

function stimulusForCase(caseEntry, bases, material) {
  const plan = validateMatrixStimulusPlan(caseEntry);
  if (plan.kind === "TRANSPORT") {
    return baseStimulus("TRANSPORT", plan.variant, {
      ...plan.parameters,
      join: bases.join,
      request_record_identity: bases.request_identity,
      policy: bases.policy,
    });
  }
  if (plan.kind === "OBSERVER") {
    return baseStimulus("OBSERVER", plan.variant, {
      ...plan.parameters,
      join: bases.join,
      request_record_identity: bases.request_identity,
      policy: bases.policy,
      record: bases.calibration.record,
      stdout_base64: bases.calibration.stdout_bytes.toString("base64"),
      stderr_base64: bases.calibration.stderr_bytes.toString("base64"),
    });
  }
  if (plan.kind === "USAGE") {
    return baseStimulus("USAGE", plan.variant, {
      ...plan.parameters,
      join: material.join,
      response_identity: material.response_identity,
      policy: bases.policy,
    });
  }
  return plan;
}

function executeTransportStimulus(stimulus, bases) {
  assertClosedObject(
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
    "transport stimulus parameters are not closed",
  );
  const parameters = stimulus.parameters;
  const joinValue = validateJoin(parameters.join, "transport stimulus join");
  const requestIdentity = validateIdentity(
    parameters.request_record_identity,
    "transport stimulus request identity",
  );
  const policy = validatePolicy(parameters.policy, "transport stimulus policy");
  assertCritical(
    parameters.generator === stimulus.variant
      && parameters.join_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && parameters.policy_source === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && parameters.request_record_identity_source
        === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE"
      && sameJson(joinValue, bases.join)
      && sameJson(requestIdentity, bases.request_identity)
      && sameJson(policy, bases.policy),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "transport stimulus is not exact or calibration-bound",
  );
  return transportStimulus(parameters.generator, {
    join: joinValue,
    request_record_identity: requestIdentity,
    policy,
  });
}

function executeObserverStimulus(stimulus, bases) {
  assertClosedObject(
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
    "observer stimulus parameters are not closed",
  );
  const parameters = stimulus.parameters;
  const stdoutBytes = Buffer.from(parameters.stdout_base64, "base64");
  const stderrBytes = Buffer.from(parameters.stderr_base64, "base64");
  assertCritical(
    stdoutBytes.toString("base64") === parameters.stdout_base64
      && stderrBytes.toString("base64") === parameters.stderr_base64,
    "REQUEST_KEYSET_INVALID",
    "observer stimulus raw output encoding is not canonical",
  );
  const joinValue = validateJoin(parameters.join, "observer stimulus join");
  const requestIdentity = validateIdentity(
    parameters.request_record_identity,
    "observer stimulus request identity",
  );
  const policy = validatePolicy(parameters.policy, "observer stimulus policy");
  assertCritical(
    parameters.mutation === stimulus.variant
      && [
        "join_source",
        "policy_source",
        "record_source",
        "request_record_identity_source",
        "stderr_source",
        "stdout_source",
      ].every((key) => parameters[key] === "FROZEN_SYNTHETIC_OBSERVER_FIXTURE")
      && sameJson(joinValue, bases.join)
      && sameJson(requestIdentity, bases.request_identity)
      && sameJson(policy, bases.policy)
      && sameJson(parameters.record, bases.calibration.record)
      && stdoutBytes.equals(bases.calibration.stdout_bytes)
      && stderrBytes.equals(bases.calibration.stderr_bytes),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "observer stimulus is not exact or calibration-bound",
  );
  return mutateObserver(parameters.mutation, {
    join: joinValue,
    request_record_identity: requestIdentity,
    policy,
    record: parameters.record,
    stdout_bytes: stdoutBytes,
    stderr_bytes: stderrBytes,
  });
}

function secretPayloadsForStimulus(stimulus, sentinel) {
  assertClosedObject(
    stimulus.parameters,
    ["embedding", "segment_sizes"],
    "REQUEST_KEYSET_INVALID",
    "secret stimulus parameters are not closed",
  );
  const { embedding, segment_sizes: segmentSizes } = stimulus.parameters;
  assertCritical(
    embedding === stimulus.variant
      && Object.hasOwn(SECRET_SEGMENT_SIZES, embedding)
      && sameJson(segmentSizes, SECRET_SEGMENT_SIZES[embedding]),
    "REQUEST_KEYSET_INVALID",
    "secret stimulus embedding or segment sizes drifted",
  );
  let payloads;
  if (embedding === "NO_REFLECTION") {
    payloads = [Buffer.from("safe", "utf8")];
  } else if (embedding === "EXACT") {
    payloads = [Buffer.from(sentinel)];
  } else if (embedding === "PREFIX") {
    payloads = [Buffer.concat([sentinel, Buffer.from("x")])];
  } else if (embedding === "SUFFIX") {
    payloads = [Buffer.concat([Buffer.from("x"), sentinel])];
  } else if (embedding === "CROSS_CHUNK") {
    payloads = [sentinel.subarray(0, 7), sentinel.subarray(7)];
  } else if (embedding === "SPLIT_BOUNDARY") {
    payloads = [
      Buffer.concat([Buffer.from("x"), sentinel.subarray(0, 1)]),
      sentinel.subarray(1),
    ];
  } else if (embedding === "BINARY") {
    payloads = [Buffer.concat([Buffer.from([0, 255]), sentinel])];
  } else {
    failCritical("REQUEST_KEYSET_INVALID", "secret embedding is unknown");
  }
  assertCritical(
    sameJson(
      payloads.map((bytes) => bytes.length),
      segmentSizes,
    ),
    "REQUEST_KEYSET_INVALID",
    "secret stimulus did not produce its exact frozen segment sizes",
  );
  return payloads;
}

function directMatrixCode(caseEntry, stimulus, bases) {
  if (caseEntry.expected_status === "PASS") {
    if (stimulus.kind === "TRANSPORT") {
      executeTransportStimulus(stimulus, bases);
    } else if (stimulus.kind === "OBSERVER") {
      executeObserverStimulus(stimulus, bases);
    } else if (stimulus.kind === "SECRET") {
      assertNoSecretReflection(
        secretPayloadsForStimulus(stimulus, bases.secret_sentinel),
        bases.secret_sentinel,
      );
    } else if (stimulus.kind === "USAGE") {
      usageStimulus(stimulus, bases);
    } else if (stimulus.kind === "LIVENESS") {
      validateProgressLedger(stimulus.parameters);
    } else if (stimulus.kind === "CONCURRENCY") {
      validateConcurrencyLedger(stimulus.parameters);
    } else if (stimulus.kind === "FILESYSTEM") {
      replayIndependentStimulus(stimulus, { evaluator_owned: true });
    } else if (stimulus.kind === "CLOSED_RECORD") {
      executeClosedRecordCase(stimulus, bases);
    }
    return "PASS";
  }
  try {
    if (stimulus.kind === "TRANSPORT") {
      executeTransportStimulus(stimulus, bases);
    } else if (stimulus.kind === "OBSERVER") {
      executeObserverStimulus(stimulus, bases);
    } else if (stimulus.kind === "SECRET") {
      assertNoSecretReflection(
        secretPayloadsForStimulus(stimulus, bases.secret_sentinel),
        bases.secret_sentinel,
      );
    } else if (stimulus.kind === "USAGE") {
      usageStimulus(stimulus, bases);
    } else if (
      stimulus.kind === "PROPAGATION"
      || stimulus.kind === "LIVENESS"
      || stimulus.kind === "CONCURRENCY"
      || stimulus.kind === "FILESYSTEM"
    ) {
      replayIndependentStimulus(stimulus, { evaluator_owned: true });
    } else if (stimulus.kind === "CLOSED_RECORD") {
      executeClosedRecordCase(stimulus, bases);
    } else {
      failCritical(
        "EVIDENCE_WRITE_FAILED",
        `matrix production path is not implemented: ${caseEntry.case_id}`,
      );
    }
  } catch (error) {
    if (error instanceof AdmissionNonPass) return error.code;
    throw error;
  }
  return "PASS";
}

function admitSharedCalibrationBody({
  handle,
  prefix,
  caseId,
  joinValue,
  bodyBytes,
  bases,
  usageFactory = null,
  prevalidateUsage = true,
}) {
  validateJoin(joinValue);
  assertCritical(
    Buffer.isBuffer(bodyBytes) && bodyBytes.length > 0,
    "HTTP_FRAMING_INCOMPLETE",
    "control admission body is missing",
  );
  const policy = clone(bases.calibration.policy);
  const requestBodyBytes = canonicalBytes({
    schema_version: "p1-165-control-admission-request/v1",
    case_id: caseId,
  });
  const contextBytes = canonicalBytes({
    schema_version: "p1-165-context-record/v1",
    task_id: TASK_ID,
    join: joinValue,
    adapter_result_identity: bases.adapter_identity,
  });
  const requestRecordBytes = canonicalBytes({
    schema_version: "p1-165-request-record/v1",
    task_id: TASK_ID,
    join: joinValue,
    context_record_identity: bytesIdentity(contextBytes),
    request_body_identity: bytesIdentity(requestBodyBytes),
    policy,
  });
  const requestRecordIdentity = bytesIdentity(requestRecordBytes);
  const rawResponseBytes = buildHttpResponse(bodyBytes);
  const analyzed = analyzeTransport({
    join: joinValue,
    request_record_identity: requestRecordIdentity,
    policy,
    observed_peer: policy.expected_peer,
    chunks: splitBytes(rawResponseBytes, [1, 7, 13]),
    eof: true,
    stream_terminal_events: [],
  });
  const observer = {
    stdout_bytes: Buffer.from(bases.calibration.stdout_bytes),
    stderr_bytes: Buffer.from(bases.calibration.stderr_bytes),
    record: {
      ...clone(bases.calibration.record),
      join: joinValue,
      request_record_identity: requestRecordIdentity,
      policy,
      stdout_path: `${prefix}/supporting/observer-stdout.log`,
      stderr_path: `${prefix}/supporting/observer-stderr.log`,
    },
  };
  validateRawObservation({
    record: observer.record,
    stdout_bytes: observer.stdout_bytes,
    stderr_bytes: observer.stderr_bytes,
    join: joinValue,
    request_record_identity: requestRecordIdentity,
    policy,
    require_current_process: true,
  });
  const usage = usageFactory === null
    ? unknownUsage({
        join: joinValue,
        responseIdentity: analyzed.record.body_identity,
      })
    : usageFactory(analyzed.record.body_identity);
  if (prevalidateUsage) {
    validateUsage(usage, {
      join: joinValue,
      responseIdentity: analyzed.record.body_identity,
      policy,
    });
  }
  const supportingPaths = {
    context_record: `${prefix}/supporting/context.json`,
    request_body: `${prefix}/supporting/request.raw`,
    request_record: `${prefix}/supporting/request-record.json`,
    transport_record: `${prefix}/supporting/transport-record.json`,
    observer_stdout: `${prefix}/supporting/observer-stdout.log`,
    observer_stderr: `${prefix}/supporting/observer-stderr.log`,
    observer_record: `${prefix}/supporting/observer.json`,
    usage_record: `${prefix}/supporting/usage.json`,
  };
  const supportingBytes = {
    context_record: contextBytes,
    request_body: requestBodyBytes,
    request_record: requestRecordBytes,
    transport_record: canonicalBytes(analyzed.record),
    observer_stdout: observer.stdout_bytes,
    observer_stderr: observer.stderr_bytes,
    observer_record: canonicalBytes(observer.record),
    usage_record: canonicalBytes(usage),
  };
  assertNoSecretReflection(Object.values(supportingBytes), bases.secret_sentinel);
  const supportingArtifacts = {};
  for (const key of Object.keys(supportingPaths)) {
    supportingArtifacts[key] = writeBytesCreateOnce(
      handle,
      supportingPaths[key],
      supportingBytes[key],
    );
  }
  const quarantine = createDisposableRoot(
    `p165ctl-${caseId.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 18)}`,
  );
  try {
    writeBytesCreateOnce(quarantine, "response.http", rawResponseBytes);
    const admission = admitAndPersistResponse({
      evidence_handle: handle,
      quarantine_handle: quarantine,
      quarantine_relative_path: "response.http",
      admitted_relative_path: `${prefix}/admission/admitted-response.http`,
      receipt_relative_path: `${prefix}/admission/admission-receipt.json`,
      join: joinValue,
      request_record_identity: requestRecordIdentity,
      request_record_bytes: requestRecordBytes,
      context_record_bytes: contextBytes,
      request_body_bytes: requestBodyBytes,
      policy,
      observed_peer: policy.expected_peer,
      transport_chunks: splitBytes(rawResponseBytes, [1, 7, 13]),
      eof: true,
      stream_terminal_events: [],
      observer_record: observer.record,
      observer_stdout_bytes: observer.stdout_bytes,
      observer_stderr_bytes: observer.stderr_bytes,
      usage_record: usage,
      secret_sentinel: bases.secret_sentinel,
      supporting_artifacts: supportingArtifacts,
    });
    const receiptPath = `${prefix}/admission/admission-receipt.json`;
    const receiptBytes = readFileSync(
      join(handle.root, ...receiptPath.split("/")),
    );
    return {
      admission,
      receipt_bytes: receiptBytes,
      receipt_identity: {
        path: receiptPath,
        ...bytesIdentity(receiptBytes),
      },
      request_record_identity: requestRecordIdentity,
    };
  } finally {
    cleanupOwnedRoot(quarantine);
  }
}

const ORDINARY_FAILURE_CASES = Object.freeze([
  ["MODEL_FAILURE", "MODEL", "MODEL_OUTPUT_REJECTED"],
  ["JSON_FAILURE", "JSON", "JSON_DECODE_FAILED"],
  ["PATCH_IR_FAILURE", "PATCH_IR", "PATCH_IR_REJECTED"],
  ["COMPILER_FAILURE", "COMPILER", "COMPILER_REJECTED"],
  ["ORACLE_FAILURE", "ORACLE", "ORACLE_FAILED"],
  ["TEST_FAILURE", "TEST", "TEST_FAILED"],
]);

function wrongButCompilableResponse(responseId, failureStage) {
  const accepted = buildAcceptedReferenceResponse(ACCEPTED_TASK_IDS[0], responseId);
  const ir = clone(accepted.ir);
  const postimage = failureStage === "TEST"
    ? Buffer.from("export function normalizeRange(\n", "utf8")
    : Buffer.from(
        [
          "export function normalizeRange(start, end) {",
          "  if (start <= end) return { start, end };",
          "  return { start: end, end };",
          "}",
          "",
        ].join("\n"),
        "utf8",
      );
  ir.operations[0].postimage = {
    base64: postimage.toString("base64"),
    sha256: sha256(postimage),
    byte_length: postimage.length,
  };
  return buildNormalizedProviderResponse({
    responseId,
    taskId: ACCEPTED_TASK_IDS[0],
    patchIrBytes: canonicalBytes(ir),
  });
}

function earlyFailureResponse(stage, responseId) {
  if (stage === "MODEL") {
    return canonicalBytes({
      schema_version: MODEL_FAILURE_SCHEMA,
      status: "DECLINED",
    });
  }
  if (stage === "JSON") return Buffer.from("{", "utf8");
  if (stage === "PATCH_IR") {
    return buildNormalizedProviderResponse({
      responseId,
      taskId: ACCEPTED_TASK_IDS[0],
      patchIrBytes: canonicalBytes({ schema_version: "SL-PATCH-IR/2" }),
    });
  }
  const accepted = buildAcceptedReferenceResponse(
    ACCEPTED_TASK_IDS[0],
    responseId,
  );
  const ir = clone(accepted.ir);
  ir.operations[0].path = "src/not-in-accepted-profile.mjs";
  return buildNormalizedProviderResponse({
    responseId,
    taskId: ACCEPTED_TASK_IDS[0],
    patchIrBytes: canonicalBytes(ir),
  });
}

function observeEarlyOrdinaryFailure(failureStage, responseBody) {
  if (failureStage === "MODEL") {
    return classifyModelFailureEnvelope(responseBody).reason_code;
  }
  const expectedCode = {
    JSON: "IR_JSON_INVALID",
    PATCH_IR: "IR_SCHEMA_INVALID",
    COMPILER: "IR_PATH_REJECTED",
  }[failureStage];
  assertCritical(
    typeof expectedCode === "string",
    "ACCOUNTING_MISMATCH",
    "early ordinary failure stage is unknown",
  );
  let observedCode = null;
  try {
    compileNormalizedProviderResponse(
      responseBody,
      loadAcceptedCompilerProfile(ACCEPTED_TASK_IDS[0]),
    );
  } catch (error) {
    observedCode = typeof error?.code === "string" ? error.code : null;
  }
  assertCritical(
    observedCode === expectedCode,
    "ACCOUNTING_MISMATCH",
    `${failureStage} fixture did not stop at its exact production boundary`,
  );
  return observedCode;
}

async function runOrdinaryFailureControls(handle, bases) {
  const root = "raw/ordinary-failure-continuation";
  writeJsonCreateOnce(handle, `${root}/plan.json`, {
    schema_version: "p1-165-ordinary-failure-plan/v1",
    task_id: TASK_ID,
    case_order: ORDINARY_FAILURE_CASES.map(([caseId]) => caseId),
    failure_stage_order: ORDINARY_FAILURE_CASES.map(([, stage]) => stage),
    denominator_policy: "ALL_FAILED_CASES_INCLUDED",
    continuation_policy: "NEXT_ACCEPTED_CELL_MUST_SUCCEED",
  });
  const results = [];
  const events = [];
  for (const [index, [caseId, failureStage, outcomeReason]]
    of ORDINARY_FAILURE_CASES.entries()) {
    const joinValue = {
      execution_id: `P1-165-ORDINARY-${String(index + 1).padStart(2, "0")}`,
      cell_id: `P1-165-ORDINARY-${String(index + 1).padStart(2, "0")}`,
      task_id: TASK_ID,
      profile_id: "B0_A",
      repetition_id: "A",
    };
    const prefix = `${root}/cases/${caseId}`;
    const responseBody = ["ORACLE", "TEST"].includes(failureStage)
      ? wrongButCompilableResponse(`P1-165-${caseId}`, failureStage)
      : earlyFailureResponse(failureStage, `P1-165-${caseId}`);
    const admitted = admitSharedCalibrationBody({
      handle,
      prefix,
      caseId,
      joinValue,
      bodyBytes: responseBody,
      bases,
    });
    const early = ["MODEL", "JSON", "PATCH_IR", "COMPILER"]
      .includes(failureStage);
    let execution = null;
    let engineReasonCode = early
      ? observeEarlyOrdinaryFailure(failureStage, admitted.admission.body_bytes)
      : null;
    if (!early) {
      execution = await executeSpine({
        taskId: ACCEPTED_TASK_IDS[0],
        responseBytes: admitted.admission.body_bytes,
        runId: `P1-165-${caseId}`,
      });
    }
    assertCritical(
      (early
        && execution === null
        && typeof engineReasonCode === "string"
        && engineReasonCode !== "UNCLASSIFIED_ENGINE_FAILURE")
        || (
          !early
          && execution !== null
          && execution.summary.worker_observed_classification === "FAILED"
          && Object.keys(execution.artifacts).length
            === EXECUTION_ARTIFACT_KEYS.length
        ),
      "ACCOUNTING_MISMATCH",
      `ordinary failure stage did not fail at its declared boundary: ${caseId}`,
    );
    if (!early) {
      if (failureStage === "ORACLE") {
        assertCritical(
          execution.summary.issue_test_exit_status !== 0
            && execution.summary.regression_test_exit_status === 0,
          "ACCOUNTING_MISMATCH",
          "ORACLE fixture did not isolate the issue postcondition failure",
        );
        engineReasonCode = "ORACLE_POSTCONDITION_FAILED";
      } else {
        assertCritical(
          execution.summary.regression_test_exit_status !== 0,
          "ACCOUNTING_MISMATCH",
          "TEST fixture did not produce an independently observed test failure",
        );
        engineReasonCode = "TEST_COMMAND_FAILED";
      }
    }
    const artifactIdentities = [];
    if (execution !== null) {
      for (const artifactName of EXECUTION_ARTIFACT_KEYS) {
        artifactIdentities.push(writeBytesCreateOnce(
          handle,
          `${prefix}/spine/${artifactName}`,
          execution.artifacts[artifactName],
        ));
      }
    }
    const admissionIdentity = {
      byte_length: admitted.receipt_identity.byte_length,
      sha256: admitted.receipt_identity.sha256,
    };
    const failureReceipt = writeResearchFailureReceipt({
      evidence_handle: handle,
      relative_path: `${prefix}/research-failure-receipt.json`,
      join: joinValue,
      failure_stage: failureStage,
      reason_code: outcomeReason,
      admission_receipt_identity: admissionIdentity,
      secret_sentinel: bases.secret_sentinel,
    });
    const failureReceiptBytes = readFileSync(
      join(handle.root, ...failureReceipt.path.split("/")),
    );
    const byName = new Map(
      EXECUTION_ARTIFACT_KEYS.map((name, artifactIndex) => [
        name,
        artifactIdentities[artifactIndex],
      ]),
    );
    const closure = closeCellEvidence({
      evidence_handle: handle,
      relative_path: `${prefix}/cell-closure.json`,
      join: joinValue,
      request_record_identity: admitted.request_record_identity,
      admitted_response_identity:
        bytesIdentity(admitted.admission.raw_response_bytes),
      body_identity: bytesIdentity(admitted.admission.body_bytes),
      admission_receipt_bytes: admitted.receipt_bytes,
      admission_receipt_identity: admitted.receipt_identity,
      adapter_control_identity: bases.adapter_identity,
      p1_149_artifact_identities: artifactIdentities.map((identity) => ({
        path: identity.path,
        byte_length: identity.byte_length,
        sha256: identity.sha256,
      })),
      p1_101_receipt_identities: execution === null
        ? []
        : [
            byName.get("p1-101-replay-receipt.json"),
            byName.get("p1-101-adapter-rollback-receipt.json"),
          ].map((identity) => ({
            path: identity.path,
            byte_length: identity.byte_length,
            sha256: identity.sha256,
          })),
      b2_scan_proof_identity: null,
      outcome: "FAILED",
      outcome_reason: outcomeReason,
      failure_stage: failureStage,
      failure_receipt_bytes: failureReceiptBytes,
      failure_receipt_identity: failureReceipt,
    });
    const result = {
      schema_version: "p1-165-ordinary-failure-case/v1",
      task_id: TASK_ID,
      case_id: caseId,
      failure_stage: failureStage,
      engine_reason_code: engineReasonCode,
      admission_receipt_identity: admitted.receipt_identity,
      research_failure_receipt_identity: failureReceipt,
      cell_closure_identity: closure,
      p1_149_artifact_count: artifactIdentities.length,
      p1_101_receipt_count: execution === null ? 0 : 2,
      denominator_included: true,
      worker_success_fields_trusted: false,
      status: "PASS",
    };
    writeJsonCreateOnce(handle, `${prefix}/result.json`, result);
    results.push(result);
    events.push({
      schema_version: "p1-165-ordinary-failure-event/v1",
      task_id: TASK_ID,
      sequence: index + 1,
      case_id: caseId,
      failure_stage: failureStage,
      cell_closure_identity: closure,
    });
  }
  return { root, results, events };
}

function finalizeOrdinaryFailureControls(handle, controls, synthetic) {
  const first = synthetic.cellOrder[0];
  assertCritical(
    first !== undefined && first.cell_id === "P1-165-CELL-01",
    "ACCOUNTING_MISMATCH",
    "accepted continuation cell is missing",
  );
  const continuationClosure = identityWithPath(
    handle.root,
    `raw/cells/${first.cell_id}/cell-closure.json`,
  );
  const continuationEvent = {
    schema_version: "p1-165-ordinary-continuation-event/v1",
    task_id: TASK_ID,
    sequence: controls.events.length + 1,
    event_type: "ACCEPTED_CONTINUATION",
    cell_id: first.cell_id,
    cell_closure_identity: continuationClosure,
    status: "PASS",
  };
  writeBytesCreateOnce(
    handle,
    `${controls.root}/events.jsonl`,
    Buffer.from(
      `${[...controls.events, continuationEvent]
        .map((event) => canonicalJson(event)).join("\n")}\n`,
    ),
  );
  const receipt = {
    schema_version: "p1-165-ordinary-failure-continuation/v1",
    task_id: TASK_ID,
    case_order: controls.results.map((entry) => entry.case_id),
    failure_stage_order: controls.results.map((entry) => entry.failure_stage),
    failed_denominator_cases: controls.results.length,
    early_failure_cases: controls.results.filter(
      (entry) => entry.p1_149_artifact_count === 0,
    ).length,
    late_failure_cases: controls.results.filter(
      (entry) => entry.p1_149_artifact_count === EXECUTION_ARTIFACT_KEYS.length,
    ).length,
    continuation_cell_id: first.cell_id,
    continuation_closure_identity: continuationClosure,
    status: "PASS",
  };
  writeJsonCreateOnce(handle, `${controls.root}/receipt.json`, receipt);
  return receipt;
}

async function runOutputTokenBoundaryControls(handle, bases) {
  const root = "raw/token-boundary";
  const caseOrder = [2047, 2048, 2049];
  writeJsonCreateOnce(handle, `${root}/contract.json`, {
    schema_version: "p1-165-output-token-boundary-contract/v1",
    task_id: TASK_ID,
    output_tokens_max: OUTPUT_TOKENS_MAX,
    case_order: caseOrder,
    semantics: "PROVIDER_REPORTED_OUTPUT_USAGE_NOT_CONTENT_TOKENIZATION",
    exact_boundary_requires_full_p1_149_spine: true,
  });
  const accepted = buildAcceptedReferenceResponse(
    ACCEPTED_TASK_IDS[0],
    "P1-165-TOKEN-BOUNDARY-2048",
  );
  const responseIdentity = bytesIdentity(accepted.response_bytes);
  const results = [];
  for (const outputTokens of caseOrder) {
    const caseId = `OUTPUT_TOKENS_${outputTokens}`;
    const joinValue = {
      execution_id: `P1-165-TOKEN-${outputTokens}`,
      cell_id: `P1-165-TOKEN-${outputTokens}`,
      task_id: TASK_ID,
      profile_id: "B0_A",
      repetition_id: "A",
    };
    const usage = observedUsage({
      join: joinValue,
      responseIdentity,
      inputTokens: 0,
      outputTokens,
    });
    const usagePath = `${root}/cases/${outputTokens}/usage.json`;
    if (outputTokens === 2049) {
      let observedReason = null;
      const attempt = createDisposableRoot("p165-token-over");
      try {
        admitSharedCalibrationBody({
          handle: attempt,
          prefix: "attempt",
          caseId,
          joinValue,
          bodyBytes: accepted.response_bytes,
          bases,
          usageFactory: (bodyIdentity) => observedUsage({
            join: joinValue,
            responseIdentity: bodyIdentity,
            inputTokens: 0,
            outputTokens,
          }),
          prevalidateUsage: false,
        });
      } catch (error) {
        if (error instanceof AdmissionNonPass) observedReason = error.code;
        else throw error;
      } finally {
        if (existsSync(attempt.root)) cleanupOwnedRoot(attempt);
      }
      assertCritical(
        observedReason === "PROVIDER_OUTPUT_USAGE_EXCEEDED",
        "ACCOUNTING_MISMATCH",
        "2049 provider-reported output tokens did not fail closed",
      );
      const safeRoot = `${root}/cases/${outputTokens}`;
      const safeReceipt = writeSafeFailureReceipt({
        evidence_handle: handle,
        relative_path: `${safeRoot}/safe-failure-receipt.json`,
        join: joinValue,
        reason_code: observedReason,
        secret_sentinel: bases.secret_sentinel,
      });
      const result = {
        schema_version: "p1-165-output-token-boundary-case/v1",
        task_id: TASK_ID,
        output_tokens: outputTokens,
        semantics: "PROVIDER_REPORTED_OUTPUT_USAGE_NOT_CONTENT_TOKENIZATION",
        expected_status: "NON_PASS",
        observed_status: "NON_PASS",
        observed_reason_code: observedReason,
        admission_receipt_identity: null,
        cell_closure_identity: null,
        p1_149_artifact_count: 0,
        p1_101_receipt_count: 0,
        safe_failure_receipt_identity: safeReceipt,
        status: "PASS",
      };
      results.push(result);
      continue;
    }
    writeJsonCreateOnce(handle, usagePath, usage);
    if (outputTokens === 2047) {
      const admitted = admitSharedCalibrationBody({
        handle,
        prefix: `${root}/cases/${outputTokens}`,
        caseId,
        joinValue,
        bodyBytes: accepted.response_bytes,
        bases,
        usageFactory: (bodyIdentity) => observedUsage({
          join: joinValue,
          responseIdentity: bodyIdentity,
          inputTokens: 0,
          outputTokens,
        }),
      });
      const result = {
        schema_version: "p1-165-output-token-boundary-case/v1",
        task_id: TASK_ID,
        output_tokens: outputTokens,
        semantics: "PROVIDER_REPORTED_OUTPUT_USAGE_NOT_CONTENT_TOKENIZATION",
        expected_status: "PASS",
        observed_status: "PASS",
        observed_reason_code: "PASS",
        admission_receipt_identity: admitted.receipt_identity,
        cell_closure_identity: null,
        p1_149_artifact_count: 0,
        p1_101_receipt_count: 0,
        safe_failure_receipt_identity: null,
        status: "PASS",
      };
      writeJsonCreateOnce(
        handle,
        `${root}/cases/${outputTokens}/result.json`,
        result,
      );
      results.push(result);
      continue;
    }
    const prefix = `${root}/cases/${outputTokens}`;
    const admitted = admitSharedCalibrationBody({
      handle,
      prefix,
      caseId,
      joinValue,
      bodyBytes: accepted.response_bytes,
      bases,
      usageFactory: (bodyIdentity) => observedUsage({
        join: joinValue,
        responseIdentity: bodyIdentity,
        inputTokens: 0,
        outputTokens,
      }),
    });
    const execution = await executeSpine({
      taskId: ACCEPTED_TASK_IDS[0],
      responseBytes: admitted.admission.body_bytes,
      runId: "P1-165-TOKEN-BOUNDARY-2048",
    });
    assertCritical(
      execution.summary.worker_observed_classification === "VERIFIED_SUCCESS"
        && Object.keys(execution.artifacts).length
          === EXECUTION_ARTIFACT_KEYS.length,
      "ACCOUNTING_MISMATCH",
      "2048 exact boundary did not complete the full accepted spine",
    );
    const artifactIdentities = [];
    for (const artifactName of EXECUTION_ARTIFACT_KEYS) {
      artifactIdentities.push(writeBytesCreateOnce(
        handle,
        `${prefix}/spine/${artifactName}`,
        execution.artifacts[artifactName],
      ));
    }
    const byName = new Map(
      EXECUTION_ARTIFACT_KEYS.map((name, artifactIndex) => [
        name,
        artifactIdentities[artifactIndex],
      ]),
    );
    const closure = closeCellEvidence({
      evidence_handle: handle,
      relative_path: `${prefix}/cell-closure.json`,
      join: joinValue,
      request_record_identity: admitted.request_record_identity,
      admitted_response_identity:
        bytesIdentity(admitted.admission.raw_response_bytes),
      body_identity: bytesIdentity(admitted.admission.body_bytes),
      admission_receipt_bytes: admitted.receipt_bytes,
      admission_receipt_identity: admitted.receipt_identity,
      adapter_control_identity: bases.adapter_identity,
      p1_149_artifact_identities: artifactIdentities.map((identity) => ({
        path: identity.path,
        byte_length: identity.byte_length,
        sha256: identity.sha256,
      })),
      p1_101_receipt_identities: [
        byName.get("p1-101-replay-receipt.json"),
        byName.get("p1-101-adapter-rollback-receipt.json"),
      ].map((identity) => ({
        path: identity.path,
        byte_length: identity.byte_length,
        sha256: identity.sha256,
      })),
      b2_scan_proof_identity: null,
      outcome: "SUCCESS",
      outcome_reason: "PASS",
    });
    const result = {
      schema_version: "p1-165-output-token-boundary-case/v1",
      task_id: TASK_ID,
      output_tokens: outputTokens,
      semantics: "PROVIDER_REPORTED_OUTPUT_USAGE_NOT_CONTENT_TOKENIZATION",
      expected_status: "PASS",
      observed_status: "PASS",
      observed_reason_code: "PASS",
      admission_receipt_identity: admitted.receipt_identity,
      cell_closure_identity: closure,
      p1_149_artifact_count: artifactIdentities.length,
      p1_101_receipt_count: 2,
      safe_failure_receipt_identity: null,
      status: "PASS",
    };
    writeJsonCreateOnce(
      handle,
      `${root}/cases/${outputTokens}/result.json`,
      result,
    );
    results.push(result);
  }
  const receipt = {
    schema_version: "p1-165-output-token-boundary-receipt/v1",
    task_id: TASK_ID,
    case_order: results.map((entry) => entry.output_tokens),
    observed_statuses: results.map((entry) => entry.observed_status),
    exact_boundary_full_p1_149_artifact_count:
      results[1].p1_149_artifact_count,
    exact_boundary_p1_101_receipt_count:
      results[1].p1_101_receipt_count,
    overflow_admission_absent:
      results[2].admission_receipt_identity === null,
    overflow_spine_absent:
      results[2].p1_149_artifact_count === 0,
    status: "PASS",
  };
  writeJsonCreateOnce(handle, `${root}/receipt.json`, receipt);
  return {
    receipt,
    expectedNonPassCases: [{
      case_id: "OUTPUT_TOKENS_2049",
      root: `${root}/cases/2049`,
      failure_receipt_path:
        `${root}/cases/2049/safe-failure-receipt.json`,
    }],
  };
}

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

function integrationFixtureExists(path) {
  try {
    lstatSync(path);
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

export function runIntegrationNegativeControls(handle, bases) {
  const root = "raw/integration-negative-control";
  writeJsonCreateOnce(handle, `${root}/plan.json`, {
    schema_version: "p1-165-integration-negative-plan/v3",
    task_id: TASK_ID,
    cases: INTEGRATION_NEGATIVE_CASES.map(
      (entry, index) => ({
        sequence: index + 1,
        ...entry,
      }),
    ),
    high_level_entry: "admitAndPersistResponse",
    final_response_policy: "ABSENT",
    attempt_root_policy: "CLEANED",
  });
  const results = [];
  for (const [index, casePlan]
    of INTEGRATION_NEGATIVE_CASES.entries()) {
    const {
      case_id: caseId,
      expected_reason_code: expectedReasonCode,
      output_tokens: outputTokens,
    } = casePlan;
    const evidence = createDisposableRoot(
      `p165int-${caseId.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 16)}`,
    );
    const quarantine = createDisposableRoot(
      `p165q-${caseId.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 16)}`,
    );
    const joinValue = {
      execution_id: `P1-165-INTEGRATION-${String(index + 1).padStart(2, "0")}`,
      cell_id: `P1-165-INTEGRATION-${String(index + 1).padStart(2, "0")}`,
      task_id: TASK_ID,
      profile_id: "B0_A",
      repetition_id: "A",
    };
    const policy = clone(bases.calibration.policy);
    let responseBody = Buffer.from("{}\n", "utf8");
    if (caseId === "SECRET_REFLECTION") {
      responseBody = Buffer.from(bases.secret_sentinel);
    }
    let rawResponse = buildHttpResponse(responseBody);
    if (caseId === "TRANSPORT_INCOMPLETE") {
      rawResponse = Buffer.from(
        "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nabc",
        "latin1",
      );
    }
    const requestBody = canonicalBytes({
      schema_version: "p1-165-integration-negative-request/v1",
      case_id: caseId,
    });
    const contextBytes = canonicalBytes({
      schema_version: "p1-165-context-record/v1",
      task_id: TASK_ID,
      join: joinValue,
      adapter_result_identity: bases.adapter_identity,
    });
    let requestRecord = {
      schema_version: "p1-165-request-record/v1",
      task_id: TASK_ID,
      join: joinValue,
      context_record_identity: bytesIdentity(contextBytes),
      request_body_identity: bytesIdentity(requestBody),
      policy,
    };
    if (caseId === "CLOSED_REQUEST") requestRecord.extra = true;
    const requestRecordBytes = canonicalBytes(requestRecord);
    const requestIdentity = bytesIdentity(requestRecordBytes);
    let observerStdoutBytes = bases.calibration.stdout_bytes;
    const observerStderrBytes = bases.calibration.stderr_bytes;
    const observerRecord = {
      ...clone(bases.calibration.record),
      join: joinValue,
      request_record_identity: requestIdentity,
      policy,
      stdout_path: "supporting/observer-stdout.log",
      stderr_path: "supporting/observer-stderr.log",
    };
    if (caseId === "OBSERVER_FORGED") {
      observerRecord.observed_rows = observerRecord.observed_rows.map(
        (row, rowIndex) => rowIndex === 0
          ? { ...row, local: "127.0.0.1:1" }
          : row,
      );
    }
    if (caseId === "OBSERVER_EXTRA_ROW") {
      const extraRow = {
        pid: observerRecord.pid,
        fd: "99u",
        local: `127.0.0.1:${49000 + index}`,
        peer: "203.0.113.10:443",
        state: "ESTABLISHED",
      };
      assertCritical(
        observerStdoutBytes.toString("utf8").endsWith("\n"),
        "OBSERVER_EVIDENCE_FORGED",
        "base observer stdout is not newline terminated",
      );
      observerStdoutBytes = Buffer.concat([
        observerStdoutBytes,
        Buffer.from(
          "node "
          + `${extraRow.pid} fixture ${extraRow.fd} IPv4 0x1 0t0 TCP `
          + `${extraRow.local}->${extraRow.peer} (${extraRow.state})\n`,
          "utf8",
        ),
      ]);
      observerRecord.stdout_identity = bytesIdentity(observerStdoutBytes);
      observerRecord.observed_rows = [
        ...observerRecord.observed_rows,
        extraRow,
      ];
    }
    if (caseId === "OBSERVER_MALFORMED_EXTRA_ROW") {
      observerStdoutBytes = Buffer.concat([
        observerStdoutBytes,
        Buffer.from("garbage unparsed row\n", "utf8"),
      ]);
      observerRecord.stdout_identity = bytesIdentity(observerStdoutBytes);
    }
    if (caseId === "OBSERVER_BAD_HEADER") {
      const lines = observerStdoutBytes.toString("utf8").split("\n");
      assertCritical(
        lines.length === 3 && lines.at(-1) === "",
        "OBSERVER_EVIDENCE_FORGED",
        "base observer stdout shape drifted before bad-header control",
      );
      lines[0] = "BROKEN PID USER FD TYPE DEVICE SIZE/OFF NODE NAME";
      observerStdoutBytes = Buffer.from(lines.join("\n"), "utf8");
      observerRecord.stdout_identity = bytesIdentity(observerStdoutBytes);
    }
    const analyzedBodyIdentity = bytesIdentity(responseBody);
    const usage = observedUsage({
      join: joinValue,
      responseIdentity: analyzedBodyIdentity,
      inputTokens: 0,
      outputTokens,
    });
    const transportRecord = caseId === "TRANSPORT_INCOMPLETE"
      ? canonicalBytes({
          schema_version: "p1-165-integration-negative-placeholder/v1",
          case_id: caseId,
        })
      : canonicalBytes(analyzeTransport({
          join: joinValue,
          request_record_identity: requestIdentity,
          policy,
          observed_peer: policy.expected_peer,
          chunks: [rawResponse],
          eof: true,
          stream_terminal_events: [],
        }).record);
    const supportingBytes = {
      context_record: contextBytes,
      request_body: requestBody,
      request_record: requestRecordBytes,
      transport_record: transportRecord,
      observer_stdout: observerStdoutBytes,
      observer_stderr: observerStderrBytes,
      observer_record: canonicalBytes(observerRecord),
      usage_record: canonicalBytes(usage),
    };
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
    const supportingArtifacts = {};
    for (const key of Object.keys(supportingPaths)) {
      supportingArtifacts[key] = writeBytesCreateOnce(
        evidence,
        supportingPaths[key],
        supportingBytes[key],
      );
    }
    const contextPath = join(evidence.root, "supporting/context.json");
    let unsafeContextKind = null;
    if (caseId === "SYMLINK_SUPPORT") {
      unlinkSync(contextPath);
      symlinkSync("request.raw", contextPath);
      unsafeContextKind = "SYMLINK";
    }
    if (caseId === "HARDLINK_SUPPORT") {
      unlinkSync(contextPath);
      writeBytesCreateOnce(evidence, "fixture/context-source.json", contextBytes);
      linkSync(join(evidence.root, "fixture/context-source.json"), contextPath);
      unsafeContextKind = "HARDLINK";
    }
    let admittedRelativePath = "admission/admitted-response.http";
    if (caseId === "PATH_ESCAPE") admittedRelativePath = "../escaped-response.http";
    if (caseId === "EVIDENCE_WRITE") {
      chmodSync(evidence.root, 0o500);
    }
    if (caseId === "CREATE_ONCE_RESPONSE") {
      writeBytesCreateOnce(
        evidence,
        admittedRelativePath,
        Buffer.from("preexisting", "utf8"),
      );
    }
    writeBytesCreateOnce(quarantine, "response.http", rawResponse);
    let observedReasonCode = null;
    try {
      admitAndPersistResponse({
        evidence_handle: evidence,
        quarantine_handle: quarantine,
        quarantine_relative_path: "response.http",
        admitted_relative_path: admittedRelativePath,
        receipt_relative_path: "admission/admission-receipt.json",
        join: joinValue,
        request_record_identity: requestIdentity,
        request_record_bytes: requestRecordBytes,
        context_record_bytes: contextBytes,
        request_body_bytes: requestBody,
        policy,
        observed_peer: policy.expected_peer,
        transport_chunks: [rawResponse],
        eof: true,
        stream_terminal_events: [],
        observer_record: caseId === "OBSERVER_MISSING" ? null : observerRecord,
        observer_stdout_bytes: observerStdoutBytes,
        observer_stderr_bytes: observerStderrBytes,
        usage_record: usage,
        secret_sentinel: bases.secret_sentinel,
        supporting_artifacts: supportingArtifacts,
      });
    } catch (error) {
      if (error instanceof AdmissionNonPass) observedReasonCode = error.code;
      else throw error;
    } finally {
      if (caseId === "EVIDENCE_WRITE" && existsSync(evidence.root)) {
        chmodSync(evidence.root, 0o700);
      }
      if (unsafeContextKind !== null && integrationFixtureExists(contextPath)) {
        unlinkSync(contextPath);
      }
      if (existsSync(quarantine.root)) cleanupOwnedRoot(quarantine);
      if (existsSync(evidence.root)) cleanupOwnedRoot(evidence);
    }
    assertCritical(
      observedReasonCode === expectedReasonCode
        && !existsSync(evidence.root)
        && !existsSync(quarantine.root),
      "ACCOUNTING_MISMATCH",
      `integration negative case did not fail closed: ${caseId} expected=${expectedReasonCode} observed=${observedReasonCode}`,
    );
    let rawFixtureDescriptorIdentity = null;
    if ([
      "OBSERVER_EXTRA_ROW",
      "OBSERVER_MALFORMED_EXTRA_ROW",
      "OBSERVER_BAD_HEADER",
    ].includes(caseId)) {
      const fixtureRoot = `${root}/fixtures/${caseId}`;
      const stdoutIdentity = writeBytesCreateOnce(
        handle,
        `${fixtureRoot}/stdout.log`,
        observerStdoutBytes,
      );
      const stderrIdentity = writeBytesCreateOnce(
        handle,
        `${fixtureRoot}/stderr.log`,
        observerStderrBytes,
      );
      const observerRecordIdentity = writeJsonCreateOnce(
        handle,
        `${fixtureRoot}/observation.json`,
        observerRecord,
      );
      rawFixtureDescriptorIdentity = writeJsonCreateOnce(
        handle,
        `${fixtureRoot}/fixture.json`,
        {
          schema_version:
            "p1-168-observer-raw-closure-integration-fixture/v1",
          task_id: TASK_ID,
          case_id: caseId,
          expected_reason_code: expectedReasonCode,
          observer_record_identity: observerRecordIdentity,
          stdout_identity: stdoutIdentity,
          stderr_identity: stderrIdentity,
          raw_nonempty_data_rows:
            observerStdoutBytes.toString("utf8")
              .split("\n")
              .slice(1)
              .filter((line) => line.trim().length > 0)
              .length,
          record_observed_rows: observerRecord.observed_rows.length,
          policy_bound_rows: observerRecord.observed_rows.filter(
            (row) =>
              row.peer === policy.expected_peer
              && row.state === "ESTABLISHED",
          ).length,
          additional_nonloopback_rows: observerRecord.observed_rows.filter(
            (row) => !row.peer.startsWith("127.0.0.1:"),
          ).length,
          malformed_data_rows:
            caseId === "OBSERVER_MALFORMED_EXTRA_ROW" ? 1 : 0,
          normalized_header_matches:
            caseId !== "OBSERVER_BAD_HEADER",
          command_executed: false,
          live_network_connections_created: 0,
          status: "FROZEN_NEGATIVE_FIXTURE",
        },
      );
    }
    const safeRoot = `${root}/failures/${caseId}`;
    const safeReceipt = writeSafeFailureReceipt({
      evidence_handle: handle,
      relative_path: `${safeRoot}/safe-failure-receipt.json`,
      join: joinValue,
      reason_code: observedReasonCode,
      secret_sentinel: bases.secret_sentinel,
    });
    const result = {
      schema_version: "p1-165-integration-negative-case/v3",
      task_id: TASK_ID,
      case_id: caseId,
      output_tokens: outputTokens,
      expected_reason_code: expectedReasonCode,
      observed_reason_code: observedReasonCode,
      attempt_root_absent: true,
      quarantine_root_absent: true,
      admitted_response_persisted: false,
      admission_receipt_persisted: false,
      raw_fixture_descriptor_identity: rawFixtureDescriptorIdentity,
      safe_failure_receipt_identity: safeReceipt,
      status: "PASS",
    };
    writeJsonCreateOnce(handle, `${root}/cases/${caseId}.json`, result);
    results.push(result);
  }
  const receipt = {
    schema_version: "p1-165-integration-negative-receipt/v2",
    task_id: TASK_ID,
    case_order: results.map((entry) => entry.case_id),
    cases: results.length,
    final_responses_persisted: results.filter(
      (entry) => entry.admitted_response_persisted,
    ).length,
    attempt_roots_remaining: results.filter(
      (entry) => !entry.attempt_root_absent,
    ).length,
    false_accepts: 0,
    status: "PASS",
  };
  writeJsonCreateOnce(handle, `${root}/receipt.json`, receipt);
  return {
    receipt,
    expectedNonPassCases: results.map((entry) => ({
      case_id: `INTEGRATION_${entry.case_id}`,
      root: `${root}/failures/${entry.case_id}`,
      failure_receipt_path:
        `${root}/failures/${entry.case_id}/safe-failure-receipt.json`,
    })),
  };
}

export function selfTestObserverRawClosureIntegrationControls() {
  const handle = createDisposableRoot("p1168-observer-closure");
  try {
    const joinValue = {
      execution_id: "P1-168-OBSERVER-CLOSURE-SELFTEST",
      cell_id: "P1-168-OBSERVER-CLOSURE-SELFTEST",
      task_id: TASK_ID,
      profile_id: "B0_A",
      repetition_id: "A",
    };
    const requestIdentity = bytesIdentity(canonicalBytes({
      schema_version: "p1-168-observer-closure-selftest-request/v1",
      task_id: TASK_ID,
    }));
    const calibration = buildFrozenSyntheticObserverFixture({
      evidence_handle: handle,
      join: joinValue,
      request_record_identity: requestIdentity,
      artifact_prefix: "selftest/observer/calibration",
      fixture_index: 901,
    });
    const adapterIdentity = writeJsonCreateOnce(
      handle,
      "selftest/adapter.json",
      {
        schema_version: "p1-168-observer-closure-selftest-adapter/v1",
        task_id: TASK_ID,
      },
    );
    const controls = runIntegrationNegativeControls(handle, {
      join: joinValue,
      request_identity: requestIdentity,
      response_identity: bytesIdentity(Buffer.from("{}\n", "utf8")),
      policy: calibration.policy,
      calibration,
      secret_sentinel: Buffer.from(
        "P1-168-OBSERVER-CLOSURE-SELFTEST-SECRET-NEVER-PERSIST",
        "utf8",
      ),
      adapter_identity: adapterIdentity,
    });
    const observerCases = [
      "OBSERVER_EXTRA_ROW",
      "OBSERVER_MALFORMED_EXTRA_ROW",
      "OBSERVER_BAD_HEADER",
    ].map((caseId) => JSON.parse(readFileSync(
      join(
        handle.root,
        `raw/integration-negative-control/cases/${caseId}.json`,
      ),
      "utf8",
    )));
    assertCritical(
      controls.receipt.cases === INTEGRATION_NEGATIVE_CASES.length
        && controls.receipt.false_accepts === 0
        && controls.receipt.status === "PASS"
        && observerCases.every((entry) =>
          entry.expected_reason_code === "OBSERVER_EVIDENCE_FORGED"
            && entry.observed_reason_code === "OBSERVER_EVIDENCE_FORGED"
            && entry.attempt_root_absent === true
            && entry.quarantine_root_absent === true
            && entry.admitted_response_persisted === false
            && entry.admission_receipt_persisted === false
            && entry.raw_fixture_descriptor_identity !== null
            && entry.status === "PASS"
        ),
      "ACCOUNTING_MISMATCH",
      "observer raw-closure integration self-test did not fail closed",
    );
    return {
      schema_version:
        "p1-168-observer-raw-closure-integration-self-test/v1",
      task_id: P1_168_TASK_ID,
      integration_negative_cases: controls.receipt.cases,
      observer_raw_closure_cases: observerCases.map((entry) => ({
        case_id: entry.case_id,
        observed_reason_code: entry.observed_reason_code,
      })),
      false_accepts: controls.receipt.false_accepts,
      disposable_root_cleaned: true,
      status: "PASS",
    };
  } finally {
    if (existsSync(handle.root)) cleanupOwnedRoot(handle);
  }
}

async function persistMatrixDecision(
  handle,
  caseEntry,
  observedStatus,
  observedCode,
  bases,
  material,
) {
  const casePrefix = `raw/cases/${caseEntry.case_id}`;
  const caseJoin = material.join;
  validateJoin(caseJoin);
  if (observedStatus === "NON_PASS") {
    const receipt = writeSafeFailureReceipt({
      evidence_handle: handle,
      relative_path: `${casePrefix}/safe-failure-receipt.json`,
      join: caseJoin,
      reason_code: observedCode,
      secret_sentinel: bases.secret_sentinel,
    });
    return {
      admitted: 0,
      safe_failure_receipts: 1,
      unsafe_failure_receipts: 0,
      persistence_before_admission: 0,
      receipt,
    };
  }

  const policy = clone(bases.calibration.policy);
  const requestBodyBytes = canonicalBytes({
    schema_version: "p1-165-matrix-admission-request/v1",
    case_id: caseEntry.case_id,
  });
  const contextBytes = canonicalBytes({
    schema_version: "p1-165-context-record/v1",
    task_id: TASK_ID,
    join: caseJoin,
    adapter_result_identity: bases.adapter_identity,
  });
  const requestRecordBytes = canonicalBytes({
    schema_version: "p1-165-request-record/v1",
    task_id: TASK_ID,
    join: caseJoin,
    context_record_identity: bytesIdentity(contextBytes),
    request_body_identity: bytesIdentity(requestBodyBytes),
    policy,
  });
  const requestRecordIdentity = bytesIdentity(requestRecordBytes);
  const fullSpineRequired = material.full_spine_required;
  const matrixSpineRunId = material.run_id;
  const bodyBytes = material.body_bytes;
  assertCritical(
    sameJson(bytesIdentity(bodyBytes), material.response_identity),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "matrix materialized body identity drifted before persistence",
  );
  const rawResponseBytes = buildHttpResponse(bodyBytes);
  const observer = {
    policy,
    join: caseJoin,
    request_record_identity: requestRecordIdentity,
    stdout_bytes: Buffer.from(bases.calibration.stdout_bytes),
    stderr_bytes: Buffer.from(bases.calibration.stderr_bytes),
    record: {
      ...clone(bases.calibration.record),
      join: caseJoin,
      request_record_identity: requestRecordIdentity,
      policy,
      stdout_path: `${casePrefix}/supporting/observer-stdout.log`,
      stderr_path: `${casePrefix}/supporting/observer-stderr.log`,
    },
  };
  validateRawObservation({
    record: observer.record,
    stdout_bytes: observer.stdout_bytes,
    stderr_bytes: observer.stderr_bytes,
    join: caseJoin,
    request_record_identity: requestRecordIdentity,
    policy,
    require_current_process: true,
  });
  const analyzed = analyzeTransport({
    join: caseJoin,
    request_record_identity: requestRecordIdentity,
    policy,
    observed_peer: policy.expected_peer,
    chunks: splitBytes(rawResponseBytes, [1, 7, 13]),
    eof: true,
    stream_terminal_events: [],
  });
  const usage = Number.isSafeInteger(caseEntry.output_tokens)
    ? observedUsage({
        join: caseJoin,
        responseIdentity: analyzed.record.body_identity,
        inputTokens: 1,
        outputTokens: caseEntry.output_tokens,
      })
    : unknownUsage({
        join: caseJoin,
        responseIdentity: analyzed.record.body_identity,
      });
  const supportingPaths = {
    context_record: `${casePrefix}/supporting/context.json`,
    request_body: `${casePrefix}/supporting/request.raw`,
    request_record: `${casePrefix}/supporting/request-record.json`,
    transport_record: `${casePrefix}/supporting/transport-record.json`,
    observer_stdout: `${casePrefix}/supporting/observer-stdout.log`,
    observer_stderr: `${casePrefix}/supporting/observer-stderr.log`,
    observer_record: `${casePrefix}/supporting/observer.json`,
    usage_record: `${casePrefix}/supporting/usage.json`,
  };
  const supportingBytes = {
    context_record: contextBytes,
    request_body: requestBodyBytes,
    request_record: requestRecordBytes,
    transport_record: canonicalBytes(analyzed.record),
    observer_stdout: observer.stdout_bytes,
    observer_stderr: observer.stderr_bytes,
    observer_record: canonicalBytes(observer.record),
    usage_record: canonicalBytes(usage),
  };
  assertNoSecretReflection(Object.values(supportingBytes), bases.secret_sentinel);
  const supportingArtifacts = {};
  for (const key of Object.keys(supportingPaths)) {
    supportingArtifacts[key] = writeBytesCreateOnce(
      handle,
      supportingPaths[key],
      supportingBytes[key],
    );
  }
  const quarantine = createDisposableRoot(
    `p165mx-${caseEntry.case_id.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 18)}`,
  );
  try {
    writeBytesCreateOnce(quarantine, "response.http", rawResponseBytes);
    const admission = admitAndPersistResponse({
      evidence_handle: handle,
      quarantine_handle: quarantine,
      quarantine_relative_path: "response.http",
      admitted_relative_path: `${casePrefix}/admission/admitted-response.http`,
      receipt_relative_path: `${casePrefix}/admission/admission-receipt.json`,
      join: caseJoin,
      request_record_identity: requestRecordIdentity,
      request_record_bytes: requestRecordBytes,
      context_record_bytes: contextBytes,
      request_body_bytes: requestBodyBytes,
      policy,
      observed_peer: policy.expected_peer,
      transport_chunks: splitBytes(rawResponseBytes, [1, 7, 13]),
      eof: true,
      stream_terminal_events: [],
      observer_record: observer.record,
      observer_stdout_bytes: observer.stdout_bytes,
      observer_stderr_bytes: observer.stderr_bytes,
      usage_record: usage,
      secret_sentinel: bases.secret_sentinel,
      supporting_artifacts: supportingArtifacts,
    });
    assertCritical(
      admission.status === "ADMITTED"
        && admission.raw_response_bytes.equals(rawResponseBytes),
      "EVIDENCE_WRITE_FAILED",
      "production matrix admission did not persist exact admitted bytes",
    );
    if (fullSpineRequired) {
      const execution = await executeSpine({
        taskId: ACCEPTED_TASK_IDS[0],
        responseBytes: admission.body_bytes,
        runId: matrixSpineRunId,
      });
      assertCritical(
        execution.summary.worker_observed_classification === "VERIFIED_SUCCESS"
          && execution.summary.p1_101_replay === "PASS"
          && execution.summary.rollback_exact === true
          && Object.keys(execution.artifacts).length
            === EXECUTION_ARTIFACT_KEYS.length,
        "ACCOUNTING_MISMATCH",
        "typed 2048 matrix case did not complete the full accepted spine",
      );
      const artifactIdentities = [];
      for (const artifactName of EXECUTION_ARTIFACT_KEYS) {
        artifactIdentities.push(writeBytesCreateOnce(
          handle,
          `${casePrefix}/spine/${artifactName}`,
          execution.artifacts[artifactName],
        ));
      }
      const byName = new Map(
        EXECUTION_ARTIFACT_KEYS.map((artifactName, index) => [
          artifactName,
          artifactIdentities[index],
        ]),
      );
      const admissionReceiptBytes = canonicalBytes(admission.receipt);
      const admissionReceiptIdentity = {
        path: `${casePrefix}/admission/admission-receipt.json`,
        ...bytesIdentity(admissionReceiptBytes),
      };
      closeCellEvidence({
        evidence_handle: handle,
        relative_path: `${casePrefix}/cell-closure.json`,
        join: caseJoin,
        request_record_identity: requestRecordIdentity,
        admitted_response_identity:
          bytesIdentity(admission.raw_response_bytes),
        body_identity: bytesIdentity(admission.body_bytes),
        admission_receipt_bytes: admissionReceiptBytes,
        admission_receipt_identity: admissionReceiptIdentity,
        adapter_control_identity: bases.adapter_identity,
        p1_149_artifact_identities: artifactIdentities.map((identity) => ({
          path: identity.path,
          byte_length: identity.byte_length,
          sha256: identity.sha256,
        })),
        p1_101_receipt_identities: [
          byName.get("p1-101-replay-receipt.json"),
          byName.get("p1-101-adapter-rollback-receipt.json"),
        ].map((identity) => ({
          path: identity.path,
          byte_length: identity.byte_length,
          sha256: identity.sha256,
        })),
        b2_scan_proof_identity: null,
        outcome: "SUCCESS",
        outcome_reason: "PASS",
      });
    }
  } finally {
    cleanupOwnedRoot(quarantine);
  }
  return {
    admitted: 1,
    safe_failure_receipts: 0,
    unsafe_failure_receipts: 0,
    persistence_before_admission: 0,
  };
}

async function writeMatrixCases(handle, matrix, bases) {
  const observations = [];
  const oracleDivergences = [];
  const caseDecisions = [];
  const expectedNonPassCases = [];
  const accounting = {
    admitted: 0,
    safe_failure_receipts: 0,
    unsafe_failure_receipts: 0,
    persistence_before_admission: 0,
  };
  for (const caseEntry of flattenCases(matrix)) {
    const material = materializeMatrixCase(caseEntry);
    const stimulus = stimulusForCase(caseEntry, bases, material);
    const input = {
      schema_version: CASE_INPUT_SCHEMA,
      task_id: TASK_ID,
      case_id: caseEntry.case_id,
      category_id: caseEntry.category_id,
      stimulus,
      synthetic_observer_fixture: {
        descriptor: bases.calibration.descriptor,
        record: bases.calibration.record,
        stdout_base64: bases.calibration.stdout_bytes.toString("base64"),
        stderr_base64: bases.calibration.stderr_bytes.toString("base64"),
      },
    };
    const startedAt = new Date().toISOString();
    const inputIdentity = writeCaseJson(handle, caseEntry.case_id, "input.json", input);
    const childArgv = [
      fileURLToPath(import.meta.url),
      "--matrix-case",
      join(handle.root, ...inputIdentity.path.split("/")),
      caseEntry.case_id,
      String(inputIdentity.byte_length),
      inputIdentity.sha256,
    ];
    const child = spawnSync(process.execPath, childArgv, {
      cwd: REPOSITORY_ROOT,
      encoding: null,
      env: closedChildEnvironment(),
      maxBuffer: 1024 * 1024,
      timeout: 60_000,
    });
    const childStdout = Buffer.isBuffer(child.stdout)
      ? child.stdout
      : Buffer.from(child.stdout ?? "");
    const childStderr = Buffer.isBuffer(child.stderr)
      ? child.stderr
      : Buffer.from(child.stderr ?? "");
    let processResult = null;
    try {
      processResult = parseJsonBytesNoDuplicate(childStdout, {
        label: "matrix child process result",
        invalid_code: "EVIDENCE_WRITE_FAILED",
      });
    } catch {
      processResult = null;
    }
    const observedCode = typeof processResult?.reason_code === "string"
      ? processResult.reason_code
      : "EVIDENCE_WRITE_FAILED";
    const observedStatus = ["PASS", "NON_PASS"].includes(processResult?.status)
      ? processResult.status
      : "NON_PASS";
    const persistence = observedStatus === "PASS" ? "ADMITTED" : "NONE";
    const childIdentityValid =
      processResult !== null
      && sameJson(
        Object.keys(processResult).sort(),
        [
          "case_id",
          "input_identity",
          "reason_code",
          "schema_version",
          "status",
          "task_id",
        ],
      )
      && childStdout.equals(canonicalBytes(processResult))
      && childStderr.length === 0
      && child.signal === null
      && Number.isSafeInteger(child.pid)
      && child.pid > 0
      && child.pid !== process.pid
      && child.status === (observedStatus === "PASS" ? 0 : 1)
      && processResult?.schema_version === CASE_PROCESS_RESULT_SCHEMA
      && processResult?.task_id === TASK_ID
      && processResult?.case_id === caseEntry.case_id
      && sameJson(processResult?.input_identity, {
        byte_length: inputIdentity.byte_length,
        sha256: inputIdentity.sha256,
      });
    const oracleMatched =
      observedCode === caseEntry.expected_reason_code
      && observedStatus === caseEntry.expected_status
      && persistence === caseEntry.expected_persistence;
    if (childIdentityValid && oracleMatched) {
      caseDecisions.push({
        caseEntry,
        material,
        observedStatus,
        observedCode,
      });
    }
    if (!childIdentityValid || !oracleMatched) {
      oracleDivergences.push({
        case_id: caseEntry.case_id,
        expected_status: caseEntry.expected_status,
        expected_reason_code: caseEntry.expected_reason_code,
        expected_persistence: caseEntry.expected_persistence,
        observed_status: observedStatus,
        observed_reason_code: observedCode,
        observed_persistence: persistence,
        child_identity_valid: childIdentityValid,
      });
    }
    const stdoutIdentity = writeCaseBytes(
      handle,
      caseEntry.case_id,
      "process/stdout.log",
      childStdout,
    );
    const stderrIdentity = writeCaseBytes(
      handle,
      caseEntry.case_id,
      "process/stderr.log",
      childStderr,
    );
    const stoppedAt = new Date().toISOString();
    const processRecord = {
      argv: [process.execPath, ...childArgv],
      environment: closedChildEnvironment(),
      parent_pid: process.pid,
      pid: child.pid,
      exit_status: Number.isSafeInteger(child.status) ? child.status : 2,
      signal: child.signal ?? null,
      started_at: startedAt,
      stopped_at: stoppedAt,
      stdout: stdoutIdentity,
      stderr: stderrIdentity,
    };
    assertCritical(
      sameJson(Object.keys(processRecord).sort(), [...PROCESS_KEYS].sort()),
      "EVIDENCE_WRITE_FAILED",
      "case process record key set drifted",
    );
    const casePrefix = `raw/matrix-process/${caseEntry.case_id}/`;
    const identities = listClosedFiles(
      join(handle.root, "raw/matrix-process", caseEntry.case_id),
    )
      .map((entry) => identityWithPath(handle.root, `${casePrefix}${entry.path}`))
      .sort((left, right) => left.path.localeCompare(right.path));
    assertCritical(
      identities.some((identity) => identity.path === inputIdentity.path),
      "CLOSED_INVENTORY_DRIFT",
      "case input is absent from case identity list",
    );
    const observation = {
      schema_version: CASE_OBSERVATION_SCHEMA,
      task_id: TASK_ID,
      case_id: caseEntry.case_id,
      status: observedStatus,
      reason_code: observedCode,
      persistence,
      process: processRecord,
      identities,
      external_effects: FALSE_EXTERNAL_EFFECTS,
    };
    writeCaseJson(handle, caseEntry.case_id, "observation.json", observation);
    observations.push(observation);
  }
  assertCritical(
    observations.length === flattenCases(matrix).length,
    "ACCOUNTING_MISMATCH",
    "matrix did not enumerate every frozen case",
  );
  const persistenceDivergences = [];
  for (const decision of caseDecisions) {
    try {
      const decisionAccounting = await persistMatrixDecision(
        handle,
        decision.caseEntry,
        decision.observedStatus,
        decision.observedCode,
        bases,
        decision.material,
      );
      if (decision.observedStatus === "NON_PASS") {
        expectedNonPassCases.push({
          case_id: decision.caseEntry.case_id,
          root: `raw/cases/${decision.caseEntry.case_id}`,
          failure_receipt_path:
            `raw/cases/${decision.caseEntry.case_id}/safe-failure-receipt.json`,
        });
      }
      for (const key of Object.keys(accounting)) {
        accounting[key] += decisionAccounting[key];
      }
    } catch (error) {
      persistenceDivergences.push({
        case_id: decision.caseEntry.case_id,
        expected_status: "PERSISTED",
        expected_reason_code: "PASS",
        observed_status: "NON_PASS",
        observed_reason_code: isCriticalReasonCode(error?.code)
          ? error.code
          : "EVIDENCE_WRITE_FAILED",
      });
    }
  }
  const matchedCaseIds = new Set(
    caseDecisions.map((decision) => decision.caseEntry.case_id),
  );
  const skippedCaseIds = observations
    .map((observation) => observation.case_id)
    .filter((caseId) => !matchedCaseIds.has(caseId));
  const divergences = [
    ...oracleDivergences.map((entry) => ({
      stage: "DECISION",
      case_id: entry.case_id,
      expected_status: entry.expected_status,
      expected_reason_code: entry.expected_reason_code,
      observed_status: entry.observed_status,
      observed_reason_code: entry.observed_reason_code,
    })),
    ...persistenceDivergences.map((entry) => ({
      stage: "PERSISTENCE",
      ...entry,
    })),
  ];
  if (
    divergences.length !== 0
    || skippedCaseIds.length !== 0
    || caseDecisions.length !== observations.length
  ) {
    failCritical(
      "ACCOUNTING_MISMATCH",
      "matrix decision and persistence divergences after complete enumeration",
      {
        divergences,
        skipped_case_ids: skippedCaseIds,
      },
    );
  }
  return { observations, accounting, expectedNonPassCases };
}

function writeHistoricalRootCauseRegressionReceipt(
  handle,
  matrixRun,
  synthetic,
) {
  const byCase = new Map(
    matrixRun.observations.map((entry) => [entry.case_id, entry]),
  );
  const exactCase = (caseId, status, reasonCode) => {
    const observed = byCase.get(caseId);
    return observed?.status === status
      && observed.reason_code === reasonCode;
  };
  const profileRoot = join(handle.root, "raw/profile-verification");
  const profileRootStat = lstatSync(profileRoot);
  const profileVerificationParent =
    profileRootStat.isDirectory()
    && !profileRootStat.isSymbolicLink()
    && synthetic.profileReceipts.length === PROFILE_ORDER.length
    && synthetic.profileReceipts.every((receipt) => receipt.status === "PASS");
  const fullSpinePrefix =
    "raw/cases/USAGE_OUTPUT_2048_FULL_SPINE";
  const typedFullSpine =
    exactCase("USAGE_OUTPUT_2048_FULL_SPINE", "PASS", "PASS")
    && existsSync(join(handle.root, fullSpinePrefix, "cell-closure.json"))
    && EXECUTION_ARTIFACT_KEYS.every((artifactName) => (
      existsSync(join(handle.root, fullSpinePrefix, "spine", artifactName))
    ));
  const regressions = {
    profile_verification_parent:
      profileVerificationParent ? "PASS" : "NON_PASS",
    forged_observer_empty_row_precedence:
      exactCase(
        "OBSERVER_FORGED",
        "NON_PASS",
        "OBSERVER_EVIDENCE_FORGED",
      ) ? "PASS" : "NON_PASS",
    inventory_ordering:
      (
        exactCase(
          "INVENTORY_EXTRA",
          "NON_PASS",
          "CLOSED_INVENTORY_DRIFT",
        )
        && exactCase(
          "INVENTORY_REORDER",
          "NON_PASS",
          "ORDERED_IDENTITY_SET_INVALID",
        )
      ) ? "PASS" : "NON_PASS",
    non_regular_before_hardlink_precedence:
      (
        exactCase(
          "FILESYSTEM_NON_REGULAR_FILE",
          "NON_PASS",
          "NON_REGULAR_FILE_REJECTED",
        )
        && exactCase(
          "FILESYSTEM_HARDLINK",
          "NON_PASS",
          "HARDLINK_REJECTED",
        )
      ) ? "PASS" : "NON_PASS",
    typed_2048_full_spine_stimulus:
      typedFullSpine ? "PASS" : "NON_PASS",
  };
  assertCritical(
    matrixRun.observations.length === 99
      && Object.values(regressions).every((status) => status === "PASS"),
    "ACCOUNTING_MISMATCH",
    "P1-165 five historical root-cause regressions did not all close",
  );
  const receipt = {
    schema_version: "p1-168-p1-165-root-cause-regression-receipt/v1",
    task_id: TASK_ID,
    matrix_cases_enumerated_once: matrixRun.observations.length,
    regressions,
    status: "PASS",
  };
  const identity = writeJsonCreateOnce(
    handle,
    "raw/historical-root-cause-regression-receipt.json",
    receipt,
  );
  return { receipt, identity };
}

function adapterResultPath(outputRoot, taskId, profileId) {
  return join(
    outputRoot,
    "positive",
    taskId,
    profileId,
    "worker-output",
    "adapter-result.json",
  );
}

function assertExactDirectoryInventory(
  root,
  { label, files, directories },
) {
  const rootIdentity = directoryIdentity(root, label);
  const entries = boundedDirectoryEntries(
    root,
    label,
    files.length + directories.length,
  );
  assertCritical(
    sameJson(
      entries.map((entry) => entry.name),
      [...files, ...directories].sort(),
    ),
    "CLOSED_INVENTORY_DRIFT",
    `${label} names differ from the closed inventory`,
  );
  for (const entry of entries) {
    const stat = lstatSync(join(root, entry.name));
    const expectedFile = files.includes(entry.name);
    const expectedDirectory = directories.includes(entry.name);
    assertCritical(
      !stat.isSymbolicLink()
        && stat.dev === rootIdentity.dev
        && stat.uid === rootIdentity.uid
        && (
          (expectedFile && stat.isFile() && stat.nlink === 1)
          || (expectedDirectory
            && stat.isDirectory()
            && realpathSync(join(root, entry.name)) === join(root, entry.name))
        ),
      stat.isSymbolicLink()
        ? "SYMLINK_REJECTED"
        : "CLOSED_INVENTORY_DRIFT",
      `${label} entry type or ownership drifted`,
    );
  }
}

function buildAcceptedAdapterProofPlan(outputRoot) {
  directoryIdentity(outputRoot, "accepted adapter matrix root");
  const cases = {};
  let fileCount = 0;
  let totalBytes = 0;
  let maximumObservedDepth = 0;
  const add = (plan) => {
    fileCount += 1;
    totalBytes += plan.byte_length;
    maximumObservedDepth = Math.max(maximumObservedDepth, plan.depth);
    assertCritical(
      fileCount <= PROOF_FILE_MAX_COUNT
        && totalBytes <= PROOF_TOTAL_MAX_BYTES
        && maximumObservedDepth <= PROOF_MAX_DEPTH,
      "RESOURCE_LIMIT_EXCEEDED",
      "accepted adapter proof set exceeds its global pre-read limits",
    );
  };
  for (const taskId of ACCEPTED_TASK_IDS) {
    for (const profileId of PROFILE_ORDER) {
      const key = `${taskId}:${profileId}`;
      const adapterId = profileId.slice(0, 2);
      const sourceCaseRoot = join(
        outputRoot,
        "positive",
        taskId,
        profileId,
      );
      const workerRoot = join(sourceCaseRoot, "worker-output");
      assertExactDirectoryInventory(sourceCaseRoot, {
        label: `accepted adapter positive root ${key}`,
        files: [
          "b0-result.json",
          "b1-program.json",
          "environment-snapshot.json",
          "execution-descriptor.json",
          "request.json",
        ],
        directories: ["worker-output"],
      });
      assertExactDirectoryInventory(workerRoot, {
        label: `accepted adapter worker root ${key}`,
        files: [
          "adapter-command-ledger.json",
          "adapter-execution-request.json",
          "adapter-result.json",
          "run-record.json",
          "stable-projection.json",
          "target-executed",
          "trace.jsonl",
        ],
        directories: adapterId === "B0" ? [] : ["work"],
      });
      const fixed = {};
      for (const sourceRelativePath of Object.values(
        ACCEPTED_ADAPTER_PROOF_FILES,
      )) {
        const plan = planRegularFileWithinRoot(
          sourceCaseRoot,
          sourceRelativePath,
          {
            label: `accepted adapter fixed proof ${key}`,
            maximumBytes: PROOF_FILE_MAX_BYTES,
          },
        );
        fixed[sourceRelativePath] = plan;
        add(plan);
      }
      let b2 = null;
      if (adapterId === "B2") {
        const workRoot = join(workerRoot, "work");
        assertExactDirectoryInventory(workRoot, {
          label: `accepted B2 work root ${key}`,
          files: [],
          directories: [
            "b2-cargo-target",
            "b2-p0-analyzer",
            "b2-scan-source",
          ],
        });
        const executable = planRegularFileWithinRoot(
          sourceCaseRoot,
          "worker-output/work/b2-cargo-target/debug/sourcelens-analyzer",
          {
            label: `accepted B2 executable ${key}`,
            maximumBytes: B2_BINARY_MAX_BYTES,
          },
        );
        const analyzer = boundedTreePlan(
          join(workRoot, "b2-p0-analyzer"),
          {
            label: `accepted B2 analyzer source ${key}`,
            maximumFiles: B2_TREE_FILE_MAX_COUNT,
            maximumTotalBytes: B2_TREE_TOTAL_MAX_BYTES,
            maximumFileBytes: B2_TREE_FILE_MAX_BYTES,
            maximumDepth: B2_TREE_MAX_DEPTH,
          },
        );
        const scanSource = boundedTreePlan(
          join(workRoot, "b2-scan-source"),
          {
            label: `accepted B2 scan source ${key}`,
            maximumFiles: B2_TREE_FILE_MAX_COUNT,
            maximumTotalBytes: B2_TREE_TOTAL_MAX_BYTES,
            maximumFileBytes: B2_TREE_FILE_MAX_BYTES,
            maximumDepth: B2_TREE_MAX_DEPTH,
          },
        );
        assertCritical(
          analyzer.file_count === 10
            && (
              scanSource.file_count === 3
              || scanSource.file_count === 4
            ),
          "CLOSED_INVENTORY_DRIFT",
          `accepted B2 bounded physical inventory drifted: ${key}`,
        );
        add(executable);
        const analyzerFiles = analyzer.files.map((entry) => {
          const plan = planRegularFileWithinRoot(
            sourceCaseRoot,
            `worker-output/work/b2-p0-analyzer/${entry.relative_path}`,
            {
              label: `accepted B2 analyzer proof ${key}`,
              maximumBytes: B2_TREE_FILE_MAX_BYTES,
            },
          );
          add(plan);
          return plan;
        });
        const scanSourceFiles = scanSource.files.map((entry) => {
          const plan = planRegularFileWithinRoot(
            sourceCaseRoot,
            `worker-output/work/b2-scan-source/${entry.relative_path}`,
            {
              label: `accepted B2 scan-source proof ${key}`,
              maximumBytes: B2_TREE_FILE_MAX_BYTES,
            },
          );
          add(plan);
          return plan;
        });
        b2 = {
          executable,
          analyzer,
          analyzer_files: analyzerFiles,
          scan_source: scanSource,
          scan_source_files: scanSourceFiles,
        };
      }
      cases[key] = { source_case_root: sourceCaseRoot, fixed, b2 };
    }
  }
  assertCritical(
    Object.keys(cases).length === 36
      && fileCount > 0
      && totalBytes > 0,
    "CLOSED_INVENTORY_DRIFT",
    "accepted adapter proof plan is incomplete",
  );
  return {
    cases,
    receipt: {
      schema_version: "p1-165-accepted-adapter-proof-limits/v1",
      task_id: TASK_ID,
      source_matrix_root: outputRoot,
      case_count: 36,
      planned_file_count: fileCount,
      planned_total_byte_length: totalBytes,
      maximum_observed_depth: maximumObservedDepth,
      limits: {
        proof_file_max_bytes: PROOF_FILE_MAX_BYTES,
        proof_total_max_bytes: PROOF_TOTAL_MAX_BYTES,
        proof_file_max_count: PROOF_FILE_MAX_COUNT,
        proof_max_depth: PROOF_MAX_DEPTH,
        b2_tree_file_max_bytes: B2_TREE_FILE_MAX_BYTES,
        b2_tree_total_max_bytes: B2_TREE_TOTAL_MAX_BYTES,
        b2_tree_file_max_count: B2_TREE_FILE_MAX_COUNT,
        b2_tree_max_depth: B2_TREE_MAX_DEPTH,
        b2_binary_max_bytes: B2_BINARY_MAX_BYTES,
      },
      planning_mode: "METADATA_ONLY_BEFORE_ANY_PROOF_CONTENT_READ",
      status: "PASS",
    },
  };
}

function readPlannedRegularFile(plan, label) {
  const beforeRoot = directoryIdentity(plan.root_identity.path, `${label} root`);
  const before = lstatSync(plan.absolute_path);
  assertCritical(
    before.isFile()
      && !before.isSymbolicLink()
      && before.nlink === 1
      && before.dev === plan.dev
      && before.ino === plan.ino
      && before.uid === plan.uid
      && before.size === plan.byte_length
      && (before.mode & 0o777) === plan.mode
      && beforeRoot.dev === plan.root_identity.dev
      && beforeRoot.ino === plan.root_identity.ino
      && beforeRoot.uid === plan.root_identity.uid,
    "IDENTITY_MISMATCH",
    `${label} drifted after its bounded pre-read plan`,
  );
  let descriptor = null;
  try {
    descriptor = openSync(
      plan.absolute_path,
      fsConstants.O_RDONLY
        | (fsConstants.O_NOFOLLOW ?? 0)
        | (fsConstants.O_NONBLOCK ?? 0),
    );
    const opened = fstatSync(descriptor);
    assertCritical(
      opened.isFile()
        && opened.dev === plan.dev
        && opened.ino === plan.ino
        && opened.uid === plan.uid
        && opened.nlink === 1
        && opened.size === plan.byte_length
        && (opened.mode & 0o777) === plan.mode,
      "IDENTITY_MISMATCH",
      `${label} changed while opening its bounded descriptor`,
    );
    const bytes = readFileSync(descriptor);
    const afterFd = fstatSync(descriptor);
    const afterPath = lstatSync(plan.absolute_path);
    const afterRoot = directoryIdentity(plan.root_identity.path, `${label} root`);
    assertCritical(
      bytes.length === plan.byte_length
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
        && afterRoot.dev === beforeRoot.dev
        && afterRoot.ino === beforeRoot.ino
        && afterRoot.uid === beforeRoot.uid
        && plan.ancestor_identities.every((ancestor) => {
          const observed = directoryIdentity(
            ancestor.path,
            `${label} ancestor`,
          );
          return observed.dev === ancestor.dev
            && observed.ino === ancestor.ino
            && observed.uid === ancestor.uid;
        }),
      "IDENTITY_MISMATCH",
      `${label} changed during its bounded no-follow read`,
    );
    return bytes;
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    failCritical(
      error?.code === "ELOOP"
        ? "SYMLINK_REJECTED"
        : "IDENTITY_MISMATCH",
      `${label} could not be read through its bounded descriptor`,
    );
  } finally {
    if (descriptor !== null) closeSync(descriptor);
  }
}

function readAcceptedP129Artifact(handle, role, expected) {
  const plan = planRegularFileWithinRoot(
    ACCEPTED_P1_129_TASK_ROOT,
    expected.relative_path,
    {
      label: `accepted P1-129 ${role}`,
      maximumBytes: 256 * 1024,
      maximumDepth: 4,
    },
  );
  assertCritical(
    plan.byte_length === expected.byte_length,
    "IDENTITY_MISMATCH",
    `accepted P1-129 ${role} byte length drifted`,
  );
  const bytes = readPlannedRegularFile(
    plan,
    `accepted P1-129 ${role}`,
  );
  assertCritical(
    bytes.length === expected.byte_length
      && sha256(bytes) === expected.sha256,
    "IDENTITY_MISMATCH",
    `accepted P1-129 ${role} exact identity drifted`,
  );
  const sourceIdentity = {
    path: plan.absolute_path,
    type: "REGULAR_FILE",
    nlink: 1,
    byte_length: bytes.length,
    sha256: sha256(bytes),
  };
  const stagedIdentity = writeBytesCreateOnce(
    handle,
    `raw/accepted-adapter-control/accepted-p1-129/${role}`,
    bytes,
  );
  return { bytes, sourceIdentity, stagedIdentity };
}

function bindAcceptedP129Authority(handle) {
  const artifacts = Object.fromEntries(
    Object.entries(ACCEPTED_P1_129_ARTIFACTS).map(([role, expected]) => [
      role,
      readAcceptedP129Artifact(handle, role, expected),
    ]),
  );
  const terminal = parseJsonBytesNoDuplicate(
    artifacts.terminal_receipt.bytes,
    { label: "accepted P1-129 terminal receipt" },
  );
  const formalSummary = parseJsonBytesNoDuplicate(
    artifacts.formal_summary.bytes,
    { label: "accepted P1-129 formal summary" },
  );
  assertCritical(
    terminal.schema_version === "p1-129-terminal-receipt/v1"
      && terminal.task_id
        === "AIOS-P1-129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION"
      && terminal.status === "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
      && terminal.candidate.commit === ACCEPTED_P1_129_CANDIDATE_COMMIT
      && terminal.candidate.tree === ACCEPTED_P1_129_CANDIDATE_TREE
      && terminal.candidate.manifest_sha256
        === ACCEPTED_P1_129_ARTIFACTS.candidate_manifest.sha256
      && terminal.fresh_reviews.cto.target_verdict === "PASS"
      && terminal.fresh_reviews.cto.sha256
        === ACCEPTED_P1_129_ARTIFACTS.cto_review.sha256
      && terminal.fresh_reviews.security.target_verdict === "PASS"
      && terminal.fresh_reviews.security.sha256
        === ACCEPTED_P1_129_ARTIFACTS.security_review.sha256
      && terminal.fresh_reviews.quality.target_verdict === "PASS"
      && terminal.fresh_reviews.quality.sha256
        === ACCEPTED_P1_129_ARTIFACTS.quality_review.sha256
      && terminal.verification.positive_runs === 36
      && terminal.verification.b2_real_p0_scan_children === 12
      && terminal.verification.negative_cases === 53
      && terminal.verification.false_accepts === 0
      && terminal.verification.external_effects_all_false === true
      && terminal.verification.canonical_make_verify === "PASS"
      && terminal.integration.canonical_commit
        === ACCEPTED_P1_129_CANDIDATE_COMMIT
      && terminal.integration.canonical_tree
        === ACCEPTED_P1_129_CANDIDATE_TREE,
    "IDENTITY_MISMATCH",
    "accepted P1-129 terminal authority facts drifted",
  );
  assertCritical(
    formalSummary.status === "PASS"
      && formalSummary.output_root === ACCEPTED_P1_129_FORMAL_ROOT
      && formalSummary.positive_runs === 36
      && formalSummary.distinct_positive_run_roots === 36
      && formalSummary.negative_cases === 53
      && formalSummary.false_accepts === 0
      && formalSummary.b2_real_repository_analysis_scan_children === 12
      && Object.values(formalSummary.external_effects)
        .every((value) => value === false),
    "IDENTITY_MISMATCH",
    "accepted P1-129 formal summary facts drifted",
  );
  const receipt = {
    schema_version: "p1-165-accepted-p1-129-authority-bundle/v1",
    task_id: TASK_ID,
    accepted_task_id:
      "AIOS-P1-129_EXACT_INPUT_BOUNDARY_SECURITY_MATRIX_COMPLETION",
    accepted_candidate_commit: ACCEPTED_P1_129_CANDIDATE_COMMIT,
    accepted_candidate_tree: ACCEPTED_P1_129_CANDIDATE_TREE,
    source_task_root: directoryIdentity(
      ACCEPTED_P1_129_TASK_ROOT,
      "accepted P1-129 task root",
    ),
    source_formal_root: directoryIdentity(
      ACCEPTED_P1_129_FORMAL_ROOT,
      "accepted P1-129 formal root",
    ),
    artifacts: Object.fromEntries(
      Object.entries(artifacts).map(([role, artifact]) => [
        role,
        {
          source_identity: artifact.sourceIdentity,
          staged_identity: artifact.stagedIdentity,
        },
      ]),
    ),
    accepted_counts: {
      positive_runs: 36,
      b2_real_repository_analysis_scan_children: 12,
      negative_cases: 53,
      false_accepts: 0,
    },
    historical_reviewed_binary_exact_bytes_claim: false,
    cooperative_local_accepted_evidence_path_residual: true,
    hostile_global_read_isolation_claim: false,
    hostile_process_isolation_claim: false,
    trusted_accepted_source_required: true,
    residual_disclosure:
      "P1-129 reviews bind the accepted formal path and exact summary, "
      + "negative-result, candidate, review and terminal identities, but do "
      + "not independently closed-hash every historical binary byte.",
    claim_boundary:
      "COOPERATIVE_LOCAL_ACCEPTED_P1_129_PATH_PLUS_CURRENT_SELECTED_INVENTORY",
    status: "PASS",
  };
  const receiptIdentity = writeJsonCreateOnce(
    handle,
    "raw/accepted-adapter-control/accepted-p1-129/authority-bundle.json",
    receipt,
  );
  return {
    formalSummary,
    receipt,
    receiptIdentity,
  };
}

function readCanonicalTaskSpec(taskId, requestDescriptor) {
  assertCritical(
    ACCEPTED_TASK_IDS.includes(taskId),
    "TASK_IDENTITY_MISMATCH",
    "TaskSpec task ID is outside the canonical accepted dataset",
  );
  const expectedProvenancePath = join(
    ACCEPTED_P1_129_DATASET_PROVENANCE_ROOT,
    taskId,
    "task-spec.json",
  );
  const expectedPath = join(
    ACCEPTED_DATASET_TASK_ROOT,
    taskId,
    "task-spec.json",
  );
  assertCritical(
    requestDescriptor !== null
      && typeof requestDescriptor === "object"
      && !Array.isArray(requestDescriptor)
      && sameJson(
        Object.keys(requestDescriptor).sort(),
        ["byte_length", "path", "sha256"],
      )
      && requestDescriptor.path === expectedProvenancePath
      && Number.isSafeInteger(requestDescriptor.byte_length)
      && requestDescriptor.byte_length >= 0
      && requestDescriptor.byte_length <= TASK_SPEC_MAX_BYTES
      && /^[0-9a-f]{64}$/.test(requestDescriptor.sha256),
    "EVIDENCE_CROSS_BINDING_INVALID",
    "request TaskSpec descriptor is not the exact accepted provenance path",
  );
  const plan = planRegularFileWithinRoot(
    ACCEPTED_DATASET_TASK_ROOT,
    `${taskId}/task-spec.json`,
    {
      label: `canonical TaskSpec ${taskId}`,
      maximumBytes: TASK_SPEC_MAX_BYTES,
      maximumDepth: 2,
    },
  );
  assertCritical(
    plan.absolute_path === expectedPath
      && plan.byte_length === requestDescriptor.byte_length,
    "EVIDENCE_CROSS_BINDING_INVALID",
    "canonical TaskSpec metadata differs from accepted provenance",
  );
  const bytes = readPlannedRegularFile(plan, `canonical TaskSpec ${taskId}`);
  assertCritical(
    bytes.length === requestDescriptor.byte_length
      && sha256(bytes) === requestDescriptor.sha256,
    "EVIDENCE_CROSS_BINDING_INVALID",
    "canonical TaskSpec bytes differ from accepted provenance",
  );
  const value = parseJsonBytesNoDuplicate(bytes, {
    label: `canonical TaskSpec ${taskId}`,
  });
  assertCritical(
    value.schema_version === TASK_SPEC_SCHEMA_VERSION
      && value.task_id === taskId,
    "TASK_IDENTITY_MISMATCH",
    "canonical TaskSpec schema or task identity drifted",
  );
  return {
    value,
    identity: {
      path: expectedPath,
      type: "REGULAR_FILE",
      nlink: 1,
      byte_length: bytes.length,
      sha256: sha256(bytes),
    },
  };
}

function writeProofBytesCreateOnce(handle, relativePath, bytes) {
  const normalized = validateArtifactPath(relativePath, "adapter proof path");
  const rootStat = lstatSync(handle.root);
  assertCritical(
    Buffer.isBuffer(bytes) && bytes.length <= PROOF_FILE_MAX_BYTES,
    "RESPONSE_TOO_LARGE",
    "adapter proof artifact exceeds the bounded per-file limit",
  );
  assertCritical(
    rootStat.isDirectory()
      && !rootStat.isSymbolicLink()
      && rootStat.dev === handle.dev
      && rootStat.ino === handle.ino
      && rootStat.uid === process.getuid()
      && realpathSync(handle.root) === handle.root,
    "PATH_ESCAPE_REJECTED",
    "adapter proof root identity is invalid",
  );
  const destination = resolve(handle.root, ...normalized.split("/"));
  const relativeDestination = relative(handle.root, destination);
  assertCritical(
    relativeDestination !== ""
      && relativeDestination !== ".."
      && !relativeDestination.startsWith(`..${sep}`)
      && !isAbsolute(relativeDestination),
    "PATH_ESCAPE_REJECTED",
    "adapter proof path escapes the owned Evidence stage",
  );
  let current = handle.root;
  const parentIdentities = [];
  for (const component of dirname(normalized).split("/")) {
    if (component === ".") continue;
    current = join(current, component);
    if (!existsSync(current)) {
      mkdirSync(current, { recursive: false, mode: 0o700 });
      chmodSync(current, 0o700);
    }
    const stat = lstatSync(current);
    assertCritical(
      stat.isDirectory()
        && !stat.isSymbolicLink()
        && stat.dev === handle.dev
        && stat.uid === rootStat.uid
        && realpathSync(current) === current,
      stat.isSymbolicLink()
        ? "SYMLINK_REJECTED"
        : "PATH_ESCAPE_REJECTED",
      "adapter proof parent is not one owned same-filesystem directory",
    );
    parentIdentities.push({
      path: current,
      dev: stat.dev,
      ino: stat.ino,
      uid: stat.uid,
    });
  }
  let descriptor = null;
  try {
    descriptor = openSync(
      destination,
      fsConstants.O_CREAT
        | fsConstants.O_EXCL
        | fsConstants.O_WRONLY
        | (fsConstants.O_NOFOLLOW ?? 0),
      0o600,
    );
    fchmodSync(descriptor, 0o600);
    writeFileSync(descriptor, bytes);
    fsyncSync(descriptor);
    const opened = fstatSync(descriptor);
    const observed = lstatSync(destination);
    const rootAfter = lstatSync(handle.root);
    assertCritical(
      opened.isFile()
        && opened.nlink === 1
        && opened.size === bytes.length
        && opened.dev === handle.dev
        && opened.uid === rootStat.uid
        && (opened.mode & 0o777) === 0o600
        && observed.isFile()
        && !observed.isSymbolicLink()
        && observed.nlink === 1
        && observed.dev === opened.dev
        && observed.ino === opened.ino
        && observed.uid === opened.uid
        && observed.size === bytes.length
        && rootAfter.isDirectory()
        && !rootAfter.isSymbolicLink()
        && rootAfter.dev === rootStat.dev
        && rootAfter.ino === rootStat.ino
        && rootAfter.uid === rootStat.uid
        && realpathSync(handle.root) === handle.root
        && parentIdentities.every((parent) => {
          const after = lstatSync(parent.path);
          return after.isDirectory()
            && !after.isSymbolicLink()
            && after.dev === parent.dev
            && after.ino === parent.ino
            && after.uid === parent.uid
            && realpathSync(parent.path) === parent.path;
        }),
      "IDENTITY_MISMATCH",
      "adapter proof artifact drifted during create-once persistence",
    );
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    failCritical(
      error?.code === "EEXIST"
        ? "CREATE_ONCE_FAILED"
        : error?.code === "ELOOP"
          ? "SYMLINK_REJECTED"
          : "EVIDENCE_WRITE_FAILED",
      `adapter proof persistence failed: ${error?.code ?? error?.message}`,
    );
  } finally {
    if (descriptor !== null) closeSync(descriptor);
  }
  return { path: normalized, ...bytesIdentity(bytes) };
}

function copyAdapterProofArtifact({
  handle,
  sourceCaseRoot,
  proofPrefix,
  sourceRelativePath,
  expectedPlan,
  includeSourceMode = false,
  includeBytes = false,
}) {
  const normalizedSource = validateArtifactPath(
    sourceRelativePath,
    "accepted adapter proof source path",
  );
  const sourcePath = join(
    sourceCaseRoot,
    ...normalizedSource.split("/"),
  );
  assertCritical(
    expectedPlan !== null
      && typeof expectedPlan === "object"
      && expectedPlan.root_identity.path === sourceCaseRoot
      && expectedPlan.relative_path === normalizedSource
      && expectedPlan.absolute_path === sourcePath
      && expectedPlan.byte_length <= PROOF_FILE_MAX_BYTES,
    "RESOURCE_LIMIT_EXCEEDED",
    `accepted adapter proof lacks its global pre-read plan: ${normalizedSource}`,
  );
  const sourceRootStat = lstatSync(sourceCaseRoot);
  assertCritical(
    sourceRootStat.isDirectory()
      && !sourceRootStat.isSymbolicLink()
      && sourceRootStat.uid === process.getuid()
      && realpathSync(sourceCaseRoot) === sourceCaseRoot
      && relative(sourceCaseRoot, sourcePath) === normalizedSource,
    "PATH_ESCAPE_REJECTED",
    `accepted adapter proof source root is unsafe: ${normalizedSource}`,
  );
  const ancestors = [];
  let current = sourceCaseRoot;
  for (const component of dirname(normalizedSource).split("/")) {
    if (component === ".") continue;
    current = join(current, component);
    const stat = lstatSync(current);
    assertCritical(
      stat.isDirectory()
        && !stat.isSymbolicLink()
        && stat.dev === sourceRootStat.dev
        && stat.uid === sourceRootStat.uid
        && realpathSync(current) === current,
      stat.isSymbolicLink()
        ? "SYMLINK_REJECTED"
        : "PATH_ESCAPE_REJECTED",
      `accepted adapter proof source ancestor is unsafe: ${normalizedSource}`,
    );
    ancestors.push({
      path: current,
      dev: stat.dev,
      ino: stat.ino,
      uid: stat.uid,
    });
  }
  const before = lstatSync(sourcePath);
  assertCritical(
    before.isFile()
      && !before.isSymbolicLink()
      && before.nlink === 1
      && before.dev === sourceRootStat.dev
      && before.uid === sourceRootStat.uid
      && before.dev === expectedPlan.dev
      && before.ino === expectedPlan.ino
      && before.uid === expectedPlan.uid
      && before.size === expectedPlan.byte_length
      && (before.mode & 0o777) === expectedPlan.mode,
    before.isSymbolicLink()
      ? "SYMLINK_REJECTED"
      : !before.isFile()
        ? "NON_REGULAR_FILE_REJECTED"
        : before.nlink !== 1
          ? "HARDLINK_REJECTED"
          : "NON_REGULAR_FILE_REJECTED",
    `accepted adapter proof source is unsafe: ${normalizedSource}`,
  );
  let sourceDescriptor = null;
  let bytes;
  try {
    sourceDescriptor = openSync(
      sourcePath,
      fsConstants.O_RDONLY
        | (fsConstants.O_NOFOLLOW ?? 0)
        | (fsConstants.O_NONBLOCK ?? 0),
    );
    const opened = fstatSync(sourceDescriptor);
    assertCritical(
      opened.isFile()
        && opened.dev === before.dev
        && opened.ino === before.ino
        && opened.uid === before.uid
        && opened.nlink === before.nlink
        && opened.size === before.size
        && (opened.mode & 0o777) === (before.mode & 0o777),
      "IDENTITY_MISMATCH",
      `accepted adapter proof source changed while opening: ${normalizedSource}`,
    );
    bytes = readFileSync(sourceDescriptor);
    const afterFd = fstatSync(sourceDescriptor);
    const afterPath = lstatSync(sourcePath);
    const rootAfter = lstatSync(sourceCaseRoot);
    assertCritical(
      afterFd.dev === opened.dev
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
        && rootAfter.isDirectory()
        && !rootAfter.isSymbolicLink()
        && rootAfter.dev === sourceRootStat.dev
        && rootAfter.ino === sourceRootStat.ino
        && rootAfter.uid === sourceRootStat.uid
        && realpathSync(sourceCaseRoot) === sourceCaseRoot
        && ancestors.every((ancestor) => {
          const observed = lstatSync(ancestor.path);
          return observed.isDirectory()
            && !observed.isSymbolicLink()
            && observed.dev === ancestor.dev
            && observed.ino === ancestor.ino
            && observed.uid === ancestor.uid
            && realpathSync(ancestor.path) === ancestor.path;
        }),
      "IDENTITY_MISMATCH",
      `accepted adapter proof source changed during read: ${normalizedSource}`,
    );
  } finally {
    if (sourceDescriptor !== null) closeSync(sourceDescriptor);
  }
  const identity = writeProofBytesCreateOnce(
    handle,
    `${proofPrefix}/${normalizedSource}`,
    bytes,
  );
  return includeSourceMode || includeBytes
    ? {
        identity,
        ...(includeSourceMode
          ? { source_mode: before.mode & 0o777 }
          : {}),
        ...(includeBytes ? { bytes } : {}),
      }
    : identity;
}

function copyB2PhysicalProof({
  handle,
  sourceCaseRoot,
  proofPrefix,
  adapterResult,
  b2Plan,
}) {
  const workerRoot = join(sourceCaseRoot, "worker-output");
  const executable = resolve(adapterResult.scan_ledger.argv[0]);
  const analyzerRoot = join(workerRoot, "work/b2-p0-analyzer");
  const scanSourceRoot = resolve(adapterResult.scan_ledger.argv[3]);
  assertCritical(
    relative(workerRoot, executable).split(sep).join("/") ===
      "work/b2-cargo-target/debug/sourcelens-analyzer"
      && relative(workerRoot, analyzerRoot).split(sep).join("/")
        === "work/b2-p0-analyzer"
      && relative(workerRoot, scanSourceRoot).split(sep).join("/")
        === "work/b2-scan-source",
    "PATH_ESCAPE_REJECTED",
    "B2 physical proof paths do not match the accepted fixed layout",
  );
  assertCritical(
    b2Plan !== null
      && typeof b2Plan === "object"
      && b2Plan.executable.absolute_path === executable
      && b2Plan.analyzer.file_count === 10
      && (
        b2Plan.scan_source.file_count === 3
        || b2Plan.scan_source.file_count === 4
      )
      && b2Plan.analyzer_files.length === 10
      && b2Plan.scan_source_files.length === b2Plan.scan_source.file_count,
    "RESOURCE_LIMIT_EXCEEDED",
    "B2 physical proof is not covered by the frozen pre-read plan",
  );
  const executableProof = copyAdapterProofArtifact({
    handle,
    sourceCaseRoot,
    proofPrefix,
    sourceRelativePath:
      "worker-output/work/b2-cargo-target/debug/sourcelens-analyzer",
    expectedPlan: b2Plan.executable,
    includeSourceMode: true,
    includeBytes: true,
  });
  const executableIdentity = executableProof.identity;
  const analyzerArtifactIdentities = b2Plan.analyzer_files.map((entry) =>
    copyAdapterProofArtifact({
      handle,
      sourceCaseRoot,
      proofPrefix,
      sourceRelativePath: entry.relative_path,
      expectedPlan: entry,
    })
  );
  const scanSourceCopies = b2Plan.scan_source_files.map((entry) =>
    copyAdapterProofArtifact({
      handle,
      sourceCaseRoot,
      proofPrefix,
      sourceRelativePath: entry.relative_path,
      expectedPlan: entry,
      includeBytes: true,
    })
  );
  const scanSourceIdentities = scanSourceCopies.map((entry) => entry.identity);
  const scanSourceInventory = scanSourceIdentities.map((identity) => ({
    relative_path: identity.path.split(
      "/worker-output/work/b2-scan-source/",
    )[1],
    sha256: identity.sha256,
    byte_length: identity.byte_length,
  }));
  assertCritical(
    executableIdentity.byte_length
        === adapterResult.actions[0].executable_byte_length
      && executableIdentity.sha256
        === adapterResult.actions[0].executable_sha256
      && analyzerArtifactIdentities.every((identity) => {
        const relativePath = identity.path.split(
          "/worker-output/work/b2-p0-analyzer/",
        )[1];
        const expected = adapterResult.materialized_analyzer.artifacts.find(
          (artifact) => artifact.relative_path === relativePath,
        );
        return expected !== undefined
          && identity.path.endsWith(
          `/worker-output/work/b2-p0-analyzer/${expected.relative_path}`,
          )
          && identity.byte_length === expected.byte_length
          && identity.sha256 === expected.sha256;
      })
      && sha256(
        Buffer.from(canonicalJson(scanSourceInventory), "utf8"),
      ) === adapterResult.actions[0].source_manifest_sha256,
    "IDENTITY_MISMATCH",
    "B2 copied physical proof does not match the raw adapter result",
  );
  return {
    proof: {
      executable_identity: executableIdentity,
      executable_source_mode: executableProof.source_mode,
      analyzer_artifact_identities: analyzerArtifactIdentities,
      scan_source_identities: scanSourceIdentities,
    },
    execution_material: {
      executable_bytes: executableProof.bytes,
      scan_source: scanSourceCopies.map((entry) => ({
        relative_path: entry.identity.path.split(
          "/worker-output/work/b2-scan-source/",
        )[1],
        bytes: entry.bytes,
      })),
    },
  };
}

function writeAcceptedBinaryDisposableFile(
  root,
  relativePath,
  bytes,
  mode,
) {
  const normalized = validateArtifactPath(
    relativePath,
    "accepted-binary disposable path",
  );
  assertCritical(
    Buffer.isBuffer(bytes)
      && bytes.length <= B2_BINARY_MAX_BYTES
      && [0o600, 0o700].includes(mode),
    "RESOURCE_LIMIT_EXCEEDED",
    "accepted-binary disposable artifact is invalid",
  );
  const rootIdentity = directoryIdentity(
    root,
    "accepted-binary disposable root",
  );
  const destination = join(root, ...normalized.split("/"));
  assertCritical(
    relative(root, destination).split(sep).join("/") === normalized,
    "PATH_ESCAPE_REJECTED",
    "accepted-binary disposable path escapes its root",
  );
  let current = root;
  for (const component of dirname(normalized).split("/")) {
    if (component === ".") continue;
    current = join(current, component);
    if (!existsSync(current)) {
      mkdirSync(current, { recursive: false, mode: 0o700 });
      chmodSync(current, 0o700);
    }
    const identity = directoryIdentity(
      current,
      "accepted-binary disposable ancestor",
    );
    assertCritical(
      identity.dev === rootIdentity.dev
        && identity.uid === rootIdentity.uid,
      "PATH_ESCAPE_REJECTED",
      "accepted-binary disposable ancestor crossed its root",
    );
  }
  writeFileSync(destination, bytes, { flag: "wx", mode });
  chmodSync(destination, mode);
  const plan = planRegularFileWithinRoot(root, normalized, {
    label: "accepted-binary disposable artifact",
    maximumBytes: B2_BINARY_MAX_BYTES,
    maximumDepth: B2_TREE_MAX_DEPTH + 2,
  });
  const observed = readPlannedRegularFile(
    plan,
    "accepted-binary disposable artifact",
  );
  assertCritical(
    observed.equals(bytes) && plan.mode === mode,
    "IDENTITY_MISMATCH",
    "accepted-binary disposable artifact drifted after persistence",
  );
  return {
    path: normalized,
    type: "REGULAR_FILE",
    nlink: 1,
    mode,
    ...bytesIdentity(bytes),
  };
}

function acceptedBinaryContentInventory(root, label) {
  const plan = boundedTreePlan(root, {
    label,
    maximumFiles: B2_TREE_FILE_MAX_COUNT,
    maximumTotalBytes: B2_TREE_TOTAL_MAX_BYTES,
    maximumFileBytes: B2_TREE_FILE_MAX_BYTES,
    maximumDepth: B2_TREE_MAX_DEPTH,
  });
  const entries = plan.files.map((entry) => {
    const bytes = readPlannedRegularFile(
      entry,
      `${label} ${entry.relative_path}`,
    );
    return {
      relative_path: entry.relative_path,
      type: "REGULAR_FILE",
      nlink: 1,
      mode: entry.mode,
      byte_length: bytes.length,
      sha256: sha256(bytes),
    };
  });
  const entrySetBytes = Buffer.from(canonicalJson(entries), "utf8");
  return {
    root_identity: directoryIdentity(root, label),
    file_count: entries.length,
    total_byte_length: entries.reduce(
      (total, entry) => total + entry.byte_length,
      0,
    ),
    entries,
    entry_set_sha256: sha256(entrySetBytes),
  };
}

function reexecuteAcceptedP129B2({
  handle,
  taskId,
  profileId,
  adapterResult,
  copiedPhysical,
  sandboxCalibrationIdentity,
}) {
  const prefix = [
    "raw/accepted-adapter-control/current-b2-reexecution",
    taskId,
    profileId,
  ].join("/");
  const fixture = createDisposableRoot("p1-165-current-b2-reexecution");
  const sourceRoot = join(fixture.root, "source");
  const syntheticHome = join(fixture.root, "synthetic-home");
  const executablePath = join(fixture.root, "sourcelens-analyzer");
  mkdirSync(sourceRoot, { recursive: false, mode: 0o700 });
  mkdirSync(syntheticHome, { recursive: false, mode: 0o700 });
  chmodSync(sourceRoot, 0o700);
  chmodSync(syntheticHome, 0o700);
  const executableIdentity = writeAcceptedBinaryDisposableFile(
    fixture.root,
    "sourcelens-analyzer",
    copiedPhysical.execution_material.executable_bytes,
    0o700,
  );
  const sourceIdentities = copiedPhysical.execution_material.scan_source
    .map((entry) => writeAcceptedBinaryDisposableFile(
      sourceRoot,
      entry.relative_path,
      entry.bytes,
      0o600,
    ));
  assertCritical(
    sourceIdentities.length > 0
      && sourceIdentities.length <= B2_TREE_FILE_MAX_COUNT
      && executableIdentity.sha256
        === copiedPhysical.proof.executable_identity.sha256
      && executableIdentity.byte_length
        === copiedPhysical.proof.executable_identity.byte_length
      && executableIdentity.sha256
        === adapterResult.actions[0].executable_sha256
      && executableIdentity.byte_length
        === adapterResult.actions[0].executable_byte_length,
    "IDENTITY_MISMATCH",
    `accepted P1-129 selected B2 executable drifted: ${taskId}:${profileId}`,
  );
  const sourceInventoryBefore = acceptedBinaryContentInventory(
    sourceRoot,
    `accepted P1-129 selected scan source ${taskId}:${profileId}`,
  );
  const expectedSourceInventory = copiedPhysical.proof
    .scan_source_identities
    .map((identity) => ({
      relative_path: identity.path.split(
        "/worker-output/work/b2-scan-source/",
      )[1],
      byte_length: identity.byte_length,
      sha256: identity.sha256,
    }))
    .sort((left, right) =>
      left.relative_path.localeCompare(right.relative_path)
    );
  assertCritical(
    sameJson(
      sourceInventoryBefore.entries.map((entry) => ({
        relative_path: entry.relative_path,
        byte_length: entry.byte_length,
        sha256: entry.sha256,
      })),
      expectedSourceInventory,
    )
      && sha256(
        Buffer.from(canonicalJson(expectedSourceInventory), "utf8"),
      ) === adapterResult.actions[0].source_manifest_sha256,
    "IDENTITY_MISMATCH",
    `accepted P1-129 selected B2 source drifted: ${taskId}:${profileId}`,
  );
  const sandbox = acceptedBinarySandboxProfile(
    fixture.root,
    syntheticHome,
    executablePath,
  );
  const profileIdentity = writeBytesCreateOnce(
    handle,
    `${prefix}/sandbox-profile.sb`,
    sandbox.profile_bytes,
  );
  const targetArgv = [
    executablePath,
    "scan",
    "--repo-path",
    sourceRoot,
  ];
  const argv = [
    SANDBOX_EXEC,
    "-p",
    sandbox.profile,
    ...targetArgv,
  ];
  const capture = captureAcceptedBinaryChild(
    argv,
    sandbox.environment,
    fixture.root,
    ACCEPTED_BINARY_EXECUTION_TIMEOUT_MS,
  );
  const persistedCapture = persistAcceptedBinaryCapture(
    handle,
    `${prefix}/process`,
    capture,
  );
  assertCritical(
    capture.error_code === null
      && capture.exit_status === 0
      && capture.signal === null
      && capture.timed_out === false
      && Number.isSafeInteger(capture.child_pid)
      && capture.child_pid > 0
      && capture.child_pid !== process.pid
      && capture.stdout.length > 0
      && capture.stdout.length <= PROOF_FILE_MAX_BYTES
      && capture.stderr.length <= PROOF_FILE_MAX_BYTES,
    "IDENTITY_MISMATCH",
    `current accepted-binary B2 scan failed: ${taskId}:${profileId}`,
  );
  const freshScanResult = parseJsonBytesNoDuplicate(capture.stdout, {
    label: `current accepted-binary B2 scan ${taskId}:${profileId}`,
  });
  const normalizedFresh = {
    ...freshScanResult,
    repo_path: "RELOCATED_SCAN_SOURCE",
  };
  const normalizedAccepted = {
    ...adapterResult.scan_result,
    repo_path: "RELOCATED_SCAN_SOURCE",
  };
  const sourceInventoryAfter = acceptedBinaryContentInventory(
    sourceRoot,
    `accepted P1-129 current scan source after ${taskId}:${profileId}`,
  );
  const executablePlanAfter = planRegularFileWithinRoot(
    fixture.root,
    "sourcelens-analyzer",
    {
      label: `accepted P1-129 current executable ${taskId}:${profileId}`,
      maximumBytes: B2_BINARY_MAX_BYTES,
      maximumDepth: 1,
    },
  );
  const executableBytesAfter = readPlannedRegularFile(
    executablePlanAfter,
    `accepted P1-129 current executable ${taskId}:${profileId}`,
  );
  assertCritical(
    sameJson(normalizedFresh, normalizedAccepted)
      && sameJson(sourceInventoryAfter, sourceInventoryBefore)
      && executableBytesAfter.equals(
        copiedPhysical.execution_material.executable_bytes,
      ),
    "IDENTITY_MISMATCH",
    `current accepted-binary B2 scan did not reproduce exactly: ${taskId}:${profileId}`,
  );
  const fixtureIdentity = sandbox.disposable_root_identity;
  cleanupOwnedRoot(fixture);
  assertCritical(
    !existsSync(fixture.root),
    "EVIDENCE_WRITE_FAILED",
    `current accepted-binary B2 fixture was not cleaned: ${taskId}:${profileId}`,
  );
  const receipt = {
    schema_version: "p1-165-current-b2-sandbox-reexecution/v1",
    task_id: TASK_ID,
    target_task_id: taskId,
    profile_id: profileId,
    source_accepted_executable_identity:
      copiedPhysical.proof.executable_identity,
    selected_executable_identity: {
      byte_length: executableIdentity.byte_length,
      sha256: executableIdentity.sha256,
    },
    selected_scan_source_inventory: expectedSourceInventory,
    selected_scan_source_inventory_sha256:
      sourceInventoryBefore.entry_set_sha256,
    sandbox_profile_identity: profileIdentity,
    sandbox_calibration_identity: sandboxCalibrationIdentity,
    target_argv: targetArgv,
    process: persistedCapture,
    source_inventory_before: sourceInventoryBefore,
    source_inventory_after: sourceInventoryAfter,
    fresh_scan_result_identity: {
      byte_length: capture.stdout.length,
      sha256: sha256(capture.stdout),
    },
    fresh_scan_matches_accepted_except_repo_relocation: true,
    executable_identity_unchanged: true,
    source_inventory_unchanged: true,
    fixture_root_identity: fixtureIdentity,
    cleanup_verified: {
      fixture_root_absent: true,
    },
    external_effects: FALSE_EXTERNAL_EFFECTS,
    historical_reviewed_binary_exact_bytes_claim: false,
    cooperative_local_accepted_evidence_path_residual: true,
    claim_boundary: sandbox.claim_boundary,
    hostile_global_read_isolation_claim: false,
    hostile_process_isolation_claim: false,
    trusted_accepted_source_required: true,
    runtime_verified: true,
    status: "PASS",
  };
  const receiptIdentity = writeJsonCreateOnce(
    handle,
    `${prefix}/receipt.json`,
    receipt,
  );
  return {
    receipt,
    receiptIdentity,
    childPid: capture.child_pid,
  };
}

function captureAcceptedBinaryChild(
  argv,
  environment,
  cwd,
  timeoutMs = 15_000,
) {
  const startedAt = new Date().toISOString();
  const result = spawnSync(argv[0], argv.slice(1), {
    cwd,
    encoding: null,
    env: environment,
    maxBuffer: 32 * 1024 * 1024,
    timeout: timeoutMs,
  });
  return {
    argv,
    cwd,
    environment,
    parent_pid: process.pid,
    child_pid: result.pid,
    exit_status: result.status,
    signal: result.signal,
    timed_out: result.error?.code === "ETIMEDOUT",
    timeout_ms: timeoutMs,
    started_at: startedAt,
    stopped_at: new Date().toISOString(),
    stdout: Buffer.isBuffer(result.stdout)
      ? result.stdout
      : Buffer.from(result.stdout ?? ""),
    stderr: Buffer.isBuffer(result.stderr)
      ? result.stderr
      : Buffer.from(result.stderr ?? ""),
    error_code: result.error?.code ?? null,
  };
}

function persistAcceptedBinaryCapture(handle, prefix, capture) {
  return {
    argv: capture.argv,
    cwd: capture.cwd,
    environment: capture.environment,
    parent_pid: capture.parent_pid,
    child_pid: capture.child_pid,
    exit_status: capture.exit_status,
    signal: capture.signal,
    timed_out: capture.timed_out,
    timeout_ms: capture.timeout_ms,
    started_at: capture.started_at,
    stopped_at: capture.stopped_at,
    error_code: capture.error_code,
    stdout_identity: writeBytesCreateOnce(
      handle,
      `${prefix}/stdout.log`,
      capture.stdout,
    ),
    stderr_identity: writeBytesCreateOnce(
      handle,
      `${prefix}/stderr.log`,
      capture.stderr,
    ),
  };
}

function acceptedBinaryFilesystemProbeSource() {
  return [
    'const fs=require("node:fs")',
    "const action=process.argv[1]",
    "const target=process.argv[2]",
    "const finish=(fd,value,status)=>{fs.writeSync(fd,JSON.stringify(value)+'\\n');process.exit(status)}",
    "const reject=(error)=>finish(2,{status:'REJECTED',code:error.code,errno:error.errno,syscall:error.syscall},error.code==='EPERM'?73:74)",
    "try{",
    " if(action==='READ_DIR'){const d=fs.opendirSync(target);d.readSync();d.closeSync()}",
    " else if(action==='WRITE_FILE'){const fd=fs.openSync(target,fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_WRONLY|(fs.constants.O_NOFOLLOW??0),0o600);fs.closeSync(fd)}",
    " else throw Object.assign(new Error('unknown action'),{code:'EINVAL'})",
    " finish(1,{status:'ALLOWED',action},0)",
    "}catch(error){reject(error)}",
  ].join("\n");
}

async function runAcceptedBinarySandboxCalibration(handle) {
  const prefix = "raw/accepted-adapter-control/sandbox-calibration";
  const fixture = createDisposableRoot(
    "p1-165-accepted-binary-sandbox-calibration",
  );
  const externalFixture = createDisposableRoot(
    "p1-165-accepted-binary-external-denial",
  );
  const syntheticHome = join(fixture.root, "synthetic-home");
  const executablePath = join(fixture.root, "sourcelens-analyzer");
  mkdirSync(syntheticHome, { recursive: false, mode: 0o700 });
  chmodSync(syntheticHome, 0o700);
  const binding = acceptedBinarySandboxProfile(
    fixture.root,
    syntheticHome,
    executablePath,
  );
  const profileIdentity = writeBytesCreateOnce(
    handle,
    `${prefix}/accepted-binary-profile.sb`,
    binding.profile_bytes,
  );
  const calibrationProfileIdentity = writeBytesCreateOnce(
    handle,
    `${prefix}/calibration-profile.sb`,
    binding.calibration_profile_bytes,
  );
  const realHomeWriteTarget = join(
    binding.real_home_identity.path,
    `.p1-165-home-write-denial-${randomBytes(12).toString("hex")}`,
  );
  const externalWriteTarget = join(
    externalFixture.root,
    `.p1-165-external-write-denial-${randomBytes(12).toString("hex")}`,
  );
  const ownedWriteTarget = join(
    fixture.root,
    `.p1-165-owned-write-allow-${randomBytes(12).toString("hex")}`,
  );
  assertCritical(
    !existsSync(realHomeWriteTarget)
      && !existsSync(externalWriteTarget)
      && !existsSync(ownedWriteTarget),
    "ROOT_PREEXISTS",
    "accepted-binary sandbox probe path preexists",
  );
  const probe = acceptedBinaryFilesystemProbeSource();
  const runSandboxed = (action, target) => captureAcceptedBinaryChild([
    SANDBOX_EXEC,
    "-p",
    binding.calibration_profile,
    process.execPath,
    "-e",
    probe,
    action,
    target,
  ], binding.environment, fixture.root);
  const captures = {
    home_read_denial: runSandboxed(
      "READ_DIR",
      binding.real_home_identity.path,
    ),
    home_write_denial: runSandboxed(
      "WRITE_FILE",
      realHomeWriteTarget,
    ),
    external_write_denial: runSandboxed(
      "WRITE_FILE",
      externalWriteTarget,
    ),
    owned_write_allowance: runSandboxed(
      "WRITE_FILE",
      ownedWriteTarget,
    ),
  };
  const persisted = Object.fromEntries(
    Object.entries(captures)
      .filter(([, capture]) => (
        capture !== null
          && typeof capture === "object"
          && Buffer.isBuffer(capture.stdout)
      ))
      .map(([label, capture]) => [
        label,
        persistAcceptedBinaryCapture(
          handle,
          `${prefix}/${label}`,
          capture,
        ),
      ]),
  );
  const parsePass = (capture, label) => parseJsonBytesNoDuplicate(
    capture.stdout,
    { label },
  );
  const parseDenied = (capture, label) => parseJsonBytesNoDuplicate(
    capture.stderr,
    { label },
  );
  const deniedHomeRead = parseDenied(
    captures.home_read_denial,
    "accepted-binary sandbox HOME read denial",
  );
  const deniedHomeWrite = parseDenied(
    captures.home_write_denial,
    "accepted-binary sandbox HOME write denial",
  );
  const deniedExternalWrite = parseDenied(
    captures.external_write_denial,
    "accepted-binary sandbox external write denial",
  );
  const allowedOwnedWrite = parsePass(
    captures.owned_write_allowance,
    "accepted-binary sandbox owned write allowance",
  );
  assertCritical(
    [
        [captures.home_read_denial, deniedHomeRead],
        [captures.home_write_denial, deniedHomeWrite],
        [captures.external_write_denial, deniedExternalWrite],
      ].every(([capture, value]) => (
        capture.exit_status === 73
          && capture.signal === null
          && capture.timed_out === false
          && capture.stdout.length === 0
          && value.status === "REJECTED"
          && value.code === "EPERM"
      ))
      && captures.owned_write_allowance.exit_status === 0
      && allowedOwnedWrite.status === "ALLOWED"
      && allowedOwnedWrite.action === "WRITE_FILE"
      && !existsSync(realHomeWriteTarget)
      && !existsSync(externalWriteTarget)
      && existsSync(ownedWriteTarget),
    "EXTERNAL_EFFECT_FORBIDDEN",
    "accepted-binary filesystem sandbox calibration did not prove its exact boundary",
  );
  const syntheticNetworkFixture = {
    schema_version: "p1-168-synthetic-network-denial-fixture/v1",
    task_id: TASK_ID,
    source_kind: "SYNTHETIC_FIXTURE_ONLY",
    live_network_probe_executed: false,
    live_network_connections_created: 0,
    sandbox_profile_identity: profileIdentity,
    calibration_profile_identity: calibrationProfileIdentity,
    expected_policy: "NETWORK_DENIAL_DEFERRED_TO_P1_169",
    status: "PASS_SYNTHETIC_FIXTURE_ONLY",
  };
  const syntheticNetworkFixtureIdentity = writeJsonCreateOnce(
    handle,
    `${prefix}/synthetic-network-denial-fixture.json`,
    syntheticNetworkFixture,
  );
  cleanupOwnedRoot(fixture);
  cleanupOwnedRoot(externalFixture);
  assertCritical(
    !existsSync(fixture.root)
      && !existsSync(externalFixture.root)
      && !existsSync(realHomeWriteTarget),
    "EVIDENCE_WRITE_FAILED",
    "accepted-binary sandbox calibration cleanup failed",
  );
  const receipt = {
    schema_version: "p1-168-accepted-binary-sandbox-calibration/v2",
    hostile_global_read_isolation_claim: false,
    hostile_process_isolation_claim: false,
    trusted_accepted_source_required: true,
    task_id: TASK_ID,
    sandbox_profile_identity: profileIdentity,
    calibration_profile_identity: calibrationProfileIdentity,
    closed_environment: binding.environment,
    real_home_identity: binding.real_home_identity,
    synthetic_network_denial_fixture_identity:
      syntheticNetworkFixtureIdentity,
    network_probe_source_kind: "SYNTHETIC_FIXTURE_ONLY",
    live_network_probe_executed: false,
    live_network_connections_created: 0,
    live_network_calibration: "DEFERRED_TO_P1_169",
    home_read_denial: persisted.home_read_denial,
    home_write_denial: persisted.home_write_denial,
    external_write_denial: persisted.external_write_denial,
    owned_write_allowance: persisted.owned_write_allowance,
    denied_error_code: "EPERM",
    real_home_write_target_absent: true,
    external_write_target_absent: true,
    calibration_roots_cleaned: true,
    excluded_real_home_config_and_credential_paths: [
      join(binding.real_home_identity.path, ".cargo", "credentials"),
      join(binding.real_home_identity.path, ".cargo", "credentials.toml"),
      join(binding.real_home_identity.path, ".cargo", "config"),
      join(binding.real_home_identity.path, ".cargo", "config.toml"),
    ],
    false_accepts: 0,
    claim_boundary: binding.claim_boundary,
    status: "PASS",
  };
  const receiptIdentity = writeJsonCreateOnce(
    handle,
    `${prefix}/receipt.json`,
    receipt,
  );
  return { receipt, receiptIdentity };
}

async function runAcceptedAdapterControl(handle) {
  const acceptedAuthority = bindAcceptedP129Authority(handle);
  const sourceMatrixRoot = directoryIdentity(
    ACCEPTED_P1_129_FORMAL_ROOT,
    "accepted P1-129 formal matrix root",
  );
  const sandboxCalibration = await runAcceptedBinarySandboxCalibration(handle);
  const proofPlan = buildAcceptedAdapterProofPlan(
    ACCEPTED_P1_129_FORMAL_ROOT,
  );
  const proofLimitsIdentity = writeJsonCreateOnce(
    handle,
    "raw/accepted-adapter-control/proof-limits.json",
    proofPlan.receipt,
  );
  const index = {};
  const proofEntries = {};
  const currentB2Receipts = [];
  const currentB2ChildPids = [];
  for (const taskId of ACCEPTED_TASK_IDS) {
    for (const profileId of PROFILE_ORDER) {
      const key = `${taskId}:${profileId}`;
      const adapterId = profileId.slice(0, 2);
      const repetitionId = profileId.endsWith("_A") ? 1 : 2;
      const sourceCaseRoot = join(
        ACCEPTED_P1_129_FORMAL_ROOT,
        "positive",
        taskId,
        profileId,
      );
      const sourceWorkerOutputRoot = join(
        sourceCaseRoot,
        "worker-output",
      );
      const sourceCaseRootIdentity = directoryIdentity(
        sourceCaseRoot,
        `accepted P1-129 selected case root ${key}`,
      );
      const proofPrefix = [
        "raw/accepted-adapter-control/proofs/positive",
        taskId,
        profileId,
      ].join("/");
      const stagedProofRoot = join(
        handle.root,
        ...proofPrefix.split("/"),
      );
      const caseProofPlan = proofPlan.cases[key];
      assertCritical(
        caseProofPlan?.source_case_root === sourceCaseRoot,
        "IDENTITY_MISMATCH",
        `accepted adapter case lacks its frozen pre-read plan: ${key}`,
      );
      const copiedArtifacts = Object.fromEntries(
        Object.entries(ACCEPTED_ADAPTER_PROOF_FILES).map(
          ([role, sourceRelativePath]) => [
            role,
            copyAdapterProofArtifact({
              handle,
              sourceCaseRoot,
              proofPrefix,
              sourceRelativePath,
              expectedPlan: caseProofPlan.fixed[sourceRelativePath],
              includeBytes: true,
            }),
          ],
        ),
      );
      const artifacts = Object.fromEntries(
        Object.entries(copiedArtifacts).map(([role, copy]) => [
          role,
          copy.identity,
        ]),
      );
      const request = parseJsonBytesNoDuplicate(
        copiedArtifacts.request.bytes,
        { label: `accepted adapter request ${key}` },
      );
      const taskSpec = readCanonicalTaskSpec(taskId, request.task_spec);
      const adapterResult = parseJsonBytesNoDuplicate(
        copiedArtifacts.adapter_result.bytes,
        { label: `accepted adapter result ${key}` },
      );
      const runRecord = parseJsonBytesNoDuplicate(
        copiedArtifacts.run_record.bytes,
        { label: `accepted adapter run record ${key}` },
      );
      assertCritical(
        request.case_id === `${taskId}-${profileId}`
          && request.adapter_id === adapterId
          && request.repetition_id === repetitionId
          && taskSpec.value.task_id === taskId
          && adapterResult.task_id === taskId
          && adapterResult.adapter_id === adapterId
          && adapterResult.repetition_id === repetitionId
          && adapterResult.terminal_status === "completed"
          && adapterResult.stop_reason_code === "agent_complete"
          && runRecord.task_id === taskId
          && runRecord.adapter_id === adapterId
          && runRecord.repetition_id === repetitionId
          && runRecord.terminal_status === "completed"
          && runRecord.stop_reason_code === "agent_complete",
        "EVIDENCE_CROSS_BINDING_INVALID",
        `accepted adapter raw proof is not bound to its key: ${key}`,
      );
      const copiedPhysical = adapterId === "B2"
        ? copyB2PhysicalProof({
            handle,
            sourceCaseRoot,
            proofPrefix,
            adapterResult,
            b2Plan: caseProofPlan.b2,
          })
        : null;
      const currentB2 = adapterId === "B2"
        ? reexecuteAcceptedP129B2({
            handle,
            taskId,
            profileId,
            adapterResult,
            copiedPhysical,
            sandboxCalibrationIdentity:
              sandboxCalibration.receiptIdentity,
          })
        : null;
      if (currentB2 !== null) {
        currentB2Receipts.push(currentB2.receiptIdentity);
        currentB2ChildPids.push(currentB2.childPid);
      }
      const b2PhysicalProof = copiedPhysical?.proof ?? null;
      const b2ScanProofIdentity = adapterId === "B2"
        ? writeJsonCreateOnce(
            handle,
            `${proofPrefix}/b2-scan-proof.json`,
            {
          schema_version: "p1-165-b2-scan-proof/v2",
    hostile_global_read_isolation_claim: false,
    hostile_process_isolation_claim: false,
    trusted_accepted_source_required: true,
              task_id: TASK_ID,
              target_task_id: taskId,
              profile_id: profileId,
              operation_id: "repository_analysis.scan",
              accepted_authority_bundle_identity:
                acceptedAuthority.receiptIdentity,
              source_case_root: sourceCaseRoot,
              source_case_root_identity: sourceCaseRootIdentity,
              source_worker_output_root: sourceWorkerOutputRoot,
              staged_proof_root: stagedProofRoot,
              request_identity: artifacts.request,
              canonical_task_spec_identity: taskSpec.identity,
              adapter_command_ledger_identity:
                artifacts.adapter_command_ledger,
              adapter_result_identity: artifacts.adapter_result,
              run_record_identity: artifacts.run_record,
              trace_identity: artifacts.trace,
              stable_projection_identity: artifacts.stable_projection,
              target_sentinel_identity: artifacts.target_executed,
              accepted_scan_ledger: adapterResult.scan_ledger,
              accepted_scan_result: adapterResult.scan_result,
              selected_physical_proof: b2PhysicalProof,
              current_fresh_sandbox_reexecution_identity:
                currentB2.receiptIdentity,
              current_fresh_child_pid: currentB2.childPid,
              current_fresh_cleanup_verified:
                currentB2.receipt.cleanup_verified,
              historical_reviewed_binary_exact_bytes_claim: false,
              cooperative_local_accepted_evidence_path_residual: true,
              claim_boundary:
                "ACCEPTED_P1_129_SELECTED_PROOF_PLUS_CURRENT_FRESH_SANDBOX_SCAN",
            },
          )
        : null;
      const entry = {
        target_task_id: taskId,
        profile_id: profileId,
        adapter_id: adapterId,
        repetition_id: repetitionId,
        source_case_root: sourceCaseRoot,
        source_case_root_identity: sourceCaseRootIdentity,
        source_worker_output_root: sourceWorkerOutputRoot,
        staged_proof_root: stagedProofRoot,
        proof_prefix: proofPrefix,
        artifacts,
        canonical_task_spec_identity: taskSpec.identity,
        b2_scan_proof_identity: b2ScanProofIdentity,
        b2_physical_proof: b2PhysicalProof,
        current_b2_reexecution_identity:
          currentB2?.receiptIdentity ?? null,
        current_b2_cleanup_verified:
          currentB2?.receipt.cleanup_verified ?? null,
      };
      proofEntries[key] = entry;
      index[key] = artifacts.adapter_result;
    }
  }
  assertCritical(
    Object.keys(index).length === 36
      && Object.keys(proofEntries).length === 36
      && Object.values(proofEntries)
        .filter((entry) => entry.adapter_id === "B2").length
        === ACCEPTED_P1_129_SELECTED_B2_COUNT
      && currentB2Receipts.length === ACCEPTED_P1_129_SELECTED_B2_COUNT
      && currentB2ChildPids.length === ACCEPTED_P1_129_SELECTED_B2_COUNT
      && new Set(currentB2ChildPids).size
        === ACCEPTED_P1_129_SELECTED_B2_COUNT,
    "IDENTITY_MISMATCH",
    "accepted P1-129 selected proof or current B2 execution set is incomplete",
  );
  const claimBoundary =
    "COOPERATIVE_LOCAL_ACCEPTED_P1_129_PATH_PLUS_CURRENT_SELECTED_INVENTORY";
  const indexReceipt = {
    schema_version: "p1-165-accepted-adapter-result-index/v4",
    hostile_global_read_isolation_claim: false,
    hostile_process_isolation_claim: false,
    trusted_accepted_source_required: true,
    task_id: TASK_ID,
    source_formal_root: sourceMatrixRoot,
    proof_limits_identity: proofLimitsIdentity,
    sandbox_calibration_identity: sandboxCalibration.receiptIdentity,
    accepted_authority_bundle_identity: acceptedAuthority.receiptIdentity,
    historical_reviewed_binary_exact_bytes_claim: false,
    cooperative_local_accepted_evidence_path_residual: true,
    claim_boundary: claimBoundary,
    entries: proofEntries,
  };
  writeJsonCreateOnce(
    handle,
    "raw/accepted-adapter-control/adapter-result-index.json",
    indexReceipt,
  );
  const cleanupVerified = {
    all_current_b2_fixture_roots_absent: Object.values(proofEntries)
      .filter((entry) => entry.adapter_id === "B2")
      .every((entry) =>
        entry.current_b2_cleanup_verified?.fixture_root_absent === true
      ),
    sandbox_calibration_roots_absent:
      sandboxCalibration.receipt.calibration_roots_cleaned === true,
    accepted_p1_129_source_preserved_read_only: true,
  };
  const controlReceipt = {
    schema_version: "p1-165-accepted-adapter-control/v4",
    hostile_global_read_isolation_claim: false,
    hostile_process_isolation_claim: false,
    trusted_accepted_source_required: true,
    task_id: TASK_ID,
    mode:
      "ACCEPTED_P1_129_PROOFS_PLUS_12_CURRENT_FRESH_B2_SANDBOX_SCANS",
    accepted_authority_bundle_identity: acceptedAuthority.receiptIdentity,
    source_formal_root: sourceMatrixRoot,
    proof_limits_identity: proofLimitsIdentity,
    sandbox_calibration_identity: sandboxCalibration.receiptIdentity,
    current_b2_scan_receipt_identities: currentB2Receipts,
    current_b2_distinct_child_pids: currentB2ChildPids,
    cleanup_verified: cleanupVerified,
    historical_reviewed_binary_exact_bytes_claim: false,
    cooperative_local_accepted_evidence_path_residual: true,
    claim_boundary: claimBoundary,
    status: "PASS",
  };
  assertCritical(
    sameJson(
      Object.keys(controlReceipt).sort(),
      [...ACCEPTED_ADAPTER_CONTROL_KEYS].sort(),
    )
      && cleanupVerified.all_current_b2_fixture_roots_absent
      && cleanupVerified.sandbox_calibration_roots_absent,
    "IDENTITY_MISMATCH",
    "accepted adapter control receipt keyset or cleanup drifted",
  );
  writeJsonCreateOnce(
    handle,
    "raw/accepted-adapter-control/process/receipt.json",
    controlReceipt,
  );
  return {
    summary: acceptedAuthority.formalSummary,
    index,
    proofEntries,
  };
}

function writeB2ScanLedger(handle, adapterControl, cellOrder) {
  const entries = cellOrder
    .filter((cell) => cell.profile_id.startsWith("B2_"))
    .map((cell) => {
      const proof = adapterControl.proofEntries[
        `${cell.task_id}:${cell.profile_id}`
      ];
      return {
        cell_id: cell.cell_id,
        task_id: cell.task_id,
        profile_id: cell.profile_id,
        operation_id: "repository_analysis.scan",
        b2_scan_proof_identity: proof.b2_scan_proof_identity,
      };
    });
  assertCritical(
    entries.length === 12
      && new Set(entries.map((entry) => entry.cell_id)).size === 12
      && entries.every(
        (entry) =>
          entry.b2_scan_proof_identity !== null,
      ),
    "IDENTITY_MISMATCH",
    "B2 compact raw scan proof ledger is incomplete",
  );
  writeJsonCreateOnce(handle, "raw/accepted-adapter-control/b2-scan-ledger.json", {
    schema_version: "p1-165-b2-scan-ledger/v2",
    task_id: TASK_ID,
    entries,
  });
}

function writeProfileManifest(profileHandle) {
  const built = buildClosedEvidenceManifest(profileHandle.root);
  const bytes = Buffer.isBuffer(built)
    ? built
    : Buffer.isBuffer(built?.bytes)
      ? built.bytes
      : canonicalBytes(built?.manifest ?? built);
  return writeBytesCreateOnce(profileHandle, "MANIFEST.json", bytes);
}

async function runSyntheticCells(handle, adapterControl) {
  const cellOrder = [];
  const profileReceipts = [];
  let acceptedSpines = 0;
  let acceptedReplays = 0;
  let realB2Children = 0;
  const compatibility = verifyAcceptedPatchIrV1Compatibility();
  createOwnedRoot(join(handle.root, "raw/profile-verification"));
  for (const profileId of PROFILE_ORDER) {
    const profileRoot = join(
      handle.root,
      "raw/profile-verification",
      profileId,
    );
    const profileHandle = createOwnedRoot(profileRoot);
    const executionOrder = [];
    for (const [taskIndex, taskId] of ACCEPTED_TASK_IDS.entries()) {
      const cellOrdinal = cellOrder.length + 1;
      const cellId = `P1-165-CELL-${String(cellOrdinal).padStart(2, "0")}`;
      const repetitionId = profileId.endsWith("_A") ? "A" : "B";
      const joinValue = {
        execution_id: `P1-165-SYNTHETIC-${String(cellOrdinal).padStart(2, "0")}`,
        cell_id: cellId,
        task_id: TASK_ID,
        profile_id: profileId,
        repetition_id: repetitionId,
      };
      validateJoin(joinValue);
      const adapterIdentity = adapterControl.index[`${taskId}:${profileId}`];
      const requestBody = canonicalBytes({
        schema_version: "p1-165-synthetic-request-body/v1",
        cell_id: cellId,
        target_task_id: taskId,
        profile_id: profileId,
      });
      const cellPrefix = `raw/cells/${cellId}`;
      writeBytesCreateOnce(handle, `${cellPrefix}/join.json`, canonicalBytes(joinValue));
      let contextBytes;
      let requestRecordBytes;
      let requestRecordIdentity;
      const observerPrefix = `${cellPrefix}/observer`;
      const cellCalibration = buildFrozenSyntheticObserverFixture({
        evidence_handle: handle,
        join: joinValue,
        artifact_prefix: observerPrefix,
        fixture_index: cellOrdinal + 1,
        request_record_factory: (generatedPolicy) => {
          const context = {
            schema_version: "p1-165-context-record/v1",
            task_id: TASK_ID,
            join: joinValue,
            adapter_result_identity: adapterIdentity,
          };
          contextBytes = canonicalBytes(context);
          const requestRecord = {
            schema_version: "p1-165-request-record/v1",
            task_id: TASK_ID,
            join: joinValue,
            context_record_identity: bytesIdentity(contextBytes),
            policy: generatedPolicy,
            request_body_identity: bytesIdentity(requestBody),
          };
          requestRecordBytes = canonicalBytes(requestRecord);
          requestRecordIdentity = bytesIdentity(requestRecordBytes);
          writeBytesCreateOnce(handle, `${cellPrefix}/request.raw`, requestBody);
          writeBytesCreateOnce(
            handle,
            `${cellPrefix}/request-record.json`,
            requestRecordBytes,
          );
          writeBytesCreateOnce(handle, `${cellPrefix}/context.json`, contextBytes);
          return requestRecordIdentity;
        },
      });
      assertCritical(
        Buffer.isBuffer(contextBytes)
          && Buffer.isBuffer(requestRecordBytes)
          && requestRecordIdentity !== undefined,
        "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
        "owned per-cell calibration did not bind exact request bytes",
      );

      const accepted = buildAcceptedReferenceResponse(
        taskId,
        `P1-165-${profileId}-${taskIndex + 1}`,
      );
      const rawResponse = buildHttpResponse(accepted.response_bytes);
      const transportChunks = splitBytes(rawResponse, [
        1 + (cellOrdinal % 7),
        3 + (cellOrdinal % 11),
        17,
      ]);
      const quarantine = createDisposableRoot(`p1-165-cell-${cellOrdinal}`);
      try {
        writeBytesCreateOnce(quarantine, "response.http", rawResponse);
        const usage = cellOrdinal === 1
          ? observedUsage({
              join: joinValue,
              responseIdentity: bytesIdentity(accepted.response_bytes),
              inputTokens: 0,
              outputTokens: 2048,
            })
          : unknownUsage({
              join: joinValue,
              responseIdentity: bytesIdentity(accepted.response_bytes),
            });
        const analyzed = analyzeTransport({
          join: joinValue,
          request_record_identity: requestRecordIdentity,
          policy: cellCalibration.policy,
          observed_peer: cellCalibration.record.peer,
          chunks: transportChunks,
          eof: true,
          stream_terminal_events: [],
        });
        const safeArtifacts = [
          contextBytes,
          requestBody,
          requestRecordBytes,
          canonicalBytes(analyzed.record),
          cellCalibration.stdout_bytes,
          cellCalibration.stderr_bytes,
          canonicalBytes(cellCalibration.record),
          canonicalBytes(usage),
        ];
        const cellSecretSentinel = Buffer.from(
          "P1-165-SYNTHETIC-SECRET-SENTINEL-DO-NOT-PERSIST",
          "utf8",
        );
        assertNoSecretReflection(safeArtifacts, cellSecretSentinel);
        const transportIdentity = writeJsonCreateOnce(
          handle,
          `${cellPrefix}/transport/transport-record.json`,
          analyzed.record,
        );
        const usageIdentity = writeJsonCreateOnce(
          handle,
          `${cellPrefix}/usage.json`,
          usage,
        );
        const supportingArtifacts = {
          context_record: {
            path: `${cellPrefix}/context.json`,
            ...bytesIdentity(contextBytes),
          },
          request_body: {
            path: `${cellPrefix}/request.raw`,
            ...bytesIdentity(requestBody),
          },
          request_record: {
            path: `${cellPrefix}/request-record.json`,
            ...requestRecordIdentity,
          },
          transport_record: transportIdentity,
          observer_stdout: {
            path: `${observerPrefix}/stdout.log`,
            ...bytesIdentity(cellCalibration.stdout_bytes),
          },
          observer_stderr: {
            path: `${observerPrefix}/stderr.log`,
            ...bytesIdentity(cellCalibration.stderr_bytes),
          },
          observer_record: {
            path: `${observerPrefix}/observation.json`,
            ...bytesIdentity(canonicalBytes(cellCalibration.record)),
          },
          usage_record: usageIdentity,
        };
        const admitted = admitAndPersistResponse({
          evidence_handle: handle,
          quarantine_handle: quarantine,
          quarantine_relative_path: "response.http",
          admitted_relative_path: `${cellPrefix}/admission/admitted-response.http`,
          receipt_relative_path: `${cellPrefix}/admission/admission-receipt.json`,
          join: joinValue,
          request_record_identity: requestRecordIdentity,
          request_record_bytes: requestRecordBytes,
          context_record_bytes: contextBytes,
          request_body_bytes: requestBody,
          policy: cellCalibration.policy,
          observed_peer: cellCalibration.record.peer,
          transport_chunks: transportChunks,
          eof: true,
          stream_terminal_events: [],
          observer_record: cellCalibration.record,
          observer_stdout_bytes: cellCalibration.stdout_bytes,
          observer_stderr_bytes: cellCalibration.stderr_bytes,
          usage_record: usage,
          secret_sentinel: cellSecretSentinel,
          supporting_artifacts: supportingArtifacts,
        });
        assertCritical(
          admitted.body_bytes.equals(accepted.response_bytes),
          "IDENTITY_MISMATCH",
          "admitted HTTP content does not equal the accepted normalized response",
        );
        const runId = `P1-165-${profileId}-${String(taskIndex + 1).padStart(2, "0")}`;
        const execution = await executeSpine({
          taskId,
          responseBytes: admitted.body_bytes,
          runId,
        });
        assertCritical(
          execution.run_id === runId
            && Object.keys(execution.artifacts).length === 24,
          "IDENTITY_MISMATCH",
          "P1-149 execution spine result is incomplete",
        );
        const profileWritten = new Map();
        const cellIdentities = [];
        for (const artifactName of EXECUTION_ARTIFACT_KEYS) {
          const bytes = execution.artifacts[artifactName];
          const profileIdentity = writeBytesCreateOnce(
            profileHandle,
            `tasks/${taskId}/${artifactName}`,
            bytes,
          );
          profileWritten.set(artifactName, profileIdentity);
          const cellIdentity = writeBytesCreateOnce(
            handle,
            `${cellPrefix}/spine/${artifactName}`,
            bytes,
          );
          cellIdentities.push(cellIdentity);
        }
        acceptedSpines += 1;
        assertCritical(
          execution.summary.p1_101_replay === "PASS"
            && execution.summary.rollback_exact === true,
          "IDENTITY_MISMATCH",
          "P1-101 replay or rollback is not independently preserved",
        );
        acceptedReplays += 1;
        if (profileId.startsWith("B2_")) realB2Children += 1;
        executionOrder.push({
          ordinal: taskIndex + 1,
          task_id: taskId,
          artifact_root: `tasks/${taskId}`,
          response: profileWritten.get("provider-response.json"),
          stable_projection: profileWritten.get("p1-101-stable-projection.json"),
        });
        const admissionReceiptPath =
          `${cellPrefix}/admission/admission-receipt.json`;
        const admissionReceiptBytes = readFileSync(
          join(handle.root, ...admissionReceiptPath.split("/")),
        );
        const spineIdentityByName = new Map(
          EXECUTION_ARTIFACT_KEYS.map((artifactName, index) => [
            artifactName,
            cellIdentities[index],
          ]),
        );
        closeCellEvidence({
          evidence_handle: handle,
          relative_path: `${cellPrefix}/cell-closure.json`,
          join: joinValue,
          request_record_identity: requestRecordIdentity,
          admitted_response_identity: bytesIdentity(admitted.raw_response_bytes),
          body_identity: bytesIdentity(admitted.body_bytes),
          admission_receipt_bytes: admissionReceiptBytes,
          admission_receipt_identity: {
            path: admissionReceiptPath,
            ...bytesIdentity(admissionReceiptBytes),
          },
          adapter_control_identity: adapterIdentity,
          p1_149_artifact_identities: cellIdentities.map((identity) => ({
            path: identity.path,
            byte_length: identity.byte_length,
            sha256: identity.sha256,
          })),
          p1_101_receipt_identities: [
            spineIdentityByName.get("p1-101-replay-receipt.json"),
            spineIdentityByName.get("p1-101-adapter-rollback-receipt.json"),
          ].map((identity) => ({
            path: identity.path,
            byte_length: identity.byte_length,
            sha256: identity.sha256,
          })),
          b2_scan_proof_identity: profileId.startsWith("B2_")
            ? adapterControl.proofEntries[
              `${taskId}:${profileId}`
            ].b2_scan_proof_identity
            : null,
          outcome: "SUCCESS",
          outcome_reason: "PASS",
        });
        cellOrder.push({
          ordinal: cellOrdinal,
          cell_id: cellId,
          task_id: taskId,
          profile_id: profileId,
          repetition_id: repetitionId,
          run_id: runId,
        });
      } finally {
        cleanupOwnedRoot(quarantine);
      }
    }
    writeJsonCreateOnce(profileHandle, "p1-055-v1-compatibility.json", compatibility);
    writeJsonCreateOnce(profileHandle, "run-plan.json", {
      schema_version: "p1-149-preflight-run-plan/v1",
      task_ids: ACCEPTED_TASK_IDS,
      execution_order: executionOrder,
      claim_boundary: READINESS_CLAIM_BOUNDARY,
    });
    writeProfileManifest(profileHandle);
    const verified = verifyFrozenExecutionEvidence(profileRoot);
    assertCritical(
      verified.status === "PASS",
      "IDENTITY_MISMATCH",
      `${profileId} frozen execution spine verification failed`,
    );
    writeJsonCreateOnce(
      handle,
      `raw/profile-verification-receipts/${profileId}.json`,
      verified,
    );
    profileReceipts.push(verified);
  }
  assertCritical(
    cellOrder.length === 36
      && new Set(cellOrder.map((entry) => entry.run_id)).size === 36
      && acceptedSpines === 36
      && acceptedReplays === 36
      && realB2Children === 12,
    "ACCOUNTING_MISMATCH",
    "synthetic 36-cell execution accounting is incomplete",
  );
  writeJsonCreateOnce(handle, "raw/synthetic/cells.json", {
    schema_version: "p1-165-synthetic-cell-order/v1",
    cells: cellOrder,
  });
  return {
    cellOrder,
    profileReceipts,
    acceptedSpines,
    acceptedReplays,
    realB2Children,
  };
}

function captureChild(argv, { timeout_ms = 5_000 } = {}) {
  return new Promise((resolveCapture, rejectCapture) => {
    const startedAt = new Date().toISOString();
    const environment = closedChildEnvironment();
    const child = spawn(argv[0], argv.slice(1), {
      cwd: REPOSITORY_ROOT,
      env: environment,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let timedOut = false;
    const append = (chunks, chunk, stream) => {
      const bytes = Buffer.from(chunk);
      if (stream === "stdout") stdoutBytes += bytes.length;
      else stderrBytes += bytes.length;
      if (stdoutBytes > 1024 * 1024 || stderrBytes > 1024 * 1024) {
        child.kill("SIGKILL");
        rejectCapture(new Error("child control output exceeded 1 MiB"));
        return;
      }
      chunks.push(bytes);
    };
    child.stdout.on("data", (chunk) => append(stdout, chunk, "stdout"));
    child.stderr.on("data", (chunk) => append(stderr, chunk, "stderr"));
    child.once("error", rejectCapture);
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
    }, timeout_ms);
    child.once("close", (exitStatus, signal) => {
      clearTimeout(timer);
      resolveCapture({
        argv,
        environment,
        parent_pid: process.pid,
        pid: child.pid,
        exit_status: exitStatus,
        signal,
        timed_out: timedOut,
        started_at: startedAt,
        stopped_at: new Date().toISOString(),
        stdout: Buffer.concat(stdout),
        stderr: Buffer.concat(stderr),
      });
    });
  });
}

function persistChildCapture(handle, prefix, capture, extra) {
  const stdout = writeBytesCreateOnce(
    handle,
    `${prefix}/stdout.log`,
    capture.stdout,
  );
  const stderr = writeBytesCreateOnce(
    handle,
    `${prefix}/stderr.log`,
    capture.stderr,
  );
  const receipt = {
    schema_version: "p1-165-control-child-receipt/v1",
    task_id: TASK_ID,
    ...extra,
    argv: capture.argv,
    environment: capture.environment,
    parent_pid: capture.parent_pid,
    pid: capture.pid,
    exit_status: capture.exit_status,
    signal: capture.signal,
    timed_out: capture.timed_out,
    started_at: capture.started_at,
    stopped_at: capture.stopped_at,
    stdout,
    stderr,
  };
  const identity = writeJsonCreateOnce(
    handle,
    `${prefix}/receipt.json`,
    receipt,
  );
  return { receipt, identity };
}

async function runCreateOnceControl(handle) {
  const fixture = createDisposableRoot("p1-165-create-once-race");
  const target = join(fixture.root, "winner.bin");
  try {
    const plan = writeJsonCreateOnce(
      handle,
      "raw/concurrency/create-once-control/plan.json",
      {
        schema_version: "p1-165-create-once-control-plan/v1",
        task_id: TASK_ID,
        slots: [1, 2, 3, 4],
        target_initially_absent: !existsSync(target),
        create_flags: ["O_CREAT", "O_EXCL", "O_WRONLY"],
      },
    );
    const captures = await Promise.all(
      [1, 2, 3, 4].map((slot) => captureChild([
        process.execPath,
        fileURLToPath(import.meta.url),
        "--create-once-child",
        target,
        String(slot),
      ])),
    );
    const children = captures.map((capture, index) => {
      const lines = capture.stdout.toString("utf8")
        .split("\n")
        .filter(Boolean);
      assertCritical(
        lines.length === 1,
        "ACCOUNTING_MISMATCH",
        "create-once child did not emit exactly one result",
      );
      const result = JSON.parse(lines[0]);
      const persisted = persistChildCapture(
        handle,
        `raw/concurrency/create-once-control/children/slot-${index + 1}`,
        capture,
        { slot: index + 1, result },
      );
      return {
        slot: index + 1,
        capture,
        result,
        receipt: persisted.identity,
        persisted_receipt: persisted.receipt,
      };
    });
    const winners = children.filter(
      (child) => child.capture.exit_status === 0
        && child.result.status === "WINNER"
        && child.result.reason_code === "PASS",
    );
    const rejected = children.filter(
      (child) => child.capture.exit_status === 1
        && child.result.status === "NON_PASS"
        && child.result.reason_code === "CREATE_ONCE_FAILED",
    );
    assertCritical(
      winners.length === 1
        && rejected.length === CONCURRENCY_SLOTS - 1
        && existsSync(target),
      "ACCOUNTING_MISMATCH",
      "real create-once race did not produce one winner and three rejections",
    );
    const winnerBytes = readFileSync(target);
    assertCritical(
      sameJson(
        bytesIdentity(winnerBytes),
        winners[0].result.artifact_identity,
      ),
      "IDENTITY_MISMATCH",
      "create-once winner bytes differ from child receipt",
    );
    const winnerIdentity = writeBytesCreateOnce(
      handle,
      "raw/concurrency/create-once-control/winner-artifact.bin",
      winnerBytes,
    );
    writeJsonCreateOnce(
      handle,
      "raw/concurrency/create-once-control/receipt.json",
      {
        schema_version: "p1-165-create-once-control-receipt/v1",
        task_id: TASK_ID,
        plan_identity: plan,
        child_receipts: children.map((child) => child.receipt),
        slots: CONCURRENCY_SLOTS,
        winners: winners.length,
        create_once_rejections: rejected.length,
        winner_slot: winners[0].slot,
        winner_artifact_identity: winnerIdentity,
        overwritten: false,
        status: "PASS",
      },
    );
    return { children, winner: winners[0] };
  } finally {
    cleanupOwnedRoot(fixture);
  }
}

async function runLivenessControl(handle) {
  const cases = [
    { case_id: "LIVENESS_NORMAL_PROGRESS", timeout_ms: 2_000 },
    { case_id: "LIVENESS_PROGRESS_RECEIPT_MISSING", timeout_ms: 2_000 },
    { case_id: "LIVENESS_WORKER_STALL", timeout_ms: 150 },
    { case_id: "LIVENESS_OBSERVER_STALL", timeout_ms: 150 },
    { case_id: "LIVENESS_EVIDENCE_WRITER_STALL", timeout_ms: 150 },
  ];
  const captures = await Promise.all(cases.map((entry) => captureChild(
    [
      process.execPath,
      fileURLToPath(import.meta.url),
      "--liveness-child",
      entry.case_id,
    ],
    { timeout_ms: entry.timeout_ms },
  )));
  const results = cases.map((entry, index) => {
    const { case_id: caseId, timeout_ms: timeoutMs } = entry;
    const capture = captures[index];
    const heartbeats = capture.stdout.toString("utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line));
    let reasonCode = "PASS";
    if (caseId === "LIVENESS_PROGRESS_RECEIPT_MISSING") {
      reasonCode = "PROGRESS_RECEIPT_MISSING";
    } else if (caseId === "LIVENESS_WORKER_STALL") {
      reasonCode = "WORKER_STALL_DETECTED";
    } else if (caseId === "LIVENESS_OBSERVER_STALL") {
      reasonCode = "OBSERVER_STALL_DETECTED";
    } else if (caseId === "LIVENESS_EVIDENCE_WRITER_STALL") {
      reasonCode = "EVIDENCE_WRITER_STALL_DETECTED";
    }
    const startedMs = Date.parse(capture.started_at);
    const stoppedMs = Date.parse(capture.stopped_at);
    assertCritical(
      heartbeats.length === (caseId === "LIVENESS_NORMAL_PROGRESS" ? 2 : 1)
        && heartbeats.every(
          (heartbeat, heartbeatIndex) =>
            sameJson(Object.keys(heartbeat).sort(), [
              "actor",
              "case_id",
              "emitted_at",
              "schema_version",
              "sequence",
              "task_id",
            ])
              && heartbeat.schema_version === "p1-165-heartbeat/v1"
              && heartbeat.task_id === TASK_ID
              && heartbeat.case_id === caseId
              && heartbeat.sequence === heartbeatIndex + 1
              && Number.isFinite(Date.parse(heartbeat.emitted_at))
              && Date.parse(heartbeat.emitted_at) >= startedMs
              && Date.parse(heartbeat.emitted_at) <= stoppedMs,
        )
        && Number.isFinite(startedMs)
        && Number.isFinite(stoppedMs)
        && startedMs <= stoppedMs
        && (
          caseId.includes("STALL")
            ? capture.timed_out === true && capture.signal === "SIGTERM"
            : capture.timed_out === false && capture.exit_status === 0
        ),
      "ACCOUNTING_MISMATCH",
      `liveness child observation drifted: ${caseId}`,
    );
    const persisted = persistChildCapture(
      handle,
      `raw/liveness/control/${caseId}`,
      capture,
      { case_id: caseId, reason_code: reasonCode, heartbeats },
    );
    return {
      case_id: caseId,
      actor: heartbeats[0].actor,
      timeout_ms: timeoutMs,
      reason_code: reasonCode,
      heartbeats,
      capture,
      receipt: persisted.identity,
      persisted_receipt: persisted.receipt,
    };
  });
  writeJsonCreateOnce(handle, "raw/liveness/control/receipt.json", {
    schema_version: "p1-165-liveness-control-receipt/v1",
    task_id: TASK_ID,
    cases: results.map((result) => ({
      case_id: result.case_id,
      reason_code: result.reason_code,
      heartbeat_count: result.heartbeats.length,
      child_receipt: result.receipt,
    })),
    normal_progress: "PASS",
    missing_receipt: "DETECTED",
    worker_stall: "DETECTED",
    observer_stall: "DETECTED",
    evidence_writer_stall: "DETECTED",
    status: "PASS",
  });
  return results;
}

function writeEventLedgers(handle, createOnceControl, livenessControl) {
  const concurrencyEvents = [...createOnceControl.children]
    .sort((left, right) => left.slot - right.slot)
    .map((child, index) => {
      const capture = child.capture;
      const childReceipt = child.persisted_receipt;
      const event = {
        schema_version: "p1-165-create-once-race-event/v1",
        task_id: TASK_ID,
        sequence: index + 1,
        order_basis: "SLOT_ASCENDING",
        slot: child.slot,
        argv: capture.argv,
        parent_pid: capture.parent_pid,
        child_pid: capture.pid,
        started_at: capture.started_at,
        stopped_at: capture.stopped_at,
        exit_status: capture.exit_status,
        signal: capture.signal,
        timed_out: capture.timed_out,
        result_status: child.result.status,
        reason_code: child.result.reason_code,
        artifact_identity: child.result.artifact_identity,
        stdout_identity: childReceipt.stdout,
        stderr_identity: childReceipt.stderr,
        child_receipt_identity: child.receipt,
      };
      assertCritical(
        sameJson(
          Object.keys(event).sort(),
          [...CREATE_ONCE_RACE_EVENT_KEYS].sort(),
        )
          && event.sequence === event.slot
          && event.slot >= 1
          && event.slot <= CONCURRENCY_SLOTS
          && event.parent_pid === process.pid
          && Number.isSafeInteger(event.child_pid)
          && event.child_pid > 0
          && event.child_pid !== process.pid
          && event.signal === null
          && event.timed_out === false
          && sameJson(childReceipt.result, child.result)
          && sameJson(childReceipt.stdout, event.stdout_identity)
          && sameJson(childReceipt.stderr, event.stderr_identity),
        "ACCOUNTING_MISMATCH",
        "actual create-once race event drifted from its child receipt",
      );
      return event;
    });
  assertCritical(
    concurrencyEvents.length === CONCURRENCY_SLOTS
      && new Set(concurrencyEvents.map((event) => event.child_pid)).size
        === CONCURRENCY_SLOTS
      && new Set(concurrencyEvents.map((event) => event.argv[3])).size === 1
      && concurrencyEvents.every(
        (event) =>
          sameJson(event.argv, [
            process.execPath,
            fileURLToPath(import.meta.url),
            "--create-once-child",
            event.argv[3],
            String(event.slot),
          ])
          && Number.isFinite(Date.parse(event.started_at))
          && Number.isFinite(Date.parse(event.stopped_at))
          && Date.parse(event.started_at) <= Date.parse(event.stopped_at),
      )
      && Math.max(
        ...concurrencyEvents.map((event) => Date.parse(event.started_at)),
      ) <= Math.min(
        ...concurrencyEvents.map((event) => Date.parse(event.stopped_at)),
      )
      && !existsSync(dirname(concurrencyEvents[0].argv[3]))
      && concurrencyEvents.filter(
        (event) =>
          event.result_status === "WINNER"
          && event.reason_code === "PASS"
          && event.exit_status === 0
          && event.artifact_identity !== null,
      ).length === 1
      && concurrencyEvents.filter(
        (event) =>
          event.result_status === "NON_PASS"
          && event.reason_code === "CREATE_ONCE_FAILED"
          && event.exit_status === 1
          && event.artifact_identity === null,
      ).length === CONCURRENCY_SLOTS - 1,
    "ACCOUNTING_MISMATCH",
    "actual create-once raw event set is not one winner and three rejections",
  );
  const concurrencyBytes = Buffer.from(
    `${concurrencyEvents.map((event) => canonicalJson(event)).join("\n")}\n`,
    "utf8",
  );
  writeBytesCreateOnce(handle, "raw/concurrency/events.jsonl", concurrencyBytes);
  const livenessEvents = livenessControl.map((result, index) => {
    const capture = result.capture;
    const childReceipt = result.persisted_receipt;
    const event = {
      schema_version: "p1-165-liveness-observation-event/v1",
      task_id: TASK_ID,
      sequence: index + 1,
      case_id: result.case_id,
      actor: result.actor,
      timeout_ms: result.timeout_ms,
      argv: capture.argv,
      parent_pid: capture.parent_pid,
      child_pid: capture.pid,
      started_at: capture.started_at,
      stopped_at: capture.stopped_at,
      exit_status: capture.exit_status,
      signal: capture.signal,
      timed_out: capture.timed_out,
      observed_reason_code: result.reason_code,
      heartbeats: result.heartbeats,
      heartbeat_count: result.heartbeats.length,
      stdout_identity: childReceipt.stdout,
      stderr_identity: childReceipt.stderr,
      child_receipt_identity: result.receipt,
    };
    assertCritical(
      sameJson(
        Object.keys(event).sort(),
        [...LIVENESS_OBSERVATION_EVENT_KEYS].sort(),
      )
        && event.parent_pid === process.pid
        && Number.isSafeInteger(event.child_pid)
        && event.child_pid > 0
        && event.child_pid !== process.pid
        && sameJson(childReceipt.heartbeats, event.heartbeats)
        && childReceipt.reason_code === event.observed_reason_code
        && childReceipt.timed_out === event.timed_out
        && childReceipt.exit_status === event.exit_status
        && childReceipt.signal === event.signal
        && childReceipt.started_at === event.started_at
        && childReceipt.stopped_at === event.stopped_at
        && sameJson(childReceipt.stdout, event.stdout_identity)
        && sameJson(childReceipt.stderr, event.stderr_identity),
      "ACCOUNTING_MISMATCH",
      `actual liveness event drifted from its child receipt: ${result.case_id}`,
    );
    return event;
  });
  assertCritical(
    livenessEvents.length === 5
      && new Set(livenessEvents.map((event) => event.child_pid)).size === 5
      && sameJson(
        livenessEvents.map((event) => event.case_id),
        [
          "LIVENESS_NORMAL_PROGRESS",
          "LIVENESS_PROGRESS_RECEIPT_MISSING",
          "LIVENESS_WORKER_STALL",
          "LIVENESS_OBSERVER_STALL",
          "LIVENESS_EVIDENCE_WRITER_STALL",
        ],
      )
      && livenessEvents.every(
        (event, index) =>
          event.sequence === index + 1
          && sameJson(event.argv, [
            process.execPath,
            fileURLToPath(import.meta.url),
            "--liveness-child",
            event.case_id,
          ])
          && Number.isFinite(Date.parse(event.started_at))
          && Number.isFinite(Date.parse(event.stopped_at))
          && Date.parse(event.started_at) <= Date.parse(event.stopped_at)
          && event.heartbeats.every(
            (heartbeat) =>
              Date.parse(heartbeat.emitted_at) >= Date.parse(event.started_at)
              && Date.parse(heartbeat.emitted_at) <= Date.parse(event.stopped_at),
          )
          && (
            index === 0
              ? event.timeout_ms === 2_000
                && event.heartbeat_count === 2
                && event.observed_reason_code === "PASS"
                && event.exit_status === 0
                && event.signal === null
                && event.timed_out === false
              : index === 1
                ? event.timeout_ms === 2_000
                  && event.heartbeat_count === 1
                  && event.observed_reason_code === "PROGRESS_RECEIPT_MISSING"
                  && event.exit_status === 0
                  && event.signal === null
                  && event.timed_out === false
                : event.timeout_ms === 150
                  && event.heartbeat_count === 1
                  && event.exit_status === null
                  && event.signal === "SIGTERM"
                  && event.timed_out === true
          ),
      ),
    "ACCOUNTING_MISMATCH",
    "actual liveness raw event set is incomplete",
  );
  writeBytesCreateOnce(
    handle,
    "raw/liveness/events.jsonl",
    Buffer.from(`${livenessEvents.map((event) => canonicalJson(event)).join("\n")}\n`),
  );
}

function writeReferenceAnswerScan(handle, cellOrder) {
  const scanPaths = cellOrder.flatMap((cell) =>
    ["request.raw", "request-record.json", "context.json"].map(
      (suffix) => `raw/cells/${cell.cell_id}/${suffix}`,
    )).sort();
  assertCritical(
    scanPaths.length === 108 && new Set(scanPaths).size === 108,
    "ACCOUNTING_MISMATCH",
    "reference scan input set is not the exact 108 request/context artifacts",
  );
  const referencePatterns = ACCEPTED_TASK_IDS.map((taskId) => {
    const repositoryPath = [
      "evaluation-harness/datasets/p1-representative-task-dataset-v1/tasks",
      taskId,
      "reference-solution.patch",
    ].join("/");
    const absolute = join(REPOSITORY_ROOT, ...repositoryPath.split("/"));
    const stat = lstatSync(absolute);
    assertCritical(
      stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
      stat.isSymbolicLink()
        ? "SYMLINK_REJECTED"
        : !stat.isFile()
          ? "NON_REGULAR_FILE_REJECTED"
          : stat.nlink !== 1
            ? "HARDLINK_REJECTED"
            : "NON_REGULAR_FILE_REJECTED",
      `accepted reference patch identity is unsafe: ${taskId}`,
    );
    const bytes = readFileSync(absolute);
    return {
      task_id: taskId,
      repository_path: repositoryPath,
      type: "REGULAR_FILE",
      nlink: 1,
      byte_length: bytes.length,
      sha256: sha256(bytes),
      bytes,
      sha_bytes: Buffer.from(sha256(bytes), "ascii"),
    };
  });
  const plan = {
    schema_version: "p1-165-reference-scan-plan/v1",
    task_id: TASK_ID,
    scan_paths: scanPaths,
    reference_artifacts: referencePatterns.map((pattern) => ({
      task_id: pattern.task_id,
      repository_path: pattern.repository_path,
      type: pattern.type,
      nlink: pattern.nlink,
      byte_length: pattern.byte_length,
      sha256: pattern.sha256,
    })),
    checks: ["EXACT_REFERENCE_BYTES", "REFERENCE_SHA256_ASCII"],
  };
  const planIdentity = writeJsonCreateOnce(
    handle,
    "raw/reference-scan/plan.json",
    plan,
  );
  let leaks = 0;
  const events = scanPaths.map((path, index) => {
    const bytes = readFileSync(join(handle.root, ...path.split("/")));
    const checks = referencePatterns.map((pattern) => {
      const exactFound = bytes.indexOf(pattern.bytes) !== -1;
      const shaFound = bytes.indexOf(pattern.sha_bytes) !== -1;
      if (exactFound || shaFound) leaks += 1;
      return {
        task_id: pattern.task_id,
        reference_sha256: pattern.sha256,
        exact_reference_bytes_found: exactFound,
        reference_sha256_ascii_found: shaFound,
      };
    });
    return {
      schema_version: "p1-165-reference-scan-event/v1",
      task_id: TASK_ID,
      sequence: index + 1,
      input_identity: identityWithPath(handle.root, path),
      checks,
      status: exactFoundOrSha(checks) ? "NON_PASS" : "PASS",
    };
  });
  assertCritical(
    leaks === 0 && events.every((event) => event.status === "PASS"),
    "SECRET_REFLECTION_DETECTED",
    "accepted reference-answer material was found in request/context Evidence",
  );
  const eventBytes = Buffer.from(
    `${events.map((event) => canonicalJson(event)).join("\n")}\n`,
    "utf8",
  );
  const eventsIdentity = writeBytesCreateOnce(
    handle,
    "raw/reference-scan/events.jsonl",
    eventBytes,
  );
  writeJsonCreateOnce(handle, "raw/reference-scan/receipt.json", {
    schema_version: "p1-165-reference-scan-receipt/v1",
    task_id: TASK_ID,
    plan_identity: planIdentity,
    events_identity: eventsIdentity,
    files_scanned: scanPaths.length,
    reference_artifacts: referencePatterns.length,
    reference_patterns: referencePatterns.length * 2,
    leaks,
    status: "PASS",
  });
  return {
    files_scanned: scanPaths.length,
    reference_patterns: referencePatterns.length * 2,
    leaks,
  };
}

const ACCEPTED_INPUT_CONFIG = Object.freeze({
  p1_035: {
    source_roots: [
      "evaluation-harness/datasets/p1-representative-task-dataset-v1",
      "evaluation-harness/validators/task-dataset-self-test.mjs",
      "evaluation-harness/validators/task-dataset-validator.mjs",
      "scripts/verify-p1-task-dataset.sh",
    ],
    verifier: ["/bin/bash", "scripts/verify-p1-task-dataset.sh"],
  },
  p1_101: {
    source_roots: [
      "evaluation-harness/harness/p1-101-accepted-shared-trace",
      "evaluation-harness/recording/p1-101-accepted-shared-trace",
      "evaluation-harness/replay/p1-101-accepted-shared-trace",
      "evaluation-harness/evaluator/p1-101-accepted-shared-trace",
      "evaluation-harness/fixtures/p1-101-accepted-shared-trace",
      "scripts/verify-p1-101-accepted-shared-trace.sh",
    ],
    verifier: [
      "/bin/bash",
      "scripts/verify-p1-101-accepted-shared-trace.sh",
    ],
  },
  p1_129: {
    source_roots: [
      "evaluation-harness/adapters/p1-125-six-task-parameterized",
      "evaluation-harness/harness/p1-125-six-task-parameterized",
      "evaluation-harness/recording/p1-125-six-task-parameterized",
      "evaluation-harness/replay/p1-125-six-task-parameterized",
      "evaluation-harness/evaluator/p1-125-six-task-parameterized",
      "evaluation-harness/fixtures/p1-125-six-task-parameterized",
      "scripts/verify-p1-125-six-task-parameterized.sh",
    ],
    verifier: [
      "/usr/local/bin/node",
      "-e",
      ACCEPTED_P1_129_SEMANTIC_VERIFIER_SOURCE,
    ],
  },
  p1_149: {
    source_roots: [
      "evaluation-harness/harness/p1-149-accepted-execution-spine",
      "evaluation-harness/replay/p1-149-accepted-execution-spine",
      "evaluation-harness/evaluator/p1-149-accepted-execution-spine",
      "scripts/verify-p1-149-accepted-execution-spine.sh",
    ],
    verifier: [
      "/bin/bash",
      "scripts/verify-p1-149-accepted-execution-spine.sh",
    ],
  },
});

function rawCommand(handle, prefix, argv, { timeout = 20 * 60 * 1000 } = {}) {
  const startedAt = new Date().toISOString();
  const environment = closedChildEnvironment();
  const result = spawnSync(argv[0], argv.slice(1), {
    cwd: REPOSITORY_ROOT,
    encoding: null,
    env: environment,
    maxBuffer: 8 * 1024 * 1024,
    timeout,
  });
  const stoppedAt = new Date().toISOString();
  const stdout = Buffer.isBuffer(result.stdout)
    ? result.stdout
    : Buffer.from(result.stdout ?? "");
  const stderr = Buffer.isBuffer(result.stderr)
    ? result.stderr
    : Buffer.from(result.stderr ?? "");
  const stdoutIdentity = writeBytesCreateOnce(
    handle,
    `${prefix}/stdout.log`,
    stdout,
  );
  const stderrIdentity = writeBytesCreateOnce(
    handle,
    `${prefix}/stderr.log`,
    stderr,
  );
  const receipt = {
    schema_version: "p1-165-raw-command-receipt/v2",
    task_id: TASK_ID,
    argv,
    cwd: REPOSITORY_ROOT,
    environment,
    parent_pid: process.pid,
    pid: result.pid,
    exit_status: result.status,
    signal: result.signal,
    started_at: startedAt,
    stopped_at: stoppedAt,
    stdout: stdoutIdentity,
    stderr: stderrIdentity,
  };
  const receiptIdentity = writeJsonCreateOnce(
    handle,
    `${prefix}/receipt.json`,
    receipt,
  );
  return { result, stdout, stderr, receipt, receiptIdentity };
}

function sourceManifest(paths) {
  const entries = [];
  const addFile = (absolute, relativePath) => {
    const stat = lstatSync(absolute);
    assertCritical(
      stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
      stat.isSymbolicLink()
        ? "SYMLINK_REJECTED"
        : !stat.isFile()
          ? "NON_REGULAR_FILE_REJECTED"
          : stat.nlink !== 1
            ? "HARDLINK_REJECTED"
            : "NON_REGULAR_FILE_REJECTED",
      `accepted source artifact is unsafe: ${relativePath}`,
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
  const visit = (absolute, relativePath) => {
    const stat = lstatSync(absolute);
    assertCritical(
      !stat.isSymbolicLink(),
      "SYMLINK_REJECTED",
      `accepted source root contains symlink: ${relativePath}`,
    );
    if (stat.isFile()) {
      addFile(absolute, relativePath);
      return;
    }
    assertCritical(
      stat.isDirectory(),
      "NON_REGULAR_FILE_REJECTED",
      `accepted source root is not a directory or file: ${relativePath}`,
    );
    for (const name of readdirSync(absolute).sort()) {
      visit(join(absolute, name), `${relativePath}/${name}`);
    }
  };
  for (const path of paths) {
    visit(join(REPOSITORY_ROOT, ...path.split("/")), path);
  }
  entries.sort((left, right) => left.path.localeCompare(right.path));
  assertCritical(
    new Set(entries.map((entry) => entry.path)).size === entries.length,
    "ORDERED_IDENTITY_SET_INVALID",
    "accepted source manifest contains duplicate paths",
  );
  return entries;
}

function writeAcceptedInputProvenance(handle) {
  const truthPath = join(
    REPOSITORY_ROOT,
    "docs/aios/truth/project_state.yaml",
  );
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
  const truthCommand = rawCommand(
    handle,
    "raw/accepted-inputs/truth-command",
    ["/usr/bin/ruby", "-e", rubyProgram, truthPath],
    { timeout: 30_000 },
  );
  assertCritical(
    truthCommand.result.status === 0,
    "IDENTITY_MISMATCH",
    "canonical Truth accepted-input extraction failed",
  );
  const accepted = JSON.parse(truthCommand.stdout.toString("utf8"));
  const truthExtractIdentity = writeJsonCreateOnce(
    handle,
    "raw/accepted-inputs/truth-extract.json",
    {
      schema_version: "p1-165-accepted-input-truth-extract/v1",
      task_id: TASK_ID,
      truth: {
        path: "docs/aios/truth/project_state.yaml",
        ...bytesIdentity(readFileSync(truthPath)),
      },
      accepted_inputs: accepted,
    },
  );
  const inputs = [];
  for (const [key, config] of Object.entries(ACCEPTED_INPUT_CONFIG)) {
    const value = accepted[key];
    assertCritical(
      value?.status === "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
        && typeof value.task_id === "string"
        && typeof value.task_contract_path === "string"
        && /^[0-9a-f]{64}$/.test(value.task_contract_sha256)
        && /^[0-9a-f]{40}$/.test(value.accepted_candidate_commit)
        && /^[0-9a-f]{40}$/.test(value.accepted_candidate_tree),
      "IDENTITY_MISMATCH",
      `canonical Truth accepted input is invalid: ${key}`,
    );
    const contractBytes = readFileSync(
      join(REPOSITORY_ROOT, ...value.task_contract_path.split("/")),
    );
    assertCritical(
      sha256(contractBytes) === value.task_contract_sha256,
      "IDENTITY_MISMATCH",
      `accepted Task Contract identity drifted: ${key}`,
    );
    const commandRoot = `raw/accepted-inputs/commands/${key}`;
    const catFile = rawCommand(
      handle,
      `${commandRoot}/git-cat-file`,
      ["/usr/bin/git", "cat-file", "-e", `${value.accepted_candidate_commit}^{commit}`],
      { timeout: 30_000 },
    );
    const tree = rawCommand(
      handle,
      `${commandRoot}/git-tree`,
      ["/usr/bin/git", "show", "-s", "--format=%T", value.accepted_candidate_commit],
      { timeout: 30_000 },
    );
    const ancestry = rawCommand(
      handle,
      `${commandRoot}/git-ancestry`,
      ["/usr/bin/git", "merge-base", "--is-ancestor", value.accepted_candidate_commit, "HEAD"],
      { timeout: 30_000 },
    );
    const verifier = rawCommand(
      handle,
      `${commandRoot}/accepted-verifier`,
      config.verifier,
    );
    assertCritical(
      catFile.result.status === 0
        && tree.result.status === 0
        && tree.stdout.toString("utf8").trim() === value.accepted_candidate_tree
        && ancestry.result.status === 0
        && verifier.result.status === 0,
      "IDENTITY_MISMATCH",
      `accepted input Git/verifier provenance failed: ${key}`,
    );
    const sourceEntries = sourceManifest(config.source_roots);
    const manifestIdentity = writeJsonCreateOnce(
      handle,
      `raw/accepted-inputs/source-manifests/${key}.json`,
      {
        schema_version: "p1-165-accepted-source-manifest/v1",
        task_id: TASK_ID,
        accepted_input_id: key,
        source_roots: config.source_roots,
        entry_count: sourceEntries.length,
        entries: sourceEntries,
      },
    );
    inputs.push({
      accepted_input_id: key,
      truth_record: value,
      contract_identity: {
        path: value.task_contract_path,
        ...bytesIdentity(contractBytes),
      },
      source_manifest: manifestIdentity,
      git_cat_file_receipt: catFile.receiptIdentity,
      git_tree_receipt: tree.receiptIdentity,
      git_ancestry_receipt: ancestry.receiptIdentity,
      accepted_verifier_receipt: verifier.receiptIdentity,
    });
  }
  const receipt = writeJsonCreateOnce(
    handle,
    "raw/accepted-inputs/receipt.json",
    {
      schema_version: "p1-165-accepted-input-provenance/v1",
      task_id: TASK_ID,
      truth_extract: truthExtractIdentity,
      truth_command_receipt: truthCommand.receiptIdentity,
      accepted_input_order: Object.keys(ACCEPTED_INPUT_CONFIG),
      inputs,
      status: "PASS",
    },
  );
  return { receipt, inputs: inputs.length };
}

function exactFoundOrSha(checks) {
  return checks.some(
    (check) => check.exact_reference_bytes_found
      || check.reference_sha256_ascii_found,
  );
}

function closedCommitInventory(handle) {
  return listClosedFiles(handle.root)
    .map((entry) => {
      const stat = lstatSync(join(handle.root, ...entry.path.split("/")));
      assertCritical(
        stat.isFile() && !stat.isSymbolicLink() && stat.nlink === 1,
        stat.isSymbolicLink()
          ? "SYMLINK_REJECTED"
          : !stat.isFile()
            ? "NON_REGULAR_FILE_REJECTED"
            : stat.nlink !== 1
              ? "HARDLINK_REJECTED"
              : "NON_REGULAR_FILE_REJECTED",
        `root inventory path is unsafe: ${entry.path}`,
      );
      return {
        path: entry.path,
        type: "REGULAR_FILE",
        nlink: 1,
        byte_length: entry.byte_length,
        sha256: entry.sha256,
      };
    })
    .sort((left, right) => left.path.localeCompare(right.path));
}

function writeWholeStageSecretScan(handle, sentinels) {
  assertCritical(
    Array.isArray(sentinels)
      && sentinels.length === 2
      && sentinels.every(
        (sentinel) => Buffer.isBuffer(sentinel) && sentinel.length >= 16,
      ),
    "REQUEST_KEYSET_INVALID",
    "whole-stage Secret scan requires exactly two bounded test sentinels",
  );
  const entries = closedCommitInventory(handle);
  assertCritical(
    entries.length > 0,
    "EVIDENCE_WRITE_FAILED",
    "whole-stage Secret scan requires retained Evidence",
  );
  const buffers = entries.map((entry) =>
    readFileSync(join(handle.root, ...entry.path.split("/")))
  );
  for (const sentinel of sentinels) {
    assertNoSecretReflection(buffers, sentinel);
  }
  const receipt = {
    schema_version: "p1-165-whole-stage-secret-scan/v1",
    task_id: TASK_ID,
    files_scanned: entries.length,
    adjacent_buffer_composition_scanned: true,
    sentinels_scanned: sentinels.length,
    representations_scanned_per_sentinel: 5,
    leaks: 0,
    status: "PASS",
  };
  const receiptBytes = canonicalBytes(receipt);
  for (const sentinel of sentinels) {
    assertNoSecretReflection([receiptBytes], sentinel);
  }
  writeBytesCreateOnce(
    handle,
    "raw/secret-closure/whole-stage-scan-receipt.json",
    receiptBytes,
  );
  return receipt;
}

function readCommittedFileNoFollow(root, entry) {
  const path = join(root, ...entry.path.split("/"));
  const before = lstatSync(path);
  assertCritical(
    before.isFile()
      && !before.isSymbolicLink()
      && before.nlink === 1,
    before.isSymbolicLink()
      ? "SYMLINK_REJECTED"
      : !before.isFile()
        ? "NON_REGULAR_FILE_REJECTED"
        : before.nlink !== 1
          ? "HARDLINK_REJECTED"
          : "NON_REGULAR_FILE_REJECTED",
    `committed Evidence path is unsafe: ${entry.path}`,
  );
  let descriptor = null;
  try {
    descriptor = openSync(
      path,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    const opened = fstatSync(descriptor);
    const bytes = readFileSync(descriptor);
    const after = lstatSync(path);
    assertCritical(
      opened.isFile()
        && opened.nlink === 1
        && opened.dev === before.dev
        && opened.ino === before.ino
        && after.dev === opened.dev
        && after.ino === opened.ino
        && after.nlink === 1
        && bytes.length === entry.byte_length
        && sha256(bytes) === entry.sha256,
      "IDENTITY_MISMATCH",
      `committed Evidence path drifted during no-follow read: ${entry.path}`,
    );
    return bytes;
  } catch (error) {
    if (error instanceof AdmissionNonPass) throw error;
    failCritical(
      error?.code === "ELOOP"
        ? "SYMLINK_REJECTED"
        : "EVIDENCE_WRITE_FAILED",
      `committed Evidence no-follow read failed: ${error?.code ?? error?.message}`,
    );
  } finally {
    if (descriptor !== null) closeSync(descriptor);
  }
}

function inspectCommittedSecretClosure(finalRoot, expectedInventory, sentinels) {
  const committedInventory = closedCommitInventory({ root: finalRoot });
  assertCritical(
    canonicalJson(committedInventory) === canonicalJson(expectedInventory),
    "CLOSED_INVENTORY_DRIFT",
    "post-commit Evidence inventory does not equal the frozen inventory",
  );
  const buffers = committedInventory.map((entry) =>
    readCommittedFileNoFollow(finalRoot, entry)
  );
  for (const sentinel of sentinels) {
    assertNoSecretReflection(buffers, sentinel);
  }
  return {
    schema_version: "p1-165-post-commit-secret-scan/v1",
    task_id: TASK_ID,
    files_scanned: committedInventory.length,
    adjacent_buffer_composition_scanned: true,
    sentinels_scanned: sentinels.length,
    representations_scanned_per_sentinel: 5,
    leaks: 0,
    status: "PASS",
  };
}

function persistAtomicCommitReceipt({
  finalRoot,
  stagePath,
  committed,
  expectedInventory,
  expectedNonPassCases,
  sentinels,
}) {
  assertCritical(
    expectedNonPassCases.length === 100
      && committed.expected_non_pass_cases === 100,
    "CLOSED_INVENTORY_DRIFT",
    "atomic commit did not bind exactly 100 safe-only NON_PASS roots",
  );
  const lockPath = `${finalRoot}.p1-165-commit-lock`;
  const stagePathAbsent = !integrationFixtureExists(stagePath);
  const commitLockAbsent = !integrationFixtureExists(lockPath);
  assertCritical(
    stagePathAbsent
      && commitLockAbsent
      && sameJson(Object.keys(committed.staged_root).sort(), [
        "dev",
        "ino",
        "path",
        "uid",
      ])
      && committed.staged_root.path === stagePath
      && committed.staged_root.path !== committed.committed_root.path
      && committed.staged_root.dev === committed.committed_root.dev
      && committed.staged_root.ino === committed.committed_root.ino
      && committed.staged_root.uid === committed.committed_root.uid,
    "IDENTITY_MISMATCH",
    "atomic commit stage identity or cleanup drifted",
  );
  const postCommitSecretScan = inspectCommittedSecretClosure(
    finalRoot,
    expectedInventory,
    sentinels,
  );
  const receiptPath = `${finalRoot}.p1-165-atomic-commit-receipt.json`;
  assertCritical(
    !integrationFixtureExists(receiptPath),
    "ROOT_PREEXISTS",
    "atomic commit receipt path must be create-once and absent",
  );
  const receipt = {
    schema_version: "p1-165-atomic-evidence-commit-receipt/v1",
    task_id: TASK_ID,
    final_root: finalRoot,
    commit: committed,
    expected_non_pass_cases: expectedNonPassCases,
    post_commit_secret_scan: postCommitSecretScan,
    stage_path_absent: stagePathAbsent,
    commit_lock_absent: commitLockAbsent,
    status: "PASS",
  };
  const receiptBytes = canonicalBytes(receipt);
  for (const sentinel of sentinels) {
    assertNoSecretReflection([receiptBytes], sentinel);
  }
  let descriptor = null;
  try {
    descriptor = openSync(
      receiptPath,
      fsConstants.O_CREAT
        | fsConstants.O_EXCL
        | fsConstants.O_WRONLY
        | (fsConstants.O_NOFOLLOW ?? 0),
      0o600,
    );
    fchmodSync(descriptor, 0o600);
    writeFileSync(descriptor, receiptBytes);
    fsyncSync(descriptor);
    const persisted = fstatSync(descriptor);
    assertCritical(
      persisted.isFile()
        && persisted.nlink === 1
        && (persisted.mode & 0o777) === 0o600
        && persisted.size === receiptBytes.length,
      "IDENTITY_MISMATCH",
      "atomic commit receipt descriptor drifted",
    );
    closeSync(descriptor);
    descriptor = null;
    const parentDescriptor = openSync(dirname(receiptPath), fsConstants.O_RDONLY);
    try {
      fsyncSync(parentDescriptor);
    } finally {
      closeSync(parentDescriptor);
    }
    const verifyDescriptor = openSync(
      receiptPath,
      fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0),
    );
    try {
      const persisted = fstatSync(verifyDescriptor);
      const persistedBytes = readFileSync(verifyDescriptor);
      const after = lstatSync(receiptPath);
      assertCritical(
        persisted.isFile()
          && persisted.nlink === 1
          && after.dev === persisted.dev
          && after.ino === persisted.ino
          && after.nlink === 1
          && (after.mode & 0o777) === 0o600
          && persistedBytes.equals(receiptBytes),
        "IDENTITY_MISMATCH",
        "atomic commit receipt changed after fsync",
      );
      for (const sentinel of sentinels) {
        assertNoSecretReflection([persistedBytes], sentinel);
      }
    } finally {
      closeSync(verifyDescriptor);
    }
  } catch (error) {
    if (descriptor !== null) closeSync(descriptor);
    if (error instanceof AdmissionNonPass) throw error;
    failCritical(
      "EVIDENCE_WRITE_FAILED",
      `atomic commit receipt persistence failed: ${error?.code ?? error?.message}`,
    );
  }
  return {
    path: receiptPath,
    ...bytesIdentity(receiptBytes),
  };
}

function buildRootManifest(handle) {
  const entries = closedCommitInventory(handle)
    .filter((entry) => entry.path !== "RAW_EVIDENCE_MANIFEST.json")
    .sort((left, right) => left.path.localeCompare(right.path));
  const manifest = {
    schema_version: "p1-165-raw-evidence-manifest/v1",
    task_id: TASK_ID,
    matrix_sha256: MATRIX_SHA256,
    entry_count: entries.length,
    entries,
  };
  writeJsonCreateOnce(handle, "RAW_EVIDENCE_MANIFEST.json", manifest);
  return manifest;
}

export async function runPreflight(outputRoot) {
  const outputRootExists = typeof outputRoot === "string"
    && isAbsolute(outputRoot)
    && integrationFixtureExists(outputRoot);
  assertCritical(
    typeof outputRoot === "string"
      && isAbsolute(outputRoot)
      && resolve(outputRoot) === outputRoot
      && !outputRootExists,
    outputRootExists ? "ROOT_PREEXISTS" : "PATH_ESCAPE_REJECTED",
    "preflight output root must be absolute, normalized, and absent",
  );
  assertCritical(
    !integrationFixtureExists(
      `${outputRoot}.p1-165-atomic-commit-receipt.json`,
    )
      && !integrationFixtureExists(`${outputRoot}.p1-165-commit-lock`),
    "ROOT_PREEXISTS",
    "preflight atomic receipt and commit lock paths must both be absent",
  );
  const parent = safeRealDirectory(dirname(outputRoot), "preflight output parent");
  assertCritical(
    realpathSync(parent) === parent
      && statSync(parent).isDirectory()
      && !lstatSync(parent).isSymbolicLink(),
    "PATH_ESCAPE_REJECTED",
    "preflight output ancestor is unsafe",
  );
  const p1168GateInputs = captureP1168GateInputs(outputRoot);
  const stagePath = join(
    parent,
    `.${basename(outputRoot)}.p1-165-stage-${randomBytes(12).toString("hex")}`,
  );
  const handle = createOwnedRoot(stagePath);
  try {
    const matrix = loadMatrix();
  const caseOrder = flattenCases(matrix.value).map((entry) => entry.case_id);
  const cellOrder = PROFILE_ORDER.flatMap((profileId) => (
    ACCEPTED_TASK_IDS.map((taskId, index) => (
      `P1-165-CELL-${String(
        PROFILE_ORDER.indexOf(profileId) * ACCEPTED_TASK_IDS.length + index + 1,
      ).padStart(2, "0")}`
    ))
  ));
  writeJsonCreateOnce(handle, "raw/kernel-contract.json", {
    schema_version: "p1-165-raw-kernel-contract/v1",
    task_id: TASK_ID,
    matrix_sha256: MATRIX_SHA256,
    response_bytes_max: RESPONSE_BYTES_MAX,
    output_tokens_max: OUTPUT_TOKENS_MAX,
    case_order: caseOrder,
    cell_order: cellOrder,
    profile_order: PROFILE_ORDER,
    concurrency_slots: CONCURRENCY_SLOTS,
    external_effects: FALSE_EXTERNAL_EFFECTS,
  });
    const adapterControl = await runAcceptedAdapterControl(handle);
    const acceptedInputProvenance = writeAcceptedInputProvenance(handle);
    const baseJoin = {
    execution_id: "P1-165-CALIBRATION",
    cell_id: "P1-165-CELL-01",
    task_id: TASK_ID,
    profile_id: "B0_A",
    repetition_id: "A",
  };
    const baseRequestIdentity = bytesIdentity(canonicalBytes({
    schema_version: "p1-165-calibration-request/v1",
    task_id: TASK_ID,
  }));
    const calibration = buildFrozenSyntheticObserverFixture({
    evidence_handle: handle,
    join: baseJoin,
    request_record_identity: baseRequestIdentity,
    artifact_prefix: "raw/observer/calibration",
    fixture_index: 1,
  });
    const secretSentinel = Buffer.from(
      "P1-165-MATRIX-SECRET-SENTINEL-NEVER-PERSIST",
      "utf8",
    );
    const bases = {
      join: baseJoin,
      request_identity: baseRequestIdentity,
      response_identity: bytesIdentity(Buffer.from("{}\n")),
      policy: calibration.policy,
      calibration,
      secret_sentinel: secretSentinel,
      adapter_identity: adapterControl.index[
        `${ACCEPTED_TASK_IDS[0]}:${PROFILE_ORDER[0]}`
      ],
    };
    const ordinaryFailureControls = await runOrdinaryFailureControls(
      handle,
      bases,
    );
    const synthetic = await runSyntheticCells(handle, adapterControl);
    const ordinaryFailureReceipt = finalizeOrdinaryFailureControls(
      handle,
      ordinaryFailureControls,
      synthetic,
    );
    const tokenBoundary = await runOutputTokenBoundaryControls(handle, bases);
    writeB2ScanLedger(handle, adapterControl, synthetic.cellOrder);
    const integrationNegative = runIntegrationNegativeControls(handle, bases);
    const matrixRun = await writeMatrixCases(handle, matrix.value, bases);
    const historicalRegression = writeHistoricalRootCauseRegressionReceipt(
      handle,
      matrixRun,
      synthetic,
    );
    const createOnceControl = await runCreateOnceControl(handle);
    const livenessControl = await runLivenessControl(handle);
    writeEventLedgers(handle, createOnceControl, livenessControl);
    const referenceScan = writeReferenceAnswerScan(
      handle,
      synthetic.cellOrder,
    );
    assertP1168GateInputsStable(p1168GateInputs, outputRoot);
    const p1168Gate = writeP1168GateEnvelope(
      handle,
      p1168GateInputs,
      matrixRun,
    );
    const secondarySecretSentinel = Buffer.from(
      "P1-165-SECONDARY-SECRET-SENTINEL-NEVER-PERSIST",
      "utf8",
    );
    const secretClosure = writeWholeStageSecretScan(handle, [
      secretSentinel,
      secondarySecretSentinel,
    ]);
    const manifest = buildRootManifest(handle);
    assertP1168GateInputsStable(p1168GateInputs, outputRoot);
    const expectedInventory = closedCommitInventory(handle);
    const summary = {
    schema_version: "p1-165-offline-preflight/v1",
    task_id: TASK_ID,
    evidence_root: outputRoot,
    response_bytes_max: RESPONSE_BYTES_MAX,
    synthetic_cells: synthetic.cellOrder.length,
    b0_cells: synthetic.cellOrder.filter((entry) => entry.profile_id.startsWith("B0")).length,
    b1_cells: synthetic.cellOrder.filter((entry) => entry.profile_id.startsWith("B1")).length,
    b2_cells: synthetic.cellOrder.filter((entry) => entry.profile_id.startsWith("B2")).length,
    accepted_p1_149_execution_spines: synthetic.acceptedSpines,
    accepted_p1_101_replays: synthetic.acceptedReplays,
    ordinary_failure_denominator_cases:
      ordinaryFailureReceipt.failed_denominator_cases,
    real_b2_repository_analysis_scan_children: synthetic.realB2Children,
    matrix_cases: matrixRun.observations.length,
    p1_168_gate_envelope: p1168Gate.envelope_identity,
    prior_interrupted_attempt:
      p1168Gate.envelope.prior_interrupted_attempt,
    prior_complete_matrix_v2_and_global_gate:
      p1168Gate.envelope.prior_complete_matrix_v2_and_global_gate,
    current_kernel_source_bundle: {
      ...p1168Gate.source_bundle_identity,
      source_file_count: p1168Gate.source_bundle.source_file_count,
    },
    reproduction: p1168GateInputs.reproduction,
    historical_root_cause_regressions:
      historicalRegression.receipt.regressions,
    negative_cases: matrixRun.observations
      .filter((entry) => entry.status === "NON_PASS").length,
    integration_negative_cases: integrationNegative.receipt.cases,
    observer_fixture_source: "FROZEN_SYNTHETIC_OBSERVER_FIXTURE",
    synthetic_observer_fixtures: synthetic.cellOrder.length + 1,
    live_loopback_calibration: "DEFERRED_TO_P1_169",
    live_loopback_calibration_connections: 0,
    output_token_boundaries: {
      "2047": "ACCEPTED",
      "2048": "ACCEPTED",
      "2049": "REJECTED",
    },
    output_token_exact_boundary_full_spine:
      tokenBoundary.receipt.exact_boundary_full_p1_149_artifact_count,
    reference_leaks: referenceScan.leaks,
    reference_scan_files: referenceScan.files_scanned,
    reference_scan_patterns: referenceScan.reference_patterns,
    whole_stage_secret_scan:
      secretClosure.leaks === 0 ? "PASS" : "NON_PASS",
    accepted_input_provenance:
      acceptedInputProvenance.inputs === 4 ? "PASS" : "NON_PASS",
    persistence_before_admission:
      matrixRun.accounting.persistence_before_admission,
    safe_failure_receipts:
      matrixRun.accounting.safe_failure_receipts
      + integrationNegative.receipt.cases
      + tokenBoundary.expectedNonPassCases.length,
    admitted_matrix_cases: matrixRun.accounting.admitted,
    unsafe_failure_receipts: matrixRun.accounting.unsafe_failure_receipts,
    false_accepts: 0,
    provider_requests: 0,
    secret_reads: 0,
    external_effects: FALSE_EXTERNAL_EFFECTS,
    closed_inventory_entries: manifest.entry_count,
    status: "PASS",
    };
    const expectedNonPassCases = [
      ...matrixRun.expectedNonPassCases,
      ...integrationNegative.expectedNonPassCases,
      ...tokenBoundary.expectedNonPassCases,
    ];
    assertCritical(
      expectedNonPassCases.length === 100
        && matrixRun.expectedNonPassCases.length === 85
        && integrationNegative.expectedNonPassCases.length === 14
        && tokenBoundary.expectedNonPassCases.length === 1,
      "CLOSED_INVENTORY_DRIFT",
      "safe-only NON_PASS root accounting is not exactly 85 + 14 + 1",
    );
    const committed = commitOwnedEvidenceStage({
      stage_handle: handle,
      final_root: outputRoot,
      expected_inventory: expectedInventory,
      expected_non_pass_cases: expectedNonPassCases,
      secret_sentinel: secretSentinel,
    });
    assertCritical(
      committed.inventory_entries === manifest.entry_count + 1,
      "CLOSED_INVENTORY_DRIFT",
      "committed Evidence count does not include exactly the root manifest",
    );
    const atomicCommitReceipt = persistAtomicCommitReceipt({
      finalRoot: outputRoot,
      stagePath,
      committed,
      expectedInventory,
      expectedNonPassCases,
      sentinels: [secretSentinel, secondarySecretSentinel],
    });
    return {
      ...summary,
      expected_non_pass_cases: expectedNonPassCases.length,
      atomic_commit_receipt: atomicCommitReceipt,
    };
  } catch (error) {
    if (existsSync(stagePath)) cleanupOwnedRoot(handle);
    throw error;
  }
}

async function main(argv) {
  assertCritical(
    argv.length === 1 && isAbsolute(argv[0]),
    "PATH_ESCAPE_REJECTED",
    "usage: node preflight.mjs ABSOLUTE_ABSENT_OUTPUT_ROOT",
  );
  const result = await runPreflight(resolve(argv[0]));
  process.stdout.write(`${canonicalJson(result)}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const invocation = process.argv.slice(2);
  const operation = invocation[0] === "--matrix-case"
    ? Promise.resolve().then(() => {
        assertCritical(
          invocation.length === 5
            && isAbsolute(invocation[1])
            && typeof invocation[2] === "string"
            && /^[0-9]+$/.test(invocation[3])
            && /^[0-9a-f]{64}$/.test(invocation[4]),
          "PATH_ESCAPE_REJECTED",
          "matrix child invocation is invalid",
        );
        runMatrixCaseChild(
          resolve(invocation[1]),
          invocation[2],
          Number(invocation[3]),
          invocation[4],
        );
      })
    : invocation[0] === "--create-once-child"
      ? Promise.resolve().then(() => {
          assertCritical(
            invocation.length === 3 && isAbsolute(invocation[1]),
            "PATH_ESCAPE_REJECTED",
            "create-once child invocation is invalid",
          );
          runCreateOnceChild(resolve(invocation[1]), Number(invocation[2]));
        })
      : invocation[0] === "--liveness-child"
        ? Promise.resolve().then(() => {
            assertCritical(
              invocation.length === 2
                && /^LIVENESS_[A-Z0-9_]+$/.test(invocation[1]),
              "REQUEST_KEYSET_INVALID",
              "liveness child invocation is invalid",
            );
            return runLivenessChild(invocation[1]);
          })
    : main(invocation);
  operation.catch((error) => {
    const reasonCode = isCriticalReasonCode(error?.code)
      ? error.code
      : "EVIDENCE_WRITE_FAILED";
    process.stdout.write(`${canonicalJson({
      schema_version: "p1-165-preflight-failure/v1",
      task_id: TASK_ID,
      status: "NON_PASS",
      reason_code: reasonCode,
      divergences: Array.isArray(error?.details?.divergences)
        ? error.details.divergences
        : [],
      skipped_case_ids: Array.isArray(error?.details?.skipped_case_ids)
        ? error.details.skipped_case_ids
        : [],
    })}\n`);
    process.exitCode = 2;
  });
}

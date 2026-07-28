import {
  existsSync,
  linkSync,
  mkdirSync,
  readFileSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";

import {
  assert,
  applyFileBytesAtomic,
  bytesIdentity,
  canonicalBytes,
  cleanupOwnedRoot,
  copyClosedTree,
  createDisposableRoot,
  safeRegularFile,
  sha256,
} from "./core.mjs";
import {
  ACCEPTED_TASK_IDS,
  buildAcceptedReferenceResponse,
} from "./accepted-inputs.mjs";
import {
  compileNormalizedProviderResponse,
  compilePatchIrV2,
} from "./patch-ir-v2.mjs";

function jsonClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function compileRejectReceipt(caseId, expectedCodes, operation) {
  let observedCode = null;
  try {
    operation();
  } catch (error) {
    observedCode = typeof error?.code === "string" ? error.code : error?.name ?? "UNKNOWN_ERROR";
  }
  const rejected = observedCode !== null;
  assert(rejected, "NEGATIVE_FALSE_ACCEPT", `negative compiler case was accepted: ${caseId}`);
  assert(
    expectedCodes.includes(observedCode),
    "NEGATIVE_REASON_DRIFT",
    `negative compiler case rejected with an unexpected reason: ${caseId}`,
    { expected_codes: expectedCodes, observed_code: observedCode },
  );
  return {
    case_id: caseId,
    expected_codes: expectedCodes,
    observed_code: observedCode,
    rejected: true,
  };
}

function unownedMutationBoundaryReceipt(fixture) {
  const disposable = createDisposableRoot("negative-unowned-mutation");
  try {
    const ownedRoot = join(disposable.root, "owned");
    mkdirSync(ownedRoot, { recursive: false, mode: 0o700 });
    const outsidePath = join(disposable.root, "outside.txt");
    const outsideBytes = Buffer.from("must remain unchanged\n", "utf8");
    writeFileSync(outsidePath, outsideBytes, { flag: "wx", mode: 0o600 });
    const operation = jsonClone(fixture.ir.operations[0]);
    operation.path = "../outside.txt";
    let observedCode = null;
    try {
      applyFileBytesAtomic(ownedRoot, operation);
    } catch (error) {
      observedCode = typeof error?.code === "string" ? error.code : error?.name ?? "UNKNOWN_ERROR";
    }
    assert(
      ["PATH_INVALID", "PATH_ESCAPE_REJECTED"].includes(observedCode),
      "NEGATIVE_REASON_DRIFT",
      "unowned mutation was not rejected at the owned-root boundary",
      { observed_code: observedCode },
    );
    const observedBytes = readFileSync(safeRegularFile(outsidePath, "unowned sentinel", true));
    assert(
      observedBytes.equals(outsideBytes),
      "NEGATIVE_FALSE_ACCEPT",
      "unowned sentinel bytes changed after a rejected operation",
    );
    return {
      case_id: "UNOWNED_MUTATION_FORBIDDEN",
      observed_code: observedCode,
      sentinel_before: bytesIdentity(outsideBytes),
      sentinel_after: bytesIdentity(observedBytes),
      rejected: true,
    };
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

export function runPatchIrNegativeMatrix() {
  const accepted = new Map();
  const positive = [];
  for (const taskId of ACCEPTED_TASK_IDS) {
    const fixture = buildAcceptedReferenceResponse(taskId, `P1-149-NEG-POS-${taskId}`);
    const result = compileNormalizedProviderResponse(fixture.response_bytes, fixture.profile);
    assert(
      result.compiled.status === "COMPILED"
        && result.compiled.plan.operations.length === fixture.ir.operations.length
        && result.compiled.plan.operations.length >= 1,
      "POSITIVE_COMPILER_NON_PASS",
      `accepted task did not compile real finite operations: ${taskId}`,
    );
    accepted.set(taskId, fixture);
    positive.push({
      task_id: taskId,
      operation_count: result.compiled.plan.operations.length,
      operation_paths: result.compiled.plan.operations.map((operation) => operation.path),
      status: "COMPILED",
    });
  }

  const first = accepted.get(ACCEPTED_TASK_IDS[0]);
  const ordered = accepted.get(ACCEPTED_TASK_IDS[5]);
  const cases = [];

  cases.push(compileRejectReceipt(
    "IR_NONCANONICAL_BYTES",
    ["IR_JSON_NOT_CANONICAL"],
    () => compilePatchIrV2(Buffer.concat([first.ir_bytes, Buffer.from(" ", "utf8")]), first.profile),
  ));

  cases.push(compileRejectReceipt("IR_ROOT_EXTRA_FIELD", ["IR_SCHEMA_INVALID"], () => {
    const value = jsonClone(first.ir);
    value.expected_status = "PASS";
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_ROOT_MISSING_FIELD", ["IR_SCHEMA_INVALID"], () => {
    const value = jsonClone(first.ir);
    delete value.operations;
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_SELECTOR_ONLY", ["IR_SCHEMA_INVALID", "IR_OPERATION_INVALID"], () => {
    const value = jsonClone(first.ir);
    value.operations = [{
      op: "SELECT_PROGRAM",
      program_selector: "known-pass",
      expected_status: "PASS",
    }];
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_PATH_ESCAPE", ["IR_PATH_REJECTED"], () => {
    const value = jsonClone(first.ir);
    value.operations[0].path = "src/../outside.mjs";
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_ABSOLUTE_PATH", ["IR_PATH_REJECTED"], () => {
    const value = jsonClone(first.ir);
    value.operations[0].path = "/private/tmp/forbidden.mjs";
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_PREIMAGE_IDENTITY_DRIFT", ["IR_PREIMAGE_INVALID"], () => {
    const value = jsonClone(first.ir);
    value.operations[0].before.sha256 = "0".repeat(64);
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_POSTIMAGE_IDENTITY_DRIFT", ["IR_POSTIMAGE_INVALID"], () => {
    const value = jsonClone(first.ir);
    value.operations[0].postimage.sha256 = "0".repeat(64);
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_OPERATION_REORDER", ["IR_OPERATION_SET_INVALID"], () => {
    const value = jsonClone(ordered.ir);
    value.operations.reverse();
    compilePatchIrV2(canonicalBytes(value), ordered.profile);
  }));

  cases.push(compileRejectReceipt("IR_OPERATION_LIMIT", ["IR_OPERATION_SET_INVALID"], () => {
    const value = jsonClone(ordered.ir);
    value.operations.push(jsonClone(value.operations[0]));
    compilePatchIrV2(canonicalBytes(value), ordered.profile);
  }));

  cases.push(compileRejectReceipt("IR_OPERATION_DUPLICATE", ["IR_OPERATION_SET_INVALID", "IR_PREIMAGE_INVALID"], () => {
    const value = jsonClone(ordered.ir);
    value.operations[1] = jsonClone(value.operations[0]);
    compilePatchIrV2(canonicalBytes(value), ordered.profile);
  }));

  cases.push(compileRejectReceipt("IR_OPERATION_MISSING_FIELD", ["IR_SCHEMA_INVALID"], () => {
    const value = jsonClone(first.ir);
    delete value.operations[0].postimage;
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_OPERATION_EXTRA_FIELD", ["IR_SCHEMA_INVALID"], () => {
    const value = jsonClone(first.ir);
    value.operations[0].expected_status = "PASS";
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_MODE_DRIFT", ["IR_MODE_REJECTED"], () => {
    const value = jsonClone(first.ir);
    value.operations[0].mode = "100755";
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_TASK_BINDING_DRIFT", ["IR_TASK_BINDING_MISMATCH"], () => {
    const value = jsonClone(first.ir);
    value.task.base_tree = "0".repeat(40);
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_DATASET_BINDING_DRIFT", ["IR_DATASET_BINDING_MISMATCH"], () => {
    const value = jsonClone(first.ir);
    value.dataset.manifest_sha256 = "0".repeat(64);
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("IR_CREATE_PATH_NOT_CLOSED", ["IR_PATH_REJECTED"], () => {
    const value = jsonClone(ordered.ir);
    const create = value.operations.find((operation) => operation.op === "CREATE_REGULAR_FILE");
    assert(create, "NEGATIVE_FIXTURE_INVALID", "accepted multi-file fixture has no create operation");
    create.path = "src/unapproved-created-path.mjs";
    value.operations.sort((left, right) => left.path.localeCompare(right.path));
    compilePatchIrV2(canonicalBytes(value), ordered.profile);
  }));

  cases.push(compileRejectReceipt("IR_TOTAL_POSTIMAGE_LIMIT", ["IR_POSTIMAGE_LIMIT_EXCEEDED"], () => {
    const value = jsonClone(first.ir);
    const oversized = Buffer.alloc(65537, 0x61);
    value.operations[0].postimage = {
      base64: oversized.toString("base64"),
      sha256: sha256(oversized),
      byte_length: oversized.length,
    };
    compilePatchIrV2(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("COMPILER_PROFILE_HASH_INVALID", ["COMPILER_PROFILE_INVALID"], () => {
    const profile = jsonClone(first.profile);
    profile.base_commit = "not-a-commit";
    compilePatchIrV2(first.ir_bytes, profile);
  }));

  cases.push(compileRejectReceipt(
    "RESPONSE_NONCANONICAL_BYTES",
    ["IR_JSON_NOT_CANONICAL"],
    () => compileNormalizedProviderResponse(
      Buffer.concat([first.response_bytes, Buffer.from(" ", "utf8")]),
      first.profile,
    ),
  ));

  cases.push(compileRejectReceipt("RESPONSE_CONTENT_IDENTITY_DRIFT", ["RESPONSE_CONTENT_IDENTITY_MISMATCH"], () => {
    const value = JSON.parse(first.response_bytes.toString("utf8"));
    value.content_sha256 = "0".repeat(64);
    compileNormalizedProviderResponse(canonicalBytes(value), first.profile);
  }));

  cases.push(compileRejectReceipt("RESPONSE_TASK_BINDING_DRIFT", ["RESPONSE_TASK_BINDING_MISMATCH"], () => {
    const value = JSON.parse(first.response_bytes.toString("utf8"));
    value.task_id = ACCEPTED_TASK_IDS[1];
    compileNormalizedProviderResponse(canonicalBytes(value), first.profile);
  }));

  cases.push(unownedMutationBoundaryReceipt(first));

  return {
    schema_version: "p1-149-patch-ir-negative-matrix/v1",
    accepted_task_count: positive.length,
    positive,
    negative_case_count: cases.length,
    negative_cases: cases,
    false_accepts: 0,
    status: "PASS",
  };
}

function verifierRejected(verifier, root) {
  try {
    const value = verifier(root);
    if (value === false || value?.status === "NON_PASS" || value?.status === "FAIL") {
      return value?.reason_code ?? value?.status ?? "NON_PASS";
    }
  } catch (error) {
    return typeof error?.code === "string" ? error.code : error?.name ?? "UNKNOWN_ERROR";
  }
  return null;
}

function findArtifact(root, suffix) {
  for (const taskId of ACCEPTED_TASK_IDS) {
    const candidate = join(root, "tasks", taskId, suffix);
    if (existsSync(candidate)) return safeRegularFile(candidate, `negative fixture ${suffix}`);
  }
  assert(false, "NEGATIVE_FIXTURE_INVALID", `required Evidence artifact is absent: ${suffix}`);
}

function writeCanonicalReplacement(path, value) {
  writeFileSync(path, canonicalBytes(value), { flag: "w", mode: 0o600 });
}

function setPlausibleFailure(value) {
  if (value === null || typeof value !== "object") return false;
  if (!Array.isArray(value)) {
    if (
      Object.hasOwn(value, "result_classification")
        && value.result_classification === "VERIFIED_SUCCESS"
    ) {
      value.result_classification = "FAILED";
      return true;
    }
    if (Object.hasOwn(value, "exit_status") && Number.isInteger(value.exit_status)) {
      value.exit_status = value.exit_status === 0 ? 1 : value.exit_status;
      return true;
    }
    if (Object.hasOwn(value, "status") && value.status === "PASS") {
      value.status = "NON_PASS";
      return true;
    }
    if (Object.hasOwn(value, "passed") && value.passed === true) {
      value.passed = false;
      return true;
    }
  }
  for (const child of Array.isArray(value) ? value : Object.values(value)) {
    if (setPlausibleFailure(child)) return true;
  }
  return false;
}

function rebuildManifest(root, buildClosedEvidenceManifest) {
  const manifestPath = join(root, "MANIFEST.json");
  if (existsSync(manifestPath)) unlinkSync(manifestPath);
  const built = buildClosedEvidenceManifest(root);
  const manifest = built?.manifest ?? built;
  const bytes = Buffer.isBuffer(built?.bytes) ? built.bytes : canonicalBytes(manifest);
  writeFileSync(manifestPath, bytes, { flag: "wx", mode: 0o600 });
}

function evidenceRejectReceipt({
  caseId,
  sourceRoot,
  verifyFrozenExecutionEvidence,
  buildClosedEvidenceManifest,
  refreshManifest,
  mutate,
}) {
  const disposable = createDisposableRoot(`negative-${caseId.toLowerCase().replaceAll("_", "-")}`);
  try {
    const fixtureRoot = join(disposable.root, "evidence");
    copyClosedTree(sourceRoot, fixtureRoot);
    mutate(fixtureRoot);
    if (refreshManifest) rebuildManifest(fixtureRoot, buildClosedEvidenceManifest);
    const observedCode = verifierRejected(verifyFrozenExecutionEvidence, fixtureRoot);
    assert(observedCode !== null, "NEGATIVE_FALSE_ACCEPT", `negative Evidence case was accepted: ${caseId}`);
    return {
      case_id: caseId,
      inventory_rebound_before_verification: refreshManifest,
      observed_code: observedCode,
      rejected: true,
    };
  } finally {
    cleanupOwnedRoot(disposable);
  }
}

export function runEvidenceNegativeMatrix({
  evidenceRoot,
  verifyFrozenExecutionEvidence,
  buildClosedEvidenceManifest,
}) {
  assert(
    typeof verifyFrozenExecutionEvidence === "function"
      && typeof buildClosedEvidenceManifest === "function",
    "NEGATIVE_MATRIX_INTERFACE_INVALID",
    "Evidence negative matrix requires semantic verifier and closed-manifest builder",
  );
  const cases = [];
  const run = (definition) => cases.push(evidenceRejectReceipt({
    sourceRoot: evidenceRoot,
    verifyFrozenExecutionEvidence,
    buildClosedEvidenceManifest,
    ...definition,
  }));

  run({
    caseId: "EVIDENCE_CONTENT_TAMPER",
    refreshManifest: false,
    mutate(root) {
      const path = findArtifact(root, "provider-response.json");
      writeFileSync(path, Buffer.concat([readFileSync(path), Buffer.from(" ", "utf8")]));
    },
  });

  run({
    caseId: "EVIDENCE_REQUIRED_FILE_MISSING",
    refreshManifest: false,
    mutate(root) {
      unlinkSync(findArtifact(root, "patch-ir.json"));
    },
  });

  run({
    caseId: "EVIDENCE_CLOSED_INVENTORY_EXTRA",
    refreshManifest: false,
    mutate(root) {
      writeFileSync(join(root, "unexpected-worker-output.json"), canonicalBytes({ claimed_success: true }), {
        flag: "wx",
        mode: 0o600,
      });
    },
  });

  run({
    caseId: "EVIDENCE_SYMLINK",
    refreshManifest: false,
    mutate(root) {
      symlinkSync("run-plan.json", join(root, "forbidden-link"));
    },
  });

  run({
    caseId: "EVIDENCE_HARDLINK",
    refreshManifest: false,
    mutate(root) {
      const source = findArtifact(root, "provider-response.json");
      linkSync(source, join(root, "forbidden-hardlink"));
    },
  });

  run({
    caseId: "EVIDENCE_EMPTY_DIRECTORY",
    refreshManifest: false,
    mutate(root) {
      mkdirSync(join(root, "forbidden-empty-directory"), { recursive: false, mode: 0o700 });
    },
  });

  run({
    caseId: "TRACE_EVENT_REORDER",
    refreshManifest: true,
    mutate(root) {
      const path = findArtifact(root, "p1-101-trace.jsonl");
      const lines = readFileSync(path, "utf8").trimEnd().split("\n");
      assert(lines.length >= 2, "NEGATIVE_FIXTURE_INVALID", "trace has fewer than two events");
      [lines[0], lines[1]] = [lines[1], lines[0]];
      writeFileSync(path, Buffer.from(`${lines.join("\n")}\n`, "utf8"));
    },
  });

  run({
    caseId: "TRACE_EVENT_MISSING",
    refreshManifest: true,
    mutate(root) {
      const path = findArtifact(root, "p1-101-trace.jsonl");
      const lines = readFileSync(path, "utf8").trimEnd().split("\n");
      lines.pop();
      writeFileSync(path, Buffer.from(`${lines.join("\n")}\n`, "utf8"));
    },
  });

  run({
    caseId: "TRACE_EVENT_DUPLICATE",
    refreshManifest: true,
    mutate(root) {
      const path = findArtifact(root, "p1-101-trace.jsonl");
      const lines = readFileSync(path, "utf8").trimEnd().split("\n");
      lines.splice(1, 0, lines[0]);
      writeFileSync(path, Buffer.from(`${lines.join("\n")}\n`, "utf8"));
    },
  });

  run({
    caseId: "COMPILER_PLAN_IDENTITY_DRIFT",
    refreshManifest: true,
    mutate(root) {
      const path = findArtifact(root, "compiler-plan.json");
      const value = JSON.parse(readFileSync(path, "utf8"));
      value.base_tree = "0".repeat(40);
      writeCanonicalReplacement(path, value);
    },
  });

  run({
    caseId: "ROLLBACK_IDENTITY_DRIFT",
    refreshManifest: true,
    mutate(root) {
      const path = findArtifact(root, "rollback-receipt.json");
      const value = JSON.parse(readFileSync(path, "utf8"));
      value.restored_snapshot.sha256 = "0".repeat(64);
      writeCanonicalReplacement(path, value);
    },
  });

  run({
    caseId: "WORKER_FALSE_SUCCESS_CANNOT_OVERRIDE_RAW_ORACLE",
    refreshManifest: true,
    mutate(root) {
      const path = findArtifact(root, "oracle-receipt.json");
      const value = JSON.parse(readFileSync(path, "utf8"));
      assert(
        setPlausibleFailure(value),
        "NEGATIVE_FIXTURE_INVALID",
        "oracle receipt has no independently falsifiable result field",
      );
      writeCanonicalReplacement(path, value);
    },
  });

  return {
    schema_version: "p1-149-evidence-negative-matrix/v1",
    negative_case_count: cases.length,
    negative_cases: cases,
    false_accepts: 0,
    status: "PASS",
  };
}

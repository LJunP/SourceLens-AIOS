#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  FALSE_EXTERNAL_EFFECTS,
  AdmissionError,
  assertNoSymlinkComponents,
  cleanupOwnedSource,
  materializeSource,
  parseBoundJson,
  readBoundFile,
  reject,
  sha256,
  sha256Json,
  stableJson,
  validateFreshRootPlans,
  writeEvidence
} from "../../recording/blind-admission-v1/recorder.mjs";
import {
  parseOptions,
  sanitizedEnvironment,
  validateExecutable,
  validateOpaqueBindings,
  validateRuntimeProfile,
  validateSource,
  validateTaskCard
} from "../../validators/blind-admission-v1/validator.mjs";

const countOccurrences = (content, needle) => {
  let count = 0;
  let offset = 0;
  while (true) {
    const found = content.indexOf(needle, offset);
    if (found < 0) return count;
    count += 1;
    offset = found + needle.length;
  }
};

const containedBy = (root, candidate) => candidate === root || candidate.startsWith(`${root}${path.sep}`);

const validateOwnedRoot = (options, protectedPaths) => {
  const ownedRoot = options["owned-root"];
  assertNoSymlinkComponents(ownedRoot);
  const stat = fs.lstatSync(ownedRoot);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o700) reject("ROOT_NOT_FRESH");
  const ownedReal = fs.realpathSync(ownedRoot);
  const sourcePlan = path.resolve(options["source-root"]);
  const evidencePlan = path.resolve(options["evidence-root"]);
  if (fs.existsSync(sourcePlan)) reject("SOURCE_ROOT_ALREADY_EXISTS");
  if (fs.existsSync(evidencePlan)) reject("OUTPUT_ALREADY_EXISTS");
  if (fs.readdirSync(ownedRoot).length !== 0) reject("ROOT_NOT_FRESH");
  if (path.dirname(sourcePlan) !== ownedReal || path.dirname(evidencePlan) !== ownedReal) reject("PATH_OUTSIDE_OWNED_ROOT");
  if (path.basename(sourcePlan) === path.basename(evidencePlan)) reject("ROOT_ALIAS_OR_OVERLAP");
  for (const protectedPath of protectedPaths) {
    const resolved = fs.realpathSync(protectedPath);
    if (containedBy(ownedReal, resolved) || containedBy(resolved, ownedReal)) reject("ROOT_ALIAS_OR_OVERLAP");
  }
  validateFreshRootPlans({ sourceRoot: sourcePlan, evidenceRoot: evidencePlan, canonicalRoot: options["canonical-root"] });
  return ownedReal;
};

const main = () => {
  const started = process.hrtime.bigint();
  const options = parseOptions(process.argv.slice(2));
  const timeoutMs = validateOpaqueBindings(options);
  const environment = sanitizedEnvironment();
  if (sha256Json(environment) !== options["environment-sha256"]) reject("EXECUTION_BINDING_MISMATCH");
  if (process.execArgv.length !== 0) reject("EXECUTION_BINDING_MISMATCH");

  const modulePath = fileURLToPath(import.meta.url);
  const recorderPath = fileURLToPath(new URL("../../recording/blind-admission-v1/recorder.mjs", import.meta.url));
  const validatorPath = fileURLToPath(new URL("../../validators/blind-admission-v1/validator.mjs", import.meta.url));
  if (fs.realpathSync(process.argv[1]) !== fs.realpathSync(modulePath)) reject("RESULT_CONTROLLED_EXECUTION_FORBIDDEN");
  const moduleInput = readBoundFile(modulePath, options["candidate-module-sha256"], Number(options["candidate-module-byte-length"]), "EXECUTING_MODULE");
  const recorderInput = readBoundFile(recorderPath, options["recorder-module-sha256"], Number(options["recorder-module-byte-length"]), "RECORDER_MODULE");
  const validatorInput = readBoundFile(validatorPath, options["validator-module-sha256"], Number(options["validator-module-byte-length"]), "VALIDATOR_MODULE");
  if (fs.realpathSync(options["canonical-root"]) !== fs.realpathSync(options["logical-cwd"]) || process.cwd() !== options["logical-cwd"]) reject("EXECUTION_BINDING_MISMATCH");

  const taskInput = parseBoundJson(options["task-card"], options["task-card-sha256"], Number(options["task-card-byte-length"]), "TASK_CARD");
  const sourceInput = parseBoundJson(options.source, options["source-sha256"], Number(options["source-byte-length"]), "SOURCE");
  const runtimeInput = parseBoundJson(options["runtime-profile"], options["runtime-profile-sha256"], Number(options["runtime-profile-byte-length"]), "RUNTIME_PROFILE");
  validateTaskCard(taskInput.json);
  validateSource(sourceInput.json);
  validateRuntimeProfile(runtimeInput.json);
  if (taskInput.json.source_artifact.sha256 !== sourceInput.sha256 || taskInput.json.source_artifact.byte_length !== sourceInput.byte_length) reject("SOURCE_IDENTITY_MISMATCH");
  if (taskInput.json.runtime_profile.sha256 !== runtimeInput.sha256 || taskInput.json.runtime_profile.byte_length !== runtimeInput.byte_length) reject("RUNTIME_PROFILE_IDENTITY_MISMATCH");
  if (timeoutMs !== taskInput.json.execution_policy.timeout_ms) reject("EXECUTION_BINDING_MISMATCH");
  const executable = validateExecutable(runtimeInput.json);
  validateOwnedRoot(options, [options["canonical-root"], options["task-card"], options.source, options["runtime-profile"], modulePath, recorderPath, validatorPath]);

  const sourcePaths = sourceInput.json.files.map((entry) => entry.path).sort();
  const operation = taskInput.json.operation;
  const targetEntry = sourceInput.json.files.find((entry) => entry.path === operation.relative_path);
  if (!targetEntry) reject("SOURCE_MANIFEST_DRIFT");
  if (operation.match === operation.replacement) reject("NO_MATERIAL_CHANGE");
  const replacementCount = countOccurrences(targetEntry.content, operation.match);
  if (replacementCount === 0) reject("EMPTY_PATCH");
  if (replacementCount !== operation.expected_replacements) reject("MATCH_COUNT_MISMATCH");

  let ownership;
  let evidenceRootOwned = false;
  try {
    ownership = materializeSource(options["source-root"], sourceInput.json.files);
    const targetPath = path.join(options["source-root"], ...operation.relative_path.split("/"));
    const targetStat = fs.lstatSync(targetPath);
    if (!targetStat.isFile() || targetStat.isSymbolicLink() || targetStat.nlink !== 1) reject("NON_UNIQUE_INPUT_LINK_COUNT");
    const before = fs.readFileSync(targetPath, "utf8");
    const childRequest = {
      expected_replacements: operation.expected_replacements,
      match: operation.match,
      relative_path: operation.relative_path,
      replacement: operation.replacement,
      source_root: options["source-root"]
    };
    const childArgv = [process.execPath, recorderPath];
    const child = spawnSync(process.execPath, [recorderPath], {
      cwd: options["source-root"],
      env: environment,
      input: Buffer.from(stableJson(childRequest), "utf8"),
      encoding: null,
      timeout: timeoutMs,
      maxBuffer: Math.max(taskInput.json.execution_policy.stdout_max_bytes, taskInput.json.execution_policy.stderr_max_bytes, 1024),
      shell: false
    });
    if (child.error?.code === "ETIMEDOUT") reject("TIMEOUT");
    if (child.error || child.status !== 0 || child.signal !== null) reject("RECORDER_NON_PASS");
    if (child.stdout.length > taskInput.json.execution_policy.stdout_max_bytes || child.stderr.length > taskInput.json.execution_policy.stderr_max_bytes) reject("RECORDER_OUTPUT_LIMIT_EXCEEDED");
    let childResult;
    try { childResult = JSON.parse(child.stdout.toString("utf8")); } catch { reject("RECORDER_RESULT_INVALID"); }
    const expectedChildKeys = ["after_byte_length", "after_sha256", "before_byte_length", "before_sha256", "relative_path", "replacements", "schema_version"].sort();
    const actualChildKeys = Object.keys(childResult ?? {}).sort();
    if (actualChildKeys.length !== expectedChildKeys.length || actualChildKeys.some((key, index) => key !== expectedChildKeys[index])) reject("RECORDER_RESULT_INVALID");

    const resultFiles = sourceInput.json.files.map((entry) => {
      const filePath = path.join(options["source-root"], ...entry.path.split("/"));
      const stat = fs.lstatSync(filePath);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) reject("RESULT_MANIFEST_DRIFT");
      const content = fs.readFileSync(filePath, "utf8");
      const bytes = Buffer.from(content, "utf8");
      return { path: entry.path, content, sha256: sha256(bytes), byte_length: bytes.length };
    }).sort((left, right) => left.path.localeCompare(right.path));
    const afterPaths = resultFiles.map((entry) => entry.path).sort();
    if (stableJson(afterPaths) !== stableJson(sourcePaths)) reject("RESULT_MANIFEST_DRIFT");
    const afterEntry = resultFiles.find((entry) => entry.path === operation.relative_path);
    if (childResult.schema_version !== "blind-admission-recorder-result/v1" || childResult.relative_path !== operation.relative_path || childResult.replacements !== replacementCount || childResult.before_sha256 !== sha256(Buffer.from(before, "utf8")) || childResult.before_byte_length !== Buffer.byteLength(before, "utf8") || childResult.after_sha256 !== afterEntry.sha256 || childResult.after_byte_length !== afterEntry.byte_length) reject("RECORDER_RESULT_INVALID");
    for (const entry of resultFiles) {
      if (entry.path !== operation.relative_path) {
        const original = sourceInput.json.files.find((sourceEntry) => sourceEntry.path === entry.path);
        if (entry.content !== original.content) reject("RESULT_MANIFEST_DRIFT");
      }
    }
    if (afterEntry.content === before) reject("NO_MATERIAL_CHANGE");
    const patchIdentity = {
      kind: operation.kind,
      relative_path: operation.relative_path,
      match_sha256: sha256(Buffer.from(operation.match, "utf8")),
      replacement_sha256: sha256(Buffer.from(operation.replacement, "utf8")),
      replacements: replacementCount,
      before_sha256: sha256(Buffer.from(before, "utf8")),
      before_byte_length: Buffer.byteLength(before, "utf8"),
      after_sha256: afterEntry.sha256,
      after_byte_length: afterEntry.byte_length
    };

    cleanupOwnedSource(options["source-root"], ownership);
    ownership = undefined;
    if (fs.existsSync(options["source-root"])) reject("ROLLBACK_NOT_EXACT");
    const evidencePath = path.join(options["evidence-root"], "evidence.json");
    const successBytes = Buffer.from(`${stableJson({ candidate_status: "COMPLETED", evidence_path: evidencePath })}\n`, "utf8");
    const orderedArgv = [...process.argv];
    const runtime = {
      actual_process_arch: process.arch,
      expected_process_arch: runtimeInput.json.actual_process.arch,
      platform: process.platform,
      executable_path: process.execPath,
      executable_realpath: executable.realpath,
      executable_sha256: executable.sha256,
      executable_byte_length: executable.byte_length,
      executable_mode: executable.mode,
      executable_version: executable.version,
      ordered_argv: orderedArgv,
      ordered_argv_sha256: sha256Json(orderedArgv),
      logical_cwd: process.cwd(),
      environment,
      environment_sha256: sha256Json(environment),
      timeout_ms: timeoutMs,
      exit_code: 0,
      stdout_sha256: sha256(successBytes),
      stdout_byte_length: successBytes.length,
      stderr_sha256: sha256(Buffer.alloc(0)),
      stderr_byte_length: 0,
      duration_ms: Number(process.hrtime.bigint() - started) / 1_000_000,
      child: {
        executable_path: process.execPath,
        module_path: recorderPath,
        ordered_argv_sha256: sha256Json(childArgv),
        logical_cwd: options["source-root"],
        environment_sha256: sha256Json(environment),
        stdout_sha256: sha256(child.stdout),
        stdout_byte_length: child.stdout.length,
        stderr_sha256: sha256(child.stderr),
        stderr_byte_length: child.stderr.length,
        exit_code: child.status,
        timed_out: false,
        shell: false
      }
    };
    const evidence = {
      schema_version: "blind-admission-evidence/v1",
      case_id: options["case-id"],
      task_id: taskInput.json.task_id,
      identities: {
        contract_sha256: options["contract-sha256"],
        contract_byte_length: Number(options["contract-byte-length"]),
        authority_sha256: options["authority-sha256"],
        authority_byte_length: Number(options["authority-byte-length"]),
        quality_freeze_sha256: options["quality-freeze-sha256"],
        quality_freeze_byte_length: Number(options["quality-freeze-byte-length"]),
        withheld_commitment_sha256: options["commitment-sha256"],
        withheld_commitment_byte_length: Number(options["commitment-byte-length"]),
        candidate_commit: options["candidate-commit"],
        candidate_tree: options["candidate-tree"],
        task_card_sha256: taskInput.sha256,
        task_card_byte_length: taskInput.byte_length,
        source_sha256: sourceInput.sha256,
        source_byte_length: sourceInput.byte_length,
        runtime_profile_sha256: runtimeInput.sha256,
        runtime_profile_byte_length: runtimeInput.byte_length,
        environment_snapshot_sha256: sha256Json(environment),
        system_configuration_sha256: runtimeInput.sha256,
        executing_module_sha256: moduleInput.sha256,
        executing_module_byte_length: moduleInput.byte_length,
        recorder_module_sha256: recorderInput.sha256,
        recorder_module_byte_length: recorderInput.byte_length,
        validator_module_sha256: validatorInput.sha256,
        validator_module_byte_length: validatorInput.byte_length
      },
      runtime,
      patch: { ...patchIdentity, patch_sha256: sha256Json(patchIdentity), material_change: true },
      result: { files: resultFiles, path_set: afterPaths, manifest_sha256: sha256Json(resultFiles.map(({ path: filePath, sha256: digest, byte_length: length }) => ({ path: filePath, sha256: digest, byte_length: length }))) },
      tests: { candidate_conformance: true, direct_spawn_without_shell: true, operation_count_exact: true, result_manifest_exact: true, source_manifest_clean: true },
      rollback: {
        source_root_initial_state: "ABSENT",
        source_root_final_state: "ABSENT",
        source_identity_before: sourceInput.sha256,
        source_identity_after: sourceInput.sha256,
        path_set_before: [],
        path_set_after: [],
        clean_state_before: true,
        clean_state_after: true,
        exact: true
      },
      external_effects: { ...FALSE_EXTERNAL_EFFECTS },
      candidate_status: "COMPLETED"
    };
    const receipt = writeEvidence(options["evidence-root"], evidence);
    evidenceRootOwned = true;
    if (receipt.path !== evidencePath) reject("EVIDENCE_IDENTITY_MISMATCH");
    return successBytes;
  } catch (error) {
    if (ownership) {
      try { cleanupOwnedSource(options["source-root"], ownership); } catch { reject("ROLLBACK_NOT_EXACT"); }
    }
    if (!evidenceRootOwned && fs.existsSync(options["evidence-root"])) {
      const entries = fs.readdirSync(options["evidence-root"]);
      if (entries.length === 0) fs.rmdirSync(options["evidence-root"]);
    }
    throw error;
  }
};

try {
  process.stdout.write(main());
} catch (error) {
  const reason = error instanceof AdmissionError ? error.reason : "INTERNAL_ERROR";
  process.stderr.write(`${stableJson({ reason, verdict: "REJECTED" })}\n`);
  process.exitCode = 1;
}

#!/usr/bin/env node
import fs from "node:fs";
import crypto from "node:crypto";

const fail = (reason) => {
  process.stderr.write(`${JSON.stringify({ verdict: "NON_PASS", reason })}\n`);
  process.exit(1);
};
const sha256 = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const read = (path, label, parseJson = true) => {
  const stat = fs.lstatSync(path);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) fail(`${label}_TYPE_INVALID`);
  const bytes = fs.readFileSync(path);
  return { bytes, sha256: sha256(bytes), byte_length: bytes.length, json: parseJson ? JSON.parse(bytes.toString("utf8")) : null };
};
const requireArgs = (argv) => {
  const expected = ["--evidence", "--expected", "--observation", "--task-card", "--source", "--runtime-profile", "--candidate-module"];
  if (argv.length !== expected.length * 2) fail("ORACLE_ARGUMENTS_INVALID");
  const values = {};
  for (let index = 0; index < expected.length; index += 1) {
    if (argv[index * 2] !== expected[index]) fail("ORACLE_ARGUMENTS_INVALID");
    values[expected[index].slice(2)] = argv[index * 2 + 1];
  }
  return values;
};
const exactFalseEffects = (value) => ["network", "provider", "secret", "remote", "production", "public"].every((key) => value?.[key] === false) && Object.keys(value ?? {}).length === 6;

try {
  const paths = requireArgs(process.argv.slice(2));
  const evidenceInput = read(paths.evidence, "EVIDENCE");
  const expectedInput = read(paths.expected, "EXPECTED");
  const observationInput = read(paths.observation, "OBSERVATION");
  const taskInput = read(paths["task-card"], "TASK_CARD");
  const sourceInput = read(paths.source, "SOURCE");
  const runtimeInput = read(paths["runtime-profile"], "RUNTIME_PROFILE");
  const candidateInput = read(paths["candidate-module"], "CANDIDATE_MODULE", false);
  const evidence = evidenceInput.json;
  const expected = expectedInput.json;
  const observation = observationInput.json;
  const task = taskInput.json;
  const runtimeProfile = runtimeInput.json;

  if (observation.schema_version !== "blind-admission-quality-observation/v1") fail("OBSERVATION_SCHEMA_INVALID");
  if (observation.candidate_evidence?.sha256 !== evidenceInput.sha256 || observation.candidate_evidence?.byte_length !== evidenceInput.byte_length) fail("OBSERVATION_EVIDENCE_BINDING_MISMATCH");
  const identityChecks = {
    task_card_sha256: taskInput.sha256,
    source_sha256: sourceInput.sha256,
    runtime_profile_sha256: runtimeInput.sha256,
    executing_module_sha256: candidateInput.sha256
  };
  for (const [key, value] of Object.entries(identityChecks)) {
    if (evidence.identities?.[key] !== value || observation.identities?.[key] !== value) fail(`IDENTITY_MISMATCH_${key.toUpperCase()}`);
  }
  if (evidence.task_id !== task.task_id || evidence.task_id !== expected.task_id || observation.task_id !== task.task_id) fail("TASK_ID_MISMATCH");
  if (observation.process?.actual_arch !== runtimeProfile.actual_process?.arch || observation.process?.platform !== runtimeProfile.actual_process?.platform) fail("ACTUAL_ARCHITECTURE_MISMATCH");
  if (observation.process?.executable_path !== runtimeProfile.executable?.path || observation.process?.executable_realpath !== runtimeProfile.executable?.realpath || observation.process?.executable_sha256 !== runtimeProfile.executable?.sha256 || observation.process?.executable_version !== runtimeProfile.executable?.version) fail("EXECUTABLE_IDENTITY_MISMATCH");
  if (evidence.runtime?.actual_process_arch !== observation.process.actual_arch || evidence.runtime?.expected_process_arch !== runtimeProfile.actual_process.arch) fail("EVIDENCE_ARCHITECTURE_MISMATCH");
  if (evidence.runtime?.ordered_argv_sha256 !== observation.command?.ordered_argv_sha256 || evidence.runtime?.logical_cwd !== observation.command?.logical_cwd || evidence.runtime?.environment_sha256 !== observation.command?.environment_sha256 || evidence.runtime?.timeout_ms !== observation.command?.timeout_ms || evidence.runtime?.exit_code !== observation.process?.exit_code || evidence.runtime?.stdout_sha256 !== observation.process?.stdout_sha256 || evidence.runtime?.stderr_sha256 !== observation.process?.stderr_sha256) fail("RAW_RUN_OBSERVATION_MISMATCH");
  if (observation.command?.timeout_ms !== task.execution_policy?.timeout_ms) fail("TIMEOUT_BINDING_MISMATCH");

  const expectedFile = expected.files?.[0];
  const actualFile = evidence.result?.files?.[0];
  if (!expectedFile || !actualFile || actualFile.path !== expectedFile.path) fail("RESULT_PATH_MISMATCH");
  const actualBytes = Buffer.from(actualFile.content ?? "", "utf8");
  const actualSha = sha256(actualBytes);
  if (actualSha !== expectedFile.sha256 || actualBytes.length !== expectedFile.byte_length) fail("RESULT_IDENTITY_MISMATCH");
  if (evidence.patch?.kind !== expected.patch.kind || evidence.patch?.replacements !== expected.patch.replacements || evidence.patch?.material_change !== true) fail("PATCH_MISMATCH");
  if (evidence.tests?.candidate_conformance !== true) fail("CANDIDATE_CONFORMANCE_NON_PASS");

  const rollback = observation.rollback ?? {};
  if (rollback.source_root_initial_state !== "ABSENT" || rollback.source_root_final_state !== "ABSENT" || rollback.path_set_before?.length !== 0 || rollback.path_set_after?.length !== 0 || rollback.clean_state_before !== true || rollback.clean_state_after !== true || rollback.exact !== true) fail("OBSERVED_ROLLBACK_NOT_EXACT");
  if (evidence.rollback?.exact !== true || evidence.rollback?.source_root_final_state !== "ABSENT" || evidence.rollback?.path_set_after?.length !== 0 || evidence.rollback?.clean_state_after !== true) fail("EVIDENCE_ROLLBACK_NOT_EXACT");
  if (!exactFalseEffects(observation.external_effects) || !exactFalseEffects(evidence.external_effects)) fail("EXTERNAL_EFFECT_FORBIDDEN");
  if (evidence.candidate_status !== "COMPLETED" || observation.process?.exit_code !== 0) fail("CANDIDATE_NOT_COMPLETED");
  process.stdout.write(`${JSON.stringify({ verdict: "PASS", task_id: evidence.task_id, result_sha256: actualSha, observation_sha256: observationInput.sha256 })}\n`);
} catch (error) {
  fail(error?.code ? `ORACLE_IO_${error.code}` : "ORACLE_INPUT_INVALID");
}

#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { validate } from "./schema-validator.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../..");
const FIXTURE_ROOT = join(REPOSITORY_ROOT, "evaluation-harness/fixtures");
const SCHEMA_ROOT = join(REPOSITORY_ROOT, "docs/aios/schemas");
const EVALUATOR = join(HERE, "evaluate.mjs");

const SCHEMA_FIXTURES = Object.freeze({
  "task-spec.schema.json": join(FIXTURE_ROOT, "visible/task-spec.json"),
  "environment-snapshot.schema.json": join(FIXTURE_ROOT, "visible/environment-snapshot.json"),
  "system-configuration.schema.json": join(FIXTURE_ROOT, "visible/system-configuration.json"),
  "run-record.schema.json": join(FIXTURE_ROOT, "visible/positive-run-record.json"),
});

let assertionCount = 0;
function assert(condition, message) {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
  assertionCount += 1;
}

function evaluatorArguments(runRecord, result) {
  return [
    EVALUATOR,
    "--task", join(FIXTURE_ROOT, "visible/task-spec.json"),
    "--environment", join(FIXTURE_ROOT, "visible/environment-snapshot.json"),
    "--configuration", join(FIXTURE_ROOT, "visible/system-configuration.json"),
    "--run-record", join(FIXTURE_ROOT, "visible", runRecord),
    "--result", join(FIXTURE_ROOT, result),
    "--oracle", join(FIXTURE_ROOT, "oracle/oracle.json"),
    "--schema-root", SCHEMA_ROOT,
    "--artifact-root", REPOSITORY_ROOT,
  ];
}

function invoke(runRecord, result) {
  const execution = spawnSync(process.execPath, evaluatorArguments(runRecord, result), {
    cwd: REPOSITORY_ROOT,
    encoding: "utf8",
    env: { PATH: process.env.PATH ?? "" },
  });
  assert(execution.signal === null, `${runRecord} evaluator must not terminate by signal`);
  assert(execution.stderr === "", `${runRecord} evaluator stderr must be empty`);
  return { object: JSON.parse(execution.stdout), bytes: execution.stdout, status: execution.status };
}

for (const [schemaName, fixturePath] of Object.entries(SCHEMA_FIXTURES)) {
  const schema = JSON.parse(readFileSync(join(SCHEMA_ROOT, schemaName), "utf8"));
  const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));
  assert(validate(fixture, schema).length === 0, `${schemaName} must accept its frozen fixture`);

  for (const requiredKey of schema.required) {
    const malformed = structuredClone(fixture);
    delete malformed[requiredKey];
    assert(validate(malformed, schema).length > 0, `${schemaName} must reject missing ${requiredKey}`);
  }

  const unexpected = structuredClone(fixture);
  unexpected.unexpected_property = true;
  assert(validate(unexpected, schema).length > 0, `${schemaName} must reject an unexpected top-level property`);
}

const positive = invoke("positive-run-record.json", "oracle/expected-result.json");
assert(positive.status === 0, "positive fixture must exit 0");
assert(positive.object.verdict === "PASS", "positive fixture must PASS");

const replay = invoke("positive-run-record.json", "oracle/expected-result.json");
assert(replay.status === 0, "positive replay must exit 0");
assert(JSON.stringify(replay.object) === JSON.stringify(positive.object), "positive replay object must match");
assert(replay.bytes === positive.bytes, "positive replay bytes must match");

const controlled = invoke("controlled-failure-run-record.json", "visible/controlled-failure-result.json");
assert(controlled.status === 1, "controlled failure must exit 1");
assert(controlled.object.verdict === "FAIL", "controlled failure must FAIL");
assert(controlled.object.reason_codes.includes("RESULT_SHA256_MISMATCH"), "controlled failure must report result mismatch");

const promoted = invoke("promoted-controlled-failure-run-record.json", "visible/controlled-failure-result.json");
assert(promoted.status === 1, "promoted controlled failure must exit 1");
assert(promoted.object.verdict === "FAIL", "promoted controlled failure must remain FAIL");
assert(promoted.object.reason_codes.includes("RESULT_SHA256_MISMATCH"), "promotion probe must report result mismatch");

process.stdout.write(`${JSON.stringify({
  schema_version: "1.0",
  self_test: "PASS",
  assertions: assertionCount,
  positive_verdict: positive.object.verdict,
  controlled_failure_verdict: controlled.object.verdict,
  promotion_probe_verdict: promoted.object.verdict,
  replay_byte_equal: replay.bytes === positive.bytes,
})}\n`);

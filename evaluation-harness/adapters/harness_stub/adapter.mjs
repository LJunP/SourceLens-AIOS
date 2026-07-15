#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalJson } from "../../evaluator/schema-validator.mjs";

export const ADAPTER_ID = "HARNESS_STUB";
export const ADAPTER_VERSION = "HARNESS_STUB-1.0";

function loadJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function assertExactContext(context) {
  if (context === null || typeof context !== "object" || Array.isArray(context)) {
    throw new Error("context must be an object");
  }
  const keys = Object.keys(context).sort();
  const expected = ["schema_version", "task_id", "values"].sort();
  if (JSON.stringify(keys) !== JSON.stringify(expected)) {
    throw new Error("context keys do not match the HARNESS_STUB contract");
  }
  if (context.schema_version !== "1.0" || typeof context.task_id !== "string") {
    throw new Error("context identity is invalid");
  }
  if (!Array.isArray(context.values) || context.values.length === 0
      || !context.values.every(Number.isSafeInteger)) {
    throw new Error("context values must be a non-empty safe-integer array");
  }
}

function buildResult(context) {
  const sortedValues = [...context.values].sort((left, right) => left - right);
  return {
    schema_version: "1.0",
    task_id: context.task_id,
    sorted_values: sortedValues,
    sum: sortedValues.reduce((total, value) => total + value, 0),
    count: sortedValues.length,
  };
}

function applyControlledFailure(result, fixture) {
  if (fixture === null || typeof fixture !== "object" || Array.isArray(fixture)) {
    throw new Error("controlled failure fixture must be an object");
  }
  const mutation = fixture.mutation;
  if (fixture.schema_version !== "1.0"
      || mutation?.operation !== "replace"
      || mutation?.json_pointer !== "/sum"
      || !Number.isSafeInteger(mutation.original_value)
      || !Number.isSafeInteger(mutation.replacement_value)) {
    throw new Error("controlled failure fixture is outside the bounded mutation contract");
  }
  if (result.sum !== mutation.original_value) {
    throw new Error("controlled failure original value does not match computed result");
  }
  return { ...result, sum: mutation.replacement_value };
}

export function execute(contextPath, controlledFailurePath = null) {
  const context = loadJson(contextPath);
  assertExactContext(context);
  const result = buildResult(context);
  return controlledFailurePath === null
    ? result
    : applyControlledFailure(result, loadJson(controlledFailurePath));
}

function usage() {
  return "Usage: adapter.mjs --context FILE [--controlled-failure FILE]";
}

function parseArguments(argv) {
  if (argv.includes("--help")) return { help: true };
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (value === undefined) throw new Error(`missing value for ${key ?? "<end>"}`);
    if (key === "--context") options.context = value;
    else if (key === "--controlled-failure") options.controlledFailure = value;
    else throw new Error(`unsupported option ${key}`);
  }
  if (!options.context) throw new Error("--context is required");
  return options;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) {
      process.stdout.write(`${usage()}\n`);
      process.exit(0);
    }
    process.stdout.write(`${canonicalJson(execute(options.context, options.controlledFailure ?? null))}\n`);
  } catch (error) {
    process.stderr.write(`HARNESS_STUB_ERROR: ${error.message}\n`);
    process.exit(2);
  }
}

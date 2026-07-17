import assert from "node:assert/strict";
import test from "node:test";
import { classifyCommandResult } from "../src/result.mjs";

test("REP004_PRESERVE_NONZERO_EXIT", () => {
  assert.deepEqual(classifyCommandResult({ exitCode: 7, signal: null }), { status: "failure", exitCode: 7 });
});

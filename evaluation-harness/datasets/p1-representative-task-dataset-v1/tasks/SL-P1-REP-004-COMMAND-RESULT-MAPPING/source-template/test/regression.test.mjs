import assert from "node:assert/strict";
import test from "node:test";
import { classifyCommandResult } from "../src/result.mjs";

test("zero exit remains success", () => {
  assert.deepEqual(classifyCommandResult({ exitCode: 0, signal: null }), { status: "success", exitCode: 0 });
});

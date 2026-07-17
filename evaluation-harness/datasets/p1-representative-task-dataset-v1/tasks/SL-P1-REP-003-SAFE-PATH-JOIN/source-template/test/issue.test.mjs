import assert from "node:assert/strict";
import test from "node:test";
import { resolveUnder } from "../src/path.mjs";

test("REP003_REJECT_PARENT_ESCAPE", () => {
  assert.throws(() => resolveUnder("/workspace/root", "../escape.txt"), /path escape/);
});

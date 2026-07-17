import assert from "node:assert/strict";
import test from "node:test";
import { resolveUnder } from "../src/path.mjs";

test("in-root paths still resolve", () => {
  assert.equal(resolveUnder("/workspace/root", "src/app.mjs"), "/workspace/root/src/app.mjs");
});

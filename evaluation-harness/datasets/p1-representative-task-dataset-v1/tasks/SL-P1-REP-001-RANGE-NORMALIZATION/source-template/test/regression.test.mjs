import assert from "node:assert/strict";
import test from "node:test";
import { normalizeRange } from "../src/range.mjs";

test("ordered ranges remain unchanged", () => {
  assert.deepEqual(normalizeRange(-2, 7), { start: -2, end: 7 });
});

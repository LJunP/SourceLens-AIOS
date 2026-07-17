import assert from "node:assert/strict";
import test from "node:test";
import { normalizeRange } from "../src/range.mjs";

test("REP001_NEGATIVE_RANGE_ORDER", () => {
  assert.deepEqual(normalizeRange(7, -2), { start: -2, end: 7 });
});

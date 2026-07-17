import assert from "node:assert/strict";
import test from "node:test";
import { validateConfig } from "../src/config.mjs";

test("REP002_REJECT_UNKNOWN_KEYS", () => {
  assert.throws(() => validateConfig({ mode: "safe", extra: true }), /unknown key: extra/);
});

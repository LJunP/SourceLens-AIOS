import assert from "node:assert/strict";
import test from "node:test";
import { validateConfig } from "../src/config.mjs";

test("valid configuration remains accepted", () => {
  assert.deepEqual(validateConfig({ mode: "safe" }), { ok: true, mode: "safe" });
});

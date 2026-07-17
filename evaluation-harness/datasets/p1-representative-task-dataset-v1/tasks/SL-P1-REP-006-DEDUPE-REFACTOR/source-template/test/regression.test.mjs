import assert from "node:assert/strict";
import test from "node:test";
import { uniqueUserNames } from "../src/users.mjs";
import { uniqueProjectNames } from "../src/projects.mjs";

test("deduplication preserves first-seen order", () => {
  const values = ["beta", "alpha", "beta", "gamma", "alpha"];
  assert.deepEqual(uniqueUserNames(values), ["beta", "alpha", "gamma"]);
  assert.deepEqual(uniqueProjectNames(values), ["beta", "alpha", "gamma"]);
});

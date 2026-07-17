import assert from "node:assert/strict";
import test from "node:test";
import { greeting } from "../src/greeting.mjs";

test("already-trimmed names remain stable", () => {
  assert.equal(greeting({ first: "Grace", last: "Hopper" }), "Hello, Grace Hopper!");
});

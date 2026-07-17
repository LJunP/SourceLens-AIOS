import assert from "node:assert/strict";
import test from "node:test";
import { greeting } from "../src/greeting.mjs";

test("REP005_FORMAT_NAME_ACROSS_MODULES", () => {
  assert.equal(greeting({ first: " Ada ", last: " Lovelace " }), "Hello, Ada Lovelace!");
});

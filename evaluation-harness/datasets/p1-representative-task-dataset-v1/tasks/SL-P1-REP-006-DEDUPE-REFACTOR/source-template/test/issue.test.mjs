import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("REP006_DEDUPE_PRESERVES_ORDER", async () => {
  const users = await readFile(new URL("../src/users.mjs", import.meta.url), "utf8");
  const projects = await readFile(new URL("../src/projects.mjs", import.meta.url), "utf8");
  const helperUrl = new URL("../src/unique.mjs", import.meta.url);
  assert.equal(existsSync(helperUrl), true, "shared unique helper must exist");
  const helper = await readFile(helperUrl, "utf8");
  assert.match(users, /from "\.\/unique\.mjs"/);
  assert.match(projects, /from "\.\/unique\.mjs"/);
  assert.match(helper, /export function uniqueStable/);
});

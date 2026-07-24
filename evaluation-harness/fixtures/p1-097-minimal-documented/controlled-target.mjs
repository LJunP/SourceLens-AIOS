#!/usr/bin/env node

import { lstatSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(64);
}

if (
  process.argv.length !== 4 ||
  process.argv[2] !== "--sentinel" ||
  !isAbsolute(process.argv[3]) ||
  resolve(process.argv[3]) !== process.argv[3]
) {
  fail("Usage: controlled-target.mjs --sentinel ABSOLUTE_PATH");
}

const sentinel = process.argv[3];
mkdirSync(dirname(sentinel), { recursive: true, mode: 0o700 });
try {
  const parent = lstatSync(dirname(sentinel));
  if (!parent.isDirectory() || parent.isSymbolicLink()) fail("sentinel parent invalid");
} catch (error) {
  fail(`sentinel parent unavailable: ${error.message}`);
}
writeFileSync(sentinel, "TARGET_EXECUTED\n", {
  encoding: "utf8",
  flag: "wx",
  mode: 0o600,
});
process.stdout.write('{"schema_version":"p1-097-controlled-target/v1","status":"EXECUTED"}\n');


#!/usr/bin/env node
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { sha256, stableJson } from "../../harness/p2-clean-room-benchmark-foundation-v1/core.mjs";

async function inventory(root) {
  const names = (await readdir(root)).sort();
  const result = [];
  for (const name of names) {
    const absolute = path.join(root, name);
    const stat = await lstat(absolute);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`invalid replay candidate leaf ${name}`);
    const bytes = await readFile(absolute);
    result.push({ relative_path: name, byte_length: bytes.length, sha256: sha256(bytes) });
  }
  return result;
}

const [left, right] = process.argv.slice(2);
if (!left || !right) throw new Error("usage: verify-replays.mjs REPLAY_1_CANDIDATE REPLAY_2_CANDIDATE");
const leftInventory = await inventory(path.resolve(left));
const rightInventory = await inventory(path.resolve(right));
if (stableJson(leftInventory) !== stableJson(rightInventory)) throw new Error("REPLAY_BYTES_DIFFER");
process.stdout.write(stableJson({
  schema_version: "p2-clean-room-byte-exact-replay-comparison/v1",
  status: "PASS_BYTE_EXACT",
  file_count: leftInventory.length,
  files: leftInventory,
}));

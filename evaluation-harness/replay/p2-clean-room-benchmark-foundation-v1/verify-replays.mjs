#!/usr/bin/env node
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import {
  assertAncestorChain,
  assertCanonicalDirectory,
  sha256,
  stableJson,
} from "../../harness/p2-clean-room-benchmark-foundation-v1/core.mjs";

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

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
  if (index % 2 === 0) pairs.push([value.replace(/^--/, ""), all[index + 1]]);
  return pairs;
}, []));
for (const required of ["evidence-root", "left-run", "right-run"]) {
  if (!args[required]) throw new Error(`missing --${required}`);
}
const evidenceRoot = await assertCanonicalDirectory(args["evidence-root"], "Task Evidence root");
const leftRoot = await assertAncestorChain(evidenceRoot, `runs/${args["left-run"]}`);
const rightRoot = await assertAncestorChain(evidenceRoot, `runs/${args["right-run"]}`);
for (const [label, root] of [["left", leftRoot], ["right", rightRoot]]) {
  const stat = await lstat(root);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`${label} run root is invalid`);
}
const leftTransactionBytes = await readFile(path.join(leftRoot, "TRANSACTION.json"));
const rightTransactionBytes = await readFile(path.join(rightRoot, "TRANSACTION.json"));
const leftTransaction = JSON.parse(leftTransactionBytes);
const rightTransaction = JSON.parse(rightTransactionBytes);
if (leftTransaction.run_id !== args["left-run"] || rightTransaction.run_id !== args["right-run"] ||
    stableJson(leftTransaction.candidate) !== stableJson(rightTransaction.candidate) ||
    leftTransaction.execution_context.sha256 !== rightTransaction.execution_context.sha256 ||
    leftTransaction.held_open_count !== 0 || rightTransaction.held_open_count !== 0) {
  throw new Error("REPLAY_TRANSACTION_BINDING_DRIFT");
}
const leftCandidate = await assertAncestorChain(leftRoot, "candidate");
const rightCandidate = await assertAncestorChain(rightRoot, "candidate");
const leftInventory = await inventory(leftCandidate);
const rightInventory = await inventory(rightCandidate);
if (stableJson(leftInventory) !== stableJson(rightInventory)) throw new Error("REPLAY_BYTES_DIFFER");
process.stdout.write(stableJson({
  schema_version: "p2-clean-room-byte-exact-replay-comparison/v1",
  status: "PASS_BYTE_EXACT",
  candidate: leftTransaction.candidate,
  execution_context_sha256: leftTransaction.execution_context.sha256,
  left: { run_id: args["left-run"], transaction_sha256: sha256(leftTransactionBytes) },
  right: { run_id: args["right-run"], transaction_sha256: sha256(rightTransactionBytes) },
  file_count: leftInventory.length,
  files: leftInventory,
}));

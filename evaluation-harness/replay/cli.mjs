#!/usr/bin/env node

import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalJson } from "../evaluator/schema-validator.mjs";
import { replayEvidence } from "./replay.mjs";

function parse(argv) {
  if (argv.includes("--help")) return { help: true };
  if (argv.length !== 2 || argv[0] !== "--evidence") {
    throw new Error("Usage: cli.mjs --evidence evaluation-harness/recording/EVIDENCE_DIRECTORY");
  }
  return { evidence: argv[1] };
}

if (resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parse(process.argv.slice(2));
    if (options.help) {
      process.stdout.write("Usage: cli.mjs --evidence evaluation-harness/recording/EVIDENCE_DIRECTORY\n");
    } else {
      process.stdout.write(`${canonicalJson(await replayEvidence(resolve(options.evidence)))}\n`);
    }
  } catch (error) {
    process.stderr.write(`AIOS_P1_001_REPLAY_ERROR: ${error.message}\n`);
    process.exit(1);
  }
}

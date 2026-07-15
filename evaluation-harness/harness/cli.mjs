#!/usr/bin/env node

import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalJson } from "../evaluator/schema-validator.mjs";
import { runHarness } from "./run.mjs";

function parse(argv) {
  if (argv.includes("--help")) return { help: true };
  if (argv.length !== 3 || argv[0] !== "run" || argv[1] !== "--output") {
    throw new Error("Usage: cli.mjs run --output evaluation-harness/recording/NEW_DIRECTORY");
  }
  return { output: argv[2] };
}

if (resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parse(process.argv.slice(2));
    if (options.help) {
      process.stdout.write("Usage: cli.mjs run --output evaluation-harness/recording/NEW_DIRECTORY\n");
    } else {
      process.stdout.write(`${canonicalJson(await runHarness(options.output))}\n`);
    }
  } catch (error) {
    process.stderr.write(`AIOS_P1_001_HARNESS_ERROR: ${error.message}\n`);
    process.exit(1);
  }
}

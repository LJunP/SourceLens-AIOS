#!/usr/bin/env node
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { buildExpectedArtifact, TASK_ID } from "./lib.mjs";

const outputPath = process.argv[2];
if (!outputPath) {
  console.error("usage: generate.mjs <output-path>");
  process.exit(64);
}

try {
  const artifact = buildExpectedArtifact();
  const bytes = Buffer.from(`${JSON.stringify(artifact, null, 2)}\n`, "utf8");
  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, bytes, { flag: "wx", mode: 0o600 });
  process.stdout.write(`${JSON.stringify({
    schema_version: "p1-219-generation-receipt/v1",
    task_id: TASK_ID,
    status: "PASS",
    output_path: outputPath,
    byte_length: bytes.length,
    sample_members: artifact.sample.length,
    provider_requests: 0,
    secret_reads: 0,
  })}\n`);
} catch (error) {
  console.error(`P1-219 GENERATION NON_PASS: ${error.message}`);
  process.exit(1);
}

#!/usr/bin/env node
import { verifyArtifactFile } from "./lib.mjs";

const artifactPath = process.argv[2];
if (!artifactPath) {
  console.error("usage: verify.mjs <artifact-path>");
  process.exit(64);
}

try {
  const result = verifyArtifactFile(artifactPath);
  process.stdout.write(`${JSON.stringify({ ...result.receipt, artifact: result.artifact_identity })}\n`);
} catch (error) {
  console.error(`P1-219 VERIFICATION NON_PASS: ${error.message}`);
  process.exit(1);
}

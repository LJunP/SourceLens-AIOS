import { readFileSync, rmSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { canonicalJson } from "../evaluator/schema-validator.mjs";
import { MANIFEST_NAME, verifyManifest } from "../recording/manifest.mjs";
import { sha256 } from "../recording/recorder.mjs";
import { loadAndPreflight, prepareEvidenceRoot, readJson } from "../harness/contracts.mjs";
import { executeScenario } from "../harness/run.mjs";

export function compareReplayArtifacts(originalProjection, replayProjection, originalVerdict, replayVerdict) {
  const comparable = { ...replayProjection, scenario: "positive" };
  const originalBytes = Buffer.from(`${canonicalJson(originalProjection)}\n`, "utf8");
  const replayBytes = Buffer.from(`${canonicalJson(comparable)}\n`, "utf8");
  return {
    status: originalBytes.equals(replayBytes) && originalVerdict.equals(replayVerdict) ? "PASS" : "FAIL",
    original_projection_sha256: sha256(originalBytes),
    replay_projection_sha256: sha256(replayBytes),
    projection_byte_equal: originalBytes.equals(replayBytes),
    evaluator_output_byte_equal: originalVerdict.equals(replayVerdict),
  };
}

export async function replayEvidence(evidenceRoot) {
  const manifest = readJson(join(evidenceRoot, MANIFEST_NAME));
  verifyManifest(evidenceRoot, manifest);
  const originalProjection = readJson(join(evidenceRoot, "positive/deterministic-projection.json"));
  const originalVerdict = readFileSync(join(evidenceRoot, "positive/evaluator-verdict.json"));
  const scratchPath = join(dirname(evidenceRoot), `.fresh-replay-${basename(evidenceRoot)}-${process.pid}`);
  const scratchRoot = prepareEvidenceRoot(scratchPath);
  try {
    const contracts = loadAndPreflight();
    const replay = await executeScenario({ contracts, outputRoot: scratchRoot, name: "replay" });
    const replayVerdict = replay.evaluated.execution.stdout;
    const comparison = compareReplayArtifacts(originalProjection, replay.projection, originalVerdict, replayVerdict);
    const result = {
      schema_version: "1.0",
      status: comparison.status,
      evidence_manifest_sha256: sha256(readFileSync(join(evidenceRoot, MANIFEST_NAME))),
      original_projection_sha256: comparison.original_projection_sha256,
      replay_projection_sha256: comparison.replay_projection_sha256,
      projection_byte_equal: comparison.projection_byte_equal,
      evaluator_output_byte_equal: comparison.evaluator_output_byte_equal,
      evidence_mutated: false,
      claim_boundary: "Fresh replay of HARNESS_STUB conformance only; no benchmark or Agent capability claim.",
    };
    if (result.status !== "PASS") throw new Error(`fresh replay mismatch: ${canonicalJson(result)}`);
    return result;
  } finally {
    rmSync(scratchRoot, { recursive: true, force: true });
  }
}

import {
  assert,
} from "../../p1-097-minimal-documented/core.mjs";
import {
  buildExactRequest,
} from "./common.mjs";

export const SYSTEM_ID = "B2";

export function buildProviderRequest({
  entry,
  configuration,
  disclosure,
  responseSchemaIdentity,
  scannerObservation,
}) {
  assert(
    scannerObservation?.operation_id === "repository_analysis.scan"
      && scannerObservation.real_invocation === true
      && scannerObservation.exit_code === 0
      && typeof scannerObservation.accepted_binding_sha256 === "string"
      && /^[0-9a-f]{64}$/.test(scannerObservation.accepted_binding_sha256)
      && typeof scannerObservation.scanner_artifact_sha256 === "string"
      && /^[0-9a-f]{64}$/.test(scannerObservation.scanner_artifact_sha256)
      && Number.isInteger(scannerObservation.file_count)
      && scannerObservation.file_count >= 0
      && scannerObservation.language_counts !== null
      && typeof scannerObservation.language_counts === "object"
      && !Array.isArray(scannerObservation.language_counts)
      && Object.values(scannerObservation.language_counts).every((count) => Number.isInteger(count) && count >= 0)
      && scannerObservation.source_bytes_disclosed_to_provider === false,
    "B2_SCANNER_OBSERVATION_INVALID",
    "B2 requires one exact accepted scanner invocation before its Provider request",
  );
  return buildExactRequest({
    entry,
    configuration,
    disclosure,
    responseSchemaIdentity,
    scannerObservation: {
      operation_id: "repository_analysis.scan",
      accepted_binding_sha256: scannerObservation.accepted_binding_sha256,
      scanner_artifact_sha256: scannerObservation.scanner_artifact_sha256,
      file_count: scannerObservation.file_count,
      language_counts: scannerObservation.language_counts,
      source_content_included: false,
    },
  });
}

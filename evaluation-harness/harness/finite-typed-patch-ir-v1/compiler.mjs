import { createHash } from "node:crypto";

export const COMPILER_VERSION = "SL-PATCH-IR-TRUSTED-COMPILER/1";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

const programBytes = (left, right) => Buffer.from(
  `{"schema":"SL-PATCH-IR/1","task":"SL-P1-REP-001-RANGE-NORMALIZATION@1.0.0",` +
    `"base_commit":"68ce8226eff4c5c7230b55b18a4cbea2f8e4a20f",` +
    `"base_tree":"900814727113d65f5dad8b63222e14f39b2cf38b",` +
    `"target":"T0","op":"REBIND_OBJECT_FIELDS","values":["${left}","${right}"]}\n`,
  "utf8",
);

const postimageBytes = (base64) => Buffer.from(base64, "base64");

const ENTRIES = [
  {
    program_id: "IR00",
    program_sha256: "e21da56b4132c121419863bad9e682532963f8b5bc9951af31b23234d9c46736",
    program: programBytes("ARG0", "ARG0"),
    status: "COMPILED",
    outcome_id: "SAFE_WRONG_START_START",
    kind: "COMPLETE_POSTIMAGE",
    postimage: postimageBytes(
      "ZXhwb3J0IGZ1bmN0aW9uIG5vcm1hbGl6ZVJhbmdlKHN0YXJ0LCBlbmQpIHsKICBpZiAoc3RhcnQgPD0gZW5kKSByZXR1cm4geyBzdGFydCwgZW5kIH07CiAgcmV0dXJuIHsgc3RhcnQ6IHN0YXJ0LCBlbmQ6IHN0YXJ0IH07Cn0K",
    ),
  },
  {
    program_id: "IR01",
    program_sha256: "db33a4d4f2a5b21f211344d785785c2b4c246677bbcf68ef0d5e1831cdf3d0c1",
    program: programBytes("ARG0", "ARG1"),
    status: "IDENTITY_NO_EFFECT_REJECTION",
    outcome_id: "IDENTITY_NO_EFFECT_REJECTION",
    kind: "IDENTITY_NO_EFFECT_REJECTION",
    postimage: null,
  },
  {
    program_id: "IR10",
    program_sha256: "ac80def7bc984820b63243b020754715c1a7ad34e18e3ded2a4ee5c1961defcc",
    program: programBytes("ARG1", "ARG0"),
    status: "COMPILED",
    outcome_id: "CORRECT_END_START",
    kind: "COMPLETE_POSTIMAGE",
    postimage: postimageBytes(
      "ZXhwb3J0IGZ1bmN0aW9uIG5vcm1hbGl6ZVJhbmdlKHN0YXJ0LCBlbmQpIHsKICBpZiAoc3RhcnQgPD0gZW5kKSByZXR1cm4geyBzdGFydCwgZW5kIH07CiAgcmV0dXJuIHsgc3RhcnQ6IGVuZCwgZW5kOiBzdGFydCB9Owp9Cg==",
    ),
  },
  {
    program_id: "IR11",
    program_sha256: "0eeca741f57b218ee175308080de3ada3db1b4eb93222bd252cac9ed6e2c66f7",
    program: programBytes("ARG1", "ARG1"),
    status: "COMPILED",
    outcome_id: "SAFE_WRONG_END_END",
    kind: "COMPLETE_POSTIMAGE",
    postimage: postimageBytes(
      "ZXhwb3J0IGZ1bmN0aW9uIG5vcm1hbGl6ZVJhbmdlKHN0YXJ0LCBlbmQpIHsKICBpZiAoc3RhcnQgPD0gZW5kKSByZXR1cm4geyBzdGFydCwgZW5kIH07CiAgcmV0dXJuIHsgc3RhcnQ6IGVuZCwgZW5kOiBlbmQgfTsKfQo=",
    ),
  },
];

const ENTRY_BY_SHA = new Map(ENTRIES.map((entry) => [entry.program_sha256, entry]));

for (const entry of ENTRIES) {
  if (entry.program.length !== 255 || sha256(entry.program) !== entry.program_sha256) {
    throw new Error(`trusted compiler constant drift: ${entry.program_id}`);
  }
}
const rejected = (proposalBytes) => ({
  status: "REJECTED",
  reason_code: "IR_NOT_EXACTLY_ADMITTED",
  program_id: null,
  outcome_id: null,
  kind: null,
  postimage: null,
  proposal_length: Buffer.isBuffer(proposalBytes) ? proposalBytes.length : null,
  proposal_sha256: Buffer.isBuffer(proposalBytes) ? sha256(proposalBytes) : null,
});

export function compileFiniteTypedPatchIr(proposalBytes) {
  if (!Buffer.isBuffer(proposalBytes)) return Object.freeze(rejected(proposalBytes));
  if (proposalBytes.length > 255) return Object.freeze(rejected(proposalBytes));

  const digest = sha256(proposalBytes);
  const entry = ENTRY_BY_SHA.get(digest);
  if (!entry || entry.program.length !== proposalBytes.length || !entry.program.equals(proposalBytes)) {
    return Object.freeze(rejected(proposalBytes));
  }

  return Object.freeze({
    status: entry.status,
    reason_code: null,
    program_id: entry.program_id,
    outcome_id: entry.outcome_id,
    kind: entry.kind,
    postimage: entry.postimage === null ? null : Buffer.from(entry.postimage),
    proposal_length: proposalBytes.length,
    proposal_sha256: digest,
  });
}

import {
  assertCritical,
  bytesIdentity,
  canonicalJson,
  exactKeys,
  parseJsonBytesNoDuplicate,
  validateIdentity,
  validateJoin,
  validatePolicy,
} from "./contract.mjs";

const LSOF = "/usr/sbin/lsof";
const NORMALIZED_LSOF_HEADER =
  "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME";
const OBSERVATION_KEYS = Object.freeze([
  "command",
  "exit_status",
  "fd",
  "join",
  "local",
  "observed_rows",
  "peer",
  "pid",
  "policy",
  "request_record_identity",
  "schema_version",
  "started_at",
  "status",
  "stderr_identity",
  "stderr_path",
  "stdout_identity",
  "stdout_path",
  "stopped_at",
]);
const ROW_KEYS = Object.freeze(["fd", "local", "peer", "pid", "state"]);

export function parseClosedObserverRecord(
  bytes,
  stdoutBytes,
  stderrBytes,
  { join, request_record_identity, policy },
) {
  const record = parseJsonBytesNoDuplicate(bytes, {
    label: "OS network observation",
    invalid_code: "OBSERVER_KEYSET_INVALID",
  });
  return validateRawObservation({
    record,
    stdout_bytes: stdoutBytes,
    stderr_bytes: stderrBytes,
    join,
    request_record_identity,
    policy,
  });
}

function parseEndpoint(value) {
  const match = /^(127\.0\.0\.1):([1-9][0-9]{0,4})$/.exec(value);
  assertCritical(
    match !== null && Number(match[2]) <= 65535,
    "NON_LOOPBACK_PEER_FORBIDDEN",
    "observed endpoint is not exact IPv4 loopback",
  );
  return { host: match[1], port: Number(match[2]) };
}

function parseLsof(stdoutBytes) {
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(stdoutBytes);
  } catch {
    assertCritical(
      false,
      "OBSERVER_EVIDENCE_FORGED",
      "lsof stdout is not valid UTF-8",
    );
  }
  const lines = text.split("\n");
  assertCritical(
    lines.at(-1) === "",
    "OBSERVER_EVIDENCE_FORGED",
    "lsof stdout is not exactly newline terminated",
  );
  lines.pop();
  assertCritical(
    lines.length === 2
      && lines.every((line) => line.trim().length > 0)
      && lines[0].trim().split(/\s+/).join(" ")
        === NORMALIZED_LSOF_HEADER,
    "OBSERVER_EVIDENCE_FORGED",
    "lsof stdout must contain the exact normalized header and one data row",
  );
  const parts = lines[1].trim().split(/\s+/);
  const name = parts.length >= 9 ? parts.slice(8).join(" ") : "";
  const match = /^([^ ]+)->([^ ]+) \(([^)]+)\)$/.exec(name);
  assertCritical(
    parts.length >= 9
      && Number.isSafeInteger(Number(parts[1]))
      && Number(parts[1]) > 0
      && /^[0-9]+[a-zA-Z]$/.test(parts[3])
      && match !== null,
    "OBSERVER_EVIDENCE_FORGED",
    "lsof data row is malformed or unrecognized",
  );
  return [{
    pid: Number(parts[1]),
    fd: parts[3],
    local: match[1],
    peer: match[2],
    state: match[3],
  }];
}

function validateRow(value, label) {
  try {
    exactKeys(value, ROW_KEYS, label);
  } catch {
    assertCritical(
      false,
      "OBSERVER_EVIDENCE_FORGED",
      `${label} key set is not closed`,
    );
  }
  assertCritical(
    Number.isSafeInteger(value.pid) && value.pid > 0,
    "OBSERVER_PID_MISMATCH",
    `${label}.pid is invalid`,
  );
  assertCritical(
    typeof value.fd === "string" && /^[0-9]+[a-zA-Z]$/.test(value.fd),
    "OBSERVER_FD_MISMATCH",
    `${label}.fd is invalid`,
  );
  parseEndpoint(value.local);
  parseEndpoint(value.peer);
  assertCritical(
    value.state === "ESTABLISHED",
    "OBSERVER_NON_PASS",
    `${label} is not an established connection`,
  );
  return value;
}

function exactObservationKeys(record) {
  try {
    exactKeys(record, OBSERVATION_KEYS, "OS network observation");
  } catch {
    assertCritical(
      false,
      "OBSERVER_KEYSET_INVALID",
      "OS network observation key set is not closed",
    );
  }
}

export function validateRawObservation({
  record,
  stdout_bytes,
  stderr_bytes,
  join,
  request_record_identity,
  policy,
}) {
  assertCritical(
    record !== null && typeof record === "object" && !Array.isArray(record),
    "OBSERVER_EVIDENCE_MISSING",
    "OS network observation is missing",
  );
  exactObservationKeys(record);
  assertCritical(
    record.schema_version
        === "p1-165-os-network-observation/v1",
    "OBSERVER_KEYSET_INVALID",
    "OS network observation schema is invalid",
  );
  const validatedJoin = validateJoin(join);
  const observedJoin = validateJoin(record.join);
  assertCritical(
    canonicalJson(validatedJoin) === canonicalJson(observedJoin),
    "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
    "OS network observation join drifted",
  );
  const requestIdentity = validateIdentity(request_record_identity);
  const observedRequestIdentity = validateIdentity(record.request_record_identity);
  assertCritical(
    canonicalJson(requestIdentity) === canonicalJson(observedRequestIdentity),
    "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
    "OS network observation request identity drifted",
  );
  const validatedPolicy = validatePolicy(policy);
  const observedPolicy = validatePolicy(record.policy);
  assertCritical(
    canonicalJson(validatedPolicy) === canonicalJson(observedPolicy),
    "OBSERVER_TRANSPORT_CROSS_BINDING_INVALID",
    "OS network observation policy drifted",
  );
  assertCritical(
    Buffer.isBuffer(stdout_bytes) && Buffer.isBuffer(stderr_bytes),
    "OBSERVER_EVIDENCE_MISSING",
    "OS network observation raw streams are missing",
  );
  assertCritical(
    canonicalJson(bytesIdentity(stdout_bytes))
      === canonicalJson(validateIdentity(record.stdout_identity)),
    "OBSERVER_STDOUT_IDENTITY_MISMATCH",
    "lsof stdout identity drifted",
  );
  assertCritical(
    canonicalJson(bytesIdentity(stderr_bytes))
      === canonicalJson(validateIdentity(record.stderr_identity)),
    "OBSERVER_STDERR_IDENTITY_MISMATCH",
    "lsof stderr identity drifted",
  );
  assertCritical(
    record.exit_status === 0 && record.status === "PASS",
    "OBSERVER_NON_PASS",
    "OS network observation did not pass",
  );
  assertCritical(
    typeof record.stdout_path === "string"
      && (
        record.stdout_path.endsWith("/stdout.log")
        || record.stdout_path.endsWith("/observer-stdout.log")
      )
      && typeof record.stderr_path === "string"
      && (
        record.stderr_path.endsWith("/stderr.log")
        || record.stderr_path.endsWith("/observer-stderr.log")
      ),
    "OBSERVER_KEYSET_INVALID",
    "OS network raw artifact paths are invalid",
  );
  assertCritical(
    Array.isArray(record.observed_rows),
    "OBSERVER_EVIDENCE_MISSING",
    "OS network observation rows are missing",
  );
  assertCritical(
    record.observed_rows.length > 0,
    "OBSERVER_EVIDENCE_FORGED",
    "OS network observation retained an empty row set for non-empty raw stdout",
  );
  const reparsed = parseLsof(stdout_bytes);
  assertCritical(
    reparsed.length === 1,
    "OBSERVER_EVIDENCE_FORGED",
    "lsof raw stdout must contain exactly one closed observation row",
  );
  const policyRows = reparsed.filter(
    (row) => row.peer === validatedPolicy.expected_peer
      && row.state === "ESTABLISHED",
  );
  assertCritical(
    policyRows.length === 1,
    "OBSERVER_EVIDENCE_FORGED",
    "lsof does not prove exactly one policy-bound loopback client connection",
  );
  const rawRow = validateRow(policyRows[0], "policy-bound lsof row");
  assertCritical(
    record.pid === rawRow.pid,
    "OBSERVER_PID_MISMATCH",
    "observation PID is not bound to raw lsof",
  );
  assertCritical(
    record.fd === rawRow.fd,
    "OBSERVER_FD_MISMATCH",
    "observation FD is not bound to raw lsof",
  );
  assertCritical(
    record.peer === rawRow.peer,
    "OBSERVER_PEER_MISMATCH",
    "observation peer is not bound to raw lsof",
  );
  assertCritical(
    record.local === rawRow.local,
    "OBSERVER_PORT_MISMATCH",
    "observation local port is not bound to raw lsof",
  );
  const expectedCommand = [
    LSOF,
    "-nP",
    "-a",
    "-p",
    String(record.pid),
    `-iTCP@${validatedPolicy.expected_peer}`,
  ];
  assertCritical(
    canonicalJson(record.command) === canonicalJson(expectedCommand),
    "OBSERVER_COMMAND_MISMATCH",
    "lsof command identity drifted",
  );
  assertCritical(
    canonicalJson(reparsed) === canonicalJson(record.observed_rows),
    "OBSERVER_EVIDENCE_FORGED",
    "lsof rows do not reconstruct from raw stdout",
  );
  const started = Date.parse(record.started_at);
  const stopped = Date.parse(record.stopped_at);
  assertCritical(
    Number.isFinite(started) && Number.isFinite(stopped) && started <= stopped,
    "OBSERVER_TIMESTAMP_INVALID",
    "observer timestamps are invalid or reversed",
  );
  return record;
}

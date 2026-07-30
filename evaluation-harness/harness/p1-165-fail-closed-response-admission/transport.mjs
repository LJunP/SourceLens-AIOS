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

const MAX_HEADER_BYTES = 64 * 1024;
const CHUNK_LINE_MAX = 1024;
const TRANSPORT_RECORD_KEYS = Object.freeze([
  "application_terminal",
  "body_identity",
  "chunks",
  "eof",
  "framing",
  "http",
  "join",
  "observed_peer",
  "policy",
  "protocol_terminal",
  "raw_response_identity",
  "request_record_identity",
  "schema_version",
]);

export function parseClosedTransportRecord(
  bytes,
  { join, request_record_identity, policy },
) {
  const value = parseJsonBytesNoDuplicate(bytes, {
    label: "transport record",
    invalid_code: "TRANSPORT_KEYSET_INVALID",
  });
  try {
    exactKeys(value, TRANSPORT_RECORD_KEYS, "transport record");
  } catch {
    assertCritical(
      false,
      "TRANSPORT_KEYSET_INVALID",
      "transport record key set is not closed",
    );
  }
  assertCritical(
    value.schema_version === "p1-165-transport-record/v1",
    "TRANSPORT_KEYSET_INVALID",
    "transport record schema is invalid",
  );
  const expectedJoin = validateJoin(join);
  const expectedRequest = validateIdentity(request_record_identity);
  const expectedPolicy = validatePolicy(policy);
  assertCritical(
    canonicalJson(validateJoin(value.join)) === canonicalJson(expectedJoin),
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    "transport record join drifted",
  );
  assertCritical(
    canonicalJson(validateIdentity(value.request_record_identity))
      === canonicalJson(expectedRequest),
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    "transport request identity drifted",
  );
  assertCritical(
    canonicalJson(validatePolicy(value.policy)) === canonicalJson(expectedPolicy)
      && value.observed_peer === expectedPolicy.expected_peer,
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    "transport policy or observed peer drifted",
  );
  validateIdentity(value.raw_response_identity);
  validateIdentity(value.body_identity);
  return value;
}

function bufferChunk(value, index) {
  assertCritical(
    Buffer.isBuffer(value),
    "TRANSPORT_KEYSET_INVALID",
    `transport chunk ${index} is not bytes`,
  );
  return value;
}

function findHeaderBoundary(bytes) {
  const crlf = bytes.indexOf("\r\n\r\n");
  const lf = bytes.indexOf("\n\n");
  if (crlf >= 0 && (lf < 0 || crlf <= lf)) {
    return { index: crlf, separator: Buffer.from("\r\n\r\n"), line: "\r\n" };
  }
  if (lf >= 0) {
    return { index: lf, separator: Buffer.from("\n\n"), line: "\n" };
  }
  assertCritical(
    false,
    "HTTP_FRAMING_INCOMPLETE",
    "HTTP response header delimiter is missing",
  );
}

function parseHeaders(headerBytes, lineSeparator) {
  assertCritical(
    headerBytes.length > 0 && headerBytes.length <= MAX_HEADER_BYTES,
    "HTTP_FRAMING_INCOMPLETE",
    "HTTP response header size is invalid",
  );
  const text = headerBytes.toString("latin1");
  const lines = text.split(lineSeparator);
  const statusMatch = /^HTTP\/(1\.[01]) ([1-5][0-9]{2})(?: .*)?$/.exec(lines.shift() ?? "");
  assertCritical(
    statusMatch !== null,
    "HTTP_FRAMING_INCOMPLETE",
    "HTTP status line is invalid",
  );
  const headers = [];
  for (const line of lines) {
    assertCritical(
      line.length > 0 && !/^[ \t]/.test(line),
      "HTTP_FRAMING_INCOMPLETE",
      "HTTP header folding or empty header is forbidden",
    );
    const colon = line.indexOf(":");
    assertCritical(
      colon > 0,
      "HTTP_FRAMING_INCOMPLETE",
      "HTTP header field is malformed",
    );
    const name = line.slice(0, colon).trim().toLowerCase();
    const value = line.slice(colon + 1).trim();
    assertCritical(
      /^[!#$%&'*+\-.^_`|~0-9a-z]+$/.test(name)
        && !/[\0\r\n]/.test(value),
      "HTTP_FRAMING_INCOMPLETE",
      "HTTP header field is invalid",
    );
    headers.push({ name, value });
  }
  return {
    version: statusMatch[1],
    status_code: Number(statusMatch[2]),
    headers,
  };
}

function valuesFor(headers, name) {
  return headers.filter((entry) => entry.name === name).map((entry) => entry.value);
}

function indexOfCrlf(bytes, start) {
  for (let index = start; index + 1 < bytes.length; index += 1) {
    if (bytes[index] === 13 && bytes[index + 1] === 10) return index;
  }
  return -1;
}

function decodeChunked(body) {
  let cursor = 0;
  const decoded = [];
  let terminalCount = 0;
  let terminalOffset = null;
  while (cursor < body.length) {
    const lineEnd = indexOfCrlf(body, cursor);
    assertCritical(
      lineEnd >= cursor && lineEnd - cursor <= CHUNK_LINE_MAX,
      "HTTP_CHUNK_FRAMING_INVALID",
      "chunk-size line is missing or too large",
    );
    const sizeLine = body.subarray(cursor, lineEnd).toString("ascii");
    assertCritical(
      /^[0-9A-Fa-f]+(?:;[!#$%&'*+\-.^_`|~0-9A-Za-z=]*)?$/.test(sizeLine),
      "HTTP_CHUNK_FRAMING_INVALID",
      "chunk-size line is invalid",
    );
    const size = Number.parseInt(sizeLine.split(";", 1)[0], 16);
    assertCritical(
      Number.isSafeInteger(size) && size >= 0,
      "HTTP_CHUNK_FRAMING_INVALID",
      "chunk size is invalid",
    );
    cursor = lineEnd + 2;
    if (size === 0) {
      terminalCount += 1;
      terminalOffset = cursor;
      const trailerEnd = body.indexOf("\r\n\r\n", cursor);
      if (trailerEnd >= 0) {
        const trailers = body.subarray(cursor, trailerEnd);
        assertCritical(
          trailers.length <= MAX_HEADER_BYTES,
          "HTTP_CHUNK_FRAMING_INVALID",
          "chunk trailers are too large",
        );
        cursor = trailerEnd + 4;
      } else {
        assertCritical(
          cursor + 2 <= body.length
            && body[cursor] === 13
            && body[cursor + 1] === 10,
          "TERMINAL_EVENT_MISSING",
          "zero chunk is not terminated",
        );
        cursor += 2;
      }
      break;
    }
    assertCritical(
      cursor + size + 2 <= body.length,
      "RESPONSE_TRUNCATED",
      "chunk body is incomplete",
    );
    decoded.push(body.subarray(cursor, cursor + size));
    cursor += size;
    assertCritical(
      body[cursor] === 13 && body[cursor + 1] === 10,
      "HTTP_CHUNK_FRAMING_INVALID",
      "chunk body is not CRLF terminated",
    );
    cursor += 2;
  }
  assertCritical(
    terminalCount === 1,
    "TERMINAL_EVENT_MISSING",
    "chunked response requires exactly one terminal zero chunk",
  );
  assertCritical(
    cursor === body.length,
    "POST_TERMINAL_BYTES",
    "bytes follow the terminal zero chunk",
  );
  return {
    bytes: Buffer.concat(decoded),
    terminal: {
      kind: "HTTP_ZERO_CHUNK",
      count: terminalCount,
      offset: terminalOffset,
    },
  };
}

function validateStreamTerminalEvents(events, rawLength) {
  assertCritical(
    Array.isArray(events),
    "TRANSPORT_KEYSET_INVALID",
    "stream_terminal_events must be an array",
  );
  assertCritical(
    events.length <= 1,
    "TERMINAL_EVENT_DUPLICATE",
    "at most one application terminal event is allowed",
  );
  if (events.length === 0) {
    return { kind: "NONE", count: 0, offset: null };
  }
  const event = events[0];
  const keys = Object.keys(event).sort();
  assertCritical(
    canonicalJson(keys) === canonicalJson(["kind", "offset"]),
    "TRANSPORT_KEYSET_INVALID",
    "stream terminal event key set is not closed",
  );
  assertCritical(
    event.kind === "APPLICATION_TERMINAL"
      && Number.isSafeInteger(event.offset)
      && event.offset >= 0
      && event.offset <= rawLength,
    "TERMINAL_EVENT_MISSING",
    "stream terminal event is invalid",
  );
  assertCritical(
    event.offset === rawLength,
    "POST_TERMINAL_BYTES",
    "application terminal event does not bind the final byte",
  );
  return { kind: event.kind, count: 1, offset: event.offset };
}

export function analyzeTransport({
  join,
  request_record_identity,
  chunks,
  eof,
  stream_terminal_events = [],
  policy,
  observed_peer,
}) {
  const validatedJoin = validateJoin(join);
  const requestIdentity = validateIdentity(
    request_record_identity,
    "request record identity",
  );
  const validatedPolicy = validatePolicy(policy);
  assertCritical(
    observed_peer === validatedPolicy.expected_peer,
    "REQUEST_RESPONSE_CROSS_BINDING_INVALID",
    "transport actual peer does not equal the frozen policy peer",
  );
  assertCritical(
    Array.isArray(chunks) && chunks.length > 0,
    "HTTP_FRAMING_INCOMPLETE",
    "transport produced no response chunks",
  );
  assertCritical(eof === true, "EARLY_CLOSE", "transport EOF was not observed");

  let total = 0;
  const chunkRecords = chunks.map((candidate, index) => {
    const chunk = bufferChunk(candidate, index);
    total += chunk.length;
    assertCritical(
      total <= validatedPolicy.response_bytes_max,
      "RESPONSE_TOO_LARGE",
      "response exceeded the streaming byte cap",
    );
    return { index, ...bytesIdentity(chunk) };
  });
  const responseBytes = Buffer.concat(chunks, total);
  const boundary = findHeaderBoundary(responseBytes);
  const headerBytes = responseBytes.subarray(0, boundary.index);
  const wireBody = responseBytes.subarray(
    boundary.index + boundary.separator.length,
  );
  const http = parseHeaders(headerBytes, boundary.line);
  const contentLengths = valuesFor(http.headers, "content-length");
  const transferEncodings = valuesFor(http.headers, "transfer-encoding");
  assertCritical(
    contentLengths.length <= 1 && transferEncodings.length <= 1,
    "HTTP_CONTENT_LENGTH_MISMATCH",
    "duplicate HTTP framing headers are forbidden",
  );
  assertCritical(
    !(contentLengths.length === 1 && transferEncodings.length === 1),
    "HTTP_CONTENT_LENGTH_MISMATCH",
    "Content-Length and Transfer-Encoding cannot coexist",
  );

  let bodyBytes;
  let framing;
  let protocolTerminal = { kind: "EOF", count: 1, offset: responseBytes.length };
  if (contentLengths.length === 1) {
    assertCritical(
      /^(0|[1-9][0-9]*)$/.test(contentLengths[0]),
      "HTTP_CONTENT_LENGTH_MISMATCH",
      "Content-Length is not a canonical decimal integer",
    );
    const declared = Number(contentLengths[0]);
    assertCritical(
      Number.isSafeInteger(declared),
      "HTTP_CONTENT_LENGTH_MISMATCH",
      "Content-Length is outside the safe integer range",
    );
    assertCritical(
      wireBody.length >= declared,
      "RESPONSE_TRUNCATED",
      "response body is shorter than Content-Length",
    );
    assertCritical(
      wireBody.length === declared,
      "POST_TERMINAL_BYTES",
      "bytes follow the Content-Length framed body",
    );
    bodyBytes = wireBody;
    framing = {
      kind: "CONTENT_LENGTH",
      declared_body_bytes: declared,
      decoded_body_bytes: bodyBytes.length,
    };
  } else if (transferEncodings.length === 1) {
    assertCritical(
      transferEncodings[0].toLowerCase() === "chunked",
      "HTTP_CHUNK_FRAMING_INVALID",
      "unsupported Transfer-Encoding",
    );
    const decoded = decodeChunked(wireBody);
    bodyBytes = decoded.bytes;
    protocolTerminal = decoded.terminal;
    framing = {
      kind: "CHUNKED",
      declared_body_bytes: null,
      decoded_body_bytes: bodyBytes.length,
    };
  } else {
    bodyBytes = wireBody;
    framing = {
      kind: "EOF",
      declared_body_bytes: null,
      decoded_body_bytes: bodyBytes.length,
    };
  }
  assertCritical(
    bodyBytes.length <= validatedPolicy.response_bytes_max,
    "RESPONSE_TOO_LARGE",
    "decoded response body exceeded the frozen cap",
  );

  const applicationTerminal = validateStreamTerminalEvents(
    stream_terminal_events,
    responseBytes.length,
  );
  const record = {
    schema_version: "p1-165-transport-record/v1",
    join: validatedJoin,
    request_record_identity: requestIdentity,
    policy: validatedPolicy,
    observed_peer,
    raw_response_identity: bytesIdentity(responseBytes),
    body_identity: bytesIdentity(bodyBytes),
    chunks: chunkRecords,
    eof: true,
    http,
    framing,
    protocol_terminal: protocolTerminal,
    application_terminal: applicationTerminal,
  };
  return { response_bytes: responseBytes, body_bytes: bodyBytes, record };
}

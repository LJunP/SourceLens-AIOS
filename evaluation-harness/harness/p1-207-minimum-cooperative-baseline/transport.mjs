import http from "node:http";

import {
  assert,
} from "./shared.mjs";
import {
  MAX_RESPONSE_BYTES,
  validateObservedPeer,
} from "./response.mjs";

export async function readSecretOnce(stream = process.stdin) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  let secret = Buffer.concat(chunks);
  if (secret.length >= 2 && secret.at(-2) === 0x0d && secret.at(-1) === 0x0a) {
    secret = secret.subarray(0, -2);
  } else if (secret.length >= 1 && secret.at(-1) === 0x0a) {
    secret = secret.subarray(0, -1);
  }
  secret = Buffer.from(secret);
  assert(secret.length >= 8 && secret.length <= 512, "SECRET_INPUT_INVALID", "Secret length is invalid");
  assert(
    !secret.includes(0x00) && !secret.includes(0x0a) && !secret.includes(0x0d),
    "SECRET_INPUT_INVALID",
    "Secret contains a forbidden control byte",
  );
  return secret;
}

export function requestLoopback({ requestBytes, secretBytes, timeoutMilliseconds = 600_000 }) {
  assert(Buffer.isBuffer(requestBytes) && requestBytes.length >= 1, "REQUEST_BYTES_INVALID", "request must be bytes");
  assert(Buffer.isBuffer(secretBytes) && secretBytes.length >= 8, "SECRET_INPUT_INVALID", "Secret must be in-memory bytes");
  assert(
    Number.isInteger(timeoutMilliseconds) && timeoutMilliseconds >= 1_000 && timeoutMilliseconds <= 600_000,
    "TRANSPORT_TIMEOUT_INVALID",
    "transport timeout is outside the closed bound",
  );

  return new Promise((resolve) => {
    const chunks = [];
    let observedBytes = 0;
    let peerAddress = null;
    let peerPort = null;
    let httpStatus = null;
    let completed = false;
    const finish = (value) => {
      if (completed) return;
      completed = true;
      resolve({
        ...value,
        http_status: httpStatus,
        peer_address: peerAddress,
        peer_port: peerPort,
        response_bytes: Buffer.concat(chunks),
      });
    };

    const request = http.request({
      protocol: "http:",
      host: "127.0.0.1",
      family: 4,
      port: 8787,
      method: "POST",
      path: "/v1/chat/completions",
      agent: false,
      setHost: true,
      headers: {
        "content-type": "application/json",
        "content-length": String(requestBytes.length),
        authorization: `Bearer ${secretBytes.toString("utf8")}`,
        connection: "close",
      },
    });

    request.once("socket", (socket) => {
      socket.once("connect", () => {
        try {
          const peer = validateObservedPeer(socket.remoteAddress, socket.remotePort);
          peerAddress = peer.peer_address;
          peerPort = peer.peer_port;
        } catch (error) {
          request.destroy(error);
        }
      });
    });

    request.once("response", (response) => {
      httpStatus = response.statusCode ?? null;
      if (peerAddress === null && response.socket !== null) {
        try {
          const peer = validateObservedPeer(response.socket.remoteAddress, response.socket.remotePort);
          peerAddress = peer.peer_address;
          peerPort = peer.peer_port;
        } catch (error) {
          response.destroy(error);
          return;
        }
      }
      response.on("data", (chunk) => {
        const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        observedBytes += bytes.length;
        if (observedBytes > MAX_RESPONSE_BYTES) {
          response.destroy(Object.assign(new Error("response exceeded the raw byte cap"), { reasonCode: "RESPONSE_TOO_LARGE" }));
          return;
        }
        chunks.push(bytes);
      });
      response.once("end", () => finish({
        transport_status: "RECEIVED",
        reason_code: "NONE",
        message: null,
      }));
      response.once("error", (error) => finish({
        transport_status: "TRANSPORT_NON_PASS",
        reason_code: error.reasonCode ?? "RESPONSE_STREAM_FAILURE",
        message: error.message,
      }));
    });

    request.setTimeout(timeoutMilliseconds, () => {
      request.destroy(Object.assign(new Error("loopback request timed out"), { reasonCode: "TRANSPORT_TIMEOUT" }));
    });
    request.once("error", (error) => finish({
      transport_status: "TRANSPORT_NON_PASS",
      reason_code: error.reasonCode ?? "LOOPBACK_TRANSPORT_FAILURE",
      message: error.message,
    }));
    request.end(requestBytes);
  });
}

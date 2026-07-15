import { createHash } from "node:crypto";
import { spawn } from "node:child_process";

export const MAX_CAPTURE_BYTES = 1024 * 1024;

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function appendBounded(chunks, chunk, state, streamName) {
  state.bytes += chunk.length;
  if (state.bytes > MAX_CAPTURE_BYTES) {
    throw new Error(`${streamName} exceeded ${MAX_CAPTURE_BYTES} bytes`);
  }
  chunks.push(chunk);
}

export async function recordCommand({ argv, cwd, timeoutSeconds, environment }) {
  if (!Array.isArray(argv) || argv.length === 0 || !argv.every((item) => typeof item === "string")) {
    throw new Error("argv must be a non-empty string array");
  }
  if (!Number.isInteger(timeoutSeconds) || timeoutSeconds < 1) {
    throw new Error("timeoutSeconds must be a positive integer");
  }

  const frozenArgv = Object.freeze([...argv]);
  const startedAt = new Date().toISOString();
  const monotonicStart = process.hrtime.bigint();
  const stdoutChunks = [];
  const stderrChunks = [];
  const stdoutState = { bytes: 0 };
  const stderrState = { bytes: 0 };
  let timedOut = false;
  let captureError = null;

  const child = spawn(frozenArgv[0], frozenArgv.slice(1), {
    cwd,
    env: { ...environment },
    shell: false,
    stdio: ["ignore", "pipe", "pipe"],
  });

  child.stdout.on("data", (chunk) => {
    if (captureError) return;
    try { appendBounded(stdoutChunks, chunk, stdoutState, "stdout"); }
    catch (error) { captureError = error; child.kill("SIGKILL"); }
  });
  child.stderr.on("data", (chunk) => {
    if (captureError) return;
    try { appendBounded(stderrChunks, chunk, stderrState, "stderr"); }
    catch (error) { captureError = error; child.kill("SIGKILL"); }
  });

  const timeout = setTimeout(() => {
    timedOut = true;
    child.kill("SIGKILL");
  }, timeoutSeconds * 1000);

  const termination = await new Promise((resolvePromise, rejectPromise) => {
    child.once("error", rejectPromise);
    child.once("close", (exitStatus, signal) => resolvePromise({ exitStatus, signal }));
  }).finally(() => clearTimeout(timeout));

  if (captureError) throw captureError;
  const endedAt = new Date().toISOString();
  const latencyMs = Number((process.hrtime.bigint() - monotonicStart) / 1_000_000n);
  const stdout = Buffer.concat(stdoutChunks);
  const stderr = Buffer.concat(stderrChunks);

  return {
    stdout,
    stderr,
    ledger: {
      schema_version: "1.0",
      record_type: "aios_p1_001_command_execution",
      argv: frozenArgv,
      cwd,
      environment,
      started_at: startedAt,
      ended_at: endedAt,
      latency_ms: latencyMs,
      timeout_seconds: timeoutSeconds,
      timed_out: timedOut,
      exit_status: termination.exitStatus,
      signal: termination.signal,
      stdout_sha256: sha256(stdout),
      stdout_bytes: stdout.length,
      stderr_sha256: sha256(stderr),
      stderr_bytes: stderr.length,
    },
  };
}

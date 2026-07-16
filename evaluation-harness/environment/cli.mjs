#!/usr/bin/env node
import { captureSnapshot, projectionIdentity, REASONS, TypedFailure, verifySnapshot, writeCanonicalJson } from "./snapshot.mjs";

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!new Set(["capture", "verify"]).has(command) || rest.length % 2 !== 0) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "usage: capture|verify with key/value options");
  }
  const options = {};
  for (let index = 0; index < rest.length; index += 2) {
    const key = rest[index];
    const value = rest[index + 1];
    if (!key.startsWith("--") || !value || Object.hasOwn(options, key.slice(2))) {
      throw new TypedFailure(REASONS.MALFORMED_INPUT, "malformed or duplicate option");
    }
    options[key.slice(2)] = value;
  }
  const required = ["source-root", "declarations", "runtime-manifest", "schema"];
  if (command === "capture") required.push("output");
  else required.push("snapshot");
  if (Object.keys(options).sort().join("\0") !== required.sort().join("\0")) {
    throw new TypedFailure(REASONS.MALFORMED_INPUT, "exact required option set was not supplied");
  }
  return { command, options };
}

function result(command, verdict, reasonCode, identity = null) {
  return {
    schema_version: "1.0",
    command,
    verdict,
    reason_code: reasonCode,
    snapshot_id: identity?.snapshotId ?? null,
    projection_sha256: identity?.projectionSha256 ?? null,
  };
}

let command = process.argv[2] === "verify" ? "verify" : "capture";
try {
  const parsed = parseArgs(process.argv.slice(2));
  command = parsed.command;
  const common = {
    sourceRoot: parsed.options["source-root"],
    declarationsPath: parsed.options.declarations,
    runtimeManifestPath: parsed.options["runtime-manifest"],
    schemaPath: parsed.options.schema,
  };
  const observed = command === "capture"
    ? captureSnapshot(common)
    : verifySnapshot({ ...common, snapshotPath: parsed.options.snapshot });
  if (command === "capture") writeCanonicalJson(parsed.options.output, observed.snapshot);
  process.stdout.write(`${JSON.stringify(result(command, "PASS", "PASS", observed))}\n`);
  process.exitCode = 0;
} catch (error) {
  if (error instanceof TypedFailure) {
    let identity = null;
    if (command === "verify") {
      try {
        const raw = JSON.parse(await import("node:fs").then(({ readFileSync }) => readFileSync(process.argv[process.argv.indexOf("--snapshot") + 1], "utf8")));
        identity = projectionIdentity(raw);
      } catch {
        identity = null;
      }
    }
    process.stdout.write(`${JSON.stringify(result(command, "FAIL", error.reasonCode, identity))}\n`);
    process.exitCode = 2;
  } else {
    process.stderr.write("unexpected internal failure\n");
    process.exitCode = 1;
  }
}

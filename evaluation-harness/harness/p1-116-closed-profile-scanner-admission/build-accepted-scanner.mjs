#!/usr/bin/env node

import {
  chmodSync,
  mkdirSync,
  readFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  assert,
  canonicalBytes,
  fileIdentity,
  parseJsonFile,
  writeCreateOnce,
} from "./core.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");

function parseArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(key?.startsWith("--") && value, "CLI_INVALID", "expected --key value pairs");
    values[key.slice(2)] = resolve(value);
  }
  for (const key of ["binding", "output-root"]) {
    assert(values[key], "CLI_INVALID", `missing --${key}`);
  }
  return values;
}

function run(argv, options = {}) {
  const result = spawnSync(argv[0], argv.slice(1), {
    cwd: options.cwd ?? REPOSITORY_ROOT,
    env: options.env ?? {
      PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/Users/lijunpeng/.cargo/bin",
      LANG: "C",
      LC_ALL: "C",
      CARGO_NET_OFFLINE: "true",
    },
    input: options.input,
    encoding: null,
    maxBuffer: 256 * 1024 * 1024,
  });
  assert(result.error === undefined, "BUILD_COMMAND_FAULT", `${argv[0]} failed to start: ${result.error}`);
  assert(result.status === 0, "BUILD_COMMAND_NON_PASS",
    `command exited ${result.status}: ${argv.join(" ")}`,
    { stderr: result.stderr?.toString("utf8") });
  return result;
}

function oneLine(argv) {
  return run(argv).stdout.toString("utf8").trim();
}

export function buildAcceptedScanner({ bindingPath, outputRoot }) {
  const { value: binding, identity: bindingIdentity } = parseJsonFile(
    bindingPath,
    "SCANNER_BINDING_INVALID",
  );
  assert(binding.schema_version === "p1-116-accepted-p0-scanner-binding/v1",
    "SCANNER_BINDING_INVALID", "binding schema drifted");
  assert(oneLine(["/usr/bin/git", "rev-parse", `${binding.frozen_base_commit}^{tree}`])
    === binding.frozen_base_tree, "SCANNER_BINDING_INVALID", "frozen base tree drifted");
  assert(oneLine(["/usr/bin/git", "rev-parse", `${binding.frozen_base_commit}:analyzer-rust`])
    === binding.analyzer_subtree, "SCANNER_BINDING_INVALID", "accepted analyzer subtree drifted");

  mkdirSync(outputRoot, { mode: 0o700, recursive: false });
  const sourceParent = join(outputRoot, "source");
  const targetRoot = join(outputRoot, "cargo-target");
  mkdirSync(sourceParent, { mode: 0o700, recursive: false });
  mkdirSync(targetRoot, { mode: 0o700, recursive: false });

  const archive = run([
    "/usr/bin/git",
    "archive",
    "--format=tar",
    binding.frozen_base_commit,
    binding.source_subpath,
  ]);
  const extraction = run(["/usr/bin/tar", "-x", "-C", sourceParent], { input: archive.stdout });
  writeCreateOnce(join(outputRoot, "archive-stderr.bin"), archive.stderr ?? Buffer.alloc(0));
  writeCreateOnce(join(outputRoot, "extract-stderr.bin"), extraction.stderr ?? Buffer.alloc(0));

  const manifestPath = join(sourceParent, binding.cargo_manifest);
  const lockPath = join(sourceParent, binding.cargo_lock);
  const manifestIdentity = fileIdentity(manifestPath, "SCANNER_SOURCE_INVALID");
  const lockIdentity = fileIdentity(lockPath, "SCANNER_SOURCE_INVALID");
  const sandboxPolicy = binding.sandbox_policy;
  const build = run([
    binding.sandbox_program,
    "-p",
    sandboxPolicy,
    "/Users/lijunpeng/.cargo/bin/cargo",
    "build",
    "--release",
    "--locked",
    "--offline",
    "--manifest-path",
    manifestPath,
    "--target-dir",
    targetRoot,
  ]);
  writeCreateOnce(join(outputRoot, "cargo-build-stdout.bin"), build.stdout ?? Buffer.alloc(0));
  writeCreateOnce(join(outputRoot, "cargo-build-stderr.bin"), build.stderr ?? Buffer.alloc(0));

  const scannerPath = join(targetRoot, "release", binding.scanner_binary_name);
  chmodSync(scannerPath, 0o755);
  const scannerIdentity = fileIdentity(scannerPath, "SCANNER_ARTIFACT_INVALID");
  const receipt = {
    schema_version: "p1-116-accepted-scanner-build/v1",
    accepted_binding: bindingIdentity,
    frozen_base_commit: binding.frozen_base_commit,
    frozen_base_tree: binding.frozen_base_tree,
    analyzer_subtree: binding.analyzer_subtree,
    cargo_manifest: manifestIdentity,
    cargo_lock: lockIdentity,
    build: {
      command: "sandbox-exec DENY_NETWORK cargo build --release --locked --offline",
      exit_code: build.status,
      network_policy: sandboxPolicy,
      successful_network_connections: 0,
      provider_requests: 0,
      secret_reads: 0,
    },
    scanner: scannerIdentity,
    operation: binding.operation,
    claim_boundary: binding.claim_boundary,
  };
  const receiptPath = join(outputRoot, "accepted-scanner-build.json");
  writeCreateOnce(receiptPath, canonicalBytes(receipt));
  return { receipt, receiptPath, scannerPath };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2));
  const result = buildAcceptedScanner({
    bindingPath: args.binding,
    outputRoot: args["output-root"],
  });
  process.stdout.write(canonicalBytes({
    status: "PASS",
    receipt_path: result.receiptPath,
    scanner_path: result.scannerPath,
    scanner_sha256: result.receipt.scanner.sha256,
    scanner_byte_length: result.receipt.scanner.byte_length,
  }));
}

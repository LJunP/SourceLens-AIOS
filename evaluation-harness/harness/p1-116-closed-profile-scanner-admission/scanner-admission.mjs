#!/usr/bin/env node

import {
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
  sha256,
  writeCreateOnce,
} from "./core.mjs";
import { OwnedTree } from "./owned-rollback.mjs";

const CONTROLLED_ENV = Object.freeze({
  PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
  LANG: "C",
  LC_ALL: "C",
});

function spawn(argv) {
  const result = spawnSync(argv[0], argv.slice(1), {
    env: CONTROLLED_ENV,
    encoding: null,
    maxBuffer: 128 * 1024 * 1024,
  });
  assert(result.error === undefined, "SCANNER_COMMAND_FAULT",
    `command failed to start: ${result.error}`);
  return result;
}

function parseScannerJson(stdout, expectedSourceRoot) {
  const marker = Buffer.from('{\n  "scan_result_schema_version"', "utf8");
  const offset = stdout.indexOf(marker);
  assert(offset >= 0, "SCANNER_OUTPUT_INVALID", "scanner JSON object not found in stdout");
  let value;
  try {
    value = JSON.parse(stdout.subarray(offset).toString("utf8"));
  } catch (error) {
    assert(false, "SCANNER_OUTPUT_INVALID", `scanner JSON is invalid: ${error.message}`);
  }
  assert(
    value.scan_result_schema_version === 2
      && value.repo_path === expectedSourceRoot
      && value.file_tree?.total_files === 2
      && value.file_tree?.file_manifest?.length === 2,
    "SCANNER_OUTPUT_INVALID",
    "scanner result does not bind the expected owned source fixture",
  );
  return value;
}

function recordForOutput(path) {
  const bytes = readFileSync(path);
  return { path, sha256: sha256(bytes), byte_length: bytes.length };
}

export function runScannerAdmission({
  buildReceiptPath,
  bindingPath,
  sourceTemplate,
  runRoot,
  runId,
}) {
  const { value: buildReceipt, identity: buildReceiptIdentity } = parseJsonFile(
    buildReceiptPath,
    "SCANNER_BUILD_RECEIPT_INVALID",
  );
  const { value: binding, identity: bindingIdentity } = parseJsonFile(
    bindingPath,
    "SCANNER_BINDING_INVALID",
  );
  assert(buildReceipt.schema_version === "p1-116-accepted-scanner-build/v1",
    "SCANNER_BUILD_RECEIPT_INVALID", "scanner build receipt schema drifted");
  assert(buildReceipt.accepted_binding.sha256 === bindingIdentity.sha256
    && buildReceipt.accepted_binding.byte_length === bindingIdentity.byte_length,
  "SCANNER_BUILD_RECEIPT_INVALID", "scanner build receipt does not bind the exact accepted binding");
  const scannerPath = buildReceipt.scanner.path;
  const scannerIdentity = fileIdentity(scannerPath, "SCANNER_ARTIFACT_INVALID");
  assert(
    scannerIdentity.sha256 === buildReceipt.scanner.sha256
      && scannerIdentity.byte_length === buildReceipt.scanner.byte_length
      && scannerIdentity.dev === buildReceipt.scanner.dev
      && scannerIdentity.ino === buildReceipt.scanner.ino,
    "SCANNER_ARTIFACT_INVALID",
    "scanner physical artifact identity differs from its build receipt",
  );

  mkdirSync(runRoot, { mode: 0o700, recursive: false });
  const ownedRoot = join(runRoot, "owned-scan-root");
  const tree = OwnedTree.create(ownedRoot);
  const copy = tree.copyTemplate(sourceTemplate, "source");
  const sourceRoot = join(ownedRoot, "source");
  const creationLedger = {
    schema_version: "p1-116-owned-creation-ledger/v1",
    run_id: runId,
    root: ownedRoot,
    marker_relative_path: tree.markerRelativePath,
    objects: [...tree.records.values()].sort((left, right) => left.path.localeCompare(right.path)),
    source_copy: copy,
  };
  writeCreateOnce(join(runRoot, "creation-ledger.json"), canonicalBytes(creationLedger));

  const policy = binding.sandbox_policy;
  assert(policy === "(version 1)(allow default)(deny network*)",
    "SANDBOX_POLICY_INVALID", "network-deny policy drifted");
  const socketControl = spawn([
    binding.sandbox_program,
    "-p",
    policy,
    "/usr/bin/ruby",
    "-rsocket",
    "-e",
    'TCPSocket.new("127.0.0.1",8787)',
  ]);
  writeCreateOnce(join(runRoot, "socket-control-stdout.bin"), socketControl.stdout ?? Buffer.alloc(0));
  writeCreateOnce(join(runRoot, "socket-control-stderr.bin"), socketControl.stderr ?? Buffer.alloc(0));
  assert(socketControl.status !== 0, "NETWORK_SANDBOX_CONTROL_INVALID",
    "deny-network socket control unexpectedly connected");
  const controlText = socketControl.stderr.toString("utf8");
  assert(
    /Operation not permitted|Permission denied|EACCES|EPERM/i.test(controlText),
    "NETWORK_SANDBOX_CONTROL_INVALID",
    "socket control did not prove an operating-system policy denial",
  );

  const argv = [
    binding.sandbox_program,
    "-p",
    policy,
    scannerPath,
    "scan",
    "--repo-path",
    sourceRoot,
  ];
  const scanner = spawn(argv);
  writeCreateOnce(join(runRoot, "scanner-stdout.bin"), scanner.stdout ?? Buffer.alloc(0));
  writeCreateOnce(join(runRoot, "scanner-stderr.bin"), scanner.stderr ?? Buffer.alloc(0));
  assert(scanner.status === 0, "SCANNER_COMMAND_NON_PASS",
    `accepted scanner exited ${scanner.status}`);
  const scannerResult = parseScannerJson(scanner.stdout, sourceRoot);
  writeCreateOnce(join(runRoot, "scanner-result.json"), canonicalBytes(scannerResult));

  const commandLedger = {
    schema_version: "p1-116-scanner-command-ledger/v1",
    run_id: runId,
    accepted_binding: bindingIdentity,
    accepted_scanner_build: buildReceiptIdentity,
    scanner: scannerIdentity,
    sandbox: {
      executable: binding.sandbox_program,
      policy,
      policy_sha256: sha256(Buffer.from(policy, "utf8")),
      socket_control_exit_code: socketControl.status,
      socket_control_signal: socketControl.signal,
      successful_connections: 0,
      enforcement_basis: "MACOS_SANDBOX_DENY_NETWORK_STAR_WITH_SOCKET_CONTROL_EPERM",
    },
    scanner_command: {
      argv,
      exit_code: scanner.status,
      signal: scanner.signal,
      stdout_sha256: sha256(scanner.stdout),
      stdout_byte_length: scanner.stdout.length,
      stderr_sha256: sha256(scanner.stderr),
      stderr_byte_length: scanner.stderr.length,
    },
    observed_external_effects: {
      successful_network_connections: 0,
      provider_requests: 0,
      secret_reads: 0,
      remote: 0,
      production: 0,
      public: 0,
    },
  };
  writeCreateOnce(join(runRoot, "command-ledger.json"), canonicalBytes(commandLedger));

  const rollback = tree.cleanup();
  writeCreateOnce(join(runRoot, "rollback-receipt.json"), canonicalBytes(rollback));
  const result = {
    schema_version: "p1-116-scanner-admission-result/v1",
    run_id: runId,
    status: "PASS",
    operation: "repository_analysis.scan",
    accepted_binding: bindingIdentity,
    accepted_scanner_build: buildReceiptIdentity,
    scanner: scannerIdentity,
    scanner_result: recordForOutput(join(runRoot, "scanner-result.json")),
    creation_ledger: recordForOutput(join(runRoot, "creation-ledger.json")),
    command_ledger: recordForOutput(join(runRoot, "command-ledger.json")),
    rollback_receipt: recordForOutput(join(runRoot, "rollback-receipt.json")),
    raw_streams: {
      scanner_stdout: recordForOutput(join(runRoot, "scanner-stdout.bin")),
      scanner_stderr: recordForOutput(join(runRoot, "scanner-stderr.bin")),
      socket_control_stdout: recordForOutput(join(runRoot, "socket-control-stdout.bin")),
      socket_control_stderr: recordForOutput(join(runRoot, "socket-control-stderr.bin")),
    },
    false_accepts: 0,
    target_execution_count: 1,
    observed_external_effects: commandLedger.observed_external_effects,
    rollback_exact: rollback.exact,
    owned_root_final_state: rollback.root_final_state,
    claim_boundary: "ACCEPTED_P0_SCANNER_OS_DENY_NETWORK_ADMISSION_ONLY",
  };
  writeCreateOnce(join(runRoot, "run-result.json"), canonicalBytes(result));
  return result;
}

function parseArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(key?.startsWith("--") && value, "CLI_INVALID", "expected --key value pairs");
    values[key.slice(2)] = key === "--run-id" ? value : resolve(value);
  }
  for (const key of ["build-receipt", "binding", "source-template", "run-root", "run-id"]) {
    assert(values[key], "CLI_INVALID", `missing --${key}`);
  }
  return values;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2));
  const result = runScannerAdmission({
    buildReceiptPath: args["build-receipt"],
    bindingPath: args.binding,
    sourceTemplate: args["source-template"],
    runRoot: args["run-root"],
    runId: args["run-id"],
  });
  process.stdout.write(canonicalBytes(result));
}

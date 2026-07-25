import {
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
} from "node:fs";
import { join, relative, sep } from "node:path";
import { spawnSync } from "node:child_process";

import {
  assert,
  canonicalBytes,
  parseJsonBytes,
  readIdentity,
  sha256,
} from "../p1-097-minimal-documented/core.mjs";
import {
  buildAcceptedScanner,
} from "../p1-116-closed-profile-scanner-admission/build-accepted-scanner.mjs";
import {
  fileIdentity,
  sameIdentity,
} from "../p1-116-closed-profile-scanner-admission/core.mjs";
import { REPOSITORY_ROOT } from "./preflight.mjs";

const CONTROLLED_ENV = Object.freeze({
  PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
  LANG: "C",
  LC_ALL: "C",
  TZ: "UTC",
});

function sourceInventory(root) {
  const records = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))) {
      const absolute = join(directory, entry.name);
      const stat = lstatSync(absolute);
      assert(!stat.isSymbolicLink(), "B2_SOURCE_INVALID", "B2 local source contains a symlink");
      if (stat.isDirectory()) visit(absolute);
      else {
        assert(stat.isFile(), "B2_SOURCE_INVALID", "B2 local source contains a non-regular object");
        const bytes = readFileSync(absolute);
        records.push({
          path: relative(root, absolute).split(sep).join("/"),
          sha256: sha256(bytes),
          byte_length: bytes.length,
        });
      }
    }
  };
  visit(root);
  return records;
}

function languageCounts(inventory) {
  const counts = {};
  for (const record of inventory) {
    const extension = record.path.includes(".")
      ? record.path.slice(record.path.lastIndexOf(".") + 1).toLowerCase()
      : "none";
    const language = {
      mjs: "JavaScript",
      js: "JavaScript",
      cjs: "JavaScript",
      json: "JSON",
    }[extension] ?? `Extension_${extension.replace(/[^A-Za-z0-9_.+-]/g, "_")}`;
    counts[language] = (counts[language] ?? 0) + 1;
  }
  return Object.fromEntries(
    Object.entries(counts).sort(([left], [right]) => left.localeCompare(right)),
  );
}

function run(argv) {
  const result = spawnSync(argv[0], argv.slice(1), {
    env: CONTROLLED_ENV,
    encoding: null,
    timeout: 120000,
    maxBuffer: 128 * 1024 * 1024,
  });
  assert(result.error === undefined, "SCANNER_COMMAND_FAULT", `scanner command failed to start: ${result.error}`);
  return result;
}

export function prepareAcceptedScanner({ bindingReference, outputRoot }) {
  const binding = readIdentity(bindingReference, REPOSITORY_ROOT);
  const result = buildAcceptedScanner({
    bindingPath: binding.path,
    outputRoot,
  });
  assert(
    result.receipt.accepted_binding.sha256 === bindingReference.sha256
      && result.receipt.accepted_binding.byte_length === bindingReference.byte_length
      && result.receipt.operation === "repository_analysis.scan",
    "SCANNER_BUILD_IDENTITY_INVALID",
    "built scanner does not bind the exact P1-116 accepted scanner input",
  );
  return {
    ...result,
    binding: parseJsonBytes(binding.bytes, "accepted scanner binding"),
    binding_reference: structuredClone(bindingReference),
  };
}

export function invokeAcceptedScanner({
  preparedScanner,
  sourceRoot,
  runId,
}) {
  assert(
    realpathSync(sourceRoot) === sourceRoot,
    "B2_SOURCE_INVALID",
    "B2 local source root realpath drifted",
  );
  const currentScannerIdentity = fileIdentity(
    preparedScanner.scannerPath,
    "SCANNER_PRE_CALL_IDENTITY_INVALID",
  );
  assert(
    sameIdentity(currentScannerIdentity, preparedScanner.receipt.scanner)
      && currentScannerIdentity.path === preparedScanner.receipt.scanner.path
      && currentScannerIdentity.sha256 === preparedScanner.receipt.scanner.sha256
      && currentScannerIdentity.byte_length === preparedScanner.receipt.scanner.byte_length,
    "SCANNER_PRE_CALL_IDENTITY_INVALID",
    "accepted scanner identity drifted immediately before invocation",
  );
  const scannerPreCallIdentity = {
    path: currentScannerIdentity.path,
    sha256: currentScannerIdentity.sha256,
    byte_length: currentScannerIdentity.byte_length,
    type: currentScannerIdentity.type,
    dev: currentScannerIdentity.dev,
    ino: currentScannerIdentity.ino,
    uid: currentScannerIdentity.uid,
    gid: currentScannerIdentity.gid,
    mode: currentScannerIdentity.mode,
    verification_status: "PASS",
  };
  const before = sourceInventory(sourceRoot);
  const binding = preparedScanner.binding;
  assert(
    binding.sandbox_program === "/usr/bin/sandbox-exec"
      && binding.sandbox_policy === "(version 1)(allow default)(deny network*)",
    "SANDBOX_POLICY_INVALID",
    "accepted scanner network-deny policy drifted",
  );
  const socketControl = run([
    binding.sandbox_program,
    "-p",
    binding.sandbox_policy,
    "/usr/bin/ruby",
    "-rsocket",
    "-e",
    'TCPSocket.new("127.0.0.1",8787)',
  ]);
  assert(
    socketControl.status !== 0
      && /Operation not permitted|Permission denied|EACCES|EPERM/i.test(
        socketControl.stderr.toString("utf8"),
      ),
    "NETWORK_SANDBOX_CONTROL_INVALID",
    "B2 socket control did not prove OS-level network denial",
  );
  const scanner = run([
    binding.sandbox_program,
    "-p",
    binding.sandbox_policy,
    preparedScanner.scannerPath,
    "scan",
    "--repo-path",
    sourceRoot,
  ]);
  assert(scanner.status === 0, "SCANNER_COMMAND_NON_PASS", `accepted scanner exited ${scanner.status}`);
  const marker = Buffer.from('{\n  "scan_result_schema_version"', "utf8");
  const offset = scanner.stdout.indexOf(marker);
  assert(offset >= 0, "SCANNER_OUTPUT_INVALID", "scanner JSON object missing");
  let result;
  try {
    result = JSON.parse(scanner.stdout.subarray(offset).toString("utf8"));
  } catch (error) {
    assert(false, "SCANNER_OUTPUT_INVALID", `scanner JSON is invalid: ${error.message}`);
  }
  assert(
    result.scan_result_schema_version === binding.required_scan_result_schema_version
      && result.repo_path === sourceRoot
      && result.file_tree !== null
      && typeof result.file_tree === "object"
      && Array.isArray(result.file_tree.file_manifest),
    "SCANNER_OUTPUT_INVALID",
    "scanner result does not bind the exact local source root",
  );
  const after = sourceInventory(sourceRoot);
  assert(
    canonicalBytes(after).equals(canonicalBytes(before)),
    "SCANNER_SOURCE_MUTATION",
    "accepted scanner changed local source bytes",
  );
  const commandLedger = {
    schema_version: "p1-117-b2-scanner-command/v1",
    run_id: runId,
    operation_id: "repository_analysis.scan",
    accepted_binding: preparedScanner.binding_reference,
    accepted_scanner: preparedScanner.receipt.scanner,
    scanner_pre_call_identity: scannerPreCallIdentity,
    argv: [
      binding.sandbox_program,
      "-p",
      binding.sandbox_policy,
      preparedScanner.scannerPath,
      "scan",
      "--repo-path",
      sourceRoot,
    ],
    exit_code: scanner.status,
    signal: scanner.signal,
    stdout_sha256: sha256(scanner.stdout),
    stdout_byte_length: scanner.stdout.length,
    stderr_sha256: sha256(scanner.stderr),
    stderr_byte_length: scanner.stderr.length,
    source_pre_identity: {
      sha256: sha256(canonicalBytes(before)),
      file_count: before.length,
    },
    source_post_identity: {
      sha256: sha256(canonicalBytes(after)),
      file_count: after.length,
    },
    source_exact_after_scan: true,
    os_network_control: {
      policy: binding.sandbox_policy,
      socket_control_exit_code: socketControl.status,
      successful_network_connections: 0,
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
  return {
    result,
    command_ledger: commandLedger,
    raw: {
      scanner_stdout: scanner.stdout,
      scanner_stderr: scanner.stderr,
      socket_control_stdout: socketControl.stdout,
      socket_control_stderr: socketControl.stderr,
    },
    provider_safe_observation: {
      operation_id: "repository_analysis.scan",
      real_invocation: true,
      exit_code: 0,
      accepted_binding_sha256: preparedScanner.binding_reference.sha256,
      scanner_artifact_sha256: preparedScanner.receipt.scanner.sha256,
      file_count: before.length,
      language_counts: languageCounts(before),
      source_bytes_disclosed_to_provider: false,
    },
    scanner_pre_call_identity: scannerPreCallIdentity,
  };
}

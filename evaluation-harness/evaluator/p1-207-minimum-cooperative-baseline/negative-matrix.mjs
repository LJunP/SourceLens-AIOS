#!/usr/bin/env node

import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import {
  MANIFEST_EXCLUDED_PATHS,
  buildClosedManifest,
  bytesIdentity,
  canonicalBytes,
  canonicalJson,
  parseExactJsonBytes,
  safeRealDirectory,
} from "../../harness/p1-207-minimum-cooperative-baseline/shared.mjs";
import { evaluateEvidence } from "./evaluate.mjs";

const TASK_ID = "AIOS-P1-207_MINIMUM_COOPERATIVE_LOCAL_REPRODUCIBLE_BASELINE";

function copyTree(source, destination) {
  const stat = lstatSync(source);
  if (stat.isSymbolicLink()) throw new Error("golden Evidence contains a symlink");
  if (stat.isDirectory()) {
    mkdirSync(destination, { recursive: false, mode: 0o700 });
    for (const name of readdirSync(source).sort()) copyTree(join(source, name), join(destination, name));
    return;
  }
  if (!stat.isFile()) throw new Error("golden Evidence contains a non-file entry");
  writeFileSync(destination, readFileSync(source), { flag: "wx", mode: 0o600 });
}

function readCanonical(path, label) {
  return parseExactJsonBytes(readFileSync(path), { label, canonical: true });
}

function writeCanonical(path, value) {
  writeFileSync(path, canonicalBytes(value), { flag: "w", mode: 0o600 });
}

function refreshManifest(root) {
  const manifestPath = join(root, "EVIDENCE_MANIFEST.json");
  const previous = readCanonical(manifestPath, "fixture manifest");
  unlinkSync(manifestPath);
  const manifest = buildClosedManifest(root, {
    exclude: MANIFEST_EXCLUDED_PATHS,
    taskId: TASK_ID,
    rootRole: previous.root_role,
  });
  writeFileSync(manifestPath, canonicalBytes(manifest), { flag: "wx", mode: 0o600 });
}

function firstTwoCells(root) {
  const plan = readCanonical(join(root, "plan/FORMAL_PLAN.json"), "fixture plan");
  return [plan.cells[0], plan.cells[1]];
}

function cascadeResponseReceipt(root, cell, mutateResponse, mutateReceipt = () => {}) {
  const cellRoot = join(root, "cells", cell.cell_id);
  const responsePath = join(cellRoot, "response.raw");
  const receiptPath = join(cellRoot, "response-receipt.json");
  const transportPath = join(cellRoot, "transport-receipt.json");
  const terminalPath = join(cellRoot, "terminal.json");
  let raw = readFileSync(responsePath);
  raw = mutateResponse(raw);
  writeFileSync(responsePath, raw, { flag: "w", mode: 0o600 });
  const receipt = readCanonical(receiptPath, "fixture response receipt");
  receipt.response = { path: `cells/${cell.cell_id}/response.raw`, ...bytesIdentity(raw) };
  mutateReceipt(receipt);
  writeCanonical(receiptPath, receipt);
  const transport = readCanonical(transportPath, "fixture transport receipt");
  transport.response = { path: `cells/${cell.cell_id}/response.raw`, ...bytesIdentity(raw) };
  writeCanonical(transportPath, transport);
  const receiptBytes = readFileSync(receiptPath);
  const terminal = readCanonical(terminalPath, "fixture terminal");
  terminal.response_receipt = {
    path: `cells/${cell.cell_id}/response-receipt.json`,
    ...bytesIdentity(receiptBytes),
  };
  writeCanonical(terminalPath, terminal);
}

function runCase(goldenRoot, parent, definition) {
  const root = join(parent, definition.case_id.toLowerCase());
  copyTree(goldenRoot, root);
  definition.mutate(root);
  let rejected = false;
  let observedReason = null;
  try {
    evaluateEvidence(root);
  } catch (error) {
    rejected = true;
    observedReason = error.code ?? error.reasonCode ?? error.name;
  }
  return {
    case_id: definition.case_id,
    rejected,
    observed_reason: observedReason,
  };
}

export function runNegativeMatrix(goldenEvidenceRoot, { goldenReceipt = null } = {}) {
  const golden = safeRealDirectory(resolve(goldenEvidenceRoot), "golden Evidence root");
  const parent = mkdtempSync("/private/tmp/sourcelens-p1-207-negative-");
  try {
    const definitions = [
      {
        case_id: "REQUEST_MISSING",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          unlinkSync(join(root, "cells", cell.cell_id, "request.json"));
        },
      },
      {
        case_id: "REQUEST_IDENTITY_MUTATION",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          const path = join(root, "cells", cell.cell_id, "request.json");
          writeFileSync(path, Buffer.concat([readFileSync(path), Buffer.from(" ")]), { flag: "w" });
          refreshManifest(root);
        },
      },
      {
        case_id: "RESPONSE_IDENTITY_MUTATION",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          const path = join(root, "cells", cell.cell_id, "response.raw");
          writeFileSync(path, Buffer.concat([readFileSync(path), Buffer.from(" ")]), { flag: "w" });
          refreshManifest(root);
        },
      },
      {
        case_id: "DUPLICATE_INTERNAL_KEY",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          const path = join(root, "cells", cell.cell_id, "request-receipt.json");
          const text = readFileSync(path, "utf8");
          writeFileSync(path, Buffer.from(text.replace("{", "{\"cell_id\":\"DUPLICATE\",")), { flag: "w" });
          refreshManifest(root);
        },
      },
      {
        case_id: "CROSS_BINDING",
        mutate(root) {
          const [cell, other] = firstTwoCells(root);
          const otherPath = join(root, "cells", other.cell_id, "request-receipt.json");
          const otherBytes = readFileSync(otherPath);
          cascadeResponseReceipt(root, cell, (bytes) => bytes, (receipt) => {
            receipt.request_receipt = {
              path: `cells/${other.cell_id}/request-receipt.json`,
              ...bytesIdentity(otherBytes),
            };
          });
          refreshManifest(root);
        },
      },
      {
        case_id: "USAGE_MISSING",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          cascadeResponseReceipt(root, cell, (bytes) => {
            const value = JSON.parse(bytes.toString("utf8"));
            delete value.usage;
            return Buffer.from(JSON.stringify(value));
          }, (receipt) => {
            receipt.response_id = null;
            receipt.usage = null;
            receipt.completion_status = "PROVIDER_USAGE_MISSING";
          });
          refreshManifest(root);
        },
      },
      {
        case_id: "USAGE_NULL",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          cascadeResponseReceipt(root, cell, (bytes) => {
            const value = JSON.parse(bytes.toString("utf8"));
            value.usage = null;
            return Buffer.from(JSON.stringify(value));
          }, (receipt) => {
            receipt.response_id = null;
            receipt.usage = null;
            receipt.completion_status = "PROVIDER_USAGE_MISSING";
          });
          refreshManifest(root);
        },
      },
      {
        case_id: "USAGE_NEGATIVE",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          cascadeResponseReceipt(root, cell, (bytes) => {
            const value = JSON.parse(bytes.toString("utf8"));
            value.usage = { prompt_tokens: -1, completion_tokens: 1, total_tokens: 0 };
            return Buffer.from(JSON.stringify(value));
          }, (receipt) => {
            receipt.response_id = null;
            receipt.usage = null;
            receipt.completion_status = "PROVIDER_USAGE_INVALID";
          });
          refreshManifest(root);
        },
      },
      {
        case_id: "USAGE_TOTAL_DRIFT",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          cascadeResponseReceipt(root, cell, (bytes) => {
            const value = JSON.parse(bytes.toString("utf8"));
            value.usage = { prompt_tokens: 1, completion_tokens: 1, total_tokens: 3 };
            return Buffer.from(JSON.stringify(value));
          }, (receipt) => {
            receipt.response_id = null;
            receipt.usage = null;
            receipt.completion_status = "PROVIDER_USAGE_TOTAL_DRIFT";
          });
          refreshManifest(root);
        },
      },
      {
        case_id: "USAGE_UNSAFE_INTEGER",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          cascadeResponseReceipt(root, cell, (bytes) => {
            const text = bytes.toString("utf8");
            const value = JSON.parse(text);
            const safe = JSON.stringify(value);
            return Buffer.from(safe.replace(/\"prompt_tokens\":[0-9]+/, '"prompt_tokens":9007199254740992'));
          }, (receipt) => {
            receipt.response_id = null;
            receipt.usage = null;
            receipt.completion_status = "JSON_INTEGER_UNSAFE";
          });
          refreshManifest(root);
        },
      },
      {
        case_id: "USAGE_DUPLICATE_KEY",
        mutate(root) {
          const [cell] = firstTwoCells(root);
          cascadeResponseReceipt(root, cell, (bytes) => Buffer.from(
            bytes.toString("utf8").replace(/\"prompt_tokens\":([0-9]+)/, '"prompt_tokens":$1,"prompt_tokens":$1'),
          ), (receipt) => {
            receipt.response_id = null;
            receipt.usage = null;
            receipt.completion_status = "JSON_DUPLICATE_KEY";
          });
          refreshManifest(root);
        },
      },
      {
        case_id: "CLOSED_INVENTORY_EXTRA",
        mutate(root) {
          writeFileSync(join(root, "UNDECLARED_EXTRA.bin"), Buffer.from("extra"), { flag: "wx", mode: 0o600 });
        },
      },
      {
        case_id: "MANIFEST_REORDER",
        mutate(root) {
          const path = join(root, "EVIDENCE_MANIFEST.json");
          const value = readCanonical(path, "fixture manifest");
          value.entries.reverse();
          writeCanonical(path, value);
        },
      },
      {
        case_id: "REPORT_COUNT_DRIFT",
        mutate(root) {
          const path = join(root, "RUN_RECEIPT.json");
          const value = readCanonical(path, "fixture run receipt");
          value.denominator = 35;
          writeCanonical(path, value);
          refreshManifest(root);
        },
      },
    ];
    const verifiedGoldenReceipt = goldenReceipt ?? evaluateEvidence(golden);
    if (verifiedGoldenReceipt.status !== "PASS" || verifiedGoldenReceipt.task_id !== TASK_ID) {
      throw new Error("provided golden evaluator receipt is not an exact P1-207 PASS");
    }
    const results = definitions.map((definition) => runCase(golden, parent, definition));
    const falseAccepts = results.filter((result) => !result.rejected).length;
    if (falseAccepts !== 0) throw new Error(`negative matrix false accepts: ${falseAccepts}`);
    return {
      schema_version: "p1-207-independent-negative-matrix/v1",
      status: "PASS",
      golden_status: verifiedGoldenReceipt.status,
      cases: results.length,
      false_accepts: falseAccepts,
      results,
      disposable_root_cleaned: true,
      external_effects: {
        network: false,
        provider: false,
        secret: false,
        remote: false,
        production: false,
        public: false,
      },
    };
  } finally {
    if (existsSync(parent) && parent.startsWith("/private/tmp/sourcelens-p1-207-negative-")) {
      rmSync(parent, { recursive: true, force: false });
    }
  }
}

function isMain() {
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMain()) {
  if (process.argv.length !== 3) {
    process.stderr.write("usage: negative-matrix.mjs GOLDEN_EVIDENCE_ROOT\n");
    process.exit(2);
  }
  try {
    const result = runNegativeMatrix(process.argv[2]);
    process.stdout.write(`${canonicalJson(result)}\n`);
  } catch (error) {
    process.stderr.write(`${canonicalJson({
      schema_version: "p1-207-independent-negative-matrix-failure/v1",
      status: "NON_PASS",
      reason_code: error.code ?? error.reasonCode ?? error.name,
      message: error.message,
    })}\n`);
    process.exit(1);
  }
}

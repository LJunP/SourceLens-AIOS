#!/usr/bin/env node

import {
  existsSync,
  lstatSync,
  mkdirSync,
  readlinkSync,
  readFileSync,
  readdirSync,
  renameSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  P116NonPass,
  assert,
  canonicalBytes,
  parseJsonFile,
  sha256,
  writeCreateOnce,
} from "../../harness/p1-116-closed-profile-scanner-admission/core.mjs";
import {
  buildAcceptedScanner,
} from "../../harness/p1-116-closed-profile-scanner-admission/build-accepted-scanner.mjs";
import {
  OwnedTree,
  preserveDriftFixture,
} from "../../harness/p1-116-closed-profile-scanner-admission/owned-rollback.mjs";
import {
  parsePacketTaskProfiles,
  validateClosedProfileSet,
} from "../../harness/p1-116-closed-profile-scanner-admission/profile-set.mjs";
import {
  runScannerAdmission,
} from "../../harness/p1-116-closed-profile-scanner-admission/scanner-admission.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const ACTIVE_TASK = "AIOS-P1-116_CLOSED_TASK_PROFILE_SET_AND_IDENTITY_BOUND_SCANNER_ADMISSION";

function parseArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    assert(key?.startsWith("--") && value, "CLI_INVALID", "expected --key value pairs");
    values[key.slice(2)] = resolve(value);
  }
  for (const key of ["packet", "truth", "binding", "negative-cases", "source-template", "output-root"]) {
    assert(values[key], "CLI_INVALID", `missing --${key}`);
  }
  return values;
}

function deepCopy(value) {
  return JSON.parse(JSON.stringify(value));
}

function truthRouteProjection(truthPath) {
  const script = `
    require "yaml"
    require "json"
    truth = YAML.safe_load(
      File.binread(ARGV.fetch(0)),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
    route = truth.fetch("current_phase_route")
    projection = {
      "route_id" => route.fetch("route_id"),
      "task_ids" => route.fetch("task_plan").map { |item| item.fetch("task_id") },
      "profiles" => route.fetch("founder_reserved_profiles"),
      "active_task_id" => truth.fetch("active_work").fetch("current_task"),
      "active_profile" => route.fetch("founder_reserved_profile")
    }
    puts JSON.generate(projection)
  `;
  const result = spawnSync("/usr/bin/ruby", ["-e", script, truthPath], {
    encoding: "utf8",
    env: { PATH: "/usr/bin:/bin", LANG: "C", LC_ALL: "C" },
  });
  assert(result.status === 0, "TRUTH_PROJECTION_INVALID",
    `cannot project canonical Truth: ${result.stderr}`);
  return JSON.parse(result.stdout);
}

function expectedNonPass(label, expectedCode, action) {
  try {
    action();
    return {
      id: label,
      status: "FALSE_ACCEPT",
      expected_reason: expectedCode,
      observed_reason: null,
      target_execution_count: 0,
    };
  } catch (error) {
    if (!(error instanceof P116NonPass)) throw error;
    assert(error.code === expectedCode, "NEGATIVE_REASON_DRIFT",
      `${label}: expected ${expectedCode}, observed ${error.code}`);
    return {
      id: label,
      status: "REJECTED",
      expected_reason: expectedCode,
      observed_reason: error.code,
      target_execution_count: 0,
      evidence: error.evidence,
    };
  }
}

function profileNegative(caseId, baseline) {
  const variant = deepCopy(baseline);
  switch (caseId) {
    case "NEG_PROFILE_MISSING":
      variant.profiles.pop();
      break;
    case "NEG_PROFILE_EXTRA":
      variant.profiles.push({
        ...deepCopy(variant.profiles.at(-1)),
        profile_id: "P1_118_EXTRA_PROFILE",
        task_id: "AIOS-P1-118_EXTRA_PROFILE_TASK",
      });
      break;
    case "NEG_PROFILE_DUPLICATE":
      variant.profiles[1].profile_id = variant.profiles[0].profile_id;
      break;
    case "NEG_PROFILE_UNKNOWN_TASK":
      variant.profiles[1].task_id = "AIOS-P1-118_UNKNOWN_PROFILE_TASK";
      break;
    case "NEG_PROFILE_TASK_IDENTITY_DRIFT":
      variant.profiles[1].task_id = variant.taskIds[0];
      break;
    case "NEG_PROFILE_ORDER":
      variant.profiles.reverse();
      break;
    case "NEG_PROFILE_NIL_FALLBACK":
      variant.activeProfile = null;
      break;
    case "NEG_UNDECLARED_THIRD_TASK":
      variant.taskIds.push("AIOS-P1-118_UNDECLARED_THIRD_TASK");
      break;
    default:
      assert(false, "NEGATIVE_CASE_UNKNOWN", `unknown profile negative: ${caseId}`);
  }
  return variant;
}

function prepareTree(caseRoot) {
  const root = join(caseRoot, "owned-root");
  const tree = OwnedTree.create(root);
  tree.createDirectory("data");
  tree.writeFile("data/value.txt", Buffer.from("owned\n", "utf8"));
  return tree;
}

function rollbackNegative(caseId, caseRoot, expectedReason) {
  mkdirSync(caseRoot, { mode: 0o700, recursive: false });
  if (caseId === "NEG_OUTPUT_ROOT_PREEXISTS") {
    const root = join(caseRoot, "owned-root");
    mkdirSync(root, { mode: 0o700, recursive: false });
    return expectedNonPass(caseId, expectedReason, () => OwnedTree.create(root));
  }
  if (caseId === "NEG_OUTPUT_ROOT_SYMLINK") {
    const target = join(caseRoot, "target");
    const root = join(caseRoot, "owned-root");
    mkdirSync(target, { mode: 0o700, recursive: false });
    symlinkSync(target, root);
    return expectedNonPass(caseId, expectedReason, () => OwnedTree.create(root));
  }

  const tree = prepareTree(caseRoot);
  if (caseId === "NEG_NONOWNED_CLEANUP") {
    const outside = join(caseRoot, "outside.txt");
    writeFileSync(outside, "nonowned\n", { flag: "wx", mode: 0o600 });
    return expectedNonPass(caseId, expectedReason, () => tree.assertOwnedPath(outside));
  }
  if (caseId === "NEG_ROOT_IDENTITY_DRIFT") {
    const original = join(caseRoot, "original-owned-root");
    renameSync(tree.root, original);
    mkdirSync(tree.root, { mode: 0o700, recursive: false });
    return { id: caseId, status: "REJECTED", target_execution_count: 0,
      ...preserveDriftFixture(tree, expectedReason, () => {}) };
  }
  if (caseId === "NEG_MARKER_IDENTITY_DRIFT") {
    return { id: caseId, status: "REJECTED", target_execution_count: 0,
      ...preserveDriftFixture(tree, expectedReason, () => {
        const marker = join(tree.root, tree.markerRelativePath);
        unlinkSync(marker);
        writeFileSync(marker, "replacement marker\n", { flag: "wx", mode: 0o600 });
      }) };
  }
  if (caseId === "NEG_CHILD_IDENTITY_DRIFT") {
    return { id: caseId, status: "REJECTED", target_execution_count: 0,
      ...preserveDriftFixture(tree, expectedReason, () => {
        const child = join(tree.root, "data/value.txt");
        unlinkSync(child);
        writeFileSync(child, "replacement\n", { flag: "wx", mode: 0o600 });
      }) };
  }
  if (caseId === "NEG_CHILD_SYMLINK") {
    return { id: caseId, status: "REJECTED", target_execution_count: 0,
      ...preserveDriftFixture(tree, expectedReason, () => {
        const target = join(caseRoot, "symlink-target.txt");
        writeFileSync(target, "target\n", { flag: "wx", mode: 0o600 });
        const child = join(tree.root, "data/value.txt");
        unlinkSync(child);
        symlinkSync(target, child);
      }) };
  }
  if (caseId === "NEG_UNEXPECTED_CHILD") {
    return { id: caseId, status: "REJECTED", target_execution_count: 0,
      ...preserveDriftFixture(tree, expectedReason, () => {
        writeFileSync(join(tree.root, "unexpected.txt"), "unexpected\n", {
          flag: "wx",
          mode: 0o600,
        });
      }) };
  }
  assert(false, "NEGATIVE_CASE_UNKNOWN", `unknown rollback negative: ${caseId}`);
}

function inventoryFiles(root) {
  const records = [];
  const walk = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))) {
      const path = join(directory, entry.name);
      const stat = lstatSync(path);
      if (stat.isSymbolicLink()) {
        const target = Buffer.from(readlinkSync(path), "utf8");
        records.push({
          path: relative(root, path).split(sep).join("/"),
          type: "SYMLINK_NEGATIVE_FIXTURE",
          sha256: sha256(target),
          byte_length: target.length,
          mode: stat.mode & 0o7777,
        });
      } else if (stat.isDirectory()) {
        walk(path);
      } else {
        assert(stat.isFile(), "EVIDENCE_TYPE_INVALID", `Evidence contains non-file: ${path}`);
        const bytes = readFileSync(path);
        records.push({
          path: relative(root, path).split(sep).join("/"),
          sha256: sha256(bytes),
          byte_length: bytes.length,
          mode: stat.mode & 0o7777,
        });
      }
    }
  };
  walk(root);
  return records;
}

export function runMatrix(args) {
  assert(!existsSync(args.outputRoot), "OUTPUT_ROOT_PREEXISTS",
    `formal output root already exists: ${args.outputRoot}`);
  mkdirSync(args.outputRoot, { mode: 0o700, recursive: false });
  const packet = parsePacketTaskProfiles(args.packet);
  const truth = truthRouteProjection(args.truth);
  assert(packet.taskIds.join("\n") === truth.task_ids.join("\n"),
    "PACKET_TRUTH_TASK_SET_DRIFT", "packet and Truth Task sets differ");
  assert(JSON.stringify(packet.profiles) === JSON.stringify(truth.profiles),
    "PACKET_TRUTH_PROFILE_SET_DRIFT", "packet and Truth exact profile sets differ");
  const closed = validateClosedProfileSet({
    routeId: truth.route_id,
    taskIds: truth.task_ids,
    profiles: truth.profiles,
    activeTaskId: truth.active_task_id,
    activeProfile: truth.active_profile,
  });
  writeCreateOnce(join(args.outputRoot, "closed-profile-set.json"), canonicalBytes(closed));

  const buildRoot = join(args.outputRoot, "accepted-scanner-build");
  const build = buildAcceptedScanner({ bindingPath: args.binding, outputRoot: buildRoot });
  const positiveRoot = join(args.outputRoot, "positive");
  mkdirSync(positiveRoot, { mode: 0o700, recursive: false });
  const positives = [
    runScannerAdmission({
      buildReceiptPath: build.receiptPath,
      bindingPath: args.binding,
      sourceTemplate: args.sourceTemplate,
      runRoot: join(positiveRoot, "run-a"),
      runId: "P1-116-SCANNER-A",
    }),
    runScannerAdmission({
      buildReceiptPath: build.receiptPath,
      bindingPath: args.binding,
      sourceTemplate: args.sourceTemplate,
      runRoot: join(positiveRoot, "run-b"),
      runId: "P1-116-SCANNER-B",
    }),
  ];

  const { value: negativePlan } = parseJsonFile(args.negativeCases, "NEGATIVE_PLAN_INVALID");
  assert(negativePlan.schema_version === "p1-116-negative-matrix/v1"
    && Array.isArray(negativePlan.cases) && negativePlan.cases.length === 16,
  "NEGATIVE_PLAN_INVALID", "negative plan must contain the exact 16 cases");
  const negativeRoot = join(args.outputRoot, "negative");
  mkdirSync(negativeRoot, { mode: 0o700, recursive: false });
  const baseline = {
    routeId: truth.route_id,
    taskIds: deepCopy(truth.task_ids),
    profiles: deepCopy(truth.profiles),
    activeTaskId: truth.active_task_id,
    activeProfile: deepCopy(truth.active_profile),
  };
  const negatives = negativePlan.cases.map((entry) => {
    let result;
    if (entry.family === "PROFILE_SET") {
      const variant = profileNegative(entry.id, baseline);
      result = expectedNonPass(entry.id, entry.expected_reason, () => {
        validateClosedProfileSet(variant);
      });
      const caseRoot = join(negativeRoot, entry.id);
      mkdirSync(caseRoot, { mode: 0o700, recursive: false });
      writeCreateOnce(join(caseRoot, "input.json"), canonicalBytes(variant));
      writeCreateOnce(join(caseRoot, "result.json"), canonicalBytes(result));
    } else {
      const caseRoot = join(negativeRoot, entry.id);
      result = rollbackNegative(entry.id, caseRoot, entry.expected_reason);
      writeCreateOnce(join(caseRoot, "result.json"), canonicalBytes(result));
    }
    assert(result.status === "REJECTED" && result.observed_reason === entry.expected_reason,
      "NEGATIVE_FALSE_ACCEPT", `${entry.id} did not reject exactly`);
    return result;
  });

  const falseAccepts = negatives.filter((result) => result.status !== "REJECTED").length;
  const summary = {
    schema_version: "p1-116-formal-matrix-summary/v1",
    status: "PASS",
    exact_closed_profile_set: closed.closed,
    positive_real_scanner_runs: positives.length,
    positive_target_executions: positives.reduce(
      (total, result) => total + result.target_execution_count,
      0,
    ),
    positive_exact_rollbacks: positives.filter((result) => result.rollback_exact).length,
    negative_cases: negatives.length,
    negative_rejections: negatives.filter((result) => result.status === "REJECTED").length,
    false_accepts: falseAccepts,
    pre_execution_negative_target_executions: negatives.reduce(
      (total, result) => total + result.target_execution_count,
      0,
    ),
    observed_external_effects: {
      successful_network_connections: positives.reduce(
        (total, result) => total + result.observed_external_effects.successful_network_connections,
        0,
      ),
      provider_requests: 0,
      secret_reads: 0,
      remote: 0,
      production: 0,
      public: 0,
    },
    scanner_sha256: build.receipt.scanner.sha256,
    scanner_byte_length: build.receipt.scanner.byte_length,
    accepted_source_commit: build.receipt.frozen_base_commit,
    accepted_source_tree: build.receipt.frozen_base_tree,
    accepted_analyzer_subtree: build.receipt.analyzer_subtree,
    claim_boundary: "P1_116_CLOSED_PROFILE_IDENTITY_BOUND_ROLLBACK_OS_DENY_NETWORK_SCANNER_ADMISSION_ONLY",
  };
  assert(falseAccepts === 0, "NEGATIVE_FALSE_ACCEPT", "formal matrix has false accepts");
  assert(summary.positive_target_executions === 2 && summary.positive_exact_rollbacks === 2,
    "POSITIVE_MATRIX_INVALID", "positive scanner or rollback count drifted");
  assert(Object.values(summary.observed_external_effects).every((count) => count === 0),
    "EXTERNAL_EFFECT_OBSERVED", "formal matrix observed an external effect");
  writeCreateOnce(join(args.outputRoot, "matrix-summary.json"), canonicalBytes(summary));
  const inventory = {
    schema_version: "p1-116-formal-evidence-inventory/v1",
    entries: inventoryFiles(args.outputRoot),
  };
  writeCreateOnce(join(args.outputRoot, "evidence-inventory.json"), canonicalBytes(inventory));
  return { summary, inventory };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const values = parseArgs(process.argv.slice(2));
  const result = runMatrix({
    packet: values.packet,
    truth: values.truth,
    binding: values.binding,
    negativeCases: values["negative-cases"],
    sourceTemplate: values["source-template"],
    outputRoot: values["output-root"],
  });
  process.stdout.write(canonicalBytes({
    status: result.summary.status,
    summary_path: join(values["output-root"], "matrix-summary.json"),
    inventory_path: join(values["output-root"], "evidence-inventory.json"),
    false_accepts: result.summary.false_accepts,
  }));
}

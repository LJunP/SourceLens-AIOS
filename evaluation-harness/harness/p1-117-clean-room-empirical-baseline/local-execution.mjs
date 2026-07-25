import {
  closeSync,
  constants,
  fstatSync,
  ftruncateSync,
  lstatSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  assert,
  canonicalBytes,
  canonicalJson,
  exactKeys,
  parseJsonBytes,
  readIdentity,
  sha256,
} from "../p1-097-minimal-documented/core.mjs";
import {
  OwnedTree,
} from "../p1-116-closed-profile-scanner-admission/owned-rollback.mjs";
import { REPOSITORY_ROOT } from "./preflight.mjs";

const CONTROLLED_ENV = Object.freeze({
  PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
  LANG: "C",
  LC_ALL: "C",
  TZ: "UTC",
});
const MODULE_BYTES = readFileSync(fileURLToPath(import.meta.url));
const MODULE_IDENTITY = Object.freeze({
  sha256: sha256(MODULE_BYTES),
  byte_length: MODULE_BYTES.length,
});
const NODE_BYTES = readFileSync(realpathSync(process.execPath));
const NODE_IDENTITY = Object.freeze({
  sha256: sha256(NODE_BYTES),
  byte_length: NODE_BYTES.length,
});
const NODE_STAT = lstatSync(realpathSync(process.execPath));
const CURRENT_NODE_FILE_IDENTITY = Object.freeze({
  path: realpathSync(process.execPath),
  sha256: NODE_IDENTITY.sha256,
  byte_length: NODE_IDENTITY.byte_length,
  type: "REGULAR_FILE",
  dev: String(NODE_STAT.dev),
  ino: String(NODE_STAT.ino),
  uid: NODE_STAT.uid,
  gid: NODE_STAT.gid,
  mode: NODE_STAT.mode & 0o7777,
});
const OPERATIONS = Object.freeze({
  REP001_KEEP_INPUT_ORDER: Object.freeze({
    "src/range.mjs": `export function normalizeRange(start, end) {
  return { start, end };
}
`,
  }),
  REP001_ASCENDING_ENDPOINTS: Object.freeze({
    "src/range.mjs": `export function normalizeRange(start, end) {
  if (start <= end) return { start, end };
  return { start: end, end: start };
}
`,
  }),
  REP001_DESCENDING_ENDPOINTS: Object.freeze({
    "src/range.mjs": `export function normalizeRange(start, end) {
  if (start >= end) return { start, end };
  return { start: end, end: start };
}
`,
  }),
  REP002_IGNORE_UNKNOWN_KEYS: Object.freeze({
    "src/config.mjs": `const REQUIRED_KEYS = ["mode"];
const ALLOWED_KEYS = new Set(["mode"]);

export function validateConfig(config) {
  for (const key of REQUIRED_KEYS) {
    if (!(key in config)) throw new Error(\`missing key: \${key}\`);
  }
  return { ok: true, mode: config.mode };
}
`,
  }),
  REP002_REJECT_UNKNOWN_KEYS: Object.freeze({
    "src/config.mjs": `const REQUIRED_KEYS = ["mode"];
const ALLOWED_KEYS = new Set(["mode"]);

export function validateConfig(config) {
  for (const key of REQUIRED_KEYS) {
    if (!(key in config)) throw new Error(\`missing key: \${key}\`);
  }
  for (const key of Object.keys(config)) {
    if (!ALLOWED_KEYS.has(key)) throw new Error(\`unknown key: \${key}\`);
  }
  return { ok: true, mode: config.mode };
}
`,
  }),
  REP002_ACCEPT_ALL_KEYS: Object.freeze({
    "src/config.mjs": `export function validateConfig(config) {
  return { ok: true, mode: config.mode };
}
`,
  }),
  REP003_LEXICAL_PREFIX_ONLY: Object.freeze({
    "src/path.mjs": `import { resolve } from "node:path";

export function resolveUnder(root, candidate) {
  const target = resolve(root, candidate);
  if (!target.startsWith(root)) throw new Error("path escape");
  return target;
}
`,
  }),
  REP003_REJECT_PARENT_ESCAPE: Object.freeze({
    "src/path.mjs": `import { isAbsolute, relative, resolve } from "node:path";

export function resolveUnder(root, candidate) {
  const normalizedRoot = resolve(root);
  const target = resolve(normalizedRoot, candidate);
  const rel = relative(normalizedRoot, target);
  if (rel === ".." || rel.startsWith("../") || isAbsolute(rel)) {
    throw new Error("path escape");
  }
  return target;
}
`,
  }),
  REP003_ALLOW_ABSOLUTE_OVERRIDE: Object.freeze({
    "src/path.mjs": `import { resolve } from "node:path";

export function resolveUnder(root, candidate) {
  return resolve(root, candidate);
}
`,
  }),
  REP004_COERCE_EXIT_TO_ZERO: Object.freeze({
    "src/result.mjs": `export function classifyCommandResult({ exitCode, signal }) {
  if (signal) return { status: "interrupted", signal };
  return { status: "success", exitCode: 0 };
}
`,
  }),
  REP004_PRESERVE_NONZERO_EXIT: Object.freeze({
    "src/result.mjs": `export function classifyCommandResult({ exitCode, signal }) {
  if (signal) return { status: "interrupted", signal };
  if (exitCode !== 0) return { status: "failure", exitCode };
  return { status: "success", exitCode };
}
`,
  }),
  REP004_DROP_EXIT_STATUS: Object.freeze({
    "src/result.mjs": `export function classifyCommandResult({ exitCode, signal }) {
  if (signal) return { status: "interrupted", signal };
  return { status: exitCode === 0 ? "success" : "failure" };
}
`,
  }),
  REP005_FORMAT_NAME_ACROSS_MODULES: Object.freeze({
    "src/profile.mjs": `export function formatDisplayName(profile) {
  return \`\${profile.first.trim()} \${profile.last.trim()}\`;
}
`,
  }),
  REP005_FORMAT_ONLY_CALLER: Object.freeze({
    "src/greeting.mjs": `import { formatDisplayName } from "./profile.mjs";

export function greeting(profile) {
  return \`Hello, \${formatDisplayName({
    first: profile.first.trim(),
    last: profile.last.trim(),
  })}!\`;
}
`,
  }),
  REP005_CHANGE_PUBLIC_SIGNATURE: Object.freeze({
    "src/profile.mjs": `export function formatDisplayName(first, last) {
  return \`\${first.trim()} \${last.trim()}\`;
}
`,
  }),
  REP006_SORT_UNIQUE_VALUES: Object.freeze({
    "src/unique.mjs": `export function uniqueStable(values) {
  return [...new Set(values)].sort();
}
`,
    "src/projects.mjs": `import { uniqueStable } from "./unique.mjs";

export function uniqueProjectNames(names) {
  return uniqueStable(names);
}
`,
    "src/users.mjs": `import { uniqueStable } from "./unique.mjs";

export function uniqueUserNames(names) {
  return uniqueStable(names);
}
`,
  }),
  REP006_DEDUPE_PRESERVES_ORDER: Object.freeze({
    "src/unique.mjs": `export function uniqueStable(values) {
  const seen = new Set();
  return values.filter((value) => {
    if (seen.has(value)) return false;
    seen.add(value);
    return true;
  });
}
`,
    "src/projects.mjs": `import { uniqueStable } from "./unique.mjs";

export function uniqueProjectNames(names) {
  return uniqueStable(names);
}
`,
    "src/users.mjs": `import { uniqueStable } from "./unique.mjs";

export function uniqueUserNames(names) {
  return uniqueStable(names);
}
`,
  }),
  REP006_KEEP_LAST_DUPLICATE: Object.freeze({
    "src/unique.mjs": `export function uniqueStable(values) {
  return values.filter((value, index) => values.lastIndexOf(value) === index);
}
`,
    "src/projects.mjs": `import { uniqueStable } from "./unique.mjs";

export function uniqueProjectNames(names) {
  return uniqueStable(names);
}
`,
    "src/users.mjs": `import { uniqueStable } from "./unique.mjs";

export function uniqueUserNames(names) {
  return uniqueStable(names);
}
`,
  }),
});

function walkRegularFiles(root) {
  const files = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))) {
      const absolute = join(directory, entry.name);
      const stat = lstatSync(absolute);
      assert(!stat.isSymbolicLink(), "LOCAL_SOURCE_INVALID", "local task source contains a symlink");
      if (stat.isDirectory()) visit(absolute);
      else {
        assert(stat.isFile(), "LOCAL_SOURCE_INVALID", "local task source contains a non-regular object");
        const bytes = readFileSync(absolute);
        files.push({
          path: relative(root, absolute).split(sep).join("/"),
          sha256: sha256(bytes),
          byte_length: bytes.length,
          mode: stat.mode & 0o777,
        });
      }
    }
  };
  visit(root);
  return files;
}

function sourceAggregate(inventory) {
  return sha256(canonicalBytes(inventory.map(({ path, sha256: digest, byte_length: length }) => ({
    path,
    sha256: digest,
    byte_length: length,
  }))));
}

function valueIdentity(value) {
  const bytes = canonicalBytes(value);
  return {
    sha256: sha256(bytes),
    byte_length: bytes.length,
  };
}

function localToolRecord(sequence, operationId, status, input, output, executableIdentity) {
  return {
    sequence,
    operation_id: operationId,
    status,
    input_identity: input === null ? null : valueIdentity(input),
    output_identity: output === null ? null : valueIdentity(output),
    executable_identity: executableIdentity === null
      ? null
      : structuredClone(executableIdentity),
  };
}

function validateTaskEnvironmentSnapshot({
  entry,
  taskBinding,
  taskSpecLoaded,
  taskSpec,
}) {
  assert(
    taskBinding?.task_id === entry.task_id
      && canonicalJson(taskBinding.task_spec) === canonicalJson(entry.task_spec),
    "TASK_ENVIRONMENT_BINDING_INVALID",
    "matrix task binding does not match the scheduled task",
  );
  const loaded = readIdentity(taskBinding.environment_snapshot, REPOSITORY_ROOT);
  const snapshot = parseJsonBytes(loaded.bytes, "task EnvironmentSnapshot");
  exactKeys(
    snapshot,
    [
      "schema_version",
      "task_id",
      "snapshot_id_alias",
      "snapshot_id_alias_disclosure",
      "authoritative_identity",
      "task_spec",
      "dataset",
      "repository",
      "source_template",
      "runtime",
      "network_policy",
    ],
    "task EnvironmentSnapshot",
  );
  assert(
    snapshot.schema_version === "p1-117-task-environment-snapshot/v1"
      && snapshot.task_id === entry.task_id
      && snapshot.snapshot_id_alias === taskSpec.environment_snapshot_ref
      && snapshot.snapshot_id_alias_disclosure
        === "ALL_SIX_ACCEPTED_TASKS_SHARE_THIS_REFERENCE_STRING_EXACT_FILE_BYTES_ARE_AUTHORITATIVE"
      && snapshot.authoritative_identity === "EXACT_FILE_SHA256_AND_BYTE_LENGTH"
      && canonicalJson(snapshot.task_spec) === canonicalJson(entry.task_spec)
      && canonicalJson(snapshot.repository) === canonicalJson(taskSpec.repository)
      && canonicalJson(snapshot.dataset.manifest)
        === canonicalJson(taskBinding.dataset_task_binding.dataset_manifest)
      && snapshot.dataset.task_entry_index
        === taskBinding.dataset_task_binding.task_entry_index
      && snapshot.dataset.dataset_version === taskSpec.dataset_version
      && snapshot.dataset.split === taskSpec.evaluation_split,
    "TASK_ENVIRONMENT_SNAPSHOT_INVALID",
    "task EnvironmentSnapshot identity or repository binding drifted",
  );
  assert(
    taskBinding.dataset_task_binding.task_id === entry.task_id
      && taskBinding.dataset_task_binding.base_commit === taskSpec.repository.base_commit
      && taskBinding.dataset_task_binding.tree_hash === taskSpec.repository.tree_hash,
    "DATASET_TASK_BINDING_INVALID",
    "dataset task binding differs from the accepted TaskSpec",
  );
  readIdentity(snapshot.dataset.manifest, REPOSITORY_ROOT);
  const sourceTemplate = join(dirname(taskSpecLoaded.path), "source-template");
  assert(
    realpathSync(sourceTemplate) === sourceTemplate
      && statSync(sourceTemplate).isDirectory()
      && snapshot.source_template.root_path
        === relative(REPOSITORY_ROOT, sourceTemplate).split(sep).join("/")
      && taskBinding.source_template_binding.root_path
        === snapshot.source_template.root_path,
    "SOURCE_TEMPLATE_BINDING_INVALID",
    "source-template root identity drifted",
  );
  const inventory = walkRegularFiles(sourceTemplate).map(
    ({ path, sha256: digest, byte_length: length }) => ({
      path,
      sha256: digest,
      byte_length: length,
    }),
  );
  const inventoryBytes = canonicalBytes(inventory);
  assert(
    canonicalJson(inventory) === canonicalJson(snapshot.source_template.files)
      && snapshot.source_template.manifest.sha256 === sha256(inventoryBytes)
      && snapshot.source_template.manifest.byte_length === inventoryBytes.length
      && snapshot.source_template.manifest.file_count === inventory.length
      && taskBinding.source_template_binding.manifest_sha256 === sha256(inventoryBytes)
      && taskBinding.source_template_binding.manifest_byte_length === inventoryBytes.length
      && taskBinding.source_template_binding.file_count === inventory.length,
    "SOURCE_TEMPLATE_BINDING_INVALID",
    "source-template file manifest drifted",
  );
  assert(
    canonicalJson(snapshot.runtime.node_executable)
        === canonicalJson(CURRENT_NODE_FILE_IDENTITY)
      && snapshot.runtime.node_version === process.version
      && snapshot.runtime.platform === process.platform
      && snapshot.runtime.architecture === process.arch
      && snapshot.runtime.standard_library_only === true
      && snapshot.runtime.locale === "C"
      && snapshot.runtime.timezone === "UTC"
      && snapshot.network_policy.task_local_execution === "DENY_ALL"
      && canonicalJson(snapshot.network_policy.allowed_hosts) === "[]"
      && snapshot.network_policy.provider_transport
        === "OUTSIDE_TASK_SNAPSHOT_GATED_SEPARATELY",
    "TASK_RUNTIME_IDENTITY_INVALID",
    "task runtime or local network policy drifted",
  );
  return {
    environment_snapshot: structuredClone(taskBinding.environment_snapshot),
    dataset_task_binding: structuredClone(taskBinding.dataset_task_binding),
    source_template_binding: structuredClone(taskBinding.source_template_binding),
    source_template_manifest: {
      sha256: sha256(inventoryBytes),
      byte_length: inventoryBytes.length,
      file_count: inventory.length,
    },
  };
}

function validateVerificationCommand(command) {
  assert(
    command !== null
      && typeof command === "object"
      && !Array.isArray(command)
      && typeof command.command_id === "string"
      && ["issue_specific", "regression", "static", "security"].includes(command.role)
      && Array.isArray(command.argv)
      && command.argv.length === 3
      && command.argv[1] === "--test"
      && typeof command.argv[2] === "string"
      && !isAbsolute(command.argv[2])
      && !command.argv[2].split(/[\\/]/).includes("..")
      && command.working_directory === "TASK_REPOSITORY"
      && Number.isInteger(command.timeout_seconds)
      && command.timeout_seconds >= 1
      && command.timeout_seconds <= 60
      && canonicalJson(command.expected_exit_codes) === "[0]"
      && command.non_secret_environment !== null
      && typeof command.non_secret_environment === "object"
      && !Array.isArray(command.non_secret_environment)
      && Object.keys(command.non_secret_environment).length === 0,
    "VERIFICATION_COMMAND_INVALID",
    "TaskSpec verification command exceeds the finite Node-test grammar",
  );
  return command;
}

function writeExistingFileExact(path, bytes) {
  const before = lstatSync(path);
  assert(
    before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && realpathSync(path) === path,
    "TRUSTED_COMPILER_TARGET_INVALID",
    `trusted compiler target is invalid: ${path}`,
  );
  const descriptor = openSync(path, constants.O_WRONLY | (constants.O_NOFOLLOW ?? 0));
  try {
    const opened = fstatSync(descriptor);
    assert(
      opened.isFile() && opened.dev === before.dev && opened.ino === before.ino,
      "TRUSTED_COMPILER_TARGET_INVALID",
      `trusted compiler target identity drifted: ${path}`,
    );
    ftruncateSync(descriptor, 0);
    writeFileSync(descriptor, bytes);
    const after = fstatSync(descriptor);
    assert(
      after.dev === opened.dev && after.ino === opened.ino && after.size === bytes.length,
      "TRUSTED_COMPILER_WRITE_INVALID",
      `trusted compiler did not preserve target identity: ${path}`,
    );
  } finally {
    closeSync(descriptor);
  }
}

function compileFiniteOperation(context, operationId) {
  assert(
    context.entry.finite_operation_ids.includes(operationId)
      && Object.hasOwn(OPERATIONS, operationId),
    "UNKNOWN_OPERATION_ID",
    `operation is outside the frozen finite catalog: ${operationId}`,
  );
  const changedPaths = [];
  for (const [relativePath, text] of Object.entries(OPERATIONS[operationId])) {
    assert(
      /^src\/[A-Za-z0-9._/-]+$/.test(relativePath)
        && !relativePath.split("/").includes(".."),
      "TRUSTED_COMPILER_SCOPE_INVALID",
      `trusted compiler path is invalid: ${relativePath}`,
    );
    const bytes = Buffer.from(text, "utf8");
    const absolute = resolve(context.sourceRoot, relativePath);
    assert(
      absolute.startsWith(`${context.sourceRoot}${sep}`),
      "TRUSTED_COMPILER_SCOPE_INVALID",
      `trusted compiler path escapes source root: ${relativePath}`,
    );
    if (context.originals.has(relativePath)) {
      const before = readFileSync(absolute);
      writeExistingFileExact(absolute, bytes);
      changedPaths.push({
        path: relativePath,
        created: false,
        before_sha256: sha256(before),
        after_sha256: sha256(bytes),
      });
    } else {
      assert(
        relativePath === "src/unique.mjs"
          && operationId.startsWith("REP006_"),
        "TRUSTED_COMPILER_SCOPE_INVALID",
        `trusted compiler may create only the REP006 shared helper: ${relativePath}`,
      );
      context.tree.writeFile(`source/${relativePath}`, bytes, 0o644);
      context.created_paths.add(relativePath);
      changedPaths.push({
        path: relativePath,
        created: true,
        before_sha256: null,
        after_sha256: sha256(bytes),
      });
    }
  }
  return {
    schema_version: "p1-117-trusted-finite-compiler/v1",
    operation_id: operationId,
    free_form_patch_accepted: false,
    source_scope: "OWNED_DISPOSABLE_TASK_SOURCE_ONLY",
    changed_paths: changedPaths,
  };
}

function runVerification(context) {
  return context.taskSpec.verification.required_commands.map((rawCommand) => {
    const command = validateVerificationCommand(rawCommand);
    const result = spawnSync(process.execPath, ["--test", command.argv[2]], {
      cwd: context.sourceRoot,
      env: CONTROLLED_ENV,
      timeout: command.timeout_seconds * 1000,
      encoding: null,
      maxBuffer: 4 * 1024 * 1024,
      shell: false,
    });
    return {
      record: {
        command_id: command.command_id,
        role: command.role,
        argv: [process.execPath, "--test", command.argv[2]],
        exit_status: Number.isInteger(result.status) && result.status >= 0 ? result.status : null,
        signal: result.signal,
        timed_out: result.error?.code === "ETIMEDOUT",
        stdout_sha256: sha256(result.stdout ?? Buffer.alloc(0)),
        stdout_byte_length: result.stdout?.length ?? 0,
        stderr_sha256: sha256(result.stderr ?? Buffer.alloc(0)),
        stderr_byte_length: result.stderr?.length ?? 0,
        passed: result.error === undefined && result.status === 0,
      },
      stdout: result.stdout ?? Buffer.alloc(0),
      stderr: result.stderr ?? Buffer.alloc(0),
    };
  });
}

function restoreAndCleanup(context) {
  for (const [relativePath, originalBytes] of context.originals.entries()) {
    const absolute = join(context.sourceRoot, relativePath);
    if (!readFileSync(absolute).equals(originalBytes)) {
      writeExistingFileExact(absolute, originalBytes);
    }
    assert(
      readFileSync(absolute).equals(originalBytes),
      "ROLLBACK_STATE_IDENTITY_MISMATCH",
      `source rollback failed: ${relativePath}`,
    );
  }
  const expectedPostPaths = new Set([
    ...context.originals.keys(),
    ...context.created_paths,
  ]);
  const postInventory = walkRegularFiles(context.sourceRoot);
  assert(
    postInventory.every((record) => expectedPostPaths.has(record.path)),
    "ROLLBACK_STATE_IDENTITY_MISMATCH",
    "undeclared source path appeared before owned cleanup",
  );
  const rollback = context.tree.cleanup();
  return {
    ...rollback,
    source_pre_sha256: context.pre_source_sha256,
    source_state_restored: true,
    nonowned_paths_touched: 0,
  };
}

export function createLocalRunContext({ entry, taskBinding, runRoot }) {
  const taskSpecLoaded = readIdentity(entry.task_spec, REPOSITORY_ROOT);
  const taskSpec = JSON.parse(taskSpecLoaded.bytes.toString("utf8"));
  assert(taskSpec.task_id === entry.task_id, "TASK_IDENTITY_DRIFT", "TaskSpec task ID differs from schedule");
  const materializationBinding = validateTaskEnvironmentSnapshot({
    entry,
    taskBinding,
    taskSpecLoaded,
    taskSpec,
  });
  const sourceTemplate = join(dirname(taskSpecLoaded.path), "source-template");
  assert(
    realpathSync(sourceTemplate) === sourceTemplate && statSync(sourceTemplate).isDirectory(),
    "LOCAL_SOURCE_INVALID",
    "TaskSpec source template is not a canonical directory",
  );
  const ownedRoot = join(runRoot, "owned-work-root");
  const tree = OwnedTree.create(ownedRoot);
  tree.copyTemplate(sourceTemplate, "source");
  const sourceRoot = join(ownedRoot, "source");
  const inventory = walkRegularFiles(sourceRoot);
  const originals = new Map(inventory.map((record) => [
    record.path,
    readFileSync(join(sourceRoot, record.path)),
  ]));
  const b1Operations = entry.system === "B1"
    ? [
        localToolRecord(
          1,
          "file_listing",
          "EXECUTED_LOCAL_RESULT_WITHHELD_FROM_PROVIDER",
          { source_root_identity: sourceAggregate(inventory) },
          {
            file_count: inventory.length,
            manifest_sha256: sourceAggregate(inventory),
          },
          MODULE_IDENTITY,
        ),
        localToolRecord(
          2,
          "lexical_search",
          "EXECUTED_LOCAL_RESULT_WITHHELD_FROM_PROVIDER",
          {
            query_class: "EXPORTED_DECLARATION_PATTERN",
            query_sha256: sha256(Buffer.from("\\bexport\\b", "utf8")),
            source_root_identity: sourceAggregate(inventory),
          },
          {
            match_count: [...originals.values()].reduce((count, bytes) => (
              count + (bytes.toString("utf8").match(/\bexport\b/g)?.length ?? 0)
            ), 0),
          },
          MODULE_IDENTITY,
        ),
      ]
    : [];
  return {
    entry,
    taskSpec,
    sourceRoot,
    tree,
    originals,
    created_paths: new Set(),
    creation_inventory: inventory,
    pre_source_sha256: sourceAggregate(inventory),
    b1_operations: b1Operations,
    materialization_binding: materializationBinding,
  };
}

export function applyEvaluateAndRollback(context, selectedOperationId) {
  let compiler = null;
  let tests = [];
  let ordinaryFailure = null;
  try {
    if (selectedOperationId !== null) {
      compiler = compileFiniteOperation(context, selectedOperationId);
    }
    tests = runVerification(context);
    if (context.entry.system === "B1") {
      context.b1_operations.push(localToolRecord(
        3,
        "trusted_finite_operation_compiler",
        selectedOperationId === null
          ? "NOT_RUN_PRECONDITION_FAILED"
          : "EXECUTED_LOCAL",
        selectedOperationId === null
          ? null
          : { selected_operation_id: selectedOperationId },
        selectedOperationId === null
          ? null
          : {
              changed_paths: compiler?.changed_paths.map((item) => ({
                path: item.path,
                created: item.created,
                after_sha256: item.after_sha256,
              })) ?? [],
            },
        selectedOperationId === null ? null : MODULE_IDENTITY,
      ));
      context.b1_operations.push(localToolRecord(
        4,
        "verification_ledger",
        "EXECUTED_LOCAL_RESULT_WITHHELD_FROM_PROVIDER",
        {
          commands: context.taskSpec.verification.required_commands.map((command) => ({
            command_id: command.command_id,
            role: command.role,
            argv: command.argv,
          })),
        },
        {
          results: tests.map(({ record }) => ({
            command_id: record.command_id,
            exit_status: record.exit_status,
            passed: record.passed,
            stdout_sha256: record.stdout_sha256,
            stderr_sha256: record.stderr_sha256,
          })),
        },
        NODE_IDENTITY,
      ));
    }
  } catch (error) {
    ordinaryFailure = {
      reason_code: error.code ?? error.reasonCode ?? "TRUSTED_COMPILER_ERROR",
      detail: error.message,
    };
  }
  const rollback = restoreAndCleanup(context);
  const issue = tests.find(({ record }) => record.role !== "regression")?.record ?? null;
  const regression = tests.find(({ record }) => record.role === "regression")?.record ?? null;
  return {
    selected_operation_id: selectedOperationId,
    compiler,
    tests,
    issue_specific: issue,
    regression,
    tests_pass: issue?.passed === true && regression?.passed === true,
    ordinary_failure: ordinaryFailure,
    b1_operations: context.b1_operations,
    rollback,
  };
}

export function abandonLocalRunContext(context) {
  return restoreAndCleanup(context);
}

export const trustedCompilerOperationIds = Object.freeze(Object.keys(OPERATIONS));

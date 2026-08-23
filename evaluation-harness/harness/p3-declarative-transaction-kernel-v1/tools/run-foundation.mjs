import { spawnSync } from 'node:child_process'
import {
  existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync,
} from 'node:fs'
import { dirname, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  canonicalJsonBytes, canonicalStringify, readCanonicalJson, sha256, strictParseJson,
} from '../lib/canonical-json.mjs'
import { runFoundationTests } from '../lib/foundation-tests.mjs'
import { validateMachineSpec } from '../lib/spec-validator.mjs'

const NODE_PATH = '/opt/homebrew/Cellar/node@22/22.23.2/bin/node'
const NODE_VERSION = 'v22.23.2'
const NODE_SHA256 = '0ef5d6908a2c10506f9685b1bd2496b6f7bcb0e23a6ee025c75eb036b997474b'
const SANDBOX_PATH = '/usr/bin/sandbox-exec'
const SANDBOX_SHA256 = '7fc7dcd7782e1abd52b11f6c512bdfb0c09d2502b619c483fdfce554c472352e'
const SANDBOX_PROFILE = '(version 1) (allow default) (deny network*)'
const TASK_ID = 'AIOS-P3-DTK-F1_DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION'
const ROUTE_ID = 'P3_DECLARATIVE_TRANSACTION_KERNEL_CLEAN_ROOM_ROUTE_V1'
const FINDING_IDS = ['P3-ETSK-F1-C1-P0-001', 'P3-ETSK-F1-C1-P1-002', 'P3-ETSK-F1-C1-P1-003']

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const repoRoot = resolve(root, '../../..')
const harnessRelative = 'evaluation-harness/harness/p3-declarative-transaction-kernel-v1'
const reportsRelative = 'evaluation-harness/reports/p3-declarative-transaction-kernel-v1'
const reportsDirectory = join(repoRoot, reportsRelative)

class RunnerError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`)
    this.name = 'RunnerError'
    this.code = code
  }
}

function fail(code, message) {
  throw new RunnerError(code, message)
}

function repoPath(path) {
  const result = relative(repoRoot, path).split(sep).join('/')
  if (result.startsWith('../') || result === '..') fail('PATH_OUTSIDE_REPOSITORY', path)
  return result
}

function fileIdentity(path, role, bytes = readFileSync(path)) {
  const stat = statSync(path)
  if (!stat.isFile()) fail('INVENTORY_NOT_REGULAR_FILE', path)
  return {
    path: repoPath(path),
    role,
    byte_length: bytes.length,
    sha256: sha256(bytes),
  }
}

function generatedIdentity(name, role, bytes) {
  return {
    path: `${reportsRelative}/${name}`,
    role,
    byte_length: bytes.length,
    sha256: sha256(bytes),
  }
}

function verifyBinary(path, expectedSha256, label) {
  const stat = statSync(path)
  if (!stat.isFile()) fail('TOOLCHAIN_NOT_REGULAR_FILE', `${label} is not a regular file`)
  const bytes = readFileSync(path)
  const actualSha256 = sha256(bytes)
  if (actualSha256 !== expectedSha256) fail('TOOLCHAIN_SHA256_MISMATCH', `${label} SHA-256 drift`)
  return { path, byte_length: bytes.length, sha256: actualSha256 }
}

function validateSchemaDeclaration(schema) {
  const expected = {
    additional_properties: false,
    canonical_json_plus_one_lf_required: true,
    duplicate_keys_rejected_before_schema_validation: true,
    required: ['schema_version', 'spec_id', 'operator_algebra', 'state_ids', 'state_schema', 'initial_state', 'event_schemas', 'cleanup_rules', 'invariants', 'result_schema', 'aggregate_semantics', 'transitions'],
    schema_version: 'p3-dtk-machine-spec-schema/v1',
    semantic_validator: 'lib/spec-validator.mjs#validateMachineSpec',
    target_schema_version: 'p3-dtk-machine-spec/v1',
    type: 'object',
  }
  if (canonicalStringify(schema) !== canonicalStringify(expected)) fail('MACHINE_SCHEMA_DECLARATION_DRIFT', 'machine schema declaration is not exact')
}

function runNetworkDenyPreflight() {
  const path = join(root, 'tools/network-deny-preflight.mjs')
  const child = spawnSync(NODE_PATH, [path], {
    encoding: null,
    env: { LANG: 'C', LC_ALL: 'C', TZ: 'UTC' },
    maxBuffer: 1024 * 1024,
  })
  if (child.error) fail('NETWORK_PREFLIGHT_SPAWN_ERROR', child.error.message)
  if (child.status !== 0) fail('NETWORK_SANDBOX_NOT_ENFORCED', `network deny preflight exited ${child.status}: ${Buffer.from(child.stderr ?? '').toString('utf8')}`)
  const stdout = Buffer.from(child.stdout)
  const result = strictParseJson(stdout, 'network deny preflight stdout')
  if (!canonicalJsonBytes(result).equals(stdout)) fail('NETWORK_PREFLIGHT_NON_CANONICAL', 'network deny preflight output is not canonical')
  if (result.verdict !== 'PASS' || result.sandbox_profile !== SANDBOX_PROFILE || result.probes.length !== 3) {
    fail('NETWORK_SANDBOX_NOT_ENFORCED', 'network deny preflight did not prove all three socket operations denied')
  }
  if (!result.probes.every(probe => probe.outcome === 'DENIED' && ['EPERM', 'EACCES'].includes(probe.error_code))) {
    fail('NETWORK_SANDBOX_NOT_ENFORCED', 'at least one socket capability remained available')
  }
  return result
}

function buildOutputs() {
  if (process.execPath !== NODE_PATH) fail('NODE_PATH_MISMATCH', `runner must execute through ${NODE_PATH}`)
  if (process.version !== NODE_VERSION) fail('NODE_VERSION_MISMATCH', `runner requires ${NODE_VERSION}`)
  const nodeIdentity = verifyBinary(NODE_PATH, NODE_SHA256, 'Node')
  const sandboxIdentity = verifyBinary(SANDBOX_PATH, SANDBOX_SHA256, 'sandbox-exec')
  const networkPreflight = runNetworkDenyPreflight()

  const schema = readCanonicalJson(join(root, 'spec/machine-spec.schema.json'))
  const spec = readCanonicalJson(join(root, 'spec/machine-spec.json'))
  const scenarios = readCanonicalJson(join(root, 'fixtures/scenarios.json'))
  const mutants = readCanonicalJson(join(root, 'fixtures/mutants.json'))
  validateSchemaDeclaration(schema.value)
  const specSummary = validateMachineSpec(spec.value)
  const tests = runFoundationTests({
    spec: spec.value,
    specSha256: spec.sha256,
    scenarios: scenarios.value,
    mutants: mutants.value,
    interpreterSourcePath: join(root, 'lib/interpreter.mjs'),
    verifierSourcePath: join(root, 'lib/replay-verifier.mjs'),
  })

  const interpreterBytes = readFileSync(join(root, 'lib/interpreter.mjs'))
  const verifierBytes = readFileSync(join(root, 'lib/replay-verifier.mjs'))
  if (sha256(interpreterBytes) === sha256(verifierBytes)) fail('INTERPRETER_VERIFIER_NOT_DISTINCT', 'interpreter and verifier bytes are identical')

  const oracle = {
    schema_version: 'p3-dtk-foundation-oracle/v1',
    task_id: TASK_ID,
    route_id: ROUTE_ID,
    frozen_finding_ids: FINDING_IDS,
    oracle_role: 'MACHINE_SPEC_IS_SOLE_DOMAIN_SEMANTIC_AUTHORITY_FOR_FOUNDATION_AND_PRODUCT',
    machine_spec: {
      path: `${harnessRelative}/spec/machine-spec.json`,
      byte_length: spec.bytes.length,
      sha256: spec.sha256,
      schema_version: spec.value.schema_version,
      spec_id: spec.value.spec_id,
    },
    schema_declaration: {
      path: `${harnessRelative}/spec/machine-spec.schema.json`,
      byte_length: schema.bytes.length,
      sha256: schema.sha256,
    },
    closed_operator_algebra_version: spec.value.operator_algebra.version,
    interpreter_role: 'GENERIC_EXECUTOR_NO_DOMAIN_BRANCHES_OUTSIDE_MACHINE_SPEC',
    verifier_role: 'INDEPENDENT_FULL_REPLAY_RECOMPUTATION_NO_INTERPRETER_IMPORT_OR_CALL',
    product_runtime_requirement: 'LOAD_VALIDATE_AND_EXECUTE_EXACT_HASH_BOUND_MACHINE_SPEC_WITHOUT_PARALLEL_HARDCODED_SEMANTICS',
  }
  const oracleBytes = canonicalJsonBytes(oracle)

  const replay = {
    schema_version: 'p3-dtk-deterministic-replay/v1',
    task_id: TASK_ID,
    spec_id: spec.value.spec_id,
    spec_sha256: spec.sha256,
    scenario_set_sha256: scenarios.sha256,
    scenario_count: tests.traces_a.length,
    traces: tests.traces_a,
    independent_full_replay_verifications: tests.verifications_a,
    verdict: 'PASS',
  }
  const replayABytes = canonicalJsonBytes(replay)
  const replayBBytes = canonicalJsonBytes({ ...replay, traces: tests.traces_b, independent_full_replay_verifications: tests.verifications_b })
  if (!replayABytes.equals(replayBBytes)) fail('DETERMINISTIC_REPLAY_BYTES_DIFFER', 'replay A and B are not byte-identical')

  const mutationReport = {
    schema_version: 'p3-dtk-foundation-mutation-report/v1',
    task_id: TASK_ID,
    spec_sha256: spec.sha256,
    mutant_set_sha256: mutants.sha256,
    mutants_total: tests.mutation_summary.mutants_total,
    mutants_killed: tests.mutation_summary.mutants_killed,
    false_accepts: tests.mutation_summary.false_accepts,
    results: tests.mutation_summary.results,
    verdict: tests.mutation_summary.verdict,
  }
  const mutationBytes = canonicalJsonBytes(mutationReport)

  const selfTestReport = {
    schema_version: 'p3-dtk-foundation-self-test-report/v1',
    task_id: TASK_ID,
    spec_sha256: spec.sha256,
    test_summary: tests.test_summary,
    verdict: tests.test_summary.verdict,
  }
  const selfTestBytes = canonicalJsonBytes(selfTestReport)

  const foundationReport = {
    schema_version: 'p3-dtk-foundation-report/v1',
    task_id: TASK_ID,
    route_id: ROUTE_ID,
    frozen_finding_ids: FINDING_IDS,
    candidate_status: 'SELF_VALIDATION_PASS_AWAITING_FRESH_INDEPENDENT_REVIEW',
    machine_spec: {
      sha256: spec.sha256,
      ...specSummary,
    },
    positive_scenarios: { passed: tests.traces_a.length, total: 10 },
    falsification_mutants: {
      killed: tests.mutation_summary.mutants_killed,
      total: tests.mutation_summary.mutants_total,
      false_accepts: tests.mutation_summary.false_accepts,
    },
    deterministic_replay: {
      independent_runs: 2,
      byte_equal: replayABytes.equals(replayBBytes),
      byte_length: replayABytes.length,
      sha256: sha256(replayABytes),
    },
    interpreter_verifier_independence: {
      interpreter_sha256: sha256(interpreterBytes),
      verifier_sha256: sha256(verifierBytes),
      distinct_bytes: true,
      verifier_imports_or_calls_interpreter: false,
      verifier_recomputes_transition_state_result_aggregate_and_terminal_verdict: true,
    },
    toolchain: {
      node: nodeIdentity,
      sandbox_exec: sandboxIdentity,
      sandbox_profile: SANDBOX_PROFILE,
      dependencies: 'NODE_STANDARD_LIBRARY_AND_TASK_LOCAL_MODULES_ONLY',
      network_deny_preflight: networkPreflight,
    },
    external_effects: {
      network: false,
      docker: false,
      provider: false,
      secret: false,
      credential: false,
      remote: false,
      production: false,
      public: false,
      p4_entry: false,
    },
    product_source_changes_allowed: false,
    fresh_independent_review_required_before_task_gate: true,
    verdict: 'PASS',
  }
  const foundationBytes = canonicalJsonBytes(foundationReport)

  const outputBytes = new Map([
    ['ORACLE_DECLARATION.json', oracleBytes],
    ['DETERMINISTIC_REPLAY_A.json', replayABytes],
    ['DETERMINISTIC_REPLAY_B.json', replayBBytes],
    ['MUTATION_REPORT.json', mutationBytes],
    ['SELF_TEST_REPORT.json', selfTestBytes],
    ['FOUNDATION_REPORT.json', foundationBytes],
  ])

  const sourceInventory = [
    ['README.md', 'FOUNDATION_DOCUMENTATION'],
    ['package.json', 'NO_DEPENDENCY_RUNTIME_DECLARATION'],
    ['spec/machine-spec.schema.json', 'MACHINE_SPEC_SCHEMA_DECLARATION'],
    ['spec/machine-spec.json', 'SOLE_DOMAIN_SEMANTIC_ORACLE'],
    ['fixtures/scenarios.json', 'EXACT_TEN_POSITIVE_SCENARIOS'],
    ['fixtures/mutants.json', 'EXACT_THIRTEEN_FALSIFICATION_MUTANTS'],
    ['lib/canonical-json.mjs', 'STRICT_CANONICAL_JSON_AND_CONTENT_ADDRESSING'],
    ['lib/spec-validator.mjs', 'CLOSED_MACHINE_SPEC_VALIDATOR'],
    ['lib/interpreter.mjs', 'GENERIC_DECLARATIVE_INTERPRETER'],
    ['lib/replay-verifier.mjs', 'INDEPENDENT_FULL_REPLAY_VERIFIER'],
    ['lib/mutants.mjs', 'MUTANT_MATERIALIZER'],
    ['lib/foundation-tests.mjs', 'FOUNDATION_TEST_ORCHESTRATION'],
    ['tools/canonicalize-json.mjs', 'CANONICAL_JSON_UTILITY'],
    ['tools/network-deny-preflight.mjs', 'SOCKET_CAPABILITY_DENY_PREFLIGHT'],
    ['tools/self-test.mjs', 'SELF_TEST_ENTRYPOINT'],
    ['tools/run-foundation.mjs', 'FOUNDATION_REPORT_ENTRYPOINT'],
  ].map(([path, role]) => fileIdentity(join(root, path), role))
  sourceInventory.push(fileIdentity(join(repoRoot, 'docs/aios/tasks/P3-DTK-F1_DECLARATIVE_TRANSACTION_SEMANTICS_FOUNDATION.yaml'), 'ACTIVE_TASK_CONTRACT'))
  const outputRoles = {
    'ORACLE_DECLARATION.json': 'HASH_BOUND_ORACLE_DECLARATION',
    'DETERMINISTIC_REPLAY_A.json': 'DETERMINISTIC_REPLAY_COPY_A',
    'DETERMINISTIC_REPLAY_B.json': 'DETERMINISTIC_REPLAY_COPY_B',
    'MUTATION_REPORT.json': 'THIRTEEN_MUTANT_KILL_REPORT',
    'SELF_TEST_REPORT.json': 'FAIL_CLOSED_SELF_TEST_REPORT',
    'FOUNDATION_REPORT.json': 'FOUNDATION_CANDIDATE_SELF_VALIDATION_REPORT',
  }
  const generatedInventory = [...outputBytes].map(([name, bytes]) => generatedIdentity(name, outputRoles[name], bytes))
  const inventory = [...sourceInventory, ...generatedInventory].sort((left, right) => left.path.localeCompare(right.path, 'en'))
  const manifest = {
    schema_version: 'p3-dtk-foundation-manifest/v1',
    task_id: TASK_ID,
    route_id: ROUTE_ID,
    frozen_finding_ids: FINDING_IDS,
    machine_spec_sha256: spec.sha256,
    oracle_declaration_sha256: sha256(oracleBytes),
    scenario_set_sha256: scenarios.sha256,
    mutant_set_sha256: mutants.sha256,
    deterministic_replay_sha256: sha256(replayABytes),
    deterministic_replay_byte_equal: replayABytes.equals(replayBBytes),
    toolchain: {
      node: nodeIdentity,
      sandbox_exec: sandboxIdentity,
      sandbox_profile: SANDBOX_PROFILE,
      dependencies: 'NODE_STANDARD_LIBRARY_AND_TASK_LOCAL_MODULES_ONLY',
    },
    closed_inventory: inventory,
    closed_inventory_count: inventory.length,
    manifest_self_hash_excluded_to_avoid_recursive_identity: true,
    specification_oracle_scenarios_mutants_reports_and_toolchain_bound: true,
    verdict: 'PASS',
  }
  outputBytes.set('FOUNDATION_MANIFEST.json', canonicalJsonBytes(manifest))
  return { outputBytes, specSha256: spec.sha256, foundationReport, manifest }
}

function writeOutputs(outputBytes) {
  if (existsSync(reportsDirectory)) fail('REPORT_DIRECTORY_ALREADY_EXISTS', reportsRelative)
  mkdirSync(dirname(reportsDirectory), { recursive: true })
  const stage = `${reportsDirectory}.stage-${process.pid}`
  if (existsSync(stage)) fail('REPORT_STAGE_ALREADY_EXISTS', stage)
  mkdirSync(stage)
  try {
    for (const [name, bytes] of outputBytes) writeFileSync(join(stage, name), bytes, { flag: 'wx', mode: 0o644 })
    renameSync(stage, reportsDirectory)
  } catch (error) {
    if (existsSync(stage)) rmSync(stage, { recursive: true, force: false })
    throw error
  }
}

function verifyInstalled(outputBytes) {
  if (!existsSync(reportsDirectory)) fail('REPORT_DIRECTORY_MISSING', reportsRelative)
  const expectedNames = [...outputBytes.keys()].sort()
  const actualNames = readdirSync(reportsDirectory).sort()
  if (canonicalStringify(actualNames) !== canonicalStringify(expectedNames)) fail('REPORT_FILE_SET_DRIFT', 'installed report file set is not exact')
  for (const [name, bytes] of outputBytes) {
    if (!readFileSync(join(reportsDirectory, name)).equals(bytes)) fail('REPORT_BYTES_DRIFT', `${name} differs from deterministic reconstruction`)
  }
}

const modes = new Set(['--check', '--write', '--verify-installed'])
const mode = process.argv[2] ?? '--check'
if (!modes.has(mode) || process.argv.length !== 3) fail('ARGUMENT_INVALID', 'use exactly one of --check, --write, or --verify-installed')
const built = buildOutputs()
if (mode === '--write') writeOutputs(built.outputBytes)
if (mode === '--verify-installed') verifyInstalled(built.outputBytes)
process.stdout.write(canonicalJsonBytes({
  schema_version: 'p3-dtk-foundation-runner-result/v1',
  mode,
  task_id: TASK_ID,
  spec_sha256: built.specSha256,
  generated_report_count: built.outputBytes.size,
  manifest_sha256: sha256(built.outputBytes.get('FOUNDATION_MANIFEST.json')),
  candidate_status: built.foundationReport.candidate_status,
  verdict: 'PASS',
}))

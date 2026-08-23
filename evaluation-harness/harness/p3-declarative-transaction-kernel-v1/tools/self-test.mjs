import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { canonicalJsonBytes, readCanonicalJson } from '../lib/canonical-json.mjs'
import { runFoundationTests } from '../lib/foundation-tests.mjs'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const spec = readCanonicalJson(join(root, 'spec/machine-spec.json'))
const scenarios = readCanonicalJson(join(root, 'fixtures/scenarios.json'))
const mutants = readCanonicalJson(join(root, 'fixtures/mutants.json'))
const result = runFoundationTests({
  spec: spec.value,
  specSha256: spec.sha256,
  scenarios: scenarios.value,
  mutants: mutants.value,
  interpreterSourcePath: join(root, 'lib/interpreter.mjs'),
  verifierSourcePath: join(root, 'lib/replay-verifier.mjs'),
})
process.stdout.write(canonicalJsonBytes({
  schema_version: 'p3-dtk-foundation-self-test/v1',
  spec_sha256: spec.sha256,
  scenario_count: result.traces_a.length,
  mutation_summary: result.mutation_summary,
  test_summary: result.test_summary,
  verdict: 'PASS',
}))

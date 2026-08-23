import { readFileSync } from 'node:fs'
import { canonicalDigest, canonicalJsonBytes, canonicalStringify, deepClone, strictParseJson } from './canonical-json.mjs'
import { executeEvent, executeScenarioMatrix } from './interpreter.mjs'
import { materializeMutant, validateMutantSet } from './mutants.mjs'
import { verifyTrace, verifyTraceMatrix } from './replay-verifier.mjs'
import { validateMachineSpec, validateState } from './spec-validator.mjs'

export class FoundationTestError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`)
    this.name = 'FoundationTestError'
    this.code = code
  }
}

export const EXACT_SCENARIO_IDS = [
  'S01_STEP_ZERO_DIFFERENT_WORKFLOW_COMPETITION',
  'S02_LOSER_FAILS_BEFORE_EFFECT',
  'S03_FIRST_CHECKPOINT_BINDS_WORKFLOW',
  'S04_SAME_WORKFLOW_CHECKPOINT_RESUME',
  'S05_PRECHECKPOINT_CLEAN_FAILED_TERMINAL_RELEASES',
  'S06_CLEANUP_UNCONFIRMED_DOES_NOT_RELEASE',
  'S07_POSTCHECKPOINT_FAILED_TERMINAL_DOES_NOT_RELEASE',
  'S08_POSTCHECKPOINT_ORPHAN_TERMINATION_DOES_NOT_RELEASE',
  'S09_TERMINAL_A_REPLAY_PRESERVES_LATER_RESERVATION_B',
  'S10_EXACTLY_ONE_TERMINAL_TRACE_PER_INVOCATION',
]

function fail(code, message) {
  throw new FoundationTestError(code, message)
}

function errorCode(error) {
  return typeof error?.code === 'string' ? error.code : 'UNCLASSIFIED_ERROR'
}

function expectCode(action, expected, testId) {
  try {
    action()
  } catch (error) {
    if (errorCode(error) !== expected) fail('SELF_TEST_WRONG_REJECTION', `${testId} expected ${expected} but got ${errorCode(error)}`)
    return
  }
  fail('SELF_TEST_FALSE_ACCEPT', `${testId} expected ${expected} but input was accepted`)
}

function assert(condition, testId, message) {
  if (!condition) fail('SELF_TEST_ASSERTION', `${testId}: ${message}`)
}

function closedObject(value, keys, label) {
  assert(value !== null && typeof value === 'object' && !Array.isArray(value), 'SCENARIO_SCHEMA_CLOSED', `${label} must be an object`)
  assert(canonicalStringify(Object.keys(value).sort()) === canonicalStringify([...keys].sort()), 'SCENARIO_SCHEMA_CLOSED', `${label} fields drift`)
}

export function validateScenarioSet(scenarioSet) {
  closedObject(scenarioSet, ['schema_version', 'scenarios'], 'scenario set')
  assert(scenarioSet.schema_version === 'p3-dtk-foundation-scenarios/v1', 'SCENARIO_SCHEMA_VERSION', 'scenario set version drift')
  assert(Array.isArray(scenarioSet.scenarios), 'SCENARIO_SCHEMA_CLOSED', 'scenarios must be an array')
  const ids = scenarioSet.scenarios.map(scenario => scenario.id)
  assert(canonicalStringify(ids) === canonicalStringify(EXACT_SCENARIO_IDS), 'SCENARIO_SET_EXACT', 'scenario ids or order drift')
  for (const scenario of scenarioSet.scenarios) {
    closedObject(scenario, ['id', 'purpose', 'steps', 'expected_final'], `scenario ${scenario.id}`)
    assert(typeof scenario.purpose === 'string' && scenario.purpose.length > 0, 'SCENARIO_SCHEMA_CLOSED', `${scenario.id} purpose invalid`)
    assert(Array.isArray(scenario.steps) && scenario.steps.length > 0, 'SCENARIO_SCHEMA_CLOSED', `${scenario.id} steps invalid`)
    assert(scenario.expected_final !== null && typeof scenario.expected_final === 'object' && !Array.isArray(scenario.expected_final), 'SCENARIO_SCHEMA_CLOSED', `${scenario.id}.expected_final must be an object`)
    for (const [index, step] of scenario.steps.entries()) {
      closedObject(step, ['event', 'expect'], `${scenario.id}.steps[${index}]`)
      const allowedExpect = new Set(['kind', 'result', 'code', 'state_unchanged'])
      const unknownExpect = Object.keys(step.expect).filter(key => !allowedExpect.has(key))
      assert(unknownExpect.length === 0, 'SCENARIO_SCHEMA_CLOSED', `${scenario.id}.steps[${index}].expect has unknown fields`)
      assert(['RESULT', 'REJECTION'].includes(step.expect.kind), 'SCENARIO_SCHEMA_CLOSED', `${scenario.id}.steps[${index}].expect kind invalid`)
      if (step.expect.kind === 'RESULT') assert(step.expect.result !== null && typeof step.expect.result === 'object' && !Array.isArray(step.expect.result), 'SCENARIO_SCHEMA_CLOSED', `${scenario.id}.steps[${index}].expect result invalid`)
      if (step.expect.kind === 'REJECTION') assert(typeof step.expect.code === 'string' && step.expect.code.length > 0, 'SCENARIO_SCHEMA_CLOSED', `${scenario.id}.steps[${index}].expect code invalid`)
    }
  }
  return { count: ids.length, ids }
}

function passing(testId) {
  return { test_id: testId, verdict: 'PASS' }
}

function transitionFor(spec, stateId, eventType) {
  const transition = spec.transitions.find(item => item.from === stateId && item.event === eventType)
  if (!transition) fail('SELF_TEST_FIXTURE_MISSING', `transition ${stateId}/${eventType} missing`)
  return transition
}

function testSpecFailures(spec, firstEvent, tests) {
  const unknownField = deepClone(spec)
  unknownField.unexpected = true
  expectCode(() => validateMachineSpec(unknownField), 'UNKNOWN_FIELD', 'SPEC_UNKNOWN_FIELD_REJECTED')
  tests.push(passing('SPEC_UNKNOWN_FIELD_REJECTED'))

  const unknownOperator = deepClone(spec)
  unknownOperator.transitions[0].guard = { op: 'unknown_expression_operator' }
  expectCode(() => validateMachineSpec(unknownOperator), 'UNKNOWN_OPERATOR', 'SPEC_UNKNOWN_OPERATOR_REJECTED')
  tests.push(passing('SPEC_UNKNOWN_OPERATOR_REJECTED'))

  const unknownEffect = deepClone(spec)
  const effectTransition = unknownEffect.transitions.find(item => item.effects.length > 0)
  effectTransition.effects[0].op = 'unknown_effect_operator'
  expectCode(() => validateMachineSpec(unknownEffect), 'UNKNOWN_EFFECT_OPERATOR', 'SPEC_UNKNOWN_EFFECT_OPERATOR_REJECTED')
  tests.push(passing('SPEC_UNKNOWN_EFFECT_OPERATOR_REJECTED'))

  const ambiguous = deepClone(spec)
  const duplicate = deepClone(ambiguous.transitions[0])
  duplicate.id = 'MUTANT_DUPLICATE_GUARD_TRANSITION'
  ambiguous.transitions.push(duplicate)
  expectCode(() => validateMachineSpec(ambiguous), 'AMBIGUOUS_TRANSITION', 'SPEC_AMBIGUOUS_TRANSITION_REJECTED')
  tests.push(passing('SPEC_AMBIGUOUS_TRANSITION_REJECTED'))

  const multiple = deepClone(spec)
  const reserve = deepClone(transitionFor(multiple, 'OPEN', 'RESERVE'))
  reserve.id = 'MUTANT_SECOND_TRUE_RESERVE_TRANSITION'
  reserve.guard = { op: 'eq', args: [{ op: 'literal', value: 1 }, { op: 'literal', value: 1 }] }
  multiple.transitions.push(reserve)
  validateMachineSpec(multiple)
  expectCode(() => executeEvent(multiple, deepClone(multiple.initial_state), deepClone(firstEvent)), 'MULTIPLE_MATCHING_TRANSITION', 'RUNTIME_MULTIPLE_TRANSITION_REJECTED')
  tests.push(passing('RUNTIME_MULTIPLE_TRANSITION_REJECTED'))

  const missingBinding = deepClone(spec)
  transitionFor(missingBinding, 'OPEN', 'RESERVE').result.code = { op: 'get', source: 'state', path: '/undeclared_result_binding' }
  expectCode(() => validateMachineSpec(missingBinding), 'MISSING_BINDING', 'SPEC_MISSING_BINDING_REJECTED_BEFORE_EFFECT')
  tests.push(passing('SPEC_MISSING_BINDING_REJECTED_BEFORE_EFFECT'))

  const cleanupContradiction = deepClone(spec)
  cleanupContradiction.cleanup_rules[0].forbid_when = deepClone(cleanupContradiction.cleanup_rules[0].allow_when)
  expectCode(() => validateMachineSpec(cleanupContradiction), 'CONTRADICTORY_CLEANUP_RULE', 'SPEC_CLEANUP_CONTRADICTION_REJECTED')
  tests.push(passing('SPEC_CLEANUP_CONTRADICTION_REJECTED'))

  const unboundCleanup = deepClone(spec)
  const release = unboundCleanup.transitions.flatMap(item => item.effects).find(effect => effect.op === 'release_frontier')
  release.rule_id = 'UNBOUND_CLEANUP_RULE'
  expectCode(() => validateMachineSpec(unboundCleanup), 'MISSING_BINDING', 'SPEC_UNBOUND_CLEANUP_RULE_REJECTED')
  tests.push(passing('SPEC_UNBOUND_CLEANUP_RULE_REJECTED'))

  const unboundResult = deepClone(spec)
  unboundResult.transitions[0].result.undeclared_result = { op: 'literal', value: true }
  expectCode(() => validateMachineSpec(unboundResult), 'UNBOUND_RESULT_SEMANTIC', 'SPEC_UNBOUND_RESULT_REJECTED')
  tests.push(passing('SPEC_UNBOUND_RESULT_REJECTED'))

  const missingResult = deepClone(spec)
  delete missingResult.transitions[0].result.code
  expectCode(() => validateMachineSpec(missingResult), 'MISSING_RESULT', 'SPEC_MISSING_RESULT_REJECTED')
  tests.push(passing('SPEC_MISSING_RESULT_REJECTED'))

  const unknownState = deepClone(spec)
  unknownState.initial_state.state_id = 'UNKNOWN_STATE_MUTANT'
  expectCode(() => validateMachineSpec(unknownState), 'UNKNOWN_STATE', 'SPEC_UNKNOWN_STATE_REJECTED')
  tests.push(passing('SPEC_UNKNOWN_STATE_REJECTED'))

  const unknownEvent = deepClone(firstEvent)
  unknownEvent.type = 'UNKNOWN_EVENT_MUTANT'
  expectCode(() => executeEvent(spec, deepClone(spec.initial_state), unknownEvent), 'UNKNOWN_EVENT', 'RUNTIME_UNKNOWN_EVENT_REJECTED')
  tests.push(passing('RUNTIME_UNKNOWN_EVENT_REJECTED'))

  const eventUnknownField = deepClone(firstEvent)
  eventUnknownField.undeclared = true
  expectCode(() => executeEvent(spec, deepClone(spec.initial_state), eventUnknownField), 'UNKNOWN_FIELD', 'RUNTIME_UNKNOWN_EVENT_FIELD_REJECTED')
  tests.push(passing('RUNTIME_UNKNOWN_EVENT_FIELD_REJECTED'))
}

function testVerifierIndependence(spec, specSha256, traces, interpreterSource, verifierSource, tests) {
  const importPattern = /(?:from\s+|import\s*\()['"][^'"]*interpreter(?:\.mjs)?['"]/
  assert(!importPattern.test(verifierSource), 'VERIFIER_NO_INTERPRETER_IMPORT', 'verifier imports the interpreter')
  assert(!/\bexecuteScenario(?:Matrix)?\s*\(/.test(verifierSource), 'VERIFIER_NO_INTERPRETER_CALL', 'verifier calls interpreter scenario execution')
  assert(!/\bexecuteEvent\s*\(/.test(verifierSource), 'VERIFIER_NO_INTERPRETER_CALL', 'verifier calls interpreter event execution')
  tests.push(passing('VERIFIER_NO_INTERPRETER_IMPORT_OR_CALL'))

  const domainBranchPattern = /\b(?:reservation|checkpoint|workflow|terminal|invocation)\b/i
  assert(!domainBranchPattern.test(interpreterSource), 'GENERIC_INTERPRETER_NO_DOMAIN_BRANCHES', 'interpreter contains a domain-name branch or binding')
  assert(!domainBranchPattern.test(verifierSource), 'GENERIC_VERIFIER_NO_DOMAIN_BRANCHES', 'verifier contains a domain-name branch or binding')
  tests.push(passing('INTERPRETER_AND_VERIFIER_CONTAIN_ONLY_GENERIC_OPERATOR_IMPLEMENTATIONS'))

  const forgedTransition = deepClone(traces[0])
  forgedTransition.steps[0].transition_id = 'FORGED_TRANSITION_ID'
  expectCode(() => verifyTrace(spec, specSha256, forgedTransition), 'TRANSITION_ID_MISMATCH', 'VERIFIER_RECOMPUTES_TRANSITION_ID')
  tests.push(passing('VERIFIER_RECOMPUTES_TRANSITION_ID'))

  const forgedPostState = deepClone(traces[0])
  forgedPostState.steps[0].post_state.reservation_epoch += 1
  expectCode(() => verifyTrace(spec, specSha256, forgedPostState), 'POST_STATE_MISMATCH', 'VERIFIER_RECOMPUTES_POST_STATE')
  tests.push(passing('VERIFIER_RECOMPUTES_POST_STATE'))

  const forgedAggregate = deepClone(traces[0])
  forgedAggregate.aggregate.input_events += 1
  expectCode(() => verifyTrace(spec, specSha256, forgedAggregate), 'AGGREGATE_TRACE_MISMATCH', 'VERIFIER_RECOMPUTES_AGGREGATE')
  tests.push(passing('VERIFIER_RECOMPUTES_AGGREGATE'))

  const replayTrace = traces.find(trace => trace.scenario_id === 'S09_TERMINAL_A_REPLAY_PRESERVES_LATER_RESERVATION_B')
  const forgedVerdict = deepClone(replayTrace)
  forgedVerdict.steps.at(-1).result.verdict = 'FAILURE'
  expectCode(() => verifyTrace(spec, specSha256, forgedVerdict), 'RESULT_MISMATCH', 'VERIFIER_RECOMPUTES_TERMINAL_VERDICT')
  tests.push(passing('VERIFIER_RECOMPUTES_TERMINAL_VERDICT'))
}

export function runFoundationTests({ spec, specSha256, scenarios, mutants, interpreterSourcePath, verifierSourcePath }) {
  const tests = []
  validateMachineSpec(spec)
  tests.push(passing('MACHINE_SPEC_VALID'))
  const scenarioInfo = validateScenarioSet(scenarios)
  for (const scenario of scenarios.scenarios) validateState(spec, scenario.expected_final, `${scenario.id}.expected_final`)
  tests.push(passing('EXACT_TEN_SCENARIOS_VALID'))
  const mutantInfo = validateMutantSet(mutants, scenarioInfo.ids)
  tests.push(passing('EXACT_THIRTEEN_MUTANTS_VALID'))

  expectCode(() => strictParseJson('{"duplicate":1,"duplicate":2}\n', 'duplicate-key self-test'), 'DUPLICATE_KEY', 'CANONICAL_JSON_DUPLICATE_KEY_REJECTED')
  tests.push(passing('CANONICAL_JSON_DUPLICATE_KEY_REJECTED'))

  const tracesA = executeScenarioMatrix(spec, specSha256, scenarios)
  const tracesB = executeScenarioMatrix(deepClone(spec), specSha256, deepClone(scenarios))
  const replayBytesA = canonicalJsonBytes(tracesA)
  const replayBytesB = canonicalJsonBytes(tracesB)
  assert(replayBytesA.equals(replayBytesB), 'TWO_REPLAY_BYTE_EQUALITY', 'independent replay bytes differ')
  tests.push(passing('TWO_REPLAY_BYTE_EQUALITY'))

  const verificationsA = verifyTraceMatrix(spec, specSha256, tracesA, scenarioInfo.ids)
  const verificationsB = verifyTraceMatrix(deepClone(spec), specSha256, tracesB, scenarioInfo.ids)
  assert(canonicalJsonBytes(verificationsA).equals(canonicalJsonBytes(verificationsB)), 'TWO_VERIFICATION_BYTE_EQUALITY', 'verification bytes differ')
  tests.push(passing('TWO_VERIFICATION_BYTE_EQUALITY'))

  const mutationResults = []
  for (const descriptor of mutants.mutants) {
    const mutation = materializeMutant(spec, tracesA, descriptor)
    let observedCode = 'FALSE_ACCEPT'
    try {
      verifyTrace(mutation.spec, mutation.verification_spec_sha256, mutation.trace)
    } catch (error) {
      observedCode = errorCode(error)
    }
    if (observedCode !== mutation.expected_rejection_code) {
      fail('MUTANT_WRONG_OUTCOME', `${descriptor.id} expected ${mutation.expected_rejection_code} but got ${observedCode}`)
    }
    mutationResults.push({
      mutant_id: descriptor.id,
      source_scenario_id: descriptor.source_scenario_id,
      expected_rejection_code: mutation.expected_rejection_code,
      observed_rejection_code: observedCode,
      killed: true,
    })
  }
  tests.push(passing('THIRTEEN_OF_THIRTEEN_MUTANTS_KILLED_ZERO_FALSE_ACCEPTS'))

  testSpecFailures(spec, scenarios.scenarios[0].steps[0].event, tests)
  const changedInvariant = deepClone(spec)
  changedInvariant.invariants[0].predicate = { op: 'literal', value: false }
  validateMachineSpec(changedInvariant)
  expectCode(() => verifyTrace(changedInvariant, specSha256, tracesA[0]), 'SPEC_DIGEST_MISMATCH', 'FROZEN_SPEC_DIGEST_REJECTS_SEMANTIC_MUTATION')
  tests.push(passing('FROZEN_SPEC_DIGEST_REJECTS_SEMANTIC_MUTATION'))
  expectCode(() => executeEvent(changedInvariant, deepClone(changedInvariant.initial_state), deepClone(scenarios.scenarios[0].steps[0].event)), 'INVARIANT_VIOLATION', 'DECLARED_INVARIANT_CHANGES_EXECUTION')
  tests.push(passing('DECLARED_INVARIANT_CHANGES_EXECUTION'))

  const changedCleanup = deepClone(spec)
  changedCleanup.cleanup_rules.find(rule => rule.id === 'FAILED_TERMINAL_RELEASE_REQUIRES_ACCEPTED_CLEANUP_AND_ZERO_CHECKPOINTS').allow_when = { op: 'literal', value: false }
  validateMachineSpec(changedCleanup)
  const reserveExecution = executeEvent(changedCleanup, deepClone(changedCleanup.initial_state), deepClone(scenarios.scenarios[4].steps[0].event))
  expectCode(() => executeEvent(changedCleanup, reserveExecution.state, deepClone(scenarios.scenarios[4].steps[1].event)), 'CLEANUP_RULE_DENIED', 'DECLARED_CLEANUP_ALGEBRA_CHANGES_EXECUTION')
  tests.push(passing('DECLARED_CLEANUP_ALGEBRA_CHANGES_EXECUTION'))

  const authoritativeReserve = executeEvent(spec, deepClone(spec.initial_state), deepClone(scenarios.scenarios[4].steps[0].event))
  const unaccepted = deepClone(scenarios.scenarios[4].steps[1].event)
  unaccepted.terminal_accepted = false
  const authoritativeStateDigest = canonicalDigest(authoritativeReserve.state)
  expectCode(() => executeEvent(spec, authoritativeReserve.state, unaccepted), 'ILLEGAL_TRANSITION', 'UNACCEPTED_TERMINAL_FAILS_CLOSED')
  assert(canonicalDigest(authoritativeReserve.state) === authoritativeStateDigest, 'UNACCEPTED_TERMINAL_FAILS_CLOSED', 'unaccepted terminal mutated state')
  tests.push(passing('UNACCEPTED_TERMINAL_FAILS_CLOSED_BEFORE_EFFECT'))

  const changedAggregate = deepClone(spec)
  changedAggregate.aggregate_semantics.bindings.accepted_results = { op: 'literal', value: 999 }
  validateMachineSpec(changedAggregate)
  const changedAggregateTrace = executeScenarioMatrix(changedAggregate, canonicalDigest(changedAggregate), { schema_version: scenarios.schema_version, scenarios: [deepClone(scenarios.scenarios[0])] })[0]
  assert(changedAggregateTrace.aggregate.accepted_results === 999, 'DECLARED_AGGREGATE_CHANGES_EXECUTION', 'aggregate binding mutation was ignored')
  tests.push(passing('DECLARED_AGGREGATE_SEMANTICS_CHANGES_EXECUTION'))

  const verdicts = ['SUCCESS', 'FAILURE', 'REJECTED']
  for (const scenarioId of [
    'S05_PRECHECKPOINT_CLEAN_FAILED_TERMINAL_RELEASES',
    'S08_POSTCHECKPOINT_ORPHAN_TERMINATION_DOES_NOT_RELEASE',
    'S09_TERMINAL_A_REPLAY_PRESERVES_LATER_RESERVATION_B',
  ]) {
    const source = tracesA.find(trace => trace.scenario_id === scenarioId)
    const replayStepIndex = source.steps.findIndex(step => step.event.type === 'REPLAY_TERMINAL')
    const actualVerdict = source.steps[replayStepIndex].event.claimed_verdict
    for (const forged of verdicts.filter(value => value !== actualVerdict)) {
      const forgedTrace = deepClone(source)
      forgedTrace.steps[replayStepIndex].event.claimed_verdict = forged
      expectCode(() => verifyTrace(spec, specSha256, forgedTrace), 'ILLEGAL_TRANSITION', `REPLAY_${actualVerdict}_CANNOT_BE_FORGED_AS_${forged}`)
    }
  }
  tests.push(passing('REPLAY_SUCCESS_FAILURE_REJECTED_CROSS_PRODUCT_FORGERIES_FAIL_CLOSED'))

  const interpreterSource = readFileSync(interpreterSourcePath, 'utf8')
  const verifierSource = readFileSync(verifierSourcePath, 'utf8')
  testVerifierIndependence(spec, specSha256, tracesA, interpreterSource, verifierSource, tests)

  return {
    test_summary: {
      total: tests.length,
      passed: tests.length,
      failed: 0,
      verdict: 'PASS',
      tests,
    },
    traces_a: tracesA,
    traces_b: tracesB,
    verifications_a: verificationsA,
    verifications_b: verificationsB,
    mutation_summary: {
      mutants_total: mutantInfo.count,
      mutants_killed: mutationResults.length,
      false_accepts: 0,
      results: mutationResults,
      verdict: 'PASS',
    },
  }
}

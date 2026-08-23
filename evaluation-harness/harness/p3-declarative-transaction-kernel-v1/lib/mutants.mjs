import { canonicalDigest, deepClone } from './canonical-json.mjs'

export class MutantDefinitionError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`)
    this.name = 'MutantDefinitionError'
    this.code = code
  }
}

const EXACT_MUTANT_IDS = [
  'UNKNOWN_STATE',
  'UNKNOWN_EVENT',
  'ILLEGAL_TRANSITION',
  'MISSING_RESULT',
  'FORGED_RESULT',
  'AGGREGATE_TRACE_MISMATCH',
  'TERMINAL_REPLAY_CROSS_INVOCATION_MUTATION',
  'RESERVATION_TAMPER',
  'HISTORY_TAMPER',
  'POSTCHECKPOINT_FAILURE_FRONTIER_RELEASE',
  'FORGED_TERMINAL_REPLAY_VERDICT',
  'DECLARED_CLEANUP_ALGEBRA_IGNORED',
  'DECLARED_INVARIANT_SEMANTIC_MUTATION',
]

const EXPECTED_REJECTION_CODES = {
  UNKNOWN_STATE: 'UNKNOWN_STATE',
  UNKNOWN_EVENT: 'UNKNOWN_EVENT',
  ILLEGAL_TRANSITION: 'ILLEGAL_TRANSITION',
  MISSING_RESULT: 'MISSING_RESULT',
  FORGED_RESULT: 'RESULT_MISMATCH',
  AGGREGATE_TRACE_MISMATCH: 'AGGREGATE_TRACE_MISMATCH',
  TERMINAL_REPLAY_CROSS_INVOCATION_MUTATION: 'POST_STATE_MISMATCH',
  RESERVATION_TAMPER: 'POST_STATE_MISMATCH',
  HISTORY_TAMPER: 'POST_STATE_MISMATCH',
  POSTCHECKPOINT_FAILURE_FRONTIER_RELEASE: 'POST_STATE_MISMATCH',
  FORGED_TERMINAL_REPLAY_VERDICT: 'ILLEGAL_TRANSITION',
  DECLARED_CLEANUP_ALGEBRA_IGNORED: 'CLEANUP_RULE_DENIED',
  DECLARED_INVARIANT_SEMANTIC_MUTATION: 'INVARIANT_VIOLATION',
}

function fail(code, message) {
  throw new MutantDefinitionError(code, message)
}

export function validateMutantSet(mutantSet, scenarioIds) {
  if (mutantSet === null || typeof mutantSet !== 'object' || Array.isArray(mutantSet)) fail('MUTANT_SET_INVALID', 'mutant set must be an object')
  if (mutantSet.schema_version !== 'p3-dtk-foundation-mutants/v1') fail('MUTANT_SET_VERSION_UNKNOWN', 'mutant set schema version drift')
  if (!Array.isArray(mutantSet.mutants)) fail('MUTANT_SET_INVALID', 'mutants must be an array')
  const actualIds = mutantSet.mutants.map(mutant => mutant.id)
  if (JSON.stringify(actualIds) !== JSON.stringify(EXACT_MUTANT_IDS)) fail('MUTANT_SET_DRIFT', 'mutant ids or order do not match the frozen exact set')
  if (new Set(actualIds).size !== actualIds.length) fail('MUTANT_ID_DUPLICATE', 'mutant ids are not unique')
  const knownScenarios = new Set(scenarioIds)
  for (const mutant of mutantSet.mutants) {
    const keys = Object.keys(mutant).sort()
    if (JSON.stringify(keys) !== JSON.stringify(['id', 'mutation', 'source_scenario_id'])) fail('MUTANT_FIELD_DRIFT', `${mutant.id} fields are not closed`)
    if (mutant.id !== mutant.mutation) fail('MUTANT_ID_DRIFT', `${mutant.id} mutation selector drift`)
    if (!knownScenarios.has(mutant.source_scenario_id)) fail('MUTANT_SOURCE_UNKNOWN', `${mutant.id} source scenario is unknown`)
  }
  return { count: mutantSet.mutants.length, ids: [...actualIds] }
}

function getTrace(traces, scenarioId) {
  const trace = traces.find(candidate => candidate.scenario_id === scenarioId)
  if (!trace) fail('MUTANT_SOURCE_UNKNOWN', `trace ${scenarioId} is missing`)
  return deepClone(trace)
}

function findStep(trace, predicate, mutantId) {
  const step = trace.steps.find(predicate)
  if (!step) fail('MUTANT_TARGET_MISSING', `${mutantId} target step is missing`)
  return step
}

function forceReleasedFrontier(state) {
  state.state_id = 'OPEN'
  state.bindings.active_task_id = null
  state.bindings.active_invocation_id = null
  state.bindings.bound_workflow_id = null
  state.checkpoint_count = 0
}

export function materializeMutant(spec, traces, descriptor) {
  const mutantSpec = deepClone(spec)
  const mutantTrace = getTrace(traces, descriptor.source_scenario_id)
  const id = descriptor.mutation

  if (id === 'UNKNOWN_STATE') {
    mutantTrace.steps.at(-1).post_state.state_id = 'UNKNOWN_STATE_MUTANT'
  } else if (id === 'UNKNOWN_EVENT') {
    mutantTrace.steps[0].event.type = 'UNKNOWN_EVENT_MUTANT'
  } else if (id === 'ILLEGAL_TRANSITION') {
    mutantTrace.steps[0].event = deepClone(mutantTrace.steps[1].event)
  } else if (id === 'MISSING_RESULT') {
    delete mutantTrace.steps.at(-1).result
  } else if (id === 'FORGED_RESULT') {
    const step = findStep(mutantTrace, item => item.result?.frontier_released === true, id)
    step.result.frontier_released = false
  } else if (id === 'AGGREGATE_TRACE_MISMATCH') {
    mutantTrace.aggregate.terminal_trace_count += 1
  } else if (id === 'TERMINAL_REPLAY_CROSS_INVOCATION_MUTATION') {
    const step = findStep(mutantTrace, item => item.event?.type === 'REPLAY_TERMINAL', id)
    step.post_state.bindings.active_invocation_id = step.event.invocation_id
  } else if (id === 'RESERVATION_TAMPER') {
    const step = findStep(mutantTrace, item => item.event?.type === 'RESERVE' && item.result?.accepted === true, id)
    step.post_state.bindings.active_invocation_id = 'inv-tampered-reservation'
  } else if (id === 'HISTORY_TAMPER') {
    const step = findStep(mutantTrace, item => item.event?.type === 'CHECKPOINT_ACCEPTED', id)
    step.post_state.checkpoint_count += 40
  } else if (id === 'POSTCHECKPOINT_FAILURE_FRONTIER_RELEASE') {
    const step = findStep(mutantTrace, item => item.event?.type === 'TERMINAL_FAILED', id)
    forceReleasedFrontier(step.post_state)
  } else if (id === 'FORGED_TERMINAL_REPLAY_VERDICT') {
    const step = findStep(mutantTrace, item => item.event?.type === 'REPLAY_TERMINAL', id)
    step.event.claimed_verdict = step.event.claimed_verdict === 'SUCCESS' ? 'FAILURE' : 'SUCCESS'
  } else if (id === 'DECLARED_CLEANUP_ALGEBRA_IGNORED') {
    const rule = mutantSpec.cleanup_rules.find(item => item.id === 'FAILED_TERMINAL_RELEASE_REQUIRES_ACCEPTED_CLEANUP_AND_ZERO_CHECKPOINTS')
    if (!rule) fail('MUTANT_TARGET_MISSING', `${id} cleanup rule is missing`)
    rule.allow_when = { op: 'literal', value: false }
    mutantTrace.spec_sha256 = canonicalDigest(mutantSpec)
  } else if (id === 'DECLARED_INVARIANT_SEMANTIC_MUTATION') {
    mutantSpec.invariants[0].predicate = { op: 'literal', value: false }
    mutantTrace.spec_sha256 = canonicalDigest(mutantSpec)
  } else {
    fail('MUTANT_UNKNOWN', `mutation ${id} is not implemented`)
  }

  return {
    mutant_id: descriptor.id,
    source_scenario_id: descriptor.source_scenario_id,
    expected_rejection_code: EXPECTED_REJECTION_CODES[id],
    verification_spec_sha256: id === 'DECLARED_CLEANUP_ALGEBRA_IGNORED' || id === 'DECLARED_INVARIANT_SEMANTIC_MUTATION' ? canonicalDigest(mutantSpec) : canonicalDigest(spec),
    spec: mutantSpec,
    trace: mutantTrace,
  }
}

export function exactMutantIds() {
  return [...EXACT_MUTANT_IDS]
}

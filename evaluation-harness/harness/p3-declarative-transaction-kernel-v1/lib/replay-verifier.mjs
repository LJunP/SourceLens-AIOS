import { canonicalDigest, canonicalStringify, deepClone } from './canonical-json.mjs'
import { validateAggregate, validateEvent, validateMachineSpec, validateResult, validateState } from './spec-validator.mjs'

export class ReplayVerificationError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`)
    this.name = 'ReplayVerificationError'
    this.code = code
  }
}

function reject(code, message) {
  throw new ReplayVerificationError(code, message)
}

function codeOf(error) {
  return typeof error?.code === 'string' ? error.code : 'UNCLASSIFIED_ERROR'
}

function pointerSegments(pointer) {
  return pointer.slice(1).split('/').map(part => part.replaceAll('~1', '/').replaceAll('~0', '~'))
}

function resolvePointer(document, pointer) {
  let cursor = document
  for (const part of pointerSegments(pointer)) {
    if (cursor === null || typeof cursor !== 'object' || !Object.hasOwn(cursor, part)) return undefined
    cursor = cursor[part]
  }
  return cursor
}

function assignPointer(document, pointer, value) {
  const parts = pointerSegments(pointer)
  const leaf = parts.pop()
  let cursor = document
  for (const part of parts) {
    if (cursor === null || typeof cursor !== 'object' || !Object.hasOwn(cursor, part)) reject('MISSING_BINDING', `write path ${pointer} has no parent binding`)
    cursor = cursor[part]
  }
  if (cursor === null || typeof cursor !== 'object' || !Object.hasOwn(cursor, leaf)) reject('MISSING_BINDING', `write path ${pointer} is not declared`)
  cursor[leaf] = deepClone(value)
}

function defined(value, label) {
  if (value === undefined) reject('MISSING_BINDING', `${label} resolved to undefined`)
  return value
}

function boolean(value, label) {
  if (typeof value !== 'boolean') reject('PREDICATE_TYPE', `${label} did not resolve to boolean`)
  return value
}

function collection(value, label) {
  if (!Array.isArray(value)) reject('COLLECTION_TYPE', `${label} is not an array`)
  return value
}

// This evaluator and the state reducer below are implemented wholly inside the
// verifier. No execution implementation or execution-produced semantic verdict is used.
function solve(term, runtime) {
  const child = (input, label = term.op) => defined(solve(input, runtime), label)
  if (term.op === 'literal') return deepClone(term.value)
  if (term.op === 'get') return resolvePointer(runtime[term.source], term.path)
  if (term.op === 'add') return term.args.map(arg => Number(child(arg, 'add arg'))).reduce((left, right) => left + right, 0)
  if (term.op === 'digest') return canonicalDigest(child(term.arg, 'digest arg'))
  if (term.op === 'lookup') {
    const table = child(term.object, 'lookup object')
    const key = child(term.key, 'lookup key')
    if (table === null || typeof table !== 'object' || Array.isArray(table)) reject('LOOKUP_TYPE', 'lookup object is not a map')
    return Object.hasOwn(table, key) ? table[key] : undefined
  }
  if (term.op === 'all') return term.args.every(arg => boolean(solve(arg, runtime), 'all arg'))
  if (term.op === 'any') return term.args.some(arg => boolean(solve(arg, runtime), 'any arg'))
  if (term.op === 'not') return !boolean(solve(term.arg, runtime), 'not arg')
  if (term.op === 'eq') return canonicalStringify(child(term.args[0], 'eq left')) === canonicalStringify(child(term.args[1], 'eq right'))
  if (term.op === 'neq') return canonicalStringify(child(term.args[0], 'neq left')) !== canonicalStringify(child(term.args[1], 'neq right'))
  if (term.op === 'gt') return child(term.args[0], 'gt left') > child(term.args[1], 'gt right')
  if (term.op === 'gte') return child(term.args[0], 'gte left') >= child(term.args[1], 'gte right')
  if (term.op === 'exists') return solve(term.arg, runtime) !== undefined
  if (term.op === 'is_null') return child(term.arg, 'is_null arg') === null
  if (term.op === 'length') {
    const value = child(term.arg, 'length arg')
    if (!Array.isArray(value) && typeof value !== 'string') reject('LENGTH_TYPE', 'length arg is not an array or string')
    return value.length
  }
  if (term.op === 'keys') {
    const value = child(term.arg, 'keys arg')
    if (value === null || typeof value !== 'object' || Array.isArray(value)) reject('KEYS_TYPE', 'keys arg is not a map')
    return Object.keys(value).sort()
  }
  if (term.op === 'unique_by') {
    const values = collection(child(term.collection, 'unique_by collection'), 'unique_by collection')
    const seen = new Set()
    for (const [index, entry] of values.entries()) {
      if (entry === null || typeof entry !== 'object' || !Object.hasOwn(entry, term.key)) reject('MISSING_BINDING', `unique_by entry ${index} has no ${term.key}`)
      const identity = canonicalStringify(entry[term.key])
      if (seen.has(identity)) return false
      seen.add(identity)
    }
    return true
  }
  if (term.op === 'map_by') {
    const values = collection(child(term.collection, 'map_by collection'), 'map_by collection')
    const result = {}
    for (const [index, entry] of values.entries()) {
      if (entry === null || typeof entry !== 'object' || !Object.hasOwn(entry, term.key)) reject('MISSING_BINDING', `map_by entry ${index} has no ${term.key}`)
      const identity = String(entry[term.key])
      if (Object.hasOwn(result, identity)) reject('MAP_BY_KEY_CONFLICT', `map_by key ${identity} is duplicated`)
      result[identity] = deepClone(entry)
    }
    return result
  }
  if (term.op === 'implies') {
    const premise = boolean(solve(term.args[0], runtime), 'implies premise')
    return !premise || boolean(solve(term.args[1], runtime), 'implies conclusion')
  }
  if (term.op === 'count_where') {
    const values = collection(child(term.collection, 'count_where collection'), 'count_where collection')
    const expected = child(term.value, 'count_where value')
    return values.filter(entry => {
      const actual = resolvePointer(entry, term.path)
      return actual !== undefined && canonicalStringify(actual) === canonicalStringify(expected)
    }).length
  }
  if (term.op === 'count_exists') {
    const values = collection(child(term.collection, 'count_exists collection'), 'count_exists collection')
    return values.filter(entry => resolvePointer(entry, term.path) !== undefined).length
  }
  reject('UNKNOWN_OPERATOR', `verifier has no operator ${term.op}`)
}

function runtime(state, event = {}, trace = { steps: [] }) {
  return { state, event, trace }
}

function enforceInvariants(spec, state, event, phase) {
  for (const invariant of spec.invariants) {
    if (!boolean(solve(invariant.predicate, runtime(state, event)), `invariant ${invariant.id}`)) reject('INVARIANT_VIOLATION', `${invariant.id} failed at ${phase}`)
  }
}

function enact(spec, effect, nextState, event) {
  const active = runtime(nextState, event)
  if (effect.op === 'set') {
    assignPointer(nextState, effect.path, solve(effect.value, active))
    return
  }
  if (effect.op === 'increment') {
    const before = resolvePointer(nextState, effect.path)
    const amount = solve(effect.amount, active)
    if (!Number.isInteger(before) || !Number.isInteger(amount)) reject('INCREMENT_TYPE', 'increment requires integers')
    assignPointer(nextState, effect.path, before + amount)
    return
  }
  if (effect.op === 'append_unique') {
    const list = resolvePointer(nextState, effect.path)
    if (!Array.isArray(list)) reject('APPEND_TYPE', `${effect.path} is not an array`)
    const value = solve(effect.value, active)
    if (value === null || typeof value !== 'object' || !Object.hasOwn(value, effect.key)) reject('MISSING_BINDING', `append value lacks ${effect.key}`)
    if (list.some(entry => canonicalStringify(entry[effect.key]) === canonicalStringify(value[effect.key]))) reject('APPEND_UNIQUE_KEY_CONFLICT', `${effect.path} already contains ${effect.key}`)
    list.push(deepClone(value))
    return
  }
  if (effect.op === 'put_once') {
    const table = resolvePointer(nextState, effect.path)
    if (table === null || typeof table !== 'object' || Array.isArray(table)) reject('PUT_ONCE_TYPE', `${effect.path} is not a map`)
    const key = String(solve(effect.key, active))
    if (Object.hasOwn(table, key)) reject('PUT_ONCE_KEY_CONFLICT', `${effect.path}/${key} already exists`)
    table[key] = deepClone(solve(effect.value, active))
    return
  }
  if (effect.op === 'release_frontier') {
    const rule = spec.cleanup_rules.find(item => item.id === effect.rule_id)
    if (!rule) reject('MISSING_BINDING', `cleanup rule ${effect.rule_id} missing`)
    const allowed = boolean(solve(rule.allow_when, active), `cleanup rule ${rule.id} allow_when`)
    const forbidden = boolean(solve(rule.forbid_when, active), `cleanup rule ${rule.id} forbid_when`)
    if (!allowed || forbidden) reject('CLEANUP_RULE_DENIED', `cleanup rule ${rule.id} did not authorize assignments`)
    for (const assignment of effect.assignments) assignPointer(nextState, assignment.path, solve(assignment.value, active))
    return
  }
  if (effect.op === 'noop') return
  reject('UNKNOWN_EFFECT_OPERATOR', `verifier has no effect ${effect.op}`)
}

function independentlyRecomputeEvent(spec, state, event) {
  validateState(spec, state, 'pre_state')
  validateEvent(spec, event)
  enforceInvariants(spec, state, event, 'PRE')
  const candidates = spec.transitions.filter(item => item.from === state.state_id && item.event === event.type && boolean(solve(item.guard, runtime(state, event)), `guard ${item.id}`))
  if (candidates.length === 0) reject('ILLEGAL_TRANSITION', `${state.state_id} + ${event.type} has no matching transition`)
  if (candidates.length > 1) reject('MULTIPLE_MATCHING_TRANSITION', `${state.state_id} + ${event.type} matched ${candidates.map(item => item.id).join(',')}`)
  const selected = candidates[0]
  const nextState = deepClone(state)
  nextState.state_id = selected.to
  for (const effect of selected.effects) enact(spec, effect, nextState, event)
  validateState(spec, nextState, 'post_state')
  enforceInvariants(spec, nextState, event, 'POST')
  const recomputedResult = Object.fromEntries(Object.entries(selected.result).map(([field, term]) => [
    field, defined(solve(term, runtime(nextState, event)), `result ${field}`),
  ]))
  validateResult(spec, recomputedResult)
  return { transition_id: selected.id, effects_applied: selected.effects.map(effect => effect.op), result: recomputedResult, state: nextState }
}

function exact(actual, expected, code, message) {
  if (canonicalStringify(actual) !== canonicalStringify(expected)) reject(code, message)
}

function assertClosed(record, allowed, required, label) {
  if (record === null || typeof record !== 'object' || Array.isArray(record)) reject('TRACE_SCHEMA_INVALID', `${label} must be an object`)
  const unknown = Object.keys(record).filter(key => !allowed.includes(key))
  const missing = required.filter(key => !Object.hasOwn(record, key))
  if (unknown.length > 0) reject('UNKNOWN_FIELD', `${label} has unknown fields: ${unknown.join(',')}`)
  if (missing.length > 0) reject('MISSING_FIELD', `${label} is missing fields: ${missing.join(',')}`)
}

function inspectRecordedState(spec, state, label) {
  try {
    validateState(spec, state, label)
  } catch (error) {
    reject(codeOf(error), error.message.replace(/^[A-Z0-9_]+: /, ''))
  }
}

function verifyRecordedSuccess(spec, recorded, ordinal, event, beforeState, recomputed) {
  const keys = ['ordinal', 'event', 'pre_state_sha256', 'transition_id', 'effects_applied', 'result', 'post_state', 'post_state_sha256']
  if (!Object.hasOwn(recorded, 'result')) reject('MISSING_RESULT', `step ${ordinal} has no recorded result`)
  assertClosed(recorded, keys, keys, `steps[${ordinal - 1}]`)
  if (recorded.ordinal !== ordinal) reject('TRACE_ORDINAL_MISMATCH', `step ${ordinal} ordinal drift`)
  exact(recorded.event, event, 'EVENT_RECORD_MISMATCH', `step ${ordinal} event changed while verifying`)
  const preDigest = canonicalDigest(beforeState)
  if (recorded.pre_state_sha256 !== preDigest) reject('PRE_STATE_DIGEST_MISMATCH', `step ${ordinal} pre-state digest drift`)
  if (recorded.transition_id !== recomputed.transition_id) reject('TRANSITION_ID_MISMATCH', `step ${ordinal} transition id is not recomputed value`)
  exact(recorded.effects_applied, recomputed.effects_applied, 'EFFECT_LIST_MISMATCH', `step ${ordinal} effect list is not recomputed value`)
  exact(recorded.result, recomputed.result, 'RESULT_MISMATCH', `step ${ordinal} result is not recomputed value`)
  inspectRecordedState(spec, recorded.post_state, `steps[${ordinal - 1}].post_state`)
  exact(recorded.post_state, recomputed.state, 'POST_STATE_MISMATCH', `step ${ordinal} post-state is not recomputed value`)
  const postDigest = canonicalDigest(recomputed.state)
  if (recorded.post_state_sha256 !== postDigest) reject('POST_STATE_DIGEST_MISMATCH', `step ${ordinal} post-state digest drift`)
  return {
    ordinal,
    event: deepClone(event),
    pre_state_sha256: preDigest,
    transition_id: recomputed.transition_id,
    effects_applied: deepClone(recomputed.effects_applied),
    result: deepClone(recomputed.result),
    post_state: deepClone(recomputed.state),
    post_state_sha256: postDigest,
  }
}

function verifyRecordedRejection(spec, recorded, ordinal, event, beforeState, recomputeError) {
  const keys = ['ordinal', 'event', 'pre_state_sha256', 'rejection', 'post_state', 'post_state_sha256']
  assertClosed(recorded, keys, keys, `steps[${ordinal - 1}]`)
  if (recorded.ordinal !== ordinal) reject('TRACE_ORDINAL_MISMATCH', `step ${ordinal} ordinal drift`)
  exact(recorded.event, event, 'EVENT_RECORD_MISMATCH', `step ${ordinal} event changed while verifying`)
  const stateDigest = canonicalDigest(beforeState)
  if (recorded.pre_state_sha256 !== stateDigest) reject('PRE_STATE_DIGEST_MISMATCH', `step ${ordinal} pre-state digest drift`)
  assertClosed(recorded.rejection, ['code', 'message'], ['code', 'message'], `steps[${ordinal - 1}].rejection`)
  if (recorded.rejection.code !== codeOf(recomputeError)) reject('REJECTION_CODE_MISMATCH', `step ${ordinal} rejection was not independently reproduced`)
  inspectRecordedState(spec, recorded.post_state, `steps[${ordinal - 1}].post_state`)
  exact(recorded.post_state, beforeState, 'REJECTION_STATE_MUTATION', `step ${ordinal} rejection record mutated state`)
  if (recorded.post_state_sha256 !== stateDigest) reject('POST_STATE_DIGEST_MISMATCH', `step ${ordinal} rejected post-state digest drift`)
  if (recorded.rejection.message !== recomputeError.message) reject('REJECTION_MESSAGE_MISMATCH', `step ${ordinal} rejection message drift`)
  return {
    ordinal,
    event: deepClone(event),
    pre_state_sha256: stateDigest,
    rejection: { code: codeOf(recomputeError), message: recomputeError.message },
    post_state: deepClone(beforeState),
    post_state_sha256: stateDigest,
  }
}

function deriveAggregate(spec, state, verifiedSteps) {
  const active = runtime(state, {}, { steps: verifiedSteps })
  const aggregate = Object.fromEntries(Object.entries(spec.aggregate_semantics.bindings).map(([field, term]) => [
    field, defined(solve(term, active), `aggregate ${field}`),
  ]))
  validateAggregate(spec, aggregate)
  return aggregate
}

export function verifyTrace(spec, expectedSpecSha256, trace) {
  validateMachineSpec(spec)
  if (canonicalDigest(spec) !== expectedSpecSha256) reject('SPEC_DIGEST_MISMATCH', 'machine specification does not match the frozen digest')
  const keys = ['schema_version', 'spec_id', 'spec_sha256', 'scenario_id', 'steps', 'final_state', 'aggregate']
  assertClosed(trace, keys, keys, 'trace')
  if (trace.schema_version !== 'p3-dtk-interpreter-trace/v1') reject('TRACE_SCHEMA_VERSION_UNKNOWN', 'trace schema version drift')
  if (trace.spec_id !== spec.spec_id) reject('SPEC_ID_MISMATCH', 'trace spec id drift')
  if (trace.spec_sha256 !== expectedSpecSha256) reject('SPEC_DIGEST_MISMATCH', 'trace does not bind the frozen specification digest')
  if (typeof trace.scenario_id !== 'string' || trace.scenario_id.length === 0) reject('TRACE_SCENARIO_ID_INVALID', 'trace scenario id is missing')
  if (!Array.isArray(trace.steps)) reject('TRACE_SCHEMA_INVALID', 'trace.steps must be an array')

  let state = deepClone(spec.initial_state)
  const verifiedSteps = []
  for (const [index, recorded] of trace.steps.entries()) {
    const ordinal = index + 1
    if (recorded === null || typeof recorded !== 'object' || Array.isArray(recorded)) reject('TRACE_SCHEMA_INVALID', `step ${ordinal} must be an object`)
    if (!Object.hasOwn(recorded, 'event')) reject('MISSING_FIELD', `step ${ordinal} has no event`)
    const event = deepClone(recorded.event)
    let recomputed
    let recomputeError
    try {
      recomputed = independentlyRecomputeEvent(spec, state, event)
    } catch (error) {
      recomputeError = error
    }
    if (recomputeError) {
      if (!Object.hasOwn(recorded, 'rejection')) reject(codeOf(recomputeError), `step ${ordinal} was not recorded as independently rejected`)
      verifiedSteps.push(verifyRecordedRejection(spec, recorded, ordinal, event, state, recomputeError))
    } else {
      if (Object.hasOwn(recorded, 'rejection')) reject('FORGED_REJECTION', `step ${ordinal} records a rejection for a valid transition`)
      verifiedSteps.push(verifyRecordedSuccess(spec, recorded, ordinal, event, state, recomputed))
      state = recomputed.state
    }
  }

  inspectRecordedState(spec, trace.final_state, 'trace.final_state')
  exact(trace.final_state, state, 'FINAL_STATE_MISMATCH', 'trace final state is not independently replayed state')
  const aggregate = deriveAggregate(spec, state, verifiedSteps)
  exact(trace.aggregate, aggregate, 'AGGREGATE_TRACE_MISMATCH', 'trace aggregate is not independently recomputed from declared aggregate semantics')
  return {
    schema_version: 'p3-dtk-replay-verification/v1',
    scenario_id: trace.scenario_id,
    spec_sha256: expectedSpecSha256,
    verified_step_count: verifiedSteps.length,
    recomputed_final_state_sha256: canonicalDigest(state),
    recomputed_aggregate_sha256: canonicalDigest(aggregate),
    verdict: 'PASS',
  }
}

export function verifyTraceMatrix(spec, expectedSpecSha256, traces, expectedScenarioIds) {
  if (!Array.isArray(traces)) reject('TRACE_MATRIX_INVALID', 'trace matrix must be an array')
  if (!Array.isArray(expectedScenarioIds)) reject('TRACE_MATRIX_INVALID', 'expected scenario ids must be an array')
  const actualIds = traces.map(trace => trace.scenario_id)
  if (new Set(actualIds).size !== actualIds.length) reject('TRACE_SCENARIO_DUPLICATE', 'trace matrix contains duplicate scenario ids')
  exact(actualIds, expectedScenarioIds, 'TRACE_SCENARIO_SET_MISMATCH', 'trace matrix does not match the frozen scenario order')
  return traces.map(trace => verifyTrace(spec, expectedSpecSha256, trace))
}

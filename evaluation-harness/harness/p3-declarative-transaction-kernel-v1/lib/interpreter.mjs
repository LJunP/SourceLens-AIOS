import { canonicalDigest, canonicalStringify, deepClone } from './canonical-json.mjs'
import { validateAggregate, validateEvent, validateMachineSpec, validateResult, validateState } from './spec-validator.mjs'

export class KernelExecutionError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`)
    this.name = 'KernelExecutionError'
    this.code = code
  }
}

function decodePointer(pointer) {
  return pointer.slice(1).split('/').map(segment => segment.replaceAll('~1', '/').replaceAll('~0', '~'))
}

function readPointer(root, pointer) {
  let current = root
  for (const segment of decodePointer(pointer)) {
    if (current === null || typeof current !== 'object' || !Object.hasOwn(current, segment)) return undefined
    current = current[segment]
  }
  return current
}

function writePointer(root, pointer, value) {
  const segments = decodePointer(pointer)
  const final = segments.pop()
  let current = root
  for (const segment of segments) {
    if (current === null || typeof current !== 'object' || !Object.hasOwn(current, segment)) throw new KernelExecutionError('MISSING_BINDING', `write path ${pointer} has no parent binding`)
    current = current[segment]
  }
  if (current === null || typeof current !== 'object' || !Object.hasOwn(current, final)) throw new KernelExecutionError('MISSING_BINDING', `write path ${pointer} is not declared`)
  current[final] = deepClone(value)
}

function requireDefined(value, label) {
  if (value === undefined) throw new KernelExecutionError('MISSING_BINDING', `${label} resolved to undefined`)
  return value
}

function requireBoolean(value, label) {
  if (typeof value !== 'boolean') throw new KernelExecutionError('PREDICATE_TYPE', `${label} did not resolve to boolean`)
  return value
}

function requireCollection(value, label) {
  if (!Array.isArray(value)) throw new KernelExecutionError('COLLECTION_TYPE', `${label} is not an array`)
  return value
}

function evaluate(expression, context) {
  const evaluateChild = (child, label = expression.op) => requireDefined(evaluate(child, context), label)
  switch (expression.op) {
    case 'literal': return deepClone(expression.value)
    case 'get': return readPointer(context[expression.source], expression.path)
    case 'add': return expression.args.reduce((sum, arg) => sum + Number(evaluateChild(arg, 'add arg')), 0)
    case 'digest': return canonicalDigest(evaluateChild(expression.arg, 'digest arg'))
    case 'lookup': {
      const object = evaluateChild(expression.object, 'lookup object')
      const key = evaluateChild(expression.key, 'lookup key')
      if (object === null || typeof object !== 'object' || Array.isArray(object)) throw new KernelExecutionError('LOOKUP_TYPE', 'lookup object is not a map')
      return Object.hasOwn(object, key) ? object[key] : undefined
    }
    case 'all': return expression.args.every(arg => requireBoolean(evaluate(arg, context), 'all arg'))
    case 'any': return expression.args.some(arg => requireBoolean(evaluate(arg, context), 'any arg'))
    case 'not': return !requireBoolean(evaluate(expression.arg, context), 'not arg')
    case 'eq': return canonicalStringify(evaluateChild(expression.args[0], 'eq left')) === canonicalStringify(evaluateChild(expression.args[1], 'eq right'))
    case 'neq': return canonicalStringify(evaluateChild(expression.args[0], 'neq left')) !== canonicalStringify(evaluateChild(expression.args[1], 'neq right'))
    case 'gt': return evaluateChild(expression.args[0], 'gt left') > evaluateChild(expression.args[1], 'gt right')
    case 'gte': return evaluateChild(expression.args[0], 'gte left') >= evaluateChild(expression.args[1], 'gte right')
    case 'exists': return evaluate(expression.arg, context) !== undefined
    case 'is_null': return evaluateChild(expression.arg, 'is_null arg') === null
    case 'length': {
      const value = evaluateChild(expression.arg, 'length arg')
      if (!Array.isArray(value) && typeof value !== 'string') throw new KernelExecutionError('LENGTH_TYPE', 'length arg is not an array or string')
      return value.length
    }
    case 'keys': {
      const value = evaluateChild(expression.arg, 'keys arg')
      if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new KernelExecutionError('KEYS_TYPE', 'keys arg is not a map')
      return Object.keys(value).sort()
    }
    case 'unique_by': {
      const values = requireCollection(evaluateChild(expression.collection, 'unique_by collection'), 'unique_by collection')
      const seen = new Set()
      for (const [index, entry] of values.entries()) {
        if (entry === null || typeof entry !== 'object' || !Object.hasOwn(entry, expression.key)) throw new KernelExecutionError('MISSING_BINDING', `unique_by entry ${index} has no ${expression.key}`)
        const key = canonicalStringify(entry[expression.key])
        if (seen.has(key)) return false
        seen.add(key)
      }
      return true
    }
    case 'map_by': {
      const values = requireCollection(evaluateChild(expression.collection, 'map_by collection'), 'map_by collection')
      const mapped = {}
      for (const [index, entry] of values.entries()) {
        if (entry === null || typeof entry !== 'object' || !Object.hasOwn(entry, expression.key)) throw new KernelExecutionError('MISSING_BINDING', `map_by entry ${index} has no ${expression.key}`)
        const key = String(entry[expression.key])
        if (Object.hasOwn(mapped, key)) throw new KernelExecutionError('MAP_BY_KEY_CONFLICT', `map_by key ${key} is duplicated`)
        mapped[key] = deepClone(entry)
      }
      return mapped
    }
    case 'implies': {
      const premise = requireBoolean(evaluate(expression.args[0], context), 'implies premise')
      return !premise || requireBoolean(evaluate(expression.args[1], context), 'implies conclusion')
    }
    case 'count_where': {
      const values = requireCollection(evaluateChild(expression.collection, 'count_where collection'), 'count_where collection')
      const expected = evaluateChild(expression.value, 'count_where value')
      return values.filter(entry => {
        const actual = readPointer(entry, expression.path)
        return actual !== undefined && canonicalStringify(actual) === canonicalStringify(expected)
      }).length
    }
    case 'count_exists': {
      const values = requireCollection(evaluateChild(expression.collection, 'count_exists collection'), 'count_exists collection')
      return values.filter(entry => readPointer(entry, expression.path) !== undefined).length
    }
    default: throw new KernelExecutionError('UNKNOWN_OPERATOR', `interpreter has no operator ${expression.op}`)
  }
}

function context(state, event = {}, trace = { steps: [] }) {
  return { state, event, trace }
}

function assertInvariants(spec, state, event, phase) {
  for (const invariant of spec.invariants) {
    const pass = requireBoolean(evaluate(invariant.predicate, context(state, event)), `invariant ${invariant.id}`)
    if (!pass) throw new KernelExecutionError('INVARIANT_VIOLATION', `${invariant.id} failed at ${phase}`)
  }
}

function applyEffect(spec, effect, working, event) {
  const runtime = context(working, event)
  switch (effect.op) {
    case 'set':
      writePointer(working, effect.path, evaluate(effect.value, runtime))
      break
    case 'increment': {
      const current = readPointer(working, effect.path)
      const amount = evaluate(effect.amount, runtime)
      if (!Number.isInteger(current) || !Number.isInteger(amount)) throw new KernelExecutionError('INCREMENT_TYPE', 'increment requires integers')
      writePointer(working, effect.path, current + amount)
      break
    }
    case 'append_unique': {
      const collection = readPointer(working, effect.path)
      if (!Array.isArray(collection)) throw new KernelExecutionError('APPEND_TYPE', `${effect.path} is not an array`)
      const value = evaluate(effect.value, runtime)
      if (value === null || typeof value !== 'object' || !Object.hasOwn(value, effect.key)) throw new KernelExecutionError('MISSING_BINDING', `append value lacks ${effect.key}`)
      if (collection.some(entry => canonicalStringify(entry[effect.key]) === canonicalStringify(value[effect.key]))) throw new KernelExecutionError('APPEND_UNIQUE_KEY_CONFLICT', `${effect.path} already contains ${effect.key}`)
      collection.push(deepClone(value))
      break
    }
    case 'put_once': {
      const container = readPointer(working, effect.path)
      if (container === null || typeof container !== 'object' || Array.isArray(container)) throw new KernelExecutionError('PUT_ONCE_TYPE', `${effect.path} is not a map`)
      const key = String(evaluate(effect.key, runtime))
      if (Object.hasOwn(container, key)) throw new KernelExecutionError('PUT_ONCE_KEY_CONFLICT', `${effect.path}/${key} already exists`)
      container[key] = deepClone(evaluate(effect.value, runtime))
      break
    }
    case 'release_frontier': {
      const rule = spec.cleanup_rules.find(candidate => candidate.id === effect.rule_id)
      if (!rule) throw new KernelExecutionError('MISSING_BINDING', `cleanup rule ${effect.rule_id} missing`)
      const allowed = requireBoolean(evaluate(rule.allow_when, runtime), `cleanup rule ${rule.id} allow_when`)
      const forbidden = requireBoolean(evaluate(rule.forbid_when, runtime), `cleanup rule ${rule.id} forbid_when`)
      if (!allowed || forbidden) throw new KernelExecutionError('CLEANUP_RULE_DENIED', `cleanup rule ${rule.id} did not authorize assignments`)
      for (const assignment of effect.assignments) writePointer(working, assignment.path, evaluate(assignment.value, runtime))
      break
    }
    case 'noop':
      break
    default:
      throw new KernelExecutionError('UNKNOWN_EFFECT_OPERATOR', `interpreter has no effect ${effect.op}`)
  }
}

export function executeEvent(spec, state, event) {
  validateState(spec, state, 'pre_state')
  validateEvent(spec, event)
  assertInvariants(spec, state, event, 'PRE')
  const matches = spec.transitions.filter(transition =>
    transition.from === state.state_id && transition.event === event.type &&
    requireBoolean(evaluate(transition.guard, context(state, event)), `guard ${transition.id}`))
  if (matches.length === 0) throw new KernelExecutionError('ILLEGAL_TRANSITION', `${state.state_id} + ${event.type} has no matching transition`)
  if (matches.length > 1) throw new KernelExecutionError('MULTIPLE_MATCHING_TRANSITION', `${state.state_id} + ${event.type} matched ${matches.map(item => item.id).join(',')}`)
  const transition = matches[0]
  const working = deepClone(state)
  working.state_id = transition.to
  for (const effect of transition.effects) applyEffect(spec, effect, working, event)
  validateState(spec, working, 'post_state')
  assertInvariants(spec, working, event, 'POST')
  const bound = Object.fromEntries(Object.entries(transition.result).map(([key, expression]) => [
    key, requireDefined(evaluate(expression, context(working, event)), `result ${key}`),
  ]))
  validateResult(spec, bound)
  return { transition_id: transition.id, effects_applied: transition.effects.map(effect => effect.op), result: bound, state: working }
}

function codeOf(error) {
  return typeof error?.code === 'string' ? error.code : 'UNCLASSIFIED_ERROR'
}

function assertExpectedResult(expectation, execution, preDigest, postDigest, scenarioId, ordinal) {
  if (expectation.kind !== 'RESULT') throw new KernelExecutionError('SCENARIO_EXPECTATION', `${scenarioId} step ${ordinal} expected rejection but produced a result`)
  if (canonicalStringify(execution.result) !== canonicalStringify(expectation.result)) throw new KernelExecutionError('SCENARIO_RESULT_MISMATCH', `${scenarioId} step ${ordinal} result drift`)
  if (expectation.state_unchanged === true && preDigest !== postDigest) throw new KernelExecutionError('SCENARIO_STATE_MUTATION', `${scenarioId} step ${ordinal} changed state`)
}

function assertFinalState(spec, scenario, state) {
  validateState(spec, scenario.expected_final, `${scenario.id}.expected_final`)
  if (canonicalStringify(state) !== canonicalStringify(scenario.expected_final)) throw new KernelExecutionError('SCENARIO_FINAL_STATE_MISMATCH', `${scenario.id} final state drift`)
}

export function evaluateAggregate(spec, state, traceSteps) {
  const runtime = context(state, {}, { steps: traceSteps })
  const aggregate = Object.fromEntries(Object.entries(spec.aggregate_semantics.bindings).map(([key, expression]) => [
    key, requireDefined(evaluate(expression, runtime), `aggregate ${key}`),
  ]))
  validateAggregate(spec, aggregate)
  return aggregate
}

export function executeScenario(spec, specSha256, scenario) {
  let state = deepClone(spec.initial_state)
  const traceSteps = []
  for (const [index, scenarioStep] of scenario.steps.entries()) {
    const ordinal = index + 1
    const event = deepClone(scenarioStep.event)
    const preState = deepClone(state)
    const preDigest = canonicalDigest(preState)
    try {
      const execution = executeEvent(spec, state, event)
      const postDigest = canonicalDigest(execution.state)
      assertExpectedResult(scenarioStep.expect, execution, preDigest, postDigest, scenario.id, ordinal)
      state = execution.state
      traceSteps.push({
        ordinal,
        event,
        pre_state_sha256: preDigest,
        transition_id: execution.transition_id,
        effects_applied: execution.effects_applied,
        result: execution.result,
        post_state: deepClone(state),
        post_state_sha256: postDigest,
      })
    } catch (error) {
      if (scenarioStep.expect.kind !== 'REJECTION' || codeOf(error) !== scenarioStep.expect.code) throw error
      const postDigest = canonicalDigest(state)
      if (preDigest !== postDigest) throw new KernelExecutionError('REJECTION_AFTER_EFFECT', `${scenario.id} step ${ordinal} mutated state before rejection`)
      traceSteps.push({
        ordinal,
        event,
        pre_state_sha256: preDigest,
        rejection: { code: codeOf(error), message: error.message },
        post_state: deepClone(state),
        post_state_sha256: postDigest,
      })
    }
  }
  assertFinalState(spec, scenario, state)
  return {
    schema_version: 'p3-dtk-interpreter-trace/v1',
    spec_id: spec.spec_id,
    spec_sha256: specSha256,
    scenario_id: scenario.id,
    steps: traceSteps,
    final_state: state,
    aggregate: evaluateAggregate(spec, state, traceSteps),
  }
}

export function executeScenarioMatrix(spec, specSha256, scenarioSet) {
  validateMachineSpec(spec)
  if (scenarioSet.schema_version !== 'p3-dtk-foundation-scenarios/v1' || !Array.isArray(scenarioSet.scenarios)) throw new KernelExecutionError('SCENARIO_SCHEMA_INVALID', 'scenario set header invalid')
  const ids = scenarioSet.scenarios.map(scenario => scenario.id)
  if (new Set(ids).size !== ids.length) throw new KernelExecutionError('SCENARIO_ID_DUPLICATE', 'scenario ids are not unique')
  return scenarioSet.scenarios.map(scenario => executeScenario(spec, specSha256, scenario))
}

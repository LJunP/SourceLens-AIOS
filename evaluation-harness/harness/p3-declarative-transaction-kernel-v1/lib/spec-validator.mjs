import { canonicalStringify } from './canonical-json.mjs'

export class SpecValidationError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`)
    this.name = 'SpecValidationError'
    this.code = code
  }
}

const TOP_KEYS = [
  'schema_version', 'spec_id', 'operator_algebra', 'state_ids', 'state_schema', 'initial_state',
  'event_schemas', 'cleanup_rules', 'invariants', 'result_schema', 'aggregate_semantics', 'transitions',
]
const ALGEBRA_KEYS = ['version', 'expression_operators', 'effect_operators']
const TRANSITION_KEYS = ['id', 'from', 'event', 'guard', 'to', 'effects', 'result']
const CLEANUP_KEYS = ['id', 'allow_when', 'forbid_when']
const INVARIANT_KEYS = ['id', 'check', 'predicate']
const RECORD_SCHEMA_KEYS = ['required', 'properties', 'additional_properties']
const AGGREGATE_KEYS = ['schema_version', 'result_schema', 'bindings']
const FIELD_SCHEMA_KEYS = ['type', 'required', 'properties', 'additional_properties', 'enum', 'items', 'minimum']

function fail(code, message) {
  throw new SpecValidationError(code, message)
}

function object(value, label) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail('TYPE_OBJECT_REQUIRED', `${label} must be an object`)
  return value
}

function array(value, label) {
  if (!Array.isArray(value)) fail('TYPE_ARRAY_REQUIRED', `${label} must be an array`)
  return value
}

function string(value, label) {
  if (typeof value !== 'string' || value.length === 0) fail('TYPE_STRING_REQUIRED', `${label} must be a non-empty string`)
  return value
}

function closed(value, keys, label) {
  object(value, label)
  const unknown = Object.keys(value).filter(key => !keys.includes(key))
  const missing = keys.filter(key => !Object.hasOwn(value, key))
  if (unknown.length > 0) fail('UNKNOWN_FIELD', `${label} has unknown fields: ${unknown.join(',')}`)
  if (missing.length > 0) fail('MISSING_FIELD', `${label} is missing fields: ${missing.join(',')}`)
}

function uniqueStrings(values, label) {
  array(values, label).forEach((value, index) => string(value, `${label}[${index}]`))
  if (new Set(values).size !== values.length) fail('DUPLICATE_ID', `${label} contains duplicates`)
}

function jsonPointer(path, label) {
  string(path, label)
  if (!/^\/(?:[^~/]|~0|~1)*(?:\/(?:[^~/]|~0|~1)*)*$/.test(path)) fail('JSON_POINTER_INVALID', `${label} is not a canonical non-root JSON Pointer`)
}

function actualType(value) {
  if (value === null) return 'null'
  if (Array.isArray(value)) return 'array'
  if (Number.isInteger(value)) return 'integer'
  return typeof value
}

function schemaTypes(schema) {
  return Array.isArray(schema.type) ? schema.type : [schema.type]
}

function validateFieldSchema(schema, label) {
  object(schema, label)
  const unknown = Object.keys(schema).filter(key => !FIELD_SCHEMA_KEYS.includes(key))
  if (unknown.length > 0) fail('UNKNOWN_FIELD', `${label} has unknown fields: ${unknown.join(',')}`)
  if (!Object.hasOwn(schema, 'type')) fail('MISSING_FIELD', `${label}.type missing`)
  const types = schemaTypes(schema)
  uniqueStrings(types, `${label}.type`)
  const supported = new Set(['string', 'integer', 'boolean', 'object', 'array', 'null'])
  if (types.some(type => !supported.has(type))) fail('FIELD_TYPE_UNKNOWN', `${label} has unsupported type`)
  if (schema.enum !== undefined) {
    array(schema.enum, `${label}.enum`)
    if (schema.enum.length === 0) fail('FIELD_ENUM_EMPTY', `${label}.enum cannot be empty`)
    if (schema.enum.some(value => !types.includes(actualType(value)))) fail('FIELD_ENUM_TYPE_MISMATCH', `${label}.enum contains a value outside declared types`)
    const canonicalValues = schema.enum.map(canonicalStringify)
    if (new Set(canonicalValues).size !== canonicalValues.length) fail('FIELD_ENUM_DUPLICATE', `${label}.enum contains duplicates`)
  }
  if (schema.minimum !== undefined) {
    if (!types.includes('integer') || !Number.isInteger(schema.minimum)) fail('FIELD_MINIMUM_INVALID', `${label}.minimum requires an integer schema and integer value`)
  }
  if (types.includes('object')) {
    if (!Array.isArray(schema.required)) fail('MISSING_FIELD', `${label}.required missing for object`)
    object(schema.properties, `${label}.properties`)
    if (!Object.hasOwn(schema, 'additional_properties')) fail('MISSING_FIELD', `${label}.additional_properties missing for object`)
    if (schema.additional_properties !== false) validateFieldSchema(schema.additional_properties, `${label}.additional_properties`)
    uniqueStrings(schema.required, `${label}.required`)
    for (const [key, child] of Object.entries(schema.properties)) validateFieldSchema(child, `${label}.properties.${key}`)
    if (schema.required.some(key => !Object.hasOwn(schema.properties, key))) fail('UNBOUND_REQUIRED_FIELD', `${label} requires an undeclared property`)
  } else if (schema.required !== undefined || schema.properties !== undefined || schema.additional_properties !== undefined) {
    fail('FIELD_SCHEMA_CONTRADICTION', `${label} has object-only members for a non-object type`)
  }
  if (types.includes('array')) {
    if (!Object.hasOwn(schema, 'items')) fail('MISSING_FIELD', `${label}.items missing for array`)
    validateFieldSchema(schema.items, `${label}.items`)
  } else if (schema.items !== undefined) {
    fail('FIELD_SCHEMA_CONTRADICTION', `${label} has array items for a non-array type`)
  }
}

function asObjectFieldSchema(recordSchema) {
  return { type: 'object', ...recordSchema }
}

function validateRecordSchema(schema, label) {
  closed(schema, RECORD_SCHEMA_KEYS, label)
  uniqueStrings(schema.required, `${label}.required`)
  object(schema.properties, `${label}.properties`)
  if (schema.additional_properties !== false) fail('OPEN_SCHEMA', `${label} must reject additional properties`)
  for (const [key, child] of Object.entries(schema.properties)) validateFieldSchema(child, `${label}.properties.${key}`)
  if (schema.required.some(key => !Object.hasOwn(schema.properties, key))) fail('UNBOUND_REQUIRED_FIELD', `${label} requires an undeclared property`)
}

export function validateValueAgainstSchema(value, schema, label) {
  const types = schemaTypes(schema)
  const actual = actualType(value)
  if (!types.includes(actual)) fail('FIELD_TYPE_MISMATCH', `${label} expected ${types.join('|')} but got ${actual}`)
  if (schema.enum && !schema.enum.some(candidate => canonicalStringify(candidate) === canonicalStringify(value))) fail('FIELD_ENUM_MISMATCH', `${label} is outside its closed enum`)
  if (schema.minimum !== undefined && value < schema.minimum) fail('FIELD_MINIMUM_MISMATCH', `${label} is below minimum ${schema.minimum}`)
  if (actual === 'object') {
    const missing = schema.required.filter(key => !Object.hasOwn(value, key))
    if (missing.length > 0) fail('MISSING_FIELD', `${label} is missing fields: ${missing.join(',')}`)
    for (const [key, child] of Object.entries(value)) {
      if (Object.hasOwn(schema.properties, key)) validateValueAgainstSchema(child, schema.properties[key], `${label}.${key}`)
      else if (schema.additional_properties === false) fail('UNKNOWN_FIELD', `${label} has unknown field: ${key}`)
      else validateValueAgainstSchema(child, schema.additional_properties, `${label}.${key}`)
    }
  }
  if (actual === 'array') value.forEach((item, index) => validateValueAgainstSchema(item, schema.items, `${label}[${index}]`))
}

function decodePointer(pointer) {
  return pointer.slice(1).split('/').map(part => part.replaceAll('~1', '/').replaceAll('~0', '~'))
}

function schemaAtPointer(rootSchema, pointer) {
  let cursor = rootSchema
  for (const part of decodePointer(pointer)) {
    const types = schemaTypes(cursor)
    if (types.includes('object')) {
      if (Object.hasOwn(cursor.properties, part)) cursor = cursor.properties[part]
      else if (cursor.additional_properties !== false) cursor = cursor.additional_properties
      else return undefined
    } else if (types.includes('array') && /^(?:0|[1-9][0-9]*)$/.test(part)) {
      cursor = cursor.items
    } else {
      return undefined
    }
  }
  return cursor
}

function assertBoundPointer(pointer, schema, label) {
  if (schema && !schemaAtPointer(schema, pointer)) fail('MISSING_BINDING', `${label} path ${pointer} is not declared by its source schema`)
}

function validateExpression(expression, operators, label, context) {
  object(expression, label)
  const op = string(expression.op, `${label}.op`)
  if (!operators.has(op)) fail('UNKNOWN_OPERATOR', `${label} uses unknown operator ${op}`)
  const exact = (...keys) => closed(expression, ['op', ...keys], label)
  if (op === 'literal') {
    exact('value')
    return
  }
  if (op === 'get') {
    exact('source', 'path')
    if (!context.allowedSources.has(expression.source)) fail('EXPRESSION_SOURCE_UNKNOWN', `${label}.source ${expression.source} is not allowed here`)
    jsonPointer(expression.path, `${label}.path`)
    assertBoundPointer(expression.path, context.schemas[expression.source], label)
    return
  }
  if (['add', 'all', 'any', 'eq', 'neq', 'gt', 'gte', 'implies'].includes(op)) {
    exact('args')
    array(expression.args, `${label}.args`)
    if (['eq', 'neq', 'gt', 'gte', 'implies'].includes(op) && expression.args.length !== 2) fail('OPERATOR_ARITY', `${label} requires exactly two args`)
    if (['all', 'any', 'add'].includes(op) && expression.args.length === 0) fail('OPERATOR_ARITY', `${label} requires args`)
    expression.args.forEach((arg, index) => validateExpression(arg, operators, `${label}.args[${index}]`, context))
    return
  }
  if (['digest', 'not', 'exists', 'is_null', 'length', 'keys'].includes(op)) {
    exact('arg')
    validateExpression(expression.arg, operators, `${label}.arg`, context)
    return
  }
  if (op === 'lookup') {
    exact('object', 'key')
    validateExpression(expression.object, operators, `${label}.object`, context)
    validateExpression(expression.key, operators, `${label}.key`, context)
    return
  }
  if (['unique_by', 'map_by'].includes(op)) {
    exact('collection', 'key')
    validateExpression(expression.collection, operators, `${label}.collection`, context)
    string(expression.key, `${label}.key`)
    return
  }
  if (op === 'count_where') {
    exact('collection', 'path', 'value')
    validateExpression(expression.collection, operators, `${label}.collection`, context)
    jsonPointer(expression.path, `${label}.path`)
    validateExpression(expression.value, operators, `${label}.value`, context)
    return
  }
  if (op === 'count_exists') {
    exact('collection', 'path')
    validateExpression(expression.collection, operators, `${label}.collection`, context)
    jsonPointer(expression.path, `${label}.path`)
    return
  }
  fail('UNKNOWN_OPERATOR', `${label} operator branch missing for ${op}`)
}

function validateEffect(effect, expressionOperators, effectOperators, cleanupRules, label, context, cleanupUsage) {
  object(effect, label)
  const op = string(effect.op, `${label}.op`)
  if (!effectOperators.has(op)) fail('UNKNOWN_EFFECT_OPERATOR', `${label} uses unknown effect operator ${op}`)
  const stateSchema = context.schemas.state
  if (op === 'set') {
    closed(effect, ['op', 'path', 'value'], label)
    jsonPointer(effect.path, `${label}.path`)
    assertBoundPointer(effect.path, stateSchema, label)
    validateExpression(effect.value, expressionOperators, `${label}.value`, context)
    return
  }
  if (op === 'increment') {
    closed(effect, ['op', 'path', 'amount'], label)
    jsonPointer(effect.path, `${label}.path`)
    const target = schemaAtPointer(stateSchema, effect.path)
    if (!target) fail('MISSING_BINDING', `${label}.path is unbound`)
    if (!schemaTypes(target).includes('integer')) fail('EFFECT_TARGET_TYPE', `${label}.path is not integer`)
    validateExpression(effect.amount, expressionOperators, `${label}.amount`, context)
    return
  }
  if (op === 'append_unique') {
    closed(effect, ['op', 'path', 'key', 'value'], label)
    jsonPointer(effect.path, `${label}.path`)
    const target = schemaAtPointer(stateSchema, effect.path)
    if (!target) fail('MISSING_BINDING', `${label}.path is unbound`)
    if (!schemaTypes(target).includes('array')) fail('EFFECT_TARGET_TYPE', `${label}.path is not array`)
    string(effect.key, `${label}.key`)
    validateExpression(effect.value, expressionOperators, `${label}.value`, context)
    return
  }
  if (op === 'put_once') {
    closed(effect, ['op', 'path', 'key', 'value'], label)
    jsonPointer(effect.path, `${label}.path`)
    const target = schemaAtPointer(stateSchema, effect.path)
    if (!target) fail('MISSING_BINDING', `${label}.path is unbound`)
    if (!schemaTypes(target).includes('object') || target.additional_properties === false) fail('EFFECT_TARGET_TYPE', `${label}.path is not an extensible map`)
    validateExpression(effect.key, expressionOperators, `${label}.key`, context)
    validateExpression(effect.value, expressionOperators, `${label}.value`, context)
    return
  }
  if (op === 'release_frontier') {
    closed(effect, ['op', 'rule_id', 'assignments'], label)
    const rule = cleanupRules.get(effect.rule_id)
    if (!rule) fail('MISSING_BINDING', `${label}.rule_id is unbound`)
    cleanupUsage.add(effect.rule_id)
    validateExpression(rule.allow_when, expressionOperators, `cleanup rule ${rule.id}.allow_when via ${label}`, context)
    validateExpression(rule.forbid_when, expressionOperators, `cleanup rule ${rule.id}.forbid_when via ${label}`, context)
    array(effect.assignments, `${label}.assignments`).forEach((assignment, index) => {
      closed(assignment, ['path', 'value'], `${label}.assignments[${index}]`)
      jsonPointer(assignment.path, `${label}.assignments[${index}].path`)
      assertBoundPointer(assignment.path, stateSchema, `${label}.assignments[${index}]`)
      validateExpression(assignment.value, expressionOperators, `${label}.assignments[${index}].value`, context)
    })
    return
  }
  if (op === 'noop') {
    closed(effect, ['op'], label)
    return
  }
  fail('UNKNOWN_EFFECT_OPERATOR', `${label} effect branch missing for ${op}`)
}

function eventFieldSchema(eventSchema) {
  return asObjectFieldSchema(eventSchema)
}

export function validateState(spec, state, label = 'state') {
  object(state, label)
  if (!spec.state_ids.includes(state.state_id)) fail('UNKNOWN_STATE', `${label}.state_id ${state.state_id} is unknown`)
  validateValueAgainstSchema(state, spec.state_schema, label)
}

export function validateEvent(spec, event, label = 'event') {
  object(event, label)
  const type = string(event.type, `${label}.type`)
  const schema = spec.event_schemas[type]
  if (!schema) fail('UNKNOWN_EVENT', `${label}.type ${type} is unknown`)
  const valueWithoutType = Object.fromEntries(Object.entries(event).filter(([key]) => key !== 'type'))
  validateValueAgainstSchema(valueWithoutType, eventFieldSchema(schema), label)
}

export function validateResult(spec, result, label = 'result') {
  validateValueAgainstSchema(result, asObjectFieldSchema(spec.result_schema), label)
}

export function validateAggregate(spec, aggregate, label = 'aggregate') {
  validateValueAgainstSchema(aggregate, asObjectFieldSchema(spec.aggregate_semantics.result_schema), label)
}

export function validateMachineSpec(spec) {
  closed(spec, TOP_KEYS, 'machine specification')
  if (spec.schema_version !== 'p3-dtk-machine-spec/v1') fail('SCHEMA_VERSION_UNKNOWN', 'machine specification schema_version drift')
  string(spec.spec_id, 'machine specification.spec_id')
  closed(spec.operator_algebra, ALGEBRA_KEYS, 'operator_algebra')
  if (spec.operator_algebra.version !== 'closed-generic-operator-algebra/v1') fail('ALGEBRA_VERSION_UNKNOWN', 'operator algebra version drift')
  uniqueStrings(spec.operator_algebra.expression_operators, 'operator_algebra.expression_operators')
  uniqueStrings(spec.operator_algebra.effect_operators, 'operator_algebra.effect_operators')
  const expressionOperators = new Set(spec.operator_algebra.expression_operators)
  const effectOperators = new Set(spec.operator_algebra.effect_operators)
  const expectedExpressions = new Set([
    'literal', 'get', 'add', 'digest', 'lookup', 'all', 'any', 'not', 'eq', 'neq', 'gt', 'gte',
    'exists', 'is_null', 'length', 'keys', 'unique_by', 'implies',
    'map_by', 'count_where', 'count_exists',
  ])
  const expectedEffects = new Set(['set', 'increment', 'append_unique', 'put_once', 'release_frontier', 'noop'])
  if (canonicalStringify([...expressionOperators].sort()) !== canonicalStringify([...expectedExpressions].sort())) fail('ALGEBRA_EXPRESSION_SET_DRIFT', 'expression operator set is not exact')
  if (canonicalStringify([...effectOperators].sort()) !== canonicalStringify([...expectedEffects].sort())) fail('ALGEBRA_EFFECT_SET_DRIFT', 'effect operator set is not exact')

  uniqueStrings(spec.state_ids, 'state_ids')
  validateFieldSchema(spec.state_schema, 'state_schema')
  if (!schemaTypes(spec.state_schema).includes('object')) fail('STATE_SCHEMA_INVALID', 'state_schema must be an object schema')
  const stateIdSchema = spec.state_schema.properties?.state_id
  if (!stateIdSchema || canonicalStringify(stateIdSchema.enum) !== canonicalStringify(spec.state_ids)) fail('STATE_ID_SCHEMA_DRIFT', 'state_schema state_id enum must exactly equal state_ids')
  validateState(spec, spec.initial_state, 'initial_state')

  object(spec.event_schemas, 'event_schemas')
  if (Object.keys(spec.event_schemas).length === 0) fail('EVENT_SCHEMA_EMPTY', 'event_schemas cannot be empty')
  for (const [eventType, schema] of Object.entries(spec.event_schemas)) {
    string(eventType, 'event type')
    validateRecordSchema(schema, `event_schemas.${eventType}`)
  }

  const stateOnly = { allowedSources: new Set(['state']), schemas: { state: spec.state_schema } }
  const cleanupSyntax = { allowedSources: new Set(['state', 'event']), schemas: { state: spec.state_schema } }
  array(spec.cleanup_rules, 'cleanup_rules')
  const cleanupRules = new Map()
  for (const [index, rule] of spec.cleanup_rules.entries()) {
    closed(rule, CLEANUP_KEYS, `cleanup_rules[${index}]`)
    string(rule.id, `cleanup_rules[${index}].id`)
    if (cleanupRules.has(rule.id)) fail('DUPLICATE_ID', `cleanup rule ${rule.id} duplicated`)
    cleanupRules.set(rule.id, rule)
    validateExpression(rule.allow_when, expressionOperators, `cleanup_rules[${index}].allow_when`, cleanupSyntax)
    validateExpression(rule.forbid_when, expressionOperators, `cleanup_rules[${index}].forbid_when`, cleanupSyntax)
    if (canonicalStringify(rule.allow_when) === canonicalStringify(rule.forbid_when)) fail('CONTRADICTORY_CLEANUP_RULE', `cleanup rule ${rule.id} allows and forbids the same predicate`)
  }

  array(spec.invariants, 'invariants')
  const invariantIds = new Set()
  for (const [index, invariant] of spec.invariants.entries()) {
    closed(invariant, INVARIANT_KEYS, `invariants[${index}]`)
    string(invariant.id, `invariants[${index}].id`)
    if (invariantIds.has(invariant.id)) fail('DUPLICATE_ID', `invariant ${invariant.id} duplicated`)
    invariantIds.add(invariant.id)
    if (invariant.check !== 'PRE_AND_POST') fail('INVARIANT_PHASE_UNKNOWN', `invariant ${invariant.id} has unsupported check phase`)
    validateExpression(invariant.predicate, expressionOperators, `invariants[${index}].predicate`, stateOnly)
  }

  validateRecordSchema(spec.result_schema, 'result_schema')
  closed(spec.aggregate_semantics, AGGREGATE_KEYS, 'aggregate_semantics')
  if (spec.aggregate_semantics.schema_version !== 'closed-generic-aggregate-semantics/v1') fail('AGGREGATE_VERSION_UNKNOWN', 'aggregate semantics version drift')
  validateRecordSchema(spec.aggregate_semantics.result_schema, 'aggregate_semantics.result_schema')
  object(spec.aggregate_semantics.bindings, 'aggregate_semantics.bindings')
  const aggregateFields = Object.keys(spec.aggregate_semantics.result_schema.properties)
  const aggregateUnknown = Object.keys(spec.aggregate_semantics.bindings).filter(key => !aggregateFields.includes(key))
  const aggregateMissing = spec.aggregate_semantics.result_schema.required.filter(key => !Object.hasOwn(spec.aggregate_semantics.bindings, key))
  if (aggregateUnknown.length > 0) fail('UNBOUND_AGGREGATE_SEMANTIC', `aggregate bindings contain unknown fields: ${aggregateUnknown.join(',')}`)
  if (aggregateMissing.length > 0) fail('MISSING_AGGREGATE', `aggregate bindings omit fields: ${aggregateMissing.join(',')}`)
  const aggregateContext = { allowedSources: new Set(['state', 'trace']), schemas: { state: spec.state_schema } }
  for (const [field, expression] of Object.entries(spec.aggregate_semantics.bindings)) validateExpression(expression, expressionOperators, `aggregate_semantics.bindings.${field}`, aggregateContext)

  array(spec.transitions, 'transitions')
  const transitionIds = new Set()
  const transitionGuards = new Set()
  const cleanupUsage = new Set()
  for (const [index, item] of spec.transitions.entries()) {
    closed(item, TRANSITION_KEYS, `transitions[${index}]`)
    string(item.id, `transitions[${index}].id`)
    if (transitionIds.has(item.id)) fail('DUPLICATE_ID', `transition ${item.id} duplicated`)
    transitionIds.add(item.id)
    if (!spec.state_ids.includes(item.from) || !spec.state_ids.includes(item.to)) fail('UNKNOWN_STATE', `transition ${item.id} references an unknown state`)
    const declaredEventSchema = spec.event_schemas[item.event]
    if (!declaredEventSchema) fail('UNKNOWN_EVENT', `transition ${item.id} references unknown event`)
    const context = { allowedSources: new Set(['state', 'event']), schemas: { state: spec.state_schema, event: eventFieldSchema(declaredEventSchema) } }
    validateExpression(item.guard, expressionOperators, `transitions[${index}].guard`, context)
    const guardKey = `${item.from}\u0000${item.event}\u0000${canonicalStringify(item.guard)}`
    if (transitionGuards.has(guardKey)) fail('AMBIGUOUS_TRANSITION', `transition ${item.id} duplicates a state/event/guard tuple`)
    transitionGuards.add(guardKey)
    array(item.effects, `transitions[${index}].effects`).forEach((effect, effectIndex) =>
      validateEffect(effect, expressionOperators, effectOperators, cleanupRules, `transitions[${index}].effects[${effectIndex}]`, context, cleanupUsage))
    object(item.result, `transitions[${index}].result`)
    const resultUnknown = Object.keys(item.result).filter(key => !Object.hasOwn(spec.result_schema.properties, key))
    const resultMissing = spec.result_schema.required.filter(key => !Object.hasOwn(item.result, key))
    if (resultUnknown.length > 0) fail('UNBOUND_RESULT_SEMANTIC', `transition ${item.id} binds unknown result fields`)
    if (resultMissing.length > 0) fail('MISSING_RESULT', `transition ${item.id} omits required result fields`)
    for (const [field, expression] of Object.entries(item.result)) validateExpression(expression, expressionOperators, `transitions[${index}].result.${field}`, context)
  }
  const unusedCleanup = [...cleanupRules.keys()].filter(id => !cleanupUsage.has(id))
  if (unusedCleanup.length > 0) fail('UNBOUND_CLEANUP_RULE', `cleanup rules are not bound to effects: ${unusedCleanup.join(',')}`)

  return {
    spec_id: spec.spec_id,
    states: spec.state_ids.length,
    events: Object.keys(spec.event_schemas).length,
    cleanup_rules: spec.cleanup_rules.length,
    invariants: spec.invariants.length,
    aggregate_bindings: Object.keys(spec.aggregate_semantics.bindings).length,
    transitions: spec.transitions.length,
  }
}

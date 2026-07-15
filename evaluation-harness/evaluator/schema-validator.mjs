import { isDeepStrictEqual } from "node:util";

const SUPPORTED_TYPES = new Set([
  "object", "array", "string", "integer", "number", "boolean", "null",
]);

export function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function validate(instance, schema) {
  const errors = [];
  validateNode(instance, schema, "$", errors);
  return errors.sort();
}

function validateNode(instance, schema, path, errors) {
  if (schema === null || typeof schema !== "object" || Array.isArray(schema)) {
    errors.push(`${path}: schema node must be an object`);
    return;
  }

  (schema.allOf ?? []).forEach((subschema, index) => {
    validateNode(instance, subschema, `${path}<allOf:${index}>`, errors);
  });

  if (Object.hasOwn(schema, "if")) {
    const conditionErrors = [];
    validateNode(instance, schema.if, path, conditionErrors);
    const branch = conditionErrors.length === 0 ? schema.then : schema.else;
    if (branch) validateNode(instance, branch, path, errors);
  }

  if (Object.hasOwn(schema, "type")) {
    const declared = Array.isArray(schema.type) ? schema.type : [schema.type];
    const unknown = declared.filter((type) => !SUPPORTED_TYPES.has(type));
    if (unknown.length > 0) errors.push(`${path}: unsupported schema type ${unknown.join(",")}`);
    if (!declared.some((type) => typeMatches(instance, type))) {
      errors.push(`${path}: expected type ${declared.join("|")}, got ${valueType(instance)}`);
      return;
    }
  }

  if (Object.hasOwn(schema, "const") && !isDeepStrictEqual(instance, schema.const)) {
    errors.push(`${path}: value does not match const`);
  }
  if (Object.hasOwn(schema, "enum") && !schema.enum.some((entry) => isDeepStrictEqual(instance, entry))) {
    errors.push(`${path}: value is not in enum`);
  }

  if (typeof instance === "string") validateString(instance, schema, path, errors);
  if (typeof instance === "number") validateNumber(instance, schema, path, errors);
  if (Array.isArray(instance)) validateArray(instance, schema, path, errors);
  if (instance !== null && typeof instance === "object" && !Array.isArray(instance)) {
    validateObject(instance, schema, path, errors);
  }
}

function validateString(instance, schema, path, errors) {
  if (Object.hasOwn(schema, "minLength") && [...instance].length < schema.minLength) {
    errors.push(`${path}: shorter than minLength`);
  }
  if (Object.hasOwn(schema, "maxLength") && [...instance].length > schema.maxLength) {
    errors.push(`${path}: longer than maxLength`);
  }
  if (Object.hasOwn(schema, "pattern")) {
    try {
      if (!new RegExp(schema.pattern).test(instance)) errors.push(`${path}: does not match pattern`);
    } catch {
      errors.push(`${path}: invalid schema pattern`);
    }
  }
  if (schema.format === "date-time") {
    const shape = /T/.test(instance) && /(?:Z|[+-]\d{2}:\d{2})$/.test(instance);
    if (!shape || Number.isNaN(Date.parse(instance))) errors.push(`${path}: invalid date-time`);
  }
}

function validateNumber(instance, schema, path, errors) {
  if (Object.hasOwn(schema, "minimum") && instance < schema.minimum) {
    errors.push(`${path}: below minimum`);
  }
}

function validateArray(instance, schema, path, errors) {
  if (Object.hasOwn(schema, "minItems") && instance.length < schema.minItems) {
    errors.push(`${path}: fewer than minItems`);
  }
  if (Object.hasOwn(schema, "maxItems") && instance.length > schema.maxItems) {
    errors.push(`${path}: more than maxItems`);
  }
  if (schema.uniqueItems) {
    const identities = instance.map((item) => canonicalJson(item));
    if (new Set(identities).size !== identities.length) errors.push(`${path}: items are not unique`);
  }
  if (schema.items && typeof schema.items === "object" && !Array.isArray(schema.items)) {
    instance.forEach((item, index) => validateNode(item, schema.items, `${path}[${index}]`, errors));
  }
}

function validateObject(instance, schema, path, errors) {
  (schema.required ?? []).forEach((key) => {
    if (!Object.hasOwn(instance, key)) errors.push(`${path}: missing required property ${key}`);
  });

  const properties = schema.properties ?? {};
  Object.entries(properties).forEach(([key, subschema]) => {
    if (Object.hasOwn(instance, key)) validateNode(instance[key], subschema, `${path}.${key}`, errors);
  });

  const unknownKeys = Object.keys(instance).filter((key) => !Object.hasOwn(properties, key)).sort();
  if (schema.additionalProperties === false) {
    unknownKeys.forEach((key) => errors.push(`${path}: additional property ${key}`));
  } else if (schema.additionalProperties && typeof schema.additionalProperties === "object") {
    unknownKeys.forEach((key) => validateNode(instance[key], schema.additionalProperties, `${path}.${key}`, errors));
  }
}

function typeMatches(instance, type) {
  switch (type) {
    case "object": return instance !== null && typeof instance === "object" && !Array.isArray(instance);
    case "array": return Array.isArray(instance);
    case "string": return typeof instance === "string";
    case "integer": return Number.isInteger(instance);
    case "number": return typeof instance === "number" && Number.isFinite(instance);
    case "boolean": return typeof instance === "boolean";
    case "null": return instance === null;
    default: return false;
  }
}

function valueType(instance) {
  if (instance === null) return "null";
  if (Array.isArray(instance)) return "array";
  if (Number.isInteger(instance)) return "integer";
  if (typeof instance === "number") return "number";
  return typeof instance;
}

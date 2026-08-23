import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'

export class CanonicalJsonError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`)
    this.name = 'CanonicalJsonError'
    this.code = code
  }
}

class StrictParser {
  constructor(text) {
    this.text = text
    this.index = 0
  }

  fail(code, message) {
    throw new CanonicalJsonError(code, `${message} at byte ${Buffer.byteLength(this.text.slice(0, this.index), 'utf8')}`)
  }

  skipWhitespace() {
    while (this.index < this.text.length && /[\t\n\r ]/.test(this.text[this.index])) this.index += 1
  }

  consume(expected) {
    if (this.text[this.index] !== expected) this.fail('JSON_SYNTAX', `expected ${JSON.stringify(expected)}`)
    this.index += 1
  }

  parseString() {
    const start = this.index
    this.consume('"')
    let escaped = false
    while (this.index < this.text.length) {
      const character = this.text[this.index]
      this.index += 1
      if (escaped) {
        escaped = false
        continue
      }
      if (character === '\\') {
        escaped = true
        continue
      }
      if (character === '"') {
        const raw = this.text.slice(start, this.index)
        try {
          return JSON.parse(raw)
        } catch (error) {
          this.fail('JSON_STRING_INVALID', error.message)
        }
      }
      if (character.codePointAt(0) < 0x20) this.fail('JSON_STRING_CONTROL_CHARACTER', 'unescaped control character')
    }
    this.fail('JSON_STRING_UNTERMINATED', 'unterminated string')
  }

  parseNumber() {
    const match = this.text.slice(this.index).match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/)
    if (!match) this.fail('JSON_NUMBER_INVALID', 'invalid number')
    this.index += match[0].length
    const value = Number(match[0])
    if (!Number.isFinite(value) || Object.is(value, -0)) this.fail('JSON_NUMBER_UNSUPPORTED', 'non-finite or negative-zero number')
    if (Number.isInteger(value) && !Number.isSafeInteger(value)) this.fail('JSON_INTEGER_UNSAFE', 'unsafe integer')
    return value
  }

  parseArray() {
    const value = []
    this.consume('[')
    this.skipWhitespace()
    if (this.text[this.index] === ']') {
      this.index += 1
      return value
    }
    while (true) {
      value.push(this.parseValue())
      this.skipWhitespace()
      if (this.text[this.index] === ']') {
        this.index += 1
        return value
      }
      this.consume(',')
      this.skipWhitespace()
    }
  }

  parseObject() {
    const value = {}
    const keys = new Set()
    this.consume('{')
    this.skipWhitespace()
    if (this.text[this.index] === '}') {
      this.index += 1
      return value
    }
    while (true) {
      if (this.text[this.index] !== '"') this.fail('JSON_OBJECT_KEY_INVALID', 'object key must be a string')
      const key = this.parseString()
      if (keys.has(key)) this.fail('DUPLICATE_KEY', `duplicate object key ${JSON.stringify(key)}`)
      keys.add(key)
      this.skipWhitespace()
      this.consume(':')
      this.skipWhitespace()
      value[key] = this.parseValue()
      this.skipWhitespace()
      if (this.text[this.index] === '}') {
        this.index += 1
        return value
      }
      this.consume(',')
      this.skipWhitespace()
    }
  }

  parseValue() {
    this.skipWhitespace()
    const character = this.text[this.index]
    if (character === '"') return this.parseString()
    if (character === '{') return this.parseObject()
    if (character === '[') return this.parseArray()
    if (character === '-' || /[0-9]/.test(character ?? '')) return this.parseNumber()
    for (const [literal, value] of [['true', true], ['false', false], ['null', null]]) {
      if (this.text.startsWith(literal, this.index)) {
        this.index += literal.length
        return value
      }
    }
    this.fail('JSON_VALUE_INVALID', 'invalid value')
  }

  parse() {
    const value = this.parseValue()
    this.skipWhitespace()
    if (this.index !== this.text.length) this.fail('JSON_TRAILING_BYTES', 'trailing bytes')
    return value
  }
}

export function strictParseJson(bytes, label = 'JSON') {
  const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes)
  const text = buffer.toString('utf8')
  if (!Buffer.from(text, 'utf8').equals(buffer)) throw new CanonicalJsonError('UTF8_INVALID', `${label} is not valid UTF-8`)
  try {
    return new StrictParser(text).parse()
  } catch (error) {
    if (error instanceof CanonicalJsonError) throw new CanonicalJsonError(error.code, `${label}: ${error.message}`)
    throw error
  }
}

export function canonicalStringify(value) {
  if (value === null) return 'null'
  if (typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value)
  if (typeof value === 'number') {
    if (!Number.isFinite(value) || Object.is(value, -0)) throw new CanonicalJsonError('CANONICAL_NUMBER_INVALID', 'number is non-finite or negative zero')
    if (Number.isInteger(value) && !Number.isSafeInteger(value)) throw new CanonicalJsonError('CANONICAL_INTEGER_UNSAFE', 'integer is outside safe range')
    return JSON.stringify(value)
  }
  if (Array.isArray(value)) return `[${value.map(canonicalStringify).join(',')}]`
  if (typeof value === 'object') {
    const prototype = Object.getPrototypeOf(value)
    if (prototype !== Object.prototype && prototype !== null) throw new CanonicalJsonError('CANONICAL_OBJECT_PROTOTYPE', 'object has a non-plain prototype')
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalStringify(value[key])}`).join(',')}}`
  }
  throw new CanonicalJsonError('CANONICAL_TYPE_UNSUPPORTED', `unsupported type ${typeof value}`)
}

export function canonicalJsonBytes(value) {
  return Buffer.from(`${canonicalStringify(value)}\n`, 'utf8')
}

export function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex')
}

export function canonicalDigest(value) {
  return sha256(canonicalJsonBytes(value))
}

export function readCanonicalJson(path, label = path) {
  const bytes = readFileSync(path)
  const value = strictParseJson(bytes, label)
  const canonical = canonicalJsonBytes(value)
  if (!canonical.equals(bytes)) throw new CanonicalJsonError('NON_CANONICAL_JSON', `${label} bytes are not canonical JSON plus one LF`)
  return { value, bytes, sha256: sha256(bytes) }
}

export function deepClone(value) {
  return strictParseJson(canonicalJsonBytes(value), 'deep clone')
}

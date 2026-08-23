#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs'
import { canonicalJsonBytes, strictParseJson } from '../lib/canonical-json.mjs'

if (process.argv.length < 3) throw new Error('usage: canonicalize-json.mjs FILE...')
for (const path of process.argv.slice(2)) {
  const value = strictParseJson(readFileSync(path), path)
  writeFileSync(path, canonicalJsonBytes(value), { flag: 'w' })
  process.stdout.write(`CANONICALIZED ${path}\n`)
}

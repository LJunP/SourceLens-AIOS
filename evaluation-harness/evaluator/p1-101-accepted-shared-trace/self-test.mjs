import {
  cpSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  QualityNonPass,
  verifyQualityFixtures,
} from "./quality-oracle.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(HERE, "../../..");
const FIXTURE_ROOT = join(
  REPOSITORY_ROOT,
  "evaluation-harness/fixtures/p1-101-accepted-shared-trace",
);

const result = verifyQualityFixtures();
if (
  result.status !== "PASS" ||
  result.positive_cases !== 6 ||
  result.negative_cases !== 19
) {
  throw new Error("fixture oracle did not accept the frozen matrix");
}

const temporaryRoot = mkdtempSync(join(tmpdir(), "p1-101-quality-fixture-self-test-"));
try {
  const copiedRoot = join(temporaryRoot, "fixtures");
  cpSync(FIXTURE_ROOT, copiedRoot, {
    recursive: true,
    dereference: false,
    errorOnExist: true,
  });
  const catalogPath = join(copiedRoot, "negative-cases.json");
  const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
  catalog.cases.pop();
  writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, {
    encoding: "utf8",
    flag: "w",
    mode: 0o600,
  });
  let rejected = false;
  try {
    verifyQualityFixtures({ fixtureRoot: copiedRoot });
  } catch (error) {
    rejected = error instanceof QualityNonPass && error.reason === "NEGATIVE_CATALOG_INVALID";
  }
  if (!rejected) {
    throw new Error("fixture oracle accepted an incomplete negative catalog");
  }
} finally {
  rmSync(temporaryRoot, { recursive: true, force: false });
}

process.stdout.write(`${JSON.stringify({
  schema_version: "p1-101-quality-fixture-self-test/v1",
  status: "PASS",
  positive_cases: result.positive_cases,
  negative_cases: result.negative_cases,
  fixture_manifest_sha256: result.fixture_manifest_sha256,
})}\n`);

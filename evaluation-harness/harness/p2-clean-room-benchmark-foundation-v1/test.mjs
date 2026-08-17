import assert from "node:assert/strict";
import {
  BENCHMARK_SPEC,
  BenchmarkInputError,
  assertIdentity,
  groundTruthFromFiles,
  isProductionJava,
  rankDocuments,
  safeRelative,
  selectDevTasks,
  selectWithinBudget,
  sha256,
  stableJson,
  taskMetrics,
  tokenize,
  validateSourcePack,
} from "./core.mjs";

function expectCode(code, operation) {
  assert.throws(operation, (error) => error instanceof BenchmarkInputError && error.code === code);
}

const baseTask = (id, repository, split) => ({ task_id: id, repository, split });
const repositories = ["a/a", "b/b", "c/c", "d/d", "e/e", "f/f"];
const tasks = repositories.flatMap((repository, index) => [
  baseTask(`task-${index}-a`, repository, index < 4 ? "DEV" : "HELD"),
  baseTask(`task-${index}-b`, repository, index < 4 ? "DEV" : "HELD"),
]);
const manifest = {
  schema_version: "p2-benchmark-source-pack/v1",
  artifact_id: "P2_BENCHMARK_SOURCE_PACK_V1",
  status: "ACCEPTED_INSTALLED_CREATE_ONCE",
  tasks,
  split: {
    DEV: { task_ids: tasks.filter((task) => task.split === "DEV").map((task) => task.task_id) },
    HELD: { task_ids: tasks.filter((task) => task.split === "HELD").map((task) => task.task_id) },
  },
  inventory: [],
};

validateSourcePack(manifest);
assert.equal(selectDevTasks(manifest).length, 8);
expectCode("HELD_OR_UNKNOWN_TASK_FORBIDDEN", () => selectDevTasks(manifest, [manifest.split.HELD.task_ids[0]]));
expectCode("DUPLICATE_TASK_ID", () => validateSourcePack({ ...manifest, tasks: [...tasks, tasks[0]] }));
expectCode("PATH_ESCAPE", () => safeRelative("../held/secret.json"));
expectCode("PATH_ESCAPE", () => safeRelative("a/../../held.json"));
assert.equal(isProductionJava("module/src/main/java/example/Main.java"), true);
assert.equal(isProductionJava("module/src/test/java/example/MainTest.java"), false);
assert.equal(isProductionJava("module/target/generated/Main.java"), false);
assert.deepEqual(groundTruthFromFiles([
  { filename: "src/test/java/T.java" },
  { filename: "src/main/java/B.java" },
  { filename: "src/main/java/A.java" },
]), ["src/main/java/A.java", "src/main/java/B.java"]);

const bytes = Buffer.from("frozen");
assertIdentity(bytes, { byteLength: bytes.length, sha256: sha256(bytes) }, "fixture");
expectCode("IDENTITY_DRIFT", () => assertIdentity(Buffer.from("drift"), { byteLength: bytes.length, sha256: sha256(bytes) }, "fixture"));
assert.deepEqual(tokenize("HTTPServer parseURL_v2"), ["httpserver", "parse", "url_v2"]);

const corpus = [
  { path: "b.java", byteLength: 10, sha256: "b", tokens: ["alpha"] },
  { path: "a.java", byteLength: 10, sha256: "a", tokens: ["alpha"] },
  { path: "c.java", byteLength: BENCHMARK_SPEC.byteBudget + 1, sha256: "c", tokens: ["alpha", "alpha"] },
];
const first = rankDocuments("B0", "alpha", corpus);
const second = rankDocuments("B0", "alpha", corpus);
assert.equal(stableJson(first), stableJson(second));
assert.deepEqual(first.map((item) => item.path), ["a.java", "b.java", "c.java"]);
const selected = selectWithinBudget(first);
assert.deepEqual(selected.selected.map((item) => item.path), ["a.java", "b.java"]);
assert.deepEqual(taskMetrics(selected.selected, ["b.java"]), {
  recall: 1,
  precision: 0.5,
  reciprocal_rank: 0.5,
  relevant_selected: 1,
  ground_truth_count: 1,
  selected_count: 2,
});

const virtualOutputs = new Set();
function createOnceVirtual(name) {
  if (virtualOutputs.has(name)) throw new BenchmarkInputError("OUTPUT_EXISTS", name);
  virtualOutputs.add(name);
}
createOnceVirtual("candidate/result.json");
expectCode("OUTPUT_EXISTS", () => createOnceVirtual("candidate/result.json"));

process.stdout.write("P2_CLEAN_ROOM_BASELINE_TESTS: PASS assertions=24\n");

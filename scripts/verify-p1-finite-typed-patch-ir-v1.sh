#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NODE_BIN="/usr/local/bin/node"
COMPILER_PATH="$ROOT_DIR/evaluation-harness/harness/finite-typed-patch-ir-v1/compiler.mjs"
RUNNER_PATH="$ROOT_DIR/evaluation-harness/harness/finite-typed-patch-ir-v1/runner.mjs"
TASK_CARD_RELATIVE="evaluation-harness/fixtures/finite-typed-patch-ir-v1/task-card.json"

if [[ "${1:-}" == "formal-preflight" ]]; then
  if [[ "$#" -ne 9 ]]; then
    echo "usage: $0 formal-preflight EXPECTED_COMMIT EXPECTED_TREE EXPECTED_MANIFEST_SHA256 EXPECTED_DIFF_BYTE_LENGTH EXPECTED_DIFF_SHA256 ABSOLUTE_MANIFEST EVIDENCE_ROOT RUN_ID" >&2
    exit 2
  fi
  expected_commit="$2"
  expected_tree="$3"
  expected_manifest_sha256="$4"
  expected_diff_byte_length="$5"
  expected_diff_sha256="$6"
  candidate_manifest="$7"
  evidence_root="$8"
  run_id="$9"

  [[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid expected commit" >&2; exit 2; }
  [[ "$expected_tree" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid expected tree" >&2; exit 2; }
  [[ "$expected_manifest_sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid expected manifest hash" >&2; exit 2; }
  [[ "$expected_diff_byte_length" =~ ^(0|[1-9][0-9]*)$ ]] || { echo "invalid expected diff length" >&2; exit 2; }
  [[ "$expected_diff_sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid expected diff hash" >&2; exit 2; }
  [[ "$run_id" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || { echo "invalid run id" >&2; exit 2; }
  [[ "$candidate_manifest" == /* && -f "$candidate_manifest" && ! -L "$candidate_manifest" ]] || {
    echo "candidate manifest must be an absolute regular non-symlink file" >&2
    exit 2
  }
  [[ "$evidence_root" == "/Users/lijunpeng/Developer/.sourcelens-audit/p1-055-finite-typed-patch-ir-20260720T014028Z" ]] || {
    echo "unexpected evidence root" >&2
    exit 2
  }
  [[ -d "$evidence_root" && ! -L "$evidence_root" ]] || { echo "evidence root identity mismatch" >&2; exit 2; }
  [[ ! -e "$evidence_root/runs/$run_id" && ! -L "$evidence_root/runs/$run_id" ]] || { echo "run root already exists" >&2; exit 2; }
  [[ -x "$NODE_BIN" && ! -L "$NODE_BIN" ]] || { echo "frozen Node path identity mismatch" >&2; exit 2; }
  for source_path in "$COMPILER_PATH" "$RUNNER_PATH"; do
    [[ -f "$source_path" && ! -L "$source_path" ]] || { echo "candidate module identity mismatch: $source_path" >&2; exit 2; }
  done

  preflight_git() {
    /usr/bin/env -i \
      HOME="$evidence_root" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      LANG=C \
      LC_ALL=C \
      TZ=UTC \
      GIT_CONFIG_NOSYSTEM=1 \
      GIT_CONFIG_GLOBAL=/dev/null \
      GIT_TERMINAL_PROMPT=0 \
      GIT_OPTIONAL_LOCKS=0 \
      /usr/bin/git -C "$ROOT_DIR" "$@"
  }

  cd "$ROOT_DIR"
  [[ "$(preflight_git rev-parse --verify 'HEAD^{commit}')" == "$expected_commit" ]] || { echo "candidate HEAD mismatch" >&2; exit 2; }
  [[ "$(preflight_git rev-parse --verify 'HEAD^{tree}')" == "$expected_tree" ]] || { echo "candidate tree mismatch" >&2; exit 2; }
  [[ -z "$(preflight_git status --porcelain=v1 --untracked-files=all)" ]] || { echo "candidate checkout is not clean" >&2; exit 2; }
  expected_changed_paths=$'Makefile\ndocs/PROJECT_CODE_MAP.md\nevaluation-harness/evaluator/finite-typed-patch-ir-v1/quality-oracle.mjs\nevaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir00.json\nevaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir01.json\nevaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir10.json\nevaluation-harness/fixtures/finite-typed-patch-ir-v1/programs/ir11.json\nevaluation-harness/fixtures/finite-typed-patch-ir-v1/task-card.json\nevaluation-harness/harness/finite-typed-patch-ir-v1/compiler.mjs\nevaluation-harness/harness/finite-typed-patch-ir-v1/runner.mjs\nscripts/verify-p1-finite-typed-patch-ir-v1.sh'
  actual_changed_paths="$(preflight_git diff --name-only d9cd7bd4d0b68c2bcaa4ff4d3b511e39eaa4208b "$expected_commit" --)"
  [[ "$actual_changed_paths" == "$expected_changed_paths" ]] || { echo "candidate changed-path population mismatch" >&2; exit 2; }
  preflight_git diff --binary --full-index --no-ext-diff --no-textconv d9cd7bd4d0b68c2bcaa4ff4d3b511e39eaa4208b "$expected_commit" -- | \
    /usr/bin/env -i \
      HOME="$evidence_root" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
      LANG=C \
      LC_ALL=C \
      TZ=UTC \
      NODE_OPTIONS="--no-warnings" \
      "$NODE_BIN" \
      evaluation-harness/harness/finite-typed-patch-ir-v1/runner.mjs \
      preflight-diff \
      --expected-byte-length "$expected_diff_byte_length" \
      --expected-sha256 "$expected_diff_sha256"

  echo "P1_055_PRELOAD_PREFLIGHT: PASS commit=$expected_commit tree=$expected_tree manifest_sha256=$expected_manifest_sha256 run_id=$run_id"
  exec /usr/bin/env -i \
    HOME="$evidence_root" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
    LANG=C \
    LC_ALL=C \
    TZ=UTC \
    NODE_OPTIONS="--no-warnings" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_TERMINAL_PROMPT=0 \
    SOURCELENS_P1_055_PRELOAD_STATUS=PASS \
    SOURCELENS_P1_055_PRELOAD_COMMIT="$expected_commit" \
    SOURCELENS_P1_055_PRELOAD_TREE="$expected_tree" \
    SOURCELENS_P1_055_PRELOAD_MANIFEST_SHA256="$expected_manifest_sha256" \
    SOURCELENS_P1_055_PRELOAD_DIFF_BYTE_LENGTH="$expected_diff_byte_length" \
    SOURCELENS_P1_055_PRELOAD_DIFF_SHA256="$expected_diff_sha256" \
    SOURCELENS_P1_055_PRELOAD_RUN_ID="$run_id" \
    "$NODE_BIN" \
    evaluation-harness/harness/finite-typed-patch-ir-v1/runner.mjs \
    run \
    --task-card "$TASK_CARD_RELATIVE" \
    --candidate-manifest "$candidate_manifest" \
    --evidence-root "$evidence_root" \
    --run-id "$run_id"
fi

if [[ "$#" -ne 0 ]]; then
  echo "P1-055 targeted verifier takes no arguments" >&2
  exit 2
fi

if [[ ! -x "$NODE_BIN" || -L "$NODE_BIN" ]]; then
  echo "P1-055 verification requires the frozen executable Node path: $NODE_BIN" >&2
  exit 1
fi

for source_path in "$COMPILER_PATH" "$RUNNER_PATH"; do
  if [[ ! -f "$source_path" || -L "$source_path" ]]; then
    echo "P1-055 Worker source is missing or symlinked: $source_path" >&2
    exit 1
  fi
done

"$NODE_BIN" --check "$COMPILER_PATH"
"$NODE_BIN" --check "$RUNNER_PATH"

cd "$ROOT_DIR"
"$NODE_BIN" \
  evaluation-harness/harness/finite-typed-patch-ir-v1/runner.mjs \
  self-test \
  --task-card "$TASK_CARD_RELATIVE"

echo "AIOS P1-055 finite typed patch IR targeted verification PASS"

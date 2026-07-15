#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "P1 SAFETY BOUNDARY FAIL: $*" >&2
  exit 1
}

tracked_sensitive="$(git ls-files \
  | grep -E '(^|/)(\.env($|\.)|id_(rsa|ed25519)$|.*\.(pem|key|p12|pfx)$)' \
  | grep -Ev '(^|/)\.env\.example$' || true)"
[[ -z "$tracked_sensitive" ]] || fail "tracked secret-like files detected: $tracked_sensitive"

git ls-files | grep -q '^\.sourcelens-audit/' && fail "historical audit material leaked into Git"

ruby -ryaml -e '
  task = YAML.safe_load(File.read("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml"), aliases: false)
  abort "network must be disabled" unless task.dig("environment", "network") == "disabled"
  abort "provider must be none" unless task.dig("environment", "provider") == "none"
  abort "secrets must be none" unless task.dig("environment", "secrets") == "none"
  abort "task worktree write boundary widened" unless task.dig("environment", "task_worktree_write") == "exact_owned_paths_only"
  abort "canonical main write must be forbidden" unless task.dig("environment", "canonical_main_write") == "forbidden"
  abort "system-under-test write must be forbidden" unless task.dig("environment", "system_under_test_checkout_write") == "forbidden"
  abort "remote effects must be forbidden" unless task.dig("environment", "remote_effects") == "forbidden"
  abort "production effects must be forbidden" unless task.dig("environment", "production_effects") == "forbidden"
' || fail "P1 task safety declaration invalid"

echo "P1 basic safety boundary validation passed (declarative/cooperative-local scope only)."

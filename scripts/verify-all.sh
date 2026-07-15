#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_step() {
  local title="$1"
  shift
  echo
  echo "==> ${title}"
  "$@"
}

run_in_dir() {
  local dir="$1"
  shift
  (cd "$dir" && "$@")
}

check_shell_scripts() {
  local script
  for script in "${ROOT_DIR}"/scripts/*.sh; do
    bash -n "$script"
  done
}

run_step "Shell syntax" check_shell_scripts
run_step "Git whitespace" git -C "$ROOT_DIR" diff --check
run_step "AIOS current authority" "${ROOT_DIR}/scripts/validate-aios-governance.sh"
run_step "P1 basic safety boundary" "${ROOT_DIR}/scripts/check-p1-safety-boundary.sh"
run_step "Project code map" node "${ROOT_DIR}/scripts/generate-project-code-map.mjs" --check
run_step "API contract" node "${ROOT_DIR}/scripts/validate-api-design.mjs"
run_step "Database schema contract" node "${ROOT_DIR}/scripts/validate-db-schema-contract.mjs"
run_step "Backend tests" run_in_dir "${ROOT_DIR}/backend-spring" mvn clean test
run_step "Frontend build" run_in_dir "${ROOT_DIR}/web-console" npm run build
run_step "Rust analyzer check" run_in_dir "${ROOT_DIR}/analyzer-rust" cargo check --locked
run_step "Rust analyzer tests" run_in_dir "${ROOT_DIR}/analyzer-rust" cargo test --locked
run_step "LLM safety fixtures" "${ROOT_DIR}/scripts/llm-safety-regression.sh"
run_step "Dependency boundary" "${ROOT_DIR}/scripts/dependency-regression-check.sh"

echo
echo "Current SourceLens AIOS P1 development baseline verification passed."

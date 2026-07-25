#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKET_PATH="/Users/lijunpeng/Developer/.sourcelens-audit/p1-116-closed-profile-rollback-route-20260725/FOUNDER_P1_CLEAN_ROOM_CLOSED_PROFILE_SET_AND_IDENTITY_BOUND_ROLLBACK_THEN_BASELINE_ROUTE_V1.md"
TRUTH_PATH="${ROOT_DIR}/docs/aios/truth/project_state.yaml"
BINDING_PATH="${ROOT_DIR}/evaluation-harness/fixtures/p1-116-closed-profile-scanner-admission/accepted-p0-binding.json"
NEGATIVE_PATH="${ROOT_DIR}/evaluation-harness/fixtures/p1-116-closed-profile-scanner-admission/negative-cases.json"
SOURCE_TEMPLATE="${ROOT_DIR}/evaluation-harness/fixtures/p1-116-closed-profile-scanner-admission/source-template"
MATRIX="${ROOT_DIR}/evaluation-harness/evaluator/p1-116-closed-profile-scanner-admission/run-matrix.mjs"
CLEANUP_HELPER="${ROOT_DIR}/scripts/p1-116-verifier-owned-cleanup.rb"

test -f "${PACKET_PATH}" && test ! -L "${PACKET_PATH}"
test -f "${TRUTH_PATH}" && test ! -L "${TRUTH_PATH}"
test -f "${BINDING_PATH}" && test ! -L "${BINDING_PATH}"
test -f "${NEGATIVE_PATH}" && test ! -L "${NEGATIVE_PATH}"
test -d "${SOURCE_TEMPLATE}" && test ! -L "${SOURCE_TEMPLATE}"
test -f "${CLEANUP_HELPER}" && test ! -L "${CLEANUP_HELPER}"

owned_parent=""
owned_dev=""
owned_ino=""
owned_uid=""
owned_gid=""
owned_mode=""
retain_owned_parent_on_failure() {
  if [[ -n "${owned_parent}" && -d "${owned_parent}" && ! -L "${owned_parent}" ]]; then
    echo "P1-116 verifier retained uncleaned output after failure: ${owned_parent}" >&2
  fi
}

ruby "${CLEANUP_HELPER}" self-test >/dev/null

if [[ -n "${P1_116_FORMAL_OUTPUT_ROOT:-}" ]]; then
  OUTPUT_ROOT="${P1_116_FORMAL_OUTPUT_ROOT}"
  test ! -e "${OUTPUT_ROOT}" && test ! -L "${OUTPUT_ROOT}"
else
  owned_parent="$(mktemp -d /private/tmp/sourcelens-p1-116-verify.XXXXXX)"
  read -r owned_dev owned_ino owned_uid owned_gid owned_mode < <(
    ruby -e '
      s = File.lstat(ARGV.fetch(0))
      puts "#{s.dev} #{s.ino} #{s.uid} #{s.gid} #{(s.mode & 07777).to_s(8)}"
    ' "${owned_parent}"
  )
  trap retain_owned_parent_on_failure EXIT
  OUTPUT_ROOT="${owned_parent}/formal"
fi

node "${MATRIX}" \
  --packet "${PACKET_PATH}" \
  --truth "${TRUTH_PATH}" \
  --binding "${BINDING_PATH}" \
  --negative-cases "${NEGATIVE_PATH}" \
  --source-template "${SOURCE_TEMPLATE}" \
  --output-root "${OUTPUT_ROOT}"

node -e '
  const fs = require("node:fs");
  const path = process.argv[1];
  const value = JSON.parse(fs.readFileSync(path, "utf8"));
  if (value.status !== "PASS"
      || value.exact_closed_profile_set !== true
      || value.positive_real_scanner_runs !== 2
      || value.positive_target_executions !== 2
      || value.positive_exact_rollbacks !== 2
      || value.negative_cases !== 16
      || value.negative_rejections !== 16
      || value.false_accepts !== 0
      || value.pre_execution_negative_target_executions !== 0
      || Object.values(value.observed_external_effects).some((count) => count !== 0)) {
    throw new Error(`P1-116 summary NON_PASS: ${JSON.stringify(value)}`);
  }
' "${OUTPUT_ROOT}/matrix-summary.json"

if [[ -n "${owned_parent}" ]]; then
  cleanup_ledger="$(
    ruby "${CLEANUP_HELPER}" capture \
      "${owned_parent}" \
      "${owned_dev}" \
      "${owned_ino}" \
      "${owned_uid}" \
      "${owned_gid}" \
      "${owned_mode}"
  )"
  printf '%s' "${cleanup_ledger}" |
    ruby "${CLEANUP_HELPER}" cleanup "${owned_parent}" >/dev/null
  test ! -e "${owned_parent}" && test ! -L "${owned_parent}"
  cleaned_output="${OUTPUT_ROOT}"
  owned_parent=""
  trap - EXIT
  echo "P1_116_CLOSED_PROFILE_SCANNER_ADMISSION: PASS output_cleaned=${cleaned_output}"
else
  echo "P1_116_CLOSED_PROFILE_SCANNER_ADMISSION: PASS output=${OUTPUT_ROOT}"
fi

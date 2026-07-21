#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${ROOT_DIR}/scripts/validate-current-task-authority.rb"

[[ -f "${CORE}" && ! -L "${CORE}" ]] || {
  echo "CURRENT_TASK_AUTHORITY: NON_PASS category=CORE_UNAVAILABLE detail=semantic core missing or symlinked" >&2
  exit 1
}
command -v ruby >/dev/null 2>&1 || {
  echo "CURRENT_TASK_AUTHORITY: NON_PASS category=CORE_UNAVAILABLE detail=ruby is required" >&2
  exit 1
}

if [[ $# -eq 0 ]]; then
  exec ruby "${CORE}"
fi

if [[ $# -eq 2 && "$1" == "--check-current-p1-route" ]]; then
  exec ruby "${CORE}" --truth "$2"
fi

echo "CURRENT_TASK_AUTHORITY: NON_PASS category=CLI detail=unsupported arguments" >&2
exit 1

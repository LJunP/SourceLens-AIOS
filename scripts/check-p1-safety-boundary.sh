#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRUTH_PATH="${ROOT_DIR}/docs/aios/truth/project_state.yaml"

fail() {
  echo "P1 SAFETY BOUNDARY FAIL: $*" >&2
  exit 1
}

repo_root_for_truth() {
  ruby -rpathname -e '
    truth = Pathname.new(ARGV.fetch(0)).realpath
    root = truth.dirname.dirname.dirname.dirname
    abort("Truth is not at docs/aios/truth/project_state.yaml") unless
      truth == root.join("docs/aios/truth/project_state.yaml")
    puts root
  ' "$1"
}

run_authority_core() {
  local repo_root="$1"
  local validator="${repo_root}/scripts/validate-current-task-authority.rb"
  [[ -f "$validator" && ! -L "$validator" ]] ||
    fail "main authority validator missing, non-regular, or symlinked"
  (
    cd "$repo_root"
    ruby "$validator"
  )
}

check_unique_p1_safety() {
  local truth_path="$1"
  ruby -ryaml -rpathname -e '
    def stop!(message)
      abort("P1_SAFETY_UNIQUE: NON_PASS #{message}")
    end

    def mapping!(value, label)
      stop!("#{label} missing or not a mapping") unless value.is_a?(Hash)
      value
    end

    def sequence!(value, label)
      stop!("#{label} missing or not a sequence") unless value.is_a?(Array)
      value
    end

    def safe_relative!(value, label)
      stop!("#{label} missing or empty") unless value.is_a?(String) && !value.empty?
      path = Pathname.new(value)
      stop!("#{label} must be repository-relative") if path.absolute?
      parts = path.each_filename.to_a
      stop!("#{label} contains unsafe traversal") if
        parts.empty? || parts.any? { |part| part.empty? || part == ".." }
      clean = path.cleanpath.to_s
      stop!("#{label} must be normalized") unless clean == value
      clean
    end

    def within?(path, root)
      path == root || path.start_with?(root + "/")
    end

    false_effects = {
      "network" => false,
      "provider" => false,
      "secret" => false,
      "remote" => false,
      "production" => false,
      "public" => false
    }
    forbidden_capabilities = %w[
      P2_REPOSITORY_INTELLIGENCE_CAPABILITY_CLAIM
      P3_SINGLE_AGENT_RUNTIME
      AGENT_SHELL
      MODEL_INITIATED_CANONICAL_WRITE
      PLATFORM_IDENTITY
      SUPERVISOR
      ROOT_CUSTODY
      STRONG_ISOLATION
      MULTI_AGENT_RUNTIME
    ]

    truth_path = Pathname.new(ARGV.fetch(0))
    stop!("Truth missing, non-regular, or symlinked") unless
      truth_path.file? && !truth_path.symlink?
    truth = YAML.safe_load(
      truth_path.binread,
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
    mapping!(truth, "Truth")

    project = mapping!(truth["project"], "project")
    stop!("current phase must remain P1") unless project["current_phase"] == "P1"
    stop!("P0 must remain complete") unless project["p0_status"] == "COMPLETE"
    stop!("P1 entry must remain authorized") unless project["p1_entry_status"] == "AUTHORIZED"

    boundary = mapping!(truth["phase_boundary"], "phase_boundary")
    stop!("phase boundary must remain P1") unless boundary["phase"] == "P1"
    task_kinds = sequence!(boundary["allowed_task_kinds"], "phase_boundary.allowed_task_kinds")
    stop!("P1 task kinds drifted") unless
      !task_kinds.empty? &&
      task_kinds.all? { |kind| kind.is_a?(String) && kind.start_with?("EVALUATION_FOUNDATION_") }

    allowed = sequence!(boundary["allowed_capabilities"], "phase_boundary.allowed_capabilities")
    stop!("P1 admits a deferred capability") unless (allowed & forbidden_capabilities).empty?
    deferred = sequence!(boundary["deferred_capabilities"], "phase_boundary.deferred_capabilities")
    stop!("P1 deferred capability set is incomplete") unless
      (forbidden_capabilities - deferred).empty?
    stop!("P1 default external effects drifted") unless
      boundary["default_external_effects"] == false_effects

    role_roots = mapping!(boundary["role_write_roots"], "phase_boundary.role_write_roots")
    repository_roots = []
    role_roots.each do |role, roots|
      next if role == "external_evidence"
      entries = roots.is_a?(Array) ? roots : [roots]
      stop!("phase boundary write roots invalid for #{role}") if entries.empty?
      entries.each_with_index do |entry, index|
        repository_roots << safe_relative!(
          entry,
          "phase_boundary.role_write_roots.#{role}[#{index}]"
        )
      end
    end
    repository_roots.uniq!
    stop!("P1 repository write roots are empty") if repository_roots.empty?

    route = mapping!(truth["current_phase_route"], "current_phase_route")
    route_roots = sequence!(
      route.fetch("additional_write_roots", []),
      "current_phase_route.additional_write_roots"
    )
    route_roots.each_with_index do |entry, index|
      path = safe_relative!(entry, "current_phase_route.additional_write_roots[#{index}]")
      stop!("route write root is outside the P1 boundary: #{path}") unless
        repository_roots.any? { |root| within?(path, root) }
    end

    puts "P1_SAFETY_UNIQUE: PASS"
  ' "$truth_path"
}

command -v ruby >/dev/null 2>&1 || fail "ruby is required"
command -v git >/dev/null 2>&1 || fail "git is required"

if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == "--check-current-p1-route" ]] ||
    fail "unsupported arguments"
  TRUTH_PATH="$2"
  ROOT_DIR="$(repo_root_for_truth "$TRUTH_PATH")"
else
  [[ -f "$TRUTH_PATH" && ! -L "$TRUTH_PATH" ]] ||
    fail "canonical Truth missing, non-regular, or symlinked"
  tracked_audit_paths="$(git -C "$ROOT_DIR" ls-files |
    grep -E '(^|/)\.sourcelens-audit(/|$)' || true)"
  [[ -z "$tracked_audit_paths" ]] ||
    fail "external Evidence material leaked into Git: ${tracked_audit_paths}"
fi

# This is the only Task/route accounting decision. Its exact PASS/NON_PASS
# output and exit status are intentionally propagated without reinterpretation.
run_authority_core "$ROOT_DIR"
check_unique_p1_safety "$TRUTH_PATH"

if [[ $# -gt 0 ]]; then
  echo "Current P1 route safety validation passed."
else
  echo "P1 basic safety boundary validation passed (current cooperative-local route only)."
fi

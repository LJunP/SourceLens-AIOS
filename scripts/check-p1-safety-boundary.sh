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

ruby -ryaml -rjson -rdigest -e '
  harness = YAML.safe_load(File.read("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml"), aliases: false)
  abort "P1-001 network must remain disabled" unless harness.dig("environment", "network") == "disabled"
  abort "P1-001 provider must remain none" unless harness.dig("environment", "provider") == "none"
  abort "P1-001 secrets must remain none" unless harness.dig("environment", "secrets") == "none"
  abort "P1-001 task worktree write boundary widened" unless harness.dig("environment", "task_worktree_write") == "exact_owned_paths_only"
  abort "P1-001 canonical main write must remain forbidden" unless harness.dig("environment", "canonical_main_write") == "forbidden"
  abort "P1-001 system-under-test write must remain forbidden" unless harness.dig("environment", "system_under_test_checkout_write") == "forbidden"
  abort "P1-001 remote effects must remain forbidden" unless harness.dig("environment", "remote_effects") == "forbidden"
  abort "P1-001 production effects must remain forbidden" unless harness.dig("environment", "production_effects") == "forbidden"

  task_path = "docs/aios/tasks/P1-003_PILOT_TASK_DATASET_AND_HIDDEN_SET_CURATION.yaml"
  task_sha = "8dec9d7b12df2e31c62e9ce146938c8a192b4751ce3a9aced3ccd38414fd0aa6"
  authorization_path = "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  authorization_sha = "1082f0a81eb41a1fae9a1767d421bb0fe8f11810bccba197ad18e3e430762a1b"
  parent_binding_path = "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/IMPLEMENTATION_PARENT_BINDING_RECORD.json"
  parent_binding_sha = "ead76e3b06eb2c509ec0ee66df72af4756be946f5f75f2801d4b75a92a1b6774"
  abort "P1-003 Task Contract identity drift" unless Digest::SHA256.file(task_path).hexdigest == task_sha
  abort "P1-003 authorization missing" unless File.file?(authorization_path)
  abort "P1-003 authorization identity drift" unless Digest::SHA256.file(authorization_path).hexdigest == authorization_sha
  abort "P1-003 implementation parent binding missing" unless File.file?(parent_binding_path)
  abort "P1-003 implementation parent binding identity drift" unless Digest::SHA256.file(parent_binding_path).hexdigest == parent_binding_sha
  task = YAML.safe_load(File.read(task_path), aliases: false)
  authorization = JSON.parse(File.read(authorization_path))
  parent_binding = JSON.parse(File.read(parent_binding_path))
  truth = YAML.safe_load(File.read("docs/aios/truth/project_state.yaml"), aliases: false)

  abort "P1-003 implementation authority state drift" unless truth.dig("project", "p1_execution_status") == "ACTIVE_AUTHORIZED_FOR_IMPLEMENTATION" && truth.dig("active_work", "current_task_status") == "ACTIVE_AUTHORIZED_FOR_IMPLEMENTATION"
  implementation_binding = truth.dig("active_work", "implementation_parent_binding")
  abort "P1-003 implementation parent path drift" unless implementation_binding["path"] == parent_binding_path && implementation_binding["sha256"] == parent_binding_sha
  abort "P1-003 implementation parent commit/tree drift" unless implementation_binding["implementation_parent_commit"] == "b9cbbf64b7fa98e7dfd30f752085f40104571957" && implementation_binding["implementation_parent_tree"] == "0580f4de27e4c6b18dbb7f170ba659e2b38ffba2"
  abort "P1-003 implementation binding widened scope" unless implementation_binding.values_at("scope_expansion", "main_advance", "baseline_execution") == [false, false, false]
  abort "P1-003 implementation next action drift" unless truth.dig("active_work", "next_eligible_action") == "CREATE_EXACT_P1_003_TASK_BRANCH_AND_WORKTREE"
  abort "P1-003 parent binding authorization drift" unless parent_binding["parent_authorization_sha256"] == authorization_sha && parent_binding["execution_nonce"] == authorization["execution_nonce"]
  abort "P1-003 parent binding scope widened" unless parent_binding.values_at("scope_expansion", "main_advance", "baseline_execution") == [false, false, false]
  abort "P1-003 acquisition contract must remain draft-only" unless task.dig("proposed_network_boundary", "current_status") == "NOT_AUTHORIZED_BY_THIS_DRAFT"
  abort "P1-003 network protocol widened" unless task.dig("proposed_network_boundary", "allowed_protocols") == ["HTTPS"]
  expected_hosts = %w[github.com api.github.com codeload.github.com raw.githubusercontent.com repo.maven.apache.org]
  abort "P1-003 network host allowlist drift" unless task.dig("proposed_network_boundary", "exact_hosts") == expected_hosts
  forbidden_operations = task.dig("proposed_network_boundary", "forbidden_operations") || []
  abort "P1-003 authenticated network prohibition missing" unless forbidden_operations.any? { |entry| entry.include?("authenticated request") && entry.include?("Provider credential") }
  abort "P1-003 remote-write prohibition missing" unless forbidden_operations.any? { |entry| entry.include?("Git receive-pack") && entry.include?("remote write") }
  abort "P1-003 acquisition executed source" unless task.dig("environment_and_oracle_rules", "acquisition_stage", "third_party_code_execution") == "forbidden"
  abort "P1-003 acquisition installed dependencies" unless task.dig("environment_and_oracle_rules", "acquisition_stage", "dependency_install_or_build") == "forbidden"
  verification = task.dig("environment_and_oracle_rules", "verification_stage")
  %w[network secrets provider remote_effects production_effects].each do |field|
    abort "P1-003 verification safety boundary widened: #{field}" unless verification[field] == "forbidden"
  end
  minimum_boundary = verification.fetch("minimum_environment_boundary")
  abort "P1-003 OCI network boundary widened" unless minimum_boundary["network"] == "none"
  abort "P1-003 OCI Secret boundary widened" unless minimum_boundary["secrets"] == "none"
  abort "P1-003 OCI user boundary widened" unless minimum_boundary["user"] == "non_root"
  abort "P1-003 OCI root filesystem became writable" unless minimum_boundary["root_filesystem"] == "read_only"
  abort "P1-003 OCI capabilities widened" unless minimum_boundary["capabilities"] == "drop_all" && minimum_boundary["privileged"] == false

  budget = task.fetch("budget")
  abort "P1-003 model/provider/baseline execution enabled" unless budget.values_at("model_calls", "provider_calls", "baseline_runs") == [0, 0, 0]
  abort "P1-003 remote/production/public effects enabled" unless budget.values_at("remote_writes", "production_effects", "public_releases") == [0, 0, 0]
  abort "P1-003 new runtime or sandbox enabled" unless budget.values_at("new_runtime_services", "new_sandbox_or_execution_carrier") == [0, 0]
  scope = authorization.fetch("authorized_scope")
  abort "P1-003 main advance authorized" unless scope["main_advance"] == false
  abort "P1-003 baseline execution authorized" unless scope["baseline_execution"] == false
  abort "P1-003 Provider call budget widened" unless authorization.dig("budgets", "provider_calls") == 0
  abort "P1-003 remote write budget widened" unless authorization.dig("budgets", "remote_writes") == 0
  abort "P1-003 production effect budget widened" unless authorization.dig("budgets", "production_effects") == 0
  abort "P1-003 public release budget widened" unless authorization.dig("budgets", "public_releases") == 0
  abort "P1-003 authenticated network was authorized" unless authorization.fetch("explicit_non_authorizations").include?("authenticated network")
  abort "P1-003 Secret use was authorized" unless authorization.fetch("explicit_non_authorizations").include?("Provider or Secret use")
  abort "P1-003 remote write was authorized" unless authorization.fetch("explicit_non_authorizations").include?("remote write")
  abort "P1-003 production effect was authorized" unless authorization.fetch("explicit_non_authorizations").include?("production effect")
' || fail "P1 task safety declaration invalid"

echo "P1 basic safety boundary validation passed (declarative/cooperative-local scope only)."

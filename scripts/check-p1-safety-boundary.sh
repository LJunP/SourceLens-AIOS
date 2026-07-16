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

  p1_004_task_path = "docs/aios/tasks/P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION.yaml"
  p1_004_task_sha = "0551602b5a330fc6d7920d048bba33caae9c5a0358c0bf57ef40cf7a63eaec6f"
  p1_004_authorization_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-task-contract-20260716T002125Z/revision-2/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  p1_004_authorization_sha = "3979871bfa949c2f613f30c5169880e6bb02131f690298b446b0c831e147517e"
  p1_004_execution_root = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-parameterized-harness-admission-execution-20260716T002125Z"
  p1_004_stop_path = "#{p1_004_execution_root}/terminal/TERMINAL_STOP_RECORD.json"
  p1_004_stop_sha = "ba3a50a97fe3bfd79c2568c13108828326dbba820cd2eef53e38fc54cd0bced3"
  p1_004_manifest_path = "#{p1_004_execution_root}/terminal/TERMINAL_EVIDENCE_MANIFEST.json"
  p1_004_manifest_sha = "201bcf229c3179f882a066173401c3b335c7dc36fea1828fc43d7cda6b7a9320"
  p1_004_seal_path = "#{p1_004_execution_root}/terminal/TERMINAL_SEAL.json"
  p1_004_seal_sha = "2bb0a14c832567feb89f6fb71e6ab88c338a4308669928399e8c2364f6553875"
  p1_004_restore_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-terminal-closure-verification-20260716T041834Z/OFFSITE_RESTORE_VERIFICATION_RECEIPT.json"
  p1_004_restore_sha = "15e92ebef2a234652e1d42a2aaa7e42fdffc9466e5f4fd94447f136a0ab56368"
  {
    p1_004_task_path => p1_004_task_sha,
    p1_004_authorization_path => p1_004_authorization_sha,
    p1_004_stop_path => p1_004_stop_sha,
    p1_004_manifest_path => p1_004_manifest_sha,
    p1_004_seal_path => p1_004_seal_sha,
    p1_004_restore_path => p1_004_restore_sha
  }.each do |path, expected|
    abort "P1-004 terminal custody artifact missing: #{path}" unless File.file?(path)
    abort "P1-004 terminal custody artifact drift: #{path}" unless Digest::SHA256.file(path).hexdigest == expected
  end
  p1_004_task = YAML.safe_load(File.read(p1_004_task_path), aliases: false)
  p1_004_authorization = JSON.parse(File.read(p1_004_authorization_path))
  p1_004_stop = JSON.parse(File.read(p1_004_stop_path))
  p1_004_manifest = JSON.parse(File.read(p1_004_manifest_path))
  p1_004_seal = JSON.parse(File.read(p1_004_seal_path))
  p1_004_restore = JSON.parse(File.read(p1_004_restore_path))

  task_path = "docs/aios/tasks/P1-003_PILOT_TASK_DATASET_AND_HIDDEN_SET_CURATION.yaml"
  task_sha = "8dec9d7b12df2e31c62e9ce146938c8a192b4751ce3a9aced3ccd38414fd0aa6"
  authorization_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  authorization_sha = "1082f0a81eb41a1fae9a1767d421bb0fe8f11810bccba197ad18e3e430762a1b"
  parent_binding_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/IMPLEMENTATION_PARENT_BINDING_RECORD.json"
  parent_binding_sha = "ead76e3b06eb2c509ec0ee66df72af4756be946f5f75f2801d4b75a92a1b6774"
  correction_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-pilot-dataset-v0.1/integration/P1_003_TERMINAL_CLASSIFICATION_CORRECTION_RECORD.json"
  correction_sha = "4ec9307bb7b4ea2fc807d8e34769592e8a1bf661c77e4962699f39328cc9ed8c"
  manifest_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-pilot-dataset-v0.1/integration/TERMINAL_EVIDENCE_MANIFEST_V2.json"
  manifest_sha = "76083450ff7da28eef4f264b3cb15c684207af69997b89d3515ae695d6c9ddf1"
  overall_stop_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-terminal-relocation-20260715T145418Z/P1_003_STOPPED_STATE_RECOVERY_AND_CANONICAL_CUTOVER_TERMINAL_STOP_RECORD.json"
  overall_stop_sha = "fd2b0b1947a9fbbf8f10294106a7abeadd3f42658b6f629fab2dfdd2567d89fa"
  hidden_public_receipt_path = "/Volumes/lijp/SourceLens-AIOS-P1-003-terminal-relocation-20260715T145418Z/visible/evidence/HIDDEN_OFFSITE_PUBLIC_RECEIPT.json"
  hidden_public_receipt_sha = "f249c9703de977e513890b0cf592ce52ce050996482e615270d22add4067b8a7"
  abort "P1-003 Task Contract identity drift" unless Digest::SHA256.file(task_path).hexdigest == task_sha
  {
    authorization_path => authorization_sha,
    parent_binding_path => parent_binding_sha,
    correction_path => correction_sha,
    manifest_path => manifest_sha,
    overall_stop_path => overall_stop_sha
  }.each do |path, expected|
    abort "P1-003 custody Evidence missing: #{path}" unless File.file?(path)
    abort "P1-003 custody Evidence identity drift: #{path}" unless Digest::SHA256.file(path).hexdigest == expected
  end
  task = YAML.safe_load(File.read(task_path), aliases: false)
  authorization = JSON.parse(File.read(authorization_path))
  parent_binding = JSON.parse(File.read(parent_binding_path))
  correction = JSON.parse(File.read(correction_path))
  manifest = JSON.parse(File.read(manifest_path))
  overall_stop = JSON.parse(File.read(overall_stop_path))
  truth = YAML.safe_load(File.read("docs/aios/truth/project_state.yaml"), aliases: false)

  exact_terminal_status = "TERMINAL_STOPPED_BEFORE_INTEGRATION_ACQUISITION_EVIDENCE_INTEGRITY_FAILURE"
  abort "P1 Task execution unexpectedly authorized" unless truth.dig("project", "p1_execution_status") == "NO_ACTIVE_TASK_AUTHORIZED"
  abort "canonical repository drift" unless truth.dig("project", "canonical_repository") == "/Users/lijunpeng/Developer/SourceLens-AIOS"
  abort "old Desktop repository remains canonical" if truth.dig("project", "canonical_repository") == "/Users/lijunpeng/Desktop/cc/project/SourceLens-AIOS"
  abort "current Task or authorization unexpectedly active" unless truth.dig("active_work", "current_task") == "NONE" && truth.dig("active_work", "current_task_status") == "NONE" && truth.dig("active_work", "current_execution_authorization") == "NONE"
  abort "next action bypasses Founder Task selection" unless truth.dig("active_work", "next_eligible_action") == "FOUNDER_SELECT_NEXT_P1_REAL_ENGINEERING_TASK"
  p1_004_id = "AIOS-P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION"
  p1_004_state = "TERMINAL_STOPPED_AFTER_UNAUTHORIZED_TRANSIENT_EFFECT_AND_INDEPENDENT_REVIEW_FAIL"
  abort "P1-004 Contract identity drift" unless p1_004_task["task_id"] == p1_004_id && p1_004_task["phase"] == "P1"
  abort "P1-004 Contract self-authorized" unless p1_004_task["status"] == "FOUNDER_EXECUTION_AUTHORIZATION_REQUIRED" && p1_004_task["execution_authorized"] == false
  p1_004_environment = p1_004_task.fetch("environment")
  %w[network provider secrets remote_effects production_effects public_release].each do |field|
    abort "P1-004 historical safety boundary widened: #{field}" unless p1_004_environment[field] == "forbidden"
  end
  p1_004_budget = p1_004_task.fetch("budget")
  abort "P1-004 external effect budget widened" unless p1_004_budget.values_at("network_calls", "provider_calls", "model_calls", "remote_writes", "production_effects") == [0, 0, 0, 0, 0]
  abort "P1-004 retry boundary widened" unless p1_004_budget["measurement_retries"] == 0 && p1_004_task.dig("delegated_execution", "retry_or_successor_task") == "forbidden"
  abort "P1-004 capture-time authorization binding drift" unless p1_004_authorization["status"] == "AUTHORIZED_ACTIVE" && p1_004_authorization["task_id"] == p1_004_id && p1_004_authorization.dig("task_contract", "sha256") == p1_004_task_sha
  abort "P1-004 authorization external boundary widened" unless p1_004_authorization["b0_b1_b2_authorized"] == false && p1_004_authorization["p2_p3_authorized"] == false && p1_004_authorization["automatic_main_advance"] == false && p1_004_authorization["automatic_next_task"] == false
  abort "P1-004 terminal state drift" unless p1_004_stop["task_id"] == p1_004_id && p1_004_stop["task_state"] == p1_004_state
  abort "P1-004 terminal reason drift" unless p1_004_stop.dig("failure", "reason_code") == "UNAUTHORIZED_TRANSIENT_EFFECT" && p1_004_stop.dig("failure", "contract_effect") == "STOP_TASK"
  abort "P1-004 nonce not retired" unless p1_004_stop.dig("nonce_state", "status") == "RETIRED_AFTER_TASK_STOP"
  abort "P1-004 candidate falsely accepted" unless p1_004_stop.dig("worker_candidate", "accepted") == false && p1_004_stop.dig("founder_gate", "status") == "NOT_REACHED"
  abort "P1-004 terminal manifest population drift" unless p1_004_manifest["artifact_count"] == 12 && p1_004_manifest["root_sha256"] == "f2d40a99178fe0b1dff221b1b5b0e85116aafe357d93bb028b676ca8185e530c"
  abort "P1-004 terminal Seal drift" unless p1_004_seal["task_id"] == p1_004_id && p1_004_seal["task_state"] == p1_004_state && p1_004_seal.dig("terminal_stop_record", "sha256") == p1_004_stop_sha && p1_004_seal.dig("terminal_evidence_manifest", "sha256") == p1_004_manifest_sha
  abort "P1-004 offsite restore is not PASS" unless p1_004_restore["result"] == "PASS" && p1_004_restore.dig("claim_boundary", "candidate_accepted") == false && p1_004_restore.dig("claim_boundary", "p1_004_capability_claims") == 0
  p1_004_history = truth.dig("task_history", "aios_p1_004")
  abort "P1-004 terminal history missing" unless p1_004_history.is_a?(Hash)
  abort "P1-004 terminal history drift" unless p1_004_history["status"] == p1_004_state && p1_004_history["execution_authorized"] == false && p1_004_history["execution_nonce_status"] == "RETIRED_AFTER_TASK_STOP" && p1_004_history["resume_retry_successor_allowed"] == false
  abort "P1-004 cleanup failed" unless p1_004_history.dig("terminal_cleanup", "restore_status") == "PASS" && p1_004_history.dig("terminal_cleanup", "task_branch_removed") == true && p1_004_history.dig("terminal_cleanup", "task_worktree_removed") == true
  abort "P1-004 claim boundary widened" unless truth.dig("claim_boundary", "p1_004_parameterized_harness_admission") == "TERMINAL_STOPPED_NOT_ACCEPTED" && truth.dig("claim_boundary", "p1_004_worker_candidate_accepted") == false && truth.dig("claim_boundary", "p1_004_capability_claims") == 0
  abort "P1-003 terminal status drift" unless truth.dig("task_history", "aios_p1_003", "status") == exact_terminal_status
  abort "P1-003 recovery was enabled" unless truth.dig("task_history", "aios_p1_003", "resume_retry_successor_allowed") == false
  abort "P1-003 nonce not retired" unless truth.dig("task_history", "aios_p1_003", "authorization_history", "execution_nonce_status") == "RETIRED"
  abort "P1-003 Evidence integrity falsely passed" unless truth.dig("task_history", "aios_p1_003", "evidence_integrity") == "FAIL"
  abort "P1-003 hidden custody not quarantined" unless truth.dig("task_history", "aios_p1_003", "hidden_custody", "status") == "QUARANTINED_HISTORICAL_RISK"
  abort "P1-003 hidden custody became a PASS" unless truth.dig("task_history", "aios_p1_003", "hidden_custody", "restore_verification") == "NON_PASS_AGGREGATE_RESTORE_MISMATCH" && truth.dig("task_history", "aios_p1_003", "hidden_custody", "pass_receipt_generated") == false
  abort "primary Agent hidden access was authorized" unless truth.dig("task_history", "aios_p1_003", "hidden_custody", "hidden_contents_or_paths_authorized_for_primary_agent") == false
  abort "generic custodian artifact-name observation was erased" unless truth.dig("task_history", "aios_p1_003", "hidden_custody", "generic_custodian_artifact_names_observed") == true
  abort "hidden dataset identity or content access was falsely recorded" unless truth.dig("task_history", "aios_p1_003", "hidden_custody", "hidden_dataset_identity_or_content_accessed") == false
  abort "hidden private file content access was falsely recorded" unless truth.dig("task_history", "aios_p1_003", "hidden_custody", "hidden_private_file_contents_read") == false
  abort "hidden public receipt locator drift" unless truth.dig("task_history", "aios_p1_003", "hidden_custody", "public_receipt_path") == hidden_public_receipt_path && truth.dig("task_history", "aios_p1_003", "hidden_custody", "public_receipt_sha256") == hidden_public_receipt_sha
  abort "P1-003 terminal correction drift" unless correction["corrected_status"] == exact_terminal_status && correction["task_remains_terminal"] == true
  abort "P1-003 terminal manifest drift" unless manifest["status"] == exact_terminal_status
  abort "overall stop task state drift" unless overall_stop["task_state"] == exact_terminal_status
  hidden_stop_evidence = overall_stop.fetch("decisive_non_pass_evidence")
  abort "overall stop public receipt binding drift" unless hidden_stop_evidence["public_aggregate_receipt_path"] == hidden_public_receipt_path && hidden_stop_evidence["public_aggregate_receipt_sha256"] == hidden_public_receipt_sha
  abort "overall stop hidden restore status drift" unless hidden_stop_evidence["restore_verification"] == "NON_PASS_AGGREGATE_RESTORE_MISMATCH" && hidden_stop_evidence["pass_receipt_generated"] == false && hidden_stop_evidence["retry_count"] == 0
  abort "overall stop hidden details access drift" unless hidden_stop_evidence["hidden_details_accessed_by_primary_agent"] == false
  cutover = truth.dig("task_history", "aios_p1_003", "canonical_cutover")
  abort "new canonical Task branch count drift" unless cutover["new_canonical_task_branch_count"] == 0
  abort "new canonical worktree count drift" unless cutover["new_canonical_worktree_count"] == 1
  abort "old Desktop cleanup policy drift" unless cutover["old_desktop_cleanup_policy"] == "REMOVE_ONLY_AFTER_ALL_CUTOVER_CHECKS_PASS"
  abort "historical governance lineages reopened" unless truth.dig("historical_lineages", "status") == "CLOSED_AND_EXCLUDED_FROM_DEFAULT_CONTEXT" && truth.dig("historical_lineages", "continuation_allowed") == false
  closed_lineages = truth.dig("historical_lineages", "names") || []
  %w[PRE PRE_DISCOVERY BOUND_EXP MCF EXECUTION_CARRIER SUPERVISOR_AND_ROOT_CUSTODY].each do |lineage|
    abort "historical lineage missing from closed set: #{lineage}" unless closed_lineages.include?(lineage)
  end
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

task_branches="$(git for-each-ref --format='%(refname:short)' refs/heads/task/)"
[[ -z "$task_branches" ]] || fail "no Task is authorized but local Task branch exists: $task_branches"
worktree_paths="$(git worktree list --porcelain | sed -n 's/^worktree //p')"
worktree_count="$(printf '%s\n' "$worktree_paths" | grep -c . || true)"
[[ "$worktree_count" -eq 1 && "$worktree_paths" == "$ROOT_DIR" ]] || fail "no Task is authorized but worktree population is not exactly the canonical repository"

echo "P1 basic safety boundary validation passed (declarative/cooperative-local scope only)."

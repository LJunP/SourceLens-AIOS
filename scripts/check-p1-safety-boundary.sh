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

  active_task_path = "docs/aios/tasks/P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION.yaml"
  active_task_sha = "0551602b5a330fc6d7920d048bba33caae9c5a0358c0bf57ef40cf7a63eaec6f"
  active_authorization_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-task-contract-20260716T002125Z/revision-2/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  active_authorization_sha = "3979871bfa949c2f613f30c5169880e6bb02131f690298b446b0c831e147517e"
  abort "P1-004 Task Contract missing" unless File.file?(active_task_path)
  abort "P1-004 Task Contract identity drift" unless Digest::SHA256.file(active_task_path).hexdigest == active_task_sha
  abort "P1-004 Founder authorization missing" unless File.file?(active_authorization_path)
  abort "P1-004 Founder authorization identity drift" unless Digest::SHA256.file(active_authorization_path).hexdigest == active_authorization_sha
  active_task = YAML.safe_load(File.read(active_task_path), aliases: false)
  active_authorization = JSON.parse(File.read(active_authorization_path))

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
  active_task_id = "AIOS-P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION"
  abort "P1 execution authorization state drift" unless truth.dig("project", "p1_execution_status") == "TASK_AUTHORIZED_PRE_IMPLEMENTATION"
  abort "canonical repository drift" unless truth.dig("project", "canonical_repository") == "/Users/lijunpeng/Developer/SourceLens-AIOS"
  abort "old Desktop repository remains canonical" if truth.dig("project", "canonical_repository") == "/Users/lijunpeng/Desktop/cc/project/SourceLens-AIOS"
  abort "current P1-004 Task binding drift" unless truth.dig("active_work", "current_task") == active_task_id && truth.dig("active_work", "current_task_status") == "FOUNDER_EXECUTION_AUTHORIZED_PRE_IMPLEMENTATION"
  abort "current P1-004 Contract binding drift" unless truth.dig("active_work", "current_task_contract") == active_task_path && truth.dig("active_work", "current_task_contract_sha256") == active_task_sha
  abort "current P1-004 authorization binding drift" unless truth.dig("active_work", "current_execution_authorization") == active_authorization_path && truth.dig("active_work", "current_execution_authorization_sha256") == active_authorization_sha
  abort "current P1-004 parent drift" unless truth.dig("active_work", "activation_parent_commit") == "48258805dfa5e7a9c6d04d23e699b1a4e7b56a33" && truth.dig("active_work", "activation_parent_tree") == "46c9540905db8d9bf3157929ecb45bf294352fd4"
  abort "current P1-004 resource binding drift" unless truth.dig("active_work", "task_branch") == "task/AIOS-P1-004-parameterized-harness-admission" && truth.dig("active_work", "task_worktree") == "/Users/lijunpeng/Developer/.sourcelens-worktrees/AIOS-P1-004-parameterized-harness-admission"
  abort "next action bypasses activation receipt" unless truth.dig("active_work", "next_eligible_action") == "VERIFY_P1_004_ACTIVATION_COMMIT_CREATE_ACTIVATION_RECEIPT_THEN_CREATE_EXACT_TASK_RESOURCES"
  abort "P1-004 Contract identity drift" unless active_task["task_id"] == active_task_id && active_task["phase"] == "P1"
  abort "P1-004 Contract self-authorized" unless active_task["status"] == "FOUNDER_EXECUTION_AUTHORIZATION_REQUIRED" && active_task["execution_authorized"] == false
  active_environment = active_task.fetch("environment")
  %w[network provider secrets remote_effects production_effects public_release].each do |field|
    abort "P1-004 safety boundary widened: #{field}" unless active_environment[field] == "forbidden"
  end
  active_budget = active_task.fetch("budget")
  abort "P1-004 external effect budget widened" unless active_budget.values_at("network_calls", "provider_calls", "model_calls", "remote_writes", "production_effects") == [0, 0, 0, 0, 0]
  abort "P1-004 retry boundary widened" unless active_budget["measurement_retries"] == 0 && active_task.dig("delegated_execution", "retry_or_successor_task") == "forbidden"
  abort "P1-004 authorization inactive" unless active_authorization["status"] == "AUTHORIZED_ACTIVE" && active_authorization["task_id"] == active_task_id
  abort "P1-004 authorization Contract drift" unless active_authorization.dig("task_contract", "sha256") == active_task_sha
  abort "P1-004 authorization Goal drift" unless active_authorization.dig("authority", "goal_canonical_sha256") == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "P1-004 authorization nonce drift" unless active_authorization["consumed_single_use_nonce"] == "0de2abda5280156daa0dcdce4f71109d6be6df280c06debee7df72c9171282c5"
  abort "P1-004 baseline or later phase authorization widened" unless active_authorization["b0_b1_b2_authorized"] == false && active_authorization["p2_p3_authorized"] == false
  abort "P1-004 automatic main/next Task enabled" unless active_authorization["automatic_main_advance"] == false && active_authorization["automatic_next_task"] == false
  expected_forbidden_effects = ["network", "Provider", "Secret", "remote", "production", "public release"]
  abort "P1-004 forbidden external effects drift" unless active_authorization["forbidden_external_effects"] == expected_forbidden_effects
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

ruby -rjson -rdigest -ropen3 -e '
  CANONICAL = "/Users/lijunpeng/Developer/SourceLens-AIOS"
  TASK_ID = "AIOS-P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION"
  TASK_BRANCH = "task/AIOS-P1-004-parameterized-harness-admission"
  TASK_WORKTREE = "/Users/lijunpeng/Developer/.sourcelens-worktrees/AIOS-P1-004-parameterized-harness-admission"
  EXECUTION_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-parameterized-harness-admission-execution-20260716T002125Z"
  RECEIPT_PATH = "#{EXECUTION_ROOT}/activation/ACTIVATION_RECEIPT.json"
  INDEX_PATH = "#{EXECUTION_ROOT}/activation/PRE_EXECUTION_EVIDENCE_INDEX.json"
  ACTIVATION_PARENT = "48258805dfa5e7a9c6d04d23e699b1a4e7b56a33"
  ACTIVATION_PARENT_TREE = "46c9540905db8d9bf3157929ecb45bf294352fd4"
  GOAL_SHA = "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  CONTRACT_SHA = "0551602b5a330fc6d7920d048bba33caae9c5a0358c0bf57ef40cf7a63eaec6f"
  AUTH_SHA = "3979871bfa949c2f613f30c5169880e6bb02131f690298b446b0c831e147517e"
  EXACT_PATHS = [
    "docs/aios/tasks/P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION.yaml",
    "docs/aios/truth/project_state.yaml",
    "scripts/validate-aios-governance.sh",
    "scripts/check-p1-safety-boundary.sh",
    "docs/PROJECT_CODE_MAP.md"
  ].freeze
  RECEIPT_KEYS = %w[
    schema_id task_id goal_sha256 activation_parent_commit activation_parent_tree
    activation_parent_count exact_changed_paths diff_sha256 activation_commit
    activation_tree full_verify_result full_verify_evidence_sha256
    task_contract_sha256 founder_execution_authorization_sha256
    pre_execution_evidence_index_core_sha256
  ].sort.freeze
  INDEX_CORE_KEYS = %w[
    schema_id task_id goal_sha256 task_contract_sha256
    founder_execution_authorization_sha256 activation_receipt_path
    activation_commit activation_tree full_verify_evidence_path
    full_verify_evidence_sha256
  ].freeze
  INDEX_KEYS = (INDEX_CORE_KEYS + %w[activation_receipt_sha256 core_sha256]).sort.freeze

  def git(*args)
    stdout, stderr, status = Open3.capture3("git", *args)
    abort "git #{args.join(" ")} failed: #{stderr}" unless status.success?
    stdout
  end

  def deep_sort(value)
    case value
    when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
    when Array then value.map { |item| deep_sort(item) }
    else value
    end
  end

  def canonical_json_file(path, value)
    expected = JSON.generate(deep_sort(value)) + "\n"
    abort "non-canonical JSON bytes: #{path}" unless File.binread(path) == expected
  end

  def parse_worktrees
    git("worktree", "list", "--porcelain").split(/\n\n+/).map do |block|
      next if block.empty?
      block.lines.each_with_object({}) do |line, record|
        key, value = line.chomp.split(" ", 2)
        record[key] = value || true
      end
    end.compact
  end

  def sha256_file(path)
    Digest::SHA256.file(path).hexdigest
  end

  receipt_exists = File.file?(RECEIPT_PATH)
  index_exists = File.file?(INDEX_PATH)
  task_branches = git("for-each-ref", "--format=%(refname:short)", "refs/heads/task/").lines.map(&:chomp).reject(&:empty?)
  worktrees = parse_worktrees
  canonical_entry = worktrees.find { |entry| entry["worktree"] == CANONICAL }
  abort "canonical worktree missing" unless canonical_entry && canonical_entry["branch"] == "refs/heads/main"
  canonical_head = git("-C", CANONICAL, "rev-parse", "HEAD").strip
  canonical_tree = git("-C", CANONICAL, "rev-parse", "HEAD^{tree}").strip

  if !receipt_exists && !index_exists && task_branches.empty?
    abort "PRE_RESOURCE must contain only the canonical worktree" unless worktrees.length == 1
    abort "PRE_RESOURCE canonical main moved before activation receipt" unless canonical_head == ACTIVATION_PARENT && canonical_tree == ACTIVATION_PARENT_TREE
    if File.exist?(EXECUTION_ROOT)
      abort "PRE_RESOURCE execution root is not a directory" unless File.directory?(EXECUTION_ROOT) && !File.symlink?(EXECUTION_ROOT)
      entries = Dir.glob("#{EXECUTION_ROOT}/**/*", File::FNM_DOTMATCH).reject { |path| [".", ".."].include?(File.basename(path)) }
      entries.each do |path|
        relative = path.delete_prefix("#{EXECUTION_ROOT}/")
        allowed_directory = File.directory?(path) && ["activation", "commands", "evidence"].include?(relative)
        allowed_file = File.file?(path) && relative == "activation/PRE_EXECUTION_ACTIVATION_PREFLIGHT.json"
        allowed = allowed_directory || allowed_file
        abort "PRE_RESOURCE contains non-preflight Task artifact: #{relative}" unless allowed
        abort "PRE_RESOURCE preflight path is a symlink: #{relative}" if File.symlink?(path)
      end
    end
  else
    abort "resource state is inconsistent: receipt/index/branch must activate together" unless receipt_exists && index_exists && task_branches == [TASK_BRANCH]
    abort "ACTIVE_RESOURCE execution root missing" unless File.directory?(EXECUTION_ROOT) && !File.symlink?(EXECUTION_ROOT)
    abort "Activation Receipt or index is a symlink" if File.symlink?(RECEIPT_PATH) || File.symlink?(INDEX_PATH)
    abort "ACTIVE_RESOURCE canonical worktree must be clean" unless git("-C", CANONICAL, "status", "--porcelain").empty?

    receipt = JSON.parse(File.read(RECEIPT_PATH))
    index = JSON.parse(File.read(INDEX_PATH))
    canonical_json_file(RECEIPT_PATH, receipt)
    canonical_json_file(INDEX_PATH, index)
    abort "Activation Receipt schema is not closed" unless receipt.keys.sort == RECEIPT_KEYS
    abort "pre-execution Evidence index schema is not closed" unless index.keys.sort == INDEX_KEYS
    abort "Activation Receipt schema drift" unless receipt["schema_id"] == "sourcelens-aios.p1-004-activation-receipt.v1"
    abort "pre-execution Evidence index schema drift" unless index["schema_id"] == "sourcelens-aios.p1-004-pre-execution-evidence-index.v1"
    [receipt, index].each do |record|
      abort "P1-004 resource Task binding drift" unless record["task_id"] == TASK_ID
      abort "P1-004 resource Goal binding drift" unless record["goal_sha256"] == GOAL_SHA
      abort "P1-004 resource Contract binding drift" unless record["task_contract_sha256"] == CONTRACT_SHA
      abort "P1-004 resource authorization binding drift" unless record["founder_execution_authorization_sha256"] == AUTH_SHA
    end
    abort "Activation Receipt parent drift" unless receipt["activation_parent_commit"] == ACTIVATION_PARENT && receipt["activation_parent_tree"] == ACTIVATION_PARENT_TREE && receipt["activation_parent_count"] == 1
    abort "Activation Receipt path population drift" unless receipt["exact_changed_paths"] == EXACT_PATHS
    abort "Activation Receipt full verification is not PASS" unless receipt["full_verify_result"] == "PASS"
    %w[diff_sha256 full_verify_evidence_sha256 pre_execution_evidence_index_core_sha256].each do |field|
      abort "Activation Receipt #{field} is not a SHA-256" unless receipt[field].is_a?(String) && receipt[field].match?(/\A[0-9a-f]{64}\z/)
    end

    activation_commit = receipt.fetch("activation_commit")
    activation_tree = receipt.fetch("activation_tree")
    abort "invalid activation commit identity" unless activation_commit.match?(/\A[0-9a-f]{40}\z/)
    abort "invalid activation tree identity" unless activation_tree.match?(/\A[0-9a-f]{40}\z/)
    abort "activation commit tree drift" unless git("rev-parse", "#{activation_commit}^{tree}").strip == activation_tree
    parent_line = git("rev-list", "--parents", "-n", "1", activation_commit).split
    abort "activation commit must have exactly one parent" unless parent_line == [activation_commit, ACTIVATION_PARENT]
    changed_paths = git("diff", "--name-only", ACTIVATION_PARENT, activation_commit, "--").lines.map(&:chomp).reject(&:empty?)
    abort "activation commit changed-path population drift" unless changed_paths.sort == EXACT_PATHS.sort
    diff_bytes = git("diff", "--binary", "--full-index", "--no-color", ACTIVATION_PARENT, activation_commit, "--", *EXACT_PATHS)
    abort "activation diff SHA-256 drift" unless receipt["diff_sha256"] == Digest::SHA256.hexdigest(diff_bytes)
    abort "ACTIVE_RESOURCE canonical main is not the receipt-bound activation commit" unless canonical_head == activation_commit && canonical_tree == activation_tree

    index_core_bytes = INDEX_CORE_KEYS.map { |key| "#{key}=#{index.fetch(key)}\n" }.join
    index_core_sha = Digest::SHA256.hexdigest(index_core_bytes)
    abort "pre-execution Evidence index core SHA-256 drift" unless index["core_sha256"] == index_core_sha
    abort "Activation Receipt does not bind the index core" unless receipt["pre_execution_evidence_index_core_sha256"] == index_core_sha
    abort "pre-execution Evidence index receipt path drift" unless index["activation_receipt_path"] == RECEIPT_PATH
    abort "pre-execution Evidence index does not bind the receipt bytes" unless index["activation_receipt_sha256"] == sha256_file(RECEIPT_PATH)
    abort "pre-execution Evidence index activation identity drift" unless index["activation_commit"] == activation_commit && index["activation_tree"] == activation_tree
    abort "full verification Evidence binding mismatch" unless index["full_verify_evidence_sha256"] == receipt["full_verify_evidence_sha256"]
    full_verify_path = File.expand_path(index.fetch("full_verify_evidence_path"))
    activation_root = File.join(EXECUTION_ROOT, "activation") + "/"
    abort "full verification Evidence escapes activation root" unless full_verify_path.start_with?(activation_root)
    abort "full verification Evidence aliases receipt/index" if [RECEIPT_PATH, INDEX_PATH].include?(full_verify_path)
    abort "full verification Evidence missing" unless File.file?(full_verify_path) && !File.symlink?(full_verify_path)
    relative_parts = full_verify_path.delete_prefix(activation_root).split("/")
    cursor = activation_root.delete_suffix("/")
    relative_parts.each do |part|
      cursor = File.join(cursor, part)
      abort "full verification Evidence path contains a symlink" if File.symlink?(cursor)
    end
    abort "full verification Evidence SHA-256 drift" unless sha256_file(full_verify_path) == index["full_verify_evidence_sha256"]

    task_ref = git("rev-parse", "refs/heads/#{TASK_BRANCH}").strip
    abort "Task branch is not based on the exact activation commit" unless git("merge-base", activation_commit, task_ref).strip == activation_commit
    abort "Task branch contains a merge commit after activation" unless git("rev-list", "--merges", "#{activation_commit}..#{task_ref}").strip.empty?
    abort "ACTIVE_RESOURCE worktree population must be canonical plus exact Task" unless worktrees.length == 2
    task_entry = worktrees.find { |entry| entry["worktree"] == TASK_WORKTREE }
    abort "exact Task worktree missing or detached" unless task_entry && task_entry["branch"] == "refs/heads/#{TASK_BRANCH}"
    abort "Task worktree HEAD does not equal exact Task ref" unless task_entry["HEAD"] == task_ref
  end
' || fail "P1-004 PRE_RESOURCE/ACTIVE_RESOURCE validation failed"

echo "P1 basic safety boundary validation passed (declarative/cooperative-local scope only)."

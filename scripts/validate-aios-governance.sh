#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "AIOS GOVERNANCE FAIL: $*" >&2
  exit 1
}

command -v ruby >/dev/null 2>&1 || fail "ruby is required"
command -v git >/dev/null 2>&1 || fail "git is required"

required_files=(
  AGENTS.md
  README.md
  ROADMAP.md
  docs/README.md
  docs/aios/README.md
  docs/aios/STRATEGIC_CONSTITUTION.md
  docs/aios/MASTER_EXECUTION_PROTOCOL.md
  docs/aios/EVALUATION_PROTOCOL.md
  docs/aios/MIGRATION_LEDGER.yaml
  docs/aios/BASELINE_ADAPTER_CONTRACT.md
  docs/aios/truth/project_state.yaml
  docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml
  docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml
  docs/aios/schemas/task-spec.schema.json
  docs/aios/schemas/environment-snapshot.schema.json
  docs/aios/schemas/system-configuration.schema.json
  docs/aios/schemas/run-record.schema.json
)

for file in "${required_files[@]}"; do
  [[ -s "$file" ]] || fail "required file missing or empty: $file"
done

ruby -ryaml -rjson -rdigest -e '
  truth = YAML.safe_load(File.read("docs/aios/truth/project_state.yaml"), aliases: false)
  task = YAML.safe_load(File.read("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml"), aliases: false)
  terminal_task = YAML.safe_load(File.read("docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml"), aliases: false)
  ledger = YAML.safe_load(File.read("docs/aios/MIGRATION_LEDGER.yaml"), aliases: false)

  expected_hashes = {
    "docs/aios/STRATEGIC_CONSTITUTION.md" => "040196be12532b8c3661665995d3e79a28d268a1ecc991623380f0939f468485",
    "docs/aios/MASTER_EXECUTION_PROTOCOL.md" => "47c444c50c7521a7515dfb2fbee0c8c81cc72b32c42eba549d080eeb0c1bcedf",
    "docs/aios/EVALUATION_PROTOCOL.md" => "da029143561fbb3c213d4a358b25e085542c6cd26ae8150a53cbb5998177eed8",
    "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml" => "d2974752b088ff30b0764d6b482e19ea939cd497eb2db3e26af28bf09dc2e12f",
    "docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml" => "c303f045e67dc1f76d51a5789eeb0573021bdcd9d17cd169d7448f64f91a87d8",
    "evaluation-harness/fixtures/oracle/FREEZE_RECEIPT.json" => "ef7f9807795a685d0aa92fc19248ed0101362861ad7d71e4fdcdbb9df0b840c6",
    "evaluation-harness/recording/aios-p1-001-evidence/evidence-manifest.json" => "e1f735816c18ab7631fa1d0b771deccc25564074350d1d74e67975d187ef3952"
  }
  expected_hashes.each do |path, expected|
    actual = Digest::SHA256.file(path).hexdigest
    abort "authority hash drift: #{path}" unless actual == expected
  end

  abort "truth schema drift" unless truth["schema_version"] == 3
  abort "phase must be P1" unless truth.dig("project", "current_phase") == "P1"
  abort "P0 must be complete" unless truth.dig("project", "p0_status") == "COMPLETE"
  abort "P1 entry must be authorized" unless truth.dig("project", "p1_entry_status") == "AUTHORIZED"
  abort "P1 execution authorization state drift" unless truth.dig("project", "p1_execution_status") == "NO_ACTIVE_TASK_AUTHORIZED"
  abort "accepted candidate commit drift" unless truth.dig("project", "accepted_harness_candidate_commit") == "02342da942e291eaa65230f824fcf47eae8f8a30"
  abort "accepted candidate tree drift" unless truth.dig("project", "accepted_harness_candidate_tree") == "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc"
  abort "active Goal state drift" unless truth.dig("goal", "control_plane_status_observed") == "ACTIVE"
  abort "active Goal canonical hash drift" unless truth.dig("goal", "observed_body_sha256") == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "active Goal raw hash drift" unless truth.dig("goal", "observed_raw_body_sha256") == "9b59ffc6919473b596f09a96afc1e8684f076f5ac32c6014ac96344a496cd0d8"
  abort "active Goal canonicalization drift" unless truth.dig("goal", "body_canonicalization") == "UTF8_LF_WITH_EXACTLY_ONE_TRAILING_LF"
  abort "active Goal identity state drift" unless truth.dig("goal", "identity_status") == "FOUNDER_MANUALLY_INSTALLED_AND_ACTIVE"
  terminal_task_id = "AIOS-P1-002_B0_ADAPTER_CONFORMANCE"
  terminal_task_path = "docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml"
  terminal_task_sha = "c303f045e67dc1f76d51a5789eeb0573021bdcd9d17cd169d7448f64f91a87d8"
  abort "Goal task authority must be NONE" unless truth.dig("goal", "current_task_authority") == "NONE"
  abort "current task must be NONE" unless truth.dig("active_work", "current_task") == "NONE"
  abort "current Task Contract must be NONE" unless truth.dig("active_work", "current_task_contract") == "NONE"
  abort "current execution authorization must be NONE" unless truth.dig("active_work", "current_execution_authorization") == "NONE"
  abort "next action drift" unless truth.dig("active_work", "next_eligible_action") == "FOUNDER_SELECT_NEXT_P1_TASK"
  abort "P1 idle boundary drift" unless truth.dig("p1_boundary", "allowed_now") == [
    "No P1 Task execution is currently authorized.",
    "Founder may select one next P1 Task after reading this terminal state; phase entry does not authorize execution."
  ]

  completed = truth.dig("task_history", "aios_p1_001")
  abort "P1-001 completion history missing" unless completed.is_a?(Hash)
  expected_completion = {
    "task_id" => "AIOS-P1-001",
    "contract" => "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml",
    "task_contract_sha256" => "d2974752b088ff30b0764d6b482e19ea939cd497eb2db3e26af28bf09dc2e12f",
    "status" => "FOUNDER_GATE_ACCEPTED_COMPLETE",
    "execution_authorized" => false,
    "persistent_evidence_runs" => 1,
    "measurement_retries" => 0,
    "capability_claims" => 0,
    "accepted_candidate_commit" => "02342da942e291eaa65230f824fcf47eae8f8a30",
    "accepted_candidate_tree" => "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc",
    "evidence_manifest_sha256" => "e1f735816c18ab7631fa1d0b771deccc25564074350d1d74e67975d187ef3952",
    "cto_review" => "PASS",
    "security_review" => "PASS",
    "quality_review" => "PASS",
    "founder_gate_decision" => "PASS"
  }
  expected_completion.each do |field, expected|
    abort "P1-001 completion drift: #{field}" unless completed[field] == expected
  end
  gate_record = completed.fetch("founder_gate_decision_record")
  abort "Founder Gate record path drift" unless gate_record["path"] == "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-001-founder-gate-20260715T093331Z/FOUNDER_GATE_DECISION_RECORD.json"
  abort "Founder Gate record hash drift" unless gate_record["sha256"] == "2bacd875f90619ccba19a2cc56a257721ab85b76bd8d3bc168dc50acec4deb72"

  authorization = completed.fetch("execution_authorization_history")
  expected_authorization = {
    "authority" => "Human Founder",
    "authorization_model" => "TASK_LEVEL_DELEGATED_EXECUTION",
    "original_status" => "ACTIVE",
    "current_status" => "CONSUMED_AND_CLOSED_BY_FOUNDER_GATE",
    "source" => "CODEX_THREAD_FOUNDER_MESSAGE",
    "task_id" => "AIOS-P1-001",
    "task_contract_sha256" => "d2974752b088ff30b0764d6b482e19ea939cd497eb2db3e26af28bf09dc2e12f",
    "goal_body_canonical_sha256" => "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0",
    "authorized_parent_commit" => "12aa712c8e8456bb4d70a6b5014fb0937ada778f",
    "authorized_parent_tree" => "a2d966ebbd7784d30e7e38eaac04e0b8eb295022",
    "scope" => "TRUTH_SYNC_AND_P1_001_IMPLEMENTATION",
    "network" => "forbidden",
    "provider" => "forbidden",
    "secrets" => "forbidden",
    "remote" => "forbidden",
    "production" => "forbidden",
    "main_advance" => "forbidden_without_founder_gate",
    "binding_rule" => "SHA256_OF_ORDERED_LF_FIELDS_WITH_FINAL_LF"
  }
  expected_authorization.each do |field, expected|
    abort "Founder authorization drift: #{field}" unless authorization[field] == expected
  end
  authorization_fields = [
    "authority=#{authorization.fetch("authority").tr(" ", "_")}",
    "authorization_model=#{authorization.fetch("authorization_model")}",
    "task_id=#{authorization.fetch("task_id")}",
    "task_contract_sha256=#{authorization.fetch("task_contract_sha256")}",
    "goal_body_canonical_sha256=#{authorization.fetch("goal_body_canonical_sha256")}",
    "authorized_parent_commit=#{authorization.fetch("authorized_parent_commit")}",
    "authorized_parent_tree=#{authorization.fetch("authorized_parent_tree")}",
    "scope=#{authorization.fetch("scope")}",
    "network=#{authorization.fetch("network")}",
    "provider=#{authorization.fetch("provider")}",
    "secrets=#{authorization.fetch("secrets")}",
    "remote=#{authorization.fetch("remote")}",
    "production=#{authorization.fetch("production")}",
    "main_advance=#{authorization.fetch("main_advance")}",
  ]
  expected_binding = Digest::SHA256.hexdigest(authorization_fields.join("\n") + "\n")
  abort "Founder authorization binding drift" unless authorization["binding_sha256"] == expected_binding

  gate_history = truth.fetch("gate_history")
  abort "Founder Gate history population drift" unless gate_history.is_a?(Array) && gate_history.length == 1
  gate = gate_history.first
  abort "Founder Gate task drift" unless gate["task_id"] == "AIOS-P1-001"
  abort "Founder Gate decision drift" unless gate["gate"] == "FOUNDER_GATE" && gate["decision"] == "PASS"
  abort "Founder Gate record binding drift" unless gate["decision_record_sha256"] == "2bacd875f90619ccba19a2cc56a257721ab85b76bd8d3bc168dc50acec4deb72"
  abort "Founder Gate candidate drift" unless gate["candidate_commit"] == "02342da942e291eaa65230f824fcf47eae8f8a30" && gate["candidate_tree"] == "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc"
  abort "Founder Gate Evidence drift" unless gate["evidence_manifest_sha256"] == "e1f735816c18ab7631fa1d0b771deccc25564074350d1d74e67975d187ef3952"
  abort "Founder Gate claim boundary drift" unless gate["claim_boundary"] == "VISIBLE_SYNTHETIC_DETERMINISTIC_HARNESS_STUB_CONFORMANCE_ONLY"
  abort "Founder Gate auto-authorized a next task" unless gate["next_task_authorized"] == false
  abort "Harness conformance status drift" unless truth.dig("claim_boundary", "evaluation_harness") == "IMPLEMENTED_AND_FOUNDER_GATE_ACCEPTED_CONFORMANCE_ONLY"
  abort "Harness conformance did not pass" unless truth.dig("claim_boundary", "harness_conformance") == "PASS"
  abort "B0 terminal claim boundary drift" unless truth.dig("claim_boundary", "b0_adapter_conformance") == "TERMINAL_STOPPED_NOT_ACCEPTED"
  abort "live B0 performance was prematurely claimed" unless truth.dig("claim_boundary", "b0_live_model_performance") == "UNKNOWN_NO_PROVIDER_RUNS"
  abort "offsite custody status drift" unless truth.dig("historical_lineages", "archive", "offsite_status") == "PASS_WITH_DECLARED_HISTORICAL_COUNT_LIMITATION"
  abort "offsite verification binding drift" unless truth.dig("historical_lineages", "archive", "offsite_verification_receipt_sha256") == "e45658d02dc21184cc5c79d5a2b052ce1b2e3885b342930a2e0fb536ba03a91f"
  abort "production readiness falsely claimed" unless truth.dig("claim_boundary", "production_ready") == false
  abort "Agent capability falsely claimed" unless truth.dig("claim_boundary", "trustworthy_software_engineering_agent_proven") == false
  abort "historical lineages reopened" unless truth.dig("historical_lineages", "continuation_allowed") == false

  terminal_history = truth.dig("task_history", "aios_p1_002")
  abort "P1-002 terminal history missing" unless terminal_history.is_a?(Hash)
  expected_terminal_history = {
    "task_id" => terminal_task_id,
    "contract" => terminal_task_path,
    "task_contract_sha256" => terminal_task_sha,
    "status" => "TERMINAL_STOPPED_AFTER_ONE_TIME_BOUNDED_REMEDIATION_NON_PASS",
    "execution_authorized" => false,
    "original_execution_authorization_status" => "CONSUMED_AND_TERMINATED",
    "implementation_attempts" => 2,
    "persistent_evidence_runs" => 2,
    "accepted_evidence_runs" => 0,
    "measurement_retries" => 0,
    "provider_calls" => 0,
    "capability_claims" => 0,
    "claim_boundary" => "OFFLINE_B0_ADAPTER_CONFORMANCE_ONLY",
    "founder_gate_status" => "NOT_REACHED",
    "main_advanced" => false,
    "terminal_reason" => "GOVERNANCE_TASK_BRANCH_CARDINALITY_NON_PASS"
  }
  expected_terminal_history.each do |field, expected|
    abort "P1-002 terminal history drift: #{field}" unless terminal_history[field] == expected
  end
  first_candidate = terminal_history.fetch("first_rejected_candidate")
  abort "first rejected candidate drift" unless first_candidate == {
    "commit" => "dbc77f25d56994a8ae6aa228570c1327ec59ebd6",
    "tree" => "6acb236ebf5d87c78dda39af003e229b93c3b469",
    "outcome" => "STOPPED_AFTER_INDEPENDENT_REVIEW_NON_PASS"
  }
  remediation_candidate = terminal_history.fetch("bounded_remediation_candidate")
  abort "bounded remediation candidate drift" unless remediation_candidate == {
    "commit" => "e7a665315dda01da699f91caf1dec09ecf75d2dc",
    "tree" => "3b9b0105877eda7a8b49fa21ed639c0ae8f2efaa",
    "outcome" => "TERMINAL_STOPPED_AFTER_ONE_TIME_BOUNDED_REMEDIATION_NON_PASS"
  }
  terminal_evidence = terminal_history.fetch("terminal_evidence")
  abort "P1-002 terminal stop binding drift" unless terminal_evidence["stop_record_sha256"] == "09f174f85a8d3e87602f09f24d495664d0ba41081baea68ba00757277cd51aef"
  abort "P1-002 terminal manifest binding drift" unless terminal_evidence["evidence_manifest_sha256"] == "ed832bb6ec9cd104a5005106efed5b0b8b23e73d4fd26625d4008a3d62e97759"
  cleanup = terminal_history.fetch("terminal_cleanup")
  abort "terminal cleanup authorization drift" unless cleanup["authorization_record_sha256"] == "465ff355ddd53519eb0fed041cacd50d5c99dfae95f3acdfe8b3f01bc4d1b632"
  abort "terminal bundle drift" unless cleanup["git_bundle_sha256"] == "985fad210f1e3c270c7526f4b5e263ea697a749ab905f188c0c6a85673e61554"
  abort "terminal bundle receipt drift" unless cleanup["git_bundle_custody_receipt_sha256"] == "904835d27eeb333836c32ec5f662f7aa5fe2bd889266482097a8f6ee3094d7dc"
  abort "terminal branch/worktree cleanup incomplete" unless cleanup["task_branches_removed"] == true && cleanup["task_worktrees_removed"] == true

  abort "terminal Task id drift" unless terminal_task["task_id"] == terminal_task_id
  abort "terminal Task phase drift" unless terminal_task["phase"] == "P1"
  abort "terminal Task Contract schema drift" unless terminal_task["schema_version"] == 2
  abort "terminal Task capture-time authorization drift" unless terminal_task["status"] == "EXECUTION_AUTHORIZED" && terminal_task["execution_authorized"] == true
  abort "terminal Task message binding drift" unless terminal_task.dig("founder_authorization", "message_sha256") == "bedd3c781cc224a13c3e64a7ff7bcd6d9d23cafaf6a897d70f4c3994697ec6db"
  abort "terminal Task parent drift" unless terminal_task.dig("source", "authorized_parent_commit") == "c3bbcf07b597220710fda1f7ee335d4b1ccbba5e" && terminal_task.dig("source", "authorized_parent_tree") == "b035d7410065f5f17b914365c10a3acc5f66fc6d"
  abort "terminal Task capture-time branch drift" unless terminal_task.dig("source", "task_branch") == "task/AIOS-P1-002-b0-adapter-conformance"
  abort "terminal Task live model boundary drift" unless terminal_task.dig("environment", "live_model_invocation") == "forbidden"
  abort "terminal Task Provider boundary drift" unless terminal_task.dig("environment", "provider_calls") == 0 && terminal_task.dig("budget", "provider_calls") == 0
  abort "terminal Task network boundary drift" unless terminal_task.dig("environment", "network") == "forbidden" && terminal_task.dig("budget", "network_calls") == 0
  abort "terminal Task tool boundary drift" unless terminal_task.dig("environment", "enabled_tools") == [] && terminal_task.dig("environment", "loop_limit") == 1
  abort "terminal Task retry boundary drift" unless terminal_task.dig("budget", "measurement_retries") == 0

  terminal_worker_paths = terminal_task.dig("implementation_scope", "worker_writable_paths") || []
  terminal_integration_paths = terminal_task.dig("implementation_scope", "integration_writable_paths") || []
  terminal_quality_paths = terminal_task.dig("implementation_scope", "quality_owned_preimplementation_paths") || []
  expected_terminal_worker_paths = [
    "evaluation-harness/adapters/b0_direct_model/**",
    "evaluation-harness/harness/b0_direct_model/**",
    "evaluation-harness/recording/b0-direct-model-offline-evidence/**",
    "evaluation-harness/recording/recorder.mjs"
  ]
  expected_terminal_integration_paths = ["scripts/verify-p1-b0-direct-model-offline.sh", "Makefile"]
  expected_terminal_quality_paths = [
    "evaluation-harness/fixtures/b0_direct_model/**",
    "evaluation-harness/evaluator/b0_direct_model/**"
  ]
  abort "terminal Worker paths drifted" unless terminal_worker_paths == expected_terminal_worker_paths
  abort "terminal Integration paths drifted" unless terminal_integration_paths == expected_terminal_integration_paths
  abort "terminal Quality paths drifted" unless terminal_quality_paths == expected_terminal_quality_paths
  terminal_owned = terminal_worker_paths + terminal_integration_paths + terminal_quality_paths
  abort "terminal owned path declaration overlap" unless terminal_owned.uniq.length == terminal_owned.length
  abort "terminal Task Contract became writable" if terminal_owned.include?(terminal_task_path)
  abort "accepted schemas became writable in terminal Task" if terminal_owned.any? { |path| path.start_with?("docs/aios/schemas/") }
  abort "terminal Task immutable binding missing" unless (terminal_task.dig("implementation_scope", "immutable_inputs") || []).include?(terminal_task_path)

  abort "task id drift" unless task["task_id"] == "AIOS-P1-001"
  abort "task phase drift" unless task["phase"] == "P1"
  abort "frozen Task Contract must not self-authorize execution" unless task["execution_authorized"] == false
  abort "frozen Task Contract capture-time status drift" unless task["status"] == "DRAFT_READY_FOR_FOUNDER_TASK_AUTHORIZATION"
  abort "harness stub missing" unless task.dig("baseline_plan", "harness_stub", "name") == "HARNESS_STUB"
  abort "harness stub included in VTSR" unless task.dig("baseline_plan", "harness_stub", "included_in_vtsr_denominator") == false
  %w[B0 B1 B2].each { |key| abort "future baseline missing: #{key}" unless task.dig("baseline_plan", "future_true_baselines", key) }
  abort "network enabled" unless task.dig("environment", "network") == "disabled"
  abort "provider enabled" unless task.dig("environment", "provider") == "none"
  abort "task worktree write boundary widened" unless task.dig("environment", "task_worktree_write") == "exact_owned_paths_only"
  abort "canonical main write enabled" unless task.dig("environment", "canonical_main_write") == "forbidden"
  abort "system-under-test write enabled" unless task.dig("environment", "system_under_test_checkout_write") == "forbidden"
  abort "measurement retry widened" unless task.dig("budget", "measurement_retries") == 0

  worker_paths = task.dig("implementation_scope", "worker_writable_paths") || []
  integration_paths = task.dig("implementation_scope", "integration_writable_paths") || []
  quality_paths = task.dig("implementation_scope", "quality_owned_preimplementation_paths") || []
  immutable_paths = task.dig("implementation_scope", "immutable_inputs") || []
  expected_worker_paths = [
    "evaluation-harness/harness/**",
    "evaluation-harness/adapters/harness_stub/**",
    "evaluation-harness/recording/**",
    "evaluation-harness/replay/**"
  ]
  expected_integration_paths = ["scripts/verify-p1-harness.sh", "Makefile"]
  expected_quality_paths = [
    "evaluation-harness/evaluator/**",
    "evaluation-harness/fixtures/visible/**",
    "evaluation-harness/fixtures/oracle/**"
  ]
  expected_immutable_paths = [
    "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml",
    "docs/aios/schemas/task-spec.schema.json",
    "docs/aios/schemas/environment-snapshot.schema.json",
    "docs/aios/schemas/system-configuration.schema.json",
    "docs/aios/schemas/run-record.schema.json",
    "docs/aios/EVALUATION_PROTOCOL.md",
    "docs/aios/BASELINE_ADAPTER_CONTRACT.md"
  ]
  abort "Worker write paths drifted" unless worker_paths == expected_worker_paths
  abort "Integration write paths drifted" unless integration_paths == expected_integration_paths
  abort "Quality write paths drifted" unless quality_paths == expected_quality_paths
  abort "immutable input set drifted" unless immutable_paths == expected_immutable_paths
  all_owned = worker_paths + integration_paths + quality_paths
  abort "owned write paths overlap" unless all_owned.uniq.length == all_owned.length
  abort "Task Contract became writable" if all_owned.include?("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml")
  abort "accepted schemas became writable" if all_owned.any? { |path| path.start_with?("docs/aios/schemas/") }
  abort "Task Contract is not immutable" unless immutable_paths.include?("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml")
  abort "accepted schema set incomplete" unless %w[task-spec environment-snapshot system-configuration run-record].all? { |name| immutable_paths.include?("docs/aios/schemas/#{name}.schema.json") }
  abort "Quality evaluator ownership missing" unless quality_paths.include?("evaluation-harness/evaluator/**")
  abort "Quality visible fixture ownership missing" unless quality_paths.include?("evaluation-harness/fixtures/visible/**")
  abort "Quality oracle ownership missing" unless quality_paths.include?("evaluation-harness/fixtures/oracle/**")
  abort "Worker can modify visible fixture" if worker_paths.include?("evaluation-harness/fixtures/visible/**")

  abort "migration ledger became current authority" unless ledger["current_phase_authority"] == false
  ids = ledger.fetch("assets").map { |entry| entry.fetch("id") }
  abort "duplicate asset ids" unless ids.uniq.length == ids.length
  %w[EVALUATION_HARNESS JAVA_AST_AND_CODE_GRAPH CODE_CHUNKS_SEARCH_AND_RETRIEVAL AGENT_RUNTIME MULTI_AGENT_ORGANIZATION_RUNTIME].each do |id|
    abort "required disposition missing: #{id}" unless ids.include?(id)
  end

  Dir.glob("docs/aios/schemas/*.json").each { |path| JSON.parse(File.read(path)) }
' || fail "structured authority validation failed"

[[ "$(git rev-parse 02342da942e291eaa65230f824fcf47eae8f8a30^{tree})" == "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc" ]] || fail "accepted candidate tree no longer resolves"
git merge-base --is-ancestor 02342da942e291eaa65230f824fcf47eae8f8a30 HEAD || fail "accepted candidate is not an ancestor of current main"

historical_paths=(
  CHAIRMAN_BRIEFING.md
  docs/AGENT_ACTIVITY_LOG.md
  docs/AGENT_DECISION_REGISTER.md
  docs/AGENT_STATUS_BOARD.md
  docs/CODEX_HANDOFF.md
  docs/PROJECT_PLAN.md
  docs/PHASE_REQUIREMENTS.md
  docs/PRODUCT_PROGRESS_LOG.md
  docs/REFACTOR_ROADMAP.md
  docs/TEAM_OPERATING_MODEL.md
  docs/SOURCELENS_OPERATING_SYSTEM.md
  docs/aios/CODEX_MASTER_PROMPT.md
  docs/aios/P0_GATE.md
  docs/aios/P0_INDEPENDENT_REVIEW.md
)

for path in "${historical_paths[@]}"; do
  [[ ! -e "$path" ]] || fail "historical path leaked into active tree: $path"
done

if git grep -n -E 'AIOS-P1-001 Contract Freeze|P1-001 execution: NOT AUTHORIZED' -- web-console/src >/dev/null 2>&1; then
  fail "product UI mirrors project control-plane state"
fi

task_branch_count="$(git for-each-ref --format='%(refname:short)' refs/heads/task/ | wc -l | tr -d ' ')"
[[ "$task_branch_count" -eq 0 ]] || fail "task branch exists while current Task is NONE"

worktree_count="$(git worktree list --porcelain | grep -c '^worktree ' || true)"
[[ "$worktree_count" -eq 1 ]] || fail "task worktree exists while current Task is NONE"

git diff --check || fail "git whitespace validation failed"

echo "AIOS governance validation passed."

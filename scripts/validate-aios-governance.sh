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
  ledger = YAML.safe_load(File.read("docs/aios/MIGRATION_LEDGER.yaml"), aliases: false)

  expected_hashes = {
    "docs/aios/STRATEGIC_CONSTITUTION.md" => "040196be12532b8c3661665995d3e79a28d268a1ecc991623380f0939f468485",
    "docs/aios/MASTER_EXECUTION_PROTOCOL.md" => "47c444c50c7521a7515dfb2fbee0c8c81cc72b32c42eba549d080eeb0c1bcedf",
    "docs/aios/EVALUATION_PROTOCOL.md" => "da029143561fbb3c213d4a358b25e085542c6cd26ae8150a53cbb5998177eed8"
  }
  expected_hashes.each do |path, expected|
    actual = Digest::SHA256.file(path).hexdigest
    abort "authority hash drift: #{path}" unless actual == expected
  end

  abort "truth schema drift" unless truth["schema_version"] == 3
  abort "phase must be P1" unless truth.dig("project", "current_phase") == "P1"
  abort "P0 must be complete" unless truth.dig("project", "p0_status") == "COMPLETE"
  abort "P1 entry must be authorized" unless truth.dig("project", "p1_entry_status") == "AUTHORIZED"
  abort "P1 execution must not be started" unless truth.dig("project", "p1_execution_status") == "NOT_STARTED"
  abort "current task must be NONE" unless truth.dig("active_work", "current_task") == "NONE"
  abort "current authorization must be NONE" unless truth.dig("active_work", "current_execution_authorization") == "NONE"
  abort "P1-001 execution widened" unless truth.dig("active_work", "aios_p1_001", "execution_authorized") == false
  abort "P1-001 runs are not zero" unless truth.dig("active_work", "aios_p1_001", "scheduled_runs") == 0
  abort "production readiness falsely claimed" unless truth.dig("claim_boundary", "production_ready") == false
  abort "Agent capability falsely claimed" unless truth.dig("claim_boundary", "trustworthy_software_engineering_agent_proven") == false
  abort "historical lineages reopened" unless truth.dig("historical_lineages", "continuation_allowed") == false

  abort "task id drift" unless task["task_id"] == "AIOS-P1-001"
  abort "task phase drift" unless task["phase"] == "P1"
  abort "task execution improperly authorized" unless task["execution_authorized"] == false
  abort "task status drift" unless task["status"] == "DRAFT_READY_FOR_FOUNDER_TASK_AUTHORIZATION"
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
[[ "$task_branch_count" -le 1 ]] || fail "more than one task branch exists"

worktree_count="$(git worktree list --porcelain | grep -c '^worktree ' || true)"
[[ "$worktree_count" -le 2 ]] || fail "more than one task worktree exists"

git diff --check || fail "git whitespace validation failed"

echo "AIOS governance validation passed."

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "AIOS GOVERNANCE FAIL: $*" >&2
  exit 1
}

command -v ruby >/dev/null 2>&1 || fail "ruby with the standard YAML library is required"
command -v node >/dev/null 2>&1 || fail "node is required for full snapshot reconstruction"

required_files=(
  AGENTS.md
  docs/aios/README.md
  docs/aios/STRATEGIC_CONSTITUTION.md
  docs/aios/MASTER_EXECUTION_PROTOCOL.md
  docs/aios/EVALUATION_PROTOCOL.md
  docs/aios/MIGRATION_LEDGER.yaml
  docs/aios/truth/project_state.yaml
  docs/aios/P0_GATE.md
  docs/aios/CODEX_MASTER_PROMPT.md
  docs/aios/BASELINE_ADAPTER_CONTRACT.md
  docs/aios/tasks/P0-04A_TRUTH_CONTAINMENT.yaml
  docs/aios/tasks/P0-04B_SLICE_F_GATE_REPAIR.yaml
  docs/aios/tasks/P0-04C_AUTHORITY_DECONTAMINATION.yaml
  docs/aios/tasks/P0-05_BASELINE_SLICING.yaml
  docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml
  docs/aios/schemas/task-spec.schema.json
  docs/aios/schemas/environment-snapshot.schema.json
  docs/aios/schemas/system-configuration.schema.json
  docs/aios/schemas/run-record.schema.json
  docs/README.md
  README.md
  ROADMAP.md
  CHAIRMAN_BRIEFING.md
  CONTRIBUTING.md
)

for file in "${required_files[@]}"; do
  [[ -s "$file" ]] || fail "required file is missing or empty: $file"
done

export AIOS_TRUTH_BINDING_PATH="${SOURCELENS_AIOS_TRUTH_BINDING:-/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p0-truth-contained-final/truth-binding.json}"

ruby -ryaml -rjson -rdigest -e '
  state = YAML.load_file("docs/aios/truth/project_state.yaml")
  ledger = YAML.load_file("docs/aios/MIGRATION_LEDGER.yaml")
  truth_task = YAML.load_file("docs/aios/tasks/P0-04A_TRUTH_CONTAINMENT.yaml")
  slice_f_task = YAML.load_file("docs/aios/tasks/P0-04B_SLICE_F_GATE_REPAIR.yaml")
  authority_task = YAML.load_file("docs/aios/tasks/P0-04C_AUTHORITY_DECONTAMINATION.yaml")
  baseline_task = YAML.load_file("docs/aios/tasks/P0-05_BASELINE_SLICING.yaml")
  p1_task = YAML.load_file("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml")

  p1_phase_status = state.dig("project", "phase_status")
  p1_entry_statuses = [
    "ENTRY_AUTHORIZED_CONTRACT_REFROZEN_V10_PENDING_INDEPENDENT_REVIEW",
    "ENTRY_AUTHORIZED_FEM_V5_BOUNDED_OBSERVATION_ACCEPTED_P1_001_EXECUTION_BLOCKED"
  ]
  if p1_entry_statuses.include?(p1_phase_status)
    audit_root = File.realpath("/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit")
    attachments_root = File.realpath("/Users/lijunpeng/.codex/attachments")
    founder_path = File.expand_path(state.dig("p1_entry_authorization", "machine_record"))
    frozen_manifest_path = File.expand_path(state.dig("p1_entry_authorization", "frozen_input_manifest"))
    goal_path = File.expand_path("/Users/lijunpeng/.codex/attachments/6b0b059a-415e-424c-a7f4-98d7c956c285/goal-objective.md")
    [founder_path, frozen_manifest_path, goal_path].each do |path|
      abort "P1 authority input missing or symlink: #{path}" unless File.file?(path) && !File.symlink?(path)
    end
    abort "P1 Founder record escapes audit root" unless File.realpath(founder_path).start_with?("#{audit_root}/")
    abort "P1 frozen manifest escapes audit root" unless File.realpath(frozen_manifest_path).start_with?("#{audit_root}/")
    abort "Goal objective escapes attachments root" unless File.realpath(goal_path).start_with?("#{attachments_root}/")
    abort "P1 Founder record hash drift" unless Digest::SHA256.file(founder_path).hexdigest == "10f60932d2da71d02434d3a34cf864be94fb3642fed5771bf59f90307342dc15"
    abort "P1 frozen manifest hash drift" unless Digest::SHA256.file(frozen_manifest_path).hexdigest == "6fdf10d722ebe13e03c7d057e6b063591c982025b481de68456d6df0e2da6541"
    abort "Long-term Goal hash drift" unless Digest::SHA256.file(goal_path).hexdigest == "60e42edb7d422265325391014cd6e329fdf14861beedc682b6892fb3fc929eea"

    founder = JSON.parse(File.read(founder_path))
    abort "P1 entry not authorized" unless founder["decision"] == "P1_ENTRY_AUTHORIZED_CONTRACT_FREEZE_FIRST" && founder["p1_entry_authorized"] == true
    abort "P1-001 execution improperly authorized" unless founder["aios_p1_001_execution_authorized"] == false
    abort "current phase must be P1" unless state.dig("project", "current_phase") == "P1"
    abort "P0 Founder Gate PASS lost" unless state.dig("founder_gate", "decision") == "PASS"
    abort "accepted checkpoint commit drift" unless state.dig("founder_gate", "accepted_checkpoint_commit") == "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10"
    abort "accepted checkpoint tree drift" unless state.dig("founder_gate", "accepted_checkpoint_tree") == "2c0956ae8598547466f691ead21532a026006bf9"
    abort "P0 decision history misrepresented" unless state.dig("founder_gate", "p1_authorized_by_this_p0_decision") == false
    abort "Truth P1 entry authorization drift" unless state.dig("p1_entry_authorization", "p1_entry_authorized") == true
    abort "Truth starts P1-001 execution" unless state.dig("p1_entry_authorization", "aios_p1_001_execution_authorized") == false
    abort "runtime P1 state drift" unless state.dig("runtime_goal_transition", "p1_authorized") == true
    abort "runtime starts P1-001" unless state.dig("runtime_goal_transition", "aios_p1_001_execution_authorized") == false
    abort "Long-term Goal status drift" unless state.dig("runtime_goal_transition", "long_term_goal_status") == "ACTIVE_FOUNDER_MANUALLY_CREATED"

    if p1_phase_status == "ENTRY_AUTHORIZED_FEM_V5_BOUNDED_OBSERVATION_ACCEPTED_P1_001_EXECUTION_BLOCKED"
      custody = state.fetch("p1_preexecution_custody_evidence")
      custody_paths = {
        "founder_acceptance_record" => [
          custody.fetch("founder_acceptance_record"),
          "5673ab89d0a8681ee7e30876944dab640a40dfb91ddded82316b062bce5f0e50"
        ],
        "fem_v5" => [
          custody.fetch("fem_v5"),
          "ee84a70855d82019ea308de07a8eede2403686f7bb8bab6f2b5f61a7c73c32bd"
        ],
        "operational_selection_manifest_v3" => [
          "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-entry-and-p1-001-contract-20260711T141809Z/root-supervisor-v11/privileged-integration-v1/ROOT_CUSTODY_V4_3_OPERATIONAL_SELECTION_MANIFEST_V3.json",
          "62e61244a56e9361b8f10a592bc9a9687787563fe961c11ba5f745488a9327c3"
        ],
        "verifier_result" => [
          "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-entry-and-p1-001-contract-20260711T141809Z/root-supervisor-v11/privileged-integration-v1/FINAL_EVIDENCE_MANIFEST_V5_VERIFICATION_RESULT.json",
          "477486c69dee2d2c560d76a349675a270906c65dcf9cfc78e6e6206b70aaf294"
        ],
        "cto_review" => [
          "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-entry-and-p1-001-contract-20260711T141809Z/root-supervisor-v11/ROOT_CUSTODY_V4_3_PHASE_A_GENERATION_2_V11_R2_FEM_V5_CTO_REVIEW.md",
          "efee9c07b57b75c4d450d1ae26a58d3e59bfc9378111bc3cd31f7d2a2798c158"
        ],
        "security_review" => [
          "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-entry-and-p1-001-contract-20260711T141809Z/root-supervisor-v11/ROOT_CUSTODY_V4_3_PHASE_A_GENERATION_2_V11_R2_FEM_V5_SECURITY_REVIEW.md",
          "fa5cb611d730752836c4c9683d1fac2a159abfabe472e6b124ae8ea0b576ccc6"
        ],
        "quality_review" => [
          "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-entry-and-p1-001-contract-20260711T141809Z/root-supervisor-v11/ROOT_CUSTODY_V4_3_PHASE_A_GENERATION_2_V11_R2_FEM_V5_QUALITY_REVIEW.md",
          "c876abfff671b9aff81b9e4685f7abb99a859872644971f979f160e8f1b0b9f0"
        ]
      }
      custody_paths.each do |label, (path, expected_sha)|
        expanded = File.expand_path(path)
        abort "#{label} missing or symlink" unless File.file?(expanded) && !File.symlink?(expanded)
        abort "#{label} escapes audit root" unless File.realpath(expanded).start_with?("#{audit_root}/")
        abort "#{label} hash drift" unless Digest::SHA256.file(expanded).hexdigest == expected_sha
      end
      abort "Founder acceptance Truth hash drift" unless custody.fetch("founder_acceptance_record_sha256") == custody_paths.fetch("founder_acceptance_record")[1]
      abort "FEM V5 Truth hash drift" unless custody.fetch("fem_v5_sha256") == custody_paths.fetch("fem_v5")[1]
      abort "OSM V3 Truth hash drift" unless custody.fetch("operational_selection_manifest_v3_sha256") == custody_paths.fetch("operational_selection_manifest_v3")[1]
      abort "verifier result Truth hash drift" unless custody.fetch("verifier_result_sha256") == custody_paths.fetch("verifier_result")[1]
      %w[cto security quality].each do |role|
        review = custody.dig("independent_reviews", role)
        abort "#{role} review verdict drift" unless review && review["verdict"] == "PASS"
        abort "#{role} review Truth hash drift" unless review["sha256"] == custody_paths.fetch("#{role}_review")[1]
      end
      fem = JSON.parse(File.read(custody.fetch("fem_v5")))
      abort "FEM V5 claim widened" unless fem["claim_identifier"] == "PHASE_A_HASH_BOUND_BOUNDED_OBSERVATION_V1"
      abort "FEM V5 candidate state drift" unless fem["candidate_state"] == "HASH_BOUND_PHASE_A_CANDIDATE_FOR_INDEPENDENT_REVIEW"
      abort "FEM V5 root custody falsely proven" unless fem["root_custody_proven"] == false
      abort "FEM V5 atomic snapshot falsely proven" unless fem["atomic_snapshot_proven"] == false
      abort "FEM V5 writer exclusion falsely proven" unless fem["writer_exclusion_proven"] == false
      abort "FEM V5 starts execution" unless fem["execution_authorized"] == false && fem["p1_001_execution_authorized"] == false
      abort "Truth bounded-observation status drift" unless custody["current_evidence_status"] == "FEM_V5_FOUNDER_ACCEPTED_HASH_BOUND_BOUNDED_OBSERVATION_ONLY"
      abort "Truth claim identifier drift" unless custody["accepted_claim_identifier"] == "PHASE_A_HASH_BOUND_BOUNDED_OBSERVATION_V1"
      abort "Truth creates or revokes P1 authority" unless custody["existing_p1_entry_authority_effect"] == "PRESERVED_NOT_CREATED_OR_REVOKED_BY_THIS_ACCEPTANCE"
      %w[root_custody_proven atomic_snapshot_proven writer_exclusion_proven phase_b_authorized production_ready aios_p1_001_execution_authorized].each do |field|
        abort "Truth authority or claim widening: #{field}" unless custody[field] == false
      end
      active = state.fetch("active_p1_work").find { |entry| entry["id"] == "P1-001" }
      abort "active P1-001 status does not preserve root-custody block" unless active && active["status"] == "PRE_EXECUTION_BLOCKED_ROOT_CUSTODY_NOT_PROVEN_FEM_V5_BOUNDED_OBSERVATION_ACCEPTED"
      abort "active P1-001 execution improperly permitted" unless active["execution_permitted"] == false
    end

    contract_path = "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml"
    contract_sha = Digest::SHA256.file(contract_path).hexdigest
    abort "P1-001 contract hash drift" unless contract_sha == "8cc4bfee6c5420256c2a413475e6ea5dff3fa653b3e2a6112b881d3361565a31"
    abort "Truth P1-001 contract hash drift" unless state.dig("p1_entry_authorization", "current_task_contract_sha256") == contract_sha
    abort "P1-001 task id drift" unless p1_task["task_id"] == "AIOS-P1-001"
    abort "P1-001 phase drift" unless p1_task["phase"] == "P1"
    abort "P1-001 contract not refrozen for review" unless p1_task["status"] == "REFROZEN_V10_PENDING_INDEPENDENT_PRE_EXECUTION_REVIEW"
    abort "P1-001 execution flag must be false" unless p1_task["execution_permitted"] == false && p1_task["execution_start_authorized"] == false
    %w[task_objective research_hypothesis why_now source_baselines fixture frozen_contract_inputs environment baseline roles exact_execution_write_scope file_ownership execution_permissions metrics budget_boundary required_artifacts success_criteria failure_criteria stop_conditions acceptance_criteria required_pre_execution_reviews forbidden_actions founder_decision].each do |field|
      value = p1_task[field]
      abort "P1-001 required contract field missing: #{field}" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
    abort "P1-001 exact write scope count drift" unless p1_task.dig("exact_execution_write_scope", "exact_changed_path_count") == 33 && p1_task.dig("exact_execution_write_scope", "paths").length == 33
    abort "P1-001 changed-path budget drift" unless p1_task.dig("budget_boundary", "maximum_changed_paths") == 33
    abort "P1-001 contract must be immutable during execution" if p1_task.dig("exact_execution_write_scope", "paths").include?("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml")
    abort "P1-001 network budget drift" unless p1_task.dig("budget_boundary", "maximum_external_network_requests") == 0
    abort "P1-001 real-provider budget drift" unless p1_task.dig("budget_boundary", "maximum_real_provider_model_cost_usd") == 0
    abort "P1-001 dependency budget drift" unless p1_task.dig("budget_boundary", "maximum_new_runtime_dependencies") == 0

    frozen = JSON.parse(File.read(frozen_manifest_path))
    abort "frozen input record type drift" unless frozen["record_type"] == "aios_p1_001_frozen_input_manifest_delta"
    abort "frozen inputs were not refrozen before implementation" unless frozen["freeze_state"] == "REFROZEN_V10_BEFORE_IMPLEMENTATION_OUTPUT_AFTER_V9_CTO_SECURITY_QUALITY_FAILURE"
    abort "frozen manifest starts execution" unless frozen["execution_authorized"] == false
    parent_manifest_path = File.join(File.dirname(frozen_manifest_path), frozen.dig("parent_manifest", "path"))
    abort "parent frozen manifest missing or symlink" unless File.file?(parent_manifest_path) && !File.symlink?(parent_manifest_path)
    abort "parent frozen manifest hash drift" unless Digest::SHA256.file(parent_manifest_path).hexdigest == frozen.dig("parent_manifest", "sha256")
    frozen.fetch("delta_frozen_inputs").each do |entry|
      path = File.expand_path(entry.fetch("path"), File.dirname(frozen_manifest_path))
      abort "frozen input missing or symlink: #{path}" unless File.file?(path) && !File.symlink?(path)
      abort "frozen input escapes audit root: #{path}" unless File.realpath(path).start_with?("#{audit_root}/")
      abort "frozen input hash drift: #{path}" unless Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
      abort "frozen input size drift: #{path}" unless File.size(path) == entry.fetch("bytes")
    end
    frozen_root = File.dirname(frozen_manifest_path)
    scope_path = File.join(frozen_root, p1_task.dig("frozen_contract_inputs", "write_scope", "path"))
    ownership_path = File.join(frozen_root, p1_task.dig("frozen_contract_inputs", "ownership", "path"))
    contract_validator_path = File.join(frozen_root, p1_task.dig("frozen_contract_inputs", "contract_validator", "path"))
    scope = YAML.load_file(scope_path)
    ownership = YAML.load_file(ownership_path)
    if scope["replace_paths"]
      base_scope = YAML.load_file(File.join(File.dirname(scope_path), scope.fetch("base")))
      scope["exact_allowed_paths"] = base_scope.fetch("exact_allowed_paths").map { |path| scope.fetch("replace_paths").fetch(path, path) }
    end
    if scope["add_paths"]
      base_scope = YAML.load_file(File.join(File.dirname(scope_path), scope.fetch("base")))
      prior_base = YAML.load_file(File.join(File.dirname(scope_path), base_scope.fetch("base")))
      inherited_paths = prior_base.fetch("exact_allowed_paths").map { |path| base_scope.fetch("replace_paths").fetch(path, path) }
      scope["exact_allowed_paths"] = inherited_paths + scope.fetch("add_paths")
    end
    if ownership["replace_paths"]
      base_ownership = YAML.load_file(File.join(File.dirname(ownership_path), ownership.fetch("base")))
      ownership["owners"] = base_ownership.fetch("owners").map do |owner|
        owner.merge("paths" => owner.fetch("paths").map { |path| ownership.fetch("replace_paths").fetch(path, path) })
      end
    end
    if ownership["add_assignments"]
      base_ownership = YAML.load_file(File.join(File.dirname(ownership_path), ownership.fetch("base")))
      prior_base = YAML.load_file(File.join(File.dirname(ownership_path), base_ownership.fetch("base")))
      owners = prior_base.fetch("owners").map do |owner|
        owner.merge("paths" => owner.fetch("paths").map { |path| base_ownership.fetch("replace_paths").fetch(path, path) })
      end
      ownership.fetch("add_assignments").each do |addition|
        target = owners.find { |owner| owner.fetch("owner_role") == addition.fetch("owner_role") }
        abort "unknown owner addition" unless target
        target["paths"] += addition.fetch("paths")
      end
      ownership["owners"] = owners
    end
    contract_paths = p1_task.dig("exact_execution_write_scope", "paths")
    abort "frozen scope and Task Contract disagree" unless scope["exact_allowed_paths"].sort == contract_paths.sort
    frozen_owner_map = ownership.fetch("owners").to_h { |owner| [owner.fetch("owner_role"), owner.fetch("paths")] }
    contract_owner_map = p1_task.fetch("file_ownership").reject { |role, _| role == "overlap_policy" }
    abort "frozen ownership and Task Contract disagree" unless frozen_owner_map == contract_owner_map
    abort "owner coverage is not exact" unless frozen_owner_map.values.flatten.sort == contract_paths.sort
    abort "owner overlap detected" unless frozen_owner_map.values.flatten.uniq.length == contract_paths.length
    abort "contract validator hash drift" unless Digest::SHA256.file(contract_validator_path).hexdigest == p1_task.dig("frozen_contract_inputs", "contract_validator", "sha256")
    abort "external frozen contract validator failed" unless system("ruby", contract_validator_path, out: File::NULL)
    abort "evaluator still accepts caller base" unless p1_task.dig("frozen_contract_inputs", "evaluator", "caller_supplied_base_identity") == false
    abort "oracle remains candidate mutable" unless p1_task.dig("frozen_contract_inputs", "immutable_oracle", "candidate_mutable") == false

    expected = %w[AGENTS.md CHAIRMAN_BRIEFING.md CONTRIBUTING.md README.md ROADMAP.md docs/PROJECT_CODE_MAP.md docs/SOURCELENS_OPERATING_SYSTEM.md docs/TEAM_OPERATING_MODEL.md docs/aios/BASELINE_ADAPTER_CONTRACT.md docs/aios/CODEX_MASTER_PROMPT.md docs/aios/EVALUATION_PROTOCOL.md docs/aios/README.md docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml docs/aios/truth/project_state.yaml scripts/validate-aios-governance.sh scripts/validate-frontend-ui.mjs web-console/src/pages/Dashboard.tsx web-console/tests/dashboard-next-action-smoke.spec.ts].sort
    changed = IO.popen(["git", "diff", "--name-only", "14df7b8e94f7c1fc8305e71a794a0815ed45fa82"], &:read).lines.map(&:strip).reject(&:empty?).sort
    abort "P1 entry change set escaped allowlist: #{changed.inspect}" unless changed == expected
    abort "staged changes forbidden during validation" unless IO.popen(["git", "diff", "--cached", "--name-only"], &:read).strip.empty?

    receipt_path_raw = ENV["AIOS_P1_ENTRY_RECEIPT_PATH"]
    receipt_sha = ENV["AIOS_P1_ENTRY_RECEIPT_SHA256"]
    abort "hash-pinned P1 entry receipt required" if receipt_path_raw.to_s.empty?
    abort "valid P1 entry receipt SHA required" unless receipt_sha.to_s.match?(/\A[0-9a-f]{64}\z/)
    receipt_path = File.expand_path(receipt_path_raw)
    abort "P1 entry receipt missing or symlink" unless File.file?(receipt_path) && !File.symlink?(receipt_path)
    abort "P1 entry receipt escapes audit root" unless File.realpath(receipt_path).start_with?("#{audit_root}/")
    abort "P1 entry receipt hash mismatch" unless Digest::SHA256.file(receipt_path).hexdigest == receipt_sha
    receipt = JSON.parse(File.read(receipt_path))
    expected_receipt_type = if p1_phase_status == "ENTRY_AUTHORIZED_FEM_V5_BOUNDED_OBSERVATION_ACCEPTED_P1_001_EXECUTION_BLOCKED"
      "sourcelens_aios_p1_preexecution_current_state_sync_receipt"
    else
      "sourcelens_aios_p1_entry_contract_freeze_receipt"
    end
    abort "P1 entry receipt type drift" unless receipt["record_type"] == expected_receipt_type
    head = IO.popen(["git", "rev-parse", "HEAD"], &:read).strip
    tree = IO.popen(["git", "rev-parse", "HEAD^{tree}"], &:read).strip
    abort "P1 entry HEAD not bound" unless head == receipt.dig("transition", "commit")
    abort "P1 entry tree not bound" unless tree == receipt.dig("transition", "tree")
    abort "P1 authority workspace must be clean" unless IO.popen(["git", "status", "--porcelain=v1", "-uall"], &:read).empty?
    if p1_phase_status == "ENTRY_AUTHORIZED_FEM_V5_BOUNDED_OBSERVATION_ACCEPTED_P1_001_EXECUTION_BLOCKED"
      sync_base = "d94443cd0806bcb9742fa676d3ffaae33a22a9f5"
      sync_base_tree = "ac83a2a70006bec1448dcc70c6371b87d2e9f6af"
      sync_paths = %w[docs/PROJECT_CODE_MAP.md docs/aios/truth/project_state.yaml scripts/validate-aios-governance.sh].sort
      abort "current-state sync authority base drift" unless receipt.dig("transition", "authority_base_commit") == sync_base
      abort "current-state sync authority base tree drift" unless receipt.dig("transition", "authority_base_tree") == sync_base_tree
      abort "current-state sync is not descended from authority base" unless system("git", "merge-base", "--is-ancestor", sync_base, head, out: File::NULL, err: File::NULL)
      direct_changed = IO.popen(["git", "diff", "--name-only", "#{sync_base}..#{head}"], &:read).lines.map(&:strip).reject(&:empty?).sort
      abort "current-state sync direct path scope drift: #{direct_changed.inspect}" unless direct_changed == sync_paths
      abort "current-state sync receipt direct path drift" unless receipt.dig("transition", "direct_changed_paths").sort == sync_paths
      abort "current-state sync direct path count drift" unless receipt.dig("transition", "direct_changed_path_count") == 3
      abort "current-state sync business path count drift" unless receipt.dig("transition", "business_path_count") == 0
      bindings = receipt.fetch("authority_bindings")
      abort "receipt Founder acceptance binding drift" unless bindings["founder_acceptance_record_sha256"] == custody["founder_acceptance_record_sha256"]
      abort "receipt FEM V5 binding drift" unless bindings["fem_v5_sha256"] == custody["fem_v5_sha256"]
      receipt_state = receipt.fetch("current_state")
      abort "receipt changes existing P1 entry authority" unless receipt_state["p1_entry_authorized"] == true && receipt_state["p1_entry_authority_effect_of_this_transition"] == "PRESERVED_NOT_CREATED_OR_REVOKED"
      %w[root_custody_proven atomic_snapshot_proven writer_exclusion_proven phase_b_authorized production_ready aios_p1_001_execution_authorized].each do |field|
        abort "receipt authority or claim widening: #{field}" unless receipt_state[field] == false
      end
    end
    descriptors = receipt.fetch("changed_path_descriptors")
    abort "P1 entry descriptor path set mismatch" unless descriptors.map { |d| d.fetch("path") }.sort == expected
    descriptors.each do |descriptor|
      path = descriptor.fetch("path")
      stat = File.lstat(path)
      abort "P1 entry path symlink rejected: #{path}" if File.symlink?(path)
      abort "P1 entry path hash drift: #{path}" unless Digest::SHA256.file(path).hexdigest == descriptor.fetch("sha256")
      abort "P1 entry path size drift: #{path}" unless stat.size == descriptor.fetch("bytes")
      abort "P1 entry path mode drift: #{path}" unless (stat.mode & 0777) == descriptor.fetch("mode")
    end
    exit 0
  end

  if state.dig("project", "phase_status") == "COMPLETE_FOUNDER_GATE_PASS_P1_NOT_AUTHORIZED"
    decision_path = File.expand_path(ENV.fetch("AIOS_FOUNDER_GATE_DECISION_PATH", "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p0-founder-gate-decision-20260711T125610Z/founder-gate-decision.json"))
    goal_path = File.expand_path(ENV.fetch("AIOS_LONG_TERM_GOAL_OBJECTIVE_PATH", "/Users/lijunpeng/.codex/attachments/6b0b059a-415e-424c-a7f4-98d7c956c285/goal-objective.md"))
    abort "Founder decision missing" unless File.file?(decision_path) && !File.symlink?(decision_path)
    abort "Long-term Goal objective missing" unless File.file?(goal_path) && !File.symlink?(goal_path)
    audit_root = File.realpath("/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit")
    attachments_root = File.realpath("/Users/lijunpeng/.codex/attachments")
    abort "Founder decision escapes trusted audit root" unless File.realpath(decision_path).start_with?("#{audit_root}/")
    abort "Goal objective escapes trusted attachments root" unless File.realpath(goal_path).start_with?("#{attachments_root}/")
    abort "Founder decision hash drift" unless Digest::SHA256.file(decision_path).hexdigest == "16e35d4f39c333d038fa2337e40b1a91a8dc5d3227899baa1542ad80fec9b8ee"
    decision = JSON.parse(File.read(decision_path))
    abort "Founder Gate must be PASS" unless decision["decision"] == "PASS"
    abort "Founder decision authorizes P1" unless decision["p1_authorized"] == false
    abort "accepted checkpoint drift" unless decision.dig("accepted_checkpoint", "commit") == "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10"
    abort "Goal objective hash drift" unless Digest::SHA256.file(goal_path).hexdigest == "60e42edb7d422265325391014cd6e329fdf14861beedc682b6892fb3fc929eea"
    goal_text = File.binread(goal_path)
    abort "Goal does not preserve P1 block" unless goal_text.include?("P1".b) && goal_text.include?("AIOS-P1-001".b)
    abort "Truth Founder decision mismatch" unless state.dig("founder_gate", "decision") == "PASS"
    abort "current phase must remain P0 until P1 authorization" unless state.dig("project", "current_phase") == "P0"
    abort "Truth authorizes P1" unless state.dig("founder_gate", "p1_authorized") == false
    abort "Truth accepted checkpoint commit drift" unless state.dig("founder_gate", "accepted_checkpoint_commit") == "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10"
    abort "Truth accepted checkpoint tree drift" unless state.dig("founder_gate", "accepted_checkpoint_tree") == "2c0956ae8598547466f691ead21532a026006bf9"
    abort "P0 control plane current status drift" unless state.dig("p0_control_plane", "status") == "COMPLETE_FOUNDER_GATE_PASS_WITH_RETAINED_TRUST_BLOCKERS"
    abort "P0 contracts not recorded as Founder accepted" unless state.dig("p0_control_plane", "contract_drafts", "status") == "FOUNDER_ACCEPTED_AS_CONTROLLED_P1_IMPLEMENTATION_DEFINITIONS"
    review = state.dig("p0_control_plane", "independent_review")
    abort "unqualified pre-Founder NO-GO reintroduced" if review.key?("p0_gate_recommendation")
    abort "historical reviewer recommendation lost" unless review["historical_pre_founder_gate_recommendation"] == "NO_GO"
    abort "current Founder Gate decision drift" unless review["current_founder_gate_decision"] == "PASS"
    p0_03 = state.fetch("active_p0_work").find { |item| item["id"] == "P0-03" }
    abort "P0-03 contracts remain unaccepted" unless p0_03 && p0_03["status"] == "COMPLETE_FOUNDER_ACCEPTED"
    p0_04c_current = state.fetch("active_p0_work").find { |item| item["id"] == "P0-04C" }
    abort "P0-04C remains review-pending" unless p0_04c_current && p0_04c_current["status"] == "COMPLETE_FOUNDER_ACCEPTED"
    risk_p0_004 = state.fetch("blocking_risks").find { |item| item["id"] == "RISK-P0-004" }
    abort "P0 baseline-slicing risk remains pending" unless risk_p0_004 && risk_p0_004["status"] == "MITIGATED_BY_FOUNDER_ACCEPTED_CHECKPOINT_WITH_RETAINED_HISTORICAL_GAP"
    abort "Goal status drift" unless state.dig("runtime_goal_transition", "long_term_goal_status") == "ACTIVE_FOUNDER_MANUALLY_CREATED"
    abort "P0-05 task not accepted" unless baseline_task["status"] == "accepted"
    abort "P0-05 Gate result drift" unless baseline_task["gate_result"] == "P0_GATE_PASS_BY_FOUNDER_DECISION"
    gate_text = File.read("docs/aios/P0_GATE.md")
    abort "P0 Gate artifact does not record PASS" unless gate_text.include?("P0_GATE_PASS_BY_FOUNDER_DECISION")
    abort "P0 Gate artifact authorizes P1" unless gate_text.include?("p1_authorized: false")
    %w[P0\ remains\ NO-GO Founder\ Gate\ remain\ open].each do |forbidden|
      abort "P0 Gate retains contradictory current-state text: #{forbidden}" if gate_text.include?(forbidden)
    end
    abort "P0 Gate still says contract acceptance is open" if gate_text.include?("independent acceptance remains open")
    abort "strategy version drift" unless state.dig("authority", "strategy", "version") == "2.3"
    abort "strategy must remain frozen" unless state.dig("authority", "strategy", "status") == "FROZEN"
    abort "execution protocol version drift" unless state.dig("authority", "execution_protocol", "version") == "1.0"
    abort "legacy context filter overstated" unless state.dig("runtime_restrictions", "legacy_context_retrieval_filter") == "NOT_IMPLEMENTED_GOVERNANCE_ALLOWLIST_ONLY"
    [truth_task, slice_f_task, authority_task, baseline_task].each do |task|
      abort "task phase drift" unless task["phase"] == "P0"
      %w[write_scope acceptance_criteria required_evidence stop_conditions forbidden_actions].each do |field|
        abort "task field missing: #{task["task_id"]}.#{field}" unless task[field].is_a?(Array) && !task[field].empty?
      end
    end
    %w[task-spec environment-snapshot system-configuration run-record].each do |name|
      JSON.parse(File.read("docs/aios/schemas/#{name}.schema.json"))
    end
    binding_path = File.expand_path(state.dig("current_worktree_preservation", "truth_binding"))
    abort "historical truth binding hash drift" unless Digest::SHA256.file(binding_path).hexdigest == state.dig("current_worktree_preservation", "truth_binding_sha256")
    overlay_path = File.expand_path(state.dig("p0_04c_candidate_overlay", "binding"))
    overlay = JSON.parse(File.read(overlay_path))
    patch_path = File.expand_path(overlay.dig("overlay", "patch_path"))
    abort "overlay patch hash drift" unless Digest::SHA256.file(patch_path).hexdigest == overlay.dig("overlay", "patch_sha256")
    expected = %w[AGENTS.md CHAIRMAN_BRIEFING.md docs/PROJECT_CODE_MAP.md docs/aios/CODEX_MASTER_PROMPT.md docs/aios/P0_GATE.md docs/aios/README.md docs/aios/tasks/P0-05_BASELINE_SLICING.yaml docs/aios/truth/project_state.yaml scripts/validate-aios-governance.sh].sort
    changed = IO.popen(["git", "diff", "--name-only", "ad6450e418d8f1b4fd5a789f913525a8dd8bdc10"], &:read).lines.map(&:strip).reject(&:empty?).sort
    abort "post-Gate change set escaped allowlist: #{changed.inspect}" unless changed == expected
    staged = IO.popen(["git", "diff", "--cached", "--name-only"], &:read).strip
    abort "staged changes forbidden during validation" unless staged.empty?
    receipt_path_raw = ENV["AIOS_POST_GATE_TRANSITION_RECEIPT_PATH"]
    receipt_sha = ENV["AIOS_POST_GATE_TRANSITION_RECEIPT_SHA256"]
    abort "hash-pinned post-Gate receipt path required" if receipt_path_raw.to_s.empty?
    abort "valid post-Gate receipt SHA required" unless receipt_sha.to_s.match?(/\A[0-9a-f]{64}\z/)
    receipt_path = File.expand_path(receipt_path_raw)
    abort "post-Gate receipt missing or symlink" unless File.file?(receipt_path) && !File.symlink?(receipt_path)
    abort "post-Gate receipt escapes audit root" unless File.realpath(receipt_path).start_with?("#{audit_root}/")
    abort "post-Gate receipt hash mismatch" unless Digest::SHA256.file(receipt_path).hexdigest == receipt_sha
    receipt = JSON.parse(File.read(receipt_path))
    abort "post-Gate receipt type drift" unless receipt["record_type"] == "sourcelens_aios_post_gate_authority_transition_receipt"
    head = IO.popen(["git", "rev-parse", "HEAD"], &:read).strip
    tree = IO.popen(["git", "rev-parse", "HEAD^{tree}"], &:read).strip
    abort "transition HEAD not bound by receipt" unless head == receipt.dig("transition", "commit")
    abort "transition tree not bound by receipt" unless tree == receipt.dig("transition", "tree")
    status = IO.popen(["git", "status", "--porcelain=v1", "-uall"], &:read)
    abort "transition workspace must be clean" unless status.empty?
    descriptors = receipt.fetch("changed_path_descriptors")
    abort "receipt descriptor path set mismatch" unless descriptors.map { |d| d.fetch("path") }.sort == expected
    descriptors.each do |descriptor|
      path = descriptor.fetch("path")
      stat = File.lstat(path)
      abort "transition path symlink rejected: #{path}" if File.symlink?(path)
      abort "transition path hash drift: #{path}" unless Digest::SHA256.file(path).hexdigest == descriptor.fetch("sha256")
      abort "transition path size drift: #{path}" unless stat.size == descriptor.fetch("bytes")
      abort "transition path mode drift: #{path}" unless (stat.mode & 0777) == descriptor.fetch("mode")
    end
    exit 0
  end

  abort "project current_phase must be P0 during this migration" unless state.dig("project", "current_phase") == "P0"
  abort "project phase_status must remain IN_PROGRESS" unless state.dig("project", "phase_status") == "IN_PROGRESS"
  abort "strategy version must be 2.3" unless state.dig("authority", "strategy", "version") == "2.3"
  abort "execution protocol version must be 1.0" unless state.dig("authority", "execution_protocol", "version") == "1.0"
  abort "P0 gate recommendation must remain NO_GO" unless state.dig("p0_control_plane", "independent_review", "p0_gate_recommendation") == "NO_GO"
  abort "legacy context filter must not be overstated as technical enforcement" unless state.dig("runtime_restrictions", "legacy_context_retrieval_filter") == "NOT_IMPLEMENTED_GOVERNANCE_ALLOWLIST_ONLY"

  expected_tasks = {
    "AIOS-P0-004A" => [truth_task, %w[accepted]],
    "AIOS-P0-004B" => [slice_f_task, %w[accepted]],
    "AIOS-P0-004C" => [authority_task, %w[review_pending accepted]],
    "AIOS-P0-005" => [baseline_task, %w[CHECKPOINT_CREATED_PENDING_INDEPENDENT_REVIEW]]
  }
  expected_tasks.each do |task_id, (task, expected_statuses)|
    abort "task id drifted: #{task_id}" unless task["task_id"] == task_id
    abort "task phase must remain P0: #{task_id}" unless task["phase"] == "P0"
    abort "task status drifted: #{task_id}" unless expected_statuses.include?(task["status"])
    %w[write_scope acceptance_criteria required_evidence stop_conditions forbidden_actions].each do |field|
      value = task[field]
      abort "task field must be a nonempty list: #{task_id}.#{field}" unless value.is_a?(Array) && !value.empty?
    end
  end
  p0_05 = state.fetch("active_p0_work").find { |item| item["id"] == "P0-05" }
  abort "P0-05 is missing from active_p0_work" unless p0_05
  expected_contract = "docs/aios/tasks/P0-05_BASELINE_SLICING.yaml"
  abort "P0-05 task contract reference drifted" unless p0_05["task_contract_ref"] == expected_contract
  checkpoint_pending_review = "CHECKPOINT_CREATED_PENDING_INDEPENDENT_REVIEW"
  acceptance_pending_review = "P0_05_CHECKPOINT_CREATED_PENDING_INDEPENDENT_REVIEW"
  checkpoint_created = "CHECKPOINT_COMMIT_CREATED_PENDING_INDEPENDENT_REVIEW"
  gate_no_go = "P0_GATE_NO_GO_FOUNDER_DECISION_REQUIRED"
  abort "P0-05 current state must record checkpoint review pending" unless p0_05["status"] == checkpoint_pending_review
  abort "P0-05 task and Truth Registry status disagree" unless baseline_task["status"] == checkpoint_pending_review
  [p0_05, baseline_task].each do |record|
    abort "P0-05 classification result drifted" unless record["classification_result"] == "CLASSIFICATION_EVIDENCE_PASS"
    abort "P0-05 acceptance must remain pending independent review" unless record["acceptance_result"] == acceptance_pending_review
    abort "P0-05 checkpoint must remain pending independent review" unless record["checkpoint_result"] == checkpoint_created
    abort "P0 gate must remain Founder-decision NO-GO" unless record["gate_result"] == gate_no_go
    abort "P1 must remain unauthorized" unless record["p1_authorized"] == false
    abort "F focused gate independent-review result drifted" unless record.dig("remaining_closure_results", "f_focused_gate") == "PASS_INDEPENDENT_REVIEW_ACCEPTED"
    abort "unsafe F isolation must not be represented as applied" unless record.dig("remaining_closure_results", "f_isolation") == "NOT_PROVEN_SAFE_NOT_APPLIED_REPAIR_ROUTE_SELECTED"
    abort "MySQL focused smoke result drifted" unless record.dig("remaining_closure_results", "mysql_flyway_smoke") == "PASS_FOCUSED_DISPOSABLE_MYSQL_8_4"
    abort "code-map freshness result drifted" unless record.dig("remaining_closure_results", "code_map_freshness") == "PASS_CANONICAL_GENERATOR_VERIFIED"
    abort "offsite media must remain independently reverified" unless record.dig("remaining_closure_results", "offsite_current_readability") == "PASS_EXTERNAL_PHYSICAL_DEVICE_REVERIFIED"
  end
  abort "P0-05 starting snapshot semantics are overstated" unless baseline_task["baseline_semantics"] == "CAPTURED_PRE_INDEPENDENT_REVIEW_STARTING_STATE_NOT_EXACT_CURRENT_WORKTREE"

  p0_04c = state.fetch("active_p0_work").find { |item| item["id"] == "P0-04C" }
  abort "P0-04C is missing from active_p0_work" unless p0_04c
  expected_p0_04c_state = {
    "review_pending" => "IMPLEMENTED_REVIEW_PENDING",
    "accepted" => "COMPLETE_INDEPENDENT_REVIEW_PASS"
  }.fetch(authority_task.fetch("status"))
  abort "P0-04C contract and Truth Registry status disagree" unless p0_04c["status"] == expected_p0_04c_state

  expected_completed = {
    "P0-04A" => "COMPLETE_INDEPENDENT_REVIEW_PASS",
    "P0-04B" => "COMPLETE_INDEPENDENT_REVIEW_PASS"
  }
  expected_completed.each do |task_id, expected_status|
    item = state.fetch("active_p0_work").find { |candidate| candidate["id"] == task_id }
    abort "active P0 task is missing: #{task_id}" unless item
    abort "active P0 task review status drifted: #{task_id}" unless item["status"] == expected_status
  end

  preservation = state.fetch("current_worktree_preservation")
  current_head = IO.popen(["git", "rev-parse", "HEAD"], &:read).strip
  preserved_head = preservation.fetch("expected_head")
  abort "checkpoint candidate must descend from the preserved baseline" unless system("git", "merge-base", "--is-ancestor", preserved_head, current_head)
  declared_binding = preservation.fetch("truth_binding")
  declared_binding_hash = preservation.fetch("truth_binding_sha256")
  abort "P0-05 final exact-state attestation drifted" unless baseline_task["final_exact_state_attestation_ref"] == declared_binding
  abort "P0-05 truth-binding hash drifted" unless baseline_task["final_exact_state_attestation_sha256"] == declared_binding_hash
  abort "current-state exactness must resolve externally" unless preservation["current_state_exact"] == "RESOLVE_FROM_EXTERNAL_ATTESTATION"
  abort "snapshot verification must be read-only after P0-04C" unless preservation["verification_behavior"] == "READ_ONLY_BY_DEFAULT_AFTER_P0_04C"

  binding_path = File.expand_path(ENV.fetch("AIOS_TRUTH_BINDING_PATH"))
  abort "truth binding is missing or not a regular file: #{binding_path}" unless File.file?(binding_path)
  abort "truth binding must not be a symlink: #{binding_path}" if File.symlink?(binding_path)
  actual_binding_hash = Digest::SHA256.file(binding_path).hexdigest
  abort "truth binding hash mismatch: #{binding_path}" unless actual_binding_hash == declared_binding_hash

  binding = JSON.parse(File.read(binding_path))
  abort "truth binding schema drifted" unless binding["schema_version"] == 1
  abort "truth binding record type drifted" unless binding["record_type"] == "sourcelens_aios_external_truth_binding"
  abort "truth binding HEAD disagrees with canonical preservation" unless binding["head"] == preservation["expected_head"]
  abort "truth binding phase must remain P0" unless binding["phase"] == "P0"
  abort "truth binding P0 gate must remain NOT_READY" unless binding["p0_gate"] == "NOT_READY"
  abort "truth binding must not authorize P1" unless binding["p1_authorized"] == false
  abort "truth binding P0-05 status drifted" unless binding["p0_05_status"] == "CONTRACT_READY_PARTITION_NOT_STARTED"

  snapshot = binding.fetch("snapshot")
  abort "truth binding tracked count drifted" unless snapshot["tracked_changed_count"] == preservation["expected_tracked_changed_count"]
  abort "truth binding untracked count drifted" unless snapshot["untracked_file_count"] == preservation["expected_untracked_file_count"]
  abort "truth binding staged count drifted" unless snapshot["staged_changed_count"] == preservation["expected_staged_changed_count"]
  %w[artifact_hashes_valid untracked_copy_hashes_valid tracked_patch_disposable_restore_valid].each do |field|
    abort "truth binding no longer proves #{field}" unless snapshot[field] == true
  end

  exact = binding.fetch("exact_state_comparison")
  %w[current_tracked_patch_matches_snapshot current_status_matches_snapshot current_untracked_paths_match_snapshot current_truth_registry_matches_snapshot current_p0_gate_matches_snapshot].each do |field|
    abort "truth binding exact-state comparison failed: #{field}" unless exact[field] == true
  end
  abort "truth binding reports repository changes after capture" unless exact["repository_files_changed_after_capture"] == false

  snapshot_root = File.dirname(binding_path)
  bound_artifacts = {
    "manifest.json" => snapshot.fetch("manifest_sha256"),
    "verification.json" => snapshot.fetch("verification_sha256"),
    "tracked.patch" => snapshot.fetch("tracked_patch_sha256"),
    "status.porcelain-v1.z" => snapshot.fetch("status_porcelain_sha256"),
    "untracked-paths.z" => snapshot.fetch("untracked_paths_sha256"),
    "make-verify.log" => binding.fetch("full_verification").fetch("log_sha256")
  }
  bound_artifacts.each do |relative_path, expected_hash|
    artifact_path = File.join(snapshot_root, relative_path)
    abort "bound snapshot artifact is missing: #{artifact_path}" unless File.file?(artifact_path)
    actual_hash = Digest::SHA256.file(artifact_path).hexdigest
    abort "bound snapshot artifact hash mismatch: #{relative_path}" unless actual_hash == expected_hash
  end

  overlay_path = File.expand_path(baseline_task.dig("authority_decontamination_overlay", "binding_ref"))
  abort "P0-04C overlay binding reference drifted" unless overlay_path == File.expand_path(authority_task.fetch("external_overlay_binding_ref"))
  abort "Truth Registry overlay binding reference drifted" unless overlay_path == File.expand_path(state.dig("p0_04c_candidate_overlay", "binding"))
  abort "P0-04C overlay binding is missing: #{overlay_path}" unless File.file?(overlay_path)
  abort "P0-04C overlay binding must not be a symlink" if File.symlink?(overlay_path)
  overlay = JSON.parse(File.read(overlay_path))
  abort "P0-04C overlay binding schema drifted" unless overlay["schema_version"] == 1
  abort "P0-04C overlay binding type drifted" unless overlay["record_type"] == "sourcelens_aios_p0_04c_overlay_binding"
  abort "P0-04C overlay baseline truth hash drifted" unless overlay.dig("baseline", "truth_binding_sha256") == declared_binding_hash
  abort "P0-04C overlay baseline HEAD drifted" unless overlay.dig("baseline", "head") == preservation["expected_head"]

  patch_path = File.expand_path(overlay.dig("overlay", "patch_path"))
  abort "P0-04C overlay patch is missing" unless File.file?(patch_path)
  abort "P0-04C overlay patch must not be a symlink" if File.symlink?(patch_path)
  abort "P0-04C overlay patch hash mismatch" unless Digest::SHA256.file(patch_path).hexdigest == overlay.dig("overlay", "patch_sha256")
  human_diff_path = File.expand_path(overlay.dig("overlay", "human_diff_path"))
  abort "P0-04C human diff is missing" unless File.file?(human_diff_path)
  abort "P0-04C human diff hash mismatch" unless Digest::SHA256.file(human_diff_path).hexdigest == overlay.dig("overlay", "human_diff_sha256")

  expected_overlay_paths = authority_task.fetch("changed_path_inventory").values.flatten.sort
  abort "P0-04C changed-path inventory must contain ten unique paths" unless expected_overlay_paths.length == 10 && expected_overlay_paths.uniq.length == 10
  bound_paths = overlay.fetch("changed_paths").map { |entry| entry.fetch("path") }.sort
  abort "P0-04C overlay paths disagree with the Task Contract" unless bound_paths == expected_overlay_paths
  # The immutable overlay binds capture/application-time evidence. Current-state
  # governance deltas are instead bound by a separately hash-pinned transition receipt.
  receipt_path_raw = ENV["AIOS_P0_TRANSITION_RECEIPT_PATH"]
  receipt_sha = ENV["AIOS_P0_TRANSITION_RECEIPT_SHA256"]
  abort "current stopped state requires a transition receipt path" if receipt_path_raw.to_s.empty?
  abort "current stopped state requires a pinned transition receipt hash" unless receipt_sha.to_s.match?(/\A[0-9a-f]{64}\z/)
  receipt_path = File.expand_path(receipt_path_raw)
  abort "transition receipt is missing or not a regular file" unless File.file?(receipt_path)
  abort "transition receipt must not be a symlink" if File.symlink?(receipt_path)
  audit_root_real = File.realpath("/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit")
  abort "transition receipt real path escapes the trusted audit root" unless File.realpath(receipt_path).start_with?("#{audit_root_real}/")
  abort "transition receipt hash mismatch" unless Digest::SHA256.file(receipt_path).hexdigest == receipt_sha
  receipt = JSON.parse(File.read(receipt_path))
  abort "transition receipt schema drifted" unless receipt["schema_version"] == 1
  abort "transition receipt type drifted" unless receipt["record_type"] == "sourcelens_aios_p0_state_transition_receipt"
  abort "transition receipt parent truth binding mismatch" unless receipt.dig("parents", "truth_binding_sha256") == declared_binding_hash
  abort "transition receipt parent overlay binding mismatch" unless receipt.dig("parents", "overlay_binding_sha256") == Digest::SHA256.file(overlay_path).hexdigest
  abort "transition receipt parent overlay patch mismatch" unless receipt.dig("parents", "overlay_patch_sha256") == overlay.dig("overlay", "patch_sha256")
  previous_receipt_path = File.expand_path(receipt.fetch("previous_transition_receipt"))
  abort "previous transition receipt is missing" unless File.file?(previous_receipt_path)
  abort "previous transition receipt must not be a symlink" if File.symlink?(previous_receipt_path)
  abort "previous transition receipt escapes trusted audit root" unless File.realpath(previous_receipt_path).start_with?("#{audit_root_real}/")
  abort "previous transition receipt hash mismatch" unless Digest::SHA256.file(previous_receipt_path).hexdigest == receipt.fetch("previous_transition_receipt_sha256")
  previous_receipt = JSON.parse(File.read(previous_receipt_path))
  previous_manifest_path = File.expand_path(receipt.fetch("previous_repair_evidence_manifest"))
  abort "previous repair evidence manifest is missing" unless File.file?(previous_manifest_path)
  abort "previous repair evidence manifest must not be a symlink" if File.symlink?(previous_manifest_path)
  abort "previous repair evidence manifest escapes trusted audit root" unless File.realpath(previous_manifest_path).start_with?("#{audit_root_real}/")
  abort "previous repair evidence manifest hash mismatch" unless Digest::SHA256.file(previous_manifest_path).hexdigest == receipt.fetch("previous_repair_evidence_manifest_sha256")
  sealed_manifest = File.expand_path(receipt.fetch("sealed_p0_05_evidence_manifest"))
  abort "sealed P0-05 evidence manifest missing" unless File.file?(sealed_manifest)
  abort "sealed P0-05 evidence manifest must not be a symlink" if File.symlink?(sealed_manifest)
  abort "sealed P0-05 evidence manifest real path escapes the trusted audit root" unless File.realpath(sealed_manifest).start_with?("#{audit_root_real}/")
  abort "sealed P0-05 evidence manifest hash mismatch" unless Digest::SHA256.file(sealed_manifest).hexdigest == receipt.fetch("sealed_p0_05_evidence_manifest_sha256")
  sealed = JSON.parse(File.read(sealed_manifest))
  ownership_artifact = sealed.fetch("artifacts").find { |item| item["path"] == "evidence/classification/path-ownership-manifest.json" }
  abort "sealed P0-05 manifest does not bind the ownership manifest" unless ownership_artifact
  ownership_path = File.expand_path(ownership_artifact.fetch("path"), File.dirname(sealed_manifest))
  abort "ownership manifest missing" unless File.file?(ownership_path)
  abort "ownership manifest must not be a symlink" if File.symlink?(ownership_path)
  abort "ownership manifest escapes sealed evidence root" unless File.realpath(ownership_path).start_with?("#{File.realpath(File.dirname(sealed_manifest))}/")
  abort "ownership manifest hash mismatch" unless Digest::SHA256.file(ownership_path).hexdigest == ownership_artifact.fetch("sha256")
  ownership = JSON.parse(File.read(ownership_path))
  allowed_transition_paths = %w[
    scripts/validate-aios-governance.sh
    docs/aios/tasks/P0-05_BASELINE_SLICING.yaml
    docs/aios/truth/project_state.yaml
    docs/aios/P0_GATE.md
    docs/PROJECT_CODE_MAP.md
    web-console/src/pages/AgentChat.tsx
    web-console/tests/agent-chat-first-viewport-smoke.spec.ts
  ].sort
  workspace_real = File.realpath(Dir.pwd)
  assert_workspace_file = lambda do |candidate_path, relative_path|
    abort "candidate path is missing: #{relative_path}" unless File.file?(candidate_path)
    abort "candidate path must not be a symlink: #{relative_path}" if File.symlink?(candidate_path)
    candidate_real = File.realpath(candidate_path)
    abort "candidate real path escapes workspace: #{relative_path}" unless candidate_real.start_with?("#{workspace_real}/")
  end
  overlay.fetch("changed_paths").each do |entry|
    relative_path = entry.fetch("path")
    next if allowed_transition_paths.include?(relative_path)
    candidate_path = File.expand_path(relative_path, Dir.pwd)
    abort "P0-04C overlay path escapes the candidate workspace: #{relative_path}" unless candidate_path.start_with?("#{Dir.pwd}/")
    assert_workspace_file.call(candidate_path, relative_path)
    abort "P0-04C non-transition candidate path hash mismatch: #{relative_path}" unless Digest::SHA256.file(candidate_path).hexdigest == entry.fetch("sha256")
  end
  changed = receipt.fetch("changed_paths")
  abort "transition receipt allowlist mismatch" unless changed.map { |entry| entry.fetch("path") }.sort == allowed_transition_paths
  changed.each do |entry|
    relative_path = entry.fetch("path")
    candidate_path = File.expand_path(relative_path, Dir.pwd)
    abort "transition path escapes candidate workspace" unless candidate_path.start_with?("#{Dir.pwd}/")
    assert_workspace_file.call(candidate_path, relative_path)
    current = entry.fetch("current")
    stat = File.lstat(candidate_path)
    abort "transition current hash mismatch: #{relative_path}" unless Digest::SHA256.file(candidate_path).hexdigest == current.fetch("sha256")
    abort "transition current byte count mismatch: #{relative_path}" unless stat.size == current.fetch("bytes")
    abort "transition current mode mismatch: #{relative_path}" unless (stat.mode & 0777) == current.fetch("mode")
    abort "transition current type mismatch: #{relative_path}" unless current.fetch("type") == "file"
  end
  ownership_entries = ownership.fetch("entries")
  ownership_by_path = ownership_entries.map { |entry| [entry.fetch("path"), entry] }.to_h
  tracked_paths = IO.popen(["git", "diff", "--name-only", "-z", preservation.fetch("expected_head"), "HEAD"], &:read).split("\0").reject(&:empty?)
  untracked_paths = IO.popen(["git", "ls-files", "--others", "--exclude-standard", "-z"], &:read).split("\0").reject(&:empty?)
  current_path_set = (tracked_paths + untracked_paths).sort
  abort "current changed path set drifted from sealed 318-path ownership manifest" unless current_path_set == ownership_by_path.keys.sort
  staged_paths = IO.popen(["git", "diff", "--cached", "--name-only", "-z"], &:read).split("\0").reject(&:empty?)
  abort "staged changes are forbidden during this transition" unless staged_paths.empty?
  abort "numbered duplicate paths detected" if untracked_paths.any? { |path| path.match?(/ [0-9]+(?:\.[^\/]*)?\z/) }
  descriptor_deltas = []
  ownership_entries.each do |before|
    relative_path = before.fetch("path")
    candidate_path = File.expand_path(relative_path, Dir.pwd)
    assert_workspace_file.call(candidate_path, relative_path)
    stat = File.lstat(candidate_path)
    current_descriptor = {"type" => "file", "mode" => stat.mode & 0777, "bytes" => stat.size, "sha256" => Digest::SHA256.file(candidate_path).hexdigest}
    before_descriptor = before.slice("type", "mode", "bytes", "sha256")
    descriptor_deltas << relative_path unless current_descriptor == before_descriptor
  end
  abort "workspace descriptor delta is not exactly the authorized seven-path allowlist" unless descriptor_deltas.sort == allowed_transition_paths
  previous_by_path = previous_receipt.fetch("changed_paths").map { |entry| [entry.fetch("path"), entry.fetch("current")] }.to_h
  changed.each do |entry|
    relative_path = entry.fetch("path")
    expected_pre = previous_by_path.fetch(relative_path) { ownership_by_path.fetch(relative_path).slice("type", "mode", "bytes", "sha256") }
    abort "transition pre descriptor mismatch" unless entry.fetch("pre") == expected_pre
  end
  expected_transition = {
    "p0_05_status" => checkpoint_pending_review,
    "p0_05_acceptance" => acceptance_pending_review,
    "checkpoint" => checkpoint_created,
    "p0_gate" => gate_no_go,
    "p1_authorized" => false
  }
  abort "transition receipt current-state claim mismatch" unless receipt["current_state"] == expected_transition
  abort "transition receipt lacks Founder authorization binding" unless receipt["founder_authorization"] == "2026-07-11_P0_05_CHECKPOINT_CREATION_AUTHORIZED"
  abort "transition receipt Founder authorization source drifted" unless receipt["founder_authorization_source"] == "current_codex_task_explicit_founder_approval_to_create_p0_05_checkpoint"
  %w[baseline_reference_status_matches patch_apply_check_passed candidate_hashes_match_after_apply nonignored_workspace_difference_empty].each do |field|
    abort "P0-04C overlay verification failed: #{field}" unless overlay.dig("verification", field) == true
  end

  [truth_task, slice_f_task].each do |task|
    inventory = task.fetch("changed_path_inventory")
    paths = inventory.values.flatten
    abort "changed-path inventory must be nonempty: #{task.fetch("task_id")}" if paths.empty?
    missing = paths.reject { |path| File.exist?(path) }
    abort "changed-path inventory references missing paths: #{missing.inspect}" unless missing.empty?
    abort "changed-path inventory contains duplicates: #{task.fetch("task_id")}" unless paths.uniq.length == paths.length
  end

  assets = ledger.fetch("assets")
  ids = assets.map { |asset| asset.fetch("id") }
  abort "migration asset ids must be unique" unless ids.uniq.length == ids.length

  allowed = %w[KEEP REFACTOR QUARANTINE FREEZE BUILD_NEW CANDIDATE_ARCHIVE]
  invalid = assets.reject { |asset| allowed.include?(asset.fetch("decision")) }
  abort "invalid migration decision: #{invalid.inspect}" unless invalid.empty?

  %w[STRATEGY_LEGACY HISTORICAL_LEDGERS DUPLICATE_STATUS_DOCS].each do |id|
    asset = assets.find { |candidate| candidate.fetch("id") == id }
    abort "missing legacy migration asset: #{id}" unless asset
    abort "legacy asset must be excluded from default Agent context: #{id}" unless asset["default_agent_context"] == "EXCLUDED"
  end

  if assets.any? { |asset| asset.fetch("decision") == "CANDIDATE_REMOVE" }
    abort "P0 must not classify an asset as CANDIDATE_REMOVE"
  end

  owned_paths = assets
    .select { |asset| asset.fetch("scope_kind") == "paths" }
    .flat_map { |asset| asset.fetch("scope").map { |path| [path, asset.fetch("id")] } }
  duplicates = owned_paths.group_by(&:first).select { |_path, owners| owners.length > 1 }
  abort "path ownership overlaps: #{duplicates.inspect}" unless duplicates.empty?
'

binding_root="$(cd "$(dirname "$AIOS_TRUTH_BINDING_PATH")" && pwd -P)"
node scripts/preserve-worktree-snapshot.mjs --verify "$binding_root" >/dev/null \
  || fail "bound snapshot failed full tracked and untracked reconstruction"

grep -Fq 'docs/aios/truth/project_state.yaml' AGENTS.md || fail "root AGENTS.md no longer points to canonical truth"
grep -Fq 'Do not load them into default context' AGENTS.md || fail "root AGENTS.md no longer excludes legacy context by default"
grep -Fq 'SOURCELENS_SNAPSHOT_VERIFICATION_RECEIPT' scripts/preserve-worktree-snapshot.mjs || fail "snapshot verification no longer exposes an external receipt boundary"
if grep -Fq 'fs.writeFileSync(path.join(absoluteSnapshot, "verification.json")' scripts/preserve-worktree-snapshot.mjs; then
  fail "snapshot verification still mutates the immutable snapshot directory"
fi

if grep -Fq 'preserved current-combined-state' docs/aios/tasks/P0-05_BASELINE_SLICING.yaml; then
  fail "P0-05 still overstates the pre-independent-review snapshot as current"
fi

grep -Fq 'exact post-remediation state is resolved only from the external attestation' docs/aios/P0_GATE.md \
  || fail "P0 Gate no longer declares its in-tree snapshot evidence boundary"

ruby -rjson -e '
  JSON.parse(File.read("docs/aios/schemas/task-spec.schema.json"))
  JSON.parse(File.read("docs/aios/schemas/environment-snapshot.schema.json"))
  JSON.parse(File.read("docs/aios/schemas/system-configuration.schema.json"))
  JSON.parse(File.read("docs/aios/schemas/run-record.schema.json"))
'

active_entries=(
  README.md
  ROADMAP.md
  CHAIRMAN_BRIEFING.md
  CONTRIBUTING.md
  docs/README.md
  docs/SOURCELENS_OPERATING_SYSTEM.md
  docs/TEAM_OPERATING_MODEL.md
  web-console/src/pages/Dashboard.tsx
)

legacy_current_pattern='Current phase.*P9|当前主线仍是 P6|SourceLens 采用 `11 个固定核心角色|release-current-schema-20260704-1618.*当前|P9 三平面|P6/P10/P11 按证据并行推进|Trusted Engineering Loop Completion Rate|completed P0 gate packet'
if grep -En "$legacy_current_pattern" "${active_entries[@]}"; then
  fail "an active entry still declares a legacy phase, team or release authority"
fi

legacy_files=(
  docs/PROJECT_PLAN.md
  docs/PHASE_REQUIREMENTS.md
  docs/PRODUCT_POSITIONING_AND_ACCESS_MODEL.md
  docs/TOP_LEVEL_PRODUCT_OPERATING_DEFINITIONS.md
  docs/AGENT_STATUS_BOARD.md
  docs/CODEX_HANDOFF.md
  docs/WORK_INTAKE_AND_BACKLOG.md
  docs/QUALITY_SCORECARD.md
  docs/PRODUCT_PROGRESS_LOG.md
  docs/REFACTOR_ROADMAP.md
  docs/PRODUCT_METRICS_AND_FEEDBACK.md
  docs/AGENT_ACTIVITY_LOG.md
  docs/AGENT_DECISION_REGISTER.md
)

for file in "${legacy_files[@]}"; do
  head -n 8 "$file" | grep -Eq 'AIOS v2\.3 状态' \
    || fail "legacy document is missing its AIOS status banner: $file"
  head -n 8 "$file" | grep -Fq 'DEFAULT AGENT CONTEXT: `EXCLUDED`' \
    || fail "legacy document is not excluded from default Agent context: $file"
done

if grep -Eq 'ENTRY_AUTHORIZED_(CONTRACT_REFROZEN_V10_PENDING_INDEPENDENT_REVIEW|FEM_V5_BOUNDED_OBSERVATION_ACCEPTED_P1_001_EXECUTION_BLOCKED)' docs/aios/truth/project_state.yaml; then
  grep -Fq 'authorized entry into P1 Agent Evaluation and Research Foundation' CHAIRMAN_BRIEFING.md \
    || fail "Founder briefing does not expose current P1 entry authorization"
  grep -Fq 'AIOS-P1-001 execution' docs/aios/README.md \
    && grep -Fq 'not started or authorized' docs/aios/README.md \
    || fail "Authority index does not preserve the P1-001 execution stop"
  grep -Fq 'P1 entry is authorized. AIOS-P1-001 execution is not.' CHAIRMAN_BRIEFING.md \
    || fail "Founder briefing does not separate P1 entry from P1-001 execution"
  grep -Fq 'REFROZEN_V10_PENDING_INDEPENDENT_PRE_EXECUTION_REVIEW' docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml \
    || fail "P1-001 contract is not refrozen for pre-execution review"
  grep -Fq 'execution_start_authorized: false' docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml \
    || fail "P1-001 contract improperly starts execution"
  grep -Fq 'FOUNDER_ACCEPTED_FOR_CONTROLLED_P1_IMPLEMENTATION' docs/aios/EVALUATION_PROTOCOL.md \
    || fail "Evaluation Protocol acceptance state is stale"
  grep -Fq 'FOUNDER_ACCEPTED_CONTROLLED_P1_IMPLEMENTATION_DEFINITION' docs/aios/BASELINE_ADAPTER_CONTRACT.md \
    || fail "Baseline Adapter Contract acceptance state is stale"
  grep -Fq 'Current state: P0 Strategic Foundation is complete and the Founder has authorized' AGENTS.md \
    || fail "AGENTS entry does not expose current P1 authorization"
  grep -Fq '当前阶段是 `P1 Agent Evaluation and Research Foundation`' README.md \
    || fail "root README current phase is stale"
  grep -Fq 'Current phase: `P1 Agent Evaluation and Research Foundation`' ROADMAP.md \
    || fail "roadmap current phase is stale"
  grep -Fq 'currently in `P1 Agent Evaluation and Research Foundation`' CONTRIBUTING.md \
    || fail "contribution boundary current phase is stale"
  grep -Fq 'Current phase: `P1 Agent Evaluation and Research Foundation`' docs/SOURCELENS_OPERATING_SYSTEM.md \
    || fail "operating-system current phase is stale"
  grep -Fq 'Current phase: `P1 Agent Evaluation and Research Foundation`' docs/TEAM_OPERATING_MODEL.md \
    || fail "team-model current phase is stale"
  grep -Fq "value: 'P1 Evaluation Foundation'" web-console/src/pages/Dashboard.tsx \
    || fail "Dashboard current phase is stale"
  grep -Fq 'P1-001 execution: NOT AUTHORIZED' web-console/src/pages/Dashboard.tsx \
    || fail "Dashboard does not preserve P1-001 execution stop"
  if grep -Fq 'P1 remains unauthorized' docs/aios/CODEX_MASTER_PROMPT.md \
    || grep -Fq 'P1 and AIOS-P1-001 are not authorized' docs/aios/README.md \
    || grep -Fq 'P1 remains `NOT AUTHORIZED`' CHAIRMAN_BRIEFING.md \
    || grep -Fq 'Current phase: `P0 Strategic Foundation`' ROADMAP.md \
    || grep -Fq 'currently in `P0 Strategic Foundation`' CONTRIBUTING.md; then
    fail "active authority entry retains the superseded P1-not-authorized state"
  fi
elif grep -Fq 'COMPLETE_FOUNDER_GATE_PASS_P1_NOT_AUTHORIZED' docs/aios/truth/project_state.yaml; then
  grep -Fq 'P0 Founder Gate is `PASS`' CHAIRMAN_BRIEFING.md \
    || fail "Founder briefing does not expose P0 PASS"
  grep -Fq 'P1 and AIOS-P1-001' CHAIRMAN_BRIEFING.md \
    || fail "Founder briefing does not expose the separate P1 authorization boundary"
  grep -Fq 'remain separately `NOT AUTHORIZED`' CHAIRMAN_BRIEFING.md \
    || fail "Founder briefing no longer records P1 as unauthorized"
  grep -Fq 'The Human Founder has accepted the P0 checkpoint' CHAIRMAN_BRIEFING.md \
    || fail "Founder briefing does not record the current P0 Gate result"
  if grep -Fq 'P0 is complete only when:' CHAIRMAN_BRIEFING.md \
    || grep -Fq 'The only current objective is to turn the inherited SourceLens worktree' CHAIRMAN_BRIEFING.md; then
    fail "Founder briefing retains an unqualified pre-Gate current-state assertion"
  fi
  grep -Fq 'historical `NO-GO`' docs/aios/README.md \
    || fail "Authority index does not classify the old NO-GO state as historical"
  grep -Fq 'later Human Founder P0 Gate' docs/aios/README.md \
    || fail "Authority index does not preserve Founder PASS precedence"
  if grep -Fq 'final control-plane PASS does not change the P0 `NO-GO` gate' docs/aios/README.md; then
    fail "Authority index retains the pre-Founder NO-GO state as current"
  fi
  grep -Fq -- '- Status: `PASS`' docs/aios/P0_GATE.md \
    || fail "P0 gate artifact does not expose PASS"
  grep -Fq 'P1 remains unauthorized' docs/aios/CODEX_MASTER_PROMPT.md \
    || fail "Codex prompt does not preserve P1 block"
else
grep -Fq 'P0 Strategic Foundation' web-console/src/pages/Dashboard.tsx \
  || fail "Dashboard does not expose the current P0 phase"
grep -Fq 'Verified Task Success Rate' web-console/src/pages/Dashboard.tsx \
  || fail "Dashboard does not expose the frozen north-star metric"
grep -Fq 'P0-05 Baseline Slicing' web-console/src/pages/Dashboard.tsx \
  || fail "Dashboard does not expose P0-05 as the current project task"
grep -Fq '继承产品运行建议（非项目任务）' web-console/src/pages/Dashboard.tsx \
  || fail "Dashboard does not separate inherited product operations from AIOS project work"
grep -Fq 'P0 gate packet is `NOT_READY`' CHAIRMAN_BRIEFING.md \
  || fail "Founder briefing does not expose the current P0 gate state"
grep -Fq -- '- Status: `NOT_READY`' docs/aios/P0_GATE.md \
  || fail "P0 gate artifact must remain NOT_READY"
fi
grep -Fq 'Do not load, index or summarize legacy documents into default planning context.' docs/aios/CODEX_MASTER_PROMPT.md \
  || fail "Codex entry prompt is missing the legacy-context allowlist rule"
grep -Fq 'Flyway (V001 ~ V032)' docs/DATABASE_DESIGN.md \
  || fail "database migration range is stale"
grep -Fq 'https://github.com/LJunP/SourceLens/security/policy' .github/ISSUE_TEMPLATE/config.yml \
  || fail "security-policy link does not target SourceLens"
grep -Fq '<description>SourceLens AIOS' backend-spring/pom.xml \
  || fail "backend metadata still uses the legacy product description"

grep -Fq 'B0 Direct Model' docs/aios/EVALUATION_PROTOCOL.md \
  || fail "Baseline Suite B0 is missing"
grep -Fq 'B2 Current SourceLens' docs/aios/EVALUATION_PROTOCOL.md \
  || fail "Baseline Suite B2 is missing"
grep -Fq 'Verified Task Success Rate' docs/aios/STRATEGIC_CONSTITUTION.md \
  || fail "the north-star metric is missing"
grep -Fq 'Patch Evidence Package' docs/aios/EVALUATION_PROTOCOL.md \
  || fail "the Patch Evidence contract is missing"

echo "AIOS_GOVERNANCE_OK"

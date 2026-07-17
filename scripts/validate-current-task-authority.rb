#!/usr/bin/env ruby
# encoding: UTF-8

require "digest"
require "English"
require "json"
require "pathname"
require "time"
require "yaml"

REPO_ROOT = File.expand_path("..", __dir__)
TRUTH_PATH = File.join(REPO_ROOT, "docs/aios/truth/project_state.yaml")
AGENT_RULES_PATH = File.join(REPO_ROOT, "AGENTS.md")

FOUNDER_HISTORICAL_METADATA_CLASSES = %w[
  TASK_AND_CONTRACT_IDENTITY TERMINAL_RECORD CONTRACT_REVIEW_RESULT EVIDENCE_HASH
  NON_RECOVERY_AND_NON_REUSE_MARKER
].freeze

HISTORICAL_ARTIFACT_CLASS_PROJECTION = {
  "CONTRACT_REVIEW_FAILURE" => %w[
    TASK_AND_CONTRACT_IDENTITY CONTRACT_REVIEW_RESULT EVIDENCE_HASH NON_RECOVERY_AND_NON_REUSE_MARKER
  ],
  "FOUNDER_DECISION" => %w[
    TASK_AND_CONTRACT_IDENTITY EVIDENCE_HASH NON_RECOVERY_AND_NON_REUSE_MARKER
  ],
  "TERMINAL_RECORD" => %w[
    TASK_AND_CONTRACT_IDENTITY TERMINAL_RECORD CONTRACT_REVIEW_RESULT EVIDENCE_HASH
    NON_RECOVERY_AND_NON_REUSE_MARKER
  ],
  "INDEPENDENT_CONTRACT_REVIEW" => %w[
    TASK_AND_CONTRACT_IDENTITY CONTRACT_REVIEW_RESULT EVIDENCE_HASH NON_RECOVERY_AND_NON_REUSE_MARKER
  ]
}.freeze
HISTORICAL_SEMANTIC_PROJECTION_ALLOWED = false
ACTIVE_WORK_KEYS = %w[
  current_task current_task_status current_task_contract current_task_contract_sha256
  current_execution_authorization current_execution_authorization_sha256 execution_nonce
  execution_nonce_status authorization_id activation_parent_commit activation_parent_tree
  task_resource_state task_branch task_worktree execution_evidence_root offsite_target
  founder_reserved_authorization founder_reserved_authorization_sha256 founder_decision_required
  escalation_reason user_action_required next_eligible_action
].freeze

def stop!(message)
  warn "CURRENT TASK AUTHORITY FAIL: #{message}"
  exit 1
end

def nonempty_string?(value)
  value.is_a?(String) && !value.strip.empty?
end

def nonempty_list?(value)
  value.is_a?(Array) && !value.empty?
end

def valid_utc_timestamp?(value)
  return false unless nonempty_string?(value)
  parsed = Time.iso8601(value)
  parsed.utc? && value.end_with?("Z")
rescue ArgumentError
  false
end

def sha256(path)
  Digest::SHA256.file(path).hexdigest
end

def bound_json!(path, expected_sha256, root, label)
  stop!("#{label} path/hash invalid") unless nonempty_string?(path) && expected_sha256.is_a?(String) && expected_sha256.match?(/\A[0-9a-f]{64}\z/)
  stop!("#{label} missing or outside custody") unless safe_under_root?(path, root, must_exist: true) && File.file?(path)
  stop!("#{label} hash drift") unless sha256(path) == expected_sha256
  JSON.parse(File.read(path))
rescue JSON::ParserError
  stop!("#{label} is not valid JSON")
end

def historical_boundary_entry!(boundary, path, expected_sha256, expected_format, expected_class, label)
  stop!("#{label} historical boundary missing") unless boundary.is_a?(Hash)
  entries = boundary["allowed_records"]
  stop!("#{label} historical allowlist invalid") unless entries.is_a?(Array)
  matches = entries.select { |entry| entry.is_a?(Hash) && entry["path"] == path }
  stop!("#{label} is not admitted by one exact historical metadata record") unless matches.length == 1
  entry = matches.first
  stop!("#{label} historical allowlist entry schema drift") unless
    entry.keys.sort == %w[
      allowed_top_level_fields byte_length format founder_metadata_classes path
      projected_semantic_json_pointers record_class sha256
    ].sort
  stop!("#{label} historical allowlist binding drift") unless
    entry["sha256"] == expected_sha256 &&
    entry["format"] == expected_format &&
    entry["record_class"] == expected_class &&
    entry["byte_length"].is_a?(Integer) && entry["byte_length"] >= 0 &&
    entry["allowed_top_level_fields"].is_a?(Array) &&
    !entry["allowed_top_level_fields"].empty? &&
    entry["allowed_top_level_fields"].all? { |field| nonempty_string?(field) } &&
    entry["allowed_top_level_fields"].uniq.length == entry["allowed_top_level_fields"].length &&
    entry["founder_metadata_classes"] == HISTORICAL_ARTIFACT_CLASS_PROJECTION.fetch(expected_class) &&
    entry["projected_semantic_json_pointers"] == []
  entry
end

def bound_historical_governance_bytes!(boundary, path, expected_sha256, expected_format, expected_class, root, label)
  entry = historical_boundary_entry!(boundary, path, expected_sha256, expected_format, expected_class, label)
  stop!("#{label} missing or outside historical governance custody") unless safe_under_root?(path, root, must_exist: true) && File.file?(path) && !File.symlink?(path)
  bytes = File.binread(path)
  stop!("#{label} historical byte length drift") unless bytes.bytesize == entry["byte_length"]
  stop!("#{label} historical hash drift") unless Digest::SHA256.hexdigest(bytes) == expected_sha256
  bytes
end

def verify_historical_governance_json!(boundary, path, expected_sha256, expected_class, root, label)
  entry = historical_boundary_entry!(boundary, path, expected_sha256, "JSON", expected_class, label)
  bytes = bound_historical_governance_bytes!(boundary, path, expected_sha256, "JSON", expected_class, root, label)
  record = JSON.parse(bytes)
  stop!("#{label} historical metadata field allowlist drift") unless
    record.is_a?(Hash) && record.keys.sort == entry["allowed_top_level_fields"].sort
  stop!("#{label} unexpectedly exposes historical semantic fields") unless entry["projected_semantic_json_pointers"] == []
  true
rescue JSON::ParserError
  stop!("#{label} is not valid JSON")
end

def bound_historical_governance_json!(*_args)
  stop!("historical governance metadata semantic projection is disabled")
end

def capability_binding_fields(capabilities)
  capabilities.length == 1 ? { "mandatory_exit_capability" => capabilities.first } : { "mandatory_exit_capabilities" => capabilities }
end

def record_capabilities(record)
  integrated = record["integrated_mandatory_exit_capabilities"]
  return integrated if integrated.is_a?(Array)
  capability = record["mandatory_exit_capability"]
  capability ? [capability] : []
end

def validate_artifact_index!(index, evidence_root, task_id, capabilities, commit, tree)
  expected_binding = capability_binding_fields(capabilities)
  stop!("accepted Exit capability artifact index mixes scalar and integrated bindings") if capabilities.length == 1 ? index.key?("mandatory_exit_capabilities") : index.key?("mandatory_exit_capability")
  stop!("accepted Exit capability artifact index header drift") unless index["record_type"] == "aios_p1_mandatory_capability_artifact_index" && index["status"] == "FROZEN" && index["task_id"] == task_id && expected_binding.all? { |key, value| index[key] == value } && index["candidate_commit"] == commit && index["candidate_tree"] == tree
  artifacts = index["artifacts"]
  stop!("accepted Exit capability artifact index is empty") unless artifacts.is_a?(Array) && !artifacts.empty?
  paths = []
  artifacts.each do |artifact|
    stop!("accepted Exit capability artifact index entry schema drift") unless artifact.is_a?(Hash) && artifact.keys.sort == %w[byte_length path sha256].sort && artifact["path"].is_a?(String) && artifact["sha256"].is_a?(String) && artifact["sha256"].match?(/\A[0-9a-f]{64}\z/) && artifact["byte_length"].is_a?(Integer) && artifact["byte_length"] >= 0
    relative = Pathname.new(artifact["path"])
    stop!("accepted Exit capability artifact path is not canonical relative") if relative.absolute? || relative.cleanpath.to_s != artifact["path"] || artifact["path"] == "."
    absolute = File.join(evidence_root, artifact["path"])
    stop!("accepted Exit capability artifact escaped Evidence root") unless safe_under_root?(absolute, evidence_root, must_exist: true) && File.file?(absolute) && !File.symlink?(absolute)
    bytes = File.binread(absolute)
    stop!("accepted Exit capability artifact identity drift") unless bytes.bytesize == artifact["byte_length"] && Digest::SHA256.hexdigest(bytes) == artifact["sha256"]
    paths << artifact["path"]
  end
  stop!("accepted Exit capability artifact index contains duplicate paths") unless paths.uniq.length == paths.length
end

def exact_terminal_status?(value)
  value.is_a?(String) && (value == "TERMINAL_STOPPED" || value.start_with?("TERMINAL_STOPPED_"))
end

def git(*args)
  output = IO.popen(["git", "-C", REPO_ROOT, *args], err: File::NULL, &:read)
  stop!("git command failed: #{args.join(' ')}") unless $CHILD_STATUS.success?
  output.strip
end

def git_at(root, *args)
  output = IO.popen(["git", "-C", root, *args], err: File::NULL, &:read)
  stop!("git command failed at #{root}: #{args.join(' ')}") unless $CHILD_STATUS.success?
  output.strip
end

def git_file(ref, path)
  output = IO.popen(["git", "-C", REPO_ROOT, "show", "#{ref}:#{path}"], err: File::NULL, &:read)
  $CHILD_STATUS.success? ? output : nil
end

def previous_truth_transition(current_bytes)
  relative_path = "docs/aios/truth/project_state.yaml"
  head_bytes = git_file("HEAD", relative_path)
  return nil unless head_bytes
  return [head_bytes, current_bytes] unless head_bytes == current_bytes

  last_change = git("log", "-1", "--format=%H", "--", relative_path)
  return nil if last_change.empty?
  previous_bytes = git_file("#{last_change}^", relative_path)
  changed_bytes = git_file(last_change, relative_path)
  previous_bytes && changed_bytes ? [previous_bytes, changed_bytes] : nil
end

def existing_ancestor(path)
  current = File.expand_path(path)
  loop do
    return current if File.exist?(current) || File.symlink?(current)
    parent = File.dirname(current)
    return nil if parent == current
    current = parent
  end
end

def safe_under_root?(path, root, must_exist: false)
  return false unless nonempty_string?(path) && nonempty_string?(root)
  root_expanded = File.expand_path(root)
  path_expanded = File.expand_path(path)
  return false unless path_expanded == root_expanded || path_expanded.start_with?(root_expanded + File::SEPARATOR)
  return false unless File.directory?(root_expanded) && !File.symlink?(root_expanded)

  root_real = File.realpath(root_expanded)
  relative = Pathname.new(path_expanded).relative_path_from(Pathname.new(root_expanded))
  cursor = root_expanded
  relative.each_filename do |component|
    cursor = File.join(cursor, component)
    break unless File.exist?(cursor) || File.symlink?(cursor)
    return false if File.symlink?(cursor)
  end

  if must_exist
    return false unless File.exist?(path_expanded) && !File.symlink?(path_expanded)
    resolved = File.realpath(path_expanded)
    resolved == root_real || resolved.start_with?(root_real + File::SEPARATOR)
  else
    ancestor = existing_ancestor(path_expanded)
    return false unless ancestor && !File.symlink?(ancestor)
    resolved = File.realpath(ancestor)
    resolved == root_real || resolved.start_with?(root_real + File::SEPARATOR)
  end
rescue ArgumentError, Errno::ENOENT, Errno::EACCES
  false
end

def flatten_scope(scope)
  case scope
  when Array
    scope
  when Hash
    scope.values.flat_map { |value| value.is_a?(Array) ? value : [] }
  else
    []
  end
end

def recursive_values(value, key, found = [])
  case value
  when Hash
    found << value[key] if value.key?(key)
    value.each_value { |child| recursive_values(child, key, found) }
  when Array
    value.each { |child| recursive_values(child, key, found) }
  end
  found.compact
end

def recursive_strings(value, found = [])
  case value
  when Hash
    value.each_value { |child| recursive_strings(child, found) }
  when Array
    value.each { |child| recursive_strings(child, found) }
  when String
    found << value
  end
  found
end

def scope_base(pattern, absolute: false)
  return nil unless nonempty_string?(pattern)
  pathname = Pathname.new(pattern)
  return nil unless pathname.absolute? == absolute
  return nil if pattern.include?("?") || pattern.include?("[") || pattern.include?("]")
  if pattern.include?("*")
    return nil unless pattern.end_with?("/**") && pattern.count("*") == 2
    base = pattern.delete_suffix("/**")
  else
    base = pattern
  end
  return nil if base.empty?
  segments = Pathname.new(base).each_filename.to_a
  return nil if segments.any? { |segment| segment == "." || segment == ".." }
  clean = Pathname.new(base).cleanpath.to_s
  return nil unless clean == base
  clean
end

def path_overlap?(left, right)
  left == "." || right == "." || left == right ||
    left.start_with?(right + File::SEPARATOR) || right.start_with?(left + File::SEPARATOR)
end

def truth_without_activation_fields(value)
  copy = Marshal.load(Marshal.dump(value))
  copy.delete("last_verified_at")
  copy.delete("verification_scope")
  copy["goal"].delete("current_task_authority")
  copy["project"].delete("phase_execution_status")
  copy["project"].delete("p1_execution_status")
  copy.delete("active_work")
  copy.fetch("phase_execution_claim").delete("current_task_claim")
  copy.fetch("mandatory_exit_capability_recovery").delete("capability_status")
  copy.fetch("mandatory_exit_capability_recovery").delete("capability_attempt_ledger")
  copy.fetch("mandatory_exit_capability_recovery").delete("final_clean_room_implementation_attempt")
  copy.fetch("mandatory_exit_capability_recovery").delete("post_revision_final_implementation_attempt")
  rebaseline = copy.fetch("mandatory_exit_capability_recovery")["project_level_rebaseline"]
  if rebaseline.is_a?(Hash)
    %w[p1_status current_task slice_attempts next_slice_ordinal next_slice_action].each { |field| rebaseline.delete(field) }
  end
  copy
end

def worktree_records
  output = git("worktree", "list", "--porcelain")
  output.split(/\n\n+/).map do |block|
    fields = {}
    block.lines.each do |line|
      key, value = line.strip.split(" ", 2)
      fields[key] = value || true
    end
    fields unless fields.empty?
  end.compact
end

truth_bytes = File.binread(TRUTH_PATH).force_encoding(Encoding::UTF_8)
rules = File.binread(AGENT_RULES_PATH).force_encoding(Encoding::UTF_8)
stop!("Truth is not valid UTF-8") unless truth_bytes.valid_encoding?
stop!("AGENTS.md is not valid UTF-8") unless rules.valid_encoding?
truth = YAML.safe_load(truth_bytes, aliases: false)

required_rule_markers = [
  "docs/aios/FOUNDER_DELEGATION_POLICY.md",
  "## Phase 级 Founder Delegation（强制执行）",
  "Founder 只保留：",
  "在当前 Phase 已获 Founder entry 授权且不触及上述保留事项时，Master 必须自主完成：",
  "强制反死循环规则：",
  "正常情况下，Founder 的下一个介入点是 Phase Gate"
]
required_rule_markers.each do |marker|
  stop!("AGENTS.md delegation rule missing: #{marker}") unless rules.include?(marker)
end

policy = truth.dig("authority", "founder_delegation_policy")
stop!("Founder delegation policy authority missing") unless policy.is_a?(Hash)
policy_rel = policy["path"]
stop!("Founder delegation policy path invalid") unless nonempty_string?(policy_rel) && !Pathname.new(policy_rel).absolute? && Pathname.new(policy_rel).cleanpath.to_s == policy_rel
policy_abs = File.join(REPO_ROOT, policy_rel)
stop!("Founder delegation policy missing") unless safe_under_root?(policy_abs, REPO_ROOT, must_exist: true)
stop!("Founder delegation policy hash drift") unless policy["sha256"] == sha256(policy_abs)
stop!("Founder delegation policy inactive") unless policy["status"] == "FOUNDER_DIRECTIVE_ACTIVE"
stop!("Founder delegation policy version drift") unless %w[1.1 1.2].include?(policy["version"])

delegation = truth.fetch("phase_delegation")
stop!("phase delegation is not active") unless delegation["status"] == "ACTIVE"
stop!("phase delegation model drift") unless delegation["model"] == "PHASE_LEVEL_FOUNDER_DELEGATION"
stop!("phase gate owner drift") unless delegation["phase_gate_owner"] == "HUMAN_FOUNDER"
stop!("task selection owner drift") unless delegation["task_selection_owner"] == "MASTER_CEO_AGENT"
stop!("task authorization owner drift") unless delegation["task_authorization_owner"] == "MASTER_CEO_AGENT_WITHIN_CURRENT_PHASE_ENVELOPE"
stop!("task gate owner drift") unless delegation["task_gate_owner"] == "MASTER_CEO_AGENT_AFTER_REQUIRED_INDEPENDENT_REVIEW"

expected_reserved = %w[
  mission_icp_year_one_or_phase_route_change
  phase_entry_or_exit
  material_scope_budget_or_permission_expansion_beyond_phase_envelope
  network_provider_secret_remote_production_or_public_effect
  irreversible_asset_removal
  material_legal_privacy_commercial_commitment
  critical_residual_risk_acceptance
]
stop!("Founder reserved decision set drift") unless delegation["founder_reserved_decisions"] == expected_reserved

expected_delegated = %w[
  select_reject_sequence_and_freeze_phase_local_tasks
  assign_roles_workers_reviewers_and_disjoint_write_ownership
  authorize_and_execute_local_task_branch_worktree_and_commands
  perform_in_scope_implementation_tests_repairs_evidence_replay_and_rollback
  accept_return_or_terminally_stop_tasks_after_independent_review
  integrate_task_to_local_canonical_main_after_task_gate
  choose_the_next_independent_phase_local_task_after_task_completion_or_stop
]
stop!("Agent delegated decision set drift") unless delegation["agent_delegated_decisions"] == expected_delegated

anti_loop = delegation.fetch("anti_loop")
stop!("routine Founder approval re-enabled") unless anti_loop["routine_founder_task_approval_required"] == false
stop!("per-file approval re-enabled") unless anti_loop["per_file_or_command_approval_required"] == false
stop!("ordinary repairs escaped the Task") unless anti_loop["ordinary_repairs_stay_in_same_task"] == true
stop!("successor chain re-enabled") unless anti_loop["successor_replacement_correction_chain_allowed"] == false
stop!("Task-specific hardcoding re-enabled") unless anti_loop["task_id_hardcoding_in_current_authority_validator_allowed"] == false
expected_contract_repair_limit = policy["version"] == "1.2" ? 0 : 1
stop!("post-freeze Contract correction policy drift") unless anti_loop["maximum_same_task_bounded_contract_repairs"] == expected_contract_repair_limit
stop!("historical execution lineage reuse re-enabled") unless anti_loop["historical_execution_lineage_reuse_allowed"] == false
stop!("historical stop permanently bans mandatory capability recovery") unless anti_loop["mandatory_exit_capability_permanent_ban_from_historical_stop"] == false
stop!("peripheral work re-enabled before P1 Exit capabilities") unless anti_loop["peripheral_work_before_exit_capabilities_allowed"] == false

mandatory_recovery = truth.fetch("mandatory_exit_capability_recovery")
expected_exit_capabilities = %w[
  VERSIONED_REPRESENTATIVE_TASK_DATASET
  HIDDEN_SET_PROTOCOL
  PARAMETERIZED_EVALUATION_HARNESS
  VTSR_COUNTING_VALIDATOR
  B0_B1_B2_COMPATIBILITY_ADAPTERS
  OBSERVABLE_TRACE
  EVALUATOR_DISAGREEMENT_AND_FALSE_SUCCESS_CHARACTERIZATION
  REPRODUCIBLE_BASELINE_REPORT
]
mandatory_capability_claim_boundary = "P1_EXIT_CAPABILITY_ENGINEERING_ARTIFACT_ONLY_NO_BENCHMARK_AGENT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM"
stop!("mandatory Exit capability recovery is inactive") unless mandatory_recovery["status"] == "ACTIVE"
stop!("mandatory Exit capability priority drift") unless mandatory_recovery["priority_order"] == expected_exit_capabilities
stop!("historical Task immutability weakened") unless mandatory_recovery["historical_tasks_immutable"] == true
stop!("historical execution lineage reuse enabled") unless mandatory_recovery["historical_execution_lineage_reuse_allowed"] == false
stop!("clean-room recovery disabled") unless mandatory_recovery["clean_room_implementation_allowed_for_required_capability"] == true
stop!("clean-room attempt count drift") unless mandatory_recovery["clean_room_attempts_per_missing_capability"] == 1
stop!("rebaseline post-freeze Contract correction limit drift") unless mandatory_recovery["maximum_same_task_bounded_contract_repairs"] == expected_contract_repair_limit
stop!("peripheral Task selection enabled") unless mandatory_recovery["peripheral_task_selection_allowed"] == false
capability_status = mandatory_recovery["capability_status"]
stop!("mandatory Exit capability status population drift") unless capability_status.is_a?(Hash) && capability_status.keys == expected_exit_capabilities
allowed_capability_states = %w[MISSING RELOCATED_PENDING_INTEGRATED_TASK FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION FOUNDER_REVISED_PENDING_IMPLEMENTATION REBASELINED_PENDING_EXECUTION IN_PROGRESS ACCEPTED FOUNDER_DISPOSED ARCHITECTURE_BLOCKED CONTRACT_REVIEW_BLOCKED]
stop!("mandatory Exit capability status invalid") unless capability_status.values.all? { |value| allowed_capability_states.include?(value) }
attempt_ledger = mandatory_recovery["capability_attempt_ledger"]
stop!("mandatory Exit capability attempt ledger population drift") unless attempt_ledger.is_a?(Hash) && attempt_ledger.keys == expected_exit_capabilities
founder_dispositions = mandatory_recovery["founder_dispositions"]
stop!("mandatory Exit capability Founder disposition map invalid") unless founder_dispositions.is_a?(Hash) && (founder_dispositions.keys - expected_exit_capabilities).empty?
history_entries_for_recovery = truth.fetch("task_history").values.select { |entry| entry.is_a?(Hash) }
recovery_evidence_base = truth.dig("project", "execution_evidence_root_base")
stop!("mandatory Exit capability Evidence base invalid") unless File.directory?(recovery_evidence_base) && !File.symlink?(recovery_evidence_base)

rebaseline = mandatory_recovery["project_level_rebaseline"]
stop!("Founder Delegation Policy v1.2 requires the P1 project-level rebaseline binding") if policy["version"] == "1.2" && !rebaseline.is_a?(Hash)
if rebaseline
expected_rebaseline_keys = %w[
  record_type status authority approved_at_utc plan_path plan_sha256 plan_byte_length
  decision_record_path decision_record_sha256 decision_record_byte_length
  canonical_parent_commit canonical_parent_tree p1_status current_task task_limit
  engineering_hours_limit calendar_days_limit final_contracts_per_task
  post_freeze_contract_corrections successor_replacement_correction_chain_allowed
  default_external_effects_authorized slices slice_attempts next_slice_ordinal next_slice_action
]
stop!("P1 project-level rebaseline schema drift") unless
  rebaseline.is_a?(Hash) && rebaseline.keys.sort == expected_rebaseline_keys.sort
stop!("P1 project-level rebaseline authority drift") unless
  rebaseline["record_type"] == "p1_exit_gate_project_level_rebaseline" &&
  rebaseline["status"] == "FOUNDER_APPROVED_ACTIVE" &&
  rebaseline["authority"] == "HUMAN_FOUNDER" &&
  valid_utc_timestamp?(rebaseline["approved_at_utc"])
stop!("P1 project-level rebaseline parent drift") unless
  rebaseline["canonical_parent_commit"] == "eca59026d57f6c67f268a44d41564fdb0a2ecc5f" &&
  rebaseline["canonical_parent_tree"] == "29db5c1bd565e582a6a209f6a81c9efb0349f3e4" &&
  git("rev-parse", "#{rebaseline['canonical_parent_commit']}^{tree}") == rebaseline["canonical_parent_tree"]
{
  "plan" => [rebaseline["plan_path"], rebaseline["plan_sha256"], rebaseline["plan_byte_length"], "ab0ba04abd4900758a3b4502fac21bdf6c392754666694a41c30c451e9058c29", 15_748],
  "Founder decision" => [rebaseline["decision_record_path"], rebaseline["decision_record_sha256"], rebaseline["decision_record_byte_length"], "083dc4d5f071bb82b6da3681c62e5a4ce37bfa8cac52c3f4da0f0ac5fea2d1f2", 8_799]
}.each do |label, (path, digest, byte_length, exact_digest, exact_length)|
  stop!("P1 rebaseline #{label} identity drift") unless digest == exact_digest && byte_length == exact_length
  stop!("P1 rebaseline #{label} missing or outside audit custody") unless
    safe_under_root?(path, recovery_evidence_base, must_exist: true) && File.file?(path) && !File.symlink?(path)
  bytes = File.binread(path)
  stop!("P1 rebaseline #{label} byte drift") unless bytes.bytesize == byte_length && Digest::SHA256.hexdigest(bytes) == digest
end
stop!("P1 rebaseline budget or anti-loop boundary drift") unless
  %w[REBASELINED_PENDING_EXECUTION REBASELINED_SLICE_ACTIVE P1_EXIT_EVIDENCE_COMPLETE_PENDING_FOUNDER_GATE].include?(rebaseline["p1_status"]) &&
  rebaseline["task_limit"] == 4 &&
  rebaseline["engineering_hours_limit"] == 76 &&
  rebaseline["calendar_days_limit"] == 21 &&
  rebaseline["final_contracts_per_task"] == 1 &&
  rebaseline["post_freeze_contract_corrections"] == 0 &&
  rebaseline["successor_replacement_correction_chain_allowed"] == false &&
  rebaseline["default_external_effects_authorized"] == false
expected_rebaseline_slices = [
  [1, "PARAMETERIZED_EVALUATION_CORE", %w[PARAMETERIZED_EVALUATION_HARNESS VTSR_COUNTING_VALIDATOR OBSERVABLE_TRACE], 24, 5, 2, 1, nil, "COOPERATIVE_LOCAL_PARAMETERIZED_EVALUATION_CORE_CONFORMANCE_ONLY_NO_B0_B1_B2_BASELINE_AGENT_P1_EXIT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM"],
  [2, "B0_B1_B2_COMPATIBILITY_ADAPTERS", %w[B0_B1_B2_COMPATIBILITY_ADAPTERS], 24, 5, 2, 1, nil, "COOPERATIVE_LOCAL_B0_B1_B2_ADAPTER_CONFORMANCE_ONLY_NO_REAL_BASELINE_AGENT_P1_EXIT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM"],
  [3, "FRESH_SYNTHETIC_HOLDOUT_AND_EVALUATOR_CALIBRATION", %w[HIDDEN_SET_PROTOCOL EVALUATOR_DISAGREEMENT_AND_FALSE_SUCCESS_CHARACTERIZATION], 16, 4, 1, 1, nil, "COOPERATIVE_LOCAL_FRESH_SYNTHETIC_ROLE_SEPARATION_AND_EVALUATOR_CALIBRATION_ONLY_NO_REAL_HIDDEN_SET_REPRESENTATIVENESS_AGENT_P1_EXIT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM"],
  [4, "FROZEN_B0_B1_B2_BASELINE_EXPERIMENT_AND_P1_REPORT", %w[REPRODUCIBLE_BASELINE_REPORT], 12, 5, 1, 1, 48, "P1_INITIAL_SMALL_SAMPLE_REPRODUCIBLE_BASELINE_ONLY_NO_BROAD_GENERALIZATION_A0_P2_P3_PRODUCTION_OR_STATISTICAL_CERTAINTY_CLAIM"]
]
actual_rebaseline_slices = Array(rebaseline["slices"]).map do |slice|
  expected_keys = %w[ordinal name capability_projection engineering_hours calendar_days implementation_iterations candidate_limit claim_boundary]
  expected_keys << "scheduled_runs" if slice.is_a?(Hash) && slice.key?("scheduled_runs")
  stop!("P1 rebaseline slice schema drift") unless slice.is_a?(Hash) && slice.keys.sort == expected_keys.sort
  [slice["ordinal"], slice["name"], slice["capability_projection"], slice["engineering_hours"],
   slice["calendar_days"], slice["implementation_iterations"], slice["candidate_limit"], slice["scheduled_runs"], slice["claim_boundary"]]
end
stop!("P1 rebaseline slice plan drift") unless actual_rebaseline_slices == expected_rebaseline_slices
stop!("P1 rebaseline aggregate budget drift") unless
  actual_rebaseline_slices.sum { |slice| slice[3] } == rebaseline["engineering_hours_limit"] &&
  actual_rebaseline_slices.sum { |slice| slice[4] } <= rebaseline["calendar_days_limit"]
slice_attempts = rebaseline["slice_attempts"]
stop!("P1 rebaseline slice attempt ledger invalid") unless
  slice_attempts.is_a?(Hash) && (slice_attempts.keys - %w[1 2 3 4]).empty?
stop!("P1 rebaseline next slice ordinal invalid") unless rebaseline["next_slice_ordinal"].is_a?(Integer) && rebaseline["next_slice_ordinal"].between?(1, 5)
end

historical_metadata_boundary = mandatory_recovery["historical_governance_metadata_read_boundary"]
if historical_metadata_boundary
expected_boundary_keys = %w[
  record_type status authority decision_record_path decision_record_sha256 mode
  allowed_purposes semantic_task_input_allowed evaluator_or_oracle_input_allowed
  worker_access_allowed quality_fixture_author_access_allowed implementation_reuse_allowed
  transitive_path_discovery_allowed allowed_records forbidden_repository_read_paths
  forbidden_asset_classes founder_allowed_record_classes artifact_record_class_projection
  field_projection_policy
]
stop!("historical governance metadata boundary schema drift") unless
  historical_metadata_boundary.is_a?(Hash) && historical_metadata_boundary.keys.sort == expected_boundary_keys.sort
stop!("historical governance metadata boundary authority drift") unless
  historical_metadata_boundary["record_type"] == "p1_exit_gate_historical_governance_metadata_read_boundary" &&
  historical_metadata_boundary["status"] == "FOUNDER_APPROVED_ACTIVE" &&
  historical_metadata_boundary["authority"] == "HUMAN_FOUNDER" &&
  historical_metadata_boundary["mode"] == "VALIDATOR_ONLY_READ_ONLY_EXACT_HASH_BOUND_ALLOWLIST_DENY_BY_DEFAULT"
stop!("historical governance metadata purpose drift") unless historical_metadata_boundary["allowed_purposes"] == %w[
  CURRENT_AUTHORITY_VALIDATION
  HISTORICAL_TERMINAL_VALIDATION
  ROUTE_UNIQUENESS_VALIDATION
  HISTORICAL_ASSET_NON_REUSE_VALIDATION
  CURRENT_STATE_CONSISTENCY_VALIDATION
]
stop!("historical governance metadata leaked into a semantic or implementation role") unless
  historical_metadata_boundary["semantic_task_input_allowed"] == false &&
  historical_metadata_boundary["evaluator_or_oracle_input_allowed"] == false &&
  historical_metadata_boundary["worker_access_allowed"] == false &&
  historical_metadata_boundary["quality_fixture_author_access_allowed"] == false &&
  historical_metadata_boundary["implementation_reuse_allowed"] == false &&
  historical_metadata_boundary["transitive_path_discovery_allowed"] == false

boundary_decision_path = historical_metadata_boundary["decision_record_path"]
boundary_decision_sha = historical_metadata_boundary["decision_record_sha256"]
boundary_decision = bound_json!(boundary_decision_path, boundary_decision_sha, recovery_evidence_base, "P1 Exit Gate historical metadata boundary Founder decision")
stop!("historical governance metadata boundary Founder decision drift") unless
  boundary_decision["record_type"] == "sourcelens_aios_founder_p1_exit_gate_historical_governance_metadata_boundary_revision" &&
  boundary_decision["schema_version"] == "1.0" &&
  boundary_decision["status"] == "APPROVED" &&
  boundary_decision["authority"] == "HUMAN_FOUNDER" &&
  valid_utc_timestamp?(boundary_decision["approved_at_utc"]) &&
  boundary_decision["canonical_parent_commit"] == "dd11590b557ac7ee5604e5740e23c79f5b398601" &&
  boundary_decision["canonical_parent_tree"] == "374285b14b93925d93e6cbe045a438216f9a12e6" &&
  boundary_decision["goal_canonical_sha256"] == truth.dig("goal", "observed_body_sha256")
stop!("historical governance metadata Founder decision boundary drift") unless
  boundary_decision.dig("historical_governance_metadata_boundary", "classification") == "TRUSTED_VERIFICATION_SUBSTRATE_NOT_SEMANTIC_TASK_INPUT" &&
  boundary_decision.dig("historical_governance_metadata_boundary", "allowed_readers") == %w[INTEGRATION_ROLE AUTHORITY_VALIDATOR] &&
  boundary_decision.dig("historical_governance_metadata_boundary", "admission_source") == "CANONICAL_TRUTH_EXACT_HASH_BOUND_REFERENCES_ONLY" &&
  boundary_decision.dig("historical_governance_metadata_boundary", "allowed_record_classes") == %w[
    TASK_AND_CONTRACT_IDENTITY TERMINAL_RECORD CONTRACT_REVIEW_RESULT EVIDENCE_HASH NON_RECOVERY_AND_NON_REUSE_MARKER
  ] &&
  boundary_decision.dig("historical_governance_metadata_boundary", "allowed_purposes") == historical_metadata_boundary["allowed_purposes"] &&
  boundary_decision.dig("historical_governance_metadata_boundary", "semantic_task_input") == false &&
  boundary_decision.dig("historical_governance_metadata_boundary", "evaluator_or_oracle_input") == false &&
  boundary_decision.dig("historical_governance_metadata_boundary", "implementation_design_input") == false
stop!("historical governance metadata Founder class projection drift") unless
  historical_metadata_boundary["founder_allowed_record_classes"] == FOUNDER_HISTORICAL_METADATA_CLASSES &&
  boundary_decision.dig("historical_governance_metadata_boundary", "allowed_record_classes") == FOUNDER_HISTORICAL_METADATA_CLASSES &&
  historical_metadata_boundary["artifact_record_class_projection"] == HISTORICAL_ARTIFACT_CLASS_PROJECTION &&
  historical_metadata_boundary["field_projection_policy"] == "EXACT_HASH_BOUND_RAW_SCHEMA_WITH_EMPTY_SEMANTIC_PROJECTION" &&
  HISTORICAL_ARTIFACT_CLASS_PROJECTION.values.flatten.uniq.all? { |record_class| FOUNDER_HISTORICAL_METADATA_CLASSES.include?(record_class) }
stop!("historical failed engineering asset boundary drift") unless
  boundary_decision.dig("failed_engineering_asset_boundary", "worker_access_allowed") == false &&
  boundary_decision.dig("failed_engineering_asset_boundary", "quality_fixture_author_access_allowed") == false &&
  boundary_decision.dig("failed_engineering_asset_boundary", "real_or_historical_hidden_material_create_read_enumerate_or_restore_allowed") == false &&
  boundary_decision.dig("failed_engineering_asset_boundary", "historical_governance_metadata_may_influence_semantic_results") == false

allowed_historical_records = historical_metadata_boundary["allowed_records"]
stop!("historical governance metadata allowlist empty") unless allowed_historical_records.is_a?(Array) && !allowed_historical_records.empty?
allowed_historical_paths = allowed_historical_records.map { |entry| entry.is_a?(Hash) ? entry["path"] : nil }
expected_historical_paths = %w[
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-036-hidden-set-protocol/contract-review/CONTRACT_REVIEW_FAILURE_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-036-hidden-set-protocol/contract-review/FOUNDER_CONTRACT_REVIEW_CAP_EXCEPTION_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-036-hidden-set-protocol/contract-review/P1_036_FOUNDER_EXCEPTION_ROUTE_TERMINAL_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-036-hidden-set-protocol/contract-review/FOUNDER_INTEGRATED_VERTICAL_SLICE_ARCHITECTURE_DISPOSITION_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-037-parameterized-harness/contract-review/P1_037_INTEGRATED_ROUTE_TERMINAL_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-037-parameterized-harness/contract-review/CONTRACT_REVIEW_FAILURE_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-038-minimal-hidden-admission-harness/FOUNDER_ATTEMPT_ACCOUNTING_RECALIBRATION_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-038-minimal-hidden-admission-harness/contract-review/CTO_FINAL_CONTRACT_REVIEW.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-038-minimal-hidden-admission-harness/contract-review/SECURITY_FINAL_CONTRACT_REVIEW.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-038-minimal-hidden-admission-harness/contract-review/FINAL_CONTRACT_REVIEW_FAILURE_RECORD.json
  /Users/lijunpeng/Developer/.sourcelens-audit/p1-038-minimal-hidden-admission-harness/P1_038_ROUTE_TERMINAL_RECORD.json
]
stop!("historical governance metadata allowlist contains duplicate or invalid paths") unless
  allowed_historical_paths.all? { |path| nonempty_string?(path) && Pathname.new(path).absolute? } &&
  allowed_historical_paths.uniq.length == allowed_historical_paths.length
stop!("historical governance metadata allowlist is not the exact closed set") unless allowed_historical_paths == expected_historical_paths
allowed_historical_records.each do |entry|
  stop!("historical governance metadata allowlist entry schema drift") unless
    entry.is_a?(Hash) && entry.keys.sort == %w[
      allowed_top_level_fields byte_length format founder_metadata_classes path
      projected_semantic_json_pointers record_class sha256
    ].sort &&
    entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[0-9a-f]{64}\z/) &&
    entry["byte_length"].is_a?(Integer) && entry["byte_length"] >= 0 &&
    entry["format"] == "JSON" &&
    HISTORICAL_ARTIFACT_CLASS_PROJECTION.key?(entry["record_class"]) &&
    entry["founder_metadata_classes"] == HISTORICAL_ARTIFACT_CLASS_PROJECTION.fetch(entry["record_class"]) &&
    entry["projected_semantic_json_pointers"] == [] &&
    entry["allowed_top_level_fields"].is_a?(Array) && !entry["allowed_top_level_fields"].empty? &&
    entry["allowed_top_level_fields"].all? { |field| nonempty_string?(field) } &&
    entry["allowed_top_level_fields"].uniq.length == entry["allowed_top_level_fields"].length
  stop!("historical governance metadata allowlist path is unsafe") unless safe_under_root?(entry["path"], recovery_evidence_base, must_exist: true) && File.file?(entry["path"]) && !File.symlink?(entry["path"])
  verify_historical_governance_json!(
    historical_metadata_boundary,
    entry["path"],
    entry["sha256"],
    entry["record_class"],
    recovery_evidence_base,
    "historical governance metadata #{File.basename(entry['path'])}"
  )
end
stop!("historical failed Contract repository denylist drift") unless historical_metadata_boundary["forbidden_repository_read_paths"] == %w[
  docs/aios/tasks/P1-036_HIDDEN_SET_PROTOCOL.yaml
  docs/aios/tasks/P1-037_PARAMETERIZED_EVALUATION_HARNESS_WITH_HIDDEN_ADMISSION.yaml
  docs/aios/tasks/P1-038_MINIMAL_HIDDEN_ADMISSION_PARAMETERIZED_HARNESS_IMPLEMENTATION.yaml
]
stop!("historical failed asset-class denylist drift") unless historical_metadata_boundary["forbidden_asset_classes"] == %w[
  FAILED_TASK_CODE FAILED_TASK_FIXTURE FAILED_TASK_CANDIDATE FAILED_TASK_PARTIAL_IMPLEMENTATION
  FAILED_TASK_HIDDEN_MATERIAL FAILED_TASK_NONCE UNACCEPTED_ENGINEERING_ASSET
]
stop!("historical failed asset-class Founder projection drift") unless
  boundary_decision.dig("failed_engineering_asset_boundary", "forbidden_asset_classes") == historical_metadata_boundary["forbidden_asset_classes"]
else
  stop!("historical governance metadata boundary missing while historical routes remain active") unless
    (mandatory_recovery["integrated_capability_routes"] || {}).empty? &&
    mandatory_recovery["final_clean_room_implementation_route"].nil? &&
    mandatory_recovery["final_clean_room_contract_review_terminal"].nil? &&
    mandatory_recovery["post_revision_final_implementation_route"].nil?
  boundary_decision = nil
  boundary_decision_path = nil
  boundary_decision_sha = nil
end

integrated_routes = mandatory_recovery["integrated_capability_routes"]
stop!("integrated capability route map invalid") unless integrated_routes.is_a?(Hash) && integrated_routes.length <= 1
integrated_route_id, integrated_route = integrated_routes.first
integrated_route_capabilities = []
if (early_transition = previous_truth_transition(truth_bytes))
  early_previous_truth = YAML.safe_load(early_transition[0], aliases: false)
  early_previous_routes = early_previous_truth.dig("mandatory_exit_capability_recovery", "integrated_capability_routes") || {}
  if early_previous_routes.is_a?(Hash) && !early_previous_routes.empty?
    stop!("integrated capability route was removed, replaced, renamed or rebound") unless integrated_routes == early_previous_routes
  end
end
if integrated_route
  expected_route_keys = %w[
    record_type authority status decision_record_path decision_record_sha256
    architecture_decision_input_sha256 canonical_parent_commit canonical_parent_tree
    task_id primary_capability mandatory_exit_capabilities blocked_route
    atomic_all_or_none activation_limit reusable bounded_contract_corrections_allowed
    claim_boundary
  ]
  stop!("integrated capability route id invalid") unless integrated_route_id.is_a?(String) && integrated_route_id.match?(/\AP1_\d{3}_[A-Z0-9_]+\z/)
  stop!("integrated capability route schema drift") unless integrated_route.is_a?(Hash) && integrated_route.keys.sort == expected_route_keys.sort
  stop!("integrated capability route authority drift") unless integrated_route["record_type"] == "p1_founder_approved_integrated_capability_route" && integrated_route["authority"] == "HUMAN_FOUNDER" && integrated_route["status"] == "FOUNDER_APPROVED_ONE_TIME"
  integrated_route_capabilities = integrated_route["mandatory_exit_capabilities"]
  stop!("integrated capability route population invalid") unless integrated_route_capabilities.is_a?(Array) && integrated_route_capabilities.length == 2 && integrated_route_capabilities.uniq.length == 2 && (integrated_route_capabilities - expected_exit_capabilities).empty?
  route_indexes = integrated_route_capabilities.map { |capability| expected_exit_capabilities.index(capability) }
  stop!("integrated capability route must bind two adjacent capabilities in priority order") unless route_indexes[1] == route_indexes[0] + 1
  stop!("integrated capability route primary drift") unless integrated_route["primary_capability"] == integrated_route_capabilities.last
  stop!("integrated capability route safety invariant drift") unless integrated_route["atomic_all_or_none"] == true && integrated_route["activation_limit"] == 1 && integrated_route["reusable"] == false && integrated_route["bounded_contract_corrections_allowed"] == 1
  stop!("integrated capability route Task id invalid") unless nonempty_string?(integrated_route["task_id"]) && integrated_route["task_id"].match?(/\AAIOS-P1-\d{3}(?:[_-][A-Z0-9_-]+)?\z/)
  stop!("integrated capability route parent identity invalid") unless integrated_route["canonical_parent_commit"].is_a?(String) && integrated_route["canonical_parent_commit"].match?(/\A[0-9a-f]{40}\z/) && integrated_route["canonical_parent_tree"].is_a?(String) && integrated_route["canonical_parent_tree"].match?(/\A[0-9a-f]{40}\z/)
  stop!("integrated capability route parent object missing") unless system("git", "-C", REPO_ROOT, "cat-file", "-e", "#{integrated_route['canonical_parent_commit']}^{commit}", out: File::NULL, err: File::NULL)
  stop!("integrated capability route parent tree drift") unless git("rev-parse", "#{integrated_route['canonical_parent_commit']}^{tree}") == integrated_route["canonical_parent_tree"]

  blocked_route = integrated_route["blocked_route"]
  expected_blocked_keys = %w[task_id status terminal_record_sha256 recovery_allowed asset_reuse_allowed]
  stop!("integrated capability blocked-route schema drift") unless blocked_route.is_a?(Hash) && blocked_route.keys.sort == expected_blocked_keys.sort && blocked_route["recovery_allowed"] == false && blocked_route["asset_reuse_allowed"] == false
  blocked_capability = integrated_route_capabilities.first
  blocked_ledger = attempt_ledger[blocked_capability]
  stop!("integrated capability route does not preserve blocked ledger") unless blocked_ledger.is_a?(Hash) && blocked_ledger["task_id"] == blocked_route["task_id"] && blocked_ledger["founder_exception_route_status"] == blocked_route["status"] && blocked_ledger["founder_exception_terminal_record_sha256"] == blocked_route["terminal_record_sha256"] && blocked_ledger["founder_exception_route_recovery_allowed"] == false

  if HISTORICAL_SEMANTIC_PROJECTION_ALLOWED
  decision = bound_historical_governance_json!(historical_metadata_boundary, integrated_route["decision_record_path"], integrated_route["decision_record_sha256"], "FOUNDER_DECISION", recovery_evidence_base, "integrated capability Founder architecture disposition")
  expected_decision_keys = %w[
    record_type schema_version status authority approved_at_utc canonical_parent_commit
    canonical_parent_tree decision_input_path decision_input_sha256 blocked_route
    architecture_disposition required_read_boundary required_role_separation
    claim_boundary forbidden delegation terminal_rule
  ]
  stop!("integrated capability Founder disposition schema drift") unless decision.keys.sort == expected_decision_keys.sort
  stop!("integrated capability Founder disposition header drift") unless decision["record_type"] == "sourcelens_aios_founder_exit_capability_architecture_disposition" && decision["schema_version"] == 1 && decision["status"] == "APPROVED" && decision["authority"] == "HUMAN_FOUNDER"
  stop!("integrated capability Founder disposition parent drift") unless decision["canonical_parent_commit"] == integrated_route["canonical_parent_commit"] && decision["canonical_parent_tree"] == integrated_route["canonical_parent_tree"]
  stop!("integrated capability Founder disposition input identity drift") unless
    decision["decision_input_sha256"] == integrated_route["architecture_decision_input_sha256"]
  stop!("integrated capability Founder disposition blocked route drift") unless decision["blocked_route"] == {
    "task_id" => blocked_route["task_id"],
    "status" => blocked_route["status"],
    "terminal_record_path" => blocked_ledger["founder_exception_terminal_record_path"],
    "terminal_record_sha256" => blocked_route["terminal_record_sha256"],
    "recovery_allowed" => false,
    "asset_reuse_allowed" => false
  }
  blocked_terminal = bound_historical_governance_json!(historical_metadata_boundary, decision.dig("blocked_route", "terminal_record_path"), decision.dig("blocked_route", "terminal_record_sha256"), "TERMINAL_RECORD", recovery_evidence_base, "integrated capability blocked-route terminal record")
  blocked_failure = bound_historical_governance_json!(historical_metadata_boundary, blocked_ledger["failure_record_path"], blocked_ledger["failure_record_sha256"], "CONTRACT_REVIEW_FAILURE", recovery_evidence_base, "integrated capability blocked-route contract review failure")
  blocked_exception = bound_historical_governance_json!(historical_metadata_boundary, blocked_ledger["founder_exception_record_path"], blocked_ledger["founder_exception_record_sha256"], "FOUNDER_DECISION", recovery_evidence_base, "integrated capability blocked-route Founder exception")
  expected_blocked_terminal_keys = %w[
    record_type schema_version status recorded_at_utc task_id mandatory_exit_capability
    attempt_ordinal canonical_parent_commit canonical_parent_tree original_task_contract_sha256
    rejected_corrected_contract_sha256 prior_cto_final_review_sha256
    prior_contract_review_failure_record_sha256 founder_exception_record_sha256
    final_exception_contract_sha256 cto_final_exception_review_sha256
    cto_final_exception_review_result security_final_exception_review_sha256
    security_final_exception_review_result quality_final_exception_review_result
    blocking_finding mutation_oracle_blocker_closed implementation_started task_activated
    task_branch_created task_worktree_created candidate_created capability_claims
    route_recovery_allowed retry_allowed resume_allowed successor_allowed replacement_allowed
    correction_chain_allowed founder_escalation_required next_required_decision claim_boundary
  ]
  stop!("integrated capability blocked-route terminal record schema drift") unless blocked_terminal.keys.sort == expected_blocked_terminal_keys.sort
  stop!("integrated capability blocked-route terminal record drift") unless
    blocked_terminal["record_type"] == "aios_p1_mandatory_capability_contract_route_terminal_record" &&
    blocked_terminal["schema_version"] == "1.0" &&
    valid_utc_timestamp?(blocked_terminal["recorded_at_utc"]) &&
    blocked_terminal["status"] == "PERMANENTLY_STOPPED_AFTER_FOUNDER_EXCEPTION_SECURITY_NON_PASS" &&
    blocked_terminal["task_id"] == blocked_route["task_id"] &&
    blocked_terminal["mandatory_exit_capability"] == blocked_capability &&
    blocked_terminal["attempt_ordinal"] == 1 &&
    blocked_terminal["implementation_started"] == false &&
    blocked_terminal["task_activated"] == false &&
    blocked_terminal["task_branch_created"] == false &&
    blocked_terminal["task_worktree_created"] == false &&
    blocked_terminal["candidate_created"] == false &&
    blocked_terminal["capability_claims"] == 0 &&
    blocked_terminal["route_recovery_allowed"] == false &&
    blocked_terminal["retry_allowed"] == false &&
    blocked_terminal["resume_allowed"] == false &&
    blocked_terminal["successor_allowed"] == false &&
    blocked_terminal["replacement_allowed"] == false &&
    blocked_terminal["correction_chain_allowed"] == false &&
    blocked_terminal["founder_escalation_required"] == true &&
    blocked_terminal["blocking_finding"] == "READ_ALLOWLIST_VS_MANDATORY_VERIFICATION_CONTRADICTION" &&
    blocked_terminal["mutation_oracle_blocker_closed"] == true &&
    blocked_terminal["cto_final_exception_review_result"] == "PASS" &&
    blocked_terminal["security_final_exception_review_result"] == "NON_PASS" &&
    blocked_terminal["quality_final_exception_review_result"] == "CANCELLED_AFTER_SECURITY_NON_PASS" &&
    blocked_terminal["next_required_decision"] == "P1_EXIT_GATE_HIDDEN_SET_CAPABILITY_ARCHITECTURE_DISPOSITION" &&
    blocked_terminal["claim_boundary"] == "CONTRACT_ROUTE_TERMINAL_EVIDENCE_ONLY_NO_IMPLEMENTATION_HIDDEN_SET_BENCHMARK_AGENT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM"
  stop!("integrated capability blocked-route terminal parent drift") unless
    blocked_terminal["canonical_parent_commit"] == blocked_exception["canonical_parent_commit"] &&
    blocked_terminal["canonical_parent_tree"] == blocked_exception["canonical_parent_tree"] &&
    blocked_terminal["canonical_parent_commit"].is_a?(String) && blocked_terminal["canonical_parent_commit"].match?(/\A[0-9a-f]{40}\z/) &&
    blocked_terminal["canonical_parent_tree"].is_a?(String) && blocked_terminal["canonical_parent_tree"].match?(/\A[0-9a-f]{40}\z/) &&
    system("git", "-C", REPO_ROOT, "cat-file", "-e", "#{blocked_terminal['canonical_parent_commit']}^{commit}", out: File::NULL, err: File::NULL) &&
    git("rev-parse", "#{blocked_terminal['canonical_parent_commit']}^{tree}") == blocked_terminal["canonical_parent_tree"]
  stop!("integrated capability blocked-route terminal lineage drift") unless
    blocked_terminal["original_task_contract_sha256"] == blocked_failure["original_task_contract_sha256"] &&
    blocked_terminal["original_task_contract_sha256"] == blocked_exception["original_task_contract_sha256"] &&
    blocked_terminal["rejected_corrected_contract_sha256"] == blocked_failure["task_contract_sha256"] &&
    blocked_terminal["rejected_corrected_contract_sha256"] == blocked_ledger["contract_sha256"] &&
    blocked_terminal["rejected_corrected_contract_sha256"] == blocked_exception["rejected_corrected_contract_sha256"] &&
    blocked_terminal["prior_cto_final_review_sha256"] == blocked_failure["final_review_sha256"] &&
    blocked_terminal["prior_cto_final_review_sha256"] == blocked_exception["blocking_cto_final_review_sha256"] &&
    blocked_terminal["prior_contract_review_failure_record_sha256"] == blocked_ledger["failure_record_sha256"] &&
    blocked_terminal["prior_contract_review_failure_record_sha256"] == blocked_exception["contract_review_failure_record_sha256"] &&
    blocked_terminal["founder_exception_record_sha256"] == blocked_ledger["founder_exception_record_sha256"] &&
    blocked_terminal["final_exception_contract_sha256"] == blocked_ledger["founder_exception_final_contract_sha256"] &&
    blocked_terminal["cto_final_exception_review_sha256"] == blocked_ledger["founder_exception_cto_review_sha256"] &&
    blocked_terminal["security_final_exception_review_sha256"] == blocked_ledger["founder_exception_security_review_sha256"]
  architecture_disposition = decision["architecture_disposition"]
  stop!("integrated capability Founder architecture disposition drift") unless architecture_disposition == {
    "kind" => "INTEGRATED_VERTICAL_SLICE_RELOCATION",
    "standalone_hidden_set_task_route" => "TERMINATED",
    "integrated_task_id" => integrated_route["task_id"],
    "mandatory_exit_capabilities" => integrated_route_capabilities,
    "partial_acceptance_allowed" => false,
    "next_capability_after_acceptance" => expected_exit_capabilities[expected_exit_capabilities.index(integrated_route_capabilities.last) + 1]
  }
  stop!("integrated capability Founder read boundary drift") unless decision["required_read_boundary"] == {
    "semantic_task_inputs" => "EXACT_HASH_BOUND_ALLOWLIST_DENY_BY_DEFAULT",
    "trusted_verification_substrate" => "READ_ONLY_EXACT_PARENT_TRACKED_TREE_AND_FROZEN_LOCAL_RUNTIME_TOOLCHAIN_DEPENDENCY_ROOTS",
    "historical_hidden_material_access" => false,
    "offsite_custody_access" => false,
    "untracked_private_material_access" => false,
    "writable_paths" => "EXACT_ALLOWLIST"
  }
  stop!("integrated capability Founder role-separation drift") unless decision["required_role_separation"] == {
    "quality_owns" => %w[public_synthetic_protocol_fixtures schemas oracle evaluator],
    "worker_owns" => %w[parameterized_harness minimal_hidden_admission_adapter],
    "worker_may_finally_review_own_work" => false
  }
  stop!("integrated capability Founder claim boundary drift") unless decision["claim_boundary"] == integrated_route["claim_boundary"]
  stop!("integrated capability Founder forbidden set drift") unless decision["forbidden"] == %w[
    real_or_historical_hidden_material_create_read_enumerate_restore_or_reuse
    network_provider_secret_remote_production_or_public_effect
    supervisor_root_custody_strong_isolation_or_p3_trust_runtime
    B0_B1_B2_or_A0_execution
    P2_or_P3_entry
    partial_capability_acceptance
    P1_036_retry_resume_successor_replacement_or_correction_chain
  ]
  stop!("integrated capability Founder delegation drift") unless decision["delegation"] == {
    "routine_task_founder_approval_required" => false,
    "master_may_prepare_review_execute_gate_integrate_and_continue" => true,
    "next_normal_founder_intervention" => "P1_PHASE_GATE_OR_REAL_FOUNDER_RESERVED_DECISION"
  }
  stop!("integrated capability Founder terminal rule drift") unless decision["terminal_rule"] == {
    "maximum_same_task_bounded_contract_corrections" => 1,
    "final_contract_non_pass_or_real_architecture_failure" => "PERMANENTLY_STOP_INTEGRATED_ROUTE_AND_ESCALATE_FOUNDER",
    "successor_replacement_or_correction_chain_allowed" => false
  }
  end
end

final_clean_room_route = mandatory_recovery["final_clean_room_implementation_route"]
final_clean_room_attempt = mandatory_recovery["final_clean_room_implementation_attempt"]
final_clean_room_terminal = mandatory_recovery["final_clean_room_contract_review_terminal"]
final_clean_room_route_id = nil
final_clean_room_capabilities = []
if final_clean_room_route
  expected_final_route_keys = %w[
    record_type authority status decision_record_path decision_record_sha256
    canonical_parent_commit canonical_parent_tree task_id route_id mandatory_exit_capabilities
    prior_terminal_routes atomic_all_or_none final_exact_contract_count activation_limit
    branch_limit worktree_limit candidate_limit retry_limit reusable old_asset_reuse_allowed
    successor_replacement_correction_chain_allowed claim_boundary
  ]
  stop!("final clean-room route schema drift") unless final_clean_room_route.is_a?(Hash) && final_clean_room_route.keys.sort == expected_final_route_keys.sort
  stop!("final clean-room route authority drift") unless
    final_clean_room_route["record_type"] == "p1_founder_approved_final_clean_room_implementation_route" &&
    final_clean_room_route["authority"] == "HUMAN_FOUNDER" &&
    final_clean_room_route["status"] == "FOUNDER_APPROVED_ONE_TIME"
  final_clean_room_route_id = final_clean_room_route["route_id"]
  final_clean_room_capabilities = final_clean_room_route["mandatory_exit_capabilities"]
  stop!("final clean-room route identity invalid") unless
    final_clean_room_route_id == "P1_038_FINAL_CLEAN_ROOM_IMPLEMENTATION_ROUTE" &&
    final_clean_room_route["task_id"] == "AIOS-P1-038_MINIMAL_HIDDEN_ADMISSION_PARAMETERIZED_HARNESS_IMPLEMENTATION"
  stop!("final clean-room route capability population drift") unless integrated_route && final_clean_room_capabilities == integrated_route_capabilities
  stop!("final clean-room route safety invariant drift") unless
    final_clean_room_route["atomic_all_or_none"] == true &&
    final_clean_room_route["final_exact_contract_count"] == 1 &&
    final_clean_room_route["activation_limit"] == 1 &&
    final_clean_room_route["branch_limit"] == 1 &&
    final_clean_room_route["worktree_limit"] == 1 &&
    final_clean_room_route["candidate_limit"] == 1 &&
    final_clean_room_route["retry_limit"] == 0 &&
    final_clean_room_route["reusable"] == false &&
    final_clean_room_route["old_asset_reuse_allowed"] == false &&
    final_clean_room_route["successor_replacement_correction_chain_allowed"] == false
  stop!("final clean-room route parent identity invalid") unless
    final_clean_room_route["canonical_parent_commit"].is_a?(String) && final_clean_room_route["canonical_parent_commit"].match?(/\A[0-9a-f]{40}\z/) &&
    final_clean_room_route["canonical_parent_tree"].is_a?(String) && final_clean_room_route["canonical_parent_tree"].match?(/\A[0-9a-f]{40}\z/)
  stop!("final clean-room route parent object missing") unless system("git", "-C", REPO_ROOT, "cat-file", "-e", "#{final_clean_room_route['canonical_parent_commit']}^{commit}", out: File::NULL, err: File::NULL)
  stop!("final clean-room route parent tree drift") unless git("rev-parse", "#{final_clean_room_route['canonical_parent_commit']}^{tree}") == final_clean_room_route["canonical_parent_tree"]
  stop!("final clean-room route prior terminal routes drift") unless final_clean_room_route["prior_terminal_routes"] == {
    "AIOS-P1-036_HIDDEN_SET_PROTOCOL" => "PERMANENTLY_STOPPED_AFTER_SECURITY_NON_PASS",
    "AIOS-P1-037_PARAMETERIZED_EVALUATION_HARNESS_WITH_HIDDEN_ADMISSION" => "PERMANENTLY_STOPPED_AFTER_FINAL_SECURITY_NON_PASS"
  }

  if HISTORICAL_SEMANTIC_PROJECTION_ALLOWED
  decision = bound_historical_governance_json!(historical_metadata_boundary, final_clean_room_route["decision_record_path"], final_clean_room_route["decision_record_sha256"], "FOUNDER_DECISION", recovery_evidence_base, "final clean-room Founder attempt-accounting decision")
  expected_decision_keys = %w[
    record_type schema_version status authority approved_at_utc canonical_parent_commit
    canonical_parent_tree goal_canonical_sha256 accepted_terminal_evidence historical_routes
    attempt_accounting final_clean_room_route contract_freeze_sequence contract_rules
    minimum_engineering_scope forbidden terminal_rule delegation
    next_capability_after_atomic_acceptance claim_boundary
  ]
  stop!("final clean-room Founder decision schema drift") unless decision.keys.sort == expected_decision_keys.sort
  stop!("final clean-room Founder decision header drift") unless
    decision["record_type"] == "sourcelens_aios_founder_exit_capability_attempt_accounting_recalibration" &&
    decision["schema_version"] == "1.0" && decision["status"] == "APPROVED" &&
    decision["authority"] == "HUMAN_FOUNDER" && valid_utc_timestamp?(decision["approved_at_utc"])
  stop!("final clean-room Founder decision parent drift") unless
    decision["canonical_parent_commit"] == final_clean_room_route["canonical_parent_commit"] &&
    decision["canonical_parent_tree"] == final_clean_room_route["canonical_parent_tree"]
  stop!("final clean-room Founder decision Goal drift") unless decision["goal_canonical_sha256"] == truth.dig("goal", "observed_body_sha256")
  accepted_terminal = decision["accepted_terminal_evidence"]
  stop!("final clean-room Founder accepted terminal Evidence schema drift") unless accepted_terminal.is_a?(Hash) && accepted_terminal.keys.sort == %w[
    p1_037_contract_review_failure_record_path p1_037_contract_review_failure_record_sha256
    p1_037_terminal_record_path p1_037_terminal_record_sha256
  ].sort
  terminal_record = bound_historical_governance_json!(historical_metadata_boundary, accepted_terminal["p1_037_terminal_record_path"], accepted_terminal["p1_037_terminal_record_sha256"], "TERMINAL_RECORD", recovery_evidence_base, "P1-037 terminal record accepted by Founder")
  failure_record = bound_historical_governance_json!(historical_metadata_boundary, accepted_terminal["p1_037_contract_review_failure_record_path"], accepted_terminal["p1_037_contract_review_failure_record_sha256"], "CONTRACT_REVIEW_FAILURE", recovery_evidence_base, "P1-037 contract failure accepted by Founder")
  stop!("final clean-room Founder accepted terminal Evidence drift") unless
    terminal_record["status"] == "PERMANENTLY_STOPPED_AFTER_FINAL_SECURITY_NON_PASS" &&
    terminal_record["route_recovery_allowed"] == false &&
    terminal_record["contract_review_failure_record_sha256"] == accepted_terminal["p1_037_contract_review_failure_record_sha256"] &&
    failure_record["status"] == "CONTRACT_REVIEW_BLOCKED" &&
    failure_record["implementation_started"] == false && failure_record["task_activated"] == false &&
    failure_record["task_branch_created"] == false && failure_record["task_worktree_created"] == false &&
    failure_record["candidate_created"] == false
  stop!("final clean-room Founder historical route preservation drift") unless decision["historical_routes"] == {
    "AIOS-P1-036_HIDDEN_SET_PROTOCOL" => {
      "status" => "PERMANENTLY_STOPPED_AFTER_SECURITY_NON_PASS",
      "immutable" => true, "recovery_allowed" => false, "asset_reuse_allowed" => false
    },
    "AIOS-P1-037_PARAMETERIZED_EVALUATION_HARNESS_WITH_HIDDEN_ADMISSION" => {
      "status" => "PERMANENTLY_STOPPED_AFTER_FINAL_SECURITY_NON_PASS",
      "immutable" => true, "recovery_allowed" => false, "asset_reuse_allowed" => false
    }
  }
  stop!("final clean-room Founder attempt-accounting drift") unless decision["attempt_accounting"] == {
    "contract_preparation_failure_is_activated_implementation_attempt" => false,
    "activated_implementation_attempt_starts_at_governance_activation_commit" => true,
    "historical_contract_failures_remain_terminal" => true,
    "maximum_new_clean_room_implementation_routes" => 1,
    "implementation_retry_limit" => 0
  }
  stop!("final clean-room Founder route binding drift") unless decision["final_clean_room_route"] == {
    "task_id" => final_clean_room_route["task_id"],
    "mandatory_exit_capabilities" => final_clean_room_capabilities,
    "atomic_acceptance_required" => true,
    "partial_acceptance_allowed" => false,
    "branch_limit" => 1,
    "worktree_limit" => 1,
    "candidate_limit" => 1,
    "retry_limit" => 0,
    "old_asset_reuse_allowed" => false
  }
  stop!("final clean-room Founder contract freeze sequence drift") unless decision["contract_freeze_sequence"] == %w[
    MINIMAL_DRAFT
    CTO_SECURITY_QUALITY_PRE_FREEZE_COLLABORATIVE_CONTRADICTION_REMOVAL
    ONE_FINAL_EXACT_CONTRACT_FREEZE
    CTO_SECURITY_QUALITY_FINAL_INDEPENDENT_REVIEW
    ACTIVATE_ONLY_AFTER_ALL_EXACT_PASS
  ]
  stop!("final clean-room Founder contract rule drift") unless decision["contract_rules"] == {
    "pre_freeze_frozen_version_chain_allowed" => false,
    "successor_replacement_or_correction_chain_allowed" => false,
    "final_exact_contract_count" => 1,
    "final_contract_non_pass_action" => "PERMANENTLY_STOP_ROUTE_AND_ESCALATE_FOUNDER"
  }
  stop!("final clean-room Founder terminal rule drift") unless decision["terminal_rule"] == {
    "final_contract_any_non_pass" => "PERMANENTLY_STOP_ROUTE_AND_ESCALATE_FOUNDER",
    "real_architecture_implementation_failure" => "PERMANENTLY_STOP_ROUTE_AND_ESCALATE_FOUNDER",
    "post_failure_founder_choices" => %w[FORMALLY_REVISE_P1_EXIT_GATE STOP_P1]
  }
  stop!("final clean-room Founder delegation drift") unless decision["delegation"] == {
    "model" => "P1_PHASE_LEVEL_FOUNDER_DELEGATION",
    "master_may_sync_prepare_freeze_review_activate_implement_gate_integrate_cleanup_and_continue" => true,
    "routine_task_founder_approval_required" => false,
    "next_normal_founder_intervention" => "P1_PHASE_GATE_OR_REAL_FOUNDER_RESERVED_DECISION"
  }
  stop!("final clean-room Founder next capability drift") unless decision["next_capability_after_atomic_acceptance"] == "VTSR_COUNTING_VALIDATOR"
  stop!("final clean-room Founder claim boundary drift") unless decision["claim_boundary"] == "FOUNDER_ARCHITECTURE_AND_ATTEMPT_ACCOUNTING_DECISION_ONLY_NO_IMPLEMENTATION_HIDDEN_SET_PARAMETERIZED_HARNESS_BENCHMARK_AGENT_P1_EXIT_P2_P3_PRODUCTION_OR_HOSTILE_PRINCIPAL_CLAIM"
  end
  stop!("final clean-room route claim boundary drift") unless final_clean_room_route["claim_boundary"] == "COOPERATIVE_LOCAL_PUBLIC_SYNTHETIC_ROLE_SEPARATED_HIDDEN_ADMISSION_AND_PARAMETERIZED_HARNESS_REPRODUCIBLE_INTEGRATION_ONLY_NO_REAL_HIDDEN_SET_SECRECY_REPRESENTATIVENESS_CUSTODY_HOSTILE_PRINCIPAL_AGENT_P1_EXIT_P2_P3_OR_PRODUCTION_CLAIM"
end

if final_clean_room_terminal
  expected_terminal_keys = %w[
    record_type status task_id route_id mandatory_exit_capabilities final_contract_path
    final_contract_sha256 final_contract_byte_length final_contract_freeze_commit
    final_contract_freeze_tree cto_review_path cto_review_sha256 cto_review_result
    security_review_path security_review_sha256 security_review_result quality_review_result
    failure_record_path failure_record_sha256 terminal_record_path terminal_record_sha256
    implementation_attempt_consumed route_recovery_allowed fourth_route_allowed
    successor_replacement_or_correction_allowed founder_escalation_required
    allowed_founder_choices
  ]
  stop!("final clean-room contract-review terminal schema drift") unless
    final_clean_room_terminal.is_a?(Hash) && final_clean_room_terminal.keys.sort == expected_terminal_keys.sort
  stop!("final clean-room contract-review terminal route binding drift") unless
    final_clean_room_route &&
    final_clean_room_terminal["record_type"] == "p1_final_clean_room_contract_review_terminal_binding" &&
    final_clean_room_terminal["status"] == "PERMANENTLY_STOPPED_AFTER_FINAL_CONTRACT_CTO_NON_PASS" &&
    final_clean_room_terminal["task_id"] == final_clean_room_route["task_id"] &&
    final_clean_room_terminal["route_id"] == final_clean_room_route_id &&
    final_clean_room_terminal["mandatory_exit_capabilities"] == final_clean_room_capabilities
  stop!("final clean-room terminal safety rule drift") unless
    final_clean_room_terminal["implementation_attempt_consumed"] == false &&
    final_clean_room_terminal["route_recovery_allowed"] == false &&
    final_clean_room_terminal["fourth_route_allowed"] == false &&
    final_clean_room_terminal["successor_replacement_or_correction_allowed"] == false &&
    final_clean_room_terminal["founder_escalation_required"] == true &&
    final_clean_room_terminal["allowed_founder_choices"] == %w[FORMALLY_REVISE_P1_EXIT_GATE STOP_P1] &&
    final_clean_room_attempt.nil?
  terminal_projection = final_clean_room_capabilities.map { |capability| capability_status[capability] }
  stop!("final clean-room terminal capability projection drift") unless
    terminal_projection == ["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"] ||
    (mandatory_recovery["post_revision_final_implementation_route"] &&
      (
        terminal_projection == ["FOUNDER_REVISED_PENDING_IMPLEMENTATION", "FOUNDER_REVISED_PENDING_IMPLEMENTATION"] ||
        (rebaseline && terminal_projection.all? { |state| %w[REBASELINED_PENDING_EXECUTION IN_PROGRESS ACCEPTED].include?(state) }) ||
        terminal_projection == ["IN_PROGRESS", "IN_PROGRESS"] ||
        terminal_projection == ["ACCEPTED", "ACCEPTED"] ||
        (mandatory_recovery["post_revision_final_route_terminal"] && terminal_projection == ["ARCHITECTURE_BLOCKED", "ARCHITECTURE_BLOCKED"])
      ))

  stop!("final clean-room terminal Contract identity drift") unless
    final_clean_room_terminal["final_contract_path"] == "docs/aios/tasks/P1-038_MINIMAL_HIDDEN_ADMISSION_PARAMETERIZED_HARNESS_IMPLEMENTATION.yaml" &&
    final_clean_room_terminal["final_contract_sha256"] == "cde6a6adff74ce1a6a7f07ebfe74ae6ba1fbeb96ae20c17cfbcd24e08e2bf354" &&
    final_clean_room_terminal["final_contract_byte_length"] == 31_905 &&
    final_clean_room_terminal["final_contract_freeze_commit"] == "8e2cbb21f03d2f36b269f9eae5af9aff735d2f7e" &&
    final_clean_room_terminal["final_contract_freeze_tree"] == "c2601c3d50c72fe86ad04a32782ce8663098f5f3"

  founder_accepted_p1_038_terminal = boundary_decision["accepted_p1_038_terminal_evidence"]
  stop!("P1-038 terminal current-Founder hash binding drift") unless founder_accepted_p1_038_terminal == {
    "terminal_record_path" => final_clean_room_terminal["terminal_record_path"],
    "terminal_record_sha256" => final_clean_room_terminal["terminal_record_sha256"],
    "contract_review_failure_record_path" => final_clean_room_terminal["failure_record_path"],
    "contract_review_failure_record_sha256" => final_clean_room_terminal["failure_record_sha256"]
  }

  if HISTORICAL_SEMANTIC_PROJECTION_ALLOWED
  cto_review = bound_historical_governance_json!(historical_metadata_boundary, final_clean_room_terminal["cto_review_path"], final_clean_room_terminal["cto_review_sha256"], "INDEPENDENT_CONTRACT_REVIEW", recovery_evidence_base, "P1-038 CTO final Contract review")
  security_review = bound_historical_governance_json!(historical_metadata_boundary, final_clean_room_terminal["security_review_path"], final_clean_room_terminal["security_review_sha256"], "INDEPENDENT_CONTRACT_REVIEW", recovery_evidence_base, "P1-038 Security final Contract review")
  stop!("final clean-room CTO review terminal binding drift") unless
    final_clean_room_terminal["cto_review_result"] == "NON_PASS" &&
    cto_review["record_type"] == "aios_independent_final_contract_review" &&
    cto_review["role"] == "CTO" && cto_review["verdict"] == "NON_PASS" &&
    cto_review["task_id"] == final_clean_room_terminal["task_id"] &&
    cto_review["task_contract_sha256"] == final_clean_room_terminal["final_contract_sha256"] &&
    cto_review.dig("findings", 0, "finding_id") == "CTO-P1-038-FINAL-CONTRACT-001" &&
    cto_review.dig("findings", 0, "severity") == "BLOCKER"
  stop!("final clean-room Security review terminal binding drift") unless
    final_clean_room_terminal["security_review_result"] == "PASS" &&
    security_review["record_type"] == "aios_p1_038_security_final_contract_review" &&
    security_review["verdict"] == "PASS" &&
    security_review.dig("contract", "sha256") == final_clean_room_terminal["final_contract_sha256"] &&
    security_review["no_failed_asset_read"] == true &&
    security_review["external_effects_observed"] == 0
  stop!("final clean-room Quality review cancellation drift") unless
    final_clean_room_terminal["quality_review_result"] == "CANCELLED_AFTER_CTO_NON_PASS"

  failure = bound_historical_governance_json!(historical_metadata_boundary, final_clean_room_terminal["failure_record_path"], final_clean_room_terminal["failure_record_sha256"], "CONTRACT_REVIEW_FAILURE", recovery_evidence_base, "P1-038 final Contract review failure record")
  terminal = bound_historical_governance_json!(historical_metadata_boundary, final_clean_room_terminal["terminal_record_path"], final_clean_room_terminal["terminal_record_sha256"], "TERMINAL_RECORD", recovery_evidence_base, "P1-038 final route terminal record")
  stop!("final clean-room Contract failure record content drift") unless
    failure["record_type"] == "aios_p1_final_clean_room_contract_review_failure" &&
    failure["status"] == "FINAL_EXACT_CONTRACT_NON_PASS" &&
    failure["task_id"] == final_clean_room_terminal["task_id"] &&
    failure["route_id"] == final_clean_room_route_id &&
    failure["mandatory_exit_capabilities"] == final_clean_room_capabilities &&
    failure.dig("final_contract", "sha256") == final_clean_room_terminal["final_contract_sha256"] &&
    failure.dig("independent_final_reviews", "cto", "sha256") == final_clean_room_terminal["cto_review_sha256"] &&
    failure.dig("independent_final_reviews", "cto", "verdict") == "NON_PASS" &&
    failure.dig("independent_final_reviews", "security", "sha256") == final_clean_room_terminal["security_review_sha256"] &&
    failure.dig("independent_final_reviews", "security", "verdict") == "PASS" &&
    failure.dig("independent_final_reviews", "quality", "verdict") == "CANCELLED_AFTER_CTO_NON_PASS" &&
    failure.dig("activation_and_implementation", "task_activated") == false &&
    failure.dig("activation_and_implementation", "implementation_attempt_consumed") == false &&
    failure.dig("terminal_effect", "route_permanently_stopped") == true &&
    failure.dig("terminal_effect", "fourth_route_allowed") == false &&
    failure.dig("terminal_effect", "founder_escalation_required") == true
  stop!("final clean-room route terminal record content drift") unless
    terminal["record_type"] == "aios_p1_final_clean_room_route_terminal_record" &&
    terminal["status"] == final_clean_room_terminal["status"] &&
    terminal["task_id"] == final_clean_room_terminal["task_id"] &&
    terminal["route_id"] == final_clean_room_route_id &&
    terminal["mandatory_exit_capabilities"] == final_clean_room_capabilities &&
    terminal["contract_review_failure_record_sha256"] == final_clean_room_terminal["failure_record_sha256"] &&
    terminal.dig("review_outcomes", "cto") == "NON_PASS" &&
    terminal.dig("review_outcomes", "security") == "PASS" &&
    terminal.dig("review_outcomes", "quality") == "CANCELLED_AFTER_CTO_NON_PASS" &&
    terminal.dig("review_outcomes", "aggregate") == "NON_PASS" &&
    terminal.dig("activation_and_implementation", "implementation_attempt_consumed") == false &&
    terminal.dig("terminal_rules", "route_recovery_allowed") == false &&
    terminal.dig("terminal_rules", "fourth_route_allowed") == false &&
    terminal.dig("terminal_rules", "allowed_founder_choices") == final_clean_room_terminal["allowed_founder_choices"] &&
    terminal["current_capability_projection"] == final_clean_room_capabilities.to_h { |capability| [capability, "CONTRACT_REVIEW_BLOCKED"] }
  end
elsif final_clean_room_route && final_clean_room_attempt.nil? &&
      final_clean_room_capabilities.all? { |capability| capability_status[capability] == "CONTRACT_REVIEW_BLOCKED" }
  stop!("final clean-room contract-review terminal binding missing")
end

post_revision_route = mandatory_recovery["post_revision_final_implementation_route"]
post_revision_attempt = mandatory_recovery["post_revision_final_implementation_attempt"]
post_revision_terminal = mandatory_recovery["post_revision_final_route_terminal"]
post_revision_route_id = nil
post_revision_capabilities = []
if post_revision_route
  expected_post_revision_route_keys = %w[
    record_type authority status decision_record_path decision_record_sha256
    canonical_parent_commit canonical_parent_tree task_id route_id mandatory_exit_capabilities
    prior_terminal_route historical_governance_metadata_classification atomic_all_or_none
    final_exact_contract_count activation_limit branch_limit worktree_limit candidate_limit
    retry_limit reusable old_asset_reuse_allowed successor_replacement_correction_chain_allowed
    final_non_pass_or_real_architecture_failure claim_boundary
  ]
  stop!("post-revision final route schema drift") unless post_revision_route.is_a?(Hash) && post_revision_route.keys.sort == expected_post_revision_route_keys.sort
  stop!("post-revision final route authority drift") unless
    post_revision_route["record_type"] == "p1_founder_approved_post_revision_final_implementation_route" &&
    post_revision_route["authority"] == "HUMAN_FOUNDER" &&
    post_revision_route["status"] == "FOUNDER_APPROVED_ONE_TIME"
  post_revision_route_id = post_revision_route["route_id"]
  post_revision_capabilities = post_revision_route["mandatory_exit_capabilities"]
  stop!("post-revision final route identity drift") unless
    post_revision_route_id == "P1_039_POST_REVISION_FINAL_IMPLEMENTATION_ROUTE" &&
    post_revision_route["task_id"] == "AIOS-P1-039_MINIMAL_HIDDEN_ADMISSION_PARAMETERIZED_HARNESS_IMPLEMENTATION" &&
    post_revision_capabilities == %w[HIDDEN_SET_PROTOCOL PARAMETERIZED_EVALUATION_HARNESS]
  stop!("post-revision final route parent drift") unless
    post_revision_route["canonical_parent_commit"] == boundary_decision["canonical_parent_commit"] &&
    post_revision_route["canonical_parent_tree"] == boundary_decision["canonical_parent_tree"] &&
    git("rev-parse", "#{post_revision_route['canonical_parent_commit']}^{tree}") == post_revision_route["canonical_parent_tree"]
  stop!("post-revision final route Founder binding drift") unless
    post_revision_route["decision_record_path"] == boundary_decision_path &&
    post_revision_route["decision_record_sha256"] == boundary_decision_sha
  stop!("final clean-room contract-review terminal binding missing") unless final_clean_room_terminal.is_a?(Hash)
  stop!("post-revision final route historical terminal binding drift") unless post_revision_route["prior_terminal_route"] == {
    "task_id" => final_clean_room_terminal["task_id"],
    "status" => final_clean_room_terminal["status"],
    "terminal_record_sha256" => final_clean_room_terminal["terminal_record_sha256"],
    "contract_review_failure_record_sha256" => final_clean_room_terminal["failure_record_sha256"],
    "recovery_allowed" => false,
    "engineering_asset_reuse_allowed" => false
  }
  stop!("post-revision final route metadata classification drift") unless post_revision_route["historical_governance_metadata_classification"] == "TRUSTED_VERIFICATION_SUBSTRATE_NOT_SEMANTIC_TASK_INPUT"
  stop!("post-revision final route safety invariant drift") unless
    post_revision_route["atomic_all_or_none"] == true &&
    post_revision_route["final_exact_contract_count"] == 1 &&
    post_revision_route["activation_limit"] == 1 &&
    post_revision_route["branch_limit"] == 1 &&
    post_revision_route["worktree_limit"] == 1 &&
    post_revision_route["candidate_limit"] == 1 &&
    post_revision_route["retry_limit"] == 0 &&
    post_revision_route["reusable"] == false &&
    post_revision_route["old_asset_reuse_allowed"] == false &&
    post_revision_route["successor_replacement_correction_chain_allowed"] == false &&
    post_revision_route["final_non_pass_or_real_architecture_failure"] == "STOP_P1_NO_FIFTH_ROUTE"
  decision_route = boundary_decision["post_revision_final_implementation_route"]
  stop!("post-revision final route Founder decision scope drift") unless
    decision_route.is_a?(Hash) &&
    decision_route["task_id"] == post_revision_route["task_id"] &&
    decision_route["route_id"] == post_revision_route_id &&
    decision_route["task_limit"] == 1 &&
    decision_route["final_exact_contract_limit"] == 1 &&
    decision_route["branch_limit"] == 1 &&
    decision_route["worktree_limit"] == 1 &&
    decision_route["candidate_limit"] == 1 &&
    decision_route["retry_limit"] == 0 &&
    decision_route["reusable"] == false &&
    decision_route["p1_038_contract_copy_or_patch_allowed"] == false &&
    decision_route["failed_engineering_asset_reuse_allowed"] == false &&
    decision_route["successor_replacement_correction_or_governance_chain_allowed"] == false &&
    decision_route["activate_only_after_cto_security_quality_exact_pass"] == true
  stop!("post-revision mandatory capability rule drift") unless boundary_decision["mandatory_exit_capability_rule"] == {
    "capabilities" => post_revision_capabilities,
    "atomic_acceptance_required" => true,
    "partial_acceptance_allowed" => false,
    "deferral_as_completion_allowed" => false,
    "claim_boundary_reduction_allowed" => false,
    "runnable_engineering_output_required" => true
  }
  stop!("post-revision delegation drift") unless
    boundary_decision.dig("delegation", "model") == "P1_PHASE_LEVEL_FOUNDER_DELEGATION" &&
    boundary_decision.dig("delegation", "master_may_sync_prepare_review_activate_implement_gate_integrate_cleanup_and_continue") == true &&
    boundary_decision.dig("delegation", "routine_task_founder_approval_required") == false &&
    boundary_decision.dig("delegation", "founder_next_normal_intervention") == "P1_PHASE_GATE"
  stop!("post-revision terminal rule drift") unless boundary_decision["terminal_rule"] == {
    "final_contract_any_non_pass" => "STOP_P1_NO_FIFTH_ROUTE",
    "real_architecture_implementation_failure" => "STOP_P1_NO_FIFTH_ROUTE",
    "successor_replacement_correction_or_new_contract_loop_allowed" => false,
    "project_level_disposition_required_after_p1_stop" => true
  }
  stop!("post-revision next capability drift") unless boundary_decision["next_capability_after_atomic_acceptance"] == "VTSR_COUNTING_VALIDATOR"
  stop!("post-revision route claim boundary drift") unless post_revision_route["claim_boundary"] == "COOPERATIVE_LOCAL_PUBLIC_SYNTHETIC_ROLE_SEPARATED_HIDDEN_ADMISSION_AND_PARAMETERIZED_HARNESS_REPRODUCIBLE_INTEGRATION_ONLY_NO_REAL_HIDDEN_SET_SECRECY_REPRESENTATIVENESS_HOSTILE_PRINCIPAL_AGENT_P1_EXIT_P2_P3_OR_PRODUCTION_CLAIM"
  stop!("post-revision route implementation attempt was reused") unless post_revision_attempt.nil? || post_revision_attempt.is_a?(Hash)
end

if post_revision_terminal
  expected_post_revision_terminal_keys = %w[
    record_type status task_id route_id mandatory_exit_capabilities failure_stage
    terminal_record_path terminal_record_sha256 implementation_attempt_consumed
    route_recovery_allowed fifth_route_allowed successor_replacement_correction_allowed
    founder_escalation_required project_level_disposition_required
  ]
  stop!("post-revision final route terminal schema drift") unless
    post_revision_terminal.is_a?(Hash) && post_revision_terminal.keys.sort == expected_post_revision_terminal_keys.sort
  stop!("post-revision final route terminal identity drift") unless
    post_revision_route &&
    post_revision_terminal["record_type"] == "p1_post_revision_final_route_terminal_binding" &&
    post_revision_terminal["status"] == "P1_TERMINAL_STOPPED" &&
    post_revision_terminal["task_id"] == post_revision_route["task_id"] &&
    post_revision_terminal["route_id"] == post_revision_route_id &&
    post_revision_terminal["mandatory_exit_capabilities"] == post_revision_capabilities &&
    %w[FINAL_CONTRACT_REVIEW_NON_PASS REAL_ARCHITECTURE_IMPLEMENTATION_FAILURE].include?(post_revision_terminal["failure_stage"])
  expected_attempt_consumed = post_revision_terminal["failure_stage"] == "REAL_ARCHITECTURE_IMPLEMENTATION_FAILURE"
  stop!("post-revision final route terminal safety invariant drift") unless
    post_revision_terminal["implementation_attempt_consumed"] == expected_attempt_consumed &&
    post_revision_terminal["route_recovery_allowed"] == false &&
    post_revision_terminal["fifth_route_allowed"] == false &&
    post_revision_terminal["successor_replacement_correction_allowed"] == false &&
    post_revision_terminal["founder_escalation_required"] == true &&
    post_revision_terminal["project_level_disposition_required"] == true
  current_post_revision_projection = post_revision_capabilities.map { |capability| capability_status[capability] }
  if rebaseline
    stop!("post-revision historical terminal capability projection escaped the approved rebaseline") unless
      current_post_revision_projection.all? { |state| %w[REBASELINED_PENDING_EXECUTION IN_PROGRESS ACCEPTED].include?(state) }
  else
    stop!("post-revision final route terminal capability projection is not atomic") unless
      current_post_revision_projection == ["ARCHITECTURE_BLOCKED", "ARCHITECTURE_BLOCKED"]
  end
  terminal_record = bound_json!(
    post_revision_terminal["terminal_record_path"],
    post_revision_terminal["terminal_record_sha256"],
    recovery_evidence_base,
    "post-revision final route terminal record"
  )
  stop!("post-revision final route terminal record content drift") unless terminal_record == {
    "record_type" => "sourcelens_aios_p1_post_revision_final_route_terminal_record",
    "schema_version" => "1.0",
    "status" => "P1_TERMINAL_STOPPED",
    "task_id" => post_revision_route["task_id"],
    "route_id" => post_revision_route_id,
    "mandatory_exit_capabilities" => post_revision_capabilities,
    "failure_stage" => post_revision_terminal["failure_stage"],
    "implementation_attempt_consumed" => expected_attempt_consumed,
    "route_recovery_allowed" => false,
    "fifth_route_allowed" => false,
    "successor_replacement_correction_allowed" => false,
    "founder_escalation_required" => true,
    "project_level_disposition_required" => true,
    "terminal_action" => "STOP_P1_NO_FIFTH_ROUTE"
  }
end

effective_final_route = post_revision_route || final_clean_room_route
effective_final_attempt = post_revision_route ? post_revision_attempt : final_clean_room_attempt
effective_final_route_id = post_revision_route ? post_revision_route_id : final_clean_room_route_id
effective_final_capabilities = post_revision_route ? post_revision_capabilities : final_clean_room_capabilities
effective_final_pending_state = post_revision_route ? "FOUNDER_REVISED_PENDING_IMPLEMENTATION" : "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"

if integrated_route
  current_route_states = integrated_route_capabilities.map { |capability| capability_status[capability] }
  allowed_route_populations = [
    ["CONTRACT_REVIEW_BLOCKED", "MISSING"],
    ["RELOCATED_PENDING_INTEGRATED_TASK", "MISSING"],
    ["FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION", "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"],
    ["FOUNDER_REVISED_PENDING_IMPLEMENTATION", "FOUNDER_REVISED_PENDING_IMPLEMENTATION"],
    ["REBASELINED_PENDING_EXECUTION", "REBASELINED_PENDING_EXECUTION"],
    ["IN_PROGRESS", "IN_PROGRESS"],
    ["ACCEPTED", "ACCEPTED"],
    ["ARCHITECTURE_BLOCKED", "ARCHITECTURE_BLOCKED"],
    ["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"]
  ]
  if rebaseline
    stop!("historical integrated route capability projection invalid under rebaseline") unless
      current_route_states.all? { |state| allowed_capability_states.include?(state) }
  else
    stop!("integrated capability route current state population is not atomic") unless allowed_route_populations.include?(current_route_states)
  end

  integrated_history_entries = history_entries_for_recovery.select do |entry|
    entry["founder_architecture_route_id"] == integrated_route_id ||
      entry["task_id"] == integrated_route["task_id"]
  end
  active_route_instance = truth.dig("active_work", "current_task") == integrated_route["task_id"] ? 1 : 0
  stop!("integrated capability route was reused") if integrated_history_entries.length + active_route_instance > 1
end

history_entries_for_recovery.each do |entry|
  match = entry["task_id"].to_s.match(/\AAIOS-P1-(\d{3})/)
  next unless match && match[1].to_i >= 35
  stop!("post-recovery Task history lacks mandatory capability identity") unless expected_exit_capabilities.include?(entry["mandatory_exit_capability"]) && entry["clean_room_attempt_ordinal"] == 1
  if entry.key?("project_level_rebaseline_slice_ordinal")
    slice = rebaseline["slices"].find { |candidate| candidate["ordinal"] == entry["project_level_rebaseline_slice_ordinal"] }
    stop!("Task history uses an unauthorized project-level rebaseline Slice") unless
      slice && entry["integrated_mandatory_exit_capabilities"] == slice["capability_projection"] &&
      entry["mandatory_exit_capability"] == slice["capability_projection"].first &&
      entry["project_level_rebaseline_decision_sha256"] == rebaseline["decision_record_sha256"]
  elsif entry.key?("founder_final_clean_room_route_id")
    stop!("Task history uses an unauthorized final clean-room route") unless
      effective_final_route && entry["task_id"] == effective_final_route["task_id"] &&
      entry["mandatory_exit_capability"] == effective_final_capabilities.last &&
      entry["integrated_mandatory_exit_capabilities"] == effective_final_capabilities &&
      entry["founder_final_clean_room_route_id"] == effective_final_route_id
  elsif entry.key?("integrated_mandatory_exit_capabilities") || entry.key?("founder_architecture_route_id")
    stop!("Task history uses an unauthorized integrated capability route") unless integrated_route && entry["task_id"] == integrated_route["task_id"] && entry["mandatory_exit_capability"] == integrated_route["primary_capability"] && entry["integrated_mandatory_exit_capabilities"] == integrated_route_capabilities && entry["founder_architecture_route_id"] == integrated_route_id
  end
end

capability_status.each do |capability, state|
  attempts = history_entries_for_recovery.select { |entry| record_capabilities(entry).include?(capability) }
  stop!("mandatory Exit capability has multiple clean-room attempts") if attempts.length > 1
  ledger = attempt_ledger[capability]
  integrated_member = integrated_route && integrated_route_capabilities.include?(capability)
  integrated_primary_ledger = integrated_route ? attempt_ledger[integrated_route["primary_capability"]] : nil
  rebaseline_capability_slice = Array(rebaseline&.dig("slices")).find { |slice| slice["capability_projection"].include?(capability) }
  rebaseline_attempt = rebaseline_capability_slice ? rebaseline["slice_attempts"][rebaseline_capability_slice["ordinal"].to_s] : nil
  case state
  when "MISSING"
    stop!("missing Exit capability already has an execution attempt") unless attempts.empty? && ledger.nil?
  when "RELOCATED_PENDING_INTEGRATED_TASK"
    stop!("relocated Exit capability is not bound to the Founder-approved integrated route") unless integrated_member && capability == integrated_route_capabilities.first && attempts.empty? && ledger.is_a?(Hash) && ledger["status"] == "CONTRACT_REVIEW_BLOCKED"
  when "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"
    stop!("Founder-recalibrated Exit capability is not bound to the final clean-room route") unless
      final_clean_room_capabilities.include?(capability) && attempts.empty? &&
      ledger.is_a?(Hash) && ledger["status"] == "CONTRACT_REVIEW_BLOCKED" &&
      final_clean_room_attempt.nil?
  when "FOUNDER_REVISED_PENDING_IMPLEMENTATION"
    stop!("Founder-revised Exit capability is not bound to the post-revision final route") unless
      post_revision_capabilities.include?(capability) && attempts.empty? &&
      ledger.is_a?(Hash) && ledger["status"] == "CONTRACT_REVIEW_BLOCKED" &&
      post_revision_attempt.nil?
  when "REBASELINED_PENDING_EXECUTION"
    slice = Array(rebaseline&.dig("slices")).find { |candidate| candidate["capability_projection"].include?(capability) }
    stop!("rebaselined Exit capability is not bound to exactly one approved Slice") unless
      slice && Array(rebaseline&.dig("slices")).count { |candidate| candidate["capability_projection"].include?(capability) } == 1
  when "IN_PROGRESS"
    execution_ledger = if rebaseline_attempt.is_a?(Hash)
      rebaseline_attempt
    elsif effective_final_capabilities.include?(capability) && effective_final_attempt.is_a?(Hash)
      effective_final_attempt
    elsif integrated_member
      integrated_primary_ledger
    else
      ledger
    end
    stop!("in-progress Exit capability attempt ledger missing") unless attempts.empty? && execution_ledger.is_a?(Hash) && execution_ledger["status"] == "ACTIVE" && execution_ledger["attempt_ordinal"] == 1
  when "ACCEPTED"
    entry = attempts.first
    entry_capabilities = entry ? record_capabilities(entry) : []
    integrated_acceptance = integrated_member && entry && entry_capabilities == integrated_route_capabilities && entry["task_id"] == integrated_route["task_id"]
    final_clean_room_acceptance = effective_final_capabilities.include?(capability) && entry && entry_capabilities == effective_final_capabilities && entry["task_id"] == effective_final_route["task_id"] && entry["founder_final_clean_room_route_id"] == effective_final_route_id
    rebaseline_acceptance = entry && entry["project_level_rebaseline_slice_ordinal"] == rebaseline_capability_slice&.dig("ordinal") &&
      entry_capabilities == rebaseline_capability_slice&.dig("capability_projection")
    execution_ledger = if rebaseline_acceptance
      rebaseline_attempt
    elsif final_clean_room_acceptance
      effective_final_attempt
    elsif integrated_acceptance
      integrated_primary_ledger
    else
      ledger
    end
    accepted_claim_boundary = if rebaseline_acceptance
      rebaseline_capability_slice["claim_boundary"]
    elsif final_clean_room_acceptance
      effective_final_route["claim_boundary"]
    elsif integrated_acceptance
      integrated_route["claim_boundary"]
    else
      mandatory_capability_claim_boundary
    end
    accepted_statuses = %w[MASTER_TASK_GATE_ACCEPTED_COMPLETE FOUNDER_GATE_ACCEPTED_COMPLETE]
    stop!("accepted Exit capability lacks one Task Gate binding") unless entry && execution_ledger.is_a?(Hash) && execution_ledger["status"] == "ACCEPTED" && execution_ledger["task_id"] == entry["task_id"] && execution_ledger["attempt_ordinal"] == 1 && accepted_statuses.include?(entry["status"]) && entry["task_gate_result"] == "PASS"
    commit = entry["accepted_candidate_commit"]
    tree = entry["accepted_candidate_tree"]
    stop!("accepted Exit capability candidate identity invalid") unless commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/) && tree.is_a?(String) && tree.match?(/\A[0-9a-f]{40}\z/)
    stop!("accepted Exit capability candidate Git object missing") unless system("git", "-C", REPO_ROOT, "cat-file", "-e", "#{commit}^{commit}", out: File::NULL, err: File::NULL)
    stop!("accepted Exit capability candidate tree drift") unless git("rev-parse", "#{commit}^{tree}") == tree
    evidence_root = entry["execution_evidence_root"]
    stop!("accepted Exit capability Evidence root invalid") unless safe_under_root?(evidence_root, recovery_evidence_base, must_exist: true)
    contract_sha = entry["task_contract_sha256"]
    corrections_used = entry["bounded_contract_corrections_used"]
    stop!("accepted Exit capability Task Contract lineage drift") unless contract_sha.is_a?(String) && contract_sha.match?(/\A[0-9a-f]{64}\z/) && execution_ledger["contract_sha256"] == contract_sha && corrections_used.is_a?(Integer) && corrections_used.between?(0, 1) && execution_ledger["bounded_contract_corrections_used"] == corrections_used
    expected_binding = capability_binding_fields(entry_capabilities)
    manifest = bound_json!(entry["evidence_manifest_path"], entry["evidence_manifest_sha256"], evidence_root, "accepted Exit capability Evidence Manifest")
    stop!("accepted Exit capability Evidence Manifest content drift") unless manifest == {
      "record_type" => "aios_p1_mandatory_capability_evidence_manifest",
      "status" => "FROZEN",
      "task_id" => entry["task_id"],
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => commit,
      "candidate_tree" => tree,
      "artifact_index_path" => entry["artifact_index_path"],
      "artifact_index_sha256" => entry["artifact_index_sha256"],
      "replay_result" => "PASS",
      "rebuild_result" => "PASS",
      "rollback_result" => "PASS",
      "claim_boundary" => accepted_claim_boundary
    }.merge(expected_binding)
    stop!("accepted Exit capability claim boundary drift") unless entry["claim_boundary"] == accepted_claim_boundary
    artifact_index = bound_json!(entry["artifact_index_path"], entry["artifact_index_sha256"], evidence_root, "accepted Exit capability artifact index")
    validate_artifact_index!(artifact_index, evidence_root, entry["task_id"], entry_capabilities, commit, tree)
    %w[cto security quality].each do |role|
      review = bound_json!(entry["#{role}_review_path"], entry["#{role}_review_sha256"], evidence_root, "accepted Exit capability #{role} review")
      stop!("accepted Exit capability #{role} review content drift") unless review == {
        "record_type" => "aios_independent_task_review",
        "status" => "PASS",
        "role" => role.upcase,
        "task_id" => entry["task_id"],
        "task_contract_sha256" => contract_sha,
        "candidate_commit" => commit,
        "candidate_tree" => tree,
        "evidence_manifest_sha256" => entry["evidence_manifest_sha256"],
        "claim_boundary" => accepted_claim_boundary
      }.merge(expected_binding)
    end
    gate = bound_json!(entry["task_gate_receipt_path"], entry["task_gate_receipt_sha256"], evidence_root, "accepted Exit capability Task Gate receipt")
    stop!("accepted Exit capability Task Gate receipt content drift") unless gate == {
      "record_type" => "aios_phase_delegated_task_gate_receipt",
      "status" => "ACCEPTED",
      "authority" => "MASTER_CEO_AGENT",
      "task_id" => entry["task_id"],
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => commit,
      "candidate_tree" => tree,
      "evidence_manifest_sha256" => entry["evidence_manifest_sha256"],
      "cto_review_sha256" => entry["cto_review_sha256"],
      "security_review_sha256" => entry["security_review_sha256"],
      "quality_review_sha256" => entry["quality_review_sha256"],
      "claim_boundary" => accepted_claim_boundary
    }.merge(expected_binding)
  when "ARCHITECTURE_BLOCKED"
    entry = attempts.first
    entry_capabilities = entry ? record_capabilities(entry) : []
    if post_revision_capabilities.include?(capability)
      stop!("post-revision final route stopped without its terminal binding") unless post_revision_terminal
    end
    post_revision_contract_terminal =
      post_revision_terminal && post_revision_capabilities.include?(capability) &&
      post_revision_terminal["failure_stage"] == "FINAL_CONTRACT_REVIEW_NON_PASS"
    if post_revision_contract_terminal
      stop!("post-revision final Contract terminal unexpectedly consumed implementation") unless
        attempts.empty? && post_revision_attempt.nil? &&
        post_revision_terminal["implementation_attempt_consumed"] == false
      next
    end
    integrated_terminal = integrated_member && entry && entry_capabilities == integrated_route_capabilities && entry["task_id"] == integrated_route["task_id"]
    final_clean_room_terminal = effective_final_capabilities.include?(capability) && entry && entry_capabilities == effective_final_capabilities && entry["task_id"] == effective_final_route["task_id"] && entry["founder_final_clean_room_route_id"] == effective_final_route_id
    execution_ledger = if final_clean_room_terminal
      effective_final_attempt
    elsif integrated_terminal
      integrated_primary_ledger
    else
      ledger
    end
    stop!("architecture-blocked Exit capability lacks terminal Evidence binding") unless entry && execution_ledger.is_a?(Hash) && execution_ledger["status"] == "ARCHITECTURE_BLOCKED" && execution_ledger["task_id"] == entry["task_id"] && execution_ledger["attempt_ordinal"] == 1 && exact_terminal_status?(entry["status"]) && entry["founder_escalation_required"] == true
    terminal = entry["terminal_evidence"]
    evidence_root = entry["execution_evidence_root"]
    stop!("architecture-blocked Exit capability Evidence root invalid") unless terminal.is_a?(Hash) && safe_under_root?(evidence_root, recovery_evidence_base, must_exist: true)
    manifest = bound_json!(terminal["evidence_manifest_path"], terminal["evidence_manifest_sha256"], evidence_root, "architecture-blocked Exit capability terminal manifest")
    stop!("architecture-blocked Exit capability terminal manifest content drift") unless manifest == {
      "record_type" => "aios_p1_mandatory_capability_terminal_evidence_manifest",
      "status" => entry["status"],
      "task_id" => entry["task_id"],
      "attempt_ordinal" => 1,
      "task_contract_sha256" => execution_ledger["contract_sha256"],
      "bounded_contract_corrections_used" => execution_ledger["bounded_contract_corrections_used"],
      "failure_classification" => "REAL_ARCHITECTURE_ROOT"
    }.merge(capability_binding_fields(entry_capabilities))
    if post_revision_terminal && post_revision_capabilities.include?(capability)
      stop!("post-revision architecture terminal stage drift") unless
        post_revision_terminal["failure_stage"] == "REAL_ARCHITECTURE_IMPLEMENTATION_FAILURE" &&
        post_revision_terminal["implementation_attempt_consumed"] == true
    end
  when "CONTRACT_REVIEW_BLOCKED"
    stop!("contract-review-blocked Exit capability cannot have an execution history entry") unless attempts.empty?
    integrated_contract_failure = integrated_member && integrated_primary_ledger.is_a?(Hash) && integrated_primary_ledger["task_id"] == integrated_route["task_id"]
    execution_ledger = integrated_contract_failure ? integrated_primary_ledger : ledger
    stop!("contract-review-blocked Exit capability ledger invalid") unless execution_ledger.is_a?(Hash) && execution_ledger["status"] == "CONTRACT_REVIEW_BLOCKED" && execution_ledger["attempt_ordinal"] == 1 && execution_ledger["founder_escalation_required"] == true
    historical_boundary_entry!(
      historical_metadata_boundary,
      execution_ledger["failure_record_path"],
      execution_ledger["failure_record_sha256"],
      "JSON",
      "CONTRACT_REVIEW_FAILURE",
      "contract review failure record"
    )
  when "FOUNDER_DISPOSED"
    disposition = founder_dispositions[capability]
    stop!("Founder-disposed Exit capability lacks an approved decision binding") unless disposition.is_a?(Hash) && disposition["status"] == "APPROVED"
    decision = bound_json!(disposition["decision_record_path"], disposition["decision_record_sha256"], recovery_evidence_base, "Founder capability disposition")
    blocking_evidence_sha = if ledger&.dig("status") == "CONTRACT_REVIEW_BLOCKED"
      ledger["failure_record_sha256"]
    elsif ledger&.dig("status") == "ARCHITECTURE_BLOCKED"
      attempts.first&.dig("terminal_evidence", "evidence_manifest_sha256")
    end
    stop!("Founder capability disposition content drift") unless decision == {
      "record_type" => "sourcelens_aios_founder_mandatory_capability_disposition",
      "status" => "APPROVED",
      "authority" => "HUMAN_FOUNDER",
      "mandatory_exit_capability" => capability,
      "blocked_task_id" => ledger&.dig("task_id"),
      "blocked_attempt_ordinal" => ledger&.dig("attempt_ordinal"),
      "blocking_evidence_sha256" => blocking_evidence_sha
    }
  end
end

if (transition = previous_truth_transition(truth_bytes))
  previous_truth = YAML.safe_load(transition[0], aliases: false)
  transition_truth = YAML.safe_load(transition[1], aliases: false)
  previous_recovery = previous_truth["mandatory_exit_capability_recovery"]
  current_recovery = transition_truth["mandatory_exit_capability_recovery"]
  if previous_recovery.is_a?(Hash) && current_recovery.is_a?(Hash)
    stop!("current Truth top-level schema changed") unless previous_truth.keys == transition_truth.keys
    %w[
      schema_version record_type phase_boundary p0_baseline
      superseded_pre_delegation_authorizations gate_history historical_lineages
    ].each do |field|
      stop!("current Truth immutable control surface changed: #{field}") unless transition_truth[field] == previous_truth[field]
    end
    previous_phase_execution_claim = Marshal.load(Marshal.dump(previous_truth.fetch("phase_execution_claim")))
    current_phase_execution_claim = Marshal.load(Marshal.dump(transition_truth.fetch("phase_execution_claim")))
    %w[current_task_claim historical_terminal_rules mandatory_priority_rule].each do |field|
      previous_phase_execution_claim.delete(field)
      current_phase_execution_claim.delete(field)
    end
    stop!("current Truth immutable control surface changed: phase_execution_claim") unless
      current_phase_execution_claim == previous_phase_execution_claim
    previous_project = Marshal.load(Marshal.dump(previous_truth.fetch("project")))
    current_project = Marshal.load(Marshal.dump(transition_truth.fetch("project")))
    %w[phase_execution_status p1_execution_status canonical_repository task_worktree_root].each do |field|
      previous_project.delete(field)
      current_project.delete(field)
    end
    stop!("current Truth project identity or Phase envelope changed") unless current_project == previous_project
    previous_goal = Marshal.load(Marshal.dump(previous_truth.fetch("goal")))
    current_goal = Marshal.load(Marshal.dump(transition_truth.fetch("goal")))
    %w[current_task_authority control_plane_status_observed].each do |field|
      previous_goal.delete(field)
      current_goal.delete(field)
    end
    stop!("current Truth Goal identity changed") unless current_goal == previous_goal
    previous_claims = previous_truth.fetch("claim_boundary")
    current_claims = transition_truth.fetch("claim_boundary")
    previous_claims.each do |key, value|
      stop!("current Truth claim was removed or rewritten: #{key}") unless current_claims[key] == value
    end
    previous_history = previous_truth.fetch("task_history")
    current_history = transition_truth.fetch("task_history")
    previous_history.each do |key, value|
      stop!("Task history is not append-only across current Truth transition: #{key}") unless current_history[key] == value
    end

    previous_recovery_invariants = Marshal.load(Marshal.dump(previous_recovery))
    current_recovery_invariants = Marshal.load(Marshal.dump(current_recovery))
    %w[
      historical_governance_metadata_read_boundary capability_status capability_attempt_ledger
      integrated_capability_routes final_clean_room_implementation_route
      final_clean_room_implementation_attempt final_clean_room_contract_review_terminal
      post_revision_final_implementation_route post_revision_final_implementation_attempt
      post_revision_final_route_terminal project_level_rebaseline founder_dispositions
      founder_decision_source maximum_same_task_bounded_contract_repairs
    ].each do |field|
      previous_recovery_invariants.delete(field)
      current_recovery_invariants.delete(field)
    end
    stop!("mandatory Exit capability recovery invariant surface changed") unless
      current_recovery_invariants == previous_recovery_invariants

    previous_integrated_routes = previous_recovery["integrated_capability_routes"] || {}
    current_integrated_routes = current_recovery["integrated_capability_routes"] || {}
    stop!("integrated capability route history invalid") unless previous_integrated_routes.is_a?(Hash) && current_integrated_routes.is_a?(Hash)
    if previous_integrated_routes.empty?
      stop!("integrated capability route initialization must add exactly one closed route") unless current_integrated_routes.empty? || current_integrated_routes.length == 1
    else
      stop!("integrated capability route was removed, replaced, renamed or rebound") unless current_integrated_routes == previous_integrated_routes
    end

    previous_final_route = previous_recovery["final_clean_room_implementation_route"]
    current_final_route = current_recovery["final_clean_room_implementation_route"]
    if previous_final_route
      stop!("final clean-room route was removed, replaced or rebound") unless current_final_route == previous_final_route
    elsif current_final_route
      stop!("final clean-room route initialization is not Founder-bound") unless
        current_final_route["record_type"] == "p1_founder_approved_final_clean_room_implementation_route" &&
        current_final_route["authority"] == "HUMAN_FOUNDER" && current_final_route["reusable"] == false
    end

    previous_boundary = previous_recovery["historical_governance_metadata_read_boundary"]
    current_boundary = current_recovery["historical_governance_metadata_read_boundary"]
    if previous_boundary
      stop!("historical governance metadata boundary was removed or rebound") unless current_boundary == previous_boundary
    elsif current_boundary
      stop!("historical governance metadata boundary initialization is not Founder-bound") unless
        current_boundary["authority"] == "HUMAN_FOUNDER" &&
        current_boundary["status"] == "FOUNDER_APPROVED_ACTIVE" &&
        current_boundary["decision_record_sha256"] == boundary_decision_sha
    end

    previous_post_revision_route = previous_recovery["post_revision_final_implementation_route"]
    current_post_revision_route = current_recovery["post_revision_final_implementation_route"]
    if previous_post_revision_route
      stop!("post-revision final route was removed, replaced or rebound") unless current_post_revision_route == previous_post_revision_route
    elsif current_post_revision_route
      stop!("post-revision final route initialization is not exact Founder-bound") unless
        current_post_revision_route["authority"] == "HUMAN_FOUNDER" &&
        current_post_revision_route["status"] == "FOUNDER_APPROVED_ONE_TIME" &&
        current_post_revision_route["decision_record_sha256"] == boundary_decision_sha &&
        current_post_revision_route["reusable"] == false
    end

    previous_rebaseline = previous_recovery["project_level_rebaseline"]
    current_rebaseline = current_recovery["project_level_rebaseline"]
    if previous_rebaseline
      stop!("P1 project-level rebaseline was removed") unless current_rebaseline.is_a?(Hash)
      previous_rebaseline_immutable = Marshal.load(Marshal.dump(previous_rebaseline))
      current_rebaseline_immutable = Marshal.load(Marshal.dump(current_rebaseline))
      %w[p1_status current_task slice_attempts next_slice_ordinal next_slice_action].each do |field|
        previous_rebaseline_immutable.delete(field)
        current_rebaseline_immutable.delete(field)
      end
      stop!("P1 project-level rebaseline immutable binding drift") unless
        current_rebaseline_immutable == previous_rebaseline_immutable
    elsif current_rebaseline
      stop!("P1 project-level rebaseline initialization is not Founder-bound") unless
        current_rebaseline.is_a?(Hash) &&
        current_rebaseline["authority"] == "HUMAN_FOUNDER" &&
        current_rebaseline["decision_record_sha256"] == "083dc4d5f071bb82b6da3681c62e5a4ce37bfa8cac52c3f4da0f0ac5fea2d1f2"
    end

    allowed_status_transitions = {
      "MISSING" => %w[MISSING REBASELINED_PENDING_EXECUTION IN_PROGRESS CONTRACT_REVIEW_BLOCKED FOUNDER_DISPOSED],
      "RELOCATED_PENDING_INTEGRATED_TASK" => %w[RELOCATED_PENDING_INTEGRATED_TASK IN_PROGRESS CONTRACT_REVIEW_BLOCKED],
      "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION" => %w[FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION IN_PROGRESS CONTRACT_REVIEW_BLOCKED],
      "FOUNDER_REVISED_PENDING_IMPLEMENTATION" => %w[FOUNDER_REVISED_PENDING_IMPLEMENTATION REBASELINED_PENDING_EXECUTION IN_PROGRESS ARCHITECTURE_BLOCKED],
      "REBASELINED_PENDING_EXECUTION" => %w[REBASELINED_PENDING_EXECUTION IN_PROGRESS ACCEPTED ARCHITECTURE_BLOCKED],
      "IN_PROGRESS" => %w[IN_PROGRESS ACCEPTED ARCHITECTURE_BLOCKED],
      "CONTRACT_REVIEW_BLOCKED" => %w[CONTRACT_REVIEW_BLOCKED RELOCATED_PENDING_INTEGRATED_TASK FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION FOUNDER_REVISED_PENDING_IMPLEMENTATION FOUNDER_DISPOSED],
      "ARCHITECTURE_BLOCKED" => %w[ARCHITECTURE_BLOCKED REBASELINED_PENDING_EXECUTION FOUNDER_DISPOSED],
      "ACCEPTED" => %w[ACCEPTED],
      "FOUNDER_DISPOSED" => %w[FOUNDER_DISPOSED]
    }
    expected_exit_capabilities.each do |capability|
      previous_state = previous_recovery.dig("capability_status", capability)
      current_state = current_recovery.dig("capability_status", capability)
      stop!("mandatory Exit capability status transition invalid: #{capability}") unless allowed_status_transitions.fetch(previous_state).include?(current_state)
      if previous_state == "CONTRACT_REVIEW_BLOCKED" && current_state == "FOUNDER_REVISED_PENDING_IMPLEMENTATION"
        stop!("Founder revision transition may occur only while initializing the one post-revision route") unless
          previous_post_revision_route.nil? && current_post_revision_route &&
          current_post_revision_route["route_id"] == "P1_039_POST_REVISION_FINAL_IMPLEMENTATION_ROUTE"
      end
      previous_attempt = previous_recovery.dig("capability_attempt_ledger", capability)
      current_attempt = current_recovery.dig("capability_attempt_ledger", capability)
      if previous_attempt
        stop!("mandatory Exit capability attempt ledger was erased: #{capability}") unless current_attempt.is_a?(Hash)
        %w[task_id attempt_ordinal contract_sha256 bounded_contract_corrections_used].each do |field|
          stop!("mandatory Exit capability attempt identity changed: #{capability}/#{field}") unless current_attempt[field] == previous_attempt[field]
        end
        %w[integrated_mandatory_exit_capabilities founder_architecture_route_id].each do |field|
          stop!("mandatory Exit capability integrated attempt identity changed: #{capability}/#{field}") if previous_attempt.key?(field) && current_attempt[field] != previous_attempt[field]
        end
        if current_final_route && Array(current_final_route["mandatory_exit_capabilities"]).include?(capability)
          stop!("final clean-room route changed historical contract-attempt ledger: #{capability}") unless current_attempt == previous_attempt
        end
      end
    end
    if integrated_route
      previous_route_states = integrated_route_capabilities.map { |capability| previous_recovery.dig("capability_status", capability) }
      current_route_states = integrated_route_capabilities.map { |capability| current_recovery.dig("capability_status", capability) }
      allowed_atomic_route_transitions = [
        [["CONTRACT_REVIEW_BLOCKED", "MISSING"], ["RELOCATED_PENDING_INTEGRATED_TASK", "MISSING"]],
        [["RELOCATED_PENDING_INTEGRATED_TASK", "MISSING"], ["IN_PROGRESS", "IN_PROGRESS"]],
        [["RELOCATED_PENDING_INTEGRATED_TASK", "MISSING"], ["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"]],
        [["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"], ["FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION", "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"]],
        [["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"], ["FOUNDER_REVISED_PENDING_IMPLEMENTATION", "FOUNDER_REVISED_PENDING_IMPLEMENTATION"]],
        [["FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION", "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"], ["IN_PROGRESS", "IN_PROGRESS"]],
        [["FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION", "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"], ["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"]],
        [["FOUNDER_REVISED_PENDING_IMPLEMENTATION", "FOUNDER_REVISED_PENDING_IMPLEMENTATION"], ["IN_PROGRESS", "IN_PROGRESS"]],
        [["FOUNDER_REVISED_PENDING_IMPLEMENTATION", "FOUNDER_REVISED_PENDING_IMPLEMENTATION"], ["ARCHITECTURE_BLOCKED", "ARCHITECTURE_BLOCKED"]],
        [["ARCHITECTURE_BLOCKED", "ARCHITECTURE_BLOCKED"], ["REBASELINED_PENDING_EXECUTION", "REBASELINED_PENDING_EXECUTION"]],
        [["REBASELINED_PENDING_EXECUTION", "REBASELINED_PENDING_EXECUTION"], ["IN_PROGRESS", "IN_PROGRESS"]],
        [["IN_PROGRESS", "IN_PROGRESS"], ["ACCEPTED", "ACCEPTED"]],
        [["IN_PROGRESS", "IN_PROGRESS"], ["ACCEPTED", "ACCEPTED"]],
        [["IN_PROGRESS", "IN_PROGRESS"], ["ARCHITECTURE_BLOCKED", "ARCHITECTURE_BLOCKED"]]
      ]
      if previous_route_states != current_route_states && current_rebaseline.nil?
        stop!("integrated capability route transition is not atomic") unless allowed_atomic_route_transitions.include?([previous_route_states, current_route_states])
      end
      blocked_capability = integrated_route_capabilities.first
      previous_blocked_ledger = previous_recovery.dig("capability_attempt_ledger", blocked_capability)
      current_blocked_ledger = current_recovery.dig("capability_attempt_ledger", blocked_capability)
      stop!("P1-036 blocked route ledger changed across integrated route transition") unless previous_blocked_ledger == current_blocked_ledger
    end


    previous_final_attempt = previous_recovery["final_clean_room_implementation_attempt"]
    current_final_attempt = current_recovery["final_clean_room_implementation_attempt"]
    if previous_final_attempt
      stop!("final clean-room implementation attempt was erased") unless current_final_attempt.is_a?(Hash)
      %w[task_id attempt_ordinal contract_sha256 founder_final_clean_room_route_id].each do |field|
        stop!("final clean-room implementation attempt identity changed: #{field}") unless current_final_attempt[field] == previous_final_attempt[field]
      end
    end


    previous_post_revision_attempt = previous_recovery["post_revision_final_implementation_attempt"]
    current_post_revision_attempt = current_recovery["post_revision_final_implementation_attempt"]
    if previous_post_revision_attempt
      stop!("post-revision final implementation attempt was erased") unless current_post_revision_attempt.is_a?(Hash)
      %w[task_id attempt_ordinal contract_sha256 founder_final_clean_room_route_id].each do |field|
        stop!("post-revision final implementation attempt identity changed: #{field}") unless current_post_revision_attempt[field] == previous_post_revision_attempt[field]
      end
    end

    previous_post_revision_terminal = previous_recovery["post_revision_final_route_terminal"]
    current_post_revision_terminal = current_recovery["post_revision_final_route_terminal"]
    if previous_post_revision_terminal
      stop!("post-revision final route terminal binding changed or was removed") unless
        current_post_revision_terminal == previous_post_revision_terminal
    elsif current_post_revision_terminal
      stop!("post-revision final route terminal was added without the frozen route") unless
        previous_post_revision_route && current_post_revision_route == previous_post_revision_route
      terminal_capabilities = Array(current_post_revision_terminal["mandatory_exit_capabilities"])
      previous_terminal_states = terminal_capabilities.map { |capability| previous_recovery.dig("capability_status", capability) }
      current_terminal_states = terminal_capabilities.map { |capability| current_recovery.dig("capability_status", capability) }
      expected_pre_state = if current_post_revision_terminal["failure_stage"] == "FINAL_CONTRACT_REVIEW_NON_PASS"
        ["FOUNDER_REVISED_PENDING_IMPLEMENTATION", "FOUNDER_REVISED_PENDING_IMPLEMENTATION"]
      else
        ["IN_PROGRESS", "IN_PROGRESS"]
      end
      stop!("post-revision final route terminal pre-state invalid") unless previous_terminal_states == expected_pre_state
      stop!("post-revision final route terminal projection is not atomic") unless
        current_terminal_states == ["ARCHITECTURE_BLOCKED", "ARCHITECTURE_BLOCKED"]
    end

    previous_final_terminal = previous_recovery["final_clean_room_contract_review_terminal"]
    current_final_terminal = current_recovery["final_clean_room_contract_review_terminal"]
    if previous_final_terminal
      stop!("final clean-room contract-review terminal binding changed") unless current_final_terminal == previous_final_terminal
    elsif current_final_terminal
      stop!("final clean-room contract-review terminal was added after implementation activation") unless previous_final_attempt.nil? && current_final_attempt.nil?
      terminal_capabilities = Array(current_final_terminal["mandatory_exit_capabilities"])
      previous_terminal_states = terminal_capabilities.map { |capability| previous_recovery.dig("capability_status", capability) }
      current_terminal_states = terminal_capabilities.map { |capability| current_recovery.dig("capability_status", capability) }
      stop!("final clean-room contract-review terminal pre-state invalid") unless previous_terminal_states == ["FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION", "FOUNDER_RECALIBRATED_PENDING_IMPLEMENTATION"]
      stop!("final clean-room contract-review terminal projection is not atomic") unless current_terminal_states == ["CONTRACT_REVIEW_BLOCKED", "CONTRACT_REVIEW_BLOCKED"]
    end
  end
end

phase = truth.dig("project", "current_phase")
stop!("current Phase missing") unless phase.is_a?(String) && phase.match?(/\AP\d+\z/)
stop!("Phase entry is not authorized") unless truth.dig("project", "#{phase.downcase}_entry_status") == "AUTHORIZED"
phase_boundary = truth.fetch("phase_boundary")
stop!("Phase boundary identity drift") unless phase_boundary["phase"] == phase
allowed_task_kinds = phase_boundary["allowed_task_kinds"]
allowed_capabilities = phase_boundary["allowed_capabilities"]
role_write_roots = phase_boundary["role_write_roots"]
immutable_paths = phase_boundary["immutable_authority_paths"]
allowed_reviewers = phase_boundary["allowed_independent_reviewers"]
reviewers_by_risk = phase_boundary["required_reviewers_by_risk"]
stop!("Phase task kinds missing") unless nonempty_list?(allowed_task_kinds)
stop!("Phase capability allowlist missing") unless allowed_capabilities.is_a?(Array)
stop!("Phase role write roots missing") unless role_write_roots.is_a?(Hash) && %w[worker quality integration external_evidence].all? { |role| role_write_roots.key?(role) }
phase_role_roots = %w[worker quality integration].flat_map do |role|
  Array(role_write_roots[role]).map { |path| [role, path] }
end
phase_role_roots.combination(2).each do |(left_role, left), (right_role, right)|
  next if left_role == right_role
  stop!("Phase role write roots overlap: #{left_role}/#{right_role}") if path_overlap?(left, right)
end
stop!("Phase immutable paths missing") unless nonempty_list?(immutable_paths)
stop!("Phase reviewer policy missing") unless nonempty_list?(allowed_reviewers) && reviewers_by_risk.is_a?(Hash)
canonical_root = truth.dig("project", "canonical_repository")
worktree_root = truth.dig("project", "task_worktree_root")
evidence_base = truth.dig("project", "execution_evidence_root_base")
rebuild_mode_value = ENV.fetch("SOURCELENS_REBUILD_VERIFY", "0")
stop!("rebuild verification mode value invalid") unless %w[0 1].include?(rebuild_mode_value)
rebuild_verification_mode = rebuild_mode_value == "1"
stop!("canonical repository path invalid") unless
  nonempty_string?(canonical_root) &&
  safe_under_root?(canonical_root, File.dirname(canonical_root), must_exist: true) &&
  File.directory?(canonical_root) &&
  !File.symlink?(canonical_root)

runtime_worktree = git("worktree", "list", "--porcelain").lines.first.to_s.sub(/^worktree /, "").strip
stop!("runtime worktree identity invalid") unless
  nonempty_string?(runtime_worktree) &&
  File.directory?(runtime_worktree) &&
  File.realpath(runtime_worktree) == File.realpath(REPO_ROOT)

rebuild_clone_status_before = nil
rebuild_canonical_status_before = nil
if rebuild_verification_mode
  stop!("rebuild verification mode requires a non-canonical fresh clone") if File.realpath(canonical_root) == File.realpath(REPO_ROOT)
  stop!("rebuild verification mode requires current Task NONE") unless truth.dig("goal", "current_task_authority") == "NONE" && truth.dig("active_work", "current_task") == "NONE"
  stop!("rebuild verification mode requires ACTIVE Goal") unless truth.dig("goal", "control_plane_status_observed") == "ACTIVE"
  stop!("rebuild verification mode branch drift") unless
    git("branch", "--show-current") == truth.dig("project", "canonical_branch") &&
    git_at(canonical_root, "branch", "--show-current") == truth.dig("project", "canonical_branch")
  rebuild_clone_status_before = git("status", "--porcelain=v1", "--untracked-files=all")
  rebuild_canonical_status_before = git_at(canonical_root, "status", "--porcelain=v1", "--untracked-files=all")
  stop!("rebuild verification clone is not clean") unless rebuild_clone_status_before.empty?
  stop!("canonical repository is not clean during rebuild verification") unless rebuild_canonical_status_before.empty?
  stop!("rebuild verification HEAD drift") unless git("rev-parse", "HEAD") == git_at(canonical_root, "rev-parse", "HEAD")
  stop!("rebuild verification tree drift") unless git("rev-parse", "HEAD^{tree}") == git_at(canonical_root, "rev-parse", "HEAD^{tree}")
else
  stop!("canonical repository identity drift") unless File.realpath(canonical_root) == File.realpath(runtime_worktree)
end

authority_runtime_root = rebuild_verification_mode ? REPO_ROOT : canonical_root
stop!("worktree root invalid") unless File.directory?(worktree_root) && !File.symlink?(worktree_root)
stop!("Evidence root base invalid") unless File.directory?(evidence_base) && !File.symlink?(evidence_base)

active = truth.fetch("active_work")
stop!("active work schema drift") unless active.is_a?(Hash) && active.keys.sort == ACTIVE_WORK_KEYS.sort
current_task = active["current_task"]
current_status = active["current_task_status"]
goal_task = truth.dig("goal", "current_task_authority")
project_status = truth.dig("project", "phase_execution_status")
if rebaseline && current_task == "NONE"
  stop!("P1 rebaseline current Task projection drift") unless rebaseline["current_task"] == "NONE"
elsif rebaseline && rebaseline["p1_status"] == "REBASELINED_SLICE_ACTIVE"
  stop!("P1 rebaseline active Task projection drift") unless
    rebaseline["current_task"] == current_task && rebaseline["p1_status"] == "REBASELINED_SLICE_ACTIVE"
end
stop!("phase/P1 execution status drift") if phase == "P1" && truth.dig("project", "p1_execution_status") != project_status
next_action = active["next_eligible_action"]
stop!("next eligible action missing") unless nonempty_string?(next_action)
founder_required = active["founder_decision_required"]
escalation_reason = active["escalation_reason"]
user_action = active["user_action_required"]

task_branches = git("for-each-ref", "--format=%(refname:short)", "refs/heads/task/").lines.map(&:strip).reject(&:empty?)
worktrees = worktree_records
canonical_real = File.realpath(authority_runtime_root)
canonical_worktrees = worktrees.select do |entry|
  begin
    File.realpath(entry.fetch("worktree")) == canonical_real
  rescue Errno::ENOENT
    false
  end
end
stop!("canonical worktree population drift") unless canonical_worktrees.length == 1

if current_task == "NONE"
  stop!("NONE state cannot retain an in-progress Exit capability") if capability_status.value?("IN_PROGRESS")
  founder_blocked_capabilities = capability_status.select { |_capability, state| %w[ARCHITECTURE_BLOCKED CONTRACT_REVIEW_BLOCKED].include?(state) }.keys
  stop!("NONE state goal authority drift") unless goal_task == "NONE"
  allowed_none_project_statuses = rebaseline ? %w[REBASELINED_PENDING_EXECUTION NO_CURRENT_TASK] : %w[NO_CURRENT_TASK]
  stop!("NONE state status drift") unless current_status == "NONE" && allowed_none_project_statuses.include?(project_status)
  %w[
    current_task_contract current_task_contract_sha256 current_execution_authorization
    current_execution_authorization_sha256 execution_nonce authorization_id
    activation_parent_commit activation_parent_tree task_branch task_worktree
    execution_evidence_root offsite_target founder_reserved_authorization
    founder_reserved_authorization_sha256
  ].each do |field|
    stop!("NONE state field must be null: #{field}") unless active[field].nil?
  end
  stop!("NONE state nonce status drift") unless active["execution_nonce_status"] == "NONE"
  stop!("NONE state resource status drift") unless active["task_resource_state"] == "NONE"
  if founder_blocked_capabilities.empty?
    stop!("NONE state cannot require a Founder decision") unless founder_required == false && escalation_reason.nil?
  elsif post_revision_terminal
    stop!("post-revision final route terminal must escalate project-level Founder disposition") unless
      founder_required == true &&
      escalation_reason == "p1_post_revision_final_route_terminal_stop" &&
      user_action == "FOUNDER_PROJECT_LEVEL_DISPOSITION_REQUIRED"
  else
    stop!("blocked mandatory capability must escalate Founder") unless founder_required == true && escalation_reason == "mandatory_exit_capability_blocked" && user_action == "FOUNDER_DECISION_REQUIRED"
  end
  stop!("NONE state task claim drift") unless truth.dig("phase_execution_claim", "current_task_claim") == "NO_CURRENT_TASK"
  stop!("Task branches remain while no Task is active") unless task_branches.empty?
  stop!("Task worktrees remain while no Task is active") unless worktrees.length == 1
  forbidden_routine_action = /FOUNDER.*(APPROV|AUTHORIZ)|REQUEST.*FOUNDER|WAIT.*FOUNDER/
  stop!("routine Founder Task approval advertised") if founder_blocked_capabilities.empty? && next_action.match?(forbidden_routine_action)
  goal_state = truth.dig("goal", "control_plane_status_observed")
  if goal_state == "BLOCKED"
    stop!("blocked Goal must request only control-plane resume") unless user_action == "RESUME_LONG_TERM_GOAL_CONTROL_PLANE" && next_action.start_with?("USER_RESUME_LONG_TERM_GOAL")
  elsif goal_state == "ACTIVE"
    if founder_blocked_capabilities.empty?
      stop!("active Goal cannot require routine user action") unless user_action.nil?
      stop!("active Goal must advertise autonomous Master continuation") unless next_action.include?("MASTER_AUTONOMOUS")
    elsif post_revision_terminal
      stop!("post-revision final route terminal must stop P1 and wait for project disposition") unless
        next_action == "STOP_P1_AND_WAIT_FOR_PROJECT_LEVEL_DISPOSITION"
    else
      stop!("blocked mandatory capability must wait for Founder disposition") unless next_action == "WAIT_FOR_FOUNDER_MANDATORY_EXIT_CAPABILITY_DECISION"
    end
  else
    stop!("Goal control-plane state invalid")
  end
  if rebuild_verification_mode
    stop!("rebuild verification clone changed during validation") unless git("status", "--porcelain=v1", "--untracked-files=all") == rebuild_clone_status_before
    stop!("canonical repository changed during rebuild verification") unless git_at(canonical_root, "status", "--porcelain=v1", "--untracked-files=all") == rebuild_canonical_status_before
    stop!("canonical HEAD changed during rebuild verification") unless git("rev-parse", "HEAD") == git_at(canonical_root, "rev-parse", "HEAD")
    stop!("canonical tree changed during rebuild verification") unless git("rev-parse", "HEAD^{tree}") == git_at(canonical_root, "rev-parse", "HEAD^{tree}")
  end
  puts "Current Task authority validation passed: NONE under Phase-level delegation."
  exit 0
end

stop!("post-revision terminal route cannot activate another Task without an approved project-level rebaseline") if post_revision_terminal && !rebaseline

expected_task_pattern = /\AAIOS-#{Regexp.escape(phase)}-\d{3}(?:[_-][A-Z0-9_-]+)?\z/
stop!("active Task id/Phase format invalid") unless nonempty_string?(current_task) && current_task.match?(expected_task_pattern)
current_task_number = current_task.match(/\AAIOS-#{Regexp.escape(phase)}-(\d{3})/)[1].to_i
stop!("P1-002..P1-034 historical Task ID range is reserved") if phase == "P1" && current_task_number.between?(2, 34)
history_entries = truth.fetch("task_history").values.select { |entry| entry.is_a?(Hash) && nonempty_string?(entry["task_id"]) }
stop!("historical Task cannot be reactivated") if history_entries.any? { |entry| entry["task_id"] == current_task }
terminal_history_ids = history_entries.select do |entry|
  status = entry["status"].to_s
  status.include?("TERMINAL") || status.include?("STOPPED") || status.include?("REJECTED") || entry["resume_retry_successor_allowed"] == false
end.map { |entry| entry["task_id"] }
accepted_history_ids = history_entries.reject { |entry| terminal_history_ids.include?(entry["task_id"]) }.select do |entry|
  status = entry["status"].to_s
  status.include?("ACCEPTED") || status.include?("COMPLETE")
end.map { |entry| entry["task_id"] }
stop!("active Task goal authority drift") unless goal_task == current_task
stop!("active Task project status drift") unless project_status == "TASK_ACTIVE"
stop!("active Task lifecycle state invalid") unless %w[AUTHORIZED_ACTIVE IN_PROGRESS REVIEW].include?(current_status)
stop!("blocked Goal cannot host an active Task") unless truth.dig("goal", "control_plane_status_observed") == "ACTIVE"
stop!("active Task cannot request routine user action") unless user_action.nil?
stop!("active Task claim drift") unless truth.dig("phase_execution_claim", "current_task_claim") == current_task

contract_rel = active["current_task_contract"]
contract_sha = active["current_task_contract_sha256"]
stop!("active Task contract path missing") unless nonempty_string?(contract_rel)
contract_pathname = Pathname.new(contract_rel)
stop!("active Task contract path must be repository-relative") if contract_pathname.absolute?
stop!("active Task contract path escapes task directory") unless contract_rel.start_with?("docs/aios/tasks/") && contract_pathname.cleanpath.to_s == contract_rel
historical_failed_contract_paths = historical_metadata_boundary ? historical_metadata_boundary["forbidden_repository_read_paths"] : []
stop!("active Task contract overlaps a historical failed Contract denylist path") if
  historical_failed_contract_paths.any? { |failed_path| path_overlap?(contract_rel, failed_path) }
contract_abs = File.join(REPO_ROOT, contract_rel)
stop!("active Task contract missing or unsafe") unless safe_under_root?(contract_abs, REPO_ROOT, must_exist: true)
stop!("active Task contract hash drift") unless nonempty_string?(contract_sha) && sha256(contract_abs) == contract_sha
contract = YAML.safe_load(File.read(contract_abs), aliases: false)
stop!("active Task contract identity drift") unless contract["task_id"] == current_task
stop!("active Task contract phase drift") unless contract["phase"] == phase
stop!("active Task Contract is not ready") unless contract["status"] == "READY_FOR_PHASE_DELEGATED_EXECUTION" && contract["execution_authority"] == "PHASE_DELEGATED"
stop!("active Task objective missing") unless nonempty_string?(contract["objective"])
stop!("active Task why_now missing") unless nonempty_list?(contract["why_now"]) || nonempty_string?(contract["why_now"])
stop!("active Task spec reference missing") unless nonempty_string?(contract["task_spec_ref"])
stop!("active Task read context missing") unless nonempty_list?(contract["read_context"])
dependencies = contract["dependencies"]
stop!("active Task dependencies must be explicit") unless dependencies.is_a?(Array) && dependencies.all? { |dependency| nonempty_string?(dependency) }
stop!("active Task depends on terminal/nonaccepted Task lineage") unless (dependencies & terminal_history_ids).empty?
stop!("active Task dependency is unknown or not accepted") unless (dependencies - accepted_history_ids).empty?
mandatory_exit_capability = contract["mandatory_exit_capability"]
stop!("active Task is not bound to a mandatory P1 Exit capability") unless expected_exit_capabilities.include?(mandatory_exit_capability)
contract_integrated_capabilities = contract["integrated_mandatory_exit_capabilities"]
contract_route_id = contract["founder_architecture_route_id"]
contract_final_route_id = contract["founder_final_clean_room_route_id"]
contract_rebaseline_slice_ordinal = contract["project_level_rebaseline_slice_ordinal"]
contract_rebaseline_decision_sha = contract["project_level_rebaseline_decision_sha256"]
rebaseline_slice = nil
if contract_rebaseline_slice_ordinal
  stop!("active rebaseline Task mixes historical route identities") unless contract_route_id.nil? && contract_final_route_id.nil?
  stop!("active rebaseline Task slice ordinal invalid") unless contract_rebaseline_slice_ordinal.is_a?(Integer)
  rebaseline_slice = rebaseline["slices"].find { |slice| slice["ordinal"] == contract_rebaseline_slice_ordinal }
  stop!("active Task is not bound to the current approved rebaseline Slice") unless
    rebaseline_slice &&
    contract_rebaseline_slice_ordinal == rebaseline["next_slice_ordinal"] &&
    contract_rebaseline_decision_sha == rebaseline["decision_record_sha256"] &&
    contract_integrated_capabilities == rebaseline_slice["capability_projection"] &&
    mandatory_exit_capability == contract_integrated_capabilities.first &&
    contract["claim_boundary"] == rebaseline_slice["claim_boundary"]
  stop!("active rebaseline Task current-state projection drift") unless
    rebaseline["p1_status"] == "REBASELINED_SLICE_ACTIVE" && rebaseline["current_task"] == current_task
  task_exit_capabilities = contract_integrated_capabilities
elsif contract_final_route_id
  stop!("active Task mixes historical and final clean-room route identities") unless contract_route_id.nil?
  stop!("active Task uses an incomplete final clean-room capability binding") unless contract_integrated_capabilities.is_a?(Array) && nonempty_string?(contract_final_route_id)
  stop!("active Task is not the exact Founder-approved final clean-room route") unless
    effective_final_route && contract_final_route_id == effective_final_route_id &&
    current_task == effective_final_route["task_id"] &&
    mandatory_exit_capability == effective_final_capabilities.last &&
    contract_integrated_capabilities == effective_final_capabilities
  task_exit_capabilities = contract_integrated_capabilities
elsif contract_integrated_capabilities || contract_route_id
  stop!("active Task uses an incomplete integrated capability binding") unless contract_integrated_capabilities.is_a?(Array) && nonempty_string?(contract_route_id)
  stop!("active Task is not the exact Founder-approved integrated route") unless integrated_route && contract_route_id == integrated_route_id && current_task == integrated_route["task_id"] && mandatory_exit_capability == integrated_route["primary_capability"] && contract_integrated_capabilities == integrated_route_capabilities
  task_exit_capabilities = contract_integrated_capabilities
else
  task_exit_capabilities = [mandatory_exit_capability]
end
stop!("active Task mandatory Exit capabilities are not all in progress") unless task_exit_capabilities.all? { |capability| capability_status[capability] == "IN_PROGRESS" }
earlier_exit_capabilities = expected_exit_capabilities.take_while { |capability| capability != mandatory_exit_capability }
if rebaseline_slice
  stop!("active rebaseline Task does not follow the approved Slice order") unless
    rebaseline["slice_attempts"].keys.map(&:to_i).all? { |ordinal| ordinal <= contract_rebaseline_slice_ordinal }
else
  unclosed_earlier_capabilities = earlier_exit_capabilities.reject do |capability|
    %w[ACCEPTED FOUNDER_DISPOSED].include?(capability_status[capability]) || (task_exit_capabilities.include?(capability) && capability_status[capability] == "IN_PROGRESS")
  end
  stop!("active Task bypasses an earlier mandatory Exit capability") unless unclosed_earlier_capabilities.empty?
end
clean_room = contract["clean_room_recovery"]
stop!("active Task clean-room recovery declaration missing") unless clean_room.is_a?(Hash)
stop!("active Task reuses historical execution lineage") unless clean_room["historical_execution_lineage_reused"] == false
stop!("active Task clean-room attempt ordinal drift") unless clean_room["attempt_ordinal"] == 1
expected_contract_correction_limit = (contract_final_route_id || rebaseline_slice) ? 0 : 1
stop!("active Task bounded Contract correction limit drift") unless clean_room["bounded_contract_corrections_allowed"] == expected_contract_correction_limit
corrections_used = clean_room["bounded_contract_corrections_used"]
stop!("active Task bounded Contract correction usage invalid") unless corrections_used.is_a?(Integer) && corrections_used.between?(0, expected_contract_correction_limit)
if corrections_used.zero?
  stop!("uncorrected Contract must not bind original Contract bytes") unless clean_room["original_contract_path"].nil? && clean_room["original_contract_sha256"].nil?
  if contract_final_route_id || rebaseline_slice
    frozen_contract_bytes = git_file(active["activation_parent_commit"], contract_rel)
    frozen_contract_error = rebaseline_slice ?
      "single final Contract was not frozen at the activation parent" :
      "final clean-room Contract was not frozen at the activation parent"
    stop!(frozen_contract_error) unless frozen_contract_bytes && Digest::SHA256.hexdigest(frozen_contract_bytes) == contract_sha
  else
    stop!("uncorrected Contract cannot replace a pre-existing Task Contract") unless git_file(active["activation_parent_commit"], contract_rel).nil?
  end
else
  stop!("corrected Contract original path must be its canonical tracked path") unless clean_room["original_contract_path"] == contract_rel
  stop!("corrected Contract original hash invalid") unless clean_room["original_contract_sha256"].is_a?(String) && clean_room["original_contract_sha256"].match?(/\A[0-9a-f]{64}\z/)
end
active_attempt = if rebaseline_slice
  rebaseline["slice_attempts"][contract_rebaseline_slice_ordinal.to_s]
elsif contract_final_route_id
  effective_final_attempt
else
  attempt_ledger[mandatory_exit_capability]
end
prior_clean_room_attempts = history_entries.select { |entry| entry["mandatory_exit_capability"] == mandatory_exit_capability }
stop!("mandatory Exit capability clean-room attempt already consumed") unless prior_clean_room_attempts.empty?
stop!("active Task read context must be canonical repository-relative paths") unless contract["read_context"].all? do |path|
  nonempty_string?(path) && path != "." && !Pathname.new(path).absolute? && Pathname.new(path).cleanpath.to_s == path &&
    safe_under_root?(File.join(REPO_ROOT, path), REPO_ROOT, must_exist: true)
end
terminal_contract_paths = history_entries.select { |entry| terminal_history_ids.include?(entry["task_id"]) }.map { |entry| entry["contract"] }.compact
stop!("active Task read context references or encloses terminal or unaccepted Task assets") unless contract["read_context"].none? do |read_path|
  terminal_contract_paths.any? { |terminal_path| path_overlap?(read_path, terminal_path) }
end
stop!("active Task read context references or encloses historical failed Contract bytes") unless contract["read_context"].none? do |read_path|
  historical_failed_contract_paths.any? { |failed_path| path_overlap?(read_path, failed_path) }
end
task_kind = contract["task_kind"]
stop!("active Task kind outside Phase envelope") unless allowed_task_kinds.include?(task_kind)
capabilities = contract["capabilities"]
stop!("active Task capabilities must be explicit") unless capabilities.is_a?(Array)
stop!("active Task capability is not in the Phase allowlist") unless (capabilities - allowed_capabilities).empty?
stop!("active Task requests a deferred capability") unless (capabilities & phase_boundary.fetch("deferred_capabilities")).empty?
lineage = contract["lineage"]
stop!("active Task lineage missing") unless lineage.is_a?(Hash)
stop!("active Task is not an independent Phase increment") unless lineage["kind"] == "INDEPENDENT_PHASE_INCREMENT"
%w[retries remediates supersedes].each do |field|
  stop!("active Task creates a #{field} chain") unless lineage[field] == []
end

roles = contract["roles"] || {}
owner = roles["accountable_owner"] || contract["owner_role"]
worker = roles["worker"] || contract["worker_role"]
reviewers = roles["independent_reviewers"] || Array(contract["independent_reviewer"])
stop!("active Task accountable Owner missing") unless nonempty_string?(owner)
stop!("active Task Worker missing") unless nonempty_string?(worker)
stop!("active Task independent Reviewer missing") unless nonempty_list?(reviewers) && reviewers.all? { |item| nonempty_string?(item) }
stop!("Worker cannot review itself") if reviewers.include?(worker)
risk_level = contract["risk_level"]
stop!("active Task risk level invalid") unless %w[low medium high critical].include?(risk_level)
stop!("active Task Reviewer is not an allowed governance role") unless reviewers.all? { |reviewer| allowed_reviewers.include?(reviewer) }
required_reviewers = reviewers_by_risk.fetch(risk_level)
stop!("active Task risk-proportional reviewers incomplete") unless (required_reviewers - reviewers).empty?
if contract["capability_claim"] == true
  stop!("capability Task baseline missing") unless nonempty_string?(contract["baseline_ref"])
elsif contract["capability_claim"] != false
  stop!("active Task capability_claim must be boolean")
end

scope = contract["allowed_paths"]
stop!("active Task allowed_paths must use the closed role map") unless scope.is_a?(Hash) && (scope.keys - %w[worker quality integration external_evidence]).empty?
scope_paths = flatten_scope(scope)
stop!("active Task write scope missing") unless nonempty_list?(scope_paths) && scope_paths.all? { |item| nonempty_string?(item) }
repo_pairs = %w[worker quality integration].flat_map do |role|
  Array(scope[role]).map { |item| [role, item] }
end
external_scope = Array(scope["external_evidence"])
stop!("active Task mixes absolute paths into repository roles") unless repo_pairs.all? { |_role, item| !Pathname.new(item).absolute? }
stop!("active Task external Evidence path must be absolute") unless external_scope.all? { |item| Pathname.new(item).absolute? }
repo_bases = repo_pairs.map { |_role, item| scope_base(item) }
stop!("active Task repository scope is not canonical") if repo_bases.any?(&:nil?)
stop!("active Task write scope overlaps historical failed Contract custody") if repo_bases.any? do |base|
  historical_failed_contract_paths.any? { |path| path_overlap?(base, path) }
end
stop!("active Task repository scope escapes root or crosses symlink") unless repo_bases.all? do |base|
  safe_under_root?(File.join(REPO_ROOT, base), REPO_ROOT)
end
stop!("active Task repository scope exceeds role-specific Phase envelope") unless repo_pairs.zip(repo_bases).all? do |(role, _item), base|
  Array(role_write_roots[role]).any? { |allowed| base == allowed || base.start_with?(allowed + File::SEPARATOR) }
end
repo_pairs.zip(repo_bases).combination(2).each do |((left_role, _left_item), left), ((right_role, _right_item), right)|
  next if left_role == right_role
  stop!("active Task cross-role write scope overlaps: #{left_role}/#{right_role}") if path_overlap?(left, right)
end
effective_immutable_paths = immutable_paths + [contract_rel]
stop!("active Task repository scope touches immutable authority or its own Contract") if repo_bases.any? do |base|
  effective_immutable_paths.any? { |immutable| base == immutable || base.start_with?(immutable + File::SEPARATOR) || immutable.start_with?(base + File::SEPARATOR) }
end
stop!("active Task external scope escapes Evidence root") unless external_scope.all? do |item|
  base = scope_base(item, absolute: true)
  next false unless base
  evidence_root = File.expand_path(active["execution_evidence_root"].to_s)
  expanded = File.expand_path(base)
  (expanded == evidence_root || expanded.start_with?(evidence_root + File::SEPARATOR)) && safe_under_root?(base, evidence_base)
end

stop!("active Task budget missing") unless contract["budget"].is_a?(Hash) && !contract["budget"].empty?
iterations = contract.dig("budget", "implementation_iterations")
stop!("active Task implementation iteration budget invalid") unless iterations.is_a?(Integer) && iterations.between?(1, 3)
stop!("active Task execution retry must be zero") unless contract.dig("budget", "execution_retries") == 0
stop!("active Task acceptance missing") unless nonempty_list?(contract["acceptance_criteria"])
stop!("active Task failure criteria missing") unless nonempty_list?(contract["failure_criteria"])
stop!("active Task Stop Conditions missing") unless nonempty_list?(contract["stop_conditions"])
stop!("active Task forbidden actions missing") unless nonempty_list?(contract["forbidden_actions"])
forbidden_text = contract["forbidden_actions"].join(" ").downcase
evidence = contract.dig("evidence", "required") || contract["required_evidence"]
stop!("active Task required Evidence missing") unless nonempty_list?(evidence)
stop!("active Task rollback missing") unless contract["rollback"].is_a?(Hash) && !contract["rollback"].empty?

contract_authority = contract["delegated_authority"]
stop!("active Task delegated authority missing") unless contract_authority.is_a?(Hash)
stop!("active Task Gate owner drift") unless contract_authority["task_gate_owner"] == "MASTER_CEO_AGENT"
stop!("routine per-Task Founder Gate re-enabled") unless contract_authority["founder_gate"] == "RESERVED_DECISIONS_ONLY"
stop!("active Task is not Phase-local") unless contract_authority["phase_local"] == true
reserved_requests = contract_authority["founder_reserved_decisions"]
stop!("active Task reserved-decision declaration missing") unless reserved_requests.is_a?(Array)
stop!("active Task declares an unknown Founder-reserved decision") unless (reserved_requests - expected_reserved).empty?
if phase_boundary.fetch("founder_reserved_risk_levels").include?(risk_level)
  stop!("critical risk acceptance was not reserved to Founder") unless reserved_requests.include?("critical_residual_risk_acceptance")
end
contract_effects = contract_authority["external_effects"]
stop!("active Task external-effect declaration missing") unless contract_effects.is_a?(Hash)
expected_effect_keys = %w[network provider secret remote production public]
stop!("active Task external-effect keys drift") unless contract_effects.keys.sort == expected_effect_keys.sort
stop!("active Task external effects must be booleans") unless contract_effects.values.all? { |value| value == true || value == false }
stop!("active Task default effect boundary drift") unless contract_effects == phase_boundary["default_external_effects"] || contract_effects.values.any?(true)
%w[network provider secret remote production public].each do |effect|
  next if contract_effects[effect] == true
  stop!("active Task does not explicitly forbid disabled effect: #{effect}") unless forbidden_text.include?(effect)
end

authorization_path = active["current_execution_authorization"]
authorization_sha = active["current_execution_authorization_sha256"]
stop!("active Task authorization path missing") unless nonempty_string?(authorization_path)
evidence_root = active["execution_evidence_root"]
stop!("active Task Evidence root must be a strict task-specific child") unless nonempty_string?(evidence_root) && File.expand_path(evidence_root) != File.expand_path(evidence_base) && safe_under_root?(evidence_root, evidence_base, must_exist: true)
historical_evidence_paths = recursive_values(truth.fetch("task_history"), "execution_evidence_root") + recursive_values(truth.fetch("task_history"), "evidence_root")
historical_evidence_paths += recursive_strings(truth.fetch("task_history")).select do |value|
  begin
    expanded = File.expand_path(value)
    base = File.expand_path(evidence_base)
    expanded == base || expanded.start_with?(base + File::SEPARATOR)
  rescue ArgumentError
    false
  end
end
current_evidence = File.expand_path(evidence_root)
historical_overlap = historical_evidence_paths.any? do |path|
  historical = File.expand_path(path.to_s)
  current_evidence == historical || current_evidence.start_with?(historical + File::SEPARATOR) || historical.start_with?(current_evidence + File::SEPARATOR)
end
stop!("active Task overlaps historical Evidence custody") if historical_overlap
if corrections_used == 1
  original_contract_bytes = git_file(active.fetch("activation_parent_commit"), contract_rel)
  stop!("corrected Contract original bytes are not committed at the activation parent") unless original_contract_bytes && Digest::SHA256.hexdigest(original_contract_bytes) == clean_room["original_contract_sha256"]
  original_contract = YAML.safe_load(original_contract_bytes, aliases: false)
  original_recovery = original_contract["clean_room_recovery"]
  stop!("bounded Contract correction original bytes are not the uncorrected Contract") unless original_recovery.is_a?(Hash) && original_recovery["bounded_contract_corrections_allowed"] == 1 && original_recovery["bounded_contract_corrections_used"] == 0 && original_recovery["original_contract_path"].nil? && original_recovery["original_contract_sha256"].nil?
  correction_invariants = %w[
    task_id phase objective mandatory_exit_capability task_kind capabilities capability_claim
    risk_level allowed_paths forbidden_actions budget claim_boundary delegated_authority
    integrated_mandatory_exit_capabilities founder_architecture_route_id
  ]
  correction_invariants.each do |field|
    stop!("bounded Contract correction changed frozen field: #{field}") unless original_contract[field] == contract[field]
  end
end
expected_attempt_keys = %w[attempt_ordinal bounded_contract_corrections_used contract_sha256 status task_id]
if rebaseline_slice
  expected_attempt_keys += %w[integrated_mandatory_exit_capabilities project_level_rebaseline_decision_sha256 project_level_rebaseline_slice_ordinal]
elsif contract_final_route_id
  expected_attempt_keys += %w[integrated_mandatory_exit_capabilities founder_final_clean_room_route_id]
elsif contract_integrated_capabilities
  expected_attempt_keys += %w[integrated_mandatory_exit_capabilities founder_architecture_route_id]
end
stop!("active Task attempt ledger schema drift") unless active_attempt.keys.sort == expected_attempt_keys.sort
stop!("active Task attempt ledger binding drift") unless active_attempt["task_id"] == current_task && active_attempt["contract_sha256"] == contract_sha && active_attempt["bounded_contract_corrections_used"] == corrections_used
if rebaseline_slice
  stop!("active rebaseline Slice attempt ledger binding drift") unless
    active_attempt["integrated_mandatory_exit_capabilities"] == contract_integrated_capabilities &&
    active_attempt["project_level_rebaseline_slice_ordinal"] == contract_rebaseline_slice_ordinal &&
    active_attempt["project_level_rebaseline_decision_sha256"] == contract_rebaseline_decision_sha
elsif contract_final_route_id
  stop!("active Task final clean-room attempt ledger binding drift") unless active_attempt["integrated_mandatory_exit_capabilities"] == contract_integrated_capabilities && active_attempt["founder_final_clean_room_route_id"] == contract_final_route_id
elsif contract_integrated_capabilities
  stop!("active Task integrated attempt ledger binding drift") unless active_attempt["integrated_mandatory_exit_capabilities"] == contract_integrated_capabilities && active_attempt["founder_architecture_route_id"] == contract_route_id
end
task_number = current_task.match(/\AAIOS-#{Regexp.escape(phase)}-(\d{3})/)[1]
stop!("active Task Evidence root is not Task-specific") unless File.basename(current_evidence).downcase.include?("#{phase.downcase}-#{task_number}")
stop!("active Task authorization must be inside exact Task Evidence custody") unless safe_under_root?(authorization_path, evidence_root, must_exist: true)
stop!("active Task authorization hash drift") unless nonempty_string?(authorization_sha) && sha256(authorization_path) == authorization_sha
authorization = JSON.parse(File.read(authorization_path))
stop!("active Task authorization record type drift") unless authorization["record_type"] == "aios_phase_delegated_task_authorization"
stop!("active Task authorization state drift") unless authorization["status"] == "ACTIVE"
stop!("active Task authorization owner drift") unless authorization["authority"] == "MASTER_CEO_AGENT"
stop!("active Task authorization delegation drift") unless authorization["delegation_model"] == "PHASE_LEVEL_FOUNDER_DELEGATION"
stop!("active Task authorization identity drift") unless authorization["task_id"] == current_task && authorization["task_contract_sha256"] == contract_sha
stop!("active Task authorization ID drift") unless active["authorization_id"].is_a?(String) && active["authorization_id"].match?(/\A[0-9a-f]{64}\z/) && authorization["authorization_id"] == active["authorization_id"]
stop!("active Task authorization replay detected") if recursive_values(truth.fetch("task_history"), "authorization_id").include?(active["authorization_id"])
stop!("active Task Goal binding drift") unless authorization["goal_canonical_sha256"] == truth.dig("goal", "observed_body_sha256")
stop!("active Task Phase binding drift") unless authorization["phase"] == phase
if rebaseline_slice
  stop!("active Task authorization rebaseline Slice binding drift") unless
    authorization["integrated_mandatory_exit_capabilities"] == contract_integrated_capabilities &&
    authorization["project_level_rebaseline_slice_ordinal"] == contract_rebaseline_slice_ordinal &&
    authorization["project_level_rebaseline_decision_sha256"] == contract_rebaseline_decision_sha &&
    !authorization.key?("founder_architecture_route_id") &&
    !authorization.key?("founder_final_clean_room_route_id")
elsif contract_final_route_id
  stop!("active Task authorization final clean-room capability binding drift") unless
    authorization["integrated_mandatory_exit_capabilities"] == contract_integrated_capabilities &&
    authorization["founder_final_clean_room_route_id"] == contract_final_route_id &&
    !authorization.key?("founder_architecture_route_id")
elsif contract_integrated_capabilities
  stop!("active Task authorization integrated capability binding drift") unless authorization["integrated_mandatory_exit_capabilities"] == contract_integrated_capabilities && authorization["founder_architecture_route_id"] == contract_route_id
else
  stop!("ordinary Task authorization cannot carry an integrated capability binding") if authorization.key?("integrated_mandatory_exit_capabilities") || authorization.key?("founder_architecture_route_id") || authorization.key?("founder_final_clean_room_route_id")
end

activation_parent_commit = active["activation_parent_commit"]
activation_parent_tree = active["activation_parent_tree"]
stop!("active Task activation parent missing") unless nonempty_string?(activation_parent_commit) && nonempty_string?(activation_parent_tree)
stop!("active Task authorization parent drift") unless authorization["parent_commit"] == activation_parent_commit && authorization["parent_tree"] == activation_parent_tree
stop!("active Task activation parent tree identity drift") unless git("rev-parse", "#{activation_parent_commit}^{tree}") == activation_parent_tree
main_branch = truth.dig("project", "canonical_branch")
main_head = git("rev-parse", "refs/heads/#{main_branch}")
stop!("active Task canonical main is not descended from activation parent") unless system("git", "-C", REPO_ROOT, "merge-base", "--is-ancestor", activation_parent_commit, main_head, out: File::NULL, err: File::NULL)
stop!("active Task activation must be one governance commit") unless git("rev-list", "--count", "#{activation_parent_commit}..#{main_head}") == "1"
activation_paths = git("diff", "--name-only", activation_parent_commit, main_head).lines.map(&:strip).reject(&:empty?).sort
expected_activation_paths = (contract_final_route_id || rebaseline_slice) ? ["docs/aios/truth/project_state.yaml"] : [contract_rel, "docs/aios/truth/project_state.yaml"].sort
stop!("active Task activation path population drift") unless activation_paths == expected_activation_paths
parent_truth_bytes = IO.popen(["git", "-C", REPO_ROOT, "show", "#{activation_parent_commit}:docs/aios/truth/project_state.yaml"], err: File::NULL, &:read)
stop!("active Task parent Truth unavailable") unless $CHILD_STATUS.success?
parent_truth = YAML.safe_load(parent_truth_bytes, aliases: false)
parent_capability_status = parent_truth.dig("mandatory_exit_capability_recovery", "capability_status")
expected_active_capability_status = Marshal.load(Marshal.dump(parent_capability_status))
if rebaseline_slice
  stop!("active rebaseline Task parent capability states are not eligible") unless
    expected_active_capability_status.is_a?(Hash) &&
    contract_integrated_capabilities.all? { |capability| expected_active_capability_status[capability] == "REBASELINED_PENDING_EXECUTION" }
  contract_integrated_capabilities.each { |capability| expected_active_capability_status[capability] = "IN_PROGRESS" }
elsif contract_final_route_id
  stop!("active final clean-room Task parent capability states are not eligible") unless
    expected_active_capability_status.is_a?(Hash) &&
    contract_integrated_capabilities.all? { |capability| expected_active_capability_status[capability] == effective_final_pending_state }
  contract_integrated_capabilities.each { |capability| expected_active_capability_status[capability] = "IN_PROGRESS" }
elsif contract_integrated_capabilities
  stop!("active integrated Task parent capability states are not eligible") unless expected_active_capability_status.is_a?(Hash) && expected_active_capability_status[contract_integrated_capabilities.first] == "RELOCATED_PENDING_INTEGRATED_TASK" && expected_active_capability_status[mandatory_exit_capability] == "MISSING"
  contract_integrated_capabilities.each { |capability| expected_active_capability_status[capability] = "IN_PROGRESS" }
else
  stop!("active Task parent mandatory Exit capability was not missing") unless expected_active_capability_status.is_a?(Hash) && expected_active_capability_status[mandatory_exit_capability] == "MISSING"
  expected_active_capability_status[mandatory_exit_capability] = "IN_PROGRESS"
end
stop!("active Task activation changed mandatory Exit capability status incorrectly") unless capability_status == expected_active_capability_status
parent_attempt_ledger = parent_truth.dig("mandatory_exit_capability_recovery", "capability_attempt_ledger")
if rebaseline_slice
  stop!("active rebaseline Task changed historical contract-attempt ledger") unless attempt_ledger == parent_attempt_ledger
  parent_rebaseline = parent_truth.dig("mandatory_exit_capability_recovery", "project_level_rebaseline")
  stop!("active rebaseline Task parent Slice attempt was already consumed") unless
    parent_rebaseline.is_a?(Hash) && parent_rebaseline.dig("slice_attempts", contract_rebaseline_slice_ordinal.to_s).nil?
  stop!("active rebaseline Task Slice attempt binding drift") unless
    rebaseline.dig("slice_attempts", contract_rebaseline_slice_ordinal.to_s) == active_attempt
elsif contract_final_route_id
  stop!("active final clean-room Task changed historical contract-attempt ledger") unless attempt_ledger == parent_attempt_ledger
  parent_attempt_key = post_revision_route ? "post_revision_final_implementation_attempt" : "final_clean_room_implementation_attempt"
  stop!("active final clean-room Task parent implementation attempt was already consumed") unless parent_truth.dig("mandatory_exit_capability_recovery", parent_attempt_key).nil?
  stop!("active final clean-room Task implementation attempt binding drift") unless effective_final_attempt == active_attempt
else
  stop!("active Task parent attempt ledger was already consumed") unless parent_attempt_ledger.is_a?(Hash) && parent_attempt_ledger[mandatory_exit_capability].nil?
  expected_active_attempt_ledger = Marshal.load(Marshal.dump(parent_attempt_ledger))
  expected_active_attempt_ledger[mandatory_exit_capability] = active_attempt
  stop!("active Task activation changed attempt ledger incorrectly") unless attempt_ledger == expected_active_attempt_ledger
end
stop!("active Task activation changed Truth outside the closed activation field set") unless truth_without_activation_fields(parent_truth) == truth_without_activation_fields(truth)
main_contract = IO.popen(["git", "-C", REPO_ROOT, "show", "#{main_head}:#{contract_rel}"], err: File::NULL, &:read)
stop!("active Task Contract is not frozen in canonical activation commit") unless $CHILD_STATUS.success? && Digest::SHA256.hexdigest(main_contract) == contract_sha

authorization_effects = authorization["external_effects"]
stop!("active Task authorization effects missing") unless authorization_effects.is_a?(Hash) && authorization_effects.keys.sort == expected_effect_keys.sort
stop!("active Task authorization effects must be booleans") unless authorization_effects.values.all? { |value| value == true || value == false }
stop!("Contract/authorization effect declaration mismatch") unless authorization_effects == contract_effects
authorization_reserved = authorization["founder_reserved_decisions"]
stop!("Contract/authorization reserved declaration mismatch") unless authorization_reserved == reserved_requests
reserved_required = authorization_effects.values.any?(true) || !authorization_reserved.empty?
stop!("Founder reserved decision flag mismatch") unless authorization["founder_reserved_decision_required"] == reserved_required

if reserved_required
  founder_path = active["founder_reserved_authorization"]
  founder_sha = active["founder_reserved_authorization_sha256"]
  stop!("Founder reserved authorization missing") unless safe_under_root?(founder_path, evidence_root, must_exist: true) && nonempty_string?(founder_sha) && sha256(founder_path) == founder_sha
  founder_decision = JSON.parse(File.read(founder_path))
  stop!("Founder reserved decision record type drift") unless founder_decision["record_type"] == "sourcelens_aios_founder_reserved_decision"
  stop!("Founder reserved decision is not approved") unless founder_decision["status"] == "APPROVED" && founder_decision["authority"] == "HUMAN_FOUNDER"
  stop!("Founder reserved decision Task binding drift") unless founder_decision["task_id"] == current_task
  stop!("Founder reserved decision authorization binding drift") unless founder_decision["authorization_id"] == active["authorization_id"]
  stop!("Founder reserved decision Contract binding drift") unless founder_decision["task_contract_sha256"] == contract_sha
  stop!("Founder reserved decision Phase binding drift") unless founder_decision["phase"] == phase
  stop!("Founder reserved decision scope drift") unless founder_decision["approved_reserved_decisions"] == authorization_reserved
  approved_effects = founder_decision["approved_external_effects"]
  stop!("Founder reserved decision effect binding drift") unless approved_effects == authorization_effects.select { |_key, enabled| enabled }
  stop!("Founder decision state mismatch") unless founder_required == true && delegation["escalation_conditions"].include?(escalation_reason)
else
  stop!("routine Founder decision re-enabled") unless founder_required == false && escalation_reason.nil? && active["founder_reserved_authorization"].nil? && active["founder_reserved_authorization_sha256"].nil?
end

stop!("phase-delegated Task must not require a nonce") unless active["execution_nonce"].nil? && active["execution_nonce_status"] == "NOT_REQUIRED_PHASE_DELEGATION"
branch = active["task_branch"]
worktree = active["task_worktree"]
resource_state = active["task_resource_state"]
stop!("active Task branch drift") unless nonempty_string?(branch) && branch.start_with?("task/")
stop!("active Task worktree outside configured root") unless safe_under_root?(worktree, worktree_root)
stop!("active Task Evidence outside configured root") unless safe_under_root?(evidence_root, evidence_base)
stop!("active Task resource state invalid") unless %w[DECLARED CREATED REVIEW].include?(resource_state)
stop!("more than one Task branch exists") unless task_branches.empty? || task_branches == [branch]
declared_worktree = worktrees.find do |entry|
  begin
    File.realpath(entry.fetch("worktree")) == File.realpath(worktree)
  rescue Errno::ENOENT
    File.expand_path(entry.fetch("worktree")) == File.expand_path(worktree)
  end
end
if resource_state == "DECLARED" && task_branches.empty?
  stop!("declared Task worktree unexpectedly exists") if declared_worktree || File.exist?(worktree)
else
  stop!("declared Task branch missing") unless task_branches == [branch]
  stop!("declared Task worktree missing") unless declared_worktree && File.directory?(worktree)
  stop!("Task worktree branch binding drift") unless declared_worktree["branch"] == "refs/heads/#{branch}"
  stop!("Task worktree path unsafe") unless safe_under_root?(worktree, worktree_root, must_exist: true)
  stop!("Task branch is not descended from activation commit") unless system("git", "-C", REPO_ROOT, "merge-base", "--is-ancestor", main_head, "refs/heads/#{branch}", out: File::NULL, err: File::NULL)
end
stop!("unexpected worktree population") unless worktrees.length == 1 + (declared_worktree ? 1 : 0)
stop!("active Task must not request routine Founder action") if next_action.match?(/FOUNDER.*(APPROV|AUTHORIZ)|REQUEST.*FOUNDER|WAIT.*FOUNDER/)

puts "Current Task authority validation passed: #{current_task} under Phase-level delegation."

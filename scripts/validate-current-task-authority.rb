#!/usr/bin/env ruby
# encoding: UTF-8

require "digest"
require "English"
require "json"
require "pathname"
require "yaml"

REPO_ROOT = File.expand_path("..", __dir__)
TRUTH_PATH = File.join(REPO_ROOT, "docs/aios/truth/project_state.yaml")
AGENT_RULES_PATH = File.join(REPO_ROOT, "AGENTS.md")

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

def exact_terminal_status?(value)
  value.is_a?(String) && (value == "TERMINAL_STOPPED" || value.start_with?("TERMINAL_STOPPED_"))
end

def git(*args)
  output = IO.popen(["git", "-C", REPO_ROOT, *args], err: File::NULL, &:read)
  stop!("git command failed: #{args.join(' ')}") unless $CHILD_STATUS.success?
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
  left == right || left.start_with?(right + File::SEPARATOR) || right.start_with?(left + File::SEPARATOR)
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
stop!("bounded Contract repair limit drift") unless anti_loop["maximum_same_task_bounded_contract_repairs"] == 1
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
stop!("mandatory Exit capability recovery is inactive") unless mandatory_recovery["status"] == "ACTIVE"
stop!("mandatory Exit capability priority drift") unless mandatory_recovery["priority_order"] == expected_exit_capabilities
stop!("historical Task immutability weakened") unless mandatory_recovery["historical_tasks_immutable"] == true
stop!("historical execution lineage reuse enabled") unless mandatory_recovery["historical_execution_lineage_reuse_allowed"] == false
stop!("clean-room recovery disabled") unless mandatory_recovery["clean_room_implementation_allowed_for_required_capability"] == true
stop!("clean-room attempt count drift") unless mandatory_recovery["clean_room_attempts_per_missing_capability"] == 1
stop!("same-Task bounded correction count drift") unless mandatory_recovery["maximum_same_task_bounded_contract_repairs"] == 1
stop!("peripheral Task selection enabled") unless mandatory_recovery["peripheral_task_selection_allowed"] == false
capability_status = mandatory_recovery["capability_status"]
stop!("mandatory Exit capability status population drift") unless capability_status.is_a?(Hash) && capability_status.keys == expected_exit_capabilities
allowed_capability_states = %w[MISSING IN_PROGRESS ACCEPTED FOUNDER_DISPOSED ARCHITECTURE_BLOCKED CONTRACT_REVIEW_BLOCKED]
stop!("mandatory Exit capability status invalid") unless capability_status.values.all? { |value| allowed_capability_states.include?(value) }
attempt_ledger = mandatory_recovery["capability_attempt_ledger"]
stop!("mandatory Exit capability attempt ledger population drift") unless attempt_ledger.is_a?(Hash) && attempt_ledger.keys == expected_exit_capabilities
founder_dispositions = mandatory_recovery["founder_dispositions"]
stop!("mandatory Exit capability Founder disposition map invalid") unless founder_dispositions.is_a?(Hash) && (founder_dispositions.keys - expected_exit_capabilities).empty?
history_entries_for_recovery = truth.fetch("task_history").values.select { |entry| entry.is_a?(Hash) }
recovery_evidence_base = truth.dig("project", "execution_evidence_root_base")
stop!("mandatory Exit capability Evidence base invalid") unless File.directory?(recovery_evidence_base) && !File.symlink?(recovery_evidence_base)

history_entries_for_recovery.each do |entry|
  match = entry["task_id"].to_s.match(/\AAIOS-P1-(\d{3})/)
  next unless match && match[1].to_i >= 35
  stop!("post-recovery Task history lacks mandatory capability identity") unless expected_exit_capabilities.include?(entry["mandatory_exit_capability"]) && entry["clean_room_attempt_ordinal"] == 1
end

capability_status.each do |capability, state|
  attempts = history_entries_for_recovery.select { |entry| entry["mandatory_exit_capability"] == capability }
  stop!("mandatory Exit capability has multiple clean-room attempts") if attempts.length > 1
  ledger = attempt_ledger[capability]
  case state
  when "MISSING"
    stop!("missing Exit capability already has an execution attempt") unless attempts.empty? && ledger.nil?
  when "IN_PROGRESS"
    stop!("in-progress Exit capability attempt ledger missing") unless attempts.empty? && ledger.is_a?(Hash) && ledger["status"] == "ACTIVE" && ledger["attempt_ordinal"] == 1
  when "ACCEPTED"
    entry = attempts.first
    accepted_statuses = %w[MASTER_TASK_GATE_ACCEPTED_COMPLETE FOUNDER_GATE_ACCEPTED_COMPLETE]
    stop!("accepted Exit capability lacks one Task Gate binding") unless entry && ledger.is_a?(Hash) && ledger["status"] == "ACCEPTED" && ledger["task_id"] == entry["task_id"] && ledger["attempt_ordinal"] == 1 && accepted_statuses.include?(entry["status"]) && entry["task_gate_result"] == "PASS"
    commit = entry["accepted_candidate_commit"]
    tree = entry["accepted_candidate_tree"]
    stop!("accepted Exit capability candidate identity invalid") unless commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/) && tree.is_a?(String) && tree.match?(/\A[0-9a-f]{40}\z/)
    stop!("accepted Exit capability candidate Git object missing") unless system("git", "-C", REPO_ROOT, "cat-file", "-e", "#{commit}^{commit}", out: File::NULL, err: File::NULL)
    stop!("accepted Exit capability candidate tree drift") unless git("rev-parse", "#{commit}^{tree}") == tree
    evidence_root = entry["execution_evidence_root"]
    stop!("accepted Exit capability Evidence root invalid") unless safe_under_root?(evidence_root, recovery_evidence_base, must_exist: true)
    contract_sha = entry["task_contract_sha256"]
    corrections_used = entry["bounded_contract_corrections_used"]
    stop!("accepted Exit capability Task Contract lineage drift") unless contract_sha.is_a?(String) && contract_sha.match?(/\A[0-9a-f]{64}\z/) && ledger["contract_sha256"] == contract_sha && corrections_used.is_a?(Integer) && corrections_used.between?(0, 1) && ledger["bounded_contract_corrections_used"] == corrections_used
    manifest = bound_json!(entry["evidence_manifest_path"], entry["evidence_manifest_sha256"], evidence_root, "accepted Exit capability Evidence Manifest")
    stop!("accepted Exit capability Evidence Manifest content drift") unless manifest == {
      "record_type" => "aios_p1_mandatory_capability_evidence_manifest",
      "status" => "FROZEN",
      "task_id" => entry["task_id"],
      "mandatory_exit_capability" => capability,
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => commit,
      "candidate_tree" => tree
    }
    %w[cto security quality].each do |role|
      review = bound_json!(entry["#{role}_review_path"], entry["#{role}_review_sha256"], evidence_root, "accepted Exit capability #{role} review")
      stop!("accepted Exit capability #{role} review content drift") unless review == {
        "record_type" => "aios_independent_task_review",
        "status" => "PASS",
        "role" => role.upcase,
        "task_id" => entry["task_id"],
        "mandatory_exit_capability" => capability,
        "task_contract_sha256" => contract_sha,
        "candidate_commit" => commit,
        "candidate_tree" => tree,
        "evidence_manifest_sha256" => entry["evidence_manifest_sha256"]
      }
    end
    gate = bound_json!(entry["task_gate_receipt_path"], entry["task_gate_receipt_sha256"], evidence_root, "accepted Exit capability Task Gate receipt")
    stop!("accepted Exit capability Task Gate receipt content drift") unless gate == {
      "record_type" => "aios_phase_delegated_task_gate_receipt",
      "status" => "ACCEPTED",
      "authority" => "MASTER_CEO_AGENT",
      "task_id" => entry["task_id"],
      "mandatory_exit_capability" => capability,
      "task_contract_sha256" => contract_sha,
      "candidate_commit" => commit,
      "candidate_tree" => tree,
      "evidence_manifest_sha256" => entry["evidence_manifest_sha256"],
      "cto_review_sha256" => entry["cto_review_sha256"],
      "security_review_sha256" => entry["security_review_sha256"],
      "quality_review_sha256" => entry["quality_review_sha256"]
    }
  when "ARCHITECTURE_BLOCKED"
    entry = attempts.first
    stop!("architecture-blocked Exit capability lacks terminal Evidence binding") unless entry && ledger.is_a?(Hash) && ledger["status"] == "ARCHITECTURE_BLOCKED" && ledger["task_id"] == entry["task_id"] && ledger["attempt_ordinal"] == 1 && exact_terminal_status?(entry["status"]) && entry["founder_escalation_required"] == true
    terminal = entry["terminal_evidence"]
    evidence_root = entry["execution_evidence_root"]
    stop!("architecture-blocked Exit capability Evidence root invalid") unless terminal.is_a?(Hash) && safe_under_root?(evidence_root, recovery_evidence_base, must_exist: true)
    manifest = bound_json!(terminal["evidence_manifest_path"], terminal["evidence_manifest_sha256"], evidence_root, "architecture-blocked Exit capability terminal manifest")
    stop!("architecture-blocked Exit capability terminal manifest content drift") unless manifest == {
      "record_type" => "aios_p1_mandatory_capability_terminal_evidence_manifest",
      "status" => entry["status"],
      "task_id" => entry["task_id"],
      "mandatory_exit_capability" => capability,
      "attempt_ordinal" => 1,
      "task_contract_sha256" => ledger["contract_sha256"],
      "bounded_contract_corrections_used" => ledger["bounded_contract_corrections_used"],
      "failure_classification" => "REAL_ARCHITECTURE_ROOT"
    }
  when "CONTRACT_REVIEW_BLOCKED"
    stop!("contract-review-blocked Exit capability cannot have an execution history entry") unless attempts.empty?
    stop!("contract-review-blocked Exit capability ledger invalid") unless ledger.is_a?(Hash) && ledger["status"] == "CONTRACT_REVIEW_BLOCKED" && ledger["attempt_ordinal"] == 1 && ledger["founder_escalation_required"] == true
    failure = bound_json!(ledger["failure_record_path"], ledger["failure_record_sha256"], recovery_evidence_base, "contract review failure record")
    stop!("contract review failure record content drift") unless failure["record_type"] == "aios_p1_mandatory_capability_contract_review_failure" && failure["status"] == "CONTRACT_REVIEW_BLOCKED" && failure["task_id"] == ledger["task_id"] && failure["mandatory_exit_capability"] == capability && failure["attempt_ordinal"] == 1 && failure["founder_escalation_required"] == true && failure["final_review_result"] != "PASS"
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
    previous_history = previous_truth.fetch("task_history")
    current_history = transition_truth.fetch("task_history")
    previous_history.each do |key, value|
      stop!("Task history is not append-only across current Truth transition: #{key}") unless current_history[key] == value
    end

    allowed_status_transitions = {
      "MISSING" => %w[MISSING IN_PROGRESS CONTRACT_REVIEW_BLOCKED FOUNDER_DISPOSED],
      "IN_PROGRESS" => %w[IN_PROGRESS ACCEPTED ARCHITECTURE_BLOCKED],
      "CONTRACT_REVIEW_BLOCKED" => %w[CONTRACT_REVIEW_BLOCKED FOUNDER_DISPOSED],
      "ARCHITECTURE_BLOCKED" => %w[ARCHITECTURE_BLOCKED FOUNDER_DISPOSED],
      "ACCEPTED" => %w[ACCEPTED],
      "FOUNDER_DISPOSED" => %w[FOUNDER_DISPOSED]
    }
    expected_exit_capabilities.each do |capability|
      previous_state = previous_recovery.dig("capability_status", capability)
      current_state = current_recovery.dig("capability_status", capability)
      stop!("mandatory Exit capability status transition invalid: #{capability}") unless allowed_status_transitions.fetch(previous_state).include?(current_state)
      previous_attempt = previous_recovery.dig("capability_attempt_ledger", capability)
      current_attempt = current_recovery.dig("capability_attempt_ledger", capability)
      if previous_attempt
        stop!("mandatory Exit capability attempt ledger was erased: #{capability}") unless current_attempt.is_a?(Hash)
        %w[task_id attempt_ordinal contract_sha256 bounded_contract_corrections_used].each do |field|
          stop!("mandatory Exit capability attempt identity changed: #{capability}/#{field}") unless current_attempt[field] == previous_attempt[field]
        end
      end
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
stop!("canonical repository identity drift") unless safe_under_root?(canonical_root, File.dirname(canonical_root), must_exist: true) && File.realpath(canonical_root) == File.realpath(git("worktree", "list", "--porcelain").lines.first.to_s.sub(/^worktree /, "").strip)
stop!("worktree root invalid") unless File.directory?(worktree_root) && !File.symlink?(worktree_root)
stop!("Evidence root base invalid") unless File.directory?(evidence_base) && !File.symlink?(evidence_base)

active = truth.fetch("active_work")
current_task = active["current_task"]
current_status = active["current_task_status"]
goal_task = truth.dig("goal", "current_task_authority")
project_status = truth.dig("project", "phase_execution_status")
stop!("phase/P1 execution status drift") if phase == "P1" && truth.dig("project", "p1_execution_status") != project_status
next_action = active["next_eligible_action"]
stop!("next eligible action missing") unless nonempty_string?(next_action)
founder_required = active["founder_decision_required"]
escalation_reason = active["escalation_reason"]
user_action = active["user_action_required"]

task_branches = git("for-each-ref", "--format=%(refname:short)", "refs/heads/task/").lines.map(&:strip).reject(&:empty?)
worktrees = worktree_records
canonical_real = File.realpath(canonical_root)
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
  stop!("NONE state status drift") unless current_status == "NONE" && project_status == "NO_CURRENT_TASK"
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
    else
      stop!("blocked mandatory capability must wait for Founder disposition") unless next_action == "WAIT_FOR_FOUNDER_MANDATORY_EXIT_CAPABILITY_DECISION"
    end
  else
    stop!("Goal control-plane state invalid")
  end
  puts "Current Task authority validation passed: NONE under Phase-level delegation."
  exit 0
end

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
stop!("active Task mandatory Exit capability is not in progress") unless capability_status[mandatory_exit_capability] == "IN_PROGRESS"
earlier_exit_capabilities = expected_exit_capabilities.take_while { |capability| capability != mandatory_exit_capability }
unclosed_earlier_capabilities = earlier_exit_capabilities.reject do |capability|
  %w[ACCEPTED FOUNDER_DISPOSED].include?(capability_status[capability])
end
stop!("active Task bypasses an earlier mandatory Exit capability") unless unclosed_earlier_capabilities.empty?
clean_room = contract["clean_room_recovery"]
stop!("active Task clean-room recovery declaration missing") unless clean_room.is_a?(Hash)
stop!("active Task reuses historical execution lineage") unless clean_room["historical_execution_lineage_reused"] == false
stop!("active Task clean-room attempt ordinal drift") unless clean_room["attempt_ordinal"] == 1
stop!("active Task bounded Contract correction limit drift") unless clean_room["bounded_contract_corrections_allowed"] == 1
corrections_used = clean_room["bounded_contract_corrections_used"]
stop!("active Task bounded Contract correction usage invalid") unless corrections_used.is_a?(Integer) && corrections_used.between?(0, 1)
if corrections_used.zero?
  stop!("uncorrected Contract must not bind original Contract bytes") unless clean_room["original_contract_path"].nil? && clean_room["original_contract_sha256"].nil?
  stop!("uncorrected Contract cannot replace a pre-existing Task Contract") unless git_file(active["activation_parent_commit"], contract_rel).nil?
else
  stop!("corrected Contract original path must be its canonical tracked path") unless clean_room["original_contract_path"] == contract_rel
  stop!("corrected Contract original hash invalid") unless clean_room["original_contract_sha256"].is_a?(String) && clean_room["original_contract_sha256"].match?(/\A[0-9a-f]{64}\z/)
end
active_attempt = attempt_ledger[mandatory_exit_capability]
prior_clean_room_attempts = history_entries.select { |entry| entry["mandatory_exit_capability"] == mandatory_exit_capability }
stop!("mandatory Exit capability clean-room attempt already consumed") unless prior_clean_room_attempts.empty?
stop!("active Task read context must be canonical repository-relative paths") unless contract["read_context"].all? do |path|
  nonempty_string?(path) && !Pathname.new(path).absolute? && Pathname.new(path).cleanpath.to_s == path &&
    safe_under_root?(File.join(REPO_ROOT, path), REPO_ROOT, must_exist: true)
end
terminal_contract_paths = history_entries.select { |entry| terminal_history_ids.include?(entry["task_id"]) }.map { |entry| entry["contract"] }.compact
stop!("active Task read context references terminal or unaccepted Task assets") unless (contract["read_context"] & terminal_contract_paths).empty?
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
  ]
  correction_invariants.each do |field|
    stop!("bounded Contract correction changed frozen field: #{field}") unless original_contract[field] == contract[field]
  end
end
stop!("active Task attempt ledger schema drift") unless active_attempt.keys.sort == %w[attempt_ordinal bounded_contract_corrections_used contract_sha256 status task_id].sort
stop!("active Task attempt ledger binding drift") unless active_attempt["task_id"] == current_task && active_attempt["contract_sha256"] == contract_sha && active_attempt["bounded_contract_corrections_used"] == corrections_used
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
stop!("active Task activation path population drift") unless activation_paths == [contract_rel, "docs/aios/truth/project_state.yaml"].sort
parent_truth_bytes = IO.popen(["git", "-C", REPO_ROOT, "show", "#{activation_parent_commit}:docs/aios/truth/project_state.yaml"], err: File::NULL, &:read)
stop!("active Task parent Truth unavailable") unless $CHILD_STATUS.success?
parent_truth = YAML.safe_load(parent_truth_bytes, aliases: false)
parent_capability_status = parent_truth.dig("mandatory_exit_capability_recovery", "capability_status")
expected_active_capability_status = Marshal.load(Marshal.dump(parent_capability_status))
stop!("active Task parent mandatory Exit capability was not missing") unless expected_active_capability_status.is_a?(Hash) && expected_active_capability_status[mandatory_exit_capability] == "MISSING"
expected_active_capability_status[mandatory_exit_capability] = "IN_PROGRESS"
stop!("active Task activation changed mandatory Exit capability status incorrectly") unless capability_status == expected_active_capability_status
parent_attempt_ledger = parent_truth.dig("mandatory_exit_capability_recovery", "capability_attempt_ledger")
stop!("active Task parent attempt ledger was already consumed") unless parent_attempt_ledger.is_a?(Hash) && parent_attempt_ledger[mandatory_exit_capability].nil?
expected_active_attempt_ledger = Marshal.load(Marshal.dump(parent_attempt_ledger))
expected_active_attempt_ledger[mandatory_exit_capability] = active_attempt
stop!("active Task activation changed attempt ledger incorrectly") unless attempt_ledger == expected_active_attempt_ledger
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

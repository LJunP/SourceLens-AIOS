#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRUTH_PATH="${ROOT_DIR}/docs/aios/truth/project_state.yaml"

fail() {
  echo "P1 SAFETY BOUNDARY FAIL: $*" >&2
  exit 1
}

check_current_p1_route() {
  local truth_path="$1"
  ruby -ryaml -rdigest -rpathname -e '
    def stop!(message)
      abort(message)
    end

    def mapping!(value, label)
      stop!("#{label} missing or not a mapping") unless value.is_a?(Hash)
      value
    end

    def nonempty_string!(value, label)
      stop!("#{label} missing or empty") unless value.is_a?(String) && !value.empty?
      value
    end

    def positive_integer!(value, label)
      stop!("#{label} must be a positive integer") unless value.is_a?(Integer) && value.positive?
      value
    end

    def sha256!(value, label)
      stop!("#{label} must be lowercase SHA-256") unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
      value
    end

    def effect_map!(value, label)
      effects = mapping!(value, label)
      expected = %w[network provider secret remote production public]
      stop!("#{label} keys drifted") unless effects.keys.sort == expected.sort
      expected.each { |key| stop!("#{label}.#{key} must be false") unless effects[key] == false }
      effects
    end

    def safe_relative_path!(value, label)
      path = Pathname.new(nonempty_string!(value, label))
      stop!("#{label} must be repository-relative") if path.absolute?
      parts = path.each_filename.to_a
      stop!("#{label} contains unsafe traversal") if parts.empty? || parts.any? { |part| part == ".." || part.empty? }
      path.cleanpath
    end

    def nullable_binding!(value, label)
      binding = mapping!(value, label)
      expected = %w[path sha256 byte_length]
      stop!("#{label} keys drifted") unless binding.keys.sort == expected.sort
      expected.each { |key| stop!("#{label}.#{key} must be null while no Task is active") unless binding[key].nil? }
    end

    def binding!(value, label)
      binding = mapping!(value, label)
      expected = %w[path sha256 byte_length]
      stop!("#{label} keys drifted") unless binding.keys.sort == expected.sort
      nonempty_string!(binding["path"], "#{label}.path")
      sha256!(binding["sha256"], "#{label}.sha256")
      positive_integer!(binding["byte_length"], "#{label}.byte_length")
      binding
    end

    def validate_bound_contract!(repo_root, binding, current_task)
      relative = safe_relative_path!(binding["path"], "active Task Contract path")
      candidate = repo_root.join(relative).cleanpath
      stop!("active Task Contract missing or symlinked") unless candidate.file? && !candidate.symlink?
      real_candidate = candidate.realpath
      stop!("active Task Contract escaped repository") unless real_candidate.to_s.start_with?(repo_root.to_s + File::SEPARATOR)
      bytes = File.binread(real_candidate)
      stop!("active Task Contract byte length drift") unless bytes.bytesize == binding["byte_length"]
      stop!("active Task Contract hash drift") unless Digest::SHA256.hexdigest(bytes) == binding["sha256"]
      contract = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
      mapping!(contract, "active Task Contract")
      stop!("active Task Contract task identity drift") unless contract["task_id"] == current_task
      stop!("active Task Contract phase drift") unless contract["phase"] == "P1"
      %w[objective why_now owner_role worker_role acceptance_criteria required_evidence stop_conditions forbidden_actions].each do |key|
        value = contract[key]
        present = value.is_a?(String) ? !value.empty? : value.respond_to?(:empty?) ? !value.empty? : !value.nil?
        stop!("active Task Contract missing #{key}") unless present
      end
      contract
    rescue Psych::Exception
      stop!("active Task Contract YAML invalid")
    end

    truth_path = Pathname.new(ARGV.fetch(0))
    stop!("Truth missing or symlinked") unless truth_path.file? && !truth_path.symlink?
    repo_root = truth_path.realpath.dirname.dirname.dirname.dirname
    truth = YAML.safe_load(truth_path.read, permitted_classes: [], permitted_symbols: [], aliases: false)
    mapping!(truth, "Truth")

    project = mapping!(truth["project"], "project")
    stop!("current phase must remain P1") unless project["current_phase"] == "P1"
    stop!("P0 must remain complete") unless project["p0_status"] == "COMPLETE"
    stop!("P1 entry must be authorized") unless project["p1_entry_status"] == "AUTHORIZED"

    route = mapping!(truth["current_phase_route"], "current_phase_route")
    nonempty_string!(route["route_id"], "current_phase_route.route_id")
    stop!("route phase drift") unless route["phase"] == "P1" && route["phase_entry_status"] == "AUTHORIZED"
    route_status = nonempty_string!(route["status"], "current_phase_route.status")
    allowed_route_statuses = %w[AUTHORIZED_READY ACTIVE]
    stop!("current_phase_route.status is outside the executable lifecycle") unless allowed_route_statuses.include?(route_status)
    decision_packet = binding!(route["decision_packet"], "current_phase_route.decision_packet")
    stop!("decision packet path missing") if decision_packet["path"].empty?
    activation_parent = mapping!(route["activation_parent"], "current_phase_route.activation_parent")
    %w[commit tree].each do |key|
      value = activation_parent[key]
      stop!("activation_parent.#{key} invalid") unless value.is_a?(String) && value.match?(/\A[0-9a-f]{40,64}\z/)
    end
    exit_gate = mapping!(route["p1_exit_gate"], "current_phase_route.p1_exit_gate")
    stop!("P1 Exit Gate source drift") unless exit_gate["source"] == "docs/aios/EVALUATION_PROTOCOL.md"
    stop!("P1 Exit Gate was changed by route activation") unless exit_gate["changed"] == false

    envelope = mapping!(route["envelope"], "current_phase_route.envelope")
    %w[max_engineering_tasks max_engineering_hours max_calendar_days].each do |key|
      positive_integer!(envelope[key], "current_phase_route.envelope.#{key}")
    end
    single_resource_limits = {
      "max_active_tasks" => 1,
      "max_task_branches" => 1,
      "max_task_worktrees" => 1,
      "max_active_candidates" => 1,
      "max_contract_corrections_per_task" => 1,
      "max_same_task_repairs" => 1
    }
    single_resource_limits.each do |key, expected|
      stop!("P1 route envelope #{key} drift") unless envelope[key] == expected
    end
    effect_map!(envelope["external_effects"], "current_phase_route.envelope.external_effects")
    stop!("P2 entry was authorized inside P1") unless envelope["p2_entry_authorized"] == false
    stop!("P3 entry was authorized inside P1") unless envelope["p3_entry_authorized"] == false

    accepted_inputs = mapping!(route["accepted_inputs"], "current_phase_route.accepted_inputs")
    stop!("P1 route has no accepted inputs") if accepted_inputs.empty?
    accepted_inputs.each do |input_id, input|
      nonempty_string!(input_id, "accepted input id")
      binding = mapping!(input, "accepted input #{input_id}")
      nonempty_string!(binding["task_id"], "accepted input #{input_id}.task_id")
      nonempty_string!(binding["status"], "accepted input #{input_id}.status")
      sha256!(binding["task_contract_sha256"], "accepted input #{input_id}.task_contract_sha256")
    end

    first_task = mapping!(route["first_task"], "current_phase_route.first_task")
    first_task_id = nonempty_string!(first_task["task_id"], "current_phase_route.first_task.task_id")
    stop!("first Task phase identity invalid") unless first_task_id.start_with?("AIOS-P1-")
    safe_relative_path!(first_task["contract_path"], "current_phase_route.first_task.contract_path")
    stop!("first Task contract path is outside current Task contracts") unless first_task["contract_path"].start_with?("docs/aios/tasks/")
    positive_integer!(first_task["max_engineering_hours"], "first Task engineering budget")
    positive_integer!(first_task["max_calendar_days"], "first Task calendar budget")
    positive_integer!(first_task["max_implementation_iterations"], "first Task implementation iterations")
    stop!("first Task candidate count must be one") unless first_task["max_candidates"] == 1
    stop!("first Task engineering budget exceeds route envelope") unless
      first_task["max_engineering_hours"] <= envelope["max_engineering_hours"]
    stop!("first Task calendar budget exceeds route envelope") unless
      first_task["max_calendar_days"] <= envelope["max_calendar_days"]
    stop!("first Task implementation iterations exceed route repair allowance") unless
      first_task["max_implementation_iterations"] <= envelope["max_same_task_repairs"] + 1
    input_ids = first_task["accepted_input_ids"]
    stop!("first Task accepted inputs missing") unless input_ids.is_a?(Array) && !input_ids.empty? && input_ids.uniq.length == input_ids.length
    stop!("first Task references an unaccepted input") unless input_ids.all? { |input_id| accepted_inputs.key?(input_id) }
    nonempty_string!(first_task["claim_boundary"], "first Task claim boundary")

    phase_boundary = mapping!(truth["phase_boundary"], "phase_boundary")
    stop!("phase boundary drift") unless phase_boundary["phase"] == "P1"
    task_kinds = phase_boundary["allowed_task_kinds"]
    stop!("P1 allowed task kinds invalid") unless task_kinds.is_a?(Array) && !task_kinds.empty? && task_kinds.all? { |kind| kind.is_a?(String) && kind.start_with?("EVALUATION_FOUNDATION_") }
    capabilities = phase_boundary["allowed_capabilities"]
    stop!("P1 allowed capabilities missing") unless capabilities.is_a?(Array) && !capabilities.empty?
    forbidden_capabilities = %w[
      P2_REPOSITORY_INTELLIGENCE_CAPABILITY_CLAIM P3_SINGLE_AGENT_RUNTIME AGENT_SHELL
      MODEL_INITIATED_CANONICAL_WRITE PLATFORM_IDENTITY SUPERVISOR ROOT_CUSTODY STRONG_ISOLATION
      MULTI_AGENT_RUNTIME
    ]
    stop!("P1 phase boundary admits a deferred capability") unless (capabilities & forbidden_capabilities).empty?
    deferred = phase_boundary["deferred_capabilities"]
    stop!("P1 deferred capability set incomplete") unless deferred.is_a?(Array) && (forbidden_capabilities - deferred).empty?
    effect_map!(phase_boundary["default_external_effects"], "phase_boundary.default_external_effects")

    role_roots = mapping!(phase_boundary["role_write_roots"], "phase_boundary.role_write_roots")
    role_roots.each do |role, roots|
      next if roots.is_a?(String)
      stop!("phase boundary write roots invalid for #{role}") unless roots.is_a?(Array)
      roots.each { |path| safe_relative_path!(path, "phase boundary write root #{role}") }
    end

    active = mapping!(truth["active_work"], "active_work")
    effect_map!(active["external_effects"], "active_work.external_effects")
    current_task = active["current_task"]
    goal_task = truth.dig("goal", "current_task_authority")

    if current_task == "NONE"
      initial_ready = route_status == "AUTHORIZED_READY"
      between_tasks = route_status == "ACTIVE"
      stop!("Task NONE requires either initial route-ready or between-Task Phase-active lifecycle") unless
        initial_ready || between_tasks
      if initial_ready
        stop!("initial Task NONE project projection is not route-ready") unless
          project["phase_execution_status"] == "AUTHORIZED_READY" &&
          project["p1_execution_status"] == "AUTHORIZED_READY"
        stop!("initial Task NONE requires an eligible first Task") unless
          first_task["status"] == "ELIGIBLE_NOT_ACTIVATED"
      else
        allowed_project_active_statuses = %w[ACTIVE EXECUTING]
        stop!("between-Task NONE requires active project execution") unless
          allowed_project_active_statuses.include?(project["phase_execution_status"]) &&
          allowed_project_active_statuses.include?(project["p1_execution_status"])
        stop!("between-Task NONE cannot leave first Task active") if first_task["status"] == "ACTIVE"
      end
      stop!("goal current Task authority drift") unless goal_task == "NONE"
      stop!("active_work current_task_status drift") unless active["current_task_status"] == "NONE"
      nullable_binding!(active["current_task_contract"], "active_work.current_task_contract")
      nullable_binding!(active["authority_record"], "active_work.authority_record")
      %w[task_branch task_worktree execution_evidence_root].each do |key|
        stop!("active_work.#{key} must be null while no Task is active") unless active[key].nil?
      end
      expected_resource_state = initial_ready ? "NOT_CREATED_ROUTE_READY" : "NONE_PHASE_ACTIVE"
      stop!("Task NONE resource state drift") unless active["task_resource_state"] == expected_resource_state
      empty_budget = mapping!(active["budget"], "active_work.budget")
      expected_budget_keys = %w[engineering_hours calendar_days implementation_iterations candidates]
      stop!("active_work.budget keys drifted while no Task is active") unless empty_budget.keys.sort == expected_budget_keys.sort
      expected_budget_keys.each do |key|
        stop!("active_work.budget.#{key} must be null while no Task is active") unless empty_budget[key].nil?
      end
      empty_roles = mapping!(active["roles"], "active_work.roles")
      expected_role_keys = %w[owner worker independent_reviewers]
      stop!("active_work.roles keys drifted while no Task is active") unless empty_roles.keys.sort == expected_role_keys.sort
      %w[owner worker].each do |key|
        stop!("active_work.roles.#{key} must be null while no Task is active") unless empty_roles[key].nil?
      end
      stop!("active_work.roles.independent_reviewers must be empty while no Task is active") unless empty_roles["independent_reviewers"] == []
      stop!("active_work.allowlisted_paths must be empty while no Task is active") unless active["allowlisted_paths"] == []
      stop!("Task NONE state unexpectedly requires Founder decision") unless active["founder_decision_required"] == false
      nonempty_string!(active["next_eligible_action"], "active_work.next_eligible_action")
      stop!("Task NONE next action drift") unless active["next_eligible_action"] == route["next_eligible_action"]
    else
      current_task = nonempty_string!(current_task, "active_work.current_task")
      stop!("active Task requires route ACTIVE") unless route_status == "ACTIVE"
      allowed_project_active_statuses = %w[ACTIVE EXECUTING]
      stop!("active Task requires active project execution status") unless
        allowed_project_active_statuses.include?(project["phase_execution_status"]) &&
        allowed_project_active_statuses.include?(project["p1_execution_status"])
      stop!("goal/current Task identity drift") unless goal_task == current_task
      nonempty_string!(active["current_task_status"], "active_work.current_task_status")
      contract_binding = binding!(active["current_task_contract"], "active_work.current_task_contract")
      binding!(active["authority_record"], "active_work.authority_record")
      validate_bound_contract!(repo_root, contract_binding, current_task)
      %w[task_branch task_worktree execution_evidence_root].each do |key|
        nonempty_string!(active[key], "active_work.#{key}")
      end
      paths = active["allowlisted_paths"]
      stop!("active Task allowlisted paths missing") unless paths.is_a?(Array) && !paths.empty? && paths.uniq.length == paths.length
      paths.each { |path| safe_relative_path!(path, "active Task allowlisted path") }
      active_budget = mapping!(active["budget"], "active_work.budget")
      expected_budget_keys = %w[engineering_hours calendar_days implementation_iterations candidates]
      stop!("active_work.budget keys drifted") unless active_budget.keys.sort == expected_budget_keys.sort
      expected_budget_keys.each { |key| positive_integer!(active_budget[key], "active_work.budget.#{key}") }
      stop!("active Task engineering budget exceeds route envelope") unless
        active_budget["engineering_hours"] <= envelope["max_engineering_hours"]
      stop!("active Task calendar budget exceeds route envelope") unless
        active_budget["calendar_days"] <= envelope["max_calendar_days"]
      stop!("active Task implementation iterations exceed route repair allowance") unless
        active_budget["implementation_iterations"] <= envelope["max_same_task_repairs"] + 1
      stop!("active Task candidate budget exceeds route concurrency allowance") unless
        active_budget["candidates"] <= envelope["max_active_candidates"]
      if current_task == first_task_id
        stop!("activated first Task engineering budget exceeds its declared bound") unless
          active_budget["engineering_hours"] <= first_task["max_engineering_hours"]
        stop!("activated first Task calendar budget exceeds its declared bound") unless
          active_budget["calendar_days"] <= first_task["max_calendar_days"]
        stop!("activated first Task implementation budget exceeds its declared bound") unless
          active_budget["implementation_iterations"] <= first_task["max_implementation_iterations"]
        stop!("activated first Task candidate budget exceeds its declared bound") unless
          active_budget["candidates"] <= first_task["max_candidates"]
      end
      mapping!(active["roles"], "active_work.roles")
      stop!("active Task unexpectedly requires Founder decision") unless active["founder_decision_required"] == false
    end
  ' "$truth_path" || fail "current P1 route safety envelope drift"
}

command -v ruby >/dev/null 2>&1 || fail "ruby is required"
command -v git >/dev/null 2>&1 || fail "git is required"

if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == "--check-current-p1-route" ]] || fail "unsupported arguments"
  check_current_p1_route "$2"
  echo "Current P1 route safety validation passed."
  exit 0
fi

[[ -f "$TRUTH_PATH" && ! -L "$TRUTH_PATH" ]] || fail "canonical Truth missing, non-regular, or symlinked"

tracked_audit_paths="$(git -C "$ROOT_DIR" ls-files | grep -E '(^|/)\.sourcelens-audit(/|$)' || true)"
[[ -z "$tracked_audit_paths" ]] || fail "external Evidence material leaked into Git: ${tracked_audit_paths}"

ruby "${ROOT_DIR}/scripts/validate-current-task-authority.rb"
check_current_p1_route "$TRUTH_PATH"

echo "P1 basic safety boundary validation passed (current cooperative-local route only)."
